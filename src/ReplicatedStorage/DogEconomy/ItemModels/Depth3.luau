-- Depth 3 (Ancient Ruins) find models: sandstone, gold, lapis and turquoise; Egyptian temple and
-- medieval knight motifs. Each recipe builds one find around the origin, resting on Y = 0, front
-- towards -Z, at the size of its old voxel model (see ItemModels.luau and docs/ITEM_MODELS_D34.md).
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
local GOLD = rgb(255, 196, 54)
local GOLD_D = rgb(196, 132, 28)
local GOLD_OLD = rgb(204, 156, 66)
local GOLD_OLD_D = rgb(150, 106, 40)
local GOLD_OLD_L = rgb(232, 192, 104)
local SAND = rgb(222, 190, 132)
local SAND_D = rgb(178, 144, 96)
local SAND_L = rgb(240, 216, 168)
local LAPIS = rgb(38, 66, 168)
local LAPIS_D = rgb(26, 40, 112)
local TURQ = rgb(52, 196, 186)
local INK = rgb(26, 24, 30)
local IVORY = rgb(248, 240, 220)
local BASALT = rgb(34, 32, 38)
local CARNELIAN = rgb(222, 82, 40)
local RUBY = rgb(214, 28, 64)
local STEEL = rgb(168, 176, 188)
local IRON = rgb(92, 96, 106)
local LEATHER = rgb(112, 64, 36)
local MOSS = rgb(92, 128, 58)

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

-- Organic segment: an ellipsoid of diameter d stretched from a to c (horns, legs, tails).
local function blob(b: any, a: Vector3, c: Vector3, d: number, color: Color3, mat: string?, over: number?): BasePart
	local len = (c - a).Magnitude
	return b:Ellipsoid(V3(d, d, len + d * (over or 0.5)), look((a + c) / 2, c), color, mat)
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
-- pointing +Y: blade tips, ears, crown points.
local function tri(b: any, base: CFrame, w: number, h: number, t: number, color: Color3, mat: string?): { BasePart }
	return {
		b:Wedge(V3(t, h, w / 2), base * CN(-w / 4, h / 2, 0) * ang(0, 90, 0), color, mat),
		b:Wedge(V3(t, h, w / 2), base * CN(w / 4, h / 2, 0) * ang(0, -90, 0), color, mat),
	}
end

-- Box from a to c (blade sections, straps) with the given cross-section (width along the
-- local X that stays horizontal, thickness along Z).
local function slab(b: any, a: Vector3, c: Vector3, w: number, t: number, color: Color3, mat: string?): BasePart
	local d = c - a
	local tilt = math.atan2(d.X, d.Y)
	return b:Box(V3(w, d.Magnitude, t), CN((a + c) / 2) * CFrame.Angles(0, 0, -tilt), color, mat)
end

local R = {}

-- Ancient Coin (Common): a worn gold coin standing on its edge, an embossed profile bust,
-- a dotted border and green patina.
R.ancient_coin = function(b: any, lod: number)
	local y = 1.12
	b:CylZ(0.3, 2.24, CN(0, y, 0), GOLD_OLD_D, "Metal")
	b:CylZ(0.36, 1.92, CN(0, y, 0), GOLD_OLD, "Metal")
	b:Accent(b:Ellipsoid(V3(0.62, 0.74, 0.14), CN(-0.04, y + 0.2, -0.18), GOLD_OLD_L, "Metal"))
	b:Accent(b:Ellipsoid(V3(0.22, 0.14, 0.12), CN(0.3, y + 0.14, -0.18) * ang(0, 0, -20), GOLD_OLD_L, "Metal"))
	b:Accent(b:Ellipsoid(V3(0.86, 0.34, 0.12), CN(-0.08, y - 0.46, -0.18), GOLD_OLD_L, "Metal"))
	b:Box(V3(0.28, 0.3, 0.1), CN(-0.08, y - 0.22, -0.18), GOLD_OLD_L, "Metal")
	b:Detail(function()
		for i = 0, 13 do
			local a = rad(i * 360 / 14)
			b:Ball(0.08, CN(cos(a) * 0.82, y + sin(a) * 0.82, -0.19), GOLD_OLD_D, "Metal")
		end
		-- laurel wreath and patina spots
		for i = 0, 2 do
			b:Ellipsoid(V3(0.12, 0.24, 0.08), CN(-0.36 + i * 0.04, y + 0.38 - i * 0.2, -0.22) * ang(0, 0, 30 - i * 25), rgb(116, 168, 110), "Metal")
		end
		b:Ellipsoid(V3(0.36, 0.22, 0.06), CN(0.5, y - 0.5, -0.18) * ang(0, 0, 25), rgb(110, 176, 150), "SmoothPlastic")
		b:Ellipsoid(V3(0.24, 0.16, 0.06), CN(-0.62, y + 0.35, 0.18), rgb(110, 176, 150), "SmoothPlastic")
	end)
end

-- Golden Cup (Common): a two-handled chalice with a lapis band and a turquoise gem.
R.golden_cup = function(b: any, lod: number)
	b:Disc(CN(0, 0.06, 0), 1.0, 0.12, GOLD_D, "Metal")
	b:Ellipsoid(V3(0.8, 0.5, 0.8), CN(0, 0.26, 0), GOLD, "Metal")
	b:CylY(0.7, 0.2, CN(0, 0.65, 0), GOLD, "Metal")
	b:Detail(function()
		b:Ball(0.34, CN(0, 0.72, 0), GOLD_D, "Metal")
	end)
	b:Ellipsoid(V3(1.34, 1.0, 1.34), CN(0, 1.52, 0), GOLD, "Metal")
	b:CylY(0.78, 1.3, CN(0, 1.92, 0), GOLD, "Metal")
	b:CylY(0.1, 1.4, CN(0, 2.33, 0), GOLD_D, "Metal")
	b:CylY(0.02, 1.16, CN(0, 2.385, 0), rgb(92, 52, 20), "SmoothPlastic")
	b:Accent(b:CylY(0.16, 1.34, CN(0, 1.72, 0), LAPIS, "SmoothPlastic"))
	b:Accent(b:Ellipsoid(V3(0.24, 0.24, 0.12), CN(0, 1.72, -0.68), TURQ, "Glass"))
	local n = if lod > 0 then 2 else 3
	arc(b, CN(0.64, 1.78, 0), 0.4, 0.13, -80, 80, n, GOLD, "Metal")
	arc(b, CN(-0.64, 1.78, 0), 0.4, 0.13, 100, 260, n, GOLD, "Metal")
	b:Detail(function()
		b:Ellipsoid(V3(0.12, 0.2, 0.18), CN(0.66, 1.72, 0), TURQ, "Glass")
		b:Ellipsoid(V3(0.12, 0.2, 0.18), CN(-0.66, 1.72, 0), TURQ, "Glass")
	end)
end

