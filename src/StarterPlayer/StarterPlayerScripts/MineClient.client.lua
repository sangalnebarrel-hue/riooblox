-- MineClient: the client half of the yard mines ("dogs dig DOWN", docs/MINE.md).
--  * Chunked, on-demand world: the shaft lining and the elevator cage of ONE yard (the yard whose
--    headframe the player is near, or whose mine the player is in) and at most TWO level interiors
--    (the level the player is in or riding to, plus the last one) exist at a time. Interiors are
--    cloned from per-layer design templates (MineLevels) and placed into the yard (MineStructures
--    .Place); everything is destroyed again a little after the player leaves.
--  * While inside a level: the level's mood (Ambient / Atmosphere overrides restored exactly on
--    leaving, an own ColorCorrectionEffect), ambient sound, the FINDS board with the player's own
--    collection, item previews on the pedestals, floating islands bobbing (TweenService only).
--  * Elevator: the headframe prompt and the stop prompt of every level open the MINE window
--    (Modules.MineScreen); MineState.Ride asks the server (MineRequest "Ride"), builds the target
--    level first, rides the cage down the shaft with the camera, then moves the character out.
--  * The head sheave of a headframe spins while anybody rides it (attribute RideSerial).
-- Nothing runs per frame while idle: a 0.25 s position check, event-driven updates, and frame
-- loops only during a ride or a wheel spin.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local MineFolder = RS:WaitForChild("Mine")
local Layout = require(MineFolder:WaitForChild("MineLayout"))
local Structures = require(MineFolder:WaitForChild("MineStructures"))
local Levels = require(MineFolder:WaitForChild("MineLevels"))
local Themes = require(MineFolder:WaitForChild("MineThemes"))
local State = require(MineFolder:WaitForChild("MineState"))

local district = workspace:WaitForChild("DOGROTS_District")
local yardsFolder = district:WaitForChild("04_PlayerYards")
local works = district:WaitForChild("MineWorks", 120)
local remote = RS:WaitForChild("MineRequest", 120) :: RemoteFunction?

local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui", 60)
local modules = gui and gui:WaitForChild("Modules", 60)
local Kit = modules and require(modules:WaitForChild("Kit")) :: any
local Net = modules and require(modules:WaitForChild("Net")) :: any

local C = Color3.fromRGB
local function T(en: string, ru: string): string
	return Kit and Kit.T(en, ru) or en
end
local function lang(): string
	return Kit and Kit.Lang() or "en"
end
local function toast(text: string, kind: string?)
	if Kit then
		Kit.Toast(text, { Kind = kind or "info", NoTranslate = true })
	end
end
local function reduced(): boolean
	if player:GetAttribute("ReducedMotion") then
		return true
	end
	return Kit ~= nil and Kit.Motion.Reduced()
