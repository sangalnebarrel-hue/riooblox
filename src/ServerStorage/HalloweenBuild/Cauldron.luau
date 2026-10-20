-- THE DEAD YARD — HAUNTED CAULDRON (WP1). Build-time builder (hw/edits/deadyard.luau → tools/sim.luau), saved in the place
-- as Workspace.DOGROTS_District.38_DeadYard.Cauldron. Social hub at Layout.Cauldron.Center (128, 0.2, 612).
--   * stone plaza disc r 14 (top 0.5) with two paving rings, a curb ring and an engraved purple rune ring,
--   * fire pit (stone ring, charred logs, green Neon flames: HwBrazier=true + HwCauldronFlame=true, green PointLight #1),
--   * giant iron pot on four clawed legs: ellipsoid belly, neck, rolled rim lip (ChainPoint attachments), riveted bands,
--     moon medallions, ring handles, green drips; Model `Brew` with the Neon `BrewSurface` (SteamPoint attachments) and
--     a few bubbles; an invisible cylinder collider (the belly mesh has no curved collision),
--   * timber tripod with iron lashing, three chains to the rim, a hanging purple K.Lantern (PointLight #2), crescent finial,
--   * 8 rune stones (`Rune1`..`Rune8` dim purple Neon parts with a `RunePoint` attachment; CauldronFX lights them),
--   * pumpkins, candle clusters (HwCandle, unlit), bones, a dog skull, potion bottles, spilled candy.
-- The four cardinal approaches (lane walk -Z, pit walk +Z, side tracks ±X) stay open.
local K = require(script.Parent.Kit)
local P = K.Palette
local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local M = Enum.Material

local Cauldron = {}

local function Rng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r:NextNumber(a: number?, b: number?): number
		state = (state * 48271) % 2147483647
		local u = (state - 1) / 2147483646
		if a == nil then
			return u
		end
		return a + (b - a) * u
	end
	function r:NextInteger(a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return r
end

local IRON = C(44, 44, 54)
local IRON_HI = C(70, 70, 84)
local RUST = C(112, 60, 42)
local BRONZE = C(150, 104, 52)
local TOXIC = C(150, 255, 70)
local TOXIC_HI = C(210, 255, 160)
local RUNE_DIM = C(64, 34, 104)
local GLOW = C(150, 80, 235)
local TIMBER = C(70, 50, 40)
local BONE = P.Bone
local BONE_DARK = C(204, 190, 158)

local function chain(parent, a: Vector3, b: Vector3, sag: number, linkLen: number?)
	local m = K.Model(parent, "Chain")
	local len = (b - a).Magnitude
	local n = math.max(3, math.floor(len / (linkLen or .62) + .5))
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - V(0, math.sin(t * math.pi) * sag, 0)
		local link = K.Bar(m, "ChainLink", prev, p, .16, .4, IRON:Lerp(RUST, .3), M.CorrodedMetal)
		link.Size = link.Size + V(0, 0, .12)
		if i % 2 == 0 then
			link.CFrame = link.CFrame * ANG(0, 0, math.pi / 2)
		end
		prev = p
	end
	return m
end

local function bone(parent, a: Vector3, b: Vector3, d: number, color: Color3)
	local m = K.Model(parent, "Bone")
	K.Rod(m, "BoneShaft", a, b, d, color, M.SmoothPlastic)
	local dir = (b - a).Unit
	local s = dir:Cross(V(0, 1, 0))
	if s.Magnitude < .1 then
		s = V(1, 0, 0)
	end
	s = s.Unit
	for _, e in { a - dir * d * .2, b + dir * d * .2 } do
		K.Ball(m, "BoneKnob", d * 1.45, CF(e + s * d * .5), color, M.SmoothPlastic)
		K.Ball(m, "BoneKnob", d * 1.45, CF(e - s * d * .5), color, M.SmoothPlastic)
	end
	return m
end

local function dogSkull(parent, cf: CFrame, s: number, eye: Color3)
	local m = K.Model(parent, "DogSkull")
	local function at(x, y, z)
		return cf * CF(x * s, y * s, z * s)
	end
	K.Ellipsoid(m, "SkullCranium", V(2.2 * s, 1.9 * s, 2.3 * s), at(0, 1.05, .2), BONE, M.SmoothPlastic)
	K.Part(m, "SkullBrow", V(1.9 * s, .36 * s, .7 * s), at(0, 1.38, -.72), BONE_DARK, M.SmoothPlastic)
	K.Part(m, "SkullMuzzle", V(1.12 * s, .72 * s, 1.55 * s), at(0, .62, -1.45), BONE, M.SmoothPlastic)
	K.Wedge(m, "SkullBridge", V(1.12 * s, .42 * s, 1.35 * s), at(0, 1.19, -1.38), BONE, M.SmoothPlastic)
	K.Part(m, "SkullNose", V(.56 * s, .32 * s, .22 * s), at(0, .9, -2.22), P.Ink, M.SmoothPlastic)
	K.Part(m, "SkullJaw", V(1.0 * s, .3 * s, 1.4 * s), at(0, .13, -1.3), BONE_DARK, M.SmoothPlastic)
	for _, sx in { -1, 1 } do
		K.Ellipsoid(m, "SkullSocket", V(.66 * s, .58 * s, .34 * s), at(sx * .5, 1.08, -.98), P.Ink, M.SmoothPlastic)
		K.Ball(m, "SkullEye", .3 * s, at(sx * .5, 1.08, -1.1), eye, M.Neon)
		K.Wedge(m, "SkullEar", V(.28 * s, 1.0 * s, .78 * s), at(sx * .78, 2.12, .35) * ANG(0, sx * math.pi / 2, 0), BONE_DARK, M.SmoothPlastic)
	end
	return m
end

-- plain small pumpkin (2 parts, no light)
local function smallPumpkin(parent, pos: Vector3, d: number, rng)
	K.Ellipsoid(parent, "SmallPumpkin", V(d, d * .72, d), CF(pos + V(0, d * .34, 0)) * ANG(0, rng:NextNumber(0, 3), 0),
		P.Pumpkin:Lerp(P.PumpkinDark, rng:NextNumber(.05, .5)), M.SmoothPlastic)
	K.CylY(parent, "SmallPumpkinStem", d * .28, d * .13, CF(pos + V(0, d * .78, 0)) * ANG(rng:NextNumber(-.3, .3), 0, rng:NextNumber(-.3, .3)), P.Stem, M.Wood)
end

function Cauldron.Build(ctx)
	local L = ctx.Layout
	local rng = Rng(7213)
	local LC = L.Cauldron
	local O = V(LC.Center.X, 0, LC.Center.Z)
	local PT = .5 -- plaza top
	local root = K.Model(ctx.Root, "Cauldron")
	local plaza = K.Model(root, "Plaza")
	local pot = K.Model(root, "Pot")
	local deco = K.Model(root, "Decor")
	local lights = 0
	local function polar(r, a, y)
		return V(O.X + math.cos(a) * r, y or 0, O.Z + math.sin(a) * r)
	end

	------------------------------------------------------------------------------------------------ plaza
	K.CylY(plaza, "PlazaDisc", PT + .3, LC.PlazaRadius * 2, CF(O.X, (PT - .3) / 2, O.Z), C(54, 50, 64), M.Slate, { Solid = true })
	-- curb ring
	local nCurb = 28
	for i = 1, nCurb do
		local a = (i - .5) / nCurb * math.pi * 2
		local r = LC.PlazaRadius - .45
		local arc = 2 * math.pi * r / nCurb
		K.Part(plaza, "PlazaCurb", V(.9, .32, arc - .12), CF(polar(r, a, PT - .08)) * ANG(0, -a, 0), C(92, 88, 104):Lerp(C(70, 66, 82), rng:NextNumber(0, .6)), M.Cobblestone)
	end
	-- paving rings (gaps show the dark base as grout)
	local function ring(r0, r1, n, top, colA, colB)
		local rm = (r0 + r1) / 2
		local arc = 2 * math.pi * rm / n
		local off = rng:NextNumber(0, 1)
		for i = 1, n do
			local a = (i - .5 + off) / n * math.pi * 2
			K.Part(plaza, "PlazaSlab", V(r1 - r0 - .18, .06, arc - .2), CF(polar(rm, a, top - .03)) * ANG(0, -a + rng:NextNumber(-.02, .02), 0),
				colA:Lerp(colB, rng:NextNumber(0, 1)), M.Slate)
		end
	end
	ring(9.5, 12.5, 22, PT + .03, C(82, 78, 94), C(104, 100, 116))
	ring(6.9, 9.5, 16, PT + .03, C(74, 70, 86), C(96, 92, 108))
	-- engraved rune ring (dim purple neon segments, flush)
	local nRune = 30
	local rr = 12.95
	for i = 1, nRune do
		if i % 5 ~= 0 then
			local a0, a1 = (i - 1) / nRune * math.pi * 2, (i - .15) / nRune * math.pi * 2
			K.Bar(plaza, "RuneRing", polar(rr, a0, PT + .04), polar(rr, a1, PT + .04), .16, .06, C(110, 56, 190), M.Neon, { Transparency = .25 })
		else
			-- small glyph: a tick across the ring
			local a = (i - .6) / nRune * math.pi * 2
			K.Bar(plaza, "RuneGlyph", polar(rr - .35, a, PT + .04), polar(rr + .35, a, PT + .04), .14, .06, C(110, 56, 190), M.Neon, { Transparency = .25 })
		end
	end

	------------------------------------------------------------------------------------------------ fire pit
	local fire = K.Model(root, "FirePit")
	K.Ellipsoid(fire, "Ashes", V(12.6, .16, 12.6), CF(O.X, PT + .01, O.Z), C(30, 26, 32), M.Ground)
	local nStones = 15
	for i = 1, nStones do
		local a = (i - .5) / nStones * math.pi * 2 + rng:NextNumber(-.06, .06)
		local s = rng:NextNumber(1.1, 1.5)
		K.Ellipsoid(fire, "FireStone", V(s * 1.15, s * .72, s), CF(polar(6.3, a, PT + s * .22)) * ANG(0, -a, 0), C(72, 68, 82):Lerp(C(46, 42, 54), rng:NextNumber(0, 1)), M.Slate, { Solid = true })
	end
	for i = 1, 4 do
		local a = (i - .5) / 4 * math.pi * 2 + .3
		local p0, p1 = polar(1.2, a, PT + .32), polar(5.0, a, PT + .32)
		K.Rod(fire, "CharredLog", p0, p1, .7, C(44, 30, 26):Lerp(C(26, 20, 20), rng:NextNumber(0, 1)), M.Wood)
		K.Ball(fire, "Ember", .42, CF(polar(rng:NextNumber(2.2, 4.4), a + .25, PT + .25)), C(255, 140, 50), M.Neon)
	end
	-- glowing fire bed + core flame under the pot + clusters of slim tongues licking up the belly between the legs
	K.Ellipsoid(fire, "FireBed", V(9.6, .14, 9.6), CF(O.X, PT + .1, O.Z), C(60, 170, 60), M.Neon, { Transparency = .15 })
	local flameCore = K.Ellipsoid(fire, "CauldronFlame", V(2.6, 1.5, 2.6), CF(O.X, PT + .85, O.Z), TOXIC_HI, M.Neon,
		{ Attrs = { HwBrazier = true, HwCauldronFlame = true } })
	for i = 1, 8 do
		local a = (i - .5) / 8 * math.pi * 2 + rng:NextNumber(-.1, .1)
		local r = rng:NextNumber(4.7, 5.2)
		local out = V(math.cos(a), 0, math.sin(a))
		local tan = V(-out.Z, 0, out.X)
		for k = -1, 1 do
			local h = (k == 0) and rng:NextNumber(3.0, 3.9) or rng:NextNumber(1.7, 2.6)
			local w = (k == 0) and .85 or .62
			local base = polar(r, a, PT + .15) + tan * k * .5
			local col = (k == 0) and TOXIC or TOXIC:Lerp(C(70, 210, 90), rng:NextNumber(.2, .6))
			local tilt = ANG(out.Z * .16 + tan.Z * k * .22, 0, -(out.X * .16 + tan.X * k * .22))
			K.Ellipsoid(fire, k == 0 and "CauldronFlame" or "CauldronFlameSide", V(w, h, w), CF(base + V(0, h * .45, 0)) * tilt, col, M.Neon,
				{ Attrs = { HwBrazier = true, HwCauldronFlame = true } })
		end
	end
	K.Light(flameCore, C(120, 255, 90), 22, 1.6)
	lights += 1

	------------------------------------------------------------------------------------------------ the pot
	local BY = 4.0 -- belly centre
	local BR = 5.5 -- belly radius
	local BH = 2.7 -- belly half height
	-- clawed legs
	for i = 1, 4 do
		local a = (i - .5) / 4 * math.pi * 2 -- diagonals (45, 135, 225, 315 deg): the cardinal faces stay free
		local top, foot = polar(3.3, a, 2.4), polar(4.6, a, PT + .55)
		K.Rod(pot, "PotLeg", top, foot, .95, IRON, M.CorrodedMetal)
		K.Ball(pot, "PotKnee", 1.15, CF(top:Lerp(foot, .45)), IRON_HI, M.CorrodedMetal)
		K.Ellipsoid(pot, "PotPaw", V(1.5, .7, 1.5), CF(foot - V(0, .25, 0)), IRON, M.CorrodedMetal)
		for k = -1, 1 do
			local ca = a + k * .45
			local cp = foot + V(math.cos(ca) * .85, -.35, math.sin(ca) * .85)
			K.Wedge(pot, "PotClaw", V(.26, .42, .7), CF(cp) * ANG(0, -ca - math.pi / 2, 0), C(200, 190, 170), M.SmoothPlastic)
		end
	end
	K.Ellipsoid(pot, "PotBelly", V(BR * 2, BH * 2, BR * 2), CF(O.X, BY, O.Z), IRON, M.CorrodedMetal)
	K.CylY(pot, "PotNeck", 1.5, 9.6, CF(O.X, 5.85, O.Z), IRON, M.CorrodedMetal)
	-- rolled rim lip (ring of short cylinders)
	local lipR, lipY, nLip = 4.85, 6.78, 18
	local lipParts = {}
	for i = 1, nLip do
		local a0, a1 = (i - 1) / nLip * math.pi * 2, i / nLip * math.pi * 2
		local seg = K.Rod(pot, "PotLip", polar(lipR, a0, lipY), polar(lipR, a1, lipY), .86, IRON_HI:Lerp(RUST, (i % 3 == 0) and .35 or .1), M.CorrodedMetal)
		seg.Size += V(.14, 0, 0)
		table.insert(lipParts, seg)
	end
	for i = 1, 8 do
		local seg = lipParts[math.floor((i - 1) * nLip / 8) + 1]
		K.Attach(seg, "ChainPoint", CF(0, .45, 0))
	end
	-- bands + rivets
	K.CylY(pot, "PotBand", .5, BR * 2 + .3, CF(O.X, BY, O.Z), IRON_HI:Lerp(RUST, .25), M.CorrodedMetal)
	local r2 = BR * math.sqrt(1 - (1.55 / BH) ^ 2)
	K.CylY(pot, "PotBand", .4, r2 * 2 + .3, CF(O.X, BY - 1.55, O.Z), IRON_HI:Lerp(RUST, .4), M.CorrodedMetal)
	K.CylY(pot, "PotNeckBand", .3, 9.9, CF(O.X, 6.15, O.Z), IRON_HI, M.CorrodedMetal)
	for i = 1, 18 do
		local a = (i - .5) / 18 * math.pi * 2
		K.Ball(pot, "PotRivet", .34, CF(polar(BR + .15, a, BY)), C(84, 84, 96), M.Metal)
	end
	-- bronze paw medallion on the belly band, facing the lane walk (where players brew)
	do
		local a = math.rad(270)
		local nrm = V(math.cos(a), 0, math.sin(a))
		local c0 = polar(5.78, a, BY + .1)
		local frame = K.Look(c0, c0 + nrm)
		local function disc(name, len, d, off, col, mat)
			return K.CylX(pot, name, len, d, frame * CF(0, 0, -off) * ANG(0, math.pi / 2, 0), col, mat)
		end
		disc("PotMedallion", .22, 2.7, .02, BRONZE, M.Metal)
		disc("PotMedallionInset", .1, 2.2, .14, C(28, 22, 36), M.SmoothPlastic)
		K.Ellipsoid(pot, "PotPawPad", V(.95, .8, .12), frame * CF(0, -.32, -.2), TOXIC, M.Neon)
		for _, t in { { -.62, .22 }, { -.22, .56 }, { .22, .56 }, { .62, .22 } } do
			K.Ellipsoid(pot, "PotPawToe", V(.36, .44, .12), frame * CF(t[1], t[2], -.2), TOXIC, M.Neon)
		end
	end
	-- ring handles
	for _, a in { 0, math.pi } do
		local lug = polar(BR - .2, a, 5.2)
		K.Part(pot, "HandleLug", V(.9, .8, .9), CF(lug) * ANG(0, -a, 0), IRON_HI, M.CorrodedMetal)
		local hc = polar(BR + .3, a, 4.3)
		local tan = V(-math.sin(a), 0, math.cos(a))
		local n = 10
		local prev
		for k = 0, n do
			local t = k / n * math.pi * 2
			local p = hc + tan * math.sin(t) * .95 + V(0, math.cos(t) * .95, 0)
			if prev then
				K.Rod(pot, "HandleRing", prev, p, .26, IRON:Lerp(RUST, .3), M.CorrodedMetal).Size += V(.08, 0, 0)
			end
			prev = p
		end
	end
	-- brew
	local brew = K.Model(root, "Brew")
	local surf = K.Ellipsoid(brew, "BrewSurface", V(9.0, .72, 9.0), CF(O.X, 6.62, O.Z), TOXIC, M.Neon)
	K.Attach(surf, "SteamPoint", CF(0, .6, 0))
	for k = 1, 3 do
		local a = k / 3 * math.pi * 2 + .5
		K.Attach(surf, "SteamPoint", CF(math.cos(a) * 2.3, .5, math.sin(a) * 2.3))
	end
	for _, b in { { 1.6, .4, .9 }, { 2.4, 2.6, .6 }, { 1.0, 4.2, .75 }, { 3.0, 5.2, .5 }, { .3, 1.8, .55 } } do
		K.Ball(brew, "BrewBubble", b[3], CF(polar(b[1], b[2], 6.9 + b[3] * .05)), TOXIC_HI, M.Neon)
	end
	-- green drips over the lip + a small spill on the plaza
	for _, a in { math.rad(300), math.rad(55), math.rad(160) } do
		K.Ellipsoid(pot, "BrewDrip", V(.42, 1.7, .42), CF(polar(4.92, a, 5.75)), TOXIC, M.Neon)
		K.Ball(pot, "BrewDripEnd", .52, CF(polar(5.06, a, 4.95)), TOXIC, M.Neon)
		K.Ellipsoid(pot, "BrewDripLip", V(.62, .34, 1.0), CF(polar(5.15, a, 7.12)) * ANG(0, -a, 0), TOXIC, M.Neon)
	end
	K.Ellipsoid(deco, "BrewSpill", V(2.2, .08, 1.5), CF(polar(7.6, math.rad(300), PT + .07)) * ANG(0, .4, 0), TOXIC:Lerp(C(40, 120, 40), .3), M.Neon, { Transparency = .2 })
	-- giant ladle resting in the brew
	local lb = polar(1.4, math.rad(320), 6.3)
	local lt = polar(7.2, math.rad(320), 8.1)
	K.Rod(pot, "LadleHandle", lb, lt, .36, C(110, 80, 56), M.Wood)
	K.CylY(pot, "LadleRing", .25, .55, CF(lt + (lt - lb).Unit * .1), IRON_HI, M.Metal)
	K.Ellipsoid(pot, "LadleBowl", V(1.6, .7, 1.6), CF(lb + V(0, .15, 0)), C(70, 70, 82), M.Metal)
	-- collider (the belly mesh would collide as a box)
	K.CylY(pot, "PotCollider", 6.9, 10.6, CF(O.X, PT + 3.45, O.Z), IRON, M.SmoothPlastic, { Solid = true, Transparency = 1, Shadow = false })

	------------------------------------------------------------------------------------------------ tripod
	local tri = K.Model(root, "Tripod")
	local APEX = V(O.X, 17.4, O.Z)
	local legA = { math.rad(90), math.rad(210), math.rad(330) }
	for _, a in legA do
		local foot = polar(8.3, a, PT)
		K.Part(tri, "TripodFooting", V(1.9, .7, 1.9), CF(foot + V(0, .2, 0)) * ANG(0, -a, 0), C(70, 66, 80), M.Cobblestone, { Solid = true })
		local top = APEX + (foot - APEX).Unit * -.6
		K.Bar(tri, "TripodLeg", foot + V(0, .2, 0), top, .85, .85, TIMBER:Lerp(C(52, 38, 32), rng:NextNumber(0, .5)), M.Wood, { Solid = true })
		for _, f in { .3, .62 } do
			local p = (foot + V(0, .2, 0)):Lerp(top, f)
			K.Bar(tri, "TripodStrap", p - (top - foot).Unit * .2, p + (top - foot).Unit * .2, 1.0, 1.0, IRON_HI:Lerp(RUST, .3), M.CorrodedMetal)
		end
		-- chain from the apex to the rim
		chain(tri, APEX - V(0, .8, 0) + (foot - APEX).Unit * .35, polar(lipR + .1, a, lipY + .3), .35, .62)
	end
	K.Ball(tri, "ApexKnot", 1.5, CF(APEX), IRON_HI:Lerp(RUST, .35), M.CorrodedMetal)
	K.CylY(tri, "ApexLashing", .7, 1.9, CF(APEX - V(0, .5, 0)), C(90, 70, 50), M.Fabric)
	-- crescent finial facing the gate
	local fin = APEX + V(0, 1.6, 0)
	K.Rod(tri, "FinialSpike", APEX, fin + V(0, .5, 0), .2, IRON, M.CorrodedMetal)
	local toGate = V(L.Gate.Center.X - O.X, 0, L.Gate.Center.Z - O.Z).Unit
	local mf = K.Look(fin + V(0, 1.75, 0), fin + V(0, 1.75, 0) + toGate)
	K.CylX(tri, "FinialMoon", .18, 3.2, mf * ANG(0, math.pi / 2, 0), BONE, M.SmoothPlastic)
	K.CylX(tri, "FinialMoonCut", .2, 2.75, mf * CF(.72, .42, 0) * ANG(0, math.pi / 2, 0), C(40, 30, 54), M.SmoothPlastic)
	K.CylX(tri, "FinialMoonGlow", .1, 3.6, mf * CF(0, 0, .12) * ANG(0, math.pi / 2, 0), GLOW, M.Neon, { Transparency = .1 })
	-- hanging purple lantern (light #2)
	local lanternTop = APEX - V(0, 1.0, 0)
	chain(tri, lanternTop, lanternTop - V(0, 2.4, 0), 0, .55)
	K.Lantern(tri, CF(lanternTop - V(0, 3.9, 0)), C(176, 92, 240), "Purple", { Range = 28, Brightness = 1.25 })
	lights += 1
	local perch = K.Part(tri, "ApexPerch", V(.3, .3, .3), CF(APEX + V(0, .75, 0)), IRON, nil, { Transparency = 1 })
	K.Attach(perch, "CrowPerch", CF(0, .1, 0))

	------------------------------------------------------------------------------------------------ rune stones
	local runes = K.Model(root, "Runes")
	for i = 1, 8 do
		local a = math.rad(22.5 + (i - 1) * 45)
		local out = V(math.cos(a), 0, math.sin(a))
		local base = polar(10.9, a, PT)
		local h = 3.0 + (i % 3) * .3
		local frame = K.Look(base, base + out) * ANG(rng:NextNumber(-.04, .04), 0, rng:NextNumber(-.05, .05))
		local stone = K.Model(runes, "RuneStone" .. i)
		local col = C(70, 66, 84):Lerp(C(88, 84, 102), rng:NextNumber(0, 1))
		K.Part(stone, "RuneStoneBase", V(2.0, .45, 1.4), CF(base + V(0, .22, 0)) * (frame - frame.Position), C(56, 52, 66), M.Cobblestone, { Solid = true })
		K.Part(stone, "RuneStoneBody", V(1.6, h, 1.0), frame * CF(0, .4 + h / 2, 0), col, M.Slate, { Solid = true })
		-- slanted menhir top (alternating direction)
		local sx = (i % 2 == 0) and 1 or -1
		K.Wedge(stone, "RuneStoneTop", V(1.0, .9, 1.6), frame * CF(0, .4 + h + .45, 0) * ANG(0, sx * math.pi / 2, 0), col, M.Slate)
		-- carved algiz-like stave around the glowing rune
		local CARVE = C(30, 24, 40)
		local yc = .4 + h * .58
		K.Part(stone, "RuneCarve", V(.12, h * .72, .06), frame * CF(0, .4 + h * .5, -.51), CARVE, M.Slate)
		for _, d in { -1, 1 } do
			K.Part(stone, "RuneCarve", V(.11, .9, .06), frame * CF(d * .3, yc + .78, -.51) * ANG(0, 0, -d * .62), CARVE, M.Slate)
		end
		local rune = K.Part(stone, "Rune" .. i, V(.8, .8, .1), frame * CF(0, yc, -.56) * ANG(0, 0, math.pi / 4), RUNE_DIM, M.Neon,
			{ Attrs = { RuneIndex = i } })
		K.Attach(rune, "RunePoint", CF(0, 0, -.35))
		-- foot dressing: candles on even stones, a pumpkin on odd ones
		local foot = base + out * 1.25 + V(0, PT, 0) - V(0, PT, 0)
		if i % 2 == 0 then
			K.Candles(stone, CF(foot.X, PT, foot.Z), 3, rng, { Light = false, Spread = .45 })
		else
			smallPumpkin(stone, V(foot.X, PT, foot.Z) + V(-out.Z, 0, out.X) * .6, rng:NextNumber(1.0, 1.4), rng)
		end
	end

	------------------------------------------------------------------------------------------------ dressing
	-- jack-o'-lanterns flanking the lane approach and the gate side
	for _, s in { { 8.3, 256, 2.1 }, { 8.3, 284, 1.8 }, { 12.2, 196, 2.0 }, { 12.0, 340, 1.7 }, { 12.3, 122, 1.9 } } do
		local a = math.rad(s[2])
		local p = polar(s[1], a, PT)
		local face = K.Look(p, p + V(math.cos(a), 0, math.sin(a)))
		K.Pumpkin(deco, face, s[3], { Light = false, Lobes = 5, Glow = C(255, 160, 60) })
	end
	smallPumpkin(deco, polar(12.9, math.rad(250), PT), 1.1, rng)
	smallPumpkin(deco, polar(13.0, math.rad(292), PT), 1.2, rng)
	smallPumpkin(deco, polar(9.0, math.rad(118), PT), 1.0, rng)
	-- candles on the fire-pit stones
	for _, a in { 40, 150, 250 } do
		K.Candles(deco, CF(polar(6.3, math.rad(a), PT + .55)), 2, rng, { Light = false, Spread = .25 })
	end
	-- bones and a dog skull by the south leg
	local bp = polar(9.0, math.rad(80), PT)
	bone(deco, bp + V(-.9, .25, -.4), bp + V(.8, .25, .5), .3, BONE_DARK)
	bone(deco, bp + V(-.4, .55, .7), bp + V(.6, .3, -.9), .26, BONE)
	bone(deco, polar(9.6, math.rad(64), PT + .22), polar(10.0, math.rad(55), PT + .22), .24, BONE_DARK)
	local sk = polar(7.9, math.rad(160), PT)
	K.Part(deco, "SkullRock", V(1.6, .8, 1.4), CF(sk + V(0, .35, 0)) * ANG(0, .5, 0), C(66, 62, 76), M.Slate)
	dogSkull(deco, K.Look(sk + V(0, .75, 0), sk + V(0, .75, 0) + V(math.cos(math.rad(160)), 0, math.sin(math.rad(160)))) * ANG(-.15, 0, 0), .55, TOXIC)
	-- potion bottles by the east stone
	for k, b in { { 0, 0, C(170, 80, 240), 1.0 }, { .7, .35, C(120, 255, 90), .8 }, { -.5, .6, C(255, 120, 40), .7 } } do
		local p = polar(9.6, math.rad(20), PT) + V(b[1], 0, b[2])
		K.Ball(deco, "PotionBody", b[4], CF(p + V(0, b[4] * .45, 0)), b[3], M.Glass, { Transparency = .25 })
		K.CylY(deco, "PotionNeck", b[4] * .45, b[4] * .3, CF(p + V(0, b[4] * 1.05, 0)), b[3]:Lerp(C(255, 255, 255), .2), M.Glass, { Transparency = .3 })
		K.CylY(deco, "PotionCork", .16, b[4] * .32, CF(p + V(0, b[4] * 1.33, 0)), C(140, 100, 60), M.Wood)
		if k == 1 then
			K.Ball(deco, "PotionGlow", b[4] * .55, CF(p + V(0, b[4] * .45, 0)), b[3], M.Neon)
		end
	end
	-- spilled candy near the north approach (the Trick offering)
	local candyCols = { C(255, 128, 24), C(176, 92, 240), C(120, 255, 110), C(255, 220, 90), C(255, 90, 140) }
	for k = 1, 6 do
		local p = polar(rng:NextNumber(7.0, 9.0), math.rad(rng:NextNumber(232, 308)), PT + .2)
		local col = candyCols[(k - 1) % #candyCols + 1]
		local yaw = rng:NextNumber(0, math.pi)
		local c = CF(p) * ANG(0, yaw, 0)
		K.Ellipsoid(deco, "Candy", V(.62, .4, .4), c, col, M.SmoothPlastic)
		K.Wedge(deco, "CandyWrap", V(.3, .34, .3), c * CF(.42, 0, 0) * ANG(0, -math.pi / 2, 0), col:Lerp(C(255, 255, 255), .35), M.SmoothPlastic)
		K.Wedge(deco, "CandyWrap", V(.3, .34, .3), c * CF(-.42, 0, 0) * ANG(0, math.pi / 2, 0), col:Lerp(C(255, 255, 255), .35), M.SmoothPlastic)
	end
	-- an ingredient barrel with mushrooms
	local bar = polar(12.0, math.rad(48), PT)
	K.CylY(deco, "IngredientBarrel", 1.7, 1.5, CF(bar + V(0, .85, 0)), C(86, 60, 44), M.WoodPlanks, { Solid = true })
	K.CylY(deco, "BarrelHoop", .14, 1.56, CF(bar + V(0, .4, 0)), IRON, M.CorrodedMetal)
	K.CylY(deco, "BarrelHoop", .14, 1.56, CF(bar + V(0, 1.3, 0)), IRON, M.CorrodedMetal)
	K.Mushrooms(deco, CF(bar + V(0, 1.7, 0)), 3, rng, C(176, 92, 240))
	K.Mushrooms(deco, CF(polar(13.2, math.rad(150), PT)), 3, rng, P.Neon)

	if ctx.Note then
		ctx.Note(string.format("Cauldron: %d parts, %d lights", K.Count(root), lights))
	end
	return root
end

return Cauldron