-- Pharaoh Mask (Common): gold face, striped lapis-and-gold nemes headdress with lappets, kohl eyes,
-- uraeus cobra, braided beard and a broad collar.
R.pharaoh_mask = function(b: any, lod: number)
	-- broad collar (three bands seen as concentric rings)
	b:Ellipsoid(V3(2.3, 0.36, 1.4), CN(0, 0.18, -0.1), TURQ, "SmoothPlastic")
	b:Detail(function()
		b:Ellipsoid(V3(1.86, 0.44, 1.14), CN(0, 0.22, -0.1), LAPIS, "SmoothPlastic")
	end)
	b:Ellipsoid(V3(1.4, 0.52, 0.9), CN(0, 0.26, -0.1), GOLD, "Foil")
	-- nemes headdress dome and lappets
	b:Ellipsoid(V3(2.0, 1.55, 1.5), CN(0, 1.62, 0.12), GOLD, "Foil")
	for _, s in { -1, 1 } do
		b:Box(V3(0.5, 1.5, 0.34), CN(s * 0.8, 0.98, -0.2) * ang(0, 0, s * 6), LAPIS, "SmoothPlastic")
	end
	b:Detail(function()
		for i = 0, 2 do
			local h = 0.35 - i * 0.3
			local f = math.sqrt(math.max(0, 1 - (h / 0.775) ^ 2))
			b:Ellipsoid(V3(2.0 * f + 0.05, 0.1, 1.5 * f + 0.05), CN(0, 1.62 + h, 0.12), LAPIS, "SmoothPlastic")
		end
		for _, s in { -1, 1 } do
			for i = 0, 1 do
				b:Box(V3(0.52, 0.12, 0.36), CN(s * 0.8, 1.3 - i * 0.42, -0.2) * ang(0, 0, s * 6), GOLD, "Foil")
			end
		end
	end)
	-- face
	b:Ellipsoid(V3(1.02, 1.3, 0.72), CN(0, 1.25, -0.45), GOLD, "Foil")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.3, 0.13, 0.08), CN(s * 0.22, 1.42, -0.77), IVORY, "SmoothPlastic")
		b:Ball(0.1, CN(s * 0.22, 1.42, -0.8), INK, "SmoothPlastic")
	end
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Box(V3(0.3, 0.04, 0.05), CN(s * 0.4, 1.4, -0.72) * ang(0, s * 30, s * 10), LAPIS_D, "SmoothPlastic")
			b:Box(V3(0.3, 0.05, 0.05), CN(s * 0.22, 1.56, -0.75) * ang(0, 0, s * -8), LAPIS_D, "SmoothPlastic")
		end
		b:Box(V3(0.24, 0.05, 0.05), CN(0, 0.94, -0.79), rgb(150, 70, 40), "SmoothPlastic")
	end)
	b:Wedge(V3(0.16, 0.3, 0.14), CN(0, 1.18, -0.82), GOLD_D, "Foil")
	-- beard
	b:CylY(0.5, 0.18, CN(0, 0.52, -0.62) * ang(-14, 0, 0), LAPIS, "SmoothPlastic")
	b:Detail(function()
		b:Ball(0.2, CN(0, 0.3, -0.67), GOLD, "Foil")
	end)
	-- uraeus cobra on the brow
	b:Accent(b:Ellipsoid(V3(0.14, 0.34, 0.12), CN(0, 1.98, -0.7) * ang(-15, 0, 0), GOLD_D, "Foil"))
	b:Detail(function()
		b:Accent(b:Ball(0.16, CN(0, 2.17, -0.74), RUBY, "Glass"))
	end)
end

-- Stone Tablet (Common): an arched sandstone stela with a winged gold sun disc and rows of
-- lapis and turquoise hieroglyphs, cracked at one corner.
R.stone_tablet = function(b: any, lod: number)
	b:Box(V3(1.92, 1.82, 0.5), CN(0, 0.91, 0), SAND, "Sandstone")
	b:CylZ(0.5, 1.92, CN(0, 1.82, 0), SAND, "Sandstone")
	b:Box(V3(1.56, 1.5, 0.04), CN(0, 1.06, -0.25), SAND_D, "Sandstone")
	b:Accent(b:CylZ(0.06, 0.42, CN(0, 2.22, -0.27), GOLD, "Foil"))
	b:Detail(function()
		-- sun wings
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.62, 0.16, 0.05), CN(s * 0.48, 2.24, -0.26) * ang(0, 0, s * -8), TURQ, "SmoothPlastic")
		end
		-- row 1: eye, bird, ankh
		b:Ellipsoid(V3(0.36, 0.16, 0.04), CN(0.48, 1.56, -0.28), IVORY, "SmoothPlastic")
		b:Ball(0.1, CN(0.48, 1.56, -0.29), LAPIS_D, "SmoothPlastic")
		b:Box(V3(0.4, 0.05, 0.04), CN(0.48, 1.68, -0.28), LAPIS_D, "SmoothPlastic")
		b:Ellipsoid(V3(0.28, 0.2, 0.04), CN(0, 1.56, -0.28), LAPIS, "SmoothPlastic")
		b:Wedge(V3(0.04, 0.08, 0.14), CN(0.04, 1.64, -0.28) * ang(0, 90, 0), CARNELIAN, "SmoothPlastic")
		b:Box(V3(0.05, 0.3, 0.04), CN(-0.48, 1.48, -0.28), TURQ, "SmoothPlastic")
		b:Box(V3(0.24, 0.05, 0.04), CN(-0.48, 1.56, -0.28), TURQ, "SmoothPlastic")
		b:Ball(0.16, CN(-0.48, 1.7, -0.27), TURQ, "SmoothPlastic")
		-- row 2: water zigzag and reeds
		for i = 0, 3 do
			b:Box(V3(0.2, 0.05, 0.04), CN(-0.36 + i * 0.16, 1.12, -0.28) * ang(0, 0, if i % 2 == 0 then 35 else -35), LAPIS, "SmoothPlastic")
		end
		b:Box(V3(0.05, 0.36, 0.04), CN(0.42, 1.08, -0.28), CARNELIAN, "SmoothPlastic")
		b:Box(V3(0.05, 0.36, 0.04), CN(0.54, 1.08, -0.28), CARNELIAN, "SmoothPlastic")
		-- row 3: seated figure
		b:Ball(0.14, CN(-0.1, 0.78, -0.28), LAPIS_D, "SmoothPlastic")
		b:Box(V3(0.16, 0.22, 0.04), CN(-0.1, 0.6, -0.28), LAPIS_D, "SmoothPlastic")
		b:Box(V3(0.42, 0.05, 0.04), CN(0.2, 0.6, -0.28), GOLD_D, "SmoothPlastic")
		-- crack and broken corner
		slab(b, V3(0.62, 2.4, -0.27), V3(0.32, 1.9, -0.27), 0.04, 0.03, INK, "SmoothPlastic")
		slab(b, V3(0.32, 1.9, -0.27), V3(0.42, 1.55, -0.27), 0.04, 0.03, INK, "SmoothPlastic")
		b:Ellipsoid(V3(0.5, 0.2, 0.46), CN(-0.72, 0.06, -0.05), MOSS, "Grass")
	end)
end

