-- Kit design tokens. Pure data: no services, safe to require from tests.
-- The palette mirrors Modules.UITheme (U.Colors / U.Rarity / U.Assets) and LabConfig.Colors so kit
-- screens look like the rest of DOGROTS; tests/uikit.luau fails if they drift apart.
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local Theme = {}

-- Typeface. PlaceTypography forces FredokaOne on every text object without the KeepFont
-- attribute, so Font is the default; FontNumeric is for numbers (stats, prices, timers) and
-- every label using it gets KeepFont (Base.Text does that).
Theme.Font = Font.fromEnum(Enum.Font.FredokaOne)
Theme.FontNumeric = Font.fromEnum(Enum.Font.FredokaOne)

-- Same keys and values as UITheme.U.Colors.
Theme.Colors = {
	metal = C(232, 244, 255),
	secondary = C(220, 237, 253),
	navy = C(218, 237, 253),
	panel = C(255, 255, 255),
	edge = C(23, 43, 76),
	orange = C(34, 184, 242),
	nav = C(55, 168, 241),
	gold = C(249, 180, 35),
	blue = C(38, 164, 243),
	green = C(125, 219, 48),
	red = C(247, 73, 112),
	purple = C(161, 103, 242),
	text = C(23, 43, 76),
	muted = C(83, 112, 150),
	light = C(247, 251, 255),
}
local P = Theme.Colors

-- Semantic tokens.
Theme.White = WHITE
Theme.Surface = C(255, 251, 242) -- window card (Menus, MiningClient.Shop and CommunityClient use it)
Theme.SurfaceAlt = C(244, 240, 232) -- section background inside a window
Theme.Field = P.navy -- search boxes and inputs (UITheme.Search)
Theme.Backdrop = C(14, 29, 58) -- dim behind windows (UITheme.ApplyShell)
Theme.BackdropTransparency = 0.45
Theme.Ink = P.text
Theme.InkMuted = P.muted
Theme.Line = P.edge
Theme.Accent = P.blue
Theme.Success = P.green
Theme.Danger = P.red
Theme.Warning = P.gold
Theme.Info = P.blue
Theme.Disabled = C(117, 133, 158)

-- Same values as UITheme.U.Rarity (dogs: Common..Secret; items add Uncommon).
Theme.Rarity = {
	Common = C(170, 190, 205),
	Uncommon = P.green,
	Rare = P.blue,
	Epic = P.purple,
	Legendary = P.gold,
	Mythic = P.red,
	Secret = C(230, 115, 245),
	["Brainrot God"] = P.red,
	-- NIGHT OF THE BURIED MOON Lucky Block tiers (LuckyBlockConfig.EventTiers)
	Pumpkin = C(255, 128, 24),
	["Cursed Pumpkin"] = C(122, 62, 200),
}
-- Item rarities (ItemValueConfig.Rarity names): same colours as dogs so a rarity reads the same everywhere.
Theme.ItemRarity = {
	Common = Theme.Rarity.Common,
	Uncommon = Theme.Rarity.Uncommon,
	Rare = Theme.Rarity.Rare,
	Epic = Theme.Rarity.Epic,
	Legendary = Theme.Rarity.Legendary,
	Secret = Theme.Rarity.Secret,
}
-- Two-stop gradients for the top rarities (card stripes and tags).
Theme.RarityGradient = {
	Legendary = { C(255, 214, 92), C(245, 152, 25) },
	Mythic = { C(255, 104, 139), C(214, 44, 98) },
	Secret = { C(244, 140, 255), C(120, 92, 255) },
	["Brainrot God"] = { C(255, 104, 139), C(255, 196, 64) },
	Pumpkin = { C(255, 176, 64), C(232, 92, 16) },
	["Cursed Pumpkin"] = { C(176, 96, 255), C(64, 22, 112) },
}
-- One order for sorting both catalogues (dogs have no Uncommon, items have no Mythic).
Theme.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7, ["Brainrot God"] = 8, Pumpkin = 5.5, ["Cursed Pumpkin"] = 6.5 }

-- Dog variants: the names of ReplicatedStorage.DogEconomy.Config.Variants, colours of LabConfig.Colors.
Theme.Variant = {
	Normal = C(151, 231, 155),
	Shiny = C(168, 220, 255),
	Golden = C(255, 200, 63),
	Corrupted = C(209, 64, 83),
	Glitched = C(211, 92, 248),
	Void = C(106, 49, 184),
}
Theme.VariantRank = { Normal = 1, Shiny = 2, Golden = 3, Corrupted = 4, Glitched = 5, Void = 6 }

