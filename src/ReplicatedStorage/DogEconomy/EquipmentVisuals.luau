-- 3D looks of equipment, built from parts (no external assets). Shared: the client shows them in
-- ViewportFrames (shop cards, case reveal, dog artifact slots) and the server welds accessories
-- onto characters (ServerScriptService.EquipmentAvatar). Looks are data in EquipmentDefinitions.
-- Rarity drives the accent ("glow" parts): colour, material and, in the world, a light / sparkles.
--   Visuals.Build(def, {World=bool, Scale=number}) -> Model, bounds {Center, Radius}
--   Visuals.Case(caseDef, opts) -> Model, bounds
--   Visuals.Viewport(parent, spec, opts) -> ViewportFrame     spec = {Id=pieceId} | {Case=caseId}
local E = require(script.Parent.EquipmentDefinitions)

local Visuals = {}

-- Accent treatment per rarity (glow parts). Lights and sparkles only exist in the world
-- (ViewportFrames ignore them) and only for the top rarities, so a crowded server stays cheap
-- (at most two lights per player: one per Legendary / Mythic accessory worn).
Visuals.Style = {
	Common = { Material = "SmoothPlastic" },
	Uncommon = { Material = "SmoothPlastic" },
	Rare = { Material = "Glass" },
	Epic = { Material = "Glass" },
	Legendary = { Material = "Neon", Light = { Range = 7, Brightness = 1 } },
	Mythic = { Material = "Neon", Light = { Range = 8, Brightness = 1.3 }, Sparkles = true },
}

local function rgb(t: any): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
function Visuals.RarityColor(rarity: string?): Color3
	return rgb(E.RarityColors[rarity or "Common"] or E.RarityColors.Common)
end

local NAMED = {
	gold = { 249, 196, 64 },
	white = { 245, 245, 250 },
	black = { 28, 30, 38 },
}

local function colourOf(role: any, look: any, rarity: string): Color3
	if type(role) == "table" then
		return rgb(role)
	end
	if role == "glow" then
		return Visuals.RarityColor(rarity)
	end
	local base = look.Base and rgb(look.Base) or Color3.fromRGB(200, 200, 200)
	if role == "trim" then
		return look.Trim and rgb(look.Trim) or base
	elseif role == "dark" then
		return base:Lerp(Color3.new(0, 0, 0), 0.5)
	elseif role == "light" then
		return base:Lerp(Color3.new(1, 1, 1), 0.45)
	elseif NAMED[role] then
		return rgb(NAMED[role])
	end
	return base
end

local function material(name: any, fallback: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or fallback]
	end)
	if ok and value then
		return value
	end
	return Enum.Material.SmoothPlastic
end

local function vec(t: any, scale: number): Vector3
	if type(t) ~= "table" then
		return Vector3.zero
	end
	return Vector3.new((t[1] or 0) * scale, (t[2] or 0) * scale, (t[3] or 0) * scale)
end

-- One part of a look. Balls use a sphere mesh so they can be squashed (ellipsoids).
local function makePart(spec: any, look: any, rarity: string, scale: number, world: boolean): (BasePart, Vector3, number)
	local shape = spec[1]
	local size = vec(spec[2], scale)
	local part: any
	if shape == "W" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if shape == "C" then
			part.Shape = Enum.PartType.Cylinder
		end
	end
	part.Name = "Piece"
	part.Size = Vector3.new(math.max(0.02, size.X), math.max(0.02, size.Y), math.max(0.02, size.Z))
	if shape == "S" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	local role = spec[5]
	local style = Visuals.Style[rarity] or Visuals.Style.Common
	part.Color = colourOf(role, look, rarity)
	part.Material = material(spec[6], role == "glow" and style.Material or "SmoothPlastic")
	part.Transparency = tonumber(spec[7]) or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = not world
	part.Massless = true
	if role == "glow" then
		part:SetAttribute("Glow", true)
	end
	local position = vec(spec[3], scale)
	local rotation = spec[4]
	local cf = CFrame.new(position)
	if type(rotation) == "table" then
		cf *= CFrame.Angles(math.rad(rotation[1] or 0), math.rad(rotation[2] or 0), math.rad(rotation[3] or 0))
	end
	part.CFrame = cf
	return part, position, part.Size.Magnitude / 2
end

