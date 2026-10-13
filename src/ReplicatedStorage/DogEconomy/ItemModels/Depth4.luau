-- Depth 4 (Cursed Depths) find models: blackened iron, bone, blood red and sickly green / purple
-- glows. Each recipe builds one find around the origin, resting on Y = 0, front towards -Z, at the
-- size of its old voxel model (see ItemModels.luau and docs/ITEM_MODELS_D34.md).
-- b:Accent marks the signature parts that mutations recolour; b:Detail holds the small work that
-- the Lod 1 silhouette skips.
local V3 = Vector3.new
local CN = CFrame.new
local rad, cos, sin = math.rad, math.cos, math.sin

local function ang(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(rad(x), rad(y or 0), rad(z or 0))
end
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Colours of the depth.
local IRON = rgb(52, 48, 56)
local IRON_D = rgb(30, 28, 34)
local RUST = rgb(110, 70, 50)
local BONE = rgb(226, 214, 186)
local BONE_D = rgb(178, 164, 136)
local BLOOD = rgb(150, 14, 26)
local BLOOD_L = rgb(204, 30, 42)
local FLESH = rgb(118, 20, 32)
local GREEN = rgb(130, 255, 90)
local PURPLE = rgb(180, 80, 255)
local EMBER = rgb(255, 118, 30)
local WAX = rgb(32, 28, 36)
local INK = rgb(16, 14, 18)
local GOLD = rgb(214, 160, 54)
local IVORY = rgb(244, 236, 214)

-- A CFrame at `at` whose LookVector points at `target` (built with fromMatrix: same result in
-- Roblox and in Lune, no lookAt edge cases for vertical directions).
local function look(at: Vector3, target: Vector3): CFrame
	local dir = target - at
	if dir.Magnitude < 1e-6 then
		return CN(at)
	end
	dir = dir.Unit
	local up = if math.abs(dir.Y) > 0.98 then V3(0, 0, -1) else V3(0, 1, 0)
	local right = dir:Cross(up).Unit
	return CFrame.fromMatrix(at, right, right:Cross(dir))
end

-- Round rod from a to c.
local function rod(b: any, a: Vector3, c: Vector3, d: number, color: Color3, mat: string?): BasePart
	return b:Cyl(math.max((c - a).Magnitude, 0.02), d, look((a + c) / 2, c) * ang(0, 90, 0), color, mat)
end

-- Square bar from a to c (cracks, rune strokes, straps).
local function bar(b: any, a: Vector3, c: Vector3, w: number, color: Color3, mat: string?): BasePart
	return b:Box(V3(w, w, math.max((c - a).Magnitude, 0.02)), look((a + c) / 2, c), color, mat)
end

-- Organic segment: an ellipsoid of diameter d stretched from a to c (horns, fangs, tendrils).
local function blob(b: any, a: Vector3, c: Vector3, d: number, color: Color3, mat: string?, over: number?): BasePart
	local len = (c - a).Magnitude
	return b:Ellipsoid(V3(d, d, len + d * (over or 0.5)), look((a + c) / 2, c), color, mat)
end

-- Tapering chain of blobs through pts with diameters ds (one fewer than pts), colours lerped
-- from c0 to c1.
local function horn(b: any, pts: { Vector3 }, ds: { number }, c0: Color3, c1: Color3, mat: string?): { BasePart }
	local out = {}
	for i = 1, #pts - 1 do
		local t = (i - 1) / math.max(1, #pts - 2)
		table.insert(out, blob(b, pts[i], pts[i + 1], ds[i], c0:Lerp(c1, t), mat))
	end
	return out
end

-- Arc of rods in the local XY plane of cf (angles in degrees from local +X towards +Y).
local function arc(b: any, cf: CFrame, r: number, d: number, a0: number, a1: number, n: number, color: Color3, mat: string?): { BasePart }
	local out = {}
	local step = (a1 - a0) / n
	for i = 1, n do
		local t0, t1 = rad(a0 + step * (i - 1)), rad(a0 + step * i)
		local p0 = cf:PointToWorldSpace(V3(cos(t0) * r, sin(t0) * r, 0))
		local p1 = cf:PointToWorldSpace(V3(cos(t1) * r, sin(t1) * r, 0))
		local mid, dir = (p0 + p1) / 2, (p1 - p0).Unit
		local half = (p1 - p0).Magnitude / 2 + d * 0.3
		table.insert(out, rod(b, mid - dir * half, mid + dir * half, d, color, mat))
	end
	return out
end

-- Flat isosceles triangle (two wedges) standing on `base` (base centre) in its local XY plane,
-- pointing +Y.
local function tri(b: any, base: CFrame, w: number, h: number, t: number, color: Color3, mat: string?): { BasePart }
	return {
		b:Wedge(V3(t, h, w / 2), base * CN(-w / 4, h / 2, 0) * ang(0, 90, 0), color, mat),
		b:Wedge(V3(t, h, w / 2), base * CN(w / 4, h / 2, 0) * ang(0, -90, 0), color, mat),
	}
end

-- Box from a to c in the XY plane with the given width (along X when vertical) and thickness (Z).
local function slab(b: any, a: Vector3, c: Vector3, w: number, t: number, color: Color3, mat: string?): BasePart
	local d = c - a
	local tilt = math.atan2(d.X, d.Y)
	return b:Box(V3(w, d.Magnitude, t), CN((a + c) / 2) * CFrame.Angles(0, 0, -tilt), color, mat)
end

-- Square pyramid tip (two crossed wedges) on `base`, pointing +Y.
local function tip(b: any, base: CFrame, w: number, h: number, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	return {
		b:Wedge(V3(w, h, w / 2), base * CN(0, h / 2, -w / 4), color, mat, props),
		b:Wedge(V3(w, h, w / 2), base * CN(0, h / 2, w / 4) * ang(0, 180, 0), color, mat, props),
	}
end

-- Dog bone lying along X: shaft plus four knobs.
local function bone(b: any, y: number, shaft: number, knob: number, color: Color3, mat: string?)
	b:Cyl(2.3, shaft, CN(0, y, 0), color, mat)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			b:Ball(knob, CN(sx * 1.35, y, sz * knob * 0.44), color, mat)
		end
	end
end

local R = {}

-- Cursed Bone (Common): a greyed, rotting bone with a black iron band of purple runes and green
-- glowing cracks along the shaft.
R.cursed_bone = function(b: any, lod: number)
	local C = rgb(184, 170, 156)
	local y = 0.31
	bone(b, y, 0.42, 0.62, C, "SmoothPlastic")
	b:Cyl(0.18, 0.47, CN(0, y, 0), IRON_D, "Metal")
	local function crack(xs: { number }, ys: { number })
		for i = 1, #xs - 1 do
			b:Accent(bar(b, V3(xs[i], y + ys[i], -0.2), V3(xs[i + 1], y + ys[i + 1], -0.2), 0.06, GREEN, "Neon"))
		end
	end
	crack({ -0.98, -0.64, -0.3 }, { 0.05, -0.07, 0.04 })
	b:Detail(function()
		crack({ 0.3, 0.6, 0.92 }, { -0.04, 0.07, -0.03 })
		bar(b, V3(-0.4, y + 0.205, 0.0), V3(-0.1, y + 0.205, 0.06), 0.05, GREEN, "Neon")
		for i = -1, 1 do
			b:Box(V3(0.04, 0.12, 0.03), CN(i * 0.05, y + i * 0.04, -0.235) * ang(0, 0, i * 30), PURPLE, "Neon")
		end
		b:Ellipsoid(V3(0.36, 0.3, 0.2), CN(1.42, y + 0.12, -0.36), rgb(96, 84, 76), "SmoothPlastic")
		b:Ellipsoid(V3(0.3, 0.2, 0.26), CN(-1.3, y + 0.24, 0.3), rgb(96, 84, 76), "SmoothPlastic")
	end)
end

-- Bloody Coin (Common): a blackened iron coin standing on its edge, an embossed skull, a smear of
-- blood running down the face and a drop pooling at its foot.
R.bloody_coin = function(b: any, lod: number)
	local y = 1.12
	local FACE = rgb(88, 84, 92)
	local RELIEF = rgb(150, 146, 152)
	b:CylZ(0.3, 2.24, CN(0, y, 0), rgb(54, 50, 58), "Metal")
	b:CylZ(0.36, 1.9, CN(0, y, 0), FACE, "Metal")
	b:Ellipsoid(V3(0.86, 0.8, 0.14), CN(0, y + 0.14, -0.18), RELIEF, "Metal")
	b:Box(V3(0.5, 0.28, 0.12), CN(0, y - 0.3, -0.18), RELIEF, "Metal")
	b:Accent(b:Ellipsoid(V3(0.9, 0.36, 0.06), CN(0.34, y + 0.42, -0.25) * ang(0, 0, -28), BLOOD, "Glass"))
	b:Accent(b:Ellipsoid(V3(0.12, 0.72, 0.06), CN(0.64, y - 0.06, -0.22), BLOOD, "Glass"))
	b:Accent(b:Ellipsoid(V3(0.1, 0.46, 0.06), CN(0.4, y - 0.08, -0.26), BLOOD, "Glass"))
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:CylZ(0.04, 0.22, CN(s * 0.18, y + 0.16, -0.26), BLOOD_L, "SmoothPlastic")
		end
		b:Wedge(V3(0.12, 0.12, 0.05), CN(0, y - 0.02, -0.26) * ang(0, 180, 0), INK, "SmoothPlastic")
		for i = -1, 1 do
			b:Box(V3(0.03, 0.2, 0.03), CN(i * 0.12, y - 0.3, -0.245), INK, "SmoothPlastic")
		end
		b:Ball(0.14, CN(0.64, y - 0.44, -0.22), BLOOD, "Glass")
		b:Ellipsoid(V3(0.5, 0.06, 0.34), CN(0.5, 0.03, -0.42), BLOOD, "Glass")
		slab(b, V3(-0.62, y + 0.62, -0.25), V3(-0.38, y - 0.1, -0.25), 0.04, 0.03, INK, "SmoothPlastic")
		for i = 0, 7 do
			local a = rad(i * 45 + 22)
			b:Box(V3(0.08, 0.08, 0.06), CN(cos(a) * 0.82, y + sin(a) * 0.82, -0.19) * ang(0, 0, 45), RELIEF, "Metal")
		end
	end)
end

-- Broken Horn (Common): a demon horn snapped off at the root, ringed with growth ridges and
-- curving, charcoal at the jagged bone-white break fading to a blood red point.
R.broken_horn = function(b: any, lod: number)
	local DARK = rgb(48, 40, 46)
	local n = if lod > 0 then 4 else 7
	local function at(t: number): Vector3
		return V3(0.3 - 1.05 * t * t, 0.04 + 2.3 * t, 0)
	end
	local function width(t: number): number
		return 0.72 * (1 - t) ^ 0.75 + 0.1
	end
	for i = 1, n do
		local t0, t1 = (i - 1) / n * 0.82, i / n * 0.82
		local a, e = at(t0), at(t1)
		local dir = (e - a).Unit
		rod(b, if i == 1 then a else a - dir * 0.03, e + dir * 0.03, width(t0), DARK:Lerp(BLOOD, t0 / 0.82), "SmoothPlastic")
	end
	b:Accent(blob(b, at(0.8), at(1.0) + V3(-0.08, 0.02, 0), 0.22, BLOOD_L, "SmoothPlastic", 0.9))
	b:Ellipsoid(V3(0.86, 0.1, 0.86), CN(0.3, 0.05, 0), BONE_D, "Slate")
	for i, a in { 20, 150, 260 } do
		local r = rad(a)
		local base = CN(0.3 + cos(r) * 0.37, 0.04, sin(r) * 0.37) * ang(0, 90 - a, 0) * ang(-12, 0, 0)
		if i < 3 or lod == 0 then
			tri(b, base, 0.26, if i == 2 then 0.42 else 0.3, 0.08, BONE_D, "Slate")
		end
	end
	b:Detail(function()
		b:Ellipsoid(V3(0.3, 0.08, 0.2), CN(-0.1, 0.03, -0.35), BONE_D, "Slate")
	end)
end

-- Demon Tooth (Common): a huge curved ivory fang with forked roots in a lump of red gum, a crack
-- and a bloody tip.
R.demon_tooth = function(b: any, lod: number)
	local ENAMEL = rgb(240, 230, 204)
	local ROOT = rgb(204, 184, 138)
	blob(b, V3(-0.16, 0.55, 0), V3(-0.24, 0.07, 0.02), 0.32, ROOT, "SmoothPlastic")
	blob(b, V3(0.16, 0.55, 0), V3(0.26, 0.07, -0.02), 0.3, ROOT, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V3(0.92, 0.32, 0.7), CN(0, 0.62, 0), FLESH, "SmoothPlastic"))
	b:Ellipsoid(V3(0.74, 1.4, 0.6), CN(0, 1.2, 0) * ang(0, 0, 4), ENAMEL, "SmoothPlastic")
	b:Ellipsoid(V3(0.46, 1.1, 0.4), CN(-0.13, 1.95, 0) * ang(0, 0, 14), ENAMEL, "SmoothPlastic")
	b:Accent(blob(b, V3(-0.24, 2.32, 0), V3(-0.38, 2.64, 0), 0.16, BLOOD_L, "SmoothPlastic", 0.9))
	b:Detail(function()
		blob(b, V3(-0.2, 2.3, -0.12), V3(-0.12, 1.98, -0.19), 0.08, BLOOD, "Glass")
		b:Ball(0.1, CN(-0.11, 1.93, -0.2), BLOOD, "Glass")
		bar(b, V3(0.2, 1.0, -0.27), V3(0.12, 1.45, -0.24), 0.04, rgb(120, 100, 80), "SmoothPlastic")
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.14, 0.1, 0.12), CN(s * 0.3, 0.78, -0.24), BLOOD, "Glass")
		end
	end)
