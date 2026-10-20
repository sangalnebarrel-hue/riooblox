-- THE DEAD YARD · the three crypts (ServerStorage.HalloweenBuild.Crypts, WP2). Build-time only.
-- Model `Crypts` under ctx.Root with `GrandCrypt`, `CryptB`, `CryptC` at Layout.Crypts.Grand/B/C (all doors face -Z).
--   GrandCrypt (x 114..142, z 724..742): the boss backdrop south of the pit, a gothic mausoleum: stepped plinth (footing,
--     moulded band) + stairs between sloped cheeks, 4-column portico (torus, fluted shafts, echinus, abacus), iron
--     double door ajar under a tudor hood with a green-lit interior, a pointed gable (copings, crockets, pinnacled
--     kneelers) with the BURIED MOON rose window (stone roundel, purple Neon rim + rune studs, glowing crescent) and the
--     black Anubis guardian on its apex, a steep slate roof with ridge cresting (the MoonTower builder raises the bell
--     tower through it), stepped side buttresses with pinnacles, glowing lancets, bone-cross reliefs, urns with green
--     fire (HwBrazier), chains, lanterns, iron forecourt fence and two violet SpotLight uplights (key light, HwKeyLight).
--     Attachment `CryptDoor` marks the threshold (boss / FX use).
--   CryptB (x 176..196, z 724..742): older gothic chapel, collapsed front-right corner with rubble and bare rafters,
--     roots creeping over it, rose window, gargoyles.
--   CryptC (x 40..56, z 734..744): small domed mausoleum in the graveyard corner with an iron grille door.
-- Markers: CrowPerch, BatRoost, FogPoint; HwLantern on lantern glass, HwCandle on candle flames.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local S = Y.Solid

local STONE = C(108, 104, 122)
local STONE_D = C(78, 74, 90)
local STONE_L = C(146, 142, 158)
local IRON = C(46, 48, 58)

-- urn on a pedestal (faces -Z)
local function urn(m, cf, s)
	K.Part(m, "UrnPedestal", V3(1.9 * s, 2.4 * s, 1.9 * s), cf * CF(0, 1.2 * s, 0), STONE_D, M.Slate, S())
	K.Part(m, "UrnPedestalCap", V3(2.2 * s, .3 * s, 2.2 * s), cf * CF(0, 2.5 * s, 0), STONE_L, M.Slate)
	K.CylY(m, "UrnFoot", .5 * s, .9 * s, cf * CF(0, 2.9 * s, 0), STONE, M.Marble)
	K.Ellipsoid(m, "UrnBody", V3(1.6 * s, 1.5 * s, 1.6 * s), cf * CF(0, 3.75 * s, 0), STONE, M.Marble)
	K.CylY(m, "UrnRim", .3 * s, 1.3 * s, cf * CF(0, 4.5 * s, 0), STONE_L, M.Marble)
	K.Ellipsoid(m, "UrnFlame", V3(.95 * s, 1.1 * s, .95 * s), cf * CF(0, 5.05 * s, 0), Y.GLOW_DIM.Green, M.Neon)
	K.Ellipsoid(m, "UrnFlame", V3(.6 * s, 1.5 * s, .6 * s), cf * CF(.05 * s, 5.5 * s, 0) * ANG(0, 0, .12), Y.GLOW.Green, M.Neon, { Attrs = { HwBrazier = true } })
	K.Ellipsoid(m, "UrnFlameTip", V3(.3 * s, .9 * s, .3 * s), cf * CF(.18 * s, 6.25 * s, 0) * ANG(0, 0, .3), C(200, 255, 190), M.Neon)
end

-- blocky gargoyle dog crouching on a ledge (faces -Z of cf)
local function gargoyle(m, cf)
	local g = C(92, 90, 106)
	K.Part(m, "GargoyleBody", V3(1.2, 1.1, 1.8), cf * CF(0, .55, .2), g, M.Slate)
	K.Part(m, "GargoyleHead", V3(1, .9, 1), cf * CF(0, 1.2, -.6), g, M.Slate)
	K.Part(m, "GargoyleSnout", V3(.6, .45, .6), cf * CF(0, 1.05, -1.25), g, M.Slate)
	K.Wedge(m, "GargoyleWing", V3(.15, 1.3, 1.4), cf * CF(-.7, 1.3, .5) * ANG(0, 0, .5), g:Lerp(P.Ink, .2), M.Slate)
	K.Wedge(m, "GargoyleWing", V3(.15, 1.3, 1.4), cf * CF(.7, 1.3, .5) * ANG(0, 0, -.5), g:Lerp(P.Ink, .2), M.Slate)
	K.Ball(m, "GargoyleEye", .2, cf * CF(-.24, 1.35, -1.1), Y.GLOW.Purple, M.Neon)
	K.Ball(m, "GargoyleEye", .2, cf * CF(.24, 1.35, -1.1), Y.GLOW.Purple, M.Neon)
end

local function pinnacle(m, cf, h)
	K.Part(m, "PinnacleBase", V3(1.6, 1, 1.6), cf * CF(0, .5, 0), STONE_D, M.Slate)
	K.Part(m, "Pinnacle", V3(1.1, h, 1.1), cf * CF(0, 1 + h / 2, 0), STONE, M.Slate)
	local cap = K.Part(m, "PinnacleCap", V3(1.4, .3, 1.4), cf * CF(0, 1.15 + h, 0), STONE_L, M.Slate)
	Y.GableTri(m, "PinnacleTip", cf * CF(0, 1.3 + h, 0), 1.1, 1.3, 1.1, STONE_L, M.Slate)
	K.Attach(cap, "CrowPerch", CF(0, 1.5, 0))
	return cap
end

-- gothic lancet window on a wall (faces -Z of cf; cf = centre of the sill on the wall face): stone jambs, sill and a
-- pointed hood, glowing glass with a pointed head (HwLantern Purple: AmbientFX gives it a slow pulse), optional mullion
local function lancet(m, cf, w, h, glass, mullion)
	K.Part(m, "LancetSill", V3(w + .8, .3, .6), cf * CF(0, -.15, -.2), STONE_L, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "LancetJamb", V3(.38, h, .5), cf * CF(sx * (w / 2 + .17), h / 2, -.2), STONE_L, M.Slate)
		K.Bar(m, "LancetHood", (cf * CF(sx * (w / 2 + .3), h - .1, -.22)).Position, (cf * CF(0, h + w * .72, -.22)).Position, .5, .36, STONE_L, M.Slate)
	end
	K.Part(m, "LancetGlass", V3(w, h, .12), cf * CF(0, h / 2, -.06), glass, M.Neon, { Attrs = { HwLantern = "Purple" } })
	Y.GableTri(m, "LancetGlassHead", cf * CF(0, h, -.06) * ANG(0, PI / 2, 0), w, w * .62, .12, glass, M.Neon)
	if mullion then
		K.Part(m, "LancetMullion", V3(.16, h + w * .3, .1), cf * CF(0, (h + w * .3) / 2, -.17), STONE_L, M.Slate)
	end
