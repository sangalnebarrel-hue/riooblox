-- The UPGRADE TREE of the yard: the one definition table behind the purchase rules (server feature
-- ServerScriptService.Economy.Features.UpgradeTree), the stat bonuses (BonusSources.UpgradeTree ->
-- DogEconomy.Bonuses -> Rules.Dig / IncomeModel / offline earnings) and the UPGRADE TREE window
-- (StarterGui.ScreenGui.Modules.UpgradeTreeScreen). Shared by server and client, pure: nothing here
-- writes a profile.
--
-- Levels live in p.Upgrades[nodeId] (missing = 0). The six original yard upgrades are nodes with
-- their original keys (Dig, Storage, Kennel, Plot, DogStorage, Ability): their prices, level gates
-- and maxima come from Config.Upgrades and their effects stay where they always were (Rules,
-- ItemRules, PlotCatalog), so saved levels keep their meaning without a migration. Every other node
-- feeds one Bonuses key through BonusSources.UpgradeTree.
--
-- Node fields: Id, Branch, Name, Description, Stat (Bonuses key) or Legacy=true, PerLevel, Max,
-- Cost={Base, Factor, Bones={Base, Factor}?}, Gate={Base, Step} (player level for the next level:
-- Base + current level x Step), Requires={[nodeId]=level} (checked when buying only), X/Y (layout
-- grid: the hub is 0,0, the crown grows up, the roots grow down), Tier (1-4), Capstone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Config)
local PlotCatalog = require(ReplicatedStorage:WaitForChild("PlotCatalog"))

local T = {}
-- p.UpgradeTreeVersion: raise only together with an idempotent migration in the feature Normalize.
T.Version = 1

