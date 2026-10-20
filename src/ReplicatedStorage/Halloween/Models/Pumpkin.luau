-- Pumpkin / ghost / candy props of NIGHT OF THE BURIED MOON (ReplicatedStorage.Halloween.Models.Pumpkin).
-- Pure builders (server and client; also run offline by tools/hw_wp5_preview.luau). Only Part / Ball / Cylinder / Wedge:
-- no SpecialMeshes, lights or particles, so the models survive ScaleTo, ViewportFrames and the server's pad projection.
--   Pumpkin.Block(tier, opts?) -> Model   PUMPKIN / CURSED PUMPKIN lucky block, LuckyBlockVisuals contract:
--       name tier..'LuckyBlock', PrimaryPart 'RootPart' (core ball, pivot = body centre = origin), authored bottom
--       y = -3.1, width <= 7, ScaleTo(.8) applied, attributes LuckyVisual / LuckyRank / LuckyShowStyle / GroundLocal,
--       Attachments 'LuckyCore' + 'DogLabelAnchor'. Named parts the show animates (client PumpkinBlockFX):
--       'PumpkinLobe' (the ribbed body), 'PumpkinStem', 'PumpkinEye' / 'PumpkinNose' / 'PumpkinMouth' (dark carved
--       holes the FX lights), 'PumpkinRim' (the lighter cut flesh around them), 'PumpkinCrack' (hidden glow lines the FX reveals), 'PumpkinBase' (the pedestal),
--       'PumpkinFlame' (cursed: purple fire tongues), 'PumpkinRune' (cursed: glowing runes).
--       opts = {Lit = true} lights the face (Neon) for previews / props.
--   Pumpkin.Ghost(size?) -> Model         a little sheet ghost (PrimaryPart 'GhostRoot' at the head centre; 'GhostHem'
--       parts wave, 'GhostEye' / 'GhostMouth' are the face); size = height in studs (default 3).
--   Pumpkin.Candy(color?) -> Model        a wrapped candy (PrimaryPart 'CandyCore'), about 1.6 studs long.
--   Pumpkin.Jack(size?, opts?) -> Model   a standalone jack-o'-lantern prop standing on y = 0 (size = width, default 2);
--       opts = {Lit = false} for an unlit one, {Cursed = true} for the purple variant.
local Pumpkin = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local SCALE = 0.8
local FOOT = -3.1

Pumpkin.Styles = {
	Pumpkin = {
		Lobe = rgb(246, 124, 26), Lobe2 = rgb(222, 98, 18), Lobe3 = rgb(255, 150, 44), Core = rgb(150, 56, 10),
		Hole = rgb(48, 18, 8), Lit = rgb(255, 200, 70), Stem = rgb(92, 104, 40), Stem2 = rgb(70, 82, 30),
		Leaf = rgb(104, 160, 52), Vine = rgb(76, 128, 40), Crack = rgb(255, 214, 110), Rim = rgb(255, 186, 100),
		Base = rgb(212, 172, 88), Base2 = rgb(176, 136, 62), Band = rgb(118, 80, 44),
	},
	CursedPumpkin = {
		Lobe = rgb(74, 36, 106), Lobe2 = rgb(52, 24, 78), Lobe3 = rgb(94, 50, 130), Core = rgb(20, 8, 30),
		Hole = rgb(12, 4, 18), Lit = rgb(150, 255, 120), Stem = rgb(30, 20, 34), Stem2 = rgb(20, 12, 24),
		Leaf = rgb(40, 52, 30), Vine = rgb(34, 24, 40), Crack = rgb(150, 255, 120), Thorn = rgb(70, 60, 76), Rim = rgb(128, 82, 168),
		Base = rgb(52, 48, 62), Base2 = rgb(36, 32, 46), Band = rgb(80, 74, 90),
		Fire = rgb(176, 70, 255), Fire2 = rgb(226, 150, 255), Rune = rgb(190, 90, 255), Glow = rgb(120, 255, 110),
	},
}

