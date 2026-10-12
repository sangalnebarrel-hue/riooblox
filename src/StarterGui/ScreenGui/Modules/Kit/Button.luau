-- Kit.Button: primary / secondary / danger / ghost / success / gold buttons with hover and press
-- tweens, disabled and busy states, an optional icon and price, and hold-to-confirm.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Format = require(script.Parent.Format)

local Button = {}
Button.__index = Button

export type Props = {
	Text: string?,
	Style: string?, -- "primary" (default) | "secondary" | "danger" | "ghost" | "success" | "gold"
	Color: Color3?, -- overrides the style background
	Icon: string?, -- icon key or asset id (left of the text)
	Price: number?, -- shown with PriceIcon on the right (Format.Short)
	PriceIcon: string?, -- default "Coins"
	PriceText: string?, -- shown instead of a number ("FREE", "R$ 99")
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	OnClick: (() -> ())?,
	Disabled: boolean?,
	Hold: number?, -- seconds the press must be held before OnClick (hold-to-confirm)
	TextSize: number?,
	Name: string?,
	LayoutOrder: number?,
	ZIndex: number?,
	NoTranslate: boolean?,
}

-- Inputs that hold a hold-to-confirm button: mouse, touch, gamepad A, Enter / Space.
local function isHoldInput(input: InputObject): boolean
	local kind, key = input.UserInputType, input.KeyCode
	return kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.Touch
		or key == Enum.KeyCode.ButtonA
		or key == Enum.KeyCode.Return
		or key == Enum.KeyCode.Space
end

function Button.new(parent: Instance?, props: Props?): any
	local p: any = props or {}
	local self: any = setmetatable({}, Button)
	self.Maid = Maid.new()
	self.Props = p
	self.Disabled = p.Disabled == true
	self.Busy = false
	self.Style = p.Style or "primary"
	self.OnClick = p.OnClick
	local z = p.ZIndex or 1
	self.Z = z

	local root = Base.New("TextButton", {
		Name = p.Name or "KitButton",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = p.Size or UDim2.fromOffset(170, 46),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = z,
	})
	self.Instance = root
	self.Maid:Give(root)
	local face = Base.Face(root, Theme.White, Theme.Radius.Button, z)
	self.Face = face
	self.StrokeObject = Base.Stroke(face, Theme.Colors.edge, Theme.StrokeWidth.Button)
	self.Gradient = Base.New("UIGradient", { Rotation = 90 }, face)

	-- Hold-to-confirm progress fill (under the content).
	self.Fill = Base.New("Frame", {
		Name = "HoldFill",
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		ZIndex = z + 1,
	}, root)
	Base.Corner(self.Fill, Theme.Radius.Button)

	-- Content row: [icon][caption (fills)][price]. UIFlexItem lets the caption take the rest.
	local content = Base.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
	}, root)
	self.Content = content
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, content)
	Base.Padding(content, 10, 3, 10, 3)

	self.IconHolder = Base.New("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.62, 0.62),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		LayoutOrder = 1,
		Visible = false,
		ZIndex = z + 3,
	}, content)

	self.Caption = Base.Text(content, {
		Name = "Caption",
		Text = p.Text or "",
		TextSize = p.TextSize or Theme.TextSize.Button,
		Scaled = true,
		MinTextSize = 10,
		AlignX = "Center",
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		ZIndex = z + 3,
		NoTranslate = p.NoTranslate,
	})
	Base.New("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, self.Caption)

	local price = Base.New("Frame", {
		Name = "Price",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 0.8),
		LayoutOrder = 3,
		Visible = false,
		ZIndex = z + 3,
	}, content)
	self.PriceFrame = price
	Base.Corner(price, Theme.Radius.Small)
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, price)
	Base.Padding(price, 6, 0, 8, 0)
	self.PriceIcon = Base.Icon(price, p.PriceIcon or "Coins", {
		Size = UDim2.fromScale(0.85, 0.85),
		ZIndex = z + 4,
		Glyph = "$",
	})
	self.PriceIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	self.PriceIcon.LayoutOrder = 1
	self.PriceLabel = Base.Text(price, {
		Name = "Amount",
		Font = "numeric",
		TextSize = (p.TextSize or Theme.TextSize.Button) - 1,
		AutoX = true,
		Size = UDim2.fromScale(0, 1),
		AlignX = "Center",
		LayoutOrder = 2,
		ZIndex = z + 4,
		NoTranslate = true,
	})

	-- Busy indicator: three pulsing dots over the content.
	local dots = Base.New("Frame", {
		Name = "Busy",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(46, 12),
		Visible = false,
		ZIndex = z + 5,
	}, root)
	self.Dots = dots
	self.DotFrames = {}
	for i = 1, 3 do
		local dot = Base.New("Frame", {
			Name = "Dot" .. i,
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset((i - 1) * 17, 0),
			Size = UDim2.fromOffset(12, 12),
			ZIndex = z + 5,
		}, dots)
		Base.Corner(dot, "pill")
		table.insert(self.DotFrames, dot)
	end
	self.DotTweens = {}

	Base.Press(root, nil, self.Maid)
	self.Maid:Give(root.Activated:Connect(function()
		if self.Props.Hold and self.Props.Hold > 0 then
			return -- hold buttons fire from the hold timer only
		end
		self:_fire()
	end))
	self:_wireHold()

	self:SetIcon(p.Icon)
	if p.PriceText then
		self:SetPrice(p.PriceText)
	elseif p.Price then
		self:SetPrice(p.Price)
	end
	self:_paint()
	if parent then
		root.Parent = parent
	end
	return self
