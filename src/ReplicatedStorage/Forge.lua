--!strict
-- Forge: shared builder for procedural part models (find models, plot decor, the mutation machine,
-- mine levels). One look for everything that is built from primitives in code:
--   * real shapes (Ball, Cylinder, Wedge, sphere meshes for organic forms), rotations and
--     materials instead of axis-aligned cube grids;
--   * every part anchored and non-interactive by default (CanCollide/CanTouch/CanQuery off),
--     smooth surfaces, so a model costs only its draw calls;
--   * level of detail: work passed to b:Detail(fn) is skipped when the builder is made with Lod >= 1;
--   * accent parts (b:Accent(part)) carry the ItemAccent attribute: mutation styling and glow
--     effects recolour only those, not the whole model.
--
--   local Forge = require(ReplicatedStorage.Forge)
--   local b = Forge.Builder("rubber_duck", { Lod = 0 })
--   local body = b:Ellipsoid(Vector3.new(2, 1.6, 2.6), CFrame.new(0, 0.8, 0), Forge.C(255, 214, 60), "SmoothPlastic")
--   b:Accent(b:Ball(0.35, CFrame.new(0.5, 2.1, -0.9), Forge.C(20, 20, 24), "SmoothPlastic"))
--   local model = b:Finish()   -- Model with an invisible Root at the origin (the ground contact point)
--
-- Coordinates: the model is built around the origin with +Y up and the "front" facing -Z (the
-- Roblox LookVector), resting on Y = 0. Callers place it with model:PivotTo(cf).
-- Cylinders use the Roblox convention (axis = local X); CylY / CylZ rotate them for you.
-- tools/qa/render.py renders Forge models for review without Studio (see docs/OVERHAUL.md).
local Forge = {}