end

-- seated jackal-dog guardian in the Anubis pose (faces -Z of cf, base on cf): black basalt, gold collar and arm bands,
-- tall pointed ears, glowing eyes. Returns the head CFrame.
local function anubis(m, cf, s, eye)
	local body, shade, gold = C(50, 46, 62), C(32, 30, 42), C(214, 168, 70)
	local function at(x, y, z)
		return cf * CF(x * s, y * s, z * s)
	end
	K.Ellipsoid(m, "CrestHaunch", V3(2.3 * s, 2.1 * s, 2.6 * s), at(0, 1.05, .5), body, M.Basalt)
	K.Part(m, "CrestChest", V3(1.6 * s, 2.9 * s, 1.4 * s), at(0, 2.4, -.2) * ANG(.15, 0, 0), body, M.Basalt)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "CrestForeleg", V3(.48 * s, 2.4 * s, .52 * s), at(sx * .48, 1.2, -.92), body, M.Basalt)
		K.Part(m, "CrestPaw", V3(.6 * s, .32 * s, .9 * s), at(sx * .48, .16, -1.18), shade, M.Basalt)
		K.Part(m, "CrestHindPaw", V3(.66 * s, .34 * s, 1.25 * s), at(sx * 1, .17, .25), shade, M.Basalt)
		K.Part(m, "CrestBand", V3(.56 * s, .2 * s, .6 * s), at(sx * .48, 1.7, -.92), gold, M.Metal)
	end
	K.Part(m, "CrestNeck", V3(.95 * s, 1.6 * s, .95 * s), at(0, 4.05, -.5) * ANG(.2, 0, 0), body, M.Basalt)
	K.Part(m, "CrestCollar", V3(1.8 * s, .38 * s, 1.5 * s), at(0, 3.5, -.38) * ANG(.15, 0, 0), gold, M.Metal)
	K.Ball(m, "CrestGem", .4 * s, at(0, 3.42, -1.12), Y.GLOW.Purple, M.Neon)
	local head = at(0, 5.05, -.72)
	K.Part(m, "CrestHead", V3(1.1 * s, 1 * s, 1.2 * s), head, body, M.Basalt)
	K.Part(m, "CrestMuzzle", V3(.58 * s, .5 * s, 1.4 * s), head * CF(0, -.22 * s, -1.2 * s), body, M.Basalt)
	K.Ball(m, "CrestNose", .28 * s, head * CF(0, -.1 * s, -1.9 * s), shade, M.Basalt)
	for _, sx in ipairs({ -1, 1 }) do
		Y.GableTri(m, "CrestEar", head * CF(sx * .33 * s, .48 * s, .1 * s) * ANG(0, PI / 2, 0), .58 * s, 1.7 * s, .2 * s, body, M.Basalt)
		K.Part(m, "CrestEye", V3(.28 * s, .13 * s, .06 * s), head * CF(sx * .28 * s, .12 * s, -.62 * s), eye, M.Neon)
	end
	K.Rod(m, "CrestTail", at(.8, .25, 1.6).Position, at(1.35, .2, .1).Position, .4 * s, body, M.Basalt)
	K.Rod(m, "CrestTail", at(1.35, .2, .1).Position, at(1.25, .2, -.9).Position, .34 * s, body, M.Basalt)
	return head
end

