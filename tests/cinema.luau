--!nolint
-- HalloweenClient.Cinema (docs/halloween2/DESIGN.md §16.2) in a small fake Roblox world: lune run tests/cinema.luau
-- Drives the real module frame by frame (fake clock, scheduler, RenderStep, input, PlayerModule controls, mixer) and
-- checks the contract that matters most: whatever ends a cinematic (its end, a skip, a menu, death, an error, Cancel),
-- the camera, the controls, the interface, the audio duck and the CinemaActive attribute are always restored; the
-- control lock never fights a menu; refusals call OnDone(false); fades lift themselves.
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local SRC = "src/StarterPlayer/StarterPlayerScripts/HalloweenClient/Cinema.luau"

---------------------------------------------------------------------------------------------------------------------
-- fake world
---------------------------------------------------------------------------------------------------------------------
local now = 0
local queue = {}
local function schedule(at, fn, ...)
	table.insert(queue, { At = at, Fn = fn, Args = table.pack(...) })
end
local function Signal()
	local s = { fns = {} }
	function s:Connect(fn)
		local c = { Connected = true, fn = fn }
		function c:Disconnect()
			self.Connected = false
		end
		table.insert(self.fns, c)
		return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function s:Fire(...)
		for _, c in ipairs(table.clone(self.fns)) do
			if c.Connected then
				c.fn(...)
			end
		end
	end
	function s:Count()
		local n = 0
		for _, c in ipairs(self.fns) do
			if c.Connected then
				n += 1
			end
		end
		return n
	end
	return s
end

local DEFAULTS = {
	ScreenGui = { Enabled = true },
	Frame = { Visible = true, BackgroundTransparency = 0 },
	TextLabel = { Visible = true, BackgroundTransparency = 0, TextTransparency = 0, TextStrokeTransparency = 1 },
	TextButton = { Visible = true, BackgroundTransparency = 0, TextTransparency = 0, TextStrokeTransparency = 1 },
	ImageLabel = { Visible = true, BackgroundTransparency = 0, ImageTransparency = 0 },
	UIStroke = { Transparency = 0 },
	DepthOfFieldEffect = { Enabled = true, FarIntensity = 0, NearIntensity = 0, FocusDistance = 0, InFocusRadius = 0 },
}
local ISA = {
	LayerCollector = { ScreenGui = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true },
}
local methods = {}
local meta = {}
local function new(class, name)
	local inst = setmetatable({}, meta)
	rawset(inst, "__props", { ClassName = class, Name = name or class })
	rawset(inst, "__children", {})
	rawset(inst, "__attrs", {})
	rawset(inst, "__changed", {})
	rawset(inst, "AttributeChanged", Signal())
	rawset(inst, "Destroying", Signal())
	for k, v in pairs(DEFAULTS[class] or {}) do
		inst.__props[k] = v
	end
	return inst
end
meta.__index = function(self, k)
	if methods[k] then
		return methods[k]
	end
	local v = rawget(self, "__props")[k]
	if v ~= nil then
		return v
	end
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == k then
			return c
		end
	end
	return nil
end
meta.__newindex = function(self, k, v)
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		props.Parent = v
		if v then
			table.insert(rawget(v, "__children"), self)
		end
	else
		props[k] = v
	end
	local sig = rawget(self, "__changed")[k]
	if sig then
		sig:Fire()
	end
end
function methods:FindFirstChild(name)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == name then
			return c
		end
	end
	return nil
end
methods.WaitForChild = methods.FindFirstChild
function methods:FindFirstChildOfClass(class)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.ClassName == class then
			return c
		end
	end
	return nil
end
function methods:GetChildren()
	return table.clone(rawget(self, "__children"))
end
function methods:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in ipairs(rawget(n, "__children")) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:IsA(class)
	return self.ClassName == class or (ISA[class] and ISA[class][self.ClassName]) or class == "Instance"
