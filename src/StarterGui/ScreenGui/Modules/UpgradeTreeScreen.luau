-- UPGRADE TREE window (Kit). A persistent window built once: a pannable, zoomable canvas with the
-- tree (crown = stat branches above the trunk, roots = estate / storage / processes / abilities
-- below it), branch-coloured connectors that fill as prerequisites are met, round nodes with icons
-- and level pips, and a detail panel (desktop: side panel, phone portrait: bottom sheet) with the
-- node's CURRENT -> NEXT bonus, requirements, price and BUY button. Without a selection the panel
-- lists every active tree bonus.
-- Everything shown comes from ReplicatedStorage.DogEconomy.UpgradeTree (the definitions the server
-- buys and applies with) and the player's snapshot; the server checks every purchase again
-- (Features.UpgradeTree: TreeUpgrade). Self-localized (Localization.UpgradeTree, NoTranslate labels).
--   Screen.Open(nodeId?)  opens the window (focusing a node), Screen.Close(), Screen.IsOpen()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Tree = require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("UpgradeTree"))
local PlotCatalog = require(ReplicatedStorage:WaitForChild("PlotCatalog"))
local Dict = require(ReplicatedStorage:WaitForChild("Localization"):WaitForChild("UpgradeTree"))

local Theme = Kit.Theme
local Motion = Kit.Motion
local New = Kit.New
local player = Players.LocalPlayer

local Screen = {}

-- Layout of the drawing (pixels at zoom 1).
local UNIT_X, UNIT_Y = 148, 136
local MARGIN_X, MARGIN_TOP, MARGIN_BOTTOM = 112, 150, 160
local NODE, CAPSTONE, HUB = 68, 82, 108
local ZOOM_MIN, ZOOM_MAX = 0.45, 1.4

local C3 = Color3.fromRGB
local COLORS = {
	Sky = C3(222, 240, 255),
	Grass = C3(226, 244, 214),
	Soil = C3(214, 186, 150),
	SoilDeep = C3(186, 148, 108),
	Trunk = C3(122, 84, 52),
	TrunkLight = C3(160, 116, 74),
	Track = C3(196, 204, 216),
	LockedFace = C3(228, 232, 238),
	LockedRing = C3(158, 168, 184),
	LockedIcon = C3(150, 160, 176),
	Pip = C3(206, 213, 224),
	Gold = Theme.Colors.gold,
	Good = Theme.Colors.green,
	Bad = Theme.Colors.red,
}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function L(en: string?): string
	if type(en) ~= "string" then
		return ""
	end
	if Kit.Lang() == "ru" then
		return Dict.Window[en] or Dict.Exact[en] or en
	end
	return en
end
local function LF(template: string, ...: any): string
	if Kit.Lang() == "ru" then
		template = Dict.Templates[template] or template
	end
	return string.format(template, ...)
end
Screen.L, Screen.LF = L, LF

-- Server replies in the player's language (node names inside them are translated too).
local function serverText(message: any): string
	local text = type(message) == "table" and tostring(message.Message or "") or tostring(message or "")
	if Kit.Lang() ~= "ru" then
		return text
	end
	local level = string.match(text, "^Reach level (%d+) for this upgrade$")
	if level then
		return LF("Reach level %s for this upgrade", level)
	end
	local name, need = string.match(text, "^Requires (.+) level (%d+)$")
	if name then
		return LF("Requires %s level %s", L(name), need)
	end
	local stage = string.match(text, "^Yard expanded: (.+)$")
	if stage then
		return LF("Yard expanded: %s", L(stage))
	end
	return Dict.Exact[text] or Dict.Window[text] or text
end
Screen.ServerText = serverText

local function short(n: number): string
	return Kit.Format.Short(math.max(0, math.floor(n or 0)), 1)
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
local state: any = {
	Upgrades = {},
	Level = 1,
	Cash = 0,
	Bones = 0,
	Loaded = false,
	Selected = nil,
	Busy = false,
	Zoom = 1,
	Side = true,
	SheetOpen = false,
	FirstRender = true,
}
local ui: any = nil -- built once (Screen.Build)

-- The profile the definitions read (levels from the snapshot, wallet and level kept live).
local function view(): any
	return { Upgrades = state.Upgrades, Level = state.Level, Cash = state.Cash, Bones = state.Bones }
end

local function readSnapshot(snapshot: any)
	local p = type(snapshot) == "table" and snapshot.Profile
	if type(p) ~= "table" then
		return
	end
	state.Upgrades = type(p.Upgrades) == "table" and p.Upgrades or {}
	state.Level = tonumber(p.Level) or state.Level
	state.Cash = tonumber(p.Cash) or state.Cash
	state.Bones = tonumber(p.Bones) or state.Bones
	state.Skin = p.EquippedPlotSkin
	state.Loaded = true
end

-- leaderstats.Coins and the Bones / Level attributes follow every transaction (Runtime.Project),
-- so affordability stays live without polling the server.
local function readLive()
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins and type(coins.Value) == "number" then
		state.Cash = coins.Value
	end
	local bones = player:GetAttribute("Bones")
	if type(bones) == "number" then
		state.Bones = bones
	end
	local level = player:GetAttribute("Level")
	if type(level) == "number" then
		state.Level = level
	end
end

------------------------------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------------------------------
local bounds = { MinX = 0, MaxX = 0, MinY = 0, MaxY = 0 }
for _, node in pairs(Tree.Nodes) do
	bounds.MinX = math.min(bounds.MinX, node.X)
	bounds.MaxX = math.max(bounds.MaxX, node.X)
	bounds.MinY = math.min(bounds.MinY, node.Y)
	bounds.MaxY = math.max(bounds.MaxY, node.Y)
end
local CONTENT_W = math.floor((bounds.MaxX - bounds.MinX) * UNIT_X + MARGIN_X * 2)
local CONTENT_H = math.floor((bounds.MaxY - bounds.MinY) * UNIT_Y + MARGIN_TOP + MARGIN_BOTTOM)
Screen.ContentSize = Vector2.new(CONTENT_W, CONTENT_H)

local function point(x: number, y: number): Vector2
	return Vector2.new(MARGIN_X + (x - bounds.MinX) * UNIT_X, MARGIN_TOP + (y - bounds.MinY) * UNIT_Y)
end
local HUB_POINT = point(0, 0)
Screen.Point = point

------------------------------------------------------------------------------------------------
-- Small builders
------------------------------------------------------------------------------------------------
local function circle(parent: Instance, name: string, size: number, color: Color3, z: number, props: any?): Frame
	local frame = New("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	if props then
		for k, v in pairs(props) do
			(frame :: any)[k] = v
		end
	end
	Kit.Corner(frame, "pill")
	return frame
end

-- A straight connector from a to b with a fill bar growing from a.
local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, z: number, track: Color3, fill: Color3): (Frame, Frame)
	local delta = b - a
	local frame = New("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(delta.Magnitude, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = track,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Kit.Corner(frame, "pill")
	local bar = New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		ZIndex = z + 1,
	}, frame)
	Kit.Corner(bar, "pill")
	return frame, bar
end

local function label(parent: Instance, props: any): any
	props.NoTranslate = true
	return Kit.Text(parent, props)
end

------------------------------------------------------------------------------------------------
-- Build (once)
------------------------------------------------------------------------------------------------
local refresh, select, arrange, setZoom, reveal, buy, showSheet

