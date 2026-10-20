-- KENNEL window (UI kit, Key 'Kennel'; docs/UIKIT.md): the dog picker of one dig kennel.
-- Opened by the kennel's ProximityPrompt: DogKennelService (server) -> DogKennelOpen:FireClient(slot) ->
-- GUIIntegration N.OpenService('Kennels', {Slot, YardId}) -> ServiceMenusController.open -> S.Open(context).
--   * IN THIS KENNEL: the dog working here now (preview, rarity, mutation, coins / min, REMOVE; tap it to
--     select it) or EMPTY KENNEL;
--   * a card per other dog: rarity ribbon + rarity frame, mutation glyph + coloured aura behind the 3D
--     preview + mutation pill, coins / min, where it is (kennel N / arriving); search, sort (best first:
--     rarity, then mutation, then income) and filter chips (idle, working, mutated, every rarity);
--   * SELECTED DOG: big preview, tags, stats, the income change against the dog inside, and ONE button:
--     PUT TO WORK (empty kennel) / SWAP (the dog inside goes to storage) / MOVE HERE (from another
--     kennel) / REMOVE FROM KENNEL. Phones: a bottom bar carries the selected dog and the button.
-- Colours: rarity = Kit.Theme (ribbon, frame, pill); mutation = ReplicatedStorage.MutationGlow.Styles
-- (the glow the dog wears in the world), read at load with a copy below as the fallback.
-- Rules: Modules.KennelLogic (pure). Requests: Assign / Remove through Modules.Net (each reply carries a
-- StateSnapshot). Text: Localization.Kennel (falls back to Localization.Dogs), labels NoTranslate except
-- dog names (DOGROTS_AutoTranslateUI translates them). tools/sim_kennel_ui.luau runs it offline.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Kit = require(script.Parent.Kit)
local Base = require(script.Parent.Kit.Base)
local Logic = require(script.Parent.KennelLogic)
local Defs = require(RS:WaitForChild("DogEconomy"):WaitForChild("DogDefinitions"))
local Loc = RS:WaitForChild("Localization")
local Dict = require(Loc:WaitForChild("Kennel"))
local DogsDict = require(Loc:WaitForChild("Dogs"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local C = Color3.fromRGB
local ACCENT = C(255, 169, 38) -- UITheme.WindowSpecs.Dogs
local Z = 3
local CLOSE_AFTER_ASSIGN = true -- a dog that starts work closes the window: the player sees it run in

local S = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function ru()
	return Kit.Lang() == "ru"
end
local function T(en)
	if ru() then
		return Dict.UI[en] or DogsDict.UI[en] or en
	end
	return en
end
local function F(en, ...)
	local pattern = en
	if ru() then
		pattern = Dict.Templates[en] or DogsDict.Templates[en] or en
	end
	return string.format(pattern, ...)
end
local function short(n)
	return Format.Short(tonumber(n) or 0, 1)
end

------------------------------------------------------------------------------------------------
-- Look of a rarity and of a mutation
------------------------------------------------------------------------------------------------
-- Mutation colours: the lighter and the darker of MutationGlow.Styles[v].Fill / .Outline (this copy is
-- the fallback and must match them: tools/test_kennel.luau checks it).
local LOOK = {
	Shiny = { Glyph = "✨", Top = C(235, 250, 255), Bottom = C(120, 225, 255), Motion = "Shimmer" },
	Golden = { Glyph = "👑", Top = C(255, 236, 140), Bottom = C(255, 196, 40), Motion = "Sweep" },
	Corrupted = { Glyph = "💀", Top = C(255, 40, 60), Bottom = C(150, 0, 22), Motion = "Flicker" },
	Glitched = { Glyph = "👾", Top = C(40, 239, 213), Bottom = C(255, 60, 220), Motion = "Glitch" },
	Void = { Glyph = "🌀", Top = C(178, 100, 255), Bottom = C(28, 0, 54), Motion = "Spin" },
}
S.Look = LOOK
local NORMAL_BG, NORMAL_LINE = C(236, 240, 246), C(200, 210, 222)

local function luminance(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end
do
	local ok, glow = pcall(function()
		local module = RS:FindFirstChild("MutationGlow")
		return module and module:IsA("ModuleScript") and require(module) or nil
	end)
	local styles = ok and type(glow) == "table" and type(glow.Styles) == "table" and glow.Styles or nil
	for name, look in pairs(styles and LOOK or {}) do
		local style = styles[name]
		if type(style) == "table" and typeof(style.Fill) == "Color3" and typeof(style.Outline) == "Color3" then
			local light, dark = style.Fill, style.Outline
			if luminance(light) < luminance(dark) then
				light, dark = dark, light
			end
			look.Top, look.Bottom = light, dark
		end
	end
end

-- Text colour and outline that read on a top -> bottom gradient: navy on very light colours, white
-- with the navy outline (the game's button text) on the rest.
local function inkOn(top, bottom)
	local l = luminance(top:Lerp(bottom, 0.5))
	if l > 0.78 then
		return Theme.Ink, 1
	end
	return Theme.White, l > 0.6 and 0 or 0.25
end
local function paintInk(label, top, bottom)
	local color, stroke = inkOn(top, bottom)
	label.TextColor3 = color
	label.TextStrokeColor3 = P.edge
	label.TextStrokeTransparency = stroke
end
local function rarityColors(rarity)
	local g = Theme.RarityGradient[rarity]
	if g then
		return g[1], g[2]
	end
	local c = Theme.RarityColor(rarity)
	return c:Lerp(Theme.White, 0.15), c
end
local function rarityWord(rarity)
	return T(string.upper(rarity or "Common"))
end
local function mutationWord(variant)
	return T(string.upper(variant or "Normal"))
end
-- Rarity pill: the rarity name on its colour (gradient for the top rarities).
local function paintRarityPill(pill, rarity)
	local top, bottom = rarityColors(rarity)
	pill:Set(rarityWord(rarity))
	pill:SetGradient(top, bottom)
	paintInk(pill.Label, top, bottom)
end
-- Mutation pill on the mutation gradient: glyph, name and income bonus (compact = false), glyph and
-- name (compact = true) or the glyph alone (compact = "glyph", narrow rows); a quiet outlined NO
-- MUTATION pill for Normal.
local function paintMutationPill(pill, stroke, variant, compact)
	local look = LOOK[variant or "Normal"]
	if look then
		local text = look.Glyph
		if compact ~= "glyph" then
			text = text .. " " .. mutationWord(variant)
			local bonus = Logic.BonusText(variant)
			if bonus ~= "" and not compact then
				text = text .. " " .. bonus
			end
		end
		pill:Set(text)
		pill:SetGradient(look.Top, look.Bottom)
		paintInk(pill.Label, look.Top, look.Bottom)
		-- light pills (Shiny, Golden) get an outline in their own darker colour so they stand out on white
		stroke.Enabled = luminance(look.Top:Lerp(look.Bottom, 0.5)) > 0.78
		stroke.Color = look.Bottom:Lerp(P.edge, 0.3)
	else
		pill:Set(T("NO MUTATION"), NORMAL_BG, P.muted)
		stroke.Enabled = true
		stroke.Color = NORMAL_LINE
	end
end
-- Preview stage: the rarity tint, or the mutation colours with a moving aura.
local function paintStage(stageGradient, aura, auraGradient, rarity, variant)
	local look = LOOK[variant or "Normal"]
	if look then
		-- strong enough to read as the mutation at a glance, light enough for the dog in front of it
		stageGradient.Color = ColorSequence.new(look.Top:Lerp(look.Bottom, 0.25):Lerp(Theme.White, 0.25), look.Bottom:Lerp(Theme.White, 0.2))
		aura.Visible = true
		aura.BackgroundTransparency = 0
		auraGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, look.Top),
			ColorSequenceKeypoint.new(0.5, Theme.White),
			ColorSequenceKeypoint.new(1, look.Bottom),
		})
		auraGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.55, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
	else
		local c = Theme.RarityColor(rarity)
		stageGradient.Color = ColorSequence.new(c:Lerp(Theme.White, 0.7), Theme.White)
		aura.Visible = false
	end
end
-- One animation step of an aura (t = os.clock()); seed de-synchronises the cards.
local function animateAura(aura, auraGradient, variant, t, seed)
	local look = LOOK[variant or ""]
	if not (look and aura.Visible) then
		return
	end
	local m = look.Motion
	local x = t + (seed or 0)
	if m == "Spin" then
		auraGradient.Rotation = (x * 40) % 360
		auraGradient.Offset = Vector2.zero
	elseif m == "Glitch" then
		if math.random() < 0.25 then
			auraGradient.Rotation = math.random(0, 3) * 90
			auraGradient.Offset = Vector2.new(math.random(-30, 30) / 100, math.random(-30, 30) / 100)
		end
	elseif m == "Flicker" then
		auraGradient.Rotation = 90
		auraGradient.Offset = Vector2.new(0, math.sin(x * 2.2) * 0.25)
		aura.BackgroundTransparency = math.random() < 0.12 and 0.6 or 0
	else -- Shimmer / Sweep: a bright band crosses the stage
		local period = m == "Sweep" and 1.8 or 2.6
		auraGradient.Rotation = 25
		auraGradient.Offset = Vector2.new(((x % period) / period) * 2 - 1, 0)
	end
end
S.Paint = { Rarity = paintRarityPill, Mutation = paintMutationPill, Stage = paintStage, Aura = animateAura, Ink = inkOn }

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local st = {
	Slot = nil, YardId = nil, Snapshot = nil, Entries = {}, List = {}, Occupant = nil, Selected = nil, Total = 0,
	Search = "", Sort = "best", Desc = true, Filter = { Rarities = {} }, Busy = false, Run = 0, Suggested = false,
	Resuggest = false, -- true from Open until the first fresh snapshot, a tap on a dog or a request
}
S.State = st
local ui = nil
local win = nil
local NetModule = nil
local function net()
	NetModule = NetModule or require(script.Parent.Net)
	return NetModule
end
local function profile()
	return st.Snapshot and st.Snapshot.Profile or nil
end
local function slotNumber()
	return Logic.SlotNumber(st.Slot) or 1
end
-- Hidden copies of every dog name (DOGROTS_AutoTranslateUI translates them): search and sentences in the
-- player's language.
local probes = {}
local function shownName(id)
	local probe = id and probes[id]
	if probe and probe.Parent then
		return probe.Text
	end
	local def = id and Defs[id]
	return def and def.DisplayName or tostring(id or "")
end

------------------------------------------------------------------------------------------------
-- Builders
------------------------------------------------------------------------------------------------
local function place(o, x, y, w, h)
	o.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	o.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
end
local function label(parent, props)
	props.NoTranslate = props.NoTranslate ~= false
	props.ZIndex = props.ZIndex or Z + 1
	props.Size = props.Size or UDim2.fromOffset(10, 10)
	return Kit.Text(parent, props)
end
local function frame(parent, name, z)
	return Kit.New("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z or Z, Size = UDim2.fromOffset(10, 10) }, parent)
end
local function panel(parent, name, z)
	local f = Kit.New("Frame", { Name = name, BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = z or Z }, parent)
	Kit.Corner(f, Theme.Radius.Card)
	Kit.Stroke(f, P.edge, 2, 0.55)
	return f
end
-- A selection ring: an accent outline 2 px around its parent (5 px outside it with the stroke).
local INSET = 5 -- content inset in the window body (it clips): rings and outlines stay visible
local function ring(parent, z, radius)
	local r = Kit.New("Frame", {
		Name = "SelectRing", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 4, 1, 4), Visible = false, ZIndex = z,
	}, parent)
	Kit.Corner(r, radius + 2)
	Kit.Stroke(r, Theme.Accent, 3)
	return r
end
-- A preview stage: tinted frame + aura + Kit.Preview slot + mutation glyph badge.
local function stage(parent, z, glyphSize)
	local s = {}
	s.Root = Kit.New("Frame", { Name = "Stage", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = z }, parent)
	Kit.Corner(s.Root, Theme.Radius.Field)
	s.Gradient = Kit.New("UIGradient", { Rotation = 90 }, s.Root)
	s.Aura = Kit.New("Frame", {
		Name = "Aura", BackgroundColor3 = Theme.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.6, 1.6), Visible = false, ZIndex = z,
	}, s.Root)
	s.AuraGradient = Kit.New("UIGradient", {}, s.Aura)
	s.Holder = frame(parent, "PreviewHolder", z + 1)
	s.Slot = Kit.Preview.Slot(s.Holder)
	s.Glyph = Kit.New("Frame", { Name = "Glyph", BackgroundColor3 = P.edge, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Visible = false, ZIndex = z + 3 }, parent)
	Kit.Corner(s.Glyph, "pill")
	Kit.Stroke(s.Glyph, Theme.White, 2)
	s.GlyphText = label(s.Glyph, { Name = "Glyph", Text = "", TextSize = glyphSize or 15, Scaled = true, MinTextSize = 8, AlignX = "Center", ZIndex = z + 4, Size = UDim2.fromScale(1, 1) })
	return s