end

function Button._fire(self: any)
	if self.Disabled or self.Busy or not self.OnClick then
		return
	end
	task.spawn(self.OnClick)
end

function Button._wireHold(self: any)
	local root = self.Instance
	local holding: any = nil
	local function stop()
		if not holding then
			return
		end
		local tween = holding.Tween
		holding = nil
		if tween then
			tween:Cancel()
		end
		Motion.Tween(self.Fill, Theme.Motion.Fast, { Size = UDim2.fromScale(0, 1) })
		task.delay(Theme.Motion.Fast, function()
			if not holding then
				self.Fill.Visible = false
			end
		end)
	end
	local function start()
		local seconds = self.Props.Hold
		if not seconds or seconds <= 0 or self.Disabled or self.Busy or holding then
			return
		end
		local token = {}
		holding = token
		self.Fill.Visible = true
		self.Fill.Size = UDim2.fromScale(0, 1)
		-- The fill is the timer: it runs even with reduced motion (a safety delay, not decoration).
		local tween = game:GetService("TweenService"):Create(
			self.Fill,
			TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		token.Tween = tween
		tween.Completed:Connect(function(state)
			if holding ~= token or state ~= Enum.PlaybackState.Completed then
				return
			end
			holding = nil
			self.Fill.Visible = false
			self.Fill.Size = UDim2.fromScale(0, 1)
			self:_fire()
		end)
		tween:Play()
	end
	self.Maid:Give(root.InputBegan:Connect(function(input)
		if isHoldInput(input) then
			start()
		end
	end))
	self.Maid:Give(root.InputEnded:Connect(function(input)
		if isHoldInput(input) then
			stop()
		end
	end))
	self.Maid:Give(root.MouseLeave:Connect(stop))
	self.Maid:Give(root.SelectionLost:Connect(stop))
	self.StopHold = stop
end

function Button._paint(self: any)
	local style = Theme.Buttons[self.Style] or Theme.Buttons.primary
	local root = self.Instance
	local base = self.Props.Color or style.Bg
	local enabled = not self.Disabled
	local tone = enabled and base or base:Lerp(Theme.Disabled, 0.7)
	local transparent = style.Transparent and enabled
	self.Face.BackgroundTransparency = transparent and 1 or 0
	self.Face.BackgroundColor3 = Theme.White
	self.Gradient.Color = ColorSequence.new(tone:Lerp(Theme.White, 0.12), tone)
	self.Gradient.Enabled = not transparent
	local textColor = style.Text
	if self.Props.Color and not style.Transparent then
		textColor = Theme.OnColor(self.Props.Color)
	end
	self.Caption.TextColor3 = textColor
	self.Caption.TextTransparency = enabled and 0 or 0.35
	-- White captions get the navy outline of the game's buttons.
	self.Caption.TextStrokeColor3 = Theme.Colors.edge
	self.Caption.TextStrokeTransparency = (textColor == Theme.White and enabled) and 0.15 or 1
	self.PriceLabel.TextColor3 = textColor
	self.PriceLabel.TextStrokeColor3 = Theme.Colors.edge
	self.PriceLabel.TextStrokeTransparency = textColor == Theme.White and 0.3 or 1
	self.PriceFrame.BackgroundColor3 = Theme.Colors.edge
	self.PriceFrame.BackgroundTransparency = (textColor == Theme.White) and 0.8 or 0.9
	self.StrokeObject.Enabled = style.Stroke ~= nil
	self.StrokeObject.Color = enabled and (style.Stroke or Theme.Colors.edge) or Color3.fromRGB(99, 116, 144)
	for _, dot in ipairs(self.DotFrames) do
		dot.BackgroundColor3 = textColor
	end
	root.Active = enabled and not self.Busy
	root.Selectable = enabled
	root:SetAttribute("KitDisabled", not enabled)
end

function Button.SetText(self: any, text: string)
	self.Caption.Text = text
end

function Button.SetStyle(self: any, style: string, color: Color3?)
	self.Style = style
	self.Props.Color = color
	self:_paint()
end

function Button.SetDisabled(self: any, disabled: boolean)
	self.Disabled = disabled == true
	if self.Disabled and self.StopHold then
		self.StopHold()
	end
	self:_paint()
end

function Button.SetOnClick(self: any, fn: (() -> ())?)
	self.OnClick = fn
end

-- Busy: shows pulsing dots, blocks clicks (a request is in flight).
function Button.SetBusy(self: any, busy: boolean)
	busy = busy == true
	if self.Busy == busy then
		return
	end
	self.Busy = busy
	self.Content.Visible = not busy
	self.Dots.Visible = busy
	for _, tween in ipairs(self.DotTweens) do
		tween:Cancel()
	end
	table.clear(self.DotTweens)
	if busy then
		if self.StopHold then
			self.StopHold()
		end
		for i, dot in ipairs(self.DotFrames) do
			dot.BackgroundTransparency = 0
			local tween = Motion.Loop(dot, 0.4, { BackgroundTransparency = 0.75 }, (i - 1) * 0.13)
			if tween then
				table.insert(self.DotTweens, tween)
			end
		end
	end
	self:_paint()
end

-- Icon key / asset (nil hides it).
function Button.SetIcon(self: any, key: string?)
	for _, child in ipairs(self.IconHolder:GetChildren()) do
		child:Destroy()
	end
	self.IconHolder.Visible = key ~= nil
	if key then
		Base.Icon(self.IconHolder, key, { Size = UDim2.fromScale(1, 1), ZIndex = self.Z + 3 })
	end
end

-- A number (formatted with Format.Short) or a ready string; nil hides the price.
function Button.SetPrice(self: any, price: any)
	if price == nil then
		self.PriceFrame.Visible = false
		return
	end
	self.PriceFrame.Visible = true
	if type(price) == "number" then
		self.PriceIcon.Visible = true
		self.PriceLabel.Text = Format.Short(price, 1)
	else
		self.PriceIcon.Visible = false
		self.PriceLabel.Text = tostring(price)
	end
end

function Button.Destroy(self: any)
	for _, tween in ipairs(self.DotTweens) do
		tween:Cancel()
	end
	self.Maid:Clean()
end

return Button
