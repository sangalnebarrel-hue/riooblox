-- THE UNDERYARD · sky and the "beneath" ceiling (ServerStorage.UnderyardBuild.Sky, WP-G, Order 11). Build-time only:
-- tools/edits/40_underyard.luau runs it through tools/sim.luau; saved as 40_Underyard.Sky. DESIGN §7.1: no visible sun,
-- a huge pale-blue moon and a black eclipse moon, a cavern-ceiling silhouette ring at the zone edge so the square reads
-- "beneath".
--   * CeilingRing: the upper cavern wall (y ~95..140, continuing Ground's wall) and the overhang lip (y ~138..170)
--     reaching 30..64 studs in over the Bounds, jagged inner edge, with huge stalactites (down to y ~112) and glow-root
--     curtains along it. All non-collide (out of reach above the 60-tall Bounds colliders).
--   * The INVERTED BELFRY: the Dead Yard's bell tower seen from below, hanging upside down out of the north ceiling over
--     the abyss behind the arrival arch (spire pointing down, a dead bell, roots) - the world above, from beneath.
--   * PaleMoon (south-west) and BlackMoon (south-east, violet corona, flare spikes): distant Neon discs facing the
--     square, within 450 studs of the centre so they stream with the zone, high enough to clear the ceiling ring from
--     the plaza and placed beside (not behind) the bell tower as seen from the arrival point. Models carry UyMoon.
--   * Eight drifting rock islands (silhouettes over the chasms, a dead tree / crooked hut / tombstone / lantern on some,
--     dangling roots): Models with ModelStreamingMode Atomic, PrimaryPart = the top slab and attributes UyDrift
--     (bob amplitude, studs) + UyDriftPeriod (s) for the client (UnderyardFX) to animate; static without it.
local U = require(script.Parent.UKit)
local K, Y = U.K, U.Y
local P = U.P
local C = U.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local Sky = { Order = 11 }

-- moon placement: layout azimuth (0 = north, pi/2 = east) and elevation seen from the square centre
local PALE = { Az = math.rad(148), El = math.rad(37), Dist = 420, D = 112 }
local BLACK = { Az = math.rad(214), El = math.rad(49), Dist = 404, D = 72 }

function Sky.Build(ctx)
	local L = ctx.Layout
	local c = L.Centre
	local B = L.Bounds
	local rng = U.Rng(40011)
	local root = ctx.Model("Sky")
	local ring = K.Model(root, "CeilingRing")

	------------------------------------------------------------------------------------------------ ceiling ring
	local function run(a: Vector3, b: Vector3, out: Vector3, name: string)
		local len = (b - a).Magnitude
		local along = (b - a).Unit
		local s = -6
		local k = 0
		while s < len + 6 do
			k += 1
			local w = rng:NextNumber(30, 48)
			local mid = a + along * (s + w / 2)
			-- upper wall (continues Ground's cavern wall, stepping in a little as it rises)
			local wy0, wy1 = 92, rng:NextNumber(136, 146)
			local wd = rng:NextNumber(20, 28)
			local wp = mid + out * (rng:NextNumber(0, 3) + wd / 2) + V3(0, (wy0 + wy1) / 2, 0)
			K.Part(ring, name, V3(w + 4, wy1 - wy0, wd), K.Look(wp, wp + out) * ANG(rng:NextNumber(.02, .07), rng:NextNumber(-.05, .05), 0),
				P.Rock:Lerp(P.RockDark, rng:NextNumber(0, .5)), M.Slate)
			-- the overhang: a thick slab reaching in over the zone, its lip drooping
			local reach = rng:NextNumber(30, 64)
			local th = rng:NextNumber(18, 30)
			local op = mid - out * (reach / 2 - 8) + V3(0, 170 - th / 2 + rng:NextNumber(-2, 4), 0)
			local ocf = K.Look(op, op - out) * ANG(-rng:NextNumber(.04, .12), rng:NextNumber(-.08, .08), rng:NextNumber(-.05, .05))
			K.Part(ring, "CeilingSlab", V3(w + rng:NextNumber(2, 8), th, reach + 16), ocf, P.RockDark:Lerp(P.Rock, rng:NextNumber(0, .4)), M.Slate)
			local lip = ocf * CF(0, -th / 2 + 2, -(reach + 16) / 2 + 3)
			K.Part(ring, "CeilingLip", V3(w * rng:NextNumber(.5, .9), 7, 8), lip * ANG(.25, rng:NextNumber(-.3, .3), 0), P.Rock, M.Slate)
			-- stalactites under the lip and along the slab underside
			local n = rng:NextInteger(1, 2)
			for j = 1, n do
				local t = (j - .5) / n
				local p = (ocf * CF(rng:NextNumber(-w * .4, w * .4), -th / 2 + 1, -(reach + 16) / 2 + 4 + t * reach * .5)).Position
				local big = j == 1 and rng:NextNumber() < .55
				U.Stalactite(ring, p, big and rng:NextNumber(26, 44) or rng:NextNumber(10, 20), big and rng:NextNumber(9, 13) or rng:NextNumber(4.5, 7), rng,
					{ Tiers = big and 3 or 2, Color = P.Rock, Shade = P.RockDark, Glow = (k + j) % 4 == 0 and U.GLOW.Green or nil })
			end
			if k % 3 == 0 then
				local rp = (lip * CF(rng:NextNumber(-w * .3, w * .3), -3, 0)).Position
				U.Roots(ring, rp, rng:NextNumber(18, 34), rng, { Count = 2, Spread = 3, Thick = 1.1, Glow = (k % 4 == 0) and U.GLOW.Green or U.GLOW.Moon })
			end
			s += w
		end
	end
	run(V3(B.X0, 0, B.Z0), V3(B.X1, 0, B.Z0), V3(0, 0, -1), "UpperWallN")
	run(V3(B.X0, 0, B.Z1), V3(B.X1, 0, B.Z1), V3(0, 0, 1), "UpperWallS")
	run(V3(B.X0, 0, B.Z0), V3(B.X0, 0, B.Z1), V3(-1, 0, 0), "UpperWallW")
	run(V3(B.X1, 0, B.Z0), V3(B.X1, 0, B.Z1), V3(1, 0, 0), "UpperWallE")
	for _, cx in ipairs({ B.X0, B.X1 }) do
		for _, cz in ipairs({ B.Z0, B.Z1 }) do
			local inward = V3(cx > 0 and -1 or 1, 0, cz > c.Z and -1 or 1)
			local p = V3(cx, 152, cz) + inward * 26
			K.Part(ring, "CeilingCorner", V3(78, 34, 78), CF(p) * ANG(0, PI / 4 + rng:NextNumber(-.2, .2), 0) * ANG(.05, 0, -.05), P.RockDark, M.Slate)
			U.Stalactite(ring, p + inward * 14 - V3(0, 16, 0), rng:NextNumber(34, 48), rng:NextNumber(11, 15), rng,
				{ Tiers = 3, Color = P.Rock, Shade = P.RockDark, Glow = U.GLOW.Violet })
		end
	end

	------------------------------------------------------------------------------------------------ the inverted belfry
	do
		local m = K.Model(root, "InvertedBelfry")
		local top = V3(0, 166, B.Z0 + 40)
		local T = CF(top) * ANG(0, .12, 0) * ANG(PI + .06, 0, .04) -- local +Y points DOWN (upside down)
		local function at(x, y, z)
			return T * CF(x, y, z)
		end
		local stone, dark = C(70, 66, 84), C(46, 42, 58)
		K.Part(m, "BelfryRock", V3(42, 16, 34), CF(top + V3(0, 4, 0)) * ANG(.08, .3, -.05), P.RockDark, M.Slate)
		-- shaft (downwards), string course, open belfry with a dead bell, spire pointing at the abyss
		K.Part(m, "BelfryShaft", V3(11, 18, 11), at(0, 9, 0), stone, M.Slate)
		for _, cx in ipairs({ -1, 1 }) do
			for _, cz in ipairs({ -1, 1 }) do
				K.Part(m, "BelfryPier", V3(2.4, 18, 2.4), at(cx * 5.2, 9, cz * 5.2), dark, M.Slate)
				K.Part(m, "BelfryPier", V3(2.2, 10, 2.2), at(cx * 4.6, 23, cz * 4.6), dark, M.Slate)
			end
		end
		K.Part(m, "BelfryCourse", V3(13, 1.2, 13), at(0, 18.4, 0), C(110, 106, 124), M.Slate)
		K.Part(m, "BelfryCourse", V3(12.4, 1.2, 12.4), at(0, 28.4, 0), C(110, 106, 124), M.Slate)
		for i = 0, 3 do
			U.GothicWindow(m, at(0, 0, 0) * ANG(0, i * PI / 2, 0) * CF(0, 5, -5.6), 2.2, 7, { Color = U.GLOW.Violet, Lantern = "Purple", Mullion = false })
		end
		U.Bell(m, at(0, 19.5, 0), 1.8, { Name = "DeadBell", Color = C(66, 62, 70) })
		local spireBase = at(0, 29, 0)
		U.Spire(m, "InvertedSpire", spireBase, 10, 30, rng, { Tiers = 6, Color = C(54, 50, 68), Shade = C(40, 36, 52), Curl = .03, Twist = .1,
			Orb = U.GLOW.Violet })
		for k = 1, 4 do
			U.Roots(m, top + V3(rng:NextNumber(-16, 16), -3, rng:NextNumber(-12, 12)), rng:NextNumber(18, 32), rng, { Count = 2, Spread = 3,
				Glow = k % 2 == 0 and U.GLOW.Green or nil })
		end
	end

	------------------------------------------------------------------------------------------------ moons
	local function placeMoon(spec): (CFrame, Vector3)
		local dir = V3(math.sin(spec.Az) * math.cos(spec.El), math.sin(spec.El), -math.cos(spec.Az) * math.cos(spec.El))
		local pos = c + dir * spec.Dist
		return K.Look(pos, c + V3(0, 30, 0)), pos
	end
	do
		local m = K.Model(root, "PaleMoon")
		m:SetAttribute("UyMoon", "Pale")
		local cf = placeMoon(PALE)
		local D = PALE.D
		-- disc faces the square (local -Z); cylinders run along local X, so turn them to face -Z
		local face = cf * ANG(0, PI / 2, 0)
		K.CylX(m, "MoonHalo", 2, D * 1.45, face * CF(-6, 0, 0), C(120, 160, 230), M.Neon, { Transparency = .82 })
		K.CylX(m, "MoonHalo", 2, D * 1.18, face * CF(-4, 0, 0), C(140, 185, 245), M.Neon, { Transparency = .62 })
		local disc = K.CylX(m, "MoonDisc", 4, D, face, U.P.Moon, M.Neon)
		m.PrimaryPart = disc
		for _, cr in ipairs({ { -.24, .05, .24 }, { .18, -.26, .15 }, { .3, .16, .09 }, { -.02, .32, .07 }, { -.3, -.22, .1 } }) do
			K.CylX(m, "MoonCrater", .6, D * cr[3], face * CF(2.3, cr[2] * D, cr[1] * D), C(120, 170, 235), M.Neon)
		end
		K.CylX(m, "MoonShade", .5, D * .9, face * CF(2.1, -D * .03, D * .2), C(132, 180, 240), M.Neon, { Transparency = .45 })
	end
	do
		local m = K.Model(root, "BlackMoon")
		m:SetAttribute("UyMoon", "Black")
		local cf = placeMoon(BLACK)
		local D = BLACK.D
		local face = cf * ANG(0, PI / 2, 0)
		K.CylX(m, "CoronaOuter", 1.5, D * 1.55, face * CF(-5, 0, 0), C(120, 60, 200), M.Neon, { Transparency = .78 })
		K.CylX(m, "Corona", 1.5, D * 1.14, face * CF(-3, 0, 0), C(180, 110, 255), M.Neon, { Transparency = .15 })
		local disc = K.CylX(m, "BlackDisc", 3, D, face, C(10, 6, 16), M.SmoothPlastic)
		m.PrimaryPart = disc
		K.CylX(m, "BlackRim", .6, D * .98, face * CF(1.6, 0, 0), C(26, 16, 40), M.SmoothPlastic)
		for k = 0, 9 do
			local a = k / 10 * PI * 2 + .2
			local len = D * (k % 2 == 0 and .5 or .32)
			-- flare spike: a thin Neon wedge pointing out of the corona (in the disc plane)
			local spike = cf * ANG(0, 0, a) * CF(0, D * .55 + len / 2, 2.5)
			K.Wedge(m, "CoronaFlare", V3(.8, len, 2.2), spike * ANG(0, PI / 2, 0), C(200, 140, 255), M.Neon, { Transparency = .25 })
		end
	end

	------------------------------------------------------------------------------------------------ drifting rock islands
	local ISLES = {
		{ V3(-28, 64, 2236), 1.0, "Tree" }, { V3(44, 92, 2262), .8, "Hut" }, { V3(160, 72, 2396), 1.1, "Grave" },
		{ V3(-158, 58, 2412), 1.0, "Lantern" }, { V3(196, 104, 2318), .7, "Tree" }, { V3(-188, 96, 2660), .9, "Hut" },
		{ V3(120, 118, 2626), .8, "Grave" }, { V3(-40, 128, 2700), 1.2, "Tree" },
	}
	for i, spec in ipairs(ISLES) do
		local m = K.Model(root, "DriftIsland")
		local s = spec[2]
		local base = CF(spec[1]) * ANG(rng:NextNumber(-.06, .06), rng:NextNumber(0, PI * 2), rng:NextNumber(-.06, .06))
		local topSlab = K.Part(m, "IsleTop", V3(16 * s, 2.4, 13 * s), base * CF(0, -1.2, 0), P.RockLight, M.Slate)
		K.Part(m, "IsleMoss", V3(14 * s, .5, 11 * s), base * CF(0, .1, 0) * ANG(0, .2, 0), P.Moss, M.Grass)
		-- the rock body tapers downward to a point
		local cf = base * CF(0, -2.4, 0) * ANG(PI, 0, 0)
		local w, d = 15 * s, 12 * s
		for k = 1, 3 do
			local h = (6 - k) * 1.6 * s
			cf = cf * ANG(rng:NextNumber(-.08, .08), rng:NextNumber(-.3, .3), rng:NextNumber(-.08, .08))
			K.Part(m, "IsleRock", V3(w, h + .6, d), cf * CF(0, h / 2, 0), P.Rock:Lerp(P.RockDark, k / 3), M.Slate)
			cf = cf * CF(0, h, 0)
			w *= .66
			d *= .66
		end
		U.Point(m, "IsleTip", cf, w, 5 * s, P.RockDark)
		U.Roots(m, (base * CF(rng:NextNumber(-3, 3), -4, rng:NextNumber(-3, 3))).Position, 12 * s + 6, rng, { Count = 1, Glow = i % 2 == 0 and U.GLOW.Green or nil })
		local deck = base * CF(rng:NextNumber(-2, 2) * s, 0, rng:NextNumber(-2, 2) * s)
		if spec[3] == "Tree" then
			-- crooked dead tree silhouette: bent trunk and three reaching branches
			local t0 = deck.Position
			local t1 = t0 + V3(rng:NextNumber(-1, 1), 5 * s, rng:NextNumber(-1, 1))
			local t2 = t1 + V3(rng:NextNumber(-1.5, 1.5), 3.5 * s, rng:NextNumber(-1.5, 1.5))
			K.Rod(m, "IsleTree", t0, t1, .9 * s, Y.BARK, M.Wood)
			K.Rod(m, "IsleTree", t1, t2, .65 * s, Y.BARK, M.Wood)
			for k = 1, 3 do
				local a = k / 3 * PI * 2 + rng:NextNumber(-.4, .4)
				local from = k == 1 and t1 or t2
				K.Rod(m, "IsleBranch", from, from + V3(math.cos(a) * 3.2 * s, rng:NextNumber(1, 2.5) * s, math.sin(a) * 3.2 * s), .35 * s, Y.BARK, M.Wood)
			end
		elseif spec[3] == "Hut" then
			-- crooked kennel-hut silhouette with one lit eye window
			local hb = deck * ANG(0, 0, .12)
			K.Part(m, "IsleHut", V3(4.4 * s, 4.6 * s, 4 * s), hb * CF(0, 2.3 * s, 0), C(48, 40, 46), M.WoodPlanks)
			U.CrookedRoof(m, hb * CF(0, 4.6 * s, 0), 4.4 * s, 4 * s, 3.2 * s, rng, { Color = C(36, 30, 40), Overhang = .5, Thick = .4 })
			K.Ball(m, "IsleHutEye", .9 * s, hb * CF(.8 * s, 3 * s, -2.05 * s), U.GLOW.Candle, M.Neon)
		elseif spec[3] == "Grave" then
			Y.Tombstone(m, deck, rng:NextInteger(1, 6), rng, nil, { NoTranslate = true })
			Y.Tombstone(m, deck * CF(3 * s, 0, 1.5) * ANG(0, .4, 0), 4, rng, nil, { NoTranslate = true })
		else
			U.Lantern(m, deck * CF(0, 6, 0), U.GLOW.Moon, "Blue", { Light = false })
			K.CylY(m, "IslePost", 5.5, .4, deck * CF(0, 2.75, 0), P.Iron, M.CorrodedMetal)
		end
		for _, d2 in ipairs(m:GetDescendants()) do
			if d2:IsA("BasePart") then
				d2.CanCollide = false
				d2.CanQuery = false
				d2.CastShadow = false
			end
		end
		m.PrimaryPart = topSlab
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m:SetAttribute("UyDrift", math.floor((1.5 + rng:NextNumber(0, 2.5)) * 10 + .5) / 10)
		m:SetAttribute("UyDriftPeriod", math.floor(rng:NextNumber(8, 15) * 10 + .5) / 10)
	end

	if ctx.Note then
		ctx.Note(string.format("Sky: %d parts (ring %d), pale moon %s, black moon %s", K.Count(root), K.Count(ring), tostring(placeMoon(PALE).Position),
			tostring(placeMoon(BLACK).Position)))
	end
end

return Sky