end

-- Possessed Doll (Uncommon): a sitting rag doll with a big burlap head, one black button eye and
-- one glowing green eye, a stitched grin, yarn hair, a patched dress and a pin through the head.
R.possessed_doll = function(b: any, lod: number)
	local DRESS = rgb(92, 58, 98)
	local SKIN = rgb(214, 194, 160)
	local HAIR = rgb(126, 40, 36)
	b:Ellipsoid(V3(0.86, 0.96, 0.66), CN(0, 0.62, 0.1), DRESS, "Fabric")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.28, 0.28, 0.9), CN(s * 0.2, 0.15, -0.38), rgb(60, 52, 64), "Fabric")
		b:Ellipsoid(V3(0.24, 0.72, 0.24), CN(s * 0.5, 0.66, 0.02) * ang(0, 0, s * 18), SKIN, "Fabric")
	end
	b:Ball(1.06, CN(0, 1.58, 0), SKIN, "Fabric")
	b:Ellipsoid(V3(1.12, 0.56, 1.12), CN(0, 1.9, 0.08), HAIR, "Fabric")
	b:CylZ(0.06, 0.28, CN(0.22, 1.64, -0.49), INK, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V3(0.2, 0.13, 0.06), CN(-0.22, 1.64, -0.5), GREEN, "Neon"))
	b:Box(V3(0.44, 0.04, 0.04), CN(0, 1.36, -0.49), INK, "SmoothPlastic")
	b:Detail(function()
		b:Ellipsoid(V3(0.3, 0.22, 0.04), CN(-0.22, 1.64, -0.47), INK, "SmoothPlastic")
		b:Box(V3(0.04, 0.2, 0.02), CN(0.22, 1.64, -0.53) * ang(0, 0, 45), BLOOD_L, "Fabric")
		b:Box(V3(0.04, 0.2, 0.02), CN(0.22, 1.64, -0.53) * ang(0, 0, -45), BLOOD_L, "Fabric")
		for i = -2, 1 do
			b:Box(V3(0.03, 0.12, 0.03), CN(0.06 + i * 0.12, 1.36, -0.505), INK, "SmoothPlastic")
		end
		for _, s in { -1, 1 } do
			blob(b, V3(s * 0.48, 1.84, 0.1), V3(s * 0.56, 1.24, 0.16), 0.12, HAIR, "Fabric")
			b:Ellipsoid(V3(0.3, 0.26, 0.34), CN(s * 0.2, 0.15, -0.84), INK, "SmoothPlastic")
		end
		blob(b, V3(0, 1.8, 0.48), V3(0.04, 1.2, 0.52), 0.12, HAIR, "Fabric")
		b:Box(V3(0.26, 0.26, 0.03), CN(0.15, 0.7, -0.21) * ang(0, 0, 10), rgb(84, 124, 72), "Fabric")
		for i = 0, 2 do
			b:Box(V3(0.12, 0.03, 0.03), CN(0.47, 1.45 + i * 0.12, -0.18) * ang(0, 70, 0), INK, "SmoothPlastic")
		end
		rod(b, V3(0.28, 1.95, -0.2), V3(0.5, 2.3, -0.36), 0.03, rgb(200, 205, 214), "Metal")
		b:Ball(0.12, CN(0.5, 2.3, -0.36), BLOOD_L, "SmoothPlastic")
	end)
