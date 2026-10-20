-- THE DEAD YARD · the MOON TOWER (ServerStorage.HalloweenBuild.MoonTower, polish P1b). Build-time only.
-- Model `MoonTower` under ctx.Root: the gothic bell tower of the Grand Crypt (Layout.Crypts.Grand), the yard's skyline
-- landmark. It rises through the ridge of the crypt's slate roof (footprint 8.6 x 8.6 centred 5 studs behind the crypt
-- centre, back face flush with the crypt's back wall) to y ~50 (the zone's build ceiling):
--   shaft with clasping corner piers + glowing lancets (W/E/back) -> string course with four gargoyles ->
--   the BURIED MOON stage (W and E faces: stone roundel, purple Neon rim, glowing crescent moon; front: twin purple
--   lancets framing the crypt's Anubis crest + an oculus) -> open belfry (pointed arches, bronze bell, violet soul-glow
--   with the tower's only PointLight, BatRoost) -> corner pinnacles + a stepped slate spire with lucarnes ->
--   iron finial with two glowing crescents.
-- Markers: CrowPerch (pinnacles, finial), BatRoost (belfry); HwLantern="Purple" on the lancet glass and moon rims (slow
-- AmbientFX pulse). Lights: 1 (belfry, Shadows=false, attribute HwKeyLight=true).
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi
local S = Y.Solid

local STONE = C(108, 104, 122)
local STONE_D = C(78, 74, 90)
local STONE_L = C(146, 142, 158)
local ROOF = C(54, 50, 70)
local IRON = C(46, 48, 58)
local GLASS = C(150, 84, 230)
local MOON = C(214, 220, 255)

-- lancet window (faces -Z of cf; cf = sill centre on the wall face), see Crypts.lancet
local function lancet(m, cf, w, h)
	K.Part(m, "LancetSill", V3(w + .8, .3, .6), cf * CF(0, -.15, -.2), STONE_L, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "LancetJamb", V3(.38, h, .5), cf * CF(sx * (w / 2 + .17), h / 2, -.2), STONE_L, M.Slate)
		K.Bar(m, "LancetHood", (cf * CF(sx * (w / 2 + .3), h - .1, -.22)).Position, (cf * CF(0, h + w * .72, -.22)).Position, .5, .36, STONE_L, M.Slate)
	end
	K.Part(m, "LancetGlass", V3(w, h, .12), cf * CF(0, h / 2, -.06), GLASS, M.Neon, { Attrs = { HwLantern = "Purple" } })
	Y.GableTri(m, "LancetGlassHead", cf * CF(0, h, -.06) * ANG(0, PI / 2, 0), w, w * .62, .12, GLASS, M.Neon)
end

-- crouching gargoyle dog on a corner (faces -Z of cf)
local function gargoyle(m, cf)
	local g = C(92, 90, 106)
	K.Part(m, "GargoyleBody", V3(1.2, 1.1, 1.9), cf * CF(0, .55, .1), g, M.Slate)
	K.Part(m, "GargoyleHead", V3(1, .9, 1), cf * CF(0, 1.15, -.75), g, M.Slate)
	K.Part(m, "GargoyleSnout", V3(.6, .45, .7), cf * CF(0, 1, -1.45), g, M.Slate)
	K.Wedge(m, "GargoyleWing", V3(.15, 1.3, 1.4), cf * CF(-.7, 1.3, .4) * ANG(0, 0, .5), g:Lerp(P.Ink, .2), M.Slate)
	K.Wedge(m, "GargoyleWing", V3(.15, 1.3, 1.4), cf * CF(.7, 1.3, .4) * ANG(0, 0, -.5), g:Lerp(P.Ink, .2), M.Slate)
	K.Ball(m, "GargoyleEye", .22, cf * CF(-.24, 1.3, -1.27), Y.GLOW.Purple, M.Neon)
	K.Ball(m, "GargoyleEye", .22, cf * CF(.24, 1.3, -1.27), Y.GLOW.Purple, M.Neon)
end

local function pinnacle(m, cf, h)
	K.Part(m, "PinnacleBase", V3(1.3, .7, 1.3), cf * CF(0, .35, 0), STONE_D, M.Slate)
	K.Part(m, "Pinnacle", V3(.8, h, .8), cf * CF(0, .7 + h / 2, 0), STONE, M.Slate)
	local cap = K.Part(m, "PinnacleCap", V3(1.05, .25, 1.05), cf * CF(0, .82 + h, 0), STONE_L, M.Slate)
	Y.GableTri(m, "PinnacleTip", cf * CF(0, .95 + h, 0), .8, 1.3, .8, STONE_L, M.Slate)
	K.Attach(cap, "CrowPerch", CF(0, 1.5, 0))
end

-- the BURIED MOON dial (faces -Z of cf): stone roundel, purple Neon rim, glowing moon with a crescent shadow, iron spikes
local function moonDial(m, cf)
	K.CylZ(m, "DialFrame", .5, 6.4, cf * CF(0, 0, -.2), STONE_L, M.Slate)
	K.CylZ(m, "DialRim", .3, 5.9, cf * CF(0, 0, -.45), Y.GLOW.Purple, M.Neon, { Attrs = { HwLantern = "Purple" } })
	K.CylZ(m, "DialMoon", .3, 5.3, cf * CF(0, 0, -.55), MOON, M.Neon)
	K.CylZ(m, "DialShadow", .3, 4.3, cf * CF(1.15, .45, -.63), C(66, 60, 88), M.Slate)
	K.CylZ(m, "DialCrater", .08, .75, cf * CF(-1.45, -.8, -.74), C(176, 180, 214), M.SmoothPlastic)
	K.CylZ(m, "DialCrater", .08, .5, cf * CF(-.75, 1.45, -.74), C(176, 180, 214), M.SmoothPlastic)
	for k = 0, 3 do
		K.Part(m, "DialStud", V3(.42, .8, .3), cf * ANG(0, 0, k * PI / 2) * CF(0, 3.5, -.15), IRON, M.CorrodedMetal)
	end
end

return {
	Build = function(ctx)
		local L = ctx.Layout
		local spec = L.Crypts.Grand
		local m = K.Model(ctx.Root, "MoonTower")
		local rng = Y.Rng(5511)
		local cx, cz = (spec.X0 + spec.X1) / 2, (spec.Z0 + spec.Z1) / 2
		local T = CF(cx, L.FloorY, cz + 4.5) -- tower axis (local y 0 = the yard floor); front = -Z (toward the pit)
		local function at(x, y, z)
			return T * CF(x, y, z)
		end
		local function face(i) -- i = 0 front (-Z), 1 west (-X), 2 back (+Z), 3 east (+X): frame on that face, -Z outward
			return ANG(0, i * PI / 2, 0)
		end

		-- 1. shaft (rises through the crypt roof from the cella top at y 13) with clasping corner piers ------------------------
		local A0, A1, R = 13, 26, 4.7
		K.Part(m, "TowerShaft", V3(R * 2, A1 - A0, R * 2), at(0, (A0 + A1) / 2, 0), STONE, M.Slate, S())
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			K.Part(m, "TowerPier", V3(1.7, A1 - A0, 1.7), at(c[1] * (R - .25), (A0 + A1) / 2, c[2] * (R - .25)), STONE_D, M.Slate, S())
		end
		for _, i in ipairs({ 1, 2, 3 }) do
			lancet(m, at(0, 0, 0) * face(i) * CF(0, 22.2, -R), 1.3, 2.6)
		end
		-- string course + gargoyles on the four corners (looking out diagonally)
		K.Part(m, "StringCourse", V3(R * 2 + 1.3, .6, R * 2 + 1.3), at(0, A1 + .3, 0), STONE_L, M.Slate)
		for k = 0, 3 do
			local a = PI / 4 + k * PI / 2
			gargoyle(m, at(0, A1 + .6, 0) * ANG(0, a, 0) * CF(0, 0, -6.5))
		end
		-- 2. the BURIED MOON stage: moon dials west + east, twin lancets + oculus on the front -----------------------------
		local B0, B1, RB = A1 + .6, 32.8, 4.4
		local bc = (B0 + B1) / 2
		K.Part(m, "MoonStage", V3(RB * 2, B1 - B0, RB * 2), at(0, bc, 0), STONE_L:Lerp(STONE, .55), M.Slate, S())
		moonDial(m, at(0, bc, 0) * face(1) * CF(0, 0, -RB))
		moonDial(m, at(0, bc, 0) * face(3) * CF(0, 0, -RB))
		for _, sx in ipairs({ -1, 1 }) do
			lancet(m, at(sx * 2.1, B0 + .8, -RB), 1.5, 3.6)
		end
		K.CylZ(m, "Oculus", .4, 1.5, at(0, B1 - 1.05, -RB - .1), STONE_L, M.Slate)
		K.CylZ(m, "OculusGlass", .3, 1.05, at(0, B1 - 1.05, -RB - .2), GLASS, M.Neon, { Attrs = { HwLantern = "Purple" } })
		K.Part(m, "MoonCornice", V3(RB * 2 + 1, .6, RB * 2 + 1), at(0, B1 + .3, 0), STONE_L, M.Slate)
		-- 3. open belfry: corner piers, pointed arches (spandrel wedges), bronze bell, violet soul-glow -----------------------
		local C0, C1, RC = B1 + .6, 38.2, 3.4
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			K.Part(m, "BelfryPier", V3(1.7, C1 - C0, 1.7), at(c[1] * RC, (C0 + C1) / 2, c[2] * RC), STONE, M.Slate, S())
		end
		local half = RC - .85 -- half width of an opening
		for i = 0, 3 do
			local f = at(0, 0, 0) * face(i) * CF(0, 0, -RC)
			for _, sx in ipairs({ -1, 1 }) do
				-- right angle at the pier top: inverted wedge, its slope forms half of the pointed opening
				K.Wedge(m, "BelfrySpandrel", V3(.8, 1.8, half), f * CF(sx * half / 2, C1 - .9, 0) * ANG(0, -sx * PI / 2, 0) * ANG(PI, 0, 0), STONE, M.Slate)
			end
		end
		K.CylX(m, "BellYoke", RC * 2 - .4, .45, at(0, C1 - .75, 0), C(70, 52, 42), M.Wood)
		K.CylY(m, "Bell", 1.8, 2, at(0, C1 - 2.1, 0), C(122, 92, 52), M.Metal)
		K.CylY(m, "BellLip", .25, 2.5, at(0, C1 - 3, 0), C(110, 82, 46), M.Metal)
		K.Ball(m, "BellCrown", .9, at(0, C1 - 1.15, 0), C(122, 92, 52), M.Metal)
		K.Ball(m, "BellClapper", .55, at(.15, C1 - 3.35, 0), IRON, M.Metal)
		local soul = K.Ellipsoid(m, "BelfryGlow", V3(1.5, 1.9, 1.5), at(0, C0 + 1.05, 0), C(196, 170, 255), M.Neon, { Transparency = .1 })
		local bl = K.Light(soul, C(176, 150, 255), 26, 2.2)
		bl:SetAttribute("HwKeyLight", true)
		K.Attach(soul, "BatRoost", CF(0, 2.2, 0))
		K.Part(m, "BelfryCornice", V3(RC * 2 + 2.6, .6, RC * 2 + 2.6), at(0, C1 + .3, 0), STONE_L, M.Slate)
		-- 4. corner pinnacles + stepped slate spire with lucarnes + iron finial with two crescents ------------------------------
		local D0 = C1 + .6
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			pinnacle(m, at(c[1] * (RC + .7), D0, c[2] * (RC + .7)), 2.3)
		end
		local tiers, th = 12, .73
		for k = 0, tiers - 1 do
			local side = 7.2 * (1 - k / (tiers + 1))
			K.Part(m, "Spire", V3(side, th, side), at(0, D0 + (k + .5) * th, 0), k % 2 == 0 and ROOF or ROOF:Lerp(C(84, 76, 108), .6), M.Slate,
				k == 0 and S() or nil)
		end
		for i = 0, 3 do
			local f = at(0, 0, 0) * face(i) * CF(0, D0 + .88, -3.2)
			K.Part(m, "Lucarne", V3(1.3, 1.5, 1), f * CF(0, .75, 0), STONE_L, M.Slate)
			K.Part(m, "LucarneSlit", V3(.45, .95, .1), f * CF(0, .7, -.52), GLASS, M.Neon)
			Y.GableTri(m, "LucarneRoof", f * CF(0, 1.5, 0) * ANG(0, PI / 2, 0), 1.6, .9, 1.15, ROOF, M.Slate)
		end
		local top = D0 + tiers * th
		K.CylY(m, "FinialRod", 1.4, .3, at(0, top + .5, 0), IRON, M.CorrodedMetal)
		local orb = K.Ball(m, "FinialOrb", .65, at(0, top + .5, 0), C(200, 160, 80), M.Metal)
		K.Attach(orb, "CrowPerch", CF(0, .45, 0))
		for i = 0, 1 do -- two crossed voxel crescents (arc of glowing blocks on the rod tip, horns up)
			local cr = at(0, top + 1.35, 0) * face(i)
			for k = -2, 2 do
				local a = -PI / 2 + k
				K.Part(m, "FinialCrescent", V3(.3, .36 - math.abs(k) * .06, .16), cr * CF(math.cos(a) * .58, math.sin(a) * .58, 0) * ANG(0, 0, a),
					C(255, 226, 140), M.Neon)
			end
		end
		-- 5. ivy up the west pier, cracks on the shaft -------------------------------------------------------------------------
		Y.Vine(m, (at(-R - .25, A1 - .3, -R + .1)).Position, (at(-R - .25, 21.8, -R)).Position, rng, V3(-1, 0, 0))
		K.Part(m, "TowerCrack", V3(.12, 2.2, .05), at(-3.1, 24.4, -R - .03) * ANG(0, 0, .4), C(40, 36, 48), M.SmoothPlastic)
		K.Part(m, "TowerCrack", V3(.12, 2.4, .05), at(3.8, 29.4, -RB - .03) * ANG(0, 0, -.3), C(40, 36, 48), M.SmoothPlastic)
		if ctx.Note then
			ctx.Note(string.format("MoonTower: %d parts, top y %.1f", K.Count(m), L.FloorY + top + 1.8))
		end
	end,
}
