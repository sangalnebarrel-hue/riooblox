--!nolint
-- CHAPTER II data + server core: lune run tests/chapter2_feature.luau
-- * Economy.Features.Underyard: Shape heals garbage (never deletes unknown keys), Normalize never throws, Validate is
--   nil-safe, EnsureDaily (contracts + rested), View shape, size budget, the Halloween view embed, the 64-skin cap.
-- * ServerScriptService.Halloween.Chapter2 against a fake Core (transactions with rollback): the Chapter I latch and
--   attributes, DR'd shards, seal offering (+ the onboarding refund), seal clears (first / repeat / gold), contracts,
--   the Toll Box, Dex II, the tailor, reward rows that convert instead of failing, key overflow, the onboarding steps,
--   Gravekeeper rewards, the progress queue.
local L = require("./lib/economy_env")
local serde = require("@lune/serde")
local Vector3 = require("@lune/roblox").Vector3

local Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Rules = L.Require("ReplicatedStorage.Halloween.Chapter2Rules")
local F = L.Require("ServerScriptService.Economy.Features.Underyard")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
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
local Rstub = { Check = function(ok, msg)
	if not ok then
		error(msg, 0)
	end
end }

local DAY = 86400
local START = Rules.UnixFromDate(2026, 10, 20)
local NOW = START + 3 * DAY + 3600 -- Oct 23 01:00 UTC: seals I-V open
L.Time = NOW

