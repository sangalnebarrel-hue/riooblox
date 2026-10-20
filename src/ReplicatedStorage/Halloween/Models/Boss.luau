-- THE GRAVEKEEPER models (ReplicatedStorage.Halloween.Models.Boss). Pure builders: the client (BossFX) builds the local
-- boss + minions from them at runtime, the offline previews build them in the Lune sim. Every model is built at the
-- origin facing -Z with its feet on y = 0 and returned ANCHORED. Rigged models carry one invisible `Bone` part per bone
-- (inside a sub-Model named after the bone) linked by Motor6D `Joint` (Part0 = parent bone / Root, Part1 = this bone) and
-- every visual part is welded (Weld, Part0 = bone) to its bone: the client calls Boss.Rig(model) (unanchors everything but
-- the root) and drives Motor6D.Transform; Boss.Pose(model, transforms) does the same maths for anchored previews.
-- API
--   Boss.Build(opts?) -> Model "Gravekeeper" (~26 studs tall, ~40 long). PrimaryPart "Root". Sub-models:
--       Plate_<Slot> (stone armor plates, attrs Slot/Bone; hidden Neon "CrackStage" parts, attr Stage 1..3, that BossFX
--       reveals as the plate wears down), Weak_<Slot> (weak points, hidden until opened: attr Weak=true; WeakCore / WeakGlow
--       / WeakCrack / WeakRim / WeakRing in gold, orange and white),
--       attachments FlamePoint (attrs Color = "Green"|"Purple", Size) for runtime fire particles, and named sockets
--       (Mouth, EyeL, EyeR, Core, Lantern, PawFL/FR/HL/HR, TailTip) on the bone parts.
--   Boss.Skeleton(seed?) -> Model "SkeletonDog" (~3.8 tall; bones Body, Head, Jaw, LegFL, LegFR, LegHL, LegHR, Tail)
--   Boss.Rock(seed?)     -> Model "CursedRock" (~5 studs; PrimaryPart "Root" on the ground, "Core" ~2.3 above it)
--   Boss.Mound(seed?)    -> Model "GraveMound" (~8 wide + a 9.2-stud glowing rune circle; PrimaryPart "Root" on the ground)
--   Boss.Hand(seed?)     -> Model "SkeletonHand" (a bony hand bursting out of a fake mound; pivot at the wrist on y 0)
--   Boss.Slots.Plates / Boss.Slots.Weak : {[slot] = {Bone, Pos (root space, rest pose), Radius}} (server hit boxes)
--   Boss.Joints : ordered bone list {Name, Parent, Pivot}
--   Boss.Rig(model) -> {Root, Motors = {[bone] = Motor6D}, Bones = {[bone] = BasePart}}
--   Boss.Pose(model, transforms) : anchored forward kinematics, transforms = {[bone] = CFrame}
--   Boss.NewRig(name, rootSize, rootCF) -> the rig builder (B:Bone / B:Part / B:Box / B:Ball / B:Ell / B:Cyl / B:Bar /
--       B:Attach / B:Light / B:Fang ...), shared with Models.Finale
--   Boss.Surface(Layout, x, z) -> y, kind : the pit's walkable surface (Floor | Ramp | Terrace | Stairs | Rim)
local Boss = {}

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local PI = math.pi
local SMOOTH = Enum.SurfaceType.Smooth

-- tiny deterministic PRNG (same shapes on every client and offline; Random is not available in every sandbox)
local function newRng(seed: number)
	local state = (math.floor(seed or 1) * 2654435761) % 4294967296
	local r = {}
	function r:NextNumber(a: number?, b: number?): number
		state = (1103515245 * state + 12345) % 2147483648
		local x = state / 2147483648
		if a and b then
			return a + (b - a) * x
		end
		return x
	end
	function r:NextInteger(a: number, b: number): number
		return math.min(b, a + math.floor(r:NextNumber() * (b - a + 1)))
	end
	return r
end
Boss.Rng = newRng

local COL = {
	Bone = RGB(222, 210, 178), BoneLight = RGB(240, 232, 208), BoneDark = RGB(176, 160, 126), BoneShadow = RGB(128, 112, 90),
	Tooth = RGB(236, 226, 190), Claw = RGB(44, 38, 46), ClawTip = RGB(96, 88, 98),
	Stone = RGB(84, 86, 100), StoneDark = RGB(54, 54, 68), StoneLight = RGB(122, 122, 136), StoneWarm = RGB(98, 92, 96),
	Moss = RGB(70, 104, 60), MossDark = RGB(48, 74, 44), Dirt = RGB(58, 44, 38), DirtDark = RGB(38, 30, 28), Root = RGB(66, 46, 34),
	Iron = RGB(58, 60, 70), IronDark = RGB(36, 38, 46), Rust = RGB(122, 70, 46),
	Green = RGB(120, 255, 110), GreenHot = RGB(206, 255, 196), GreenDeep = RGB(36, 190, 90),
	Purple = RGB(176, 92, 240), PurpleHot = RGB(232, 196, 255), PurpleDeep = RGB(104, 36, 196),
	Socket = RGB(14, 8, 20), Crack = RGB(34, 26, 28), Ink = RGB(18, 10, 28),
	-- weak points only: molten gold / pumpkin orange / white (used nowhere else on the boss, so an open weak point never
	-- blends into the green soul fire and the purple runes)
	WeakHot = RGB(255, 236, 150), WeakGold = RGB(255, 200, 70), Weak = RGB(255, 128, 24), WeakRim = RGB(255, 246, 222),
}
Boss.Colors = COL

