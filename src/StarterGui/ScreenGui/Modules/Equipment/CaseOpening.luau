-- Case opening overlay (EQUIPMENT shop): the case shakes and bursts open, a reel of pieces spins
-- and slows down onto the winner (honest draws with the case odds, sent by the server), a rarity
-- flourish plays and the reward card shows the piece, its rolled bonus and what it boosts.
-- SKIP (or Escape / gamepad B) jumps straight to the reward. With Reduced Motion the reward card
-- appears at once. The overlay is its own ScreenGui above the kit windows and modals.
--   CaseOpening.Play(reply, opts) -> handle     reply: the EquipmentOpenCase reply
--     ({Opened, Reel, WinIndex, Case}); opts: {Again = {Text, Price, PriceIcon, PriceText, Style},
--     OnAgain = fn(), Action = {Text, Style}, OnAction = fn(opened), OnClose = fn()}
--   CaseOpening.Skip(), CaseOpening.Close(), CaseOpening.IsOpen(), CaseOpening.Phase()
local RunService = game:GetService("RunService")

local Shared = require(script.Parent.Shared)
local Kit = Shared.Kit
local E = Shared.E
local Visuals = Shared.Visuals
local Base = require(script.Parent.Parent.Kit.Base)
local T = Shared.T

local C = {}
C.Timing = { Pop = 0.18, Shake = 0.5, Burst = 0.18, Spin = 2.4, Settle = 0.22, Reveal = 0.28 }

local ui: any = nil
local state: any = { Open = false, Phase = "idle", Token = 0 }
C.State = state

local Theme = Kit.Theme
local DARK = Color3.fromRGB(10, 14, 32)

local function tween(instance: Instance, time: number, goals: any, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): any
	return Kit.Motion.Tween(instance, time, goals, style, direction)
end

local function rarityGradient(rarity: string): (Color3, Color3)
	local g = Theme.RarityGradient[rarity]
	if g then
		return g[1], g[2]
	end
	local c = Theme.RarityColor(rarity)
	return c:Lerp(Color3.new(1, 1, 1), 0.25), c
end

