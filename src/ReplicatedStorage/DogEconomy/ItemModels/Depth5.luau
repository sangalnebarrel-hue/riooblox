-- Find models of depth 5, THE VOID (25 items): deep black / indigo bodies, cosmic neon (violet,
-- cyan, magenta), glass shells and impossible geometry. Loaded by ItemModels (see its header):
-- each recipe builds around the origin, resting on Y = 0, front towards -Z, at the size of the
-- find's old voxel model. lod 0 <= 40 parts, lod 1 <= 14 parts (tests/item_models.luau checks).
-- b:Accent marks the 1-4 signature parts that mutation styling recolours (DiscoveryVisuals.Style).
local PI = math.pi
local rad = math.rad
local V3 = Vector3.new
local CF = CFrame.new
local Ang = CFrame.Angles
local C = Color3.fromRGB

-- VOID palette
local VOID = C(16, 12, 28) -- near-black violet body
local DEEP = C(30, 20, 64)
local INDIGO = C(48, 32, 104)
local GUNMETAL = C(62, 58, 84)
local OBSIDIAN = C(22, 18, 34)
local VIOLET = C(170, 80, 255)
local CYAN = C(70, 230, 255)
local MAGENTA = C(255, 70, 210)
local STAR = C(238, 232, 255)
local GLASS = C(150, 170, 255)
local BLACK = C(4, 4, 8)

local function T(t: number)
	return { Transparency = t }
end

-- Vertical ring in the cf XY plane (facing the front), centred on cf.
local function vring(b, cf, radius, thick, color, mat, n, props)
	return b:Ring(cf * Ang(PI / 2, 0, 0), radius, thick, color, mat, n, props)
end

-- Arc of n rods in the cf XY plane from angle a0 to a1 (radians, 0 = +X, PI/2 = +Y).
local function arc(b, cf, radius, thick, a0, a1, n, color, mat, props)
	local out = {}
	local step = (a1 - a0) / n
	for i = 0, n - 1 do
		local t0, t1 = a0 + step * i, a0 + step * (i + 1)
		local p0 = cf:PointToWorldSpace(V3(math.cos(t0) * radius, math.sin(t0) * radius, 0))
		local p1 = cf:PointToWorldSpace(V3(math.cos(t1) * radius, math.sin(t1) * radius, 0))
		local mid, dir = (p0 + p1) / 2, (p1 - p0).Unit
		local len = (p1 - p0).Magnitude + thick * 0.4
		table.insert(out, b:Rod(mid - dir * len / 2, mid + dir * len / 2, thick, color, mat, props))
	end
	return out
end

-- Flat triangle (two wedges) in the cf XY plane: base centre at radius r0 along angle a,
-- pointing outwards, `len` long, base `w` wide and `t` thick.
local function spike(b, cf, a, r0, len, w, t, color, mat, props)
	local u = V3(math.cos(a), math.sin(a), 0)
	local p = V3(-math.sin(a), math.cos(a), 0)
	local out = {}
	for _, s in { 1, -1 } do
		local py = p * s
		local vz = -u
		local centre = u * r0 + py * (w / 4) + u * (len / 2)
		local local_ = CFrame.fromMatrix(centre, py:Cross(vz), py, vz)
		table.insert(out, b:Wedge(V3(t, w / 2, len), cf * local_, color, mat, props))
	end
	return out
end

-- The 12 edges of a box of `size` centred on cf.
local function edges(b, cf, size, w, color, mat, props)
	local h = size / 2
	local out = {}
	for _, s1 in { -1, 1 } do
		for _, s2 in { -1, 1 } do
			table.insert(out, b:Box(V3(size.X + w, w, w), cf * CF(0, s1 * h.Y, s2 * h.Z), color, mat, props))
			table.insert(out, b:Box(V3(w, size.Y + w, w), cf * CF(s1 * h.X, 0, s2 * h.Z), color, mat, props))
			table.insert(out, b:Box(V3(w, w, size.Z + w), cf * CF(s1 * h.X, s2 * h.Y, 0), color, mat, props))
		end
	end
	return out
end

-- Upright band (crown) of n flat boxes around cf's Y axis.
local function band(b, cf, radius, height, thick, n, color, mat, props)
	local out = {}
	local len = 2 * radius * math.tan(PI / n) + thick * 0.5
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 2 * PI
		table.insert(out, b:Box(V3(len, height, thick), cf * Ang(0, a, 0) * CF(0, 0, -radius), color, mat, props))
	end
	return out
end

-- Obsidian display stand of the COSMIC_COLLAPSE set (moon, dead star, sun): base + neon rim + stem.
-- Returns the stem top height.
local function stand(b, lod)
	b:Disc(CF(0, 0.1, 0), 1.45, 0.2, OBSIDIAN, "Glass")
	if lod <= 0 then
		b:Disc(CF(0, 0.2, 0), 1.18, 0.04, VIOLET, "Neon")
	end
	b:CylY(0.42, 0.26, CF(0, 0.41, 0), GUNMETAL, "Metal")
	return 0.62
end

-- Black plinth with a neon strip for the floating REALITY_BREAKDOWN panels.
local function plinth(b, glow)
	b:Box(V3(1.5, 0.26, 0.62), CF(0, 0.13, 0), OBSIDIAN, "Glass")
	b:Detail(function()
		b:Box(V3(1.2, 0.06, 0.04), CF(0, 0.15, -0.32), glow, "Neon")
	end)
end

local R = {}

-- COMMON -----------------------------------------------------------------------------------------

R.void_fragment = function(b, lod)
	b:Ellipsoid(V3(2.5, 0.75, 1.9), CF(0, 0.3, 0.05) * Ang(0, 0.3, 0), OBSIDIAN, "Slate")
	b:Detail(function()
		b:Box(V3(0.9, 0.42, 0.8), CF(0.85, 0.3, 0.45) * Ang(0.12, 0.6, 0.1), VOID, "Slate")
		b:Box(V3(0.7, 0.34, 0.6), CF(-0.95, 0.26, -0.35) * Ang(-0.1, 0.9, 0.12), VOID, "Slate")
	end)
	-- main shard: smoky violet glass around a neon core
	local main = CF(0.05, 0.35, 0) * Ang(0.06, 0.6, -0.08)
	b:Prism(main, 0.95, 2.15, 0.75, C(60, 36, 130), "Glass", T(0.5))
	b:Accent(b:Box(V3(0.34, 1.95, 0.34), main * CF(0, 1.05, 0), VIOLET, "Neon"))
	local left = CF(-0.7, 0.3, 0.2) * Ang(0.1, 0.3, 0.5)
	b:Prism(left, 0.6, 1.25, 0.45, C(84, 52, 170), "Glass", T(0.4))
	b:Prism(CF(0.72, 0.3, -0.25) * Ang(-0.25, -0.5, -0.55), 0.52, 0.95, 0.4, C(84, 52, 170), "Glass", T(0.4))
	b:Detail(function()
		b:Box(V3(0.2, 1.05, 0.2), left * CF(0, 0.6, 0), MAGENTA, "Neon")
		b:Accent(b:Gem(0.32, CF(0.62, 2.85, -0.25), CYAN, "Neon"))
	end)
