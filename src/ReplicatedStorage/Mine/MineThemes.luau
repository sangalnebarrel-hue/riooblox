-- MineThemes: the look of every mine level (colours, materials, names, lighting mood, ambient
-- sound) shared by the world builders (MineStructures, MineLevels), the client (MineClient) and
-- the elevator window (MineScreen). Index = dig layer (Config.Layers): 1 Backyard (surface),
-- 2 Caverns, 3 Ancient Ruins, 4 Cursed Depths, 5 THE VOID (the rare zone).
-- Text here is the English source; Russian lives in ReplicatedStorage.Localization.Mine (world
-- signs are translated by DOGROTS_AutoTranslateUI) and in Themes[i].Ru (self-localized UI).
local C = Color3.fromRGB

local Themes = {}

Themes[1] = {
	Layer = 1,
	Key = "Surface",
	Title = "BACKYARD",
	Ru = "ЗАДНИЙ ДВОР",
	Depth = "0–10 m",
	DepthRu = "0–10 м",
	Tagline = "Grass, junk and lost toys",
	TaglineRu = "Трава, хлам и потерянные игрушки",
	Accent = C(126, 200, 90),
	Rock = C(122, 96, 70),
	RockDark = C(88, 66, 48),
	Floor = C(96, 160, 72),
	Glow = C(190, 255, 140),
}

Themes[2] = {
	Layer = 2,
	Key = "Caverns",
	Title = "CAVERNS",
	Ru = "ПЕЩЕРЫ",
	Depth = "10–50 m",
	DepthRu = "10–50 м",
	Tagline = "Blue crystals, coal and fossils",
	TaglineRu = "Синие кристаллы, уголь и окаменелости",
	Accent = C(84, 186, 255),
	Rock = C(96, 108, 126),
	RockDark = C(58, 66, 82),
	RockLight = C(132, 146, 166),
	Floor = C(74, 82, 96),
	Glow = C(110, 210, 255),
	Water = C(70, 150, 200),
	RockMaterial = "Slate",
	FloorMaterial = "Slate",
	Strata = { C(104, 116, 134), C(78, 88, 104), C(120, 132, 150) },
	Lighting = {
		Ambient = C(62, 80, 108),
		OutdoorAmbient = C(62, 80, 108),
		Atmosphere = { Density = 0.36, Offset = 0, Color = C(74, 104, 142), Decay = C(32, 46, 72), Glare = 0, Haze = 1.4 },
		Grade = { TintColor = C(214, 232, 255), Saturation = -0.04, Contrast = 0.12, Brightness = -0.02 },
	},
	Sound = { Drone = 0.34, DroneVolume = 0.14, Drips = true, DripPitch = 1.6 },
}

Themes[3] = {
	Layer = 3,
	Key = "Ruins",
	Title = "ANCIENT RUINS",
	Ru = "ДРЕВНИЕ РУИНЫ",
	Depth = "50–150 m",
	DepthRu = "50–150 м",
	Tagline = "Idols, pottery and gold",
	TaglineRu = "Идолы, керамика и золото",
	Accent = C(255, 196, 54),
	Rock = C(196, 160, 106),
	RockDark = C(140, 104, 66),
	RockLight = C(226, 196, 140),
	Floor = C(178, 142, 92),
	Glow = C(255, 206, 90),
	Glyph = C(108, 72, 38),
	RockMaterial = "Sandstone",
	FloorMaterial = "Sandstone",
	Strata = { C(190, 152, 98), C(160, 122, 78), C(214, 180, 122) },
	Lighting = {
		Ambient = C(120, 94, 62),
		OutdoorAmbient = C(120, 94, 62),
		Atmosphere = { Density = 0.32, Offset = 0, Color = C(204, 164, 104), Decay = C(122, 82, 40), Glare = 0, Haze = 1.7 },
		Grade = { TintColor = C(255, 238, 208), Saturation = 0.08, Contrast = 0.1, Brightness = 0 },
	},
	Sound = { Drone = 0.42, DroneVolume = 0.12, Drips = false, Wind = true },
}

