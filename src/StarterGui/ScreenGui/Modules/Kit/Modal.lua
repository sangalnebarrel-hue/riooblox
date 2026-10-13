-- Kit.Modal / Kit.Confirm / Kit.Alert: a blocking dialog above kit windows with a title, body,
-- an optional list of cards (what will be spent / destroyed), custom content and two buttons.
-- Danger dialogs use hold-to-confirm (1 s by default). Returns a promise-like object:
--   local result = Kit.Confirm("RELEASE 3 DOGS?", "They leave forever.", {Danger = true})
--   result:Then(function(ok) ... end)      -- or: local ok = result:Await()
-- Cancel, the backdrop, Escape / gamepad B, or the owning window closing resolve false.
local TextService = game:GetService("TextService")
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Lang = require(script.Parent.Lang)
local Overlay = require(script.Parent.Overlay)
local Layout = require(script.Parent.Layout)
local Button = require(script.Parent.Button)
local Cards = require(script.Parent.Cards)
local Virtual = require(script.Parent.Virtual)
local Sound = require(script.Parent.Sound)

local Modal = {}
Modal.__index = Modal

local open: { any } = {}

export type Props = {
	Title: string?,
	Body: string?,
	Cards: { any }?, -- card data list (Kit card data), shown as compact rows
	CardKind: string?, -- "Dog" (default) | "Item"
	Content: ((frame: Frame, width: number) -> ())?, -- custom content builder
	ContentHeight: number?,
	ConfirmText: string?,
	CancelText: string?,
	Danger: boolean?,
	Hold: number?, -- hold seconds for the confirm button (default 1 when Danger; 0 = none)
	ConfirmStyle: string?,
	NoCancel: boolean?, -- one OK button (Kit.Alert)
	Accent: Color3?,
	Width: number?,
	NoTranslate: boolean?, -- Title/Body are self-localized
}

local function measure(text: string, size: number, width: number): number
	if text == "" then
		return 0
	end
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(width, 10000))
	end)
	if ok and bounds then
		return math.ceil(bounds.Y) + 4
	end
	return size * 2
end