end
function methods:Destroy()
	self.Parent = nil
	rawget(self, "Destroying"):Fire()
end
function methods:SetAttribute(k, v)
	if rawget(self, "__attrs")[k] ~= v then
		rawget(self, "__attrs")[k] = v
		rawget(self, "AttributeChanged"):Fire(k)
	end
end
function methods:GetAttribute(k)
	return rawget(self, "__attrs")[k]
end
function methods:GetPropertyChangedSignal(prop)
	local list = rawget(self, "__changed")
	list[prop] = list[prop] or Signal()
	return list[prop]
end

-- services
local renders = {}
local RunService = {
	Heartbeat = Signal(),
	RenderStepped = Signal(),
	BindToRenderStep = function(_, name, prio, fn)
		renders[name] = { Prio = prio, Fn = fn }
	end,
	UnbindFromRenderStep = function(_, name)
		renders[name] = nil
	end,
	IsClient = function()
		return true
	end,
}
local TweenService = {
	Create = function(_, inst, _, goals)
		local tw = { Completed = Signal() }
		function tw:Play()
			for k, v in pairs(goals) do
				inst[k] = v
			end
		end
		function tw:Cancel() end
		return tw
	end,
}
local UIS = { InputBegan = Signal(), TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false, MouseEnabled = true }
local casBound = {}
local CAS = {
	BindActionAtPriority = function(_, name)
		casBound[name] = true
	end,
	UnbindAction = function(_, name)
		casBound[name] = nil
	end,
}
local Lighting = new("Lighting")
local RSf = new("Folder", "ReplicatedStorage")

-- the player, character, PlayerGui, main ScreenGui, HUD layers
local player = new("Player", "Player1")
rawset(player, "CharacterRemoving", Signal())
rawset(player, "CharacterAdded", Signal())
local pg = new("PlayerGui", "PlayerGui")
pg.Parent = player
local main = new("ScreenGui", "ScreenGui")
main.Parent = pg
local hud = new("Frame", "HUD")
hud.Parent = main
local hudLabel = new("TextLabel", "Coins")
hudLabel.TextTransparency = .1
hudLabel.Parent = hud
local mining = new("ScreenGui", "MiningGui")
mining.Parent = pg
local taggedLayer = new("ScreenGui", "SomeHUDLayer")
taggedLayer:SetAttribute("HideWithUI", true)
taggedLayer.Parent = pg
local keptLayer = new("ScreenGui", "RevealOverlay") -- not hideable (no tag)
keptLayer.Parent = pg
local character, hum
local function spawnCharacter()
	character = new("Model", "Character")
	hum = new("Humanoid", "Humanoid")
	hum.Health = 100
	rawset(hum, "Died", Signal())
	hum.Parent = character
	player.Character = character
end
spawnCharacter()
local scripts = new("PlayerScripts", "PlayerScripts")
scripts.Parent = player
local pm = new("ModuleScript", "PlayerModule")
pm.Parent = scripts
local controls = { controlsEnabled = true, Disables = 0, Enables = 0 }
function controls:Disable()
	self.controlsEnabled = false
	self.Disables += 1
end
function controls:Enable()
	self.controlsEnabled = true
	self.Enables += 1
end

-- camera
local camera = new("Camera", "Camera")
camera.CameraType = roblox.Enum.CameraType.Custom
camera.CFrame = roblox.CFrame.new(0, 10, 20)
camera.FieldOfView = 70
camera.CameraSubject = hum
local workspaceFake = { CurrentCamera = camera }

