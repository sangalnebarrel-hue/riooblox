--!nocheck
-- DOG SHELTER end to end: lune run tests/shelter_e2e.luau
-- Runs the REAL economy modules (Economy.ShelterService, ShelterRules, Transactions, Engine, Rules, RecordStats and the
-- feature registry with Features/Equipment) through tests/lib/economy_env.luau on a fake in-memory DataStore:
--   a profile with sellable, locked, favorite, kennel, working, displayed and event dogs (one wearing an artifact)
--   -> List -> Quote -> Sell -> coins, stats, LastSaleAt, the artifact back in the bag, the dog gone
--   -> leave + flush -> a NEW Transactions/Engine (another server) loads the saved record: dog still gone, coins kept.
-- Also: an idempotent Sell retry (transaction receipt), every protection, hold-to-confirm for rank >= 5 and event dogs,
-- quote expiry on the SERVER clock, the visit rule (radius + shelter hall), the unready / rate-limited messages, one
-- broken dog never breaks the list, the window's pure model (ShelterModel) and the dictionary (Localization.Shelter).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local NOW = 1792000000 -- 2026-10-15
L.Time = NOW

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local r = {}
	for k, x in pairs(v) do
		r[k] = copy(x)
	end
	return r
end

------------------------------------------------------------------------------------------------
-- World: the Welcome Hub's DogShelter.SellAnchor where the place has it
------------------------------------------------------------------------------------------------
local ANCHOR = CFrame.new(121.85, 3.6, 204.95)
local anchor = {
	Name = "SellAnchor",
	CFrame = ANCHOR,
	Position = ANCHOR.Position,
	IsA = function(_, class)
		return class == "BasePart" or class == "Part" or class == "Instance"
	end,
}
local function node(children)
	return {
		FindFirstChild = function(_, name)
			return children[name]
		end,
	}
end
local shelterAnchor = anchor
local district = node({ ["32_WelcomeHub"] = node({ DogShelter = {
	FindFirstChild = function(_, name)
		if name == "SellAnchor" then
			return shelterAnchor
		end
		return nil
	end,
} }) })
L.Workspace = setmetatable({
	FindFirstChild = function(_, name)
		if name == "DOGROTS_District" then
			return district
		end
		return nil
	end,
	GetServerTimeNow = function()
		return L.Time
	end,
}, { __index = function() return nil end })
-- ServerLuck builds a live Folder on load; the engine only reads its rank multipliers.
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end }