------------------------------------------------------------------------------------------------------------------
local function grand(parent, spec, rng)
	local m = K.Model(parent, "GrandCrypt")
	local cx, cz = (spec.X0 + spec.X1) / 2, (spec.Z0 + spec.Z1) / 2
	local O = CF(cx, .2, cz) -- local frame: front = -Z (z = -9 is the front edge at z 724)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- stepped plinth: footing course, two tiers with a moulded band, cap; stairs between sloped cheek walls
	K.Part(m, "PlinthFooting", V3(29.6, .45, 19.2), at(0, .225, .2), STONE_D:Lerp(P.Ink, .15), M.Cobblestone, S())
	K.Part(m, "Plinth", V3(28, 1.1, 17.6), at(0, .55, .2), STONE_D, M.Cobblestone, S())
	K.Part(m, "PlinthBand", V3(28.3, .3, 17.9), at(0, 1.12, .2), STONE_L, M.Slate)
	K.Part(m, "Plinth", V3(26.4, .9, 16.4), at(0, 1.55, .6), STONE, M.Cobblestone, S())
	K.Part(m, "PlinthCap", V3(26.8, .25, 16.8), at(0, 2.05, .6), STONE_L, M.Slate)
	for k = 1, 3 do
		local top = .7 * k
		K.Part(m, "CryptStair", V3(12 - k * .6, top, 1.15), at(0, top / 2, -8.7 - (3 - k) * 1.15 - .6), (k % 2 == 0) and STONE or STONE_D, M.Slate, S())
	end
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "StairCheek", V3(.8, .9, 3.5), at(sx * 6.1, .45, -10.45), STONE_D, M.Slate, S())
		K.Wedge(m, "StairCheekSlope", V3(.8, 1.5, 3.5), at(sx * 6.1, 1.65, -10.45), STONE_L, M.Slate)
	end
	-- cella: solid core + front wall with the door opening (door 6 x 9 from the porch floor y 2.2)
	local fy = 2.2
	local top = 13
	K.Part(m, "CellaCore", V3(21, top - fy, 12), at(0, fy + (top - fy) / 2, 3), STONE, M.Slate, S())
	local fz = -3.9 -- front wall centre (z -4.9..-2.9)
	K.Part(m, "CellaFront", V3(7.5, top - fy, 2), at(-6.75, fy + (top - fy) / 2, fz), STONE, M.Slate, S())
	K.Part(m, "CellaFront", V3(7.5, top - fy, 2), at(6.75, fy + (top - fy) / 2, fz), STONE, M.Slate, S())
	K.Part(m, "CellaLintel", V3(6, top - fy - 9, 2), at(0, fy + 9 + (top - fy - 9) / 2, fz), STONE, M.Slate, S())
	K.Part(m, "DoorArchitrave", V3(7.4, .8, .5), at(0, fy + 9.3, -5.05), STONE_L, M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "DoorJamb", V3(.7, 9, .5), at(sx * 3.35, fy + 4.5, -5.05), STONE_L, M.Slate)
		-- low pointed (tudor) hood over the door, keystone skull with green eyes
		K.Bar(m, "DoorHood", (at(sx * 3.75, fy + 9.55, -5.3)).Position, (at(0, fy + 10.65, -5.3)).Position, .5, .42, STONE_L, M.Slate)
	end
	Y.Skull(m, at(0, fy + 10.25, -5.55), .85, Y.GLOW.Green, STONE_L)
	-- interior glimpsed through the ajar door: dark recess + green glow
	K.Part(m, "CryptDark", V3(6, 9, .2), at(0, fy + 4.5, -2.85), C(12, 18, 14), M.SmoothPlastic)
	K.Part(m, "CryptGlowFloor", V3(5.6, .06, 1.8), at(0, fy + .03, -3.8), Y.GLOW_DIM.Green, M.Neon)
	local glow = K.Part(m, "CryptGlow", V3(.4, .4, .4), at(0, fy + 3.5, -3.2), Y.GLOW.Green, M.Neon, { Transparency = 1 })
	K.Light(glow, Y.GLOW.Green, 16, 1.2)
	K.Attach(glow, "CryptDoor", CF(0, -1.3, -1.9))
	K.Ball(m, "CryptEye", .35, at(-.8, fy + 5.6, -3.05), Y.GLOW.Green, M.Neon)
	K.Ball(m, "CryptEye", .35, at(.2, fy + 5.7, -3.05), Y.GLOW.Green, M.Neon)
	-- iron double door: left leaf shut, right leaf ajar (~28 degrees inward)
	for _, sx in ipairs({ -1, 1 }) do
		local hinge = at(sx * 3, fy, -4.75) * ANG(0, sx == 1 and .5 or 0, 0)
		local leaf = function(x, y, z)
			return hinge * CF(-sx * x, y, z)
		end
		K.Part(m, "CryptDoorLeaf", V3(2.95, 8.9, .3), leaf(1.5, 4.45, 0), IRON, M.CorrodedMetal)
		for _, yy in ipairs({ 1.4, 4.45, 7.5 }) do
			K.Part(m, "CryptDoorBand", V3(2.95, .3, .12), leaf(1.5, yy, -.2), C(70, 66, 74), M.CorrodedMetal)
		end
		K.Ball(m, "CryptDoorStud", .32, leaf(.4, 2.9, -.2), C(90, 84, 70), M.Metal)
		K.Ball(m, "CryptDoorStud", .32, leaf(.4, 6, -.2), C(90, 84, 70), M.Metal)
		-- paw relief
		K.Ball(m, "PawPad", .9, leaf(1.6, 5.6, -.2), C(80, 76, 90), M.CorrodedMetal)
		for t = -1, 1 do
			K.Ball(m, "PawToe", .42, leaf(1.6 + t * .45, 6.35 + (t == 0 and .12 or 0), -.2), C(80, 76, 90), M.CorrodedMetal)
		end
		K.CylZ(m, "CryptRing", .12, .7, leaf(.55, 4.1, -.25), C(150, 120, 60), M.Metal)
	end
	-- portico: 4 columns (plinth, torus, fluted shaft, astragal, echinus, abacus), ceiling, entablature with skull frieze
	local colZ = -7.6
	for _, x in ipairs({ -9.6, -4.9, 4.9, 9.6 }) do
		local base = at(x, fy, colZ)
		local sh = top - fy - 2.2
		K.Part(m, "ColumnBase", V3(2.4, .55, 2.4), base * CF(0, .275, 0), STONE_L, M.Slate, S())
		K.CylY(m, "ColumnTorus", .4, 2.05, base * CF(0, .75, 0), STONE_L, M.Marble)
		K.CylY(m, "Column", sh, 1.6, base * CF(0, .95 + sh / 2, 0), STONE_L:Lerp(STONE, .3), M.Marble, S())
		for _, phi in ipairs({ -.62, 0, .62 }) do
			K.Part(m, "ColumnFlute", V3(.16, sh - .5, .1), base * CF(math.sin(phi) * .79, .95 + sh / 2, -math.cos(phi) * .79) * ANG(0, -phi, 0), STONE_D, M.Slate)
		end
		K.CylY(m, "ColumnAstragal", .3, 1.85, base * CF(0, .95 + sh + .15, 0), STONE_L, M.Marble)
		K.CylY(m, "ColumnEchinus", .5, 2.2, base * CF(0, .95 + sh + .55, 0), STONE_L, M.Slate)
		K.Part(m, "ColumnAbacus", V3(2.5, .45, 2.5), at(x, top - .225, colZ), STONE_L, M.Slate)
		K.Part(m, "ColumnMoss", V3(1.7, .1, .9), at(x - .1, fy + .6, colZ - .9), P.Moss, M.Grass)
	end
	K.Part(m, "PorticoCeiling", V3(23, .8, 5.6), at(0, top + .4, -6.2), STONE, M.Slate, S())
	K.Part(m, "Architrave", V3(23.4, 1.2, 1.1), at(0, top + .6, -8.6), STONE_L, M.Slate)
	K.Part(m, "Frieze", V3(23.2, 1.5, .9), at(0, top + 1.95, -8.4), STONE_D, M.Slate)
	K.Part(m, "Cornice", V3(24.6, .55, 2), at(0, top + 2.95, -8.2), STONE_L, M.Slate)
	for _, x in ipairs({ -9, -4.5, 4.5, 9 }) do
		Y.Skull(m, at(x, top + 2, -8.95), .95, nil, STONE_L)
	end
	for _, x in ipairs({ -11.2, -6.75, -2.25, 2.25, 6.75, 11.2 }) do
		K.Part(m, "Triglyph", V3(.7, 1.4, .3), at(x, top + 1.95, -8.95), STONE, M.Slate)
	end
	-- pointed gothic gable on the cornice: raking copings with crockets, the BURIED MOON rose window (stone roundel,
	-- purple Neon rim, crescent moon, rune ticks) and the black Anubis guardian on the apex
	local gy, gz, GW, GH = top + 3.2, -7.9, 18, 10
	Y.GableTri(m, "Gable", at(0, gy, gz) * ANG(0, PI / 2, 0), GW, GH, 2, STONE, M.Slate, true)
	for _, sx in ipairs({ -1, 1 }) do
		local nrm = V3(sx * GH, GW / 2, 0).Unit
		local function pt(t, off)
			return (O * CF(V3(sx * GW / 2 * (1 - t), gy + GH * t, gz) + nrm * off)).Position
		end
		K.Bar(m, "GableCoping", pt(-.04, .3), pt(1.02, .3), 2.4, .6, STONE_L, M.Slate)
		for _, t in ipairs({ .26, .5, .74 }) do
			K.Ball(m, "GableCrocket", .8, CF(pt(t, .82)), STONE_L, M.Slate)
		end
		K.Part(m, "GableFoot", V3(1.6, 1.3, 2.6), at(sx * 9.3, gy + .65, gz), STONE_L, M.Slate)
		pinnacle(m, at(sx * 9.3, gy + 1.3, gz), 2.4)
	end
	local em = at(0, gy + 3.6, gz - 1) -- rose window centre on the gable face (faces -Z)
	K.CylZ(m, "MoonFrame", .45, 6.6, em * CF(0, 0, -.15), STONE_L, M.Slate)
	K.CylZ(m, "MoonRim", .3, 6, em * CF(0, 0, -.3), Y.GLOW.Purple, M.Neon, { Attrs = { HwLantern = "Purple" } })
	local disc = K.CylZ(m, "MoonDisc", .3, 5.4, em * CF(0, 0, -.4), C(196, 188, 160), M.Neon)
	K.Light(disc, Y.GLOW.Purple, 18, .9)
	K.CylZ(m, "MoonShadow", .32, 4.4, em * CF(1.1, .45, -.47), STONE, M.Slate)
	for _, c in ipairs({ { -1.5, -.9, .8 }, { -.6, 1.55, .55 }, { -2.05, .6, .42 } }) do
		K.CylZ(m, "MoonCrater", .1, c[3], em * CF(c[1], c[2], -.6), C(176, 170, 150), M.Marble)
	end
	for k = 0, 7 do
		if k ~= 4 then
			K.Part(m, "MoonRune", V3(.44, .44, .1), em * ANG(0, 0, k * PI / 4) * CF(0, 3.72, -.05) * ANG(0, 0, PI / 4), Y.GLOW.Purple, M.Neon)
		end
	end
	K.Part(m, "CrestPlinth", V3(2.4, 1.2, 2.6), at(0, gy + GH - .1, gz), STONE_L, M.Slate)
	local crestCap = K.Part(m, "CrestPlinthCap", V3(2.8, .3, 3), at(0, gy + GH + .65, gz), STONE_L, M.Slate)
	local head = anubis(m, at(0, gy + GH + .8, gz + .3), .8, Y.GLOW.Green)
	Y.AttachAt(crestCap, "CrowPerch", (head * CF(0, .6, .3)).Position)
	-- steep slate roof behind the gable (the Moon Tower rises through its ridge), back gable, eaves on the old stepped base
	for k = 0, 1 do
		K.Part(m, "SteppedRoof", V3(22.4 - k * 3.4, .95, 13.6 - k * 2.6), at(0, top + .48 + k * .95, 3), k % 2 == 0 and STONE_D or STONE, M.Slate, k == 0 and S() or nil)
	end
	local ROOF = C(54, 50, 70)
	local rz0, rz1 = gz + .9, 9.7
	local slope = GH / (GW / 2)
	for _, sx in ipairs({ -1, 1 }) do
		local a = at(0, gy + GH + .25, (rz0 + rz1) / 2).Position
		local b = at(sx * 11.3, gy + GH - 11.3 * slope + .25, (rz0 + rz1) / 2).Position
		local roof = K.Bar(m, "Roof", a, b, rz1 - rz0, .5, ROOF, M.Slate, S())
		local Ls = (b - a).Magnitude
		for r = 1, 3 do
			K.Part(m, "RoofShingles", V3(rz1 - rz0 + .2, .18, Ls / 3 + .25), roof.CFrame * CF(0, .3, -Ls / 2 + (r - .5) * Ls / 3) * ANG(-.05, 0, 0),
				ROOF:Lerp(C(74, 68, 94), r * .25), M.Slate)
		end
	end
	local ridge = K.Part(m, "RidgeCap", V3(.8, .45, 6.8), at(0, gy + GH + .5, -3.55), IRON, M.CorrodedMetal)
	for _, z in ipairs({ -5.8, -3.6, -1.4 }) do
		K.Wedge(m, "RidgeCresting", V3(.12, .9, .4), at(0, gy + GH + 1.15, z), IRON, M.CorrodedMetal)
	end
	K.Attach(ridge, "CrowPerch", CF(0, .4, 2))
	Y.GableTri(m, "BackGable", at(0, gy + GH - 11 * slope, 8.75) * ANG(0, PI / 2, 0), 22, 11 * slope, .9, STONE, M.Slate, true)
	-- side walls: stepped buttresses with weathering and pinnacles, a lancet window and a bone-cross relief per side
	for _, sx in ipairs({ -1, 1 }) do
		for k, z in ipairs({ -1.6, 3.4, 8.2 }) do
			K.Part(m, "Buttress", V3(2.4, 6.2, 1.6), at(sx * 11.7, fy + 3.1, z), STONE_D, M.Slate, S())
			K.Wedge(m, "ButtressStep", V3(1.6, .7, .45), at(sx * 12.68, fy + 6.55, z) * ANG(0, -sx * PI / 2, 0), STONE_D, M.Slate)
			K.Part(m, "Buttress", V3(1.9, 5.2, 1.4), at(sx * 11.55, fy + 8.8, z), STONE_D:Lerp(STONE, .3), M.Slate, S())
			K.Part(m, "ButtressCap", V3(2.1, .3, 1.6), at(sx * 11.55, fy + 11.55, z), STONE_L, M.Slate)
			K.Part(m, "ButtressPinnacle", V3(.8, 2.2, .8), at(sx * 12, fy + 12.8, z), STONE, M.Slate)
			local tip = fy + 13.9
			Y.GableTri(m, "ButtressPinnacleTip", at(sx * 12, tip, z), .8, 1.4, .8, STONE_L, M.Slate)
			if k ~= 2 then
				Y.Marker(m, "CrowPerch", (at(sx * 12, tip + 1.5, z)).Position)
			end
		end
		lancet(m, at(sx * 10.5, fy + 3.4, 5.8) * ANG(0, -sx * PI / 2, 0), 1.4, 4.6, Y.GLOW_DIM.Purple:Lerp(Y.GLOW.Purple, .35), true)
		local rp = at(sx * 10.55, fy + 5.2, .9) * ANG(0, -sx * PI / 2, 0) -- faces outward
		K.Part(m, "ReliefPanel", V3(3.2, 3.2, .2), rp, STONE_D, M.Slate)
		K.Part(m, "ReliefBone", V3(3.2, .45, .2), rp * CF(0, 0, -.18) * ANG(0, 0, PI / 4), STONE_L, M.Marble)
		K.Part(m, "ReliefBone", V3(3.2, .45, .2), rp * CF(0, 0, -.18) * ANG(0, 0, -PI / 4), STONE_L, M.Marble)
		Y.Skull(m, rp * CF(0, .1, -.4), .9, nil, STONE_L)
	end
	-- guardian dogs on pedestals at the front corners (stone, glowing green eyes)
	for _, sx in ipairs({ -1, 1 }) do
		local pc = at(sx * 12.6, 2.15, -6.8)
		K.Part(m, "GuardianPlinth", V3(2.8, 2.2, 3.2), pc * CF(0, 1.1, 0), STONE_D, M.Slate, S())
		local pcap = K.Part(m, "GuardianPlinthCap", V3(3.1, .3, 3.5), pc * CF(0, 2.35, 0), STONE_L, M.Slate)
		local _, ghead = Y.DogStatue(m, pc * CF(0, 2.5, .2) * ANG(0, -sx * .25, 0), { Scale = .72, EyeColor = Y.GLOW.Green, Color = STONE_L, Name = "GuardianDog" })
		Y.AttachAt(pcap, "CrowPerch", (ghead * CF(0, 1, .2)).Position)
	end
	-- urns (green fire: HwBrazier) flanking the stairs, hanging chains between the columns, lanterns
	urn(m, at(-7.6, 0, -11.2), 1)
	urn(m, at(7.6, 0, -11.2), 1)
	for _, pair in ipairs({ { -9.6, -4.9 }, { 4.9, 9.6 } }) do
		K.Chain(m, (at(pair[1], top - 1.1, colZ)).Position, (at(pair[2], top - 1.1, colZ)).Position, 1.5, 9)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local lp = at(sx * 4.9, top - 3.6, colZ - .9)
		K.Part(m, "LanternArm", V3(.2, .2, 1), at(sx * 4.9, top - 1.9, colZ - .55), IRON, M.CorrodedMetal)
		K.Part(m, "LanternHook", V3(.1, .5, .1), at(sx * 4.9, top - 2.25, colZ - .95), IRON, M.CorrodedMetal)
		K.Lantern(m, lp * CF(0, 0, -.05), sx < 0 and Y.GLOW.Green or Y.GLOW.Purple, sx < 0 and "Green" or "Purple", { Range = 12, Brightness = .8 })
	end
	-- key light: two violet uplights in the forecourt wash the columns, the gable and the Anubis (SpotLights, no shadows)
	for _, sx in ipairs({ -1, 1 }) do
		local u = at(sx * 11.2, .3, -10.7) * ANG(.42, 0, sx * .12)
		K.Part(m, "UplightHousing", V3(1.1, .55, .8), u, IRON, M.CorrodedMetal)
		local lens = K.Part(m, "UplightLens", V3(.86, .06, .56), u * CF(0, .29, 0), C(206, 176, 255), M.Neon)
		local sl = K.Light(lens, C(160, 116, 255), 34, 3, "SpotLight")
		sl.Face = N.Top
		sl.Angle = 70
		sl:SetAttribute("HwKeyLight", true)
	end
	-- iron forecourt fence + candles on the stairs + moss/cracks + rubble
	Y.IronFence(m, (at(-14, 0, -12.6)).Position, (at(-6.4, 0, -12.6)).Position, { Height = 3, Spacing = 1.25, Solid = true }, rng)
	Y.IronFence(m, (at(6.4, 0, -12.6)).Position, (at(14, 0, -12.6)).Position, { Height = 3, Spacing = 1.25, Solid = true, Broken = .2 }, rng)
	for _, x in ipairs({ -14, -6.4, 6.4, 14 }) do
		K.Part(m, "FencePier", V3(1.1, 3.6, 1.1), at(x, 1.8, -12.6), STONE_D, M.Cobblestone, S())
		K.Part(m, "FencePierCap", V3(1.4, .3, 1.4), at(x, 3.75, -12.6), STONE_L, M.Slate)
	end
	K.Candles(m, at(-4.3, 2.1, -8.9), 3, rng, { Light = false, Spread = .5 })
	K.Candles(m, at(4.1, 2.1, -8.9), 4, rng, { Light = false, Spread = .6 })
	K.Candles(m, at(-5.2, 1.4, -10.4), 2, rng, { Light = false, Spread = .3 })
	for _, c in ipairs({ { -8.4, 9.2, -5.02, .12 }, { 7.6, 6.4, -5.02, -.3 }, { -2, 12.4, -5.02, .5 } }) do
		K.Part(m, "Crack", V3(.12, 2.4, .05), at(c[1], c[2], c[3]) * ANG(0, 0, c[4]), C(40, 36, 48), M.SmoothPlastic)
	end
	K.Part(m, "Crack", V3(.14, 3.2, .05), at(-5.6, gy + 2.2, gz - 1.02) * ANG(0, 0, -.35), C(40, 36, 48), M.SmoothPlastic)
	Y.Vine(m, (at(-10.6, top - .4, 2.2)).Position, (at(-10.6, fy + 2, 2)).Position, rng, V3(-1, 0, 0))
	Y.Vine(m, (at(-6.4, top - .6, -5)).Position, (at(-6.9, fy + 4.5, -5)).Position, rng, V3(0, 0, -1))
	Y.Vine(m, (at(10.6, top - .4, 1.5)).Position, (at(10.6, fy + 3, 1)).Position, rng, V3(1, 0, 0))
	Y.Vine(m, (at(6.4, gy + 2.6, gz - 1.05)).Position, (at(7.6, gy + .2, gz - 1.1)).Position, rng, V3(0, 0, -1))
	for k = 1, 4 do
		K.Part(m, "Rubble", V3(rng:NextNumber(.8, 1.5), rng:NextNumber(.5, .9), rng:NextNumber(.8, 1.4)),
			at((k % 2 == 0 and 1 or -1) * rng:NextNumber(7, 14), .4, -13.6 - rng:NextNumber(0, .8)) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), 0), STONE_D, M.Slate)
	end
	K.Attach(K.Part(m, "BatHang", V3(.2, .2, .2), at(0, top - .2, -6.2), P.Ink, nil, { Transparency = 1 }), "BatRoost")
	Y.Marker(m, "FogPoint", (at(-5, .4, -14.5)).Position)
	Y.Marker(m, "FogPoint", (at(6, .4, -14.8)).Position)
	return m