end

-- Black Candle (Uncommon): a tall black wax candle on an iron dish with a skull, wax dripping
-- down its sides and pooling, burning with a sickly green flame.
R.black_candle = function(b: any, lod: number)
	local DRIP = rgb(58, 50, 64)
	b:CylY(0.1, 0.96, CN(0, 0.05, 0), IRON, "Metal")
	b:Ellipsoid(V3(0.78, 0.14, 0.78), CN(0.04, 0.12, -0.02), DRIP, "SmoothPlastic")
	b:CylY(1.5, 0.46, CN(0, 0.88, 0), WAX, "SmoothPlastic")
	b:Ellipsoid(V3(0.52, 0.16, 0.5), CN(0.02, 1.63, 0), DRIP, "SmoothPlastic")
	b:CylY(0.16, 0.04, CN(0, 1.76, 0), INK, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V3(0.26, 0.56, 0.26), CN(0, 2.08, 0), GREEN, "Neon", { Transparency = 0.15 }))
	b:Accent(b:Ellipsoid(V3(0.12, 0.28, 0.12), CN(0, 1.98, 0), rgb(232, 255, 200), "Neon"))
	local drips = { { 250, 0.62 }, { 200, 0.74 }, { 110, 0.4 }, { 310, 0.32 } }
	for i, d in drips do
		local a = rad(d[1])
		local function drip()
			b:Ellipsoid(V3(0.11, d[2], 0.11), CN(cos(a) * 0.23, 1.66 - d[2] / 2, sin(a) * 0.23), DRIP, "SmoothPlastic")
			b:Ball(0.13, CN(cos(a) * 0.235, 1.66 - d[2] + 0.04, sin(a) * 0.235), DRIP, "SmoothPlastic")
		end
		if i <= 2 then
			drip()
		else
			b:Detail(drip)
		end
	end
	b:Detail(function()
		b:Ball(0.2, CN(0, 0.12, -0.45), BONE, "SmoothPlastic")
		for _, s in { -1, 1 } do
			b:Ball(0.06, CN(s * 0.045, 0.14, -0.54), INK, "SmoothPlastic")
		end
		b:Box(V3(0.05, 0.16, 0.03), CN(-0.08, 1.0, -0.235) * ang(0, 0, 20), PURPLE, "Neon")
		b:Box(V3(0.05, 0.12, 0.03), CN(0.06, 0.8, -0.235) * ang(0, 0, -25), PURPLE, "Neon")
	end)
end

-- Cursed Ring (Uncommon): a thorned blackened-iron band; three bone claws grip a blood-red eye
-- gem with a glowing core and a slit pupil.
R.cursed_ring = function(b: any, lod: number)
	local c = CN(0, 0.82, 0)
	arc(b, c, 0.68, 0.24, 90 + 26, 450 - 26, if lod > 0 then 6 else 9, IRON, "Metal")
	b:Ellipsoid(V3(0.5, 0.3, 0.5), CN(0, 1.56, 0), IRON_D, "Metal")
	for i = 0, 2 do
		local a = rad(90 + i * 120)
		local p0 = V3(cos(a) * 0.22, 1.56, sin(a) * 0.22)
		blob(b, p0, V3(cos(a) * 0.2, 2.02, sin(a) * 0.2), 0.1, BONE, "SmoothPlastic")
	end
	b:Accent(b:Ball(0.46, CN(0, 1.84, 0), BLOOD_L, "Glass", { Transparency = 0.25 }))
	b:Accent(b:Ball(0.22, CN(0, 1.84, -0.06), rgb(255, 70, 50), "Neon"))
	b:Detail(function()
		b:Ellipsoid(V3(0.06, 0.26, 0.04), CN(0, 1.84, -0.23), INK, "SmoothPlastic")
		for _, a in { 160, 200, 340, 20 } do
			local r = rad(a)
			tri(b, c * CN(cos(r) * 0.8, sin(r) * 0.8, 0) * ang(0, 0, a - 90), 0.14, 0.2, 0.08, IRON_D, "Metal")
		end
	end)
end

