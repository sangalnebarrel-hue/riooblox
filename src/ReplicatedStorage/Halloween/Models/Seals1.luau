-- BELL SEALS I-IV · client-built visuals (ReplicatedStorage.Halloween.Models.Seals1, WP-I; docs/halloween2/DESIGN.md
-- §8.4.1-4, §24.2 "activity-state visuals belong to the presenters"). Pure builders: Instance.new + datatypes only (no
-- services, no assets), so the presenters (HalloweenClient.Trials.Echo / Run / Mirror / Mine), the seal-clear
-- cinematic (HalloweenClient.Trials) and the offline render QA build exactly the same parts. Every builder returns a
-- Model (anchored, non-colliding, non-queryable, shadowless parts; emitters and lights inside) plus a table of the
-- pieces the presenter animates. Colours follow the Underyard palette (DESIGN §7.1).
--   EchoMound(groundCF, opts?)        a spectral grave mound with a bell rune ring (life segments) and a floating bell
--   JumpTrail(from, to, opts?)        the telegraphed arc of wisp orbs an echo jumps along + the landing rune
--   NextMark(pos)                     H09 Bell Pup: the faint pulsing ring where the echo will land next
--   HollowOre(groundCF, seed)         a hollow ore node: crooked rock foot, violet crystal spires (break stages), the
--                                     hollow core with its glowing shell
--   FallingRock(seed) · GasVent(cf) · CollapseDebris(from, to, seed)   Hollow Mine hazard dressing
--   RunArrow(scale?)                  the floating guide arrow of the Funeral Run (points along its -Z)
--   SwingArc(hinge, arm, amp, groundY)  the dashed ground arc under a coffin pendulum (the coffin's sweep)
--   GhostStone(cf, color)             a small spectral headstone with a facing arrow (pond reflection fallback)
--   AltarFlare(cf, color)             the seal-clear ignition dressing on an altar socket (flames, shard, column)
local M = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local C3 = Color3.fromRGB
local PI = math.pi

M.Colors = {
	Sickly = C3(120, 255, 140),
	Violet = C3(150, 80, 230),
	VioletHi = C3(196, 150, 255),
	Candle = C3(255, 170, 80),
	Moon = C3(150, 200, 255),
	Bone = C3(230, 222, 200),
	Ink = C3(16, 12, 26),
	Spirit = C3(150, 255, 210),
	Ore = C3(176, 110, 255),
	OreDeep = C3(92, 40, 160),
	Rock = C3(66, 60, 72),
	RockDark = C3(48, 44, 56),
	Soil = C3(58, 48, 64),
	Gas = C3(140, 255, 120),
	Gold = C3(255, 210, 110),
	Blood = C3(220, 40, 60),
}
local COL = M.Colors

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- deterministic generator (Park-Miller): the same seed builds the same node on every client
local function rng(seed: number): (number?, number?) -> number
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function(a: number?, b: number?): number
		s = (s * 48271) % 2147483647
		local r = s / 2147483647
		if a and b then
			return a + (b - a) * r
		end
		return r
	end
end
M.Rng = rng

-- a frame at `at` whose -Z looks at `target` (CFrame.lookAt without its offline quirks)
local function look(at: Vector3, target: Vector3): CFrame
	local d = target - at
	if d.Magnitude < 1e-6 then
		return CF(at)
	end
	local f = d.Unit
	local up = math.abs(f.Y) > .99 and V3(0, 0, 1) or V3(0, 1, 0)
	local r = f:Cross(up).Unit
	local u = r:Cross(f).Unit
	return CFrame.fromMatrix(at, r, u, -f)
end
M.Look = look

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: any?): BasePart
	local p: BasePart = Instance.new((props and props.Class) or "Part") :: any
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		if props.Transparency then
			p.Transparency = props.Transparency
		end
		if props.Shape then
			(p :: any).Shape = props.Shape
		end
	end
	p.Parent = parent
	return p
end
M.Part = part

