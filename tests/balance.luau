--!nocheck
-- BALANCE block (docs/BALANCE.md): lune run tests/balance.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): Economy.Rules.MiningAction stores
-- Stone from broken ores in p.Resources (DogEconomy.Resources) inside the mining transaction, for a
-- new player and for an old profile without Resources / StoneMined; Engine:MiningAction (the fast
-- path every hit uses) returns the stored Stone; Normalize / Validate keep it.
local L = require("./lib/economy_env")
local R = L.Require("ServerScriptService.Economy.Rules")
local C = L.Require("ServerScriptService.Economy.Config")
local Resources = L.Require("ReplicatedStorage.DogEconomy.Resources")
local MiningRules = L.Require("ReplicatedStorage.Mining.MiningRules")
local Text = L.Require("ReplicatedStorage.Mining.MiningText")
local M = C.Mining

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
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end
local function truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local NOW = 1760000000
L.Time = NOW

local function firstTarget(session)
	local best
	for _, t in pairs(session.Targets or {}) do
		if not best or t.SpawnAt < best.SpawnAt then best = t end
	end
	return best
end

-- Mines the current ore of p until it breaks (perfect hits), through Economy.Rules. The server
-- clock (workspace:GetServerTimeNow, L.Time) moves to each circle's gold band.
local function breakOre(p, session, random)
	R.MiningAction(p, "MiningBegin", {}, NOW, random, session, 0.05)
	for _ = 1, 400 do
		local t = firstTarget(session)
		L.Time = t.SpawnAt + t.Window * 0.8
		local msg = R.MiningAction(p, "MiningHit", { Target = t.Id, Quality = 2 }, NOW, random, session, 0.05)
		if Text.Key(msg) == "BROKE" then return msg end
	end
	error("ore never broke")
end

local function newPlayer(layers)
	local p = R.Profile(1, NOW)
	p.Mining.PickaxeOwned, p.Mining.PickaxeLevel = 1, 1
	for i = 1, layers or 1 do
		p.UnlockedLayers[tostring(i)] = true
	end
	return p
end

test("new player: breaking limestone stores Stone in p.Resources and counts it", function()
	local p = newPlayer()
	eq(Resources.Get(p, "Stone"), 0, "starts without Stone")
	eq(p.Mining.OreId, "Limestone", "first ore is limestone")
	local cash = p.Cash
	local msg = breakOre(p, { Targets = {} }, rng(3))
	eq(Resources.Get(p, "Stone"), 4, "limestone on layer 1 stores 4 Stone")
	eq(p.Mining.LastStone, 4)
	eq(p.Mining.StoneMined, 4)
	truthy(p.Cash - cash >= M.Ores[1].ValueMin, "and pays its coins: " .. (p.Cash - cash))
	truthy(string.find(msg, "|4", 1, true) ~= nil, msg)
	R.Validate(p)
	eq(Resources.Get(p, "Stone"), 4, "Validate keeps it")
end)

test("old player: profile without Resources or StoneMined gets Stone on the next break", function()
	local p = newPlayer()
	p.Resources = nil
	p.Mining.StoneMined, p.Mining.LastStone = nil, nil
	-- An old save as stored before this update (fields missing, current ore from the old table).
	p.Mining.OreHP, p.Mining.OreMaxHP, p.Mining.OreValue = 16, 16, 47
	p = R.Normalize(p, 1, NOW)
	eq(p.Mining.StoneMined, 0, "normalized to 0")
	eq(type(p.Resources), "table", "Resources feature fills the table")
	breakOre(p, { Targets = {} }, rng(5))
	eq(Resources.Get(p, "Stone"), 4)
	eq(p.Mining.StoneMined, 4)
	eq(p.Mining.OreMaxHP, M.Ores[p.Mining.OreIndex].HP, "the next ore uses the new HP table")
	R.Validate(p)
end)