-- modules the Cinema reaches lazily
local mixerLog = {}
local Mixer = {
	Duck = function(reason, levels, fade)
		table.insert(mixerLog, { "Duck", reason, levels })
	end,
	Release = function(reason)
		table.insert(mixerLog, { "Release", reason })
	end,
}
local mixerInst = new("ModuleScript", "AudioMixer")
mixerInst.Parent = RSf
local hallow = new("Folder", "Halloween")
hallow.Parent = RSf
local sharedInst = new("ModuleScript", "Shared")
sharedInst.Parent = hallow
local fxInst = new("ModuleScript", "FX")
fxInst.Parent = hallow
local fxLog = {}
local SharedStub = {
	L = function(en)
		return en
	end,
	ReducedMotion = function()
		return player:GetAttribute("ReducedMotion") == true
	end,
	Quality = function()
		return "High"
	end,
}
local FXStub = {
	Shake = function(a)
		table.insert(fxLog, { "Shake", a })
	end,
	Punch = function(a)
		table.insert(fxLog, { "Punch", a })
	end,
}
local modules = {
	[mixerInst] = Mixer,
	[sharedInst] = SharedStub,
	[fxInst] = FXStub,
	[pm] = {
		GetControls = function()
			return controls
		end,
	},
}

local services = {
	Players = { LocalPlayer = player },
	RunService = RunService,
	TweenService = TweenService,
	UserInputService = UIS,
	ContextActionService = CAS,
	Lighting = Lighting,
	ReplicatedStorage = RSf,
}
local game = {
	GetService = function(_, name)
		return assert(services[name], "no service " .. name)
	end,
}
local warns = {}
local env = {
	game = game,
	workspace = workspaceFake,
	script = new("ModuleScript", "Cinema"),
	require = function(m)
		return assert(modules[m], "require of an unknown module")
	end,
	Instance = { new = new },
	Enum = roblox.Enum,
	Font = { fromEnum = function()
		return "FredokaOne"
	end },
	Color3 = roblox.Color3,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	TweenInfo = { new = function()
		return {}
	end },
	task = {
		delay = function(t, fn, ...)
			schedule(now + (t or 0), fn, ...)
		end,
		defer = function(fn, ...)
			schedule(now, fn, ...)
		end,
		spawn = function(fn, ...)
			if type(fn) == "thread" then
				coroutine.resume(fn, ...)
			else
				fn(...)
			end
		end,
		wait = function()
			return 0
		end,
	},
	os = setmetatable({ clock = function()
		return now
	end }, { __index = os }),
	warn = function(...)
		table.insert(warns, table.concat({ ... }, " "))
	end,
	typeof = typeof,
	print = print,
}
local Cinema = luau.load(fs.readFile(SRC), { debugName = "Cinema", environment = env })()

local function step(dt)
	now += dt
	table.sort(queue, function(a, b)
		return a.At < b.At
	end)
	while queue[1] and queue[1].At <= now + 1e-9 do
		local e = table.remove(queue, 1)
		e.Fn(table.unpack(e.Args, 1, e.Args.n))
	end
	RunService.Heartbeat:Fire(dt)
	local list = {}
	for name, r in pairs(renders) do
		table.insert(list, { Name = name, Prio = r.Prio, Fn = r.Fn })
	end
	table.sort(list, function(a, b)
		return a.Prio < b.Prio
	end)
	for _, r in ipairs(list) do
		if renders[r.Name] then
			r.Fn(dt)
		end
	end
end
local function run(seconds)
	local t = 0
	while t < seconds do
		step(1 / 60)
		t += 1 / 60
	end
end

---------------------------------------------------------------------------------------------------------------------
-- assertions
---------------------------------------------------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
	-- every test leaves the world idle
	run(3)
