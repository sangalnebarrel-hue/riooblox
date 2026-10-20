-- NIGHT OF THE BURIED MOON · event dogs H01-H08 (ReplicatedStorage.Halloween.Models.EventDogs, WP4 + polish P2).
-- Voxel dogs built from Parts (no meshes, no free models). One builder for every consumer:
--   * the place build (ServerStorage.HalloweenBuild.Dogs via hw/edits/dogs.luau) saves each model in
--     ServerStorage.DogTemplates.<Id> and ReplicatedStorage.MenuModels.<Id> and generates the clip ModuleScripts
--     ReplicatedStorage.DogAnimationClips.<Id>.<clip> for every name in EventDogs.ClipNamesFor(id);
--   * runtime UI (Halloween window previews) may call EventDogs.Build(id) for a fresh copy.
-- Rig contract (ReplicatedStorage.DogAnimationPlayer + ApplyParts):
--   Model <Id> (PrimaryPart RootPart at the ground centre, head toward -Z, feet on y = 0, ~4.5-6 studs tall at scale 1)
--     attrs DogId, AnimationBaseScale = 1, AnimationSource = "DogAnimationClips", DogPartRig = true, EventDex
--   RootPart > Root (Bone) > Body > ... unique bone names, every Bone.CFrame a pure translation (bind pose). Paw_* are
--   the four lowest bones (DogAnimationPlayer's dig lift picks the hind paws that way): no bone sits below them.
--   Every visible BasePart carries DogBone = <bone name> and DogBoneOffset = <its CFrame in that bone's rest space,
--   template units>, so DogAnimationPlayer:ApplyParts moves it with the bone (parts never need welds or scripts).
-- Ability FX hooks: Attachments named "HwFX_<Name>" under parts (attrs HwFX = recipe, HwFXColor, HwFXColor2, HwFXRate,
--   HwFXLight, SelfManagedFX = true so WorldDetailQuality never takes over what a caller adds). They move with the parts
--   and survive Rig.Prepare. EventDogs.StartFX(model, opts) (client) runs their looping particles + light,
--   EventDogs.BurstFX(model, count) emits one burst (a find / ability proc). Nothing runs unless a caller asks.
-- Clips: {duration, loop, fps, category, tracks = {[bone] = {{px, py, pz, qx, qy, qz, qw}, ...}}} (Bone.Transform per
-- frame); generated procedurally here (EventDogs.Clip) so tests can check them without the place. Besides the kennel
-- chain (Idle / DigStart / DigLoop / DigEnd / DigFind) every dog has Walk, Run, Sniff, Sleep, Happy, RareFind and a
-- signature clip ("Signature", also saved under the dog's own name, EventDogs.Spec(id).SignatureName).
local E = {}
E.Version = 2
E.Order = { "HW_PumpkinPup", "HW_SheetShiba", "HW_BoneCorgi", "HW_Frankenpug", "HW_BatDachshund", "HW_PlaguePug",
	"HW_HeadlessHound", "HW_EclipseDog" }
E.ClipNames = { "Idle", "Walk", "DigStart", "DigLoop", "DigEnd", "DigFind", "Happy", "Sniff", "Run", "Sleep", "RareFind", "Signature" }
E.FPS = 20
E.EventDex = "BuriedMoon2026"

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local MAT = Enum.Material
local PI = math.pi
local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function toCF(cf: any): CFrame
	if typeof(cf) == "Vector3" then
		return CF(cf)
	end
	return cf
end

---------------------------------------------------------------------------------------------------------------------
-- Rig builder
---------------------------------------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig

local function newRig(id: string, spec: any)
	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = V3(0.2, 0.2, 0.2)
	root.CFrame = CF()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root
	local self = setmetatable({ Id = id, Model = model, Root = root, Bones = {}, Rest = {}, Count = 0, Names = {}, Hooks = 0 }, Rig)
	for _, b in ipairs(spec.Bones) do
		self:Bone(b[1], b[2], b[3])
	end
	return self
end

function Rig:Bone(name: string, parent: string?, pos: Vector3)
	assert(self.Bones[name] == nil, "duplicate bone " .. name)
	local bone = Instance.new("Bone")
	bone.Name = name
	local parentPos = parent and self.Rest[parent] or V3(0, 0, 0)
	bone.CFrame = CF(pos - parentPos)
	bone.Parent = parent and self.Bones[parent] or self.Root
	self.Bones[name] = bone
	self.Rest[name] = pos
	return bone
end

-- opts: Shape, Transparency, Reflectance, Shadow (false = no shadow)
function Rig:Add(class: string, bone: string, name: string, size: Vector3, cf: any, color: Color3, material: Enum.Material?, opts: any?)
	opts = opts or {}
	local rest = self.Rest[bone]
	assert(rest, "unknown bone " .. tostring(bone) .. " (" .. name .. ")")
	cf = toCF(cf)
	-- part names stay unique (tests and tools key parts by name)
	if self.Names[name] then
		local n = self.Names[name] + 1
		self.Names[name] = n
		name = name .. "_" .. n
	end
	self.Names[name] = 1
	local p = Instance.new(class)
	p.Name = name
	if opts.Shape then
		(p :: any).Shape = opts.Shape
	end
	p.Size = V3(math.max(0.02, size.X), math.max(0.02, size.Y), math.max(0.02, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material or MAT.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	-- only the big masses cast shadows (moving shadow casters are what costs): trims, eyes, toes and seams do not
	p.CastShadow = (material ~= MAT.Neon) and opts.Shadow ~= false and math.min(size.X, size.Y, size.Z) > 0.22
		and size.X * size.Y * size.Z > 0.12
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Transparency then
		p.Transparency = opts.Transparency
	end
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	p:SetAttribute("DogBone", bone)
	p:SetAttribute("DogBoneOffset", CF(-rest) * cf)
	if size.X * size.Y * size.Z < 0.0012 and material ~= MAT.Neon then
		-- optional LOD hook: a Low-quality client may hide these tiny trims (stitches, specks, nails) before animating
		p:SetAttribute("DogDetail", true)
	end
	p.Parent = self.Model
	self.Count += 1
	return p
end
function Rig:Box(bone, name, size, cf, color, mat, opts)
	return self:Add("Part", bone, name, size, cf, color, mat, opts)
end
function Rig:Wedge(bone, name, size, cf, color, mat, opts)
	return self:Add("WedgePart", bone, name, size, cf, color, mat, opts)
end
function Rig:Corner(bone, name, size, cf, color, mat, opts)
	return self:Add("CornerWedgePart", bone, name, size, cf, color, mat, opts)
end
function Rig:Neon(bone, name, size, cf, color, opts)
	return self:Add("Part", bone, name, size, cf, color, MAT.Neon, opts)
end
function Rig:Ball(bone, name, d, pos, color, mat, opts)
	opts = table.clone(opts or {})
	opts.Shape = Enum.PartType.Ball
	return self:Add("Part", bone, name, V3(d, d, d), pos, color, mat, opts)
end
-- Cylinder along the part's X axis.
function Rig:Cyl(bone, name, length, d, cf, color, mat, opts)
	opts = table.clone(opts or {})
	opts.Shape = Enum.PartType.Cylinder
	return self:Add("Part", bone, name, V3(length, d, d), cf, color, mat, opts)
end
-- Isosceles triangle (two WedgeParts) in the XY plane around `center`, visible from -Z and +Z; down = apex at the bottom.
-- `turn` (optional CFrame rotation) turns the whole triangle about its centre (e.g. to put it on a side face).
function Rig:Tri(bone, name, center: Vector3, w: number, h: number, depth: number, color, mat, down: boolean?, turn: CFrame?)
	local size = V3(depth, h, w / 2)
	local flip = down and ANG(0, 0, PI) or CF()
	local a = down and -1 or 1
	local base = CF(center) * (turn or CF())
	self:Wedge(bone, name .. "A", size, base * CF(-w / 4, 0, 0) * flip * ANG(0, a * PI / 2, 0), color, mat)
	self:Wedge(bone, name .. "B", size, base * CF(w / 4, 0, 0) * flip * ANG(0, -a * PI / 2, 0), color, mat)
end
-- A baked accent light. Saved OFF and tagged DogLight; its part carries SelfManagedFX so WorldDetailQuality never
-- budgets it with the yard lights: DogAnimationPlayer's part-rig LOD switches it on near the camera (not on Low).
-- Static copies (yard displays, viewports) stay unlit and keep their Neon glow.
function Rig:Light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = false
	l:SetAttribute("DogLight", true)
	part:SetAttribute("SelfManagedFX", true)
	l.Parent = part
	return l
end
-- fn(s, side): s = 1 for the L side (+X), -1 for the R side (-X)
function Rig:Pair(fn)
	fn(1, "L")
	fn(-1, "R")
end

-- Bevelled block: three overlapping cores (X / Y / Z) read as one voxel block with stepped (chamfered) edges.
-- `top` (optional) colours the Y core: a lighter crown / darker underside band.
function Rig:Round(bone, name, size: Vector3, cf, color, mat, b: number?, top: Color3?)
	cf = toCF(cf)
	b = b or math.min(size.X, size.Y, size.Z) * 0.2
	self:Box(bone, name, V3(size.X, size.Y - 2 * b, size.Z - 2 * b), cf, color, mat)
	self:Box(bone, name .. "Y", V3(size.X - 2 * b, size.Y, size.Z - 2 * b), cf, top or color, mat)
	return self:Box(bone, name .. "Z", V3(size.X - 2 * b, size.Y - 2 * b, size.Z), cf, color, mat)
end

-- A box from a to b (model space), its Y axis along a -> b.
function Rig:Seg(bone, name, a: Vector3, b: Vector3, w: number, d: number?, color, mat, opts)
	local mid = (a + b) / 2
	local dir = b - a
	local up = dir.Unit
	local ref = math.abs(up.Y) < 0.95 and V3(0, 1, 0) or V3(1, 0, 0)
	local right = ref:Cross(up).Unit
	local back = right:Cross(up).Unit
	return self:Add("Part", bone, name, V3(w, dir.Magnitude, d or w), CFrame.fromMatrix(mid, right, up, back), color, mat, opts)
end

-- A layered eye on a face that looks toward -Z: rim (socket / lid line), white, iris, pupil and a catch-light.
-- c = centre on the face plane. o: Rim, White, Iris, Pupil, Shine, Glow (Neon iris), Turn (rotation), Look (iris
-- offset V3), IrisK (iris share of the eye), PupilK, Lid (colour of an upper lid band), NoWhite.
function Rig:Eye(bone, name, c: Vector3, w: number, h: number, o: any)
	local base = CF(c) * (o.Turn or CF())
	local d = 0.03
	local z = 0
	local function layer(n, size, x, y, color, mat)
		z -= d
		return self:Add("Part", bone, name .. n, V3(size.X, size.Y, d + 0.004), base * CF(x, y, z + d / 2), color, mat)
	end
	if o.Rim then
		layer("Rim", V3(w + 0.1, h + 0.1, 0), 0, 0, o.Rim)
	end
	if not o.NoWhite then
		layer("White", V3(w, h, 0), 0, 0, o.White or C(250, 246, 236))
	end
	local look = o.Look or V3(0, 0, 0)
	local k = o.IrisK or 0.66
	local iw, ih = w * k, h * k
	layer("Iris", V3(iw, ih, 0), look.X, look.Y, o.Iris, o.Glow and MAT.Neon or nil)
	local pk = o.PupilK or 0.5
	layer("Pupil", V3(iw * pk, ih * (pk + 0.08), 0), look.X, look.Y - ih * 0.04, o.Pupil or C(14, 10, 20))
	layer("Shine", V3(math.max(0.05, iw * 0.3), math.max(0.05, ih * 0.3), 0), look.X + iw * 0.24, look.Y + ih * 0.24, o.Shine or C(255, 255, 255), MAT.Neon)
	if o.Lid then
		self:Add("Part", bone, name .. "Lid", V3(w + 0.12, h * 0.26, 0.05), base * CF(0, h * 0.42, -0.04), o.Lid)
	end
end

-- A paw on the ground toward -Z: bevelled sole block, three toes (dark gaps between them read as toe beans) and
-- optional nails. `bone` carries it all (the Paw_* bone).
function Rig:Paw(bone, tag: string, x: number, z: number, w: number, d: number, h: number, color, o: any?)
	o = o or {}
	self:Round(bone, "Paw_" .. tag, V3(w, h, d), V3(x, h / 2, z), color, o.Mat, math.min(0.07, h * 0.22), o.Top)
	local tw = (w - 0.08) / 3
	local front = z - d / 2
	for i = -1, 1 do
		local tx = x + i * (tw + 0.04)
		self:Box(bone, "Toe" .. (i + 2) .. "_" .. tag, V3(tw, h * 0.66, 0.2), V3(tx, h * 0.33, front - 0.07), o.Toe or color, o.Mat)
		if o.Nail then
			self:Box(bone, "Nail" .. (i + 2) .. "_" .. tag, V3(tw * 0.5, 0.08, 0.1), V3(tx, 0.05, front - 0.2), o.Nail, o.NailMat)
		end
	end
	if o.Bean then
		self:Box(bone, "Bean_" .. tag, V3(w - 0.12, 0.05, 0.12), V3(x, 0.03, front - 0.03), o.Bean)
	end
end

-- A stepped fur tuft / flame tongue / drip: `steps` boxes shrinking along the frame's -Y from `cf` (the root),
-- alternating two colours. Turn `cf` to point it (ANG(PI, 0, 0) = upward).
function Rig:Tuft(bone, name, cf, len: number, w: number, steps: number, color, color2, mat, depthK: number?)
	cf = toCF(cf)
	local seg = len / steps
	for i = 1, steps do
		local k = 1 - (i - 1) / steps * 0.72
		self:Add("Part", bone, name .. i, V3(w * k, seg * 1.12, w * k * (depthK or 0.8)), cf * CF(0, -(i - 0.5) * seg, 0),
			(i % 2 == 0 and color2) or color, mat)
	end
end

-- An ability FX hook: Attachment "HwFX_<name>" under `part` at model position `pos` (see EventDogs.StartFX).
function Rig:Hook(part: BasePart, name: string, kind: string, pos: Vector3, color: Color3, color2: Color3?, rate: number?, light: number?)
	local a = Instance.new("Attachment")
	a.Name = "HwFX_" .. name
	a.CFrame = part.CFrame:ToObjectSpace(CF(pos))
	a:SetAttribute("HwFX", kind)
	a:SetAttribute("HwFXColor", color)
	a:SetAttribute("HwFXColor2", color2 or color)
	a:SetAttribute("HwFXRate", rate or 6)
	a:SetAttribute("HwFXLight", light or 0)
	a:SetAttribute("SelfManagedFX", true)
	a.Parent = part
	self.Hooks += 1
	return a
end

---------------------------------------------------------------------------------------------------------------------
-- Clip maths (pure; runs in Lune and in Roblox)
---------------------------------------------------------------------------------------------------------------------
local TAU = 2 * PI
local function sinU(u: number, k: number, ph: number?): number
	return math.sin(TAU * (k * u + (ph or 0)))
end
local function cosU(u: number, k: number, ph: number?): number
	return math.cos(TAU * (k * u + (ph or 0)))
end
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
-- 0 outside [a, b], a smooth hump inside (peak 1 at the middle)
local function bump(t: number, a: number, b: number): number
	if t <= a or t >= b then
		return 0
	end
	local s = math.sin(PI * (t - a) / (b - a))
	return s * s
end
-- 0 before a, eases to 1 at b
local function rise(t: number, a: number, b: number): number
	return smooth((t - a) / math.max(1e-6, b - a))
end
-- 0 outside [a, d], 1 on [b, c], smooth ramps between (a plateau)
local function hold(t: number, a: number, b: number, c: number, d: number): number
	return rise(t, a, b) * (1 - rise(t, c, d))
end
-- a deterministic flicker in 0..1 (summed sines; k = speed; an integer k keeps a loop seamless)
local function flick(x: number, k: number, ph: number?): number
	local p = ph or 0
	return 0.5 + 0.25 * math.sin(TAU * (k * x + p)) + 0.15 * math.sin(TAU * ((2 * k + 1) * x + p * 1.7)) + 0.1 * math.sin(TAU * ((4 * k + 3) * x + p * 0.6))
end
E.Math = { sinU = sinU, cosU = cosU, smooth = smooth, bump = bump, rise = rise, hold = hold, flick = flick }

-- q = qx * qy * qz (CFrame.Angles(rx, ry, rz) order)
local function quat(rx: number, ry: number, rz: number): (number, number, number, number)
	local cx, sx = math.cos(rx / 2), math.sin(rx / 2)
	local cy, sy = math.cos(ry / 2), math.sin(ry / 2)
	local cz, sz = math.cos(rz / 2), math.sin(rz / 2)
	return sx * cy * cz + cx * sy * sz, cx * sy * cz - sx * cy * sz, cx * cy * sz + sx * sy * cz, cx * cy * cz - sx * sy * sz
end
E.Quat = quat

---------------------------------------------------------------------------------------------------------------------
-- Generic dog motion (every bone is optional; dog specs add their own extras)
---------------------------------------------------------------------------------------------------------------------
local CLIPS = {
	Idle = { 3.2, true },
	Walk = { 0.8, true },
	DigStart = { 0.5 },
	DigLoop = { 1.0, true },
	DigEnd = { 0.5 },
	DigFind = { 1.6 },
	Happy = { 1.8 },
	Sniff = { 2.4 },
	Run = { 0.5, true },
	Sleep = { 4.0, true },
	RareFind = { 2.6 },
	Signature = { 3.0 },
}
function E.IsLooped(clip: string): boolean
	local c = CLIPS[clip]
	return c ~= nil and c[2] == true
end

-- the tail chain (Tail > Tail2 > TailTip): a wave that travels to the tip
local function tail(add, pitch: number, amp: number, x: number, k: number, lag: number?)
	lag = lag or 0.09
	add("Tail", 0, 0, 0, pitch, amp * math.sin(TAU * k * x), 0)
	add("Tail2", 0, 0, 0, pitch * 0.3, amp * 0.8 * math.sin(TAU * (k * x - lag)), 0)
	add("TailTip", 0, 0, 0, pitch * 0.2, amp * 0.7 * math.sin(TAU * (k * x - 2 * lag)), 0)
end

-- m = motion parameters of a spec (all optional): Breath, Wag, Stride, Scoop, Hop, Look, Spin, IdleK, ScoopK
local function idlePose(m, u0, add)
	local u = (u0 * (m.IdleK or 1)) % 1
	add("Body", 0, (m.Breath or 0.05) * sinU(u, 1), 0, 0.015 * sinU(u, 1, 0.25), 0, 0.01 * sinU(u, 1, 0.5))
	add("Neck", 0, 0, 0, 0.03 * sinU(u, 1, 0.1), 0.05 * sinU(u, 1, 0.3), 0)
	add("Head", 0, 0, 0, 0.05 * sinU(u, 2, 0.2), (m.Look or 0.2) * sinU(u, 1), 0.05 * sinU(u, 1, 0.6))
	add("Jaw", 0, 0, 0, -(0.05 + 0.04 * sinU(u, 4)), 0, 0)
	local twitch = bump(u, 0.55, 0.63)
	local twitch2 = bump(u, 0.15, 0.23)
	add("Ear_L", 0, 0, 0, 0.05 * sinU(u, 1), 0, -0.3 * twitch)
	add("Ear_R", 0, 0, 0, 0.05 * sinU(u, 1, 0.5), 0, 0.3 * twitch2)
	tail(add, 0.12 + 0.04 * sinU(u, 2), m.Wag or 0.35, u, 4)
end

local LEGS = {
	{ "Leg_FL", "Paw_FL", 0 },
	{ "Leg_BR", "Paw_BR", 0 },
	{ "Leg_FR", "Paw_FR", 0.5 },
	{ "Leg_BL", "Paw_BL", 0.5 },
}
local function walkPose(m, u, add)
	local a = m.Stride or 0.45
	for _, leg in ipairs(LEGS) do
		add(leg[1], 0, 0, 0, a * sinU(u, 1, leg[3]), 0, 0)
		add(leg[2], 0, 0, 0, 0.35 * math.max(0, sinU(u, 1, leg[3] + 0.25)), 0, 0)
	end
	add("Body", 0, 0.07 * sinU(u, 2, 0.25), 0, 0.02 * sinU(u, 2), 0.03 * sinU(u, 1), 0.03 * sinU(u, 1, 0.25))
	add("Neck", 0, 0, 0, 0.04 * sinU(u, 2, 0.1), 0, 0)
	add("Head", 0, 0, 0, 0.05 * sinU(u, 2, 0.3), 0.04 * sinU(u, 1), 0)
	tail(add, 0.15, 0.3, u, 2)
	add("Ear_L", 0, 0, 0, 0.08 * sinU(u, 2, 0.2), 0, 0)
	add("Ear_R", 0, 0, 0, 0.08 * sinU(u, 2, 0.2), 0, 0)
	add("Jaw", 0, 0, 0, -0.08, 0, 0)
end

-- gallop: the front pair and the hind pair each move nearly together, the back flexes
local function runPose(m, u, add)
	local a = (m.Stride or 0.45) * 1.6
	add("Leg_FL", 0, 0, 0, a * sinU(u, 1, 0), 0, 0)
	add("Leg_FR", 0, 0, 0, a * sinU(u, 1, 0.08), 0, 0)
	add("Leg_BL", 0, 0, 0, a * sinU(u, 1, 0.5), 0, 0)
	add("Leg_BR", 0, 0, 0, a * sinU(u, 1, 0.58), 0, 0)
	for _, p in ipairs({ { "Paw_FL", 0 }, { "Paw_FR", 0.08 }, { "Paw_BL", 0.5 }, { "Paw_BR", 0.58 } }) do
		add(p[1], 0, 0, 0, 0.55 * math.max(0, sinU(u, 1, p[2] + 0.25)), 0, 0)
	end
	add("Body", 0, 0.16 + 0.12 * sinU(u, 1, 0.3), -0.05, 0.09 * sinU(u, 1, 0.05), 0, 0)
	add("Neck", 0, 0, 0, -0.06 * sinU(u, 1, 0.1), 0, 0)
	add("Head", 0, 0, 0, -0.06 * sinU(u, 1, 0.15) - 0.05, 0, 0)
	add("Jaw", 0, 0, 0, -0.22, 0, 0)
	add("Ear_L", 0, 0, 0, 0.35, 0, -0.1)
	add("Ear_R", 0, 0, 0, 0.35, 0, 0.1)
	tail(add, -0.15, 0.18, u, 2)
end

local function digPose(m, u, add)
	local s = m.Scoop or 0.75
	local k = m.ScoopK or 1
	add("Body", 0, -0.12, 0, -0.06 + 0.02 * sinU(u, 2 * k), 0, 0.02 * sinU(u, k))
	add("Neck", 0, 0, 0, -0.16, 0, 0)
	add("Head", 0, 0, 0, -0.28 + 0.06 * sinU(u, 2 * k), 0.06 * sinU(u, k), 0)
	add("Jaw", 0, 0, 0, -0.06, 0, 0)
	add("Leg_FL", 0, 0, 0, 0.25 + s * sinU(u, k), 0, 0)
	add("Leg_FR", 0, 0, 0, 0.25 + s * sinU(u, k, 0.5), 0, 0)
	add("Paw_FL", 0, 0, 0, -0.35 * sinU(u, k, 0.2), 0, 0)
	add("Paw_FR", 0, 0, 0, -0.35 * sinU(u, k, 0.7), 0, 0)
	add("Leg_BL", 0, 0, 0, 0.06 + 0.05 * sinU(u, 2 * k), 0, 0)
	add("Leg_BR", 0, 0, 0, 0.06 + 0.05 * sinU(u, 2 * k, 0.5), 0, 0)
	tail(add, 0.35, 0.45, u, 3 * k)
	add("Ear_L", 0, 0, 0, 0.25, 0, 0)
	add("Ear_R", 0, 0, 0, 0.25, 0, 0)
end

-- nose to the ground: quick sniffs left and right, tail up
local function sniffPose(m, t, d, add)
	local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
	local sn = down * (0.5 + 0.5 * math.sin(TAU * 7 * t))
	add("Body", 0, -0.06 * down, 0, -0.07 * down, 0, 0)
	add("Neck", 0, 0, 0, -0.3 * down, 0.12 * math.sin(TAU * 0.8 * t) * down, 0)
	add("Head", 0, -0.02 * sn, 0, -0.22 * down + 0.05 * sn, 0.18 * math.sin(TAU * 0.6 * t) * down, 0)
	add("Jaw", 0, 0, 0, -0.04 * sn, 0, 0)
	add("Leg_FL", 0, 0, 0, 0.12 * down, 0, 0)
	add("Leg_FR", 0, 0, 0, 0.12 * down, 0, 0)
	add("Ear_L", 0, 0, 0, 0.3 * down, 0, 0)
	add("Ear_R", 0, 0, 0, 0.3 * down, 0, 0)
	tail(add, 0.35 * down, 0.25 * down, t / d, 6)
end

-- curled up asleep: legs folded, chin down, slow breaths, tail wrapped round
local function sleepPose(m, u, add)
	local hip = m.HipY or 1.4
	local drop = math.max(0, hip - 0.42)
	local br = sinU(u, 1)
	add("Body", 0, -drop + 0.04 * br, 0, 0.02 * br, 0, 0)
	add("Leg_FL", 0, 0, 0, 1.45, 0, -0.12)
	add("Leg_FR", 0, 0, 0, 1.45, 0, 0.12)
	add("Paw_FL", 0, 0, 0, -0.25, 0, 0)
	add("Paw_FR", 0, 0, 0, -0.25, 0, 0)
	add("Leg_BL", 0, 0, 0, 1.5, 0, -0.35)
	add("Leg_BR", 0, 0, 0, 1.5, 0, 0.35)
	add("Neck", 0, 0, 0, -0.28 + 0.02 * br, 0.12, 0)
	add("Head", 0, 0, 0, -0.22, 0.2, 0.12)
	add("Jaw", 0, 0, 0, 0, 0, 0)
	add("Ear_L", 0, 0, 0, -0.15, 0, -0.25)
	add("Ear_R", 0, 0, 0, -0.15, 0, 0.25)
	add("Tail", 0, 0, 0, -0.35, 0.9, 0)
	add("Tail2", 0, 0, 0, -0.1, 0.5 + 0.04 * br, 0)
	add("TailTip", 0, 0, 0, 0, 0.4, 0)
end

local function digStillPose(m, add)
	digPose(m, 0, add)
end

local function findPose(m, t, d, add)
	local hop = bump(t, 0.12, 0.62)
	local joy = bump(t, 0.05, d - 0.05)
	add("Body", 0, (m.Hop or 0.55) * hop, 0, 0.12 * hop, 0, 0)
	add("Leg_FL", 0, 0, 0, 0.55 * hop, 0, 0)
	add("Leg_FR", 0, 0, 0, 0.55 * hop, 0, 0)
	add("Leg_BL", 0, 0, 0, -0.45 * hop, 0, 0)
	add("Leg_BR", 0, 0, 0, -0.45 * hop, 0, 0)
	add("Neck", 0, 0, 0, 0.12 * joy, 0, 0)
	add("Head", 0, 0, 0, 0.3 * joy, 0, 0.12 * math.sin(TAU * 2 * t / d) * joy)
	add("Jaw", 0, 0, 0, -0.3 * joy, 0, 0)
	add("Ear_L", 0, 0, 0, 0, 0, -0.3 * joy)
	add("Ear_R", 0, 0, 0, 0, 0, 0.3 * joy)
	tail(add, 0.4 * joy, 0.6 * joy, t / d, 5)
end

local function happyPose(m, t, d, add)
	local hop1 = bump(t, 0.08, 0.5)
	local hop2 = bump(t, 0.62, 1.08)
	local joy = bump(t, 0.02, d - 0.02)
	local hop = math.max(hop1, hop2)
	add("Body", 0, (m.Hop or 0.55) * 0.8 * hop, 0, 0.1 * hop, 0, 0)
	if m.Spin ~= false then
		add("Root", 0, 0, 0, 0, TAU * rise(t, 0.55, 1.25), 0)
	end
	add("Leg_FL", 0, 0, 0, 0.5 * hop, 0, 0)
	add("Leg_FR", 0, 0, 0, 0.5 * hop, 0, 0)
	add("Leg_BL", 0, 0, 0, -0.4 * hop, 0, 0)
	add("Leg_BR", 0, 0, 0, -0.4 * hop, 0, 0)
	add("Head", 0, 0, 0, 0.25 * joy, 0, 0.18 * math.sin(TAU * 3 * t / d) * joy)
	add("Jaw", 0, 0, 0, -0.32 * joy, 0, 0)
	add("Ear_L", 0, 0, 0, 0, 0, -0.35 * joy)
	add("Ear_R", 0, 0, 0, 0, 0, 0.35 * joy)
	tail(add, 0.45 * joy, 0.7 * joy, t / d, 6)
end

-- crouch, a big leap with a full turn, a proud landing
local function rareFindPose(m, t, d, add)
	local crouch = bump(t, 0.0, 0.5) * (1 - rise(t, 0.3, 0.42))
	local air = bump(t, 0.38, 1.25)
	local land = bump(t, 1.2, 1.6)
	local joy = bump(t, 0.3, d - 0.05)
	add("Body", 0, -0.25 * crouch + (m.Hop or 0.55) * 1.6 * air - 0.12 * land, 0, -0.1 * crouch + 0.15 * air, 0, 0)
	if m.Spin ~= false then
		add("Root", 0, 0, 0, 0, TAU * rise(t, 0.42, 1.2), 0)
	end
	local tuck = air
	add("Leg_FL", 0, 0, 0, 0.3 * crouch + 0.8 * tuck, 0, 0)
	add("Leg_FR", 0, 0, 0, 0.3 * crouch + 0.8 * tuck, 0, 0)
	add("Leg_BL", 0, 0, 0, 0.2 * crouch - 0.7 * tuck, 0, 0)
	add("Leg_BR", 0, 0, 0, 0.2 * crouch - 0.7 * tuck, 0, 0)
	add("Neck", 0, 0, 0, 0.18 * joy, 0, 0)
	add("Head", 0, 0, 0, 0.3 * joy - 0.15 * crouch, 0, 0.12 * math.sin(TAU * 3 * t / d) * land)
	add("Jaw", 0, 0, 0, -0.35 * joy, 0, 0)
	add("Ear_L", 0, 0, 0, 0.3 * air, 0, -0.4 * joy)
	add("Ear_R", 0, 0, 0, 0.3 * air, 0, 0.4 * joy)
	tail(add, 0.5 * joy, 0.7 * joy, t / d, 7)
end

---------------------------------------------------------------------------------------------------------------------
-- Dog specs
---------------------------------------------------------------------------------------------------------------------
local SPECS = {}
E.Specs = SPECS

-- shared: a standard quadruped skeleton (+ extras), legs at x = ±lx, front z = fz, hind z = hz, hips at hipY, paws at pawY
local function legBones(list, lx: number, fz: number, hz: number, hipY: number, pawY: number, dz: number?)
	for _, l in ipairs({ { "FL", 1, fz }, { "FR", -1, fz }, { "BL", 1, hz }, { "BR", -1, hz } }) do
		table.insert(list, { "Leg_" .. l[1], "Body", V3(l[2] * lx, hipY, l[3]) })
		table.insert(list, { "Paw_" .. l[1], "Leg_" .. l[1], V3(l[2] * lx, pawY, l[3] + (dz or 0)) })
	end
	return list
end
local LEG_TAGS = { { "FL", 1, true }, { "FR", -1, true }, { "BL", 1, false }, { "BR", -1, false } }

---------------------------------------------------------------- H01 PUMPKIN PUP (Rare)
do
	local ORANGE, ORANGE_HI, ORANGE_LO = C(240, 120, 24), C(252, 150, 48), C(196, 84, 14)
	local FUR, FUR_HI, FUR_LO, CREAM, CREAM_LO = C(226, 170, 102), C(240, 196, 132), C(150, 92, 52), C(255, 238, 206), C(238, 210, 168)
	local RIM, FLESH, GLOW, GLOW_HOT = C(96, 32, 6), C(255, 210, 120), C(255, 190, 56), C(255, 240, 170)
	local LEAF, LEAF_LO, VINE, STEM = C(118, 176, 62), C(66, 116, 38), C(78, 128, 44), C(110, 100, 52)
	local NOSE, PINK = C(64, 30, 14), C(240, 108, 112)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 1.88, 0.3) },
		{ "Neck", "Body", V3(0, 2.45, -0.95) },
		{ "Charm", "Neck", V3(0, 2.22, -1.42) },
		{ "Head", "Neck", V3(0, 2.95, -1.4) },
		{ "Flame", "Head", V3(0, 4.0, -2.2) },
		{ "Jaw", "Head", V3(0, 3.02, -2.85) },
		{ "Lid", "Head", V3(0, 4.95, -1.7) },
		{ "Ear_L", "Head", V3(1.28, 4.28, -1.55) },
		{ "Ear_R", "Head", V3(-1.28, 4.28, -1.55) },
		{ "Tail", "Body", V3(0, 2.3, 1.5) },
		{ "Tail2", "Tail", V3(0, 2.72, 1.84) },
		{ "TailTip", "Tail2", V3(0, 3.12, 1.96) },
	}
	legBones(bones, 0.56, -0.42, 1.12, 1.3, 0.36, -0.04)
	SPECS.HW_PumpkinPup = {
		Code = "H01",
		SignatureName = "PumpkinBounce",
		Bones = bones,
		Durations = { Idle = 4.0 },
		Motion = { Breath = 0.04, Wag = 0.3, Hop = 0.6, Look = 0.22 },
		Extra = function(clip, t, d, u, add)
			-- the candle inside flickers (the hot cores of the carved eyes dance), the lid hops, the charm swings
			local x = E.IsLooped(clip) and u or t / d
			add("Flame", 0.012 * sinU(x, 13), 0.035 * (flick(x, 9) - 0.5), 0, 0, 0, 0)
			if clip == "Idle" then
				local hopL = bump(u, 0.42, 0.5) + bump(u, 0.52, 0.58) * 0.6
				add("Lid", 0, 0.12 * hopL, 0, 0, 0.12 * sinU(u, 1), 0.08 * hopL)
				add("Charm", 0, 0, 0, 0.12 * sinU(u, 2), 0, 0.08 * sinU(u, 1))
				add("Ear_L", 0, 0, 0, 0, 0, 0.05 * sinU(u, 2))
				add("Ear_R", 0, 0, 0, 0, 0, -0.05 * sinU(u, 2, 0.2))
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				add("Charm", 0, 0, 0, 0.3 * sinU(u, k, 0.3), 0, 0)
				add("Lid", 0, 0.04 * math.max(0, sinU(u, k)), 0, 0, 0, 0)
				add("Ear_L", 0, 0, 0, 0, 0, 0.15 * sinU(u, k, 0.2))
				add("Ear_R", 0, 0, 0, 0, 0, -0.15 * sinU(u, k, 0.2))
			elseif clip == "DigLoop" then
				add("Charm", 0, 0, 0, 0.3 * sinU(u, 2), 0, 0.15 * sinU(u, 1))
				add("Lid", 0, 0.03 * math.max(0, sinU(u, 2)), 0, 0, 0, 0.04 * sinU(u, 1))
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local a, b = 0.2, 0.95
				if clip == "RareFind" then
					a, b = 0.45, 1.5
				end
				local pop = bump(t, a, b)
				add("Lid", 0, 0.8 * pop, 0, 0, TAU * rise(t, a + 0.05, b - 0.05), 0.25 * pop)
				add("Charm", 0, 0, 0, 0.5 * math.sin(TAU * 4 * t / d) * bump(t, 0, d), 0, 0)
				add("Flame", 0, 0.05 * pop, 0, 0, 0, 0)
			elseif clip == "Signature" then
				-- PUMPKIN BOUNCE: three bounces (squash on every landing), the lid rockets off on the last one
				local hops = { { 0.15, 0.7, 0.45 }, { 0.85, 1.4, 0.6 }, { 1.55, 2.35, 1.1 } }
				for i, h in ipairs(hops) do
					local air = bump(t, h[1], h[2])
					local squash = bump(t, h[2] - 0.05, h[2] + 0.2)
					add("Body", 0, h[3] * air - 0.12 * squash, 0, 0.08 * air, 0, 0)
					add("Leg_FL", 0, 0, 0, 0.5 * air, 0, 0)
					add("Leg_FR", 0, 0, 0, 0.5 * air, 0, 0)
					add("Leg_BL", 0, 0, 0, -0.45 * air, 0, 0)
					add("Leg_BR", 0, 0, 0, -0.45 * air, 0, 0)
					add("Ear_L", 0, 0, 0, 0, 0, -0.5 * air + 0.2 * squash)
					add("Ear_R", 0, 0, 0, 0, 0, 0.5 * air - 0.2 * squash)
					if i == 3 then
						add("Root", 0, 0, 0, 0, TAU * rise(t, h[1] + 0.05, h[2] - 0.05), 0)
					end
				end
				local fly = bump(t, 1.6, 2.85)
				add("Lid", 0, 1.6 * fly, 0, 0.3 * fly, 2 * TAU * rise(t, 1.6, 2.8), 0)
				add("Charm", 0, 0, 0, 0.6 * math.sin(TAU * 5 * t / d) * bump(t, 0.1, d - 0.1), 0, 0)
				add("Head", 0, 0, 0, 0.15 * bump(t, 0.1, d - 0.1), 0, 0.15 * math.sin(TAU * 2 * t / d) * bump(t, 0.1, d - 0.1))
				add("Jaw", 0, 0, 0, -0.25 * bump(t, 0.1, d - 0.1), 0, 0)
				tail(add, 0.4, 0.6 * bump(t, 0.05, d - 0.05), t / d, 7)
			end
		end,
		Build = function(r)
			-------- body: a ginger pup with pumpkin-ribbed fur, cream chest ruff, a leafy vine harness
			r:Round("Body", "Torso", V3(1.72, 1.46, 2.56), V3(0, 1.88, 0.3), FUR, nil, 0.24, FUR_HI)
			r:Round("Body", "Haunch", V3(1.62, 1.2, 0.8), V3(0, 1.98, 1.25), FUR, nil, 0.22, FUR_HI)
			r:Box("Body", "Belly", V3(1.2, 0.08, 1.9), V3(0, 1.15, 0.25), CREAM)
			-- a brown beagle saddle over the back, stepped down the flanks
			r:Round("Body", "Saddle", V3(1.52, 0.12, 1.7), V3(0, 2.62, 0.55), FUR_LO, nil, 0.04)
			r:Pair(function(s, side)
				r:Box("Body", "SaddleSide_" .. side, V3(0.06, 0.46, 1.5), V3(s * 0.875, 2.35, 0.55), FUR_LO)
				r:Box("Body", "SaddleStep_" .. side, V3(0.06, 0.2, 0.9), V3(s * 0.875, 2.05, 0.6), FUR_LO)
				r:Box("Body", "FlankFluff_" .. side, V3(0.08, 0.36, 0.5), V3(s * 0.885, 1.5, -0.1), FUR_HI)
			end)
			-- cream ruff cascading down the chest
			r:Tuft("Body", "Ruff", CF(0, 2.48, -1.0), 1.0, 1.0, 3, CREAM, CREAM_LO)
			r:Tuft("Body", "RuffL", CF(0.38, 2.2, -0.96) * ANG(0, 0, 0.3), 0.55, 0.42, 2, CREAM_LO, CREAM)
			r:Tuft("Body", "RuffR", CF(-0.38, 2.2, -0.96) * ANG(0, 0, -0.3), 0.55, 0.42, 2, CREAM_LO, CREAM)
			-- vine harness with leaves
			r:Box("Body", "VineTop", V3(1.5, 0.12, 0.22), V3(0, 2.64, -0.42), VINE)
			r:Box("Body", "VineBelly", V3(1.3, 0.12, 0.22), V3(0, 1.14, -0.42), VINE)
			r:Pair(function(s, side)
				r:Box("Body", "VineSide_" .. side, V3(0.12, 1.26, 0.22), V3(s * 0.88, 1.9, -0.42), VINE)
				r:Box("Body", "VineCurl_" .. side, V3(0.1, 0.28, 0.1), V3(s * 0.92, 2.4, -0.18), VINE)
				r:Box("Body", "VineLeaf_" .. side, V3(0.06, 0.34, 0.4), CF(s * 0.94, 1.62, -0.2) * ANG(0.4, 0, -s * 0.25), LEAF)
				r:Box("Body", "VineLeafVein_" .. side, V3(0.07, 0.3, 0.05), CF(s * 0.945, 1.62, -0.2) * ANG(0.4, 0, -s * 0.25), LEAF_LO)
				r:Box("Body", "BackLeaf_" .. side, V3(0.52, 0.07, 0.36), CF(s * 0.34, 2.71, -0.2) * ANG(0, s * 0.5, 0), LEAF)
				r:Box("Body", "BackLeafVein_" .. side, V3(0.04, 0.08, 0.32), CF(s * 0.34, 2.72, -0.2) * ANG(0, s * 0.5 + PI / 2, 0), LEAF_LO)
			end)
			r:Box("Body", "VineKnot", V3(0.26, 0.2, 0.26), V3(0, 2.7, -0.42), STEM)
			-------- legs: fluffy pup legs, leafy cuffs, cream paws with toes
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.56, front and -0.42 or 1.12
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.54, 0.98, 0.56), V3(x, 0.86, z), FUR, nil, 0.1)
				if front then
					r:Round(leg, "Shoulder_" .. tag, V3(0.62, 0.6, 0.68), V3(x, 1.4, z), FUR, nil, 0.14, FUR_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.68, 0.82, 0.86), V3(x + s * 0.02, 1.4, z + 0.04), FUR, nil, 0.18, FUR_HI)
				end
				r:Box(leg, "Cuff_" .. tag, V3(0.62, 0.13, 0.62), V3(x, 0.5, z), LEAF)
				r:Box(leg, "CuffLeaf_" .. tag, V3(0.05, 0.3, 0.26), CF(x + s * 0.33, 0.58, z - 0.1) * ANG(0, 0, -s * 0.35), LEAF)
				r:Paw(paw, tag, x, z - 0.06, 0.64, 0.66, 0.36, CREAM, { Toe = CREAM, Bean = C(150, 80, 50) })
			end
			-------- neck, leafy collar and the little pumpkin charm
			r:Round("Neck", "Neck", V3(1.08, 0.82, 0.92), V3(0, 2.52, -0.95), FUR, nil, 0.16)
			r:Box("Neck", "Collar", V3(1.16, 0.16, 0.96), V3(0, 2.24, -0.96), VINE)
			r:Pair(function(s, side)
				r:Box("Neck", "CollarLeaf_" .. side, V3(0.06, 0.34, 0.3), CF(s * 0.6, 2.2, -1.3) * ANG(0, 0, -s * 0.4), LEAF)
				r:Box("Neck", "CollarLeafB_" .. side, V3(0.3, 0.06, 0.34), CF(s * 0.42, 2.3, -0.5) * ANG(0, s * 0.4, 0.3 * s), LEAF_LO)
			end)
			r:Box("Charm", "CharmString", V3(0.05, 0.2, 0.05), V3(0, 2.07, -1.44), VINE)
			local charm = r:Round("Charm", "Charm", V3(0.42, 0.34, 0.4), V3(0, 1.86, -1.45), ORANGE, nil, 0.08, ORANGE_HI)
			r:Box("Charm", "CharmRib", V3(0.07, 0.35, 0.41), V3(0, 1.86, -1.45), ORANGE_LO)
			r:Box("Charm", "CharmStem", V3(0.08, 0.12, 0.08), V3(0, 2.07, -1.45), STEM)
			r:Neon("Charm", "CharmFace", V3(0.22, 0.06, 0.02), V3(0, 1.82, -1.66), GLOW)
			r:Neon("Charm", "CharmEyes", V3(0.2, 0.05, 0.02), V3(0, 1.92, -1.66), GLOW)
			-------- the carved pumpkin helmet (two crossed bevelled blocks = an octagonal pumpkin, grooved)
			local helmet = r:Round("Head", "Pumpkin", V3(2.0, 1.98, 2.1), V3(0, 3.9, -1.7), ORANGE, nil, 0.26, ORANGE_HI)
			r:Light(helmet, C(255, 150, 40), 8, 1.4)
			r:Round("Head", "PumpkinWide", V3(2.42, 1.7, 1.66), V3(0, 3.88, -1.7), ORANGE, nil, 0.24)
			r:Box("Head", "Underside", V3(1.8, 0.08, 1.9), V3(0, 2.89, -1.7), ORANGE_LO)
			r:Pair(function(s, side)
				for i, z in ipairs({ -2.12, -1.28 }) do
					r:Box("Head", "Groove" .. i .. "_" .. side, V3(0.06, 1.3, 0.1), V3(s * 1.225, 3.88, z), ORANGE_LO)
				end
				r:Box("Head", "GrooveBack_" .. side, V3(0.1, 1.5, 0.06), V3(s * 0.42, 3.9, -0.635), ORANGE_LO)
				r:Box("Head", "GrooveTop_" .. side, V3(0.08, 0.04, 1.2), V3(s * 0.55, 4.905, -1.7), ORANGE_LO)
				r:Box("Head", "Shine_" .. side, V3(0.05, 0.36, 0.2), V3(s * 1.228, 4.36, -1.7), ORANGE_HI)
			end)
			r:Box("Head", "GrooveTopFront", V3(0.6, 0.04, 0.08), V3(0, 4.905, -2.32), ORANGE_LO)
			r:Box("Head", "GrooveTopBack", V3(0.6, 0.04, 0.08), V3(0, 4.905, -1.08), ORANGE_LO)
			-- carved eyes: dark rim, fresh yellow flesh, glowing core and a dancing candle hot-spot (Flame bone)
			r:Pair(function(s, side)
				local turn = ANG(0, 0, -s * 0.14)
				r:Tri("Head", "EyeRim_" .. side, V3(s * 0.5, 4.22, -2.77), 0.86, 0.74, 0.04, RIM, MAT.SmoothPlastic, false, turn)
				r:Tri("Head", "EyeCut_" .. side, V3(s * 0.5, 4.2, -2.8), 0.72, 0.62, 0.04, FLESH, MAT.SmoothPlastic, false, turn)
				r:Tri("Head", "Eye_" .. side, V3(s * 0.5, 4.18, -2.835), 0.56, 0.47, 0.04, GLOW, MAT.Neon, false, turn)
				r:Neon("Flame", "EyeHot_" .. side, V3(0.14, 0.14, 0.03), V3(s * 0.5, 4.08, -2.865), GLOW_HOT)
				-- angry brow notch carved above each eye
				r:Box("Head", "Brow_" .. side, V3(0.5, 0.08, 0.04), CF(s * 0.52, 4.68, -2.77) * ANG(0, 0, s * 0.3), RIM)
			end)
			-------- pumpkin muzzle (pup snout shape) with the carved grin, a dog nose and a tongue
			r:Round("Head", "Muzzle", V3(1.3, 0.78, 0.8), V3(0, 3.3, -3.05), ORANGE, nil, 0.16, ORANGE_HI)
			r:Box("Head", "MuzzleRib", V3(0.06, 0.62, 0.82), V3(0, 3.3, -3.06), ORANGE_LO)
			r:Pair(function(s, side)
				r:Box("Head", "MuzzleGroove_" .. side, V3(0.06, 0.6, 0.12), V3(s * 0.655, 3.3, -3.15), ORANGE_LO)
				r:Box("Head", "Whisker_" .. side, V3(0.05, 0.05, 0.04), V3(s * 0.34, 3.5, -3.47), RIM)
				r:Box("Head", "WhiskerB_" .. side, V3(0.05, 0.05, 0.04), V3(s * 0.46, 3.44, -3.47), RIM)
			end)
			r:Box("Head", "GrinRim", V3(1.02, 0.38, 0.03), V3(0, 3.13, -3.465), RIM)
			r:Box("Head", "GrinCut", V3(0.94, 0.3, 0.03), V3(0, 3.13, -3.49), FLESH)
			r:Neon("Head", "Grin", V3(0.84, 0.21, 0.03), V3(0, 3.13, -3.515), GLOW)
			r:Pair(function(s, side)
				r:Box("Head", "GrinEndRim_" .. side, V3(0.22, 0.24, 0.03), V3(s * 0.5, 3.29, -3.465), RIM)
				r:Neon("Head", "GrinEnd_" .. side, V3(0.12, 0.13, 0.03), V3(s * 0.5, 3.29, -3.515), GLOW)
				r:Box("Head", "Tooth_" .. side, V3(0.15, 0.11, 0.04), V3(s * 0.2, 3.195, -3.53), ORANGE)
			end)
			r:Box("Head", "ToothLow", V3(0.16, 0.1, 0.04), V3(0, 3.07, -3.53), ORANGE)
			r:Round("Head", "Nose", V3(0.48, 0.28, 0.3), V3(0, 3.62, -3.36), NOSE, nil, 0.06)
			r:Box("Head", "NostrilL", V3(0.08, 0.06, 0.03), V3(0.1, 3.6, -3.52), C(30, 12, 4))
			r:Box("Head", "NostrilR", V3(0.08, 0.06, 0.03), V3(-0.1, 3.6, -3.52), C(30, 12, 4))
			r:Box("Head", "NoseShine", V3(0.12, 0.05, 0.03), V3(0.08, 3.71, -3.5), C(255, 214, 170))
			-- chin + tongue (Jaw)
			r:Round("Jaw", "Chin", V3(1.0, 0.24, 0.62), V3(0, 2.86, -3.0), ORANGE_LO, nil, 0.06)
			r:Box("Jaw", "Tongue", V3(0.26, 0.06, 0.3), CF(0.14, 2.98, -3.36) * ANG(-0.25, 0, 0), PINK)
			r:Box("Jaw", "TongueTip", V3(0.22, 0.05, 0.12), CF(0.14, 2.92, -3.52) * ANG(-0.6, 0, 0), C(226, 90, 98))
			-- ginger cheek fluff poking out under the helmet
			r:Pair(function(s, side)
				r:Tuft("Head", "Cheek_" .. side, CF(s * 0.86, 3.0, -2.5) * ANG(0, 0, s * 0.55), 0.48, 0.34, 3, CREAM, CREAM_LO)
				r:Tuft("Head", "CheekB_" .. side, CF(s * 0.98, 2.98, -1.95) * ANG(0, 0, s * 0.45), 0.4, 0.3, 2, CREAM_LO, CREAM)
			end)
			-------- floppy pup ears poking out of holes cut in the helmet sides
			r:Pair(function(s, side)
				local ear = "Ear_" .. side
				local tilt = CF(s * 1.37, 3.78, -1.55) * ANG(0, 0, s * 0.12)
				r:Box("Head", "EarHole_" .. side, V3(0.05, 0.34, 0.74), V3(s * 1.235, 4.28, -1.55), RIM)
				r:Round(ear, "EarBase_" .. side, V3(0.26, 0.3, 0.62), V3(s * 1.3, 4.26, -1.55), FUR_HI, nil, 0.06)
				r:Round(ear, "Ear_" .. side, V3(0.2, 1.02, 0.66), tilt, FUR, nil, 0.06)
				r:Box(ear, "EarTip_" .. side, V3(0.22, 0.26, 0.6), tilt * CF(0, -0.42, 0), FUR_LO)
				r:Box(ear, "EarFold_" .. side, V3(0.04, 0.6, 0.08), tilt * CF(s * 0.1, 0.05, -0.18), FUR_LO)
			end)
			-------- the lid: cut line, lid, curly stem, vine and two leaves
			r:Box("Head", "LidCut", V3(1.24, 0.04, 1.14), V3(0, 4.905, -1.7), RIM)
			r:Round("Lid", "Lid", V3(1.12, 0.2, 1.02), V3(0, 5.0, -1.7), ORANGE_HI, nil, 0.06)
			r:Round("Lid", "Stem", V3(0.32, 0.56, 0.32), CF(0, 5.36, -1.7) * ANG(0, 0, 0.14), STEM, nil, 0.06)
			r:Box("Lid", "StemTop", V3(0.38, 0.1, 0.38), CF(-0.04, 5.66, -1.7) * ANG(0, 0, 0.14), C(132, 122, 64))
			r:Box("Lid", "StemVine", V3(0.12, 0.12, 0.52), V3(0.16, 5.46, -1.36), VINE)
			r:Box("Lid", "StemCurl", V3(0.12, 0.34, 0.12), V3(0.16, 5.62, -1.14), VINE)
			r:Box("Lid", "StemCurlB", V3(0.12, 0.12, 0.26), V3(0.16, 5.78, -1.26), VINE)
			for i, lf in ipairs({ { V3(-0.42, 5.12, -1.5), 0.5, -0.3 }, { V3(0.36, 5.12, -2.05), -0.8, 0.25 } }) do
				local cf = CF(lf[1]) * ANG(0, lf[2], lf[3])
				r:Box("Lid", "Leaf" .. i, V3(0.62, 0.06, 0.42), cf, LEAF)
				r:Wedge("Lid", "LeafTip" .. i, V3(0.06, 0.2, 0.42), cf * CF(0.41, 0, 0) * ANG(0, 0, -PI / 2), LEAF)
				r:Box("Lid", "LeafVein" .. i, V3(0.66, 0.07, 0.05), cf, LEAF_LO)
			end
			-------- vine tail: curling vine (3 bones) with a leaf and a pumpkin bud
			r:Box("Tail", "TailBase", V3(0.3, 0.3, 0.3), V3(0, 2.32, 1.58), VINE)
			r:Seg("Tail", "TailVine", V3(0, 2.36, 1.6), V3(0, 2.74, 1.86), 0.24, 0.24, VINE)
			r:Seg("Tail2", "TailVine2", V3(0, 2.72, 1.84), V3(0, 3.1, 1.96), 0.22, 0.22, VINE)
			r:Box("Tail2", "TailLeaf", V3(0.06, 0.42, 0.36), CF(0.16, 2.95, 2.02) * ANG(0.4, 0, -0.5), LEAF)
			r:Box("TailTip", "TailCurlA", V3(0.2, 0.2, 0.46), V3(0, 3.24, 1.82), VINE)
			r:Box("TailTip", "TailCurlB", V3(0.2, 0.34, 0.2), V3(0, 3.08, 1.62), VINE)
			r:Box("TailTip", "TailLeafB", V3(0.07, 0.44, 0.4), CF(-0.16, 3.32, 2.12) * ANG(0.4, 0, 0.45), LEAF)
			r:Box("TailTip", "TailLeafVein", V3(0.08, 0.42, 0.04), CF(-0.17, 3.32, 2.12) * ANG(0.4, 0, 0.45), LEAF_LO)
			r:Round("TailTip", "Bud", V3(0.32, 0.28, 0.32), V3(0, 2.86, 1.68), ORANGE, nil, 0.06)
			r:Box("TailTip", "BudRib", V3(0.06, 0.29, 0.33), V3(0, 2.86, 1.68), ORANGE_LO)
			r:Box("TailTip", "BudStem", V3(0.06, 0.1, 0.06), V3(0, 3.03, 1.68), STEM)
			-------- ability FX hooks (PUMPKIN PATCH): embers out of the carved face, a little glow at the charm
			r:Hook(helmet, "Glow", "Embers", V3(0, 4.2, -2.9), GLOW, C(255, 120, 30), 6, 0)
			r:Hook(charm, "Charm", "Embers", V3(0, 1.86, -1.7), GLOW_HOT, GLOW, 2, 0)
		end,
	}
