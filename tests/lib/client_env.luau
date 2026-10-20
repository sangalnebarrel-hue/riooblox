--!nocheck
-- A small fake Roblox client for Lune: enough of Instance (properties, children, attributes, events), the client
-- services, a manual clock and the task scheduler to run client UI modules from src/ (the Kit, Modules.TutorialDirector)
-- headless. Not a test by itself; require it from a test as "./lib/client_env".
--
--   local CE = require("./lib/client_env")
--   local gui = CE.MainGui()                        -- PlayerGui.ScreenGui with src/StarterGui/ScreenGui/Modules mounted
--   CE.Overrides["ReplicatedStorage/Navigation/PathGuide"] = fakePathGuide
--   local Director = CE.Require(gui.Modules.TutorialDirector)
--   CE.Advance(2.5)                                   -- run time forward: tasks, delays, Heartbeat, render steps
--   CE.Click(button)                                  -- fires GuiButton.Activated
-- Errors inside spawned tasks and signal handlers land in CE.Errors, warn() calls in CE.Warnings.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")

local CE = {}
local ROOT = (process.env.DOGROTS_SRC or "src"):gsub("/$", "")
local Vector2, Vector3, UDim2, CFrame = roblox.Vector2, roblox.Vector3, roblox.UDim2, roblox.CFrame
local Enum = roblox.Enum

CE.Now = 100 -- os.clock()
CE.Unix = 1760000000 -- os.time() / GetServerTimeNow()
CE.Screen = Vector2.new(1280, 720)
CE.Errors = {}
CE.Warnings = {}
CE.Overrides = {}
CE.Verbose = false

------------------------------------------------------------------------------------------------------------------------
-- Scheduler
------------------------------------------------------------------------------------------------------------------------
local queue = {}
local ours = setmetatable({}, { __mode = "k" })
local cancelled = setmetatable({}, { __mode = "k" })
local function resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) == "dead" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(CE.Errors, tostring(err) .. "\n" .. debug.traceback(thread))
	end