end

R.anti_matter_cube = function(b, lod)
	local c = CF(0, 1.2, 0)
	local s = 2.2
	if lod <= 0 then
		edges(b, c, V3(s, s, s), 0.16, GUNMETAL, "Metal")
		b:Detail(function()
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						b:Box(V3(0.3, 0.3, 0.3), c * CF(x * s / 2, y * s / 2, z * s / 2), OBSIDIAN, "Metal")
					end
				end
			end
		end)
	else
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				b:Box(V3(0.18, s, 0.18), c * CF(x * s / 2, 0, z * s / 2), GUNMETAL, "Metal")
			end
		end
		b:Box(V3(s + 0.18, 0.18, s + 0.18), c * CF(0, -s / 2, 0), GUNMETAL, "Metal")
		b:Box(V3(s + 0.18, 0.18, s + 0.18), c * CF(0, s / 2, 0), GUNMETAL, "Metal")
	end
	b:Box(V3(s - 0.1, s - 0.1, s - 0.1), c, GLASS, "Glass", T(0.78))
	-- anti-matter: a black core in a magenta glow
	b:Accent(b:Ball(0.95, c, MAGENTA, "Neon", T(0.35)))
	b:Ball(0.62, c, BLACK, "SmoothPlastic")
	b:Detail(function()
		local orbit = c * Ang(rad(20), 0, rad(-25))
		b:Ring(orbit, 0.78, 0.05, CYAN, "Neon", 10)
		b:Accent(b:Ball(0.16, orbit * CF(0.78, 0, 0), CYAN, "Neon"))
	end)
end

-- UNCOMMON ---------------------------------------------------------------------------------------

R.glitched_coin = function(b, lod)
	local c = CF(0, 1.12, 0)
	b:Accent(b:CylZ(0.3, 2.24, c, VIOLET, "Neon"))
	b:CylZ(0.42, 1.96, c, GUNMETAL, "Metal")
	-- emblem: a pixel diamond
	b:Accent(b:Box(V3(0.62, 0.62, 0.1), c * CF(0, 0, -0.22) * Ang(0, 0, PI / 4), CYAN, "Neon"))
	-- displaced slices of the coin (the glitch)
	b:Box(V3(1.7, 0.24, 0.42), c * CF(0.38, 0.42, 0), GUNMETAL, "Metal")
	b:Box(V3(1.4, 0.18, 0.44), c * CF(-0.42, -0.5, -0.01), INDIGO, "Metal")
	b:Detail(function()
		b:CylZ(0.04, 2.24, c * CF(-0.13, 0.02, 0.24), CYAN, "Neon", T(0.55))
		b:CylZ(0.04, 2.24, c * CF(0.13, -0.02, 0.26), MAGENTA, "Neon", T(0.55))
		b:Box(V3(0.16, 0.16, 0.12), c * CF(-0.32, 0.3, -0.23), MAGENTA, "Neon")
		b:Box(V3(0.16, 0.16, 0.12), c * CF(0.3, -0.28, -0.23), CYAN, "Neon")
		b:Box(V3(0.2, 0.2, 0.2), c * CF(1.32, 0.62, -0.1), CYAN, "Neon")
		b:Box(V3(0.14, 0.14, 0.14), c * CF(1.25, 0.95, 0.05), MAGENTA, "Neon")
		b:Box(V3(0.16, 0.16, 0.16), c * CF(-1.3, -0.62, 0), VIOLET, "Neon")
	end)
end

R.piece_of_reality = function(b, lod)
	-- a torn-out pane of the ordinary world (sky, grass, sun), void black behind, cyan torn edges
	local c = CF(0, 1.38, 0) * Ang(0, 0, rad(-8))
	local SKY = C(110, 190, 255)
	b:Box(V3(1.9, 1.5, 0.2), c, SKY, "SmoothPlastic")
	b:Box(V3(1.9, 0.42, 0.22), c * CF(0, -0.55, 0), C(96, 190, 82), "SmoothPlastic")
	-- jagged sides
	spike(b, c * CF(0.95, 0.05, 0), 0, 0, 0.75, 1.3, 0.2, SKY, "SmoothPlastic")
	spike(b, c * CF(-0.95, 0.1, 0), PI, 0, 0.5, 1.1, 0.2, SKY, "SmoothPlastic")
	b:Detail(function()
		spike(b, c * CF(-0.2, 0.75, 0), PI / 2, 0, 0.55, 1.3, 0.2, SKY, "SmoothPlastic")
		spike(b, c * CF(0.25, -0.76, 0), -PI / 2, 0, 0.6, 1.2, 0.22, C(96, 190, 82), "SmoothPlastic")
	end)
	-- void back and torn neon edge
	b:Box(V3(2.05, 1.65, 0.12), c * CF(0, 0, 0.14), VOID, "Glass")
	b:Accent(b:Rod((c * CF(-0.95, 0.75, -0.11)).Position, (c * CF(-0.2, 1.3, -0.11)).Position, 0.08, CYAN, "Neon"))
	b:Accent(b:Rod((c * CF(0.95, -0.6, -0.11)).Position, (c * CF(1.7, 0.05, -0.11)).Position, 0.08, CYAN, "Neon"))
	b:Accent(b:Ball(0.42, c * CF(0.45, 0.35, -0.12), C(255, 222, 90), "Neon"))
	b:Detail(function()
		b:Ellipsoid(V3(0.6, 0.24, 0.1), c * CF(-0.4, 0.42, -0.12), STAR, "SmoothPlastic")
		b:Ellipsoid(V3(0.4, 0.2, 0.1), c * CF(-0.15, 0.48, -0.13), STAR, "SmoothPlastic")
		-- floating chips of the pane
		spike(b, CF(1.15, 2.35, 0.1) * Ang(0.3, 0.4, 0), 0.4, 0, 0.42, 0.36, 0.1, SKY, "SmoothPlastic")
		spike(b, CF(-1.05, 0.45, -0.1) * Ang(-0.2, 0.5, 0), 3.6, 0, 0.36, 0.3, 0.1, SKY, "SmoothPlastic")
	end)
