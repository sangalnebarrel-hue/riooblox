-- Player titles (shown above the character, docs/TITLES.md). Shared by the server feature
-- (ServerScriptService.Economy.Features.Titles unlocks and equips them), the title window
-- (Modules.TitlesScreen) and the billboard renderer (ReplicatedStorage.TitleBadge).
--
-- A title definition:
--   Id        stable key saved in p.Titles.Unlocked / p.Titles.Equipped (never rename one)
--   Text, RU  the title in English and Russian (shown upper-case)
--   Icon      an emoji shown before the text
--   Rarity    Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret (styling and sort order)
--   Color     one colour (Common..Rare) or Gradient = {Color3, ...} (Epic and above)
--   Category  one of Titles.Categories
--   Stat, Target  unlocked when Titles.Stats[Stat](profile) >= Target (existing saved stats only,
--             plus the counters the Titles feature keeps in p.Titles.Counters)
--   How, HowRU    how to get it (the locked card shows this and a progress bar)
--   Hidden    Secret titles show "???" until unlocked
-- Legacy titles: every p.Cosmetics key a player already owns (Dogdex, set, collection, finds,
-- prestige and event titles, paid kennel cosmetics) is a title too: id "legacy:<key>" (Titles.Legacy).
local RS = game:GetService("ReplicatedStorage")
local Economy = RS:WaitForChild("DogEconomy")
local DexRewards = require(Economy:WaitForChild("DexRewards"))
local DogDefs = require(Economy:WaitForChild("DogDefinitions"))
local ItemDefs = require(Economy:WaitForChild("ItemDefinitions"))
local SetDefs = require(Economy:WaitForChild("SetDefinitions"))
local ValueConfig = require(RS:WaitForChild("ItemValueConfig"))

local Titles = {}
Titles.Version = 1
Titles.LegacyPrefix = "legacy:"

local C = Color3.fromRGB

Titles.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Titles.RarityRank = {}
for i, name in ipairs(Titles.Rarities) do
	Titles.RarityRank[name] = i
end
Titles.RarityRU = {
	Common = "ОБЫЧНЫЙ",
	Uncommon = "НЕОБЫЧНЫЙ",
	Rare = "РЕДКИЙ",
	Epic = "ЭПИЧЕСКИЙ",
	Legendary = "ЛЕГЕНДАРНЫЙ",
	Mythic = "МИФИЧЕСКИЙ",
	Secret = "СЕКРЕТНЫЙ",
}

-- How each rarity is drawn (TitleBadge): plate transparency, a glow stroke, a gradient, an
-- animated shimmer and sparkles. Colours of the plate border follow the Kit rarity palette.
Titles.Styles = {
	Common = { Plate = 0.6, Border = nil, Glow = false, Gradient = false, Animated = false, Sparkle = false },
	Uncommon = { Plate = 0.55, Border = C(125, 219, 48), Glow = false, Gradient = false, Animated = false, Sparkle = false },
	Rare = { Plate = 0.5, Border = C(38, 164, 243), Glow = true, Gradient = false, Animated = false, Sparkle = false },
	Epic = { Plate = 0.45, Border = C(161, 103, 242), Glow = true, Gradient = true, Animated = false, Sparkle = false },
	Legendary = { Plate = 0.4, Border = C(249, 180, 35), Glow = true, Gradient = true, Animated = true, Sparkle = false },
	Mythic = { Plate = 0.35, Border = C(247, 73, 112), Glow = true, Gradient = true, Animated = true, Sparkle = true },
	Secret = { Plate = 0.25, Border = C(230, 115, 245), Glow = true, Gradient = true, Animated = true, Sparkle = true, Dark = true },
}

Titles.Categories = {
	{ Id = "Digging", Text = "DIGGING", RU = "РАСКОПКИ", Icon = "🔍" },
	{ Id = "Depths", Text = "DEPTHS", RU = "ГЛУБИНЫ", Icon = "🌋" },
	{ Id = "Dogs", Text = "DOGS", RU = "СОБАКИ", Icon = "🐕" },
	{ Id = "Mining", Text = "MINING", RU = "ШАХТА", Icon = "⛏️" },
	{ Id = "Lab", Text = "LAB", RU = "ЛАБОРАТОРИЯ", Icon = "🧬" },
	{ Id = "Social", Text = "SOCIAL", RU = "ОБЩЕНИЕ", Icon = "🤝" },
	{ Id = "Wealth", Text = "WEALTH", RU = "БОГАТСТВО", Icon = "💰" },
	{ Id = "Progress", Text = "PROGRESS", RU = "ПРОГРЕСС", Icon = "⏳" },
	{ Id = "Events", Text = "EVENTS", RU = "СОБЫТИЯ", Icon = "🎉" },
	{ Id = "Legacy", Text = "COLLECTION", RU = "КОЛЛЕКЦИЯ", Icon = "📜" },
}
Titles.CategoryById = {}
for _, cat in ipairs(Titles.Categories) do
	Titles.CategoryById[cat.Id] = cat
