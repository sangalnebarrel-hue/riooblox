-- THE DEAD YARD — THE GRAVEYARD PIT / boss arena (WP1). Build-time builder (hw/edits/deadyard.luau → tools/sim.luau),
-- saved in the place as Workspace.DOGROTS_District.38_DeadYard.Pit. All numbers come from Layout.Pit:
-- opening x 98..158 z 642..702 (rim y 0.2), terrace ring y -4 (6 wide), arena floor y -8 (x 104..152, z 648..696),
-- 4 ramps N/S/E/W (8 wide): upper = stone stairs over an invisible wedge (rim -> terrace, 35°), lower = timber trestle
-- ramp over an invisible wedge (terrace -> floor, 22°).
-- The pit owns the 6.5-wide rim walk around the opening (Ground.lua leaves that ring open) and builds:
--   * solid structure: rim-walk slabs, retaining-wall cores (rim -> floor), terrace blocks, arena floor slab,
--   * abandoned-excavation dressing: stone cladding + timber shoring on the outer walls, plank shoring on the inner walls,
--     a giant dog skull (YardKit.GiantSkull) breaking out of the south wall + a ribcage tunnelling out of it, giant bones in
--     the side walls, hanging roots + chains,
--     a broken scaffold with ladders, old dig-station rails + a toppled cart, rubble, glowing mushrooms,
--   * a low stone balustrade on the rim (gaps at the ramps), 8 lanterns on posts framing the ramps (8 PointLights),
--   * floor: dark cracked stone tiles with faint purple rune circles (flush Neon, nothing on the 48x48 arena floor),
--   * THE GRAVE BELL (boss summon) at Layout.Bell: a gothic stone belfry with a swinging bronze bell (own budget line in
--     tools/hw_test_wp1: <= 260 parts, 2 lights), FogPoint markers (floor + terrace), CrowPerch on the rim.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit) -- the shared giant dog skull
local P = K.Palette
local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local M = Enum.Material

local Pit = {}

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

local STONE = C(84, 80, 96)
local STONE_DARK = C(58, 54, 68)
local STONE_LIGHT = C(112, 108, 124)
local EARTH = C(70, 54, 50)
local TIMBER = C(84, 62, 46)
local TIMBER_DARK = C(58, 42, 34)
local IRON = C(42, 42, 52)
local RUST = C(116, 62, 42)
local BONE = P.Bone
local BONE_DARK = C(204, 190, 158)
local RUNE = C(104, 52, 176)
local FLOOR = C(48, 44, 58)

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

local function bigBone(parent, a: Vector3, b: Vector3, d: number, color: Color3, normal: Vector3?)
	local m = K.Model(parent, "GiantBone")
	K.Rod(m, "BoneShaft", a, b, d, color, M.SmoothPlastic)
	local dir = (b - a).Unit
	local s = dir:Cross(normal or V(0, 1, 0))
	if s.Magnitude < .1 then
		s = dir:Cross(V(1, 0, 0))
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
	K.Part(m, "SkullTeeth", V(.96 * s, .2 * s, .1 * s), at(0, .3, -2.2), BONE, M.SmoothPlastic)
	for _, sx in { -1, 1 } do
		K.Ellipsoid(m, "SkullSocket", V(.66 * s, .58 * s, .34 * s), at(sx * .5, 1.08, -.98), P.Ink, M.SmoothPlastic)
		K.Ball(m, "SkullEye", .3 * s, at(sx * .5, 1.08, -1.1), eye, M.Neon)
		K.Wedge(m, "SkullEar", V(.28 * s, 1.0 * s, .78 * s), at(sx * .78, 2.12, .35) * ANG(0, sx * math.pi / 2, 0), BONE_DARK, M.SmoothPlastic)
		K.Wedge(m, "SkullFang", V(.16 * s, .36 * s, .16 * s), at(sx * .33, .02, -2.08) * ANG(math.pi, 0, 0), BONE, M.SmoothPlastic)
	end
	return m
end

-- yaw that turns local +X toward a horizontal direction
local function yawX(dir: Vector3)
	return ANG(0, math.atan2(-dir.Z, dir.X), 0)
end

