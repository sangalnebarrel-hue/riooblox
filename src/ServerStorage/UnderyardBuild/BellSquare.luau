-- THE UNDERYARD · BELL SQUARE (ServerStorage.UnderyardBuild.BellSquare, WP-G, Order 30). Build-time only:
-- tools/edits/40_underyard.luau runs it through tools/sim.luau; saved as 40_Underyard.BellSquare (UyDistrict
-- "BellSquare"). Everything around UnderyardLayout.Square / SealAltars / ArrivalArch, nothing on a gameplay anchor:
--   * Plaza: concentric paving fields (plaza r 62), radial joints, a striped spiral inlay and a faint rune circle round
--     the tower, glowing cracks running out of its foot, a paw trail from the arrival arch.
--   * THE BROKEN BELL TOWER (Square.Tower: base 24 x 24, ~92 tall): a stepped plinth, then three crooked tiers that
--     zigzag (each one twisted and leaning against the one below), stretched lancets, a sealed dog-door, a dog-faced
--     clock and a rose window, gargoyles and mourning dog statues on the buttresses, an open belfry with the HUGE BELL
--     hanging exactly at TowerBell (y 70, lit from inside), and a cracked, broken crown: a jagged stump, the snapped
--     spire caught across it at a crazy angle, rubble, a bent dog weathervane, roots spilling over.
--   * 7 SEAL ALTARS at SealAltars (facing out): stepped base, crooked pedestal, empty socket, Roman numeral plaque, dim
--     rune ring, little seal bell, candles. Ignited state (tag UyShowAtSeal = i): floating bell shard, flames, bright rune
--     ring, light column; socket PointLight tagged UyLightAtSeal = i (saved at full Brightness, UyBaseBrightness).
--   * ARRIVAL ARCH (L.ArrivalArch; its portal plane sits 3.5 studs north of the point so EchoPoint_1 at z 2343 stays
--     clear): crooked pillars, stone + Neon pointed arches, the swirling violet portal disc (Model PortalSwirl,
--     UySwirl = true, Atomic, PrimaryPart hub) with Attachment PortalCentre, dog-skull keystone, two dog statues.
--   * BLACK COFFIN SHRINE (Square.CoffinShrine): stepped dais (east face flush with the coffin's foot), a stone bier, a
--     CLEAR 4 x 2.4 x 7.5 coffin space with Attachment CoffinSeat at its centre (on the bier), 6 candle stands (HwCandle),
--     3 chain anchor rings (Attachments ChainAnchor_1..3), a gothic reredos with a black moon emblem and plaque.
--   * CONTRACTS BOARD, TOLL BOX (crooked collection box with a bell), THE TAILOR OF THE DEAD (striped stall, dress form),
--     PRACTICE RING (flush stone ring + rope posts on the plaza half, the hand bell on its post at TutorialBell, the
--     Mourner pedestal), benches, dog graves, glowing flower planters, candles, crooked lamp posts.
-- Signs are NoTranslate with TextEN / TextRU attributes (localized by the client). Budget: <= 5000 parts, <= 50 lights.
local U = require(script.Parent.UKit)
local K, Y = U.K, U.Y
local P = U.P
local C = U.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi

local BellSquare = { Order = 30 }

-- seal colours (I ECHO .. VII LAST BELL) for the altar ignition
local SEAL_GLOW = {
	C(150, 205, 255), C(255, 170, 80), C(200, 220, 255), C(130, 255, 150), C(190, 120, 255), C(245, 240, 255), C(160, 70, 255),
}
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII" }

local STONE = C(98, 94, 116)
local STONE_D = C(68, 64, 84)
local STONE_L = C(140, 136, 158)
local BRONZE = C(96, 78, 62)

-- one-candle iron stand (candle flame HwCandle); returns the flame
local function candleStand(m: Instance, cf: CFrame, h: number): BasePart
	K.CylY(m, "CandleStand", h, .22, cf * CF(0, h / 2, 0), P.Iron, M.CorrodedMetal)
	K.CylY(m, "CandleDish", .16, .9, cf * CF(0, h, 0), P.Iron, M.CorrodedMetal)
	K.CylY(m, "CandleWax", .9, .34, cf * CF(0, h + .5, 0), P.Wax, M.SmoothPlastic)
	return K.Ellipsoid(m, "CandleFlame", V3(.2, .38, .2), cf * CF(0, h + 1.15, 0), U.GLOW.Candle, M.Neon, { Attrs = { HwCandle = true } })
end

-- small bell hanging from cf (3 parts)
local function miniBell(m: Instance, cf: CFrame, s: number, col: Color3?)
	local c = col or BRONZE
	K.CylY(m, "MiniBell", .9 * s, .9 * s, cf * CF(0, -.5 * s, 0), c, M.Metal)
	K.CylY(m, "MiniBellLip", .25 * s, 1.25 * s, cf * CF(0, -1.0 * s, 0), c:Lerp(P.Ink, .25), M.Metal)
	K.Ball(m, "MiniBellClapper", .32 * s, cf * CF(0, -1.2 * s, 0), P.Iron, M.Metal)
end

function BellSquare.Build(ctx)
	local L = ctx.Layout
	local c = L.Centre
	local SQ = L.Square
	local rng = U.Rng(40030)
	local space = U.Space(L)
	local points = U.Space(L) -- gameplay points only (no set-piece claims): for details placed inside a set piece
	local root = ctx.Model("BellSquare")
	root:SetAttribute("UyDistrict", "BellSquare")
	local lights = 0
	local function light(part: BasePart, color: Color3, range: number, brightness: number): Light
		lights += 1
		return K.Light(part, color, range, brightness)
	end
	-- footprints of the set pieces (decor scattering keeps off them)
	space:Claim(c, 23)
	for _, p in ipairs(L.SealAltars) do
		space:Claim(p, 5.5)
	end
	space:Claim(L.ArrivalArch, 11)
	space:Claim(SQ.CoffinShrine.Position, 10)
	space:Claim((SQ.ContractsBoard * CF(0, 0, 3)).Position, 5.5)
	space:Claim((SQ.TollBox * CF(0, 0, 3.4)).Position, 4)
	space:Claim((SQ.Tailor * CF(0, 0, 6)).Position, 6.5)
	space:Claim(SQ.PracticeRing.Centre, SQ.PracticeRing.Radius + 2.5)

	------------------------------------------------------------------------------------------------ plaza paving
	local plaza = K.Model(root, "Plaza")
	do
		local R = SQ.Plaza.Radius
		local rings = { { R, C(66, 62, 80), .03 }, { 52, C(80, 76, 96), .05 }, { 40, C(60, 56, 74), .07 }, { 28, C(86, 82, 102), .09 } }
		for _, rr in ipairs(rings) do
			K.CylY(plaza, "PlazaPaving", .1, rr[1] * 2, CF(c.X, rr[3] - .05, c.Z), rr[2], M.Slate)
		end
		-- radial joints between the fields (flagstone look)
		for i = 1, 24 do
			local a = (i - .5) / 24 * PI * 2
			K.Bar(plaza, "PavingJoint", U.Polar(c, 28.6, a, .1), U.Polar(c, R - .6, a, .1), .28, .04, C(40, 36, 50), M.Slate)
		end
		-- striped spiral inlay round the tower (1.3 turns from r 18 to r 26.5)
		local prev = U.Polar(c, 18, 0, .11)
		for k = 1, 30 do
			local t = k / 30
			local p = U.Polar(c, 18 + 8.5 * t, t * PI * 2 * 1.3, .11)
			K.Bar(plaza, "SpiralInlay", prev, p, .9, .04, (k % 2 == 0) and P.White or P.Black, M.SmoothPlastic)
			prev = p
		end
		-- faint rune circle and glowing cracks out of the tower foot
		U.RuneRing(plaza, CF(c.X, .12, c.Z), 30.5, { N = 14, Width = .4, H = .04, Color = C(120, 80, 200), Transparency = .45, Glyphs = false })
		for i = 1, 7 do
			local a = (i - .5) / 7 * PI * 2 + .2
			local p0 = U.Polar(c, 17, a, .12)
			local p1 = U.Polar(c, 22 + rng:NextNumber(0, 3), a + rng:NextNumber(-.08, .08), .12)
			local p2 = U.Polar(c, 26 + rng:NextNumber(0, 3), a + rng:NextNumber(-.1, .1), .12)
			K.Bar(plaza, "GlowCrack", p0, p1, .3, .04, U.GLOW.Violet, M.Neon)
			K.Bar(plaza, "GlowCrack", p1, p2, .22, .04, U.GLOW.Violet, M.Neon, { Transparency = .3 })
		end
		-- the paw trail from the arrival arch to the tower door
		U.PawTrail(plaza, { V3(0, .13, L.ArrivalArch.Z + 5), V3(2, .13, c.Z - 30), V3(0, .13, c.Z - 17) }, 3.2, { Size = 1.3, Gait = .7, Color = P.BoneDark,
			Height = 0, Skip = function(p)
				return not space:Free(p, .2) and (p - L.ArrivalArch).Magnitude > 12
			end })
	end

	------------------------------------------------------------------------------------------------ the broken bell tower
	local tower = K.Model(root, "BellTower")
	local T = CF(c.X, 0, c.Z)
	local function face(i: number): CFrame -- i = 0 north (-Z), 1 east, 2 south, 3 west; -Z of the result faces out
		return ANG(0, -i * PI / 2, 0)
	end
	-- quoins: alternating long / short, light / dark corner stones up the four edges of a tier (a little proud)
	local function quoins(frame: CFrame, half: number, y0: number, y1: number)
		for _, cx in ipairs({ -1, 1 }) do
			for _, cz in ipairs({ -1, 1 }) do
				local k, y = 0, y0 + .2
				while y < y1 - 1.1 do
					k += 1
					local long = k % 2 == 0
					K.Part(tower, "Quoin", V3(long and 2.3 or 1.5, 1.1, long and 1.5 or 2.3), frame * CF(cx * (half - .5), y + .55, cz * (half - .5)),
						long and STONE_L or STONE_D, M.Slate)
					y += 1.3
				end
			end
		end
	end
	-- corbel bracket under an overhang (the wall is on +Z of cf, the bracket sticks out to -Z, flat top at cf)
	local function corbel(cf: CFrame, w: number, h: number, d: number)
		K.Wedge(tower, "Corbel", V3(w, h, d), cf * CF(0, -h / 2, -d / 2) * ANG(0, 0, PI), STONE_D, M.Slate)
	end
	-- stepped plinth
	K.Part(tower, "TowerPlinth", V3(30, .8, 30), T * CF(0, .4, 0), STONE_D, M.Slate, { Solid = true })
	K.Part(tower, "TowerPlinth", V3(27.6, .8, 27.6), T * CF(0, 1.2, 0), STONE, M.Slate, { Solid = true })
	K.Part(tower, "TowerPlinth", V3(25.6, .8, 25.6), T * CF(0, 2.0, 0), STONE_L, M.Slate, { Solid = true })

	-- tier A (y 2.4..20.4): the 24 x 24 base, heavy buttresses, the sealed dog-door, lancets
	local A0, A1, HA = 2.4, 20.4, SQ.Tower.Half
	local TA = T
	K.Part(tower, "TowerTierA", V3(HA * 2, A1 - A0, HA * 2), TA * CF(0, (A0 + A1) / 2, 0), STONE, M.Slate, { Solid = true })
	quoins(TA, HA, A0, A1)
	for i = 0, 3 do
		for _, y in ipairs({ 8, 14.5 }) do
			K.Part(tower, "TowerCourse", V3(HA * 2 - 3, .5, .5), TA * face(i) * CF(0, y, -HA), STONE_D, M.Slate)
		end
	end
	for _, cx in ipairs({ -1, 1 }) do
		for _, cz in ipairs({ -1, 1 }) do
			local corner = TA * CF(cx * 13.2, 0, cz * 13.2)
			K.Part(tower, "TowerButtress", V3(6, 13, 6), corner * CF(0, A0 + 6.5, 0) * ANG(0, PI / 4, 0), STONE_D, M.Slate, { Solid = true })
			Y.GableTri(tower, "ButtressCap", corner * CF(0, A0 + 13, 0) * ANG(0, PI / 4, 0), 6.2, 2.2, 6.2, STONE_L, M.Slate)
			local out = V3(cx, 0, cz).Unit
			local seat = (corner * CF(0, A0 + 13.6, 0)).Position + out * .8
			Y.DogStatue(tower, K.Look(seat, seat + out), { Scale = 1.05, Bowed = true, Color = C(150, 148, 166), EyeColor = U.GLOW.Green, Name = "MourningDog" })
		end
	end
	-- the sealed dog-door on the north face: pointed frame, iron-banded leaves, glowing keyhole, chains + padlock
	do
		local f = TA * face(0) * CF(0, A0, -HA)
		local dw, dh = 7, 10.5
		K.Part(tower, "DoorRecess", V3(dw, dh, .4), f * CF(0, dh / 2, .1), P.Ink, M.SmoothPlastic)
		Y.GableTri(tower, "DoorRecessHead", f * CF(0, dh, .1) * ANG(0, PI / 2, 0), dw, 4.2, .4, P.Ink, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			K.Part(tower, "DoorJamb", V3(1.2, dh, 1.1), f * CF(sx * (dw / 2 + .6), dh / 2, -.3), STONE_L, M.Slate)
			K.Bar(tower, "DoorArch", (f * CF(sx * (dw / 2 + .6), dh - .3, -.3)).Position, (f * CF(0, dh + 4.6, -.3)).Position, 1.1, 1.0, STONE_L, M.Slate)
			K.Part(tower, "DoorLeaf", V3(dw / 2 - .15, dh - .4, .3), f * CF(sx * dw / 4, (dh - .4) / 2, -.1), P.WoodDark, M.WoodPlanks)
			for _, y in ipairs({ 2.5, 6, 9 }) do
				K.Part(tower, "DoorStrap", V3(dw / 2 - .6, .35, .12), f * CF(sx * dw / 4, y, -.3), P.Iron, M.CorrodedMetal)
			end
		end
		local key = K.Part(tower, "DoorKeyhole", V3(.5, 1.1, .1), f * CF(.4, 5.2, -.32), U.GLOW.Green, M.Neon)
		light(key, U.GLOW.Green, 10, .8)
		K.Part(tower, "DoorPadlock", V3(1.2, 1.3, .5), f * CF(0, 4.6, -.6), P.Iron, M.CorrodedMetal)
		for _, sx in ipairs({ -1, 1 }) do
			K.Chain(tower, (f * CF(sx * (dw / 2 + .4), 8.2, -.6)).Position, (f * CF(0, 5, -.7)).Position, .4, 7)
		end
		Y.Skull(tower, f * CF(0, dh + 2.6, -.5), 1.5, U.GLOW.Green, P.Bone)
	end
	for _, i in ipairs({ 1, 2, 3 }) do
		U.GothicWindow(tower, TA * face(i) * CF(0, 5.2, -HA), 2.8, 9.6, { Color = U.GLOW.Violet, Lantern = "Purple", Tilt = (i - 2) * .04 })
	end
	K.Part(tower, "StringCourse", V3(HA * 2 + 1.8, 1, HA * 2 + 1.8), TA * CF(0, A1 + .5, 0), STONE_L, M.Slate)

	-- tier B (y ~21..38): twisted 6 degrees and leaning east; twin green lancets, striped banners, gargoyles, pinnacles
	local HB, BH = 10.6, 17
	local TB = TA * CF(1.3, A1 + 1, -.7) * ANG(0, .11, .032)
	K.Part(tower, "TowerTierB", V3(HB * 2, BH, HB * 2), TB * CF(0, BH / 2, 0), STONE:Lerp(STONE_D, .2), M.Slate)
	quoins(TB, HB, 0, BH)
	for i = 0, 3 do
		for _, x in ipairs({ -3.4, 3.4 }) do
			U.GothicWindow(tower, TB * face(i) * CF(x, 2.6, -HB), 2.1, 10.5, { Color = U.GLOW.Green, Lantern = "Green", Tilt = x * .008 })
		end
		local f = TB * face(i) * CF(0, BH - .4, -HB - .35)
		for k = 0, 4 do
			K.Part(tower, "TowerBanner", V3(2.6, 1.4, .08), f * CF(0, -k * 1.4 - .7, 0), k % 2 == 0 and P.Black or P.White, M.Fabric)
		end
		K.Wedge(tower, "TowerBannerTail", V3(.08, 1.3, 1.3), f * CF(-.65, -7.6, 0) * ANG(PI, PI / 2, 0), P.Black, M.Fabric)
		K.Wedge(tower, "TowerBannerTail", V3(.08, 1.3, 1.3), f * CF(.65, -7.6, 0) * ANG(PI, -PI / 2, 0), P.Black, M.Fabric)
	end
	K.Part(tower, "TowerCornice", V3(HB * 2 + 1.8, 1.1, HB * 2 + 1.8), TB * CF(0, BH + .55, 0), STONE_L, M.Slate)
	for k = 0, 3 do
		local a = PI / 4 + k * PI / 2
		local corner = TB * CF(0, BH + 1.1, 0) * ANG(0, a, 0) * CF(0, 0, -HB * 1.34)
		U.Gargoyle(tower, corner * CF(0, 0, -.9), 1.55, { Eye = U.GLOW.Violet })
		local pin = TB * CF(0, BH + 1.1, 0) * ANG(0, a, 0) * CF(0, 0, -HB * 1.22)
		U.Spire(tower, "CornerPinnacle", pin * CF(0, 0, 1.7), 1.7, 7, rng, { Tiers = 3, Color = STONE_L, Shade = STONE, Curl = .14 })
	end
	-- flying struts propping the leaning tower: from the plinth corners up to tier B's corners
	for _, cx in ipairs({ -1, 1 }) do
		for _, cz in ipairs({ -1, 1 }) do
			local foot = (TA * CF(cx * 15.6, .8, cz * 15.6)).Position
			local head = (TB * CF(cx * (HB - .6), 4.5, cz * (HB - .6))).Position
			K.Bar(tower, "TowerStrut", foot, head, 2.3, 2.3, STONE_D, M.Slate, { Solid = true })
			K.Part(tower, "StrutFoot", V3(3.2, 1.2, 3.2), CF(foot + V3(0, .2, 0)) * ANG(0, PI / 4, 0), STONE, M.Slate, { Solid = true })
		end
	end

	-- tier C (y ~39..54): leaning back west, the dog clock (north), the rose window (south), two leaning "ear" turrets
	local HC, CH = 9.3, 15
	local TC = TB * CF(-1.9, BH + 1.1, .9) * ANG(0, .1, -.062)
	K.Part(tower, "TowerTierC", V3(HC * 2, CH, HC * 2), TC * CF(0, CH / 2, 0), STONE, M.Slate)
	quoins(TC, HC, 0, CH)
	do -- dog clock (north): bone dial, ink rim, ticks, crooked hands stuck at a minute to midnight, a bone for the long hand
		local f = TC * face(0) * CF(0, 7.6, -HC)
		K.CylZ(tower, "ClockRim", .5, 11.6, f * CF(0, 0, -.2), P.Ink, M.Slate)
		K.CylZ(tower, "ClockDial", .4, 10.2, f * CF(0, 0, -.42), P.Bone, M.SmoothPlastic)
		for h = 1, 12 do
			local a = h / 12 * PI * 2
			K.Part(tower, "ClockTick", V3(h % 3 == 0 and .7 or .4, h % 3 == 0 and 1.3 or .85, .1), f * ANG(0, 0, -a) * CF(0, 4.2, -.66), P.Ink, M.SmoothPlastic)
		end
		K.Part(tower, "ClockHand", V3(.5, 4.2, .12), f * ANG(0, 0, .18) * CF(0, 1.9, -.78), P.Ink, M.Metal)
		K.Part(tower, "ClockHand", V3(.35, 2.8, .12), f * ANG(0, 0, -.5) * CF(0, 1.2, -.86), P.Ink, M.Metal)
		K.Bone(tower, f * ANG(0, 0, .18) * CF(0, 3.9, -.9), 1.4, P.Bone)
		K.CylZ(tower, "ClockHub", .3, 1.1, f * CF(0, 0, -.95), U.GLOW.Green, M.Neon)
		U.Gargoyle(tower, TC * face(0) * CF(0, CH - .1, -HC - 1.0), 1.0, { Eye = U.GLOW.Green, Wings = false })
	end
	do -- rose window (south)
		local f = TC * face(2) * CF(0, 7.6, -HC)
		K.CylZ(tower, "RoseFrame", .6, 9.8, f * CF(0, 0, -.2), STONE_L, M.Slate)
		K.CylZ(tower, "RoseGlass", .3, 8.4, f * CF(0, 0, -.45), U.GLOW.Violet, M.Neon, { Attrs = { HwLantern = "Purple" } })
		for k = 0, 5 do
			K.Part(tower, "RoseTracery", V3(.4, 8.4, .2), f * ANG(0, 0, k * PI / 6) * CF(0, 0, -.62), STONE_L, M.Slate)
		end
		K.CylZ(tower, "RoseHub", .5, 2.2, f * CF(0, 0, -.7), STONE_L, M.Slate)
	end
	for _, i in ipairs({ 1, 3 }) do -- the "ears": cantilevered round turrets leaning out east and west, curled pointed roofs
		local f = TC * face(i) * CF(0, CH - 6.5, -HC - 1.6)
		corbel(TC * face(i) * CF(0, CH - 6.5, -HC), 4.8, 3.6, 3.2)
		local body = f * ANG(-.34, 0, 0)
		K.CylY(tower, "EarTurret", 7.5, 4.6, body * CF(0, 3.75, 0), STONE_L:Lerp(STONE, .4), M.Slate)
		K.CylY(tower, "EarTurretBand", .6, 5.2, body * CF(0, 6.9, 0), STONE_D, M.Slate)
		K.Part(tower, "EarTurretSlit", V3(.5, 2.2, .3), body * CF(0, 4, -2.25), U.GLOW.Green, M.Neon)
		U.Spire(tower, "EarTurretRoof", body * CF(0, 7.2, 0) * ANG(0, PI / 2, 0), 5.6, 16, rng, { Tiers = 5, Color = C(50, 46, 66), Shade = C(38, 34, 52),
			Curl = .16, Twist = .06, Orb = U.GLOW.Green })
	end
	do -- a glowing crack zig-zagging down the east face of tier C into tier B
		local f = TC * face(1) * CF(0, 0, -HC - .05)
		local pts = { f * CF(-5.5, CH, 0), f * CF(-4, CH - 3, 0), f * CF(-6.5, CH - 6.5, 0), f * CF(-4.5, CH - 10, 0), f * CF(-7, CH - 15, 0) }
		for k = 1, #pts - 1 do
			K.Bar(tower, "TowerCrack", pts[k].Position, pts[k + 1].Position, .35, .12, U.GLOW.Violet, M.Neon)
		end
	end
	K.Part(tower, "TowerCornice", V3(HC * 2 + 1.6, 1, HC * 2 + 1.6), TC * CF(0, CH + .5, 0), STONE_L, M.Slate)

	-- belfry (open, overhanging tier C on corbels): piers, pointed arches, balustrade, beams, THE BELL at TowerBell
	local HD, DH, PW = 12.5, 27, 4.8
	local TD = TC * CF(.9, CH + 1, -.3) * ANG(0, .12, .035)
	K.Part(tower, "BelfryFloor", V3(HD * 2, 1.2, HD * 2), TD * CF(0, .6, 0), STONE_D, M.Slate)
	for i = 0, 3 do
		for k = -2, 2 do
			corbel(TD * face(i) * CF(k * 4.6, 0, -HC + .2), 1.6, 2.6, HD - HC + .3)
		end
	end
	for _, cx in ipairs({ -1, 1 }) do
		for _, cz in ipairs({ -1, 1 }) do
			K.Part(tower, "BelfryPier", V3(PW, DH, PW), TD * CF(cx * (HD - PW / 2), DH / 2, cz * (HD - PW / 2)), STONE, M.Slate)
		end
	end
	local span = HD * 2 - PW * 2 + 1
	for i = 0, 3 do
		local f = TD * face(i) * CF(0, 0, -(HD - PW / 2))
		U.Arch(tower, "BelfryArch", f * CF(0, 12.6, 0), span, PW - .6, 1.3, 4, { Stretch = 1.1, Color = STONE_L })
		for _, sx in ipairs({ -1, 1 }) do
			K.Wedge(tower, "BelfrySpandrel", V3(PW - .8, 6.4, span / 2), f * CF(sx * span / 4, DH - 3.2, 0) * ANG(0, -sx * PI / 2, 0) * ANG(PI, 0, 0), STONE,
				M.Slate)
		end
		K.Part(tower, "BelfryLintel", V3(span + 1, 1.6, PW - .6), f * CF(0, DH - .8, 0), STONE, M.Slate)
		K.Part(tower, "BelfryRail", V3(span, .5, .9), f * CF(0, 3.4, 0), P.Black, M.Slate)
		for k = -2, 2 do
			K.CylY(tower, "BelfryBaluster", 2.2, .55, f * CF(k * span / 5.5, 2.2, 0), P.Bone, M.SmoothPlastic)
		end
	end
	-- THE HUGE BELL: centre exactly at TowerBell, hanging a little out of plumb (mid-swing)
	local bellCF = CF(c.X, SQ.Tower.BellY, c.Z) * ANG(.07, .3, .03)
	local bellTop = SQ.Tower.BellY + 9.7
	local headY = bellTop + 1.1
	local tdY = TD.Position.Y
	for _, cz in ipairs({ -1, 1 }) do
		K.Part(tower, "BellBeam", V3(HD * 2 - 1, 1.8, 1.8), TD * CF(0, headY - 2 - tdY, cz * (HD - PW / 2)), P.WoodDark, M.Wood)
	end
	local hs = CF(c.X, headY, c.Z) * (TD - TD.Position)
	K.Part(tower, "BellHeadstock", V3(2.4, 2.2, HD * 2 - 1), hs, P.WoodDark, M.Wood)
	for _, sz in ipairs({ -1.4, 1.4 }) do
		K.Part(tower, "BellStrap", V3(2.7, 2.6, .5), hs * CF(0, 0, sz), P.Iron, M.CorrodedMetal)
	end
	do
		local bell = K.Model(tower, "TowerBellBody")
		bell:SetAttribute("UyTowerBell", true)
		local prof = { { 6.4, 3.0 }, { 5.0, 4.4 }, { 3.2, 5.1 }, { 1.2, 5.5 }, { -1.0, 5.8 }, { -3.2, 6.2 }, { -5.0, 6.8 }, { -6.3, 7.3 } }
		for i, row in ipairs(prof) do
			K.CylY(bell, "BellBand", 2.3, row[2] * 2, bellCF * CF(0, row[1], 0), BRONZE:Lerp(P.Ink, (i % 2) * .12), M.Metal)
		end
		K.CylY(bell, "BellLip", .7, 15, bellCF * CF(0, -7.2, 0), BRONZE:Lerp(P.Ink, .3), M.Metal)
		K.CylY(bell, "BellMouth", .2, 14, bellCF * CF(0, -7.5, 0), P.Ink, M.SmoothPlastic)
		K.CylY(bell, "BellRunes", .45, 11.9, bellCF * CF(0, 2.2, 0), U.GLOW.Violet, M.Neon, { Transparency = .1 })
		K.CylZ(bell, "BellCrown", 1.2, 3.4, bellCF * CF(0, 8.0, 0), BRONZE:Lerp(P.Ink, .2), M.Metal)
		local cr = { V3(-1.2, 5.2, -4.55), V3(.4, 2.6, -5.6), V3(-.8, -.4, -5.85), V3(.9, -3.6, -6.3), V3(-.2, -6.6, -7.1) }
		for k = 1, #cr - 1 do
			K.Bar(bell, "BellCrack", (bellCF * CF(cr[k])).Position, (bellCF * CF(cr[k + 1])).Position, .4, .2, U.GLOW.Violet, M.Neon)
		end
		K.Rod(bell, "BellClapperRod", (bellCF * CF(0, 4, 0)).Position, (bellCF * CF(.6, -7.2, 0)).Position, .7, P.Iron, M.Metal)
		K.Ball(bell, "BellClapper", 2.2, bellCF * CF(.7, -8, 0), P.Iron, M.Metal)
		local glow = K.Part(bell, "BellGlow", V3(.4, .4, .4), bellCF * CF(0, -2, 0), U.GLOW.Violet, M.Neon, { Transparency = 1 })
		local bl = light(glow, C(170, 110, 255), 44, 2.3)
		bl:SetAttribute("HwKeyLight", true)
	end
	K.Part(tower, "BelfryCornice", V3(HD * 2 + 1.8, 1.2, HD * 2 + 1.8), TD * CF(0, DH + .6, 0), STONE_L, M.Slate)
	for k = 0, 3 do
		local a = PI / 4 + k * PI / 2
		U.Gargoyle(tower, TD * CF(0, DH + 1.2, 0) * ANG(0, a, 0) * CF(0, 0, -HD * 1.36), 1.1, { Eye = U.GLOW.Green })
	end
	-- belfry clearance round the bell (reported; the piers must never touch it)
	local axis = (TD * CF(0, SQ.Tower.BellY - tdY, 0)).Position
	local bellOff = V3(axis.X - c.X, 0, axis.Z - c.Z).Magnitude

	-- the broken crown: jagged parapet, a stepped stump with a ragged top, the snapped spire caught across it
	local TE = TD * CF(0, DH + 1.2, 0) * ANG(0, -.04, 0)
	for i = 0, 3 do
		for k = -2, 2 do
			if not (i == 1 and k == 1) and not (i == 2 and k == -2) and not (i == 0 and k == 2) then -- missing merlons
				local h = rng:NextNumber(1.2, 4.8)
				local blk = K.Part(tower, "CrownMerlon", V3(3.8, h, 1.4), TE * face(i) * CF(k * 4.9, h / 2, -HD + .5), STONE, M.Slate)
				blk.CFrame *= ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.14, .14))
			end
		end
	end
	K.Part(tower, "CrownStump", V3(15, 3, 15), TE * CF(0, 1.5, 0), STONE_D, M.Slate)
	K.Part(tower, "CrownStump", V3(11, 2.8, 11), TE * CF(-.5, 4.4, .3) * ANG(0, .2, .03), STONE, M.Slate)
	K.Part(tower, "CrownStump", V3(7.4, 2.4, 7.4), TE * CF(-1.2, 7, .6) * ANG(0, .35, .06), STONE_D, M.Slate)
	for k = 1, 4 do
		local a = k / 4 * PI * 2
		K.Part(tower, "CrownShard", V3(rng:NextNumber(1.6, 2.6), rng:NextNumber(1.8, 3.8), rng:NextNumber(1.4, 2.4)),
			TE * CF(-1.2 + math.cos(a) * 2.3, 9.2, .6 + math.sin(a) * 2.3) * ANG(rng:NextNumber(-.4, .4), a, rng:NextNumber(-.4, .4)), STONE, M.Slate)
	end
	-- the snapped spire: its broken base on the stump, leaning out over the north-east at ~60 degrees
	local spireBase = TE * CF(2.2, 8.4, -1.6) * ANG(0, PI / 4, 0) * ANG(-1.05, 0, 0)
	U.Spire(tower, "SnappedSpire", spireBase, 6.6, 17, rng, { Tiers = 6, Color = C(58, 54, 74), Shade = C(44, 40, 58), Curl = .05, Twist = .05,
		Orb = U.GLOW.Violet })
	K.Part(tower, "SpireBreak", V3(7, 1.2, 7), spireBase * CF(0, .2, 0) * ANG(.2, .3, .1), STONE_D, M.Slate)
	for k = 1, 3 do
		local a = k * 2.1
		K.Bar(tower, "CrownCrack", (TE * CF(math.cos(a) * 3, 1, math.sin(a) * 3)).Position, (TE * CF(math.cos(a) * 4.5, 8, math.sin(a) * 4.5)).Position, .3, .3,
			U.GLOW.Violet, M.Neon)
	end
	local crownGlow = K.Part(tower, "CrownGlow", V3(.4, .4, .4), TE * CF(0, 6, 0), U.GLOW.Violet, M.Neon, { Transparency = 1 })
	light(crownGlow, U.GLOW.Violet, 26, 1.4)
	for k = 1, 6 do
		local a = rng:NextNumber(0, PI * 2)
		K.Part(tower, "Rubble", V3(rng:NextNumber(.8, 1.6), rng:NextNumber(.6, 1.1), rng:NextNumber(.8, 1.6)),
			TE * CF(math.cos(a) * 9.5, .4, math.sin(a) * 9.5) * ANG(rng:NextNumber(0, 1), a, rng:NextNumber(0, 1)), STONE, M.Slate)
	end
	do -- a bent dog weathervane
		local vb = TE * CF(-3.5, 6, 2.5)
		local vt = vb * ANG(.3, 0, -.45) * CF(0, 6.5, 0)
		K.Rod(tower, "VaneRod", vb.Position, vt.Position, .25, P.Iron, M.CorrodedMetal)
		local dog = vt * ANG(0, .6, .25)
		K.Part(tower, "VaneDog", V3(.15, .9, 2.4), dog * CF(0, .4, 0), P.Iron, M.CorrodedMetal)
		K.Part(tower, "VaneDog", V3(.15, .9, .9), dog * CF(0, 1.2, -1.2), P.Iron, M.CorrodedMetal)
		K.Wedge(tower, "VaneDogEar", V3(.15, .6, .4), dog * CF(0, 1.9, -1.0), P.Iron, M.CorrodedMetal)
		K.Part(tower, "VaneDog", V3(.15, .9, .25), dog * CF(0, -.4, -.9), P.Iron, M.CorrodedMetal)
		K.Part(tower, "VaneDog", V3(.15, .9, .25), dog * CF(0, -.4, .9), P.Iron, M.CorrodedMetal)
		K.Part(tower, "VaneDogTail", V3(.15, .25, 1.2), dog * CF(0, .9, 1.6) * ANG(.6, 0, 0), P.Iron, M.CorrodedMetal)
		K.Ball(tower, "VaneArrow", .5, vt, P.Iron, M.CorrodedMetal)
	end
	for _, sp in ipairs({ { 9, -7 }, { -8, 8 }, { 7, 8 } }) do
		U.Roots(tower, (TE * CF(sp[1], 1, sp[2])).Position, rng:NextNumber(12, 20), rng, { Count = 2, Spread = 2.2, Glow = U.GLOW.Green })
	end
	-- ivy creeping up tier A
	for _, iv in ipairs({ { 1, -8, A0 + 15, A0 + 1 }, { 3, 6, A0 + 16, A0 + 3 }, { 2, -9, A0 + 14, A0 + 2 } }) do
		local f = TA * face(iv[1]) * CF(iv[2], 0, -HA - .25)
		Y.Vine(tower, (f * CF(0, iv[3], 0)).Position, (f * CF(0, iv[4], 0)).Position, rng, (TA * face(iv[1])).LookVector)
	end
	-- candles round the plinth (unlit wax clusters, two lit)
	for k = 0, 7 do
		local a = (k + .5) / 8 * PI * 2
		local p = U.Polar(c, 14.2, a, 2.4)
		U.Candles(tower, CF(p), 3, rng, { Light = k == 1 or k == 5, Range = 12 })
		if k == 1 or k == 5 then
			lights += 1
		end
	end
	local topY = 0
	for _, d in ipairs(tower:GetDescendants()) do
		if d:IsA("BasePart") then
			topY = math.max(topY, d.CFrame.Position.Y)
		end
	end
	tower:SetAttribute("TowerTop", math.floor(topY * 10 + .5) / 10)
	tower:SetAttribute("BellClearance", math.floor((math.sqrt(2) * (HD - PW) - 7.5 - bellOff) * 100 + .5) / 100) -- to the nearest pier corner

	------------------------------------------------------------------------------------------------ seal altars
	local altars = K.Model(root, "SealAltars")
	for i, pos in ipairs(L.SealAltars) do
		local m = K.Model(altars, "SealAltar_" .. i)
		m:SetAttribute("Seal", i)
		local out = V3(pos.X - c.X, 0, pos.Z - c.Z).Unit
		local A = K.Look(pos, pos + out) -- faces away from the tower
		local glowC = SEAL_GLOW[i]
		-- compact footprint (a low diamond step, a 3 x 3 upper step): TutorialEcho_2 lies 2.9 studs from altar II's centre
		K.Part(m, "AltarStep", V3(4.6, .35, 4.6), A * CF(0, .175, 0) * ANG(0, PI / 4, 0), STONE_D, M.Slate, { Solid = true })
		K.Part(m, "AltarStep", V3(3.0, .85, 3.0), A * CF(0, .775, 0), STONE, M.Slate, { Solid = true })
		local top = U.Crooked(m, "AltarPedestal", A * CF(0, 1.2, 0), V3(2.3, 2.6, 2.3), 2, rng, { Color = STONE_L, Shade = STONE, Solid = true, Lean = .03,
			Twist = .18, Taper = .05 })
		K.Part(m, "AltarCapital", V3(2.9, .5, 2.9), top * CF(0, .25, 0), STONE_L, M.Slate)
		local sock = top * CF(0, .5, 0)
		for k = 0, 3 do -- the empty socket: a square cup
			K.Part(m, "AltarSocket", V3(2.7, .9, .4), sock * ANG(0, k * PI / 2, 0) * CF(0, .45, -1.15), STONE_D, M.Slate)
		end
		K.CylY(m, "SocketHollow", .12, 2.2, sock * CF(0, .1, 0), P.Ink, M.SmoothPlastic)
		local holder = K.Part(m, "SocketLight", V3(.3, .3, .3), sock * CF(0, .6, 0), glowC, M.SmoothPlastic, { Transparency = 1 })
		local sl = light(holder, glowC, 16, 1.6)
		sl:SetAttribute("UyLightAtSeal", i)
		sl:SetAttribute("UyBaseBrightness", 1.6)
		holder:SetAttribute("UyLightAtSeal", i)
		-- Roman numeral plaque on the outward face of the pedestal
		local plaque = K.Part(m, "AltarNumeral", V3(1.8, 1.2, .22), A * CF(0, 2.5, -1.28), P.Slate, M.Slate)
		local g = K.Sign(plaque, N.Front, NUMERALS[i], P.Bone, { PixelsPerStud = 40, Stroke = false, H = .9, W = .9 })
		g:SetAttribute("NoTranslate", true)
		local label = g:FindFirstChild("Title")
		if label then
			label:SetAttribute("NoTranslate", true)
		end
		-- dim rune ring on the floor
		U.RuneRing(m, A * CF(0, .62, 0), 4.6, { N = 7, Width = .32, H = .04, Color = glowC:Lerp(P.Ink, .55), Transparency = .4, Glyphs = false, Phase = i })
		-- little seal bell on a curled hook at the back
		local hookBase = A * CF(0, 1.2, 1.6)
		local hookTop = A * CF(0, 5.6, 2.0)
		K.Rod(m, "AltarHook", hookBase.Position, hookTop.Position, .2, P.Iron, M.CorrodedMetal)
		K.Rod(m, "AltarHook", hookTop.Position, (A * CF(0, 6.0, 1.2)).Position, .18, P.Iron, M.CorrodedMetal)
		miniBell(m, A * CF(0, 5.9, 1.2), .7, BRONZE)
		-- candles on the lower step corners (unlit), front corners unless a gameplay point is there
		for k, cp in ipairs({ CF(-1.75, .35, -1.0), CF(1.75, .35, -1.0), CF(-1.75, .35, 1.0), CF(1.75, .35, 1.0) }) do
			local w = A * cp
			if points:Free(w.Position, .6) then
				U.Candles(m, w, (k % 2 == 0) and 2 or 3, rng, { Light = false, Spread = .35 })
			end
		end
		-- IGNITED STATE (visible once the player has cleared seal i): floating shard, flames, bright ring, light column
		local lit = {}
		local shardCF = sock * CF(0, 2.6, 0) * ANG(0, i * .7, .2)
		table.insert(lit, K.Wedge(m, "SealShard", V3(.5, 1.3, .9), shardCF * CF(0, .65, -.45), glowC, M.Neon))
		table.insert(lit, K.Wedge(m, "SealShard", V3(.5, 1.3, .9), shardCF * CF(0, .65, .45) * ANG(0, PI, 0), glowC, M.Neon))
		table.insert(lit, K.Wedge(m, "SealShard", V3(.5, .9, .9), shardCF * CF(0, -.45, -.45) * ANG(PI, PI, 0), glowC, M.Neon))
		table.insert(lit, K.Wedge(m, "SealShard", V3(.5, .9, .9), shardCF * CF(0, -.45, .45) * ANG(PI, 0, 0), glowC, M.Neon))
		for k = 0, 2 do
			local fa = k / 3 * PI * 2
			table.insert(lit, K.Ellipsoid(m, "SealFlame", V3(.6, 1.3, .6), sock * CF(math.cos(fa) * .55, .9, math.sin(fa) * .55) * ANG(0, 0, .15), glowC, M.Neon))
		end
		table.insert(lit, K.CylY(m, "SealGlowDisc", .14, 2.2, sock * CF(0, .2, 0), glowC, M.Neon))
		table.insert(lit, K.CylY(m, "SealLightColumn", 12, 1.4, sock * CF(0, 7, 0), glowC, M.Neon, { Transparency = .78 }))
		for _, p in ipairs(U.RuneRing(m, A * CF(0, .66, 0), 4.6, { N = 7, Width = .4, H = .05, Color = glowC, Transparency = .05, Glyphs = true, Phase = i })) do
			table.insert(lit, p)
		end
		U.Tag(lit, { UyShowAtSeal = i })
	end

	------------------------------------------------------------------------------------------------ arrival arch (portal)
	do
		local m = K.Model(root, "ArrivalArch")
		local plane = V3(L.ArrivalArch.X, 0, L.ArrivalArch.Z - 3.5) -- the portal plane (EchoPoint_1 lies 5 studs in front of it)
		local AC = K.Look(plane, V3(c.X, 0, c.Z)) -- faces the tower (players arrive in front of it)
		m:SetAttribute("PortalPlaneZ", plane.Z)
		K.Part(m, "ArchDais", V3(19, .5, 5), AC * CF(0, .25, -.3), STONE_D, M.Slate, { Solid = true })
		local riser = K.Part(m, "ArchDais", V3(15.5, .5, 3.4), AC * CF(0, .75, .2), STONE, M.Slate, { Solid = true })
		U.Sign(riser, N.Front, "TO THE DEAD YARD", "В МЁРТВЫЙ ДВОР", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .9, W = .8, Name = "ArchSign" })
		local tops = {}
		for _, sx in ipairs({ -1, 1 }) do
			local base = AC * CF(sx * 7.6, 1, .2)
			K.Part(m, "ArchPlinth", V3(4.6, 1.4, 4.6), base * CF(0, .7, 0), STONE_D, M.Slate, { Solid = true })
			local top = U.Crooked(m, "ArchPillar", base * CF(0, 1.4, 0) * ANG(0, 0, sx * .02), V3(3.4, 15.5, 3.6), 4, rng,
				{ Color = STONE, Shade = STONE_D, Solid = 2, Lean = .02, Twist = .1, Taper = .04 })
			table.insert(tops, top)
			U.Spire(m, "ArchPinnacle", top, 2.2, 7.5, rng, { Tiers = 4, Color = STONE_L, Shade = STONE, Curl = sx * .1, Orb = U.GLOW.Violet })
			local _, garg = U.Gargoyle(m, top * CF(sx * 1.6, -1.4, -1.4) * ANG(0, sx * .5, 0), .9, { Eye = U.GLOW.Violet, Wings = true })
			local _g = garg
		end
		local springs = AC * CF(0, 16.4, .2)
		local _, apex = U.Arch(m, "ArchRing", springs, 15.2, 3.2, 1.6, 6, { Stretch = 1.4, Color = STONE_L })
		U.Arch(m, "ArchNeon", springs * CF(0, 0, -.9), 12.6, .5, .4, 6, { Stretch = 1.4, Color = U.GLOW.Violet, Material = M.Neon })
		Y.Skull(m, apex * CF(0, .4, -1.3), 2.2, U.GLOW.Green, P.Bone)
		-- the portal: layered Neon discs + a pointed veil above them
		local disc = AC * CF(0, 9.4, .2)
		local layers = { { 11.2, C(60, 22, 110), 0, .05 }, { 9.4, C(120, 56, 215), -.06, .1 }, { 7.0, C(170, 110, 255), -.12, .15 },
			{ 4.4, C(210, 180, 255), -.18, .2 }, { 1.8, C(245, 236, 255), -.24, 0 } }
		for _, ly in ipairs(layers) do
			K.CylZ(m, "PortalDisc", .12, ly[1], disc * CF(0, 0, ly[3]), ly[2], M.Neon, { Transparency = ly[4] })
		end
		-- the pointed head of the opening glows like a veil (fills it up to the inside of the stone ring)
		local headH = U.ArchInner(15.2, 1.6, 0, { Stretch = 1.4 }) - .8
		local veil = K.Wedge(m, "PortalVeil", V3(.1, headH, 5.8), AC * CF(-2.9, 16.4 + headH / 2, .25) * ANG(0, PI / 2, 0), C(90, 40, 160), M.Neon,
			{ Transparency = .35 })
		local veil2 = K.Wedge(m, "PortalVeil", V3(.1, headH, 5.8), AC * CF(2.9, 16.4 + headH / 2, .25) * ANG(0, -PI / 2, 0), C(90, 40, 160), M.Neon,
			{ Transparency = .35 })
		K.Part(m, "PortalVeilBand", V3(11.6, 1.2, .1), AC * CF(0, 15.8, .25), C(120, 60, 200), M.Neon, { Transparency = .3 })
		local _v = { veil, veil2 }
		local swirl = K.Model(m, "PortalSwirl")
		local hub = K.Part(swirl, "SwirlHub", V3(.4, .4, .4), disc * CF(0, 0, -.32), U.GLOW.Violet, M.SmoothPlastic, { Transparency = 1 })
		for arm = 0, 5 do
			local prev = (disc * CF(0, 0, -.3)).Position
			for k = 1, 3 do
				local th = arm / 6 * PI * 2 + k * .55
				local r = .9 + k * 1.45
				local p = (disc * CF(math.cos(th) * r, math.sin(th) * r, -.3)).Position
				K.Bar(swirl, "SwirlArm", prev, p, .32 - k * .05, .05, k == 3 and C(255, 255, 255) or C(225, 200, 255), M.Neon, { Transparency = .1 * k })
				prev = p
			end
		end
		swirl.PrimaryPart = hub
		swirl.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		swirl:SetAttribute("UySwirl", true)
		swirl:SetAttribute("UySwirlSpeed", .8)
		K.Attach(hub, "PortalCentre", CF(0, 0, 0), { Kind = "ArrivalPortal" })
		light(hub, C(170, 110, 255), 28, 2)
		for k = 0, 11 do -- rune studs round the disc on the opening edge
			local a = k / 12 * PI * 2
			K.Part(m, "PortalRune", V3(.5, .5, .1), disc * CF(math.cos(a) * 6.1, math.sin(a) * 6.1, -.15) * ANG(0, 0, a), C(200, 160, 255), M.Neon)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local sp = AC * CF(sx * 12.6, 0, -.4)
			K.Part(m, "ArchStatuePlinth", V3(3.6, 1.2, 4.2), sp * CF(0, .6, 0), STONE_D, M.Slate, { Solid = true })
			Y.DogStatue(m, sp * CF(0, 1.2, 0) * ANG(0, -sx * .3, 0), { Scale = 1.15, Color = C(150, 148, 168), EyeColor = U.GLOW.Violet, Name = "ArchDog" })
		end
		local _t = tops
	end

	------------------------------------------------------------------------------------------------ the Black Coffin shrine
	do
		local m = K.Model(root, "CoffinShrine")
		local S = SQ.CoffinShrine -- -Z faces the tower; the coffin lies along local Z (4 x 2.4 x 7.5)
		local foot = -3.75 -- local z of the coffin's foot end (towards the tower)
		K.Part(m, "ShrineDais", V3(14, .5, 11.75), S * CF(0, .25, foot + 11.75 / 2), STONE_D, M.Slate, { Solid = true })
		K.Part(m, "ShrineDais", V3(11.6, .5, 10.55), S * CF(0, .75, foot + 10.55 / 2), STONE, M.Slate, { Solid = true })
		local bier = K.Part(m, "CoffinBier", V3(5.2, 1, 7.5), S * CF(0, 1.5, 0), STONE_L, M.Slate, { Solid = true })
		for _, sx in ipairs({ -1, 1 }) do
			for k = 0, 4 do -- striped bier frieze (accent)
				K.Part(m, "BierStripe", V3(.1, .4, 1.5), S * CF(sx * 2.65, 1.5, -3 + k * 1.5), k % 2 == 0 and P.Black or P.White, M.SmoothPlastic)
			end
			for _, sz in ipairs({ -1, 1 }) do -- carved paw feet
				K.Part(m, "BierPaw", V3(1.3, .7, 1.6), S * CF(sx * 2.2, 1.35, sz * 3.5 - sz * .2), STONE, M.Slate)
			end
		end
		-- the coffin seat: centre of the clear 4 x 2.4 x 7.5 coffin space on the bier (top y 2.0)
		local seat = K.Attach(bier, "CoffinSeat", CF(0, 1.7, 0), { SizeX = 4, SizeY = 2.4, SizeZ = 7.5 })
		local _s = seat
		-- six candle stands round it
		local flames = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -2.6, .2, 3.0 }) do
				table.insert(flames, candleStand(m, S * CF(sx * 3.7, 1.0, z), 2.6 + math.abs(z) * .25))
			end
		end
		light(flames[2], U.GLOW.Candle, 18, 1)
		-- three chain anchor rings: both sides and the head end
		local anchors = { S * CF(-5.0, 1.0, 0), S * CF(5.0, 1.0, 0), S * CF(0, 1.0, 5.6) }
		for k, a in ipairs(anchors) do
			local post = K.CylY(m, "ChainPost", 1.6, .9, a * CF(0, .8, 0), P.Iron, M.CorrodedMetal)
			local ringCF = a * CF(0, 1.9, 0) * (k == 3 and CF() or ANG(0, PI / 2, 0))
			K.CylZ(m, "ChainRing", .25, 1.4, ringCF, P.Iron, M.CorrodedMetal)
			K.CylZ(m, "ChainRingHole", .27, .8, ringCF, P.Ink, M.SmoothPlastic)
			Y.AttachAt(post, "ChainAnchor_" .. k, (ringCF).Position)
		end
		-- the reredos behind the head end (west): pointed panel, moon window, black moon emblem, pinnacles, gargoyles
		local back = S * CF(0, 1.0, 7.4)
		K.Part(m, "Reredos", V3(10, 11, 1.1), back * CF(0, 5.5, 0), STONE, M.Slate)
		Y.GableTri(m, "ReredosGable", back * CF(0, 11, 0) * ANG(0, PI / 2, 0), 10, 4.2, 1.1, STONE, M.Slate)
		local win = U.GothicWindow(m, back * CF(0, 3.2, -.6), 2.6, 4.2, { Color = U.GLOW.Moon, Lantern = "Blue", Mullion = false })
		light(win, U.GLOW.Moon, 16, .9)
		K.CylZ(m, "BlackMoonEmblem", .3, 3.6, back * CF(0, 11.2, -.7), C(10, 6, 16), M.SmoothPlastic)
		K.CylZ(m, "BlackMoonRim", .2, 4.2, back * CF(0, 11.2, -.6), U.GLOW.Violet, M.Neon)
		for _, sx in ipairs({ -1, 1 }) do
			local pb = back * CF(sx * 5.6, 0, 0)
			local top = U.Crooked(m, "ReredosPier", pb, V3(1.6, 12.5, 1.6), 3, rng, { Color = STONE_D, Lean = .03, Twist = .12 })
			U.Spire(m, "ReredosPinnacle", top, 1.4, 5, rng, { Tiers = 3, Color = STONE_L, Curl = sx * .12, Flat = true })
			U.Gargoyle(m, back * CF(sx * 5.6, 8.6, -1.2), .75, { Eye = U.GLOW.Violet })
		end
		local plaque = K.Part(m, "ShrinePlaque", V3(6.4, 1.3, .25), back * CF(0, 1.3, -.7), P.Slate, M.Slate)
		U.Sign(plaque, N.Front, "THE BLACK COFFIN", "ЧЁРНЫЙ ГРОБ", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .8, Name = "ShrineSign" })
		-- bones and skulls heaped against the dais corners (west)
		Y.Skull(m, S * CF(-6.2, .9, 5.2) * ANG(-.2, .5, 0), 1.0, nil, P.Bone)
		Y.Skull(m, S * CF(6.2, .9, 5.4) * ANG(-.1, -.6, 0), .9, nil, P.Bone)
	end

	------------------------------------------------------------------------------------------------ contracts board
	do
		local m = K.Model(root, "ContractsBoard")
		local Bd = SQ.ContractsBoard * CF(0, 0, 3) -- 3 studs behind the prompt point, facing the tower
		for _, sx in ipairs({ -1, 1 }) do
			U.Crooked(m, "BoardPost", Bd * CF(sx * 3.5, 0, 0), V3(.8, 9.2, .8), 2, rng, { Color = P.WoodDark, Material = M.Wood, Solid = true, Lean = .03,
				Twist = .2, Taper = 0 })
		end
		local board = K.Part(m, "BoardPanel", V3(7.2, 4.8, .35), Bd * CF(0, 5.2, 0) * ANG(0, 0, .02), P.Wood, M.WoodPlanks, { Solid = true })
		for _, e in ipairs({ { 0, 2.55, 7.6, .35 }, { 0, -2.55, 7.6, .35 }, { -3.7, 0, .35, 5.4 }, { 3.7, 0, .35, 5.4 } }) do
			K.Part(m, "BoardFrame", V3(e[3], e[4], .5), board.CFrame * CF(e[1], e[2], -.05), P.WoodDark, M.Wood)
		end
		for k = 1, 6 do
			local nx, ny = -2.3 + ((k - 1) % 3) * 2.3, ((k <= 3) and 1.1 or -1.1)
			local note = K.Part(m, "ContractNote", V3(1.7, 1.9, .06), board.CFrame * CF(nx, ny, -.2) * ANG(0, 0, rng:NextNumber(-.15, .15)), P.Bone, M.SmoothPlastic)
			K.CylZ(m, "WaxSeal", .08, .42, note.CFrame * CF(0, -.6, -.05), C(170, 30, 50), M.SmoothPlastic)
		end
		local header = K.Part(m, "BoardHeader", V3(7.4, 1.2, .3), Bd * CF(0, 8.2, -.1) * ANG(0, 0, -.03), P.WoodDark, M.WoodPlanks)
		U.Sign(header, N.Front, "CONTRACTS", "КОНТРАКТЫ", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .85, Name = "BoardSign" })
		local ridge = U.CrookedRoof(m, Bd * CF(0, 9.1, .1), 8.2, 2.4, 1.6, rng, { Color = C(40, 34, 46), Overhang = .5, Thick = .35 })
		Y.Skull(m, ridge * CF(0, .6, 0), .8, U.GLOW.Green, P.Bone)
		local _, glass = U.Lantern(m, Bd * CF(4.4, 8.6, -.8), U.GLOW.Candle, "Orange", { Range = 14, Brightness = .9, Size = .8 })
		lights += 1
		local _g = glass
	end

	------------------------------------------------------------------------------------------------ toll box
	do
		local m = K.Model(root, "TollBox")
		local Tb = SQ.TollBox * CF(0, 0, 3.4) -- behind the prompt point
		K.Part(m, "TollPlinth", V3(3.2, .6, 3.0), Tb * CF(0, .3, 0), STONE_D, M.Slate, { Solid = true })
		local box = K.Part(m, "TollChest", V3(2.6, 3.2, 2.2), Tb * CF(0, 2.2, 0) * ANG(.05, .1, .07), P.WoodDark, M.WoodPlanks, { Solid = true })
		for _, y in ipairs({ -1.0, .9 }) do
			K.Part(m, "TollBand", V3(2.72, .28, 2.32), box.CFrame * CF(0, y, 0), P.Iron, M.CorrodedMetal)
		end
		K.Wedge(m, "TollLid", V3(2.8, .7, 2.4), box.CFrame * CF(0, 1.95, 0) * ANG(0, PI, 0), P.Wood, M.WoodPlanks)
		K.Part(m, "TollSlot", V3(1.3, .12, .3), box.CFrame * CF(0, 2.0, .35), P.Ink, M.SmoothPlastic)
		K.Part(m, "TollPadlock", V3(.7, .8, .3), box.CFrame * CF(0, .2, -1.2), C(150, 120, 60), M.Metal)
		Y.Skull(m, box.CFrame * CF(0, -.55, -1.25), .9, U.GLOW.Candle, P.Bone)
		-- curled iron arm with the toll bell
		local a0 = (box.CFrame * CF(.9, 1.4, .7)).Position
		local a1 = a0 + V3(0, 3.4, 0) + (Tb.LookVector * -.2)
		local a2 = a1 + Tb.LookVector * 1.8 + V3(0, .6, 0)
		K.Rod(m, "TollArm", a0, a1, .22, P.Iron, M.CorrodedMetal)
		K.Rod(m, "TollArm", a1, a2, .2, P.Iron, M.CorrodedMetal)
		K.Rod(m, "TollCurl", a2, a2 + Tb.LookVector * .4 + V3(0, .5, 0), .16, P.Iron, M.CorrodedMetal)
		U.Bell(m, CF(a2 - V3(0, .1, 0)), .55, { Name = "TollBell" })
		K.Bar(m, "TollBellRope", a2 - V3(0, 1.5, 0), a2 - V3(0, 3.6, 0), .12, .12, C(170, 150, 110), M.Fabric)
		for k = 1, 3 do
			local cc = ({ U.GLOW.Candle, U.GLOW.Violet, U.GLOW.Green })[k]
			K.Ball(m, "TollCandy", .5, Tb * CF(-1.0 + k * .45, .85, -1.2), cc, M.Neon)
		end
		local stake = K.Part(m, "TollSignStake", V3(.3, 2.8, .3), Tb * CF(-2.4, 1.4, -.6), P.WoodDark, M.Wood, { Solid = true })
		local _st = stake
		local sign = K.Part(m, "TollSignBoard", V3(3.2, 1.1, .2), Tb * CF(-2.4, 2.9, -.75) * ANG(0, 0, .06), P.Wood, M.WoodPlanks)
		U.Sign(sign, N.Front, "TOLL BOX", "ПОШЛИНА", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .8, Name = "TollSign" })
		local _, glass = U.Lantern(m, CF(a1 + Tb.LookVector * .9 + V3(0, .2, 0)), U.GLOW.Candle, "Orange", { Range = 12, Brightness = .8, Size = .6 })
		lights += 1
		local _g = glass
	end

	------------------------------------------------------------------------------------------------ the Tailor of the Dead
	do
		local m = K.Model(root, "TailorStall")
		local St = SQ.Tailor * CF(0, 0, 6) -- behind the prompt point (EchoPoint at the prompt keeps clear)
		K.Part(m, "StallFloor", V3(9, .4, 5), St * CF(0, .2, 0), P.WoodDark, M.WoodPlanks, { Solid = true })
		K.Part(m, "StallCounter", V3(8, 2.6, 1.2), St * CF(0, 1.7, -1.9), P.Wood, M.WoodPlanks, { Solid = true })
		K.Part(m, "StallCounterTop", V3(8.4, .25, 1.6), St * CF(0, 3.1, -1.9), P.WoodDark, M.Wood)
		for _, sx in ipairs({ -1, 1 }) do
			U.Crooked(m, "StallPost", St * CF(sx * 4.2, .4, 2.2), V3(.5, 7.2, .5), 2, rng, { Color = P.WoodDark, Material = M.Wood, Solid = true, Taper = 0 })
			U.Crooked(m, "StallPost", St * CF(sx * 4.2, 3.2, -2.3), V3(.4, 2.6, .4), 1, rng, { Color = P.WoodDark, Material = M.Wood, Taper = 0 })
		end
		K.Part(m, "StallBackWall", V3(8.2, 5.2, .3), St * CF(0, 3.0, 2.4), C(52, 40, 52), M.WoodPlanks)
		-- striped awning (black / white slats) sloping to the front + scalloped hem
		for k = 0, 5 do
			local x = -3.75 + k * 1.5
			local p0 = (St * CF(x, 7.6, 2.4)).Position
			local p1 = (St * CF(x, 5.8, -3.0)).Position
			K.Bar(m, "AwningSlat", p0, p1, 1.5, .14, k % 2 == 0 and P.Black or P.White, M.Fabric)
			K.Wedge(m, "AwningHem", V3(1.5, .6, .14), CFrame.new(p1 - V3(0, .35, 0)) * (St - St.Position) * ANG(0, 0, PI) * CF(0, 0, 0), k % 2 == 0 and P.Black or P.White,
				M.Fabric)
		end
		local beam = K.Part(m, "AwningBeam", V3(9, .9, .3), St * CF(0, 5.6, -3.15), P.WoodDark, M.Wood)
		U.Sign(beam, N.Front, "THE TAILOR OF THE DEAD", "ПОРТНОЙ МЁРТВЫХ", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .85, W = .95, Name = "TailorSign" })
		-- headless dress form with a ghostly veil
		local df = St * CF(-2.6, .4, .6)
		K.CylY(m, "DressFormFoot", .2, 1.4, df * CF(0, .1, 0), P.Iron, M.CorrodedMetal)
		K.CylY(m, "DressFormStand", 2.2, .2, df * CF(0, 1.2, 0), P.Iron, M.CorrodedMetal)
		K.Ellipsoid(m, "DressFormTorso", V3(1.6, 2.4, 1.1), df * CF(0, 3.3, 0), C(170, 150, 170), M.Fabric)
		K.CylY(m, "DressFormNeck", .6, .45, df * CF(0, 4.7, 0), P.WoodDark, M.Wood)
		K.Ellipsoid(m, "DressFormVeil", V3(2.2, 3.6, 1.6), df * CF(0, 3.4, -.05), C(200, 190, 255), M.Neon, { Transparency = .78 })
		-- bolts of cloth, spools, hanging drapes
		for k, col in ipairs({ U.GLOW.Violet:Lerp(P.Ink, .3), U.GLOW.Green:Lerp(P.Ink, .45), P.Black }) do
			K.CylX(m, "ClothBolt", 2.2, .9, St * CF(-.8 + k * 1.1, 3.7, -1.9) * ANG(0, .1 * k, 0), col, M.Fabric)
		end
		for k = 1, 3 do
			K.CylY(m, "ThreadSpool", .6, .5, St * CF(2.6 + k * .4, 3.5, -1.8), ({ U.GLOW.Candle, P.White, U.GLOW.Violet })[k], M.Fabric)
		end
		for k, col in ipairs({ C(110, 60, 170), C(40, 90, 70), C(30, 26, 36) }) do
			K.Part(m, "HangingDrape", V3(1.6, 3.6, .1), St * CF(.4 + k * 1.2, 4.6, 2.1) * ANG(0, 0, rng:NextNumber(-.05, .05)), col, M.Fabric)
		end
		-- giant scissors over the stall
		local sc = St * CF(0, 8.6, 2.5)
		K.Part(m, "ScissorBlade", V3(.3, 3.6, .15), sc * ANG(0, 0, .45) * CF(0, 1.2, 0), C(180, 180, 196), M.Metal)
		K.Part(m, "ScissorBlade", V3(.3, 3.6, .15), sc * ANG(0, 0, -.45) * CF(0, 1.2, 0), C(180, 180, 196), M.Metal)
		K.CylZ(m, "ScissorHandle", .2, 1.2, sc * ANG(0, 0, .45) * CF(0, -.9, 0), P.Black, M.Metal)
		K.CylZ(m, "ScissorHandle", .2, 1.2, sc * ANG(0, 0, -.45) * CF(0, -.9, 0), P.Black, M.Metal)
		local _, glass = U.Lantern(m, St * CF(3.8, 5.4, -3.1), U.GLOW.Candle, "Orange", { Range = 14, Brightness = .9, Size = .7 })
		lights += 1
		local _g = glass
	end

	------------------------------------------------------------------------------------------------ practice ring
	do
		local m = K.Model(root, "PracticeRing")
		local PR = SQ.PracticeRing
		local pc = CF(PR.Centre.X, 0, PR.Centre.Z)
		K.CylY(m, "PracticeFloor", .1, PR.Radius * 2 - .6, pc * CF(0, .11, 0), C(46, 42, 58), M.Slate)
		local n = 18
		for k = 1, n do
			local a0, a1 = (k - 1) / n * PI * 2, k / n * PI * 2 - .02
			K.Bar(m, "PracticeRingStone", U.Polar(PR.Centre, PR.Radius, a0, .17), U.Polar(PR.Centre, PR.Radius, a1, .17), 1.3, .22,
				k % 2 == 0 and STONE_L or P.Bone:Lerp(STONE_L, .5), M.Slate)
		end
		U.RuneRing(m, pc * CF(0, .17, 0), PR.Radius - 2.6, { N = 8, Width = .3, H = .04, Color = C(150, 120, 210), Transparency = .45, Glyphs = false })
		-- rope posts on the plaza half (the half on the ring road stays open)
		local posts = {}
		for k = -2, 2 do
			local a = k * .55 -- around north (towards the tower)
			local p = U.Polar(PR.Centre, PR.Radius + 1.6, a, 0)
			if space:Free(p, .6) then
				K.CylY(m, "RopePost", 2.4, .5, CF(p + V3(0, 1.2, 0)) * ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.06, .06)), P.WoodDark, M.Wood)
				K.Ball(m, "RopePostKnob", .7, CF(p + V3(0, 2.5, 0)), P.Bone, M.SmoothPlastic)
				table.insert(posts, p)
			end
		end
		for k = 1, #posts - 1 do
			K.Chain(m, posts[k] + V3(0, 2.1, 0), posts[k + 1] + V3(0, 2.1, 0), .5, 8)
		end
		-- the Mourner pedestal (the dummy stands here)
		local mp = CF(SQ.Mourner.X, 0, SQ.Mourner.Z)
		K.CylY(m, "MournerPedestal", .6, 4.4, mp * CF(0, .4, 0), STONE, M.Slate, { Solid = true })
		K.CylY(m, "MournerPedestalRim", .2, 4.9, mp * CF(0, .2, 0), STONE_D, M.Slate)
		-- the hand bell on its post (the bell hangs at TutorialBell, the strike point)
		local tb = SQ.TutorialBell
		local postBase = V3(tb.X, 0, tb.Z + 1.6)
		K.Part(m, "BellPostFoot", V3(1.4, .3, 1.4), CF(postBase + V3(0, .15, 0)), STONE_D, M.Slate)
		K.CylY(m, "BellPost", 4.4, .45, CF(postBase + V3(0, 2.3, 0)) * ANG(-.06, 0, .03), P.WoodDark, M.Wood)
		local armTop = postBase + V3(0, 4.3, -.3)
		K.Rod(m, "BellPostArm", armTop, V3(tb.X, 4.3, tb.Z), .22, P.Iron, M.CorrodedMetal)
		K.Rod(m, "BellPostCurl", V3(tb.X, 4.3, tb.Z), V3(tb.X, 4.8, tb.Z - .5), .18, P.Iron, M.CorrodedMetal)
		U.Bell(m, CF(tb.X, 4.2, tb.Z), .55, { Name = "HandBell", Color = C(150, 120, 70) })
		local board = K.Part(m, "PracticeSign", V3(4.4, 1.2, .2), CF(PR.Centre.X - PR.Radius - 2.4, 2.4, PR.Centre.Z) * ANG(0, PI / 2, 0), P.Wood,
			M.WoodPlanks)
		K.CylY(m, "PracticeSignStake", 2.2, .3, CF(PR.Centre.X - PR.Radius - 2.4, 1.1, PR.Centre.Z), P.WoodDark, M.Wood)
		U.Sign(board, N.Front, "PRACTICE RING", "ТРЕНИРОВОЧНЫЙ КРУГ", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .8, Name = "PracticeSignText" })
		U.Sign(board, N.Back, "PRACTICE RING", "ТРЕНИРОВОЧНЫЙ КРУГ", P.Bone, { PixelsPerStud = 30, Stroke = false, H = .8, Name = "PracticeSignBack" })
	end

	------------------------------------------------------------------------------------------------ plaza decor
	local decor = K.Model(root, "PlazaDecor")
	-- crooked lamp posts at r 52 between the echo rings
	local nLamp = 0
	for k = 0, 15 do
		local a = (k + .5) / 16 * PI * 2
		local p = U.Polar(c, 52, a, 0)
		if nLamp < 10 and space:Free(p, 1.6) then
			space:Claim(p, 1.6)
			local lm = U.Lamp(decor, U.Facing(p, c), rng, { Height = 10.5, Color = (k % 3 == 0) and U.GLOW.Violet or U.GLOW.Candle,
				Kind = (k % 3 == 0) and "Purple" or "Orange", Range = 22, Brightness = 1.1, Lite = true })
			lm.Name = "PlazaLamp"
			lights += 1
			nLamp += 1
		end
	end
	-- benches facing the tower (crooked plank seats on iron legs)
	local nBench = 0
	for k = 0, 23 do
		local a = (k + .25) / 24 * PI * 2
		local p = U.Polar(c, 43.5, a, 0)
		if nBench < 10 and space:Free(p, 3.2) then
			space:Claim(p, 3.2)
			nBench += 1
			local bcf = U.Facing(p, c) * ANG(0, rng:NextNumber(-.08, .08), 0)
			local bm = K.Model(decor, "Bench")
			K.Part(bm, "BenchSeat", V3(4.6, .3, 1.2), bcf * CF(0, 1.3, 0) * ANG(0, 0, rng:NextNumber(-.05, .05)), P.Wood, M.WoodPlanks, { Solid = true })
			K.Part(bm, "BenchBack", V3(4.6, 1.3, .2), bcf * CF(0, 2.3, .6) * ANG(-.18, 0, rng:NextNumber(-.06, .06)), P.WoodDark, M.WoodPlanks)
			for _, sx in ipairs({ -1, 1 }) do
				K.Part(bm, "BenchLeg", V3(.25, 1.3, 1.1), bcf * CF(sx * 1.9, .65, 0), P.Iron, M.CorrodedMetal)
				K.Bar(bm, "BenchArm", (bcf * CF(sx * 2.4, 1.3, .5)).Position, (bcf * CF(sx * 2.5, 2.0, -.5)).Position, .2, .2, P.Iron, M.CorrodedMetal)
			end
		end
	end
	-- dog graves along the plaza rim (between the outer echo ring and the kerb)
	local nGrave = 0
	for k = 0, 47 do
		local a = (k + .5) / 48 * PI * 2
		local p = U.Polar(c, 60.2, a, 0)
		if nGrave < 14 and space:Free(p, 1.8) then
			space:Claim(p, 1.8)
			nGrave += 1
			Y.Tombstone(decor, U.Facing(p, c) * ANG(0, rng:NextNumber(-.2, .2), 0), ({ 4, 7, 8, 9, 1, 6 })[nGrave % 6 + 1], rng, nil, { NoTranslate = true })
		end
	end
	-- glowing flower planters, candle clusters
	local nPlant, nCandle = 0, 0
	for k = 0, 31 do
		local a = (k + .75) / 32 * PI * 2
		local r = (k % 2 == 0) and 25.5 or 39
		local p = U.Polar(c, r, a, 0)
		if k % 2 == 0 and nPlant < 7 and space:Free(p, 2) then
			space:Claim(p, 2)
			nPlant += 1
			K.Part(decor, "Planter", V3(3.2, 1, 3.2), CF(p + V3(0, .5, 0)) * ANG(0, a, 0), STONE_D, M.Slate, { Solid = true })
			K.Part(decor, "PlanterSoil", V3(2.7, .2, 2.7), CF(p + V3(0, 1.02, 0)) * ANG(0, a, 0), C(40, 30, 34), M.Ground)
			U.FlowerPatch(decor, CF(p + V3(0, 1.1, 0)), 3, rng, { Spread = 1, Color = ({ U.GLOW.Green, U.GLOW.Moon, U.GLOW.Violet })[nPlant % 3 + 1] })
		elseif k % 2 == 1 and nCandle < 8 and space:Free(p, 1) then
			space:Claim(p, 1)
			nCandle += 1
			U.Candles(decor, CF(p), 4, rng, { Light = false })
		end
	end
	-- bone piles + skulls at the foot of a few graves, glowing mushrooms round the planters
	for k = 1, 4 do
		local a = k / 4 * PI * 2 + .4
		local p = U.Polar(c, 61, a, 0)
		if space:Free(p, .8) then
			Y.Skull(decor, CF(p + V3(0, .4, 0)) * ANG(-.25, a, 0), .8, nil, P.BoneDark)
		end
	end

	root:SetAttribute("Lights", lights)
	if ctx.Note then
		ctx.Note(string.format("BellSquare: %d parts, %d lights (tower %d parts, top y %.1f, bell clearance %.2f), %d lamps, %d benches, %d graves",
			K.Count(root), lights, K.Count(tower), tower:GetAttribute("TowerTop") or 0, tower:GetAttribute("BellClearance") or 0, nLamp, nBench, nGrave))
	end
end

return BellSquare
