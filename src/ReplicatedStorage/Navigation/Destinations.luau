-- Navigation.Destinations: every place "SHOW THE WAY" can lead to (pure data + name matching;
-- shared by DistrictGuide, the Navigator window, PathGuide and tests/navigation.luau).
--   Key       stable id (MapRouting / NavigationAnchors keys for the district places)
--   Category  "Plot" (the player's own yard) | "Shops" | "Attractions"
--   Name/Ru   display name, Short/ShortRu  HUD chip, Detail/DetailRu  one-line subtitle
--   Icon      emoji glyph, Color  optional override of the category colour
--   Aliases   other names callers pass to NavigateDistrict (old display names keep working)
--   Sealed    closed area: never routed, shown disabled with its Detail. Event places (THE DEAD YARD, the church) carry a
--             live Sealed: reading entry.Sealed asks Navigation.Live at that moment (Destinations.Sealed(entry) too)
--   PriorityAliases  names this entry takes over from other entries' plain aliases ("Portal" -> the church while the
--             Halloween event runs)
local Destinations = {}
local Live = require(script.Parent:WaitForChild("Live"))

local C = Color3.fromRGB
-- NIGHT OF THE BURIED MOON (Halloween event, WP9): the event's places are in the list when the place ships the event
-- (config flag, read once: DistrictGuide caches its rows); whether they are open is read at call time ([WP-F] Live).
local HALLOWEEN = Live.Configured()

Destinations.Categories = {
	{ Id = "Plot", Text = "MY PLOT", Ru = "МОЙ УЧАСТОК", Color = C(105, 232, 120) },
	{ Id = "Shops", Text = "SHOPS", Ru = "МАГАЗИНЫ", Color = C(255, 192, 58) },
	{ Id = "Attractions", Text = "ATTRACTIONS", Ru = "АТТРАКЦИОНЫ", Color = C(72, 202, 255) },
}

