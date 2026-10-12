-- Equipment catalogue shared by the server (ServerScriptService.Economy.Features.Equipment), the
-- bonus sources (BonusSources.Artifacts / Accessories) and the client (Modules.Equipment.*).
-- Pure data plus small pure helpers: no services, safe to require from Lune tests.
--
--   DOG ARTIFACTS   affect ONE dog (the dog they are equipped on); slots per dog by its rank.
--   PLAYER ACCESSORIES affect YOU: every dog and your earnings (one per slot Hat/Face/Back/Aura).
--
-- Every piece has a rolled quality Roll (0..1): its value is Min + (Max - Min) * Roll.
-- Values are Bonuses fractions (.10 = +10%), see ReplicatedStorage.DogEconomy.Bonuses.
-- Look: the 3D look built from parts by EquipmentVisuals (no external assets):
--   {Base = {r,g,b}, Trim = {r,g,b}, Parts = {{shape, size, position, rotation, colour, material, transparency}}}
--   shape 'B' block | 'S' ball | 'C' cylinder (axis X) | 'W' wedge; colour 'base' | 'trim' | 'dark' |
--   'light' | 'glow' (rarity accent: colour, material and light follow the rarity) | 'gold' |
--   'white' | 'black' | {r,g,b}. Units are studs; accessories are authored for a 1.2-stud head.
local Pricing = require(script.Parent.BoostPricing)

local E = {}
E.Version = 1

E.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
E.RarityIndex = {}
for i, r in ipairs(E.Rarities) do
	E.RarityIndex[r] = i
end
-- Same colours as Kit.Theme.Rarity (tests/equipment.luau checks they stay in sync).
E.RarityColors = {
	Common = { 170, 190, 205 },
	Uncommon = { 125, 219, 48 },
	Rare = { 38, 164, 243 },
	Epic = { 161, 103, 242 },
	Legendary = { 249, 180, 35 },
	Mythic = { 247, 73, 112 },
}
E.RarityRu = { Common = "Обычный", Uncommon = "Необычный", Rare = "Редкий", Epic = "Эпический", Legendary = "Легендарный", Mythic = "Мифический" }

-- Stats. Scope: "dog" = only the dog the artifact is on, "you" = all your dogs / your earnings.
E.Stats = {
	DigSpeed = { Name = "DIG SPEED", Ru = "СКОРОСТЬ КОПАНИЯ", Short = "SPEED", ShortRu = "СКОРОСТЬ", Icon = "Dig", Color = { 38, 164, 243 } },
	Luck = { Name = "LUCK", Ru = "УДАЧА", Short = "LUCK", ShortRu = "УДАЧА", Icon = "Luck", Color = { 125, 219, 48 } },
	Income = { Name = "INCOME", Ru = "ДОХОД", Short = "INCOME", ShortRu = "ДОХОД", Icon = "Coins", Color = { 249, 180, 35 } },
	MoneyMult = { Name = "MONEY MULTIPLIER", Ru = "МНОЖИТЕЛЬ ДЕНЕГ", Short = "MONEY", ShortRu = "ДЕНЬГИ", Icon = "Coins", Color = { 236, 150, 20 } },
	RareFind = { Name = "RARE FINDS", Ru = "РЕДКИЕ НАХОДКИ", Short = "RARE", ShortRu = "РЕДКОЕ", Icon = "Star", Color = { 161, 103, 242 } },
	ItemMutation = { Name = "ITEM MUTATIONS", Ru = "МУТАЦИИ НАХОДОК", Short = "MUTATION", ShortRu = "МУТАЦИЯ", Icon = "Star", Color = { 230, 115, 245 } },
	DogPower = { Name = "DOG POWER", Ru = "СИЛА СОБАКИ", Short = "POWER", ShortRu = "СИЛА", Icon = "Dig", Color = { 247, 73, 112 } },
	XP = { Name = "XP", Ru = "ОПЫТ", Short = "XP", ShortRu = "ОПЫТ", Icon = "Star", Color = { 34, 184, 242 } },
	Offline = { Name = "OFFLINE EARNINGS", Ru = "ОФЛАЙН-ДОХОД", Short = "OFFLINE", ShortRu = "ОФЛАЙН", Icon = "Coins", Color = { 83, 112, 150 } },
}
-- What a stat does, for tooltips: dog artifacts (this dog) and accessories (you).
E.StatHelp = {
	DigSpeed = { Dog = { "This dog digs faster.", "Эта собака копает быстрее." }, You = { "All your dogs dig faster.", "Все твои собаки копают быстрее." } },
	Luck = { Dog = { "Rare loot and finds come more often for this dog.", "Этой собаке чаще попадаются редкие вещи и находки." }, You = { "Rare loot and finds come more often for all your dogs.", "Всем твоим собакам чаще попадаются редкие вещи и находки." } },
	Income = { Dog = { "Everything this dog digs is worth more.", "Всё, что выкапывает эта собака, стоит дороже." }, You = { "Everything your dogs dig is worth more.", "Всё, что выкапывают твои собаки, стоит дороже." } },
	MoneyMult = { Dog = { "Multiplies the money this dog earns.", "Умножает деньги этой собаки." }, You = { "Multiplies all money your dogs earn.", "Умножает все деньги твоих собак." } },
	RareFind = { Dog = { "This dog finds rare items more often.", "Эта собака чаще находит редкие предметы." }, You = { "Your dogs find rare items more often.", "Твои собаки чаще находят редкие предметы." } },
	ItemMutation = { Dog = { "Items this dog finds mutate more often.", "Находки этой собаки чаще мутируют." }, You = { "Items your dogs find mutate more often.", "Находки твоих собак чаще мутируют." } },
	DogPower = { Dog = { "This dog's whole work is stronger: more value per dig.", "Вся работа этой собаки сильнее: больше ценности за раскопку." }, You = { "Your dogs are stronger.", "Твои собаки сильнее." } },
	XP = { Dog = { "More XP.", "Больше опыта." }, You = { "You gain more XP from digging.", "Ты получаешь больше опыта за раскопки." } },
	Offline = { Dog = { "More offline earnings.", "Больше офлайн-дохода." }, You = { "Your dogs earn more while you are away.", "Собаки зарабатывают больше, пока тебя нет." } },
}
E.ArtifactStats = { "DigSpeed", "Luck", "Income", "RareFind", "ItemMutation", "DogPower" }
E.AccessoryStats = { "Luck", "Income", "MoneyMult", "RareFind", "ItemMutation", "XP", "Offline", "DigSpeed" }

E.Slots = { "Hat", "Face", "Back", "Aura" }
E.SlotInfo = {
	Hat = { Name = "HAT", Ru = "ШАПКА" },
	Face = { Name = "FACE", Ru = "ЛИЦО" },
	Back = { Name = "BACK", Ru = "СПИНА" },
	Aura = { Name = "AURA", Ru = "АУРА" },
}

-- Artifact slots per dog: Common 1, Rare 2, Epic 2, Legendary 3, Mythic 3, Secret 4 (by dog rank 1..6).
E.DogSlotsByRank = { 1, 2, 2, 3, 3, 4 }
E.DogRarities = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
E.MaxDogSlots = 4
-- Inventory limits (salvage pieces to make room). Robux credits are never lost to a full bag:
-- they wait until there is room to open them.
E.Capacity = { Artifact = 120, Accessory = 80 }
-- Bones for salvaging one piece.
E.Salvage = { Common = 2, Uncommon = 4, Rare = 9, Epic = 20, Legendary = 45, Mythic = 110 }
-- Per-dog ceiling of each artifact stat (several artifacts with the same stat on one dog).
E.ArtifactCaps = { DigSpeed = 1.0, Luck = 1.2, Income = 1.0, RareFind = 1.25, ItemMutation = 1.5, DogPower = 0.8 }
-- Most pieces one SalvageEquipment request may name.
E.MaxSalvageBatch = 30

