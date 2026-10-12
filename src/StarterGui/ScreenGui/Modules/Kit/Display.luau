-- Kit.Pill / Badge / RarityTag / VariantTag / MutationTag, Kit.ProgressBar, Kit.StatRow,
-- Kit.Countdown, Kit.EmptyState and Kit.Now.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Format = require(script.Parent.Format)
local Lang = require(script.Parent.Lang)
local Button = require(script.Parent.Button)

local Display = {}

local function place(object: any, p: any)
	if p.Size then
		object.Size = p.Size
	end
	if p.Position then
		object.Position = p.Position
	end
	if p.AnchorPoint then
		object.AnchorPoint = p.AnchorPoint
	end
	if p.LayoutOrder then
		object.LayoutOrder = p.LayoutOrder
	end
end

-- Server clock in unix seconds, from the engine's synced clock (no polling).
function Display.Now(): number
	local ok, now = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(now) == "number" then
		return now
	end
	return os.time()
end

------------------------------------------------------------------------------------------------
-- Pill: a rounded label that grows with its text. Badge: the small red counter.
------------------------------------------------------------------------------------------------
local Pill = {}
Pill.__index = Pill
Display.PillClass = Pill

function Display.Pill(parent: Instance?, props: any): any
	local p: any = props or {}
	local self: any = setmetatable({}, Pill)
	local z = p.ZIndex or 1
	local height = p.Height or 22
	local frame = Base.New("Frame", {
		Name = p.Name or "KitPill",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundColor3 = p.Color or Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = z,
	})
	place(frame, p)
	if p.Size == nil then
		frame.Size = UDim2.fromOffset(0, height)
	end
	Base.Corner(frame, "pill")
	Base.Padding(frame, p.PadX or 8, 0, p.PadX or 8, 0)
	self.Instance = frame
	self.Gradient = Base.New("UIGradient", { Rotation = 90, Enabled = false }, frame)
	self.Label = Base.Text(frame, {
		Name = "Text",
		Text = p.Text or "",
		TextSize = p.TextSize or 13,
		AutoX = true,
		Size = UDim2.fromScale(0, 1),
		AlignX = "Center",
		Font = p.Font,
		ZIndex = z + 1,
		NoTranslate = p.NoTranslate,
	})
	self:Set(p.Text or "", p.Color or Theme.Accent, p.TextColor)
	if p.Gradient then
		self:SetGradient(p.Gradient[1], p.Gradient[2])
	end
	if parent then
		frame.Parent = parent
	end
	return self
end

function Pill.Set(self: any, text: string?, color: Color3?, textColor: Color3?)
	if text ~= nil then
		self.Label.Text = text
	end
	if color then
		self.Instance.BackgroundColor3 = color
		self.Gradient.Enabled = false
		self.Label.TextColor3 = textColor or Theme.OnColor(color)
		self.Label.TextStrokeColor3 = Theme.Colors.edge
		self.Label.TextStrokeTransparency = self.Label.TextColor3 == Theme.White and 0.35 or 1
	end
end

function Pill.SetGradient(self: any, top: Color3, bottom: Color3)
	self.Instance.BackgroundColor3 = Theme.White
	self.Gradient.Color = ColorSequence.new(top, bottom)
	self.Gradient.Enabled = true
	self.Label.TextColor3 = Theme.White
	self.Label.TextStrokeTransparency = 0.25
end

function Pill.SetVisible(self: any, visible: boolean)
	self.Instance.Visible = visible
end

function Pill.Destroy(self: any)
	self.Instance:Destroy()
end

function Display.Badge(parent: Instance?, props: any): any
	local p: any = table.clone(props or {})
	p.Name = p.Name or "KitBadge"
	p.Color = p.Color or Theme.Danger
	p.Height = p.Height or 20
	p.TextSize = p.TextSize or 12
	p.Font = p.Font or "numeric"
	p.PadX = p.PadX or 6
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	return Display.Pill(parent, p)
end