function Modal.new(props: Props): any
	local p: any = props or {}
	local self: any = setmetatable({}, Modal)
	self.Maid = Maid.new()
	self.Done = false
	self.Callbacks = {}
	self.Props = p
	local danger = p.Danger == true
	local hold = p.Hold
	if hold == nil then
		hold = danger and 1 or 0
	end
	local accent = p.Accent or (danger and Theme.Danger or Theme.Accent)
	local gui = Overlay.Modals()
	local depth = #open + 1
	table.insert(open, self)

	local root = Base.New("Frame", {
		Name = "KitModal",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = depth * 10,
	}, gui)
	self.Instance = root
	self.Maid:Give(root)
	local shade = Base.New("TextButton", {
		Name = "Shade",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = depth * 10,
	}, root)
	self.Maid:Give(shade.Activated:Connect(function()
		self:Resolve(p.NoCancel == true)
	end))

	-- Size: width from the screen, height from the measured content.
	local sx, sy, sw, sh = Base.SafeArea(gui)
	local info = Layout.Classify(sw, sh)
	local w = math.floor(math.min(p.Width or 520, sw - 24))
	local pad = info.Phone and 14 or 18
	local innerW = w - pad * 2
	local titleH = 34
	local body = p.Body or ""
	local bodyH = math.min(measure(body, 17, innerW), 180)
	local rowH = 64
	local cards = p.Cards or {}
	local listH = #cards > 0 and math.min(#cards * (rowH + 6) + 6, rowH * 3 + 30) or 0
	local contentH = p.Content and (p.ContentHeight or 120) or 0
	local hintH = hold > 0 and 20 or 0
	local buttonsH = 48
	local function total()
		local h = pad + titleH + 6
		if bodyH > 0 then
			h += bodyH + 8
		end
		if listH > 0 then
			h += listH + 8
		end
		if contentH > 0 then
			h += contentH + 8
		end
		return h + hintH + buttonsH + pad
	end
	local maxH = sh - 24
	if total() > maxH and listH > 0 then
		listH = math.max(rowH + 12, listH - (total() - maxH))
	end
	if total() > maxH and bodyH > 0 then
		bodyH = math.max(40, bodyH - (total() - maxH))
	end
	local h = math.min(total(), maxH)

	local card = Base.New("Frame", {
		Name = "Dialog",
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = depth * 10 + 1,
	}, root)
	self.Dialog = card
	Base.PlaceCentered(card, sx + (sw - w) / 2, sy + (sh - h) / 2, w, h)
	Base.Corner(card, Theme.Radius.Window)
	Base.Stroke(card, Theme.Colors.edge, Theme.StrokeWidth.Window)
	local scale = Base.New("UIScale", { Name = "KitMotion" }, card)
	local z = depth * 10 + 2
	local bar = Base.New("Frame", {
		Name = "AccentBar",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(pad, 10),
		Size = UDim2.new(0, 46, 0, 5),
		ZIndex = z,
	}, card)
	Base.Corner(bar, "pill")
	local y = pad + 2
	self.Title = Base.Text(card, {
		Name = "Title",
		Text = p.Title or "",
		TextSize = info.Phone and 21 or 24,
		Scaled = true,
		MinTextSize = 14,
		Color = danger and Theme.Darken(Theme.Danger, 0.15) or Theme.Ink,
		Position = UDim2.fromOffset(pad, y),
		Size = UDim2.fromOffset(innerW, titleH),
		ZIndex = z,
		NoTranslate = p.NoTranslate,
	})
	y += titleH + 6
	if bodyH > 0 then
		local holder = Base.New("ScrollingFrame", {
			Name = "BodyScroll",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(pad, y),
			Size = UDim2.fromOffset(innerW, bodyH),
			CanvasSize = UDim2.fromOffset(0, measure(body, 17, innerW - 8)),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = accent,
			ZIndex = z,
		}, card)
		self.Body = Base.Text(holder, {
			Name = "Body",
			Text = body,
			TextSize = 17,
			Color = Theme.InkMuted,
			Wrap = true,
			AlignY = "Top",
			Size = UDim2.new(1, -8, 1, 0),
			ZIndex = z,
			NoTranslate = p.NoTranslate,
		})
		self.Body.Size = UDim2.new(1, -8, 0, measure(body, 17, innerW - 8))
		y += bodyH + 8
	end
	if listH > 0 then
		local listFrame = Base.New("Frame", {
			Name = "CardList",
			BackgroundColor3 = Theme.SurfaceAlt,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(pad, y),
			Size = UDim2.fromOffset(innerW, listH),
			ZIndex = z,
		}, card)
		Base.Corner(listFrame, Theme.Radius.Field)
		local kind = p.CardKind or "Dog"
		local list = Virtual.List(listFrame, {
			Name = "Cards",
			RowHeight = rowH,
			Padding = 6,
			ZIndex = z,
			Create = function(frame)
				return Cards.new(frame, kind)
			end,
			Bind = function(cell, data)
				cell:Bind(data)
			end,
			Layout = function(cell, cw, ch)
				cell:Layout(cw, ch)
			end,
			Destroy = function(cell)
				cell:Destroy()
			end,
		})
		self.List = list
		self.Maid:Give(list)
		list:SetItems(cards)
		y += listH + 8
	end
	if contentH > 0 then
		local content = Base.New("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(pad, y),
			Size = UDim2.fromOffset(innerW, contentH),
			ZIndex = z,
		}, card)
		self.Content = content
		local ok, err = pcall(p.Content, content, innerW)
		if not ok then
			warn("Kit.Modal content: " .. tostring(err))
		end
		y += contentH + 8
	end
	if hintH > 0 then
		self.Hint = Base.Text(card, {
			Name = "Hint",
			Text = Lang.Word("HOLD"),
			TextSize = 13,
			Color = accent,
			AlignX = "Right",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, pad, 1, -(pad + buttonsH + 2)),
			Size = UDim2.fromOffset(innerW, 18),
			ZIndex = z,
		})
	end
	local buttonY = UDim2.new(0, pad, 1, -(pad + buttonsH))
	local half = math.floor((innerW - 10) / 2)
	if not p.NoCancel then
		self.CancelButton = Button.new(card, {
			Name = "Cancel",
			Text = p.CancelText or Lang.Word("CANCEL"),
			Style = "secondary",
			Position = buttonY,
			Size = UDim2.fromOffset(half, buttonsH),
			ZIndex = z,
			OnClick = function()
				self:Resolve(false)
			end,
		})
		self.CancelButton.Instance:SetAttribute("KitSound", "") -- Resolve plays the cue
		self.Maid:Give(self.CancelButton)
	end
	self.ConfirmButton = Button.new(card, {
		Name = "Confirm",
		Text = p.ConfirmText or (p.NoCancel and Lang.Word("OK") or Lang.Word("CONFIRM")),
		Style = p.ConfirmStyle or (danger and "danger" or "success"),
		Position = p.NoCancel and buttonY or UDim2.new(0, pad + half + 10, 1, -(pad + buttonsH)),
		Size = UDim2.fromOffset(p.NoCancel and innerW or half, buttonsH),
		Hold = hold > 0 and hold or nil,
		ZIndex = z,
		OnClick = function()
			self:Resolve(true)
		end,
	})
	self.ConfirmButton.Instance:SetAttribute("KitSound", "")
	self.Maid:Give(self.ConfirmButton)

	self.Entry = Overlay.Push({
		Kind = "modal",
		Dismiss = function()
			self:Resolve(p.NoCancel == true)
		end,
	})

	-- Open: shade fade + scale.
	Sound.Play(p.NoCancel and "Notify" or "Open", { Pitch = 1.1 })
	if Motion.Reduced() then
		shade.BackgroundTransparency = 0.4
	else
		scale.Scale = 0.9
		Motion.Tween(shade, Theme.Motion.Open, { BackgroundTransparency = 0.4 })
		Motion.Tween(scale, Theme.Motion.Open, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	self.Shade, self.Scale = shade, scale
	-- Screen rotation / window resize: keep the dialog centred inside the safe area.
	self.Maid:Give(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local nx, ny, nw, nh = Base.SafeArea(gui)
		local fw, fh = math.min(w, nw - 24), math.min(h, nh - 24)
		Base.PlaceCentered(card, nx + (nw - fw) / 2, ny + (nh - fh) / 2, fw, fh)
	end))
	Base.GamepadFocus((self.CancelButton or self.ConfirmButton).Instance)
	return self
