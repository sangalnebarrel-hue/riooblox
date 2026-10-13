-- MineWorld: the real, physical mine under every yard ("dogs dig DOWN"). docs/MINE.md.
--  * Carves the shaft through the yard ground and the island rock (MineCarve: reversible pieces,
--    the originals stay hidden in place).
--  * Builds per yard, under DOGROTS_District.MineWorks.<yard>: the headframe over the shaft
--    (Atomic streaming: it arrives whole) and the rock shell under the island that encloses the
--    four levels (always present, so nothing ever floats in the sky). The level interiors are
--    built on the client only while a player is near them (MineClient / MineLevels).
--  * Mirrors the owner's dig layer onto the yard (attributes MineLayer, MineUnlocked bitmask,
--    MineFrame / MineSx for clients) and onto the headframe's depth sign.
--  * Shows a rope winch with a "DIGGING AT <LAYER>" sign over every kennel pit whose dog works in
--    the mine (owner's CurrentLayer >= 2).
--  * The elevator station (MineStructures.Headframe) replaces the yard Workshop: the Workshop model
--    is moved out of the yard into ServerStorage.MineRemovedWorkshops (kept for a rollback), the
--    UPGRADE TREE prompt (UpgradeAnchor / UpgradeInteractionZone) moves to the station's kiosk.
--    Where the Workshop stood behind the shaft the station gets its hoist-house annex; where it
--    stood on the far side (mirrored yards) an ore depot fills the lot and points at the elevator.
--  * Validates elevator rides (RemoteFunction ReplicatedStorage.MineRequest, action "Ride"): the
--    level must be unlocked by the yard's owner (visitors may ride another player's mine) and the
--    rider must stand at that yard's headframe or inside its mine. The client moves its own
--    character afterwards; the server pre-streams the arrival point.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MineFolder = RS:WaitForChild("Mine")
local Layout = require(MineFolder:WaitForChild("MineLayout"))
local Structures = require(MineFolder:WaitForChild("MineStructures"))
local Themes = require(MineFolder:WaitForChild("MineThemes"))
local Carve = require(script.Parent:WaitForChild("Mine"):WaitForChild("MineCarve"))

local district = workspace:WaitForChild("DOGROTS_District")
local yardsFolder = district:WaitForChild("04_PlayerYards")

local LAYOUT_VERSION = 2
local RIDE_COOLDOWN = 1.2

local works = district:FindFirstChild("MineWorks")
if not works then
	works = Instance.new("Folder")
	works.Name = "MineWorks"
	works.Parent = district
end

local runtime = nil
local function views(): any
	if runtime == nil then
		local ok, module = pcall(function()
			return require(ServerScriptService:WaitForChild("Economy"):WaitForChild("Runtime"))
		end)
		runtime = ok and module or false
	end
	return runtime and runtime.Views or nil
end

local state = {} -- yard -> {Layout, Root, Headframe, Prompt, Winches, Owner}

------------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------------
local function setStreaming(model: Model, mode: Enum.ModelStreamingMode)
	local ok, err = pcall(function()
		model.ModelStreamingMode = mode
	end)
	if not ok then
		warn("DOGROTS mine: ModelStreamingMode on " .. model:GetFullName() .. ": " .. tostring(err))
	end
end

local function tag(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("MineWorks", true)
		end
	end
end

------------------------------------------------------------------------------------------------
-- The Workshop makes way for the elevator station
------------------------------------------------------------------------------------------------
local removed = game:GetService("ServerStorage"):FindFirstChild("MineRemovedWorkshops")
if not removed then
	removed = Instance.new("Folder")
	removed.Name = "MineRemovedWorkshops"
	removed.Parent = game:GetService("ServerStorage")
end
-- Which side the yard's Workshop stood on (+1: behind the shaft, design x' > 0; -1: far side).
-- Remembered on the yard, so it survives the Workshop leaving.
local function workshopSide(yard: Model, layout: any): number
	local side = yard:GetAttribute("MineWorkshopSide")
	if type(side) == "number" then
		return side
	end
	local workshop = yard:FindFirstChild("Workshop")
	side = 1
	if workshop and workshop:IsA("Model") then
		side = layout:ToDesign(workshop:GetPivot().Position).X >= 0 and 1 or -1
		yard:SetAttribute("MineWorkshopLot", workshop:GetPivot())
	end
	yard:SetAttribute("MineWorkshopSide", side)
	return side
