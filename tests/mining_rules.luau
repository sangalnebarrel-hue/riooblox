--!nolint
-- Unit tests for the pure mining rules: lune run tests/mining_rules.luau
local M = require("../src/ReplicatedStorage/DogEconomy/MiningConfig")
local Rules = require("../src/ReplicatedStorage/Mining/MiningRules")
local Text = require("../src/ReplicatedStorage/Mining/MiningText")
M.MaxCash = 9e15

-- Deterministic stand-in for Roblox's Random (not available in plain Lune).
local Random = {}
function Random.new(seed)
	local state = (seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return {
		NextNumber = function(_self)
			state = (state * 48271) % 2147483647
			return state / 2147483647
		end,
	}
end

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
local function errorsWith(fn, key)
	local ok, err = pcall(fn)
	if ok then
		error("expected error " .. key, 2)
	end
	if Text.Key(err) ~= key then
		error("expected error " .. key .. " got " .. tostring(err), 2)
	end
end

-- A deterministic context with a wallet, an XP counter and a controllable clock.
local function newCtx(seed)
	local rng = Random.new(seed or 1)
	local ctx = { Now = 1000, Clock = 1000, Cash = 0, XP = 0, Layer = 1, Ping = 0.05, Session = { Targets = {} } }
	ctx.Random = function()
		return rng:NextNumber()
	end
	ctx.Pay = function(n)
		if ctx.Cash < n then
			error("Not enough Cash or Bones", 0)
		end
		ctx.Cash -= n
	end
	ctx.Credit = function(n)
		ctx.Cash += n
	end
	ctx.AddXP = function(n)
		ctx.XP += n
	end
	return ctx
end
local function advance(ctx, dt)
	ctx.Clock += dt
	ctx.Now = math.floor(ctx.Clock)
end
local function firstTarget(ctx)
	local best
	for _, t in ctx.Session.Targets do
		if not best or t.SpawnAt < best.SpawnAt then
			best = t
		end
	end
	return best
end
-- Waits until the target is at fraction f of its window, then hits it.
local function hitAt(m, ctx, f, quality)
	local t = firstTarget(ctx)
	ctx.Clock = t.SpawnAt + t.Window * f
	ctx.Now = math.floor(ctx.Clock)
	return Rules.Action(m, M, "MiningHit", { Target = t.Id, Quality = quality or 2 }, ctx)
end

test("config sanity: 12 ores, 7 pickaxes, 7 weights, first weight free, wooden needs no strength", function()
	eq(#M.Ores, 12)
	eq(#M.Pickaxes, 7)
	eq(#M.Weights, 7)
	eq(M.Weights[1].Price, 0)
	eq(M.Pickaxes[1].Strength, 0)
	for i = 2, #M.Pickaxes do
		truthy(M.Pickaxes[i].Price > M.Pickaxes[i - 1].Price, "pickaxe prices rise")
		truthy(M.Pickaxes[i].Strength > M.Pickaxes[i - 1].Strength, "pickaxe strength rises")
		truthy(M.Pickaxes[i].Damage > M.Pickaxes[i - 1].Damage, "pickaxe damage rises")
	end
	for i = 2, #M.Weights do
		truthy(M.Weights[i].Price > M.Weights[i - 1].Price, "weight prices rise")
		truthy(M.Weights[i].Strength <= M.Weights[i - 1].Cap, "weight " .. i .. " unlockable with previous cap")
	end
	-- Every pickaxe requirement is reachable with the weight one step below it.
	for i = 2, #M.Pickaxes do
		truthy(M.Pickaxes[i].Strength <= M.Weights[i - 1].Cap, "pickaxe " .. i .. " reachable with weight " .. (i - 1))
	end
	for _, ore in M.Ores do
		truthy(ore.Name and ore.RU and ore.Visual, "ore names/visual " .. ore.Id)
	end
end)

test("new state normalizes idempotently", function()
	local m = Rules.Normalize(Rules.New(M), M)
	local copy = table.clone(m)
	Rules.Normalize(m, M)
	for k, v in copy do
		if type(v) ~= "table" then
			eq(m[k], v, "field " .. k)
		end
	end
	eq(m.OreId, "Limestone")
	eq(m.Version, 2)
end)

test("v1 save migrates ore by legacy index and keeps progress", function()
	local v1 = {
		Strength = 120, PickaxeOwned = 3, PickaxeLevel = 2, WeightOwned = 3, WeightLevel = 3, Hits = 50,
		OresBroken = 4, CoinsEarned = 9000, TrainingReps = 30, OreIndex = 6, OreMaxHP = 82, OreHP = 40,
		OreValue = 10000, OreEarned = 3000, OreSerial = 5,
	}
	local m = Rules.Normalize(v1, M)
	eq(m.OreId, "Ruby", "legacy index 6 was Ruby")
	eq(m.OreHP, M.Ores[m.OreIndex].HP, "migrated ore starts fresh")
	eq(m.OreEarned, 0)
	eq(m.Strength, 120)
	eq(m.PickaxeLevel, 2)
	eq(m.Hits, 50)
	eq(m.Version, 2)
end)

test("corrupt values are clamped", function()
	local m = Rules.Normalize({ Strength = 1e9, PickaxeOwned = 99, PickaxeLevel = -3, OreId = "Nope", Combo = 1e6 }, M)
	eq(m.Strength, M.MaxStrength)
	eq(m.PickaxeOwned, #M.Pickaxes)
	eq(m.PickaxeLevel, #M.Pickaxes, "level 0 with owned picks equips the best")
	eq(m.OreId, "Limestone")
	eq(m.Combo, M.ComboCap)
end)

test("buying: order, strength and coins are enforced; wooden is cheap and needs 0 strength", function()
	local m = Rules.New(M)
	local ctx = newCtx()
	errorsWith(function()
		Rules.Action(m, M, "MiningBegin", {}, ctx)
	end, "NEED_PICKAXE")
	errorsWith(function()
		Rules.Action(m, M, "MiningPickaxe", { Level = 2 }, ctx)
	end, "IN_ORDER")
	errorsWith(function()
		Rules.Action(m, M, "MiningPickaxe", { Level = 1 }, ctx)
	end, "NEED_COINS")
	ctx.Cash = 4200
	eq(Text.Key(Rules.Action(m, M, "MiningPickaxe", { Level = 1 }, ctx)), "BOUGHT")
	eq(ctx.Cash, 4200 - M.Pickaxes[1].Price)
	eq(m.PickaxeLevel, 1)
	ctx.Cash = 1e9
	errorsWith(function()
		Rules.Action(m, M, "MiningPickaxe", { Level = 2 }, ctx)
	end, "NEED_STRENGTH")
	m.Strength = M.Pickaxes[2].Strength
	Rules.Action(m, M, "MiningPickaxe", { Level = 2 }, ctx)
	eq(m.PickaxeOwned, 2)
	-- Re-equip an owned pickaxe for free.
	local before = ctx.Cash
	eq(Text.Key(Rules.Action(m, M, "MiningPickaxe", { Level = 1 }, ctx)), "EQUIPPED")
	eq(ctx.Cash, before)
	eq(m.PickaxeLevel, 1)
end)

test("weights: first is free, cap and cooldown enforced", function()
	local m = Rules.New(M)
	local ctx = newCtx()
	errorsWith(function()
		Rules.Action(m, M, "MiningTrain", {}, ctx)
	end, "NEED_WEIGHT")
	eq(Text.Key(Rules.Action(m, M, "MiningWeight", { Level = 1 }, ctx)), "WEIGHT_BOUGHT")
	eq(ctx.Cash, 0, "free weight costs nothing")
	advance(ctx, 5)
	eq(Text.Key(Rules.Action(m, M, "MiningTrain", {}, ctx)), "TRAINED")
	eq(m.Strength, M.Weights[1].Gain)
	errorsWith(function()
		Rules.Action(m, M, "MiningTrain", {}, ctx)
	end, "REST")
	for _ = 1, 500 do
		advance(ctx, M.Weights[1].Cooldown + M.MinLiftTime)
		local ok = pcall(Rules.Action, m, M, "MiningTrain", {}, ctx)
		if not ok then
			break
		end
	end
	eq(m.Strength, M.Weights[1].Cap, "stops at the cap")
	errorsWith(function()
		advance(ctx, 5)
		Rules.Action(m, M, "MiningTrain", {}, ctx)
	end, "WEIGHT_CAPPED")
end)

test("timing: too early rejected, perfect graded by server, claimed perfect downgraded when early", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel = 1, 1
	local ctx = newCtx()
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	local t = firstTarget(ctx)
	ctx.Clock = t.SpawnAt + t.Window * 0.2
	errorsWith(function()
		Rules.Action(m, M, "MiningHit", { Target = t.Id, Quality = 2 }, ctx)
	end, "TOO_EARLY")
	-- good-zone click that claims perfect is downgraded to a normal hit
	eq(Text.Key(hitAt(m, ctx, 0.5, 2)), "HIT")
	eq(m.LastQuality, 1)
	-- the next target is a new id
	local t2 = firstTarget(ctx)
	truthy(t2.Id ~= t.Id, "target replaced")
	eq(Text.Key(hitAt(m, ctx, 0.82, 2)), "PERFECT")
	eq(m.LastQuality, 2)
	eq(m.Combo, 1)
	-- reusing a consumed target id fails
	errorsWith(function()
		Rules.Action(m, M, "MiningHit", { Target = t2.Id, Quality = 2 }, ctx)
	end, "TARGET_GONE")
	-- far too late: counted as a miss, the slot gets a fresh circle
	local t3 = firstTarget(ctx)
	ctx.Clock = t3.SpawnAt + t3.Window + 2
	ctx.Now = math.floor(ctx.Clock)
	eq(Text.Key(Rules.Action(m, M, "MiningHit", { Target = t3.Id, Quality = 1 }, ctx)), "TOO_LATE")
	eq(m.Combo, 0)
	local t4 = firstTarget(ctx)
	truthy(t4.Id ~= t3.Id, "late hit respawns the slot")
	-- a reported miss replaces the target and resets the combo
	ctx.Clock = t4.SpawnAt + t4.Window * 1.01
	eq(Text.Key(Rules.Action(m, M, "MiningHit", { Target = t4.Id, Miss = true }, ctx)), "MISS")
	eq(m.Combo, 0)
	truthy(firstTarget(ctx).Id ~= t4.Id)
end)

test("session expires", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel = 1, 1
	local ctx = newCtx()
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	advance(ctx, M.SessionSeconds + 5)
	local t = firstTarget(ctx)
	errorsWith(function()
		Rules.Action(m, M, "MiningHit", { Target = t.Id, Quality = 1 }, ctx)
	end, "SESSION_OVER")
end)

test("breaking pays exactly the ore total, rolls a new ore and pauses the circles", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel = 1, 1
	local ctx = newCtx(4)
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	local value, serial = m.OreValue, m.OreSerial
	local hits = 0
	repeat
		local msg = hitAt(m, ctx, 0.6, 1)
		hits += 1
	until Text.Key(msg) == "BROKE" or hits > 500
	eq(ctx.Cash, value, "all coins of the ore were paid")
	eq(m.OresBroken, 1)
	eq(m.OreSerial, serial + 1)
	eq(m.Collection.Limestone, 1)
	truthy(hits >= 10, "wooden needs many hits on limestone (" .. hits .. ")")
	truthy(ctx.XP > 0, "breaking grants XP")
	truthy(firstTarget(ctx).SpawnAt >= ctx.Clock + M.Client.BreakPause - 1e-6, "circles wait for the new pile")
end)

test("Voidbreaker breaks ANY ore in at most 2 hits", function()
	local pick = M.Pickaxes[#M.Pickaxes]
	local m = Rules.New(M)
	m.Strength = pick.Strength
	for _, ore in M.Ores do
		local normal = Rules.HitDamage(M, m, pick, 1, 0, false)
		truthy(math.ceil(ore.HP / normal) <= 2, ore.Id .. " needs " .. math.ceil(ore.HP / normal) .. " normal hits")
	end
	-- and the wooden pickaxe needs many clicks even on the cheapest ore
	local wood = M.Pickaxes[1]
	truthy(Rules.HitsToBreak(M, Rules.New(M), wood, M.Ores[1]) >= 12, "wooden is click-heavy")
end)

test("ore luck shifts weight towards rare ores", function()
	local w0, t0 = Rules.OreWeights(M, 0)
	local w1, t1 = Rules.OreWeights(M, 1)
	truthy(w1[#w1] / t1 > w0[#w0] / t0, "rarest ore more likely with luck")
	eq(w1[1], w0[1], "the commonest ore weight is unchanged")
end)

test("layer multiplier scales ore value", function()
	local m = Rules.New(M)
	local seqA, seqB = Random.new(9), Random.new(9)
	Rules.RollOre(m, M, function()
		return seqA:NextNumber()
	end, 0, 1)
	local v1 = m.OreValue
	local m2 = Rules.New(M)
	Rules.RollOre(m2, M, function()
		return seqB:NextNumber()
	end, 0, 5)
	eq(m2.OreId, m.OreId)
	truthy(math.abs(m2.OreValue - v1 * M.LayerValue[5]) <= M.LayerValue[5], "layer 5 value")
end)

test("buying a pickaxe mid-session reissues its circles", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel, m.Strength = 3, 3, 500
	local ctx = newCtx()
	ctx.Cash = 1e9
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	local n = 0
	for _ in ctx.Session.Targets do
		n += 1
	end
	eq(n, M.Pickaxes[3].Circles)
	Rules.Action(m, M, "MiningPickaxe", { Level = 4 }, ctx)
	n = 0
	for _ in ctx.Session.Targets do
		n += 1
	end
	eq(n, M.Pickaxes[4].Circles)
end)

test("messages localize in both languages", function()
	local en = Text.Message(Rules.Code("NEED_STRENGTH", 25))
	truthy(string.find(en, "25"), en)
	local broke = Text.Message(Rules.Code("BROKE", "Ruby", 12345), function(id, key)
		if key == "BROKE" then
			local ore = Rules.OreById(M, id)
			return ore
		end
		return nil
	end)
	truthy(string.find(broke, "Ruby") and string.find(broke, "12.3K"), broke)
	eq(Text.Short(95000000), "95M")
	eq(Text.Short(1500), "1500")
	eq(Text.Short(15000), "15K")
end)

test("training session toggles with mining session", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel = 1, 1
	local ctx = newCtx()
	Rules.Action(m, M, "MiningTrainBegin", {}, ctx)
	truthy(m.TrainingUntil > ctx.Now)
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	eq(m.TrainingUntil, 0, "mining ends training")
	truthy(m.ActiveUntil > ctx.Now)
	Rules.Action(m, M, "MiningTrainBegin", {}, ctx)
	eq(m.ActiveUntil, 0, "training ends mining")
	Rules.Action(m, M, "MiningTrainEnd", {}, ctx)
	eq(m.TrainingUntil, 0)
	errorsWith(function()
		Rules.Action(m, M, "MiningNope", {}, ctx)
	end, "BAD_ACTION")
end)

test("break pause cannot be skipped (miss before open, Begin, re-equip) and stale clicks are harmless", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel, m.Strength = 7, 7, 1100
	local ctx = newCtx(11)
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	local oldIds = {}
	for _, t in ctx.Session.Targets do
		oldIds[#oldIds + 1] = t.Id
	end
	local msg = hitAt(m, ctx, 0.8, 2)
	eq(Text.Key(msg), "BROKE", "voidbreaker one-shots limestone")
	local pauseUntil = ctx.Session.PauseUntil
	truthy(pauseUntil and pauseUntil > ctx.Clock, "pause stored")
	-- a stale click for a circle of the broken ore is answered harmlessly
	eq(Text.Key(Rules.Action(m, M, "MiningHit", { Target = oldIds[2], Quality = 2 }, ctx)), "STALE")
	-- missing a circle that has not opened yet is refused
	local t = firstTarget(ctx)
	errorsWith(function()
		Rules.Action(m, M, "MiningHit", { Target = t.Id, Miss = true }, ctx)
	end, "TOO_EARLY")
	-- Begin while live keeps the same circles
	local before = t.Id
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	eq(firstTarget(ctx).Id, before, "Begin is idempotent")
	-- re-equipping another pickaxe re-issues, but never before the pause ends
	Rules.Action(m, M, "MiningPickaxe", { Level = 6 }, ctx)
	for _, x in ctx.Session.Targets do
		truthy(x.SpawnAt >= pauseUntil - 1e-6, "no circle before the pause")
	end
end)

test("a lift ends mining and needs rest plus a minimum lift time", function()
	local m = Rules.New(M)
	m.PickaxeOwned, m.PickaxeLevel, m.WeightOwned, m.WeightLevel = 1, 1, 1, 1
	local ctx = newCtx()
	Rules.Action(m, M, "MiningBegin", {}, ctx)
	advance(ctx, 5)
	Rules.Action(m, M, "MiningTrain", {}, ctx)
	eq(m.ActiveUntil, 0, "mining ended")
	eq(next(ctx.Session.Targets), nil, "circles cleared")
	advance(ctx, M.Weights[1].Cooldown * M.CooldownTolerance)
	errorsWith(function()
		Rules.Action(m, M, "MiningTrain", {}, ctx)
	end, "REST")
	advance(ctx, M.MinLiftTime + 0.01)
	eq(Text.Key(Rules.Action(m, M, "MiningTrain", {}, ctx)), "TRAINED")
end)

print(string.format("mining_rules: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
