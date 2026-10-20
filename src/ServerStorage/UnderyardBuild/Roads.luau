-- THE UNDERYARD · roads (ServerStorage.UnderyardBuild.Roads, WP-G, Order 20). Build-time only: tools/edits/
-- 40_underyard.luau runs it through tools/sim.luau; saved as 40_Underyard.Roads.
--   * RING ROAD (UnderyardLayout.Square.RingRoad r 66..82 on the central island's cobble floor): a spiral of pale stone
--     bands swirling round the square, a dog's paw-print trail walking the centre line, black/white striped kerbs on
--     both edges (inner kerb open at the arrival arch, the Tailor's stall and the practice ring; outer kerb open at the
--     five spokes), 16 crooked street lamps on the outer verge (HwLantern, one light each).
--   * SPOKES: a pale runner with paw prints along each bridge deck (Ground builds the decks) from the road to the
--     district floor, and a black/white checker threshold under every gate.
--   * THE BLACK BELL APPROACH: the bridge from Gate_BlackBellArena to the arena edge (Arena.Approach, 18 wide). It
--     climbs onto a crest (y 7) and then winds DOWN in a spiral question-mark curl round the CURLED SPIRE (a twisted rock
--     column rising out of the abyss whose top rolls up like a fern) to the arena landing at y 0. Solid deck along the
--     sampled curve (segments + joint discs), keel and piers into the abyss, crooked parapets alternating bone-white and
--     ink stone, side colliders (20 tall) from inside the island gap to inside the arena island, pale cross bands and a
--     paw trail, 6 lamps.
-- Lights: 22 (all Shadows=false). Nothing on the gameplay anchors (echo / choir points are on open road).
local U = require(script.Parent.UKit)
local K, Y = U.K, U.Y
local P = U.P
local C = U.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local CREST = 7 -- approach crest height
local DECK_W = 18
local COLLIDE_H = 20

local Roads = { Order = 20 }

local function smooth(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- centreline of the arena approach (flat, y = 0): straight -> 90deg turn east -> 180deg curl -> 90deg turn back south
local function approachPath(L): { Vector3 }
	local from, to = L.Arena.Approach.From, L.Arena.Approach.To
	local x0 = from.X
	local z0 = from.Z + 6 -- end of the gate straight
	local zEnd = to.Z - 3 -- end of the last turn
	local a = 20
	local b = ((zEnd - z0) - 2 * a) / 2
	local pts = {}
	local function add(p: Vector3)
		table.insert(pts, p)
	end
	add(V3(x0, 0, from.Z - 4))
	for z = from.Z - 1, z0, 3 do
		add(V3(x0, 0, z))
	end
	local function arc(cx: number, cz: number, r: number, t0: number, t1: number, n: number)
		for i = 1, n do
			local t = t0 + (t1 - t0) * i / n
			add(V3(cx + math.cos(t) * r, 0, cz + math.sin(t) * r))
		end
	end
	-- A: centre (x0 + a, z0), from angle pi (west point) to pi/2 (south point), heading +x at the end
	arc(x0 + a, z0, a, PI, PI / 2, 11)
	-- B: centre (x0 + a, z0 + a + b), from -pi/2 (north point) through 0 (east) to pi/2 (south point)
	arc(x0 + a, z0 + a + b, b, -PI / 2, PI / 2, 21)
	-- C: centre (x0 + a, zEnd), from -pi/2 (north point) to -pi (west point), heading +z at the end
	arc(x0 + a, zEnd, a, -PI / 2, -PI, 11)
	add(V3(x0, 0, to.Z + 2))
	add(V3(x0, 0, to.Z + 6))
	return pts
end
Roads.ApproachPath = approachPath

function Roads.Build(ctx)
	local L = ctx.Layout
	local c = L.Centre
	local SQ = L.Square
	local rng = U.Rng(40020)
	local root = ctx.Model("Roads")
	local ring = K.Model(root, "RingRoad")
	local spokesM = K.Model(root, "Spokes")
	local lampsM = K.Model(root, "StreetLamps")
	local lightCount = 0

	local rIn, rOut = SQ.RingRoad.Inner, SQ.RingRoad.Outer
	local rMid = (rIn + rOut) / 2
	local practice = SQ.PracticeRing
	local function nearPractice(p: Vector3, m: number): boolean
		local dx, dz = p.X - practice.Centre.X, p.Z - practice.Centre.Z
		return dx * dx + dz * dz < (practice.Radius + m) ^ 2
	end
	-- spoke angles (layout angles of the gates seen from the centre)
	local spokeA = {}
	for name, g in pairs(L.Gates) do
		spokeA[name] = U.AngleOf(c, g.Position)
	end
	local function nearSpoke(a: number, halfWidth: number, r: number): boolean
		for _, sa in pairs(spokeA) do
			if math.abs(U.AngleDiff(a, sa)) * r < halfWidth then
				return true
			end
		end
		return false
	end
	-- inner-kerb openings: the arrival arch (north), the Tailor's stall, the practice ring
	local arrivalA = U.AngleOf(c, L.ArrivalArch)
	local tailorA = U.AngleOf(c, SQ.Tailor.Position)
	local function innerOpen(a: number): boolean
		return math.abs(U.AngleDiff(a, arrivalA)) < .2 or math.abs(U.AngleDiff(a, tailorA)) < .11
	end

	------------------------------------------------------------------------------------------------ ring road
	-- spiral bands: pale stone strips leaning 28 degrees off the radial, all swirling the same way
	local nBands = 40
	for i = 1, nBands do
		local a = (i - .5) / nBands * PI * 2
		local p = U.Polar(c, rMid, a, .05)
		if not nearPractice(p, 3) then
			local radial = V3(math.sin(a), 0, -math.cos(a))
			local cf = K.Look(p, p + radial) * ANG(0, math.rad(28), 0)
			K.Part(ring, "SpiralBand", V3(2.4, .08, (rOut - rIn) / math.cos(math.rad(28)) + .6), cf, i % 2 == 0 and P.CobbleLight or P.StoneLight,
				M.Slate)
		end
	end
	-- the dog that walked the ring: paw prints along the centre line (skipping the practice ring)
	local loop = U.ArcPoints(c, rMid - 2, 0, PI * 2, 96, .03)
	U.PawTrail(ring, loop, 14, { Size = 1.6, Gait = 1.0, Color = P.BoneDark, Skip = function(p)
		return nearPractice(p, 2)
	end })
	-- striped kerbs (solid, 0.35 tall): inner r 64..66, outer r 82..84
	local function kerbRing(r: number, seg: number, skip)
		local pts = U.ArcPoints(c, r, 0, PI * 2, 160, 0)
		U.StripeTrim(ring, "RoadKerb", pts, 2, .35, seg, { Solid = true, Material = M.Slate, Skip = skip })
	end
	kerbRing(rIn - 1, 5, function(p)
		local a = U.AngleOf(c, p)
		return innerOpen(a) or nearPractice(p, 1.5)
	end)
	kerbRing(rOut + 1, 5.5, function(p)
		return nearSpoke(U.AngleOf(c, p), 12, rOut + 1)
	end)
	-- street lamps on the outer verge (r 85.5), clear of the spokes, hook over the road; pennant strings between
	-- neighbouring lamps (not across a spoke)
	local lampTop = {}
	for i = 1, 16 do
		local a = (i - .5) / 16 * PI * 2
		if not nearSpoke(a, 15, 86) then
			local base = U.Polar(c, 85.6, a, 0)
			local lm = U.Lamp(lampsM, U.Facing(base, c), rng, { Height = 11.5, Color = (i % 4 == 0) and U.GLOW.Green or U.GLOW.Candle,
				Kind = (i % 4 == 0) and "Green" or "Orange", Range = 22, Brightness = 1.15, Lite = true })
			lm.Name = "RingLamp"
			lightCount += 1
			lampTop[i] = U.Polar(c, 85.6, a, 11.2)
		end
	end
	local bunting = K.Model(lampsM, "RingBunting")
	for i = 1, 16 do
		local j = i % 16 + 1
		local mid = i / 16 * PI * 2
		if lampTop[i] and lampTop[j] and not nearSpoke(mid, 13, 86) then
			U.Pennants(bunting, lampTop[i], lampTop[j], { Sag = .07, Spacing = 2.6, Size = 1.2, Segs = 5,
				Colors = (i % 2 == 0) and { P.Black, P.White } or { U.GLOW.Violet:Lerp(P.Ink, .35), P.White } })
		end
	end

	------------------------------------------------------------------------------------------------ spokes
	for name, g in pairs(L.Gates) do
		if name ~= "BlackBellArena" then
			local m = K.Model(spokesM, "Spoke_" .. name)
			local a = spokeA[name]
			local u = V3(math.sin(a), 0, -math.cos(a))
			local n = V3(-u.Z, 0, u.X)
			local marsh = name == "MourningMarsh"
			local endY = marsh and L.Marsh.GroundY or 0
			local function y(t: number): number
				if not marsh or t <= 102 then
					return 0
				end
				return math.max(endY, (t - 102) / 8 * endY)
			end
			local function at(t: number, off: number, dy: number): Vector3
				return V3(c.X, y(t) + dy, c.Z) + u * t + n * off
			end
			-- pale runner (follows the Marsh ramp), paw prints on it
			local pts = { at(rOut + 2, 0, .06), at(102, 0, .06) }
			if marsh then
				table.insert(pts, at(110, 0, .06))
			end
			table.insert(pts, at(116, 0, .06))
			for i = 1, #pts - 1 do
				K.Bar(m, "SpokeRunner", pts[i], pts[i + 1] + (pts[i + 1] - pts[i]).Unit * .3, 11, .1, P.CobbleLight, M.Slate)
			end
			U.PawTrail(m, pts, 5.5, { Size = 1.4, Gait = .8, Color = P.BoneDark, Height = .07 })
			-- black / white checker threshold under the gate
			local gt = (V3(g.Position.X, 0, g.Position.Z) - V3(c.X, 0, c.Z)).Magnitude
			for k = -4, 3 do
				for row = 0, 1 do
					local p = at(gt - 1 + row * 2, (k + .5) * 2, .08)
					K.Part(m, "GateThreshold", V3(2, .1, 2), K.Look(p, p + u), ((k + row) % 2 == 0) and P.Black or P.White, M.SmoothPlastic)
				end
			end
		end
	end

	------------------------------------------------------------------------------------------------ the Black Bell approach
	local ap = K.Model(root, "ArenaApproach")
	ap:SetAttribute("UyApproach", "BlackBellArena") -- (UyDistrict belongs to the district builder's root model)
	local flat = approachPath(L)
	local total = U.Length(flat)
	-- height profile: up to the crest, then a long spiral descent to the arena landing
	local samples = U.Sample(flat, 3, 0)
	local path = {}
	for _, smp in ipairs(samples) do
		local s = smp.S
		-- (0.04 under the profile: where the deck lies on the island / arena floor its top never z-fights them)
		local h = CREST * smooth(5, 26, s) * (1 - smooth(26, total - 10, s)) - .04
		table.insert(path, { Pos = V3(smp.Pos.X, h, smp.Pos.Z), Dir = smp.Dir, S = s })
	end
	local last = flat[#flat]
	table.insert(path, { Pos = V3(last.X, -.04, last.Z), Dir = V3(0, 0, 1), S = total })
	local top = {}
	for _, pt in ipairs(path) do
		table.insert(top, pt.Pos)
	end
	local deck = U.Deck(ap, "ApproachDeck", top, DECK_W, 2.5, C(64, 58, 74), M.Cobblestone)
	for _, p in ipairs(deck) do
		p:SetAttribute("UyFloor", "BlackBellArena")
	end
	-- keel under the deck, piers into the abyss
	for i = 2, #path - 1, 2 do
		local p = path[i]
		local cf = K.Look(p.Pos, p.Pos + p.Dir)
		if p.Pos.Y > .8 then
			K.Part(ap, "ApproachKeel", V3(12, 3.2, 6.6), cf * CF(0, -4, 0), P.StoneDark, M.Slate)
			Y.GableTri(ap, "ApproachKeelPoint", cf * CF(0, -5.6, 0) * ANG(PI, PI / 2, 0), 6.6, 3.5, 10, P.StoneDark, M.Slate)
		end
	end
	for _, s in ipairs({ 24, 52, 80, 108 }) do
		local best = path[1]
		for _, p in ipairs(path) do
			if math.abs(p.S - s) < math.abs(best.S - s) then
				best = p
			end
		end
		local base = CF(best.Pos.X, -42, best.Pos.Z) * ANG(0, math.atan2(best.Dir.X, best.Dir.Z), 0)
		U.Crooked(ap, "ApproachPier", base, V3(6, best.Pos.Y - 2.5 + 42, 5), 4, rng, { Color = P.Stone, Shade = P.StoneDark, Taper = -.03, Lean = .015,
			Solid = true })
	end
	-- crooked parapets alternating bone-white and ink stone; side colliders; lamps on the outer side of the curl
	local half = DECK_W / 2
	local par = 0
	for i = 1, #path - 1 do
		local p0, p1 = path[i], path[i + 1]
		local right0 = V3(-p0.Dir.Z, 0, p0.Dir.X)
		local right1 = V3(-p1.Dir.Z, 0, p1.Dir.X)
		for _, sx in ipairs({ -1, 1 }) do
			local a = p0.Pos + right0 * sx * (half - .5)
			local b = p1.Pos + right1 * sx * (half - .5)
			if p0.S > 7 and p1.S < total - 4 then
				par += 1
				local h = 1.5 + (par % 3) * .15
				local blk = K.Bar(ap, "ApproachParapet", a + V3(0, h / 2, 0), b + V3(0, h / 2, 0) + (b - a).Unit * .25, 1.1, h,
					(i % 2 == 0) and P.Bone:Lerp(P.StoneLight, .35) or P.Black, M.Slate, { Solid = true })
				blk.CFrame *= ANG(0, 0, rng:NextNumber(-.04, .04))
			end
		end
	end
	for i = 1, #path - 3, 3 do
		local p0, p1 = path[i], path[math.min(#path, i + 3)]
		local r0 = V3(-p0.Dir.Z, 0, p0.Dir.X)
		local r1 = V3(-p1.Dir.Z, 0, p1.Dir.X)
		for _, sx in ipairs({ -1, 1 }) do
			local a = p0.Pos + r0 * sx * (half + .1)
			local b = p1.Pos + r1 * sx * (half + .1)
			U.Collider(ap, a, b, math.min(a.Y, b.Y) - 1, math.max(a.Y, b.Y) + COLLIDE_H)
		end
	end
	-- pale cross bands every few samples + a paw trail down the middle
	for i = 3, #path - 2, 3 do
		local p = path[i]
		local nxt = path[i + 1]
		local cf = K.Look(p.Pos, nxt.Pos) * CF(0, .05, 0)
		K.Part(ap, "ApproachBand", V3(DECK_W - 2, .1, 1.6), cf, P.StoneLight, M.Slate)
	end
	local trail = {}
	for _, p in ipairs(path) do
		table.insert(trail, p.Pos + V3(0, .1, 0))
	end
	U.PawTrail(ap, trail, 8, { Size = 1.5, Gait = 1.1, Color = P.BoneDark, Height = 0 })
	-- lamps: on the parapet line at fixed distances, alternating sides
	for k, s in ipairs({ 12, 34, 58, 82, 104, 126 }) do
		local best = path[1]
		for _, p in ipairs(path) do
			if math.abs(p.S - s) < math.abs(best.S - s) then
				best = p
			end
		end
		local sx = (k % 2 == 0) and 1 or -1
		local right = V3(-best.Dir.Z, 0, best.Dir.X)
		local base = best.Pos + right * sx * (half + .9)
		local lm = U.Lamp(ap, U.Facing(base, best.Pos), rng, { Height = 11, Color = (k % 2 == 0) and U.GLOW.Violet or U.GLOW.Candle,
			Kind = (k % 2 == 0) and "Purple" or "Orange", Range = 22, Brightness = 1.2, Lite = true })
		lm.Name = "ApproachLamp"
		-- a corbel under the lamp foot so it stands on the parapet line
		K.Part(ap, "LampCorbel", V3(2.6, 1.2, 2.6), CF(base - V3(0, .6, 0)), P.StoneDark, M.Slate, { Solid = true })
		lightCount += 1
	end
	-- THE CURLED SPIRE: a twisted rock column out of the abyss inside the curl, its top rolling up like a fern
	do
		local m = K.Model(ap, "CurledSpire")
		local from = L.Arena.Approach.From
		local zc = from.Z + 6 + 20 + ((L.Arena.Approach.To.Z - 3 - from.Z - 6) - 40) / 2
		local centre = V3(from.X + 20, 0, zc)
		local topCF = U.Crooked(m, "CurlStem", CF(centre.X, -42, centre.Z), V3(9, 64, 9), 6, rng,
			{ Color = P.RockLight, Shade = P.Rock, Taper = .06, Lean = .03, Twist = .3 })
		-- the curl: shrinking blocks along a log spiral in a vertical plane
		local spin = topCF * ANG(0, PI / 3, 0)
		local prev = spin.Position
		local r0 = 9
		for k = 1, 14 do
			local th = k / 14 * PI * 1.6
			local r = r0 * math.exp(-.35 * th)
			local q = (spin * CF(r0 - math.cos(th) * r, math.sin(th) * r, 0)).Position
			local thick = 5.2 * math.exp(-.3 * th)
			K.Bar(m, "Curl", prev, q, thick, thick, P.RockLight:Lerp(P.Bone, k / 30), M.Slate)
			prev = q
		end
		K.Ball(m, "CurlEye", 1.2, CF(prev), U.GLOW.Green, M.Neon)
		U.Roots(m, (topCF * CF(0, -2, 0)).Position, 16, rng, { Count = 2, Glow = U.GLOW.Green })
	end

	root:SetAttribute("Lights", lightCount)
	if ctx.Note then
		ctx.Note(string.format("Roads: %d parts, %d lamps (lights), approach %.0f studs, crest y %d", K.Count(root), lightCount, total, CREST))
	end
end

return Roads