end

R.black_star = function(b, lod)
	local c = CF(0, 1.62, 0)
	-- violet neon star behind (reads as a glowing outline), obsidian star in front
	local reach = { 1.42, 0.92 }
	local width = { 0.82, 0.62 }
	for i = 0, 7 do
		local long = i % 2 == 0
		if long or lod <= 0 then
			local k = long and 1 or 2
			local a = PI / 2 + i * PI / 4
			if lod <= 0 then
				spike(b, c * CF(0, 0, 0.12), a, 0.2, reach[k], width[k], 0.24, VIOLET, "Neon")
			end
			spike(b, c, a, 0.2, reach[k] - 0.16, width[k] - 0.2, 0.46, OBSIDIAN, "Glass")
		end
	end
	if lod > 0 then
		b:Accent(b:CylZ(0.1, 1.5, c * CF(0, 0, 0.2), VIOLET, "Neon"))
	end
	b:Ball(1.0, c, BLACK, "Metal")
	b:Accent(b:CylZ(0.08, 1.24, c * CF(0, 0, 0.1), MAGENTA, "Neon"))
	b:Detail(function()
		b:Accent(b:Ball(0.22, c * CF(0, 0, -0.45), VIOLET, "Neon"))
	end)
end

R.mini_black_hole = function(b, lod)
	local c = CF(0, 1.15, 0)
	local disc = c * Ang(rad(-18), 0, rad(6))
	b:Ball(1.4, c, BLACK, "SmoothPlastic")
	-- lensed photon ring behind the horizon
	b:Accent(b:CylZ(0.06, 1.85, c * CF(0, 0, 0.35), C(255, 200, 140), "Neon"))
	-- accretion disc: hot inside, violet outside
	b:Disc(disc, 3.7, 0.04, VIOLET, "Neon", T(0.4))
	b:Disc(disc, 2.95, 0.07, MAGENTA, "Neon")
	b:Accent(b:Disc(disc, 2.15, 0.1, C(255, 196, 120), "Neon"))
	-- polar jets
	b:Cone(c * CF(0, 0.66, 0), 0.5, 0.26, 0.04, lod <= 0 and 3 or 1, CYAN, "Neon", T(0.3))
	b:Cone(c * CF(0, -0.66, 0) * Ang(PI, 0, 0), 0.5, 0.26, 0.04, lod <= 0 and 3 or 1, CYAN, "Neon", T(0.3))
	b:Detail(function()
		b:Ball(0.2, disc * CF(1.55, 0.08, 0.6), GUNMETAL, "Slate")
		b:Ball(0.14, disc * CF(-1.4, 0.06, -0.9), GUNMETAL, "Slate")
		b:Ball(0.16, disc * CF(-0.5, 0.08, 1.55), GUNMETAL, "Slate")
	end)
end

R.frozen_time = function(b, lod)
	local METAL = C(52, 46, 82)
	local ICE = C(185, 235, 255)
	b:Disc(CF(0, 0.09, 0), 1.5, 0.18, METAL, "Metal")
	b:Disc(CF(0, 2.62, 0), 1.5, 0.18, METAL, "Metal")
	for i = 0, 2 do
		local a = rad(90 + i * 120)
		b:CylY(2.44, 0.1, CF(math.cos(a) * 0.62, 1.35, math.sin(a) * 0.62), METAL, "Metal")
	end
	b:Ellipsoid(V3(1.0, 1.15, 1.0), CF(0, 1.93, 0), ICE, "Glass", T(0.55))
	b:Ellipsoid(V3(1.0, 1.15, 1.0), CF(0, 0.77, 0), ICE, "Glass", T(0.55))
	b:CylY(0.32, 0.2, CF(0, 1.35, 0), ICE, "Glass", T(0.4))
	-- the sand stopped mid-fall, glowing
	b:Accent(b:Ellipsoid(V3(0.78, 0.42, 0.78), CF(0, 0.44, 0), CYAN, "Neon"))
	b:Accent(b:Ellipsoid(V3(0.7, 0.34, 0.7), CF(0, 1.62, 0), CYAN, "Neon"))
	b:Detail(function()
		for i = 0, 3 do
			b:Ball(0.08 - i * 0.008, CF(0, 1.3 - i * 0.17, 0), CYAN, "Neon")
		end
		-- a frozen clock ring around the glass
		local ring = CF(0, 1.35, 0) * Ang(rad(70), rad(20), 0)
		b:Ring(ring, 0.92, 0.06, ICE, "Glass", 12, T(0.2))
		b:Box(V3(0.05, 0.42, 0.05), CF(0, 1.55, -0.52) * Ang(0, 0, rad(-30)), STAR, "Neon")
		b:Gem(0.22, CF(0.5, 0.3, -0.45), ICE, "Glass")
	end)
end

-- RARE -------------------------------------------------------------------------------------------

R.unknown_signal = function(b, lod)
	b:Box(V3(1.5, 0.34, 1.25), CF(0, 0.17, 0.05), OBSIDIAN, "Metal")
	b:Accent(b:Box(V3(0.8, 0.09, 0.04), CF(0, 0.2, -0.58), CYAN, "Neon"))
	b:CylY(1.45, 0.14, CF(0, 1.06, 0.15), GUNMETAL, "Metal")
	-- dish tilted up and towards the front
	local dish = CF(0, 1.85, 0.1) * Ang(rad(-40), 0, 0)
	b:Ellipsoid(V3(1.55, 0.28, 1.55), dish, C(196, 196, 222), "Metal")
	b:Detail(function()
		b:Ellipsoid(V3(1.3, 0.12, 1.3), dish * CF(0, 0.1, 0), DEEP, "SmoothPlastic")
		b:Rod((dish * CF(0.55, 0.1, 0)).Position, (dish * CF(0, 0.7, 0)).Position, 0.05, GUNMETAL, "Metal")
		b:Rod((dish * CF(-0.55, 0.1, 0)).Position, (dish * CF(0, 0.7, 0)).Position, 0.05, GUNMETAL, "Metal")
	end)
	local tip = dish * CF(0, 0.72, 0)
	b:Accent(b:Ball(0.24, tip, MAGENTA, "Neon"))
	-- signal waves leaving the dish
	local waves = CF(tip.Position) * Ang(0, 0, 0)
	local n = lod <= 0 and 4 or 2
	arc(b, waves, 0.42, 0.07, rad(55), rad(125), n, VIOLET, "Neon")
	arc(b, waves, 0.72, 0.07, rad(55), rad(125), n, VIOLET, "Neon", T(0.25))
	b:Detail(function()
		arc(b, waves, 1.02, 0.07, rad(58), rad(122), n, VIOLET, "Neon", T(0.5))
	end)