-- Eye of Statue (Common): a chipped sandstone fragment of a colossal face, carved with a
-- painted almond eye under a heavy brow.
R.eye_of_statue = function(b: any, lod: number)
	b:Box(V3(2.2, 1.2, 1.0), CN(0, 0.6, 0.12), SAND, "Sandstone")
	b:Wedge(V3(2.2, 0.46, 1.0), CN(0, 1.43, 0.12) * ang(0, 180, 0), SAND, "Sandstone")
	b:Box(V3(0.7, 0.55, 0.7), CN(-0.86, 1.38, 0.22) * ang(18, 12, 28), SAND_L, "Sandstone")
	b:Ellipsoid(V3(1.9, 0.36, 0.56), CN(-0.08, 1.24, -0.36) * ang(0, 0, -3), SAND, "Sandstone")
	b:Ellipsoid(V3(1.36, 0.42, 0.34), CN(-0.08, 0.88, -0.42), SAND_L, "Sandstone")
	b:Ellipsoid(V3(1.2, 0.3, 0.3), CN(-0.08, 0.5, -0.4), SAND_L, "Sandstone")
	b:Ellipsoid(V3(1.06, 0.44, 0.3), CN(-0.08, 0.69, -0.5), IVORY, "Marble")
	b:Accent(b:CylZ(0.06, 0.4, CN(-0.08, 0.69, -0.64), LAPIS, "SmoothPlastic"))
	b:Accent(b:CylZ(0.07, 0.18, CN(-0.08, 0.69, -0.66), INK, "SmoothPlastic"))
	b:Detail(function()
		slab(b, V3(-0.6, 0.73, -0.58), V3(-1.05, 0.86, -0.42), 0.08, 0.05, LAPIS_D, "SmoothPlastic")
		slab(b, V3(0.36, 1.5, -0.39), V3(0.56, 0.3, -0.39), 0.04, 0.04, SAND_D, "SmoothPlastic")
		b:Box(V3(0.3, 0.22, 0.26), CN(-0.95, 0.11, -0.7) * ang(0, 30, 0), SAND_D, "Sandstone")
		b:Box(V3(0.2, 0.16, 0.2), CN(0.95, 0.08, -0.62) * ang(0, -20, 0), SAND, "Sandstone")
	end)
end

-- Ritual Dagger (Uncommon): a wavy bronze blade with engraved runes, a gold crescent guard,
-- a wrapped grip and a turquoise pommel.
R.ritual_dagger = function(b: any, lod: number)
	b:Ball(0.36, CN(0, 0.18, 0), GOLD, "Metal")
	b:Accent(b:Ball(0.2, CN(0, 0.2, -0.12), TURQ, "Glass"))
	b:CylY(0.92, 0.2, CN(0, 0.82, 0), LEATHER, "Fabric")
	b:Detail(function()
		b:CylY(0.08, 0.26, CN(0, 0.46, 0), GOLD, "Metal")
		b:CylY(0.08, 0.26, CN(0, 1.2, 0), GOLD, "Metal")
		b:Ball(0.16, CN(0.62, 1.66, 0), TURQ, "Glass")
		b:Ball(0.16, CN(-0.62, 1.66, 0), TURQ, "Glass")
	end)
	arc(b, CN(0, 1.86, 0), 0.62, 0.16, 200, 340, if lod > 0 then 2 else 4, GOLD, "Metal")
	local pts = { V3(0, 1.3, 0), V3(0.08, 1.9, 0), V3(-0.08, 2.45, 0), V3(0.08, 3.0, 0), V3(0, 3.4, 0) }
	local widths = { 0.36, 0.34, 0.3, 0.26 }
	local BRONZE = rgb(222, 156, 84)
	for i = 1, 4 do
		local a, c = pts[i], pts[i + 1]
		local dir = (c - a).Unit
		slab(b, a - dir * 0.05, c + dir * 0.05, widths[i], 0.07, BRONZE, "Metal")
	end
	tri(b, CN(0, 3.38, 0), 0.26, 0.47, 0.07, BRONZE, "Metal")
	b:Detail(function()
		for i = 0, 2 do
			local p = pts[i + 2]
			b:Accent(b:Box(V3(0.06, 0.18, 0.09), CN(p.X, p.Y - 0.1, 0) * ang(0, 0, if i % 2 == 0 then 20 else -20), TURQ, "SmoothPlastic"))
		end
	end)
end

-- Lost Crown (Uncommon): a tarnished, dented gold circlet with blunt points, one bent and one
-- snapped, a single ruby left in its sockets and dirt stuck to the rim.
R.lost_crown = function(b: any, lod: number)
	b:CylY(0.12, 2.42, CN(0, 0.06, 0), GOLD_OLD_D, "Metal")
	b:CylY(0.72, 2.3, CN(0, 0.42, 0), GOLD_OLD, "Metal")
	b:CylY(0.02, 2.06, CN(0, 0.785, 0), rgb(54, 40, 24), "SmoothPlastic")
	local n = if lod > 0 then 5 else 6
	for i = 0, n - 1 do
		local a = i * 360 / n + 30
		local cf = CN(0, 0.78, 0) * ang(0, a, 0) * CN(0, 0, -1.08)
		if i == 2 then
			cf = cf * ang(-24, 0, 0) -- bent outwards
		end
		local s = if i == 4 then 0.46 else 0.72 -- snapped point
		b:Box(V3(s, s, 0.08), cf * ang(0, 0, 45), GOLD_OLD, "Metal")
		if i ~= 4 then
			b:Detail(function()
				b:Ball(0.15, cf * CN(0, s * 0.71, 0), GOLD_OLD_L, "Metal")
			end)
		end
	end
	b:Accent(b:Ellipsoid(V3(0.26, 0.3, 0.14), CN(0, 0.44, -1.16), RUBY, "Glass"))
	b:Detail(function()
		for _, a in { -55, 55 } do
			b:CylZ(0.06, 0.26, CN(0, 0.44, 0) * ang(0, a, 0) * CN(0, 0, -1.15), rgb(40, 30, 20), "SmoothPlastic")
		end
		b:Ellipsoid(V3(0.42, 0.24, 0.3), CN(0.9, 0.1, -0.78), rgb(98, 70, 44), "Ground")
		b:Ellipsoid(V3(0.3, 0.2, 0.26), CN(-1.05, 0.1, 0.5), rgb(98, 70, 44), "Ground")
		b:Ellipsoid(V3(0.4, 0.2, 0.06), CN(-0.6, 0.5, -1.0) * ang(0, -30, 0), GOLD_OLD_D, "Metal")
	end)
end

-- Ancient Book (Uncommon): a thick leather tome with brass corners, a strap clasp, raised spine
-- bands and a gold sun emblem with a turquoise eye.
R.ancient_book = function(b: any, lod: number)
	local y = 1.18
	b:Box(V3(1.66, 2.22, 0.82), CN(-0.04, y, 0), rgb(236, 222, 182), "SmoothPlastic")
	b:Box(V3(1.8, 2.36, 0.12), CN(0, y, 0.45), LEATHER, "Fabric")
	b:Box(V3(1.8, 2.36, 0.12), CN(0, y, -0.45), LEATHER, "Fabric")
	b:Box(V3(0.16, 2.36, 1.02), CN(0.9, y, 0), rgb(92, 50, 28), "Fabric")
	b:Box(V3(0.3, 0.3, 1.08), CN(-0.86, y, 0), rgb(84, 46, 26), "Fabric")
	b:Box(V3(0.22, 0.34, 0.06), CN(-0.62, y, -0.53), GOLD_D, "Metal")
	b:Accent(b:CylZ(0.05, 0.86, CN(0.02, y + 0.12, -0.52), GOLD, "Foil"))
	b:Accent(b:Ellipsoid(V3(0.42, 0.24, 0.1), CN(0.02, y + 0.12, -0.56), TURQ, "Glass"))
	b:Detail(function()
		b:Ball(0.12, CN(0.02, y + 0.12, -0.6), INK, "SmoothPlastic")
		for i = -1, 1 do
			b:Box(V3(0.06, 0.1, 1.06), CN(0.98, y + i * 0.6, 0), GOLD_D, "Metal")
		end
		for _, sy in { -1, 1 } do
			b:Wedge(V3(0.08, 0.34, 0.34), CN(-0.72, y + sy * 1.0, -0.5) * ang(if sy > 0 then 0 else 180, 90, 0), GOLD_D, "Metal")
			b:Box(V3(1.3, 0.05, 0.03), CN(0.08, y + sy * 0.86, -0.52), GOLD, "Foil")
		end
	end)