end
local task = {}
function task.spawn(fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	ours[thread] = true
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	ours[thread] = true
	table.insert(queue, { At = CE.Now, Thread = thread, Args = table.pack(...) })
	return thread
end
function task.delay(t, fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	ours[thread] = true
	table.insert(queue, { At = CE.Now + (tonumber(t) or 0), Thread = thread, Args = table.pack(...) })
	return thread
end
function task.wait(t)
	local thread = coroutine.running()
	assert(ours[thread], "task.wait outside a task (fake scheduler)")
	local start = CE.Now
	table.insert(queue, { At = CE.Now + math.max(tonumber(t) or 0, 1 / 60), Thread = thread, Args = table.pack() })
	coroutine.yield()
	return CE.Now - start
end
function task.cancel(thread)
	cancelled[thread] = true
end
CE.task = task

------------------------------------------------------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ Handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local c = { Connected = true }
	function c.Disconnect()
		c.Connected = false
	end
	table.insert(self.Handlers, { Fn = fn, C = c })
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	local thread = coroutine.running()
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		resume(thread, ...)
	end)
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, h in ipairs(table.clone(self.Handlers)) do
		if h.C.Connected then
			task.spawn(h.Fn, ...)
		end
	end
end
CE.Signal = Signal

------------------------------------------------------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------------------------------------------------------
local SUPER = {
	GuiBase2d = "Instance", GuiObject = "GuiBase2d", Frame = "GuiObject", ScrollingFrame = "GuiObject", TextLabel = "GuiObject",
	GuiButton = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", ImageLabel = "GuiObject", TextBox = "GuiObject",
	ViewportFrame = "GuiObject", CanvasGroup = "GuiObject", LayerCollector = "GuiBase2d", ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector", UIComponent = "Instance", UIConstraint = "UIComponent",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIGradient = "UIComponent", UIScale = "UIComponent", UIPadding = "UIComponent",
	UIListLayout = "UIComponent", UIGridLayout = "UIComponent", UIFlexItem = "UIComponent", UIPageLayout = "UIComponent",
	UITextSizeConstraint = "UIConstraint", UISizeConstraint = "UIConstraint", UIAspectRatioConstraint = "UIConstraint",
	PVInstance = "Instance", BasePart = "PVInstance", Part = "BasePart", MeshPart = "BasePart", WedgePart = "BasePart",
	SpawnLocation = "Part", Model = "PVInstance", Workspace = "Model", ValueBase = "Instance", IntValue = "ValueBase",
	NumberValue = "ValueBase", StringValue = "ValueBase", BoolValue = "ValueBase", ObjectValue = "ValueBase",
	LuaSourceContainer = "Instance", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer", Script = "BaseScript",
	LocalScript = "Script", PostEffect = "Instance", DepthOfFieldEffect = "PostEffect", BlurEffect = "PostEffect",
	ColorCorrectionEffect = "PostEffect",
}
local EVENTS = {
	Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton2Click = true,
	MouseEnter = true, MouseLeave = true, MouseMoved = true, InputBegan = true, InputEnded = true, InputChanged = true,
	SelectionGained = true, SelectionLost = true, Destroying = true, ChildAdded = true, ChildRemoved = true,
	DescendantAdded = true, DescendantRemoving = true, Changed = true, AncestryChanged = true, CharacterAdded = true,
	CharacterRemoving = true, Completed = true, Triggered = true, FocusLost = true, Focused = true, TouchTap = true,
	OnClientEvent = true, Event = true, Died = true, Heartbeat = true, RenderStepped = true, Stepped = true,
	LastInputTypeChanged = true, PromptShown = true, PromptHidden = true, PromptTriggered = true, MouseWheelForward = true,
	MouseWheelBackward = true, Ended = true, Played = true, PlayerAdded = true, PlayerRemoving = true,
}
local PROXY = setmetatable({}, { __mode = "k" }) -- proxy -> state
local function isA(className, class)
	local c = className
	while c do
		if c == class then
			return true
		end
		c = SUPER[c] or (c ~= "Instance" and "Instance" or nil)
	end
	return class == "Instance"
end
local function stateOf(proxy)
	return PROXY[proxy]
end
CE.StateOf = stateOf
local newInstance
local function fireChanged(st, key)
	local sig = st.PropSignals[key]
	if sig then
		sig:Fire()
	end
	local changed = st.Events.Changed
	if changed then
		changed:Fire(key)
	end
end
local function absSize(proxy)
	local st = stateOf(proxy)
	if not st then
		return Vector2.zero
	end
	if st.Class == "ScreenGui" or st.Class == "PlayerGui" then
		return CE.Screen
	end
	if st.Class == "BillboardGui" or st.Class == "SurfaceGui" then
		local s = st.Props.Size or UDim2.new()
		return Vector2.new(s.X.Offset, s.Y.Offset)
	end
	if isA(st.Class, "GuiObject") then
		local parent = st.Parent
		local ps = parent and stateOf(parent) and (isA(stateOf(parent).Class, "GuiBase2d") or stateOf(parent).Class == "PlayerGui") and absSize(parent) or CE.Screen
		local s = st.Props.Size or UDim2.new()
		return Vector2.new(ps.X * s.X.Scale + s.X.Offset, ps.Y * s.Y.Scale + s.Y.Offset)
	end
	return Vector2.zero
end
local function absPosition(proxy)
	local st = stateOf(proxy)
	if not st or not isA(st.Class, "GuiObject") then
		return Vector2.zero
	end
	local parent = st.Parent
	local pst = parent and stateOf(parent)
	local pp = (pst and isA(pst.Class, "GuiObject")) and absPosition(parent) or Vector2.zero
	local ps = (pst and (isA(pst.Class, "GuiBase2d"))) and absSize(parent) or CE.Screen
	local p = st.Props.Position or UDim2.new()
	local a = st.Props.AnchorPoint or Vector2.zero
	local size = absSize(proxy)
	return Vector2.new(pp.X + ps.X * p.X.Scale + p.X.Offset - a.X * size.X, pp.Y + ps.Y * p.Y.Scale + p.Y.Offset - a.Y * size.Y)
end
local function defaults(className)
	local d = {}
	if isA(className, "GuiObject") then
		d.Visible = true
		d.Active = false
		d.Size = UDim2.new()
		d.Position = UDim2.new()
		d.AnchorPoint = Vector2.zero
		d.ZIndex = 1
		d.BackgroundTransparency = 0
		if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
			-- only text objects have Text (on a Frame `.Text` finds a child named Text, as in Roblox)
			d.Text = ""
			d.TextSize = 14
		end
		d.Selectable = false
		d.Modal = false
		d.Rotation = 0
	end
	if isA(className, "LayerCollector") then
		d.Enabled = true
		d.Size = UDim2.new()
	end
	if isA(className, "BasePart") then
		d.Size = Vector3.new(4, 1, 2)
		d.CFrame = CFrame.new()
		d.Transparency = 0
		d.LocalTransparencyModifier = 0
	end
	if className == "Camera" then
		d.CameraType = Enum.CameraType.Custom
		d.CFrame = CFrame.new(0, 10, 20)
		d.FieldOfView = 70
		d.ViewportSize = CE.Screen
	end
	if className == "Humanoid" then
		d.Health = 100
		d.MaxHealth = 100
		d.CameraOffset = Vector3.zero
	end
	if className == "Highlight" then
		d.Enabled = true
	end
	if isA(className, "ValueBase") then
		d.Value = className == "StringValue" and "" or (className == "BoolValue" and false or 0)
	end
	return d
end

-- extra methods by class
local METHODS = {}
local function bounding(proxy)
	local minV, maxV
	for _, d in ipairs(proxy:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, s = d.Position, d.Size
			local lo, hi = p - s / 2, p + s / 2
			minV = minV and Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) or lo
			maxV = maxV and Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) or hi
		end
	end
	if not minV then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end
