-- NIGHT OF THE BURIED MOON window (StarterGui.ScreenGui.Modules.HalloweenScreen; UI kit window, navigation key "Halloween").
-- Routed by GUIIntegration.kitScreens: N.OpenPage("Halloween", arg) -> S.Open(arg). arg: nil | tab id | {Tab = id}
-- (case-insensitive; "Cauldron" from the cauldron prompt, "Boss" from the Grave Bell).
-- Tabs: event (overview: candy, curse, Blood Moon, Candy Rush, server exorcism, the way to THE DEAD YARD), quests
-- (5 daily quests + the all-done bonus), dex (Event DogDex BURIED MOON 2026 + reward track), cauldron (TRICK / TREAT),
-- boss (THE GRAVEKEEPER I-V), cosmetics (pickaxe skins with 3D previews).
-- Look: the kit window (rounded card, gradient header, pill tabs, kit buttons) in the Halloween palette: dark purple
-- glass panels, pumpkin orange actions, neon green progress, white text.
-- Data: the Halloween view (Bus "StateChanged" from HalloweenClient.State and every Request reply), the live attributes
-- of RS.Halloween.State (BloodMoon / Exorcism / Boss folders) and of the player (MoonCandy, MoonCurse, HwRush*,
-- HwBossUnlocked, HwInZone). Requests go to RS.Halloween.Remotes.Request (the screen lives in StarterGui).
-- Text: ReplicatedStorage.Localization.Halloween (UI / Templates; labels NoTranslate; server replies via Dict.Translate).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Theme, Format, Motion = Kit.Theme, Kit.Format, Kit.Motion

local S = {}
S.Tabs = { "event", "quests", "dex", "cauldron", "boss", "cosmetics" }

local player = Players.LocalPlayer
local Halloween = RS:WaitForChild("Halloween", 10)
local Config, Shared, Bus = nil, nil, nil
if Halloween then
	local okC, c = pcall(require, Halloween:WaitForChild("Config", 10))
	Config = okC and c or nil
	local okS, s = pcall(require, Halloween:WaitForChild("Shared", 10))
	Shared = okS and s or nil
	local okB, b = pcall(require, Halloween:WaitForChild("Bus", 10))
	Bus = okB and b or nil
end
-- built vector icons (RS.Halloween.Icons); nil = the emoji glyphs stay
local Icons = nil
if Halloween then
	local mod = Halloween:FindFirstChild("Icons")
	if mod then
		local okI, m = pcall(require, mod)
		Icons = okI and type(m) == "table" and m.New and m or nil
	end
end
-- CHAPTER II (WP-L): the shared Underyard rules / names (RS.Halloween.UnderyardView) and its icons (registered into Icons)
local UV, UIcons = nil, nil
if Halloween then
	local modV = Halloween:FindFirstChild("UnderyardView")
	if modV then
		local okV, m = pcall(require, modV)
		UV = okV and type(m) == "table" and m or nil
	end
	local modI = Halloween:FindFirstChild("UnderyardIcons")
	if modI then
		local okI, m = pcall(require, modI)
		UIcons = okI and type(m) == "table" and m or nil
	end
end
Config = Config or { HalloweenEventEnabled = false }
local Dict = { UI = {}, Templates = {}, Exact = {}, Patterns = {} }
do
	local folder = RS:FindFirstChild("Localization")
	local module = folder and folder:FindFirstChild("Halloween")
	if module then
		local ok, d = pcall(require, module)
		if ok and type(d) == "table" then
			Dict = d
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------------------------------
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string): string
	if ru() then
		return (Dict.UI and Dict.UI[en]) or (Dict.Exact and Dict.Exact[en]) or (UV and UV.T(en, "ru")) or en
	end
	return en
end
-- CHAPTER II labels (Localization.UnderyardUI, then .Underyard) and config pairs {en, ru}
local function UT(en: string): string
	return UV and UV.T(en, Kit.Lang()) or en
end
local function UF(en: string, ...): string
	if UV then
		return UV.F(en, Kit.Lang(), ...)
	end
	local ok, out = pcall(string.format, en, ...)
	return ok and out or en
end
local function UL(pair: any): string
	if UV then
		return UV.L(pair, Kit.Lang())
	end
	return type(pair) == "table" and tostring(pair[1]) or tostring(pair or "")
end
-- string.format with a localized template; a Russian template may be {one, few, many} (picked by the first number)
local function F(en: string, ...): string
	local fmt: any = en
	if ru() and Dict.Templates then
		fmt = Dict.Templates[en] or en
	end
	if type(fmt) == "table" then
		local n = 0
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "number" then
				n = v
				break
			end
		end
		fmt = Dict.Plural and Dict.Plural(n, fmt[1], fmt[2], fmt[3]) or fmt[3]
	end
	local ok, out = pcall(string.format, fmt, ...)
	return ok and out or en
end
-- server message -> (text, selfLocalized)
local function said(r: any): (string, boolean)
	local msg = type(r) == "table" and r.Message or r
	msg = tostring(msg or "")
	if Dict.Translate then
		local out = Dict.Translate(msg, Kit.Lang())
		if out then
			return out, true
		end
	end
	return msg, not ru()
end
-- upper case that also handles Cyrillic (string.upper is ASCII only)
local function upper(text: string): string
	return (string.gsub(string.upper(text), utf8.charpattern, function(ch)
		local c = utf8.codepoint(ch)
		if c >= 0x430 and c <= 0x44F then
			return utf8.char(c - 0x20)
		elseif c == 0x451 then
			return utf8.char(0x401)
		end
		return ch
	end))
end
S.Upper = upper
local function num(n: any): string
	return Format.Number(math.floor(tonumber(n) or 0))
end
local function short(n: any): string
	return Format.Short(math.floor(tonumber(n) or 0), 1)
end

------------------------------------------------------------------------------------------------------------------------
-- Palette (Config.Palette + kit tokens)
------------------------------------------------------------------------------------------------------------------------
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local PUMPKIN = C(255, 128, 24)
local PUMPKIN_HI = C(255, 176, 74)
local PURPLE = C(122, 62, 200)
local PURPLE_HI = C(176, 120, 246)
local NEON = C(120, 255, 110)
local BLOOD = C(200, 30, 50)
local GHOST = C(140, 215, 255)
local GOLD = C(255, 200, 70)
local BONE = C(236, 226, 200)
local INK = C(16, 8, 26)
local BG_TOP, BG_BOTTOM = C(48, 22, 74), C(24, 10, 38)
local PANEL_TOP, PANEL_BOTTOM = C(70, 36, 104), C(52, 24, 80)
local PANEL_EDGE = C(124, 84, 178)
local TRACK = C(28, 12, 42)
local SOFT = C(226, 212, 248) -- body text on panels
local MUTED = C(170, 150, 204)
local TAB_OFF = C(66, 34, 98)
local Z = 3

local RARITY = {
	Common = C(170, 190, 205), Rare = Theme.Rarity.Rare, Epic = Theme.Rarity.Epic, Legendary = Theme.Rarity.Legendary,
	Mythic = Theme.Rarity.Mythic, Secret = Theme.Rarity.Secret,
}

------------------------------------------------------------------------------------------------------------------------
-- Small UI helpers (dark Halloween panels on top of the kit components)
------------------------------------------------------------------------------------------------------------------------
-- rendered width of a Fredoka One string (pill rows are placed by hand)
local function textW(text: string, size: number): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(10000, 1000))
	end)
	if ok and v and v.X > 0 then
		return v.X
	end
	return (utf8.len(text) or #text) * size * 0.62
end

-- height of wrapped Fredoka One text in a box `width` wide
local function textH(text: string, size: number, width: number): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(math.max(10, width), 10000))
	end)
	if ok and v and v.Y > 0 then
		return math.ceil(v.Y) + 2
	end
	return math.ceil(textW(text, size) / math.max(10, width) + 0.5) * size * 1.2
end

local function place(o: any, x: number, y: number, w: number, h: number)
	o.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	o.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
end

local function gradient(o: any, top: Color3, bottom: Color3, rotation: number?)
	local g = o:FindFirstChild("HwGradient")
	if not g then
		g = Kit.New("UIGradient", { Name = "HwGradient" }, o)
	end
	o.BackgroundColor3 = WHITE
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	return g
end