-- Rarity flourish in the world: a soft light on the first glow part, sparkles for Mythic.
local function decorate(model: Model, rarity: string)
	local style = Visuals.Style[rarity] or Visuals.Style.Common
	local glow: any = nil
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("Glow") then
			glow = part
			break
		end
	end
	if not glow then
		return
	end
	if style.Light then
		local light = Instance.new("PointLight")
		light.Range = style.Light.Range
		light.Brightness = style.Light.Brightness
		light.Color = Visuals.RarityColor(rarity)
		light.Shadows = false
		light.Parent = glow
	end
	if style.Sparkles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MythicSparkles"
		emitter.Rate = 4
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(0.6, 1.4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.Color = ColorSequence.new(Visuals.RarityColor(rarity), Color3.new(1, 1, 1))
		emitter.LightEmission = 0.8
		emitter.Parent = glow
	end
end

local function assemble(name: string, look: any, rarity: string, opts: any?): (Model, any)
	local o = opts or {}
	local scale = tonumber(o.Scale) or 1
	local world = o.World == true
	local model = Instance.new("Model")
	model.Name = name
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local radii = {}
	for _, spec in ipairs(look.Parts or {}) do
		local part, position, radius = makePart(spec, look, rarity, scale, world)
		part.Parent = model
		local r = Vector3.new(radius, radius, radius)
		minV = minV:Min(position - r * 0.6)
		maxV = maxV:Max(position + r * 0.6)
		table.insert(radii, { Position = position, Radius = radius })
	end
	if minV.X == math.huge then
		minV, maxV = Vector3.zero, Vector3.zero
	end
	local center = (minV + maxV) / 2
	local reach = 0.5
	for _, row in ipairs(radii) do
		reach = math.max(reach, (row.Position - center).Magnitude + row.Radius * 0.75)
	end
	if world then
		decorate(model, rarity)
	end
	model:SetAttribute("Rarity", rarity)
	return model, { Center = center, Radius = reach }
end

-- The model of an artifact or accessory definition (or its id).
function Visuals.Build(defOrId: any, opts: any?): (Model?, any)
	local def = type(defOrId) == "table" and defOrId or E.Def(defOrId)
	if not def or type(def.Look) ~= "table" then
		return nil, nil
	end
	return assemble(def.Id, def.Look, def.Rarity, opts)
end

-- A treasure chest in the case's colours; its lock glows in the case's best rarity.
function Visuals.Case(caseOrId: any, opts: any?): (Model?, any)
	local case = type(caseOrId) == "table" and caseOrId or E.CaseById[caseOrId]
	if not case then
		return nil, nil
	end
	local look = case.Look or {}
	local artifact = case.Kind == "Artifact"
	local parts = {
		{ "B", { 2.3, 1.25, 1.55 }, { 0, -0.25, 0 }, nil, "base", artifact and "Wood" or "SmoothPlastic" },
		{ "C", { 2.34, 1.55, 1.55 }, { 0, 0.36, 0 }, nil, "base", artifact and "Wood" or "SmoothPlastic" },
		{ "B", { 0.2, 1.3, 1.62 }, { -0.75, -0.24, 0 }, nil, "trim", "Metal" },
		{ "B", { 0.2, 1.3, 1.62 }, { 0.75, -0.24, 0 }, nil, "trim", "Metal" },
		{ "C", { 0.22, 1.6, 1.6 }, { -0.75, 0.36, 0 }, nil, "trim", "Metal" },
		{ "C", { 0.22, 1.6, 1.6 }, { 0.75, 0.36, 0 }, nil, "trim", "Metal" },
		{ "B", { 2.36, 0.1, 1.6 }, { 0, 0.37, 0 }, nil, "dark" },
		{ "B", { 0.42, 0.5, 0.12 }, { 0, 0.18, -0.82 }, nil, "glow" },
		{ "S", { 0.16, 0.16, 0.08 }, { 0, 0.14, -0.9 }, nil, "black" },
	}
	return assemble(case.Id, { Base = look.Base, Trim = look.Trim, Parts = parts }, look.Glow or "Rare", opts)
end

-- A ViewportFrame showing a piece ({Id}) or a case ({Case}), framed from the front-right.
-- opts: Yaw (degrees, default 28), Pitch (default 18), Zoom (default 1).
-- Returns the frame, and the model with its bounds and camera distance (for a turntable).
function Visuals.Viewport(parent: Instance?, spec: any, opts: any?): (ViewportFrame, Model?, any)
	local o = opts or {}
	local view = Instance.new("ViewportFrame")
	view.Name = "EquipmentView"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(1, 1)
	view.Ambient = Color3.fromRGB(150, 150, 160)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.6, -1, -0.4)
	local model, bounds
	if type(spec) == "table" and spec.Case then
		model, bounds = Visuals.Case(spec.Case)
	elseif type(spec) == "table" then
		model, bounds = Visuals.Build(spec.Id)
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	if model and bounds then
		model.Parent = view
		local yaw = math.rad(tonumber(o.Yaw) or 28)
		local pitch = math.rad(tonumber(o.Pitch) or 18)
		local direction = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
		local distance = bounds.Radius / math.sin(math.rad(camera.FieldOfView / 2)) * (tonumber(o.Zoom) or 1) * 1.02
		camera.CFrame = CFrame.lookAt(bounds.Center + direction * distance, bounds.Center)
		bounds.Distance, bounds.Yaw, bounds.Pitch = distance, yaw, pitch
	end
	if parent then
		view.Parent = parent
	end
	return view, model, bounds
end

-- Turns the camera of a Visuals.Viewport around its model (yaw in radians).
function Visuals.Turn(view: ViewportFrame, bounds: any, yaw: number)
	local camera = view.CurrentCamera
	if not camera or not bounds or not bounds.Distance then
		return
	end
	local pitch = bounds.Pitch or 0.3
	local direction = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
	camera.CFrame = CFrame.lookAt(bounds.Center + direction * bounds.Distance, bounds.Center)
end

return Visuals