end

---------------------------------------------------------------- H02 SHEET SHIBA (Epic)
do
	local FUR, FUR_LO, FUR_HI, CREAM, CREAM_LO, NOSE = C(214, 128, 58), C(176, 98, 42), C(232, 154, 82), C(248, 236, 210), C(226, 208, 176), C(48, 32, 30)
	local SHEET, SHEET_LO, SHEET_HI, SHEET_SH, HOLE = C(236, 241, 252), C(204, 212, 236), C(252, 253, 255), C(178, 186, 216), C(20, 18, 34)
	local GHOST, GHOST_HOT = C(150, 220, 255), C(220, 248, 255)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.25, 0.3) },
		{ "Neck", "Body", V3(0, 2.95, -1.2) },
		{ "Bib", "Neck", V3(0, 2.75, -1.5) },
		{ "Head", "Neck", V3(0, 3.3, -1.7) },
		{ "Jaw", "Head", V3(0, 3.0, -2.95) },
		{ "Ear_L", "Head", V3(0.56, 4.72, -1.95) },
		{ "Ear_R", "Head", V3(-0.56, 4.72, -1.95) },
		{ "Hem_L1", "Body", V3(1.1, 2.05, -0.75) },
		{ "Hem_L2", "Body", V3(1.1, 2.05, 0.3) },
		{ "Hem_L3", "Body", V3(1.1, 2.05, 1.32) },
		{ "Hem_R1", "Body", V3(-1.1, 2.05, -0.75) },
		{ "Hem_R2", "Body", V3(-1.1, 2.05, 0.3) },
		{ "Hem_R3", "Body", V3(-1.1, 2.05, 1.32) },
		{ "Hem_B", "Body", V3(0, 2.3, 1.86) },
		{ "Tail", "Body", V3(0, 3.2, 1.55) },
		{ "Tail2", "Tail", V3(0, 3.62, 1.5) },
		{ "TailTip", "Tail2", V3(0, 3.82, 1.2) },
	}
	legBones(bones, 0.6, -0.85, 1.25, 1.6, 0.4, -0.06)
	local HEMS = { "Hem_L1", "Hem_L2", "Hem_L3", "Hem_R1", "Hem_R2", "Hem_R3" }
	SPECS.HW_SheetShiba = {
		Code = "H02",
		SignatureName = "GhostFloat",
		Bones = bones,
		Durations = { Signature = 3.6 },
		Motion = { Breath = 0.06, Wag = 0.25, Look = 0.18 },
		Extra = function(clip, t, d, u, add)
			local oneShot = not E.IsLooped(clip)
			local amp, k = 0.07, 2
			if clip == "Walk" then
				amp, k = 0.16, 2
			elseif clip == "Run" then
				amp, k = 0.28, 1
			elseif clip == "DigLoop" then
				amp, k = 0.12, 3
			elseif clip == "Sleep" then
				amp, k = 0.03, 1
			elseif oneShot then
				amp = (clip == "Sniff" and 0.08 or 0.25) * bump(t, 0, d)
			end
			for i, h in ipairs(HEMS) do
				local side = i <= 3 and 1 or -1
				local w = oneShot and math.sin(TAU * 5 * t / d + i) or sinU(u, k, i * 0.17)
				add(h, 0, 0, 0, amp * 0.5 * w, 0, side * amp * (0.6 + 0.4 * w))
			end
			local wb = oneShot and math.sin(TAU * 4 * t / d) or sinU(u, k, 0.33)
			add("Hem_B", 0, 0, 0, amp * (0.5 + 0.5 * wb), 0, amp * 0.3 * wb)
			add("Bib", 0, 0, 0, -amp * 0.6 * wb, 0, amp * 0.3 * math.sin(TAU * (oneShot and t / d or u)))
			if clip == "Idle" then
				-- a ghost bobs: the whole sheeted dog floats a hair up and down
				add("Root", 0, 0.05 + 0.05 * sinU(u, 1), 0, 0, 0, 0)
			elseif clip == "Happy" or clip == "RareFind" then
				-- BOO: it floats up like a real ghost, sheet fluttering
				local float = bump(t, 0.1, d - 0.1)
				add("Root", 0, 0.9 * float, 0, 0, 0, 0.12 * math.sin(TAU * 2 * t / d) * float)
				add("Leg_FL", 0, 0, 0, -0.3 * float, 0, 0)
				add("Leg_FR", 0, 0, 0, -0.3 * float, 0, 0)
				add("Leg_BL", 0, 0, 0, 0.4 * float, 0, 0)
				add("Leg_BR", 0, 0, 0, 0.4 * float, 0, 0)
			elseif clip == "Signature" then
				-- GHOST FLOAT: drifts up out of its own shadow, sways in a slow figure eight with paws dangling,
				-- turns to the viewer with a BOO (head forward, jaw open), then settles back down
				local float = hold(t, 0.2, 0.9, d - 0.8, d - 0.1)
				local x = t / d
				add("Root", 0.35 * math.sin(TAU * 1.5 * x) * float, 1.3 * float + 0.12 * math.sin(TAU * 3 * x) * float, 0,
					0.1 * math.sin(TAU * 3 * x) * float, 0.5 * math.sin(TAU * 0.75 * x) * float, 0.14 * math.sin(TAU * 1.5 * x) * float)
				for _, l in ipairs({ "Leg_FL", "Leg_FR" }) do
					add(l, 0, 0, 0, -0.35 * float + 0.12 * math.sin(TAU * 4 * x) * float, 0, 0)
				end
				for _, l in ipairs({ "Leg_BL", "Leg_BR" }) do
					add(l, 0, 0, 0, 0.45 * float + 0.1 * math.sin(TAU * 4 * x + 1) * float, 0, 0)
				end
				local boo = bump(t, 1.6, 2.4)
				add("Neck", 0, 0, -0.15 * boo, 0.2 * boo, 0, 0)
				add("Head", 0, 0, -0.1 * boo, 0.15 * boo, 0, 0.1 * math.sin(TAU * 6 * x) * boo)
				add("Jaw", 0, 0, 0, -0.45 * boo, 0, 0)
				add("Ear_L", 0, 0, 0, 0.3 * boo, 0, -0.3 * boo)
				add("Ear_R", 0, 0, 0, 0.3 * boo, 0, 0.3 * boo)
				tail(add, 0.2 * float, 0.4 * float, x, 4)
			end
		end,
		Build = function(r)
			-------- the shiba underneath (fur shows at the legs, the snout, the tail and through one tear)
			r:Round("Body", "Torso", V3(1.86, 1.46, 2.9), V3(0, 2.22, 0.3), FUR, nil, 0.24)
			r:Box("Body", "Belly", V3(1.5, 0.12, 2.5), V3(0, 1.47, 0.3), CREAM)
			r:Round("Body", "Chest", V3(1.3, 1.0, 0.3), V3(0, 2.12, -1.22), CREAM, nil, 0.08)
			-------- the bedsheet over the back: crown, side drapes with light / shadow fold pairs
			local sheet = r:Round("Body", "SheetTop", V3(2.14, 0.32, 3.18), V3(0, 3.08, 0.3), SHEET, nil, 0.1, SHEET_HI)
			r:Light(sheet, GHOST, 7, 0.55)
			r:Round("Body", "SheetCrown", V3(1.56, 0.16, 2.7), V3(0, 3.26, 0.3), SHEET_HI, nil, 0.05)
			r:Pair(function(s, side)
				r:Box("Body", "SheetSide_" .. side, V3(0.14, 1.04, 3.12), V3(s * 1.07, 2.52, 0.3), SHEET)
				for i, z in ipairs({ -0.62, 0.22, 0.98 }) do
					r:Box("Body", "FoldHi" .. i .. "_" .. side, V3(0.06, 0.96, 0.1), V3(s * 1.16, 2.5, z), SHEET_HI)
					r:Box("Body", "FoldLo" .. i .. "_" .. side, V3(0.05, 0.86, 0.1), V3(s * 1.155, 2.46, z + 0.1), SHEET_LO)
				end
				r:Box("Body", "SheetBulge_" .. side, V3(0.06, 0.42, 0.9), V3(s * 1.16, 2.78, -0.3), SHEET_HI)
			end)
			-- an embroidered pumpkin patch on the left flank
			r:Box("Body", "Patch", V3(0.04, 0.54, 0.58), V3(1.17, 2.48, 0.62), C(214, 222, 240))
			r:Box("Body", "PatchPumpkin", V3(0.03, 0.26, 0.32), V3(1.195, 2.46, 0.62), C(255, 140, 40))
			r:Box("Body", "PatchFace", V3(0.02, 0.06, 0.18), V3(1.21, 2.44, 0.62), C(90, 40, 20))
			r:Box("Body", "PatchStem", V3(0.03, 0.08, 0.06), V3(1.195, 2.63, 0.62), C(90, 120, 50))
			for i, o in ipairs({ V3(0, 0.3, 0), V3(0, -0.3, 0), V3(0, 0, 0.32), V3(0, 0, -0.32) }) do
				local size = o.Y ~= 0 and V3(0.035, 0.04, 0.5) or V3(0.035, 0.46, 0.04)
				r:Box("Body", "PatchStitch" .. i, size, V3(1.19, 2.48, 0.62) + o, C(120, 130, 160))
			end
			-- a tear on the right flank: shiba fur peeks through a frayed hole
			r:Box("Body", "TearRim", V3(0.04, 0.4, 0.5), V3(-1.17, 2.55, 0.78), SHEET_SH)
			r:Box("Body", "TearFur", V3(0.04, 0.28, 0.36), V3(-1.19, 2.55, 0.78), FUR)
			r:Box("Body", "TearFray", V3(0.04, 0.08, 0.14), V3(-1.2, 2.7, 0.66), SHEET_LO)
			-------- ragged hem panels (bones sway them), teeth of different lengths, the faint ghost glow and an ecto drip
			local hemLen = { 0.62, 0.48, 0.66 }
			for i, z in ipairs({ -0.75, 0.3, 1.32 }) do
				r:Pair(function(s, side)
					local bone = "Hem_" .. side .. i
					local len = hemLen[s > 0 and i or (4 - i)]
					-- the skirt flares out a little toward the hem
					local hf = CF(s * 1.1, 2.08, z) * ANG(0, 0, s * 0.16)
					r:Box(bone, "Hem" .. i .. "_" .. side, V3(0.14, len, 1.04), hf * CF(0, -len / 2, 0), SHEET)
					r:Box(bone, "HemFold" .. i .. "_" .. side, V3(0.05, len * 0.8, 0.1), hf * CF(s * 0.08, -len / 2, 0.18), SHEET_LO)
					r:Box(bone, "HemToothA" .. i .. "_" .. side, V3(0.14, 0.24, 0.36), hf * CF(0, -len - 0.12, -0.3), SHEET)
					r:Box(bone, "HemToothB" .. i .. "_" .. side, V3(0.14, 0.14, 0.26), hf * CF(0, -len - 0.07, 0.32), SHEET_HI)
					r:Neon(bone, "HemGlow" .. i .. "_" .. side, V3(0.16, 0.05, 1.0), hf * CF(0, -len + 0.03, 0), GHOST, { Transparency = 0.15 })
					if i == 2 then
						r:Box(bone, "Ecto" .. i .. "_" .. side, V3(0.1, 0.22, 0.1), hf * CF(0, -len - 0.32, -0.3), C(170, 240, 255), MAT.Glass, { Transparency = 0.3 })
						r:Neon(bone, "EctoDrop" .. i .. "_" .. side, V3(0.08, 0.08, 0.08), hf * CF(0, -len - 0.47, -0.3), GHOST_HOT)
					end
				end)
			end
			r:Round("Body", "SheetRump", V3(2.14, 0.86, 0.16), V3(0, 2.62, 1.84), SHEET, nil, 0.05)
			r:Box("Body", "SheetRumpFold", V3(0.08, 0.7, 0.05), V3(-0.4, 2.6, 1.93), SHEET_LO)
			r:Box("Hem_B", "HemBack", V3(2.06, 0.72, 0.14), V3(0, 1.94, 1.86), SHEET)
			r:Box("Hem_B", "HemBackFold", V3(0.1, 0.6, 0.05), V3(0.35, 1.98, 1.95), SHEET_LO)
			r:Box("Hem_B", "HemBackToothA", V3(0.5, 0.24, 0.14), V3(0.55, 1.46, 1.86), SHEET)
			r:Box("Hem_B", "HemBackToothB", V3(0.42, 0.18, 0.14), V3(-0.62, 1.49, 1.86), SHEET)
			r:Box("Hem_B", "HemBackToothC", V3(0.26, 0.3, 0.14), V3(-0.05, 1.43, 1.86), SHEET_HI)
			r:Neon("Hem_B", "HemBackGlow", V3(2.0, 0.05, 0.16), V3(0, 1.6, 1.86), GHOST, { Transparency = 0.15 })
			-- the tail hole
			r:Box("Body", "TailHole", V3(0.64, 0.05, 0.64), V3(0, 3.255, 1.55), SHEET_SH)
			r:Box("Body", "TailHoleIn", V3(0.46, 0.05, 0.46), V3(0, 3.27, 1.55), HOLE)
			-------- legs: shiba legs, cream socks and paws with toes
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.6, front and -0.85 or 1.25
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.55, 1.22, 0.56), V3(x, 1.06, z), FUR, nil, 0.1)
				r:Box(leg, "LegBack_" .. tag, V3(0.1, 0.8, 0.36), V3(x + s * 0.27, 1.16, z + 0.06), FUR_LO)
				r:Round(leg, "Sock_" .. tag, V3(0.6, 0.34, 0.6), V3(x, 0.56, z), CREAM, nil, 0.08)
				r:Paw(paw, tag, x, z - 0.06, 0.64, 0.7, 0.4, CREAM, { Toe = CREAM, Bean = C(200, 150, 140) })
			end
			-------- the hood: sheet over the head with eye holes; the ears tent it up; the left ear tears through
			r:Round("Head", "Hood", V3(2.12, 1.7, 1.86), V3(0, 3.88, -2.05), SHEET, nil, 0.26, SHEET_HI)
			r:Round("Head", "HoodCrown", V3(1.5, 0.28, 1.36), V3(0, 4.78, -2.05), SHEET_HI, nil, 0.08)
			r:Box("Head", "HoodDrape", V3(1.96, 1.2, 0.56), CF(0, 3.45, -0.95) * ANG(-0.38, 0, 0), SHEET)
			r:Box("Head", "HoodDrapeFold", V3(0.06, 1.0, 0.58), CF(0.45, 3.45, -0.95) * ANG(-0.38, 0, 0), SHEET_LO)
			r:Box("Head", "HoodDrapeFoldB", V3(0.06, 0.9, 0.58), CF(-0.55, 3.4, -0.95) * ANG(-0.38, 0, 0), SHEET_LO)
			r:Pair(function(s, side)
				r:Box("Head", "HoodFold_" .. side, V3(0.04, 1.2, 0.08), V3(s * 1.07, 3.85, -2.4), SHEET_LO)
				r:Box("Head", "HoodFoldHi_" .. side, V3(0.05, 1.2, 0.08), V3(s * 1.075, 3.88, -2.5), SHEET_HI)
				r:Box("Head", "HoodFoldB_" .. side, V3(0.04, 0.9, 0.08), V3(s * 1.07, 3.75, -1.55), SHEET_LO)
				-- eye holes (a plus of two boxes reads round), shiba eyes peeking out, a ghostly glow under each
				local ex = s * 0.44
				r:Box("Head", "HoleA_" .. side, V3(0.5, 0.4, 0.03), V3(ex, 4.12, -2.99), HOLE)
				r:Box("Head", "HoleB_" .. side, V3(0.34, 0.6, 0.03), V3(ex, 4.12, -2.99), HOLE)
				r:Box("Head", "HoleEdge_" .. side, V3(0.38, 0.05, 0.03), V3(ex, 4.45, -2.985), SHEET_SH)
				r:Box("Head", "EyeIris_" .. side, V3(0.22, 0.26, 0.03), V3(ex + s * 0.02, 4.1, -3.015), C(56, 30, 20))
				r:Box("Head", "EyePupil_" .. side, V3(0.12, 0.16, 0.03), V3(ex + s * 0.02, 4.09, -3.04), C(10, 8, 12))
				r:Neon("Head", "EyeShine_" .. side, V3(0.07, 0.07, 0.03), V3(ex + 0.07, 4.17, -3.06), C(255, 255, 255))
				r:Neon("Head", "HoleGlow_" .. side, V3(0.3, 0.04, 0.03), V3(ex, 3.83, -3.0), GHOST, { Transparency = 0.1 })
				r:Box("Head", "Blush_" .. side, V3(0.24, 0.08, 0.03), V3(s * 0.62, 3.75, -2.985), C(255, 196, 212))
				-- ragged lower edge of the hood
				r:Box("Head", "HoodTabA_" .. side, V3(0.36, 0.22, 0.12), V3(s * 0.8, 3.1, -2.92), SHEET)
				r:Box("Head", "HoodTabB_" .. side, V3(0.12, 0.32, 1.0), V3(s * 1.08, 3.02, -2.4), SHEET)
				r:Box("Head", "HoodTabC_" .. side, V3(0.12, 0.2, 0.5), V3(s * 1.08, 3.08, -1.6), SHEET_HI)
			end)
			r:Neon("Head", "HoodGlow", V3(1.86, 0.05, 0.12), V3(0, 3.21, -2.95), GHOST, { Transparency = 0.15 })
			-------- shiba snout under the hood: cream cheeks, nose with nostrils, mouth line, tongue on the jaw
			r:Round("Head", "Snout", V3(0.96, 0.56, 0.8), V3(0, 3.24, -3.32), FUR, nil, 0.12, FUR_HI)
			r:Round("Head", "Cheeks", V3(1.24, 0.4, 0.52), V3(0, 3.06, -3.06), CREAM, nil, 0.1)
			r:Round("Head", "SnoutCream", V3(0.7, 0.3, 0.4), V3(0, 3.1, -3.55), CREAM, nil, 0.06)
			r:Round("Head", "Nose", V3(0.38, 0.24, 0.2), V3(0, 3.44, -3.74), NOSE, nil, 0.05)
			r:Box("Head", "NostrilL", V3(0.06, 0.05, 0.03), V3(0.08, 3.41, -3.85), C(20, 12, 12))
			r:Box("Head", "NostrilR", V3(0.06, 0.05, 0.03), V3(-0.08, 3.41, -3.85), C(20, 12, 12))
			r:Box("Head", "NoseShine", V3(0.1, 0.05, 0.03), V3(0.07, 3.52, -3.85), C(210, 200, 210))
			r:Box("Head", "MouthLine", V3(0.06, 0.16, 0.03), V3(0, 3.24, -3.765), NOSE)
			r:Box("Head", "Mouth", V3(0.46, 0.04, 0.03), V3(0, 3.14, -3.765), NOSE)
			r:Round("Jaw", "Jaw", V3(0.8, 0.2, 0.66), V3(0, 2.86, -3.3), CREAM, nil, 0.06)
			r:Box("Jaw", "Tongue", V3(0.3, 0.06, 0.34), V3(0, 2.97, -3.52), C(236, 110, 120))
			-------- ear tents; the left ear tip has torn through the sheet
			r:Pair(function(s, side)
				local bone = "Ear_" .. side
				r:Round(bone, "TentA_" .. side, V3(0.66, 0.36, 0.58), V3(s * 0.56, 4.94, -1.95), SHEET, nil, 0.08)
				r:Box(bone, "TentB_" .. side, V3(0.44, 0.3, 0.4), V3(s * 0.58, 5.24, -1.97), SHEET_HI)
				r:Box(bone, "TentShade_" .. side, V3(0.04, 0.5, 0.4), V3(s * 0.31, 5.05, -1.95), SHEET_LO)
				if s < 0 then
					r:Box(bone, "TentC_" .. side, V3(0.24, 0.24, 0.2), V3(s * 0.6, 5.5, -1.99), SHEET_HI)
				else
					r:Box(bone, "TearRing_" .. side, V3(0.34, 0.06, 0.3), V3(s * 0.6, 5.4, -1.98), SHEET_SH)
					r:Tri(bone, "EarTip_" .. side, V3(s * 0.6, 5.6, -1.98), 0.32, 0.4, 0.14, FUR, MAT.SmoothPlastic, false)
					r:Tri(bone, "EarTipIn_" .. side, V3(s * 0.6, 5.57, -2.06), 0.16, 0.24, 0.03, CREAM, MAT.SmoothPlastic, false)
				end
			end)
			-------- bib with a bow tie and a candy-corn charm
			r:Box("Bib", "Bib", V3(1.5, 0.5, 0.12), V3(0, 2.95, -1.48), SHEET)
			r:Box("Bib", "BibTooth", V3(0.5, 0.2, 0.12), V3(-0.3, 2.6, -1.48), SHEET)
			r:Box("Bib", "BibToothB", V3(0.3, 0.14, 0.12), V3(0.42, 2.63, -1.48), SHEET_HI)
			r:Neon("Bib", "BibGlow", V3(1.48, 0.05, 0.14), V3(0, 2.72, -1.48), GHOST, { Transparency = 0.15 })
			r:Box("Bib", "BowKnot", V3(0.2, 0.2, 0.14), V3(0, 3.08, -1.58), C(255, 128, 24))
			r:Pair(function(s, side)
				r:Wedge("Bib", "Bow_" .. side, V3(0.12, 0.3, 0.32), CF(s * 0.26, 3.08, -1.58) * ANG(0, s * PI / 2, 0), C(255, 128, 24))
			end)
			r:Box("Bib", "CornA", V3(0.24, 0.12, 0.08), V3(0, 2.88, -1.6), C(255, 240, 210))
			r:Box("Bib", "CornB", V3(0.18, 0.12, 0.08), V3(0, 2.76, -1.6), C(255, 140, 30))
			r:Box("Bib", "CornC", V3(0.1, 0.12, 0.08), V3(0, 2.64, -1.6), C(255, 214, 60))
			-------- curly shiba tail out of the tail hole (3 bones), cream underside and tip
			r:Round("Tail", "TailRoot", V3(0.42, 0.56, 0.42), V3(0, 3.46, 1.58), FUR, nil, 0.08)
			r:Round("Tail2", "TailCurl", V3(0.46, 0.44, 0.62), V3(0, 3.78, 1.36), FUR, nil, 0.1, FUR_HI)
			r:Box("Tail2", "TailCurlCream", V3(0.36, 0.1, 0.5), V3(0, 3.55, 1.36), CREAM)
			r:Round("TailTip", "TailFront", V3(0.4, 0.44, 0.42), V3(0, 3.68, 1.04), FUR, nil, 0.08)
			r:Round("TailTip", "TailTipCream", V3(0.36, 0.3, 0.36), V3(0, 3.4, 1.02), CREAM, nil, 0.06)
			r:Tuft("TailTip", "TailFluff", CF(0, 3.32, 1.0), 0.3, 0.26, 2, CREAM, CREAM_LO)
			-------- ability FX hooks (GHOST LOOT): ghost wisps off the sheet and the back hem
			r:Hook(sheet, "Sheet", "Wisps", V3(0, 3.3, 0.1), GHOST, GHOST_HOT, 4, 0.8)
		end,
	}