local function buildNode(content: Frame, id: string): any
	local node = Tree.Nodes[id]
	local branch = Tree.BranchById[node.Branch]
	local size = node.Capstone and CAPSTONE or NODE
	local at = point(node.X, node.Y)
	local w: any = { Id = id, Size = size, Point = at, Branch = branch }
	-- Holder: the circle on top, the pips and the name below it.
	local holder = New("Frame", {
		Name = "Node_" .. id,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(at.X, at.Y - size / 2 - 10),
		Size = UDim2.fromOffset(140, size + 70),
		ZIndex = 10,
	}, content)
	w.Holder = holder
	local center = UDim2.new(0.5, 0, 0, size / 2 + 10)
	w.Glow = circle(holder, "Glow", size + 20, branch.Color, 10, { Position = center, BackgroundTransparency = 0.6, Visible = false })
	w.Select = circle(holder, "SelectRing", size + 14, Theme.White, 10, { Position = center, BackgroundTransparency = 1, Visible = false })
	w.SelectStroke = Kit.Stroke(w.Select, Theme.Colors.edge, 3, 0)
	local button = New("TextButton", {
		Name = "Bubble",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, holder)
	button:SetAttribute("NoTranslate", true)
	Kit.Corner(button, "pill")
	w.Button = button
	w.Ring = Kit.Stroke(button, branch.Color, node.Capstone and 5 or 4, 0)
	w.Pop = New("UIScale", { Name = "Pop" }, button)
	w.Gradient = New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Theme.White, C3(236, 242, 250)) }, button)
	w.Icon = Kit.Icon(button, branch.Icon, {
		Size = UDim2.fromOffset(math.floor(size * 0.56), math.floor(size * 0.56)),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 13,
		Color = branch.Color,
	})
	-- Badges: lock (locked), check (maxed), arrow (affordable).
	local function badge(name: string, glyph: string, color: Color3): Frame
		local b = circle(holder, name, 26, color, 15, { Position = UDim2.new(0.5, size / 2 - 6, 0, 12), Visible = false })
		Kit.Stroke(b, Theme.Colors.edge, 2, 0)
		label(b, { Text = glyph, TextSize = 15, AlignX = "Center", Color = Theme.White, ZIndex = 16, Font = "numeric" })
		return b
	end
	w.Lock = badge("LockBadge", "🔒", COLORS.LockedRing)
	w.Check = badge("MaxBadge", "✓", COLORS.Gold)
	w.Ready = badge("BuyBadge", "▲", COLORS.Good)
	if node.Capstone then
		local crown = label(holder, { Name = "Crown", Text = "★", TextSize = 18, AlignX = "Center", Color = COLORS.Gold, Stroke = 0.2,
			Size = UDim2.fromOffset(30, 20), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 12), ZIndex = 16 })
		w.Crown = crown
	end
	-- Level pips.
	local pipSize = node.Max <= 6 and 9 or 7
	local pips = New("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, size + 15),
		Size = UDim2.fromOffset(node.Max * (pipSize + 3), pipSize),
		ZIndex = 12,
	}, holder)
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pips)
	w.Pips = {}
	for i = 1, node.Max do
		local pip = New("Frame", {
			Name = "Pip" .. i,
			Size = UDim2.fromOffset(pipSize, pipSize),
			BackgroundColor3 = COLORS.Pip,
			BorderSizePixel = 0,
			LayoutOrder = i,
			ZIndex = 12,
		}, pips)
		Kit.Corner(pip, "pill")
		w.Pips[i] = pip
	end
	w.Name = label(holder, {
		Name = "NodeName",
		Text = L(node.Name),
		TextSize = 14,
		MinTextSize = 10,
		Scaled = true,
		Wrap = true,
		AlignX = "Center",
		AlignY = "Top",
		Position = UDim2.fromOffset(4, size + 15 + pipSize + 4),
		Size = UDim2.new(1, -8, 0, 34),
		ZIndex = 12,
		Stroke = false,
	})
	return w
end