---------------------------------------------------------------------------------------------------------------------
-- builder
---------------------------------------------------------------------------------------------------------------------
local function newBuilder(name: string)
	local m = Instance.new("Model")
	m.Name = name
	local b = { Model = m, Bottom = 0, Top = 0, Count = 0 }
	function b.part(pname: string, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, class: string?)
		local p = Instance.new(class or "Part") :: any
		p.Name = pname
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or M.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local ey = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
		b.Bottom = math.min(b.Bottom, cf.Y - ey)
		b.Top = math.max(b.Top, cf.Y + ey)
		b.Count += 1
		p.Parent = m
		return p
	end
	function b.ball(pname: string, pos: Vector3, d: number, color: Color3, mat: Enum.Material?)
		return b.part(pname, CF(pos), V3(d, d, d), color, mat, Enum.PartType.Ball)
	end
	-- cylinder from a to b (Roblox cylinders run along X)
	function b.rod(pname: string, a: Vector3, c: Vector3, d: number, color: Color3, mat: Enum.Material?)
		local dir = c - a
		local len = math.max(dir.Magnitude, 0.05)
		local x = dir.Unit
		local up = math.abs(x.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local z = x:Cross(up).Unit
		local y = z:Cross(x).Unit
		return b.part(pname, CFrame.fromMatrix((a + c) / 2, x, y, z), V3(len, d, d), color, mat, Enum.PartType.Cylinder)
	end
	-- thin flat box along a -> c lying on a surface with normal n
	function b.strip(pname: string, a: Vector3, c: Vector3, n: Vector3, width: number, thick: number, color: Color3, mat: Enum.Material?)
		local dir = c - a
		local x = dir.Unit
		local y = n:Cross(x).Unit
		return b.part(pname, CFrame.fromMatrix((a + c) / 2, x, y, x:Cross(y)), V3(dir.Magnitude + width * 0.4, width, thick), color, mat)
	end
	-- isosceles triangle in the XY plane of cf (point up unless down), two wedges back to back, thickness t
	function b.triangle(pname: string, cf: CFrame, w: number, h: number, t: number, color: Color3, mat: Enum.Material?, down: boolean?)
		local flip = down and ANG(0, 0, math.pi) or CF()
		-- a WedgePart is full height at its local +Z: each half turns that edge to the middle
		b.part(pname, cf * flip * CF(-w / 4, 0, 0) * ANG(0, math.pi / 2, 0), V3(t, h, w / 2), color, mat, nil, "WedgePart")
		b.part(pname, cf * flip * CF(w / 4, 0, 0) * ANG(0, -math.pi / 2, 0), V3(t, h, w / 2), color, mat, nil, "WedgePart")
	end
	return b
end

---------------------------------------------------------------------------------------------------------------------
-- the pumpkin body (shared by blocks and props): 3-ball lobes in a ring around a core ball at `c` (unit size: the
-- block's body is 6.8 wide, 4.1 tall; k scales it)
---------------------------------------------------------------------------------------------------------------------
local LOBES = 10
local function body(b, c: Vector3, k: number, s, rootName: string?)
	local core = b.ball(rootName or "PumpkinCore", c, 4.0 * k, s.Core)
	for i = 0, LOBES - 1 do
		local a = (i + 0.5) / LOBES * math.pi * 2 + math.pi / 2 -- a lobe groove sits on the face centre line (-Z)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local col = i % 2 == 0 and s.Lobe or s.Lobe2
		b.ball("PumpkinLobe", c + dir * 2.1 * k, 2.66 * k, col)
		b.ball("PumpkinLobe", c + dir * 1.72 * k + Vector3.new(0, 0.94 * k, 0), 2.16 * k, col:Lerp(s.Lobe3, 0.25))
		b.ball("PumpkinLobe", c + dir * 1.74 * k + Vector3.new(0, -0.98 * k, 0), 2.08 * k, col:Lerp(s.Core, 0.12))
	end
	return core
end

-- surface point of the body in direction (azimuth a, height y) — for faces, cracks and vines
local function surface(c: Vector3, k: number, a: number, y: number): (Vector3, Vector3)
	local r
	local ay = math.abs(y)
	if ay <= 0.85 then
		r = 2.1 + math.sqrt(math.max(0, 1.33 * 1.33 - y * y)) * 0.98
	else
		r = 1.72 + math.sqrt(math.max(0, 1.08 * 1.08 - (ay - 0.96) ^ 2))
	end
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local p = c + (dir * r + Vector3.new(0, y, 0)) * k
	local n = (dir * (1 - math.min(ay, 1.6) / 2.4) + Vector3.new(0, y / 2.6, 0)).Unit
	return p, n
end

-- carved jack-o'-lantern face on the -Z side; lit = Neon glow colour, else the dark hole colour
local function face(b, c: Vector3, k: number, s, lit: boolean, cursed: boolean)
	local col = lit and s.Lit or s.Hole
	local mat = lit and M.Neon or M.SmoothPlastic
	local front = -math.pi / 2
	for _, side in ipairs({ -1, 1 }) do
		local a = front + side * 0.36
		local p, n = surface(c, k, a, 0.55)
		local cf = CFrame.lookAt(p + n * 0.05 * k, p + n * 2) * ANG(0, math.pi, 0) * ANG(0, 0, rad(side * (cursed and -14 or 10)))
		local rimCf = cf * CF(0, 0, -0.04 * k) -- (local +Z points out of the pumpkin here)
		if cursed then
			-- slanted, angry eyes
			b.triangle("PumpkinEye", cf * ANG(0, 0, rad(side * 18)), 1.16 * k, 0.86 * k, 0.12 * k, col, mat, true)
			b.triangle("PumpkinRim", rimCf * ANG(0, 0, rad(side * 18)), 1.42 * k, 1.08 * k, 0.1 * k, s.Rim, M.SmoothPlastic, true)
		else
			b.triangle("PumpkinEye", cf, 1.14 * k, 0.98 * k, 0.12 * k, col, mat)
			b.triangle("PumpkinRim", rimCf * CF(0, -0.04 * k, 0), 1.4 * k, 1.2 * k, 0.1 * k, s.Rim, M.SmoothPlastic)
		end
	end
	do
		local p, n = surface(c, k, front, 0.0)
		local cf = CFrame.lookAt(p + n * 0.06 * k, p + n * 2) * ANG(0, math.pi, 0)
		b.triangle("PumpkinNose", cf, 0.5 * k, 0.42 * k, 0.12 * k, col, mat)
		b.triangle("PumpkinRim", cf * CF(0, -0.03 * k, -0.04 * k), 0.7 * k, 0.58 * k, 0.1 * k, s.Rim, M.SmoothPlastic)
	end
	-- the grin: a curved row of segments with two notched teeth
	local segs = cursed and 7 or 6
	for i = 0, segs - 1 do
		local t = (i + 0.5) / segs * 2 - 1
		local a = front + t * 0.62
		local y = -0.5 + math.abs(t) ^ 1.6 * 0.42
		local p, n = surface(c, k, a, y)
		local h = (cursed and (0.42 - math.abs(t) * 0.14) or (0.4 - math.abs(t) * 0.2)) * k
		local cf = CFrame.lookAt(p + n * 0.05 * k, p + n * 2) * ANG(0, math.pi, 0) * ANG(0, 0, rad(-t * 26))
		b.part("PumpkinMouth", cf, V3(0.78 * k, h, 0.12 * k), col, mat)
		b.part("PumpkinRim", cf * CF(0, 0, -0.04 * k), V3(0.8 * k, h + 0.2 * k, 0.1 * k), s.Rim, M.SmoothPlastic)
	end
	for _, t in ipairs(cursed and { -0.55, -0.15, 0.25, 0.62 } or { -0.32, 0.32 }) do
		local a = front + t * 0.62
		local y = -0.5 + math.abs(t) ^ 1.6 * 0.42
		local p, n = surface(c, k, a, y + (cursed and -0.1 or 0.12))
		local cf = CFrame.lookAt(p + n * 0.09 * k, p + n * 2) * ANG(0, math.pi, 0)
		if cursed then
			b.triangle("PumpkinTooth", cf * ANG(0, 0, 0), 0.22 * k, 0.26 * k, 0.1 * k, s.Lobe, M.SmoothPlastic)
		else
			b.part("PumpkinTooth", cf, V3(0.22 * k, 0.2 * k, 0.1 * k), s.Lobe, M.SmoothPlastic)
		end
	end
end

-- hidden glow cracks across the front and sides (PumpkinBlockFX fades them in before the burst)
local function cracks(b, c: Vector3, k: number, s)
	local rng = Random.new(41)
	local starts = { { -1.9, 0.9 }, { -1.15, -0.2 }, { -2.05, -0.95 }, { 1.95, 0.35 }, { 1.1, 1.05 }, { 0.35, -1.25 }, { 2.6, -0.4 }, { -2.7, 0.2 } }
	for _, st in ipairs(starts) do
		local a = -math.pi / 2 + st[1] * 0.55
		local y = st[2]
		local p0, n0 = surface(c, k, a, y)
		for _ = 1, 2 do
			local a2 = a + rng:NextNumber(-0.22, 0.22)
			local y2 = math.clamp(y + rng:NextNumber(-0.6, 0.6), -1.5, 1.5)
			local p1, n1 = surface(c, k, a2, y2)
			local seg = b.strip("PumpkinCrack", p0 + n0 * 0.06 * k, p1 + n1 * 0.06 * k, (n0 + n1).Unit, 0.13 * k, 0.05 * k, s.Crack, M.Neon)
			seg.Transparency = 1
			a, y, p0, n0 = a2, y2, p1, n1
		end
	end
end

-- curled stem with leaves (and thorns when cursed)
local function stem(b, top: Vector3, k: number, s, cursed: boolean)
	local p0 = top + Vector3.new(0, -0.25 * k, 0)
	local p1 = top + Vector3.new(0.12 * k, 0.75 * k, 0.05 * k)
	local p2 = top + Vector3.new(0.5 * k, 1.35 * k, -0.08 * k)
	local p3 = top + Vector3.new(1.05 * k, 1.5 * k, -0.2 * k)
	b.rod("PumpkinStem", p0, p1, 0.72 * k, s.Stem, M.Wood)
	b.rod("PumpkinStem", p1, p2, 0.56 * k, s.Stem2, M.Wood)
	b.rod("PumpkinStem", p2, p3, 0.38 * k, s.Stem2, M.Wood)
	b.ball("PumpkinStem", p1, 0.62 * k, s.Stem, M.Wood)
	b.ball("PumpkinStem", p2, 0.48 * k, s.Stem2, M.Wood)
	-- curly tendril
	local prev = top + Vector3.new(-0.3 * k, 0.3 * k, 0.1 * k)
	for i = 1, 5 do
		local a = i * 1.15
		local p = top + Vector3.new(-0.55 * k - math.sin(a) * 0.45 * k, 0.3 * k + i * 0.2 * k, 0.1 * k + math.cos(a) * 0.45 * k)
		b.rod("PumpkinVine", prev, p, 0.12 * k, s.Vine)
		prev = p
	end
	-- leaves (two flat wedges each, a broad leaf shape)
	for _, L in ipairs({ { -1.3, 0.35, 0.5, 25 }, { 1.05, 0.25, 0.95, -35 } }) do
		local at = top + Vector3.new(L[1] * k, L[2] * k, L[3] * k)
		local cf = CF(at) * ANG(0, rad(L[4]), 0) * ANG(rad(-34), 0, rad(L[1] > 0 and -22 or 22))
		b.part("PumpkinLeaf", cf, V3(1.5 * k, 0.07 * k, 1.0 * k), s.Leaf, M.SmoothPlastic)
		b.part("PumpkinLeaf", cf * CF(0.2 * k, 0, 0.62 * k) * ANG(0, rad(28), 0), V3(0.7 * k, 0.06 * k, 0.5 * k), s.Leaf, M.SmoothPlastic)
		b.part("PumpkinLeaf", cf * CF(0, 0.045 * k, 0), V3(1.3 * k, 0.05 * k, 0.08 * k), s.Vine, M.SmoothPlastic)
	end
	if cursed then
		for i, t in ipairs({ 0.25, 0.55, 0.8 }) do
			local p = p0:Lerp(p2, t)
			local side = i % 2 == 0 and 1 or -1
			b.triangle("PumpkinThorn", CF(p + Vector3.new(side * 0.3 * k, 0, 0)) * ANG(0, 0, rad(-side * 70)), 0.22 * k, 0.42 * k, 0.16 * k, s.Thorn, M.Slate)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- pedestals
---------------------------------------------------------------------------------------------------------------------
local function strawBase(b, k: number, s)
	-- a round straw bale (lying cylinder disc stack) with twine, scattered straw and two little pumpkins
	local y = FOOT + 0.55
	b.part("PumpkinBase", CF(0, y, 0) * ANG(0, 0, rad(90)), V3(1.1, 5.9, 5.9), s.Base, M.Fabric, Enum.PartType.Cylinder)
	b.part("PumpkinBase", CF(0, y + 0.5, 0) * ANG(0, 0, rad(90)), V3(0.12, 5.6, 5.6), s.Base2, M.Fabric, Enum.PartType.Cylinder)
	for _, r in ipairs({ 2.2, 1.2 }) do
		for i = 0, 5 do
			local a = (i + (r > 2 and 0 or 0.5)) / 6 * math.pi * 2
			b.part("PumpkinBase", CF(math.cos(a) * r, y + 0.57, math.sin(a) * r) * ANG(0, -a, 0), V3(0.9, 0.06, 0.12), s.Base2, M.Fabric)
		end
	end
	b.part("PumpkinBase", CF(0, y - 0.05, 0) * ANG(0, 0, rad(90)), V3(0.2, 5.98, 5.98), s.Band, M.Fabric, Enum.PartType.Cylinder)
	-- straw wisps poking out of the rim
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2 + 0.2
		b.part("PumpkinBase", CF(math.cos(a) * 2.98, y + 0.15, math.sin(a) * 2.98) * ANG(0, -a, rad(70 + (i % 3) * 12)), V3(0.7, 0.07, 0.07), s.Base2, M.Fabric)
	end
	-- two tiny pumpkins on the bale's edge
	for _, P in ipairs({ { -2.35, -1.75, 0.95 }, { 2.45, -1.4, 0.8 } }) do
		local c = Vector3.new(P[1], y + 0.55 + P[3] * 0.32, P[2])
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			b.ball("PumpkinMini", c + Vector3.new(math.cos(a), 0, math.sin(a)) * P[3] * 0.24, P[3] * 0.62, i % 2 == 0 and s.Lobe or s.Lobe2)
		end
		b.rod("PumpkinMini", c + Vector3.new(0, P[3] * 0.22, 0), c + Vector3.new(0.05, P[3] * 0.5, 0), 0.12, s.Stem)
	end
end

local function altarBase(b, k: number, s)
	-- a cracked gravestone altar: two stepped slabs, rune grooves glowing violet, bones and chains at the feet
	local y = FOOT + 0.55
	b.part("PumpkinBase", CF(0, FOOT + 0.25, 0), V3(6.1, 0.5, 6.1), s.Base2, M.Slate)
	b.part("PumpkinBase", CF(0, FOOT + 0.78, 0), V3(5.3, 0.56, 5.3), s.Base, M.Slate)
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			b.part("PumpkinBase", CF(x * 2.75, FOOT + 0.62, z * 2.75) * ANG(0, rad(45), 0), V3(0.85, 0.85, 0.85), s.Band, M.Slate)
			b.ball("PumpkinBase", Vector3.new(x * 2.75, FOOT + 1.2, z * 2.75), 0.5, s.Band, M.Slate)
		end
	end
	-- rune ring on the top slab (violet glow) and a cracked seam
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		if i % 4 ~= 1 then
			b.part("PumpkinRune", CF(math.cos(a) * 2.35, FOOT + 1.07, math.sin(a) * 2.35) * ANG(0, -a, 0), V3(0.12, 0.04, 0.62), s.Rune, M.Neon)
		end
	end
	for _, f in ipairs({ { 0, -1 }, { 1, 0 } }) do
		local face = Vector3.new(f[1], 0, f[2])
		local side = Vector3.new(f[2], 0, -f[1])
		local p = face * 2.66 + Vector3.new(0, FOOT + 0.78, 0)
		b.part("PumpkinRune", CF(p + side * 0.4) * CFrame.fromMatrix(Vector3.zero, side, Vector3.new(0, 1, 0)) * ANG(0, 0, rad(60)), V3(0.6, 0.06, 0.04), s.Glow, M.Neon)
		b.part("PumpkinRune", CF(p + side * 0.62 + Vector3.new(0, -0.12, 0)) * CFrame.fromMatrix(Vector3.zero, side, Vector3.new(0, 1, 0)) * ANG(0, 0, rad(-40)), V3(0.42, 0.06, 0.04), s.Glow, M.Neon)
	end
	-- bones and a skull at the feet
	local boneCol = rgb(222, 212, 186)
	for _, B in ipairs({ { -2.4, -3.05, 30 }, { 2.2, -2.85, -20 } }) do
		local cf = CF(B[1], FOOT + 1.12, B[2] * 0.85) * ANG(0, rad(B[3]), 0)
		b.part("PumpkinBone", cf * ANG(0, 0, rad(90)), V3(1.2, 0.22, 0.22), boneCol, M.SmoothPlastic, Enum.PartType.Cylinder)
		for _, x in ipairs({ -0.62, 0.62 }) do
			for _, z in ipairs({ -0.1, 0.1 }) do
				b.ball("PumpkinBone", (cf * CF(x, 0, z)).Position, 0.3, boneCol)
			end
		end
	end
	local skull = CF(1.9, FOOT + 1.42, -2.0) * ANG(0, rad(-20), 0)
	b.ball("PumpkinSkull", skull.Position, 0.68, boneCol)
	b.part("PumpkinSkull", skull * CF(0, -0.28, -0.14), V3(0.44, 0.22, 0.32), boneCol)
	for _, x in ipairs({ -0.14, 0.14 }) do
		b.ball("PumpkinSkull", (skull * CF(x, 0.03, -0.27)).Position, 0.18, rgb(20, 8, 26))
	end
	-- thorny vines crawling over the altar edge
	local prev = Vector3.new(-2.9, FOOT + 1.1, 1.6)
	for i = 1, 6 do
		local p = Vector3.new(-2.9 + i * 0.38, FOOT + 1.12 + math.sin(i * 1.3) * 0.12, 1.6 + math.cos(i * 1.1) * 0.5 + i * 0.25)
		b.rod("PumpkinVine", prev, p, 0.16, s.Vine)
		if i % 2 == 0 then
			b.triangle("PumpkinThorn", CF(p + Vector3.new(0, 0.14, 0)), 0.14, 0.26, 0.1, s.Thorn, M.Slate)
		end
		prev = p
	end
end

-- static purple fire tongues licking up around the cursed pumpkin (the FX adds real flames): each tongue is two
-- crossed flat triangles with a bright core
local function cursedFire(b, c: Vector3, s)
	for i = 0, 5 do
		local a = (i + 0.5) / 6 * math.pi * 2 + 0.3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local h = (i % 2 == 0) and 1.9 or 1.35
		local base = c + dir * 2.95 + Vector3.new(0, -1.95, 0)
		local cf = CF(base + Vector3.new(0, h / 2, 0)) * ANG(0, -a, 0) * ANG(0, 0, rad(-8))
		b.triangle("PumpkinFlame", cf, 0.62, h, 0.1, s.Fire, M.Neon)
		b.triangle("PumpkinFlame", cf * ANG(0, math.pi / 2, 0), 0.62, h, 0.1, s.Fire, M.Neon)
		b.triangle("PumpkinFlame", cf * CF(0, -h * 0.12, -0.06) * ANG(0, rad(45), 0), 0.34, h * 0.62, 0.08, s.Fire2, M.Neon)
	end
end

-- permanent cursed glow seams (always visible: the curse leaks out)
local function cursedSeams(b, c: Vector3, k: number, s)
	for _, st in ipairs({ { 0.9, 0.3, 1.3, -0.6 }, { 4.2, 0.7, 4.5, -0.3 }, { 2.4, -0.2, 2.7, 0.9 } }) do
		local p0, n0 = surface(c, k, st[1], st[2])
		local p1, n1 = surface(c, k, st[3], st[4])
		b.strip("PumpkinGlowSeam", p0 + n0 * 0.05, p1 + n1 * 0.05, (n0 + n1).Unit, 0.1, 0.05, s.Glow, M.Neon)
	end
end

function Pumpkin.Block(tier: string, opts: { [string]: any }?): Model
	opts = opts or {}
	local cursed = tier == "Cursed Pumpkin" or opts.Style == "CursedPumpkin"
	local style = cursed and "CursedPumpkin" or "Pumpkin"
	local s = Pumpkin.Styles[style]
	local b = newBuilder(tostring(tier) .. "LuckyBlock")
	local m = b.Model
	local c = Vector3.new(0, 0, 0) -- body centre = pivot (RootPart)
	local root = body(b, c, 1, s, "RootPart")
	m.PrimaryPart = root
	face(b, c, 1, s, opts.Lit == true, cursed)
	cracks(b, c, 1, s)
	stem(b, Vector3.new(0, 1.95, 0), 1, s, cursed)
	if cursed then
		altarBase(b, 1, s)
		cursedFire(b, c, s)
		cursedSeams(b, c, 1, s)
	else
		strawBase(b, 1, s)
	end
	local rank = opts.Rank or (cursed and 5 or 4)
	m:SetAttribute("LuckyVisual", true)
	m:SetAttribute("LuckyRank", rank)
	m:SetAttribute("LuckyShowStyle", style)
	m:SetAttribute("PumpkinParts", b.Count)
	local core = Instance.new("Attachment")
	core.Name = "LuckyCore"
	core.Position = Vector3.zero
	core.Parent = root
	local label = Instance.new("Attachment")
	label.Name = "DogLabelAnchor"
	label.Position = Vector3.new(0, b.Top + 1.5 / SCALE, 0)
	label.Parent = root
	local ok = pcall(function()
		m:ScaleTo(SCALE)
	end)
	if not ok then
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local rel = root.CFrame:ToObjectSpace(p.CFrame)
				p.Size *= SCALE
				p.CFrame = root.CFrame * (rel - rel.Position + rel.Position * SCALE)
			elseif p:IsA("Attachment") then
				p.Position *= SCALE
			end
		end
	end
	m:SetAttribute("GroundLocal", Vector3.new(0, b.Bottom * SCALE, 0))
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- props
---------------------------------------------------------------------------------------------------------------------
function Pumpkin.Jack(size: number?, opts: { [string]: any }?): Model
	opts = opts or {}
	local k = (size or 2) / 6.8
	local s = Pumpkin.Styles[opts.Cursed and "CursedPumpkin" or "Pumpkin"]
	local b = newBuilder("JackOLantern")
	local c = Vector3.new(0, 2.05 * k, 0)
	body(b, c, k, s, "PumpkinCore")
	-- the pivot stands on the ground (y = 0) under the pumpkin
	local root = b.part("JackRoot", CF(0, 0.1 * k, 0), V3(0.2, 0.2, 0.2), s.Core)
	root.Transparency = 1
	b.Model.PrimaryPart = root
	face(b, c, k, s, opts.Lit ~= false, opts.Cursed == true)
	stem(b, c + Vector3.new(0, 1.95 * k, 0), k, s, opts.Cursed == true)
	b.Model:SetAttribute("PumpkinParts", b.Count)
	return b.Model
end

function Pumpkin.Ghost(size: number?): Model
	local k = (size or 3) / 3
	local b = newBuilder("PumpkinGhost")
	local white = rgb(238, 246, 255)
	local shade = rgb(208, 226, 248)
	local headC = Vector3.new(0, 0, 0)
	local root = b.ball("GhostRoot", headC, 1.5 * k, white)
	root.Transparency = 0.15
	b.Model.PrimaryPart = root
	-- the sheet: stacked balls flaring out, a wavy hem of balls
	for i, row in ipairs({ { -0.5, 1.62 }, { -0.98, 1.78 }, { -1.38, 1.86 } }) do
		local p = b.ball("GhostBody", headC + Vector3.new(0, row[1] * k, 0.06 * i * k), row[2] * k, i == 3 and shade or white)
		p.Transparency = 0.15
	end
	-- the sheet's wavy hem flares out
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = b.ball("GhostHem", headC + Vector3.new(math.cos(a) * 0.78 * k, (-1.95 - (i % 2) * 0.16) * k, math.sin(a) * 0.78 * k + 0.2 * k), 0.66 * k, shade)
		p.Transparency = 0.2
	end
	-- little arms
	for _, side in ipairs({ -1, 1 }) do
		local p = b.ball("GhostArm", headC + Vector3.new(side * 0.85 * k, -0.55 * k, -0.05 * k), 0.52 * k, white)
		p.Transparency = 0.15
	end
	-- face: big dark eyes with a glint, an open mouth
	for _, side in ipairs({ -1, 1 }) do
		b.part("GhostEye", CF(headC + Vector3.new(side * 0.26 * k, 0.12 * k, -0.66 * k)), V3(0.24 * k, 0.36 * k, 0.12 * k), rgb(22, 14, 34), M.SmoothPlastic)
		b.ball("GhostEye", headC + Vector3.new(side * 0.26 * k + 0.05 * k, 0.2 * k, -0.73 * k), 0.08 * k, rgb(255, 255, 255), M.Neon)
	end
	b.part("GhostMouth", CF(headC + Vector3.new(0, -0.22 * k, -0.68 * k)), V3(0.22 * k, 0.26 * k, 0.1 * k), rgb(22, 14, 34), M.SmoothPlastic)
	b.Model:SetAttribute("PumpkinParts", b.Count)
	return b.Model
end

function Pumpkin.Candy(color: Color3?): Model
	local col = color or rgb(255, 128, 24)
	local b = newBuilder("PumpkinCandy")
	local core = b.ball("CandyCore", Vector3.zero, 0.78, col)
	b.Model.PrimaryPart = core
	local light = col:Lerp(rgb(255, 255, 255), 0.55)
	-- swirl stripes
	for i, a in ipairs({ -30, 30 }) do
		b.part("CandyStripe", CF(0, 0, 0) * ANG(0, 0, rad(a)) * ANG(0, rad(i * 40), 0), V3(0.12, 0.8, 0.8), light, M.SmoothPlastic, Enum.PartType.Cylinder)
	end
	-- twisted wrapper ends (wedge fans) on both sides
	for _, side in ipairs({ -1, 1 }) do
		b.rod("CandyTwist", Vector3.new(side * 0.36, 0, 0), Vector3.new(side * 0.52, 0, 0), 0.22, light)
		for _, flip in ipairs({ 0, math.pi }) do
			b.part("CandyWrapper", CF(side * 0.68, 0, 0) * ANG(flip, 0, 0) * ANG(0, side > 0 and math.pi / 2 or -math.pi / 2, 0) * CF(0, 0.12, 0),
				V3(0.08, 0.3, 0.36), side > 0 and col or col:Lerp(rgb(0, 0, 0), 0.12), M.SmoothPlastic, nil, "WedgePart")
		end
	end
	b.Model:SetAttribute("PumpkinParts", b.Count)
	return b.Model
end

return Pumpkin
