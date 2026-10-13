--!nolint
-- MY BAG logic (Modules.InventoryLogic): rarity, rows, filters, sorts, showcase marks, Lucky Block
-- grouping, capacity, sell safety and market prices, for a fresh profile and an old one.
-- lune run tests/inventory.luau
local L = require("./lib/economy_env")
local Logic = L.Require("StarterGui.ScreenGui.Modules.InventoryLogic")
local Definitions = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local ValueConfig = L.Require("ReplicatedStorage.ItemValueConfig")
local Valuation = L.Require("ReplicatedStorage.ItemValuation")
local Blocks = L.Require("ReplicatedStorage.LuckyBlockConfig")

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

local function ctx(extra)
	local c = {
		Definitions = Definitions,
		ValueConfig = ValueConfig,
		Price = function(item)
			return (Valuation.Price(item))
		end,
		Showcase = {},
	}
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end

-- A few real item ids of different rarities.
local byRarity = {}
local ids = {}
for id, def in pairs(Definitions) do
	table.insert(ids, id)
	local rarity = Logic.Rarity(def, ValueConfig)
	byRarity[rarity] = byRarity[rarity] or id
end
table.sort(ids)

local function item(uid, id, fields)
	local def = Definitions[id]
	local x = {
		ItemUid = uid,
		ItemId = id,
		DisplayName = def.DisplayName,
		Depth = def.Depth,
		Class = def.Class,
		WeightKg = def.BaseWeightKg,
		TierIndex = 3,
		Mutation = "NORMAL",
		FoundAt = 100,
		Favorite = false,
		Tradeable = true,
		CombinedOdds = 1 / def.BaseDropChance,
	}
	for k, v in pairs(fields or {}) do
		x[k] = v
	end
	return x
end

test("rarity follows ItemValuation for every definition", function()
	local n = 0
	for _, id in ipairs(ids) do
		local def = Definitions[id]
		local _, info = Valuation.Price({ ItemId = id, WeightKg = def.BaseWeightKg, Mutation = "NORMAL" })
		eq(Logic.Rarity(def, ValueConfig), info.Rarity, id)
		n += 1
	end
	truthy(n > 50, "definitions " .. n)
	eq(Logic.Rarity(nil, ValueConfig), "Common")
	truthy(byRarity.Common and byRarity.Rare, "found common and rare items")
end)