end
local function placeStage(s, x, y, w, h, glyph)
	place(s.Root, x, y, w, h)
	local inset = math.floor(math.min(w, h) * 0.04)
	place(s.Holder, x + inset, y + inset, w - inset * 2, h - inset * 2)
	s.Glyph.Size = UDim2.fromOffset(glyph, glyph)
	s.Glyph.Position = UDim2.fromOffset(math.floor(x + w - 4), math.floor(y + 4))
end
local function setStageVisible(s, visible)
	s.Root.Visible = visible
	s.Holder.Visible = visible
	s.Glyph.Visible = visible and LOOK[s.Variant or "Normal"] ~= nil
end
local function showStage(s, dogId, rarity, variant)
	paintStage(s.Gradient, s.Aura, s.AuraGradient, rarity, variant)
	local look = LOOK[variant or "Normal"]
	s.Variant = variant
	s.Glyph.Visible = look ~= nil and s.Root.Visible
	if look then
		s.Glyph.BackgroundColor3 = look.Bottom
		s.GlyphText.Text = look.Glyph
	end
	s.Slot:Show(dogId and { Kind = "Dog", DogId = dogId, Variant = variant } or nil)
end
local function tagRow(parent, name, z, align)
	local row = frame(parent, name, z)
	local list = Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
	}, row)
	return row, list