end

---------------------------------------------------------------- H03 BONE CORGI (Epic)
do
	local BONE, BONE_LO, BONE_HI, JOINT, INK = C(236, 226, 200), C(198, 184, 154), C(252, 248, 234), C(214, 198, 160), C(26, 20, 32)
	local SOUL, SOUL_HOT, RED, GOLD = C(120, 255, 140), C(228, 255, 228), C(200, 40, 52), C(255, 200, 70)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.1, 0.35) },
		{ "Ribs_L", "Body", V3(0.45, 2.3, -0.42) },
		{ "Ribs_R", "Body", V3(-0.45, 2.3, -0.42) },
		{ "Soul", "Body", V3(0, 2.02, -0.42) },
		{ "Pelvis", "Body", V3(0, 2.3, 1.3) },
		{ "Neck", "Body", V3(0, 2.6, -1.15) },
		{ "Head", "Neck", V3(0, 2.85, -1.6) },
		{ "Jaw", "Head", V3(0, 2.62, -2.28) },
		{ "Ear_L", "Head", V3(0.45, 3.82, -1.85) },
		{ "Ear_R", "Head", V3(-0.45, 3.82, -1.85) },
		{ "Tail", "Pelvis", V3(0, 2.5, 1.62) },
		{ "Tail2", "Tail", V3(0, 2.62, 1.94) },
		{ "TailTip", "Tail2", V3(0, 2.74, 2.2) },
	}
	legBones(bones, 0.55, -0.75, 1.3, 1.62, 0.42)
	-- where each bone flies when the skeleton falls apart (model space; children subtract their parent's flight)
	local BURST = {
		Body = { V3(0, 0.55, 0), V3(0.15, 0, 0) },
		Ribs_L = { V3(0.9, 0.35, -0.2), V3(0, 0, -0.6) },
		Ribs_R = { V3(-0.9, 0.35, -0.2), V3(0, 0, 0.6) },
		Soul = { V3(0, 0.7, -0.1), V3(0, 3.1, 0) },
		Pelvis = { V3(0, 0.75, 0.55), V3(0.5, 0, 0) },
		Neck = { V3(0, 0.8, -0.45), V3(0.25, 0, 0) },
		Head = { V3(0, 1.15, -0.8), V3(0.4, 0.4, 0) },
		Jaw = { V3(0, 0.8, -1.1), V3(-0.6, 0, 0) },
		Ear_L = { V3(0.55, 1.55, -0.8), V3(0, 0, -0.9) },
		Ear_R = { V3(-0.55, 1.55, -0.8), V3(0, 0, 0.9) },
		Tail = { V3(0, 0.95, 0.95), V3(-0.6, 0, 0) },
		Tail2 = { V3(0, 1.1, 1.25), V3(-0.7, 0, 0) },
		TailTip = { V3(0, 1.25, 1.55), V3(-0.8, 0, 0) },
		Leg_FL = { V3(0.75, 0.25, -0.5), V3(0.5, 0, -0.5) },
		Leg_FR = { V3(-0.75, 0.25, -0.5), V3(0.5, 0, 0.5) },
		Leg_BL = { V3(0.75, 0.25, 0.5), V3(-0.5, 0, -0.5) },
		Leg_BR = { V3(-0.75, 0.25, 0.5), V3(-0.5, 0, 0.5) },
		Paw_FL = { V3(0.95, 0.15, -0.75), V3(0.8, 0, 0) },
		Paw_FR = { V3(-0.95, 0.15, -0.75), V3(0.8, 0, 0) },
		Paw_BL = { V3(0.95, 0.15, 0.75), V3(-0.8, 0, 0) },
		Paw_BR = { V3(-0.95, 0.15, 0.75), V3(-0.8, 0, 0) },
	}
	local PARENT = {}
	for _, b in ipairs(bones) do
		PARENT[b[1]] = b[2]
	end
	local function burst(t, add, a, b, c, e)
		-- a..b fly apart, hover until c, snap back by e (with a wobble)
		local out = rise(t, a, b)
		local back = rise(t, c, e)
		local k = out * (1 - back)
		local wob = bump(t, c, e) * 0.12
		for name, v in pairs(BURST) do
			local p = PARENT[name]
			local dv = v[1] - (p and BURST[p] and BURST[p][1] or V3(0, 0, 0))
			local spin = v[2] * k
			add(name, dv.X * k, dv.Y * k + wob * (name == "Head" and 1 or 0), dv.Z * k, spin.X, spin.Y, spin.Z)
		end
	end
	-- the skeleton drops into a heap of bones (k = 0..1)
	local function heap(add, k)
		add("Body", 0, -1.22 * k, 0.05 * k, 0.05 * k, 0, 0.08 * k)
		for _, l in ipairs(LEG_TAGS) do
			local s = l[2]
			add("Leg_" .. l[1], 0, 0, 0, (l[3] and 0.25 or -0.25) * k, 0, s * 1.3 * k)
			add("Paw_" .. l[1], 0, 0, 0, 0, 0, -s * 1.0 * k)
		end
		add("Ribs_L", 0, -0.05 * k, 0, 0, 0, 0.75 * k)
		add("Ribs_R", 0, -0.05 * k, 0, 0, 0, -0.75 * k)
		add("Pelvis", 0, -0.05 * k, 0, 0, 0, 0.25 * k)
		add("Neck", 0, 0, 0, -0.7 * k, 0.2 * k, 0)
		add("Head", 0, -0.12 * k, -0.15 * k, 0.15 * k, 0.4 * k, 0.45 * k)
		add("Jaw", 0, 0, 0, -0.35 * k, 0, 0)
		add("Ear_L", 0, 0, 0, 0, 0, -0.4 * k)
		add("Ear_R", 0, 0, 0, 0, 0, 0.5 * k)
		add("Tail", 0, 0, 0, -0.6 * k, 0.4 * k, 0)
		add("Soul", 0, 0.9 * k, 0, 0, 0, 0)
	end
	SPECS.HW_BoneCorgi = {
		Code = "H03",
		SignatureName = "Rattle",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.4 },
		Motion = { Breath = 0.04, Wag = 0.5, Stride = 0.5, Hop = 0.4, Look = 0.25 },
		Extra = function(clip, t, d, u, add)
			local x = E.IsLooped(clip) and u or t / d
			-- the soul flame never sits still
			add("Soul", 0, 0.06 * sinU(x, E.IsLooped(clip) and 2 or 3), 0, 0, TAU * x, 0)
			if clip == "Idle" then
				add("Ribs_L", 0, 0, 0, 0, 0, -0.04 * sinU(u, 1))
				add("Ribs_R", 0, 0, 0, 0, 0, 0.04 * sinU(u, 1))
				add("Jaw", 0, 0, 0, -0.14 * bump(u, 0.3, 0.36) - 0.14 * bump(u, 0.38, 0.44), 0, 0) -- clack clack
				-- a rattle: every bone shivers for a moment
				local rat = bump(u, 0.72, 0.84)
				for i, b in ipairs({ "Ribs_L", "Ribs_R", "Pelvis", "Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR", "Head", "Tail" }) do
					add(b, 0, 0.02 * rat * sinU(u, 60, i * 0.13), 0, 0.05 * rat * sinU(u, 50, i * 0.29), 0, 0.06 * rat * sinU(u, 70, i * 0.41))
				end
			elseif clip == "Walk" or clip == "Run" then
				add("Jaw", 0, 0, 0, -0.08 * sinU(u, 2), 0, 0)
				add("Ribs_L", 0, 0, 0, 0, 0, -0.05 * sinU(u, 2))
				add("Ribs_R", 0, 0, 0, 0, 0, 0.05 * sinU(u, 2))
				add("Pelvis", 0, 0, 0, 0, 0.06 * sinU(u, 1), 0)
			elseif clip == "DigLoop" then
				add("Jaw", 0, 0, 0, -0.1 * math.max(0, sinU(u, 2)), 0, 0)
				add("Pelvis", 0, 0, 0, 0, 0.08 * sinU(u, 1), 0.04 * sinU(u, 2))
			elseif clip == "DigFind" then
				burst(t, add, 0.25, 0.55, 0.95, 1.3)
			elseif clip == "Happy" then
				burst(t, add, 0.12, 0.45, 1.05, 1.45)
				add("Soul", 0, 0, 0, 0, TAU * 2 * rise(t, 0.2, 1.3), 0)
			elseif clip == "RareFind" then
				burst(t, add, 1.25, 1.55, 1.95, 2.4)
			elseif clip == "Signature" then
				-- RATTLE: it shakes itself to pieces, drops into a heap of bones, the soul hovers, then it snaps back together
				local shake = bump(t, 0.05, 0.75)
				for i, b in ipairs({ "Ribs_L", "Ribs_R", "Pelvis", "Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR", "Head", "Jaw", "Tail", "Neck" }) do
					add(b, 0.03 * shake * math.sin(TAU * 21 * t + i), 0.03 * shake * math.sin(TAU * 17 * t + i * 2), 0,
						0.08 * shake * math.sin(TAU * 19 * t + i * 3), 0.05 * shake * math.sin(TAU * 23 * t + i), 0.09 * shake * math.sin(TAU * 25 * t + i * 5))
				end
				local fall = rise(t, 0.6, 0.95)
				local back = rise(t, 2.35, 2.85)
				local k = fall * (1 - back)
				-- the landing bounces a little; the rebuild overshoots
				k += 0.08 * bump(t, 0.95, 1.2) - 0.1 * bump(t, 2.8, 3.2)
				heap(add, k)
				local peek = bump(t, 1.5, 2.3)
				add("Head", 0, 0.12 * peek, 0, 0, -0.5 * peek, 0) -- the skull looks around from the heap
				add("Soul", 0, 0.2 * math.sin(TAU * 2 * t / d) * k, 0, 0, TAU * 2 * rise(t, 0.8, 2.6), 0)
				add("Jaw", 0, 0, 0, -0.25 * bump(t, 2.85, 3.3), 0, 0)
				tail(add, 0.3 * bump(t, 2.8, d), 0.6 * bump(t, 2.8, d), t / d, 8)
			end
		end,
		Build = function(r)
			-------- the skull: cranium with crest and brow, deep sockets with green soul eyes, cheekbones, snout, teeth
			r:Round("Head", "Cranium", V3(1.42, 1.08, 1.3), V3(0, 3.28, -2.0), BONE, nil, 0.22, BONE_HI)
			r:Round("Head", "Occiput", V3(1.0, 0.72, 0.32), V3(0, 3.24, -1.3), BONE_LO, nil, 0.1)
			r:Box("Head", "Crest", V3(0.12, 0.08, 1.0), V3(0, 3.84, -2.0), BONE_HI)
			r:Box("Head", "Brow", V3(1.5, 0.18, 0.2), V3(0, 3.62, -2.66), BONE_HI)
			r:Box("Head", "Crack", V3(0.05, 0.42, 0.04), CF(0.25, 3.6, -2.775) * ANG(0, 0, 0.5), INK)
			r:Box("Head", "CrackB", V3(0.05, 0.03, 0.3), CF(0.36, 3.83, -2.3) * ANG(0, 0.5, 0), INK)
			r:Box("Head", "CrackC", V3(0.04, 0.04, 0.3), CF(-0.3, 3.83, -1.7) * ANG(0, 0.5, 0), INK)
			r:Pair(function(s, side)
				r:Round("Head", "Socket_" .. side, V3(0.5, 0.46, 0.1), V3(s * 0.36, 3.22, -2.65), INK, nil, 0.06)
				r:Box("Head", "SocketDeep_" .. side, V3(0.3, 0.28, 0.04), V3(s * 0.36, 3.22, -2.7), C(8, 4, 12))
				r:Neon("Head", "EyeGlow_" .. side, V3(0.15, 0.15, 0.04), V3(s * 0.34, 3.19, -2.72), SOUL)
				r:Neon("Head", "EyeShine_" .. side, V3(0.06, 0.06, 0.03), V3(s * 0.34 + 0.05, 3.25, -2.745), SOUL_HOT)
				r:Box("Head", "CheekBone_" .. side, V3(0.16, 0.18, 0.74), V3(s * 0.7, 3.0, -2.5), BONE_HI)
				r:Box("Head", "Temple_" .. side, V3(0.08, 0.36, 0.5), V3(s * 0.72, 3.38, -2.0), BONE_LO)
				r:Box("Head", "Fang_" .. side, V3(0.11, 0.24, 0.1), V3(s * 0.34, 2.64, -3.38), BONE_HI)
				r:Box("Head", "JawHinge_" .. side, V3(0.16, 0.2, 0.2), V3(s * 0.42, 2.7, -2.3), JOINT)
			end)
			r:Round("Head", "Snout", V3(0.86, 0.52, 0.9), V3(0, 2.98, -3.02), BONE, nil, 0.1, BONE_HI)
			r:Tri("Head", "NoseHole", V3(0, 3.08, -3.48), 0.34, 0.26, 0.04, INK, MAT.SmoothPlastic, true)
			r:Box("Head", "SnoutRidge", V3(0.1, 0.06, 0.7), V3(0, 3.26, -2.95), BONE_HI)
			for i, x in ipairs({ -0.17, -0.06, 0.06, 0.17 }) do
				r:Box("Head", "Tooth" .. i, V3(0.09, 0.14, 0.1), V3(x, 2.68, -3.4), BONE_HI)
			end
			-------- jaw: mandible with a row of teeth (it clacks)
			r:Pair(function(s, side)
				r:Box("Jaw", "Mandible_" .. side, V3(0.14, 0.2, 1.02), V3(s * 0.36, 2.54, -2.84), BONE)
			end)
			r:Round("Jaw", "Chin", V3(0.86, 0.22, 0.26), V3(0, 2.54, -3.3), BONE, nil, 0.06)
			for i, x in ipairs({ -0.22, -0.08, 0.08, 0.22 }) do
				r:Box("Jaw", "LowTooth" .. i, V3(0.09, 0.12, 0.09), V3(x, 2.68, -3.3), BONE_HI)
			end
			-------- big corgi ears (bone), with a hollow inside
			r:Pair(function(s, side)
				local turn = ANG(0, 0, -s * 0.22)
				r:Tri("Ear_" .. side, "Ear_" .. side, V3(s * 0.5, 4.25, -1.86), 0.76, 0.94, 0.16, BONE, MAT.SmoothPlastic, false, turn)
				r:Tri("Ear_" .. side, "EarIn_" .. side, V3(s * 0.5, 4.2, -1.95), 0.44, 0.6, 0.04, BONE_LO, MAT.SmoothPlastic, false, turn)
				r:Box("Ear_" .. side, "EarBase_" .. side, V3(0.5, 0.16, 0.22), V3(s * 0.46, 3.84, -1.86), BONE_HI)
			end)
			-------- neck vertebrae + red bandana with polka dots and a bone tag
			for i = 0, 2 do
				r:Round("Neck", "NeckBone" .. i, V3(0.34, 0.3, 0.28), V3(0, 2.64 + i * 0.08, -1.24 - i * 0.18), i % 2 == 0 and BONE or BONE_HI, nil, 0.06)
			end
			r:Round("Neck", "Bandana", V3(0.96, 0.3, 0.64), V3(0, 2.48, -1.35), RED, MAT.Fabric, 0.06)
			r:Tri("Neck", "BandanaTip", V3(0, 2.18, -1.68), 0.86, 0.5, 0.08, RED, MAT.Fabric, true)
			for i, p in ipairs({ V3(-0.2, 2.32, -1.73), V3(0.18, 2.36, -1.73), V3(0, 2.12, -1.73), V3(0.4, 2.52, -1.68) }) do
				r:Box("Neck", "Dot" .. i, V3(0.07, 0.07, 0.03), p, C(255, 232, 222))
			end
			r:Box("Neck", "Tag", V3(0.3, 0.12, 0.05), V3(0, 1.96, -1.74), GOLD, MAT.Metal)
			r:Box("Neck", "TagEndA", V3(0.08, 0.16, 0.05), V3(-0.17, 1.96, -1.74), GOLD, MAT.Metal)
			r:Box("Neck", "TagEndB", V3(0.08, 0.16, 0.05), V3(0.17, 1.96, -1.74), GOLD, MAT.Metal)
			r:Box("Neck", "TagRing", V3(0.06, 0.1, 0.05), V3(0, 2.07, -1.74), GOLD, MAT.Metal)
			-------- spine: centrum + spinous process + transverse processes per vertebra
			for i = 0, 6 do
				local z = -0.95 + i * 0.42
				r:Box("Body", "Vertebra" .. i, V3(0.36, 0.26, 0.27), V3(0, 2.55, z), BONE)
				r:Box("Body", "Spine" .. i, V3(0.11, 0.22, 0.14), CF(0, 2.78, z + 0.03) * ANG(-0.25, 0, 0), i % 2 == 0 and BONE_HI or BONE)
				r:Box("Body", "Transverse" .. i, V3(0.56, 0.07, 0.1), V3(0, 2.5, z), BONE_LO)
			end
			r:Box("Body", "Sternum", V3(0.22, 0.12, 1.42), V3(0, 1.68, -0.36), BONE)
			r:Box("Body", "Xiphoid", V3(0.12, 0.1, 0.26), V3(0, 1.7, 0.42), BONE_LO)
			r:Pair(function(s, side)
				r:Box("Body", "Blade_" .. side, V3(0.1, 0.56, 0.48), CF(s * 0.52, 2.28, -0.82) * ANG(0, 0, s * 0.15), BONE_LO)
				r:Box("Body", "BladeRidge_" .. side, V3(0.12, 0.44, 0.08), CF(s * 0.56, 2.3, -0.82) * ANG(0, 0, s * 0.15), BONE_HI)
			end)
			-------- pelvis: sacrum, ilium wings, hip sockets
			r:Round("Pelvis", "Sacrum", V3(0.52, 0.3, 0.6), V3(0, 2.46, 1.32), BONE, nil, 0.06)
			r:Pair(function(s, side)
				r:Round("Pelvis", "Ilium_" .. side, V3(0.16, 0.5, 0.56), CF(s * 0.4, 2.36, 1.28) * ANG(0, 0, -s * 0.25), BONE, nil, 0.05)
				r:Round("Pelvis", "HipSocket_" .. side, V3(0.3, 0.3, 0.3), V3(s * 0.55, 2.08, 1.3), JOINT, nil, 0.06)
			end)
			r:Box("Pelvis", "Ischium", V3(0.64, 0.12, 0.42), V3(0, 2.02, 1.55), BONE_LO)
			-------- rib cage: five curved ribs per side (top, outer bow, lower arc to the sternum)
			r:Pair(function(s, side)
				local bone = "Ribs_" .. side
				for i, z in ipairs({ -0.95, -0.63, -0.31, 0.01, 0.31 }) do
					local k = ({ 1, 1, 0.97, 0.9, 0.78 })[i]
					local bot = 1.74 + (1 - k) * 1.2
					r:Box(bone, "RibTop" .. i .. "_" .. side, V3(0.44, 0.12, 0.13), V3(s * 0.31, 2.48, z), BONE)
					r:Seg(bone, "RibSide" .. i .. "_" .. side, V3(s * 0.5, 2.52, z), V3(s * 0.62 * k, 2.02 + (1 - k) * 0.5, z), 0.13, 0.13, BONE)
					r:Seg(bone, "RibLow" .. i .. "_" .. side, V3(s * 0.64 * k, 2.08 + (1 - k) * 0.5, z), V3(s * 0.12, bot, z), 0.12, 0.12, BONE_LO)
				end
			end)
			-------- the soul: a green heart-flame inside the ribs
			local soul = r:Neon("Soul", "SoulCore", V3(0.32, 0.32, 0.32), CF(0, 2.02, -0.42) * ANG(0.6, 0.78, 0), SOUL)
			r:Neon("Soul", "SoulHot", V3(0.15, 0.15, 0.15), CF(0, 2.02, -0.42) * ANG(0.2, 0.3, 0.5), SOUL_HOT)
			r:Tuft("Soul", "SoulFlame", CF(0, 2.16, -0.42) * ANG(PI, 0.4, 0), 0.4, 0.22, 2, SOUL, SOUL_HOT, MAT.Neon)
			r:Light(soul, SOUL, 7, 1.3)
			-------- short corgi legs: femur, knee, tibia + fibula; ankle, foot bones and claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.55, front and -0.75 or 1.3
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "FemurHead_" .. tag, V3(0.32, 0.22, 0.32), V3(x, 1.62, z), BONE_HI, nil, 0.06)
				r:Box(leg, "Femur_" .. tag, V3(0.22, 0.56, 0.22), V3(x, 1.33, z), BONE)
				r:Round(leg, "Knee_" .. tag, V3(0.32, 0.26, 0.32), V3(x, 1.02, z), JOINT, nil, 0.07)
				r:Box(leg, "Tibia_" .. tag, V3(0.2, 0.52, 0.2), V3(x, 0.7, z), BONE)
				r:Box(leg, "Fibula_" .. tag, V3(0.07, 0.46, 0.07), V3(x + s * 0.12, 0.72, z + 0.04), BONE_LO)
				r:Round(paw, "Ankle_" .. tag, V3(0.3, 0.2, 0.3), V3(x, 0.38, z), BONE_HI, nil, 0.06)
				r:Box(paw, "Heel_" .. tag, V3(0.42, 0.12, 0.3), V3(x, 0.08, z + 0.06), BONE)
				for j, dx in ipairs({ -0.14, 0, 0.14 }) do
					r:Seg(paw, "Metatarsal" .. j .. "_" .. tag, V3(x + dx * 0.5, 0.3, z - 0.05), V3(x + dx, 0.08, z - 0.32), 0.08, 0.08, BONE_LO)
					r:Box(paw, "Toe" .. j .. "_" .. tag, V3(0.1, 0.1, 0.18), V3(x + dx, 0.06, z - 0.42), BONE_HI)
					r:Box(paw, "Claw" .. j .. "_" .. tag, V3(0.06, 0.06, 0.1), V3(x + dx, 0.04, z - 0.55), BONE_LO)
				end
			end
			-------- tail vertebrae (three bones)
			r:Round("Tail", "TailBoneA", V3(0.26, 0.24, 0.26), V3(0, 2.52, 1.76), BONE, nil, 0.05)
			r:Box("Tail", "TailSpineA", V3(0.08, 0.14, 0.1), V3(0, 2.68, 1.76), BONE_HI)
			r:Round("Tail2", "TailBoneB", V3(0.22, 0.2, 0.22), V3(0, 2.62, 2.0), BONE_LO, nil, 0.04)
			r:Box("Tail2", "TailSpineB", V3(0.07, 0.12, 0.08), V3(0, 2.76, 2.0), BONE_HI)
			r:Round("TailTip", "TailBoneC", V3(0.18, 0.18, 0.2), V3(0, 2.72, 2.22), BONE, nil, 0.04)
			r:Box("TailTip", "TailBoneD", V3(0.12, 0.12, 0.14), V3(0, 2.8, 2.4), BONE_HI)
			-------- ability FX hooks (BONE HOARD): soul fire licking out of the ribs
			r:Hook(soul, "Soul", "Soul", V3(0, 2.1, -0.42), SOUL, SOUL_HOT, 5, 1)
		end,
	}