-- Roll ranges. Artifacts are strong on one dog; accessories are smaller but help every dog.
local ARTIFACT_RANGE = {
	Common = { 0.03, 0.05 },
	Uncommon = { 0.05, 0.08 },
	Rare = { 0.08, 0.12 },
	Epic = { 0.12, 0.17 },
	Legendary = { 0.17, 0.24 },
	Mythic = { 0.24, 0.34 },
}
local ARTIFACT_SCALE = { DigSpeed = 1.0, Luck = 1.2, Income = 1.0, RareFind = 1.25, ItemMutation = 1.5, DogPower = 0.8 }
local ACCESSORY_RANGE = {
	Common = { 0.01, 0.02 },
	Uncommon = { 0.02, 0.035 },
	Rare = { 0.035, 0.055 },
	Epic = { 0.055, 0.08 },
	Legendary = { 0.08, 0.11 },
	Mythic = { 0.11, 0.15 },
}
local ACCESSORY_SCALE = { Luck = 1.2, Income = 1.0, MoneyMult = 0.6, RareFind = 1.25, ItemMutation = 1.5, XP = 2.5, Offline = 2.0, DigSpeed = 1.0 }

local function round4(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

-- Colours used by looks.
local BROWN, WOOD, IRON, BRASS, GOLD = { 120, 80, 50 }, { 150, 105, 64 }, { 120, 128, 140 }, { 196, 156, 72 }, { 249, 196, 64 }
local RED, GREEN, BLUE, PURPLE, WHITE = { 214, 64, 70 }, { 84, 186, 82 }, { 60, 140, 230 }, { 140, 90, 230 }, { 245, 245, 250 }
local DARK, VOID, PAPER = { 40, 44, 60 }, { 46, 22, 86 }, { 236, 226, 196 }

-- Dog artifacts: 4 per rarity, every stat in four rarities.
E.Artifacts = {
	-- Common
	{ Id = "RustyTrowel", Name = "Rusty Trowel", Ru = "Ржавый совок", Rarity = "Common", Stat = "DigSpeed",
		Look = { Base = { 176, 96, 56 }, Trim = WOOD, Parts = {
			{ "C", { 1.1, 0.26, 0.26 }, { 0, -0.62, 0 }, { 0, 0, 90 }, "trim", "Wood" },
			{ "B", { 0.72, 0.86, 0.1 }, { 0, 0.34, 0 }, nil, "base", "CorrodedMetal" },
			{ "W", { 0.1, 0.36, 0.72 }, { 0, 0.95, 0 }, { 0, 90, 0 }, "base", "CorrodedMetal" },
			{ "C", { 0.14, 0.34, 0.34 }, { 0, -0.08, 0 }, { 0, 0, 90 }, "glow" },
		} } },
	{ Id = "LuckyPebble", Name = "Lucky Pebble", Ru = "Счастливый камешек", Rarity = "Common", Stat = "Luck",
		Look = { Base = { 150, 158, 170 }, Trim = GREEN, Parts = {
			{ "S", { 1.3, 0.95, 1.1 }, { 0, 0, 0 }, nil, "base", "Slate" },
			{ "S", { 0.26, 0.26, 0.08 }, { -0.09, 0.12, -0.53 }, nil, "glow" },
			{ "S", { 0.26, 0.26, 0.08 }, { 0.09, 0.12, -0.53 }, nil, "glow" },
			{ "S", { 0.26, 0.26, 0.08 }, { 0, -0.05, -0.53 }, nil, "glow" },
		} } },
	{ Id = "CopperCoin", Name = "Copper Coin", Ru = "Медная монета", Rarity = "Common", Stat = "Income",
		Look = { Base = { 205, 120, 70 }, Trim = { 160, 88, 50 }, Parts = {
			{ "C", { 0.16, 1.4, 1.4 }, { 0, 0, 0 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.2, 1.05, 1.05 }, { 0, 0, 0 }, { 0, 90, 0 }, "trim", "Metal" },
			{ "B", { 0.18, 0.55, 0.22 }, { 0, 0, -0.08 }, nil, "glow" },
		} } },
	{ Id = "ChewToy", Name = "Chew Toy", Ru = "Жевательная игрушка", Rarity = "Common", Stat = "DogPower",
		Look = { Base = { 236, 92, 120 }, Trim = WHITE, Parts = {
			{ "C", { 1.3, 0.34, 0.34 }, { 0, 0, 0 }, nil, "base" },
			{ "S", { 0.46, 0.46, 0.46 }, { -0.7, 0.16, 0 }, nil, "base" },
			{ "S", { 0.46, 0.46, 0.46 }, { -0.7, -0.16, 0 }, nil, "base" },
			{ "S", { 0.46, 0.46, 0.46 }, { 0.7, 0.16, 0 }, nil, "base" },
			{ "S", { 0.46, 0.46, 0.46 }, { 0.7, -0.16, 0 }, nil, "base" },
			{ "C", { 0.3, 0.38, 0.38 }, { 0, 0, 0 }, nil, "glow" },
		} } },
	-- Uncommon
	{ Id = "SpringClaws", Name = "Spring Claws", Ru = "Пружинные когти", Rarity = "Uncommon", Stat = "DigSpeed",
		Look = { Base = { 200, 210, 222 }, Trim = BROWN, Parts = {
			{ "B", { 1.3, 0.34, 0.5 }, { 0, -0.45, 0 }, nil, "trim", "Fabric" },
			{ "W", { 0.22, 0.95, 0.4 }, { -0.42, 0.18, 0 }, nil, "base", "Metal" },
			{ "W", { 0.22, 1.1, 0.4 }, { 0, 0.26, 0 }, nil, "base", "Metal" },
			{ "W", { 0.22, 0.95, 0.4 }, { 0.42, 0.18, 0 }, nil, "base", "Metal" },
			{ "C", { 1.36, 0.16, 0.16 }, { 0, -0.27, -0.26 }, nil, "glow" },
		} } },
	{ Id = "FourLeafTag", Name = "Four-Leaf Tag", Ru = "Жетон-клевер", Rarity = "Uncommon", Stat = "Luck",
		Look = { Base = GREEN, Trim = BRASS, Parts = {
			{ "S", { 0.62, 0.62, 0.14 }, { -0.28, 0.28, 0 }, nil, "base" },
			{ "S", { 0.62, 0.62, 0.14 }, { 0.28, 0.28, 0 }, nil, "base" },
			{ "S", { 0.62, 0.62, 0.14 }, { -0.28, -0.28, 0 }, nil, "base" },
			{ "S", { 0.62, 0.62, 0.14 }, { 0.28, -0.28, 0 }, nil, "base" },
			{ "C", { 0.1, 0.34, 0.34 }, { 0, 0, -0.06 }, { 0, 90, 0 }, "glow" },
			{ "C", { 0.08, 0.36, 0.36 }, { 0, 0.78, 0 }, { 0, 90, 0 }, "trim", "Metal" },
		} } },
	{ Id = "OldMapScrap", Name = "Old Map Scrap", Ru = "Обрывок карты", Rarity = "Uncommon", Stat = "RareFind",
		Look = { Base = PAPER, Trim = { 170, 120, 70 }, Parts = {
			{ "B", { 1.5, 1.05, 0.06 }, { 0, 0, 0 }, { 0, 0, -6 }, "base", "Fabric" },
			{ "C", { 1.12, 0.18, 0.18 }, { -0.8, 0.07, 0 }, { 0, 0, 84 }, "trim", "Fabric" },
			{ "B", { 0.42, 0.08, 0.04 }, { 0.25, -0.12, -0.05 }, { 0, 0, 45 }, "glow" },
			{ "B", { 0.42, 0.08, 0.04 }, { 0.25, -0.12, -0.05 }, { 0, 0, -45 }, "glow" },
			{ "B", { 0.7, 0.04, 0.03 }, { -0.15, 0.22, -0.04 }, { 0, 0, 12 }, "trim" },
		} } },
	{ Id = "GlowMushroom", Name = "Glow Mushroom", Ru = "Светящийся гриб", Rarity = "Uncommon", Stat = "ItemMutation",
		Look = { Base = { 110, 200, 230 }, Trim = PAPER, Parts = {
			{ "C", { 0.8, 0.42, 0.42 }, { 0, -0.45, 0 }, { 0, 0, 90 }, "trim" },
			{ "S", { 1.45, 0.75, 1.45 }, { 0, 0.12, 0 }, nil, "base" },
			{ "S", { 0.26, 0.2, 0.26 }, { -0.35, 0.43, -0.2 }, nil, "glow" },
			{ "S", { 0.22, 0.18, 0.22 }, { 0.32, 0.4, 0.22 }, nil, "glow" },
			{ "S", { 0.2, 0.16, 0.2 }, { 0.05, 0.5, -0.4 }, nil, "glow" },
		} } },
	-- Rare
	{ Id = "GoldBone", Name = "Gold Bone", Ru = "Золотая косточка", Rarity = "Rare", Stat = "Income",
		Look = { Base = GOLD, Trim = { 255, 236, 160 }, Parts = {
			{ "C", { 1.3, 0.34, 0.34 }, { 0, 0, 0 }, nil, "base", "Foil" },
			{ "S", { 0.48, 0.48, 0.48 }, { -0.7, 0.17, 0 }, nil, "base", "Foil" },
			{ "S", { 0.48, 0.48, 0.48 }, { -0.7, -0.17, 0 }, nil, "base", "Foil" },
			{ "S", { 0.48, 0.48, 0.48 }, { 0.7, 0.17, 0 }, nil, "base", "Foil" },
			{ "S", { 0.48, 0.48, 0.48 }, { 0.7, -0.17, 0 }, nil, "base", "Foil" },
			{ "S", { 0.22, 0.22, 0.22 }, { 0, 0, -0.16 }, nil, "glow" },
		} } },
	{ Id = "BrassCompass", Name = "Brass Compass", Ru = "Латунный компас", Rarity = "Rare", Stat = "RareFind",
		Look = { Base = BRASS, Trim = WHITE, Parts = {
			{ "C", { 0.24, 1.35, 1.35 }, { 0, 0, 0 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.26, 1.1, 1.1 }, { 0, 0, -0.02 }, { 0, 90, 0 }, "trim" },
			{ "W", { 0.06, 0.45, 0.12 }, { 0, 0.22, -0.16 }, { 90, 0, 0 }, "glow" },
			{ "W", { 0.06, 0.45, 0.12 }, { 0, -0.22, -0.16 }, { -90, 0, 0 }, "dark" },
			{ "C", { 0.18, 0.24, 0.24 }, { 0, 0.78, 0 }, { 0, 0, 90 }, "base", "Metal" },
		} } },
	{ Id = "IronCollar", Name = "Iron Collar", Ru = "Железный ошейник", Rarity = "Rare", Stat = "DogPower",
		Look = { Base = IRON, Trim = DARK, Parts = {
			{ "C", { 0.36, 1.5, 1.5 }, { 0, 0, 0 }, { 0, 0, 90 }, "base", "DiamondPlate" },
			{ "C", { 0.4, 1.12, 1.12 }, { 0, 0, 0 }, { 0, 0, 90 }, "black" },
			{ "S", { 0.2, 0.2, 0.2 }, { 0.72, 0, 0 }, nil, "glow" },
			{ "S", { 0.2, 0.2, 0.2 }, { -0.72, 0, 0 }, nil, "glow" },
			{ "S", { 0.2, 0.2, 0.2 }, { 0, 0, -0.72 }, nil, "glow" },
			{ "C", { 0.08, 0.42, 0.42 }, { 0, -0.36, -0.78 }, { 0, 90, 0 }, "trim", "Metal" },
		} } },
	{ Id = "RadVial", Name = "Rad Vial", Ru = "Радиоактивная колба", Rarity = "Rare", Stat = "ItemMutation",
		Look = { Base = { 150, 240, 60 }, Trim = DARK, Parts = {
			{ "C", { 1.3, 0.62, 0.62 }, { 0, 0, 0 }, { 0, 0, 90 }, "white", "Glass", 0.55 },
			{ "C", { 0.85, 0.5, 0.5 }, { 0, -0.2, 0 }, { 0, 0, 90 }, "glow" },
			{ "C", { 0.24, 0.68, 0.68 }, { 0, 0.74, 0 }, { 0, 0, 90 }, "trim", "Metal" },
			{ "B", { 0.3, 0.3, 0.04 }, { 0, -0.05, -0.31 }, { 0, 0, 45 }, "black" },
		} } },
	-- Epic
	{ Id = "TurboPaws", Name = "Turbo Paws", Ru = "Турбо-лапы", Rarity = "Epic", Stat = "DigSpeed",
		Look = { Base = { 70, 80, 110 }, Trim = { 255, 140, 40 }, Parts = {
			{ "S", { 0.95, 0.8, 0.5 }, { 0, -0.2, 0 }, nil, "base" },
			{ "S", { 0.34, 0.4, 0.3 }, { -0.42, 0.38, 0 }, nil, "base" },
			{ "S", { 0.34, 0.42, 0.3 }, { -0.14, 0.5, 0 }, nil, "base" },
			{ "S", { 0.34, 0.42, 0.3 }, { 0.14, 0.5, 0 }, nil, "base" },
			{ "S", { 0.34, 0.4, 0.3 }, { 0.42, 0.38, 0 }, nil, "base" },
			{ "W", { 0.2, 0.5, 0.9 }, { -0.25, -0.45, 0.45 }, { 0, 180, 0 }, "glow" },
			{ "W", { 0.2, 0.5, 0.9 }, { 0.25, -0.45, 0.45 }, { 0, 180, 0 }, "glow" },
		} } },
	{ Id = "HorseshoeCharm", Name = "Horseshoe Charm", Ru = "Подкова удачи", Rarity = "Epic", Stat = "Luck",
		Look = { Base = { 200, 205, 215 }, Trim = GOLD, Parts = {
			{ "B", { 0.28, 1.1, 0.24 }, { -0.5, 0.1, 0 }, { 0, 0, -8 }, "base", "Metal" },
			{ "B", { 0.28, 1.1, 0.24 }, { 0.5, 0.1, 0 }, { 0, 0, 8 }, "base", "Metal" },
			{ "C", { 0.24, 1.1, 1.1 }, { 0, -0.4, 0 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.28, 0.6, 0.6 }, { 0, -0.4, 0 }, { 0, 90, 0 }, "black" },
			{ "S", { 0.14, 0.14, 0.14 }, { -0.5, 0.45, -0.14 }, nil, "glow" },
			{ "S", { 0.14, 0.14, 0.14 }, { 0.5, 0.45, -0.14 }, nil, "glow" },
			{ "S", { 0.14, 0.14, 0.14 }, { 0, -0.9, -0.14 }, nil, "glow" },
		} } },
	{ Id = "TreasureCollar", Name = "Treasure Collar", Ru = "Ошейник сокровищ", Rarity = "Epic", Stat = "Income",
		Look = { Base = { 150, 40, 50 }, Trim = GOLD, Parts = {
			{ "C", { 0.34, 1.5, 1.5 }, { 0, 0, 0 }, { 0, 0, 90 }, "base", "Fabric" },
			{ "C", { 0.38, 1.16, 1.16 }, { 0, 0, 0 }, { 0, 0, 90 }, "black" },
			{ "S", { 0.22, 0.22, 0.22 }, { 0.72, 0, 0 }, nil, "glow" },
			{ "S", { 0.22, 0.22, 0.22 }, { -0.72, 0, 0 }, nil, "glow" },
			{ "S", { 0.22, 0.22, 0.22 }, { 0, 0, 0.72 }, nil, "glow" },
			{ "C", { 0.1, 0.55, 0.55 }, { 0, -0.36, -0.8 }, { 0, 90, 0 }, "trim", "Foil" },
		} } },
	{ Id = "PowerBandana", Name = "Power Bandana", Ru = "Бандана силы", Rarity = "Epic", Stat = "DogPower",
		Look = { Base = RED, Trim = WHITE, Parts = {
			{ "W", { 0.08, 0.9, 1.5 }, { 0, -0.1, 0 }, { 0, 90, 180 }, "base", "Fabric" },
			{ "B", { 1.5, 0.22, 0.1 }, { 0, 0.42, 0 }, nil, "base", "Fabric" },
			{ "S", { 0.3, 0.3, 0.3 }, { 0.78, 0.42, 0 }, nil, "base", "Fabric" },
			{ "S", { 0.3, 0.3, 0.06 }, { 0, 0.05, -0.06 }, nil, "glow" },
			{ "S", { 0.12, 0.12, 0.06 }, { -0.3, 0.2, -0.06 }, nil, "trim" },
			{ "S", { 0.12, 0.12, 0.06 }, { 0.3, 0.2, -0.06 }, nil, "trim" },
		} } },
	-- Legendary
	{ Id = "MidasBell", Name = "Midas Bell", Ru = "Колокольчик Мидаса", Rarity = "Legendary", Stat = "Income",
		Look = { Base = GOLD, Trim = { 255, 240, 190 }, Parts = {
			{ "S", { 1.1, 1.2, 1.1 }, { 0, 0.15, 0 }, nil, "base", "Foil" },
			{ "C", { 0.22, 1.36, 1.36 }, { 0, -0.38, 0 }, { 0, 0, 90 }, "base", "Foil" },
			{ "S", { 0.32, 0.32, 0.32 }, { 0, -0.55, 0 }, nil, "glow" },
			{ "C", { 0.1, 0.42, 0.42 }, { 0, 0.82, 0 }, { 0, 90, 0 }, "trim", "Metal" },
			{ "B", { 1.12, 0.1, 0.1 }, { 0, -0.05, -0.5 }, nil, "glow" },
		} } },
	{ Id = "RelicRadar", Name = "Relic Radar", Ru = "Радар реликвий", Rarity = "Legendary", Stat = "RareFind",
		Look = { Base = { 210, 220, 232 }, Trim = DARK, Parts = {
			{ "C", { 0.2, 1.4, 1.4 }, { 0, 0.2, 0 }, { 0, 70, 30 }, "base", "Metal" },
			{ "C", { 0.24, 0.9, 0.9 }, { 0, 0.2, 0 }, { 0, 70, 30 }, "trim" },
			{ "C", { 0.9, 0.12, 0.12 }, { 0.1, 0.5, -0.2 }, { 0, 70, 60 }, "trim", "Metal" },
			{ "S", { 0.24, 0.24, 0.24 }, { 0.32, 0.86, -0.3 }, nil, "glow" },
			{ "B", { 0.8, 0.3, 0.6 }, { 0, -0.6, 0 }, nil, "trim", "Metal" },
		} } },
	{ Id = "PrismShard", Name = "Prism Shard", Ru = "Осколок призмы", Rarity = "Legendary", Stat = "ItemMutation",
		Look = { Base = { 190, 230, 255 }, Trim = { 255, 160, 230 }, Parts = {
			{ "B", { 0.5, 1.5, 0.5 }, { 0, 0.1, 0 }, { 0, 45, 8 }, "base", "Glass", 0.25 },
			{ "B", { 0.36, 1.0, 0.36 }, { -0.42, -0.15, 0.1 }, { 0, 30, 24 }, "trim", "Glass", 0.25 },
			{ "B", { 0.32, 0.85, 0.32 }, { 0.4, -0.22, -0.05 }, { 0, 60, -22 }, "base", "Glass", 0.25 },
			{ "B", { 0.24, 0.9, 0.24 }, { 0, 0.1, 0 }, { 0, 45, 8 }, "glow" },
			{ "C", { 0.2, 1.3, 1.3 }, { 0, -0.62, 0 }, { 0, 0, 90 }, "dark", "Slate" },
		} } },
	{ Id = "TitanHarness", Name = "Titan Harness", Ru = "Шлейка титана", Rarity = "Legendary", Stat = "DogPower",
		Look = { Base = { 60, 66, 84 }, Trim = { 220, 160, 60 }, Parts = {
			{ "B", { 1.5, 0.3, 0.14 }, { 0, 0, 0 }, { 0, 0, 35 }, "base", "Fabric" },
			{ "B", { 1.5, 0.3, 0.14 }, { 0, 0, 0 }, { 0, 0, -35 }, "base", "Fabric" },
			{ "B", { 0.6, 0.6, 0.2 }, { 0, 0, -0.04 }, { 0, 0, 45 }, "trim", "Metal" },
			{ "B", { 0.3, 0.3, 0.1 }, { 0, 0, -0.16 }, { 0, 0, 45 }, "glow" },
			{ "B", { 0.5, 0.36, 0.16 }, { -0.62, 0.45, 0 }, { 0, 0, 35 }, "trim", "Metal" },
			{ "B", { 0.5, 0.36, 0.16 }, { 0.62, 0.45, 0 }, { 0, 0, -35 }, "trim", "Metal" },
		} } },
	-- Mythic
	{ Id = "ChronoGear", Name = "Chrono Gear", Ru = "Хроношестерня", Rarity = "Mythic", Stat = "DigSpeed",
		Look = { Base = { 220, 200, 120 }, Trim = DARK, Parts = {
			{ "C", { 0.22, 1.3, 1.3 }, { 0, 0, 0 }, { 0, 90, 0 }, "base", "Metal" },
			{ "B", { 0.3, 1.72, 0.2 }, { 0, 0, 0 }, nil, "base", "Metal" },
			{ "B", { 1.72, 0.3, 0.2 }, { 0, 0, 0 }, nil, "base", "Metal" },
			{ "B", { 0.3, 1.72, 0.2 }, { 0, 0, 0 }, { 0, 0, 45 }, "base", "Metal" },
			{ "B", { 0.3, 1.72, 0.2 }, { 0, 0, 0 }, { 0, 0, -45 }, "base", "Metal" },
			{ "C", { 0.26, 0.7, 0.7 }, { 0, 0, -0.02 }, { 0, 90, 0 }, "glow" },
			{ "B", { 0.06, 0.42, 0.06 }, { 0.08, 0.16, -0.16 }, { 0, 0, -30 }, "black" },
		} } },
	{ Id = "FortuneEye", Name = "Fortune Eye", Ru = "Око фортуны", Rarity = "Mythic", Stat = "Luck",
		Look = { Base = WHITE, Trim = GOLD, Parts = {
			{ "S", { 1.25, 1.25, 1.25 }, { 0, 0, 0 }, nil, "base" },
			{ "C", { 0.1, 0.72, 0.72 }, { 0, 0, -0.6 }, { 0, 90, 0 }, "glow" },
			{ "C", { 0.12, 0.3, 0.3 }, { 0, 0, -0.64 }, { 0, 90, 0 }, "black" },
			{ "C", { 0.16, 1.5, 1.5 }, { 0, 0, 0 }, { 0, 90, 0 }, "trim", "Foil", 0.1 },
		} } },
	{ Id = "OracleOrb", Name = "Oracle Orb", Ru = "Сфера оракула", Rarity = "Mythic", Stat = "RareFind",
		Look = { Base = { 170, 220, 255 }, Trim = BRASS, Parts = {
			{ "S", { 1.2, 1.2, 1.2 }, { 0, 0.25, 0 }, nil, "base", "Glass", 0.35 },
			{ "S", { 0.6, 0.6, 0.6 }, { 0, 0.25, 0 }, nil, "glow" },
			{ "C", { 0.3, 0.9, 0.9 }, { 0, -0.5, 0 }, { 0, 0, 90 }, "trim", "Metal" },
			{ "W", { 0.12, 0.5, 0.3 }, { -0.42, -0.2, 0 }, { 0, 90, 20 }, "trim", "Metal" },
			{ "W", { 0.12, 0.5, 0.3 }, { 0.42, -0.2, 0 }, { 0, -90, -20 }, "trim", "Metal" },
		} } },
	{ Id = "VoidCrystal", Name = "Void Crystal", Ru = "Кристалл пустоты", Rarity = "Mythic", Stat = "ItemMutation",
		Look = { Base = VOID, Trim = { 200, 120, 255 }, Parts = {
			{ "B", { 0.62, 1.6, 0.62 }, { 0, 0.05, 0 }, { 0, 45, 0 }, "base", "Glass", 0.15 },
			{ "B", { 0.3, 1.1, 0.3 }, { 0, 0.05, 0 }, { 0, 45, 0 }, "glow" },
			{ "C", { 0.08, 1.7, 1.7 }, { 0, 0.05, 0 }, { 0, 0, 70 }, "trim", "Neon", 0.2 },
			{ "B", { 0.3, 0.7, 0.3 }, { -0.45, -0.4, 0.1 }, { 0, 30, 25 }, "base", "Glass", 0.15 },
		} } },
}

-- Player accessories: 4 per rarity across the Hat / Face / Back / Aura slots.
-- Hat: y = 0 is the top of the head. Face: z = 0 is the front of the head at eye level (front = -Z).
-- Back: z = 0 is the back of the torso (out = +Z). Aura: y = 0 is the ground under the player.
E.Accessories = {
	-- Common
	{ Id = "PaperHat", Name = "Paper Hat", Ru = "Бумажная шляпа", Rarity = "Common", Slot = "Hat", Stat = "XP",
		Look = { Base = PAPER, Trim = BLUE, Parts = {
			{ "W", { 1.3, 0.62, 0.42 }, { 0, 0.3, -0.21 }, nil, "base", "Fabric" },
			{ "W", { 1.3, 0.62, 0.42 }, { 0, 0.3, 0.21 }, { 0, 180, 0 }, "base", "Fabric" },
			{ "B", { 1.36, 0.14, 0.9 }, { 0, 0.02, 0 }, nil, "glow" },
		} } },
	{ Id = "RoundSpecs", Name = "Round Specs", Ru = "Круглые очки", Rarity = "Common", Slot = "Face", Stat = "RareFind",
		Look = { Base = DARK, Trim = { 200, 230, 255 }, Parts = {
			{ "C", { 0.06, 0.44, 0.44 }, { -0.26, 0, -0.04 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.06, 0.44, 0.44 }, { 0.26, 0, -0.04 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.07, 0.36, 0.36 }, { -0.26, 0, -0.05 }, { 0, 90, 0 }, "trim", "Glass", 0.4 },
			{ "C", { 0.07, 0.36, 0.36 }, { 0.26, 0, -0.05 }, { 0, 90, 0 }, "trim", "Glass", 0.4 },
			{ "B", { 0.14, 0.05, 0.05 }, { 0, 0.04, -0.05 }, nil, "glow" },
		} } },
	{ Id = "CanvasSatchel", Name = "Canvas Satchel", Ru = "Холщовая сумка", Rarity = "Common", Slot = "Back", Stat = "Offline",
		Look = { Base = { 168, 150, 110 }, Trim = BROWN, Parts = {
			{ "B", { 1.2, 1.0, 0.5 }, { 0, -0.1, 0.27 }, nil, "base", "Fabric" },
			{ "B", { 1.24, 0.45, 0.54 }, { 0, 0.25, 0.29 }, nil, "trim", "Fabric" },
			{ "B", { 0.2, 0.2, 0.06 }, { 0, 0.08, 0.57 }, nil, "glow" },
		} } },
	{ Id = "DustAura", Name = "Dust Aura", Ru = "Пыльная аура", Rarity = "Common", Slot = "Aura", Stat = "DigSpeed",
		Look = { Base = { 200, 180, 140 }, Trim = { 160, 140, 110 }, Parts = {
			{ "C", { 0.08, 4.4, 4.4 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "SmoothPlastic", 0.72 },
			{ "C", { 0.1, 3.2, 3.2 }, { 0, 0.12, 0 }, { 0, 0, 90 }, "glow", nil, 0.6 },
		} } },
	-- Uncommon
	{ Id = "MinerHelmet", Name = "Miner Helmet", Ru = "Шахтёрская каска", Rarity = "Uncommon", Slot = "Hat", Stat = "DigSpeed",
		Look = { Base = { 245, 196, 40 }, Trim = DARK, Parts = {
			{ "S", { 1.42, 0.86, 1.42 }, { 0, 0.0, 0 }, nil, "base" },
			{ "C", { 0.1, 1.62, 1.62 }, { 0, -0.18, 0 }, { 0, 0, 90 }, "base" },
			{ "C", { 0.22, 0.34, 0.34 }, { 0, 0.12, -0.7 }, { 0, 90, 0 }, "trim", "Metal" },
			{ "C", { 0.24, 0.24, 0.24 }, { 0, 0.12, -0.72 }, { 0, 90, 0 }, "glow" },
		} } },
	{ Id = "CloverMonocle", Name = "Clover Monocle", Ru = "Монокль-клевер", Rarity = "Uncommon", Slot = "Face", Stat = "Luck",
		Look = { Base = BRASS, Trim = GREEN, Parts = {
			{ "C", { 0.07, 0.5, 0.5 }, { 0.26, 0.02, -0.05 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.08, 0.4, 0.4 }, { 0.26, 0.02, -0.06 }, { 0, 90, 0 }, "glow", nil, 0.35 },
			{ "B", { 0.03, 0.6, 0.03 }, { 0.42, -0.3, -0.04 }, { 0, 0, 20 }, "base", "Metal" },
			{ "S", { 0.12, 0.12, 0.04 }, { 0.5, -0.6, -0.04 }, nil, "trim" },
		} } },
	{ Id = "PupBackpack", Name = "Pup Backpack", Ru = "Рюкзак щенка", Rarity = "Uncommon", Slot = "Back", Stat = "Income",
		Look = { Base = { 70, 150, 220 }, Trim = WHITE, Parts = {
			{ "B", { 1.25, 1.35, 0.55 }, { 0, -0.05, 0.3 }, nil, "base", "Fabric" },
			{ "B", { 0.9, 0.55, 0.22 }, { 0, -0.35, 0.66 }, nil, "trim", "Fabric" },
			{ "S", { 0.26, 0.24, 0.08 }, { 0, -0.36, 0.78 }, nil, "glow" },
			{ "S", { 0.1, 0.1, 0.06 }, { -0.12, -0.2, 0.78 }, nil, "glow" },
			{ "S", { 0.1, 0.1, 0.06 }, { 0.12, -0.2, 0.78 }, nil, "glow" },
		} } },
	{ Id = "SparkAura", Name = "Spark Aura", Ru = "Искристая аура", Rarity = "Uncommon", Slot = "Aura", Stat = "XP",
		Look = { Base = { 120, 220, 255 }, Trim = WHITE, Parts = {
			{ "C", { 0.08, 4.4, 4.4 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "SmoothPlastic", 0.7 },
			{ "S", { 0.3, 0.3, 0.3 }, { 1.8, 1.2, 0 }, nil, "glow" },
			{ "S", { 0.26, 0.26, 0.26 }, { -1.3, 2.0, 1.2 }, nil, "glow" },
			{ "S", { 0.22, 0.22, 0.22 }, { -0.6, 0.8, -1.7 }, nil, "glow" },
		} } },
	-- Rare
	{ Id = "ExplorerFedora", Name = "Explorer Fedora", Ru = "Шляпа исследователя", Rarity = "Rare", Slot = "Hat", Stat = "RareFind",
		Look = { Base = { 150, 110, 70 }, Trim = DARK, Parts = {
			{ "C", { 0.08, 2.0, 2.0 }, { 0, 0.02, 0 }, { 0, 0, 90 }, "base", "Fabric" },
			{ "C", { 0.62, 1.2, 1.2 }, { 0, 0.33, 0 }, { 0, 0, 90 }, "base", "Fabric" },
			{ "C", { 0.16, 1.24, 1.24 }, { 0, 0.12, 0 }, { 0, 0, 90 }, "trim", "Fabric" },
			{ "W", { 0.06, 0.55, 0.3 }, { 0.6, 0.35, 0.1 }, { 0, 0, -20 }, "glow" },
		} } },
	{ Id = "AviatorGoggles", Name = "Aviator Goggles", Ru = "Лётные очки", Rarity = "Rare", Slot = "Face", Stat = "DigSpeed",
		Look = { Base = { 120, 80, 50 }, Trim = { 120, 200, 255 }, Parts = {
			{ "C", { 0.18, 0.5, 0.5 }, { -0.27, 0.05, -0.08 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.18, 0.5, 0.5 }, { 0.27, 0.05, -0.08 }, { 0, 90, 0 }, "base", "Metal" },
			{ "C", { 0.2, 0.38, 0.38 }, { -0.27, 0.05, -0.1 }, { 0, 90, 0 }, "glow", nil, 0.2 },
			{ "C", { 0.2, 0.38, 0.38 }, { 0.27, 0.05, -0.1 }, { 0, 90, 0 }, "glow", nil, 0.2 },
			{ "B", { 1.3, 0.16, 0.06 }, { 0, 0.05, 0.02 }, nil, "base", "Fabric" },
		} } },
	{ Id = "CoinSatchel", Name = "Coin Satchel", Ru = "Сумка с монетами", Rarity = "Rare", Slot = "Back", Stat = "MoneyMult",
		Look = { Base = { 110, 70, 50 }, Trim = GOLD, Parts = {
			{ "S", { 1.3, 1.3, 0.8 }, { 0, -0.15, 0.4 }, nil, "base", "Fabric" },
			{ "C", { 0.2, 0.5, 0.5 }, { 0, 0.5, 0.4 }, { 0, 0, 90 }, "base", "Fabric" },
			{ "C", { 0.08, 0.36, 0.36 }, { -0.25, 0.65, 0.4 }, { 0, 90, 30 }, "glow" },
			{ "C", { 0.08, 0.36, 0.36 }, { 0.2, 0.7, 0.45 }, { 0, 90, -20 }, "glow" },
			{ "S", { 0.3, 0.3, 0.06 }, { 0, -0.15, 0.82 }, nil, "trim", "Foil" },
		} } },
	{ Id = "CloverAura", Name = "Clover Aura", Ru = "Аура клевера", Rarity = "Rare", Slot = "Aura", Stat = "Luck",
		Look = { Base = GREEN, Trim = { 190, 255, 160 }, Parts = {
			{ "C", { 0.08, 4.6, 4.6 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "SmoothPlastic", 0.65 },
			{ "S", { 0.5, 0.06, 0.5 }, { 1.9, 0.15, 0 }, nil, "glow" },
			{ "S", { 0.5, 0.06, 0.5 }, { -1.9, 0.15, 0 }, nil, "glow" },
			{ "S", { 0.5, 0.06, 0.5 }, { 0, 0.15, 1.9 }, nil, "glow" },
			{ "S", { 0.5, 0.06, 0.5 }, { 0, 0.15, -1.9 }, nil, "glow" },
		} } },
	-- Epic
	{ Id = "LuckyTopHat", Name = "Lucky Top Hat", Ru = "Счастливый цилиндр", Rarity = "Epic", Slot = "Hat", Stat = "Luck",
		Look = { Base = { 34, 36, 48 }, Trim = GREEN, Parts = {
			{ "C", { 0.08, 1.75, 1.75 }, { 0, 0.02, 0 }, { 0, 0, 90 }, "base" },
			{ "C", { 1.1, 1.1, 1.1 }, { 0, 0.58, 0 }, { 0, 0, 90 }, "base" },
			{ "C", { 0.2, 1.14, 1.14 }, { 0, 0.2, 0 }, { 0, 0, 90 }, "glow" },
			{ "S", { 0.22, 0.22, 0.06 }, { 0.3, 0.22, -0.56 }, nil, "trim" },
		} } },
	{ Id = "PrismVisor", Name = "Prism Visor", Ru = "Призменный визор", Rarity = "Epic", Slot = "Face", Stat = "ItemMutation",
		Look = { Base = { 220, 230, 255 }, Trim = { 255, 150, 230 }, Parts = {
			{ "B", { 1.25, 0.34, 0.1 }, { 0, 0.04, -0.1 }, nil, "glow", nil, 0.15 },
			{ "B", { 1.32, 0.08, 0.14 }, { 0, 0.22, -0.08 }, nil, "base", "Metal" },
			{ "B", { 0.1, 0.42, 0.7 }, { -0.66, 0.06, 0.25 }, nil, "base", "Metal" },
			{ "B", { 0.1, 0.42, 0.7 }, { 0.66, 0.06, 0.25 }, nil, "base", "Metal" },
		} } },
	{ Id = "RocketPack", Name = "Rocket Pack", Ru = "Ракетный ранец", Rarity = "Epic", Slot = "Back", Stat = "DigSpeed",
		Look = { Base = { 210, 215, 225 }, Trim = RED, Parts = {
			{ "C", { 1.3, 0.5, 0.5 }, { -0.3, 0, 0.35 }, { 0, 0, 90 }, "base", "Metal" },
			{ "C", { 1.3, 0.5, 0.5 }, { 0.3, 0, 0.35 }, { 0, 0, 90 }, "base", "Metal" },
			{ "S", { 0.5, 0.5, 0.5 }, { -0.3, 0.65, 0.35 }, nil, "trim" },
			{ "S", { 0.5, 0.5, 0.5 }, { 0.3, 0.65, 0.35 }, nil, "trim" },
			{ "W", { 0.3, 0.6, 0.3 }, { -0.3, -0.95, 0.35 }, { 180, 0, 0 }, "glow" },
			{ "W", { 0.3, 0.6, 0.3 }, { 0.3, -0.95, 0.35 }, { 180, 0, 0 }, "glow" },
		} } },
	{ Id = "GoldenGlow", Name = "Golden Glow", Ru = "Золотое сияние", Rarity = "Epic", Slot = "Aura", Stat = "Income",
		Look = { Base = GOLD, Trim = { 255, 240, 180 }, Parts = {
			{ "C", { 0.08, 4.8, 4.8 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "SmoothPlastic", 0.6 },
			{ "C", { 0.1, 3.6, 3.6 }, { 0, 0.14, 0 }, { 0, 0, 90 }, "glow", nil, 0.45 },
			{ "C", { 0.06, 3.0, 3.0 }, { 0, 2.4, 0 }, { 0, 0, 90 }, "glow", nil, 0.7 },
		} } },
	-- Legendary
	{ Id = "RoyalCrown", Name = "Royal Crown", Ru = "Королевская корона", Rarity = "Legendary", Slot = "Hat", Stat = "MoneyMult",
		Look = { Base = GOLD, Trim = RED, Parts = {
			{ "C", { 0.42, 1.3, 1.3 }, { 0, 0.18, 0 }, { 0, 0, 90 }, "base", "Foil" },
			{ "W", { 0.26, 0.42, 0.18 }, { 0, 0.58, -0.58 }, nil, "base", "Foil" },
			{ "W", { 0.26, 0.42, 0.18 }, { 0, 0.58, 0.58 }, { 0, 180, 0 }, "base", "Foil" },
			{ "W", { 0.18, 0.42, 0.26 }, { -0.58, 0.58, 0 }, { 0, 90, 0 }, "base", "Foil" },
			{ "W", { 0.18, 0.42, 0.26 }, { 0.58, 0.58, 0 }, { 0, -90, 0 }, "base", "Foil" },
			{ "S", { 0.2, 0.2, 0.1 }, { 0, 0.2, -0.64 }, nil, "glow" },
		} } },
	{ Id = "StarShades", Name = "Star Shades", Ru = "Звёздные очки", Rarity = "Legendary", Slot = "Face", Stat = "Income",
		Look = { Base = GOLD, Trim = { 40, 30, 60 }, Parts = {
			{ "B", { 0.42, 0.42, 0.06 }, { -0.27, 0.04, -0.06 }, { 0, 0, 45 }, "trim", "Glass", 0.1 },
			{ "B", { 0.42, 0.42, 0.06 }, { 0.27, 0.04, -0.06 }, { 0, 0, 45 }, "trim", "Glass", 0.1 },
			{ "B", { 0.3, 0.3, 0.07 }, { -0.27, 0.04, -0.07 }, { 0, 0, 0 }, "glow" },
			{ "B", { 0.3, 0.3, 0.07 }, { 0.27, 0.04, -0.07 }, { 0, 0, 0 }, "glow" },
			{ "B", { 1.3, 0.06, 0.06 }, { 0, 0.24, -0.05 }, nil, "base", "Foil" },
		} } },
	{ Id = "AngelWings", Name = "Angel Wings", Ru = "Крылья ангела", Rarity = "Legendary", Slot = "Back", Stat = "Offline",
		Look = { Base = WHITE, Trim = { 255, 230, 160 }, Parts = {
			{ "W", { 0.12, 1.6, 1.0 }, { -0.75, 0.3, 0.4 }, { 0, 70, 20 }, "base", "SmoothPlastic" },
			{ "W", { 0.12, 1.2, 0.8 }, { -1.2, -0.2, 0.55 }, { 0, 70, 35 }, "base", "SmoothPlastic" },
			{ "W", { 0.12, 1.6, 1.0 }, { 0.75, 0.3, 0.4 }, { 0, -70, -20 }, "base", "SmoothPlastic" },
			{ "W", { 0.12, 1.2, 0.8 }, { 1.2, -0.2, 0.55 }, { 0, -70, -35 }, "base", "SmoothPlastic" },
			{ "S", { 0.3, 0.3, 0.3 }, { 0, 0.2, 0.2 }, nil, "glow" },
		} } },
	{ Id = "InfernoAura", Name = "Inferno Aura", Ru = "Адская аура", Rarity = "Legendary", Slot = "Aura", Stat = "ItemMutation",
		Look = { Base = { 255, 100, 30 }, Trim = { 255, 200, 60 }, Parts = {
			{ "C", { 0.08, 4.8, 4.8 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "SmoothPlastic", 0.6 },
			{ "W", { 0.3, 0.9, 0.5 }, { 2.0, 0.45, 0 }, { 0, 90, 0 }, "glow", nil, 0.2 },
			{ "W", { 0.3, 0.9, 0.5 }, { -2.0, 0.45, 0 }, { 0, -90, 0 }, "glow", nil, 0.2 },
			{ "W", { 0.3, 0.9, 0.5 }, { 0, 0.45, 2.0 }, { 0, 0, 0 }, "glow", nil, 0.2 },
			{ "W", { 0.3, 0.9, 0.5 }, { 0, 0.45, -2.0 }, { 0, 180, 0 }, "glow", nil, 0.2 },
		} } },
	-- Mythic
	{ Id = "CosmicCrown", Name = "Cosmic Crown", Ru = "Космическая корона", Rarity = "Mythic", Slot = "Hat", Stat = "Luck",
		Look = { Base = { 60, 40, 120 }, Trim = { 160, 230, 255 }, Parts = {
			{ "C", { 0.1, 1.6, 1.6 }, { 0, 0.45, 0 }, { 0, 0, 90 }, "glow", nil, 0.1 },
			{ "C", { 0.12, 1.2, 1.2 }, { 0, 0.45, 0 }, { 0, 0, 90 }, "base", "Glass", 0.2 },
			{ "S", { 0.24, 0.24, 0.24 }, { 0, 0.55, -0.8 }, nil, "trim" },
			{ "S", { 0.2, 0.2, 0.2 }, { 0.75, 0.55, 0.3 }, nil, "trim" },
			{ "S", { 0.2, 0.2, 0.2 }, { -0.75, 0.55, 0.3 }, nil, "trim" },
		} } },
	{ Id = "GalaxyMask", Name = "Galaxy Mask", Ru = "Маска галактики", Rarity = "Mythic", Slot = "Face", Stat = "RareFind",
		Look = { Base = { 30, 24, 60 }, Trim = { 200, 160, 255 }, Parts = {
			{ "B", { 1.3, 0.55, 0.12 }, { 0, 0.05, -0.08 }, nil, "base", "Glass", 0.05 },
			{ "S", { 0.26, 0.16, 0.06 }, { -0.27, 0.07, -0.15 }, nil, "glow" },
			{ "S", { 0.26, 0.16, 0.06 }, { 0.27, 0.07, -0.15 }, nil, "glow" },
			{ "S", { 0.08, 0.08, 0.04 }, { -0.5, 0.22, -0.15 }, nil, "trim" },
			{ "S", { 0.06, 0.06, 0.04 }, { 0.48, -0.12, -0.15 }, nil, "trim" },
		} } },
	{ Id = "VoidWings", Name = "Void Wings", Ru = "Крылья пустоты", Rarity = "Mythic", Slot = "Back", Stat = "MoneyMult",
		Look = { Base = VOID, Trim = PURPLE, Parts = {
			{ "W", { 0.12, 1.8, 1.1 }, { -0.8, 0.35, 0.4 }, { 0, 70, 25 }, "base", "Glass", 0.1 },
			{ "W", { 0.14, 1.3, 0.8 }, { -1.3, -0.25, 0.55 }, { 0, 70, 40 }, "glow", nil, 0.2 },
			{ "W", { 0.12, 1.8, 1.1 }, { 0.8, 0.35, 0.4 }, { 0, -70, -25 }, "base", "Glass", 0.1 },
			{ "W", { 0.14, 1.3, 0.8 }, { 1.3, -0.25, 0.55 }, { 0, -70, -40 }, "glow", nil, 0.2 },
		} } },
	{ Id = "RainbowAura", Name = "Rainbow Aura", Ru = "Радужная аура", Rarity = "Mythic", Slot = "Aura", Stat = "Income",
		Look = { Base = { 255, 90, 160 }, Trim = { 80, 230, 240 }, Parts = {
			{ "C", { 0.08, 5.0, 5.0 }, { 0, 0.1, 0 }, { 0, 0, 90 }, "base", "Neon", 0.6 },
			{ "C", { 0.08, 4.2, 4.2 }, { 0, 0.14, 0 }, { 0, 0, 90 }, "trim", "Neon", 0.55 },
			{ "C", { 0.08, 3.4, 3.4 }, { 0, 0.18, 0 }, { 0, 0, 90 }, "glow", nil, 0.5 },
			{ "C", { 0.06, 3.2, 3.2 }, { 0, 2.6, 0 }, { 0, 0, 90 }, "glow", nil, 0.65 },
		} } },
}

-- Cases. Price: Cash follows the player's income (BoostPricing.Coins: the layer floor or that many
-- minutes of the team's income, whichever is larger), Bones are fixed, Robux buys credits.
-- Odds are percentages per rarity (sum 100). Pity: the Opens-th open in a row without a piece of
-- at least that rarity is guaranteed to be one.
E.Cases = {
	{ Id = "DigCrate", Kind = "Artifact", Name = "DIG CRATE", Ru = "ЯЩИК КОПАТЕЛЯ",
		Cash = { MinCash = 3000, IncomeMinutes = 5 },
		Odds = { Common = 52, Uncommon = 30, Rare = 13, Epic = 4, Legendary = 0.9, Mythic = 0.1 },
		Pity = { Rarity = "Epic", Opens = 30 },
		Look = { Base = { 150, 105, 64 }, Trim = { 120, 128, 140 }, Glow = "Rare" } },
	{ Id = "RelicChest", Kind = "Artifact", Name = "RELIC CHEST", Ru = "СУНДУК РЕЛИКВИЙ",
		Bones = 60,
		Odds = { Uncommon = 38, Rare = 37, Epic = 18, Legendary = 6, Mythic = 1 },
		Pity = { Rarity = "Legendary", Opens = 30 },
		Look = { Base = { 90, 60, 140 }, Trim = { 249, 196, 64 }, Glow = "Epic" } },
	{ Id = "MythicVault", Kind = "Artifact", Name = "MYTHIC VAULT", Ru = "МИФИЧЕСКОЕ ХРАНИЛИЩЕ",
		Robux = true,
		Odds = { Rare = 40, Epic = 38, Legendary = 18, Mythic = 4 },
		Pity = { Rarity = "Legendary", Opens = 10 },
		Look = { Base = { 40, 30, 70 }, Trim = { 247, 73, 112 }, Glow = "Mythic" } },
	{ Id = "StyleBox", Kind = "Accessory", Name = "STYLE BOX", Ru = "КОРОБКА СТИЛЯ",
		Cash = { MinCash = 3000, IncomeMinutes = 5 },
		Odds = { Common = 52, Uncommon = 30, Rare = 13, Epic = 4, Legendary = 0.9, Mythic = 0.1 },
		Pity = { Rarity = "Epic", Opens = 30 },
		Look = { Base = { 60, 160, 220 }, Trim = { 245, 245, 250 }, Glow = "Rare" } },
	{ Id = "GlamChest", Kind = "Accessory", Name = "GLAM CHEST", Ru = "ГЛАМУРНЫЙ СУНДУК",
		Bones = 60,
		Odds = { Uncommon = 38, Rare = 37, Epic = 18, Legendary = 6, Mythic = 1 },
		Pity = { Rarity = "Legendary", Opens = 30 },
		Look = { Base = { 230, 90, 160 }, Trim = { 249, 196, 64 }, Glow = "Epic" } },
	{ Id = "StarTrunk", Kind = "Accessory", Name = "STAR TRUNK", Ru = "ЗВЁЗДНЫЙ СУНДУК",
		Robux = true,
		Odds = { Rare = 40, Epic = 38, Legendary = 18, Mythic = 4 },
		Pity = { Rarity = "Legendary", Opens = 10 },
		Look = { Base = { 30, 40, 90 }, Trim = { 120, 220, 255 }, Glow = "Mythic" } },
}

-- Robux packs of case credits (developer products). Id = 0 / Enabled = false: not sold until
-- the owner creates the products in Creator Hub and pastes the ids here (docs/EQUIPMENT.md).
-- Opening a credit bought with Robux is a paid random reward: PaidRandomPolicy gates it, the odds
-- are shown before the purchase and the piece is flagged PaidRandom.
E.Products = {
	{ Key = "MythicVault1", Case = "MythicVault", Count = 1, Id = 0, Enabled = false, Robux = 49, Name = "MYTHIC VAULT KEY" },
	{ Key = "MythicVault5", Case = "MythicVault", Count = 5, Id = 0, Enabled = false, Robux = 199, Name = "5 MYTHIC VAULT KEYS" },
	{ Key = "StarTrunk1", Case = "StarTrunk", Count = 1, Id = 0, Enabled = false, Robux = 49, Name = "STAR TRUNK KEY" },
	{ Key = "StarTrunk5", Case = "StarTrunk", Count = 5, Id = 0, Enabled = false, Robux = 199, Name = "5 STAR TRUNK KEYS" },
}

-- Indexes and computed roll ranges.
E.ArtifactById, E.AccessoryById, E.CaseById, E.ProductByKey = {}, {}, {}, {}
for i, def in ipairs(E.Artifacts) do
	def.Kind = "Artifact"
	def.Order = i
	local range = ARTIFACT_RANGE[def.Rarity]
	local scale = ARTIFACT_SCALE[def.Stat] or 1
	def.Min, def.Max = round4(range[1] * scale), round4(range[2] * scale)
	E.ArtifactById[def.Id] = def
end
for i, def in ipairs(E.Accessories) do
	def.Kind = "Accessory"
	def.Order = i
	local range = ACCESSORY_RANGE[def.Rarity]
	local scale = ACCESSORY_SCALE[def.Stat] or 1
	def.Min, def.Max = round4(range[1] * scale), round4(range[2] * scale)
	E.AccessoryById[def.Id] = def
end
for i, case in ipairs(E.Cases) do
	case.Order = i
	E.CaseById[case.Id] = case
end
for _, product in ipairs(E.Products) do
	E.ProductByKey[product.Key] = product
end

-- The definition of a piece id (artifact or accessory) and its kind.
function E.Def(id: any): (any, string?)
	if type(id) ~= "string" then
		return nil, nil
	end
	local def = E.ArtifactById[id]
	if def then
		return def, "Artifact"
	end
	def = E.AccessoryById[id]
	if def then
		return def, "Accessory"
	end
	return nil, nil
end

-- The value of an owned piece ({Id, Roll}): Min + (Max - Min) * Roll. 0 for unknown pieces.
function E.Value(entry: any): number
	if type(entry) ~= "table" then
		return 0
	end
	local def = E.Def(entry.Id)
	if not def then
		return 0
	end
	local roll = tonumber(entry.Roll) or 0
	if roll ~= roll then
		roll = 0
	end
	roll = math.clamp(roll, 0, 1)
	return def.Min + (def.Max - def.Min) * roll
end

-- Artifact slots of a dog: accepts a dog definition / dog record with Rank or Rarity, a rank
-- number (1..6) or a dog rarity name.
function E.DogSlots(value: any): number
	local rank: number? = nil
	if type(value) == "number" then
		rank = value
	elseif type(value) == "string" then
		rank = table.find(E.DogRarities, value)
	elseif type(value) == "table" then
		rank = tonumber(value.Rank) or table.find(E.DogRarities, value.Rarity or "")
	end
	if not rank then
		return 1
	end
	rank = math.clamp(math.floor(rank), 1, #E.DogSlotsByRank)
	return E.DogSlotsByRank[rank]
end

-- Pieces a case can give, grouped by rarity: {[rarity] = {def, ...}} (catalogue order).
function E.Pool(case: any): { [string]: { any } }
	local list = case.Kind == "Artifact" and E.Artifacts or E.Accessories
	local pool = {}
	for _, def in ipairs(list) do
		if (case.Odds[def.Rarity] or 0) > 0 then
			pool[def.Rarity] = pool[def.Rarity] or {}
			table.insert(pool[def.Rarity], def)
		end
	end
	return pool
end

-- Odds rows of a case, rarest last: {{Rarity, Chance (0..1), Count = pieces of that rarity}}.
function E.Odds(case: any): { any }
	local total = 0
	for _, r in ipairs(E.Rarities) do
		total += case.Odds[r] or 0
	end
	local pool = E.Pool(case)
	local rows = {}
	for _, r in ipairs(E.Rarities) do
		local weight = case.Odds[r] or 0
		if weight > 0 and pool[r] then
			table.insert(rows, { Rarity = r, Chance = total > 0 and weight / total or 0, Count = #pool[r] })
		end
	end
	return rows
end

-- Cash price of one open for this player (nil when the case is not sold for Cash).
function E.CashPrice(case: any, p: any, now: number?): number?
	if type(case) ~= "table" or type(case.Cash) ~= "table" then
		return nil
	end
	return Pricing.Coins(case.Cash, p, now)
end

-- "+12.3%" for a stat value (fractions).
function E.Format(value: number): string
	local pct = (tonumber(value) or 0) * 100
	if pct >= 10 then
		return string.format("+%.1f%%", pct)
	end
	local text = string.format("+%.2f%%", pct)
	text = (string.gsub(text, "0%%$", "%%"))
	return text
end

-- Roll quality label (shown on cards): 0..1 -> "87%".
function E.Quality(roll: number): number
	return math.floor(math.clamp(tonumber(roll) or 0, 0, 1) * 100 + 0.5)
end

return E