-- Demon Skull (Uncommon): a bone skull with two curved horns, red glowing eyes in black
-- sockets, fangs and cracks.
R.demon_skull = function(b: any, lod: number)
	b:Ball(1.56, CN(0, 1.5, 0.12), BONE, "SmoothPlastic")
	b:Ellipsoid(V3(1.3, 0.86, 1.0), CN(0, 1.05, -0.22), BONE, "SmoothPlastic")
	b:Ellipsoid(V3(0.86, 0.36, 0.7), CN(0, 0.62, -0.32), BONE_D, "SmoothPlastic")
	b:Ellipsoid(V3(1.0, 0.36, 0.9), CN(0, 0.18, -0.22), BONE_D, "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.42, 0.36, 0.2), CN(s * 0.29, 1.2, -0.68), INK, "SmoothPlastic")
		b:Accent(b:Ball(0.13, CN(s * 0.29, 1.2, -0.76), BLOOD_L, "Neon"))
		local pts = { V3(s * 0.5, 1.95, 0.0), V3(s * 0.85, 2.3, 0.05), V3(s * 0.95, 2.72, 0.1), V3(s * 0.8, 3.0, 0.12) }
		if lod > 0 then
			table.remove(pts, 4)
		end
		horn(b, pts, { 0.34, 0.24, 0.14 }, rgb(48, 40, 46), BLOOD_L, "SmoothPlastic")
	end
	b:Ellipsoid(V3(0.18, 0.24, 0.1), CN(0, 0.92, -0.72), INK, "SmoothPlastic")
	b:Detail(function()
		for _, s in { -1, 1 } do
			blob(b, V3(s * 0.28, 0.62, -0.6), V3(s * 0.3, 0.26, -0.62), 0.12, IVORY, "SmoothPlastic")
			b:Ellipsoid(V3(0.3, 0.22, 0.4), CN(s * 0.52, 0.98, -0.42), BONE, "SmoothPlastic")
		end
		for i = -1, 1 do
			b:Box(V3(0.09, 0.14, 0.06), CN(i * 0.11, 0.48, -0.64), IVORY, "SmoothPlastic")
		end
		bar(b, V3(0.2, 2.24, -0.4), V3(0.36, 1.86, -0.62), 0.04, rgb(110, 96, 80), "SmoothPlastic")
		bar(b, V3(0.36, 1.86, -0.62), V3(0.28, 1.6, -0.74), 0.04, rgb(110, 96, 80), "SmoothPlastic")
	end)
end

-- Frozen Heart (Uncommon): a dark red heart locked in a translucent block of ice, its arteries
-- frozen through the top, with frost shards around.
R.frozen_heart = function(b: any, lod: number)
	local ICE = rgb(176, 222, 255)
	local HEART = rgb(184, 30, 50)
	b:Accent(b:Ellipsoid(V3(0.78, 0.86, 0.66), CN(0.02, 0.66, 0) * ang(0, 0, 12), HEART, "SmoothPlastic"))
	b:Accent(b:Ball(0.52, CN(0.18, 1.0, 0.02), HEART, "SmoothPlastic"))
	b:Ball(0.48, CN(-0.2, 1.02, 0.04), rgb(160, 24, 44), "SmoothPlastic")
	blob(b, V3(0.05, 1.1, 0.05), V3(0.12, 1.7, 0.0), 0.24, rgb(196, 44, 60), "SmoothPlastic")
	blob(b, V3(-0.18, 1.15, -0.1), V3(-0.34, 1.55, -0.12), 0.18, rgb(110, 70, 170), "SmoothPlastic")
	b:Box(V3(1.5, 1.25, 1.1), CN(0, 0.625, 0) * ang(0, 18, 0), ICE, "Ice", { Transparency = 0.55 })
	b:Box(V3(1.1, 0.42, 0.84), CN(0.08, 1.4, 0.02) * ang(0, -10, 8), ICE, "Ice", { Transparency = 0.5 })
	tri(b, CN(0.62, 1.15, -0.1) * ang(0, 30, -28), 0.3, 0.8, 0.22, ICE, "Glass")
	tri(b, CN(-0.55, 1.2, 0.15) * ang(0, -20, 32), 0.26, 0.66, 0.2, ICE, "Glass")
	b:Detail(function()
		tri(b, CN(-0.15, 1.55, 0.3) * ang(-25, 0, 8), 0.22, 0.5, 0.18, ICE, "Glass")
		b:Ellipsoid(V3(1.7, 0.05, 1.3), CN(0, 0.025, 0), rgb(200, 232, 255), "Ice", { Transparency = 0.3 })
		bar(b, V3(0.25, 0.9, -0.3), V3(0.05, 0.5, -0.32), 0.035, rgb(60, 40, 110), "SmoothPlastic")
		bar(b, V3(-0.1, 0.95, -0.3), V3(-0.12, 0.6, -0.3), 0.035, rgb(60, 40, 110), "SmoothPlastic")
		b:Ball(0.14, CN(0.12, 1.72, 0), rgb(240, 250, 255), "Ice")
		b:Ball(0.12, CN(-0.34, 1.57, -0.12), rgb(240, 250, 255), "Ice")
	end)
end

-- Soul Fragment (Rare): a translucent spectral shard with a ghost face trapped inside, a wisp
-- curling up from its tip, held by three iron claws on a glowing rune dish.
R.soul_fragment = function(b: any, lod: number)
	local SOUL = rgb(150, 236, 255)
	b:CylY(0.16, 1.2, CN(0, 0.08, 0), IRON, "Metal")
	for i = 0, 2 do
		local a = rad(90 + i * 120)
		local p0, p1 = V3(cos(a) * 0.46, 0.14, sin(a) * 0.46), V3(cos(a) * 0.42, 0.75, sin(a) * 0.42)
		blob(b, p0, p1, 0.12, IRON_D, "Metal")
		b:Detail(function()
			blob(b, p1, V3(cos(a) * 0.26, 1.05, sin(a) * 0.26), 0.08, IRON_D, "Metal")
		end)
	end
	b:Prism(CN(0, 0.74, 0) * ang(0, 45, 5), 0.78, 1.5, 0.9, SOUL, "Glass", { Transparency = 0.4 })
	tip(b, CN(0, 0.74, 0) * ang(0, 45, 5) * ang(180, 0, 0), 0.78, 0.52, SOUL, "Glass", { Transparency = 0.4 })
	b:Accent(b:Ellipsoid(V3(0.36, 1.1, 0.36), CN(0.06, 1.6, 0), rgb(210, 255, 255), "Neon"))
	b:Accent(b:Ellipsoid(V3(0.16, 0.62, 0.12), CN(-0.1, 3.38, 0) * ang(0, 0, -25), SOUL, "Neon", { Transparency = 0.4 }))
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.08, 0.12, 0.04), CN(0.06 + s * 0.08, 1.84, -0.18), INK, "SmoothPlastic")
		end
		b:Ellipsoid(V3(0.08, 0.14, 0.04), CN(0.06, 1.62, -0.18), INK, "SmoothPlastic")
		b:Ellipsoid(V3(0.1, 0.4, 0.08), CN(0.12, 3.72, 0) * ang(0, 0, -62), SOUL, "Neon", { Transparency = 0.5 })
		b:CylY(0.04, 1.22, CN(0, 0.16, 0), rgb(90, 220, 240), "Neon")
	end)
end

