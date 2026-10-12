--!nocheck
-- Dogdex and MY DOGS (spec §8): lune run tests/dogdex.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): the DexRewards table, the Dogdex feature
-- (DexClaim through Rules.Action, the old claim ledger, Lucky Block storage, coin scaling, Normalize,
-- the snapshot and its species stats against the income model), the pure screen logic
-- (Modules.DogInfo: filters, sorts, comparison, sources, reward states) and the Russian strings of the
-- two windows (every T("...") / F("...") of DogsScreen and DogdexScreen has an entry).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local L = require("./lib/economy_env")
local C = L.Require("ReplicatedStorage.DogEconomy.Config")
local D = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")
local Rewards = L.Require("ReplicatedStorage.DogEconomy.DexRewards")
local Pricing = L.Require("ReplicatedStorage.DogEconomy.BoostPricing")
local Blocks = L.Require("ReplicatedStorage.LuckyBlockConfig")
local Lifecycle = L.Require("ReplicatedStorage.LuckyLifecycleConfig")
local R = L.Require("ServerScriptService.Economy.Rules")
local Registry = L.Require("ServerScriptService.Economy.FeatureRegistry")
local Feature = L.Require("ServerScriptService.Economy.Features.Dogdex")
local Info = L.Require("StarterGui.ScreenGui.Modules.DogInfo")

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
local function refused(fn, needle)
	local ok, err = pcall(fn)
	if ok then error("expected a refusal" .. (needle and (" (" .. needle .. ")") or ""), 2) end
	if needle and not string.find(tostring(err), needle, 1, true) then error("wrong refusal: " .. tostring(err), 2) end
	return tostring(err)
end
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local r = {}
	for k, x in pairs(v) do r[k] = deepCopy(x) end
	return r
end
local function deepEqual(a, b, path)
	path = path or "p"
	if type(a) ~= type(b) then error(path .. ": type " .. type(a) .. " ~= " .. type(b), 2) end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
		return
	end
	for k, v in pairs(a) do deepEqual(v, b[k], path .. "." .. tostring(k)) end
	for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. " added", 2) end end
end