local function build()
	if ui and ui.Gui.Parent then
		return ui
	end
	local gui = Base.Layer("EquipmentReveal", Theme.Layer.Modals + 2)
	gui:SetAttribute("NoTranslate", true)
	local root = Kit.New("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1 }, gui)
	local backdrop = Kit.New("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = DARK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 1,
	}, root)
	local stage = Kit.New("Frame", { Name = "Stage", BackgroundTransparency = 1, ZIndex = 2 }, root)
	local title = Kit.Text(stage, { Name = "Title", TextSize = 30, Scaled = true, MinTextSize = 14, AlignX = "Center", Color = Theme.White, Stroke = 0, ZIndex = 5, NoTranslate = true })
	local subtitle = Kit.Text(stage, { Name = "Subtitle", TextSize = 16, AlignX = "Center", Color = Theme.White, Stroke = 0.4, ZIndex = 5, NoTranslate = true })
	-- Rarity flourish behind the case / reward: a glow disc and slowly turning rays.
	local glow = Kit.New("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.White, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, stage)
	Kit.Corner(glow, "pill")
	local rays = Kit.New("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2 }, stage)
	local rayFrames = {}
	for i = 1, 8 do
		local ray = Kit.New("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.07, 0, 1, 0),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Rotation = (i - 1) * 22.5,
			ZIndex = 2,
		}, rays)
		Kit.New("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, ray)
		table.insert(rayFrames, ray)
	end
	-- The case.
	local caseHolder = Kit.New("Frame", { Name = "Case", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 4 }, stage)
	local caseScale = Kit.New("UIScale", { Name = "Pop" }, caseHolder)
	-- The reel.
	local reel = Kit.New("Frame", { Name = "Reel", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(22, 28, 54), BorderSizePixel = 0, ClipsDescendants = true, Visible = false, ZIndex = 4 }, stage)
	Kit.Corner(reel, 16)
	Kit.Stroke(reel, Theme.Colors.gold, 3)
	local strip = Kit.New("Frame", { Name = "Strip", BackgroundTransparency = 1, ZIndex = 5 }, reel)
	local marker = Kit.New("Frame", { Name = "Marker", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Theme.Colors.gold, BorderSizePixel = 0, ZIndex = 8 }, reel)
	for _, y in ipairs({ 0, 1 }) do
		local notch = Kit.New("Frame", {
			Name = y == 0 and "NotchTop" or "NotchBottom",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromOffset(18, 18),
			Rotation = 45,
			BackgroundColor3 = Theme.Colors.gold,
			BorderSizePixel = 0,
			ZIndex = 8,
		}, reel)
		local _ = notch
	end
	local flash = Kit.New("Frame", { Name = "Flash", BackgroundColor3 = Theme.White, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 20 }, root)
	-- The reward card.
	local card = Kit.New("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 10 }, stage)
	Kit.Corner(card, 20)
	local cardStroke = Kit.Stroke(card, Theme.Colors.edge, 4)
	local cardScale = Kit.New("UIScale", { Name = "Pop" }, card)
	local band = Kit.New("Frame", { Name = "Band", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = 11 }, card)
	Kit.Corner(band, 16)
	local bandGradient = Kit.New("UIGradient", { Rotation = 90 }, band)
	local viewHolder = Kit.New("Frame", { Name = "View", BackgroundTransparency = 1, ZIndex = 12 }, card)
	local tags = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = 12 }, card)
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, tags)
	local rarityTag = Kit.Pill(tags, { Name = "Rarity", Height = 24, TextSize = 14, LayoutOrder = 1, ZIndex = 13, NoTranslate = true })
	local newTag = Kit.Pill(tags, { Name = "New", Height = 24, TextSize = 14, Color = Theme.Danger, LayoutOrder = 2, ZIndex = 13, NoTranslate = true })
	local pityTag = Kit.Pill(tags, { Name = "Pity", Height = 24, TextSize = 14, Color = Theme.Colors.gold, LayoutOrder = 3, ZIndex = 13, NoTranslate = true })
	local name = Kit.Text(card, { Name = "PieceName", TextSize = 28, Scaled = true, MinTextSize = 14, ZIndex = 12, NoTranslate = true })
	local stat = Kit.Text(card, { Name = "Stat", TextSize = 24, Scaled = true, MinTextSize = 12, Font = "numeric", ZIndex = 12, NoTranslate = true })
	local scope = Kit.Pill(card, { Name = "Scope", Height = 26, TextSize = 14, ZIndex = 12, NoTranslate = true })
	local help = Kit.Text(card, { Name = "Help", TextSize = 14, Color = Theme.InkMuted, Wrap = true, AlignY = "Top", ZIndex = 12, NoTranslate = true })
	local quality = Kit.ProgressBar(card, { Name = "Quality", Height = 20, Value = 0, TextSize = 13, ZIndex = 12, NoTranslate = true })
	local buttons = {}
	buttons.Collect = Kit.Button(card, { Name = "Collect", Text = Shared.W("COLLECT"), Style = "success", ZIndex = 13, NoTranslate = true, OnClick = function()
		C.Close()
	end })
	buttons.Again = Kit.Button(card, { Name = "Again", Text = Shared.W("AGAIN"), Style = "primary", ZIndex = 13, NoTranslate = true, OnClick = function()
		local fn = state.Opts and state.Opts.OnAgain
		if fn then
			buttons.Again:SetBusy(true)
			task.spawn(fn)
		end
	end })
	buttons.Action = Kit.Button(card, { Name = "Action", Text = "", Style = "secondary", ZIndex = 13, NoTranslate = true, OnClick = function()
		local fn = state.Opts and state.Opts.OnAction
		local opened = state.Reply and state.Reply.Opened
		C.Close()
		if fn and opened then
			task.spawn(fn, opened)
		end
	end })
	local skip = Kit.Button(root, { Name = "Skip", Text = Shared.W("SKIP") .. " »", Style = "secondary", AnchorPoint = Vector2.new(1, 0), ZIndex = 30, NoTranslate = true, OnClick = function()
		C.Skip()
	end })
	ui = {
		Gui = gui, Root = root, Backdrop = backdrop, Stage = stage, Title = title, Subtitle = subtitle, Glow = glow, Rays = rays, RayFrames = rayFrames,
		Case = caseHolder, CaseScale = caseScale, Reel = reel, Strip = strip, Marker = marker, Flash = flash, Card = card, CardStroke = cardStroke,
		CardScale = cardScale, Band = band, BandGradient = bandGradient, View = viewHolder, Tags = tags, RarityTag = rarityTag, NewTag = newTag,
		PityTag = pityTag, Name = name, Stat = stat, Scope = scope, Help = help, Quality = quality, Buttons = buttons, Skip = skip, Tiles = {},
	}
	C.UI = ui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if state.Open then
			C.Layout()
		end
	end)
	return ui