local function ellipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: any?): BasePart
	local p = part(parent, name, size, cf, color, material, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end
M.Ellipsoid = ellipsoid

local function cylY(parent: Instance, name: string, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, props: any?): BasePart
	local o = props and table.clone(props) or {}
	o.Shape = Enum.PartType.Cylinder
	return part(parent, name, V3(height, diameter, diameter), cf * ANG(0, 0, PI / 2), color, material, o)
end

local function ball(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, material: Enum.Material?, props: any?): BasePart
	local o = props and table.clone(props) or {}
	o.Shape = Enum.PartType.Ball
	return part(parent, name, V3(d, d, d), cf, color, material, o)
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: any?): BasePart
	local o = props and table.clone(props) or {}
	o.Class = "WedgePart"
	return part(parent, name, size, cf, color, material, o)
end

-- a bar from a to b (thickness w x h)
local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, props: any?): BasePart
	local len = (b - a).Magnitude
	return part(parent, name, V3(w, h, math.max(.05, len)), look((a + b) / 2, b), color, material, props)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l:SetAttribute("UyBase", brightness)
	l.Parent = parent
	return l
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = props.Texture or SPARK
	e.Color = ColorSequence.new(props.Color or COL.Spirit, props.Color2 or props.Color or COL.Spirit)
	e.LightEmission = props.Light or 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, props.Size and props.Size[1] or .3),
		NumberSequenceKeypoint.new(.5, props.Size and props.Size[2] or .5), NumberSequenceKeypoint.new(1, props.Size and props.Size[3] or 0) })
	e.Transparency = NumberSequence.new(props.Trans and props.Trans[1] or .2, props.Trans and props.Trans[2] or 1)
	e.Lifetime = NumberRange.new(props.Life and props.Life[1] or 1, props.Life and props.Life[2] or 2)
	e.Speed = NumberRange.new(props.Speed and props.Speed[1] or .5, props.Speed and props.Speed[2] or 1.5)
	e.SpreadAngle = Vector2.new(props.Spread or 30, props.Spread or 30)
	e.Acceleration = props.Accel or V3(0, 1, 0)
	e.Rate = props.Rate or 5
	e.LockedToPart = false
	e:SetAttribute("UyBaseRate", props.Rate or 5)
	e:SetAttribute("HwParticlePriority", true)
	e.Parent = parent
	return e
end
M.Emitter = emitter

local function model(name: string, pivot: CFrame): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("SelfManagedFX", true)
	local root = part(m, "Root", V3(.2, .2, .2), pivot, COL.Ink, Enum.Material.SmoothPlastic, { Transparency = 1 })
	m.PrimaryPart = root
	return m, root
end