end
-- Width of a line of window text (Fredoka One, the kit's font) in pixels.
local function textWidth(text, size)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(4000, 200))
	end)
	if ok and typeof(v) == "Vector2" then
		return v.X
	end
	return (utf8.len(text) or #text) * size * 0.7
end
-- The width the visible pills of a tag row need: each Kit.Pill is its text plus its UIPadding, with the
-- list's gap between them.
local function rowNeed(row)
	local list = row:FindFirstChildOfClass("UIListLayout")
	local total, n = 0, 0
	for _, c in ipairs(row:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			local text = c:FindFirstChild("Text")
			local pad = c:FindFirstChildOfClass("UIPadding")
			local w = (text and text:IsA("TextLabel")) and math.ceil(textWidth(text.Text, text.TextSize)) or c.AbsoluteSize.X
			total += w + (pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) or 0)
			n += 1
		end
	end
	return total + (list and list.Padding.Offset or 0) * math.max(0, n - 1)
end
-- Fits the pills of a tag row (placed with place(), so its width is Size.X.Offset) on small screens and
-- in long languages: runs the steps in order, each one making the row narrower, until the pills fit.
-- The caller paints the full texts and sizes first.
local function fitRow(row, steps)
	local width = row.Size.X.Offset
	for _, step in ipairs(steps) do
		if rowNeed(row) <= width then
			return
		end
		step()
	end
end
local TAG_TEXT, TAG_TEXT_SMALL = 11, 9 -- text of the small pills (card rows, IN THIS KENNEL) and its narrow-row size
local CAPTION_MIN = 9 -- smallest text of the IN THIS KENNEL caption
local function mutationPill(parent, height, textSize, z)
	local pill = Kit.Pill(parent, { Name = "Mutation", Height = height, TextSize = textSize, ZIndex = z, NoTranslate = true })
	local stroke = Kit.Stroke(pill.Instance, NORMAL_LINE, 1.5)
	return pill, stroke
end
local function coinsPill(parent, height, textSize, z)
	return Kit.Pill(parent, { Name = "Coins", Height = height, TextSize = textSize, Font = "numeric", PadX = 7, Color = C(255, 236, 180), TextColor = Theme.Ink, ZIndex = z, NoTranslate = true })
end
local COINS, COINS_BETTER = C(255, 236, 180), C(196, 240, 160)

------------------------------------------------------------------------------------------------
-- Card (a VirtualGrid cell): "card" layout in the grid, "row" layout on phones
------------------------------------------------------------------------------------------------
local Card = {}
Card.__index = Card

function Card.new(cellFrame)
	local self = setmetatable({}, Card)
	local z = (cellFrame.ZIndex or Z) + 1
	self.Maid = Kit.Maid.new()
	self.Seed = math.random() * 10
	local root = Kit.New("TextButton", {
		Name = "KennelCard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = z,
	}, cellFrame)
	self.Instance = root
	self.Maid:Give(root)
	self.Ring = ring(root, z, Theme.Radius.Card)
	self.Face = Base.Face(root, Theme.White, Theme.Radius.Card, z)
	self.Frame = Kit.Stroke(self.Face, P.edge, 3)
	self.FrameGradient = Kit.New("UIGradient", { Rotation = 90, Enabled = false }, self.Frame)
	Base.Press(root, nil, self.Maid, 1.03)
	-- rarity ribbon (card) / rarity bar + rarity pill (row)
	self.Ribbon = Kit.New("Frame", { Name = "Ribbon", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = z + 2 }, root)
	Kit.Corner(self.Ribbon, 11)
	self.RibbonGradient = Kit.New("UIGradient", { Rotation = 90 }, self.Ribbon)
	self.RibbonText = label(self.Ribbon, { Name = "Rarity", TextSize = 13, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = Theme.White, Stroke = 0.3, ZIndex = z + 3, Size = UDim2.fromScale(1, 1) })
	self.Bar = Kit.New("Frame", { Name = "RarityBar", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = z + 2 }, root)
	Kit.Corner(self.Bar, 3)
	self.BarGradient = Kit.New("UIGradient", { Rotation = 90 }, self.Bar)
	self.Stage = stage(root, z + 1, 15)
	self.Name = label(root, { Name = "DogName", TextSize = 16, Scaled = true, MinTextSize = 10, AlignX = "Center", NoTranslate = false, ZIndex = z + 3 })
	-- Tags: the mutation (cards) or rarity + where it is (rows); Tags2 (rows): mutation + ★ / 🔒
	self.Tags, self.TagsList = tagRow(root, "Tags", z + 3)
	self.Tags2 = tagRow(root, "Tags2", z + 3)
	self.RarityPill = Kit.Pill(self.Tags, { Name = "Rarity", Height = 20, TextSize = TAG_TEXT, LayoutOrder = 1, ZIndex = z + 4, NoTranslate = true })
	self.Mutation, self.MutationStroke = mutationPill(self.Tags, 20, 12, z + 4)
	self.Mutation.Instance.LayoutOrder = 1
	-- where it is (⛏ KENNEL n / ARRIVING): over the preview on cards (with ★ / 🔒), after the rarity on rows
	self.State = Kit.Pill(root, { Name = "Where", Height = 18, TextSize = 11, Color = Theme.Accent, LayoutOrder = 2, ZIndex = z + 5, NoTranslate = true })
	self.Marks = Kit.Pill(self.Tags2, { Name = "Marks", Height = 20, TextSize = 11, Color = P.edge, LayoutOrder = 2, ZIndex = z + 4, NoTranslate = true })
	self.Coins = coinsPill(root, 20, 12, z + 3)
	self.Veil = Kit.New("Frame", { Name = "Veil", BackgroundColor3 = Theme.White, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = z + 6 }, root)
	Kit.Corner(self.Veil, Theme.Radius.Card)
	self.Maid:Give(root.Activated:Connect(function()
		if self.OnClick and self.Entry then
			self.OnClick(self.Entry, self)
		end
	end))
	return self
end

function Card.Layout(self, w, h)
	local row = w >= h * 1.8
	self.Mode = row and "row" or "card"
	self.W, self.H = w, h
	self.Ribbon.Visible = not row
	self.Bar.Visible = row
	self.RarityPill.Instance.Visible = row
	self.Tags2.Visible = row
	self.State.Instance.AnchorPoint = Vector2.zero
	if not row then
		-- ribbon 22 | stage 48% (where-it-is pill on it) | name 20 | mutation pill 22 | coins 20
		self.State.Instance.Parent = self.Instance
		self.Mutation.Instance.Parent = self.Tags
		place(self.Ribbon, 4, 4, w - 8, 22)
		local sy, sh = 30, math.floor(h * 0.48)
		placeStage(self.Stage, 6, sy, w - 12, sh, 26)
		self.State.Instance.Position = UDim2.fromOffset(10, sy + 6)
		place(self.Name, 6, sy + sh + 6, w - 12, 20)
		place(self.Tags, 6, sy + sh + 30, w - 12, 22)
		self.TagsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		self.Coins.Instance.AnchorPoint = Vector2.new(0.5, 1)
		self.Coins.Instance.Position = UDim2.new(0.5, 0, 1, -8)
		self.Name.TextXAlignment = Enum.TextXAlignment.Center
	else
		-- rarity bar | square stage | name ........ coins
		--                           | rarity + where it is (⛏ KENNEL n / ARRIVING)
		--                           | mutation + ★ / 🔒
		self.State.Instance.Parent = self.Tags
		self.Mutation.Instance.Parent = self.Tags2
		local s = h - 16
		place(self.Bar, 4, 4, 6, h - 8)
		placeStage(self.Stage, 14, 8, s, s, 22)
		local x = 22 + s
		-- 26 px high, centred where the coins are: a long name on a narrow row (320 px phones) wraps onto
		-- two readable lines instead of two tiny ones
		place(self.Name, x, 4, w - x - 104, 26)
		self.Name.TextXAlignment = Enum.TextXAlignment.Left
		self.Coins.Instance.AnchorPoint = Vector2.new(1, 0)
		self.Coins.Instance.Position = UDim2.new(1, -8, 0, 7)
		place(self.Tags, x, 34, w - x - 8, 20)
		place(self.Tags2, x, 60, w - x - 8, 20)
		self.TagsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end
	if self.Entry then
		self:Bind(self.Entry, self.Ctx or {})
	end
end

-- e: KennelLogic entry. ctx: {Selected = uid, Better = coins of the dog inside or nil}
function Card.Bind(self, e, ctx)
	self.Entry, self.Ctx = e, ctx
	local top, bottom = rarityColors(e.Rarity)
	self.Frame.Color = Theme.White
	self.FrameGradient.Color = ColorSequence.new(top, bottom)
	self.FrameGradient.Enabled = true
	self.BarGradient.Color = ColorSequence.new(top, bottom)
	self.RibbonGradient.Color = ColorSequence.new(top, bottom)
	self.RibbonText.Text = rarityWord(e.Rarity)
	paintInk(self.RibbonText, top, bottom)
	paintRarityPill(self.RarityPill, e.Rarity)
	self.RarityPill.Label.TextSize = TAG_TEXT
	showStage(self.Stage, e.DogId, e.Rarity, e.Variant)
	self.Name.Text = e.Name
	-- the card is narrow: glyph + name here, the income bonus is in SELECTED DOG
	paintMutationPill(self.Mutation, self.MutationStroke, e.Variant, true)
	-- green: putting this dog here raises the team's income. A dog from another kennel never does (its
	-- kennel is left empty, KennelLogic.Gain), however much it earns.
	local better = ctx.Better ~= nil and e.Status ~= "Other" and e.Coins > ctx.Better
	self.Coins:Set(F("$%s / min", short(e.Coins)), better and COINS_BETTER or COINS, Theme.Ink)
	-- where it is (an idle dog in storage shows nothing); ★ favourite, 🔒 locked
	local marks = (e.Favorite and "★" or "") .. (e.Locked and "🔒" or "")
	local where, color
	if e.Status == "Other" then
		where, color = F("⛏ KENNEL %d", e.OtherSlot or 0), Theme.Accent
	elseif e.Status == "Arriving" then
		where, color = T("ARRIVING"), Theme.Disabled
	end
	local pill = where
	if self.Mode == "row" then
		self.Marks:SetVisible(marks ~= "")
		self.Marks:Set(marks, P.edge)
	else
		self.Marks:SetVisible(false)
		if marks ~= "" then
			pill = pill and (pill .. " " .. marks) or marks
		end
	end
	self.State:SetVisible(pill ~= nil)
	if pill then
		self.State:Set(pill, color or P.edge)
	end
	-- narrow rows (320 px phones, Russian): smaller rarity text, then "⛏ n", then the mutation glyph alone
	if self.Mode == "row" then
		fitRow(self.Tags, {
			function()
				self.RarityPill.Label.TextSize = TAG_TEXT_SMALL
			end,
			function()
				if e.Status == "Other" then
					self.State:Set("⛏ " .. tostring(e.OtherSlot or 0))
				end
			end,
		})
		fitRow(self.Tags2, {
			function()
				paintMutationPill(self.Mutation, self.MutationStroke, e.Variant, "glyph")
			end,
		})
	elseif self.Mode == "card" then
		fitRow(self.Tags, {
			function()
				paintMutationPill(self.Mutation, self.MutationStroke, e.Variant, "glyph")
			end,
		})
	end
	self.Veil.Visible = e.Status == "Arriving"
	self.Ring.Visible = ctx.Selected == e.Uid