end

-- Sizes everything from the safe area: a vertical card on desktop / portrait phones, a
-- horizontal card on landscape phones.
function C.Layout()
	local u = build()
	local sx, sy, sw, sh = Base.SafeArea(u.Gui)
	local phone = sw < 700 or sh < 560
	local short = sh < 420
	u.Stage.Position = UDim2.fromOffset(sx, sy)
	u.Stage.Size = UDim2.fromOffset(sw, sh)
	local skipW = phone and 104 or 132
	u.Skip.Instance.Size = UDim2.fromOffset(skipW, 44)
	u.Skip.Instance.Position = UDim2.fromOffset(sx + sw - 12, sy + 10)
	-- The title stays clear of the SKIP button on both sides.
	u.Title.Size = UDim2.new(1, -(skipW * 2 + 40), 0, short and 30 or 40)
	u.Title.Position = UDim2.fromOffset(skipW + 20, short and 6 or 18)
	u.Subtitle.Position = UDim2.new(0, 12, 0, (short and 6 or 18) + (short and 28 or 40))
	u.Subtitle.Size = UDim2.new(1, -24, 0, 20)
	local center = UDim2.fromScale(0.5, short and 0.56 or 0.5)
	local caseSize = math.floor(math.min(sw * 0.6, sh * (short and 0.62 or 0.42), 260))
	u.Case.Position = center
	u.Case.Size = UDim2.fromOffset(caseSize, caseSize)
	local glowSize = math.floor(math.min(sw, sh) * (short and 0.95 or 0.8))
	u.Glow.Position = center
	u.Glow.Size = UDim2.fromOffset(glowSize, glowSize)
	u.Rays.Position = center
	u.Rays.Size = UDim2.fromOffset(glowSize * 1.3, glowSize * 1.3)
	-- Reel: tiles sized so about five show on a phone and seven on a desktop.
	local reelW = math.floor(math.min(sw - 24, 860))
	local tileW = math.floor(math.clamp(reelW / (phone and 4.6 or 6.6), 78, 120))
	local tileH = math.floor(math.clamp(tileW * 1.18, 92, 140))
	u.Reel.Position = center
	u.Reel.Size = UDim2.fromOffset(reelW, tileH + 24)
	u.TileW, u.TileH, u.Gap, u.ReelW = tileW, tileH, 8, reelW
	for i, tile in ipairs(u.Tiles) do
		tile.Position = UDim2.fromOffset((i - 1) * (tileW + 8), 12)
		tile.Size = UDim2.fromOffset(tileW, tileH)
	end
	u.Strip.Size = UDim2.fromOffset(#u.Tiles * (tileW + 8), tileH + 24)
	-- Card.
	local cardW = math.floor(math.min(sw - 24, short and 640 or 430))
	local cardH = math.floor(math.min(sh - (short and 16 or 90), short and 300 or 560))
	u.Card.Position = UDim2.fromScale(0.5, short and 0.5 or 0.53)
	u.Card.Size = UDim2.fromOffset(cardW, cardH)
	local pad = phone and 12 or 16
	local buttonH = 46
	local inner = cardW - pad * 2
	if short then
		-- [view] [texts] side by side, buttons along the bottom.
		local viewS = math.floor(math.min(cardH - buttonH - pad * 3, cardW * 0.36))
		u.Band.Position = UDim2.fromOffset(pad - 4, pad - 4)
		u.Band.Size = UDim2.fromOffset(viewS + 8, viewS + 8)
		u.View.Position = UDim2.fromOffset(pad, pad)
		u.View.Size = UDim2.fromOffset(viewS, viewS)
		local x = pad + viewS + 12
		local w = cardW - x - pad
		u.Tags.Position = UDim2.fromOffset(x, pad)
		u.Tags.Size = UDim2.fromOffset(w, 26)
		u.Name.Position = UDim2.fromOffset(x, pad + 30)
		u.Name.Size = UDim2.fromOffset(w, 30)
		u.Stat.Position = UDim2.fromOffset(x, pad + 62)
		u.Stat.Size = UDim2.fromOffset(w, 28)
		u.Scope.Instance.Position = UDim2.fromOffset(x, pad + 94)
		u.Help.Position = UDim2.fromOffset(x, pad + 124)
		u.Help.Size = UDim2.fromOffset(w, math.max(0, viewS - 150))
		u.Help.Visible = viewS - 150 >= 18
		u.Quality.Instance.Position = UDim2.fromOffset(x, pad + viewS - 20)
		u.Quality.Instance.Size = UDim2.fromOffset(w, 20)
	else
		local viewS = math.floor(math.min(inner * 0.62, cardH * 0.36))
		u.Band.Position = UDim2.fromOffset(pad, pad)
		u.Band.Size = UDim2.fromOffset(inner, viewS + 16)
		u.View.Position = UDim2.new(0.5, -viewS / 2, 0, pad + 8)
		u.View.Size = UDim2.fromOffset(viewS, viewS)
		local y = pad + viewS + 26
		u.Tags.Position = UDim2.fromOffset(pad, y)
		u.Tags.Size = UDim2.fromOffset(inner, 26)
		u.Tags:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
		u.Name.Position = UDim2.fromOffset(pad, y + 32)
		u.Name.Size = UDim2.fromOffset(inner, 34)
		u.Name.TextXAlignment = Enum.TextXAlignment.Center
		u.Stat.Position = UDim2.fromOffset(pad, y + 68)
		u.Stat.Size = UDim2.fromOffset(inner, 30)
		u.Stat.TextXAlignment = Enum.TextXAlignment.Center
		u.Scope.Instance.AnchorPoint = Vector2.new(0.5, 0)
		u.Scope.Instance.Position = UDim2.new(0.5, 0, 0, y + 102)
		u.Help.Position = UDim2.fromOffset(pad, y + 134)
		local helpH = cardH - (y + 134) - (buttonH * 2 + 10) - pad - 32
		u.Help.Size = UDim2.fromOffset(inner, math.max(0, helpH))
		u.Help.Visible = helpH >= 18
		u.Help.TextXAlignment = Enum.TextXAlignment.Center
		u.Quality.Instance.Position = UDim2.new(0, pad, 1, -(pad + buttonH * 2 + 10 + 28))
		u.Quality.Instance.Size = UDim2.fromOffset(inner, 20)
	end
	-- Buttons: [action] [again] on one row, COLLECT under them (two rows), or one row when short.
	local b = u.Buttons
	local showAction = b.Action.Instance.Visible
	local showAgain = b.Again.Instance.Visible
	if short then
		local count = 1 + (showAction and 1 or 0) + (showAgain and 1 or 0)
		local w = math.floor((inner - (count - 1) * 8) / count)
		local x = pad
		for _, key in ipairs({ "Action", "Again", "Collect" }) do
			local button = b[key]
			if button.Instance.Visible then
				button.Instance.Position = UDim2.new(0, x, 1, -(pad + buttonH))
				button.Instance.Size = UDim2.fromOffset(w, buttonH)
				x += w + 8
			end
		end
	else
		local top = { }
		if showAction then
			table.insert(top, b.Action)
		end
		if showAgain then
			table.insert(top, b.Again)
		end
		local w = #top > 0 and math.floor((inner - (#top - 1) * 8) / #top) or inner
		for i, button in ipairs(top) do
			button.Instance.Position = UDim2.new(0, pad + (i - 1) * (w + 8), 1, -(pad + buttonH * 2 + 8))
			button.Instance.Size = UDim2.fromOffset(w, buttonH)
		end
		b.Collect.Instance.Position = UDim2.new(0, pad, 1, -(pad + buttonH))
		b.Collect.Instance.Size = UDim2.fromOffset(inner, buttonH)
	end
	u.Short = short
end

local function makeTile(parent: Instance, id: string): Frame
	local def = E.Def(id)
	local rarity = def and def.Rarity or "Common"
	local top, bottom = rarityGradient(rarity)
	local tile = Kit.New("Frame", { Name = "Tile", BackgroundColor3 = Theme.White, BorderSizePixel = 0, ZIndex = 6 }, parent)
	Kit.Corner(tile, 12)
	Kit.Stroke(tile, Theme.Colors.edge, 2)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(top:Lerp(Color3.new(1, 1, 1), 0.35), bottom) }, tile)
	Kit.Text(tile, {
		Name = "Stat",
		Text = def and Shared.StatShort(def.Stat) or "?",
		Font = "numeric",
		TextSize = 22,
		Scaled = true,
		MinTextSize = 10,
		AlignX = "Center",
		Color = Theme.White,
		Stroke = 0,
		Position = UDim2.new(0, 6, 0.12, 0),
		Size = UDim2.new(1, -12, 0.3, 0),
		ZIndex = 7,
		NoTranslate = true,
	})
	Kit.Text(tile, {
		Name = "Label",
		Text = def and Shared.Name(def) or "?",
		TextSize = 15,
		Scaled = true,
		MinTextSize = 8,
		Wrap = true,
		AlignX = "Center",
		Color = Theme.White,
		Stroke = 0,
		Position = UDim2.new(0, 6, 0.46, 0),
		Size = UDim2.new(1, -12, 0.42, 0),
		ZIndex = 7,
		NoTranslate = true,
	})
	tile:SetAttribute("PieceId", id)
	return tile