end

---------------------------------------------------------------- H04 FRANKENPUG (Legendary)
do
	local SKIN, SKIN_LO, SKIN_HI = C(124, 176, 100), C(92, 140, 78), C(150, 200, 122)
	local PATCH_TAN, PATCH_GREY = C(204, 168, 118), C(140, 162, 140)
	local MUZZLE, STITCH, HAIR = C(40, 36, 44), C(34, 26, 34), C(34, 46, 36)
	local METAL, METAL_HI, RUST, COPPER = C(150, 152, 164), C(200, 204, 214), C(138, 82, 48), C(200, 116, 62)
	local SPARK, SPARK2, SPARK_HOT = C(170, 230, 255), C(120, 255, 110), C(240, 255, 255)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.05, 0.3) },
		{ "Coil", "Body", V3(0, 2.95, 0.6) },
		{ "Arc", "Coil", V3(0, 4.3, 0.6) },
		{ "Neck", "Body", V3(0, 2.6, -0.95) },
		{ "Spark_L", "Neck", V3(1.42, 2.72, -1.0) },
		{ "Spark_R", "Neck", V3(-1.42, 2.72, -1.0) },
		{ "Head", "Neck", V3(0, 2.85, -1.4) },
		{ "Hair", "Head", V3(0, 4.35, -1.85) },
		{ "Jaw", "Head", V3(0, 2.72, -2.55) },
		{ "Ear_L", "Head", V3(0.82, 4.28, -1.6) },
		{ "Ear_R", "Head", V3(-0.82, 4.28, -1.6) },
		{ "Tail", "Body", V3(0, 2.5, 1.6) },
		{ "Tail2", "Tail", V3(0, 2.88, 1.84) },
		{ "TailTip", "Tail2", V3(0, 3.12, 1.66) },
	}
	legBones(bones, 0.66, -0.55, 1.15, 1.42, 0.38, -0.06)
	-- arcs: on at rest, "off" = sunk into the battery / the bolt (the flicker of a spark gap)
	local function arc(x: number, k: number, ph: number, duty: number): number
		local v = 0.5 + 0.5 * math.sin(TAU * (k * x + ph)) * math.sin(TAU * ((2 * k - 1) * x + ph * 2))
		return v < duty and 1 or 0
	end
	SPECS.HW_Frankenpug = {
		Code = "H04",
		SignatureName = "Zap",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.2 },
		Motion = { Breath = 0.06, Wag = 0.45, Stride = 0.42, Hop = 0.45, Look = 0.16 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- sparks crackle around the neck bolts all the time (fast jitter from summed sines)
			local fast = clip == "Idle" and 16 or clip == "Sleep" and 4 or looped and 5 or 8
			add("Spark_L", 0, 0, 0, 0.5 * sinU(x, fast), 0.7 * sinU(x, fast + 3, 0.3), 0.4 * sinU(x, fast * 2 - 1))
			add("Spark_R", 0, 0, 0, 0.5 * sinU(x, fast + 1, 0.5), 0.7 * sinU(x, fast + 2), 0.4 * sinU(x, fast * 2, 0.2))
			-- the tesla arc between the coils flickers (sinks into the battery when off)
			local duty = clip == "Sleep" and 0.15 or clip == "Signature" and 0.85 or 0.45
			local off = 1 - arc(x, looped and 9 or 7, 0.13, duty)
			add("Arc", 0, -1.2 * off, 0, 0, TAU * 0.5 * arc(x, looped and 4 or 3, 0.37, 0.5), 0)
			if clip == "Idle" then
				-- a jolt: the whole pug shudders for a moment, its hair stands up
				local jolt = bump(u, 0.7, 0.82)
				add("Body", 0, 0.06 * jolt, 0, 0, 0, 0.06 * math.sin(TAU * 40 * u) * jolt)
				add("Head", 0, 0, 0, 0.1 * jolt, 0, 0.12 * math.sin(TAU * 36 * u) * jolt)
				add("Hair", 0, 0.12 * jolt, 0, 0, 0, 0)
				add("Coil", 0, 0.05 * jolt, 0, 0, 0, 0)
				add("Ear_L", 0, 0, 0, 0, 0, -0.4 * jolt)
				add("Ear_R", 0, 0, 0, 0, 0, 0.4 * jolt)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local zap = bump(t, 0.15, math.min(d, 1.0))
				add("Spark_L", 0, 0.15 * zap, 0, 0, TAU * 2 * rise(t, 0.1, 1.0), 0)
				add("Spark_R", 0, 0.15 * zap, 0, 0, -TAU * 2 * rise(t, 0.1, 1.0), 0)
				add("Coil", 0, 0.12 * zap, 0, 0, 0, 0.1 * math.sin(TAU * 12 * t / d) * zap)
				add("Hair", 0, 0.2 * zap, 0, 0, 0, 0.1 * math.sin(TAU * 9 * t / d) * zap)
				add("Head", 0, 0, 0, 0, 0, 0.1 * math.sin(TAU * 10 * t / d) * zap)
			elseif clip == "Signature" then
				-- ZAP: the coils charge, a jolt throws every limb out, hair stands on end, then a dizzy happy shake
				local charge = rise(t, 0.1, 0.9)
				local shock = bump(t, 0.9, 1.9)
				local fizz = math.sin(TAU * 31 * t) * shock
				add("Coil", 0, 0.05 * charge * (1 - shock) + 0.2 * shock, 0, 0.06 * fizz, 0, 0.08 * fizz)
				add("Body", 0, 0.45 * shock, 0, 0.05 * fizz, 0, 0.08 * fizz)
				for _, l in ipairs(LEG_TAGS) do
					add("Leg_" .. l[1], 0, 0, 0, (l[3] and 0.5 or -0.5) * shock, 0, l[2] * 0.45 * shock)
				end
				add("Hair", 0, 0.35 * shock, 0, 0.1 * fizz, 0, 0.12 * fizz)
				add("Ear_L", 0, 0, 0, 0.3 * shock, 0, -0.8 * shock)
				add("Ear_R", 0, 0, 0, 0.3 * shock, 0, 0.8 * shock)
				add("Jaw", 0, 0, 0, -0.4 * shock, 0, 0)
				add("Spark_L", 0, 0.2 * shock, 0, 0, TAU * 3 * rise(t, 0.8, 2.0), 0)
				add("Spark_R", 0, 0.2 * shock, 0, 0, -TAU * 3 * rise(t, 0.8, 2.0), 0)
				local dizzy = bump(t, 1.9, d)
				add("Head", 0, 0, 0, 0.1 * dizzy, 0.25 * math.sin(TAU * 2.5 * t) * dizzy, 0.18 * math.sin(TAU * 2.5 * t + 1.2) * dizzy)
				tail(add, 0.3 * dizzy, 0.7 * dizzy, t / d, 8)
			end
		end,
		Build = function(r)
			-------- stocky stitched body: patchwork skin, seams with cross stitches, a stapled scar
			r:Round("Body", "Torso", V3(2.1, 1.5, 2.5), V3(0, 2.05, 0.3), SKIN, nil, 0.26, SKIN_HI)
			r:Round("Body", "Chest", V3(1.84, 1.3, 0.4), V3(0, 2.0, -0.98), SKIN_HI, nil, 0.14)
			r:Box("Body", "Belly", V3(1.5, 0.1, 1.9), V3(0, 1.28, 0.3), SKIN_HI)
			r:Box("Body", "SeamRing", V3(2.14, 1.0, 0.07), V3(0, 2.05, -0.45), STITCH)
			r:Box("Body", "SeamRingTop", V3(1.6, 0.07, 0.07), V3(0, 2.805, -0.45), STITCH)
			for i = 0, 5 do
				r:Box("Body", "SeamTick" .. i, V3(0.05, 0.05, 0.24), V3(-0.75 + i * 0.3, 2.81, -0.45), STITCH)
			end
			r:Box("Body", "BackSeam", V3(0.06, 0.06, 1.5), V3(-0.45, 2.81, 0.95), STITCH)
			for i = 0, 3 do
				r:Box("Body", "BackTick" .. i, V3(0.22, 0.05, 0.05), V3(-0.45, 2.815, 0.4 + i * 0.36), STITCH)
			end
			-- patchwork: a tan patch (left) and a grey patch (right), stitched in
			r:Box("Body", "PatchTan", V3(0.06, 0.8, 0.9), V3(1.04, 2.05, 0.75), PATCH_TAN)
			r:Box("Body", "PatchTanSpot", V3(0.07, 0.24, 0.3), V3(1.045, 2.2, 0.95), C(150, 110, 70))
			r:Box("Body", "PatchGrey", V3(0.06, 0.7, 0.8), V3(-1.04, 1.95, 0.85), PATCH_GREY)
			for _, sd in ipairs({ { 1, 0.75, 0.8, 0.9 }, { -1, 0.85, 0.7, 0.8 } }) do
				local sx, z, h, w = sd[1], sd[2], sd[3], sd[4]
				local y = sx > 0 and 2.05 or 1.95
				r:Box("Body", "PatchEdgeT" .. sx, V3(0.08, 0.05, w + 0.04), V3(sx * 1.05, y + h / 2, z), STITCH)
				r:Box("Body", "PatchEdgeB" .. sx, V3(0.08, 0.05, w + 0.04), V3(sx * 1.05, y - h / 2, z), STITCH)
				r:Box("Body", "PatchEdgeF" .. sx, V3(0.08, h, 0.05), V3(sx * 1.05, y, z - w / 2), STITCH)
				r:Box("Body", "PatchEdgeK" .. sx, V3(0.08, h, 0.05), V3(sx * 1.05, y, z + w / 2), STITCH)
				for i = 0, 2 do
					r:Box("Body", "PatchTick" .. sx .. i, V3(0.08, 0.18, 0.04), V3(sx * 1.06, y + h / 2, z - w / 3 + i * w / 3), STITCH)
				end
			end
			-- a stapled scar on the left shoulder
			r:Box("Body", "Scar", V3(0.05, 0.08, 0.7), CF(1.055, 2.35, -0.35) * ANG(0.35, 0, 0), C(96, 54, 56))
			for i = 0, 2 do
				r:Box("Body", "Staple" .. i, V3(0.06, 0.22, 0.05), CF(1.07, 2.35 + (i - 1) * 0.11, -0.35 + (i - 1) * 0.22) * ANG(0.35, 0, 0), METAL_HI, MAT.Metal)
			end
			-------- harness, battery pack and two tesla coils on the back (Coil bone hops when it zaps)
			r:Pair(function(s, side)
				r:Box("Body", "Strap_" .. side, V3(0.06, 1.3, 0.16), V3(s * 1.07, 2.2, 0.6), C(70, 52, 40))
				r:Box("Body", "StrapBuckle_" .. side, V3(0.08, 0.22, 0.22), V3(s * 1.1, 2.3, 0.6), METAL, MAT.Metal)
				-- cables from the battery to the neck bolts
				r:Seg("Body", "Cable_" .. side, V3(s * 0.4, 2.95, 0.25), V3(s * 0.9, 2.82, -0.7), 0.08, 0.08, s > 0 and C(200, 40, 40) or C(30, 30, 34))
			end)
			r:Box("Body", "StrapBelly", V3(1.6, 0.06, 0.16), V3(0, 1.26, 0.6), C(70, 52, 40))
			local battery = r:Round("Coil", "Battery", V3(1.0, 0.44, 0.9), V3(0, 3.06, 0.6), C(62, 66, 76), MAT.Metal, 0.08)
			r:Box("Coil", "HazardA", V3(1.02, 0.1, 0.2), V3(0, 3.06, 0.3), C(255, 200, 40))
			r:Box("Coil", "HazardB", V3(1.02, 0.1, 0.2), V3(0, 3.06, 0.9), C(255, 200, 40))
			r:Pair(function(s, side)
				r:Box("Coil", "Gauge_" .. side, V3(0.04, 0.2, 0.42), V3(s * 0.51, 3.07, 0.6), C(20, 24, 22))
				r:Neon("Coil", "GaugeGlow_" .. side, V3(0.04, 0.12, 0.3), V3(s * 0.525, 3.07, 0.56), SPARK2)
			end)
			r:Box("Coil", "TerminalA", V3(0.14, 0.16, 0.14), V3(0.36, 3.34, 0.6), C(220, 50, 50))
			r:Box("Coil", "TerminalB", V3(0.14, 0.16, 0.14), V3(-0.36, 3.34, 0.6), C(40, 40, 44))
			local coilTop = nil
			for i, z in ipairs({ 0.32, 0.88 }) do
				r:Box("Coil", "CoilFoot" .. i, V3(0.36, 0.1, 0.36), V3(0, 3.32, z), METAL, MAT.Metal)
				r:Box("Coil", "CoilRod" .. i, V3(0.12, 0.86, 0.12), V3(0, 3.76, z), METAL, MAT.Metal)
				for j = 0, 3 do
					r:Cyl("Coil", "Winding" .. i .. j, 0.1, 0.42 - j * 0.05, CF(0, 3.44 + j * 0.13, z) * ANG(0, 0, PI / 2), j % 2 == 0 and COPPER or C(170, 90, 46), MAT.Metal)
				end
				r:Cyl("Coil", "Torus" .. i, 0.1, 0.44, CF(0, 4.1, z) * ANG(0, 0, PI / 2), METAL_HI, MAT.Metal)
				local top = r:Ball("Coil", "CoilBall" .. i, 0.28, V3(0, 4.2, z), METAL_HI, MAT.Metal)
				coilTop = coilTop or top
			end
			r:Light(coilTop, C(150, 255, 210), 6, 0.9)
			-- the arc between the coil tops (Arc bone: flickers)
			local zig = { V3(0, 4.24, 0.38), V3(0.1, 4.44, 0.48), V3(-0.08, 4.34, 0.6), V3(0.06, 4.46, 0.72), V3(0, 4.24, 0.82) }
			for i = 1, #zig - 1 do
				r:Seg("Arc", "Arc" .. i, zig[i], zig[i + 1], 0.05, 0.05, i % 2 == 0 and SPARK_HOT or SPARK2, MAT.Neon)
			end
			-------- legs (front-left is a borrowed tan leg, stitched on; hind-right wears a metal brace)
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.66, front and -0.55 or 1.15
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				local col = tag == "FL" and PATCH_TAN or SKIN
				r:Round(leg, "Leg_" .. tag, V3(0.62, 1.04, 0.64), V3(x, 0.92, z), col, nil, 0.1)
				r:Round(leg, "Upper_" .. tag, V3(0.7, 0.5, 0.74), V3(x, 1.4, z + (front and 0 or 0.04)), col, nil, 0.14, tag == "FL" and C(220, 186, 138) or SKIN_HI)
				r:Paw(paw, tag, x, z - 0.06, 0.72, 0.74, 0.38, tag == "FL" and C(176, 140, 96) or SKIN_LO, { Toe = tag == "FL" and C(190, 154, 108) or SKIN_LO, Nail = STITCH })
			end
			r:Box("Leg_FL", "LegSeam_FL", V3(0.66, 0.07, 0.68), V3(0.66, 1.18, -0.55), STITCH)
			for i = 0, 2 do
				r:Box("Leg_FL", "LegTick" .. i, V3(0.05, 0.2, 0.05), V3(0.43 + i * 0.23, 1.18, -0.89), STITCH)
			end
			for i, y in ipairs({ 0.62, 1.02 }) do
				r:Box("Leg_BR", "Brace" .. i, V3(0.68, 0.1, 0.7), V3(-0.66, y, 1.15), METAL, MAT.Metal)
				r:Box("Leg_BR", "BraceRivet" .. i, V3(0.06, 0.06, 0.06), V3(-1.0, y, 1.15), METAL_HI, MAT.Metal)
			end
			r:Box("Leg_BR", "BraceBar", V3(0.06, 0.5, 0.08), V3(-1.0, 0.82, 1.15), METAL, MAT.Metal)
			-------- neck: stitched collar seam, iron bolts with hex nuts and crackling sparks
			r:Round("Neck", "Neck", V3(1.32, 0.82, 0.94), V3(0, 2.72, -1.05), SKIN, nil, 0.14)
			r:Box("Neck", "NeckSeam", V3(1.36, 0.07, 0.96), V3(0, 2.6, -1.05), STITCH)
			for i = 0, 3 do
				r:Box("Neck", "NeckTick" .. i, V3(0.05, 0.2, 0.05), V3(-0.45 + i * 0.3, 2.6, -1.53), STITCH)
			end
			r:Pair(function(s, side)
				r:Cyl("Neck", "Washer_" .. side, 0.06, 0.52, CF(s * 0.68, 2.72, -1.0), RUST, MAT.CorrodedMetal)
				r:Cyl("Neck", "Bolt_" .. side, 0.66, 0.26, CF(s * 1.0, 2.72, -1.0), METAL, MAT.Metal)
				r:Box("Neck", "Nut_" .. side, V3(0.18, 0.4, 0.4), V3(s * 1.33, 2.72, -1.0), METAL, MAT.DiamondPlate)
				r:Box("Neck", "NutB_" .. side, V3(0.18, 0.4, 0.4), CF(s * 1.33, 2.72, -1.0) * ANG(PI / 4, 0, 0), METAL, MAT.DiamondPlate)
				r:Box("Neck", "NutRust_" .. side, V3(0.19, 0.1, 0.3), V3(s * 1.33, 2.55, -1.0), RUST, MAT.CorrodedMetal)
				r:Cyl("Neck", "BoltTip_" .. side, 0.1, 0.18, CF(s * 1.47, 2.72, -1.0), METAL_HI, MAT.Metal)
				local bone = "Spark_" .. side
				r:Seg(bone, "SparkA_" .. side, V3(s * 1.5, 2.8, -1.0), V3(s * 1.62, 3.05, -1.04), 0.05, 0.05, SPARK, MAT.Neon)
				r:Seg(bone, "SparkA2_" .. side, V3(s * 1.62, 3.05, -1.04), V3(s * 1.55, 3.25, -0.96), 0.05, 0.05, SPARK_HOT, MAT.Neon)
				r:Seg(bone, "SparkB_" .. side, V3(s * 1.52, 2.62, -1.02), V3(s * 1.7, 2.5, -0.9), 0.05, 0.05, SPARK, MAT.Neon)
				r:Seg(bone, "SparkB2_" .. side, V3(s * 1.7, 2.5, -0.9), V3(s * 1.66, 2.32, -1.05), 0.05, 0.05, SPARK2, MAT.Neon)
				r:Seg(bone, "SparkC_" .. side, V3(s * 1.55, 2.76, -1.1), V3(s * 1.74, 2.86, -1.28), 0.04, 0.04, SPARK_HOT, MAT.Neon)
			end)
			-------- the head: round pug skull, flat-top hair with a white lightning streak, forehead scar and wrinkles
			r:Round("Head", "Head", V3(1.94, 1.72, 1.6), V3(0, 3.5, -1.85), SKIN, nil, 0.3, SKIN_HI)
			r:Round("Head", "Cheeks", V3(2.06, 0.9, 1.2), V3(0, 3.12, -2.0), SKIN, nil, 0.22)
			r:Round("Head", "BrowRidge", V3(1.76, 0.24, 0.22), V3(0, 4.0, -2.6), SKIN_HI, nil, 0.06)
			r:Round("Head", "NoseRoll", V3(0.9, 0.16, 0.16), V3(0, 3.44, -2.8), SKIN_HI, nil, 0.05)
			r:Round("Hair", "Hair", V3(2.1, 0.36, 1.72), V3(0, 4.5, -1.85), HAIR, nil, 0.08, C(48, 62, 50))
			r:Box("Hair", "HairBack", V3(2.04, 0.5, 0.16), V3(0, 4.16, -1.0), HAIR)
			r:Box("Hair", "Streak", V3(0.24, 0.05, 1.5), CF(0.42, 4.69, -1.85) * ANG(0, 0.2, 0), C(236, 240, 236))
			r:Box("Hair", "StreakB", V3(0.24, 0.05, 0.5), CF(0.62, 4.69, -2.35) * ANG(0, -0.6, 0), C(236, 240, 236))
			for i, h in ipairs({ 0.3, 0.22, 0.38, 0.26, 0.32 }) do
				r:Box("Hair", "Fringe" .. i, V3(0.4, h, 0.14), V3(-0.8 + (i - 1) * 0.4, 4.36 - h / 2 + 0.06, -2.68), HAIR)
			end
			r:Box("Head", "Scar", V3(1.3, 0.08, 0.04), CF(0.1, 4.0, -2.725) * ANG(0, 0, 0.12), C(96, 52, 54))
			for i = 0, 4 do
				r:Box("Head", "ScarStitch" .. i, V3(0.05, 0.24, 0.04), CF(-0.42 + i * 0.26, 4.0 + (-0.52 + i * 0.26) * 0.12, -2.74) * ANG(0, 0, 0.12), STITCH)
			end
			r:Box("Head", "WrinkleA", V3(0.5, 0.06, 0.04), V3(0, 4.2, -2.655), SKIN_LO)
			r:Box("Head", "WrinkleB", V3(0.3, 0.06, 0.04), CF(0.2, 3.52, -2.655) * ANG(0, 0, 0.5), SKIN_LO)
			r:Box("Head", "WrinkleC", V3(0.3, 0.06, 0.04), CF(-0.2, 3.52, -2.655) * ANG(0, 0, -0.5), SKIN_LO)
			-- mismatched eyes: a big glaring yellow one and a small red one under a droopy lid
			r:Eye("Head", "EyeL", V3(0.5, 3.66, -2.65), 0.58, 0.58, { Rim = SKIN_LO, White = C(255, 248, 214), Iris = C(255, 206, 40), Glow = true, Look = V3(0.03, 0, 0) })
			r:Eye("Head", "EyeR", V3(-0.52, 3.6, -2.65), 0.4, 0.36, { Rim = SKIN_LO, White = C(255, 236, 222), Iris = C(255, 56, 56), Glow = true, IrisK = 0.6, Lid = SKIN_LO })
			r:Box("Head", "BrowL", V3(0.6, 0.12, 0.08), CF(0.5, 4.02, -2.67) * ANG(0, 0, -0.18), HAIR)
			-------- pug face: black muzzle, jowls, nose, underbite with a fang, tongue
			r:Round("Head", "Muzzle", V3(1.1, 0.7, 0.36), V3(0, 3.0, -2.78), MUZZLE, nil, 0.1)
			r:Round("Head", "Nose", V3(0.46, 0.26, 0.16), V3(0, 3.3, -2.98), C(16, 14, 18), nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.1, 0.05, 0.03), V3(0.1, 3.38, -3.065), C(170, 170, 180))
			r:Box("Head", "NostrilL", V3(0.08, 0.06, 0.03), V3(0.1, 3.26, -3.065), C(60, 60, 66))
			r:Box("Head", "NostrilR", V3(0.08, 0.06, 0.03), V3(-0.1, 3.26, -3.065), C(60, 60, 66))
			r:Box("Head", "MouthLine", V3(0.6, 0.04, 0.03), V3(0, 2.86, -2.97), C(14, 12, 16))
			r:Pair(function(s, side)
				r:Round("Head", "Jowl_" .. side, V3(0.34, 0.5, 0.42), V3(s * 0.62, 2.95, -2.68), SKIN_LO, nil, 0.08)
				local bone = "Ear_" .. side
				r:Round(bone, "EarTop_" .. side, V3(0.52, 0.14, 0.52), V3(s * 0.82, 4.36, -1.85), MUZZLE, nil, 0.04)
				r:Round(bone, "EarFlap_" .. side, V3(0.52, 0.4, 0.14), V3(s * 0.82, 4.22, -2.12), MUZZLE, nil, 0.04)
			end)
			r:Round("Jaw", "Jaw", V3(1.0, 0.24, 0.4), V3(0, 2.6, -2.74), MUZZLE, nil, 0.06)
			r:Box("Jaw", "Tongue", V3(0.3, 0.1, 0.36), CF(0.18, 2.55, -2.97) * ANG(-0.5, 0, 0), C(236, 106, 120))
			r:Box("Jaw", "Fang", V3(0.08, 0.16, 0.06), V3(-0.3, 2.8, -2.93), C(250, 248, 240))
			r:Box("Jaw", "FangB", V3(0.07, 0.12, 0.06), V3(0.26, 2.78, -2.93), C(250, 248, 240))
			-------- corkscrew tail with a stitch (three bones)
			r:Round("Tail", "TailA", V3(0.34, 0.34, 0.44), V3(0, 2.66, 1.72), SKIN, nil, 0.06)
			r:Round("Tail2", "TailB", V3(0.34, 0.44, 0.34), V3(0, 2.98, 1.86), SKIN, nil, 0.06)
			r:Box("Tail2", "TailStitch", V3(0.38, 0.05, 0.05), V3(0, 2.9, 2.03), STITCH)
			r:Round("TailTip", "TailC", V3(0.3, 0.3, 0.38), V3(0, 3.2, 1.72), SKIN, nil, 0.06)
			r:Round("TailTip", "TailD", V3(0.26, 0.26, 0.26), V3(0, 3.04, 1.52), SKIN_LO, nil, 0.05)
			-------- ability FX hooks (OVERCHARGE): sparks off both bolts and the coil tops
			r:Light(r.Model:FindFirstChild("Bolt_L"), C(170, 230, 255), 7, 0.7)
			local bl = r.Model:FindFirstChild("BoltTip_L")
			local br = r.Model:FindFirstChild("BoltTip_R")
			r:Hook(bl, "Spark_L", "Sparks", V3(1.52, 2.72, -1.0), SPARK, SPARK_HOT, 8, 0)
			r:Hook(br, "Spark_R", "Sparks", V3(-1.52, 2.72, -1.0), SPARK, SPARK_HOT, 8, 0)
			r:Hook(coilTop, "Coil", "Sparks", V3(0, 4.3, 0.32), SPARK2, SPARK_HOT, 6, 1.2)
			local _ = battery
		end,
	}