-- Rarity pill ("LEGENDARY") in the rarity colour (gradient for the top tiers).
function Display.RarityTag(parent: Instance?, rarity: string?, props: any): any
	local p: any = table.clone(props or {})
	p.Name = p.Name or "RarityTag"
	p.Text = Lang.Upper(rarity)
	p.Color = Theme.RarityColor(rarity)
	local tag = Display.Pill(parent, p)
	tag.SetRarity = function(self: any, value: string?)
		self:Set(Lang.Upper(value), Theme.RarityColor(value))
		local gradient = value and Theme.RarityGradient[value]
		if gradient then
			self:SetGradient(gradient[1], gradient[2])
		end
	end
	tag:SetRarity(rarity)
	return tag
end

-- Dog variant pill ("GOLDEN"); hidden for Normal unless ShowNormal.
function Display.VariantTag(parent: Instance?, variant: string?, props: any): any
	local p: any = table.clone(props or {})
	p.Name = p.Name or "VariantTag"
	local tag = Display.Pill(parent, p)
	tag.SetVariant = function(self: any, value: string?)
		self:Set(Lang.Upper(value or "Normal"), Theme.VariantColor(value))
		self.Instance.Visible = (value ~= nil and value ~= "" and value ~= "Normal") or p.ShowNormal == true
	end
	tag:SetVariant(variant)
	return tag
end

-- Item mutation pill ("RAINBOW"); hidden for NORMAL unless ShowNormal.
function Display.MutationTag(parent: Instance?, mutation: string?, props: any): any
	local p: any = table.clone(props or {})
	p.Name = p.Name or "MutationTag"
	local tag = Display.Pill(parent, p)
	tag.SetMutation = function(self: any, value: string?)
		local name = string.upper(value or "NORMAL")
		self:Set(name, Theme.MutationColor(name))
		self.Instance.Visible = name ~= "NORMAL" or p.ShowNormal == true
	end
	tag:SetMutation(mutation)
	return tag
end

------------------------------------------------------------------------------------------------
-- ProgressBar
------------------------------------------------------------------------------------------------
local ProgressBar = {}
ProgressBar.__index = ProgressBar

function Display.ProgressBar(parent: Instance?, props: any): any
	local p: any = props or {}
	local self: any = setmetatable({}, ProgressBar)
	local z = p.ZIndex or 1
	local track = Base.New("Frame", {
		Name = p.Name or "KitProgress",
		BackgroundColor3 = p.Track or Theme.Colors.secondary,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, p.Height or 18),
		ZIndex = z,
	})
	place(track, p)
	Base.Corner(track, "pill")
	Base.Stroke(track, Theme.Colors.edge, 2, 0.35)
	self.Instance = track
	self.Fill = Base.New("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = z + 1,
	}, track)
	Base.Corner(self.Fill, "pill")
	self.Gradient = Base.New("UIGradient", { Rotation = 90 }, self.Fill)
	self.Label = Base.Text(track, {
		Name = "Text",
		Text = p.Text or "",
		TextSize = p.TextSize or 13,
		AlignX = "Center",
		Color = Theme.White,
		Stroke = 0.1,
		Font = "numeric",
		ZIndex = z + 2,
		NoTranslate = p.NoTranslate,
	})
	self:SetColor(p.Color or Theme.Success)
	self.Value = 0
	self:SetValue(p.Value or 0, true)
	if parent then
		track.Parent = parent
	end
	return self
end

function ProgressBar.SetColor(self: any, color: Color3)
	self.Gradient.Color = ColorSequence.new(color:Lerp(Theme.White, 0.25), color)
end

-- 0..1; animates unless instant.
function ProgressBar.SetValue(self: any, value: number, instant: boolean?)
	local v = math.clamp(tonumber(value) or 0, 0, 1)
	self.Value = v
	local goal = { Size = UDim2.fromScale(v, 1) }
	self.Fill.Visible = v > 0
	if instant then
		self.Fill.Size = goal.Size
	else
		Motion.Tween(self.Fill, Theme.Motion.Fill, goal)
	end
end

function ProgressBar.SetText(self: any, text: string)
	self.Label.Text = text
end

function ProgressBar.Destroy(self: any)
	self.Instance:Destroy()
end

------------------------------------------------------------------------------------------------
-- StatRow: "DIG SPEED      12 → 15 (+3)", the next value coloured by whether it is better.
------------------------------------------------------------------------------------------------
local StatRow = {}
StatRow.__index = StatRow