end

local function grad(...)
	return { ... }
end

-- stylua: ignore
Titles.List = {
	-- Digging
	{ Id = "FirstFind", Icon = "🔍", Text = "FIRST FIND", RU = "ПЕРВАЯ НАХОДКА", Rarity = "Common", Category = "Digging",
		Stat = "Finds", Target = 1, Color = C(232, 238, 246), How = "Find your first treasure", HowRU = "Найди первое сокровище" },
	{ Id = "TreasureSeeker", Icon = "🗺️", Text = "TREASURE SEEKER", RU = "ИСКАТЕЛЬ СОКРОВИЩ", Rarity = "Uncommon", Category = "Digging",
		Stat = "Finds", Target = 50, Color = C(160, 232, 112), How = "Find 50 treasures", HowRU = "Найди 50 сокровищ" },
	{ Id = "TreasureHunter", Icon = "💎", Text = "TREASURE HUNTER", RU = "ОХОТНИК ЗА СОКРОВИЩАМИ", Rarity = "Rare", Category = "Digging",
		Stat = "Finds", Target = 500, Color = C(104, 200, 255), How = "Find 500 treasures", HowRU = "Найди 500 сокровищ" },
	{ Id = "Heavyweight", Icon = "🏋️", Text = "HEAVYWEIGHT", RU = "ТЯЖЕЛОВЕС", Rarity = "Rare", Category = "Digging",
		Stat = "HeavyFinds", Target = 15, Color = C(255, 170, 84), How = "Find 15 different treasures of HEAVY size or bigger", HowRU = "Найди 15 разных сокровищ размера HEAVY и больше" },
	{ Id = "RelicHunter", Icon = "🏺", Text = "RELIC HUNTER", RU = "ОХОТНИК ЗА РЕЛИКВИЯМИ", Rarity = "Epic", Category = "Digging",
		Stat = "Finds", Target = 2500, Gradient = grad(C(196, 132, 255), C(255, 128, 214)), How = "Find 2,500 treasures", HowRU = "Найди 2 500 сокровищ" },
	{ Id = "LegendaryDigger", Icon = "🏆", Text = "LEGENDARY DIGGER", RU = "ЛЕГЕНДАРНЫЙ КОПАТЕЛЬ", Rarity = "Legendary", Category = "Digging",
		Stat = "LegendaryFinds", Target = 10, Gradient = grad(C(255, 226, 120), C(255, 170, 40), C(255, 236, 160)), How = "Find 10 Legendary or Secret treasures", HowRU = "Найди 10 легендарных или секретных сокровищ" },
	{ Id = "SecretKeeper", Icon = "🗝️", Text = "SECRET KEEPER", RU = "ХРАНИТЕЛЬ ТАЙН", Rarity = "Mythic", Category = "Digging",
		Stat = "SecretFinds", Target = 1, Gradient = grad(C(255, 110, 170), C(170, 110, 255), C(110, 220, 255)), How = "Find a Secret treasure", HowRU = "Найди секретное сокровище" },
	-- Depths
	{ Id = "CaveExplorer", Icon = "🦇", Text = "CAVE EXPLORER", RU = "ИССЛЕДОВАТЕЛЬ ПЕЩЕР", Rarity = "Uncommon", Category = "Depths",
		Stat = "Depth", Target = 2, Color = C(214, 178, 130), How = "Unlock the Caverns", HowRU = "Открой Пещеры" },
	{ Id = "RuinRaider", Icon = "🏛️", Text = "RUIN RAIDER", RU = "РАСХИТИТЕЛЬ РУИН", Rarity = "Rare", Category = "Depths",
		Stat = "Depth", Target = 3, Color = C(96, 214, 240), How = "Unlock the Ancient Ruins", HowRU = "Открой Древние руины" },
	{ Id = "DeepDigger", Icon = "🌋", Text = "DEEP DIGGER", RU = "ГЛУБИННЫЙ КОПАТЕЛЬ", Rarity = "Epic", Category = "Depths",
		Stat = "Depth", Target = 4, Gradient = grad(C(255, 120, 60), C(200, 70, 220)), How = "Reach the Cursed Depths", HowRU = "Доберись до Проклятых глубин" },
	{ Id = "VoidWalker", Icon = "🌌", Text = "VOID WALKER", RU = "СТРАННИК ПУСТОТЫ", Rarity = "Legendary", Category = "Depths",
		Stat = "Depth", Target = 5, Gradient = grad(C(150, 90, 255), C(80, 200, 255), C(200, 140, 255)), How = "Reach THE VOID", HowRU = "Доберись до ПУСТОТЫ" },
	-- Dogs
	{ Id = "DogFriend", Icon = "🐶", Text = "DOG FRIEND", RU = "ДРУГ СОБАК", Rarity = "Common", Category = "Dogs",
		Stat = "Dogs", Target = 1, Color = C(255, 226, 186), How = "Adopt your first dog", HowRU = "Заведи первую собаку" },
	{ Id = "ShinyHunter", Icon = "✨", Text = "SHINY HUNTER", RU = "ОХОТНИК ЗА СИЯНИЕМ", Rarity = "Rare", Category = "Dogs",
		Stat = "Variants", Target = 10, Color = C(190, 236, 255), How = "Own 10 dogs with a rare variant (Shiny, Golden and up)", HowRU = "Получи 10 собак с редким вариантом (Shiny, Golden и выше)" },
	{ Id = "DogMaster", Icon = "🐕", Text = "DOG MASTER", RU = "ПОВЕЛИТЕЛЬ СОБАК", Rarity = "Rare", Category = "Dogs",
		Stat = "Dogdex", Target = 25, Color = C(120, 196, 255), How = "Discover 25 dogs in the Dogdex", HowRU = "Открой 25 собак в Догдексе" },
	{ Id = "Collector", Icon = "📚", Text = "COLLECTOR", RU = "КОЛЛЕКЦИОНЕР", Rarity = "Epic", Category = "Dogs",
		Stat = "Dogdex", Target = 50, Gradient = grad(C(130, 170, 255), C(196, 120, 255)), How = "Discover 50 dogs in the Dogdex", HowRU = "Открой 50 собак в Догдексе" },
	{ Id = "PackLeader", Icon = "🐺", Text = "PACK LEADER", RU = "ВОЖАК СТАИ", Rarity = "Epic", Category = "Dogs",
		Stat = "Dogs", Target = 40, Gradient = grad(C(170, 190, 220), C(110, 140, 255)), How = "Own 40 dogs at once", HowRU = "Владей 40 собаками одновременно" },
	{ Id = "LivingDogdex", Icon = "🏅", Text = "LIVING DOGDEX", RU = "ЖИВОЙ ДОГДЕКС", Rarity = "Mythic", Category = "Dogs",
		Stat = "Dogdex", Target = 100, Gradient = grad(C(255, 214, 92), C(255, 104, 139), C(120, 160, 255)), How = "Discover all 100 dogs", HowRU = "Открой все 100 собак" },
	{ Id = "VoidTamer", Icon = "🕳️", Text = "VOID TAMER", RU = "УКРОТИТЕЛЬ ПУСТОТЫ", Rarity = "Secret", Category = "Dogs", Hidden = true,
		Stat = "VoidDogs", Target = 1, Gradient = grad(C(120, 70, 220), C(30, 10, 60), C(200, 120, 255)), How = "Own a Void dog", HowRU = "Получи собаку варианта Void" },
	-- Mining
	{ Id = "RockBreaker", Icon = "⛏️", Text = "ROCK BREAKER", RU = "КРУШИТЕЛЬ КАМНЯ", Rarity = "Uncommon", Category = "Mining",
		Stat = "Ores", Target = 100, Color = C(196, 210, 222), How = "Break 100 ores at your Mining Corner", HowRU = "Разбей 100 руд в своей шахте" },
	{ Id = "Stonemason", Icon = "🪨", Text = "STONEMASON", RU = "КАМЕНЩИК", Rarity = "Rare", Category = "Mining",
		Stat = "Stone", Target = 1000, Color = C(206, 196, 180), How = "Collect 1,000 stone", HowRU = "Добудь 1 000 камня" },
	{ Id = "OreBaron", Icon = "💠", Text = "ORE BARON", RU = "РУДНЫЙ БАРОН", Rarity = "Epic", Category = "Mining",
		Stat = "Ores", Target = 2500, Gradient = grad(C(110, 230, 255), C(150, 120, 255)), How = "Break 2,500 ores", HowRU = "Разбей 2 500 руд" },
	-- Lab
	{ Id = "LabAssistant", Icon = "🧪", Text = "LAB ASSISTANT", RU = "ЛАБОРАНТ", Rarity = "Uncommon", Category = "Lab",
		Stat = "Lab", Target = 1, Color = C(150, 240, 190), How = "Run your first lab experiment", HowRU = "Проведи первый опыт в лаборатории" },
	{ Id = "MadScientist", Icon = "🧬", Text = "MAD SCIENTIST", RU = "БЕЗУМНЫЙ УЧЁНЫЙ", Rarity = "Epic", Category = "Lab",
		Stat = "Lab", Target = 25, Gradient = grad(C(120, 255, 150), C(170, 90, 255)), How = "Run 25 lab experiments", HowRU = "Проведи 25 опытов в лаборатории" },
	-- Social
	{ Id = "Trader", Icon = "🤝", Text = "TRADER", RU = "ТОРГОВЕЦ", Rarity = "Uncommon", Category = "Social",
		Stat = "Trades", Target = 3, Color = C(130, 230, 200), How = "Complete 3 trades", HowRU = "Заверши 3 обмена" },
	{ Id = "MasterTrader", Icon = "💼", Text = "MASTER TRADER", RU = "МАСТЕР ОБМЕНА", Rarity = "Epic", Category = "Social",
		Stat = "Trades", Target = 50, Gradient = grad(C(90, 230, 190), C(80, 150, 255)), How = "Complete 50 trades", HowRU = "Заверши 50 обменов" },
	-- Wealth
	{ Id = "Millionaire", Icon = "💰", Text = "MILLIONAIRE", RU = "МИЛЛИОНЕР", Rarity = "Rare", Category = "Wealth",
		Stat = "Coins", Target = 1e6, Format = "coins", Color = C(255, 214, 90), How = "Earn 1M coins in total", HowRU = "Заработай 1M монет за всё время" },
	{ Id = "Billionaire", Icon = "🤑", Text = "BILLIONAIRE", RU = "МИЛЛИАРДЕР", Rarity = "Legendary", Category = "Wealth",
		Stat = "Coins", Target = 1e9, Format = "coins", Gradient = grad(C(255, 236, 140), C(120, 220, 90), C(255, 200, 60)), How = "Earn 1B coins in total", HowRU = "Заработай 1B монет за всё время" },
	{ Id = "Tycoon", Icon = "🏦", Text = "TYCOON", RU = "МАГНАТ", Rarity = "Mythic", Category = "Wealth",
		Stat = "Coins", Target = 1e12, Format = "coins", Gradient = grad(C(255, 220, 110), C(255, 120, 160), C(255, 250, 220)), How = "Earn 1T coins in total", HowRU = "Заработай 1T монет за всё время" },
	-- Progress
	{ Id = "Veteran", Icon = "⏳", Text = "VETERAN", RU = "ВЕТЕРАН", Rarity = "Rare", Category = "Progress",
		Stat = "Playtime", Target = 86400, Format = "hours", Color = C(150, 200, 255), How = "Play for 24 hours in total", HowRU = "Проведи в игре 24 часа" },
	{ Id = "Prestige", Icon = "👑", Text = "PRESTIGE", RU = "ПРЕСТИЖ", Rarity = "Epic", Category = "Progress",
		Stat = "Prestige", Target = 1, Gradient = grad(C(255, 214, 92), C(255, 140, 60)), How = "Reach Prestige 1", HowRU = "Получи Престиж 1" },
	{ Id = "OldTimer", Icon = "🕰️", Text = "OLD TIMER", RU = "СТАРОЖИЛ", Rarity = "Legendary", Category = "Progress",
		Stat = "Playtime", Target = 360000, Format = "hours", Gradient = grad(C(255, 220, 160), C(210, 150, 90), C(255, 236, 200)), How = "Play for 100 hours in total", HowRU = "Проведи в игре 100 часов" },
	{ Id = "Ascended", Icon = "🌟", Text = "ASCENDED", RU = "ВОЗНЕСЁННЫЙ", Rarity = "Mythic", Category = "Progress",
		Stat = "Prestige", Target = 3, Gradient = grad(C(255, 250, 200), C(255, 170, 230), C(170, 220, 255)), How = "Reach Prestige 3", HowRU = "Получи Престиж 3" },
	-- Events
	{ Id = "DogWrangler", Icon = "🐾", Text = "DOG WRANGLER", RU = "ЛОВЕЦ ЩЕНКОВ", Rarity = "Uncommon", Category = "Events",
		Stat = "Pups", Target = 10, Color = C(255, 206, 120), How = "Catch 10 runaway pups during DOG RUSH", HowRU = "Поймай 10 сбежавших щенков во время СОБАЧЬЕГО ЗАБЕГА" },
	{ Id = "StormChaser", Icon = "🌩️", Text = "STORM CHASER", RU = "ОХОТНИК ЗА БУРЯМИ", Rarity = "Rare", Category = "Events",
		Stat = "Events", Target = 6, Color = C(140, 210, 255), How = "Witness 6 different world events", HowRU = "Застань 6 разных мировых событий" },
	{ Id = "PupHerder", Icon = "🐾", Text = "PUP HERDER", RU = "ПАСТУХ ЩЕНКОВ", Rarity = "Epic", Category = "Events",
		Stat = "Pups", Target = 50, Gradient = grad(C(255, 200, 110), C(255, 130, 90)), How = "Catch 50 runaway pups during DOG RUSH", HowRU = "Поймай 50 сбежавших щенков во время СОБАЧЬЕГО ЗАБЕГА" },
	{ Id = "StampedeKing", Icon = "🐾", Text = "STAMPEDE KING", RU = "КОРОЛЬ ЗАБЕГА", Rarity = "Legendary", Category = "Events",
		Stat = "Pups", Target = 200, Gradient = grad(C(255, 230, 120), C(255, 150, 50), C(255, 245, 190)), How = "Catch 200 runaway pups during DOG RUSH", HowRU = "Поймай 200 сбежавших щенков во время СОБАЧЬЕГО ЗАБЕГА" },
	{ Id = "NullWitness", Icon = "❓", Text = "NULL WITNESS", RU = "СВИДЕТЕЛЬ NULL", Rarity = "Secret", Category = "Events", Hidden = true,
		Stat = "NullHour", Target = 1, Gradient = grad(C(200, 190, 210), C(90, 80, 110), C(255, 60, 120)), How = "Witness the NULL HOUR", HowRU = "Застань NULL HOUR" },
}