end

R.alien_skull = function(b, lod)
	local BONE = C(206, 198, 226)
	b:Disc(CF(0, 0.08, 0), 1.25, 0.16, OBSIDIAN, "Glass")
	b:Detail(function()
		b:Disc(CF(0, 0.17, 0), 1.0, 0.03, VIOLET, "Neon")
	end)
	-- big swept-back cranium, narrow face, tiny chin
	b:Ellipsoid(V3(1.55, 1.45, 1.75), CF(0, 1.38, 0.12) * Ang(rad(-25), 0, 0), BONE, "Marble")
	b:Ellipsoid(V3(1.05, 1.05, 0.95), CF(0, 0.85, -0.3) * Ang(rad(15), 0, 0), BONE, "Marble")
	b:Ellipsoid(V3(0.46, 0.44, 0.5), CF(0, 0.42, -0.5), BONE, "Marble")
	for _, s in { -1, 1 } do
		local socket = CF(s * 0.3, 1.08, -0.66) * Ang(0, s * rad(-12), s * rad(-28))
		b:Ellipsoid(V3(0.6, 0.36, 0.3), socket, BLACK, "SmoothPlastic")
		b:Accent(b:Ellipsoid(V3(0.32, 0.16, 0.12), socket * CF(0, 0, -0.12), VIOLET, "Neon"))
	end
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.06, 0.16, 0.06), CF(s * 0.06, 0.78, -0.76), BLACK, "SmoothPlastic")
			b:Ellipsoid(V3(0.32, 0.22, 0.4), CF(s * 0.5, 0.82, -0.42), BONE, "Marble")
		end
		b:Box(V3(0.36, 0.035, 0.08), CF(0, 0.52, -0.72), BLACK, "SmoothPlastic")
	end)
end

R.cosmic_egg = function(b, lod)
	b:Disc(CF(0, 0.14, 0), 1.45, 0.28, OBSIDIAN, "Metal")
	b:Accent(b:Disc(CF(0, 0.3, 0), 1.25, 0.06, VIOLET, "Neon"))
	local egg = CF(0, 1.28, 0)
	b:Ellipsoid(V3(1.5, 2.0, 1.5), egg, C(36, 22, 92), "Glass")
	-- glowing crack across the front
	local crack = {
		V3(-0.5, 0.25), V3(-0.22, 0.05), V3(-0.05, 0.3), V3(0.2, 0.02), V3(0.45, 0.2),
	}
	local function onShell(p)
		-- point on the front of the shell for (x, y) offsets
		local x, y = p.X, p.Y
		local z = -0.75 * math.sqrt(math.max(0, 1 - (x / 0.75) ^ 2 - (y / 1.0) ^ 2)) - 0.01
		return egg:PointToWorldSpace(V3(x, y, z))
	end
	for i = 1, #crack - 1 do
		local part = b:Rod(onShell(crack[i]), onShell(crack[i + 1]), 0.07, MAGENTA, "Neon")
		if i == 2 or i == 3 then
			b:Accent(part)
		end
	end
	b:Detail(function()
		for i, p in { V3(0.3, 0.6), V3(-0.35, 0.65), V3(0.5, -0.35), V3(-0.15, -0.55), V3(0.05, 0.75) } do
			b:Ball(i % 2 == 0 and 0.08 or 0.06, CF(onShell(p)), STAR, "Neon")
		end
		for i = 0, 2 do
			local a = rad(90 + i * 120)
			b:Rod(V3(math.cos(a) * 0.62, 0.28, math.sin(a) * 0.62), V3(math.cos(a) * 0.66, 0.75, math.sin(a) * 0.66), 0.1, GUNMETAL, "Metal")
		end
		local orbit = egg * Ang(rad(12), 0, rad(-18))
		b:Ring(orbit, 1.05, 0.05, CYAN, "Neon", 12, T(0.15))
		b:Ball(0.2, orbit * CF(-1.05, 0, 0), C(180, 180, 200), "Slate")
	end)
end

R.broken_portal = function(b, lod)
	local STONE = C(56, 50, 76)
	local c = CF(0, 1.95, 0)
	b:Box(V3(2.1, 0.3, 0.9), CF(0, 0.15, 0), OBSIDIAN, "Slate")
	b:Wedge(V3(0.7, 0.42, 0.5), CF(0, 0.5, -0.2), STONE, "Slate")
	b:Wedge(V3(0.7, 0.42, 0.5), CF(0, 0.5, 0.2) * Ang(0, PI, 0), STONE, "Slate")
	-- chunky ring of 12 stones, two missing at the top right, one drifting away
	local n = lod <= 0 and 12 or 8
	local radius = 1.45
	local len = 2 * radius * math.tan(PI / n) + 0.05
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 2 * PI
		local gone = (lod <= 0 and (i == 1 or i == 2)) or (lod > 0 and i == 1)
		if not gone then
			b:Box(V3(len, 0.42, 0.52), c * Ang(0, 0, a - PI / 2) * CF(0, radius, 0), STONE, "Slate")
		end
	end
	b:Detail(function()
		local a = 1.5 / 12 * 2 * PI
		b:Box(V3(len, 0.42, 0.52), c * Ang(0, 0, a - PI / 2) * CF(0.25, radius + 0.42, -0.1) * Ang(0.3, 0.2, 0.5), STONE, "Slate")
		b:Box(V3(0.2, 0.18, 0.12), c * Ang(0, 0, 1.2) * CF(0.1, radius + 0.25, -0.05) * Ang(0.5, 0.3, 0.9), STONE, "Slate")
		for i = 0, 3 do
			local ra = rad(200 + i * 45)
			b:Box(V3(0.22, 0.12, 0.04), c * Ang(0, 0, ra - PI / 2) * CF(0, radius, -0.27), CYAN, "Neon")
		end
	end)
	-- the void inside: violet glow, indigo swirl, black heart
	b:Accent(b:CylZ(0.1, 2.75, c, VIOLET, "Neon"))
	b:CylZ(0.12, 2.1, c * CF(0, 0, -0.02), C(70, 30, 150), "Neon", T(0.15))
	b:Accent(b:CylZ(0.14, 1.15, c * CF(0, 0, -0.04), BLACK, "SmoothPlastic"))
	b:Detail(function()
		arc(b, c * CF(0, 0, -0.08), 0.8, 0.06, rad(10), rad(150), 3, MAGENTA, "Neon")
	end)
