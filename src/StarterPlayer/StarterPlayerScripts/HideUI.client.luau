-- HIDE UI (docs/UI.md): the HIDE UI button of the HUD (eye, top-right) and the H key hide the
-- whole interface for screenshots, videos and streams.
--   * One switch: the main ScreenGui attribute UIHidden (true = hidden). GUIIntegration keeps the
--     HUD hidden while it is set and clears it when any menu opens.
--   * Hiding: the HUD groups slide to their nearest edge (rail left, currency bar up, cluster up /
--     right: attribute HUDEdge, set by UITheme.LayoutHUD) while the rest of the HUD, the bag toast,
--     event notices, the tutorial card and the map marker button fade out; then the main ScreenGui
--     is switched off (its scripts keep running and cannot pop anything back). HUD-like layers
--     fade and switch off too: MiningGui, MiningToast, the kit toasts (KitOverlay), the lucky
--     arrival banner and any ScreenGui tagged HideWithUI = true. The Roblox CoreGui (chat,
--     leaderboard, backpack, emotes, health, the top bar) is hidden and later restored exactly
--     as it was. World billboards (titles, name plates, markers) stay: they are part of the world.
--   * A small eye button stays in the top-right corner; it fades to almost invisible after 2 s
--     and wakes up on mouse movement or a tap. The eye, H or Escape bring everything back with
--     the reverse animation. Reduced motion: instant.
-- Animations run on one Heartbeat connection that exists only while something animates.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ScreenGui")
local modules = gui:WaitForChild("Modules")
local U = require(modules:WaitForChild("UITheme"))
local N = require(modules:WaitForChild("GUIIntegration"))
local Kit = require(modules:WaitForChild("Kit"))
local Motion, Sound = Kit.Motion, Kit.Sound
local hud = gui:WaitForChild("HUD")

local HIDE_TIME, SHOW_TIME, FADE_TIME = 0.3, 0.36, 0.22
local IDLE_SECONDS = 2
local MAX_FADE = 320 -- objects faded per subtree; bigger ones simply switch off
-- HUD-like layers (menus are not listed: opening a menu shows the interface again).
local LAYERS = { MiningGui = true, MiningToast = true, KitOverlay = true, DOGROTS_LuckyArrivalBanner = true }
-- Frames of the main ScreenGui that fade with the HUD (the whole ScreenGui switches off after).
local FRAMES = { InventoryToast = true, WorldEventNotice = true, OnboardingGuide = true, RewardMachineRewardToast = true }
local CORE = { "PlayerList", "Backpack", "Chat", "EmotesMenu", "Health", "SelfView", "Captures" }

local hidden = false
local token = 0

------------------------------------------------------------------------------------------------
-- Animation driver
------------------------------------------------------------------------------------------------
local anims: { any } = {}
local driver: RBXScriptConnection? = nil
local function easeOutBack(t: number): number
	local c1, c3 = 1.2, 2.2
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function easeInBack(t: number): number
	local c1, c3 = 1.2, 2.2
	return c3 * t ^ 3 - c1 * t ^ 2
end
local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function step()
	local now = os.clock()
	for i = #anims, 1, -1 do
		local a = anims[i]
		local t = math.clamp((now - a.Start) / a.Duration, 0, 1)
		if now >= a.Start then
			local ok, err = pcall(a.Step, a.Ease(t))
			if not ok then
				warn("HideUI: " .. tostring(err))
				t = 1
			end
		end
		if t >= 1 then
			table.remove(anims, i)
			if a.Done then
				task.spawn(a.Done)
			end
		end
	end
	if #anims == 0 and driver then
		driver:Disconnect()
		driver = nil
	end
end
local function animate(duration: number, delay: number, ease: (number) -> number, stepFn: (number) -> (), done: (() -> ())?)
	table.insert(anims, { Start = os.clock() + delay, Duration = math.max(0.01, duration), Ease = ease, Step = stepFn, Done = done })
	if not driver then
		driver = RunService.Heartbeat:Connect(step)
	end
end
-- Interrupting (H pressed again mid-animation) FINISHES every running animation first: its last
-- step and its Done put the real transparencies/positions back (Done callbacks check the token
-- for side effects), so the opposite animation never mistakes half-faded values for real ones.
local function stopAll()
	local running = table.clone(anims)
	table.clear(anims)
	for _, a in ipairs(running) do
		pcall(a.Step, a.Ease(1))
		if a.Done then
			pcall(a.Done)
		end
	end
	if driver then
		driver:Disconnect()
		driver = nil
	end
end