Destinations.List = {
	-- MY PLOT (resolved for the player's own yard).
	{
		Key = "PlayerYards",
		Category = "Plot",
		Icon = "🏠",
		Name = "Your yard",
		Ru = "Твой участок",
		Short = "MY YARD",
		ShortRu = "УЧАСТОК",
		Detail = "Your dogs, digging and workshop",
		DetailRu = "Твои собаки, раскопки и мастерская",
		Aliases = { "My yard", "Yard", "Home", "My plot", "Plot" },
	},
	{
		Key = "MyKennels",
		Category = "Plot",
		Icon = "🐕",
		Name = "My kennels",
		Ru = "Мои будки",
		Short = "KENNELS",
		ShortRu = "БУДКИ",
		Detail = "Dig spots: put your dogs to work",
		DetailRu = "Места раскопок: отправь собак работать",
		Aliases = { "Kennels", "Kennel", "Dig spots", "Dig slots" },
	},
	{
		Key = "MiningCorner",
		Category = "Plot",
		Icon = "⛏",
		Name = "Ore quarry",
		Ru = "Рудный карьер",
		Short = "QUARRY",
		ShortRu = "КАРЬЕР",
		Detail = "Mine ore with your pickaxe for Coins and Stone",
		DetailRu = "Добывай руду киркой за монеты и камень",
		Aliases = { "Mining", "Mining corner", "Mine corner", "Ore", "Quarry", "Ore quarry" },
	},
	{
		Key = "MineElevator",
		Category = "Plot",
		Icon = "🛗",
		Name = "Mine elevator",
		Ru = "Лифт в шахту",
		Short = "ELEVATOR",
		ShortRu = "ЛИФТ",
		Detail = "Ride down to the deep layers",
		DetailRu = "Спустись к глубоким слоям",
		Aliases = { "Elevator", "Mine", "Mine shaft", "Headframe" },
	},
	{
		Key = "BestFinds",
		Category = "Plot",
		Icon = "🏆",
		Name = "BEST FINDS showcase",
		Ru = "Витрина лучших находок",
		Short = "SHOWCASE",
		ShortRu = "ВИТРИНА",
		Detail = "Your rarest finds on display",
		DetailRu = "Твои самые редкие находки",
		Aliases = { "Showcase", "Best finds", "My best finds", "Trophies" },
	},
	{
		Key = "Collector",
		Category = "Plot",
		Icon = "💰",
		Name = "My collector",
		Ru = "Мой сборщик",
		Short = "COLLECTOR",
		ShortRu = "СКУПЩИК",
		Detail = "Sell your finds for Coins",
		DetailRu = "Продавай находки за монеты",
		Aliases = { "Seller", "Sell finds", "Vendor" },
	},
	-- SHOPS.
	{
		Key = "Shops",
		Category = "Shops",
		Icon = "🛒",
		Name = "Paw market",
		Ru = "Лапкин рынок",
		Short = "MARKET",
		ShortRu = "РЫНОК",
		Detail = "Equipment, cosmetics and supplies",
		DetailRu = "Экипировка, косметика и припасы",
		Aliases = { "Market", "Shop", "Paw market street", "Marketplace" },
	},
	{
		Key = "Equipment",
		Category = "Shops",
		Icon = "🎒",
		Name = "Equipment shop",
		Ru = "Магазин экипировки",
		Short = "EQUIPMENT",
		ShortRu = "ЭКИПИРОВКА",
		Detail = "Accessories, artifacts and cases",
		DetailRu = "Аксессуары, артефакты и кейсы",
		Aliases = { "EQUIPMENT", "Upgrades", "UPGRADES", "Upgrade shop" },
	},
	{
		Key = "Cosmetics",
		Category = "Shops",
		Icon = "🎩",
		Name = "Cosmetics shop",
		Ru = "Магазин косметики",
		Short = "COSMETICS",
		ShortRu = "КОСМЕТИКА",
		Detail = "Skins and style for your yard",
		DetailRu = "Скины и стиль для участка",
		Aliases = { "COSMETICS", "Cosmetic shop" },
	},
	{
		Key = "Supplies",
		Category = "Shops",
		Icon = "📦",
		Name = "Supplies shop",
		Ru = "Магазин припасов",
		Short = "SUPPLIES",
		ShortRu = "ПРИПАСЫ",
		Detail = "Treats, snacks and boosts",
		DetailRu = "Лакомства, перекусы и бусты",
		Aliases = { "SUPPLIES", "Supply shop" },
	},
	{
		Key = "Shelter",
		Category = "Shops",
		Icon = "🐶",
		Name = "Dog Shelter",
		Ru = "Приют для собак",
		Short = "SHELTER",
		ShortRu = "ПРИЮТ",
		Detail = "Sell extra dogs and find them a new home",
		DetailRu = "Отдай лишних собак в добрые руки",
		Aliases = { "Shelter", "Dog shelter" },
	},
	-- ATTRACTIONS.
	{
		Key = "DogLine",
		Category = "Attractions",
		Icon = "👅",
		Name = "THE DOG",
		Ru = "СОБАКА",
		Short = "THE DOG",
		ShortRu = "СОБАКА",
		Detail = "Follow the tongue to find your next dog",
		DetailRu = "Иди по языку к своей следующей собаке",
		Aliases = { "Factory", "Dog line", "DOG LINE", "Tongue", "The tongue", "Dog factory" },
	},
	{
		Key = "MutationLab",
		Category = "Attractions",
		Icon = "☢️",
		Name = "Mutation lab",
		Ru = "Лаборатория мутаций",
		Short = "LAB",
		ShortRu = "ЛАБА",
		Detail = "The nuclear tower: mutate your dogs at its console",
		DetailRu = "Ядерная башня: мутируй собак у её пульта",
		Color = C(120, 255, 90),
		Aliases = { "Lab", "Laboratory", "Genetics lab", "Mutation machine", "Nuclear tower", "Cooling tower", "Tower" },
	},
	{
		Key = "DogDex",
		Category = "Attractions",
		Icon = "🏛",
		Name = "DogDex museum",
		Ru = "Музей Догдекса",
		Short = "MUSEUM",
		ShortRu = "МУЗЕЙ",
		Detail = "100 good boys to discover",
		DetailRu = "100 хороших пёсиков ждут тебя",
		Aliases = { "Museum", "DogDex", "Dogdex museum", "DOGDEX" },
	},
	{
		Key = "RewardMachine",
		Category = "Attractions",
		Icon = "🎰",
		Name = "DOG-O-MATIC PLAZA",
		Ru = "Площадь DOG-O-MATIC",
		Short = "DOG-O-MATIC",
		ShortRu = "DOG-O-MATIC",
		Detail = "DOG-O-MATIC rewards and odds",
		DetailRu = "Награды и шансы DOG-O-MATIC",
		Color = C(255, 120, 200),
		Aliases = { "DOG-O-MATIC", "Reward machine", "Machine", "Roulette" },
	},
	{
		Key = "WelcomeHub",
		Category = "Attractions",
		Icon = "⛲",
		Name = "Welcome plaza",
		Ru = "Приветственная площадь",
		Short = "PLAZA",
		ShortRu = "ПЛОЩАДЬ",
		Detail = "Arrival, community and DOG EXPRESS",
		DetailRu = "Прибытие, сообщество и DOG EXPRESS",
		Aliases = { "Paw square", "Spawn", "Hub", "Welcome hub" },
	},
	{
		Key = "DogPark",
		Category = "Attractions",
		Icon = "🏅",
		Name = "Leaderboard Plaza",
		Ru = "Площадь рекордов",
		Short = "RECORDS",
		ShortRu = "РЕКОРДЫ",
		Detail = "All-time records and the social court",
		DetailRu = "Рекорды всех времён и площадка для общения",
		Aliases = { "Leaderboards", "Leaderboard", "Dog park", "Records" },
	},
	{
		Key = "PortalRuins",
		Category = "Attractions",
		Icon = "🌀",
		Name = "Digging layers",
		Ru = "Слои раскопок",
		Short = "LAYERS",
		ShortRu = "СЛОИ",
		Detail = "Discover the underground layers",
		DetailRu = "Открой подземные слои",
		Aliases = { "Layers", "Portal", "Portals", "Layer portal" },
	},
	{
		Key = "Feedback",
		Category = "Attractions",
		Icon = "✉",
		Name = "Developer mailbox",
		Ru = "Почта разработчиков",
		Short = "MAILBOX",
		ShortRu = "ПОЧТА",
		Detail = "Send ideas and wishes to the developers",
		DetailRu = "Отправь идеи и пожелания разработчикам",
		Aliases = { "Mailbox", "Ideas", "Suggestions" },
	},
	{
		Key = "GlobalDigSite",
		Category = "Attractions",
		Icon = "🔒",
		Name = "Global event",
		Ru = "Глобальное событие",
		Short = "EVENT",
		ShortRu = "СОБЫТИЕ",
		Detail = "COMING SOON",
		DetailRu = "СКОРО",
		Sealed = true,
		Aliases = { "Event headquarters", "Global dig", "Global dig site" },
	},
	{
		Key = "TheVoid",
		Category = "Attractions",
		Icon = "🔒",
		Name = "The Void",
		Ru = "Пустота",
		Short = "THE VOID",
		ShortRu = "ПУСТОТА",
		Detail = "SEALED / FUTURE AREA",
		DetailRu = "ЗАКРЫТО / БУДУЩАЯ ЗОНА",
		Sealed = true,
		Aliases = { "Void" },
	},
}

-- An entry whose Sealed is decided when it is read (entry.Sealed, Destinations.Sealed): fn() -> sealed?
local function liveSealed(entry: any, fn: () -> boolean): any
	entry.Sealed = nil
	return setmetatable(entry, {
		__index = function(_, key)
			if key == "Sealed" then
				return fn()
			end
			return nil
		end,
	})
end

-- While the Halloween event is on THE DEAD YARD takes the place of the sealed global event site (same map slot), and
-- THE CHURCH (the Grand Crypt + Moon Tower, the way down to CHAPTER II · THE UNDERYARD) follows it.
if HALLOWEEN then
	for i, entry in ipairs(Destinations.List) do
		if entry.Key == "GlobalDigSite" then
			Destinations.List[i] = liveSealed({
				Key = "DeadYard",
				Category = "Attractions",
				Icon = "🎃",
				Name = "The Dead Yard",
				Ru = "Мёртвый двор",
				Short = "DEAD YARD",
				ShortRu = "МЁРТВЫЙ ДВОР",
				Detail = "Night of the Buried Moon: candy, curses and the cauldron",
				DetailRu = "Ночь Погребённой Луны: конфеты, проклятия и котёл",
				Color = C(255, 140, 40),
				Aliases = { "Dead Yard", "Halloween", "Buried Moon", "Night of the Buried Moon", "Cauldron", "Haunted cauldron", "Graveyard",
					"Global event", "Event headquarters", "Global dig", "Global dig site" },
			}, function()
				return not Live.Halloween()
			end)
			-- [WP-F] THE CHURCH: open while CHAPTER II is (the reveal, the cinematic and the DESCEND portal live there)
			table.insert(Destinations.List, i + 1, liveSealed({
				Key = "Church",
				Category = "Attractions",
				Icon = "⛪",
				Name = "The Church",
				Ru = "Церковь",
				Short = "CHURCH",
				ShortRu = "ЦЕРКОВЬ",
				Detail = "The Grand Crypt under the Moon Tower: something is waiting below",
				DetailRu = "Большой склеп под Лунной башней: внизу что-то ждёт",
				Color = C(150, 80, 230),
				PriorityAliases = { "Portal", "Underyard", "The Underyard", "Underyard portal" },
				Aliases = { "Church", "Crypt", "Grand Crypt", "Moon Tower", "Underyard gate", "Церковь", "Склеп", "Большой склеп",
					"Портал", "Поддворье", "Лунная башня" },
			}, function()
				return not Live.Chapter2()
			end))
			break
		end
	end
end

Destinations.ByKey = {} :: { [string]: any }
for i, entry in ipairs(Destinations.List) do
	entry.Order = i
	Destinations.ByKey[entry.Key] = entry
end
local categoryById = {}
for _, category in ipairs(Destinations.Categories) do
	categoryById[category.Id] = category
end

-- Lower-case, letters and digits only ("DOG-O-MATIC PLAZA" == "dogomatic plaza"). [WP-F] Cyrillic letters count as
-- letters too (lower-cased, Ё = Е), so the Russian aliases ("Церковь", "СКЛЕП") resolve; other symbols are dropped.
function Destinations.Normalize(name: any): string
	if type(name) ~= "string" then
		return ""
	end
	local ok, out = pcall(function()
		local parts = {}
		for _, code in utf8.codes(name) do
			if code < 128 then
				local ch = string.char(code)
				if string.find(ch, "%w") then
					table.insert(parts, string.lower(ch))
				end
			elseif code >= 0x400 and code <= 0x4FF then
				if code >= 0x410 and code <= 0x42F then
					code += 0x20
				elseif code == 0x401 or code == 0x451 then
					code = 0x435
				end
				table.insert(parts, utf8.char(code))
			end
		end
		return table.concat(parts)
	end)
	if ok then
		return out
	end
	return (string.gsub(string.lower(name), "[^%w]", ""))
end

-- Is the entry closed right now? (event places ask Navigation.Live)
function Destinations.Sealed(entry: any): boolean
	return type(entry) == "table" and entry.Sealed == true
end

local index: { [string]: string } = {}
local function remember(name: any, key: string)
	local n = Destinations.Normalize(name)
	if n ~= "" and index[n] == nil then
		index[n] = key
	end
end
-- Keys and display names first (exact meaning), then the aliases an entry takes over, then every other alias.
for _, entry in ipairs(Destinations.List) do
	remember(entry.Key, entry.Key)
	remember(entry.Name, entry.Key)
end
for _, entry in ipairs(Destinations.List) do
	for _, alias in ipairs(entry.PriorityAliases or {}) do
		remember(alias, entry.Key)
	end
end
for _, entry in ipairs(Destinations.List) do
	remember(entry.Short, entry.Key)
	for _, alias in ipairs(entry.Aliases or {}) do
		remember(alias, entry.Key)
	end
end

-- Key of a destination from a key, a display name (any case) or an alias; nil when unknown.
function Destinations.Resolve(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	if Destinations.ByKey[name] then
		return name
	end
	return index[Destinations.Normalize(name)]
end

function Destinations.Get(nameOrKey: any): any
	local key = Destinations.Resolve(nameOrKey)
	return key and Destinations.ByKey[key] or nil
end

function Destinations.Category(id: any): any
	return categoryById[id] or Destinations.Categories[3]
end

function Destinations.Color(entry: any): Color3
	return entry.Color or Destinations.Category(entry.Category).Color
end

-- Localized text of an entry: field "Name" | "Short" | "Detail", lang "ru" | "en".
function Destinations.Text(entry: any, field: string, lang: string?): string
	if lang == "ru" then
		local ru = entry[field == "Name" and "Ru" or field .. "Ru"]
		if type(ru) == "string" then
			return ru
		end
	end
	return tostring(entry[field] or entry.Name or entry.Key)
end

return Destinations
