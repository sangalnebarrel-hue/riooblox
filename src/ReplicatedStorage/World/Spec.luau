-- Pure part specifications for code-built world geometry (docs/OVERHAUL.md, "Клиентский фундамент").
-- A layout module returns a list of plain spec tables; World.Builder turns them into Instances,
-- tests check them in Lune (part counts, bounds, determinism) and tools/preview renders them.
-- No Instance API here: only Vector3 / CFrame / Color3 values and tables.
--
-- A part spec:
--   { Class = "Part" | "WedgePart" | "CornerWedgePart" | "TrussPart",
--     Shape = "Block" | "Ball" | "Cylinder",           -- Part only; Cylinder's axis is X (as in Roblox)
--     Name, Size = Vector3, CFrame = CFrame,             -- CFrame relative to the anchor
--     Color = Color3, Material = "Neon" (an Enum.Material name), Transparency, Reflectance,
--     CastShadow = nil (Builder decides) | boolean, CanCollide = false (default), CanQuery, CanTouch,
--     Tags = { "Tag" }, Attributes = { Key = value }, Props = { AnyProperty = value },
--     Children = { child specs } }
-- A child spec (lights, emitters, attachments, beams, surface GUIs and their labels):
--   { Class = "PointLight", Range = 12, ... any property ..., Children = { ... } }
--   Enum properties may be given by name (Face = "Front"). A Beam names its attachments:
--   Attachment0 = "TopA", Attachment1 = "TopB" (attachment Names anywhere in the same build).
--
--   local S = Spec
--   local base = S.Block("Base", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), S.Mat("Marble", WHITE))
--   local lamp = S.Ball("Lamp", 1.5, CFrame.new(0, 6, 0), S.Neon(GOLD, { Children = { S.PointLight({ Range = 14 }) } }))
--   local posts = S.Ring({ S.Cylinder("Post", 5, 0.6, CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2)) }, 6, 3.5)
--   local specs = S.Concat({ base, lamp }, posts, S.MirrorX(sideDecor))
--   S.PartCount(specs), S.Bounds(specs), S.Count(specs), S.Validate(specs)
local Spec = {}

Spec.PartClasses = { Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true }
Spec.Shapes = { Block = true, Ball = true, Cylinder = true }
Spec.DefaultColor = Color3.fromRGB(163, 162, 165)

local PART_KEYS = {
	Class = true, Shape = true, Name = true, Size = true, CFrame = true, Color = true, Material = true,
	Transparency = true, Reflectance = true, CastShadow = true, CanCollide = true, CanQuery = true,
	CanTouch = true, Anchored = true, Tags = true, Attributes = true, Props = true, Children = true,
}
Spec.PartKeys = PART_KEYS

local function copy(t: any): any
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- Shallow merge, later tables win. Children and Tags lists are concatenated, Attributes / Props merged.
function Spec.Merge(...: any): any
	local out: any = {}
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if t then
			for k, v in pairs(t) do
				if (k == "Children" or k == "Tags") and out[k] then
					local list = table.clone(out[k])
					for _, item in ipairs(v) do
						table.insert(list, item)
					end
					out[k] = list
				elseif (k == "Attributes" or k == "Props") and out[k] then
					local merged = copy(out[k])
					for key, value in pairs(v) do
						merged[key] = value
					end
					out[k] = merged
				else
					out[k] = v
				end
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------
-- Parts
------------------------------------------------------------------------------------------------

-- A part spec from a props table; fills the defaults of every key Builder reads.
function Spec.Part(props: any): any
	local s = Spec.Merge(props)
	s.Class = s.Class or "Part"
	if s.Class == "Part" then
		s.Shape = s.Shape or "Block"
	end
	s.Name = s.Name or s.Class
	s.Size = s.Size or Vector3.new(1, 1, 1)
	s.CFrame = s.CFrame or CFrame.identity
	s.Color = s.Color or Spec.DefaultColor
	s.Material = s.Material or "SmoothPlastic"
	s.Transparency = s.Transparency or 0
	s.Reflectance = s.Reflectance or 0
	s.CanCollide = s.CanCollide == true
	return s
end

function Spec.Block(name: string, size: Vector3, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, { Class = "Part", Shape = "Block", Name = name, Size = size, CFrame = cframe }))
end