end

---------------------------------------------------------------- H05 BAT DACHSHUND (Legendary)
do
	local FUR, FUR_HI, FUR_LO, TAN, TAN_LO = C(62, 48, 80), C(84, 66, 104), C(42, 32, 58), C(204, 142, 90), C(162, 106, 66)
	local MEMBRANE, MEMBRANE_HI, STRUT, EDGE = C(112, 52, 140), C(140, 74, 170), C(36, 24, 48), C(190, 110, 255)
	local CAPE, LINING, GOLD, EYE = C(30, 22, 38), C(184, 26, 48), C(255, 200, 70), C(255, 60, 84)
	local SWEEP, W = 0.35, 1.12
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 1.75, 0.3) },
		{ "Cape", "Body", V3(0, 2.4, -1.0) },
		{ "Wing_L", "Body", V3(0.7, 2.3, -0.75) },
		{ "WingTip_L", "Wing_L", V3(0.7, 2.3, -0.75) },
		{ "Wing_R", "Body", V3(-0.7, 2.3, -0.75) },
		{ "WingTip_R", "Wing_R", V3(-0.7, 2.3, -0.75) },
		{ "Neck", "Body", V3(0, 2.15, -1.6) },
		{ "Head", "Neck", V3(0, 2.45, -2.05) },
		{ "Jaw", "Head", V3(0, 2.25, -2.95) },
		{ "Ear_L", "Head", V3(0.45, 3.25, -2.2) },
		{ "Ear_R", "Head", V3(-0.45, 3.25, -2.2) },
		{ "Tail", "Body", V3(0, 2.0, 2.3) },
		{ "Tail2", "Tail", V3(0, 2.32, 2.72) },
		{ "TailTip", "Tail2", V3(0, 2.52, 3.05) },
	}
	legBones(bones, 0.48, -1.15, 1.75, 1.2, 0.32, -0.06)
	-- the wing in its own plane (u outward from the shoulder, v up), in units of W
	local WRIST, BODYPT = { 1.3, 0.85 }, { 0.1, -0.55 }
	local TIPS = { { 2.55, 1.4 }, { 2.5, 0.55 }, { 2.0, -0.18 }, { 1.25, -0.5 } }
	SPECS.HW_BatDachshund = {
		Code = "H05",
		SignatureName = "WingHover",
		Bones = bones,
		Durations = { Signature = 3.4 },
		Motion = { Breath = 0.04, Wag = 0.4, Stride = 0.5, Hop = 0.5, Look = 0.2 },
		Extra = function(clip, t, d, u, add)
			-- wings flap about the shoulder (roll) and fold at the wrist
			local flap, fold = 0, 0
			if clip == "Idle" then
				local beat = bump(u, 0.35, 0.65)
				flap = 0.12 * sinU(u, 1) + 0.55 * beat * math.sin(TAU * 3 * (u - 0.35) / 0.3)
				fold = -0.15 + 0.25 * beat
			elseif clip == "Walk" then
				flap = 0.45 * sinU(u, 2)
				fold = 0.15 * sinU(u, 2, -0.1)
			elseif clip == "Run" then
				flap = 0.7 * sinU(u, 2)
				fold = 0.25 * sinU(u, 2, -0.12)
			elseif clip == "DigLoop" then
				flap = 0.35 + 0.08 * sinU(u, 2)
				fold = -0.45
			elseif clip == "Sleep" then
				-- wrapped round itself like a roosting bat
				flap = -0.55 + 0.03 * sinU(u, 1)
				fold = -0.9
			elseif clip == "Sniff" then
				flap = 0.2 * bump(t, 0.2, d - 0.2)
				fold = -0.3 * bump(t, 0.2, d - 0.2)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local fly = bump(t, 0.05, d - 0.1)
				flap = 0.75 * math.sin(TAU * (clip == "DigFind" and 5 or 6) * t / d) * fly
				fold = 0.2 * math.sin(TAU * 5 * t / d - 0.5) * fly
				add("Root", 0, (clip == "DigFind" and 0.35 or 0.7) * fly, 0, 0, 0, 0)
			elseif clip == "Signature" then
				-- WING HOVER: big beats lift the long dog off the ground; it hovers with dangling paws, loops once, lands
				local fly = hold(t, 0.25, 0.8, d - 0.7, d - 0.1)
				local k = 7 / d
				flap = (0.85 * math.sin(TAU * k * t) + 0.1) * hold(t, 0.05, 0.3, d - 0.4, d)
				fold = 0.3 * math.sin(TAU * k * t - 0.6) * fly
				local loop = rise(t, 1.4, 2.3)
				add("Root", 0, 1.4 * fly + 0.12 * math.sin(TAU * k * t + 0.8) * fly, 0, TAU * loop * fly, 0, 0)
				for _, l in ipairs(LEG_TAGS) do
					add("Leg_" .. l[1], 0, 0, 0, (l[3] and -0.35 or 0.45) * fly, 0, 0)
					add("Paw_" .. l[1], 0, 0, 0, 0.3 * fly, 0, 0)
				end
				add("Ear_L", 0, 0, 0, 0.3 * fly, 0, -0.3 * fly)
				add("Ear_R", 0, 0, 0, 0.3 * fly, 0, 0.3 * fly)
				add("Jaw", 0, 0, 0, -0.3 * bump(t, 1.2, 2.5), 0, 0)
				tail(add, -0.3 * fly, 0.3 * fly, t / d, 5)
			end
			add("Wing_L", 0, 0, 0, 0, 0, -flap)
			add("Wing_R", 0, 0, 0, 0, 0, flap)
			add("WingTip_L", 0, 0, 0, 0, fold, -fold * 0.5)
			add("WingTip_R", 0, 0, 0, 0, -fold, fold * 0.5)
			local looped = E.IsLooped(clip)
			local sway = clip == "Walk" and sinU(u, 2, 0.2) or clip == "Run" and sinU(u, 2, 0.2) * 1.6 or clip == "Idle" and sinU(u, 1) or 0
			add("Cape", 0, 0, 0, 0.1 * sway + ((not looped) and 0.25 * bump(t, 0, d) or 0), 0, 0)
		end,
		Build = function(r)
			-------- the long low black-and-tan sausage body, tan points, a glowing ridge down the spine
			local torso = r:Round("Body", "Torso", V3(1.48, 1.18, 4.0), V3(0, 1.75, 0.3), FUR, nil, 0.28, FUR_HI)
			r:Box("Body", "Belly", V3(1.04, 0.1, 3.4), V3(0, 1.17, 0.3), C(84, 66, 100))
			r:Round("Body", "Chest", V3(1.24, 1.0, 0.3), V3(0, 1.7, -1.78), TAN, nil, 0.1)
			r:Box("Body", "ChestBib", V3(0.7, 0.4, 0.06), V3(0, 1.45, -1.95), TAN_LO)
			r:Round("Body", "Rump", V3(1.3, 1.02, 0.3), V3(0, 1.76, 2.3), FUR, nil, 0.12)
			r:Box("Body", "UnderTail", V3(0.5, 0.3, 0.06), V3(0, 1.6, 2.46), TAN)
			r:Pair(function(s, side)
				r:Box("Body", "Flank_" .. side, V3(0.06, 0.6, 3.1), V3(s * 0.74, 1.62, 0.45), FUR_LO)
				r:Box("Body", "FlankHi_" .. side, V3(0.06, 0.1, 3.0), V3(s * 0.745, 2.02, 0.4), FUR_HI)
			end)
			r:Neon("Body", "SpineGlow", V3(0.06, 0.05, 2.6), V3(0, 2.355, 0.75), EDGE, { Transparency = 0.15 })
			for i = 0, 3 do
				r:Box("Body", "SpineTuft" .. i, V3(0.16, 0.12, 0.2), V3(0, 2.38, 0.0 + i * 0.6), FUR_HI)
			end
			-------- short legs with tan points and claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.48, front and -1.15 or 1.75
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.48, 0.86, 0.5), V3(x, 0.84, z), FUR, nil, 0.09)
				r:Round(leg, "Upper_" .. tag, V3(0.56, 0.46, 0.66), V3(x, 1.26, z), FUR, nil, 0.12, FUR_HI)
				r:Box(leg, "Sock_" .. tag, V3(0.5, 0.22, 0.52), V3(x, 0.48, z), TAN)
				r:Paw(paw, tag, x, z - 0.06, 0.58, 0.66, 0.32, TAN, { Toe = TAN, Nail = C(236, 230, 218) })
			end
			-------- neck + head: long snout, tan brows and cheeks, glowing red eyes, fangs, bat nose
			r:Round("Neck", "Neck", V3(0.92, 0.84, 0.86), CF(0, 2.25, -1.85) * ANG(0.3, 0, 0), FUR, nil, 0.14)
			r:Round("Head", "Head", V3(1.26, 1.1, 1.3), V3(0, 2.75, -2.45), FUR, nil, 0.22, FUR_HI)
			r:Round("Head", "Snout", V3(0.78, 0.56, 1.06), V3(0, 2.53, -3.55), FUR, nil, 0.12, FUR_HI)
			r:Round("Head", "SnoutTan", V3(0.82, 0.28, 0.96), V3(0, 2.37, -3.5), TAN, nil, 0.06)
			r:Round("Head", "Nose", V3(0.38, 0.28, 0.2), V3(0, 2.74, -4.1), C(64, 36, 58), nil, 0.06)
			r:Box("Head", "NostrilL", V3(0.07, 0.08, 0.03), V3(0.08, 2.72, -4.21), C(24, 12, 22))
			r:Box("Head", "NostrilR", V3(0.07, 0.08, 0.03), V3(-0.08, 2.72, -4.21), C(24, 12, 22))
			r:Box("Head", "NoseShine", V3(0.1, 0.05, 0.03), V3(0.08, 2.84, -4.2), C(220, 170, 210))
			r:Box("Head", "MouthLine", V3(0.04, 0.12, 0.03), V3(0, 2.5, -4.09), C(20, 12, 24))
			r:Pair(function(s, side)
				r:Box("Head", "Brow_" .. side, V3(0.24, 0.12, 0.06), V3(s * 0.38, 3.16, -3.12), TAN)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.36, 2.92, -3.1), 0.3, 0.24, { Rim = C(14, 8, 18), White = C(255, 214, 220), Iris = EYE, Glow = true, IrisK = 0.72 })
				r:Round("Head", "Cheek_" .. side, V3(0.12, 0.32, 0.52), V3(s * 0.64, 2.55, -2.95), TAN, nil, 0.04)
				r:Tri("Head", "Fang_" .. side, V3(s * 0.24, 2.13, -3.98), 0.14, 0.26, 0.08, C(252, 250, 244), MAT.SmoothPlastic, true)
				-- big bat ears: pink inside with ridges, a glowing rim
				local turn = ANG(0, 0, -s * 0.28)
				local ear = "Ear_" .. side
				local base = CF(s * 0.56, 3.82, -2.22) * turn
				r:Tri(ear, "Ear_" .. side, V3(s * 0.56, 3.82, -2.22), 0.76, 1.24, 0.14, FUR, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.55, 3.74, -2.3), 0.46, 0.8, 0.04, C(170, 92, 140), MAT.SmoothPlastic, false, turn)
				r:Seg(ear, "EarRidge_" .. side, (base * CF(0, -0.38, -0.12)).Position, (base * CF(0, 0.2, -0.12)).Position, 0.04, 0.03, C(120, 60, 100))
				r:Seg(ear, "EarRimOut_" .. side, (base * CF(s * 0.36, -0.6, 0)).Position, (base * CF(0, 0.62, 0)).Position, 0.05, 0.16, EDGE, MAT.Neon)
				r:Box(ear, "EarBase_" .. side, V3(0.5, 0.18, 0.3), V3(s * 0.48, 3.26, -2.22), FUR_HI)
			end)
			r:Round("Jaw", "Jaw", V3(0.66, 0.18, 0.88), V3(0, 2.17, -3.45), TAN, nil, 0.05)
			r:Box("Jaw", "Tongue", V3(0.26, 0.05, 0.3), V3(0, 2.27, -3.62), C(220, 90, 110))
			-------- the tiny vampire cape: standing collar, red lining, scalloped hem, gold clasp with a glowing ruby
			r:Box("Cape", "CapeTop", V3(1.56, 0.1, 1.4), V3(0, 2.44, -0.38), CAPE, MAT.Fabric)
			r:Box("Cape", "CapeLining", V3(1.5, 0.04, 1.36), V3(0, 2.38, -0.38), LINING, MAT.Fabric)
			r:Pair(function(s, side)
				r:Box("Cape", "CapeSide_" .. side, V3(0.08, 0.62, 1.34), V3(s * 0.8, 2.12, -0.38), CAPE, MAT.Fabric)
				r:Box("Cape", "CapeSideLining_" .. side, V3(0.03, 0.6, 1.3), V3(s * 0.75, 2.12, -0.38), LINING, MAT.Fabric)
				for i, z in ipairs({ -0.85, -0.38, 0.09 }) do
					r:Wedge("Cape", "Scallop" .. i .. "_" .. side, V3(0.08, 0.2, 0.42), CF(s * 0.8, 1.72, z) * ANG(PI, 0, 0), CAPE, MAT.Fabric)
				end
				r:Box("Cape", "Collar_" .. side, V3(0.1, 0.66, 0.52), CF(s * 0.56, 2.74, -1.08) * ANG(0, 0, -s * 0.35), CAPE, MAT.Fabric)
				r:Box("Cape", "CollarLining_" .. side, V3(0.04, 0.62, 0.48), CF(s * 0.51, 2.72, -1.08) * ANG(0, 0, -s * 0.35), LINING, MAT.Fabric)
			end)
			r:Box("Cape", "CapeTail", V3(1.3, 0.1, 0.4), CF(0, 2.36, 0.45) * ANG(0.35, 0, 0), CAPE, MAT.Fabric)
			r:Box("Cape", "Clasp", V3(0.28, 0.28, 0.08), V3(0, 2.5, -1.22), GOLD, MAT.Metal)
			local ruby = r:Neon("Cape", "Ruby", V3(0.13, 0.13, 0.05), V3(0, 2.5, -1.27), C(255, 30, 60))
			r:Light(ruby, C(200, 70, 255), 7, 0.8)
			-------- bat wings: humerus + forearm to the wrist, four finger bones, membrane panels, glowing trailing edge
			r:Pair(function(s, side)
				local shoulder = V3(s * 0.7, 2.3, -0.75)
				local frame = CF(shoulder) * ANG(0, -s * SWEEP, 0) * ANG(0, 0, s * 0.38)
				local function P(p): Vector3
					return (frame * CF(s * p[1] * W, p[2] * W, 0)).Position
				end
				local wing, tip = "Wing_" .. side, "WingTip_" .. side
				-- a membrane triangle: apex at `a`, base from b to c (isosceles fit), in the wing plane
				local function panel(bone, name, a, b, c, color)
					local m = { (b[1] + c[1]) / 2, (b[2] + c[2]) / 2 }
					local du, dv = (a[1] - m[1]) * s, a[2] - m[2]
					local h = math.sqrt(du * du + dv * dv) * W
					local w = math.sqrt((b[1] - c[1]) ^ 2 + (b[2] - c[2]) ^ 2) * W
					local mid = { (a[1] + m[1]) / 2, (a[2] + m[2]) / 2 }
					local turn = frame.Rotation * ANG(0, 0, math.atan2(dv, du) - PI / 2)
					r:Tri(bone, name, P(mid), w, h, 0.06, color, MAT.SmoothPlastic, false, turn)
				end
				panel(tip, "MembraneA_" .. side, WRIST, TIPS[1], TIPS[2], MEMBRANE)
				panel(tip, "MembraneB_" .. side, WRIST, TIPS[2], TIPS[3], MEMBRANE_HI)
				panel(tip, "MembraneC_" .. side, WRIST, TIPS[3], TIPS[4], MEMBRANE)
				panel(wing, "MembraneD_" .. side, { 0, 0 }, WRIST, TIPS[4], MEMBRANE_HI)
				panel(wing, "MembraneE_" .. side, { 0, 0 }, TIPS[4], BODYPT, MEMBRANE)
				-- arm and finger bones with knuckles
				r:Round(wing, "WingRoot_" .. side, V3(0.4, 0.36, 0.36), shoulder, STRUT, nil, 0.08)
				r:Seg(wing, "Humerus_" .. side, P({ 0, 0 }), P({ 0.6, 0.52 }), 0.17, 0.17, STRUT)
				r:Seg(wing, "Forearm_" .. side, P({ 0.6, 0.52 }), P(WRIST), 0.15, 0.15, STRUT)
				r:Round(tip, "Wrist_" .. side, V3(0.26, 0.26, 0.2), P(WRIST), STRUT, nil, 0.05)
				r:Box(tip, "Thumb_" .. side, V3(0.1, 0.24, 0.1), (frame * CF(s * WRIST[1] * W, WRIST[2] * W + 0.2, 0) * ANG(0, 0, s * 0.4)).Position, C(226, 220, 206))
				for i, tp in ipairs(TIPS) do
					local mid = { WRIST[1] + (tp[1] - WRIST[1]) * 0.5, WRIST[2] + (tp[2] - WRIST[2]) * 0.5 }
					r:Seg(tip, "Finger" .. i .. "_" .. side, P(WRIST), P(tp), 0.09, 0.09, STRUT)
					r:Box(tip, "Knuckle" .. i .. "_" .. side, V3(0.13, 0.13, 0.13), P(mid), STRUT)
				end
				-- the glowing trailing edge between the finger tips
				for i = 1, #TIPS - 1 do
					r:Seg(tip, "Edge" .. i .. "_" .. side, P(TIPS[i]), P(TIPS[i + 1]), 0.04, 0.07, EDGE, MAT.Neon, { Transparency = 0.15 })
				end
				r:Seg(wing, "EdgeIn_" .. side, P(TIPS[4]), P(BODYPT), 0.04, 0.07, EDGE, MAT.Neon, { Transparency = 0.15 })
			end)
			-------- thin tail with a heart-arrow tuft (three bones)
			r:Seg("Tail", "TailA", V3(0, 2.02, 2.32), V3(0, 2.34, 2.74), 0.2, 0.2, FUR)
			r:Seg("Tail2", "TailB", V3(0, 2.32, 2.72), V3(0, 2.54, 3.07), 0.17, 0.17, FUR)
			r:Seg("TailTip", "TailC", V3(0, 2.52, 3.05), V3(0, 2.62, 3.3), 0.14, 0.14, FUR_LO)
			r:Tri("TailTip", "TailTuft", V3(0, 2.68, 3.42), 0.44, 0.36, 0.1, LINING, MAT.SmoothPlastic, false, ANG(PI / 2 - 0.3, 0, 0))
			r:Neon("TailTip", "TailGem", V3(0.1, 0.1, 0.1), V3(0, 2.66, 3.4), EDGE)
			-------- ability FX hooks (NIGHT FLIGHT): violet trails off both wing tips
			r:Pair(function(s, side)
				local f = r.Model:FindFirstChild("Edge1_" .. side)
				local frame = CF(V3(s * 0.7, 2.3, -0.75)) * ANG(0, -s * SWEEP, 0) * ANG(0, 0, s * 0.38)
				r:Hook(f, "Wing_" .. side, "Trail", (frame * CF(s * TIPS[1][1] * W, TIPS[1][2] * W, 0)).Position, EDGE, C(255, 120, 200), 10, 0)
			end)
			local _ = torso
		end,
	}