end

local function clearViews()
	if state.Turn then
		state.Turn:Disconnect()
		state.Turn = nil
	end
	for _, child in ipairs(ui.View:GetChildren()) do
		child:Destroy()
	end
	for _, child in ipairs(ui.Case:GetChildren()) do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
end

local function paintCard(reply: any)
	local opened = reply.Opened
	local def = E.Def(opened.Id)
	local rarity = opened.Rarity or (def and def.Rarity) or "Common"
	local kind = opened.Kind or (def and def.Kind) or "Accessory"
	local color = Theme.RarityColor(rarity)
	local top, bottom = rarityGradient(rarity)
	ui.CardStroke.Color = color:Lerp(Theme.Colors.edge, 0.25)
	ui.BandGradient.Color = ColorSequence.new(top:Lerp(Color3.new(1, 1, 1), 0.55), bottom:Lerp(Color3.new(1, 1, 1), 0.15))
	ui.RarityTag:Set(Shared.Rarity(rarity), color)
	local g = Theme.RarityGradient[rarity]
	if g then
		ui.RarityTag:SetGradient(g[1], g[2])
	end
	ui.NewTag:Set(Shared.W("NEW"), Theme.Danger)
	ui.NewTag:SetVisible(opened.New == true)
	ui.PityTag:Set(Shared.W("PITY"), Theme.Colors.gold)
	ui.PityTag:SetVisible(opened.Pity == true)
	ui.Name.Text = Shared.Name(def)
	local statName = def and def.Stat or opened.Stat
	ui.Stat.Text = statName and Shared.StatLine(statName, opened.Value or E.Value(opened)) or ""
	ui.Stat.TextColor3 = statName and Shared.StatColor(statName):Lerp(Theme.Ink, 0.25) or Theme.Ink
	ui.Scope:Set(Shared.Scope(kind), kind == "Artifact" and Shared.Colors.Artifact or Shared.Colors.Accessory)
	ui.Help.Text = statName and Shared.Help(statName, kind) or ""
	ui.Quality:SetColor(color)
	ui.Quality:SetText(Shared.Quality(opened.Roll or 0))
	ui.Quality:SetValue(math.clamp(opened.Roll or 0, 0.04, 1), true)
	clearViews()
	local view, _, bounds = Visuals.Viewport(ui.View, { Id = opened.Id }, { Yaw = 24 })
	view.ZIndex = 13
	if not Kit.Motion.Reduced() and bounds then
		local yaw = bounds.Yaw or 0.4
		state.Turn = RunService.RenderStepped:Connect(function(dt)
			yaw += dt * 0.7
			Visuals.Turn(view, bounds, yaw)
		end)
	end
	local opts = state.Opts or {}
	local b = ui.Buttons
	b.Again:SetBusy(false)
	b.Again.Instance.Visible = opts.Again ~= nil
	if opts.Again then
		b.Again:SetText(opts.Again.Text or Shared.W("AGAIN"))
		b.Again:SetStyle(opts.Again.Style or "primary")
		if opts.Again.PriceText then
			b.Again:SetPrice(opts.Again.PriceText)
		else
			b.Again:SetPrice(opts.Again.Price)
		end
		b.Again:SetDisabled(opts.Again.Disabled == true)
	end
	b.Action.Instance.Visible = opts.Action ~= nil
	if opts.Action then
		b.Action:SetText(opts.Action.Text)
		b.Action:SetStyle(opts.Action.Style or "secondary")
	end
	C.Layout()
