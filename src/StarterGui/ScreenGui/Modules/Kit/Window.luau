-- Kit.Window: a persistent screen window (build its content once, update it in place; never
-- rebuilt by a poll). Own ScreenGui layer, dim backdrop, header (title, subtitle, accent, icon,
-- close X), optional tab bar, body. Desktop: a centred card sized from the viewport. Phone: a
-- full-screen sheet inside the safe area. Open / close: backdrop fade + card scale and fade in
-- ~0.18 s (instant with ReducedMotion).
-- Navigation: the base window takes GUIIntegration navigation (N.Acquire('Kit', Key)) and gives
-- it back on close; when navigation moves elsewhere the kit windows close. Only one kit window
-- is open at a time; Stack = true opens a window over the current one (closing it returns to the
-- one below).
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Layout = require(script.Parent.Layout)
local Motion = require(script.Parent.Motion)
local Maid = require(script.Parent.Maid)
local Signal = require(script.Parent.Signal)
local Overlay = require(script.Parent.Overlay)
local Nav = require(script.Parent.Nav)
local Button = require(script.Parent.Button)
local Controls = require(script.Parent.Controls)
local Sound = require(script.Parent.Sound)

local Window = {}
Window.__index = Window

local stack: { any } = {} -- open windows, bottom first

export type Props = {
	Key: string?, -- navigation key (OpenMenu value); default Title
	Title: string?,
	Subtitle: string?,
	Accent: Color3?, -- header colour (UITheme.WindowSpecs colours fit)
	Icon: string?, -- icon key (Theme.Icons / GameIcons) or asset id
	Tabs: { any }?, -- {{Id, Text, Badge?}}
	Tab: string?, -- initially selected tab
	OnTab: ((id: string) -> ())?,
	MaxSize: Vector2?, -- desktop card limit (default 1040 x 760)
	Stack: boolean?, -- open over the current kit window instead of replacing it
	NoNavigation: boolean?, -- do not touch GUIIntegration (tools, tests)
	OnOpen: ((window: any) -> ())?,
	OnClose: ((window: any, reason: string) -> ())?,
	Name: string?,
	NoTranslate: boolean?, -- Title/Subtitle are self-localized
}

local function closeTop(allowBase: boolean): boolean
	local top = stack[#stack]
	if not top then
		return false
	end
	if not allowBase and #stack == 1 and top.NavKey then
		return false -- GUIIntegration closes the base window through N.Close
	end
	top:Close("escape")
	return true
end
Nav.CloseTop = closeTop

function Window.new(props: Props): any
	local p: any = props or {}
	local self: any = setmetatable({}, Window)
	self.Props = p
	self.Key = p.Key or p.Title or "KitWindow"
	self.Maid = Maid.new() -- lives as long as the window
	self.OpenMaid = Maid.new() -- connections that only matter while open
	self.Opened = Signal.new()
	self.Closed = Signal.new()
	self.Resized = Signal.new()
	self.TabChanged = Signal.new()
	self.Maid:Give(self.Opened)
	self.Maid:Give(self.Closed)
	self.Maid:Give(self.Resized)
	self.Maid:Give(self.TabChanged)
	self.IsOpen = false
	self.Token = 0
	self.Pages = {}
	self.Accent = p.Accent or Theme.Accent
	local gui = Overlay.Windows()
	self.Gui = gui

	local root = Base.New("Frame", {
		Name = p.Name or ("KitWindow_" .. self.Key),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
	}, gui)
	self.Root = root
	self.Maid:Give(root)
	-- The backdrop sinks clicks behind the card (it does not close the window).
	self.Backdrop = Base.New("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 1,
	}, root)
	local card = Base.New("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 2,
	}, root)
	self.Card = card
	self.CardCorner = Base.Corner(card, Theme.Radius.Window)
	self.CardStroke = Base.Stroke(card, Theme.Colors.edge, Theme.StrokeWidth.Window)
	self.Scale = Base.New("UIScale", { Name = "KitMotion" }, card)

	local header = Base.New("Frame", {
		Name = "Header",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, card)
	self.Header = header
	Base.Corner(header, Theme.Radius.Card)
	Base.Stroke(header, Theme.Colors.edge, 2)
	self.HeaderGradient = Base.New("UIGradient", { Rotation = 90 }, header)
	if p.Icon then
		self.Icon = Base.Icon(header, p.Icon, { ZIndex = 4, AnchorPoint = Vector2.new(0, 0.5), Color = Theme.White })
	end
	self.Title = Base.Text(header, {
		Name = "Title",
		Text = p.Title or "",
		TextSize = Theme.TextSize.Title,
		Scaled = true,
		MinTextSize = 14,
		Color = Theme.White,
		Stroke = 0,
		ZIndex = 4,
		NoTranslate = p.NoTranslate,
	})
	self.Subtitle = Base.Text(header, {
		Name = "Subtitle",
		Text = p.Subtitle or "",
		TextSize = Theme.TextSize.Subtitle,
		Color = Theme.White,
		Stroke = 0.45,
		ZIndex = 4,
		NoTranslate = p.NoTranslate,
	})
	self.CloseButton = Button.new(header, {
		Name = "Close",
		Text = "X",
		Style = "danger",
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 5,
		NoTranslate = true,
		OnClick = function()
			self:Close("button")
		end,
	})
	self.CloseButton.Instance:SetAttribute("KitSound", "") -- closing plays the Close cue itself
	self.Maid:Give(self.CloseButton)

	if p.Tabs then
		self.Tabs = Controls.Tabs.new(card, {
			Name = "Tabs",
			Tabs = p.Tabs,
			Selected = p.Tab,
			Accent = self.Accent,
			ZIndex = 3,
			OnChange = function(id)
				self:_showTab(id)
			end,
		})
		self.Maid:Give(self.Tabs)
		self.Tab = self.Tabs.Selected
	end

	self.Body = Base.New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
	}, card)

	-- Covers the content during open / close so the whole card fades without a CanvasGroup.
	self.Cover = Base.New("Frame", {
		Name = "FadeCover",
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 60,
	}, card)
	self.CoverCorner = Base.Corner(self.Cover, Theme.Radius.Window)

	self:SetAccent(self.Accent)
	self:Relayout()
	return self
