-- Kit.Toast (non-blocking notification queue), Kit.Tooltip (hover / long-press info) and
-- Kit.LongPress.
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)
local Motion = require(script.Parent.Motion)
local Overlay = require(script.Parent.Overlay)
local Sound = require(script.Parent.Sound)

local Feedback = {}

------------------------------------------------------------------------------------------------
-- Toast
------------------------------------------------------------------------------------------------
local KINDS = {
	info = { Color = Theme.Info, Glyph = "i", Sound = "Notify" },
	success = { Color = Theme.Success, Glyph = "✓", Sound = "Success" },
	error = { Color = Theme.Danger, Glyph = "!", Sound = "Error" },
	warn = { Color = Theme.Warning, Glyph = "!", Sound = "Notify", Pitch = 0.85 },
}

-- The cue of a toast: opts.Sound ("Coin" for a sale, false for none), else its kind's cue.
local function toastSound(entry: any)
	if entry.Sound == false then
		return
	end
	local kind = KINDS[entry.Kind] or KINDS.info
	local cue = type(entry.Sound) == "string" and entry.Sound or kind.Sound
	Sound.Play(cue, kind.Pitch and cue == kind.Sound and { Pitch = kind.Pitch } or nil)
end
Feedback.MaxToasts = 3
local queue: { any } = {}
local shown: { any } = {}
local TOAST_H, TOAST_GAP = 48, 8

local function layoutToasts(animate: boolean)
	local gui = Overlay.Top()
	local x, y, w = Base.SafeArea(gui)
	local width = math.min(440, w - 32)
	local index = 0
	for _, toast in ipairs(shown) do
		if not toast.Leaving then
			local goal = UDim2.fromOffset(x + w / 2, y + 12 + index * (TOAST_H + TOAST_GAP))
			toast.Frame.Size = UDim2.fromOffset(width, TOAST_H)
			if animate then
				Motion.Tween(toast.Frame, Theme.Motion.Slide, { Position = goal })
			else
				toast.Frame.Position = goal
			end
			index += 1
		end
	end
end

local pump: () -> ()

local function hide(toast: any)
	if toast.Leaving then
		return
	end
	toast.Leaving = true
	local t = Theme.Motion.Close
	Motion.Tween(toast.Frame, t, { BackgroundTransparency = 1, Position = toast.Frame.Position - UDim2.fromOffset(0, 10) })
	Motion.Tween(toast.Label, t, { TextTransparency = 1, TextStrokeTransparency = 1 })
	Motion.Tween(toast.Dot, t, { BackgroundTransparency = 1 })
	Motion.Tween(toast.Glyph, t, { TextTransparency = 1 })
	Motion.Tween(toast.Stroke, t, { Transparency = 1 })
	task.delay(Motion.Reduced() and 0 or t, function()
		toast.Frame:Destroy()
		local index = table.find(shown, toast)
		if index then
			table.remove(shown, index)
		end
		layoutToasts(true)
		pump()
	end)
end

local function schedule(toast: any)
	local token = {}
	toast.Token = token
	task.delay(toast.Duration, function()
		if toast.Token == token then
			hide(toast)
		end
	end)
end

local function show(entry: any)
	local gui = Overlay.Top()
	local kind = KINDS[entry.Kind] or KINDS.info
	local frame = Base.New("Frame", {
		Name = "KitToast",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 980,
	})
	Base.Corner(frame, 14)
	local stroke = Base.Stroke(frame, Theme.Colors.edge, 2, 0.2)
	local dot = Base.New("Frame", {
		Name = "Kind",
		BackgroundColor3 = kind.Color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 981,
	}, frame)
	Base.Corner(dot, "pill")
	local glyph = Base.Text(dot, {
		Name = "Glyph",
		Text = kind.Glyph,
		TextSize = 17,
		AlignX = "Center",
		Color = Theme.White,
		ZIndex = 982,
		NoTranslate = true,
	})
	local label = Base.Text(frame, {
		Name = "Message",
		Text = entry.Text,
		TextSize = 16,
		Scaled = true,
		MinTextSize = 11,
		Wrap = true,
		Position = UDim2.fromOffset(46, 4),
		Size = UDim2.new(1, -86, 1, -8),
		ZIndex = 981,
		NoTranslate = entry.NoTranslate,
	})
	local count = Base.Text(frame, {
		Name = "Count",
		Text = "",
		Font = "numeric",
		TextSize = 15,
		AlignX = "Right",
		Color = Theme.InkMuted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(34, 24),
		ZIndex = 981,
		NoTranslate = true,
	})
	local toast = {
		Frame = frame,
		Label = label,
		Dot = dot,
		Glyph = glyph,
		Stroke = stroke,
		CountLabel = count,
		Text = entry.Text,
		Count = 1,
		Duration = entry.Duration,
	}
	table.insert(shown, toast)
	layoutToasts(false)
	-- Slides in from above its slot with a small overshoot.
	local final = frame.Position
	frame.Position = final - UDim2.fromOffset(0, TOAST_H + 18)
	frame.BackgroundTransparency = 0.3
	frame.Parent = gui
	Motion.Tween(frame, Theme.Motion.Slide + 0.06, { Position = final, BackgroundTransparency = 0 }, Enum.EasingStyle.Back)
	toastSound(entry)
	schedule(toast)
