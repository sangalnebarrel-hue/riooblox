-- THE LAST BELL finale models (ReplicatedStorage.Halloween.Models.Finale). Pure builders for the Gravekeeper difficulty V
-- finale (docs/halloween2/DESIGN.md §11, §23.2): the client (HalloweenClient.FinaleFX) builds every piece at runtime, the
-- offline previews build them in Lune. Every model is built at the origin facing -Z and returned ANCHORED. Rigged models
-- use the Gravekeeper's rig builder (Models.Boss.NewRig: one invisible `Bone` part per bone, Motor6D `Joint`, visual parts
-- welded to their bone); the client calls Boss.Rig(model) and drives Motor6D.Transform, previews call Boss.Pose.
-- API
--   Finale.Bell(opts?)        -> Model "BlackBell" (~26 tall, black iron, violet runes, cracked rim). PrimaryPart "Root" =
--       the hang point Finale.BellHang above the bell centre; bones "Bell" (swings about the hang point) and "Clapper".
--       Named parts: "Rune" (rune band, flares on tolls), "Crack" (glowing rim crack), "RimGlow", "SoulGlow" (spirit inside,
--       hidden), sub-models "PatternSlot_<i>" (i = 1..6, attr Slot; parts "Glyph" / "SlotRim": the choir pattern),
--       attachments "ChainEye_<N|E|S|W>" (where the cursed chains hook in), "Mouth" (under the lip), "Core", part
--       "BellLight" (PointLight, Brightness 0 until FinaleFX lights it).
--   Finale.Chain(count, opts?) -> Model "CursedChain", handle {Links = {{Parts, Local, Glow}}, Count, LinkLength}: links
--       built at the origin; Finale.LayChain(handle, path, grow?) lays them along a polyline (BulkMoveTo lists).
--   Finale.ChainAnchor(height) -> Model "ChainAnchor" (stone post + iron ring; attachment "Ring"; PrimaryPart on the ground)
--   Finale.Candle(index, opts?) -> Model "CursedCandle_<i>" (~10 tall wax tower on an iron tripod; sub-models "Flame"
--       (lit) and "Smoke" (snuffed), part "FlameLight" (PointLight), "Glyph" parts = the candle's sign (the same six signs
--       as the bell's pattern slots); attachment "FlameTip"). Finale.SetCandleLit(model, lit) shows one or the other.
--   Finale.GhostDog(seed?, opts?) -> rigged Model "GhostDog" (~4.6 tall translucent spectral hound with bone accents; bones Body,
--       Head, Jaw, LegFR, LegFL, LegHR, LegHL, Tail; attachment "Mouth"). Finale.GhostPose(mode, t, k) -> transforms.
--   Finale.Hound(opts?) -> rigged Model "TheLastBark" (THE LAST BARK: a sitting colossal hound ~52 tall, near-black hide,
--       white-violet bones, burning eyes, violet mane; its haunches fade into smoke). Bones Pelvis, Chest, Neck, Head, Jaw,
--       EarL/R, ArmL/R, ForeL/R, PawL/R, ThighL/R, ShinL/R, Tail1..3. Attachments "JawSocket" (the jaw weak point),
--       "Mouth", "EyeL", "EyeR", "Core". Parts "EyeCore" / "EyeFlame" / "MouthGlow" / "JawCore" (hidden until Bark) /
--       "Mane". Finale.HoundPose(name, t, k, beat) -> transforms for Loom | Rise | Bark | Circles | Lines | Waves |
--       SafeDance | Howl | Shatter.
--   Finale.Spirit()          -> rigged Model "GravekeeperSpirit" (the boss's soul torn out of the corpse; bones Body, Head,
--       Jaw, ArmL, ArmR, Tail). Finale.SpiritPose(t, k) -> transforms.
--   Finale.WeakMound(seed?)  -> Model "BuriedWeak" (a buried weak point: dirt mound torn open on a gold soul heart;
--       parts "WeakCore" / "WeakGlow" / "WeakRim"; attachment "Top")
--   Finale.BlackMoon(radius) -> Model "BlackMoon" (a black disc facing -Z with a violet corona, flare spikes, hidden
--       crack network "MoonCrack" (attr Stage 1..3) and shards "MoonShard"; PrimaryPart "Root" at the centre)
--   Finale.ReplayStage()     -> Model "FinaleMemory" (the journal replay's stage: a dark pit set inside a black box)
--   Finale.Glyph(builder, bone, frame, size, index, color, group?) the six candle signs (1 moon, 2 paw, 3 bone, 4 eye,
--       5 bell, 6 star) drawn as neon strokes on a surface frame (LookVector into the surface)
--   Finale.Defaults(Layout, cfg) -> {BellCF, Chains = {N,E,S,W}, Candles = {Vector3 x6}, HoundCF, MoonDir, JawPos}
--       the server-independent placement used for late joiners and the journal replay (the server's payloads win)
--   Finale.Keys = {"N","E","S","W"} ; Finale.BellHang ; Finale.Colors ; Finale.Count(model) -> parts
local Finale = {}

local Boss = require((script.Parent :: Instance):WaitForChild("Boss"))

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local PI = math.pi
local SMOOTH = Enum.SurfaceType.Smooth
local look = Boss.Look
local newRng = Boss.Rng

local COL = {
	Iron = RGB(30, 27, 40), IronDark = RGB(17, 15, 24), IronEdge = RGB(66, 60, 84), IronRust = RGB(76, 50, 70),
	IronBand = RGB(44, 40, 58),
	Rune = RGB(150, 80, 230), RuneHot = RGB(226, 190, 255), RuneDeep = RGB(78, 34, 150), RuneDim = RGB(46, 24, 84),
	Bone = RGB(230, 222, 200), BoneLight = RGB(244, 238, 222), BoneDark = RGB(170, 158, 134),
	BoneViolet = RGB(226, 216, 248), BoneVioletShade = RGB(170, 154, 214),
	Wax = RGB(234, 226, 206), WaxShade = RGB(198, 186, 162), WaxDrip = RGB(246, 240, 226), Wick = RGB(24, 20, 22),
	Flame = RGB(255, 170, 80), FlameHot = RGB(255, 238, 196), FlameDeep = RGB(255, 108, 40), Smoke = RGB(120, 116, 132),
	Ghost = RGB(168, 214, 255), GhostDeep = RGB(92, 132, 232), GhostEye = RGB(206, 255, 236), GhostMist = RGB(124, 150, 210),
	Hide = RGB(15, 11, 24), HideEdge = RGB(36, 26, 56), HideSmoke = RGB(40, 24, 66), Throat = RGB(196, 120, 255),
	EyeCore = RGB(255, 252, 255), EyeFire = RGB(196, 124, 255), Claw = RGB(222, 210, 236),
	Spirit = RGB(120, 255, 110), SpiritHot = RGB(206, 255, 196), SpiritDeep = RGB(36, 190, 90), SpiritEdge = RGB(176, 92, 240),
	Weak = RGB(255, 128, 24), WeakGold = RGB(255, 200, 70), WeakHot = RGB(255, 236, 150), WeakRim = RGB(255, 246, 222),
	Dirt = RGB(58, 44, 38), DirtDark = RGB(38, 30, 28),
	Stone = RGB(70, 68, 84), StoneDark = RGB(44, 42, 56), StoneLight = RGB(104, 100, 118),
	Moon = RGB(9, 7, 15), Corona = RGB(186, 140, 255), CoronaHot = RGB(244, 232, 255), Dawn = RGB(150, 200, 255),
	Void = RGB(6, 5, 10),
}
Finale.Colors = COL
Finale.Keys = { "N", "E", "S", "W" }
-- the hang point (top of the crown) relative to the bell centre: FinaleFX hangs the bell so that its centre sits on the
-- server's BellCF
Finale.BellHang = V3(0, 15.6, 0)
Finale.BellLip = -13 -- bottom of the bell relative to its centre

---------------------------------------------------------------------------------------------------------------------
-- small helpers (anchored, non-interactive parts)
---------------------------------------------------------------------------------------------------------------------
local function part(parent: Instance, name: string, class: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?,
	o: { [string]: any }?): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	if o and o.Shape then
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
	p.CastShadow = o and o.Shadow == true or false
	if o and o.T then
		p.Transparency = o.T
	end
	if o and o.Refl then
		p.Reflectance = o.Refl
	end
	if o and o.Mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- a box between two points (w across, h along `up`)
local function barCF(a: Vector3, b: Vector3, up: Vector3?): (CFrame, number)
	local len = math.max(.05, (b - a).Magnitude)
	return look((a + b) / 2, b, up), len
end

local function groundRoot(m: Model, at: Vector3?): BasePart
	local r = Instance.new("Part")
	r.Name = "Root"
	r.Size = V3(.4, .4, .4)
	r.CFrame = CF(at or V3(0, 0, 0))
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

function Finale.Count(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- outward unit vector at bell angle `a` (0 = -Z / north, +90 deg = +X / east)
local function outward(a: number): Vector3
	return V3(math.sin(a), 0, -math.cos(a))
end
local function tangent(a: number): Vector3
	return V3(math.cos(a), 0, math.sin(a))
end

---------------------------------------------------------------------------------------------------------------------
-- the six candle signs (also on the bell's pattern slots): strokes in [-1, 1]^2 (u right, v up) and dots {u, v, d}
---------------------------------------------------------------------------------------------------------------------
local function arcPts(cx: number, cy: number, r: number, a0: number, a1: number, n: number): { { number } }
	local out = {}
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		table.insert(out, { cx + math.cos(a) * r, cy + math.sin(a) * r })
	end
	return out
end
local function polyline(pts: { { number } }): { { number } }
	local segs = {}
	for i = 1, #pts - 1 do
		table.insert(segs, { pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2] })
	end
	return segs
end
local function concat(a: { any }, b: { any }): { any }
	local out = table.clone(a)
	for _, v in ipairs(b) do
		table.insert(out, v)
	end
	return out
end
local GLYPHS = {
	-- 1 crescent moon
	{ Strokes = concat(polyline(arcPts(0, 0, .86, 55, 305, 6)), polyline(arcPts(.36, 0, .6, 80, 280, 4))), Dots = {} },
	-- 2 paw
	{ Strokes = {}, Dots = { { 0, -.32, .95 }, { -.66, .26, .44 }, { -.24, .66, .44 }, { .24, .66, .44 }, { .66, .26, .44 } } },
	-- 3 bone
	{ Strokes = { { -.55, -.55, .55, .55 } }, Dots = { { -.76, -.48, .4 }, { -.48, -.76, .4 }, { .48, .76, .4 }, { .76, .48, .4 } } },
	-- 4 eye
	{ Strokes = polyline({ { -.92, 0 }, { -.36, .46 }, { .36, .46 }, { .92, 0 }, { .36, -.46 }, { -.36, -.46 }, { -.92, 0 } }),
		Dots = { { 0, 0, .5 } } },
	-- 5 bell
	{ Strokes = { { -.26, .78, .26, .78 }, { -.26, .78, -.44, .08 }, { -.44, .08, -.8, -.52 }, { .26, .78, .44, .08 }, { .44, .08, .8, -.52 },
		{ -.86, -.58, .86, -.58 } }, Dots = { { 0, -.86, .32 } } },
	-- 6 star
	{ Strokes = { { 0, .92, 0, -.92 }, { -.8, .46, .8, -.46 }, { -.8, -.46, .8, .46 } }, Dots = {} },
}
Finale.GlyphDefs = GLYPHS

-- draws sign `index` on the surface frame F (LookVector points INTO the surface, X = the viewer's right, Y = up), size =
-- half-extent in studs. b = rig builder (bone given) or nil for plain parts under `group`.
function Finale.Glyph(b: any, bone: string?, F: CFrame, size: number, index: number, color: Color3, group: Instance, name: string?)
	local g = GLYPHS[((index - 1) % #GLYPHS) + 1]
	local nm = name or "Glyph"
	local w = math.max(.12, size * .2)
	local depth = math.max(.08, size * .1)
	local out = {}
	local function at(u: number, v: number): Vector3
		return (F * CF(u * size, v * size, depth * .5 - .02)).Position
	end
	for _, s in ipairs(g.Strokes) do
		local a, c = at(s[1], s[2]), at(s[3], s[4])
		local p
		if b and bone then
			p = b:Bar(bone, nm, a, c, w, depth, color, MAT.Neon, { Group = group, Shadow = false }, -F.LookVector)
		else
			local cf, len = barCF(a, c, -F.LookVector)
			p = part(group, nm, "Part", V3(w, depth, len + w * .6), cf, color, MAT.Neon)
		end
		table.insert(out, p)
	end
	for _, d in ipairs(g.Dots) do
		local pos = at(d[1], d[2])
		local dd = d[3] * size
		local p
		if b and bone then
			p = b:Ball(bone, nm, dd, pos, color, MAT.Neon, { Group = group, Shadow = false })
		else
			p = part(group, nm, "Part", V3(dd, dd, dd), CF(pos), color, MAT.Neon, { Shape = Enum.PartType.Ball })
		end
		table.insert(out, p)
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- THE BLACK BELL
---------------------------------------------------------------------------------------------------------------------
-- the bell's profile (y, outer radius) from the shoulder down to the lip, relative to the bell centre
local PROFILE = { { 13.1, 3.5 }, { 12.6, 4.8 }, { 11.7, 5.8 }, { 10.2, 6.4 }, { 6.8, 6.75 }, { 2.6, 7.05 }, { -1.6, 7.6 }, { -5.5, 8.6 },
	{ -8.8, 9.9 }, { -11.2, 11.3 }, { -12.9, 12.3 } }
Finale.BellProfile = PROFILE
local function profileR(y: number): number
	if y >= PROFILE[1][1] then
		return PROFILE[1][2]
	end
	for i = 2, #PROFILE do
		local a, b = PROFILE[i - 1], PROFILE[i]
		if y >= b[1] then
			return a[2] + (b[2] - a[2]) * (a[1] - y) / (a[1] - b[1])
		end
	end
	return PROFILE[#PROFILE][2]
end
Finale.BellRadius = profileR

-- the main crack: stave column + its angle
local function crackAngle(n: number): (number, number)
	local k = n - 1
	return k, (k + .5) / n * 2 * PI
end

function Finale.Bell(opts: { [string]: any }?): Model
	local o = opts or {}
	local detail = o.Detail or 1
	local N = detail >= .7 and 18 or 12
	local rng = newRng(o.Seed or 1331)
	local hang = Finale.BellHang
	local b = Boss.NewRig("BlackBell", V3(1, 1, 1), CF(hang))
	b:Bone("Bell", nil, hang)
	b:Bone("Clapper", "Bell", V3(0, 12.2, 0))
	local function P(name, size, cf, color, mat, extra)
		local ex = extra or {}
		ex.Shadow = ex.Shadow == true
		return b:Part("Bell", name, size, cf, color, mat, ex)
	end
	local kc, ac = crackAngle(N)
	---------------------------------------------------------------- the body: staves following the profile
	local T = 1.15
	for i = 1, #PROFILE - 1 do
		local y0, r0 = PROFILE[i][1], PROFILE[i][2]
		local y1, r1 = PROFILE[i + 1][1], PROFILE[i + 1][2]
		for k = 0, N - 1 do
			-- the cracked chunk: the two lowest staves of column kc are broken out of the lip
			if k == kc and i >= #PROFILE - 2 then
				continue
			end
			local a = (k + .5) / N * 2 * PI
			local ov, tv = outward(a), tangent(a)
			local d = (ov * (r1 - r0) + V3(0, y1 - y0, 0))
			local len = d.Magnitude
			d = d.Unit
			local n = (ov * (y0 - y1) + V3(0, r1 - r0, 0)).Unit
			local mid = ov * ((r0 + r1) / 2) + V3(0, (y0 + y1) / 2, 0) - n * (T / 2)
			local w = 2 * PI * math.max(r0, r1) / N * 1.08
			-- one smooth casting: the same iron everywhere, a little rust bleeding down from the rune band
			local shade = COL.Iron
			if i >= 6 and rng:NextNumber() < .14 then
				shade = COL.IronRust:Lerp(COL.Iron, .6)
			elseif i <= 3 then
				shade = COL.Iron:Lerp(COL.IronEdge, .18) -- the shoulder catches the light
			end
			P("Stave", V3(w, len + .14, T), CFrame.fromMatrix(mid, tv, -d), shade, MAT.CorrodedMetal, { Shadow = i >= 4 })
		end
	end
	-- the crown dome closing the top + the crown boss + the canons (hanging loop)
	P("Crown", V3(7.6, 2.0, 7.6), CF(0, 12.85, 0), COL.Iron:Lerp(COL.IronEdge, .18), MAT.CorrodedMetal, { Mesh = "Sphere", Shadow = true })
	P("CrownBoss", V3(1.6, 3.6, 3.6), CF(0, 13.9, 0) * ANG(0, 0, PI / 2), COL.Iron, MAT.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
	for _, s in ipairs({ -1, 1 }) do
		b:Bar("Bell", "Canon", V3(s * 1.5, 14.0, 0), V3(s * 1.15, 15.6, 0), .9, .9, COL.Iron, MAT.CorrodedMetal, { Shadow = false })
		b:Bar("Bell", "Canon", V3(0, 14.0, s * 1.5), V3(0, 15.6, s * 1.15), .9, .9, COL.IronDark, MAT.CorrodedMetal, { Shadow = false })
	end
	P("HangRing", V3(1.0, 2.8, 2.8), CF(0, 15.8, 0) * ANG(0, PI / 2, 0), COL.IronEdge, MAT.Metal, { Shape = Enum.PartType.Cylinder })
	---------------------------------------------------------------- raised bands: shoulder, rune band frame, the sound bow
	local function band(y: number, extra: number, h: number, depth: number, color: Color3, name: string, skip: (number) -> boolean)
		local r = profileR(y) + extra
		for k = 0, N - 1 do
			local a = (k + .5) / N * 2 * PI
			if not skip(a) then
				local ov, tv = outward(a), tangent(a)
				P(name, V3(2 * PI * r / N * 1.06, h, depth), CFrame.fromMatrix(ov * (r - depth / 2) + V3(0, y, 0), tv, V3(0, 1, 0)), color,
					MAT.CorrodedMetal)
			end
		end
	end
	local function none(_a: number): boolean
		return false
	end
	band(11.1, .3, .7, 1.0, COL.IronBand, "ShoulderBand", none)
	band(3.4, .4, .7, 1.0, COL.IronBand, "Band", none)
	band(-3.6, .45, .7, 1.0, COL.IronBand, "Band", none)
	-- the sound bow: a thick torus around the lip (broken where the chunk is missing)
	local lipN = N + 4
	local lipR, lipY = 12.3, -12.55
	for k = 0, lipN - 1 do
		local a = (k + .5) / lipN * 2 * PI
		local da = math.abs(((a - ac + PI) % (2 * PI)) - PI)
		if da > 2 * PI / N * .62 then
			local p0 = outward(k / lipN * 2 * PI) * lipR + V3(0, lipY, 0)
			local p1 = outward((k + 1) / lipN * 2 * PI) * lipR + V3(0, lipY, 0)
			b:Cyl("Bell", "SoundBow", p0, p1, 1.55, COL.IronEdge:Lerp(COL.Iron, .45), MAT.CorrodedMetal, { Shadow = false })
			-- a thin violet glow under the lip (flares on every toll)
			if k % 2 == 0 then
				b:Bar("Bell", "RimGlow", p0 - V3(0, .82, 0) - outward(a) * .25, p1 - V3(0, .82, 0) - outward(a) * .25, .22, .14, COL.RuneDeep,
					MAT.Neon, { Shadow = false })
			end
		end
	end
	---------------------------------------------------------------- the jagged break + the glowing rim crack
	do
		local ov, tv = outward(ac), tangent(ac)
		local yTop = PROFILE[#PROFILE - 2][1]
		local rTop = PROFILE[#PROFILE - 2][2]
		-- jagged teeth hanging from the stave above the gap and standing at its sides
		for i, s in ipairs({ -1, 0, 1 }) do
			local pos = ov * (rTop + .3) + tv * (s * 1.2) + V3(0, yTop - .9 - (i == 2 and .8 or 0), 0)
			P("BrokenEdge", V3(1.1, 1.8 + (i == 2 and 1 or 0), .9), CFrame.fromMatrix(pos, tv, V3(0, -1, 0)) * ANG(0, 0, s * .35),
				COL.IronDark, MAT.CorrodedMetal, { Class = "WedgePart" })
		end
		for _, s in ipairs({ -1, 1 }) do
			local a = ac + s * (2 * PI / N) * .58
			local pos = outward(a) * (profileR(-11.6) - .2) + V3(0, -11.6, 0)
			P("BrokenEdge", V3(.9, 2.4, 1.0), CFrame.fromMatrix(pos, tangent(a), V3(0, 1, 0)) * ANG(0, 0, s * .4), COL.IronDark,
				MAT.CorrodedMetal, { Class = "WedgePart" })
		end
		-- the glowing crack running up from the break (zig-zag over the staves), with branches
		local function surf(a: number, y: number, lift: number?): Vector3
			return outward(a) * (profileR(y) + (lift or .06)) + V3(0, y, 0)
		end
		local zig = { { 0, -9.6 }, { -.07, -7.4 }, { .05, -5.2 }, { -.04, -3.0 }, { .08, -1.0 }, { .02, 1.4 } }
		for i = 1, #zig - 1 do
			local a0, a1 = ac + zig[i][1], ac + zig[i + 1][1]
			local p0, p1 = surf(a0, zig[i][2]), surf(a1, zig[i + 1][2])
			local w = .34 - i * .04
			b:Bar("Bell", "Crack", p0, p1, w, .16, i <= 2 and COL.RuneHot or COL.Rune, MAT.Neon, { Shadow = false }, outward((a0 + a1) / 2))
		end
		for _, br in ipairs({ { 2, .13, -6.2 }, { 3, -.16, -3.9 }, { 4, .15, -1.9 } }) do
			local base = zig[br[1]]
			local p0 = surf(ac + base[1], base[2])
			local p1 = surf(ac + base[1] + br[2], br[3])
			b:Bar("Bell", "Crack", p0, p1, .16, .14, COL.Rune, MAT.Neon, { Shadow = false }, outward(ac + base[1]))
		end
		-- a smaller crack on the far side
		local a2 = ac + PI * .85
		local z2 = { { 0, -12.0 }, { .05, -10.0 }, { -.03, -8.3 }, { .04, -6.9 } }
		for i = 1, #z2 - 1 do
			b:Bar("Bell", "Crack", surf(a2 + z2[i][1], z2[i][2]), surf(a2 + z2[i + 1][1], z2[i + 1][2]), .2, .14, COL.Rune, MAT.Neon,
				{ Shadow = false }, outward(a2))
		end
		-- violet light leaking through the gap
		local l = b:Light("Bell", ov * 9 + V3(0, -10.5, 0), COL.Rune, 12, 0, "CrackLight")
		local _ = l
	end
	---------------------------------------------------------------- the rune band: six pattern slots + runes between them
	local slotY = -.2
	for i = 1, 6 do
		local a = (i - 1) / 6 * 2 * PI + PI / 6
		local ov, tv = outward(a), tangent(a)
		local r = profileR(slotY)
		local g = b:Group("Bell", "PatternSlot_" .. i, { Slot = i })
		b:Part("Bell", "SlotPlate", V3(.5, 4.0, 4.0), CFrame.fromMatrix(ov * (r + .18) + V3(0, slotY, 0), ov, V3(0, 1, 0)), COL.IronDark,
			MAT.CorrodedMetal, { Group = g, Shape = Enum.PartType.Cylinder, Shadow = false })
		b:Part("Bell", "SlotRim", V3(.32, 4.6, 4.6), CFrame.fromMatrix(ov * (r + .02) + V3(0, slotY, 0), ov, V3(0, 1, 0)), COL.RuneDim,
			MAT.Neon, { Group = g, Shape = Enum.PartType.Cylinder, Shadow = false })
		local F = CFrame.fromMatrix(ov * (r + .5) + V3(0, slotY, 0), -tv, V3(0, 1, 0))
		Finale.Glyph(b, "Bell", F, 1.35, i, COL.RuneDim, g, "Glyph")
	end
	for i = 1, 6 do
		-- two-stroke runes between the slots (flare on the tolls)
		local a = (i - 1) / 6 * 2 * PI
		local r = profileR(slotY)
		local base = outward(a) * (r + .1)
		local tv = tangent(a)
		b:Bar("Bell", "Rune", base + V3(0, -1.6, 0) - tv * .45, base + V3(0, 1.4, 0) + tv * .2, .26, .16, COL.RuneDeep, MAT.Neon,
			{ Shadow = false }, outward(a))
		b:Bar("Bell", "Rune", base + V3(0, .4, 0) - tv * .7, base + V3(0, -.4, 0) + tv * .75, .22, .16, COL.RuneDeep, MAT.Neon,
			{ Shadow = false }, outward(a))
	end
	---------------------------------------------------------------- an inscription ring low on the flare + a lip band
	if detail >= .5 then
		band(-10.3, .4, .5, .9, COL.IronBand, "Band", function(a: number): boolean
			return math.abs(((a - ac + PI) % (2 * PI)) - PI) < 2 * PI / N * .6
		end)
	end
	local inscr = detail >= .7 and 18 or 9
	for i = 1, inscr do
		local a = (i - .5) / inscr * 2 * PI + .09
		if math.abs(((a - ac + PI) % (2 * PI)) - PI) > .18 then
			local y = -7.4 + (i % 3) * .25
			local base = outward(a) * (profileR(y) + .08) + V3(0, y, 0)
			local tv = tangent(a)
			local tilt = (i % 2 == 0) and .5 or -.4
			b:Bar("Bell", "Rune", base - tv * tilt * .6 + V3(0, -.7, 0), base + tv * tilt * .6 + V3(0, .7, 0), .2, .14, COL.RuneDeep, MAT.Neon,
				{ Shadow = false }, outward(a))
		end
	end
	---------------------------------------------------------------- dog-skull gargoyles on the shoulder, chain eyes
	local skulls = detail >= .7 and 8 or 4
	for i = 1, skulls do
		local a = (i - .5) / skulls * 2 * PI
		local ov, tv = outward(a), tangent(a)
		local y = 9.4
		local base = ov * (profileR(y) + .35) + V3(0, y, 0)
		-- skull frame: LookVector into the bell, +Z = outward, X = the viewer's right
		local F = CFrame.fromMatrix(base, -tv, V3(0, 1, 0)) * ANG(.25, 0, 0)
		b:Ell("Bell", "Gargoyle", V3(1.9, 1.5, 1.9), F * CF(0, .25, .1), COL.Bone, MAT.SmoothPlastic, { Shadow = false })
		b:Ell("Bell", "GargoyleSnout", V3(.95, .7, 1.9), F * CF(0, -.15, 1.25) * ANG(.12, 0, 0), COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
		b:Box("Bell", "GargoyleJaw", V3(.75, .25, 1.3), F * CF(0, -.6, 1.15) * ANG(.35, 0, 0), COL.BoneDark, MAT.SmoothPlastic, { Shadow = false })
		for _, s in ipairs({ -1, 1 }) do
			b:Ell("Bell", "GargoyleSocket", V3(.55, .45, .3), F * CF(s * .45, .35, .92), COL.Void, MAT.SmoothPlastic, { Shadow = false })
			b:Ball("Bell", "GargoyleEye", .26, (F * CF(s * .45, .35, 1.02)).Position, COL.RuneHot, MAT.Neon, { Shadow = false })
			b:Wedge("Bell", "GargoyleEar", V3(.22, .6, .8), F * CF(s * .6, .95, -.35) * ANG(-.9, 0, s * -.35), COL.BoneDark, MAT.SmoothPlastic,
				{ Shadow = false })
			b:Fang("Bell", "GargoyleFang", (F * CF(s * .28, -.35, 1.95)).Position, .4, .2, .12, true, COL.BoneLight)
		end
	end
	for i, key in ipairs(Finale.Keys) do
		local a = (i - 1) * PI / 2
		local ov, tv = outward(a), tangent(a)
		local y = 10.4
		local base = ov * (profileR(y) + .3) + V3(0, y, 0)
		b:Box("Bell", "EyePlate", V3(2.6, 2.4, .6), CFrame.fromMatrix(base, tv, V3(0, 1, 0)), COL.IronBand, MAT.CorrodedMetal, { Shadow = false })
		local ringC = base + ov * 1.25 + V3(0, .3, 0)
		for s = 0, 5 do
			local a0 = s / 6 * 2 * PI
			local a1 = (s + 1) / 6 * 2 * PI
			local p0 = ringC + ov * math.cos(a0) * .95 + V3(0, math.sin(a0) * .95, 0)
			local p1 = ringC + ov * math.cos(a1) * .95 + V3(0, math.sin(a1) * .95, 0)
			b:Cyl("Bell", "ChainEye", p0, p1, .45, COL.IronEdge, MAT.Metal, { Shadow = false })
		end
		b:Attach("Bell", "ChainEye_" .. key, ringC)
	end
	---------------------------------------------------------------- inside: the clapper, the soul glow, the light
	b:Cyl("Clapper", "ClapperRod", V3(0, 12.0, 0), V3(0, -7.6, 0), .9, COL.Iron, MAT.CorrodedMetal, { Shadow = false })
	b:Ball("Clapper", "ClapperBall", 3.6, V3(0, -9.4, 0), COL.IronDark, MAT.CorrodedMetal, { Shadow = false })
	b:Part("Clapper", "ClapperGlow", V3(.45, 3.9, 3.9), CF(0, -9.4, 0) * ANG(0, 0, PI / 2), COL.Rune, MAT.Neon,
		{ Shape = Enum.PartType.Cylinder, Shadow = false })
	b:Ball("Bell", "SoulGlow", 9.5, V3(0, 1, 0), COL.Rune, MAT.Neon, { T = 1, Shadow = false })
	b:Light("Bell", V3(0, -2, 0), COL.Rune, 34, 0, "BellLight")
	b:Attach("Bell", "Core", V3(0, 1, 0))
	b:Attach("Bell", "Mouth", V3(0, -12.8, 0))
	b.Model:SetAttribute("Parts", b.Count)
	return b.Model
end

---------------------------------------------------------------------------------------------------------------------
-- CURSED CHAINS
---------------------------------------------------------------------------------------------------------------------
-- link-local parts (link centre at the origin, long axis Z): 2 side bars + 2 rounded caps + a glow core; every 4th link
-- carries a barbed rune shackle. Low detail (opts.Detail < .5): side bars + glow only.
function Finale.Chain(count: number, opts: { [string]: any }?): (Model, any)
	local o = opts or {}
	local L = o.LinkLength or 3.0
	local W = o.Width or 1.75
	local th = o.Thickness or .55
	local detail = o.Detail or 1
	local m = Instance.new("Model")
	m.Name = "CursedChain"
	local handle = { Links = {}, Count = count, LinkLength = L * .78 }
	for i = 1, count do
		local link = { Parts = {}, Local = {}, Index = i }
		local function add(name, class, size, lcf, color, mat, ex)
			local p = part(m, name, class, size, lcf, color, mat, ex)
			p:SetAttribute("Link", i)
			table.insert(link.Parts, p)
			table.insert(link.Local, lcf)
			return p
		end
		local tint = (i % 3 == 0) and COL.IronRust:Lerp(COL.Iron, .4) or COL.Iron
		for _, s in ipairs({ -1, 1 }) do
			add("LinkSide", "Part", V3(th, th, L - th * .6), CF(s * (W / 2 - th / 2), 0, 0), tint, MAT.CorrodedMetal)
		end
		if detail >= .5 then
			for _, s in ipairs({ -1, 1 }) do
				add("LinkCap", "Part", V3(W, th * 1.12, th * 1.12), CF(0, 0, s * (L / 2 - th / 2)), COL.IronDark, MAT.CorrodedMetal,
					{ Shape = Enum.PartType.Cylinder })
			end
		end
		link.Glow = add("LinkGlow", "Part", V3(.26, .26, L * .72), CF(), COL.RuneDeep, MAT.Neon, { T = .35 })
		if detail >= .5 and i % 4 == 2 then
			add("Shackle", "Part", V3(W + .25, .5, .9), CF(0, 0, 0), COL.IronBand, MAT.CorrodedMetal)
			add("ShackleRune", "Part", V3(.5, .56, .3), CF(0, 0, -.35), COL.Rune, MAT.Neon)
			for _, s in ipairs({ -1, 1 }) do
				add("Barb", "WedgePart", V3(.3, .7, .5), CF(s * (W / 2 + .2), .4, 0) * ANG(0, 0, s * -.5), COL.IronEdge, MAT.Metal)
			end
		end
		table.insert(handle.Links, link)
	end
	m:SetAttribute("Links", count)
	return m, handle
end

-- point at arc length s along a polyline (+ tangent)
local function along(path: { Vector3 }, lens: { number }, s: number): (Vector3, Vector3)
	for i = 1, #path - 1 do
		local l = lens[i]
		if s <= l or i == #path - 1 then
			local a, c = path[i], path[i + 1]
			local d = c - a
			local f = l > 1e-6 and math.clamp(s / l, 0, 1) or 0
			return a + d * f, d.Magnitude > 1e-6 and d.Unit or V3(0, 0, -1)
		end
		s -= l
	end
	return path[#path], V3(0, 0, -1)
end

-- the chain's link CFrames along `path` (polyline from the anchor to the bell). grow (0..1) shows only the first part of
-- the chain (the rest collapsed onto the anchor), for "chains attach". Returns parts, cframes for BulkMoveTo.
function Finale.LayChain(handle: any, path: { Vector3 }, grow: number?): ({ BasePart }, { CFrame })
	local lens, total = {}, 0
	for i = 1, #path - 1 do
		lens[i] = (path[i + 1] - path[i]).Magnitude
		total += lens[i]
	end
	local n = handle.Count
	local step = total / math.max(1, n)
	local g = math.clamp(grow or 1, 0, 1)
	local parts, cfs = {}, {}
	for i, link in ipairs(handle.Links) do
		local s = (i - .5) * step * g
		local pos, dir = along(path, lens, s)
		local up = math.abs(dir.Y) > .97 and V3(1, 0, 0) or V3(0, 1, 0)
		local base = look(pos, pos + dir, up)
		if i % 2 == 0 then
			base = base * ANG(0, 0, PI / 2)
		end
		-- a slight per-link roll so the chain does not look machined
		base = base * ANG(0, 0, math.sin(i * 1.7) * .08)
		local scale = math.clamp(step / handle.LinkLength, .7, 1.25)
		for k, p in ipairs(link.Parts) do
			local lc = link.Local[k]
			table.insert(parts, p)
			table.insert(cfs, base * CF(lc.Position.X, lc.Position.Y, lc.Position.Z * scale) * (lc - lc.Position))
		end
	end
	return parts, cfs
end

-- a sagging path from a to b (n segments): the chains hang a little under their own weight
function Finale.ChainPath(a: Vector3, b: Vector3, sag: number?, n: number?): { Vector3 }
	return Boss.Sag(a, b, sag or 1.6, n or 10)
end

function Finale.ChainAnchor(height: number?): Model
	local h = math.max(4, height or 10)
	local m = Instance.new("Model")
	m.Name = "ChainAnchor"
	groundRoot(m)
	local lean = ANG(.05, 0, -.04)
	local post = CF(0, h / 2, 0) * lean
	part(m, "Post", "Part", V3(2.8, h, 2.8), post, COL.StoneDark, MAT.Slate, { Shadow = true })
	part(m, "PostCap", "Part", V3(3.3, .7, 3.3), post * CF(0, h / 2 + .2, 0), COL.Stone, MAT.Slate)
	part(m, "PostFoot", "Part", V3(3.8, 1.2, 3.8), CF(0, .6, 0), COL.Stone, MAT.Slate)
	-- a dog skull crowning the post
	part(m, "Skull", "Part", V3(2.0, 1.6, 2.2), post * CF(0, h / 2 + 1.3, 0), COL.Bone, MAT.SmoothPlastic, { Mesh = true })
	part(m, "SkullSnout", "Part", V3(.9, .7, 1.3), post * CF(0, h / 2 + 1.0, -1.2), COL.BoneDark, MAT.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		part(m, "SkullEye", "Part", V3(.38, .38, .38), post * CF(s * .42, h / 2 + 1.45, -.95), COL.Rune, MAT.Neon, { Shape = Enum.PartType.Ball })
	end
	-- rune strip down the front
	for i = 0, 2 do
		local y = h * (.25 + i * .22)
		part(m, "Rune", "Part", V3(.3, h * .14, .2), post * CF(0, y - h / 2, -1.42) * ANG(0, 0, (i % 2 == 0) and .3 or -.3), COL.RuneDeep, MAT.Neon)
	end
	-- the iron ring facing -Z (the chain hooks in here)
	local ringC = post * CF(0, h / 2 - 1.0, -2.0)
	for s = 0, 7 do
		local a0, a1 = s / 8 * 2 * PI, (s + 1) / 8 * 2 * PI
		local p0 = (ringC * CF(math.cos(a0) * 1.05, math.sin(a0) * 1.05, 0)).Position
		local p1 = (ringC * CF(math.cos(a1) * 1.05, math.sin(a1) * 1.05, 0)).Position
		local cf, len = barCF(p0, p1)
		part(m, "Ring", "Part", V3(len + .2, .42, .42), cf * ANG(0, PI / 2, 0), COL.IronEdge, MAT.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "RingPlate", "Part", V3(1.6, 1.6, .5), post * CF(0, h / 2 - 1.0, -1.55), COL.IronBand, MAT.CorrodedMetal)
	-- rubble at the foot
	local rng = newRng(math.floor(h * 13))
	for i = 1, 3 do
		local a = i / 3 * 2 * PI + rng:NextNumber(-.4, .4)
		local s = rng:NextNumber(.8, 1.4)
		part(m, "Rubble", "Part", V3(s, s * .7, s * .9), CF(math.cos(a) * 2.4, s * .3, math.sin(a) * 2.4) * ANG(rng:NextNumber(0, 2), a, 0),
			COL.Stone, MAT.Slate)
	end
	local ring = Instance.new("Attachment")
	ring.Name = "Ring"
	ring.CFrame = ringC
	ring.Parent = m.PrimaryPart
	m:SetAttribute("Height", h)
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- CURSED CANDLES
---------------------------------------------------------------------------------------------------------------------
function Finale.Candle(index: number, opts: { [string]: any }?): Model
	local o = opts or {}
	local rng = newRng(400 + (index or 1) * 17)
	local H = o.Height or rng:NextNumber(8.4, 10.2)
	local R = 1.45
	local m = Instance.new("Model")
	m.Name = "CursedCandle_" .. tostring(index)
	groundRoot(m)
	m:SetAttribute("Index", index)
	-- iron tripod: three clawed feet, a bowl, a stem
	for i = 1, 3 do
		local a = i / 3 * 2 * PI + .3
		local foot = V3(math.cos(a) * 2.5, .25, math.sin(a) * 2.5)
		local knee = V3(math.cos(a) * 1.6, 1.4, math.sin(a) * 1.6)
		local cf, len = barCF(foot, knee)
		part(m, "Leg", "Part", V3(.42, .42, len), cf, COL.Iron, MAT.CorrodedMetal)
		local cf2, len2 = barCF(knee, V3(0, 2.1, 0))
		part(m, "Leg", "Part", V3(.38, .38, len2), cf2, COL.Iron, MAT.CorrodedMetal)
		part(m, "Claw", "WedgePart", V3(.5, .5, .9), look(foot, foot + V3(math.cos(a), 0, math.sin(a))) * CF(0, 0, -.3), COL.IronEdge, MAT.Metal)
	end
	part(m, "Bowl", "Part", V3(.7, 4.4, 4.4), CF(0, 2.35, 0) * ANG(0, 0, PI / 2), COL.IronDark, MAT.CorrodedMetal, { Shape = Enum.PartType.Cylinder,
		Shadow = true })
	part(m, "BowlRim", "Part", V3(.3, 4.8, 4.8), CF(0, 2.75, 0) * ANG(0, 0, PI / 2), COL.IronBand, MAT.Metal, { Shape = Enum.PartType.Cylinder })
	-- a dog-skull boss on the bowl, facing out (-Z)
	part(m, "Skull", "Part", V3(1.3, 1.0, 1.2), CF(0, 2.35, -2.2), COL.Bone, MAT.SmoothPlastic, { Mesh = true })
	part(m, "SkullEye", "Part", V3(.26, .26, .26), CF(-.28, 2.45, -2.75), COL.Rune, MAT.Neon, { Shape = Enum.PartType.Ball })
	part(m, "SkullEye", "Part", V3(.26, .26, .26), CF(.28, 2.45, -2.75), COL.Rune, MAT.Neon, { Shape = Enum.PartType.Ball })
	-- the wax tower (slightly leaning, shaded rings), melted crown, drips, the wax pool in the bowl
	local lean = ANG(rng:NextNumber(-.04, .04), 0, rng:NextNumber(-.04, .04))
	local base = CF(0, 2.8, 0) * lean
	part(m, "WaxPool", "Part", V3(.5, 4.0, 4.0), CF(0, 2.9, 0) * ANG(0, 0, PI / 2), COL.WaxShade, MAT.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Wax", "Part", V3(H, R * 2, R * 2), base * CF(0, H / 2, 0) * ANG(0, 0, PI / 2), COL.Wax, MAT.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder, Shadow = true })
	part(m, "WaxRing", "Part", V3(.5, R * 2 + .12, R * 2 + .12), base * CF(0, H * .3, 0) * ANG(0, 0, PI / 2), COL.WaxShade, MAT.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder })
	-- the melted crown: a ring of blobs, a sunken top
	for i = 1, 7 do
		local a = i / 7 * 2 * PI + rng:NextNumber(-.2, .2)
		local s = rng:NextNumber(.7, 1.0)
		part(m, "WaxLip", "Part", V3(s, s * .8, s), base * CF(math.cos(a) * (R - .25), H + rng:NextNumber(-.15, .2), math.sin(a) * (R - .25)),
			COL.WaxDrip, MAT.SmoothPlastic, { Mesh = true })
	end
	part(m, "WaxTop", "Part", V3(.3, R * 1.8, R * 1.8), base * CF(0, H - .05, 0) * ANG(0, 0, PI / 2), COL.WaxShade, MAT.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder })
	for i = 1, 5 do
		local a = rng:NextNumber(0, 2 * PI)
		local len = rng:NextNumber(1.2, 3.4)
		local y = H - len / 2 - rng:NextNumber(0, .4)
		part(m, "Drip", "Part", V3(.5, len, .5), base * CF(math.cos(a) * (R + .05), y, math.sin(a) * (R + .05)), COL.WaxDrip, MAT.SmoothPlastic,
			{ Mesh = true })
		part(m, "DripTip", "Part", V3(.62, .62, .62), base * CF(math.cos(a) * (R + .08), y - len / 2 + .1, math.sin(a) * (R + .08)), COL.WaxDrip,
			MAT.SmoothPlastic, { Mesh = true })
	end
	-- the candle's sign, carved in violet on the side facing out (-Z): the glyph frame's LookVector points into the candle
	-- (+Z), its X is the viewer's right (-X)
	local G = CFrame.fromMatrix((base * CF(0, H * .55, -R - .04)).Position, -base.RightVector, base.UpVector)
	Finale.Glyph(nil, nil, G, .95, index, COL.Rune, m, "Glyph")
	part(m, "GlyphPlate", "Part", V3(.12, 2.5, 2.5), CFrame.fromMatrix((base * CF(0, H * .55, -R + .02)).Position, -base.LookVector, base.UpVector),
		COL.WaxShade, MAT.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	-- wick, the flame (lit), the smoke (snuffed)
	local top = base * CF(0, H, 0)
	part(m, "Wick", "Part", V3(.16, .8, .16), top * CF(0, .3, 0) * ANG(.15, 0, .1), COL.Wick, MAT.SmoothPlastic)
	local flame = Instance.new("Model")
	flame.Name = "Flame"
	flame.Parent = m
	part(flame, "FlameCore", "Part", V3(.8, 1.6, .8), top * CF(0, 1.2, 0), COL.FlameHot, MAT.Neon, { Mesh = true })
	part(flame, "FlameBody", "Part", V3(1.5, 3.2, 1.5), top * CF(0, 1.8, 0), COL.Flame, MAT.Neon, { Mesh = true, T = .15 })
	part(flame, "FlameTip", "Part", V3(.7, 2.2, .7), top * CF(.06, 3.4, 0) * ANG(0, 0, -.08), COL.FlameDeep, MAT.Neon, { Mesh = true, T = .1 })
	part(flame, "FlameHalo", "Part", V3(3.4, 5.0, 3.4), top * CF(0, 2.0, 0), COL.Flame, MAT.Neon, { Mesh = true, T = .8 })
	local holder = part(flame, "FlameLight", "Part", V3(.2, .2, .2), top * CF(0, 2.0, 0), COL.Flame, MAT.SmoothPlastic, { T = 1 })
	local light = Instance.new("PointLight")
	light.Color = COL.Flame
	light.Range = 14
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = holder
	local smoke = Instance.new("Model")
	smoke.Name = "Smoke"
	smoke.Parent = m
	for i = 1, 3 do
		part(smoke, "SmokeWisp", "Part", V3(.35 + i * .15, 1.4 + i * .4, .35 + i * .15), top * CF(math.sin(i * 1.3) * .35, .8 + i * 1.1, 0)
			* ANG(0, 0, math.sin(i * 2.1) * .25), COL.Smoke, MAT.SmoothPlastic, { Mesh = true, T = .5 + i * .12 })
	end
	local tip = Instance.new("Attachment")
	tip.Name = "FlameTip"
	tip.CFrame = top * CF(0, 2.0, 0)
	tip.Parent = m.PrimaryPart
	m:SetAttribute("Height", H + 2.8)
	Finale.SetCandleLit(m, true)
	return m
end

-- lit: the flame + light show and the smoke hides; snuffed: the other way round. Parts keep their built transparency in
-- the attribute BaseT so this can be called any number of times.
function Finale.SetCandleLit(m: Model, lit: boolean)
	for _, groupName in ipairs({ "Flame", "Smoke" }) do
		local g = m:FindFirstChild(groupName)
		local show = (groupName == "Flame") == (lit == true)
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "FlameLight" then
					if d:GetAttribute("BaseT") == nil then
						d:SetAttribute("BaseT", d.Transparency)
					end
					d.Transparency = show and d:GetAttribute("BaseT") or 1
				elseif d:IsA("PointLight") then
					d.Enabled = show
				end
			end
		end
	end
	m:SetAttribute("Lit", lit == true)
end

---------------------------------------------------------------------------------------------------------------------
-- GHOST DOGS (choir adds)
---------------------------------------------------------------------------------------------------------------------
function Finale.GhostDog(seed: number?, opts: { [string]: any }?): Model
	local rng = newRng(seed or 21)
	local detail = (opts and opts.Detail) or 1
	local b = Boss.NewRig("GhostDog", V3(1, 1, 1), CF(0, .5, 0))
	b:Bone("Body", nil, V3(0, 2.7, 0))
	b:Bone("Head", "Body", V3(0, 3.4, -2.2))
	b:Bone("Jaw", "Head", V3(0, 3.2, -2.9))
	b:Bone("LegFR", "Body", V3(.8, 2.4, -1.5))
	b:Bone("LegFL", "Body", V3(-.8, 2.4, -1.5))
	b:Bone("LegHR", "Body", V3(.75, 2.5, 1.6))
	b:Bone("LegHL", "Body", V3(-.75, 2.5, 1.6))
	b:Bone("Tail", "Body", V3(0, 3.0, 2.3))
	local ghost = COL.Ghost:Lerp(COL.GhostDeep, rng:NextNumber(0, .25))
	local function G(bone, name, size, cf, t)
		return b:Ell(bone, name, size, cf, ghost, MAT.Neon, { T = t or .5, Shadow = false })
	end
	-- spectral body (+ an inner glow), bones showing through: spine, ribs, shoulder blades
	G("Body", "GhostBody", V3(2.3, 2.1, 4.8), CF(0, 2.8, .1) * ANG(.06, 0, 0), .55)
	G("Body", "GhostChest", V3(2.2, 2.3, 2.2), CF(0, 2.7, -1.3), .5)
	b:Ell("Body", "GhostCore", V3(1.2, 1.0, 2.8), CF(0, 2.75, 0), COL.GhostEye, MAT.Neon, { T = .55, Shadow = false })
	b:Bar("Body", "Spine", V3(0, 3.55, -1.9), V3(0, 3.35, 2.1), .26, .3, COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	for i, z in ipairs(detail >= .7 and { -1.5, -.9, -.3 } or { -.9 }) do
		for _, s in ipairs({ -1, 1 }) do
			local p0 = V3(.15 * s, 3.45, z)
			local p1 = V3(.95 * s, 2.85, z + .1)
			local p2 = V3(.7 * s, 2.15, z + .2)
			b:Bar("Body", "Rib", p0, p1, .14, .16, COL.Bone, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
			b:Bar("Body", "Rib", p1, p2, .13, .15, COL.BoneDark, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
			local _ = i
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		b:Box("Body", "Scapula", V3(.16, .9, .6), CF(.7 * s, 3.3, -1.5) * ANG(-.2, 0, .3 * s), COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	end
	-- mist trailing behind
	if detail >= .5 then
		G("Body", "Mist", V3(1.6, 1.2, 2.6), CF(0, 2.6, 2.6) * ANG(-.2, 0, 0), .72)
	end
	-- head: spectral skull + bone mask + burning cyan eyes
	G("Head", "GhostHead", V3(1.8, 1.6, 2.0), CF(0, 3.6, -2.85), .45)
	b:Ell("Head", "SkullMask", V3(1.35, .75, 1.7), CF(0, 3.95, -3.05) * ANG(-.15, 0, 0), COL.BoneLight, MAT.SmoothPlastic, { Shadow = false })
	b:Box("Head", "SnoutBone", V3(.8, .55, 1.25), CF(0, 3.5, -3.95), COL.Bone, MAT.SmoothPlastic, { Shadow = false })
	b:Ell("Head", "Nose", V3(.4, .26, .2), CF(0, 3.66, -4.6), COL.GhostDeep, MAT.Neon, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		b:Ell("Head", "EyeSocket", V3(.48, .42, .3), CF(.42 * s, 3.8, -3.55), COL.Void, MAT.SmoothPlastic, { Shadow = false })
		b:Ball("Head", "Eye", .3, V3(.42 * s, 3.8, -3.68), COL.GhostEye, MAT.Neon, { Shadow = false })
		b:Wedge("Head", "Ear", V3(.22, .9, .55), CF(.55 * s, 4.45, -2.45) * ANG(-.35, 0, -.3 * s), ghost, MAT.Neon, { T = .45, Shadow = false })
		if detail >= .5 then
			b:Fang("Head", "Fang", V3(.28 * s, 3.22, -4.25), .38, .2, .13, true, COL.BoneLight)
		end
	end
	-- jaw
	G("Jaw", "GhostJaw", V3(.85, .4, 1.4), CF(0, 3.05, -3.85), .45)
	b:Bar("Jaw", "JawBone", V3(-.32, 3.0, -3.1), V3(-.26, 2.92, -4.4), .12, .16, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
	b:Bar("Jaw", "JawBone", V3(.32, 3.0, -3.1), V3(.26, 2.92, -4.4), .12, .16, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
	if detail >= .5 then
		b:Fang("Jaw", "Fang", V3(-.2, 3.1, -4.25), .3, .16, .12, false, COL.BoneLight)
		b:Fang("Jaw", "Fang", V3(.2, 3.1, -4.25), .3, .16, .12, false, COL.BoneLight)
	end
	-- legs: spectral upper leg, a bone shank showing through, misty paws
	local legs = { { "LegFR", 1, -1.5, false }, { "LegFL", -1, -1.5, false }, { "LegHR", 1, 1.6, true }, { "LegHL", -1, 1.6, true } }
	for _, l in ipairs(legs) do
		local name, s, z, hind = l[1], l[2], l[3], l[4]
		local hip = V3(.8 * s, 2.4, z)
		local knee = hind and V3(.85 * s, 1.3, z - .35) or V3(.85 * s, 1.3, z + .1)
		local paw = V3(.85 * s, .35, z - .05)
		G(name, "GhostLeg", V3(.75, 1.4, .9), CF((hip + knee) / 2), .5)
		b:Bar(name, "Shank", knee, paw + V3(0, .2, 0), .18, .18, COL.Bone, MAT.SmoothPlastic, { Shadow = false })
		G(name, "GhostShin", V3(.5, 1.2, .55), CF((knee + paw) / 2), .62)
		G(name, "GhostPaw", V3(.62, .32, .8), CF(paw + V3(0, -.05, -.18)), .6)
	end
	-- tail: wisps curling up
	G("Tail", "TailWisp", V3(.5, .5, 1.5), CF(0, 3.25, 2.95) * ANG(.5, 0, 0), .5)
	G("Tail", "TailWisp", V3(.36, .36, 1.3), CF(0, 3.85, 3.6) * ANG(.9, 0, 0), .62)
	b:Ell("Tail", "TailTip", V3(.3, .3, .9), CF(0, 4.4, 3.95) * ANG(1.2, 0, 0), COL.GhostEye, MAT.Neon, { T = .5, Shadow = false })
	b:Attach("Head", "Mouth", V3(0, 3.2, -4.5))
	b:Attach("Body", "Core", V3(0, 2.75, 0))
	b.Model:SetAttribute("Parts", b.Count)
	return b.Model
end

-- ghost dog poses: mode "Run" (bounding gallop; t = time, k = speed 0..1), "Bite" (k = lunge 0..1), "Spawn" (k = rise 0..1),
-- "Idle"
function Finale.GhostPose(mode: string, t: number, k: number): { [string]: CFrame }
	local P = {}
	local run = mode == "Run" and math.clamp(k, 0, 1) or (mode == "Idle" and 0 or .25)
	local ph = t * 11
	local a = math.sin(ph) * .75 * run
	P.LegFR = ANG(a, 0, 0)
	P.LegFL = ANG(math.sin(ph + .5) * .75 * run, 0, 0)
	P.LegHR = ANG(-math.sin(ph + PI) * .7 * run, 0, 0)
	P.LegHL = ANG(-math.sin(ph + PI + .5) * .7 * run, 0, 0)
	P.Body = ANG(math.sin(ph * 2) * .05 * run, 0, math.sin(t * 2.1) * .04)
	P.Head = ANG(math.sin(t * 3.1) * .06 - .05 * run, math.sin(t * 1.7) * .12, 0)
	P.Jaw = ANG(-.12 - math.max(0, math.sin(t * 5)) * .12, 0, 0)
	P.Tail = ANG(.1 + math.sin(t * 6) * .15, math.sin(t * 7) * .45, 0)
	if mode == "Bite" then
		local l = math.sin(math.clamp(k, 0, 1) * PI)
		P.Body = ANG(.18 * l, 0, 0)
		P.Head = ANG(-.35 * l, 0, 0)
		P.Jaw = ANG(-.85 * l, 0, 0)
		P.LegFR = ANG(.7 * l, 0, 0)
		P.LegFL = ANG(.6 * l, 0, 0)
		P.LegHR = ANG(-.4 * l, 0, 0)
		P.LegHL = ANG(-.45 * l, 0, 0)
	elseif mode == "Spawn" then
		local r = 1 - math.clamp(k, 0, 1)
		P.Body = ANG(-.5 * r, 0, 0)
		P.Head = ANG(-.4 * r, 0, 0)
		P.Jaw = ANG(-.6 * r, 0, 0)
	end
	return P
end

---------------------------------------------------------------------------------------------------------------------
-- THE LAST BARK: the colossal spectral hound (sitting, looming over the pit)
---------------------------------------------------------------------------------------------------------------------
Finale.HoundJoints = {
	{ "Pelvis", nil, V3(0, 10, 15) },
	{ "Chest", "Pelvis", V3(0, 22, 7) },
	{ "Neck", "Chest", V3(0, 33, 3.5) },
	{ "Head", "Neck", V3(0, 42.5, -1.5) },
	{ "Jaw", "Head", V3(0, 41.4, -5.6) },
	{ "EarL", "Head", V3(-3.4, 47.2, .6) }, { "EarR", "Head", V3(3.4, 47.2, .6) },
	{ "ArmL", "Chest", V3(-6.6, 29, 4) }, { "ArmR", "Chest", V3(6.6, 29, 4) },
	{ "ForeL", "ArmL", V3(-7.2, 15.5, 2.4) }, { "ForeR", "ArmR", V3(7.2, 15.5, 2.4) },
	{ "PawL", "ForeL", V3(-7.2, 2.6, .5) }, { "PawR", "ForeR", V3(7.2, 2.6, .5) },
	{ "ThighL", "Pelvis", V3(-7.4, 10.5, 15.5) }, { "ThighR", "Pelvis", V3(7.4, 10.5, 15.5) },
	{ "ShinL", "ThighL", V3(-8.2, 5.0, 9.0) }, { "ShinR", "ThighR", V3(8.2, 5.0, 9.0) },
	{ "Tail1", "Pelvis", V3(2.5, 5.5, 20.5) }, { "Tail2", "Tail1", V3(8, 2.6, 19) }, { "Tail3", "Tail2", V3(11, 1.6, 12) },
}
Finale.HoundJawLocal = V3(0, 40.8, -11) -- the jaw socket (the HoundJaw weak point) in the rest pose, model space
Finale.HoundRootOffset = CF(0, 1, 0) -- the rig root sits 1 stud above the ground pivot (HoundCF * this)

function Finale.Hound(opts: { [string]: any }?): Model
	local o = opts or {}
	local detail = o.Detail or 1
	local rng = newRng(o.Seed or 777)
	local b = Boss.NewRig("TheLastBark", V3(2, 2, 2), Finale.HoundRootOffset)
	for _, j in ipairs(Finale.HoundJoints) do
		b:Bone(j[1], j[2], j[3])
	end
	local HIDE, SMOKE = COL.Hide, COL.HideSmoke
	local BONE, BSH = COL.BoneViolet, COL.BoneVioletShade
	local function hide(bone, name, size, cf, t)
		return b:Ell(bone, name, size, cf, HIDE, MAT.SmoothPlastic, { T = t, Shadow = (t or 0) < .3 })
	end
	-- an ellipsoid stretched from a to c (long axis = Z)
	local function limb(bone, name, a, c, w, h, color, mat, t)
		local cf, len = barCF(a, c)
		return b:Ell(bone, name, V3(w, h, len + math.min(w, h) * .5), cf, color or HIDE, mat or MAT.SmoothPlastic, { T = t, Shadow = false })
	end
	local function edge(bone, a, c, w, up)
		-- a violet rim line: the hound is a silhouette, the rim light draws its contour
		return b:Bar(bone, "Rim", a, c, w or .35, .3, COL.Rune, MAT.Neon, { T = .2, Shadow = false }, up)
	end
	local function flame(bone, pos, s, lean)
		local l = lean or V3(0, 0, .3)
		b:Ell(bone, "Mane", V3(s, s * 2.6, s), CF(pos + l * .5) * ANG(l.Z * .6, 0, -l.X * .6), COL.Rune, MAT.Neon, { T = .15, Shadow = false })
		b:Ell(bone, "Mane", V3(s * .5, s * 1.9, s * .5), CF(pos + V3(0, s * 1.0, 0) + l) * ANG(l.Z, 0, -l.X), COL.RuneHot, MAT.Neon,
			{ T = .1, Shadow = false })
	end
	---------------------------------------------------------------- pelvis + haunches (fading into smoke)
	hide("Pelvis", "Haunch", V3(13.5, 11.5, 12.5), CF(0, 9.5, 15.5) * ANG(.2, 0, 0), .3)
	for _, s in ipairs({ -1, 1 }) do
		hide("Pelvis", "HaunchSide", V3(5.8, 10, 11.5), CF(s * 5.8, 8.0, 14.2), .36)
	end
	b:Bar("Pelvis", "IliacCrest", V3(-4.4, 14.6, 15), V3(4.4, 14.6, 15), 1.0, 1.0, BONE, MAT.SmoothPlastic, { Shadow = false })
	for i = 0, 2 do
		local z = 13.5 + i * 2.6
		b:Wedge("Pelvis", "SpinePlate", V3(.7, 2.2 - i * .4, 1.8), CF(0, 15.6 - i * 1.4, z) * ANG(.5, 0, 0), BONE, MAT.SmoothPlastic, { Shadow = false })
	end
	b:Ell("Pelvis", "Wisp", V3(15, 6, 13), CF(0, 4, 17), SMOKE, MAT.Neon, { T = .8, Shadow = false })
	if detail >= .7 then
		for i = 1, 3 do
			b:Ell("Pelvis", "Wisp", V3(4, 7, 4), CF(rng:NextNumber(-5, 5), 14 + i * 2.5, 18 + i * 1.5) * ANG(.4, 0, rng:NextNumber(-.3, .3)), SMOKE,
				MAT.Neon, { T = .82, Shadow = false })
		end
	end
	---------------------------------------------------------------- chest: deep barrel, torn flank showing the ribs, spine
	hide("Chest", "Waist", V3(10, 10.5, 13), CF(0, 15.5, 11.5) * ANG(.55, 0, 0), .15)
	hide("Chest", "Barrel", V3(14.5, 17, 14), CF(0, 22.5, 5.6) * ANG(.35, 0, 0))
	hide("Chest", "Brisket", V3(10.5, 10.5, 8.5), CF(0, 21.5, .6) * ANG(.2, 0, 0))
	b:Ell("Chest", "Hollow", V3(2.6, 10, 9.5), CF(-6.6, 22, 6.6) * ANG(.35, 0, 0), COL.RuneDeep, MAT.Neon, { T = .35, Shadow = false })
	for i = 1, (detail >= .7 and 5 or 3) do
		local z = 3.0 + i * 1.55
		local top = V3(-5.1, 28.5 - i * .9, z + 1.2)
		local mid = V3(-7.8, 22.5 - i * .5, z)
		local low = V3(-5.8, 16.5 - i * .1, z - 1.6)
		b:Bar("Chest", "Rib", top, mid, .8, .65, BONE, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
		b:Bar("Chest", "Rib", mid, low, .7, .6, BSH, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
	end
	b:Ell("Chest", "Hollow", V3(2.0, 6, 5.5), CF(6.7, 21, 8.2) * ANG(.35, 0, 0), COL.RuneDeep, MAT.Neon, { T = .4, Shadow = false })
	for i = 1, 2 do
		local z = 6.5 + i * 1.6
		b:Bar("Chest", "Rib", V3(5.4, 25.2 - i * .6, z + 1), V3(7.6, 21 - i * .4, z), .65, .55, BONE, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
		b:Bar("Chest", "Rib", V3(7.6, 21 - i * .4, z), V3(6.0, 17.4, z - 1.2), .6, .5, BSH, MAT.SmoothPlastic, { Shadow = false }, V3(0, 0, 1))
	end
	for _, s in ipairs({ -1, 1 }) do
		b:Box("Chest", "Scapula", V3(.9, 7.4, 4.4), CF(s * 5.0, 29.8, 5.5) * ANG(-.45, 0, s * .32), BONE, MAT.SmoothPlastic, { Shadow = false })
	end
	for i = 0, 4 do
		b:Wedge("Chest", "SpinePlate", V3(.8, 2.8 - i * .2, 2.0), CF(0, 32.5 - i * 3.2, 2.5 + i * 2.6) * ANG(.6, 0, 0), BONE, MAT.SmoothPlastic,
			{ Shadow = false })
	end
	edge("Chest", V3(0, 30.8, .8), V3(0, 24, 12.5), .45, V3(0, 1, 0))
	edge("Chest", V3(-5.6, 16.6, -1.2), V3(-6.4, 27.5, 1.6), .3)
	edge("Chest", V3(5.6, 16.6, -1.2), V3(6.4, 27.5, 1.6), .3)
	b:Attach("Chest", "Core", V3(0, 23, 3))
	---------------------------------------------------------------- neck + the violet mane
	hide("Neck", "NeckBase", V3(11, 12.5, 10.5), CF(0, 33.5, 3.0) * ANG(-.3, 0, 0))
	hide("Neck", "NeckUpper", V3(9.2, 10.5, 9.0), CF(0, 39, .4) * ANG(-.5, 0, 0))
	for i = 0, 2 do
		b:Wedge("Neck", "SpinePlate", V3(.75, 2.2, 1.8), CF(0, 40 - i * 2.4, 3.8 + i * 1.3) * ANG(.9, 0, 0), BONE, MAT.SmoothPlastic, { Shadow = false })
	end
	local maneN = detail >= .7 and 9 or 5
	for i = 1, maneN do
		local f = (i - 1) / math.max(1, maneN - 1)
		local side = (i % 2 == 0) and 1 or -1
		flame("Neck", V3(side * (1.4 + f * .8), 45.6 - f * 13.5, 2.0 + f * 6.5), 2.6 - f * .9, V3(side * .5, 0, 1.1))
	end
	edge("Neck", V3(0, 45, 1.8), V3(0, 35.5, 7.2), .45, V3(0, 1, 0))
	---------------------------------------------------------------- head: hide cranium, a bone mask, burning eyes
	hide("Head", "Cranium", V3(9.4, 7.8, 9.6), CF(0, 43.8, .2))
	hide("Head", "Cheek", V3(9.8, 5.8, 6.8), CF(0, 42.0, -3.2))
	hide("Head", "Muzzle", V3(5.8, 4.4, 12.5), CF(0, 42.0, -9.4) * ANG(-.05, 0, 0))
	b:Wedge("Head", "MuzzleBridge", V3(4.6, 1.6, 8.0), CF(0, 44.3, -8.6), HIDE, MAT.SmoothPlastic, { Shadow = false })
	b:Ell("Head", "Nose", V3(3.0, 2.0, 1.8), CF(0, 43.0, -15.4), COL.Void, MAT.SmoothPlastic, { Shadow = false })
	b:Ell("Head", "NoseShine", V3(1.2, .5, .6), CF(-.5, 43.7, -16.0), COL.RuneDeep, MAT.Neon, { T = .4, Shadow = false })
	b:Bar("Head", "MaskRidge", V3(0, 46.6, -2.4), V3(0, 44.7, -13.2), .95, .7, BONE, MAT.SmoothPlastic, { Shadow = false }, V3(0, 1, -.15))
	for _, s in ipairs({ -1, 1 }) do
		b:Bar("Head", "MaskBrow", V3(s * .7, 47.0, -2.8), V3(s * 4.3, 46.2, -4.8), 1.1, .8, BONE, MAT.SmoothPlastic, { Shadow = false })
		b:Bar("Head", "MaskCheek", V3(s * 4.5, 43.0, -2.4), V3(s * 3.0, 42.1, -10.6), .85, 1.0, BSH, MAT.SmoothPlastic, { Shadow = false })
		b:Bar("Head", "MaskRim", V3(s * 4.3, 46.0, -4.8), V3(s * 3.9, 43.6, -6.4), .6, .6, BONE, MAT.SmoothPlastic, { Shadow = false })
		b:Ell("Head", "EyeSocket", V3(2.8, 2.1, 1.6), CF(s * 2.9, 44.9, -5.2) * ANG(0, s * .35, 0), COL.Void, MAT.SmoothPlastic, { Shadow = false })
		b:Ball("Head", "EyeCore", 1.9, V3(s * 3.0, 44.85, -5.75), COL.EyeCore, MAT.Neon, { Shadow = false })
		b:Ball("Head", "EyeHalo", 4.6, V3(s * 3.0, 44.85, -5.5), COL.EyeFire, MAT.Neon, { T = .72, Shadow = false })
		b:Ell("Head", "EyeFlame", V3(1.4, 5.0, 1.4), CF(s * 3.5, 47.2, -3.9) * ANG(-.95, 0, s * -.25), COL.EyeFire, MAT.Neon, { T = .05, Shadow = false })
		b:Ell("Head", "EyeFlame", V3(.8, 3.4, .8), CF(s * 3.8, 48.9, -2.0) * ANG(-1.15, 0, s * -.3), COL.RuneHot, MAT.Neon, { T = .15, Shadow = false })
		b:Attach("Head", s < 0 and "EyeL" or "EyeR", V3(s * 3.0, 44.85, -6.0))
		b:Fang("Head", "Fang", V3(s * 2.3, 40.0, -13.6), 3.0, 1.2, .75, true, COL.BoneLight)
		b:Fang("Head", "Tooth", V3(s * 2.6, 40.0, -10.8), 1.6, .8, .5, true, COL.Bone)
		b:Fang("Head", "Tooth", V3(s * 2.7, 40.0, -8.4), 1.2, .7, .45, true, COL.Bone)
	end
	edge("Head", V3(0, 47.8, 3.0), V3(0, 47.0, -2.6), .45, V3(0, 1, 0))
	edge("Head", V3(-4.7, 41.0, -1.4), V3(-2.9, 40.4, -13.0), .25)
	edge("Head", V3(4.7, 41.0, -1.4), V3(2.9, 40.4, -13.0), .25)
	for _, s in ipairs({ -1, 1 }) do
		local ear = s < 0 and "EarL" or "EarR"
		b:Wedge(ear, "Ear", V3(1.8, 7.2, 4.6), CF(s * 3.6, 50.8, 1.4) * ANG(-.35, 0, s * -.25), HIDE, MAT.SmoothPlastic, { Shadow = false })
		b:Wedge(ear, "EarInner", V3(.5, 5.2, 2.6), CF(s * 3.45, 50.4, .6) * ANG(-.35, 0, s * -.25), COL.RuneDeep, MAT.Neon, { T = .25, Shadow = false })
		b:Box(ear, "EarNotch", V3(1.9, .9, 1.0), CF(s * 3.9, 52.8, 2.4) * ANG(.4, 0, s * .4), COL.Void, MAT.SmoothPlastic, { Shadow = false })
	end
	---------------------------------------------------------------- the jaw (opens on Bark; the weak point sits inside)
	hide("Jaw", "LowerJaw", V3(5.0, 2.4, 11.0), CF(0, 39.4, -10.6))
	for _, s in ipairs({ -1, 1 }) do
		b:Bar("Jaw", "Jawbone", V3(s * 3.2, 40.6, -5.4), V3(s * 2.2, 38.9, -14.8), .75, 1.0, BONE, MAT.SmoothPlastic, { Shadow = false })
		b:Fang("Jaw", "Fang", V3(s * 2.0, 40.0, -14.4), 1.8, .9, .6, false, COL.BoneLight)
		b:Fang("Jaw", "Tooth", V3(s * 2.2, 40.0, -11.6), 1.1, .7, .45, false, COL.Bone)
	end
	b:Ell("Jaw", "MouthGlow", V3(3.8, 1.0, 9.0), CF(0, 40.4, -10.0), COL.Throat, MAT.Neon, { T = .2, Shadow = false })
	b:Ball("Jaw", "JawCore", 2.4, Finale.HoundJawLocal, COL.WeakHot, MAT.Neon, { T = 1, Shadow = false })
	b:Ball("Jaw", "JawHalo", 4.8, Finale.HoundJawLocal, COL.WeakGold, MAT.Neon, { T = 1, Shadow = false })
	b:Attach("Jaw", "JawSocket", Finale.HoundJawLocal)
	b:Attach("Jaw", "Mouth", V3(0, 40.8, -14.6))
	---------------------------------------------------------------- forelegs (planted): hide over white-violet bone
	for _, s in ipairs({ -1, 1 }) do
		local arm, fore, paw = s < 0 and "ArmL" or "ArmR", s < 0 and "ForeL" or "ForeR", s < 0 and "PawL" or "PawR"
		hide(arm, "UpperArm", V3(6.8, 15.5, 7.6), CF(s * 7.0, 22.4, 3.2) * ANG(.05, 0, s * .05))
		b:Bar(arm, "Humerus", V3(s * 8.3, 27.5, 1.0), V3(s * 8.6, 16.8, .7), 1.2, 1.2, BONE, MAT.SmoothPlastic, { Shadow = false })
		edge(arm, V3(s * 10.1, 27.6, 2.8), V3(s * 10.2, 17.2, 2.2), .3)
		hide(fore, "Forearm", V3(5.4, 13.6, 5.8), CF(s * 7.2, 9.0, 1.6))
		b:Bar(fore, "Radius", V3(s * 7.2, 14.6, -1.2), V3(s * 7.2, 3.6, -1.6), 1.0, 1.0, BONE, MAT.SmoothPlastic, { Shadow = false })
		b:Ball(fore, "Elbow", 2.4, V3(s * 7.5, 15.4, 4.3), BSH, MAT.SmoothPlastic, { Shadow = false })
		edge(fore, V3(s * 9.7, 14.6, 1.9), V3(s * 9.5, 4.0, 1.5), .25)
		hide(paw, "Paw", V3(6.2, 3.0, 8.0), CF(s * 7.2, 1.5, -1.6))
		for _, dx in ipairs({ -1.9, -.65, .65, 1.9 }) do
			local base = V3(s * 7.2 + dx, 1.5, -5.0)
			b:Bar(paw, "Claw", base, base + V3(dx * .1, -1.0, -1.9), .55, .65, COL.Claw, MAT.SmoothPlastic, { Shadow = false })
		end
		b:Ell(paw, "Wisp", V3(8.5, 2.4, 9.5), CF(s * 7.2, 1.0, -.8), SMOKE, MAT.Neon, { T = .78, Shadow = false })
	end
	---------------------------------------------------------------- hind legs (folded under the haunches, half smoke)
	for _, s in ipairs({ -1, 1 }) do
		local thigh, shin = s < 0 and "ThighL" or "ThighR", s < 0 and "ShinL" or "ShinR"
		hide(thigh, "Thigh", V3(7.0, 8.5, 13), CF(s * 7.8, 7.6, 12.4) * ANG(-.35, 0, 0), .3)
		b:Bar(thigh, "Femur", V3(s * 9.4, 9.8, 15.2), V3(s * 9.6, 5.6, 8.6), 1.0, 1.0, BONE, MAT.SmoothPlastic, { Shadow = false })
		hide(shin, "Shin", V3(4.2, 4.0, 10), CF(s * 8.4, 2.2, 12.6) * ANG(.1, 0, 0), .4)
		hide(shin, "HindPaw", V3(5.0, 2.4, 6.2), CF(s * 8.5, 1.2, 7.4), .35)
		b:Ell(shin, "Wisp", V3(7.5, 2.6, 9.5), CF(s * 8.5, 1.0, 10), SMOKE, MAT.Neon, { T = .8, Shadow = false })
	end
	---------------------------------------------------------------- tail: curled round the right flank, burning out
	limb("Tail1", "Tail", V3(2.5, 5.5, 20.5), V3(8, 2.6, 19), 4.2, 4.0, HIDE, MAT.SmoothPlastic, .3)
	limb("Tail2", "Tail", V3(8, 2.6, 19), V3(11, 1.6, 12), 3.4, 3.2, HIDE, MAT.SmoothPlastic, .4)
	limb("Tail3", "TailFlame", V3(11, 1.6, 12), V3(10.2, 1.8, 5.2), 2.8, 2.4, COL.Rune, MAT.Neon, .25)
	limb("Tail3", "TailFlame", V3(10.4, 1.9, 7), V3(9.6, 2.6, 3.0), 1.3, 1.2, COL.RuneHot, MAT.Neon, .2)
	b.Model:SetAttribute("Parts", b.Count)
	b.Model:SetAttribute("Height", 54)
	return b.Model
end

-- forward kinematics of one bone of a rigged model (the Motor6D chain from the root) with `transforms` applied at the
-- joints and the root at rootCF (default: where it is); returns the bone part's world CFrame
function Finale.Solve(model: Model, transforms: { [string]: CFrame }?, bone: string, rootCF: CFrame?): CFrame?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local tf = transforms or {}
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "Joint" and d.Parent and d.Parent.Parent then
			motors[d.Parent.Parent.Name] = d
		end
	end
	local function solve(name: string, depth: number): CFrame?
		local m = motors[name]
		if not m or depth > 32 then
			return nil
		end
		local parentCF
		if m.Part0 == root then
			parentCF = rootCF or root.CFrame
		else
			local p0 = m.Part0
			parentCF = p0 and p0.Parent and solve(p0.Parent.Name, depth + 1)
		end
		if not parentCF then
			return nil
		end
		return parentCF * m.C0 * (tf[name] or CF()) * m.C1:Inverse()
	end
	return solve(bone, 0)
end

-- where THE LAST BARK's jaw socket lands with the rig root at rootCF (= HoundCF * Finale.HoundRootOffset) in the pose
-- `transforms` (FinaleFX lunges the hound so this point meets the server's JawPos on a Bark)
function Finale.JawPoint(model: Model, transforms: { [string]: CFrame }?, rootCF: CFrame?): Vector3?
	local jawCF = Finale.Solve(model, transforms, "Jaw", rootCF)
	local rest = Finale.Solve(model, {}, "Jaw", Finale.HoundRootOffset)
	if not (jawCF and rest) then
		return nil
	end
	return jawCF * rest:PointToObjectSpace(Finale.HoundJawLocal)
end

-- hound poses (transforms per bone; +X pitch lifts the nose / swings a leg forward, -X lowers it). name: Loom (idle
-- menace), Rise (k 0..1 = coming up out of the dark, hunched), Bark (k = jaw open, head thrown down toward the pit), Circles
-- (forepaw stomps on the beat), Lines (head sweeps breathing lines across the pit), Waves (howling up on each beat),
-- SafeDance (swaying, tail lashing), Howl (victory: head up, jaw wide), Shatter (collapsing forward).
-- t = seconds, beat = beats since the stage's musical start (FINALE_HOUND clock).
function Finale.HoundPose(name: string, t: number, k: number?, beat: number?): { [string]: CFrame }
	local P = {}
	local kk = math.clamp(k or 1, 0, 1)
	local bt = beat or t * 100 / 60
	local ph = bt % 1
	local hit = math.exp(-ph * 6) -- a kick on every beat
	local breath = math.sin(t * 1.3)
	local sway = math.sin(bt * PI / 2)
	P.Chest = ANG(breath * .02, 0, 0)
	P.Neck = ANG(-.06 + math.sin(t * .9) * .03, math.sin(t * .37) * .08, 0)
	P.Head = ANG(-.1 + math.sin(t * 1.1) * .03, math.sin(t * .5 + 1) * .12, math.sin(t * .31) * .04)
	P.Jaw = ANG(-.03 - math.max(0, math.sin(t * .8)) * .06, 0, 0)
	P.EarL = ANG(math.sin(t * 2.3) * .05, 0, math.sin(t * 1.9) * .05)
	P.EarR = ANG(math.sin(t * 2.1 + 1) * .05, 0, -math.sin(t * 1.7) * .05)
	P.Tail1 = ANG(0, math.sin(t * .8) * .12, 0)
	P.Tail2 = ANG(0, math.sin(t * .8 - .6) * .2, 0)
	P.Tail3 = ANG(0, math.sin(t * .8 - 1.2) * .3, 0)
	if name == "Rise" then
		local r = 1 - kk
		P.Chest = ANG(-.3 * r, 0, 0)
		P.Neck = ANG(-.35 * r, 0, 0)
		P.Head = ANG(-.25 * r - .1, 0, 0)
		P.Jaw = ANG(-.25 * r, 0, 0)
		P.ArmL = ANG(-.35 * r, 0, 0)
		P.ArmR = ANG(-.35 * r, 0, 0)
	elseif name == "Bark" then
		-- the lunge: the hound crashes forward over the rim, forelegs reaching, the head driven down into the pit with the
		-- jaw wide open (the weak point); it shudders while it is staggered. FinaleFX moves the rest of the way so the jaw
		-- meets the server's JawPos (Finale.JawPoint).
		local shudder = math.sin(t * 24) * .015 * kk
		P.Pelvis = ANG(-.5 * kk, 0, 0)
		P.Chest = ANG(-.5 * kk, 0, shudder)
		P.Neck = ANG(0, 0, 0)
		P.Head = ANG(.2 * kk + shudder, 0, shudder)
		P.Jaw = ANG(-.85 * kk, 0, 0)
		P.EarL = ANG(-.5 * kk, 0, -.2 * kk)
		P.EarR = ANG(-.5 * kk, 0, .2 * kk)
		P.ArmL = ANG(.95 * kk, 0, 0)
		P.ArmR = ANG(.95 * kk, 0, 0)
		P.ForeL = ANG(-.3 * kk, 0, 0)
		P.ForeR = ANG(-.3 * kk, 0, 0)
	elseif name == "Circles" then
		-- alternate forepaw stomps on the beat, a growl on each
		local left = math.floor(bt) % 2 == 0
		local lift = math.sin(math.clamp(ph / .45, 0, 1) * PI) * kk
		P.ArmL = ANG(left and .45 * lift or 0, 0, 0)
		P.ForeL = ANG(left and -.7 * lift or 0, 0, 0)
		P.ArmR = ANG(left and 0 or .45 * lift, 0, 0)
		P.ForeR = ANG(left and 0 or -.7 * lift, 0, 0)
		P.Chest = ANG(-.05 * hit * kk, 0, (left and 1 or -1) * .04 * lift)
		P.Head = ANG(-.18 - .1 * hit * kk, 0, 0)
		P.Jaw = ANG(-.3 * hit * kk, 0, 0)
	elseif name == "Lines" then
		-- the head sweeps across the pit breathing lines, jaw half open
		P.Neck = ANG(-.2 * kk, sway * .45 * kk, 0)
		P.Head = ANG(-.22 * kk, sway * .2 * kk, 0)
		P.Jaw = ANG((-.35 - .2 * hit) * kk, 0, 0)
		P.Chest = ANG(-.05 * kk, sway * .08 * kk, 0)
	elseif name == "Waves" then
		-- howls up at the black moon on every beat
		P.Neck = ANG((.35 + .12 * hit) * kk, 0, 0)
		P.Head = ANG((.3 + .1 * hit) * kk, 0, 0)
		P.Jaw = ANG((-.35 - .45 * hit) * kk, 0, 0)
		P.Chest = ANG(.08 * kk, 0, 0)
	elseif name == "SafeDance" then
		P.Chest = ANG(0, sway * .12 * kk, sway * .06 * kk)
		P.Neck = ANG(-.12 * kk, -sway * .3 * kk, 0)
		P.Head = ANG(-.14 * kk, -sway * .15 * kk, 0)
		P.Tail1 = ANG(0, math.sin(bt * PI) * .5 * kk, 0)
		P.Tail2 = ANG(0, math.sin(bt * PI - .7) * .6 * kk, 0)
		P.Tail3 = ANG(0, math.sin(bt * PI - 1.4) * .7 * kk, 0)
		P.Jaw = ANG(-.15 * kk, 0, 0)
	elseif name == "Howl" then
		local tr = math.sin(t * 30) * .015 * kk
		P.Chest = ANG(.12 * kk, 0, 0)
		P.Neck = ANG(.55 * kk + tr, 0, 0)
		P.Head = ANG(.45 * kk, 0, tr)
		P.Jaw = ANG(-.75 * kk, 0, 0)
		P.EarL = ANG(-.3 * kk, 0, 0)
		P.EarR = ANG(-.3 * kk, 0, 0)
	elseif name == "Shatter" then
		P.Chest = ANG(-.25 * kk, 0, .05 * kk)
		P.Neck = ANG(-.35 * kk, .1 * kk, 0)
		P.Head = ANG(-.3 * kk, 0, .2 * kk)
		P.Jaw = ANG(-.5 * kk, 0, 0)
	end
	return P
end

---------------------------------------------------------------------------------------------------------------------
-- THE GRAVEKEEPER'S SPIRIT (torn out of the corpse at the false victory, it flies into the bell)
---------------------------------------------------------------------------------------------------------------------
function Finale.Spirit(): Model
	local b = Boss.NewRig("GravekeeperSpirit", V3(1, 1, 1), CF(0, 0, 0))
	b:Bone("Body", nil, V3(0, 7, 0))
	b:Bone("Head", "Body", V3(0, 11.6, -1.2))
	b:Bone("Jaw", "Head", V3(0, 11.0, -3.6))
	b:Bone("ArmL", "Body", V3(-2.4, 9.8, -.6))
	b:Bone("ArmR", "Body", V3(2.4, 9.8, -.6))
	b:Bone("Tail", "Body", V3(0, 4.4, .6))
	local G, H, E = COL.Spirit, COL.SpiritHot, COL.SpiritEdge
	-- a shroud of green fire around a ribcage and a white-hot soul core
	b:Ball("Body", "SoulCore", 2.4, V3(0, 7.8, -.4), H, MAT.Neon, { Shadow = false })
	b:Ball("Body", "SoulHalo", 5.0, V3(0, 7.8, -.4), G, MAT.Neon, { T = .75, Shadow = false })
	b:Bar("Body", "Spine", V3(0, 10.4, .8), V3(0, 4.6, 1.2), .55, .55, H, MAT.Neon, { T = .2, Shadow = false })
	for i = 1, 4 do
		local y = 9.9 - i * 1.15
		for _, s in ipairs({ -1, 1 }) do
			local p0 = V3(.2 * s, y + .2, .8)
			local p1 = V3(1.9 * s, y, -.2)
			local p2 = V3(1.0 * s, y - .5, -1.5)
			b:Bar("Body", "Rib", p0, p1, .3, .35, G, MAT.Neon, { T = .25, Shadow = false }, V3(0, 1, 0))
			b:Bar("Body", "Rib", p1, p2, .26, .3, i % 2 == 0 and E or G, MAT.Neon, { T = .3, Shadow = false }, V3(0, 1, 0))
		end
	end
	b:Ell("Body", "Shroud", V3(3.8, 9.4, 3.0), CF(0, 6.6, .8) * ANG(.12, 0, 0), G, MAT.ForceField, { T = .5, Shadow = false })
	b:Ell("Body", "ShroudCore", V3(2.4, 6.4, 2.0), CF(0, 6.4, 1.0) * ANG(.12, 0, 0), E, MAT.Neon, { T = .72, Shadow = false })
	-- the wispy tail it trails instead of legs
	b:Ell("Tail", "Wisp", V3(3.4, 4.6, 3.0), CF(0, 3.4, 1.0) * ANG(.3, 0, 0), G, MAT.Neon, { T = .55, Shadow = false })
	b:Ell("Tail", "Wisp", V3(2.2, 4.0, 2.0), CF(0, .8, 2.4) * ANG(.55, 0, 0), E, MAT.Neon, { T = .62, Shadow = false })
	b:Ell("Tail", "Wisp", V3(1.1, 3.2, 1.1), CF(0, -1.2, 4.0) * ANG(.8, 0, 0), E, MAT.Neon, { T = .7, Shadow = false })
	-- the spectral dog skull (bone-pale fire, long and narrow): deep sockets with burning slits, swept-back horns of flame
	local SK = H:Lerp(G, .35)
	b:Ell("Head", "Skull", V3(2.9, 2.5, 4.0), CF(0, 12.3, -2.1), SK, MAT.Neon, { T = .2, Shadow = false })
	b:Ell("Head", "Snout", V3(1.55, 1.15, 4.2), CF(0, 11.7, -4.9) * ANG(-.1, 0, 0), SK, MAT.Neon, { T = .2, Shadow = false })
	b:Ell("Head", "Glow", V3(4.2, 3.8, 6.2), CF(0, 12.0, -3.2), G, MAT.Neon, { T = .8, Shadow = false })
	b:Ell("Head", "Nose", V3(.7, .45, .5), CF(0, 12.0, -6.95), COL.Void, MAT.SmoothPlastic, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		b:Ell("Head", "EyeSocket", V3(1.15, .7, .55), CF(s * .78, 12.55, -3.85) * ANG(0, s * .35, s * -.35), COL.Void, MAT.SmoothPlastic,
			{ Shadow = false })
		b:Ell("Head", "Eye", V3(.7, .22, .3), CF(s * .8, 12.55, -4.08) * ANG(0, 0, s * -.35), H, MAT.Neon, { Shadow = false })
		b:Ell("Head", "EyeTrail", V3(.3, .35, 3.4), CF(s * 1.05, 12.9, -2.3) * ANG(-.22, s * -.18, 0), E, MAT.Neon, { T = .15, Shadow = false })
		b:Bar("Head", "Horn", V3(s * .9, 13.2, -1.4), V3(s * 1.45, 13.7, .9), .5, .5, E, MAT.Neon, { T = .1, Shadow = false })
		b:Bar("Head", "Horn", V3(s * 1.45, 13.7, .9), V3(s * 1.35, 13.2, 2.4), .3, .3, H, MAT.Neon, { T = .1, Shadow = false })
		b:Fang("Head", "Fang", V3(s * .5, 11.15, -6.0), .8, .4, .25, true, COL.BoneLight)
	end
	b:Ell("Jaw", "SpiritJaw", V3(1.4, .55, 3.6), CF(0, 10.75, -5.0), SK, MAT.Neon, { T = .25, Shadow = false })
	b:Fang("Jaw", "Fang", V3(-.42, 10.95, -6.3), .6, .3, .2, false, COL.BoneLight)
	b:Fang("Jaw", "Fang", V3(.42, 10.95, -6.3), .6, .3, .2, false, COL.BoneLight)
	-- long spectral arms reaching forward, three claws each
	for _, s in ipairs({ -1, 1 }) do
		local arm = s < 0 and "ArmL" or "ArmR"
		local sh, el, wr = V3(s * 2.4, 9.8, -.6), V3(s * 3.4, 8.2, -3.4), V3(s * 3.0, 7.0, -6.0)
		b:Bar(arm, "Arm", sh, el, .6, .6, G, MAT.Neon, { T = .3, Shadow = false })
		b:Bar(arm, "Arm", el, wr, .5, .5, G, MAT.Neon, { T = .35, Shadow = false })
		for i = -1, 1 do
			b:Bar(arm, "Claw", wr, wr + V3(i * .45, -1.2, -1.5), .18, .2, H, MAT.Neon, { Shadow = false })
		end
	end
	b:Attach("Body", "Core", V3(0, 7.8, -.4))
	b.Model:SetAttribute("Parts", b.Count)
	return b.Model
end

function Finale.SpiritPose(t: number, k: number?): { [string]: CFrame }
	local kk = math.clamp(k or 1, 0, 1)
	return {
		Body = ANG(math.sin(t * 2.2) * .06, math.sin(t * .9) * .15, math.sin(t * 1.7) * .05),
		Head = ANG(-.2 * kk + math.sin(t * 3) * .08, math.sin(t * 1.3) * .2, 0),
		Jaw = ANG(-.5 * kk - math.max(0, math.sin(t * 6)) * .3, 0, 0),
		ArmL = ANG(.25 * kk + math.sin(t * 4) * .15, 0, -.15 * kk),
		ArmR = ANG(.25 * kk + math.sin(t * 4 + 1) * .15, 0, .15 * kk),
		Tail = ANG(math.sin(t * 5) * .25, math.sin(t * 3.4) * .35, 0),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- BURIED WEAK POINT (choir phase: a mound torn open on a gold soul heart; gold = weak point, as on the Gravekeeper)
---------------------------------------------------------------------------------------------------------------------
function Finale.WeakMound(seed: number?): Model
	local rng = newRng(seed or 9)
	local m = Instance.new("Model")
	m.Name = "BuriedWeak"
	groundRoot(m)
	-- a heaped grave mound: base, a lopsided crown, clods tumbling off it
	part(m, "Mound", "Part", V3(8.4, 3.6, 7.8), CF(0, .4, 0) * ANG(0, rng:NextNumber(0, 6), 0), COL.Dirt, MAT.Ground, { Mesh = true, Shadow = true })
	part(m, "MoundCrown", "Part", V3(5.6, 3.4, 5.0), CF(rng:NextNumber(-.4, .4), 1.6, rng:NextNumber(-.4, .4)) * ANG(.1, rng:NextNumber(0, 6), .08),
		COL.Dirt:Lerp(COL.DirtDark, .3), MAT.Ground, { Mesh = true, Shadow = true })
	for i = 1, 7 do
		local a = i / 7 * 2 * PI + rng:NextNumber(-.2, .2)
		local d = rng:NextNumber(.9, 1.5)
		local r = rng:NextNumber(1.8, 3.2)
		part(m, "Clod", "Part", V3(d * 1.4, d, d * 1.2), CF(math.cos(a) * r, 2.6 - r * .45, math.sin(a) * r) * ANG(rng:NextNumber(0, 2), a, 0),
			i % 2 == 0 and COL.DirtDark or COL.Dirt, MAT.Ground, { Mesh = true })
	end
	-- the torn-open top (earth flaps bent back) + the gold heart half buried in it
	part(m, "Hole", "Part", V3(2.9, .7, 2.7), CF(0, 3.05, 0), COL.Void, MAT.SmoothPlastic, { Mesh = true })
	for i = 1, 4 do
		local a = i / 4 * 2 * PI + .4
		part(m, "Flap", "WedgePart", V3(1.6, .9, 1.2), look(V3(math.cos(a) * 1.7, 3.1, math.sin(a) * 1.6), V3(math.cos(a) * 4, 2.2, math.sin(a) * 4)),
			COL.DirtDark, MAT.Ground)
	end
	part(m, "WeakCore", "Part", V3(1.7, 1.7, 1.7), CF(0, 3.2, 0), COL.WeakHot, MAT.Neon, { Shape = Enum.PartType.Ball })
	part(m, "WeakGlow", "Part", V3(2.7, 2.7, 2.7), CF(0, 3.3, 0), COL.WeakGold, MAT.Neon, { Shape = Enum.PartType.Ball, T = .62 })
	-- gold cracks running down the mound from the hole
	for i = 1, 6 do
		local a = i / 6 * 2 * PI + rng:NextNumber(-.25, .25)
		local p0 = V3(math.cos(a) * 1.4, 3.0, math.sin(a) * 1.3)
		local p1 = V3(math.cos(a + .1) * 2.8, 1.9, math.sin(a + .1) * 2.6)
		local p2 = V3(math.cos(a + .25) * 4.0, .6, math.sin(a + .25) * 3.7)
		for _, seg in ipairs({ { p0, p1 }, { p1, p2 } }) do
			local cf, len = barCF(seg[1], seg[2])
			part(m, "WeakCrack", "Part", V3(.24, .16, len + .1), cf, i % 2 == 0 and COL.WeakGold or COL.Weak, MAT.Neon)
		end
	end
	-- the rim ring (gold / white, like the boss's weak points)
	for i = 0, 11 do
		local a0, a1 = i / 12 * 2 * PI, (i + 1) / 12 * 2 * PI
		local p0, p1 = V3(math.cos(a0) * 4.4, .12, math.sin(a0) * 4.4), V3(math.cos(a1) * 4.4, .12, math.sin(a1) * 4.4)
		local cf, len = barCF(p0, p1)
		part(m, "WeakRim", "Part", V3(.34, .12, len * .82), cf, i % 3 == 0 and COL.WeakRim or COL.WeakGold, MAT.Neon)
	end
	-- a broken coffin plank + a bone
	part(m, "Plank", "Part", V3(.4, 3.0, 1.2), CF(3.4, 1.0, 1.8) * ANG(.5, .4, .9), RGB(70, 52, 44), MAT.WoodPlanks)
	local bcf, blen = barCF(V3(-3.4, .9, 1.4), V3(-1.8, 1.6, 2.6))
	part(m, "Bone", "Part", V3(.36, .36, blen), bcf, COL.Bone, MAT.SmoothPlastic)
	local top = Instance.new("Attachment")
	top.Name = "Top"
	top.CFrame = CF(0, 3.3, 0)
	top.Parent = m.PrimaryPart
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- THE BLACK MOON (backdrop disc facing -Z; FinaleFX draws it camera-relative, like BloodMoonFX's moon)
---------------------------------------------------------------------------------------------------------------------
function Finale.BlackMoon(radius: number?): Model
	local R = radius or 60
	local m = Instance.new("Model")
	m.Name = "BlackMoon"
	groundRoot(m)
	local face = ANG(0, PI / 2, 0) -- cylinder axis (local X) -> Z
	part(m, "Disc", "Part", V3(1.0, R * 2, R * 2), CF(0, 0, 0) * face, COL.Moon, MAT.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Rim", "Part", V3(.6, R * 2.05, R * 2.05), CF(0, 0, .8) * face, COL.CoronaHot, MAT.Neon, { Shape = Enum.PartType.Cylinder, T = .05 })
	part(m, "Corona", "Part", V3(.6, R * 2.24, R * 2.24), CF(0, 0, 1.8) * face, COL.Corona, MAT.Neon, { Shape = Enum.PartType.Cylinder, T = .45 })
	part(m, "Corona", "Part", V3(.6, R * 2.7, R * 2.7), CF(0, 0, 2.8) * face, COL.Rune, MAT.Neon, { Shape = Enum.PartType.Cylinder, T = .7 })
	part(m, "Corona", "Part", V3(.6, R * 3.5, R * 3.5), CF(0, 0, 3.8) * face, COL.RuneDeep, MAT.Neon, { Shape = Enum.PartType.Cylinder, T = .86 })
	-- flare spikes (alternating long / short)
	for i = 0, 15 do
		local a = i / 16 * 2 * PI + .1
		local len = (i % 2 == 0) and R * 1.05 or R * .6
		local dir = V3(math.cos(a), math.sin(a), 0)
		local p0 = dir * R * 1.02 + V3(0, 0, 1.2)
		local p1 = dir * (R * 1.02 + len) + V3(0, 0, 1.2)
		local cf, l = barCF(p0, p1, V3(0, 0, -1))
		part(m, "Flare", "Part", V3(R * (i % 2 == 0 and .05 or .035), .3, l), cf, COL.Corona, MAT.Neon, { T = (i % 2 == 0) and .45 or .6 })
	end
	-- hidden crack network (victory): three stages spreading from an impact point
	local hub = V3(-R * .18, R * .22, -.7)
	local cracks = {
		{ 1, { 0, 0 }, { .35, -.1 } }, { 1, { 0, 0 }, { -.25, .3 } }, { 1, { 0, 0 }, { .05, -.42 } },
		{ 2, { .35, -.1 }, { .7, .12 } }, { 2, { -.25, .3 }, { -.55, .35 } }, { 2, { .05, -.42 }, { -.1, -.78 } }, { 2, { .35, -.1 }, { .48, -.5 } },
		{ 3, { .7, .12 }, { .95, .3 } }, { 3, { -.55, .35 }, { -.8, .62 } }, { 3, { -.1, -.78 }, { .2, -1.05 } }, { 3, { .48, -.5 }, { .82, -.6 } },
		{ 3, { -.25, .3 }, { -.4, -.1 } },
	}
	for _, c in ipairs(cracks) do
		local p0 = hub + V3(c[2][1] * R, c[2][2] * R, 0)
		local p1 = hub + V3(c[3][1] * R, c[3][2] * R, 0)
		local cf, l = barCF(p0, p1, V3(0, 0, -1))
		local p = part(m, "MoonCrack", "Part", V3(R * (.05 - c[1] * .008), .3, l), cf, COL.CoronaHot, MAT.Neon, { T = 1 })
		p:SetAttribute("Stage", c[1])
	end
	-- shards (fly off when it breaks)
	local rng = newRng(66)
	for i = 1, 10 do
		local a = i / 10 * 2 * PI + rng:NextNumber(-.2, .2)
		local r = R * rng:NextNumber(.25, .8)
		local s = R * rng:NextNumber(.12, .22)
		local p = part(m, "MoonShard", "WedgePart", V3(.6, s, s * 1.2), CF(math.cos(a) * r, math.sin(a) * r, -.9) * ANG(0, 0, a) * ANG(0, PI / 2, 0), COL.Moon,
			MAT.SmoothPlastic, { T = 1 })
		p:SetAttribute("Dir", V3(math.cos(a), math.sin(a), 0))
	end
	m:SetAttribute("Radius", R)
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- THE JOURNAL REPLAY'S STAGE: the pit as a memory (dark stone floor, terrace, rim, gravestones, four chain anchors) inside
-- a black box, so the replay looks the same wherever the player opens the journal. Origin = the pit floor centre.
---------------------------------------------------------------------------------------------------------------------
function Finale.ReplayStage(): Model
	local m = Instance.new("Model")
	m.Name = "FinaleMemory"
	groundRoot(m)
	local rng = newRng(5150)
	part(m, "Floor", "Part", V3(1.2, 50, 50), CF(0, -.6, 0) * ANG(0, 0, PI / 2), COL.StoneDark, MAT.Slate, { Shape = Enum.PartType.Cylinder, Shadow = true })
	-- floor cracks (violet)
	for i = 1, 7 do
		local a = i / 7 * 2 * PI + rng:NextNumber(-.3, .3)
		local p0 = V3(math.cos(a) * 3, .02, math.sin(a) * 3)
		local p1 = V3(math.cos(a + .2) * rng:NextNumber(12, 22), .02, math.sin(a + .2) * rng:NextNumber(12, 22))
		local cf, len = barCF(p0, p1)
		part(m, "FloorCrack", "Part", V3(.3, .06, len), cf, COL.RuneDeep, MAT.Neon)
	end
	-- the terrace ring (top +4) and the rim wall (top +8.2)
	for i = 0, 15 do
		local a = (i + .5) / 16 * 2 * PI
		local o = V3(math.cos(a), 0, math.sin(a))
		part(m, "Terrace", "Part", V3(2 * PI * 29 / 16 * 1.05, 4.6, 6), CFrame.fromMatrix(o * 28 + V3(0, 1.7, 0), V3(-math.sin(a), 0, math.cos(a)), V3(0, 1, 0)),
			COL.Stone, MAT.Slate, { Shadow = true })
	end
	for i = 0, 23 do
		local a = (i + .5) / 24 * 2 * PI
		local o = V3(math.cos(a), 0, math.sin(a))
		part(m, "Rim", "Part", V3(2 * PI * 33 / 24 * 1.05, 9, 4), CFrame.fromMatrix(o * 33 + V3(0, 3.9, 0), V3(-math.sin(a), 0, math.cos(a)), V3(0, 1, 0)),
			i % 2 == 0 and COL.StoneDark or COL.Stone, MAT.Slate, { Shadow = true })
	end
	-- gravestones leaning on the rim
	for i = 1, 8 do
		local a = i / 8 * 2 * PI + .3
		local o = V3(math.cos(a), 0, math.sin(a))
		local h = rng:NextNumber(3.2, 4.8)
		part(m, "Grave", "Part", V3(2.6, h, .7), look(o * 33.5 + V3(0, 8.4 + h / 2, 0), V3(0, 8.4 + h / 2, 0)) * ANG(rng:NextNumber(-.2, .2), 0,
			rng:NextNumber(-.15, .15)), COL.StoneLight, MAT.Slate)
	end
	-- the four chain anchors (N, E, S, W) on the rim
	for i, key in ipairs(Finale.Keys) do
		local a = (i - 1) * PI / 2
		local o = outward(a)
		local post = Finale.ChainAnchor(12)
		post.Name = "Anchor_" .. key
		post:PivotTo(look(o * 36 + V3(0, 8.2, 0), V3(0, 8.2, 0)))
		post.Parent = m
	end
	-- the black box (inward faces dark, a far violet glow low on the walls)
	local S = 240
	for _, w in ipairs({ { V3(0, 0, -S), V3(2 * S, 2 * S, 2) }, { V3(0, 0, S), V3(2 * S, 2 * S, 2) }, { V3(-S, 0, 0), V3(2, 2 * S, 2 * S) },
		{ V3(S, 0, 0), V3(2, 2 * S, 2 * S) }, { V3(0, S, 0), V3(2 * S, 2, 2 * S) }, { V3(0, -6, 0), V3(2 * S, 2, 2 * S) } }) do
		part(m, "Void", "Part", w[2], CF(w[1]), COL.Void, MAT.SmoothPlastic)
	end
	for i = 0, 7 do
		local a = i / 8 * 2 * PI
		part(m, "VoidGlow", "Part", V3(80, 6, 1), look(V3(math.cos(a), 0, math.sin(a)) * (S - 3) + V3(0, 10, 0), V3(0, 10, 0)), COL.RuneDim,
			MAT.Neon, { T = .55 })
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- default placement (late joiners, the journal replay; the server's payloads always win)
---------------------------------------------------------------------------------------------------------------------
function Finale.Defaults(L: any, cfg: any): { [string]: any }
	local P = L.Pit.Center
	local floor = L.Pit.FloorY
	local height = (cfg and cfg.Bell and cfg.Bell.Height) or 28
	local out = {}
	out.BellCF = CF(P.X, floor + height, P.Z)
	-- the four rim anchors: the tops of the N / E / S / W ramps (BossFinale.Anchors), the hittable link a quarter of the
	-- way up toward the bell (Bell.ChainAlong)
	out.Chains = {}
	for _, r in ipairs(L.Pit.Ramps) do
		out.Chains[r.Id] = V3(r.Top.X, r.Top.Y + 1, r.Top.Z)
	end
	out.ChainAlong = (cfg and cfg.Bell and cfg.Bell.ChainAlong) or .25
	-- six candles on the terrace ring, off the ramps (two on the east and west sides, one each north and south)
	out.Candles = {}
	for i, o in ipairs({ { 27, -11 }, { 27, 11 }, { 11, 27 }, { -27, 11 }, { -27, -11 }, { -11, -27 } }) do
		local x, z = P.X + o[1], P.Z + o[2]
		out.Candles[i] = V3(x, Boss.Surface(L, x, z), z)
	end
	-- THE LAST BARK rises behind the south rim, facing the pit; the Black Moon behind it
	local hound = (cfg and cfg.Hound) or {}
	-- config offsets may be Vector3s or {x, y, z} tables
	local function vec(v: any, default: Vector3): Vector3
		if typeof(v) == "Vector3" then
			return v
		elseif type(v) == "table" then
			return V3(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
		end
		return default
	end
	local pos = P + vec(hound.HoundOffset, V3(0, 0, 50))
	out.HoundCF = look(pos, V3(P.X, pos.Y, P.Z))
	out.MoonDir = vec(hound.MoonDir, V3(0, .35, 1)).Unit
	out.JawPos = P + vec(hound.JawOffset, V3(0, 10, 18))
	return out
end

return Finale