function Pit.Build(ctx)
	local L = ctx.Layout
	local rng = Rng(8821)
	local LP = L.Pit
	local R = LP.Rim
	local A = LP.Arena
	local RIM, TY, FY = L.FloorY, LP.TerraceY, LP.FloorY -- 0.2, -4, -8
	local RW = 6.5 -- rim walk width
	local CORE = 2.5 -- retaining wall core thickness (under the rim walk)
	local SHORE = .6 -- inner shoring band (terrace blocks stop SHORE short of the arena edge)
	local CX, CZ = (R.X0 + R.X1) / 2, (R.Z0 + R.Z1) / 2
	local pit = K.Model(ctx.Root, "Pit")
	local struct = K.Model(pit, "Structure")
	local walls = K.Model(pit, "Walls")
	local floorM = K.Model(pit, "ArenaFloor")
	local rimM = K.Model(pit, "Rim")
	local deco = K.Model(pit, "Decor")
	local lights = 0

	local function box(parent, name, x0, x1, y0, y1, z0, z1, col, mat, props)
		return K.Part(parent, name, V(x1 - x0, y1 - y0, z1 - z0), CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), col, mat, props)
	end
	local SOLID = { Solid = true }

	------------------------------------------------------------------------------------------------ solid structure
	-- rim walk ring (top 0.2, like the yard floor)
	local OX0, OX1, OZ0, OZ1 = R.X0 - RW, R.X1 + RW, R.Z0 - RW, R.Z1 + RW
	local IX0, IX1, IZ0, IZ1 = R.X0 - CORE, R.X1 + CORE, R.Z0 - CORE, R.Z1 + CORE
	local RIMCOL = C(66, 62, 76)
	box(struct, "RimWalk", OX0, OX1, RIM - 2, RIM, OZ0, IZ0, RIMCOL, M.Slate, SOLID)
	box(struct, "RimWalk", OX0, OX1, RIM - 2, RIM, IZ1, OZ1, RIMCOL, M.Slate, SOLID)
	box(struct, "RimWalk", OX0, IX0, RIM - 2, RIM, IZ0, IZ1, RIMCOL, M.Slate, SOLID)
	box(struct, "RimWalk", IX1, OX1, RIM - 2, RIM, IZ0, IZ1, RIMCOL, M.Slate, SOLID)
	-- retaining wall cores (rim -> below the floor); their inner faces are the opening edges
	local WCOL = C(62, 58, 72)
	box(struct, "WallCore", IX0, IX1, FY - 2, RIM, IZ0, R.Z0, WCOL, M.Cobblestone, SOLID)
	box(struct, "WallCore", IX0, IX1, FY - 2, RIM, R.Z1, IZ1, WCOL, M.Cobblestone, SOLID)
	box(struct, "WallCore", IX0, R.X0, FY - 2, RIM, R.Z0, R.Z1, WCOL, M.Cobblestone, SOLID)
	box(struct, "WallCore", R.X1, IX1, FY - 2, RIM, R.Z0, R.Z1, WCOL, M.Cobblestone, SOLID)
	-- arena floor slab (under everything inside the opening)
	local floor = box(struct, "ArenaFloor", R.X0, R.X1, FY - 2, FY, R.Z0, R.Z1, FLOOR, M.Slate, SOLID)
	-- terrace ring (earth, top -4), stopping SHORE short of the arena edge (the shoring fills that band)
	local TCOL = EARTH
	box(struct, "Terrace", R.X0, R.X1, FY, TY, R.Z0, A.Z0 - SHORE, TCOL, M.Ground, SOLID)
	box(struct, "Terrace", R.X0, R.X1, FY, TY, A.Z1 + SHORE, R.Z1, TCOL, M.Ground, SOLID)
	box(struct, "Terrace", R.X0, A.X0 - SHORE, FY, TY, A.Z0 - SHORE, A.Z1 + SHORE, TCOL, M.Ground, SOLID)
	box(struct, "Terrace", A.X1 + SHORE, R.X1, FY, TY, A.Z0 - SHORE, A.Z1 + SHORE, TCOL, M.Ground, SOLID)

	------------------------------------------------------------------------------------------------ sides
	-- each side: points along the edge are P(t, o, y) with t along the edge, o = distance into the pit from the opening edge
	local SIDES = {
		{ id = "N", along = "x", fixed = R.Z0, n = V(0, 0, 1), t0 = R.X0, t1 = R.X1, gap = CX },
		{ id = "S", along = "x", fixed = R.Z1, n = V(0, 0, -1), t0 = R.X0, t1 = R.X1, gap = CX },
		{ id = "W", along = "z", fixed = R.X0, n = V(1, 0, 0), t0 = R.Z0, t1 = R.Z1, gap = CZ },
		{ id = "E", along = "z", fixed = R.X1, n = V(-1, 0, 0), t0 = R.Z0, t1 = R.Z1, gap = CZ },
	}
	local function Pt(sd, t, o, y)
		if sd.along == "x" then
			return V(t, y, sd.fixed + sd.n.Z * o)
		end
		return V(sd.fixed + sd.n.X * o, y, t)
	end
	local function tangent(sd)
		return sd.along == "x" and V(1, 0, 0) or V(0, 0, 1)
	end
	-- a box lying along a side: t-range, o-range (into the pit), y-range
	local function sideBox(parent, name, sd, ta, tb, oa, ob, ya, yb, col, mat, props)
		local a, b = Pt(sd, ta, oa, ya), Pt(sd, tb, ob, yb)
		return box(parent, name, math.min(a.X, b.X), math.max(a.X, b.X), ya, yb, math.min(a.Z, b.Z), math.max(a.Z, b.Z), col, mat, props)
	end
	local HALFGAP = 4

	for _, sd in SIDES do
		local runs = { { sd.t0, sd.gap - HALFGAP }, { sd.gap + HALFGAP, sd.t1 } }
		for ri, run in runs do
			-- W/E cladding starts .6 in from the corners (the N/S stones own the corner)
			local inset = sd.along == "z" and .6 or 0
			local ta, tb = run[1] + (ri == 1 and inset or 0), run[2] - (ri == 2 and inset or 0)
			------------------------------------------------ outer wall: two rows of big cladding stones
			for row = 0, 1 do
				local y0 = TY + row * 2.1
				local t = ta + (row == 1 and rng:NextNumber(.5, 2.5) or 0)
				if row == 1 then
					sideBox(walls, "WallStone", sd, ta, t, 0, .45, y0, y0 + 2.05, STONE:Lerp(STONE_DARK, rng:NextNumber(0, .7)), M.Cobblestone)
				end
				while t < tb - .3 do
					local len = math.min(tb - t, rng:NextNumber(4.2, 7.2))
					if tb - (t + len) < 1.2 then
						len = tb - t
					end
					local depth = rng:NextNumber(.35, .6)
					sideBox(walls, "WallStone", sd, t + .07, t + len - .07, 0, depth, y0 + .04, y0 + 2.04 - (row == 1 and .1 or 0),
						STONE:Lerp(STONE_DARK, rng:NextNumber(0, .7)):Lerp(C(90, 76, 70), rng:NextNumber(0, .25)), M.Cobblestone)
					t += len
				end
			end
			------------------------------------------------ timber shoring on the outer wall
			local n = math.max(2, math.floor((tb - ta) / 6.5 + .5))
			for k = 0, n do
				local t = ta + (tb - ta) * k / n
				t = math.clamp(t, ta + .5, tb - .5)
				local base = Pt(sd, t, .95, TY)
				local top = Pt(sd, t + rng:NextNumber(-.3, .3), .75, RIM - .15)
				if rng:NextNumber() < .18 then
					-- broken post: snapped half leaning on the wall
					K.Bar(walls, "ShorePost", base, base:Lerp(top, .55), .75, .75, TIMBER_DARK, M.Wood)
					K.Bar(deco, "ShorePostBroken", Pt(sd, t + .8, 2.2, TY + .35), Pt(sd, t - .6, 1.2, TY + 2.4), .7, .7, TIMBER_DARK, M.Wood)
				else
					K.Bar(walls, "ShorePost", base, top, .75, .75, TIMBER:Lerp(TIMBER_DARK, rng:NextNumber(0, .7)), M.Wood)
				end
			end
			K.Bar(walls, "ShoreWale", Pt(sd, ta + .2, .5, -.75), Pt(sd, tb - .2, .5, -.75), .55, .6, TIMBER_DARK, M.Wood)
			------------------------------------------------ inner wall (terrace edge -> floor): plank shoring
			local ia = math.max(ta, sd.along == "x" and A.X0 or A.Z0)
			local ib = math.min(tb, sd.along == "x" and A.X1 or A.Z1)
			local io = 6 -- arena edge offset from the opening edge
			for _, y in { FY + 1.0, FY + 2.9 } do
				local t = ia
				while t < ib - .5 do
					local len = math.min(ib - t, rng:NextNumber(5, 8))
					if ib - (t + len) < 1.5 then
						len = ib - t
					end
					if rng:NextNumber() > .12 then
						sideBox(walls, "ShorePlank", sd, t + .05, t + len - .05, io - SHORE + .05, io - SHORE + .3, y - .75, y + .75,
							C(96, 72, 54):Lerp(TIMBER_DARK, rng:NextNumber(0, .6)), M.WoodPlanks)
					end
					t += len
				end
			end
			local ni = math.max(2, math.floor((ib - ia) / 5.5 + .5))
			for k = 0, ni do
				local t = math.clamp(ia + (ib - ia) * k / ni, ia + .36, ib - .36)
				sideBox(walls, "ShorePile", sd, t - .3, t + .3, io - SHORE + .3, io - .05, FY, TY + .25, TIMBER_DARK, M.Wood)
			end
			-- timber curb on the terrace edge
			sideBox(walls, "TerraceCurb", sd, ia, ib, io - SHORE - .3, io - .02, TY - .2, TY + .15, TIMBER, M.Wood)
			------------------------------------------------ hanging roots on the outer wall
			for _ = 1, 1 do
				local t = rng:NextNumber(ta + 2, tb - 2)
				local prev = Pt(sd, t, .2, RIM - .1)
				local len = rng:NextNumber(2.4, 3.6)
				for k = 1, 3 do
					local nxt = Pt(sd, t + rng:NextNumber(-.5, .5), .35 + k * .18, RIM - .1 - len * k / 3)
					K.Rod(deco, "HangingRoot", prev, nxt, .26 - k * .05, C(64, 48, 42):Lerp(C(40, 30, 28), k * .2), M.Wood)
					prev = nxt
				end
			end
		end
		------------------------------------------------ balustrade on the rim: parapet + coping per run, posts between
		for ri, run in runs do
			local pa, pb
			if sd.along == "x" then
				pa, pb = (ri == 1) and (sd.t0 - .9) or run[1], (ri == 2) and (sd.t1 + .9) or run[2]
			else
				pa, pb = run[1], run[2]
			end
			sideBox(rimM, "Parapet", sd, pa, pb, -.9, 0, RIM, RIM + 1.05, STONE_DARK, M.Cobblestone, SOLID)
			local ca, cb = pa, pb
			if sd.along == "x" then
				ca, cb = (ri == 1) and (sd.t0 - 1.05) or run[1], (ri == 2) and (sd.t1 + 1.05) or run[2]
			else
				ca, cb = (ri == 1) and (sd.t0 + .12) or run[1], (ri == 2) and (sd.t1 - .12) or run[2]
			end
			sideBox(rimM, "ParapetCoping", sd, ca, cb, -1.05, .12, RIM + 1.05, RIM + 1.35, STONE_LIGHT, M.Slate, SOLID)
			local ta, tb = run[1], run[2]
			local np = math.max(2, math.floor((tb - ta) / 6.4 + .5))
			-- posts at k = 1..np (run 1: corner -> gap) or 0..np-1 (run 2: gap -> corner); corners get their own big post
			for k = (ri == 1 and 1 or 0), (ri == 1 and np or np - 1) do
				local t = ta + (tb - ta) * k / np
				local c = Pt(sd, math.clamp(t, ta + .64, tb - .64), -.45, RIM)
				local w, hgt = 1.4, 1.95
				local post = box(rimM, "BalustradePost", c.X - w / 2, c.X + w / 2, RIM, RIM + hgt, c.Z - w / 2, c.Z + w / 2, STONE, M.Cobblestone, SOLID)
				box(rimM, "BalustradeCap", c.X - w / 2 - .18, c.X + w / 2 + .18, RIM + hgt, RIM + hgt + .3, c.Z - w / 2 - .18, c.Z + w / 2 + .18, STONE_LIGHT, M.Slate)
				if k % 2 == 1 then
					K.Ball(rimM, "PostBall", .95, CF(c.X, RIM + hgt + .3 + .4, c.Z), C(96, 92, 108), M.Slate)
					K.Attach(post, "CrowPerch", CF(0, hgt / 2 + .8, 0))
				end
			end
		end
	end
	-- big corner posts with pumpkins
	for _, c in { V(R.X0 - .45, 0, R.Z0 - .45), V(R.X1 + .45, 0, R.Z0 - .45), V(R.X0 - .45, 0, R.Z1 + .45), V(R.X1 + .45, 0, R.Z1 + .45) } do
		local w, hgt = 2.0, 2.6
		local post = box(rimM, "BalustradePost", c.X - w / 2, c.X + w / 2, RIM, RIM + hgt, c.Z - w / 2, c.Z + w / 2, STONE, M.Cobblestone, SOLID)
		box(rimM, "BalustradeCap", c.X - w / 2 - .2, c.X + w / 2 + .2, RIM + hgt, RIM + hgt + .32, c.Z - w / 2 - .2, c.Z + w / 2 + .2, STONE_LIGHT, M.Slate)
		K.Ellipsoid(rimM, "PostPumpkin", V(1.6, 1.1, 1.6), CF(c.X, RIM + hgt + .32 + .52, c.Z) * ANG(0, rng:NextNumber(0, 3), 0), P.Pumpkin:Lerp(P.PumpkinDark, .3), M.SmoothPlastic)
		K.CylY(rimM, "PostPumpkinStem", .4, .2, CF(c.X, RIM + hgt + 1.55, c.Z) * ANG(.2, 0, .2), P.Stem, M.Wood)
		K.Attach(post, "CrowPerch", CF(.6, hgt / 2 + .35, -.6))
	end
	-- timber piles in the four inner corners (the terrace blocks stop SHORE short of the arena edge on both sides)
	for _, c in { V(A.X0, 0, A.Z0), V(A.X1, 0, A.Z0), V(A.X0, 0, A.Z1), V(A.X1, 0, A.Z1) } do
		local sx, sz = (c.X < CX) and -1 or 1, (c.Z < CZ) and -1 or 1
		box(walls, "ShoreCornerPile", math.min(c.X, c.X + sx * SHORE), math.max(c.X, c.X + sx * SHORE), FY, TY + .25,
			math.min(c.Z, c.Z + sz * SHORE), math.max(c.Z, c.Z + sz * SHORE), TIMBER_DARK, M.Wood, SOLID)
	end

	------------------------------------------------------------------------------------------------ ramps
	local ramps = K.Model(pit, "Ramps")
	local LANTERN_KIND = { N = { C(255, 140, 40), "Orange" }, S = { C(176, 92, 240), "Purple" }, W = { C(120, 255, 110), "Green" }, E = { C(176, 92, 240), "Purple" } }
	for _, rp in LP.Ramps do
		local top, mid, bot = rp.Top, rp.Mid, rp.Bottom
		local dir = V(mid.X - top.X, 0, mid.Z - top.Z).Unit
		local side = V(-dir.Z, 0, dir.X)
		local W = 8
		local m = K.Model(ramps, "Ramp" .. rp.Id)
		-- upper: invisible wedge collider (rim -> terrace) + stone stairs + cheek walls
		local run1 = (V(mid.X, 0, mid.Z) - V(top.X, 0, top.Z)).Magnitude
		local c1 = V((top.X + mid.X) / 2, (RIM + TY) / 2, (top.Z + mid.Z) / 2)
		K.Wedge(m, "RampCollider", V(W, RIM - TY, run1), K.Look(c1, c1 + dir), STONE, M.Slate, { Solid = true, Transparency = 1, Shadow = false })
		local steps = 6
		for i = 0, steps - 1 do
			local s0, s1 = run1 * i / steps, run1 * (i + 1) / steps
			local ytop = RIM - (RIM - TY) * (i + .55) / steps
			local p = V(top.X, 0, top.Z) + dir * ((s0 + s1) / 2)
			local hgt = ytop - TY
			K.Part(m, "RampStep", V(W - .6, hgt, s1 - s0 + .02), K.Look(V(p.X, TY + hgt / 2, p.Z), V(p.X, TY + hgt / 2, p.Z) + dir),
				STONE_LIGHT:Lerp(STONE, rng:NextNumber(0, .6)), M.Slate)
		end
		for _, sgn in { -1, 1 } do
			local cc = c1 + side * sgn * (W / 2 - .2) + V(0, .25, 0)
			K.Wedge(m, "RampCheek", V(.5, RIM - TY + .5, run1), K.Look(cc, cc + dir), STONE_DARK, M.Cobblestone)
		end
		-- lower: invisible wedge collider (terrace -> floor) + timber trestle ramp
		local run2 = (V(bot.X, 0, bot.Z) - V(mid.X, 0, mid.Z)).Magnitude
		local c2 = V((mid.X + bot.X) / 2, (TY + FY) / 2, (mid.Z + bot.Z) / 2)
		K.Wedge(m, "RampCollider", V(W, TY - FY, run2), K.Look(c2, c2 + dir), TIMBER, M.Wood, { Solid = true, Transparency = 1, Shadow = false })
		-- fill under the end of the stairs (the terrace stops SHORE short of the arena edge)
		local f0 = V(mid.X, 0, mid.Z) - dir * SHORE / 2
		K.Part(m, "RampFill", V(W, TY - FY, SHORE + .02), K.Look(V(f0.X, (TY + FY) / 2, f0.Z), V(f0.X, (TY + FY) / 2, f0.Z) + dir), EARTH, M.Ground, { Solid = true })
		local slopeA = V(mid.X, TY, mid.Z)
		local slopeB = V(bot.X, FY, bot.Z)
		local planks = 8
		for i = 0, planks - 1 do
			local a = slopeA:Lerp(slopeB, (i + .06) / planks)
			local b = slopeA:Lerp(slopeB, (i + .94) / planks)
			local pl = K.Bar(m, "RampPlank", a + V(0, .05, 0), b + V(0, .05, 0), W - .3 - rng:NextNumber(0, .4), .22, C(104, 78, 58):Lerp(TIMBER_DARK, rng:NextNumber(0, .6)), M.WoodPlanks)
			pl.CFrame = pl.CFrame * CF(rng:NextNumber(-.15, .15), 0, 0)
		end
		for _, sgn in { -1, 1 } do
			local o = side * sgn * (W / 2 - .35)
			K.Bar(m, "RampStringer", slopeA + o - V(0, .3, 0), slopeB + o - V(0, .3, 0), .45, .5, TIMBER_DARK, M.Wood)
			local mp = slopeA:Lerp(slopeB, .5) + o
			K.Part(m, "RampTrestle", V(.5, mp.Y - .55 - FY, .5), CF(mp.X, (mp.Y - .55 + FY) / 2, mp.Z), TIMBER_DARK, M.Wood)
		end
		local mp = slopeA:Lerp(slopeB, .5)
		K.Bar(m, "RampTrestleBeam", mp - side * (W / 2 - .3) - V(0, .75, 0), mp + side * (W / 2 - .3) - V(0, .75, 0), .4, .4, TIMBER_DARK, M.Wood)
		-- lanterns on posts framing the ramp entrance
		local lk = LANTERN_KIND[rp.Id]
		for _, sgn in { -1, 1 } do
			local pos = V(top.X, RIM, top.Z) - dir * 1.4 + side * sgn * (W / 2 + 1.2)
			local toRamp = (V(top.X, RIM, top.Z) - dir * 1.4 - pos).Unit
			K.Lantern(rimM, CF(pos) * yawX(toRamp), lk[1], lk[2], { Height = 6.2, Range = 20, Brightness = 1.15 })
			lights += 1
		end
	end

	------------------------------------------------------------------------------------------------ arena floor
	local TILE = 6
	local nT = math.floor((A.X1 - A.X0) / TILE)
	for i = 0, nT - 1 do
		for j = 0, nT - 1 do
			local x0, z0 = A.X0 + i * TILE, A.Z0 + j * TILE
			local col = C(54, 50, 64):Lerp(C(74, 70, 86), rng:NextNumber(0, 1))
			local y = FY + .05 + ((i + j) % 2) * .03
			if rng:NextNumber() < .14 then
				-- cracked tile: two pieces with a dark seam
				local cut = rng:NextNumber(2, 4)
				box(floorM, "FloorTile", x0 + .1, x0 + cut - .08, y - .1, y, z0 + .1, z0 + TILE - .1, col, M.Slate)
				box(floorM, "FloorTile", x0 + cut + .08, x0 + TILE - .1, y - .12, y - .025, z0 + .1, z0 + TILE - .1, col:Lerp(P.Ink, .15), M.Slate)
			else
				box(floorM, "FloorTile", x0 + .1, x0 + TILE - .1, y - .1, y, z0 + .1, z0 + TILE - .1, col, M.Slate)
			end
		end
	end
	-- rune circles (subtle, flush)
	local RY = FY + .1
	local function runeArc(r, n, skipAxes, w)
		for i = 1, n do
			local a0, a1 = (i - 1) / n * math.pi * 2, (i - .2) / n * math.pi * 2
			local am = (a0 + a1) / 2
			local onAxis = false
			for k = 0, 3 do
				local d = math.abs(((am - k * math.pi / 2) + math.pi) % (math.pi * 2) - math.pi)
				if d < .2 then
					onAxis = true
				end
			end
			if not (skipAxes and onAxis) then
				K.Bar(floorM, "RuneLine", V(CX + math.cos(a0) * r, RY, CZ + math.sin(a0) * r), V(CX + math.cos(a1) * r, RY, CZ + math.sin(a1) * r), w, .05, RUNE, M.Neon, { Transparency = .35 })
			end
		end
	end
	runeArc(18.5, 24, true, .2)
	runeArc(11, 16, false, .16)
	runeArc(3.2, 10, false, .14)
	for k = 0, 7 do
		local a = (k + .5) / 8 * math.pi * 2
		-- sun / compass spokes between the inner circles + a diamond glyph between the outer circles
		K.Bar(floorM, "RuneLine", V(CX + math.cos(a) * 4.2, RY, CZ + math.sin(a) * 4.2), V(CX + math.cos(a) * (k % 2 == 0 and 10 or 8.2), RY, CZ + math.sin(a) * (k % 2 == 0 and 10 or 8.2)), .14, .05, RUNE, M.Neon, { Transparency = .45 })
		local g = V(CX + math.cos(a) * 14.8, RY, CZ + math.sin(a) * 14.8)
		K.Part(floorM, "RuneGlyph", V(.9, .05, .9), CF(g) * ANG(0, a + math.pi / 4, 0), RUNE, M.Neon, { Transparency = .3 })
	end
	-- cracks
	for _ = 1, 7 do
		local p = V(rng:NextNumber(A.X0 + 2, A.X1 - 2), FY + .08, rng:NextNumber(A.Z0 + 2, A.Z1 - 2))
		local ang = rng:NextNumber(0, math.pi * 2)
		for _ = 1, 2 do
			ang += rng:NextNumber(-.6, .6)
			local nxt = p + V(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(1.6, 3.2)
			K.Bar(floorM, "FloorCrack", p, nxt, .14, .04, C(22, 18, 28), M.Slate)
			p = nxt
		end
	end
	-- FogPoints on the arena floor + terrace
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + .2
		local r = (k % 2 == 0) and 9 or 17
		K.Attach(floor, "FogPoint", CF(V(CX + math.cos(a) * r, FY + .5, CZ + math.sin(a) * r) - floor.CFrame.Position))
	end
	for _, p in { V(R.X0 + 3, TY + .5, R.Z0 + 3), V(R.X1 - 3, TY + .5, R.Z1 - 3), V(R.X0 + 3, TY + .5, R.Z1 - 3), V(R.X1 - 3, TY + .5, R.Z0 + 3) } do
		K.Attach(floor, "FogPoint", CF(p - floor.CFrame.Position))
	end

	------------------------------------------------------------------------------------------------ the buried giant (south wall)
	local giant = K.Model(deco, "BuriedGiant")
	-- the face breaks out of the wall cladding (sockets just in front of the stones), the braincase stays in the wall, the
	-- muzzle and the dropped jaw reach over the terrace (the muzzle tip stops short of the arena edge)
	Y.GiantSkull(giant, CF(CX - 15, TY - .85, R.Z1 - 1.6) * ANG(0, 0, .05), .8,
		{ Name = "GiantSkull", Lite = true, Solid = false, Light = false, Mound = false, Tilt = .15, Eye = C(176, 92, 240), EyeDim = C(90, 44, 140) })
	-- a giant ribcage tunnelling out of the south wall: spine runs out of the wall, rib arches curve down to the terrace
	local rx0 = CX + 13
	local sp0, sp1 = V(rx0, RIM - 1.2, R.Z1 + .3), V(rx0, TY + .9, R.Z1 - 4.4)
	K.Rod(giant, "GiantSpine", sp0, sp1, .95, BONE_DARK, M.SmoothPlastic)
	for k = 1, 4 do
		local t = (k - .5) / 4
		local sp = sp0:Lerp(sp1, t)
		local col = BONE:Lerp(BONE_DARK, rng:NextNumber(0, .8))
		K.Ball(giant, "Vertebra", 1.25, CF(sp + V(0, .35, 0)), BONE, M.SmoothPlastic)
		local w = 3.2 - k * .25
		for _, sgn in { -1, 1 } do
			local pts = {
				sp,
				sp + V(sgn * w * .62, .45, .1),
				sp + V(sgn * w, -(sp.Y - TY) * .45, .15),
				V(sp.X + sgn * w * .82, TY - .2, sp.Z + .2),
			}
			for j = 1, 3 do
				K.Rod(giant, "GiantRib", pts[j], pts[j + 1], .62 - j * .07, col, M.SmoothPlastic).Size += V(.2, 0, 0)
			end
		end
	end
	-- giant bones sticking out of the side walls
	for _, b in {
		{ V(R.X0 + .2, -1.8, CZ - 17), V(R.X0 + 3.2, -2.6, CZ - 14.5) },
		{ V(R.X0 + .2, -2.4, CZ + 19), V(R.X0 + 2.6, -3.3, CZ + 21.5) },
		{ V(R.X1 - .2, -1.6, CZ + 12), V(R.X1 - 3.0, -2.5, CZ + 15) },
		{ V(R.X1 - .2, -2.2, CZ - 22), V(R.X1 - 2.7, -3.2, CZ - 19.5) },
		{ V(CX - 20, -1.4, R.Z0 + .2), V(CX - 17, -2.4, R.Z0 + 2.8) },
	} do
		bigBone(deco, b[1], b[2], .8, BONE_DARK)
	end

	------------------------------------------------------------------------------------------------ scaffold, ladders, rails, cart
	local sc = K.Model(deco, "BrokenScaffold")
	local sx0, sz0 = R.X1 - 5.4, R.Z0 + .9 -- terrace NE corner
	local posts = { V(sx0, 0, sz0), V(sx0 + 4, 0, sz0), V(sx0, 0, sz0 + 4.2), V(sx0 + 4, 0, sz0 + 4.2) }
	for i, p in posts do
		local h = (i == 4) and 3.4 or 7.6
		K.Part(sc, "ScaffoldPost", V(.45, h, .45), CF(p.X, TY + h / 2, p.Z), TIMBER, M.Wood, { Solid = true })
	end
	for _, y in { TY + 2.4, RIM + .05 } do
		K.Bar(sc, "ScaffoldBeam", V(sx0, y, sz0), V(sx0 + 4, y, sz0), .35, .35, TIMBER_DARK, M.Wood)
		K.Bar(sc, "ScaffoldBeam", V(sx0, y, sz0), V(sx0, y, sz0 + 4.2), .35, .35, TIMBER_DARK, M.Wood)
	end
	K.Bar(sc, "ScaffoldBeam", V(sx0 + 4, RIM + .05, sz0), V(sx0 + 4, TY + 3.2, sz0 + 4.2), .35, .35, TIMBER_DARK, M.Wood) -- sagging broken beam
	K.Bar(sc, "ScaffoldBrace", V(sx0, TY + .3, sz0), V(sx0 + 4, RIM - .3, sz0), .25, .25, TIMBER_DARK, M.Wood)
	K.Bar(sc, "ScaffoldBrace", V(sx0, TY + .3, sz0 + 4.2), V(sx0, RIM - .3, sz0), .25, .25, TIMBER_DARK, M.Wood)
	for k = 0, 2 do
		local plk = K.Part(sc, "ScaffoldPlank", V(4.4, .2, 1.2), CF(sx0 + 2, RIM + .3, sz0 + .6 + k * 1.3) * ANG(0, 0, k == 2 and -.35 or 0), C(104, 78, 58), M.WoodPlanks)
		if k == 2 then
			plk.CFrame = plk.CFrame * CF(.4, -.6, 0)
		end
	end
	local function ladder(base: Vector3, topP: Vector3, w: number)
		local m = K.Model(deco, "Ladder")
		local dir = (topP - base).Unit
		local side = dir:Cross(V(0, 1, 0))
		if side.Magnitude < .1 then
			side = V(1, 0, 0)
		end
		side = side.Unit
		for _, sgn in { -1, 1 } do
			K.Bar(m, "LadderRail", base + side * sgn * w / 2, topP + side * sgn * w / 2, .22, .22, TIMBER, M.Wood)
		end
		local len = (topP - base).Magnitude
		for k = 1, math.floor(len / .9) do
			local p = base + dir * (k * .9)
			K.Bar(m, "LadderRung", p - side * w / 2, p + side * w / 2, .14, .14, TIMBER_DARK, M.Wood)
		end
	end
	-- ladders against the outer walls (terrace -> rim)
	ladder(V(R.X0 + 2.2, TY, CZ - 9), V(R.X0 + .7, RIM + .6, CZ - 9), 1.3)
	ladder(V(CX + 20, TY, R.Z1 - 2.3), V(CX + 20, RIM + .6, R.Z1 - .7), 1.3)
	ladder(V(sx0 - 1.2, TY, sz0 + 1.6), V(sx0 - .2, RIM + .4, sz0 + 1.6), 1.2)
	-- old dig-station rails along the east terrace (north of the ramp) + a toppled cart
	local rx = R.X1 - 3
	local rz0, rz1 = R.Z0 + 7.5, CZ - HALFGAP - 1
	for _, o in { -.75, .75 } do
		K.Bar(deco, "OldRail", V(rx + o, TY + .25, rz0), V(rx + o, TY + .25, rz1), .18, .22, C(92, 70, 60), M.CorrodedMetal)
	end
	local nS = math.floor((rz1 - rz0) / 2.2)
	for k = 0, nS do
		local z = rz0 + (rz1 - rz0) * k / nS
		K.Part(deco, "RailSleeper", V(2.4, .18, .5), CF(rx, TY + .07, z) * ANG(0, rng:NextNumber(-.08, .08), 0), TIMBER_DARK, M.Wood)
	end
	do
		local cm = K.Model(deco, "ToppledCart")
		local cc = CF(rx - .6, TY + 1.0, rz1 - 2.5) * ANG(0, .4, 1.15)
		K.Part(cm, "CartTub", V(2.2, 1.5, 3.0), cc, C(96, 62, 46), M.CorrodedMetal)
		K.Part(cm, "CartRim", V(2.4, .2, 3.2), cc * CF(0, .8, 0), IRON, M.CorrodedMetal)
		for _, w in { { -.9, -1.0 }, { .9, -1.0 }, { -.9, 1.0 } } do
			K.CylX(cm, "CartWheel", .25, .9, cc * CF(w[1] * 1.25, -.8, w[2]), IRON, M.CorrodedMetal)
		end
		for k = 1, 4 do
			K.Ball(cm, "SpilledOre", rng:NextNumber(.5, .8), CF(rx - 1.3 + rng:NextNumber(-.6, .6), TY + .25, rz1 - 2.5 + rng:NextNumber(-1.4, 1.4)), k % 2 == 0 and C(70, 64, 84) or C(150, 80, 235), k % 2 == 0 and M.Slate or M.Neon)
		end
	end

	------------------------------------------------------------------------------------------------ rubble, mushrooms, chains
	local terraceSpots = {
		V(R.X0 + 2.5, TY, CZ - 20), V(R.X0 + 2.2, TY, CZ + 13), V(CX - 7, TY, R.Z0 + 2.4), V(CX + 9, TY, R.Z1 - 2.2),
		V(R.X1 - 2.4, TY, CZ + 22), V(CX - 23, TY, R.Z1 - 2.6), V(R.X1 - 2.5, TY, CZ + 8),
	}
	for i, p in terraceSpots do
		for _ = 1, 3 do
			local s = rng:NextNumber(.6, 1.5)
			local q = p + V(rng:NextNumber(-1.4, 1.4), 0, rng:NextNumber(-1.4, 1.4))
			K.Part(deco, "Rubble", V(s, s * .7, s * .9), CF(q.X, TY + s * .25, q.Z) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, 3), rng:NextNumber(-.4, .4)),
				STONE:Lerp(STONE_DARK, rng:NextNumber(0, 1)), M.Slate)
		end
		if i % 2 == 1 then
			K.Mushrooms(deco, CF(p + V(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))), 3, rng, i % 4 == 1 and P.Neon or C(176, 92, 240))
		end
	end
	K.Mushrooms(deco, CF(CX - 15 + 3.4, TY, R.Z1 - 2.6), 4, rng, C(176, 92, 240))
	-- chains hanging down the outer walls from rings under the coping
	for _, c in { { "N", CX - 12 }, { "N", CX + 16 }, { "W", CZ + 25 }, { "E", CZ - 8 }, { "S", CX - 4 } } do
		for _, sd in SIDES do
			if sd.id == c[1] then
				local a = Pt(sd, c[2], .75, RIM - .2)
				K.CylX(deco, "ChainRing", .2, .6, CF(a), IRON, M.CorrodedMetal)
				chain(deco, a, Pt(sd, c[2] + .4, .85, TY + rng:NextNumber(.6, 1.4)), 0, .6)
			end
		end
	end
	-- chains sagging between the scaffold and the north wall
	chain(deco, V(sx0, RIM - .3, sz0), V(sx0 - 8, RIM - .2, R.Z0 + .4), 1.6, .62)

	------------------------------------------------------------------------------------------------ rim dressing
	-- outer curb of the rim walk
	local CURB = C(84, 80, 94)
	box(rimM, "RimCurb", OX0, OX1, RIM - .2, RIM + .1, OZ0, OZ0 + .6, CURB, M.Cobblestone)
	box(rimM, "RimCurb", OX0, OX1, RIM - .2, RIM + .1, OZ1 - .6, OZ1, CURB, M.Cobblestone)
	box(rimM, "RimCurb", OX0, OX0 + .6, RIM - .2, RIM + .1, OZ0 + .6, OZ1 - .6, CURB, M.Cobblestone)
	box(rimM, "RimCurb", OX1 - .6, OX1, RIM - .2, RIM + .1, OZ0 + .6, OZ1 - .6, CURB, M.Cobblestone)
	-- candles + a pumpkin on a few balustrade copings
	for _, p in { V(CX - 20, RIM + 1.35, R.Z0 - .45), V(R.X1 + .45, RIM + 1.35, CZ + 18), V(CX + 14, RIM + 1.35, R.Z1 + .45) } do
		K.Candles(deco, CF(p), 3, rng, { Light = false, Spread = .35 })
	end

	------------------------------------------------------------------------------------------------ THE GRAVE BELL (boss summon)
	-- a gothic stone belfry on the north rim at Layout.Bell (the prompt anchor Layout.Bell.Prompt stays just in front of the
	-- bell): a three-tier stepped dais with a flush violet rune ring around a glowing well under the bell (its kerb carries
	-- an invisible collider so nobody stands inside the bell), four buttressed piers with pointed voxel arches, timber
	-- bearing beams + stone lintels with inscribed friezes ("THE GRAVE BELL" toward the cauldron, "RING TO SUMMON" toward the
	-- pit), a Neon line under the cornice, a stepped slate spire with corner pinnacles and a Neon crescent finial, chains,
	-- two green-flame braziers (HwBrazier, one PointLight) and candles on the dais corners, a violet SpotLight on the bell.
	-- The bell itself (crown, shoulder dome, stepped waist, sound bow, lip, gold bands, violet Neon rune band `BellGlow`,
	-- moon medallion in front, dog skull behind, dark mouth, `BellClapper` with a green core, headstock + lever) is the
	-- Model `GraveBell.Swing`, PrimaryPart `SwingPivot` = the axle `BellBeam` (X axis): swing it with PivotTo(pivot * rotX).
	do
		local B = L.Bell.Position
		local bell = K.Model(pit, "GraveBell")
		bell:SetAttribute("HwGraveBell", true)
		local G = CF(B.X, RIM, B.Z) -- front (prompt, cauldron) = -Z, back (pit) = +Z
		local function at(x, y, z)
			return G * CF(x, y, z)
		end
		local VIOLET = C(176, 92, 240)
		local PIER, PIER_HI = C(88, 84, 100), C(118, 114, 130)
		local BRONZE, BRONZE_D, GOLD = C(150, 108, 56), C(118, 84, 46), C(196, 150, 70)
		-- stepped dais, rune ring + glyphs, the glowing well under the bell
		K.Part(bell, "BellDais", V(11.0, .3, 9.4), at(0, .15, 0), C(60, 56, 70), M.Cobblestone, SOLID)
		K.Part(bell, "BellDais", V(9.4, .3, 8.0), at(0, .45, 0), C(78, 74, 90), M.Slate, { Solid = true })
		K.Part(bell, "BellDais", V(8.0, .25, 6.6), at(0, .725, 0), C(96, 92, 108), M.Slate, { Solid = true })
		for i = 1, 16 do
			local a0, a1 = (i - 1) / 16 * math.pi * 2, (i - .2) / 16 * math.pi * 2
			K.Bar(bell, "BellRune", (at(math.cos(a0) * 2.75, .87, math.sin(a0) * 2.75)).Position, (at(math.cos(a1) * 2.75, .87, math.sin(a1) * 2.75)).Position,
				.16, .05, VIOLET, M.Neon, { Transparency = .15 })
		end
		for k = 0, 7 do
			local a = (k + .5) / 8 * math.pi * 2
			K.Part(bell, "BellRuneGlyph", V(.5, .05, .5), at(math.cos(a) * 3.1, .87, math.sin(a) * 3.1) * ANG(0, a + math.pi / 4, 0), VIOLET, M.Neon, { Transparency = .2 })
		end
		K.CylY(bell, "BellWellKerb", .45, 4.4, at(0, 1.07, 0), C(84, 80, 96), M.Cobblestone, { Solid = true })
		K.CylY(bell, "BellWell", .5, 3.6, at(0, 1.09, 0), C(16, 10, 22), M.SmoothPlastic)
		K.CylY(bell, "BellWellGlow", .54, 2.7, at(0, 1.11, 0), C(120, 60, 200), M.Neon, { Transparency = .3 })
		K.CylY(bell, "BellCollider", 6, 4.4, at(0, 4, 0), STONE, M.Slate, { Solid = true, Transparency = 1, Shadow = false })
		-- four buttressed piers
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local px, pz = sx * 3.25, sz * 2.6
				K.Part(bell, "PierBase", V(1.7, 1.0, 1.7), at(px, 1.1, pz), PIER:Lerp(STONE_DARK, .4), M.Cobblestone, { Solid = true })
				K.Part(bell, "PierShaft", V(1.15, 6.9, 1.15), at(px, 5.05, pz), PIER, M.Cobblestone, { Solid = true })
				K.Part(bell, "PierBand", V(1.38, .3, 1.38), at(px, 4.6, pz), PIER_HI, M.Slate)
				K.Part(bell, "PierCapital", V(1.55, .45, 1.55), at(px, 8.725, pz), PIER_HI, M.Slate)
				K.Wedge(bell, "PierButtress", V(1.0, 3.6, 1.0), at(px + sx * 1.05, 2.1, pz) * ANG(0, -sx * math.pi / 2, 0), PIER:Lerp(STONE_DARK, .2), M.Cobblestone)
			end
		end
		-- bearing beams (timber, along Z) + stone lintels (along X) with inscribed friezes, cornice, glow line
		for _, sx in { -1, 1 } do
			K.Part(bell, "BellFrameBeam", V(1.2, .9, 6.9), at(sx * 3.25, 9.4, 0), TIMBER_DARK, M.Wood)
			K.Part(bell, "BellBearing", V(.5, .5, .7), at(sx * 2.4, 8.7, 0), IRON, M.CorrodedMetal)
		end
		for _, sz in { -1, 1 } do
			K.Part(bell, "BellLintel", V(7.7, 1.1, 1.2), at(0, 9.5, sz * 2.6), PIER_HI, M.Slate)
			local panel = K.Part(bell, "BellFrieze", V(6.2, .78, .06), at(0, 9.5, sz * 3.23), C(40, 28, 54), M.SmoothPlastic)
			K.Sign(panel, sz < 0 and Enum.NormalId.Front or Enum.NormalId.Back, sz < 0 and "THE GRAVE BELL" or "RING TO SUMMON", P.Cream,
				{ PixelsPerStud = 24, H = .86, W = .96, StrokeColor = C(70, 24, 110) })
		end
		local cornice = K.Part(bell, "BellCornice", V(8.8, .3, 7.4), at(0, 10.2, 0), C(78, 74, 90), M.Slate)
		K.Attach(cornice, "BatRoost", CF(0, -.5, 0))
		for _, sz in { -1, 1 } do
			K.Part(bell, "BellCorniceGlow", V(8.6, .1, .12), at(0, 10.0, sz * 3.62), VIOLET, M.Neon)
		end
		for _, sx in { -1, 1 } do
			K.Part(bell, "BellCorniceGlow", V(.12, .1, 7.1), at(sx * 4.32, 10.0, 0), VIOLET, M.Neon)
		end
		-- pointed voxel arches: front / back (x span) and sides (z span), stepped blocks under the lintels / beams
		for _, sz in { -1, 1 } do
			for _, sx in { -1, 1 } do
				for _, st in { { 2.34, .675, 7.2 }, { 1.675, .65, 7.95 }, { 1.025, .65, 8.5 } } do
					K.Part(bell, "BellArch", V(st[2], 8.95 - st[3], 1.0), at(sx * st[1], (8.95 + st[3]) / 2, sz * 2.6), PIER, M.Cobblestone)
				end
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				for _, st in { { 1.71, .625, 7.6 }, { 1.08, .65, 8.3 } } do
					K.Part(bell, "BellArch", V(1.0, 8.95 - st[3], st[2]), at(sx * 3.25, (8.95 + st[3]) / 2, sz * st[1]), PIER, M.Cobblestone)
				end
			end
		end
		-- stepped slate spire, corner pinnacles, crescent finial
		local tiers = { { 7.4, 6.0 }, { 6.3, 5.1 }, { 5.2, 4.2 }, { 4.1, 3.4 }, { 3.0, 2.6 }, { 2.0, 1.8 }, { 1.2, 1.1 } }
		for k, t in tiers do
			K.Part(bell, "BellSpire", V(t[1], .55, t[2]), at(0, 10.35 + (k - .5) * .55, 0), (k % 2 == 1) and C(60, 50, 76) or C(48, 40, 62), M.Slate)
		end
		K.Part(bell, "BellSpireTip", V(.6, .8, .6), at(0, 14.2 + .4, 0), C(60, 50, 76), M.Slate)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local pin = K.Part(bell, "BellPinnacle", V(.7, 1.0, .7), at(sx * 4.0, 10.85, sz * 3.35), PIER_HI, M.Slate)
				K.Part(bell, "BellPinnacle", V(.45, .6, .45), at(sx * 4.0, 11.65, sz * 3.35), PIER_HI, M.Slate)
				K.Ball(bell, "BellPinnacleKnob", .42, at(sx * 4.0, 12.12, sz * 3.35), C(96, 92, 108), M.Slate)
				if sz < 0 then
					K.Attach(pin, "CrowPerch", CF(0, 1.55, 0))
				end
			end
		end
		K.CylY(bell, "BellFinialRod", 2.0, .22, at(0, 15.95, 0), IRON, M.CorrodedMetal)
		local MOON = C(255, 222, 140)
		local cc, cr = at(0, 17.85, 0), .95
		for k = 0, 5 do -- crescent opening to the upper right, thickest at the bottom left
			local a0, a1 = math.rad(105 + k * 40), math.rad(105 + (k + 1) * 40)
			local w = ({ .16, .26, .34, .34, .26, .16 })[k + 1]
			K.Bar(bell, "BellCrescent", (cc * CF(math.cos(a0) * cr, math.sin(a0) * cr, 0)).Position, (cc * CF(math.cos(a1) * cr, math.sin(a1) * cr, 0)).Position, .2, w, MOON, M.Neon)
		end
		K.Attach(K.Part(bell, "BellFinialTop", V(.2, .2, .2), at(0, 17.0, 0), IRON, nil, { Transparency = 1 }), "CrowPerch", CF(0, .2, 0))
		-- chain swags on the sides
		for _, sx in { -1, 1 } do
			chain(bell, (at(sx * 3.95, 8.75, -2.1)).Position, (at(sx * 3.95, 8.75, 2.1)).Position, 1.1, .6)
		end
		-- the swinging bell (pivot = axle)
		local AX = 8.6
		local swing = K.Model(bell, "Swing")
		local pivot = K.Part(swing, "SwingPivot", V(.3, .3, .3), at(0, AX, 0), IRON, nil, { Transparency = 1 })
		swing.PrimaryPart = pivot
		K.CylX(swing, "BellBeam", 4.8, .32, at(0, AX, 0), IRON, M.CorrodedMetal)
		K.Part(swing, "BellHeadstock", V(3.4, .8, 1.2), at(0, AX, 0), TIMBER, M.Wood)
		for _, sx in { -1, 1 } do
			K.Part(swing, "BellStrap", V(.18, 1.1, 1.3), at(sx * .85, 7.85, 0), IRON, M.CorrodedMetal)
		end
		K.Bar(swing, "BellLever", (at(1.55, AX, .2)).Position, (at(1.95, AX, -2.3)).Position, .28, .28, IRON, M.CorrodedMetal)
		K.CylY(swing, "BellCrown", .45, .95, at(0, 8.0, 0), BRONZE_D, M.Metal)
		K.Ellipsoid(swing, "BellShoulder", V(2.7, 1.3, 2.7), at(0, 7.25, 0), BRONZE, M.Metal)
		K.CylY(swing, "BellBand", .16, 2.8, at(0, 6.95, 0), GOLD, M.Metal)
		-- waist: two tall tiers, then the stepped flare (sound bow) and the lip
		for _, w in { { 1.1, 2.75, 6.4 }, { .9, 2.95, 5.4 }, { .35, 3.4, 4.775 }, { .3, 3.9, 4.45 }, { .3, 4.4, 4.15 } } do
			K.CylY(swing, "BellWaist", w[1], w[2], at(0, w[3], 0), BRONZE:Lerp(BRONZE_D, math.max(0, w[2] - 2.95) / 1.6), M.Metal)
		end
		K.CylY(swing, "BellGlow", .2, 3.0, at(0, 5.85, 0), VIOLET, M.Neon)
		K.CylY(swing, "BellBand", .1, 3.02, at(0, 4.92, 0), GOLD, M.Metal)
		K.CylY(swing, "BellLip", .26, 4.7, at(0, 3.87, 0), GOLD:Lerp(BRONZE, .4), M.Metal)
		K.CylY(swing, "BellMouth", .05, 4.35, at(0, 3.72, 0), C(14, 8, 18), M.SmoothPlastic)
		K.Ball(swing, "BellClapper", .85, at(0, 3.6, 0), C(60, 50, 40), M.Metal)
		K.Ball(swing, "BellClapperGlow", .5, at(0, 3.25, 0), C(120, 255, 110), M.Neon)
		-- moon medallion toward the summoners, the Gravekeeper's skull toward the pit
		K.CylZ(swing, "BellMedallion", .14, 1.15, at(0, 5.36, -1.52), GOLD:Lerp(BRONZE_D, .3), M.Metal)
		K.CylZ(swing, "BellMoon", .06, .84, at(0, 5.36, -1.6), MOON, M.Neon)
		K.CylZ(swing, "BellMoonShade", .07, .68, at(.19, 5.46, -1.62), GOLD:Lerp(BRONZE_D, .3), M.Metal)
		dogSkull(swing, at(0, 4.98, 1.62) * ANG(0, math.pi, 0) * ANG(.08, 0, 0), .34, C(120, 255, 110)).Name = "BellSkull"
		-- pull rope with a striped sally from the lever, its tail coiled on the dais
		local ROPE = C(150, 128, 92)
		K.Rod(bell, "BellRope", (at(1.95, AX - .15, -2.3)).Position, (at(1.95, 3.9, -2.35)).Position, .16, ROPE, M.Fabric)
		for k = 0, 2 do
			K.CylY(bell, "BellSally", .4, .3, at(1.95, 3.7 - k * .42, -2.35), k % 2 == 0 and C(170, 40, 50) or P.Cream, M.Fabric)
		end
		K.Rod(bell, "BellRope", (at(1.95, 2.65, -2.35)).Position, (at(2.25, 1.0, -2.75)).Position, .16, ROPE, M.Fabric)
		K.CylY(bell, "BellRopeCoil", .25, .95, at(2.4, .98, -2.85), ROPE, M.Fabric)
		-- green-flame braziers on the front corners (one lit), candles on the back corners
		for _, sx in { -1, 1 } do
			K.Part(bell, "BrazierPlinth", V(1.2, .8, 1.2), at(sx * 4.95, .7, -4.15), PIER_HI, M.Slate, { Solid = true })
			K.CylY(bell, "BrazierStand", .7, .3, at(sx * 4.95, 1.45, -4.15), IRON, M.CorrodedMetal)
			K.CylY(bell, "BrazierBowl", .45, 1.2, at(sx * 4.95, 2.0, -4.15), IRON, M.CorrodedMetal)
			K.CylY(bell, "BrazierRim", .1, 1.36, at(sx * 4.95, 2.25, -4.15), RUST, M.CorrodedMetal)
			local flame = K.Ellipsoid(bell, "BrazierFlame", V(.95, 1.15, .95), at(sx * 4.95, 2.72, -4.15), C(120, 255, 110), M.Neon,
				{ Transparency = .15, Attrs = { HwBrazier = true } })
			K.Ellipsoid(bell, "BrazierFlameCore", V(.5, .8, .5), at(sx * 4.95, 2.62, -4.15), C(220, 255, 200), M.Neon)
			if sx < 0 then
				K.Light(flame, C(120, 255, 110), 14, 1.0)
				lights += 1
			end
			K.Candles(bell, at(sx * 4.85, .3, 4.15), 3, rng, { Light = false, Spread = .35 })
		end
		-- violet key light under the spire, aimed down at the bell
		local lamp = K.Part(bell, "BellKeyLight", V(.3, .3, .3), K.Look(at(0, 9.9, -.6).Position, at(0, 3, -.6).Position), VIOLET, nil, { Transparency = 1 })
		local spot = K.Light(lamp, C(170, 120, 255), 18, 2.5, "SpotLight")
		spot.Angle = 75
		spot:SetAttribute("HwKeyLight", true)
		lights += 1
	end

	if ctx.Note then
		ctx.Note(string.format("Pit: %d parts, %d lights", K.Count(pit), lights))
	end
	return pit
end

return Pit