test("fresh profile: empty bag, empty blocks", function()
	eq(#Logic.Rows({}, ctx()), 0)
	eq(#Logic.Rows({ Items = {} }, ctx()), 0)
	eq(#Logic.Rows(nil, ctx()), 0)
	eq(#Logic.Blocks({}, 0, Blocks), 0)
	eq(#Logic.Blocks(nil, 0, Blocks), 0)
	eq(next(Logic.ShowcaseSet(nil, {})), nil)
	local cap = Logic.Capacity(nil, nil)
	eq(cap.Full, false)
	eq(cap.Fraction, 0)
end)

test("old profile items without the newer fields still make rows", function()
	local id = byRarity.Common
	local old = { ItemId = id, WeightKg = Definitions[id].BaseWeightKg } -- no Mutation, FoundAt, Favorite, DisplayName, Depth
	local rows = Logic.Rows({ Items = { u1 = old } }, ctx())
	eq(#rows, 1)
	local r = rows[1]
	eq(r.Key, "u1")
	eq(r.Mutation, "NORMAL")
	eq(r.Favorite, false)
	eq(r.FoundAt, 0)
	eq(r.Name, Definitions[id].DisplayName)
	eq(r.Depth, Definitions[id].Depth)
	truthy(r.Value >= 1, "value from ItemValuation")
	truthy(r.Tradeable, "tradeable unless false")
	-- A broken price function falls back to SellValue.
	local rows2 = Logic.Rows({ Items = { u1 = { ItemId = "nope", SellValue = 42 } } }, ctx())
	eq(rows2[1].Value, 42)
	eq(rows2[1].Rarity, "Common")
end)

local function sample()
	local profile = { Items = {} }
	local common, rare = byRarity.Common, byRarity.Rare
	local top = byRarity.Legendary or byRarity.Epic or rare
	profile.Items.a = item("a", common, { FoundAt = 10, WeightKg = 1, Mutation = "NORMAL" })
	profile.Items.b = item("b", common, { FoundAt = 30, WeightKg = 9, Mutation = "GOLDEN", Favorite = true })
	profile.Items.c = item("c", rare, { FoundAt = 20, WeightKg = 3, Mutation = "RAINBOW" })
	profile.Items.d = item("d", top, { FoundAt = 5, WeightKg = 0.5, Mutation = "NORMAL" })
	return profile, Logic.Rows(profile, ctx({ Showcase = { d = true } }))
end

test("filters: search, rarity chips, depth, mutation, favourites", function()
	local _, rows = sample()
	eq(#rows, 4)
	eq(#Logic.Filter(rows, {}), 4)
	eq(#Logic.Filter(rows, { Favorites = true }), 1)
	eq(#Logic.Filter(rows, { Mutations = { "GOLDEN" } }), 1)
	eq(#Logic.Filter(rows, { Mutations = { GOLDEN = true, RAINBOW = true } }), 2)
	eq(#Logic.Filter(rows, { Mutations = {} }), 4, "an empty set means any")
	eq(#Logic.Filter(rows, { Query = "golden" }), 1, "mutation words are searchable")
	eq(#Logic.Filter(rows, { Query = "   " }), 4, "blank search")
	local name = string.lower(rows[1].Name)
	truthy(#Logic.Filter(rows, { Query = string.upper(string.sub(name, 1, 3)) }) >= 1, "case-insensitive name search")
	eq(#Logic.Filter(rows, { Query = "zzzz-no-such" }), 0)
	local common = 0
	for _, r in ipairs(rows) do
		if r.Rarity == "Common" then
			common += 1
		end
	end
	eq(#Logic.Filter(rows, { Rarities = { "Common" } }), common)
	eq(#Logic.Filter(rows, { Rarities = { Common = true } }), common)
	local depth = rows[1].Depth
	local atDepth = 0
	for _, r in ipairs(rows) do
		if r.Depth == depth then
			atDepth += 1
		end
	end
	eq(#Logic.Filter(rows, { Depth = depth }), atDepth)
	eq(Logic.ExtraFilters({ Depth = 2, Mutations = { "GOLDEN", "VOID" }, Favorites = true }), 4)
	eq(Logic.ExtraFilters({}), 0)
	eq(Logic.Filtering({ Query = " " }), false)
	eq(Logic.Filtering({ Rarities = { "Epic" } }), true)
	eq(Logic.Filtering({ Rarities = {} }), false)
end)

test("sorts: rarest, newest, value, heaviest, name (and flipped)", function()
	local _, rows = sample()
	local function keys(list)
		local out = {}
		for _, r in ipairs(list) do
			table.insert(out, r.Key)
		end
		return table.concat(out, "")
	end
	eq(keys(Logic.Sort(rows, "newest")), "bcad")
	eq(keys(Logic.Sort(rows, "newest", false)), "dacb")
	eq(keys(Logic.Sort(rows, "heaviest")), "bcad")
	local rarest = Logic.Sort(rows, "rarest")
	for i = 2, #rarest do
		truthy(rarest[i - 1].Rank >= rarest[i].Rank, "rarest order")
	end
	local value = Logic.Sort(rows, "value")
	for i = 2, #value do
		truthy(value[i - 1].Value >= value[i].Value, "value order")
	end
	local name = Logic.Sort(rows, "name")
	for i = 2, #name do
		truthy(string.lower(name[i - 1].Name) <= string.lower(name[i].Name), "name A-Z")
	end
	-- Equal keys keep a stable order (rank, value, uid).
	local twins = Logic.Rows({ Items = { z = item("z", byRarity.Common), y = item("y", byRarity.Common) } }, ctx())
	eq(keys(Logic.Sort(twins, "newest")), "yz")
	eq(keys(Logic.View(rows, { Sort = "newest", Desc = true, Favorites = true })), "b")
	eq(Logic.SortDescending.name, false)
	eq(#Logic.Sorts, 5)
end)

test("showcase marks: optional feature, any shape, unknown uids ignored", function()
	local profile = sample()
	eq(next(Logic.ShowcaseSet({}, profile.Items)), nil)
	local set = Logic.ShowcaseSet({ Features = { Showcase = { Slots = { "a", "nope", "c" } } } }, profile.Items)
	truthy(set.a and set.c and not set.nope, "slot list")
	set = Logic.ShowcaseSet({ Showcase = { Pinned = { b = true } } }, profile.Items)
	truthy(set.b, "map form")
	set = Logic.ShowcaseSet({ Features = { Showcase = { Slots = { { Uid = "d" } } } } }, profile.Items)
	truthy(set.d, "nested slot records")
	local _, rows = sample()
	for _, r in ipairs(rows) do
		eq(r.Showcase, r.Key == "d", "row " .. r.Key)
	end
end)

test("mutation options: present ones, most valuable first", function()
	local _, rows = sample()
	local list = Logic.Mutations(rows, ValueConfig)
	eq(#list, 2)
	eq(list[1], "RAINBOW")
	eq(list[2], "GOLDEN")
end)

test("lucky blocks group by tier: stacks, stored, placed, ready", function()
	local now = 1000
	local profile = {
		LuckyCredits = { Epic = 2, Rare = 0, Uncommon = 1 },
		OwnedBlocks = {
			s1 = { Uid = "s1", Tier = "Epic", State = "Stored" },
			p1 = { Uid = "p1", Tier = "Epic", State = "Placed", ReadyAt = now + 30 },
			p2 = { Uid = "p2", Tier = "Epic", State = "Placed", ReadyAt = now - 5 },
			r1 = { Uid = "r1", Tier = "Legendary", State = "Ready", ReadyAt = now - 50 },
			x = "broken",
		},
	}
	local groups = Logic.Blocks(profile, now, Blocks)
	eq(#groups, 3)
	eq(groups[1].Tier, "Legendary")
	eq(groups[1].Ready, 1)
	eq(groups[1].Uid, "r1")
	local epic = groups[2]
	eq(epic.Tier, "Epic")
	eq(epic.Count, 5)
	eq(epic.Stored, 3)
	eq(epic.Placed, 2)
	eq(epic.Ready, 1)
	eq(epic.NextReadyAt, now + 30)
	eq(epic.Uid, "s1", "a stored block shows the odds first")
	eq(groups[3].Tier, "Rare", "legacy Uncommon credits count as Rare")
	eq(groups[3].Count, 1)
	eq(Logic.BlockCount(groups), 7)
end)

test("capacity and sell safety", function()
	local c = Logic.Capacity(40, 50)
	eq(c.Warn, true)
	eq(c.Full, false)
	c = Logic.Capacity(50, 50)
	eq(c.Full, true)
	eq(c.Fraction, 1)
	eq(Logic.Capacity(60, 50).Fraction, 1)
	eq(Logic.SellHold("Common"), 0)
	eq(Logic.SellHold("Rare"), 0)
	eq(Logic.SellHold("Epic"), 1)
	eq(Logic.SellHold("Secret"), 1)
	eq(Logic.SellHold("Common", true), 1, "favourites are held too")
	local _, rows = sample()
	local total = 0
	for _, r in ipairs(rows) do
		total += r.Value
	end
	eq(Logic.TotalValue(rows), total)
end)

test("market price input, fee and hints", function()
	eq(Logic.ParsePrice("1,234"), 1234)
	eq(Logic.ParsePrice(" 2 500 "), 2500)
	eq(Logic.ParsePrice("12k"), 12000)
	eq(Logic.ParsePrice("1.5M"), 1500000)
	local v, why = Logic.ParsePrice("abc")
	eq(v, nil)
	eq(why, "invalid")
	v, why = Logic.ParsePrice("")
	eq(why, "empty")
	v, why = Logic.ParsePrice("5")
	eq(why, "low")
	v, why = Logic.ParsePrice("2000", 10, 1000)
	eq(why, "high")
	eq(Logic.ParsePrice("10"), 10)
	eq(Logic.Fee(10), 1)
	eq(Logic.Fee(1000), 10)
	eq(Logic.Fee(1001), 11)
	local hints = Logic.PriceHints(1000)
	eq(#hints, 4)
	eq(hints[1], 1000)
	eq(hints[3], 2000)
	eq(Logic.PriceHints(3)[1], 10, "never below the minimum")
end)

test("weight text", function()
	eq(Logic.WeightText(0.25), "250 g")
	eq(Logic.WeightText(4.21), "4.2 kg")
	eq(Logic.WeightText(37.4), "37 kg")
	eq(Logic.WeightText(1500, function(n)
		return string.format("%.1fK", n / 1000)
	end), "1.5K kg")
end)

print(string.format("inventory: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("inventory tests failed")
end