-- a rounded glass panel (dark purple gradient, light purple rim)
local function panel(parent: Instance, name: string, top: Color3?, bottom: Color3?, z: number?): Frame
	local f = Kit.New("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = z or Z }, parent)
	Kit.Corner(f, 14)
	Kit.Stroke(f, PANEL_EDGE, 2, 0.15)
	gradient(f, top or PANEL_TOP, bottom or PANEL_BOTTOM)
	return f
end

local function txt(parent: Instance?, props: { [string]: any }): any
	local p = table.clone(props)
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	p.Color = p.Color or WHITE
	p.ZIndex = p.ZIndex or Z + 1
	return Kit.Text(parent, p)
end

-- emoji / glyph in a coloured circle
local function badge(parent: Instance, name: string, glyph: string, color: Color3, z: number?): (Frame, any)
	local f = Kit.New("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = z or Z + 1 }, parent)
	Kit.Corner(f, "pill")
	Kit.Stroke(f, INK, 2, 0.2)
	gradient(f, color:Lerp(WHITE, 0.25), color:Lerp(INK, 0.25))
	local g = txt(f, { Name = "Glyph", Text = glyph, TextSize = 40, Scaled = true, MinTextSize = 8, AlignX = "Center",
		Position = UDim2.fromScale(0.16, 0.16), Size = UDim2.fromScale(0.68, 0.68), ZIndex = (z or Z + 1) + 1 })
	return f, g
end

-- a built icon filling `holder` (or a sub-box of it); hides `glyph` (the emoji label it replaces). nil without Icons.
local function art(holder: Instance?, kind: string, opts: { [string]: any }?, glyph: any?): any
	if not Icons or not holder then
		return nil
	end
	local o = table.clone(opts or {})
	o.ZIndex = o.ZIndex or ((holder :: any).ZIndex + 1)
	o.Size = o.Size or 48
	local ok, h = pcall(Icons.New, holder, kind, o)
	if not ok then
		return nil
	end
	if glyph then
		glyph.TextTransparency = 1
	end
	return h
end
S.Art = art
-- the built icon of a Server Exorcism milestone kind
function S.MilestoneIcon(kind: string?): (string, { [string]: any })
	if kind == "CandyRush" then
		return "Candy", {}
	elseif kind == "Block" then
		return "Pumpkin", {}
	elseif kind == "Mutation" then
		return "Potion", { Glow = C(190, 110, 255) }
	elseif kind == "Boss" then
		return "Skull", { Glow = C(255, 70, 80) }
	end
	return "Star", {}
end
-- a built icon inside a badge() circle (hides its Glyph label)
local function badgeArt(f: Frame, kind: string, opts: { [string]: any }?): any
	local o = table.clone(opts or {})
	o.FrameSize, o.Position, o.AnchorPoint = UDim2.fromScale(o.Scale or 0.86, o.Scale or 0.86), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	o.Scale = nil
	return art(f, kind, o, f:FindFirstChild("Glyph"))
end

local function button(parent: Instance, props: { [string]: any }): any
	local p = table.clone(props)
	p.ZIndex = p.ZIndex or Z + 2
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	return Kit.Button(parent, p)
end

local function bar(parent: Instance, name: string, color: Color3, height: number?): any
	local b = Kit.ProgressBar(parent, { Name = name, Color = color, Track = TRACK, Height = height or 18, TextSize = 13, NoTranslate = true,
		ZIndex = Z + 1 })
	return b
end

local function pill(parent: Instance, name: string, text: string, color: Color3, textColor: Color3?): any
	return Kit.Pill(parent, { Name = name, Text = text, Color = color, TextColor = textColor, Height = 24, TextSize = 13, PadX = 9,
		NoTranslate = true, ZIndex = Z + 2 })
end

local function scrollPage(page: Frame): ScrollingFrame
	return Kit.New("ScrollingFrame", {
		Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		ScrollBarThickness = 6, ScrollBarImageColor3 = PANEL_EDGE, ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = Z,
	}, page)
end

------------------------------------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------------------------------------
local st = { View = nil, Busy = {}, Selected = { Treat = nil, Boss = nil }, LastNearCheck = 0 }
S.State = st

local function view(): any
	return st.View or {}
end
local function stateFolder(): Instance?
	return Halloween and Halloween:FindFirstChild("State")
end
local function folderAttrs(name: string): { [string]: any }
	local f = stateFolder()
	local sub = f and f:FindFirstChild(name)
	return sub and sub:GetAttributes() or {}
end
local function now(): number
	return Kit.Now()
end
local function candy(): number
	local a = player:GetAttribute("MoonCandy")
	if type(a) == "number" then
		return a
	end
	return tonumber(view().Candy) or 0
end
local function root(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end
local function near(pos: Vector3?, range: number): boolean
	local r = root()
	return r ~= nil and pos ~= nil and (r.Position - pos).Magnitude <= range
end
local function layout(): any
	return Shared and Shared.Layout or nil
end
local function moonState(): any
	if Shared then
		local ok, s = pcall(Shared.BloodMoonState, now())
		if ok and s then
			return s
		end
	end
	return { State = "NORMAL", WarningTimestamp = 0, StartTimestamp = 0, ActiveEndTimestamp = 0, EndTimestamp = 0 }
end
local function clock(sec: number): string
	return Format.Clock(math.max(0, math.ceil(sec)), Kit.Lang())
end
local function duration(sec: number): string
	return Format.Duration(math.max(0, math.ceil(sec)), Kit.Lang())
end
local function nav(): any
	local ok, n = pcall(require, script.Parent.GUIIntegration)
	return ok and n or nil
end
local function showTheWay()
	local n = nav()
	if n and n.Navigate then
		n.Navigate("DeadYard")
	end
end
local function audio(cue: string)
	if not Halloween then
		return
	end
	task.spawn(function()
		local mod = Halloween:FindFirstChild("Audio")
		if mod then
			local ok, A = pcall(require, mod)
			if ok and type(A) == "table" and A.Play and (not A.Has or A.Has(cue)) then
				pcall(A.Play, cue)
			end
		end
	end)
end

-- names (Config) -> localized display
local function dogName(id: string): string
	local def = Config.Dogs and Config.Dogs.Defs and Config.Dogs.Defs[id]
	return T(def and def.Name or id)
end
local function skinName(id: string): string
	return T(Config.Skins and Config.Skins.Names and Config.Skins.Names[id] or id)
end
local DECOR = { hw_jack_o_lantern = "JACK-O'-LANTERN", hw_grave_stone = "GRAVE STONE", hw_candle_cluster = "CANDLE CLUSTER", hw_bone_arch = "BONE ARCH" }
local MUTATION_GLYPH = { HAUNTED = "👻", PUMPKINIZED = "🎃", ["BLOOD MOON"] = "🩸", ECLIPSED = "🌑" }

-- a CHAPTER II reward row (Bell Shards, Coffin Keys, Lucky Dust, fragments, showcase finds, uy_ decor, UY_ skins, H09-H16)
local function uyRow(row: any): boolean
	return UV ~= nil and UV.IsChapter2Row(row)
end
local UY_GLYPH = { Shards = "🔔", Key = "🗝️", Dust = "✨", Fragments = "🧩", Find = "💎", Decor = "🪦", Skin = "⛏️", Dog = "🐶", Title = "👑" }

-- {glyph, text, color} of a reward row (Config.Rewards / quests / dex / Core reply rows)
local function rewardChip(row: any): (string, string, Color3)
	local kind = row.Kind
	if uyRow(row) then
		local rarity = UV.RowRarity(row)
		local amount = math.floor(tonumber(row.Amount) or 0)
		local text = (kind == "Shards" or kind == "Key" or kind == "Dust" or kind == "Fragments") and (num(amount) .. " " .. upper(UL(UV.KindName[kind])))
			or upper(UV.RowName(row, Kit.Lang()))
		local color = kind == "Shards" and C(150, 80, 230) or kind == "Key" and C(110, 150, 220) or kind == "Dust" and C(170, 140, 60)
			or RARITY[rarity] or PURPLE
		return UY_GLYPH[kind] or "🎁", text, color
	end
	if kind == "Candy" then
		return "🍬", num(row.Amount), PUMPKIN
	elseif kind == "Bones" then
		return "🦴", num(row.Amount), BONE:Lerp(PURPLE, 0.35)
	elseif kind == "Block" then
		local cursed = row.Id == "Cursed Pumpkin"
		local n = row.Amount or 1
		return cursed and "💀" or "🎃", (n > 1 and (n .. "× ") or "") .. T(cursed and "CURSED PUMPKIN" or "PUMPKIN BLOCK"), cursed and PURPLE or PUMPKIN
	elseif kind == "Decor" then
		return "🕯️", upper(T(DECOR[row.Id or ""] or tostring(row.Name or row.Id))), C(96, 170, 120)
	elseif kind == "Skin" then
		return "⛏️", upper(skinName(row.Id or "")), RARITY[(Config.Skins and Config.Skins.Rarity and Config.Skins.Rarity[row.Id]) or "Epic"] or PURPLE
	elseif kind == "Dog" then
		return "🐶", upper(dogName(row.Id or "")), RARITY[Shared and select(1, Shared.Rarity(row.Rank or (Config.Dogs.Defs[row.Id] or {}).Rank)) or "Rare"] or PURPLE
	elseif kind == "Mutation" then
		return MUTATION_GLYPH[row.Id or ""] or "🧬", T(tostring(row.Id) .. " FIND"), C(150, 90, 220)
	elseif kind == "Cash" then
		return "💰", row.Amount and num(row.Amount) or T("COINS"), C(90, 180, 70)
	elseif kind == "Luck" then
		return "🍀", T("LUCK BOOST"), C(70, 170, 90)
	end
	return "🎁", tostring(row.Name or kind or "?"), PURPLE
end

local function chipRow(holder: Frame, rows: { any }, maxW: number, height: number?, center: boolean?): number
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local h = height or 26
	local x, y = 0, 0
	for i, row in ipairs(rows) do
		local glyph, text, color = rewardChip(row)
		local label = glyph .. " " .. text .. (row.Suffix or "")
		local size = h >= 26 and 14 or 12
		local p = Kit.Pill(holder, { Name = "Reward" .. i, Text = label, Color = color, Height = h, TextSize = size,
			PadX = 9, NoTranslate = true, ZIndex = Z + 3 })
		local w = math.ceil(textW(label, size)) + 18
		if maxW > 0 and w > maxW then
			-- wider than the whole row (long Russian names): smaller text, then a fixed width with "…"
			local fit = size
			while fit > 9 and math.ceil(textW(label, fit)) + 18 > maxW do
				fit -= 1
			end
			p.Label.TextSize = fit
			w = math.ceil(textW(label, fit)) + 18
			if w > maxW then
				p.Instance.AutomaticSize = Enum.AutomaticSize.None
				p.Instance.Size = UDim2.fromOffset(maxW, h)
				p.Label.AutomaticSize = Enum.AutomaticSize.None
				p.Label.Size = UDim2.fromScale(1, 1)
				p.Label.TextTruncate = Enum.TextTruncate.AtEnd
				w = maxW
			end
		end
		if x > 0 and maxW > 0 and x + w > maxW then
			x, y = 0, y + h + 6
		end
		p.Instance.Position = UDim2.fromOffset(x, y)
		p.Instance:SetAttribute("HwRowY", y)
		p.Instance:SetAttribute("HwW", w)
		x += w + 6
	end
	if center and maxW > 0 then
		-- shift every line to the middle
		local lines = {}
		for _, c in ipairs(holder:GetChildren()) do
			local ly = c:GetAttribute("HwRowY")
			if ly then
				local line = lines[ly] or { Items = {}, Right = 0 }
				lines[ly] = line
				table.insert(line.Items, c)
				line.Right = math.max(line.Right, c.Position.X.Offset + (c:GetAttribute("HwW") or 0))
			end
		end
		for _, line in pairs(lines) do
			local dx = math.floor((maxW - line.Right) / 2)
			for _, c in ipairs(line.Items) do
				c.Position = UDim2.fromOffset(c.Position.X.Offset + dx, c.Position.Y.Offset)
			end
		end
	end
	return #rows > 0 and (y + h) or 0
end

------------------------------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------------------------------
local win: any = nil
local ui: any = nil
local refreshAll: () -> ()
local revealTab: () -> ()

local function setView(v: any)
	if type(v) == "table" then
		st.View = v
		if ui then
			refreshAll()
		end
	end
end

local function invoke(action: string, args: any?): (boolean, any)
	local remotes = Halloween and Halloween:FindFirstChild("Remotes")
	local rf = remotes and remotes:FindFirstChild("Request")
	if not rf then
		return false, "Not ready"
	end
	local ok, a, b = pcall(function()
		return rf:InvokeServer(action, args or {})
	end)
	if not ok then
		return false, "Connection problem; try again"
	end
	if a and type(b) == "table" and type(b.View) == "table" then
		if Bus then
			Bus.Fire("StateChanged", { View = b.View })
		end
		setView(b.View)
	end
	return a == true, b
end
S.Invoke = invoke

local function toastResult(ok: boolean, res: any, okText: string?)
	if ok then
		local text, own = okText or nil, true
		if not text then
			text, own = said(res)
		end
		if text ~= "" then
			Kit.Toast(text, { Kind = "success", Sound = "Coin", NoTranslate = own })
		end
	else
		local text, own = said(res)
		Kit.Toast(text ~= "" and text or T("Something went wrong, try again"), { Kind = "error", NoTranslate = own })
		audio("Deny")
	end
end

-- button-bound request: busy state, stale-window guard, toast
local function act(btn: any, action: string, args: any?, onOk: ((any) -> ())?, okText: string?)
	if st.Busy[action] then
		return
	end
	st.Busy[action] = true
	if btn then
		btn:SetBusy(true)
	end
	task.spawn(function()
		local ok, res = invoke(action, args)
		st.Busy[action] = nil
		if btn then
			btn:SetBusy(false)
		end
		toastResult(ok, res, okText)
		if ok and onOk then
			onOk(res)
		end
		if ui then
			refreshAll()
		end
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- REWARD REVEAL: the big moment of a claim (event DogDex collection, the cauldron brew, the daily bonus)
-- A full-screen card above the kit windows: a turning ray burst behind a spinning 3D preview of the best row (pickaxe
-- skin / pumpkin block / candy model, the dog's preview, else its built icon) in a rarity-coloured glow ring, then the
-- rows pop in as item cards one by one (least rare first, the best last) with rising ticks, an Unlock for the rare ones,
-- confetti and the Claim cue at the end. Secret rows add a violet shimmer and a vignette. Tap anywhere: skip to the end
-- (then COLLECT / tap closes). ReducedMotion: no turning, no spin, no confetti, the cards appear at once.
------------------------------------------------------------------------------------------------------------------------
local REVEAL_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }
local function rowRarity(row: any): string
	local kind = row.Kind
	if type(row.Rarity) == "string" and REVEAL_RANK[row.Rarity] then
		return row.Rarity
	end
	if uyRow(row) then
		return UV.RowRarity(row)
	end
	local function byRank(rank: any, default: string): string
		if Shared and type(rank) == "number" then
			return (select(1, Shared.Rarity(rank)))
		end
		return default
	end
	if kind == "Dog" then
		local def = Config.Dogs and Config.Dogs.Defs and Config.Dogs.Defs[row.Id or ""]
		return byRank(row.Rank or (def and def.Rank), "Rare")
	elseif kind == "Skin" then
		return (Config.Skins and Config.Skins.Rarity and Config.Skins.Rarity[row.Id or ""]) or "Epic"
	elseif kind == "Block" then
		return row.Id == "Cursed Pumpkin" and "Mythic" or "Epic"
	elseif kind == "Title" then
		return "Legendary"
	elseif kind == "Decor" then
		return "Epic"
	elseif kind == "Mutation" then
		return byRank(row.Rank or 4, "Legendary")
	end
	return byRank(row.Rank, "Rare")
end
S.RowRarity = rowRarity
local REWARD_TITLE = { BuriedMoon2026 = "BURIED MOON SURVIVOR" }
-- {name, line under it} of a reward row
local function rowText(row: any): (string, string)
	local kind = row.Kind
	local n = tonumber(row.Amount) or 1
	if uyRow(row) then
		return upper(UV.RowName(row, Kit.Lang())), UV.RowSub(row, Kit.Lang())
	end
	if kind == "Candy" then
		return T("MOON CANDY"), "+" .. num(row.Amount)
	elseif kind == "Bones" then
		return T("BONES"), "+" .. num(row.Amount)
	elseif kind == "Block" then
		local cursed = row.Id == "Cursed Pumpkin"
		return T(cursed and "CURSED PUMPKIN" or "PUMPKIN BLOCK"), n > 1 and ("x" .. n) or T("LUCKY BLOCK")
	elseif kind == "Skin" then
		return upper(skinName(row.Id or "")), T("PICKAXE SKIN")
	elseif kind == "Dog" then
		return upper(dogName(row.Id or "")), T("EVENT DOG")
	elseif kind == "Decor" then
		return upper(T(DECOR[row.Id or ""] or tostring(row.Name or row.Id))), T("YARD DECOR")
	elseif kind == "Mutation" then
		return T(tostring(row.Id) .. " FIND"), T("MUTATION")
	elseif kind == "Title" then
		return T(REWARD_TITLE[row.Id or ""] or tostring(row.Name or row.Id)), T("NEW TITLE")
	elseif kind == "Cash" then
		return T("COINS"), row.Amount and ("+" .. num(row.Amount)) or ""
	end
	return tostring(row.Name or kind or "?"), ""
end

-- a 3D model of a reward row for the hero preview (nil = the built icon)
local function rewardModel(row: any): Instance?
	local kind = row.Kind
	local ok, model = false, nil
	if uyRow(row) and (kind == "Decor" or kind == "Find") then
		-- the Underyard window builds plot cosmetics / showcase finds (DecorModels / DiscoveryVisuals)
		local mod = script.Parent:FindFirstChild("UnderyardScreen")
		local okU, U = false, nil
		if mod then
			okU, U = pcall(require, mod)
		end
		if okU and type(U) == "table" and U.ItemModel then
			ok, model = pcall(U.ItemModel, { Kind = kind, Id = row.Id })
		end
	elseif kind == "Skin" then
		local mod = Halloween and Halloween:FindFirstChild("PickaxeSkins")
		local okM, Skins = false, nil
		if mod then
			okM, Skins = pcall(require, mod)
		end
		if okM and type(Skins) == "table" and Skins.Build then
			ok, model = pcall(Skins.Build, row.Id)
		end
		if ok and typeof(model) == "Instance" then
			model:SetAttribute("SkinId", row.Id)
		end
	elseif kind == "Block" or kind == "Candy" then
		local folder = Halloween and Halloween:FindFirstChild("Models")
		local mod = folder and folder:FindFirstChild("Pumpkin")
		local okM, P = false, nil
		if mod then
			okM, P = pcall(require, mod)
		end
		if okM and type(P) == "table" then
			if kind == "Block" and P.Block then
				ok, model = pcall(P.Block, row.Id or "Pumpkin", { Lit = true })
			elseif kind == "Candy" and P.Candy then
				ok, model = pcall(P.Candy, PUMPKIN)
			end
		end
	end
	if ok and typeof(model) == "Instance" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("ParticleEmitter") or d:IsA("Sound") or d:IsA("Light") then
				d:Destroy()
			end
		end
		return model
	end
	return nil
end
S.RewardModel = rewardModel

-- a ViewportFrame showing `model` with an orbiting camera; returns (frame, step(dt, kick)) or nil
local function orbitViewport(parent: Instance, model: Instance, z: number, focusOverride: Vector3?, distOverride: number?): (any, any)
	local vp = Kit.New("ViewportFrame", { Name = "Preview3D", BackgroundTransparency = 1, Ambient = C(178, 160, 220), LightColor = C(255, 236, 210),
		LightDirection = Vector3.new(-1, -1.2, -0.6), Size = UDim2.fromScale(1, 1), ZIndex = z })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local okBox, cf, size = pcall(function()
		if model:IsA("Model") then
			return (model :: any):GetBoundingBox()
		end
		return (model :: any).CFrame, (model :: any).Size
	end)
	if not okBox then
		vp.Parent = parent
		return vp, function() end
	end
	local focus = focusOverride or cf.Position
	local dist = distOverride or (size.Magnitude / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.02)
	local light0 = Vector3.new(-1, -1.2, -0.6)
	local yaw, pitch = math.rad(35), math.rad(14)
	local function place(a: number, bob: number)
		local dir = Vector3.new(math.sin(a) * math.cos(pitch), math.sin(pitch), math.cos(a) * math.cos(pitch))
		cam.CFrame = CFrame.lookAt(focus + dir * dist + Vector3.new(0, bob, 0), focus + Vector3.new(0, bob, 0))
		-- the light turns with the camera: the model reads as spinning under a fixed key light
		vp.LightDirection = (CFrame.Angles(0, a, 0) * light0)
	end
	place(yaw, 0)
	vp.Parent = parent
	local spin = yaw
	return vp, function(dt: number, kick: number?)
		spin += dt * (0.9 + (kick or 0) * 12)
		place(spin, math.sin(os.clock() * 1.6) * dist * 0.012)
	end
end
S.OrbitViewport = orbitViewport

local revealGui: ScreenGui? = nil
local revealActive: any = nil
local function revealLayer(): ScreenGui
	if revealGui and revealGui.Parent then
		return revealGui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "DOGROTS_HalloweenReward"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 74 -- [WP-D2] above the kit windows (60), modals (62) and CommunityServices (70, no tie), under toasts (95)
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g:SetAttribute("NoTranslate", true)
	g.Parent = player:WaitForChild("PlayerGui")
	revealGui = g
	return g
end

-- rewardReveal(title, rows, opts?) opts: Kicker (small line above the title), Accent (Color3), Done (fn on close)
local function rewardReveal(title: string, rows: { any }?, opts: { [string]: any }?)
	if type(rows) ~= "table" or #rows == 0 then
		return
	end
	opts = opts or {}
	if revealActive then
		revealActive.Close(true)
	end
	local reduced = Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion()) or false
	local low = Shared and Shared.Low() or false
	-- least rare first, the best row last; the hero is the best row
	local list = {}
	for i, row in ipairs(rows) do
		if type(row) == "table" then
			table.insert(list, { Row = row, Rarity = rowRarity(row), I = i })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = REVEAL_RANK[a.Rarity] or 2, REVEAL_RANK[b.Rarity] or 2
		if ra ~= rb then
			return ra < rb
		end
		return a.I < b.I
	end)
	local best = list[#list]
	local bestColor = RARITY[best.Rarity] or PURPLE
	local secret = best.Rarity == "Secret"
	local gui = revealLayer()
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if W < 10 then
		-- a brand-new ScreenGui has no size yet: the main gui's, else the camera's
		local main = player:FindFirstChildOfClass("PlayerGui")
		main = main and main:FindFirstChild("ScreenGui")
		local okS, size = pcall(function()
			return main and main.AbsoluteSize.X > 10 and main.AbsoluteSize or workspace.CurrentCamera.ViewportSize
		end)
		W, H = okS and size and size.X or 1280, okS and size and size.Y or 720
	end
	local phone = math.min(W, H) < 560
	local maid = {}
	local function give(x)
		table.insert(maid, x)
		return x
	end
	local root = give(Kit.New("TextButton", { Name = "RewardReveal", Text = "", AutoButtonColor = false, BackgroundColor3 = C(8, 2, 16),
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1, Selectable = false }, gui))
	root:SetAttribute("NoTranslate", true)
	TweenService:Create(root, TweenInfo.new(reduced and 0 or 0.3), { BackgroundTransparency = 0.16 }):Play()
	-- the world behind goes soft while the card is up
	local blur = nil
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then
			blur = Instance.new("BlurEffect")
			blur.Name = "DOGROTS_HalloweenRewardBlur"
			blur.Size = reduced and 8 or 0
			blur.Parent = cam
			if not reduced then
				TweenService:Create(blur, TweenInfo.new(0.35), { Size = 10 }):Play()
			end
		end
	end)
	if blur then
		give(blur)
	end
	-- vignette (Secret: violet) - two crossed gradient frames darken the edges
	for i, rot in ipairs({ 0, 90 }) do
		local v = Kit.New("Frame", { Name = "Vignette" .. i, BorderSizePixel = 0, BackgroundColor3 = secret and C(70, 10, 110) or C(0, 0, 0),
			BackgroundTransparency = secret and 0.2 or 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, root)
		Kit.New("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.22, 1),
			NumberSequenceKeypoint.new(0.78, 1), NumberSequenceKeypoint.new(1, 0.1) }) }, v)
	end
	local col = Kit.New("Frame", { Name = "Column", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.min(W - 24, 760), math.min(H - 24, 640)), ZIndex = 3 }, root)
	local scale = Kit.New("UIScale", { Name = "Pop", Scale = reduced and 1 or 0.6 }, col)
	if not reduced then
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	local cw = col.Size.X.Offset
	local ch = col.Size.Y.Offset
	-- heading
	local kicker = txt(col, { Name = "Kicker", Text = opts.Kicker or T("YOU GOT"), TextSize = phone and 14 or 17, Scaled = true, MinTextSize = 9, AlignX = "Center",
		Color = bestColor:Lerp(WHITE, 0.45), ZIndex = 8, Stroke = 0.4 })
	place(kicker, 0, 0, cw, phone and 18 or 22)
	local head = txt(col, { Name = "Title", Text = title, TextSize = phone and 30 or 44, Scaled = true, MinTextSize = 14, AlignX = "Center", ZIndex = 8, Stroke = 0.1 })
	place(head, 0, phone and 18 or 22, cw, phone and 38 or 54)
	local headGrad = Kit.New("UIGradient", { Rotation = 0, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, bestColor:Lerp(WHITE, 0.55)),
		ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, bestColor:Lerp(WHITE, 0.55)) }) }, head)
	-- hero: rays, glow ring, the 3D model (or icon)
	-- side by side on short landscape screens (hero left, cards right), stacked otherwise
	local side = H < 520 and W > H * 1.4
	local headH = phone and 60 or 84
	local heroS = math.floor(side and math.min(ch - headH - 34, cw * 0.36) or math.min(phone and 170 or 250, ch * 0.4))
	local heroX = side and math.floor(cw * 0.22) or cw / 2
	local heroY = headH + heroS / 2 + (side and 2 or 0)
	local hero = Kit.New("Frame", { Name = "Hero", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(heroX, heroY), Size = UDim2.fromOffset(heroS, heroS), ZIndex = 4 }, col)
	local rays = {}
	local nRays = low and 8 or 14
	for i = 1, nRays do
		local r = Kit.New("Frame", { Name = "Ray", BorderSizePixel = 0, BackgroundColor3 = (i % 2 == 0) and bestColor or bestColor:Lerp(WHITE, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, i % 2 == 0 and 26 or 14, 2.3, 0),
			Rotation = (i - 1) * 180 / nRays, ZIndex = 4 }, hero)
		Kit.New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, r)
		rays[i] = r
	end
	local halo = Kit.New("Frame", { Name = "Halo", BorderSizePixel = 0, BackgroundColor3 = bestColor, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.0, 1.0), ZIndex = 5 }, hero)
	Kit.Corner(halo, "pill")
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(bestColor:Lerp(WHITE, 0.3), bestColor:Lerp(INK, 0.5)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.15) }) }, halo)
	local ring = Kit.Stroke(halo, bestColor:Lerp(WHITE, 0.35), 4, 0.05)
	local disc = Kit.New("Frame", { Name = "Disc", BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.86), ZIndex = 5 }, hero)
	Kit.Corner(disc, "pill")
	gradient(disc, C(64, 30, 98), C(20, 8, 34))
	local step = nil
	local model = rewardModel(best.Row)
	if model then
		local okV, vp, fn = pcall(orbitViewport, disc, model, 6)
		if okV and vp then
			vp.Size = UDim2.fromScale(1.2, 1.2)
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Position = UDim2.fromScale(0.5, 0.5)
			step = fn
		end
	elseif best.Row.Kind == "Dog" then
		pcall(function()
			local renderer = require(script.Parent.PreviewRenderer)
			local view = renderer.Dog(disc, best.Row.Id, 0, 0, math.floor(heroS * 0.86), math.floor(heroS * 0.86))
			if view then
				view.ZIndex = 6
			end
		end)
	end
	if not step and best.Row.Kind ~= "Dog" then
		local kind, o = "Star", {}
		if Icons then
			kind, o = (UIcons and UIcons.ForReward or Icons.ForReward)(best.Row)
		end
		local ic = table.clone(o)
		ic.Size, ic.ZIndex = heroS, 7
		ic.FrameSize, ic.Position, ic.AnchorPoint = UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
		art(disc, kind, ic)
	end
	-- rarity tag under the hero
	local tag = Kit.Pill(col, { Name = "Rarity", Text = T(string.upper(best.Rarity)), Color = bestColor, Height = 26, TextSize = 14, NoTranslate = true, ZIndex = 9 })
	local grad = Theme.RarityGradient[best.Rarity]
	if grad then
		tag:SetGradient(grad[1], grad[2])
	end
	tag.Instance.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Instance.Position = UDim2.fromOffset(heroX, heroY + heroS / 2 + 12)
	-- the cards
	local n = #list
	local areaX = side and math.floor(cw * 0.44) or 0
	local areaW = side and cw - areaX or cw
	local perRow = side and math.min(n, 3) or phone and math.min(n, cw < 360 and 2 or 3) or math.min(n, 5)
	local gap = phone and 8 or 12
	local cardW = math.floor(math.min(phone and 116 or 136, (areaW - gap * (perRow - 1)) / perRow))
	local cardH = math.floor(cardW * 1.18)
	local rowsN = math.ceil(n / perRow)
	local top = side and headH or heroY + heroS / 2 + (phone and 34 or 44)
	local btnH = phone and 42 or 48
	local avail = ch - top - btnH - 14
	if rowsN * (cardH + gap) > avail and rowsN > 0 then
		-- not enough height (phone landscape): smaller cards
		cardH = math.max(70, math.floor(avail / rowsN) - gap)
		cardW = math.floor(cardH / 1.18)
	end
	local cards = {}
	for i, e in ipairs(list) do
		local r = math.floor((i - 1) / perRow)
		local inRow = math.min(perRow, n - r * perRow)
		local c = (i - 1) % perRow
		local x0 = areaX + (areaW - (inRow * cardW + (inRow - 1) * gap)) / 2
		local rc = RARITY[e.Rarity] or PURPLE
		local card = Kit.New("Frame", { Name = "Card" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x0 + c * (cardW + gap) + cardW / 2, top + r * (cardH + gap) + cardH / 2), Size = UDim2.fromOffset(cardW, cardH),
			ZIndex = 10, Visible = reduced }, col)
		Kit.Corner(card, 14)
		gradient(card, rc:Lerp(C(50, 22, 80), 0.55), C(22, 8, 36))
		local stroke = Kit.Stroke(card, rc, 3, 0)
		local rg = Theme.RarityGradient[e.Rarity]
		if rg then
			Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(rg[1], rg[2]) }, stroke)
		end
		local pop = Kit.New("UIScale", { Name = "Pop", Scale = 1 }, card)
		local iconBox = Kit.New("Frame", { Name = "IconBox", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, math.floor(cardH * 0.06)), Size = UDim2.fromOffset(math.floor(cardW * 0.62), math.floor(cardW * 0.62)), ZIndex = 11 }, card)
		local glyphTxt = nil
		if Icons then
			local kind, o = (UIcons and UIcons.ForReward or Icons.ForReward)(e.Row)
			local ic = table.clone(o)
			ic.Size, ic.ZIndex = cardW * 0.62, 12
			art(iconBox, kind, ic)
		else
			local glyph = rewardChip(e.Row)
			glyphTxt = txt(iconBox, { Name = "Glyph", Text = glyph, TextSize = 48, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = 12 })
			glyphTxt.Size = UDim2.fromScale(1, 1)
		end
		local name, sub = rowText(e.Row)
		local nameL = txt(card, { Name = "Name", Text = name, TextSize = phone and 12 or 14, Scaled = true, MinTextSize = 7, AlignX = "Center", Wrap = true,
			ZIndex = 12, Stroke = 0.4 })
		place(nameL, 6, math.floor(cardH * 0.06 + cardW * 0.62 + 2), cardW - 12, math.floor(cardH * 0.2))
		local subL = txt(card, { Name = "Sub", Text = sub, TextSize = phone and 11 or 13, Scaled = true, MinTextSize = 7, AlignX = "Center", ZIndex = 12,
			Color = rc:Lerp(WHITE, 0.5), Font = "numeric" })
		place(subL, 6, cardH - math.floor(cardH * 0.17) - 4, cardW - 12, math.floor(cardH * 0.15))
		cards[i] = { Frame = card, Pop = pop, Rarity = e.Rarity, Row = e.Row, Stroke = stroke }
	end
	local collect
	collect = button(col, { Name = "Collect", Text = T("COLLECT"), Style = "success", TextSize = phone and 17 or 20, ZIndex = 12, OnClick = function()
		if revealActive and revealActive.Close then
			revealActive.Close()
		end
	end })
	local bw = math.min(phone and 200 or 260, areaW - 40)
	place(collect.Instance, areaX + areaW / 2 - bw / 2, math.min(ch - btnH - (side and 4 or 0), top + rowsN * (cardH + gap) + 6), bw, btnH)
	collect.Instance.Visible = reduced
	local hint = txt(col, { Name = "Hint", Text = T("Tap to skip"), TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED, ZIndex = 12 })
	place(hint, 0, ch - 18, cw, 16)
	hint.Visible = not reduced
	-- confetti (frame particles falling from the top of the screen)
	local confetti = {}
	local function burstConfetti()
		if reduced then
			return
		end
		local count = low and 18 or 40
		for k = 1, count do
			local cc = (k % 4 == 0) and NEON or (k % 4 == 1) and PUMPKIN or (k % 4 == 2) and bestColor or GOLD
			local sz = math.random(6, 11)
			local f = Kit.New("Frame", { Name = "Confetti", BorderSizePixel = 0, BackgroundColor3 = cc, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(W * (0.15 + 0.7 * math.random()), -20 - math.random() * 120), Size = UDim2.fromOffset(sz, sz * (k % 2 == 0 and 1 or 0.5)),
				Rotation = math.random(0, 360), ZIndex = 20 }, root)
			if k % 3 == 0 then
				Kit.Corner(f, "pill")
			end
			table.insert(confetti, { F = f, VX = (math.random() - 0.5) * 120, VY = 140 + math.random() * 160, Spin = (math.random() - 0.5) * 540, Life = 2.2 + math.random() })
		end
	end
	-- timeline
	local alive = true
	local revealed = 0
	local finished = false
	local t0 = os.clock()
	local kick = 0
	local function showCard(i: number, quiet: boolean?)
		local c = cards[i]
		if not c or c.Shown then
			return
		end
		c.Shown = true
		c.Frame.Visible = true
		revealed = math.max(revealed, i)
		if not reduced and not quiet then
			c.Pop.Scale = 0.2
			TweenService:Create(c.Pop, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			c.Stroke.Thickness = 7
			TweenService:Create(c.Stroke, TweenInfo.new(0.5), { Thickness = 3 }):Play()
		end
		if not quiet then
			local rank = REVEAL_RANK[c.Rarity] or 2
			if rank >= 4 then
				audio("Unlock")
				kick = 1
			else
				task.spawn(function()
					local mod = Halloween and Halloween:FindFirstChild("Audio")
					local okA, A = false, nil
					if mod then
						okA, A = pcall(require, mod)
					end
					if okA and A and A.Play then
						pcall(A.Play, "CandyTick", nil, { Pitch = 0.9 + i * 0.08 })
					end
				end)
			end
		end
	end
	local function finish()
		if finished then
			return
		end
		finished = true
		for i = 1, #cards do
			showCard(i, true)
		end
		collect.Instance.Visible = true
		hint.Visible = false
		if not reduced then
			collect.Instance.Size = UDim2.fromOffset(bw * 0.7, btnH * 0.7)
			TweenService:Create(collect.Instance, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(bw, btnH) }):Play()
		end
		audio(secret and "RewardSecret" or "Claim")
		burstConfetti()
	end
	local conn
	local function close(instant: boolean?)
		if not alive then
			return
		end
		alive = false
		if revealActive and revealActive.Root == root then
			revealActive = nil
		end
		if conn then
			conn:Disconnect()
		end
		local function destroy()
			for i = #maid, 1, -1 do
				pcall(function()
					maid[i]:Destroy()
				end)
			end
		end
		if instant or reduced then
			destroy()
		else
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
			TweenService:Create(root, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			col.Visible = false
			task.delay(0.22, destroy)
		end
		if type(opts.Done) == "function" then
			task.spawn(opts.Done)
		end
	end
	revealActive = { Root = root, Close = close, Finish = finish }
	root.Activated:Connect(function()
		if not finished then
			finish()
		elseif os.clock() - t0 > 0.6 then
			close()
		end
	end)
	audio("RewardOpen")
	if reduced then
		finish()
	end
	-- one RenderStepped while the card is up: rays turn, the model spins, the title shimmers, cards appear on schedule,
	-- confetti falls
	local firstAt, gapT = 0.55, (n > 5 and 0.16 or 0.24)
	conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then
			return
		end
		local age = os.clock() - t0
		if not reduced then
			for i, r in ipairs(rays) do
				r.Rotation = (i - 1) * 180 / nRays + age * 14
			end
			headGrad.Offset = Vector2.new(math.sin(age * (secret and 2.2 or 1.3)) * 0.6, 0)
			ring.Transparency = 0.05 + 0.25 * (0.5 + 0.5 * math.sin(age * 3))
			if step then
				step(dt, kick)
			end
			kick = math.max(0, kick - dt * 2.5)
		end
		if not finished then
			local due = math.floor((age - firstAt) / gapT) + 1
			for i = revealed + 1, math.min(due, #cards) do
				showCard(i)
			end
			if age > firstAt + gapT * #cards + 0.15 then
				finish()
			end
		end
		for k = #confetti, 1, -1 do
			local p = confetti[k]
			p.Life -= dt
			if p.Life <= 0 or not p.F.Parent then
				p.F:Destroy()
				table.remove(confetti, k)
			else
				p.VY += 260 * dt
				p.F.Position = p.F.Position + UDim2.fromOffset(p.VX * dt, p.VY * dt)
				p.F.Rotation += p.Spin * dt
				if p.Life < 0.5 then
					p.F.BackgroundTransparency = 1 - p.Life / 0.5
				end
			end
		end
	end)
	give(root)
	return revealActive
end
S.RewardReveal = rewardReveal
local function rewardsDialog(title: string, rows: { any }?, opts: { [string]: any }?)
	return rewardReveal(title, rows, opts)
end

------------------------------------------------------------------------------------------------------------------------
-- Cards: {Frame, Layout(w, compact) -> h, Refresh()}
------------------------------------------------------------------------------------------------------------------------
local pages: { [string]: any } = {}

local function sectionTitle(parent: Instance, glyph: string, text: string, color: Color3?): any
	local t = txt(parent, { Name = "Heading", Text = glyph ~= "" and (glyph .. "  " .. text) or text, TextSize = 20, Scaled = true, MinTextSize = 11, Color = color or WHITE,
		Stroke = 0.35 })
	return t
end

---------------------------------------------------------------------------- EVENT
pages.event = function(page: Frame)
	local P: any = { Cards = {} }
	local scroll = scrollPage(page)
	P.Scroll = scroll

	-- HERO: THE DEAD YARD
	local hero = panel(scroll, "Hero", C(86, 34, 118), C(26, 8, 36))
	hero.ClipsDescendants = true
	local moonGlow = Kit.New("Frame", { Name = "MoonGlow", BorderSizePixel = 0, BackgroundColor3 = C(255, 150, 60), BackgroundTransparency = 0.72,
		ZIndex = Z + 1 }, hero)
	Kit.Corner(moonGlow, "pill")
	local moon = Kit.New("Frame", { Name = "Moon", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 1 }, hero)
	Kit.Corner(moon, "pill")
	gradient(moon, C(255, 246, 214), C(255, 170, 70), 120)
	local crater1 = Kit.New("Frame", { Name = "Crater", BorderSizePixel = 0, BackgroundColor3 = C(236, 160, 70), BackgroundTransparency = 0.35,
		ZIndex = Z + 2 }, moon)
	Kit.Corner(crater1, "pill")
	local crater2 = crater1:Clone()
	crater2.Parent = moon
	local pumpkin = txt(hero, { Name = "Pumpkin", Text = "🎃", TextSize = 90, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = Z + 3 })
	local bats = txt(hero, { Name = "Bats", Text = "🦇  🦇", TextSize = 30, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = Z + 2,
		Transparency = 0.15 })
	-- built hero art: the Buried Moon, a jack-o'-lantern in front of it, two bats (gentle idle motion)
	local heroArt = nil
	if Icons then
		heroArt = {}
		heroArt.Moon = Kit.New("Frame", { Name = "HeroMoon", BackgroundTransparency = 1, ZIndex = Z + 1 }, hero)
		art(heroArt.Moon, "Moon", { Size = 150, ZIndex = Z + 1 })
		heroArt.Pumpkin = Kit.New("Frame", { Name = "HeroPumpkin", BackgroundTransparency = 1, ZIndex = Z + 3 }, hero)
		art(heroArt.Pumpkin, "Pumpkin", { Size = 96, ZIndex = Z + 3 })
		heroArt.Bats = {}
		for i = 1, 2 do
			local b = Kit.New("Frame", { Name = "HeroBat" .. i, BackgroundTransparency = 1, ZIndex = Z + 2, Rotation = i == 1 and -10 or 12 }, hero)
			art(b, "Bat", { Size = 40, ZIndex = Z + 2 })
			heroArt.Bats[i] = b
		end
		if not (Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion())) then
			local breath = Kit.New("UIScale", { Name = "Breath" }, heroArt.Pumpkin)
			TweenService:Create(breath, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 }):Play()
			for i, b in ipairs(heroArt.Bats) do
				TweenService:Create(b, TweenInfo.new(0.9 + i * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Rotation = i == 1 and 8 or -6 }):Play()
			end
		end
		pumpkin.Visible, bats.Visible = false, false
	end
	local heroKicker = txt(hero, { Name = "Kicker", Text = T("HALLOWEEN EVENT"), TextSize = 15, Color = PUMPKIN_HI, Scaled = true, MinTextSize = 9 })
	local heroTitle = txt(hero, { Name = "Title", Text = T("THE DEAD YARD"), TextSize = 34, Scaled = true, MinTextSize = 16, Stroke = 0.2 })
	local heroBody = txt(hero, { Name = "Body", Text = T("Dig haunted graves, mine moon ore, knock on 7 cursed doors and feed the cauldron. Stay active: the curse rises when you idle."),
		TextSize = 16, Wrap = true, Color = SOFT, AlignY = "Top" })
	local go = button(hero, { Name = "ShowWay", Text = T("SHOW THE WAY"), Color = PUMPKIN, Icon = nil, TextSize = 18, OnClick = showTheWay })
	local how = button(hero, { Name = "HowToPlay", Text = T("HOW TO PLAY"), Style = "secondary", TextSize = 16, OnClick = function()
		if win then
			win:Close("guide")
		end
		if Bus then
			Bus.Fire("Onboarding", { Replay = true })
		end
	end })
	local here = pill(hero, "InZone", "✅ " .. T("YOU ARE IN THE DEAD YARD"), C(46, 140, 60))
	table.insert(P.Cards, { Frame = hero, Column = 1, Layout = function(w, compact)
		local art = compact and 0 or math.min(190, w * 0.3)
		local tw = w - art - 32
		local by = compact and 68 or 78
		-- the card grows with the description (Russian runs a line longer than English)
		local bh = math.max(compact and 64 or 54, textH(heroBody.Text, 16, tw))
		local h = math.max(compact and 214 or 196, by + bh + 64)
		place(heroKicker, 18, 14, tw, 18)
		place(heroTitle, 18, 32, tw, compact and 34 or 42)
		place(heroBody, 18, by, tw, bh)
		local bw = math.min(220, (tw - 12) / 2)
		local inZone = player:GetAttribute("HwInZone") == true
		local first = inZone and (math.ceil(textW(here.Label.Text, 13)) + 18) or bw
		place(go.Instance, 18, h - 58, bw, 44)
		place(how.Instance, 30 + first, h - 58, math.min(180, tw - first - 12), 44)
		here.Instance.Position = UDim2.fromOffset(18, h - 48)
		P.HeroZone = inZone
		moon.Visible, moonGlow.Visible, pumpkin.Visible = art > 0 and not heroArt, art > 0 and not heroArt, art > 0 and not heroArt
		if art > 0 then
			local m = math.min(art - 30, 130)
			place(moonGlow, w - art + (art - m) / 2 - 14, 4, m + 28, m + 28)
			place(moon, w - art + (art - m) / 2, 18, m, m)
			place(crater1, m * 0.22, m * 0.30, m * 0.2, m * 0.2)
			place(crater2, m * 0.56, m * 0.56, m * 0.14, m * 0.14)
			place(pumpkin, w - art + art * 0.35, h - 92, 86, 86)
			place(bats, w - art + 4, 8, 90, 30)
			if heroArt then
				local ms = m + 36
				place(heroArt.Moon, w - art + (art - ms) / 2, 2, ms, ms)
				local ps = math.min(100, art * 0.56)
				place(heroArt.Pumpkin, w - art + (art - ps) / 2 + art * 0.12, h - ps - 10, ps, ps)
				place(heroArt.Bats[1], w - art + 2, 10, 46, 46)
				place(heroArt.Bats[2], w - 52, 46, 34, 34)
			end
		end
		bats.Visible = art > 0 and not heroArt
		if heroArt then
			heroArt.Moon.Visible, heroArt.Pumpkin.Visible = art > 0, art > 0
			heroArt.Bats[1].Visible, heroArt.Bats[2].Visible = art > 0, art > 0
		end
		return h
	end, Refresh = function()
		local inZone = player:GetAttribute("HwInZone") == true
		go.Instance.Visible = not inZone
		here.Instance.Visible = inZone
		if P.HeroZone ~= nil and P.HeroZone ~= inZone then
			P.Relayout()
		end
	end })

	-- CHAPTER II · THE UNDERYARD (WP-L): the Chapter I checklist while it is sealed, then the way down + the Underyard window
	local c2Card = panel(scroll, "Chapter2", C(78, 48, 150), C(22, 14, 50))
	c2Card.ClipsDescendants = true
	local c2Stroke = c2Card:FindFirstChildWhichIsA("UIStroke")
	if c2Stroke then
		c2Stroke.Color = C(150, 200, 255)
	end
	local c2Badge = badge(c2Card, "Icon", "🔔", C(110, 70, 200))
	local c2Art = badgeArt(c2Badge, "Seal", { Size = 48, Glow = C(150, 200, 255) })
	local c2Kicker = txt(c2Card, { Name = "Kicker", Text = UT("CHAPTER II"), TextSize = 14, Scaled = true, MinTextSize = 8, Color = C(150, 200, 255) })
	local c2Title = txt(c2Card, { Name = "Title", Text = UT("THE UNDERYARD"), TextSize = 26, Scaled = true, MinTextSize = 12, Stroke = 0.25 })
	local c2Count = txt(c2Card, { Name = "Count", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = NEON,
		Font = "numeric", Stroke = 0.3 })
	local c2Lock = pill(c2Card, "Locked", "🔒 " .. UT("LOCKED"), C(90, 60, 130))
	local c2Head = txt(c2Card, { Name = "Line", Text = "", TextSize = 16, Wrap = true, Color = C(196, 226, 255), AlignY = "Top" })
	local c2Body = txt(c2Card, { Name = "Body", Text = "", TextSize = 14, Wrap = true, Color = SOFT, AlignY = "Top" })
	local c2Bar = bar(c2Card, "Progress", C(150, 200, 255), 14)
	local c2Rows = {}
	local checklist = UV and UV.Config and UV.Config.Chapter1 and UV.Config.Chapter1.Checklist or {}
	for i, row in ipairs(checklist) do
		local r = Kit.New("Frame", { Name = "Check" .. i, BorderSizePixel = 0, BackgroundColor3 = C(16, 8, 30), BackgroundTransparency = 0.4, ZIndex = Z + 1 }, c2Card)
		Kit.Corner(r, 10)
		local mark = txt(r, { Name = "Mark", Text = "🔒", TextSize = 16, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = Z + 2 })
		local label = txt(r, { Name = "Text", Text = UL(row.Text), TextSize = 14, Wrap = true, Color = SOFT, ZIndex = Z + 2 })
		local value = txt(r, { Name = "Value", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, AlignX = "Right", Color = GOLD, Font = "numeric",
			ZIndex = Z + 2 })
		c2Rows[i] = { Frame = r, Mark = mark, Text = label, Value = value, Key = row.Key }
	end
	local function underyardModule(): any
		local mod = script.Parent:FindFirstChild("UnderyardScreen")
		if not mod then
			return nil
		end
		local ok, m = pcall(require, mod)
		return ok and type(m) == "table" and m or nil
	end
	local c2Descend = button(c2Card, { Name = "Descend", Text = UT("DESCEND"), Color = C(150, 80, 230), TextSize = 17, OnClick = function()
		local U = underyardModule()
		if win then
			win:Close("way")
		end
		if U and U.Descend then
			U.Descend()
		else
			local n = nav()
			if n and n.Navigate then
				n.Navigate("DeadYard")
			end
		end
	end })
	local c2Open = button(c2Card, { Name = "OpenUnderyard", Text = UT("OPEN UNDERYARD"), Style = "secondary", TextSize = 16, OnClick = function()
		local n = nav()
		if n and n.OpenPage then
			n.OpenPage("Underyard")
		end
	end })
	local c2State: any = { Key = "" }
	local function c2Data(): (boolean, any, boolean, boolean)
		local enabled = UV ~= nil and Shared ~= nil and Shared.Chapter2Enabled ~= nil and Shared.Chapter2Enabled()
		local cv = view().Chapter2 or {}
		local eligible = player:GetAttribute("HalloweenChapter1Complete") == true or (cv.Chapter1 ~= nil and cv.Chapter1.Complete == true)
		local below = player:GetAttribute("UyInZone") == true
		return enabled, cv, eligible, below
	end
	c2Card.Visible = (select(1, c2Data()))
	table.insert(P.Cards, { Frame = c2Card, Column = 1, Layout = function(w, compact)
		local enabled, _, eligible, below = c2Data()
		c2Card.Visible = enabled
		place(c2Badge, 16, 16, 52, 52)
		local cw = compact and 90 or 120
		place(c2Kicker, 80, 14, w - 80 - cw - 24, 18)
		place(c2Title, 80, 32, w - 80 - cw - 24, compact and 28 or 32)
		place(c2Count, w - cw - 16, 18, cw, 28)
		c2Lock.Instance.AnchorPoint = Vector2.new(1, 0)
		c2Lock.Instance.Position = UDim2.new(1, -16, 0, 50)
		local y = 78
		local headH = c2Head.Text ~= "" and textH(c2Head.Text, 16, w - 32) or 0
		c2Head.Visible = headH > 0
		place(c2Head, 16, y, w - 32, headH)
		y += headH > 0 and headH + 2 or 0
		local bodyH = c2Body.Text ~= "" and textH(c2Body.Text, 14, w - 32) or 0
		c2Body.Visible = bodyH > 0
		place(c2Body, 16, y, w - 32, bodyH)
		y += bodyH > 0 and bodyH + 8 or 0
		place(c2Bar.Instance, 16, y, w - 32, 14)
		y += 24
		for _, r in ipairs(c2Rows) do
			r.Frame.Visible = not eligible
			if not eligible then
				local vw = compact and 64 or 80
				local tw = w - 32 - 36 - vw - 12
				local rh = math.max(30, textH(r.Text.Text, 14, tw) + 8)
				place(r.Frame, 16, y, w - 32, rh)
				place(r.Mark, 6, math.floor((rh - 22) / 2), 24, 22)
				place(r.Text, 36, 4, tw, rh - 8)
				place(r.Value, w - 32 - vw - 8, math.floor((rh - 22) / 2), vw, 22)
				y += rh + 6
			end
		end
		local showDescend = eligible and not below
		c2Descend.Instance.Visible = showDescend
		local bw = math.min(230, math.floor((w - 32 - 12) / 2))
		if showDescend then
			place(c2Descend.Instance, 16, y + 4, bw, 44)
			place(c2Open.Instance, 16 + bw + 12, y + 4, bw, 44)
		else
			place(c2Open.Instance, 16, y + 4, math.min(260, w - 32), 44)
		end
		c2State.Layout = (eligible and "E" or "L") .. (showDescend and "D" or "")
		return y + 4 + 44 + 14
	end, Refresh = function()
		local enabled, cv, eligible, below = c2Data()
		local layoutKey = tostring(enabled) .. (eligible and "E" or "L") .. ((eligible and not below) and "D" or "")
		if not enabled then
			if c2Card.Visible then
				P.Relayout()
			end
			return
		end
		c2Lock.Instance.Visible = not eligible
		local head, body
		if not eligible then
			local c1 = cv.Chapter1 or {}
			local values = {}
			for _, row in ipairs(c1.Checklist or {}) do
				values[row.Key] = row
			end
			local done = 0
			for _, r in ipairs(c2Rows) do
				local row = values[r.Key] or {}
				local ok = row.Done == true
				if ok then
					done += 1
				end
				r.Mark.Text = ok and "✅" or "🔒"
				r.Value.Text = F("%d / %d", math.min(tonumber(row.Value) or 0, tonumber(row.Goal) or 0), tonumber(row.Goal) or 0)
				r.Value.TextColor3 = ok and NEON or GOLD
				r.Text.TextColor3 = ok and NEON or SOFT
			end
			local total = math.max(1, #c2Rows)
			c2Count.Text = F("%d / %d", done, #c2Rows)
			c2Count.TextColor3 = GOLD
			c2Bar:SetColor(GOLD)
			c2Bar:SetValue(done / total)
			head = UT("CHAPTER II IS SEALED")
			body = UT("Finish Chapter I in the Dead Yard to break the seals below the church.")
			if c2Art and c2Art.Set then
				c2Art:Set("Seal", { Size = 48, Dim = 0.45 })
			end
		else
			local o = UV.Objective(cv, now(), { Eligible = true, InZone = below, InTrial = false, Shards = tonumber(player:GetAttribute("BellShards")) or tonumber(cv.Shards) or 0,
				Keys = tonumber(player:GetAttribute("CoffinKeys")) or 0, Near = function()
					return false
				end })
			head, body = UV.ObjectiveText(o, Kit.Lang(), now())
			local cleared = tonumber(cv.Cleared) or 0
			local seals = (UV.Config.Seals and #UV.Config.Seals) or 7
			c2Count.Text = F("%d / %d", cleared, seals)
			c2Count.TextColor3 = NEON
			c2Bar:SetColor(C(150, 200, 255))
			c2Bar:SetValue(cleared / math.max(1, seals))
			if c2Art and c2Art.Set then
				c2Art:Set("Seal", { Size = 48, Glow = C(150, 200, 255) })
			end
		end
		local changed = c2Head.Text ~= (head or "") or c2Body.Text ~= (body or "") or c2State.Key ~= layoutKey or not c2Card.Visible
		c2Head.Text, c2Body.Text = head or "", body or ""
		c2State.Key = layoutKey
		if changed then
			P.Relayout()
		end
	end })

	-- BLOOD MOON
	local moonCard = panel(scroll, "BloodMoon")
	local moonBadge = badge(moonCard, "Icon", "🌕", C(150, 60, 70))
	local moonArt = badgeArt(moonBadge, "Moon", { Size = 48 })
	local function moonIcon(state)
		if moonArt then
			moonArt:Set("Moon", { Size = 48, State = state })
		end
	end
	local moonTitle = sectionTitle(moonCard, "", T("BLOOD MOON"))
	local moonStatus = txt(moonCard, { Name = "Status", Text = "", TextSize = 18, Scaled = true, MinTextSize = 10, Color = SOFT })
	local moonTimer = txt(moonCard, { Name = "Timer", Text = "", TextSize = 30, Scaled = true, MinTextSize = 12, AlignX = "Right", Color = GOLD,
		Font = "numeric", Stroke = 0.3 })
	local moonBar = bar(moonCard, "Progress", BLOOD, 16)
	local perks = Kit.New("Frame", { Name = "Perks", BackgroundTransparency = 1, ZIndex = Z + 1 }, moonCard)
	local perkList = { { "🍬", T("+50% CANDY"), PUMPKIN }, { "🪦", T("HAUNTED DIG SPOTS"), C(120, 60, 160) }, { "🩸", T("BLOOD MOON FINDS"), BLOOD } }
	local perkPills = {}
	for i, p in ipairs(perkList) do
		perkPills[i] = pill(perks, "Perk" .. i, p[1] .. " " .. p[2], p[3])
	end
	table.insert(P.Cards, { Frame = moonCard, Column = 1, Layout = function(w, compact)
		local h = compact and 150 or 136
		local tw = compact and 104 or 150
		place(moonBadge, 16, 16, 48, 48)
		place(moonTitle, 74, 14, w - 74 - tw - 24, 26)
		place(moonStatus, 74, 42, w - 74 - tw - 24, 22)
		place(moonTimer, w - tw - 16, 18, tw, 40)
		place(moonBar.Instance, 16, 76, w - 32, 16)
		local x, y = 0, 0
		for _, p in ipairs(perkPills) do
			local pw = math.ceil(textW(p.Label.Text, 13)) + 18
			if x > 0 and x + pw > w - 32 then
				x, y = 0, y + 30
			end
			p.Instance.Position = UDim2.fromOffset(x, y)
			x += pw + 6
		end
		-- the card grows with the perk rows (long Russian perks wrap to a third row on a phone)
		place(perks, 16, 102, w - 32, y + 26)
		return math.max(h, 102 + y + 26 + 10)
	end, Tick = function()
		local s = moonState()
		local t = now()
		local stateName = s.State
		if stateName == "WARNING" then
			moonStatus.Text = T("RISES IN")
			moonTimer.Text = clock(s.StartTimestamp - t)
			moonTimer.TextColor3 = C(255, 110, 110)
			moonBar:SetColor(BLOOD)
			moonBar:SetValue(1 - math.clamp((s.StartTimestamp - t) / math.max(1, s.StartTimestamp - s.WarningTimestamp), 0, 1), true)
			moonBadge.Glyph.Text = "🌕"
			moonIcon("Blood")
		elseif stateName == "ACTIVE" then
			moonStatus.Text = T("THE BLOOD MOON IS UP! ENDS IN")
			moonTimer.Text = clock(s.ActiveEndTimestamp - t)
			moonTimer.TextColor3 = C(255, 90, 90)
			moonBar:SetColor(BLOOD)
			moonBar:SetValue(math.clamp((s.ActiveEndTimestamp - t) / math.max(1, s.ActiveEndTimestamp - s.StartTimestamp), 0, 1), true)
			moonBadge.Glyph.Text = "🩸"
			moonIcon("Blood")
		elseif stateName == "ENDING" then
			moonStatus.Text = T("THE BLOOD MOON FADES")
			moonTimer.Text = ""
			moonBar:SetValue(0, true)
			moonBadge.Glyph.Text = "🌘"
			moonIcon("Fading")
		else
			moonStatus.Text = T("NEXT BLOOD MOON IN")
			moonTimer.Text = clock((s.WarningTimestamp or t) - t)
			moonTimer.TextColor3 = GOLD
			local period = tonumber(s.Period) or 915
			moonBar:SetColor(PURPLE_HI)
			moonBar:SetValue(1 - math.clamp(((s.WarningTimestamp or t) - t) / period, 0, 1), true)
			moonBadge.Glyph.Text = "🌕"
			moonIcon("Full")
		end
	end })

	-- SERVER EXORCISM
	local exo = panel(scroll, "Exorcism")
	local exoBadge = badge(exo, "Icon", "👻", C(90, 150, 200))
	badgeArt(exoBadge, "Ghost", { Size = 48, Glow = NEON })
	local exoTitle = sectionTitle(exo, "", T("SERVER EXORCISM"))
	local exoSub = txt(exo, { Name = "Sub", Text = T("Every candy and every objective in the Dead Yard banishes souls. Milestones help the whole server."),
		TextSize = 14, Wrap = true, Color = MUTED, AlignY = "Top" })
	local exoCount = txt(exo, { Name = "Count", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = GHOST,
		Font = "numeric", Stroke = 0.3 })
	local exoBar = bar(exo, "Progress", NEON, 22)
	local ticks, stones = {}, {}
	local milestones = (Config.Exorcism and Config.Exorcism.Milestones) or {}
	local MILESTONE_GLYPH = { CandyRush = "🍬", Block = "🎃", Mutation = "🧬", Boss = "💀" }
	local MILESTONE_SHORT = { CandyRush = "SERVER CANDY RUSH", Block = "PUMPKIN BLOCK FOR EXORCISTS", Mutation = "MUTATIONS x2", Boss = "THE GRAVEKEEPER" }
	for i, m in ipairs(milestones) do
		local tick = Kit.New("Frame", { Name = "Tick" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = Z + 4 },
			exoBar.Instance)
		ticks[i] = tick
		local stone = Kit.New("Frame", { Name = "Milestone" .. i, BackgroundTransparency = 1, ZIndex = Z + 1 }, exo)
		local b, g = badge(stone, "Badge", MILESTONE_GLYPH[m.Kind] or "⭐", C(70, 40, 110))
		local mk, mo = S.MilestoneIcon(m.Kind)
		local ma = badgeArt(b, mk, { Size = 36, Glow = mo.Glow, Scale = 0.84 })
		local at = txt(stone, { Name = "At", Text = num(m.At), TextSize = 14, Scaled = true, MinTextSize = 8, Color = GOLD, Font = "numeric" })
		local name = txt(stone, { Name = "Name", Text = T(MILESTONE_SHORT[m.Kind] or m.Name or ""), TextSize = 12, Wrap = true, Color = SOFT, AlignY = "Top" })
		stones[i] = { Frame = stone, Badge = b, Glyph = g, At = at, Name = name, Def = m, Art = ma }
	end
	table.insert(P.Cards, { Frame = exo, Column = 1, Layout = function(w, compact)
		place(exoBadge, 16, 16, 48, 48)
		local cw = compact and 130 or 160
		place(exoTitle, 74, 14, w - 74 - cw - 24, 26)
		place(exoCount, w - cw - 16, 16, cw, 28)
		local subH = textH(exoSub.Text, 14, w - 92)
		place(exoSub, 74, 42, w - 92, subH)
		local barY = math.max(76, 42 + subH + 8)
		place(exoBar.Instance, 16, barY, w - 32, 22)
		local goal = (Config.Exorcism and Config.Exorcism.Goal) or 5000
		for i, tick in ipairs(ticks) do
			local f = math.clamp((milestones[i].At or 0) / goal, 0, 1)
			tick.Visible = f < 0.999
			place(tick, (w - 32) * f - 1, 3, 3, 16)
		end
		local cols = compact and 2 or #stones
		local gap = 10
		local sw = math.floor((w - 32 - gap * (cols - 1)) / math.max(1, cols))
		local y0 = barY + 34
		for i, s in ipairs(stones) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			place(s.Frame, 16 + col * (sw + gap), y0 + row * 60, sw, 54)
			place(s.Badge, 0, 4, 36, 36)
			place(s.At, 42, 0, sw - 42, 18)
			place(s.Name, 42, 18, sw - 42, 34)
			-- two lines at most, and the longest word must fit (ТЫКВЕННЫЙ / СМОТРИТЕЛЬ on a tablet)
			local longest = 0
			for word in string.gmatch(s.Name.Text, "%S+") do
				longest = math.max(longest, textW(word, 12))
			end
			local fit = 12
			while fit > 8 and (textH(s.Name.Text, fit, sw - 42) > 34 or longest * fit / 12 > sw - 42) do
				fit -= 1
			end
			s.Name.TextSize = fit
		end
		local rows = math.ceil(#stones / math.max(1, cols))
		return y0 + rows * 60 + 6
	end, Refresh = function()
		local e = folderAttrs("Exorcism")
		local goal = tonumber(e.Goal) or (Config.Exorcism and Config.Exorcism.Goal) or 5000
		local souls = tonumber(e.Souls) or 0
		local reached = tonumber(e.Milestone) or 0
		exoCount.Text = F("%s / %s", num(souls), num(goal))
		exoBar:SetValue(math.clamp(souls / math.max(1, goal), 0, 1))
		for i, s in ipairs(stones) do
			local done = i <= reached
			local nextOne = i == reached + 1
			s.Glyph.Text = done and "✅" or (MILESTONE_GLYPH[s.Def.Kind] or "⭐")
			if s.Art then
				local mk, mo = S.MilestoneIcon(s.Def.Kind)
				s.Art:Set(done and "Check" or mk, done and { Size = 36 } or { Size = 36, Glow = mo.Glow, Dim = (not nextOne) and 0.3 or nil })
			end
			gradient(s.Badge, (done and NEON or nextOne and PUMPKIN or C(90, 60, 130)):Lerp(WHITE, 0.2), (done and C(40, 140, 60) or nextOne and C(190, 80, 10) or C(50, 26, 80)))
			s.At.TextColor3 = done and NEON or GOLD
		end
	end })

	-- MOON CANDY
	local candyCard = panel(scroll, "Candy", C(110, 54, 30), C(66, 24, 44))
	local candyBadge = badge(candyCard, "Icon", "🍬", PUMPKIN)
	badgeArt(candyBadge, "Candy", { Size = 56, Scale = 0.94 })
	local candyLabel = sectionTitle(candyCard, "", T("MOON CANDY"), PUMPKIN_HI)
	local candyValue = txt(candyCard, { Name = "Value", Text = "0", TextSize = 40, Scaled = true, MinTextSize = 14, Font = "numeric", Stroke = 0.2 })
	local candyInfo = txt(candyCard, { Name = "Info", Text = "", TextSize = 14, Scaled = true, MinTextSize = 9, Color = SOFT })
	local multPill = pill(candyCard, "Mult", "x1", C(60, 30, 90))
	table.insert(P.Cards, { Frame = candyCard, Column = 2, Layout = function(w)
		place(candyBadge, 16, 16, 56, 56)
		local reserve = multPill.Instance.Visible and 170 or 16
		place(candyLabel, 84, 12, w - 84 - reserve, 24)
		place(candyValue, 84, 36, w - 84 - 16, 44)
		place(candyInfo, 16, 84, w - 32, 20)
		multPill.Instance.AnchorPoint = Vector2.new(1, 0)
		multPill.Instance.Position = UDim2.new(1, -14, 0, 14)
		return 114
	end, Refresh = function()
		local v = view()
		candyValue.Text = num(candy())
		candyInfo.Text = F("Lifetime %s  ·  Spent %s", num(v.Lifetime), num(v.Spent))
		local mult = tonumber(player:GetAttribute("HwCandyMult")) or 1
		multPill:Set("⚡ " .. F("x%s CANDY NOW", string.format("%.2g", mult)), mult > 1.01 and C(46, 150, 60) or BLOOD)
		local vis = math.abs(mult - 1) > 0.01
		if multPill.Instance.Visible ~= vis then
			multPill.Instance.Visible = vis
			P.Relayout()
		end
	end })

	-- CURSE
	local curseCard = panel(scroll, "Curse")
	local curseBadge = badge(curseCard, "Icon", "💀", C(120, 60, 170))
	local curseArt = badgeArt(curseBadge, "Skull", { Size = 48, Glow = C(196, 120, 255) })
	local curseLabel = sectionTitle(curseCard, "", T("CURSE"))
	local curseValue = txt(curseCard, { Name = "Value", Text = "0%", TextSize = 24, Scaled = true, MinTextSize = 10, AlignX = "Right", Font = "numeric",
		Stroke = 0.3 })
	local curseBar = bar(curseCard, "Meter", PURPLE_HI, 16)
	local curseInfo = txt(curseCard, { Name = "Info", Text = T("Idling in the Dead Yard raises the curse. Above 80% you earn less candy. Dig, mine and fight to lift it."),
		TextSize = 14, Wrap = true, Color = MUTED, AlignY = "Top" })
	table.insert(P.Cards, { Frame = curseCard, Column = 2, Layout = function(w)
		place(curseBadge, 16, 16, 48, 48)
		place(curseLabel, 74, 14, w - 190, 26)
		place(curseValue, w - 106, 14, 90, 28)
		place(curseBar.Instance, 74, 46, w - 90, 16)
		local ih = textH(curseInfo.Text, 14, w - 32)
		place(curseInfo, 16, 74, w - 32, ih)
		return 74 + ih + 10
	end, Refresh = function()
		local c = math.clamp(tonumber(player:GetAttribute("MoonCurse")) or tonumber(view().Curse) or 0, 0, 100)
		curseValue.Text = math.floor(c + 0.5) .. "%"
		curseBar:SetValue(c / 100)
		local col = PURPLE_HI:Lerp(BLOOD, math.clamp((c - 40) / 60, 0, 1))
		curseBar:SetColor(col)
		curseValue.TextColor3 = c >= 80 and C(255, 110, 110) or WHITE
		curseBadge.Glyph.Text = c >= 70 and "☠️" or "💀"
		if curseArt then
			local stepN = c >= 85 and 4 or c >= 70 and 3 or c >= 40 and 2 or 1
			curseArt:Set("Skull", { Size = 48, Glow = ({ C(196, 120, 255), C(236, 110, 220), C(255, 80, 90), C(255, 40, 40) })[stepN] })
		end
	end })

	-- CANDY RUSH
	local rushCard = panel(scroll, "Rush")
	local rushBadge = badge(rushCard, "Icon", "⚡", C(240, 170, 40))
	badgeArt(rushBadge, "Bolt", { Size = 48 })
	local rushLabel = sectionTitle(rushCard, "", T("CANDY RUSH x2"))
	local rushInfo = txt(rushCard, { Name = "Info", Text = T("Double candy for 10 minutes of active play. Once a day."), TextSize = 14, Wrap = true,
		Color = MUTED, AlignY = "Top" })
	local rushStatus = txt(rushCard, { Name = "Status", Text = "", TextSize = 18, Scaled = true, MinTextSize = 10, Color = GOLD, Font = "numeric" })
	local rushBtn
	rushBtn = button(rushCard, { Name = "Start", Text = T("START RUSH"), Color = PUMPKIN, TextSize = 17, OnClick = function()
		act(rushBtn, "RushStart", {}, function()
			audio("RushStart")
		end, T("CANDY RUSH x2 STARTED"))
	end })
	local serverRush = pill(rushCard, "ServerRush", "", C(46, 150, 60))
	table.insert(P.Cards, { Frame = rushCard, Column = 2, Layout = function(w)
		place(rushBadge, 16, 16, 48, 48)
		place(rushLabel, 74, 14, w - 90, 26)
		local ih = textH(rushInfo.Text, 14, w - 90)
		place(rushInfo, 74, 42, w - 90, ih)
		local y = math.max(78, 42 + ih + 6)
		local bw = math.min(160, math.floor((w - 32) * 0.45))
		place(rushStatus, 16, y + 6, w - bw - 44, 30)
		place(rushBtn.Instance, w - bw - 16, y, bw, 42)
		serverRush.Instance.Position = UDim2.fromOffset(16, y + 48)
		return y + (serverRush.Instance.Visible and 82 or 54)
	end, Tick = function()
		local v = view()
		local r = v.Rush or {}
		local active = player:GetAttribute("HwRushActive")
		if active == nil then
			active = r.Active == true
		end
		local remaining = tonumber(player:GetAttribute("HwRushRemaining")) or tonumber(r.Remaining) or 0
		local max = tonumber(r.Max) or (Config.CandyRush and Config.CandyRush.Seconds) or 600
		if active and remaining > 0 then
			rushStatus.Text = F("ACTIVE · %s LEFT", clock(remaining))
			rushStatus.TextColor3 = NEON
			rushBtn.Instance.Visible = false
		elseif remaining <= 0 and r.Remaining ~= nil then
			rushStatus.Text = F("USED TODAY · NEW IN %s", clock(tonumber(v.ResetIn) and (86400 - now() % 86400) or 0))
			rushStatus.TextColor3 = MUTED
			rushBtn.Instance.Visible = false
		else
			rushStatus.Text = F("READY · %s", clock(remaining > 0 and remaining or max))
			rushStatus.TextColor3 = GOLD
			rushBtn.Instance.Visible = true
		end
		local sr = tonumber(stateFolder() and stateFolder():GetAttribute("ServerRushUntil")) or 0
		local wasVisible = serverRush.Instance.Visible
		serverRush.Instance.Visible = sr > now()
		if sr > now() then
			serverRush:Set("🍬 " .. F("SERVER RUSH x2 · %s", clock(sr - now())))
		end
		if wasVisible ~= serverRush.Instance.Visible then
			P.Relayout()
		end
	end })

	-- TONIGHT: the next things to do, each a shortcut to its tab
	local tonight = panel(scroll, "Tonight")
	local tonightTitle = sectionTitle(tonight, "🌙", T("TONIGHT"))
	local tRows = {}
	for i, def in ipairs({ { "📜", "quests" }, { "🚪", nil }, { "🧪", "cauldron" }, { "💀", "boss" } }) do
		local row = Kit.New("TextButton", { Name = "Row" .. i, Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = C(30, 12, 46),
			BackgroundTransparency = 0.35, ZIndex = Z + 1 }, tonight)
		Kit.Corner(row, 10)
		local glyph = txt(row, { Name = "Glyph", Text = def[1], TextSize = 20, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = Z + 2 })
		art(glyph, ({ "Scroll", "Door", "Cauldron", "Skull" })[i], { Size = 24, ZIndex = Z + 3, FrameSize = UDim2.fromScale(1.15, 1.15),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) }, glyph)
		local label = txt(row, { Name = "Label", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, Color = SOFT, ZIndex = Z + 2 })
		local arrow = txt(row, { Name = "Go", Text = def[2] and "›" or "", TextSize = 24, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = PUMPKIN_HI,
			ZIndex = Z + 2 })
		if def[2] then
			row:SetAttribute("KitSound", "Tab")
			row.Activated:Connect(function()
				if win then
					win:SetTab(def[2])
				end
			end)
		end
		tRows[i] = { Frame = row, Glyph = glyph, Label = label, Arrow = arrow }
	end
	table.insert(P.Cards, { Frame = tonight, Column = 2, Layout = function(w)
		place(tonightTitle, 16, 12, w - 32, 24)
		for i, r in ipairs(tRows) do
			place(r.Frame, 12, 42 + (i - 1) * 38, w - 24, 32)
			place(r.Glyph, 6, 4, 24, 24)
			place(r.Label, 38, 4, w - 24 - 38 - 34, 24)
			place(r.Arrow, w - 24 - 30, 2, 24, 28)
		end
		return 42 + #tRows * 38 + 6
	end, Refresh = function()
		local v = view()
		local list = v.Quests and v.Quests.List or {}
		local done = 0
		for _, q in ipairs(list) do
			if q.Claimed then
				done += 1
			end
		end
		tRows[1].Label.Text = F("Daily quests claimed: %d / %d", done, #list)
		local knocked = 0
		for _ in pairs(v.Houses and v.Houses.Knocked or {}) do
			knocked += 1
		end
		local houses = (Config.TrickOrTreat and Config.TrickOrTreat.Houses) or 7
		tRows[2].Label.Text = F("Doors knocked today: %d / %d", knocked, houses)
		local c = v.Cauldron or {}
		local levels = (Config.Cauldron and Config.Cauldron.Levels) or {}
		local lv = tonumber(c.Level) or 1
		tRows[3].Label.Text = F("Cauldron level %d · %s", lv, T(levels[lv] and levels[lv].Name or ""))
		local unlocked = tonumber(player:GetAttribute("HwBossUnlocked")) or (v.Boss and v.Boss.Unlocked) or 1
		local diffs = (Config.Boss and Config.Boss.Difficulties) or {}
		tRows[4].Label.Text = F("Gravekeeper: up to %s unlocked", (diffs[unlocked] and diffs[unlocked].Numeral) or tostring(unlocked))
	end })

	-- MAIN MAP DECOR toggle (MainMapLayer reads player attribute HwMapDecor)
	local decor = panel(scroll, "Decor", C(52, 26, 78), C(40, 18, 60))
	local decorLabel = txt(decor, { Name = "Label", Text = "🦇  " .. T("HALLOWEEN DECOR ON THE MAIN MAP"), TextSize = 15, Scaled = true, MinTextSize = 9,
		Color = SOFT })
	local decorBtn
	decorBtn = button(decor, { Name = "Toggle", Text = "", Style = "secondary", TextSize = 15, OnClick = function()
		player:SetAttribute("HwMapDecor", player:GetAttribute("HwMapDecor") == false)
		P.Refresh()
	end })
	decorBtn.Instance:SetAttribute("KitSound", "Toggle")
	table.insert(P.Cards, { Frame = decor, Column = 1, Layout = function(w)
		place(decorLabel, 16, 10, w - 140, 36)
		place(decorBtn.Instance, w - 112, 9, 96, 38)
		return 56
	end, Refresh = function()
		local on = player:GetAttribute("HwMapDecor") ~= false
		decorBtn:SetText(on and T("ON") or T("OFF"))
		decorBtn:SetStyle(on and "success" or "secondary")
	end })

	function P.Layout(L)
		local w = L.Width
		local compact = L.Phone
		local two = w >= 700
		local gap = compact and 10 or 12
		local pad = 2
		local colW = two and { math.floor((w - gap - pad * 2 - 8) * 0.58), 0 } or { w - pad * 2 - 8 }
		if two then
			colW[2] = w - pad * 2 - 8 - gap - colW[1]
		end
		local y = { pad, pad }
		for _, card in ipairs(P.Cards) do
			local col = two and card.Column or 1
			local cw = colW[col]
			local h = card.Layout(cw, compact or not two)
			if card.Frame.Visible then -- a card can hide itself (CHAPTER II while Chapter II is switched off)
				local x = pad + (col == 2 and (colW[1] + gap) or 0)
				place(card.Frame, x, y[col], cw, h)
				y[col] += h + gap
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, math.max(y[1], y[2] or 0) + 4)
	end
	function P.Relayout()
		if win then
			P.Layout(win:GetLayout())
		end
	end
	function P.Refresh()
		for _, card in ipairs(P.Cards) do
			if card.Refresh then
				card.Refresh()
			end
			if card.Tick then
				card.Tick()
			end
		end
	end
	function P.Tick()
		for _, card in ipairs(P.Cards) do
			if card.Tick then
				card.Tick()
			end
		end
	end
	return P
end

---------------------------------------------------------------------------- QUESTS
local QUEST_GLYPH = { DigSpots = "🪦", Perfect = "✨", EarnCandy = "🍬", BloodMoon = "🌕", BossDamage = "💀", OpenPumpkin = "🎃",
	FindMutation = "🧬", MineOre = "⛏️", Knock = "🚪" }
local QUEST_COLOR = { DigSpots = C(130, 70, 190), Perfect = C(90, 160, 230), EarnCandy = PUMPKIN, BloodMoon = BLOOD, BossDamage = C(110, 110, 130),
	OpenPumpkin = C(230, 120, 30), FindMutation = C(80, 190, 120), MineOre = C(150, 110, 80), Knock = C(170, 90, 60) }

local function questText(q: any): string
	local text = q.Text or q.Id or "?"
	if string.find(text, "%%d") then
		return F(text, q.Goal or 0)
	end
	return T(text)
end
S.QuestText = questText

pages.quests = function(page: Frame)
	local P = {}
	local scroll = scrollPage(page)
	local head = panel(scroll, "Header", C(86, 40, 120), C(54, 22, 84))
	local headTitle = sectionTitle(head, "📜", T("DAILY QUESTS"))
	local headReset = txt(head, { Name = "Reset", Text = "", TextSize = 15, Scaled = true, MinTextSize = 9, Color = MUTED })
	local bonusBox = panel(head, "Bonus", C(120, 60, 30), C(80, 30, 40), Z + 1)
	local bonusTitle = txt(bonusBox, { Name = "Title", Text = T("ALL QUESTS BONUS"), TextSize = 15, Scaled = true, MinTextSize = 9, Color = PUMPKIN_HI,
		ZIndex = Z + 2 })
	local bonusChips = Kit.New("Frame", { Name = "Chips", BackgroundTransparency = 1, ZIndex = Z + 2 }, bonusBox)
	local bonusBtn
	bonusBtn = button(bonusBox, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 16, ZIndex = Z + 3, OnClick = function()
		act(bonusBtn, "QuestBonus", {}, function(res)
			rewardsDialog(T("DAILY BONUS"), res and res.Rewards, { Kicker = T("ALL QUESTS DONE") })
		end, "")
	end })
	local rows = {}
	for i = 1, 8 do
		local card = panel(scroll, "Quest" .. i)
		card.Visible = false
		local icon, glyph = badge(card, "Icon", "⭐", PURPLE)
		Kit.Corner(icon, 12)
		local title = txt(card, { Name = "Title", Text = "", TextSize = 18, Scaled = true, MinTextSize = 10, Stroke = 0.5 })
		local progress = bar(card, "Progress", NEON, 18)
		local chips = Kit.New("Frame", { Name = "Rewards", BackgroundTransparency = 1, ZIndex = Z + 1 }, card)
		local claim
		claim = button(card, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 17, OnClick = function()
			local q = rows[i].Quest
			if not q then
				return
			end
			act(claim, "QuestClaim", { Id = q.Id }, function(res)
				audio("Claim")
				local parts = {}
				if res and (res.Candy or 0) > 0 then
					table.insert(parts, "+" .. num(res.Candy) .. " 🍬")
				end
				if res and (res.Bones or 0) > 0 then
					table.insert(parts, "+" .. num(res.Bones) .. " 🦴")
				end
				if #parts > 0 then
					Kit.Toast(T("QUEST REWARD") .. "  " .. table.concat(parts, "  "), { Kind = "success", NoTranslate = true, Sound = false })
				end
			end, "")
		end })
		rows[i] = { Frame = card, Icon = icon, Glyph = glyph, Title = title, Bar = progress, Chips = chips, Claim = claim }
	end
	local empty = txt(scroll, { Name = "Empty", Text = T("Loading quests..."), TextSize = 18, AlignX = "Center", Color = MUTED, Visible = false })
	P.Rows = rows

	-- ALL QUESTS bonus reward chips
	function P.BonusRows(): { any }
		local bonus = (Config.Quests and Config.Quests.AllBonus) or {}
		local out = {}
		if bonus.Candy then
			table.insert(out, { Kind = "Candy", Amount = bonus.Candy })
		end
		if bonus.Kind then
			table.insert(out, bonus)
		end
		return out
	end

	local lastW, compactFlag = 600, false
	function P.Layout(L)
		local w = L.Width - 12
		lastW, compactFlag = w, L.Phone
		local compact = L.Phone
		local narrow = w < 560
		local y = 2
		local headH = narrow and 150 or 92
		place(head, 2, y, w, headH)
		place(headTitle, 16, 12, narrow and w - 32 or w * 0.45, 28)
		place(headReset, 18, 44, narrow and w - 32 or w * 0.45, 22)
		local bw = narrow and w - 24 or math.min(470, w * 0.52)
		local btnW = narrow and 104 or 120
		local chipW = bw - 12 - btnW - 20
		P.BonusChipW, P.BonusChipH = chipW, narrow and 24 or 26
		-- the chips wrap onto a second line when they do not fit (long Russian block name): the box grows
		local chH = chipRow(bonusChips, P.BonusRows(), chipW, P.BonusChipH)
		local boxH = math.max(narrow and 68 or 72, 32 + chH + 8)
		if narrow then
			headH = 72 + boxH + 10
			place(head, 2, y, w, headH)
		end
		place(bonusBox, narrow and 12 or w - bw - 12, narrow and 72 or 10, bw, boxH)
		place(bonusTitle, 12, 6, chipW, 20)
		place(bonusChips, 12, 32, chipW, chH)
		place(bonusBtn.Instance, bw - btnW - 12, boxH / 2 - 22, btnW, 44)
		y += headH + 12
		local rowH = narrow and 132 or 92
		for _, r in ipairs(rows) do
			if r.Frame.Visible then
				place(r.Frame, 2, y, w, rowH)
				local iconS = narrow and 52 or 64
				place(r.Icon, 14, narrow and 14 or (rowH - iconS) / 2, iconS, iconS)
				local tx = 14 + iconS + 14
				local claimW = narrow and 132 or 150
				r.ClaimW = claimW
				local mid = w - tx - claimW - 28
				place(r.Title, tx, narrow and 12 or 12, narrow and w - tx - 14 or mid, 26)
				place(r.Bar.Instance, tx, narrow and 46 or 46, narrow and w - tx - 14 or mid * 0.62, 20)
				local chipX = narrow and tx or tx + mid * 0.62 + 12
				local chipW = narrow and (w - tx - claimW - 28) or mid * 0.38 - 12
				place(r.Chips, chipX, narrow and 84 or 44, chipW, 26)
				r.ChipW = chipW
				place(r.Claim.Instance, w - claimW - 14, narrow and 78 or (rowH - 46) / 2, claimW, 46)
				y += rowH + 10
			end
		end
		place(empty, 2, y + 20, w, 30)
		scroll.CanvasSize = UDim2.fromOffset(0, y + 8)
		local _ = compact
	end
	function P.Refresh()
		local v = view()
		local list = v.Quests and v.Quests.List or {}
		local allClaimed = #list > 0
		local changed = false
		for i, r in ipairs(rows) do
			local q = list[i]
			r.Quest = q
			local vis = q ~= nil
			if r.Frame.Visible ~= vis then
				r.Frame.Visible = vis
				changed = true
			end
			if q then
				r.Glyph.Text = QUEST_GLYPH[q.Id] or "⭐"
				local col = QUEST_COLOR[q.Id] or PURPLE
				gradient(r.Icon, col:Lerp(WHITE, 0.25), col:Lerp(INK, 0.3))
				r.Title.Text = questText(q)
				local done = (q.Progress or 0) >= (q.Goal or 1)
				r.Bar:SetValue(math.clamp((q.Progress or 0) / math.max(1, q.Goal or 1), 0, 1))
				r.Bar:SetText(F("%s / %s", num(q.Progress), num(q.Goal)))
				r.Bar:SetColor(done and NEON or PUMPKIN)
				local rewards = { { Kind = "Candy", Amount = q.Candy or (Config.Candy and Config.Candy.Quest and Config.Candy.Quest[1]) or 25 } }
				if q.Bones then
					table.insert(rewards, { Kind = "Bones", Amount = q.Bones })
				end
				chipRow(r.Chips, rewards, r.ChipW or 200, 26)
				if q.Claimed then
					local label = "✓ " .. T("CLAIMED")
					r.Claim:SetText(textW(label, 16) <= (r.ClaimW or 150) - 26 and label or T("CLAIMED"))
					r.Claim:SetStyle("secondary")
					r.Claim:SetDisabled(true)
				elseif done then
					r.Claim:SetText(T("CLAIM"))
					r.Claim:SetStyle("success")
					r.Claim:SetDisabled(false)
				else
					r.Claim:SetText(T("IN PROGRESS"))
					r.Claim:SetStyle("secondary")
					r.Claim:SetDisabled(true)
				end
				allClaimed = allClaimed and q.Claimed == true
			end
		end
		empty.Visible = #list == 0
		chipRow(bonusChips, P.BonusRows(), P.BonusChipW or 320, P.BonusChipH or 26)
		local claimed = v.Quests and v.Quests.AllClaimed
		if claimed then
			bonusBtn:SetText("✓ " .. T("CLAIMED"))
			bonusBtn:SetStyle("secondary")
			bonusBtn:SetDisabled(true)
		else
			bonusBtn:SetText(T("CLAIM"))
			bonusBtn:SetStyle(allClaimed and "success" or "secondary")
			bonusBtn:SetDisabled(not allClaimed)
		end
		if changed then
			P.Layout({ Width = lastW + 12, Phone = compactFlag })
		end
	end
	function P.Tick()
		headReset.Text = F("NEW QUESTS IN %s", clock(86400 - now() % 86400))
	end
	return P
end

---------------------------------------------------------------------------- EVENT DOGDEX
local function registerDogPreview()
	if S.PreviewKind then
		return S.PreviewKind
	end
	S.PreviewKind = "HwDog"
	Kit.Preview.Register("HwDog", function(spec, parent)
		local id = spec.DogId
		-- 1. the game's dog renderer (ReplicatedStorage.MenuModels[id], WP4 adds the event dogs there)
		local models = RS:FindFirstChild("MenuModels")
		if models and models:FindFirstChild(id) then
			local okR, renderer = pcall(require, script.Parent.PreviewRenderer)
			if okR and renderer and renderer.Dog then
				local okD, view = pcall(renderer.Dog, parent, { DogId = id }, 0, 0, 128, 128, spec.Silhouette == true)
				if okD and view then
					return view
				end
			end
		end
		-- 2. the shared event-dog builders (RS.Halloween.Models.EventDogs.Build; the Underyard dogs H09-H16: EventDogs2)
		local folder = Halloween and Halloween:FindFirstChild("Models")
		local chapter2 = UV ~= nil and UV.Config.Dogs and UV.Config.Dogs.Defs[id] ~= nil
		local okB, model = false, nil
		for _, name in ipairs(chapter2 and { "EventDogs2", "EventDogs" } or { "EventDogs" }) do
			local mod = folder and folder:FindFirstChild(name)
			if mod and not (okB and typeof(model) == "Instance") then
				local okM, Dogs = pcall(require, mod)
				if okM and type(Dogs) == "table" and Dogs.Build then
					okB, model = pcall(Dogs.Build, id)
				end
			end
		end
		do
			if okB and typeof(model) == "Instance" then
				local vp = Kit.New("ViewportFrame", { Name = "Preview", BackgroundTransparency = 1, Ambient = C(170, 150, 210), LightColor = C(255, 230, 200),
					LightDirection = Vector3.new(-1, -1, -0.6), Size = UDim2.fromScale(1, 1) })
				if spec.Silhouette then
					vp.ImageColor3 = Color3.new(0, 0, 0)
				end
				local cam = Instance.new("Camera")
				cam.FieldOfView = 30
				cam.Parent = vp
				vp.CurrentCamera = cam
				model.Parent = vp
				local okBox, cf, size = pcall(function()
					return (model :: any):GetBoundingBox()
				end)
				if okBox then
					local radius = size.Magnitude / 2
					local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
					local dir = Vector3.new(-0.62, 0.32, -0.72).Unit -- dogs face -Z: a 3/4 front view
					cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
				end
				vp.Parent = parent
				return vp
			end
		end
		-- 3. a glyph
		local code = Config.Dogs and Config.Dogs.Defs and Config.Dogs.Defs[id] and Config.Dogs.Defs[id].Code
			or (UV and UV.Config.Dogs and UV.Config.Dogs.Defs[id] and UV.Config.Dogs.Defs[id].Code) or "?"
		local l = txt(parent, { Name = "Preview", Text = spec.Silhouette and "❔" or "🐶", TextSize = 64, Scaled = true, MinTextSize = 10, AlignX = "Center" })
		l:SetAttribute("HwCode", code)
		return l
	end, function(spec)
		return tostring(spec.DogId) .. "|" .. (spec.Silhouette and "S" or "")
	end)
	return S.PreviewKind
end

-- the two event collections of the dex tab (CHAPTER I / CHAPTER II switch, WP-L):
--   BURIED MOON 2026            Config.Dogs + Config.DexRewards, the Halloween view's Dex / DexCount / DexClaims, request DexClaim
--   THE UNDERYARD COLLECTION    Chapter2Config.Dogs + .Dex2Rewards, view.Chapter2.Dex2, request C2DexClaim
local function dexSets(): { any }
	local sets = {}
	local rewards1 = {}
	for _, row in ipairs(Config.DexRewards or {}) do
		local rows = {}
		if row.Candy then
			table.insert(rows, { Kind = "Candy", Amount = row.Candy })
		end
		if row.Bones then
			table.insert(rows, { Kind = "Bones", Amount = row.Bones })
		end
		if row.Block then
			table.insert(rows, { Kind = "Block", Id = row.Block, Amount = 1 })
		end
		if row.Skin then
			table.insert(rows, { Kind = "Skin", Id = row.Skin })
		end
		-- the 8/8 title is granted with the reward but is not a reply row: shown as its own pill, added to the card
		table.insert(rewards1, { Count = row.Count, Rows = rows, TitlePill = row.Title and ("👑 " .. T("BURIED MOON SURVIVOR")) or nil,
			Extra = row.Title and { Kind = "Title", Id = row.Title } or nil })
	end
	sets[1] = {
		Id = "BuriedMoon", Switch = "CHAPTER I", Order = (Config.Dogs and Config.Dogs.Order) or {}, Defs = (Config.Dogs and Config.Dogs.Defs) or {},
		Rewards = rewards1, Accent = NEON, Title = T("BURIED MOON 2026"),
		Info = T("Event dogs come from Pumpkin Lucky Blocks, the Gravekeeper and the cauldron brew. They stay yours after the event."),
		Secret = T("A secret dog of the Buried Moon. Only the luckiest ever see it."), Action = "DexClaim", Kicker = T("COLLECTION REWARD"),
		Name = function(id: string, _def: any): string
			return dogName(id)
		end,
		Ability = function(_id: string, def: any): string
			return T(def.Signature or "")
		end,
		Data = function(v: any): (any, number?, any)
			return v.Dex or {}, tonumber(v.DexCount), v.DexClaims or {}
		end,
		RevealTitle = function(n: number): string
			return F("%d EVENT DOGS FOUND", n)
		end,
		OpenDex = function()
			(S :: any).OpenDogDex()
		end,
	}
	local c2 = UV and UV.Config
	if c2 and c2.Dogs and Shared and Shared.Chapter2Enabled and Shared.Chapter2Enabled() then
		local own = UV.Dicts().Own
		local rewards2 = {}
		for _, tier in ipairs(c2.Dex2Rewards or {}) do
			table.insert(rewards2, { Count = tier.Count, Rows = table.clone(tier.Rows or {}) })
		end
		sets[2] = {
			Id = "Underyard", Switch = "CHAPTER II", Order = c2.Dogs.Order or {}, Defs = c2.Dogs.Defs or {}, Rewards = rewards2,
			Accent = C(150, 200, 255), Title = UT("THE UNDERYARD COLLECTION"),
			Info = UT("Eight dogs live below the last bell: seals, the Black Coffin, the Gravekeeper's last stand and one hidden room hold them."),
			Secret = UT("A secret of the Underyard. Only a crowned few ever see it."), Action = "C2DexClaim", Kicker = UT("DEX II REWARD"),
			Name = function(_id: string, def: any): string
				return UL(def.Name)
			end,
			Ability = function(id: string, _def: any): string
				local info = own and own.Dogs and own.Dogs[id]
				return info and (upper(UL(info.Ability)) .. ": " .. UL(info.Text)) or ""
			end,
			Data = function(v: any): (any, number?, any)
				local d = (v.Chapter2 and v.Chapter2.Dex2) or {}
				return d.Dex or {}, tonumber(d.Count), d.Claims or {}
			end,
			RevealTitle = function(n: number): string
				return UF("%d UNDERYARD DOGS FOUND", n)
			end,
			OpenDex = function()
				local mod = script.Parent:FindFirstChild("UnderyardScreen")
				local ok, U = false, nil
				if mod then
					ok, U = pcall(require, mod)
				end
				if ok and type(U) == "table" and U.OpenDogDex then
					U.OpenDogDex()
				else
					(S :: any).OpenDogDex()
				end
			end,
		}
	end
	return sets
end

pages.dex = function(page: Frame)
	local P: any = { Chapter = 1 }
	local scroll = scrollPage(page)
	local kind = registerDogPreview()
	local defsList = dexSets()

	-- one collection inside its own container (the switch shows one at a time)
	local function buildSet(set: any): any
		local box = Kit.New("Frame", { Name = "Dex_" .. set.Id, BackgroundTransparency = 1, ZIndex = Z }, scroll)
		local head = panel(box, "Progress", C(86, 40, 120), C(54, 22, 84))
		local headTitle = sectionTitle(head, "📖", set.Title)
		local headCount = txt(head, { Name = "Count", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Right", Color = set.Accent,
			Font = "numeric", Stroke = 0.3 })
		local headBar = bar(head, "Bar", set.Accent, 18)
		local headInfo = txt(head, { Name = "Info", Text = set.Info, TextSize = 14, Wrap = true, Color = MUTED, AlignY = "Top" })
		local openDex = button(head, { Name = "OpenDex", Text = "📖 " .. T("OPEN DOGDEX"), Style = "secondary", TextSize = 15, OnClick = function()
			set.OpenDex()
		end })

		local track = panel(box, "Rewards")
		local trackTitle = sectionTitle(track, "🏆", T("COLLECTION REWARDS"))
		local nodes = {}
		for i, tier in ipairs(set.Rewards) do
			local node = Kit.New("Frame", { Name = "Reward" .. i, BorderSizePixel = 0, BackgroundColor3 = C(30, 12, 46), BackgroundTransparency = 0.35,
				ZIndex = Z + 1 }, track)
			Kit.Corner(node, 12)
			local circle, glyph = badge(node, "Count", tostring(tier.Count), C(80, 50, 120))
			local chips = Kit.New("Frame", { Name = "Chips", BackgroundTransparency = 1, ZIndex = Z + 1 }, node)
			local claim
			claim = button(node, { Name = "Claim", Text = T("CLAIM"), Style = "success", TextSize = 12, OnClick = function()
				act(claim, set.Action, { Count = tier.Count }, function(res)
					local got = table.clone((res and type(res.Rewards) == "table") and res.Rewards or {})
					local extra = tier.Extra
					if not extra then
						for _, row in ipairs(tier.Rows) do
							if row.Kind == "Title" then
								extra = row
							end
						end
					end
					if extra then
						local has = false
						for _, row in ipairs(got) do
							if row.Kind == "Title" then
								has = true
							end
						end
						if not has then
							table.insert(got, table.clone(extra))
						end
					end
					rewardsDialog(set.RevealTitle(tier.Count), got, { Kicker = set.Kicker })
				end, "")
			end })
			local rows = {}
			for _, row in ipairs(tier.Rows) do
				if not (tier.TitlePill and row.Kind == "Title") then
					table.insert(rows, row)
				end
			end
			nodes[i] = { Frame = node, Circle = circle, Glyph = glyph, Chips = chips, Claim = claim, Row = tier, Rewards = rows, TitlePill = tier.TitlePill }
		end

		local cards = {}
		for i, id in ipairs(set.Order) do
			local def = set.Defs[id] or {}
			local card = panel(box, "Dog_" .. id)
			local holder = Kit.New("Frame", { Name = "PreviewHolder", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 1, ClipsDescendants = true }, card)
			Kit.Corner(holder, 12)
			gradient(holder, C(112, 70, 160), C(44, 20, 72)) -- moonlit: the black silhouette of an undiscovered dog reads on it
			local slot = Kit.Preview.Slot(holder)
			local code = pill(card, "Code", def.Code or ("H0" .. i), C(30, 14, 46))
			local rarityName = Shared and select(1, Shared.Rarity(def.Rank or 2)) or "Rare"
			local rarity = Kit.Pill(card, { Name = "Rarity", Text = T(string.upper(rarityName)), Color = RARITY[rarityName] or PURPLE, Height = 22, TextSize = 12,
				NoTranslate = true, ZIndex = Z + 2 })
			local grad = Theme.RarityGradient[rarityName]
			if grad then
				rarity:SetGradient(grad[1], grad[2])
			end
			local name = txt(card, { Name = "Name", Text = "", TextSize = 17, Scaled = true, MinTextSize = 10, AlignX = "Center", Stroke = 0.4 })
			local ability = txt(card, { Name = "Ability", Text = "", TextSize = 12, Wrap = true, AlignX = "Center", AlignY = "Top", Color = SOFT })
			local status = txt(card, { Name = "Status", Text = "", TextSize = 12, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED })
			cards[i] = { Id = id, Def = def, Frame = card, Holder = holder, Slot = slot, Code = code, Rarity = rarity, Name = name, Ability = ability, Status = status,
				Secret = (def.Rank or 0) >= 6 or def.Secret == true }
		end

		-- the reward list (circle, reward chips, CLAIM) at width w; returns its height
		local function layoutTrack(x: number, y: number, w: number): number
			place(trackTitle, 16, 12, w - 32, 26)
			local ny = 46
			for _, n in ipairs(nodes) do
				local chipW = w - 24 - 62 - 118
				local h = chipRow(n.Chips, table.clone(n.Rewards), chipW, 24)
				if n.TitlePill then
					local tp = Kit.Pill(n.Chips, { Name = "Title", Text = n.TitlePill, Color = GOLD, Height = 24, TextSize = 12, PadX = 9,
						NoTranslate = true, ZIndex = Z + 3 })
					tp.Instance.Position = UDim2.fromOffset(0, h + 6)
					h += 30
				end
				local nh = math.max(60, h + 16)
				place(n.Frame, 12, ny, w - 24, nh)
				place(n.Circle, 8, nh / 2 - 22, 44, 44)
				place(n.Chips, 62, 8, chipW, nh - 16)
				place(n.Claim.Instance, w - 24 - 112, nh / 2 - 19, 104, 38)
				ny += nh + 8
			end
			place(track, x, y, w, ny + 6)
			return ny + 6
		end

		local S2 = { Box = box, Set = set, Ready = 0 }
		-- lays the collection out at width L.Width - 12; returns its height
		function S2.Layout(L: any): number
			local w = L.Width - 12
			if w < 60 then
				return 0
			end
			local wide = w >= 900
			local gridX, gridW, gridY = 2, w, 0
			local rw = wide and 360 or w
			local infoH = math.max(36, textH(headInfo.Text, 14, rw - 32))
			local headH = math.max(wide and 176 or 166, 74 + infoH + 62)
			local sideBottom
			if wide then
				gridW = w - rw - 12
				gridX = 2
				local rx = 2 + gridW + 12
				place(head, rx, 2, rw, headH)
				local th = layoutTrack(rx, 2 + headH + 12, rw)
				gridY = 2
				sideBottom = 2 + headH + 12 + th
			else
				place(head, 2, 2, w, headH)
				local th = layoutTrack(2, 2 + headH + 12, w)
				gridY = 2 + headH + 12 + th + 12
				sideBottom = gridY
			end
			local hw = head.Size.X.Offset
			place(headTitle, 16, 12, hw - 136, 26)
			place(headCount, hw - 110, 12, 94, 28)
			place(headBar.Instance, 16, 48, hw - 32, 18)
			place(headInfo, 16, 74, hw - 32, infoH)
			place(openDex.Instance, 16, head.Size.Y.Offset - 50, math.min(220, hw - 32), 38)
			local cols = gridW >= 700 and 4 or gridW >= 520 and 3 or 2
			local gap = 12
			local cw = math.floor((gridW - gap * (cols - 1)) / cols)
			local ph = math.floor(cw * (cols == 2 and 0.62 or 0.6))
			local abilityH = 66
			for _, c in ipairs(cards) do
				abilityH = math.max(abilityH, textH(set.Ability(c.Id, c.Def), 12, cw - 16))
				if c.Secret then
					abilityH = math.max(abilityH, textH(set.Secret, 12, cw - 16))
				end
			end
			local ch = ph + 62 + abilityH
			for i, c in ipairs(cards) do
				local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
				place(c.Frame, gridX + col * (cw + gap), gridY + row * (ch + gap), cw, ch)
				place(c.Holder, 8, 8, cw - 16, ph)
				c.Code.Instance.Position = UDim2.fromOffset(14, 14)
				c.Rarity.Instance.AnchorPoint = Vector2.new(1, 0)
				c.Rarity.Instance.Position = UDim2.new(1, -14, 0, 14)
				place(c.Name, 8, ph + 12, cw - 16, 22)
				place(c.Ability, 8, ph + 36, cw - 16, abilityH)
				place(c.Status, 8, ch - 22, cw - 16, 16)
			end
			local rows = math.ceil(#cards / cols)
			local bottom = gridY + rows * (ch + gap)
			return math.max(bottom, sideBottom or 0)
		end
		function S2.Refresh()
			local dex, count, claims = set.Data(view())
			local found = 0
			for _, c in ipairs(cards) do
				local has = dex[c.Id] == true
				if has then
					found += 1
				end
				c.Slot:Show({ Kind = kind, DogId = c.Id, Silhouette = not has })
				local hidden = c.Secret and not has
				c.Name.Text = hidden and "???" or set.Name(c.Id, c.Def)
				c.Name.TextColor3 = has and WHITE or MUTED
				c.Ability.Text = hidden and set.Secret or set.Ability(c.Id, c.Def)
				c.Status.Text = has and ("✅ " .. T("DISCOVERED")) or ("🔒 " .. T("NOT FOUND YET"))
				c.Status.TextColor3 = has and set.Accent or MUTED
				local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
				if stroke then
					stroke.Color = has and set.Accent or PANEL_EDGE
					stroke.Transparency = has and 0.2 or 0.15
				end
			end
			local total = #cards
			count = count or found
			headCount.Text = F("%d / %d", count, total)
			headBar:SetValue(total > 0 and count / total or 0)
			local ready = 0
			for _, n in ipairs(nodes) do
				local tier = n.Row
				local claimed = claims[tostring(tier.Count)] == true
				local can = count >= tier.Count and not claimed
				if can then
					ready += 1
				end
				gradient(n.Circle, (claimed and NEON or can and PUMPKIN or C(90, 60, 130)):Lerp(WHITE, 0.2), claimed and C(40, 140, 60) or can and C(190, 80, 10) or C(50, 26, 80))
				n.Glyph.Text = claimed and "✓" or tostring(tier.Count)
				if claimed then
					n.Claim:SetText(T("CLAIMED")) -- the circle already shows ✓
					n.Claim:SetStyle("secondary")
					n.Claim:SetDisabled(true)
				elseif can then
					n.Claim:SetText(T("CLAIM"))
					n.Claim:SetStyle("success")
					n.Claim:SetDisabled(false)
				else
					n.Claim:SetText("🔒 " .. F("%d / %d", math.min(count, tier.Count), tier.Count))
					n.Claim:SetStyle("secondary")
					n.Claim:SetDisabled(true)
				end
			end
			S2.Ready = ready
		end
		return S2
	end

	local sets = {}
	for i, def in ipairs(defsList) do
		sets[i] = buildSet(def)
	end
	P.Sets = sets

	-- CHAPTER I / CHAPTER II (only while Chapter II is on)
	local switch = Kit.New("Frame", { Name = "ChapterSwitch", BorderSizePixel = 0, BackgroundColor3 = C(30, 12, 46), BackgroundTransparency = 0.3, ZIndex = Z },
		scroll)
	Kit.Corner(switch, "pill")
	local switchBtns = {}
	for i, set in ipairs(sets) do
		switchBtns[i] = button(switch, { Name = "Chapter" .. i, Text = UT(set.Set.Switch), Style = i == 1 and "primary" or "secondary", TextSize = 15,
			OnClick = function()
				P.Select(i)
			end })
	end
	switch.Visible = #sets > 1

	function P.Select(i: number)
		i = math.clamp(math.floor(tonumber(i) or 1), 1, #sets)
		if P.Chapter == i then
			return
		end
		P.Chapter = i
		audio("UiTab")
		scroll.CanvasPosition = Vector2.new(0, 0)
		P.Paint()
		if win then
			P.Layout(win:GetLayout())
		end
	end
	function P.Paint()
		for i, b in ipairs(switchBtns) do
			local on = i == P.Chapter
			local n = sets[i].Ready or 0
			b:SetText(UT(sets[i].Set.Switch) .. ((not on and n > 0) and ("  ● " .. n) or ""))
			b:SetStyle(on and "primary" or "secondary", on and (i == 2 and C(150, 80, 230) or PUMPKIN) or nil)
		end
	end

	function P.Layout(L)
		local w = L.Width - 12
		if w < 60 then
			return
		end
		local top = 0
		if #sets > 1 then
			local sw = math.min(w - 4, 420)
			place(switch, 2, 2, sw, 46)
			local bw = math.floor((sw - 18) / 2)
			for i, b in ipairs(switchBtns) do
				place(b.Instance, 6 + (i - 1) * (bw + 6), 5, bw, 36)
			end
			top = 58
		end
		local bottom = top
		for i, set in ipairs(sets) do
			local on = i == P.Chapter
			set.Box.Visible = on
			if on then
				local h = set.Layout(L)
				place(set.Box, 0, top, L.Width, h)
				bottom = top + h
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, bottom + 4)
	end
	function P.Refresh()
		local ready = 0
		for _, set in ipairs(sets) do
			set.Refresh()
			ready += set.Ready or 0
		end
		P.Ready = ready
		P.Paint()
	end
	return P
end

---------------------------------------------------------------------------- CAULDRON
local function thresholds(): { number }
	local v = view()
	if v.Cauldron and type(v.Cauldron.Thresholds) == "table" and #v.Cauldron.Thresholds > 0 then
		return v.Cauldron.Thresholds
	end
	local out, sum = {}, 0
	for i, row in ipairs((Config.Cauldron and Config.Cauldron.Levels) or {}) do
		sum += row.Cost or 0
		out[i] = sum
	end
	return out
end

-- the page's frame loop: runs fn(dt, t) every frame while `tab` is the open tab of the open window (stops itself)
-- onStop (optional) runs once when the loop ends (window closed / tab changed)
local function pageLoop(tab: string, fn: (number, number) -> (), onStop: (() -> ())?): () -> ()
	local conn = nil
	local t0 = os.clock()
	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if onStop then
			pcall(onStop)
		end
	end
	return function()
		if conn then
			return
		end
		conn = RunService.RenderStepped:Connect(function(dt)
			if not (win and win.IsOpen and st.Tab == tab) then
				stop()
				return
			end
			local ok, err = pcall(fn, dt, os.clock() - t0)
			if not ok then
				warn("HalloweenScreen " .. tab .. " loop: " .. tostring(err))
				stop()
			end
		end)
	end
end

-- brew colour of a cauldron level (L5 THE BURIED MOON BREW: moon violet)
local function brewColor(level: number): Color3
	if level >= 5 then
		return C(196, 150, 255)
	end
	return NEON:Lerp(C(220, 255, 140), (level - 1) / 4 * 0.6)
end

-- the cauldron art of the TRICK panel: a built iron pot with its glowing brew (colour by level), a breathing glow,
-- flickering green flames, bubbles and steam rising and a candy circling in; animated while the tab is open.
-- Without Icons: the frame drawing.
local caulArt = setmetatable({}, { __mode = "k" })
local function cauldronArt(parent: Instance): Frame
	local artF = Kit.New("Frame", { Name = "CauldronArt", BackgroundTransparency = 1, ZIndex = Z + 1 }, parent)
	local function part(name, x, y, w, h, top, bottom, z, round)
		local f = Kit.New("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = WHITE, Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
			ZIndex = z }, artF)
		Kit.Corner(f, round or "pill")
		gradient(f, top, bottom)
		return f
	end
	if Icons then
		-- a soft round glow: two crossed gradient discs (the kit has no radial gradient)
		local glow = part("Glow", 0.06, 0.12, 0.88, 0.84, NEON, NEON, Z + 1)
		local glowG = glow:FindFirstChild("HwGradient")
		glowG.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.72), NumberSequenceKeypoint.new(1, 1) })
		glowG.Rotation = 0
		local glow2 = part("Glow2", 0.06, 0.12, 0.88, 0.84, NEON, NEON, Z + 1)
		local glowG2 = glow2:FindFirstChild("HwGradient")
		glowG2.Transparency = glowG.Transparency
		glowG2.Rotation = 90
		local glowScale = Kit.New("UIScale", { Name = "Breath" }, glow)
		Kit.New("UIScale", { Name = "Breath" }, glow2)
		local flames = {}
		for i, f in ipairs({ { 0.3, 0.72, 0.16 }, { 0.42, 0.7, 0.2 }, { 0.58, 0.71, 0.18 } }) do
			local fl = part("Flame" .. i, f[1], f[2], f[3], 0.24, C(220, 255, 170), C(40, 170, 70), Z + 2)
			fl.AnchorPoint = Vector2.new(0, 1)
			fl.Position = UDim2.fromScale(f[1], f[2] + 0.24)
			flames[i] = fl
		end
		local potHolder = Kit.New("Frame", { Name = "Pot", BackgroundTransparency = 1, Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.84, 0.84),
			ZIndex = Z + 3 }, artF)
		local pot = art(potHolder, "Cauldron", { Size = 150, ZIndex = Z + 3, Glow = NEON })
		local bubbles, steam = {}, {}
		for i = 1, 4 do
			local b = part("Bubble" .. i, 0.3 + i * 0.09, 0.4, 0.06, 0.06, WHITE, NEON, Z + 6)
			Kit.New("UIAspectRatioConstraint", { AspectRatio = 1 }, b)
			bubbles[i] = { F = b, X = 0.3 + i * 0.09, Phase = i * 0.37 }
		end
		for i = 1, 3 do
			local p = part("Steam" .. i, 0.25 + i * 0.12, 0.2, 0.18, 0.18, WHITE, C(200, 255, 210), Z + 2)
			Kit.New("UIAspectRatioConstraint", { AspectRatio = 1 }, p)
			steam[i] = { F = p, X = 0.22 + i * 0.13, Phase = i * 0.53 }
		end
		local candyF = Kit.New("Frame", { Name = "Candy", BackgroundTransparency = 1, Position = UDim2.fromScale(0.72, 0.02), Size = UDim2.fromScale(0.24, 0.24),
			ZIndex = Z + 7 }, artF)
		art(candyF, "Candy", { Size = 40, ZIndex = Z + 7 })
		local level = 1
		local reduced = Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion()) or false
		local function step(_, t)
			local col = brewColor(level)
			glowScale.Scale = 1 + 0.04 * math.sin(t * 2.2)
			glow2.Breath.Scale = glowScale.Scale
			for i, fl in ipairs(flames) do
				local k = 0.85 + 0.25 * math.noise(t * 3 + i * 1.7, i)
				fl.Size = UDim2.fromScale(fl.Size.X.Scale, 0.24 * k)
			end
			for _, b in ipairs(bubbles) do
				local u = (t * 0.55 + b.Phase) % 1
				b.F.Position = UDim2.fromScale(b.X + math.sin(u * 6 + b.Phase) * 0.02, 0.4 - u * 0.3)
				b.F.BackgroundTransparency = u
				b.F.BackgroundColor3 = col:Lerp(WHITE, 0.5)
			end
			for _, p in ipairs(steam) do
				local u = (t * 0.22 + p.Phase) % 1
				p.F.Position = UDim2.fromScale(p.X + math.sin(u * 3 + p.Phase) * 0.04, 0.3 - u * 0.3)
				p.F.Size = UDim2.fromScale(0.12 + u * 0.14, 0.12 + u * 0.14)
				p.F.BackgroundTransparency = 0.55 + 0.45 * u
			end
			candyF.Rotation = math.sin(t * 1.4) * 14
			candyF.Position = UDim2.fromScale(0.72, 0.02 + math.sin(t * 1.8) * 0.02)
		end
		step(0, 0.4)
		caulArt[artF] = {
			Loop = (not reduced) and pageLoop("cauldron", step) or nil,
			Set = function(lv: number)
				if lv == level and pot and pot.Key then
					return
				end
				level = lv
				local col = brewColor(lv)
				if pot then
					pot:Set("Cauldron", { Size = 150, Glow = col })
				end
				glowG.Color = ColorSequence.new(col, col)
				glowG2.Color = glowG.Color
			end,
		}
		return artF
	end
	local glow = part("Glow", 0.02, 0.06, 0.96, 0.9, NEON, C(40, 120, 60), Z + 1)
	glow.BackgroundTransparency = 0.86
	part("LegL", 0.25, 0.7, 0.09, 0.2, C(60, 54, 72), C(20, 16, 28), Z + 2, 6)
	part("LegR", 0.66, 0.7, 0.09, 0.2, C(60, 54, 72), C(20, 16, 28), Z + 2, 6)
	local fire = txt(artF, { Name = "Fire", Text = "🔥🔥🔥", TextSize = 40, Scaled = true, MinTextSize = 6, AlignX = "Center", ZIndex = Z + 2 })
	fire.Position, fire.Size = UDim2.fromScale(0.22, 0.74), UDim2.fromScale(0.56, 0.2)
	local body = part("Body", 0.13, 0.33, 0.74, 0.5, C(84, 76, 98), C(18, 14, 26), Z + 3)
	Kit.Stroke(body, INK, 3, 0)
	local band = part("Band", 0.13, 0.5, 0.74, 0.07, C(120, 110, 136), C(60, 54, 72), Z + 4, 3)
	band.BackgroundTransparency = 0.2
	local rim = part("Rim", 0.08, 0.27, 0.84, 0.15, C(130, 122, 146), C(44, 38, 56), Z + 5)
	Kit.Stroke(rim, INK, 3, 0)
	part("Brew", 0.14, 0.295, 0.72, 0.09, C(200, 255, 170), C(46, 190, 70), Z + 6)
	for i, b in ipairs({ { 0.3, 0.17, 0.08 }, { 0.48, 0.07, 0.12 }, { 0.65, 0.19, 0.06 }, { 0.58, 0.0, 0.05 } }) do
		local bubble = part("Bubble" .. i, b[1], b[2], b[3], b[3], C(220, 255, 200), NEON, Z + 6)
		bubble.BackgroundTransparency = 0.15
		Kit.New("UIAspectRatioConstraint", { AspectRatio = 1 }, bubble)
	end
	local candy = txt(artF, { Name = "Candy", Text = "🍬", TextSize = 40, Scaled = true, MinTextSize = 6, AlignX = "Center", ZIndex = Z + 7 })
	candy.Position, candy.Size, candy.Rotation = UDim2.fromScale(0.74, 0.02), UDim2.fromScale(0.22, 0.22), 18
	return artF