Titles.ById = {}
for index, def in ipairs(Titles.List) do
	def.Order = index
	Titles.ById[def.Id] = def
end

------------------------------------------------------------------------------------------------
-- Stats: pure, nil-safe readers of saved data. c = p.Titles.Counters (may be nil).
------------------------------------------------------------------------------------------------
local function tbl(v: any): { [any]: any }
	return type(v) == "table" and v or {}
end
local function num(v: any): number
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end
local function count(t: any): number
	local n = 0
	for _, v in pairs(tbl(t)) do
		if v then
			n += 1
		end
	end
	return n
end

-- Legendary or Secret items (ItemValueConfig rarity by drop chance), by item id.
local LEGENDARY_ITEMS = {}
do
	local limit = 0.0001
	for _, row in ipairs(ValueConfig.Rarity or {}) do
		if row.Name == "Legendary" then
			limit = row.MaxChance
		end
	end
	for id, def in pairs(ItemDefs) do
		if type(def) == "table" and tonumber(def.BaseDropChance) and def.BaseDropChance <= limit then
			LEGENDARY_ITEMS[id] = true
		end
	end
end
Titles.LegendaryItems = LEGENDARY_ITEMS
function Titles.IsLegendaryItem(itemId: any): boolean
	return type(itemId) == "string" and LEGENDARY_ITEMS[itemId] == true