local function build()
	local win = Kit.Window.new({
		Key = "UpgradeTree",
		Name = "UpgradeTreeWindow",
		Title = L("UPGRADE TREE"),
		Subtitle = L("Upgrades work anywhere. Tap a node to see what it gives."),
		Accent = C3(98, 178, 72),
		Icon = "Yard",
		NoTranslate = true,
		MaxSize = Vector2.new(1200, 820),
	})
	ui = { Window = win, Nodes = {}, Edges = {}, Stubs = {}, Maid = Kit.Maid.new() }
	win.Maid:Give(ui.Maid)
	local body = win.Body

	-- Toolbar: tree progress on the left, wallet on the right.
	local toolbar = New("Frame", { Name = "Toolbar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), ZIndex = 3 }, body)
	ui.Toolbar = toolbar
	ui.ProgressLabel = label(toolbar, { Name = "Progress", Text = "", Font = "numeric", TextSize = 17, MinTextSize = 10, Scaled = true, Color = Theme.Ink, ZIndex = 4,
		Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(180, 20) })
	ui.ProgressBar = Kit.ProgressBar(toolbar, { Name = "ProgressBar", Value = 0, Height = 12, Color = C3(98, 178, 72), ZIndex = 4,
		Position = UDim2.fromOffset(2, 24), Size = UDim2.fromOffset(180, 12), NoTranslate = true })
	local function chip(name: string, icon: string, color: Color3): (Frame, any)
		local frame = New("Frame", { Name = name, BackgroundColor3 = Theme.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(118, 34), ZIndex = 4 }, toolbar)
		Kit.Corner(frame, "pill")
		Kit.Stroke(frame, Theme.Colors.edge, 2, 0.35)
		Kit.Icon(frame, icon, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Color = Theme.White, Glyph = icon == "Bones" and "🦴" or "$" })
		local text = label(frame, { Name = "Amount", Text = "0", Font = "numeric", TextSize = 17, Color = color, AlignX = "Right", Scaled = true, MinTextSize = 11,
			Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -42, 1, 0), ZIndex = 5 })
		return frame, text
	end
	ui.CashChip, ui.CashText = chip("CashChip", "Coins", C3(40, 150, 40))
	ui.BonesChip, ui.BonesText = chip("BonesChip", "Bones", Theme.Ink)

	-- Canvas area: the scrolling tree and its floating controls.
	local area = New("Frame", { Name = "CanvasArea", BackgroundTransparency = 1, ZIndex = 3 }, body)
	ui.Area = area
	local canvas = New("ScrollingFrame", {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Sky,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.edge,
		ScrollBarImageTransparency = 0.4,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		CanvasSize = UDim2.fromOffset(CONTENT_W, CONTENT_H),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ClipsDescendants = true,
		Selectable = false,
		ZIndex = 3,
	}, area)
	Kit.Corner(canvas, Theme.Radius.Card)
	Kit.Stroke(canvas, Theme.Colors.edge, 2, 0.2)
	ui.Canvas = canvas
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CONTENT_W, CONTENT_H),
		ZIndex = 3,
	}, canvas)
	ui.Content = content
	ui.Scale = New("UIScale", { Name = "Zoom", Scale = 1 }, content)

	-- Backdrop: sky over the crown, soil under the roots, the trunk between them.
	local sky = New("Frame", { Name = "Sky", BorderSizePixel = 0, Size = UDim2.fromOffset(CONTENT_W, HUB_POINT.Y), ZIndex = 3 }, content)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(COLORS.Sky, COLORS.Grass) }, sky)
	sky.BackgroundColor3 = Theme.White
	local soil = New("Frame", { Name = "Soil", BorderSizePixel = 0, Position = UDim2.fromOffset(0, HUB_POINT.Y),
		Size = UDim2.fromOffset(CONTENT_W, CONTENT_H - HUB_POINT.Y), ZIndex = 3, BackgroundColor3 = Theme.White }, content)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(COLORS.Soil:Lerp(Theme.White, 0.45), COLORS.SoilDeep:Lerp(Theme.White, 0.35)) }, soil)
	local left, right = point(bounds.MinX, 0), point(bounds.MaxX, 0)
	local trunk = New("Frame", { Name = "Trunk", AnchorPoint = Vector2.new(0, 0.5), BorderSizePixel = 0, BackgroundColor3 = Theme.White,
		Position = UDim2.fromOffset(left.X - 40, HUB_POINT.Y), Size = UDim2.fromOffset(right.X - left.X + 80, 18), ZIndex = 5 }, content)
	Kit.Corner(trunk, "pill")
	Kit.Stroke(trunk, Theme.Colors.edge, 2, 0.3)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(COLORS.TrunkLight, COLORS.Trunk) }, trunk)

	-- Connectors: hub stubs (trunk to the first node of every path) and prerequisite lines.
	for _, edge in ipairs(Tree.Edges) do
		local child = Tree.Nodes[edge.To]
		local branch = Tree.BranchById[child.Branch]
		local b = point(child.X, child.Y)
		if edge.From == "Hub" then
			local frame, bar = line(content, Vector2.new(b.X, HUB_POINT.Y), b, 10, 6, COLORS.Track, branch.Color)
			frame.Name = "Stub_" .. edge.To
			bar.Size = UDim2.fromScale(1, 1)
			table.insert(ui.Stubs, { To = edge.To, Frame = frame, Fill = bar })
		else
			local parent = Tree.Nodes[edge.From]
			local frame, bar = line(content, point(parent.X, parent.Y), b, 8, 6, COLORS.Track, branch.Color)
			frame.Name = "Edge_" .. edge.From .. "_" .. edge.To
			table.insert(ui.Edges, { From = edge.From, To = edge.To, Need = edge.Need, Frame = frame, Fill = bar, Value = -1 })
		end
	end

	-- Branch labels above the crown and below the roots.
	for _, branch in ipairs(Tree.Branches) do
		local minX, maxX, top, bottom = math.huge, -math.huge, math.huge, -math.huge
		for _, node in pairs(Tree.Nodes) do
			if node.Branch == branch.Id then
				minX, maxX = math.min(minX, node.X), math.max(maxX, node.X)
				top, bottom = math.min(top, node.Y), math.max(bottom, node.Y)
			end
		end
		local y = branch.Side == "Crown" and top - 0.68 or bottom + 0.8
		local at = point((minX + maxX) / 2, y)
		local pill = Kit.Pill(content, { Name = "Branch_" .. branch.Id, Text = L(branch.Name), Color = branch.Color, TextSize = 14, Height = 28,
			PadX = 12, ZIndex = 8, NoTranslate = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X, at.Y) })
		Kit.Stroke(pill.Instance, Theme.Colors.edge, 2, 0.25)
	end

	-- Hub: the workshop with the tree progress.
	local hub = circle(content, "Hub", HUB, Theme.White, 20, { Position = UDim2.fromOffset(HUB_POINT.X, HUB_POINT.Y) })
	Kit.Stroke(hub, Theme.Colors.edge, 4, 0)
	Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(255, 224, 120), C3(240, 160, 30)) }, hub)
	Kit.Icon(hub, "Yard", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 21, Color = Theme.White })
	ui.HubPercent = label(hub, { Name = "Percent", Text = "0%", Font = "numeric", TextSize = 20, AlignX = "Center", Color = Theme.White, Stroke = 0.1,
		Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, 0, 0, 24), ZIndex = 21 })
	local hubButton = New("TextButton", { Name = "HubButton", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 22 }, hub)
	hubButton:SetAttribute("NoTranslate", true)
	label(content, { Name = "HubCaption", Text = L("WORKSHOP"), TextSize = 15, AlignX = "Center", Color = Theme.White, Stroke = 0.1,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(HUB_POINT.X, HUB_POINT.Y + HUB / 2 + 2), Size = UDim2.fromOffset(160, 22), ZIndex = 21 })

	-- Nodes.
	for _, id in ipairs(Tree.Order) do
		local w = buildNode(content, id)
		ui.Nodes[id] = w
	end

	-- Floating canvas controls: zoom and the bonus summary.
	local controls = New("Frame", { Name = "Controls", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(44, 148), ZIndex = 30 }, area)
	ui.ControlsLayout = New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, controls)
	ui.ZoomIn = Kit.Button(controls, { Name = "ZoomIn", Text = "+", Style = "secondary", Size = UDim2.fromOffset(44, 44), LayoutOrder = 1, ZIndex = 31, NoTranslate = true,
		OnClick = function() setZoom(state.Zoom * 1.2) end })
	ui.ZoomOut = Kit.Button(controls, { Name = "ZoomOut", Text = "−", Style = "secondary", Size = UDim2.fromOffset(44, 44), LayoutOrder = 2, ZIndex = 31, NoTranslate = true,
		OnClick = function() setZoom(state.Zoom / 1.2) end })
	ui.Fit = Kit.Button(controls, { Name = "Fit", Text = "⤢", Style = "secondary", Size = UDim2.fromOffset(44, 44), LayoutOrder = 3, ZIndex = 31, NoTranslate = true,
		OnClick = function()
			local size = canvas.AbsoluteSize
			setZoom(math.min(size.X / CONTENT_W, size.Y / CONTENT_H))
		end })
	ui.BonusesButton = Kit.Button(toolbar, { Name = "MyBonuses", Text = L("MY BONUSES"), Icon = "Star", Style = "gold", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -260, 0.5, 0), Size = UDim2.fromOffset(170, 38), ZIndex = 5, NoTranslate = true,
		OnClick = function() select(nil, true) end })

	-- Detail panel (side panel or bottom sheet).
	local panel = New("Frame", { Name = "Panel", BackgroundColor3 = Theme.SurfaceAlt, BorderSizePixel = 0, ZIndex = 40, Active = true }, body)
	Kit.Corner(panel, Theme.Radius.Card)
	ui.PanelStroke = Kit.Stroke(panel, Theme.Colors.edge, 2, 0.2)
	ui.Panel = panel
	ui.SheetClose = Kit.Button(panel, { Name = "CloseSheet", Text = "✕", Style = "ghost", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(40, 40), ZIndex = 48, NoTranslate = true, OnClick = function() showSheet(false) end })
	ui.Handle = New("Frame", { Name = "Handle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(46, 5),
		BackgroundColor3 = Theme.Colors.edge, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 41 }, panel)
	Kit.Corner(ui.Handle, "pill")

	-- Node details.
	local detail = New("Frame", { Name = "Detail", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 41 }, panel)
	ui.Detail = detail
	local scroll = New("ScrollingFrame", { Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 1, -66), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5, ScrollBarImageColor3 = Theme.Colors.edge, ZIndex = 41, Selectable = false }, detail)
	ui.DetailScroll = scroll
	New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	Kit.Padding(scroll, 12, 12, 14, 10)
	-- Header: icon, name, branch, level.
	local header = New("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 1, ZIndex = 42 }, scroll)
	ui.DetailHeader = header
	ui.DetailBadge = circle(header, "Badge", 54, Theme.White, 42, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
	ui.DetailRing = Kit.Stroke(ui.DetailBadge, Theme.Colors.edge, 3, 0)
	ui.DetailIconHolder = New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(32, 32), ZIndex = 43 }, ui.DetailBadge)
	ui.DetailName = label(header, { Name = "Name", Text = "", TextSize = 21, MinTextSize = 12, Scaled = true, Color = Theme.Ink, ZIndex = 42,
		Position = UDim2.fromOffset(64, 2), Size = UDim2.new(1, -110, 0, 28) })
	ui.DetailBranch = label(header, { Name = "Branch", Text = "", TextSize = 14, MinTextSize = 10, Scaled = true, ZIndex = 42,
		Position = UDim2.fromOffset(64, 32), Size = UDim2.new(1, -150, 0, 20) })
	ui.DetailLevel = Kit.Pill(header, { Name = "Level", Text = "", Color = Theme.Colors.edge, TextSize = 13, Height = 24, ZIndex = 42, NoTranslate = true, Font = "numeric",
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 30) })
	ui.DetailDescription = label(scroll, { Name = "Description", Text = "", TextSize = 15, Wrap = true, AlignY = "Top", Color = Theme.InkMuted, LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0), ZIndex = 42 })
	ui.DetailDescription.AutomaticSize = Enum.AutomaticSize.Y
	-- Bonus box: NOW -> NEXT.
	local bonus = New("Frame", { Name = "Bonus", BackgroundColor3 = Theme.White, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 104), LayoutOrder = 2, ZIndex = 42 }, scroll)
	Kit.Corner(bonus, Theme.Radius.Field)
	Kit.Stroke(bonus, Theme.Colors.edge, 2, 0.5)
	ui.Bonus = bonus
	ui.NowCaption = label(bonus, { Name = "NowCaption", Text = L("NOW"), TextSize = 12, Color = Theme.InkMuted, AlignX = "Center", ZIndex = 43,
		Position = UDim2.fromScale(0, 0.06), Size = UDim2.fromScale(0.42, 0.18) })
	ui.NextCaption = label(bonus, { Name = "NextCaption", Text = L("NEXT"), TextSize = 12, Color = Theme.InkMuted, AlignX = "Center", ZIndex = 43,
		Position = UDim2.fromScale(0.58, 0.06), Size = UDim2.fromScale(0.42, 0.18) })
	ui.NowValue = label(bonus, { Name = "Now", Text = "", Font = "numeric", TextSize = 26, MinTextSize = 12, Scaled = true, AlignX = "Center", Color = Theme.Ink, ZIndex = 43,
		Position = UDim2.fromScale(0.02, 0.24), Size = UDim2.fromScale(0.40, 0.34) })
	ui.Arrow = label(bonus, { Name = "Arrow", Text = "→", TextSize = 24, AlignX = "Center", Color = Theme.InkMuted, Font = "numeric", ZIndex = 43,
		Position = UDim2.fromScale(0.42, 0.24), Size = UDim2.fromScale(0.16, 0.34) })
	ui.NextValue = label(bonus, { Name = "Next", Text = "", Font = "numeric", TextSize = 26, MinTextSize = 12, Scaled = true, AlignX = "Center", Color = C3(46, 160, 60), ZIndex = 43,
		Position = UDim2.fromScale(0.58, 0.24), Size = UDim2.fromScale(0.40, 0.34) })
	ui.StatLabel = label(bonus, { Name = "Stat", Text = "", TextSize = 14, MinTextSize = 10, Scaled = true, AlignX = "Center", Color = Theme.Ink, ZIndex = 43,
		Position = UDim2.fromScale(0.04, 0.60), Size = UDim2.fromScale(0.92, 0.17) })
	ui.PerLevel = label(bonus, { Name = "PerLevel", Text = "", TextSize = 12, MinTextSize = 9, Scaled = true, AlignX = "Center", Color = Theme.InkMuted, ZIndex = 43,
		Position = UDim2.fromScale(0.04, 0.79), Size = UDim2.fromScale(0.92, 0.15) })
	-- Estate stage preview (EXPAND YOUR YARD only).
	local estate = New("Frame", { Name = "Estate", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 196), LayoutOrder = 4, Visible = false, ZIndex = 42 }, scroll)
	ui.Estate = estate
	ui.EstateView = New("ViewportFrame", { Name = "NextStagePreview", BackgroundColor3 = C3(28, 36, 48), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 140),
		Ambient = C3(175, 175, 185), LightColor = Color3.new(1, 1, 0.94), LightDirection = Vector3.new(-1, -1, -0.5), ZIndex = 42 }, estate)
	Kit.Corner(ui.EstateView, Theme.Radius.Field)
	ui.EstateCaption = label(estate, { Name = "Caption", Text = "", TextSize = 14, Wrap = true, AlignY = "Top", Color = Theme.Ink, ZIndex = 42,
		Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 48) })
	-- Requirements.
	ui.ReqTitle = label(scroll, { Name = "RequirementsTitle", Text = L("REQUIREMENTS"), TextSize = 14, Color = Theme.InkMuted, LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 18), ZIndex = 42 })
	ui.ReqRows = {}
	for i = 1, 3 do
		local row = New("Frame", { Name = "Requirement" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 5 + i, ZIndex = 42 }, scroll)
		local mark = circle(row, "Mark", 20, COLORS.Good, 42, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
		local glyph = label(mark, { Name = "Glyph", Text = "✓", TextSize = 13, AlignX = "Center", Color = Theme.White, Font = "numeric", ZIndex = 43 })
		local text = label(row, { Name = "Text", Text = "", TextSize = 15, MinTextSize = 10, Scaled = true, Color = Theme.Ink, ZIndex = 42,
			Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0) })
		ui.ReqRows[i] = { Frame = row, Mark = mark, Glyph = glyph, Text = text }
	end
	-- Price.
	local price = New("Frame", { Name = "Price", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 10, ZIndex = 42 }, scroll)
	ui.Price = price
	label(price, { Name = "Caption", Text = L("PRICE"), TextSize = 14, Color = Theme.InkMuted, Size = UDim2.new(0.3, 0, 1, 0), ZIndex = 42 })
	ui.PriceCash = label(price, { Name = "Cash", Text = "", Font = "numeric", TextSize = 18, MinTextSize = 11, Scaled = true, AlignX = "Right", ZIndex = 42,
		Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.4, 1) })
	ui.PriceBones = label(price, { Name = "Bones", Text = "", Font = "numeric", TextSize = 18, MinTextSize = 11, Scaled = true, AlignX = "Right", ZIndex = 42,
		Position = UDim2.fromScale(0.7, 0), Size = UDim2.fromScale(0.3, 1) })
	-- BUY (pinned under the scroll).
	ui.Buy = Kit.Button(detail, { Name = "Buy", Text = L("BUY"), Style = "success", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 48), ZIndex = 45, NoTranslate = true, OnClick = function() buy() end })
	ui.BuyPop = New("UIScale", { Name = "Pop" }, ui.Buy.Instance)

	-- Summary of the active tree bonuses.
	local summary = New("ScrollingFrame", { Name = "Summary", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.edge, ZIndex = 41, Visible = false, Selectable = false }, panel)
	ui.Summary = summary
	New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, summary)
	Kit.Padding(summary, 12, 14, 14, 12)
	label(summary, { Name = "Title", Text = L("YOUR TREE BONUSES"), TextSize = 19, MinTextSize = 12, Scaled = true, Color = Theme.Ink, LayoutOrder = 1,
		Size = UDim2.new(1, -36, 0, 26), ZIndex = 42 })
	ui.SummaryProgress = label(summary, { Name = "Progress", Text = "", Font = "numeric", TextSize = 14, Color = Theme.InkMuted, LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18), ZIndex = 42 })
	ui.SummaryRows = {}
	for i, row in ipairs(Tree.Summary({})) do
		local frame = New("Frame", { Name = "Row_" .. row.Id, BackgroundColor3 = Theme.White, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = 10 + i, ZIndex = 42 }, summary)
		Kit.Corner(frame, Theme.Radius.Small)
		local name = label(frame, { Name = "Label", Text = L(row.Label), TextSize = 14, MinTextSize = 9, Scaled = true, ZIndex = 43,
			Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.66, -10, 1, 0) })
		local value = label(frame, { Name = "Value", Text = "", Font = "numeric", TextSize = 16, MinTextSize = 9, Scaled = true, AlignX = "Right", ZIndex = 43,
			Position = UDim2.new(0.66, 0, 0, 0), Size = UDim2.new(0.34, -10, 1, 0) })
		ui.SummaryRows[row.Id] = { Frame = frame, Label = name, Value = value }
	end
	-- Legend and hints.
	local legend = New("Frame", { Name = "Legend", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 72), LayoutOrder = 100, ZIndex = 42 }, summary)
	New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, legend)
	for i, entry in ipairs({ { COLORS.Good, "▲", "Ready to buy" }, { COLORS.LockedRing, "🔒", "Locked" }, { COLORS.Gold, "✓", "Maxed" } }) do
		local row = New("Frame", { Name = "Legend" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i, ZIndex = 42 }, legend)
		local dot = circle(row, "Dot", 18, entry[1], 42, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
		label(dot, { Text = entry[2], TextSize = 11, AlignX = "Center", Color = Theme.White, Font = "numeric", ZIndex = 43 })
		label(row, { Text = L(entry[3]), TextSize = 14, Color = Theme.Ink, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), ZIndex = 42 })
	end
	local hint = label(summary, { Name = "Hint", Text = L("Tap a node to see what it gives.") .. "\n" .. L("Every upgrade works anywhere: no need to visit the workshop."),
		TextSize = 14, Wrap = true, AlignY = "Top", Color = Theme.InkMuted, LayoutOrder = 101, Size = UDim2.new(1, 0, 0, 0), ZIndex = 42 })
	hint.AutomaticSize = Enum.AutomaticSize.Y

	-- Loading / error state over the canvas.
	ui.Status = label(area, { Name = "Status", Text = L("Loading your upgrades..."), TextSize = 16, AlignX = "Center", Color = Theme.Ink, Wrap = true,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(0.7, 0, 0, 40), ZIndex = 32, Visible = false })

	----------------------------------------------------------------------------------------------
	-- Input: node taps, mouse drag to pan, ctrl+wheel and pinch to zoom.
	----------------------------------------------------------------------------------------------
	local drag: any = nil
	local function beginDrag(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = { Start = Vector2.new(input.Position.X, input.Position.Y), Canvas = canvas.CanvasPosition, Moved = false }
		end
	end
	ui.Maid:Give(canvas.InputBegan:Connect(beginDrag))
	ui.Maid:Give(canvas.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			setZoom(state.Zoom * (input.Position.Z > 0 and 1.1 or 1 / 1.1))
		end
	end))
	ui.Maid:Give(UserInputService.InputChanged:Connect(function(input)
		if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.Start
		if delta.Magnitude > 6 then
			drag.Moved = true
		end
		if drag.Moved then
			local size = canvas.AbsoluteCanvasSize - canvas.AbsoluteWindowSize
			local target = drag.Canvas - delta
			canvas.CanvasPosition = Vector2.new(math.clamp(target.X, 0, math.max(0, size.X)), math.clamp(target.Y, 0, math.max(0, size.Y)))
		end
	end))
	ui.Maid:Give(UserInputService.InputEnded:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.DraggedAt = drag.Moved and os.clock() or state.DraggedAt
			drag = nil
		end
	end))
	local pinchStart = nil
	ui.Maid:Give(UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, inputState)
		if not win.IsOpen then
			return
		end
		if inputState == Enum.UserInputState.Begin then
			pinchStart = state.Zoom
		elseif inputState == Enum.UserInputState.Change and pinchStart then
			setZoom(pinchStart * scale)
		else
			pinchStart = nil
		end
	end))
	for id, w in pairs(ui.Nodes) do
		ui.Maid:Give(w.Button.InputBegan:Connect(beginDrag))
		ui.Maid:Give(w.Button.Activated:Connect(function()
			if (drag and drag.Moved) or (state.DraggedAt and os.clock() - state.DraggedAt < 0.15) then
				return -- the press ended a drag
			end
			select(id, true)
		end))
	end
	ui.Maid:Give(hubButton.Activated:Connect(function()
		select(nil, true)
	end))

	-- Live data while open.
	ui.Maid:Give(Net.Changed:Connect(function(snapshot)
		if win.IsOpen then
			readSnapshot(snapshot)
			readLive()
			refresh()
		end
	end))
	local scheduled = false
	local function live()
		if not win.IsOpen or scheduled then
			return
		end
		scheduled = true
		task.delay(0.25, function()
			scheduled = false
			if win.IsOpen then
				readLive()
				refresh()
			end
		end)
	end
	ui.Maid:Give(player:GetAttributeChangedSignal("Bones"):Connect(live))
	ui.Maid:Give(player:GetAttributeChangedSignal("Level"):Connect(live))
	ui.Maid:Give(player:GetAttributeChangedSignal("InventoryRevision"):Connect(live))
	ui.Maid:Give(win.Resized:Connect(function(layout)
		arrange(layout)
	end))
	ui.Maid:Give(win.Closed:Connect(function()
		state.SheetOpen = false
		if ui.SelectLoop then
			ui.SelectLoop:Cancel()
			ui.SelectLoop = nil
		end
		-- The estate preview is a clone of the whole yard: free it with the window.
		ui.EstateToken = nil
		for _, child in ipairs(ui.EstateView:GetChildren()) do
			if child:IsA("Model") or child:IsA("Camera") then
				child:Destroy()
			end
		end
	end))
	arrange(win:GetLayout())