end
-- level colour + start the animation (the cauldron tab calls it on refresh / show)
function S.CauldronArtLevel(artF: Frame, level: number, animate: boolean?)
	local h = caulArt[artF]
	if h then
		h.Set(math.clamp(math.floor(level), 1, 5))
		if animate and h.Loop then
			h.Loop()
		end
	end
end
S.CauldronArt = cauldronArt

-- TRICK odds chips: PUMPKIN BLOCK 94% / CURSED PUMPKIN 6%
local function trickRows(): { any }
	local cursedChance = (Config.Cauldron and Config.Cauldron.CursedChance) or 0.06
	return { { Kind = "Block", Id = "Pumpkin", Suffix = " " .. math.floor((1 - cursedChance) * 100 + 0.5) .. "%" },
		{ Kind = "Block", Id = "Cursed Pumpkin", Suffix = " " .. math.floor(cursedChance * 100 + 0.5) .. "%" } }
end

pages.cauldron = function(page: Frame)
	local P = {}
	local scroll = scrollPage(page)
	local levels = (Config.Cauldron and Config.Cauldron.Levels) or {}
	local trickCost = (Config.Cauldron and Config.Cauldron.TrickCost) or 80
	-- [WP-E] the TRICK price grows with every trick of the UTC day (server View.Cauldron.TrickPrice); a view from an
	-- earlier UTC day means the price is back to the base
	local function trickPrice(): (number, number)
		local v = view()
		local c = v.Cauldron or {}
		local today = math.floor(now() / 86400)
		if tonumber(v.Day) and tonumber(v.Day) < today then
			return tonumber(c.TrickBase) or trickCost, 0
		end
		return tonumber(c.TrickPrice) or trickCost, tonumber(c.TricksToday) or 0
	end
	local shownPrice = trickCost -- the price on the TRICK button (sent as MaxPrice: never pay more than shown)

	-- TRICK
	local trick = panel(scroll, "Trick", C(96, 40, 110), C(44, 14, 54))
	local trickArt = cauldronArt(trick)
	local prizesTitle = txt(trick, { Name = "PrizesTitle", Text = T("TOP PRIZES"), TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = PUMPKIN_HI })
	local prizes = Kit.New("Frame", { Name = "Prizes", BackgroundTransparency = 1, ZIndex = Z + 1 }, trick)
	local prizeRows = {}
	for _, row in ipairs((Config.Rewards and Config.Rewards.Pumpkin) or {}) do
		if (row.Rank or 0) >= 5 or row.Kind == "Skin" then
			table.insert(prizeRows, row)
		end
	end
	local trickTitle = txt(trick, { Name = "Title", Text = T("TRICK"), TextSize = 30, Scaled = true, MinTextSize = 12, AlignX = "Center", Color = PUMPKIN_HI,
		Stroke = 0.2 })
	local trickBody = txt(trick, { Name = "Body", Text = F("Throw %d candy into the cauldron and get a PUMPKIN LUCKY BLOCK. Sometimes it comes out CURSED.", trickCost),
		TextSize = 15, Wrap = true, AlignX = "Center", AlignY = "Top", Color = SOFT })
	local trickChips = Kit.New("Frame", { Name = "Chance", BackgroundTransparency = 1, ZIndex = Z + 1 }, trick)
	local trickHint = txt(trick, { Name = "Hint", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED })
	local trickBtn
	trickBtn = button(trick, { Name = "Trick", Text = T("TRICK"), Color = PUMPKIN, TextSize = 19, PriceText = "🍬 " .. trickCost, OnClick = function()
		if not P.Near then
			showTheWay()
			return
		end
		act(trickBtn, "CauldronTrick", { Request = (HttpService:GenerateGUID(false):gsub("-", "")), MaxPrice = shownPrice }, function(res)
			audio("CauldronSplash")
			local cursed = res and res.Tier == "Cursed Pumpkin"
			Kit.Toast((cursed and "💀 " or "🎃 ") .. T(cursed and "CURSED PUMPKIN LUCKY BLOCK added to your Inventory" or "PUMPKIN LUCKY BLOCK added to your Inventory"),
				{ Kind = "success", NoTranslate = true, Sound = "Coin" })
		end, "")
	end })
	local trickCount = txt(trick, { Name = "Count", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED })

	-- TREAT
	local treat = panel(scroll, "Treat", C(60, 30, 96), C(34, 14, 56))
	local treatTitle = txt(treat, { Name = "Title", Text = T("TREAT"), TextSize = 30, Scaled = true, MinTextSize = 12, Color = NEON, Stroke = 0.2 })
	-- [WP-E] late starters: every brew is ready by the claim deadline (Shared.BrewSeconds), at least one day after the start
	local treatBody = txt(treat, { Name = "Body", Text = Kit.T("Feed candy to the cauldron. The more you invest, the better the brew. One brew per season, ready 7 days after you start, and always by Oct 31 (at least 1 day).",
		"Корми котёл конфетами. Чем больше вложишь, тем лучше зелье. Одно зелье за сезон: готово через 7 дней после начала и всегда к 31 октября (не раньше чем через 1 день)."),
		TextSize = 14, Wrap = true, AlignY = "Top", Color = SOFT })
	local line = Kit.New("Frame", { Name = "Line", BorderSizePixel = 0, BackgroundColor3 = TRACK, ZIndex = Z + 1 }, treat)
	Kit.Corner(line, "pill")
	local lineFill = Kit.New("Frame", { Name = "Fill", BorderSizePixel = 0, BackgroundColor3 = NEON, ZIndex = Z + 1, Size = UDim2.fromScale(0, 1) }, line)
	Kit.Corner(lineFill, "pill")
	local lvNodes = {}
	for i, lv in ipairs(levels) do
		local node = Kit.New("TextButton", { Name = "Level" .. i, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = Z + 2 }, treat)
		local circle, glyph = badge(node, "Circle", tostring(i), C(80, 50, 120), Z + 2)
		local name = txt(node, { Name = "Name", Text = T(lv.Name or ""), TextSize = 12, Wrap = true, AlignX = "Center", AlignY = "Top", Color = SOFT, ZIndex = Z + 3 })
		local cost = txt(node, { Name = "Cost", Text = "", TextSize = 12, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = GOLD, Font = "numeric", ZIndex = Z + 3 })
		node.Activated:Connect(function()
			st.Selected.Treat = i
			P.Refresh()
		end)
		lvNodes[i] = { Button = node, Circle = circle, Glyph = glyph, Name = name, Cost = cost }
	end
	local investLabel = txt(treat, { Name = "Invested", Text = "", TextSize = 16, Scaled = true, MinTextSize = 9, Color = WHITE })
	local investBar = bar(treat, "InvestBar", NEON, 18)
	local investBtns = {}
	for i, step in ipairs((Config.Cauldron and Config.Cauldron.InvestStep) or { 10, 50 }) do
		local b
		b = button(treat, { Name = "Invest" .. step, Text = "+" .. step .. " 🍬", Color = PURPLE, TextSize = 17, OnClick = function()
			act(b, "CauldronInvest", { Amount = step }, function(res)
				audio(res and res.Message and string.find(res.Message, "LEVEL") and "CauldronLevelUp" or "CandyTick")
			end)
		end })
		investBtns[i] = b
	end
	local nextBtn
	nextBtn = button(treat, { Name = "InvestNext", Text = T("NEXT LEVEL"), Color = PUMPKIN, TextSize = 16, OnClick = function()
		local need = P.NeedForNext or 0
		if need > 0 then
			act(nextBtn, "CauldronInvest", { Amount = need }, function()
				audio("CauldronLevelUp")
			end)
		end
	end })
	local brewBox = panel(treat, "Brew", C(40, 18, 62), C(28, 10, 44), Z + 1)
	local brewIcon = txt(brewBox, { Name = "Icon", Text = "⏳", TextSize = 30, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = Z + 2 })
	local brewArt = art(brewIcon, "Potion", { Size = 52, ZIndex = Z + 3, FrameSize = UDim2.fromScale(1.1, 1.1), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5) }, brewIcon)
	local function brewState(kind: string, opts: { [string]: any })
		if brewArt then
			local o = table.clone(opts)
			o.Size = 52
			brewArt:Set(kind, o)
		end
	end
	local brewLabel = txt(brewBox, { Name = "Label", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, Color = MUTED, ZIndex = Z + 2 })
	local brewTimer = txt(brewBox, { Name = "Timer", Text = "", TextSize = 22, Scaled = true, MinTextSize = 10, Color = GOLD, Font = "numeric", ZIndex = Z + 2 })
	local brewBar = bar(brewBox, "BrewProgress", GOLD, 12)
	brewBar.Instance.ZIndex = Z + 2
	local brewBtn
	brewBtn = button(brewBox, { Name = "Action", Text = "", Color = PUMPKIN, TextSize = 16, ZIndex = Z + 3, OnClick = function()
		local c = view().Cauldron or {}
		if (c.StartedAt or 0) <= 0 then
			act(brewBtn, "CauldronBrew", {}, function()
				audio("CauldronBubbles")
			end)
		elseif not c.Claimed and (c.ReadyAt or 0) <= now() then
			if Bus and not st.Busy.CauldronClaim then
				Bus.Fire("CauldronClaimPending", {}) -- CauldronFX holds the claimer's public geyser until the finale decides
			end
			act(brewBtn, "CauldronClaim", {}, function(res)
				S.BrewFinale(res)
			end, "")
		end
	end })
	local previewTitle = txt(treat, { Name = "PreviewTitle", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, Color = PUMPKIN_HI })
	local previewChips = Kit.New("Frame", { Name = "PreviewChips", BackgroundTransparency = 1, ZIndex = Z + 1 }, treat)
	local previewHint = txt(treat, { Name = "PreviewHint", Text = "👆 " .. T("Tap a level to see its brew. Every row is granted, not rolled."), TextSize = 13,
		Scaled = true, MinTextSize = 8, Color = MUTED })

	function P.Layout(L)
		local w = L.Width - 12
		local narrow = w < 760
		local tw = narrow and w or math.floor(w * 0.36)
		-- TRICK: art, title, description (measured), odds + top prizes (wide), hint, button, counter
		local artS = narrow and 110 or 170
		local ty = (narrow and 8 or 14) + artS + 2
		local bodyH = math.max(narrow and 40 or 58, textH(trickBody.Text, 15, tw - 40))
		local cy = ty + 38 + bodyH + 4
		P.TrickChipW = tw - 40
		P.TrickRows = P.TrickRows or trickRows()
		local chH = chipRow(trickChips, P.TrickRows, tw - 40, 24, true)
		local ph = chipRow(prizes, prizeRows, tw - 40, 24, true)
		local th
		if narrow then
			th = cy + 128
		else
			th = math.max(600, cy + chH + 32 + ph + 20 + 112)
		end
		place(trick, 2, 2, tw, th)
		place(trickArt, tw / 2 - artS / 2, narrow and 8 or 14, artS, artS)
		place(trickTitle, 12, ty, tw - 24, 34)
		place(trickBody, 20, ty + 38, tw - 40, bodyH)
		place(trickChips, 20, cy, tw - 40, chH)
		place(prizesTitle, 20, cy + chH + 10, tw - 40, 18)
		place(prizes, 20, cy + chH + 32, tw - 40, ph)
		trickHint.TextWrapped = narrow -- two lines on a phone
		place(trickHint, 16, th - (narrow and 128 or 112), tw - 32, narrow and 34 or 18)
		place(trickBtn.Instance, 20, th - 88, tw - 40, 52)
		place(trickCount, 16, th - 30, tw - 32, 18)
		trickChips.Visible = not narrow
		prizes.Visible, prizesTitle.Visible = not narrow, not narrow
		-- TREAT: everything below the description moves down with it (Russian: one more line)
		local x0 = narrow and 2 or tw + 14
		local y0 = narrow and th + 14 or 2
		local ww = narrow and w or w - tw - 12
		local tbH = math.max(40, textH(treatBody.Text, 14, ww - 36))
		local dy = tbH - 40
		local hh = (narrow and 560 or 600) + dy
		place(treat, x0, y0, ww, hh)
		place(treatTitle, 18, 12, ww - 36, 36)
		place(treatBody, 18, 50, ww - 36, tbH)
		-- level track
		local n = #lvNodes
		local nodeW = math.floor((ww - 36) / math.max(1, n))
		place(line, 18 + nodeW / 2, 120 + dy, ww - 36 - nodeW, 8)
		for i, node in ipairs(lvNodes) do
			place(node.Button, 18 + (i - 1) * nodeW, 98 + dy, nodeW, 96)
			place(node.Circle, nodeW / 2 - 25, 0, 50, 50)
			place(node.Cost, 2, 54, nodeW - 4, 16)
			-- the longest word must fit the node too (SIMMERING / OVERFLOWING on a phone)
			local longest = 0
			for word in string.gmatch(node.Name.Text, "%S+") do
				longest = math.max(longest, textW(word, 12))
			end
			local fit = 12
			while fit > 8 and (textH(node.Name.Text, fit, nodeW - 4) > 30 or longest * fit / 12 > nodeW - 4) do
				fit -= 1
			end
			node.Name.TextSize = fit
			place(node.Name, 2, 70, nodeW - 4, 30)
		end
		place(investLabel, 18, 204 + dy, ww - 36, 22)
		place(investBar.Instance, 18, 230 + dy, ww - 36, 18)
		local bw = math.floor((ww - 36 - 20) / 3)
		for i, b in ipairs(investBtns) do
			place(b.Instance, 18 + (i - 1) * (bw + 10), 258 + dy, bw, 44)
		end
		place(nextBtn.Instance, 18 + 2 * (bw + 10), 258 + dy, bw, 44)
		place(brewBox, 18, 316 + dy, ww - 36, 92)
		place(brewIcon, 10, 18, 52, 52)
		place(brewLabel, 70, 10, ww - 36 - 70 - 200, 18)
		place(brewTimer, 70, 28, ww - 36 - 70 - 200, 32)
		place(brewBar.Instance, 70, 66, ww - 36 - 70 - 20, 12)
		P.BrewBarW = { Full = ww - 36 - 70 - 20, Short = ww - 36 - 70 - 210 }
		place(brewBtn.Instance, ww - 36 - 188, 20, 176, 48)
		place(previewTitle, 18, 424 + dy, ww - 36, 20)
		place(previewChips, 18, 450 + dy, ww - 36, 120)
		P.PreviewW = ww - 36
		scroll.CanvasSize = UDim2.fromOffset(0, (narrow and (th + 14 + hh) or math.max(th, hh) + 2) + 4)
	end

	function P.Shown()
		local c = view().Cauldron or {}
		S.CauldronArtLevel(trickArt, tonumber(c.Level) or 1, true)
	end

	function P.Refresh()
		local v = view()
		local c = v.Cauldron or {}
		local level = tonumber(c.Level) or 1
		S.CauldronArtLevel(trickArt, level, false)
		local th = thresholds()
		local invested = tonumber(c.Invested) or 0
		local have = candy()
		local lo, hi = th[level] or 0, th[level + 1]
		-- trick
		local cauldronPos = layout() and layout().Cauldron and layout().Cauldron.Center
		P.Near = near(cauldronPos, ((Config.Cauldron and Config.Cauldron.Range) or 22) + 6)
		-- [WP-E] the price of the next TRICK + "the cauldron grows hungry" hint
		local price, today = trickPrice()
		shownPrice = price
		trickBody.Text = F("Throw %d candy into the cauldron and get a PUMPKIN LUCKY BLOCK. Sometimes it comes out CURSED.", price)
		if not P.Near then
			trickBtn:SetText(T("SHOW THE WAY"))
			trickBtn:SetPrice(nil)
			trickBtn:SetDisabled(false)
			trickHint.Text = "📍 " .. T("Stand next to the Haunted Cauldron in the Dead Yard")
			trickHint.TextColor3 = GOLD
		else
			trickBtn:SetText(T("TRICK"))
			trickBtn:SetPrice("🍬 " .. price)
			trickBtn:SetDisabled(have < price)
			local maxPrice = tonumber(c.TrickMax)
			local hungry = today <= 0 and ("🎃 " .. Kit.T("The price rises with every trick today", "Цена растёт с каждой гадостью за день"))
				or (maxPrice and price >= maxPrice) and ("🔥 " .. Kit.T("The cauldron is starving: the price resets at midnight (UTC)",
					"Котёл ненасытен: цена сбросится в полночь (UTC)"))
				or ("🔥 " .. Kit.T("The cauldron grows hungry: the price rises with every trick today", "Котёл голодает: цена растёт с каждой гадостью за день"))
			trickHint.Text = have < price and F("You need %d candy", price) or hungry
			trickHint.TextColor3 = have < price and C(255, 120, 120) or (today > 0 and PUMPKIN_HI or MUTED)
		end
		trickCount.Text = F("Tricks played: %d", tonumber(c.Tricks) or 0)
		P.TrickRows = trickRows()
		chipRow(trickChips, P.TrickRows, P.TrickChipW or 300, 24, true)
		-- treat track
		for i, node in ipairs(lvNodes) do
			local reached = i <= level
			local selected = (st.Selected.Treat or level) == i
			gradient(node.Circle, (reached and NEON or C(90, 60, 130)):Lerp(WHITE, 0.2), reached and C(40, 140, 60) or C(50, 26, 80))
			node.Glyph.Text = reached and (i == level and "🔥" or "✓") or tostring(i)
			node.Cost.Text = i == 1 and T("FREE") or ("🍬 " .. num(th[i] or 0))
			local stroke = node.Circle:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = selected and PUMPKIN_HI or INK
				stroke.Thickness = selected and 3 or 2
				stroke.Transparency = selected and 0 or 0.2
			end
		end
		local maxLevel = #lvNodes
		lineFill.Size = UDim2.fromScale(math.clamp((level - 1) / math.max(1, maxLevel - 1), 0, 1), 1)
		if hi then
			investLabel.Text = F("LEVEL %d · %s", level, T(levels[level] and levels[level].Name or "")) .. "   " .. F("%s / %s to the next level", num(invested), num(hi))
			investBar:SetValue(math.clamp((invested - lo) / math.max(1, hi - lo), 0, 1))
			investBar:SetText("")
		else
			investLabel.Text = F("LEVEL %d · %s", level, T(levels[level] and levels[level].Name or "")) .. "   " .. T("TOP LEVEL!")
			investBar:SetValue(1)
		end
		P.NeedForNext = hi and math.max(0, hi - invested) or 0
		local locked = c.Claimed == true or hi == nil
		for i, b in ipairs(investBtns) do
			local step = ((Config.Cauldron and Config.Cauldron.InvestStep) or { 10, 50 })[i]
			b:SetDisabled(locked or have < 1)
			b:SetText("+" .. step .. " 🍬")
		end
		nextBtn:SetText(hi and F("NEXT LEVEL · %s", num(P.NeedForNext)) or T("MAX"))
		nextBtn:SetDisabled(locked or have < P.NeedForNext or P.NeedForNext <= 0)
		-- brew
		P.Tick()
		-- preview
		local sel = st.Selected.Treat or level
		local tableName = levels[sel] and levels[sel].Table
		previewTitle.Text = F("BREW REWARDS AT LEVEL %d · %s", sel, T(levels[sel] and levels[sel].Name or ""))
		local chipsH = chipRow(previewChips, (Config.Rewards and tableName and Config.Rewards[tableName]) or {}, P.PreviewW or 500, 30)
		local py = previewChips.Position.Y.Offset
		previewHint.Position = UDim2.fromOffset(previewChips.Position.X.Offset, py + chipsH + 10)
		previewHint.Size = UDim2.fromOffset(P.PreviewW or 500, 18)
	end

	function P.Tick()
		local c = view().Cauldron or {}
		local t = now()
		local running = (c.StartedAt or 0) > 0 and not c.Claimed and (c.ReadyAt or 0) > t
		brewBar.Instance.Visible = running
		if P.BrewBarW then
			brewBar.Instance.Size = UDim2.fromOffset(running and P.BrewBarW.Full or P.BrewBarW.Short, 12)
		end
		if c.Claimed then
			brewIcon.Text = "🏆"
			brewState("Crown", {})
			brewLabel.Text = T("YOUR BREW")
			brewTimer.Text = T("CLAIMED THIS SEASON")
			brewTimer.TextColor3 = NEON
			brewBtn.Instance.Visible = false
		elseif (c.StartedAt or 0) <= 0 then
			brewIcon.Text = "🫕"
			brewState("Cauldron", { Glow = brewColor(tonumber(c.Level) or 1) })
			brewLabel.Text = T("YOUR BREW")
			brewTimer.Text = T("NOT STARTED")
			brewTimer.TextColor3 = MUTED
			brewBtn.Instance.Visible = true
			brewBtn:SetText(T("START BREW"))
			brewBtn:SetStyle("primary", PUMPKIN)
			brewBtn:SetDisabled(false)
		elseif (c.ReadyAt or 0) > t then
			brewIcon.Text = "⏳"
			brewState("Potion", { Glow = brewColor(tonumber(c.Level) or 1), Dim = 0.35 })
			brewLabel.Text = T("READY IN")
			brewTimer.Text = duration((c.ReadyAt or 0) - t)
			brewTimer.TextColor3 = GOLD
			brewBtn.Instance.Visible = false
			local span = math.max(1, (c.ReadyAt or 0) - (c.StartedAt or 0))
			brewBar:SetValue(math.clamp((t - (c.StartedAt or t)) / span, 0, 1), true)
		else
			brewIcon.Text = "✨"
			brewState("Potion", { Glow = brewColor(tonumber(c.Level) or 1) })
			brewLabel.Text = T("YOUR BREW")
			brewTimer.Text = T("READY!")
			brewTimer.TextColor3 = NEON
			brewBtn.Instance.Visible = true
			brewBtn:SetText(T("CLAIM BREW"))
			brewBtn:SetStyle("success")
			brewBtn:SetDisabled(false)
		end
		-- the label and timer take the button's room while it is hidden (БУДЕТ ГОТОВО ЧЕРЕЗ on a phone)
		if P.BrewBarW then
			local lw = math.max(40, brewBtn.Instance.Visible and (P.BrewBarW.Short + 10) or P.BrewBarW.Full)
			brewLabel.Size = UDim2.fromOffset(lw, 18)
			brewTimer.Size = UDim2.fromOffset(lw, 32)
		end
		-- the TRICK button follows where the player is
		local cauldronPos = layout() and layout().Cauldron and layout().Cauldron.Center
		local isNear = near(cauldronPos, ((Config.Cauldron and Config.Cauldron.Range) or 22) + 6)
		if isNear ~= P.Near then
			P.Refresh()
		end
	end
	return P
