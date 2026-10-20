-- THE DEAD YARD — the hero entrance gate (WP1). Build-time builder (hw/edits/deadyard.luau → tools/sim.luau), saved in
-- the place as Workspace.DOGROTS_District.38_DeadYard.Gate. Faces -X (players arrive from the boulevard along z 575).
--   * two old stone pillars (dog-skull reliefs framed by purple glow, crescent friezes, dead vines), a stone lintel with
--     jack-o'-lanterns, the "THE DEAD YARD" board, an iron crown arch with a dog skull + crossed giant bones crest,
--   * two rusty iron leaves: Models LeafL / LeafR with attributes HwGateLeaf="L"/"R", OpenAngle=100, OpenSign=+1/-1
--     (PrimaryPart = HingeStile, axis-aligned, its CFrame is the hinge pivot; open = pivot * Angles(0, rad(OpenAngle) *
--     OpenSign, 0) swings the leaf INTO the yard). Leaves start closed and never collide,
--   * wing walls to the fence with the "NIGHT OF THE BURIED MOON" plaque (Layout.Gate.Plaque), a glowing paw medallion,
--     two green-flame braziers (flame parts HwBrazier=true + green PointLight), K.Lantern Purple/Green,
--   * markers: CrowPerch (top), GateFog (threshold), the threshold paving x 33..38 (top 0.5, Future paving -> Hollow Lane).
-- Nothing solid inside the opening z 566..584.
local K = require(script.Parent.Kit)
local P = K.Palette
local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local M = Enum.Material

local Gate = {}

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

local STONE = C(92, 88, 104)
local STONE_DARK = C(64, 60, 76)
local STONE_LIGHT = C(122, 118, 134)
local IRON = C(40, 40, 48)
local RUST = C(118, 62, 40)
local GLOW = C(150, 80, 235)
local GREEN = C(120, 255, 110)
local BONE = P.Bone
local BONE_DARK = C(204, 190, 158)
local FACE_X = ANG(0, math.pi / 2, 0) -- local -Z -> world -X

-- chain of alternating links between two points (sagging)
local function chain(parent, a: Vector3, b: Vector3, sag: number, linkLen: number?)
	local m = K.Model(parent, "Chain")
	local len = (b - a).Magnitude
	local n = math.max(3, math.floor(len / (linkLen or .62) + .5))
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - V(0, math.sin(t * math.pi) * sag, 0)
		local link = K.Bar(m, "ChainLink", prev, p, .16, .4, IRON:Lerp(RUST, .25), M.CorrodedMetal)
		link.Size = link.Size + V(0, 0, .12)
		if i % 2 == 0 then
			link.CFrame = link.CFrame * ANG(0, 0, math.pi / 2)
		end
		prev = p
	end
	return m
end

-- giant cartoon dog bone between two points (shaft + 4 knobs); normal = facing normal of the plane the bone is seen in
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

-- stylised dog skull facing -Z of cf (s = scale, dz = depth factor for reliefs), glowing eyes
local function dogSkull(parent, cf: CFrame, s: number, eye: Color3, dz: number?)
	local m = K.Model(parent, "DogSkull")
	local d = dz or 1
	local function at(x, y, z)
		return cf * CF(x * s, y * s, z * s * d)
	end
	K.Ellipsoid(m, "SkullCranium", V(2.2 * s, 1.9 * s, 2.3 * s * d), at(0, 1.05, .2), BONE, M.SmoothPlastic)
	K.Part(m, "SkullBrow", V(1.9 * s, .36 * s, .7 * s * d), at(0, 1.38, -.72), BONE_DARK, M.SmoothPlastic)
	K.Part(m, "SkullMuzzle", V(1.12 * s, .72 * s, 1.55 * s * d), at(0, .62, -1.45), BONE, M.SmoothPlastic)
	K.Wedge(m, "SkullBridge", V(1.12 * s, .42 * s, 1.35 * s * d), at(0, 1.19, -1.38), BONE, M.SmoothPlastic)
	K.Part(m, "SkullNose", V(.56 * s, .32 * s, .22 * s * d), at(0, .9, -2.22), P.Ink, M.SmoothPlastic)
	K.Part(m, "SkullJaw", V(1.0 * s, .3 * s, 1.4 * s * d), at(0, .13, -1.3), BONE_DARK, M.SmoothPlastic)
	K.Part(m, "SkullTeeth", V(.96 * s, .2 * s, .1 * s * d), at(0, .3, -2.2), BONE, M.SmoothPlastic)
	for _, sx in { -1, 1 } do
		K.Ellipsoid(m, "SkullSocket", V(.66 * s, .58 * s, .34 * s * d), at(sx * .5, 1.08, -.98), P.Ink, M.SmoothPlastic)
		K.Ball(m, "SkullEye", .3 * s, at(sx * .5, 1.08, -1.1), eye, M.Neon)
		K.Wedge(m, "SkullEar", V(.28 * s, 1.0 * s, .78 * s), at(sx * .78, 2.12, .35) * ANG(0, sx * math.pi / 2, 0) * ANG(0, 0, 0), BONE_DARK, M.SmoothPlastic)
		K.Wedge(m, "SkullFang", V(.16 * s, .36 * s, .16 * s * d), at(sx * .33, .02, -2.08) * ANG(math.pi, 0, 0), BONE, M.SmoothPlastic)
	end
	return m