end

-- Recomputes the window rectangle and the header / tabs / body layout from the safe area.
function Window.Relayout(self: any)
	local gui = self.Gui
	if gui.AbsoluteSize.X < 2 then
		return
	end
	local p = self.Props
	local sx, sy, sw, sh = Base.SafeArea(gui)
	local info = Layout.Classify(sw, sh, UserInputService.TouchEnabled)
	local maxSize: Vector2 = p.MaxSize or Vector2.new(1040, 760)
	local x, y, w, h = Layout.WindowRect(sx, sy, sw, sh, info.Phone, maxSize.X, maxSize.Y, 28)
	local card = self.Card
	Base.PlaceCentered(card, x, y, w, h)
	local radius = info.Phone and 0 or Theme.Radius.Window
	self.CardCorner.CornerRadius = UDim.new(0, radius)
	self.CoverCorner.CornerRadius = UDim.new(0, radius)
	self.CardStroke.Enabled = not info.Phone

	local landscape = info.Phone and info.Landscape
	local pad = info.Phone and (landscape and 6 or 8) or 12
	local headerH = info.Phone and (landscape and 50 or 58) or 74
	local header = self.Header
	header.Position = UDim2.fromOffset(pad, pad)
	header.Size = UDim2.new(1, -pad * 2, 0, headerH)
	local closeSize = info.Phone and math.min(44, headerH - 8) or 48 -- >= 42 px touch target
	self.CloseButton.Instance.Size = UDim2.fromOffset(closeSize, closeSize)
	self.CloseButton.Instance.Position = UDim2.new(1, -(headerH - closeSize) / 2, 0.5, 0)
	local textX = 14
	if self.Icon then
		local iconSize = headerH - (info.Phone and 10 or 12)
		self.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
		self.Icon.Position = UDim2.new(0, 8, 0.5, 0)
		textX = iconSize + 16
	end
	local textW = -(textX + closeSize + 18)
	local showSubtitle = not landscape and (self.Subtitle.Text ~= "")
	local titleH = info.Phone and 30 or 38
	local subtitleH = info.Phone and 18 or 22
	local block = titleH + (showSubtitle and subtitleH or 0)
	local top = math.floor((headerH - block) / 2)
	self.Title.Position = UDim2.fromOffset(textX, top)
	self.Title.Size = UDim2.new(1, textW, 0, titleH)
	local limit = self.Title:FindFirstChildWhichIsA("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = Theme.Size("Title", info.Phone)
	end
	self.Subtitle.Visible = showSubtitle
	self.Subtitle.Position = UDim2.fromOffset(textX + 1, top + titleH - 2)
	self.Subtitle.Size = UDim2.new(1, textW, 0, subtitleH)
	self.Subtitle.TextSize = Theme.Size("Subtitle", info.Phone)

	local cursor = pad + headerH + (info.Phone and 6 or 10)
	if self.Tabs then
		local tabH = info.Phone and (landscape and 36 or 42) or 46
		self.Tabs.Instance.Position = UDim2.fromOffset(pad, cursor)
		self.Tabs.Instance.Size = UDim2.new(1, -pad * 2, 0, tabH)
		cursor += tabH + (info.Phone and 4 or 8)
	end
	self.Body.Position = UDim2.fromOffset(pad, cursor)
	self.Body.Size = UDim2.new(1, -pad * 2, 1, -(cursor + pad))

	self.Layout = {
		Phone = info.Phone,
		Landscape = landscape,
		Touch = info.Touch,
		Width = w - pad * 2,
		Height = h - cursor - pad,
		Window = Rect.new(x, y, x + w, y + h),
		Safe = Rect.new(sx, sy, sx + sw, sy + sh),
	}
	self.Resized:Fire(self.Layout)
end

-- Layout info of the body: {Phone, Landscape, Touch, Width, Height, Window, Safe}.
function Window.GetLayout(self: any): any
	if not self.Layout then
		self:Relayout()
	end
	-- Before the first layout (no screen size yet) callers still get a usable answer.
	return self.Layout or { Phone = false, Landscape = false, Touch = UserInputService.TouchEnabled, Width = 0, Height = 0 }
end

function Window.SetTitle(self: any, title: string?, subtitle: string?)
	if title then
		self.Title.Text = title
	end
	if subtitle then
		local had = self.Subtitle.Text ~= ""
		self.Subtitle.Text = subtitle
		if had ~= (subtitle ~= "") then
			self:Relayout()
		end
	end
end

function Window.SetAccent(self: any, color: Color3)
	self.Accent = color
	self.HeaderGradient.Color = ColorSequence.new(color:Lerp(Theme.White, 0.18), color)
	if self.Tabs then
		self.Tabs:SetAccent(color)
	end
end

-- A frame inside the body shown only while tab `id` is selected (created on first use).
function Window.Page(self: any, id: string): Frame
	local page = self.Pages[id]
	if page then
		return page
	end
	page = Base.New("Frame", {
		Name = "Page_" .. id,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = (self.Tab == nil) or self.Tab == id,
		ZIndex = 2,
	}, self.Body)
	self.Pages[id] = page
	return page
end

function Window._showTab(self: any, id: string)
	local previous = self.Tab
	self.Tab = id
	for pageId, page in pairs(self.Pages) do
		page.Visible = pageId == id
	end
	local page = self.Pages[id]
	if page and previous ~= id and self.IsOpen and not Motion.Reduced() then
		page.Position = UDim2.fromOffset(0, 10)
		Motion.Tween(page, Theme.Motion.Fast, { Position = UDim2.new() })
	end
	self.TabChanged:Fire(id)
	if self.Props.OnTab then
		task.spawn(self.Props.OnTab, id)
	end
end

-- Selects a tab (fires TabChanged / OnTab unless silent).
function Window.SetTab(self: any, id: string, silent: boolean?)
	if not self.Tabs then
		return
	end
	if silent then
		self.Tabs:Select(id, true)
		self.Tab = id
		for pageId, page in pairs(self.Pages) do
			page.Visible = pageId == id
		end
	else
		self.Tabs:Select(id)
	end
end

function Window.SetBadge(self: any, tabId: string, text: any)
	if self.Tabs then
		self.Tabs:SetBadge(tabId, text)
	end
end

function Window.Open(self: any)
	if self.Destroyed or self.IsOpen then
		return
	end
	if not self.Props.Stack then
		-- Hand navigation over silently when this window takes it; otherwise give it back.
		local takeOver = not self.Props.NoNavigation
		for i = #stack, 1, -1 do
			local window = stack[i]
			if window then
				window:_close("replaced", takeOver)
			end
		end
	end
	if #stack == 0 and not self.Props.NoNavigation then
		self.NavKey = Nav.Acquire(self.Key) and self.Key or nil
	else
		self.NavKey = nil
	end
	table.insert(stack, self)
	self.IsOpen = true
	self.Token += 1
	self.Root.ZIndex = #stack
	self.Root.Visible = true
	-- Relayout while open: screen size (window resize, rotation) and top bar inset.
	self.OpenMaid:Give(self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Relayout()
	end))
	self.OpenMaid:Give(GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		self:Relayout()
	end))
	self:Relayout()
	Sound.Play("Open", self.Props.Stack and { Pitch = 1.15 } or nil)
	local t = Theme.Motion.Open
	if Motion.Reduced() then
		self.Backdrop.BackgroundTransparency = Theme.BackdropTransparency
		self.Scale.Scale = 1
		self.Cover.Visible = false
	else
		-- Blur-free backdrop fade, and the card springs up (Back easing overshoots slightly).
		self.Backdrop.BackgroundTransparency = 1
		self.Scale.Scale = 0.9
		self.Cover.Visible = true
		self.Cover.BackgroundTransparency = 0
		Motion.Tween(self.Backdrop, t, { BackgroundTransparency = Theme.BackdropTransparency })
		Motion.Tween(self.Scale, t + 0.06, { Scale = 1 }, Enum.EasingStyle.Back)
		local fade = Motion.Tween(self.Cover, t, { BackgroundTransparency = 1 })
		local token = self.Token
		if fade then
			fade.Completed:Connect(function()
				if self.Token == token then
					self.Cover.Visible = false
				end
			end)
		end
	end
	Base.GamepadFocus(self.CloseButton.Instance)
	self.Opened:Fire()
	if self.Props.OnOpen then
		task.spawn(self.Props.OnOpen, self)
	end