end

-- THE BURIED MOON BREW claimed: CauldronFX plays the finale at the cauldron (Bus "CauldronClaimLocal"; it sets Handled and
-- calls Reveal when the potion bursts), then the reward card. Far from the cauldron / ReducedMotion: the card at once.
function S.BrewFinale(res: any)
	local rows = (type(res) == "table" and type(res.Rewards) == "table") and res.Rewards or {}
	local c = view().Cauldron or {}
	local level = math.clamp(tonumber(type(res) == "table" and res.Level) or tonumber(c.Level) or 1, 1, 5)
	local levels = (Config.Cauldron and Config.Cauldron.Levels) or {}
	local kicker = F("LEVEL %d · %s", level, T(levels[level] and levels[level].Name or ""))
	local shown = false
	local function reveal()
		if shown then
			return
		end
		shown = true
		rewardsDialog(T("THE BURIED MOON BREW"), rows, { Kicker = kicker })
	end
	-- FromWindow: the open window owns the modal count; the finale ignores it at start and the window closes right below
	local d = { Rows = rows, Level = level, Reveal = reveal, FromWindow = (win ~= nil and win.IsOpen) == true }
	if Bus then
		Bus.Fire("CauldronClaimLocal", d)
	end
	if d.Handled then
		if win and win.IsOpen then
			win:Close("brew") -- the finale plays in the world
		end
		task.delay(tonumber(d.Seconds) or 14, reveal) -- safety net: the card always comes
	else
		reveal()
	end