end

function Card.Animate(self, t)
	if self.Entry then
		animateAura(self.Stage.Aura, self.Stage.AuraGradient, self.Entry.Variant, t, self.Seed)
	end
end

function Card.Destroy(self)
	self.Stage.Slot:Destroy()
	self.Maid:Clean()
end

------------------------------------------------------------------------------------------------
-- Data -> view
------------------------------------------------------------------------------------------------
local refresh, layout, renderDetail, renderOccupant

local function filtering()
	local f = st.Filter
	return (st.Search or "") ~= "" or f.Free or f.Working or f.Mutated or next(f.Rarities or {}) ~= nil
end

local function rebuild()
	local p = profile()
	local stats = st.Snapshot and st.Snapshot.DogStats or {}
	local player = Players.LocalPlayer
	local all = Logic.Entries(p, stats, st.Slot, player and player.UserId, shownName)
	st.Entries, st.Occupant = {}, nil
	for _, e in ipairs(all) do
		st.Entries[e.Uid] = e
		if e.Status == "Here" then
			st.Occupant = e
		end
	end
	local list = {}
	local filter = { Query = Logic.Fold(st.Search or ""), Free = st.Filter.Free, Working = st.Filter.Working, Mutated = st.Filter.Mutated, Rarities = st.Filter.Rarities }
	for _, e in ipairs(all) do
		if e.Status ~= "Here" and Logic.Match(e, filter) then
			table.insert(list, e)
		end
	end
	st.List = Logic.Sort(list, st.Sort, st.Desc)
	st.Total = #all - (st.Occupant and 1 or 0)
	if st.Selected and not st.Entries[st.Selected] then
		st.Selected = nil
	end
	-- the preselected dog; done again on the first fresh snapshot of this open (st.Resuggest) when the
	-- player has not picked one, since the cached snapshot may be minutes old
	if not st.Suggested and p then
		st.Suggested = true
		local pick = Logic.Suggest(Logic.Sort(table.clone(all), "best", true), st.Occupant)
		st.Selected = pick and pick.Uid or nil
	end
end

local function cardContext()
	return { Selected = st.Selected, Better = st.Occupant and st.Occupant.Coins or nil }
end