end
local function removeWorkshop(yard: Model, layout: any)
	local workshop = yard:FindFirstChild("Workshop")
	if workshop then
		workshop.Name = yard.Name .. "_Workshop"
		workshop:SetAttribute("FromYard", yard.Name)
		workshop.Parent = removed
	end
	-- UPGRADE TREE stays reachable: its anchor and zone move to the station's kiosk.
	local kiosk = Structures.Kiosk
	local anchor = yard:FindFirstChild("UpgradeAnchor")
	if anchor and anchor:IsA("BasePart") then
		anchor.CFrame = layout:CF(kiosk.Anchor.X, kiosk.Anchor.Y, kiosk.Anchor.Z, -1, 0)
	end
	local zone = yard:FindFirstChild("UpgradeInteractionZone")
	if zone and zone:IsA("BasePart") then
		zone.CFrame = layout:ToWorld(kiosk.Zone)
		zone.Size = kiosk.ZoneSize
	end
end

local function build(yard: Model, layout: any)
	local name = yard.Name .. "_Mine"
	local side = workshopSide(yard, layout)
	local old = works:FindFirstChild(name)
	if old and old:GetAttribute("LayoutVersion") == LAYOUT_VERSION then
		return old
	end
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = name
	root:SetAttribute("YardId", yard:GetAttribute("YardId"))
	root:SetAttribute("LayoutVersion", LAYOUT_VERSION)
	local headframe = Structures.Headframe({ Annex = side > 0 })
	Structures.Place(headframe, layout)
	headframe.Name = "Headframe"
	-- "Show the way" (Navigation.PathGuide) points at the elevator gate.
	local gatePart = headframe:FindFirstChild("Gate", true)
	if gatePart then
		gatePart:SetAttribute("NavTarget", "MineElevator")
	end
	tag(headframe)
	setStreaming(headframe, Enum.ModelStreamingMode.Atomic)
	headframe.Parent = root
	local shell = Structures.Shell()
	Structures.Place(shell, layout)
	shell.Name = "Shell"
	tag(shell)
	-- One unit: floors and walls of every level arrive together wherever the player enters.
	setStreaming(shell, Enum.ModelStreamingMode.Atomic)
	shell.Parent = root
	local winches = Instance.new("Model")
	winches.Name = "Winches"
	winches.Parent = root
	-- The far-side Workshop lot becomes an ore depot pointing at the elevator.
	local lot = yard:GetAttribute("MineWorkshopLot")
	if side < 0 and typeof(lot) == "CFrame" then
		local p = (lot :: CFrame).Position
		local origin = layout:CF(layout:ToDesign(p).X, Layout.GroundY, layout:ToDesign(p).Z, 0, -1)
		local ok, depot = pcall(Structures.Depot, origin, layout.Sx < 0 and "◄" or "►")
		if ok and depot then
			depot.Name = "Depot"
			tag(depot)
			setStreaming(depot, Enum.ModelStreamingMode.Atomic)
			depot.Parent = root
		elseif not ok then
			warn("DOGROTS mine: depot for " .. yard.Name .. ": " .. tostring(depot))
		end
	end
	root.Parent = works
	return root
end

local function prompt(headframe: Model): ProximityPrompt?
	local gate = headframe:FindFirstChild("Gate", true)
	local anchor = gate and gate:FindFirstChild("PromptAnchor")
	if not anchor then
		return nil
	end
	local p = anchor:FindFirstChild("MineElevatorPrompt")
	if not p then
		p = Instance.new("ProximityPrompt")
		p.Name = "MineElevatorPrompt"
		p.ActionText = "Ride the elevator"
		p.ObjectText = "MINE"
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.GamepadKeyCode = Enum.KeyCode.ButtonX
		p.HoldDuration = 0
		p.MaxActivationDistance = 11
		p.RequiresLineOfSight = false
		p:SetAttribute("MinePrompt", "Elevator")
		p.Parent = anchor
	end
	return p :: ProximityPrompt
end