-- a flat bell glyph lying on the ground at cf (its crown towards cf's -Z), s = size: a stepped bell silhouette
local function bellGlyph(parent: Instance, cf: CFrame, s: number, color: Color3, transparency: number?): { BasePart }
	local out = {}
	local t = { Transparency = transparency or .05 }
	local rows = { { .2, .18, -.64 }, { .5, .2, -.47 }, { .66, .28, -.23 }, { .8, .28, .04 }, { 1.06, .14, .26 }, { .22, .2, .43 } }
	for _, r in ipairs(rows) do
		table.insert(out, part(parent, "BellGlyph", V3(r[1] * s, .05, r[2] * s), cf * CF(0, 0, r[3] * s), color, Enum.Material.Neon, t))
	end
	return out
end

-- a small 3D bell (crown up) at cf, height ~2.2 * s
local function bell3D(parent: Instance, cf: CFrame, s: number, color: Color3, material: Enum.Material, transparency: number): { BasePart }
	local out = {}
	local t = { Transparency = transparency }
	local rows = { { .8, .7 }, { .42, 1.0 }, { .02, 1.14 }, { -.38, 1.28 } }
	for _, r in ipairs(rows) do
		table.insert(out, cylY(parent, "SpiritBell", .45 * s, r[2] * s, cf * CF(0, r[1] * s, 0), color, material, t))
	end
	table.insert(out, cylY(parent, "SpiritBell", .14 * s, 1.6 * s, cf * CF(0, -.78 * s, 0), color, material, t))
	table.insert(out, ball(parent, "SpiritBellClapper", .38 * s, cf * CF(0, -.95 * s, 0), COL.Bone, Enum.Material.Neon, { Transparency = transparency * .6 }))
	table.insert(out, part(parent, "SpiritBellCrown", V3(.18 * s, .35 * s, .5 * s), cf * CF(0, 1.1 * s, 0), color, material, t))
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- I · ECHO DIG
---------------------------------------------------------------------------------------------------------------------
M.EchoSegments = 18
M.EchoRingRadius = 3.4

-- groundCF: the echo point on the ground (its Y = the floor), facing = the target's yaw
function M.EchoMound(groundCF: CFrame, opts: { [string]: any }?): (Model, { [string]: any })
	local o = opts or {}
	local color = o.Color or COL.Spirit
	local m, root = model("EchoMound", groundCF)
	local P: { [string]: any } = { Root = root, Ring = {}, Glyphs = {}, Bell = {}, Body = {} }
	local g = groundCF
	-- the grave: a soft mound of grave soil, a ghostly shell over it, a crooked headstone at its head
	table.insert(P.Body, ellipsoid(m, "Mound", V3(4.6, 1.3, 3.6), g * CF(0, .3, .2), COL.Soil, Enum.Material.Ground))
	table.insert(P.Body, ellipsoid(m, "MoundTop", V3(3.2, .9, 2.4), g * CF(.2, .62, .35) * ANG(0, .3, 0), COL.Soil:Lerp(COL.Ink, .2), Enum.Material.Ground))
	P.Shell = ellipsoid(m, "MoundShell", V3(5.2, 1.9, 4.2), g * CF(0, .35, .2), color, Enum.Material.ForceField, { Transparency = .15 })
	local stoneCF = g * CF(0, 1.1, -1.75) * ANG(-.12, .1, .06)
	P.Stone = part(m, "Headstone", V3(1.7, 2.2, .45), stoneCF, C3(112, 106, 132), Enum.Material.Slate)
	table.insert(P.Body, P.Stone)
	-- a pointed top: two wedges whose tall (+Z) faces meet in the middle
	table.insert(P.Body, wedge(m, "HeadstoneTop", V3(.45, .5, .85), stoneCF * CF(-.425, 1.35, 0) * ANG(0, PI / 2, 0), C3(112, 106, 132), Enum.Material.Slate))
	table.insert(P.Body, wedge(m, "HeadstoneTop", V3(.45, .5, .85), stoneCF * CF(.425, 1.35, 0) * ANG(0, -PI / 2, 0), C3(112, 106, 132), Enum.Material.Slate))
	-- the bell rune on the headstone (facing the mound)
	for _, p in ipairs(bellGlyph(m, stoneCF * CF(0, .1, .24) * ANG(-PI / 2, 0, 0), 1.1, color, .02)) do
		table.insert(P.Glyphs, p)
	end
	-- the rune ring: its segments are the echo's life (they go dark one by one)
	local n = M.EchoSegments
	local r = M.EchoRingRadius
	for i = 1, n do
		local a = (i - .5) / n * PI * 2
		local arc = 2 * PI * r / n
		local seg = part(m, "LifeSegment", V3(arc * .7, .06, .24), g * ANG(0, -a, 0) * CF(0, .05, -r), COL.Moon, Enum.Material.Neon, { Transparency = .1 })
		seg:SetAttribute("Index", i)
		P.Ring[i] = seg
	end
	-- four bell glyphs on the ring (pointing out)
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		for _, p in ipairs(bellGlyph(m, g * ANG(0, -a, 0) * CF(0, .07, -(r + .9)), .9, COL.VioletHi, .1)) do
			table.insert(P.Glyphs, p)
		end
	end
	-- the spectral bell hovering over the grave (swings, rings when dug)
	P.BellPivot = g * CF(0, 4.3, .1)
	for _, p in ipairs(bell3D(m, P.BellPivot, .9, color, Enum.Material.Neon, .35)) do
		table.insert(P.Bell, p)
	end
	P.Light = light(root, color, 12, 1.4)
	local wisp = part(m, "WispSource", V3(3, .2, 2.6), g * CF(0, .6, .2), color, Enum.Material.SmoothPlastic, { Transparency = 1 })
	P.Emitters = {
		emitter(wisp, { Color = color, Color2 = COL.Moon, Rate = 6, Life = { 1.2, 2.2 }, Speed = { .6, 1.6 }, Size = { .25, .45, 0 },
			Accel = V3(0, 1.4, 0), Spread = 25 }),
		emitter(wisp, { Texture = SMOKE, Color = color:Lerp(COL.Ink, .3), Rate = 2, Life = { 1.8, 2.8 }, Speed = { .2, .6 }, Size = { 1, 2.2, 3 },
			Trans = { .72, 1 }, Light = .35, Accel = V3(0, .5, 0), Spread = 40 }),
	}
	P.Model = m
	return m, P
end

-- the arc an echo jumps along: orbs on a parabola from -> to (height grows with the distance) + the landing rune
function M.JumpTrail(from: Vector3, to: Vector3, opts: { [string]: any }?): (Model, { [string]: any })
	local o = opts or {}
	local color = o.Color or COL.Spirit
	local count = o.Count or 12
	local m, root = model("EchoJumpTrail", CF(to))
	local P: { [string]: any } = { Root = root, Orbs = {}, Land = {}, From = from, To = to }
	local d = (to - from) * V3(1, 0, 1)
	local height = 5 + d.Magnitude * .12
	P.Height = height
	for i = 1, count do
		local k = i / (count + 1)
		local pos = from:Lerp(to, k) + V3(0, 1.2 + math.sin(k * PI) * height, 0)
		local orb = ball(m, "TrailOrb", .55, CF(pos), color, Enum.Material.Neon, { Transparency = .25 })
		orb:SetAttribute("K", k)
		P.Orbs[i] = orb
	end
	-- landing rune: a dashed ring + a cross of bell glyph bars
	local n = 14
	for i = 1, n do
		local a = (i - .5) / n * PI * 2
		local seg = part(m, "LandingRune", V3(1.05, .06, .22), CF(to) * ANG(0, -a, 0) * CF(0, .08, -3), color, Enum.Material.Neon, { Transparency = .2 })
		table.insert(P.Land, seg)
	end
	for _, p in ipairs(bellGlyph(m, CF(to) * CF(0, .09, 0), 1.6, COL.VioletHi, .15)) do
		table.insert(P.Land, p)
	end
	P.Model = m
	return m, P
end

-- the echo's next landing point (H09 Bell Pup: ECHO EAR)
function M.NextMark(pos: Vector3): (Model, { [string]: any })
	local m, root = model("EchoNextMark", CF(pos))
	local P: { [string]: any } = { Root = root, Ring = {} }
	local n = 10
	for i = 1, n do
		local a = (i - .5) / n * PI * 2
		table.insert(P.Ring, part(m, "NextRing", V3(1.3, .05, .16), CF(pos) * ANG(0, -a, 0) * CF(0, .07, -2.2), COL.Gold, Enum.Material.Neon,
			{ Transparency = .45 }))
	end
	-- a little paw print in the middle (the Bell Pup's)
	table.insert(P.Ring, ellipsoid(m, "PawPad", V3(.9, .06, .75), CF(pos) * CF(0, .07, .25), COL.Gold, Enum.Material.Neon, { Transparency = .4 }))
	for k = -1, 1 do
		table.insert(P.Ring, ellipsoid(m, "PawToe", V3(.34, .06, .4), CF(pos) * CF(k * .42, .07, -.42 - (k == 0 and .12 or 0)), COL.Gold, Enum.Material.Neon,
			{ Transparency = .4 }))
	end
	P.Model = m
	return m, P
end

---------------------------------------------------------------------------------------------------------------------
-- IV · HOLLOW MINE
---------------------------------------------------------------------------------------------------------------------
-- a pointed crystal spire standing at base (up = its +Y), width w, height h
local function spire(parent: Instance, base: CFrame, w: number, h: number, color: Color3, stage: number): { BasePart }
	local out = {}
	local body = part(parent, "Crystal", V3(w, h * .72, w), base * CF(0, h * .36, 0) * ANG(0, PI / 4, 0), color, Enum.Material.Neon, { Transparency = .12 })
	table.insert(out, body)
	local top = base * CF(0, h * .72, 0) * ANG(0, PI / 4, 0)
	local capH = h * .28
	table.insert(out, wedge(parent, "CrystalTip", V3(w, capH, w / 2), top * CF(0, capH / 2, -w / 4), color:Lerp(Color3.new(1, 1, 1), .25),
		Enum.Material.Neon, { Transparency = .08 }))
	table.insert(out, wedge(parent, "CrystalTip", V3(w, capH, w / 2), top * CF(0, capH / 2, w / 4) * ANG(0, PI, 0), color:Lerp(Color3.new(1, 1, 1), .25),
		Enum.Material.Neon, { Transparency = .08 }))
	-- a darker glassy sheath on one side (depth)
	table.insert(out, part(parent, "CrystalSheath", V3(w * .55, h * .6, w * 1.08), base * CF(w * .3, h * .3, 0) * ANG(0, PI / 4, 0),
		COL.OreDeep, Enum.Material.Glass, { Transparency = .25 }))
	for _, p in ipairs(out) do
		p:SetAttribute("Stage", stage)
	end
	return out
end

function M.HollowOre(groundCF: CFrame, seed: number): (Model, { [string]: any })
	local r = rng(seed)
	local m, root = model("HollowOre", groundCF)
	local P: { [string]: any } = { Root = root, Rocks = {}, Crystals = { {}, {}, {} }, Cracks = {} }
	local g = groundCF
	-- the crooked rock foot
	for k = 1, 5 do
		local a = (k / 5) * PI * 2 + r(-.3, .3)
		local d = r(.9, 1.9)
		local s = V3(r(1.6, 2.6), r(1.0, 1.8), r(1.4, 2.4))
		local rock = part(m, "OreRock", s, g * CF(math.cos(a) * d, s.Y / 2 - .15, math.sin(a) * d) * ANG(r(-.25, .25), r(0, PI), r(-.25, .25)),
			(k % 2 == 0) and COL.Rock or COL.RockDark, Enum.Material.Slate)
		table.insert(P.Rocks, rock)
	end
	-- the hollow core: a black heart inside a glowing shell, raised on the rocks
	P.CoreCF = g * CF(0, 2.5, 0)
	P.Shell = ball(m, "CoreShell", 2.6, P.CoreCF, COL.Ore, Enum.Material.Neon, { Transparency = .55 })
	P.Core = ball(m, "Core", 1.5, P.CoreCF, COL.Ink, Enum.Material.SmoothPlastic)
	P.CoreEye = ball(m, "CoreEye", .55, P.CoreCF * CF(0, 0, -.62), COL.VioletHi, Enum.Material.Neon)
	-- crystal spires around the core: stage 1 breaks off first (outer, lower), stage 3 last (tall inner ones)
	local count = 8
	for k = 1, count do
		local a = (k / count) * PI * 2 + r(-.2, .2)
		local stage = k % 3 + 1
		local d = stage == 3 and r(.6, 1.0) or r(1.3, 2.1)
		local h = stage == 3 and r(4.4, 5.8) or (stage == 2 and r(3.2, 4.2) or r(2.2, 3.0))
		local w = stage == 3 and r(.9, 1.15) or r(.6, .85)
		local tilt = (stage == 3 and .18 or .42) + r(-.08, .08)
		local base = g * CF(math.cos(a) * d, .6, math.sin(a) * d) * ANG(0, -a, 0) * ANG(0, 0, -tilt)
		for _, p in ipairs(spire(m, base, w, h, k % 2 == 0 and COL.Ore or COL.Ore:Lerp(COL.Moon, .25), stage)) do
			table.insert(P.Crystals[stage], p)
		end
	end
	-- crack lines on the rocks (shown as the node takes damage)
	for k = 1, 6 do
		local a = r(0, PI * 2)
		local p0 = (g * CF(math.cos(a) * 1.2, r(.4, 1.4), math.sin(a) * 1.2)).Position
		local p1 = (g * CF(math.cos(a + r(-.6, .6)) * 2.2, r(.2, 1.8), math.sin(a + r(-.6, .6)) * 2.2)).Position
		local c = bar(m, "OreCrack", p0, p1, .12, .12, COL.VioletHi, Enum.Material.Neon, { Transparency = 1 })
		c:SetAttribute("At", k / 6)
		table.insert(P.Cracks, c)
	end
	P.Light = light(root, COL.Ore, 14, 1.6)
	local glow = part(m, "SparkSource", V3(2.6, 3, 2.6), g * CF(0, 2.6, 0), COL.Ore, Enum.Material.SmoothPlastic, { Transparency = 1 })
	P.Emitters = { emitter(glow, { Color = COL.VioletHi, Color2 = COL.Ore, Rate = 4, Life = { .8, 1.6 }, Speed = { .3, 1 }, Size = { .2, .35, 0 },
		Accel = V3(0, .8, 0), Spread = 180 }) }
	P.Model = m
	return m, P
end

-- a crooked lump of cavern rock (falls from the ceiling onto a telegraph)
function M.FallingRock(seed: number): (Model, { [string]: any })
	local r = rng(seed)
	local m, root = model("FallingRock", CF())
	local P: { [string]: any } = { Root = root, Parts = {} }
	-- a faceted lump: a core block, two wedge facets and a smaller knuckle, all turned differently
	local core = V3(r(2.2, 2.8), r(1.8, 2.3), r(2.0, 2.6))
	table.insert(P.Parts, part(m, "Rock", core, ANG(r(-.3, .3), r(0, PI), r(-.3, .3)), COL.Rock, Enum.Material.Slate))
	for k = 1, 2 do
		local s = V3(r(1.6, 2.4), r(1.0, 1.6), r(1.4, 2.0))
		table.insert(P.Parts, wedge(m, "RockFacet", s, CF(r(-.5, .5), (k == 1 and 1 or -1) * r(.7, 1.0), r(-.5, .5)) * ANG(k == 1 and 0 or PI, r(0, PI * 2), 0),
			k == 1 and COL.Rock:Lerp(COL.Bone, .08) or COL.RockDark, Enum.Material.Slate))
	end
	table.insert(P.Parts, part(m, "RockKnuckle", V3(r(1.1, 1.5), r(1.0, 1.4), r(1.1, 1.5)), CF(r(.8, 1.2), r(-.3, .3), r(-.6, .6)) * ANG(r(0, PI), r(0, PI), 0),
		COL.RockDark, Enum.Material.Slate))
	table.insert(P.Parts, bar(m, "RockVein", V3(-1, .4, -.6), V3(1.1, -.2, .7), .16, .16, COL.Ore, Enum.Material.Neon))
	P.Model = m
	return m, P
end

-- a gas vent cracking open in the mine floor (green fissures + a vent ring)
function M.GasVent(cf: CFrame, radius: number?): (Model, { [string]: any })
	local rr = radius or 5
	local m, root = model("GasVent", cf)
	local P: { [string]: any } = { Root = root, Cracks = {} }
	local r = rng(math.floor(cf.Position.X * 13 + cf.Position.Z * 7))
	P.Ring = cylY(m, "VentRing", .12, 2.4, cf * CF(0, .06, 0), COL.RockDark, Enum.Material.Slate)
	P.Mouth = cylY(m, "VentMouth", .14, 1.5, cf * CF(0, .08, 0), COL.Gas, Enum.Material.Neon, { Transparency = .2 })
	for k = 1, 7 do
		local a = k / 7 * PI * 2 + r(-.25, .25)
		local len = rr * r(.55, .95)
		local p0 = (cf * CF(math.cos(a) * 1, .07, math.sin(a) * 1)).Position
		local p1 = (cf * CF(math.cos(a + r(-.2, .2)) * len, .07, math.sin(a + r(-.2, .2)) * len)).Position
		table.insert(P.Cracks, bar(m, "VentCrack", p0, p1, .22, .05, COL.Gas, Enum.Material.Neon, { Transparency = .15 }))
	end
	local src = part(m, "GasSource", V3(2, .4, 2), cf * CF(0, .4, 0), COL.Gas, Enum.Material.SmoothPlastic, { Transparency = 1 })
	P.Emitters = {
		emitter(src, { Texture = SMOKE, Color = COL.Gas, Color2 = COL.Gas:Lerp(COL.Ink, .4), Rate = 14, Life = { 2, 3.2 }, Speed = { 1.5, 3 },
			Size = { 1.5, 3.6, 5 }, Trans = { .45, 1 }, Light = .4, Accel = V3(0, -.3, 0), Spread = 70 }),
	}
	P.Model = m
	return m, P
end

-- rubble spilling along a collapsing tunnel line
function M.CollapseDebris(from: Vector3, to: Vector3, seed: number): (Model, { [string]: any })
	local r = rng(seed)
	local m, root = model("CollapseDebris", CF((from + to) / 2))
	local P: { [string]: any } = { Root = root, Chunks = {} }
	local len = (to - from).Magnitude
	local n = math.clamp(math.floor(len / 3), 4, 16)
	for k = 1, n do
		local at = from:Lerp(to, (k - .5) / n) + V3(r(-1.5, 1.5), 0, r(-1.5, 1.5))
		local s = V3(r(1, 2.4), r(.8, 1.8), r(1, 2.2))
		local chunk
		if k % 2 == 0 then
			chunk = wedge(m, "Debris", s, CF(at + V3(0, s.Y / 2 - .3, 0)) * ANG(0, r(0, PI * 2), 0), k % 3 == 0 and COL.RockDark or COL.Rock, Enum.Material.Slate)
		else
			chunk = part(m, "Debris", s, CF(at + V3(0, s.Y / 2 - .4, 0)) * ANG(r(-.4, .4), r(0, PI), r(-.4, .4)), k % 3 == 0 and COL.RockDark or COL.Rock,
				Enum.Material.Slate)
		end
		chunk:SetAttribute("K", (k - .5) / n)
		table.insert(P.Chunks, chunk)
	end
	P.Model = m
	return m, P
end

---------------------------------------------------------------------------------------------------------------------
-- II · FUNERAL RUN
---------------------------------------------------------------------------------------------------------------------
-- the guide arrow (tip towards its -Z): a chevron head and a shaft, candle-gold Neon with a dark rim
function M.RunArrow(scale: number?): (Model, { [string]: any })
	local k = scale or 1.6
	local m, root = model("RunArrow", CF())
	local P: { [string]: any } = { Root = root, Parts = {} }
	local gold = COL.Gold
	local tip = V3(0, 0, -1.6) * k
	table.insert(P.Parts, bar(m, "ArrowShaft", V3(0, 0, 1.5) * k, V3(0, 0, -1.2) * k, .5 * k, .34 * k, gold, Enum.Material.Neon))
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(P.Parts, bar(m, "ArrowHead", tip + V3(sx * .08, 0, .06) * k, V3(sx * 1.05, 0, -.45) * k, .48 * k, .34 * k, gold, Enum.Material.Neon))
		table.insert(P.Parts, bar(m, "ArrowRim", tip + V3(sx * .08, -.14, .14) * k, V3(sx * 1.12, -.14, -.38) * k, .66 * k, .14 * k, COL.Ink,
			Enum.Material.SmoothPlastic, { Transparency = .15 }))
	end
	table.insert(P.Parts, bar(m, "ArrowRim", V3(0, -.14, 1.6) * k, V3(0, -.14, -1.1) * k, .66 * k, .14 * k, COL.Ink, Enum.Material.SmoothPlastic,
		{ Transparency = .15 }))
	P.Model = m
	return m, P
end

-- the dashed arc a coffin sweeps over the lane (hinge = the pendulum pivot; the swing is about the hinge's local Z)
function M.SwingArc(hinge: CFrame, arm: number, amp: number, groundY: number, dashes: number?): (Model, { [string]: any })
	local m, root = model("SwingArc", hinge)
	local P: { [string]: any } = { Root = root, Dashes = {} }
	local n = dashes or 13
	local ext = math.abs(amp)
	for k = 0, n - 1 do
		local a = -ext + (k + .5) / n * 2 * ext
		local p = (hinge * ANG(0, 0, a) * CF(0, -arm, 0)).Position
		local q = (hinge * ANG(0, 0, a + 2 * ext / n * .55) * CF(0, -arm, 0)).Position
		local pg, qg = V3(p.X, groundY + .09, p.Z), V3(q.X, groundY + .09, q.Z)
		local dash = bar(m, "SwingDash", pg, qg, .3, .05, COL.Candle, Enum.Material.Neon, { Transparency = .45 })
		dash:SetAttribute("A", a)
		table.insert(P.Dashes, dash)
	end
	P.Model = m
	return m, P
end

---------------------------------------------------------------------------------------------------------------------
-- III · MIRROR GRAVES
---------------------------------------------------------------------------------------------------------------------
-- a small spectral headstone whose rune face (and arrow) points along cf's +Z
function M.GhostStone(cf: CFrame, color: Color3?): (Model, { [string]: any })
	local c = color or COL.Moon
	local m, root = model("GhostStone", cf)
	local P: { [string]: any } = { Root = root, Parts = {} }
	table.insert(P.Parts, part(m, "GhostSlab", V3(1.4, 2.4, .5), cf * CF(0, 1.4, 0), c, Enum.Material.ForceField, { Transparency = .05 }))
	table.insert(P.Parts, wedge(m, "GhostGable", V3(.5, .7, .7), cf * CF(-.35, 2.95, 0) * ANG(0, PI / 2, 0), c, Enum.Material.ForceField))
	table.insert(P.Parts, wedge(m, "GhostGable", V3(.5, .7, .7), cf * CF(.35, 2.95, 0) * ANG(0, -PI / 2, 0), c, Enum.Material.ForceField))
	-- the rune on its face and a chevron on the ground in front: both show where it faces
	local face = cf * CF(0, 1.4, .28)
	table.insert(P.Parts, part(m, "GhostRune", V3(.18, 1.1, .05), face * CF(0, -.15, 0), COL.VioletHi, Enum.Material.Neon))
	table.insert(P.Parts, part(m, "GhostRune", V3(.7, .16, .05), face * CF(0, .3, 0), COL.VioletHi, Enum.Material.Neon))
	local tip = (cf * CF(0, .1, 2.0)).Position
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(P.Parts, bar(m, "GhostRuneOut", tip, (cf * CF(sx * .7, .1, 1.3)).Position, .2, .05, COL.VioletHi, Enum.Material.Neon, { Transparency = .15 }))
	end
	table.insert(P.Parts, bar(m, "GhostRuneOut", (cf * CF(0, .1, .6)).Position, tip, .2, .05, COL.VioletHi, Enum.Material.Neon, { Transparency = .15 }))
	P.Model = m
	return m, P
end

---------------------------------------------------------------------------------------------------------------------
-- SEAL CLEAR · altar ignition dressing (the cinematic's beat; the saved ignited altar fades in after it)
---------------------------------------------------------------------------------------------------------------------
-- cf: the altar socket (top of the pedestal)
function M.AltarFlare(cf: CFrame, color: Color3): (Model, { [string]: any })
	local m, root = model("AltarFlare", cf)
	local P: { [string]: any } = { Root = root, Flames = {}, Shard = {}, Ring = {} }
	for k = 0, 2 do
		local a = k / 3 * PI * 2
		table.insert(P.Flames, ellipsoid(m, "FlareFlame", V3(.7, 1.6, .7), cf * CF(math.cos(a) * .55, 1.0, math.sin(a) * .55), color, Enum.Material.Neon,
			{ Transparency = .1 }))
	end
	local shardCF = cf * CF(0, 2.9, 0)
	P.ShardCF = shardCF
	table.insert(P.Shard, wedge(m, "FlareShard", V3(.5, 1.4, .9), shardCF * CF(0, .7, -.45), color, Enum.Material.Neon))
	table.insert(P.Shard, wedge(m, "FlareShard", V3(.5, 1.4, .9), shardCF * CF(0, .7, .45) * ANG(0, PI, 0), color, Enum.Material.Neon))
	table.insert(P.Shard, wedge(m, "FlareShard", V3(.5, 1.0, .9), shardCF * CF(0, -.5, -.45) * ANG(PI, PI, 0), color, Enum.Material.Neon))
	table.insert(P.Shard, wedge(m, "FlareShard", V3(.5, 1.0, .9), shardCF * CF(0, -.5, .45) * ANG(PI, 0, 0), color, Enum.Material.Neon))
	P.Column = cylY(m, "FlareColumn", 30, 2.2, cf * CF(0, 15, 0), color, Enum.Material.Neon, { Transparency = .6 })
	local n = 16
	for i = 1, n do
		local a = (i - .5) / n * PI * 2
		table.insert(P.Ring, part(m, "FlareRune", V3(1.3, .06, .3), cf * CF(0, -2.2, 0) * ANG(0, -a, 0) * CF(0, 0, -2.6), color, Enum.Material.Neon,
			{ Transparency = .1 }))
	end
	P.Light = light(root, color, 22, 3)
	P.Model = m
	return m, P
end

return M