end

R.dimension_key = function(b, lod)
	local KEYMETAL = C(92, 76, 140)
	local y = 0.7
	local bow = CF(-1.0, y, 0)
	vring(b, bow, 0.56, 0.16, KEYMETAL, "Metal", lod <= 0 and 10 or 6)
	b:Accent(b:CylZ(0.08, 1.06, bow, VIOLET, "Neon"))
	b:CylZ(0.1, 0.56, bow * CF(0, 0, -0.02), BLACK, "SmoothPlastic")
	b:Cyl(1.95, 0.2, CF(0.55, y, 0), KEYMETAL, "Metal")
	-- bit: three teeth, one glowing
	b:Box(V3(0.16, 0.44, 0.14), CF(1.12, y - 0.3, 0), KEYMETAL, "Metal")
	b:Box(V3(0.16, 0.3, 0.14), CF(1.34, y - 0.24, 0), KEYMETAL, "Metal")
	b:Accent(b:Box(V3(0.16, 0.5, 0.14), CF(1.54, y - 0.33, 0), CYAN, "Neon"))
	b:Detail(function()
		b:Cyl(0.08, 0.3, CF(-0.36, y, 0), KEYMETAL, "Metal")
		b:Cyl(0.08, 0.3, CF(0.15, y, 0), KEYMETAL, "Metal")
		b:Ball(0.24, CF(1.56, y, 0), KEYMETAL, "Metal")
		b:Gem(0.14, CF(-1.55, y + 0.62, -0.05), CYAN, "Neon")
		b:Gem(0.1, CF(-0.4, y + 0.55, 0), MAGENTA, "Neon")
	end)
end

-- EPIC -------------------------------------------------------------------------------------------

R.galaxy_in_a_bottle = function(b, lod)
	local BOTTLE = C(180, 210, 255)
	b:CylY(0.1, 1.25, CF(0, 0.05, 0), BOTTLE, "Glass", T(0.35))
	b:CylY(1.45, 1.25, CF(0, 0.82, 0), BOTTLE, "Glass", T(0.65))
	b:Ellipsoid(V3(1.25, 0.72, 1.25), CF(0, 1.55, 0), BOTTLE, "Glass", T(0.6))
	b:CylY(0.5, 0.42, CF(0, 2.05, 0), BOTTLE, "Glass", T(0.55))
	b:CylY(0.36, 0.38, CF(0, 2.44, 0), C(150, 98, 56), "Wood")
	b:Detail(function()
		b:CylY(0.08, 0.5, CF(0, 2.25, 0), VIOLET, "SmoothPlastic")
	end)
	-- the galaxy: haze disc, bright core, two spiral arms
	local g = CF(0, 0.85, 0) * Ang(rad(-38), 0, rad(14))
	b:Accent(b:Disc(g, 1.05, 0.03, C(120, 60, 220), "Neon", T(0.62)))
	b:Accent(b:Ball(0.26, g, C(255, 240, 200), "Neon"))
	b:Detail(function()
		for arm = 0, 1 do
			for i = 1, 6 do
				local t = i / 6
				local a = arm * PI + t * 3.4
				local r = 0.1 + 0.36 * t
				local size = 0.16 - t * 0.08
				-- each blob lies along the spiral (tangent = the direction of growing a)
				b:Ellipsoid(V3(size, size * 0.45, size * 2.2), g * CF(math.cos(a) * r, 0, math.sin(a) * r) * Ang(0, -a, 0), arm == 0 and CYAN or MAGENTA, "Neon")
			end
		end
		b:Ball(0.05, CF(0.32, 1.35, -0.2), STAR, "Neon")
		b:Ball(0.04, CF(-0.3, 0.45, 0.25), STAR, "Neon")
	end)
end

R.eye_of_the_void = function(b, lod)
	local LID = C(40, 26, 84)
	local c = CF(0, 0.95, 0)
	b:Disc(CF(0, 0.07, 0), 0.9, 0.14, OBSIDIAN, "Glass")
	b:CylY(0.32, 0.16, CF(0, 0.3, 0), GUNMETAL, "Metal")
	b:Ball(1.25, c, C(226, 218, 240), "SmoothPlastic")
	b:Accent(b:CylZ(0.1, 0.7, c * CF(0, 0, -0.56), VIOLET, "Neon"))
	b:Ellipsoid(V3(0.15, 0.52, 0.1), c * CF(0, 0, -0.63), BLACK, "SmoothPlastic")
	-- heavy lids leave an almond opening
	b:Ellipsoid(V3(1.5, 0.6, 1.36), c * CF(0, 0.46, 0.06) * Ang(rad(-12), 0, 0), LID, "SmoothPlastic")
	b:Ellipsoid(V3(1.45, 0.52, 1.34), c * CF(0, -0.5, 0.06) * Ang(rad(10), 0, 0), LID, "SmoothPlastic")
	-- tendril corners
	spike(b, c * CF(0, -0.02, 0.02), 0, 0.62, 0.62, 0.42, 0.34, LID, "SmoothPlastic")
	spike(b, c * CF(0, -0.02, 0.02), PI, 0.62, 0.62, 0.42, 0.34, LID, "SmoothPlastic")
	b:Detail(function()
		b:Ball(0.12, c * CF(-0.14, 0.12, -0.64), STAR, "Neon")
		vring(b, c * CF(0, 0, 0.05) * Ang(0, 0, rad(18)), 0.98, 0.05, VIOLET, "Neon", 12, T(0.25))
		b:Accent(b:Gem(0.16, c * CF(1.08, 0.55, 0), MAGENTA, "Neon"))
	end)
end