end
local function restored(label)
	assert(camera.CameraType == roblox.Enum.CameraType.Custom, label .. ": camera not Custom")
	assert(camera.CameraSubject == hum or camera.CameraSubject ~= nil, label .. ": no subject")
	assert(camera.FieldOfView == 70, label .. ": FOV " .. tostring(camera.FieldOfView))
	assert(main:GetAttribute("CinemaActive") == nil, label .. ": CinemaActive left set")
	assert(not casBound.DOGROTS_CinemaLock, label .. ": movement sink left bound")
	assert(controls.controlsEnabled == true, label .. ": controls left disabled")
	assert(main.Enabled == true and mining.Enabled == true and taggedLayer.Enabled == true, label .. ": interface left hidden")
	assert(math.abs(hudLabel.TextTransparency - .1) < 1e-9, label .. ": HUD transparency not restored")
	assert(renders.DOGROTS_Cinema == nil, label .. ": render step left bound")
	assert(not Cinema.Busy(), label .. ": still busy")
	assert(camera:FindFirstChild("DOGROTS_CinemaFocus") == nil, label .. ": DoF left on the camera")
	local ducks = 0
	for _, e in ipairs(mixerLog) do
		ducks += e[1] == "Duck" and 1 or -1
	end
	assert(ducks == 0, label .. ": duck / release unbalanced (" .. ducks .. ")")
end
local function shot(t)
	return roblox.CFrame.new(100 + t, 20, 50)
end

test("a full cinematic runs, owns the camera, then restores everything", function()
	local done, timeline = nil, {}
	local h = Cinema.Play({ Id = "Church", Duration = 4, Shot = shot, Fov = 50, Focus = { Target = roblox.Vector3.new(100, 20, 40), Radius = 10 },
		Timeline = { { 1, function()
			table.insert(timeline, 1)
		end }, { 2.5, function()
			table.insert(timeline, 2.5)
		end } },
		OnDone = function(ok, reason)
			done = { ok, reason }
		end })
	assert(h, "refused")
	run(.2)
	assert(camera.CameraType == roblox.Enum.CameraType.Scriptable, "camera scripted")
	assert(main:GetAttribute("CinemaActive") == true and main:GetAttribute("CinemaId") == "Church", "CinemaActive")
	assert(casBound.DOGROTS_CinemaLock and controls.controlsEnabled == false, "controls locked")
	assert(pg:FindFirstChild("DOGROTS_Cinema"), "letterbox")
	assert(camera:FindFirstChild("DOGROTS_CinemaFocus"), "camera-parented DoF")
	assert(mixerLog[#mixerLog][1] == "Duck" and mixerLog[#mixerLog][3] == "Cinematic", "duck preset")
	assert(Cinema.Busy(), "busy")
	run(1.5)
	assert(main.Enabled == false and mining.Enabled == false and taggedLayer.Enabled == false, "interface hidden")
	assert(keptLayer.Enabled == true, "untagged overlays are never touched")
	assert((camera.CFrame.Position - roblox.Vector3.new(101.7, 20, 50)).Magnitude < .5, "shot followed")
	run(3)
	assert(done and done[1] == true and done[2] == "Done", "OnDone(true, Done)")
	assert(#timeline == 2 and timeline[1] == 1, "timeline fired in order")
	restored("end")
end)

test("a skip after SkipAfter: OnSkip, the Always entries, a glide back, OnDone(true, Skipped)", function()
	local events = {}
	local h = Cinema.Play({ Id = "Skip", Duration = 10, Shot = shot, SkipAfter = .5,
		Timeline = { { 6, function()
			table.insert(events, "late")
		end }, { 8, function()
			table.insert(events, "always")
		end, Always = true } },
		OnSkip = function()
			table.insert(events, "skip")
		end,
		OnDone = function(ok, reason)
			table.insert(events, reason .. tostring(ok))
		end })
	assert(h, "refused")
	run(.2)
	UIS.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown }, false)
	assert(#events == 0, "input before SkipAfter is ignored")
	run(.5)
	UIS.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.Touch, KeyCode = roblox.Enum.KeyCode.Unknown }, true)
	run(1)
	assert(events[1] == "skip" and events[2] == "always" and events[3] == "Skippedtrue", table.concat(events, ","))
	assert(not table.find(events, "late"), "non-Always entries are dropped")
	local waited = { h.Done:Wait() }
	assert(waited[1] == true and waited[2] == "Skipped", "a late Wait returns at once")
	restored("skip")
end)