end

-- Resolves once (true = confirmed) and closes the dialog.
function Modal.Resolve(self: any, value: boolean)
	if self.Done then
		return
	end
	self.Done = true
	self.Result = value == true
	Sound.Play(self.Result and "Toggle" or "Close")
	Overlay.Remove(self.Entry)
	local index = table.find(open, self)
	if index then
		table.remove(open, index)
	end
	for _, callback in ipairs(self.Callbacks) do
		task.spawn(callback, self.Result)
	end
	table.clear(self.Callbacks)
	local t = Theme.Motion.Close
	self.Instance.Active = false
	Motion.Tween(self.Shade, t, { BackgroundTransparency = 1 })
	Motion.Tween(self.Scale, t, { Scale = 0.94 })
	task.delay(Motion.Reduced() and 0 or t, function()
		self.Maid:Clean()
	end)
end

function Modal.Cancel(self: any)
	self:Resolve(false)
end

-- Calls fn(confirmed) once the dialog is resolved (immediately if it already is).
function Modal.Then(self: any, fn: (boolean) -> ()): any
	if self.Done then
		task.spawn(fn, self.Result)
	else
		table.insert(self.Callbacks, fn)
	end
	return self
end

-- Yields until resolved; returns true when confirmed.
function Modal.Await(self: any): boolean
	if self.Done then
		return self.Result
	end
	local thread = coroutine.running()
	table.insert(self.Callbacks, function(result)
		task.spawn(thread, result)
	end)
	return coroutine.yield()
end

function Modal.Count(): number
	return #open
end

-- Shorthands.
function Modal.Confirm(title: string, body: string?, opts: any?): any
	local p: any = table.clone(opts or {})
	p.Title, p.Body = title, body
	return Modal.new(p)
end

function Modal.Alert(title: string, body: string?, opts: any?): any
	local p: any = table.clone(opts or {})
	p.Title, p.Body, p.NoCancel = title, body, true
	return Modal.new(p)
end

return Modal
