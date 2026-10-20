-- THE DEAD YARD · the broken lab annex (ServerStorage.HalloweenBuild.BrokenLab, WP2). Build-time only.
-- Model `BrokenLab` under ctx.Root, footprint x 184..208, z 604..634, open toward -X (the ore field in front of it).
-- A ruined mutation-lab annex echoing the nuclear tower lab next door: cracked concrete slab with hazard edging, broken
-- back/side walls with rebar, the tower's radiation-paw emblem, steel I-beam frame (one beam crashed down), torn
-- corrugated roof, the cracked CONTAINMENT TUBE (glass staves, toxic fluid, a floating specimen skull) leaking a
-- toxic-green spill that flows -X out over the ore field (flat Neon/Glass puddles, not solid), toppled tanks, waste
-- barrels, a smashed console, a broken glass partition, a half-collapsed catwalk, a lab bench with beakers, a second
-- specimen tube, the hanging ANNEX sign, hanging cables, an empty cryo-pod with glowing paw prints walking
-- away, and a flickering green warning beacon (HwLantern = "Green" + PointLight). Polish P1b: the collapsed mini
-- COOLING TOWER in the back corner (an echo of the nuclear lab's tower: hyperbolic concrete rings, red/white crown
-- broken open, glowing toxic core with a PointLight, neon crack, radiation-paw emblem, hazard band), a broken cooling
-- pipe from it to the containment tube, a stepped hazard-striped machine base / clamps / bubbles for the tube, X-bracing
-- with riveted gusset plates, corrugated roof ribs, jagged wall tops, flickering amber hazard lamps (HwLantern Orange)
-- and a half-toppled FLOODLIGHT MAST whose SpotLight sweeps the ore field (key light). Every Layout.OrePoints position
-- stays clear (no solid / tall part within 4.5 studs). Markers: FogPoint, CrowPerch, BatRoost.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local S = Y.Solid

local CONC = C(150, 150, 158)
local CONC_D = C(112, 112, 122)
local STEEL = C(70, 74, 84)
local HAZ_Y = C(246, 196, 40)
local HAZ_K = C(28, 26, 32)
local TOXIC = Y.GLOW.Green
local TOXIC_D = C(70, 170, 60)
local GLASS = C(170, 230, 220)

-- I-beam between two points (web + two flanges), flanges across `side` (a unit vector perpendicular to the beam)
local function ibeam(m, a, b, size, solid)
	local cf = K.Look((a + b) / 2, b)
	local len = (b - a).Magnitude
	K.Part(m, "IBeamWeb", V3(size * .22, size, len), cf, STEEL, M.CorrodedMetal, solid and S() or nil)
	K.Part(m, "IBeamFlange", V3(size * .8, size * .14, len), cf * CF(0, size * .45, 0), STEEL:Lerp(P.Rust, .3), M.CorrodedMetal)
	K.Part(m, "IBeamFlange", V3(size * .8, size * .14, len), cf * CF(0, -size * .45, 0), STEEL:Lerp(P.Rust, .3), M.CorrodedMetal)
end

local function column(m, base, h)
	local web = K.Part(m, "ColumnWeb", V3(.3, h, 1.1), base * CF(0, h / 2, 0), STEEL, M.CorrodedMetal, S())
	K.Part(m, "ColumnFlange", V3(1.1, h, .18), base * CF(0, h / 2, .55), STEEL:Lerp(P.Rust, .25), M.CorrodedMetal)
	K.Part(m, "ColumnFlange", V3(1.1, h, .18), base * CF(0, h / 2, -.55), STEEL:Lerp(P.Rust, .25), M.CorrodedMetal)
	K.Part(m, "ColumnFoot", V3(1.6, .4, 1.6), base * CF(0, .2, 0), CONC_D, M.Concrete)
	return web
end

local function barrel(m, cf, color, toppled, rng)
	local b = cf
	if toppled then
		b = cf * CF(0, .8, 0) * ANG(0, 0, PI / 2) * CF(0, -.8, 0)
	end
	K.CylY(m, "WasteBarrel", 2.2, 1.6, b * CF(0, 1.1, 0), color, M.CorrodedMetal, S())
	K.CylY(m, "BarrelHoop", .14, 1.66, b * CF(0, .55, 0), color:Lerp(P.Ink, .35), M.CorrodedMetal)
	K.CylY(m, "BarrelHoop", .14, 1.66, b * CF(0, 1.65, 0), color:Lerp(P.Ink, .35), M.CorrodedMetal)
	K.Part(m, "BarrelLabel", V3(.7, .7, .06), b * CF(0, 1.1, -.8), HAZ_Y, M.SmoothPlastic)
	if toppled then
		K.Ellipsoid(m, "BarrelLeak", V3(rng:NextNumber(2.4, 3.4), .05, rng:NextNumber(1.6, 2.4)), cf * CF(-1.6, .04, .3), TOXIC_D, M.Neon)
	else
		K.CylY(m, "BarrelLid", .12, 1.5, b * CF(0, 2.26, 0), color:Lerp(P.Ink, .2), M.CorrodedMetal)
	end
end