------------------------------------------------------------------------------------------------
-- Carving
------------------------------------------------------------------------------------------------
local carved = false
local holes = {} -- {CFrame, Size, Yard}
local function carveAll()
	if carved then
		return
	end
	carved = true
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { works, district:FindFirstChild("KennelDogs") or works }
	params.RespectCanCollide = false
	local byPart = {}
	local order = {}
	for _, hole in holes do
		local ok, found = pcall(function()
			return workspace:GetPartBoundsInBox(hole.CFrame, hole.Size, params)
		end)
		if ok then
			for _, part in found do
				if Carve.Relevant(part) then
					if not byPart[part] then
						byPart[part] = {}
						table.insert(order, part)
					end
					table.insert(byPart[part], hole)
				end
			end
		else
			warn("DOGROTS mine: carve query failed: " .. tostring(found))
		end
	end
	local pieces = 0
	for _, part in order do
		local made = Carve.Apply(part, byPart[part])
		Carve.Mirror(part, made)
		pieces += #made
	end
	print(string.format("DOGROTS_MINE_CARVED: %d parts -> %d pieces, %d shafts", #order, pieces, #holes))
end

-- Pieces added later by yard skins / stages inside a shaft opening are hidden (the reserved zone
-- is free at every stage; this is only a safety net).
local function guardSurface(yard: Model, layout: any)
	local cf, size = layout:Hole(30, -1)
	local function check(d: Instance)
		if not d:IsA("BasePart") or not Carve.Relevant(d) then
			return
		end
		local p = cf:PointToObjectSpace(d.Position)
		local s = d.Size
		local reach = math.max(s.X, s.Y, s.Z) / 2
		if math.abs(p.X) < size.X / 2 + reach and math.abs(p.Z) < size.Z / 2 + reach and math.abs(p.Y) < size.Y / 2 + reach then
			-- Exact test on the part's corners projected on the opening.
			local inside = false
			for _, dx in { -0.5, 0, 0.5 } do
				for _, dz in { -0.5, 0, 0.5 } do
					local q = cf:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(s.X * dx, 0, s.Z * dz)))
					if math.abs(q.X) < size.X / 2 - 0.2 and math.abs(q.Z) < size.Z / 2 - 0.2 and math.abs(q.Y) < size.Y / 2 then
						inside = true
					end
				end
			end
			if inside then
				Carve.Hide(d)
			end
		end
	end
	local function watch(dev: Instance)
		for _, d in dev:GetDescendants() do
			check(d)
		end
		dev.DescendantAdded:Connect(function(d)
			task.defer(check, d)
		end)
	end
	local dev = yard:FindFirstChild("PlotDevelopment")
	if dev then
		watch(dev)
	end
	yard.ChildAdded:Connect(function(child)
		if child.Name == "PlotDevelopment" then
			task.defer(watch, child)
		end
	end)
end

------------------------------------------------------------------------------------------------
-- Owner state -> yard attributes, depth sign, kennel winches
------------------------------------------------------------------------------------------------
local function unlockedMask(player: Player?): number
	local all = views()
	local p = player and all and all[player.UserId]
	return Layout.Mask(type(p) == "table" and p.UnlockedLayers or nil)
end

-- Depth lamps on the station front: lit in the depth's colour once the owner unlocked it.
local function updateLamps(s: any, mask: number)
	local headframe = s.Root and s.Root:FindFirstChild("Headframe")
	if not headframe then
		return
	end
	for i = 1, 5 do
		local lamp = headframe:FindFirstChild("DepthLamp" .. i, true)
		if lamp and lamp:IsA("BasePart") then
			local open = Layout.Unlocked(mask, i)
			lamp.Material = open and Enum.Material.Neon or Enum.Material.SmoothPlastic
			lamp.Color = open and Themes.Get(i).Accent or Color3.fromRGB(60, 58, 66)
		end
	end
end

local function updateSign(s: any, layer: number)
	local headframe = s.Root and s.Root:FindFirstChild("Headframe")
	local sign = headframe and headframe:FindFirstChild("DepthSign", true)
	local gui = sign and sign:FindFirstChild("DepthSignGui")
	local back = gui and gui:FindFirstChild("Back")
	if not back then
		return
	end
	local theme = Themes.Get(layer)
	local label = back:FindFirstChild("Layer")
	if label and label:IsA("TextLabel") then
		label.Text = theme.Title
		label.TextColor3 = theme.Accent
	end
	local depth = back:FindFirstChild("Depth")
	if depth and depth:IsA("TextLabel") then
		depth.Text = theme.Depth
	end
	local stroke = back:FindFirstChild("Accent")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = theme.Accent
	end
end

local function pitFrame(slot: Instance): CFrame?
	local pit = slot:FindFirstChild("DarkExcavation")
	local floor = slot:FindFirstChild("KennelFloor")
	if not (pit and pit:IsA("BasePart")) then
		return nil
	end
	local top = pit.Position + Vector3.new(0, pit.Size.Y / 2, 0)
	local dir = Vector3.new(0, 0, -1)
	if floor and floor:IsA("BasePart") then
		local d = pit.Position - floor.Position
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.01 then
			dir = d.Unit
		end
	end
	return Layout.Facing(top, dir)
end