end
local function lowFX(): boolean
	local choice = player:GetAttribute("WorldEventFX")
	return choice == "Low" or player:GetAttribute("LowFX") == true or (choice == nil and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

-- Client-only world container (WorldDetailQuality budgets its lights and emitters too).
local world = Instance.new("Folder")
world.Name = "MineClientWorld"
world.Parent = district

local function yardById(id: any): Model?
	if id == nil then
		return nil
	end
	for _, yard in yardsFolder:GetChildren() do
		if yard:GetAttribute("YardId") == id then
			return yard :: Model
		end
	end
	return nil
end
local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

------------------------------------------------------------------------------------------------
-- Screens
------------------------------------------------------------------------------------------------
local function openScreen(yardId: any)
	if not modules then
		return
	end
	local module = modules:FindFirstChild("MineScreen")
	if not module then
		return
	end
	local ok, screen = pcall(require, module)
	if ok and type(screen) == "table" and type(screen.Open) == "function" then
		local opened, err = pcall(screen.Open, { YardId = yardId })
		if not opened then
			warn("DOGROTS mine screen: " .. tostring(err))
		end
	end
end

------------------------------------------------------------------------------------------------
-- Mood: Ambient / Atmosphere overrides (restored exactly), own colour grade
------------------------------------------------------------------------------------------------
local Mood = {
	Active = false,
	Base = {},
	Last = {},
	AtmoBase = {},
	AtmoLast = {},
	Conns = {},
	Theme = nil :: any,
	Applied = false,
	Writing = false,
	Atmosphere = nil :: Atmosphere?,
	Grade = nil :: ColorCorrectionEffect?,
}
local LIGHT_KEYS = { "Ambient", "OutdoorAmbient" }
local ATMO_KEYS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local function eventBusy(): boolean
	local events = RS:FindFirstChild("WorldEvents")
	local s = events and events:FindFirstChild("State")
	local v = s and s:GetAttribute("State")
	return v == "ACTIVE" or v == "ENDING"
end
-- Writes our value unless someone else changed it since our last write; their value becomes the
-- new baseline, so leaving restores the live value (the server's day cycle keeps running).
local function drive(object: Instance, base: any, last: any, key: string, value: any)
	local current = (object :: any)[key]
	if current ~= last[key] then
		base[key] = current
	end
	;(object :: any)[key] = value
	last[key] = (object :: any)[key]
end
local function restore(object: Instance?, base: any, last: any, keys: { string })
	if not object then
		return
	end
	for _, key in keys do
		if base[key] ~= nil and (object :: any)[key] == last[key] then
			(object :: any)[key] = base[key]
		end
	end
end
local function moodApply(withGrade: boolean?)
	local theme = Mood.Theme
	if not Mood.Active or not theme or not theme.Lighting then
		return
	end
	local l = theme.Lighting
	if eventBusy() then
		-- A world event drives the lighting now: hand it back until the event ends.
		if Mood.Applied then
			restore(Lighting, Mood.Base, Mood.Last, LIGHT_KEYS)
			restore(Mood.Atmosphere, Mood.AtmoBase, Mood.AtmoLast, ATMO_KEYS)
			Mood.Applied = false
		end
	else
		if not Mood.Applied then
			for _, key in LIGHT_KEYS do
				Mood.Base[key] = (Lighting :: any)[key]
				Mood.Last[key] = (Lighting :: any)[key]
			end
			if Mood.Atmosphere then
				for _, key in ATMO_KEYS do
					Mood.AtmoBase[key] = (Mood.Atmosphere :: any)[key]
					Mood.AtmoLast[key] = (Mood.Atmosphere :: any)[key]
				end
			end
		end
		Mood.Applied = true
		Mood.Writing = true
		for _, key in LIGHT_KEYS do
			if l[key] then
				drive(Lighting, Mood.Base, Mood.Last, key, l[key])
			end
		end
		if Mood.Atmosphere and l.Atmosphere then
			for _, key in ATMO_KEYS do
				if l.Atmosphere[key] ~= nil then
					drive(Mood.Atmosphere, Mood.AtmoBase, Mood.AtmoLast, key, l.Atmosphere[key])
				end
			end
		end
		Mood.Writing = false
	end
	local grade = Mood.Grade
	if withGrade and grade and l.Grade then
		local goals = { TintColor = l.Grade.TintColor, Saturation = l.Grade.Saturation, Contrast = l.Grade.Contrast, Brightness = l.Grade.Brightness }
		if reduced() then
			for k, v in goals do
				(grade :: any)[k] = v
			end
		else
			TweenService:Create(grade, TweenInfo.new(0.8, Enum.EasingStyle.Sine), goals):Play()
		end
	end
end
local reapplyQueued = false
local function queueReapply()
	if Mood.Writing or reapplyQueued then
		return
	end
	reapplyQueued = true
	task.delay(0.1, function()
		reapplyQueued = false
		moodApply()
	end)
end
function Mood.Begin(theme: any)
	Mood.Theme = theme
	if not Mood.Active then
		Mood.Active = true
		Mood.Applied = false
		Mood.Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "DOGROTS_MineGrade"
		grade.Parent = Lighting
		Mood.Grade = grade
		for _, key in LIGHT_KEYS do
			table.insert(Mood.Conns, Lighting:GetPropertyChangedSignal(key):Connect(queueReapply))
		end
		if Mood.Atmosphere then
			for _, key in ATMO_KEYS do
				table.insert(Mood.Conns, Mood.Atmosphere:GetPropertyChangedSignal(key):Connect(queueReapply))
			end
		end
		local events = RS:FindFirstChild("WorldEvents")
		local s = events and events:FindFirstChild("State")
		if s then
			table.insert(Mood.Conns, s:GetAttributeChangedSignal("State"):Connect(queueReapply))
		end
	end
	moodApply(true)
end
function Mood.End()
	if not Mood.Active then
		return
	end
	for _, c in Mood.Conns do
		c:Disconnect()
	end
	Mood.Conns = {}
	if Mood.Applied then
		restore(Lighting, Mood.Base, Mood.Last, LIGHT_KEYS)
		restore(Mood.Atmosphere, Mood.AtmoBase, Mood.AtmoLast, ATMO_KEYS)
	end
	if Mood.Grade then
		Mood.Grade:Destroy()
	end
	Mood.Active, Mood.Applied, Mood.Theme, Mood.Grade, Mood.Atmosphere = false, false, nil, nil, nil
	Mood.Base, Mood.Last, Mood.AtmoBase, Mood.AtmoLast = {}, {}, {}, {}
end

------------------------------------------------------------------------------------------------
-- Sound (built-in client sounds only: the game ships no uploaded SFX)
------------------------------------------------------------------------------------------------
local FALLING = "rbxasset://sounds/action_falling.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local CLANK = "rbxasset://sounds/collide.wav"
local function sound(id: string, volume: number, speed: number, parent: Instance?, looped: boolean?, effects: any?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Looped = looped == true
	for class, props in effects or {} do
		local e = Instance.new(class)
		for k, v in props do
			(e :: any)[k] = v
		end
		e.Parent = s
	end
	s.Parent = parent or SoundService
	return s
end
local function shot(id: string, volume: number, speed: number, effects: any?)
	local s = sound(id, volume, speed, nil, false, effects)
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
local CAVE = { ReverbSoundEffect = { DecayTime = 2.4, WetLevel = -2, DryLevel = -4, Density = 1, Diffusion = 1 } }
local DRONE = { EqualizerSoundEffect = { LowGain = 4, MidGain = -6, HighGain = -30 }, ReverbSoundEffect = { DecayTime = 3, WetLevel = -6 } }

local Ambient = { Drone = nil :: Sound?, Token = 0 }
function Ambient.Start(theme: any)
	Ambient.Stop()
	local spec = theme.Sound
	if not spec then
		return
	end
	Ambient.Token += 1
	local token = Ambient.Token
	local drone = sound(FALLING, spec.DroneVolume or 0.14, spec.Drone or 0.35, nil, true, DRONE)
	drone.Name = "MineAmbience"
	drone:Play()
	Ambient.Drone = drone
	local function cue()
		if Ambient.Token ~= token then
			return
		end
		if spec.Drips then
			shot(WATER, 0.22, (spec.DripPitch or 1.6) + math.random() * 0.6, CAVE)
		elseif spec.Pings then
			shot(PING, 0.12, 0.3 + math.random() * 0.15, CAVE)
		elseif spec.Rumble then
			shot(LAND, 0.3, 0.22 + math.random() * 0.08, { DistortionSoundEffect = { Level = 0.4 }, ReverbSoundEffect = { DecayTime = 2.6, WetLevel = -4 } })
		elseif spec.Wind then
			shot(FALLING, 0.06, 0.9 + math.random() * 0.2, CAVE)
		end
		task.delay(3 + math.random() * 5, cue)
	end
	task.delay(1.5, cue)
end
function Ambient.Stop()
	Ambient.Token += 1
	if Ambient.Drone then
		Ambient.Drone:Destroy()
		Ambient.Drone = nil
	end
end

------------------------------------------------------------------------------------------------
-- Text helpers for world labels and prompts
------------------------------------------------------------------------------------------------
local function themeName(layer: number): string
	return Themes.Name(layer, lang())
end
local function localizeElevatorPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("MinePrompt") == "Elevator" then
		prompt.ActionText = T("Ride the elevator", "Спуститься на лифте")
		prompt.ObjectText = T("MINE", "ШАХТА")
	end
end
if works then
	for _, d in works:GetDescendants() do
		localizeElevatorPrompt(d)
	end
end

------------------------------------------------------------------------------------------------
-- Level interiors (max 2 alive) and the shaft lining + cage of one yard
------------------------------------------------------------------------------------------------
local templates = {}
local function template(layer: number): Model
	local low = lowFX()
	local key = layer .. (low and "L" or "H")
	if not templates[key] then
		templates[key] = Levels.Build(layer, { LowFX = low })
	end
	return templates[key]
end

local levels = {} -- key -> {Model, Yard, Layer, Tweens, Conns, LastUsed, Previews}
local function levelKey(yard: Instance, layer: number): string
	return tostring(yard:GetAttribute("YardId")) .. ":" .. layer
end
local function destroyLevel(key: string)
	local entry = levels[key]
	if not entry then
		return
	end
	levels[key] = nil
	for _, t in entry.Tweens do
		t:Cancel()
	end
	for _, c in entry.Conns do
		c:Disconnect()
	end
	entry.Model:Destroy()
end

local itemDefs = nil
local function defs(): any
	if itemDefs == nil then
		local ok, d = pcall(function()
			return require(RS:WaitForChild("DogEconomy"):WaitForChild("ItemDefinitions"))
		end)
		itemDefs = ok and d or {}
	end
	return itemDefs
end
local function collection(): any
	local snapshot = Net and Net.Cached()
	local profile = snapshot and snapshot.Profile
	return type(profile) == "table" and type(profile.Collection) == "table" and profile.Collection or {}
end

-- The FINDS board: the player's own collection of this depth.
local function updateBoard(entry: any)
	local theme = Themes.Get(entry.Layer)
	local board = entry.Model:FindFirstChild("FindsBoard", true)
	local surface = board and board:FindFirstChild("FindsBoardGui")
	local back = surface and surface:FindFirstChild("Back")
	if not back then
		return
	end
	local owned = collection()
	local items = Levels.Items(entry.Layer)
	local found = 0
	local grid = back:FindFirstChild("Grid")
	for _, id in items do
		local has = owned[id] == true
		if has then
			found += 1
		end
		local cell = grid and grid:FindFirstChild("Item_" .. id)
		if cell and cell:IsA("Frame") then
			cell.BackgroundColor3 = has and theme.Accent:Lerp(C(0, 0, 0), 0.55) or C(40, 38, 46)
			local mark = cell:FindFirstChild("Mark")
			if mark and mark:IsA("TextLabel") then
				mark.Text = has and "✓" or "?"
				mark.TextColor3 = has and C(130, 255, 160) or C(120, 118, 130)
			end
			local name = cell:FindFirstChild("ItemName")
			if name and name:IsA("TextLabel") then
				name.TextColor3 = has and C(255, 255, 255) or C(150, 148, 160)
			end
		end
	end
	local title = back:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = "FINDS AT THIS DEPTH"
	end
	local count = back:FindFirstChild("Count")
	if count and count:IsA("TextLabel") then
		count.Text = found .. " / " .. #items
	end
end

-- Pedestals: the three rarest finds of this depth the player owns (or still has to find, as a
-- dark silhouette), as small 3D previews floating over the pedestals.
local function updatePedestals(entry: any)
	for _, g in entry.Previews or {} do
		g:Destroy()
	end
	entry.Previews = {}
	local owned = collection()
	local items = table.clone(Levels.Items(entry.Layer))
	local d = defs()
	table.sort(items, function(a, b)
		local fa, fb = owned[a] == true, owned[b] == true
		if fa ~= fb then
			return fa
		end
		local ca = d[a] and d[a].BaseDropChance or 1
		local cb = d[b] and d[b].BaseDropChance or 1
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	local visuals = nil
	pcall(function()
		visuals = require(RS:WaitForChild("DogEconomy"):WaitForChild("DiscoveryVisuals"))
	end)
	for i = 1, 3 do
		local id = items[i]
		local anchor = entry.Model:FindFirstChild("Pedestal" .. i, true)
		if id and anchor and anchor:IsA("Attachment") then
			local has = owned[id] == true
			local bb = Instance.new("BillboardGui")
			bb.Name = "MinePedestalPreview"
			bb.Adornee = anchor
			bb.Size = UDim2.fromScale(3, 3.7)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
			bb.MaxDistance = 45
			bb.LightInfluence = 0
			bb.Parent = anchor
			local view = nil
			if visuals then
				local ok, frame = pcall(visuals.Preview, bb, { ItemId = id, Mutation = "NORMAL" }, 0, 0, 120, 120)
				if ok and frame then
					view = frame
					frame.Size = UDim2.fromScale(1, 0.78)
					frame.Position = UDim2.fromScale(0, 0)
					frame.BackgroundTransparency = 1
					if not has then
						frame.ImageColor3 = C(0, 0, 0)
						frame.ImageTransparency = 0.15
					end
				end
			end
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0, view and 0.78 or 0.6)
			label.Size = UDim2.fromScale(1, 0.22)
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = has and C(255, 236, 170) or C(170, 170, 180)
			label.TextStrokeTransparency = 0.4
			label.Text = has and Levels.ItemName(id) or "???"
			if not has then
				label:SetAttribute("NoTranslate", true)
			end
			label.Parent = bb
			table.insert(entry.Previews, bb)
		end
	end
end

local function decorateLevel(entry: any)
	local model = entry.Model
	local theme = Themes.Get(entry.Layer)
	-- Elevator stop prompt.
	local anchor = model:FindFirstChild("StopAnchor", true)
	if anchor then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MineStopPrompt"
		prompt.ActionText = T("Elevator", "Лифт")
		prompt.ObjectText = themeName(entry.Layer)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("MinePrompt", "Stop")
		prompt:SetAttribute("YardId", entry.Yard:GetAttribute("YardId"))
		prompt.Parent = anchor
	end
	updateBoard(entry)
	updatePedestals(entry)
	if Net then
		local last = 0
		table.insert(entry.Conns, Net.Changed:Connect(function()
			if os.clock() - last > 2 then
				last = os.clock()
				updateBoard(entry)
			end
		end))
	end
	-- Floating islands and other bobbing parts.
	if not reduced() then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("MineBob") then
				local amp = d:GetAttribute("MineBob") or 1
				local period = d:GetAttribute("MineBobPeriod") or 3
				local tween = TweenService:Create(d, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = d.CFrame + Vector3.new(0, amp, 0) })
				tween:Play()
				table.insert(entry.Tweens, tween)
			end
		end
	end
	model:SetAttribute("Theme", theme.Key)
end

local function trimLevels(keep: { [string]: boolean })
	local list = {}
	for key, entry in levels do
		table.insert(list, { key, entry.LastUsed })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local alive = 0
	for _, row in list do
		alive += 1
		if alive > 2 and not keep[row[1]] then
			destroyLevel(row[1])
		end
	end
end

local function ensureLevel(yard: Model, layer: number): any
	if layer < 2 then
		return nil
	end
	local key = levelKey(yard, layer)
	local entry = levels[key]
	if entry then
		entry.LastUsed = os.clock()
		return entry
	end
	local layout = Layout.ForYard(yard)
	if not layout then
		return nil
	end
	local model = template(layer):Clone()
	Structures.Place(model, layout)
	model.Name = "MineLevel_" .. key
	entry = { Model = model, Yard = yard, Layer = layer, Tweens = {}, Conns = {}, LastUsed = os.clock(), Previews = {} }
	levels[key] = entry
	decorateLevel(entry)
	model.Parent = world
	trimLevels({ [key] = true })
	return entry
end

local Shaft = { Yard = nil :: Model?, Lining = nil :: Model?, Cage = nil :: Model?, CageLayer = 1, LeftAt = 0 }
local function destroyShaft()
	if Shaft.Lining then
		Shaft.Lining:Destroy()
	end
	if Shaft.Cage then
		Shaft.Cage:Destroy()
	end
	Shaft.Yard, Shaft.Lining, Shaft.Cage = nil, nil, nil
end
-- Assigned below (station doors, counterweight and rope follow this client's cage).
local syncStation: (yard: Model, layout: any) -> () = function() end
local function cageCF(layout: any, y: number): CFrame
	return layout:ToWorld(CFrame.new(Layout.Shaft.X, y, Layout.Shaft.Z))
end
local function ensureShaft(yard: Model): boolean
	if Shaft.Yard == yard and Shaft.Lining and Shaft.Lining.Parent then
		return true
	end
	destroyShaft()
	local layout = Layout.ForYard(yard)
	if not layout then
		return false
	end
	local lining = Structures.Lining()
	Structures.Place(lining, layout)
	lining.Parent = world
	local cage = Structures.Cage()
	Structures.Place(cage, layout)
	cage:PivotTo(cageCF(layout, Layout.StopY(Shaft.CageLayer) or Layout.GroundY))
	cage.Parent = world
	Shaft.Yard, Shaft.Lining, Shaft.Cage = yard, lining, cage
	syncStation(yard, layout)
	return true
end

------------------------------------------------------------------------------------------------
-- Head sheave spin while somebody rides (any client near the headframe)
------------------------------------------------------------------------------------------------
local function rideSeconds(from: number?, to: number?): number
	local a = Layout.StopY(from or 1) or Layout.GroundY
	local b = Layout.StopY(to or 1) or Layout.GroundY
	if reduced() then
		return 1.0
	end
	return math.clamp(math.abs(a - b) / 42 + 1.4, 2.2, 5.5)
end
local spinning = {}
local function spinWheel(headframe: Instance, seconds: number, down: boolean)
	local wheel = headframe:FindFirstChild("Wheel", true)
	local axle = wheel and wheel:FindFirstChild("Axle")
	if not wheel or not axle or not axle:IsA("BasePart") or spinning[wheel] then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - axle.Position).Magnitude > 260 then
		return
	end
	spinning[wheel] = true
	local center, axis = axle.Position, axle.CFrame.RightVector
	local parts = {}
	for _, d in wheel:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { d, d.CFrame })
		end
	end
	local started = os.clock()
	local angle = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		if t >= seconds or not wheel.Parent then
			connection:Disconnect()
			spinning[wheel] = nil
			return
		end
		-- Speeds up and slows down with the cage (radians per second).
		angle += (down and 1 or -1) * math.sin(math.min(1, t / seconds) * math.pi) * 4 * dt
		local turn = CFrame.new(center) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-center)
		for _, row in parts do
			row[1].CFrame = turn * row[2]
		end
	end)