-- Eye in a Jar (Rare): a glass jar of sickly green liquid with a rusty lid; an amber-irised
-- eyeball floats inside trailing its optic nerve, with bubbles and a stained label.
R.eye_in_a_jar = function(b: any, lod: number)
	b:CylY(0.08, 1.4, CN(0, 0.04, 0), rgb(150, 190, 170), "Glass", { Transparency = 0.3 })
	b:Accent(b:CylY(1.55, 1.26, CN(0, 0.86, 0), rgb(130, 210, 70), "Glass", { Transparency = 0.45 }))
	b:Ball(0.74, CN(0, 0.98, -0.02), rgb(240, 236, 226), "SmoothPlastic")
	b:Accent(b:CylZ(0.05, 0.36, CN(0, 1.0, -0.37), rgb(210, 128, 24), "SmoothPlastic"))
	b:CylZ(0.06, 0.16, CN(0, 1.0, -0.38), INK, "SmoothPlastic")
	horn(b, { V3(0, 0.86, 0.3), V3(0.12, 0.55, 0.4), V3(0.05, 0.2, 0.28) }, { 0.14, 0.1 }, rgb(196, 76, 86), rgb(160, 50, 64), "SmoothPlastic")
	b:CylY(2.0, 1.36, CN(0, 1.04, 0), rgb(214, 236, 228), "Glass", { Transparency = 0.62 })
	b:CylY(0.1, 1.2, CN(0, 2.08, 0), rgb(214, 236, 228), "Glass", { Transparency = 0.4 })
	b:CylY(0.28, 1.32, CN(0, 2.26, 0), RUST, "Metal")
	b:Detail(function()
		b:CylY(0.02, 1.24, CN(0, 1.64, 0), rgb(170, 240, 110), "Glass", { Transparency = 0.3 })
		bar(b, V3(0.2, 1.2, -0.25), V3(0.12, 1.06, -0.33), 0.03, BLOOD_L, "SmoothPlastic")
		bar(b, V3(-0.24, 0.84, -0.26), V3(-0.12, 0.92, -0.33), 0.03, BLOOD_L, "SmoothPlastic")
		for i, p in { V3(0.35, 1.4, -0.2), V3(-0.3, 1.25, 0.2), V3(0.25, 0.4, 0.3) } do
			b:Ball(0.08 + i * 0.02, CN(p), rgb(240, 255, 230), "Glass", { Transparency = 0.3 })
		end
		b:Box(V3(0.62, 0.42, 0.02), CN(0, 1.62, -0.69), rgb(214, 196, 150), "SmoothPlastic")
		b:Box(V3(0.04, 0.3, 0.02), CN(0, 1.62, -0.705) * ang(0, 0, 40), BLOOD, "SmoothPlastic")
		b:Box(V3(0.04, 0.3, 0.02), CN(0, 1.62, -0.705) * ang(0, 0, -40), BLOOD, "SmoothPlastic")
		b:CylY(0.08, 0.3, CN(0, 2.44, 0), RUST, "Metal")
	end)
end

-- Burning Chain (Rare): a heavy chain lying on the ground in a loose curve, links alternating
-- blackened iron and red-hot glowing iron, with flames licking up from the hot links and a
-- snapped link at one end.
R.burning_chain = function(b: any, lod: number)
	local HOT = rgb(255, 98, 24)
	local CHAIN = rgb(74, 68, 78)
	local a, c, d = 0.3, 0.15, 0.12
	local function along(x: number): (number, number)
		return 0.22 * sin(x * 1.4), -math.atan(0.22 * 1.4 * cos(x * 1.4))
	end
	for i = 0, 5 do
		local x = -1.175 + i * 0.47
		local z, yaw = along(x)
		local upright = i % 2 == 1
		local hot = i % 2 == 0
		local color = if hot then HOT else CHAIN
		local mat = if hot then "CrackedLava" else "Metal"
		local frame = CN(x, if upright then c + d / 2 else d / 2, z) * CFrame.Angles(0, yaw, 0)
		if upright then
			frame = frame * ang(90, 0, 0)
		end
		if lod > 0 then
			b:Ellipsoid(V3(0.72, 0.12, 0.42), frame, color, mat)
		else
			-- rounded rectangle of four rods in the link's local XZ plane
			local parts = {
				rod(b, frame:PointToWorldSpace(V3(-a - 0.05, 0, -c)), frame:PointToWorldSpace(V3(a + 0.05, 0, -c)), d, color, mat),
				rod(b, frame:PointToWorldSpace(V3(-a - 0.05, 0, c)), frame:PointToWorldSpace(V3(a + 0.05, 0, c)), d, color, mat),
				rod(b, frame:PointToWorldSpace(V3(-a, 0, -c - 0.05)), frame:PointToWorldSpace(V3(-a, 0, c + 0.05)), d, color, mat),
				rod(b, frame:PointToWorldSpace(V3(a, 0, -c - 0.05)), frame:PointToWorldSpace(V3(a, 0, c + 0.05)), d, color, mat),
			}
			if hot then
				b:Accent(parts)
			end
		end
		if hot then
			b:Accent(b:Ellipsoid(V3(0.18, 0.4, 0.18), CN(x, 0.3, z) * ang(0, 0, (i - 2) * 6), rgb(255, 120, 30), "Neon", { Transparency = 0.1 }))
			b:Detail(function()
				b:Ellipsoid(V3(0.09, 0.22, 0.09), CN(x, 0.25, z - 0.06), rgb(255, 230, 120), "Neon")
			end)
		end
	end
	b:Detail(function()
		-- snapped half link at the end
		local x = -1.175 + 6 * 0.47
		local z, yaw = along(x)
		local frame = CN(x, d / 2, z) * CFrame.Angles(0, yaw, 0)
		rod(b, frame:PointToWorldSpace(V3(-a - 0.05, 0, -c)), frame:PointToWorldSpace(V3(0.05, 0, -c)), d, CHAIN, "Metal")
		rod(b, frame:PointToWorldSpace(V3(-a - 0.05, 0, c)), frame:PointToWorldSpace(V3(-0.04, 0, c)), d, CHAIN, "Metal")
		rod(b, frame:PointToWorldSpace(V3(-a, 0, -c - 0.05)), frame:PointToWorldSpace(V3(-a, 0, c + 0.05)), d, CHAIN, "Metal")
		b:Ball(0.08, CN(0.0, 0.05, -0.36), HOT, "Neon")
		b:Ball(0.06, CN(-0.6, 0.04, 0.3), HOT, "Neon")
	end)
end