local function updateWinches(yard: Model)
	local s = state[yard]
	if not s or not s.Root then
		return
	end
	local folder = s.Root:FindFirstChild("Winches")
	if not folder then
		return
	end
	local layer = yard:GetAttribute("MineLayer") or 1
	local theme = Themes.Get(layer)
	local owner = yard:GetAttribute("OwnerUserId") or 0
	for i = 1, 5 do
		local slot = yard:FindFirstChild("DigSlot_" .. i)
		local name = "Winch_" .. i
		local existing = folder:FindFirstChild(name)
		local want = slot ~= nil
			and layer >= 2
			and owner ~= 0
			and slot:GetAttribute("Unlocked") ~= false
			and slot:GetAttribute("AssignedDogUid") ~= nil
			and slot:GetAttribute("AssignedOwnerUserId") == owner
		if want and slot then
			if not existing or existing:GetAttribute("Layer") ~= layer then
				if existing then
					existing:Destroy()
				end
				local cf = pitFrame(slot)
				if cf then
					local winch = Structures.Winch(cf, theme.Accent)
					winch.Name = name
					winch:SetAttribute("Layer", layer)
					winch:SetAttribute("Slot", i)
					local board = winch:FindFirstChild("WinchSign", true)
					local gui = board and board:FindFirstChild("WinchSignGui")
					local layerLabel = gui and gui:FindFirstChild("Layer", true)
					if layerLabel and layerLabel:IsA("TextLabel") then
						layerLabel.Text = theme.Title
					end
					tag(winch)
					winch.Parent = folder
				end
			end
		elseif existing then
			existing:Destroy()
		end
	end
end

local function refreshOwner(yard: Model)
	local s = state[yard]
	if not s then
		return
	end
	local id = yard:GetAttribute("OwnerUserId") or 0
	local player = id ~= 0 and Players:GetPlayerByUserId(id) or nil
	local layer = 1
	if player then
		layer = Layout.LayerNumber(player:GetAttribute("CurrentLayer")) or 1
	end
	local mask = unlockedMask(player)
	if yard:GetAttribute("MineLayer") ~= layer then
		yard:SetAttribute("MineLayer", layer)
	end
	if yard:GetAttribute("MineUnlocked") ~= mask then
		yard:SetAttribute("MineUnlocked", mask)
	end
	updateSign(s, layer)
	updateLamps(s, mask)
	updateWinches(yard)
end

local function bindOwner(yard: Model)
	local s = state[yard]
	if s.OwnerConnection then
		s.OwnerConnection:Disconnect()
		s.OwnerConnection = nil
	end
	local id = yard:GetAttribute("OwnerUserId") or 0
	local player = id ~= 0 and Players:GetPlayerByUserId(id) or nil
	if player then
		s.OwnerConnection = player:GetAttributeChangedSignal("CurrentLayer"):Connect(function()
			task.defer(refreshOwner, yard)
		end)
	end
	refreshOwner(yard)
end

------------------------------------------------------------------------------------------------
-- Yards
------------------------------------------------------------------------------------------------
local function setup(yard: Instance)
	if not yard:IsA("Model") or state[yard] or not yard:GetAttribute("YardId") then
		return
	end
	local landscape = yard:WaitForChild("YardLandscape", 30)
	if not landscape or not landscape:WaitForChild("YardFoundation", 30) or not yard:WaitForChild("StorageAnchor", 30) then
		warn("DOGROTS mine: " .. yard.Name .. " has no YardFoundation / StorageAnchor")
		return
	end
	yard:WaitForChild("DigSlot_1", 10)
	local frame, sx = Layout.FrameFromParts(yard)
	if not frame then
		return
	end
	yard:SetAttribute("MineFrame", frame)
	yard:SetAttribute("MineSx", sx)
	local layout = Layout.ForYard(yard)
	local s = { Layout = layout }
	state[yard] = s
	s.Root = build(yard :: Model, layout)
	removeWorkshop(yard :: Model, layout)
	local headframe = s.Root:FindFirstChild("Headframe")
	s.Prompt = headframe and prompt(headframe)
	local cf, size = layout:Hole(2, Layout.IslandBottom - 2)
	table.insert(holes, { CFrame = cf, Size = size, Yard = yard })
	guardSurface(yard :: Model, layout)
	yard:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		task.defer(bindOwner, yard)
	end)
	for i = 1, 5 do
		local slot = yard:FindFirstChild("DigSlot_" .. i)
		if slot then
			for _, key in { "AssignedDogUid", "Unlocked", "AssignedOwnerUserId" } do
				slot:GetAttributeChangedSignal(key):Connect(function()
					task.defer(updateWinches, yard)
				end)
			end
		end
	end
	yard:GetAttributeChangedSignal("MineLayer"):Connect(function()
		task.defer(updateWinches, yard)
	end)
	bindOwner(yard :: Model)
