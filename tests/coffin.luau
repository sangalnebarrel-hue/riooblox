--!nolint
-- THE BLACK COFFIN · server: lune run tests/coffin.luau
-- Runs the real ServerScriptService.Halloween.Coffin on the real Chapter2.luau against a fake Core (transactions with
-- rollback, as tests/chapter2_feature.luau): request + prompt registration, every refusal (closed, not eligible, far,
-- cooldown, key, shards, full dog storage) with nothing spent, the price, key use and key refund, the H16 crown roll,
-- the H12 bonus roll and its +25% conversions, duplicate / full-storage conversion, the onboarding's forced showcase
-- find, the C2Coffin / C2CoffinNear / C2CoffinRefused signals, the Hollow King's hand-off to SecretReveal and the
-- server-wide C2Announce on the show's reveal beat, the Studio preview, CoffinConfig.Beats, and the distribution of
-- Coffin.Plan and of real openings against Chapter2Config's odds.
local L = require("./lib/economy_env")
local Vector3 = require("@lune/roblox").Vector3

local Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Rules = L.Require("ReplicatedStorage.Halloween.Chapter2Rules")
local CC = L.Require("ReplicatedStorage.Halloween.CoffinConfig")
local Layout = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local HConfig = L.Require("ReplicatedStorage.Halloween.Config")
local H = L.Require("ServerScriptService.Economy.Features.Halloween")
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

local DAY = 86400
local START = Rules.UnixFromDate(2026, 10, 20)
L.Time = START + 3 * DAY + 3600

-- every Random.new() gets its own stream (economy_env seeds a missing seed with 1)
local baseRandom = L.Random.new
local streams = 0
L.Random.new = function(seed)
	if seed == nil then
		streams += 1
		seed = 7919 * streams + 13
	end
	return baseRandom(seed)
end

---------------------------------------------------------------------------------------------------------------------
-- content stand-ins (WP-K1 / K2 / K3 ids)
---------------------------------------------------------------------------------------------------------------------
local itemDefs = {}
for _, id in ipairs(Cfg.Finds.Order) do
	itemDefs[id] = { Id = id, BaseDropChance = 1e-3 }
end
local itemsFull = false
L.Overrides["ServerScriptService/Economy/ItemRules"] = {
	Definitions = itemDefs,
	Free = function()
		return not itemsFull
	end,
}
local catalog = {}
for _, id in ipairs(Cfg.Decor.Order) do
	catalog[id] = 1
end
L.Overrides["ReplicatedStorage/DogEconomy/DecorCatalog"] = {
	MaxOwned = function(id)
		return catalog[id] or 0
	end,
}
for _, id in ipairs(Cfg.Skins.Order) do
	HConfig.Skins.Names[id] = id
end
-- the Secret arrival (ServerScriptService.SecretReveal): records every hand-off
local arrivals = {}
local arrivalHas = true
L.Overrides["ServerScriptService/SecretReveal"] = {
	Has = function(id)
		return arrivalHas and id == "HW_HollowKing"
	end,
	Show = function(id, ground, facing, opts)
		table.insert(arrivals, { Id = id, Ground = ground, Facing = facing, Opts = opts })
		return {}
	end,
}
local C2 = L.Require("ServerScriptService.Halloween.Chapter2")
local Coffin = L.Require("ServerScriptService.Halloween.Coffin")
local realPlan = Coffin.Plan
-- the timed hand-off / announcements run when the test flushes them
local delayed = {}
Coffin.Delay = function(seconds, fn)
	table.insert(delayed, { T = seconds, Fn = fn })
end
local function flush()
	local list = delayed
	delayed = {}
	for _, d in ipairs(list) do
		d.Fn()
	end
	return list
end

---------------------------------------------------------------------------------------------------------------------
-- fake world + Core
---------------------------------------------------------------------------------------------------------------------
local SHRINE = Layout.Anchors.CoffinShrine
local function fakePlayer(uid, pos)
	local attrs = {}
	return { UserId = uid, Name = "P" .. uid, DisplayName = "Player" .. uid, Parent = true, Attrs = attrs, Pos = pos or SHRINE + Vector3.new(6, 0, 0),
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end }
end
local playerList = {}
L.Stubs.Players.GetPlayers = function()
	return playerList
end

local profiles, signals, handlers, prompts = {}, {}, {}, {}
local assetReady = {}
for _, id in ipairs(Cfg.Dogs.Order) do
	assetReady[id] = true