end
local function watchHeadframe(headframe: Instance)
	if not headframe:IsA("Model") or headframe.Name ~= "Headframe" then
		return
	end
	headframe:GetAttributeChangedSignal("RideSerial"):Connect(function()
		local at = headframe:GetAttribute("RideAt") or 0
		if workspace:GetServerTimeNow() - at > 3 then
			return
		end
		local from, to = headframe:GetAttribute("RideFrom"), headframe:GetAttribute("RideTo")
		spinWheel(headframe, rideSeconds(from, to), (to or 1) > (from or 1))
	end)
end
if works then
	for _, d in works:GetDescendants() do
		watchHeadframe(d)
	end
	works.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(localizeElevatorPrompt, d)
		elseif d:IsA("Model") and d.Name == "Headframe" then
			task.defer(watchHeadframe, d)
		end
	end)
end

------------------------------------------------------------------------------------------------
-- Location: which mine / level the player is in; chunk management
------------------------------------------------------------------------------------------------
local riding = false
local current = { Yard = nil :: Model?, Layer = 1, Kind = nil :: string? }
local leftMineAt = os.clock()
local announced = {}

local function nearestHeadframeYard(pos: Vector3): Model?
	local best, bestD = nil, 95
	for _, yard in yardsFolder:GetChildren() do
		if yard:GetAttribute("YardId") ~= nil then
			local layout = Layout.ForYard(yard)
			if layout then
				local top = layout:Point(Layout.Shaft.X, Layout.GroundY, Layout.Shaft.Z)
				local d = (pos - top).Magnitude
				if d < bestD then
					best, bestD = yard :: Model, d
				end
			end
		end
	end
	return best