end

local function setPhase(phase: string)
	state.Phase = phase
	ui.Root:SetAttribute("Phase", phase)
end

-- The reward: flourish and card.
local function reveal(token: number)
	if token ~= state.Token then
		return
	end
	local reply = state.Reply
	local rarity = reply.Opened.Rarity or "Common"
	local color = Theme.RarityColor(rarity)
	setPhase("reward")
	ui.Skip.Instance.Visible = false
	ui.Reel.Visible = false
	ui.Case.Visible = false
	ui.Title.Text = T("YOU GOT", "ТЕБЕ ВЫПАЛО")
	ui.Subtitle.Text = ""
	paintCard(reply)
	-- On short screens the card needs the whole height.
	ui.Title.Visible = not ui.Short
	ui.Card.Visible = true
	ui.Glow.BackgroundColor3 = color
	for _, ray in ipairs(ui.RayFrames) do
		ray.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3)
	end
	local rank = E.RarityIndex[rarity] or 1
	if Kit.Motion.Reduced() then
		ui.Glow.BackgroundTransparency = 0.75
		ui.Rays.Visible = rank >= 4
		ui.Rays.Rotation = 0
		ui.CardScale.Scale = 1
		return
	end
	ui.Rays.Visible = rank >= 3
	ui.Rays.Rotation = 0
	ui.Glow.BackgroundTransparency = 1
	tween(ui.Glow, C.Timing.Reveal, { BackgroundTransparency = rank >= 5 and 0.55 or 0.72 })
	tween(ui.Rays, 7, { Rotation = 90 }, Enum.EasingStyle.Linear)
	ui.Flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	ui.Flash.BackgroundTransparency = rank >= 5 and 0.15 or 0.45
	tween(ui.Flash, 0.35, { BackgroundTransparency = 1 })
	ui.CardScale.Scale = 0.6
	tween(ui.CardScale, C.Timing.Reveal, { Scale = 1 }, Enum.EasingStyle.Back)
	if rank >= 5 then
		-- Legendary / Mythic: a second pulse of the glow.
		task.delay(C.Timing.Reveal + 0.05, function()
			if token == state.Token and state.Open then
				tween(ui.Glow, 0.45, { BackgroundTransparency = 0.75 }, Enum.EasingStyle.Sine)
			end
		end)
	end