end
local dogFree = true
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
	OnRequest = function(action, fn, opts)
		handlers[action] = { Fn = fn, Cost = opts and opts.Cost }
	end,
	OnReady = function() end,
	Near = function(player, pos, range)
		return (player.Pos - pos).Magnitude <= range
	end,
	Root = function(player)
		return { Position = player.Pos }
	end,
	IsActive = function()
		return true
	end,
}
function core.State(player)
	return core.Players[player]
end
local transactions = 0
function core.Transact(player, label, fn, opts)
	opts = opts or {}
	transactions += 1
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
			local x = { ItemId = o.ItemId, ItemUid = "I" .. tostring(#p.Items + 1), Origin = o.Origin }
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
			local n = 0
			for _ in pairs(p.Dogs) do
				n += 1
			end
			local uid = "D" .. tostring(n + 1)
			p.Dogs[uid] = { DogUid = uid, DogId = id, Origin = "BuriedMoon" }
			return { DogUid = uid, DogId = id }
		end
		function ctx.Candy(n)
			h.Candy += n
			return n
		end
		function ctx.Stat(key, n)
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

local modules = { Chapter2 = C2 }
modules.Underyard = {
	Prompt = function(anchorName, props, fn)
		prompts[anchorName] = { Props = props, Fn = fn }
		return {}
	end,
}
modules.Coffin = Coffin
C2.Start(core, modules)
Coffin.Start(core, modules)

local windows = {}
Coffin.OpenWindow = function(player)
	table.insert(windows, player.UserId)
end

local function newPlayer(uid, chapter1, pos)
	local p = { UserId = uid, Resources = {}, Cosmetics = {}, Dogs = {}, Halloween = { Season = HConfig.Season, Candy = 0, Skins = {} } }
	if chapter1 ~= false then
		p.Halloween.Boss = { Best = 2 }
		p.Halloween.Cauldron = { Invested = 300 }
		p.Halloween.Stats = { Knocks = 7, BloodMoons = 1, Spots = 10 }
	end
	profiles[uid] = p
	local pl = fakePlayer(uid, pos)
	table.insert(playerList, pl)
	handlers.C2Hello.Fn(pl, {})
	return pl, p
end
local function give(pl, keys, shards)
	C2.Transact(pl, "test", function(p, u)
		u.Keys = keys
		p.Resources.BellShards = shards
	end)
end
local function prof(pl)
	return profiles[pl.UserId]
end
local function shards(pl)
	return prof(pl).Resources.BellShards or 0
end
local function signalsOf(kind, target)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == kind and (target == nil or s.Target == target) then
			table.insert(out, s)
		end
	end
	return out
end
-- (module code reads the real os.clock: the cooldown is switched off except in the test that checks it)
local clock = 1000
CC.Cooldown = 0
-- the request handler returns (ok, result); call it directly
local function request(pl)
	clock += 10
	signals = {}
	delayed = {}
	return handlers[CC.Request.Action].Fn(pl, {})
end
-- a scripted plan: main row (a Coffin.Table row key or a row table), crown / pug rows, pug roll
local function rowOf(key)
	for _, row in ipairs(Cfg.Coffin.Table) do
		if row.Key == key then
			local r = table.clone(row)
			r.Weight = nil
			if r.Min and r.Max then
				r.Amount = r.Max
				r.Min, r.Max = nil, nil
			end
			return r
		end
	end
	error("no coffin row " .. key)
end
local function script(mainKey, opts)
	opts = opts or {}
	Coffin.Plan = function(rng, forced)
		local plan = realPlan(rng, forced)
		if mainKey and not forced then
			plan.Main = rowOf(mainKey)
		end
		if opts.Crown then
			plan.Crown = rowOf(opts.Crown)
			plan.Crown.Bonus = "Crown"
		end
		if opts.Pug then
			plan.Pug = rowOf(opts.Pug)
			plan.Pug.Bonus = "Pug"
		end
		if opts.PugRoll then
			plan.PugRoll = opts.PugRoll
		end
		return plan
	end
end
local PRICE = Cfg.Coffin.Price

---------------------------------------------------------------------------------------------------------------------
-- tests
---------------------------------------------------------------------------------------------------------------------
test("the request and the shrine prompt are registered (localized prompt, Studio preview stays off)", function()
	truthy(handlers[CC.Request.Action], "C2CoffinOpen registered")
	eq(handlers[CC.Request.Action].Cost, CC.Request.Cost)
	eq(handlers[CC.Request.DebugAction], nil, "the preview request exists only in Studio")
	local prompt = prompts[CC.Anchor]
	truthy(prompt, "prompt on the CoffinShrine anchor")
	eq(prompt.Props.ActionText, "OPEN")
	eq(prompt.Props.ObjectText, "THE BLACK COFFIN")
	eq(prompt.Props.ActionTextRU, "ОТКРЫТЬ")
	eq(prompt.Props.ObjectTextRU, "ЧЁРНЫЙ ГРОБ")
	truthy(prompt.Props.HoldDuration > 0, "hold to open (no accidental spend)")
	eq(CC.Radius, 14)
	eq(Cfg.Proximity.Slack, 6)
end)

test("refusals: closed, not eligible, far, cooldown, busy — nothing is spent", function()
	local pl = newPlayer(201, true)
	give(pl, 3, 1000)
	HConfig.HalloweenChapter2Enabled = false
	local ok, err = request(pl)
	eq(ok, false)
	eq(err, "Chapter II is closed")
	HConfig.HalloweenChapter2Enabled = true
	local lazy = newPlayer(202, false)
	give(lazy, 3, 1000)
	ok, err = request(lazy)
	eq(err, "Finish Chapter I first")
	pl.Pos = SHRINE + Vector3.new(CC.Radius + Cfg.Proximity.Slack + 1, 0, 0)
	ok, err = request(pl)
	eq(err, "Come closer to the Black Coffin")
	pl.Pos = SHRINE + Vector3.new(CC.Radius + Cfg.Proximity.Slack - .5, 0, 0)
	script("Dust")
	ok = request(pl)
	truthy(ok, "inside radius + slack")
	-- the cooldown
	CC.Cooldown = 60
	signals = {}
	ok, err = handlers[CC.Request.Action].Fn(pl, {})
	eq(err, "Please wait a moment")
	CC.Cooldown = 0
	eq(prof(pl).Underyard.Keys, 2, "only the first opening spent a key")
	eq(shards(pl), 1000 - PRICE.Shards)
end)

test("refusals inside the write: no key, not enough shards, full dog storage (forced finds are fine)", function()
	local pl = newPlayer(203, true)
	script("Dust")
	give(pl, 0, 1000)
	local ok, err = request(pl)
	eq(ok, false)
	eq(err, "You need a Coffin Key")
	give(pl, 1, PRICE.Shards - 1)
	ok, err = request(pl)
	eq(err, "Not enough Bell Shards")
	eq(prof(pl).Underyard.Keys, 1, "the key stays")
	eq(shards(pl), PRICE.Shards - 1)
	give(pl, 1, 500)
	dogFree = false
	ok, err = request(pl)
	eq(err, "Make room in your dog storage first")
	eq(prof(pl).Underyard.Keys, 1)
	eq(shards(pl), 500)
	eq(prof(pl).Underyard.Coffins.Opened, 0)
	-- the prompt path: a refusal becomes a C2CoffinRefused signal and (keys / shards) the Underyard window
	dogFree = true
	give(pl, 0, 500)
	windows = {}
	clock += 10
	signals = {}
	prompts[CC.Anchor].Fn(pl)
	local refused = signalsOf("C2CoffinRefused", pl)
	eq(#refused, 1)
	eq(refused[1].Data.Text, "You need a Coffin Key")
	eq(refused[1].Data.Need, "Key")
	eq(#windows, 1, "the COFFIN tab opens")
	give(pl, 1, 10)
	clock += 10
	prompts[CC.Anchor].Fn(pl)
	eq(#windows, 2, "not enough shards also opens it")
end)

test("an opening costs 150 Bell Shards + 1 Coffin Key, records the result and advances the Coffin contract", function()
	local pl = newPlayer(204, true)
	give(pl, 2, 400)
	script("Bones")
	local u = prof(pl).Underyard
	local contract = nil
	for _, c in ipairs(u.Daily.Contracts.List) do
		if c.Id == "Coffin" then
			contract = c
		end
	end
	local ok, res = request(pl)
	truthy(ok, tostring(res))
	u = prof(pl).Underyard
	eq(u.Keys, 1)
	eq(shards(pl), 400 - PRICE.Shards)
	eq(prof(pl).Bones, 600, "bones row paid")
	eq(u.Coffins.Opened, 1)
	eq(u.Coffins.Last[1].Key, "Bones")
	eq(u.Coffins.Last[1].Rank, 1)
	eq(res.Message, "The Black Coffin opens")
	eq(res.Coffin.Keys, 1)
	eq(res.Coffin.Shards, 250)
	eq(pl.Attrs.CoffinKeys, 1, "attribute synced")
	if contract then
		local after = nil
		for _, c in ipairs(u.Daily.Contracts.List) do
			if c.Id == "Coffin" then
				after = c
			end
		end
		eq(after.Progress, 1, "Coffin contract")
	end
	-- the opener's show payload
	local mine = signalsOf("C2Coffin", pl)
	eq(#mine, 1)
	local d = mine[1].Data
	eq(d.UserId, 204)
	eq(d.Name, "Player204")
	eq(d.Rank, 1)
	eq(d.Rarity, "Common")
	eq(d.Tier, 1)
	eq(d.Main.Kind, "Bones")
	eq(d.Main.Amount, 600)
	eq(#d.Rows, 1)
	eq(d.Converted, false)
	eq(d.Keys, 1)
	eq(d.Shards, 250)
	truthy(type(d.Seed) == "number" and d.Seed >= 1 and d.Seed < 2147483647, "seed")
	truthy(type(d.At) == "number", "server time")
	-- the shards refund row is DR-exempt and the key refund row gives the key back
	script("Shards")
	give(pl, 1, 300)
	ok, res = request(pl)
	eq(shards(pl), 300 - PRICE.Shards + 90, "refund row (Max 90 scripted), exempt from DR")
	script("Key")
	give(pl, 1, 300)
	ok, res = request(pl)
	eq(prof(pl).Underyard.Keys, 1, "key spent and refunded")
	eq(res.Coffin.Main.Kind, "Key")
	eq(res.Coffin.Rank, 3)
	eq(#signalsOf("C2Key", pl), 1, "C2Key fly-in for the refund")
	-- a refund key above the cap becomes shards (Overflow)
	give(pl, Cfg.Coffin.MaxKeys, 300)
	C2.Transact(pl, "t", function(_p, u2)
		u2.Keys = Cfg.Coffin.MaxKeys
	end)
	ok, res = request(pl)
	-- (12 - 1 + 1 = 12: room for the refund after the spend, no overflow)
	eq(prof(pl).Underyard.Keys, Cfg.Coffin.MaxKeys)
	eq(res.Coffin.Main.Overflow, nil)
end)

test("H16 CROWN OF THE UNDERYARD: a stored crown roll adds one showcase find, consumed once", function()
	local pl = newPlayer(205, true)
	give(pl, 3, 1000)
	C2.Transact(pl, "t", function(_p, u)
		u.Coffins.Crown.Rolls = 1
	end)
	script("Dust", { Crown = "uy_wax_hand" })
	local ok, res = request(pl)
	truthy(ok, tostring(res))
	eq(#res.Rewards, 2)
	eq(res.Rewards[2].Bonus, "Crown")
	eq(res.Rewards[2].Kind, "Find")
	eq(res.Rewards[2].Id, "uy_wax_hand")
	truthy(res.Rewards[2].Item, "the find was minted")
	eq(prof(pl).Underyard.Coffins.Crown.Rolls, 0)
	truthy(prof(pl).Underyard.Owned.Finds.uy_wax_hand, "owned")
	eq(prof(pl).Underyard.Coffins.Opened, 1, "a bonus roll is not a second opening")
	ok, res = request(pl)
	eq(#res.Rewards, 1, "no stored roll: no bonus")
	-- the real crown rows are always showcase finds
	for i = 1, 300 do
		local plan = realPlan(L.Random.new(5000 + i), false)
		eq(plan.Crown.Group, "Find")
		eq(plan.Pug.Group, "Find")
	end
end)

test("H12 COFFIN SENSE: the bonus find roll needs the pug in the yard team; duplicate conversions +25%", function()
	local pl = newPlayer(206, true)
	give(pl, 4, 2000)
	script("Dust", { Pug = "uy_black_feather", PugRoll = .05 })
	local ok, res = request(pl)
	eq(#res.Rewards, 1, "no pug in the team: no bonus")
	prof(pl).Dogs.D1 = { DogUid = "D1", DogId = "HW_CoffinPug", AssignedSlot = "DigSlot_1", State = "Working" }
	ok, res = request(pl)
	eq(#res.Rewards, 2)
	eq(res.Rewards[2].Bonus, "Pug")
	eq(res.Rewards[2].Id, "uy_black_feather")
	script("Dust", { Pug = "uy_black_feather", PugRoll = Cfg.Dogs.Defs.HW_CoffinPug.BonusFindChance + .001 })
	ok, res = request(pl)
	eq(#res.Rewards, 1, "roll above the chance")
	-- a duplicate find with the pug: 80 shards + 150 dust, +25% each
	script("uy_black_feather")
	local before = shards(pl)
	ok, res = request(pl)
	local main = res.Rewards[1]
	eq(main.Converted, true)
	eq(main.Reason, "Owned")
	eq(main.Conversion[1].Kind, "Shards")
	eq(main.Conversion[1].Amount, 100)
	eq(main.Conversion[2].Kind, "Dust")
	eq(main.Conversion[2].Amount, 188)
	eq(shards(pl), before - PRICE.Shards + 100)
	eq(res.Coffin.Duplicate, true)
	eq(res.Coffin.Converted, true)
end)

test("duplicates convert (§9.4): finds, plot cosmetics, pickaxe skins, a full item storage", function()
	local pl = newPlayer(207, true)
	give(pl, 8, 5000)
	script("uy_hollow_heart")
	local ok, res = request(pl)
	eq(res.Rewards[1].Converted, nil, "first copy delivered")
	ok, res = request(pl)
	local r = res.Rewards[1]
	eq(r.Converted, true)
	eq(#r.Conversion, 3, "a Legendary find also gives fragments")
	eq(r.Conversion[3].Kind, "Fragments")
	eq(r.Conversion[3].Amount, Cfg.Duplicates.Find.LegendaryFragments)
	script("uy_moon_statue")
	request(pl)
	ok, res = request(pl)
	r = res.Rewards[1]
	eq(r.Converted, true)
	eq(r.Conversion[1].Kind, "Fragments")
	eq(r.Conversion[1].Amount, Cfg.Duplicates.Decor.Fragments)
	eq(r.Conversion[2].Amount, Cfg.Duplicates.Decor.Dust)
	eq(res.Coffin.Rank, 5, "Moon Statue is Mythic")
	script("UY_TVHead")
	request(pl)
	ok, res = request(pl)
	r = res.Rewards[1]
	eq(r.Conversion[1].Amount, Cfg.Duplicates.Skin.Fragments)
	itemsFull = true
	script("uy_coffin_nail")
	ok, res = request(pl)
	r = res.Rewards[1]
	eq(r.Converted, true)
	eq(r.Reason, "Full", "a full item storage converts like a duplicate")
	eq(res.Coffin.Duplicate, false, "storage full is not a duplicate")
	itemsFull = false
end)

test("the onboarding's first coffin rolls a showcase find (forced group) and completes the step", function()
	local pl = newPlayer(208, true)
	C2.MarkEntered(pl)
	C2.Transact(pl, "t", function(_p, u, ctx)
		u.Tutorial.Step = 2
		u.Tutorial.Mark = 0
	end)
	eq(C2.TutorialEventNow(pl, "Toll"), true)
	eq(prof(pl).Underyard.Tutorial.Step, 3)
	eq(pl.Attrs.UyTutorial, 3)
	truthy(C2.ForceCoffinFind(pl), "step 3 forces the find group")
	Coffin.Plan = realPlan
	local ok, res = request(pl) -- the tutorial granted 1 key + 150 shards
	truthy(ok, tostring(res))
	eq(res.Coffin.Forced, true)
	eq(res.Coffin.Main.Kind, "Find")
	eq(prof(pl).Underyard.Tutorial.Step, 4, "coffin opened -> next step")
	eq(prof(pl).Underyard.Keys, 0)
	-- a forced opening never needs dog storage room
	dogFree = false
	C2.Transact(pl, "t", function(_p, u)
		u.Tutorial.Step = 3
		u.Tutorial.Mark = u.Coffins.Opened
		u.Keys = 1
	end)
	give(pl, 1, 200)
	ok, res = request(pl)
	truthy(ok, tostring(res))
	eq(res.Coffin.Main.Group, "Find")
	dogFree = true
	-- the forced plan never leaves the group
	for i = 1, 500 do
		eq(realPlan(L.Random.new(900 + i), true).Main.Group, "Find")
	end
end)

test("dogs: declared supply, the Secret announce server-wide, Mythic announce, conversions stay quiet", function()
	for _, other in ipairs(playerList) do
		other.Pos = SHRINE + Vector3.new(0, 0, 900) -- everyone from earlier tests leaves the square
	end
	local opener = newPlayer(209, true)
	local nearby = newPlayer(210, true, SHRINE + Vector3.new(40, 0, 10))
	local far = newPlayer(211, true, SHRINE + Vector3.new(400, 0, 0))
	give(opener, 12, 9000)
	script("HW_HollowKing")
	local ok, res = request(opener)
	truthy(ok, tostring(res))
	eq(res.Rewards[1].Kind, "Dog")
	eq(res.Rewards[1].Dog.DogId, "HW_HollowKing")
	eq(res.Coffin.Rank, 6)
	eq(res.Coffin.Rarity, "Secret")
	eq(#signalsOf("C2Announce", "all"), 0, "nothing is announced before the show reveals it")
	eq(#delayed, 1, "the hand-off is scheduled")
	local beats6 = CC.Beats(6)
	truthy(math.abs(delayed[1].T - beats6.Handoff) < .01, "hand-off on the show's beat")
	eq(res.Coffin.Arrival, true)
	eq(res.Coffin.Handoff, res.Coffin.At + beats6.Handoff)
	arrivals = {}
	flush()
	eq(#arrivals, 1, "SecretReveal.Show")
	eq(arrivals[1].Id, "HW_HollowKing")
	eq(arrivals[1].Opts.Venue, "Coffin")
	eq(arrivals[1].Opts.By, "Player209")
	local ground, facing = Coffin.KingSpot()
	eq(arrivals[1].Ground, ground)
	eq(arrivals[1].Facing, facing)
	local ann = signalsOf("C2Announce", "all")
	eq(#ann, 1)
	eq(ann[1].Data.Arrival, true)
	eq(ann[1].Data.RevealAt, res.Coffin.At + beats6.Reveal)
	eq(ann[1].Data.Kind, "HollowKing")
	eq(ann[1].Data.Name, "Player209")
	eq(ann[1].Data.UserId, 209)
	eq(ann[1].Data.DogId, "HW_HollowKing")
	local near = signalsOf("C2CoffinNear")
	eq(#near, 1, "only the nearby player gets the lighter show")
	eq(near[1].Target, nearby)
	eq(near[1].Data.Main.Id, "HW_HollowKing")
	eq(near[1].Data.Seed, res.Coffin.Seed, "same seed: the same show")
	eq(near[1].Data.Handoff, res.Coffin.Handoff, "the lighter show knows the hand-off")
	eq(near[1].Data.Arrival, true)
	eq(#signalsOf("C2Coffin", far), 0)
	-- Mythic dog: announced on the lid's opening
	script("HW_Bridehound")
	ok, res = request(opener)
	eq(#signalsOf("C2Announce", "all"), 0)
	eq(#delayed, 1)
	truthy(math.abs(delayed[1].T - CC.Beats(5).Reveal) < .01, "announce on the reveal beat")
	flush()
	ann = signalsOf("C2Announce", "all")
	eq(#ann, 1)
	eq(ann[1].Data.Kind, "Mythic")
	eq(ann[1].Data.DogId, "HW_Bridehound")
	-- a dog whose model is not in the place converts (no announce)
	assetReady.HW_BellkeeperWolf = false
	script("HW_BellkeeperWolf")
	local before = shards(opener)
	ok, res = request(opener)
	eq(res.Rewards[1].Converted, true)
	eq(res.Rewards[1].Reason, "Unavailable")
	eq(shards(opener), before - PRICE.Shards + Cfg.Duplicates.DogShardsPerRank * 5)
	eq(#delayed, 0, "a converted reward is not announced")
	eq(#signalsOf("C2Announce"), 0)
	assetReady.HW_BellkeeperWolf = true
	-- ordinary rewards are not announced
	script("Fragments")
	request(opener)
	eq(#delayed, 0)
	flush()
	eq(#signalsOf("C2Announce"), 0)
	-- a Mythic cosmetic is
	script("UY_NastyOctopus")
	request(opener)
	flush()
	ann = signalsOf("C2Announce", "all")
	eq(#ann, 1)
	eq(ann[1].Data.RewardKind, "Skin")
	eq(ann[1].Data.DogId, nil)
	-- a duplicate dog is still a dog
	script("HW_BellPup")
	request(opener)
	ok, res = request(opener)
	eq(res.Rewards[1].Converted, nil)
	local pups = 0
	for _, d in pairs(prof(opener).Dogs) do
		if d.DogId == "HW_BellPup" then
			pups += 1
		end
	end
	eq(pups, 2)
end)

test("the Studio preview only presents: nothing granted or spent", function()
	local pl = newPlayer(212, true)
	give(pl, 1, 200)
	signals = {}
	delayed = {}
	arrivals = {}
	local ok, res = Coffin.Preview(pl, { Rank = 6 })
	truthy(ok)
	eq(res.Coffin.Preview, true)
	eq(res.Coffin.Main.Id, "HW_HollowKing")
	eq(prof(pl).Underyard.Keys, 1)
	eq(shards(pl), 200)
	flush()
	eq(#arrivals, 1, "the preview shows the arrival too")
	eq(#signalsOf("C2Announce"), 0, "previews are never announced")
	ok, res = Coffin.Preview(pl, nil)
	eq(res.Coffin.Rank, 1)
end)

test("Coffin.Plan matches Chapter2Config's odds (200 000 rolls) and every row is well-formed", function()
	local groups = Rules.CoffinGroups(Cfg)
	local count, rows = {}, {}
	local N = 200000
	local rng = L.Random.new(424242)
	for _ = 1, N do
		local plan = realPlan(rng, false)
		local main = plan.Main
		count[main.Group] = (count[main.Group] or 0) + 1
		rows[main.Key] = (rows[main.Key] or 0) + 1
		truthy(main.Weight == nil, "no weight in a rolled row")
		if main.Min then
			error("Min left in a rolled row")
		end
	end
	for group, p in pairs(groups) do
		local expected = N * p
		local sigma = math.sqrt(N * p * (1 - p))
		local got = count[group] or 0
		truthy(math.abs(got - expected) <= 4.5 * sigma + 2, string.format("%s: %d vs %.1f (sigma %.1f)", group, got, expected, sigma))
	end
	-- per-row check of the frequent rows (each find of a tier, each decor)
	for _, row in ipairs(Cfg.Coffin.Table) do
		local p = Rules.CoffinChance(row, Cfg)
		if p > .001 then
			local expected = N * p
			local sigma = math.sqrt(N * p * (1 - p))
			truthy(math.abs((rows[row.Key] or 0) - expected) <= 4.5 * sigma + 2, row.Key)
		end
	end
	eq(Rules.CoffinTotal(Cfg), Cfg.Coffin.TotalWeight)
	-- rare tails exist in the table with the §9.3 weights
	eq(Rules.CoffinChance(rowOf("HW_HollowKing"), Cfg) * 0 + Cfg.Dogs.CoffinWeight.HW_HollowKing, 4)
	truthy(math.abs(groups.Secret - 4 / 100000) < 1e-12, "1 in 25 000")
	truthy(math.abs(groups.Mythic - 64 / 100000) < 1e-12, "Mythic dogs .064%")
end)

test("real openings follow the odds and pay exactly what they report (4 000 openings)", function()
	Coffin.Plan = realPlan
	local pl, p = newPlayer(213, true)
	local N = 4000
	local count = {}
	local dust0 = 0
	for i = 1, N do
		C2.Transact(pl, "t", function(pp, u)
			u.Keys = 1
			pp.Resources.BellShards = 150
			pp.Resources.LuckyDust = 0
			-- keep the profile small: forget owned finds / decor so most rows deliver, and clear the dogs
			table.clear(u.Owned.Finds)
			table.clear(u.Owned.Decor)
			pp.Items = {}
			pp.Decor = { Owned = {} }
			pp.Dogs = {}
			pp.Halloween.Skins = {}
		end)
		local ok, res = request(pl)
		truthy(ok, tostring(res))
		local main = res.Coffin.Main
		local group = nil
		for _, row in ipairs(Cfg.Coffin.Table) do
			if row.Key == (main.Key or main.Id or main.Kind) then
				group = row.Group
			end
		end
		group = group or (main.Kind == "Dust" and "Dust")
		count[res.Coffin.Rank] = (count[res.Coffin.Rank] or 0) + 1
		-- what the reply reports is what the profile got
		local pr = prof(pl)
		if main.Kind == "Dust" and not main.Converted then
			eq(pr.Resources.LuckyDust, main.Amount, "dust paid")
			truthy(main.Amount >= 60 and main.Amount <= 120, "dust 60-120")
		elseif main.Kind == "Shards" then
			eq(pr.Resources.BellShards, main.Amount, "refund paid")
			truthy(main.Amount >= 40 and main.Amount <= 90, "shards 40-90")
		elseif main.Kind == "Fragments" then
			truthy(main.Amount >= 1 and main.Amount <= 3, "fragments 1-3")
		end
		eq(pr.Underyard.Coffins.Opened, i)
	end
	-- rank distribution against the table (rank 1 = Dust/Shards/Bones = 47.0%, finds of the Common tier rank 2 ...)
	local byRank = {}
	for _, row in ipairs(Cfg.Coffin.Table) do
		byRank[row.Rank] = (byRank[row.Rank] or 0) + Rules.CoffinChance(row, Cfg)
	end
	for rank, prob in pairs(byRank) do
		if prob > .01 then
			local expected = N * prob
			local sigma = math.sqrt(N * prob * (1 - prob))
			truthy(math.abs((count[rank] or 0) - expected) <= 4.5 * sigma + 2, string.format("rank %d: %d vs %.1f", rank, count[rank] or 0, expected))
		end
	end
	eq(#prof(pl).Underyard.Coffins.Last, Cfg.Coffin.Last, "Last stays capped")
end)

test("the opening is one transaction (plus the queue flush) and the profile stays valid", function()
	local pl = newPlayer(214, true)
	give(pl, 2, 400)
	script("Dust")
	C2.QueueShards(pl, 3, "Echo")
	local before = transactions
	local ok = request(pl)
	truthy(ok)
	eq(transactions - before, 2, "queue flush + the opening")
	eq(shards(pl), 400 + 3 - PRICE.Shards, "queued streak shards written before the opening")
	F.Validate(Rstub, prof(pl))
end)

test("without the arrival (no SecretReveal entry) the king is still announced, flagged for the client's own show", function()
	for _, other in ipairs(playerList) do
		other.Pos = SHRINE + Vector3.new(0, 0, 900)
	end
	local pl = newPlayer(215, true)
	give(pl, 2, 400)
	arrivalHas = false
	arrivals = {}
	script("HW_HollowKing")
	local ok, res = request(pl)
	truthy(ok, tostring(res))
	eq(res.Coffin.Arrival, false)
	flush()
	eq(#arrivals, 0, "no SecretReveal.Show without an arrival")
	local ann = signalsOf("C2Announce", "all")
	eq(#ann, 1)
	eq(ann[1].Data.Kind, "HollowKing")
	eq(ann[1].Data.Arrival, false)
	arrivalHas = true
	-- a converted king (model not in the place) is neither shown nor announced
	assetReady.HW_HollowKing = false
	ok, res = request(pl)
	eq(res.Rewards[1].Converted, true)
	eq(res.Coffin.Arrival, nil)
	eq(#delayed, 0)
	assetReady.HW_HollowKing = true
end)

test("CoffinConfig.Beats: ordered beats per rank, the Secret's blackout and hand-off, slow motion only for Mythic", function()
	for rank = 1, 6 do
		local b = CC.Beats(rank)
		eq(b.Rank, rank)
		eq(#b.Chains, 3)
		local last = 0
		for k = 1, 3 do
			truthy(b.Chains[k].Tighten >= last and b.Chains[k].Snap > b.Chains[k].Tighten, "chain " .. k)
			last = b.Chains[k].Snap
		end
		truthy(b.Padlock > last and b.RattleFrom >= last and b.RattleTo > b.RattleFrom, "padlock / rattle")
		truthy(b.Open > b.RattleTo, "the lid opens after the rattle")
		truthy(b.Card > b.Open and b.End >= b.Card, "card after the lid")
		eq(b.SkipAfter, b.Open, "skippable after the lid opens")
		eq(b.Shockwave, rank >= 2)
		if rank == 5 then
			eq(#b.Lightning, 3)
			truthy(b.SlowFrom and b.SlowTo > b.SlowFrom, "Mythic slow motion")
			truthy(b.RealEnd > b.End, "slow motion stretches the screen time")
			for _, t in ipairs({ 0, b.SlowFrom, (b.SlowFrom + b.SlowTo) / 2, b.SlowTo, b.End }) do
				truthy(math.abs(CC.ShowTime(b, CC.RealTime(b, t)) - t) < 1e-9, "RealTime / ShowTime inverse at " .. t)
			end
		else
			eq(b.SlowFrom, nil)
			eq(b.RealEnd, b.End)
		end
		if rank < 5 then
			eq(#b.Lightning, 0)
		end
		if rank == 6 then
			eq(b.Secret, true)
			truthy(b.Blackout > b.RattleTo and b.Lift > b.Blackout and b.Open > b.Lift, "blackout before the lid")
			truthy(b.Handoff > b.Open and b.Reveal > b.Handoff and b.Release > b.Handoff, "hand-off after the lid")
		else
			eq(b.Secret, false)
			eq(b.Reveal, b.Open)
		end
	end
	-- a rarer reward takes longer
	truthy(CC.Beats(1).Open < CC.Beats(5).Open, "pace by rarity")
	-- the king stands in front of the coffin's foot, on the floor, facing the tower
	local ground, facing = Coffin.KingSpot()
	local shrine = Layout.Square.CoffinShrine
	local loc = shrine:PointToObjectSpace(ground)
	truthy(loc.Z < -(CC.Model.Length / 2), "in front of the foot")
	truthy(math.abs(loc.Y) < .1, "on the floor")
	truthy(facing:Dot(Layout.Square.Tower.Centre - shrine.Position) > 0, "faces the tower")
end)

print(string.format("coffin: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("coffin tests failed")
end