end

local function enterLevel(yard: Model, layer: number)
	local theme = Themes.Get(layer)
	Mood.Begin(theme)
	Ambient.Start(theme)
	local key = levelKey(yard, layer)
	if not announced[key] or os.clock() - announced[key] > 60 then
		announced[key] = os.clock()
		toast(themeName(layer) .. " · " .. Themes.DepthText(layer, lang()), "info")
	end
end
local function leaveLevel()
	Mood.End()
	Ambient.Stop()
end

local function setLocation(yard: Model?, layer: number, kind: string?)
	local wasLevel = current.Kind == "Level" and current.Yard == yard and current.Layer == layer
	local nowLevel = kind == "Level" and yard ~= nil
	if nowLevel and not wasLevel and yard then
		enterLevel(yard, layer)
	elseif not nowLevel and current.Kind == "Level" then
		leaveLevel()
	end
	current.Yard, current.Layer, current.Kind = yard, layer, kind
	State.Set({ YardId = yard and yard:GetAttribute("YardId") or nil, Layer = layer, Kind = kind }, nil)
end

local function update()
	if riding then
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	local pos = root.Position
	local yard, _, kind, layer = Layout.Find(yardsFolder, pos)
	local inLevel = kind == "Level" or (kind == "Shaft" and (layer or 1) >= 2)
	if yard then
		leftMineAt = os.clock()
		if inLevel then
			ensureLevel(yard :: Model, layer or 2)
		end
	end
	setLocation(yard :: Model?, yard and (layer or 1) or 1, inLevel and "Level" or kind)
	-- Shaft lining + cage: the mine the player is in, else the nearest headframe.
	local shaftYard = (yard :: Model?) or nearestHeadframeYard(pos)
	if shaftYard then
		Shaft.LeftAt = os.clock()
		if Shaft.Yard ~= shaftYard then
			Shaft.CageLayer = 1
			ensureShaft(shaftYard)
		end
	elseif Shaft.Yard and os.clock() - Shaft.LeftAt > 12 then
		destroyShaft()
	end
	-- Out of every mine for a while: drop the interiors.
	if not yard and os.clock() - leftMineAt > 20 then
		for key in levels do
			destroyLevel(key)
		end
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.25 then
		return
	end
	elapsed = 0
	debug.profilebegin("MineClient")
	update()
	debug.profileend()
