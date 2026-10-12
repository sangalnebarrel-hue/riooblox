--!nocheck
-- Dog income, the shared income model and the Bonuses pipeline wiring: lune run tests/income.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau). A dummy BonusSource is injected
-- for each stat key and the test checks that exactly the intended outputs move.
local L = require("./lib/economy_env")
local C = L.Require("ReplicatedStorage.DogEconomy.Config")
local B = L.Require("ReplicatedStorage.DogEconomy.Bonuses")
local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")
local O = L.Require("ServerScriptService.Economy.OfflineEarnings")
local Value = L.Require("ReplicatedStorage.ItemValuation")
local Lifetime = L.Require("ServerScriptService.Economy.LifetimeStats")

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
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then error((msg or "") .. string.format(" expected %.6g ±%.3g got %.6g", b, tolerance, a), 2) end
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
-- A profile with these dogs at work (slots 1..n), deterministic.
local function team(ids, opts)
	opts = opts or {}
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p.Upgrades = opts.Upgrades or {}
	for i = 1, (opts.Layer or 1) do p.UnlockedLayers[tostring(i)] = true end
	p.CurrentLayer = opts.Layer or 1
	p.LastDig = NOW
	for i, id in ipairs(ids) do
		local d = R.Mint(p, id, "dog" .. i, {}, NOW, rng(i), "Test", opts.Variant or "Normal", true)
		d.AssignedSlot = "DigSlot_" .. i
		d.State = "Digging"
		d.Mastery = opts.Mastery or 0
		d.MasteryXP = (opts.Mastery or 0) ^ 2 * 5
		d.NextWorkAt = NOW
	end
	return p
end
-- Runs Rules.Dig every second; sells discoveries every minute (counted at their sale price).
local function simulate(p, seconds, seed, keepItems, from)
	local random = rng(seed)
	local itemCash = 0
	from = from or NOW
	for t = from, from + seconds do
		L.Time = t
		R.Dig(p, t, random)
		if not keepItems and (t - from) % 60 == 0 then
			for uid, x in pairs(p.Items) do
				itemCash += Value.Price(x)
				p.Items[uid] = nil
			end
		end
	end
	return itemCash
end
-- Installs a dummy bonus source for the duration of fn.
local function withSource(source, fn)
	table.insert(B.Sources, source)
	local ok, err = pcall(fn)
	table.remove(B.Sources, table.find(B.Sources, source))
	if not ok then error(err, 0) end
end
local function global(key, amount)
	return { Name = "TestGlobal", Global = function(_, _, add) add(key, amount) end }
end

-- Config ----------------------------------------------------------------------------------------
test("variant table: 10,000 total, ~23% mutated, Golden ~5%, Void rare", function()
	local total, mutated, golden, void = 0, 0, 0, 0
	for i, v in ipairs(C.Variants) do
		total += v.Weight
		if i > 1 then mutated += v.Weight end
		if v.Name == "Golden" then golden = v.Weight end
		if v.Name == "Void" then void = v.Weight end
		truthy(R.VariantNames[v.Name], "name index " .. v.Name)
	end
	eq(total, 10000, "sum")
	truthy(mutated / total >= .20 and mutated / total <= .25, "mutated share")
	truthy(golden / total >= .04 and golden / total <= .06, "golden share")
	truthy(void / total <= .003, "void stays rare")
	eq(C.Variants[1].Name, "Normal", "Normal stays row 1")
end)

test("R.Variant sums the real weights (no 10,000 truncation)", function()
	local counts, n, random = {}, 200000, rng(11)
	for _ = 1, n do
		local v = R.Variant(random)
		counts[v] = (counts[v] or 0) + 1
	end
	for _, v in ipairs(C.Variants) do near((counts[v.Name] or 0) / n, v.Weight / 10000, .004, v.Name) end
	-- Scaling every weight keeps the odds (the old code truncated at 10,000).
	local saved = {}
	for i, v in ipairs(C.Variants) do saved[i] = v.Weight; v.Weight *= 3 end
	local triple, random2 = {}, rng(11)
	for _ = 1, n do local v = R.Variant(random2); triple[v] = (triple[v] or 0) + 1 end
	for i, v in ipairs(C.Variants) do v.Weight = saved[i] end
	for _, v in ipairs(C.Variants) do near((triple[v.Name] or 0) / n, v.Weight / 10000, .004, "x3 " .. v.Name) end
end)