end

------------------------------------------------------------------------------------------------------------------
local function cryptB(parent, spec, rng)
	local m = K.Model(parent, "CryptB")
	local cx, cz = (spec.X0 + spec.X1) / 2, (spec.Z0 + spec.Z1) / 2
	local O = CF(cx, .2, cz) * ANG(0, 0, 0)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local stone = C(96, 98, 108)
	local dark = C(70, 72, 84)
	local fy = 1.2
	local wallTop = 10
	K.Part(m, "Plinth", V3(19.6, 1, 17.6), at(0, .5, 0), dark, M.Cobblestone, S())
	K.Part(m, "Step", V3(6, .5, 1.2), at(0, .25, -9.4), dark, M.Slate, S())
	-- walls (front wall broken at the right corner)
	K.Part(m, "Wall", V3(15.6, wallTop - fy, .9), at(0, fy + (wallTop - fy) / 2, 7.8), stone, M.Slate, S())
	K.Part(m, "Wall", V3(.9, wallTop - fy, 15.6), at(-7.8, fy + (wallTop - fy) / 2, 0), stone, M.Slate, S())
	K.Part(m, "Wall", V3(.9, wallTop - fy, 10.6), at(7.8, fy + (wallTop - fy) / 2, 2.5), stone, M.Slate, S())
	K.Part(m, "Wall", V3(.9, 3.2, 5), at(7.8, fy + 1.6, -5.3), stone, M.Slate, S())
	K.Part(m, "WallBroken", V3(.9, 2.2, 2.2), at(7.8, fy + 4.3, -4), stone, M.Slate)
	K.Part(m, "Wall", V3(6, wallTop - fy, .9), at(-4.8, fy + (wallTop - fy) / 2, -7.8), stone, M.Slate, S())
	K.Part(m, "Wall", V3(3.4, 5.2, .9), at(4.2, fy + 2.6, -7.8), stone, M.Slate, S())
	K.Part(m, "WallBroken", V3(2.2, 1.8, .9), at(3.4, fy + 6.1, -7.8) * ANG(0, 0, .2), stone, M.Slate)
	K.Part(m, "Wall", V3(3.6, wallTop - fy - 7, .9), at(0, fy + 7 + (wallTop - fy - 7) / 2, -7.8), stone, M.Slate, S())
	-- quoins on the surviving front-left corner, cornice band, a lancet window, a big crack
	for k = 0, 3 do
		K.Part(m, "Quoin", V3(k % 2 == 0 and 1.6 or 1.1, 1.1, .3), at(-7.15 + (k % 2 == 0 and 0 or -.25), fy + 1 + k * 2.2, -8.35), C(130, 130, 142), M.Slate)
	end
	K.Part(m, "Cornice", V3(7, .45, 1.3), at(-4.5, wallTop - .1, -8.1), C(124, 124, 136), M.Slate)
	K.Part(m, "LancetFrame", V3(1.6, 4, .3), at(-4.6, fy + 3.6, -8.32), C(124, 124, 136), M.Slate)
	K.Part(m, "LancetGlass", V3(1, 3.4, .1), at(-4.6, fy + 3.5, -8.45), Y.GLOW_DIM.Purple, M.Neon)
	Y.GableTri(m, "LancetTop", at(-4.6, fy + 5.6, -8.32) * ANG(0, PI / 2, 0), 1.6, .9, .3, C(124, 124, 136), M.Slate)
	for _, c in ipairs({ { -2.6, 8.6, .3, 2.2 }, { -3.1, 6.6, -.5, 2 }, { -2.5, 4.7, .2, 1.6 } }) do
		K.Part(m, "Crack", V3(.14, c[4], .06), at(c[1], c[2], -8.29) * ANG(0, 0, c[3]), C(36, 34, 44), M.SmoothPlastic)
	end
	Y.Vine(m, (at(-7.9, wallTop, -8.4)).Position, (at(-7.9, fy + 2, -8.6)).Position, rng, V3(0, 0, -1))
	-- pointed door arch + dark interior + fallen door leaf
	Y.GableTri(m, "DoorArch", at(0, fy + 6.2, -8.3) * ANG(0, PI / 2, 0), 4.2, 1.6, .5, C(124, 124, 136), M.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "DoorJamb", V3(.6, 6.2, .5), at(sx * 2, fy + 3.1, -8.3), C(124, 124, 136), M.Slate)
	end
	-- the ruin can be entered: dark floor, a cracked sarcophagus lit purple from inside, candles
	K.Part(m, "CryptFloor", V3(14.6, .1, 14.6), at(0, fy + .05, 0), C(40, 36, 48), M.Slate)
	local sar = at(0, fy, 3.2)
	K.Part(m, "Sarcophagus", V3(3.4, 2.2, 6.4), sar * CF(0, 1.1, 0), C(120, 118, 132), M.Marble, S())
	K.Part(m, "SarcophagusLid", V3(3.8, .5, 6.8), sar * CF(.7, 2.45, -.4) * ANG(0, .22, .05), C(140, 138, 152), M.Marble)
	K.Part(m, "SarcophagusGlow", V3(2.6, .1, 5.4), sar * CF(0, 2.15, 0), Y.GLOW_DIM.Purple, M.Neon)
	Y.Skull(m, sar * CF(0, 2.9, -2.6) * ANG(-.2, .3, 0), .9, Y.GLOW.Purple)
	local ig = K.Part(m, "CryptGlow", V3(.3, .3, .3), sar * CF(0, 3.4, 0), Y.GLOW.Purple, M.Neon, { Transparency = 1 })
	K.Light(ig, Y.GLOW.Purple, 13, 1)
	K.Candles(m, at(-3.2, fy, 5.6), 3, rng, { Light = false, Spread = .5 })
	Y.Cobweb(m, at(-7.3, wallTop - .4, -7.3) * ANG(0, PI, 0), 2.2)
	K.Part(m, "FallenDoor", V3(3.2, .35, 6.2), at(-.6, .45, -11.5) * ANG(.08, .3, .05), C(66, 46, 40), M.WoodPlanks)
	K.Part(m, "FallenDoorBand", V3(3.25, .1, .3), at(-.6, .66, -10.4) * ANG(.08, .3, .05), IRON, M.CorrodedMetal)
	-- front-gabled roof: left slope intact, right slope broken (bare rafters)
	local rise = 5.2
	local span = 8.3
	local slope = math.sqrt(rise * rise + span * span)
	for _, s in ipairs({ -1, 1 }) do
		local ridge = at(0, wallTop + rise, 0)
		if s == -1 then
			local a = (at(0, wallTop + rise + .35, -8.8)).Position
			local b = (at(-span - .8, wallTop - .45, -8.8)).Position
			local a2 = (at(0, wallTop + rise + .35, 8.8)).Position
			local mid = (a + a2) / 2
			local eave = (at(-span - .8, wallTop - .45, 0)).Position
			local roof = K.Bar(m, "RoofPlane", mid, eave, 17.6, .45, C(52, 50, 66), M.Slate, S())
			local Ls = (eave - mid).Magnitude
			for r = 1, 4 do
				K.Part(m, "Shingles", V3(17.6, .2, Ls / 4 + .3), roof.CFrame * CF(0, .3, Ls / 2 - (r - .5) * Ls / 4) * ANG(.06, 0, 0), C(60, 56, 76):Lerp(P.Ink, r * .06), M.Slate)
			end
			local _ = { ridge, b }
		else
			-- intact strip near the back + exposed rafters at the collapsed front
			local ra, rb = (at(0, wallTop + rise + .35, 3.4)).Position, (at(span + .8, wallTop - .45, 3.4)).Position
			local roof = K.Bar(m, "RoofPlane", ra, rb, 10.8, .45, C(52, 50, 66), M.Slate, S())
			local Ls = (rb - ra).Magnitude
			for r = 1, 3 do
				K.Part(m, "Shingles", V3(10.8, .2, Ls / 3 + .3), roof.CFrame * CF(0, .3, Ls / 2 - (r - .5) * Ls / 3) * ANG(.06, 0, 0), C(60, 56, 76):Lerp(P.Ink, r * .06), M.Slate)
			end
			for k = 0, 2 do
				local z = -7.6 + k * 2.6
				K.Bar(m, "Rafter", (at(0, wallTop + rise, z)).Position, (at(span * (k == 0 and .55 or .95), wallTop + rise * (k == 0 and .45 or .05), z)).Position, .35, .4, C(74, 56, 46), M.Wood)
			end
		end
	end
	K.Part(m, "RidgeBeam", V3(.5, .5, 17.8), at(0, wallTop + rise + .3, 0), C(74, 56, 46), M.Wood)
	Y.GableTri(m, "Gable", at(0, wallTop, 7.8) * ANG(0, PI / 2, 0), span * 2, rise, .9, stone, M.Slate, true)
	K.Wedge(m, "Gable", V3(.9, rise, span), at(0, wallTop, -7.8) * ANG(0, PI / 2, 0) * CF(0, rise / 2, -span / 2), stone, M.Slate, S())
	-- rose window in the (half-surviving) front gable area, bell cote on the back gable
	local rw = at(-1.6, wallTop + 1.1, -8.3)
	K.CylZ(m, "RoseFrame", .3, 2.6, rw, C(124, 124, 136), M.Slate)
	K.CylZ(m, "RoseGlass", .1, 2.1, rw * CF(0, 0, -.12), Y.GLOW.Purple, M.Neon, { Attrs = { HwLantern = "Purple" } })
	K.Part(m, "RoseMullion", V3(2.1, .16, .1), rw * CF(0, 0, -.2), C(124, 124, 136), M.Slate)
	K.Part(m, "RoseMullion", V3(.16, 2.1, .1), rw * CF(0, 0, -.2), C(124, 124, 136), M.Slate)
	local bc = at(0, wallTop + rise * .5, 8.2)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "BellCotePier", V3(.6, 3.4, .8), bc * CF(sx * 1.2, 4.2, 0), stone, M.Slate)
	end
	K.Part(m, "BellCoteTop", V3(3.2, .5, 1.1), bc * CF(0, 6.1, 0), C(124, 124, 136), M.Slate)
	Y.GableTri(m, "BellCoteRoof", bc * CF(0, 6.35, 0) * ANG(0, PI / 2, 0), 3.2, 1.1, 1.1, C(52, 50, 66), M.Slate)
	K.CylY(m, "Bell", 1.2, 1.2, bc * CF(0, 4.8, 0), C(110, 86, 50), M.Metal)
	K.CylY(m, "BellLip", .2, 1.45, bc * CF(0, 4.2, 0), C(110, 86, 50), M.Metal)
	local cote = K.Part(m, "BellCoteFinial", V3(.3, 1, .3), bc * CF(0, 7.4, 0), IRON, M.CorrodedMetal)
	K.Attach(cote, "CrowPerch", CF(0, .6, 0))
	-- buttresses (left side + back), gargoyles on the front corners
	for _, z in ipairs({ -4, 2.5 }) do
		K.Part(m, "Buttress", V3(1.4, 7, 1.5), at(-8.7, fy + 3.5, z), dark, M.Slate, S())
		K.Wedge(m, "ButtressTop", V3(1.5, 1.4, 1.4), at(-8.7, fy + 7.7, z) * ANG(0, PI / 2, 0), dark, M.Slate)
	end
	gargoyle(m, at(-7.6, wallTop + .1, -8.1))
	local gl = K.Part(m, "GargoyleLedge", V3(1.6, .3, 2.2), at(-7.6, wallTop - .1, -7.9), C(124, 124, 136), M.Slate)
	K.Attach(gl, "BatRoost", CF(0, -.6, .4))
	-- the fallen gargoyle in the rubble + rubble pile at the collapsed corner
	gargoyle(m, at(9.6, .25, -10.2) * ANG(.2, 2.4, 1.2))
	for k = 1, 9 do
		local r = rng:NextNumber(0, 3.2)
		local a = rng:NextNumber(-PI * .9, PI * .2)
		K.Part(m, "Rubble", V3(rng:NextNumber(.8, 1.8), rng:NextNumber(.5, 1.2), rng:NextNumber(.8, 1.6)),
			at(7.4 + math.cos(a) * r, .45 + rng:NextNumber(0, .5), -9 + math.sin(a) * r) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3)),
			stone:Lerp(dark, rng:NextNumber(0, 1)), M.Slate, k <= 4 and S() or nil)
	end
	-- roots creeping over the roof and down the left wall
	local root = C(58, 46, 44)
	local pts = { at(-9.5, .3, 9.4), at(-8.4, 6, 8.7), at(-6, wallTop + 2.6, 6.2), at(-2.6, wallTop + 4.4, 3), at(0, wallTop + 5.4, 1.4) }
	for k = 1, #pts - 1 do
		K.Rod(m, "Root", pts[k].Position, pts[k + 1].Position, .9 - k * .14, root, M.Wood)
	end
	local pts2 = { at(-8.3, wallTop + .2, 4), at(-8.4, 7, -1), at(-8.5, 3.6, -3.5), at(-9.3, .3, -6.2) }
	for k = 1, #pts2 - 1 do
		K.Rod(m, "Root", pts2[k].Position, pts2[k + 1].Position, .55 - k * .08, root, M.Wood)
	end
	K.Rod(m, "Root", at(-6, wallTop + 2.6, 6.2).Position, at(-4.5, wallTop + 1.4, 9.4).Position, .4, root, M.Wood)
	Y.Tree(m, at(-10.4, .2, 9.6), 11, Y.Rng(4711), { Perches = 2, Spread = 5, Bats = true })
	Y.Marker(m, "FogPoint", (at(2, .4, -12)).Position)
	Y.Marker(m, "FogPoint", (at(9.5, .4, -12.5)).Position)
	return m
