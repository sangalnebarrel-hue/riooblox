--!nocheck
-- Economy core review regressions: lune run tests/economy_core.luau
-- Runs the real src modules (tests/lib/economy_env.luau) with small stubs:
--  * kennel dogs keep digging (and animating) while the finds storage is full: ordinary loot is
--    paid into the wallet, so only Rules.Storage().LootFull may stop their work;
--  * Economy.IncomeModel keeps time-independent dog contexts across its 5-minute buckets (a
--    Snapshot of a big collection no longer re-samples every dog kind every 5 minutes) and its
--    results never differ from a cold computation;
--  * the hidden EventRoll (100 Global Dig tokens -> a free dog) is closed while Global Dig is
--    disabled, like EventClaim: dog income now accrues those tokens while the player is AFK.
local L = require("./lib/economy_env")

local NOW = 1760000000 -- 08:53 UTC
local DAY = math.floor(NOW / 86400) * 86400

-- World stubs for ServerScriptService.DogKennelService (set before anything requires it).
local function folder(children)
	return {
		GetChildren = function()
			return children or {}
		end,
		FindFirstChild = function() return nil end,
	}
end
local residents = {}
local district = {
	WaitForChild = function(_, name)
		if name == "KennelDogs" then return folder(residents) end
		return folder({})
	end,
}
L.Workspace = setmetatable({
	WaitForChild = function(_, name)
		assert(name == "DOGROTS_District", "unexpected workspace child " .. tostring(name))
		return district
	end,
	GetServerTimeNow = function() return L.Time end,
	FindFirstChild = function() return nil end,
}, { __index = function() return nil end })
local runtimeStub = { Views = {}, Ready = function() return true end, Allow = function() return true end }
L.Overrides["ServerScriptService/Economy/Runtime"] = runtimeStub
-- ServerLuck creates a live Folder on load; the tongue odds only read its rank multipliers.
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end }

local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")
local Model = L.Require("ServerScriptService.Economy.IncomeModel")
local S = L.Require("ServerScriptService.Economy.SignatureRules")
local D = L.Require("ServerScriptService.Economy.DogDefinitions")
local B = L.Require("ReplicatedStorage.DogEconomy.Bonuses")

-- Real bonus sources are set aside so the cases measure the economy core alone.
local installedSources = table.clone(B.Sources)
table.clear(B.Sources)

local passed, failed = 0, 0
local function test(name, fn)
	L.Time = NOW
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
local function team(ids, layer)
	local p = R.Profile(1, NOW)
	for i = 1, layer or 1 do p.UnlockedLayers[tostring(i)] = true end
	p.CurrentLayer = layer or 1
	p.LastDig = NOW
	p.Upgrades.DogStorage = 12
	for i, id in ipairs(ids) do
		local d = R.Mint(p, id, string.format("dog%03d", i), {}, NOW, rng(i), "Test", "Normal", true)
		if i <= 5 then
			d.AssignedSlot = "DigSlot_" .. i
			d.State = "Digging"
			d.NextWorkAt = NOW
		end
	end
	return p
end
local function fillFinds(p)
	local capacity = R.Storage(p, L.Time).ItemCapacity
	for k = 1, capacity do p.Items["filler" .. k] = { ItemUid = "filler" .. k } end
end

-- Kennel work state ----------------------------------------------------------------------------
test("kennel dogs keep digging while the finds storage is full (coins still flow)", function()
	local Kennels = L.Require("ServerScriptService.DogKennelService")
	local p = team({ "Breadog" })
	fillFinds(p)
	local storage = R.Storage(p, NOW)
	eq(storage.ItemFull, true, "finds storage full")
	eq(storage.LootFull, false, "ordinary loot never blocks")
	-- The economy really keeps paying this dog.
	local cash = p.Cash
	R.Dig(p, NOW, rng(3))
	truthy(p.Cash > cash, "a dig with full finds storage still pays coins")
	runtimeStub.Views[1] = p
	local attrs = { OwnerUserId = 1, NextWorkAt = NOW + 8, AnimationName = "Idle" }
	local model = {
		GetAttribute = function(_, k) return attrs[k] end,
		SetAttribute = function(_, k, v) attrs[k] = v end,
	}
	table.clear(residents)
	table.insert(residents, model)
	Kennels.UpdateWorkVisuals()
	eq(attrs.Producing, true, "Producing")
	eq(attrs.AnimationName, "Work", "dig animation")
	eq(attrs.WorkState, "DIGGING", "work state")
	eq(attrs.StorageFull, false, "not blocked by storage")
	-- A stalled economy tick still rests the dog.
	attrs.NextWorkAt = NOW - 30
	L.Time = NOW + 30
	Kennels.UpdateWorkVisuals()
	eq(attrs.Producing, false, "stalled tick")
	eq(attrs.AnimationName, "Idle", "stalled tick idles")
	table.clear(residents)
	runtimeStub.Views[1] = nil
end)