-- Item mutations: every key of ItemValueConfig.Mutation. The four with a 3D look use the
-- DiscoveryVisuals colours.
Theme.Mutation = {
	NORMAL = C(170, 190, 205),
	SHINY = C(168, 220, 255),
	GOLDEN = C(255, 195, 40),
	RAINBOW = C(80, 230, 240),
	CURSED = C(194, 40, 62),
	CORRUPTED = C(209, 64, 83),
	GLITCHED = C(207, 49, 255),
	VOID = C(106, 49, 184),
	TOASTED = C(214, 140, 70),
	BURNED = C(133, 82, 52),
	SPORE = C(140, 190, 90),
	FROZEN = C(140, 215, 255),
	INFERNAL = C(255, 92, 40),
	SOLAR = C(255, 170, 40),
	RADIOACTIVE = C(150, 240, 60),
	SPOILED = C(130, 140, 90),
	-- NIGHT OF THE BURIED MOON (post-cap value; DiscoveryVisuals has their 3D looks)
	HAUNTED = C(96, 214, 178),
	PUMPKINIZED = C(255, 128, 24),
	["BLOOD MOON"] = C(204, 26, 46),
	ECLIPSED = C(98, 36, 168),
}

-- Image assets of the HUD tiles (same ids as UITheme.U.Assets). Other keys resolve through
-- ReplicatedStorage.GameIcons.
Theme.Icons = {
	Dogs = "rbxassetid://117639585361256",
	Inventory = "rbxassetid://77546579160081",
	Yard = "rbxassetid://115488468002446",
	Shop = "rbxassetid://99434251630478",
	DogDex = "rbxassetid://124671430150778",
	Lab = "rbxassetid://105402832269661",
	Events = "rbxassetid://86724140753338",
	Trade = "rbxassetid://137537596011172",
}

Theme.Radius = { Window = 18, Card = 14, Button = 12, Field = 10, Small = 8 }
Theme.StrokeWidth = { Window = 3, Card = 2, Button = 2, Field = 2 }

-- Text sizes in pixels: desktop and compact (phones).
Theme.TextSize = { Title = 30, Subtitle = 16, Heading = 21, Body = 17, Small = 14, Tiny = 12, Button = 19 }
Theme.TextSizeCompact = { Title = 23, Subtitle = 13, Heading = 18, Body = 15, Small = 13, Tiny = 11, Button = 17 }

-- Durations in seconds. Spec: open/close 0.15-0.25 s, never slow.
Theme.Motion = { Press = 0.09, Fast = 0.12, Open = 0.18, Close = 0.14, Slide = 0.22, Fill = 0.25 }

-- ScreenGui DisplayOrder of the kit layers. The main ScreenGui is 0, MiningGui 40,
-- CommunityServices / MiningShop 70.
Theme.Layer = { Windows = 60, Modals = 62, Overlay = 95 }

-- Button styles: background, text and stroke colours.
Theme.Buttons = {
	primary = { Bg = P.blue, Text = WHITE, Stroke = P.edge },
	success = { Bg = P.green, Text = WHITE, Stroke = P.edge },
	danger = { Bg = P.red, Text = WHITE, Stroke = P.edge },
	gold = { Bg = P.gold, Text = WHITE, Stroke = P.edge },
	secondary = { Bg = WHITE, Text = P.text, Stroke = P.edge },
	ghost = { Bg = WHITE, Text = P.text, Stroke = nil, Transparent = true },
}

function Theme.Size(name: string, compact: boolean?): number
	local sizes: any = compact and Theme.TextSizeCompact or Theme.TextSize
	return sizes[name] or 16
end

function Theme.RarityColor(name: string?): Color3
	return (name and Theme.Rarity[name]) or Theme.Rarity.Common
end

function Theme.RarityOrder(name: string?): number
	return (name and Theme.RarityRank[name]) or 0
end

function Theme.VariantColor(name: string?): Color3
	return (name and Theme.Variant[name]) or Theme.Variant.Normal
end

function Theme.MutationColor(name: string?): Color3
	return (name and Theme.Mutation[string.upper(name)]) or Theme.Mutation.NORMAL
end

function Theme.Lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

function Theme.Darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Readable text colour on top of a background colour.
function Theme.OnColor(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return luminance > 0.72 and P.text or WHITE
end

-- "#RRGGBB" for RichText <font color="">.
function Theme.Hex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

return Theme