-- Cursed Sword (Rare): a black serrated blade with a glowing red rune fuller, a horned guard
-- around a bone skull, a blood-red wrapped grip and a glowing gem pommel.
R.cursed_sword = function(b: any, lod: number)
	b:Ball(0.3, CN(0, 0.15, 0), IRON, "Metal")
	b:Accent(b:Ball(0.16, CN(0, 0.16, -0.11), BLOOD_L, "Neon"))
	b:CylY(0.82, 0.17, CN(0, 0.71, 0), rgb(92, 20, 28), "Fabric")
	b:Ellipsoid(V3(0.42, 0.36, 0.3), CN(0, 1.24, 0), BONE, "SmoothPlastic")
	for _, s in { -1, 1 } do
		blob(b, V3(s * 0.15, 1.24, 0), V3(s * 0.46, 1.38, 0), 0.16, IRON, "Metal")
		if lod == 0 then
			blob(b, V3(s * 0.46, 1.38, 0), V3(s * 0.64, 1.66, 0), 0.1, IRON, "Metal")
		end
	end
	slab(b, V3(0, 1.36, 0), V3(0, 2.42, 0), 0.42, 0.08, IRON_D, "Metal")
	slab(b, V3(0, 2.38, 0), V3(0, 3.32, 0), 0.32, 0.08, IRON_D, "Metal")
	tri(b, CN(0, 3.3, 0), 0.32, 0.52, 0.08, IRON_D, "Metal")
	b:Accent(b:Box(V3(0.07, 1.8, 0.1), CN(0, 2.32, 0), BLOOD_L, "Neon"))
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ball(0.07, CN(s * 0.08, 1.27, -0.14), BLOOD_L, "Neon")
			blob(b, V3(s * 0.1, 0.17, 0), V3(s * 0.3, 0.13, -0.03), 0.07, IRON_D, "Metal")
			for i = 0, 2 do
				local w = if i == 0 then 0.21 else 0.16
				b:Wedge(V3(0.08, 0.2, 0.12), CN(s * (w + 0.06), 1.62 + i * 0.6, 0) * ang(0, -s * 90, 0), IRON_D, "Metal")
			end
		end
		for i = 0, 2 do
			b:CylY(0.04, 0.2, CN(0, 0.45 + i * 0.25, 0), IRON, "Metal")
		end
	end)
end

-- Book of Souls (Rare): a black tome bound with a bone face on its cover whose eyes glow green,
-- a spine of vertebrae, iron corners and a strap, and a ghostly wisp curling out of glowing pages.
R.book_of_souls = function(b: any, lod: number)
	local y = 1.18
	local COVER = rgb(36, 28, 40)
	b:Box(V3(1.66, 2.22, 0.8), CN(-0.04, y, 0), rgb(196, 186, 150), "SmoothPlastic")
	b:Box(V3(1.8, 2.36, 0.12), CN(0, y, 0.45), COVER, "Fabric")
	b:Box(V3(1.8, 2.36, 0.12), CN(0, y, -0.45), COVER, "Fabric")
	b:Box(V3(0.16, 2.36, 1.02), CN(0.9, y, 0), rgb(26, 20, 30), "Fabric")
	b:Accent(b:Box(V3(0.04, 2.1, 0.72), CN(-0.88, y, 0), GREEN, "Neon"))
	b:Ellipsoid(V3(0.9, 1.1, 0.16), CN(0.04, y + 0.1, -0.52), BONE, "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Accent(b:Ball(0.12, CN(0.04 + s * 0.2, y + 0.25, -0.6), GREEN, "Neon"))
	end
	b:Box(V3(0.3, 0.26, 1.06), CN(-0.86, y - 0.62, 0), IRON, "Metal")
	b:Ellipsoid(V3(0.18, 0.62, 0.1), CN(-0.36, y + 1.32, 0) * ang(0, 0, 22), GREEN, "Neon", { Transparency = 0.45 })
	b:Detail(function()
		b:Ellipsoid(V3(0.12, 0.42, 0.08), CN(-0.6, y + 1.74, 0) * ang(0, 0, 58), GREEN, "Neon", { Transparency = 0.5 })
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.26, 0.22, 0.06), CN(0.04 + s * 0.2, y + 0.25, -0.58), INK, "SmoothPlastic")
		end
		b:Ellipsoid(V3(0.32, 0.14, 0.05), CN(0.04, y - 0.22, -0.59), INK, "SmoothPlastic")
		for i = -1, 1 do
			b:Box(V3(0.03, 0.12, 0.03), CN(0.04 + i * 0.08, y - 0.22, -0.615), BONE, "SmoothPlastic")
		end
		for i = 0, 3 do
			b:Ellipsoid(V3(0.12, 0.34, 0.44), CN(0.99, y - 0.78 + i * 0.52, 0), BONE_D, "SmoothPlastic")
		end
		for _, sy in { -1, 1 } do
			b:Wedge(V3(0.08, 0.34, 0.34), CN(-0.72, y + sy * 1.0, -0.5) * ang(if sy > 0 then 0 else 180, 90, 0), IRON, "Metal")
			b:Wedge(V3(0.08, 0.34, 0.34), CN(0.72, y + sy * 1.0, -0.5) * ang(if sy > 0 then 0 else 180, -90, 0), IRON, "Metal")
		end
		b:Box(V3(0.2, 0.24, 0.08), CN(-0.72, y - 0.62, -0.56), GOLD, "Metal")
	end)
end

-- Demon Crown (Epic): a blackened iron crown of jagged thorn points with two big curved horns, a
-- glowing blood-red gem in front, purple side stones and blood running down the band.
R.demon_crown = function(b: any, lod: number)
	b:CylY(0.82, 2.3, CN(0, 0.41, 0), IRON, "Metal")
	b:CylY(0.02, 2.06, CN(0, 0.825, 0), INK, "SmoothPlastic")
	local heights = { 1.0, 0.62, 0.8, 0.56, 0.9, 0.66, 0.74 }
	local n = if lod > 0 then 5 else 7
	for i = 1, n do
		local h = heights[i]
		local a = (i - 1) * 360 / n
		local cf = CN(0, 0.8, 0) * ang(0, a, 0) * CN(0, h / 2 - 0.08, -1.1) * ang(-8, 0, 0)
		b:Wedge(V3(0.1, h, 0.44), cf * ang(0, if i % 2 == 0 then 90 else -90, 0), IRON_D, "Metal")
	end
	for _, s in { -1, 1 } do
		local pts = { V3(s * 1.05, 0.45, 0.05), V3(s * 1.4, 0.95, 0.08), V3(s * 1.46, 1.55, 0.1), V3(s * 1.26, 1.98, 0.12) }
		if lod > 0 then
			table.remove(pts, 4)
		end
		horn(b, pts, { 0.42, 0.3, 0.18 }, rgb(54, 46, 50), BLOOD_L, "SmoothPlastic")
	end
	b:CylZ(0.12, 0.52, CN(0, 0.47, -1.16), IRON_D, "Metal")
	b:Accent(b:Ellipsoid(V3(0.32, 0.4, 0.16), CN(0, 0.47, -1.23), BLOOD_L, "Neon"))
	b:Detail(function()
		b:CylY(0.12, 2.42, CN(0, 0.06, 0), rgb(76, 22, 30), "Metal")
		for _, s in { -1, 1 } do
			b:Accent(b:Ellipsoid(V3(0.18, 0.22, 0.1), CN(0, 0.47, 0) * ang(0, s * 50, 0) * CN(0, 0, -1.16), PURPLE, "Neon"))
		end
		for i, x in { -0.4, 0.55 } do
			local z = -math.sqrt(1.15 ^ 2 - x * x) - 0.01
			b:Ellipsoid(V3(0.1, 0.36 + i * 0.1, 0.06), CN(x, 0.5 - i * 0.04, z), BLOOD, "Glass")
		end
		for i = 0, 5 do
			b:Ball(0.1, CN(0, 0.3, 0) * ang(0, 30 + i * 60, 0) * CN(0, 0, -1.15), rgb(90, 84, 96), "Metal")
		end
	end)
end

