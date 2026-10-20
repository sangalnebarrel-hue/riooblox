-- Shared helpers of the WP2 Dead Yard builders (Street, Graveyard, Crypts, BrokenLab, Props):
-- ServerStorage.HalloweenBuild.YardKit. Build-time only, required by the builders next to it; builds on Kit.
local K = require(script.Parent.Kit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local Y = {}

Y.GLOW = { Orange = C(255, 150, 54), Green = C(134, 255, 110), Purple = C(190, 112, 255) }
Y.GLOW_DIM = { Orange = C(176, 84, 26), Green = C(70, 160, 60), Purple = C(110, 58, 170) }
Y.WEB = C(226, 228, 236)
Y.BARK = C(62, 50, 52)

-- deterministic PRNG with Random's NextNumber/NextInteger interface (Lune's roblox lib has no Random, so K.Rng fails
-- inside the build sim; Kit helpers that take an rng accept this object as well)
function Y.Rng(seed: number)
	local st = math.floor(seed) % 2147483647
	if st <= 0 then
		st += 2147483646
	end
	local r = {}
	function r:NextNumber(lo, hi)
		st = (st * 16807) % 2147483647
		local u = st / 2147483647
		if lo == nil then
			return u
		end
		return lo + (hi - lo) * u
	end
	function r:NextInteger(lo, hi)
		return math.min(hi, lo + math.floor(self:NextNumber() * (hi - lo + 1)))
	end
	return r
end

function Y.Solid(extra)
	local t = { Solid = true }
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

-- attachment at a WORLD position (upright, world-aligned) on a part
function Y.AttachAt(part: BasePart, name: string, worldPos: Vector3, attrs)
	return K.Attach(part, name, part.CFrame:Inverse() * CF(worldPos), attrs)
end

-- triangle in the local YZ plane (thickness along X), base centred at `base`, apex up
function Y.GableTri(m, name, base, width, height, thick, color, mat, isSolid)
	K.Wedge(m, name, V3(thick, height, width / 2), base * CF(0, height / 2, -width / 4), color, mat, isSolid and Y.Solid() or nil)
	K.Wedge(m, name, V3(thick, height, width / 2), base * CF(0, height / 2, width / 4) * ANG(0, PI, 0), color, mat, isSolid and Y.Solid() or nil)
end

-- corner cobweb: corner at cf origin, spreads along +X and -Y in cf's XY plane (5 thin strands)
function Y.Cobweb(m, cf, size)
	for k = 0, 2 do
		local a = -k * PI / 4
		K.Bar(m, "Cobweb", cf.Position, cf * V3(math.cos(a) * size, math.sin(a) * size, 0), .05, .05, Y.WEB, M.SmoothPlastic, { Transparency = .3 })
	end
	local r = .62
	local p0 = cf * V3(size * r, 0, 0)
	local p1 = cf * V3(math.cos(-PI / 4) * size * r * .9, math.sin(-PI / 4) * size * r * .9, 0)
	local p2 = cf * V3(0, -size * r, 0)
	K.Bar(m, "Cobweb", p0, p1, .045, .045, Y.WEB, M.SmoothPlastic, { Transparency = .3 })
	K.Bar(m, "Cobweb", p1, p2, .045, .045, Y.WEB, M.SmoothPlastic, { Transparency = .3 })
end

-- jack-o'-lantern without a PointLight unless asked (lights are budgeted)
function Y.Pumpkin(m, cf, size, opts)
	opts = opts or {}
	if opts.Light == nil then
		opts.Light = false
	end
	opts.Lobes = opts.Lobes or 5
	return K.Pumpkin(m, cf, size, opts)
end