test("R.Mint validates a forced variant", function()
	local p = team({})
	local ok = pcall(R.Mint, p, "Breadog", "bad", {}, NOW, rng(1), "DogLine", "Rainbow")
	eq(ok, false, "unknown variant refused")
	local d = R.Mint(p, "Breadog", "good", {}, NOW, rng(1), "DogLine", "Golden")
	eq(d.Variant, "Golden")
	local d2 = R.Mint(p, "Breadog", "lucky", {}, NOW, rng(1), "LuckyBlock", "Void", true)
	eq(d2.Variant, "Void", "frozen lucky rows still mint")
end)

-- Dog income ------------------------------------------------------------------------------------
test("ordinary loot is paid into the wallet as it is dug", function()
	local p = team({ "Breadog", "Chipdog" })
	local cash0 = p.Cash
	local earned0 = Lifetime.Normalize(p).TotalCoinsEarned
	simulate(p, 120, 3, true)
	truthy(p.Cash > cash0, "wallet grew")
	eq(next(p.Loot), nil, "no loot stacks created")
	local yield = 0
	for _, d in pairs(p.Dogs) do yield += d.LastYield or 0 end
	truthy(yield > 0, "LastYield recorded")
	truthy(type(p.DogIncome) == "table" and p.DogIncome.Total == p.Cash - cash0, "dog income book matches the wallet")
	eq(p.Lifetime.TotalCoinsEarned - earned0, p.Cash - cash0, "lifetime coins")
end)

test("no storage stall: income keeps flowing without selling", function()
	local p = team({ "Breadog", "Chipdog", "Melondog", "Corndoggo", "Tacodach" }, { Upgrades = { Plot = 4 } })
	local cash0 = p.Cash
	simulate(p, 300, 5, true)
	local first = p.Cash - cash0
	simulate(p, 300, 6, true, NOW + 301)
	local second = p.Cash - cash0 - first
	truthy(first > 0 and second > first * .6, "second 5 minutes still earn (" .. first .. " / " .. second .. ")")
end)

test("old loot stacks stay sellable", function()
	local p = team({})
	p.Loot["1:1:Old Sneaker"] = { Name = "Old Sneaker", Category = "Junk", Count = 3, Value = 90, Layer = 1 }
	local cash0 = p.Cash
	R.Action(p, "SellLoot", {}, NOW, rng(1))
	eq(p.Cash - cash0, 90)
end)

test("Rules.Storage contract and item-full state", function()
	local p = team({ "Breadog" })
	local s = R.Storage(p, NOW)
	for _, k in ipairs({ "LootUnits", "LootCapacity", "ItemCount", "ItemCapacity" }) do eq(type(s[k]), "number", k) end
	eq(s.LootFull, false)
	eq(s.ItemFull, false)
	eq(s.ItemCapacity, 50)
	-- Fill discovery storage: dogs keep earning coins, find no items, and the state says so.
	local cap = s.ItemCapacity
	for i = 1, cap do p.Items["x" .. i] = { ItemUid = "x" .. i, ItemId = "old_sneaker", OwnerUserId = 1, WeightKg = 1 } end
	local full = R.Storage(p, NOW)
	eq(full.ItemFull, true)
	eq(full.LootFull, false)
	local cash0 = p.Cash
	simulate(p, 120, 9, true)
	eq(I.Count(p.Items), cap, "no items past capacity")
	truthy(p.Cash > cash0, "coins still flow")
	local model = R.IncomeModel(p, NOW)
	eq(model.ItemsPerMinute, 0, "model counts no finds when full")
	truthy(R.IncomeModel(p, NOW, { Potential = true }).ItemsPerMinute > 0, "potential still counts them")
end)

test("Storage Crate adds discovery slots", function()
	local p = team({})
	p.Supplies.StorageCrate = NOW + 60
	eq(R.Storage(p, NOW).ItemCapacity, 50 + C.Supplies.StorageCrate.Magnitude)
end)

test("auto-deposit signatures earn their share as value", function()
	local p = team({ "Skatehound" })
	local d = p.Dogs.dog1
	local def = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")[d.DogId]
	local e = R.Team(p, NOW)
	local b = B.For(p, d, NOW)
	local plain = R.RollMultiplier(p, d, def, e, b, false, { AutoDeposit = nil })
	local skate = R.RollMultiplier(p, d, def, e, b, false, { AutoDeposit = .20 })
	near(skate / plain, 1.2, 1e-9)
end)