------------------------------------------------------------------------------------------------
-- Fading: every transparency of a subtree goes to 1 (or back); the real values are kept and put
-- back once the subtree is switched off, so it looks the same next time.
------------------------------------------------------------------------------------------------
local function collect(root: Instance): { any }
	local entries = {}
	local function add(o: Instance)
		local props: { [string]: number } = {}
		if o:IsA("GuiObject") then
			props.BackgroundTransparency = o.BackgroundTransparency
			if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
				props.TextTransparency = (o :: any).TextTransparency
				props.TextStrokeTransparency = (o :: any).TextStrokeTransparency
			elseif o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ViewportFrame") then
				props.ImageTransparency = (o :: any).ImageTransparency
			elseif o:IsA("CanvasGroup") then
				props.GroupTransparency = (o :: any).GroupTransparency
			end
		elseif o:IsA("UIStroke") then
			props.Transparency = o.Transparency
		else
			return
		end
		table.insert(entries, { Object = o, Props = props })
	end
	add(root)
	for _, d in ipairs(root:GetDescendants()) do
		if #entries >= MAX_FADE then
			break
		end
		add(d)
	end
	return entries
end
local function applyFade(entries: { any }, alpha: number)
	for _, entry in ipairs(entries) do
		local o: any = entry.Object
		if o.Parent then
			for prop, home in pairs(entry.Props) do
				o[prop] = home + (1 - home) * alpha
			end
		end
	end
end

-- Restores queued by the hide animation, run once the interface is switched off (or when a
-- show interrupts it).
local pending: { () -> () } = {}
local function flushPending()
	local list = pending
	pending = {}
	for _, fn in ipairs(list) do
		pcall(fn)
	end
end

------------------------------------------------------------------------------------------------
-- HUD-like layers: Enabled = false while hidden (a script enabling one meanwhile is noted and
-- undone), then back to what they want.
------------------------------------------------------------------------------------------------
local held: { [Instance]: any } = {}
local function hold(target: LayerCollector, fade: boolean)
	if held[target] then
		return
	end
	local record: any = { Wanted = target.Enabled }
	held[target] = record
	local function off()
		target.Enabled = false
	end
	record.Connection = target:GetPropertyChangedSignal("Enabled"):Connect(function()
		if held[target] and target.Enabled then
			record.Wanted = true
			off()
		end
	end)
	if not record.Wanted then
		return
	end
	if fade and not Motion.Reduced() then
		local entries = collect(target)
		local mine = token
		animate(FADE_TIME, 0, easeOutQuad, function(t)
			applyFade(entries, t)
		end, function()
			if held[target] and token == mine then
				off()
			end
			applyFade(entries, 0)
		end)
	else
		off()
	end
end
local function release(target: LayerCollector, fade: boolean)
	local record = held[target]
	if not record then
		return
	end
	held[target] = nil
	record.Connection:Disconnect()
	if not record.Wanted or not target.Parent then
		return
	end
	if fade and not Motion.Reduced() then
		local entries = collect(target)
		applyFade(entries, 1)
		target.Enabled = true
		animate(FADE_TIME + 0.06, 0.08, easeOutQuad, function(t)
			applyFade(entries, 1 - t)
		end, function()
			applyFade(entries, 0)
		end)
	else
		target.Enabled = true
	end
end
local function layerWanted(child: Instance): boolean
	return child:IsA("LayerCollector") and child ~= gui and (LAYERS[child.Name] == true or child:GetAttribute("HideWithUI") == true)
end

------------------------------------------------------------------------------------------------
-- Roblox CoreGui and top bar
------------------------------------------------------------------------------------------------
local savedCore: { [string]: boolean }? = nil
local savedTopbar = false
local function hideCore()
	local saved = {}
	for _, name in ipairs(CORE) do
		local okEnum, item = pcall(function()
			return (Enum.CoreGuiType :: any)[name]
		end)
		if okEnum and item then
			local ok, on = pcall(function()
				return StarterGui:GetCoreGuiEnabled(item)
			end)
			if ok then
				saved[name] = on == true
				if on then
					pcall(function()
						StarterGui:SetCoreGuiEnabled(item, false)
					end)
				end
			end
		end
	end
	savedCore = saved
	local ok, topbar = pcall(function()
		return StarterGui:GetCore("TopbarEnabled")
	end)
	savedTopbar = ok and topbar ~= false
	if savedTopbar then
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
	end
end
local function showCore()
	for name, on in pairs(savedCore or {}) do
		if on then
			pcall(function()
				StarterGui:SetCoreGuiEnabled((Enum.CoreGuiType :: any)[name], true)
			end)
		end
	end
	if savedTopbar then
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", true)
		end)
	end
	savedCore, savedTopbar = nil, false
end

