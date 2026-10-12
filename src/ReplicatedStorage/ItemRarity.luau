-- ItemRarity: the one rarity of a find (discovery item) for every screen, card, showcase and model.
-- The rule is ItemValuation.Rarity (the price rule: Class 'Secret', then BaseDropChance against
-- ItemValueConfig.Rarity), so a find's rarity and its price multiplier never disagree.
--   Tiers                  {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret"}, lowest first
--   Of(x) -> tier?         x = an ItemId, an item definition or a find ({ItemId=...}); nil if unknown
--   Order(tier) -> 1..6    0 for an unknown tier (sort keys)
--   Color(tier) -> Color3  the same values as Kit.Theme.ItemRarity (tests/item_rarity.luau checks it);
--                          Common for an unknown tier
--   Label(tier, lang?)     upper-case label: English, or Russian when lang == "ru" (LabelsRU, the
--                          feminine form agrees with «находка»); "" for an unknown tier
-- Mutations are a separate axis (Kit.Theme.Mutation): they change the price, not the rarity.
local RS = game:GetService("ReplicatedStorage")
local Valuation = require(RS:WaitForChild("ItemValuation"))
local Definitions = require(RS:WaitForChild("DogEconomy"):WaitForChild("ItemDefinitions"))

local ItemRarity = {}
ItemRarity.Tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }
ItemRarity.Rank = {}
for i, tier in ipairs(ItemRarity.Tiers) do
	ItemRarity.Rank[tier] = i
end
ItemRarity.Colors = {
	Common = Color3.fromRGB(170, 190, 205),
	Uncommon = Color3.fromRGB(125, 219, 48),
	Rare = Color3.fromRGB(38, 164, 243),
	Epic = Color3.fromRGB(161, 103, 242),
	Legendary = Color3.fromRGB(249, 180, 35),
	Secret = Color3.fromRGB(230, 115, 245),
}
ItemRarity.Labels = {
	Common = "COMMON",
	Uncommon = "UNCOMMON",
	Rare = "RARE",
	Epic = "EPIC",
	Legendary = "LEGENDARY",
	Secret = "SECRET",
}
ItemRarity.LabelsRU = {
	Common = "ОБЫЧНАЯ",
	Uncommon = "НЕОБЫЧНАЯ",
	Rare = "РЕДКАЯ",
	Epic = "ЭПИЧЕСКАЯ",
	Legendary = "ЛЕГЕНДАРНАЯ",
	Secret = "СЕКРЕТНАЯ",
}

local function definition(x: any): any
	if type(x) == "string" then
		return Definitions[x]
	elseif type(x) ~= "table" then
		return nil
	end
	if type(x.ItemId) == "string" then
		return Definitions[x.ItemId]
	end
	if type(x.Id) == "string" and Definitions[x.Id] then
		return Definitions[x.Id]
	end
	if type(x.BaseDropChance) == "number" then
		return x
	end
	return nil
end

function ItemRarity.Of(x: any): string?
	local def = definition(x)
	if not def then
		return nil
	end
	return (Valuation.Rarity(def))
end

function ItemRarity.Order(tier: string?): number
	return tier and ItemRarity.Rank[tier] or 0
end

function ItemRarity.Color(tier: string?): Color3
	return tier and ItemRarity.Colors[tier] or ItemRarity.Colors.Common
end

function ItemRarity.Label(tier: string?, lang: string?): string
	local labels = lang == "ru" and ItemRarity.LabelsRU or ItemRarity.Labels
	return tier and labels[tier] or ""
end

return ItemRarity