refresh = function(snapshot, resetScroll)
	if snapshot then
		st.Snapshot = snapshot
	end
	if not (ui and st.Snapshot) then
		return
	end
	rebuild()
	local n = slotNumber()
	win:SetTitle(F("KENNEL %d", n), st.Occupant and F("Now digging: %s", st.Occupant.Name) or T("Choose a dog to dig here"))
	local none = st.Total == 0 and st.Occupant == nil
	if ui.Grid.Empty then
		if st.Total == 0 then
			ui.Grid.Empty:Set({ Title = T("NO OTHER DOGS"), Body = T("Adopt more dogs at the DOG LINE.") })
		else
			ui.Grid.Empty:Set({ Title = T("NO DOGS HERE"), Body = T("Try another search or filter.") })
		end
	end
	ui.Grid:SetItems(st.List, { ResetScroll = resetScroll == true })
	ui.Count.Text = filtering() and F("%d / %d SHOWN", #st.List, st.Total or 0) or F("DOGS: %d", st.Total or 0)
	ui.NoDogs:SetVisible(none)
	ui.GridHost.Visible = not none
	renderOccupant()
	renderDetail()
	layout()
end
S.Refresh = refresh

-- Also before the first snapshot (st.Snapshot nil: "Loading..."), so no panel shows its default children.
renderOccupant = function()
	local o = ui.Occ
	local e = st.Occupant
	o.Empty.Visible = e == nil
	o.Empty.Text = st.Snapshot and (T("EMPTY KENNEL") .. "\n" .. T("Pick a dog and press PUT TO WORK")) or T("Loading...")
	for _, x in ipairs({ o.Name, o.Caption, o.TagsA, o.TagsB, o.Remove.Instance, o.Hit }) do
		x.Visible = e ~= nil
	end
	o.Remove.Instance.Visible = e ~= nil and o.WithButton == true
	o.TagsB.Visible = e ~= nil and o.Tall == true
	setStageVisible(o.Stage, e ~= nil)
	o.Ring.Visible = e ~= nil and st.Selected == e.Uid
	if not e then
		o.Stage.Slot:Show(nil)
		o.Frame.Color, o.Frame.Thickness, o.Frame.Transparency = P.edge, 2, 0.55
		o.FrameGradient.Enabled = false
		return
	end
	o.Name.Text = e.Name
	showStage(o.Stage, e.DogId, e.Rarity, e.Variant)
	paintRarityPill(o.Rarity, e.Rarity)
	o.Rarity.Label.TextSize, o.Mutation.Label.TextSize = TAG_TEXT, TAG_TEXT
	-- tall panel (desktop): rarity + coins, then the mutation with its bonus; strips: rarity + mutation
	paintMutationPill(o.Mutation, o.MutationStroke, e.Variant, not o.Tall)
	o.Coins:Set(F("$%s / min", short(e.Coins)), COINS, Theme.Ink)
	o.Coins.Instance.Visible = o.Tall == true
	local function glyphOnly()
		paintMutationPill(o.Mutation, o.MutationStroke, e.Variant, "glyph")
	end
	local function smallText()
		o.Rarity.Label.TextSize, o.Mutation.Label.TextSize = TAG_TEXT_SMALL, TAG_TEXT_SMALL
	end
	if o.Tall then
		fitRow(o.TagsA, { smallText })
		fitRow(o.TagsB, {
			function()
				paintMutationPill(o.Mutation, o.MutationStroke, e.Variant, true)
			end,
			glyphOnly,
		})
	else
		-- 320 px phones and the landscape strip in Russian: the glyph alone, then smaller text
		fitRow(o.TagsA, { glyphOnly, smallText })
	end
	-- strips: the caption carries the coins; on one line, or on two where the strip has room for them
	-- and one is too narrow (320 px phones cut the coins off)
	local caption = T("IN THIS KENNEL")
	local box = o.CaptionBox
	if box then
		local coins = F("$%s / min", short(e.Coins))
		local line = caption .. " · " .. coins
		local twoLines = box.H2 ~= nil and textWidth(line, CAPTION_MIN) > box.W
		caption = twoLines and (caption .. "\n" .. coins) or line
		o.Caption.TextWrapped = twoLines
		if twoLines then
			place(o.Caption, box.X, box.Y2, box.W, box.H2)
		else
			place(o.Caption, box.X, box.Y, box.W, box.H)
		end
	end
	o.Caption.Text = caption
	local top, bottom = rarityColors(e.Rarity)
	o.Frame.Color, o.Frame.Thickness, o.Frame.Transparency = Theme.White, 3, 0
	o.FrameGradient.Color = ColorSequence.new(top, bottom)
	o.FrameGradient.Enabled = true
end

local function planOf(e)
	return Logic.Plan(e, st.Occupant, st.Slot)
end
local ACTION = {
	Assign = { Text = "PUT TO WORK", Style = "success" },
	Swap = { Text = "SWAP", Style = "gold" },
	Move = { Text = "MOVE HERE", Style = "primary" },
	Remove = { Text = "REMOVE FROM KENNEL", Style = "danger" },
	Blocked = { Text = "Select a dog", Style = "secondary" },
	Arriving = { Text = "ARRIVING", Style = "secondary" },
}
S.Action = ACTION

local function whereText(e)
	if e.Status == "Here" then
		return T("Digging in this kennel")
	elseif e.Status == "Other" then
		return F("Digging in kennel %d", e.OtherSlot or 0)
	elseif e.Status == "Arriving" then
		return T("On the way to your yard")
	end
	return T("In storage")
end

-- The income line of SELECTED DOG: how the team's income changes when the dog starts work here.
local function deltaLine(e)
	local gain, emptied = Logic.Gain(e, st.Occupant)
	if gain == nil then
		return "", Theme.InkMuted
	elseif emptied then
		-- MOVE HERE: the dog earns the same here; its kennel is left empty and the dog inside goes to storage
		if gain <= -0.5 then
			return F("▼ −$%s / min · kennel %d will be empty", short(-gain), emptied), P.red
		end
		return F("Same income · kennel %d will be empty", emptied), Theme.InkMuted
	elseif math.abs(gain) < 0.5 then
		return T("Same income as now"), Theme.InkMuted
	elseif gain > 0 then
		return F("▲ +$%s / min more than now", short(gain)), C(74, 170, 22)
	end
	return F("▼ −$%s / min less than now", short(-gain)), P.red
end

renderDetail = function()
	local d = ui.Detail
	local e = st.Selected and st.Entries[st.Selected] or nil
	d.Hint.Visible = e == nil
	d.Hint.Text = st.Snapshot and T("Tap a dog to see it here") or T("Loading...")
	for _, x in ipairs({ d.Name, d.Tags, d.Where, d.Delta }) do
		x.Visible = e ~= nil
	end
	d.Stats.Visible = e ~= nil and d.ShowStats ~= false
	d.Frame.Visible = e ~= nil and d.ShowStage ~= false
	setStageVisible(d.Stage, e ~= nil and d.ShowStage ~= false)
	if not e then
		d.Stage.Slot:Show(nil)
	else
		d.Name.Text = e.Name
		showStage(d.Stage, e.DogId, e.Rarity, e.Variant)
		local top, bottom = rarityColors(e.Rarity)
		d.FrameGradient.Color = ColorSequence.new(top, bottom)
		paintRarityPill(d.Rarity, e.Rarity)
		paintMutationPill(d.Mutation, d.MutationStroke, e.Variant, false)
		fitRow(d.Tags, {
			function()
				paintMutationPill(d.Mutation, d.MutationStroke, e.Variant, true)
			end,
		})
		d.RowCoins:Set("$" .. short(e.Coins))
		d.RowEff:Set("x" .. string.format("%.2f", e.Efficiency))
		d.RowBonus:Set(Logic.BonusText(e.Variant) ~= "" and Logic.BonusText(e.Variant) or "—")
		d.Where.Text = whereText(e)
		d.Delta.Text, d.Delta.TextColor3 = deltaLine(e)
	end
	local plan = planOf(e)
	local look = ACTION[(e and e.Status == "Arriving") and "Arriving" or plan.Kind]
	for _, button in ipairs({ ui.Action, ui.BarAction }) do
		button:SetText(T(look.Text))
		button:SetStyle(look.Style)
		button:SetDisabled(e == nil or plan.Kind == "Blocked" or st.Busy)
	end
	-- phone bottom bar
	ui.BarName.Text = e and e.Name or (st.Snapshot and T("Tap a dog to see it here") or T("Loading..."))
	ui.BarName.TextColor3 = e and Theme.Ink or Theme.InkMuted
	ui.BarMutation.Instance.Visible = e ~= nil
	if e then
		paintMutationPill(ui.BarMutation, ui.BarMutationStroke, e.Variant, true)
	end
	if ui.Occ.Ring then
		ui.Occ.Ring.Visible = st.Occupant ~= nil and st.Selected == st.Occupant.Uid
	end
end

------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------
local function said(result)
	return tostring(type(result) == "table" and result.Message or result or "")
end
local function setBusy(busy)
	st.Busy = busy
	if ui then
		ui.Action:SetBusy(busy)
		ui.BarAction:SetBusy(busy)
		ui.Occ.Remove:SetBusy(busy)
	end
end
local function run(plan, e)
	if st.Busy or plan.Kind == "Blocked" then
		if plan.Reason and not st.Busy then
			Kit.Toast(T(plan.Reason), { Kind = "warn", NoTranslate = true })
		end
		return
	end
	st.Resuggest = false -- the player acted on this selection: a later snapshot must not change it
	st.Run += 1
	local mine = st.Run
	setBusy(true)
	local token = win.Token
	local n = slotNumber()
	local ok, result = true, nil
	for _, step in ipairs(plan.Steps) do
		ok, result = net().Request(step[1], step[2])
		if not ok then
			break
		end
	end
	local current = st.Run == mine -- false: the window was reopened meanwhile, that open owns the state
	if current then
		setBusy(false)
	end
	-- the toast tells what happened even when the window was closed meanwhile
	if not ok then
		Kit.Toast(said(result), { Kind = "error" }) -- server text: DOGROTS_AutoTranslateUI translates it
	elseif plan.Kind == "Remove" then
		Kit.Toast(F("%s returned to storage", e.Name), { Kind = "success", NoTranslate = true })
	elseif plan.Kind == "Move" then
		Kit.Toast(F("%s moved here · kennel %d is free", e.Name, plan.Freed or 0), { Kind = "success", NoTranslate = true })
	elseif plan.Kind == "Swap" and plan.Replaced then
		Kit.Toast(F("%s digs in kennel %d · %s went to storage", e.Name, n, plan.Replaced.Name or ""), { Kind = "success", NoTranslate = true })
	else
		Kit.Toast(F("%s digs in kennel %d", e.Name, n), { Kind = "success", NoTranslate = true })
	end
	if not (current and win and win.IsOpen and win.Token == token) then
		return
	end
	if not ok then
		refresh(net().Cached())
		task.spawn(function()
			local fresh = net().Snapshot(0)
			if win and win.IsOpen and win.Token == token and not st.Busy then
				refresh(fresh)
			end
		end)
		return
	end
	if plan.Kind == "Remove" then
		st.Selected = e.Uid -- PUT TO WORK puts it back with one tap
	end
	refresh(net().Cached())
	if CLOSE_AFTER_ASSIGN and plan.Kind ~= "Remove" then
		task.delay(0.35, function()
			if win and win.IsOpen and win.Token == token then
				win:Close("assigned")
			end
		end)
	end
end
function S.Act()
	local e = st.Selected and st.Entries[st.Selected] or nil
	if not e then
		return
	end
	task.spawn(run, planOf(e), e)
end
function S.RemoveOccupant()
	local e = st.Occupant
	if e then
		task.spawn(run, planOf(e), e)
	end
end
function S.Select(uid)
	if not ui then
		return
	end
	st.Selected = uid
	st.Resuggest = false -- the player's pick stays when a fresh snapshot arrives
	renderDetail()
	ui.Grid:Refresh()
	if win and win:GetLayout().Phone then
		layout()
	end
end

------------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------------
local function navigate(destination)
	local ok, N = pcall(function()
		return require(script.Parent.GUIIntegration)
	end)
	if ok and N and type(N.Navigate) == "function" then
		N.Navigate(destination)
	end
end

local function build()
	if ui then
		return ui
	end
	ui = { Lang = Kit.Lang() }
	S.UI = ui
	win = Kit.Window.new({
		Key = "Kennel", Name = "KennelWindow", Title = F("KENNEL %d", 1), Subtitle = T("Choose a dog to dig here"),
		Accent = ACCENT, Icon = "Dogs", NoTranslate = true, MaxSize = Vector2.new(1100, 760),
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
	})
	S.Window = win
	local body = Kit.New("Frame", {
		Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(INSET, INSET), Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2), ZIndex = Z,
	}, win.Body)
	ui.Body = body
	local probeFrame = Kit.New("Frame", { Name = "NameProbes", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(1, 1) }, body)
	local namesChanged = false
	for id, def in pairs(Defs) do
		if type(def) == "table" and type(def.DisplayName) == "string" then
			local probe = Kit.New("TextLabel", { Name = tostring(id), Text = def.DisplayName, BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1) }, probeFrame)
			probes[id] = probe
			-- AutoTranslate translates the probes a moment later: names, search and toasts follow
			probe:GetPropertyChangedSignal("Text"):Connect(function()
				if namesChanged then
					return
				end
				namesChanged = true
				task.delay(0.2, function()
					namesChanged = false
					if win and win.IsOpen and not st.Busy then
						refresh(nil)
					end
				end)
			end)
		end
	end
	-- toolbar
	ui.Search = Kit.SearchBox(body, { Name = "Search", Placeholder = T("Search dogs"), ZIndex = Z, OnChange = function(text)
		st.Search = text
		refresh(nil, true)
	end })
	ui.Sort = Kit.SortSelect(body, {
		Name = "Sort",
		Options = {
			-- every option sets its direction: SortSelect keeps the last one otherwise (BEST after NAME
			-- would list the worst dogs first)
			{ Id = "best", Text = T("BEST"), NoTranslate = true, Descending = true },
			{ Id = "income", Text = T("INCOME"), NoTranslate = true, Descending = true },
			{ Id = "mutation", Text = T("MUTATION"), NoTranslate = true, Descending = true },
			{ Id = "name", Text = T("NAME"), NoTranslate = true, Descending = false },
		},
		Selected = "best", ZIndex = Z,
		OnChange = function(id, desc)
			st.Sort, st.Desc = id, desc
			refresh(nil, true)
		end,
	})
	local chipOptions = {
		{ Id = "s:Free", Text = T("IDLE"), Color = P.green, NoTranslate = true },
		{ Id = "s:Working", Text = T("WORKING"), Color = Theme.Accent, NoTranslate = true },
		{ Id = "s:Mutated", Text = T("✨ MUTATED"), Color = Theme.Variant.Glitched, NoTranslate = true },
	}
	for _, rarity in ipairs(Logic.Rarities) do
		table.insert(chipOptions, { Id = "r:" .. rarity, Text = rarityWord(rarity), Color = Theme.RarityColor(rarity), NoTranslate = true })
	end
	ui.Chips = Kit.Chips(body, { Name = "Filters", Multi = true, Options = chipOptions, TextSize = 14, ZIndex = Z, OnChange = function(selected)
		local f = { Rarities = {} }
		for _, id in ipairs(selected) do
			local kind, key = string.match(id, "^(%a):(.+)$")
			if kind == "s" then
				f[key] = true
			elseif kind == "r" then
				f.Rarities[key] = true
			end
		end
		st.Filter = f
		refresh(nil, true)
	end })
	ui.Count = label(body, { Name = "Count", TextSize = 14, Color = Theme.InkMuted, AlignX = "Right", Scaled = true, MinTextSize = 10 })
	-- grid
	ui.GridHost = frame(body, "GridHost", Z)
	ui.Grid = Kit.VirtualGrid(ui.GridHost, {
		Name = "Dogs", ZIndex = Z, Gap = 12, Padding = 8,
		CellSize = function(w, h)
			if w < 520 or h < 236 * 1.3 then
				return Vector2.new(math.min(360, w), 88) -- rows: two columns on a landscape phone
			end
			return Vector2.new(160, 236)
		end,
		Key = function(e)
			return e.Uid
		end,
		Create = function(cellFrame)
			local card = Card.new(cellFrame)
			card.OnClick = function(e)
				if e.Status == "Arriving" then
					Kit.Toast(T("Wait until your dog arrives in your yard"), { Kind = "warn", NoTranslate = true })
				end
				S.Select(e.Uid)
			end
			return card
		end,
		Bind = function(card, e)
			card:Bind(e, cardContext())
		end,
		Layout = function(card, w, h)
			card:Layout(w, h)
		end,
		Destroy = function(card)
			card:Destroy()
		end,
		Empty = { Icon = "Dogs", Title = T("NO DOGS HERE"), Body = T("Try another search or filter."), NoTranslate = true },
	})
	ui.NoDogs = Kit.EmptyState(body, {
		Icon = "Dogs", Title = T("NO DOGS YET"), Body = T("Adopt a dog at the DOG LINE, then put it to work here."),
		ActionText = T("SHOW THE WAY"), NoTranslate = true, ZIndex = Z + 1,
		OnAction = function()
			if win then
				win:Close("navigate")
			end
			navigate("Factory")
		end,
	})
	ui.NoDogs:SetVisible(false)
	-- IN THIS KENNEL (tap it to select the dog inside)
	local o = {}
	o.Root = panel(body, "Occupant", Z)
	o.Frame = o.Root:FindFirstChildWhichIsA("UIStroke")
	o.FrameGradient = Kit.New("UIGradient", { Rotation = 90, Enabled = false }, o.Frame)
	o.Ring = ring(o.Root, Z, Theme.Radius.Card)
	o.Hit = Kit.New("TextButton", { Name = "Select", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 1 }, o.Root)
	o.Hit.Activated:Connect(function()
		if st.Occupant then
			S.Select(st.Occupant.Uid)
		end
	end)
	o.Caption = label(o.Root, { Name = "Caption", Text = T("IN THIS KENNEL"), TextSize = 12, Scaled = true, MinTextSize = CAPTION_MIN, Color = Theme.InkMuted, ZIndex = Z + 2 })
	o.Stage = stage(o.Root, Z + 2, 12)
	o.Name = label(o.Root, { Name = "DogName", TextSize = 18, Scaled = true, MinTextSize = 10, NoTranslate = false, ZIndex = Z + 3 })
	o.TagsA = tagRow(o.Root, "Tags", Z + 3)
	o.TagsB = tagRow(o.Root, "Tags2", Z + 3)
	o.Rarity = Kit.Pill(o.TagsA, { Name = "Rarity", Height = 20, TextSize = TAG_TEXT, LayoutOrder = 1, ZIndex = Z + 4, NoTranslate = true })
	o.Coins = coinsPill(o.TagsA, 20, 11, Z + 4)
	o.Coins.Instance.LayoutOrder = 3
	o.Mutation, o.MutationStroke = mutationPill(o.TagsA, 20, TAG_TEXT, Z + 4)
	o.Mutation.Instance.LayoutOrder = 2
	o.Remove = Kit.Button(o.Root, { Name = "Remove", Text = T("REMOVE"), Style = "danger", TextSize = 14, ZIndex = Z + 4, NoTranslate = true, OnClick = function()
		S.RemoveOccupant()
	end })
	o.Empty = label(o.Root, { Name = "Empty", Text = T("EMPTY KENNEL") .. "\n" .. T("Pick a dog and press PUT TO WORK"), TextSize = 15, Wrap = true, AlignX = "Center", Color = Theme.InkMuted, ZIndex = Z + 2 })
	ui.Occ = o
	-- SELECTED DOG (desktop side panel)
	local d = {}
	d.Caption = label(body, { Name = "SelectedCaption", Text = T("SELECTED DOG"), TextSize = 13, Color = Theme.InkMuted })
	d.Root = panel(body, "Selected", Z)
	d.Hint = label(d.Root, { Name = "Hint", Text = T("Tap a dog to see it here"), TextSize = 16, Wrap = true, AlignX = "Center", Color = Theme.InkMuted })
	d.Frame = Kit.New("Frame", { Name = "StageFrame", BackgroundTransparency = 1, ZIndex = Z + 1 }, d.Root)
	Kit.Corner(d.Frame, Theme.Radius.Card)
	local stroke = Kit.Stroke(d.Frame, Theme.White, 3)
	d.FrameGradient = Kit.New("UIGradient", { Rotation = 90 }, stroke)
	d.Stage = stage(d.Root, Z + 1, 20)
	d.Name = label(d.Root, { Name = "DogName", TextSize = 22, Scaled = true, MinTextSize = 12, AlignX = "Center", NoTranslate = false, ZIndex = Z + 2 })
	d.Tags = tagRow(d.Root, "Tags", Z + 2, Enum.HorizontalAlignment.Center)
	d.Rarity = Kit.Pill(d.Tags, { Name = "Rarity", Height = 24, TextSize = 13, LayoutOrder = 1, ZIndex = Z + 3, NoTranslate = true })
	d.Mutation, d.MutationStroke = mutationPill(d.Tags, 24, 13, Z + 3)
	d.Mutation.Instance.LayoutOrder = 2
	d.Stats = frame(d.Root, "Stats", Z + 2)
	Kit.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, d.Stats)
	d.RowCoins = Kit.StatRow(d.Stats, { Name = "Coins", Label = T("COINS / MIN"), Value = "—", Height = 28, TextSize = 15, LayoutOrder = 1, ZIndex = Z + 3, NoTranslate = true })
	d.RowEff = Kit.StatRow(d.Stats, { Name = "Efficiency", Label = T("EFFICIENCY"), Value = "—", Height = 28, TextSize = 15, LayoutOrder = 2, ZIndex = Z + 3, NoTranslate = true })
	d.RowBonus = Kit.StatRow(d.Stats, { Name = "Bonus", Label = T("MUTATION BONUS"), Value = "—", Height = 28, TextSize = 15, LayoutOrder = 3, ZIndex = Z + 3, NoTranslate = true })
	for _, row in ipairs({ d.RowCoins, d.RowEff, d.RowBonus }) do
		row.Instance.BackgroundColor3 = Theme.SurfaceAlt
	end
	d.Where = label(d.Root, { Name = "Where", TextSize = 14, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = Theme.InkMuted, ZIndex = Z + 2 })
	d.Delta = label(d.Root, { Name = "Delta", TextSize = 14, Scaled = true, MinTextSize = 10, AlignX = "Center", ZIndex = Z + 2 })
	ui.Detail = d
	ui.Action = Kit.Button(body, { Name = "Action", Text = T("PUT TO WORK"), Style = "success", TextSize = 22, ZIndex = Z + 1, NoTranslate = true, OnClick = function()
		S.Act()
	end })
	-- phone bottom bar
	ui.Bar = panel(body, "ActionBar", Z + 2)
	ui.BarName = label(ui.Bar, { Name = "DogName", TextSize = 15, Scaled = true, MinTextSize = 10, NoTranslate = false, ZIndex = Z + 3 })
	ui.BarMutation, ui.BarMutationStroke = mutationPill(ui.Bar, 20, 11, Z + 3)
	ui.BarAction = Kit.Button(ui.Bar, { Name = "Action", Text = T("PUT TO WORK"), Style = "success", TextSize = 16, ZIndex = Z + 3, NoTranslate = true, OnClick = function()
		S.Act()
	end })
	win.Resized:Connect(function()
		layout()
	end)
	return ui