end

function Gate.Build(ctx)
	local L = ctx.Layout
	local rng = Rng(5507)
	local G = L.Gate
	local GX, FY, CZ = G.Center.X, L.FloorY, (G.Opening.Z0 + G.Opening.Z1) / 2
	local HALF = (G.Opening.Z1 - G.Opening.Z0) / 2 -- 9
	local gate = K.Model(ctx.Root, "Gate")
	local static = K.Model(gate, "Structure")
	local deco = K.Model(gate, "Decor")
	local lights = 0
	local function Z(sgn, d)
		return CZ + sgn * d
	end

	------------------------------------------------------------------------------------------------ threshold
	local th = K.Part(static, "GateThreshold", V(5, .4, HALF * 2 + 1), CF(35.5, .3, CZ), C(58, 54, 66), M.Cobblestone, { Solid = true })
	for r = 0, 2 do
		for c = 0, 5 do
			local w = 1.45
			local z0 = CZ - HALF - .5 + .2 + (c + (r % 2) * .5) * 3.1
			if z0 + 2.9 <= CZ + HALF + .5 then
				K.Part(deco, "ThresholdSlab", V(w, .1, 2.85), CF(33.95 + r * 1.65, .52, z0 + 1.45) * ANG(0, rng:NextNumber(-.03, .03), 0),
					STONE_DARK:Lerp(STONE, rng:NextNumber(0, .5)), M.Slate)
			end
		end
	end
	K.Part(deco, "GateSill", V(.9, .14, HALF * 2), CF(GX, .55, CZ), C(76, 72, 88), M.Slate)
	for i, z in { CZ - 7, CZ - 3.5, CZ, CZ + 3.5, CZ + 7 } do
		K.Attach(th, "GateFog", CF(V(33.6, .6, z) - th.CFrame.Position))
		if i % 2 == 1 then
			K.Attach(th, "GateFog", CF(V(37.6, .6, z) - th.CFrame.Position))
		end
	end

	------------------------------------------------------------------------------------------------ pillars
	local function pillar(sgn)
		local m = K.Model(static, sgn < 0 and "PillarL" or "PillarR")
		local zc = Z(sgn, HALF + 3.2) -- 562.8 / 587.2 (inner faces stay outside the opening)
		local function blk(name, sx, y0, y1, sz, col, mat, solid)
			return K.Part(m, name, V(sx, y1 - y0, sz), CF(GX, (y0 + y1) / 2, zc), col, mat, { Solid = solid })
		end
		blk("PillarPlinth", 6.2, FY, 1.1, 5.4, STONE_DARK, M.Cobblestone, true)
		blk("PillarBase", 5.6, 1.1, 3.7, 5.0, STONE, M.Slate, true)
		blk("PillarBaseMold", 5.9, 3.7, 4.15, 5.25, STONE_DARK, M.Slate, true)
		blk("PillarShaft", 4.6, 4.15, 18.35, 4.4, STONE, M.Cobblestone, true)
		for i, y in { 6.6, 9.0, 11.4, 13.8, 16.2 } do
			blk("PillarCourse", 4.72, y - .16, y + .16, 4.52, STONE:Lerp(STONE_DARK, .45 + (i % 2) * .15), M.Slate)
		end
		blk("PillarCapMold", 5.2, 18.35, 18.85, 5.0, STONE_DARK, M.Slate, true)
		blk("PillarFrieze", 4.8, 18.85, 20.45, 4.6, STONE_LIGHT, M.Slate, true)
		blk("PillarCornice", 6.0, 20.45, 21.2, 5.4, STONE_DARK, M.Slate, true)
		-- front relief panel: dark inset, stone frame, purple glow inside the frame, dog skull + crossed bones
		local fx = GX - 2.3 -- shaft front face (33.7)
		K.Part(m, "ReliefInset", V(.1, 8.8, 2.8), CF(fx - .05, 11.2, zc), C(34, 28, 46), M.Slate)
		for _, d in { -1.6, 1.6 } do
			K.Part(m, "ReliefFrame", V(.36, 9.6, .42), CF(fx - .16, 11.2, zc + d), STONE_LIGHT, M.Slate)
			K.Part(m, "ReliefGlow", V(.12, 8.7, .12), CF(fx - .14, 11.2, zc + d * .83), GLOW, M.Neon)
		end
		for _, y in { 6.6, 15.8 } do
			K.Part(m, "ReliefFrame", V(.36, .42, 3.62), CF(fx - .16, y, zc), STONE_LIGHT, M.Slate)
			K.Part(m, "ReliefGlow", V(.12, .12, 2.7), CF(fx - .14, y + (y < 10 and .34 or -.34), zc), GLOW, M.Neon)
		end
		dogSkull(m, CF(fx - .25, 11.5, zc) * FACE_X, .78, GLOW, .55)
		bigBone(m, V(fx - .35, 7.6, zc - 1.05), V(fx - .35, 10.1, zc + 1.05), .32, BONE_DARK, V(1, 0, 0))
		bigBone(m, V(fx - .45, 7.6, zc + 1.05), V(fx - .45, 10.1, zc - 1.05), .32, BONE_DARK, V(1, 0, 0))
		-- crescent moon carved in the frieze
		K.CylX(m, "FriezeMoon", .14, 1.25, CF(GX - 2.47, 19.65, zc), BONE_DARK, M.SmoothPlastic)
		K.CylX(m, "FriezeMoonCut", .14, 1.05, CF(GX - 2.52, 19.78, zc + sgn * .32), STONE_LIGHT, M.Slate)
		-- inner face (toward the opening): a carved vertical giant bone
		local inner = zc - sgn * 2.2
		bigBone(m, V(GX, 6.6, inner - sgn * .2), V(GX, 15.0, inner - sgn * .2), .72, BONE_DARK, V(0, 0, 1))
		-- yard-side face: carved paw circle
		K.CylX(m, "YardPawDisc", .12, 2.3, CF(GX + 2.36, 14.6, zc), C(34, 28, 46), M.Slate)
		K.Ellipsoid(m, "YardPawPad", V(.1, .62, .74), CF(GX + 2.44, 14.32, zc), GLOW, M.Neon)
		for _, t in { { -.5, .3 }, { -.19, .56 }, { .19, .56 }, { .5, .3 } } do
			K.Ellipsoid(m, "YardPawToe", V(.1, .3, .26), CF(GX + 2.44, 14.6 + t[2], zc + t[1]), GLOW, M.Neon)
		end
		-- hinge pintles (static; the leaf's hinge stile turns on them)
		for _, y in { 2.6, 8.6, 14.6 } do
			K.Part(m, "HingePintle", V(.36, .44, 1.6), CF(GX, y, Z(sgn, HALF + .2)), IRON, M.CorrodedMetal)
		end
		-- dead vines climbing the outer side + front corner
		local vx = GX - 2.3
		local vz = zc + sgn * 2.2
		local prev = V(vx + 1.2, FY + .3, vz + sgn * .06)
		for i = 1, 6 do
			local nxt = V(vx + rng:NextNumber(-.1, 1.6), FY + i * 2.4 + rng:NextNumber(-.4, .4), vz + sgn * .08)
			K.Rod(m, "DeadVine", prev, nxt, .16, C(66, 48, 58), M.Wood)
			if i % 2 == 0 then
				K.Part(m, "VineLeaf", V(.5, .08, .36), CF(nxt + V(0, 0, sgn * .12)) * ANG(math.pi / 2, rng:NextNumber(0, 3), 0), C(92, 46, 52), M.SmoothPlastic)
			end
			prev = nxt
		end
		-- moss on the plinth + broken stone chunks at the foot
		K.Part(m, "PlinthMoss", V(1.6, .14, 4.6), CF(GX - 2.5, 1.12, zc), P.Moss, M.Grass)
		K.Part(m, "Rubble", V(.9, .6, .7), CF(GX - 3.6, FY + .25, zc + sgn * 2.4) * ANG(.3, .7, .2), STONE_DARK, M.Slate)
		K.Part(m, "Rubble", V(.6, .4, .5), CF(GX - 3.3, FY + .18, zc + sgn * 3.2) * ANG(.1, 1.7, .4), STONE, M.Slate)
	end
	pillar(-1)
	pillar(1)

	------------------------------------------------------------------------------------------------ lintel + jack-o'-lanterns
	local LT = 22.4
	local lintel = K.Part(static, "GateLintel", V(4.4, 1.2, (HALF + 6.1) * 2), CF(GX + .2, 21.8, CZ), STONE_DARK, M.Slate, { Solid = true })
	K.Part(static, "LintelFace", V(.3, .7, (HALF + 5.5) * 2), CF(GX - 2.08, 21.75, CZ), STONE, M.Slate)
	for _, sgn in { -1, 1 } do
		local zc = Z(sgn, HALF + 4.3)
		K.CylY(static, "PumpkinSeat", .45, 3.0, CF(GX, LT + .22, zc), STONE_LIGHT, M.Slate)
		local pk = K.Pumpkin(deco, CF(GX - .1, LT + .4, zc) * FACE_X * ANG(0, sgn * -.18, 0), 3.7, { Light = true, Glow = C(255, 150, 50) })
		pk.Name = "GatePumpkin"
		lights += 1
		K.Attach(lintel, "CrowPerch", CF(V(GX + 1.2, LT + .05, Z(sgn, HALF + 6.4)) - lintel.CFrame.Position))
	end

	------------------------------------------------------------------------------------------------ sign board
	local board = K.Model(static, "DeadYardSign")
	local BX = 34.1
	local BW = 18.6
	local by0, by1 = LT, LT + 4.4
	for i, y in { by0 + .75, by0 + 2.2, by0 + 3.65 } do
		K.Part(board, "SignPlank", V(.5, 1.42, BW - (i == 2 and 0 or rng:NextNumber(.2, .6))),
			CF(BX, y, CZ + rng:NextNumber(-.15, .15)) * ANG(rng:NextNumber(-.012, .012), 0, 0), P.WoodDark:Lerp(C(44, 30, 34), (i % 2) * .4), M.WoodPlanks)
	end
	-- iron frame + corner brackets + purple glow edge
	for _, y in { by0 + .08, by1 - .08 } do
		K.Part(board, "SignIron", V(.62, .28, BW + .5), CF(BX - .02, y, CZ), IRON, M.CorrodedMetal)
		K.Part(board, "SignGlow", V(.14, .14, BW - .6), CF(BX - .36, y + (y < by0 + 1 and .26 or -.26), CZ), GLOW, M.Neon)
	end
	for _, sgn in { -1, 1 } do
		K.Part(board, "SignIron", V(.62, 4.7, .3), CF(BX - .02, (by0 + by1) / 2, Z(sgn, BW / 2 + .1)), IRON, M.CorrodedMetal)
		for _, y in { by0 + .45, by1 - .45 } do
			K.Part(board, "SignBracket", V(.7, .7, .7), CF(BX - .05, y, Z(sgn, BW / 2 - .2)) * ANG(math.pi / 4, 0, 0), RUST, M.CorrodedMetal)
		end
		-- struts back to the arch
		K.Rod(board, "SignStrut", V(BX + .3, by1 - .4, Z(sgn, 5.2)), V(GX, by1 + .5, Z(sgn, 5.2)), .22, IRON, M.CorrodedMetal)
	end
	local text = K.Part(board, "SignText", V(.1, 4.0, BW - 1.6), CF(BX - .33, (by0 + by1) / 2, CZ), BONE, M.SmoothPlastic, { Transparency = 1 })
	K.Sign(text, Enum.NormalId.Left, "THE DEAD YARD", BONE, { PixelsPerStud = 24, StrokeColor = C(110, 50, 190), W = .96, H = .86, MaxDistance = 600 })
	local tl = text:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
	tl.TextStrokeTransparency = 0
	-- a hanging bone and a cobweb on the board
	chain(board, V(BX - .2, by0 + .05, Z(1, 6.4)), V(BX - .2, by0 - 1.6, Z(1, 6.4)), 0, .5)
	bigBone(board, V(BX - .2, by0 - 1.75, Z(1, 7.1)), V(BX - .2, by0 - 1.75, Z(1, 5.7)), .22, BONE, V(1, 0, 0))

	------------------------------------------------------------------------------------------------ iron crown arch + crest
	local arch = K.Model(static, "CrownArch")
	local function arc(rz, ry, n, w, h, col)
		local pts = {}
		for i = 0, n do
			local t = i / n * math.pi
			table.insert(pts, V(GX, LT + math.sin(t) * ry, CZ - math.cos(t) * rz))
		end
		for i = 1, n do
			K.Bar(arch, "ArchBand", pts[i], pts[i + 1], w, h, col, M.CorrodedMetal).Size += V(0, 0, .1)
		end
		return pts
	end
	local outer = arc(11, 7.6, 12, .5, .55, IRON:Lerp(RUST, .2))
	local inner = arc(10, 6.4, 12, .36, .4, IRON)
	for i = 2, 12, 2 do
		K.Bar(arch, "ArchSpoke", inner[i], outer[i], .22, .22, IRON, M.CorrodedMetal)
	end
	for i = 2, 12 do
		if i ~= 7 then
			local p = outer[i]
			local t = (i - 1) / 12 * math.pi
			local nrm = V(0, math.sin(t) / 7.6, -math.cos(t) / 11).Unit
			K.Bar(arch, "ArchSpike", p, p + nrm * 1.1, .14, .14, IRON, M.CorrodedMetal)
			K.Part(arch, "ArchSpikeTip", V(.1, .34, .34), CF(p + nrm * 1.3) * ANG(math.atan2(nrm.Z, nrm.Y), 0, 0) * ANG(math.pi / 4, 0, 0), IRON:Lerp(C(80, 76, 90), .3), M.CorrodedMetal)
		end
	end
	-- glow ribbon under the inner arc
	for i = 3, 10 do
		K.Bar(arch, "ArchGlow", inner[i] - V(0, .26, 0), inner[i + 1] - V(0, .26, 0), .12, .1, GLOW, M.Neon)
	end
	local apex = LT + 7.6
	local crest = K.Model(static, "Crest")
	bigBone(crest, V(GX + .9, apex + .4, CZ - 4.6), V(GX + .9, apex + 3.6, CZ + 4.6), .62, BONE_DARK, V(1, 0, 0))
	bigBone(crest, V(GX + 1.1, apex + 3.6, CZ - 4.6), V(GX + 1.1, apex + .4, CZ + 4.6), .62, BONE_DARK, V(1, 0, 0))
	local skull = dogSkull(crest, CF(GX + .1, apex - .3, CZ) * FACE_X, 1.45, GREEN, .8)
	skull.Name = "CrestSkull"
	local cr = K.Part(crest, "CrestPerch", V(.3, .3, .3), CF(GX + .2, apex + 2.6, CZ), BONE, M.SmoothPlastic, { Transparency = 1 })
	K.Attach(cr, "CrowPerch", CF(0, .2, 0))
	for _, sgn in { -1, 1 } do
		local tip = K.Part(crest, "CrestPerch", V(.3, .3, .3), CF(GX + 1, apex + 4.3, Z(sgn, 5.1)), BONE, M.SmoothPlastic, { Transparency = 1 })
		K.Attach(tip, "CrowPerch", CF(0, .1, 0))
	end
	-- chains draped from the crest down to the lintel ends
	for _, sgn in { -1, 1 } do
		chain(arch, V(GX - .4, apex - .4, Z(sgn, 1.6)), V(GX - .6, LT + .3, Z(sgn, 9.4)), 1.1, .6)
	end

	------------------------------------------------------------------------------------------------ cobweb (upper corner of the opening)
	do
		local o = V(GX - 1.0, 21.15, Z(1, HALF + .55))
		local ends = {}
		for i = 0, 4 do
			local a = math.rad(i * 22.5)
			local e = o + V(0, -math.cos(a) * 3.4, -math.sin(a) * 3.4)
			table.insert(ends, e)
			K.Bar(deco, "Cobweb", o, e, .05, .05, C(220, 225, 235), M.SmoothPlastic, { Transparency = .35 })
		end
		for ring = 1, 2 do
			local f = ring * .36
			for i = 1, #ends - 1 do
				K.Bar(deco, "Cobweb", o:Lerp(ends[i], f), o:Lerp(ends[i + 1], f), .04, .04, C(220, 225, 235), M.SmoothPlastic, { Transparency = .45 })
			end
		end
	end

	------------------------------------------------------------------------------------------------ the leaves
	local function leaf(sgn)
		local lm = K.Model(gate, sgn < 0 and "LeafL" or "LeafR")
		lm.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams as a whole: never on a client without its HingeStile
		local hz = Z(sgn, HALF - .3) -- hinge line just off the pillar
		local W = HALF - .4
		local function at(u, y, xo)
			return V(GX + (xo or 0), y, hz - sgn * u)
		end
		local function col()
			return IRON:Lerp(RUST, rng:NextNumber(0, .45))
		end
		local y0 = .85
		local function topY(u)
			local t = u / W
			return 15.4 + 1.25 * math.sin(t * math.pi / 2)
		end
		local hinge = K.Part(lm, "HingeStile", V(.5, 15.4 - y0 + .4, .5), CF(at(.25, (y0 + 15.8) / 2)), IRON, M.CorrodedMetal)
		lm.PrimaryPart = hinge
		K.Part(lm, "MeetingStile", V(.46, topY(W) - y0 + .5, .46), CF(at(W - .23, (y0 + topY(W) + .5) / 2)), IRON, M.CorrodedMetal)
		local prevTop = at(.25, topY(.25))
		for _, u in { 3, 6, W - .23 } do
			local p = at(u, topY(u))
			K.Bar(lm, "TopRail", prevTop, p, .34, .4, col(), M.CorrodedMetal).Size += V(0, 0, .3)
			prevTop = p
		end
		for _, y in { y0 + .2, 5.3, 12.1 } do
			K.Part(lm, "LeafRail", V(.3, .36, W - .3), CF(at(W / 2, y)), col(), M.CorrodedMetal)
		end
		-- rusty kick plate with rivets and a bone emblem
		K.Part(lm, "KickPlate", V(.14, 4.7, W - .9), CF(at(W / 2, y0 + 2.6)), RUST:Lerp(IRON, .3), M.CorrodedMetal)
		for _, u in { .9, W / 2, W - .9 } do
			for _, y in { y0 + .7, 4.8 } do
				K.Ball(lm, "Rivet", .26, CF(at(u, y, -.1)), IRON, M.CorrodedMetal)
			end
		end
		bigBone(lm, at(W / 2 - 1.6, y0 + 2.6, -.18), at(W / 2 + 1.6, y0 + 2.6, -.18), .3, BONE_DARK, V(1, 0, 0))
		-- bars with spear tips
		local nb = 8
		for i = 1, nb do
			local u = .55 + (i - .5) * (W - 1.0) / nb
			local top = topY(u) + 1.05
			K.Part(lm, "LeafBar", V(.18, top - 5.3, .18), CF(at(u, (5.3 + top) / 2)), IRON, M.CorrodedMetal)
			K.Part(lm, "LeafSpear", V(.1, .46, .46), CF(at(u, top + .2)) * ANG(math.pi / 4, 0, 0), IRON:Lerp(C(90, 84, 96), .35), M.CorrodedMetal)
		end
		-- medallion: ring + emblem (L = crescent moon with a star, R = dog skull)
		local mc = at(W / 2, 8.7, -.12)
		local R = 2.05
		local seg = 12
		for i = 1, seg do
			local a0, a1 = (i - 1) / seg * math.pi * 2, i / seg * math.pi * 2
			K.Bar(lm, "MedallionRing", mc + V(0, math.sin(a0) * R, math.cos(a0) * R), mc + V(0, math.sin(a1) * R, math.cos(a1) * R), .3, .3, RUST:Lerp(P.Gold, .25), M.CorrodedMetal).Size += V(0, 0, .16)
		end
		K.CylX(lm, "MedallionBack", .1, R * 2 - .2, CF(mc + V(-.02, 0, 0)), C(30, 22, 40), M.SmoothPlastic)
		-- yard-side emblem (seen when leaving): a crescent on both leaves
		local mb = mc + V(.24, 0, 0)
		K.CylX(lm, "MedallionMoonBack", .12, 2.4, CF(mb + V(.1, 0, 0)), BONE_DARK, M.SmoothPlastic)
		K.CylX(lm, "MedallionMoonBackCut", .12, 2.1, CF(mb + V(.15, .22, sgn * .58)), C(30, 22, 40), M.SmoothPlastic)
		if sgn < 0 then
			K.CylX(lm, "MedallionMoon", .12, 2.6, CF(mc + V(-.1, 0, 0)), BONE, M.SmoothPlastic)
			K.CylX(lm, "MedallionMoonCut", .12, 2.25, CF(mc + V(-.15, .25, -sgn * .62)), C(30, 22, 40), M.SmoothPlastic)
			K.Part(lm, "MedallionStar", V(.1, .5, .5), CF(mc + V(-.24, .35, -sgn * .78)) * ANG(math.pi / 4, 0, 0), GLOW, M.Neon)
		else
			dogSkull(lm, CF(mc + V(-.05, -.95, 0)) * FACE_X, .58, GREEN, .35).Name = "MedallionSkull"
		end
		-- scrollwork band under the top rail
		for _, uc in { 2.2, W - 2.0 } do
			local c0 = at(uc, 13.65, -.02)
			local pts = {}
			for k = 0, 6 do
				local a = k / 6 * math.pi * 1.6 + .3
				local r = .95 - k * .1
				table.insert(pts, c0 + V(0, math.sin(a) * r, math.cos(a) * r * -sgn))
			end
			for k = 1, #pts - 1 do
				K.Bar(lm, "Scroll", pts[k], pts[k + 1], .14, .16, IRON, M.CorrodedMetal).Size += V(0, 0, .08)
			end
		end
		-- hinge straps with ball ends
		for _, y in { 2.6, 8.6, 14.6 } do
			K.Part(lm, "HingeStrap", V(.16, .52, 2.4), CF(at(1.25, y, -.2)), RUST, M.CorrodedMetal)
			K.Ball(lm, "StrapEnd", .5, CF(at(2.45, y, -.22)), RUST, M.CorrodedMetal)
		end
		-- broken chain hanging from the meeting stile (+ padlock on L)
		local cTop = at(W - .3, 9.6, -.32)
		chain(lm, cTop, cTop - V(0, sgn < 0 and 3.2 or 2.2, 0) + V(0, 0, sgn * .3), 0, .5)
		if sgn < 0 then
			local pl = cTop - V(0, 3.75, 0) + V(0, 0, sgn * .3)
			K.Part(lm, "Padlock", V(.4, .95, .8), CF(pl), C(110, 84, 44), M.CorrodedMetal)
			K.Part(lm, "PadlockKey", V(.08, .28, .14), CF(pl - V(.21, .1, 0)), P.Ink, M.SmoothPlastic)
		end
		lm:SetAttribute("HwGateLeaf", sgn < 0 and "L" or "R")
		lm:SetAttribute("OpenAngle", 100)
		lm:SetAttribute("OpenSign", sgn < 0 and 1 or -1)
		return lm
	end
	leaf(-1)
	leaf(1)

	------------------------------------------------------------------------------------------------ wing walls, plaque, braziers
	local function wing(sgn)
		local m = K.Model(static, sgn < 0 and "WingL" or "WingR")
		local zIn = Z(sgn, HALF + 3.2 + 2.7) -- outer face of the pillar plinth
		local zOut = Z(sgn, HALF + 17.3 - 2.6) -- inner face of the end pier
		local zEnd = Z(sgn, HALF + 17.3 - 1.3) -- end pier centre (fence continues behind it)
		local len = math.abs(zIn - zOut)
		local zm = (zIn + zOut) / 2
		local WX = 34.7
		K.Part(m, "WingFooting", V(2.4, .6, len), CF(WX, FY + .3, zm), STONE_DARK, M.Cobblestone, { Solid = true })
		K.Part(m, "WingWall", V(1.8, 8.0, len), CF(WX, FY + 4.3, zm), STONE:Lerp(STONE_DARK, .2), M.Cobblestone, { Solid = true })
		K.Part(m, "WingCoping", V(2.3, .45, len + .2), CF(WX, FY + 8.52, zm), STONE_DARK, M.Slate, { Solid = true })
		K.Wedge(m, "WingSweep", V(2.1, 1.6, len), CF(WX, FY + 9.55, zm) * ANG(0, sgn < 0 and 0 or math.pi, 0), STONE_DARK, M.Slate, { Solid = true })
		for _, y in { 3.0, 5.6 } do
			K.Part(m, "WingCourse", V(1.92, .26, len - .1), CF(WX, FY + y, zm), STONE_DARK, M.Slate)
		end
		-- end pier
		local ex = 34.0
		K.Part(m, "EndPierFoot", V(2.6, .7, 2.7), CF(ex, FY + .35, zEnd), STONE_DARK, M.Cobblestone, { Solid = true })
		K.Part(m, "EndPierShaft", V(2.4, 5.6, 2.4), CF(ex, FY + .7 + 2.8, zEnd), STONE, M.Cobblestone, { Solid = true })
		local cap = K.Part(m, "EndPierCap", V(2.9, .5, 2.9), CF(ex, FY + 6.55, zEnd), STONE_DARK, M.Slate, { Solid = true })
		K.Attach(cap, "CrowPerch", CF(.9, .25, sgn * .9))
		-- green-flame brazier
		local bt = FY + 6.8
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + .4
			K.Bar(m, "BrazierLeg", V(ex + math.cos(a) * .9, bt, zEnd + math.sin(a) * .9), V(ex + math.cos(a) * 1.15, bt + 1.1, zEnd + math.sin(a) * 1.15), .16, .16, IRON, M.CorrodedMetal)
		end
		K.CylY(m, "BrazierBowl", .7, 2.5, CF(ex, bt + 1.35, zEnd), IRON:Lerp(RUST, .35), M.CorrodedMetal)
		K.CylY(m, "BrazierBowlBase", .35, 1.6, CF(ex, bt + .95, zEnd), IRON, M.CorrodedMetal)
		K.CylY(m, "BrazierRim", .22, 2.8, CF(ex, bt + 1.75, zEnd), IRON:Lerp(RUST, .2), M.CorrodedMetal)
		K.CylY(m, "BrazierCoals", .12, 2.2, CF(ex, bt + 1.82, zEnd), C(60, 90, 50), M.Neon, { Transparency = .1 })
		local flames = {}
		for k, f in { { 0, 0, 2.3, .95 }, { .45, .2, 1.7, .7 }, { -.4, -.15, 1.5, .62 }, { .1, -.45, 1.3, .55 }, { -.2, .48, 1.1, .5 } } do
			local fl = K.Ellipsoid(m, "BrazierFlame", V(f[4], f[3], f[4]), CF(ex + f[1], bt + 1.85 + f[3] / 2, zEnd + f[2]) * ANG(f[2] * .3, 0, -f[1] * .3),
				k == 1 and C(190, 255, 170) or GREEN, M.Neon, { Attrs = { HwBrazier = true } })
			table.insert(flames, fl)
		end
		K.Light(flames[1], GREEN, 20, 1.3)
		lights += 1
		-- draped chain from the pillar to the end pier
		if sgn > 0 then -- (the left wing carries the plaque)
			chain(m, V(33.65, 9.2, Z(sgn, HALF + 5.15)), V(33.0, 6.2, zEnd - sgn * 1.2), 1.0, .62)
		end
		-- small pumpkins + candles at the wall foot (yard side, greeting players who come in)
		K.Ellipsoid(m, "WingPumpkin", V(1.6, 1.15, 1.6), CF(37.0, FY + .5, zm + sgn * 1.4), P.Pumpkin:Lerp(P.PumpkinDark, .25), M.SmoothPlastic)
		K.CylY(m, "WingPumpkinStem", .4, .2, CF(37.0, FY + 1.18, zm + sgn * 1.4) * ANG(.2, 0, .1), P.Stem, M.Wood)
		K.Ellipsoid(m, "WingPumpkin", V(1.1, .8, 1.1), CF(36.7, FY + .36, zm + sgn * 2.7), P.Pumpkin:Lerp(P.PumpkinDark, .45), M.SmoothPlastic)
		K.Candles(m, CF(36.9, FY + .02, zm - sgn * .6), 3, rng, { Light = false, Spread = .5 })
		return m, zm
	end
	local wl, zmL = wing(-1)
	local wr, zmR = wing(1)

	-- the plaque NIGHT OF THE BURIED MOON (Layout.Gate.Plaque, on the left wing, faces -X)
	do
		local pq = G.Plaque
		local px = 33.8 -- wall front face
		local pm = K.Model(wl, "Plaque")
		local plate = K.Part(pm, "PlaquePlate", V(.2, 2.6, 6.0), CF(px - .1, pq.Y, pq.Z), C(36, 20, 54), M.SmoothPlastic)
		for _, y in { pq.Y - 1.4, pq.Y + 1.4 } do
			K.Part(pm, "PlaqueFrame", V(.3, .26, 6.5), CF(px - .15, y, pq.Z), C(150, 108, 52), M.Metal)
		end
		for _, dz in { -3.12, 3.12 } do
			K.Part(pm, "PlaqueFrame", V(.3, 3.06, .26), CF(px - .15, pq.Y, pq.Z + dz), C(150, 108, 52), M.Metal)
			K.Ball(pm, "PlaqueBolt", .34, CF(px - .32, pq.Y + 1.4, pq.Z + dz), C(180, 140, 70), M.Metal)
			K.Ball(pm, "PlaqueBolt", .34, CF(px - .32, pq.Y - 1.4, pq.Z + dz), C(180, 140, 70), M.Metal)
		end
		K.Sign(plate, Enum.NormalId.Left, "NIGHT OF THE BURIED MOON", C(255, 214, 120), { PixelsPerStud = 28, StrokeColor = C(20, 8, 30), W = .9, H = .78 })
		-- purple halo behind the bronze frame
		K.Part(pm, "PlaqueHalo", V(.1, 3.5, 7.0), CF(px - .05, pq.Y, pq.Z), GLOW, M.Neon)
	end
	-- glowing paw medallion on the right wing
	do
		local pz = Z(1, 575 - G.Plaque.Z) -- mirror of the plaque
		local px = 33.8
		local pm = K.Model(wr, "PawMedallion")
		K.CylX(pm, "PawStone", .35, 3.6, CF(px - .17, 6, pz), STONE_LIGHT, M.Slate)
		K.CylX(pm, "PawInset", .1, 3.0, CF(px - .38, 6, pz), C(34, 24, 48), M.Slate)
		K.Ellipsoid(pm, "PawPad", V(.14, 1.05, 1.25), CF(px - .44, 5.55, pz), GLOW, M.Neon)
		for _, t in { { -.78, .45 }, { -.3, .85 }, { .3, .85 }, { .78, .45 } } do
			K.Ellipsoid(pm, "PawToe", V(.14, .5, .42), CF(px - .44, 5.75 + t[2], pz + t[1]), GLOW, M.Neon)
		end
	end

	------------------------------------------------------------------------------------------------ lanterns
	-- purple lanterns hanging over the threshold from brackets on the pillars' inner faces
	for _, sgn in { -1, 1 } do
		local zf = Z(sgn, HALF + 1.0) -- pillar inner face
		local zl = Z(sgn, HALF - .55)
		local m = K.Model(deco, "GateLanternBracket")
		K.Part(m, "BracketPlate", V(.9, 1.6, .16), CF(34.6, 16.2, zf - sgn * .08), IRON, M.CorrodedMetal)
		K.Bar(m, "BracketArm", V(34.6, 16.6, zf - sgn * .1), V(34.6, 16.6, zl), .2, .2, IRON, M.CorrodedMetal)
		K.Bar(m, "BracketBrace", V(34.6, 15.5, zf - sgn * .1), V(34.6, 16.6, zl + sgn * .5), .14, .14, IRON, M.CorrodedMetal)
		K.Bar(m, "LanternHanger", V(34.6, 16.6, zl), V(34.6, 16.15, zl), .1, .1, IRON, M.CorrodedMetal)
		K.Lantern(deco, CF(34.6, 14.5, zl), C(176, 92, 240), "Purple", { Range = 16, Brightness = 1.1 })
		lights += 1
		-- green lantern on the yard-side face of the pillar
		local zc = Z(sgn, HALF + 3.2)
		K.Part(m, "BracketPlate", V(.16, 1.6, .9), CF(GX + 2.38, 11.4, zc), IRON, M.CorrodedMetal)
		K.Bar(m, "BracketArm", V(GX + 2.4, 11.8, zc), V(GX + 3.6, 11.8, zc), .2, .2, IRON, M.CorrodedMetal)
		K.Bar(m, "LanternHanger", V(GX + 3.6, 11.8, zc), V(GX + 3.6, 11.35, zc), .1, .1, IRON, M.CorrodedMetal)
		K.Lantern(deco, CF(GX + 3.6, 9.7, zc), GREEN, "Green", { Range = 18, Brightness = 1.0 })
		lights += 1
	end

	if ctx.Note then
		ctx.Note(string.format("Gate: %d parts, %d lights", K.Count(gate), lights))
	end
	return gate
end

return Gate