end

-- Golden Scarab (Uncommon): a gold scarab beetle with a domed wing shell split by a seam and inlaid
-- with lapis, a broad toothed head, six chunky splayed legs and a carnelian sun disc held up in
-- front.
R.golden_scarab = function(b: any, lod: number)
	b:Ellipsoid(V3(1.26, 0.64, 1.36), CN(0, 0.42, 0.32), GOLD, "Foil")
	b:Ellipsoid(V3(1.16, 0.5, 0.66), CN(0, 0.4, -0.5), GOLD_D, "Foil")
	b:Ellipsoid(V3(0.92, 0.2, 0.46), CN(0, 0.27, -0.92), GOLD, "Foil")
	b:Accent(b:CylZ(0.1, 0.6, CN(0, 0.78, -1.22) * ang(-25, 0, 0), rgb(250, 110, 40), "Neon"))
	local legs = {
		{ V3(0.36, 0.34, -0.6), V3(0.68, 0.56, -0.86), V3(0.28, 0.74, -1.17) },
		{ V3(0.5, 0.32, -0.15), V3(0.95, 0.44, -0.2), V3(1.2, 0.03, -0.32) },
		{ V3(0.5, 0.32, 0.38), V3(0.9, 0.44, 0.62), V3(1.08, 0.03, 0.98) },
	}
	for _, leg in legs do
		for _, s in { -1, 1 } do
			local m = V3(s, 1, 1)
			if lod > 0 then
				rod(b, leg[1] * m, leg[3] * m, 0.1, GOLD_D, "Metal")
			else
				blob(b, leg[1] * m, leg[2] * m, 0.12, GOLD_D, "Metal")
				blob(b, leg[2] * m, leg[3] * m, 0.09, GOLD_D, "Metal")
			end
		end
	end
	b:Detail(function()
		b:CylZ(0.08, 0.68, CN(0, 0.78, -1.22) * ang(-25, 0, 0) * CN(0, 0, 0.04), GOLD, "Metal")
		b:Box(V3(0.04, 0.06, 1.2), CN(0, 0.735, 0.36), GOLD_D, "Metal")
		for _, s in { -1, 1 } do
			b:Accent(b:Ellipsoid(V3(0.14, 0.08, 0.9), CN(s * 0.3, 0.7, 0.36) * ang(0, s * 3, s * -12), LAPIS, "SmoothPlastic"))
			b:Ball(0.1, CN(s * 0.34, 0.34, -0.9), INK, "SmoothPlastic")
		end
		for i = 0, 3 do
			b:Ellipsoid(V3(0.12, 0.08, 0.16), CN(-0.27 + i * 0.18, 0.25, -1.14), GOLD, "Foil")
		end
	end)
end

-- Broken Sword (Uncommon): a knight's longsword snapped mid-blade with a jagged break, its tip
-- lying at the foot; wheel pommel, leather grip, rust spots.
R.broken_sword = function(b: any, lod: number)
	b:CylZ(0.16, 0.44, CN(0, 0.22, 0), STEEL, "Metal")
	b:CylY(0.82, 0.18, CN(0, 0.84, 0), LEATHER, "Fabric")
	b:Box(V3(1.24, 0.14, 0.2), CN(0, 1.32, 0), IRON, "Metal")
	b:Ball(0.22, CN(0.64, 1.32, 0), IRON, "Metal")
	b:Ball(0.22, CN(-0.64, 1.32, 0), IRON, "Metal")
	b:Box(V3(0.36, 0.16, 0.12), CN(0, 1.46, 0), IRON, "Metal")
	b:Box(V3(0.32, 1.3, 0.07), CN(0, 2.18, 0), STEEL, "Metal")
	-- jagged break
	b:Wedge(V3(0.07, 0.34, 0.18), CN(0.07, 2.99, 0) * ang(0, -90, 0), STEEL, "Metal")
	b:Wedge(V3(0.07, 0.16, 0.14), CN(-0.09, 2.9, 0) * ang(0, 90, 0), STEEL, "Metal")
	-- the broken-off tip on the ground
	local tipCf = CN(0.42, 0.035, -0.32) * ang(0, -35, 0) * ang(90, 0, 0)
	b:Box(V3(0.3, 0.62, 0.07), tipCf, STEEL, "Metal")
	tri(b, tipCf * CN(0, 0.31, 0), 0.3, 0.4, 0.07, STEEL, "Metal")
	b:Accent(b:Ellipsoid(V3(0.2, 0.2, 0.08), CN(0, 1.32, -0.11), RUBY, "Glass"))
	b:Detail(function()
		b:Box(V3(0.07, 1.1, 0.075), CN(0, 2.12, 0), rgb(118, 124, 136), "Metal")
		for i = 0, 2 do
			b:CylY(0.04, 0.2, CN(0, 0.58 + i * 0.25, 0), rgb(70, 40, 22), "Fabric")
		end
		b:Ellipsoid(V3(0.16, 0.22, 0.08), CN(0.08, 2.5, -0.03), rgb(150, 80, 40), "SmoothPlastic")
		b:Ellipsoid(V3(0.12, 0.14, 0.08), CN(-0.09, 1.8, 0.03), rgb(150, 80, 40), "SmoothPlastic")
		b:Wedge(V3(0.08, 0.1, 0.08), CN(0.16, 2.3, 0) * ang(0, -90, 0), rgb(60, 62, 70), "Metal")
	end)
end

-- Knight Helmet (Uncommon): a steel great helm with eye slits, a brass cross of reinforcing
-- bands, breathing holes, rivets and a red plume.
R.knight_helmet = function(b: any, lod: number)
	b:CylY(0.12, 1.68, CN(0, 0.06, 0), IRON, "Metal")
	b:CylY(1.42, 1.6, CN(0, 0.79, 0), STEEL, "Metal")
	b:Ellipsoid(V3(1.6, 0.72, 1.6), CN(0, 1.5, 0), STEEL, "Metal")
	for _, s in { -1, 1 } do
		b:Box(V3(0.44, 0.09, 0.1), CN(0, 1.08, 0) * ang(0, s * 21, 0) * CN(0, 0, -0.77), INK, "SmoothPlastic")
	end
	b:Accent(b:CylY(0.14, 1.64, CN(0, 1.24, 0), GOLD_D, "Metal"))
	b:Accent(b:Box(V3(0.16, 1.18, 0.08), CN(0, 0.68, -0.79), GOLD_D, "Metal"))
	b:CylY(0.16, 0.2, CN(0, 1.9, 0), GOLD_D, "Metal")
	for i = -1, 1 do
		b:Ellipsoid(V3(0.24, 0.9, 0.22), CN(0, 2.08, 0.18) * ang(-35 - i * 12, 0, i * 14) * CN(0, 0.3, 0), rgb(196, 34, 44), "Fabric")
	end
	b:Detail(function()
		for i = 0, 3 do
			local row, col = i // 2, i % 2
			b:CylZ(0.06, 0.08, CN(0, 0.5 + row * 0.18, 0) * ang(0, -32 - col * 14, 0) * CN(0, 0, -0.79), INK, "SmoothPlastic")
		end
		for i = 0, 5 do
			b:Ball(0.08, CN(0, 1.24, 0) * ang(0, -75 + i * 30, 0) * CN(0, 0, -0.83), GOLD, "Metal")
		end
	end)