end
function Titles.LegendaryCollected(p: any): number
	local n = 0
	for id, known in pairs(tbl(type(p) == "table" and p.Collection)) do
		if known and LEGENDARY_ITEMS[id] then
			n += 1
		end
	end
	return n
end

function Titles.MuseumCount(p: any): number
	local n = 0
	for id, known in pairs(tbl(p.DogDex)) do
		local def = DogDefs[id]
		if known == true and type(def) == "table" and not def.MuseumExcluded and (def.Index or 0) >= 1 and (def.Index or 0) <= 100 then
			n += 1
		end
	end
	return n
end

local function deepest(p: any): number
	local layers = tbl(p.UnlockedLayers)
	local n = 1
	for i = 1, 5 do
		if layers[tostring(i)] then
			n = i
		else
			break
		end
	end
	return n
end

Titles.Stats = {
	Finds = function(p)
		return num(tbl(p.Stats).TotalFinds)
	end,
	SecretFinds = function(p)
		return num(tbl(p.Stats).SecretFinds)
	end,
	LegendaryFinds = function(p, c)
		return math.max(Titles.LegendaryCollected(p), num(tbl(c).LegendaryFinds))
	end,
	HeavyFinds = function(p)
		return count(p.HeavyCollection)
	end,
	Depth = deepest,
	Dogs = function(p)
		return count(p.Dogs)
	end,
	Dogdex = function(p)
		return Titles.MuseumCount(p)
	end,
	Variants = function(p)
		local n = 0
		for _, seen in pairs(tbl(p.VariantDex)) do
			for variant, on in pairs(tbl(seen)) do
				if on == true and variant ~= "Normal" then
					n += 1
				end
			end
		end
		return n
	end,
	VoidDogs = function(p)
		for _, seen in pairs(tbl(p.VariantDex)) do
			if tbl(seen).Void == true then
				return 1
			end
		end
		return 0
	end,
	Ores = function(p)
		local m = tbl(p.Mining)
		local total = 0
		for _, n in pairs(tbl(m.Collection)) do
			total += math.max(0, num(n))
		end
		return math.max(num(m.OresBroken), total)
	end,
	Stone = function(p, c)
		return num(tbl(c).Stone)
	end,
	Lab = function(p)
		return num(tbl(p.Lab).Experiments)
	end,
	Trades = function(p)
		return num(tbl(p.Stats).CompletedTrades)
	end,
	Coins = function(p)
		return num(tbl(p.Lifetime).TotalCoinsEarned)
	end,
	Playtime = function(p)
		return num(tbl(p.Lifetime).TotalPlaytimeSeconds)
	end,
	Prestige = function(p)
		return num(p.Prestige)
	end,
	Pups = function(p)
		return num(tbl(p.DogRush).Lifetime)
	end,
	Events = function(p)
		return count(p.WorldEventsSeen)
	end,
	NullHour = function(p)
		return tbl(p.WorldEventsSeen).NULL_HOUR and 1 or 0
	end,
}

