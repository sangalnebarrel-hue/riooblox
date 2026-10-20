-- THE UNDERYARD · ground, islands, bridges, boundary (ServerStorage.UnderyardBuild.Ground, WP-G, Order 10). Build-time
-- only: tools/edits/40_underyard.luau runs it through tools/sim.luau; the output is saved in the place as
-- Workspace.DOGROTS_District.40_Underyard.Ground.
-- The zone is a ring of mesas inside a sunken cavern (DESIGN §7): BELL SQUARE is the central island (disc r 88, floor
-- top y 0) with the plaza and the ring road (their surfaces are Roads / BellSquare); bridges ("spokes") run from the
-- ring road through the five gates to the district islands, which sit in the corners of UnderyardLayout.Districts:
--   * FUNERAL CARNIVAL / CROOKED ROW / UNDERCRYPT at y 0, MOURNING MARSH at Marsh.GroundY (-1.5, the bridge ramps
--     down to it), the BLACK BELL ARENA island (circle r 62 round Arena.Centre + a strip to the south wall); the
--     Undercrypt floor leaves the sunken-mine hole (Undercrypt.Floor rect + the ramp corridor RampTop -> RampBottom,
--     12 wide) open for the district builder, which builds the pit walls and the y -16 floor.
--   * District floors are FLAT with irregular cliff edges only (the district builders add every prop); the edges are
--     crooked strata columns that drop into the abyss and break the straight box lines with a rocky rim.
--   * Between the mesas: the abyss (catch floor top y -40 over the whole zone, dark slate with violet fissures,
--     stalagmites, fallen bells, bone heaps) and rock spires; the cavern wall rises along UnderyardLayout.Bounds from
--     the abyss to y ~100 (Sky continues it to the ceiling ring) with moss ledges, glow fungus and fossil dog skulls.
--   * Safety: invisible colliders (UyCollider, 20 tall) along every walkable edge (central island rim, district inner
--     edges, bridge sides) with gaps only where the bridges join, plus 60-tall colliders on all four Bounds lines
--     (they reach down to the catch floor), and the catch floor itself (DistrictSafety's y -85 is never reached).
-- Nothing is placed on the gameplay anchors; walkable bridges are 20 wide between their parapets (gates 16 clear).
local U = require(script.Parent.UKit)
local K, Y = U.K, U.Y
local P = U.P
local C = U.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local ABYSS = -40 -- catch floor top
local BOTTOM = -42 -- cliff columns reach below it
local ISLAND_R = 88 -- central island rim
local BRIDGE_W = 22 -- deck width (20 walkable between the parapets)
local COLLIDE_H = 20 -- edge colliders: players jump ~7.2 studs
local BOUND_TOP = 60 -- Bounds colliders: 60 above the floor
local SIDE = BRIDGE_W / 2 - .2 -- spoke bridge side colliders, across the centre line
local APPROACH_HALF = 9.1 -- the arena approach's side colliders (Roads: 18-wide deck, colliders at +-9.1)

local TOP = C(54, 50, 64) -- central island floor (under the plaza / road surfaces)

local Ground = { Order = 10 }

function Ground.Build(ctx)
	local L = ctx.Layout
	local c = L.Centre
	local rng = U.Rng(40010)
	local root = ctx.Model("Ground")
	local island = K.Model(root, "CentralIsland")
	local bridges = K.Model(root, "Bridges")
	local districts = K.Model(root, "DistrictBases")
	local abyss = K.Model(root, "Abyss")
	local wall = K.Model(root, "CavernWall")
	local colliders = K.Model(root, "Colliders")
	root:SetAttribute("CatchFloorY", ABYSS)

	------------------------------------------------------------------------------------------------ bridges (corridors)
	-- every spoke: centre line from the island centre along the gate's radial direction; the arena spoke is the short
	-- landing in front of the Arena gate (Roads builds the approach bridge from there).
	local spokes = {}
	for name, g in pairs(L.Gates) do
		local a = U.AngleOf(c, g.Position)
		local u = V3(math.sin(a), 0, -math.cos(a))
		local r = (V3(g.Position.X, 0, g.Position.Z) - V3(c.X, 0, c.Z)).Magnitude
		table.insert(spokes, { Name = name, A = a, U = u, N = V3(-u.Z, 0, u.X), R = r, Gate = g.Position, Arena = name == "BlackBellArena" })
	end
	table.sort(spokes, function(x, y)
		return x.Name < y.Name
	end)
	-- distance along / across a spoke for a point (XZ)
	local function local2(sp, p: Vector3): (number, number)
		local d = V3(p.X - c.X, 0, p.Z - c.Z)
		return d:Dot(sp.U), d:Dot(sp.N)
	end
	local function inCorridor(p: Vector3, margin: number?): boolean
		for _, sp in ipairs(spokes) do
			local t, n = local2(sp, p)
			local half = (sp.Arena and 10.5 or BRIDGE_W / 2 + .5) + (margin or 0)
			local t1 = sp.Arena and 100 or 128
			if t > 78 and t < t1 and math.abs(n) < half then
				return true
			end
		end
		return false
	end

	------------------------------------------------------------------------------------------------ catch floor + abyss
	local zmin, zmax = L.Zone.Min, L.Zone.Max
	local catch = K.Part(abyss, "CatchFloor", V3(zmax.X - zmin.X + 10, 2, zmax.Z - zmin.Z + 10),
		CF((zmin.X + zmax.X) / 2, ABYSS - 1, (zmin.Z + zmax.Z) / 2), P.Abyss, M.Slate, { Solid = true, Shadow = false })
	catch:SetAttribute("UyCatchFloor", true)
	-- abyss dressing in the open chasms (never under an island): fissures, stalagmites, fallen bells, bone heaps
	local function openChasm(p: Vector3): boolean
		local dx, dz = p.X - c.X, p.Z - c.Z
		if dx * dx + dz * dz < (ISLAND_R + 6) ^ 2 then
			return false
		end
		for _, d in ipairs(L.Districts) do
			if d.Kind == "Box" and d.Name ~= "BlackBellArena" then
				if p.X > d.Min.X - 6 and p.X < d.Max.X + 6 and p.Z > d.Min.Z - 6 and p.Z < d.Max.Z + 6 then
					return false
				end
			end
		end
		local ax, az = p.X - L.Arena.Centre.X, p.Z - L.Arena.Centre.Z
		if ax * ax + az * az < 68 * 68 or (math.abs(ax) < 50 and p.Z > L.Arena.Centre.Z) then
			return false
		end
		return math.abs(p.X) < L.Bounds.X1 - 6 and p.Z > L.Bounds.Z0 + 6 and p.Z < L.Bounds.Z1 - 6
	end
	local chasmSpots = {}
	for _ = 1, 600 do
		local p = V3(rng:NextNumber(L.Bounds.X0, L.Bounds.X1), ABYSS, rng:NextNumber(L.Bounds.Z0, L.Bounds.Z1))
		if openChasm(p) and not inCorridor(p, 6) then
			table.insert(chasmSpots, p)
		end
		if #chasmSpots >= 44 then
			break
		end
	end
	for i, p in ipairs(chasmSpots) do
		local kind = i % 7
		if kind == 0 or kind == 3 then -- violet fissure (two crooked glowing strokes)
			local a = rng:NextNumber(0, PI)
			local q = p + V3(math.cos(a) * rng:NextNumber(6, 12), 0, math.sin(a) * rng:NextNumber(6, 12))
			local r = q + V3(math.cos(a + .6) * rng:NextNumber(4, 8), 0, math.sin(a + .6) * rng:NextNumber(4, 8))
			K.Bar(abyss, "AbyssFissure", p + V3(0, .05, 0), q + V3(0, .05, 0), rng:NextNumber(.4, .8), .1, U.GLOW.Violet, M.Neon)
			K.Bar(abyss, "AbyssFissure", q + V3(0, .05, 0), r + V3(0, .05, 0), rng:NextNumber(.3, .6), .1, U.GLOW.Violet, M.Neon)
		elseif kind == 1 or kind == 4 then -- stalagmite
			U.Crooked(abyss, "Stalagmite", CF(p), V3(rng:NextNumber(3, 6), rng:NextNumber(6, 16), rng:NextNumber(3, 6)), 3, rng,
				{ Color = P.Rock, Shade = P.RockDark, Taper = .3, Lean = .08 })
		elseif kind == 2 then -- bone heap: a skull on two crossed bones
			Y.Skull(abyss, CF(p + V3(0, .5, 0)) * ANG(-.3, rng:NextNumber(0, PI * 2), .1), 1.2, nil, P.BoneDark)
			K.Bone(abyss, CF(p + V3(0, .15, 0)) * ANG(0, rng:NextNumber(0, PI), 0), 2.2, P.BoneDark)
		elseif kind == 5 and i < 30 then -- a fallen bell, half sunk and cracked
			local bm = U.Bell(abyss, CF(p + V3(0, 3.2, 0)) * ANG(rng:NextNumber(.8, 1.3), rng:NextNumber(0, PI), 0), rng:NextNumber(1.4, 2.2),
				{ Name = "FallenBell", Color = C(70, 66, 74) })
			local _ = bm
		else -- glow fungus cluster
			K.Mushrooms(abyss, CF(p), 3, rng, U.GLOW.Green)
		end
	end
	-- rock spires rising from the abyss in the wide chasms (north of the square, east and west between the districts)
	local spireSpots = {
		V3(-46, 0, 2210), V3(30, 0, 2196), V3(-8, 0, 2260), V3(52, 0, 2268), V3(-60, 0, 2290),
		V3(150, 0, 2376), V3(200, 0, 2420), V3(118, 0, 2440), V3(-150, 0, 2372), V3(-196, 0, 2430), V3(-118, 0, 2420),
		V3(-68, 0, 2540), V3(66, 0, 2700),
	}
	for i, s in ipairs(spireSpots) do
		local h = rng:NextNumber(46, 78)
		local base = CF(s.X, ABYSS, s.Z)
		local top = U.Crooked(abyss, "AbyssSpire", base, V3(rng:NextNumber(9, 14), h * .62, rng:NextNumber(9, 14)), 4, rng,
			{ Color = P.Rock, Shade = P.RockDark, Taper = .12, Lean = .06, Twist = .25, Solid = 1 })
		U.Spire(abyss, "AbyssSpireTip", top, rng:NextNumber(5, 7), h * .38, rng, { Tiers = 3, Color = P.RockLight, Shade = P.Rock, Curl = .07, Flat = true })
		if i % 3 == 0 then
			U.Roots(abyss, (top * CF(0, -2, 0)).Position, 12, rng, { Count = 2, Glow = U.GLOW.Green })
		end
	end

	------------------------------------------------------------------------------------------------ central island
	local disc = K.CylY(island, "IslandFloor", 8, ISLAND_R * 2, CF(c.X, -4, c.Z), TOP, M.Cobblestone, { Solid = true })
	disc:SetAttribute("UyFloor", "BellSquare")
	local nCol = 54
	for i = 1, nCol do
		local a = (i - .5) / nCol * PI * 2 + rng:NextNumber(-.03, .03)
		local out = V3(math.sin(a), 0, -math.cos(a))
		local r = ISLAND_R + rng:NextNumber(1, 3.5)
		local top = U.Polar(c, r, a, -rng:NextNumber(.25, 1.2))
		U.CliffColumn(island, top, BOTTOM, out, rng, { Width = 12, Depth = 8, Tiers = 2, Color = P.RockLight, Shade = P.RockDark, Moss = .12 })
	end
	-- parapet: crooked low stone blocks round the rim, skull caps here and there, gaps at the bridges
	local nPar = 84
	for i = 1, nPar do
		local a0 = (i - 1) / nPar * PI * 2
		local a1 = i / nPar * PI * 2 - .012
		local pa, pb = U.Polar(c, ISLAND_R - .9, a0, 0), U.Polar(c, ISLAND_R - .9, a1, 0)
		local mid = (pa + pb) / 2
		if not inCorridor(mid, 1) then
			local h = rng:NextNumber(1.3, 2.0)
			local blk = K.Bar(island, "Parapet", pa + V3(0, h / 2, 0), pb + V3(0, h / 2, 0), 1.3, h, P.Stone:Lerp(P.StoneDark, rng:NextNumber(0, .6)), M.Slate,
				{ Solid = true })
			blk.CFrame *= ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.05, .05))
			if i % 6 == 0 then
				Y.Skull(island, K.Look(mid + V3(0, h + .45, 0), V3(c.X, h + .45, c.Z)), .9, i % 12 == 0 and U.GLOW.Green or nil, P.Bone)
			elseif i % 6 == 3 then
				K.Part(island, "ParapetCap", V3(1.7, .35, 2.2), CF(mid + V3(0, h + .1, 0)) * ANG(0, -U.AngleOf(c, mid), 0), P.StoneLight, M.Slate)
			end
		end
	end
	-- rim collider, open exactly between the side colliders of each bridge (approach: +-9.1, spokes: +-10.8)
	local gaps = {}
	for _, sp in ipairs(spokes) do
		table.insert(gaps, { Angle = sp.A, Half = sp.Arena and APPROACH_HALF or SIDE })
	end
	U.ArcColliders(colliders, c, ISLAND_R + .4, 0, PI * 2, gaps, -1, COLLIDE_H)

	------------------------------------------------------------------------------------------------ district islands
	-- inner edges of a box district = the sides that are not on the zone Bounds
	local B = L.Bounds
	local edgeLines = {} -- district name -> { {A, B, Out} } collider lines (offset 1.2 outside the box)
	local function edgeFeatures(model: Instance, a: Vector3, b: Vector3, out: Vector3, topY: number, name: string)
		local len = (b - a).Magnitude
		local n = math.max(2, math.floor(len / 9.5))
		for k = 0, n do
			local p = a:Lerp(b, math.clamp((k + rng:NextNumber(-.3, .3)) / n, 0, 1))
			-- a rim rock above the floor stands fully outside the box; a ledge below the floor may reach under it
			local depth = rng:NextNumber(7, 11)
			local dy = rng:NextNumber(-.7, 1.4)
			if math.abs(dy) < .25 then
				dy = -.35
			end
			local off = dy > 0 and depth / 2 + rng:NextNumber(.9, 2.5) or rng:NextNumber(1.2, 5.5)
			local top = V3(p.X, topY + dy, p.Z) + out * off
			if not inCorridor(top, 3) then
				U.CliffColumn(model, top, BOTTOM, out, rng, { Width = rng:NextNumber(8, 12), Depth = depth, Tiers = 2, Color = P.Rock, Shade = P.RockDark,
					Moss = .12, Push = dy > 0 and 0 or nil })
			end
		end
		-- the walkable edge: colliders on a line 1.2 outside the box, cut exactly between each crossing bridge's side
		-- colliders (|offset across the bridge| < SIDE, beyond the island rim)
		local lines = edgeLines[name] or {}
		edgeLines[name] = lines
		local la, lb = a + out * 1.2, b + out * 1.2
		table.insert(lines, { A = la, B = lb, Out = out })
		local e = (lb - la).Unit
		local cuts = {}
		for _, sp in ipairs(spokes) do
			if not sp.Arena then
				local rel = V3(la.X - c.X, 0, la.Z - c.Z)
				local k0, k1 = sp.N:Dot(rel), sp.N:Dot(e)
				if math.abs(k1) > 1e-6 then
					local s0, s1 = (-SIDE - k0) / k1, (SIDE - k0) / k1
					if s0 > s1 then
						s0, s1 = s1, s0
					end
					local tm = sp.U:Dot(rel + e * ((s0 + s1) / 2))
					if s1 > 0 and s0 < len and tm > ISLAND_R then
						table.insert(cuts, { math.max(0, s0), math.min(len, s1) })
					end
				end
			end
		end
		table.sort(cuts, function(x, y)
			return x[1] < y[1]
		end)
		local runs, cur = {}, 0
		for _, cut in ipairs(cuts) do
			if cut[1] > cur then
				table.insert(runs, { cur, cut[1] })
			end
			cur = math.max(cur, cut[2])
		end
		if cur < len then
			table.insert(runs, { cur, len })
		end
		for _, run in ipairs(runs) do
			if run[2] - run[1] > .5 then
				U.Collider(colliders, la + e * run[1], la + e * run[2], topY - 1, topY + COLLIDE_H, 2, 0)
			end
		end
	end

	local function slab(model: Instance, name: string, x0: number, x1: number, z0: number, z1: number, topY: number, col: Color3, mat: Enum.Material)
		return K.Part(model, name, V3(x1 - x0, 8, z1 - z0), CF((x0 + x1) / 2, topY - 4, (z0 + z1) / 2), col, mat, { Solid = true })
	end
	-- rotated floor piece: along direction d (unit, XZ) from point o for length len, extending `w` to the side n (unit)
	-- (top 0.02 below topY: it overlaps the axis slabs, the lower face never z-fights)
	local function slabAlong(model: Instance, name: string, o: Vector3, d: Vector3, len: number, n: Vector3, w: number, topY: number, col: Color3,
		mat: Enum.Material)
		local centre = o + d * (len / 2) + n * (w / 2)
		local cf = K.Look(V3(centre.X, topY - 4.02, centre.Z), V3(centre.X + d.X, topY - 4.02, centre.Z + d.Z))
		return K.Part(model, name, V3(w, 8, len), cf, col, mat, { Solid = true })
	end

	local LOOK = {
		FuneralCarnival = { C(60, 50, 58), M.Ground },
		CrookedRow = { C(58, 54, 66), M.Slate },
		MourningMarsh = { C(44, 48, 44), M.Mud },
		Undercrypt = { C(56, 52, 62), M.Slate },
	}
	for _, d in ipairs(L.Districts) do
		if d.Kind == "Box" and d.Name ~= "BlackBellArena" then
			local m = K.Model(districts, d.Name .. "Base")
			m:SetAttribute("UyDistrictBase", d.Name)
			local look = LOOK[d.Name] or { P.Slate, M.Slate }
			local topY = d.Name == "MourningMarsh" and L.Marsh.GroundY or 0
			local x0, x1, z0, z1 = d.Min.X, d.Max.X, d.Min.Z, d.Max.Z
			local floorName = d.Name .. "Floor"
			if d.Name == "Undercrypt" then
				-- floor with the sunken-mine hole: R = Undercrypt.Floor rect, Q = ramp corridor (RampTop -> RampBottom, 12 wide,
				-- starting 2 before RampTop and running into R). Filled around it with axis + corridor-aligned pieces.
				local UC = L.Undercrypt
				local fx0, fx1, fz0, fz1 = UC.Floor.Min.X, UC.Floor.Max.X, UC.Floor.Min.Z, UC.Floor.Max.Z
				local rt, rb = V3(UC.RampTop.X, 0, UC.RampTop.Z), V3(UC.RampBottom.X, 0, UC.RampBottom.Z)
				local dd = (rb - rt).Unit
				local pp = V3(dd.Z, 0, -dd.X) -- perpendicular, points east / north-east of the corridor
				if pp.X < 0 then
					pp = -pp
				end
				local hw = 6
				local s = rt - dd * 2
				local wEdge0 = s - pp * hw -- west edge start
				local eEdge0 = s + pp * hw -- east edge start
				local zN = math.min(wEdge0.Z, eEdge0.Z)
				local xW = math.min(wEdge0.X, eEdge0.X)
				local tW = (fx0 - wEdge0.X) / dd.X -- west edge reaches x = fx0
				local zW = wEdge0.Z + dd.Z * tW
				local tE = (fz0 - eEdge0.Z) / dd.Z -- east edge reaches z = fz0
				local xE = eEdge0.X + dd.X * tE
				slab(m, floorName, x0, x1, z0, zN, topY, look[1], look[2]) -- north band
				slab(m, floorName, x0, x1, fz1, z1, topY, look[1], look[2]) -- south band
				slab(m, floorName, fx1, x1, zN, fz1, topY, look[1], look[2]) -- east band
				slab(m, floorName, x0, xW, zN, fz1, topY, look[1], look[2]) -- west band
				slab(m, floorName, xW, fx0, zW, fz1, topY, look[1], look[2]) -- west of R, south of the corridor
				slab(m, floorName, xE, fx1, zN, fz0, topY, look[1], look[2]) -- north of R, east of the corridor
				slabAlong(m, floorName, wEdge0, dd, tW, -pp, 12, topY, look[1], look[2]) -- along the corridor's west edge
				slabAlong(m, floorName, eEdge0, dd, tE, pp, 12, topY, look[1], look[2]) -- along the corridor's east edge
				slabAlong(m, floorName, s - pp * (hw + 2), -dd, 9, pp, hw * 2 + 4, topY, look[1], look[2]) -- behind the corridor's top
				m:SetAttribute("MineHoleRect", string.format("%g,%g,%g,%g", fx0, fz0, fx1, fz1))
				m:SetAttribute("MineHoleRamp", string.format("%g,%g,%g,%g,%g", s.X, s.Z, rb.X + dd.X * 4, rb.Z + dd.Z * 4, hw * 2))
			else
				slab(m, floorName, x0, x1, z0, z1, topY, look[1], look[2])
			end
			for _, f in ipairs(m:GetChildren()) do
				if f:IsA("BasePart") then
					f:SetAttribute("UyFloor", d.Name)
				end
			end
			-- inner edges (sides not on the Bounds)
			local sides = {
				{ x0 > B.X0 + .5, V3(x0, 0, z0), V3(x0, 0, z1), V3(-1, 0, 0) },
				{ x1 < B.X1 - .5, V3(x1, 0, z0), V3(x1, 0, z1), V3(1, 0, 0) },
				{ z0 > B.Z0 + .5, V3(x0, 0, z0), V3(x1, 0, z0), V3(0, 0, -1) },
				{ z1 < B.Z1 - .5, V3(x0, 0, z1), V3(x1, 0, z1), V3(0, 0, 1) },
			}
			for _, sd in ipairs(sides) do
				if sd[1] then
					edgeFeatures(m, sd[2], sd[3], sd[4], topY, d.Name)
				end
			end
		end
	end

	-- BLACK BELL ARENA island: circle r 62 round Arena.Centre + a strip to the south wall, floor y 0
	do
		local m = K.Model(districts, "BlackBellArenaBase")
		m:SetAttribute("UyDistrictBase", "BlackBellArena")
		local A = L.Arena.Centre
		local AR, SX = 62, 44
		local col, mat = C(50, 46, 60), M.Slate
		local f1 = K.CylY(m, "BlackBellArenaFloor", 8, AR * 2, CF(A.X, -4, A.Z), col, mat, { Solid = true })
		local f2 = K.Part(m, "BlackBellArenaFloor", V3(SX * 2, 8, B.Z1 - A.Z), CF(A.X, -4.02, (A.Z + B.Z1) / 2), col, mat, { Solid = true })
		f1:SetAttribute("UyFloor", "BlackBellArena")
		f2:SetAttribute("UyFloor", "BlackBellArena")
		local zSide = A.Z + math.sqrt(AR * AR - SX * SX)
		-- rim columns on the arc (west side round the north to the east side) and down the strip sides
		local aMin = PI - math.asin(SX / AR) -- layout angle of the arc's meeting point with the strip
		local nArc = 46
		-- (rim rocks that rise above the floor stand fully outside the island; lower ledges may reach under it)
		local function rim(): (number, number)
			local dy = rng:NextNumber(-.7, 1.3)
			if math.abs(dy) < .25 then
				dy = -.35
			end
			return dy, dy > 0 and 4.5 + rng:NextNumber(.9, 2.5) or rng:NextNumber(1.2, 4.5)
		end
		for i = 0, nArc do
			local a = -aMin + (2 * aMin) * i / nArc
			local dy, off = rim()
			local top = U.Polar(A, AR + off, a, dy)
			if not inCorridor(top, 3) and math.abs(U.AngleDiff(a, 0)) > .2 then
				U.CliffColumn(m, top, BOTTOM, V3(math.sin(a), 0, -math.cos(a)), rng, { Width = 10, Depth = 9, Tiers = 2, Color = P.Rock, Shade = P.RockDark,
					Moss = .12, Push = dy > 0 and 0 or nil })
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			for z = zSide, B.Z1 - 4, 8 do
				local dy, off = rim()
				U.CliffColumn(m, V3(A.X + sx * (SX + off), dy, z), BOTTOM, V3(sx, 0, 0), rng,
					{ Width = 9, Depth = 9, Tiers = 2, Color = P.Rock, Shade = P.RockDark, Push = dy > 0 and 0 or nil })
			end
			U.Collider(colliders, V3(A.X + sx * (SX + 1.2), 0, zSide - 2), V3(A.X + sx * (SX + 1.2), 0, B.Z1), -1, COLLIDE_H)
		end
		-- arc collider, open exactly between the approach bridge's side colliders at the north landing
		U.ArcColliders(colliders, A, AR + 1.2, -aMin, aMin, { { Angle = 0, Half = APPROACH_HALF } }, -1, COLLIDE_H)
		m:SetAttribute("ApproachLanding", L.Arena.Approach.To)
	end

	------------------------------------------------------------------------------------------------ spoke bridges
	local function lineHit(o: Vector3, dir: Vector3, a: Vector3, b: Vector3): number?
		-- distance t along o + dir * t where it crosses segment a-b (XZ), or nil
		local ex, ez = b.X - a.X, b.Z - a.Z
		local den = dir.X * ez - dir.Z * ex
		if math.abs(den) < 1e-6 then
			return nil
		end
		local wx, wz = a.X - o.X, a.Z - o.Z
		local t = (wx * ez - wz * ex) / den
		local s = (wx * dir.Z - wz * dir.X) / den
		if s < -.02 or s > 1.02 then
			return nil
		end
		return t
	end
	for _, sp in ipairs(spokes) do
		local m = K.Model(bridges, "Bridge_" .. sp.Name)
		m:SetAttribute("Gate", sp.Name)
		local function at(t: number, n: number, y: number?): Vector3
			return V3(c.X, y or 0, c.Z) + sp.U * t + sp.N * n
		end
		local look = K.Look(at(sp.R, 0, -4.02), at(sp.R + 1, 0, -4.02)) -- top 0.02 under the floors it overlaps
		-- gate landing (wide enough for the arch plinths)
		local landing = K.Part(m, "GateLanding", V3(36, 8, 13), look, C(60, 56, 70), M.Slate, { Solid = true })
		landing:SetAttribute("UyFloor", "BellSquare")
		for _, sx in ipairs({ -1, 1 }) do
			for k = 0, 1 do
				U.CliffColumn(m, at(sp.R + (k == 0 and -4 or 4), sx * 17.5, -.4), BOTTOM, sp.N * sx, rng,
					{ Width = 8, Depth = 7, Tiers = 2, Color = P.RockLight, Shade = P.RockDark })
			end
		end
		if sp.Arena then
			continue
		end
		local marsh = sp.Name == "MourningMarsh"
		local endY = marsh and L.Marsh.GroundY or 0
		local t0, t1 = 82, 122
		-- deck top 0.04 under the island / district floors it overlaps (no z-fighting where they meet)
		local pts = { at(t0, 0, -.04), at(102, 0, -.04) }
		if marsh then
			table.insert(pts, at(110, 0, endY - .04))
		end
		table.insert(pts, at(t1, 0, endY - .04))
		for _, p in ipairs(U.Deck(m, "BridgeDeck", pts, BRIDGE_W, 3, C(62, 58, 72), M.Slate)) do
			p:SetAttribute("UyFloor", "BellSquare")
		end
		-- under the deck: a pointed rib arch between the cliffs and two crooked piers into the abyss
		for _, sx in ipairs({ -1, 1 }) do
			local pier = at(sp.R + 4, sx * 8.5, -3)
			U.Crooked(m, "BridgePier", CF(V3(pier.X, BOTTOM, pier.Z)) * ANG(0, -sp.A, 0), V3(4.5, -3 - BOTTOM, 4.5), 3, rng,
				{ Color = P.Stone, Shade = P.StoneDark, Taper = -.04, Lean = .02, Solid = true })
			local ribA, ribB = at(sp.R - 9, sx * 8.5, -12), at(sp.R + 4, sx * 8.5, -3.2)
			K.Bar(m, "BridgeRib", ribA, ribB, 2.2, 2.2, P.StoneDark, M.Slate)
			K.Bar(m, "BridgeRib", ribB, at(sp.R + 17, sx * 8.5, -12), 2.2, 2.2, P.StoneDark, M.Slate)
		end
		-- parapets + side colliders from the island rim to the district edge (clipped where they meet its collider line)
		local target = edgeLines[sp.Name] or {}
		for _, sx in ipairs({ -1, 1 }) do
			local o = at(0, sx * SIDE, 0)
			local tHit = nil
			for _, ln in ipairs(target) do
				local t = lineHit(o, sp.U, ln.A, ln.B)
				if t and t > 90 and (tHit == nil or t < tHit) then
					tHit = t
				end
			end
			tHit = tHit or 112
			U.Collider(colliders, at(ISLAND_R - 2.5, sx * SIDE, 0), at(tHit + .8, sx * SIDE, 0), -1, COLLIDE_H)
			-- parapet blocks (stop short of the gate plinths) with bone-knuckle posts
			local segs = {}
			table.insert(segs, { ISLAND_R - 1.5, sp.R - 4.8 })
			table.insert(segs, { sp.R + 4.8, math.min(tHit - 1, sp.R + 14) })
			for _, sg in ipairs(segs) do
				if sg[2] - sg[1] > 1 then
					local n = math.max(1, math.floor((sg[2] - sg[1]) / 3.6))
					for k = 1, n do
						local ta = sg[1] + (sg[2] - sg[1]) * (k - 1) / n
						local tb = sg[1] + (sg[2] - sg[1]) * k / n - .15
						local yA = marsh and ta > 102 and math.max(endY, (ta - 102) / 8 * endY) or 0
						local yB = marsh and tb > 102 and math.max(endY, (tb - 102) / 8 * endY) or 0
						local h = 1.6
						local blk = K.Bar(m, "BridgeParapet", at(ta, sx * (BRIDGE_W / 2 - .6), yA + h / 2), at(tb, sx * (BRIDGE_W / 2 - .6), yB + h / 2), 1.2, h,
							P.Stone:Lerp(P.StoneDark, rng:NextNumber(0, .5)), M.Slate, { Solid = true })
						blk.CFrame *= ANG(0, 0, rng:NextNumber(-.05, .05))
						if k % 2 == 0 then
							K.Ball(m, "ParapetKnuckle", .75, CF(at(ta, sx * (BRIDGE_W / 2 - .6), yA + h + .2)), P.Bone, M.SmoothPlastic)
						end
					end
				end
			end
		end
	end

	------------------------------------------------------------------------------------------------ cavern wall (Bounds)
	-- irregular strata columns (26..44 wide, four tiers stepping back as they rise, the inner face never inside the Bounds
	-- line), long pale strata ledges across several columns, leaning buttress slabs, glow fungus ledges, crystal veins
	-- and root curtains. Sky continues the wall from y ~95 into the ceiling ring.
	local function wallRun(a: Vector3, b: Vector3, out: Vector3, name: string)
		local len = (b - a).Magnitude
		local along = (b - a).Unit
		local s = -4
		local col = 0
		while s < len + 4 do
			col += 1
			local w = rng:NextNumber(26, 44)
			local mid = a + along * (s + w / 2)
			local y = BOTTOM
			local tops = { rng:NextNumber(-6, 6), rng:NextNumber(26, 42), rng:NextNumber(58, 76), rng:NextNumber(92, 104) }
			for ti, y1 in ipairs(tops) do
				local depth = rng:NextNumber(18, 30)
				local push = 2.2 + (ti - 1) * rng:NextNumber(.6, 2.4) + rng:NextNumber(0, 3)
				local cpos = mid + out * (push + depth / 2) + V3(0, (y + y1) / 2, 0)
				local cf = K.Look(cpos, cpos + out) * ANG(rng:NextNumber(-.035, .02), rng:NextNumber(-.05, .05), rng:NextNumber(-.06, .06))
				local shade = (ti + col) % 3 == 0 and rng:NextNumber(.5, .75) or rng:NextNumber(0, .35)
				K.Part(wall, name, V3(w + rng:NextNumber(1, 5), y1 - y + 2, depth), cf, P.RockLight:Lerp(P.RockDark, shade), M.Slate, { Solid = ti <= 2 })
				-- face details (one per tier at most)
				local r = rng:NextNumber()
				local face = mid + out * (push - .2) + along * rng:NextNumber(-w * .3, w * .3)
				if ti >= 2 and r < .16 then
					local ly = y1 - rng:NextNumber(2, 6)
					local lp = face + V3(0, ly, 0) - out * 1.4
					K.Part(wall, "WallLedge", V3(rng:NextNumber(8, 14), .9, 3.2), K.Look(lp, lp - out), P.RockLight, M.Slate)
					K.Mushrooms(wall, K.Look(lp + V3(0, .45, 0), lp - out * 3 + V3(0, .45, 0)), 2, rng, (col % 2 == 0) and U.GLOW.Green or U.GLOW.Moon)
				elseif r < .3 then
					local v0 = face + V3(0, rng:NextNumber(y + 4, y1 - 8), 0) - out * .25
					local v1 = v0 + V3(0, rng:NextNumber(5, 10), 0) + along * rng:NextNumber(-4, 4)
					K.Bar(wall, "CrystalVein", v0, v1, .55, .35, U.GLOW.Violet, M.Neon)
				elseif ti >= 3 and r < .38 then
					U.Roots(wall, face + V3(0, y1 - 1, 0) - out * .4, rng:NextNumber(12, 22), rng, { Count = 1, Glow = (col % 3 == 0) and U.GLOW.Green or nil })
				end
				y = y1
			end
			-- leaning buttress slab every few columns (top leans out of the wall face, only above head height)
			if col % 3 == 0 then
				local bp = mid + out * 3 + V3(0, 46, 0)
				local bcf = K.Look(bp, bp + out) * ANG(-.22, rng:NextNumber(-.2, .2), rng:NextNumber(-.15, .15))
				K.Part(wall, "WallButtress", V3(rng:NextNumber(10, 16), 70, 12), bcf * CF(0, 0, 6), P.Rock:Lerp(P.RockDark, rng:NextNumber(0, .5)), M.Slate)
			end
			s += w
		end
		-- pale strata ledges running across the columns
		for _, sy in ipairs({ rng:NextNumber(24, 30), rng:NextNumber(54, 62), rng:NextNumber(84, 90) }) do
			local t = rng:NextNumber(0, 40)
			while t < len - 10 do
				local l = rng:NextNumber(50, 110)
				local p0 = a + along * t + V3(0, sy + rng:NextNumber(-3, 3), 0) + out * 1.4
				local p1 = a + along * math.min(len, t + l) + V3(0, sy + rng:NextNumber(-3, 3), 0) + out * 1.4
				K.Bar(wall, "WallStrata", p0, p1, 3.4, 1.6, P.StoneLight:Lerp(P.Rock, .35), M.Slate)
				t += l + rng:NextNumber(20, 60)
			end
		end
	end
	wallRun(V3(B.X0, 0, B.Z0), V3(B.X1, 0, B.Z0), V3(0, 0, -1), "CavernWallN")
	wallRun(V3(B.X0, 0, B.Z1), V3(B.X1, 0, B.Z1), V3(0, 0, 1), "CavernWallS")
	wallRun(V3(B.X0, 0, B.Z0), V3(B.X0, 0, B.Z1), V3(-1, 0, 0), "CavernWallW")
	wallRun(V3(B.X1, 0, B.Z0), V3(B.X1, 0, B.Z1), V3(1, 0, 0), "CavernWallE")
	for _, cx in ipairs({ B.X0, B.X1 }) do
		for _, cz in ipairs({ B.Z0, B.Z1 }) do
			local o = V3(cx > 0 and 1 or -1, 0, cz > c.Z and 1 or -1)
			K.Part(wall, "CavernCorner", V3(40, 150, 40), CF(cx + o.X * 22, 30, cz + o.Z * 22) * ANG(0, rng:NextNumber(0, PI), 0), P.RockDark, M.Slate)
		end
	end
	-- fossil dog skulls embedded in the wall (dogs everywhere), facing into the zone
	for i, f in ipairs({ { V3(-120, 46, B.Z0 - 3), V3(0, 0, 1) }, { V3(B.X1 + 3, 40, 2400), V3(-1, 0, 0) }, { V3(B.X0 - 3, 52, 2560), V3(1, 0, 0) },
		{ V3(150, 58, B.Z1 + 3), V3(0, 0, -1) } }) do
		Y.GiantSkull(wall, K.Look(f[1], f[1] + f[2]) * ANG(.15, 0, 0), 1.6 + (i % 2) * .4,
			{ Lite = true, Mound = false, Solid = false, Light = false, Eye = U.GLOW.Green, EyeDim = C(60, 140, 80), Name = "FossilSkull" })
	end
	-- 60-tall colliders on the Bounds lines (outside the line, down to the catch floor)
	local bt = 2
	K.Part(colliders, "BoundCollider", V3(B.X1 - B.X0 + bt * 2, BOUND_TOP - ABYSS, bt), CF((B.X0 + B.X1) / 2, (BOUND_TOP + ABYSS) / 2, B.Z0 - bt / 2),
		P.Violet, M.SmoothPlastic, { Solid = true, Shadow = false, Transparency = 1 })
	K.Part(colliders, "BoundCollider", V3(B.X1 - B.X0 + bt * 2, BOUND_TOP - ABYSS, bt), CF((B.X0 + B.X1) / 2, (BOUND_TOP + ABYSS) / 2, B.Z1 + bt / 2),
		P.Violet, M.SmoothPlastic, { Solid = true, Shadow = false, Transparency = 1 })
	K.Part(colliders, "BoundCollider", V3(bt, BOUND_TOP - ABYSS, B.Z1 - B.Z0 + bt * 2), CF(B.X0 - bt / 2, (BOUND_TOP + ABYSS) / 2, (B.Z0 + B.Z1) / 2),
		P.Violet, M.SmoothPlastic, { Solid = true, Shadow = false, Transparency = 1 })
	K.Part(colliders, "BoundCollider", V3(bt, BOUND_TOP - ABYSS, B.Z1 - B.Z0 + bt * 2), CF(B.X1 + bt / 2, (BOUND_TOP + ABYSS) / 2, (B.Z0 + B.Z1) / 2),
		P.Violet, M.SmoothPlastic, { Solid = true, Shadow = false, Transparency = 1 })

	if ctx.Note then
		ctx.Note(string.format("Ground: %d parts (island %d, bridges %d, districts %d, abyss %d, wall %d, colliders %d)", K.Count(root), K.Count(island),
			K.Count(bridges), K.Count(districts), K.Count(abyss), K.Count(wall), K.Count(colliders)))
	end
end

return Ground