end

---------------------------------------------------------------- H06 PLAGUE PUG (Mythic)
do
	local FAWN, FAWN_HI, FAWN_LO, BLACK = C(216, 180, 130), C(234, 204, 160), C(178, 142, 96), C(32, 28, 32)
	local LEATHER, LEATHER_LO, LEATHER_HI = C(96, 64, 46), C(64, 42, 30), C(128, 90, 62)
	local CLOAK, CLOAK_LO, CLOAK_HI, TRIM = C(56, 48, 70), C(38, 32, 50), C(76, 66, 94), C(112, 58, 140)
	local HAT, BAND, BRASS, BRASS_HI = C(30, 28, 38), C(104, 46, 130), C(212, 168, 74), C(246, 214, 130)
	local TOXIC, TOXIC_HOT, GLASS, FOG = C(120, 255, 110), C(214, 255, 204), C(206, 240, 226), C(150, 240, 140)
	local FOGS = { V3(1.25, 0.52, -1.3), V3(-1.35, 0.52, 0.25), V3(0.95, 0.52, 1.7) }
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.0, 0.3) },
		{ "Cloak_L", "Body", V3(1.12, 2.8, 0.0) },
		{ "Cloak_R", "Body", V3(-1.12, 2.8, 0.0) },
		{ "Cloak_B", "Body", V3(0, 2.8, 1.62) },
		{ "Lantern", "Body", V3(1.42, 4.18, -0.32) },
		{ "Flame", "Lantern", V3(1.42, 3.5, -0.32) },
		{ "Neck", "Body", V3(0, 2.6, -0.95) },
		{ "Head", "Neck", V3(0, 2.85, -1.35) },
		{ "Beak", "Head", V3(0, 3.25, -2.5) },
		{ "Hat", "Head", V3(0, 4.38, -1.75) },
		{ "Tail", "Body", V3(0, 2.4, 1.72) },
		{ "Tail2", "Tail", V3(0, 2.8, 1.86) },
		{ "TailTip", "Tail2", V3(0, 2.98, 1.62) },
	}
	for i, p in ipairs(FOGS) do
		table.insert(bones, { "Fog_" .. i, "Root", p })
	end
	legBones(bones, 0.64, -0.55, 1.15, 1.4, 0.36, -0.06)
	SPECS.HW_PlaguePug = {
		Code = "H06",
		SignatureName = "CoughCloud",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.4 },
		Motion = { Breath = 0.05, Wag = 0.3, Stride = 0.4, Hop = 0.4, Look = 0.25 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the green fog rolls round the paws on slow closed loops; the lantern flame flickers
			for i = 1, #FOGS do
				local ph = (i - 1) / #FOGS
				local a = TAU * (x + ph)
				local k = clip == "Run" and 0.2 or 1
				add("Fog_" .. i, 0.35 * math.cos(a) * k, 0.08 * math.sin(2 * a), 0.35 * math.sin(a) * k, 0, a * (i % 2 == 0 and -1 or 1), 0)
			end
			add("Flame", 0, 0.03 * (flick(x, looped and 7 or 9) - 0.5), 0, 0.15 * sinU(x, 5), 0.4 * sinU(x, 3), 0.15 * sinU(x, 6, 0.2))
			local sway = clip == "Walk" and sinU(u, 2) or clip == "Run" and 1.6 * sinU(u, 2) or clip == "Idle" and sinU(u, 1) or clip == "DigLoop" and sinU(u, 2) or 0
			add("Cloak_L", 0, 0, 0, 0.05 * sway, 0, -0.06 - 0.05 * sway)
			add("Cloak_R", 0, 0, 0, -0.05 * sway, 0, 0.06 + 0.05 * sway)
			add("Cloak_B", 0, 0, 0, 0.08 + 0.06 * sway, 0, 0)
			add("Lantern", 0, 0, 0, 0.18 * sway, 0, 0.12 * (looped and sinU(u, clip == "Idle" and 1 or 2, 0.25) or 0))
			if clip == "Idle" then
				add("Beak", 0, 0, 0, 0.05 * sinU(u, 2, 0.3), 0, 0)
				add("Hat", 0, 0, 0, 0, 0.04 * sinU(u, 1), 0.03 * sinU(u, 1, 0.25))
				-- a little cough
				local c = bump(u, 0.62, 0.68) + bump(u, 0.7, 0.76)
				add("Head", 0, 0, -0.05 * c, -0.12 * c, 0, 0)
				add("Body", 0, 0, 0, -0.03 * c, 0, 0)
			elseif clip == "DigLoop" then
				add("Beak", 0, 0, 0, -0.12 + 0.08 * sinU(u, 2), 0, 0)
			elseif clip == "Sleep" then
				-- the long beak rests on its crossed paws, the hat slides over its goggles
				add("Neck", 0, 0, 0, 0.2, 0, 0)
				add("Head", 0, 0.05, 0, 0.3, 0, 0)
				add("Beak", 0, 0, 0, 0.12, 0, 0)
				add("Hat", 0, -0.08, -0.12, -0.22, 0, 0.08)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local tip = bump(t, 0.1, d - 0.15)
				add("Hat", 0, 0.45 * tip, 0, -0.25 * tip, 0, 0.2 * tip) -- tips its hat
				add("Beak", 0, 0, 0, 0.2 * tip, 0, 0)
				add("Lantern", 0, 0, 0, 0.4 * math.sin(TAU * 3 * t / d) * tip, 0, 0)
			elseif clip == "Signature" then
				-- COUGH CLOUD: three coughs, a green cloud billows out of the beak and rolls round, a bow with the hat
				local cough = 0
				for _, c0 in ipairs({ 0.3, 0.75, 1.2 }) do
					cough += bump(t, c0, c0 + 0.25)
				end
				add("Head", 0, -0.05 * cough, -0.15 * cough, -0.25 * cough, 0, 0)
				add("Neck", 0, 0, 0, -0.1 * cough, 0, 0)
				add("Body", 0, -0.04 * cough, 0, -0.05 * cough, 0, 0)
				add("Beak", 0, 0, 0, -0.15 * cough, 0, 0)
				add("Lantern", 0, 0, 0, 0.5 * math.sin(TAU * 2 * t) * bump(t, 0.2, 2.2), 0, 0.3 * math.sin(TAU * 1.5 * t) * bump(t, 0.2, 2.2))
				-- the cloud: every fog bank is blown to the front of the beak, rises and drifts back to the paws
				local blow = hold(t, 0.35, 1.3, 2.0, 2.9)
				for i, p in ipairs(FOGS) do
					local target = V3((i - 2) * 0.7, 2.6 + i * 0.25, -4.6 - (i % 2) * 0.4)
					local dv = (target - p) * blow
					add("Fog_" .. i, dv.X, dv.Y + 0.2 * math.sin(TAU * 2 * t + i) * blow, dv.Z, 0, TAU * 0.5 * blow, 0)
				end
				local bow = bump(t, 2.3, d - 0.05)
				add("Hat", 0, 0.5 * bow, -0.2 * bow, -0.35 * bow, 0, 0.25 * bow)
				add("Neck", 0, 0, 0, -0.2 * bow, 0, 0)
				tail(add, 0.3, 0.5 * bow, t / d, 6)
			end
		end,
		Build = function(r)
			-------- the pug under the cloak
			r:Round("Body", "Torso", V3(2.0, 1.45, 2.5), V3(0, 2.0, 0.3), FAWN, nil, 0.24, FAWN_HI)
			r:Box("Body", "Belly", V3(1.6, 0.1, 2.1), V3(0, 1.27, 0.3), C(236, 210, 166))
			r:Round("Body", "Chest", V3(1.6, 1.1, 0.28), V3(0, 1.95, -0.98), FAWN_HI, nil, 0.1)
			-------- cloak: shoulders, high collar, side and back drapes with ragged hems and purple trim
			r:Round("Body", "CloakTop", V3(2.32, 0.2, 2.62), V3(0, 2.84, 0.2), CLOAK, MAT.Fabric, 0.06, CLOAK_HI)
			r:Box("Body", "CloakRidge", V3(1.6, 0.12, 2.3), V3(0, 2.97, 0.25), CLOAK_LO, MAT.Fabric)
			r:Box("Body", "Collar", V3(2.0, 0.88, 0.16), V3(0, 3.2, -0.92), CLOAK, MAT.Fabric)
			r:Box("Body", "CollarTrim", V3(2.02, 0.08, 0.18), V3(0, 3.64, -0.92), TRIM, MAT.Fabric)
			r:Pair(function(s, side)
				r:Box("Body", "CollarWing_" .. side, V3(0.16, 0.88, 0.6), CF(s * 1.02, 3.2, -0.72) * ANG(0, -s * 0.5, 0), CLOAK, MAT.Fabric)
				r:Box("Body", "CollarWingTrim_" .. side, V3(0.17, 0.08, 0.6), CF(s * 1.02, 3.64, -0.72) * ANG(0, -s * 0.5, 0), TRIM, MAT.Fabric)
				local bone = "Cloak_" .. side
				r:Box(bone, "Drape_" .. side, V3(0.12, 1.1, 2.4), V3(s * 1.15, 2.25, 0.2), CLOAK, MAT.Fabric)
				r:Box(bone, "DrapeTrim_" .. side, V3(0.14, 0.08, 2.4), V3(s * 1.15, 1.73, 0.2), TRIM, MAT.Fabric)
				for i, tz in ipairs({ { -0.55, 0.3, 0.5 }, { 0.45, 0.22, 0.42 }, { 1.15, 0.34, 0.36 }, { -0.05, 0.16, 0.3 } }) do
					r:Box(bone, "DrapeTooth" .. i .. "_" .. side, V3(0.12, tz[2], tz[3]), V3(s * 1.15, 1.7 - tz[2] / 2, tz[1]), i % 2 == 0 and CLOAK_HI or CLOAK, MAT.Fabric)
				end
				r:Box(bone, "DrapeFold_" .. side, V3(0.04, 0.9, 0.08), V3(s * 1.22, 2.3, 0.6), CLOAK_LO)
				r:Box(bone, "DrapeFoldB_" .. side, V3(0.04, 0.8, 0.08), V3(s * 1.22, 2.35, -0.3), CLOAK_LO)
				r:Box(bone, "DrapeFoldHi_" .. side, V3(0.04, 0.85, 0.08), V3(s * 1.22, 2.32, 0.15), CLOAK_HI)
				r:Box(bone, "DrapePatch_" .. side, V3(0.04, 0.34, 0.4), V3(s * 1.22, 2.5, 1.05), C(74, 64, 90))
				r:Box(bone, "DrapeStitch_" .. side, V3(0.05, 0.05, 0.44), V3(s * 1.23, 2.68, 1.05), C(130, 110, 150))
			end)
			r:Box("Cloak_B", "DrapeBack", V3(2.2, 1.0, 0.12), V3(0, 2.3, 1.62), CLOAK, MAT.Fabric)
			r:Box("Cloak_B", "DrapeBackTrim", V3(2.2, 0.08, 0.14), V3(0, 1.8, 1.62), TRIM, MAT.Fabric)
			r:Box("Cloak_B", "DrapeBackTooth", V3(0.6, 0.3, 0.12), V3(0.55, 1.62, 1.62), CLOAK, MAT.Fabric)
			r:Box("Cloak_B", "DrapeBackToothB", V3(0.4, 0.2, 0.12), V3(-0.6, 1.67, 1.62), CLOAK_HI, MAT.Fabric)
			-- amulet clasp with a toxic gem
			r:Round("Body", "Clasp", V3(0.32, 0.32, 0.1), V3(0, 3.0, -1.02), BRASS, MAT.Metal, 0.05)
			r:Box("Body", "ClaspGem", V3(0.14, 0.14, 0.04), V3(0, 3.0, -1.08), TOXIC, MAT.Neon)
			-- bandolier with three potion vials across the chest
			r:Box("Body", "Bandolier", V3(0.18, 1.56, 0.08), CF(0.1, 2.05, -1.12) * ANG(0, 0, 0.6), LEATHER)
			for i, v in ipairs({ { V3(-0.32, 1.76, -1.18), TOXIC }, { V3(0.12, 2.06, -1.18), C(190, 90, 255) }, { V3(0.52, 2.36, -1.18), C(255, 150, 40) } }) do
				r:Box("Body", "Vial" .. i, V3(0.16, 0.24, 0.12), v[1], GLASS, MAT.Glass, { Transparency = 0.4 })
				r:Neon("Body", "VialBrew" .. i, V3(0.12, 0.14, 0.1), v[1] - V3(0, 0.03, 0), v[2])
				r:Box("Body", "VialCork" .. i, V3(0.1, 0.06, 0.08), v[1] + V3(0, 0.15, 0), C(150, 104, 64))
			end
			-------- legs: fawn pug legs, black toes
			for _, l in ipairs(LEG_TAGS) do
				local tag, sx, front = l[1], l[2], l[3]
				local x, z = sx * 0.64, front and -0.55 or 1.15
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.6, 1.02, 0.62), V3(x, 0.9, z), FAWN, nil, 0.1)
				r:Paw(paw, tag, x, z - 0.06, 0.7, 0.72, 0.36, FAWN_LO, { Toe = BLACK, Nail = C(20, 18, 20) })
			end
			-------- the leather plague mask: stitched cap, brass goggles with toxic lenses, a long hooked beak
			r:Round("Neck", "Neck", V3(1.2, 0.72, 0.82), V3(0, 2.75, -1.1), LEATHER_LO, nil, 0.12)
			r:Round("Head", "Mask", V3(1.8, 1.56, 1.56), V3(0, 3.5, -1.78), LEATHER, nil, 0.26, LEATHER_HI)
			r:Box("Head", "MaskSeam", V3(0.06, 0.06, 1.56), V3(0, 4.29, -1.78), LEATHER_LO)
			for i = 0, 3 do
				r:Box("Head", "SeamStitch" .. i, V3(0.2, 0.05, 0.05), V3(0, 4.3, -2.3 + i * 0.34), C(200, 164, 112))
			end
			r:Box("Head", "Strap", V3(1.86, 0.16, 1.6), V3(0, 3.78, -1.78), LEATHER_LO)
			r:Pair(function(s, side)
				r:Box("Head", "Rivet_" .. side, V3(0.08, 0.12, 0.12), V3(s * 0.94, 3.78, -2.2), BRASS, MAT.Metal)
				r:Box("Head", "StrapBuckle_" .. side, V3(0.06, 0.24, 0.24), V3(s * 0.94, 3.78, -1.4), BRASS, MAT.Metal)
				r:Cyl("Head", "GoggleRim_" .. side, 0.16, 0.64, CF(s * 0.44, 3.78, -2.58) * ANG(0, PI / 2, 0), BRASS, MAT.Metal)
				r:Cyl("Head", "GoggleRing_" .. side, 0.06, 0.54, CF(s * 0.44, 3.78, -2.67) * ANG(0, PI / 2, 0), BRASS_HI, MAT.Metal)
				r:Cyl("Head", "Lens_" .. side, 0.06, 0.46, CF(s * 0.44, 3.78, -2.68) * ANG(0, PI / 2, 0), C(170, 255, 150), MAT.Neon)
				r:Box("Head", "LensPupil_" .. side, V3(0.12, 0.16, 0.03), V3(s * 0.44, 3.76, -2.72), C(40, 70, 40))
				r:Box("Head", "LensShine_" .. side, V3(0.1, 0.06, 0.03), V3(s * 0.44 + 0.1, 3.88, -2.72), C(250, 255, 250), MAT.Neon)
				r:Round("Head", "Cheek_" .. side, V3(0.22, 0.52, 0.62), V3(s * 0.85, 3.05, -2.2), LEATHER_LO, nil, 0.06)
			end)
			r:Box("Head", "GoggleBridge", V3(0.3, 0.08, 0.06), V3(0, 3.82, -2.62), BRASS, MAT.Metal)
			r:Cyl("Beak", "BeakRing", 0.14, 1.0, CF(0, 3.22, -2.6) * ANG(0, PI / 2, 0), BRASS, MAT.Metal)
			local segs = {
				{ V3(0.9, 0.74, 0.55), V3(0, 3.2, -2.9) },
				{ V3(0.74, 0.62, 0.55), V3(0, 3.1, -3.38) },
				{ V3(0.58, 0.48, 0.52), V3(0, 2.98, -3.86) },
				{ V3(0.42, 0.36, 0.48), V3(0, 2.84, -4.3) },
			}
			for i, sg in ipairs(segs) do
				r:Round("Beak", "Beak" .. i, sg[1], sg[2], i % 2 == 1 and LEATHER or LEATHER_HI, nil, math.min(0.1, sg[1].Y * 0.18))
				r:Box("Beak", "BeakStitch" .. i, V3(0.06, 0.04, sg[1].Z - 0.08), sg[2] + V3(0, sg[1].Y / 2 + 0.02, 0), C(200, 164, 112))
			end
			r:Wedge("Beak", "BeakTip", V3(0.28, 0.34, 0.44), CF(0, 2.78, -4.72) * ANG(0.25, 0, 0), LEATHER_LO)
			r:Box("Beak", "BeakHook", V3(0.2, 0.22, 0.14), V3(0, 2.62, -4.86), LEATHER_LO)
			r:Pair(function(s, side)
				r:Box("Beak", "Nostril_" .. side, V3(0.04, 0.08, 0.14), V3(s * 0.37, 3.16, -3.38), C(30, 20, 14))
				r:Box("Beak", "BeakSeam_" .. side, V3(0.04, 0.04, 1.4), V3(s * 0.2, 2.9, -3.6), LEATHER_LO)
			end)
			-------- wide-brimmed hat (a gentle droop at the front), purple band, buckle and a crow feather
			r:Round("Hat", "Brim", V3(2.7, 0.1, 2.5), V3(0, 4.42, -1.75), HAT, MAT.Fabric, 0.03)
			r:Box("Hat", "BrimFront", V3(2.3, 0.08, 0.32), CF(0, 4.43, -3.04) * ANG(0.28, 0, 0), HAT, MAT.Fabric)
			r:Pair(function(s, side)
				r:Box("Hat", "BrimSide_" .. side, V3(0.32, 0.08, 2.1), CF(s * 1.42, 4.46, -1.75) * ANG(0, 0, -s * 0.3), HAT, MAT.Fabric)
			end)
			r:Round("Hat", "Crown", V3(1.56, 0.86, 1.42), V3(0, 4.88, -1.75), HAT, MAT.Fabric, 0.1)
			r:Box("Hat", "CrownTop", V3(1.36, 0.08, 1.22), V3(0, 5.34, -1.75), C(42, 38, 52), MAT.Fabric)
			r:Box("Hat", "CrownDent", V3(0.12, 0.06, 1.0), V3(0, 5.36, -1.75), C(20, 18, 26), MAT.Fabric)
			r:Box("Hat", "Band", V3(1.6, 0.2, 1.46), V3(0, 4.58, -1.75), BAND, MAT.Fabric)
			r:Box("Hat", "Buckle", V3(0.32, 0.24, 0.04), V3(0, 4.58, -2.49), BRASS, MAT.Metal)
			r:Box("Hat", "BuckleHole", V3(0.16, 0.1, 0.03), V3(0, 4.58, -2.51), BAND)
			r:Box("Hat", "Feather", V3(0.08, 0.8, 0.26), CF(0.78, 5.02, -1.35) * ANG(0.25, 0, -0.3), C(30, 42, 38))
			r:Box("Hat", "FeatherSheen", V3(0.09, 0.54, 0.06), CF(0.79, 5.0, -1.3) * ANG(0.25, 0, -0.3), C(70, 110, 100))
			r:Box("Hat", "FeatherB", V3(0.07, 0.56, 0.2), CF(0.9, 4.92, -1.2) * ANG(0.1, 0, -0.55), C(110, 40, 130))
			-------- the crook staff on its back with the swinging lantern of green plague-fire
			r:Seg("Body", "StaffA", V3(0.92, 2.2, 0.95), V3(1.02, 4.32, 0.18), 0.12, 0.12, C(70, 48, 34))
			r:Seg("Body", "StaffB", V3(1.02, 4.3, 0.2), V3(1.3, 4.52, -0.12), 0.11, 0.11, C(70, 48, 34))
			r:Seg("Body", "StaffC", V3(1.3, 4.5, -0.1), V3(1.42, 4.24, -0.32), 0.1, 0.1, C(70, 48, 34))
			r:Box("Body", "StaffStrap", V3(0.16, 0.2, 0.22), V3(0.95, 2.55, 0.85), LEATHER)
			for i = 0, 2 do
				local alt = i % 2 == 0
				r:Box("Lantern", "Link" .. i, alt and V3(0.12, 0.16, 0.04) or V3(0.04, 0.16, 0.12), V3(1.42, 4.12 - i * 0.13, -0.32), BRASS, MAT.Metal)
			end
			r:Box("Lantern", "LanternCap", V3(0.5, 0.1, 0.5), V3(1.42, 3.8, -0.32), BRASS, MAT.Metal)
			r:Box("Lantern", "LanternRoof", V3(0.32, 0.1, 0.32), V3(1.42, 3.9, -0.32), BRASS_HI, MAT.Metal)
			r:Box("Lantern", "LanternBase", V3(0.5, 0.1, 0.5), V3(1.42, 3.2, -0.32), BRASS, MAT.Metal)
			r:Box("Lantern", "LanternFoot", V3(0.3, 0.08, 0.3), V3(1.42, 3.11, -0.32), BRASS_HI, MAT.Metal)
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					r:Box("Lantern", "LanternPost" .. sx .. sz, V3(0.06, 0.52, 0.06), V3(1.42 + sx * 0.21, 3.5, -0.32 + sz * 0.21), BRASS, MAT.Metal)
				end
			end
			r:Box("Lantern", "LanternGlass", V3(0.38, 0.5, 0.38), V3(1.42, 3.5, -0.32), C(190, 255, 190), MAT.Glass, { Transparency = 0.45 })
			local flame = r:Neon("Flame", "LanternFlame", V3(0.2, 0.28, 0.2), CF(1.42, 3.48, -0.32) * ANG(0, 0.78, 0), TOXIC)
			r:Neon("Flame", "LanternFlameHot", V3(0.1, 0.16, 0.1), V3(1.42, 3.44, -0.32), TOXIC_HOT)
			r:Light(flame, TOXIC, 9, 1.4)
			-------- banks of green fog rolling round the paws (translucent glowing puffs)
			for i, p in ipairs(FOGS) do
				local bone = "Fog_" .. i
				r:Box(bone, "Fog" .. i .. "A", V3(0.95, 0.22, 0.75), CF(p) * ANG(0, 0.4 * i, 0), FOG, MAT.Neon, { Transparency = 0.72 })
				r:Box(bone, "Fog" .. i .. "B", V3(0.6, 0.2, 0.55), CF(p + V3(0.32, 0.14, 0.1)) * ANG(0, -0.3 * i, 0), FOG, MAT.Neon, { Transparency = 0.76 })
				r:Box(bone, "Fog" .. i .. "C", V3(0.5, 0.16, 0.45), CF(p + V3(-0.28, 0.2, -0.18)) * ANG(0, 0.7 * i, 0), FOG, MAT.Neon, { Transparency = 0.8 })
			end
			-------- curly fawn tail with a black tip (three bones)
			r:Round("Tail", "TailA", V3(0.34, 0.42, 0.34), V3(0, 2.6, 1.82), FAWN, nil, 0.06)
			r:Round("Tail2", "TailB", V3(0.32, 0.32, 0.38), V3(0, 2.94, 1.76), FAWN, nil, 0.06)
			r:Round("TailTip", "TailC", V3(0.26, 0.26, 0.26), V3(0, 2.86, 1.52), BLACK, nil, 0.05)
			-------- ability FX hooks (PLAGUE): toxic fog out of the lantern and the beak
			r:Hook(flame, "Lantern", "Fog", V3(1.42, 3.7, -0.32), FOG, TOXIC, 4, 1)
			r:Hook(r.Model:FindFirstChild("BeakHook"), "Beak", "Fog", V3(0, 2.7, -4.9), FOG, C(90, 200, 90), 2, 0)
		end,
	}