Themes[4] = {
	Layer = 4,
	Key = "Cursed",
	Title = "CURSED DEPTHS",
	Ru = "ПРОКЛЯТЫЕ ГЛУБИНЫ",
	Depth = "150–500 m",
	DepthRu = "150–500 м",
	Tagline = "Cursed ore, bones and chains",
	TaglineRu = "Проклятая руда, кости и цепи",
	Accent = C(255, 60, 50),
	Rock = C(46, 36, 40),
	RockDark = C(24, 18, 22),
	RockLight = C(74, 58, 62),
	Floor = C(34, 26, 30),
	Glow = C(255, 70, 40),
	Lava = C(255, 96, 30),
	Bone = C(232, 218, 194),
	RockMaterial = "Basalt",
	FloorMaterial = "Basalt",
	Strata = { C(54, 40, 44), C(36, 26, 30), C(88, 34, 34) },
	Lighting = {
		Ambient = C(96, 36, 34),
		OutdoorAmbient = C(96, 36, 34),
		Atmosphere = { Density = 0.48, Offset = 0, Color = C(146, 34, 32), Decay = C(64, 10, 12), Glare = 0, Haze = 2.2 },
		Grade = { TintColor = C(255, 216, 210), Saturation = 0.06, Contrast = 0.2, Brightness = -0.03 },
	},
	Sound = { Drone = 0.22, DroneVolume = 0.18, Rumble = true },
}

Themes[5] = {
	Layer = 5,
	Key = "Void",
	Title = "THE VOID",
	Ru = "ПУСТОТА",
	Depth = "500+ m",
	DepthRu = "500+ м",
	Tagline = "The rare zone: void crystals",
	TaglineRu = "Редкая зона: кристаллы Пустоты",
	Accent = C(176, 92, 255),
	Rock = C(22, 16, 34),
	RockDark = C(10, 6, 18),
	RockLight = C(46, 34, 70),
	Floor = C(14, 10, 24),
	Glow = C(180, 90, 255),
	Cyan = C(90, 224, 255),
	Star = C(240, 236, 255),
	RockMaterial = "Basalt",
	FloorMaterial = "Glass",
	Strata = { C(30, 20, 48), C(18, 12, 30), C(64, 34, 104) },
	Lighting = {
		Ambient = C(56, 34, 88),
		OutdoorAmbient = C(56, 34, 88),
		Atmosphere = { Density = 0.44, Offset = 0, Color = C(46, 24, 80), Decay = C(12, 2, 34), Glare = 0, Haze = 1.1 },
		Grade = { TintColor = C(232, 216, 255), Saturation = 0.12, Contrast = 0.24, Brightness = -0.04 },
	},
	Sound = { Drone = 0.5, DroneVolume = 0.16, Pings = true },
}

-- Island strata of the shaft (top down): topsoil, clay, gravel, rock.
Themes.IslandStrata = {
	{ Top = 1, Bottom = -2.5, Color = C(104, 74, 48), Material = "Ground" },
	{ Top = -2.5, Bottom = -8, Color = C(150, 104, 70), Material = "Sand" },
	{ Top = -8, Bottom = -14, Color = C(122, 116, 104), Material = "Pebble" },
	{ Top = -14, Bottom = -22, Color = C(88, 96, 100), Material = "Slate" },
	{ Top = -22, Bottom = -32, Color = C(68, 80, 86), Material = "Rock" },
}

-- The island rock of the outer shell (matches CohesiveIsland.IslandMass).
Themes.ShellRock = C(68, 83, 88)
Themes.ShellDark = C(50, 60, 66)

function Themes.Get(layer: any): any
	return Themes[tonumber(layer) or 1] or Themes[1]
end

-- Display name and depth in the player's language ("ru" | "en").
function Themes.Name(layer: any, lang: string?): string
	local t = Themes.Get(layer)
	return lang == "ru" and t.Ru or t.Title
end
function Themes.DepthText(layer: any, lang: string?): string
	local t = Themes.Get(layer)
	return lang == "ru" and t.DepthRu or t.Depth
end

return Themes