R.corrupted_crown = function(b, lod)
	local METAL = C(72, 58, 104)
	local base = CF(0, 0.26, 0)
	band(b, base, 1.1, 0.52, 0.14, lod <= 0 and 8 or 6, METAL, "Metal")
	local points = 5
	for i = 0, points - 1 do
		local a = i / points * 2 * PI
		local broken = i == 2 or i == 3
		local h = broken and 0.3 or 0.72
		local spot = base * Ang(0, a, 0) * CF(0, 0.28, -1.08) * Ang(rad(-8), 0, 0)
		if lod <= 0 then
			b:Prism(spot, 0.34, h, broken and 0.16 or 0.46, METAL, "Metal")
		else
			b:Box(V3(0.34, h + 0.3, 0.34), spot * CF(0, (h + 0.3) / 2, 0), METAL, "Metal")
		end
		local front = i == 0 or i == 1 or i == points - 1
		if lod <= 0 or i == 1 or i == points - 1 then
			local gem = b:Ball(0.24, spot * CF(0, 0.2, -0.19), VIOLET, "Neon")
			if front then
				b:Accent(gem)
			end
		end
	end
	-- the corruption itself: a void orb hovering inside the crown
	b:Accent(b:Ball(0.42, base * CF(0, 0.75, 0), MAGENTA, "Neon"))
	b:Detail(function()
		-- a point torn off and floating, void dripping from the band
		local a = 2.5 / points * 2 * PI
		b:Prism(base * Ang(0, a, 0) * CF(0, 1.02, -1.0) * Ang(rad(25), 0, rad(20)), 0.24, 0.2, 0.2, METAL, "Metal")
		for i, a2 in { 0.4, 2.2, 4.4 } do
			b:Ellipsoid(V3(0.12, 0.3 + i * 0.05, 0.12), base * Ang(0, a2, 0) * CF(0, -0.2, -1.1), VIOLET, "Neon")
		end
	end)
end

R.cube_of_nothing = function(b, lod)
	local s = 1.38
	local c = CF(0, s * math.sqrt(3) / 2 + 0.02, 0)
	local onVertex = c * Ang(rad(45), 0, rad(35.264))
	edges(b, onVertex, V3(s, s, s), 0.09, VIOLET, "Neon")
	-- nothing: a pure black cube turned the other way
	b:Accent(b:Box(V3(0.82, 0.82, 0.82), c * Ang(0, rad(45), 0) * Ang(rad(30), 0, 0), BLACK, "SmoothPlastic"))
	b:Detail(function()
		edges(b, c * Ang(0, rad(20), rad(15)), V3(1.05, 1.05, 1.05), 0.05, CYAN, "Neon", T(0.3))
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					if not (x == -1 and y == -1 and z == -1) and not (x == 1 and y == 1 and z == 1) then
						b:Ball(0.16, onVertex * CF(x * s / 2, y * s / 2, z * s / 2), STAR, "Neon")
					end
				end
			end
		end
	end)
end

-- LEGENDARY --------------------------------------------------------------------------------------

R.fragment_of_the_moon = function(b, lod)
	local MOON = C(220, 220, 234)
	local top = stand(b, lod)
	-- a crescent (opening to -X): overlapping ellipsoids along an arc, thick in the middle
	local c = CF(0, top + 1.0, 0) * Ang(0, 0, rad(-16))
	local r = 0.6
	local a0, a1 = rad(-138), rad(138)
	local function at(a)
		return c:PointToWorldSpace(V3(math.cos(a) * r, math.sin(a) * r, 0))
	end
	local function thickness(t)
		return 0.14 + 0.66 * math.sin(t * PI)
	end
	local n = lod <= 0 and 11 or 6
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local p0, p1 = at(a0 + (a1 - a0) * t0), at(a0 + (a1 - a0) * t1)
		local d = thickness((t0 + t1) / 2)
		b:Ellipsoid(V3(d, d, (p1 - p0).Magnitude * 1.75 + d * 0.25), CFrame.lookAt((p0 + p1) / 2, p1), MOON, "Slate")
	end
	b:Rod(V3(0, top - 0.05, 0), at(rad(-80)), 0.12, GUNMETAL, "Metal")
	-- moonlight: a pale halo behind and a star in the crescent's arms
	b:Accent(b:CylZ(0.04, 2.0, c * CF(0.1, 0, 0.5), C(160, 200, 255), "Neon", T(0.78)))
	b:Accent(b:Gem(0.26, c * CF(-0.32, 0.18, 0), C(255, 236, 150), "Neon"))
	b:Detail(function()
		for _, t in { 0.3, 0.5, 0.68 } do
			local a = a0 + (a1 - a0) * t
			local d = thickness(t)
			b:Ellipsoid(V3(0.2, 0.2, 0.05), CF(at(a) + V3(0, 0, -d / 2 + 0.02)), C(160, 160, 182), "Slate")
		end
		b:Ball(0.12, c * CF(0.95, 0.75, 0.1), MOON, "Slate")
		b:Ball(0.08, c * CF(-0.95, -0.55, -0.1), MOON, "Slate")
	end)
end

R.dead_star = function(b, lod)
	local top = stand(b, lod)
	local c = CF(0, top + 0.82, 0)
	b:Ball(1.42, c, C(40, 20, 34), "Basalt")
	-- cooling cracks
	local cracks = {
		{ V3(-0.35, 0.45), V3(-0.05, 0.12) }, { V3(-0.05, 0.12), V3(0.3, 0.3) },
		{ V3(-0.05, 0.12), V3(0.05, -0.35) }, { V3(0.05, -0.35), V3(-0.3, -0.52) },
	}
	local function onSurface(p)
		local z = -math.sqrt(math.max(0, 0.71 ^ 2 - p.X ^ 2 - p.Y ^ 2)) - 0.005
		return c:PointToWorldSpace(V3(p.X, p.Y, z))
	end
	for i, seg in cracks do
		local part = b:Rod(onSurface(seg[1]), onSurface(seg[2]), 0.07, C(255, 60, 90), "Neon")
		if i <= 2 then
			b:Accent(part)
		end
	end
	b:Ball(1.78, c, C(110, 24, 64), "Glass", T(0.72))
	b:Detail(function()
		b:Ring(c * Ang(rad(16), 0, rad(-12)), 1.08, 0.05, GUNMETAL, "Metal", 12)
		b:Ellipsoid(V3(0.2, 0.12, 0.16), c * CF(0.95, 0.55, -0.3) * Ang(0.4, 0.2, 0), OBSIDIAN, "Basalt")
		b:Ellipsoid(V3(0.14, 0.1, 0.12), c * CF(-0.9, -0.3, -0.5) * Ang(0.1, 0.6, 0.3), OBSIDIAN, "Basalt")
	end)
end