-- Shadow Crystal (Epic): a cluster of dark violet crystals with a glowing purple core, shadow
-- tendrils curling up from a black basalt base veined with purple light.
R.shadow_crystal = function(b: any, lod: number)
	local DARK = rgb(78, 36, 132)
	local DARKER = rgb(54, 24, 96)
	local SHADOW = rgb(26, 10, 40)
	b:Ellipsoid(V3(2.1, 0.66, 1.8), CN(0, 0.33, 0), rgb(30, 28, 34), "Basalt")
	b:Prism(CN(0, 0.42, 0) * ang(0, 30, -6), 0.86, 1.9, 0.8, DARK, "Glass", { Transparency = 0.3 })
	b:Accent(b:Ellipsoid(V3(0.34, 1.4, 0.34), CN(0.06, 1.5, 0) * ang(0, 0, -6), PURPLE, "Neon"))
	b:Prism(CN(0.55, 0.45, 0.15) * ang(10, -20, -32), 0.5, 1.0, 0.45, DARKER, "Glass", { Transparency = 0.2 })
	b:Accent(b:Ellipsoid(V3(0.22, 1.0, 0.12), CN(0.78, 1.0, -0.42) * ang(0, 0, -20), SHADOW, "SmoothPlastic", { Transparency = 0.3 }))
	b:Detail(function()
		b:Prism(CN(-0.5, 0.45, -0.15) * ang(-8, 15, 30), 0.44, 0.85, 0.4, DARKER, "Glass", { Transparency = 0.2 })
		b:Prism(CN(-0.15, 0.45, 0.55) * ang(28, 40, -6), 0.38, 0.7, 0.35, DARK, "Glass", { Transparency = 0.2 })
		b:Ellipsoid(V3(0.2, 0.9, 0.12), CN(-0.85, 0.9, 0.3) * ang(0, 0, 25), SHADOW, "SmoothPlastic", { Transparency = 0.3 })
		b:Ellipsoid(V3(0.16, 0.8, 0.1), CN(0.2, 0.9, -0.82) * ang(30, 0, -10), SHADOW, "SmoothPlastic", { Transparency = 0.3 })
		bar(b, V3(-0.7, 0.55, -0.6), V3(-0.2, 0.62, -0.78), 0.04, PURPLE, "Neon")
		bar(b, V3(0.4, 0.6, -0.72), V3(0.85, 0.5, -0.5), 0.04, PURPLE, "Neon")
		local edge = CN(0, 0.42, 0) * ang(0, 30, -6)
		bar(b, edge:PointToWorldSpace(V3(-0.43, 0.1, -0.43)), edge:PointToWorldSpace(V3(-0.43, 1.85, -0.43)), 0.035, rgb(220, 160, 255), "Neon")
		b:Box(V3(0.18, 0.28, 0.18), CN(-0.75, 0.66, -0.35) * ang(20, 30, 25), DARK, "Glass")
		b:Box(V3(0.14, 0.22, 0.14), CN(0.65, 0.64, 0.5) * ang(-15, 10, -30), DARK, "Glass")
	end)
end

-- Heart of the Beast (Epic): a huge crimson demon heart with glowing ember veins, a burning split
-- down its front, bone spikes and thick arteries.
R.heart_of_the_beast = function(b: any, lod: number)
	local F2 = rgb(150, 34, 46)
	local VEIN = rgb(255, 92, 40)
	b:Ellipsoid(V3(1.2, 1.3, 1.0), CN(0.22, 0.8, 0) * ang(0, 0, 14), FLESH, "SmoothPlastic")
	b:Ellipsoid(V3(0.98, 1.06, 0.9), CN(-0.32, 0.88, -0.06) * ang(0, 0, -12), F2, "SmoothPlastic")
	b:Ellipsoid(V3(0.56, 0.56, 0.56), CN(0.12, 0.28, 0), FLESH, "SmoothPlastic")
	b:Ellipsoid(V3(0.62, 0.5, 0.56), CN(0.32, 1.42, 0.12), F2, "SmoothPlastic")
	b:Ellipsoid(V3(0.56, 0.46, 0.5), CN(-0.28, 1.46, 0.14), FLESH, "SmoothPlastic")
	blob(b, V3(0.0, 1.45, 0.0), V3(0.05, 1.86, 0.0), 0.4, rgb(176, 50, 60), "SmoothPlastic")
	b:Detail(function()
		blob(b, V3(0.05, 1.86, 0.0), V3(-0.34, 1.98, 0.1), 0.34, rgb(176, 50, 60), "SmoothPlastic")
		b:CylY(0.32, 0.26, CN(0.5, 1.78, 0.16) * ang(0, 0, -20), rgb(90, 60, 130), "SmoothPlastic")
		b:CylY(0.02, 0.18, CN(0.555, 1.93, 0.16) * ang(0, 0, -20), INK, "SmoothPlastic")
	end)
	b:Accent(rod(b, V3(0.32, 1.25, -0.44), V3(0.12, 0.82, -0.52), 0.07, VEIN, "Neon"))
	b:Accent(rod(b, V3(0.12, 0.82, -0.52), V3(0.2, 0.4, -0.38), 0.07, VEIN, "Neon"))
	blob(b, V3(0.6, 1.0, 0.2), V3(0.98, 1.36, 0.36), 0.16, BONE, "SmoothPlastic")
	blob(b, V3(-0.62, 1.1, 0.2), V3(-0.98, 1.42, 0.3), 0.14, BONE, "SmoothPlastic")
	b:Detail(function()
		rod(b, V3(0.12, 0.82, -0.52), V3(-0.28, 0.72, -0.5), 0.06, VEIN, "Neon")
		rod(b, V3(-0.36, 1.2, -0.42), V3(-0.5, 0.82, -0.36), 0.05, VEIN, "Neon")
		rod(b, V3(0.55, 1.05, -0.35), V3(0.62, 0.6, -0.36), 0.05, VEIN, "Neon")
		b:Accent(slab(b, V3(-0.06, 1.3, -0.44), V3(-0.1, 0.75, -0.48), 0.06, 0.06, rgb(255, 200, 80), "Neon"))
		blob(b, V3(0.0, 1.05, 0.45), V3(0.0, 1.32, 0.86), 0.12, BONE, "SmoothPlastic")
		blob(b, V3(0.36, 0.5, -0.36), V3(0.4, 0.2, -0.42), 0.07, BLOOD, "Glass")
		b:Ellipsoid(V3(0.5, 0.05, 0.4), CN(0.4, 0.025, -0.4), BLOOD, "Glass")
	end)
end

-- Black Halo (Legendary): a ring of black iron lying flat, its inner edge burning with violet
-- light, thorns jutting outwards and red runes along the top.
R.black_halo = function(b: any, lod: number)
	local flat = CN(0, 0.16, 0) * ang(-90, 0, 0)
	arc(b, flat, 1.36, 0.32, 0, 360, if lod > 0 then 7 else 12, rgb(24, 20, 28), "Metal")
	b:Accent(arc(b, CN(0, 0.2, 0) * ang(-90, 0, 0), 1.14, 0.12, 15, 375, if lod > 0 then 6 else 12, rgb(190, 60, 255), "Neon"))
	b:Detail(function()
		for i = 0, 7 do
			local a = rad(i * 45 + 22.5)
			local d = V3(cos(a), 0, sin(a))
			blob(b, d * 1.45 + V3(0, 0.22, 0), d * 1.72 + V3(0, 0.44, 0), 0.12, rgb(40, 34, 44), "Metal", 0.7)
		end
		for i = 0, 3 do
			local a = i * 90 + 45
			local r = rad(a)
			b:Box(V3(0.08, 0.03, 0.2), CN(cos(r) * 1.36, 0.33, sin(r) * 1.36) * ang(0, -a, 0), BLOOD_L, "Neon")
		end
	end)