-- A sphere of `diameter` studs (Roblox balls are uniform).
function Spec.Ball(name: string, diameter: number, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, {
		Class = "Part", Shape = "Ball", Name = name, Size = Vector3.new(diameter, diameter, diameter), CFrame = cframe,
	}))
end

-- A cylinder along its local X axis: `length` studs long, `diameter` wide (as in Roblox).
-- Stand one up with CFrame.Angles(0, 0, math.pi / 2).
function Spec.Cylinder(name: string, length: number, diameter: number, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, {
		Class = "Part", Shape = "Cylinder", Name = name, Size = Vector3.new(length, diameter, diameter), CFrame = cframe,
	}))
end

-- Roblox wedge: full height at the back (+Z), sloping down to the front (-Z).
function Spec.Wedge(name: string, size: Vector3, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, { Class = "WedgePart", Name = name, Size = size, CFrame = cframe }))
end

-- Roblox corner wedge: its peak is the (+X, +Y, -Z) corner, sloping down towards -X and +Z.
function Spec.CornerWedge(name: string, size: Vector3, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, { Class = "CornerWedgePart", Name = name, Size = size, CFrame = cframe }))
end

function Spec.Truss(name: string, size: Vector3, cframe: CFrame?, props: any?): any
	return Spec.Part(Spec.Merge(props, { Class = "TrussPart", Name = name, Size = size, CFrame = cframe }))
end

-- A copy of `spec` with `props` merged over it.
function Spec.With(spec: any, props: any): any
	return Spec.Merge(spec, props)
end

------------------------------------------------------------------------------------------------
-- Material presets (props to pass as the last argument, or to merge with Spec.Merge)
------------------------------------------------------------------------------------------------

function Spec.Mat(material: string, color: Color3?, extra: any?): any
	return Spec.Merge({ Material = material, Color = color }, extra)
end

-- Glowing: never casts a shadow.
function Spec.Neon(color: Color3, extra: any?): any
	return Spec.Merge({ Material = "Neon", Color = color, CastShadow = false }, extra)
end

function Spec.Glass(color: Color3, transparency: number?, extra: any?): any
	return Spec.Merge({ Material = "Glass", Color = color, Transparency = transparency or 0.45, Reflectance = 0.08, CastShadow = false }, extra)
end

function Spec.Metal(color: Color3, extra: any?): any
	return Spec.Merge({ Material = "Metal", Color = color, Reflectance = 0.05 }, extra)
end

function Spec.ForceField(color: Color3, transparency: number?, extra: any?): any
	return Spec.Merge({ Material = "ForceField", Color = color, Transparency = transparency or 0.2, CastShadow = false }, extra)
end

------------------------------------------------------------------------------------------------
-- Child specs
------------------------------------------------------------------------------------------------

function Spec.Child(className: string, props: any?): any
	return Spec.Merge(props, { Class = className })
end

function Spec.PointLight(props: any?): any
	return Spec.Merge({ Class = "PointLight", Range = 12, Brightness = 1, Color = Color3.new(1, 1, 1), Shadows = false }, props)
end

function Spec.SpotLight(props: any?): any
	return Spec.Merge({ Class = "SpotLight", Range = 16, Brightness = 2, Angle = 60, Face = "Front", Color = Color3.new(1, 1, 1), Shadows = false }, props)
end

function Spec.SurfaceLight(props: any?): any
	return Spec.Merge({ Class = "SurfaceLight", Range = 12, Brightness = 1, Angle = 90, Face = "Front", Color = Color3.new(1, 1, 1), Shadows = false }, props)
end

function Spec.Emitter(props: any?): any
	return Spec.Merge({ Class = "ParticleEmitter" }, props)
end

function Spec.Attachment(name: string, cframe: CFrame?, props: any?): any
	return Spec.Merge(props, { Class = "Attachment", Name = name, CFrame = cframe or CFrame.identity })
end

-- A beam between two attachments of the same build, named by their Name.
function Spec.Beam(name: string, attachment0: string, attachment1: string, props: any?): any
	return Spec.Merge(props, { Class = "Beam", Name = name, Attachment0 = attachment0, Attachment1 = attachment1 })
end