test("speed beyond the cooldown floor becomes extra rolls", function()
	local p = team({ "Breadog" }, { Mastery = 100, Upgrades = { Dig = 10 } })
	local d = p.Dogs.dog1
	local e = R.Team(p, NOW)
	local cooldown, overflow = R.Cooldown(p, d, e, B.For(p, d, NOW))
	eq(cooldown, C.Work.MinCooldown, "at the floor")
	truthy(overflow > 1, "overflow")
	local random = rng(4)
	local total = 0
	for _ = 1, 20000 do total += R.RollCount(2, 1.25, random) end
	near(total / 20000, 2.5, .02, "expected rolls")
	eq(R.RollCount(2, 1, random), 2)
end)

test("dog luck stat is real (not +0.0%)", function()
	local p = team({ "Barkbeard", "Breadog" })
	local m = R.IncomeModel(p, NOW)
	truthy(m.Dogs.dog1.LuckPct > 50, "Barkbeard treasure luck " .. m.Dogs.dog1.LuckPct)
	truthy(m.Dogs.dog2.LuckPct >= 0, "Breadog")
	p.LuckBoosts = { ["2"] = NOW + 600 }
	local boosted = R.IncomeModel(p, NOW)
	near(boosted.Dogs.dog2.LuckPct - m.Dogs.dog2.LuckPct, 200, 1e-6, "2x LUCK = +200%")
end)

test("efficiency: better dogs score higher, a plain Common ~1", function()
	local p = team({ "Corndoggo", "NinjaInu", "KingCorgi", "TheDog" })
	local m = R.IncomeModel(p, NOW)
	truthy(math.abs(m.Dogs.dog1.Efficiency - 1.12) < .15, "Corndoggo ~1.12 (" .. m.Dogs.dog1.Efficiency .. ")")
	truthy(m.Dogs.dog2.Efficiency > m.Dogs.dog1.Efficiency, "rare > common")
	truthy(m.Dogs.dog4.Efficiency > m.Dogs.dog3.Efficiency, "secret > legendary")
	for _, s in pairs(m.Dogs) do
		eq(type(s.CoinsPerMin), "number")
		eq(type(s.DigsPerMin), "number")
	end
end)

test("the model matches the real Rules.Dig (2 h, two teams)", function()
	for _, case in ipairs({
		{ { "Breadog", "Chipdog", "Melondog", "Corndoggo", "Tacodach" }, { Upgrades = { Plot = 4 } } },
		{ { "NinjaInu", "Barkbeard", "GamerDog", "CraneCorgi", "Sharkshund" }, { Layer = 2, Upgrades = { Dig = 3, Plot = 4, Kennel = 3, Ability = 2 }, Mastery = 20 } },
	}) do
		local p = team(case[1], case[2])
		local model = R.IncomeModel(p, NOW).PerMinute
		local cash0 = p.Cash
		local seconds = 7200
		local items = simulate(p, seconds, 21)
		local real = (p.Cash - cash0 + items) / (seconds / 60)
		truthy(math.abs(model / real - 1) < .12, string.format("model %.0f vs real %.0f", model, real))
	end
end)