------------------------------------------------------------------------------------------------
-- The show-UI eye button (its own layer, above everything HUD-like).
------------------------------------------------------------------------------------------------
local layer = Instance.new("ScreenGui")
layer.Name = "DOGROTS_ShowUI"
layer.ResetOnSpawn = false
layer.IgnoreGuiInset = true
layer.ScreenInsets = Enum.ScreenInsets.None
layer.DisplayOrder = 99
layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
layer.Enabled = false
layer:SetAttribute("NoTranslate", true)
layer.Parent = playerGui
local group = Instance.new("CanvasGroup")
group.Name = "Eye"
group.BackgroundTransparency = 1
group.AnchorPoint = Vector2.new(1, 0)
group.Size = UDim2.fromOffset(46, 46)
group.GroupTransparency = 1
group.Parent = layer
local eyeButton = Instance.new("TextButton")
eyeButton.Name = "ShowUI"
eyeButton.Text = ""
eyeButton.AutoButtonColor = false
eyeButton.BackgroundColor3 = Color3.fromRGB(23, 43, 76)
eyeButton.BackgroundTransparency = 0.35
eyeButton.Size = UDim2.fromScale(1, 1)
eyeButton.Parent = group
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = eyeButton
local ring = Instance.new("UIStroke")
ring.Color = Color3.new(1, 1, 1)
ring.Thickness = 2
ring.Transparency = 0.4
ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ring.Parent = eyeButton
U.EyeGlyph(eyeButton, 3, false)

-- Top-right of the Core UI safe area (the layer ignores insets, so screen pixels).
local function placeEye()
	local right, top = layer.AbsoluteSize.X, 0
	local ok, safe = pcall(function()
		return GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	end)
	if ok and safe and safe.Max.X > safe.Min.X then
		right, top = safe.Max.X, safe.Min.Y
	end
	group.Position = UDim2.fromOffset(math.floor(right - 10), math.floor(top + 10))
end
layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeEye)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeEye)

local eyeTween: Tween? = nil
local eyeGoal = 1
local lastActivity = 0
local idleCheck = false
local function eyeTo(transparency: number, time: number)
	eyeGoal = transparency
	if eyeTween then
		eyeTween:Cancel()
		eyeTween = nil
	end
	if Motion.Reduced() or time <= 0 then
		group.GroupTransparency = transparency
		return
	end
	local tween = TweenService:Create(group, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = transparency })
	eyeTween = tween
	tween:Play()
end
local function scheduleIdle()
	if idleCheck then
		return
	end
	idleCheck = true
	task.delay(IDLE_SECONDS + 0.05, function()
		idleCheck = false
		if not hidden then
			return
		end
		if os.clock() - lastActivity >= IDLE_SECONDS then
			eyeTo(0.88, 0.6)
		else
			scheduleIdle()
		end
	end)
end
local function wake()
	lastActivity = os.clock()
	if eyeGoal > 0.2 then
		eyeTo(0.1, 0.15)
	end
	scheduleIdle()
end
local wakeConnections: { RBXScriptConnection } = {}
local function watchActivity(on: boolean)
	for _, connection in ipairs(wakeConnections) do
		connection:Disconnect()
	end
	table.clear(wakeConnections)
	if not on then
		return
	end
	table.insert(wakeConnections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			wake()
		end
	end))
	table.insert(wakeConnections, UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Gamepad1 then
			wake()
		end
	end))
end

------------------------------------------------------------------------------------------------
-- The main ScreenGui
------------------------------------------------------------------------------------------------
local function offset(object: GuiObject, edge: string): UDim2
	local size = gui.AbsoluteSize
	local x = object.AbsolutePosition.X - gui.AbsolutePosition.X
	local y = object.AbsolutePosition.Y - gui.AbsolutePosition.Y
	local w, h = object.AbsoluteSize.X, object.AbsoluteSize.Y
	if edge == "Left" then
		return UDim2.fromOffset(-(x + w + 24), 0)
	elseif edge == "Right" then
		return UDim2.fromOffset(size.X - x + 24, 0)
	elseif edge == "Bottom" then
		return UDim2.fromOffset(0, size.Y - y + 24)
	end
	return UDim2.fromOffset(0, -(y + h + 24))