test("death mid-shot restores at once and reports Died", function()
	local result
	Cinema.Play({ Id = "Death", Duration = 8, Shot = shot, OnDone = function(ok, reason)
		result = { ok, reason }
	end })
	run(1)
	hum.Health = 0
	hum.Died:Fire()
	run(.5)
	assert(result and result[1] == false and result[2] == "Died", "Died")
	hum.Health = 100
	restored("death")
end)

test("character removal and Cancel both restore", function()
	local r1, r2
	Cinema.Play({ Id = "Removal", Duration = 8, Shot = shot, OnDone = function(ok, reason)
		r1 = reason
	end })
	run(.5)
	player.CharacterRemoving:Fire(character)
	run(.5)
	assert(r1 == "Character", "Character")
	restored("removal")
	local h = Cinema.Play({ Id = "Cancel", Duration = 8, Shot = shot, OnDone = function(ok, reason)
		r2 = { ok, reason }
	end })
	run(.5)
	h.Cancel()
	assert(r2[1] == false and r2[2] == "Cancelled", "Cancelled")
	run(.5)
	restored("cancel")
end)

test("a throwing Shot / Timeline / OnDone never strands the player", function()
	local result
	Cinema.Play({ Id = "Throws", Duration = 2, Shot = function()
		error("shot broke")
	end, Timeline = { { .5, function()
		error("timeline broke")
	end } }, OnDone = function(ok, reason)
		result = { ok, reason }
		error("ondone broke")
	end })
	run(3)
	assert(result and result[1] == true, "still finishes")
	restored("throws")
	-- a broken option during the build (Focus with a bad Target) is an Error with a full teardown
	local r2
	local h = Cinema.Play({ Id = "Bad", Duration = 2, Shot = shot, Timeline = "nope", OnDone = function(ok, reason)
		r2 = { ok, reason }
	end })
	run(3)
	assert(h ~= nil or (r2 and r2[1] == false), "handled")
	restored("bad build")
end)

test("refusals: busy, menu open, mining, non-Custom camera, dead; Force / Preempt override", function()
	local reasons = {}
	local function try(o)
		o.OnDone = function(ok, reason)
			table.insert(reasons, reason)
		end
		local h, why = Cinema.Play(o)
		run(.05)
		return h, why
	end
	local a = Cinema.Play({ Id = "A", Duration = 6, Shot = shot })
	local _, why = try({ Id = "B", Duration = 1, Shot = shot })
	assert(why == "Busy" and reasons[1] == "Busy", "busy")
	local b = Cinema.Play({ Id = "B2", Duration = 1, Shot = shot, Preempt = true })
	assert(b and a.Finished, "preempt cancels the running one")
	run(2)
	main:SetAttribute("OpenMenu", "Shop")
	_, why = try({ Id = "C", Duration = 1, Shot = shot })
	assert(why == "Menu", "menu")
	local forced = Cinema.Play({ Id = "Forced", Duration = .5, Force = true })
	assert(forced, "Force ignores menus")
	run(1)
	main:SetAttribute("OpenMenu", nil)
	main:SetAttribute("MiningActive", true)
	_, why = try({ Id = "D", Duration = 1, Shot = shot })
	assert(why == "Mining", "mining")
	main:SetAttribute("MiningActive", nil)
	camera.CameraType = roblox.Enum.CameraType.Scriptable
	_, why = try({ Id = "E", Duration = 1, Shot = shot })
	assert(why == "Camera", "camera")
	camera.CameraType = roblox.Enum.CameraType.Custom
	hum.Health = 0
	_, why = try({ Id = "F", Duration = 1 })
	assert(why == "Dead", "dead")
	hum.Health = 100
	restored("refusals")
end)