end

-- Royal Ring (Rare): a heavy gold band with sculpted shoulders, a large polished ruby in a
-- four-prong setting and two small diamonds.
R.royal_ring = function(b: any, lod: number)
	local c = CN(0, 0.86, 0)
	arc(b, c, 0.72, 0.28, 90 + 24, 450 - 24, if lod > 0 then 7 else 11, GOLD, "Metal")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.34, 0.52, 0.36), CN(s * 0.3, 1.5, 0) * ang(0, 0, s * 35), GOLD_D, "Metal")
	end
	b:CylY(0.24, 0.62, CN(0, 1.66, 0), GOLD_D, "Metal")
	b:Accent(b:Ellipsoid(V3(0.6, 0.42, 0.6), CN(0, 1.86, 0), RUBY, "Glass"))
	b:Detail(function()
		b:Accent(b:CylY(0.04, 0.3, CN(0, 2.06, 0), rgb(255, 120, 150), "Glass"))
		for i = 0, 3 do
			local a = rad(45 + i * 90)
			rod(b, V3(cos(a) * 0.3, 1.72, sin(a) * 0.3), V3(cos(a) * 0.24, 2.0, sin(a) * 0.24), 0.06, GOLD, "Metal")
		end
		for _, s in { -1, 1 } do
			b:Accent(b:Ball(0.14, CN(s * 0.42, 1.56, -0.12), rgb(220, 240, 255), "Glass"))
		end
	end)
end

-- Dog Statuette (Rare): a black basalt jackal lying on a gilded shrine chest, tall ears lined
-- with gold, a gold collar.
R.dog_statuette = function(b: any, lod: number)
	local DOG = BASALT
	b:Box(V3(1.4, 0.96, 2.3), CN(0, 0.48, 0.1), rgb(30, 30, 36), "Slate")
	b:Box(V3(1.56, 0.1, 2.46), CN(0, 1.0, 0.1), GOLD, "Foil")
	b:Detail(function()
		b:Box(V3(1.56, 0.1, 2.46), CN(0, 0.05, 0.1), GOLD, "Foil")
		for _, s in { -1, 1 } do
			b:Box(V3(0.02, 0.5, 0.12), CN(s * 0.71, 0.53, -0.4), GOLD, "Foil")
			b:Box(V3(0.02, 0.5, 0.12), CN(s * 0.71, 0.53, 0.6), GOLD, "Foil")
			b:Box(V3(0.02, 0.16, 0.5), CN(s * 0.71, 0.53, 0.1), TURQ, "SmoothPlastic")
		end
	end)
	b:Ellipsoid(V3(0.82, 0.6, 1.5), CN(0, 1.32, 0.25), DOG, "Slate")
	b:Ellipsoid(V3(0.86, 0.62, 0.74), CN(0, 1.36, 0.66), DOG, "Slate")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.2, 0.18, 0.8), CN(s * 0.22, 1.13, -0.58), DOG, "Slate")
	end
	b:Ellipsoid(V3(0.44, 0.78, 0.46), CN(0, 1.72, -0.34) * ang(-20, 0, 0), DOG, "Slate")
	b:Ellipsoid(V3(0.48, 0.44, 0.58), CN(0, 2.08, -0.5), DOG, "Slate")
	b:Ellipsoid(V3(0.24, 0.22, 0.52), CN(0, 2.0, -0.86) * ang(8, 0, 0), DOG, "Slate")
	for _, s in { -1, 1 } do
		local ear = CN(s * 0.15, 2.22, -0.44) * ang(0, 0, s * -8)
		if lod > 0 then
			b:Wedge(V3(0.07, 0.5, 0.24), ear * CN(0, 0.25, 0) * ang(0, s * 90, 0), DOG, "Slate")
		else
			tri(b, ear, 0.24, 0.52, 0.07, DOG, "Slate")
		end
	end
	b:Accent(b:Ellipsoid(V3(0.52, 0.12, 0.52), CN(0, 1.56, -0.3) * ang(-20, 0, 0), GOLD, "Foil"))
	b:Detail(function()
		b:Ellipsoid(V3(0.14, 0.7, 0.14), CN(0, 1.25, 1.1) * ang(60, 0, 0), DOG, "Slate")
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.1, 0.34, 0.03), CN(s * 0.16, 2.44, -0.48) * ang(0, 0, s * -8), GOLD, "Foil")
			b:Ball(0.08, CN(s * 0.15, 2.14, -0.75), GOLD, "Foil")
		end
	end)
end

-- Crystal of Time (Rare): an hourglass of two turquoise crystal bulbs in a gold-and-lapis frame,
-- with glowing golden sand falling between them.
R.crystal_of_time = function(b: any, lod: number)
	local CRY = rgb(110, 230, 220)
	b:CylY(0.24, 1.6, CN(0, 0.12, 0), GOLD, "Metal")
	b:CylY(0.24, 1.6, CN(0, 2.98, 0), GOLD, "Metal")
	for i = 0, 2 do
		local a = rad(90 + i * 120)
		b:CylY(2.62, 0.13, CN(cos(a) * 0.66, 1.55, sin(a) * 0.66), GOLD_D, "Metal")
	end
	b:Prism(CN(0, 0.24, 0) * ang(0, 45, 0), 0.74, 0.6, 0.66, CRY, "Glass", { Transparency = 0.35 })
	b:Prism(CN(0, 2.86, 0) * ang(180, 45, 0), 0.74, 0.6, 0.66, CRY, "Glass", { Transparency = 0.35 })
	b:Accent(b:Box(V3(0.5, 0.4, 0.5), CN(0, 0.46, 0) * ang(0, 45, 0), rgb(255, 176, 48), "Neon"))
	b:Accent(b:CylY(1.1, 0.06, CN(0, 1.15, 0), rgb(255, 190, 70), "Neon"))
	b:Detail(function()
		b:Prism(CN(0, 2.26, 0) * ang(180, 45, 0), 0.34, 0.06, 0.26, rgb(255, 176, 48), "Neon")
		b:CylY(0.12, 1.66, CN(0, 0.3, 0), LAPIS, "SmoothPlastic")
		b:CylY(0.12, 1.66, CN(0, 2.8, 0), LAPIS, "SmoothPlastic")
		for i = 0, 2 do
			local a = rad(90 + i * 120)
			b:Ball(0.22, CN(cos(a) * 0.66, 3.16, sin(a) * 0.66), GOLD, "Metal")
		end
		b:Accent(b:Gem(0.24, CN(0, 3.24, 0), TURQ, "Glass"))
	end)
end