end

pump = function()
	local visible = 0
	for _, toast in ipairs(shown) do
		if not toast.Leaving then
			visible += 1
		end
	end
	while visible < Feedback.MaxToasts and #queue > 0 do
		show(table.remove(queue, 1))
		visible += 1
	end
end

-- Shows a short notification at the top of the screen. Never blocks input. Repeating the text
-- of a visible toast bumps its counter ("×2") instead of stacking.
-- opts: Kind "info" | "success" | "error" | "warn", Duration seconds (2.6), NoTranslate,
-- Sound (a Kit.Sound cue instead of the kind's cue, or false for a silent toast).
function Feedback.Toast(text: string, opts: any?)
	local o: any = opts or {}
	local duration = o.Duration or 2.6
	for _, toast in ipairs(shown) do
		if toast.Text == text and not toast.Leaving then
			toast.Count += 1
			toast.CountLabel.Text = "×" .. toast.Count
			toast.Duration = duration
			schedule(toast)
			toastSound({ Kind = o.Kind or "info", Sound = o.Sound })
			-- A small pop on the repeated toast.
			if not Motion.Reduced() then
				local pop = toast.Frame:FindFirstChild("KitPop") or Base.New("UIScale", { Name = "KitPop" }, toast.Frame)
				pop.Scale = 1.05
				Motion.Tween(pop, Theme.Motion.Fast, { Scale = 1 })
			end
			return
		end
	end
	for _, entry in ipairs(queue) do
		if entry.Text == text then
			return
		end
	end
	table.insert(queue, { Text = text, Kind = o.Kind or "info", Duration = duration, NoTranslate = o.NoTranslate, Sound = o.Sound })
	pump()
end

function Feedback.ToastCount(): (number, number)
	local visible = 0
	for _, toast in ipairs(shown) do
		if not toast.Leaving then
			visible += 1
		end
	end
	return visible, #queue
end

------------------------------------------------------------------------------------------------
-- LongPress: touch hold (and right click) on a GuiObject.
------------------------------------------------------------------------------------------------
local LONG_PRESS = 0.45
local MOVE_TOLERANCE = 12

function Feedback.LongPress(target: GuiObject, fn: () -> (), opts: any?): any
	local o: any = opts or {}
	local duration = o.Duration or LONG_PRESS
	local handle: any = { Fired = false }
	local connections = {}
	local pressing: any = nil
	table.insert(connections, target.InputBegan:Connect(function(input)
		local touch = input.UserInputType == Enum.UserInputType.Touch
		local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if not (touch or mouse) then
			return
		end
		-- A new press: the click that ends it counts again unless this press fires.
		handle.Fired = false
		if mouse and o.Mouse ~= true then
			return
		end
		local token = { Start = input.Position }
		pressing = token
		task.delay(duration, function()
			if pressing == token then
				pressing = nil
				handle.Fired = true
				task.spawn(fn)
			end
		end)
	end))
	table.insert(connections, target.InputChanged:Connect(function(input)
		if pressing and input.UserInputType == Enum.UserInputType.Touch then
			if (input.Position - pressing.Start).Magnitude > MOVE_TOLERANCE then
				pressing = nil
			end
		end
	end))
	table.insert(connections, target.InputEnded:Connect(function()
		pressing = nil
	end))
	if o.RightClick ~= false and target:IsA("GuiButton") then
		table.insert(connections, (target :: any).MouseButton2Click:Connect(function()
			task.spawn(fn)
		end))
	end
	-- True when the current press fired the long press: ignore the click its release produces.
	function handle.Consumed(): boolean
		return handle.Fired == true
	end
	function handle.Destroy()
		pressing = nil
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	handle.Disconnect = handle.Destroy
	return handle
end

------------------------------------------------------------------------------------------------
-- Tooltip: hover (mouse), selection (gamepad) or long press (touch) shows a small panel next to
-- the target. One panel per ScreenGui is reused.
------------------------------------------------------------------------------------------------
local panels: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local currentOwner: any = nil

local function panelFor(layer: Instance): any
	local panel = panels[layer]
	if panel and panel.Frame.Parent then
		return panel
	end
	local frame = Base.New("Frame", {
		Name = "KitTooltip",
		BackgroundColor3 = Theme.Colors.edge,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(260, 0),
		Visible = false,
		ZIndex = 960,
	}, layer)
	Base.Corner(frame, 10)
	Base.Padding(frame, 10, 8, 10, 8)
	Base.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, frame)
	local title = Base.Text(frame, {
		Name = "Title",
		TextSize = 16,
		Color = Theme.Colors.gold,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		ZIndex = 961,
	})
	local body = Base.Text(frame, {
		Name = "Body",
		TextSize = 14,
		Color = Theme.White,
		Wrap = true,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
		ZIndex = 961,
	})
	body.AutomaticSize = Enum.AutomaticSize.Y
	panel = { Frame = frame, Title = title, Body = body }
	-- AutomaticSize settles after the text is set: place the panel again with its real height.
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if frame.Visible and panel.Place then
			panel.Place()
		end
	end)
	panels[layer] = panel
	return panel
