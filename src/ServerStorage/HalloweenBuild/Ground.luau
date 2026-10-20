-- THE DEAD YARD — ground + perimeter fence (WP1). Build-time builder: hw/edits/deadyard.luau runs it through tools/sim.luau
-- and the result is saved in the place (Workspace.DOGROTS_District.38_DeadYard.Ground / .Fence).
-- Ground: solid floor slabs (top y 0.2) over the island hole, leaving the pit opening + its 6.5-wide rim-walk ring (Pit.lua
-- builds both, solid, top 0.2 on the ring); dark varied surface layers
-- (each layer kind has ONE colour + ONE height, so overlapping patches of a kind merge without z-fighting), puddles, dead
-- grass tufts, roots, rocks, faint purple cracks radiating from the pit, stone paths (cauldron walk, pit walk, crypt walk,
-- side tracks to the graveyard / ore field) and FogPoint attachments.
-- Fence: wrought-iron sections between stone piers on every Layout.FenceRuns line (the west run leaves room for the gate
-- wings built by Gate.lua), skull / stone-ball finials, CrowPerch attachments on the pier caps and an invisible 40-tall
-- collider wall along every run (players jump ~7.2 studs; tall props next to the fence must not reach its top).
-- Base-map cliff blocks poking up through the yard floor (the SE-corner WeatheredBasalt, top 1.5) are hidden with
-- K.Hide (World.Disable restores them); their part outside the yard is rebuilt so the island edge looks unchanged.
-- Names avoid the MapArtDirection keywords (soil, trunk, leaves, lawn, turf, apron, ...), see note 08 §8.
local K = require(script.Parent.Kit)
local P = K.Palette
local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local M = Enum.Material

local Ground = {}