-- Cursed Idol (Rare): a squat dark-jade idol crouching on a stepped pedestal, hugging its belly,
-- with a block head, heavy brow, glowing green eyes, a grimacing mouth and a sun-disc crest.
R.cursed_idol = function(b: any, lod: number)
	local JADE = rgb(52, 92, 70)
	local JADE_D = rgb(32, 58, 46)
	local GLOW = rgb(120, 255, 110)
	b:Box(V3(1.5, 0.46, 1.5), CN(0, 0.23, 0), rgb(62, 58, 56), "Slate")
	b:Box(V3(1.22, 0.14, 1.22), CN(0, 0.53, 0), rgb(84, 78, 72), "Slate")
	b:Ellipsoid(V3(1.0, 0.86, 0.8), CN(0, 1.02, 0.05), JADE, "Marble")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.38, 0.36, 0.56), CN(s * 0.34, 0.76, -0.26), JADE_D, "Marble")
		b:Ellipsoid(V3(0.24, 0.62, 0.26), CN(s * 0.46, 1.08, -0.2) * ang(-20, 0, s * -28), JADE_D, "Marble")
	end
	b:CylZ(0.2, 1.6, CN(0, 2.02, 0.52), JADE_D, "Marble")
	b:Box(V3(1.1, 1.0, 0.86), CN(0, 1.92, 0), JADE, "Marble")
	b:Box(V3(1.18, 0.2, 0.3), CN(0, 2.2, -0.36), JADE_D, "Marble")
	for _, s in { -1, 1 } do
		b:Accent(b:Ellipsoid(V3(0.24, 0.1, 0.06), CN(s * 0.25, 2.0, -0.47), GLOW, "Neon"))
	end
	b:Box(V3(0.7, 0.22, 0.08), CN(0, 1.6, -0.42), INK, "SmoothPlastic")
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Box(V3(0.32, 0.2, 0.04), CN(s * 0.25, 2.0, -0.44), INK, "SmoothPlastic")
			b:Cyl(0.08, 0.3, CN(s * 0.58, 1.78, 0), GOLD, "Metal")
		end
		b:Wedge(V3(0.2, 0.3, 0.16), CN(0, 1.84, -0.5), JADE_D, "Marble")
		for i = 0, 3 do
			b:Box(V3(0.08, 0.1, 0.04), CN(-0.24 + i * 0.16, 1.66, -0.45), IVORY, "SmoothPlastic")
		end
		for i = 0, 4 do
			local a = rad(20 + i * 35)
			b:Ball(0.14, CN(cos(a) * 0.8, 2.02 + sin(a) * 0.8, 0.52), GOLD, "Metal")
		end
		slab(b, V3(-0.2, 1.3, -0.33), V3(0.1, 0.8, -0.38), 0.04, 0.03, GLOW, "Neon")
		b:Ball(0.26, CN(-0.45, 0.72, -0.5), IVORY, "SmoothPlastic")
		b:Ball(0.07, CN(-0.5, 0.74, -0.62), INK, "SmoothPlastic")
		b:Ball(0.07, CN(-0.4, 0.74, -0.62), INK, "SmoothPlastic")
	end)
end

-- Sealed Sarcophagus (Epic): a sandstone chest on a plinth under an anthropoid gold lid with a
-- striped nemes head and a gold face, crossed arms, bronze bands and red wax seals.
R.sealed_sarcophagus = function(b: any, lod: number)
	b:Box(V3(1.5, 0.22, 3.8), CN(0, 0.11, 0), SAND_D, "Sandstone")
	b:Box(V3(1.24, 0.7, 3.5), CN(0, 0.57, 0), SAND, "Sandstone")
	b:Ellipsoid(V3(1.22, 0.7, 3.0), CN(0, 0.95, 0.22), GOLD, "Foil")
	b:Ellipsoid(V3(1.16, 0.74, 1.1), CN(0, 1.04, -1.16), LAPIS, "SmoothPlastic")
	local face = CN(0, 1.2, -1.52) * ang(-30, 0, 0)
	b:Accent(b:Ellipsoid(V3(0.66, 0.74, 0.46), face, GOLD, "Foil"))
	for _, s in { -1, 1 } do
		b:Box(V3(0.24, 0.16, 0.7), CN(s * 0.44, 1.2, -0.86) * ang(0, 0, s * -10), LAPIS, "SmoothPlastic")
		rod(b, V3(s * 0.42, 1.22, -0.75), V3(-s * 0.22, 1.3, -0.2), 0.13, GOLD_D, "Foil")
	end
	for i, z in { 0.35, 1.05 } do
		b:Box(V3(1.3, 0.1, 0.18), CN(0, 1.3, z), rgb(150, 92, 44), "Metal")
		b:Accent(b:CylY(0.1, 0.4, CN(0, 1.37, z), rgb(176, 22, 30), "SmoothPlastic"))
		b:Detail(function()
			for _, s in { -1, 1 } do
				b:Box(V3(0.06, 0.95, 0.18), CN(s * 0.64, 0.7, z), rgb(150, 92, 44), "Metal")
			end
			if i == 1 then
				b:CylY(0.04, 0.2, CN(0, 1.43, z), GOLD, "Foil")
			end
		end)
	end
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.2, 0.09, 0.08), face * CN(s * 0.15, 0.1, -0.21), IVORY, "SmoothPlastic")
			b:Ball(0.07, face * CN(s * 0.15, 0.1, -0.24), INK, "SmoothPlastic")
			b:Box(V3(0.26, 0.05, 0.18), CN(s * 0.45, 1.27, -0.86) * ang(0, 0, s * -10), GOLD, "Foil")
		end
		b:Ellipsoid(V3(0.12, 0.42, 0.14), face * CN(0, -0.48, -0.08), LAPIS, "SmoothPlastic")
		for _, h in { 0.16, -0.06 } do
			local f = math.sqrt(1 - (h / 0.37) ^ 2)
			b:Ellipsoid(V3(1.16 * f + 0.04, 0.07, 1.1 * f + 0.04), CN(0, 1.04 + h, -1.16), GOLD, "Foil")
		end
		b:Ellipsoid(V3(0.9, 0.12, 0.42), CN(0, 1.22, -0.98), TURQ, "SmoothPlastic")
		rod(b, V3(0.26, 1.34, -0.3), V3(0.1, 1.38, -0.68), 0.05, LAPIS_D, "SmoothPlastic")
		rod(b, V3(-0.26, 1.34, -0.3), V3(-0.12, 1.4, -0.66), 0.05, GOLD, "Foil")
		b:Ellipsoid(V3(0.7, 0.4, 0.5), CN(0, 1.04, 1.55), GOLD_D, "Foil")
		for i = 0, 2 do
			for _, s in { -1, 1 } do
				b:Box(V3(0.02, 0.14, 0.24), CN(s * 0.62, 0.6, -1.1 + i * 0.45), LAPIS, "SmoothPlastic")
			end
		end
	end)
end

