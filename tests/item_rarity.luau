--!nocheck
--!nolint
-- ReplicatedStorage.ItemRarity: tiers, the price rule (ItemValuation.Rarity), colours in sync with
-- Kit.Theme.ItemRarity, labels: lune run tests/item_rarity.luau
-- Prints the tier distribution of the item catalogue (docs/OVERHAUL.md quotes it).
local process = require("@lune/process")
local L = require("./lib/economy_env")
local Rarity = L.Require("ReplicatedStorage.ItemRarity")
local Valuation = L.Require("ReplicatedStorage.ItemValuation")
local ValueConfig = L.Require("ReplicatedStorage.ItemValueConfig")
local Defs = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local Theme = L.Require("StarterGui.ScreenGui.Modules.Kit.Theme")

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
local function rgb(c)
	return math.floor(c.R * 255 + 0.5) .. "," .. math.floor(c.G * 255 + 0.5) .. "," .. math.floor(c.B * 255 + 0.5)
end

test("tiers are the ItemValueConfig rarities, lowest first", function()
	local names = {}
	for _, row in ValueConfig.Rarity do
		names[row.Name] = row.MaxChance
	end
	eq(#Rarity.Tiers, 6)
	local n = 0
	for _ in names do
		n += 1
	end
	eq(n, #Rarity.Tiers, "same count")
	for i, tier in Rarity.Tiers do
		truthy(names[tier], tier .. " is a value rarity")
		eq(Rarity.Order(tier), i)
		if i > 1 and tier ~= "Secret" then
			truthy(names[tier] < names[Rarity.Tiers[i - 1]], tier .. " is rarer than " .. Rarity.Tiers[i - 1])
		end
	end
	eq(Rarity.Order("Mythic"), 0)
	eq(Rarity.Order(nil), 0)
end)

test("Of follows the price rule for every item, by id, definition or find", function()
	local count = 0
	for id, def in Defs do
		count += 1
		local tier, multiplier = Valuation.Rarity(def)
		eq(Rarity.Of(id), tier, id)
		eq(Rarity.Of(def), tier, id .. " def")
		eq(Rarity.Of({ ItemId = id, BaseDropChance = 1, Class = "Common" }), tier, id .. " find (the definition wins)")
		local _, breakdown = Valuation.Price({ ItemId = id, WeightKg = def.BaseWeightKg, TierIndex = 3, Mutation = "Normal" })
		eq(breakdown.Rarity, tier, id .. " price breakdown")
		eq(breakdown.Factors.Rarity, multiplier, id .. " multiplier")
		if def.Class == "Secret" then
			eq(tier, "Secret", id)
		end
	end
	eq(count, 108, "item catalogue size")
	eq(Rarity.Of({ BaseDropChance = 0.5, Class = "Treasure" }), "Common", "a definition-like table")
	eq(Rarity.Of({ BaseDropChance = 0.00005, Class = "Artifact" }), "Legendary")
	eq(Rarity.Of("no_such_item"), nil)
	eq(Rarity.Of({ ItemId = "no_such_item" }), nil)
	eq(Rarity.Of(nil), nil)
	eq(Rarity.Of(7), nil)
end)

test("colours are the Kit.Theme.ItemRarity colours", function()
	for _, tier in Rarity.Tiers do
		truthy(Theme.ItemRarity[tier], "Theme.ItemRarity." .. tier)
		eq(rgb(Rarity.Color(tier)), rgb(Theme.ItemRarity[tier]), tier)
	end
	for tier in Theme.ItemRarity do
		truthy(Rarity.Colors[tier], "ItemRarity.Colors." .. tier)
	end
	eq(rgb(Rarity.Color("Nope")), rgb(Theme.ItemRarity.Common), "unknown -> Common")
	eq(rgb(Rarity.Color(nil)), rgb(Theme.ItemRarity.Common))
end)

test("every tier has an English and a Russian label", function()
	for _, tier in Rarity.Tiers do
		eq(Rarity.Label(tier), string.upper(tier))
		local ru = Rarity.Label(tier, "ru")
		truthy(ru ~= "" and ru ~= Rarity.Label(tier) and ru:find("[\208\209]"), tier .. " Russian label " .. ru)
		eq(Rarity.LabelsRU[tier], ru)
	end
	eq(Rarity.Label("Nope"), "")
	eq(Rarity.Label(nil, "ru"), "")
end)

-- Distribution of the catalogue (kept in docs/OVERHAUL.md).
local byTier = {}
for _, def in Defs do
	local tier = Rarity.Of(def)
	byTier[tier] = (byTier[tier] or 0) + 1
end
local parts = {}
for _, tier in Rarity.Tiers do
	table.insert(parts, tier .. "=" .. (byTier[tier] or 0))
end
print("item_rarity distribution: " .. table.concat(parts, " "))

print(("item_rarity: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