test("a menu opening mid-shot ends the cinematic as presented (OnSkip ran)", function()
	local events = {}
	Cinema.Play({ Id = "MenuMid", Duration = 8, Shot = shot, OnSkip = function()
		table.insert(events, "skip")
	end, OnDone = function(ok, reason)
		table.insert(events, reason .. tostring(ok))
	end })
	run(1)
	main:SetAttribute("OpenMenu", "Dogs")
	run(1)
	assert(events[1] == "skip" and events[2] == "Menutrue", table.concat(events, ","))
	-- the menu owns the controls now: the cinematic released its lock, controls come back when the menu closes
	main:SetAttribute("OpenMenu", nil)
	run(.2)
	restored("menu mid-shot")
end)

test("the control lock is ref-counted and never fights a menu", function()
	local d0, e0 = controls.Disables, controls.Enables
	Cinema.LockControls("a")
	Cinema.LockControls("b")
	assert(controls.controlsEnabled == false and controls.Disables == d0 + 1, "one Disable for two reasons")
	Cinema.Unlock("a")
	assert(controls.controlsEnabled == false, "b still holds")
	-- a menu opens (GUIIntegration sees the controls already disabled and leaves them alone)
	main:SetAttribute("OpenMenu", "Shop")
	run(.1)
	Cinema.Unlock("b")
	run(.1)
	assert(controls.controlsEnabled == false and controls.Enables == e0, "never re-enabled while a menu holds them")
	assert(not casBound.DOGROTS_CinemaLock, "the sink goes at once")
	main:SetAttribute("OpenMenu", nil)
	run(.1)
	assert(controls.controlsEnabled == true and controls.Enables == e0 + 1, "re-enabled when the menu closed")
	-- the other order: a menu disabled the controls first (GUIIntegration owns them)
	main:SetAttribute("OpenMenu", "Shop")
	controls:Disable() -- GUIIntegration
	local d1 = controls.Disables
	Cinema.LockControls("c")
	assert(controls.Disables == d1, "no Disable while the menu owns them")
	controls:Enable() -- GUIIntegration closes its menu
	main:SetAttribute("OpenMenu", nil)
	run(.1)
	assert(controls.controlsEnabled == false, "the lock takes over once the menu is gone")
	Cinema.Unlock("c")
	Cinema.Unlock("unknown")
	assert(controls.controlsEnabled == true and not Cinema.Locked(), "released")
end)

test("HideUI / ShowUI are ref-counted and keep a layer a script enabled meanwhile off until the release", function()
	Cinema.HideUI("x")
	Cinema.HideUI("y")
	run(.5)
	assert(main.Enabled == false and taggedLayer.Enabled == false, "hidden")
	mining.Enabled = true -- a script re-enables it while hidden
	assert(mining.Enabled == false, "held off")
	Cinema.ShowUI("x")
	run(.5)
	assert(main.Enabled == false, "y still hides")
	Cinema.ShowUI("y")
	run(.5)
	assert(main.Enabled == true and mining.Enabled == true and taggedLayer.Enabled == true, "shown again")
	assert(math.abs(hudLabel.TextTransparency - .1) < 1e-9, "transparency restored exactly")
end)