-- A player whose character stands `offset` studs from the reception anchor (anchor object space).
local function newPlayer(uid)
	local attrs = {}
	local pl = { UserId = uid, Name = "Tester" .. uid, DisplayName = "Tester" .. uid, Attributes = attrs }
	local root = { Name = "HumanoidRootPart", Position = ANCHOR.Position, IsA = function(_, c) return c == "BasePart" end }
	local humanoid = { Health = 100 }
	pl.Root, pl.Humanoid = root, humanoid
	pl.Character = {
		FindFirstChild = function(_, name)
			if name == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
		FindFirstChildOfClass = function(_, class)
			if class == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	function pl:GetAttribute(k)
		return attrs[k]
	end
	function pl:SetAttribute(k, v)
		attrs[k] = v
	end
	function pl:Stand(x, y, z)
		root.Position = (ANCHOR * CFrame.new(x, y, z)).Position
	end
	pl:Stand(-4, 0, 0) -- at the desk side of the reception
	return pl
end

------------------------------------------------------------------------------------------------
-- A fake DataStore (UpdateAsync semantics: the transform sees a copy, nil = no write) and one server
------------------------------------------------------------------------------------------------
local function newStore()
	local store = { Data = {}, Reads = 0, Updates = 0 }
	function store:Read(k)
		self.Reads += 1
		return copy(self.Data[k])
	end
	function store:Update(k, fn)
		self.Updates += 1
		local v = fn(copy(self.Data[k]))
		if v ~= nil then
			self.Data[k] = copy(v)
		end
		return copy(v)
	end
	return store
end

local guidCount = 0
local function guid()
	guidCount += 1
	return string.format("%032x", guidCount)
end
local function clock()
	return L.Time
end

local Tx = L.Require("ServerScriptService.Economy.Transactions")
local Engine = L.Require("ServerScriptService.Economy.Engine")
local R = L.Require("ServerScriptService.Economy.Rules")
local D = L.Require("ServerScriptService.Economy.DogDefinitions")
local SRules = L.Require("ServerScriptService.Economy.ShelterRules")
local Config = L.Require("ReplicatedStorage.DogEconomy.ShelterConfig")

-- One game server: its own Transactions + Engine (session) on the shared store, and the Runtime surface the
-- shelter uses (Ready / Allow / Refresh / Tx / Engine). It becomes Economy.Runtime for ShelterService.
local function server(store, session)
	local tx = Tx.new(store, clock, guid, { LockWait = 0 })
	local connected = {}
	local engine = Engine.new(tx, {
		Now = clock,
		Guid = guid,
		Random = function()
			return 0.5
		end,
		Session = session,
		Connected = function(id)
			return connected[id] == true
		end,
		AssetReady = function()
			return true
		end,
	})
	local rt = { Tx = tx, Engine = engine, Loaded = {}, Views = {}, Refreshes = 0, Throttle = false, Connected = connected, Store = store }
	function rt.Ready(player)
		return rt.Loaded[player.UserId] == true
	end
	function rt.Allow(_player, _cost)
		return not rt.Throttle
	end
	function rt.Refresh(_player)
		rt.Refreshes += 1
	end
	function rt.Join(player)
		connected[player.UserId] = true
		local ok, result = engine:Join(player.UserId)
		assert(ok, "join failed: " .. tostring(result))
		rt.Loaded[player.UserId] = true
	end
	function rt.Leave(player)
		connected[player.UserId] = nil
		rt.Loaded[player.UserId] = nil
		local ok, result = engine:Leave(player.UserId)
		assert(ok, "leave failed: " .. tostring(result))
		local saved, note = tx:FlushProfile(player.UserId)
		assert(saved, "flush failed: " .. tostring(note))
		assert(tx:UnloadProfile(player.UserId), "unload failed")
	end
	function rt.Profile(uid)
		return tx.Cache["p:" .. uid]
	end
	-- Runs fn(p) in a profile transaction (what the game's own actions do).
	function rt.Edit(uid, fn)
		local ok, result = tx:Run({ "p:" .. uid }, function(v)
			local p = v["p:" .. uid]
			fn(p)
			R.Validate(p)
			return true
		end)
		assert(ok, "edit failed: " .. tostring(result))
	end
	L.Overrides["ServerScriptService/Economy/Runtime"] = rt
	return rt
end

local Shelter = L.Require("ServerScriptService.Economy.ShelterService")
local function call(player, action, args)
	local ok, a, b = pcall(Shelter.Request, player, action, args)
	if not ok then
		return false, a -- what CommunityServices' safe() turns an error into
	end
	return a, b
end

-- The dogs of the test profile: uid -> {DogId, fields}
local DOGS = {
	free1 = { "Breadog" },
	free2 = { "Sausagedog", Variant = "Golden", Mastery = 50, AscensionLevel = 1 },
	king = { "KingCorgi" }, -- wears an artifact
	cerb = { "Cerberdog" }, -- rank 5: hold to confirm
	pup = { "HW_PumpkinPup" }, -- event dog: hold to confirm
	locked = { "Potatodog", Locked = true },
	fav = { "Breadog", Favorite = true },
	kennel = { "Breadog", AssignedSlot = "DigSlot_1", State = "Digging" },
	walk = { "Sausagedog", State = "Walking" },
	shown = { "Potatodog" },
}
local function seed(rt, uid)
	rt.Edit(uid, function(p)
		p.Upgrades.DogStorage = 2
		for dogUid, spec in pairs(DOGS) do
			local d = R.Mint(p, spec[1], dogUid, { Minted = 0 }, L.Time, function()
				return 0.5
			end, "Test", spec.Variant or "Normal", true)
			for k, v in pairs(spec) do
				if type(k) == "string" then
					d[k] = v
				end
			end
		end
		p.DisplayDogs = { ["1"] = "shown" }
		local eq = p.Equipment
		eq.Artifacts.art1 = { Uid = "art1", Id = "GoldBone", Rarity = "Rare", Roll = 0.5, DogUid = "king", Slot = 1, CreatedAt = L.Time, Origin = "Test" }
	end)
end
local function rowOf(list, uid)
	for _, row in ipairs(list.Rows) do
		if row.Uid == uid then
			return row
		end
	end
	return nil
end
local function priceOf(uid, p)
	return SRules.Price(p.Dogs[uid], D, R.Bonus)
end

------------------------------------------------------------------------------------------------
-- The full path
------------------------------------------------------------------------------------------------
local store = newStore()
local rt = server(store, "SERVER-A")
local me = newPlayer(1)
rt.Join(me)
seed(rt, 1)

test("List: every dog, sellable first and cheapest first, protections with their codes", function()
	local ok, list = call(me, "List", {})
	truthy(ok, "list ok: " .. tostring(list))
	eq(#list.Rows, 10, "every dog listed")
	eq(list.Count, 10, "count")
	eq(list.TTL, Config.QuoteTTL, "TTL sent with the list")
	local seenProtected = false
	for i, row in ipairs(list.Rows) do
		if not row.Eligible then
			seenProtected = true
		else
			truthy(not seenProtected, "sellable rows first")
		end
		if i > 1 and row.Eligible and list.Rows[i - 1].Eligible then
			truthy(list.Rows[i - 1].Price <= row.Price, "cheapest first")
		end
	end
	local expected = { locked = "Locked", fav = "Favorite", kennel = "Kennel", walk = "Working", shown = "Display" }
	for uid, code in pairs(expected) do
		local row = rowOf(list, uid)
		eq(row.Eligible, false, uid .. " protected")
		eq(row.Protection, code, uid .. " code")
		eq(row.Reason, SRules.Messages[code], uid .. " reason")
	end
	for _, uid in ipairs({ "free1", "free2", "king", "cerb", "pup" }) do
		eq(rowOf(list, uid).Eligible, true, uid .. " sellable")
	end
	eq(list.Sellable, 5, "sellable count")
	eq(rowOf(list, "cerb").NeedsHold, true, "rank 5 needs a hold")
	eq(rowOf(list, "pup").NeedsHold, true, "event dog needs a hold")
	eq(rowOf(list, "pup").Event, true, "event flag")
	eq(rowOf(list, "free1").NeedsHold, false, "common dog: no hold")
	eq(rowOf(list, "king").NeedsHold, false, "rank 4: no hold")
end)

test("price breakdown: base x 25% x bonus (variant + mastery + ascension)", function()
	local _, list = call(me, "List", {})
	local row = rowOf(list, "free2")
	local b = row.Breakdown
	eq(b.Base, D.Sausagedog.BasePrice, "catalog value")
	eq(b.Rate, 0.25, "shelter rate")
	truthy(math.abs(b.Variant - 0.30) < 1e-9, "golden +30%")
	truthy(math.abs(b.Ascension - 0.03) < 1e-9, "ascension 1 +3%")
	truthy(math.abs(b.Mastery - 50 * 0.0015) < 1e-9, "mastery 50 +7.5%")
	truthy(math.abs(b.Bonus - 1.405) < 1e-9, "bonus x1.405")
	eq(row.Price, math.floor(D.Sausagedog.BasePrice * 0.25 * 1.405), "price")
	eq(b.Price, row.Price, "breakdown price = row price")
end)

local soldPrice, cashBefore, lifetimeBefore
test("Quote -> Sell: coins, stats, LastSaleAt, the dog gone, its artifact back in the bag", function()
	local p0 = rt.Profile(1)
	cashBefore = p0.Cash
	lifetimeBefore = p0.Lifetime and p0.Lifetime.TotalCoinsEarned or 0
	eq(p0.Equipment.Artifacts.art1.DogUid, "king", "artifact worn before the sale")
	local ok, q = call(me, "Quote", { Uid = "king" })
	truthy(ok, "quote ok: " .. tostring(q))
	eq(#q.Token, 32, "token")
	eq(q.TTL, Config.QuoteTTL, "TTL")
	eq(q.Expires, L.Time + Config.QuoteTTL, "server expiry")
	eq(q.Fingerprint, nil, "fingerprint stays on the server")
	eq(q.Price, priceOf("king", p0), "quoted price")
	soldPrice = q.Price
	local refreshes = rt.Refreshes
	local sold, result = call(me, "Sell", { Token = q.Token })
	truthy(sold, "sell ok: " .. tostring(result))
	eq(result.Cash, soldPrice, "paid")
	eq(result.Uid, "king", "uid")
	truthy(string.find(result.Message, "found a new home", 1, true), "message")
	local p = rt.Profile(1)
	eq(p.Dogs.king, nil, "dog gone")
	eq(p.Cash, cashBefore + soldPrice, "coins")
	eq(result.Balance, p.Cash, "balance in the reply")
	eq(p.Lifetime.TotalCoinsEarned, lifetimeBefore + soldPrice, "lifetime coins")
	eq(p.Stats.TotalSellValue, soldPrice, "Stats.Sale")
	eq(p.Stats.BiggestSale, soldPrice, "biggest sale")
	eq(p.LastSaleAt, L.Time, "LastSaleAt (tutorial sale step)")
	truthy(p.Equipment.Artifacts.art1 ~= nil, "artifact kept")
	eq(p.Equipment.Artifacts.art1.DogUid, nil, "artifact released (no dangling DogUid)")
	eq(p.Equipment.Artifacts.art1.Slot, nil, "artifact slot released")
	eq(rt.Refreshes, refreshes + 1, "projection refreshed")
	eq(me:GetAttribute("LastShelterSaleAt"), L.Time, "LastShelterSaleAt attribute")
	eq(Shelter.Quotes[1], nil, "quote consumed")
	truthy(rt.Tx.Dirty["p:1"], "profile dirty until the next save")
	-- The List no longer shows it.
	local _, list = call(me, "List", {})
	eq(rowOf(list, "king"), nil, "not listed any more")
	eq(#list.Rows, 9, "nine dogs left")
	-- The same token again (a lost reply retried): answered from the receipt, never paid twice.
	local again, retry = call(me, "Sell", { Token = q.Token })
	truthy(again, "retry answered: " .. tostring(retry))
	eq(retry.Cash, soldPrice, "same reply")
	eq(rt.Profile(1).Cash, cashBefore + soldPrice, "not paid twice")
	-- Even from far away: the receipt answers before the visit check.
	me:Stand(0, 0, 200)
	local far, farReply = call(me, "Sell", { Token = q.Token })
	me:Stand(-4, 0, 0)
	truthy(far, "receipt answers anywhere: " .. tostring(farReply))
	eq(rt.Profile(1).Cash, cashBefore + soldPrice, "still not paid twice")
end)

test("flush -> a NEW Transactions/Engine reloads from the store: dog still gone, coins kept", function()
	-- An autosave while the player is still on server A: another server is refused (session lock).
	local saved = rt.Tx:FlushProfile(1)
	truthy(saved, "autosave")
	local stored = store.Data["p:1"].Value
	eq(stored.Dogs.king, nil, "saved without the dog")
	eq(stored.Cash, cashBefore + soldPrice, "saved coins")
	local other = server(store, "SERVER-B")
	other.Connected[1] = true
	local joined, why = other.Engine:Join(1)
	eq(joined, false, "the live session on server A blocks server B")
	truthy(string.find(tostring(why), "another server", 1, true), "message: " .. tostring(why))
	-- The player leaves server A (release + save), then joins server B.
	L.Overrides["ServerScriptService/Economy/Runtime"] = rt
	rt.Leave(me)
	eq(store.Data["p:1"].Value.Session, nil, "session released")
	local fresh = server(store, "SERVER-C")
	fresh.Join(me)
	local p = fresh.Profile(1)
	eq(p.Dogs.king, nil, "dog still gone after the reload")
	eq(p.Cash, cashBefore + soldPrice, "coins kept")
	eq(p.Stats.TotalSellValue, soldPrice, "stats kept")
	eq(p.LastSaleAt, NOW, "LastSaleAt kept")
	eq(p.Equipment.Artifacts.art1.DogUid, nil, "artifact still free")
	for uid in pairs(DOGS) do
		if uid ~= "king" then
			truthy(p.Dogs[uid], uid .. " still owned")
		end
	end
	-- The shelter keeps working on the new server.
	local ok, list = call(me, "List", {})
	truthy(ok, "list on the new server: " .. tostring(list))
	eq(#list.Rows, 9, "nine dogs")
	rt = fresh
end)

test("protections: Quote refuses every protected dog with its reason", function()
	-- A join delivers walking dogs (Engine:Join): put "walk" on the road again on this server.
	eq(rt.Profile(1).Dogs.walk.State, "Inventory", "delivered by the join")
	rt.Edit(1, function(p)
		p.Dogs.walk.State = "Walking"
	end)
	for uid, code in pairs({ locked = "Locked", fav = "Favorite", kennel = "Kennel", walk = "Working", shown = "Display" }) do
		local ok, reason = call(me, "Quote", { Uid = uid })
		eq(ok, false, uid .. " refused")
		eq(reason, SRules.Messages[code], uid .. " reason")
	end
	local ok, reason = call(me, "Quote", { Uid = "nope" })
	eq(ok, false, "unknown dog")
	eq(reason, SRules.Messages.Missing, "not owned")
	-- An active trade session protects every dog.
	rt.Engine.TradeByUser[1] = "trade1"
	local _, list = call(me, "List", {})
	for _, row in ipairs(list.Rows) do
		eq(row.Eligible, false, row.Uid .. " in trade")
		eq(row.Protection, "Trade", "trade code")
	end
	local q, r = call(me, "Quote", { Uid = "free1" })
	eq(q, false, "no quote during a trade")
	eq(r, SRules.Messages.Trade, "trade reason")
	rt.Engine.TradeByUser[1] = nil
end)

test("a dog that changes after the review is not sold (lock / favorite / mastery)", function()
	local function quoteThen(uid, change)
		local ok, q = call(me, "Quote", { Uid = uid })
		truthy(ok, "quote " .. uid .. ": " .. tostring(q))
		rt.Edit(1, function(p)
			change(p.Dogs[uid])
		end)
		local cash = rt.Profile(1).Cash
		local sold, why = call(me, "Sell", { Token = q.Token })
		eq(sold, false, uid .. " refused")
		eq(rt.Profile(1).Cash, cash, "no coins")
		truthy(rt.Profile(1).Dogs[uid], "dog kept")
		return why
	end
	eq(quoteThen("free1", function(d) d.Locked = true end), SRules.Messages.Locked, "locked after the quote")
	rt.Edit(1, function(p) p.Dogs.free1.Locked = false end)
	eq(quoteThen("free1", function(d) d.Favorite = true end), SRules.Messages.Favorite, "favorite after the quote")
	rt.Edit(1, function(p) p.Dogs.free1.Favorite = false end)
	eq(quoteThen("free1", function(d) d.MasteryXP = (d.MasteryXP or 0) + 1 end), "Dog changed; review this dog again before selling", "changed after the quote")
end)

test("hold-to-confirm: rank 5 and event dogs need Confirm = true", function()
	for _, uid in ipairs({ "cerb", "pup" }) do
		local ok, q = call(me, "Quote", { Uid = uid })
		truthy(ok, "quote " .. uid)
		eq(q.NeedsHold, true, uid .. " needs a hold")
		local cash = rt.Profile(1).Cash
		local sold, why = call(me, "Sell", { Token = q.Token })
		eq(sold, false, uid .. " refused without the hold")
		eq(why, "Hold the button to confirm this sale", "hold message")
		eq(rt.Profile(1).Cash, cash, "nothing paid")
		local held, result = call(me, "Sell", { Token = q.Token, Confirm = true })
		truthy(held, uid .. " sold with the hold: " .. tostring(result))
		eq(rt.Profile(1).Cash, cash + q.Price, "paid")
		eq(rt.Profile(1).Dogs[uid], nil, "gone")
	end
end)

test("quotes expire on the SERVER clock (TTL), whatever the device clock says", function()
	local ok, q = call(me, "Quote", { Uid = "free2" })
	truthy(ok, "quote")
	L.Time += Config.QuoteTTL + 1
	local sold, why = call(me, "Sell", { Token = q.Token })
	eq(sold, false, "expired")
	eq(why, "Confirmation expired; choose the dog again", "expiry message")
	truthy(rt.Profile(1).Dogs.free2, "dog kept")
	-- A fresh quote inside its TTL sells.
	local ok2, q2 = call(me, "Quote", { Uid = "free2" })
	truthy(ok2, "fresh quote")
	L.Time += Config.QuoteTTL - 1
	local sold2, result = call(me, "Sell", { Token = q2.Token })
	truthy(sold2, "sold inside the TTL: " .. tostring(result))
	-- A token that was never issued.
	local bad, badWhy = call(me, "Sell", { Token = string.rep("a", 32) })
	eq(bad, false, "unknown token")
	eq(badWhy, "Confirmation expired; choose the dog again", "unknown token message")
	local junk, junkWhy = call(me, "Sell", { Token = "not-a-token" })
	eq(junk, false, "malformed token")
	eq(junkWhy, "Invalid confirmation", "malformed message")
end)

test("visit rule: radius 26 or inside the shelter hall; far away, dead or streamed out is refused", function()
	local function listFrom(x, y, z)
		me:Stand(x, y, z)
		local ok, why = call(me, "List", {})
		return ok, why
	end
	truthy(listFrom(-4, 0, 0), "at the desk")
	truthy(listFrom(0, 0, 25.5), "25.5 studs: inside the radius (the old 18 refused)")
	truthy(listFrom(-20, 0, 35), "far corner of the hall (40 studs away, inside the box)")
	truthy(listFrom(-25.5, 0, 10), "doorway with the server slack")
	local ok, why = listFrom(-40, 0, 0)
	eq(ok, false, "outside on the plaza")
	eq(why, "Visit the reception inside Dog Shelter", "visit message")
	eq(listFrom(10, 0, 60), false, "behind the building")
	me:Stand(-4, 0, 0)
	me.Humanoid.Health = 0
	eq((call(me, "List", {})), false, "dead")
	me.Humanoid.Health = 100
	shelterAnchor = nil
	eq((call(me, "List", {})), false, "anchor missing")
	shelterAnchor = anchor
	truthy((call(me, "List", {})), "back")
	-- The client closes its window earlier than the server refuses (an open window is always served).
	truthy(Config.CloseRadius < Config.VisitRadius, "client radius inside the server radius")
	truthy(Config.InReach(0, 0, Config.CloseRadius, true), "client: radius")
	eq(Config.InReach(-26, 0, 10, true), false, "client: no slack outside the hall")
	truthy(Config.InReach(-26, 0, 10, false), "server: slack")
end)

test("unready profile and rate limit have their own messages", function()
	rt.Loaded[1] = nil
	local ok, why = call(me, "List", {})
	eq(ok, false, "not ready")
	eq(why, "Please wait for your profile", "ready message")
	rt.Loaded[1] = true
	rt.Throttle = true
	ok, why = call(me, "List", {})
	eq(ok, false, "rate limited")
	eq(why, "Too many requests; wait a moment", "rate message")
	rt.Throttle = false
	ok, why = call(me, "Nope", {})
	eq(ok, false, "unknown action")
	eq(why, "Unknown shelter action", "unknown action message")
	ok, why = call(me, "List", "x")
	eq(why, "Invalid request", "bad args")
end)

test("one broken dog never breaks the list (per-row pcall)", function()
	rt.Tx.Cache["p:1"].Dogs.broken = { DogUid = "broken", DogId = "NoSuchDog", OwnerUserId = 1, State = "Inventory", AssignedSlot = "", DisplayName = "Mystery" }
	local ok, list = call(me, "List", {})
	rt.Tx.Cache["p:1"].Dogs.broken = nil
	truthy(ok, "list ok: " .. tostring(list))
	local row = rowOf(list, "broken")
	truthy(row, "broken dog shown")
	eq(row.Eligible, false, "never sellable")
	eq(row.Protection, "Error", "error code")
	eq(row.Reason, SRules.Messages.Error, "error reason")
	truthy(#list.Rows >= 6, "every other dog still listed")
end)

test("ShelterRules: the Studio QA cases and the legacy Rate", function()
	local p = { UserId = 1, Dogs = { a = { DogUid = "a", OwnerUserId = 1, DogId = "A", State = "Inventory", AssignedSlot = "" } }, DisplayDogs = {}, Listings = {}, Reservations = {} }
	truthy(SRules.Eligible(p, "a"), "inventory dog")
	eq((SRules.Eligible(p, "missing")), false, "missing")
	eq((SRules.Eligible(p, "a", true)), false, "trade")
	p.Listings.a = {}
	eq((SRules.Eligible(p, "a")), false, "listing")
	p.Listings = { L1 = "a" }
	eq((SRules.Eligible(p, "a")), false, "listing by value")
	p.Listings = {}
	p.Reservations.a = true
	eq((SRules.Eligible(p, "a")), false, "reservation")
	p.Reservations = {}
	p.Dogs.a.PricePaid = 999999999
	eq(SRules.Price(p.Dogs.a, { A = { BasePrice = 100 } }, function() return 1 end), 25, "catalog price")
	eq(SRules.Price(p.Dogs.a, { A = { BasePrice = 100, ShelterRate = 0.1 } }, function() return 1 end), 10, "ShelterRate override")
	eq(SRules.Rate, 0.25, "legacy Rate")
end)

------------------------------------------------------------------------------------------------
-- The window's pure model
------------------------------------------------------------------------------------------------
local Model = require("../src/StarterGui/ScreenGui/Modules/ShelterScreen/ShelterModel")

test("ShelterModel: filters, sorts, counts, next selection", function()
	local rows = {
		{ Uid = "a", Name = "A", Rarity = "Common", Rank = 1, Price = 900, Eligible = true },
		{ Uid = "b", Name = "B", Rarity = "Mythic", Rank = 5, Price = 1625000, Eligible = true },
		{ Uid = "c", Name = "C", Rarity = "Rare", Rank = 2, Price = 5500, Eligible = false, Protection = "Locked" },
		{ Uid = "d", Name = "D", Rarity = "Common", Rank = 1, Price = 875, Eligible = true },
	}
	local function ids(list)
		local out = {}
		for _, r in ipairs(list) do
			table.insert(out, r.Uid)
		end
		return table.concat(out, ",")
	end
	eq(ids(Model.Items(rows, "all", "sellable", false)), "d,a,b,c", "sellable first, cheapest first")
	eq(ids(Model.Items(rows, "all", "sellable", true)), "b,a,d,c", "sellable first, most valuable first")
	eq(ids(Model.Items(rows, "sellable", "price", false)), "b,a,d", "price: best first")
	eq(ids(Model.Items(rows, "sellable", "price", true)), "d,a,b", "price flipped")
	eq(ids(Model.Items(rows, "all", "rarity", false)), "b,c,d,a", "rarity: rarest first, ties by price")
	eq(ids(Model.Items(rows, "protected", "sellable", false)), "c", "protected filter")
	local c = Model.Counts(rows)
	eq(c.all, 4)
	eq(c.sellable, 3)
	eq(c.protected, 1)
	eq(c.Total, 900 + 1625000 + 875, "worth of the sellable dogs")
	local shown = Model.Items(rows, "all", "sellable", false)
	eq(Model.NextUid(shown, "a"), "b", "next one")
	eq(Model.NextUid(shown, "c"), "b", "last one -> previous")
	eq(Model.NextUid({ rows[1] }, "a"), nil, "nothing left")
	eq(Model.Find(rows, "c").Price, 5500, "find")
	eq(Model.Protection("Favorite").Icon, "❤️", "favorite icon")
	eq(Model.Protection("???").Label, "UNAVAILABLE", "unknown code")
end)

test("ShelterModel: retries, deadlines and the breakdown text", function()
	truthy(Model.Retryable("Visit the reception inside Dog Shelter"), "lagged visit retries")
	truthy(Model.Retryable("Please wait for your profile"), "loading profile retries")
	truthy(Model.Retryable("Too many requests; wait a moment"), "rate limit retries")
	eq(Model.Retryable("Unlock this dog first"), false, "a protection does not retry")
	truthy(Model.Stale("Confirmation expired; choose the dog again"), "stale quote")
	eq(Model.Deadline({ TTL = 45 }, 100), 144, "TTL minus one second on the local clock")
	eq(Model.Deadline({}, 100), 100, "no TTL: expired")
	eq(Model.Mult(1.405), "×1.41", "multiplier")
	eq(Model.Mult(1), "×1", "x1")
	eq(Model.Mult(2.35), "×2.35", "max bonus")
	eq(Model.Percent(0.25), "25%", "rate")
	eq(Model.Percent(0.075), "7.5%", "mastery part")
	local parts = Model.BonusParts({ Variant = 0.3, Mastery = 0.075, Ascension = 0 })
	eq(#parts, 2, "zero parts dropped")
	eq(parts[1].Key, "Variant +%s")
	eq(parts[1].Value, "30%")
	eq(parts[2].Value, "7.5%")
end)

------------------------------------------------------------------------------------------------
-- Localization
------------------------------------------------------------------------------------------------
test("every string of the window and every server reply has a Russian entry", function()
	local Dict = L.Require("ReplicatedStorage.Localization.Shelter")
	local base = {}
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en, ru in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"([^"]*)"') do
		base[en] = ru
	end
	local others = {}
	for _, file in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local name = file:gsub("%.luau$", "")
		if name ~= "Shelter" then
			local ok, dict = pcall(L.Require, "ReplicatedStorage.Localization." .. name)
			if ok and type(dict) == "table" and type(dict.Exact) == "table" then
				for en, ru in pairs(dict.Exact) do
					others[en] = ru
				end
			end
		end
	end
	local function russian(ru, what)
		truthy(type(ru) == "string" and ru ~= "", "translation for " .. what)
		local stripped = ru:gsub("%%[%ds]", ""):gsub("DogDex", "")
		truthy(not string.find(stripped, "[A-Za-z]"), "Latin letters in the translation of " .. what .. ": " .. ru)
	end
	for en, ru in pairs(Dict.Exact) do
		eq(base[en], nil, "Exact repeats a base dictionary entry: " .. en)
		eq(others[en], nil, "Exact repeats another module's entry: " .. en)
		russian(ru, en)
	end
	for en, ru in pairs(Dict.UI) do
		russian(ru, en)
	end
	-- Window strings: T("...") and F("...", ...).
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/ShelterScreen.luau")
	local count = 0
	for en in string.gmatch(source, '[^%w]T%("([^"]+)"%)') do
		truthy(Dict.UI[en], "untranslated window text: " .. en)
		count += 1
	end
	local function template(en)
		local ru = Dict.Templates[en]
		truthy(ru, "missing template: " .. en)
		local _, a = string.gsub(en, "%%[ds]", "")
		local _, b = string.gsub(ru, "%%[ds]", "")
		eq(a, b, "placeholders of " .. en)
		for spec in string.gmatch(en, "%%[ds]") do
			truthy(string.find(ru, spec, 1, true), "specifier " .. spec .. " kept in " .. en)
		end
		count += 1
	end
	for en in string.gmatch(source, 'F%("([^"]+)"') do
		template(en)
	end
	truthy(count >= 50, "window strings found: " .. count)
	-- The model's labels and bonus templates.
	for _, protection in pairs(Model.Protections) do
		truthy(Dict.UI[protection.Label], "protection label " .. protection.Label)
	end
	for _, part in ipairs(Model.BonusParts({ Variant = 1, Mastery = 1, Ascension = 1 })) do
		template(part.Key)
	end
	-- The prompt.
	truthy(Dict.UI["SELL EXTRA DOGS"] and Dict.UI["DOG SHELTER"], "prompt texts")
	-- Server replies: the rules' messages and every literal reply of the service.
	local replies = {}
	for _, message in pairs(SRules.Messages) do
		replies[message] = true
	end
	local service = fs.readFile("src/ServerScriptService/Economy/ShelterService.luau")
	for line in string.gmatch(service, "[^\n]+") do
		if string.find(line, "R%.Check%(") then
			-- R.Check(ok, reason) passes a ShelterRules message on (covered above).
			local message = string.match(line, ',%s*"([^"]+)"%)%s*$')
			truthy(message or string.find(line, "reason%)"), "R.Check without a known message: " .. line)
			if message then
				replies[message] = true
			end
		end
	end
	for message in string.gmatch(service, 'return false, "([^"]+)"') do
		replies[message] = true
	end
	for _, message in ipairs({ "Profile session unavailable", "Cash limit reached", "Account is busy; retry shortly" }) do
		replies[message] = true
	end
	local n = 0
	for message in pairs(replies) do
		truthy(Dict.Exact[message] or others[message] or base[message], "untranslated server reply: " .. message)
		n += 1
	end
	truthy(n >= 20, "server replies found: " .. n)
	-- The sale message pattern.
	local text = "Pumpkin Pup found a new home! +5500 Coins"
	local out = text
	for _, rule in ipairs(Dict.Patterns) do
		out = string.gsub(out, rule[1], rule[2])
	end
	eq(out, "Pumpkin Pup: новый дом найден! +5500 монет", "sale message")
end)

print(string.format("shelter_e2e: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("shelter_e2e tests failed")
end