end

------------------------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------------------------
local function clampCanvas(target: Vector2): Vector2
	local canvas = ui.Canvas
	local size = canvas.AbsoluteSize
	local maxX = math.max(0, CONTENT_W * state.Zoom - size.X)
	local maxY = math.max(0, CONTENT_H * state.Zoom - size.Y)
	return Vector2.new(math.clamp(target.X, 0, maxX), math.clamp(target.Y, 0, maxY))
end

setZoom = function(zoom: number, keepCenter: Vector2?)
	if not ui then
		return
	end
	local canvas = ui.Canvas
	local size = canvas.AbsoluteSize
	local old = state.Zoom
	zoom = math.clamp(zoom, ZOOM_MIN, ZOOM_MAX)
	-- Keep the content point in the middle of the view where it was.
	local center = keepCenter or ((canvas.CanvasPosition + size / 2) / old)
	state.Zoom = zoom
	ui.Scale.Scale = zoom
	canvas.CanvasSize = UDim2.fromOffset(math.ceil(CONTENT_W * zoom), math.ceil(CONTENT_H * zoom))
	canvas.CanvasPosition = clampCanvas(center * zoom - size / 2)
end
Screen.SetZoom = function(z: number)
	setZoom(z)
end

-- Scrolls the canvas so a node is in view (above the bottom sheet on phones).
reveal = function(id: string?, animate: boolean?)
	local canvas = ui.Canvas
	local size = canvas.AbsoluteSize
	local target
	if id and ui.Nodes[id] then
		local at = ui.Nodes[id].Point * state.Zoom
		local visibleH = size.Y
		if not state.Side and state.SheetOpen then
			visibleH = math.max(80, size.Y - ui.SheetHeight)
		end
		target = clampCanvas(Vector2.new(at.X - size.X / 2, at.Y - visibleH / 2))
	else
		-- The hub and the first rows of both halves.
		local at = Vector2.new(HUB_POINT.X, HUB_POINT.Y - UNIT_Y * 0.9) * state.Zoom
		target = clampCanvas(Vector2.new(at.X - size.X / 2, at.Y - size.Y / 2))
	end
	if animate and not Motion.Reduced() then
		Motion.Tween(canvas, Theme.Motion.Slide, { CanvasPosition = target })
	else
		canvas.CanvasPosition = target
	end