R.piece_of_the_sun = function(b, lod)
	local top = stand(b, lod)
	local c = CF(0, top + 0.82, 0)
	b:Accent(b:Ball(1.12, c, C(255, 204, 70), "Neon"))
	b:Ball(1.42, c, C(255, 120, 40), "Neon", T(0.6))
	-- containment gyroscope: two dark rings around the core
	local seg = lod <= 0 and 10 or 8
	vring(b, c * Ang(0, rad(30), rad(20)), 0.86, 0.07, GUNMETAL, "Metal", seg)
	b:Detail(function()
		b:Ring(c * Ang(rad(-20), 0, rad(-15)), 0.86, 0.07, GUNMETAL, "Metal", seg)
		-- prominences looping off the surface
		arc(b, c * CF(0.18, 0.52, -0.2) * Ang(0, rad(-20), 0), 0.22, 0.06, rad(-10), rad(190), 3, C(255, 150, 40), "Neon")
		arc(b, c * CF(-0.48, -0.3, -0.25) * Ang(0, rad(30), rad(120)), 0.18, 0.05, rad(-10), rad(190), 3, C(255, 150, 40), "Neon")
	end)
end

R.lost_planet = function(b, lod)
	local PLANET = C(56, 70, 168)
	local c = CF(0, 0.9, 0)
	local tilt = c * Ang(rad(-20), 0, rad(10))
	b:Ball(1.7, c, PLANET, "SmoothPlastic")
	b:Detail(function()
		b:Ellipsoid(V3(1.74, 0.26, 1.74), c * CF(0, 0.32, 0), C(110, 80, 200), "SmoothPlastic")
		b:Ellipsoid(V3(1.74, 0.18, 1.74), c * CF(0, -0.2, 0), C(70, 150, 200), "SmoothPlastic")
		b:Ellipsoid(V3(1.72, 0.12, 1.72), c * CF(0, 0.05, 0), C(140, 110, 230), "SmoothPlastic")
		b:Ball(1.86, c, CYAN, "Neon", T(0.85))
	end)
	-- ring system
	b:Accent(b:Disc(tilt, 3.7, 0.03, C(206, 186, 255), "Neon", T(0.45)))
	b:Disc(tilt, 3.05, 0.05, C(150, 120, 230), "SmoothPlastic")
	b:Disc(tilt, 2.3, 0.06, C(90, 70, 170), "SmoothPlastic", T(0.2))
	-- a small grey moon
	b:Ball(0.42, CF(1.3, 1.95, 0.55), C(190, 190, 205), "Slate")
	b:Detail(function()
		b:Ellipsoid(V3(0.12, 0.1, 0.04), CF(1.24, 2.0, 0.34), C(150, 150, 165), "Slate")
		b:Accent(b:Ball(0.1, CF(-0.38, 1.25, -0.72), MAGENTA, "Neon"))
	end)
end

