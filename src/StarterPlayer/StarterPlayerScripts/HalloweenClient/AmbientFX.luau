-- Ambient life of THE DEAD YARD (StarterPlayerScripts.HalloweenClient.AmbientFX), WP10b. Client only.
-- * Light life: every HwLantern / HwCandle / HwBrazier part (and jack-o'-lantern PumpkinGlow lights) flickers in
--   Brightness / Color only (WorldDetailQuality owns Light.Enabled), with "drive" writes (an external writer such as a
--   world event wins for 2 s) and a full yield while a world event is ACTIVE/ENDING. Flares: Bus "LanternFlare"
--   {Position, Radius, Strength, Seconds, Color?}. Per-part local dimming: attribute HwLocalDim (0..1) set by HouseFX.
-- * Crows on CrowPerch attachments (idle bob / peck / look / hop-turn / caw, take off when a player comes close and
--   land on another perch), the strange dog silhouette running along Layout.SilhouettePath every 45-100 s,
--   wandering ghosts between GhostPath_* points, bat flocks around BatRoost attachments at night, fireflies and
--   will-o'-wisps over the graveyard, short fog wisps curling up at FogPoint markers, chains swaying in the wind
--   (Bus "ChainKick" {Position, Radius, Strength} gives them a shove).
-- Everything: client-local parts under workspace.DOGROTS_HalloweenFX (SelfManagedFX), markers found by name/attribute with
-- streaming in mind (DescendantAdded / DescendantRemoving), budgets from Shared.Budget (Crows / Ghosts / Bats / Ambient)
-- and Shared.Quality(), everything off when the camera is > 260 studs from the yard.
-- Exports for the sibling FX modules: AmbientFX.Rig (bone rig for part-built creatures) and AmbientFX.Models
-- (Crow, Bat, Ghost, SilhouetteDog, Wisp, Candy builders: Models.X(parent?, opts?) -> rig).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local IDENT = CFrame.new()
local V3 = Vector3.new
local RGB = Color3.fromRGB
local rad = math.rad

local AmbientFX = {}

---------------------------------------------------------------------------------------------------------------------
-- Rig: part-built creature with a bone hierarchy. Parts are anchored, posed in one BulkMoveTo per update.
---------------------------------------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig
AmbientFX.Rig = Rig

local bulkOk = nil
local function bulk(parts: { BasePart }, cfs: { CFrame })
	if bulkOk ~= false then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if ok then
			bulkOk = true
			return
		end
		bulkOk = false
	end
	for i, p in ipairs(parts) do
		p.CFrame = cfs[i]
	end
end
Rig.Bulk = bulk

function Rig.new(name: string, parent: Instance?)
	local m = Instance.new("Model")
	m.Name = name
	local root = { Name = "Root", Pivot = IDENT, Local = IDENT }
	local self = setmetatable({
		Model = m, Bones = { Root = root }, Order = { root }, Parts = {}, Locals = {}, BoneOf = {}, Base = {}, BaseColor = {},
		Fade = 0, Root = IDENT, World = {}, Scale = 1,
	}, Rig)
	if parent then
		m.Parent = parent
	end
	return self
end

-- bone pivot in rig rest space (origin = feet / centre, forward = -Z)
function Rig:Bone(name: string, parentName: string?, pivot: CFrame)
	local parent = self.Bones[parentName or "Root"]
	local b = { Name = name, Parent = parent, Pivot = pivot, Local = parent.Pivot:Inverse() * pivot }
	self.Bones[name] = b
	table.insert(self.Order, b)
	return b
end

-- opts: Shape ("Ball"|"Cylinder"), Class ("WedgePart"|"CornerWedgePart"), Mesh ("Sphere"), T (transparency), Name,
--       Reflectance, Glow (true = part is an emissive accent; Color tweaks keep it)
function Rig:Part(bone: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): BasePart
	opts = opts or {}
	local p = Instance.new(opts.Class or "Part")
	if opts.Shape == "Ball" then
		(p :: any).Shape = Enum.PartType.Ball
	elseif opts.Shape == "Cylinder" then
		(p :: any).Shape = Enum.PartType.Cylinder
	end
	p.Name = opts.Name or bone
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = opts.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = opts.T or 0
	p.Reflectance = opts.Reflectance or 0
	if opts.Mesh == "Sphere" then
		local sm = Instance.new("SpecialMesh")
		sm.MeshType = Enum.MeshType.Sphere
		sm.Parent = p
	end
	p.CFrame = cf
	p.Parent = self.Model
	local b = self.Bones[bone] or self.Bones.Root
	table.insert(self.Parts, p)
	local i = #self.Parts
	self.Locals[i] = b.Pivot:Inverse() * cf
	self.BoneOf[i] = b
	self.Base[i] = p.Transparency
	self.BaseColor[i] = color
	return p
end

-- uniform scale (call before the first Update)
function Rig:SetScale(k: number)
	if math.abs(k - 1) < 1e-4 then
		return self
	end
	local function sc(cf: CFrame): CFrame
		return CFrame.new(cf.Position * k) * (cf - cf.Position)
	end
	for _, b in ipairs(self.Order) do
		b.Pivot = sc(b.Pivot)
		b.Local = sc(b.Local)
	end
	for i, p in ipairs(self.Parts) do
		self.Locals[i] = sc(self.Locals[i])
		p.Size = p.Size * k
	end
	self.Scale *= k
	return self
end

function Rig:Update(rootCF: CFrame, pose: { [string]: CFrame }?)
	self.Root = rootCF
	local world = self.World
	for _, b in ipairs(self.Order) do
		local q = pose and pose[b.Name]
		if b.Parent == nil then
			world[b] = q and rootCF * q or rootCF
		else
			local w = world[b.Parent] * b.Local
			world[b] = q and w * q or w
		end
	end
	local cfs = table.create(#self.Parts)
	for i = 1, #self.Parts do
		cfs[i] = world[self.BoneOf[i]] * self.Locals[i]
	end
	bulk(self.Parts, cfs)
end

function Rig:BoneWorld(name: string): CFrame
	local b = self.Bones[name]
	return (b and self.World[b]) or self.Root
end

-- 0 = as built, 1 = invisible
function Rig:SetFade(f: number)
	f = math.clamp(f, 0, 1)
	if math.abs(f - self.Fade) < .004 then
		return
	end
	self.Fade = f
	for i, p in ipairs(self.Parts) do
		local b = self.Base[i]
		if b < 1 then
			p.Transparency = b + (1 - b) * f
		end
	end
end

function Rig:Tint(color: Color3, alpha: number, filter: ((BasePart) -> boolean)?)
	for i, p in ipairs(self.Parts) do
		if not filter or filter(p) then
			p.Color = self.BaseColor[i]:Lerp(color, alpha)
		end
	end
end

function Rig:Destroy()
	self.Dead = true
	self.Model:Destroy()
end

---------------------------------------------------------------------------------------------------------------------
-- Part-built models (rest space: feet / centre at the origin, facing -Z)
---------------------------------------------------------------------------------------------------------------------
local Models = {}
AmbientFX.Models = Models

local C = {
	Crow = RGB(24, 21, 32), CrowSheen = RGB(44, 38, 66), Beak = RGB(46, 40, 44), CrowEye = RGB(255, 196, 70), Leg = RGB(58, 52, 58),
	Bat = RGB(36, 24, 44), BatWing = RGB(54, 34, 66), BatEye = RGB(255, 60, 70),
	Ghost = RGB(214, 238, 255), GhostCore = RGB(140, 220, 255), GhostEye = RGB(18, 22, 44),
	Shadow = RGB(9, 7, 13), ShadowEye = RGB(205, 255, 140),
	Wisp = RGB(150, 255, 170),
}
AmbientFX.Colors = C

local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- CROW (~1.3 tall perched). Bones: Body, Head, Jaw, WingL, WingR, Tail, Legs. Rest pose = wings spread (flight).
function Models.Crow(parent: Instance?, opts: { [string]: any }?): any
	local r = Rig.new("HwCrow", parent)
	r:Bone("Legs", "Root", at(0, .5, .02))
	r:Bone("Body", "Root", at(0, .62, .05))
	r:Bone("Head", "Body", at(0, 1.02, -.42))
	r:Bone("Jaw", "Head", at(0, 1.1, -.78))
	r:Bone("WingL", "Body", at(-.3, .96, -.12))
	r:Bone("WingR", "Body", at(.3, .96, -.12))
	r:Bone("Tail", "Body", at(0, .76, .5))
	local mat = Enum.Material.SmoothPlastic
	r:Part("Body", V3(.72, .66, 1.12), at(0, .78, .06) * ang(-8, 0, 0), C.Crow, mat, { Mesh = "Sphere", Reflectance = .04 })
	r:Part("Body", V3(.62, .6, .62), at(0, .86, -.3), C.Crow, mat, { Mesh = "Sphere" })
	r:Part("Body", V3(.5, .24, .7), at(0, 1.04, .02) * ang(-6, 0, 0), C.CrowSheen, mat, { Mesh = "Sphere" })
	r:Part("Head", V3(.48, .46, .52), at(0, 1.2, -.6), C.Crow, mat, { Mesh = "Sphere", Reflectance = .05 })
	r:Part("Head", V3(.4, .14, .3), at(0, 1.36, -.56), C.CrowSheen, mat, { Mesh = "Sphere" })
	r:Part("Head", V3(.14, .12, .42), at(0, 1.19, -.98), C.Beak, mat, { Class = "WedgePart", Name = "Beak" })
	r:Part("Jaw", V3(.12, .06, .32), at(0, 1.1, -.93) * ang(0, 0, 180), C.Beak, mat, { Class = "WedgePart", Name = "Beak" })
	for s = -1, 1, 2 do
		r:Part("Head", V3(.08, .08, .08), at(s * .19, 1.25, -.78), C.CrowEye, Enum.Material.Neon, { Shape = "Ball", Name = "Eye" })
		local wing = s < 0 and "WingL" or "WingR"
		-- spread wing: inner arm, secondaries, primaries fanned to the tip
		r:Part(wing, V3(.72, .07, .5), at(s * .66, .96, -.06), C.Crow, mat, { Name = "Wing" })
		r:Part(wing, V3(.62, .05, .42), at(s * .7, .95, .32) * ang(0, s * 8, 0), C.CrowSheen, mat, { Name = "Wing" })
		r:Part(wing, V3(.7, .05, .34), at(s * 1.28, .97, .02) * ang(0, s * -10, 0), C.Crow, mat, { Name = "Wing" })
		for k = 0, 2 do
			r:Part(wing, V3(.16, .04, .44), at(s * (1.5 + k * .13), .97, .14 + k * .06) * ang(0, s * (-12 + k * 9), 0), C.CrowSheen, mat, { Name = "Feather" })
		end
		r:Part("Legs", V3(.06, .4, .06), at(s * .12, .26, .02), C.Leg, mat, { Name = "Leg" })
		r:Part("Legs", V3(.08, .04, .3), at(s * .12, .04, -.06), C.Leg, mat, { Name = "Foot" })
	end
	r:Part("Tail", V3(.42, .06, .66), at(0, .72, .86) * ang(14, 0, 0), C.Crow, mat, { Name = "Tail" })
	r:Part("Tail", V3(.3, .05, .5), at(0, .66, 1.02) * ang(18, 0, 0), C.CrowSheen, mat, { Name = "Tail" })
	r:Update(IDENT, Models.CrowPose(0, "Perch", 0))
	return r
end

-- pose: mode "Perch" (folded) | "Fly" (flap phase) | "Glide"; t = seconds; extra = {Peck, Look, Caw, Ruffle, Tuck}
function Models.CrowPose(t: number, mode: string, flap: number, extra: { [string]: number }?): { [string]: CFrame }
	extra = extra or {}
	local pose = {}
	if mode == "Perch" then
		local ruffle = (extra.Ruffle or 0) * 18
		-- folded: span turned back along the body, chord vertical against the flank, tips drooping over the tail
		pose.WingL = at(.19, .05, 0) * ang(5, 0, 0) * ang(0, 0, -112 + ruffle) * ang(0, 90, 0)
		pose.WingR = at(-.19, .05, 0) * ang(5, 0, 0) * ang(0, 0, 112 - ruffle) * ang(0, -90, 0)
		pose.Body = ang(-(extra.Peck or 0) * 16 + math.sin(t * 2.1) * 1.2, 0, 0)
		pose.Head = ang(-(extra.Peck or 0) * 44 + (extra.Caw or 0) * 26, (extra.Look or 0), 0)
		pose.Jaw = ang((extra.Caw or 0) * 26, 0, 0)
		pose.Tail = ang(math.sin(t * 1.3) * 4 - (extra.Peck or 0) * 10, 0, 0)
	else
		local a = mode == "Glide" and (6 + math.sin(t * 2) * 4) or (math.sin(flap) * 52 + 8)
		pose.WingL = ang(0, 0, a)
		pose.WingR = ang(0, 0, -a)
		pose.Body = ang(mode == "Glide" and -2 or -8, 0, 0)
		pose.Head = ang(10, 0, 0)
		pose.Tail = ang(-6 + math.sin(t * 3) * 3, 0, 0)
		pose.Legs = ang(-(extra.Tuck or 1) * 70, 0, 0) * at(0, .08 * (extra.Tuck or 1), .1 * (extra.Tuck or 1))
	end
	return pose
end

-- BAT (~1.7 span). Bones: WingL, WingR, WingL2, WingR2 (elbows), Head.
function Models.Bat(parent: Instance?, opts: { [string]: any }?): any
	local r = Rig.new("HwBat", parent)
	r:Bone("Head", "Root", at(0, .1, -.2))
	r:Bone("WingL", "Root", at(-.14, .08, -.04))
	r:Bone("WingR", "Root", at(.14, .08, -.04))
	r:Bone("WingL2", "WingL", at(-.56, .08, -.04))
	r:Bone("WingR2", "WingR", at(.56, .08, -.04))
	local mat = Enum.Material.SmoothPlastic
	r:Part("Root", V3(.3, .28, .5), at(0, 0, .04), C.Bat, mat, { Mesh = "Sphere" })
	r:Part("Head", V3(.24, .22, .24), at(0, .08, -.3), C.Bat, mat, { Mesh = "Sphere" })
	for s = -1, 1, 2 do
		r:Part("Head", V3(.05, .16, .1), at(s * .07, .24, -.3) * ang(0, 0, s * -12), C.Bat, mat, { Class = "WedgePart", Name = "Ear" })
		r:Part("Head", V3(.045, .045, .045), at(s * .06, .11, -.41), C.BatEye, Enum.Material.Neon, { Shape = "Ball", Name = "Eye" })
		local w1, w2 = s < 0 and "WingL" or "WingR", s < 0 and "WingL2" or "WingR2"
		r:Part(w1, V3(.44, .035, .36), at(s * .36, .08, .02), C.BatWing, mat, { Name = "Membrane" })
		r:Part(w1, V3(.46, .05, .05), at(s * .37, .1, -.14), C.Bat, mat, { Name = "Arm" })
		r:Part(w2, V3(.42, .03, .4), at(s * .78, .08, .04) * ang(0, s * -10, 0), C.BatWing, mat, { Name = "Membrane" })
		r:Part(w2, V3(.06, .03, .2), at(s * .98, .08, .22) * ang(0, s * 30, 0), C.BatWing, mat, { Class = "WedgePart", Name = "Scallop" })
		r:Part(w2, V3(.06, .03, .18), at(s * .66, .08, .26) * ang(0, s * 20, 0), C.BatWing, mat, { Class = "WedgePart", Name = "Scallop" })
	end
	r:Update(IDENT, Models.BatPose(.6))
	return r
end

function Models.BatPose(flap: number): { [string]: CFrame }
	local a = math.sin(flap) * 55
	local b = math.sin(flap - .6) * 30
	return { WingL = ang(0, 0, a), WingR = ang(0, 0, -a), WingL2 = ang(0, 0, b), WingR2 = ang(0, 0, -b), Head = ang(math.sin(flap * .5) * 6, 0, 0) }
end

-- GHOST: a spectral dog (~3.2 tall incl. the wispy tail). Bones: Body, Head, EarL, EarR, Tail1..3.
function Models.Ghost(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local r = Rig.new("HwGhost", parent)
	local tint = opts.Color or C.Ghost
	local core = opts.Core or C.GhostCore
	local mat = Enum.Material.SmoothPlastic
	r:Bone("Body", "Root", at(0, 1.5, 0))
	r:Bone("Head", "Body", at(0, 2.05, -.25))
	r:Bone("EarL", "Head", at(-.55, 2.95, -.1))
	r:Bone("EarR", "Head", at(.55, 2.95, -.1))
	r:Bone("Tail1", "Body", at(0, 1.05, .55))
	r:Bone("Tail2", "Tail1", at(0, .6, 1.0))
	r:Bone("Tail3", "Tail2", at(0, .28, 1.4))
	r:Part("Body", V3(1.55, 1.5, 1.85), at(0, 1.55, .18), tint, mat, { Mesh = "Sphere", T = .42, Name = "Sheet" })
	r:Part("Body", V3(.85, .85, .9), at(0, 1.7, 0), core, Enum.Material.Neon, { Mesh = "Sphere", T = .72, Name = "Core" })
	for s = -1, 1, 2 do
		r:Part("Body", V3(.34, .55, .36), at(s * .44, 1.02, -.62), tint, mat, { Mesh = "Sphere", T = .4, Name = "Paw" })
	end
	r:Part("Head", V3(1.42, 1.28, 1.36), at(0, 2.55, -.35), tint, mat, { Mesh = "Sphere", T = .32, Name = "Skull" })
	r:Part("Head", V3(.78, .58, .86), at(0, 2.33, -1.08), tint, mat, { Mesh = "Sphere", T = .3, Name = "Snout" })
	r:Part("Head", V3(.22, .17, .16), at(0, 2.47, -1.5), C.GhostEye, mat, { Mesh = "Sphere", T = .15, Name = "Nose" })
	r:Part("Head", V3(.42, .12, .1), at(0, 2.14, -1.38), C.GhostEye, mat, { Mesh = "Sphere", T = .3, Name = "Mouth" })
	for s = -1, 1, 2 do
		r:Part("Head", V3(.27, .38, .12), at(s * .31, 2.72, -.98) * ang(0, s * -14, s * 8), C.GhostEye, mat, { Mesh = "Sphere", T = .08, Name = "Eye" })
		r:Part("Head", V3(.08, .08, .05), at(s * .3, 2.78, -1.05), core, Enum.Material.Neon, { Shape = "Ball", T = .1, Name = "EyeGlint" })
		r:Part(s < 0 and "EarL" or "EarR", V3(.34, .95, .55), at(s * .78, 2.5, -.12) * ang(0, 0, s * 24), tint, mat, { Mesh = "Sphere", T = .38, Name = "Ear" })
	end
	r:Part("Tail1", V3(1.1, 1.0, 1.1), at(0, .85, .72), tint, mat, { Mesh = "Sphere", T = .5, Name = "Wisp" })
	r:Part("Tail2", V3(.72, .66, .8), at(0, .44, 1.14), tint, mat, { Mesh = "Sphere", T = .58, Name = "Wisp" })
	r:Part("Tail3", V3(.42, .4, .55), at(.04, .2, 1.5), tint, mat, { Mesh = "Sphere", T = .66, Name = "Wisp" })
	r:Part("Tail3", V3(.22, .22, .32), at(.1, .1, 1.8), tint, mat, { Mesh = "Sphere", T = .74, Name = "Wisp" })
	r:Update(IDENT, Models.GhostPose(0))
	return r
end

function Models.GhostPose(t: number, look: number?): { [string]: CFrame }
	return {
		Body = ang(math.sin(t * 1.4) * 3, 0, math.sin(t * .9) * 4),
		Head = ang(math.sin(t * 1.1 + 1) * 5, look or 0, 0),
		EarL = ang(0, 0, math.sin(t * 2.2) * 10 - 4),
		EarR = ang(0, 0, -math.sin(t * 2.2 + .5) * 10 + 4),
		Tail1 = ang(math.sin(t * 2.4) * 10, math.sin(t * 1.7) * 18, 0),
		Tail2 = ang(math.sin(t * 2.4 - .8) * 14, math.sin(t * 1.7 - .9) * 24, 0),
		Tail3 = ang(math.sin(t * 2.4 - 1.6) * 18, math.sin(t * 1.7 - 1.8) * 30, 0),
	}
end

-- THE SILHOUETTE: a lanky, absolutely black voxel dog with glowing eyes (~5.3 tall at the ears). Gallop pose below.
function Models.SilhouetteDog(parent: Instance?, opts: { [string]: any }?): any
	local r = Rig.new("HwSilhouetteDog", parent)
	local k = C.Shadow
	local mat = Enum.Material.SmoothPlastic
	r:Bone("Body", "Root", at(0, 3.1, .1))
	r:Bone("Neck", "Body", at(0, 3.55, -1.55))
	r:Bone("Head", "Neck", at(0, 4.35, -2.2))
	r:Bone("Tail", "Body", at(0, 3.45, 2.15))
	r:Bone("Tail2", "Tail", at(0, 3.25, 3.15))
	for s = -1, 1, 2 do
		local n = s < 0 and "L" or "R"
		r:Bone("FU" .. n, "Body", at(s * .46, 2.95, -1.25))
		r:Bone("FL" .. n, "FU" .. n, at(s * .46, 1.6, -1.25))
		r:Bone("BU" .. n, "Body", at(s * .44, 3.0, 1.7))
		r:Bone("BL" .. n, "BU" .. n, at(s * .44, 1.75, 2.05))
	end
	r:Part("Body", V3(1.25, 1.15, 3.2), at(0, 3.12, .25), k, mat, { Name = "Torso" })
	r:Part("Body", V3(1.45, 1.55, 1.3), at(0, 3.15, -1.15), k, mat, { Name = "Chest" })
	r:Part("Body", V3(1.2, 1.1, 1.0), at(0, 3.1, 1.75), k, mat, { Name = "Hips" })
	r:Part("Body", V3(.9, .5, 2.6), at(0, 2.5, .2), k, mat, { Name = "Belly" })
	r:Part("Body", V3(.5, .3, 3.6), at(0, 3.78, .1), k, mat, { Name = "Spine" })
	for i = 0, 4 do
		r:Part("Body", V3(.22, .34, .22), at(0, 3.95 + (i % 2) * .08, -1.2 + i * .7) * ang(-20, 0, 0), k, mat, { Class = "WedgePart", Name = "Spike" })
	end
	r:Part("Neck", V3(.8, 1.35, .9), at(0, 3.95, -1.95) * ang(-34, 0, 0), k, mat, { Name = "Neck" })
	r:Part("Head", V3(1.1, .95, 1.25), at(0, 4.55, -2.5), k, mat, { Name = "Skull" })
	r:Part("Head", V3(.66, .55, 1.1), at(0, 4.33, -3.5), k, mat, { Name = "Snout" })
	r:Part("Head", V3(.6, .22, .9), at(0, 4.0, -3.35), k, mat, { Name = "Jaw" })
	for s = -1, 1, 2 do
		r:Part("Head", V3(.28, .85, .34), at(s * .36, 5.32, -2.25) * ang(-12, 0, s * -10), k, mat, { Class = "WedgePart", Name = "Ear" })
		r:Part("Head", V3(.26, .15, .06), at(s * .3, 4.66, -3.13), C.ShadowEye, Enum.Material.Neon, { Name = "Eye" })
		r:Part("Head", V3(.5, .32, .05), at(s * .3, 4.66, -3.15), C.ShadowEye, Enum.Material.Neon, { Mesh = "Sphere", Name = "EyeGlow", T = .62 })
		local n = s < 0 and "L" or "R"
		r:Part("FU" .. n, V3(.42, 1.55, .5), at(s * .46, 2.2, -1.25), k, mat, { Name = "Leg" })
		r:Part("FL" .. n, V3(.32, 1.55, .36), at(s * .46, .85, -1.25), k, mat, { Name = "Leg" })
		r:Part("FL" .. n, V3(.44, .22, .62), at(s * .46, .11, -1.4), k, mat, { Name = "Paw" })
		r:Part("BU" .. n, V3(.5, 1.45, .66), at(s * .44, 2.35, 1.85) * ang(-14, 0, 0), k, mat, { Name = "Thigh" })
		r:Part("BL" .. n, V3(.32, 1.7, .36), at(s * .44, .95, 2.05), k, mat, { Name = "Leg" })
		r:Part("BL" .. n, V3(.44, .22, .62), at(s * .44, .11, 1.95), k, mat, { Name = "Paw" })
	end
	r:Part("Tail", V3(.32, .32, 1.1), at(0, 3.38, 2.65) * ang(18, 0, 0), k, mat, { Name = "Tail" })
	r:Part("Tail2", V3(.22, .22, 1.0), at(0, 3.15, 3.6) * ang(28, 0, 0), k, mat, { Name = "Tail" })
	r:Update(IDENT, Models.DogPose(0, 0))
	return r
end

-- gallop: phase in radians (one stride = 2*pi), run 0..1 (0 = standing)
function Models.DogPose(phase: number, run: number, look: number?): { [string]: CFrame }
	local s = math.sin(phase)
	local pose = {
		Root = at(0, math.abs(math.sin(phase)) * .35 * run, 0),
		Body = ang(s * 5 * run, 0, 0),
		Neck = ang(-s * 6 * run, 0, 0),
		Head = ang(s * 5 * run, look or 0, 0),
		Tail = ang(-14 * run + math.sin(phase * .5) * 6, math.sin(phase * .7) * 8, 0),
		Tail2 = ang(-10 * run, math.sin(phase * .7 - .6) * 12, 0),
	}
	for side = -1, 1, 2 do
		local n = side < 0 and "L" or "R"
		local off = side < 0 and 0 or .35
		local fs = math.sin(phase + off)
		local bs = math.sin(phase + 2.6 + off)
		pose["FU" .. n] = ang(fs * 42 * run, 0, 0)
		pose["FL" .. n] = ang(math.max(0, -math.cos(phase + off)) * 55 * run, 0, 0)
		pose["BU" .. n] = ang(bs * 38 * run, 0, 0)
		pose["BL" .. n] = ang(-math.max(0, math.cos(phase + 2.6 + off)) * 50 * run, 0, 0)
	end
	return pose
end

-- WILL-O'-WISP: glowing orb with a halo (Trail attachments A0/A1 on the core)
function Models.Wisp(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local r = Rig.new("HwWisp", parent)
	local col = opts.Color or C.Wisp
	local core = r:Part("Root", V3(.42, .42, .42), IDENT, col, Enum.Material.Neon, { Shape = "Ball", Name = "Core" })
	r:Part("Root", V3(.95, .95, .95), IDENT, col, Enum.Material.Neon, { Shape = "Ball", T = .82, Name = "Halo" })
	local a0 = Instance.new("Attachment")
	a0.Name = "A0"
	a0.Position = V3(0, .18, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Name = "A1"
	a1.Position = V3(0, -.18, 0)
	a1.Parent = core
	pcall(function()
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = .9
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Color = ColorSequence.new(col)
		tr.Transparency = NumberSequence.new(.35, 1)
		tr.WidthScale = NumberSequence.new(1, 0)
		tr.Parent = core
		r.Trail = tr
	end)
	r:Update(IDENT)
	return r
end

-- wrapped candy (~0.9 long): centre + twisted wrapper ends + stripe
function Models.Candy(parent: Instance?, opts: { [string]: any }?): any
	opts = opts or {}
	local col = opts.Color or RGB(255, 128, 24)
	local stripe = opts.Stripe or RGB(255, 242, 208)
	local r = Rig.new("HwCandy", parent)
	r:Part("Root", V3(.46, .42, .42), IDENT, col, Enum.Material.SmoothPlastic, { Mesh = "Sphere", Reflectance = .12, Name = "Candy" })
	r:Part("Root", V3(.1, .44, .44), IDENT, stripe, Enum.Material.SmoothPlastic, { Shape = "Cylinder", Name = "Stripe" })
	for s = -1, 1, 2 do
		r:Part("Root", V3(.12, .14, .14), at(s * .28, 0, 0), col, Enum.Material.SmoothPlastic, { Shape = "Cylinder", Name = "Twist" })
		r:Part("Root", V3(.22, .3, .3), at(s * .42, 0, 0) * ang(0, s > 0 and 0 or 180, 0), col:Lerp(stripe, .25), Enum.Material.SmoothPlastic,
			{ Class = "WedgePart", Name = "Wrapper" })
	end
	r:Update(IDENT)
	return r
end

---------------------------------------------------------------------------------------------------------------------
-- small math helpers (shared with the sibling modules)
---------------------------------------------------------------------------------------------------------------------
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
AmbientFX.Smooth = smooth

-- begin -> peak -> fade envelope over [0,1]
local function envelope(t: number, attack: number?, release: number?): number
	attack = attack or .15
	release = release or .5
	if t <= 0 or t >= 1 then
		return 0
	end
	if t < attack then
		return smooth(t / attack)
	elseif t > 1 - release then
		return smooth((1 - t) / release)
	end
	return 1
end
AmbientFX.Envelope = envelope

local function bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end
AmbientFX.Bezier = bezier

local function yawCF(pos: Vector3, dir: Vector3): CFrame
	local flat = V3(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	return CFrame.new(pos) * CFrame.Angles(0, math.atan2(-flat.X, -flat.Z), 0)
end
AmbientFX.YawCF = yawCF

-- facing `dir` with limited pitch (flying creatures)
local function flyCF(pos: Vector3, dir: Vector3, maxPitch: number?, roll: number?): CFrame
	local flat = V3(dir.X, 0, dir.Z)
	local yaw = flat.Magnitude > 1e-4 and math.atan2(-flat.X, -flat.Z) or 0
	local pitch = math.clamp(math.atan2(dir.Y, math.max(flat.Magnitude, 1e-4)), -(maxPitch or .6), maxPitch or .6)
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll or 0)
end
AmbientFX.FlyCF = flyCF

-- polyline helpers (silhouette path)
function AmbientFX.PathLength(points: { Vector3 }): number
	local len = 0
	for i = 2, #points do
		len += (points[i] - points[i - 1]).Magnitude
	end
	return len
end

function AmbientFX.PathAt(points: { Vector3 }, d: number): (Vector3, Vector3)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local seg = (b - a).Magnitude
		if d <= seg or i == #points then
			local t = seg > 0 and math.clamp(d / seg, 0, 1) or 0
			return a:Lerp(b, t), (b - a).Unit
		end
		d -= seg
	end
	return points[#points], V3(1, 0, 0)
end

-- world position of an attachment (parent part CFrame * attachment CFrame; same as WorldPosition, works offline too)
local function attPos(a: Attachment): Vector3
	local p = a.Parent
	if p and p:IsA("BasePart") then
		return (p.CFrame * a.CFrame).Position
	end
	return a.WorldPosition
end
AmbientFX.AttPos = attPos

-- zone distance in XZ (0 inside)
function AmbientFX.ZoneDistance(layout: any, pos: Vector3): number
	local a, b = layout.Zone.Min, layout.Zone.Max
	local dx = math.max(a.X - pos.X, pos.X - b.X, 0)
	local dz = math.max(a.Z - pos.Z, pos.Z - b.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- flicker factor of a light kind at time t (pure; tested offline)
function AmbientFX.Flicker(kind: string, t: number, phase: number, amp: number?): number
	amp = amp or 1
	local n1 = math.noise(t * 1.3 + phase, phase * .37)
	local n2 = math.noise(t * 6.1 + phase * 2.1, 3.3)
	if kind == "Candle" then
		return 1 + amp * (.2 * math.noise(t * 4.2 + phase, 1.7) + .12 * math.noise(t * 11 + phase, 9.1))
	elseif kind == "Brazier" then
		return 1 + amp * (.24 * math.noise(t * 5 + phase, 2.2) + .14 * math.noise(t * 13 + phase, 5.5))
	elseif kind == "Purple" then
		return 1 + amp * (.12 * math.sin(t * 1.6 + phase) + .06 * n2)
	elseif kind == "Pumpkin" then
		return 1 + amp * (.16 * math.noise(t * 3 + phase, 4.4) + .08 * n2)
	end
	return 1 + amp * (.1 * n1 + .06 * n2)
end

---------------------------------------------------------------------------------------------------------------------
-- runtime
---------------------------------------------------------------------------------------------------------------------
function AmbientFX.Start(ctx)
	local Shared, Layout, Bus, FX, Audio = ctx.Shared, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio
	local player = Players.LocalPlayer
	local rng = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = FX.Folder()

	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Layout.Zone.Center
	end
	local function zoneDist(pos: Vector3): number
		return AmbientFX.ZoneDistance(Layout, pos)
	end

	-- quality / budgets (refreshed every 2 s)
	local Q = { Quality = "High", Crows = 0, Ghosts = 0, Bats = 0, Ambient = 1, Particles = 1, Near = false, Night = true, Blood = 0 }
	local function refreshQuality()
		Q.Quality = Shared.Quality()
		Q.Crows = Shared.Budget("Crows")
		Q.Ghosts = Shared.Budget("Ghosts")
		Q.Bats = Shared.Budget("Bats")
		Q.Ambient = Shared.Budget("Ambient")
		Q.Particles = FX.Budget("Particles")
		Q.Near = Shared.Enabled() and zoneDist(camPos()) <= 260
		local night = Lighting:GetAttribute("IsNight")
		if type(night) ~= "boolean" then
			local clock = Lighting.ClockTime
			night = clock < 6.4 or clock > 17.6
		end
		local ok, bm = pcall(function()
			return Shared.BloodMoonAlpha(Shared.Now())
		end)
		Q.Blood = ok and bm or 0
		Q.Night = night or Q.Blood > .2
	end
	refreshQuality()

	local function characters(): { BasePart }
		local out = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				table.insert(out, root)
			end
		end
		return out
	end
	local charCache, charAt = {}, -1
	local function chars(): { BasePart }
		local now = os.clock()
		if now - charAt > .2 then
			charAt = now
			charCache = characters()
		end
		return charCache
	end
	local function nearestChar(pos: Vector3): number
		local best = 1e9
		for _, root in ipairs(chars()) do
			local d = (root.CFrame.Position - pos).Magnitude
			if d < best then
				best = d
			end
		end
		return best
	end

	-- world event yield (WorldEventLighting owns the district lights while ACTIVE / ENDING)
	local weState = nil
	local function worldEventBusy(): boolean
		if not weState or not weState.Parent then
			local we = RS:FindFirstChild("WorldEvents")
			weState = we and we:FindFirstChild("State")
		end
		local s = weState and weState:GetAttribute("State")
		return s == "ACTIVE" or s == "ENDING"
	end

	-------------------------------------------------------------------------------------------------------------
	-- registries (markers)
	-------------------------------------------------------------------------------------------------------------
	local lights, lightList = {}, {}
	local perches, perchList = {}, {}
	local ghostPoints, roosts, fogPoints = {}, {}, {}
	local chains, chainList = {}, {}

	local function ancestorFlag(inst: Instance, root: Instance): boolean
		local a = inst.Parent
		while a and a ~= root do
			if a:GetAttribute("HwGateLeaf") ~= nil or a:GetAttribute("HwDoor") ~= nil then
				return true
			end
			a = a.Parent
		end
		return false
	end

	local function lightKind(p: BasePart): string?
		local lan = p:GetAttribute("HwLantern")
		if type(lan) == "string" then
			return lan == "Purple" and "Purple" or "Lantern"
		end
		if p:GetAttribute("HwCandle") == true then
			return "Candle"
		end
		if p:GetAttribute("HwBrazier") == true then
			return "Brazier"
		end
		if p.Name == "PumpkinGlow" then
			return "Pumpkin"
		end
		return nil
	end

	local function addLightRec(e, l: Instance)
		if l:IsA("PointLight") or l:IsA("SpotLight") or l:IsA("SurfaceLight") then
			for _, rec in ipairs(e.Lights) do
				if rec.L == l then
					return
				end
			end
			-- the pristine brightness is shared with BloodMoonFX (WP10a) through the HwBaseBrightness attribute
			local base = l:GetAttribute("HwBaseBrightness")
			if type(base) ~= "number" then
				base = (l :: any).Brightness
				l:SetAttribute("HwBaseBrightness", base)
			end
			table.insert(e.Lights, { L = l, Base = base, Last = nil, Foreign = 0 })
		end
	end

	local function addLight(p: BasePart, kind: string)
		if lights[p] then
			return
		end
		local e = { Part = p, Kind = kind, Lights = {}, Color = p.Color, Phase = rng:NextNumber(0, 100), Pos = p.CFrame.Position,
			Faces = nil, SputterAt = os.clock() + rng:NextNumber(4, 18), Sputter = -10, Glass = kind ~= "Pumpkin" }
		for _, c in ipairs(p:GetChildren()) do
			addLightRec(e, c)
		end
		if kind == "Pumpkin" and p.Parent then
			e.Faces = {}
			for _, f in ipairs(p.Parent:GetChildren()) do
				if f:IsA("BasePart") and (f.Name == "PumpkinEye" or f.Name == "PumpkinMouth") then
					table.insert(e.Faces, { Part = f, Color = f.Color })
				end
			end
		end
		lights[p] = e
		table.insert(lightList, e)
	end

	local function addChainLink(link: BasePart, root: Instance)
		local model = link.Parent
		if not model or model.Name ~= "Chain" or ancestorFlag(link, root) then
			return
		end
		local rec = chains[model]
		if not rec then
			rec = { Model = model, Links = {}, Rest = {}, Dirty = true, Angle = 0, Vel = 0, Phase = rng:NextNumber(0, 50) }
			chains[model] = rec
			table.insert(chainList, rec)
		end
		table.insert(rec.Links, link)
		table.insert(rec.Rest, link.CFrame)
		rec.Dirty = true
	end

	local function onAdded(inst: Instance, root: Instance)
		if inst:IsA("Attachment") then
			local n = inst.Name
			if n == "CrowPerch" then
				if not perches[inst] then
					local rec = { Att = inst, Busy = nil }
					perches[inst] = rec
					table.insert(perchList, rec)
				end
			elseif string.sub(n, 1, 9) == "GhostPath" then
				ghostPoints[inst] = true
			elseif n == "BatRoost" then
				roosts[inst] = true
			elseif n == "FogPoint" then
				fogPoints[inst] = true
			end
		elseif inst:IsA("BasePart") then
			local kind = lightKind(inst)
			if kind then
				addLight(inst, kind)
			elseif inst.Name == "ChainLink" then
				addChainLink(inst, root)
			end
		elseif inst:IsA("Light") then
			local e = inst.Parent and lights[inst.Parent :: any]
			if e then
				addLightRec(e, inst)
			end
		end
	end

	local function onRemoving(inst: Instance)
		if inst:IsA("Attachment") then
			local rec = perches[inst]
			if rec then
				perches[inst] = nil
				rec.Dead = true
			end
			ghostPoints[inst] = nil
			roosts[inst] = nil
			fogPoints[inst] = nil
		elseif inst:IsA("BasePart") then
			local e = lights[inst]
			if e then
				lights[inst] = nil
				e.Dead = true
			end
			if inst.Name == "ChainLink" then
				local rec = inst.Parent and chains[inst.Parent :: any]
				if rec then
					local i = table.find(rec.Links, inst)
					if i then
						table.remove(rec.Links, i)
						table.remove(rec.Rest, i)
						rec.Dirty = true
					end
				end
			end
		elseif inst:IsA("Model") and chains[inst] then
			chains[inst].Dead = true
			chains[inst] = nil
		end
	end

	task.spawn(function()
		local yard = nil
		while not yard do
			local d = workspace:FindFirstChild("DOGROTS_District")
			yard = d and d:FindFirstChild("38_DeadYard")
			if not yard then
				task.wait(1)
			end
		end
		yard.DescendantAdded:Connect(function(inst)
			onAdded(inst, yard)
		end)
		yard.DescendantRemoving:Connect(onRemoving)
		for i, inst in ipairs(yard:GetDescendants()) do
			onAdded(inst, yard)
			if i % 4000 == 0 then
				task.wait()
			end
		end
	end)

	local function compact(list: { any })
		for i = #list, 1, -1 do
			if list[i].Dead then
				table.remove(list, i)
			end
		end
	end

	local function keysOf(set: { [Instance]: boolean }): { Attachment }
		local out = {}
		for a in pairs(set) do
			if a.Parent then
				table.insert(out, a)
			end
		end
		return out
	end

	-------------------------------------------------------------------------------------------------------------
	-- 1. light life
	-------------------------------------------------------------------------------------------------------------
	local flares = {}
	Bus.On("LanternFlare", function(d)
		if type(d) == "table" and typeof(d.Position) == "Vector3" then
			table.insert(flares, { Pos = d.Position, R = d.Radius or 20, S = d.Strength or 1.5, T0 = os.clock(), D = d.Seconds or 2,
				Color = typeof(d.Color) == "Color3" and d.Color or nil })
		end
	end)
	local active, activeAt = {}, -1
	local WHITE = Color3.new(1, 1, 1)
	local BLACK = Color3.new(0, 0, 0)
	local function flareAt(pos: Vector3, now: number): (number, Color3?, number)
		local f, col, colA = 0, nil, 0
		for _, fl in ipairs(flares) do
			local t = (now - fl.T0) / fl.D
			if t >= 0 and t < 1 then
				local d = (pos - fl.Pos).Magnitude
				if d < fl.R then
					local env = envelope(t, .12, .7) * (1 - (d / fl.R) ^ 2)
					f += fl.S * env
					if env > colA then
						colA = env
						col = fl.Color
					end
				end
			end
		end
		return f, col, colA
	end
	local function driveLight(rec, value: number, now: number)
		local l = rec.L :: any
		if not l.Parent then
			return
		end
		local cur = l.Brightness
		if rec.Last ~= nil and math.abs(cur - rec.Last) > 1e-3 then
			rec.Foreign = now + 2 -- someone else wrote this light: let them have it
		end
		if now < rec.Foreign then
			rec.Last = cur
			return
		end
		if math.abs(value - cur) > .004 then
			l.Brightness = value
		end
		rec.Last = value
	end
	local function stepLights(now: number)
		if worldEventBusy() then
			return
		end
		local cam = camPos()
		if now - activeAt > .5 then
			activeAt = now
			compact(lightList)
			for i = #flares, 1, -1 do
				if now - flares[i].T0 > flares[i].D then
					table.remove(flares, i)
				end
			end
			table.clear(active)
			local maxN = Q.Quality == "Low" and 24 or Q.Quality == "Medium" and 60 or 110
			local cand = {}
			for _, e in ipairs(lightList) do
				if e.Part.Parent then
					local d = (e.Pos - cam).Magnitude
					local range = (e.Kind == "Candle" or e.Kind == "Pumpkin") and 100 or 170
					if d < range then
						table.insert(cand, { E = e, D = d })
					end
				end
			end
			table.sort(cand, function(a, b)
				return a.D < b.D
			end)
			for i = 1, math.min(maxN, #cand) do
				active[i] = cand[i].E
				cand[i].E.Dist = cand[i].D
			end
		end
		local blood = Q.Blood
		-- BloodMoonFX flickers the HwLantern lights itself during the Blood Moon (FX folder attribute HwBloodFlicker)
		local bmOwns = (FX.Folder():GetAttribute("HwBloodFlicker") or 0) > 0
		for _, e in ipairs(active) do
			local lantern = e.Kind == "Lantern" or e.Kind == "Purple"
			if not e.Dead and not (bmOwns and lantern) then
				-- sputter: begin -> dip -> recover
				if now >= e.SputterAt then
					e.Sputter = now
					e.SputterAt = now + rng:NextNumber(5, 20) / (1 + blood * 2)
				end
				local sp = now - e.Sputter
				local dip = 0
				if e.Kind ~= "Purple" and sp < .45 then
					dip = (sp < .08 and smooth(sp / .08) or smooth(1 - (sp - .08) / .37)) * (.45 + blood * .25)
				end
				local f = AmbientFX.Flicker(e.Kind, now, e.Phase, 1 + blood * 1.2) * (1 - dip)
				local fl, flCol, flA = flareAt(e.Pos, now)
				f *= 1 + fl
				local dim = e.Part:GetAttribute("HwLocalDim")
				if type(dim) == "number" then
					f *= math.clamp(dim, 0, 1)
				end
				for _, rec in ipairs(e.Lights) do
					driveLight(rec, rec.Base * math.max(0, f), now)
				end
				-- glow colour (near ones only: cheap, client-local)
				if (e.Dist or 0) < 90 then
					local base = e.Color
					local target
					if f >= 1 then
						target = base:Lerp(flCol or WHITE, math.clamp((f - 1) * .28 + flA * .3, 0, .55))
					else
						target = base:Lerp(BLACK, math.clamp((1 - f) * .55, 0, .7))
					end
					if e.Glass then
						e.Part.Color = target
					end
					if e.Faces then
						for _, face in ipairs(e.Faces) do
							if face.Part.Parent then
								face.Part.Color = face.Color:Lerp(f >= 1 and WHITE or BLACK, math.clamp(math.abs(f - 1) * .4, 0, .5))
							end
						end
					end
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 2. crows
	-------------------------------------------------------------------------------------------------------------
	local crows = {}
	local crowPopAt = -1
	local nextCaw = os.clock() + rng:NextNumber(3, 8)
	local function freePerch(from: Vector3?, minD: number, maxD: number): any
		compact(perchList)
		local cam = camPos()
		local cands = {}
		for _, rec in ipairs(perchList) do
			if not rec.Busy and rec.Att.Parent then
				local pos = attPos(rec.Att)
				local dc = (pos - cam).Magnitude
				local df = from and (pos - from).Magnitude or 50
				if dc < 170 and df >= minD and df <= maxD and nearestChar(pos) > 14 then
					table.insert(cands, rec)
				end
			end
		end
		if #cands == 0 then
			return nil
		end
		return cands[rng:NextInteger(1, #cands)]
	end
	local function spawnCrow()
		local perch = freePerch(nil, 0, 1e9)
		if not perch then
			return
		end
		local rig = Models.Crow(folder)
		rig:SetScale(rng:NextNumber(.85, 1.1))
		perch.Busy = rig
		local c = { Rig = rig, State = "Perch", Perch = perch, Pos = attPos(perch.Att), Yaw = rng:NextNumber(0, math.pi * 2),
			T = rng:NextNumber(0, 10), Peck = 0, PeckAt = os.clock() + rng:NextNumber(2, 6), Look = 0, LookTarget = 0,
			LookAt = 0, HopAt = os.clock() + rng:NextNumber(5, 12), Hop = -10, HopFrom = 0, HopTo = 0, Caw = -10, Ruffle = -10,
			RuffleAt = os.clock() + rng:NextNumber(6, 16), Fade = 1 }
		rig:SetFade(1)
		table.insert(crows, c)
	end
	local function takeOff(c, leave: boolean)
		local from = c.Pos
		local dest = (not leave) and freePerch(from, 22, 95) or nil
		if c.Perch then
			c.Perch.Busy = nil
			c.Perch = nil
		end
		local destPos
		if dest then
			dest.Busy = c.Rig
			c.Perch = dest
			destPos = attPos(dest.Att)
		else
			local a = rng:NextNumber(0, math.pi * 2)
			destPos = from + V3(math.cos(a) * 110, rng:NextNumber(35, 55), math.sin(a) * 110)
			c.Leaving = true
		end
		local dir = (destPos - from)
		local flat = V3(dir.X, 0, dir.Z)
		flat = flat.Magnitude > .1 and flat.Unit or V3(1, 0, 0)
		local len = dir.Magnitude
		c.Path = { from, from + V3(0, 5 + len * .08, 0) + flat * 4, destPos + V3(0, 6 + len * .1, 0) - flat * 5, destPos }
		c.FlyT, c.FlyDur = 0, math.clamp(len / 13, 1.8, 7)
		c.State = "Fly"
		if rng:NextNumber() < .55 then
			Audio.Play("CrowCaw", from, { Volume = .8, Pitch = rng:NextNumber(.92, 1.1) })
		end
	end
	local function stepCrows(dt: number, now: number)
		local want = Q.Near and math.floor(Q.Crows + .5) or 0
		-- population (one change per second)
		if now - crowPopAt > 1 then
			crowPopAt = now
			local perched = 0
			for _, c in ipairs(crows) do
				if not c.Leaving then
					perched += 1
				end
			end
			if perched < want and #perchList > 0 then
				spawnCrow()
			elseif perched > want then
				for _, c in ipairs(crows) do
					if not c.Leaving then
						if c.State == "Perch" and Q.Near then
							takeOff(c, true)
						else
							c.Leaving, c.Kill = true, true
						end
						break
					end
				end
			end
		end
		local cam = camPos()
		for i = #crows, 1, -1 do
			local c = crows[i]
			c.T += dt
			local dist = (c.Pos - cam).Magnitude
			c.Fade = math.max(0, c.Fade - dt * 1.5)
			if c.Kill or (c.Perch and c.Perch.Dead and c.State == "Perch") then
				if c.Perch then
					c.Perch.Busy = nil
				end
				c.Rig:Destroy()
				table.remove(crows, i)
			elseif c.State == "Perch" then
				if c.Perch and c.Perch.Att.Parent then
					c.Pos = attPos(c.Perch.Att)
				end
				-- idle behaviours
				if now >= c.PeckAt then
					c.Peck = now
					c.PeckAt = now + rng:NextNumber(2.5, 7)
				end
				if now >= c.LookAt then
					c.LookTarget = rng:NextNumber(-70, 70)
					c.LookAt = now + rng:NextNumber(1.2, 3.5)
				end
				if now >= c.HopAt then
					c.Hop, c.HopFrom = now, c.Yaw
					c.HopTo = c.Yaw + rad(rng:NextNumber(35, 110)) * (rng:NextNumber() < .5 and -1 or 1)
					c.HopAt = now + rng:NextNumber(6, 15)
				end
				if now >= c.RuffleAt then
					c.Ruffle = now
					c.RuffleAt = now + rng:NextNumber(7, 18)
				end
				if now >= nextCaw and dist < 120 and Q.Near then
					nextCaw = now + rng:NextNumber(5, 13) / math.max(.35, Q.Ambient)
					c.Caw = now
					Audio.Play("CrowCaw", c.Pos, { Pitch = rng:NextNumber(.9, 1.12) })
				end
				c.Look += (c.LookTarget - c.Look) * math.min(1, dt * 6)
				local hopT = now - c.Hop
				local hopY = 0
				if hopT < .28 then
					c.Yaw = c.HopFrom + (c.HopTo - c.HopFrom) * smooth(hopT / .28)
					hopY = math.sin(hopT / .28 * math.pi) * .3
				end
				local peck = now - c.Peck < .32 and math.sin((now - c.Peck) / .32 * math.pi) or 0
				local caw = now - c.Caw < .55 and math.sin((now - c.Caw) / .55 * math.pi) or 0
				local ruffle = now - c.Ruffle < .5 and math.sin((now - c.Ruffle) / .5 * math.pi * 2) ^ 2 or 0
				if (dist < 140 or (c.SlowT or 0) > .25) then
					c.SlowT = 0
					c.Rig:Update(CFrame.new(c.Pos + V3(0, hopY, 0)) * CFrame.Angles(0, c.Yaw, 0),
						Models.CrowPose(c.T, "Perch", 0, { Peck = peck, Look = c.Look, Caw = caw, Ruffle = ruffle }))
				else
					c.SlowT = (c.SlowT or 0) + dt
				end
				c.Rig:SetFade(c.Fade)
				-- startle
				if nearestChar(c.Pos) < 9.5 then
					takeOff(c, false)
				end
			elseif c.State == "Fly" then
				c.FlyT += dt
				local t = math.clamp(c.FlyT / c.FlyDur, 0, 1)
				local et = t < .5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
				local p = bezier(c.Path[1], c.Path[2], c.Path[3], c.Path[4], et)
				local ahead = bezier(c.Path[1], c.Path[2], c.Path[3], c.Path[4], math.min(1, et + .02))
				local dir = ahead - p
				c.Pos = p
				local flapping = t < .4 or t > .8
				local mode = flapping and "Fly" or "Glide"
				local tuck = smooth(math.min(t / .15, (1 - t) / .12, 1))
				c.Rig:Update(flyCF(p, dir.Magnitude > 1e-3 and dir or V3(0, 0, -1), .5),
					Models.CrowPose(c.T, mode, c.T * (t < .4 and 15 or 11), { Tuck = tuck }))
				if c.Leaving then
					c.Rig:SetFade(smooth((t - .55) / .45))
				end
				if t >= 1 then
					if c.Leaving then
						c.Kill = true
					else
						c.State = "Perch"
						c.Yaw = math.atan2(-dir.X, -dir.Z)
						c.HopAt = now + rng:NextNumber(3, 9)
					end
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 3. the silhouette dog
	-------------------------------------------------------------------------------------------------------------
	local dog = nil
	local dogRig = nil
	local nextDog = os.clock() + rng:NextNumber(20, 45)
	local pathPts = Layout.SilhouettePath or {}
	local pathLen = #pathPts >= 2 and AmbientFX.PathLength(pathPts) or 0
	local function startDog()
		if pathLen <= 0 then
			return
		end
		local pts = table.clone(pathPts)
		if rng:NextNumber() < .5 then
			local rev = {}
			for i = #pts, 1, -1 do
				table.insert(rev, pts[i])
			end
			pts = rev
		end
		local rig = dogRig
		if not rig or rig.Dead then
			rig = Models.SilhouetteDog(folder)
			dogRig = rig
		end
		rig:SetFade(1)
		dog = { Rig = rig, Pts = pts, D = 0, Speed = rng:NextNumber(30, 38), Phase = 0, Run = 1, T = 0,
			StopAt = rng:NextNumber() < .35 and pathLen * rng:NextNumber(.3, .7) or nil, Stopped = 0, Flared = false }
	end
	local function stepDog(dt: number, now: number)
		if not dog then
			if now >= nextDog then
				nextDog = now + rng:NextNumber(45, 100)
				if Q.Near and zoneDist(camPos()) < 200 then
					startDog()
				end
			end
			return
		end
		dog.T += dt
		local stopping = dog.StopAt and dog.D >= dog.StopAt and dog.Stopped < 1.9
		if stopping then
			dog.Stopped += dt
			dog.Run = math.max(0, dog.Run - dt * 4)
			if dog.Stopped > .5 and not dog.Flared then
				dog.Flared = true
				local pos = AmbientFX.PathAt(dog.Pts, dog.D)
				if rng:NextNumber() < .6 then
					Audio.Play("Howl", pos + V3(0, 4, 0), { Volume = .7, Pitch = rng:NextNumber(.8, .95) })
				end
			end
		else
			dog.Run = math.min(1, dog.Run + dt * 3)
			dog.D += dog.Speed * dt * (.25 + .75 * dog.Run)
		end
		dog.Phase += dt * (dog.Speed / 6.5) * math.pi * 2 * math.max(.2, dog.Run)
		local pos, dir = AmbientFX.PathAt(dog.Pts, dog.D)
		-- look at the camera while stopped
		local look = 0
		if stopping then
			local cam = camPos()
			local to = (cam - pos)
			local fwd = V3(dir.X, 0, dir.Z).Unit
			local right = fwd:Cross(V3(0, 1, 0))
			local a = math.deg(math.atan2(-to:Dot(right), to:Dot(fwd)))
			look = math.clamp(a, -80, 80) * smooth(dog.Stopped / .45) * (1 - smooth((dog.Stopped - 1.5) / .4))
		end
		dog.Rig:Update(yawCF(pos, dir), Models.DogPose(dog.Phase, dog.Run, look))
		local fadeIn = smooth(dog.D / 14)
		local fadeOut = smooth((pathLen - dog.D) / 14)
		dog.Rig:SetFade(1 - math.min(fadeIn, fadeOut, dog.T / .6))
		-- eyes flare while it stares
		local flare = stopping and envelope(dog.Stopped / 1.9, .25, .4) or 0
		for _, p in ipairs(dog.Rig.Parts) do
			if p.Name == "Eye" or p.Name == "EyeGlow" then
				p.Color = C.ShadowEye:Lerp(WHITE, flare * .6)
			end
		end
		if dog.D >= pathLen then
			dog.Rig:SetFade(1) -- the rig is kept (invisible) for the next run
			dog = nil
			nextDog = math.max(nextDog, now + rng:NextNumber(45, 100))
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 4. wandering ghosts
	-------------------------------------------------------------------------------------------------------------
	local ghosts = {}
	local ghostSpawnAt = -10
	local nextWoo = 0
	local function ghostPointList(): { Vector3 }
		local out = {}
		for _, a in ipairs(keysOf(ghostPoints)) do
			table.insert(out, attPos(a))
		end
		if #out < 4 then
			local g = Layout.Graveyard
			for x = g.X0 + 8, g.X1 - 8, 18 do
				for z = g.Z0 + 10, g.Z1 - 10, 30 do
					table.insert(out, V3(x, Layout.FloorY, z))
				end
			end
		end
		return out
	end
	local function pickPoint(pts: { Vector3 }, from: Vector3?, minD: number, maxD: number): Vector3?
		local cam = camPos()
		local cands = {}
		for _, p in ipairs(pts) do
			local df = from and (p - from).Magnitude or 40
			if df >= minD and df <= maxD and (p - cam).Magnitude < 220 then
				table.insert(cands, p)
			end
		end
		if #cands == 0 then
			return nil
		end
		return cands[rng:NextInteger(1, #cands)]
	end
	local function spawnGhost()
		local pts = ghostPointList()
		local start = pickPoint(pts, nil, 0, 1e9)
		if not start then
			return
		end
		local rig = Models.Ghost(folder)
		rig:SetScale(rng:NextNumber(.75, 1.05))
		rig:SetFade(1)
		local g = { Rig = rig, Pos = start + V3(0, 1.6, 0), From = start, To = start, T = 0, Dur = 1, Legs = rng:NextInteger(3, 6),
			Fade = 1, State = "In", Yaw = rng:NextNumber(0, 6.28), Roll = 0, Age = rng:NextNumber(0, 20), Hover = rng:NextNumber(1.4, 3.2) }
		table.insert(ghosts, g)
	end
	local function stepGhosts(dt: number, now: number)
		local want = Q.Near and math.floor(Q.Ghosts + .5) or 0
		local alive = 0
		for _, g in ipairs(ghosts) do
			if g.State ~= "Out" then
				alive += 1
			end
		end
		if alive < want and now - ghostSpawnAt > 3 then
			ghostSpawnAt = now
			spawnGhost()
		elseif alive > want then
			for _, g in ipairs(ghosts) do
				if g.State ~= "Out" then
					g.State = "Out"
					break
				end
			end
		end
		local cam = camPos()
		local pts = nil
		for i = #ghosts, 1, -1 do
			local g = ghosts[i]
			g.Age += dt
			if g.State == "In" then
				g.Fade = math.max(0, g.Fade - dt / 1.4)
				if g.Fade <= 0 then
					g.State = "Move"
				end
			elseif g.State == "Out" then
				g.Fade = math.min(1, g.Fade + dt / 1.4)
				if g.Fade >= 1 then
					g.Rig:Destroy()
					table.remove(ghosts, i)
					continue
				end
			end
			-- path legs
			g.T += dt
			if g.T >= g.Dur then
				pts = pts or ghostPointList()
				local nextP = pickPoint(pts, g.To, 12, 70) or pickPoint(pts, g.To, 0, 1e9) or g.To
				g.From, g.To, g.T = g.To, nextP, 0
				g.Dur = math.max(2, (nextP - g.From).Magnitude / rng:NextNumber(4.5, 7.5))
				g.Legs -= 1
				g.Side = rng:NextNumber(-6, 6)
				if g.Legs <= 0 and g.State == "Move" then
					g.State = "Out"
				end
			end
			local t = smooth(g.T / g.Dur)
			local a, b = g.From, g.To
			local mid = (a + b) / 2
			local flat = V3(b.X - a.X, 0, b.Z - a.Z)
			local side = flat.Magnitude > .1 and flat.Unit:Cross(V3(0, 1, 0)) * (g.Side or 0) or V3()
			local u = 1 - t
			local p = a * (u * u) + (mid + side) * (2 * u * t) + b * (t * t)
			p += V3(0, g.Hover + math.sin(g.Age * 1.3) * .35, 0)
			local move = p - g.Pos
			g.Pos = p
			if move.Magnitude > 1e-3 then
				local targetYaw = math.atan2(-move.X, -move.Z)
				local dy = (targetYaw - g.Yaw + math.pi) % (2 * math.pi) - math.pi
				g.Yaw += dy * math.min(1, dt * 2.5)
				g.Roll += (math.clamp(-dy * 1.4, -.35, .35) - g.Roll) * math.min(1, dt * 3)
			end
			local dist = (p - cam).Magnitude
			local look = 0
			if dist < 16 then
				local to = cam - p
				local yawTo = math.atan2(-to.X, -to.Z)
				look = math.clamp(math.deg((yawTo - g.Yaw + math.pi) % (2 * math.pi) - math.pi), -60, 60)
				if now >= nextWoo and Q.Near then
					nextWoo = now + rng:NextNumber(14, 26)
					Audio.Play("GhostWoo", p, { Volume = .7, Pitch = rng:NextNumber(.9, 1.15) })
				end
			end
			if dist < 200 then
				g.Rig:Update(CFrame.new(p) * CFrame.Angles(0, g.Yaw, 0) * CFrame.Angles(0, 0, g.Roll), Models.GhostPose(g.Age, look))
			end
			g.Rig:SetFade(g.Fade)
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 5. bats
	-------------------------------------------------------------------------------------------------------------
	local flocks = {}
	local batAt = -10
	local function roostList(): { Vector3 }
		local out = {}
		for _, a in ipairs(keysOf(roosts)) do
			table.insert(out, attPos(a))
		end
		if #out == 0 then
			for _, c in pairs(Layout.Crypts) do
				table.insert(out, V3((c.X0 + c.X1) / 2, (c.Height or 12) + 2, (c.Z0 + c.Z1) / 2))
			end
		end
		return out
	end
	local function stepBats(dt: number, now: number)
		local want = Q.Near and math.floor(Q.Bats * (Q.Night and 1 or .3) + .5) or 0
		local count = 0
		for _, f in ipairs(flocks) do
			count += #f.Bats
		end
		if count < want and now - batAt > 1.5 then
			batAt = now
			local list = roostList()
			if #list > 0 then
				local center = list[rng:NextInteger(1, #list)]
				local f = { Center = center + V3(0, 6, 0), From = nil, To = nil, Move = 0, MoveAt = now + rng:NextNumber(20, 40), Bats = {} }
				for _ = 1, math.min(want - count, rng:NextInteger(3, 5)) do
					local rig = Models.Bat(folder)
					rig:SetScale(rng:NextNumber(.8, 1.15))
					rig:SetFade(1)
					table.insert(f.Bats, { Rig = rig, Phase = rng:NextNumber(0, 6.28), W = rng:NextNumber(.9, 1.6) * (rng:NextNumber() < .5 and -1 or 1),
						R = rng:NextNumber(5, 12), H = rng:NextNumber(-2, 5), Flap = rng:NextNumber(0, 6), Fade = 1, Last = nil })
				end
				table.insert(flocks, f)
			end
		elseif count > want then
			local f = flocks[#flocks]
			if f then
				for _, b in ipairs(f.Bats) do
					b.Out = true
				end
			end
		end
		local cam = camPos()
		for fi = #flocks, 1, -1 do
			local f = flocks[fi]
			if now >= f.MoveAt and not f.To then
				local list = roostList()
				f.From, f.To, f.Move = f.Center, list[rng:NextInteger(1, #list)] + V3(0, 6, 0), 0
				f.MoveAt = now + rng:NextNumber(25, 45)
			end
			local center = f.Center
			if f.To then
				f.Move += dt / 5
				local t = smooth(f.Move)
				center = f.From:Lerp(f.To, t) + V3(0, math.sin(t * math.pi) * 10, 0)
				if f.Move >= 1 then
					f.Center, f.To = f.To, nil
					center = f.Center
				end
			end
			for bi = #f.Bats, 1, -1 do
				local b = f.Bats[bi]
				b.Phase += dt * b.W * .9
				b.Flap += dt * (b.Gliding and 3 or 13)
				if rng:NextNumber() < dt * .4 then
					b.Gliding = not b.Gliding
				end
				local p = center + V3(math.cos(b.Phase) * b.R, b.H + math.sin(b.Phase * 2.1) * 2, math.sin(b.Phase) * b.R * .8)
				local dir = b.Last and (p - b.Last) or V3(0, 0, -1)
				b.Last = p
				b.Fade = b.Out and math.min(1, b.Fade + dt) or math.max(0, b.Fade - dt)
				if (p - cam).Magnitude < 180 then
					b.Rig:Update(flyCF(p, dir.Magnitude > 1e-4 and dir or V3(0, 0, -1), .5, -b.W * .25),
						Models.BatPose(b.Gliding and (1.2 + math.sin(b.Flap) * .2) or b.Flap))
				end
				b.Rig:SetFade(b.Fade)
				if b.Out and b.Fade >= 1 then
					b.Rig:Destroy()
					table.remove(f.Bats, bi)
				end
			end
			if #f.Bats == 0 then
				table.remove(flocks, fi)
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 6. fireflies + will-o'-wisps over the graveyard
	-------------------------------------------------------------------------------------------------------------
	local g = Layout.Graveyard
	local flyBox = FX.Part({ Name = "HwFireflies", Size = V3(g.X1 - g.X0, 3.5, g.Z1 - g.Z0), Transparency = 1,
		CFrame = CFrame.new((g.X0 + g.X1) / 2, Layout.FloorY + 2.2, (g.Z0 + g.Z1) / 2), Parent = folder })
	local flies = Instance.new("ParticleEmitter")
	flies.Name = "Fireflies"
	flies.Texture = FX.Textures.Sparkle
	flies.Color = ColorSequence.new(RGB(200, 255, 140), RGB(140, 255, 200))
	flies.LightEmission = 1
	flies.LightInfluence = 0
	flies.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.2, .28), NumberSequenceKeypoint.new(.8, .22),
		NumberSequenceKeypoint.new(1, 0) })
	flies.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.25, .1), NumberSequenceKeypoint.new(.75, .2),
		NumberSequenceKeypoint.new(1, 1) })
	flies.Lifetime = NumberRange.new(4, 7)
	flies.Speed = NumberRange.new(.3, 1.1)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Acceleration = V3(0, .15, 0)
	flies.Drag = .5
	flies.RotSpeed = NumberRange.new(-30, 30)
	flies.Shape = Enum.ParticleEmitterShape.Box
	flies.Rate = 0
	flies.Parent = flyBox
	local wisps = {}
	local function stepWisps(dt: number, now: number)
		local near = Q.Near and zoneDist(camPos()) < 160
		flies.Rate = near and (Q.Night and 7 or 3) * Q.Ambient * Q.Particles or 0
		local want = near and math.floor((Q.Quality == "Low" and 1 or Q.Quality == "Medium" and 3 or 5) * (Q.Night and 1 or .6) + .5) or 0
		if #wisps < want and rng:NextNumber() < dt then
			local rig = Models.Wisp(folder, { Color = rng:NextNumber() < .7 and C.Wisp or RGB(150, 200, 255) })
			rig:SetFade(1)
			local home = V3(rng:NextNumber(g.X0 + 4, g.X1 - 4), Layout.FloorY + rng:NextNumber(1.2, 3), rng:NextNumber(g.Z0 + 6, g.Z1 - 6))
			table.insert(wisps, { Rig = rig, Home = home, T = 0, Life = rng:NextNumber(7, 14), Seed = rng:NextNumber(0, 100) })
		end
		for i = #wisps, 1, -1 do
			local w = wisps[i]
			w.T += dt
			local k = w.T / w.Life
			if k >= 1 or (want == 0 and w.T > .1 and not w.Ending) then
				if k >= 1 then
					w.Rig:Destroy()
					table.remove(wisps, i)
					continue
				end
				w.Ending = true
				w.Life = w.T + 1
			end
			local s = w.Seed
			local p = w.Home + V3(math.noise(w.T * .25, s) * 7, math.noise(w.T * .4, s + 9) * 1.2 + math.sin(w.T * 2) * .2, math.noise(w.T * .25, s + 31) * 7)
			w.Rig:Update(CFrame.new(p))
			w.Rig:SetFade(1 - envelope(k, .12, .2) * (.85 + .15 * math.sin(w.T * 7 + s)))
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- 7. fog wisps at FogPoints (short begin -> peak -> fade puffs near the camera)
	-------------------------------------------------------------------------------------------------------------
	local fogLive = 0
	local nextFog = os.clock() + 2
	local function stepFog(now: number)
		if now < nextFog then
			return
		end
		local maxLive = Q.Quality == "Low" and 1 or Q.Quality == "Medium" and 2 or 4
		nextFog = now + rng:NextNumber(1.8, 3.6) / math.max(.35, Q.Ambient)
		if not Q.Near or fogLive >= maxLive then
			return
		end
		local cam = camPos()
		local cands = {}
		for _, a in ipairs(keysOf(fogPoints)) do
			local d = (attPos(a) - cam).Magnitude
			if d > 10 and d < 95 then
				table.insert(cands, attPos(a))
			end
		end
		if #cands == 0 then
			return
		end
		local pos = cands[rng:NextInteger(1, #cands)]
		fogLive += 1
		local wind = V3(math.cos(now * .05), 0, math.sin(now * .05))
		local dur = rng:NextNumber(3, 4.5)
		FX.Emit(pos + V3(0, .6, 0), 3.2 * Q.Ambient, dur, { Texture = FX.Textures.Smoke, Color = RGB(150, 140, 185), Color2 = RGB(80, 70, 110),
			Speed = { .6, 1.8 }, Spread = 35, Direction = (wind + V3(0, .6, 0)).Unit, Lifetime = { 3.5, 5.5 }, Size = { 2.5, 5.5, 7.5 },
			Transparency = { .72, 1 }, LightEmission = .05, Drag = .8, Acceleration = V3(wind.X * .3, .25, wind.Z * .3), Count = 1, ZOffset = 0 })
		task.delay(dur + 1, function()
			fogLive = math.max(0, fogLive - 1)
		end)
	end

	-------------------------------------------------------------------------------------------------------------
	-- 8. chains swaying in the wind (+ kicks)
	-------------------------------------------------------------------------------------------------------------
	Bus.On("ChainKick", function(d)
		if type(d) == "table" and typeof(d.Position) == "Vector3" then
			local pos, r, s = d.Position, d.Radius or 18, d.Strength or 1
			for _, rec in ipairs(chainList) do
				if not rec.Dead and rec.A then
					local dd = (rec.Mid - pos).Magnitude
					if dd < r then
						rec.Vel += s * .9 * (1 - dd / r) * (rng:NextNumber() < .5 and -1 or 1)
					end
				end
			end
		end
	end)
	local function prepChain(rec)
		rec.Dirty = false
		local n = #rec.Links
		if n < 3 then
			rec.A = nil
			return
		end
		local pa, pb, best = rec.Rest[1].Position, rec.Rest[1].Position, -1
		for i = 1, n do
			for j = i + 1, n do
				local d = (rec.Rest[i].Position - rec.Rest[j].Position).Magnitude
				if d > best then
					best, pa, pb = d, rec.Rest[i].Position, rec.Rest[j].Position
				end
			end
		end
		if pa.Y < pb.Y then
			pa, pb = pb, pa
		end
		rec.Mid = (pa + pb) / 2
		local span = pb - pa
		if math.abs(span.Y) < best * .45 then
			-- hung at both ends: swing about the line between them
			rec.A, rec.Axis, rec.Amp = pa, span.Unit, rad(4)
		else
			-- hanging from its top end: pendulum
			local h = V3(span.X, 0, span.Z)
			local axis = h.Magnitude > .2 and h.Unit:Cross(V3(0, 1, 0)) or V3(1, 0, 0)
			rec.A, rec.Axis, rec.Amp = pa, axis, rad(6)
		end
	end
	local chainActive, chainAt = {}, -1
	local function stepChains(dt: number, now: number)
		if Q.Quality == "Low" then
			return
		end
		local cam = camPos()
		if now - chainAt > .6 then
			chainAt = now
			compact(chainList)
			table.clear(chainActive)
			local range = Q.Quality == "Medium" and 45 or 75
			local maxN = Q.Quality == "Medium" and 8 or 18
			local cand = {}
			for _, rec in ipairs(chainList) do
				if rec.Dirty then
					prepChain(rec)
				end
				if rec.A then
					local d = (rec.Mid - cam).Magnitude
					if d < range then
						table.insert(cand, { R = rec, D = d })
					end
				end
			end
			table.sort(cand, function(a, b)
				return a.D < b.D
			end)
			for i = 1, math.min(maxN, #cand) do
				chainActive[i] = cand[i].R
			end
		end
		local parts, cfs = {}, {}
		for _, rec in ipairs(chainActive) do
			if not rec.Dead and rec.A then
				-- damped spring for kicks + wind
				local w = 2.3
				rec.Vel += (-w * w * rec.Angle - 2 * .1 * w * rec.Vel) * dt
				rec.Angle += rec.Vel * dt
				rec.Angle = math.clamp(rec.Angle, -.6, .6)
				local wind = rec.Amp * (.6 * math.sin(now * .9 + rec.Phase) + .4 * math.noise(now * .45, rec.Phase))
				local a = wind + rec.Angle
				local ok, rot = pcall(CFrame.fromAxisAngle, rec.Axis, a)
				if ok then
					local R = CFrame.new(rec.A) * rot * CFrame.new(-rec.A)
					for i, link in ipairs(rec.Links) do
						if link.Parent then
							table.insert(parts, link)
							table.insert(cfs, R * rec.Rest[i])
						end
					end
				end
			end
		end
		if #parts > 0 then
			bulk(parts, cfs)
		end
	end

	-- camera left the area: drop every actor at once (nobody sees them leave from > 260 studs)
	local function clearActors()
		for _, c in ipairs(crows) do
			if c.Perch then
				c.Perch.Busy = nil
			end
			c.Rig:Destroy()
		end
		table.clear(crows)
		for _, gh in ipairs(ghosts) do
			gh.Rig:Destroy()
		end
		table.clear(ghosts)
		for _, f in ipairs(flocks) do
			for _, b in ipairs(f.Bats) do
				b.Rig:Destroy()
			end
		end
		table.clear(flocks)
		for _, w in ipairs(wisps) do
			w.Rig:Destroy()
		end
		table.clear(wisps)
		flies.Rate = 0
		if dog then
			dog.Rig:SetFade(1)
			dog = nil
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- main loop
	-------------------------------------------------------------------------------------------------------------
	local qAt, lightAt = 0, 0
	local wasNear = true
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if now - qAt > 2 then
			qAt = now
			refreshQuality()
		end
		dt = math.min(dt, .1)
		if now - lightAt >= .05 then
			lightAt = now
			local okL, errL = pcall(stepLights, now)
			if not okL then
				warn("AmbientFX lights: " .. tostring(errL))
			end
		end
		if not Q.Near then
			if wasNear then
				wasNear = false
				pcall(clearActors)
			end
			return
		end
		wasNear = true
		local ok, err = pcall(function()
			stepCrows(dt, now)
			stepDog(dt, now)
			stepGhosts(dt, now)
			stepBats(dt, now)
			stepWisps(dt, now)
			stepFog(now)
			stepChains(dt, now)
		end)
		if not ok then
			warn("AmbientFX: " .. tostring(err))
		end
	end)
	player:GetAttributeChangedSignal("WorldEventFX"):Connect(refreshQuality)
end

return AmbientFX