end

showSheet = function(open: boolean)
	if state.Side then
		return
	end
	state.SheetOpen = open
	if not open then
		select(nil, false)
	end
	local panel = ui.Panel
	local goal = open and UDim2.new(0, 0, 1, -ui.SheetHeight) or UDim2.new(0, 0, 1, 16)
	panel.Visible = true
	local tween = Motion.Tween(panel, Theme.Motion.Slide, { Position = goal })
	if not open then
		if tween then
			local token = {}
			ui.SheetToken = token
			tween.Completed:Once(function()
				if ui.SheetToken == token and not state.SheetOpen then
					panel.Visible = false
				end
			end)
		else
			panel.Visible = false
		end
	end
end

arrange = function(layout: any)
	if not ui or not layout or (layout.Width or 0) < 10 then
		return
	end
	local W, H = layout.Width, layout.Height
	local phone = layout.Phone
	local toolbarH = phone and (layout.Landscape and 36 or 42) or 44
	local toolbar = ui.Toolbar
	toolbar.Size = UDim2.new(1, 0, 0, toolbarH)
	-- Progress on the left; MY BONUSES and the wallet on the right.
	local chipW, gap, chipH = phone and 98 or 128, 8, toolbarH - 6
	local bonesW = chipW - 18
	ui.BonesChip.Size = UDim2.fromOffset(bonesW, chipH)
	ui.BonesChip.Position = UDim2.new(1, 0, 0.5, 0)
	ui.CashChip.Size = UDim2.fromOffset(chipW, chipH)
	ui.CashChip.Position = UDim2.new(1, -(bonesW + gap), 0.5, 0)
	local narrow = W < 560
	local bonusW = narrow and chipH or (phone and 150 or 176)
	ui.BonusesButton:SetText(narrow and "" or L("MY BONUSES"))
	ui.BonusesButton.Instance.Size = UDim2.fromOffset(bonusW, chipH)
	ui.BonusesButton.Instance.Position = UDim2.new(1, -(bonesW + chipW + gap * 2), 0.5, 0)
	local progressW = math.clamp(W - (bonesW + chipW + bonusW + gap * 3) - 6, 60, 260)
	ui.ProgressLabel.Size = UDim2.fromOffset(progressW, math.floor(toolbarH * 0.5))
	ui.ProgressBar.Instance.Position = UDim2.fromOffset(2, math.floor(toolbarH * 0.56))
	ui.ProgressBar.Instance.Size = UDim2.fromOffset(progressW, math.max(8, math.floor(toolbarH * 0.28)))
	local top = toolbarH + (phone and 4 or 8)
	state.Side = W >= 620
	local area, panel = ui.Area, ui.Panel
	if state.Side then
		local panelW = math.clamp(math.floor(W * 0.34), 270, 380)
		area.Position = UDim2.fromOffset(0, top)
		area.Size = UDim2.new(1, -(panelW + 10), 1, -top)
		panel.Position = UDim2.new(1, -panelW, 0, top)
		panel.Size = UDim2.new(0, panelW, 1, -top)
		panel.Visible = true
		ui.PanelStroke.Enabled = true
		ui.SheetClose.Instance.Visible = false
		ui.Handle.Visible = false
	else
		area.Position = UDim2.fromOffset(0, top)
		area.Size = UDim2.new(1, 0, 1, -top)
		ui.SheetHeight = math.clamp(math.floor((H - top) * 0.6), 220, 480)
		panel.Size = UDim2.new(1, 0, 0, ui.SheetHeight)
		panel.Position = state.SheetOpen and UDim2.new(0, 0, 1, -ui.SheetHeight) or UDim2.new(0, 0, 1, 16)
		panel.Visible = state.SheetOpen
		ui.PanelStroke.Enabled = true
		ui.SheetClose.Instance.Visible = true
		ui.Handle.Visible = true
	end
	-- Panel content: the sheet keeps room for its close button.
	ui.DetailScroll.Position = UDim2.fromOffset(0, state.Side and 0 or 14)
	ui.DetailScroll.Size = UDim2.new(1, 0, 1, -(66 + (state.Side and 0 or 14)))
	ui.Summary.Position = UDim2.fromOffset(0, state.Side and 0 or 14)
	ui.Summary.Size = UDim2.new(1, 0, 1, state.Side and 0 or -14)
	-- Floating controls: compact on phones.
	local buttonSize = phone and 40 or 44
	for _, b in ipairs({ ui.ZoomIn, ui.ZoomOut, ui.Fit }) do
		b.Instance.Size = UDim2.fromOffset(buttonSize, buttonSize)
	end
	-- A short canvas (landscape phone) gets the zoom buttons in a row.
	local row = (H - top) < 300
	ui.ControlsLayout.FillDirection = row and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	ui.ZoomIn.Instance.Parent.Size = row and UDim2.fromOffset(buttonSize * 3 + 16, buttonSize) or UDim2.fromOffset(buttonSize, buttonSize * 3 + 16)
	-- Compact detail panel on short screens.
	local compact = (H - top) < 340
	ui.DetailHeader.Size = UDim2.new(1, 0, 0, compact and 48 or 58)
	ui.DetailBadge.Size = UDim2.fromOffset(compact and 42 or 54, compact and 42 or 54)
	ui.DetailName.Position = UDim2.fromOffset(compact and 52 or 64, compact and 0 or 2)
	ui.DetailBranch.Position = UDim2.fromOffset(compact and 52 or 64, compact and 27 or 32)
	ui.DetailLevel.Instance.Position = UDim2.new(1, 0, 0, compact and 24 or 30)
	ui.Bonus.Size = UDim2.new(1, 0, 0, compact and 88 or 104)
	ui.Canvas.ScrollBarThickness = layout.Touch and 4 or 8
	if state.LayoutKey ~= (state.Side and "side" or "sheet") .. tostring(phone) then
		state.LayoutKey = (state.Side and "side" or "sheet") .. tostring(phone)
		state.Zoom = math.clamp(phone and (layout.Landscape and 0.72 or 0.8) or 1, ZOOM_MIN, ZOOM_MAX)
		ui.Scale.Scale = state.Zoom
		ui.Canvas.CanvasSize = UDim2.fromOffset(math.ceil(CONTENT_W * state.Zoom), math.ceil(CONTENT_H * state.Zoom))
		task.defer(reveal, state.Selected, false)
	end
	refresh()