end

---------------------------------------------------------------------------- BOSS
local function bossActive(b: { [string]: any }): boolean
	local s = tostring(b.State or "Idle")
	if s == "" or s == "Idle" or s == "Defeated" or s == "Escaped" or s == "Cooldown" or s == "Ended" then
		return false
	end
	return (tonumber(b.MaxArmor) or 0) > 0
end
S.BossActive = bossActive

local function phaseName(b: { [string]: any }): string
	local name = b.PhaseName
	if type(name) ~= "string" or name == "" then
		local phase = tonumber(b.Phase) or 0
		for _, p in ipairs((Config.Boss and Config.Boss.Phases) or {}) do
			if p.Id == phase then
				name = p.Name
			end
		end
	end
	return T(name or "")
end
S.PhaseName = phaseName

-- the colour of a difficulty I..V (green -> yellow -> orange -> red -> violet)
function S.DifficultyColor(i: number): Color3
	return ({ C(120, 255, 110), C(255, 220, 80), C(255, 150, 40), C(255, 60, 70), C(190, 90, 255) })[math.clamp(math.floor(i), 1, 5)]
end

-- THE GRAVEKEEPER in a ViewportFrame (RS.Halloween.Models.Boss): returns (frame, step(dt, t)) or nil
local function bossViewport(parent: Instance, z: number): (any, any)
	local folderM = Halloween and Halloween:FindFirstChild("Models")
	local mod = folderM and folderM:FindFirstChild("Boss")
	if not mod then
		return nil, nil
	end
	local okM, Boss = pcall(require, mod)
	if not okM or type(Boss) ~= "table" or not Boss.Build then
		return nil, nil
	end
	local okB, model = pcall(Boss.Build, {})
	if not okB or typeof(model) ~= "Instance" then
		return nil, nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	local vp = Kit.New("ViewportFrame", { Name = "BossView", BackgroundTransparency = 1, Ambient = C(150, 120, 176), LightColor = C(255, 214, 190),
		LightDirection = Vector3.new(-0.5, -1, 0.6), Size = UDim2.fromScale(1, 1), ZIndex = z })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local okBox, cf, size = pcall(function()
		return (model :: any):GetBoundingBox()
	end)
	local focus = okBox and cf.Position or Vector3.new(0, 13, 0)
	local radius = okBox and size.Magnitude / 2 or 24
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 0.82
	local function place(yaw: number, bob: number)
		-- the boss faces -Z: a 3/4 front view from the left, a little from above
		local dir = (CFrame.Angles(0, yaw, 0) * Vector3.new(-0.62, 0.24, -0.75)).Unit
		cam.CFrame = CFrame.lookAt(focus + dir * dist + Vector3.new(0, bob, 0), focus + Vector3.new(0, bob * 0.5, 0))
	end
	place(0, 0)
	vp.Parent = parent
	return vp, function(_, t: number)
		place(math.sin(t * 0.35) * 0.32, math.sin(t * 0.9) * 0.4)
	end