local function deep(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = deep(x)
	end
	return o
end

---------------------------------------------------------------------------------------------------------------------
-- the feature
---------------------------------------------------------------------------------------------------------------------
test("Shape creates the §3.2 layout on an empty profile", function()
	local p = { UserId = 7 }
	local u = F.Shape(p)
	eq(p.Underyard, u)
	eq(u.Version, 1)
	eq(u.Chapter1.Complete, false)
	eq(u.Keys, 0)
	eq(u.Fragments, 0)
	for i = 1, 7 do
		local s = u.Seals[tostring(i)]
		truthy(s and s.Offered == false and s.Cleared == false and s.Gold == false and s.Best == 0, "seal " .. i)
	end
	eq(u.Daily.Day, -1)
	eq(type(u.Daily.Contracts.List), "table")
	eq(u.Rested.Pool, 0)
	eq(u.Tutorial.Step, 0)
	for _, k in ipairs(F.Stats) do
		eq(u.Stats[k], 0, k)
	end
	eq(u.Coffins.Crown.Rolls, 0)
end)

test("Shape heals garbage and keeps unknown keys", function()
	local p = { UserId = 7, Underyard = {
		Version = "x", Chapter1 = { Complete = "yes", At = -5, Notified = 1 }, RevealSeen = 1, Entered = true, FirstEnterAt = 0 / 0,
		Tutorial = "broken", Seals = { ["1"] = { Offered = false, Cleared = true, Gold = true, Best = 1e30 }, ["2"] = "junk", ["9"] = { Cleared = true } },
		Keys = 1e9, Fragments = -3, Daily = { Day = 20384.7, Raw = -1, Eff = 0 / 0, Exchange = math.huge, Contracts = { Day = "d",
			List = { { Id = "Perfect", Goal = 40, Progress = 99, Claimed = 1 }, "bad", { Id = 5 }, { Id = string.rep("x", 50) } } } },
		Rested = { Pool = 99999 }, Dex2Claims = { ["3"] = true, [4] = true, ["5"] = "y" },
		Owned = { Decor = { uy_moon_statue = true, bad = 1 }, Finds = "x" }, Journal = { reveal = true, seal1 = 1790000000, [3] = true },
		Coffins = { Opened = 2.9, Last = { { Key = "Dust", Kind = "Dust", Amount = 77 }, { Kind = "x" }, 4 }, Crown = { Seconds = -1, Rolls = 99 } },
		Boss = { FinaleClears = "2", FirstClears = { ["3"] = true } }, Stats = { Perfect = 12, Downs = -4, Mystery = 3 },
		FutureFeature = { Keep = true },
	} }
	local u = F.Shape(p)
	eq(u.Version, 1)
	eq(u.Chapter1.Complete, false, "only true is true")
	eq(u.Chapter1.At, 0)
	eq(u.RevealSeen, false)
	eq(u.Entered, true)
	eq(u.FirstEnterAt, 0)
	eq(u.Tutorial.Step, 0)
	eq(u.Seals["1"].Cleared, true)
	eq(u.Seals["1"].Offered, true, "a cleared seal was offered")
	eq(u.Seals["1"].Gold, true)
	eq(u.Seals["1"].Best, 1e9)
	eq(u.Seals["2"].Cleared, false)
	truthy(u.Seals["9"] ~= nil, "unknown seal row kept")
	eq(u.Keys, Cfg.Coffin.MaxKeys)
	eq(u.Fragments, 0)
	eq(u.Daily.Day, 20384)
	eq(u.Daily.Raw, 0)
	eq(u.Daily.Eff, 0)
	eq(u.Daily.Exchange, 0)
	eq(#u.Daily.Contracts.List, 1)
	eq(u.Daily.Contracts.List[1].Progress, 99, "saved progress is kept (claims compare with the goal)")
	eq(u.Rested.Pool, Cfg.Rested.Cap, "a garbage pool is capped")
	truthy(u.Dex2Claims["3"] and not u.Dex2Claims["5"], "dex claims")
	truthy(u.Owned.Decor.uy_moon_statue and u.Owned.Decor.bad == nil, "owned decor")
	eq(next(u.Owned.Finds), nil)
	eq(u.Journal.reveal, 0)
	eq(u.Journal.seal1, 1790000000)
	eq(u.Coffins.Opened, 2)
	eq(#u.Coffins.Last, 1)
	eq(u.Coffins.Last[1].Amount, 77)
	eq(u.Coffins.Crown.Rolls, 9)
	eq(u.Boss.FinaleClears, 0)
	eq(u.Stats.Perfect, 12)
	eq(u.Stats.Downs, 0)
	eq(u.Stats.Mystery, 3, "unknown stat kept")
	truthy(u.FutureFeature and u.FutureFeature.Keep, "unknown key kept")
	-- idempotent
	local before = serde.encode("json", u)
	F.Shape(p)
	eq(serde.encode("json", p.Underyard), before, "second Shape changes nothing")
end)

test("Normalize never throws and never erases data; Validate is nil-safe", function()
	local p = { UserId = 1 }
	F.Normalize(Rstub, p, NOW)
	eq(p.Underyard, nil, "absent stays absent (created lazily)")
	F.Validate(Rstub, p)
	-- a sub-table that throws on write: parked under UnderyardBroken, a clean table replaces it
	local evil = setmetatable({}, { __newindex = function()
		error("read-only")
	end })
	p.Underyard = evil
	F.Normalize(Rstub, p, NOW)
	eq(p.UnderyardBroken, evil)
	truthy(type(p.Underyard) == "table" and p.Underyard ~= evil and p.Underyard.Version == 1, "fresh table")
	F.Validate(Rstub, p)
	local ok = pcall(F.Validate, Rstub, { Underyard = { Keys = 99, Fragments = 0, Seals = {}, Daily = {}, Chapter1 = {} } })
	eq(ok, false, "keys above the cap")
	ok = pcall(F.Validate, Rstub, { Underyard = "x" })
	eq(ok, false)
	ok = pcall(F.Validate, Rstub, { Underyard = { Keys = 1.5, Fragments = 0, Seals = {}, Daily = {}, Chapter1 = {} } })
	eq(ok, false)
end)

test("EnsureDaily draws contracts, accrues rested, resets once per UTC day", function()
	local p = { UserId = 4242 }
	local changed = F.EnsureDaily(p, NOW)
	truthy(changed, "first day")
	local u = p.Underyard
	local today = NOW // DAY
	eq(u.Daily.Day, today)
	eq(#u.Daily.Contracts.List, 3)
	local expect = Rules.PickContracts(4242, today, Cfg, 0)
	for i, row in ipairs(expect) do
		eq(u.Daily.Contracts.List[i].Id, row.Id)
	end
	eq(u.Rested.Pool, 750, "3 full days since the start x 250, capped")
	eq(F.EnsureDaily(p, NOW + 60), false)
	u.Daily.Raw, u.Daily.Exchange = 400, 40
	u.Rested.Pool = 0
	F.EnsureDaily(p, NOW + DAY)
	eq(u.Daily.Raw, 0)
	eq(u.Daily.Exchange, 0)
	eq(u.Rested.Pool, 50, "(500 - 400) x .5")
end)

test("View: shape, fresh profiles stay untouched, size budget", function()
	local fresh = { UserId = 9 }
	local v = F.View(fresh, NOW)
	eq(fresh.Underyard, nil, "View never creates data")
	truthy(v.Fresh, "fresh")
	eq(#v.Seals, 7)
	eq(v.Mask, "0000000")
	eq(v.Chapter1.Total, 5)
	eq(v.Phase, 5)
	eq(v.NextPhaseAt, START + 4 * DAY)
	local p = { UserId = 9, DogDex = { HW_BellPup = true }, Resources = { BellShards = 321, LuckyDust = 9 },
		Halloween = { Boss = { Best = 3 }, Cauldron = { Invested = 400 }, Stats = { Knocks = 7, BloodMoons = 1, Spots = 10 } } }
	F.EnsureDaily(p, NOW)
	local u = p.Underyard
	u.Seals["1"].Offered, u.Seals["1"].Cleared = true, true
	v = F.View(p, NOW)
	eq(v.Fresh, nil)
	eq(v.Shards, 321)
	eq(v.Dust, 9)
	eq(v.Mask, "1000000")
	eq(v.Cleared, 1)
	truthy(v.Chapter1.Ready and not v.Chapter1.Complete, "ready, not yet latched")
	eq(v.Seals[1].Cost, 60, "seal I opened 3 days ago: -40%")
	eq(v.Seals[1].Discount, true)
	eq(v.Seals[2].Playable, false)
	eq(v.Seals[2].Previous, true)
	eq(v.Seals[3].Open, true)
	eq(v.Seals[6].Open, false)
	eq(#v.Contracts.List, 3)
	eq(v.Daily.Rate, 1)
	eq(v.Dex2.Count, 1)
	eq(v.Tutorial.Current, 0)
	eq(v.Daily.DoorsMax, 3)
	-- a maximal profile stays under 6 KB of JSON
	for i = 1, 7 do
		local s = u.Seals[tostring(i)]
		s.Offered, s.Cleared, s.Gold, s.At, s.Best, s.Progress = true, true, true, NOW, 999999, 3
	end
	for _, key in ipairs(Cfg.Journal.Order) do
		u.Journal[key] = NOW
		u.JournalRead[key] = true
	end
	for _, id in ipairs(Cfg.Decor.Order) do
		u.Owned.Decor[id] = true
	end
	for _, id in ipairs(Cfg.Finds.Order) do
		u.Owned.Finds[id] = true
	end
	for i = 1, 10 do
		table.insert(u.Coffins.Last, { Key = "uy_bottled_whisper", Kind = "Find", Id = "uy_bottled_whisper", Amount = 1, Rank = 3, Converted = true, At = NOW + i })
	end
	for _, tier in ipairs(Cfg.Dex2Rewards) do
		u.Dex2Claims[tostring(tier.Count)] = true
	end
	u.Boss.FirstClears = { ["3"] = true, ["4"] = true, ["5"] = true, F = true }
	for _, k in ipairs(F.Stats) do
		u.Stats[k] = 123456789
	end
	F.Shape(p)
	local size = #serde.encode("json", u)
	truthy(size <= 6144, "p.Underyard is " .. size .. " bytes")
end)

test("Halloween view embeds .Chapter2; skins cap raised to 64", function()
	local H = L.Require("ServerScriptService.Economy.Features.Halloween")
	local p = { UserId = 3, Halloween = { Skins = {} } }
	for i = 1, 70 do
		p.Halloween.Skins["S" .. i] = true
	end
	H.Shape(p)
	local n = 0
	for _ in pairs(p.Halloween.Skins) do
		n += 1
	end
	eq(n, 64)
	local view = H.View(p, NOW)
	truthy(type(view.Chapter2) == "table" and #view.Chapter2.Seals == 7, "embedded Chapter II view")
	local bare = H.View({ UserId = 3 }, NOW)
	truthy(bare.Fresh and type(bare.Chapter2) == "table", "fresh Halloween view still carries Chapter2")
end)

test("Shared.Budget falls back to the Chapter II quality keys", function()
	local Shared = L.Require("ReplicatedStorage.Halloween.Shared")
	eq(Shared.Budget("UnderMotes"), 60)
	eq(Shared.Budget("CoffinFX"), 1)
	eq(Shared.Budget("Particles"), 60, "existing key unchanged")
	eq(Shared.Budget("NoSuchKey"), 0)
end)

---------------------------------------------------------------------------------------------------------------------
-- Chapter2.luau against a fake Core
---------------------------------------------------------------------------------------------------------------------
local itemDefs = { uy_coffin_nail = { Id = "uy_coffin_nail", BaseDropChance = 1e-3 }, uy_hollow_heart = { Id = "uy_hollow_heart", BaseDropChance = 1e-5 } }
local itemsFull = false
L.Overrides["ServerScriptService/Economy/ItemRules"] = {
	Definitions = itemDefs,
	Free = function()
		return not itemsFull
	end,
}
local catalog = { hw_bone_arch = 1, uy_spirit_fence = 1, uy_moon_statue = 1 }
L.Overrides["ReplicatedStorage/DogEconomy/DecorCatalog"] = {
	MaxOwned = function(id)
		return catalog[id] or 0
	end,
}
local C2 = L.Require("ServerScriptService.Halloween.Chapter2")
local HConfig = L.Require("ReplicatedStorage.Halloween.Config")
-- the place registers every Chapter II skin (WP-K2); the "unregistered skin" paths are exercised by taking one out
for _, id in ipairs({ "UY_TVHead", "UY_Laughsaw", "UY_BellReaper" }) do
	assert(HConfig.Skins.Names[id] ~= nil, "Chapter II skin " .. id .. " is registered in Config.Skins")
end
HConfig.Skins.Names.UY_Laughsaw = nil

local function fakePlayer(uid)
	local attrs = {}
	return { UserId = uid, Name = "P" .. uid, Parent = true, Attrs = attrs,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end }
end

local profiles, signals, handlers = {}, {}, {}
local assetReady = { HW_BellPup = true, HW_MourningShiba = true, HW_BellkeeperWolf = true, HW_HollowKing = true }
local dogFree = true
local nearOk = true
local rootPos = Vector3.new(0, 3, 2462)
local core = {
	Players = {},
	Rules = { Check = Rstub.Check, Free = function()
		return dogFree
	end },
	Runtime = { Engine = { AssetReady = function(id)
		return assetReady[id] == true
	end }, Views = {} },
	DogsOf = function(rows)
		local out = {}
		for _, row in ipairs(rows or {}) do
			if type(row) == "table" and row.Kind == "Dog" and not table.find(out, row.Id) then
				table.insert(out, row.Id)
			end
		end
		return out
	end,
	SetAttr = function(inst, k, v)
		inst:SetAttribute(k, v)
	end,
	Signal = function(target, kind, data)
		table.insert(signals, { Target = target, Kind = kind, Data = data })
	end,
	OnRequest = function(action, fn)
		handlers[action] = fn
	end,
	OnReady = function() end,
	Near = function()
		return nearOk
	end,
	Root = function()
		return { Position = rootPos }
	end,
	IsActive = function()
		return true
	end,
}
function core.State(player)
	return core.Players[player]
end
-- Core.Transact: deep-copy rollback on error, Shape of p.Halloween, a minimal ctx, the Halloween view on the result
local H = L.Require("ServerScriptService.Economy.Features.Halloween")
function core.Transact(player, label, fn, opts)
	opts = opts or {}
	local p = profiles[player.UserId]
	local backup = deep(p)
	local after = {}
	local declared = table.clone(opts.Dogs or {})
	local ok, res = pcall(function()
		local h = H.Shape(p)
		local ctx = { Touched = false, Granted = {} }
		function ctx.After(f)
			table.insert(after, f)
		end
		function ctx.Item(o)
			if itemsFull then
				return nil
			end
			p.Items = p.Items or {}
			local x = { ItemId = o.ItemId, Uid = tostring(#p.Items + 1), Origin = o.Origin }
			table.insert(p.Items, x)
			return deep(x)
		end
		function ctx.Decor(id)
			p.Decor = p.Decor or { Owned = {} }
			local have = p.Decor.Owned[id] or 0
			if have >= (catalog[id] or 0) then
				return false
			end
			p.Decor.Owned[id] = have + 1
			return true
		end
		function ctx.Skin(id)
			Rstub.Check(HConfig.Skins.Names[id] ~= nil, "Unknown skin")
			if h.Skins[id] then
				return false
			end
			h.Skins[id] = true
			return true
		end
		function ctx.Dog(id)
			Rstub.Check(table.find(declared, id) ~= nil, "Dog grant not declared")
			p.Dogs = p.Dogs or {}
			local n = 1 -- (p.Dogs is keyed by DogUid: count the keys for a fresh uid)
			for _ in pairs(p.Dogs) do
				n += 1
			end
			local uid = "D" .. tostring(n)
			p.Dogs[uid] = { DogUid = uid, DogId = id, Origin = "BuriedMoon" }
			return { DogUid = uid, DogId = id }
		end
		function ctx.Candy(n)
			h.Candy += n
			return n
		end
		function ctx.Stat(key, n) -- Core's Halloween stat helper (Core.ctx.Item calls it): must never be shadowed
			h.Stats[key] = (h.Stats[key] or 0) + (n or 1)
		end
		function ctx.Spend(n)
			Rstub.Check(h.Candy >= n, "Not enough Candy")
			h.Candy -= n
		end
		function ctx.Bones(n)
			p.Bones = (p.Bones or 0) + n
			return n
		end
		function ctx.Coins(spec)
			local n = type(spec) == "number" and spec or 50000
			p.Cash = (p.Cash or 0) + n
			return n
		end
		local r = fn(p, h, ctx, L.Time)
		F.Validate(Rstub, p)
		return r
	end)
	if not ok then
		profiles[player.UserId] = backup
		return false, res
	end
	local view = H.View(p, L.Time)
	if type(res) == "table" and res.View == nil then
		res.View = view
	end
	core.Players[player] = core.Players[player] or { Ready = true }
	core.Players[player].View = view
	for _, f in ipairs(after) do
		f()
	end
	return true, res, nil, false
end
C2.Start(core, { Chapter2 = C2 })

local function newProfile(uid, chapter1)
	local p = { UserId = uid, Resources = {}, Cosmetics = {}, Halloween = { Season = HConfig.Season, Candy = 0, Skins = {} } }
	if chapter1 then
		p.Halloween.Boss = { Best = 2 }
		p.Halloween.Cauldron = { Invested = 300 }
		p.Halloween.Stats = { Knocks = 7, BloodMoons = 1, Spots = 10 }
	end
	profiles[uid] = p
	return fakePlayer(uid), p
end
local function call(action, player, args)
	local ok, a, b = pcall(handlers[action], player, args or {})
	if not ok then
		return false, a
	end
	return a, b
end
local function shards(uid)
	local r = profiles[uid].Resources
	return r and r.BellShards or 0
end
local function signalsOf(kind)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == kind then
			table.insert(out, s)
		end
	end
	return out
end

test("every §4.2 request is registered; Chapter I latch + attributes on C2Hello", function()
	for _, a in ipairs({ "C2Hello", "C2Notified", "C2RevealSeen", "C2ContractClaim", "C2ContractBonus", "C2Exchange", "C2SealOffer",
		"C2DexClaim", "C2Craft", "C2Journal", "C2Tutorial" }) do
		truthy(type(handlers[a]) == "function", a)
	end
	local pl = newProfile(101, false)
	local ok, res = call("C2Hello", pl)
	truthy(ok, tostring(res))
	truthy(res.Server and res.Server.Phase == 5, "server phase info")
	eq(pl.Attrs.HalloweenChapter1Complete, false)
	eq(pl.Attrs.UySealMask, "0000000")
	eq(pl.Attrs.UyTutorial, 0)
	ok, res = call("C2SealOffer", pl, { Seal = 1 })
	eq(ok, false)
	eq(res, "Finish Chapter I first")
	local done = newProfile(102, true)
	signals = {}
	ok = call("C2Hello", done)
	truthy(ok, "hello")
	eq(done.Attrs.HalloweenChapter1Complete, true, "latched")
	eq(profiles[102].Underyard.Chapter1.Complete, true)
	eq(profiles[102].Underyard.Chapter1.At, NOW)
	truthy(profiles[102].Underyard.Journal.chapter1, "journal chapter1")
	eq(#signalsOf("C2Reveal"), 1, "C2Reveal at the flip")
	-- the latch survives a Chapter I nerf
	profiles[102].Halloween.Boss.Best = 0
	call("C2Hello", done)
	eq(profiles[102].Underyard.Chapter1.Complete, true)
	eq(#signalsOf("C2Reveal"), 1, "no second reveal")
	ok = call("C2Notified", done)
	truthy(ok)
	eq(done.Attrs.Chapter2Notified, true)
	nearOk = false
	ok, res = call("C2RevealSeen", done)
	eq(res, "Come closer to the church")
	ok, res = call("C2RevealSeen", done, { Replay = true })
	truthy(ok and res.Replay, "replay sets nothing")
	eq(profiles[102].Underyard.RevealSeen, false)
	nearOk = true
	ok = call("C2RevealSeen", done)
	truthy(ok)
	eq(done.Attrs.Chapter2RevealSeen, true)
	truthy(profiles[102].Underyard.Journal.reveal, "journal reveal")
end)

test("onboarding: enter -> shards -> toll -> coffin grant -> practice -> mourner -> free first offering", function()
	local pl = newProfile(103, true)
	call("C2Hello", pl)
	local u = profiles[103].Underyard
	u.Rested.Pool = 0
	C2.MarkEntered(pl)
	u = profiles[103].Underyard
	eq(u.Entered, true)
	eq(u.Tutorial.Step, 1)
	eq(pl.Attrs.UyTutorial, 1)
	truthy(u.Journal.descend, "journal descend")
	-- step 1: 10 shards earned
	C2.Transact(pl, "t", function(_p, _u, ctx)
		ctx.Shards(6, "Echo")
	end)
	eq(profiles[103].Underyard.Tutorial.Step, 1)
	C2.Transact(pl, "t", function(_p, _u, ctx)
		ctx.Shards(4, "Echo")
	end)
	eq(profiles[103].Underyard.Tutorial.Step, 2, "10 shards -> step 2")
	-- step 2 completes only from the Toll trial event (not by request)
	local ok, err = call("C2Tutorial", pl, { Step = 2 })
	eq(ok, false)
	eq(err, "Finish this step first")
	eq(C2.TutorialEventNow(pl, "Coffin"), false, "not the current step")
	local before = shards(103)
	local keysBefore = profiles[103].Underyard.Keys
	eq(C2.TutorialEventNow(pl, "Toll"), true)
	u = profiles[103].Underyard
	eq(u.Tutorial.Step, 3)
	eq(u.Keys, keysBefore + 1, "coffin key granted")
	eq(shards(103), before + 150, "coffin shards granted (exempt)")
	eq(pl.Attrs.UyTutorial, 3)
	truthy(C2.ForceCoffinFind(pl), "the tutorial coffin forces a showcase find")
	C2.Transact(pl, "coffin", function(_p, _u, ctx)
		ctx.SpendShards(150)
		ctx.Keys(0)
		ctx.RecordCoffin({ Key = "uy_coffin_nail", Kind = "Find", Id = "uy_coffin_nail", Amount = 1, Rank = 2 })
	end)
	u = profiles[103].Underyard
	eq(u.Coffins.Opened, 1)
	eq(u.Coffins.Last[1].Key, "uy_coffin_nail")
	eq(u.Tutorial.Step, 4, "coffin opened -> step 4")
	-- step 4: the practice ring (server proximity)
	rootPos = Vector3.new(30, 3, 2462)
	ok, err = call("C2Tutorial", pl, { Step = 4 })
	eq(err, "Finish this step first")
	rootPos = Vector3.new(2, 3, 2463)
	ok = call("C2Tutorial", pl, { Step = 4 })
	truthy(ok, "inside the ring")
	eq(profiles[103].Underyard.Tutorial.Step, 5)
	-- step 5 (Mourner) by event, then step 6: the first offering is covered by the tutorial
	eq(C2.TutorialEventNow(pl, "Mourner"), true)
	eq(profiles[103].Underyard.Tutorial.Step, 6)
	local s0 = shards(103)
	ok, err = call("C2SealOffer", pl, { Seal = 1 })
	truthy(ok, tostring(err))
	eq(err.Refunded, 60, "Seal I costs 60 on Oct 23 and the tutorial pays it")
	eq(shards(103), s0, "no shards spent")
	u = profiles[103].Underyard
	truthy(u.Seals["1"].Offered, "offered")
	truthy(u.Tutorial.Done, "onboarding done")
	eq(pl.Attrs.UyTutorial, -1)
	-- skip works for anyone and is idempotent
	local p2 = newProfile(104, true)
	call("C2Hello", p2)
	C2.MarkEntered(p2)
	ok = call("C2Tutorial", p2, { Skip = true })
	truthy(ok)
	eq(p2.Attrs.UyTutorial, -1)
end)

test("Bell Shards: DR per source, exempt sources, rested first, contract + stats", function()
	local pl = newProfile(105, true)
	call("C2Hello", pl)
	local u = profiles[105].Underyard
	u.Rested.Pool = 0
	u.Tutorial.Done = true
	u.Daily.Contracts.List = { { Id = "Shards", Goal = 250, Progress = 0, Claimed = false } }
	local got = 0
	C2.Transact(pl, "t", function(_p, _u, ctx)
		got = ctx.Shards(600, "Streak")
	end)
	eq(got, 535, "500 + 100 x .35")
	C2.Transact(pl, "t", function(_p, _u, ctx)
		got = ctx.Shards(300, "First")
	end)
	eq(got, 300, "first clear is exempt")
	u = profiles[105].Underyard
	eq(u.Daily.Raw, 600)
	eq(u.Stats.ShardsEarned, 835)
	eq(u.Daily.Contracts.List[1].Progress, 250, "earn-shards contract")
	C2.Transact(pl, "t", function(_p, _u, ctx)
		got = ctx.Shards(50, "Contract")
	end)
	eq(profiles[105].Underyard.Stats.ShardsEarned, 835, "contract shards are not 'earned'")
	eq(#signalsOf("C2Shards") > 0, true)
	C2.Transact(pl, "t", function(_p, _u, ctx)
		ctx.Stat("Mutations", 2)
		ctx.C2Stat("Revives", 1)
	end)
	eq(profiles[105].Halloween.Stats.Mutations, 2, "Core ctx.Stat untouched")
	eq(profiles[105].Underyard.Stats.Revives, 1, "Chapter II stats through C2Stat")
	local ok, err = C2.Transact(pl, "t", function(_p, _u, ctx)
		ctx.SpendShards(1e6)
	end)
	eq(ok, false)
	eq(err, "Not enough Bell Shards")
	eq(shards(105), 885, "rolled back")
end)

test("seal offering, first clear with dog + key, repeat (DR), gold, gating errors", function()
	local pl = newProfile(106, true)
	call("C2Hello", pl)
	local u = profiles[106].Underyard
	u.Tutorial.Done = true
	u.Rested.Pool = 0
	local ok, err = call("C2SealOffer", pl, { Seal = 2 })
	eq(err, "Clear the previous seal first")
	ok, err = call("C2SealOffer", pl, { Seal = 1 })
	eq(err, "Not enough Bell Shards")
	profiles[106].Resources.BellShards = 1000
	nearOk = false
	ok, err = call("C2SealOffer", pl, { Seal = 1 })
	eq(err, "Come closer to the seal's altar")
	nearOk = true
	ok, err = call("C2SealOffer", pl, { Seal = 1 })
	truthy(ok, tostring(err))
	eq(shards(106), 940, "60 after the discount")
	ok, err = call("C2SealOffer", pl, { Seal = 1 })
	eq(err, "The offering is already made")
	ok, err = call("C2SealOffer", pl, { Seal = 9 })
	eq(err, "Unknown seal")
	signals = {}
	local res
	ok, res = C2.GrantSeal(pl, 1, { Gold = false, Score = 13 })
	truthy(ok, tostring(res))
	truthy(res.First, "first clear")
	u = profiles[106].Underyard
	eq(u.Seals["1"].Cleared, true)
	eq(u.Keys, 1)
	eq(shards(106), 940 + 150)
	local dogs = 0
	for _, d in pairs(profiles[106].Dogs or {}) do
		dogs += 1
		eq(d.DogId, "HW_BellPup")
		eq(d.Origin, "Underyard")
	end
	eq(dogs, 1, "H09 Bell Pup")
	eq(pl.Attrs.UySealMask, "1000000")
	eq(pl.Attrs.UySeals, 1)
	eq(pl.Attrs.CoffinKeys, 1)
	truthy(u.Journal.seal1, "journal seal1")
	eq(#signalsOf("C2Seal"), 1)
	ok, res = C2.GrantSeal(pl, 1, { Gold = true, Score = 19 })
	truthy(ok and not res.First and res.Gold, "repeat + gold")
	u = profiles[106].Underyard
	eq(u.Keys, 2, "gold key")
	eq(u.Seals["1"].Best, 19)
	eq(shards(106), 940 + 150 + 20, "repeat 20 (DR tier 1)")
	ok, res = C2.GrantSeal(pl, 1, { Gold = true })
	eq(profiles[106].Underyard.Keys, 2, "gold only once")
	-- seal IV's dog asset is missing in this place: converted, never an error
	u.Seals["4"].Offered = true
	ok, res = C2.GrantSeal(pl, 4, {})
	truthy(ok, tostring(res))
	local conv = nil
	for _, r in ipairs(res.Rewards) do
		if r.Id == "HW_CandleCorgi" then
			conv = r
		end
	end
	truthy(conv and conv.Converted and conv.Reason == "Unavailable" and conv.Conversion[1].Amount == 450, "dog -> 150 x rank shards")
	ok, res = C2.GrantSeal(pl, 6, {})
	eq(ok, false)
	eq(res, "Make the offering at the seal's altar first")
end)

test("contracts: claim, bonus key, errors", function()
	local pl = newProfile(107, true)
	call("C2Hello", pl)
	local u = profiles[107].Underyard
	u.Tutorial.Done = true
	local list = u.Daily.Contracts.List
	eq(#list, 3)
	local ok, err = call("C2ContractClaim", pl, { Id = list[1].Id })
	eq(err, "Contract not finished yet")
	ok, err = call("C2ContractClaim", pl, { Id = "Nope" })
	eq(err, "This contract is not part of today's list")
	ok, err = call("C2ContractBonus", pl)
	eq(err, "Finish and claim every contract first")
	for _, row in ipairs(profiles[107].Underyard.Daily.Contracts.List) do
		row.Progress = row.Goal
	end
	local before = shards(107)
	for _, row in ipairs(profiles[107].Underyard.Daily.Contracts.List) do
		ok, err = call("C2ContractClaim", pl, { Id = row.Id })
		truthy(ok, tostring(err))
	end
	eq(shards(107), before + 180, "3 x 60 (exempt)")
	ok, err = call("C2ContractClaim", pl, { Id = profiles[107].Underyard.Daily.Contracts.List[1].Id })
	eq(err, "Contract already claimed")
	ok = call("C2ContractBonus", pl)
	truthy(ok)
	eq(profiles[107].Underyard.Keys, 1)
	eq(profiles[107].Underyard.Daily.Contracts.AllClaimed, true)
	ok, err = call("C2ContractBonus", pl)
	eq(err, "Contract bonus already claimed today")
	eq(Rules.DoorsPerDay(profiles[107].Underyard, Cfg), 4, "+1 door with all contracts claimed")
end)

test("Toll Box exchange: candy -> shards, daily cap, proximity", function()
	local pl = newProfile(108, true)
	call("C2Hello", pl)
	profiles[108].Halloween.Candy = 2000
	local ok, res = call("C2Exchange", pl, { Shards = 30 })
	truthy(ok, tostring(res))
	eq(res.Shards, 30)
	eq(profiles[108].Halloween.Candy, 2000 - 750)
	ok, res = call("C2Exchange", pl, { Shards = 30 })
	truthy(ok)
	eq(res.Shards, 10, "daily cap 40")
	ok, res = call("C2Exchange", pl, { Shards = 1 })
	eq(res, "The Toll Box is full for today. Come back tomorrow!")
	ok, res = call("C2Exchange", pl, { Shards = 41 })
	eq(res, "Choose how many shards to buy")
	local poor = newProfile(109, true)
	call("C2Hello", poor)
	ok, res = call("C2Exchange", poor, { Shards = 5 })
	eq(res, "Not enough Candy")
	eq(shards(109), 0)
end)

test("reward rows convert instead of failing (duplicates, full storage, unknown ids, key overflow)", function()
	local pl = newProfile(110, true)
	call("C2Hello", pl)
	local ok, rows = C2.Grant(pl, "t", {
		{ Kind = "Find", Id = "uy_coffin_nail" }, -- new
		{ Kind = "Find", Id = "uy_coffin_nail" }, -- duplicate in the same write
		{ Kind = "Find", Id = "uy_wax_hand" }, -- not in ItemDefinitions here
		{ Kind = "Decor", Id = "uy_spirit_fence" }, { Kind = "Decor", Id = "uy_spirit_fence" }, { Kind = "Decor", Id = "uy_grave_gate" },
		{ Kind = "Skin", Id = "UY_TVHead" }, { Kind = "Skin", Id = "UY_TVHead" }, { Kind = "Skin", Id = "UY_Laughsaw" },
		{ Kind = "Dust", Min = 60, Max = 60 }, { Kind = "Fragments", Amount = 2 }, { Kind = "Bones", Amount = 300 },
		{ Kind = "Cash", Coins = { IncomeMinutes = 30, MinCash = 50000 } }, { Kind = "Candy", Amount = 5 },
		{ Kind = "Title", Id = "HollowCrown2026" }, { Kind = "Mystery" },
	})
	truthy(ok, tostring(rows))
	eq(rows[1].Amount, 1)
	truthy(rows[1].Item, "find granted")
	truthy(rows[2].Converted and rows[2].Reason == "Owned", "find duplicate")
	eq(rows[2].Conversion[1].Kind, "Shards")
	eq(rows[2].Conversion[1].Amount, 80)
	truthy(rows[3].Converted and rows[3].Reason == "Unavailable", "unknown find")
	eq(rows[4].Amount, 1)
	truthy(rows[5].Converted and rows[5].Reason == "Owned", "decor at max")
	eq(rows[5].Conversion[1].Amount, 12)
	truthy(rows[6].Converted and rows[6].Reason == "Unavailable", "decor not in the catalog yet")
	eq(rows[7].Amount, 1)
	truthy(rows[8].Converted and rows[8].Reason == "Owned", "skin owned")
	eq(rows[8].Conversion[2].Amount, 800)
	truthy(rows[9].Converted and rows[9].Reason == "Unavailable", "skin not registered yet")
	eq(rows[10].Amount, 60)
	eq(rows[11].Amount, 2)
	eq(rows[14].Amount, 5)
	eq(profiles[110].Cosmetics.HollowCrown2026, true)
	truthy(rows[16].Converted, "unknown kind")
	local u = profiles[110].Underyard
	eq(u.Fragments, 2 + 12 + 12 + 25 + 25)
	truthy(u.Owned.Finds.uy_coffin_nail and u.Owned.Decor.uy_spirit_fence, "owned sets")
	-- full item storage
	itemsFull = true
	ok, rows = C2.Grant(pl, "t", { { Kind = "Find", Id = "uy_hollow_heart" } })
	itemsFull = false
	truthy(rows[1].Converted and rows[1].Reason == "Full", "full storage")
	eq(#rows[1].Conversion, 3, "legendary: + 3 fragments")
	-- key overflow above 12
	u.Keys = 11
	ok, rows = C2.Grant(pl, "t", { { Kind = "Key", Amount = 3 } })
	eq(profiles[110].Underyard.Keys, 12)
	eq(rows[1].Amount, 1)
	eq(rows[1].Overflow.Amount, 2 * Cfg.Coffin.OverflowKeyShards)
	-- a declared dog arrives; a full dog storage parks the dog (§9.4 dogs are never converted) until there is room
	ok, rows = C2.Grant(pl, "t", { { Kind = "Dog", Id = "HW_BellPup", Rank = 2 } })
	truthy(rows[1].Dog, "declared through the rows")
	dogFree = false
	ok, rows = C2.Grant(pl, "t", { { Kind = "Dog", Id = "HW_BellPup", Rank = 2, Source = "Seal" } })
	truthy(ok and rows[1].Pending == true and rows[1].Reason == "Full" and not rows[1].Converted, "dog storage full: parked")
	eq(#profiles[110].Underyard.PendingDogs, 1)
	eq(profiles[110].Underyard.PendingDogs[1].Id, "HW_BellPup")
	eq(pl:GetAttribute("UyPendingDogs"), 1, "attribute for the client")
	local okD, why = C2.DeliverPendingDogs(pl, profiles[110].Underyard.PendingDogs)
	truthy(okD and #why == 0, "still full: nothing delivered")
	eq(#profiles[110].Underyard.PendingDogs, 1, "still waiting")
	dogFree = true
	local dogsBefore = 0
	for _ in pairs(profiles[110].Dogs) do
		dogsBefore += 1
	end
	local okD2, delivered = C2.DeliverPendingDogs(pl, profiles[110].Underyard.PendingDogs)
	truthy(okD2 and #delivered == 1 and delivered[1].Dog and delivered[1].Dog.DogId == "HW_BellPup", "delivered with room")
	eq(#profiles[110].Underyard.PendingDogs, 0, "list emptied")
	local dogsAfter = 0
	for _ in pairs(profiles[110].Dogs) do
		dogsAfter += 1
	end
	eq(dogsAfter, dogsBefore + 1)
	eq(pl:GetAttribute("UyPendingDogs"), 0)
	truthy(not C2.DeliverPendingDogs(pl, {}), "nothing to deliver")
	-- a waiting list at its cap converts as before
	dogFree = false
	profiles[110].Underyard.PendingDogs = {}
	for i = 1, Cfg.Limits.PendingDogs do
		profiles[110].Underyard.PendingDogs[i] = { Id = "HW_BellPup", Rank = 2, Source = "t", At = 1 }
	end
	ok, rows = C2.Grant(pl, "t", { { Kind = "Dog", Id = "HW_BellPup", Rank = 2 } })
	truthy(rows[1].Converted and rows[1].Reason == "Full", "full waiting list converts")
	profiles[110].Underyard.PendingDogs = {}
	dogFree = true
	-- resonance keys respect the per-day cap
	u = profiles[110].Underyard
	u.Keys = 0
	C2.Grant(pl, "t", { { Kind = "Key", Amount = 1, Source = "Resonance" }, { Kind = "Key", Amount = 1, Source = "Resonance" },
		{ Kind = "Key", Amount = 1, Source = "Resonance" } })
	eq(profiles[110].Underyard.Keys, 2, "2 resonance keys per day")
end)

test("Dex II claims, the tailor, journal", function()
	local pl = newProfile(111, true)
	call("C2Hello", pl)
	local p = profiles[111]
	p.DogDex = { HW_BellPup = true, HW_CandleCorgi = true }
	local ok, res = call("C2DexClaim", pl, { Count = 3 })
	eq(res, "Discover more Underyard dogs first")
	profiles[111].DogDex.HW_CoffinPug = true -- (the failed claim rolled back: the profile table was replaced)
	ok, res = call("C2DexClaim", pl, { Count = 3 })
	truthy(ok, tostring(res))
	eq(profiles[111].Underyard.Keys, 1)
	eq(shards(111), 300)
	ok, res = call("C2DexClaim", pl, { Count = 3 })
	eq(res, "Reward already claimed")
	ok, res = call("C2DexClaim", pl, { Count = 4 })
	eq(res, "Invalid reward")
	-- tailor
	ok, res = call("C2Craft", pl, { Id = "uy_spirit_fence" })
	eq(res, "Not enough fragments")
	profiles[111].Underyard.Fragments = 200
	ok, res = call("C2Craft", pl, { Id = "uy_spirit_fence" })
	truthy(ok, tostring(res))
	eq(profiles[111].Underyard.Fragments, 155)
	ok, res = call("C2Craft", pl, { Id = "uy_spirit_fence" })
	eq(res, "You already own this cosmetic")
	eq(profiles[111].Underyard.Fragments, 155, "nothing spent")
	ok, res = call("C2Craft", pl, { Id = "UY_BellReaper" })
	eq(res, "This skin only comes from the Dex II")
	ok, res = call("C2Craft", pl, { Id = "UY_Laughsaw" })
	eq(res, "This cosmetic is not available yet")
	ok, res = call("C2Craft", pl, { Id = "UY_TVHead" })
	truthy(ok, tostring(res))
	eq(profiles[111].Underyard.Fragments, 65)
	-- journal
	ok, res = call("C2Journal", pl, { Key = "seal5" })
	eq(res, "This entry is still locked")
	ok = call("C2Journal", pl, { Key = "chapter1" })
	truthy(ok)
	eq(profiles[111].Underyard.JournalRead.chapter1, true)
end)

test("Gravekeeper rewards for Chapter II players (difficulty shards, first-clear keys, finale)", function()
	local pl = newProfile(112, true)
	call("C2Hello", pl)
	profiles[112].Underyard.Rested.Pool = 0
	local ok, res = C2.BossReward(pl, 4, {})
	truthy(ok, tostring(res))
	eq(shards(112), 40)
	eq(profiles[112].Underyard.Keys, 1, "first full clear of IV")
	C2.BossReward(pl, 4, {})
	eq(profiles[112].Underyard.Keys, 1, "only once")
	eq(shards(112), 80)
	ok, res = C2.BossReward(pl, 5, { Finale = true })
	truthy(ok and res.FinaleFirst, "finale first clear")
	local u = profiles[112].Underyard
	eq(u.Keys, 1 + 1 + 3, "V first clear + finale 3")
	eq(shards(112), 80 + 70 + 250)
	eq(profiles[112].Cosmetics.LastBark2026, true)
	eq(u.Boss.FinaleClears, 1)
	truthy(u.Journal.finale, "journal finale")
	ok, res = C2.BossReward(pl, 5, { Finale = true })
	truthy(ok and not res.FinaleFirst, "repeat")
	eq(profiles[112].Underyard.Boss.FinaleClears, 2)
	local stranger = newProfile(113, false)
	call("C2Hello", stranger)
	ok, res = C2.BossReward(stranger, 5, {})
	eq(ok, false)
end)

test("progress queue: contracts, stats, perfect streak shards with the minute cap", function()
	local pl = newProfile(114, true)
	call("C2Hello", pl)
	local u = profiles[114].Underyard
	u.Rested.Pool = 0
	u.Tutorial.Done = true
	u.Daily.Contracts.List = { { Id = "Perfect", Goal = 40, Progress = 0, Claimed = false },
		{ Id = "Echo", Goal = 15, Progress = 0, Claimed = false }, { Id = "Resonance", Goal = 150, Progress = 0, Claimed = false } }
	for _ = 1, 30 do
		C2.StreakHit(pl, true)
	end
	C2.StreakHit(pl, false)
	for _ = 1, 4 do
		C2.StreakHit(pl, true)
	end
	C2.Progress(pl, "Echo", 15)
	C2.Progress(pl, "Trial", 1)
	C2.FlushNow(pl)
	u = profiles[114].Underyard
	eq(u.Stats.Perfect, 34)
	eq(u.Stats.Streaks, 6, "30 consecutive -> 6 streaks")
	eq(u.Daily.Contracts.List[1].Progress, 34)
	eq(u.Daily.Contracts.List[2].Progress, 15)
	eq(u.Stats.Trials, 1)
	eq(shards(114), 10, "6 streaks x 2 = 12, capped at 10 per minute")
	eq(u.Daily.Resonance, 34 + 6 * 3 + 15 * 4 + 60)
	eq(u.Daily.Contracts.List[3].Progress, 150)
end)

print(string.format("chapter2_feature: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("chapter2_feature tests failed")
end