end

------------------------------------------------------------------------------------------------
-- Rendering (in place; nothing is rebuilt)
------------------------------------------------------------------------------------------------
local STATUS_PRIORITY = { affordable = 1, ready = 2, locked = 3, max = 4 }

local function paintNode(w: any, status: string, level: number, max: number, selected: boolean)
	local branch = w.Branch
	local locked, maxed = status == "locked", status == "max"
	w.Button.BackgroundColor3 = locked and COLORS.LockedFace or Theme.White
	w.Gradient.Enabled = not locked
	w.Gradient.Color = maxed and ColorSequence.new(branch.Color:Lerp(Theme.White, 0.55), branch.Color:Lerp(Theme.White, 0.25))
		or ColorSequence.new(Theme.White, C3(236, 242, 250))
	w.Ring.Color = locked and COLORS.LockedRing or maxed and COLORS.Gold or branch.Color
	if w.Icon:IsA("ImageLabel") then
		w.Icon.ImageColor3 = locked and COLORS.LockedIcon or maxed and Theme.White or branch.Color
		w.Icon.ImageTransparency = locked and 0.25 or 0
	else
		w.Icon.TextColor3 = locked and COLORS.LockedIcon or maxed and Theme.White or branch.Color
	end
	w.Glow.Visible = status == "affordable"
	w.Lock.Visible = locked
	w.Check.Visible = maxed
	w.Ready.Visible = status == "affordable"
	w.Name.TextColor3 = locked and Theme.InkMuted or Theme.Ink
	for i, pip in ipairs(w.Pips) do
		pip.BackgroundColor3 = i <= level and (maxed and COLORS.Gold or branch.Color) or COLORS.Pip
	end
	w.Select.Visible = selected
	w.Holder.ZIndex = selected and 11 or 10
end

