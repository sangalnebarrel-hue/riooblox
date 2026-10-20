--!nocheck
-- CHAPTER I rebalance (WP-E, docs/halloween2/DESIGN.md §12): lune run tests/chapter1_rebalance.luau
-- Runs the real src modules (tests/lib/economy_env.luau) with small stubs (the place-only RS.Halloween.State /
-- Remotes folders, fake players, a fake Halloween core that runs the real Core grant ctx):
--  * rare prize philosophy: every rescaled Pumpkin / Cursed Pumpkin probability = old x class factor within 1e-6,
--    weights sum to 1e6, the rest is the Lucky Dust filler; the originals stay in Config.Rebalance.Was;
--  * every §12.2 lever has its new value (and the boss dog drop follows the philosophy per dog);
--  * the per-minute candy cap is applied to the BASE amount, before the rush / Blood Moon multipliers;
--  * TRICK: escalating price within a UTC day (140, 170, 200, 240 cap), reset on the next day, MaxPrice guard;
--  * brew catch-up: ready = min(StartedAt + 7 d, 2026-10-31 18:00 UTC), never sooner than StartedAt + 1 d;
--  * the exorcism block goes only to players active in the Dead Yard in the last 180 s;
--  * EarnCandy is not progressed by quest / reward candy;
--  * Dust rows through EventBlocks (Rows / Freeze / Apply / Odds), frozen pools of owned blocks untouched;
--  * passive yard event mutations x PassiveScale.
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local DAY = 86400
local OCT20 = 1792454400 -- 2026-10-20 00:00 UTC
local DEADLINE = 1793469600 -- 2026-10-31 18:00 UTC
local NOW = OCT20 + 9 * 3600
L.Time = NOW

---------------------------------------------------------------------------------------------------------------------
-- place-only instances: RS.Halloween.State (attributes + child folders) and Remotes (no Signal: Core.Signal no-ops)
---------------------------------------------------------------------------------------------------------------------
local function fakeFolder(name)
	local f = { Name = name, _attrs = {}, _children = {} }
	function f:GetAttribute(k)
		return self._attrs[k]
	end
	function f:SetAttribute(k, v)
		self._attrs[k] = v
	end
	function f:FindFirstChild(n)
		return self._children[n]
	end
	function f:WaitForChild(n)
		return self._children[n]
	end
	function f:GetAttributeChangedSignal()
		return { Connect = function() return { Disconnect = function() end } end }
	end
	return f
end
local State = fakeFolder("State")
State._children.Exorcism = fakeFolder("Exorcism")
local Remotes = fakeFolder("Remotes")

local realRS = L.Game.ReplicatedStorage
local realHW = realRS.Halloween
local function hwChild(n)
	if n == "State" then
		return State
	elseif n == "Remotes" then
		return Remotes
	end
	return realHW:FindFirstChild(n)
end
local HW = setmetatable({
	FindFirstChild = function(_, n) return hwChild(n) end,
	WaitForChild = function(_, n) return hwChild(n) end,
}, { __index = realHW })
local function rsChild(n)
	if n == "Halloween" then
		return HW
	end
	return realRS:FindFirstChild(n)
end
L.Stubs.ReplicatedStorage = setmetatable({
	Halloween = HW,
	FindFirstChild = function(_, n) return rsChild(n) end,
	WaitForChild = function(_, n) return rsChild(n) end,
}, { __index = realRS })

local players = {}
L.Stubs.Players.GetPlayers = function()
	return players
end
L.Overrides["ServerScriptService/Economy/Runtime"] = {
	Views = {}, Ready = function() return true end, Allow = function() return true end,
	Engine = { Guid = function() return "g" end, AssetReady = function() return false end },
}
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end }

local C = L.Require("ReplicatedStorage.Halloween.Config")
local DropRates = L.Require("ReplicatedStorage.Halloween.DropRates")
local Rules1 = L.Require("ReplicatedStorage.Halloween.Chapter1Rules")
local Shared = L.Require("ReplicatedStorage.Halloween.Shared")
local Feature = L.Require("ServerScriptService.Economy.Features.Halloween")
local R = L.Require("ServerScriptService.Economy.Rules")
local Core = L.Require("ServerScriptService.Halloween.Core")