-- Eye of Ancient God (Epic): a gold Wadjet eye standing on a lapis base, with a lapis brow,
-- a glowing turquoise pupil, the teardrop line and spiral, and a fan of sun rays behind.
R.eye_of_ancient_god = function(b: any, lod: number)
	local cy = 1.02
	b:Box(V3(1.4, 0.18, 0.6), CN(0, 0.09, 0.05), LAPIS, "SmoothPlastic")
	b:Ellipsoid(V3(1.5, 0.66, 0.3), CN(0, cy, 0), IVORY, "Marble")
	local upper = CN(0, cy - 0.61, 0)
	arc(b, upper, 1.0, 0.14, 38, 142, if lod > 0 then 2 else 4, GOLD, "Foil")
	local lower = CN(0, cy + 0.88, 0)
	arc(b, lower, 1.16, 0.12, -133, -47, if lod > 0 then 2 else 3, GOLD, "Foil")
	b:Accent(b:CylZ(0.1, 0.56, CN(0, cy, -0.12), LAPIS_D, "SmoothPlastic"))
	b:Accent(b:Ball(0.28, CN(0, cy, -0.16), rgb(80, 255, 230), "Neon"))
	arc(b, CN(0, cy - 0.5, 0), 1.12, 0.16, 42, 138, if lod > 0 then 2 else 3, LAPIS, "SmoothPlastic")
	slab(b, V3(-0.74, cy - 0.02, 0), V3(-1.2, cy - 0.04, 0), 0.12, 0.12, GOLD, "Foil")
	slab(b, V3(0.12, cy - 0.32, 0), V3(0.14, 0.2, 0), 0.12, 0.12, GOLD, "Foil")
	b:Detail(function()
		b:Box(V3(1.46, 0.05, 0.64), CN(0, 0.2, 0.05), GOLD, "Foil")
		b:Ball(0.08, CN(0.05, cy + 0.05, -0.3), rgb(255, 255, 255), "Neon")
		b:Ball(0.18, CN(0.14, 0.26, 0), GOLD, "Foil")
		arc(b, CN(-0.62, 0.5, 0), 0.26, 0.11, 100, 360, 4, GOLD, "Foil")
		for i = 0, 6 do
			local a = rad(20 + i * 23.3)
			local p0 = V3(cos(a) * 0.95, cy - 0.15 + sin(a) * 0.95, 0.16)
			local p1 = V3(cos(a) * 1.22, cy - 0.15 + sin(a) * 1.22, 0.16)
			slab(b, p0, p1, 0.08, 0.06, GOLD_D, "Foil")
		end
	end)
end

-- Crown of Forgotten King (Legendary): a gold crown on an ermine rim with a red velvet cap,
-- two crossing arches, an orb and cross, pearl-tipped points and a ring of jewels.
R.crown_of_forgotten_king = function(b: any, lod: number)
	b:CylY(0.24, 2.48, CN(0, 0.12, 0), rgb(244, 240, 232), "Fabric")
	b:Detail(function()
		for i = 0, 5 do
			b:Ball(0.08, CN(0, 0.12, 0) * ang(0, i * 60 + 15, 0) * CN(0, 0, -1.24), INK, "SmoothPlastic")
		end
	end)
	b:CylY(0.62, 2.28, CN(0, 0.55, 0), GOLD, "Foil")
	b:Ellipsoid(V3(2.08, 1.44, 2.08), CN(0, 0.84, 0), rgb(150, 18, 40), "Fabric")
	local n = if lod > 0 then 2 else 3
	arc(b, CN(0, 0.86, 0), 1.06, 0.14, 12, 168, n, GOLD, "Foil")
	arc(b, CN(0, 0.86, 0) * ang(0, 90, 0), 1.06, 0.14, 12, 168, n, GOLD, "Foil")
	b:Accent(b:Ball(0.34, CN(0, 2.02, 0), GOLD, "Foil"))
	b:Detail(function()
		b:Box(V3(0.08, 0.36, 0.08), CN(0, 2.32, 0), GOLD, "Foil")
		b:Box(V3(0.24, 0.08, 0.08), CN(0, 2.36, 0), GOLD, "Foil")
	end)
	local pts = if lod > 0 then 4 else 6
	for i = 0, pts - 1 do
		local cf = CN(0, 0.86, 0) * ang(0, i * 360 / pts + 180 / pts, 0) * CN(0, 0, -1.08)
		b:Box(V3(0.5, 0.5, 0.08), cf * ang(0, 0, 45), GOLD, "Foil")
		b:Detail(function()
			b:Ball(0.16, cf * CN(0, 0.38, 0), IVORY, "SmoothPlastic")
		end)
	end
	if lod > 0 then
		b:Accent(b:Ellipsoid(V3(0.32, 0.36, 0.16), CN(0, 0.56, -1.16), rgb(40, 90, 230), "Glass"))
	else
		b:Accent(b:Gem(0.3, CN(0, 0.56, -1.16), rgb(40, 90, 230), "Glass"))
	end
	b:Detail(function()
		local jewels = { RUBY, rgb(30, 190, 110), RUBY, rgb(30, 190, 110) }
		for i, col in jewels do
			b:Accent(b:Ellipsoid(V3(0.2, 0.24, 0.1), CN(0, 0.55, 0) * ang(0, 45 + (i - 1) * 90, 0) * CN(0, 0, -1.15), col, "Glass"))
		end
	end)
end

-- Dragon Egg (Legendary): a crimson egg banded with gold scale ridges, rows of scale plates and
-- spines, split by a glowing ember crack, resting in a nest of basalt stones and gold coins.
R.dragon_egg = function(b: any, lod: number)
	local SHELL = rgb(122, 22, 34)
	local PLATE = rgb(156, 36, 46)
	local RIDGE = rgb(214, 150, 44)
	local GLOW = rgb(255, 150, 40)
	b:CylY(0.1, 1.9, CN(0, 0.05, 0), rgb(46, 40, 40), "Basalt")
	local rocks = if lod > 0 then 3 else 5
	for i = 0, rocks - 1 do
		local a = i * 360 / rocks + 20
		b:Box(V3(0.56, 0.44, 0.5), CN(0, 0.3, 0) * ang(0, a, 0) * CN(0, 0, -0.9) * ang(12, 30, 8), rgb(52, 48, 50), "Basalt")
	end
	b:Ellipsoid(V3(1.46, 1.96, 1.46), CN(0, 1.28, 0), SHELL, "SmoothPlastic")
	for i = 0, 2 do
		b:Ellipsoid(V3(0.14, 2.0, 1.5), CN(0, 1.28, 0) * ang(0, 30 + i * 60, 0), RIDGE, "Foil")
	end
	b:Ellipsoid(V3(1.5, 0.12, 1.5), CN(0, 1.18, 0), RIDGE, "Foil")
	local function onShell(x: number, y: number): Vector3
		local u, v = x / 0.73, (y - 1.28) / 0.98
		return V3(x, y, -0.73 * math.sqrt(math.max(0, 1 - u * u - v * v)) - 0.02)
	end
	local crack = { onShell(-0.32, 1.72), onShell(-0.1, 1.48), onShell(-0.22, 1.24), onShell(0.08, 0.98), onShell(0.0, 0.74) }
	for i = 1, #crack - 1 do
		b:Accent(slab(b, crack[i], crack[i + 1], 0.07, 0.06, GLOW, "Neon"))
	end
	b:Detail(function()
		-- scale plates in two rows
		for row, y in { 0.86, 1.62 } do
			local v = (y - 1.28) / 0.98
			local r = 0.73 * math.sqrt(1 - v * v)
			for i = 0, 5 do
				local a = rad(i * 60 + row * 30 + 15)
				local pos = V3(cos(a) * r, y, sin(a) * r)
				b:Ellipsoid(V3(0.4, 0.3, 0.12), look(pos, pos + V3(cos(a), -v * 0.6, sin(a))), PLATE, "SmoothPlastic")
			end
		end
		for i = 0, 2 do
			local a = rad(150 + i * 60)
			local p = V3(cos(a) * 0.36, 2.0 + (i % 2) * 0.06, sin(a) * 0.36)
			blob(b, p, p + V3(cos(a) * 0.16, 0.3, sin(a) * 0.16), 0.12, RIDGE, "Foil", 0.6)
		end
		for i = 0, 2 do
			b:Disc(CN(-0.55 + i * 0.5, 0.14, -0.84 + (i % 2) * 0.12) * ang(8, 0, -6), 0.26, 0.05, GOLD, "Metal")
		end
	end)
end