-- How a stat reads in the window. Label is English; the window translates it (Localization.UpgradeTree).
-- Format: "percent" (+12%), "mult" (x1.25), "units" (+50), "count" (220), "stage" (yard stage name).
T.Stats = {
	DigSpeed = { Label = "dig speed", Format = "percent" },
	Luck = { Label = "rare loot luck", Format = "percent" },
	Income = { Label = "earnings", Format = "percent" },
	MoneyMult = { Label = "money multiplier", Format = "mult" },
	RareFind = { Label = "rare find chance", Format = "percent" },
	ItemMutation = { Label = "find mutation chance", Format = "percent" },
	DogPower = { Label = "dog power", Format = "percent" },
	Storage = { Label = "discovery slots", Format = "units" },
	XP = { Label = "XP gain", Format = "percent" },
	Offline = { Label = "offline earnings", Format = "percent" },
	DogMutation = { Label = "mutated dog chance", Format = "percent" },
	-- Mining Strength (Config.Mining): unlocks the better pickaxes and adds damage above a pickaxe's
	-- requirement. Read by Economy.Rules.MiningAction / Runtime (not a Bonuses key).
	Strength = { Label = "mining strength", Format = "units" },
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Ordered as drawn: the crown (stat branches) left to right, then the roots (the base).
T.Branches = {
	{ Id = "Speed", Name = "DIGGING SPEED", Icon = "Dig", Color = rgb(74, 196, 92), Side = "Crown",
		Description = "Dogs rest less between digs. Speed past the limit becomes extra loot rolls." },
	{ Id = "Dogs", Name = "DOG EFFICIENCY", Icon = "Dogs", Color = rgb(240, 120, 70), Side = "Crown",
		Description = "Every dog digs as if it were stronger." },
	{ Id = "Earnings", Name = "EARNINGS", Icon = "Coins", Color = rgb(249, 180, 35), Side = "Crown",
		Description = "Everything your dogs dig is worth more." },
	{ Id = "Money", Name = "MONEY MULTIPLIER", Icon = "MoneyVault", Color = rgb(236, 72, 153), Side = "Crown",
		Description = "Rare and expensive multipliers on all dog earnings." },
	{ Id = "Luck", Name = "LUCK", Icon = "Luck", Color = rgb(38, 190, 160), Side = "Crown",
		Description = "Rare loot (artifacts, treasure, space finds) comes up more often." },
	{ Id = "Rare", Name = "RARE FINDS", Icon = "RareBlock", Color = rgb(38, 164, 243), Side = "Crown",
		Description = "A bigger chance to dig up rare discoveries." },
	{ Id = "Mutation", Name = "FIND MUTATIONS", Icon = "Star", Color = rgb(161, 103, 242), Side = "Crown",
		Description = "Discoveries come out Golden, Rainbow, Cursed and other mutations more often." },
	{ Id = "Strength", Name = "STRENGTH", Icon = "EnergySnack", Color = rgb(235, 72, 52), Side = "Crown",
		Description = "Mining Strength: better pickaxes need it, and every point above a pickaxe's need adds damage." },
	{ Id = "Estate", Name = "ESTATE", Icon = "Yard", Color = rgb(196, 140, 74), Side = "Roots",
		Description = "Develop your yard: more kennels and a more valuable estate." },
	{ Id = "Storage", Name = "STORAGE & CAPACITY", Icon = "StorageCrate", Color = rgb(70, 140, 220), Side = "Roots",
		Description = "Room for more discoveries and more dogs." },
	{ Id = "Processes", Name = "PROCESSES", Icon = "Settings", Color = rgb(20, 170, 190), Side = "Roots",
		Description = "Offline earnings and faster player levels." },
	{ Id = "Abilities", Name = "ABILITIES", Icon = "LuckyTreat", Color = rgb(214, 80, 200), Side = "Roots",
		Description = "Stronger dog abilities and better genes." },
}
T.BranchById = {}
for index, branch in ipairs(T.Branches) do
	branch.Index = index
	T.BranchById[branch.Id] = branch
end

local legacyEffects = Config.UpgradeEffects
-- {Id, Branch, X, Y, Tier, ...}: see the header for the fields.
local list = {
	-- DIGGING SPEED -----------------------------------------------------------------------------
	{ Id = "Dig", Branch = "Speed", Legacy = true, Name = "DIG SPEED", X = -3, Y = -1, Tier = 1,
		Label = "dig speed", Format = "percent", PerLevel = legacyEffects.Dig,
		Description = "Dogs rest less between digs. Stacks with every other speed bonus." },
	{ Id = "QuickPaws", Branch = "Speed", Name = "QUICK PAWS", X = -3, Y = -2, Tier = 2,
		Stat = "DigSpeed", PerLevel = 0.02, Max = 10, Cost = { Base = 45000, Factor = 1.75 }, Gate = { Base = 8, Step = 1 },
		Requires = { Dig = 3 }, Description = "Every dog digs faster. Speed past the limit turns into extra loot rolls." },
	{ Id = "TirelessDiggers", Branch = "Speed", Name = "TIRELESS DIGGERS", X = -3, Y = -3, Tier = 3,
		Stat = "DigSpeed", PerLevel = 0.025, Max = 10, Cost = { Base = 3200000, Factor = 1.85 }, Gate = { Base = 18, Step = 1.5 },
		Requires = { QuickPaws = 5 }, Description = "Every dog digs even faster." },
	{ Id = "TurboDig", Branch = "Speed", Name = "TURBO DIG", X = -3, Y = -4, Tier = 4, Capstone = true,
		Stat = "DigSpeed", PerLevel = 0.05, Max = 5, Cost = { Base = 300000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 32, Step = 2 }, Requires = { TirelessDiggers = 10 },
		Description = "Capstone: a big boost to the digging speed of every dog." },
	-- DOG EFFICIENCY ----------------------------------------------------------------------------
	{ Id = "PuppyTraining", Branch = "Dogs", Name = "PUPPY TRAINING", X = -2, Y = -1, Tier = 1,
		Stat = "DogPower", PerLevel = 0.015, Max = 10, Cost = { Base = 4000, Factor = 1.75 }, Gate = { Base = 2, Step = 1 },
		Description = "Every dog digs with more power: more Cash from every dig." },
	{ Id = "AlphaDiet", Branch = "Dogs", Name = "ALPHA DIET", X = -2, Y = -2, Tier = 2,
		Stat = "DogPower", PerLevel = 0.02, Max = 10, Cost = { Base = 70000, Factor = 1.8 }, Gate = { Base = 10, Step = 1 },
		Requires = { PuppyTraining = 5 }, Description = "A better diet: every dog digs with more power." },
	{ Id = "ChampionBloodline", Branch = "Dogs", Name = "CHAMPION BLOODLINE", X = -2, Y = -3, Tier = 3,
		Stat = "DogPower", PerLevel = 0.02, Max = 10, Cost = { Base = 3500000, Factor = 1.85 }, Gate = { Base = 20, Step = 1.5 },
		Requires = { AlphaDiet = 5 }, Description = "Champion genes: every dog digs with more power." },
	{ Id = "PackLeader", Branch = "Dogs", Name = "PACK LEADER", X = -2, Y = -4, Tier = 4, Capstone = true,
		Stat = "DogPower", PerLevel = 0.04, Max = 5, Cost = { Base = 330000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 34, Step = 2 }, Requires = { ChampionBloodline = 10 },
		Description = "Capstone: the whole pack digs with much more power." },
	-- EARNINGS ----------------------------------------------------------------------------------
	{ Id = "TreatBudget", Branch = "Earnings", Name = "TREAT BUDGET", X = -1, Y = -1, Tier = 1,
		Stat = "Income", PerLevel = 0.02, Max = 10, Cost = { Base = 3000, Factor = 1.75 }, Gate = { Base = 1, Step = 1 },
		Description = "Everything your dogs dig is worth more." },
	{ Id = "SharpShovels", Branch = "Earnings", Name = "SHARP SHOVELS", X = -1, Y = -2, Tier = 2,
		Stat = "Income", PerLevel = 0.025, Max = 10, Cost = { Base = 60000, Factor = 1.8 }, Gate = { Base = 9, Step = 1 },
		Requires = { TreatBudget = 5 }, Description = "Sharper tools: everything your dogs dig is worth more." },
	{ Id = "MarketSavvy", Branch = "Earnings", Name = "MARKET SAVVY", X = -1, Y = -3, Tier = 3,
		Stat = "Income", PerLevel = 0.025, Max = 10, Cost = { Base = 3400000, Factor = 1.85 }, Gate = { Base = 19, Step = 1.5 },
		Requires = { SharpShovels = 5 }, Description = "Better deals: everything your dogs dig is worth more." },
	{ Id = "DigTycoon", Branch = "Earnings", Name = "DIG TYCOON", X = -1, Y = -4, Tier = 4, Capstone = true,
		Stat = "Income", PerLevel = 0.05, Max = 5, Cost = { Base = 320000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 33, Step = 2 }, Requires = { MarketSavvy = 10 },
		Description = "Capstone: a big boost to the value of everything your dogs dig." },
	-- MONEY MULTIPLIER --------------------------------------------------------------------------
	{ Id = "PawsOfGold", Branch = "Money", Name = "PAWS OF GOLD", X = 0, Y = -3, Tier = 3,
		Stat = "MoneyMult", PerLevel = 0.03, Max = 5, Cost = { Base = 30000000, Factor = 2 }, Gate = { Base = 24, Step = 2 },
		Requires = { SharpShovels = 8, FourLeafCollar = 8 },
		Description = "A money multiplier on all dog earnings. It multiplies with every other bonus." },
	{ Id = "DogecoinVault", Branch = "Money", Name = "DOGECOIN VAULT", X = 0, Y = -4.35, Tier = 4, Capstone = true,
		Stat = "MoneyMult", PerLevel = 0.05, Max = 5, Cost = { Base = 1200000000, Factor = 2, Bones = { Base = 300, Factor = 1.5 } },
		Gate = { Base = 40, Step = 2 }, Requires = { PawsOfGold = 5 },
		Description = "Capstone: a second money multiplier on all dog earnings." },
	-- LUCK --------------------------------------------------------------------------------------
	{ Id = "LuckyNose", Branch = "Luck", Name = "LUCKY NOSE", X = 1, Y = -1, Tier = 1,
		Stat = "Luck", PerLevel = 0.04, Max = 10, Cost = { Base = 2500, Factor = 1.7 }, Gate = { Base = 2, Step = 1 },
		Description = "Rare loot (artifacts, treasure, space finds) comes up more often, and rare discoveries a little too." },
	{ Id = "FourLeafCollar", Branch = "Luck", Name = "FOUR-LEAF COLLAR", X = 1, Y = -2, Tier = 2,
		Stat = "Luck", PerLevel = 0.05, Max = 10, Cost = { Base = 40000, Factor = 1.75 }, Gate = { Base = 10, Step = 1 },
		Requires = { LuckyNose = 5 }, Description = "More luck on rare loot and rare discoveries." },
	{ Id = "FortuneHound", Branch = "Luck", Name = "FORTUNE HOUND", X = 1, Y = -3, Tier = 3,
		Stat = "Luck", PerLevel = 0.06, Max = 10, Cost = { Base = 2600000, Factor = 1.8 }, Gate = { Base = 20, Step = 1.5 },
		Requires = { FourLeafCollar = 5 }, Description = "Even more luck on rare loot and rare discoveries." },
	{ Id = "GoldenHorseshoe", Branch = "Luck", Name = "GOLDEN HORSESHOE", X = 1, Y = -4, Tier = 4, Capstone = true,
		Stat = "Luck", PerLevel = 0.12, Max = 5, Cost = { Base = 260000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 34, Step = 2 }, Requires = { FortuneHound = 10 },
		Description = "Capstone: a big boost to luck." },
	-- RARE FINDS --------------------------------------------------------------------------------
	{ Id = "TreasureSense", Branch = "Rare", Name = "TREASURE SENSE", X = 2, Y = -1, Tier = 1,
		Stat = "RareFind", PerLevel = 0.05, Max = 10, Cost = { Base = 2500, Factor = 1.7 }, Gate = { Base = 3, Step = 1 },
		Description = "Rare discoveries (the ones with the smallest drop chance) are found more often." },
	{ Id = "RelicRadar", Branch = "Rare", Name = "RELIC RADAR", X = 2, Y = -2, Tier = 2,
		Stat = "RareFind", PerLevel = 0.06, Max = 10, Cost = { Base = 40000, Factor = 1.75 }, Gate = { Base = 11, Step = 1 },
		Requires = { TreasureSense = 5 }, Description = "Rare discoveries are found more often." },
	{ Id = "DeepScanner", Branch = "Rare", Name = "DEEP SCANNER", X = 2, Y = -3, Tier = 3,
		Stat = "RareFind", PerLevel = 0.08, Max = 10, Cost = { Base = 2400000, Factor = 1.8 }, Gate = { Base = 21, Step = 1.5 },
		Requires = { RelicRadar = 5 }, Description = "Rare discoveries are found even more often." },
	{ Id = "Archaeologist", Branch = "Rare", Name = "ARCHAEOLOGIST", X = 2, Y = -4, Tier = 4, Capstone = true,
		Stat = "RareFind", PerLevel = 0.15, Max = 5, Cost = { Base = 220000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 34, Step = 2 }, Requires = { DeepScanner = 10 },
		Description = "Capstone: rare discoveries turn up much more often." },
	-- FIND MUTATIONS ----------------------------------------------------------------------------
	{ Id = "ShinyPolish", Branch = "Mutation", Name = "SHINY POLISH", X = 3, Y = -1, Tier = 1,
		Stat = "ItemMutation", PerLevel = 0.08, Max = 10, Cost = { Base = 3000, Factor = 1.7 }, Gate = { Base = 4, Step = 1 },
		Description = "Discoveries come out mutated (Golden, Rainbow, Cursed...) more often. Mutated finds sell for more." },
	{ Id = "StrangeSoil", Branch = "Mutation", Name = "STRANGE SOIL", X = 3, Y = -2, Tier = 2,
		Stat = "ItemMutation", PerLevel = 0.1, Max = 10, Cost = { Base = 45000, Factor = 1.75 }, Gate = { Base = 12, Step = 1 },
		Requires = { ShinyPolish = 5 }, Description = "Discoveries mutate more often." },
	{ Id = "CosmicDust", Branch = "Mutation", Name = "COSMIC DUST", X = 3, Y = -3, Tier = 3,
		Stat = "ItemMutation", PerLevel = 0.12, Max = 10, Cost = { Base = 1800000, Factor = 1.8 }, Gate = { Base = 22, Step = 1.5 },
		Requires = { StrangeSoil = 5 }, Description = "Discoveries mutate even more often." },
	{ Id = "PrismCore", Branch = "Mutation", Name = "PRISM CORE", X = 3, Y = -4, Tier = 4, Capstone = true,
		Stat = "ItemMutation", PerLevel = 0.25, Max = 5, Cost = { Base = 150000000, Factor = 2, Bones = { Base = 120, Factor = 1.5 } },
		Gate = { Base = 35, Step = 2 }, Requires = { CosmicDust = 10 },
		Description = "Capstone: discoveries mutate much more often." },
	-- STRENGTH ----------------------------------------------------------------------------------
	-- Mining Strength used to be trained at the weight rack of the Mining Corner; it lives here now.
	-- Price curve (docs/BALANCE.md): reaching each pickaxe's Strength costs about 20-40% of that
	-- pickaxe's price, so Strength stays a real but secondary step of the pickaxe ladder
	-- (all 1,100 points: ~3.3B Coins + Bones, the TV-Head pickaxe alone costs 10B).
	{ Id = "IronGrip", Branch = "Strength", Name = "IRON GRIP", X = 4, Y = -1, Tier = 1,
		Stat = "Strength", PerLevel = 5, Max = 10, Cost = { Base = 550, Factor = 1.33 }, Gate = { Base = 1, Step = 0.5 },
		Description = "+5 mining Strength per level. Strength unlocks better pickaxes and adds damage." },
	{ Id = "HeavyLifter", Branch = "Strength", Name = "HEAVY LIFTER", X = 4, Y = -2, Tier = 2,
		Stat = "Strength", PerLevel = 10, Max = 10, Cost = { Base = 7500, Factor = 1.3 }, Gate = { Base = 4, Step = 0.5 },
		Requires = { IronGrip = 5 }, Description = "+10 mining Strength per level." },
	{ Id = "TitanBack", Branch = "Strength", Name = "TITAN BACK", X = 4, Y = -3, Tier = 3,
		Stat = "Strength", PerLevel = 20, Max = 10, Cost = { Base = 230000, Factor = 1.3 }, Gate = { Base = 12, Step = 1 },
		Requires = { HeavyLifter = 5 }, Description = "+20 mining Strength per level." },
	{ Id = "Colossus", Branch = "Strength", Name = "COLOSSUS", X = 4, Y = -4, Tier = 3,
		Stat = "Strength", PerLevel = 45, Max = 10, Cost = { Base = 4500000, Factor = 1.38 }, Gate = { Base = 20, Step = 1.5 },
		Requires = { TitanBack = 5 }, Description = "+45 mining Strength per level." },
	{ Id = "MountainBreaker", Branch = "Strength", Name = "MOUNTAIN BREAKER", X = 4, Y = -5, Tier = 4, Capstone = true,
		Stat = "Strength", PerLevel = 60, Max = 5, Cost = { Base = 250000000, Factor = 1.45, Bones = { Base = 80, Factor = 1.5 } },
		Gate = { Base = 32, Step = 2 }, Requires = { Colossus = 10 },
		Description = "Capstone: +60 mining Strength per level, up to the full 1,100." },
	-- ESTATE ------------------------------------------------------------------------------------
	{ Id = "Plot", Branch = "Estate", Legacy = true, Name = "EXPAND YOUR YARD", X = -3, Y = 1, Tier = 1,
		Label = "yard stage", Format = "stage", PerLevel = legacyEffects.Plot,
		Description = "Grow your yard stage by stage: new kennels open, the estate is rebuilt, and everything your dogs dig is worth more with every stage." },
	{ Id = "Kennel", Branch = "Estate", Legacy = true, Name = "KENNEL QUALITY", X = -2, Y = 1, Tier = 1,
		Label = "dug value", Format = "percent", PerLevel = legacyEffects.Kennel,
		Description = "Better kennels: everything your dogs dig is worth more." },
	-- STORAGE & CAPACITY ------------------------------------------------------------------------
	{ Id = "Storage", Branch = "Storage", Legacy = true, Name = "DISCOVERY STORAGE", X = -1, Y = 1, Tier = 1,
		Label = "discovery slots", Format = "units", PerLevel = legacyEffects.Storage,
		Description = "More slots for discoveries, so dogs keep finding items longer before you sell." },
	{ Id = "BiggerCrates", Branch = "Storage", Name = "BIGGER CRATES", X = -1, Y = 2, Tier = 2,
		Stat = "Storage", PerLevel = 10, Max = 10, Cost = { Base = 25000, Factor = 1.6 }, Gate = { Base = 6, Step = 1 },
		Requires = { Storage = 3 }, Description = "More slots for discoveries." },
	{ Id = "VaultAnnex", Branch = "Storage", Name = "VAULT ANNEX", X = -1, Y = 3, Tier = 3,
		Stat = "Storage", PerLevel = 20, Max = 10, Cost = { Base = 1500000, Factor = 1.65 }, Gate = { Base = 18, Step = 1.5 },
		Requires = { BiggerCrates = 10 }, Description = "Many more slots for discoveries." },
	{ Id = "DogStorage", Branch = "Storage", Legacy = true, Name = "DOG CAPACITY", X = 0, Y = 1, Tier = 1,
		Label = "dog capacity", Format = "count", PerLevel = legacyEffects.DogStorage,
		Description = "Room for more dogs in your storage." },
	-- PROCESSES ---------------------------------------------------------------------------------
	{ Id = "NightShift", Branch = "Processes", Name = "NIGHT SHIFT", X = 1, Y = 1, Tier = 1,
		Stat = "Offline", PerLevel = 0.05, Max = 10, Cost = { Base = 8000, Factor = 1.7 }, Gate = { Base = 5, Step = 1 },
		Description = "Dogs earn more while you are offline." },
	{ Id = "EndlessShift", Branch = "Processes", Name = "ENDLESS SHIFT", X = 1, Y = 2, Tier = 3,
		Stat = "Offline", PerLevel = 0.1, Max = 5, Cost = { Base = 5000000, Factor = 2, Bones = { Base = 60, Factor = 1.5 } },
		Gate = { Base = 22, Step = 2 }, Requires = { NightShift = 10 },
		Description = "Capstone: dogs earn much more while you are offline." },
	{ Id = "FastLearner", Branch = "Processes", Name = "FAST LEARNER", X = 2, Y = 1, Tier = 1,
		Stat = "XP", PerLevel = 0.04, Max = 10, Cost = { Base = 6000, Factor = 1.7 }, Gate = { Base = 3, Step = 1 },
		Description = "Digging and finds give more XP." },
	{ Id = "Bookworm", Branch = "Processes", Name = "BOOKWORM", X = 2, Y = 2, Tier = 3,
		Stat = "XP", PerLevel = 0.08, Max = 5, Cost = { Base = 2000000, Factor = 2 }, Gate = { Base = 18, Step = 2 },
		Requires = { FastLearner = 10 }, Description = "Digging and finds give even more XP." },
	-- ABILITIES ---------------------------------------------------------------------------------
	{ Id = "Ability", Branch = "Abilities", Legacy = true, Name = "ABILITY POWER", X = 3, Y = 1, Tier = 1,
		Label = "dug value", Format = "percent", PerLevel = legacyEffects.Ability,
		Description = "Strengthens what dog abilities produce: everything your dogs dig is worth more." },
	{ Id = "GoodGenes", Branch = "Abilities", Name = "GOOD GENES", X = 3, Y = 2, Tier = 2,
		Stat = "DogMutation", PerLevel = 0.05, Max = 10, Cost = { Base = 100000, Factor = 1.75 }, Gate = { Base = 12, Step = 1 },
		Requires = { Ability = 2 },
		Description = "Dogs you buy from the conveyor are mutated (Shiny, Golden, Void...) more often." },
}

T.Nodes = {}
T.Order = {}
for _, node in ipairs(list) do
	assert(T.BranchById[node.Branch], "UpgradeTree: unknown branch " .. tostring(node.Branch))
	assert(T.Nodes[node.Id] == nil, "UpgradeTree: duplicate node " .. node.Id)
	if node.Legacy then
		-- The original yard upgrades keep their saved key, price curve, level gate and maximum.
		local legacy = Config.Upgrades[node.Id]
		assert(legacy, "UpgradeTree: legacy upgrade missing from Config.Upgrades: " .. node.Id)
		node.Max = legacy.Max
		node.Cost = { Base = legacy.Base, Factor = legacy.Factor }
		node.Gate = { Base = legacy.LevelBase or 1, Step = legacy.LevelStep or 0 }
	else
		assert(T.Stats[node.Stat], "UpgradeTree: unknown stat " .. tostring(node.Stat))
		node.Label = T.Stats[node.Stat].Label
		node.Format = T.Stats[node.Stat].Format
	end
	node.Requires = node.Requires or {}
	node.Tier = node.Tier or 1
	T.Nodes[node.Id] = node
	table.insert(T.Order, node.Id)
end
for _, node in pairs(T.Nodes) do
	for parent in pairs(node.Requires) do
		assert(T.Nodes[parent], "UpgradeTree: " .. node.Id .. " requires unknown node " .. parent)
	end
end
-- Branch order, then bottom to top inside the crown and top to bottom inside the roots.
table.sort(T.Order, function(a, b)
	local x, y = T.Nodes[a], T.Nodes[b]
	local bx, by = T.BranchById[x.Branch].Index, T.BranchById[y.Branch].Index
	if bx ~= by then
		return bx < by
	end
	if math.abs(x.Y) ~= math.abs(y.Y) then
		return math.abs(x.Y) < math.abs(y.Y)
	end
	return x.X < y.X
end)

-- Lines of the drawing: {From, To, Need}. From = "Hub" for the first node of a path.
T.Edges = {}
for _, id in ipairs(T.Order) do
	local node = T.Nodes[id]
	local any = false
	local parents = {}
	for parent in pairs(node.Requires) do
		table.insert(parents, parent)
	end
	table.sort(parents)
	for _, parent in ipairs(parents) do
		any = true
		table.insert(T.Edges, { From = parent, To = id, Need = node.Requires[parent] })
	end
	if not any then
		table.insert(T.Edges, { From = "Hub", To = id, Need = 0 })
	end
end

-- Prices are rounded to three significant digits (12,345 -> 12,300) so they read cleanly. The
-- original upgrades keep their exact old prices.
local function nice(n)
	n = math.max(0, n)
	if n < 1000 then
		return math.floor(n + 0.5)
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.floor(n / step + 0.5) * step
end
T.Nice = nice

-- Saved level of a node (0 when missing or malformed).
function T.Level(p, id)
	local upgrades = type(p) == "table" and p.Upgrades
	local v = type(upgrades) == "table" and upgrades[id]
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(v)
end

-- Cash and Bones price of the next level when the node is at `level`.
function T.Cost(id, level)
	local node = T.Nodes[id]
	if not node then
		return 0, 0
	end
	level = math.max(0, math.floor(level or 0))
	local cost = node.Cost
	local cash
	if node.Legacy then
		cash = math.floor(cost.Base * cost.Factor ^ level)
	else
		cash = nice(cost.Base * cost.Factor ^ level)
	end
	local bones = 0
	if cost.Bones then
		bones = nice(cost.Bones.Base * cost.Bones.Factor ^ level)
	end
	return cash, bones
end

-- Player level needed to buy the next level when the node is at `level`.
function T.Gate(id, level)
	local node = T.Nodes[id]
	if not node then
		return 1
	end
	level = math.max(0, math.floor(level or 0))
	return math.max(1, math.floor(node.Gate.Base + level * node.Gate.Step))
end

-- XP for reaching `newLevel` (the original upgrades keep 25 + 10 x level).
function T.XP(id, newLevel)
	local node = T.Nodes[id]
	local tier = node and not node.Legacy and node.Tier or 1
	return (25 + 10 * math.max(1, math.floor(newLevel or 1))) * tier
end

-- Total Cash and Bones to raise a node from level `from` to `to`.
function T.TotalCost(id, from, to)
	local cash, bones = 0, 0
	for level = from or 0, (to or 0) - 1 do
		local c, b = T.Cost(id, level)
		cash += c
		bones += b
	end
	return cash, bones
end

-- The numeric bonus of a node at `level` (fractions for percent / mult, units, dogs, stage index).
function T.Value(id, level)
	local node = T.Nodes[id]
	if not node then
		return 0
	end
	level = math.clamp(math.floor(level or 0), 0, node.Max)
	if node.Format == "count" then
		return math.min(Config.MaxDogs, 20 + node.PerLevel * level)
	elseif node.Format == "stage" then
		return math.clamp(1 + level, 1, #PlotCatalog.Stages)
	end
	return node.PerLevel * level
end

local function trim(s)
	s = string.gsub(s, "(%.%d-)0+$", "%1")
	return (string.gsub(s, "%.$", ""))
end
-- Shared number formatting of bonuses: "+12%", "+4.5%", "x1.25", "+50", "220".
function T.FormatValue(format, value)
	if format == "percent" then
		return "+" .. trim(string.format("%.1f", value * 100)) .. "%"
	elseif format == "mult" then
		return "x" .. trim(string.format("%.2f", 1 + value))
	elseif format == "units" then
		return "+" .. tostring(math.floor(value + 0.5))
	elseif format == "count" then
		return tostring(math.floor(value + 0.5))
	end
	return tostring(value)
end

-- The bonus text of a node at `level`: value text and the (English) stat label. Yard stages read as
-- the stage name.
function T.Text(id, level)
	local node = T.Nodes[id]
	if not node then
		return "", ""
	end
	local value = T.Value(id, level)
	if node.Format == "stage" then
		local stage = PlotCatalog.Stages[value]
		return stage and stage.Name or "", node.Label
	end
	return T.FormatValue(node.Format, value), node.Label
end

-- The yard stage a Plot level stands for (PlotCatalog.Stages row) and its kennel count.
function T.Stage(level)
	local index = math.clamp(1 + math.floor(level or 0), 1, #PlotCatalog.Stages)
	return PlotCatalog.Stages[index], index
end

-- What blocks the next level: {Kind="Max"} | {Kind="Level", Need, Have} | {Kind="Node", Node, Need, Have}.
-- Requirements are checked when buying only: levels already owned stay owned.
function T.Requirements(p, id)
	local node = T.Nodes[id]
	local rows = {}
	if not node then
		return rows
	end
	local level = T.Level(p, id)
	local playerLevel = type(p) == "table" and tonumber(p.Level) or 1
	table.insert(rows, { Kind = "Level", Need = T.Gate(id, level), Have = playerLevel, Met = playerLevel >= T.Gate(id, level) })
	local parents = {}
	for parent in pairs(node.Requires) do
		table.insert(parents, parent)
	end
	table.sort(parents, function(a, b)
		local ia, ib = T.BranchById[T.Nodes[a].Branch].Index, T.BranchById[T.Nodes[b].Branch].Index
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	for _, parent in ipairs(parents) do
		local have = T.Level(p, parent)
		table.insert(rows, { Kind = "Node", Node = parent, Need = node.Requires[parent], Have = have, Met = have >= node.Requires[parent] })
	end
	return rows
end

-- true when nothing but money stands between the player and the next level; otherwise false and the
-- server's message. The feature checks purchases with exactly this function.
function T.Check(p, id)
	local node = T.Nodes[id]
	if not node then
		return false, "Unknown upgrade"
	end
	local level = T.Level(p, id)
	if level >= node.Max then
		return false, "Already at maximum"
	end
	for _, row in ipairs(T.Requirements(p, id)) do
		if not row.Met then
			if row.Kind == "Level" then
				return false, "Reach level " .. row.Need .. " for this upgrade"
			end
			return false, "Requires " .. T.Nodes[row.Node].Name .. " level " .. row.Need
		end
	end
	return true, nil
end

-- "max" | "locked" (requirements missing) | "ready" (unlocked, not affordable) | "affordable".
function T.Status(p, id)
	local node = T.Nodes[id]
	if not node then
		return "locked"
	end
	local level = T.Level(p, id)
	if level >= node.Max then
		return "max"
	end
	if not T.Check(p, id) then
		return "locked"
	end
	local cash, bones = T.Cost(id, level)
	if (tonumber(p.Cash) or 0) >= cash and (tonumber(p.Bones) or 0) >= bones then
		return "affordable"
	end
	return "ready"
end

-- Pipeline totals of the tree for one profile: {[BonusesKey]=sum, MoneyMultFactor=product}.
function T.Totals(p)
	local totals = { MoneyMultFactor = 1 }
	for key in pairs(T.Stats) do
		totals[key] = 0
	end
	for _, id in ipairs(T.Order) do
		local node = T.Nodes[id]
		if node.Stat then
			local amount = T.Value(id, T.Level(p, id))
			if amount ~= 0 then
				totals[node.Stat] += amount
				if node.Stat == "MoneyMult" then
					totals.MoneyMultFactor *= 1 + amount
				end
			end
		end
	end
	return totals
end

-- The tree's whole effect for the "active bonuses" list: {Id, Label, Text, Active}. Combined rows
-- multiply the way the server applies them (Rules.Cooldown, Rules.RollMultiplier, Bonuses.ValueFactor).
function T.Summary(p)
	local t = T.Totals(p)
	local up = function(id)
		return T.Level(p, id)
	end
	local speed = (1 + legacyEffects.Dig * up("Dig")) * (1 + t.DigSpeed) - 1
	local estate = legacyEffects.Plot * up("Plot") + legacyEffects.Kennel * up("Kennel")
	local ability = legacyEffects.Ability * up("Ability")
	local value = (1 + estate) * (1 + ability) * (1 + t.Income) * t.MoneyMultFactor * (1 + t.DogPower)
	local stage, stageIndex = T.Stage(up("Plot"))
	local slots = legacyEffects.Storage * up("Storage") + t.Storage
	local rows = {
		{ Id = "Value", Label = "total dug value", Text = "x" .. trim(string.format("%.2f", value)), Active = value > 1.0001 },
		{ Id = "DigSpeed", Label = "dig speed", Text = T.FormatValue("percent", speed), Active = speed > 0 },
		{ Id = "Income", Label = "earnings", Text = T.FormatValue("percent", t.Income), Active = t.Income > 0 },
		{ Id = "MoneyMult", Label = "money multiplier", Text = "x" .. trim(string.format("%.3f", t.MoneyMultFactor)), Active = t.MoneyMultFactor > 1 },
		{ Id = "DogPower", Label = "dog power", Text = T.FormatValue("percent", t.DogPower), Active = t.DogPower > 0 },
		{ Id = "Estate", Label = "dug value (estate and kennels)", Text = T.FormatValue("percent", estate), Active = estate > 0 },
		{ Id = "Ability", Label = "dug value (ability power)", Text = T.FormatValue("percent", ability), Active = ability > 0 },
		{ Id = "Luck", Label = "rare loot luck", Text = T.FormatValue("percent", t.Luck), Active = t.Luck > 0 },
		{ Id = "RareFind", Label = "rare find chance", Text = T.FormatValue("percent", t.RareFind), Active = t.RareFind > 0 },
		{ Id = "ItemMutation", Label = "find mutation chance", Text = T.FormatValue("percent", t.ItemMutation), Active = t.ItemMutation > 0 },
		{ Id = "Storage", Label = "discovery slots", Text = T.FormatValue("units", slots), Active = slots > 0 },
		{ Id = "DogStorage", Label = "dog capacity", Text = tostring(T.Value("DogStorage", up("DogStorage"))), Active = up("DogStorage") > 0 },
		{ Id = "Plot", Label = "yard stage", Text = stage.Name, Active = stageIndex > 1, Stage = stageIndex, Kennels = stage.Slots },
		{ Id = "Offline", Label = "offline earnings", Text = T.FormatValue("percent", t.Offline), Active = t.Offline > 0 },
		{ Id = "XP", Label = "XP gain", Text = T.FormatValue("percent", t.XP), Active = t.XP > 0 },
		{ Id = "DogMutation", Label = "mutated dog chance", Text = T.FormatValue("percent", t.DogMutation), Active = t.DogMutation > 0 },
		{ Id = "Strength", Label = "mining strength", Text = T.FormatValue("units", t.Strength), Active = t.Strength > 0 },
	}
	return rows
end

-- Mining Strength from the STRENGTH branch (added to the Strength a player trained before the branch existed).
function T.Strength(p)
	local total = 0
	for _, id in ipairs(T.Order) do
		local node = T.Nodes[id]
		if node.Stat == "Strength" then
			total += T.Value(id, T.Level(p, id))
		end
	end
	return total
end

-- Bought levels and all levels of the tree (progress bar).
function T.Progress(p)
	local owned, total = 0, 0
	for _, id in ipairs(T.Order) do
		local node = T.Nodes[id]
		owned += math.min(node.Max, T.Level(p, id))
		total += node.Max
	end
	return owned, total
end

-- A saved level that a known node can hold (Validate) / the healed value (Normalize).
function T.ValidLevel(id, value)
	local node = T.Nodes[id]
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 then
		return false
	end
	return node == nil or value <= node.Max
end

return T