end
-- Edge-tagged HUD children slide (sorted, for a small ripple); the other visible HUD children
-- and the HUD-like frames of the main ScreenGui fade.
local function parts(): ({ any }, { GuiObject })
	local slides, fades = {}, {}
	if hud.Visible then
		for _, child in ipairs(hud:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				local edge = child:GetAttribute("HUDEdge")
				if type(edge) == "string" then
					table.insert(slides, { Object = child, Edge = edge, Order = child.AbsolutePosition.Y + child.AbsolutePosition.X * 0.25 })
				else
					table.insert(fades, child)
				end
			end
		end
	end
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and child ~= hud and (FRAMES[child.Name] or child:GetAttribute("HideWithUI") == true) then
			table.insert(fades, child)
		end
	end
	local guide = gui:FindFirstChild("DistrictGuide")
	local clear = guide and guide:FindFirstChild("ClearMarker")
	if clear and clear:IsA("GuiObject") and clear.Visible then
		table.insert(fades, clear)
	end
	table.sort(slides, function(a, b)
		return a.Order < b.Order
	end)
	return slides, fades
end

local function hide()
	if hidden then
		return
	end
	hidden = true
	token += 1
	local mine = token
	stopAll()
	flushPending()
	Sound.Play("Toggle", { Pitch = 0.85 })
	hideCore()
	for _, child in ipairs(playerGui:GetChildren()) do
		if layerWanted(child) then
			hold(child :: LayerCollector, true)
		end
	end
	local function finish()
		if token ~= mine then
			return
		end
		hud.Visible = false
		gui.Enabled = false
		flushPending()
	end
	if Motion.Reduced() then
		finish()
	else
		local slides, fades = parts()
		for i, part in ipairs(slides) do
			local object = part.Object
			local home = object.Position
			local away = home + offset(object, part.Edge)
			table.insert(pending, function()
				object.Position = home -- home again while hidden (a relayout may move it meanwhile)
			end)
			animate(HIDE_TIME, math.min(i, 12) * 0.012, easeInBack, function(t)
				object.Position = home:Lerp(away, t)
			end)
		end
		for _, child in ipairs(fades) do
			local entries = collect(child)
			table.insert(pending, function()
				applyFade(entries, 0)
			end)
			animate(FADE_TIME, 0, easeOutQuad, function(t)
				applyFade(entries, t)
			end)
		end
		animate(HIDE_TIME + 0.18, 0, easeOutQuad, function() end, finish)
	end
	-- The way back.
	placeEye()
	layer.Enabled = true
	eyeTo(0.1, 0.3)
	lastActivity = os.clock()
	watchActivity(true)
	scheduleIdle()
end

local function show()
	if not hidden then
		return
	end
	hidden = false
	token += 1
	local mine = token
	stopAll()
	flushPending()
	Sound.Play("Toggle", { Pitch = 1.1 })
	watchActivity(false)
	eyeTo(1, 0.12)
	task.delay(0.14, function()
		if not hidden then
			layer.Enabled = false
		end
	end)
	showCore()
	for target in pairs(held) do
		release(target :: LayerCollector, true)
	end
	gui.Enabled = true
	-- The HUD comes back only when no menu took over meanwhile (GUIIntegration shows the menu).
	if N.Owner ~= "HUD" then
		return
	end
	hud.Visible = true
	if Motion.Reduced() then
		U.RequestHUDLayout(gui)
		return
	end
	local slides, fades = parts()
	for i, part in ipairs(slides) do
		local object = part.Object
		local home = object.Position
		local away = home + offset(object, part.Edge)
		object.Position = away
		animate(SHOW_TIME, math.min(i, 12) * 0.014, easeOutBack, function(t)
			object.Position = away:Lerp(home, t)
		end, function()
			object.Position = home
		end)
	end
	for _, child in ipairs(fades) do
		local entries = collect(child)
		applyFade(entries, 1)
		animate(FADE_TIME + 0.08, 0.1, easeOutQuad, function(t)
			applyFade(entries, 1 - t)
		end, function()
			applyFade(entries, 0)
		end)
	end
	-- Settle (the leaderboard may be back) once everything is home.
	animate(SHOW_TIME + 0.24, 0, easeOutQuad, function() end, function()
		if token == mine then
			U.RequestHUDLayout(gui)
		end
	end)
end

local function sync()
	if gui:GetAttribute("UIHidden") == true then
		hide()
	else
		show()
	end
end
gui:GetAttributeChangedSignal("UIHidden"):Connect(sync)
-- A menu that opens without going through GUIIntegration still brings the interface back.
gui:GetAttributeChangedSignal("OpenMenu"):Connect(function()
	if gui:GetAttribute("OpenMenu") ~= nil and gui:GetAttribute("UIHidden") then
		gui:SetAttribute("UIHidden", nil)
	end
end)
-- Layers that appear while hidden (a mining toast...) stay hidden too.
playerGui.ChildAdded:Connect(function(child)
	if hidden and layerWanted(child) then
		hold(child :: LayerCollector, false)
	end
end)

eyeButton.Activated:Connect(function()
	gui:SetAttribute("UIHidden", nil)
end)
eyeButton.MouseEnter:Connect(wake)

-- H toggles (Escape also brings the interface back). Typing in a text box or the chat never does.
UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Escape and hidden then
		gui:SetAttribute("UIHidden", nil)
		return
	end
	if processed or key ~= Enum.KeyCode.H then
		return
	end
	if hidden then
		gui:SetAttribute("UIHidden", nil)
	elseif N.Owner == "HUD" then
		gui:SetAttribute("UIHidden", true)
	end
end)

sync()