-- A context memoizes every stat once per evaluation pass (several titles share a stat).
function Titles.Context(p: any, counters: any): any
	return { P = type(p) == "table" and p or {}, C = counters, Memo = {} }
end
function Titles.Value(def: any, ctx: any): number
	local stat = def and def.Stat
	local fn = stat and Titles.Stats[stat]
	if not fn then
		return 0
	end
	local memo = ctx.Memo
	local v = memo[stat]
	if v == nil then
		local ok, result = pcall(fn, ctx.P, ctx.C)
		v = ok and num(result) or 0
		memo[stat] = v
	end
	return v
end
-- value, target (both numbers); legacy titles have no progress (owned = 1 / 1).
function Titles.Progress(def: any, ctx: any): (number, number)
	if not def then
		return 0, 1
	end
	if def.Legacy then
		local owned = tbl(ctx.P.Cosmetics)[def.Key] == true
		return owned and 1 or 0, 1
	end
	return Titles.Value(def, ctx), def.Target or 1
end
function Titles.Met(def: any, ctx: any): boolean
	local value, target = Titles.Progress(def, ctx)
	return value >= target
end

------------------------------------------------------------------------------------------------
-- Legacy cosmetic titles (p.Cosmetics keys)
------------------------------------------------------------------------------------------------
-- stylua: ignore
local LEGACY_FIXED = {
	GoldenKennel = { Text = "GOLDEN KENNEL", RU = "ЗОЛОТАЯ БУДКА", Icon = "🏠", Rarity = "Legendary", Gradient = grad(C(255, 226, 120), C(230, 150, 30), C(255, 240, 180)) },
	CyberKennel = { Text = "CYBER KENNEL", RU = "КИБЕРБУДКА", Icon = "🤖", Rarity = "Epic", Gradient = grad(C(60, 240, 220), C(90, 140, 255)) },
	VoidAura = { Text = "VOID AURA", RU = "АУРА ПУСТОТЫ", Icon = "🌀", Rarity = "Mythic", Gradient = grad(C(140, 80, 230), C(60, 30, 120), C(200, 140, 255)) },
	FounderPlaque = { Text = "FOUNDER", RU = "ОСНОВАТЕЛЬ", Icon = "🪧", Rarity = "Legendary", Gradient = grad(C(255, 240, 200), C(214, 168, 90), C(255, 250, 230)) },
	SupporterTitle = { Text = "SUPPORTER", RU = "СПОНСОР", Icon = "⭐", Rarity = "Legendary", Gradient = grad(C(255, 236, 120), C(255, 170, 60), C(255, 250, 200)) },
	EventSupporter = { Text = "EVENT SUPPORTER", RU = "СПОНСОР СОБЫТИЙ", Icon = "🎗️", Rarity = "Epic", Gradient = grad(C(255, 150, 190), C(160, 120, 255)) },
}
local DEX_RU = {
	["DOG SPOTTER"] = "ЗНАТОК СОБАК",
	["DOG COLLECTOR"] = "КОЛЛЕКЦИОНЕР СОБАК",
	["DOGDEX EXPERT"] = "ЭКСПЕРТ ДОГДЕКСА",
	["DOG SCHOLAR"] = "СОБАКОВЕД",
	["DOG LEGEND"] = "СОБАЧЬЯ ЛЕГЕНДА",
	["DOGDEX MASTER"] = "МАСТЕР ДОГДЕКСА",
}
local DOG_SET_RU = { Explorers = "ИССЛЕДОВАТЕЛИ", Food = "ВКУСНЯШКИ", Cyber = "КИБЕР", Cosmic = "КОСМОС", Undead = "НЕЖИТЬ" }
local ITEM_SET_RU = {
	["BURIED JUNK"] = "ЗАКОПАННЫЙ МУСОР",
	["DOG TREASURES"] = "СОБАЧЬИ СОКРОВИЩА",
	["LOST & FOUND"] = "БЮРО НАХОДОК",
	["CHILDHOOD CACHE"] = "ДЕТСКИЙ ТАЙНИК",
	["CRYSTAL VEIN"] = "КРИСТАЛЬНАЯ ЖИЛА",
	["ANCIENT MINER"] = "ДРЕВНИЙ ШАХТЁР",
	["FOSSIL HUNTER"] = "ОХОТНИК ЗА ОКАМЕНЕЛОСТЯМИ",
	["KNIGHT'S REMAINS"] = "ОСТАНКИ РЫЦАРЯ",
	["ANCIENT EGYPT"] = "ДРЕВНИЙ ЕГИПЕТ",
	["TEMPLE RELICS"] = "РЕЛИКВИИ ХРАМА",
	["FORGOTTEN KING"] = "ЗАБЫТЫЙ КОРОЛЬ",
	["DEMON REMAINS"] = "ОСТАНКИ ДЕМОНА",
	["CURSED KING"] = "ПРОКЛЯТЫЙ КОРОЛЬ",
	["SOUL CABINET"] = "ШКАФ ДУШ",
	["VOID RELICS"] = "РЕЛИКВИИ ПУСТОТЫ",
	["REALITY BREAKDOWN"] = "РАСПАД РЕАЛЬНОСТИ",
	["ALIEN CONTACT"] = "КОНТАКТ С ПРИШЕЛЬЦАМИ",
	["COSMIC COLLAPSE"] = "КОСМИЧЕСКИЙ КОЛЛАПС",
}
Titles.LegacyRU = { Dex = DEX_RU, DogSets = DOG_SET_RU, ItemSets = ITEM_SET_RU }