end

local function spin(token: number)
	if token ~= state.Token then
		return
	end
	local reply = state.Reply
	setPhase("spin")
	ui.Case.Visible = false
	ui.Reel.Visible = true
	ui.Title.Text = T("ROLLING…", "КРУТИМ…")
	local step = ui.TileW + ui.Gap
	local winIndex = reply.WinIndex or #ui.Tiles
	local finalX = math.floor(ui.ReelW / 2 - (winIndex - 0.5) * step + 4)
	-- Land a little off-centre inside the winning tile, then settle onto its middle.
	local offset = ((state.Seed or 0.5) - 0.5) * ui.TileW * 0.6
	ui.Strip.Position = UDim2.fromOffset(math.floor(ui.ReelW / 2 - 2.5 * step), 0)
	tween(ui.Strip, C.Timing.Spin, { Position = UDim2.fromOffset(finalX + offset, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	task.delay(C.Timing.Spin, function()
		if token ~= state.Token or not state.Open then
			return
		end
		tween(ui.Strip, C.Timing.Settle, { Position = UDim2.fromOffset(finalX, 0) }, Enum.EasingStyle.Sine)
		local win = ui.Tiles[winIndex]
		if win then
			local stroke = win:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = Theme.Colors.gold
				stroke.Thickness = 4
			end
		end
		task.delay(C.Timing.Settle + 0.12, function()
			reveal(token)
		end)
	end)
end

-- Starts the opening of `reply` (an EquipmentOpenCase reply). Replaces a running one.
function C.Play(reply: any, opts: any?): any
	assert(type(reply) == "table" and type(reply.Opened) == "table", "CaseOpening.Play: reply without Opened")
	build()
	state.Token += 1
	local token = state.Token
	state.Reply = reply
	state.Opts = opts or {}
	state.Seed = (tonumber(reply.Opened.Roll) or 0.5)
	state.Open = true
	clearViews()
	-- Reel tiles from the server's draws.
	for _, tile in ipairs(ui.Tiles) do
		tile:Destroy()
	end
	ui.Tiles = {}
	for _, id in ipairs(reply.Reel or { reply.Opened.Id }) do
		table.insert(ui.Tiles, makeTile(ui.Strip, id))
	end
	ui.Root.Visible = true
	ui.Card.Visible = false
	ui.Reel.Visible = false
	ui.Rays.Visible = false
	ui.Glow.BackgroundTransparency = 1
	ui.Skip.Instance.Visible = true
	ui.Title.Visible = true
	-- Static captions follow the current language.
	ui.Skip:SetText(Shared.W("SKIP") .. " »")
	ui.Buttons.Collect:SetText(Shared.W("COLLECT"))
	local case = E.CaseById[reply.Case]
	ui.Title.Text = case and (T("OPENING ", "ОТКРЫВАЕМ ") .. Shared.CaseName(case)) or ""
	ui.Subtitle.Text = case and Shared.Scope(case.Kind) or ""
	C.Layout()
	-- Escape / gamepad B: skip the animation, then close.
	if state.Entry then
		Kit.Overlay.Remove(state.Entry)
	end
	local function push()
		state.Entry = Kit.Overlay.Push({
			Kind = "equipment-reveal",
			Dismiss = function(reason)
				state.Entry = nil
				if reason == "escape" and state.Phase ~= "reward" and state.Open then
					C.Skip()
					push()
				else
					C.Close()
				end
			end,
		})
	end
	push()
	if Kit.Motion.Reduced() then
		ui.Backdrop.BackgroundTransparency = 0.2
		reveal(token)
		return C
	end
	setPhase("case")
	ui.Backdrop.BackgroundTransparency = 1
	tween(ui.Backdrop, C.Timing.Pop, { BackgroundTransparency = 0.2 })
	ui.Case.Visible = true
	ui.Case.Rotation = 0
	local caseView = Visuals.Viewport(ui.Case, { Case = reply.Case }, { Yaw = 22, Pitch = 16 })
	caseView.ZIndex = 4
	ui.CaseScale.Scale = 0.5
	tween(ui.CaseScale, C.Timing.Pop, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Three growing shakes, then the burst.
	local shakes = { -6, 8, -10, 0 }
	for i, angle in ipairs(shakes) do
		task.delay(C.Timing.Pop + (i - 1) * C.Timing.Shake / #shakes, function()
			if token == state.Token and state.Phase == "case" then
				tween(ui.Case, C.Timing.Shake / #shakes, { Rotation = angle }, Enum.EasingStyle.Sine)
			end
		end)
	end
	task.delay(C.Timing.Pop + C.Timing.Shake, function()
		if token ~= state.Token or state.Phase ~= "case" then
			return
		end
		setPhase("burst")
		ui.Flash.BackgroundColor3 = Theme.White
		ui.Flash.BackgroundTransparency = 0.25
		tween(ui.Flash, C.Timing.Burst + 0.1, { BackgroundTransparency = 1 })
		tween(ui.CaseScale, C.Timing.Burst, { Scale = 1.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(C.Timing.Burst, function()
			spin(token)
		end)
	end)
	return C
end

-- Jumps to the reward card.
function C.Skip()
	if not state.Open or state.Phase == "reward" then
		return
	end
	state.Token += 1
	ui.Backdrop.BackgroundTransparency = 0.2
	ui.CaseScale.Scale = 1
	reveal(state.Token)
end

function C.Close()
	if not state.Open then
		return
	end
	state.Open = false
	state.Token += 1
	setPhase("idle")
	if state.Entry then
		Kit.Overlay.Remove(state.Entry)
		state.Entry = nil
	end
	clearViews()
	local opts = state.Opts or {}
	state.Opts = nil
	if Kit.Motion.Reduced() then
		ui.Root.Visible = false
	else
		local token = state.Token
		tween(ui.Backdrop, Theme.Motion.Close, { BackgroundTransparency = 1 })
		tween(ui.CardScale, Theme.Motion.Close, { Scale = 0.9 })
		task.delay(Theme.Motion.Close, function()
			if token == state.Token and not state.Open then
				ui.Root.Visible = false
			end
		end)
	end
	if opts.OnClose then
		task.spawn(opts.OnClose)
	end
end

-- OPEN AGAIN failed (no Coins, bag full...): the button works again.
function C.AgainDone()
	if ui then
		ui.Buttons.Again:SetBusy(false)
	end
end

function C.IsOpen(): boolean
	return state.Open == true
end
function C.Phase(): string
	return state.Phase
end

return C