end)

------------------------------------------------------------------------------------------------
-- Elevator ride
------------------------------------------------------------------------------------------------
local function rootOffset(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end
local function placeCharacter(character: Model, root: BasePart, feet: CFrame)
	local target = feet + Vector3.new(0, rootOffset(character, root) + 0.15, 0)
	character:PivotTo(target * root.CFrame:Inverse() * character:GetPivot())
end
local function waitForFloor(position: Vector3, timeout: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character or world }
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -9, 0), params)
		if hit then
			return true
		end
		task.wait(0.1)
	end
	return false
end

------------------------------------------------------------------------------------------------
-- Station pieces this client animates for its own cage: freight doors, counterweight, ropes
------------------------------------------------------------------------------------------------
local function headframeOf(yard: Model): Instance?
	local root = works and works:FindFirstChild(yard.Name .. "_Mine")
	return root and root:FindFirstChild("Headframe") or nil
end
local doorBase = setmetatable({}, { __mode = "k" }) -- part -> open CFrame
local function setDoors(yard: Model, closed: number, seconds: number)
	local headframe = headframeOf(yard)
	local doors = headframe and headframe:FindFirstChild("Doors", true)
	if not doors then
		return
	end
	for _, leaf in doors:GetChildren() do
		local slide = leaf:GetAttribute("Slide")
		if type(slide) == "number" then
			for _, p in leaf:GetDescendants() do
				if p:IsA("BasePart") then
					doorBase[p] = doorBase[p] or p.CFrame
					local goal = doorBase[p] + Vector3.new(0, slide * closed, 0)
					if seconds > 0 and not reduced() then
						TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
					else
						p.CFrame = goal
					end
				end
			end
		end
	end
