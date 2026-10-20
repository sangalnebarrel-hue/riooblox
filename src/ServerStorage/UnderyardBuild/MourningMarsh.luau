-- THE UNDERYARD · MOURNING MARSH (Seal III: MIRROR GRAVES) — ServerStorage.UnderyardBuild.MourningMarsh, WP-H3.
-- Build-time builder (Order 50) run by tools/edits/40_underyard.luau; its output is saved in the place as the model
-- 40_Underyard.MourningMarsh (attribute UyDistrict = "MourningMarsh"). DESIGN §7, §8.4 item 3, §22.6. Every coordinate
-- comes from UnderyardLayout (Marsh / MirrorGraves / Gates / ChoirPaths / Districts); nothing here moves an anchor.
-- What it builds inside the district box x -222..-75, z 2470..2712:
--   * its own ground: a mud bed (top Marsh.GroundY) under a sheet of black water (dark Glass, top Marsh.WaterY,
--     CanCollide false) with Neon moon-blue edges where it meets the banks / islands; mud banks rise to the neighbours'
--     floor (y 0) on the north + east edges. The marsh is shallow: wading players stand on the mud bed.
--   * boardwalks (deck top Marsh.BoardwalkY, 9 wide; invisible solid floor under weathered planks): the gate path (via
--     ChoirPath_7), a ring around the mirror pond (passes ChoirPath_8 / ChoirPath_9), short spurs to the six grave
--     islands, a south branch to the Funeral Landing jetty on the Black Mere and a west branch to the Weeping Dog shrine.
--   * THE MIRROR POND at Marsh.Pond: a flat reflective dark disc (Glass + Reflectance) inside a crooked stone rim,
--     with a Neon edge, an under-glow and an invisible collider ring that keeps players off the mirror.
--   * THE SIX MIRROR GRAVES at UnderyardLayout.MirrorGraves: grave islands joined to the ring; each headstone is the
--     hinge model `MirrorGrave_<i>_Stone` (ModelStreamingMode Atomic, PrimaryPart `StoneHinge` at its base, world-axis
--     aligned) with a Neon rune glyph on its +Z face and a little dog skull on top facing the same way (the runtime
--     turns it in 90° steps with PivotTo(hinge * Angles(0, k * pi/2, 0)); attributes MirrorGrave = i, Rune = glyph).
--   * THE CONSULT STONE at Marsh.Consult: a dog-faced scrying basin on the north terrace (grave 1 island), facing the pond.
--   * dressing: dead willows with hanging moss, funeral boats (two moored at the jetty, one adrift, one beached),
--     glowing flowers (Neon petals) on tussocks and lily pads, reeds, sunken graves and coffins, the Black Mere (deep,
--     ink-black water fenced by invisible colliders), blue fog emitters + motes in the SelfManagedFX model `MarshFog`.
-- Seal state (§7.3): the boat / jetty lanterns and the willow wisps carry UyLightAtSeal = 3 (they light up when the
-- player clears Seal III); moon lilies on the pond rim carry UyShowAtSeal = 3. Lantern glass: HwLantern, candles HwCandle.
-- Budgets: <= 3 000 parts, <= 30 lights (reported through ctx.Note).
local G = require(script.Parent.GothicProps)
local K, Y = G.K, G.Y
local COL = G.Col
local C = Color3.fromRGB
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local SEAL = 3 -- MIRROR GRAVES
local RING_R, RING_W = 39, 9 -- pond ring boardwalk: centre radius / width (contains ChoirPath_8 r 37.6 and _9 r 42.8)
local DECK_W = 9 -- gate path / branches
local ISLAND_R = 5.25 -- grave island top radius (centred on the grave)
local MUD, MUD_DARK, BANK = C(44, 36, 38), C(30, 24, 28), C(58, 48, 44)
local WATER = C(12, 16, 32)
local EDGE = C(110, 170, 255)
local PLANKS = { C(74, 62, 54), C(62, 52, 48), C(86, 72, 60), C(70, 72, 58), C(56, 46, 44) }
local BLOOM = { C(150, 200, 255), C(176, 120, 255), C(120, 255, 140), C(200, 230, 255) }

local function districtBox(L, name)
	for _, d in ipairs(L.Districts) do
		if d.Name == name then
			return d
		end
	end
	error("UnderyardLayout.Districts has no " .. name)
end