-- A SurfaceGui on `face` with one TextLabel filling it. labelProps go to the TextLabel.
function Spec.Label(face: string, text: string, labelProps: any?, guiProps: any?): any
	local label = Spec.Merge({
		Class = "TextLabel", Name = "Text", Text = text, BackgroundTransparency = 1, TextScaled = true,
		Size = UDim2.fromScale(1, 1), TextColor3 = Color3.new(1, 1, 1),
	}, labelProps)
	return Spec.Merge({ Class = "SurfaceGui", Name = "Label", Face = face, PixelsPerStud = 40, SizingMode = "PixelsPerStud", LightInfluence = 0 }, guiProps, { Children = { label } })
end

------------------------------------------------------------------------------------------------
-- Transforms (new lists; inputs are never modified)
------------------------------------------------------------------------------------------------

local function list(specs: any): { any }
	if specs.Class ~= nil then
		return { specs } -- a single spec
	end
	return specs
end

local function transformed(spec: any, cframe: CFrame): any
	local s = copy(spec)
	s.CFrame = cframe * (spec.CFrame or CFrame.identity)
	return s
end

local function asCFrame(by: any): CFrame
	if typeof(by) == "Vector3" then
		return CFrame.new(by)
	end
	return by
end

-- Moves every spec: new CFrame = by * CFrame (by: CFrame or Vector3), in the anchor's space.
function Spec.Offset(specs: any, by: any): { any }
	local cf = asCFrame(by)
	local out = {}
	for _, spec in ipairs(list(specs)) do
		table.insert(out, transformed(spec, cf))
	end
	return out
end
Spec.Transform = Spec.Offset

-- Turns every spec around the anchor's origin: yaw in degrees around +Y, or any rotation CFrame.
function Spec.Rotate(specs: any, rotation: any): { any }
	local cf = type(rotation) == "number" and CFrame.Angles(0, math.rad(rotation), 0) or rotation
	return Spec.Offset(specs, cf)
end

