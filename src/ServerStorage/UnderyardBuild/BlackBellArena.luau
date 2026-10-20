-- THE UNDERYARD · BLACK BELL ARENA (Seal VII: LAST BELL TRIAL, BLACK BELL ASSAULT) —
-- ServerStorage.UnderyardBuild.BlackBellArena, WP-H3. Build-time builder (Order 60) run by tools/edits/40_underyard.luau;
-- saved as the model 40_Underyard.BlackBellArena (attribute UyDistrict = "BlackBellArena"). DESIGN §7, §8.4 item 7,
-- §8.6 (assault), §22.6. Coordinates: UnderyardLayout.Arena / Districts (never moved). The Gravekeeper finale (§11)
-- happens in the Dead Yard pit, not here: this arena serves the Last Bell trial and the Black Bell Assault.
--   * own ground: a base slab over the district box (top -.1; another package lays the approach road surface on it), the
--     ARENA FLOOR (r Arena.Radius = 52, top y 0: cracked dark stone, a bronze paw medallion under the bell, a BRONZE RUNE
--     RING r 44..47 whose glyphs carry UyLightAtSeal = 7) — nothing but flush inlays inside r 48 apart from the four
--     chain anchors the trial needs; the spawn mark at Arena.Spawn.
--   * a RAISED OUTER RING (tier A r 52..58 top 2, tier B r 58..70 top 4.5, buttressed outer face, stairs on the
--     diagonals, a gap for the approach) with ruins: broken arches, toppled columns, lancet walls, fallen bell shards,
--     a mourning dog statue, dog-skull gargoyles, gravestones; 8 braziers (violet fire, HwBrazier).
--   * THE GALLOWS: a giant twisted bell frame (two leaning, twisting iron uprights on the ring at E/W, braces, a crooked
--     crossbeam with a headstock + shackle) holding THE BLACK BELL at Arena.Bell: model `BlackBell` (Atomic, PrimaryPart
--     `BellCrown` at its crown, attribute UySwing = true; ~22 tall, black iron, violet rune bands and glyphs, a dog
--     skull relief facing the approach, a hollow mouth with the clapper and a violet inner light).
--   * 4 CHAIN ANCHORS at Arena.Chains: models `ArenaChain_N/E/S/W` (Atomic, attribute ChainKey = "N".."W") — an iron
--     bollard on a stone base with a violet `ChainGlow` band and a heavy chain rising to the bell's waist.
--   * the descending approach (Arena.Approach, road surface by another package): kerbs, chained posts, gravestones,
--     banners with the bell sigil, lantern posts, terraced banks rising into a canyon, two mourning dog statues and a
--     crooked iron entry arch with a small bell at the ring gap; the outer grounds get graves, dead trees and fog.
-- Budgets: <= 3 000 parts, <= 30 lights (reported through ctx.Note).
local G = require(script.Parent.GothicProps)
local K, Y = G.K, G.Y
local COL = G.Col
local C = Color3.fromRGB
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local SEAL = 7 -- LAST BELL
local INNER_CLEAR = 48 -- nothing but flush inlays (and the chain anchors) inside this radius
local TIER_A, TIER_B = { 52, 56, 1.5 }, { 56, 61.5, 3.5 } -- inner radius, outer radius, top (inside the framework island r 62)
local FT = .05 -- arena floor top: just over the framework's island floor (y 0) so the two never z-fight
local FLOOR = C(40, 36, 48)
local FLOOR_DARK = C(28, 24, 34)
local IRON_BLACK = C(26, 24, 32)
local IRON_EDGE = C(48, 44, 58)
local BELL_IRON = C(36, 32, 46) -- the Black Bell: black iron that still catches the violet light
local BELL_EDGE = C(62, 56, 76)
local RUNE = C(170, 100, 255)
local FLAME = C(186, 120, 255)

local function districtBox(L, name)
	for _, d in ipairs(L.Districts) do
		if d.Name == name then
			return d
		end
	end
	error("UnderyardLayout.Districts has no " .. name)
end