end

-- the stat lines of a difficulty card
local function statsText(d: any): string
	local candyRange = d.Candy and (d.Candy[1] .. "-" .. d.Candy[2]) or "?"
	local lines = {
		F("Armor x%s", tostring(d.Armor or 1)),
		F("Rewards x%s", tostring(d.Reward or 1)),
		"🍬 " .. candyRange,
		"🐶 " .. F("%s%% event dog", tostring(math.floor((d.DogChance or 0) * 1000 + 0.5) / 10)),
	}
	if d.CursedBlock then
		table.insert(lines, "💀 " .. F("%s%% Cursed Pumpkin", tostring(math.floor(d.CursedBlock * 100 + 0.5))))
	end
	if d.EclipseChance then
		table.insert(lines, "🌑 " .. T("ECLIPSED finds"))
	end
	return table.concat(lines, "\n")
end

pages.boss = function(page: Frame)
	local P = {}
	local scroll = scrollPage(page)
	local diffs = (Config.Boss and Config.Boss.Difficulties) or {}

	local head = panel(scroll, "Status", C(96, 26, 46), C(34, 8, 26))
	head.ClipsDescendants = true
	local skull = txt(head, { Name = "Art", Text = "💀", TextSize = 90, Scaled = true, MinTextSize = 10, AlignX = "Center" })
	-- THE GRAVEKEEPER himself in the header (a 3D view built the first time the tab opens, swaying slowly); until then /
	-- without the model: a built skull with burning eyes
	local bossArt = Kit.New("Frame", { Name = "BossArt", BackgroundTransparency = 1, ZIndex = Z + 1 }, head)
	local bossSkull = art(bossArt, "Skull", { Size = 120, ZIndex = Z + 2, Glow = C(255, 70, 80) }, Icons and skull or nil)
	local bossView = nil
	local title = txt(head, { Name = "Title", Text = T("THE GRAVEKEEPER"), TextSize = 32, Scaled = true, MinTextSize = 14, Stroke = 0.2 })
	local status = txt(head, { Name = "Status", Text = "", TextSize = 16, Scaled = true, MinTextSize = 9, Color = SOFT })
	local armor = bar(head, "Armor", BLOOD, 22)
	local fight = txt(head, { Name = "Fight", Text = "", TextSize = 14, Scaled = true, MinTextSize = 8, Color = GOLD, Font = "numeric" })
	local goBtn = button(head, { Name = "ShowWay", Text = T("SHOW THE WAY"), Color = PUMPKIN, TextSize = 16, OnClick = showTheWay })

	local cards = {}
	for i, d in ipairs(diffs) do
		local card = panel(scroll, "Difficulty" .. i)
		local numeral = txt(card, { Name = "Numeral", Text = d.Numeral or tostring(i), TextSize = 46, Scaled = true, MinTextSize = 12, AlignX = "Center",
			Color = WHITE, Stroke = 0.1 })
		local name = txt(card, { Name = "Name", Text = T(d.Name or ""), TextSize = 18, Scaled = true, MinTextSize = 9, AlignX = "Center", Color = PUMPKIN_HI })
		local stats = txt(card, { Name = "Stats", Text = "", TextSize = 13, Wrap = true, AlignX = "Center", AlignY = "Top", Color = SOFT, Rich = true })
		local lock = txt(card, { Name = "Lock", Text = "", TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = MUTED })
		local summon
		summon = button(card, { Name = "Summon", Text = T("SUMMON"), Color = BLOOD, TextSize = 16, OnClick = function()
			if not P.NearBell then
				showTheWay()
				return
			end
			act(summon, "BossSummon", { Difficulty = d.Id or i }, function()
				audio("BellToll")
				if win then
					win:Close("summon")
				end
			end)
		end })
		-- the danger art in the card body: a skull burning in the difficulty's colour + one pip per level
		local danger = Kit.New("Frame", { Name = "Danger", BackgroundTransparency = 1, ZIndex = Z + 1 }, card)
		local dangerSkull = art(danger, "Skull", { Size = 80, ZIndex = Z + 2, Glow = S.DifficultyColor(i) })
		local pips = Kit.New("Frame", { Name = "Pips", BackgroundTransparency = 1, ZIndex = Z + 1 }, card)
		local pipArt = {}
		for k = 1, i do
			local pf = Kit.New("Frame", { Name = "Pip" .. k, BackgroundTransparency = 1, ZIndex = Z + 2 }, pips)
			pipArt[k] = { Frame = pf, Art = art(pf, "Skull", { Size = 16, ZIndex = Z + 2, Glow = S.DifficultyColor(i) }) }
		end
		danger.Visible, pips.Visible = dangerSkull ~= nil, dangerSkull ~= nil
		cards[i] = { Frame = card, Numeral = numeral, Name = name, Stats = stats, Lock = lock, Summon = summon, Def = d, Danger = danger,
			DangerArt = dangerSkull, Pips = pips, PipArt = pipArt }
	end
	local hint = txt(scroll, { Name = "Hint", Text = T("Ring the Grave Bell at the pit to summon. Beat a difficulty to unlock the next one. Everyone nearby can join the fight."),
		TextSize = 14, Wrap = true, AlignX = "Center", Color = MUTED })

	function P.Layout(L)
		local w = L.Width - 12
		local narrow = w < 760
		local hh = narrow and 150 or 150
		for _, c in ipairs(cards) do
			c.Stats.Text = statsText(c.Def)
		end
		place(head, 2, 2, w, hh)
		local art = narrow and 0 or 140
		skull.Visible = art > 0
		place(skull, w - art - 10, 6, art, art)
		bossArt.Visible = art > 0
		place(bossArt, w - art - 30, -6, art + 26, art + 12)
		place(title, 18, 14, w - art - 36, 38)
		place(status, 18, 54, w - art - 36, 22)
		place(armor.Instance, 18, 84, w - art - 200, 22)
		place(fight, 18, 114, w - art - 200, 20)
		place(goBtn.Instance, w - art - 172, 80, 160, 44)
		local y = hh + 14
		if narrow then
			local bw = math.clamp(math.floor(w * 0.3), 128, 210) -- one-line SUMMON / GO TO THE BELL when there is room
			local sw = w - 92 - bw - 22
			for i, c in ipairs(cards) do
				-- the card grows with its stat lines (IV and V list the Cursed Pumpkin and ECLIPSED rows too)
				-- emoji lines (🍬 🐶 💀 🌑) stand a little taller than plain text
				local sh = textH(c.Stats.Text, 13, sw) + select(2, string.gsub(c.Stats.Text, "\n", "")) * 3 + 4
				local ch = math.max(104, 12 + sh + 4 + 18 + 10)
				place(c.Frame, 2, y, w, ch)
				place(c.Numeral, 10, ch / 2 - 38, 70, 56)
				place(c.Name, 10, ch / 2 + 18, 70, 22)
				place(c.Stats, 92, 12, sw, sh)
				c.Stats.TextXAlignment = Enum.TextXAlignment.Left
				place(c.Lock, 92, 12 + sh + 4, sw, 18)
				c.Lock.TextXAlignment = Enum.TextXAlignment.Left
				place(c.Summon.Instance, w - bw - 12, ch / 2 - 22, bw, 44)
				y += ch + 10
				local _ = i
			end
		else
			local gap = 12
			local cw = math.floor((w - gap * (#cards - 1)) / math.max(1, #cards))
			local ch = math.clamp((L.Height or 600) - (hh + 14) - 58, 300, 420)
			for i, c in ipairs(cards) do
				place(c.Frame, 2 + (i - 1) * (cw + gap), y, cw, ch)
				place(c.Numeral, 10, 14, cw - 20, 60)
				place(c.Name, 10, 76, cw - 20, 24)
				place(c.Stats, 10, 108, cw - 20, 130)
				c.Stats.TextXAlignment = Enum.TextXAlignment.Center
				place(c.Lock, 10, ch - 88, cw - 20, 18)
				c.Lock.TextXAlignment = Enum.TextXAlignment.Center
				place(c.Summon.Instance, 10, ch - 60, cw - 20, 48)
				-- the empty card body gets the danger skull (when there is room under the stat lines)
				local sh = textH(statsText(c.Def), 13, cw - 20) + 6
				local top, bottom = 108 + sh, ch - 96
				local room = bottom - top
				local show = c.DangerArt ~= nil and room >= 50
				c.Danger.Visible, c.Pips.Visible = show, show and room >= 76
				if show then
					local pipsH = room >= 76 and 18 or 0
					local s = math.min(room - pipsH - 4, cw * 0.62, 110)
					place(c.Danger, cw / 2 - s / 2, top + (room - pipsH - s) / 2, s, s)
					local n = #c.PipArt
					local pw = 16
					place(c.Pips, cw / 2 - (n * (pw + 3) - 3) / 2, bottom - pipsH, n * (pw + 3), pw)
					for k, pa in ipairs(c.PipArt) do
						place(pa.Frame, (k - 1) * (pw + 3), 0, pw, pw)
					end
				end
			end
			y += ch + 12
		end
		local hintH = math.max(40, textH(hint.Text, 14, w - 40))
		place(hint, 20, y, w - 40, hintH)
		scroll.CanvasSize = UDim2.fromOffset(0, y + hintH + 6)
	end

	function P.Refresh()
		local b = folderAttrs("Boss")
		local unlocked = tonumber(player:GetAttribute("HwBossUnlocked")) or (view().Boss and view().Boss.Unlocked) or 1
		local active = bossActive(b)
		local t = now()
		local nextAt = tonumber(b.NextSummonAt) or 0
		local bellPos = layout() and layout().Bell and layout().Bell.Position
		P.NearBell = near(bellPos, ((Config.Boss and Config.Boss.SummonRange) or 18) + 4)
		local best = view().Boss and view().Boss.Best or 0
		for i, c in ipairs(cards) do
			local d = c.Def
			local id = d.Id or i
			local open = id <= unlocked
			local selectedTone = open and C(150, 30, 50) or C(60, 40, 80)
			gradient(c.Frame, (open and C(96, 30, 60) or PANEL_TOP), (open and C(40, 10, 30) or PANEL_BOTTOM))
			if c.DangerArt then
				local dim = (not open) and 0.6 or nil
				c.DangerArt:Set("Skull", { Size = 80, Glow = S.DifficultyColor(id), Dim = dim })
				for _, pa in ipairs(c.PipArt) do
					if pa.Art then
						pa.Art:Set("Skull", { Size = 16, Glow = S.DifficultyColor(id), Dim = dim })
					end
				end
			end
			c.Numeral.TextColor3 = open and WHITE or MUTED
			c.Stats.Text = statsText(d)
			if not open then
				c.Lock.Text = "🔒 " .. F("Defeat %s first", (diffs[id - 1] and diffs[id - 1].Numeral) or tostring(id - 1))
				c.Summon:SetText(T("LOCKED"))
				c.Summon:SetStyle("secondary")
				c.Summon:SetDisabled(true)
			else
				c.Lock.Text = best >= id and ("✅ " .. T("DEFEATED")) or ""
				if active then
					c.Summon:SetText(T("FIGHT ON"))
					c.Summon:SetStyle("secondary")
					c.Summon:SetDisabled(true)
				elseif nextAt > t then
					c.Summon:SetText("⏳ " .. clock(nextAt - t))
					c.Summon:SetStyle("secondary")
					c.Summon:SetDisabled(true)
				elseif not P.NearBell then
					c.Summon:SetText(T("GO TO THE BELL"))
					c.Summon:SetStyle("primary", PUMPKIN)
					c.Summon:SetDisabled(false)
				else
					c.Summon:SetText(T("SUMMON"))
					c.Summon:SetStyle("primary", selectedTone)
					c.Summon:SetDisabled(false)
				end
			end
		end
		if active then
			local d = diffs[tonumber(b.Difficulty) or 1] or {}
			status.Text = "⚔️ " .. F("FIGHT IN PROGRESS · %s %s", d.Numeral or "", T(d.Name or "")) .. "  ·  " .. phaseName(b)
			local max = math.max(1, tonumber(b.MaxArmor) or 1)
			local a = math.clamp(tonumber(b.Armor) or 0, 0, max)
			armor.Instance.Visible = true
			armor:SetValue(a / max)
			armor:SetText(F("ARMOR %s / %s", short(a), short(max)))
			local ends = tonumber(b.EndsAt) or 0
			fight.Text = (ends > t and ("⏱ " .. clock(ends - t) .. "   ") or "") .. F("Fighters: %d", tonumber(b.Fighters) or 0)
		else
			armor.Instance.Visible = false
			if nextAt > t then
				status.Text = F("The Gravekeeper rests. Next summon in %s", clock(nextAt - t))
			else
				status.Text = T("Sleeping under the Graveyard Pit. Ring the bell to wake him.")
			end
			fight.Text = F("Your best: %s", best > 0 and ((diffs[best] and diffs[best].Numeral) or tostring(best)) or "—")
		end
	end
	P.Tick = P.Refresh
	-- the first time the tab opens: THE GRAVEKEEPER in the header (then it sways while the tab is open)
	local swayLoop = nil
	function P.Shown()
		if not bossView and not (Shared and Shared.Low()) then -- Low quality keeps the built skull (no 700-part viewport)
			bossView = true
			task.spawn(function()
				local vp, stepFn = bossViewport(bossArt, Z + 2)
				if vp then
					vp.Size = UDim2.fromScale(1, 1)
					if bossSkull then
						bossSkull.Instance.Visible = false
					end
					skull.TextTransparency = 1
					if stepFn and not (Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion())) then
						swayLoop = pageLoop("boss", stepFn)
						swayLoop()
					end
				end
			end)
		elseif swayLoop then
			swayLoop()
		end
	end
	return P
end

---------------------------------------------------------------------------- COSMETICS
local function skinSources(id: string): { string }
	local out = {}
	local function add(s)
		if not table.find(out, s) then
			table.insert(out, s)
		end
	end
	for name, rows in pairs((Config.Rewards or {})) do
		if type(rows) == "table" then
			for _, row in ipairs(rows) do
				if type(row) == "table" and row.Kind == "Skin" and row.Id == id then
					if name == "Pumpkin" then
						add(T("Pumpkin Lucky Block"))
					elseif name == "CursedPumpkin" then
						add(T("Cursed Pumpkin"))
					elseif string.match(name, "^Treat%d") then
						add(F("Cauldron brew L%s+", string.match(name, "%d")))
					end
				end
			end
		end
	end
	for _, row in ipairs(Config.DexRewards or {}) do
		if row.Skin == id then
			add(F("Event DogDex %d/8", row.Count))
		end
	end
	table.sort(out)
	return out
end
local SKIN_GLYPH = { GraveShovel = "🪦", BonePickaxe = "🦴", PumpkinSmasher = "🎃", GhostScythe = "👻", LivingCoffin = "⚰️", SoulReaper = "💀" }

-- a skin's 3D preview: (frame, controller {Model, Step(dt, kick), SetLocked(on)}) or nil. Framed on the model's box for
-- the slot's aspect (thin scythes fill the slot's height), the camera orbits (cheap: one CFrame per frame) with the key
-- light turning along, so the skin reads as spinning on a turntable like the pickaxe shop's preview.
local function skinViewport(id: string, aspect: number?): (any, any)
	local mod = Halloween and Halloween:FindFirstChild("PickaxeSkins")
	if not mod then
		return nil, nil
	end
	local okM, Skins = pcall(require, mod)
	if not okM or type(Skins) ~= "table" or not Skins.Build then
		return nil, nil
	end
	local okB, model = pcall(Skins.Build, id)
	if not okB or typeof(model) ~= "Instance" then
		return nil, nil
	end
	model:SetAttribute("SkinId", id)
	local vp = Kit.New("ViewportFrame", { Name = "Preview3D", BackgroundTransparency = 1, Ambient = C(180, 160, 220), LightColor = C(255, 236, 210),
		LightDirection = Vector3.new(-1, -1.2, -0.5), Size = UDim2.fromScale(1, 1), ZIndex = Z + 2 })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 28
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local okBox, cf, size = pcall(function()
		if model:IsA("Model") then
			return model:GetBoundingBox()
		end
		return (model :: any).CFrame, (model :: any).Size
	end)
	local focus = okBox and cf.Position or Vector3.zero
	local box = okBox and size or Vector3.new(2, 5, 2)
	local tanH = math.tan(math.rad(cam.FieldOfView / 2))
	local wide = math.max(box.X, box.Z)
	local dist = math.max(box.Y / 2 / tanH, wide / 2 / (tanH * math.max(0.4, aspect or 1.4))) * 1.08 + wide / 2
	local light0 = Vector3.new(-1, -1.2, -0.5)
	local spin = math.rad(40)
	local function place(a: number, bob: number)
		local dir = Vector3.new(math.sin(a) * 0.96, 0.18, math.cos(a) * 0.96).Unit
		cam.CFrame = CFrame.lookAt(focus + dir * dist + Vector3.new(0, bob, 0), focus + Vector3.new(0, bob, 0))
		vp.LightDirection = CFrame.Angles(0, a - math.rad(40), 0) * light0
	end
	place(spin, 0)
	local ctl = { Model = model, Skins = Skins }
	function ctl.Step(dt: number, kick: number)
		spin += dt * (0.9 + kick * 12)
		place(spin, math.sin(os.clock() * 1.6) * 0.15)
	end
	function ctl.SetLocked(on: boolean)
		vp.Ambient = on and C(70, 60, 96) or C(180, 160, 220)
		vp.LightColor = on and C(120, 110, 150) or C(255, 236, 210)
		vp.ImageColor3 = on and C(150, 140, 175) or WHITE
	end
	return vp, ctl
end

pages.cosmetics = function(page: Frame)
	local P = {}
	local scroll = scrollPage(page)
	local orderList = (Config.Skins and Config.Skins.Order) or {}
	local head = panel(scroll, "Header", C(86, 40, 120), C(54, 22, 84))
	local headTitle = sectionTitle(head, "⛏️", T("PICKAXE SKINS"))
	local headInfo = txt(head, { Name = "Info", Text = T("Skins only change the look. Every stat still comes from your real pickaxe."), TextSize = 14,
		Scaled = true, MinTextSize = 8, Color = MUTED })
	local unequip
	unequip = button(head, { Name = "Unequip", Text = T("UNEQUIP"), Style = "secondary", TextSize = 15, OnClick = function()
		act(unequip, "SkinEquip", { Id = "" })
	end })
	local cards = {}
	local equipBurst
	for i, id in ipairs(orderList) do
		local rarityName = (Config.Skins.Rarity and Config.Skins.Rarity[id]) or "Epic"
		local card = panel(scroll, "Skin_" .. id)
		local holder = Kit.New("Frame", { Name = "PreviewHolder", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = Z + 1, ClipsDescendants = true }, card)
		Kit.Corner(holder, 12)
		local rc = RARITY[rarityName] or PURPLE
		gradient(holder, rc:Lerp(C(40, 18, 62), 0.55), C(18, 8, 30))
		-- a turntable glow under the preview
		local disc = Kit.New("Frame", { Name = "Turntable", BorderSizePixel = 0, BackgroundColor3 = rc, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.62, 0.16), ZIndex = Z + 1 }, holder)
		Kit.Corner(disc, "pill")
		Kit.New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1) }) }, disc)
		local glyph = txt(holder, { Name = "Glyph", Text = SKIN_GLYPH[id] or "⛏️", TextSize = 70, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = Z + 2 })
		local glyphArt = art(glyph, "Pickaxe", { Size = 90, ZIndex = Z + 2, Glow = rc }, glyph)
		local lockF = Kit.New("Frame", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8),
			Size = UDim2.fromOffset(30, 30), ZIndex = Z + 4, Visible = false }, holder)
		art(lockF, "Lock", { Size = 30, ZIndex = Z + 4 })
		local rarity = Kit.Pill(card, { Name = "Rarity", Text = T(string.upper(rarityName)), Color = rc, Height = 22, TextSize = 12, NoTranslate = true,
			ZIndex = Z + 3 })
		local grad = Theme.RarityGradient[rarityName]
		if grad then
			rarity:SetGradient(grad[1], grad[2])
		end
		local name = txt(card, { Name = "Name", Text = skinName(id), TextSize = 19, Scaled = true, MinTextSize = 10, AlignX = "Center", Stroke = 0.4 })
		local source = txt(card, { Name = "Source", Text = "", TextSize = 12, Wrap = true, AlignX = "Center", AlignY = "Top", Color = MUTED })
		local equip
		equip = button(card, { Name = "Equip", Text = T("EQUIP"), Color = PUMPKIN, TextSize = 16, OnClick = function()
			act(equip, "SkinEquip", { Id = id }, function()
				equipBurst(i)
			end)
		end })
		cards[i] = { Id = id, Frame = card, Holder = holder, Glyph = glyph, GlyphArt = glyphArt, Lock = lockF, Rarity = rarity, Name = name, Source = source,
			Equip = equip, Color = rc, Kick = 0 }
		-- tap / click a still preview: it turns for a moment (a scroll drag on phones does the same, harmlessly)
		holder.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				local c = cards[i]
				c.Kick = math.max(c.Kick, 0.6)
			end
		end)
	end

	-- equip feedback: the preview kicks into a fast spin, the card rim flashes, sparkles burst out of the slot, the claim cue
	equipBurst = function(i: number)
		local c = cards[i]
		if not c then
			return
		end
		c.Kick = 1
		audio("Claim")
		local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
		local reduced = Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion())
		if stroke then
			stroke.Color = WHITE
			stroke.Thickness = reduced and 3 or 7
			TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Color = NEON, Thickness = 3 }):Play()
		end
		if reduced then
			return
		end
		local pop = c.Frame:FindFirstChild("EquipPop") or Kit.New("UIScale", { Name = "EquipPop" }, c.Frame)
		pop.Scale = 1.06
		TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local w, h = c.Holder.AbsoluteSize.X, c.Holder.AbsoluteSize.Y
		if w < 4 then
			w, h = 200, 140
		end
		for k = 1, 14 do
			local a = (k / 14) * math.pi * 2
			local sz = math.random(6, 11)
			local s = Kit.New("Frame", { Name = "Sparkle", BorderSizePixel = 0, BackgroundColor3 = (k % 3 == 0) and WHITE or (k % 3 == 1) and c.Color or NEON,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w / 2, h / 2), Size = UDim2.fromOffset(sz, sz), Rotation = 45, ZIndex = Z + 5 }, c.Holder)
			Kit.Corner(s, 3)
			local d = math.min(w, h) * (0.35 + math.random() * 0.2)
			TweenService:Create(s, TweenInfo.new(0.55 + math.random() * 0.25, Enum.EasingStyle.Quart), { Position = UDim2.fromOffset(w / 2 + math.cos(a) * d, h / 2 + math.sin(a) * d * 0.8),
				BackgroundTransparency = 1, Rotation = 225, Size = UDim2.fromOffset(sz * 0.4, sz * 0.4) }):Play()
			task.delay(0.85, function()
				s:Destroy()
			end)
		end
	end

	function P.Layout(L)
		local w = L.Width - 12
		local narrow = w < 640
		place(head, 2, 2, w, narrow and 104 or 64)
		place(headTitle, 16, 10, narrow and w - 32 or w * 0.4, 26)
		place(headInfo, 16, narrow and 40 or 36, narrow and w - 32 or w - 220, 20)
		place(unequip.Instance, narrow and 16 or w - 166, narrow and 64 or 11, 150, narrow and 34 or 42)
		local y = (narrow and 104 or 64) + 12
		local cols = w >= 900 and 3 or 2
		local gap = 12
		local cw = math.floor((w - gap * (cols - 1)) / cols)
		local ch = narrow and 262 or 262
		P.Aspect = (cw - 16) / math.max(1, ch - 120)
		for i, c in ipairs(cards) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			place(c.Frame, 2 + col * (cw + gap), y + row * (ch + gap), cw, ch)
			local ph = ch - 120
			place(c.Holder, 8, 8, cw - 16, ph)
			place(c.Glyph, (cw - 16) / 2 - ph * 0.4, ph * 0.1, ph * 0.8, ph * 0.8)
			c.Rarity.Instance.AnchorPoint = Vector2.new(1, 0)
			c.Rarity.Instance.Position = UDim2.new(1, -14, 0, 14)
			place(c.Name, 8, ph + 12, cw - 16, 24)
			-- the source line gets the room down to the button (two lines; long Russian sources shrink)
			place(c.Source, 10, ph + 38, cw - 20, ch - ph - 38 - 56)
			local fit = 12
			while fit > 9 and textH(c.Source.Text, fit, cw - 20) > ch - ph - 38 - 56 do
				fit -= 1
			end
			c.Source.TextSize = fit
			place(c.Equip.Instance, 12, ch - 52, cw - 24, 42)
		end
		scroll.CanvasSize = UDim2.fromOffset(0, y + math.ceil(#cards / cols) * (ch + gap) + 4)
	end

	-- one frame loop while the tab is open. A ViewportFrame whose camera does not move is not re-rendered, so only ONE
	-- preview turns continuously: the equipped skin (not on Low), and only while its card is on screen. Every other card
	-- is a still render at its 3/4 angle; equipping (or tapping a preview) kicks that card into a short spin. The equipped
	-- skin also runs its living motion (PickaxeSkins.Track through the MiningClient's PickFX) while the tab is open only.
	local tracked = nil
	local function untrack()
		if tracked and tracked.Ctl then
			pcall(tracked.Ctl.Skins.Untrack, tracked.Ctl.Model)
		end
		tracked = nil
	end
	local function onScreen(c): boolean
		local y, h = c.Holder.AbsolutePosition.Y, c.Holder.AbsoluteSize.Y
		local top = scroll.AbsolutePosition.Y
		return y + h > top and y < top + scroll.AbsoluteSize.Y
	end
	local spinLoop = pageLoop("cosmetics", function(dt)
		if Kit.Motion.Reduced() or (Shared and Shared.ReducedMotion()) then
			return -- still previews; the loop only keeps the close hook armed
		end
		local low = Shared and Shared.Low()
		local equipped = view().Skin or ""
		for _, c in ipairs(cards) do
			if c.Ctl then
				if (c.Kick > 0 or (not low and c.Id == equipped)) and onScreen(c) then
					c.Ctl.Step(dt, c.Kick)
				end
				c.Kick = math.max(0, c.Kick - dt * 1.7)
			end
		end
	end, untrack) -- window closed / tab changed: the hidden preview stops animating in PickFX
	local function track()
		local equipped = view().Skin or ""
		local want = nil
		if not (Shared and Shared.Low()) and win and win.IsOpen and st.Tab == "cosmetics" then
			for _, c in ipairs(cards) do
				if c.Id == equipped and c.Ctl then
					want = c
				end
			end
		end
		if tracked == want then
			return
		end
		untrack()
		tracked = want
		if want then
			pcall(want.Ctl.Skins.Track, want.Ctl.Model, true)
		end
	end

	function P.Shown()
		-- 3D previews are built the first time the tab is opened (300-700 parts per skin). The loop also runs under
		-- ReducedMotion (no turning there, see Step) so closing the tab always untracks the living preview.
		spinLoop()
		if P.Built then
			track()
			return
		end
		P.Built = true
		task.spawn(function()
			for _, c in ipairs(cards) do
				local vp, ctl = skinViewport(c.Id, P.Aspect)
				if vp then
					vp.Parent = c.Holder
					c.Glyph.Visible = false
					c.Ctl = ctl
					ctl.SetLocked(not ((view().Skins or {})[c.Id] == true))
				end
				task.wait()
			end
			track()
		end)
	end

	function P.Refresh()
		local v = view()
		local owned = v.Skins or {}
		local equipped = v.Skin or ""
		unequip.Instance.Visible = equipped ~= ""
		for _, c in ipairs(cards) do
			local has = owned[c.Id] == true
			local on = equipped == c.Id
			local srcs = skinSources(c.Id)
			c.Source.Text = has and T("Owned forever: keep it after the event.") or (#srcs > 0 and (T("Find it in:") .. " " .. table.concat(srcs, " · ")) or "")
			local stroke = c.Frame:FindFirstChildWhichIsA("UIStroke")
			if stroke and c.Kick <= 0 then
				stroke.Color = on and NEON or has and PUMPKIN_HI or PANEL_EDGE
				stroke.Thickness = on and 3 or 2
				stroke.Transparency = 0.1
			end
			c.Glyph.TextTransparency = (has and not c.GlyphArt) and 0 or (c.GlyphArt and 1 or 0.55)
			if c.GlyphArt then
				c.GlyphArt:Set("Pickaxe", { Size = 90, Glow = c.Color, Dim = (not has) and 0.55 or nil })
			end
			c.Lock.Visible = not has
			if c.Ctl then
				c.Ctl.SetLocked(not has)
			end
			if on then
				c.Equip:SetText("✓ " .. T("EQUIPPED"))
				c.Equip:SetStyle("success")
				c.Equip:SetDisabled(true)
			elseif has then
				c.Equip:SetText(T("EQUIP"))
				c.Equip:SetStyle("primary", PUMPKIN)
				c.Equip:SetDisabled(false)
			else
				c.Equip:SetText("🔒 " .. T("LOCKED"))
				c.Equip:SetStyle("secondary")
				c.Equip:SetDisabled(true)
			end
		end
		track()
	end
	return P
end

------------------------------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------------------------------
local TAB_TEXT = { event = "EVENT", quests = "QUESTS", dex = "EVENT DOGDEX", cauldron = "CAULDRON", boss = "BOSS", cosmetics = "COSMETICS" }
local TAB_ALIAS = { overview = "event", exorcism = "event", home = "event", quest = "quests", dogdex = "dex", eventdex = "dex", trick = "cauldron",
	treat = "cauldron", gravekeeper = "boss", bell = "boss", skins = "cosmetics", skin = "cosmetics" }

local function tabOf(arg: any): string?
	local id = type(arg) == "table" and arg.Tab or arg
	if type(id) ~= "string" then
		return nil
	end
	id = string.lower(id)
	id = TAB_ALIAS[id] or id
	return TAB_TEXT[id] and id or nil
end

local function restyleTabs(tabs: any)
	-- the kit pill tabs on the dark card: purple glass when off, pumpkin when selected
	function tabs._paint(self, instant)
		for id, entry in pairs(self.Buttons) do
			local on = id == self.Selected
			local goal = { BackgroundColor3 = on and PUMPKIN or TAB_OFF }
			if instant then
				entry.Face.BackgroundColor3 = goal.BackgroundColor3
			else
				Motion.Tween(entry.Face, Theme.Motion.Fast, goal)
			end
			entry.Caption.TextColor3 = on and WHITE or SOFT
			entry.Caption.TextStrokeColor3 = INK
			entry.Caption.TextStrokeTransparency = on and 0.35 or 1
			local stroke = entry.Face:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = on and INK or PANEL_EDGE
				stroke.Transparency = on and 0 or 0.25
			end
		end
	end
	tabs:_paint(true)
end

local function build()
	if ui then
		return ui
	end
	ui = { Lang = Kit.Lang(), Pages = {} }
	local tabs = {}
	for _, id in ipairs(S.Tabs) do
		table.insert(tabs, { Id = id, Text = T(TAB_TEXT[id]), NoTranslate = true })
	end
	win = Kit.Window.new({
		Key = "Halloween", Name = "HalloweenWindow", Title = T("NIGHT OF THE BURIED MOON"),
		Subtitle = T("THE DEAD YARD · candy, curses and the Blood Moon"), Accent = PUMPKIN, Icon = "HalloweenGlyph", NoTranslate = true,
		MaxSize = Vector2.new(1140, 790), Tabs = tabs, Tab = "event",
		OnOpen = function()
			S._opened()
		end,
		OnTab = function(id)
			st.Tab = id
			local p = ui and ui.Pages[id]
			if p and p.Shown then
				p.Shown()
			end
			audio("UiTab")
		end,
	})
	S.Window = win
	-- dark Halloween skin of the kit window
	gradient(win.Card, BG_TOP, BG_BOTTOM)
	win.Cover.BackgroundColor3 = BG_BOTTOM
	win.CardStroke.Color = INK
	win.HeaderGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C(255, 156, 52)), ColorSequenceKeypoint.new(0.55, C(222, 92, 40)), ColorSequenceKeypoint.new(1, C(120, 52, 190)),
	})
	win.HeaderGradient.Rotation = 0
	local headerStroke = win.Header:FindFirstChildWhichIsA("UIStroke")
	if headerStroke then
		headerStroke.Color = INK
	end
	if win.Icon and win.Icon:IsA("TextLabel") then
		win.Icon.Text = "🎃"
		win.Icon.TextSize = 54
		local limit = win.Icon:FindFirstChildWhichIsA("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = 54
		end
		-- the built jack-o'-lantern in the header (a touch larger than the icon box, like the kit's image icons)
		art(win.Icon, "Pumpkin", { Size = 56, ZIndex = (win.Icon.ZIndex or 4) + 1, FrameSize = UDim2.fromScale(1.0, 1.0), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5) }, win.Icon)
	end
	if win.Tabs then
		restyleTabs(win.Tabs)
	end
	-- the candy balance in the header (left of the close button)
	local chip = Kit.New("Frame", { Name = "CandyChip", BorderSizePixel = 0, BackgroundColor3 = C(30, 12, 44), BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(1, 0.5), ZIndex = 5 }, win.Header)
	Kit.Corner(chip, "pill")
	Kit.Stroke(chip, PUMPKIN_HI, 2, 0.1)
	local chipGlyph = txt(chip, { Name = "Glyph", Text = "🍬", TextSize = 22, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = 6 })
	art(chipGlyph, "Candy", { Size = 34, ZIndex = 7, FrameSize = UDim2.fromScale(1.12, 1.12), Position = UDim2.fromScale(0.44, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5) }, chipGlyph)
	local chipValue = txt(chip, { Name = "Value", Text = "0", TextSize = 22, Scaled = true, MinTextSize = 9, Font = "numeric", Color = PUMPKIN_HI, ZIndex = 6,
		Stroke = 0.4 })
	ui.Chip, ui.ChipValue = chip, chipValue
	local function placeChip(L)
		local headerH = win.Header.AbsoluteSize.Y > 0 and win.Header.AbsoluteSize.Y or (L.Phone and (L.Landscape and 50 or 58) or 74)
		local closeSize = L.Phone and math.min(44, headerH - 8) or 48
		local cw = L.Phone and 96 or 132
		local ch = L.Phone and 32 or 40
		chip.Size = UDim2.fromOffset(cw, ch)
		chip.Position = UDim2.new(1, -(closeSize + (headerH - closeSize) / 2 + 10), 0.5, 0)
		place(chipGlyph, 6, 3, ch - 6, ch - 6)
		place(chipValue, ch + 2, 2, cw - ch - 10, ch - 4)
		local textX = win.Title.Position.X.Offset
		local titleSpan = -(textX + closeSize + 18 + cw + 12)
		local portrait = L.Phone and not L.Landscape
		local short = T("BURIED MOON")
		if portrait and L.Width and textW(short, 14) > L.Width + titleSpan - 8 then
			short = T("HALLOWEEN") -- ПОГРЕБЁННАЯ ЛУНА does not fit beside the candy chip on a narrow phone
		end
		win.Title.Text = portrait and short or T("NIGHT OF THE BURIED MOON")
		if portrait then
			win.Subtitle.Visible = false
			local th = win.Title.Size.Y.Offset
			win.Title.Position = UDim2.fromOffset(textX, math.floor((headerH - th) / 2))
		end
		win.Title.Size = UDim2.new(1, titleSpan, 0, win.Title.Size.Y.Offset)
		win.Subtitle.Size = UDim2.new(1, titleSpan, 0, win.Subtitle.Size.Y.Offset)
	end
	for _, id in ipairs(S.Tabs) do
		local ok, p = pcall(pages[id], win:Page(id))
		if ok then
			ui.Pages[id] = p
		else
			warn("HalloweenScreen: page " .. id .. " failed: " .. tostring(p))
		end
	end
	win.Resized:Connect(function(L)
		if (L.Width or 0) < 60 then
			return
		end
		placeChip(L)
		for _, p in pairs(ui.Pages) do
			if p.Layout then
				local ok, err = pcall(p.Layout, L)
				if not ok then
					warn("HalloweenScreen layout: " .. tostring(err))
				end
			end
		end
		-- reward chip rows flow with the new widths
		if win.IsOpen then
			refreshAll()
		end
		task.defer(revealTab)
	end)
	return ui