R.dog_from_another_timeline = function(b, lod)
	local FUR = C(86, 72, 162)
	local MUZZLE = C(164, 154, 218)
	local EAR = C(48, 38, 100)
	b:Disc(CF(0, 0.04, 0), 2.25, 0.08, OBSIDIAN, "Glass")
	b:Detail(function()
		b:Disc(CF(0, 0.02, 0), 2.38, 0.04, CYAN, "Neon")
	end)
	-- a sitting dog looking at the front
	b:Ellipsoid(V3(1.1, 1.25, 1.35), CF(0, 0.8, 0.28) * Ang(rad(-28), 0, 0), FUR, "SmoothPlastic")
	b:Ellipsoid(V3(0.8, 0.95, 0.72), CF(0, 1.15, -0.2), FUR, "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Detail(function()
			b:Ellipsoid(V3(0.46, 0.62, 0.92), CF(s * 0.42, 0.4, 0.3), FUR, "SmoothPlastic")
		end)
		b:CylY(0.8, 0.21, CF(s * 0.24, 0.44, -0.42), FUR, "SmoothPlastic")
		-- floppy ears
		b:Ellipsoid(V3(0.2, 0.62, 0.38), CF(s * 0.45, 1.8, -0.3) * Ang(rad(6), 0, s * rad(16)), EAR, "SmoothPlastic")
	end
	b:Ball(0.84, CF(0, 1.92, -0.36), FUR, "SmoothPlastic")
	b:Ellipsoid(V3(0.44, 0.38, 0.72), CF(0, 1.76, -0.86) * Ang(rad(6), 0, 0), MUZZLE, "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Accent(b:Ball(0.13, CF(s * 0.19, 2.02, -0.74), CYAN, "Neon"))
	end
	b:Accent(b:CylY(0.1, 0.8, CF(0, 1.5, -0.27), MAGENTA, "Neon"))
	b:Detail(function()
		b:Ball(0.17, CF(0, 1.86, -1.22), BLACK, "SmoothPlastic")
		b:Ellipsoid(V3(0.16, 0.06, 0.2), CF(0, 1.6, -1.06), C(255, 120, 170), "SmoothPlastic")
		for _, s in { -1, 1 } do
			b:Ellipsoid(V3(0.28, 0.16, 0.38), CF(s * 0.24, 0.08, -0.5), MUZZLE, "SmoothPlastic")
		end
		b:Rod(V3(0, 0.45, 0.85), V3(0.12, 1.0, 1.2), 0.15, FUR, "SmoothPlastic")
		-- timeline glitch: the head echoes in two other timelines, pixels fall out of this one
		b:Ball(0.84, CF(-0.21, 1.94, -0.33), CYAN, "Neon", T(0.75))
		b:Ball(0.84, CF(0.23, 1.89, -0.4), MAGENTA, "Neon", T(0.78))
		b:Box(V3(0.16, 0.16, 0.16), CF(0.95, 1.55, -0.2), CYAN, "Neon")
		b:Box(V3(0.12, 0.12, 0.12), CF(-0.9, 1.2, -0.1), MAGENTA, "Neon")
		b:Box(V3(0.1, 0.1, 0.1), CF(0.8, 2.3, -0.3), MAGENTA, "Neon")
	end)
end

R.reality_error = function(b, lod)
	local PANEL = C(24, 18, 42)
	local RED = C(220, 40, 70)
	plinth(b, RED)
	local c = CF(0, 1.9, 0)
	b:Box(V3(3.5, 2.45, 0.2), c, PANEL, "Glass", T(0.12))
	b:Box(V3(3.5, 0.42, 0.26), c * CF(0, 1.42, 0), RED, "SmoothPlastic")
	-- warning sign: yellow triangle with a black "!"
	spike(b, c * CF(0, -0.62, -0.12), PI / 2, 0, 1.25, 1.45, 0.1, C(255, 205, 50), "Neon", { Accent = true })
	b:Box(V3(0.16, 0.5, 0.08), c * CF(0, -0.02, -0.19), BLACK, "SmoothPlastic")
	b:Box(V3(0.16, 0.15, 0.08), c * CF(0, -0.47, -0.19), BLACK, "SmoothPlastic")
	-- glitch slices pulled sideways out of the window
	b:Accent(b:Box(V3(1.3, 0.2, 0.22), c * CF(-1.45, 0.62, -0.02), CYAN, "Neon"))
	b:Box(V3(1.0, 0.22, 0.2), c * CF(1.62, -0.35, 0.02), C(70, 44, 140), "SmoothPlastic")
	b:Detail(function()
		for i = 0, 2 do
			b:Box(V3(0.22, 0.22, 0.06), c * CF(1.1 + i * 0.3, 1.42, -0.15), i == 2 and STAR or C(255, 140, 150), "Neon")
		end
		b:Box(V3(0.8, 0.12, 0.22), c * CF(1.55, 0.95, -0.02), MAGENTA, "Neon")
		b:Box(V3(0.16, 0.16, 0.16), c * CF(-1.95, -0.6, -0.1), MAGENTA, "Neon")
		b:Box(V3(0.12, 0.12, 0.12), c * CF(-1.85, -0.92, -0.1), CYAN, "Neon")
		b:Rod((c * CF(-1.2, -1.0, -0.11)).Position, (c * CF(-0.75, -0.2, -0.11)).Position, 0.04, RED, "Neon")
	end)
end

-- SECRET -----------------------------------------------------------------------------------------

R.null = function(b, lod)
	local FRAME = C(226, 224, 236)
	plinth(b, STAR)
	local c = CF(0, 2.0, 0)
	local w = 3.0
	local t = 0.26
	-- an empty frame, its top right corner missing and drifting off
	b:Box(V3(w - 0.55, t, t), c * CF(-0.275, w / 2 - t / 2, 0), FRAME, "Metal")
	b:Box(V3(w, t, t), c * CF(0, -w / 2 + t / 2, 0), FRAME, "Metal")
	b:Box(V3(t, w, t), c * CF(-w / 2 + t / 2, 0, 0), FRAME, "Metal")
	b:Box(V3(t, w - 0.55, t), c * CF(w / 2 - t / 2, -0.275, 0), FRAME, "Metal")
	b:Box(V3(0.5, t, t), c * CF(w / 2 + 0.1, w / 2 + 0.12, -0.05) * Ang(0.2, 0.3, rad(14)), FRAME, "Metal")
	-- and a hole where the picture was
	b:Accent(b:CylZ(0.04, 1.68, c * CF(0, 0, 0.02), STAR, "Neon"))
	b:CylZ(0.08, 1.5, c, BLACK, "SmoothPlastic")
	b:Detail(function()
		local pixels = { { 0.95, 0.45, 0.18 }, { 1.18, 0.62, 0.12 }, { -0.92, -0.55, 0.14 }, { 0.75, -0.85, 0.1 } }
		for i, px in pixels do
			b:Box(V3(px[3], px[3], px[3]), c * CF(px[1], px[2], -0.04), i % 2 == 0 and STAR or BLACK, i % 2 == 0 and "Neon" or "SmoothPlastic")
		end
	end)
end

R.unknown_question = function(b, lod)
	local Q = C(196, 120, 255)
	plinth(b, VIOLET)
	local function question(cf, scale, segments)
		local thick = 0.3 * scale
		local hook = cf * CF(0, 0.55 * scale, 0)
		local parts = arc(b, hook, 0.6 * scale, thick, rad(205), rad(-62), segments, Q, "Neon")
		local endPoint = hook:PointToWorldSpace(V3(math.cos(rad(-62)) * 0.6 * scale, math.sin(rad(-62)) * 0.6 * scale, 0))
		local neck = cf:PointToWorldSpace(V3(0, -0.35 * scale, 0))
		table.insert(parts, b:Rod(endPoint, neck, thick, Q, "Neon"))
		table.insert(parts, b:CylY(0.3 * scale, thick, cf * CF(0, -0.42 * scale, 0), Q, "Neon"))
		local dot = b:Ball(thick * 1.25, cf * CF(0, -0.95 * scale, 0), Q, "Neon")
		return parts, dot
	end
	local _, dot = question(CF(0, 2.15, 0), 1.25, lod <= 0 and 8 or 5)
	b:Accent(dot)
	-- dark glass halo behind the big one
	b:CylZ(0.06, 2.6, CF(0, 2.15, 0.3), DEEP, "Glass", T(0.35))
	b:Detail(function()
		question(CF(-1.45, 2.95, 0.15) * Ang(0, 0, rad(18)), 0.42, 4)
		question(CF(1.5, 1.45, 0.1) * Ang(0, 0, rad(-15)), 0.36, 4)
	end)
end

R.the_cube = function(b, lod)
	local s = 2.4
	local c = CF(0, s / 2, 0)
	b:Box(V3(s, s, s), c, C(20, 18, 30), "Glass", T(0.45))
	b:Accent(b:Box(V3(0.95, 0.95, 0.95), c, C(200, 180, 255), "Neon"))
	b:Detail(function()
		edges(b, c, V3(s, s, s), 0.05, C(190, 170, 255), "Neon", T(0.35))
	end)
end

-- Every recipe ends on the ground: the parts are moved so the model rests on Y = 0 and is
-- centred on X / Z (the Root stays at the origin = the ground contact point).
local function settle(b)
	local lo, hi
	local parts = {}
	for _, p in b.Model:GetDescendants() do
		if p:IsA("BasePart") and p ~= b.Model.PrimaryPart then
			table.insert(parts, p)
			local cf, size = p.CFrame, p.Size
			local corners = {}
			if p:IsA("Part") and p.Shape == Enum.PartType.Ball then
				local r = math.min(size.X, size.Y, size.Z) / 2
				corners = { cf.Position - Vector3.one * r, cf.Position + Vector3.one * r }
			else
				for _, x in { -0.5, 0.5 } do
					for _, y in { -0.5, 0.5 } do
						for _, z in { -0.5, 0.5 } do
							table.insert(corners, cf:PointToWorldSpace(size * V3(x, y, z)))
						end
					end
				end
			end
			for _, q in corners do
				lo = lo and lo:Min(q) or q
				hi = hi and hi:Max(q) or q
			end
		end
	end
	if not lo then
		return
	end
	local shift = V3(-(lo.X + hi.X) / 2, -lo.Y, -(lo.Z + hi.Z) / 2)
	if shift.Magnitude < 1e-4 then
		return
	end
	for _, p in parts do
		p.CFrame = p.CFrame + shift
	end
end

local Recipes = {}
for id, fn in R do
	Recipes[id] = function(b, lod)
		fn(b, lod)
		settle(b)
	end
end
return Recipes