end

for _, yard in yardsFolder:GetChildren() do
	task.spawn(setup, yard)
end
-- Carve once every yard's shaft is known (an island strip is shared by an east and a west yard).
task.spawn(function()
	local deadline = os.clock() + 40
	local expected = 0
	for _, yard in yardsFolder:GetChildren() do
		if yard:GetAttribute("YardId") then
			expected += 1
		end
	end
	while #holes < expected and os.clock() < deadline do
		task.wait(0.2)
	end
	carveAll()
end)
yardsFolder.ChildAdded:Connect(function(yard)
	task.defer(setup, yard)
end)
Players.PlayerAdded:Connect(function()
	for yard in state do
		task.defer(bindOwner, yard)
	end
end)
-- Unlocks change without a CurrentLayer change only through rare paths (Studio panel, a layer
-- unlocked and selected at once is covered by the signal): a cheap 3 s re-check.
task.spawn(function()
	while true do
		task.wait(3)
		for yard in state do
			local id = yard:GetAttribute("OwnerUserId") or 0
			local player = id ~= 0 and Players:GetPlayerByUserId(id) or nil
			local mask = unlockedMask(player)
			if yard:GetAttribute("MineUnlocked") ~= mask then
				yard:SetAttribute("MineUnlocked", mask)
				local s = state[yard]
				if s then
					updateLamps(s, mask)
				end
			end
		end
	end
end)

------------------------------------------------------------------------------------------------
-- Elevator requests
------------------------------------------------------------------------------------------------
local remote = RS:FindFirstChild("MineRequest")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "MineRequest"
	remote.Parent = RS
end
local lastRide = {}
Players.PlayerRemoving:Connect(function(player)
	lastRide[player] = nil
end)

local function yardById(id: any): Model?
	for yard in state do
		if yard:GetAttribute("YardId") == id then
			return yard
		end
	end
	return nil
end

local function ride(player: Player, args: any): (boolean, any)
	if type(args) ~= "table" then
		return false, "Invalid request"
	end
	local now = os.clock()
	if now - (lastRide[player] or -10) < RIDE_COOLDOWN then
		return false, "Please wait a moment"
	end
	local layer = Layout.LayerNumber(args.Layer)
	local yard = yardById(args.YardId)
	if not layer or not yard then
		return false, "Invalid request"
	end
	local s = state[yard]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false, "Wait for your character"
	end
	if (yard:GetAttribute("OwnerUserId") or 0) == 0 and layer > 1 then
		return false, "This yard has no owner"
	end
	if not Layout.Unlocked(yard:GetAttribute("MineUnlocked") or 1, layer) then
		return false, "This depth is still locked"
	end
	-- At this yard's headframe, or already inside its mine.
	local layout = s.Layout
	local d = layout:ToDesign(root.Position)
	local sh = Layout.Shaft
	local atTop = math.abs(d.X - sh.X) <= 16 and math.abs(d.Z - sh.Z) <= 14 and root.Position.Y > Layout.GroundY - 3 and root.Position.Y < Layout.GroundY + 14
	if not atTop and not layout:Contains(root.Position) then
		return false, "Stand at the mine elevator"
	end
	lastRide[player] = now
	local arrival = layout:Arrival(layer)
	local from = layout:LayerAtY(root.Position.Y)
	local headframe = s.Root and s.Root:FindFirstChild("Headframe")
	if headframe then
		headframe:SetAttribute("RideFrom", from)
		headframe:SetAttribute("RideTo", layer)
		headframe:SetAttribute("RideAt", workspace:GetServerTimeNow())
		headframe:SetAttribute("RideSerial", (headframe:GetAttribute("RideSerial") or 0) + 1)
	end
	-- Stream the arrival floor (the shell) to the rider before the client moves there.
	pcall(function()
		player:RequestStreamAroundAsync(arrival.Position, 4)
	end)
	return true, { Arrival = arrival, Layer = layer, From = from, YardId = yard:GetAttribute("YardId") }
end

remote.OnServerInvoke = function(player: Player, action: any, args: any)
	if action == "Ride" then
		local ok, result = ride(player, args)
		return ok, result
	end
	return false, "Invalid request"
end

print("DOGROTS_MINE_READY: headframes, shells and elevators")