end

local function badges()
	if not (ui and win) then
		return
	end
	local v = view()
	local ready = 0
	for _, q in ipairs(v.Quests and v.Quests.List or {}) do
		if not q.Claimed and (q.Progress or 0) >= (q.Goal or 1) then
			ready += 1
		end
	end
	win:SetBadge("quests", ready > 0 and ready or nil)
	local dex = ui.Pages.dex
	win:SetBadge("dex", dex and (dex.Ready or 0) > 0 and dex.Ready or nil)
	local c = v.Cauldron or {}
	win:SetBadge("cauldron", (c.StartedAt or 0) > 0 and not c.Claimed and (c.ReadyAt or 0) <= now() and "!" or nil)
	win:SetBadge("boss", bossActive(folderAttrs("Boss")) and "!" or nil)
end

refreshAll = function()
	if not ui then
		return
	end
	ui.ChipValue.Text = num(candy())
	for id, p in pairs(ui.Pages) do
		if p.Refresh then
			local ok, err = pcall(p.Refresh)
			if not ok then
				warn("HalloweenScreen refresh " .. id .. ": " .. tostring(err))
			end
		end
	end
	badges()
end
S.Refresh = function()
	refreshAll()
end

function S._opened()
	local token = win.Token
	refreshAll()
	local maid = win.OpenMaid
	if Bus then
		maid:Give(Bus.On("StateChanged", function(d)
			if d and type(d.View) == "table" and d.View ~= st.View then
				st.View = d.View
				refreshAll()
			end
		end))
	end
	for _, attr in ipairs({ "MoonCandy", "MoonCurse", "HwBossUnlocked", "HwInZone", "HwCandyMult", "HwRushActive", "HwMapDecor" }) do
		maid:Give(player:GetAttributeChangedSignal(attr):Connect(function()
			if win.IsOpen then
				refreshAll()
			end
		end))
	end
	local f = stateFolder()
	if f then
		for _, name in ipairs({ "Exorcism", "Boss" }) do
			local sub = f:FindFirstChild(name)
			if sub then
				maid:Give(sub.AttributeChanged:Connect(function()
					if win.IsOpen then
						local p = ui.Pages[name == "Boss" and "boss" or "event"]
						if p and p.Refresh then
							pcall(p.Refresh)
						end
						badges()
					end
				end))
			end
		end
	end
	-- live timers (Blood Moon, rush, brew, quest reset, boss cooldown): 2 Hz while open
	task.spawn(function()
		while win and win.IsOpen and win.Token == token do
			for _, p in pairs(ui.Pages) do
				if p.Tick then
					pcall(p.Tick)
				end
			end
			ui.ChipValue.Text = num(candy())
			task.wait(0.5)
		end
	end)
	-- a fresh view from the server
	task.spawn(function()
		local ok, res = invoke("Hello", {})
		if ok and type(res) == "table" and win.IsOpen and win.Token == token then
			refreshAll()
		end
	end)