function Display.StatRow(parent: Instance?, props: any): any
	local p: any = props or {}
	local self: any = setmetatable({}, StatRow)
	self.Props = p
	self.Formatter = Format.Resolve(p.Format, Lang.Get())
	local z = p.ZIndex or 1
	local textSize = p.TextSize or 16
	local row = Base.New("Frame", {
		Name = p.Name or "KitStat",
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = p.Background == false and 1 or 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, p.Height or 32),
		ZIndex = z,
	})
	place(row, p)
	Base.Corner(row, Theme.Radius.Small)
	self.Instance = row
	local x = 10
	if p.Icon then
		Base.Icon(row, p.Icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = z + 1,
		})
		x = 34
	end
	self.Label = Base.Text(row, {
		Name = "Label",
		Text = p.Label or "",
		TextSize = textSize - 1,
		Color = Theme.InkMuted,
		Scaled = true,
		MinTextSize = 9,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(0.5, -x, 1, 0),
		ZIndex = z + 1,
		NoTranslate = p.NoTranslate,
	})
	self.Value = Base.Text(row, {
		Name = "Value",
		TextSize = textSize,
		Font = "numeric",
		Rich = true,
		Scaled = true,
		MinTextSize = 9,
		AlignX = "Right",
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.5, -10, 1, 0),
		ZIndex = z + 1,
		NoTranslate = true,
	})
	self:Set(p.Value, p.Next)
	if parent then
		row.Parent = parent
	end
	return self
end

-- Current value and the optional next value (an upgrade preview).
function StatRow.Set(self: any, value: any, nextValue: any)
	self.Current, self.NextValue = value, nextValue
	local fmt = self.Formatter
	local text = fmt(value)
	if nextValue ~= nil and type(value) == "number" and type(nextValue) == "number" then
		local delta, _, better = Format.Delta(value, nextValue, self.Props.HigherIsBetter)
		if delta ~= 0 then
			local color = Theme.Hex(better and Color3.fromRGB(74, 170, 22) or Theme.Danger)
			local sign = delta > 0 and "+" or "-"
			text = string.format(
				'%s  <font color="%s">→ %s</font>  <font color="%s" size="%d">(%s%s)</font>',
				text,
				color,
				fmt(nextValue),
				color,
				math.max(9, (self.Props.TextSize or 16) - 3),
				sign,
				fmt(math.abs(delta))
			)
		end
	elseif nextValue ~= nil then
		text = text .. "  → " .. fmt(nextValue)
	end
	self.Value.Text = text
end

function StatRow.SetLabel(self: any, label: string)
	self.Label.Text = label
end

function StatRow.Destroy(self: any)
	self.Instance:Destroy()
end

------------------------------------------------------------------------------------------------
-- Countdown: a label counting down to EndsAt (server unix seconds). One shared 1 Hz ticker runs
-- only while countdowns exist.
------------------------------------------------------------------------------------------------
local Countdown = {}
Countdown.__index = Countdown
local active: { [any]: boolean } = {}
local ticking = false

local function tickAll()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		while next(active) do
			local now = Display.Now()
			for countdown in pairs(active) do
				local ok, err = pcall(countdown._render, countdown, now)
				if not ok then
					active[countdown] = nil
					warn("Kit.Countdown: " .. tostring(err))
				end
			end
			-- Wake just after the next whole second so every label flips together.
			task.wait(math.max(0.05, 1 - (Display.Now() % 1) + 0.02))
		end
		ticking = false
	end)
end

function Display.Countdown(parent: Instance?, props: any): any
	local p: any = props or {}
	local self: any = setmetatable({}, Countdown)
	self.Props = p
	self.Maid = Maid.new()
	local label = Base.Text(nil, {
		Name = p.Name or "KitCountdown",
		TextSize = p.TextSize or 16,
		Color = p.Color or Theme.Ink,
		AlignX = p.AlignX or "Left",
		Font = p.Font or "numeric",
		Scaled = p.Scaled,
		Size = p.Size or UDim2.new(1, 0, 0, 24),
		Position = p.Position,
		AnchorPoint = p.AnchorPoint,
		ZIndex = p.ZIndex,
		LayoutOrder = p.LayoutOrder,
		NoTranslate = true, -- self-localized (units via Kit.Lang), changes every second
	})
	self.Instance = label
	self.Maid:Give(label)
	self.Maid:Give(label.Destroying:Connect(function()
		active[self] = nil
	end))
	self:SetEndsAt(p.EndsAt)
	if parent then
		label.Parent = parent
	end
	return self