end

-- The IN THIS KENNEL panel at (x, y, w, h). tall (desktop, h >= 120): the caption and REMOVE across the
-- top, then the preview with the name, rarity + coins and the mutation with its bonus beside it. Otherwise
-- a strip: preview, caption with the coins, name, rarity + mutation on one row.
local function occupantLayout(x, y, w, h, tall, withButton)
	local o = ui.Occ
	place(o.Root, x, y, w, h)
	o.Tall, o.WithButton = tall, withButton
	if tall then
		local bw, bh = withButton and 96 or 0, 30
		o.CaptionBox = nil
		o.Caption.TextWrapped = false
		place(o.Caption, 12, 8, w - 24 - bw - 6, 20)
		place(o.Remove.Instance, w - bw - 8, 6, bw, bh)
		local s = h - 44 - 8
		placeStage(o.Stage, 8, 44, s, s, 20)
		local tx = 8 + s + 10
		local tw = w - tx - 8
		place(o.Name, tx, 44, tw, 24)
		place(o.TagsA, tx, 72, tw, 22)
		place(o.TagsB, tx, 98, tw, 22)
		o.Mutation.Instance.Parent = o.TagsB
	else
		local pad = 6
		local s = h - pad * 2
		placeStage(o.Stage, pad, pad, s, s, 18)
		local tx = pad + s + 10
		local tw = w - tx - 8
		local bw, bh = withButton and 86 or 0, 28
		-- roomy (>= 72 px): caption + REMOVE on the first line, then the name and the tags under both;
		-- low: REMOVE on the right, caption / name / tags stacked left of it
		local roomy = h >= 72
		local nameW = roomy and tw or (tw - bw - 6)
		-- the caption box (renderOccupant places the caption: Y / H on one line, Y2 / H2 on two lines)
		if roomy then
			o.CaptionBox = { X = tx, Y = 8, W = tw - bw - 6, H = 16, Y2 = 3, H2 = 28 }
			place(o.Remove.Instance, w - bw - 6, 4, bw, bh)
			place(o.Name, tx, 34, nameW, 20)
			place(o.TagsA, tx, h - 25, nameW, 20)
		else
			o.CaptionBox = { X = tx, Y = 3, W = nameW, H = 14 }
			place(o.Remove.Instance, w - bw - 6, (h - bh) / 2, bw, bh)
			place(o.Name, tx, 17, nameW, 18)
			place(o.TagsA, tx, h - 22, nameW, 20)
		end
		o.Mutation.Instance.Parent = o.TagsA
		local box = o.CaptionBox
		place(o.Caption, box.X, box.Y, box.W, box.H)
	end
	place(o.Empty, 14, 4, w - 28, h - 8)
	o.Empty.TextSize = tall and 15 or 13
	if ui.Detail then
		renderOccupant() -- also while loading: the empty panel, not every default child
	end