end
local weightBase = setmetatable({}, { __mode = "k" })
-- depth: 0 = cage at the surface, 1 = at the Void stop. The counterweight falls as the cage rises.
local function setCounterweight(yard: Model, depth: number)
	local headframe = headframeOf(yard)
	local cw = headframe and headframe:FindFirstChild("Counterweight", true)
	if not cw then
		return
	end
	local travel = cw:GetAttribute("Travel") or 7
	local offset = travel * (1 - 2 * math.clamp(depth, 0, 1))
	local hookY = nil
	for _, p in cw:GetDescendants() do
		if p:IsA("BasePart") then
			weightBase[p] = weightBase[p] or p.CFrame
			p.CFrame = weightBase[p] + Vector3.new(0, offset, 0)
			if p.Name == "WeightHook" then
				hookY = p.Position.Y + p.Size.Y / 2
			end
		end
	end
	local rope = headframe:FindFirstChild("CounterRope", true)
	if rope and rope:IsA("BasePart") and hookY then
		local top = rope:GetAttribute("TopY") or (rope.Position.Y + rope.Size.X / 2)
		local x, z = rope.Position.X, rope.Position.Z
		local len = math.max(0.2, top - hookY)
		rope.Size = Vector3.new(len, rope.Size.Y, rope.Size.Z)
		rope.CFrame = CFrame.new(x, hookY + len / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	end
end
-- The cage's hoist rope runs from the cage hook up to the machine room floor of the station.
local function fitCageRope(layout: any, y: number)
	local cage = Shaft.Cage
	local rope = cage and cage:FindFirstChild("CageRope", true)
	if not (rope and rope:IsA("BasePart")) then
		return
	end
	local topY = Structures.RopeTopY or (Layout.GroundY + 20)
	local bottom = layout:Point(Layout.Shaft.X, y + (Structures.CageHeight or 8.2) + 1.3, Layout.Shaft.Z)
	local len = math.max(0.2, topY - bottom.Y)
	rope.Size = Vector3.new(len, rope.Size.Y, rope.Size.Z)
	rope.CFrame = CFrame.new(bottom.X, bottom.Y + len / 2, bottom.Z) * CFrame.Angles(0, 0, math.pi / 2)
end

syncStation = function(yard: Model, layout: any)
	local y = Layout.StopY(Shaft.CageLayer) or Layout.GroundY
	fitCageRope(layout, y)
	setDoors(yard, Shaft.CageLayer == 1 and 0 or 1, 0)
	local bottomY = Layout.StopY(5) or -160
	setCounterweight(yard, (Layout.GroundY - y) / math.max(1, Layout.GroundY - bottomY))
end

------------------------------------------------------------------------------------------------
-- Ride presentation: a fade, a cinematic but safe shot inside the shaft, a depth readout
------------------------------------------------------------------------------------------------
local rideGui = Instance.new("ScreenGui")
rideGui.Name = "MineRide"
rideGui.IgnoreGuiInset = true
rideGui.ResetOnSpawn = false
rideGui.DisplayOrder = 90
rideGui:SetAttribute("NoTranslate", true)
rideGui.Parent = player:WaitForChild("PlayerGui")
local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundColor3 = C(6, 8, 14)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Parent = rideGui
local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "Depth"
depthLabel.AnchorPoint = Vector2.new(0.5, 1)
depthLabel.Position = UDim2.new(0.5, 0, 1, -34)
depthLabel.Size = UDim2.fromOffset(420, 52)
depthLabel.BackgroundColor3 = C(14, 18, 30)
depthLabel.BackgroundTransparency = 0.25
depthLabel.TextColor3 = C(255, 255, 255)
depthLabel.TextScaled = true
depthLabel.Font = Enum.Font.Arcade
depthLabel.Visible = false
depthLabel:SetAttribute("NoTranslate", true)
depthLabel.Parent = rideGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = depthLabel
	local st = Instance.new("UIStroke")
	st.Name = "Accent"
	st.Thickness = 3
	st.Color = C(110, 214, 255)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = depthLabel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = depthLabel
end
local function fadeTo(alpha: number, seconds: number)
	if reduced() then
		seconds = math.min(seconds, 0.08)
	end
	local tween = TweenService:Create(fade, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 - alpha })
	tween:Play()
	task.wait(seconds)