-- blocky skull (faces -Z of cf); eyeColor = Neon glow, nil = dark sockets
function Y.Skull(m, cf, s, eyeColor, bone)
	bone = bone or P.Bone
	K.Ball(m, "Skull", s, cf, bone, M.SmoothPlastic)
	K.Part(m, "SkullJaw", V3(s * .62, s * .32, s * .5), cf * CF(0, -s * .45, -s * .16), bone:Lerp(P.BoneDark, .4), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		K.Ball(m, "SkullEye", s * .3, cf * CF(sx * s * .21, s * .03, -s * .38), eyeColor or C(24, 16, 26), eyeColor and M.Neon or M.SmoothPlastic)
	end
end

-- gnarled dead tree: flared roots, bent 3-segment trunk, reaching branches with twigs. opts: Color, Branches,
-- Hollow (glowing eyes in a trunk hollow), Perches (CrowPerch count), Bats (BatRoost), Lean, Spread (max horizontal reach)
function Y.Tree(parent, cf, height, rng, opts)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "DeadTree")
	local bark = opts.Color or Y.BARK
	local darkBark = bark:Lerp(P.Ink, .35)
	local base = cf.Position
	local spread = opts.Spread or height * .5
	for k = 1, 4 do
		local a = k / 4 * PI * 2 + rng:NextNumber(-.4, .4)
		K.Rod(m, "TreeRoot", base + V3(0, height * .07, 0), base + V3(math.cos(a) * height * .17, -.15, math.sin(a) * height * .17),
			height * .055, darkBark, M.Wood)
	end
	local p = base
	local lean = opts.Lean or V3(rng:NextNumber(-.18, .18), 0, rng:NextNumber(-.18, .18))
	local dir = (V3(0, 1, 0) + lean).Unit
	local thick = height * .085
	local joints = {}
	local trunkParts = {}
	for k = 1, 3 do
		local len = height * (k == 1 and .24 or .17)
		local q = p + dir * len
		local seg = K.Rod(m, "TreeStem", p, q, thick, bark:Lerp(darkBark, k * .1), M.Wood, k <= 2 and Y.Solid() or nil)
		table.insert(trunkParts, seg)
		K.Ball(m, "TreeKnot", thick * 1.05, CF(q), bark, M.Wood)
		joints[k] = { q, dir, thick }
		dir = (dir + V3(rng:NextNumber(-.4, .4), 0, rng:NextNumber(-.4, .4))).Unit
		thick *= .76
		p = q
	end
	local tips = {}
	local branchParts = {}
	local function clampReach(q)
		local off = V3(q.X - base.X, 0, q.Z - base.Z)
		if off.Magnitude > spread then
			off = off.Unit * spread
			return V3(base.X + off.X, q.Y, base.Z + off.Z)
		end
		return q
	end
	local function branch(from, d, len, th, depth)
		local to = clampReach(from + d * len)
		local part = K.Rod(m, depth == 0 and "TreeBranch" or "TreeTwig", from, to, th, depth == 0 and bark or darkBark, M.Wood)
		if depth == 0 then
			K.Ball(m, "TreeKnot", th * 1.05, CF(to), bark, M.Wood)
			table.insert(branchParts, { part, from, to })
		end
		if depth >= 2 then
			table.insert(tips, { part, to })
			return
		end
		local n = depth == 0 and 2 or rng:NextInteger(1, 2)
		for _ = 1, n do
			local d2 = (d + V3(rng:NextNumber(-.9, .9), rng:NextNumber(-.25, .45), rng:NextNumber(-.9, .9))).Unit
			branch(to, d2, len * rng:NextNumber(.5, .68), th * .6, depth + 1)
		end
	end
	local nb = opts.Branches or 3
	for b = 1, nb do
		local j = joints[b == 1 and 2 or 3]
		local a = b / nb * PI * 2 + rng:NextNumber(-.5, .5)
		local d = (V3(math.cos(a), rng:NextNumber(.35, .9), math.sin(a))).Unit
		branch(j[1], d, height * rng:NextNumber(.24, .32), j[3] * .78, 0)
	end
	-- crows on a few twig tips, bats under a main branch
	local perches = opts.Perches or 2
	for k = 1, math.min(perches, #tips) do
		local t = tips[math.floor((k - 1) * #tips / perches) + 1]
		Y.AttachAt(t[1], "CrowPerch", t[2] + V3(0, .2, 0))
	end
	if opts.Bats ~= false and branchParts[1] then
		local bp = branchParts[1]
		Y.AttachAt(bp[1], "BatRoost", bp[2]:Lerp(bp[3], .6) - V3(0, .4, 0))
	end
	if opts.Hollow then
		local seg = trunkParts[1]
		local hd = (opts.HollowDir or V3(0, 0, -1)).Unit
		local c = base + V3(0, height * .14, 0) + hd * height * .036
		local hcf = K.Look(c, c + hd)
		K.Ellipsoid(m, "TreeHollow", V3(height * .05, height * .075, height * .03), hcf, C(14, 8, 18), M.SmoothPlastic)
		local eye = opts.HollowColor or Y.GLOW.Orange
		K.Ball(m, "HollowEye", height * .012, hcf * CF(-height * .012, height * .008, -height * .012), eye, M.Neon)
		K.Ball(m, "HollowEye", height * .012, hcf * CF(height * .012, height * .008, -height * .012), eye, M.Neon)
		local _ = seg
	end
	m:SetAttribute("Height", height)
	return m, tips, branchParts
end

-- tombstone facing -Z of cf (its engraving faces the cf LookVector). style 1..9. returns the model
local NAMES_FONT_LI = .75
function Y.Tombstone(parent, cf, style, rng, text, opts)
	opts = opts or {}
	local m = K.Model(parent, "Tombstone")
	local stone = (opts.Color or P.Stone):Lerp(P.StoneDark, rng:NextNumber(0, .55))
	local lean = CF(0, 0, 0) * ANG(rng:NextNumber(-.07, .07), 0, rng:NextNumber(-.09, .09))
	local w, h = rng:NextNumber(2.2, 2.9), rng:NextNumber(2.7, 3.7)
	local body = cf * lean
	local function engrave(part, t, face, hgt)
		if not t then
			return
		end
		local g = K.Sign(part, face or Enum.NormalId.Front, t, C(44, 40, 52), { PixelsPerStud = 24, Stroke = false, H = hgt or .45, W = .8, LightInfluence = NAMES_FONT_LI })
		if opts.NoTranslate then
			g:SetAttribute("NoTranslate", true)
		end
	end
	if style ~= 7 then
		K.Part(m, "GraveBase", V3(w + .8, .45, 1.6), cf * CF(0, .22, 0), P.StoneDark, M.Slate, Y.Solid())
	end
	local top
	if style == 1 then -- rounded slab
		local sh = h - w / 2
		local slab = K.Part(m, "GraveSlab", V3(w, sh, .55), body * CF(0, .45 + sh / 2, 0), stone, M.Slate, Y.Solid())
		K.CylX(m, "GraveArch", .55, w, body * CF(0, .45 + sh, 0) * ANG(0, PI / 2, 0), stone, M.Slate)
		engrave(slab, text)
		top = body * CF(0, .45 + h, 0)
	elseif style == 2 then -- celtic cross
		K.Part(m, "GraveCross", V3(.6, h + .7, .5), body * CF(0, .45 + (h + .7) / 2, 0), stone, M.Slate, Y.Solid())
		K.Part(m, "GraveCross", V3(w * .95, .55, .5), body * CF(0, .45 + h * .7, 0), stone, M.Slate)
		K.CylZ(m, "GraveRing", .3, 1.5, body * CF(0, .45 + h * .7, .05), stone:Lerp(P.StoneDark, .3), M.Slate)
		top = body * CF(0, .45 + h + .7, 0)
	elseif style == 3 then -- gothic pointed slab
		local slab = K.Part(m, "GraveSlab", V3(w, h, .6), body * CF(0, .45 + h / 2, 0), stone, M.Slate, Y.Solid())
		Y.GableTri(m, "GraveTop", body * CF(0, .45 + h, 0) * ANG(0, PI / 2, 0), w, .9, .6, stone, M.Slate)
		engrave(slab, text)
		top = body * CF(0, .45 + h + .9, 0)
	elseif style == 4 then -- paw grave with a bone on top
		local slab = K.Part(m, "GraveSlab", V3(w * .9, h * .7, .5), body * CF(0, .45 + h * .35, 0), stone, M.Slate, Y.Solid())
		K.Bone(m, body * CF(0, .45 + h * .7 + .25, 0), w * .8, P.Bone)
		engrave(slab, "🐾", nil, .6)
		top = body * CF(0, .45 + h * .7 + .5, 0)
	elseif style == 5 then -- obelisk
		K.Part(m, "GravePlinth", V3(1.7, .8, 1.7), body * CF(0, .85, 0), stone:Lerp(P.StoneDark, .2), M.Slate, Y.Solid())
		local shaft = K.Part(m, "GraveObelisk", V3(1.1, h + 1.6, 1.1), body * CF(0, 1.25 + (h + 1.6) / 2, 0), stone, M.Slate, Y.Solid())
		Y.GableTri(m, "GraveTop", body * CF(0, 1.25 + h + 1.6, 0) * ANG(0, PI / 2, 0), 1.1, .8, 1.1, stone, M.Slate)
		engrave(shaft, text, Enum.NormalId.Front, .3)
		top = body * CF(0, 1.25 + h + 2.4, 0)
	elseif style == 6 then -- broken slab, top half fallen in the grass
		local sh = h * .55
		local slab = K.Part(m, "GraveSlab", V3(w, sh, .55), body * CF(0, .45 + sh / 2, 0), stone, M.Slate, Y.Solid())
		K.Wedge(m, "GraveBreak", V3(.55, .5, w), body * CF(0, .45 + sh + .25, 0) * ANG(0, PI / 2, 0), stone, M.Slate)
		K.Part(m, "GraveShard", V3(w * .95, h * .4, .5), cf * CF(.3, .5, -1.5) * ANG(-PI / 2 + .15, .4, 0), stone:Lerp(P.Moss, .15), M.Slate)
		engrave(slab, text, nil, .5)
		top = body * CF(0, .45 + sh + .5, 0)
	elseif style == 7 then -- wooden cross with a dog collar
		local wood = P.WoodOld:Lerp(P.WoodDark, rng:NextNumber(0, .5))
		K.Part(m, "GraveMound", V3(1.8, .4, 3), cf * CF(0, .2, 1.2), C(70, 54, 46), M.Ground)
		K.Part(m, "WoodCross", V3(.42, h + .4, .3), body * CF(0, (h + .4) / 2, 0), wood, M.WoodPlanks, Y.Solid())
		K.Part(m, "WoodCross", V3(w * .85, .38, .3), body * CF(0, h * .68, -.05), wood, M.WoodPlanks)
		K.CylY(m, "DogCollar", .22, 1.0, body * CF(0, h * .52, 0) * ANG(.25, 0, 0), C(170, 40, 50), M.Fabric)
		K.CylZ(m, "CollarTag", .06, .36, body * CF(0, h * .52 - .45, -.38), P.Gold, M.Metal)
		top = body * CF(0, h + .4, 0)
	elseif style == 8 then -- little doghouse tomb
		local hw = w + .4
		local hb = K.Part(m, "DoghouseTomb", V3(hw, 2.2, 2.2), body * CF(0, 1.55, .3), stone, M.Slate, Y.Solid())
		K.Part(m, "DoghouseRoof", V3(hw + .4, .3, 1.6), body * CF(0, 3.05, -.35) * ANG(-.62, 0, 0), stone:Lerp(P.StoneDark, .3), M.Slate)
		K.Part(m, "DoghouseRoof", V3(hw + .4, .3, 1.6), body * CF(0, 3.05, .95) * ANG(.62, 0, 0), stone:Lerp(P.StoneDark, .3), M.Slate)
		K.Part(m, "DoghouseDoor", V3(1, 1.3, .1), body * CF(0, 1.1, -.82), C(20, 14, 24), M.SmoothPlastic)
		K.CylZ(m, "DoghouseDoorTop", .1, 1, body * CF(0, 1.75, -.82), C(20, 14, 24), M.SmoothPlastic)
		local plate = K.Part(m, "DoghousePlate", V3(1.5, .45, .1), body * CF(0, 2.5, -.82), P.BoneDark, M.Slate)
		engrave(plate, text, nil, .8)
		local _ = hb
		top = body * CF(0, 3.6, .3)
	else -- 9: standing stone bone
		local col = P.Bone:Lerp(P.StoneLight, .55)
		K.CylY(m, "BoneStone", h, .75, body * CF(0, .45 + h / 2, 0), col, M.Marble, Y.Solid())
		for _, sy in ipairs({ .45 + .2, .45 + h }) do
			K.Ball(m, "BoneStoneKnob", .95, body * CF(-.32, sy, 0), col, M.Marble)
			K.Ball(m, "BoneStoneKnob", .95, body * CF(.32, sy, 0), col, M.Marble)
		end
		top = body * CF(0, .45 + h + .4, 0)
	end
	if style ~= 7 and style ~= 9 and rng:NextNumber() < .6 then
		K.Part(m, "GraveMoss", V3(w * .55, .12, .4), body * CF(rng:NextNumber(-.3, .3), .5, -.3), P.Moss, M.Grass)
	end
	return m, top
end

-- sitting stone dog statue (faces -Z of cf, base on cf). opts: Scale, Bowed (mourning, head down), Color, EyeColor
function Y.DogStatue(parent, cf, opts)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "DogStatue")
	local k = opts.Scale or 1
	local stone = opts.Color or C(176, 174, 188)
	local shade = stone:Lerp(P.Ink, .22)
	local function at(x, y, z)
		return cf * CF(x * k, y * k, z * k)
	end
	K.Ellipsoid(m, "StatueHaunch", V3(2.8 * k, 2.3 * k, 2.9 * k), at(0, 1.15, .75), stone, M.Marble)
	K.Part(m, "StatueChest", V3(2 * k, 2.7 * k, 1.7 * k), at(0, 2.25, -.25) * ANG(.32, 0, 0), stone, M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "StatueLeg", V3(.6 * k, 2.3 * k, .62 * k), at(sx * .6, 1.15, -.95), stone, M.Marble)
		K.Part(m, "StatuePaw", V3(.76 * k, .4 * k, 1.05 * k), at(sx * .6, .2, -1.25), shade, M.Marble)
		K.Part(m, "StatueHindPaw", V3(.82 * k, .42 * k, 1.45 * k), at(sx * 1.25, .21, .35), shade, M.Marble)
	end
	local neckY = opts.Bowed and 3.55 or 3.85
	K.Part(m, "StatueNeck", V3(1.35 * k, 1.3 * k, 1.25 * k), at(0, neckY, -.55) * ANG(opts.Bowed and -.35 or .1, 0, 0), stone, M.Marble)
	K.Part(m, "StatueCollar", V3(1.5 * k, .3 * k, 1.4 * k), at(0, neckY - .35, -.5) * ANG(opts.Bowed and -.35 or .1, 0, 0), C(120, 96, 70), M.Metal)
	local head = at(0, opts.Bowed and 3.95 or 4.75, opts.Bowed and -1.15 or -.85) * ANG(opts.Bowed and -.6 or .05, 0, 0)
	K.Part(m, "StatueHead", V3(1.55 * k, 1.4 * k, 1.5 * k), head, stone, M.Marble)
	K.Part(m, "StatueMuzzle", V3(.92 * k, .78 * k, 1.35 * k), head * CF(0, -.25 * k, -1.2 * k), stone, M.Marble)
	K.Ball(m, "StatueNose", .42 * k, head * CF(0, -.02 * k, -1.88 * k), shade, M.Marble)
	K.Part(m, "StatueBrow", V3(1.62 * k, .3 * k, .42 * k), head * CF(0, .45 * k, -.66 * k), shade, M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "StatueEar", V3(.42 * k, 1.35 * k, .72 * k), head * CF(sx * .88 * k, -.3 * k, .15 * k) * ANG(0, 0, sx * .16), shade, M.Marble)
		if opts.EyeColor then
			K.Part(m, "StatueEye", V3(.32 * k, .22 * k, .06 * k), head * CF(sx * .38 * k, .18 * k, -.77 * k), opts.EyeColor, M.Neon)
		else
			K.Part(m, "StatueEye", V3(.42 * k, .08 * k, .06 * k), head * CF(sx * .38 * k, .2 * k, -.77 * k), C(40, 38, 48), M.SmoothPlastic)
		end
	end
	K.Rod(m, "StatueTail", (at(1.1, .3, 1.75)).Position, (at(1.8, .3, .3)).Position, .48 * k, stone, M.Marble)
	K.Rod(m, "StatueTail", (at(1.8, .3, .3)).Position, (at(1.55, .3, -.55)).Position, .42 * k, stone, M.Marble)
	K.Part(m, "StatueMoss", V3(1.3 * k, .1 * k, .9 * k), at(-.5, 2.3, .95) * ANG(0, .4, .35), P.Moss, M.Grass)
	return m, head
end

-- hanging ivy strand from `top` down to `bottom` (on a wall), a few leaf clusters
function Y.Vine(m, top: Vector3, bottom: Vector3, rng, out: Vector3?)
	out = out or V3(0, 0, 0)
	local a = top
	local leaf = C(54, 86, 52)
	for k = 1, 3 do
		local b = top:Lerp(bottom, k / 3) + out * .15 + V3(rng:NextNumber(-.35, .35), 0, rng:NextNumber(-.35, .35)) * (k < 3 and 1 or 0)
		K.Rod(m, "IvyVine", a, b, .14, C(60, 70, 44), M.Grass)
		local side = math.abs(out.X) > .5 and V3(0, 0, 1) or V3(1, 0, 0)
		for j = -1, 1, 2 do
			local w, h = rng:NextNumber(.55, .85), rng:NextNumber(.45, .7)
			local size = math.abs(out.X) > .5 and V3(.2, h, w) or (math.abs(out.Z) > .5 and V3(w, h, .2) or V3(w, h * .6, w))
			K.Ellipsoid(m, "IvyFoliage", size, CF(a:Lerp(b, .35 + j * .2) + out * .15 + side * j * rng:NextNumber(.3, .55)) * ANG(0, 0, j * .5),
				leaf:Lerp(P.Moss, rng:NextNumber(0, .6)), M.Grass)
		end
		a = b
	end
end

-- wrought-iron fence run a->b (on the ground), bars with spear finials; opts: Height, Spacing, Solid, Broken (0..1)
function Y.IronFence(m, a: Vector3, b: Vector3, opts, rng)
	opts = opts or {}
	local h = opts.Height or 2.6
	local len = (b - a).Magnitude
	local base = K.Look((a + b) / 2, b)
	local iron = opts.Color or P.Iron
	K.Part(m, "IronRail", V3(.12, .12, len), base * CF(0, .5, 0), iron, M.CorrodedMetal, opts.Solid and Y.Solid() or nil)
	K.Part(m, "IronRail", V3(.12, .12, len), base * CF(0, h - .35, 0), iron, M.CorrodedMetal)
	local n = math.max(1, math.floor(len / (opts.Spacing or 1.1)))
	for k = 0, n do
		if not (opts.Broken and rng and rng:NextNumber() < opts.Broken) then
			local z = -len / 2 + k * len / n
			K.Part(m, "IronBar", V3(.11, h, .11), base * CF(0, h / 2, z), iron, M.CorrodedMetal, opts.Solid and Y.Solid() or nil)
			if opts.Finials ~= false then
				K.Wedge(m, "IronSpear", V3(.08, .35, .2), base * CF(0, h + .17, z), iron, M.CorrodedMetal)
			end
		end
	end
	return base
end

-- small pile of bones (and maybe a skull)
function Y.BonePile(m, cf, rng, n, skull)
	for k = 1, n do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(0, .9)
		K.Bone(m, cf * CF(math.cos(a) * r, .2 + k * .06, math.sin(a) * r) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.2, .2)),
			rng:NextNumber(1, 1.6), P.Bone:Lerp(P.BoneDark, rng:NextNumber(0, .6)))
	end
	if skull then
		Y.Skull(m, cf * CF(.3, .45, -.2) * ANG(-.2, rng:NextNumber(-.6, .6), .1), .8, nil)
	end