end

-- The search box placeholder at text size `size` for a box searchW wide (its text area is the box less
-- 76 px: magnifier and clear button): a narrow box says just "Search", the magnifier tells the rest.
local function searchPlaceholder(searchW, size)
	local long = T("Search dogs")
	ui.Search.Box.TextSize = size
	ui.Search.Box.PlaceholderText = textWidth(long, size) + 4 > searchW - 76 and T("Search") or long
end

layout = function()
	if not (ui and win) then
		return
	end
	local L = win:GetLayout()
	local w, h = L.Width - INSET * 2, L.Height - INSET * 2
	if w < 10 or h < 10 then
		return
	end
	local phone, landscape = L.Phone, L.Landscape
	local gap = phone and 6 or 10
	local d = ui.Detail
	local none = st.Snapshot ~= nil and st.Total == 0 and st.Occupant == nil
	for _, x in ipairs({ ui.Search.Instance, ui.Sort.Instance, ui.Chips.Instance, ui.Occ.Root }) do
		x.Visible = not none
	end
	if none then
		-- no dogs at all: only NO DOGS YET (with SHOW THE WAY), centred
		ui.Count.Visible, ui.GridHost.Visible = false, false
		d.Root.Visible, d.Caption.Visible, ui.Action.Instance.Visible, ui.Bar.Visible = false, false, false, false
		ui.NoDogs.Instance.Size = UDim2.fromOffset(math.min(360, w - 20), 230)
		ui.NoDogs.Instance.Position = UDim2.fromOffset(w / 2, h / 2)
		return
	end
	if not phone then
		local panelW = math.clamp(math.floor(w * 0.33), 300, 360)
		local gridW = w - panelW - gap
		local sortW = 210
		local countW = 130
		place(ui.Search.Instance, 0, 0, gridW - sortW - gap, 42)
		searchPlaceholder(gridW - sortW - gap, 17)
		place(ui.Sort.Instance, gridW - sortW, 0, sortW, 42)
		place(ui.Chips.Instance, 0, 52, gridW - countW - gap, 36)
		place(ui.Count, gridW - countW, 52, countW, 36)
		ui.Count.Visible = true
		place(ui.GridHost, 0, 98, gridW, h - 98)
		ui.NoDogs.Instance.Position = UDim2.fromOffset(gridW / 2, 98 + (h - 98) / 2)
		-- right column: IN THIS KENNEL, SELECTED DOG, the button
		local px = gridW + gap
		local occH = 128
		occupantLayout(px, 0, panelW, occH, true, true)
		local top = occH + 10
		place(d.Caption, px + 4, top, panelW - 8, 18)
		top += 22
		local bottomH = 52
		local dh = h - top - bottomH - gap
		place(d.Root, px, top, panelW, dh)
		-- what fits under the preview: name 32, tags 34, where 22, delta 20, paddings; then the stats (100)
		local fixed = 10 + 8 + 32 + 34 + 22 + 20 + 8
		local avail = dh - fixed
		d.ShowStats = avail - 100 >= 110
		local ps = math.min(panelW - 40, d.ShowStats and (avail - 100) or avail)
		d.ShowStage = ps >= 70
		ps = d.ShowStage and ps or 0
		local sx = (panelW - ps) / 2
		place(d.Frame, sx - 3, 7, ps + 6, ps + 6)
		placeStage(d.Stage, sx, 10, ps, ps, 30)
		local y = d.ShowStage and (10 + ps + 8) or 10
		place(d.Name, 10, y, panelW - 20, 28)
		y += 32
		place(d.Tags, 6, y, panelW - 12, 26)
		y += 34
		if d.ShowStats then
			place(d.Stats, 12, y, panelW - 24, 3 * 28 + 2 * 4)
			y += 3 * 28 + 2 * 4 + 8
		end
		place(d.Where, 16, y, panelW - 32, 20)
		y += 22
		place(d.Delta, 16, y, panelW - 32, 20)
		place(d.Hint, 16, 0, panelW - 32, dh)
		place(ui.Action.Instance, px, h - bottomH, panelW, bottomH)
		d.Root.Visible, d.Caption.Visible, ui.Action.Instance.Visible = true, true, true
		ui.Bar.Visible = false
	else
		-- phones: toolbar, chips, IN THIS KENNEL, rows, bottom bar
		local y = 0
		local rowH = landscape and 36 or 40
		local barH = landscape and 58 or 64
		-- search + SORT across rowW; SORT gives up to 30 px where even "Search" would not fit the box (its
		-- text area is the box less 76 px: magnifier and clear button), as on 320 px phones
		local function toolbar(rowW)
			local sortW = 170
			local missing = textWidth(T("Search"), 15) + 4 - (rowW - sortW - gap - 76)
			if missing > 0 then
				sortW = math.max(140, sortW - math.ceil(missing))
			end
			place(ui.Search.Instance, 0, 0, rowW - sortW - gap, rowH)
			place(ui.Sort.Instance, rowW - sortW, 0, sortW, rowH)
			return rowW - sortW - gap
		end
		local searchW
		if landscape then
			local leftW = math.floor(w * 0.55)
			searchW = toolbar(leftW)
			place(ui.Chips.Instance, leftW + gap, 0, w - leftW - gap, rowH)
			y = rowH + gap
		else
			searchW = toolbar(w)
			place(ui.Chips.Instance, 0, rowH + gap, w, 34)
			y = rowH + gap + 34 + gap
			occupantLayout(0, y, w, 80, false, true)
			y += 80 + gap
		end
		searchPlaceholder(searchW, 15)
		ui.Count.Visible = false
		place(ui.GridHost, 0, y, w, h - y - barH - gap)
		ui.NoDogs.Instance.Position = UDim2.fromOffset(w / 2, y + (h - y - barH) / 2)
		d.Root.Visible, d.Caption.Visible, ui.Action.Instance.Visible = false, false, false
		ui.Bar.Visible = true
		local bx = 0
		if landscape then
			-- REMOVE only where the tags still fit beside it; otherwise tap the strip and use the bar
			local ow = math.floor(w * 0.5)
			local room = ow - (6 + (barH - 12) + 10) - 8 - 86 - 6
			occupantLayout(0, h - barH, ow, barH, false, room >= 236)
			bx = ow + gap
		end
		local barW = w - bx
		place(ui.Bar, bx, h - barH, barW, barH)
		local bw = math.min(190, math.floor(barW * 0.46))
		place(ui.BarName, 10, landscape and 4 or 6, barW - bw - 24, landscape and 22 or 24)
		ui.BarMutation.Instance.Position = UDim2.fromOffset(10, barH - (landscape and 26 or 30))
		place(ui.BarAction.Instance, barW - bw - 8, 7, bw, barH - 14)
	end
	ui.NoDogs.Instance.Size = UDim2.fromOffset(300, 230)
	ui.Grid:Relayout()
	renderDetail() -- also while loading: the hint and a disabled button, not every default child