-- correct lookAt everywhere (Lune's CFrame.lookAt is broken; this one uses fromMatrix)
local function look(at: Vector3, target: Vector3, up: Vector3?): CFrame
	local f = target - at
	if f.Magnitude < 1e-6 then
		return CF(at)
	end
	f = f.Unit
	local u = up or V3(0, 1, 0)
	local r = f:Cross(u)
	if r.Magnitude < 1e-4 then
		r = f:Cross(V3(0, 0, -1))
		if r.Magnitude < 1e-4 then
			r = f:Cross(V3(1, 0, 0))
		end
	end
	r = r.Unit
	return CFrame.fromMatrix(at, r, r:Cross(f).Unit, -f)
end
Boss.Look = look

---------------------------------------------------------------------------------------------------------------------
-- rig builder
---------------------------------------------------------------------------------------------------------------------
local B = {}
B.__index = B

local function newRig(name: string, rootSize: Vector3, rootCF: CFrame)
	local self = setmetatable({}, B)
	local model = Instance.new("Model")
	model.Name = name
	self.Model = model
	self.Bones = {}
	self.Count = 0
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = rootSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	self.Root = root
	return self
end
-- the rig builder is shared with the finale models (Models.Finale: the Black Bell, the ghost dogs, THE LAST BARK, the
-- Gravekeeper's spirit): Boss.NewRig(name, rootSize, rootCF) -> builder with the B:* methods below
Boss.NewRig = function(name: string, rootSize: Vector3, rootCF: CFrame)
	return newRig(name, rootSize, rootCF)
end

-- a bone: sub-model + invisible pivot part, Motor6D from the parent bone (or the root)
function B:Bone(name: string, parent: string?, pivot: Vector3)
	local group = Instance.new("Model")
	group.Name = name
	group.Parent = self.Model
	local bone = Instance.new("Part")
	bone.Name = "Bone"
	bone.Size = V3(.4, .4, .4)
	bone.CFrame = CF(pivot)
	bone.Transparency = 1
	bone.Anchored = true
	bone.CanCollide = false
	bone.CanQuery = false
	bone.CanTouch = false
	bone.CastShadow = false
	bone.Parent = group
	local parentPart = parent and self.Bones[parent].Part or self.Root
	local joint = Instance.new("Motor6D")
	joint.Name = "Joint"
	joint.Part0 = parentPart
	joint.Part1 = bone
	joint.C0 = parentPart.CFrame:Inverse() * CF(pivot)
	joint.C1 = CF()
	joint.Parent = bone
	self.Bones[name] = { Part = bone, Group = group, Parent = parent, Pivot = pivot }
	return group
end

function B:Group(bone: string, name: string, attrs: { [string]: any }?): Model
	local g = Instance.new("Model")
	g.Name = name
	for k, v in pairs(attrs or {}) do
		g:SetAttribute(k, v)
	end
	g:SetAttribute("Bone", bone)
	g.Parent = self.Bones[bone].Group
	return g
end

-- o: Class, Shape, T (transparency), Refl, Mesh ("Sphere"), Group (Model), Shadow
function B:Part(bone: string, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, o: { [string]: any }?): BasePart
	o = o or {}
	if self.Xform then
		cf = self.Xform * cf
	end
	local p = Instance.new(o.Class or "Part")
	p.Name = name
	if o.Shape then
		(p :: any).Shape = o.Shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or MAT.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	if o.Shadow ~= nil then
		p.CastShadow = o.Shadow
	else
		p.CastShadow = (mat ~= MAT.Neon) and (size.X + size.Y + size.Z) > 3.2
	end
	if o.T then
		p.Transparency = o.T
	end
	if o.Refl then
		p.Reflectance = o.Refl
	end
	if o.Mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType[o.Mesh]
		m.Parent = p
	end
	local bonePart = self.Bones[bone].Part
	local w = Instance.new("Weld")
	w.Name = "W"
	w.Part0 = bonePart
	w.Part1 = p
	w.C0 = bonePart.CFrame:Inverse() * cf
	w.C1 = CF()
	w.Parent = p
	p.Parent = o.Group or self.Bones[bone].Group
	self.Count += 1
	return p
end

function B:Box(bone, name, size, cf, color, mat, o)
	return self:Part(bone, name, size, cf, color, mat, o)
end

function B:Ball(bone, name, d: number, pos: Vector3, color, mat, o)
	o = o or {}
	o.Shape = Enum.PartType.Ball
	return self:Part(bone, name, V3(d, d, d), CF(pos), color, mat, o)
end

function B:Ell(bone, name, size: Vector3, cf: CFrame, color, mat, o)
	o = o or {}
	o.Mesh = "Sphere"
	return self:Part(bone, name, size, cf, color, mat, o)
end

function B:Wedge(bone, name, size, cf, color, mat, o)
	o = o or {}
	o.Class = "WedgePart"
	return self:Part(bone, name, size, cf, color, mat, o)
end

function B:Corner(bone, name, size, cf, color, mat, o)
	o = o or {}
	o.Class = "CornerWedgePart"
	return self:Part(bone, name, size, cf, color, mat, o)
end

-- cylinder between two points
function B:Cyl(bone, name, a: Vector3, b: Vector3, d: number, color, mat, o)
	o = o or {}
	o.Shape = Enum.PartType.Cylinder
	local len = math.max(.05, (b - a).Magnitude)
	return self:Part(bone, name, V3(len, d, d), look((a + b) / 2, b) * ANG(0, PI / 2, 0), color, mat, o)
end

-- box between two points (w = across, h = along `up`)
function B:Bar(bone, name, a: Vector3, b: Vector3, w: number, h: number, color, mat, o, up: Vector3?)
	local len = math.max(.05, (b - a).Magnitude)
	return self:Part(bone, name, V3(w, h, len), look((a + b) / 2, b, up), color, mat, o)
end

function B:Attach(bone: string, name: string, pos: Vector3, attrs: { [string]: any }?): Attachment
	local bonePart = self.Bones[bone].Part
	if self.Xform then
		pos = (self.Xform * CF(pos)).Position
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = bonePart.CFrame:Inverse() * CF(pos)
	for k, v in pairs(attrs or {}) do
		a:SetAttribute(k, v)
	end
	a.Parent = bonePart
	return a
end

function B:Light(bone: string, pos: Vector3, color: Color3, range: number, brightness: number, name: string?)
	local bonePart = self.Bones[bone].Part
	local holder = self:Part(bone, name or "GlowLight", V3(.2, .2, .2), CF(pos), color, MAT.SmoothPlastic, { T = 1, Shadow = false })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = holder
	local _ = bonePart
	return l
end

---------------------------------------------------------------------------------------------------------------------
-- reusable details
---------------------------------------------------------------------------------------------------------------------
-- long bone: shaft + knobbly ends (+ optional crack)
function B:LongBone(bone, name, a: Vector3, b: Vector3, d: number, color: Color3?, o: { [string]: any }?)
	o = o or {}
	local c = color or COL.Bone
	self:Cyl(bone, name, a, b, d, c, MAT.SmoothPlastic)
	local dir = (b - a).Unit
	local side = dir:Cross(V3(0, 1, 0))
	if side.Magnitude < .1 then
		side = V3(1, 0, 0)
	end
	side = side.Unit
	local k = o.Knob or 1.32
	for _, e in ipairs({ { a, 1 }, { b, -1 } }) do
		local p, s = e[1], e[2]
		self:Ball(bone, name .. "Knob", d * k, p + dir * d * .12 * s + side * d * .22, COL.BoneLight, MAT.SmoothPlastic)
		self:Ball(bone, name .. "Knob", d * k * .9, p + dir * d * .12 * s - side * d * .24, c, MAT.SmoothPlastic)
	end
	if o.Crack then
		local m = a:Lerp(b, o.Crack)
		local n = side:Cross(dir).Unit
		local outward = (o.Out or n)
		self:Bar(bone, name .. "Crack", m + outward * d * .5 - dir * d * .55, m + outward * d * .5 + dir * d * .5 + side * d * .2, .09, .1,
			COL.Crack, MAT.SmoothPlastic, { Shadow = false })
	end
	if o.Groove then
		self:Cyl(bone, name .. "Groove", a:Lerp(b, .2), a:Lerp(b, .8), d * .78, COL.BoneDark, MAT.SmoothPlastic)
	end
end

-- iron chain along a list of points (links alternate orientation)
function B:Chain(bone, name, pts: { Vector3 }, link: number?, group: Model?)
	local len = link or .9
	local k = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local seg = (b - a).Magnitude
		local n = math.max(1, math.floor(seg / (len * .78) + .5))
		for j = 1, n do
			local p0 = a:Lerp(b, (j - 1) / n)
			local p1 = a:Lerp(b, j / n)
			k += 1
			local part = self:Bar(bone, name, p0, p1, .26, len * .62, COL.Iron, MAT.CorrodedMetal, { Group = group, Shadow = false })
			part.Size = V3(.26, len * .62, (p1 - p0).Magnitude + .18)
			if k % 2 == 0 then
				part.CFrame = part.CFrame * ANG(0, 0, PI / 2)
				local w = part:FindFirstChild("W") :: Weld
				if w then
					w.C0 = self.Bones[bone].Part.CFrame:Inverse() * part.CFrame
				end
			end
		end
	end
end

-- sagging curve between two points
local function sag(a: Vector3, b: Vector3, depth: number, n: number): { Vector3 }
	local out = {}
	for i = 0, n do
		local t = i / n
		table.insert(out, a:Lerp(b, t) - V3(0, math.sin(t * PI) * depth, 0))
	end
	return out
end
Boss.Sag = sag

-- stacked neon flame tuft (+ FlamePoint attachment for runtime particles)
function B:Flame(bone, pos: Vector3, s: number, kind: string, lean: Vector3?, group: Model?)
	local green = kind ~= "Purple"
	local hot = green and COL.GreenHot or COL.PurpleHot
	local mid = green and COL.Green or COL.Purple
	local deep = green and COL.GreenDeep or COL.PurpleDeep
	local l = lean or V3(0, 0, 0)
	local o = { Group = group, Shadow = false }
	self:Ball(bone, "FlameCore", s * 1.05, pos, hot, MAT.Neon, { Group = group, Shadow = false })
	self:Ell(bone, "Flame", V3(s * 1.1, s * 2.1, s * 1.1), CF(pos + V3(0, s * .8, 0) + l * .4) * ANG(l.Z * .5, 0, -l.X * .5), mid, MAT.Neon, o)
	self:Ell(bone, "FlameTip", V3(s * .55, s * 1.7, s * .55), CF(pos + V3(0, s * 1.9, 0) + l) * ANG(l.Z, 0, -l.X), deep, MAT.Neon,
		{ Group = group, Shadow = false })
	self:Ell(bone, "FlameLick", V3(s * .4, s * 1.1, s * .4), CF(pos + V3(s * .45, s * 1.15, s * .2) + l * .6) * ANG(l.Z, 0, -l.X - .5), mid,
		MAT.Neon, { Group = group, Shadow = false })
	self:Ell(bone, "FlameHalo", V3(s * 1.9, s * 3.2, s * 1.9), CF(pos + V3(0, s * 1.0, 0) + l * .5), mid, MAT.Neon,
		{ Group = group, Shadow = false, T = .72 })
	self:Attach(bone, "FlamePoint", pos + V3(0, s * .6, 0), { Color = green and "Green" or "Purple", Size = s })
end

-- fang made of two wedges (isosceles), pointing along `dir` (down for upper teeth, up for lower)
function B:Fang(bone, name, base: Vector3, len: number, w: number, t: number, down: boolean, color: Color3?)
	local c = color or COL.Tooth
	local y = down and -1 or 1
	local mid = base + V3(0, y * len / 2, 0)
	if down then
		self:Wedge(bone, name, V3(t, len, w / 2), CF(mid + V3(0, 0, -w / 4)) * ANG(PI, 0, 0), c, MAT.SmoothPlastic, { Shadow = false })
		self:Wedge(bone, name, V3(t, len, w / 2), CF(mid + V3(0, 0, w / 4)) * ANG(PI, PI, 0), c, MAT.SmoothPlastic, { Shadow = false })
	else
		self:Wedge(bone, name, V3(t, len, w / 2), CF(mid + V3(0, 0, w / 4)), c, MAT.SmoothPlastic, { Shadow = false })
		self:Wedge(bone, name, V3(t, len, w / 2), CF(mid + V3(0, 0, -w / 4)) * ANG(0, PI, 0), c, MAT.SmoothPlastic, { Shadow = false })
	end
end

-- hooked claw: 3 tapering segments from `base` forward along `fwd`, curling down to the ground
function B:Claw(bone, name, base: Vector3, fwd: Vector3, len: number, d: number)
	local f = V3(fwd.X, 0, fwd.Z).Unit
	local p0 = base
	local p1 = base + f * len * .38 + V3(0, len * .14, 0)
	local p2 = base + f * len * .74 + V3(0, len * .02, 0)
	local p3 = base + f * len * .96 + V3(0, -len * .3, 0)
	self:Bar(bone, name, p0, p1, d, d * 1.15, COL.Claw, MAT.SmoothPlastic)
	self:Bar(bone, name, p1, p2, d * .8, d * .95, COL.Claw, MAT.SmoothPlastic)
	self:Bar(bone, name .. "Tip", p2, p3, d * .5, d * .6, COL.ClawTip, MAT.SmoothPlastic)
end

-- crack line drawn flush on a surface (from a to b, pushed out along n)
function B:CrackLine(bone, a: Vector3, b: Vector3, n: Vector3, color: Color3?, neon: boolean?, group: Model?)
	local o = { Shadow = false, Group = group }
	return self:Bar(bone, neon and "GlowCrack" or "Crack", a + n * .04, b + n * .04, .1, .08, color or COL.Crack, neon and MAT.Neon or MAT.SmoothPlastic, o, n)
end

-- vertebra: body (cylinder along the spine) + dorsal spine + transverse processes
function B:Vertebra(bone, pos: Vector3, axis: Vector3, d: number, spine: number, lean: number?, stone: boolean?)
	local ax = axis.Unit
	self:Cyl(bone, "Vertebra", pos - ax * d * .28, pos + ax * d * .28, d, COL.Bone, MAT.SmoothPlastic)
	self:Cyl(bone, "Disc", pos + ax * d * .3, pos + ax * d * .42, d * .78, COL.BoneShadow, MAT.SmoothPlastic, { Shadow = false })
	if spine > 0 then
		local up = V3(0, 1, 0)
		local top = pos + up * (d * .4 + spine) + ax * (lean or 0) * spine
		self:Bar(bone, "DorsalSpine", pos + up * d * .3, top, d * .26, d * .55, COL.BoneLight, MAT.SmoothPlastic, nil, ax)
		self:Ball(bone, "SpineTip", d * .32, top, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
	end
	local side = ax:Cross(V3(0, 1, 0))
	if side.Magnitude > .1 then
		side = side.Unit
		self:Bar(bone, "Transverse", pos - side * d * 1.05, pos + side * d * 1.05, d * .24, d * .22, COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
	end
	if stone then
		self:Box(bone, "FusedStone", V3(d * .9, d * .45, d * .8), CF(pos + V3(0, d * .45, 0)) * ANG(.2, .4, -.15), COL.StoneDark, MAT.Slate)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- THE GRAVEKEEPER
---------------------------------------------------------------------------------------------------------------------
Boss.Joints = {
	{ "Pelvis", nil, V3(0, 13.5, 8) },
	{ "Chest", "Pelvis", V3(0, 15.6, 1.6) },
	{ "Neck", "Chest", V3(0, 17.2, -9.4) },
	{ "Head", "Neck", V3(0, 18.4, -14) },
	{ "Jaw", "Head", V3(0, 16.5, -15.4) },
	{ "ArmR", "Chest", V3(5.2, 14.6, -7.5) }, { "ForeR", "ArmR", V3(5.6, 8.2, -6.6) }, { "PawR", "ForeR", V3(5.6, 2.6, -8.6) },
	{ "ArmL", "Chest", V3(-5.2, 14.6, -7.5) }, { "ForeL", "ArmL", V3(-5.6, 8.2, -6.6) }, { "PawL", "ForeL", V3(-5.6, 2.6, -8.6) },
	{ "ThighR", "Pelvis", V3(4.6, 12.8, 9) }, { "ShinR", "ThighR", V3(5.0, 7.4, 5.8) }, { "FootR", "ShinR", V3(5.0, 3.6, 11.2) },
	{ "ThighL", "Pelvis", V3(-4.6, 12.8, 9) }, { "ShinL", "ThighL", V3(-5.0, 7.4, 5.8) }, { "FootL", "ShinL", V3(-5.0, 3.6, 11.2) },
	{ "Tail1", "Pelvis", V3(0, 14.4, 12.6) }, { "Tail2", "Tail1", V3(0, 13.0, 16.0) }, { "Tail3", "Tail2", V3(.6, 10.6, 19.0) },
	{ "Tail4", "Tail3", V3(1.6, 7.8, 21.2) },
}

-- the neck, skull and jaw are built level and then tilted nose-down about the neck joint (menacing, low-slung head that
-- leaves the gravestone ridge visible from the front)
local NECK_PIVOT = V3(0, 17.2, -9.4)
local NECK_XF = CF(NECK_PIVOT) * ANG(-.2, 0, 0) * CF(-NECK_PIVOT)
Boss.NeckTilt = NECK_XF
for _, j in ipairs(Boss.Joints) do
	if j[1] == "Head" or j[1] == "Jaw" then
		j[3] = (NECK_XF * CF(j[3])).Position
	end
end

-- hit boxes (root space, rest pose). Plates: stone armor broken with timing hits; Weak: open briefly while ENRAGED.
Boss.Slots = {
	Plates = {
		ShoulderL = { Bone = "ArmL", Pos = V3(-6.3, 14.6, -7.3), Radius = 3.4 },
		ShoulderR = { Bone = "ArmR", Pos = V3(6.3, 14.6, -7.3), Radius = 3.4 },
		HipL = { Bone = "Pelvis", Pos = V3(-4.9, 14.2, 9.6), Radius = 3.2 },
		HipR = { Bone = "Pelvis", Pos = V3(4.9, 14.2, 9.6), Radius = 3.2 },
		BracerL = { Bone = "ForeL", Pos = V3(-5.7, 5.4, -7.6), Radius = 2.6 },
		BracerR = { Bone = "ForeR", Pos = V3(5.7, 5.4, -7.6), Radius = 2.6 },
	},
	PlateOrder = { "ShoulderL", "ShoulderR", "BracerL", "BracerR", "HipL", "HipR" },
	Weak = {
		Heart = { Bone = "Chest", Pos = V3(0, 11.4, -3.6), Radius = 2.6 },
		Throat = { Bone = "Neck", Pos = (NECK_XF * CF(0, 16.0, -11.8)).Position, Radius = 2.2 },
		Spine = { Bone = "Pelvis", Pos = V3(0, 13.4, 5.0), Radius = 2.2 },
	},
	WeakOrder = { "Heart", "Throat", "Spine" },
}

local function spineY(z: number): number
	local pts = { { -10, 17.0 }, { -7, 17.7 }, { -4, 17.9 }, { -1, 17.6 }, { 2, 16.9 }, { 5, 15.9 }, { 8, 15.2 }, { 11, 14.8 } }
	if z <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		if z <= pts[i][1] then
			local a, b = pts[i - 1], pts[i]
			return a[2] + (b[2] - a[2]) * (z - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- hidden crack stages (part name "CrackStage", attribute Stage = 1..3, built at Transparency 1): BossFX reveals stage s
-- once the plate's wear (State.Boss.PlateWear, 0..9) reaches 3 / 6 / 8: fine green seams -> spreading cracks -> a hot
-- fissure. segs = {{face CFrame (local -Z = out), x0, y0, x1, y1}} in face units (x * w, y * h)
local STAGE_COL = { COL.GreenDeep, COL.Green, COL.GreenHot }
local function crackStage(b, bone: string, g: Model, stage: number, segs: { { any } }, w: number, h: number)
	for _, s in ipairs(segs) do
		local fcf: CFrame = s[1]
		local a = (fcf * CF(s[2] * w, s[3] * h, 0)).Position
		local c = (fcf * CF(s[4] * w, s[5] * h, 0)).Position
		local p = b:Bar(bone, "CrackStage", a, c, stage == 3 and .2 or .13, .1, STAGE_COL[stage], MAT.Neon, { Group = g, Shadow = false, T = 1 },
			fcf.LookVector)
		p:SetAttribute("Stage", stage)
	end
end

-- stone armor plate (sub-model Plate_<slot>) facing `normal`
local function plate(b, bone: string, slot: string, center: Vector3, normal: Vector3, size: Vector3, up: Vector3?, rng: any)
	-- curved stone shell: 3 slabs on an arc around the local X axis (like a pauldron), layered face, iron band, rivets,
	-- a glowing purple rune and a green crack on the middle slab, chipped rim and moss on the top slab
	local g = b:Group(bone, "Plate_" .. slot, { Slot = slot, Plate = true })
	local n = normal.Unit
	local cf = look(center, center + n, up)
	local w, h, t = size.X, size.Y, size.Z
	local R = h * .62
	local segs = { { .62, h * .4, COL.Stone }, { 0, h * .44, COL.StoneDark }, { -.5, h * .36, COL.Stone } }
	local mid
	for k, sg in ipairs(segs) do
		local scf = cf * CF(0, 0, R) * ANG(sg[1], 0, 0) * CF(0, 0, -R)
		local slab = b:Box(bone, "PlateSlab", V3(w * (k == 2 and 1 or .94), sg[2] + .35, t), scf, sg[3], MAT.Slate, { Group = g })
		b:Box(bone, "PlateFace", V3(w * .8, sg[2] * .72, t * .4), scf * CF(0, 0, -t * .5), k == 2 and COL.Stone or COL.StoneLight, MAT.Slate,
			{ Group = g, Shadow = false })
		if k == 2 then
			mid = scf
		end
		local _ = slab
	end
	local topcf = cf * CF(0, 0, R) * ANG(.62, 0, 0) * CF(0, 0, -R)
	b:Box(bone, "PlateRim", V3(w * .98, .4, t + .25), topcf * CF(0, segs[1][2] / 2 + .1, 0), COL.StoneLight, MAT.Slate, { Group = g, Shadow = false })
	local botcf = cf * CF(0, 0, R) * ANG(-.5, 0, 0) * CF(0, 0, -R)
	b:Box(bone, "PlateRim", V3(w * .9, .4, t + .2), botcf * CF(0, -segs[3][2] / 2 - .05, -.1), COL.StoneWarm, MAT.Slate, { Group = g, Shadow = false })
	-- iron band + rivets (middle slab)
	b:Box(bone, "PlateBand", V3(w + .3, .55, t + .35), mid * CF(0, h * .1, 0), COL.Iron, MAT.CorrodedMetal, { Group = g })
	for _, sx in ipairs({ -1, 1 }) do
		b:Ball(bone, "Rivet", .5, (mid * CF(sx * w * .42, h * .1, -t * .62)).Position, COL.Rust, MAT.CorrodedMetal, { Group = g, Shadow = false })
		b:Ball(bone, "Rivet", .36, (topcf * CF(sx * w * .38, 0, -t * .6)).Position, COL.IronDark, MAT.CorrodedMetal, { Group = g, Shadow = false })
		b:Ball(bone, "Rivet", .36, (botcf * CF(sx * w * .36, 0, -t * .6)).Position, COL.IronDark, MAT.CorrodedMetal, { Group = g, Shadow = false })
	end
	-- purple rune (crescent + slash) and a green glow crack
	local face = -t * .74
	local hh = h * .44
	local glyph = { { V3(-.2, .3, 0), V3(-.06, .06, 0) }, { V3(-.06, .06, 0), V3(-.13, -.18, 0) }, { V3(-.13, -.18, 0), V3(.04, -.36, 0) },
		{ V3(.14, .26, 0), V3(.24, -.3, 0) } }
	for _, seg in ipairs(glyph) do
		local a = (mid * CF(seg[1].X * w, seg[1].Y * hh * 2 - hh * .2, face)).Position
		local c = (mid * CF(seg[2].X * w, seg[2].Y * hh * 2 - hh * .2, face)).Position
		b:Bar(bone, "Rune", a, c, .2, .1, COL.Purple, MAT.Neon, { Group = g, Shadow = false }, mid.LookVector * -1)
	end
	local ca = (topcf * CF(w * .3, 0, face)).Position
	local cb = (mid * CF(w * .2, -hh * .1, face)).Position
	local cc = (botcf * CF(w * .34, 0, face)).Position
	b:Bar(bone, "GlowCrack", ca, cb, .14, .1, COL.Green, MAT.Neon, { Group = g, Shadow = false }, n)
	b:Bar(bone, "GlowCrack", cb, cc, .12, .1, COL.Green, MAT.Neon, { Group = g, Shadow = false }, n)
	-- chipped corner + moss on the top
	b:Box(bone, "Chip", V3(w * .18, .5, t * .6), topcf * CF(-w * .4, segs[1][2] * .3, -t * .45) * ANG(0, 0, .6), COL.Crack, MAT.Slate,
		{ Group = g, Shadow = false })
	b:Box(bone, "PlateMoss", V3(w * .55, .2, t * .9), topcf * CF(rng:NextNumber(-.15, .15) * w, segs[1][2] / 2 + .3, .05), COL.Moss, MAT.Grass,
		{ Group = g, Shadow = false })
	-- crack stages across the three slab faces (hidden until the plate wears down)
	local fm, ft, fb = mid * CF(0, 0, -t * .75), topcf * CF(0, 0, -t * .75), botcf * CF(0, 0, -t * .75)
	local hu = h * .16
	crackStage(b, bone, g, 1, { { fm, -.04, .1, -.26, .62 }, { fm, -.04, .1, .18, -.4 }, { fm, .18, -.4, .33, -.75 } }, w, hu)
	crackStage(b, bone, g, 2, { { fm, -.26, .62, -.34, .9 }, { ft, -.3, -.6, .06, .35 }, { ft, .06, .35, .2, .8 }, { fb, .12, .7, -.18, -.2 } }, w, hu)
	crackStage(b, bone, g, 3, { { ft, .28, -.75, .34, .6 }, { fm, -.36, -.25, .02, .2 }, { fm, .02, .2, .36, -.05 }, { fb, -.34, .5, -.06, -.6 },
		{ fb, -.06, -.6, .2, -.75 } }, w, hu)
	b:Attach(bone, "PlateCenter", (mid * CF(0, 0, -t * .8)).Position, { Slot = slot })
	return g
end

-- gravestone on the back (style 1 arch slab, 2 cross, 3 obelisk, 4 broken slab), base buried in a dirt clump
local function gravestone(b, bone: string, base: Vector3, style: number, height: number, yaw: number, tilt: number, roll: number, rng: any)
	local g = b:Group(bone, "Gravestone" .. style)
	local o = { Group = g }
	local cf = CF(base) * ANG(0, yaw, 0) * ANG(tilt, 0, roll)
	local stone = COL.Stone:Lerp(COL.StoneDark, rng:NextNumber(0, .4))
	local top
	if style == 1 then
		local w = 4.4
		local slab = height - w / 2
		b:Box(bone, "GraveSlab", V3(w, slab, 1.2), cf * CF(0, slab / 2, 0), stone, MAT.Slate, o)
		b:Part(bone, "GraveArch", V3(1.2, w, w), cf * CF(0, slab, 0) * ANG(0, PI / 2, 0), stone, MAT.Slate,
			{ Group = g, Shape = Enum.PartType.Cylinder })
		-- carved border + R.I.P. bars + glowing crescent
		b:Box(bone, "GraveCarve", V3(w * .8, .14, .1), cf * CF(0, slab * .78, -.62), COL.Crack, MAT.Slate, { Group = g, Shadow = false })
		b:Box(bone, "GraveCarve", V3(w * .8, .14, .1), cf * CF(0, slab * .22, -.62), COL.Crack, MAT.Slate, { Group = g, Shadow = false })
		for i = 0, 4 do
			local a = PI * (.15 + i * .14)
			local r = 1.0
			local p0 = cf * CF(math.cos(a) * r, slab + .2 + math.sin(a) * r * .9 - 1.0, -.64)
			local a2 = PI * (.15 + (i + 1) * .14)
			local p1 = cf * CF(math.cos(a2) * r, slab + .2 + math.sin(a2) * r * .9 - 1.0, -.64)
			b:Bar(bone, "GraveRune", p0.Position, p1.Position, .2, .14, COL.Purple, MAT.Neon, { Group = g, Shadow = false })
		end
		local slabPart = g:FindFirstChild("GraveSlab")
		if slabPart then
			local sg = Instance.new("SurfaceGui")
			sg.Name = "Engraving"
			sg.Face = Enum.NormalId.Front
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 24
			sg.LightInfluence = 1
			sg.MaxDistance = 260
			sg:SetAttribute("NoTranslate", true)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(.86, .34)
			t.Position = UDim2.fromScale(.07, .3)
			t.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
			t.TextScaled = true
			t.Text = "R.I.P."
			t.TextColor3 = COL.Ink
			t.TextTransparency = .25
			t:SetAttribute("NoTranslate", true)
			t.Parent = sg
			sg.Parent = slabPart
		end
		top = slab + w / 2
	elseif style == 2 then
		b:Box(bone, "GraveCross", V3(1.2, height, 1.1), cf * CF(0, height / 2, 0), stone, MAT.Slate, o)
		b:Box(bone, "GraveCross", V3(4.0, 1.1, 1.1), cf * CF(0, height * .7, 0), stone, MAT.Slate, { Group = g })
		b:Box(bone, "CrossCap", V3(1.4, .3, 1.3), cf * CF(0, height + .1, 0), COL.StoneLight, MAT.Slate, { Group = g, Shadow = false })
		for _, sx in ipairs({ -1, 1 }) do
			b:Box(bone, "CrossCap", V3(.3, 1.3, 1.3), cf * CF(sx * 2.05, height * .7, 0), COL.StoneLight, MAT.Slate, { Group = g, Shadow = false })
		end
		b:Ball(bone, "CrossGem", .7, (cf * CF(0, height * .7, -.56)).Position, COL.Green, MAT.Neon, { Group = g, Shadow = false })
		top = height
	elseif style == 3 then
		local w = 3.4
		b:Box(bone, "GraveObelisk", V3(w, height - 1.8, 1.4), cf * CF(0, (height - 1.8) / 2, 0), stone, MAT.Slate, o)
		b:Wedge(bone, "GravePoint", V3(w, 1.8, .7), cf * CF(0, height - .9, -.35), stone, MAT.Slate, { Group = g })
		b:Wedge(bone, "GravePoint", V3(w, 1.8, .7), cf * CF(0, height - .9, .35) * ANG(0, PI, 0), stone, MAT.Slate, { Group = g })
		b:Box(bone, "GraveBandTop", V3(w + .3, .35, 1.7), cf * CF(0, height - 2.0, 0), COL.StoneLight, MAT.Slate, { Group = g, Shadow = false })
		-- carved paw print (glowing)
		local face = cf * CF(0, height * .45, -.72)
		b:Ball(bone, "PawPad", .9, face.Position, COL.Purple, MAT.Neon, { Group = g, Shadow = false })
		for i, dx in ipairs({ -.65, -.22, .22, .65 }) do
			local dy = (i == 1 or i == 4) and .55 or .85
			b:Ball(bone, "PawToe", .38, (face * CF(dx, dy, 0)).Position, COL.Purple, MAT.Neon, { Group = g, Shadow = false })
		end
		top = height
	else
		local w = 3.8
		b:Box(bone, "GraveBroken", V3(w, height * .78, 1.1), cf * CF(0, height * .39, 0), stone, MAT.Slate, o)
		b:Corner(bone, "GraveShard", V3(w * .55, height * .3, 1.1), cf * CF(-w * .22, height * .78 + height * .15, 0), stone, MAT.Slate,
			{ Group = g })
		b:Wedge(bone, "GraveShard", V3(1.1, height * .22, w * .42), cf * CF(w * .28, height * .78 + height * .11, 0) * ANG(0, PI / 2, 0), stone,
			MAT.Slate, { Group = g })
		b:Box(bone, "GraveCarve", V3(w * .6, .14, .1), cf * CF(0, height * .45, -.57), COL.Crack, MAT.Slate, { Group = g, Shadow = false })
		top = height
	end
	-- cracks + moss
	b:CrackLine(bone, (cf * CF(-1.0, top * .55, -.62)).Position, (cf * CF(-.3, top * .3, -.62)).Position, (cf.LookVector * -1), COL.Crack, false, g)
	b:CrackLine(bone, (cf * CF(-.3, top * .3, -.62)).Position, (cf * CF(-.6, top * .12, -.62)).Position, (cf.LookVector * -1), COL.Crack, false, g)
	b:Box(bone, "GraveMoss", V3(2.2, .22, 1.3), cf * CF(rng:NextNumber(-.6, .6), top * .62, .1), COL.Moss, MAT.Grass, { Group = g, Shadow = false })
	-- dirt clump the stone is buried in (+ roots and a stray bone)
	for i = 1, 4 do
		local a = i / 4 * PI * 2 + rng:NextNumber(-.3, .3)
		local p = base + V3(math.cos(a) * 1.7, -.2 + rng:NextNumber(-.1, .3), math.sin(a) * 1.2)
		b:Ell(bone, "GraveDirt", V3(rng:NextNumber(2.2, 3.0), rng:NextNumber(1.1, 1.5), rng:NextNumber(1.8, 2.4)), CF(p) * ANG(0, a, 0),
			i % 2 == 0 and COL.Dirt or COL.DirtDark, MAT.Ground, { Group = g })
	end
	b:Box(bone, "GraveMossClump", V3(2.6, .3, 1.8), CF(base + V3(.4, .45, .3)) * ANG(0, .5, 0), COL.MossDark, MAT.Grass, { Group = g, Shadow = false })
	return g, cf, top
end

function Boss.Build(opts: { [string]: any }?): Model
	opts = opts or {}
	local rng = newRng(opts.Seed or 1031)
	local b = newRig("Gravekeeper", V3(4, 2, 4), CF(0, 1, 0))
	for _, j in ipairs(Boss.Joints) do
		b:Bone(j[1], j[2], j[3])
	end
	local up = V3(0, 1, 0)

	-------------------------------------------------------------------------------- pelvis + lumbar spine
	for _, z in ipairs({ 2.6, 3.9, 5.2, 6.5 }) do
		b:Vertebra("Pelvis", V3(0, spineY(z) - .7, z), V3(0, -.12, 1), 2.0, 1.1 - (z - 2.6) * .1, .25, z == 3.9)
	end
	b:Ell("Pelvis", "Sacrum", V3(2.8, 1.9, 4.6), CF(0, 14.6, 10.0) * ANG(-.12, 0, 0), COL.BoneDark, MAT.SmoothPlastic)
	b:Vertebra("Pelvis", V3(0, 15.0, 8.8), V3(0, -.1, 1), 1.9, .9, .3)
	b:Vertebra("Pelvis", V3(0, 14.8, 11.0), V3(0, -.12, 1), 1.7, .7, .3, true)
	for _, s in ipairs({ 1, -1 }) do
		-- ilium blade, ischium, pubis, hip socket
		b:Box("Pelvis", "Ilium", V3(.8, 3.4, 5.0), CF(2.5 * s, 14.0, 9.2) * ANG(.25, 0, -.42 * s), COL.Bone, MAT.SmoothPlastic)
		b:Box("Pelvis", "IliumEdge", V3(.9, .5, 5.2), CF(2.95 * s, 15.55, 9.4) * ANG(.25, 0, -.42 * s), COL.BoneLight, MAT.SmoothPlastic)
		b:Bar("Pelvis", "Ischium", V3(2.6 * s, 12.4, 10.0), V3(1.4 * s, 11.6, 13.0), .9, .8, COL.Bone, MAT.SmoothPlastic)
		b:Bar("Pelvis", "Pubis", V3(3.0 * s, 12.0, 8.4), V3(.2 * s, 11.2, 9.6), .8, .7, COL.BoneDark, MAT.SmoothPlastic)
		b:Ball("Pelvis", "HipSocket", 1.9, V3(4.1 * s, 12.8, 9.0), COL.BoneShadow, MAT.SmoothPlastic)
		plate(b, "Pelvis", s > 0 and "HipR" or "HipL", V3(4.5 * s, 14.4, 9.6), V3(.85 * s, .55, .1), V3(5.6, 4.4, 1.3), up, rng)
	end
	b:CrackLine("Pelvis", V3(-1.0, 15.6, 9.6), V3(-.2, 15.3, 11.6), V3(0, 1, 0))

	-------------------------------------------------------------------------------- chest: thoracic spine, scapulae, ribs
	local thor = { -9.0, -7.6, -6.2, -4.8, -3.4, -2.0, -.6, .8 }
	local spines = { 3.0, 3.5, 3.4, 3.0, 2.6, 2.2, 1.7, 1.3 }
	for i, z in ipairs(thor) do
		b:Vertebra("Chest", V3(0, spineY(z) - .7, z), V3(0, .05, 1), 2.1, spines[i], .35, i == 3 or i == 6)
	end
	for _, s in ipairs({ 1, -1 }) do
		b:Box("Chest", "Scapula", V3(.7, 6.0, 3.8), CF(3.3 * s, 16.0, -7.4) * ANG(-.22, 0, .32 * s), COL.Bone, MAT.SmoothPlastic)
		b:Box("Chest", "ScapulaRidge", V3(.6, 5.2, .6), CF(3.75 * s, 16.2, -7.4) * ANG(-.22, 0, .32 * s), COL.BoneLight, MAT.SmoothPlastic)
	end
	local ribs = {
		{ z = -8.0, w = 3.5, h = 3.7, yc = 13.5 }, { z = -6.3, w = 4.3, h = 4.4, yc = 13.1 }, { z = -4.6, w = 4.9, h = 4.8, yc = 12.9 },
		{ z = -2.9, w = 5.1, h = 4.8, yc = 12.9 }, { z = -1.2, w = 4.9, h = 4.5, yc = 13.1 }, { z = .5, w = 4.3, h = 3.9, yc = 13.5 },
	}
	for i, r in ipairs(ribs) do
		for _, s in ipairs({ 1, -1 }) do
			local pts = {}
			for k = 0, 6 do
				local phi = math.rad(80 - k * 26)
				local x = s * math.max(1.0, r.w * math.cos(phi))
				local y = r.yc + r.h * math.sin(phi)
				local z = r.z + (1 - (math.sin(phi) + 1) / 2) * 1.3
				table.insert(pts, V3(x, y, z))
			end
			local broken = (s == 1 and i == 4) or (s == -1 and i == 2)
			local last = broken and 4 or #pts - 1
			for k = 1, last do
				local col = (k % 2 == 0) and COL.Bone or COL.BoneLight
				b:Bar("Chest", "Rib", pts[k], pts[k + 1], .62, .95, col, MAT.SmoothPlastic, { Shadow = k < 4 }, V3(0, 0, 1))
			end
			if broken then
				-- jagged end + loose fragment
				local e = pts[last + 1]
				b:Wedge("Chest", "RibShard", V3(.6, .8, .9), CF(e + V3(0, -.3, 0)) * ANG(PI, 0, 0), COL.BoneDark, MAT.SmoothPlastic)
				b:Bar("Chest", "RibFragment", pts[#pts - 1] + V3(.4 * s, -.6, .4), pts[#pts] + V3(.3 * s, -.5, .3), .55, .8, COL.BoneDark, MAT.SmoothPlastic)
			elseif i % 2 == 1 then
				local m = pts[3]
				b:CrackLine("Chest", m + V3(.3 * s, .4, 0), m + V3(.35 * s, -.5, .1), V3(s, 0, 0))
			end
		end
	end
	-- sternum
	b:Bar("Chest", "Sternum", V3(0, 8.6, -8.4), V3(0, 9.0, -4.6), 1.5, .8, COL.Bone, MAT.SmoothPlastic)
	b:Bar("Chest", "Sternum", V3(0, 8.95, -4.2), V3(0, 9.3, .4), 1.4, .8, COL.BoneLight, MAT.SmoothPlastic)
	b:Bar("Chest", "Sternum", V3(0, 9.35, .8), V3(0, 9.9, 2.8), 1.2, .7, COL.Bone, MAT.SmoothPlastic)
	-- soul fire inside the ribcage
	b:Ball("Chest", "SoulCore", 2.6, V3(0, 12.2, -3.6), COL.GreenHot, MAT.Neon, { Shadow = false })
	b:Ball("Chest", "SoulGlow", 4.4, V3(0, 12.2, -3.6), COL.Green, MAT.Neon, { Shadow = false, T = .62 })
	b:Ball("Chest", "SoulHalo", 6.4, V3(0, 12.4, -3.6), COL.Purple, MAT.Neon, { Shadow = false, T = .86 })
	b:Flame("Chest", V3(-.9, 12.8, -2.4), 1.0, "Green", V3(-.2, 0, .3))
	b:Flame("Chest", V3(1.0, 13.0, -4.6), .9, "Purple", V3(.2, 0, .2))
	b:Flame("Chest", V3(0, 13.4, -3.4), 1.3, "Green", V3(0, 0, .5))
	b:Light("Chest", V3(0, 12.2, -3.6), COL.Green, 26, 2.4, "SoulLight")
	b:Attach("Chest", "Core", V3(0, 12.2, -3.6))
	-- gravestones on the back
	gravestone(b, "Chest", V3(.2, spineY(-5.6) + .9, -5.6), 1, 8.6, 1.25, -.1, .06, rng)
	gravestone(b, "Chest", V3(-.4, spineY(-.6) + .8, -.6), 2, 7.6, -.35, .1, -.18, rng)
	gravestone(b, "Pelvis", V3(.4, spineY(4.4) + .7, 4.4), 3, 8.0, -1.2, .12, .1, rng)
	gravestone(b, "Pelvis", V3(-.3, spineY(9.4) + .4, 9.4), 4, 5.6, 1.05, .28, -.1, rng)
	b:Light("Chest", V3(.3, spineY(-5.4) + 5.2, -6.6), COL.Purple, 16, 1.6, "GraveLight")
	-- flames between the stones and on the shoulders
	b:Flame("Chest", V3(1.6, spineY(-3) + .6, -3.0), 1.0, "Green", V3(.2, 0, .5))
	b:Flame("Chest", V3(-1.5, spineY(-7.8) + .8, -7.8), .9, "Purple", V3(-.2, 0, .5))
	b:Flame("Pelvis", V3(-1.4, spineY(6.8) + .6, 6.8), .85, "Green", V3(-.3, 0, .4))
	for _, s in ipairs({ 1, -1 }) do
		b:Flame("Chest", V3(4.4 * s, 18.4, -7.0), 1.35, s > 0 and "Purple" or "Green", V3(.5 * s, 0, .6))
	end
	-- chains strung between the stones and down the flanks
	b:Chain("Chest", "Chain", sag(V3(1.8, 21.0, -5.6), V3(-1.4, 21.4, -.6), 1.6, 6))
	b:Chain("Pelvis", "Chain", sag(V3(-1.2, 20.2, -.2), V3(1.6, 19.4, 4.2), 1.5, 6))
	b:Chain("Chest", "Chain", { V3(2.4, 20.4, -5.4), V3(4.0, 18.2, -4.6), V3(5.0, 15.4, -3.6), V3(5.2, 13.2, -2.6) })
	b:Chain("Pelvis", "Chain", { V3(-1.8, 19.6, 4.6), V3(-3.4, 17.6, 5.2), V3(-4.6, 15.6, 5.8), V3(-4.9, 14.0, 6.4) })
	b:Chain("Chest", "Chain", { V3(-5.0, 10.8, -4.6), V3(-5.3, 9.6, -4.4), V3(-5.2, 8.4, -4.0), V3(-4.9, 7.6, -3.6) }, .8)

	-------------------------------------------------------------------------------- neck: vertebrae, collar, lantern
	b.Xform = NECK_XF
	local n0, n1 = V3(0, 17.4, -9.6), V3(0, 18.7, -13.8)
	local nAxis = (n1 - n0).Unit
	for i = 1, 4 do
		local t = (i - .5) / 4
		local p = n0:Lerp(n1, t) + V3(0, math.sin(t * PI) * .5, 0)
		b:Vertebra("Neck", p, nAxis, 2.0 - i * .08, 1.2 - i * .12, .3, i == 2)
	end
	local collarC = V3(0, 17.7, -10.8)
	local ringCF = look(collarC, collarC + nAxis)
	for i = 0, 11 do
		local a = i / 12 * PI * 2
		local p = (ringCF * CF(math.cos(a) * 2.5, math.sin(a) * 2.5, 0)).Position
		local tangent = (ringCF.RightVector * -math.sin(a) + ringCF.UpVector * math.cos(a))
		b:Bar("Neck", "Collar", p - tangent * .7, p + tangent * .7, .7, 1.1, COL.Iron, MAT.CorrodedMetal, { Shadow = false }, nAxis)
		if i % 2 == 0 then
			local outward = (p - collarC).Unit
			b:Bar("Neck", "CollarSpike", p + outward * .2, p + outward * 1.4, .4, .4, COL.IronDark, MAT.CorrodedMetal, { Shadow = false })
		end
	end
	-- hanging green lantern under the throat
	local lanternTop = (ringCF * CF(0, -2.6, 0)).Position
	b:Chain("Neck", "LanternChain", { lanternTop, lanternTop + V3(0, -1.6, -.1), lanternTop + V3(0, -3.0, -.2) }, .7)
	local lc = lanternTop + V3(0, -4.1, -.2)
	b:Box("Neck", "LanternCap", V3(1.5, .3, 1.5), CF(lc + V3(0, .95, 0)), COL.IronDark, MAT.CorrodedMetal)
	b:Box("Neck", "LanternBase", V3(1.5, .3, 1.5), CF(lc + V3(0, -.95, 0)), COL.IronDark, MAT.CorrodedMetal)
	b:Box("Neck", "LanternGlass", V3(1.05, 1.6, 1.05), CF(lc), COL.Green, MAT.Neon, { Shadow = false, T = .15 })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b:Box("Neck", "LanternBar", V3(.16, 1.7, .16), CF(lc + V3(sx * .62, 0, sz * .62)), COL.Iron, MAT.CorrodedMetal, { Shadow = false })
		end
	end
	b:Wedge("Neck", "LanternRoof", V3(1.4, .5, .7), CF(lc + V3(0, 1.35, -.35)), COL.IronDark, MAT.CorrodedMetal, { Shadow = false })
	b:Wedge("Neck", "LanternRoof", V3(1.4, .5, .7), CF(lc + V3(0, 1.35, .35)) * ANG(0, PI, 0), COL.IronDark, MAT.CorrodedMetal, { Shadow = false })
	b:Light("Neck", lc, COL.Green, 14, 1.8, "LanternLight")
	b:Attach("Neck", "Lantern", lc)
	-- broken chain dangling from the collar
	b:Chain("Neck", "Chain", { (ringCF * CF(2.4, -.6, 0)).Position, V3(3.0, 15.4, -10.2), V3(3.2, 13.6, -9.8), V3(3.0, 12.4, -9.6) }, .8)

	-------------------------------------------------------------------------------- head: stone-plated, horned skull
	b:Ell("Head", "Cranium", V3(7.9, 6.0, 7.6), CF(0, 19.7, -16.0), COL.Bone, MAT.SmoothPlastic)
	b:Ell("Head", "Occiput", V3(5.8, 5.0, 3.8), CF(0, 19.6, -12.7) * ANG(.3, 0, 0), COL.BoneDark, MAT.SmoothPlastic)
	b:Ell("Head", "Temple", V3(8.4, 3.6, 5.0), CF(0, 18.6, -16.6), COL.BoneDark, MAT.SmoothPlastic)
	for _, s in ipairs({ 1, -1 }) do
		-- heavy angry V brow overhanging deep slanted sockets; small ember eyes glaring from inside
		b:Bar("Head", "Brow", V3(4.2 * s, 21.4, -18.6), V3(.3 * s, 20.0, -20.9), 1.7, 1.3, COL.BoneLight, MAT.SmoothPlastic, nil, V3(0, 1, -.5))
		b:Wedge("Head", "BrowSpike", V3(.9, 1.1, 2.2), CF(4.3 * s, 21.7, -18.2) * ANG(-.2, -.5 * s, -.6 * s), COL.Bone, MAT.SmoothPlastic, { Shadow = false })
		b:Ell("Head", "EyeSocket", V3(2.9, 1.9, 1.5), CF(2.05 * s, 19.35, -20.05) * ANG(.15, .22 * s, -.38 * s), COL.Socket, MAT.SmoothPlastic, { Shadow = false })
		b:Ell("Head", "SocketDeep", V3(2.1, 1.3, 1.0), CF(2.1 * s, 19.3, -20.4) * ANG(.15, .22 * s, -.38 * s), RGB(6, 2, 10), MAT.SmoothPlastic, { Shadow = false })
		b:Ball("Head", "Eye", 1.05, V3(2.25 * s, 19.25, -20.55), COL.Green, MAT.Neon, { Shadow = false })
		b:Ball("Head", "EyeCore", .5, V3(2.25 * s, 19.25, -21.0), COL.GreenHot, MAT.Neon, { Shadow = false })
		b:Box("Head", "EyeSlit", V3(.85, .14, .1), CF(2.25 * s, 19.25, -21.12) * ANG(0, 0, -.38 * s), COL.PurpleDeep, MAT.Neon, { Shadow = false })
		b:Ball("Head", "EyeHalo", 2.1, V3(2.25 * s, 19.3, -20.7), COL.Green, MAT.Neon, { Shadow = false, T = .74 })
		b:Bar("Head", "Cheekbone", V3(3.0 * s, 18.2, -19.4), V3(4.2 * s, 17.8, -14.8), 1.2, 1.5, COL.Bone, MAT.SmoothPlastic)
		b:Ball("Head", "CheekKnob", 1.6, V3(4.15 * s, 17.8, -14.7), COL.BoneDark, MAT.SmoothPlastic)
		b:Attach("Head", s > 0 and "EyeR" or "EyeL", V3(2.25 * s, 19.25, -20.9))
		-- eye flames trailing back over the skull
		b:Ell("Head", "EyeFlame", V3(.55, .6, 2.8), CF(3.0 * s, 20.4, -18.4) * ANG(-.35, .25 * s, 0), COL.Green, MAT.Neon, { Shadow = false })
		b:Ell("Head", "EyeFlame", V3(.5, .55, 2.6), CF(3.45 * s, 21.2, -16.6) * ANG(-.55, .3 * s, 0), COL.GreenDeep, MAT.Neon, { Shadow = false })
		b:Ell("Head", "EyeFlame", V3(.4, .45, 2.2), CF(3.6 * s, 21.9, -14.9) * ANG(-.75, .35 * s, 0), COL.Purple, MAT.Neon, { Shadow = false })
		-- muzzle sides (taper toward the nose)
		b:Box("Head", "MuzzleSide", V3(.9, 2.2, 5.6), CF(1.45 * s, 17.55, -22.7) * ANG(0, -.16 * s, 0), COL.BoneDark, MAT.SmoothPlastic)
		-- swept-back stone horns (thin, curling behind the skull) with rune bands
		local hp = { V3(2.7 * s, 21.9, -15.0), V3(3.8 * s, 23.2, -13.0), V3(4.5 * s, 23.9, -10.4), V3(4.7 * s, 23.8, -7.8), V3(4.4 * s, 23.0, -5.6) }
		local hd = { 1.55, 1.2, .9, .6 }
		for k = 1, 4 do
			b:Bar("Head", "Horn", hp[k], hp[k + 1], hd[k], hd[k] * 1.1, k % 2 == 1 and COL.StoneDark or COL.Stone, MAT.Slate, nil, V3(s, 1, 0))
			b:Ball("Head", "HornJoint", hd[k] * 1.05, hp[k + 1], COL.StoneDark, MAT.Slate, { Shadow = false })
		end
		b:Wedge("Head", "HornTip", V3(.55, .8, 1.3), look(hp[5], hp[5] + (hp[5] - hp[4])) * ANG(-PI / 2, 0, 0), COL.StoneLight, MAT.Slate, { Shadow = false })
		b:Cyl("Head", "HornRune", hp[1]:Lerp(hp[2], .55) - (hp[2] - hp[1]).Unit * .15, hp[1]:Lerp(hp[2], .55) + (hp[2] - hp[1]).Unit * .15, 1.65,
			COL.Purple, MAT.Neon, { Shadow = false })
		b:Cyl("Head", "HornRune", hp[3]:Lerp(hp[4], .3) - (hp[4] - hp[3]).Unit * .12, hp[3]:Lerp(hp[4], .3) + (hp[4] - hp[3]).Unit * .12, 1.05,
			COL.Purple, MAT.Neon, { Shadow = false })
		b:CrackLine("Head", hp[2] + V3(0, .55, .2), hp[3] + V3(0, .45, -.2), V3(0, 1, 0))
	end
	b:Light("Head", V3(0, 19.4, -21.6), COL.Green, 16, 2.2, "EyeLight")
	-- muzzle: core, chamfered bridge, rounded tip, diamond nasal cavity
	b:Box("Head", "Muzzle", V3(2.6, 2.2, 5.4), CF(0, 17.6, -22.7), COL.Bone, MAT.SmoothPlastic)
	b:Wedge("Head", "NasalBridge", V3(2.4, 1.2, 5.2), CF(0, 19.3, -22.5), COL.BoneLight, MAT.SmoothPlastic)
	b:Ell("Head", "MuzzleTip", V3(2.8, 2.2, 1.6), CF(0, 17.75, -25.15), COL.BoneLight, MAT.SmoothPlastic)
	for _, s in ipairs({ 1, -1 }) do
		b:Bar("Head", "MuzzleEdge", V3(1.35 * s, 18.75, -20.2), V3(1.05 * s, 18.45, -25.0), .8, .8, COL.Bone, MAT.SmoothPlastic, { Shadow = false },
			V3(s, 1, 0))
	end
	b:Box("Head", "NasalCavity", V3(1.2, 1.2, .5), CF(0, 18.3, -25.85) * ANG(0, 0, PI / 4), COL.BoneShadow, MAT.SmoothPlastic, { Shadow = false })
	b:Box("Head", "NasalHole", V3(.85, .85, .5), CF(0, 18.27, -25.95) * ANG(0, 0, PI / 4), COL.Socket, MAT.SmoothPlastic, { Shadow = false })
	b:Box("Head", "NasalSeptum", V3(.14, 1.05, .5), CF(0, 18.27, -26.0), COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
	b:CrackLine("Head", V3(-.9, 19.7, -21.4), V3(-.4, 19.15, -24.0), V3(0, 1, -.3))
	b:CrackLine("Head", V3(-.4, 19.15, -24.0), V3(-.8, 18.7, -25.3), V3(0, .6, -1))
	b:CrackLine("Head", V3(2.4, 22.0, -17.0), V3(3.3, 21.1, -18.4), V3(.5, 1, -.3))
	b:Bar("Head", "GlowCrack", V3(.7, 21.4, -20.1), V3(1.2, 20.1, -21.2), .14, .1, COL.Green, MAT.Neon, { Shadow = false }, V3(0, 1, -.6))
	-- upper teeth (one canine snapped, one missing tooth) + ectoplasm drool
	for _, s in ipairs({ 1, -1 }) do
		b:Fang("Head", "Canine", V3(1.4 * s, 16.6, -25.0), s > 0 and 3.2 or 1.4, 1.2, .9, true)
		for k, z in ipairs({ -23.5, -22.3, -21.1, -19.9 }) do
			if not (s < 0 and k == 2) then
				b:Fang("Head", "Tooth", V3((1.75 + k * .08) * s, 16.6, z), 1.3 - k * .08, .85, .6, true)
			end
		end
		b:Fang("Head", "Incisor", V3(.42 * s, 16.75, -25.7), 1.0, .5, .45, true)
		b:Fang("Head", "Incisor", V3(.95 * s, 16.75, -25.5), 1.1, .55, .5, true)
	end
	b:Ell("Head", "Drool", V3(.28, 2.6, .28), CF(1.45, 14.0, -25.0), COL.Green, MAT.Neon, { Shadow = false, T = .15 })
	b:Ball("Head", "DroolDrop", .45, V3(1.45, 12.6, -25.0), COL.GreenHot, MAT.Neon, { Shadow = false })
	b:Ell("Head", "Drool", V3(.22, 1.6, .22), CF(-.95, 15.6, -25.6), COL.Green, MAT.Neon, { Shadow = false, T = .2 })
	-- stone crown plating: a low ridge of slabs (iron band, rivets, purple runes, green glow crack)
	local plateTop = CF(0, 22.65, -16.4) * ANG(-.14, 0, 0)
	b:Box("Head", "SkullPlate", V3(3.2, .8, 6.6), plateTop, COL.StoneDark, MAT.Slate)
	b:Box("Head", "SkullPlateFace", V3(2.4, .4, 5.4), plateTop * CF(0, .42, 0), COL.Stone, MAT.Slate, { Shadow = false })
	for _, s in ipairs({ 1, -1 }) do
		b:Box("Head", "SkullPlateSide", V3(2.6, .8, 5.8), CF(2.6 * s, 22.05, -16.2) * ANG(-.1, 0, -.42 * s), COL.Stone, MAT.Slate)
		b:Box("Head", "SkullPlateSideEdge", V3(.45, .85, 5.9), CF(3.75 * s, 21.55, -16.2) * ANG(-.1, 0, -.42 * s), COL.StoneLight, MAT.Slate,
			{ Shadow = false })
	end
	b:Box("Head", "BrowPlate", V3(3.4, .7, 2.2), CF(0, 21.9, -19.6) * ANG(-.5, 0, 0), COL.Stone, MAT.Slate)
	b:Box("Head", "SkullBand", V3(7.0, .45, .8), CF(0, 22.3, -14.9) * ANG(-.14, 0, 0), COL.Iron, MAT.CorrodedMetal)
	for _, p in ipairs({ V3(-1.2, 23.15, -18.6), V3(1.2, 23.15, -18.6), V3(-1.2, 23.4, -14.2), V3(1.2, 23.4, -14.2), V3(3.3, 22.0, -14.9), V3(-3.3, 22.0, -14.9) }) do
		b:Ball("Head", "Rivet", .42, p, COL.Rust, MAT.CorrodedMetal, { Shadow = false })
	end
	for _, seg in ipairs({ { V3(-.8, 23.13, -17.8), V3(-.25, 23.2, -16.4) }, { V3(-.25, 23.2, -16.4), V3(-.7, 23.26, -15.3) },
		{ V3(.7, 23.13, -18.0), V3(.9, 23.26, -15.6) } }) do
		b:Bar("Head", "Rune", seg[1], seg[2], .2, .1, COL.Purple, MAT.Neon, { Shadow = false }, V3(0, 1, .14))
	end
	b:Bar("Head", "GlowCrack", V3(-3.3, 21.9, -18.0), V3(-2.3, 22.4, -16.2), .16, .1, COL.Green, MAT.Neon, { Shadow = false }, V3(-.5, 1, 0))
	b:Bar("Head", "GlowCrack", V3(-2.3, 22.4, -16.2), V3(-2.9, 22.2, -14.4), .14, .1, COL.Green, MAT.Neon, { Shadow = false }, V3(-.5, 1, 0))
	b:Box("Head", "SkullMoss", V3(1.8, .22, 1.4), CF(.9, 23.35, -14.0) * ANG(-.14, .3, 0), COL.Moss, MAT.Grass, { Shadow = false })
	b:Attach("Head", "Mouth", V3(0, 15.8, -24.4))

	-------------------------------------------------------------------------------- jaw (built open: the glowing maw shows from the front)
	for _, s in ipairs({ 1, -1 }) do
		b:Bar("Jaw", "Mandible", V3(3.4 * s, 16.4, -15.4), V3(1.6 * s, 13.5, -24.5), 1.2, 1.6, COL.Bone, MAT.SmoothPlastic)
		b:Bar("Jaw", "MandibleUnder", V3(3.1 * s, 15.6, -15.8), V3(1.45 * s, 12.9, -23.9), .9, .7, COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
		b:Box("Jaw", "Coronoid", V3(1.0, 2.2, 1.5), CF(3.35 * s, 17.0, -16.2) * ANG(.35, 0, 0), COL.Bone, MAT.SmoothPlastic)
		b:Fang("Jaw", "Canine", V3(1.35 * s, 14.15, -23.8), 2.5, 1.05, .8, false)
		for k, z in ipairs({ -22.2, -20.8, -19.4, -18.0 }) do
			local t = (z + 24.5) / 9.1
			b:Fang("Jaw", "Tooth", V3((1.6 + 1.8 * t) * s, 13.5 + 2.9 * t + .55, z), 1.05 - k * .06, .75, .5, false)
		end
	end
	b:Box("Jaw", "Chin", V3(3.3, 1.5, 1.8), CF(0, 13.3, -24.6) * ANG(.32, 0, 0), COL.Bone, MAT.SmoothPlastic)
	b:Ball("Jaw", "MouthGlow", 3.2, V3(0, 15.5, -21.4), COL.Green, MAT.Neon, { Shadow = false, T = .25 })
	b:Ell("Jaw", "Ectoplasm", V3(1.8, .5, 4.6), CF(0, 14.5, -20.2) * ANG(.32, 0, 0), COL.GreenDeep, MAT.Neon, { Shadow = false, T = .45 })
	b:Ball("Jaw", "MawSmoke", 4.4, V3(0, 15.4, -22.4), COL.Purple, MAT.Neon, { Shadow = false, T = .85 })

	b.Xform = nil
	-------------------------------------------------------------------------------- forelegs
	for _, s in ipairs({ 1, -1 }) do
		local side = s > 0 and "R" or "L"
		local arm, fore, paw = "Arm" .. side, "Fore" .. side, "Paw" .. side
		b:LongBone(arm, "Humerus", V3(5.2 * s, 14.4, -7.5), V3(5.6 * s, 8.7, -6.4), 2.5, COL.Bone,
			{ Groove = true, Crack = s > 0 and .55 or nil, Out = V3(s, 0, 0), Knob = 1.25 })
		b:Ball(arm, "Tubercle", 2.8, V3(5.4 * s, 14.9, -8.5), COL.BoneLight, MAT.SmoothPlastic)
		plate(b, arm, "Shoulder" .. side, V3(6.4 * s, 14.7, -7.5), V3(s, .25, -.1), V3(5.2, 5.6, 1.5), up, rng)
		-- radius + ulna, elbow, bracer, shackle
		b:LongBone(fore, "Radius", V3(5.3 * s, 8.0, -7.0), V3(5.3 * s, 3.1, -8.8), 1.5, COL.Bone, { Knob = 1.25 })
		b:LongBone(fore, "Ulna", V3(6.05 * s, 8.3, -6.2), V3(6.0 * s, 3.2, -8.3), 1.25, COL.BoneDark, { Knob = 1.2 })
		b:Ball(fore, "Olecranon", 2.1, V3(5.9 * s, 8.9, -5.6), COL.BoneLight, MAT.SmoothPlastic)
		local bracerC = V3(5.65 * s, 5.5, -7.6)
		local g = b:Group(fore, "Plate_Bracer" .. side, { Slot = "Bracer" .. side, Plate = true })
		local foreAxis = (V3(5.65 * s, 3.0, -8.6) - V3(5.65 * s, 8.0, -6.6)).Unit
		local bcf = look(bracerC, bracerC + foreAxis, V3(0, 0, -1))
		for k = 0, 3 do
			local a = k * PI / 2 + PI / 4
			local off = (bcf * CF(math.cos(a) * 1.35, math.sin(a) * 1.35, 0)).Position
			b:Part(fore, "BracerSlab", V3(1.9, 1.9, 3.4), look(off, off + foreAxis, (off - bracerC).Unit), k % 2 == 0 and COL.Stone or COL.StoneDark,
				MAT.Slate, { Group = g })
		end
		b:Part(fore, "BracerBand", V3(3.9, 3.9, .5), bcf * CF(0, 0, -1.2), COL.Iron, MAT.CorrodedMetal, { Group = g })
		b:Part(fore, "BracerBand", V3(3.9, 3.9, .5), bcf * CF(0, 0, 1.2), COL.Iron, MAT.CorrodedMetal, { Group = g })
		b:Bar(fore, "Rune", (bcf * CF(1.92 * s, -.6, -.7)).Position, (bcf * CF(1.92 * s, .6, .8)).Position, .2, .1, COL.Purple, MAT.Neon,
			{ Group = g, Shadow = false })
		b:Bar(fore, "Rune", (bcf * CF(1.92 * s, .6, -.7)).Position, (bcf * CF(1.92 * s, -.1, .1)).Position, .2, .1, COL.Purple, MAT.Neon,
			{ Group = g, Shadow = false })
		b:Bar(fore, "GlowCrack", (bcf * CF(-.5, 1.92, -.9)).Position, (bcf * CF(.4, 1.92, .5)).Position, .14, .1, COL.Green, MAT.Neon,
			{ Group = g, Shadow = false })
		for _, sz in ipairs({ -1.2, 1.2 }) do
			b:Ball(fore, "Rivet", .45, (bcf * CF(0, 1.98, sz)).Position, COL.Rust, MAT.CorrodedMetal, { Group = g, Shadow = false })
			b:Ball(fore, "Rivet", .45, (bcf * CF(1.98 * s, 0, sz)).Position, COL.Rust, MAT.CorrodedMetal, { Group = g, Shadow = false })
		end
		-- crack stages on the four slab faces (face k at k * 90 + 45 degrees around the forearm)
		local faces = {}
		for k = 0, 3 do
			local a = k * PI / 2 + PI / 4
			local nrm = (bcf.RightVector * math.cos(a) + bcf.UpVector * math.sin(a)).Unit
			local fp = bracerC + nrm * 2.33
			faces[k] = look(fp, fp + nrm, foreAxis)
		end
		crackStage(b, fore, g, 1, { { faces[0], -.5, -.7, .3, .05 }, { faces[0], .3, .05, .6, .55 } }, .9, 1.6)
		crackStage(b, fore, g, 2, { { faces[1], .4, -.8, -.2, -.1 }, { faces[0], -.5, -.7, -.7, -.95 }, { faces[3], .5, .25, -.3, .8 } }, .9, 1.6)
		crackStage(b, fore, g, 3, { { faces[2], -.6, -.85, .1, 0 }, { faces[2], .1, 0, -.3, .85 }, { faces[1], -.2, -.1, .5, .6 },
			{ faces[3], -.6, -.5, .2, -.05 } }, .9, 1.6)
		b:Attach(fore, "PlateCenter", bracerC + V3(1.4 * s, 0, -.6), { Slot = "Bracer" .. side })
		local shack = V3(5.65 * s, 3.5, -8.55)
		local scf = look(shack, shack + foreAxis, V3(0, 0, -1))
		for k = 0, 7 do
			local a = k / 8 * PI * 2
			local p = (scf * CF(math.cos(a) * 1.25, math.sin(a) * 1.25, 0)).Position
			local tangent = scf.RightVector * -math.sin(a) + scf.UpVector * math.cos(a)
			b:Bar(fore, "Shackle", p - tangent * .52, p + tangent * .52, .42, .7, COL.IronDark, MAT.CorrodedMetal, { Shadow = false }, foreAxis)
		end
		b:Chain(fore, "Chain", { shack + V3(1.3 * s, -.2, .2), shack + V3(1.7 * s, -1.0, .8), shack + V3(1.8 * s, -1.9, 1.5), shack + V3(1.6 * s, -2.7, 2.4) }, .75)
		-- paw: carpus, 4 spread toes, big hooked claws, dew claw
		b:Ell(paw, "Carpus", V3(4.0, 1.9, 3.0), CF(5.6 * s, 2.25, -9.1), COL.BoneDark, MAT.SmoothPlastic)
		b:Ell(paw, "CarpusTop", V3(2.8, 1.2, 2.2), CF(5.6 * s, 2.9, -8.8), COL.Bone, MAT.SmoothPlastic)
		for _, dx in ipairs({ -1.95, -.68, .68, 1.95 }) do
			local x = 5.6 * s + dx
			local spread = dx * .3
			local m0 = V3(5.6 * s + dx * .45, 2.0, -9.7)
			local m1 = V3(x + spread, 1.05, -11.2 + math.abs(dx) * .25)
			local t1 = m1 + V3(spread * .4, -.1, -1.5 + math.abs(dx) * .3)
			b:Bar(paw, "Metacarpal", m0, m1, .95, .95, COL.Bone, MAT.SmoothPlastic)
			b:Ball(paw, "Knuckle", 1.25, m1, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
			b:Bar(paw, "Phalanx", m1, t1, .8, .8, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
			b:Ball(paw, "Knuckle", .95, t1, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
			b:Claw(paw, "Claw", t1 + V3(0, .3, 0), V3(spread * .35, 0, -1), 3.9 - math.abs(dx) * .4, .95)
		end
		b:Claw(paw, "DewClaw", V3(5.6 * s - 2.1 * s, 2.5, -9.4), V3(-.7 * s, 0, -1), 2.0, .6)
		b:Attach(paw, side == "R" and "PawFR" or "PawFL", V3(5.6 * s, 0, -10.8))
	end

	-------------------------------------------------------------------------------- hind legs
	for _, s in ipairs({ 1, -1 }) do
		local side = s > 0 and "R" or "L"
		local thigh, shin, foot = "Thigh" .. side, "Shin" .. side, "Foot" .. side
		b:LongBone(thigh, "Femur", V3(4.6 * s, 12.6, 9.0), V3(5.0 * s, 7.9, 6.0), 2.6, COL.Bone,
			{ Groove = true, Crack = s < 0 and .45 or nil, Out = V3(s, 0, 0), Knob = 1.22 })
		b:Ball(thigh, "Trochanter", 2.6, V3(5.4 * s, 12.9, 9.7), COL.BoneLight, MAT.SmoothPlastic)
		b:Ball(shin, "Patella", 1.6, V3(5.0 * s, 7.7, 4.9), COL.BoneLight, MAT.SmoothPlastic)
		b:LongBone(shin, "Tibia", V3(5.0 * s, 7.2, 6.0), V3(5.0 * s, 3.9, 11.0), 1.9, COL.Bone, { Knob = 1.2 })
		b:Cyl(shin, "Fibula", V3(5.75 * s, 7.0, 6.4), V3(5.6 * s, 4.1, 10.6), .7, COL.BoneDark, MAT.SmoothPlastic)
		b:Ball(foot, "Hock", 1.9, V3(5.0 * s, 3.9, 11.8), COL.BoneLight, MAT.SmoothPlastic)
		b:Ell(foot, "Tarsus", V3(2.4, 1.6, 2.2), CF(5.0 * s, 3.2, 11.0), COL.BoneDark, MAT.SmoothPlastic)
		for _, dx in ipairs({ -1.6, -.55, .55, 1.6 }) do
			local m0 = V3(5.0 * s + dx * .35, 3.0, 10.8)
			local m1 = V3(5.0 * s + dx, .95, 8.9)
			local t1 = m1 + V3(dx * .18, -.1, -1.4)
			b:Bar(foot, "Metatarsal", m0, m1, .85, .85, COL.Bone, MAT.SmoothPlastic)
			b:Ball(foot, "Knuckle", 1.1, m1, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
			b:Bar(foot, "Phalanx", m1, t1, .7, .7, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
			b:Claw(foot, "Claw", t1 + V3(0, .25, 0), V3(dx * .12, 0, -1), 3.0, .8)
		end
		b:Attach(foot, side == "R" and "PawHR" or "PawHL", V3(5.0 * s, 0, 8.4))
	end
	-- shackle chain between the hind legs (broken in the middle)
	b:Chain("ShinR", "Chain", { V3(4.3, 4.6, 9.8), V3(3.3, 3.4, 9.9), V3(2.5, 2.4, 10.0), V3(2.1, 1.6, 10.1) }, .7)
	b:Chain("ShinL", "Chain", { V3(-4.3, 4.6, 9.8), V3(-3.5, 3.2, 9.9), V3(-2.9, 1.9, 10.0) }, .7)

	-------------------------------------------------------------------------------- tail
	local tailPts = { V3(0, 14.4, 12.6), V3(0, 13.0, 16.0), V3(.6, 10.6, 19.0), V3(1.6, 7.8, 21.2), V3(2.5, 5.2, 22.4) }
	local tailD = { 1.6, 1.3, 1.0, .75 }
	for i = 1, 4 do
		local bone = "Tail" .. i
		local a, c = tailPts[i], tailPts[i + 1]
		local axis = (c - a).Unit
		for k = 1, 3 do
			local p = a:Lerp(c, (k - .5) / 3)
			b:Vertebra(bone, p, axis, tailD[i] * (1 - k * .04), tailD[i] * .45, .2)
		end
	end
	-- wrapped chain around the tail
	do
		local a, c = tailPts[2], tailPts[3]
		local axis = (c - a).Unit
		local cf0 = look(a, c)
		local pts = {}
		for k = 0, 10 do
			local t = k / 10
			local ang = t * PI * 3.2
			table.insert(pts, (cf0 * CF(math.cos(ang) * .95, math.sin(ang) * .95, -t * (c - a).Magnitude)).Position)
		end
		b:Chain("Tail2", "Chain", pts, .55)
		local _ = axis
	end
	b:Flame("Tail4", tailPts[5] + V3(0, .2, 0), 1.0, "Purple", V3(.3, 0, .4))
	b:Flame("Tail4", tailPts[5] + V3(-.3, -.4, -.4), .65, "Green", V3(-.2, 0, .3))
	b:Light("Tail4", tailPts[5] + V3(0, 1, 0), COL.Purple, 12, 1.4, "TailLight")
	b:Attach("Tail4", "TailTip", tailPts[5])

	-------------------------------------------------------------------------------- weak points (hidden until opened)
	-- a molten gold core in a pumpkin-orange glow, gold / orange cracks radiating out, a white-gold rim ring around the
	-- opening and a pale ForceField bubble: the only gold, orange and white on the rig (BossFX adds the highlight, light,
	-- reticle and the x3 tag while open)
	local function weak(slot: string, bone: string, pos: Vector3, normal: Vector3, size: number)
		local g = b:Group(bone, "Weak_" .. slot, { Slot = slot, Weak = true })
		local n = normal.Unit
		local cf = look(pos, pos + n)
		b:Ball(bone, "WeakCore", size * .7, pos, COL.WeakHot, MAT.Neon, { Group = g, Shadow = false, T = 1 })
		b:Ball(bone, "WeakGlow", size * 1.3, pos, COL.Weak, MAT.Neon, { Group = g, Shadow = false, T = 1 })
		for k = 0, 5 do
			local a = k / 6 * PI * 2 + .3
			local p0 = (cf * CF(math.cos(a) * size * .35, math.sin(a) * size * .35, -size * .3)).Position
			local p1 = (cf * CF(math.cos(a + .25) * size * 1.15, math.sin(a + .25) * size * 1.15, -size * .2)).Position
			b:Bar(bone, "WeakCrack", p0, p1, .22, .14, k % 2 == 0 and COL.WeakGold or COL.Weak, MAT.Neon, { Group = g, Shadow = false, T = 1 }, n)
		end
		-- rim ring: 10 short segments around the opening, facing out along the normal
		local rr = size * 1.08
		for k = 0, 9 do
			local a0, a1 = k / 10 * PI * 2, (k + .8) / 10 * PI * 2
			local p0 = (cf * CF(math.cos(a0) * rr, math.sin(a0) * rr, -size * .25)).Position
			local p1 = (cf * CF(math.cos(a1) * rr, math.sin(a1) * rr, -size * .25)).Position
			b:Bar(bone, "WeakRim", p0, p1, .2, .2, COL.WeakRim, MAT.Neon, { Group = g, Shadow = false, T = 1 }, n)
		end
		b:Ball(bone, "WeakRing", size * 1.9, pos, COL.WeakRim, MAT.ForceField, { Group = g, Shadow = false, T = 1 })
		b:Attach(bone, "WeakCenter", pos, { Slot = slot })
	end
	weak("Heart", "Chest", Boss.Slots.Weak.Heart.Pos, V3(0, -1, -.4), 2.5) -- outgrows the soul core it sits in (BossFX dims the soul)
	b.Xform = nil
	weak("Throat", "Neck", Boss.Slots.Weak.Throat.Pos, V3(0, -1, -.2), 1.7)
	weak("Spine", "Pelvis", Boss.Slots.Weak.Spine.Pos, V3(0, -1, 0), 1.8)

	b.Model:SetAttribute("Parts", b.Count)
	b.Model:SetAttribute("Height", 25.5)
	return b.Model
end

---------------------------------------------------------------------------------------------------------------------
-- SKELETON DOG (minion of the pack phase)
---------------------------------------------------------------------------------------------------------------------
function Boss.Skeleton(seed: number?): Model
	local rng = newRng(seed or 7)
	local b = newRig("SkeletonDog", V3(1, 1, 1), CF(0, .5, 0))
	b:Bone("Body", nil, V3(0, 2.4, 0))
	b:Bone("Head", "Body", V3(0, 2.95, -2.1))
	b:Bone("Jaw", "Head", V3(0, 2.75, -2.55))
	b:Bone("LegFR", "Body", V3(.72, 2.15, -1.45))
	b:Bone("LegFL", "Body", V3(-.72, 2.15, -1.45))
	b:Bone("LegHR", "Body", V3(.66, 2.15, 1.55))
	b:Bone("LegHL", "Body", V3(-.66, 2.15, 1.55))
	b:Bone("Tail", "Body", V3(0, 2.7, 2.15))
	local bone = COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .35))
	-- spine + ribs + pelvis
	for i = 0, 5 do
		local z = -1.75 + i * .72
		local y = 2.85 - math.abs(z - .1) * .06
		b:Cyl("Body", "Vertebra", V3(0, y, z - .22), V3(0, y, z + .22), .62, bone, MAT.SmoothPlastic)
		b:Bar("Body", "DorsalSpine", V3(0, y + .2, z), V3(0, y + .62 - i * .04, z + .14), .14, .24, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	end
	for i, z in ipairs({ -1.3, -.85, -.4, .05 }) do
		local w = ({ .72, .86, .9, .78 })[i]
		for _, s in ipairs({ 1, -1 }) do
			local p0 = V3(.22 * s, 2.72, z)
			local p1 = V3(w * s, 2.3, z + .08)
			local p2 = V3(w * .85 * s, 1.75, z + .18)
			local p3 = V3(.18 * s, 1.5, z + .22)
			b:Bar("Body", "Rib", p0, p1, .16, .22, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
			b:Bar("Body", "Rib", p1, p2, .16, .22, bone, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
			b:Bar("Body", "Rib", p2, p3, .16, .22, bone, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
		end
	end
	b:Bar("Body", "Sternum", V3(0, 1.48, -1.35), V3(0, 1.55, .3), .36, .2, bone, MAT.SmoothPlastic, { Shadow = false })
	for _, s in ipairs({ 1, -1 }) do
		b:Box("Body", "Ilium", V3(.2, .7, 1.0), CF(.5 * s, 2.6, 1.55) * ANG(.2, 0, -.4 * s), bone, MAT.SmoothPlastic)
		b:Box("Body", "Scapula", V3(.18, 1.0, .7), CF(.6 * s, 2.55, -1.45) * ANG(-.2, 0, .3 * s), COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	end
	b:Ball("Body", "SoulCore", .55, V3(0, 2.15, -.6), COL.Green, MAT.Neon, { Shadow = false })
	b:Ball("Body", "SoulGlow", 1.0, V3(0, 2.15, -.6), COL.Green, MAT.Neon, { Shadow = false, T = .6 })
	b:Flame("Body", V3(0, 3.3, -.4), .32, rng:NextNumber() < .5 and "Green" or "Purple", V3(0, 0, .3))
	-- stone saddle plate + a chain stub (they serve the Gravekeeper)
	b:Box("Body", "Saddle", V3(1.0, .22, 1.2), CF(0, 3.15, .7) * ANG(.08, 0, .05), COL.StoneDark, MAT.Slate)
	b:Bar("Body", "Rune", V3(-.25, 3.28, .4), V3(.2, 3.29, 1.0), .08, .05, COL.Purple, MAT.Neon, { Shadow = false })
	-- head
	b:Ell("Head", "Cranium", V3(1.4, 1.2, 1.4), CF(0, 3.22, -2.7), COL.BoneLight, MAT.SmoothPlastic)
	b:Box("Head", "Snout", V3(.66, .5, 1.05), CF(0, 2.98, -3.72), bone, MAT.SmoothPlastic)
	b:Wedge("Head", "SnoutRidge", V3(.62, .3, 1.0), CF(0, 3.38, -3.62), COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	b:Ell("Head", "SnoutTip", V3(.7, .55, .45), CF(0, 3.02, -4.22), COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	b:Ell("Head", "Nose", V3(.36, .22, .12), CF(0, 3.1, -4.43), COL.Socket, MAT.SmoothPlastic, { Shadow = false })
	b:Box("Head", "HeadPlate", V3(.95, .18, .9), CF(0, 3.8, -2.75) * ANG(-.1, 0, .06), COL.Stone, MAT.Slate, { Shadow = false })
	b:Bar("Head", "GlowCrack", V3(-.3, 3.9, -3.0), V3(.15, 3.91, -2.5), .07, .04, COL.Green, MAT.Neon, { Shadow = false })
	for _, s in ipairs({ 1, -1 }) do
		b:Ell("Head", "EyeSocket", V3(.5, .46, .3), CF(.34 * s, 3.27, -3.28) * ANG(0, .3 * s, 0), COL.Socket, MAT.SmoothPlastic, { Shadow = false })
		b:Ball("Head", "Eye", .3, V3(.34 * s, 3.26, -3.38), COL.Green, MAT.Neon, { Shadow = false })
		b:Bar("Head", "Brow", V3(.62 * s, 3.62, -3.0), V3(.08 * s, 3.46, -3.36), .18, .16, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
		b:Wedge("Head", "Ear", V3(.16, .55, .4), CF(.45 * s, 3.88, -2.4) * ANG(-.3, 0, -.25 * s), COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
		b:Fang("Head", "Fang", V3(.27 * s, 2.74, -4.05), .4, .2, .14, true)
		b:Bar("Jaw", "Mandible", V3(.42 * s, 2.72, -2.65), V3(.26 * s, 2.46, -4.15), .16, .22, bone, MAT.SmoothPlastic, { Shadow = false })
		b:Fang("Jaw", "Fang", V3(.24 * s, 2.56, -3.95), .3, .16, .12, false)
	end
	b:Box("Jaw", "Chin", V3(.56, .22, .3), CF(0, 2.43, -4.12), bone, MAT.SmoothPlastic, { Shadow = false })
	b:Box("Jaw", "MouthGlow", V3(.4, .08, .9), CF(0, 2.66, -3.6), COL.Green, MAT.Neon, { Shadow = false, T = .3 })
	b:Box("Head", "Collar", V3(1.25, .3, .5), CF(0, 2.7, -2.05) * ANG(.5, 0, 0), COL.Iron, MAT.CorrodedMetal, { Shadow = false })
	b:Chain("Head", "Chain", { V3(0, 2.4, -1.95), V3(.05, 2.0, -1.8), V3(.1, 1.6, -1.7) }, .36)
	-- legs (one bone each: upper + lower + paw + claws)
	local legs = { { "LegFR", 1, -1.45, -1 }, { "LegFL", -1, -1.45, -1 }, { "LegHR", 1, 1.55, 1 }, { "LegHL", -1, 1.55, 1 } }
	for _, l in ipairs(legs) do
		local name, s, z, hind = l[1], l[2], l[3], l[4] > 0
		local hip = V3(.72 * s, 2.15, z)
		local knee = hind and V3(.78 * s, 1.15, z - .35) or V3(.76 * s, 1.15, z + .12)
		local ankle = hind and V3(.76 * s, .45, z + .2) or V3(.76 * s, .4, z - .05)
		b:Bar(name, "Upper", hip, knee, .34, .34, bone, MAT.SmoothPlastic)
		b:Ball(name, "Hip", .46, hip, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
		b:Ball(name, "Joint", .42, knee, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
		b:Bar(name, "Lower", knee, ankle, .26, .26, bone, MAT.SmoothPlastic)
		b:Ell(name, "Paw", V3(.5, .2, .6), CF(ankle + V3(0, -.3, -.22)), COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
		for _, dx in ipairs({ -.14, 0, .14 }) do
			b:Bar(name, "Claw", ankle + V3(dx, -.3, -.45), ankle + V3(dx * 1.2, -.42, -.75), .07, .09, COL.Claw, MAT.SmoothPlastic, { Shadow = false })
		end
	end
	-- tail
	local tp = { V3(0, 2.7, 2.15), V3(0, 2.95, 2.75), V3(0, 3.35, 3.2), V3(.1, 3.85, 3.4) }
	for i = 1, 3 do
		b:Cyl("Tail", "TailBone", tp[i], tp[i + 1], .26 - i * .04, bone, MAT.SmoothPlastic, { Shadow = false })
	end
	b:Ball("Tail", "TailTip", .2, tp[4], COL.Green, MAT.Neon, { Shadow = false })
	b:Attach("Body", "Core", V3(0, 2.15, -.6))
	b.Model:SetAttribute("Parts", b.Count)
	return b.Model
end

-- invisible ground-origin root (PrimaryPart): PivotTo(CFrame.new(groundPos)) puts the model's feet on the ground
local function groundRoot(m: Model): BasePart
	local r = Instance.new("Part")
	r.Name = "Root"
	r.Size = V3(.4, .4, .4)
	r.CFrame = CF()
	r.Transparency = 1
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Parent = m
	m.PrimaryPart = r
	return r
end

---------------------------------------------------------------------------------------------------------------------
-- CURSED ROCK (falls from the sky in phase 4; landed rocks are broken with timing hits)
---------------------------------------------------------------------------------------------------------------------
function Boss.Rock(seed: number?): Model
	local rng = newRng(seed or 3)
	local m = Instance.new("Model")
	m.Name = "CursedRock"
	local function part(name, class, size, cf, color, mat, o)
		local p = Instance.new(class)
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = mat ~= MAT.Neon
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
		if o and o.T then
			p.Transparency = o.T
		end
		if o and o.Shape then
			(p :: any).Shape = o.Shape
		end
		p.Parent = m
		return p
	end
	local c = V3(0, 2.3, 0)
	local core = part("Core", "Part", V3(3.4, 3.2, 3.4), CF(c) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, 6), rng:NextNumber(-.3, .3)),
		RGB(46, 40, 54), MAT.Basalt)
	groundRoot(m)
	local rockCols = { RGB(62, 54, 72), RGB(46, 40, 56), RGB(76, 68, 86), RGB(38, 34, 46) }
	for i = 1, 13 do
		local dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(-.5, 1), rng:NextNumber(-1, 1))
		if dir.Magnitude < .2 then
			dir = V3(0, 1, 0)
		end
		dir = dir.Unit
		local p = c + dir * rng:NextNumber(1.1, 1.6)
		local size = V3(rng:NextNumber(1.6, 2.6), rng:NextNumber(1.4, 2.4), rng:NextNumber(1.0, 1.6))
		local cf = look(p, p + dir) * ANG(0, 0, rng:NextNumber(0, 6))
		local class = i % 4 == 0 and "WedgePart" or "Part"
		local f = part("Facet", class, size, cf, rockCols[(i % #rockCols) + 1], i % 2 == 0 and MAT.Basalt or MAT.Slate)
		if class == "Part" and rng:NextNumber() < .7 then
			-- glowing vein on the outer face
			local face = cf * CF(0, 0, -size.Z / 2 - .03)
			local len = math.min(size.X, size.Y) * rng:NextNumber(.7, 1.1)
			local ang = rng:NextNumber(0, PI)
			local col = rng:NextNumber() < .35 and COL.Green or COL.Purple
			part("GlowCrack", "Part", V3(len, .16, .08), face * ANG(0, 0, ang), col, MAT.Neon)
			part("GlowCrack", "Part", V3(len * .5, .12, .08), face * ANG(0, 0, ang) * CF(len * .4, len * .12, 0) * ANG(0, 0, .8), col, MAT.Neon)
		end
		local _ = f
	end
	-- jagged spikes on top
	for i = 1, 3 do
		local a = i / 3 * PI * 2 + rng:NextNumber(-.4, .4)
		local p = c + V3(math.cos(a) * .9, 1.8, math.sin(a) * .9)
		part("Spike", "WedgePart", V3(.9, rng:NextNumber(1.4, 2.2), 1.0), look(p, p + V3(math.cos(a), 0, math.sin(a))) * ANG(-.3, 0, 0),
			RGB(52, 44, 60), MAT.Basalt)
	end
	part("CoreGlow", "Part", V3(3.2, 3.2, 3.2), CF(c), COL.Purple, MAT.Neon, { T = .55, Shape = Enum.PartType.Ball })
	for i = 1, 4 do
		local a = i / 4 * PI * 2
		part("Ember", "Part", V3(.3, .3, .3), CF(c + V3(math.cos(a) * 2.6, rng:NextNumber(-.6, 1.4), math.sin(a) * 2.6)), COL.GreenHot, MAT.Neon,
			{ Shape = Enum.PartType.Ball })
	end
	-- a broken iron band (it was chained once)
	for k = 0, 4 do
		local a = k / 6 * PI * 2
		local p = c + V3(math.cos(a) * 2.05, -.4 + k * .05, math.sin(a) * 2.05)
		local tangent = V3(-math.sin(a), 0, math.cos(a))
		local seg = part("IronBand", "Part", V3(.3, .5, 1.2), look(p, p + tangent), COL.Iron, MAT.CorrodedMetal)
		local _ = seg
	end
	local glow = Instance.new("Attachment")
	glow.Name = "Glow"
	glow.Parent = core
	m:SetAttribute("Parts", #m:GetChildren())
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- GRAVE MOUND (burrow phase: one real, the others fake)
---------------------------------------------------------------------------------------------------------------------
function Boss.Mound(seed: number?): Model
	local rng = newRng(seed or 11)
	local m = Instance.new("Model")
	m.Name = "GraveMound"
	local function part(name, class, size, cf, color, mat, o)
		local p = Instance.new(class)
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = mat ~= MAT.Neon and size.Magnitude > 2
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
		if o and o.T then
			p.Transparency = o.T
		end
		if o and o.Shape then
			(p :: any).Shape = o.Shape
		end
		if o and o.Mesh then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = m
		return p
	end
	local base = part("Base", "Part", V3(8.2, 2.8, 7.6), CF(0, .3, 0) * ANG(0, rng:NextNumber(0, 6), 0), COL.Dirt, MAT.Ground, { Mesh = true })
	groundRoot(m)
	part("Crown", "Part", V3(5.0, 2.6, 4.6), CF(rng:NextNumber(-.3, .3), 1.05, rng:NextNumber(-.3, .3)), RGB(72, 54, 44), MAT.Ground, { Mesh = true })
	for i = 1, 9 do
		local a = i / 9 * PI * 2 + rng:NextNumber(-.2, .2)
		local r = rng:NextNumber(2.2, 3.6)
		local d = rng:NextNumber(.7, 1.4)
		part("Clod", "Part", V3(d, d * .8, d), CF(math.cos(a) * r, .35 + rng:NextNumber(0, .5), math.sin(a) * r) * ANG(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			i % 2 == 0 and COL.DirtDark or RGB(74, 58, 46), MAT.Ground)
	end
	-- earth cracks with a faint glow (green = the Gravekeeper stirring below)
	for i = 1, 6 do
		local a = i / 6 * PI * 2 + rng:NextNumber(-.3, .3)
		local p0 = V3(math.cos(a) * .6, 1.82, math.sin(a) * .6)
		local p1 = V3(math.cos(a) * 2.6, 1.0, math.sin(a) * 2.4)
		local mid = (p0 + p1) / 2
		part("Crack", "Part", V3(.22, .12, (p1 - p0).Magnitude), look(mid, p1), COL.Socket, MAT.SmoothPlastic)
		part("CrackGlow", "Part", V3(.18, .14, (p1 - p0).Magnitude * .85), look(mid + V3(0, .06, 0), p1 + V3(0, .06, 0)), i % 2 == 0 and COL.Green or COL.Purple, MAT.Neon)
	end
	-- bones, a skull fragment and a tiny broken grave marker
	for i = 1, 3 do
		local a = rng:NextNumber(0, 6.28)
		local p = V3(math.cos(a) * 2.4, .9, math.sin(a) * 2.2)
		local dir = V3(math.cos(a + 1.6), .15, math.sin(a + 1.6))
		part("Bone", "Part", V3(1.6, .28, .28), look(p, p + dir) * ANG(0, PI / 2, 0), COL.Bone, MAT.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		part("BoneKnob", "Part", V3(.42, .42, .42), CF(p + dir.Unit * .8), COL.BoneLight, MAT.SmoothPlastic, { Shape = Enum.PartType.Ball })
		part("BoneKnob", "Part", V3(.42, .42, .42), CF(p - dir.Unit * .8), COL.BoneLight, MAT.SmoothPlastic, { Shape = Enum.PartType.Ball })
	end
	part("Skull", "Part", V3(1.1, .9, 1.2), CF(-1.4, 1.35, -1.6) * ANG(.3, .7, .2), COL.BoneLight, MAT.SmoothPlastic, { Mesh = true })
	part("SkullEye", "Part", V3(.22, .22, .22), CF(-1.65, 1.45, -2.1), COL.Socket, MAT.SmoothPlastic, { Shape = Enum.PartType.Ball })
	part("SkullEye", "Part", V3(.22, .22, .22), CF(-1.25, 1.45, -2.18), COL.Socket, MAT.SmoothPlastic, { Shape = Enum.PartType.Ball })
	part("Marker", "Part", V3(1.4, 1.8, .35), CF(1.9, 1.4, 1.5) * ANG(-.25, -.5, .3), COL.Stone, MAT.Slate)
	part("MarkerTop", "Part", V3(.35, 1.4, 1.4), CF(1.95, 2.3, 1.42) * ANG(-.25, -.5, .3) * ANG(0, PI / 2, 0), COL.Stone, MAT.Slate,
		{ Shape = Enum.PartType.Cylinder })
	for i = 1, 4 do
		local a = rng:NextNumber(0, 6.28)
		local p = V3(math.cos(a) * 3.2, .7, math.sin(a) * 3.0)
		part("DeadGrass", "WedgePart", V3(.12, .7, .4), CF(p) * ANG(0, a, rng:NextNumber(-.4, .4)), RGB(92, 96, 58), MAT.Grass)
	end
	-- the rune circle around every mound ("find the real circle"): glowing purple ring + rune ticks + candles
	local ringR = 4.6
	for i = 0, 17 do
		local a = i / 18 * PI * 2
		local p = V3(math.cos(a) * ringR, .12, math.sin(a) * ringR)
		local seg = 2 * PI * ringR / 18 * .8
		part("RuneRing", "Part", V3(.3, .1, seg), look(p, p + V3(-math.sin(a), 0, math.cos(a))), COL.Purple, MAT.Neon)
		if i % 3 == 0 then
			local q = V3(math.cos(a) * (ringR + .7), .12, math.sin(a) * (ringR + .7))
			part("RuneTick", "Part", V3(.22, .1, .9), look(q, q + V3(math.cos(a), 0, math.sin(a))) * ANG(0, .5, 0), COL.PurpleHot, MAT.Neon)
		end
	end
	for i = 1, 3 do
		local a = i / 3 * PI * 2 + .4
		local q = V3(math.cos(a) * (ringR - .5), 0, math.sin(a) * (ringR - .5))
		part("Candle", "Part", V3(.32, .7, .32), CF(q + V3(0, .35, 0)), RGB(236, 226, 200), MAT.SmoothPlastic)
		part("CandleFlame", "Part", V3(.22, .3, .22), CF(q + V3(0, .85, 0)), COL.Green, MAT.Neon, { Shape = Enum.PartType.Ball })
	end
	local top = Instance.new("Attachment")
	top.Name = "Top"
	top.CFrame = CF(0, 1.6, 0)
	top.Parent = base
	m:SetAttribute("Parts", #m:GetChildren())
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- SKELETON HAND (bursts out of a fake mound)
---------------------------------------------------------------------------------------------------------------------
function Boss.Hand(seed: number?): Model
	local rng = newRng(seed or 5)
	local b = newRig("SkeletonHand", V3(.5, .5, .5), CF(0, 0, 0))
	b:Bone("Arm", nil, V3(0, 0, 0))
	b:Cyl("Arm", "Radius", V3(-.2, -1.2, 0), V3(-.15, 1.6, .1), .38, COL.Bone, MAT.SmoothPlastic)
	b:Cyl("Arm", "Ulna", V3(.22, -1.2, 0), V3(.2, 1.5, .05), .32, COL.BoneDark, MAT.SmoothPlastic)
	b:Ell("Arm", "Wrist", V3(.9, .5, .55), CF(0, 1.75, .05), COL.BoneLight, MAT.SmoothPlastic)
	for i, dx in ipairs({ -.33, -.11, .11, .33 }) do
		local len = ({ .75, .9, .85, .65 })[i]
		local p0 = V3(dx, 1.95, .05)
		local p1 = V3(dx * 1.3, 1.95 + len, .05 + rng:NextNumber(-.1, .1))
		local p2 = p1 + V3(dx * .2, len * .65, -.25)
		local p3 = p2 + V3(0, len * .3, -.3)
		b:Cyl("Arm", "Finger", p0, p1, .16, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
		b:Cyl("Arm", "Finger", p1, p2, .14, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
		b:Cyl("Arm", "FingerTip", p2, p3, .1, COL.Claw, MAT.SmoothPlastic, { Shadow = false })
	end
	b:Cyl("Arm", "Thumb", V3(-.4, 1.8, 0), V3(-.75, 2.3, -.2), .16, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
	b:Cyl("Arm", "Thumb", V3(-.75, 2.3, -.2), V3(-.85, 2.7, -.45), .12, COL.Claw, MAT.SmoothPlastic, { Shadow = false })
	b:Ball("Arm", "Glow", .9, V3(0, 1.4, .05), COL.Purple, MAT.Neon, { Shadow = false, T = .55 })
	return b.Model
end

---------------------------------------------------------------------------------------------------------------------
-- rig helpers
---------------------------------------------------------------------------------------------------------------------
-- runtime: unanchor every part except the root (joints keep the shape), collect the motors
function Boss.Rig(model: Model)
	local rig = { Root = model.PrimaryPart, Motors = {}, Bones = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d ~= rig.Root then
				d.Anchored = false
				d.Massless = true
			end
		elseif d:IsA("Motor6D") and d.Name == "Joint" and d.Parent then
			local group = d.Parent.Parent
			if group then
				rig.Motors[group.Name] = d
				rig.Bones[group.Name] = d.Parent
			end
		end
	end
	return rig
end

-- anchored forward kinematics (previews and the offline tests): transforms[bone] = CFrame applied at the joint
function Boss.Pose(model: Model, transforms: { [string]: CFrame }?)
	transforms = transforms or {}
	local root = model.PrimaryPart
	if not root then
		return
	end
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "Joint" and d.Parent and d.Parent.Parent then
			motors[d.Parent.Parent.Name] = d
		end
	end
	local world = {}
	local function solve(name: string): CFrame
		if world[name] then
			return world[name]
		end
		local m = motors[name]
		local parentCF
		if m.Part0 == root then
			parentCF = root.CFrame
		else
			parentCF = solve(m.Part0.Parent.Name)
		end
		local cf = parentCF * m.C0 * (transforms[name] or CF()) * m.C1:Inverse()
		world[name] = cf
		return cf
	end
	for name in pairs(motors) do
		solve(name)
	end
	for name, m in pairs(motors) do
		local bonePart = m.Part1
		local cf = world[name]
		bonePart.CFrame = cf
		for _, d in ipairs(m.Part1.Parent:GetDescendants()) do
			if d:IsA("Weld") and d.Name == "W" and d.Part0 == bonePart and d.Part1 then
				d.Part1.CFrame = cf * d.C0 * d.C1:Inverse()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- pit surface (server rock placement + client telegraphs agree on it)
---------------------------------------------------------------------------------------------------------------------
-- walkable surface height of the Graveyard Pit at (x, z) from Layout.Pit (the geometry Pit.lua builds): y, kind =
-- "Floor" (arena floor), "Ramp" (8-wide lower ramp terrace -> floor), "Terrace" (ring), "Stairs" (upper ramp rim ->
-- terrace) or "Rim" (outside the opening)
function Boss.Surface(L: any, x: number, z: number): (number, string)
	local P = L.Pit
	local R, A = P.Rim, P.Arena
	if x < R.X0 or x > R.X1 or z < R.Z0 or z > R.Z1 then
		return L.FloorY, "Rim"
	end
	-- fraction along the 8-wide ramp a -> b, nil when (x, z) is off it
	local function along(a: Vector3, b: Vector3): number?
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 then
			return nil
		end
		local ux, uz = dx / len, dz / len
		local rx, rz = x - a.X, z - a.Z
		local t = (rx * ux + rz * uz) / len
		if t >= 0 and t <= 1 and math.abs(rx * uz - rz * ux) <= 4 then
			return t
		end
		return nil
	end
	for _, rp in ipairs(P.Ramps) do
		local t = along(rp.Mid, rp.Bottom)
		if t then
			return P.TerraceY + (P.FloorY - P.TerraceY) * t, "Ramp"
		end
		t = along(rp.Top, rp.Mid)
		if t then
			return L.FloorY + (P.TerraceY - L.FloorY) * t, "Stairs"
		end
	end
	if x >= A.X0 and x <= A.X1 and z >= A.Z0 and z <= A.Z1 then
		return P.FloorY, "Floor"
	end
	return P.TerraceY, "Terrace"
end

return Boss