-- Income model cache ---------------------------------------------------------------------------
local kinds = {}
for id, def in pairs(D) do
	if def.Available and not def.Reserved then table.insert(kinds, id) end
end
table.sort(kinds)

test("a new 5-minute bucket re-samples only clock-dependent dog contexts", function()
	local p = team(kinds, 3)
	Model.Reset()
	R.IncomeModel(p, NOW)
	local calls = 0
	local context = S.Context
	S.Context = function(...)
		calls += 1
		return context(...)
	end
	local ok, err = pcall(R.IncomeModel, p, NOW + 300)
	S.Context = context
	assert(ok, err)
	-- Before: every owned kind (101 x 120 samples = 12,120 contexts, ~150 ms) every 5 minutes.
	truthy(calls <= 3 * Model.Samples, "contexts sampled on the bucket change: " .. calls)
end)

test("cached income equals a cold computation at every clock phase", function()
	local p = team(kinds, 3)
	-- Five Don Puglione rotations by day, then night (Vampug, Barkula) and back to day.
	local times = {}
	for k = 0, 4 do table.insert(times, DAY + 12 * 3600 + 300 * k + 17) end
	table.insert(times, DAY + 19 * 3600 + 5)
	table.insert(times, DAY + 19 * 3600 + 905)
	table.insert(times, DAY + 86400 + 6 * 3600 + 5)
	Model.Reset()
	for _, t in ipairs(times) do
		L.Time = t
		p.LastDig = t
		local warm = R.IncomeModel(p, t)
		Model.Reset()
		local cold = R.IncomeModel(p, t)
		for uid, stats in pairs(cold.Dogs) do
			local w = warm.Dogs[uid]
			eq(w and w.CoinsPerMin, stats.CoinsPerMin, p.Dogs[uid].DogId .. " at " .. (t - DAY))
			eq(w and w.LuckPct, stats.LuckPct, p.Dogs[uid].DogId .. " luck at " .. (t - DAY))
		end
		eq(warm.PerMinute, cold.PerMinute, "team at " .. (t - DAY))
	end
end)

-- Event tokens ---------------------------------------------------------------------------------
test("EventRoll stays closed while Global Dig is disabled", function()
	local GlobalDig = L.Require("ReplicatedStorage.GlobalDigConfig")
	local Engine = L.Require("ServerScriptService.Economy.Engine")
	local p = team({ "Breadog", "Chipdog", "Corndoggo", "Melondog", "Tacodach" })
	fillFinds(p)
	-- AFK with a full finds storage: dog income keeps accruing Global Dig tokens.
	local random = rng(9)
	for t = NOW, NOW + 600 do
		L.Time = t
		R.Dig(p, t, random)
	end
	truthy(p.EventTokens >= 100, "tokens accrued while AFK: " .. p.EventTokens)
	table.clear(p.Items)
	p.Session = { Id = "S", Expires = NOW + 10 ^ 6 }
	local engine = setmetatable({
		Tx = {
			Run = function(_, keys, fn)
				local v = { ["p:1"] = p }
				local ok, result = pcall(fn, v)
				return ok, result
			end,
			Read = function() return p end,
		},
		Now = function() return L.Time end,
		Guid = function() return "rolled-dog" end,
		Random = rng(4),
		Session = "S",
		Connected = function() return true end,
		AssetReady = function() return true end,
	}, Engine)
	local enabled = GlobalDig.Enabled
	GlobalDig.Enabled = false
	local before, dogs = p.EventTokens, R.Count(p.Dogs)
	local ok, result = pcall(engine.Roll, engine, 1, "EventRoll")
	local refused = not ok or result == false
	eq(refused, true, "EventRoll refused while Global Dig is disabled")
	eq(p.EventTokens, before, "no tokens spent")
	eq(R.Count(p.Dogs), dogs, "no dog minted")
	-- With Global Dig enabled the roll works as before.
	GlobalDig.Enabled = true
	local ok2, done, minted = pcall(engine.Roll, engine, 1, "EventRoll")
	GlobalDig.Enabled = enabled
	truthy(ok2 and done, "EventRoll works while Global Dig is enabled: " .. tostring(done) .. " " .. tostring(minted))
	eq(p.EventTokens, before - 100, "tokens spent")
	eq(R.Count(p.Dogs), dogs + 1, "dog minted")
end)

for _, s in ipairs(installedSources) do table.insert(B.Sources, s) end
print(string.format("economy_core: %d passed, %d failed", passed, failed))
if failed > 0 then error("economy_core tests failed") end