end

-- the DogDex window on its event tab (WP4 adds the tab; falls back to the collection)
function S.OpenDogDex()
	local mod = script.Parent:FindFirstChild("DogdexScreen")
	local ok, dex = false, nil
	if mod then
		ok, dex = pcall(require, mod)
	end
	if not ok or type(dex) ~= "table" or not dex.Open then
		local n = nav()
		if n then
			n.OpenPage("DogDex")
		end
		return
	end
	if type(dex.OpenEvent) == "function" then -- WP4: DogdexScreen.OpenEvent() opens its BURIED MOON 2026 tab
		if pcall(dex.OpenEvent) then
			return
		end
	end
	pcall(dex.Open)
	local w = dex.Window
	if w and w.Pages then
		for _, id in ipairs({ dex.EventTab or "", "event", "buriedmoon", "BuriedMoon", "halloween" }) do
			if id ~= "" and w.Pages[id] then
				pcall(function()
					w:SetTab(id)
				end)
				break
			end
		end
	end
end

-- scroll the tab strip so the selected tab is in sight (phones: six tabs do not fit; opening straight on BOSS / COSMETICS)
function revealTab()
	local tabs = win and win.Tabs
	local entry = tabs and tabs.Selected and tabs.Buttons and tabs.Buttons[tabs.Selected]
	local strip = tabs and tabs.Instance
	if not (entry and strip and strip:IsA("ScrollingFrame")) then
		return
	end
	local view = strip.AbsoluteSize.X
	if view < 40 then
		return
	end
	local left = entry.X or entry.Button.Position.X.Offset
	local right = left + (entry.W or entry.Button.Size.X.Offset)
	local x = strip.CanvasPosition.X
	if left < x then
		x = math.max(0, left - 12)
	elseif right > x + view then
		x = right - view + 12
	end
	if x ~= strip.CanvasPosition.X then
		strip.CanvasPosition = Vector2.new(x, 0)
	end
end

function S.Open(arg: any?, _page: any?)
	if not Config.HalloweenEventEnabled or (Shared and not Shared.Enabled()) then
		Kit.Toast(T("The Night of the Buried Moon has ended"), { Kind = "warn", NoTranslate = true })
		return
	end
	if ui and ui.Lang ~= Kit.Lang() and not (win and win.IsOpen) then
		win:Destroy()
		ui, win = nil, nil
	end
	if st.View == nil and Bus then
		local last = Bus.Last("StateChanged")
		if type(last) == "table" and type(last.View) == "table" then
			st.View = last.View
		end
	end
	build()
	local tab = tabOf(arg) or st.Tab
	if tab and ui.Pages[tab] then
		win:SetTab(tab, false)
		st.Tab = tab
	end
	-- {Tab = "dex", Chapter = 2}: the dex tab on THE UNDERYARD COLLECTION (WP-L)
	local chapter = type(arg) == "table" and tonumber(arg.Chapter) or nil
	if chapter and ui.Pages.dex and ui.Pages.dex.Select then
		ui.Pages.dex.Select(chapter)
	end
	if not win.IsOpen then
		win:Open()
	end
	task.defer(revealTab)
	local p = ui.Pages[win.Tab or "event"]
	if p and p.Shown then
		p.Shown()
	end
	audio("UiOpen")
end

function S.Close()
	if win and win.IsOpen then
		win:Close("close")
	end
end

function S.IsOpen(): boolean
	return win ~= nil and win.IsOpen
end

-- latest view pushed by HalloweenClient (kept while the window is closed so the first open is instant)
if Bus then
	Bus.On("StateChanged", function(d)
		if d and type(d.View) == "table" then
			st.View = d.View
		end
	end)
	-- a reward card from anywhere (CauldronFX's finale without a Reveal callback, the Studio debug panel)
	Bus.On("RewardReveal", function(d)
		if type(d) == "table" and type(d.Rows) == "table" then
			rewardsDialog(tostring(d.Title or T("THE BURIED MOON BREW")), d.Rows, { Kicker = d.Kicker })
		end
	end)
	Bus.On("OpenWindow", function(d)
		local n = nav()
		if n and n.OpenPage then
			n.OpenPage("Halloween", { Tab = type(d) == "table" and d.Tab or nil })
		else
			S.Open(d)
		end
	end)
end
S.T, S.F, S.Said = T, F, said

return S