return {
	Order = 50,
	Build = function(ctx)
		local L = ctx.Layout
		local MK = L.Marsh
		local GY, WY, BY = MK.GroundY, MK.WaterY, MK.BoardwalkY
		local box = districtBox(L, "MourningMarsh")
		local X0, X1, Z0, Z1 = box.Min.X, box.Max.X, box.Min.Z, box.Max.Z
		local PC = MK.Pond.Centre
		local PR = MK.Pond.Radius
		local rng = G.Rng(50311)

		local root = ctx.Model("MourningMarsh")
		root:SetAttribute("UyDistrict", "MourningMarsh")
		root:SetAttribute("Seal", SEAL)
		local function sub(name)
			return K.Model(root, name)
		end
		local ground, decks, pond, graves, flora, props, lamps, colliders =
			sub("Ground"), sub("Boardwalks"), sub("MirrorPond"), sub("MirrorGraves"), sub("Flora"), sub("Props"), sub("Lamps"), sub("Colliders")
		local fx = G.FXModel(root, "MarshFog")

		local function at(x, y, z)
			return CF(x, y, z)
		end
		local function polar(a: number, r: number, y: number): Vector3 -- UnderyardLayout.Ring convention: a = 0 is north (-Z)
			return V3(PC.X + math.sin(a) * r, y, PC.Z - math.cos(a) * r)
		end
		local function plankColor()
			return PLANKS[rng:NextInteger(1, #PLANKS)]:Lerp(COL.Ink, rng:NextNumber(0, .15))
		end

		-- keep-out list: decor never lands on walkways / islands / the pond
		local walk = {} -- {a, b, halfWidth} segments + {centre, radius} discs
		local discs = {}
		local function onWalk(p: Vector3, pad: number, openRing: boolean?): boolean
			for _, s in ipairs(walk) do
				local a, b = s[1], s[2]
				local ab = V3(b.X - a.X, 0, b.Z - a.Z)
				local ap = V3(p.X - a.X, 0, p.Z - a.Z)
				local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
				local q = V3(a.X + ab.X * t, 0, a.Z + ab.Z * t)
				if G.Flat(p, q) < s[3] + pad then
					return true
				end
			end
			for _, d in ipairs(discs) do
				if G.Flat(p, d[1]) < d[2] + pad then
					return true
				end
			end
			local rp = G.Flat(p, PC)
			if openRing then -- only the ring deck itself and the pond + rim
				if rp < PR + 3.5 + pad or math.abs(rp - RING_R) < RING_W / 2 + pad then
					return true
				end
			elseif rp < RING_R + RING_W / 2 + pad then -- the whole pond / graves / ring complex
				return true
			end
			return false
		end

		----------------------------------------------------------------------------------------------- ground + water
		-- the world framework (Ground, Order 10) may already have laid the marsh floor at GroundY with cliff edges + the
		-- bridge from the gate ramping down onto it: then the district builds on that floor instead of duplicating it
		local fwBase = G.DistrictBase(ctx.Root, "MourningMarsh")
		local bridge = G.BridgeDeck(ctx.Root, "MourningMarsh")
		root:SetAttribute("OnFrameworkBase", fwBase ~= nil)
		local W, D = X1 - X0, Z1 - Z0
		if not fwBase then
			K.Part(ground, "MarshMudBed", V3(W, 4, D), at((X0 + X1) / 2, GY - 2, (Z0 + Z1) / 2), MUD, M.Mud, G.Solid())
			-- banks: north + east meet the neighbours' floor (y 0) when nothing else lays it
			K.Wedge(ground, "MarshBank", V3(W, -GY, 6), at((X0 + X1) / 2, GY / 2, Z0 + 3), BANK, M.Mud, G.Solid())
			K.Wedge(ground, "MarshBank", V3(D, -GY, 6), at(X1 - 3, GY / 2, (Z0 + Z1) / 2) * ANG(0, -PI / 2, 0), BANK, M.Mud, G.Solid())
		end
		-- west + south: a shore rising under the boundary cliffs
		K.Wedge(ground, "MarshBank", V3(D, .5 - GY, 8), at(X0 + 4, (GY + .5) / 2, (Z0 + Z1) / 2) * ANG(0, PI / 2, 0), BANK, M.Mud, G.Solid())
		K.Wedge(ground, "MarshBank", V3(W, .5 - GY, 8), at((X0 + X1) / 2, (GY + .5) / 2, Z1 - 4) * ANG(0, PI, 0), BANK, M.Mud, G.Solid())
		-- the black water sheet (walk-through; the mud bed below is the floor)
		K.Part(ground, "BlackWater", V3(W - .4, .2, D - .4), at((X0 + X1) / 2, WY - .1, (Z0 + Z1) / 2), WATER, M.Glass,
			{ Transparency = .18, Reflectance = .22, Shadow = false })
		-- Neon edges where the water meets the banks (wavy dashed lines just above the surface)
		local function edgeLine(a: Vector3, b: Vector3)
			local len = (b - a).Magnitude
			local n = math.max(1, math.floor(len / 14))
			for k = 0, n - 1 do
				local t0, t1 = k / n, (k + rng:NextNumber(.62, .9)) / n
				local off = V3(rng:NextNumber(-.4, .4), 0, rng:NextNumber(-.4, .4))
				K.Bar(ground, "WaterEdge", a:Lerp(b, t0) + off, a:Lerp(b, t1) + off, .22, .06, EDGE, M.Neon, { Transparency = .3 })
			end
		end
		local ey = WY + .04
		local nIn = fwBase and .6 or 2.4 -- north / east waterline: at the bank, or along the framework's cliff edge
		edgeLine(V3(X0 + 6, ey, Z0 + nIn), V3(X1 - 3, ey, Z0 + nIn))
		edgeLine(V3(X1 - nIn, ey, Z0 + 4), V3(X1 - nIn, ey, Z1 - 6))
		edgeLine(V3(X0 + 4.4, ey, Z0 + 4), V3(X0 + 4.4, ey, Z1 - 6))
		edgeLine(V3(X0 + 6, ey, Z1 - 4.4), V3(X1 - 3, ey, Z1 - 4.4))

		-- round mud islet / tussock (stacked discs: they collide as cylinders), Neon edge ring at the waterline
		local function islet(c: Vector3, r: number, top: number, opts)
			opts = opts or {}
			local parent = opts.Parent or ground
			K.CylY(parent, opts.Name or "MudIslet", top - GY + .1, r * 2 + 1.6, at(c.X, (GY + top) / 2 - .35, c.Z), MUD_DARK:Lerp(MUD, .5), M.Mud, G.Solid())
			K.CylY(parent, opts.Name or "MudIslet", .5, r * 2, at(c.X, top - .25, c.Z), opts.Top or C(56, 60, 50), opts.TopMat or M.Ground, G.Solid())
			if opts.Edge ~= false then
				G.Ring(parent, at(c.X, ey, c.Z), r + .85, math.max(6, math.floor(r * 1.25)), .18, .05, EDGE, M.Neon,
					{ Fill = .6, Phase = rng:NextNumber(0, PI), Transparency = .35, Name = "WaterEdge" })
			end
		end

		-------------------------------------------------------------------------------------------------- boardwalks
		local function pile(parent, p: Vector3, top: number, d: number?)
			K.CylY(parent, "BoardwalkPile", top - GY, d or .6, at(p.X, (GY + top) / 2, p.Z) * ANG(rng:NextNumber(-.05, .05), 0, rng:NextNumber(-.05, .05)),
				COL.TimberDark, M.Wood)
		end
		local function rope(parent, a: Vector3, b: Vector3)
			local mid = a:Lerp(b, .5) - V3(0, .45, 0)
			K.Bar(parent, "RopeRail", a, mid, .12, .12, COL.Rope, M.Fabric)
			K.Bar(parent, "RopeRail", mid, b, .12, .12, COL.Rope, M.Fabric)
		end
		-- straight deck from a to b: invisible floor + planks across + stringers + piles (+ a rope rail on one side)
		local function deck(parent, a: Vector3, b: Vector3, width: number, opts)
			opts = opts or {}
			local flat = V3(b.X - a.X, 0, b.Z - a.Z)
			local len = flat.Magnitude
			local cf = K.Look(V3((a.X + b.X) / 2, BY, (a.Z + b.Z) / 2), V3(b.X, BY, b.Z))
			G.Floor(parent, "BoardwalkFloor", V3(width, .8, len + (opts.Overlap or 1)), cf * CF(0, -.4, 0))
			local n = math.max(1, math.floor(len / 2 + .5))
			for k = 0, n - 1 do
				if rng:NextNumber() > .035 then
					local z = -len / 2 + (k + .5) * len / n
					K.Part(parent, "Plank", V3(width + rng:NextNumber(-.4, .3), .35, len / n - .22),
						cf * CF(rng:NextNumber(-.15, .15), -.175 + rng:NextNumber(0, .04), z) * ANG(0, rng:NextNumber(-.035, .035), rng:NextNumber(-.015, .015)),
						plankColor(), M.WoodPlanks)
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				K.Part(parent, "Stringer", V3(.45, .45, len), cf * CF(sx * (width / 2 - .5), -.6, 0), COL.TimberDark, M.Wood)
				local np = math.max(1, math.floor(len / 8))
				for k = 0, np do
					pile(parent, cf * V3(sx * (width / 2 - .5), 0, -len / 2 + k * len / np), BY - .4)
				end
			end
			if opts.Rail then
				local sx = opts.Rail
				local np = math.max(1, math.floor(len / 8))
				local prev
				for k = 0, np do
					if not (opts.SkipEnds and (k == 0 or k == np)) then
						local p = cf * V3(sx * (width / 2 - .3), 0, -len / 2 + k * len / np)
						K.CylY(parent, "RailPost", 2.6, .42, at(p.X, BY + 1.0, p.Z) * ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.06, .06)),
							COL.TimberDark, M.Wood, G.Solid())
						local top = V3(p.X, BY + 2.1, p.Z)
						if prev and rng:NextNumber() > .15 then
							rope(parent, prev, top)
						end
						prev = top
					end
				end
			end
			table.insert(walk, { a, b, width / 2 })
			return cf
		end
		-- ramp from the neighbour floor (y 0) up to the deck
		local function rampUp(parent, p: Vector3, dir: Vector3, width: number)
			local c = p - dir * 1.25
			K.Wedge(parent, "BoardwalkRamp", V3(width, BY, 2.5), K.Look(V3(c.X, BY / 2, c.Z), V3(c.X, BY / 2, c.Z) + dir),
				plankColor(), M.WoodPlanks, G.Solid())
		end

		-- 1. gate path: gate exit -> ChoirPath_7 -> the ring (radial)
		local gate = L.Gates.MourningMarsh
		local u = gate.Facing
		local E0
		local bridgeEnd = nil -- along the spoke from the gate, where the framework bridge lands on the mud
		for _, bp in ipairs(bridge) do
			local cf, sz = bp.CFrame, bp.Size / 2
			for _, cx in ipairs({ -1, 1 }) do
				for _, cz in ipairs({ -1, 1 }) do
					local w = cf * V3(cx * sz.X, sz.Y, cz * sz.Z)
					local t = V3(w.X - gate.Position.X, 0, w.Z - gate.Position.Z):Dot(u)
					bridgeEnd = bridgeEnd and math.max(bridgeEnd, t) or t
				end
			end
		end
		if bridgeEnd then
			-- a gangplank from the bridge's landing on the mud up to the boardwalk
			local foot = gate.Position + u * (bridgeEnd - 1)
			local GL = 7
			E0 = V3(foot.X, BY, foot.Z) + u * GL
			local mid = V3(foot.X, (GY + BY) / 2, foot.Z) + u * (GL / 2)
			K.Wedge(decks, "BoardwalkGangplank", V3(DECK_W, BY - GY, GL), K.Look(mid, mid + u), plankColor(), M.WoodPlanks, G.Solid())
			for k = 1, 4 do
				local c = V3(foot.X, GY + (BY - GY) * (k - .5) / 4.6 + .1, foot.Z) + u * (GL * (k - .5) / 4.6)
				K.Part(decks, "GangplankCleat", V3(DECK_W - .6, .2, .35), K.Look(c, c + u) * ANG(math.atan((BY - GY) / GL), 0, 0), COL.TimberDark, M.Wood)
			end
			table.insert(walk, { V3(foot.X, 0, foot.Z), E0, DECK_W / 2 })
		else
			E0 = gate.Position + u * 9
			E0 = V3(E0.X, BY, E0.Z)
		end
		local E1 = V3(L.ChoirPaths[7].X, BY, L.ChoirPaths[7].Z)
		local radial = V3(E1.X - PC.X, 0, E1.Z - PC.Z).Unit
		local E2 = V3(PC.X, BY, PC.Z) + radial * (RING_R + 1)
		if not bridgeEnd then
			rampUp(decks, E0, V3(E1.X - E0.X, 0, E1.Z - E0.Z).Unit, DECK_W)
		end
		deck(decks, E0, E1, DECK_W, { Rail = 1 })
		deck(decks, E1, E2, DECK_W, { Rail = -1, SkipEnds = true })
		-- landing at the bend
		K.CylY(decks, "BoardwalkLanding", .8, 12, at(E1.X, BY - .4, E1.Z), COL.Ink, M.SmoothPlastic, G.Solid({ Transparency = 1, Shadow = false }))
		do -- parallel planks across the round landing, square to the bisector of the bend
			local d0 = V3(E1.X - E0.X, 0, E1.Z - E0.Z).Unit
			local bis = (d0 + radial).Unit
			local lcf = K.Look(V3(E1.X, BY, E1.Z), V3(E1.X, BY, E1.Z) + bis)
			for k = 0, 5 do
				local z = -5 + k * 2
				local half = math.sqrt(math.max(36 - z * z, 4))
				K.Part(decks, "Plank", V3(half * 2, .35, 1.8), lcf * CF(rng:NextNumber(-.2, .2), -.17 + rng:NextNumber(0, .03), z) * ANG(0, rng:NextNumber(-.03, .03), 0),
					plankColor(), M.WoodPlanks)
			end
		end
		table.insert(discs, { E1, 6.5 })
		-- crooked lantern arch over the start of the path (rope with three little glass lanterns, no lights)
		do
			local side = V3(-gate.Facing.Z, 0, gate.Facing.X)
			local base = E0 + gate.Facing * (bridgeEnd and .5 or 3)
			local tops = {}
			for _, s in ipairs({ -1, 1 }) do
				local p = base + side * s * (DECK_W / 2 + .2)
				local top = p + V3(rng:NextNumber(-.4, .4), 7.5 + s * .6, 0)
				K.Rod(props, "ArchPost", V3(p.X, GY, p.Z), top, .6, COL.TimberDark, M.Wood, G.Solid())
				K.Ball(props, "ArchPostKnob", .8, CF(top), COL.Timber, M.Wood)
				table.insert(tops, top)
			end
			local mid = tops[1]:Lerp(tops[2], .5) - V3(0, 1.4, 0)
			K.Bar(props, "ArchRope", tops[1], mid, .16, .16, COL.Rope, M.Fabric)
			K.Bar(props, "ArchRope", mid, tops[2], .16, .16, COL.Rope, M.Fabric)
			for k = 1, 3 do
				local t = k / 4
				local p = (t < .5 and tops[1]:Lerp(mid, t * 2) or mid:Lerp(tops[2], t * 2 - 1)) - V3(0, .9, 0)
				K.Part(props, "ArchLanternGlass", V3(.5, .7, .5), at(p.X, p.Y, p.Z), BLOOM[k], M.Neon, { Attrs = { HwLantern = "Purple" } })
				K.Part(props, "ArchLanternCap", V3(.7, .15, .7), at(p.X, p.Y + .43, p.Z), COL.Iron, M.CorrodedMetal)
			end
			local crow = K.Part(props, "ArchPerch", V3(.2, .2, .2), CF(tops[2] + V3(0, .5, 0)), COL.Iron, nil, { Transparency = 1 })
			K.Attach(crow, "CrowPerch")
		end

		-- 2. the ring around the pond: radial planks over 32 floor segments, stringers, piles, outer rope rail
		local NSEG = 32
		for i = 1, NSEG do
			local a0 = (i - 1) / NSEG * PI * 2
			local am = a0 + PI / NSEG
			local chord = 2 * (RING_R + RING_W / 2) * math.tan(PI / NSEG) + .4
			local c = polar(am, RING_R, BY - .4)
			G.Floor(decks, "BoardwalkFloor", V3(RING_W, .8, chord), CF(c) * ANG(0, PI / 2 - am, 0))
		end
		local nPlanks = math.floor(2 * PI * RING_R / 2)
		for k = 0, nPlanks - 1 do
			if rng:NextNumber() > .035 then
				local a = k / nPlanks * PI * 2
				local c = polar(a, RING_R + rng:NextNumber(-.15, .15), BY - .175 + rng:NextNumber(0, .04))
				K.Part(decks, "Plank", V3(RING_W + rng:NextNumber(-.4, .3), .35, 1.75), CF(c) * ANG(0, -a + PI / 2, 0) * ANG(0, rng:NextNumber(-.03, .03), 0),
					plankColor(), M.WoodPlanks)
			end
		end
		for _, rr in ipairs({ RING_R - RING_W / 2 + .5, RING_R + RING_W / 2 - .5 }) do
			G.Ring(decks, at(PC.X, BY - .82, PC.Z), rr, 24, .45, .45, COL.TimberDark, M.Wood, { Name = "Stringer" })
			for k = 0, 15 do
				pile(decks, polar((k + .5) / 16 * PI * 2, rr, 0), BY - .4)
			end
		end
		-- junction angles (gate path, south + west branches) keep the outer rail open
		local aEntry = math.atan2(radial.X, -radial.Z)
		local junctions = { aEntry, PI, PI * 1.5 }
		local function nearJunction(a: number, tol: number): boolean
			for _, j in ipairs(junctions) do
				local d = math.abs((a - j + PI) % (2 * PI) - PI)
				if d < tol then
					return true
				end
			end
			return false
		end
		do
			local prev
			local NR = 28
			for k = 0, NR do
				local a = k / NR * PI * 2
				if nearJunction(a, .17) then
					prev = nil
				elseif k < NR then
					local p = polar(a, RING_R + RING_W / 2 - .3, BY + 1.0)
					K.CylY(decks, "RailPost", 2.6, .42, CF(p) * ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.06, .06)), COL.TimberDark, M.Wood, G.Solid())
					local top = p + V3(0, 1.1, 0)
					if prev and rng:NextNumber() > .12 then
						rope(decks, prev, top)
					end
					prev = top
				end
			end
		end

		-- 3. south branch to the Black Mere + the Funeral Landing jetty; 4. west branch to the Weeping Dog shrine
		local MERE = { C = V3(-165, GY, 2655), RX = 34, RZ = 30 }
		local S0 = polar(PI, RING_R + RING_W / 2 - 1, BY)
		local S1 = V3(PC.X, BY, 2630)
		deck(decks, S0, S1, DECK_W, { Rail = 1, SkipEnds = true })
		local J1 = V3(-153, BY, 2652)
		local jdir = V3(J1.X - S1.X, 0, J1.Z - S1.Z).Unit
		local JW = 7
		deck(decks, S1 - jdir * 2, J1, JW, {})
		local J2 = J1 + jdir * 5.5
		local jcf = K.Look(J2, J2 + jdir)
		G.Floor(decks, "BoardwalkFloor", V3(11, .8, 11), jcf * CF(0, -.4, 0))
		for k = 0, 5 do
			K.Part(decks, "Plank", V3(11 + rng:NextNumber(-.3, .2), .35, 1.62), jcf * CF(0, -.175 + rng:NextNumber(0, .04), -5.5 + (k + .5) * 11 / 6),
				plankColor(), M.WoodPlanks)
		end
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local p = jcf * V3(sx * 5.1, 0, sz * 5.1)
				K.CylY(decks, "MooringPost", 3.8 - GY, .7, at(p.X, (GY + BY + 3.3) / 2, p.Z), COL.TimberDark, M.Wood, G.Solid())
				K.CylY(decks, "MooringRope", .5, .9, at(p.X, BY + 2.2, p.Z), COL.Rope, M.Fabric)
			end
		end
		table.insert(discs, { J2, 7.8 })
		local W0 = polar(PI * 1.5, RING_R + RING_W / 2 - 1, BY)
		local W1 = V3(-201, BY, PC.Z)
		deck(decks, W0, W1, DECK_W, { Rail = -1, SkipEnds = true })
		local SH = V3(-208, BY, PC.Z)
		K.CylY(decks, "ShrinePlatform", BY - GY + .4, 13, at(SH.X, (GY + BY) / 2 - .2, SH.Z), COL.Slate, M.Cobblestone, G.Solid())
		K.CylY(decks, "ShrinePlatformRim", .3, 13.6, at(SH.X, BY - .35, SH.Z), COL.StoneDark, M.Slate)
		table.insert(discs, { SH, 7 })

		------------------------------------------------------------------------------------------------ the mirror pond
		local RIM_IN, RIM_OUT, RIM_TOP = PR, PR + 2.6, .8
		G.Ring(pond, at(PC.X, GY, PC.Z), (RIM_IN + RIM_OUT) / 2, 30, RIM_OUT - RIM_IN, RIM_TOP - GY, COL.Stone, M.Cobblestone,
			{ Solid = true, Rng = rng, HJitter = .22, Name = "PondRim" })
		G.Ring(pond, at(PC.X, RIM_TOP - .05, PC.Z), (RIM_IN + RIM_OUT) / 2 + .1, 30, RIM_OUT - RIM_IN + .5, .26, COL.StoneLight, M.Slate,
			{ Rng = rng, Jitter = .15, Phase = .05, Name = "PondCoping", Solid = true })
		K.CylY(pond, "PondBed", .4, PR * 2 + .5, at(PC.X, GY + .2, PC.Z), C(6, 6, 12), M.SmoothPlastic)
		K.CylY(pond, "MirrorPond", .3, PR * 2 + .6, at(PC.X, -.35, PC.Z), C(10, 12, 26), M.Glass, { Transparency = .06, Reflectance = .62, Shadow = false })
		G.Ring(pond, at(PC.X, -.19, PC.Z), PR - .35, 30, .3, .05, EDGE, M.Neon, { Fill = .82, Transparency = .25, Name = "MirrorEdge" })
		G.Ring(pond, at(PC.X, -.19, PC.Z), PR * .55, 16, .14, .04, C(120, 150, 230), M.Neon, { Fill = .45, Phase = .3, Transparency = .55, Name = "MirrorRipple" })
		local glow = K.Part(pond, "PondGlow", V3(.4, .4, .4), at(PC.X, .9, PC.Z), COL.Moon, M.Neon, { Transparency = 1 })
		K.Light(glow, COL.Moon, 30, .7):SetAttribute("HwBaseBrightness", .7)
		-- invisible collider ring on the rim's inner edge: nobody walks on the mirror
		for k = 0, 19 do
			local a = (k + .5) / 20 * PI * 2
			local c = polar(a, RIM_IN - .2, RIM_TOP + 5)
			G.Collider(colliders, "PondCollider", V3(.8, 10, 2 * RIM_IN * math.tan(PI / 20) + .8), CF(c) * ANG(0, PI / 2 - a, 0))
		end
		-- rim inlays: each grave's glyph faces its grave (dim violet, flush on the coping)
		local GLYPH = { "Arrow", "Fork", "Eye", "Moon", "Bone", "Paw" }
		for i = 1, 6 do
			local a = (i - 1) / 6 * PI * 2
			local p = polar(a, (RIM_IN + RIM_OUT) / 2, RIM_TOP + .21)
			G.Rune(pond, CF(p) * ANG(0, PI - a, 0) * ANG(PI / 2, 0, 0), GLYPH[i], 1.3, COL.VioletDim, { Depth = .06, Transparency = .1, Name = "RimGlyph" })
		end
		-- moon lilies on the rim bloom once Seal III is cleared
		do
			local lilies = K.Model(pond, "MoonLilies")
			lilies:SetAttribute("UyShowAtSeal", SEAL)
			for k = 0, 5 do
				local a = (k + .5) / 6 * PI * 2
				G.Flower(lilies, CF(polar(a, RIM_OUT - .6, RIM_TOP + .21)), .9, BLOOM[k % 2 + 1], rng, 5)
			end
			for _, p in ipairs(lilies:GetDescendants()) do
				if p:IsA("BasePart") then
					p:SetAttribute("UyShowAtSeal", SEAL)
				end
			end
		end

		---------------------------------------------------------------------------------------------- the mirror graves
		local TOPI = .4
		for i, gp in ipairs(L.MirrorGraves) do
			local a = (i - 1) / 6 * PI * 2
			local isle = K.Model(graves, "GraveIsland_" .. i)
			islet(gp, ISLAND_R, TOPI, { Parent = isle, Name = "GraveIsland", Top = C(52, 58, 48) })
			table.insert(discs, { gp, ISLAND_R + .5 })
			-- spur from the ring
			local sp0 = polar(a, RING_R - RING_W / 2 + .6, BY)
			local sp1 = polar(a, 24 + ISLAND_R - 1.2, BY)
			deck(isle, sp0, sp1, 6, { Overlap = .6 })
			-- paving, plinth (static)
			K.Part(isle, "GravePaving", V3(4.8, .3, 4.8), at(gp.X, TOPI + .05, gp.Z) * ANG(0, rng:NextNumber(-.03, .03), 0), COL.Slate, M.Slate, G.Solid())
			local plinthTop = TOPI + .2 + .7
			K.Part(isle, "GravePlinth", V3(3.0, .7, 3.0), at(gp.X, TOPI + .2 + .35, gp.Z), COL.StoneDark, M.Slate, G.Solid())
			K.Part(isle, "GravePlinthLip", V3(3.3, .18, 3.3), at(gp.X, plinthTop - .05, gp.Z), COL.Stone, M.Slate)
			-- the turning headstone
			local stone = K.Model(graves, "MirrorGrave_" .. i .. "_Stone")
			stone.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			stone:SetAttribute("MirrorGrave", i)
			stone:SetAttribute("Rune", GLYPH[i])
			local hcf = at(gp.X, plinthTop, gp.Z)
			local hinge = K.Part(stone, "StoneHinge", V3(1, .2, 1), hcf, COL.Ink, nil, { Transparency = 1 })
			stone.PrimaryPart = hinge
			local body = hcf * CF(0, 2.1, 0) * ANG(rng:NextNumber(-.05, .05), 0, (i % 2 == 0 and 1 or -1) * rng:NextNumber(.03, .06))
			local shade = COL.Stone:Lerp(COL.StoneDark, rng:NextNumber(.1, .5))
			K.Part(stone, "Headstone", V3(2.2, 4.2, 2.2), body, shade, M.Slate, G.Solid())
			Y.GableTri(stone, "HeadstoneGable", body * CF(0, 2.1, 0) * ANG(0, PI / 2, 0), 2.2, 1.3, 2.2, shade:Lerp(COL.StoneLight, .15), M.Slate)
			K.Part(stone, "HeadstoneCollar", V3(2.35, .28, 2.35), body * CF(0, 1.35, 0), COL.StoneLight:Lerp(shade, .4), M.Slate)
			K.Part(stone, "HeadstoneFoot", V3(2.4, .35, 2.4), body * CF(0, -1.92, 0), COL.StoneDark, M.Slate)
			K.Part(stone, "RunePanel", V3(1.8, 2.2, .06), body * CF(0, -.1, 1.13), COL.Ink, M.SmoothPlastic)
			G.Rune(stone, body * CF(0, -.1, 1.16) * ANG(0, PI, 0), GLYPH[i], 1.6, COL.Violet, { Depth = .1, Name = "RuneGlyph" })
			G.Skull(stone, body * CF(0, 3.72, .05) * ANG(0, PI, 0) * ANG(-.12, 0, 0), .95, nil, COL.Bone)
			K.Part(stone, "HeadstoneMoss", V3(1.4, .12, .5), body * CF(rng:NextNumber(-.3, .3), 1.55, -.9), COL.Moss, M.Grass)
			K.Part(stone, "HeadstoneCrack", V3(.08, 1.6, .06), body * CF(-.7, .5, -1.12) * ANG(0, 0, .3), COL.Ink, M.SmoothPlastic)
			-- dressing on the island: candles, a short bowed fence behind, glowing flowers
			local out = V3(math.sin(a), 0, -math.cos(a))
			local tan = V3(math.cos(a), 0, math.sin(a))
			K.Candles(isle, CF(gp + tan * 2.6 - out * .4 + V3(0, TOPI, 0)), 3, rng, { Light = false, Spread = .5 })
			local f0 = gp - tan * 3.9 + out * 1.6 + V3(0, TOPI, 0)
			local f1 = gp - tan * 3.5 - out * 2.2 + V3(0, TOPI, 0)
			Y.IronFence(isle, f0, f1, { Height = 2.1, Spacing = 1.2, Broken = .15, Color = COL.Iron }, rng)
			for _, s in ipairs({ -1, 1 }) do
				local fp = gp - tan * s * 3.4 + out * 1.6 + V3(0, TOPI, 0)
				G.Flower(isle, CF(fp), rng:NextNumber(.9, 1.4), BLOOM[(i + s) % 3 + 1], rng)
			end
		end

		-- grave 1 island: the north terrace down to the pond rim + THE CONSULT STONE (faces the pond)
		do
			local g1 = L.MirrorGraves[1]
			local CS = MK.Consult
			local tz0, tz1 = g1.Z + 2, PC.Z - RIM_OUT + 1.2
			K.Part(graves, "ConsultTerrace", V3(8.5, TOPI - GY, tz1 - tz0), at(g1.X, (GY + TOPI) / 2, (tz0 + tz1) / 2), C(52, 58, 48), M.Ground, G.Solid())
			K.Part(graves, "ConsultPaving", V3(7.6, .3, tz1 - tz0 - .6), at(g1.X, TOPI + .05, (tz0 + tz1) / 2 + .2), COL.Slate, M.Slate, G.Solid())
			for _, sx in ipairs({ -1, 1 }) do
				K.Part(graves, "ConsultKerb", V3(.6, .7, tz1 - tz0), at(g1.X + sx * 4.1, TOPI + .1, (tz0 + tz1) / 2), COL.StoneDark, M.Slate, G.Solid())
			end
			local cm = K.Model(graves, "ConsultStone")
			cm:SetAttribute("ConsultStone", true)
			local cz = CS.Z + 1.5 -- the basin stands just south of the anchor point, clear of grave 1's turning headstone
			local base = at(CS.X, TOPI + .2, cz) -- faces +Z (the pond): engravings on the +Z side
			K.Part(cm, "ConsultBase", V3(3.4, .5, 2.4), base * CF(0, .25, 0), COL.StoneDark, M.Slate, G.Solid())
			K.Part(cm, "ConsultPedestal", V3(1.7, 1.5, 1.5), base * CF(0, 1.25, 0) * ANG(0, .04, 0), COL.Stone, M.Slate, G.Solid())
			K.Part(cm, "ConsultPedestalBand", V3(1.9, .22, 1.7), base * CF(0, 1.65, 0), COL.StoneLight, M.Slate)
			K.CylY(cm, "ConsultBasin", .8, 3.1, base * CF(0, 2.4, 0), COL.Stone:Lerp(COL.StoneLight, .3), M.Slate, G.Solid())
			K.CylY(cm, "ConsultBasinLip", .2, 3.3, base * CF(0, 2.86, 0), COL.StoneLight, M.Slate)
			K.CylY(cm, "ConsultWater", .1, 2.5, base * CF(0, 2.93, 0), C(8, 10, 22), M.Glass, { Reflectance = .6, Transparency = .05 })
			G.Rune(cm, base * CF(0, 3.0, 0) * ANG(PI / 2, 0, 0), "Eye", 1.5, COL.Moon, { Depth = .05, Name = "ConsultEye" })
			G.Skull(cm, base * CF(0, 1.3, .95) * ANG(0, PI, 0), .9, COL.Moon:Lerp(COL.Ink, .3), COL.Bone)
			for _, sx in ipairs({ -1, 1 }) do
				K.Wedge(cm, "ConsultEar", V3(.35, .9, .7), base * CF(sx * 1.25, 3.2, -.3) * ANG(0, 0, sx * .25), COL.StoneLight, M.Slate)
			end
			local candles = K.Candles(cm, base * CF(1.9, .5, .7), 3, rng, { Light = true, Range = 12, Spread = .45 })
			local _ = candles
		end

		------------------------------------------------------------------------------------------------- the black mere
		do
			local mc = MERE.C
			K.Ellipsoid(ground, "BlackMereBed", V3(MERE.RX * 2, .3, MERE.RZ * 2), at(mc.X, GY + .08, mc.Z), C(5, 5, 10), M.SmoothPlastic)
			local N = 28
			local pts = {}
			for k = 0, N - 1 do
				local a = k / N * PI * 2
				table.insert(pts, V3(mc.X + math.cos(a) * MERE.RX, ey, mc.Z + math.sin(a) * MERE.RZ))
			end
			-- collider ring, clipped exactly to the jetty corridor (|lateral| < JW / 2 + .3 between S1 and the platform):
			-- the clipped ends meet the jetty side walls below, so the mere is sealed except over the jetty itself
			local side0 = V3(-jdir.Z, 0, jdir.X)
			local half = JW / 2 + .3
			local corrLen = ((J2 - jdir * 5.5) - S1).Magnitude
			local function lat(p: Vector3): number
				return V3(p.X - S1.X, 0, p.Z - S1.Z):Dot(side0)
			end
			local function lon(p: Vector3): number
				return V3(p.X - S1.X, 0, p.Z - S1.Z):Dot(jdir)
			end
			local function wall(a: Vector3, b: Vector3)
				if (b - a).Magnitude > .3 then
					G.Fence(colliders, V3(a.X, GY, a.Z), V3(b.X, GY, b.Z), 12)
				end
			end
			for k = 1, N do
				local p, q = pts[k], pts[k % N + 1]
				K.Bar(ground, "WaterEdge", p, q, .26, .06, EDGE, M.Neon, { Transparency = .2 })
				local lp, lq = lat(p), lat(q)
				local ta, tb = 1, 0 -- t-interval of the segment inside the corridor strip
				if math.abs(lq - lp) > 1e-6 then
					local t1, t2 = (-half - lp) / (lq - lp), (half - lp) / (lq - lp)
					ta, tb = math.max(0, math.min(t1, t2)), math.min(1, math.max(t1, t2))
				elseif math.abs(lp) < half then
					ta, tb = 0, 1
				end
				local inside = ta < tb and (function()
					local l = lon(p:Lerp(q, (ta + tb) / 2))
					return l > -1 and l < corrLen + 1
				end)()
				if inside then
					wall(p, p:Lerp(q, ta))
					wall(p:Lerp(q, tb), q)
				else
					wall(p, q)
				end
			end
			-- jetty side walls + the platform's three open sides
			local side = V3(-jdir.Z, 0, jdir.X)
			for _, s in ipairs({ -1, 1 }) do
				local a = S1 + side * s * (JW / 2 + .3) + jdir * 0
				local b = J2 - jdir * 5.5 + side * s * (JW / 2 + .3)
				G.Fence(colliders, V3(a.X, BY, a.Z), V3(b.X, BY, b.Z), 10, .6)
				local c0 = J2 - jdir * 5.5 + side * s * 5.8
				local c1 = J2 + jdir * 5.8 + side * s * 5.8
				G.Fence(colliders, V3(c0.X, BY, c0.Z), V3(c1.X, BY, c1.Z), 10, .6)
				G.Fence(colliders, V3(c0.X, BY, c0.Z), V3((J2 - jdir * 5.5 + side * s * (JW / 2 + .3)).X, BY, (J2 - jdir * 5.5 + side * s * (JW / 2 + .3)).Z), 10, .6)
			end
			local e0, e1 = J2 + jdir * 5.8 + side * 5.8, J2 + jdir * 5.8 - side * 5.8
			G.Fence(colliders, V3(e0.X, BY, e0.Z), V3(e1.X, BY, e1.Z), 10, .6)
			table.insert(discs, { mc, math.max(MERE.RX, MERE.RZ) - 2 })
		end

		------------------------------------------------------------------------------------------------------- lamps
		local lights = 0
		local function lamp(p: Vector3, face: Vector3, color: Color3, kind: string, h: number, attrs)
			local base = K.Look(p, p + face)
			G.LampPost(lamps, base, h, color, kind, rng, { Light = 18, Brightness = 1, Attrs = attrs })
			lights += 1
		end
		-- gate path
		do
			local d = V3(E1.X - E0.X, 0, E1.Z - E0.Z).Unit
			local side = V3(-d.Z, 0, d.X)
			lamp(E0:Lerp(E1, .3) - side * (DECK_W / 2 - .6), side, COL.Moon, "Purple", 8)
			lamp(E1 + side * 4.6 - d * 2.6, -side, COL.Green, "Green", 8.5)
			lamp(E1:Lerp(E2, .75) - side * 0 + V3(-radial.Z, 0, radial.X) * (DECK_W / 2 - .6), V3(radial.Z, 0, -radial.X), COL.Moon, "Purple", 8)
		end
		-- ring: one lamp by each grave spur (inner edge, beside the spur)
		for i = 1, 6 do
			local a = (i - 1) / 6 * PI * 2 + .16
			local p = polar(a, RING_R - RING_W / 2 + .9, BY)
			lamp(p, V3(p.X - PC.X, 0, p.Z - PC.Z).Unit, i % 2 == 0 and COL.Moon or C(170, 120, 255), "Purple", 7.5)
		end
		-- jetty (lit when Seal III is cleared)
		lamp(S1 + V3(-(DECK_W / 2 - .6), 0, -3), V3(1, 0, 0), COL.Candle, "Orange", 8, { UyLightAtSeal = SEAL })
		do
			local side = V3(-jdir.Z, 0, jdir.X)
			lamp(J2 + jdir * 4.2 + side * 4.2, -side, COL.Candle, "Orange", 9, { UyLightAtSeal = SEAL })
		end

		------------------------------------------------------------------------------------------------ funeral boats
		local function boat(cf: CFrame, len: number, opts)
			opts = opts or {}
			local m = K.Model(props, "FuneralBoat")
			local wood, dark = C(58, 44, 40), C(36, 28, 30)
			local w = len * .24
			-- hull: keel bottom, flared sides, raised curling prow + stern
			K.Part(m, "BoatBottom", V3(w * .7, .3, len * .78), cf * CF(0, -.35, 0), dark, M.WoodPlanks)
			for _, s in ipairs({ -1, 1 }) do
				K.Part(m, "BoatSide", V3(.25, 1.1, len * .8), cf * CF(s * w * .42, .1, 0) * ANG(0, 0, s * .32), wood, M.WoodPlanks)
				K.Part(m, "BoatGunwale", V3(.32, .2, len * .82), cf * CF(s * w * .56, .62, 0), C(90, 70, 52), M.Wood)
			end
			for _, e in ipairs({ -1, 1 }) do
				local tip = cf * CF(0, 0, e * len * .44)
				K.Wedge(m, "BoatEnd", V3(w * .7, 1.2, len * .14), tip * CF(0, .1, e * len * .02) * ANG(0, e > 0 and PI or 0, 0), wood, M.WoodPlanks)
				local p0 = (tip * CF(0, .5, e * len * .07)).Position
				local p1 = (tip * CF(0, 2.3, e * len * .13)).Position
				local p2 = (tip * CF(0, 3.3, e * len * .07)).Position
				K.Rod(m, "BoatCurl", p0, p1, .4, dark, M.Wood)
				K.Rod(m, "BoatCurl", p1, p2, .32, dark, M.Wood)
				K.Ball(m, "BoatCurlKnob", .5, CF(p2), C(90, 70, 52), M.Wood)
			end
			for k = -1, 1 do
				K.Part(m, "BoatRib", V3(w * .95, .18, .25), cf * CF(0, .45, k * len * .22), dark, M.Wood)
			end
			-- shrouded coffin, wreath, candles
			local coffin = cf * CF(0, .55, -len * .04)
			K.Part(m, "BoatCoffin", V3(w * .52, .7, len * .42), coffin, C(30, 22, 30), M.Wood)
			K.Part(m, "BoatShroud", V3(w * .58, .18, len * .38), coffin * CF(0, .42, 0) * ANG(0, 0, .03), C(150, 156, 176), M.Fabric, { Transparency = .1 })
			K.CylX(m, "BoatWreath", .25, w * .5, coffin * CF(0, .6, -len * .12) * ANG(0, 0, PI / 2), C(40, 70, 46), M.Grass)
			for k = 1, 3 do
				local fl = coffin * CF((k - 2) * .35, .7, -len * .12)
				K.Ball(m, "BoatFlower", .3, fl, BLOOM[k], M.Neon)
			end
			K.Candles(m, cf * CF(0, .3, len * .3), 2, rng, { Light = false, Spread = .3 })
			if opts.Lantern then
				local tip = (cf * CF(0, 3.6, -len * .44 - len * .07)).Position
				G.CageLantern(m, CF(tip - V3(0, .2, 0)), COL.Candle, "Orange", { Light = 14, Brightness = .9, Attrs = { UyLightAtSeal = SEAL }, Scale = .8 })
				lights += 1
			end
			return m
		end
		do
			local side = V3(-jdir.Z, 0, jdir.X)
			local yaw = math.atan2(-jdir.X, -jdir.Z)
			for _, s in ipairs({ -1, 1 }) do
				local p = J2 + side * s * 9 + jdir * (s * 1.5)
				boat(at(p.X, WY + .15, p.Z) * ANG(0, yaw + s * .12, 0) * ANG(0, 0, s * .03), 13, { Lantern = true })
			end
			-- adrift on the mere, and beached on the east shore
			boat(at(-182, WY + .15, 2664) * ANG(0, 1.1, .04), 12, { Lantern = true })
			boat(at(-84, GY + .9, 2655) * ANG(.12, -.3, .1), 11, {})
		end

		------------------------------------------------------------------------------------------------------ willows
		local function willow(base: Vector3, height: number, opts)
			opts = opts or {}
			local m = K.Model(flora, "DeadWillow")
			local bark = C(54, 46, 48)
			local dark = bark:Lerp(COL.Ink, .35)
			local moss = { C(92, 108, 88), C(74, 92, 76), C(108, 118, 96) }
			for k = 1, 4 do
				local ra = k / 4 * PI * 2 + rng:NextNumber(-.4, .4)
				K.Rod(m, "WillowRoot", base + V3(0, height * .07, 0), base + V3(math.cos(ra) * height * .17, GY - base.Y - .2, math.sin(ra) * height * .17),
					height * .05, dark, M.Wood)
			end
			local p = base
			local dir = (V3(rng:NextNumber(-.25, .25), 1, rng:NextNumber(-.25, .25))).Unit
			local thick = height * .085
			local joints = {}
			for k = 1, 3 do
				local q = p + dir * height * ({ .3, .22, .14 })[k]
				K.Rod(m, "WillowStem", p, q, thick, bark:Lerp(dark, k * .12), M.Wood, k == 1 and G.Solid() or nil)
				if k < 3 then
					K.Ball(m, "WillowKnot", thick * 1.1, CF(q), bark, M.Wood)
				end
				joints[k] = q
				dir = (dir + V3(rng:NextNumber(-.45, .45), .1, rng:NextNumber(-.45, .45))).Unit
				thick *= .74
				p = q
			end
			local nb = opts.Branches or 5
			local wispAt
			for b = 1, nb do
				local ab = b / nb * PI * 2 + rng:NextNumber(-.4, .4)
				local hd = V3(math.cos(ab), 0, math.sin(ab))
				local s0 = b <= 2 and joints[2] or joints[3]
				local q1 = s0 + hd * height * .12 + V3(0, height * .13, 0)
				local q2 = q1 + hd * height * .13 + V3(0, height * .015, 0)
				local q3 = q2 + hd * height * .07 - V3(0, height * .11, 0)
				K.Rod(m, "WillowBranch", s0, q1, height * .032, bark, M.Wood)
				K.Rod(m, "WillowBranch", q1, q2, height * .022, dark, M.Wood)
				K.Rod(m, "WillowTwig", q2, q3, height * .014, dark, M.Wood)
				for j, hp in ipairs({ q1:Lerp(q2, .6), q3 }) do
					local len = math.min(rng:NextNumber(height * .26, height * .46), hp.Y - (WY + 1.2))
					if len > 1 then
						K.Part(m, "HangingMoss", V3(.14, len, rng:NextNumber(.5, .9)),
							CF(hp - V3(0, len / 2, 0)) * ANG(0, rng:NextNumber(0, PI), rng:NextNumber(-.05, .05)), moss[(b + j) % 3 + 1], M.Grass,
							{ Transparency = .12 })
					end
				end
				if b == 1 then
					wispAt = q2
				end
			end
			if opts.Wisp and wispAt then
				G.CageLantern(m, CF(wispAt), COL.Green, "Green", { Light = 14, Brightness = .8, Attrs = { UyLightAtSeal = SEAL }, Scale = .7 })
				lights += 1
			end
			local perch = K.Part(m, "WillowPerch", V3(.2, .2, .2), CF(joints[3] + V3(0, .4, 0)), bark, nil, { Transparency = 1 })
			K.Attach(perch, "CrowPerch")
			return m
		end
		-- mud flats break the black water up into banks; most carry a willow, all get a reed bed at their rim
		local FLATS = { -- {x, z, radius, willow height (0 = none), wisp lantern}
			{ -196, 2494, 11, 24, true }, { -160, 2482, 8, 19 }, { -92, 2532, 8, 21 }, { -90, 2600, 10, 23, true },
			{ -206, 2606, 9, 20 }, { -112, 2650, 10, 22 }, { -98, 2692, 11, 19 }, { -204, 2696, 10, 21, true },
			{ -130, 2697, 8, 17 }, { -190, 2516, 6, 16 }, { -212, 2652, 6, 0 }, { -96, 2566, 6, 0 }, { -122, 2620, 6, 0 },
			{ -172, 2611, 7, 0 }, { -124, 2484, 5, 0 },
		}
		for i, f in ipairs(FLATS) do
			local c = V3(f[1], 0, f[2])
			local top = -.15 + (i % 3) * .1
			islet(c, f[3], top, { Name = "MudFlat", Top = C(50, 54, 46):Lerp(C(62, 58, 50), (i % 4) / 4), TopMat = i % 2 == 0 and M.Ground or M.Mud })
			-- a second lobe so no flat reads as a perfect disc
			local la = rng:NextNumber(0, PI * 2)
			local lr = f[3] * rng:NextNumber(.5, .7)
			local lc = c + V3(math.cos(la), 0, math.sin(la)) * f[3] * .75
			K.CylY(ground, "MudFlatLobe", top - GY + .05, lr * 2, at(lc.X, (GY + top) / 2 - .05, lc.Z), C(54, 52, 46), M.Mud, G.Solid())
			table.insert(discs, { c, f[3] + .5 })
			if f[4] > 0 then
				local wb = c + V3(rng:NextNumber(-1.5, 1.5), top, rng:NextNumber(-1.5, 1.5))
				willow(wb, f[4], { Wisp = f[5] })
			end
		end

		------------------------------------------------- tussocks with glowing flowers, lily pads, reeds, sunken graves
		local function free(p: Vector3, r: number): boolean
			if p.X < X0 + 9 or p.X > X1 - 7 or p.Z < Z0 + 7 or p.Z > Z1 - 9 then
				return false
			end
			return not onWalk(p, r)
		end
		-- reed beds at the rims of the flats + glowing flowers on the flats
		for i, f in ipairs(FLATS) do
			local c = V3(f[1], 0, f[2])
			for k = 1, (f[3] >= 9 and 2 or 1) do
				local ra = rng:NextNumber(0, PI * 2)
				local rp = c + V3(math.cos(ra), 0, math.sin(ra)) * (f[3] + .6)
				for _ = 1, 4 do
					local bp = rp + V3(rng:NextNumber(-1.2, 1.2), GY, rng:NextNumber(-1.2, 1.2))
					local h = rng:NextNumber(3, 5.4)
					local tip = bp + V3(rng:NextNumber(-.5, .5), h, rng:NextNumber(-.5, .5))
					K.Bar(flora, "Reed", bp, tip, .12, .12, C(70, 84, 58):Lerp(C(96, 92, 64), rng:NextNumber(0, 1)), M.Grass)
					if rng:NextNumber() < .5 then
						K.Ellipsoid(flora, "ReedHead", V3(.28, .9, .28), CF(tip - (tip - bp).Unit * .6), C(74, 52, 40), M.Fabric)
					end
				end
				local _ = k
			end
			local col = BLOOM[i % #BLOOM + 1]
			for _ = 1, (f[4] > 0 and 2 or 4) do
				local fa = rng:NextNumber(0, PI * 2)
				local fr = rng:NextNumber(f[3] * .35, f[3] * .8)
				G.Flower(flora, CF(c + V3(math.cos(fa) * fr, -.15 + (i % 3) * .1, math.sin(fa) * fr)), rng:NextNumber(.9, 1.7), col, rng, 3)
			end
		end
		local placed = 0
		local tries = 0
		while placed < 12 and tries < 400 do
			tries += 1
			local p = V3(rng:NextNumber(X0, X1), 0, rng:NextNumber(Z0, Z1))
			if free(p, 3) then
				placed += 1
				local r = rng:NextNumber(1.4, 2.2)
				islet(p, r, rng:NextNumber(-.35, -.05), { Name = "Tussock", Top = C(46, 62, 50), TopMat = M.Grass, Edge = placed % 3 == 0 })
				local col = BLOOM[rng:NextInteger(1, #BLOOM)]
				for _ = 1, 2 do
					local fa = rng:NextNumber(0, PI * 2)
					local fp = p + V3(math.cos(fa) * r * .5, -.2, math.sin(fa) * r * .5)
					G.Flower(flora, CF(fp), rng:NextNumber(.8, 1.6), col, rng, rng:NextInteger(3, 4))
				end
				table.insert(discs, { p, r + 1 })
			end
		end
		-- dead stumps poking out of the water
		for _ = 1, 12 do
			local p = V3(rng:NextNumber(X0, X1), 0, rng:NextNumber(Z0, Z1))
			if free(p, 1.5) then
				local h = rng:NextNumber(1.2, 3.2)
				local d = rng:NextNumber(.9, 1.6)
				local cf = at(p.X, GY + h / 2, p.Z) * ANG(rng:NextNumber(-.2, .2), 0, rng:NextNumber(-.2, .2))
				K.CylY(props, "DeadStump", h, d, cf, C(48, 40, 42), M.Wood)
				K.Wedge(props, "StumpSplinter", V3(d * .5, .8, d * .4), cf * CF(d * .15, h / 2 + .4, 0), C(70, 58, 52), M.Wood)
				table.insert(discs, { p, d })
			end
		end
		-- lily pads on open water (a third carry a flower)
		local pads, ptries = 0, 0
		while pads < 34 and ptries < 500 do
			ptries += 1
			local p = V3(rng:NextNumber(X0, X1), 0, rng:NextNumber(Z0, Z1))
			local rp = G.Flat(p, PC)
			local inRingWater = rp > PR + 4 and rp < RING_R - RING_W / 2 - 1 and not onWalk(p, .6, true)
			if inRingWater or free(p, 1.5) then
				pads += 1
				local d = rng:NextNumber(1.6, 2.6)
				K.CylY(flora, "LilyPad", .06, d, at(p.X, WY + .05, p.Z), C(38, 66, 50):Lerp(C(60, 90, 62), rng:NextNumber(0, 1)), M.SmoothPlastic)
				if pads % 3 == 0 then
					G.Flower(flora, at(p.X, WY + .05, p.Z), .35, BLOOM[pads % #BLOOM + 1], rng, 5)
				end
			end
		end
		-- sunken graves + half-drowned coffins
		local sunk, stries = 0, 0
		while sunk < 11 and stries < 300 do
			stries += 1
			local p = V3(rng:NextNumber(X0, X1), 0, rng:NextNumber(Z0, Z1))
			if free(p, 2.5) then
				sunk += 1
				if sunk % 4 == 0 then
					local cf = at(p.X, WY + .1, p.Z) * ANG(rng:NextNumber(-.25, .25), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3))
					K.Part(props, "DrownedCoffin", V3(2, .9, 5.6), cf, C(40, 30, 34), M.Wood)
					K.Wedge(props, "DrownedCoffinHead", V3(2, .9, 1.2), cf * CF(0, 0, -3.4), C(40, 30, 34), M.Wood)
					K.Part(props, "DrownedCoffinLid", V3(2.1, .15, 4.6), cf * CF(.3, .55, .4) * ANG(0, .12, .05), C(54, 40, 42), M.Wood)
					K.Part(props, "DrownedCoffinCross", V3(.2, .05, 1.6), cf * CF(.3, .66, -.4), COL.BoneDark, M.SmoothPlastic)
				else
					local cf = at(p.X, GY + .35, p.Z) * ANG(rng:NextNumber(-.25, .1), rng:NextNumber(0, PI * 2), rng:NextNumber(-.25, .25))
					Y.Tombstone(props, cf, ({ 1, 3, 6, 2, 5 })[sunk % 5 + 1], rng, nil, { Color = COL.Stone })
				end
			end
		end

		------------------------------------------------------------------------------------- the Weeping Dog shrine (west)
		do
			local face = V3(1, 0, 0)
			local sbase = K.Look(V3(SH.X - 2, BY, SH.Z), V3(SH.X - 2, BY, SH.Z) + face)
			K.Part(props, "ShrinePlinth", V3(5, 1.2, 5), sbase * CF(0, .6, 0), COL.StoneDark, M.Slate, G.Solid())
			K.Part(props, "ShrinePlinthCap", V3(5.4, .3, 5.4), sbase * CF(0, 1.35, 0), COL.Stone, M.Slate)
			Y.DogStatue(props, sbase * CF(0, 1.5, 0), { Bowed = true, Scale = 1.25, Color = C(150, 156, 176), Name = "WeepingDog" })
			for _, s in ipairs({ -1, 1 }) do
				K.Part(props, "StatueTear", V3(.14, .9, .1), sbase * CF(s * .5, 6.0, -2.2), COL.Moon, M.Neon, { Transparency = .2 })
			end
			K.Candles(props, sbase * CF(2.2, 1.5, -2.4), 4, rng, { Light = true, Range = 14, Spread = .6 })
			lights += 1
			for k = 1, 5 do
				local fa = -PI / 2 + (k - 3) * .5
				G.Flower(props, sbase * CF(math.sin(fa) * 4.5, 0, -math.cos(fa) * 4.5), rng:NextNumber(.8, 1.2), BLOOM[k % #BLOOM + 1], rng)
			end
		end

		----------------------------------------------------------------------------------------------- fog + motes (FX)
		local FOG = {
			{ -100, 2490, 26 }, { -160, 2487, 28 }, { -205, 2512, 22 }, { -208, 2598, 24 }, { -112, 2612, 26 }, { -168, 2655, 40 },
			{ -92, 2560, 20 }, { -96, 2690, 24 }, { -205, 2694, 24 }, { -132, 2696, 26 },
		}
		for _, f in ipairs(FOG) do
			local host = G.EmitterPart(fx, "FogEmitter", V3(f[3], 1, f[3]), at(f[1], WY + .6, f[2]))
			G.Fog(host, { Rate = f[3] > 30 and 2 or 1.2 })
		end
		for _, p in ipairs({ V3(-120, 0, 2660), V3(-196, 0, 2490), V3(-90, 0, 2510) }) do
			local host = G.EmitterPart(fx, "MoteEmitter", V3(14, 2, 14), at(p.X, 1.5, p.Z))
			G.Motes(host, { Color = COL.Green, Rate = 2.5, Size = .3 })
		end
		for _, p in ipairs({ V3(-120, 0, 2500), V3(-200, 0, 2560), V3(-100, 0, 2580), V3(-150, 0, 2700) }) do
			Y.Marker(fx, "FogPoint", p + V3(0, .4, 0))
		end

		local parts, nl, emitters = G.Count(root)
		ctx.Note(string.format("MourningMarsh: %d parts, %d lights, %d emitters (budget 3000 / 30)", parts, nl, emitters))
		local _ = lights
		return root
	end,
}