end

local function hideTip(owner: any)
	if currentOwner ~= owner then
		return
	end
	currentOwner = nil
	for _, panel in pairs(panels) do
		panel.Frame.Visible = false
	end
end

local function showTip(owner: any, target: GuiObject, title: string?, body: string)
	local layer: any = target:FindFirstAncestorWhichIsA("LayerCollector")
	if not layer then
		return
	end
	hideTip(currentOwner)
	currentOwner = owner
	local panel = panelFor(layer)
	panel.Title.Text = title or ""
	panel.Title.Visible = title ~= nil and title ~= ""
	panel.Body.Text = body
	local frame = panel.Frame
	local screen = layer.AbsoluteSize
	local width = math.min(280, screen.X - 24)
	frame.Size = UDim2.fromOffset(width, 0)
	frame.Visible = true
	-- Above the target when there is room, otherwise below; clamped to the screen.
	local function place()
		if not target.Parent then
			return
		end
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		local height = math.max(frame.AbsoluteSize.Y, 40)
		local x = math.clamp(pos.X + size.X / 2 - width / 2, 12, math.max(12, screen.X - width - 12))
		local y = pos.Y - height - 8
		if y < 8 then
			y = pos.Y + size.Y + 8
		end
		frame.Position = UDim2.fromOffset(math.floor(x), math.floor(math.min(y, math.max(8, screen.Y - height - 8))))
	end
	panel.Place = place
	place()
end

-- Attaches a tooltip. content: a string or a function returning (body[, title]) evaluated when
-- shown. opts: Title, Delay (0.35 s). Returns a handle with Destroy() and SetText(body, title).
function Feedback.Tooltip(target: GuiObject, content: any, opts: any?): any
	local o: any = opts or {}
	local handle: any = { Content = content, Title = o.Title }
	local connections = {}
	local hovering: any = nil
	local function resolve(): (string, string?)
		local value = handle.Content
		if type(value) == "function" then
			local body, title = value()
			return tostring(body or ""), title or handle.Title
		end
		return tostring(value or ""), handle.Title
	end
	local function open()
		local body, title = resolve()
		if body ~= "" or (title or "") ~= "" then
			showTip(handle, target, title, body)
		end
	end
	local function hover()
		local token = {}
		hovering = token
		task.delay(o.Delay or 0.35, function()
			if hovering == token then
				open()
			end
		end)
	end
	local function leave()
		hovering = nil
		hideTip(handle)
	end
	table.insert(connections, target.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		hover()
	end))
	table.insert(connections, target.MouseLeave:Connect(leave))
	table.insert(connections, target.SelectionGained:Connect(hover))
	table.insert(connections, target.SelectionLost:Connect(leave))
	table.insert(connections, target.AncestryChanged:Connect(leave))
	table.insert(connections, target:GetPropertyChangedSignal("Visible"):Connect(leave))
	local press = Feedback.LongPress(target, open, { RightClick = false })
	table.insert(connections, target.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			task.delay(1.6, function()
				if currentOwner == handle then
					hideTip(handle)
				end
			end)
		end
	end))
	handle.Press = press
	function handle.SetText(_self: any, body: any, title: string?)
		handle.Content = body
		if title then
			handle.Title = title
		end
		if currentOwner == handle then
			open()
		end
	end
	function handle.Destroy()
		leave()
		press.Destroy()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	handle.Disconnect = handle.Destroy
	return handle
end

function Feedback.HideTooltip()
	if currentOwner then
		hideTip(currentOwner)
	end
end

return Feedback