end

------------------------------------------------------------------------------------------------------------------
local function cryptC(parent, spec, rng)
	local m = K.Model(parent, "CryptC")
	local cx, cz = (spec.X0 + spec.X1) / 2, (spec.Z0 + spec.Z1) / 2
	local O = CF(cx, .2, cz - .3)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local stone = C(118, 114, 130)
	local dark = C(82, 80, 94)
	K.Part(m, "Plinth", V3(15.2, .8, 9.4), at(0, .4, 0), dark, M.Cobblestone, S())
	K.Part(m, "Step", V3(5, .4, 1), at(0, .2, -5.1), dark, M.Slate, S())
	local body = K.Part(m, "Body", V3(10, 6.2, 6.4), at(0, .8 + 3.1, .8), stone, M.Slate, S())
	local _ = body
	for _, c in ipairs({ { -5, -2.4 }, { 5, -2.4 }, { -5, 4 }, { 5, 4 } }) do
		K.Part(m, "Pilaster", V3(1, 6.4, 1), at(c[1], .8 + 3.2, c[2]), C(140, 136, 152), M.Slate)
	end
	K.Part(m, "Cornice", V3(11, .6, 7.4), at(0, 7.3, .8), C(140, 136, 152), M.Slate)
	-- small portico: two columns + pediment over the grille door
	for _, sx in ipairs({ -1, 1 }) do
		K.CylY(m, "Column", 5.6, .8, at(sx * 2.3, .8 + 2.8, -3.4), C(150, 146, 160), M.Marble, S())
	end
	K.Part(m, "PorticoBeam", V3(6, .6, 2), at(0, 6.9, -3.1), C(140, 136, 152), M.Slate)
	Y.GableTri(m, "Pediment", at(0, 7.2, -3.4) * ANG(0, PI / 2, 0), 6.4, 1.8, .9, stone, M.Slate)
	K.Part(m, "DoorDark", V3(2.6, 4.4, .1), at(0, .8 + 2.2, -2.45), C(16, 10, 22), M.SmoothPlastic)
	for b = -2, 2 do
		K.Part(m, "GrilleBar", V3(.12, 4.4, .12), at(b * .55, .8 + 2.2, -2.6), IRON, M.CorrodedMetal)
	end
	for _, yy in ipairs({ 1.2, 3.4, 5 }) do
		K.Part(m, "GrilleRail", V3(2.6, .12, .12), at(0, yy, -2.6), IRON, M.CorrodedMetal)
	end
	K.Part(m, "NamePlate", V3(3.4, .7, .1), at(0, 5.7, -2.5), C(170, 150, 100), M.Metal)
	-- dome
	K.CylY(m, "DomeDrum", 1.2, 5.6, at(0, 8.2, .8), stone, M.Slate)
	K.CylY(m, "DomeRing", .3, 6, at(0, 8.85, .8), C(140, 136, 152), M.Slate)
	K.Ball(m, "Dome", 5.4, at(0, 8.8, .8), C(74, 66, 96), M.Slate)
	for k = 0, 3 do
		local a = k / 4 * PI * 2
		K.Part(m, "DomeRib", V3(.3, 2.6, .3), at(math.cos(a) * 1.85, 10.25, .8 + math.sin(a) * 1.85) * ANG(math.sin(a) * .62, 0, -math.cos(a) * .62), C(140, 136, 152), M.Slate)
	end
	local fin = K.Ball(m, "DomeFinial", .7, at(0, 11.7, .8), C(150, 146, 160), M.Marble)
	K.CylZ(m, "FinialMoon", .12, 1.1, at(0, 12.6, .8), C(230, 220, 160), M.Neon)
	K.CylZ(m, "FinialMoonCut", .14, .9, at(.3, 12.7, .8), dark, M.Slate)
	K.Attach(fin, "CrowPerch", CF(0, .45, 0))
	-- corner urns on the plinth
	for _, c in ipairs({ { -6.8, -3.8 }, { 6.8, -3.8 } }) do
		K.CylY(m, "CornerUrnFoot", .4, .7, at(c[1], 1, c[2]), stone, M.Slate)
		K.Ellipsoid(m, "CornerUrn", V3(1.2, 1.1, 1.2), at(c[1], 1.7, c[2]), stone, M.Marble)
		K.CylY(m, "CornerUrnRim", .25, .9, at(c[1], 2.25, c[2]), C(140, 136, 152), M.Marble)
	end
	-- a lantern hanging from the portico beam + candles on the step
	K.Part(m, "LanternHook", V3(.1, .6, .1), at(1.4, 6.3, -3.4), IRON, M.CorrodedMetal)
	K.Lantern(m, at(1.4, 4.9, -3.4), Y.GLOW.Orange, "Orange", { Range = 12, Brightness = .8 })
	K.Candles(m, at(-1.6, .4, -5.1), 3, rng, { Light = false, Spread = .4 })
	Y.Cobweb(m, at(-2.5, 6.3, -3.2), 1.6)
	Y.Vine(m, (at(-5.4, 6.6, 2)).Position, (at(-5.6, 1.4, 2.5)).Position, rng, V3(-1, 0, 0))
	K.Attach(K.Part(m, "BatHang", V3(.2, .2, .2), at(0, 6.4, -3.1), P.Ink, nil, { Transparency = 1 }), "BatRoost")
	Y.Marker(m, "FogPoint", (at(4, .4, -6.5)).Position)
	return m