end

function Window.Close(self: any, reason: string?)
	self:_close(reason or "close", false)
end

-- silent: hide at once without giving navigation back (another kit window takes over).
function Window._close(self: any, reason: string, silent: boolean)
	if not self.IsOpen then
		return
	end
	-- Windows stacked above this one close first.
	local index = table.find(stack, self)
	if index then
		for i = #stack, index + 1, -1 do
			stack[i]:_close(reason, true)
		end
		table.remove(stack, index)
	end
	self.IsOpen = false
	self.Token += 1
	local token = self.Token
	self.OpenMaid:Clean()
	Overlay.DismissOwned(self, reason)
	local navKey = self.NavKey
	self.NavKey = nil
	if navKey and not silent and reason ~= "navigation" then
		Nav.Release(navKey)
	end
	if not silent and reason ~= "navigation" and reason ~= "replaced" and reason ~= "destroy" then
		Sound.Play("Close")
	end
	if silent or Motion.Reduced() then
		self.Root.Visible = false
		self.Cover.Visible = false
	else
		local t = Theme.Motion.Close
		self.Cover.Visible = true
		Motion.Tween(self.Backdrop, t, { BackgroundTransparency = 1 })
		Motion.Tween(self.Scale, t, { Scale = 0.96 })
		Motion.Tween(self.Cover, t, { BackgroundTransparency = 0 })
		task.delay(t, function()
			if self.Token == token and not self.IsOpen then
				self.Root.Visible = false
				self.Cover.Visible = false
			end
		end)
	end
	self.Closed:Fire(reason)
	if self.Props.OnClose then
		task.spawn(self.Props.OnClose, self, reason)
	end
end

function Window.Toggle(self: any)
	if self.IsOpen then
		self:Close("toggle")
	else
		self:Open()
	end
end

function Window.Destroy(self: any)
	if self.Destroyed then
		return
	end
	self:_close("destroy", false)
	self.Destroyed = true
	self.OpenMaid:Clean()
	self.Maid:Clean()
end

-- The window on top of the kit stack (nil when none is open).
function Window.Top(): any
	return stack[#stack]
end

function Window.Count(): number
	return #stack
end

function Window.CloseAll(reason: string?)
	for i = #stack, 1, -1 do
		local window = stack[i]
		if window then
			window:_close(reason or "close", i > 1)
		end
	end
end

-- Navigation moved elsewhere (another menu, a reward, Escape, respawn): close the kit windows.
Nav.Changed:Connect(function()
	local base = stack[1]
	if not base or not base.NavKey then
		return
	end
	if not Nav.Owns(base.NavKey) then
		Window.CloseAll("navigation")
	end
end)

return Window