return {
	Order = 60,
	Build = function(ctx)
		local L = ctx.Layout
		local A = L.Arena
		local AC = A.Centre
		local AR = A.Radius
		local BELL = A.Bell
		local AP = A.Approach
		local ROAD_HALF = AP.Width / 2
		local box = districtBox(L, "BlackBellArena")
		local X0, X1, Z0, Z1 = box.Min.X, box.Max.X, box.Min.Z, box.Max.Z
		local rng = G.Rng(60719)

		local root = ctx.Model("BlackBellArena")
		root:SetAttribute("UyDistrict", "BlackBellArena")
		root:SetAttribute("Seal", SEAL)
		local function sub(name)
			return K.Model(root, name)
		end
		local ground, floor, ring, ruins, frame, approach, lamps, outer =
			sub("Ground"), sub("ArenaFloor"), sub("OuterRing"), sub("Ruins"), sub("BellFrame"), sub("Approach"), sub("Lamps"), sub("OuterGraves")
		local fx = G.FXModel(root, "ArenaFX")

		local function at(x, y, z)
			return CF(x, y, z)
		end
		-- polar around the arena centre: a = 0 north (-Z), clockwise seen from above (towards +X)
		local function polar(a: number, r: number, y: number): Vector3
			return V3(AC.X + math.sin(a) * r, y, AC.Z - math.cos(a) * r)
		end
		local function radialCF(a: number, r: number, y: number): CFrame -- local X radial (outwards), Z tangential
			return CF(polar(a, r, y)) * ANG(0, PI / 2 - a, 0)
		end
		local function outward(a: number): Vector3
			return V3(math.sin(a), 0, -math.cos(a))
		end
		local lights = 0
		-- the world framework (Ground, Order 10 / Roads, Order 20) may already have laid the arena island (circle r 62 +
		-- a strip to the south wall over the abyss) and the winding approach bridge: build on them, never duplicate them
		local base = G.DistrictBase(ctx.Root, "BlackBellArena")
		local deck = G.Named(ctx.Root, "ApproachDeck", root)
		local bridgePath = nil
		do
			local roads = script.Parent:FindFirstChild("Roads")
			if #deck > 0 and roads and roads:IsA("ModuleScript") then
				local ok, mod = pcall(require, roads)
				if ok and type(mod) == "table" and type(mod.ApproachPath) == "function" then
					local ok2, pts = pcall(mod.ApproachPath, L)
					if ok2 and type(pts) == "table" and #pts >= 2 then
						bridgePath = pts
					end
				end
			end
		end
		root:SetAttribute("OnFrameworkIsland", base ~= nil)
		root:SetAttribute("ApproachBridge", bridgePath ~= nil)

		---------------------------------------------------------------------------------------------------- ground
		if not base then -- standalone: the district lays its own ground over the whole box
			K.Part(ground, "ArenaGround", V3(X1 - X0, 4, Z1 - Z0), at((X0 + X1) / 2, -2.1, (Z0 + Z1) / 2), C(48, 42, 50), M.Ground, G.Solid())
		end
		K.CylY(floor, "ArenaFloorStone", 1.2, AR * 2, at(AC.X, FT - .6, AC.Z), FLOOR, M.Slate, G.Solid())

		-- flush inlays (all within .1 of the floor) -------------------------------------------------------------
		local function inlayRing(r: number, n: number, w: number, color: Color3, mat: Enum.Material, fill: number?, y: number?, name: string?)
			return G.Ring(floor, at(AC.X, FT + (y or .01), AC.Z), r, n, w, .06, color, mat, { Fill = fill, Name = name or "FloorInlay" })
		end
		-- worn slab rings + radial joints
		for _, r in ipairs({ 14, 24, 34 }) do
			inlayRing(r, 28, .3, FLOOR_DARK, M.Slate, .96, nil, "FloorJoint")
		end
		for k = 0, 11 do
			local a = k / 12 * PI * 2 + .13
			K.Bar(floor, "FloorJoint", polar(a, 14.2, FT + .04), polar(a, 43.6, FT + .04), .3, .06, FLOOR_DARK, M.Slate)
		end
		-- the bronze paw medallion under the bell
		K.CylY(floor, "Medallion", .06, 22, at(AC.X, FT + .03, AC.Z), C(52, 44, 58), M.Slate)
		inlayRing(11, 32, .7, COL.Bronze, M.Metal, .94, .04, "MedallionRim")
		inlayRing(8.4, 24, .3, COL.BronzeDark, M.Metal, .6, .04, "MedallionRim")
		G.Rune(floor, at(AC.X, FT + .07, AC.Z + 1) * ANG(PI / 2, 0, 0) * ANG(0, 0, PI), "Paw", 11, COL.Bronze, { Depth = .08, Material = M.Metal, Width = .2, Name = "MedallionPaw" })
		-- cracks: jagged dark runs from the medallion outwards, a few glowing violet near the chain anchors
		for k = 1, 14 do
			local a = k / 14 * PI * 2 + rng:NextNumber(-.15, .15)
			local r = rng:NextNumber(11.5, 16)
			local p = polar(a, r, FT + .05)
			local steps = rng:NextInteger(3, 5)
			for _ = 1, steps do
				a += rng:NextNumber(-.12, .12)
				r = math.min(r + rng:NextNumber(4, 7), 43)
				local q = polar(a, r, FT + .05)
				K.Bar(floor, "FloorCrack", p, q, rng:NextNumber(.18, .35), .05, C(18, 14, 24), M.SmoothPlastic)
				p = q
			end
		end
		for _, key in ipairs({ "N", "E", "S", "W" }) do
			local c = A.Chains[key]
			local d = V3(c.X - AC.X, 0, c.Z - AC.Z).Unit
			local side = V3(-d.Z, 0, d.X)
			local p = V3(c.X, FT + .06, c.Z) - d * 3
			for k = 1, 3 do
				local q = p - d * rng:NextNumber(3, 5) + side * rng:NextNumber(-2, 2)
				K.Bar(floor, "GlowCrack", p, q, .2, .05, RUNE, M.Neon, { Transparency = .25 })
				p = q
				local _ = k
			end
		end
		-- THE BRONZE RUNE RING (r 44..47): bronze band, borders, 24 glyphs that light up once Seal VII is cleared
		inlayRing(45.5, 48, 2.8, COL.BronzeDark, M.Metal, .95, .02, "RuneRingBand")
		inlayRing(43.9, 48, .35, COL.Bronze, M.Metal, 1, .05, "RuneRingBorder")
		inlayRing(47.1, 48, .35, COL.Bronze, M.Metal, 1, .05, "RuneRingBorder")
		for k = 0, 23 do
			local a = (k + .5) / 24 * PI * 2
			local p = polar(a, 45.5, FT + .09)
			local cf = CF(p) * ANG(0, PI - a, 0) * ANG(PI / 2, 0, 0)
			G.Rune(floor, cf, G.GlyphNames[k % #G.GlyphNames + 1], 1.7, RUNE, { Depth = .04, Width = .16, Name = "RingGlyph", Attrs = { UyLightAtSeal = SEAL } })
		end
		-- the edge spawn mark (flush bronze circle + arrow towards the centre)
		do
			local s = A.Spawn
			G.Ring(floor, at(s.X, FT + .02, s.Z), 2.6, 16, .3, .06, COL.Bronze, M.Metal, { Fill = .7, Name = "SpawnMark" })
			local toC = V3(AC.X - s.X, 0, AC.Z - s.Z).Unit
			G.Rune(floor, CF(V3(s.X, FT + .08, s.Z)) * ANG(0, math.atan2(toC.X, toC.Z), 0) * ANG(PI / 2, 0, 0), "Arrow", 2.6, COL.Bronze,
				{ Depth = .05, Material = M.Metal, Name = "SpawnMark" })
		end

		----------------------------------------------------------------------------------------------- the outer ring
		local NSEG = 40
		local GAP_HALF = ROAD_HALF + 1.5 -- the approach opening at the north
		local function inGap(a: number, r: number): boolean
			local p = polar(a, r, 0)
			return math.abs(p.X - AC.X) < GAP_HALF and p.Z < AC.Z
		end
		for _, tier in ipairs({ TIER_A, TIER_B }) do
			local r0, r1, top = tier[1], tier[2], tier[3]
			local g = math.asin(GAP_HALF / r0) -- segments are clipped to [g, 2pi - g]
			for i = 1, NSEG do
				local a0, a1 = (i - 1) / NSEG * PI * 2, i / NSEG * PI * 2
				if a1 > g and a0 < 2 * PI - g then
					a0, a1 = math.max(a0, g), math.min(a1, 2 * PI - g)
					local am = (a0 + a1) / 2
					local rm = (r0 + r1) / 2
					local chord = 2 * r1 * math.tan((a1 - a0) / 2) + .3
					local h = top + .6 + rng:NextNumber(-.15, .2)
					local col = (tier == TIER_A and C(62, 56, 70) or C(54, 50, 62)):Lerp(COL.Slate, rng:NextNumber(0, .4))
					K.Part(ring, tier == TIER_A and "RingTierA" or "RingTierB", V3(r1 - r0 + (tier == TIER_A and .4 or 0), h, chord),
						radialCF(am, rm, top - h / 2) * ANG(0, 0, rng:NextNumber(-.012, .012)), col, M.Cobblestone, G.Solid())
					-- coping stones along the inner lip
					K.Part(ring, "RingCoping", V3(1.4, .35, chord * rng:NextNumber(.7, .95)), radialCF(am, r0 + .7, top + .1) * ANG(0, rng:NextNumber(-.05, .05), 0),
						COL.StoneLight:Lerp(COL.Stone, rng:NextNumber(0, .6)), M.Slate)
				end
			end
		end
		-- buttresses on the outer face, every 30° away from the approach (standalone only: on the framework island the
		-- outer face meets its cliff rim)
		for k = 0, 11 do
			local a = (k + .5) / 12 * PI * 2
			if not base and not inGap(a, TIER_B[2]) then
				local cf = radialCF(a, TIER_B[2] + 1.6, 0) * ANG(0, -PI / 2, 0) -- -Z outwards: wedge high side against the wall
				K.Wedge(ring, "RingButtress", V3(3.2, TIER_B[3] + .5, 3.4), cf * CF(0, (TIER_B[3] + .5) / 2 - .1, 0) * ANG(0, PI, 0), C(50, 46, 58), M.Slate, G.Solid())
			end
		end
		-- stairs on the diagonals: floor -> tier A (inside r 48..52), tier A -> tier B
		for _, a in ipairs({ PI / 4, 3 * PI / 4, 5 * PI / 4, 7 * PI / 4 }) do
			for k = 0, math.floor(TIER_A[3] / .5) - 1 do
				local r = TIER_A[1] - .45 - k * .9
				K.Part(ring, "ArenaStair", V3(1, TIER_A[3] - k * .5, 7), radialCF(a, r, (TIER_A[3] - k * .5) / 2), C(70, 64, 78), M.Slate, G.Solid())
			end
			for k = 0, math.floor((TIER_B[3] - TIER_A[3]) / .5) - 1 do
				local r = TIER_B[1] - .45 - k * .9
				local top = TIER_B[3] - k * .5
				K.Part(ring, "ArenaStair", V3(1, top - TIER_A[3] + .2, 6), radialCF(a, r, TIER_A[3] + (top - TIER_A[3]) / 2 - .1), C(66, 60, 74), M.Slate, G.Solid())
			end
		end

		----------------------------------------------------------------------------------------------------- braziers
		for k = 0, 7 do
			local a = (({ 1, 2, 4, 5, 7, 8, 10, 11 })[k + 1]) / 12 * PI * 2
			local p = polar(a, (TIER_A[1] + TIER_A[2]) / 2, TIER_A[3])
			local m = K.Model(ring, "Brazier")
			K.Part(m, "BrazierPedestal", V3(2.4, 2.4, 2.4), at(p.X, p.Y + 1.2, p.Z) * ANG(0, a, 0), C(60, 54, 68), M.Slate, G.Solid())
			K.Part(m, "BrazierPedestalCap", V3(2.9, .4, 2.9), at(p.X, p.Y + 2.5, p.Z) * ANG(0, a, 0), COL.StoneLight, M.Slate)
			for j = 0, 2 do
				local la = a + j / 3 * PI * 2
				local foot = p + V3(math.cos(la) * 1.5, 2.7, math.sin(la) * 1.5)
				K.Bar(m, "BrazierLeg", foot, p + V3(math.cos(la) * .9, 3.9, math.sin(la) * .9), .3, .3, IRON_BLACK, M.CorrodedMetal)
			end
			K.CylY(m, "BrazierBowl", 1.1, 3.4, at(p.X, p.Y + 4.2, p.Z), IRON_BLACK, M.CorrodedMetal)
			K.CylY(m, "BrazierRim", .3, 3.8, at(p.X, p.Y + 4.8, p.Z), IRON_EDGE, M.CorrodedMetal)
			K.Ball(m, "BrazierCoals", 2.6, at(p.X, p.Y + 4.7, p.Z), C(40, 20, 34), M.Slate)
			local flame = K.Part(m, "BrazierFlame", V3(1.6, 2.6, .2), at(p.X, p.Y + 6.1, p.Z) * ANG(0, a, 0), FLAME, M.Neon,
				{ Transparency = .2, Attrs = { HwBrazier = true } })
			K.Part(m, "BrazierFlame", V3(1.6, 2.2, .2), at(p.X, p.Y + 5.9, p.Z) * ANG(0, a + PI / 2, 0), C(230, 200, 255), M.Neon, { Transparency = .25 })
			local l = K.Light(flame, FLAME, 22, 1.2)
			l:SetAttribute("HwBaseBrightness", 1.2)
			lights += 1
			local host = G.EmitterPart(fx, "BrazierFire", V3(2, .6, 2), at(p.X, p.Y + 5.2, p.Z))
			G.Fire(host, { Color = FLAME, Color2 = C(90, 40, 170), Size = 2.4, Rate = 12 })
		end

		-------------------------------------------------------------------------------------------------------- ruins
		local function column(parent, base: CFrame, h: number, broken: boolean)
			K.Part(parent, "ColumnBase", V3(2.8, .8, 2.8), base * CF(0, .4, 0), C(78, 72, 88), M.Slate, G.Solid())
			local y = .8
			local drum = 1
			while y < h - .1 do
				local dh = math.min(rng:NextNumber(1.8, 2.6), h - y)
				K.CylY(parent, "ColumnDrum", dh, 1.9 - drum * .03, base * CF(rng:NextNumber(-.08, .08), y + dh / 2, rng:NextNumber(-.08, .08)) * ANG(0, drum, 0),
					C(96, 90, 106):Lerp(C(70, 66, 80), rng:NextNumber(0, 1)), M.Slate, G.Solid())
				y += dh
				drum += 1
			end
			if not broken then
				K.Part(parent, "ColumnCapital", V3(2.6, .7, 2.6), base * CF(0, h + .35, 0), C(110, 104, 120), M.Slate)
			else
				K.Wedge(parent, "ColumnBreak", V3(1.9, .9, 1.9), base * CF(0, h + .45, 0) * ANG(0, rng:NextNumber(0, PI), 0), C(96, 90, 106), M.Slate)
			end
			return base * CF(0, h + .7, 0)
		end
		local function ruinAt(kind: number, a: number)
			local p = polar(a, (TIER_B[1] + TIER_B[2]) / 2, TIER_B[3])
			local base = CF(p) * ANG(0, PI - a, 0) -- -Z faces the arena centre
			local m = K.Model(ruins, "Ruin")
			if kind == 1 then -- broken gothic arch: two columns, a half arch on one of them
				local top1 = column(m, base * CF(-3.4, 0, 0), 8, false)
				column(m, base * CF(3.4, 0, 0), 5.2, true)
				K.Part(m, "ArchSpring", V3(2.4, 1.4, 2.2), top1 * CF(1, .6, 0) * ANG(0, 0, -.35), C(104, 98, 116), M.Slate)
				K.Part(m, "ArchSpring", V3(2.2, 1.3, 2.1), top1 * CF(2.8, 1.5, 0) * ANG(0, 0, -.7), C(100, 94, 112), M.Slate)
				K.Wedge(m, "ArchRubble", V3(2, 1.2, 1.6), base * CF(1.5, .6, -1.4) * ANG(.3, .6, 0), C(90, 84, 100), M.Slate)
			elseif kind == 2 then -- toppled column + rubble
				column(m, base * CF(-2.5, 0, 0), 3, true)
				for d = 0, 2 do
					K.CylX(m, "FallenDrum", 2.3, 1.85, base * CF(.2 + d * 2.4, .9, rng:NextNumber(-.3, .3)) * ANG(0, rng:NextNumber(-.15, .15), 0), C(90, 84, 100), M.Slate, G.Solid())
				end
				G.Rubble(m, base * CF(1, 0, -1.6), 2.4, 5, rng, .9, { Color = C(80, 74, 90) })
			elseif kind == 3 then -- lancet wall fragment (pointed window hole)
				for _, s in ipairs({ -1, 1 }) do
					K.Part(m, "WallPier", V3(2.6, 10 + s * 1.5, 1.6), base * CF(s * 2.6, (10 + s * 1.5) / 2, 0) * ANG(0, 0, s * .02), C(70, 64, 80), M.Slate, G.Solid())
				end
				K.Part(m, "WallSill", V3(7.8, 1.2, 1.8), base * CF(0, .6, 0), C(64, 58, 74), M.Slate, G.Solid())
				Y.GableTri(m, "WallLancet", base * CF(0, 8.2, 0) * ANG(0, PI / 2, 0), 2.8, 2.4, 1.6, C(70, 64, 80), M.Slate)
				K.Part(m, "WallLancetGlow", V3(2.4, 5.4, .1), base * CF(0, 4.6, .2), C(60, 34, 100), M.Neon, { Transparency = .55 })
			elseif kind == 4 then -- a fallen bell shard: curved black iron plates with a violet crack
				for j = 0, 2 do
					K.Part(m, "BellShard", V3(4.2, .7, 3.2), base * CF(-2 + j * 2.6, 1 + j * .7, 0) * ANG(.5 - j * .25, .3 * j, .9 - j * .45), IRON_BLACK, M.CorrodedMetal, j == 0 and G.Solid() or nil)
				end
				K.Part(m, "BellShardCrack", V3(.18, .1, 3), base * CF(-2, 1.42, 0) * ANG(.5, 0, .9), RUNE, M.Neon)
				G.Rubble(m, base * CF(0, 0, -1.4), 2.6, 4, rng, .8, { Color = IRON_EDGE })
			elseif kind == 5 then -- mourning dog statue on a plinth, facing the bell
				K.Part(m, "StatuePlinth", V3(5, 2.2, 5), base * CF(0, 1.1, 0), C(64, 58, 74), M.Slate, G.Solid())
				K.Part(m, "StatuePlinthCap", V3(5.5, .4, 5.5), base * CF(0, 2.4, 0), C(96, 90, 106), M.Slate)
				Y.DogStatue(m, base * CF(0, 2.6, 0), { Bowed = true, Scale = 1.15, Color = C(128, 124, 142), Name = "MourningHound" })
				K.Candles(m, base * CF(1.8, 2.6, -1.8), 3, rng, { Light = false, Spread = .4 })
			else -- dog-skull gargoyle on a pillar
				K.Part(m, "GargoylePillar", V3(2.4, 7, 2.4), base * CF(0, 3.5, 0) * ANG(0, .3, .03), C(66, 60, 76), M.Slate, G.Solid())
				K.Part(m, "GargoylePillarCap", V3(3, .6, 3), base * CF(0, 7.2, 0), C(96, 90, 106), M.Slate)
				G.Skull(m, base * CF(0, 8.5, -.3), 2.2, RUNE, COL.Bone)
				K.Attach(K.Part(m, "GargoylePerch", V3(.2, .2, .2), base * CF(0, 9.8, 0), COL.Bone, nil, { Transparency = 1 }), "CrowPerch")
			end
		end
		local RUIN_ANGLES = { 15, 45, 75, 105, 135, 165, 195, 225, 255, 285, 315, 345 }
		local RUIN_KIND = { 6, 1, 2, 3, 5, 4, 1, 3, 2, 5, 1, 6 }
		for i, deg in ipairs(RUIN_ANGLES) do
			ruinAt(RUIN_KIND[i], math.rad(deg))
		end

		-------------------------------------------------------------------------------------------------- the gallows
		local BEAM_Y = BELL.Y + 26 -- crossbeam centre height
		local UPR = (TIER_B[1] + TIER_B[2]) / 2 -- uprights stand on tier B, east + west
		local tops = {}
		for _, sx in ipairs({ -1, 1 }) do
			local base = V3(AC.X + sx * UPR, TIER_B[3], AC.Z)
			-- plinth + iron foot
			K.Part(frame, "GallowsPlinth", V3(7, 3, 7), at(base.X, base.Y + 1.5, base.Z) * ANG(0, .1 * sx, 0), C(58, 52, 66), M.Slate, G.Solid())
			K.Part(frame, "GallowsPlinthCap", V3(6.2, 1, 6.2), at(base.X, base.Y + 3.5, base.Z) * ANG(0, .1 * sx + .4, 0), C(80, 74, 90), M.Slate, G.Solid())
			K.Part(frame, "GallowsFoot", V3(5, 1.6, 5), at(base.X, base.Y + 4.8, base.Z) * ANG(0, .7 * sx, 0), IRON_EDGE, M.CorrodedMetal, G.Solid())
			-- twisted upright: 10 segments, each turned a little further, leaning inward with a crooked wobble
			local y = base.Y + 5.4
			local n = 10
			local segH = (BEAM_Y - 2 - y) / n
			local prevTop
			for k = 1, n do
				local t = (k - .5) / n
				local lean = sx * -(t ^ 1.6) * 7
				local wob = math.sin(t * PI * 2.2 + sx) * 1.4
				local cx, cz = base.X + lean, base.Z + wob
				local cy = y + (k - .5) * segH
				local w = 5.2 - t * 1.2
				local seg = K.Part(frame, "GallowsUpright", V3(w, segH + .9, w), at(cx, cy, cz) * ANG(0, k * .32 * sx, 0) * ANG(rng:NextNumber(-.04, .04), 0, sx * .06 * t),
					IRON_BLACK, M.CorrodedMetal, G.Solid())
				if k % 2 == 0 then
					K.Part(frame, "GallowsCollar", V3(w + .5, .45, w + .5), at(cx, cy + segH / 2, cz) * ANG(0, k * .32 * sx + .1, 0), RUNE, M.Neon, { Transparency = .12 })
				end
				if k % 3 == 1 then -- iron thorns
					local d = V3(sx * -1, rng:NextNumber(-.2, .4), rng:NextNumber(-1, 1)).Unit
					K.Wedge(frame, "GallowsThorn", V3(.7, 2.6, .7), CF(V3(cx, cy, cz) + d * (w / 2 + .6)) * ANG(0, math.atan2(d.X, d.Z), 0) * ANG(-PI / 2 + .3, 0, 0),
						IRON_EDGE, M.CorrodedMetal)
					local d2 = V3(sx, rng:NextNumber(-.2, .4), rng:NextNumber(-1, 1)).Unit
					K.Wedge(frame, "GallowsThorn", V3(.7, 2.2, .7), CF(V3(cx, cy, cz) + d2 * (w / 2 + .5)) * ANG(0, math.atan2(d2.X, d2.Z), 0) * ANG(-PI / 2 + .3, 0, 0),
						IRON_EDGE, M.CorrodedMetal)
				end
				if k == 4 or k == 8 then -- glyphs facing the arena
					G.Rune(frame, at(cx - sx * (w / 2 + .05), cy, cz) * ANG(0, sx > 0 and PI / 2 or -PI / 2, 0) * ANG(0, PI, 0), k == 4 and "Bell" or "Eye", 3, RUNE,
						{ Depth = .12, Name = "GallowsGlyph" })
				end
				local _ = seg
				prevTop = V3(cx, cy + segH / 2, cz)
			end
			tops[sx] = prevTop
			-- brace from the upright to the beam
			local b0 = V3(base.X + sx * -4.2, BELL.Y + 2, base.Z + .5)
			local b1 = V3(AC.X + sx * 36, BEAM_Y - 1.5, AC.Z)
			local bm = b0:Lerp(b1, .5) + V3(0, 1.5, sx * .8)
			K.Rod(frame, "GallowsBrace", b0, bm, 1.6, IRON_BLACK, M.CorrodedMetal)
			K.Rod(frame, "GallowsBrace", bm, b1, 1.4, IRON_BLACK, M.CorrodedMetal)
			K.Ball(frame, "GallowsBraceKnot", 2, CF(bm), IRON_EDGE, M.CorrodedMetal)
			-- finial on the beam end: a crown of spikes and a dog skull looking down at the arena
			local fe = V3(prevTop.X, BEAM_Y + 2.6, prevTop.Z)
			for j = 0, 3 do
				local fa = j / 4 * PI * 2 + .4
				K.Wedge(frame, "GallowsFinial", V3(.9, 3.4, .9), CF(fe + V3(math.cos(fa) * 1.6, 1.4, math.sin(fa) * 1.6)) * ANG(math.sin(fa) * .3, 0, -math.cos(fa) * .3), IRON_EDGE, M.CorrodedMetal)
			end
			G.Skull(frame, CF(fe + V3(-sx * 2.4, -.4, 0)) * ANG(0, sx > 0 and PI / 2 or -PI / 2, 0) * ANG(-.5, 0, 0), 2.4, RUNE, COL.Bone)
			K.Attach(K.Part(frame, "GallowsPerch", V3(.2, .2, .2), CF(fe + V3(0, 3.6, 0)), IRON_EDGE, nil, { Transparency = 1 }), "CrowPerch")
		end
		-- the crooked crossbeam (6 kinked segments) from upright to upright
		do
			local a, b = tops[-1] + V3(0, 1.2, 0), tops[1] + V3(0, 1.2, 0)
			local n = 6
			local prev = a
			for k = 1, n do
				local t = k / n
				local q = a:Lerp(b, t) + V3(0, (k < n) and math.sin(t * PI) * 2.2 + rng:NextNumber(-.8, .8) or 0, (k < n) and rng:NextNumber(-1, 1) or 0)
				local seg = K.Bar(frame, "GallowsBeam", prev, q, 4.6, 4.2, IRON_BLACK, M.CorrodedMetal)
				seg.Size = V3(seg.Size.X, seg.Size.Y, seg.Size.Z + 2.2)
				if k % 2 == 1 then
					K.Bar(frame, "GallowsBeamBand", prev:Lerp(q, .45), prev:Lerp(q, .55), 4.9, 4.5, RUNE, M.Neon, { Transparency = .15 })
				end
				prev = q
			end
			-- headstock over the bell + a heavy shackle down to the crown
			local hs = V3(BELL.X, BEAM_Y + 2.6, BELL.Z)
			K.Part(frame, "BellHeadstock", V3(9, 5.2, 7), CF(hs) * ANG(0, .05, .03), IRON_EDGE, M.CorrodedMetal)
			K.Part(frame, "BellHeadstockCap", V3(10, 1, 8), CF(hs + V3(0, 3, 0)) * ANG(0, .08, 0), IRON_BLACK, M.CorrodedMetal)
			local crownTop = BELL.Y + 13.4
			for _, s in ipairs({ -1, 1 }) do
				K.Bar(frame, "BellStrap", hs + V3(s * 2.4, -2.4, 0), V3(BELL.X + s * 1.1, crownTop + 1.6, BELL.Z), .9, 1.2, IRON_BLACK, M.CorrodedMetal)
			end
			K.CylZ(frame, "BellShacklePin", 3.6, .9, CF(V3(BELL.X, crownTop + 1.4, BELL.Z)), IRON_EDGE, M.CorrodedMetal)
			-- two hanging lanterns on chains (light when Seal VII is cleared)
			for _, s in ipairs({ -1, 1 }) do
				local hook = V3(AC.X + s * 26, BEAM_Y - 1.6 + math.sin((.5 + s * 26 / 124) * PI) * 2, AC.Z)
				local hang = hook - V3(0, 9, 0)
				G.Chain(frame, hook, hang, 0, { Link = 1.3, Thick = .22, Width = .55 })
				G.CageLantern(frame, CF(hang), RUNE, "Purple", { Light = 30, Brightness = 1.2, Scale = 1.6, Attrs = { UyLightAtSeal = SEAL } })
				lights += 1
			end
		end

		------------------------------------------------------------------------------------------------ THE BLACK BELL
		local bellCrownCF
		do
			local m = K.Model(root, "BlackBell")
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			m:SetAttribute("UySwing", true)
			m:SetAttribute("UySwingAmp", 4) -- degrees: a slow menacing sway (client), struck harder on trial events
			local B = BELL
			local bot = B.Y - 11 -- lip bottom
			local function bcf(y: number, dx: number?, dz: number?)
				return at(B.X + (dx or 0), y, B.Z + (dz or 0))
			end
			-- the crown (PrimaryPart): the pivot the bell swings on
			local crownY = B.Y + 11.8
			local crown = K.Part(m, "BellCrown", V3(3.8, 2.2, 3.8), bcf(crownY), IRON_EDGE, M.CorrodedMetal)
			m.PrimaryPart = crown
			bellCrownCF = crown.CFrame
			-- canons: four arched loops + a central eye loop
			for k = 0, 3 do
				local a = k / 4 * PI * 2 + PI / 4
				local p0 = bcf(crownY + 1, math.cos(a) * 1.5, math.sin(a) * 1.5).Position
				local p1 = bcf(crownY + 2.4, math.cos(a) * .9, math.sin(a) * .9).Position
				K.Bar(m, "BellCanon", p0, p1, .6, .6, IRON_BLACK, M.CorrodedMetal)
			end
			K.CylZ(m, "BellCanonEye", .7, 2.2, bcf(crownY + 2.2), IRON_BLACK, M.CorrodedMetal)
			-- shoulder dome + stepped waist (each tier a little crooked) + sound bow
			K.Ellipsoid(m, "BellShoulder", V3(13.8, 5.4, 13.8), bcf(B.Y + 8.4), BELL_IRON, M.CorrodedMetal)
			-- waist: eight tiers following a concave flare from the shoulder (d 13.4) to the sound bow (d 20)
			local NT = 8
			local yTop, yBot = B.Y + 8, bot + 3.6
			local function tierD(i: number): number
				local u = (i - .5) / NT
				return 13.4 + (19.6 - 13.4) * u ^ 1.8
			end
			-- outer radius of the waist at height y (the stepped profile; the sound bow below, the shoulder above)
			local function bellR(y: number): number
				if y >= yTop then
					return 6.7
				elseif y <= yBot then
					return 10.2
				end
				local i = math.clamp(math.floor((yTop - y) / ((yTop - yBot) / NT)) + 1, 1, NT)
				return tierD(i) / 2
			end
			for i = 1, NT do
				local y1 = yTop - (i - 1) * (yTop - yBot) / NT
				local y0 = yTop - i * (yTop - yBot) / NT
				K.CylY(m, "BellTier", y1 - y0 + .25, tierD(i), bcf((y0 + y1) / 2, rng:NextNumber(-.15, .15), rng:NextNumber(-.15, .15)) * ANG(rng:NextNumber(-.015, .015), i * .4, rng:NextNumber(-.015, .015)),
					BELL_IRON:Lerp(IRON_EDGE, (i % 2) * .18), M.CorrodedMetal)
			end
			K.CylY(m, "BellSoundBow", 1.6, 20.4, bcf(bot + 2.9), BELL_EDGE, M.CorrodedMetal)
			-- the hollow mouth: an ink ceiling set back above a flared lip ring
			K.CylY(m, "BellMouthDark", .3, 19.2, bcf(bot + 2.05), COL.Ink, M.SmoothPlastic)
			for k = 0, 19 do
				local a = (k + .5) / 20 * PI * 2
				local cf = bcf(bot + 1, math.cos(a) * 10.1, math.sin(a) * 10.1) * ANG(0, -a, 0) * ANG(0, 0, .28)
				K.Part(m, "BellLip", V3(1.1, 2.2, 3.4), cf, BELL_EDGE, M.CorrodedMetal)
			end
			-- violet rune bands + six big glyphs on the waist + a crack running down one flank (all on the profile)
			for _, by in ipairs({ B.Y - 2.6, B.Y + 3.4 }) do
				G.Ring(m, bcf(by), bellR(by + .25) + .14, 22, .3, .5, RUNE, M.Neon, { Fill = .72, Name = "BellRuneBand" })
			end
			for k = 0, 5 do
				local a = k / 6 * PI * 2 + PI / 6
				local o = V3(math.sin(a), 0, -math.cos(a))
				local gy = B.Y - .4
				local p = V3(B.X, gy, B.Z) + o * (math.max(bellR(gy - 1.4), bellR(gy + 1.4)) + .3)
				G.Rune(m, K.Look(p, p + o), G.GlyphNames[k + 1], 3.2, RUNE, { Depth = .14, Width = .13, Name = "BellGlyph" })
			end
			do
				local o = V3(math.sin(2.1), 0, -math.cos(2.1))
				local y = B.Y + 7
				local prev = V3(B.X, y, B.Z) + o * (bellR(y) + .12)
				for _ = 1, 5 do
					y -= 3.1
					local q = V3(B.X, y, B.Z) + o * (bellR(y) + .12) + V3(-o.Z, 0, o.X) * rng:NextNumber(-.8, .8)
					K.Bar(m, "BellCrack", prev, q, .28, .28, RUNE, M.Neon)
					prev = q
				end
			end
			-- the dog skull relief facing the approach (north)
			G.Skull(m, bcf(B.Y + 1.4, 0, -7.5), 4, RUNE, COL.Bone:Lerp(IRON_EDGE, .3))
			-- clapper hanging out of the mouth + the violet inner light
			K.Bar(m, "BellClapperRod", V3(B.X, bot + 2.2, B.Z), V3(B.X + .3, bot - .2, B.Z), .7, .7, IRON_EDGE, M.CorrodedMetal)
			K.Ball(m, "BellClapper", 3.2, bcf(bot - .9, .35, 0), IRON_BLACK, M.CorrodedMetal)
			K.Ball(m, "BellClapperCore", 1.3, bcf(bot - 2.25, .35, 0), RUNE, M.Neon)
			local glow = K.Part(m, "BellInnerGlow", V3(.4, .4, .4), bcf(bot + 1.2), RUNE, nil, { Transparency = 1 })
			K.Light(glow, RUNE, 48, 1.6):SetAttribute("HwBaseBrightness", 1.6)
			lights += 1
			local mote = G.EmitterPart(fx, "BellMotes", V3(16, 6, 16), bcf(B.Y - 2))
			G.Motes(mote, { Color = RUNE, Rate = 4, Size = .45, Speed = .5 })
		end

		------------------------------------------------------------------------------------------- the chain anchors
		for _, key in ipairs({ "N", "E", "S", "W" }) do
			local c = A.Chains[key]
			local m = K.Model(root, "ArenaChain_" .. key)
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			m:SetAttribute("ChainKey", key)
			local toC = V3(AC.X - c.X, 0, AC.Z - c.Z).Unit
			local bcf = K.Look(V3(c.X, 0, c.Z), V3(c.X, 0, c.Z) + toC) -- -Z faces the bell
			-- (compact base: the north anchor stands 5 studs from the arena's edge spawn)
			local post = K.Part(m, "AnchorBase", V3(4, 1.2, 4), bcf * CF(0, .6, 0), C(70, 64, 80), M.Slate, G.Solid())
			m.PrimaryPart = post
			K.Part(m, "AnchorBaseCap", V3(3.5, .4, 3.5), bcf * CF(0, 1.4, 0) * ANG(0, PI / 4, 0), C(96, 90, 106), M.Slate, G.Solid())
			K.CylY(m, "AnchorPost", 4.2, 2.6, bcf * CF(0, 3.5, 0), IRON_BLACK, M.CorrodedMetal, G.Solid())
			K.Ball(m, "AnchorCap", 2.9, bcf * CF(0, 5.6, 0), IRON_EDGE, M.CorrodedMetal)
			local band = K.CylY(m, "ChainGlow", .5, 2.9, bcf * CF(0, 3.2, 0), RUNE, M.Neon, { Transparency = .1, Attrs = { ChainKey = key } })
			for j = 0, 3 do
				local ja = j / 4 * PI * 2
				K.Wedge(m, "AnchorSpike", V3(.6, 1.4, .6), bcf * CF(math.cos(ja) * 1.45, 2.2, math.sin(ja) * 1.45) * ANG(0, -ja, 0) * ANG(0, 0, .5), IRON_EDGE, M.CorrodedMetal)
			end
			-- shackle ring on the cap
			G.Ring(m, bcf * CF(0, 6.4, -.4) * ANG(PI / 2, 0, 0), .9, 8, .3, .3, IRON_EDGE, M.CorrodedMetal, { Name = "AnchorShackle" })
			local l = K.Light(band, RUNE, 14, .8)
			l:SetAttribute("HwBaseBrightness", .8)
			lights += 1
			-- the chain up to the bell's waist
			local from = (bcf * CF(0, 6.5, -.4)).Position
			local to = V3(BELL.X, BELL.Y - 3.4, BELL.Z) - toC * 8.6
			G.Chain(m, from, to, 2.5, { Link = 2.3, Thick = .45, Width = 1.1, Color = IRON_BLACK })
			K.Ball(m, "ChainBellShackle", 1.6, CF(to), IRON_EDGE, M.CorrodedMetal)
		end

		------------------------------------------------------------------------------------------------- the approach
		local zA, zB = AP.From.Z, AP.To.Z
		local ringZ = AC.Z - TIER_B[2] -- where the ring's outer face crosses the straight approach line
		if bridgePath then
			-- the framework's winding approach bridge (18 wide, over the abyss): dress its edges from the outside — stone
			-- corbels hung on the deck sides carry chained iron posts, bell banners and little grave balconies, so nothing
			-- stands on the walkway (its parapets + side colliders stay the edge) and nothing blocks its lamps
			local total = G.PathLength(bridgePath)
			local HALF = ROAD_HALF
			local avoid = {}
			for _, p in ipairs(G.Named(ctx.Root, "LampCorbel", root)) do
				table.insert(avoid, p.CFrame.Position)
			end
			local taken = {} -- {pos} of my own items, per side, for spacing
			local function clear(p: Vector3, r: number): boolean
				for _, q in ipairs(avoid) do
					if G.Flat(p, q) < r then
						return false
					end
				end
				for _, q in ipairs(taken) do
					if G.Flat(p, q) < r then
						return false
					end
				end
				return true
			end
			-- deck-edge frame at distance s: point on the outer face of the deck side `side` (+1 right of travel), the
			-- deck top there, the travel direction and the outward unit vector
			local function edgeAt(s: number, side: number, out: number): (Vector3, Vector3)
				local c, d = G.PathAt(bridgePath, s)
				local top = G.DeckTop(deck, c.X, c.Z) or G.DeckTop(deck, c.X + d.X, c.Z + d.Z) or 0
				local o = V3(-d.Z, 0, d.X) * side
				local p = c + o * (HALF + out)
				return V3(p.X, top, p.Z), o
			end
			local function corbel(p: Vector3, o: Vector3, w: number, depth: number, name: string): CFrame
				local cf = K.Look(p, p + o) -- -Z points away from the deck
				K.Part(approach, name, V3(w, .8, depth), cf * CF(0, -.4, 0), C(62, 56, 70), M.Slate, G.Solid())
				K.Wedge(approach, name .. "Bracket", V3(w * .8, 2, depth * .95), cf * CF(0, -1.8, 0) * ANG(PI, 0, 0), C(52, 46, 60), M.Slate)
				return cf
			end
			local sMin, sMax = 10, total - 14 -- clear of the gate arch and of the ring at the landing
			-- bell banners, alternating sides
			for i, s0 in ipairs({ 23, 46, 70, 93, 115 }) do
				local side = i % 2 == 1 and 1 or -1
				for shift = 0, 3 do
					local s = s0 + shift * 4
					local p = edgeAt(s, side, 1.3)
					if s <= sMax and clear(p, 5) then
						local _, o = edgeAt(s, side, 1.3)
						corbel(p, o, 2.6, 2.6, "BannerCorbel")
						G.Banner(approach, K.Look(p, p - o), 13 + (i % 2) * 2.5, i % 2 == 0 and COL.Cloth or COL.ClothViolet, rng,
							{ Sigil = i % 2 == 0 and "Eye" or "Bell", Glow = RUNE })
						table.insert(taken, p)
						break
					end
				end
			end
			-- grave balconies: a ledge with a headstone facing the walkers, candles at its foot (4, spread along the bridge)
			local balconies = 0
			local s = 28
			while balconies < 4 and s <= sMax do
				local placed = false
				for _, side in ipairs(balconies % 2 == 0 and { -1, 1 } or { 1, -1 }) do
					local p, o = edgeAt(s, side, 1.9)
					if not placed and clear(p, 6) then
						balconies += 1
						corbel(p, o, 4.2, 3.8, "GraveBalcony")
						Y.Tombstone(approach, K.Look(p, p - o) * CF(0, 0, .4), ({ 1, 3, 8, 5 })[balconies], rng, nil, { Color = COL.Stone })
						K.Candles(approach, K.Look(p, p - o) * CF(1.3, 0, -.9), 3, rng, { Light = false, Spread = .35 })
						table.insert(taken, p)
						placed = true
					end
				end
				s += placed and 24 or 5
			end
			-- chained iron posts on small corbels every ~9 studs on both sides, chains sagging between them
			for _, side in ipairs({ -1, 1 }) do
				local prevTop, prevS = nil, nil
				local s = sMin
				while s <= sMax do
					local p, o = edgeAt(s, side, .9)
					if clear(p, 3.2) then
						corbel(p, o, 1.6, 1.8, "ChainCorbel")
						K.CylY(approach, "ChainPost", 2.8, .6, CF(p + V3(0, 1.4, 0)) * ANG(rng:NextNumber(-.05, .05), 0, rng:NextNumber(-.05, .05)), IRON_BLACK, M.CorrodedMetal, G.Solid())
						K.Ball(approach, "ChainPostKnob", .85, CF(p + V3(0, 2.9, 0)), IRON_EDGE, M.CorrodedMetal)
						local top = p + V3(0, 2.5, 0)
						if prevTop and s - prevS < 16 then
							G.Chain(approach, prevTop, top, 1.1, { Link = 1.6, Thick = .18, Width = .45 })
						end
						prevTop, prevS = top, s
					end
					s += 9
				end
			end
		else
			-- standalone (no framework approach bridge): a straight road along Arena.Approach between terraced banks rising
			-- into a canyon towards the ring; kerbs + chained posts on the road edges, graves, banners, lamps, mausoleums
			local TERR = { -- {inner |x|, z start, top}
				{ ROAD_HALF + 1.2, zA + 14, 1.4 }, { ROAD_HALF + 5, zA + 34, 2.4 }, { ROAD_HALF + 9.5, zA + 52, 3.4 },
			}
			local zEnd = ringZ + 1.5
			for ti, t in ipairs(TERR) do
				for _, s in ipairs({ -1, 1 }) do
					local xi, xo = t[1], 42 + ti * 4
					local za, zb2 = t[2], zEnd
					K.Part(approach, "BankTerrace", V3(xo - xi, t[3] + .1, zb2 - za), at(AC.X + s * (xi + xo) / 2, t[3] / 2 - .05, (za + zb2) / 2), C(54, 48, 58), M.Ground, G.Solid())
					local nw = math.max(1, math.floor((zb2 - za) / 7))
					for k = 0, nw - 1 do
						local zc = za + (k + .5) * (zb2 - za) / nw
						K.Part(approach, "BankWall", V3(1.2, t[3] + .45, (zb2 - za) / nw + .3), at(AC.X + s * (xi + .3), (t[3] + .45) / 2, zc) * ANG(0, rng:NextNumber(-.03, .03), s * rng:NextNumber(0, .03)),
							C(76, 70, 84):Lerp(C(60, 56, 68), rng:NextNumber(0, 1)), M.Cobblestone, G.Solid())
					end
					K.Part(approach, "BankWall", V3(xo - xi, t[3] + .45, 1.2), at(AC.X + s * (xi + xo) / 2, (t[3] + .45) / 2, za + .3), C(70, 64, 78), M.Cobblestone, G.Solid())
				end
			end
			for _, s in ipairs({ -1, 1 }) do
				local x = AC.X + s * (ROAD_HALF + .45)
				K.Part(approach, "RoadKerb", V3(.9, .5, zB - zA - 14), at(x, .2, (zA + 12 + zB - 2) / 2), C(84, 78, 92), M.Slate, G.Solid())
				local prev
				local np = 8
				for k = 0, np do
					local z = zA + 12 + k * (zB - zA - 16) / np
					local post = V3(x, 0, z)
					K.CylY(approach, "ChainPost", 3, .7, at(post.X, 1.5, post.Z) * ANG(rng:NextNumber(-.05, .05), 0, rng:NextNumber(-.05, .05)), IRON_BLACK, M.CorrodedMetal, G.Solid())
					K.Ball(approach, "ChainPostKnob", .9, at(post.X, 3.1, post.Z), IRON_EDGE, M.CorrodedMetal)
					local top = V3(post.X, 2.7, post.Z)
					if prev and k ~= 4 then
						G.Chain(approach, prev, top, .9, { Link = 1.5, Thick = .18, Width = .45 })
					end
					prev = top
				end
			end
			for _, s in ipairs({ -1, 1 }) do
				for k = 0, 6 do
					local z = zA + 17 + k * 7.6 + rng:NextNumber(-1, 1)
					local x = AC.X + s * (ROAD_HALF + 3 + rng:NextNumber(0, .8))
					Y.Tombstone(approach, at(x, TERR[1][3], z) * ANG(0, s * PI / 2 + rng:NextNumber(-.25, .25), 0), ({ 1, 3, 4, 6, 8, 2, 5 })[k + 1], rng, nil, { Color = COL.Stone })
				end
				for k = 0, 3 do
					local z = TERR[2][2] + 3 + k * 8.5
					G.Banner(approach, at(AC.X + s * (ROAD_HALF + 7.5), TERR[2][3], z) * ANG(0, s * PI / 2, 0), 13 + (k % 2) * 2.5, k % 2 == 0 and COL.Cloth or COL.ClothViolet, rng,
						{ Sigil = k % 2 == 0 and "Bell" or "Eye", Glow = RUNE })
				end
			end
			for i, z in ipairs({ zA + 20, zA + 45, zA + 70 }) do
				for _, s in ipairs({ -1, 1 }) do
					if i == 2 or (i == 1 and s < 0) or (i == 3 and s > 0) then
						local p = V3(AC.X + s * (ROAD_HALF + 1.9), z + s * 3 >= zA + 14 and 1.4 or 0, z + s * 3) -- on the first terrace's edge
						G.LampPost(lamps, K.Look(p, p + V3(-s, 0, 0)), 9, COL.Candle, "Orange", rng, { Light = 20, Brightness = 1.1 })
						lights += 1
					end
				end
			end
			-- the banks are an old burial ground: rows of graves, a crooked mausoleum, dead trees, bone piles
			for _, s in ipairs({ -1, 1 }) do
				for k = 0, 5 do
					local x = AC.X + s * (24 + k * 4.2 + rng:NextNumber(-.6, .6))
					Y.Tombstone(approach, at(x, TERR[2][3], TERR[2][2] + 6 + rng:NextNumber(-1, 1)) * ANG(0, PI + rng:NextNumber(-.2, .2), 0), rng:NextInteger(1, 9), rng, nil, { Color = COL.Stone })
					Y.Tombstone(approach, at(x + s * 2, TERR[1][3], TERR[1][2] + 6 + rng:NextNumber(-1, 1)) * ANG(0, PI + rng:NextNumber(-.2, .2), 0), rng:NextInteger(1, 9), rng, nil, { Color = COL.Stone })
				end
				local mb = at(AC.X + s * 41, TERR[3][3], zEnd - 7) * ANG(0, s * .12, 0) -- -Z (the door) faces north, up the approach
				K.Part(approach, "MausoleumBase", V3(8.4, .8, 9.4), mb * CF(0, .4, 0), C(64, 58, 74), M.Slate, G.Solid())
				K.Part(approach, "MausoleumBody", V3(7, 6.4, 8), mb * CF(0, 4, 0) * ANG(0, 0, s * .04), C(84, 78, 94), M.Slate, G.Solid())
				Y.GableTri(approach, "MausoleumRoof", mb * CF(0, 7.2, 0), 9.2, 3.8, 7.8, C(50, 44, 58), M.Slate, true)
				K.Part(approach, "MausoleumDoor", V3(2.8, 4.2, .2), mb * CF(0, 2.9, -4.05), C(18, 14, 24), M.SmoothPlastic)
				Y.GableTri(approach, "MausoleumDoorHead", mb * CF(0, 5, -4.05) * ANG(0, PI / 2, 0), 2.8, 1.2, .2, C(18, 14, 24), M.SmoothPlastic)
				G.Skull(approach, mb * CF(0, 6.7, -4.2), 1.2, RUNE, COL.Bone)
				for _, sx in ipairs({ -1, 1 }) do
					K.Part(approach, "MausoleumPilaster", V3(.9, 6.6, .9), mb * CF(sx * 3.3, 4.1, -4.05), C(104, 98, 114), M.Slate)
				end
				K.Candles(approach, mb * CF(-1.6, .8, -5), 3, rng, { Light = false, Spread = .4 })
				Y.Tree(approach, at(AC.X + s * 30, TERR[3][3], zEnd - 9), rng:NextNumber(12, 15), rng, { Branches = 3, Perches = 2, Bats = true })
				Y.Tree(approach, at(AC.X + s * 44, TERR[1][3], TERR[1][2] + 12), rng:NextNumber(10, 13), rng, { Branches = 3, Perches = 1 })
				Y.BonePile(approach, at(AC.X + s * 30, TERR[2][3], TERR[2][2] + 12), rng, 4, true)
				Y.IronFence(approach, V3(AC.X + s * 20, TERR[2][3], TERR[2][2] + 10), V3(AC.X + s * 20, TERR[2][3], TERR[2][2] + 17), { Height = 2.4, Spacing = 1.3, Broken = .2 }, rng)
				for ti, t in ipairs(TERR) do
					G.Rubble(approach, at(AC.X + s * (42 + ti * 4 + 1.5), 0, (t[2] + zEnd) / 2), 3, 4, rng, 1.6, { Color = C(70, 64, 76), Min = 1.2, Max = 2.8 })
				end
			end
		end

		-- at the ring gap (both cases): two mourning hounds on tier B flanking the way in, and a crooked iron entry arch
		-- with a small bell over it
		do
			local rMid = (TIER_B[1] + TIER_B[2]) / 2
			for _, s in ipairs({ -1, 1 }) do
				local x = ROAD_HALF + 6.6
				local p = V3(AC.X + s * x, TIER_B[3], AC.Z - math.sqrt(rMid * rMid - x * x))
				local hb = K.Look(p, p + V3(-s * .45, 0, -1).Unit)
				K.Part(approach, "HoundPlinth", V3(4.6, 1.4, 4.6), hb * CF(0, .7, 0), C(64, 58, 74), M.Slate, G.Solid())
				K.Part(approach, "HoundPlinthCap", V3(5, .4, 5), hb * CF(0, 1.55, 0), C(96, 90, 106), M.Slate)
				Y.DogStatue(approach, hb * CF(0, 1.75, 0), { Bowed = true, Scale = 1.45, Color = C(120, 116, 134), EyeColor = RUNE, Name = "GateHound" })
			end
			local gx = ROAD_HALF + 2.2
			local gz = AC.Z - math.sqrt((TIER_B[1] + 1.6) ^ 2 - gx * gx)
			local hs = {}
			for _, s in ipairs({ -1, 1 }) do
				local b = V3(AC.X + s * gx, 0, gz)
				local t = b + V3(-s * 1.2, TIER_B[3] + 15, 0)
				K.Rod(approach, "EntryPost", b, t, 1.4, IRON_BLACK, M.CorrodedMetal, G.Solid())
				K.Wedge(approach, "EntryPostThorn", V3(.6, 2, .6), CF(t + V3(0, 1, 0)), IRON_EDGE, M.CorrodedMetal)
				hs[s] = t
			end
			local mid = hs[-1]:Lerp(hs[1], .5) + V3(0, 2.4, 0)
			K.Bar(approach, "EntryBeam", hs[-1] - V3(0, .6, 0), mid, 1.2, 1.2, IRON_BLACK, M.CorrodedMetal)
			K.Bar(approach, "EntryBeam", mid, hs[1] - V3(0, .6, 0), 1.2, 1.2, IRON_BLACK, M.CorrodedMetal)
			K.Part(approach, "EntryBand", V3(1.5, 1.5, 1.5), CF(mid) * ANG(0, 0, PI / 4), RUNE, M.Neon, { Transparency = .1 })
			local hang = mid - V3(0, 4.2, 0)
			G.Chain(approach, mid - V3(0, .7, 0), hang + V3(0, 1, 0), 0, { Link = .8, Thick = .16, Width = .4 })
			K.CylY(approach, "EntryBell", 1.6, 1.8, CF(hang), IRON_BLACK, M.CorrodedMetal)
			K.Ball(approach, "EntryBellCrown", 1.4, CF(hang + V3(0, .9, 0)), IRON_BLACK, M.CorrodedMetal)
			K.CylY(approach, "EntryBellLip", .3, 2.2, CF(hang - V3(0, .8, 0)), IRON_EDGE, M.CorrodedMetal)
			K.Ball(approach, "EntryBellClapper", .6, CF(hang - V3(0, 1.2, 0)), RUNE, M.Neon)
			K.Attach(K.Part(approach, "EntryPerch", V3(.2, .2, .2), CF(mid + V3(0, 1, 0)), IRON_EDGE, nil, { Transparency = 1 }), "CrowPerch")
		end

		------------------------------------------------------------------------------------------------ outer grounds
		do
			-- standalone: the whole box outside the ring + banks; on the framework island: its south strip only (the rest
			-- of the box is the abyss)
			local function free(p: Vector3, r: number): boolean
				if p.X < X0 + 3 or p.X > X1 - 3 or p.Z < Z0 + 3 or p.Z > Z1 - 3 then
					return false
				end
				if G.Flat(p, AC) < TIER_B[2] + 2 + r then
					return false
				end
				if base then
					return math.abs(p.X - AC.X) < 40 - r and p.Z > AC.Z + 60
				end
				return not (math.abs(p.X - AC.X) < 48 + 12 + r and p.Z < AC.Z - 40)
			end
			local n, tries = 0, 0
			local want = base and 12 or 22
			while n < want and tries < 600 do
				tries += 1
				local p = V3(rng:NextNumber(X0, X1), 0, rng:NextNumber(Z0, Z1))
				if free(p, 2) then
					n += 1
					local gy = base and 0 or -.1
					if n % 6 == 0 then
						Y.Tree(outer, at(p.X, gy, p.Z), rng:NextNumber(11, 15), rng, { Branches = 3, Perches = 2 })
					else
						Y.Tombstone(outer, at(p.X, gy, p.Z) * ANG(0, rng:NextNumber(0, PI * 2), 0), rng:NextInteger(1, 9), rng, nil, { Color = COL.Stone })
					end
				end
			end
			local FOG = base and { V3(0, 0, 2700), V3(-28, 0, 2698), V3(28, 0, 2698) }
				or { V3(-50, 0, 2505), V3(50, 0, 2505), V3(0, 0, 2706), V3(-62, 0, 2700), V3(62, 0, 2700) }
			for _, p in ipairs(FOG) do
				local host = G.EmitterPart(fx, "GroundFog", V3(22, 1, 22), at(p.X, .6, p.Z))
				G.Fog(host, { Color = C(150, 140, 230), Color2 = COL.MoonDim, Rate = 1.1 })
			end
			for _, p in ipairs(base and { V3(-20, 0, 2696), V3(20, 0, 2696) } or { V3(-30, 0, 2520), V3(30, 0, 2520), V3(-60, 0, 2650), V3(60, 0, 2650) }) do
				Y.Marker(fx, "FogPoint", p + V3(0, .4, 0))
			end
		end

		local parts, nl, emitters = G.Count(root)
		ctx.Note(string.format("BlackBellArena: %d parts, %d lights, %d emitters (budget 3000 / 30); bell crown at %s", parts, nl, emitters,
			tostring(bellCrownCF and bellCrownCF.Position)))
		local _ = lights
		return root
	end,
}