end

return {
	Build = function(ctx)
		local L = ctx.Layout
		local m = K.Model(ctx.Root, "Crypts")
		grand(m, L.Crypts.Grand, Y.Rng(5101))
		cryptB(m, L.Crypts.B, Y.Rng(5202))
		-- the swallowed 34_GardenPolish Broadleaf (green, at x 200 z 720) would stand next to crypt B: hide it (K.Hide
		-- remembers the originals for World.Disable) and plant a dead tree in its place
		local gardens = ctx.District and ctx.District:FindFirstChild("34_GardenPolish")
		local pocket = gardens and gardens:FindFirstChild("PocketGardens")
		for _, t in ipairs(pocket and pocket:GetChildren() or {}) do
			if t.Name == "Broadleaf" then
				local pos
				for _, d in ipairs(t:GetDescendants()) do
					if d:IsA("BasePart") then
						pos = d.CFrame.Position
						break
					end
				end
				if pos and math.abs(pos.X - 200) < 8 and math.abs(pos.Z - 720) < 8 then
					K.Hide(t)
					if ctx.Note then
						ctx.Note("Crypts: hid the green Broadleaf at (200, 720)")
					end
				end
			end
		end
		Y.Tree(m, CF(203.5, L.FloorY, 717.5), 13, Y.Rng(5404), { Perches = 2, Spread = 5.2, Hollow = true, HollowDir = V3(-1, 0, -.3), HollowColor = Y.GLOW.Purple })
		cryptC(m, L.Crypts.C, Y.Rng(5303))
	end,
}