return {
	Build = function(ctx)
		local L = ctx.Layout
		local B = L.BrokenLab
		local rng = Y.Rng(6101)
		local clear = Y.Keepout(L)
		local m = K.Model(ctx.Root, "BrokenLab")
		local cx, cz = (B.X0 + B.X1) / 2, (B.Z0 + B.Z1) / 2
		local O = CF(cx, L.FloorY, cz) -- local x -12 = open front (world 184), +12 = back (world 208)
		local function at(x, y, z)
			return O * CF(x, y, z)
		end
		local fl = .45 -- slab top (local)

		-- 1. cracked slab + hazard edging ------------------------------------------------------------------------
		for i, t in ipairs({ { -6, -7.5, .004 }, { 6, -7.5, -.003 }, { -6, 7.5, -.002 }, { 6, 7.5, .006 } }) do
			K.Part(m, "LabSlab", V3(11.8, .5, 14.8), at(t[1], fl - .25 + (i == 4 and .1 or 0), t[2]) * ANG(t[3], 0, i == 4 and .006 or 0),
				CONC_D:Lerp(CONC, i / 4), M.Concrete, S())
		end
		K.Part(m, "HazardEdge", V3(1, .08, 29.6), at(-11.5, fl + .02, 0), HAZ_Y, M.SmoothPlastic)
		for k = 0, 9 do
			K.Part(m, "HazardStripe", V3(.45, .1, 1.5), at(-11.5, fl + .04, -13.5 + k * 3) * ANG(0, .7, 0), HAZ_K, M.SmoothPlastic)
		end
		for _, c in ipairs({ { -4, -2, .5 }, { 3, 6, -.4 }, { 8, -10, .9 } }) do
			K.Part(m, "SlabCrack", V3(.14, .04, 5), at(c[1], fl + .02, c[2]) * ANG(0, c[3], 0), C(30, 30, 36), M.SmoothPlastic)
		end

		-- 2. back wall (broken top, rebar) with the radiation-paw emblem ----------------------------------------------
		local heights = { 11.5, 13, 12, 8.5, 12, 6.5 }
		for k, h in ipairs(heights) do
			local z = -15 + (k - .5) * 5
			K.Part(m, "BackWall", V3(1.2, h, 5.02), at(11.4, fl + h / 2, z), CONC:Lerp(CONC_D, (k % 2) * .4), M.Concrete, S())
			for r = 1, 2 do
				K.Rod(m, "Rebar", (at(11.4, fl + h - .2, z - 1.5 + r * 1.2)).Position, (at(11.2 + rng:NextNumber(-.4, .4), fl + h + rng:NextNumber(.8, 1.6), z - 1.6 + r * 1.3)).Position, .12, P.Rust, M.CorrodedMetal)
			end
			local jh = rng:NextNumber(.7, 1.5)
			K.Wedge(m, "WallJag", V3(1.2, jh, 1.6), at(11.4, fl + h + jh / 2, z + (k % 2 == 0 and 1 or -1) * rng:NextNumber(.9, 1.5)) * ANG(0, k % 2 == 0 and 0 or PI, 0),
				CONC:Lerp(CONC_D, (k % 2) * .4), M.Concrete)
			if k == 2 or k == 5 then
				local cap = K.Part(m, "WallTopMarker", V3(.2, .2, .2), at(11.4, fl + h + .1, z), CONC, nil, { Transparency = 1 })
				K.Attach(cap, "CrowPerch", CF(0, .2, 0))
			end
		end
		local em = at(10.7, fl + 8, -6.2) * ANG(0, PI / 2, 0) -- faces -X
		K.CylZ(m, "EmblemRing", .2, 7.2, em * CF(0, 0, .05), HAZ_K, M.SmoothPlastic)
		K.CylZ(m, "EmblemDisc", .22, 6.6, em * CF(0, 0, -.02), HAZ_Y, M.SmoothPlastic)
		for k = 0, 2 do
			local a = k * 2 * PI / 3 + PI / 2
			K.Part(m, "EmblemBlade", V3(1.9, 2.3, .1), em * CF(math.cos(a) * 1.85, math.sin(a) * 1.85, -.15) * ANG(0, 0, a - PI / 2), HAZ_K, M.SmoothPlastic)
		end
		K.CylZ(m, "EmblemCore", .12, 1.9, em * CF(0, 0, -.2), C(235, 235, 225), M.SmoothPlastic)
		K.Ball(m, "EmblemPaw", .7, em * CF(0, -.15, -.26), TOXIC, M.Neon)
		for t = -1, 1 do
			K.Ball(m, "EmblemToe", .32, em * CF(t * .38, .38 + (t == 0 and .08 or 0), -.26), TOXIC, M.Neon)
		end
		K.Part(m, "EmblemCrack", V3(.16, 4.2, .06), em * CF(1.4, .3, -.3) * ANG(0, 0, .35), C(30, 26, 30), M.SmoothPlastic)
		-- pipes along the back wall, one burst and dripping
		for _, py in ipairs({ 3.2, 4.4 }) do
			K.CylZ(m, "WallPipe", 22, .55, at(10.3, fl + py, -3), C(96, 104, 98), M.CorrodedMetal)
		end
		for _, pz in ipairs({ -12, -4, 4 }) do
			K.Part(m, "PipeBracket", V3(.6, 1.8, .3), at(10.6, fl + 3.8, pz), STEEL, M.CorrodedMetal)
		end
		K.Part(m, "PipeDrip", V3(.25, 2.6, .25), at(10.3, fl + 1.5, 5.4), TOXIC, M.Neon)
		K.Ellipsoid(m, "DripPool", V3(2.2, .06, 1.6), at(9.9, fl + .03, 5.4), TOXIC_D, M.Neon)

		-- 3. side walls (stepping down toward the open front) + broken chunks ---------------------------------------
		for _, s in ipairs({ -1, 1 }) do
			for k, seg in ipairs({ { 9.2, 4.4, 10.5 }, { 4.6, 4.8, 7 }, { .4, 3.6, 3.6 } }) do
				K.Part(m, "SideWall", V3(seg[2], seg[3], 1.1), at(seg[1], fl + seg[3] / 2, s * 14.4), CONC:Lerp(CONC_D, k * .25), M.Concrete, S())
			end
			for k = 1, 3 do
				local px = rng:NextNumber(-3.5, 1)
				K.Part(m, "Rubble", V3(rng:NextNumber(.9, 1.8), rng:NextNumber(.6, 1.2), rng:NextNumber(.9, 1.6)),
					at(px, fl + .4, s * (13 - rng:NextNumber(0, 1.6))) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3)), CONC_D, M.Concrete)
			end
		end
		local s1 = K.Part(m, "SignPlate", V3(4.4, 1.6, .12), at(5, fl + 5, -13.8) * ANG(0, 0, -.04), HAZ_Y, M.SmoothPlastic)
		K.Sign(s1, N.Back, "DANGER · MUTAGEN", HAZ_K, { PixelsPerStud = 24, Stroke = false, H = .7, W = .9 })

		-- 4. steel frame: front columns, roof beams, a beam crashed to the floor ----------------------------------------
		local cols = {}
		for _, c in ipairs({ { -11, -13.4, 12.6 }, { -11, 0, 12.2 }, { -11, 13.4, 9.5 }, { 0, -13.4, 12.6 }, { 0, 13.4, 12.6 } }) do
			table.insert(cols, column(m, at(c[1], fl, c[2]), c[3]))
		end
		ibeam(m, (at(-11, fl + 12.6, -13.8)).Position, (at(-11, fl + 12.2, 1.4)).Position, 1.1)
		ibeam(m, (at(-11, fl + 12.5, -13.4)).Position, (at(11, fl + 12.5, -13.4)).Position, 1.1)
		ibeam(m, (at(0, fl + 12.6, 13.4)).Position, (at(11, fl + 12.6, 13.4)).Position, 1.1)
		ibeam(m, (at(0, fl + 12.4, 0)).Position, (at(11, fl + 12.4, 0)).Position, .9)
		ibeam(m, (at(-11, fl + 9.6, 13.4)).Position, (at(-5.6, fl + .6, 6.5)).Position, 1.1, true) -- crashed beam
		ibeam(m, (at(-11, fl + 12.2, 1.4)).Position, (at(-10.2, fl + 8.4, 4.4)).Position, .9)        -- dangling end
		-- torn corrugated roof over the back half (one sheet hanging down)
		for k, t in ipairs({ { -10, .02 }, { -3.4, -.03 }, { 3.2, .05 } }) do
			local sheet = K.Part(m, "RoofSheet", V3(11.6, .16, 6.4), at(5.6, fl + 13.15, t[1]) * ANG(t[2], 0, .02), C(128, 130, 138):Lerp(P.Rust, k * .2), M.CorrodedMetal)
			for r = -2, 2 do -- corrugation ribs
				K.Part(m, "RoofRib", V3(11.4, .1, .16), sheet.CFrame * CF(0, .12, r * 1.2), C(146, 148, 156):Lerp(P.Rust, k * .16), M.CorrodedMetal)
			end
		end
		K.Part(m, "RoofSheet", V3(6.2, .16, 6), at(3.4, fl + 9.4, -10.2) * ANG(-.15, 0, 1.05), C(120, 120, 128):Lerp(P.Rust, .5), M.CorrodedMetal)
		K.Attach(K.Part(m, "BatHang", V3(.2, .2, .2), at(6, fl + 12.6, -4), P.Ink, nil, { Transparency = 1 }), "BatRoost")
		-- hanging cables with sparking ends
		for k, c in ipairs({ { -5, -6, 6.5 }, { 2, 4, 5.5 }, { 6, -9, 7.5 }, { -9, -9, 4.5 } }) do
			local top = at(c[1], fl + 12.4, c[2])
			local mid = at(c[1] + .6, fl + 12.4 - c[3] * .6, c[2] + .4)
			local bot = at(c[1] + .2, fl + 12.4 - c[3], c[2] + .9)
			K.Rod(m, "Cable", top.Position, mid.Position, .16, C(26, 26, 30), M.Fabric)
			K.Rod(m, "Cable", mid.Position, bot.Position, .16, C(26, 26, 30), M.Fabric)
			if k % 2 == 1 then
				K.Ball(m, "CableSpark", .35, bot, C(255, 240, 150), M.Neon)
			end
		end
		-- the flickering warning beacon on the front column
		local bc = at(-11, fl + 12.6 + .55, -13.4)
		K.CylY(m, "BeaconBase", .5, 1.2, bc * CF(0, .25, 0), STEEL, M.Metal)
		local glass = K.Ball(m, "BeaconGlass", 1.1, bc * CF(0, .95, 0), TOXIC, M.Neon, { Attrs = { HwLantern = "Green" } })
		K.Light(glass, TOXIC, 20, 1.2)
		K.CylY(m, "BeaconCage", .12, 1.3, bc * CF(0, 1.2, 0), STEEL, M.Metal)
		K.Attach(glass, "CrowPerch", CF(0, .7, 0))

		-- 5. the cracked containment tube (hero) -----------------------------------------------------------------------
		local tb = at(3, fl, 0)
		K.CylY(m, "TubePedestal", 1.2, 6.4, tb * CF(0, .6, 0), STEEL, M.DiamondPlate, S())
		K.CylY(m, "TubeRing", .16, 6.6, tb * CF(0, 1.15, 0), TOXIC, M.Neon)
		K.CylY(m, "TubeBottomCap", .9, 5, tb * CF(0, 1.65, 0), C(110, 116, 126), M.Metal)
		local th = 7.6
		local staves = 12
		for k = 0, staves - 1 do
			local a = k / staves * PI * 2
			local broken = (k == 6 or k == 7 or k == 5)
			local h = broken and (k == 6 and 1.4 or 3.2) or th
			local p = tb * CF(math.cos(a) * 2.15, 2.1 + h / 2, math.sin(a) * 2.15) * ANG(0, -a + PI / 2, 0)
			K.Part(m, "TubeGlass", V3(1.15, h, .14), p, GLASS, M.Glass, { Transparency = .55, Solid = not broken })
		end
		K.CylY(m, "TubeFluid", 2.8, 3.9, tb * CF(0, 2.1 + 1.4, 0), TOXIC, M.Neon)
		local fluidLight = K.Part(m, "TubeCore", V3(.3, .3, .3), tb * CF(0, 4, 0), TOXIC, M.Neon, { Transparency = 1 })
		K.Light(fluidLight, TOXIC, 18, 1)
		-- the specimen: a dog skull and spine floating in the tube
		Y.Skull(m, tb * CF(0, 6.1, 0) * ANG(.2, -PI / 2, 0), 1.05, TOXIC, P.Bone)
		for k = 1, 3 do
			K.Part(m, "SpecimenSpine", V3(.4, .32, .4), tb * CF(.55 * k, 5.6 - k * .35, 0) * ANG(0, 0, .4), P.BoneDark, M.SmoothPlastic)
		end
		K.CylY(m, "TubeTopCap", 1, 5, tb * CF(0, 2.1 + th + .5, 0), C(110, 116, 126), M.Metal)
		K.CylY(m, "TubeDome", .7, 3.6, tb * CF(0, 2.1 + th + 1.35, 0), STEEL, M.Metal)
		for k = 0, 3 do
			local a = k / 4 * PI * 2 + PI / 4
			K.Rod(m, "TubePipe", (tb * CF(math.cos(a) * 1.6, 2.1 + th + 1, math.sin(a) * 1.6)).Position,
				(tb * CF(math.cos(a) * 2.8, fl + 12.2, math.sin(a) * 2.8)).Position, .4, C(96, 104, 98), M.CorrodedMetal)
		end
		for _, a in ipairs({ PI * .85, PI * 1.15 }) do
			local d = tb * CF(math.cos(a) * 2.6, 1.5, math.sin(a) * 2.6) * ANG(0, -a - PI / 2, 0)
			K.Part(m, "TubeGauge", V3(.9, .9, .25), d, C(60, 64, 72), M.Metal)
			K.CylZ(m, "TubeDial", .06, .65, d * CF(0, 0, -.14), TOXIC, M.Neon)
		end
		-- glass shards in front of the broken staves
		for k = 1, 6 do
			K.Wedge(m, "GlassShard", V3(rng:NextNumber(.4, .9), .06, rng:NextNumber(.6, 1.2)), tb * CF(-3 - rng:NextNumber(0, 2.6), .05, rng:NextNumber(-2, 2)) * ANG(0, rng:NextNumber(0, PI * 2), 0),
				GLASS, M.Glass, { Transparency = .45 })
		end

		-- 6. the toxic spill: from the tube out over the ore field (-X), flat and not solid ----------------------------
		local spill = {
			{ 0, fl, 0, 4.6, 3.6 }, { -3.6, fl, .8, 4.4, 3 }, { -7.2, fl, -.4, 4, 3.4 }, { -10.4, fl, .6, 3.4, 2.6 },
			{ -13.6, 0, -.6, 4.4, 3.4 }, { -17.4, 0, .9, 3.8, 2.8 }, { -20.6, 0, -.3, 3, 2.2 }, { -16, 0, -3.6, 2.4, 1.8 },
		}
		for k, s in ipairs(spill) do
			local wp = at(s[1], s[2], s[3]).Position
			if clear(wp, 4.6 + s[4] / 2) then
				local cf = CF(wp + V3(0, .035, 0)) * ANG(0, rng:NextNumber(-.4, .4), 0)
				K.Ellipsoid(m, "ToxicSpill", V3(s[4], .05, s[5]), cf, k <= 4 and TOXIC or TOXIC_D, M.Neon)
				K.Ellipsoid(m, "ToxicSheen", V3(s[4] * .8, .06, s[5] * .75), cf * CF(0, .02, 0), C(190, 255, 170), M.Glass, { Transparency = .5, Reflectance = .3 })
			end
		end
		Y.Marker(m, "FogPoint", (at(-15, .4, 0)).Position)
		Y.Marker(m, "FogPoint", (at(-4, fl + .4, -8)).Position)
		Y.Marker(m, "FogPoint", (at(5, fl + .4, 10)).Position)

		-- 7. toppled tanks, barrels, crates --------------------------------------------------------------------------
		local function tank(cf, len, d, color)
			K.CylX(m, "Tank", len, d, cf, color, M.CorrodedMetal, S())
			for _, x in ipairs({ -len * .32, 0, len * .32 }) do
				K.CylX(m, "TankHoop", .25, d + .12, cf * CF(x, 0, 0), color:Lerp(P.Ink, .35), M.CorrodedMetal)
			end
			K.Ball(m, "TankEnd", d * .98, cf * CF(len / 2, 0, 0), color:Lerp(P.Ink, .1), M.CorrodedMetal)
			K.Ball(m, "TankEnd", d * .98, cf * CF(-len / 2, 0, 0), color:Lerp(P.Ink, .1), M.CorrodedMetal)
			K.Part(m, "TankLabel", V3(1.4, 1.4, .06), cf * CF(len * .15, 0, -d / 2 - .02), HAZ_Y, M.SmoothPlastic)
		end
		tank(at(6.2, fl + 1.8, -9.4) * ANG(0, .35, 0), 6.4, 3.6, C(170, 176, 182))
		K.CylY(m, "TankValve", .25, 1.4, at(4.6, fl + 3.9, -10) * ANG(PI / 2, 0, 0), P.Blood, M.Metal)
		barrel(m, at(-6.5, fl, 9.5), C(90, 150, 70), false, rng)
		barrel(m, at(-4.6, fl, 11.4), C(230, 180, 40), false, rng)
		barrel(m, at(-8.3, fl, -9), C(90, 150, 70), true, rng)
		barrel(m, at(9.2, fl, -2.6) * ANG(0, 1.2, 0), C(230, 180, 40), true, rng)
		barrel(m, at(-1.5, fl, -11.6), C(170, 60, 60), false, rng)
		for k, c in ipairs({ { 8.6, -13 }, { 6.6, -13.1 }, { 7.7, -13, 2.1 } }) do
			local cr = at(c[1], fl + (c[3] or 0), c[2]) * ANG(0, k * .3, 0)
			K.Part(m, "Crate", V3(2, 2, 2), cr * CF(0, 1, 0), C(130, 104, 70), M.WoodPlanks, S())
			K.Part(m, "CrateLabel", V3(1, 1, .06), cr * CF(0, 1, -1.02), HAZ_Y, M.SmoothPlastic)
		end

		-- 8. smashed console + specimen shelf ------------------------------------------------------------------------
		local con = at(7.8, fl, -3.25) * ANG(0, PI / 2, 0)
		K.Part(m, "ConsoleDesk", V3(5.6, 1.5, 2), con * CF(0, .75, 0), C(80, 86, 96), M.Metal, S())
		K.Wedge(m, "ConsoleTop", V3(5.6, .6, 2), con * CF(0, 1.8, 0) * ANG(0, PI, 0), C(64, 70, 80), M.Metal)
		for k, x in ipairs({ -1.8, 0, 1.8 }) do
			local mon = con * CF(x, 2.9, .4) * ANG(0, 0, k == 3 and .25 or 0)
			K.Part(m, "Monitor", V3(1.7, 1.3, .5), mon, C(40, 44, 50), M.Metal)
			K.Part(m, "MonitorScreen", V3(1.4, 1, .05), mon * CF(0, 0, -.27), k == 2 and C(20, 30, 22) or TOXIC_D, M.Neon)
		end
		K.Part(m, "MonitorCrack", V3(.06, 1.1, .06), con * CF(0, 2.9, .1) * ANG(0, 0, .5), TOXIC, M.Neon)
		K.Part(m, "Keyboard", V3(2.2, .12, .7), con * CF(-.4, 2.15, -.4) * ANG(.25, 0, 0), C(30, 32, 38), M.SmoothPlastic)
		local chair = at(5.9, fl, -4.6) * ANG(.2, .8, PI / 2 - .1)
		K.Part(m, "ChairSeat", V3(1.4, .25, 1.4), chair * CF(0, .8, 0), C(40, 40, 46), M.Fabric)
		K.Part(m, "ChairBack", V3(1.4, 1.4, .2), chair * CF(0, 1.5, .6), C(40, 40, 46), M.Fabric)
		K.CylY(m, "ChairPole", .8, .2, chair * CF(0, .3, 0), STEEL, M.Metal)
		local sh = at(9.2, fl, 3.4) * ANG(0, PI / 2, 0)
		K.Part(m, "ShelfFrame", V3(5, 5.6, .2), sh * CF(0, 2.8, .7), STEEL, M.Metal)
		for _, yy in ipairs({ 1.4, 3.2, 5 }) do
			K.Part(m, "Shelf", V3(5, .16, 1.4), sh * CF(0, yy, 0), STEEL:Lerp(P.Rust, .3), M.CorrodedMetal)
		end
		local jarCols = { TOXIC, Y.GLOW.Purple, C(255, 120, 60), TOXIC }
		for k = 1, 6 do
			local yy = ({ 1.4, 3.2, 5 })[(k - 1) % 3 + 1]
			local x = -1.8 + math.floor((k - 1) / 3) * 2.6 + rng:NextNumber(-.3, .3)
			K.CylY(m, "SpecimenJar", .9, .7, sh * CF(x, yy + .53, 0), GLASS, M.Glass, { Transparency = .4 })
			K.CylY(m, "JarGlow", .6, .5, sh * CF(x, yy + .42, 0), jarCols[(k - 1) % 4 + 1], M.Neon)
		end

		-- 9. broken glass partition --------------------------------------------------------------------------------
		for _, z in ipairs({ -11.8, -8, -4.2 }) do
			K.Part(m, "PartitionPost", V3(.3, 7, .3), at(-3.4, fl + 3.5, z), STEEL, M.Metal, S())
		end
		K.Part(m, "PartitionRail", V3(.3, .3, 7.9), at(-3.4, fl + 7, -8), STEEL, M.Metal)
		K.Part(m, "PartitionGlass", V3(.1, 6.6, 3.6), at(-3.4, fl + 3.4, -9.9), GLASS, M.Glass, { Transparency = .6, Solid = true })
		K.Wedge(m, "PartitionGlass", V3(.1, 3.2, 3.6), at(-3.4, fl + 1.7, -6.1), GLASS, M.Glass, { Transparency = .6 })

		-- 10. catwalk along the back wall (half collapsed), hazard bands on the columns, vent fan, annex sign ----------------
		local cw = 6.4
		K.Part(m, "Catwalk", V3(2.4, .25, 14), at(9.2, fl + cw, -6.5), C(96, 100, 110), M.DiamondPlate, S())
		K.Part(m, "CatwalkBroken", V3(2.4, .25, 6.5), at(8.9, fl + cw - 2.1, 3.6) * ANG(-.62, 0, .08), C(96, 100, 110), M.DiamondPlate)
		K.Part(m, "CatwalkRail", V3(.14, .14, 14), at(8.05, fl + cw + 1.4, -6.5), HAZ_Y, M.Metal)
		for k = 0, 4 do
			local z = -13 + k * 3.25
			K.Part(m, "CatwalkPost", V3(.14, 1.4, .14), at(8.05, fl + cw + .7, z), STEEL, M.Metal)
			if k % 2 == 0 then
				K.Part(m, "CatwalkStrut", V3(.25, cw, .25), at(8.6, fl + cw / 2, z), STEEL, M.CorrodedMetal)
			end
		end
		for i, c in ipairs(cols) do
			local pos = c.CFrame.Position
			for b = 0, 1 do
				K.Part(m, "HazardBand", V3(1.25, .45, 1.25), CF(pos.X, L.FloorY + fl + .65 + b * .9, pos.Z), b == 0 and HAZ_Y or HAZ_K, M.SmoothPlastic)
			end
			local _ = i
		end
		-- the annex name sign hangs by one chain from the front beam
		local sg = at(-11.3, fl + 9.4, -6.5) * ANG(0, -PI / 2, 0) * ANG(0, 0, .42)
		local sign = K.Part(m, "AnnexSign", V3(6.2, 1.4, .16), sg, C(220, 222, 226), M.Metal)
		K.Part(m, "AnnexSignStripe", V3(6.2, .25, .17), sg * CF(0, -.55, 0), HAZ_Y, M.SmoothPlastic)
		K.Sign(sign, N.Front, "MUTATION LAB · ANNEX B", C(40, 44, 52), { PixelsPerStud = 24, Stroke = false, H = .62, W = .92 })
		K.Chain(m, (sg * CF(2.8, .7, 0)).Position, (at(-11, fl + 12, -4.2)).Position, .1, 5)
		-- lab bench with beakers and a second (intact) specimen tube
		local bench = at(-1, fl, 11.8)
		K.Part(m, "LabBench", V3(5.6, .3, 2), bench * CF(0, 2.1, 0), C(200, 204, 210), M.SmoothPlastic, S())
		K.Part(m, "LabBenchBase", V3(5.2, 1.95, 1.8), bench * CF(0, 1, 0), C(110, 116, 126), M.Metal)
		for k, c in ipairs({ { -2, TOXIC }, { -1, Y.GLOW.Purple }, { .2, C(255, 140, 60) }, { 1.6, TOXIC } }) do
			local bk = bench * CF(c[1], 2.25, rng:NextNumber(-.4, .4))
			K.CylY(m, "Beaker", .9, .55, bk * CF(0, .45, 0), GLASS, M.Glass, { Transparency = .45 })
			K.CylY(m, "BeakerLiquid", .45, .45, bk * CF(0, .3, 0), c[2], M.Neon)
			local _ = k
		end
		K.Part(m, "SpilledBeaker", V3(.5, .5, .9), bench * CF(2.3, 2.5, .2) * ANG(PI / 2, 0, .4), GLASS, M.Glass, { Transparency = .45 })
		local t2 = at(9.6, fl, -11.4)
		K.CylY(m, "SmallTubeBase", .8, 2.6, t2 * CF(0, .4, 0), STEEL, M.DiamondPlate, S())
		K.CylY(m, "SmallTube", 4, 2, t2 * CF(0, 2.8, 0), GLASS, M.Glass, { Transparency = .5, Solid = true })
		K.CylY(m, "SmallTubeFluid", 3.4, 1.7, t2 * CF(0, 2.6, 0), Y.GLOW.Purple, M.Neon)
		K.CylY(m, "SmallTubeCap", .6, 2.4, t2 * CF(0, 5.1, 0), C(110, 116, 126), M.Metal)
		K.Ellipsoid(m, "SmallTubeSpecimen", V3(.9, 1.1, .9), t2 * CF(0, 2.9, 0), C(40, 20, 60), M.SmoothPlastic)

		-- 11. the open cryo-pod and glowing paw prints walking out of the lab -------------------------------------------
		local pod = at(-5.4, fl, 4.6) * ANG(0, .4, 0)
		K.Part(m, "PodBase", V3(2.6, .8, 5.2), pod * CF(0, .4, 0), C(90, 96, 108), M.Metal, S())
		K.CylZ(m, "PodShell", 4.8, 2.4, pod * CF(0, 1.35, 0), C(170, 176, 186), M.Metal)
		K.Part(m, "PodInside", V3(1.9, .2, 4.2), pod * CF(0, 2.5, 0), C(20, 40, 26), M.Neon)
		K.Part(m, "PodLid", V3(2.4, .25, 4.6), pod * CF(-1.9, 2.4, 0) * ANG(0, 0, .9), GLASS, M.Glass, { Transparency = .35 })
		K.Part(m, "PodLight", V3(.5, .2, .5), pod * CF(.8, .9, -2.62), C(255, 60, 60), M.Neon)
		local paw = at(-8, fl, 6)
		for k = 0, 6 do
			local pos = paw * CF(-k * 2.1, 0, (k % 2) * 1.1 - .5 - k * .45)
			local wp = pos.Position
			local y = wp.X > 184 and (L.FloorY + fl) or L.FloorY
			local pcf = CF(wp.X, y + .03, wp.Z) * ANG(0, PI / 2, 0)
			K.Ellipsoid(m, "PawPrint", V3(.75, .04, .62), pcf, TOXIC, M.Neon)
			for t = -1, 1 do
				K.Ellipsoid(m, "PawPrintToe", V3(.26, .04, .3), pcf * CF(t * .34, 0, -.52 + math.abs(t) * .1), TOXIC, M.Neon)
			end
		end

		-- 12. the collapsed mini COOLING TOWER in the back corner: stacked hyperbolic concrete rings, a red/white crown
		--     broken open toward the ore field, the glowing toxic core (PointLight: the annex's key light), a neon crack,
		--     the tower's radiation-paw emblem, a hazard band, fallen crown chunks and rebar ---------------------------------
		local ct = at(7.2, fl, 9.6)
		local TH, TW, RBASE, RWAIST, RTOP = 26, 19, 4.4, 2.8, 3.25
		local function radius(h)
			if h < TW then
				return RWAIST + (RBASE - RWAIST) * ((TW - h) / TW) ^ 2
			end
			return RWAIST + (RTOP - RWAIST) * ((h - TW) / (TH - TW)) ^ 2
		end
		local function onWall(a, h, out) -- frame on the tower wall at angle a (outward = -Z), height h
			return ct * ANG(0, -a, 0) * CF(0, h, -radius(h) - (out or 0))
		end
		local CONC_T = C(156, 156, 164)
		K.CylY(m, "CoolingFooting", .6, RBASE * 2 + 1, ct * CF(0, .3, 0), CONC_D, M.Concrete, S())
		for k = 0, 9 do
			local h0 = .6 + k * 1.94
			K.CylY(m, "CoolingRing", 1.94, radius(h0 + .97) * 2, ct * CF(0, h0 + .97, 0), CONC_T:Lerp(CONC_D, (k % 3) * .12 + rng:NextNumber(0, .06)),
				M.Concrete, k <= 1 and S() or nil)
		end
		local hb = 1.9
		K.CylY(m, "CoolingHazardBand", .7, (radius(hb) + .08) * 2, ct * CF(0, hb, 0), HAZ_Y, M.SmoothPlastic)
		for k = 0, 9 do
			K.Part(m, "CoolingHazardStripe", V3(.36, .6, .1), onWall(k / 10 * PI * 2, hb, .1) * ANG(0, 0, .65), HAZ_K, M.SmoothPlastic)
		end
		local crownCols = { C(238, 236, 230), C(198, 52, 52), C(238, 236, 230) }
		for ring = 0, 2 do
			local h0 = 20 + ring * 2
			local r = radius(h0 + 1)
			local cut = ring == 0 and .95 or ring == 1 and .45 or -.3 -- the collapse eats the -X (ore field) side
			for k = 0, 11 do
				local a = k / 12 * PI * 2
				if -math.sin(a) <= cut then
					local hh = ring == 2 and rng:NextNumber(.7, 2) or 2
					K.Part(m, "CoolingCrown", V3(2 * PI * r / 12 * 1.07, hh, .55), ct * ANG(0, -a, 0) * CF(0, h0 + hh / 2, -r + .275), crownCols[ring + 1], M.Concrete)
				end
			end
		end
		local coreR = radius(20) - .5
		local core = K.CylY(m, "CoolingCore", .12, coreR * 2, ct * CF(0, 20.05, 0), TOXIC, M.Neon)
		local cl = K.Light(core, TOXIC, 24, 2.2)
		cl:SetAttribute("HwKeyLight", true)
		K.Ellipsoid(m, "CoolingVapour", V3(coreR * 1.7, 2.6, coreR * 1.7), ct * CF(0, 21.4, 0), C(170, 255, 140), M.Neon, { Transparency = .7 })
		for k = 1, 4 do
			local b = ct * ANG(0, -(k + .5) / 12 * PI * 2, 0)
			local r = radius(24.5)
			K.Rod(m, "CoolingRebar", (b * CF(rng:NextNumber(-.4, .4), 24.6, -r + .25)).Position,
				(b * CF(rng:NextNumber(-.5, .5), 26 + rng:NextNumber(.4, 1.4), -r - rng:NextNumber(.1, .6))).Position, .12, P.Rust, M.CorrodedMetal)
		end
		-- the neon crack running down the ore-field face
		local crack = { { 3.2, -.62 }, { 7, -.42 }, { 10.6, -.6 }, { 14.2, -.38 }, { 18.4, -.55 } }
		for k = 1, #crack - 1 do
			local p0, p1 = crack[k], crack[k + 1]
			K.Bar(m, "CoolingCrack", onWall(3 * PI / 2 + p0[2], p0[1], -.04).Position, onWall(3 * PI / 2 + p1[2], p1[1], -.04).Position, .22, .22, TOXIC, M.Neon)
		end
		K.Ellipsoid(m, "CoolingSeep", V3(3.4, .06, 2.4), onWall(3 * PI / 2 - .5, 0, .9) * CF(0, .035, -.6), TOXIC_D, M.Neon)
		-- radiation-paw emblem (the nuclear tower's badge, small)
		local te = onWall(3 * PI / 2 + .42, 11.2, .08)
		K.CylZ(m, "TowerEmblemRing", .12, 2.6, te * CF(0, 0, .02), HAZ_K, M.SmoothPlastic)
		K.CylZ(m, "TowerEmblem", .14, 2.35, te * CF(0, 0, -.04), HAZ_Y, M.SmoothPlastic)
		for k = 0, 2 do
			local a = k * 2 * PI / 3 + PI / 2
			K.Part(m, "TowerEmblemBlade", V3(.66, .8, .06), te * CF(math.cos(a) * .66, math.sin(a) * .66, -.13) * ANG(0, 0, a - PI / 2), HAZ_K, M.SmoothPlastic)
		end
		K.Ball(m, "TowerEmblemPaw", .32, te * CF(0, -.06, -.16), TOXIC, M.Neon)
		-- crown chunks that fell into the lab
		for k, c in ipairs({ { 2.8, 8.2, 1, .4 }, { 3.4, 12.9, 2, 1.2 }, { 1.4, 6.5, 1, 2.1 }, { 5, 13.7, 2, -.6 } }) do
			K.Part(m, "CrownChunk", V3(1.9, .9, 1.2), at(c[1], fl + .4, c[2]) * ANG(rng:NextNumber(-.25, .25), c[4], rng:NextNumber(-.3, .3)), crownCols[c[3]]:Lerp(CONC_D, .15), M.Concrete)
		end
		-- a broken cooling pipe from the tower to the containment tube, dripping into a toxic pool
		local ps = onWall(-.41, 10.4, -.3).Position
		local pe = (at(3.9, fl + 10.4, 2.2)).Position
		local brk1, brk2 = ps:Lerp(pe, .42), ps:Lerp(pe, .6) - V3(0, .5, 0)
		K.Rod(m, "CoolingPipe", ps, brk1, 1.05, C(96, 104, 98), M.CorrodedMetal)
		K.Rod(m, "CoolingPipe", brk2, pe, 1.05, C(96, 104, 98), M.CorrodedMetal)
		for _, f in ipairs({ { ps, brk1, .06 }, { brk1, ps, .08 }, { brk2, pe, .08 } }) do
			local d = (f[2] - f[1]).Unit
			K.Rod(m, "PipeFlange", f[1] + d * f[3], f[1] + d * (f[3] + .3), 1.4, STEEL, M.Metal)
		end
		K.Part(m, "PipeDrip", V3(.24, brk1.Y - L.FloorY - fl - .4, .24), CF(brk1.X, (brk1.Y + L.FloorY + fl) / 2 - .2, brk1.Z), TOXIC, M.Neon)
		K.Ellipsoid(m, "DripPool", V3(2.6, .06, 2), CF(brk1.X, L.FloorY + fl + .035, brk1.Z), TOXIC, M.Neon)
		-- cables sagging from the crown to the frame
		for _, c in ipairs({ { 4.6, 20, 11.4, .5, 12.4, 13.4 }, { 6.2, 19.4, 6.6, 10.8, 12.2, 1.6 } }) do
			local a, b = at(c[1], fl + c[2], c[3]).Position, at(c[4], fl + c[5], c[6]).Position
			local mid = a:Lerp(b, .5) - V3(0, 2.2, 0)
			K.Rod(m, "Cable", a, mid, .16, C(26, 26, 30), M.Fabric)
			K.Rod(m, "Cable", mid, b, .16, C(26, 26, 30), M.Fabric)
		end

		-- 13. the half-toppled FLOODLIGHT MAST at the front corner, propped on the broken column: its SpotLight sweeps
		--     the ore field (the annex's second key light) --------------------------------------------------------------------
		local mbase = at(-13.6, 0, 17.2)
		K.Part(m, "MastFooting", V3(1.7, .8, 1.7), mbase * CF(0, .25, 0) * ANG(.08, .3, -.14), CONC_D, M.Concrete, S())
		local m0 = (mbase * CF(0, .55, 0)).Position
		local rest = at(-11.6, fl + 9.5, 14).Position -- the top corner of the broken front column
		local m1 = m0 + (rest - m0).Unit * 14.4
		K.Rod(m, "MastPole", m0, m1, .5, STEEL:Lerp(P.Rust, .2), M.Metal)
		local side = (rest - m0):Cross(V3(0, 1, 0)).Unit * .9
		K.Rod(m, "MastPole", m0 + side, m1 + side * .4, .24, STEEL, M.Metal)
		for k = 1, 4 do
			local t = k / 5
			K.Rod(m, "MastRung", m0:Lerp(m1, t), (m0 + side):Lerp(m1 + side * .4, t + .06), .14, STEEL, M.Metal)
		end
		local target = V3(178, 1, 668)
		local hc = K.Look(m1 + V3(0, .7, 0), target)
		K.Part(m, "FloodYoke", V3(3, .26, .3), hc * CF(0, -.85, .1), STEEL, M.Metal)
		local housing = K.Part(m, "FloodHousing", V3(2.6, 1.6, .75), hc, C(58, 62, 70), M.Metal)
		local lens = K.Part(m, "FloodLens", V3(2.2, 1.2, .1), hc * CF(0, 0, -.4), C(214, 255, 226), M.Neon)
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(m, "FloodBarnDoor", V3(.1, 1.5, .9), hc * CF(sx * 1.45, 0, -.65) * ANG(0, sx * .5, 0), C(58, 62, 70), M.Metal)
		end
		local fl2 = K.Light(lens, C(200, 255, 214), 46, 3.5, "SpotLight")
		fl2.Face = N.Front
		fl2.Angle = 55
		fl2:SetAttribute("HwKeyLight", true)
		K.Attach(housing, "CrowPerch", CF(0, 1.1, .1))
		K.Rod(m, "MastCable", (hc * CF(.9, -.6, .4)).Position, m0:Lerp(m1, .5) + side * .5 - V3(0, 1.2, 0), .14, C(26, 26, 30), M.Fabric)
		K.Rod(m, "MastCable", m0:Lerp(m1, .5) + side * .5 - V3(0, 1.2, 0), at(-11.2, fl + .1, 12.4).Position, .14, C(26, 26, 30), M.Fabric)

		-- 14. flickering amber hazard lamps (HwLantern Orange: AmbientFX flickers and sputters them; no PointLights) --------
		local lamps = {
			onWall(4 * PI / 3, 22.15, -.3), -- on the broken crown
			at(-11.62, fl + 10.2, 0) * ANG(0, PI / 2, 0), -- front column
			CF(m0:Lerp(m1, .62) - side * .45) * ANG(0, PI / 2, 0), -- floodlight mast
		}
		for _, lc in ipairs(lamps) do
			K.Part(m, "HazardLampBase", V3(.6, .3, .6), lc, STEEL, M.Metal)
			K.Ellipsoid(m, "HazardLamp", V3(.55, .6, .55), lc * CF(0, .4, 0), C(255, 150, 40), M.Neon, { Attrs = { HwLantern = "Orange" } })
		end

		-- 15. the containment tube as the hero machine: stepped hazard-striped base, cap clamps, rising bubbles, feed pipes --
		K.Part(m, "TubePlinth", V3(8.2, .35, 8.2), tb * CF(0, .175, 0), STEEL, M.DiamondPlate, S())
		K.Part(m, "TubeStep", V3(7.2, .35, 7.2), tb * CF(0, .52, 0), HAZ_Y, M.SmoothPlastic, S())
		for k = 0, 3 do
			for _, o in ipairs({ -1.6, 1.6 }) do
				K.Part(m, "TubeStepStripe", V3(.5, .37, .12), tb * ANG(0, k * PI / 2, 0) * CF(o, .52, -3.58) * ANG(0, 0, 0), HAZ_K, M.SmoothPlastic)
			end
		end
		for k = 0, 3 do
			local a = PI / 4 + k * PI / 2
			for _, y in ipairs({ 1.65, 2.1 + th + .5 }) do
				K.Part(m, "TubeClamp", V3(.55, 1.2, .5), tb * ANG(0, -a, 0) * CF(0, y, -2.55), STEEL:Lerp(P.Rust, .25), M.CorrodedMetal)
			end
		end
		for k = 1, 5 do
			K.Ball(m, "TubeBubble", rng:NextNumber(.3, .6), tb * CF(rng:NextNumber(-1.2, 1.2), 5.2 + k * .7, rng:NextNumber(-1.2, 1.2)), C(190, 255, 170), M.Neon,
				{ Transparency = .25 })
		end
		for _, c in ipairs({ { -.4, 1 }, { -2.2, -1 } }) do
			local a = c[1]
			local p0 = tb * ANG(0, -a, 0) * CF(0, .9, -3.25)
			local p1 = tb * ANG(0, -a, 0) * CF(c[2] * .9, .6, -5.4)
			K.Rod(m, "TubeFeed", p0.Position, p1.Position, .5, C(96, 104, 98), M.CorrodedMetal)
			K.CylY(m, "TubeFeedFlange", .2, .8, p1, STEEL, M.Metal)
		end

		-- 16. truss craft: knee braces at the column heads, riveted gusset plates ---------------------------------------------
		for _, b in ipairs({
			{ { -11, 9.4, -12.9 }, { -11, 12, -10.4 } }, { { -11, 9.2, -.5 }, { -11, 11.7, -3 } },
			{ { .5, 9.4, -13.4 }, { 3, 12, -13.4 } }, { { -.5, 9.4, -13.4 }, { -3, 12, -13.4 } },
		}) do
			ibeam(m, at(b[1][1], fl + b[1][2], b[1][3]).Position, at(b[2][1], fl + b[2][2], b[2][3]).Position, .5)
		end
		for _, g in ipairs({ { -11.62, 12, -13.4, "X" }, { -11.62, 11.6, 0, "X" }, { 0, 12, -14.02, "Z" }, { 0, 12, 14.02, "Z" } }) do
			local gc = at(g[1], fl + g[2], g[3])
			local outX = g[4] == "X"
			K.Part(m, "GussetPlate", outX and V3(.1, 1.4, 1.4) or V3(1.4, 1.4, .1), gc * (outX and ANG(PI / 4, 0, 0) or ANG(0, 0, PI / 4)), STEEL:Lerp(P.Rust, .35), M.CorrodedMetal)
			for _, o in ipairs({ { 0, .45 }, { -.4, -.1 }, { .4, -.1 } }) do
				local off = outX and CF(-.08 * (g[1] < 0 and 1 or -1), o[2], o[1]) or CF(o[1], o[2], .08 * (g[3] < 0 and -1 or 1))
				K.Ball(m, "Rivet", .2, gc * off, STEEL:Lerp(P.Rust, .1), M.Metal)
			end
		end
	end,
}