test("offline estimate is the same model x efficiency", function()
	local p = team({ "Breadog", "Chipdog" }, { Upgrades = { Plot = 1 } })
	local rate, rows, base = O.Estimate(p)
	local clean = R.IncomeModel(p, 41, { AssignedOnly = true, Potential = true })
	near(base * 60, clean.PerMinute, 1e-6, "base rate")
	near(rate / base, L.Require("ReplicatedStorage.OfflineEarningsConfig").Efficiency, 1e-9, "efficiency")
	eq(#rows, 2)
end)

-- Bonuses pipeline: one dummy source per key, exactly the intended outputs move --------------------
local function snapshotOf(p)
	local d = p.Dogs.dog1
	local def = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")[d.DogId]
	local e = R.Team(p, NOW)
	local b = B.For(p, d, NOW)
	local cooldown, overflow = R.Cooldown(p, d, e, b)
	local ctx = { Value = 1, CategoryLuck = {}, ItemScale = 1, WeightLuck = 0, MutationChance = 0, MutationValue = 1 }
	local effects = R.ItemEffects(p, d, e, ctx, b, 0, 50)
	local rows = I.MutationRows(effects)
	local rare, common
	for id, item in pairs(I.Definitions) do
		if item.Depth == 1 and item.Class ~= "Secret" then
			if item.BaseDropChance < .01 then rare = rare or id else common = common or id end
		end
	end
	local m = R.IncomeModel(p, NOW)
	local offline, _, offlineBase = O.Estimate(p)
	return {
		Cooldown = cooldown,
		Overflow = overflow,
		Value = R.RollMultiplier(p, d, def, e, b, false, {}),
		Luck = R.LootLuck(p, e, NOW, 0, b),
		IncomeMult = effects.IncomeMult,
		RareChance = I.ItemChance(I.Definitions[rare], effects),
		CommonChance = I.ItemChance(I.Definitions[common], effects),
		Normal = rows[1].Chance,
		Golden = rows[2].Chance,
		Capacity = R.Storage(p, NOW).ItemCapacity,
		Mutated = 1 - R.VariantRows(p, NOW)[1].Weight / 10000,
		Offline = offline,
		OfflineBase = offlineBase,
		DigsPerMin = m.Dogs.dog1.DigsPerMin,
		PerMinute = m.PerMinute,
	}
end
local function changed(base, after)
	local out = {}
	for k, v in pairs(base) do
		if math.abs(after[k] - v) > 1e-9 * math.max(1, math.abs(v)) then out[k] = true end
	end
	return out
end
local function onlyChanged(diff, allowed, key)
	for k in pairs(diff) do truthy(allowed[k], key .. " must not change " .. k) end
end

test("pipeline: baseline is untouched without sources", function()
	eq(#B.Sources, 0, "no sources installed in src")
	local p = team({ "Breadog" })
	local s = snapshotOf(p)
	eq(s.IncomeMult, 1)
	eq(s.Capacity, 50)
end)

local cases = {
	{ Key = "DigSpeed", Amount = .5, Expect = { Cooldown = true, DigsPerMin = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "Luck", Amount = .5, Expect = { Luck = true, RareChance = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "Income", Amount = .5, Expect = { Value = true, IncomeMult = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "MoneyMult", Amount = .5, Expect = { Value = true, IncomeMult = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "DogPower", Amount = .5, Expect = { Value = true, IncomeMult = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "RareFind", Amount = .5, Expect = { RareChance = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "ItemMutation", Amount = 1, Expect = { Normal = true, Golden = true, PerMinute = true, Offline = true, OfflineBase = true } },
	{ Key = "Storage", Amount = 30, Expect = { Capacity = true } },
	{ Key = "Offline", Amount = .5, Expect = { Offline = true } },
	{ Key = "DogMutation", Amount = .5, Expect = { Mutated = true } },
	{ Key = "XP", Amount = .5, Expect = {} },
	{ Key = "DepthSpeed", Amount = .5, Expect = {} },
}
for _, case in ipairs(cases) do
	test("pipeline: " .. case.Key .. " moves exactly its outputs", function()
		local p = team({ "Breadog" })
		local base = snapshotOf(p)
		local after
		withSource(global(case.Key, case.Amount), function() after = snapshotOf(p) end)
		local diff = changed(base, after)
		for k in pairs(case.Expect) do truthy(diff[k], case.Key .. " should change " .. k) end
		onlyChanged(diff, case.Expect, case.Key)
		if case.Key == "Income" or case.Key == "MoneyMult" or case.Key == "DogPower" then
			near(after.Value / base.Value, 1.5, 1e-9, "value x1.5")
			near(after.IncomeMult, 1.5, 1e-9, "items x1.5")
		elseif case.Key == "Luck" then
			near(after.Luck - base.Luck, .5, 1e-9, "luck +.5")
		elseif case.Key == "RareFind" then
			near(after.RareChance / base.RareChance, 1.5, 1e-9, "rare finds x1.5")
		elseif case.Key == "ItemMutation" then
			near(after.Golden / base.Golden, 2, 1e-9, "golden x2")
			near(after.Normal, 1 - 2 * (1 - base.Normal), 1e-9, "normal is the remainder")
		elseif case.Key == "Storage" then
			eq(after.Capacity, base.Capacity + 30)
		elseif case.Key == "Offline" then
			near(after.Offline / base.Offline, 1.5, 1e-9, "offline x1.5")
		elseif case.Key == "DogMutation" then
			near(after.Mutated / base.Mutated, 1.5, 1e-9, "mutated rows x1.5")
		end
	end)
end

test("pipeline: XP bonus scales dig XP only", function()
	local function run(withBonus)
		local p = team({ "Breadog" })
		local xp0 = p.XP
		local cash0 = p.Cash
		local function go() simulate(p, 240, 31, true) end
		if withBonus then withSource(global("XP", 1), go) else go() end
		return p.XP - xp0, p.Cash - cash0
	end
	local xp, cash = run(false)
	local xp2, cash2 = run(true)
	eq(cash2, cash, "same coins")
	truthy(xp2 >= xp * 1.9, string.format("xp doubled (%d -> %d)", xp, xp2))
end)

test("pipeline: DigSpeed past the floor still pays (extra rolls)", function()
	local p = team({ "Breadog" }, { Mastery = 100, Upgrades = { Dig = 10 } })
	local d = p.Dogs.dog1
	local base = R.IncomeModel(p, NOW).PerMinute
	local _, overflow = R.Cooldown(p, d, R.Team(p, NOW), B.For(p, d, NOW))
	local after, overflow2
	withSource(global("DigSpeed", 1), function()
		after = R.IncomeModel(p, NOW).PerMinute
		_, overflow2 = R.Cooldown(p, d, R.Team(p, NOW), B.For(p, d, NOW))
	end)
	truthy(overflow2 > overflow * 1.3, "overflow grew")
	near(after / base, overflow2 / overflow, .02, "income follows the overflow (loot and items)")
	-- The real dig loop agrees: same seed, the bonus pays ~overflow ratio more.
	local function earn(withBonus)
		local q = team({ "Breadog" }, { Mastery = 100, Upgrades = { Dig = 10 } })
		local cash0 = q.Cash
		local items = 0
		local function go() items = simulate(q, 3600, 41) end
		if withBonus then withSource(global("DigSpeed", 1), go) else go() end
		return q.Cash - cash0 + items
	end
	local plain, fast = earn(false), earn(true)
	truthy(fast / plain > 1.3, string.format("simulated %.0f -> %.0f", plain, fast))
end)

test("pipeline: a per-dog source changes only that dog", function()
	local source = { Name = "TestDog", Dog = function(_, d, _, add) if d.DogUid == "dog1" then add("Income", 1) end end }
	local function run(installed)
		local p = team({ "Breadog", "Chipdog" })
		local cash0 = p.Cash
		local yields = { dog1 = 0, dog2 = 0 }
		local random = rng(17)
		local function go()
			for t = NOW, NOW + 200 do
				L.Time = t
				R.Dig(p, t, random)
				for uid, d in pairs(p.Dogs) do
					if d.LastAbilityAt == t then yields[uid] += d.LastYield or 0 end
				end
			end
		end
		if installed then withSource(source, go) else go() end
		return yields, p
	end
	local base = run(false)
	local after, p = run(true)
	eq(after.dog2, base.dog2, "other dog untouched")
	truthy(after.dog1 > base.dog1 * 1.8, "artifact dog doubled")
	for _, x in pairs(p.Items) do
		if x.SourceDogUid == "dog1" then near(x.IncomeMult, 2, 1e-9, "item multiplier stored at mint") end
		if x.SourceDogUid == "dog2" then eq(x.IncomeMult, nil, "no multiplier on the other dog's items") end
	end
end)

test("pipeline: item value is fixed at mint (no equip-then-sell)", function()
	local x = { ItemUid = "i1", ItemId = "old_sneaker", WeightKg = 1, TierIndex = 3, Mutation = "NORMAL" }
	local def = I.Definitions[x.ItemId]
	if not def then
		for id in pairs(I.Definitions) do x.ItemId = id; break end
		def = I.Definitions[x.ItemId]
	end
	x.WeightKg = def.BaseWeightKg
	local plain = Value.Price(x)
	withSource(global("Income", 2), function() eq(Value.Price(x), plain, "live bonus ignored at sale") end)
	x.IncomeMult = 3
	truthy(Value.Price(x) >= plain * 3 - 1, "stored multiplier counts")
end)

print(string.format("income: %d passed, %d failed", passed, failed))
if failed > 0 then error("income tests failed") end