-- Golden Dog Idol (Legendary): a polished gold dog sitting on a lapis-and-marble plinth, with
-- ruby eyes, floppy ears, an emerald on its brow, a turquoise collar with a medal and a curled tail.
R.golden_dog_idol = function(b: any, lod: number)
	b:Box(V3(1.6, 0.36, 1.6), CN(0, 0.18, 0), LAPIS, "SmoothPlastic")
	b:Box(V3(1.7, 0.1, 1.7), CN(0, 0.41, 0), GOLD_D, "Metal")
	b:Box(V3(1.42, 0.2, 1.42), CN(0, 0.56, 0), rgb(236, 232, 224), "Marble")
	b:Ellipsoid(V3(0.98, 0.72, 0.94), CN(0, 0.98, 0.2), GOLD, "Foil")
	b:Ellipsoid(V3(0.74, 1.04, 0.7), CN(0, 1.34, -0.06) * ang(-12, 0, 0), GOLD, "Foil")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.22, 0.82, 0.24), CN(s * 0.2, 1.02, -0.36) * ang(-6, 0, 0), GOLD, "Foil")
	end
	b:Ellipsoid(V3(0.66, 0.6, 0.62), CN(0, 2.02, -0.16), GOLD, "Foil")
	b:Ellipsoid(V3(0.38, 0.32, 0.46), CN(0, 1.92, -0.46), GOLD, "Foil")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V3(0.2, 0.56, 0.32), CN(s * 0.36, 1.92, -0.1) * ang(0, 0, s * 18), GOLD_D, "Foil")
	end
	b:Accent(b:Ellipsoid(V3(0.66, 0.14, 0.62), CN(0, 1.7, -0.12) * ang(-12, 0, 0), TURQ, "SmoothPlastic"))
	b:Detail(function()
		b:Ball(0.13, CN(0, 1.98, -0.69), INK, "SmoothPlastic")
		for _, s in { -1, 1 } do
			b:Accent(b:Ball(0.12, CN(s * 0.15, 2.12, -0.42), RUBY, "Glass"))
			b:Ellipsoid(V3(0.24, 0.12, 0.3), CN(s * 0.2, 0.7, -0.44), GOLD, "Foil")
			b:Ellipsoid(V3(0.3, 0.14, 0.42), CN(s * 0.4, 0.71, 0.05), GOLD, "Foil")
		end
		b:Accent(b:CylZ(0.05, 0.2, CN(0, 1.56, -0.42) * ang(-12, 0, 0), GOLD, "Metal"))
		b:Accent(b:Gem(0.12, CN(0, 2.3, -0.36), rgb(30, 200, 120), "Glass"))
		blob(b, V3(0, 0.82, 0.62), V3(0, 1.08, 0.86), 0.16, GOLD_D, "Foil")
		blob(b, V3(0, 1.08, 0.86), V3(0, 1.3, 0.72), 0.14, GOLD_D, "Foil")
		for i = 0, 3 do
			b:Box(V3(0.12, 0.12, 0.02), CN(-0.45 + i * 0.3, 0.18, -0.81), GOLD, "Foil")
		end
	end)
end

-- HUGE STATUE (Secret world find): a colossal sandstone dog sitting on a stepped temple pedestal,
-- with a striped lapis wig, a gold headband, turquoise inlaid eyes, a gold collar and medallion,
-- cracks, moss and fallen rubble.
R.huge_statue = function(b: any, lod: number)
	local S = SAND
	b:Box(V3(17.5, 2.0, 18.4), CN(0, 1.0, 0.8), SAND_D, "Sandstone")
	b:Box(V3(14.6, 1.8, 15.0), CN(0, 2.9, 1.2), S, "Sandstone")
	b:Ellipsoid(V3(10.6, 7.6, 9.8), CN(0, 7.4, 3.2), S, "Sandstone")
	b:Ellipsoid(V3(7.8, 10.8, 7.2), CN(0, 10.4, -0.4) * ang(-10, 0, 0), S, "Sandstone")
	for _, s in { -1, 1 } do
		b:CylY(7.0, 2.4, CN(s * 2.3, 7.2, -3.6), S, "Sandstone")
	end
	b:Ellipsoid(V3(6.4, 6.0, 6.2), CN(0, 17.4, -1.4), S, "Sandstone")
	b:Ellipsoid(V3(3.6, 3.0, 4.4), CN(0, 16.4, -4.4), SAND_L, "Sandstone")
	for _, s in { -1, 1 } do
		b:Box(V3(1.4, 6.0, 2.2), CN(s * 3.1, 14.6, -1.2) * ang(0, 0, s * 6), LAPIS, "Sandstone")
		local ear = CN(s * 1.9, 20.0, -1.2) * ang(0, 0, s * -10)
		if lod > 0 then
			b:Wedge(V3(0.9, 3.4, 1.8), ear * CN(0, 1.7, 0) * ang(0, s * 90, 0), S, "Sandstone")
		else
			tri(b, ear, 1.8, 3.6, 0.9, S, "Sandstone")
		end
	end
	b:Accent(b:Ellipsoid(V3(6.6, 1.2, 6.0), CN(0, 13.6, -0.9) * ang(-10, 0, 0), GOLD, "Foil"))
	b:Detail(function()
		b:Ellipsoid(V3(6.7, 0.9, 6.5), CN(0, 18.9, -1.4), GOLD, "Foil")
		b:Box(V3(6.0, 1.9, 1.8), CN(0, 0.95, -9.4), SAND_D, "Sandstone")
		b:Box(V3(6.0, 1.0, 1.4), CN(0, 2.3, -6.2), S, "Sandstone")
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(2.9, 1.6, 3.6), CN(s * 2.3, 4.6, -4.6), SAND_L, "Sandstone")
			b:Accent(b:Ellipsoid(V3(1.1, 0.6, 0.4), CN(s * 1.25, 18.0, -4.3), TURQ, "Glass"))
			for i = 0, 2 do
				b:Box(V3(1.45, 0.45, 2.25), CN(s * 3.1, 16.6 - i * 1.6, -1.2) * ang(0, 0, s * 6), GOLD_D, "Sandstone")
			end
		end
		b:Ball(1.3, CN(0, 17.2, -6.5), BASALT, "Slate")
		b:Accent(b:CylZ(0.5, 2.0, CN(0, 12.6, -4.0) * ang(-10, 0, 0), TURQ, "Glass"))
		b:Ellipsoid(V3(2.2, 1.6, 7.5), CN(-5.4, 4.6, 4.5) * ang(0, -25, 0), S, "Sandstone")
		slab(b, V3(2.6, 12.6, -3.6), V3(1.4, 8.6, -4.0), 0.25, 0.25, rgb(110, 88, 60), "Sandstone")
		slab(b, V3(-4.2, 9.0, -1.6), V3(-3.0, 5.4, -3.2), 0.25, 0.25, rgb(110, 88, 60), "Sandstone")
		b:Ellipsoid(V3(4.0, 0.6, 3.0), CN(-4.6, 3.85, -4.6), MOSS, "Grass")
		b:Ellipsoid(V3(3.0, 0.5, 2.4), CN(5.8, 1.95, -8.2), MOSS, "Grass")
		b:Box(V3(1.6, 1.2, 1.4), CN(6.0, 2.9, -6.4) * ang(20, 30, 10), SAND_D, "Sandstone")
		b:Box(V3(1.1, 0.9, 1.0), CN(-6.4, 0.6, -9.6) * ang(0, 40, 15), SAND_D, "Sandstone")
	end)
end

return R