end

function Countdown._render(self: any, now: number)
	local p = self.Props
	local left = (self.EndsAt or 0) - now
	local text
	if left <= 0 then
		active[self] = nil
		text = p.DoneText or Lang.T("READY", "ГОТОВО")
		if not self.Done then
			self.Done = true
			if p.OnDone then
				task.spawn(p.OnDone)
			end
		end
	else
		local seconds = math.ceil(left)
		local body = p.Style == "duration" and Format.Duration(seconds, Lang.Get()) or Format.Clock(seconds, Lang.Get())
		text = (p.Prefix or "") .. body
	end
	if self.Instance.Text ~= text then
		self.Instance.Text = text
	end
end

-- New end time (server unix seconds); nil shows DoneText.
function Countdown.SetEndsAt(self: any, endsAt: number?)
	self.EndsAt = endsAt
	self.Done = false
	self:_render(Display.Now())
	if endsAt and endsAt > Display.Now() then
		active[self] = true
		tickAll()
	end
end

function Countdown.Destroy(self: any)
	active[self] = nil
	self.Maid:Clean()
end

-- Number of running countdowns (tests).
function Display.ActiveCountdowns(): number
	local n = 0
	for _ in pairs(active) do
		n += 1
	end
	return n
end

------------------------------------------------------------------------------------------------
-- EmptyState: icon, title, body and an optional action button, centred.
------------------------------------------------------------------------------------------------
local EmptyState = {}
EmptyState.__index = EmptyState

function Display.EmptyState(parent: Instance?, props: any): any
	local p: any = props or {}
	local self: any = setmetatable({}, EmptyState)
	self.Maid = Maid.new()
	local z = p.ZIndex or 1
	local root = Base.New("Frame", {
		Name = p.Name or "KitEmpty",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 230),
		ZIndex = z,
	})
	place(root, p)
	self.Instance = root
	self.Maid:Give(root)
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, root)
	local circle = Base.New("Frame", {
		Name = "IconCircle",
		BackgroundColor3 = Theme.Colors.secondary,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(76, 76),
		LayoutOrder = 1,
		ZIndex = z + 1,
	}, root)
	Base.Corner(circle, "pill")
	self.Icon = Base.Icon(circle, p.Icon or "Star", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(52, 52),
		Color = p.Icon and Theme.White or Theme.InkMuted,
		ZIndex = z + 2,
	})
	self.Title = Base.Text(root, {
		Name = "Title",
		Text = p.Title or Lang.Word("NOTHING"),
		TextSize = p.TitleSize or 21,
		AlignX = "Center",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		ZIndex = z + 1,
		NoTranslate = p.NoTranslate,
	})
	self.Body = Base.Text(root, {
		Name = "Body",
		Text = p.Body or "",
		TextSize = 15,
		Color = Theme.InkMuted,
		AlignX = "Center",
		Wrap = true,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 3,
		ZIndex = z + 1,
		NoTranslate = p.NoTranslate,
	})
	Base.New("UISizeConstraint", { MaxSize = Vector2.new(380, math.huge) }, self.Body)
	self.Body.Visible = (p.Body or "") ~= ""
	if p.ActionText then
		self.Action = Button.new(root, {
			Name = "Action",
			Text = p.ActionText,
			Style = p.ActionStyle or "success",
			Size = UDim2.fromOffset(220, 44),
			LayoutOrder = 4,
			ZIndex = z + 1,
			OnClick = p.OnAction,
		})
		self.Maid:Give(self.Action)
	end
	if parent then
		root.Parent = parent
	end
	return self
end

function EmptyState.Set(self: any, props: any)
	if props.Title then
		self.Title.Text = props.Title
	end
	if props.Body then
		self.Body.Text = props.Body
		self.Body.Visible = props.Body ~= ""
	end
	if props.ActionText and self.Action then
		self.Action:SetText(props.ActionText)
	end
end

function EmptyState.SetVisible(self: any, visible: boolean)
	self.Instance.Visible = visible
end

function EmptyState.Destroy(self: any)
	self.Maid:Clean()
end

return Display
