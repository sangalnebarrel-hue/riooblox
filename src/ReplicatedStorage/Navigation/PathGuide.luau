-- Navigation.PathGuide (client only): "SHOW THE WAY". Plans a route on Navigation.RouteGraph and
-- draws it with glowing chevrons lying on the ground, gliding towards the target, plus a final
-- pointer at the destination (bobbing neon down-arrow, pulsing ground ring, name + distance).
--   PathGuide.Show(nameOrKey) -> ok, reason   start (or switch) a route; reason "sealed" | "unknown" | "noyard"
--   PathGuide.Clear(reason?)                 stop it ("cleared" | "arrived" | ...)
--   PathGuide.Active() -> state?             {Key, Entry, Color, Remaining, Heading, Length}
--   PathGuide.Estimate(key) -> studs?        route length from the player (no drawing)
--   PathGuide.Changed(state?)                fired on start / switch / stop
--   PathGuide.Progress(state)                fired 4x per second while a route is active
-- Budget: one pool of <= 40 parts created once (16 arrows x 2 bars + 3 pointer parts + 1 anchor),
-- local to this client (a workspace folder created here is never replicated). Nothing runs per
-- frame while no route is active. Reduced Motion: static arrows, no bobbing. Low quality: 8 arrows.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local RouteGraph = require(script.Parent.RouteGraph)
local Destinations = require(script.Parent.Destinations)
local ArrowFlow = require(script.Parent.ArrowFlow)

local PathGuide = {}
PathGuide.StrayDistance = 12 -- re-plan when the player is this far from the route
PathGuide.ArriveDistance = 8 -- arrived within this distance of the goal
PathGuide.CheckInterval = 0.25 -- off-route / arrival / HUD checks (4x per second)
PathGuide.ReplanInterval = 0.5
PathGuide.Hover = 0.14 -- arrows float this high above the ground
PathGuide.RaycastsPerFrame = 6
PathGuide.MaxArrows = 16

local WHITE = Color3.new(1, 1, 1)
local OPEN = math.rad(52) -- half opening angle of the chevron arms
local ARM = 2.5 -- chevron arm length (studs)

-- Tiny signal (handlers run in their own thread so a failing listener cannot stop the guide).
local function newSignal(): any
	local handlers: { [any]: boolean } = {}
	local signal = {}
	function signal.Connect(_self: any, fn: (...any) -> ())
		local handle = { Fn = fn }
		handlers[handle] = true
		return {
			Disconnect = function()
				handlers[handle] = nil
			end,
		}
	end
	function signal.Fire(_self: any, ...: any)
		for handle in pairs(handlers) do
			task.spawn(handle.Fn, ...)
		end
	end
	return signal
end
PathGuide.Changed = newSignal()
PathGuide.Progress = newSignal()

local player = Players.LocalPlayer
local started = false
local kit: any = nil -- PlayerGui.ScreenGui.Modules.Kit (Maid, Motion, Lang), when available
local maid: any = nil -- lives while a route is active
local active: any = nil
local pool: any = nil

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------
local function lang(): string
	if kit then
		local ok, value = pcall(kit.Lang)
		if ok then
			return value
		end
	end
	local ok, locale = pcall(function()
		return player.LocaleId
	end)
	return (ok and type(locale) == "string" and string.sub(string.lower(locale), 1, 2) == "ru") and "ru" or "en"
end
local function T(en: string, ru: string): string
	return lang() == "ru" and ru or en
end
PathGuide.T = T

local function reducedMotion(): boolean
	if player and player:GetAttribute("ReducedMotion") == true then
		return true
	end
	if kit and kit.Motion then
		local ok, value = pcall(kit.Motion.Reduced)
		return ok and value == true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function lowQuality(): boolean
	if player:GetAttribute("LowFX") == true or player:GetAttribute("WorldEventFX") == "Low" then
		return true
	end
	local ok, level = pcall(function()
		local settingsService: any = UserSettings():GetService("UserGameSettings")
		return settingsService.SavedQualityLevel
	end)
	if ok and level and level ~= Enum.SavedQualitySetting.Automatic then
		return level.Value <= 3
	end
	return false
