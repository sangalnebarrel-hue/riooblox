-- THE MOURNER · the practice dummy of the Underyard's practice ring (ReplicatedStorage.Halloween.Models.Mourner, WP-H2;
-- DESIGN §9 "Chapter II onboarding" step 5). A client-only prop: HalloweenClient.UnderyardFX stands it on its pedestal
-- (BellSquare.PracticeRing.MournerPedestal, UnderyardLayout.Square.Mourner) and idles it; the trial presenter
-- HalloweenClient.Trials.Mourner drives the wind-ups, strikes, the opening chest and the defeat. Pure Part builders
-- (Part / WedgePart / balls / cylinders, built-in materials, no assets), deterministic, so offline renders show exactly
-- what players see.
--
-- Look: a tall crooked training dummy in a tattered funeral shroud on an iron stand: a hooded head with a bone dog-skull
-- mask and violet eyes, a black lace veil, a bone ruff, long drooping sleeves (a funeral lantern in the left hand, a
-- bronze hand-bell in the right) and a ribcage over its chest that swings open to bare the glowing heart: the weak spot
-- (its centre is the server's Strike target, 3.7 studs above the pedestal top = world y 4.4).
--
-- API
--   Mourner.Build(parent?, opts?) -> rig     opts {Lite = bool (Low quality: no lace / fewer tatters), Light = bool}
--     rig.Model, rig.Parts, rig:Update(rootCF, pose), rig:BoneWorld(name), rig:SetFade(f), rig:Glow(k 0..1),
--     rig:Destroy(); rig.Heart (the weak spot part), rig.Light (PointLight in the heart, when opts.Light)
--   Mourner.Pose(state, t, k) -> pose        state: "Idle" | "WindCircle" | "StrikeCircle" | "WindLine" | "StrikeLine" |
--                                            "WindRing" | "StrikeRing" | "Hurt" | "Open" | "Defeat"; t = time (s, the idle
--                                            sway), k = 0..1 progress through the state
--   Mourner.Blend(a, b, w) -> pose           bone-wise blend of two poses (smooth transitions)
--   Mourner.HeartY (3.7) · Mourner.Height (7.6) · Mourner.Bones
-- Rest space: origin = the pedestal top under the dummy's centre, +Y up, the dummy faces -Z.
local Mourner = {}

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local IDENT = CFrame.new()
local PI = math.pi
local rad = math.rad
local MAT = Enum.Material

Mourner.HeartY = 3.7
Mourner.Height = 7.6

local COL = {
	Shroud = C(58, 46, 78), ShroudDark = C(38, 30, 54), ShroudHi = C(84, 68, 110), Lace = C(20, 14, 30),
	Bone = C(230, 222, 200), BoneDark = C(176, 164, 140), Iron = C(52, 48, 58), Wood = C(84, 62, 44),
	Eye = C(190, 120, 255), Heart = C(170, 110, 255), HeartCore = C(245, 236, 255), Candle = C(255, 170, 80),
	Bronze = C(170, 132, 70), Ink = C(16, 12, 26),
}
Mourner.Colors = COL

---------------------------------------------------------------------------------------------------------------------
-- a tiny bone rig (the HalloweenClient.AmbientFX.Rig contract, self-contained so offline tools can build it too)
---------------------------------------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig

local function bulkMove(parts: { BasePart }, cfs: { CFrame })
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

local function newRig(parent: Instance?): any
	local m = Instance.new("Model")
	m.Name = "UyMourner"
	local root = { Name = "Root", Pivot = IDENT, Local = IDENT }
	local self = setmetatable({ Model = m, Bones = { Root = root }, Order = { root }, Parts = {}, Locals = {}, BoneOf = {}, Base = {},
		World = {}, Root = IDENT, Fade = 0, GlowParts = {} }, Rig)
	if parent then
		m.Parent = parent
	end
	return self
end

function Rig:Bone(name: string, parentName: string?, pivot: CFrame)
	local parent = self.Bones[parentName or "Root"]
	local b = { Name = name, Parent = parent, Pivot = pivot, Local = parent.Pivot:Inverse() * pivot }
	self.Bones[name] = b
	table.insert(self.Order, b)
	return b
end

-- opts: Shape ("Ball" | "Cylinder"), Class ("WedgePart"), T (transparency), Name, Glow (Neon accent dimmed by :Glow)
function Rig:Part(bone: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local p = Instance.new(o.Class or "Part") :: BasePart
	if o.Shape == "Ball" then
		(p :: any).Shape = Enum.PartType.Ball
	elseif o.Shape == "Cylinder" then
		(p :: any).Shape = Enum.PartType.Cylinder
	end
	p.Name = o.Name or bone
	p.Size = size
	p.Color = color
	p.Material = material or MAT.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = o.T or 0
	p.CFrame = cf
	p.Parent = self.Model
	local b = self.Bones[bone] or self.Bones.Root
	table.insert(self.Parts, p)
	local i = #self.Parts
	self.Locals[i] = b.Pivot:Inverse() * cf
	self.BoneOf[i] = b
	self.Base[i] = p.Transparency
	if o.Glow then
		table.insert(self.GlowParts, { Part = p, Color = color })
	end
	return p
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
	bulkMove(self.Parts, cfs)
end

function Rig:BoneWorld(name: string): CFrame
	local b = self.Bones[name]
	return (b and self.World[b]) or self.Root
end

-- 0 = as built, 1 = gone
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

-- the Neon accents (eyes, heart, candle): k = 0 dim ember .. 1 full glow (2 = flaring white)
function Rig:Glow(k: number)
	k = math.clamp(k, 0, 2)
	if self.GlowK and math.abs(self.GlowK - k) < .01 then
		return
	end
	self.GlowK = k
	for _, g in ipairs(self.GlowParts) do
		local col = g.Color
		if k < 1 then
			col = COL.Ink:Lerp(col, .25 + .75 * k)
		elseif k > 1 then
			col = col:Lerp(Color3.new(1, 1, 1), (k - 1) * .6)
		end
		g.Part.Color = col
	end
	if self.Light then
		self.Light.Brightness = .4 + 1.6 * math.min(k, 1.5)
	end
end

function Rig:Destroy()
	self.Dead = true
	self.Model:Destroy()
end

---------------------------------------------------------------------------------------------------------------------
-- the build
---------------------------------------------------------------------------------------------------------------------
Mourner.Bones = { "Root", "Body", "Head", "ArmL", "ArmR", "Lantern", "Bell", "RibL", "RibR", "Heart" }

local function at(x: number, y: number, z: number): CFrame
	return CF(x, y, z)
end

function Mourner.Build(parent: Instance?, opts: { [string]: any }?): any
	local o = opts or {}
	local lite = o.Lite == true
	local r = newRig(nil)
	local HY = Mourner.HeartY
	-- bones (rest space: pedestal top = origin)
	r:Bone("Body", "Root", at(0, 2.5, 0))
	r:Bone("Head", "Body", at(0, 5.35, -.05))
	r:Bone("ArmL", "Body", at(-1.42, 5.05, 0))
	r:Bone("ArmR", "Body", at(1.42, 5.05, 0))
	r:Bone("Lantern", "ArmL", at(-1.62, 2.5, -.3))
	r:Bone("Bell", "ArmR", at(1.62, 2.55, -.3))
	r:Bone("RibL", "Body", at(-.92, HY, -.78))
	r:Bone("RibR", "Body", at(.92, HY, -.78))
	r:Bone("Heart", "Body", at(0, HY, -.5))

	-- the stand: an iron cross foot, a collar, a crooked post
	for _, yaw in ipairs({ 0, PI / 2 }) do
		r:Part("Root", V(2.8, .26, .46), at(0, .13, 0) * ANG(0, yaw + .2, 0), COL.Iron, MAT.CorrodedMetal, { Name = "StandFoot" })
	end
	r:Part("Root", V(.5, .9, .9), at(0, .4, 0) * ANG(0, 0, PI / 2), COL.Iron, MAT.CorrodedMetal, { Name = "StandCollar", Shape = "Cylinder" })
	r:Part("Root", V(.42, 2.4, .42), at(.04, 1.5, .02) * ANG(.03, 0, -.04), COL.Wood, MAT.Wood, { Name = "StandPost" })

	-- the shroud: a tapered stack from the shoulders down to the tattered hem
	local rows = { { 5.0, 1.95, 1.3 }, { 4.35, 2.05, 1.4 }, { 3.65, 2.2, 1.5 }, { 2.9, 2.45, 1.65 }, { 2.15, 2.72, 1.8 }, { 1.45, 2.95, 1.95 } }
	for i, row in ipairs(rows) do
		local y, w, d = row[1], row[2], row[3]
		local col = (i % 2 == 0) and COL.Shroud or COL.Shroud:Lerp(COL.ShroudDark, .35)
		if y > 2.9 and y < 4.6 then
			-- the chest: the shroud splits round the open ribcage (two side panels and a back panel)
			r:Part("Body", V(.62, .78, d), at(-w / 2 + .31, y, 0), col, MAT.Fabric, { Name = "Shroud" })
			r:Part("Body", V(.62, .78, d), at(w / 2 - .31, y, 0), col, MAT.Fabric, { Name = "Shroud" })
			r:Part("Body", V(w - 1.24, .78, .5), at(0, y, d / 2 - .25), col, MAT.Fabric, { Name = "Shroud" })
		else
			r:Part("Body", V(w, .8, d), at(0, y, 0) * ANG(0, (i % 3 - 1) * .05, 0), col, MAT.Fabric, { Name = "Shroud" })
		end
	end
	-- the chest cavity (dark) behind the heart
	r:Part("Body", V(1.0, 1.55, .3), at(0, HY, -.18), COL.Ink, MAT.SmoothPlastic, { Name = "ChestHollow" })
	-- shoulder drape, a rope belt, the shroud's long folds
	r:Part("Body", V(2.9, .34, 1.5), at(0, 5.38, 0), COL.ShroudHi, MAT.Fabric, { Name = "Shoulders" })
	for _, sx in ipairs({ -1, 1 }) do
		r:Part("Body", V(.6, .66, 1.45), at(sx * 1.35, 5.16, 0) * ANG(0, 0, sx * -.35), COL.ShroudHi, MAT.Fabric, { Name = "ShoulderPad" })
		r:Part("Body", V(.14, 2.0, .08), at(sx * .55, 1.95, -.95) * ANG(-.08, 0, sx * .05), COL.ShroudDark, MAT.Fabric, { Name = "Fold" })
		r:Part("Body", V(.12, 1.6, .08), at(sx * 1.1, 2.05, -.86) * ANG(-.08, 0, sx * .12), COL.ShroudDark, MAT.Fabric, { Name = "Fold" })
		r:Part("Body", V(.18, .9, .18), at(sx * .3, 2.35, -.88) * ANG(0, 0, sx * .15), COL.BoneDark, MAT.Fabric, { Name = "BeltTassel" })
	end
	r:Part("Body", V(2.35, .22, 1.62), at(0, 2.9, -.02), COL.BoneDark, MAT.Fabric, { Name = "RopeBelt" })
	-- tattered hem: hanging wedges round the bottom
	local tatters = lite and 7 or 12
	for k = 0, tatters - 1 do
		local a = k / tatters * PI * 2 + .2
		local rx, rz = 1.45, 1.0
		local len = .55 + ((k * 37) % 5) * .14
		local px, pz = math.sin(a) * rx, -math.cos(a) * rz
		r:Part("Body", V(.08, len, .5), at(px, 1.05 - len / 2, pz) * ANG(0, -a + PI / 2, PI) * ANG((k % 2) * .12, 0, 0),
			k % 2 == 0 and COL.ShroudDark or COL.Shroud, MAT.Fabric, { Class = "WedgePart", Name = "Tatter" })
	end
	-- a bone ruff round the neck
	local ruff = lite and 8 or 12
	for k = 0, ruff - 1 do
		local a = k / ruff * PI * 2
		r:Part("Body", V(.36, .36, .36), at(math.sin(a) * .62, 5.58, -math.cos(a) * .46), k % 2 == 0 and COL.Bone or COL.BoneDark, MAT.SmoothPlastic,
			{ Shape = "Ball", Name = "Ruff" })
	end

	-- the ribcage (two halves that swing open on vertical hinges at their outer ends)
	for i = 0, 3 do
		local y = HY - .6 + i * .4
		local w = .95 - math.abs(i - 1.5) * .12
		r:Part("RibL", V(w, .17, .2), at(-.92 + w / 2, y, -.78) * ANG(0, .12, 0), COL.Bone, MAT.SmoothPlastic, { Name = "Rib" })
		r:Part("RibR", V(w, .17, .2), at(.92 - w / 2, y, -.78) * ANG(0, -.12, 0), COL.Bone, MAT.SmoothPlastic, { Name = "Rib" })
	end
	r:Part("RibL", V(.2, 1.5, .24), at(-.92, HY, -.76), COL.BoneDark, MAT.SmoothPlastic, { Name = "RibSpine" })
	r:Part("RibR", V(.2, 1.5, .24), at(.92, HY, -.76), COL.BoneDark, MAT.SmoothPlastic, { Name = "RibSpine" })

	-- the heart: the weak spot
	local heart = r:Part("Heart", V(.82, .82, .82), at(0, HY, -.5), COL.Heart, MAT.Neon, { Shape = "Ball", Name = "MournerHeart", Glow = true })
	r:Part("Heart", V(.4, .4, .4), at(0, HY + .04, -.62), COL.HeartCore, MAT.Neon, { Shape = "Ball", Name = "MournerHeartCore", Glow = true })
	for _, sx in ipairs({ -1, 1 }) do
		r:Part("Heart", V(.42, .5, .42), at(sx * .2, HY + .28, -.5), COL.Heart, MAT.Neon, { Shape = "Ball", Name = "MournerHeartLobe", Glow = true })
	end
	r.Heart = heart
	if o.Light ~= false then
		local ok, pl = pcall(function()
			local l = Instance.new("PointLight")
			l.Color = COL.Heart
			l.Range = 9
			l.Brightness = 1.2
			l.Shadows = false
			l.Parent = heart
			return l
		end)
		if ok then
			r.Light = pl
		end
	end

	-- the head: a hood, a dog-skull mask with violet eyes, floppy cloth ears, a lace veil
	r:Part("Head", V(1.75, 1.95, 1.8), at(0, 6.18, .1), COL.ShroudDark, MAT.Fabric, { Shape = "Ball", Name = "Hood" })
	-- the hood's crooked tip droops backwards
	r:Part("Head", V(1.0, 1.0, 1.0), at(0, 6.95, .55), COL.ShroudDark, MAT.Fabric, { Shape = "Ball", Name = "HoodTip" })
	r:Part("Head", V(.62, .62, .62), at(.1, 7.0, 1.12), COL.ShroudDark:Lerp(COL.Shroud, .3), MAT.Fabric, { Shape = "Ball", Name = "HoodTip" })
	r:Part("Head", V(.36, .36, .36), at(.22, 6.8, 1.5), COL.ShroudDark, MAT.Fabric, { Shape = "Ball", Name = "HoodTip" })
	r:Part("Head", V(1.4, .16, .3), at(0, 6.62, -.95) * ANG(.15, 0, 0), COL.ShroudHi, MAT.Fabric, { Name = "HoodRim" })
	r:Part("Head", V(1.18, 1.12, 1.0), at(0, 6.08, -.62), COL.Bone, MAT.SmoothPlastic, { Shape = "Ball", Name = "SkullMask" })
	r:Part("Head", V(.62, .5, .78), at(0, 5.86, -1.22), COL.Bone, MAT.SmoothPlastic, { Name = "SkullSnout" })
	r:Part("Head", V(.3, .2, .16), at(0, 6.0, -1.62), COL.Ink, MAT.SmoothPlastic, { Name = "SkullNose" })
	r:Part("Head", V(.56, .16, .62), at(0, 5.6, -1.12), COL.BoneDark, MAT.SmoothPlastic, { Name = "SkullJaw" })
	for _, sx in ipairs({ -1, 1 }) do
		r:Part("Head", V(.42, .4, .2), at(sx * .27, 6.22, -1.08), COL.Ink, MAT.SmoothPlastic, { Shape = "Ball", Name = "EyeSocket" })
		r:Part("Head", V(.2, .2, .1), at(sx * .27, 6.2, -1.18), COL.Eye, MAT.Neon, { Shape = "Ball", Name = "MournerEye", Glow = true })
		r:Part("Head", V(.5, .14, .22), at(sx * .27, 6.47, -1.08) * ANG(0, 0, sx * -.25), COL.BoneDark, MAT.SmoothPlastic, { Name = "Brow" })
		-- floppy ears hanging out of the hood
		r:Part("Head", V(.2, 1.05, .55), at(sx * .9, 5.85, -.25) * ANG(0, 0, sx * .38), COL.ShroudHi, MAT.Fabric, { Name = "Ear" })
		for t = 0, 1 do
			r:Part("Head", V(.12, .1, .3), at(sx * .14 + sx * t * .16, 5.62, -1.5), COL.Bone, MAT.SmoothPlastic, { Name = "Tooth" })
		end
	end
	if not lite then
		r:Part("Head", V(1.7, 1.6, .06), at(0, 5.75, .9) * ANG(.25, 0, 0), COL.Lace, MAT.Fabric, { T = .35, Name = "Veil" })
		for _, sx in ipairs({ -1, 1 }) do
			r:Part("Head", V(.06, 1.5, .9), at(sx * .82, 5.5, .45) * ANG(0, 0, sx * .12), COL.Lace, MAT.Fabric, { T = .35, Name = "Veil" })
		end
	end

	-- the arms: long drooping sleeves, bony paws
	for _, sx in ipairs({ -1, 1 }) do
		local bone = sx < 0 and "ArmL" or "ArmR"
		local x = sx * 1.5
		r:Part(bone, V(.62, 1.2, .62), at(x, 4.45, 0), COL.ShroudHi, MAT.Fabric, { Name = "Sleeve" })
		r:Part(bone, V(.7, 1.1, .7), at(x + sx * .05, 3.4, -.05) * ANG(.08, 0, sx * .05), COL.Shroud, MAT.Fabric, { Name = "Sleeve" })
		r:Part(bone, V(.95, .6, .9), at(x + sx * .1, 2.75, -.1), COL.ShroudDark, MAT.Fabric, { Class = "WedgePart", Name = "Cuff" })
		r:Part(bone, V(.34, .4, .34), at(x + sx * .12, 2.45, -.2), COL.Bone, MAT.SmoothPlastic, { Shape = "Ball", Name = "Paw" })
		for f = -1, 1 do
			r:Part(bone, V(.1, .32, .1), at(x + sx * .12 + f * .1, 2.22, -.32), COL.BoneDark, MAT.SmoothPlastic, { Name = "Claw" })
		end
	end
	-- the funeral lantern (left hand): chain, cage, candle
	local L0 = V(-1.62, 2.5, -.3)
	r:Part("Lantern", V(.08, .5, .08), CF(L0 + V(0, -.25, 0)), COL.Iron, MAT.Metal, { Name = "LanternChain" })
	r:Part("Lantern", V(.6, .1, .6), CF(L0 + V(0, -.55, 0)), COL.Iron, MAT.Metal, { Name = "LanternCap" })
	r:Part("Lantern", V(.62, .1, .62), CF(L0 + V(0, -1.35, 0)), COL.Iron, MAT.Metal, { Name = "LanternBase" })
	for k = 0, 3 do
		local a = k / 4 * PI * 2 + PI / 4
		r:Part("Lantern", V(.07, .8, .07), CF(L0 + V(math.cos(a) * .26, -.95, math.sin(a) * .26)), COL.Iron, MAT.Metal, { Name = "LanternBar" })
	end
	r:Part("Lantern", V(.26, .5, .26), CF(L0 + V(0, -1.05, 0)), COL.Candle, MAT.Neon, { Name = "LanternFlame", Glow = true, T = .1 })
	-- the bronze hand-bell (right hand)
	local B0 = V(1.62, 2.55, -.3)
	r:Part("Bell", V(.12, .3, .12), CF(B0 + V(0, -.15, 0)), COL.Wood, MAT.Wood, { Name = "BellHandle" })
	r:Part("Bell", V(.5, .32, .5), CF(B0 + V(0, -.45, 0)), COL.Bronze, MAT.Metal, { Name = "BellBody" })
	r:Part("Bell", V(.66, .3, .66), CF(B0 + V(0, -.72, 0)), COL.Bronze:Lerp(COL.Ink, .2), MAT.Metal, { Name = "BellBody" })
	r:Part("Bell", V(.8, .12, .8), CF(B0 + V(0, -.92, 0)), COL.Bronze:Lerp(COL.Ink, .35), MAT.Metal, { Name = "BellLip" })
	r:Part("Bell", V(.16, .16, .16), CF(B0 + V(0, -1.04, 0)), COL.Iron, MAT.Metal, { Shape = "Ball", Name = "BellClapper" })

	r.Model.Parent = parent
	r:Update(IDENT, Mourner.Pose("Idle", 0, 0))
	r:Glow(1)
	return r
end

---------------------------------------------------------------------------------------------------------------------
-- poses (bone-local rotations; positive X on an arm swings it forward, Z spreads it)
---------------------------------------------------------------------------------------------------------------------
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function arms(pose: { [string]: CFrame }, fwdL: number, fwdR: number, spreadL: number, spreadR: number)
	pose.ArmL = ANG(rad(fwdL), 0, rad(-spreadL))
	pose.ArmR = ANG(rad(fwdR), 0, rad(spreadR))
end

function Mourner.Pose(state: string, t: number, k: number?): { [string]: CFrame }
	local p = smooth(k or 0)
	local sway = math.sin(t * .8)
	local pose: { [string]: CFrame } = {
		Body = ANG(rad(math.sin(t * .6) * 1.8), rad(math.sin(t * .35) * 4), rad(sway * 2.6)),
		Head = ANG(rad(math.sin(t * .7 + 1) * 4 - 6), rad(math.sin(t * .45) * 8), rad(-sway * 5)),
		Lantern = ANG(rad(math.sin(t * 1.3) * 9), 0, rad(math.sin(t * 1.1 + .6) * 7)),
		Bell = ANG(rad(math.sin(t * 1.2 + 2) * 6), 0, rad(math.sin(t * .9) * 5)),
		RibL = IDENT, RibR = IDENT, Heart = IDENT,
	}
	arms(pose, 6 + sway * 3, 6 - sway * 3, 6, 6)
	if state == "WindCircle" then
		-- both arms rise overhead, the body leans back
		arms(pose, 6 + 150 * p, 6 + 150 * p, 6 + 10 * p, 6 + 10 * p)
		pose.Body = pose.Body * ANG(rad(-10 * p), 0, 0)
		pose.Head = pose.Head * ANG(rad(-18 * p), 0, 0)
	elseif state == "StrikeCircle" then
		-- the slam: arms crash down in front
		arms(pose, 156 - 136 * p, 156 - 136 * p, 16 - 6 * p, 16 - 6 * p)
		pose.Body = pose.Body * ANG(rad(-10 + 30 * p), 0, 0)
		pose.Head = pose.Head * ANG(rad(-18 + 30 * p), 0, 0)
	elseif state == "WindLine" then
		-- the right arm draws back, the left points at the target
		arms(pose, 6 + 84 * p, 6 - 40 * p, 6, 6 + 30 * p)
		pose.Body = pose.Body * ANG(0, rad(28 * p), 0)
	elseif state == "StrikeLine" then
		arms(pose, 90 - 60 * p, -34 + 124 * p, 6, 36 - 30 * p)
		pose.Body = pose.Body * ANG(rad(10 * p), rad(28 - 46 * p), 0)
	elseif state == "WindRing" then
		-- arms spread wide, head thrown back: the wail builds
		arms(pose, 10, 10, 6 + 80 * p, 6 + 80 * p)
		pose.Head = pose.Head * ANG(rad(-26 * p), 0, 0)
		pose.Body = pose.Body * ANG(rad(-6 * p), 0, 0)
	elseif state == "StrikeRing" then
		-- the wail: a full turn with the arms out
		arms(pose, 10, 10, 86 + 14 * math.sin(p * PI), 86 + 14 * math.sin(p * PI))
		pose.Body = pose.Body * ANG(0, p * PI * 2, 0)
		pose.Head = pose.Head * ANG(rad(-26 + 20 * p), 0, 0)
	elseif state == "Hurt" then
		local h = math.sin(p * PI)
		arms(pose, 6 - 20 * h, 6 - 20 * h, 6 + 30 * h, 6 + 30 * h)
		pose.Body = pose.Body * ANG(rad(-16 * h), 0, rad(6 * h))
		pose.Head = pose.Head * ANG(rad(-24 * h), 0, 0)
	elseif state == "Open" then
		-- the ribcage swings open, the heart bared
		arms(pose, 12, 12, 6 + 34 * p, 6 + 34 * p)
		pose.RibL = ANG(0, rad(110 * p), 0)
		pose.RibR = ANG(0, rad(-110 * p), 0)
		pose.Head = pose.Head * ANG(rad(-20 * p), 0, 0)
		pose.Body = pose.Body * ANG(rad(-5 * p), 0, 0)
	elseif state == "Defeat" then
		-- slumps over its post, arms dangling, the chest open
		arms(pose, -4 + 10 * p, -4 + 10 * p, 4, 4)
		pose.Body = ANG(rad(30 * p), 0, rad(6 * p))
		pose.Head = ANG(rad(38 * p), 0, rad(-10 * p))
		pose.RibL = ANG(0, rad(110), 0)
		pose.RibR = ANG(0, rad(-110), 0)
	end
	return pose
end

-- bone-wise blend (w = 0 -> a, 1 -> b)
function Mourner.Blend(a: { [string]: CFrame }, b: { [string]: CFrame }, w: number): { [string]: CFrame }
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local out = {}
	for name, cf in pairs(a) do
		out[name] = cf:Lerp(b[name] or IDENT, w)
	end
	for name, cf in pairs(b) do
		if out[name] == nil then
			out[name] = IDENT:Lerp(cf, w)
		end
	end
	return out
end

return Mourner