local passed, failed = 0, 0
local function test(name, fn)
	L.Time = NOW
	table.clear(State._attrs)
	State._children.BloodMoon = nil
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
local function near(a, b, tol, msg)
	if math.abs(a - b) > tol then
		error(string.format("%s expected %.12g got %.12g (tolerance %g)", msg or "", b, a, tol), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function errors(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then
		error((msg or "") .. " expected an error", 2)
	end
	if pattern and not string.find(tostring(err), pattern, 1, true) then
		error((msg or "") .. " wrong error: " .. tostring(err), 2)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- fixtures
---------------------------------------------------------------------------------------------------------------------
local function fakePlayer(uid, pos)
	local attrs = {}
	local root = { Position = pos, Name = "HumanoidRootPart" }
	function root:IsA(c)
		return c == "BasePart"
	end
	local hum = { Health = 100 }
	local character = { _attrs = {} }
	function character:FindFirstChildOfClass(c)
		return c == "Humanoid" and hum or nil
	end
	function character:FindFirstChild(n)
		return n == "HumanoidRootPart" and root or nil
	end
	function character:GetAttribute(k)
		return self._attrs[k]
	end
	function character:SetAttribute(k, v)
		self._attrs[k] = v
	end
	local p = { UserId = uid, Name = "Player" .. uid, DisplayName = "Player" .. uid, Character = character, Parent = true, Root = root }
	function p:GetAttribute(k)
		return attrs[k]
	end
	function p:SetAttribute(k, v)
		attrs[k] = v
	end
	function p:IsA(c)
		return c == "Player"
	end
	return p
end

local IN_YARD = Vector3.new(128, 1, 640)
local OUTSIDE = Vector3.new(0, 5, 0)

local function newState()
	return { Ready = true, Curse = 0, LastActivity = -1e9, MoveDist = 0, MinuteStart = os.clock(), MinuteCandy = 0,
		PerfectStart = os.clock(), PerfectCount = 0, InZone = false, BMSeconds = 0 }
end

local function newProfile(uid)
	local p = { UserId = uid, Bones = 0, Cash = 0, OwnedBlocks = {}, Dogs = {}, Items = {} }
	Feature.Shape(p)
	Feature.EnsureDaily(p, L.Time)
	return p
end

local function ctxFor(player, p)
	local st = Core.Players[player] or newState()
	Core.Players[player] = st
	local ctx = Core.MakeCtx(player, p, Feature.Shape(p), {}, L.Time, {}, {}, st)
	return ctx, st
end

local function questProgress(p, id)
	for _, q in ipairs(p.Halloween.Quests.List) do
		if q.Id == id then
			return q.Progress
		end
	end
	return nil
end

-- a fake Halloween core for SSS.Halloween.Actions: real Core grant ctx inside, blocks recorded instead of stored
local profiles, granted = {}, {}
local handlers = {}
local fakeCore = {
	Rules = R,
	Feature = Feature,
	OnRequest = function(action, fn) handlers[action] = fn end,
	Near = function() return true end,
	Signal = function() end,
	State = function(pl) return Core.Players[pl] end,
	Transact = function(player, _label, fn, opts)
		local p = profiles[player.UserId]
		local h = Feature.Shape(p)
		Feature.EnsureDaily(p, L.Time)
		local st = Core.Players[player] or newState()
		Core.Players[player] = st
		local ctx = Core.MakeCtx(player, p, h, {}, L.Time, Core.DogsOf(opts and opts.Rows), {}, st)
		ctx.Block = function(tier, n)
			table.insert(granted, { Tier = tier, N = n or 1 })
			return { "uid" .. #granted }
		end
		local ok, res = pcall(fn, p, h, ctx, L.Time)
		if not ok then
			return false, tostring(res)
		end
		if type(res) == "table" then
			res.View = Core.View(p, L.Time)
		end
		return true, res, nil, false
	end,
}
local Actions = L.Require("ServerScriptService.Halloween.Actions")
Actions.Start(fakeCore)

---------------------------------------------------------------------------------------------------------------------
-- rare prize philosophy
---------------------------------------------------------------------------------------------------------------------
test("the rare prize rescale ran at load and kept the original tables", function()
	eq(C.Rebalance.Applied, true, "Rebalance.Applied")
	local was = C.Rebalance.Was
	truthy(was.Pumpkin and was.CursedPumpkin, "originals kept")
	local sum = 0
	for _, row in ipairs(was.Pumpkin) do
		sum += row.Weight
	end
	eq(sum, 10115, "original Pumpkin weight sum")
	sum = 0
	for _, row in ipairs(was.CursedPumpkin) do
		sum += row.Weight
	end
	eq(sum, 9272, "original Cursed Pumpkin weight sum")
end)

test("every rescaled probability = old x class factor within 1e-6; weights sum to 1e6; the rest is Lucky Dust", function()
	for key, filler in pairs(C.Rebalance.Filler) do
		local old, new = C.Rebalance.Was[key], C.Rewards[key]
		local oldTotal, newTotal = 0, 0
		for _, row in ipairs(old) do
			oldTotal += row.Weight
		end
		for _, row in ipairs(new) do
			newTotal += row.Weight
			eq(row.Weight, math.floor(row.Weight), key .. " integer weight")
			truthy(row.Weight >= 1, key .. " positive weight")
		end
		eq(newTotal, 1000000, key .. " weight sum")
		eq(#new, #old + 1, key .. " rows (originals + filler)")
		local claimed = 0
		for i, row in ipairs(old) do
			local factor = C.Rebalance.RarityScale[DropRates.Classify(row)]
			truthy(factor ~= nil, "factor for " .. tostring(row.Name))
			local want = row.Weight / oldTotal * factor
			local got = new[i].Weight / newTotal
			near(got, want, 1e-6, key .. " " .. tostring(row.Name))
			eq(new[i].Id, row.Id, key .. " row identity")
			eq(new[i].Kind, row.Kind, key .. " row kind")
			claimed += want
		end
		local dust = new[#new]
		eq(dust.Kind, "Dust", key .. " filler kind")
		eq(dust.Amount[1], filler.Amount[1], key .. " filler min")
		eq(dust.Amount[2], filler.Amount[2], key .. " filler max")
		near(dust.Weight / newTotal, 1 - claimed, 1e-5, key .. " filler takes the freed probability")
		near(C.Rebalance.Odds[key].FillerChance, dust.Weight / newTotal, 1e-12, key .. " report filler chance")
	end
end)

test("classes: resources by kind, prizes by rarity (rank as fallback)", function()
	eq(DropRates.Classify({ Kind = "Cash", Rarity = "Rare" }), "Resource")
	eq(DropRates.Classify({ Kind = "Bones", Rarity = "Rare" }), "Resource")
	eq(DropRates.Classify({ Kind = "Candy" }), "Resource")
	eq(DropRates.Classify({ Kind = "Dust" }), "Resource")
	eq(DropRates.Classify({ Kind = "Decor", Rarity = "Epic" }), "Epic")
	eq(DropRates.Classify({ Kind = "Dog", Rank = 5 }), "Mythic")
	eq(DropRates.Classify({ Kind = "Mutation", Rarity = "Secret", Rank = 6 }), "Secret")
	local s = C.Rebalance.RarityScale
	eq(s.Resource, .5)
	eq(s.Rare, .10)
	eq(s.Epic, .10)
	eq(s.Legendary, .05)
	eq(s.Mythic, .025)
	eq(s.Secret, .01)
end)

test("DropRates.Rescale: inputs untouched, fillers split, impossible prizes kept possible, bad factors refused", function()
	local rows = {
		{ Kind = "Cash", Weight = 600, Name = "coins", Coins = { MinCash = 1 } },
		{ Kind = "Dog", Rarity = "Secret", Weight = 1, Name = "tiny" },
		{ Kind = "Decor", Rarity = "Rare", Weight = 399, Name = "decor" },
	}
	local out, report = DropRates.Rescale(rows, { Resource = .5, Rare = .1, Secret = 1e-6 }, {
		{ Kind = "Dust", Amount = 5, Weight = 3, Name = "a" }, { Kind = "Dust", Amount = 9, Weight = 1, Name = "b" } })
	eq(rows[1].Weight, 600, "input weight untouched")
	out[1].Coins.MinCash = 99
	eq(rows[1].Coins.MinCash, 1, "deep copies")
	eq(out[2].Weight, 1, "a prize that rounds to 0 keeps weight 1")
	local sum = 0
	for _, row in ipairs(out) do
		sum += row.Weight
	end
	eq(sum, 1000000)
	eq(out[4].Name, "a")
	eq(out[5].Name, "b")
	near(out[4].Weight / (out[4].Weight + out[5].Weight), .75, 1e-5, "filler split by weight")
	near(report.FillerChance, (out[4].Weight + out[5].Weight) / 1e6, 1e-12)
	errors(function()
		DropRates.Rescale(rows, { Resource = .5 }, { Kind = "Dust" })
	end, "no factor for class", "missing factor")
	errors(function()
		DropRates.Rescale(rows, { Resource = 2, Rare = 1, Secret = 1 }, { Kind = "Dust" })
	end, "factor above 1", "factor > 1")
	errors(function()
		DropRates.Rescale(rows, { Resource = .5, Rare = .1, Secret = .1 }, nil)
	end, "filler row is required", "filler required")
end)

test("boss drops follow the philosophy (per dog), CursedBlock and EclipseChance as designed", function()
	local oldChance = { .02, .04, .07, .12, .2 }
	local function rows(w)
		local out = {}
		for _, id in ipairs(C.Boss.EventDogs) do
			local rank = C.Dogs.Defs[id].Rank
			table.insert(out, { Kind = "Dog", Id = id, Rank = rank, Weight = rank >= 5 and w.Rank5 or w.Normal })
		end
		return out
	end
	local oldRows, newRows = rows({ Normal = 3, Rank5 = 1 }), rows(C.Boss.DogWeights)
	local function total(t)
		local s = 0
		for _, r in ipairs(t) do
			s += r.Weight
		end
		return s
	end
	for d, def in ipairs(C.Boss.Difficulties) do
		local want = DropRates.ScaleChance(oldChance[d], oldRows, C.Rebalance.RarityScale)
		near(def.DogChance, want, 1e-12, "DogChance " .. d)
		for i, row in ipairs(oldRows) do
			local oldAbs = oldChance[d] * row.Weight / total(oldRows)
			local newAbs = def.DogChance * newRows[i].Weight / total(newRows)
			near(newAbs, oldAbs * (DropRates.Factor(row, C.Rebalance.RarityScale)), 1e-12, "difficulty " .. d .. " " .. row.Id)
		end
	end
	eq(C.Boss.Difficulties[4].CursedBlock, .03, "IV cursed block")
	eq(C.Boss.Difficulties[5].CursedBlock, .08, "V cursed block")
	near(C.Boss.Difficulties[5].EclipseChance, .03 * .01, 1e-15, "V eclipse (Secret x .01)")
	local oldCandy = { { 20, 35 }, { 30, 50 }, { 45, 70 }, { 60, 85 }, { 80, 100 } }
	for d, def in ipairs(C.Boss.Difficulties) do
		eq(def.Candy[1], math.floor(oldCandy[d][1] * .6 + .5), "boss candy min " .. d)
		eq(def.Candy[2], math.floor(oldCandy[d][2] * .6 + .5), "boss candy max " .. d)
	end
end)

test("every other §12.2 lever has its new value", function()
	eq(C.Cauldron.TrickCost, 140, "trick base")
	eq(C.Rebalance.TrickEscalation.Step, .20)
	eq(C.Rebalance.TrickEscalation.Max, 240, "cap = 3x the old 80")
	eq(C.Candy.PerfectHitCap, 20)
	eq(C.Candy.MinuteCap, 110)
	eq(C.Ore.Candy[1], 1)
	eq(C.Ore.Candy[2], 2)
	eq(C.Candy.TreatHouse[1], 4)
	eq(C.Candy.TreatHouse[2], 9)
	eq(C.Candy.TrickHouse[1], 1)
	eq(C.Candy.TrickHouse[2], 3)
	eq(C.BloodMoon.CandyBonus, .25)
	eq(C.Quests.AllBonus.Candy, 15)
	eq(C.Quests.AllBonus.Kind, "Block")
	eq(C.Quests.AllBonus.Amount, 1)
	eq(C.Rebalance.PassiveScale, .2)
	local oldSpots = { CursedSoil = { 2, 4 }, GhostSoil = { 2, 4 }, PumpkinPatch = { 6, 10 }, BoneGrave = { 1, 3 }, CursedTreasure = { 14, 24 } }
	for _, t in ipairs(C.DigSpots.Types) do
		local was = oldSpots[t.Id]
		eq(t.Candy[1], math.max(1, math.floor(was[1] * .6 + .5)), t.Id .. " min")
		eq(t.Candy[2], math.max(1, math.floor(was[2] * .6 + .5)), t.Id .. " max")
	end
	local oldQuests = { DigSpots = 45, Perfect = 30, EarnCandy = 25, BloodMoon = 40, BossDamage = 50, OpenPumpkin = 35, FindMutation = 50,
		MineOre = 30, Knock = 25 }
	for _, q in ipairs(C.Quests.Pool) do
		eq(q.Candy, math.floor(oldQuests[q.Id] * .6 + .5), "quest " .. q.Id)
	end
	local block = C.Exorcism.Milestones[2]
	eq(block.Kind, "Block")
	eq(block.ActiveWindow, 180, "exorcism block window")
	eq(C.Rebalance.BrewDeadline.At, DEADLINE, "deadline = 2026-10-31 18:00 UTC")
	eq(C.Season, "NOTBM_2026", "the wipe key never changes")
end)

---------------------------------------------------------------------------------------------------------------------
-- candy: minute cap before multipliers, earned candy only
---------------------------------------------------------------------------------------------------------------------
test("MinuteCap applies to the base amount BEFORE the rush / Blood Moon multipliers", function()
	local pl = fakePlayer(101, IN_YARD)
	local p = newProfile(101)
	Core.Players[pl] = nil
	local ctx, st = ctxFor(pl, p)
	-- no multiplier: 200 base -> the cap
	eq(ctx.Candy(200, "Ore"), 110, "plain cap")
	eq(ctx.Candy(5, "Ore"), 0, "minute spent")
	-- a new minute with a personal Candy Rush (x2): the whole capped base is doubled
	st.MinuteStart = os.clock() - 61
	st.RushActive, st.RushRemaining, st.RushDay = true, 600, Feature.Day(L.Time)
	eq(ctx.Candy(200, "Ore"), 220, "rush keeps its value at the cap (was 110)")
	eq(ctx.Candy(10, "Queue"), 0, "cap reached")
	eq(ctx.Candy(10, "Treat", { NoCap = true }), 20, "uncapped sources are multiplied as before")
	-- rush + Blood Moon in the zone (x2 x 1.25)
	st.MinuteStart = os.clock() - 61
	st.InZone = true
	local moon = fakeFolder("BloodMoon")
	moon:SetAttribute("State", "ACTIVE")
	State._children.BloodMoon = moon
	eq(ctx.Candy(110, "Ore"), 275, "rush x Blood Moon on the full capped base")
	eq(ctx.Candy(1, "Ore"), 0)
	State._children.BloodMoon = nil
	Core.Players[pl] = nil
end)

test("EarnCandy counts earned candy only (never quest claims, reward rows or conversions)", function()
	local pl = fakePlayer(102, IN_YARD)
	local p = newProfile(102)
	Core.Players[pl] = nil
	local ctx = ctxFor(pl, p)
	eq(questProgress(p, "EarnCandy"), 0)
	ctx.Candy(18, "Quest", { NoMult = true, NoCap = true })
	ctx.Reward({ Kind = "Candy", Amount = 30 })
	ctx.Candy(60, "Duplicate", { NoMult = true, NoCap = true })
	ctx.Candy(40, "Debug", { NoMult = true, NoCap = true })
	eq(questProgress(p, "EarnCandy"), 0, "payouts do not progress EarnCandy")
	eq(p.Halloween.Candy, 148, "the payouts were still paid")
	ctx.Candy(7, "Ore")
	ctx.Candy(5, "Treat", { NoCap = true })
	ctx.Candy(3, "Boss", { NoCap = true })
	eq(questProgress(p, "EarnCandy"), 15, "earned sources progress it")
	truthy(Rules1.Earned("Queue", nil, C) and Rules1.Earned("DigSpot", {}, C), "play is earned")
	truthy(not Rules1.Earned("Quest", {}, C) and not Rules1.Earned("Reward", nil, C), "payout sources are not")
	truthy(Rules1.Earned("Quest", { Earned = true }, C), "explicit override")
	-- the real QuestClaim action pays its candy without progressing EarnCandy
	profiles[103] = newProfile(103)
	local p3 = profiles[103]
	local pl3 = fakePlayer(103, IN_YARD)
	for _, q in ipairs(p3.Halloween.Quests.List) do
		if q.Id == "Perfect" then
			q.Progress = q.Goal
		end
	end
	local ok, res = handlers.QuestClaim(pl3, { Id = "Perfect" })
	truthy(ok, tostring(res))
	eq(res.Candy, 18, "Perfect quest pays 18 (was 30)")
	eq(questProgress(p3, "EarnCandy"), 0, "quest claim candy is not 'earned'")
	Core.Players[pl] = nil
	Core.Players[pl3] = nil
end)

test("Dust reward rows pay Lucky Dust through Resources", function()
	local pl = fakePlayer(104, IN_YARD)
	local p = newProfile(104)
	local ctx = ctxFor(pl, p)
	local out = ctx.Reward({ Kind = "Dust", Amount = { 40, 70 } })
	eq(out.Kind, "Dust")
	truthy(out.Amount >= 40 and out.Amount <= 70, "amount in range: " .. tostring(out.Amount))
	eq(p.Resources.LuckyDust, out.Amount, "resource added")
	eq(ctx.Touched, true, "normal profile touched (projection refresh)")
	local fixed = ctx.Reward({ Kind = "Dust", Amount = 25 })
	eq(fixed.Amount, 25)
	eq(p.Resources.LuckyDust, out.Amount + 25)
	Core.Players[pl] = nil
end)

---------------------------------------------------------------------------------------------------------------------
-- TRICK escalation
---------------------------------------------------------------------------------------------------------------------
test("TRICK price escalates within a UTC day, caps at 240 and resets the next day", function()
	eq(table.concat(Rules1.TrickPrices(C, 7), ","), "140,170,200,240,240,240,240", "the ladder")
	local pl = fakePlayer(201, IN_YARD)
	profiles[201] = newProfile(201)
	local p = profiles[201]
	Feature.AddCandy(p, 5000)
	table.clear(granted)
	local paid = {}
	for _ = 1, 6 do
		local before = p.Halloween.Candy
		local ok, res = handlers.CauldronTrick(pl, {})
		truthy(ok, tostring(res))
		table.insert(paid, before - p.Halloween.Candy)
		eq(res.Price, paid[#paid], "reply price")
		eq(res.View.Cauldron.TrickPrice, res.NextPrice, "the view shows the next price")
	end
	eq(table.concat(paid, ","), "140,170,200,240,240,240", "paid")
	eq(#granted, 6, "one block per trick")
	eq(p.Halloween.Cauldron.Tricks, 6, "lifetime counter")
	eq(p.Halloween.Cauldron.TricksToday.N, 6, "today counter")
	-- the client's MaxPrice guard: a trick dearer than the shown price is refused and costs nothing
	local before = p.Halloween.Candy
	local ok, err = handlers.CauldronTrick(pl, { MaxPrice = 200 })
	eq(ok, false, "refused")
	truthy(string.find(err, "price changed", 1, true), err)
	eq(p.Halloween.Candy, before, "nothing spent")
	-- next UTC day: back to the base price (the view too)
	L.Time = NOW + DAY
	eq(Core.View(p, L.Time).Cauldron.TrickPrice, 140, "view after midnight")
	local ok2, res2 = handlers.CauldronTrick(pl, { MaxPrice = 140 })
	truthy(ok2, tostring(res2))
	eq(res2.Price, 140, "reset")
	eq(p.Halloween.Cauldron.TricksToday.N, 1)
	-- not enough candy: refused before anything changes
	p.Halloween.Candy = 100
	local ok3, err3 = handlers.CauldronTrick(pl, {})
	eq(ok3, false)
	eq(err3, "Not enough Candy")
	eq(p.Halloween.Cauldron.TricksToday.N, 1, "a refused trick does not count")
	Core.Players[pl] = nil
end)

test("TricksToday heals broken saved values", function()
	for _, bad in ipairs({ "x", { Day = "y", N = 5 }, { Day = Rules1.Day(NOW) - 1, N = 9 }, { Day = Rules1.Day(NOW), N = -4 } }) do
		local c = { TricksToday = bad }
		eq(Rules1.TricksToday(c, NOW), 0, "bad value")
		eq(Rules1.TrickPrice(c, NOW, C), 140)
		eq(Rules1.NoteTrick(c, NOW), 1)
		eq(c.TricksToday.Day, Rules1.Day(NOW))
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- brew catch-up
---------------------------------------------------------------------------------------------------------------------
test("brew catch-up: min(StartedAt + 7 d, Oct 31 18:00 UTC); after the deadline one day", function()
	local function ready(start)
		return start + Shared.BrewSeconds(start)
	end
	eq(Shared.BrewSeconds(), 7 * DAY, "no start = the full brew")
	eq(Shared.BrewSeconds(0), 7 * DAY)
	eq(ready(OCT20), OCT20 + 7 * DAY, "early starter: 7 days")
	eq(ready(DEADLINE - 7 * DAY), DEADLINE, "exactly 7 days before")
	eq(ready(OCT20 + 6 * DAY), DEADLINE, "late starter: by the deadline")
	eq(ready(DEADLINE - 30 * 3600), DEADLINE, "30 h before: the deadline")
	eq(ready(DEADLINE - 6 * 3600), DEADLINE, "6 h before: still ready by the deadline (never stranded)")
	eq(ready(DEADLINE - 60), DEADLINE, "a minute before: the deadline")
	eq(ready(DEADLINE), DEADLINE + DAY, "at the deadline: one day")
	eq(ready(DEADLINE + 5 * DAY), DEADLINE + 6 * DAY, "after the deadline: one day")
	for start = OCT20 - 10 * DAY, DEADLINE + 3 * DAY, 3517 do
		local r = ready(start)
		if start < DEADLINE then
			truthy(r <= DEADLINE, "a brew started before the deadline is ready by it")
		else
			eq(r, start + DAY, "a brew started after the deadline takes one day")
		end
		truthy(r <= start + 7 * DAY, "never later than 7 days")
		eq(r, Rules1.BrewReadyAt(start, C), "Shared and Chapter1Rules agree")
	end
	-- the claim follows it (a late starter on Oct 29 claims on Oct 31 18:00, not Nov 5)
	local pl = fakePlayer(301, IN_YARD)
	profiles[301] = newProfile(301)
	local p = profiles[301]
	p.Halloween.Cauldron.StartedAt = DEADLINE - 2 * DAY - 18 * 3600 -- Oct 29 00:00
	L.Time = DEADLINE - 60
	local view = Core.View(p, L.Time)
	eq(view.Cauldron.ReadyAt, DEADLINE, "the view shows the catch-up time")
	local ok, err = handlers.CauldronClaim(pl, {})
	eq(ok, false, "a minute early")
	eq(err, "The brew is not ready yet")
	L.Time = DEADLINE
	local ok2, res = handlers.CauldronClaim(pl, {})
	truthy(ok2, tostring(res))
	eq(p.Halloween.Cauldron.Claimed, true)
	Core.Players[pl] = nil
end)

---------------------------------------------------------------------------------------------------------------------
-- exorcism block
---------------------------------------------------------------------------------------------------------------------
test("the exorcism block goes only to players active in the Dead Yard in the last 180 s", function()
	local active = fakePlayer(401, IN_YARD) -- playing in the yard now
	local afk = fakePlayer(402, IN_YARD) -- standing in the yard, no action for minutes
	local away = fakePlayer(403, OUTSIDE) -- active elsewhere on the island
	local earlier = fakePlayer(404, OUTSIDE) -- left the yard 2 minutes ago
	local stale = fakePlayer(405, OUTSIDE) -- left the yard 4 minutes ago
	for _, pl in ipairs({ active, afk, away, earlier, stale }) do
		Core.Players[pl] = newState()
	end
	Core.Players[active].LastActivity = os.clock()
	Core.Players[away].LastActivity = os.clock()
	Core.Players[afk].LastActivity = os.clock() - 300
	for _, pl in ipairs({ active, afk, away }) do
		Core.TickPlayer(pl, Core.Players[pl], 1)
	end
	Core.Players[earlier].YardActiveAt = os.clock() - 120
	Core.Players[stale].YardActiveAt = os.clock() - 240
	truthy(Core.ActiveInYard(active, 180), "active in the yard")
	truthy(not Core.ActiveInYard(afk, 180), "AFK in the yard")
	truthy(not Core.ActiveInYard(away, 180), "active elsewhere")
	truthy(Core.ActiveInYard(earlier, 180), "within the window")
	truthy(not Core.ActiveInYard(stale, 180), "outside the window")

	local Ex = L.Require("ServerScriptService.Halloween.Exorcism")
	local m = C.Exorcism.Milestones[2]
	local yes, no = Ex.Recipients({ active, afk, away, earlier, stale }, m, Core)
	eq(#yes, 2, "two exorcists")
	eq(yes[1], active)
	eq(yes[2], earlier)
	eq(#no, 3, "three others")
	local all = Ex.Recipients({ active, afk }, { Kind = "Block" }, Core)
	eq(#all, 2, "no window: everyone (other milestones)")
	local none = Ex.Recipients({ active }, m, {})
	eq(#none, 0, "a core without ActiveInYard: nobody, never everyone")

	-- the real milestone: non-exorcists are told why, the grant list is the exorcist list
	players = { active, afk, away, earlier, stale }
	local toasts = {}
	local exCore = {
		OnSouls = function() end,
		ActiveInYard = Core.ActiveInYard,
		InZone = Core.InZone,
		Signal = function(target, kind, data)
			if kind == "Toast" then
				toasts[target] = data.Text
			end
		end,
		Transact = function() return true, {}, nil, false end,
	}
	Ex.Start(exCore)
	Ex.Add(m.At + 1, active)
	eq(Ex.Milestone, 2, "milestone reached")
	truthy(toasts[afk] and toasts[stale], "the others near the event are told (idle in the yard / there lately)")
	truthy(toasts[away] == nil, "a player who never played the yard is not bothered")
	truthy(toasts[active] == nil and toasts[earlier] == nil, "exorcists get the block, not the notice")
	players = {}
	for _, pl in ipairs({ active, afk, away, earlier, stale }) do
		Core.Players[pl] = nil
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- Dust rows through EventBlocks; frozen pools
---------------------------------------------------------------------------------------------------------------------
test("EventBlocks: the rescaled table with its Dust row is frozen into new blocks; owned blocks keep their pool", function()
	local E = L.Require("ServerScriptService.Economy.EventBlocks")
	local rows = E.Rows("Pumpkin")
	local dust = nil
	local sum = 0
	for _, row in ipairs(rows) do
		sum += row.Weight
		if row.Kind == "Dust" then
			dust = row
		end
	end
	eq(sum, 1000000, "rows sum")
	truthy(dust ~= nil, "Dust row present")
	-- a new block freezes the rescaled table
	local b = { Uid = "aa", Tier = "Pumpkin" }
	E.Freeze(b, L.Random.new(9))
	eq(#b.Pool, #rows)
	eq(b.OddsVersion, C.Rebalance.OddsVersion, "odds version")
	-- an owned block granted before keeps its frozen (old) pool
	local old = { Uid = "bb", Tier = "Pumpkin", Seed = 77, Variants = { { Name = "Normal", Weight = 1 } }, Pool = {} }
	for _, row in ipairs(C.Rebalance.Was.Pumpkin) do
		table.insert(old.Pool, table.clone(row))
	end
	E.Freeze(old, L.Random.new(9))
	eq(old.Pool[1].Weight, 2600, "old pool untouched")
	eq(#old.Pool, #C.Rebalance.Was.Pumpkin, "no filler injected into old blocks")
	-- odds disclosure
	local odds = E.Odds("Pumpkin")
	local dustOdds = nil
	for _, o in ipairs(odds) do
		if o.Kind == "Dust" then
			dustOdds = o
		end
	end
	truthy(dustOdds and math.abs(dustOdds.Chance - C.Rebalance.Odds.Pumpkin.FillerChance) < 1e-12, "dust odds disclosed")
	-- opening a Dust row pays Lucky Dust in range
	local p = newProfile(501)
	for seed = 1, 25 do
		local before = p.Resources and p.Resources.LuckyDust or 0
		local v = E.Apply(p, b, dust, L.Random.new(seed), L.Time)
		eq(v.Kind, "Dust")
		truthy(v.Amount >= 40 and v.Amount <= 70, "amount " .. tostring(v.Amount))
		eq(p.Resources.LuckyDust, before + v.Amount)
		truthy(string.match(v.Name, "^%d+ Lucky Dust$"), "name " .. tostring(v.Name))
	end
	-- cursed: bigger dust
	local cursedDust = nil
	for _, row in ipairs(E.Rows("Cursed Pumpkin")) do
		if row.Kind == "Dust" then
			cursedDust = row
		end
	end
	local v = E.Apply(p, b, cursedDust, L.Random.new(3), L.Time)
	truthy(v.Amount >= 150 and v.Amount <= 260, "cursed dust " .. tostring(v.Amount))
	-- the weighted pick lands on Dust about as often as disclosed
	local hits, n = 0, 20000
	for seed = 1, n do
		b.Seed = seed * 7919
		local row = E.Pick(b)
		if row.Kind == "Dust" then
			hits += 1
		end
	end
	near(hits / n, C.Rebalance.Odds.Pumpkin.FillerChance, .02, "pick frequency")
end)

test("the exorcism Epic+ pumpkin keeps only Epic+ rows (no Dust) after the rescale", function()
	local kept = 0
	for _, row in ipairs(C.Rewards.Pumpkin) do
		if (row.Rank or 1) >= 3 then
			kept += 1
			truthy(row.Kind ~= "Dust", "dust never in the Epic+ pool")
		end
	end
	truthy(kept >= 10, "Epic+ rows kept: " .. kept)
end)

---------------------------------------------------------------------------------------------------------------------
-- passive generation
---------------------------------------------------------------------------------------------------------------------
test("passive yard event mutations are YardChance x PassiveScale (boosts still apply)", function()
	local H = L.Require("ServerScriptService.Economy.HalloweenHooks")
	local function byName(rows)
		local out = {}
		for _, r in ipairs(rows or {}) do
			out[r.Name] = r.Chance
		end
		return out
	end
	local rows = byName(H.Rows(L.Time))
	near(rows.HAUNTED, .004 * .2, 1e-15, "HAUNTED")
	near(rows.PUMPKINIZED, .0015 * .2, 1e-15, "PUMPKINIZED")
	eq(rows["BLOOD MOON"], nil, "BLOOD MOON only during a Blood Moon")
	local moon = fakeFolder("BloodMoon")
	moon:SetAttribute("State", "ACTIVE")
	State._children.BloodMoon = moon
	State:SetAttribute("MutationBoostUntil", L.Time + 60)
	rows = byName(H.Rows(L.Time))
	near(rows.HAUNTED, .004 * .2 * 2 * 2, 1e-15, "Blood Moon x exorcism boost")
	near(rows["BLOOD MOON"], .0012 * .2 * 2 * 2, 1e-15, "BLOOD MOON row")
end)

---------------------------------------------------------------------------------------------------------------------
-- view
---------------------------------------------------------------------------------------------------------------------
test("the client view carries the TRICK price, its range and the catch-up ReadyAt", function()
	local p = newProfile(601)
	local v = Core.View(p, L.Time)
	eq(v.Cauldron.TrickPrice, 140)
	eq(v.Cauldron.TrickBase, 140)
	eq(v.Cauldron.TrickMax, 240)
	eq(v.Cauldron.TricksToday, 0)
	eq(v.Cauldron.ReadyAt, 0, "no brew")
	p.Halloween.Cauldron.TricksToday = { Day = Rules1.Day(L.Time), N = 2 }
	p.Halloween.Cauldron.StartedAt = OCT20 + 8 * DAY
	v = Core.View(p, L.Time)
	eq(v.Cauldron.TrickPrice, 200)
	eq(v.Cauldron.TricksToday, 2)
	eq(v.Cauldron.ReadyAt, DEADLINE, "late brew ready at the deadline")
end)

print(string.format("chapter1_rebalance: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("chapter1_rebalance tests failed")
end