end

------------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------------
function S._opened()
	local token = win.Token
	-- live data while open: every newer snapshot (our replies, other screens, the 5 s poll)
	win.OpenMaid:Give(net().Changed:Connect(function(snapshot)
		if win.IsOpen and not st.Busy then
			if st.Resuggest then
				-- the first fresh snapshot: preselect again from it unless the player has picked a dog
				-- (a dog bought or arrived since the cached one was written may be the best one now)
				st.Resuggest, st.Suggested = false, false
			end
			refresh(snapshot)
		end
	end))
	local player = Players.LocalPlayer
	if player then
		local scheduled = false
		win.OpenMaid:Give(player:GetAttributeChangedSignal("InventoryRevision"):Connect(function()
			if scheduled then
				return
			end
			scheduled = true
			task.delay(1.5, function()
				scheduled = false
				if win.IsOpen and win.Token == token and not st.Busy then
					net().Snapshot(0)
				end
			end)
		end))
	end
	-- mutation auras: 20 Hz while open, visible cells only (VirtualGrid binds just those)
	if not Kit.Motion.Reduced() then
		local last = 0
		win.OpenMaid:Give(Run.Heartbeat:Connect(function()
			local t = os.clock()
			if t - last < 0.05 then
				return
			end
			last = t
			ui.Grid:ForEachVisible(function(card)
				card:Animate(t)
			end)
			animateAura(ui.Occ.Stage.Aura, ui.Occ.Stage.AuraGradient, ui.Occ.Stage.Variant, t, 1.3)
			animateAura(ui.Detail.Stage.Aura, ui.Detail.Stage.AuraGradient, ui.Detail.Stage.Variant, t, 2.7)
		end))
	end
	task.spawn(function()
		while win.IsOpen and win.Token == token do
			task.wait(5)
			if win.IsOpen and win.Token == token and not st.Busy then
				net().Snapshot(4)
			end
		end
	end)
	local cached = net().Cached()
	if cached then
		refresh(cached, true)
	end
	task.spawn(function()
		local fresh = net().Snapshot(0)
		if win.IsOpen and win.Token == token and fresh and not st.Busy then
			refresh(fresh)
		end
	end)
end

function S._closed()
	if ui then
		ui.Detail.Stage.Slot:Show(nil)
		ui.Occ.Stage.Slot:Show(nil)
	end
end

-- context: {Slot = "DigSlot_n", YardId = the player's YardId}
function S.Open(context)
	if type(context) ~= "table" or type(context.Slot) ~= "string" or not Logic.SlotNumber(context.Slot) then
		return
	end
	if ui and ui.Lang ~= Kit.Lang() and not (win and win.IsOpen) then
		-- the language changed: build the window again in the new one
		ui.Grid:Destroy()
		ui.Detail.Stage.Slot:Destroy()
		ui.Occ.Stage.Slot:Destroy()
		win:Destroy()
		ui, win = nil, nil
		table.clear(probes)
	end
	build()
	if st.Slot ~= context.Slot then
		-- another kennel: nothing of the last one may show until this one is rebuilt
		st.Occupant, st.Entries, st.List, st.Total = nil, {}, {}, 0
	end
	st.Slot, st.YardId = context.Slot, context.YardId
	st.Selected, st.Suggested, st.Resuggest = nil, false, true
	st.Run += 1 -- a request still in flight from an earlier open no longer owns the buttons
	setBusy(false)
	st.Search, st.Sort, st.Desc, st.Filter = "", "best", true, { Rarities = {} }
	ui.Search:SetText("", true)
	ui.Sort:Set("best", true, true)
	ui.Chips:SetSelected({}, true)
	win:SetTitle(F("KENNEL %d", slotNumber()), T("Loading..."))
	if win.IsOpen then
		refresh(net().Cached(), true)
	else
		win:Open()
	end
	layout()
end

function S.Close()
	if win and win.IsOpen then
		win:Close("close")
	end
end
function S.IsOpen()
	return win ~= nil and win.IsOpen
end

return S
