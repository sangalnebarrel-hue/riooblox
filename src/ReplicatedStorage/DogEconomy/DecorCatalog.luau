-- Plot decorations: 6 categories x 6 items (+ the NIGHT OF THE BURIED MOON reward categories), the decor slots of a yard and the shared rules
-- (server feature Economy.Features.Decor, world Economy.PlotDecorWorld, window Modules.DecorScreen).
-- Models: ReplicatedStorage.Decor.DecorModels (one Forge recipe per Id). Docs: docs/PLOT_COSMETICS.md.
--
-- Prices are "minutes of income at the yard stage that unlocks the item" (docs/ECONOMY.md §5/§12:
-- ~1.5K/min at stage 1, ~6K at stage 4, ~30K at stage 5, ~100K at stage 6, ~1M at stage 7-8 and
-- 4M+ at stage 9) plus Stone from active mining at the Mining Corner (~320-580 per hour early,
-- 1.3-2.6K mid, 4.1-4.7K late): a few minutes of mining for early pieces, tens of minutes to two
-- hours for late ones. Small 15K-2M coins + 20-1,000 Stone, Large 150K-150M coins + 150-9,000
-- Stone; the three Mythic pieces also cost Bones. Late pieces stay aspirational.
--
-- Slots are in yard-frame coordinates (PlotAppearance.Frame): x' = local X * sx (sx = -1 on the
-- mirrored east yards), z towards the gate (+64) / storage (-64). Decorations face the central
-- walkway. Large slots fill the free zones Z1 (x' 9..32, z 7..17) and Z2 (x' -32..-9, z 7..17);
-- small slots are the fence-side plant strips (x' = ±31) and path spots beside the walkway
-- (x' = ±5.9, between the walkway and the kennel pits, in the gaps between pits and walkway
-- lamps: z 48 / 32 / 12 / -8 / -28). The mine headframe zone (x' 8..32,
-- z -30..-42) and every route stay clear.
--   Small footprint: <= 3.2 wide (along the walkway) x 2.6 deep at the ground, <= 4 x 3.4 above 3 studs.
--   Large footprint: <= 9.6 wide x 11 deep.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotCatalog = require(ReplicatedStorage:WaitForChild("PlotCatalog"))

local D = {}
D.Version = 1

D.Categories = {
	{ Id = "Buildings", Name = "BUILDINGS", RU = "ЗДАНИЯ", Size = "Large", Icon = "🏠" },
	{ Id = "Plants", Name = "PLANTS", RU = "РАСТЕНИЯ", Size = "Small", Icon = "🌳" },
	{ Id = "Lighting", Name = "LIGHTING", RU = "СВЕТ", Size = "Small", Icon = "💡" },
	{ Id = "Decor", Name = "DECOR", RU = "ДЕКОР", Size = "Small", Icon = "⛲" },
	{ Id = "Statues", Name = "STATUES", RU = "СТАТУИ", Size = "Large", Icon = "🗿" },
	{ Id = "Zones", Name = "THEMED ZONES", RU = "ТЕМАТИЧЕСКИЕ ЗОНЫ", Size = "Large", Icon = "🏝" },
	-- NIGHT OF THE BURIED MOON rewards (Pumpkin Lucky Blocks / the cauldron); never sold (Features.Decor buy()).
	{ Id = "HauntedSmall", Name = "HALLOWEEN", RU = "ХЭЛЛОУИН", Size = "Small", Icon = "🎃" },
	{ Id = "HauntedLarge", Name = "HALLOWEEN", RU = "ХЭЛЛОУИН", Size = "Large", Icon = "🦴" },
}
D.CategoryById = {}
for i, c in ipairs(D.Categories) do
	c.Order = i
	D.CategoryById[c.Id] = c
end

D.Sizes = {
	Small = { Name = "SMALL", RU = "МАЛЕНЬКОЕ" },
	Large = { Name = "BIG", RU = "БОЛЬШОЕ" },
}

-- Id, Category, Name (EN), RU, Stage (yard stage gate), Cash, Stone, Bones?, Rarity (display tier).
local K = 1000
local M = 1000000
D.Items = {
	-- BUILDINGS (Large)
	{ Id = "doghouse_deluxe", Category = "Buildings", Name = "DOG HOUSE DELUXE", RU = "ЭЛИТНАЯ БУДКА", Stage = 2, Cash = 150 * K, Stone = 150, Rarity = "Uncommon" },
	{ Id = "gazebo", Category = "Buildings", Name = "GAZEBO", RU = "БЕСЕДКА", Stage = 3, Cash = 400 * K, Stone = 300, Rarity = "Rare" },
	{ Id = "treehouse", Category = "Buildings", Name = "TREEHOUSE", RU = "ДОМИК НА ДЕРЕВЕ", Stage = 5, Cash = 2 * M, Stone = 1200, Rarity = "Rare" },
	{ Id = "windmill", Category = "Buildings", Name = "WINDMILL", RU = "ВЕТРЯНАЯ МЕЛЬНИЦА", Stage = 6, Cash = 8 * M, Stone = 2200, Rarity = "Epic" },
	{ Id = "lighthouse", Category = "Buildings", Name = "LIGHTHOUSE", RU = "МАЯК", Stage = 7, Cash = 30 * M, Stone = 4000, Rarity = "Legendary" },
	{ Id = "mini_castle", Category = "Buildings", Name = "MINI CASTLE", RU = "МИНИ-ЗАМОК", Stage = 9, Cash = 150 * M, Stone = 9000, Bones = 200, Rarity = "Mythic" },
	-- PLANTS (Small)
	{ Id = "flower_bed", Category = "Plants", Name = "FLOWER BED", RU = "КЛУМБА", Stage = 1, Cash = 15 * K, Stone = 20, Rarity = "Common" },
	{ Id = "oak_tree", Category = "Plants", Name = "OAK TREE", RU = "ДУБ", Stage = 1, Cash = 30 * K, Stone = 35, Rarity = "Common" },
	{ Id = "hedge_arch", Category = "Plants", Name = "HEDGE ARCH", RU = "АРКА ИЗ ЖИВОЙ ИЗГОРОДИ", Stage = 2, Cash = 60 * K, Stone = 60, Rarity = "Uncommon" },
	{ Id = "palm_tree", Category = "Plants", Name = "PALM TREE", RU = "ПАЛЬМА", Stage = 3, Cash = 120 * K, Stone = 120, Rarity = "Rare" },
	{ Id = "cherry_blossom", Category = "Plants", Name = "CHERRY BLOSSOM", RU = "ЦВЕТУЩАЯ САКУРА", Stage = 5, Cash = 450 * K, Stone = 400, Rarity = "Epic" },
	{ Id = "giant_mushroom", Category = "Plants", Name = "GIANT MUSHROOM", RU = "ГИГАНТСКИЙ ГРИБ", Stage = 6, Cash = 1200 * K, Stone = 700, Rarity = "Legendary" },
	-- LIGHTING (Small)
	{ Id = "lantern_post", Category = "Lighting", Name = "LANTERN POST", RU = "ФОНАРНЫЙ СТОЛБ", Stage = 1, Cash = 20 * K, Stone = 25, Rarity = "Common" },
	{ Id = "brazier", Category = "Lighting", Name = "BRAZIER", RU = "ЖАРОВНЯ", Stage = 2, Cash = 45 * K, Stone = 50, Rarity = "Uncommon" },
	{ Id = "string_lights", Category = "Lighting", Name = "STRING LIGHTS ARCH", RU = "АРКА С ГИРЛЯНДОЙ", Stage = 3, Cash = 100 * K, Stone = 100, Rarity = "Rare" },
	{ Id = "neon_paw_sign", Category = "Lighting", Name = "NEON PAW SIGN", RU = "НЕОНОВАЯ ЛАПКА", Stage = 4, Cash = 250 * K, Stone = 200, Rarity = "Rare" },
	{ Id = "crystal_lamp", Category = "Lighting", Name = "CRYSTAL LAMP", RU = "КРИСТАЛЬНАЯ ЛАМПА", Stage = 6, Cash = 900 * K, Stone = 650, Rarity = "Epic" },
	{ Id = "spotlight_tower", Category = "Lighting", Name = "SPOTLIGHT TOWER", RU = "ПРОЖЕКТОРНАЯ ВЫШКА", Stage = 7, Cash = 2 * M, Stone = 1000, Rarity = "Legendary" },
	-- DECOR (Small)
	{ Id = "signpost", Category = "Decor", Name = "SIGNPOST", RU = "УКАЗАТЕЛЬ", Stage = 1, Cash = 15 * K, Stone = 20, Rarity = "Common" },
	{ Id = "bone_pile", Category = "Decor", Name = "BONE PILE", RU = "ГОРА КОСТЕЙ", Stage = 1, Cash = 25 * K, Stone = 30, Rarity = "Common" },
	{ Id = "bench_set", Category = "Decor", Name = "BENCH SET", RU = "СКАМЕЙКА", Stage = 2, Cash = 50 * K, Stone = 50, Rarity = "Uncommon" },
	{ Id = "picnic_set", Category = "Decor", Name = "PICNIC SET", RU = "НАБОР ДЛЯ ПИКНИКА", Stage = 3, Cash = 110 * K, Stone = 110, Rarity = "Uncommon" },
	{ Id = "treasure_chest", Category = "Decor", Name = "TREASURE CHEST", RU = "СУНДУК С СОКРОВИЩАМИ", Stage = 4, Cash = 300 * K, Stone = 220, Rarity = "Rare" },
	{ Id = "fountain", Category = "Decor", Name = "FOUNTAIN", RU = "ФОНТАН", Stage = 5, Cash = 700 * K, Stone = 450, Rarity = "Epic" },
	-- STATUES (Large)
	{ Id = "bone_obelisk", Category = "Statues", Name = "BONE OBELISK", RU = "КОСТЯНОЙ ОБЕЛИСК", Stage = 2, Cash = 200 * K, Stone = 180, Rarity = "Uncommon" },
	{ Id = "trophy_column", Category = "Statues", Name = "TROPHY COLUMN", RU = "КОЛОННА С КУБКОМ", Stage = 4, Cash = 800 * K, Stone = 500, Rarity = "Rare" },
	{ Id = "knight_dog", Category = "Statues", Name = "KNIGHT DOG", RU = "ПЁС-РЫЦАРЬ", Stage = 5, Cash = 2500 * K, Stone = 1300, Rarity = "Epic" },
	{ Id = "pharaoh_dog", Category = "Statues", Name = "PHARAOH DOG", RU = "ПЁС-ФАРАОН", Stage = 6, Cash = 10 * M, Stone = 2500, Rarity = "Epic" },
	{ Id = "golden_dog_statue", Category = "Statues", Name = "GOLDEN DOG STATUE", RU = "ЗОЛОТАЯ СТАТУЯ ПСА", Stage = 8, Cash = 60 * M, Stone = 6500, Rarity = "Legendary" },
	{ Id = "cosmic_dog", Category = "Statues", Name = "COSMIC DOG", RU = "КОСМИЧЕСКИЙ ПЁС", Stage = 9, Cash = 120 * M, Stone = 8000, Bones = 150, Rarity = "Mythic" },
	-- THEMED ZONES (Large)
	{ Id = "zen_garden", Category = "Zones", Name = "ZEN GARDEN", RU = "ДЗЕН-САД", Stage = 3, Cash = 300 * K, Stone = 280, Rarity = "Uncommon" },
	{ Id = "candy_corner", Category = "Zones", Name = "CANDY CORNER", RU = "КОНФЕТНЫЙ УГОЛОК", Stage = 4, Cash = 900 * K, Stone = 550, Rarity = "Rare" },
	{ Id = "pirate_cove", Category = "Zones", Name = "PIRATE COVE", RU = "ПИРАТСКАЯ БУХТА", Stage = 5, Cash = 3 * M, Stone = 1500, Rarity = "Rare" },
	{ Id = "ice_corner", Category = "Zones", Name = "ICE CORNER", RU = "ЛЕДЯНОЙ УГОЛОК", Stage = 6, Cash = 12 * M, Stone = 2700, Rarity = "Epic" },
	{ Id = "haunted_corner", Category = "Zones", Name = "HAUNTED CORNER", RU = "ЖУТКИЙ УГОЛОК", Stage = 7, Cash = 40 * M, Stone = 4500, Rarity = "Legendary" },
	{ Id = "space_pad", Category = "Zones", Name = "SPACE PAD", RU = "КОСМОДРОМ", Stage = 9, Cash = 100 * M, Stone = 8500, Bones = 150, Rarity = "Mythic" },
	-- HALLOWEEN (event rewards: Reward = event id; Stage 1 so PLACE is never stage-locked; Cash/Stone 0 = not for sale)
	{ Id = "hw_jack_o_lantern", Category = "HauntedSmall", Name = "JACK-O'-LANTERN", RU = "ТЫКВЕННЫЙ ФОНАРЬ", Stage = 1, Cash = 0, Stone = 0, Rarity = "Rare", Reward = "BuriedMoon2026" },
	{ Id = "hw_grave_stone", Category = "HauntedSmall", Name = "GRAVE STONE", RU = "НАДГРОБИЕ", Stage = 1, Cash = 0, Stone = 0, Rarity = "Rare", Reward = "BuriedMoon2026" },
	{ Id = "hw_candle_cluster", Category = "HauntedSmall", Name = "CANDLE CLUSTER", RU = "СВЕЧИ", Stage = 1, Cash = 0, Stone = 0, Rarity = "Epic", Reward = "BuriedMoon2026" },
	{ Id = "hw_bone_arch", Category = "HauntedLarge", Name = "BONE ARCH", RU = "КОСТЯНАЯ АРКА", Stage = 1, Cash = 0, Stone = 0, Rarity = "Legendary", Reward = "BuriedMoon2026" },
}
D.ById = {}
D.Order = {}
for i, item in ipairs(D.Items) do
	local category = D.CategoryById[item.Category]
	assert(category, "Unknown decor category " .. tostring(item.Category))
	item.Size = category.Size
	item.Order = i
	D.ById[item.Id] = item
	table.insert(D.Order, item.Id)
end

-- Decor slots of every yard. Side: +1 = the kennel 2/4 side (x' > 0), -1 = the kennel 1/3/5 side.
D.Slots = {
	{ Id = "L1", Size = "Large", X = 14.75, Z = 12.4 },
	{ Id = "L2", Size = "Large", X = 26.25, Z = 12.4 },
	{ Id = "L3", Size = "Large", X = -14.75, Z = 12.4 },
	{ Id = "L4", Size = "Large", X = -26.25, Z = 12.4 },
	{ Id = "P1", Size = "Small", X = 31, Z = 38 },
	{ Id = "P2", Size = "Small", X = 31, Z = 0 },
	{ Id = "P3", Size = "Small", X = 31, Z = -22 },
	{ Id = "P4", Size = "Small", X = -31, Z = 38 },
	{ Id = "P5", Size = "Small", X = -31, Z = 0 },
	{ Id = "P6", Size = "Small", X = -31, Z = -22 },
	{ Id = "S1", Size = "Small", X = 5.9, Z = 48 },
	{ Id = "S2", Size = "Small", X = 5.9, Z = 32 },
	{ Id = "S3", Size = "Small", X = 5.9, Z = 12 },
	{ Id = "S4", Size = "Small", X = 5.9, Z = -8 },
	{ Id = "S5", Size = "Small", X = 5.9, Z = -28 },
	{ Id = "S6", Size = "Small", X = -5.9, Z = 48 },
	{ Id = "S7", Size = "Small", X = -5.9, Z = 32 },
	{ Id = "S8", Size = "Small", X = -5.9, Z = 12 },
	{ Id = "S9", Size = "Small", X = -5.9, Z = -8 },
	{ Id = "S10", Size = "Small", X = -5.9, Z = -28 },
}
D.SlotById = {}
D.SlotCount = { Small = 0, Large = 0 }
for i, slot in ipairs(D.Slots) do
	slot.Order = i
	slot.Number = 0
	D.SlotById[slot.Id] = slot
	D.SlotCount[slot.Size] += 1
	slot.Number = D.SlotCount[slot.Size]
end
-- Frame height of the slot origin: just above the YardFoundation top (frame y -0.2).
D.GroundY = -0.15

function D.Get(id: any): any
	return type(id) == "string" and D.ById[id] or nil
end
function D.Slot(id: any): any
	return type(id) == "string" and D.SlotById[id] or nil
end
function D.Fits(id: any, slotId: any): boolean
	local item, slot = D.Get(id), D.Slot(slotId)
	return item ~= nil and slot ~= nil and item.Size == slot.Size
end
-- Coins, Stone, Bones of one copy (server prices; the client shows the same table).
function D.Price(id: any): (number, number, number)
	local item = D.Get(id)
	if not item then
		return 0, 0, 0
	end
	return item.Cash, item.Stone, item.Bones or 0
end
-- Copies of one decoration a player can own: one per slot of its size.
function D.MaxOwned(id: any): number
	local item = D.Get(id)
	return item and D.SlotCount[item.Size] or 0
end
function D.Stage(p: any): number
	local ok, level = pcall(PlotCatalog.Level, p)
	return ok and tonumber(level) or 1
end
-- ok, the yard stage it needs.
function D.Unlocked(p: any, id: any): (boolean, number)
	local item = D.Get(id)
	if not item then
		return false, 99
	end
	return D.Stage(p) >= item.Stage, item.Stage
end

-- World CFrame of a slot. frame = PlotAppearance.Frame(yard), sx = mirror sign of the yard.
-- The decoration's front (-Z) faces the central walkway.
function D.SlotCFrame(frame: CFrame, sx: number, slot: any): CFrame
	local x = slot.X * (sx or 1)
	local yaw = x > 0 and math.pi / 2 or -math.pi / 2
	return frame * CFrame.new(x, D.GroundY, slot.Z) * CFrame.Angles(0, yaw, 0)
end

-- Display helpers (the window is localized with these pairs).
function D.SlotName(slot: any, ru: boolean?): string
	if not slot then
		return ""
	end
	if slot.Size == "Large" then
		return (ru and "БОЛЬШОЕ МЕСТО " or "BIG SPOT ") .. slot.Number
	end
	return (ru and "МАЛОЕ МЕСТО " or "SMALL SPOT ") .. slot.Number
end
-- Event reward decorations (Item.Reward): never bought, only granted.
function D.IsReward(id: any): boolean
	local item = D.Get(id)
	return item ~= nil and item.Reward ~= nil
end
function D.ItemName(item: any, ru: boolean?): string
	if not item then
		return ""
	end
	return ru and item.RU or item.Name
end

return D