end

local function newMaid(): any
	if kit and kit.Maid then
		return kit.Maid.new()
	end
	local tasks = {}
	return {
		Give = function(_self: any, item: any)
			table.insert(tasks, item)
			return item
		end,
		Clean = function(_self: any)
			for i = #tasks, 1, -1 do
				local item = tasks[i]
				if typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				elseif type(item) == "function" then
					pcall(item)
				elseif type(item) == "table" and type(item.Disconnect) == "function" then
					pcall(item.Disconnect, item)
				end
			end
			table.clear(tasks)
		end,
	}
end

local function character(): (BasePart?, Humanoid?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, nil
end

-- The player's feet (route positions are on the walking surface).
local function feet(): Vector3?
	local root, humanoid = character()
	if not root then
		return nil
	end
	local drop = root.Size.Y / 2 + (humanoid and humanoid.HipHeight or 2)
	return root.Position - Vector3.new(0, drop, 0)
end

local function district(): Instance?
	return workspace:FindFirstChild("DOGROTS_District")
end

-- Raycasts ignore the guide itself, every character and the dogs.
local rayParams: RaycastParams? = nil
local function refreshRayParams()
	local exclude: { Instance } = {}
	if pool then
		table.insert(exclude, pool.Folder)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	local map = district()
	if map then
		for _, path in ipairs({ { "KennelDogs" }, { "03_DogLine", "ActiveDogs" } }) do
			local node: Instance? = map
			for _, name in ipairs(path) do
				node = node and node:FindFirstChild(name)
			end
			if node then
				table.insert(exclude, node)
			end
		end
	end
	local fx = workspace:FindFirstChild("WorldEventFX")
	if fx then
		table.insert(exclude, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	params.IgnoreWater = true
	rayParams = params
end

-- Straight walkable line between two ground points (waist-high ray); unknown geometry = clear.
local function lineClear(a: Vector3, b: Vector3): boolean
	if not rayParams then
		refreshRayParams()
	end
	local lift = Vector3.new(0, 2.2, 0)
	local delta = b - a
	if delta.Magnitude < 0.5 then
		return true
	end
	local hit = workspace:Raycast(a + lift, delta, rayParams)
	return hit == nil or (hit.Position - (a + lift)).Magnitude >= delta.Magnitude - 1.5
end

------------------------------------------------------------------------------------------------
-- Targets: the static RouteGraph target, refined by the live yard model when it is streamed in.
------------------------------------------------------------------------------------------------
local function myYardId(): number?
	local id = tonumber(player:GetAttribute("YardId"))
	if id and RouteGraph.Yard(id) then
		return id
	end
	return nil
end

local function liveYard(id: number): Instance?
	local map = district()
	local yards = map and map:FindFirstChild("04_PlayerYards")
	if not yards then
		return nil
	end
	for _, yard in ipairs(yards:GetChildren()) do
		if yard:GetAttribute("YardId") == id then
			return yard
		end
	end
	return nil
end

local function positionOf(object: Instance?): (Vector3?, number)
	if not object then
		return nil, 0
	end
	if object:IsA("BasePart") then
		return object.Position, object.Size.Y / 2
	end
	if object:IsA("Model") then
		local ok, cf, size = pcall(function()
			return object:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position, size.Y / 2
		end
	end
	return nil, 0
end

-- A live object for a yard destination: tagged with the NavTarget attribute by the system that
-- builds it, or the known names of today's models.
local function liveObject(key: string, yard: Instance): Instance?
	local known: Instance? = nil
	if key == "MiningCorner" then
		local corner = yard:FindFirstChild("MiningCorner")
		known = corner and corner:FindFirstChild("MiningPad")
	elseif key == "BestFinds" then
		local deco = yard:FindFirstChild("PlotDevelopment")
		known = deco and deco:FindFirstChild("BestFinds")
	elseif key == "Collector" then
		known = yard:FindFirstChild("SellAnchor")
	elseif key == "MineElevator" then
		-- The mine is built under DOGROTS_District.MineWorks (tagged with the yard's YardId), not
		-- inside the yard model; its elevator gate carries NavTarget = "MineElevator".
		local works = yard.Parent and yard.Parent.Parent and yard.Parent.Parent:FindFirstChild("MineWorks")
		local yardId = yard:GetAttribute("YardId")
		for _, mine in ipairs(works and works:GetChildren() or {}) do
			if yardId ~= nil and mine:GetAttribute("YardId") == yardId then
				local headframe = mine:FindFirstChild("Headframe")
				local gate = headframe and headframe:FindFirstChild("Gate", true)
				if gate and gate:GetAttribute("NavTarget") == key then
					known = gate
				end
			end
		end
	end
	if known then
		return known
	end
	for _, item in ipairs(yard:GetDescendants()) do
		if item:GetAttribute("NavTarget") == key then
			return item
		end
	end
	return nil
end

local function resolveTarget(key: string): (any?, string?)
	local entry = Destinations.ByKey[key]
	if not entry then
		return nil, "unknown"
	end
	if entry.Sealed then
		return nil, "sealed"
	end
	local spec = (RouteGraph.Targets :: any)[key]
	if not spec then
		return nil, "unknown"
	end
	if not spec.Yard then
		return RouteGraph.Target(key), nil
	end
	local id = myYardId()
	if not id then
		return nil, "noyard"
	end
	local overrides: any = nil
	local yard = liveYard(id)
	local object = yard and key ~= "PlayerYards" and key ~= "MyKennels" and liveObject(key, yard)
	local pos, halfHeight = positionOf(object or nil)
	local static = RouteGraph.Target(key, { YardId = id })
	if pos and static then
		local pointer = pos + Vector3.new(0, halfHeight, 0)
		if RouteGraph.Flat(pos, static.Pointer) <= 6 then
			-- Where we expected it: keep the hand-made approach, point at the real object.
			overrides = { Pointer = pointer }
		else
			-- Moved (another layout): walk the yard's centre line to the object's z, then
			-- sideways up to 10 studs short of it.
			local xp, z = RouteGraph.YardLocal(id, pos)
			if xp and z then
				local side = xp < 0 and -1 or 1
				local stop = math.abs(xp) > 10 and (xp - side * 10) or 0
				overrides = { Via = { RouteGraph.YardPoint(id, 0, z) }, Goal = RouteGraph.YardPoint(id, stop, z), Pointer = pointer }
			end
		end
	end
	return RouteGraph.Target(key, { YardId = id, Overrides = overrides }), nil
end

local function plan(target: any, from: Vector3): any?
	local route = RouteGraph.Plan(from, target, { Visible = lineClear })
	if not route then
		return nil
	end
	route.Samples = RouteGraph.Build(route.Points)
	return route
end

------------------------------------------------------------------------------------------------
-- Pool: created once, reused by every route.
------------------------------------------------------------------------------------------------
local function newPart(parent: Instance, name: string, size: Vector3, class: string?): BasePart
	local part: any = Instance.new(class or "Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = parent
	return part
end

local function buildPool()
	if pool then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DOGROTS_PathGuide"
	local bars: { BasePart } = {}
	for i = 1, PathGuide.MaxArrows * 2 do
		table.insert(bars, newPart(folder, "ArrowBar" .. i, Vector3.new(0.5, 0.1, ARM)))
	end
	local shaft = newPart(folder, "PointerShaft", Vector3.new(0.55, 2.4, 0.55))
	local headL = newPart(folder, "PointerHeadL", Vector3.new(0.4, 1.7, 1.25), "WedgePart")
	local headR = newPart(folder, "PointerHeadR", Vector3.new(0.4, 1.7, 1.25), "WedgePart")
	local anchor = newPart(folder, "PointerAnchor", Vector3.new(1, 1, 1))
	anchor.Material = Enum.Material.SmoothPlastic
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = "GoalRing"
	ring.Adornee = anchor
	ring.Height = 0.12
	ring.Radius = 3
	ring.InnerRadius = 2.35
	ring.AlwaysOnTop = false
	ring.ZIndex = 0
	ring.Visible = false
	ring.Parent = anchor

	local board = Instance.new("BillboardGui")
	board.Name = "GoalLabel"
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = 2000
	board.Size = UDim2.fromOffset(210, 58)
	board.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	board.Enabled = false
	board.Parent = folder
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Color3.fromRGB(23, 43, 76)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = card
	local function label(name: string, y: number, h: number, size: number, font: Enum.Font): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Position = UDim2.new(0, 8, 0, y)
		text.Size = UDim2.new(1, -16, 0, h)
		text.Font = font
		text.TextSize = size
		text.TextColor3 = WHITE
		text.TextScaled = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text:SetAttribute("NoTranslate", true)
		text:SetAttribute("KeepFont", true)
		text.Parent = card
		return text
	end
	local title = label("Title", 4, 28, 20, Enum.Font.FredokaOne)
	local distance = label("Distance", 31, 22, 17, Enum.Font.GothamBold)
	folder.Parent = workspace
	pool = {
		Folder = folder,
		Bars = bars,
		Shaft = shaft,
		HeadL = headL,
		HeadR = headR,
		Anchor = anchor,
		Ring = ring,
		Board = board,
		Title = title,
		Distance = distance,
		Stroke = stroke,
		Shown = 0, -- bars currently visible
		Last = {}, -- per bar: last transparency step written
	}
end
PathGuide.PartCount = function(): number
	if not pool then
		return 0
	end
	local count = 0
	for _, item in ipairs(pool.Folder:GetDescendants()) do
		if item:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function hideAll()
	if not pool then
		return
	end
	for _, bar in ipairs(pool.Bars) do
		bar.Transparency = 1
	end
	pool.Shown = 0
	table.clear(pool.Last)
	for _, part in ipairs({ pool.Shaft, pool.HeadL, pool.HeadR }) do
		part.Transparency = 1
	end
	pool.Ring.Visible = false
	pool.Board.Enabled = false
end

------------------------------------------------------------------------------------------------
-- Drawing (only while a route is active)
------------------------------------------------------------------------------------------------

local function groundY(a: any, i: number, now: number): number
	local cached = a.Ground[i]
	if cached then
		return cached
	end
	local base = a.Samples.Positions[i]
	if a.Budget > 0 and (a.Retry[i] or 0) <= now then
		a.Budget -= 1
		local hit = workspace:Raycast(base + Vector3.new(0, 4, 0), Vector3.new(0, -9, 0), rayParams)
		if hit and hit.Position.Y <= base.Y + 2.6 and hit.Position.Y >= base.Y - 4 then
			a.Ground[i] = hit.Position.Y
			return hit.Position.Y
		end
		a.Retry[i] = now + 1 -- not streamed in yet: graph height for now, try again later
	end
	return base.Y
end

local function heightAt(a: any, s: number, now: number): number
	local samples = a.Samples
	local n = #samples.Positions
	local f = s / samples.Spacing
	local i = math.clamp(math.floor(f) + 1, 1, n)
	local j = math.min(n, i + 1)
	local y0, y1 = groundY(a, i, now), groundY(a, j, now)
	return y0 + (y1 - y0) * math.clamp(f - (i - 1), 0, 1)
end

local function drawArrows(a: any, now: number)
	local flow = ArrowFlow.Layout(a.Samples.Length, a.Progress, now - a.StartedAt, a.Flow)
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local bars = pool.Bars
	local last = pool.Last
	local base: Color3 = a.Color
	local up = Vector3.new(0, 1, 0)
	local used = 0
	for _, arrow in ipairs(flow) do
		local pos, tangent = RouteGraph.PointAt(a.Samples, arrow.S)
		local y = heightAt(a, arrow.S, now) + PathGuide.Hover
		local right = Vector3.new(-tangent.Z, 0, tangent.X)
		local tip = Vector3.new(pos.X, y, pos.Z) + tangent * 0.8
		local back = -tangent * math.cos(OPEN)
		local side = right * math.sin(OPEN)
		for armIndex = 1, 2 do
			local dir = armIndex == 1 and (back - side) or (back + side)
			local center = tip + dir * (ARM / 2)
			used += 1
			local bar = bars[used]
			table.insert(parts, bar)
			table.insert(frames, CFrame.lookAt(center, center + dir, up))
			-- Opacity and colour in 20 steps: no property write when nothing visible changed.
			local opacity = arrow.Alpha * (0.5 + 0.5 * arrow.Glow)
			local step = math.floor(opacity * 20 + 0.5) * 100 + math.floor(arrow.Glow * 10 + 0.5)
			if last[used] ~= step then
				last[used] = step
				bar.Transparency = 1 - math.floor(opacity * 20 + 0.5) / 20
				bar.Color = base:Lerp(WHITE, 0.42 * math.floor(arrow.Glow * 10 + 0.5) / 10)
			end
		end
	end
	for i = used + 1, pool.Shown do
		bars[i].Transparency = 1
		last[i] = nil
	end
	pool.Shown = used
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function drawPointer(a: any, now: number)
	local pointer: Vector3 = a.Pointer
	local t = now - a.StartedAt
	local bob = a.Static and 0 or math.sin(t * 2.6) * 0.45
	local camera = workspace.CurrentCamera
	local h = camera and camera.CFrame.RightVector or Vector3.new(1, 0, 0)
	h = Vector3.new(h.X, 0, h.Z)
	h = h.Magnitude > 1e-3 and h.Unit or Vector3.new(1, 0, 0)
	local headH = pool.HeadL.Size.Y
	local headW = pool.HeadL.Size.Z
	local tipY = pointer.Y + 1.3 + bob
	local headCenter = Vector3.new(pointer.X, tipY + headH / 2, pointer.Z)
	local down = Vector3.new(0, -1, 0)
	local leftZ = h
	local rightZ = -h
	local leftCF = CFrame.fromMatrix(headCenter - h * (headW / 2), down:Cross(leftZ), down, leftZ)
	local rightCF = CFrame.fromMatrix(headCenter + h * (headW / 2), down:Cross(rightZ), down, rightZ)
	local shaftH = pool.Shaft.Size.Y
	local shaftCF = CFrame.new(headCenter + Vector3.new(0, headH / 2 + shaftH / 2 - 0.05, 0))
	workspace:BulkMoveTo({ pool.HeadL, pool.HeadR, pool.Shaft }, { leftCF, rightCF, shaftCF }, Enum.BulkMoveMode.FireCFrameChanged)
	-- Ground ring: a ripple that grows and fades (static with Reduced Motion).
	local ring = pool.Ring
	if a.Arrived then
		local k = math.clamp((now - a.Arrived) / 1.2, 0, 1)
		ring.Radius = 3 + k * 6
		ring.InnerRadius = ring.Radius - 0.6
		ring.Transparency = 0.2 + 0.8 * k
	elseif a.Static then
		ring.Radius = 3
		ring.InnerRadius = 2.35
		ring.Transparency = 0.25
	else
		local k = (t * 0.8) % 1
		ring.Radius = 2.2 + k * 1.8
		ring.InnerRadius = ring.Radius - 0.55
		ring.Transparency = 0.15 + 0.7 * k
	end
end

local function placeAnchor(a: any)
	local goal: Vector3 = a.Goal
	pool.Anchor.CFrame = CFrame.new(goal.X, goal.Y + 0.08, goal.Z) * CFrame.Angles(math.pi / 2, 0, 0)
	pool.Board.StudsOffsetWorldSpace = Vector3.new(a.Pointer.X - goal.X, a.Pointer.Y - goal.Y + 5.2, a.Pointer.Z - goal.Z)
end

------------------------------------------------------------------------------------------------
-- Route state
------------------------------------------------------------------------------------------------
local function publicState(a: any): any
	return {
		Key = a.Key,
		Entry = a.Entry,
		Color = a.Color,
		Remaining = a.Remaining,
		Length = a.Samples and a.Samples.Length or 0,
		Heading = a.Heading,
		Arrived = a.Arrived ~= nil,
	}
end

local function formatDistance(studs: number): string
	return string.format("%d %s", math.max(0, math.floor(studs + 0.5)), T("m", "м"))
end
PathGuide.FormatDistance = formatDistance

local function applyRoute(a: any, route: any)
	a.Route = route
	a.Samples = route.Samples
	a.Goal = route.Goal
	a.Pointer = route.Pointer or route.Goal
	a.Ground = {}
	a.Retry = {}
	a.Hint = 1
	a.Progress = 0
	a.Remaining = route.Samples.Length
	placeAnchor(a)
end

local function replan(a: any, now: number)
	a.NextReplan = now + PathGuide.ReplanInterval
	local from = feet()
	if not from then
		return
	end
	local target, reason = resolveTarget(a.Key)
	if not target then
		PathGuide.Clear(reason or "unknown")
		return
	end
	a.Target = target
	local route = plan(target, from)
	if route then
		applyRoute(a, route)
		a.NoRoute = false
	else
		-- Off the map (The Void...): keep the pointer, no arrows, try again later.
		a.NoRoute = true
		a.Goal = target.Docks[1] and target.Docks[1].Goal or target.Pointer
		a.Pointer = target.Pointer
		placeAnchor(a)
	end
end

local function updateHud(a: any)
	local here = a.Feet
	if here and a.Samples and not a.NoRoute then
		a.Remaining = math.max(0, a.Samples.Length - a.Progress) + math.max(0, (a.Lateral or 0) - 2)
		local ahead = RouteGraph.PointAt(a.Samples, a.Progress + 6)
		local dir = Vector3.new(ahead.X - here.X, 0, ahead.Z - here.Z)
		local camera = workspace.CurrentCamera
		if dir.Magnitude > 0.5 and camera then
			local look = camera.CFrame.LookVector
			local right = camera.CFrame.RightVector
			local f = Vector3.new(look.X, 0, look.Z)
			local r = Vector3.new(right.X, 0, right.Z)
			if f.Magnitude > 1e-3 and r.Magnitude > 1e-3 then
				a.Heading = math.deg(math.atan2(dir.Unit:Dot(r.Unit), dir.Unit:Dot(f.Unit)))
			end
		end
	elseif here then
		a.Remaining = RouteGraph.Flat(here, a.Pointer)
	end
	pool.Title.Text = Destinations.Text(a.Entry, "Name", lang())
	pool.Distance.Text = a.Arrived and T("YOU ARE HERE!", "ТЫ НА МЕСТЕ!") or formatDistance(a.Remaining or 0)
	PathGuide.Progress:Fire(publicState(a))
end

local function check(a: any, now: number)
	a.Static = reducedMotion()
	if a.Static ~= a.WasStatic then
		a.WasStatic = a.Static
		a.Flow.Static = a.Static
	end
	local here = a.Feet
	if here and not a.Arrived and RouteGraph.Flat(here, a.Goal) <= PathGuide.ArriveDistance and math.abs(here.Y - a.Goal.Y) < 8 then
		a.Arrived = now
		hideAll()
		for _, part in ipairs({ pool.Shaft, pool.HeadL, pool.HeadR }) do
			part.Transparency = 0.05
		end
		pool.Ring.Visible = true
		pool.Board.Enabled = true
		updateHud(a)
		task.delay(1.6, function()
			if active == a then
				PathGuide.Clear("arrived")
			end
		end)
		return
	end
	if a.Arrived then
		return
	end
	if now >= (a.NextRays or 0) then
		a.NextRays = now + 5
		refreshRayParams()
	end
	if (a.NoRoute or (a.Lateral or 0) > PathGuide.StrayDistance) and now >= (a.NextReplan or 0) then
		replan(a, now)
		if active ~= a then
			return
		end
	end
	updateHud(a)
end

local function step()
	local a = active
	if not a or not pool then
		return
	end
	local now = os.clock()
	a.Budget = PathGuide.RaycastsPerFrame
	local here = feet()
	a.Feet = here
	if here and a.Samples and not a.NoRoute then
		local s, lateral, index = RouteGraph.Locate(a.Samples, here, a.Hint)
		a.Hint = index
		a.Progress = s
		a.Lateral = lateral
	end
	if now >= a.NextCheck then
		a.NextCheck = now + PathGuide.CheckInterval
		check(a, now)
		if active ~= a then
			return
		end
	end
	if not a.Arrived and not a.NoRoute then
		drawArrows(a, now)
	elseif a.NoRoute and pool.Shown > 0 then
		hideAll()
		pool.Ring.Visible = true
		pool.Board.Enabled = true
	end
	drawPointer(a, now)
end

------------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------------
function PathGuide.Start()
	if started then
		return
	end
	assert(RunService:IsClient(), "PathGuide runs on the client")
	started = true
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui", 30)
		local gui = playerGui and playerGui:WaitForChild("ScreenGui", 30)
		local modules = gui and gui:WaitForChild("Modules", 30)
		local module = modules and modules:WaitForChild("Kit", 30)
		if module then
			local ok, value = pcall(require, module)
			if ok then
				kit = value
			end
		end
	end)
end

function PathGuide.Active(): any
	return active and publicState(active) or nil
end

function PathGuide.Clear(reason: string?)
	local a = active
	if not a then
		return
	end
	active = nil
	if maid then
		maid:Clean()
	end
	hideAll()
	PathGuide.Changed:Fire(nil, reason or "cleared", a.Key)
end

-- Length of the route from the player to a destination (nil: sealed / unknown / no route).
function PathGuide.Estimate(nameOrKey: any): number?
	local key = Destinations.Resolve(nameOrKey)
	local from = feet()
	if not key or not from then
		return nil
	end
	local target = resolveTarget(key)
	if not target then
		return nil
	end
	local route = RouteGraph.Plan(from, target)
	return route and route.Length or nil
end

function PathGuide.Show(nameOrKey: any): (boolean, string?)
	PathGuide.Start()
	local key = Destinations.Resolve(nameOrKey)
	if not key then
		return false, "unknown"
	end
	local entry = Destinations.ByKey[key]
	local target, reason = resolveTarget(key)
	if not target then
		return false, reason
	end
	if active then
		PathGuide.Clear("switched")
	end
	buildPool()
	refreshRayParams()
	local now = os.clock()
	local low = lowQuality()
	local a: any = {
		Key = key,
		Entry = entry,
		Target = target,
		Color = Destinations.Color(entry),
		StartedAt = now,
		NextCheck = 0,
		NextReplan = 0,
		Budget = PathGuide.RaycastsPerFrame,
		Static = reducedMotion(),
		Flow = ArrowFlow.Config(low and ArrowFlow.Low or nil),
	}
	a.WasStatic = a.Static
	a.Flow.Static = a.Static
	a.Flow.Max = math.min(a.Flow.Max, PathGuide.MaxArrows)
	active = a
	local from = feet()
	if from then
		local route = plan(target, from)
		if route then
			applyRoute(a, route)
		else
			a.NoRoute = true
		end
	else
		a.NoRoute = true
	end
	if a.NoRoute then
		a.Goal = target.Docks[1] and target.Docks[1].Goal or target.Pointer
		a.Pointer = target.Pointer
		placeAnchor(a)
	end
	-- Colours of this destination.
	for _, part in ipairs({ pool.Shaft, pool.HeadL, pool.HeadR }) do
		part.Color = a.Color
		part.Transparency = 0.05
	end
	pool.Ring.Color3 = a.Color
	pool.Ring.Visible = true
	pool.Stroke.Color = a.Color
	pool.Board.Enabled = true
	for _, bar in ipairs(pool.Bars) do
		bar.Color = a.Color
	end
	maid = newMaid()
	maid:Give(RunService.Heartbeat:Connect(step))
	maid:Give(player.CharacterAdded:Connect(function()
		a.NextReplan = 0
		a.NoRoute = true -- re-plan from the new spawn on the next check
	end))
	maid:Give(player:GetAttributeChangedSignal("YardId"):Connect(function()
		if Destinations.ByKey[key] and Destinations.ByKey[key].Category == "Plot" then
			a.NextReplan = 0
			a.NoRoute = true
		end
	end))
	updateHud(a)
	PathGuide.Changed:Fire(publicState(a), "started", key)
	return true, nil
end

return PathGuide