end

---------------------------------------------------------------- H07 HEADLESS HOUND (Mythic)
do
	local STEEL, STEEL_LO, STEEL_HI = C(72, 74, 88), C(48, 50, 60), C(126, 130, 148)
	local HIDE, HIDE_HI, RIVET, CLAW = C(44, 40, 52), C(62, 58, 72), C(186, 190, 202), C(214, 218, 228)
	local EMBER, FLAME, FLAME_HOT, FLAME_RED = C(255, 128, 36), C(255, 160, 50), C(255, 238, 170), C(255, 96, 30)
	local ORANGE, ORANGE_HI, ORANGE_LO, RIM, GLOW = C(236, 116, 26), C(250, 146, 50), C(190, 82, 14), C(90, 30, 6), C(255, 196, 70)
	local BANNER, GOLD = C(118, 26, 40), C(214, 170, 70)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.95, 0.3) },
		{ "Banner", "Body", V3(0, 3.82, 1.1) },
		{ "Neck", "Body", V3(0, 3.55, -1.25) },
		{ "Flame", "Neck", V3(0, 4.25, -1.86) },
		{ "Flame2", "Neck", V3(0, 4.25, -1.86) },
		{ "Head", "Neck", V3(0, 3.5, -1.98) },
		{ "Tail", "Body", V3(0, 3.35, 1.95) },
		{ "Tail2", "Tail", V3(0, 3.72, 2.42) },
		{ "TailTip", "Tail2", V3(0, 4.0, 2.8) },
	}
	legBones(bones, 0.62, -0.9, 1.35, 2.55, 1.2, 0.04)
	SPECS.HW_HeadlessHound = {
		Code = "H07",
		SignatureName = "HeadSearch",
		Bones = bones,
		Durations = { Signature = 3.6 },
		Motion = { Breath = 0.04, Wag = 0.25, Stride = 0.4, Hop = 0.5, Look = 0.3 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the neck fire: two layers of tongues flicker against each other
			local fk = looped and 1 or 1.5
			add("Flame", 0, 0.06 * (flick(x, 7 * fk) - 0.5), 0, 0.12 * sinU(x, 5), 0.5 * sinU(x, 3), 0.1 * sinU(x, 9, 0.3))
			add("Flame2", 0, 0.08 * (flick(x, 9 * fk, 0.4) - 0.5), 0, -0.1 * sinU(x, 6, 0.2), -0.6 * sinU(x, 2, 0.1), 0.12 * sinU(x, 7))
			-- the carried head swings on its chain
			if clip == "Idle" then
				add("Head", 0, 0, 0, 0.1 * sinU(u, 1, 0.2), 0.35 * sinU(u, 1), 0.08 * sinU(u, 2))
				add("Banner", 0, 0, 0, 0.06 + 0.04 * sinU(u, 1), 0, 0)
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				add("Head", 0, 0, 0, 0.25 * sinU(u, k, 0.15), 0, 0.12 * sinU(u, 1))
				add("Banner", 0, 0, 0, 0.12 + 0.1 * sinU(u, 2), 0, 0)
			elseif clip == "DigLoop" then
				add("Head", 0, 0, 0, -0.25 + 0.1 * sinU(u, 2), 0.15 * sinU(u, 1), 0)
				add("Banner", 0, 0, 0, 0.1, 0, 0)
			elseif clip == "Sleep" then
				add("Flame", 0, -0.25, 0, 0, 0, 0)
				add("Flame2", 0, -0.3, 0, 0, 0, 0)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local up = bump(t, 0.1, d - 0.1)
				add("Head", 0, 0, 0, 0.3 * math.sin(TAU * 2 * t / d) * up, TAU * rise(t, 0.2, math.min(d, 1.4)), 0)
				add("Flame", 0, 0.3 * up, 0, 0, 0, 0)
				add("Flame2", 0, 0.25 * up, 0, 0, 0, 0)
				add("Banner", 0, 0, 0, 0.3 * up, 0, 0)
			elseif clip == "Signature" then
				-- HEAD SEARCH: the hound stoops, the jack-o'-head swings left and right sniffing the ground, finds the
				-- treasure scent, the neck fire roars up and the head spins round on its chain
				local stoop = hold(t, 0.1, 0.5, 2.0, 2.4)
				add("Body", 0, -0.12 * stoop, 0, -0.12 * stoop, 0, 0)
				add("Neck", 0, 0, 0, -0.25 * stoop, 0, 0)
				add("Head", 0, 0, 0, -0.35 * stoop, 0.9 * math.sin(TAU * 0.9 * t) * stoop, 0.15 * math.sin(TAU * 1.8 * t) * stoop)
				local found = bump(t, 2.2, d - 0.05)
				add("Head", 0, 0, 0, 0.2 * found, TAU * rise(t, 2.4, 3.3), 0)
				add("Flame", 0, 0.5 * found, 0, 0, 0, 0)
				add("Flame2", 0, 0.45 * found, 0, 0, 0, 0)
				add("Banner", 0, 0, 0, 0.35 * found, 0, 0)
				tail(add, 0.3 * found, 0.5 * found, t / d, 6)
			end
		end,
		Build = function(r)
			-------- lean hound body in blackened plate armour with ember-lit seams
			r:Round("Body", "Torso", V3(1.6, 1.4, 3.3), V3(0, 3.0, 0.3), HIDE, nil, 0.24, HIDE_HI)
			r:Round("Body", "Chest", V3(1.72, 1.76, 1.22), V3(0, 2.92, -0.85), HIDE, nil, 0.26)
			r:Round("Body", "ChestPlate", V3(1.6, 1.42, 0.2), V3(0, 3.0, -1.52), STEEL, MAT.DiamondPlate, 0.06)
			r:Box("Body", "ChestRidge", V3(0.16, 1.42, 0.1), V3(0, 3.0, -1.64), STEEL_HI, MAT.Metal)
			r:Box("Body", "ChestRim", V3(1.62, 0.1, 0.2), V3(0, 3.68, -1.53), STEEL_HI, MAT.Metal)
			r:Neon("Body", "ChestEmber", V3(0.5, 0.05, 0.04), V3(0, 2.62, -1.64), EMBER)
			for i, z in ipairs({ -0.55, 0.3, 1.15 }) do
				local y = 3.78 + (i == 2 and 0.03 or 0)
				r:Round("Body", "BackPlate" .. i, V3(1.74, 0.22, 0.95), V3(0, y, z), STEEL, MAT.DiamondPlate, 0.05)
				r:Box("Body", "BackPlateEdge" .. i, V3(1.76, 0.08, 0.1), V3(0, y + 0.12, z - 0.45), STEEL_HI, MAT.Metal)
				for _, sx in ipairs({ -1, 1 }) do
					r:Box("Body", "Rivet" .. i .. "_" .. sx, V3(0.1, 0.06, 0.1), V3(sx * 0.72, y + 0.14, z + 0.25), RIVET, MAT.Metal)
				end
			end
			r:Pair(function(s, side)
				r:Box("Body", "SidePlate_" .. side, V3(0.12, 0.85, 2.6), V3(s * 0.86, 3.2, 0.35), STEEL, MAT.DiamondPlate)
				r:Neon("Body", "SideSeam_" .. side, V3(0.04, 0.05, 2.4), V3(s * 0.93, 2.84, 0.35), EMBER)
				r:Box("Body", "SideTrim_" .. side, V3(0.14, 0.08, 2.62), V3(s * 0.87, 3.6, 0.35), STEEL_HI, MAT.Metal)
				for k = 0, 4 do
					r:Box("Body", "SideRivet" .. k .. "_" .. side, V3(0.06, 0.08, 0.08), V3(s * 0.94, 3.45, -0.65 + k * 0.5), RIVET, MAT.Metal)
				end
				r:Box("Body", "SideRune_" .. side, V3(0.04, 0.3, 0.3), CF(s * 0.93, 3.15, 0.35) * ANG(PI / 4, 0, 0), STEEL_HI, MAT.Metal)
				r:Neon("Body", "SideRuneGlow_" .. side, V3(0.03, 0.12, 0.12), CF(s * 0.955, 3.15, 0.35) * ANG(PI / 4, 0, 0), EMBER)
				r:Round("Body", "Pauldron_" .. side, V3(0.56, 0.38, 0.96), V3(s * 0.92, 3.62, -0.85), STEEL, MAT.Metal, 0.08, STEEL_HI)
				r:Box("Body", "PauldronRim_" .. side, V3(0.58, 0.1, 0.98), V3(s * 0.94, 3.42, -0.85), STEEL_HI, MAT.Metal)
				for j, z in ipairs({ -1.1, -0.6 }) do
					r:Box("Body", "Spike" .. j .. "_" .. side, V3(0.16, 0.24, 0.16), V3(s * 0.95, 3.92, z), STEEL_HI, MAT.Metal)
					r:Box("Body", "SpikeTip" .. j .. "_" .. side, V3(0.08, 0.18, 0.08), V3(s * 0.95, 4.12, z), CLAW, MAT.Metal)
				end
				r:Round("Body", "HipPlate_" .. side, V3(0.5, 0.34, 0.86), V3(s * 0.88, 3.58, 1.35), STEEL, MAT.Metal, 0.07)
			end)
			r:Box("Body", "TuckedBelly", V3(1.2, 0.2, 1.6), V3(0, 2.25, 0.6), HIDE_HI)
			-------- tattered war banner over the hindquarters with a golden pumpkin sigil
			r:Box("Banner", "BannerTop", V3(1.5, 0.08, 1.0), V3(0, 3.95, 1.25), BANNER, MAT.Fabric)
			r:Box("Banner", "BannerTrim", V3(1.52, 0.06, 0.06), V3(0, 3.97, 0.76), GOLD, MAT.Metal)
			for i, x in ipairs({ -0.5, 0, 0.5 }) do
				local len = ({ 0.62, 0.8, 0.5 })[i]
				r:Box("Banner", "BannerTail" .. i, V3(0.46, len, 0.08), V3(x, 3.92 - len / 2, 1.78), BANNER, MAT.Fabric)
				r:Box("Banner", "BannerNotch" .. i, V3(0.2, 0.16, 0.08), V3(x + 0.12, 3.92 - len - 0.06, 1.78), BANNER, MAT.Fabric)
			end
			r:Box("Banner", "BannerSigil", V3(0.32, 0.28, 0.04), V3(0, 3.62, 1.83), GOLD, MAT.Metal)
			r:Box("Banner", "BannerSigilStem", V3(0.08, 0.1, 0.04), V3(0, 3.8, 1.83), GOLD, MAT.Metal)
			-------- long armoured legs: thigh plate, knee cop, greave, sabaton with claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, sx, front = l[1], l[2], l[3]
				local x, z = sx * 0.62, front and -0.9 or 1.35
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Thigh_" .. tag, V3(0.52, 1.36, 0.54), V3(x, 1.92, z), HIDE, nil, 0.1)
				r:Box(leg, "ThighPlate_" .. tag, V3(0.12, 0.9, 0.5), V3(x + sx * 0.28, 2.0, z), STEEL, MAT.Metal)
				r:Round(leg, "Knee_" .. tag, V3(0.52, 0.28, 0.22), V3(x, 1.3, z - 0.27), STEEL_HI, MAT.Metal, 0.05)
				r:Round(paw, "Shin_" .. tag, V3(0.42, 0.96, 0.44), V3(x, 0.72, z + 0.04), HIDE, nil, 0.08)
				r:Box(paw, "Greave_" .. tag, V3(0.46, 0.78, 0.1), V3(x, 0.76, z - 0.22), STEEL, MAT.DiamondPlate)
				r:Box(paw, "GreaveEmber_" .. tag, V3(0.3, 0.04, 0.03), V3(x, 0.98, z - 0.28), EMBER, MAT.Neon)
				r:Round(paw, "Sabaton_" .. tag, V3(0.58, 0.28, 0.74), V3(x, 0.14, z - 0.08), STEEL, MAT.Metal, 0.06, STEEL_HI)
				for j, dx in ipairs({ -0.17, 0, 0.17 }) do
					r:Box(paw, "Claw" .. j .. "_" .. tag, V3(0.1, 0.1, 0.2), V3(x + dx, 0.06, z - 0.52), CLAW, MAT.Metal)
				end
			end
			-------- the neck ends in a jagged stump: a ring of steel teeth round a pit of embers, and the fire roars out
			r:Round("Neck", "Gorget", V3(1.12, 1.05, 1.0), CF(0, 3.75, -1.55) * ANG(0.42, 0, 0), STEEL, MAT.Metal, 0.1)
			r:Box("Neck", "GorgetBand", V3(1.16, 0.12, 1.04), CF(0, 3.55, -1.46) * ANG(0.42, 0, 0), STEEL_HI, MAT.Metal)
			r:Box("Neck", "GorgetBandB", V3(1.16, 0.12, 1.04), CF(0, 3.92, -1.64) * ANG(0.42, 0, 0), STEEL_HI, MAT.Metal)
			r:Round("Neck", "Stump", V3(0.98, 0.16, 0.94), V3(0, 4.18, -1.86), STEEL_HI, MAT.Metal, 0.04)
			r:Neon("Neck", "StumpEmbers", V3(0.7, 0.06, 0.66), V3(0, 4.26, -1.86), FLAME_RED)
			for i = 0, 7 do
				local a = i / 8 * TAU
				r:Box("Neck", "StumpTooth" .. i, V3(0.14, 0.2 + (i % 3) * 0.06, 0.14), CF(0.42 * math.cos(a), 4.32, -1.86 + 0.4 * math.sin(a)) * ANG(0, -a, 0.15), STEEL_HI, MAT.Metal)
			end
			local core = r:Neon("Flame", "FlameCore", V3(0.42, 0.3, 0.42), V3(0, 4.38, -1.86), FLAME_HOT)
			r:Light(core, C(255, 150, 60), 11, 1.9)
			r:Tuft("Flame", "Tongue", CF(0, 4.3, -1.86) * ANG(PI, 0.3, 0), 1.35, 0.62, 4, FLAME, FLAME_HOT, MAT.Neon)
			for i, o in ipairs({ { V3(0.26, 0, 0.18), 0.95, 0.36 }, { V3(-0.24, 0, 0.22), 0.8, 0.34 }, { V3(0.2, 0, -0.26), 0.72, 0.32 }, { V3(-0.22, 0, -0.2), 1.0, 0.36 } }) do
				local bone = i % 2 == 0 and "Flame" or "Flame2"
				r:Tuft(bone, "SideTongue" .. i, CF(V3(0, 4.28, -1.86) + o[1]) * ANG(PI, 0.5 * i, 0.12 * (i % 2 == 0 and 1 or -1)), o[2], o[3], 3, i % 2 == 0 and FLAME_RED or FLAME, FLAME, MAT.Neon)
			end
			-------- the carried jack-o'-head: it dangles from the gorget on a chain and looks around
			for i = 0, 3 do
				local alt = i % 2 == 0
				r:Box("Head", "Link" .. i, alt and V3(0.12, 0.16, 0.04) or V3(0.04, 0.16, 0.12), V3(0, 3.42 - i * 0.12, -1.98), STEEL_HI, MAT.Metal)
			end
			local jack = r:Round("Head", "Jack", V3(1.0, 0.82, 0.92), V3(0, 2.62, -2.08), ORANGE, nil, 0.16, ORANGE_HI)
			r:Light(jack, C(255, 150, 50), 6, 0.9)
			r:Round("Head", "JackWide", V3(1.18, 0.66, 0.74), V3(0, 2.62, -2.08), ORANGE, nil, 0.12)
			r:Pair(function(s, side)
				r:Box("Head", "JackGroove_" .. side, V3(0.05, 0.6, 0.08), V3(s * 0.592, 2.62, -2.2), ORANGE_LO)
				r:Box("Head", "JackGrooveB_" .. side, V3(0.05, 0.56, 0.08), V3(s * 0.592, 2.62, -1.9), ORANGE_LO)
				r:Tri("Head", "JackEar_" .. side, V3(s * 0.32, 3.12, -2.1), 0.32, 0.3, 0.12, ORANGE_LO, MAT.SmoothPlastic, false, ANG(0, 0, -s * 0.25))
				local turn = ANG(0, 0, -s * 0.15)
				r:Tri("Head", "JackEyeRim_" .. side, V3(s * 0.22, 2.76, -2.555), 0.36, 0.3, 0.03, RIM, MAT.SmoothPlastic, false, turn)
				r:Tri("Head", "JackEye_" .. side, V3(s * 0.22, 2.75, -2.58), 0.24, 0.2, 0.03, GLOW, MAT.Neon, false, turn)
			end)
			r:Tri("Head", "JackNose", V3(0, 2.6, -2.56), 0.14, 0.11, 0.03, RIM, MAT.SmoothPlastic, true)
			r:Box("Head", "JackGrinRim", V3(0.62, 0.18, 0.03), V3(0, 2.42, -2.555), RIM)
			r:Neon("Head", "JackGrin", V3(0.54, 0.1, 0.03), V3(0, 2.42, -2.58), GLOW)
			for i, xx in ipairs({ -0.14, 0.14 }) do
				r:Box("Head", "JackTooth" .. i, V3(0.08, 0.06, 0.03), V3(xx, 2.455, -2.6), ORANGE)
			end
			r:Box("Head", "JackStem", V3(0.14, 0.2, 0.14), CF(0, 3.1, -2.02) * ANG(0, 0, 0.2), C(100, 92, 46))
			r:Box("Head", "JackCap", V3(0.3, 0.06, 0.3), V3(0, 3.04, -2.06), ORANGE_LO)
			-------- segmented armoured tail with a blade tip (three bones)
			r:Seg("Tail", "TailA", V3(0, 3.36, 1.96), V3(0, 3.74, 2.44), 0.38, 0.38, STEEL, MAT.Metal)
			r:Box("Tail", "TailRing", V3(0.44, 0.44, 0.08), CF(0, 3.5, 2.14) * ANG(0.9, 0, 0), STEEL_HI, MAT.Metal)
			r:Seg("Tail2", "TailB", V3(0, 3.72, 2.42), V3(0, 4.02, 2.82), 0.32, 0.32, STEEL, MAT.Metal)
			r:Box("Tail2", "TailRingB", V3(0.36, 0.36, 0.07), CF(0, 3.87, 2.62) * ANG(0.9, 0, 0), STEEL_HI, MAT.Metal)
			r:Seg("TailTip", "TailC", V3(0, 4.0, 2.8), V3(0, 4.18, 3.06), 0.26, 0.26, STEEL_LO, MAT.Metal)
			r:Wedge("TailTip", "TailBlade", V3(0.08, 0.5, 0.36), CF(0, 4.38, 3.2) * ANG(0.6, 0, 0), CLAW, MAT.Metal)
			r:Neon("TailTip", "TailEmber", V3(0.05, 0.05, 0.3), CF(0, 4.3, 3.12) * ANG(0.6, 0, 0), EMBER)
			-------- ability FX hooks (HEADLESS TREASURE): fire off the neck, gold-fire embers round the jack-o'-head
			r:Hook(core, "Flame", "Flame", V3(0, 4.45, -1.86), FLAME, FLAME_RED, 10, 1.4)
			r:Hook(jack, "Head", "Embers", V3(0, 2.62, -2.1), C(255, 214, 90), FLAME, 4, 0)
		end,
	}
end

---------------------------------------------------------------- H08 ECLIPSE DOG (SECRET)
do
	local VOID, VOID_HI, VOID_LO, GLOSS = C(18, 14, 26), C(38, 28, 54), C(10, 8, 14), C(30, 24, 42)
	local NEON, NEON_HOT, WHITE, PALE = C(176, 70, 255), C(226, 182, 255), C(244, 240, 255), C(170, 206, 255)
	local STONE, STONE_HI, STONE_LO = C(120, 112, 142), C(152, 144, 174), C(84, 78, 104)
	local HALO = V3(0, 4.15, -1.0)
	local SHARDS = {
		{ V3(2.05, 1.7, -0.45), 0.42 },
		{ V3(-2.0, 2.75, 0.6), 0.38 },
		{ V3(1.15, 4.3, 1.75), 0.32 },
		{ V3(-1.35, 1.45, -1.9), 0.36 },
		{ V3(1.55, 3.2, 1.9), 0.28 },
	}
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.6, 0.25) },
		{ "Neck", "Body", V3(0, 3.3, -1.15) },
		{ "Halo", "Neck", HALO },
		{ "Rays", "Halo", HALO },
		{ "Head", "Neck", V3(0, 3.85, -1.65) },
		{ "Jaw", "Head", V3(0, 3.5, -2.55) },
		{ "Ear_L", "Head", V3(0.42, 4.45, -1.65) },
		{ "Ear_R", "Head", V3(-0.42, 4.45, -1.65) },
		{ "Tail", "Body", V3(0, 3.0, 1.7) },
		{ "Tail2", "Tail", V3(0, 3.6, 2.35) },
		{ "TailTip", "Tail2", V3(0, 4.05, 2.75) },
		{ "Orbit", "Root", V3(0, 2.0, 0.2) },
	}
	for i, c in ipairs(SHARDS) do
		table.insert(bones, { "Chunk_" .. i, "Orbit", c[1] })
	end
	legBones(bones, 0.55, -0.75, 1.2, 2.2, 0.95, 0)
	-- a crescent of n boxes on an arc of radius rad in the frame's XY plane (opening toward +X), facing -Z
	local function crescent(r, bone, name, frame: CFrame, rad: number, thick: number, depth: number, color, mat, n: number?)
		n = n or 5
		for i = 0, n - 1 do
			local a = math.rad(100 + i * 160 / (n - 1))
			local seg = rad * math.rad(160 / (n - 1)) * 1.15
			local w = thick * (1 - 0.45 * math.abs(i - (n - 1) / 2) / ((n - 1) / 2))
			r:Box(bone, name .. i, V3(w, seg, depth), frame * CF(rad * math.cos(a), rad * math.sin(a), 0) * ANG(0, 0, a), color, mat)
		end
	end
	SPECS.HW_EclipseDog = {
		Code = "H08",
		SignatureName = "Howl",
		Bones = bones,
		Durations = { Idle = 6.4, DigLoop = 4.0, Signature = 3.8 },
		Motion = { Breath = 0.035, Wag = 0.22, Stride = 0.42, Hop = 0.5, Look = 0.22, IdleK = 2, ScoopK = 4, Spin = false },
		Extra = function(clip, t, d, u, add)
			-- the moon shards orbit the dog (one turn per Idle / DigLoop), bob and tumble; the corona turns, the rays counter-turn
			local looped = E.IsLooped(clip)
			local turns = (clip == "Idle" or clip == "DigLoop") and 1 or 0
			local x = looped and u or t / d
			if not looped then
				add("Orbit", 0, 0.3 * bump(t, 0.1, d - 0.1), 0, 0, TAU * rise(t, 0.1, d - 0.1), 0)
			elseif turns > 0 then
				add("Orbit", 0, 0, 0, 0, TAU * turns * u, 0)
			else
				add("Orbit", 0, 0, 0, 0, 0.12 * sinU(u, 1), 0)
			end
			for i = 1, #SHARDS do
				local ph = i / #SHARDS
				add("Chunk_" .. i, 0, 0.18 * sinU(x, 2, ph), 0, 0.3 * sinU(x, 1, ph), TAU * x * (i % 2 == 0 and -1 or 1), 0.2 * sinU(x, 1, ph + 0.25))
			end
			-- loops turn whole revolutions (seamless), one-shots a slow quarter turn
			add("Halo", 0, 0, 0, 0, 0, looped and -TAU * u or TAU * 0.25 * x)
			add("Rays", 0, 0, 0, 0, 0, looped and TAU * (clip == "Run" and 1 or 2) * u or -TAU * 0.5 * x)
			if clip == "Happy" or clip == "RareFind" then
				-- it rises and hovers: the eclipse at full strength
				local hover = bump(t, 0.1, d - 0.1)
				add("Root", 0, 0.8 * hover, 0, 0, 0, 0)
				add("Leg_FL", 0, 0, 0, 0.3 * hover, 0, 0)
				add("Leg_FR", 0, 0, 0, 0.3 * hover, 0, 0)
				add("Leg_BL", 0, 0, 0, -0.3 * hover, 0, 0)
				add("Leg_BR", 0, 0, 0, -0.3 * hover, 0, 0)
			elseif clip == "Signature" then
				-- HOWL: it sits back on its haunches, raises its muzzle to the dead moon and howls; the corona flares,
				-- the rays race round and the shards climb into a tight fast ring
				local sit = hold(t, 0.1, 0.6, d - 0.6, d - 0.1)
				local howl = hold(t, 0.8, 1.2, d - 1.0, d - 0.55)
				add("Body", 0, -0.42 * sit, 0.1 * sit, 0.32 * sit, 0, 0)
				add("Leg_BL", 0, 0, 0, 0.85 * sit, 0, 0)
				add("Leg_BR", 0, 0, 0, 0.85 * sit, 0, 0)
				add("Paw_BL", 0, 0, 0, -1.0 * sit, 0, 0)
				add("Paw_BR", 0, 0, 0, -1.0 * sit, 0, 0)
				add("Leg_FL", 0, 0, 0, -0.28 * sit, 0, 0)
				add("Leg_FR", 0, 0, 0, -0.28 * sit, 0, 0)
				add("Neck", 0, 0, 0, 0.45 * howl, 0, 0)
				add("Head", 0, 0, 0, 0.45 * howl, 0, 0.04 * math.sin(TAU * 7 * t) * howl)
				add("Jaw", 0, 0, 0, -0.5 * howl - 0.06 * math.sin(TAU * 9 * t) * howl, 0, 0)
				add("Ear_L", 0, 0, 0, -0.3 * howl, 0, 0)
				add("Ear_R", 0, 0, 0, -0.3 * howl, 0, 0)
				add("Halo", 0, 0.2 * howl, 0.1 * howl, 0, 0, -TAU * 1.5 * rise(t, 0.8, d - 0.5))
				add("Rays", 0, 0, 0, 0, 0, TAU * 3 * rise(t, 0.8, d - 0.5))
				add("Orbit", 0, 0.7 * howl, 0, 0, TAU * 2 * rise(t, 0.6, d - 0.4), 0)
				tail(add, -0.25 * sit, 0.3 * sit, t / d, 3)
			end
		end,
		Build = function(r)
			-------- a lean wolf-dog of pure void: glossy black with a deep violet sheen on its upper planes
			r:Round("Body", "Torso", V3(1.45, 1.25, 3.0), V3(0, 2.68, 0.25), VOID, nil, 0.22, VOID_HI)
			r:Round("Body", "Chest", V3(1.6, 1.56, 1.05), V3(0, 2.62, -0.82), VOID, nil, 0.26, VOID_HI)
			r:Box("Body", "Loin", V3(1.2, 0.3, 1.5), V3(0, 2.02, 0.9), VOID_LO)
			r:Box("Body", "BackSheen", V3(0.9, 0.06, 2.6), V3(0, 3.31, 0.3), C(54, 40, 78), nil, { Reflectance = 0.1 })
			-- eclipse emblem on the chest: a black sun inside a neon ring with a flare
			r:Cyl("Body", "EclipseDisc", 0.06, 0.64, CF(0, 2.75, -1.36) * ANG(0, PI / 2, 0), GLOSS, MAT.SmoothPlastic, { Reflectance = 0.15 })
			for i = 0, 9 do
				local a = i / 10 * TAU
				r:Neon("Body", "EmblemRing" .. i, V3(0.22, 0.05, 0.04), CF(0.4 * math.cos(a), 2.75 + 0.4 * math.sin(a), -1.39) * ANG(0, 0, a + PI / 2), i % 3 == 0 and NEON_HOT or NEON)
			end
			r:Neon("Body", "EmblemFlare", V3(0.1, 0.1, 0.04), V3(0.28, 3.02, -1.41), WHITE)
			-- crescent moons on both flanks
			r:Pair(function(s, side)
				crescent(r, "Body", "FlankMoon_" .. side, CF(s * 0.735, 2.75, 0.45) * ANG(0, s * PI / 2, 0), 0.32, 0.12, 0.03, NEON, MAT.Neon, 5)
			end)
			-- a ruff of void fur round the neck with violet tips, and a spine crest
			r:Round("Neck", "Mane", V3(1.36, 0.5, 1.2), CF(0, 3.3, -1.2) * ANG(0.3, 0, 0), VOID_HI, nil, 0.14)
			r:Round("Neck", "ManeTop", V3(1.1, 0.42, 0.95), CF(0, 3.66, -1.36) * ANG(0.38, 0, 0), VOID, nil, 0.12, VOID_HI)
			r:Neon("Neck", "ManeGlow", V3(1.38, 0.04, 0.05), CF(0, 3.05, -1.78) * ANG(0.3, 0, 0), NEON, { Transparency = 0.2 })
			for i, x in ipairs({ -0.36, -0.12, 0.12, 0.36 }) do
				r:Tuft("Neck", "Bib" .. i, CF(x, 3.0, -1.66) * ANG(-0.2, 0, x * 0.4), 0.42 - math.abs(x) * 0.3, 0.24, 2, VOID_HI, VOID)
			end
			for i = 0, 4 do
				local z = -0.6 + i * 0.5
				r:Tuft("Body", "Crest" .. i, CF(0, 3.3, z) * ANG(PI - 0.5, 0, 0), 0.36 - i * 0.03, 0.22, 2, VOID_HI, VOID)
			end
			r:Neon("Body", "CrestGlow", V3(0.05, 0.05, 2.3), V3(0, 3.33, 0.4), NEON, { Transparency = 0.25 })
			-------- long slender legs, violet-tipped claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, sx, front = l[1], l[2], l[3]
				local x, z = sx * 0.55, front and -0.75 or 1.2
				local zp = front and -0.78 or 1.25
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Thigh_" .. tag, V3(0.46, 1.3, 0.5), V3(x, 1.6, z), VOID, nil, 0.1, VOID_HI)
				r:Round(paw, "Shin_" .. tag, V3(0.38, 0.84, 0.4), V3(x, 0.62, zp), VOID, nil, 0.08)
				r:Box(paw, "ShinEdge_" .. tag, V3(0.05, 0.6, 0.05), V3(x, 0.66, zp - 0.21), NEON, MAT.Neon)
				r:Paw(paw, tag, x, zp - 0.1, 0.52, 0.64, 0.26, VOID_HI, { Toe = VOID_HI, Nail = NEON, NailMat = MAT.Neon })
			end
			-------- neck, head and snout; glowing slit eyes, a crescent on the brow
			r:Round("Neck", "Neck", V3(0.9, 1.15, 0.9), CF(0, 3.42, -1.35) * ANG(0.38, 0, 0), VOID, nil, 0.16)
			r:Round("Head", "Head", V3(1.25, 1.05, 1.25), V3(0, 3.98, -1.95), VOID, nil, 0.22, VOID_HI)
			r:Round("Head", "Snout", V3(0.7, 0.5, 0.92), V3(0, 3.72, -2.95), VOID, nil, 0.12, VOID_HI)
			r:Round("Head", "Nose", V3(0.3, 0.2, 0.16), V3(0, 3.93, -3.42), GLOSS, nil, 0.04)
			r:Box("Head", "NoseShine", V3(0.1, 0.04, 0.03), V3(0.06, 4.01, -3.51), C(180, 160, 220))
			r:Box("Head", "BrowRidge", V3(1.1, 0.12, 0.12), V3(0, 4.3, -2.6), VOID_HI)
			crescent(r, "Head", "BrowMoon", CF(0, 4.42, -2.6) * ANG(0, 0, PI / 2), 0.16, 0.07, 0.03, NEON_HOT, MAT.Neon, 4)
			r:Pair(function(s, side)
				local turn = ANG(0, 0, s * 0.22)
				r:Box("Head", "Socket_" .. side, V3(0.42, 0.16, 0.03), CF(s * 0.34, 4.1, -2.585) * turn, C(40, 14, 60))
				r:Neon("Head", "Eye_" .. side, V3(0.34, 0.09, 0.03), CF(s * 0.34, 4.1, -2.61) * turn, NEON)
				r:Neon("Head", "EyeHot_" .. side, V3(0.1, 0.06, 0.03), CF(s * 0.3, 4.1, -2.635) * turn, WHITE)
				r:Tuft("Head", "Cheek_" .. side, CF(s * 0.62, 3.7, -1.9) * ANG(-0.6, 0, s * 0.7), 0.5, 0.3, 3, VOID, VOID_HI)
				-- tall pointed ears with neon rims
				local eturn = ANG(0, 0, -s * 0.12)
				local ear = "Ear_" .. side
				r:Tri(ear, "Ear_" .. side, V3(s * 0.42, 4.95, -1.66), 0.54, 0.96, 0.16, VOID, MAT.SmoothPlastic, false, eturn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.42, 4.88, -1.75), 0.3, 0.58, 0.04, C(56, 24, 86), MAT.SmoothPlastic, false, eturn)
				local base = CF(s * 0.42, 4.95, -1.66) * eturn
				r:Seg(ear, "EarRimOut_" .. side, (base * CF(s * 0.28, -0.48, 0)).Position, (base * CF(0, 0.49, 0)).Position, 0.05, 0.18, NEON, MAT.Neon)
				r:Seg(ear, "EarRimIn_" .. side, (base * CF(-s * 0.28, -0.48, 0)).Position, (base * CF(0, 0.49, 0)).Position, 0.05, 0.18, NEON, MAT.Neon)
			end)
			r:Round("Jaw", "Jaw", V3(0.6, 0.18, 0.8), V3(0, 3.4, -2.85), VOID_HI, nil, 0.05)
			r:Pair(function(s, side)
				r:Box("Jaw", "Fang_" .. side, V3(0.06, 0.12, 0.06), V3(s * 0.18, 3.54, -3.2), C(230, 220, 255))
			end)
			r:Box("Jaw", "Tongue", V3(0.24, 0.04, 0.3), V3(0, 3.5, -2.95), C(120, 50, 170))
			-------- star specks scattered over the coat (a night sky in the shape of a dog)
			local SPECKS = {
				{ "Body", V3(0.3, 3.315, -0.2), 0 }, { "Body", V3(-0.25, 3.315, 0.6), 0 }, { "Body", V3(0.15, 3.315, 1.3), 0 },
				{ "Body", V3(-0.35, 3.315, -0.75), 0 }, { "Body", V3(0.4, 3.315, 0.95), 0 },
				{ "Body", V3(0.73, 2.4, -0.1), 1 }, { "Body", V3(0.73, 3.05, 1.1), 1 }, { "Body", V3(0.73, 2.25, 1.4), 1 },
				{ "Body", V3(-0.73, 2.9, -0.2), 1 }, { "Body", V3(-0.73, 2.35, 0.8), 1 }, { "Body", V3(-0.73, 3.0, 1.45), 1 },
				{ "Body", V3(0.81, 2.2, -0.8), 1 }, { "Body", V3(-0.81, 3.05, -0.9), 1 },
				{ "Head", V3(0.3, 4.505, -1.7), 0 }, { "Head", V3(-0.25, 4.505, -2.2), 0 }, { "Head", V3(0.63, 3.95, -1.6), 1 },
				{ "Head", V3(-0.63, 4.1, -2.1), 1 }, { "Leg_FL", V3(0.79, 1.7, -0.75), 1 }, { "Leg_BR", V3(-0.79, 1.45, 1.2), 1 },
				{ "Leg_BL", V3(0.79, 1.9, 1.2), 1 }, { "Paw_FR", V3(-0.75, 0.7, -0.78), 1 },
			}
			for i, sp in ipairs(SPECKS) do
				local size = (i % 4 == 0) and 0.09 or 0.06
				local col = ({ WHITE, NEON_HOT, PALE })[i % 3 + 1]
				local dim = sp[3] == 0 and V3(size, 0.03, size) or V3(0.03, size, size)
				r:Neon(sp[1], "Star" .. i, dim, sp[2], col)
			end
			-- two bigger four-point stars
			for i, sp in ipairs({ { "Body", V3(0.732, 2.55, 0.0) }, { "Body", V3(-0.732, 2.6, 0.45) } }) do
				r:Neon(sp[1], "BigStarA" .. i, V3(0.03, 0.26, 0.05), sp[2], WHITE)
				r:Neon(sp[1], "BigStarB" .. i, V3(0.03, 0.05, 0.26), sp[2], WHITE)
			end
			-------- the corona: a black moon disc behind the head, a 24-segment neon ring and a counter-turning ray crown
			local disc = r:Cyl("Halo", "MoonDisc", 0.06, 1.92, CF(HALO) * ANG(0, PI / 2, 0), VOID_LO)
			r:Light(disc, NEON, 8, 0.9)
			for i = 0, 23 do
				local a = i / 24 * TAU
				local rad = 1.0
				r:Neon("Halo", "Corona" .. i, V3(0.3, 0.1, 0.1), CF(HALO + V3(rad * math.cos(a), rad * math.sin(a), 0.02)) * ANG(0, 0, a + PI / 2), i % 6 == 0 and NEON_HOT or NEON)
			end
			for i = 0, 11 do
				local a = (i + 0.5) / 12 * TAU
				local len = ({ 0.5, 0.3, 0.42, 0.26 })[i % 4 + 1]
				local rad = 1.12 + len / 2
				r:Neon("Rays", "Ray" .. i, V3(0.06, len, 0.05), CF(HALO + V3(rad * math.cos(a), rad * math.sin(a), 0.03)) * ANG(0, 0, a - PI / 2), i % 2 == 0 and NEON_HOT or NEON, { Transparency = i % 2 == 0 and 0.05 or 0.3 })
			end
			-------- bushy tail (three bones) with a nebula tip
			r:Round("Tail", "TailA", V3(0.5, 0.5, 0.86), CF(0, 3.25, 2.0) * ANG(0.75, 0, 0), VOID, nil, 0.1, VOID_HI)
			r:Round("Tail2", "TailB", V3(0.48, 0.48, 0.78), CF(0, 3.82, 2.55) * ANG(0.85, 0, 0), VOID, nil, 0.1, VOID_HI)
			r:Round("TailTip", "TailC", V3(0.36, 0.36, 0.5), CF(0, 4.2, 2.9) * ANG(0.95, 0, 0), VOID_HI, nil, 0.08)
			r:Neon("TailTip", "TailNebula", V3(0.2, 0.2, 0.2), CF(0, 4.38, 3.06) * ANG(0.6, 0.6, 0), NEON, { Transparency = 0.2 })
			r:Neon("TailTip", "TailStar", V3(0.08, 0.08, 0.08), V3(0, 4.46, 3.12), WHITE)
			r:Neon("Tail2", "TailStarB", V3(0.03, 0.06, 0.06), V3(0.245, 3.8, 2.5), WHITE)
			-------- moon-rock shards in orbit: grey crescents of stone with violet cracks
			for i, c in ipairs(SHARDS) do
				local pos, sz = c[1], c[2]
				local bone = "Chunk_" .. i
				local frame = CF(pos) * ANG(0.3 * i, 0.7 * i, 0.4 * i)
				crescent(r, bone, "Shard" .. i .. "_", frame, sz, sz * 0.7, sz * 0.75, i % 2 == 0 and STONE or STONE_HI, MAT.Slate, 4)
				r:Box(bone, "ShardCore" .. i, V3(sz * 0.45, sz * 0.5, sz * 0.6), frame * CF(-sz, 0, 0), STONE_LO, MAT.Slate)
				r:Neon(bone, "Crack" .. i, V3(0.04, sz * 0.9, 0.04), frame * CF(-sz * 0.95, 0, -sz * 0.38) * ANG(0, 0, 0.4), NEON)
				r:Neon(bone, "CrackB" .. i, V3(0.04, sz * 0.5, 0.04), frame * CF(-sz * 0.7, sz * 0.4, -sz * 0.38) * ANG(0, 0, -0.6), NEON_HOT)
			end
			-------- ability FX hooks (ECLIPSE): star sparks off the corona, void smoke off the body
			r:Hook(disc, "Corona", "Stars", HALO + V3(0, 0, 0.05), NEON_HOT, NEON, 6, 1.2)
			r:Hook(r.Model:FindFirstChild("Torso"), "Void", "Void", V3(0, 2.9, 0.3), C(60, 20, 90), C(10, 6, 16), 3, 0)
		end,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------------------------