test("Fade lifts itself after MaxHold; Flash / Title / Impulse / Shake never throw", function()
	Cinema.Fade(1, .5, { MaxHold = 4 })
	run(1)
	local overlay = pg:FindFirstChild("DOGROTS_CinemaOverlay")
	assert(overlay and overlay.Fade.BackgroundTransparency == 0, "faded to black")
	assert(overlay.Fade.Active == false, "the fade never sinks input")
	run(5)
	assert(overlay.Fade.BackgroundTransparency == 1, "watchdog lifted the fade")
	Cinema.Flash(roblox.Color3.new(1, 1, 1), .8, .3)
	local t = Cinema.Title("THE UNDERYARD", "ПОДДВОРЬЕ", { Sub = { "BENEATH THE LAST BELL", "ПОД ПОСЛЕДНИМ КОЛОКОЛОМ" }, Duration = 1 })
	run(.5)
	assert(overlay:FindFirstChild("Title"), "title shown")
	run(3)
	assert(overlay:FindFirstChild("Title") == nil and not t.Alive, "title gone")
	Cinema.Shake(.5, .3)
	Cinema.Impulse(1, roblox.Vector3.new(1, 0, 0))
	run(1)
	assert(renders.DOGROTS_CinemaImpulse == nil, "impulse unbinds itself")
	player:SetAttribute("ReducedMotion", true)
	local before = #fxLog
	Cinema.Shake(1, 1)
	Cinema.Impulse(1)
	assert(#fxLog == before, "no shake / impulse with ReducedMotion")
	player:SetAttribute("ReducedMotion", nil)
end)

test("ReducedMotion: static cuts (no blend), still restores", function()
	player:SetAttribute("ReducedMotion", true)
	local positions = {}
	Cinema.Play({ Id = "Reduced", Duration = 3.4, CutEvery = 1, Shot = function(t)
		return roblox.CFrame.new(t * 10, 5, 5)
	end })
	for _ = 1, 150 do
		step(1 / 60)
		positions[math.floor(camera.CFrame.Position.X + .5)] = true
	end
	local distinct = 0
	for _ in pairs(positions) do
		distinct += 1
	end
	assert(distinct <= 4, "static cuts only, got " .. distinct .. " camera positions")
	run(2)
	player:SetAttribute("ReducedMotion", nil)
	restored("reduced")
end)

test("a shot-less cinematic keeps the player camera (letterbox + lock + duck only)", function()
	local done
	Cinema.Play({ Id = "Overlay", Duration = 1, OnDone = function(ok)
		done = ok
	end })
	run(.3)
	assert(camera.CameraType == roblox.Enum.CameraType.Custom, "camera untouched")
	assert(controls.controlsEnabled == false, "still locked")
	run(1.5)
	assert(done == true, "done")
	restored("overlay")
end)

test("shot helpers: Dolly holds and eases, Orbit circles the centre, Path interpolates keyframes", function()
	local V = roblox.Vector3
	local a, b = roblox.CFrame.new(0, 0, 0), roblox.CFrame.new(10, 0, 0)
	local dolly = Cinema.Dolly(a, b, 3, 1)
	assert(dolly(0).Position.X == 0 and dolly(1).Position.X == 0, "holds before t0")
	assert(math.abs(dolly(2).Position.X - 5) < 1e-6, "halfway")
	assert(dolly(9).Position.X == 10, "holds after t1")
	local orbit = Cinema.Orbit(V.new(0, 0, 100), 20, 8, 0, math.pi, 4)
	local p0, p1 = orbit(0).Position, orbit(4).Position
	assert((p0 - V.new(20, 8, 100)).Magnitude < 1e-4, "starts at angle 0")
	assert((p1 - V.new(-20, 8, 100)).Magnitude < 1e-4, "ends at angle pi")
	for t = 0, 4, .5 do
		local p = orbit(t).Position
		assert(math.abs((V.new(p.X, 0, p.Z) - V.new(0, 0, 100)).Magnitude - 20) < 1e-4, "stays on the circle")
	end
	local path = Cinema.Path({ { 2, b }, { 0, a }, { 4, roblox.CFrame.new(10, 10, 0) } })
	assert(path(-1).Position.X == 0 and path(1).Position.X == 5 and path(3).Position.Y == 5 and path(9).Position.Y == 10, "keys")
	local up = Cinema.LookAt(V.new(0, 0, 0), V.new(0, 10, 0))
	assert(up and (up.Position - V.new(0, 0, 0)).Magnitude < 1e-9, "vertical look-at is safe")
end)

print(string.format("cinema: %d passed, %d failed", passed, failed))