end
-- Pulls a wanted camera position in before walls (the character, the cage and the shaft lining
-- never block: they are part of the shot).
local function safeEye(from: Vector3, wanted: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local dir = wanted - from
	local hit = workspace:Raycast(from, dir, params)
	if hit then
		return hit.Position - dir.Unit * 0.8
	end
	return wanted
end

local function rideSequence(yard: Model, layout: any, fromLayer: number, layer: number, arrival: CFrame)
	local character = player.Character
	local root = rootPart()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	ensureShaft(yard)
	if layer >= 2 then
		ensureLevel(yard, layer)
	end
	pcall(function()
		player:RequestStreamAroundAsync(arrival.Position, 3)
	end)
	waitForFloor(arrival.Position, 3)
	local camera = workspace.CurrentCamera
	local fromY = Layout.StopY(fromLayer) or Layout.GroundY
	local toY = Layout.StopY(layer) or Layout.GroundY
	local bottomY = Layout.StopY(5) or -160
	local seconds = rideSeconds(fromLayer, layer)
	local still = reduced()
	local cage = Shaft.Cage
	local facing = arrival.Rotation
	local function at(y: number): CFrame
		return cageCF(layout, y)
	end
	local function depthOf(y: number): number
		return (Layout.GroundY - y) / math.max(1, Layout.GroundY - bottomY)
	end
	-- Doors shut, the screen dips to black and the shot moves inside the shaft (no camera ever
	-- travels through the station walls).
	if fromLayer == 1 then
		setDoors(yard, 1, 0.45)
	end
	shot(CLANK, 0.4, 0.6)
	fadeTo(1, 0.28)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	placeCharacter(character, root, CFrame.new(at(fromY).Position) * facing)
	if cage then
		cage:PivotTo(at(fromY))
	end
	fitCageRope(layout, fromY)
	-- The cage roof (and its lamp and hook) would block the shot from above: hidden locally.
	local hidden = {}
	if cage then
		for _, d in cage:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "CageRoof" or d.Name == "CageLamp" or d.Name == "CageHook") then
				d.LocalTransparencyModifier = 1
				table.insert(hidden, d)
			end
		end
	end
	local previousType = camera.CameraType
	local previousFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = still and previousFov or 76
	local theme = Themes.Get(layer)
	local accent = depthLabel:FindFirstChild("Accent")
	if accent and accent:IsA("UIStroke") then
		accent.Color = theme.Accent
	end
	depthLabel.Visible = true
	local hum = sound(FALLING, 0.18, 0.55, nil, true, DRONE)
	hum:Play()
	local started = os.clock()
	local done = false
	local angle0 = math.random() * math.pi * 2
	local function shotAt(y: number, t: number): CFrame
		-- Above the rider inside the 8 x 8 shaft, slowly circling the cable, looking down at the
		-- rider's head: the lining, lamps and level openings stream past.
		local a = angle0 + (still and 0 or t * 0.55)
		local r = 1.6
		local eye = layout:Point(Layout.Shaft.X + math.cos(a) * r, y + 11.2, Layout.Shaft.Z + math.sin(a) * r)
		local focus = layout:Point(Layout.Shaft.X, y + 3.4 + (toY < fromY and -1.5 or 1.5), Layout.Shaft.Z)
		local shake = still and Vector3.zero or Vector3.new(math.sin(os.clock() * 29) * 0.04, math.sin(os.clock() * 21) * 0.035, 0)
		return CFrame.lookAt(eye + shake, focus)
	end
	camera.CFrame = shotAt(fromY, 0)
	task.spawn(fadeTo, 0, 0.35)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - started) / seconds)
		local a = t * t * (3 - 2 * t)
		local y = fromY + (toY - fromY) * a
		local cf = at(y)
		if cage then
			cage:PivotTo(cf)
		end
		fitCageRope(layout, y)
		setCounterweight(yard, depthOf(y))
		placeCharacter(character, root, CFrame.new(cf.Position) * facing)
		camera.CFrame = shotAt(y, os.clock() - started)
		local meters = math.max(0, math.floor((Layout.GroundY - y) * 0.5 + 0.5))
		depthLabel.Text = (toY < fromY and "▼ " or "▲ ") .. themeName(layer) .. "  ·  " .. meters .. (lang() == "ru" and " м" or " m")
		if t >= 1 then
			done = true
			connection:Disconnect()
		end
	end)
	while not done and character.Parent and humanoid.Health > 0 do
		task.wait()
	end
	if connection.Connected then
		connection:Disconnect()
	end
	hum:Destroy()
	shot(CLANK, 0.5, 0.45)
	Shaft.CageLayer = layer
	setCounterweight(yard, depthOf(toY))
	-- Step out: dip to black, then a safe follow shot from inside the cage behind the rider until
	-- they are out of the shaft, then the normal camera.
	fadeTo(1, 0.22)
	for _, d in hidden do
		if d.Parent then
			d.LocalTransparencyModifier = 0
		end
	end
	depthLabel.Visible = false
	if character.Parent and humanoid.Health > 0 then
		placeCharacter(character, root, arrival)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = false
	end
	if layer == 1 then
		setDoors(yard, 0, 0.5)
	end
	local ignore = { character, world }
	local look = arrival.LookVector
	local function follow(): CFrame
		local r = rootPart()
		local pos = r and r.Position or arrival.Position
		local head = pos + Vector3.new(0, 1.6, 0)
		local wanted = head - look * 6.5 + Vector3.new(0, 3.2, 0)
		return CFrame.lookAt(safeEye(head, wanted, ignore), head + look * 5 - Vector3.new(0, 0.6, 0))
	end
	camera.FieldOfView = previousFov
	camera.CFrame = follow()
	task.spawn(fadeTo, 0, 0.3)
	local shaftCenter = layout:Point(Layout.Shaft.X, 0, Layout.Shaft.Z)
	local followStart = os.clock()
	local following = true
	local followConn
	followConn = RunService.RenderStepped:Connect(function(dt)
		local r = rootPart()
		local flat = r and Vector3.new(r.Position.X - shaftCenter.X, 0, r.Position.Z - shaftCenter.Z).Magnitude or 99
		if not r or flat > 9.5 or os.clock() - followStart > 2.6 or not character.Parent then
			following = false
			followConn:Disconnect()
			return
		end
		camera.CFrame = camera.CFrame:Lerp(follow(), math.min(1, dt * 8))
	end)
	while following do
		task.wait()
	end
	camera.CameraType = previousType ~= Enum.CameraType.Scriptable and previousType or Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end