function E.Spec(id: string)
	return SPECS[id]
end

function E.BoneNames(id: string): { string }
	local spec = SPECS[id]
	local out = {}
	for _, b in ipairs(spec and spec.Bones or {}) do
		table.insert(out, b[1])
	end
	return out
end

-- every clip saved for a dog: E.ClipNames + its signature clip under the dog's own name
function E.ClipNamesFor(id: string): { string }
	local out = table.clone(E.ClipNames)
	local spec = SPECS[id]
	if spec and spec.SignatureName and not table.find(out, spec.SignatureName) then
		table.insert(out, spec.SignatureName)
	end
	return out
end

local function clipKey(id: string, clip: string): string?
	if CLIPS[clip] then
		return clip
	end
	local spec = SPECS[id]
	if spec and spec.SignatureName == clip then
		return "Signature"
	end
	return nil
end

-- A fresh model of an event dog (not parented). opts.Name overrides the model name.
function E.Build(id: string, opts: any?): Model?
	local spec = SPECS[id]
	if not spec then
		return nil
	end
	local r = newRig(id, spec)
	spec.Build(r)
	local model = r.Model
	if opts and opts.Name then
		model.Name = opts.Name
	end
	model:SetAttribute("DogId", id)
	model:SetAttribute("AnimationBaseScale", 1)
	model:SetAttribute("AnimationSource", "DogAnimationClips")
	model:SetAttribute("DogPartRig", true)
	model:SetAttribute("DogRenderVersion", 2)
	model:SetAttribute("EventDex", E.EventDex)
	model:SetAttribute("EventCode", spec.Code)
	model:SetAttribute("Parts", r.Count)
	model:SetAttribute("FXHooks", r.Hooks)
	if spec.SignatureName then
		model:SetAttribute("SignatureClip", spec.SignatureName)
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	return model
end

function E.Duration(id: string, clip: string): number
	local spec = SPECS[id]
	local key = clipKey(id, clip) or clip
	return spec and spec.Durations and spec.Durations[key] or (CLIPS[key] and CLIPS[key][1]) or 1
end

-- One clip as the DogAnimationPlayer table.
function E.Clip(id: string, clipName: string): any
	local spec = SPECS[id]
	local clip = clipKey(id, clipName)
	if not spec or not clip then
		return nil
	end
	local bones, rest = {}, {}
	for _, b in ipairs(spec.Bones) do
		bones[b[1]] = true
		rest[b[1]] = b[3]
	end
	local d = E.Duration(id, clip)
	local loop = E.IsLooped(clip)
	local fps = E.FPS
	local frames = math.max(2, math.floor(d * fps + 0.5) + 1)
	local m = table.clone(spec.Motion or {})
	m.HipY = m.HipY or (rest.Leg_FL and rest.Leg_FL.Y) or 1.4
	local tracks, moving = {}, {}
	local function sample(t: number)
		local acc = {}
		local function add(bone, px, py, pz, rx, ry, rz)
			if not bones[bone] then
				return
			end
			local a = acc[bone]
			if not a then
				a = { 0, 0, 0, 0, 0, 0 }
				acc[bone] = a
			end
			a[1] += px
			a[2] += py
			a[3] += pz
			a[4] += rx
			a[5] += ry
			a[6] += rz
		end
		local u = t / d
		local function scaled(w)
			return function(bone, px, py, pz, rx, ry, rz)
				add(bone, px * w, py * w, pz * w, rx * w, ry * w, rz * w)
			end
		end
		if clip == "Idle" then
			idlePose(m, u, add)
		elseif clip == "Walk" then
			walkPose(m, u, add)
		elseif clip == "Run" then
			runPose(m, u, add)
		elseif clip == "DigLoop" then
			digPose(m, u, add)
		elseif clip == "DigStart" or clip == "DigEnd" then
			digStillPose(m, scaled(clip == "DigStart" and smooth(u) or 1 - smooth(u)))
		elseif clip == "DigFind" then
			findPose(m, t, d, add)
		elseif clip == "Happy" then
			happyPose(m, t, d, add)
		elseif clip == "Sniff" then
			sniffPose(m, t, d, add)
		elseif clip == "Sleep" then
			sleepPose(m, u, add)
		elseif clip == "RareFind" then
			rareFindPose(m, t, d, add)
		end
		if spec.Extra then
			-- DigStart / DigEnd blend the extras of the dig loop like the base pose
			if clip == "DigStart" or clip == "DigEnd" then
				spec.Extra("DigLoop", 0, E.Duration(id, "DigLoop"), 0, scaled(clip == "DigStart" and smooth(u) or 1 - smooth(u)))
			end
			spec.Extra(clip, t, d, u, add)
		end
		return acc
	end
	for f = 1, frames do
		local t = loop and (f - 1) / (frames - 1) * d or math.min(d, (f - 1) / fps)
		if f == frames then
			t = d
		end
		local acc = sample(loop and (f == frames and 0 or t) or t)
		for bone in pairs(bones) do
			local a = acc[bone]
			local px, py, pz, rx, ry, rz = 0, 0, 0, 0, 0, 0
			if a then
				px, py, pz, rx, ry, rz = a[1], a[2], a[3], a[4], a[5], a[6]
			end
			local qx, qy, qz, qw = quat(rx, ry, rz)
			local row = tracks[bone]
			if not row then
				row = table.create(frames)
				tracks[bone] = row
			end
			row[f] = { px, py, pz, qx, qy, qz, qw }
			if math.abs(px) + math.abs(py) + math.abs(pz) + math.abs(rx) + math.abs(ry) + math.abs(rz) > 1e-5 then
				moving[bone] = true
			end
		end
	end
	for bone in pairs(tracks) do
		if not moving[bone] then
			tracks[bone] = nil
		end
	end
	return { duration = d, loop = loop, fps = fps, category = "motion", tracks = tracks }
end

local function num(v: number): string
	if math.abs(v) < 5e-5 then
		return "0"
	end
	local s = string.format("%.4f", v)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		return "0"
	end
	return s
end

-- Lua source of a clip ModuleScript (a plain table: DogAnimationPlayer's loadClip simply requires it).
function E.Serialize(clip: any, header: string?): string
	local out = { header or "", "return {duration=", num(clip.duration), ",loop=", tostring(clip.loop), ",fps=", tostring(clip.fps),
		",category=\"", clip.category or "motion", "\",tracks={\n" }
	local names = {}
	for bone in pairs(clip.tracks) do
		table.insert(names, bone)
	end
	table.sort(names)
	for _, bone in ipairs(names) do
		table.insert(out, "[\"" .. bone .. "\"]={")
		for i, row in ipairs(clip.tracks[bone]) do
			table.insert(out, (i > 1 and "," or "") .. "{" .. num(row[1]) .. "," .. num(row[2]) .. "," .. num(row[3]) .. "," .. num(row[4])
				.. "," .. num(row[5]) .. "," .. num(row[6]) .. "," .. num(row[7]) .. "}")
		end
		table.insert(out, "},\n")
	end
	table.insert(out, "}}\n")
	return table.concat(out)
end

---------------------------------------------------------------------------------------------------------------------
-- Ability FX (client runtime; never called at build time)
---------------------------------------------------------------------------------------------------------------------
local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}
-- recipe per HwFX kind: texture, lifetime, size (start, peak, end), speed, spread, rise (acceleration Y), light emission
local RECIPES = {
	Embers = { Tex = "Sparkle", Life = { 0.6, 1.2 }, Size = { 0.12, 0.22, 0 }, Speed = { 1, 2.5 }, Spread = 25, Rise = 3, Emission = 1 },
	Wisps = { Tex = "Smoke", Life = { 0.8, 1.4 }, Size = { 0.25, 0.6, 0.9 }, Speed = { 0.3, 0.8 }, Spread = 180, Rise = 1.2, Emission = 0.8, Fade = 0.55 },
	Soul = { Tex = "Fire", Life = { 0.35, 0.7 }, Size = { 0.35, 0.28, 0 }, Speed = { 0.6, 1.4 }, Spread = 12, Rise = 4, Emission = 1 },
	Sparks = { Tex = "Sparkle", Life = { 0.15, 0.35 }, Size = { 0.2, 0.3, 0 }, Speed = { 4, 8 }, Spread = 180, Rise = -6, Emission = 1 },
	Fog = { Tex = "Smoke", Life = { 1.2, 2.2 }, Size = { 0.4, 1.3, 1.8 }, Speed = { 0.2, 0.6 }, Spread = 180, Rise = 0.35, Emission = 0.35, Fade = 0.6 },
	Flame = { Tex = "Fire", Life = { 0.3, 0.6 }, Size = { 0.6, 0.5, 0 }, Speed = { 1.5, 3 }, Spread = 10, Rise = 5, Emission = 1 },
	Stars = { Tex = "Sparkle", Life = { 0.8, 1.6 }, Size = { 0, 0.22, 0 }, Speed = { 0.2, 0.6 }, Spread = 180, Rise = 0, Emission = 1 },
	Void = { Tex = "Smoke", Life = { 0.8, 1.4 }, Size = { 0.3, 0.8, 1.1 }, Speed = { 0.3, 0.7 }, Spread = 180, Rise = 0.6, Emission = 0, Fade = 0.5 },
	Trail = { Tex = "Sparkle", Life = { 0.3, 0.6 }, Size = { 0.25, 0.15, 0 }, Speed = { 0.2, 0.6 }, Spread = 180, Rise = -0.5, Emission = 1 },
}
E.FXRecipes = RECIPES

local function emitterFor(att: Attachment, kind: string, scale: number)
	local r = RECIPES[kind] or RECIPES.Embers
	local c1 = att:GetAttribute("HwFXColor")
	local c2 = att:GetAttribute("HwFXColor2")
	c1 = typeof(c1) == "Color3" and c1 or Color3.new(1, 1, 1)
	c2 = typeof(c2) == "Color3" and c2 or c1
	local e = Instance.new("ParticleEmitter")
	e.Name = "HwFXEmitter"
	e.Texture = TEX[r.Tex] or TEX.Sparkle
	e.Color = ColorSequence.new(c1, c2)
	e.LightEmission = r.Emission
	e.Lifetime = NumberRange.new(r.Life[1], r.Life[2])
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, r.Size[1] * scale),
		NumberSequenceKeypoint.new(0.35, r.Size[2] * scale),
		NumberSequenceKeypoint.new(1, r.Size[3] * scale),
	})
	local fade = r.Fade or 0.1
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, fade),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(r.Speed[1] * scale, r.Speed[2] * scale)
	e.SpreadAngle = Vector2.new(r.Spread, r.Spread)
	e.Acceleration = Vector3.new(0, r.Rise * scale, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.LockedToPart = false
	e.Rate = 0
	e.Enabled = true
	e.Parent = att
	return e
end

-- the hooks of a model, scanned once per model (weak cache; rescanned if a hook left the model)
local hookCache = setmetatable({}, { __mode = "k" })
local function allHooks(model: Instance): { Attachment }
	local list = hookCache[model]
	if list and (list[1] == nil or list[1]:IsDescendantOf(model)) then
		return list
	end
	list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and d:GetAttribute("HwFX") then
			table.insert(list, d)
		end
	end
	hookCache[model] = list
	return list
end
local function hooksOf(model: Instance, only: any?): { Attachment }
	local list = allHooks(model)
	if not only then
		return list
	end
	local out = {}
	for _, d in ipairs(list) do
		if only[string.sub(d.Name, 6)] then
			table.insert(out, d)
		end
	end
	return out
end
local function scaleOf(model: Instance): number
	local scale = 1
	pcall(function()
		local base = model:GetAttribute("AnimationBaseScale") or 1
		scale = math.clamp((model :: any):GetScale() / base, 0.2, 4)
	end)
	return scale
end

-- Looping ability FX on an event-dog model (kennel copy, companion, preview, reveal): one ParticleEmitter (+ an
-- optional PointLight) per HwFX_* hook. opts: Low (a third of the particles, no lights), Intensity (rate x, default
-- 1), Only ({[hookName] = true}). Returns a handle {Stop(), SetIntensity(k), Burst(n)} or nil (no hooks).
function E.StartFX(model: Instance, opts: any?)
	opts = opts or {}
	if typeof(model) ~= "Instance" then
		return nil
	end
	local hooks = hooksOf(model, opts.Only)
	if #hooks == 0 then
		return nil
	end
	local scale = scaleOf(model)
	local items = {}
	for _, att in ipairs(hooks) do
		local e = emitterFor(att, att:GetAttribute("HwFX"), scale)
		local light = nil
		local lb = tonumber(att:GetAttribute("HwFXLight")) or 0
		if lb > 0 and not opts.Low and (opts.Intensity == nil or opts.Intensity > 0) then
			light = Instance.new("PointLight")
			light.Name = "HwFXLight"
			light.Color = att:GetAttribute("HwFXColor") or Color3.new(1, 1, 1)
			light.Range = 7 * scale
			light.Brightness = lb
			light.Shadows = false
			light.Parent = att
		end
		table.insert(items, { E = e, L = light, Rate = tonumber(att:GetAttribute("HwFXRate")) or 6, B = lb })
	end
	local handle = {}
	function handle.SetIntensity(k: number)
		k = math.max(0, tonumber(k) or 0)
		for _, it in ipairs(items) do
			if it.E.Parent then
				it.E.Rate = it.Rate * k * (opts.Low and 0.35 or 1)
			end
			if it.L and it.L.Parent then
				it.L.Brightness = it.B * math.min(k, 1.5)
			end
		end
	end
	function handle.Burst(n: number?)
		for _, it in ipairs(items) do
			if it.E.Parent then
				it.E:Emit(math.floor((n or 10) * (opts.Low and 0.4 or 1) + 0.5))
			end
		end
	end
	function handle.Stop()
		for _, it in ipairs(items) do
			it.E.Rate = 0
			it.E.Enabled = false
			local e, l = it.E, it.L
			task.delay(2.5, function()
				e:Destroy()
				if l then
					l:Destroy()
				end
			end)
		end
		table.clear(items)
	end
	handle.SetIntensity(opts.Intensity or 1)
	return handle
end

-- One burst from every hook (a find / an ability proc), no lasting emitters. Returns the number of hooks used.
-- One burst from the hooks (a find / an ability proc): one Rate-0 emitter per hook, made on the first burst and reused
-- (no lights, no lasting instances per call). opts: Low / Reduced (40 % of the particles), Only, MaxDistance (default
-- 120 studs: farther or behind the camera = nothing). Returns the number of hooks that emitted.
function E.BurstFX(model: Instance, count: number?, opts: any?): number
	opts = opts or {}
	if typeof(model) ~= "Instance" or not model.Parent then
		return 0
	end
	local camera = workspace.CurrentCamera
	if camera and model:IsA("Model") and model:IsDescendantOf(workspace) then
		local ok, offset = pcall(function()
			return (model :: Model):GetPivot().Position - camera.CFrame.Position
		end)
		if ok then
			local dist = offset.Magnitude
			if dist > (opts.MaxDistance or 120) or (dist > 12 and camera.CFrame.LookVector:Dot(offset / dist) < 0.2) then
				return 0
			end
		end
	end
	local hooks = hooksOf(model, opts.Only)
	local n = math.floor((count or 12) * ((opts.Low or opts.Reduced) and 0.4 or 1) + 0.5)
	if #hooks == 0 or n <= 0 then
		return 0
	end
	local scale = nil
	for _, att in ipairs(hooks) do
		local e = att:FindFirstChild("HwFXBurst")
		if not e then
			scale = scale or scaleOf(model)
			e = emitterFor(att, att:GetAttribute("HwFX"), scale)
			e.Name = "HwFXBurst"
		end
		e:Emit(n)
	end
	return #hooks
end

return E