-- deterministic RNG with the Random API subset the Kit helpers use (Lune's roblox lib has no Random)
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

local FLOOR = C(54, 47, 60)
local IRON = C(38, 38, 46)
local PIER = C(84, 80, 94)
local PIER_DARK = C(62, 58, 72)

-- gate wings (built by Gate.lua) occupy the west fence line between these z values (opening ± 17.3)
local WING = 17.3

function Ground.Build(ctx)
	local L = ctx.Layout
	local rng = Rng(1031)
	local ground = K.Model(ctx.Root, "Ground")
	local fence = K.Model(ctx.Root, "Fence")
	local layers = K.Model(ground, "Surface")
	local paths = K.Model(ground, "Paths")
	local detail = K.Model(ground, "Detail")

	local rim = L.Pit.Rim
	local ZX0, ZX1, ZZ0, ZZ1 = 33, 210, 531, 745.3
	local FY = L.FloorY

	------------------------------------------------------------------------------------------------ floor slabs
	local slabs = {}
	local function slab(x0, x1, z0, z1)
		local s = K.Part(ground, "YardFloor", V(x1 - x0, 2, z1 - z0), CF((x0 + x1) / 2, FY - 1, (z0 + z1) / 2), FLOOR, M.Ground, { Solid = true })
		table.insert(slabs, { part = s, x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
		return s
	end
	-- the Pit builder owns the opening + its 6.5-wide rim-walk ring (x 91.5..164.5, z 635.5..708.5)
	local RW = 6.5
	slab(ZX0, ZX1, ZZ0, rim.Z0 - RW)
	slab(ZX0, ZX1, rim.Z1 + RW, ZZ1)
	slab(ZX0, rim.X0 - RW, rim.Z0 - RW, rim.Z1 + RW)
	slab(rim.X1 + RW, ZX1, rim.Z0 - RW, rim.Z1 + RW)
	local function slabAt(x, z)
		for _, s in slabs do
			if x >= s.x0 and x <= s.x1 and z >= s.z0 and z <= s.z1 then
				return s.part
			end
		end
		return nil
	end
	-- base-map cliff blocks poking up through the yard floor (01_IslandAndStreets.LayeredCliffs: the SE-corner
	-- WeatheredBasalt rises to y 1.5 over x 199..209, z 726..750): hidden (K.Hide remembers them for World.Disable),
	-- and rebuilt in the same rock everywhere but above the floor slab: its part beyond the yard edge in full, and under
	-- the yard up to the slab bottom (no cavity under the floor, the east cliff face looks unchanged)
	local island = ctx.District and ctx.District:FindFirstChild("01_IslandAndStreets")
	local cliffs = island and island:FindFirstChild("LayeredCliffs")
	for _, part in ipairs(cliffs and cliffs:GetChildren() or {}) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, s = part.CFrame, part.Size
			local function ext(axis: string): number
				return math.abs(cf.XVector[axis]) * s.X / 2 + math.abs(cf.YVector[axis]) * s.Y / 2 + math.abs(cf.ZVector[axis]) * s.Z / 2
			end
			local p = cf.Position
			local ex, ey, ez = ext("X"), ext("Y"), ext("Z")
			local x0, x1, z0, z1, top, bottom = p.X - ex, p.X + ex, p.Z - ez, p.Z + ez, p.Y + ey, p.Y - ey
			if top > FY + .05 and x0 < ZX1 and x1 > ZX0 and z0 < ZZ1 and z1 > ZZ0 then
				K.Hide(part)
				local function edge(cx0, cx1, cz0, cz1, cy1)
					cy1 = cy1 or top
					if cx1 - cx0 > .05 and cz1 - cz0 > .05 and cy1 - bottom > .05 then
						K.Part(ground, "IslandEdgeRock", V(cx1 - cx0, cy1 - bottom, cz1 - cz0), CF((cx0 + cx1) / 2, (cy1 + bottom) / 2, (cz0 + cz1) / 2),
							part.Color, part.Material, { Solid = true })
					end
				end
				local ix0, ix1 = math.max(x0, ZX0), math.min(x1, ZX1)
				local iz0, iz1 = math.max(z0, ZZ0), math.min(z1, ZZ1)
				edge(x0, ZX0, z0, z1) -- west of the yard
				edge(ZX1, x1, z0, z1) -- east
				edge(ix0, ix1, z0, ZZ0) -- north
				edge(ix0, ix1, ZZ1, z1) -- south
				edge(ix0, ix1, iz0, iz1, FY - 2) -- under the yard floor slab (slab bottom FY - 2)
				if ctx.Note then
					ctx.Note(string.format("Ground: hid %s (top %.1f) poking through the yard floor", part:GetFullName(), top))
				end
			end
		end
	end
	-- attachment on the slab under a ground point
	local function groundAttach(name, x, z, h, attrs)
		local s = slabAt(x, z)
		if not s then
			return nil
		end
		return K.Attach(s, name, CF(V(x, FY + (h or 0), z) - s.CFrame.Position), attrs)
	end

	------------------------------------------------------------------------------------------------ keep-out areas
	local cz = L.Cauldron.Center
	local function inRect(x, z, r, m)
		m = m or 0
		return x >= r[1] - m and x <= r[2] + m and z >= r[3] - m and z <= r[4] + m
	end
	local PIT_AREA = { rim.X0 - 6.5, rim.X1 + 6.5, rim.Z0 - 6.5, rim.Z1 + 6.5 } -- opening + rim walk (Pit.lua)
	local HOUSES = { 49, 205, 542.5, 557.5 }
	local LANE = { L.Lane.X0, L.Lane.X1, L.Lane.Z0, L.Lane.Z1 }
	local function blocked(x, z, m)
		m = m or 0
		if inRect(x, z, PIT_AREA, m) or inRect(x, z, HOUSES, m) or inRect(x, z, LANE, m) then
			return true
		end
		local dx, dz = x - cz.X, z - cz.Z
		if math.sqrt(dx * dx + dz * dz) < L.Cauldron.PlazaRadius + 0.5 + m then
			return true
		end
		return x < ZX0 + 1.2 or x > 208.6 or z < ZZ0 + 1.6 or z > ZZ1 - 1.6
	end

	------------------------------------------------------------------------------------------------ surface layers
	-- one colour / material / height per kind: overlapping patches of a kind merge into organic blobs (no z-fight)
	local KIND = {
		Mud = { C(41, 34, 36), M.Mud, FY + .03 },
		Dust = { C(72, 62, 68), M.Ground, FY + .05 },
		Grass = { C(74, 78, 50), M.Grass, FY + .07 },
		Moss = { C(48, 66, 48), M.Grass, FY + .09 },
		Rock = { C(76, 74, 88), M.Slate, FY + .11 },
		Ash = { C(34, 30, 40), M.Ground, FY + .13 },
	}
	-- flat ellipses (sphere mesh) read as natural blotches; a blob = 1..3 overlapping ellipses of one kind
	local function patch(kind, x, z, w, d, rot)
		local k = KIND[kind]
		return K.Ellipsoid(layers, kind .. "Patch", V(w, .1, d), CF(x, k[3] - .05, z) * ANG(0, rot, 0), k[1], k[2])
	end
	local function blob(kind, x, z, size)
		local n = rng:NextInteger(1, 3)
		for i = 1, n do
			local ox, oz = i == 1 and 0 or rng:NextNumber(-size * .4, size * .4), i == 1 and 0 or rng:NextNumber(-size * .4, size * .4)
			local px, pz = x + ox, z + oz
			if not blocked(px, pz, size * .25) then
				patch(kind, px, pz, size * rng:NextNumber(.7, 1.15), size * rng:NextNumber(.4, .75), rng:NextNumber(0, math.pi))
			end
		end
	end
	local REGIONS = {
		-- x0, x1, z0, z1, blobs, kinds (weighted list)
		{ 38, 64, 584, 596, 4, { "Mud", "Mud", "Dust" } }, -- gate court (south of the lane)
		{ 37, 49, 556, 567, 2, { "Mud", "Dust" } }, -- gate court (north of the lane)
		{ 92, 166, 584, 636, 18, { "Dust", "Grass", "Mud", "Rock", "Grass", "Ash", "Dust" } }, -- cauldron field
		{ 38, 94, 592, 742, 18, { "Grass", "Moss", "Grass", "Dust", "Mud", "Dust" } }, -- graveyard ground
		{ 160, 207, 584, 742, 16, { "Rock", "Dust", "Ash", "Rock", "Mud", "Dust" } }, -- ore field (rocky, scorched)
		{ 92, 166, 709, 742, 7, { "Grass", "Moss", "Dust" } }, -- crypt strip
		{ 36, 207, 533, 542, 5, { "Grass", "Dust" } }, -- behind the houses
		{ 38, 206, 558, 567, 6, { "Dust", "Mud", "Grass" } }, -- porches strip
	}
	for _, r in REGIONS do
		for _ = 1, r[5] do
			local x, z = rng:NextNumber(r[1], r[2]), rng:NextNumber(r[3], r[4])
			if not blocked(x, z) then
				-- mostly mid-size blotches, a few big low-contrast washes
				local big = rng:NextNumber() < .25
				blob(big and "Dust" or r[6][rng:NextInteger(1, #r[6])], x, z, big and rng:NextNumber(14, 22) or rng:NextNumber(5, 11))
			end
		end
	end

	------------------------------------------------------------------------------------------------ puddles
	local PUDDLE = C(30, 28, 62)
	local function puddle(x, z, s)
		patch("Mud", x, z, s * 2.1, s * 1.5, rng:NextNumber(0, math.pi))
		local n = 2
		for i = 1, n do
			local ox, oz = i == 1 and 0 or rng:NextNumber(-s * .35, s * .35), i == 1 and 0 or rng:NextNumber(-s * .3, s * .3)
			K.Ellipsoid(detail, "Puddle", V(s * rng:NextNumber(.8, 1.2), .08, s * rng:NextNumber(.55, .85)),
				CF(x + ox, FY + .145, z + oz) * ANG(0, rng:NextNumber(0, math.pi), 0), PUDDLE, M.Glass, { Reflectance = .22, Transparency = .12 })
		end
	end
	for _, p in { { 42, 590, 3.2 }, { 47, 562, 2.6 }, { 104, 606, 3 }, { 151, 618, 2.8 }, { 112, 632, 2.4 }, { 166, 640, 3.4 },
		{ 88, 702, 2.6 }, { 170, 712, 3 }, { 118, 714, 2.4 }, { 186, 590, 2.6 }, { 62, 744 - 6, 2.4 }, { 140, 588, 2.2 } } do
		if not blocked(p[1], p[2], p[3] * .6) then
			puddle(p[1], p[2], p[3])
		end
	end

	------------------------------------------------------------------------------------------------ paths
	-- formal flagstone walk: solid bed (top 0.4) + running-bond slabs (non-solid, tops 0.44/0.47 checkerboard)
	local BED = C(46, 42, 52)
	local function flagWalk(name, x0, x1, z0, z1, rowLen, cols, curbs)
		local alongZ = (z1 - z0) >= (x1 - x0)
		local len = alongZ and (z1 - z0) or (x1 - x0)
		local wid = alongZ and (x1 - x0) or (z1 - z0)
		local m = K.Model(paths, name)
		K.Part(m, "WalkBed", V(x1 - x0, .3, z1 - z0), CF((x0 + x1) / 2, FY + .05, (z0 + z1) / 2), BED, M.Slate, { Solid = true })
		local rows = math.max(1, math.floor(len / rowLen + .5))
		local rl = len / rows
		for r = 1, rows do
			local nc = cols + (r % 2 == 0 and 1 or 0)
			local cw = (wid - (curbs and 1.4 or .4)) / nc
			local stagger = r % 2 == 0 and 0 or 0
			for c = 1, nc do
				local u = (r - .5) * rl
				local v = -wid / 2 + (curbs and .7 or .2) + (c - .5) * cw + stagger
				local w, d = cw - rng:NextNumber(.18, .32), rl - rng:NextNumber(.18, .32)
				local top = ((r + c) % 2 == 0) and .44 or .47
				local col = P.StoneDark:Lerp(P.Stone, rng:NextNumber(0, .55)):Lerp(C(80, 70, 96), rng:NextNumber(0, .25))
				local pos = alongZ and V((x0 + x1) / 2 + v, FY + top - .1, z0 + u) or V(x0 + u, FY + top - .1, (z0 + z1) / 2 + v)
				local size = alongZ and V(w, .2, d) or V(d, .2, w)
				if rng:NextNumber() < .12 and w > 1.6 then
					-- cracked slab: two halves with a hairline gap
					local half = alongZ and V(w / 2 - .06, .2, d) or V(d, .2, w / 2 - .06)
					local off = alongZ and V(w / 4, 0, 0) or V(0, 0, w / 4)
					K.Part(m, "WalkSlab", half, CF(pos - off) * ANG(0, rng:NextNumber(-.05, .05), 0), col, M.Slate)
					K.Part(m, "WalkSlab", half, CF(pos + off - V(0, .03, 0)) * ANG(0, rng:NextNumber(-.05, .05), 0), col:Lerp(P.Ink, .15), M.Slate)
				else
					K.Part(m, "WalkSlab", size, CF(pos) * ANG(0, rng:NextNumber(-.04, .04), 0), col, M.Slate)
				end
			end
		end
		if curbs then
			for _, side in { -1, 1 } do
				local segs = math.max(1, math.floor(len / 4))
				for s = 1, segs do
					local u0, u1 = (s - 1) * len / segs, s * len / segs
					local v = side * (wid / 2 - .33)
					local a = alongZ and V((x0 + x1) / 2 + v, FY + .3, z0 + u0 + .05) or V(x0 + u0 + .05, FY + .3, (z0 + z1) / 2 + v)
					local b = alongZ and V((x0 + x1) / 2 + v, FY + .3, z0 + u1 - .05) or V(x0 + u1 - .05, FY + .3, (z0 + z1) / 2 + v)
					K.Bar(m, "WalkCurb", a, b, .7, .42, PIER_DARK:Lerp(P.Stone, rng:NextNumber(0, .3)), M.Cobblestone)
				end
			end
		end
		return m
	end
	-- lane -> cauldron plaza (Layout.Cauldron.Walk), slightly under the plaza disc
	local w = L.Cauldron.Walk
	flagWalk("CauldronWalk", w.X0, w.X1, w.Z0, w.Z1 + 2.2, 2.7, 3, true)
	-- plaza -> pit north rim walk
	flagWalk("PitWalk", 124, 132, cz.Z + L.Cauldron.PlazaRadius - 1.4, rim.Z0 - 6, 2.6, 2, true)
	-- pit south rim walk -> grand crypt
	flagWalk("CryptWalk", 124, 132, rim.Z1 + 6, 721, 2.6, 2, true)

	-- side tracks: trampled dirt strip + stepping stones (non-solid, walk on the floor)
	local function track(name, pts, width, stones)
		local m = K.Model(paths, name)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local A, B = V(a[1], 0, a[2]), V(b[1], 0, b[2])
			local len = (B - A).Magnitude
			local dir = (B - A).Unit
			local side = dir:Cross(V(0, 1, 0)).Unit
			local yaw = math.atan2(-dir.X, -dir.Z)
			local n = math.max(1, math.floor(len / 3.2 + .5))
			for s = 1, n do
				local p = A + dir * ((s - .5) * len / n)
				-- worn trail: soft ellipse of trampled ash
				K.Ellipsoid(m, "TrailWear", V(width * rng:NextNumber(.9, 1.2), .1, len / n * 1.5),
					CF(p.X + side.X * rng:NextNumber(-.4, .4), KIND.Ash[3] - .05, p.Z + side.Z * rng:NextNumber(-.4, .4)) * ANG(0, yaw + rng:NextNumber(-.15, .15), 0),
					KIND.Ash[1], KIND.Ash[2])
				if rng:NextNumber() < stones then
					local q = p + side * rng:NextNumber(-width * .22, width * .22)
					local sz = rng:NextNumber(1.3, 2)
					K.Part(m, "StepStone", V(sz, .2, sz * rng:NextNumber(.65, .95)), CF(q.X, FY + .12, q.Z) * ANG(0, rng:NextNumber(0, math.pi), 0),
						P.StoneDark:Lerp(P.Stone, rng:NextNumber(0, .5)), M.Slate)
				end
			end
		end
		return m
	end
	track("TrackGraveyard", { { cz.X - 14, cz.Z + 1 }, { 105, 614 }, { 95, 617 } }, 3.6, .8)
	track("TrackOreField", { { cz.X + 14, cz.Z - 1 }, { 151, 609 }, { 161, 606 } }, 3.6, .8)
	track("TrackGraveGate", { { 59, L.Lane.Z1 }, { 59, 592 } }, 4.2, .9)
	track("TrackOreGate", { { 176, L.Lane.Z1 }, { 178, 591 } }, 4.2, .9)
	track("TrackGateCourt", { { 40, 583 }, { 44, 589 } }, 3.4, .6)

	------------------------------------------------------------------------------------------------ cracks (faint purple glow)
	local CRACK = C(92, 50, 150)
	local function crack(x, z, ang, len, width)
		local pos = V(x, FY + .16, z)
		local segs = rng:NextInteger(3, 5)
		local wd = width
		for i = 1, segs do
			ang += rng:NextNumber(-.55, .55)
			local step = len / segs * rng:NextNumber(.7, 1.3)
			local nxt = pos + V(math.cos(ang), 0, math.sin(ang)) * step
			if blocked(nxt.X, nxt.Z) and not inRect(nxt.X, nxt.Z, PIT_AREA) then
				break
			end
			K.Bar(detail, "GlowCrack", pos, nxt, wd, .06, CRACK, M.Neon, { Transparency = .25 })
			K.Bar(detail, "CrackEdge", pos + V(0, -.02, 0), nxt + V(0, -.02, 0), wd + .3, .06, C(24, 18, 30), M.Ground)
			if i == 2 and rng:NextNumber() < .7 then
				local b = ang + (rng:NextNumber() < .5 and -1 or 1) * rng:NextNumber(.6, 1.1)
				local bn = nxt + V(math.cos(b), 0, math.sin(b)) * step * .7
				if not blocked(bn.X, bn.Z) then
					K.Bar(detail, "GlowCrack", nxt, bn, wd * .6, .06, CRACK, M.Neon, { Transparency = .35 })
				end
			end
			pos = nxt
			wd = math.max(.08, wd * .78)
		end
	end
	local pc = V((rim.X0 + rim.X1) / 2, 0, (rim.Z0 + rim.Z1) / 2)
	for _, a in { 38, 128, 146, 222, 306, 324 } do
		local r = math.rad(a)
		local d = 30 / math.max(math.abs(math.cos(r)), math.abs(math.sin(r))) + 6.6
		crack(pc.X + math.cos(r) * d, pc.Z + math.sin(r) * d, r, rng:NextNumber(10, 16), .32)
	end

	------------------------------------------------------------------------------------------------ dead grass tufts
	local function tuft(x, z, s)
		local n = 3
		local base = rng:NextNumber(0, math.pi * 2)
		for i = 1, n do
			local h = s * rng:NextNumber(.7, 1.35)
			local col = C(124, 112, 64):Lerp(C(78, 82, 50), rng:NextNumber(0, 1))
			local a = base + i * (math.pi * 2 / n) + rng:NextNumber(-.4, .4)
			K.Wedge(detail, "GrassBlade", V(.07, h, h * .42),
				CF(x + math.cos(a) * .18, FY + h / 2 - .05, z + math.sin(a) * .18) * ANG(0, a, 0) * ANG(rng:NextNumber(-.3, -.1), 0, rng:NextNumber(-.2, .2)),
				col, M.Grass)
		end
	end
	local nt = 0
	local tuftAreas = {
		{ 92, 166, 584, 636, 14 }, { 38, 94, 592, 742, 8 }, { 160, 207, 584, 742, 7 }, { 92, 166, 709, 742, 6 },
		{ 36, 207, 533, 542, 2 }, { 37, 60, 556, 596, 4 },
	}
	for _, t in tuftAreas do
		for _ = 1, t[5] do
			local x, z = rng:NextNumber(t[1], t[2]), rng:NextNumber(t[3], t[4])
			if not blocked(x, z, .5) then
				tuft(x, z, rng:NextNumber(.8, 1.5))
				nt += 1
			end
		end
	end
	-- tufts hugging the pit rim walk and the plaza edge (where players look)
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2 + rng:NextNumber(-.15, .15)
		local r = L.Cauldron.PlazaRadius + rng:NextNumber(.9, 2.2)
		local x, z = cz.X + math.cos(a) * r, cz.Z + math.sin(a) * r
		if not blocked(x, z) and not inRect(x, z, { w.X0 - 1, w.X1 + 1, w.Z0, w.Z1 + 3 }) and not inRect(x, z, { 123, 133, 620, 640 }) then
			tuft(x, z, rng:NextNumber(.9, 1.4))
		end
	end

	------------------------------------------------------------------------------------------------ rocks + roots
	local function rock(x, z, s)
		local col = C(58, 56, 68):Lerp(C(92, 90, 104), rng:NextNumber(0, 1))
		if rng:NextNumber() < .5 then
			K.Part(detail, "Rock", V(s, s * rng:NextNumber(.45, .7), s * rng:NextNumber(.6, 1)),
				CF(x, FY + s * .12, z) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, math.pi), rng:NextNumber(-.3, .3)), col, M.Slate)
		else
			K.Ellipsoid(detail, "Rock", V(s, s * .6, s * .8), CF(x, FY + s * .1, z) * ANG(0, rng:NextNumber(0, math.pi), 0), col, M.Slate)
		end
	end
	for _, t in { { 92, 166, 584, 636, 7 }, { 160, 207, 584, 742, 9 }, { 92, 166, 709, 742, 4 }, { 38, 94, 592, 742, 3 } } do
		for _ = 1, t[5] do
			local x, z = rng:NextNumber(t[1], t[2]), rng:NextNumber(t[3], t[4])
			if not blocked(x, z, 1) then
				rock(x, z, rng:NextNumber(.6, 1.6))
			end
		end
	end
	local ROOT = C(60, 46, 42)
	local function rootCoil(x, z, ang, len)
		local a = V(x, FY - .15, z)
		local segs = 3
		local prev = a
		for i = 1, segs do
			ang += rng:NextNumber(-.5, .5)
			local h = (i == segs) and -.25 or rng:NextNumber(.15, .35)
			local nxt = V(prev.X + math.cos(ang) * len / segs, FY + h, prev.Z + math.sin(ang) * len / segs)
			K.Rod(detail, "RootCoil", prev, nxt, .38 - i * .07, ROOT:Lerp(C(40, 32, 30), i * .15), M.Wood)
			prev = nxt
		end
	end

	------------------------------------------------------------------------------------------------ FENCE
	local G = L.Gate.Opening
	local piers = {}
	local pierCount = 0
	local function pier(pos, face)
		for _, q in piers do
			if (q - pos).Magnitude < .5 then
				return
			end
		end
		table.insert(piers, pos)
		pierCount += 1
		local i = pierCount
		local m = K.Model(fence, "FencePier")
		local x, z = pos.X, pos.Z
		K.Part(m, "PierFoot", V(2.9, 1.1, 2.9), CF(x, FY + .55, z), PIER_DARK, M.Cobblestone, { Solid = true })
		K.Part(m, "PierShaft", V(2.2, 6.9, 2.2), CF(x, FY + 1.1 + 3.45, z), PIER:Lerp(PIER_DARK, rng:NextNumber(0, .4)), M.Cobblestone, { Solid = true })
		local cap = K.Part(m, "PierCap", V(2.8, .55, 2.8), CF(x, FY + 8.28, z), C(70, 68, 82), M.Slate, { Solid = true })
		local top = FY + 8.55
		local kind = i % 3
		if kind == 0 then
			-- little dog skull finial
			-- little dog skull finial looking out of the yard
			local o = CF(x, top, z) * ANG(0, face, 0)
			K.Ellipsoid(m, "SkullFinial", V(1.2, 1.0, 1.15), o * CF(0, .55, .1), P.Bone, M.SmoothPlastic)
			K.Part(m, "SkullSnout", V(.66, .46, .8), o * CF(0, .36, -.55), P.BoneDark, M.SmoothPlastic)
			K.Part(m, "SkullNose", V(.3, .18, .1), o * CF(0, .5, -.97), P.Ink, M.SmoothPlastic)
			for _, sx in { -.27, .27 } do
				K.Part(m, "SkullEye", V(.26, .24, .12), o * CF(sx, .72, -.45), P.Ink, M.SmoothPlastic)
			end
		elseif kind == 1 then
			K.Part(m, "BallNeck", V(1, .4, 1), CF(x, top + .2, z), PIER_DARK, M.Slate)
			K.Ball(m, "StoneBall", 1.25, CF(x, top + 1.02, z), C(96, 94, 108), M.Slate)
		else
			-- small pumpkin (no face, no light)
			K.Ellipsoid(m, "PierPumpkin", V(1.5, 1.05, 1.5), CF(x, top + .5, z) * ANG(0, rng:NextNumber(0, 3), 0), P.Pumpkin:Lerp(P.PumpkinDark, rng:NextNumber(.1, .45)), M.SmoothPlastic)
			K.CylY(m, "PierPumpkinStem", .45, .2, CF(x, top + 1.15, z) * ANG(.25, 0, .15), P.Stem, M.Wood)
		end
		if rng:NextNumber() < .3 then
			-- moss creeping over one side of the cap
			local s = rng:NextInteger(0, 3) * math.pi / 2
			K.Part(m, "PierMoss", V(2.86, .2, .5), CF(x, FY + 8.14, z) * ANG(0, s, 0) * CFrame.new(0, 0, 1.2), P.Moss, M.Grass)
		end
		K.Attach(cap, "CrowPerch", CF(0, .28, 0))
		if rng:NextNumber() < .25 then
			rootCoil(x + rng:NextNumber(-1.5, 1.5), z + rng:NextNumber(-1.5, 1.5), rng:NextNumber(0, math.pi * 2), rng:NextNumber(3, 5))
		end
	end

	local sections = 0
	local function section(a, b, spacing)
		local len = (b - a).Magnitude
		if len < .5 then
			return
		end
		sections += 1
		local dir = (b - a).Unit
		local m = K.Model(fence, "FenceSection")
		local rust = IRON:Lerp(P.Rust, rng:NextNumber(.05, .3))
		local up = V(0, 1, 0)
		K.Bar(m, "FenceRailLow", a + up * (FY + .88), b + up * (FY + .88), .24, .3, rust, M.CorrodedMetal)
		K.Bar(m, "FenceRailTop", a + up * (FY + 6.15), b + up * (FY + 6.15), .3, .38, rust, M.CorrodedMetal)
		if spacing < 2 then
			K.Bar(m, "FenceRailMid", a + up * (FY + 5.45), b + up * (FY + 5.45), .16, .16, IRON, M.CorrodedMetal)
		end
		local n = math.max(1, math.floor(len / spacing))
		local s = len / n
		for i = 1, n do
			local p = a + dir * ((i - .5) * s)
			local tall = i % 2 == 1
			local h = tall and 7.25 or 6.3
			K.Part(m, "FenceBar", V(.2, h, .2), K.Look(V(p.X, FY + h / 2, p.Z), V(p.X, FY + h / 2, p.Z) + dir), IRON, M.CorrodedMetal)
			if tall then
				K.Part(m, "SpearTip", V(.12, .44, .44), K.Look(V(p.X, FY + h + .18, p.Z), V(p.X, FY + h + .18, p.Z) + dir) * ANG(math.pi / 4, 0, 0),
					IRON:Lerp(C(70, 66, 76), .3), M.CorrodedMetal)
			end
		end
	end

	local function run(A, B, opts)
		local len = (B - A).Magnitude
		local dir = (B - A).Unit
		local n = math.max(1, math.floor(len / 22 + .5))
		local pts = {}
		for i = 0, n do
			table.insert(pts, A + dir * (len * i / n))
		end
		for i, p in pts do
			if (i > 1 or opts.pierA ~= false) and (i < #pts or opts.pierB ~= false) then
				pier(p, opts.face)
			end
		end
		for i = 1, #pts - 1 do
			local a = pts[i] + dir * ((i > 1 or opts.pierA ~= false) and 1.1 or 0)
			local b = pts[i + 1] - dir * ((i + 1 < #pts or opts.pierB ~= false) and 1.1 or 0)
			section(a, b, opts.spacing)
		end
	end
	local x0, x1, z0, z1 = L.Inner.X0, L.Inner.X1, L.Inner.Z0, L.Inner.Z1
	-- west (boulevard side): dense; the gate wings own z (opening.Z0 - WING) .. (opening.Z1 + WING)
	-- face = yaw that turns a finial's -Z toward the outside of the yard
	run(V(x0, 0, z0), V(x0, 0, G.Z0 - WING), { spacing = 1.9, pierB = false, face = math.pi / 2 })
	run(V(x0, 0, G.Z1 + WING), V(x0, 0, z1), { spacing = 1.9, pierA = false, face = math.pi / 2 })
	run(V(x0, 0, z0), V(x1, 0, z0), { spacing = 2.3, face = 0 }) -- -Z (lab side)
	run(V(x1, 0, z0), V(x1, 0, z1), { spacing = 3.0, face = -math.pi / 2 }) -- +X (cliff)
	run(V(x0, 0, z1), V(x1, 0, z1), { spacing = 2.8, face = math.pi }) -- +Z (south cliff)

	-- invisible collider walls along every Layout.FenceRuns segment, COLLIDER tall: well above anything a player can climb
	-- next to a fence (the broken-lab catwalk + back wall reach y 13.7, crypt roofs ~20, the gate pillars ~26) + a jump,
	-- so nobody can step onto a collider top and walk out of the yard (fully transparent: the camera ignores them)
	local COLLIDER = 40
	for i, r in L.FenceRuns do
		local a, b = V(r[1], FY + COLLIDER / 2, r[2]), V(r[3], FY + COLLIDER / 2, r[4])
		local c = K.Bar(fence, "FenceCollider", a, b, 1, COLLIDER, P.Ink, M.SmoothPlastic, { Solid = true, Shadow = false })
		c.Size = c.Size + V(0, 0, 1)
		c.Transparency = 1
		c:SetAttribute("Run", i)
	end

	------------------------------------------------------------------------------------------------ FogPoints
	local FOG = {
		{ 44, 590 }, { 43, 560 }, { 90, 575 }, { 160, 575 }, { 200, 575 },
		{ 59, 600 }, { 77, 600 }, { 59, 632 }, { 77, 652 }, { 59, 662 }, { 77, 684 }, { 59, 702 }, { 77, 716 }, { 44, 740 },
		{ 100, 598 }, { 156, 598 }, { 108, 622 }, { 148, 622 }, { 88.5, 690 }, { 167.5, 690 }, { 110, 714 }, { 146, 714 }, { 128, 738 },
		{ 168, 600 }, { 170, 640 }, { 184, 660 }, { 168, 700 }, { 190, 708 }, { 204, 736 },
		{ 69.5, 537 }, { 115.5, 537 }, { 161.5, 537 }, { 88.5, 650 }, { 167.5, 652 },
	}
	for _, p in FOG do
		groundAttach("FogPoint", p[1], p[2], .4)
	end

	-- roots creeping out from under the fence on the cliff side and around the field
	for _ = 1, 4 do
		rootCoil(rng:NextNumber(150, 206), rng:NextNumber(690, 742), rng:NextNumber(0, math.pi * 2), rng:NextNumber(3, 6))
	end

	if ctx.Note then
		ctx.Note(string.format("Ground: %d parts (%d piers, %d sections, %d tufts), Fence %d parts", K.Count(ground), pierCount, sections, nt, K.Count(fence)))
	end
end

return Ground