export type Builder = {
	Model: Model,
	Lod: number,
	Parts: number,
	Box: (self: Builder, size: Vector3, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Ball: (self: Builder, diameter: number, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Ellipsoid: (self: Builder, size: Vector3, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Cyl: (self: Builder, length: number, diameter: number, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	CylY: (self: Builder, height: number, diameter: number, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	CylZ: (self: Builder, length: number, diameter: number, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Wedge: (self: Builder, size: Vector3, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> WedgePart,
	Beam: (self: Builder, a: Vector3, b: Vector3, width: number, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Rod: (self: Builder, a: Vector3, b: Vector3, diameter: number, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Ring: (self: Builder, cf: CFrame, radius: number, thickness: number, color: Color3, material: string?, segments: number?, props: { [string]: any }?) -> { BasePart },
	Disc: (self: Builder, cf: CFrame, diameter: number, thickness: number, color: Color3, material: string?, props: { [string]: any }?) -> Part,
	Cone: (self: Builder, cf: CFrame, height: number, baseDiameter: number, tipDiameter: number, steps: number, color: Color3, material: string?, props: { [string]: any }?) -> { BasePart },
	Gem: (self: Builder, size: number, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> { BasePart },
	Prism: (self: Builder, cf: CFrame, width: number, height: number, tip: number, color: Color3, material: string?, props: { [string]: any }?) -> { BasePart },
	Roof: (self: Builder, size: Vector3, cf: CFrame, color: Color3, material: string?, props: { [string]: any }?) -> { BasePart },
	Light: (self: Builder, part: BasePart, color: Color3, range: number, brightness: number?, kind: string?) -> Light,
	Accent: <T>(self: Builder, part: T) -> T,
	Detail: (self: Builder, fn: () -> ()) -> (),
	Folder: (self: Builder, name: string) -> Model,
	Into: (self: Builder, parent: Instance) -> (),
	Finish: (self: Builder) -> Model,
}

function Forge.C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
function Forge.Hex(hex: string): Color3
	return Color3.fromHex(hex)
end

-- Shared palette so items, decor and machines read as one game.
Forge.Palette = {
	Gold = Color3.fromRGB(255, 196, 54),
	GoldDark = Color3.fromRGB(196, 132, 28),
	Silver = Color3.fromRGB(198, 205, 214),
	Iron = Color3.fromRGB(96, 102, 112),
	Steel = Color3.fromRGB(140, 150, 162),
	Copper = Color3.fromRGB(196, 112, 62),
	Bronze = Color3.fromRGB(168, 116, 58),
	Bone = Color3.fromRGB(240, 228, 200),
	Ivory = Color3.fromRGB(250, 243, 222),
	Wood = Color3.fromRGB(150, 98, 56),
	WoodDark = Color3.fromRGB(96, 62, 38),
	Leather = Color3.fromRGB(122, 72, 42),
	Stone = Color3.fromRGB(150, 146, 140),
	StoneDark = Color3.fromRGB(92, 88, 86),
	Sand = Color3.fromRGB(226, 196, 140),
	Grass = Color3.fromRGB(96, 160, 72),
	Leaf = Color3.fromRGB(70, 140, 60),
	Water = Color3.fromRGB(80, 170, 230),
	Ink = Color3.fromRGB(26, 26, 32),
	White = Color3.fromRGB(245, 245, 245),
	Red = Color3.fromRGB(214, 52, 52),
	Ruby = Color3.fromRGB(220, 30, 70),
	Orange = Color3.fromRGB(255, 140, 40),
	Yellow = Color3.fromRGB(255, 214, 60),
	Green = Color3.fromRGB(60, 200, 90),
	Emerald = Color3.fromRGB(30, 200, 120),
	Teal = Color3.fromRGB(40, 200, 190),
	Blue = Color3.fromRGB(60, 120, 230),
	Sapphire = Color3.fromRGB(50, 90, 230),
	Purple = Color3.fromRGB(150, 70, 220),
	Amethyst = Color3.fromRGB(170, 90, 230),
	Pink = Color3.fromRGB(255, 120, 190),
	Void = Color3.fromRGB(40, 16, 70),
	VoidGlow = Color3.fromRGB(170, 80, 255),
	Cursed = Color3.fromRGB(120, 20, 40),
	CursedGlow = Color3.fromRGB(255, 50, 70),
}

local MATERIALS: { [string]: Enum.Material } = {}
for _, m in Enum.Material:GetEnumItems() do
	MATERIALS[m.Name] = m
end
local function material(name: string?): Enum.Material
	return (name and MATERIALS[name]) or Enum.Material.SmoothPlastic
end
Forge.Material = material

local DEFAULTS = {
	Anchored = true,
	CanCollide = false,
	CanTouch = false,
	CanQuery = false,
	CastShadow = true,
}

local function apply(p: BasePart, props: { [string]: any }?)
	for k, v in DEFAULTS do
		(p :: any)[k] = v
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			if k == "Name" or k == "Transparency" or k == "Reflectance" or k == "CanCollide" or k == "CanQuery" or k == "CanTouch" or k == "CastShadow" or k == "Anchored" then
				(p :: any)[k] = v
			elseif k == "Accent" then
				if v then
					p:SetAttribute("ItemAccent", true)
				end
			elseif k == "Attributes" then
				for ak, av in v :: any do
					p:SetAttribute(ak, av)
				end
			end
		end
	end
end

local Builder = {}
Builder.__index = Builder

function Forge.Builder(name: string, options: { Lod: number?, Parent: Instance? }?): Builder
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	apply(root, nil)
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	local self = setmetatable({
		Model = model,
		Lod = options and options.Lod or 0,
		Parts = 0,
		_parent = model :: Instance,
	}, Builder)
	return (self :: any) :: Builder
end

local function finishPart(self: any, p: BasePart, props: { [string]: any }?, defaultName: string): BasePart
	if not (props and props.Name) then
		p.Name = defaultName
	end
	apply(p, props)
	p.Parent = self._parent
	self.Parts += 1
	return p
end

function Builder.Box(self: any, size: Vector3, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material(mat)
	return finishPart(self, p, props, "Box") :: Part
end

function Builder.Ball(self: any, diameter: number, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = cf
	p.Color = color
	p.Material = material(mat)
	return finishPart(self, p, props, "Ball") :: Part
end

-- Non-uniform sphere (egg, body, cushion): a Block with a Sphere SpecialMesh filling its size.
function Builder.Ellipsoid(self: any, size: Vector3, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material(mat)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return finishPart(self, p, props, "Ellipsoid") :: Part
end

-- Cylinder along the part's local X axis (Roblox convention).
function Builder.Cyl(self: any, length: number, diameter: number, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cf
	p.Color = color
	p.Material = material(mat)
	return finishPart(self, p, props, "Cylinder") :: Part
end
-- Vertical cylinder centred on cf (axis = cf.UpVector).
function Builder.CylY(self: any, height: number, diameter: number, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	return Builder.Cyl(self, height, diameter, cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, props)
end
-- Cylinder along cf.LookVector.
function Builder.CylZ(self: any, length: number, diameter: number, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): Part
	return Builder.Cyl(self, length, diameter, cf * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
end

-- WedgePart: full height at local +Z, the slope goes down towards -Z (front).
function Builder.Wedge(self: any, size: Vector3, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material(mat)
	return finishPart(self, p, props, "Wedge") :: WedgePart
end

-- Square bar from a to b (width x width section).
function Builder.Beam(self: any, a: Vector3, b: Vector3, width: number, color: Color3, mat: string?, props: { [string]: any }?): Part
	local len = (b - a).Magnitude
	return Builder.Box(self, Vector3.new(width, width, math.max(len, 0.05)), CFrame.lookAt((a + b) / 2, b), color, mat, props)
end
-- Round rod from a to b.
function Builder.Rod(self: any, a: Vector3, b: Vector3, diameter: number, color: Color3, mat: string?, props: { [string]: any }?): Part
	local len = (b - a).Magnitude
	return Builder.Cyl(self, math.max(len, 0.05), diameter, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
end

-- Torus approximation in the cf XZ plane (ring lying flat when cf is upright): segments short rods.
function Builder.Ring(self: any, cf: CFrame, radius: number, thickness: number, color: Color3, mat: string?, segments: number?, props: { [string]: any }?): { BasePart }
	local n = segments or 16
	local out: { BasePart } = {}
	local seg = 2 * math.pi * radius / n * 1.08
	for i = 1, n do
		local a = (i - 0.5) / n * 2 * math.pi
		local pos = cf:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
		local tangent = cf:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		local part = Builder.Cyl(self, seg, thickness, CFrame.lookAt(pos, pos + tangent, cf.UpVector) * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
		table.insert(out, part)
	end
	return out
end

-- Flat round plate (coin, lid, base) lying in the cf XZ plane.
function Builder.Disc(self: any, cf: CFrame, diameter: number, thickness: number, color: Color3, mat: string?, props: { [string]: any }?): Part
	return Builder.CylY(self, thickness, diameter, cf, color, mat, props)
end

-- Stepped cone / taper along cf.UpVector from the base (cf) to the tip; steps >= 2.
function Builder.Cone(self: any, cf: CFrame, height: number, baseDiameter: number, tipDiameter: number, steps: number, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	local out: { BasePart } = {}
	local n = math.max(2, steps)
	local h = height / n
	for i = 1, n do
		local f = (i - 0.5) / n
		local d = baseDiameter + (tipDiameter - baseDiameter) * f
		table.insert(out, Builder.CylY(self, h * 1.02, math.max(d, 0.02), cf * CFrame.new(0, h * (i - 0.5), 0), color, mat, props))
	end
	return out
end

-- Faceted gem: a cube turned onto a vertex plus a smaller crossed cube (reads as cut facets).
function Builder.Gem(self: any, size: number, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	local m = mat or "Glass"
	local out: { BasePart } = {}
	local a = Builder.Box(self, Vector3.one * size, cf * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), color, m, props)
	local b = Builder.Box(self, Vector3.one * size * 0.82, cf * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(45), 0, 0), color:Lerp(Color3.new(1, 1, 1), 0.12), m, props)
	table.insert(out, a)
	table.insert(out, b)
	return out
end

-- Crystal prism: a square column with a two-wedge pointed tip, standing on cf (base centre).
function Builder.Prism(self: any, cf: CFrame, width: number, height: number, tip: number, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	local out: { BasePart } = {}
	local m = mat or "Glass"
	table.insert(out, Builder.Box(self, Vector3.new(width, height, width), cf * CFrame.new(0, height / 2, 0), color, m, props))
	-- two wedges back to back form the ridge of the tip
	-- (a wedge is full height at its local +Z: each half turns its tall face to the middle)
	table.insert(out, Builder.Wedge(self, Vector3.new(width, tip, width / 2), cf * CFrame.new(0, height + tip / 2, -width / 4), color, m, props))
	table.insert(out, Builder.Wedge(self, Vector3.new(width, tip, width / 2), cf * CFrame.new(0, height + tip / 2, width / 4) * CFrame.Angles(0, math.pi, 0), color, m, props))
	return out
end

-- Gable roof: two wedges meeting at a ridge along cf X, size = (length, height, depth).
function Builder.Roof(self: any, size: Vector3, cf: CFrame, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	local half = Vector3.new(size.X, size.Y, size.Z / 2)
	local out: { BasePart } = {}
	table.insert(out, Builder.Wedge(self, half, cf * CFrame.new(0, 0, -size.Z / 4), color, mat, props))
	table.insert(out, Builder.Wedge(self, half, cf * CFrame.new(0, 0, size.Z / 4) * CFrame.Angles(0, math.pi, 0), color, mat, props))
	return out
end

-- A light on a part. kind: "Point" (default) | "Spot" | "Surface".
function Builder.Light(self: any, part: BasePart, color: Color3, range: number, brightness: number?, kind: string?): Light
	local light: Light
	if kind == "Spot" then
		light = Instance.new("SpotLight")
	elseif kind == "Surface" then
		light = Instance.new("SurfaceLight")
	else
		light = Instance.new("PointLight")
	end
	light.Color = color
	light.Brightness = brightness or 1.2
	;(light :: any).Range = range
	light.Shadows = false
	light.Parent = part
	return light
end

function Builder.Accent(self: any, part: any): any
	if typeof(part) == "Instance" then
		part:SetAttribute("ItemAccent", true)
	elseif type(part) == "table" then
		for _, p in part do
			p:SetAttribute("ItemAccent", true)
		end
	end
	return part
end

-- Work that only exists at full detail (Lod 0): engraving, rivets, small trims.
function Builder.Detail(self: any, fn: () -> ())
	if self.Lod <= 0 then
		fn()
	end
end

-- Sub-model (moving part groups: lids, rotors, arms). Following parts go into it until b:Into(model).
function Builder.Folder(self: any, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = self._parent
	self._parent = m
	return m
end
function Builder.Into(self: any, parent: Instance)
	self._parent = parent
end

function Builder.Finish(self: any): Model
	self._parent = self.Model
	self.Model:SetAttribute("ForgeParts", self.Parts)
	return self.Model
end

-- Counts BaseParts under an instance (budget checks in tests and QA).
function Forge.CountParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return Forge