test("deeper unlocked layer: more Stone per limestone; existing Stone is added to", function()
	local p = newPlayer(3)
	p.Resources = { Stone = 100 }
	breakOre(p, { Targets = {} }, rng(9))
	eq(Resources.Get(p, "Stone"), 100 + MiningRules.StoneForBreak(M, M.Ores[1], 3), "layer 3")
	eq(MiningRules.StoneForBreak(M, M.Ores[1], 3), 6)
end)

test("Stone never passes Resources.Max and the counter records only what was added", function()
	local p = newPlayer()
	local max = Resources.Kinds.Stone.Max
	p.Resources = { Stone = max - 1 }
	breakOre(p, { Targets = {} }, rng(11))
	eq(Resources.Get(p, "Stone"), max, "clamped")
	eq(p.Mining.LastStone, 1, "only the added Stone")
	R.Validate(p)
end)

test("Engine:MiningAction (fast path) commits Stone and returns it to the client", function()
	L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end, Current = function() return 1 end }
	local Tx = L.Require("ServerScriptService.Economy.Transactions")
	local Engine = L.Require("ServerScriptService.Economy.Engine")
	local data = {}
	local store = {}
	function store:Read(k) return R.Copy(data[k]) end
	function store:Update(k, fn)
		local v = fn(R.Copy(data[k]))
		if v ~= nil then data[k] = R.Copy(v) end
		return R.Copy(v)
	end
	local n = 0
	local function guid() n += 1; return string.format("%032x", n) end
	local clock = function() return NOW end
	local tx = Tx.new(store, clock, guid, {})
	local engine = Engine.new(tx, { Now = clock, Guid = guid, Random = rng(13), Session = "S1" })
	local ok, err = engine:Join(1)
	truthy(ok, "join: " .. tostring(err))
	ok, err = tx:Run({ "p:1" }, function(v)
		local p = v["p:1"]
		p.Mining.PickaxeOwned, p.Mining.PickaxeLevel = 1, 1
		p.Resources = nil -- old profile
		return true
	end)
	truthy(ok, "seed: " .. tostring(err))
	local session = { Targets = {} }
	local okB, begin = engine:MiningAction(1, "MiningBegin", {}, nil, session, 0.05)
	truthy(okB, "begin: " .. tostring(begin))
	local result
	for _ = 1, 400 do
		local t = firstTarget(session)
		L.Time = t.SpawnAt + t.Window * 0.8
		local okH, r = engine:MiningAction(1, "MiningHit", { Target = t.Id, Quality = 2 }, nil, session, 0.05)
		truthy(okH, "hit: " .. tostring(r))
		if Text.Key(r.Message) == "BROKE" then
			result = r
			break
		end
	end
	truthy(result, "broke")
	eq(type(result.Resources), "table", "fast result carries Resources")
	eq(result.Resources.Stone, 4)
	eq(result.MiningState.LastStone, 4)
	local saved = tx:Read("p:1")
	eq(Resources.Get(saved, "Stone"), 4, "committed with the coins")
	eq(saved.Mining.StoneMined, 4)
	L.Overrides["ServerScriptService/Economy/ServerLuck"] = nil
end)

test("prices from the server config: pickaxes several times dearer, owned ones stay owned", function()
	eq(M.Pickaxes[1].Price, 600)
	eq(M.Pickaxes[2].Price, 7500)
	truthy(M.Pickaxes[3].Price >= 135000 and M.Pickaxes[7].Price >= 595000000, "advanced pickaxes dearer")
	local p = newPlayer()
	p.Mining.PickaxeOwned, p.Mining.PickaxeLevel, p.Mining.Strength = 7, 7, 1100
	p = R.Normalize(p, 1, NOW)
	eq(p.Mining.PickaxeOwned, 7, "an owned Voidbreaker stays owned")
	local cash = p.Cash
	R.MiningAction(p, "MiningPickaxe", { Level = 5 }, NOW, rng(1), { Targets = {} }, 0)
	eq(p.Mining.PickaxeLevel, 5, "re-equip")
	eq(p.Cash, cash, "free")
end)

print(string.format("balance: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