end

-- Unknown Skull (Legendary): a long ashen skull of no known beast: three eye sockets with violet
-- glowing pupils, long fangs, glowing runes and violet crystals growing out of the back.
R.unknown_skull = function(b: any, lod: number)
	local ASH = rgb(188, 178, 196)
	local ASH_D = rgb(140, 130, 150)
	local VIO = rgb(200, 110, 255)
	local CRYSTAL = rgb(150, 70, 230)
	local cran = CN(0, 1.3, 0.35) * ang(-25, 0, 0)
	local semi = V3(0.65, 0.625, 1.0)
	-- frame on the cranium surface (direction x, y, z in cranium space) with +Y along the normal
	local function onCranium(x: number, y: number, z: number): CFrame
		local q = V3(x / semi.X, y / semi.Y, z / semi.Z)
		local k = 0.96 / q.Magnitude
		local p = cran:PointToWorldSpace(V3(x, y, z) * k)
		local normal = cran:VectorToWorldSpace(V3(x / semi.X ^ 2, y / semi.Y ^ 2, z / semi.Z ^ 2)).Unit
		return look(p, p + normal) * ang(-90, 0, 0)
	end
	b:Ellipsoid(semi * 2, cran, ASH, "SmoothPlastic")
	b:Ellipsoid(V3(1.15, 0.95, 0.9), CN(0, 0.9, -0.35), ASH, "SmoothPlastic")
	b:Ellipsoid(V3(0.86, 0.3, 0.78), CN(0, 0.15, -0.38), ASH_D, "SmoothPlastic")
	local sockets = { CN(-0.27, 1.0, -0.74), CN(0.27, 1.0, -0.74), CN(0, 1.42, -0.62) * ang(-25, 0, 0) }
	for i, cf in sockets do
		b:Ellipsoid(if i == 3 then V3(0.2, 0.34, 0.16) else V3(0.32, 0.36, 0.18), cf, INK, "SmoothPlastic")
		b:Accent(b:Ball(0.12, cf * CN(0, 0, -0.07), VIO, "Neon"))
	end
	for _, s in { -1, 1 } do
		blob(b, V3(s * 0.22, 0.56, -0.66), V3(s * 0.2, 0.18, -0.68), 0.1, IVORY, "SmoothPlastic", 0.9)
	end
	local main = onCranium(0.05, 0.5, 0.75)
	if lod > 0 then
		b:Box(V3(0.3, 0.7, 0.3), main * CN(0, 0.3, 0), CRYSTAL, "Glass")
	else
		b:Prism(main * CN(0, -0.1, 0), 0.3, 0.55, 0.32, CRYSTAL, "Glass", { Transparency = 0.15 })
	end
	b:Detail(function()
		b:Prism(onCranium(0.42, 0.1, 0.7) * CN(0, -0.08, 0), 0.24, 0.42, 0.26, CRYSTAL, "Glass", { Transparency = 0.15 })
		b:Prism(onCranium(-0.4, 0.2, 0.65) * CN(0, -0.06, 0), 0.2, 0.3, 0.2, CRYSTAL, "Glass", { Transparency = 0.15 })
		for _, s in { -1, 1 } do
			blob(b, V3(s * 0.08, 0.54, -0.72), V3(s * 0.08, 0.3, -0.73), 0.07, IVORY, "SmoothPlastic", 0.9)
			b:Ellipsoid(V3(0.3, 0.2, 0.44), CN(s * 0.5, 0.82, -0.5), ASH_D, "SmoothPlastic")
		end
		b:Ellipsoid(V3(0.14, 0.2, 0.08), CN(0, 0.72, -0.78), INK, "SmoothPlastic")
		bar(b, V3(0.55, 1.5, 0.2), V3(0.62, 1.2, 0.6), 0.04, VIO, "Neon")
		bar(b, V3(-0.6, 1.45, 0.1), V3(-0.64, 1.2, 0.55), 0.04, VIO, "Neon")
		bar(b, V3(0.15, 1.95, 0.0), V3(0.3, 1.75, 0.5), 0.04, rgb(90, 80, 96), "SmoothPlastic")
	end)
end

-- The Forbidden Bone (Legendary): an old ivory bone carved with glowing red runes, bound by two
-- iron chain loops joined to a gold padlock, with paper seal talismans hanging on its front.
R.the_forbidden_bone = function(b: any, lod: number)
	local y = 0.34
	local CHAIN = rgb(84, 78, 90)
	bone(b, y, 0.44, 0.66, rgb(232, 222, 196), "Marble")
	local n = if lod > 0 then 3 else 6
	for _, x in { -0.55, 0.55 } do
		arc(b, CN(x, y, 0) * ang(0, 90, 0), 0.28, 0.1, 0, 360, n, CHAIN, "Metal")
	end
	b:Accent(b:Box(V3(0.34, 0.28, 0.14), CN(0, 0.15, -0.44), GOLD, "Metal"))
	b:Detail(function()
		rod(b, V3(-0.55, 0.3, -0.27), V3(0, 0.36, -0.44), 0.07, CHAIN, "Metal")
		rod(b, V3(0.55, 0.3, -0.27), V3(0, 0.36, -0.44), 0.07, CHAIN, "Metal")
		arc(b, CN(0, 0.29, -0.44), 0.1, 0.05, 0, 180, 3, CHAIN, "Metal")
		b:CylZ(0.02, 0.07, CN(0, 0.13, -0.515), INK, "SmoothPlastic")
		for i, x in { -0.95, -0.8, 0.8, 0.95 } do
			b:Accent(b:Box(V3(0.05, 0.16, 0.04), CN(x, y + 0.02, -0.225) * ang(0, 0, if i % 2 == 0 then 20 else -20), BLOOD_L, "Neon"))
		end
		for _, x in { -0.3, 0.3 } do
			local cf = CN(x, y - 0.08, -0.235) * ang(0, 0, x * 20)
			b:Box(V3(0.18, 0.5, 0.02), cf, rgb(236, 222, 170), "SmoothPlastic")
			b:Box(V3(0.05, 0.34, 0.025), cf, BLOOD_L, "SmoothPlastic")
		end
	end)
end

-- Normal Bone (Secret): a perfectly clean, perfectly ordinary white bone. Except one thin slice
-- of the shaft sits a little out of place, with a faint cyan / magenta fringe, like a bad frame.
R.normal_bone = function(b: any, lod: number)
	local W = rgb(250, 249, 244)
	local y = 0.31
	bone(b, y, 0.42, 0.62, W, "SmoothPlastic")
	b:Accent(b:Cyl(0.06, 0.42, CN(0.38, y + 0.025, -0.06), W, "SmoothPlastic"))
	b:Cyl(0.015, 0.42, CN(0.345, y + 0.04, -0.1), rgb(0, 255, 240), "Neon", { Transparency = 0.5 })
	b:Detail(function()
		b:Cyl(0.015, 0.42, CN(0.415, y + 0.01, -0.02), rgb(255, 0, 200), "Neon", { Transparency = 0.5 })
	end)
end

return R