METHODS.Model = {
	GetBoundingBox = function(self)
		return bounding(self)
	end,
	GetPivot = function(self)
		local primary = self.PrimaryPart
		if primary then
			return primary.CFrame
		end
		return (bounding(self))
	end,
	PivotTo = function(self, cf)
		local now = METHODS.Model.GetPivot(self)
		for _, d in ipairs(self:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = cf * now:ToObjectSpace(d.CFrame)
			end
		end
	end,
}
METHODS.Sound = {
	Play = function() end,
	Stop = function() end,
	Pause = function() end,
	Resume = function() end,
}
METHODS.RemoteFunction = {
	InvokeServer = function(self, ...)
		assert(CE.OnInvoke, "no CE.OnInvoke handler")
		return CE.OnInvoke(self, ...)
	end,
}
METHODS.RemoteEvent = {
	FireServer = function(self, ...)
		if CE.OnFire then
			CE.OnFire(self, ...)
		end
	end,
}
METHODS.BindableEvent = {
	Fire = function(self, ...)
		self.Event:Fire(...)
	end,
}

local Instance = {}
function Instance.new(className, parent)
	local proxy = newInstance(className)
	if parent then
		proxy.Parent = parent
	end
	return proxy
end
CE.Instance = Instance

local function setParent(proxy, st, parent)
	if st.Destroyed and parent ~= nil then
		error("The Parent property of " .. st.Name .. " is locked (destroyed)", 3)
	end
	local old = st.Parent
	if old == parent then
		return
	end
	if old then
		local ost = stateOf(old)
		local i = table.find(ost.Children, proxy)
		if i then
			table.remove(ost.Children, i)
		end
		if ost.Events.ChildRemoved then
			ost.Events.ChildRemoved:Fire(proxy)
		end
	end
	st.Parent = parent
	if parent then
		local pst = stateOf(parent)
		assert(pst, "Parent must be a fake instance")
		table.insert(pst.Children, proxy)
		if pst.Events.ChildAdded then
			pst.Events.ChildAdded:Fire(proxy)
		end
		local a = parent
		while a do
			local ast = stateOf(a)
			if ast.Events.DescendantAdded then
				ast.Events.DescendantAdded:Fire(proxy)
			end
			a = ast.Parent
		end
	end
	fireChanged(st, "Parent")
	if st.Events.AncestryChanged then
		st.Events.AncestryChanged:Fire(proxy, parent)
	end
end

local Base = {}
function Base.IsA(self, class)
	return isA(stateOf(self).Class, class)
end
function Base.FindFirstChild(self, name, recursive)
	for _, c in ipairs(stateOf(self).Children) do
		if stateOf(c).Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(stateOf(self).Children) do
			local found = Base.FindFirstChild(c, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function Base.WaitForChild(self, name)
	return Base.FindFirstChild(self, name)
end
function Base.FindFirstChildOfClass(self, class)
	for _, c in ipairs(stateOf(self).Children) do
		if stateOf(c).Class == class then
			return c
		end
	end
	return nil
end
function Base.FindFirstChildWhichIsA(self, class, recursive)
	for _, c in ipairs(stateOf(self).Children) do
		if isA(stateOf(c).Class, class) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(stateOf(self).Children) do
			local found = Base.FindFirstChildWhichIsA(c, class, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function Base.FindFirstAncestorOfClass(self, class)
	local a = stateOf(self).Parent
	while a do
		if stateOf(a).Class == class then
			return a
		end
		a = stateOf(a).Parent
	end
	return nil
end
function Base.FindFirstAncestorWhichIsA(self, class)
	local a = stateOf(self).Parent
	while a do
		if isA(stateOf(a).Class, class) then
			return a
		end
		a = stateOf(a).Parent
	end
	return nil
end
function Base.FindFirstAncestor(self, name)
	local a = stateOf(self).Parent
	while a do
		if stateOf(a).Name == name then
			return a
		end
		a = stateOf(a).Parent
	end
	return nil
end
function Base.GetChildren(self)
	return table.clone(stateOf(self).Children)
end
function Base.GetDescendants(self)
	local out = {}
	local function walk(p)
		for _, c in ipairs(stateOf(p).Children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Base.IsDescendantOf(self, ancestor)
	local a = stateOf(self).Parent
	while a do
		if a == ancestor then
			return true
		end
		a = stateOf(a).Parent
	end
	return false
end
function Base.IsAncestorOf(self, other)
	return Base.IsDescendantOf(other, self)
end
function Base.GetAttribute(self, name)
	return stateOf(self).Attributes[name]
end
function Base.GetAttributes(self)
	return table.clone(stateOf(self).Attributes)
end
function Base.SetAttribute(self, name, value)
	local st = stateOf(self)
	if st.Attributes[name] == value then
		return
	end
	st.Attributes[name] = value
	local sig = st.AttrSignals[name]
	if sig then
		sig:Fire()
	end
	if st.Events.AttributeChanged then
		st.Events.AttributeChanged:Fire(name)
	end
end
function Base.GetAttributeChangedSignal(self, name)
	local st = stateOf(self)
	st.AttrSignals[name] = st.AttrSignals[name] or Signal.new()
	return st.AttrSignals[name]
end
function Base.GetPropertyChangedSignal(self, name)
	local st = stateOf(self)
	st.PropSignals[name] = st.PropSignals[name] or Signal.new()
	return st.PropSignals[name]
end
function Base.ClearAllChildren(self)
	for _, c in ipairs(table.clone(stateOf(self).Children)) do
		c:Destroy()
	end
end
function Base.Destroy(self)
	local st = stateOf(self)
	if st.Destroyed then
		return
	end
	if st.Events.Destroying then
		st.Events.Destroying:Fire()
	end
	for _, c in ipairs(table.clone(st.Children)) do
		c:Destroy()
	end
	setParent(self, st, nil)
	st.Destroyed = true
end
function Base.GetFullName(self)
	local names = {}
	local a = self
	while a do
		table.insert(names, 1, stateOf(a).Name)
		a = stateOf(a).Parent
	end
	return table.concat(names, ".")
end
function Base.Clone(self)
	local st = stateOf(self)
	local copy = newInstance(st.Class)
	local cst = stateOf(copy)
	cst.Name = st.Name
	for k, v in pairs(st.Props) do
		cst.Props[k] = v
	end
	for k, v in pairs(st.Attributes) do
		cst.Attributes[k] = v
	end
	for _, c in ipairs(st.Children) do
		c:Clone().Parent = copy
	end
	return copy
end

newInstance = function(className)
	local st = {
		Class = className,
		Name = className,
		Props = defaults(className),
		Children = {},
		Attributes = {},
		AttrSignals = {},
		PropSignals = {},
		Events = {},
		Parent = nil,
		Destroyed = false,
	}
	local proxy = newproxy(true)
	local mt = getmetatable(proxy)
	PROXY[proxy] = st
	mt.__index = function(_, key)
		if key == "Name" then
			return st.Name
		elseif key == "ClassName" then
			return st.Class
		elseif key == "Parent" then
			return st.Parent
		elseif key == "AbsoluteSize" then
			return absSize(proxy)
		elseif key == "AbsolutePosition" then
			return absPosition(proxy)
		elseif key == "Position" and isA(st.Class, "BasePart") then
			return (st.Props.CFrame or CFrame.new()).Position
		elseif key == "TextBounds" then
			local text = tostring(st.Props.Text or "")
			return Vector2.new(#text * (st.Props.TextSize or 14) * 0.5, st.Props.TextSize or 14)
		end
		local m = METHODS[st.Class] and METHODS[st.Class][key]
		if m then
			return m
		end
		if Base[key] then
			return Base[key]
		end
		local v = st.Props[key]
		if v ~= nil then
			return v
		end
		if EVENTS[key] then
			st.Events[key] = st.Events[key] or Signal.new()
			return st.Events[key]
		end
		return Base.FindFirstChild(proxy, key)
	end
	mt.__newindex = function(_, key, value)
		if key == "Name" then
			st.Name = tostring(value)
			fireChanged(st, "Name")
		elseif key == "Parent" then
			setParent(proxy, st, value)
		elseif key == "Position" and isA(st.Class, "BasePart") then
			local cf = st.Props.CFrame or CFrame.new()
			st.Props.CFrame = cf - cf.Position + value
			fireChanged(st, "CFrame")
			fireChanged(st, "Position")
		else
			if st.Props[key] == value then
				return
			end
			st.Props[key] = value
			fireChanged(st, key)
		end
	end
	mt.__tostring = function()
		return st.Name
	end
	return proxy
end
CE.IsInstance = function(v)
	return type(v) == "userdata" and PROXY[v] ~= nil
end

------------------------------------------------------------------------------------------------------------------------
-- The data model, services and the local player
------------------------------------------------------------------------------------------------------------------------
local game = newInstance("DataModel")
game.Name = "Game"
local services = {}
local function service(name)
	if services[name] then
		return services[name]
	end
	local s = newInstance(name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
METHODS.DataModel = {
	GetService = function(_, name)
		return service(name)
	end,
	FindService = function(_, name)
		return services[name]
	end,
}
CE.Game = game
CE.Service = service
local workspace = service("Workspace")
local camera = newInstance("Camera")
camera.Name = "Camera"
camera.Parent = workspace
workspace.CurrentCamera = camera
METHODS.Workspace = {
	GetServerTimeNow = function()
		return CE.Unix
	end,
	Raycast = function()
		return nil
	end,
	GetBoundingBox = METHODS.Model.GetBoundingBox,
}
CE.Workspace = workspace
CE.Camera = camera

local RunService = service("RunService")
local bound = {}
METHODS.RunService = {
	IsClient = function()
		return true
	end,
	IsServer = function()
		return false
	end,
	IsStudio = function()
		return false
	end,
	IsRunning = function()
		return true
	end,
	BindToRenderStep = function(_, name, priority, fn)
		bound[name] = { Priority = priority, Fn = fn }
	end,
	UnbindFromRenderStep = function(_, name)
		bound[name] = nil
	end,
}
CE.Bound = bound

local UIS = service("UserInputService")
UIS.TouchEnabled = false
UIS.KeyboardEnabled = true
UIS.MouseEnabled = true
UIS.GamepadEnabled = false
METHODS.UserInputService = {
	GetLastInputType = function()
		return Enum.UserInputType.MouseMovement
	end,
	GetFocusedTextBox = function()
		return nil
	end,
	GetMouseLocation = function()
		return Vector2.new(640, 360)
	end,
	GetConnectedGamepads = function()
		return {}
	end,
	IsKeyDown = function()
		return false
	end,
}
CE.UserInputService = UIS

local GuiService = service("GuiService")
GuiService.ReducedMotionEnabled = false
GuiService.TopbarInset = roblox.Rect.new(0, 0, 1280, 58)
METHODS.GuiService = {
	GetInsetArea = function()
		error("not available in the fake client")
	end,
	GetGuiInset = function()
		return Vector2.new(0, 58), Vector2.zero
	end,
}

local TweenService = service("TweenService")
METHODS.TweenService = {
	Create = function(_, target, info, goals)
		local tween = { PlaybackState = Enum.PlaybackState.Begin, Completed = Signal.new(), Target = target, Goals = goals, Info = info }
		function tween.Play(self)
			self.PlaybackState = Enum.PlaybackState.Playing
			local looped = type(info) == "table" and (info.RepeatCount or 0) < 0
			for k, v in pairs(goals) do
				target[k] = v
			end
			if not looped then
				task.defer(function()
					if self.PlaybackState == Enum.PlaybackState.Playing then
						self.PlaybackState = Enum.PlaybackState.Completed
						self.Completed:Fire(Enum.PlaybackState.Completed)
					end
				end)
			end
		end
		function tween.Cancel(self)
			self.PlaybackState = Enum.PlaybackState.Cancelled
		end
		function tween.Pause(self)
			self.PlaybackState = Enum.PlaybackState.Paused
		end
		function tween.Destroy() end
		return tween
	end,
}
local TextService = service("TextService")
METHODS.TextService = {
	GetTextSize = function(_, text, size, _font, frame)
		local width = #tostring(text) * size * 0.5
		local maxW = frame and frame.X or 1e6
		local lines = math.max(1, math.ceil(width / math.max(1, maxW)))
		return Vector2.new(math.min(width, maxW), lines * size * 1.2)
	end,
}
local Http = service("HttpService")
local guidCounter = 0
METHODS.HttpService = {
	GenerateGUID = function(_, braces)
		guidCounter += 1
		local hex = string.format("%032x", guidCounter)
		local g = hex:sub(1, 8) .. "-" .. hex:sub(9, 12) .. "-" .. hex:sub(13, 16) .. "-" .. hex:sub(17, 20) .. "-" .. hex:sub(21)
		return braces and "{" .. g .. "}" or g
	end,
	JSONEncode = function(_, v)
		return serde.encode("json", v)
	end,
	JSONDecode = function(_, v)
		return serde.decode("json", v)
	end,
}
service("LocalizationService").RobloxLocaleId = "en-us"
service("SoundService")
service("ContextActionService")
service("ProximityPromptService").Enabled = true
service("Lighting")
service("StarterGui")
local Players = service("Players")
local player = newInstance("Player")
player.Name = "Tester"
player.UserId = 1
player.DisplayName = "Tester"
player.LocaleId = "en-us"
player.Parent = Players
Players.LocalPlayer = player
METHODS.Players = {
	GetPlayers = function()
		return { player }
	end,
	GetPlayerByUserId = function(_, id)
		return id == 1 and player or nil
	end,
}
METHODS.Player = {
	GetNetworkPing = function()
		return 0.05
	end,
}
local playerGui = newInstance("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local playerScripts = newInstance("PlayerScripts")
playerScripts.Name = "PlayerScripts"
playerScripts.Parent = player
CE.Player = player
CE.PlayerGui = playerGui

-- A character with a root part and a humanoid at `position`.
function CE.Spawn(position)
	local old = player.Character
	if old then
		player.CharacterRemoving:Fire(old)
		old:Destroy()
	end
	local character = newInstance("Model")
	character.Name = "Tester"
	local root = newInstance("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(position or Vector3.new(0, 3, 0))
	root.Parent = character
	local humanoid = newInstance("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	player.Character = character
	player.CharacterAdded:Fire(character)
	return character
end
function CE.MoveTo(position)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	root.CFrame = CFrame.new(position)
end

------------------------------------------------------------------------------------------------------------------------
-- Modules from src/
------------------------------------------------------------------------------------------------------------------------
local CLASS = { [".server.luau"] = "Script", [".client.luau"] = "LocalScript", [".luau"] = "ModuleScript" }
local FILE = setmetatable({}, { __mode = "k" })
-- Sources are read when mounted: Lune's fs calls yield, and a require inside a fake task must not hand its
-- coroutine to Lune's scheduler.
local SOURCE = {}
-- Mounts the src directory `rel` (e.g. "ReplicatedStorage") under `parent` (scripts get their file; a directory next
-- to a script file holds that script's children).
function CE.Mount(rel, parent)
	local dir = ROOT .. "/" .. rel
	local entries = fs.readDir(dir)
	table.sort(entries)
	local made = {}
	local function scriptFor(name)
		return made[name]
	end
	for _, entry in ipairs(entries) do
		local full = dir .. "/" .. entry
		if not fs.isDir(full) then
			for suffix, class in pairs(CLASS) do
				if entry:sub(-#suffix) == suffix and (suffix ~= ".luau" or not (entry:find("%.server%.luau$") or entry:find("%.client%.luau$"))) then
					local name = entry:sub(1, -#suffix - 1)
					local inst = newInstance(class)
					inst.Name = name
					FILE[inst] = full
					if class == "ModuleScript" then
						SOURCE[full] = fs.readFile(full)
					end
					inst.Parent = parent
					made[name] = inst
				end
			end
		end
	end
	for _, entry in ipairs(entries) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local holder = scriptFor(entry)
			if not holder then
				holder = newInstance("Folder")
				holder.Name = entry
				holder.Parent = parent
			end
			CE.Mount(rel .. "/" .. entry, holder)
		end
	end
	return parent
end

local cache = setmetatable({}, { __mode = "k" })
local realTypeof = typeof
local function fakeTypeof(v)
	if CE.IsInstance(v) then
		return "Instance"
	end
	return realTypeof(v)
end
local TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return { Time = time or 1, EasingStyle = style, EasingDirection = direction, RepeatCount = repeatCount or 0, Reverses = reverses, DelayTime = delayTime or 0 }
	end,
}
local RaycastParams = {
	new = function()
		return { FilterType = nil, FilterDescendantsInstances = {} }
	end,
}
local fakeOs = setmetatable({
	clock = function()
		return CE.Now
	end,
	time = function()
		return math.floor(CE.Unix)
	end,
}, { __index = os })
local function pathOf(inst)
	local names = {}
	local a = inst
	while a and a ~= game do
		table.insert(names, 1, a.Name)
		a = a.Parent
	end
	return table.concat(names, "/")
end
CE.PathOf = pathOf
local requireModule
requireModule = function(target)
	assert(CE.IsInstance(target), "require: not a fake ModuleScript")
	local path = pathOf(target)
	for key, value in pairs(CE.Overrides) do
		if path:sub(-#key) == key then
			return value
		end
	end
	if cache[target] ~= nil then
		return cache[target]
	end
	local file = FILE[target]
	assert(file, "require: no source for " .. path)
	local env = setmetatable({
		script = target,
		game = game,
		workspace = workspace,
		require = requireModule,
		Instance = Instance,
		typeof = fakeTypeof,
		task = task,
		os = fakeOs,
		tick = function()
			return CE.Unix
		end,
		time = function()
			return CE.Now
		end,
		wait = function(t)
			return task.wait(t)
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(CE.Warnings, table.concat(parts, " "))
			if CE.Verbose then
				print("warn:", ...)
			end
		end,
		print = function(...)
			if CE.Verbose then
				print(...)
			end
		end,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		UDim2 = UDim2,
		UDim = roblox.UDim,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Font = roblox.Font,
		Enum = Enum,
		TweenInfo = TweenInfo,
		RaycastParams = RaycastParams,
		BrickColor = roblox.BrickColor,
		Random = { new = function(seed)
			local s = math.floor(tonumber(seed) or 7) % 2147483647
			if s <= 0 then
				s += 2147483646
			end
			local r = {}
			function r:NextNumber(a, b)
				s = (s * 48271) % 2147483647
				local x = s / 2147483647
				return a and a + (b - a) * x or x
			end
			function r:NextInteger(a, b)
				return a + math.floor(self:NextNumber() * (b - a + 1))
			end
			return r
		end },
		newproxy = newproxy,
	}, { __index = _G })
	local source = SOURCE[file]
	assert(source, "require: source not mounted for " .. path)
	local fn = luau.load(source, { debugName = file, environment = env })
	local result = fn()
	cache[target] = result
	return result
end
CE.Require = requireModule

-- The main ScreenGui (ResetOnSpawn false) with src/StarterGui/ScreenGui/Modules mounted in it, and a HUD frame.
function CE.MainGui()
	local gui = newInstance("ScreenGui")
	gui.Name = "ScreenGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 0
	local modules = newInstance("Folder")
	modules.Name = "Modules"
	modules.Parent = gui
	CE.Mount("StarterGui/ScreenGui/Modules", modules)
	local hud = newInstance("Frame")
	hud.Name = "HUD"
	hud.Size = UDim2.fromScale(1, 1)
	hud.Parent = gui
	gui.Parent = playerGui
	return gui
end
function CE.MountReplicated()
	CE.Mount("ReplicatedStorage", service("ReplicatedStorage"))
	return service("ReplicatedStorage")
end

------------------------------------------------------------------------------------------------------------------------
-- Time and input
------------------------------------------------------------------------------------------------------------------------
local function runDue()
	local guard = 0
	while guard < 10000 do
		guard += 1
		local index = nil
		local best = math.huge
		for i, q in ipairs(queue) do
			if q.At <= CE.Now and q.At < best then
				index, best = i, q.At
			end
		end
		if not index then
			return
		end
		local q = table.remove(queue, index)
		resume(q.Thread, table.unpack(q.Args, 1, q.Args.n))
	end
end
function CE.Step(dt)
	dt = dt or 1 / 30
	CE.Now += dt
	CE.Unix += dt
	local list = {}
	for name, b in pairs(bound) do
		table.insert(list, { Name = name, Priority = b.Priority, Fn = b.Fn })
	end
	table.sort(list, function(a, b)
		return a.Priority < b.Priority
	end)
	for _, b in ipairs(list) do
		if bound[b.Name] and bound[b.Name].Fn == b.Fn then
			local ok, err = pcall(b.Fn, dt)
			if not ok then
				table.insert(CE.Errors, "render step " .. b.Name .. ": " .. tostring(err))
			end
		end
	end
	RunService.RenderStepped:Fire(dt)
	RunService.Stepped:Fire(CE.Now, dt)
	RunService.Heartbeat:Fire(dt)
	runDue()
end
function CE.Advance(seconds, dt)
	dt = dt or 1 / 20
	local target = CE.Now + seconds
	runDue()
	while CE.Now + 1e-9 < target do
		CE.Step(math.min(dt, target - CE.Now))
	end
end
-- A tap on a GuiButton (Activated fires only for an Active, visible button, like a real tap).
function CE.Click(button)
	assert(CE.IsInstance(button), "Click: not an instance")
	if button.Active == false then
		return false
	end
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, true)
	button.Activated:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	runDue()
	return true
end
function CE.Tap()
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown }, false)
	runDue()
end
-- Is `object` actually on screen (it and every ancestor up to its enabled LayerCollector visible)?
function CE.Shown(object)
	local a = object
	while a do
		local st = stateOf(a)
		if not st then
			return false
		end
		if isA(st.Class, "GuiObject") and st.Props.Visible == false then
			return false
		end
		if isA(st.Class, "LayerCollector") then
			return st.Props.Enabled ~= false and st.Parent ~= nil
		end
		a = st.Parent
	end
	return false
end
function CE.Part(name, position, size, parent)
	local p = newInstance("Part")
	p.Name = name
	p.CFrame = CFrame.new(position)
	p.Size = size or Vector3.new(4, 1, 4)
	p.Parent = parent
	return p
end
function CE.Model(name, parent)
	local m = newInstance("Model")
	m.Name = name
	m.Parent = parent
	return m
end
function CE.Folder(name, parent)
	local f = newInstance("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

return CE