function State.Ride(yardId: any, layer: number): (boolean, string?)
	if riding then
		return false, T("The elevator is moving", "Лифт уже едет")
	end
	local yard = yardById(yardId)
	local layout = yard and Layout.ForYard(yard)
	if not yard or not layout or not remote then
		return false, T("The mine is not ready yet", "Шахта ещё не готова")
	end
	local ok, okServer, result = pcall(function()
		return (remote :: RemoteFunction):InvokeServer("Ride", { YardId = yardId, Layer = layer })
	end)
	if not ok then
		return false, T("Connection problem; try again", "Проблема со связью, попробуй ещё раз")
	end
	if not okServer or type(result) ~= "table" or typeof(result.Arrival) ~= "CFrame" then
		return false, type(result) == "string" and result or T("Invalid request", "Неверный запрос")
	end
	riding = true
	State.Set(nil, true)
	leaveLevel()
	local from = tonumber(result.From) or 1
	task.spawn(function()
		local okRide, err = pcall(rideSequence, yard :: Model, layout, from, layer, result.Arrival)
		if not okRide then
			warn("DOGROTS mine ride: " .. tostring(err))
			local root = rootPart()
			if root then
				root.Anchored = false
			end
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Custom
		end
		riding = false
		State.Set(nil, false)
		current.Kind = nil
		update()
	end)
	return true, nil
end

player.CharacterAdded:Connect(function()
	if riding then
		riding = false
		State.Set(nil, false)
	end
	local camera = workspace.CurrentCamera
	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end)

------------------------------------------------------------------------------------------------
-- Prompts
------------------------------------------------------------------------------------------------
local function promptYardId(prompt: Instance): any
	local id = prompt:GetAttribute("YardId")
	local node = prompt.Parent
	while id == nil and node and node ~= workspace do
		id = node:GetAttribute("YardId")
		node = node.Parent
	end
	return id
end
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player or riding then
		return
	end
	local kind = prompt:GetAttribute("MinePrompt")
	if kind == "Elevator" or kind == "Stop" then
		openScreen(promptYardId(prompt))
	end
end)

print("DOGROTS_MINE_CLIENT_READY")