local NOW = 1760000000
L.Time = NOW
-- Museum species in catalogue order (#1..#100).
local museum = {}
for _, def in pairs(D) do
	if not def.MuseumExcluded and def.Index >= 1 and def.Index <= 100 then museum[def.Index] = def.Id end
end
local function profile(discovered, opts)
	opts = opts or {}
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p = R.Normalize(p, 1, NOW)
	for i = 1, discovered do p.DogDex[museum[i]] = true end
	for i = 1, (opts.Layer or 1) do p.UnlockedLayers[tostring(i)] = true end
	p.CurrentLayer = opts.Layer or 1
	p.LastDig = NOW
	return p
end
local function claim(p, count)
	return R.Action(p, "DexClaim", { Count = count }, NOW, rng(3))
end

-- DexRewards table -------------------------------------------------------------------------------
test("reward tiers: 10, 20 ... 100, increasing, valid blocks, unique titles", function()
	eq(Rewards.Tiers[1].Count, 10, "first tier")
	eq(Rewards.Tiers[#Rewards.Tiers].Count, Rewards.Total, "last tier is the full collection")
	eq(Rewards.Total, Info.MuseumTotal, "full collection = every museum dog")
	eq(Rewards.Total, 100, "museum size")
	local seen, titles = {}, {}
	for i, tier in ipairs(Rewards.Tiers) do
		truthy(not seen[tier.Count], "unique threshold " .. tier.Count)
		seen[tier.Count] = true
		eq(Rewards.ByCount[tier.Count], tier, "ByCount")
		eq(tier.Index, i, "index")
		if i > 1 then
			local prev = Rewards.Tiers[i - 1]
			truthy(tier.Count > prev.Count, "threshold order")
			truthy(tier.Bones > prev.Bones, "bones grow")
			truthy(tier.Coins.MinCash > prev.Coins.MinCash and tier.Coins.IncomeMinutes >= prev.Coins.IncomeMinutes, "coins grow")
		end
		if tier.Block then
			truthy(Blocks.Rank(tier.Block.Tier) ~= nil, "lucky tier " .. tostring(tier.Block.Tier))
			truthy(tier.Block.Count >= 1 and tier.Block.Count <= 3, "block count")
		end
		if tier.Title then
			truthy(not titles[tier.Title], "unique title")
			titles[tier.Title] = true
			eq(tier.Title, "Dex" .. tier.Count, "title id follows the old Dex<n> keys")
			truthy(type(tier.TitleName) == "string" and tier.TitleName ~= "", "title name")
		end
	end
	truthy(Rewards.Tiers[#Rewards.Tiers].Title == "Dex100" and Rewards.ByCount[10].Title == "Dex10" and Rewards.ByCount[50].Title == "Dex50", "old titles kept on 10/50/100")
	eq(Rewards.Get(25), nil, "old threshold 25 is gone")
	eq(Rewards.Get("10"), nil, "only numbers")
end)

-- DexClaim ---------------------------------------------------------------------------------------
test("DexClaim goes through the feature (not the old Bones = count branch)", function()
	local p = profile(12)
	local bones, cash = p.Bones, p.Cash
	local message, extra = claim(p, 10)
	eq(message, "Dogdex reward claimed")
	eq(p.DexClaims["10"], true, "ledger")
	eq(p.Bones - bones, 25, "tier bones")
	truthy(p.Cash - cash >= 20000, "coins at least the floor")
	eq(extra.DexReward.Coins, p.Cash - cash, "reply carries the coins")
	eq(p.Cosmetics.Dex10, true, "title")
	local stored = 0
	for uid, b in pairs(p.OwnedBlocks) do
		stored += 1
		eq(#uid, 32, "block uid length")
		truthy(uid:match("^%x+$"), "hex uid")
		eq(b.Uid, uid)
		eq(b.Tier, "Rare")
		eq(b.State, "Stored")
		eq(b.PaidRandom, false, "free reward, not paid random")
		eq(b.OwnerUserId, 1)
	end
	eq(stored, 1, "one Rare Lucky Block")
	R.Validate(p)
	refused(function() claim(p, 10) end, "already claimed")
end)

test("old ledger: claimed 10/25 stay claimed, 25 is not claimable, new 20/30 pay once", function()
	local p = profile(31)
	p.DexClaims = { ["10"] = true, ["25"] = true }
	p.Cosmetics.Dex10 = true
	p.Cosmetics.Dex25 = true
	p = R.Normalize(p, 1, NOW)
	refused(function() claim(p, 10) end, "already claimed")
	refused(function() claim(p, 25) end, "Invalid milestone")
	refused(function() claim(p, 75) end, "Invalid milestone")
	local bones = p.Bones
	claim(p, 20)
	eq(p.Bones - bones, 40, "20 pays its bones")
	refused(function() claim(p, 20) end, "already claimed")
	claim(p, 30)
	eq(p.Cosmetics.Dex30, true, "30 title")
	eq(p.Cosmetics.Dex25, true, "old title kept")
	eq(p.DexClaims["25"], true, "old key kept")
	refused(function() claim(p, 40) end, "Discover 40 dogs")
	for _, bad in ipairs({ 0, -10, 10.5, 1e9, "10", true }) do
		refused(function() R.Action(p, "DexClaim", { Count = bad }, NOW, rng(1)) end, "Invalid milestone")
	end
	refused(function() R.Action(p, "DexClaim", {}, NOW, rng(1)) end, "Invalid milestone")
end)

test("the count is the museum count: bonus dogs (Aurion) do not count", function()
	local p = profile(9)
	p.DogDex.Aurion = true
	eq(R.MuseumCount(p), 9)
	refused(function() claim(p, 10) end, "Discover 10 dogs")
	p.DogDex[museum[10]] = true
	claim(p, 10)
end)

test("full Lucky Block storage refuses the claim and changes nothing", function()
	local p = profile(10)
	for i = 1, Lifecycle.InventoryCapacity do
		local uid = string.format("%032x", i)
		p.OwnedBlocks[uid] = { Uid = uid, OwnerUserId = 1, Tier = "Common", State = "Stored", PurchasedAt = NOW }
	end
	local before = deepCopy(p)
	refused(function() claim(p, 10) end, "storage is full")
	eq(p.DexClaims["10"], nil, "nothing claimed")
	eq(p.Bones, before.Bones)
	eq(p.Cash, before.Cash)
end)

test("coins follow the player's income (BoostPricing minutes) and the deepest layer floor", function()
	local p = profile(20)
	local tier = Rewards.ByCount[20]
	eq(Rewards.Coins(tier, p, NOW), 40000, "floor at layer 1")
	p.OfflineEarnings = { BaseRate = 250, PeakRate = 0, PeakAt = 0 }
	local expected = Pricing.Coins(tier.Coins, p, NOW)
	eq(expected, 230000, "15 minutes of 250 coins/s")
	local cash = p.Cash
	claim(p, 10)
	claim(p, 20)
	local tier10 = Pricing.Coins(Rewards.ByCount[10].Coins, p, NOW)
	eq(p.Cash - cash, tier10 + expected, "coins granted = the shown amounts")
	local deep = profile(10, { Layer = 3 })
	eq(Rewards.Coins(Rewards.ByCount[10], deep, NOW), 20000 * C.BoostPricing.LayerScale[3], "deeper layer, bigger floor")
end)

test("wallet limits: coins and bones never pass MaxCash", function()
	local p = profile(10)
	p.Cash = C.MaxCash - 5
	p.Bones = C.MaxCash - 3
	claim(p, 10)
	eq(p.Cash, C.MaxCash)
	eq(p.Bones, C.MaxCash)
	R.Validate(p)
end)

test("a whole run: every tier once, totals match the table", function()
	local p = profile(100)
	local bones, blocks = p.Bones, 0
	local expectBones, expectBlocks = 0, 0
	for _, tier in ipairs(Rewards.Tiers) do
		claim(p, tier.Count)
		expectBones += tier.Bones
		expectBlocks += tier.Block and tier.Block.Count or 0
	end
	for _ in pairs(p.OwnedBlocks) do blocks += 1 end
	eq(p.Bones - bones, expectBones, "bones")
	eq(blocks, expectBlocks, "blocks")
	for _, tier in ipairs(Rewards.Tiers) do
		refused(function() claim(p, tier.Count) end, "already claimed")
	end
	eq(Rewards.Next(p.DexClaims), nil, "nothing left")
end)

test("Engine-style transaction: a refused claim leaves the saved copy untouched", function()
	local p = profile(15)
	p.DexClaims["10"] = true
	local saved = deepCopy(p)
	local work = deepCopy(saved)
	local ok = pcall(function() claim(work, 10) end)
	eq(ok, false)
	deepEqual(saved, p)
end)

-- Normalize --------------------------------------------------------------------------------------
test("Normalize: numeric ledger keys become strings, VariantDex learns owned variants", function()
	local p = profile(3)
	p.DexClaims = { [10] = true, ["50"] = true }
	local d = R.Mint(p, "Breadog", "dog1", {}, NOW, rng(1), "Test", "Golden", true)
	p.VariantDex.Breadog = nil
	d.Variant = "Void" -- a lab reroll changes the variant without Rules.Discover
	p = R.Normalize(p, 1, NOW)
	eq(p.DexClaims["10"], true)
	eq(p.DexClaims[10], nil)
	eq(p.DexClaims["50"], true)
	eq(p.VariantDex.Breadog.Void, true, "current variant recorded")
	local again = deepCopy(p)
	p = R.Normalize(p, 1, NOW)
	deepEqual(again.VariantDex, p.VariantDex, "idempotent")
	deepEqual(again.DexClaims, p.DexClaims, "idempotent ledger")
	p.DexClaims = "broken"
	p = R.Normalize(p, 1, NOW)
	eq(type(p.DexClaims), "table", "healed")
end)

-- Snapshot and species stats --------------------------------------------------------------------
test("snapshot: rewards, counts, variant masks; stats only for discovered species; profile untouched", function()
	Feature.ResetCache()
	local p = profile(25)
	p.DogDex.Aurion = true
	p.DexClaims["10"] = true
	local d = R.Mint(p, museum[1], "dogA", {}, NOW, rng(1), "Test", "Shiny", true)
	d.AssignedSlot = "DigSlot_1"
	d.State = "Digging"
	p = R.Normalize(p, 1, NOW)
	local before = deepCopy(p)
	local view = {}
	Registry.Snapshot(R, p, view, NOW)
	deepEqual(before, p, "snapshot must not write the profile")
	local dex = view.Dogdex
	truthy(dex, "Features.Dogdex")
	eq(dex.Count, 25)
	eq(dex.Total, 100)
	eq(dex.Bonus, 1, "Aurion is a bonus dog")
	eq(dex.BonusTotal, 1)
	eq(#dex.Rewards, #Rewards.Tiers)
	eq(dex.Rewards[1].Claimed, true)
	eq(dex.Rewards[2].Claimed, false)
	eq(dex.Rewards[2].Coins, Rewards.Coins(Rewards.Tiers[2], p, NOW))
	local n = 0
	for id, s in pairs(dex.DexStats) do
		n += 1
		truthy(p.DogDex[id] == true, "only discovered: " .. id)
		truthy(s.C > 0 and s.D > 0 and s.E > 0, "positive stats " .. id)
	end
	eq(n, 26, "25 museum dogs + Aurion")
	eq(dex.DexStats[museum[30]], nil, "undiscovered species hidden")
	local set = Info.VariantsOf(dex.VariantDex[museum[1]])
	truthy(set.Shiny, "Shiny recorded in the mask")
	local size = #serde.encode("json", dex)
	truthy(size < 6000, "small payload: " .. size .. " bytes")
end)

test("species stats = the income model of a lone Normal mastery-0 dog with the player's bonuses", function()
	Feature.ResetCache()
	local p = profile(40, { Layer = 2 })
	p.Upgrades.Dig = 3
	local stats = Feature.Stats(R, p, NOW)
	for _, id in ipairs({ museum[1], museum[3], museum[25], museum[40] }) do
		local solo = profile(0, { Layer = 2 })
		solo.Upgrades.Dig = 3
		local dog = R.Mint(solo, id, "solo", {}, NOW, rng(1), "Test", "Normal", true)
		dog.Mastery = 0
		local model = R.IncomeModel(solo, NOW)
		local m = model.Dogs.solo
		local s = stats[id]
		near(s.C, m.CoinsPerMin, math.max(1, m.CoinsPerMin * 0.006), id .. " coins/min")
		near(s.D, m.DigsPerMin, 0.006, id .. " digs/min")
		near(s.E, m.Efficiency, 0.006, id .. " efficiency")
		near(s.L, m.LuckPct, 0.06, id .. " luck")
	end
	-- Potatodog digs slower than a plain Common, Pelmendog earns more (audit measurements).
	truthy(stats.Potatodog.D < stats.Breadog.D, "Potatodog is slow")
end)

test("species stats are cached and follow the depth", function()
	Feature.ResetCache()
	local p = profile(20, { Layer = 3 })
	local a = Feature.Stats(R, p, NOW)
	local b = Feature.Stats(R, p, NOW + 5)
	eq(a, b, "cache hit")
	p.CurrentLayer = 1
	local c = Feature.Stats(R, p, NOW + 6)
	truthy(c ~= a and c.Breadog.C < a.Breadog.C, "shallower layer earns less")
	local d = Feature.Stats(R, p, NOW + 6 + Feature.CacheSeconds + 1)
	truthy(d ~= c, "expires")
end)

test("rewards of Features.Dogdex survive a snapshot error in stats", function()
	local p = profile(5)
	local saved = Feature.Stats
	Feature.Stats = function() error("boom") end
	local view = {}
	Feature.Snapshot(R, p, view, NOW)
	Feature.Stats = saved
	truthy(view.Dogdex and #view.Dogdex.Rewards == #Rewards.Tiers and next(view.Dogdex.DexStats) == nil)
end)

-- Modules.DogInfo --------------------------------------------------------------------------------
local function entry(id, opts)
	opts = opts or {}
	local def = D[id]
	local d = { DogUid = opts.Uid or id, DogId = id, DisplayName = def.DisplayName, Rarity = def.Rarity, Variant = opts.Variant or "Normal",
		Mastery = opts.Mastery or 0, AscensionLevel = opts.Ascension or 0, AssignedSlot = opts.Slot or "", State = opts.State or "Inventory",
		Locked = opts.Locked, Favorite = opts.Favorite, CreatedAt = opts.CreatedAt or 0 }
	return Info.Entry(d, opts.Stats or {}, opts.Name)
end

test("DogInfo: fold and upper handle Cyrillic", function()
	eq(Info.Fold("КОФЕЙНЫЙ Пёс Ёж"), "кофейный пёс ёж")
	eq(Info.Upper("кофейный пёс"), "КОФЕЙНЫЙ ПЁС")
	eq(Info.Fold("Coffee DOG"), "coffee dog")
end)

test("DogInfo: filters (search, digging/idle, locked, favorite, rarity, variant)", function()
	local list = {
		entry("Breadog", { Uid = "a", Slot = "DigSlot_1", State = "Digging" }),
		entry("Breadog", { Uid = "b", Variant = "Golden", Locked = true }),
		entry("CoffeeDog", { Uid = "c", Favorite = true, Name = "Кофейный пёс" }),
		entry("TheDog", { Uid = "d", Variant = "Void", State = "Walking" }),
	}
	local function ids(filter)
		local out = {}
		for _, e in ipairs(list) do if Info.Match(e, filter) then table.insert(out, e.Uid) end end
		return table.concat(out, ",")
	end
	eq(ids({}), "a,b,c,d")
	eq(ids({ Query = "bread" }), "a,b")
	eq(ids({ Query = Info.Fold("КОФЕ") }), "c", "Russian name")
	eq(ids({ Query = "coffee" }), "c", "English name still matches")
	eq(ids({ States = { Digging = true } }), "a")
	eq(ids({ States = { Idle = true } }), "b,c,d")
	eq(ids({ States = { Digging = true, Idle = true } }), "a,b,c,d")
	eq(ids({ States = { Locked = true } }), "b")
	eq(ids({ States = { Favorite = true } }), "c")
	eq(ids({ Rarities = { Secret = true } }), "d")
	eq(ids({ Rarities = { Secret = true, Common = true } }), "a,b,c,d")
	eq(ids({ Rarities = { Rare = true } }), "")
	eq(ids({ Variant = "Mutated" }), "b,d")
	eq(ids({ Variant = "Golden" }), "b")
	eq(ids({ Variant = "Normal", States = { Idle = true } }), "c")
	eq(Info.State(list[4].Dog), "Arriving")
	eq(Info.Slot(list[1].Dog), 1)
end)

test("DogInfo: sorts by rarity, efficiency, income, dig speed, newest, mastery, name", function()
	local list = {
		entry("Breadog", { Uid = "a", Stats = { Efficiency = 1.1, CoinsPerMin = 900, DigsPerMin = 2.5 }, CreatedAt = 30, Mastery = 5 }),
		entry("TheDog", { Uid = "b", Stats = { Efficiency = 9, CoinsPerMin = 9000, DigsPerMin = 2.0 }, CreatedAt = 10, Mastery = 1 }),
		entry("CoffeeDog", { Uid = "c", Stats = { Efficiency = 2.2, CoinsPerMin = 1500, DigsPerMin = 3.1 }, CreatedAt = 20, Mastery = 9 }),
		entry("Potatodog", { Uid = "d", Stats = { Efficiency = 0.9, CoinsPerMin = 700, DigsPerMin = 1.9 }, CreatedAt = 40, Mastery = 0 }),
	}
	local function order(key, desc)
		local out = {}
		for _, e in ipairs(Info.SortEntries(list, key, desc)) do table.insert(out, e.Uid) end
		return table.concat(out, ",")
	end
	eq(order("rarity", true), "b,c,a,d", "rarity, then efficiency inside a rarity")
	eq(order("efficiency", true), "b,c,a,d")
	eq(order("efficiency", false), "d,a,c,b")
	eq(order("income", true), "b,c,a,d")
	eq(order("speed", true), "c,a,b,d")
	eq(order("newest", true), "d,a,c,b")
	eq(order("mastery", true), "c,a,b,d")
	eq(order("name", false), "a,c,d,b")
	eq(#Info.SortEntries({}, "rarity", true), 0)
end)

test("DogInfo: compare picks the better value per stat and the overall winner", function()
	local a = entry("Breadog", { Variant = "Golden", Mastery = 40, Stats = { CoinsPerMin = 1000, Efficiency = 1.3, DigsPerMin = 2.8, LuckPct = 0, ItemFindsPerMin = 2 } })
	local b = entry("Samuriba", { Ascension = 2, Stats = { CoinsPerMin = 1250, Efficiency = 1.6, DigsPerMin = 2.8, LuckPct = 5, ItemFindsPerMin = 2 } })
	local result = Info.Compare(a, b)
	eq(result.Winner, "b")
	near(result.IncomeGain, 0.25, 1e-9, "b earns 25% more")
	local by = {}
	for _, row in ipairs(result.Rows) do by[row.Id] = row end
	eq(by.income.Better, "b")
	eq(by.speed.Better, nil, "a tie has no better side")
	eq(by.variant.Better, "a", "Golden beats Normal")
	eq(by.mastery.Better, "a")
	eq(by.ascension.Better, "b")
	eq(by.power.Better, "b", "Rare power over Common")
	eq(Info.Compare(a, a).Winner, nil, "same dog: no winner")
	local bonus = Info.Bonus({ Variant = "Golden", Mastery = 100, AscensionLevel = 3 })
	near(bonus.Total, 0.30 + 0.15 + C.Ascension[4], 1e-9, "Rules.Bonus mirror")
	near(R.Bonus({ Variant = "Golden", Mastery = 100, AscensionLevel = 3 }), 1 + bonus.Total, 1e-9, "same as Rules.Bonus")
end)

test("DogInfo: line chances add up to 1, sources per species", function()
	local total = 0
	for _, def in pairs(D) do total += Info.LineChance(def) or 0 end
	near(total, 1, 1e-9, "every dog on the line")
	truthy(Info.LineChance(D.TheDog) < Info.LineChance(D.Cubedog), "THE DOG is the rarest secret")
	eq(Info.LineChance(D.Aurion), nil, "Aurion never walks the line")
	local function keys(id)
		local out = {}
		for _, s in ipairs(Info.Sources(D[id])) do table.insert(out, s.Key) end
		return table.concat(out, ",")
	end
	eq(keys("Aurion"), "Jackpot,Trade")
	eq(keys("TheDog"), "Line,Trade")
	eq(keys("Breadog"), "Line,Lucky,Machine,Trade")
	local lucky = Info.Sources(D.Breadog)[2]
	truthy(table.find(lucky.Tiers, "Common") and table.find(lucky.Tiers, "Rare") and not table.find(lucky.Tiers, "Mythic"), "Common dogs come from Common/Rare blocks")
end)

test("DogInfo: species entries, filters and sorts (undiscovered names stay secret)", function()
	local p = profile(5)
	R.Mint(p, museum[2], "own1", {}, NOW, rng(1), "Test", "Normal", true)
	R.Mint(p, museum[2], "own2", {}, NOW, rng(1), "Test", "Golden", true).Mastery = 12
	p.DexFavorites[museum[3]] = true
	local stats = Feature.Stats(R, p, NOW)
	local list = Info.SpeciesEntries(p, { DexStats = stats }, nil)
	eq(#list, #Info.Species)
	eq(list[1].Id, museum[1], "Dogdex order")
	eq(list[#list].Id, "Aurion", "bonus dogs last")
	local e2 = list[2]
	eq(e2.Owned, 2)
	eq(e2.BestMastery, 12)
	local function count(filter)
		local n = 0
		for _, e in ipairs(list) do if Info.MatchSpecies(e, filter) then n += 1 end end
		return n
	end
	eq(count({ Found = true }), 5)
	eq(count({ Missing = true }), #Info.Species - 5)
	eq(count({ Found = true, Missing = true }), #Info.Species)
	eq(count({ Favorite = true }), 1)
	eq(count({ Owned = true }), 1)
	eq(count({ Query = Info.Fold(D[museum[60]].DisplayName) }), 0, "undiscovered name is not searchable")
	eq(count({ Query = "60" }), 1, "the Dogdex number is")
	eq(count({ Query = Info.Fold(D[museum[1]].DisplayName) }) >= 1, true)
	eq(count({ Rarities = { Secret = true } }), 11)
	local sorted = Info.SortSpecies(list, "income", true)
	truthy(sorted[1].Stats and sorted[5].Stats and not sorted[6].Stats, "discovered first")
	truthy(sorted[1].Stats.C >= sorted[2].Stats.C, "income descending")
	local byRarity = Info.SortSpecies(list, "rarity", true)
	eq(byRarity[1].Def.Rarity, "Secret")
	eq(Info.SortSpecies(list, "number", false)[1].Id, museum[1])
end)

test("DogInfo: variant masks and reward rows", function()
	local set, n = Info.VariantsOf(1 + 4 + 32)
	truthy(set.Normal and set.Golden and set.Void and not set.Shiny)
	eq(n, 3)
	local _, n2 = Info.VariantsOf({ Shiny = true, Bogus = true })
	eq(n2, 1)
	local p = profile(31)
	p.DexClaims["10"] = true
	local rows, count = Info.RewardRows(nil, p)
	eq(count, 31)
	eq(rows[1].State, "claimed")
	eq(rows[2].State, "ready")
	eq(rows[3].State, "ready")
	eq(rows[4].State, "locked")
	eq(rows[4].Missing, 9)
	local ready, nextLocked = Info.RewardSummary(rows)
	eq(ready, 2)
	eq(nextLocked.Count, 40)
	local view = {}
	Feature.Snapshot(R, p, view, NOW)
	local rows2 = Info.RewardRows(view.Dogdex, p)
	eq(rows2[2].Coins, view.Dogdex.Rewards[2].Coins, "server coin amounts")
	eq(rows2[1].State, "claimed")
end)

-- Russian strings of the two windows -------------------------------------------------------------
test("every self-localized string of DogsScreen / DogdexScreen has a Russian entry", function()
	local Dict = L.Require("ReplicatedStorage.Localization.Dogs")
	local missing = {}
	local total = 0
	for _, file in ipairs({ "src/StarterGui/ScreenGui/Modules/DogsScreen.luau", "src/StarterGui/ScreenGui/Modules/DogdexScreen.luau" }) do
		local source = fs.readFile(file)
		-- Label / Tip fields of the stat tables are passed through T() when shown.
		for field, text in string.gmatch(source, "\n%s*(%a+) = \"([^\"]*)\",") do
			if field == "Label" or field == "Tip" then
				total += 1
				if not (Dict.UI[text] or Dict.Exact[text]) then table.insert(missing, field .. ": " .. text) end
			end
		end
		for kind, quote, text in string.gmatch(source, "[^%w_]([TF])%((['\"])(.-)%2") do
			total += 1
			local ru = kind == "T" and (Dict.UI[text] or Dict.Exact[text]) or Dict.Templates[text]
			if not ru then table.insert(missing, kind .. ": " .. text) end
			if ru and kind == "F" then
				local _, a = string.gsub(text, "%%[%d%.]*[dsf]", "")
				local _, b = string.gsub(ru, "%%[%d%.]*[dsf]", "")
				if a ~= b then table.insert(missing, "placeholders differ: " .. text) end
			end
			if ru then
				local bare = string.gsub(string.gsub(string.gsub(ru, "<[^>]+>", ""), "%%[%d%.]*[dsf]", ""), "%f[%a]x%f[%A]", "")
				if string.find(bare, "[A-Za-z]") then
					table.insert(missing, "Latin in Russian: " .. text .. " -> " .. ru)
				end
			end
		end
	end
	truthy(total > 60, "strings found: " .. total)
	truthy(#missing == 0, table.concat(missing, " | "))
	-- Server replies the windows show (left to DOGROTS_AutoTranslateUI).
	for _, text in ipairs({ "Dogdex reward claimed", "Reward already claimed", "Invalid milestone", "Dog assigned to dig", "Returned to storage",
		"Kennel occupied", "Unlock this dog first", "Visit DOG STORAGE in your own yard", "Display slot cleared",
		"Your Lucky Block storage is full. Open a block, then claim this reward" }) do
		truthy(Dict.Exact[text], "server reply " .. text)
	end
	local function pattern(text)
		for _, rule in ipairs(Dict.Patterns) do
			local out, n = string.gsub(text, rule[1], rule[2])
			if n > 0 then return out end
		end
	end
	truthy(pattern("Discover 40 dogs to unlock this reward"), "unlock pattern")
	truthy(pattern("Breadog placed in display 2"), "display pattern")
end)

print(string.format("dogdex: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("dogdex tests failed")
end