end

-- invisible marker (part + attachment) for FX points on open ground
function Y.Marker(parent, name, pos, attrs)
	return K.Marker(parent, name, pos, attrs)
end

-- flush ring of Neon arc segments in the XZ plane of cf (summon circles, rune rings). opts: Fill (arc share of each
-- segment, .8), Phase (radians), H (thickness, .05), Transparency (.2), Name
function Y.RuneRing(m, cf, r, n, w, color, opts)
	opts = opts or {}
	local fill = opts.Fill or .8
	for i = 1, n do
		local a0 = (i - 1) / n * PI * 2 + (opts.Phase or 0)
		local a1 = a0 + fill / n * PI * 2
		K.Bar(m, opts.Name or "RuneRing", (cf * CF(math.cos(a0) * r, 0, math.sin(a0) * r)).Position, (cf * CF(math.cos(a1) * r, 0, math.sin(a1) * r)).Position,
			w, opts.H or .05, color, M.Neon, { Transparency = opts.Transparency or .2 })
	end
end

-- GIANT DOG SKULL in THE DOG statue's voxel-stepped language (faces -Z of cf, cf on the ground): five stacked cranium
-- tiers with a sagittal crest and occipital, a stepped brow ridge over deep sockets (dark recess, dim Neon halo, bright
-- Neon pupil), a nasal bridge sloping to the nasal cavity, cheek arches, upper incisors / fangs / molars, the lower jaw
-- dropped open from its hinge into a mud mound (chin half sunk), dark cracks, a glowing fissure and moss caps.
-- s = scale (1: cranium 6 wide, ~12.5 long, ~7 tall). opts: Eye / EyeDim (pupil + socket halo colours), Fissure (crack
-- glow colour), Light (range, or false = no PointLight; the light sits on the left pupil, which carries HwLantern =
-- opts.Lantern when given), Brightness, Lite (no molars, clods or small details: ~45 parts instead of ~75), Mound (false =
-- no mud), Tilt (nose-up radians, .22), Solid (false = nothing collides), Name. Returns the model and the cranium top.
function Y.GiantSkull(parent, cf, s, opts)
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "GiantSkull")
	local lite = opts.Lite == true
	local eye = opts.Eye or Y.GLOW.Green
	local HI, BONE, MID, DARK = C(242, 234, 212), C(226, 214, 186), C(204, 190, 158), C(174, 158, 126)
	local TOOTH, INK, SEAM = C(248, 244, 230), C(18, 10, 24), C(84, 68, 62)
	local SP = M.SmoothPlastic
	local U = cf * CF(0, 1.2 * s, 1.0 * s) * ANG(opts.Tilt or .22, 0, 0) -- upper skull: palate y 0, braincase front z 0
	local J = cf * CF(0, 2.0 * s, 2.5 * s) * ANG(-.27, 0, 0) -- lower jaw: hinge at the origin, chin toward -Z
	local function solid()
		return opts.Solid ~= false and Y.Solid() or nil
	end
	local function blk(f, name, x, y, z, sx, sy, sz, col, mat, props, rot)
		local c = f * CF(x * s, y * s, z * s)
		return K.Part(m, name, V3(sx * s, sy * s, sz * s), rot and c * rot or c, col, mat or SP, props)
	end
	local function wdg(f, name, x, y, z, sx, sy, sz, col, rot)
		local c = f * CF(x * s, y * s, z * s)
		return K.Wedge(m, name, V3(sx * s, sy * s, sz * s), rot and c * rot or c, col, SP)
	end
	local DOWN = ANG(PI, 0, 0) -- flipped wedge: a tooth pointing down
	-- braincase: five stepped tiers (darker low, lighter high), sagittal crest, occipital
	blk(U, "SkullBase", 0, .75, 2.3, 5.2, 1.5, 5.0, DARK, nil, solid())
	blk(U, "Cranium", 0, 2.15, 2.2, 6.0, 1.3, 4.6, MID, nil, solid())
	blk(U, "Cranium", 0, 3.3, 2.35, 5.2, 1.0, 4.4, BONE, nil, solid())
	blk(U, "CraniumDome", 0, 4.2, 2.55, 4.2, .8, 3.8, BONE)
	blk(U, "CraniumDome", 0, 4.9, 2.75, 3.0, .6, 3.0, HI)
	wdg(U, "SagittalCrest", 0, 5.55, 3.0, .7, .7, 3.6, HI)
	blk(U, "Occipital", 0, 2.5, 4.95, 3.6, 2.6, 1.0, MID)
	if not lite then
		blk(U, "OccipitalCrest", 0, 4.05, 5.0, 2.4, .6, .8, BONE)
	end
	-- stepped brow ridge over deep sockets: the dark recess sits ~.5 behind the brow, rims and cheek ridges
	blk(U, "BrowRidge", 0, 3.75, -.35, 5.6, .55, 1.2, BONE)
	blk(U, "BrowRidge", 0, 4.2, -.1, 4.4, .45, .9, HI)
	blk(U, "NasalBridge", 0, 2.6, -.5, 1.2, 2.0, 1.0, BONE)
	local pupil
	for _, sx in ipairs({ -1, 1 }) do
		blk(U, "EyeSocket", sx * 1.62, 2.75, -.32, 1.7, 1.45, .3, INK)
		blk(U, "SocketHalo", sx * 1.62, 2.72, -.5, 1.2, 1.0, .06, opts.EyeDim or Y.GLOW_DIM.Green, M.Neon)
		blk(U, "OrbitRim", sx * 2.7, 2.75, -.45, .55, 1.9, .95, MID)
		blk(U, "CheekRidge", sx * 1.7, 1.85, -.55, 2.0, .55, .95, MID)
		local p = K.Ball(m, "SocketGlow", .66 * s, U * CF(sx * 1.62 * s, 2.7 * s, -.58 * s), eye, M.Neon)
		if sx < 0 then
			pupil = p
		end
	end
	-- muzzle: three narrowing steps to the nose, sloping bridge, nasal cavity, maxilla sides, cheek arches
	blk(U, "Muzzle", 0, 1.05, -1.4, 3.8, 1.9, 2.4, BONE, nil, solid())
	blk(U, "Muzzle", 0, .9, -3.55, 3.1, 1.6, 2.1, BONE)
	blk(U, "MuzzleTip", 0, .8, -5.35, 2.5, 1.35, 1.7, HI)
	wdg(U, "SnoutBridge", 0, 2.45, -2.4, 1.9, 1.0, 4.4, BONE)
	blk(U, "NoseBone", 0, 1.68, -5.3, 1.9, .4, 1.5, BONE)
	blk(U, "NasalCavity", 0, 1.05, -6.22, 1.5, .95, .1, INK)
	if not lite then
		blk(U, "NasalSeptum", 0, 1.05, -6.27, .16, .95, .06, MID)
	end
	for _, sx in ipairs({ -1, 1 }) do
		blk(U, "Maxilla", sx * 1.72, .75, -2.7, .45, 1.2, 3.4, MID)
		K.Bar(m, "CheekArch", (U * CF(sx * 2.25 * s, 1.5 * s, -.7 * s)).Position, (U * CF(sx * 3.15 * s, 1.7 * s, 2.1 * s)).Position, .75 * s, .9 * s, MID, SP)
	end
	-- upper teeth (palate y 0) + the dark mouth behind them
	blk(U, "MouthDark", 0, -.35, -1.8, 3.0, .7, 4.0, INK)
	for _, sx in ipairs({ -1, 1 }) do
		wdg(U, "Fang", sx * 1.0, -.55, -5.0, .48, 1.5, .55, TOOTH, DOWN)
		if not lite then
			for k = 1, 3 do
				wdg(U, "Molar", sx * 1.5, -.18, -1.6 - k * .95, .42, .55, .75, TOOTH:Lerp(MID, .35), DOWN)
			end
		end
	end
	for k = 1, lite and 2 or 4 do
		local x = lite and (k == 1 and -.35 or .35) or (-.75 + (k - 1) * .5)
		wdg(U, "Incisor", x, -.12, -5.85, .32, .5, .32, TOOTH, DOWN)
	end
	-- lower jaw dropped open from the hinge, chin in the mound
	for _, sx in ipairs({ -1, 1 }) do
		K.Bar(m, "Mandible", (J * CF(sx * 2.3 * s, 0, .4 * s)).Position, (J * CF(sx * 1.0 * s, 0, -5.6 * s)).Position, .8 * s, 1.2 * s, DARK, SP)
		wdg(J, "CoronoidProcess", sx * 2.3, .95, .1, .6, 1.5, 1.3, MID)
		wdg(J, "LowerFang", sx * .95, .95, -5.55, .44, 1.2, .5, TOOTH)
		if not lite then
			for k = 1, 2 do
				wdg(J, "LowerTooth", sx * (1.25 + k * .2), .75, -4.6 + k * 1.1, .38, .55, .6, TOOTH:Lerp(MID, .3))
			end
		end
	end
	blk(J, "MandibleChin", 0, 0, -5.95, 2.6, 1.15, 1.1, MID)
	-- mud mound: one under the braincase, one burying the chin (+ clods, a stone, moss)
	if opts.Mound ~= false then
		local MUD = C(60, 46, 42)
		K.Ellipsoid(m, "SkullMound", V3(9 * s, 1.5 * s, 7.5 * s), cf * CF(0, -.15 * s, 2.6 * s) * ANG(0, .2, 0), MUD, M.Mud)
		K.Ellipsoid(m, "SkullMound", V3(6.4 * s, 1.3 * s, 5.2 * s), cf * CF(0, -.1 * s, -3.6 * s) * ANG(0, -.15, 0), MUD:Lerp(C(78, 60, 50), .5), M.Ground)
		if not lite then
			for k, c in ipairs({ { -3.4, -2.2, .9 }, { 3.0, -4.6, .7 }, { -2.6, -5.4, .55 }, { 3.9, 1.6, .8 }, { -4.2, 3.4, .65 } }) do
				K.Ball(m, "DirtClod", c[3] * s, cf * CF(c[1] * s, c[3] * .2 * s, c[2] * s), MUD:Lerp(P.Ink, k * .05), M.Mud)
			end
			K.Part(m, "Rubble", V3(1.1 * s, .6 * s, .9 * s), cf * CF(4.2 * s, .2 * s, -1.4 * s) * ANG(.2, .7, .1), P.StoneDark, M.Slate)
			K.Ellipsoid(m, "MoundMoss", V3(2.4 * s, .3 * s, 1.6 * s), cf * CF(-3.0 * s, .4 * s, 1.0 * s) * ANG(0, .5, 0), P.Moss, M.Grass)
		end
	end
	-- weathering: moss on the dome, dark cracks over the forehead steps, a glowing fissure on the left side
	blk(U, "SkullMoss", -.7, 5.28, 3.3, 2.3, .16, 1.7, P.Moss, M.Grass, nil, ANG(0, .3, 0))
	blk(U, "SkullCrack", .6, 4.9, 1.22, .12, .5, .08, SEAM, nil, nil, ANG(0, 0, .35))
	if not lite then
		blk(U, "SkullMoss", 1.7, 4.47, -.15, 1.5, .14, .7, P.Moss:Lerp(C(80, 110, 60), .4), M.Grass)
		blk(U, "SkullCrack", .95, 4.61, 1.5, .12, .06, 1.7, SEAM, nil, nil, ANG(0, .3, 0))
		blk(U, "SkullCrack", 3.02, 2.3, 3.3, .06, 1.0, .12, SEAM, nil, nil, ANG(.4, 0, 0))
		blk(U, "GlowFissure", -3.02, 2.2, 3.2, .06, 1.1, .12, opts.Fissure or Y.GLOW.Purple, M.Neon, nil, ANG(.45, 0, 0))
		blk(U, "GlowFissure", -2.62, 3.82, 3.0, .06, .06, 1.2, opts.Fissure or Y.GLOW.Purple, M.Neon, nil, ANG(0, .5, 0))
	end
	if opts.Light ~= false and pupil then
		K.Light(pupil, eye, opts.Light or 14, opts.Brightness or 1.2)
		if opts.Lantern then
			pupil:SetAttribute("HwLantern", opts.Lantern)
		end
	end
	local top = U * CF(0, 5.95 * s, 3.4 * s)
	K.Attach(K.Part(m, "SkullTop", V3(.2, .2, .2), top, HI, nil, { Transparency = 1 }), "CrowPerch", CF(0, .1, 0))
	return m, top
end

-- distance check against the gameplay points that must stay clear (Layout.DigPoints / OrePoints)
function Y.Keepout(L)
	local pts = {}
	for _, p in ipairs(L.DigPoints) do
		table.insert(pts, p)
	end
	for _, p in ipairs(L.OrePoints) do
		table.insert(pts, p)
	end
	return function(pos: Vector3, r: number): boolean
		for _, p in ipairs(pts) do
			local dx, dz = pos.X - p.X, pos.Z - p.Z
			if dx * dx + dz * dz < r * r then
				return false
			end
		end
		return true
	end
end

return Y