-- Mirror image across the anchor's YZ plane (x -> -x). Boxes, balls, cylinders, trusses and
-- wedges are symmetric along their own X, so M * CF * M is exact; a corner wedge is not, so it is
-- turned a quarter around Y with its X / Z sizes swapped to keep its peak at the mirrored corner.
-- Children follow their part: a child CFrame / Position (attachments) is mirrored in the part's
-- space, and a face (Face, EmissionDirection: signs, surface / spot lights, emitters) that pointed
-- along the part's X now points the other way (Left <-> Right), so mirrored signs face outwards.
local QUARTER = CFrame.Angles(0, math.pi / 2, 0)
local UNQUARTER = QUARTER:Inverse()
function Spec.MirrorCFrame(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local NORMALS = {
	Right = Vector3.new(1, 0, 0), Left = Vector3.new(-1, 0, 0), Top = Vector3.new(0, 1, 0),
	Bottom = Vector3.new(0, -1, 0), Back = Vector3.new(0, 0, 1), Front = Vector3.new(0, 0, -1),
}
local FACE_KEYS = { "Face", "EmissionDirection" }

local function mirrorVector(v: Vector3): Vector3
	return Vector3.new(-v.X, v.Y, v.Z)
end

-- A NormalId name (or EnumItem) mirrored, then turned by `turn` (a pure rotation).
local function mirrorFace(face: any, turn: CFrame): any
	local name = if typeof(face) == "EnumItem" then face.Name else face
	local normal = NORMALS[name]
	if not normal then
		return face
	end
	local mirrored = turn * mirrorVector(normal)
	for candidate, n in pairs(NORMALS) do
		if n:Dot(mirrored) > 0.5 then
			return candidate
		end
	end
	return face
end

-- Children of a mirrored part. `turn` is the rotation the mirrored parent added on top of the
-- mirror (a corner wedge's quarter turn, undone here); deeper levels need none.
local function mirrorChildren(children: { any }, turn: CFrame): { any }
	local out = {}
	for _, child in ipairs(children) do
		local c = copy(child)
		if typeof(child.CFrame) == "CFrame" then
			c.CFrame = turn * Spec.MirrorCFrame(child.CFrame)
		end
		if typeof(child.Position) == "Vector3" then
			c.Position = turn * mirrorVector(child.Position)
		end
		for _, key in ipairs(FACE_KEYS) do
			if child[key] ~= nil then
				c[key] = mirrorFace(child[key], turn)
			end
		end
		if child.Children then
			c.Children = mirrorChildren(child.Children, CFrame.identity)
		end
		table.insert(out, c)
	end
	return out
end

function Spec.MirrorX(specs: any): { any }
	local out = {}
	for _, spec in ipairs(list(specs)) do
		local s = copy(spec)
		local cf = Spec.MirrorCFrame(spec.CFrame or CFrame.identity)
		local turn = CFrame.identity
		if spec.Class == "CornerWedgePart" then
			local size = spec.Size or Vector3.new(1, 1, 1)
			s.Size = Vector3.new(size.Z, size.Y, size.X)
			cf = cf * QUARTER
			turn = UNQUARTER
		end
		s.CFrame = cf
		if spec.Children then
			s.Children = mirrorChildren(spec.Children, turn)
		end
		table.insert(out, s)
	end
	return out
end

local function suffixed(spec: any, i: number): any
	local s = copy(spec)
	if s.Name then
		s.Name = s.Name .. "_" .. i
	end
	return s
end

-- `count` copies; copy i (1-based) is moved by step applied i - 1 times (step: Vector3 or CFrame).
function Spec.Array(specs: any, count: number, step: any): { any }
	local stepCf = asCFrame(step)
	local out = {}
	local at = CFrame.identity
	for i = 1, count do
		for _, spec in ipairs(list(specs)) do
			table.insert(out, transformed(suffixed(spec, i), at))
		end
		at = at * stepCf
	end
	return out
end

-- Copies on an arc around the anchor's +Y axis, from `fromDegrees` to `toDegrees` (inclusive).
-- The template is authored at the origin; each copy sits `radius` studs out along its own -Z.
-- options.Face: "Out" (default, the template's -Z points away from the centre), "In", or "Fixed"
-- (positions only, the template's rotation is kept).
function Spec.Arc(specs: any, count: number, radius: number, fromDegrees: number, toDegrees: number, options: any?): { any }
	local face = options and options.Face or "Out"
	local out = {}
	for i = 1, count do
		local t = count == 1 and 0.5 or (i - 1) / (count - 1)
		local angle = math.rad(fromDegrees + (toDegrees - fromDegrees) * t)
		local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		if face == "In" then
			base = base * CFrame.Angles(0, math.pi, 0)
		elseif face == "Fixed" then
			base = CFrame.new(base.Position)
		end
		for _, spec in ipairs(list(specs)) do
			table.insert(out, transformed(suffixed(spec, i), base))
		end
	end
	return out
end

-- `count` copies evenly around a full circle (no duplicate at 360 degrees).
function Spec.Ring(specs: any, count: number, radius: number, options: any?): { any }
	local start = options and options.Start or 0
	local last = start + 360 * (count - 1) / math.max(1, count)
	return Spec.Arc(specs, count, radius, start, last, options)
end

-- One list from several lists or single specs.
function Spec.Concat(...: any): { any }
	local out = {}
	for i = 1, select("#", ...) do
		local item = select(i, ...)
		if item then
			for _, spec in ipairs(list(item)) do
				table.insert(out, spec)
			end
		end
	end
	return out
end

-- World-space copies (CFrame = anchor * CFrame) for exporters and previews.
function Spec.Flatten(specs: any, anchor: CFrame?): { any }
	return Spec.Offset(specs, anchor or CFrame.identity)
end

------------------------------------------------------------------------------------------------
-- Queries
------------------------------------------------------------------------------------------------

function Spec.IsPart(spec: any): boolean
	return type(spec) == "table" and Spec.PartClasses[spec.Class or "Part"] == true
end

function Spec.PartCount(specs: any): number
	local n = 0
	for _, spec in ipairs(list(specs)) do
		if Spec.IsPart(spec) then
			n += 1
		end
	end
	return n
end

local CHILD_KINDS = {
	PointLight = "Lights", SpotLight = "Lights", SurfaceLight = "Lights",
	ParticleEmitter = "Emitters", Fire = "Emitters", Smoke = "Emitters", Sparkles = "Emitters",
	Beam = "Beams", Trail = "Beams", Attachment = "Attachments",
	SurfaceGui = "Guis", BillboardGui = "Guis", Highlight = "Highlights",
}

-- Budget counts: {Parts, Lights, Emitters, Beams, Attachments, Guis, Highlights, Other}.
function Spec.Count(specs: any): any
	local counts = { Parts = 0, Lights = 0, Emitters = 0, Beams = 0, Attachments = 0, Guis = 0, Highlights = 0, Other = 0 }
	local function children(spec: any)
		for _, child in ipairs(spec.Children or {}) do
			local kind = CHILD_KINDS[child.Class]
			if kind then
				counts[kind] += 1
			elseif not (child.Class == "TextLabel" or child.Class == "ImageLabel" or child.Class == "Frame") then
				counts.Other += 1
			end
			children(child)
		end
	end
	for _, spec in ipairs(list(specs)) do
		if Spec.IsPart(spec) then
			counts.Parts += 1
		end
		children(spec)
	end
	return counts
end

local CORNERS = {
	Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1),
}

-- Axis-aligned bounds (in the anchor's space) of every part's box: {Min, Max, Size, Center}, or nil.
function Spec.Bounds(specs: any): any
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, spec in ipairs(list(specs)) do
		if Spec.IsPart(spec) then
			local half = (spec.Size or Vector3.new(1, 1, 1)) / 2
			local cf = spec.CFrame or CFrame.identity
			for _, corner in ipairs(CORNERS) do
				local p = cf * (corner * half)
				x0, y0, z0 = math.min(x0, p.X), math.min(y0, p.Y), math.min(z0, p.Z)
				x1, y1, z1 = math.max(x1, p.X), math.max(y1, p.Y), math.max(z1, p.Z)
			end
		end
	end
	if x0 == math.huge then
		return nil
	end
	local minV, maxV = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
	return { Min = minV, Max = maxV, Size = maxV - minV, Center = (minV + maxV) / 2 }
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Structural check for layout tests: returns ok, {messages}.
function Spec.Validate(specs: any): (boolean, { string })
	local problems = {}
	for i, spec in ipairs(list(specs)) do
		local label = string.format("#%d %s", i, tostring(spec.Name))
		if not Spec.PartClasses[spec.Class or "Part"] then
			table.insert(problems, label .. ": unknown class " .. tostring(spec.Class))
		end
		if spec.Shape ~= nil and not Spec.Shapes[spec.Shape] then
			table.insert(problems, label .. ": unknown shape " .. tostring(spec.Shape))
		end
		local size = spec.Size
		if typeof(size) ~= "Vector3" or not (finite(size.X) and finite(size.Y) and finite(size.Z)) or size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
			table.insert(problems, label .. ": bad size " .. tostring(size))
		end
		local cf = spec.CFrame
		if typeof(cf) ~= "CFrame" then
			table.insert(problems, label .. ": CFrame missing")
		else
			for _, n in ipairs({ cf:GetComponents() }) do
				if not finite(n) then
					table.insert(problems, label .. ": CFrame is not finite")
					break
				end
			end
		end
		if spec.Material ~= nil and type(spec.Material) ~= "string" then
			table.insert(problems, label .. ": Material must be an Enum.Material name")
		end
		for key in pairs(spec) do
			if not PART_KEYS[key] then
				table.insert(problems, label .. ": unknown key " .. tostring(key) .. " (use Props)")
			end
		end
	end
	return #problems == 0, problems
end

------------------------------------------------------------------------------------------------
-- Deterministic random numbers (identical in Lune and Roblox; Park-Miller)
------------------------------------------------------------------------------------------------

function Spec.Rng(seed: number): any
	local state = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if state == 0 then
		state = 1
	end
	local rng = {}
	function rng.Number(a: number?, b: number?): number
		state = (state * 48271) % 2147483647
		local x = state / 2147483647
		if a and b then
			return a + (b - a) * x
		end
		return x
	end
	function rng.Integer(a: number, b: number): number
		return math.min(b, a + math.floor(rng.Number() * (b - a + 1)))
	end
	function rng.Pick(items: { any }): any
		return items[rng.Integer(1, #items)]
	end
	return rng
end

return Spec