local RARITY_COLOR = {
	Common = C(232, 238, 246),
	Uncommon = C(160, 232, 112),
	Rare = C(104, 200, 255),
}
local RARITY_GRADIENT = {
	Epic = grad(C(196, 132, 255), C(140, 110, 255)),
	Legendary = grad(C(255, 226, 120), C(245, 152, 25), C(255, 236, 160)),
	Mythic = grad(C(255, 104, 139), C(214, 44, 98), C(255, 170, 200)),
	Secret = grad(C(244, 140, 255), C(120, 92, 255), C(230, 200, 255)),
}
local function byCount(n: number, steps: { { number } }, names: { string }): string
	for i = #steps, 1, -1 do
		if n >= steps[i][1] then
			return names[i]
		end
	end
	return names[1]
end
local function legacyRow(key: string): any
	local fixed = LEGACY_FIXED[key]
	if fixed then
		return table.clone(fixed)
	end
	local dex = string.match(key, "^Dex(%d+)$")
	if dex then
		local n = tonumber(dex) or 0
		local name = DexRewards.TitleName(key) or ("DOGDEX " .. n)
		return {
			Text = name,
			RU = DEX_RU[name] or ("ДОГДЕКС " .. n),
			Icon = "📖",
			Rarity = byCount(n, { { 0 }, { 25 }, { 50 }, { 90 }, { 100 } }, { "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }),
		}
	end
	local finds = string.match(key, "^Finds(%d+)$")
	if finds then
		local n = tonumber(finds) or 0
		return {
			Text = n .. " FINDS",
			RU = n .. " НАХОДОК",
			Icon = "🔎",
			Rarity = byCount(n, { { 0 }, { 100 }, { 250 }, { 1000 }, { 2500 } }, { "Common", "Uncommon", "Rare", "Epic", "Legendary" }),
		}
	end
	local prestige = string.match(key, "^Prestige(%d+)$")
	if prestige then
		local n = tonumber(prestige) or 1
		return { Text = "PRESTIGE " .. n, RU = "ПРЕСТИЖ " .. n, Icon = "👑", Rarity = byCount(n, { { 0 }, { 3 }, { 5 } }, { "Epic", "Legendary", "Mythic" }) }
	end
	local event = string.match(key, "^Event(%d+)$")
	if event then
		local n = tonumber(event) or 1
		return {
			Text = "GLOBAL DIG HERO " .. n,
			RU = "ГЕРОЙ ГЛОБАЛЬНЫХ РАСКОПОК " .. n,
			Icon = "🎉",
			Rarity = byCount(n, { { 0 }, { 2 }, { 3 }, { 4 }, { 5 } }, { "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }),
		}
	end
	local setId, kind = string.match(key, "^Discovery:([%w_]+):(%a+)$")
	if setId and (kind == "Normal" or kind == "Heavy") then
		local set = SetDefs[setId]
		local name = type(set) == "table" and set.Name or (string.gsub(setId, "_", " "))
		local ru = ITEM_SET_RU[name] or name
		if kind == "Heavy" then
			return { Text = "HEAVY " .. name, RU = "ТЯЖЁЛЫЙ НАБОР: " .. ru, Icon = "🏺", Rarity = "Epic" }
		end
		return { Text = name, RU = ru, Icon = "🏺", Rarity = "Rare" }
	end
	local dogSet = string.match(key, "^Set(%a+)$")
	if dogSet then
		local upper = string.upper(dogSet)
		return { Text = upper .. " SET", RU = "НАБОР: " .. (DOG_SET_RU[dogSet] or upper), Icon = "🧩", Rarity = "Rare" }
	end
	-- Anything else a player owns stays a (plain) title.
	if #key <= 60 and string.match(key, "^[%w_:%-]+$") then
		local spaced = string.upper((string.gsub(string.gsub(key, "(%l)(%u)", "%1 %2"), "[_:]", " ")))
		return { Text = spaced, RU = spaced, Icon = "🏷️", Rarity = "Common" }
	end
	return nil
end

local legacyCache: { [string]: any } = {}
local legacyCount = 0
function Titles.Legacy(key: any): any
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local hit = legacyCache[key]
	if hit ~= nil then
		return hit or nil
	end
	local row = legacyRow(key)
	if row then
		row.Id = Titles.LegacyPrefix .. key
		row.Key = key
		row.Legacy = true
		row.Category = "Legacy"
		row.Order = 1000
		if not row.Color and not row.Gradient then
			if RARITY_GRADIENT[row.Rarity] then
				row.Gradient = RARITY_GRADIENT[row.Rarity]
			else
				row.Color = RARITY_COLOR[row.Rarity] or RARITY_COLOR.Common
			end
		end
		row.How = "An earlier achievement title"
		row.HowRU = "Титул за прошлое достижение"
	end
	if legacyCount > 400 then
		table.clear(legacyCache)
		legacyCount = 0
	end
	legacyCount += 1
	legacyCache[key] = row or false
	return row
end
function Titles.LegacyId(key: string): string
	return Titles.LegacyPrefix .. key
end

-- Any title id (regular or "legacy:<key>").
function Titles.Get(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	local def = Titles.ById[id]
	if def then
		return def
	end
	local prefix = Titles.LegacyPrefix
	if string.sub(id, 1, #prefix) == prefix then
		return Titles.Legacy(string.sub(id, #prefix + 1))
	end
	return nil
end

-- Legacy title ids the profile owns (p.Cosmetics true entries that map to a title).
function Titles.OwnedLegacy(p: any): { string }
	local out = {}
	for key, owned in pairs(tbl(type(p) == "table" and p.Cosmetics)) do
		if owned == true and type(key) == "string" and Titles.Legacy(key) then
			table.insert(out, Titles.LegacyPrefix .. key)
		end
	end
	table.sort(out)
	return out
end

------------------------------------------------------------------------------------------------
-- Presentation helpers (client)
------------------------------------------------------------------------------------------------
function Titles.Text(def: any, lang: string?): string
	if not def then
		return ""
	end
	return (lang == "ru" and def.RU) or def.Text or def.Id
end
function Titles.How(def: any, lang: string?): string
	if not def then
		return ""
	end
	return (lang == "ru" and def.HowRU) or def.How or ""
end
function Titles.RarityText(rarity: string?, lang: string?): string
	if lang == "ru" then
		return Titles.RarityRU[rarity or ""] or string.upper(rarity or "")
	end
	return string.upper(rarity or "")
end
-- The colours of a title: one colour, or two or more for a gradient.
function Titles.Colors(def: any): { Color3 }
	if def and type(def.Gradient) == "table" and #def.Gradient >= 2 then
		return def.Gradient
	end
	return { def and def.Color or RARITY_COLOR.Common }
end
function Titles.Style(def: any): any
	return Titles.Styles[def and def.Rarity or "Common"] or Titles.Styles.Common
end
function Titles.Rank(def: any): number
	return Titles.RarityRank[def and def.Rarity or "Common"] or 1
end

return Titles