local function paintDetail(id: string, p: any)
	local node = Tree.Nodes[id]
	local branch = Tree.BranchById[node.Branch]
	local level = Tree.Level(p, id)
	local maxed = level >= node.Max
	local status = Tree.Status(p, id)
	ui.DetailName.Text = L(node.Name)
	ui.DetailBranch.Text = L(branch.Name) .. (node.Capstone and ("  ·  " .. L("CAPSTONE")) or "")
	ui.DetailBranch.TextColor3 = branch.Color:Lerp(Color3.new(0, 0, 0), 0.15)
	ui.DetailLevel:Set(LF("LV %s / %s", math.min(level, node.Max), node.Max), maxed and COLORS.Gold or Theme.Colors.edge)
	ui.DetailRing.Color = maxed and COLORS.Gold or branch.Color
	if ui.DetailIconKey ~= branch.Icon then
		ui.DetailIconKey = branch.Icon
		for _, child in ipairs(ui.DetailIconHolder:GetChildren()) do
			child:Destroy()
		end
		local icon = Kit.Icon(ui.DetailIconHolder, branch.Icon, { Size = UDim2.fromScale(1, 1), ZIndex = 43, Color = branch.Color })
		ui.DetailIcon = icon
	end
	if ui.DetailIcon and ui.DetailIcon:IsA("ImageLabel") then
		ui.DetailIcon.ImageColor3 = branch.Color
	end
	ui.DetailDescription.Text = L(node.Description)
	-- CURRENT -> NEXT from the definitions.
	local nowText, statLabel = Tree.Text(id, level)
	local nextText = maxed and L("MAX") or (Tree.Text(id, level + 1))
	if node.Format == "stage" then
		nowText, nextText = L(nowText), maxed and L("MAX") or L(nextText)
	end
	ui.NowValue.Text = nowText
	ui.NextValue.Text = nextText
	ui.NextValue.TextColor3 = maxed and COLORS.Gold or C3(46, 160, 60)
	ui.StatLabel.Text = L(statLabel)
	if node.Format == "stage" then
		-- The current stage: its kennels and the dug value it adds.
		local stage = Tree.Stage(level)
		ui.PerLevel.Text = LF("%s kennels", stage.Slots) .. "  ·  " .. Tree.FormatValue("percent", node.PerLevel * level) .. " " .. L("dug value")
	else
		-- "+2% per level · MAX +20%" (a multiplier node adds its percent to its own factor).
		local one = node.Format == "count" and "+" .. tostring(node.PerLevel)
			or Tree.FormatValue(node.Format == "mult" and "percent" or node.Format, node.PerLevel)
		ui.PerLevel.Text = LF("%s per level", one) .. "  ·  " .. LF("MAX %s", (Tree.Text(id, node.Max)))
	end
	-- Estate: the next stage on the player's own yard.
	ui.Estate.Visible = id == "Plot"
	if id == "Plot" then
		local nextStage = math.clamp(level + 2, 1, #PlotCatalog.Stages)
		local stage = PlotCatalog.Stages[nextStage]
		ui.EstateCaption.Text = maxed and L("Your estate is fully developed.")
			or (L("NEXT STAGE") .. ": " .. L(stage.Name) .. " · " .. LF("%s kennels", stage.Slots) .. "\n" .. L(stage.Feature))
		if ui.EstateToken ~= tostring(nextStage) .. ":" .. tostring(state.Skin) then
			ui.EstateToken = tostring(nextStage) .. ":" .. tostring(state.Skin)
			for _, child in ipairs(ui.EstateView:GetChildren()) do
				if child:IsA("Model") or child:IsA("Camera") then
					child:Destroy()
				end
			end
			pcall(function()
				local map = workspace:FindFirstChild("DOGROTS_District")
				local yards = map and map:FindFirstChild("04_PlayerYards")
				local source
				for _, yard in ipairs(yards and yards:GetChildren() or {}) do
					if yard:GetAttribute("OwnerUserId") == player.UserId then
						source = yard
						break
					end
				end
				if not source then
					return
				end
				local Appearance = require(ReplicatedStorage:WaitForChild("PlotAppearance"))
				local model = Appearance.Preview(source, nextStage, state.Skin or "Classic")
				model.Parent = ui.EstateView
				local frame = Appearance.Frame(model)
				local camera = Instance.new("Camera")
				camera.FieldOfView = 38
				camera.CFrame = CFrame.lookAt(frame:PointToWorldSpace(Vector3.new(72, 120, 145)), frame:PointToWorldSpace(Vector3.new(0, 5, 0)))
				camera.Parent = ui.EstateView
				ui.EstateView.CurrentCamera = camera
			end)
		end
	end
	-- Requirements (level gate + prerequisite nodes), green or red.
	local rows = maxed and {} or Tree.Requirements(p, id)
	ui.ReqTitle.Visible = not maxed
	for i, row in ipairs(ui.ReqRows) do
		local req = rows[i]
		row.Frame.Visible = req ~= nil
		if req then
			row.Mark.BackgroundColor3 = req.Met and COLORS.Good or COLORS.Bad
			row.Glyph.Text = req.Met and "✓" or "✕"
			if req.Kind == "Level" then
				row.Text.Text = LF("Player level %s", req.Need)
			else
				row.Text.Text = LF("%s level %s", L(Tree.Nodes[req.Node].Name), req.Need) .. "  (" .. math.min(req.Have, req.Need) .. "/" .. req.Need .. ")"
			end
			row.Text.TextColor3 = req.Met and Theme.Ink or COLORS.Bad
		end
	end
	-- Price and BUY.
	local cash, bones = Tree.Cost(id, level)
	ui.Price.Visible = not maxed
	ui.PriceCash.Text = "$" .. short(cash)
	ui.PriceCash.TextColor3 = p.Cash >= cash and C3(40, 150, 40) or COLORS.Bad
	ui.PriceBones.Visible = bones > 0
	ui.PriceBones.Text = "🦴 " .. short(bones)
	ui.PriceBones.TextColor3 = p.Bones >= bones and Theme.Ink or COLORS.Bad
	local buyButton = ui.Buy
	if maxed then
		buyButton:SetText(L("MAXED OUT"))
		buyButton:SetStyle("gold")
		buyButton:SetPrice(nil)
		buyButton:SetDisabled(true)
	elseif status == "locked" then
		buyButton:SetText(L("LOCKED"))
		buyButton:SetStyle("secondary")
		buyButton:SetPrice(nil)
		buyButton:SetDisabled(true)
	elseif status == "ready" then
		local missing = math.max(0, cash - p.Cash)
		buyButton:SetText(missing > 0 and LF("NEED %s MORE", "$" .. short(missing)) or LF("NEED %s MORE", "🦴 " .. short(bones - p.Bones)))
		buyButton:SetStyle("secondary")
		buyButton:SetPrice(nil)
		buyButton:SetDisabled(true)
	else
		buyButton:SetText(level == 0 and L("UNLOCK") or LF("BUY LEVEL %s", level + 1))
		buyButton:SetStyle("success")
		buyButton:SetPrice(cash)
		buyButton:SetDisabled(false)
	end
end

local function paintSummary(p: any)
	local owned, total = Tree.Progress(p)
	ui.SummaryProgress.Text = L("TREE PROGRESS") .. ": " .. LF("%s / %s LEVELS", owned, total)
	for _, row in ipairs(Tree.Summary(p)) do
		local w = ui.SummaryRows[row.Id]
		if w then
			w.Value.Text = row.Id == "Plot" and L(row.Text) or row.Text
			w.Value.TextColor3 = row.Active and C3(40, 150, 40) or Theme.InkMuted
			w.Label.TextColor3 = row.Active and Theme.Ink or Theme.InkMuted
			w.Frame.BackgroundTransparency = row.Active and 0 or 0.5
		end
	end
end

refresh = function()
	if not ui then
		return
	end
	local p = view()
	-- Toolbar.
	local owned, total = Tree.Progress(p)
	ui.ProgressLabel.Text = LF("%s / %s LEVELS", owned, total)
	ui.ProgressBar:SetValue(total > 0 and owned / total or 0, state.FirstRender)
	ui.HubPercent.Text = math.floor(owned / math.max(1, total) * 100) .. "%"
	ui.CashText.Text = short(p.Cash)
	ui.BonesText.Text = short(p.Bones)
	ui.Status.Visible = not state.Loaded
	-- Nodes.
	local statuses = {}
	for id, w in pairs(ui.Nodes) do
		local node = Tree.Nodes[id]
		local status = Tree.Status(p, id)
		statuses[id] = status
		paintNode(w, status, math.min(Tree.Level(p, id), node.Max), node.Max, state.Selected == id)
	end
	-- Connectors fill as the parent levels up (animated after the first paint).
	for _, edge in ipairs(ui.Edges) do
		local value = math.clamp(Tree.Level(p, edge.From) / edge.Need, 0, 1)
		if edge.Value ~= value then
			local goal = { Size = UDim2.fromScale(value, 1) }
			if state.FirstRender or edge.Value < 0 then
				edge.Fill.Size = goal.Size
			else
				Motion.Tween(edge.Fill, Theme.Motion.Fill * 1.6, goal)
			end
			edge.Value = value
		end
		edge.Frame.BackgroundColor3 = statuses[edge.To] == "locked" and COLORS.Track or COLORS.Track:Lerp(Theme.White, 0.3)
	end
	for _, stub in ipairs(ui.Stubs) do
		stub.Fill.BackgroundTransparency = statuses[stub.To] == "locked" and 0.55 or 0
	end
	-- Panel.
	local selected = state.Selected
	ui.Detail.Visible = selected ~= nil
	ui.Summary.Visible = selected == nil
	if selected then
		paintDetail(selected, p)
	else
		paintSummary(p)
	end
	ui.Buy:SetBusy(state.Busy)
	state.FirstRender = false
end

select = function(id: string?, fromInput: boolean?)
	if not ui then
		return
	end
	state.Selected = id
	state.LastSelected = id or state.LastSelected
	if ui.SelectLoop then
		ui.SelectLoop:Cancel()
		ui.SelectLoop = nil
	end
	refresh()
	if id then
		local w = ui.Nodes[id]
		w.SelectStroke.Transparency = 0
		ui.SelectLoop = Motion.Loop(w.SelectStroke, 0.55, { Transparency = 0.7 })
		ui.DetailScroll.CanvasPosition = Vector2.zero
	end
	if not state.Side then
		if fromInput or id then
			showSheet(true)
		end
	end
	if fromInput and id then
		reveal(id, true)
	end
end
Screen.Select = function(id: string?)
	select(id, true)
end

------------------------------------------------------------------------------------------------
-- Purchase
------------------------------------------------------------------------------------------------
local function celebrate(id: string, newLevel: number)
	local w = ui.Nodes[id]
	if not w then
		return
	end
	local branch = w.Branch
	-- Pop the node.
	w.Pop.Scale = 1
	local up = Motion.Tween(w.Pop, 0.1, { Scale = 1.22 })
	if up then
		up.Completed:Once(function()
			Motion.Tween(w.Pop, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	-- A ring bursting out of it.
	if not Motion.Reduced() then
		local ring = circle(w.Holder, "Burst", w.Size, Theme.White, 14, {
			Position = UDim2.new(0.5, 0, 0, w.Size / 2 + 10),
			BackgroundTransparency = 1,
		})
		local stroke = Kit.Stroke(ring, branch.Color, 5, 0)
		Motion.Tween(ring, 0.45, { Size = UDim2.fromOffset(w.Size * 2, w.Size * 2) })
		Motion.Tween(stroke, 0.45, { Transparency = 1, Thickness = 1 })
		task.delay(0.5, function()
			ring:Destroy()
		end)
		-- Floating "LV n".
		local float = label(w.Holder, { Name = "LevelUp", Text = LF("LV %s", newLevel), Font = "numeric", TextSize = 18, AlignX = "Center",
			Color = C3(46, 160, 60), Stroke = 0.1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(90, 24), ZIndex = 17 })
		float.TextStrokeColor3 = Theme.White
		Motion.Tween(float, 0.7, { Position = UDim2.new(0.5, 0, 0, -26), TextTransparency = 1, TextStrokeTransparency = 1 })
		task.delay(0.75, function()
			float:Destroy()
		end)
	end
	-- The new pip.
	local pip = w.Pips[newLevel]
	if pip then
		local scale = pip:FindFirstChild("Pop") or New("UIScale", { Name = "Pop" }, pip)
		scale.Scale = 1.9
		Motion.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	ui.BuyPop.Scale = 0.94
	Motion.Tween(ui.BuyPop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

buy = function()
	local id = state.Selected
	if not id or state.Busy or not ui then
		return
	end
	local p = view()
	local level = Tree.Level(p, id)
	local ok, why = Tree.Check(p, id)
	if not ok then
		Kit.Toast(serverText(why), { Kind = "warn", NoTranslate = true })
		return
	end
	state.Busy = true
	ui.Buy:SetBusy(true)
	local success, result = Net.Request("TreeUpgrade", { Node = id, Level = level })
	state.Busy = false
	ui.Buy:SetBusy(false)
	if success then
		-- The reply's snapshot (published by Net) already holds the new level; keep it even if not.
		if Tree.Level(view(), id) <= level then
			local copy = table.clone(state.Upgrades)
			copy[id] = level + 1
			state.Upgrades = copy
		end
		readLive()
		refresh()
		celebrate(id, level + 1)
		local message = id == "Plot" and type(result) == "table" and result.Message and serverText(result.Message)
			or LF("%s → LV %s", L(Tree.Nodes[id].Name), level + 1)
		Kit.Toast(message, { Kind = "success", NoTranslate = true })
	else
		Kit.Toast(serverText(result), { Kind = "error", NoTranslate = true })
		refresh()
	end
end
Screen.Buy = function()
	buy()
end

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------
-- A node worth pointing at for a new visitor: the cheapest affordable one, else the cheapest unlocked.
local function suggestion(): string?
	local p = view()
	local best, bestRank, bestCost = nil, math.huge, math.huge
	for _, id in ipairs(Tree.Order) do
		local status = Tree.Status(p, id)
		local rank = STATUS_PRIORITY[status] or 9
		if rank <= 2 then
			local cost = Tree.Cost(id, Tree.Level(p, id))
			if rank < bestRank or (rank == bestRank and cost < bestCost) then
				best, bestRank, bestCost = id, rank, cost
			end
		end
	end
	return best
end

function Screen.Open(focus: string?)
	if not ui then
		build()
	end
	local win = ui.Window
	readSnapshot(Net.Cached())
	readLive()
	if focus ~= nil and not Tree.Nodes[focus] then
		focus = nil
	end
	local firstOpen = not state.Opened
	state.Opened = true
	win:Open()
	arrange(win:GetLayout())
	if focus then
		select(focus, false)
	elseif state.Side then
		select(state.LastSelected or (state.Loaded and suggestion()) or nil, false)
	else
		state.SheetOpen = false
		select(nil, false)
		ui.Panel.Visible = false
	end
	task.defer(function()
		if win.IsOpen then
			reveal(focus or (state.Side and state.Selected) or nil, false)
		end
	end)
	-- Fresh levels from the server (shared, cached fetch; no polling).
	task.spawn(function()
		local snapshot = Net.Snapshot(firstOpen and 0 or 2)
		if not win.IsOpen then
			return
		end
		if snapshot then
			readSnapshot(snapshot)
			readLive()
			if state.Side and not state.Selected and not focus then
				state.Selected = suggestion()
				select(state.Selected, false)
				reveal(state.Selected, true)
			end
			refresh()
		else
			ui.Status.Visible = true
			ui.Status.Text = L("Could not load your upgrades. Try again.")
		end
	end)
end

function Screen.Close()
	if ui and ui.Window.IsOpen then
		ui.Window:Close("close")
	end
end

function Screen.IsOpen(): boolean
	return ui ~= nil and ui.Window.IsOpen == true
end

-- For the emulation harness and debugging.
function Screen.Internals(): any
	return ui, state
end

return Screen
