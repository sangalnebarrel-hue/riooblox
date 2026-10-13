-- Depth 1 (Backyard) find models: one individual Forge recipe per item (see ItemModels.luau).
-- Every recipe builds around the origin, resting on Y = 0, front towards -Z, at the size of the
-- old voxel model. Lod 1 keeps the silhouette (b:Detail work is skipped); b:Accent marks the
-- signature parts that mutations recolour.
local Forge = require(script.Parent.Parent.Parent:WaitForChild("Forge"))
local P = Forge.Palette

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local R = {}

R.rusty_spoon = function(b, _lod)
	local steel, inner, rust, rustDark = C(172, 166, 156), C(124, 118, 110), C(196, 98, 38), C(122, 60, 30)
	b:Accent(b:Ellipsoid(V(1.3, 0.28, 1.6), CF(0, 0.14, -1.0), steel, "CorrodedMetal"))
	b:Ellipsoid(V(1.04, 0.1, 1.3), CF(0, 0.24, -0.98), inner, "Metal")
	-- the neck rises out of the bowl, the handle slopes back down to the ground
	b:Box(V(0.22, 0.07, 1.0), CF(0, 0.235, 0.12) * ANG(rad(-2), 0, 0), steel, "CorrodedMetal")
	b:Box(V(0.34, 0.07, 1.3), CF(0, 0.17, 1.22) * ANG(rad(5), 0, 0), steel, "CorrodedMetal")
	b:Ellipsoid(V(0.54, 0.08, 0.64), CF(0, 0.09, 1.92), steel, "CorrodedMetal")
	b:Detail(function()
		-- rust: patches on the bowl and the handle, a rusty collar at the neck
		b:Ellipsoid(V(0.62, 0.06, 0.5), CF(0.24, 0.25, -1.25) * ANG(0, rad(30), 0), rust, "CorrodedMetal")
		b:Ellipsoid(V(0.3, 0.06, 0.26), CF(-0.32, 0.25, -0.72), rustDark, "CorrodedMetal")
		b:Ellipsoid(V(0.5, 0.18, 0.36), CF(0.42, 0.1, -0.55) * ANG(0, rad(-30), 0), rust, "CorrodedMetal")
		b:Ellipsoid(V(0.32, 0.12, 0.3), CF(0, 0.235, -0.3), rustDark, "CorrodedMetal")
		b:Ellipsoid(V(0.36, 0.06, 0.62), CF(-0.02, 0.2, 1.05) * ANG(rad(5), rad(-10), 0), rust, "CorrodedMetal")
		b:Ellipsoid(V(0.46, 0.06, 0.4), CF(0.04, 0.125, 1.95), rust, "CorrodedMetal")
		b:Box(V(0.05, 0.02, 0.9), CF(0, 0.21, 1.3) * ANG(rad(5), 0, 0), rustDark, "Metal")
	end)
end

R.bottle_cap = function(b, lod)
	local red, redDark, silver, white, yellow = C(206, 38, 42), C(158, 28, 32), C(196, 198, 204), C(246, 242, 232), C(255, 206, 60)
	-- a crown cap leaning back on its rim, face up towards the viewer
	local base = CF(0, 1.07, 0) * ANG(rad(30), 0, 0)
	b:CylZ(0.44, 1.96, base, red, "Metal")
	-- the crimped skirt: rounded flutes all around the rim
	local flutes = lod <= 0 and 12 or 8
	for k = 0, flutes - 1 do
		local a = 2 * math.pi * k / flutes
		b:CylZ(0.42, 0.26, base * CF(math.cos(a) * 0.96, math.sin(a) * 0.96, 0.01), redDark, "Metal")
	end
	b:Accent(b:CylZ(0.06, 1.74, base * CF(0, 0, -0.23), red, "SmoothPlastic"))
	b:CylZ(0.04, 1.18, base * CF(0, 0, -0.26), white, "SmoothPlastic")
	b:CylZ(0.04, 0.9, base * CF(0, 0, -0.275), yellow, "SmoothPlastic")
	b:CylZ(0.05, 1.86, base * CF(0, 0, 0.225), silver, "Metal")
	b:Detail(function()
		-- logo centre, a scratch and two rust specks on the flutes
		b:CylZ(0.03, 0.52, base * CF(0, 0, -0.29), red, "SmoothPlastic")
		b:Ball(0.16, base * CF(0.08, 0.08, -0.3), white, "SmoothPlastic")
		b:Box(V(0.6, 0.035, 0.02), base * CF(-0.35, -0.55, -0.27) * ANG(0, 0, rad(-25)), silver, "Metal")
		b:Ball(0.16, base * CF(0.98, 0.42, -0.1), C(150, 84, 40), "CorrodedMetal")
		b:Ball(0.14, base * CF(-0.75, -0.78, -0.12), C(150, 84, 40), "CorrodedMetal")
	end)
end

R.chewed_bone = function(b, _lod)
	local bone, worn, dirt, bite = C(238, 226, 196), C(208, 190, 152), C(116, 86, 58), C(168, 148, 112)
	b:Accent(b:Cyl(2.4, 0.46, CF(0, 0.3, 0), bone, "Limestone"))
	b:Ball(0.64, CF(-1.36, 0.32, -0.27), bone, "Limestone")
	b:Ball(0.64, CF(-1.36, 0.32, 0.27), bone, "Limestone")
	b:Ball(0.64, CF(1.36, 0.32, 0.27), bone, "Limestone")
	-- the chewed knob: smaller and flattened where it was bitten off
	b:Ellipsoid(V(0.5, 0.52, 0.6), CF(1.3, 0.26, -0.24) * ANG(0, rad(20), 0), worn, "Limestone")
	b:Detail(function()
		b:Ellipsoid(V(0.12, 0.4, 0.42), CF(1.53, 0.27, -0.32) * ANG(0, rad(20), 0), bite, "Limestone")
		for i, x in { -0.62, -0.22, 0.22, 0.62 } do
			b:Ellipsoid(V(0.1, 0.07, 0.2), CF(x, 0.52, (i % 2 == 0) and 0.06 or -0.06) * ANG(0, rad(18 * i), 0), bite, "Limestone")
		end
		b:Ellipsoid(V(0.5, 0.16, 0.34), CF(-0.9, 0.14, -0.2), dirt, "Ground")
		b:Ellipsoid(V(0.3, 0.2, 0.3), CF(-1.55, 0.14, 0.38), dirt, "Ground")
	end)
end

R.lost_key = function(b, lod)
	local brass, dark, patina, paper, cord = C(198, 158, 76), C(138, 104, 44), C(92, 152, 128), C(236, 226, 196), C(186, 44, 40)
	b:Ring(CF(-1.12, 0.11, 0), 0.5, 0.22, brass, "Metal", lod <= 0 and 10 or 6)
	local collar = b:Cyl(0.2, 0.34, CF(-0.5, 0.17, 0), dark, "Metal")
	b:Cyl(1.62, 0.2, CF(0.33, 0.1, 0), brass, "Metal")
	b:Ball(0.24, CF(1.14, 0.12, 0), brass, "Metal")
	local bit = b:Box(V(0.52, 0.12, 0.5), CF(0.86, 0.06, 0.32), brass, "Metal")
	b:Box(V(0.14, 0.12, 0.22), CF(0.7, 0.06, 0.66), brass, "Metal")
	b:Box(V(0.14, 0.12, 0.16), CF(1.02, 0.06, 0.63), brass, "Metal")
	b:Accent(collar)
	b:Accent(bit)
	b:Detail(function()
		-- ornament inside the bow, green patina and a paper lost-property tag on a red string
		b:Ball(0.24, CF(-1.12, 0.12, 0), dark, "Metal")
		b:Box(V(0.84, 0.08, 0.09), CF(-1.12, 0.08, 0) * ANG(0, rad(45), 0), dark, "Metal")
		b:Box(V(0.84, 0.08, 0.09), CF(-1.12, 0.08, 0) * ANG(0, rad(-45), 0), dark, "Metal")
		b:Ellipsoid(V(0.26, 0.06, 0.2), CF(-1.52, 0.2, 0.22), patina, "Metal")
		b:Ellipsoid(V(0.3, 0.06, 0.16), CF(0.1, 0.19, 0.02), patina, "Metal")
		b:Rod(V(-1.36, 0.12, -0.46), V(-1.5, 0.03, -0.82), 0.05, cord, "Fabric")
		b:Box(V(0.7, 0.03, 0.42), CF(-1.42, 0.015, -1.05) * ANG(0, rad(20), 0), paper, "Cardboard")
		b:Box(V(0.4, 0.02, 0.05), CF(-1.38, 0.035, -1.08) * ANG(0, rad(20), 0), cord, "SmoothPlastic")
	end)
end

R.rubber_duck = function(b, _lod)
	local yellow, shade, orange, ink = C(255, 212, 58), C(242, 186, 40), C(255, 136, 36), C(24, 24, 30)
	b:Accent(b:Ellipsoid(V(1.72, 1.16, 2.0), CF(0, 0.58, 0.12), yellow, "SmoothPlastic"))
	b:Ellipsoid(V(0.84, 0.62, 0.74), CF(0, 0.98, 0.98) * ANG(rad(-35), 0, 0), yellow, "SmoothPlastic")
	b:Accent(b:Ball(1.16, CF(0, 1.42, -0.48), yellow, "SmoothPlastic"))
	b:Ellipsoid(V(0.74, 0.22, 0.64), CF(0, 1.34, -1.1), orange, "SmoothPlastic")
	b:Ellipsoid(V(0.6, 0.16, 0.5), CF(0, 1.23, -1.04), C(226, 104, 30), "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Ball(0.2, CF(s * 0.3, 1.6, -0.96), ink, "SmoothPlastic")
		b:Ellipsoid(V(0.28, 0.56, 1.0), CF(s * 0.84, 0.72, 0.18) * ANG(rad(-12), 0, rad(-8 * s)), shade, "SmoothPlastic")
	end
	b:Detail(function()
		for _, s in { -1, 1 } do
			b:Ball(0.07, CF(s * 0.3 + 0.03, 1.65, -1.05), P.White, "SmoothPlastic")
			b:Ellipsoid(V(0.22, 0.14, 0.06), CF(s * 0.42, 1.36, -0.92) * ANG(0, rad(30 * s), 0), C(255, 150, 140), "SmoothPlastic")
		end
		b:Ellipsoid(V(0.16, 0.34, 0.24), CF(0, 2.04, -0.42) * ANG(rad(-20), 0, 0), yellow, "SmoothPlastic")
	end)
end

R.toy_car = function(b, _lod)
	local red, tire, chrome, glass, lamp, tail = C(222, 44, 44), C(30, 30, 34), C(208, 212, 220), C(130, 196, 236), C(255, 226, 120), C(255, 70, 60)
	b:Accent(b:Box(V(1.62, 0.56, 2.3), CF(0, 0.62, 0.02), red, "SmoothPlastic"))
	b:Box(V(1.36, 0.5, 1.1), CF(0, 1.15, 0.18), glass, "Glass")
	b:Box(V(1.44, 0.14, 1.2), CF(0, 1.47, 0.18), red, "SmoothPlastic")
	b:Wedge(V(1.36, 0.5, 0.36), CF(0, 1.15, -0.55), glass, "Glass")
	b:Wedge(V(1.36, 0.5, 0.3), CF(0, 1.15, 0.88) * ANG(0, math.pi, 0), glass, "Glass")
	for _, x in { -0.82, 0.82 } do
		for _, z in { -0.72, 0.72 } do
			b:Cyl(0.3, 0.64, CF(x, 0.32, z), tire, "Rubber")
		end
	end
	b:Detail(function()
		for _, x in { -0.83, 0.83 } do
			for _, z in { -0.72, 0.72 } do
				b:Cyl(0.32, 0.3, CF(x, 0.32, z), chrome, "Metal")
			end
		end
		b:Box(V(1.66, 0.14, 0.12), CF(0, 0.42, -1.18), chrome, "Metal")
		b:Box(V(1.66, 0.14, 0.12), CF(0, 0.42, 1.22), chrome, "Metal")
		for _, x in { -0.55, 0.55 } do
			b:Ball(0.22, CF(x, 0.72, -1.14), lamp, "SmoothPlastic")
			b:Box(V(0.26, 0.14, 0.06), CF(x, 0.74, 1.18), tail, "SmoothPlastic")
		end
		b:Box(V(0.3, 0.02, 2.31), CF(0, 0.91, 0.02), P.White, "SmoothPlastic")
		b:Box(V(0.3, 0.02, 1.21), CF(0, 1.545, 0.18), P.White, "SmoothPlastic")
		b:Disc(CF(0.815, 0.64, 0.05) * ANG(0, 0, rad(90)), 0.42, 0.02, P.White, "SmoothPlastic")
		b:Box(V(0.6, 0.18, 0.04), CF(0, 0.66, -1.16), C(60, 60, 70), "Metal")
	end)
end

R.tennis_ball = function(b, lod)
	local felt, seam, dirt = C(206, 232, 64), C(246, 246, 236), C(132, 120, 70)
	local r = 1.1
	local centre = CF(0, r + 0.03, 0) * ANG(rad(20), rad(35), rad(10))
	b:Accent(b:Ball(2 * r, centre, felt, "Fabric"))
	-- the classic seam: a curve that winds twice around the ball
	local n = lod <= 0 and 24 or 12
	local a, bb = 0.7, 0.3
	local c = 2 * math.sqrt(a * bb)
	local lift = r + (lod <= 0 and 0.025 or 0.08)
	local function point(t)
		local x = a * math.cos(t) + bb * math.cos(3 * t)
		local y = a * math.sin(t) - bb * math.sin(3 * t)
		local z = c * math.sin(2 * t)
		return centre:PointToWorldSpace(V(x, y, z).Unit * lift)
	end
	-- resample the curve by arc length so every piece of the seam has the same length
	local samples, lengths = {}, { 0 }
	local steps = 240
	for i = 0, steps do
		samples[i + 1] = point(i / steps * 2 * math.pi)
		if i > 0 then
			lengths[i + 1] = lengths[i] + (samples[i + 1] - samples[i]).Magnitude
		end
	end
	local total = lengths[steps + 1]
	local seamPoints = {}
	local j = 1
	for i = 0, n do
		local target = total * i / n
		while j < steps and lengths[j + 1] < target do
			j += 1
		end
		local f = (target - lengths[j]) / math.max(lengths[j + 1] - lengths[j], 1e-6)
		seamPoints[i + 1] = samples[j]:Lerp(samples[j + 1], math.clamp(f, 0, 1))
	end
	for i = 1, n do
		-- each piece overlaps its neighbours a little so the seam reads as one line
		local p, q = seamPoints[i], seamPoints[i + 1]
		local d = (q - p) * 0.1
		b:Rod(p - d, q + d, 0.14, seam, "SmoothPlastic")
	end
	b:Detail(function()
		b:Ellipsoid(V(0.7, 0.5, 0.2), CF(-0.62, 0.58, -0.72) * ANG(rad(-25), rad(-40), 0), dirt, "Ground")
		b:Ellipsoid(V(0.12, 0.2, 0.1), CF(0.3, 1.3, -1.06), C(70, 74, 40), "Fabric")
		b:Ellipsoid(V(0.12, 0.2, 0.1), CF(0.48, 1.24, -1.0), C(70, 74, 40), "Fabric")
	end)
end

R.worm_jar = function(b, lod)
	local glass, soil, worm, wormDark, lid, lidDark, paper = C(196, 228, 238), C(106, 72, 44), C(232, 122, 132), C(196, 92, 104), C(204, 62, 52), C(150, 40, 36), C(240, 230, 200)
	b:CylY(0.9, 1.3, CF(0, 0.47, 0), soil, "Ground")
	b:CylY(2.0, 1.4, CF(0, 1.0, 0), glass, "Glass", { Transparency = 0.55 })
	b:CylY(0.5, 1.43, CF(0, 0.62, 0), paper, "Cardboard")
	b:CylY(0.16, 1.18, CF(0, 2.07, 0), glass, "Glass", { Transparency = 0.45 })
	b:Accent(b:CylY(0.34, 1.36, CF(0, 2.3, 0), lid, "Metal"))
	b:CylY(0.05, 1.2, CF(0, 2.48, 0), lidDark, "Metal")
	-- worms: pink rods with a round head, one climbing up the glass
	local function wormAt(points, head)
		for i = 1, #points - 1 do
			b:Rod(points[i], points[i + 1], 0.14, worm, "SmoothPlastic")
		end
		b:Ball(0.17, CF(head), wormDark, "SmoothPlastic")
	end
	wormAt({ V(-0.35, 0.95, -0.4), V(-0.05, 1.0, -0.55), V(0.25, 1.32, -0.55) }, V(0.27, 1.38, -0.54))
	b:Detail(function()
		wormAt({ V(0.4, 0.94, 0.1), V(0.2, 0.98, 0.42), V(-0.2, 0.96, 0.4) }, V(-0.24, 0.97, 0.38))
		wormAt({ V(-0.52, 0.94, 0.2), V(-0.56, 1.3, -0.12), V(-0.5, 1.6, -0.3) }, V(-0.49, 1.66, -0.32))
		for k = 0, 2 do
			local a = rad(120 * k + 20)
			b:CylY(0.02, 0.12, CF(math.cos(a) * 0.32, 2.51, math.sin(a) * 0.32), C(40, 30, 30), "SmoothPlastic")
		end
		b:Box(V(0.5, 0.14, 0.03), CF(0, 0.64, -0.725), C(190, 40, 40), "SmoothPlastic")
		b:Ellipsoid(V(0.08, 0.3, 0.08), CF(0.35, 1.05, -0.2) * ANG(0, 0, rad(-15)), P.Leaf, "Grass")
	end)
end

R.dog_tag = function(b, lod)
	local steel, steelDark, enamel, chain = C(214, 220, 228), C(150, 158, 170), C(214, 44, 60), C(190, 194, 200)
	-- a pair of rounded military-style tags, the front one carries a red enamel paw
	local function tag(cf, color, corners)
		local w, h, t, d = 1.0, 1.6, 0.1, 0.3
		b:Box(V(w, h - d, t), cf, color, "Metal")
		b:Box(V(w - d, h, t), cf, color, "Metal")
		if corners then
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					b:CylZ(t, d, cf * CF(sx * (w - d) / 2, sy * (h - d) / 2, 0), color, "Metal")
				end
			end
		end
	end
	local front = CF(-0.08, 0.84, -0.06) * ANG(0, 0, rad(-4))
	tag(front, steel, lod <= 0)
	tag(CF(0.14, 0.86, 0.08) * ANG(0, 0, rad(10)), steelDark, false)
	b:Accent(b:Ellipsoid(V(0.44, 0.36, 0.06), front * CF(0, -0.32, -0.06), enamel, "SmoothPlastic"))
	-- ball chain: a loop that comes out of both tag holes (they line up at about (0, 1.5))
	local beads = lod <= 0 and 14 or 6
	local span = rad(324)
	for i = 0, beads - 1 do
		local a = rad(-72) + span * i / (beads - 1)
		b:Ball(lod <= 0 and 0.13 or 0.2, CF(math.cos(a) * 0.36, 2.02 + math.sin(a) * 0.52, 0.01), chain, "Metal")
	end
	b:Detail(function()
		for _, p in { V(-0.16, -0.08, 0), V(0, -0.02, 0), V(0.16, -0.08, 0) } do
			b:Accent(b:Ball(0.15, front * CF(p.X, p.Y, -0.06), enamel, "SmoothPlastic"))
		end
		b:CylZ(0.12, 0.12, front * CF(0, 0.66, 0), C(40, 40, 46), "Metal")
		for i = 0, 2 do
			b:Box(V(0.62 - i * 0.12, 0.05, 0.02), front * CF(-0.06 + i * 0.06, 0.42 - i * 0.14, -0.055), steelDark, "Metal")
		end
	end)
end

R.bent_fork = function(b, _lod)
	local steel, steelDark, wood, woodDark, dirt = C(178, 184, 192), C(118, 124, 132), C(150, 98, 56), C(100, 64, 38), C(108, 80, 50)
	b:Accent(b:Box(V(0.82, 0.08, 0.42), CF(0, 0.08, -0.95), steel, "Metal"))
	-- four tines: one bent sideways, one bent up
	b:Box(V(0.11, 0.07, 0.95), CF(-0.33, 0.08, -1.6), steel, "Metal")
	b:Box(V(0.11, 0.07, 0.95), CF(-0.11, 0.08, -1.6), steel, "Metal")
	b:Box(V(0.11, 0.07, 0.95), CF(0.11, 0.08, -1.12) * ANG(rad(22), 0, 0) * CF(0, 0, -0.47), steel, "Metal")
	b:Box(V(0.11, 0.07, 0.95), CF(0.33, 0.08, -1.12) * ANG(0, rad(-24), 0) * CF(0, 0, -0.47), steel, "Metal")
	b:Box(V(0.22, 0.08, 0.95), CF(0, 0.08, -0.3), steel, "Metal")
	-- the handle is bent away at the neck
	local handle = CF(0, 0.08, 0.15) * ANG(0, rad(22), 0)
	b:Cyl(0.16, 0.26, handle * CF(0, 0.04, 0.12) * ANG(0, rad(90), 0), steelDark, "Metal")
	b:Box(V(0.36, 0.2, 1.4), handle * CF(0, 0.04, 0.9), wood, "Wood")
	b:CylY(0.2, 0.36, handle * CF(0, 0.04, 1.6), woodDark, "Wood")
	b:Detail(function()
		b:CylY(0.03, 0.1, handle * CF(0, 0.155, 0.6), steel, "Metal")
		b:CylY(0.03, 0.1, handle * CF(0, 0.155, 1.2), steel, "Metal")
		b:Ellipsoid(V(0.52, 0.1, 0.4), CF(-0.2, 0.05, -1.85), dirt, "Ground")
		b:Ellipsoid(V(0.2, 0.1, 0.5), CF(0, 0.085, -0.4), steelDark, "CorrodedMetal")
		b:Box(V(0.04, 0.02, 0.8), handle * CF(0.1, 0.145, 0.9), woodDark, "Wood")
	end)
end

R.shiny_marble = function(b, lod)
	local clear, orange, blue, white = C(196, 232, 255), C(255, 104, 20), C(30, 90, 255), C(250, 250, 255)
	local centre = CF(-0.25, 1.0, 0.05)
	b:Ball(2.0, centre, clear, "Glass", { Transparency = 0.5 })
	-- cat's-eye vane: three twisted blades through the centre
	for k = 0, 2 do
		local col = (k == 1) and blue or orange
		b:Accent(b:Ellipsoid(V(0.16, 1.72, 0.86), centre * ANG(0, rad(60 * k), 0) * ANG(rad(18), 0, 0), col, "SmoothPlastic"))
	end
	local function small(d, pos, base, band)
		b:Ball(d, CF(pos), base, "Glass")
		if lod <= 0 then
			b:Ellipsoid(V(d * 1.02, d * 0.34, d * 1.02), CF(pos) * ANG(rad(30), rad(20), rad(-25)), band, "SmoothPlastic")
		end
	end
	small(0.72, V(1.2, 0.36, -0.6), C(220, 40, 60), white)
	small(0.56, V(1.3, 0.28, 0.5), C(50, 190, 90), C(250, 230, 90))
	small(0.44, V(-1.46, 0.22, -0.78), C(255, 200, 40), blue)
	b:Detail(function()
		b:Ball(0.2, centre * CF(-0.42, 0.55, -0.52), white, "SmoothPlastic", { Transparency = 0.1 })
		b:Ball(0.1, centre * CF(-0.2, 0.72, -0.6), white, "SmoothPlastic")
		b:Ball(0.08, centre * CF(0.25, -0.2, -0.45), white, "Glass")
	end)
end

R.garden_gnome = function(b, lod)
	local red, blue, white, skin, boot, grass, gold = C(214, 40, 44), C(52, 100, 196), C(246, 244, 238), C(244, 192, 156), C(96, 62, 38), C(92, 160, 70), C(255, 196, 54)
	b:Disc(CF(0, 0.08, 0), 1.06, 0.16, grass, "SmoothPlastic")
	for _, s in { -1, 1 } do
		b:Ellipsoid(V(0.36, 0.26, 0.52), CF(s * 0.2, 0.26, -0.12), boot, "SmoothPlastic")
		b:Ellipsoid(V(0.26, 0.62, 0.28), CF(s * 0.46, 0.98, -0.12) * ANG(rad(-25), 0, rad(-12 * s)), blue, "SmoothPlastic")
	end
	b:Ellipsoid(V(0.92, 1.08, 0.84), CF(0, 0.86, 0), blue, "SmoothPlastic")
	b:Ball(0.66, CF(0, 1.56, 0), skin, "SmoothPlastic")
	b:Ellipsoid(V(0.66, 0.74, 0.42), CF(0, 1.3, -0.2), white, "SmoothPlastic")
	b:Ball(0.24, CF(0, 1.56, -0.34), C(236, 150, 130), "SmoothPlastic")
	-- the pointed hat (stepped cone), leaning back a little
	local steps = lod <= 0 and 6 or 3
	b:Accent(b:Cone(CF(0, 1.66, 0.02) * ANG(rad(8), 0, 0), 1.2, 0.74, 0.08, steps, red, "SmoothPlastic"))
	b:Detail(function()
		-- belt and buckle, hands, eyes and moustache
		b:Ellipsoid(V(0.95, 0.12, 0.87), CF(0, 0.86, 0), C(40, 32, 30), "SmoothPlastic")
		b:Box(V(0.2, 0.15, 0.05), CF(0, 0.86, -0.44), gold, "Metal")
		for _, s in { -1, 1 } do
			b:Ball(0.22, CF(s * 0.34, 0.74, -0.38), skin, "SmoothPlastic")
		end
		for _, s in { -1, 1 } do
			b:Ball(0.08, CF(s * 0.13, 1.66, -0.29), P.Ink, "SmoothPlastic")
			b:Ellipsoid(V(0.24, 0.12, 0.12), CF(s * 0.12, 1.47, -0.36) * ANG(0, 0, rad(-20 * s)), white, "SmoothPlastic")
		end
		b:CylY(0.16, 0.08, CF(-0.38, 0.24, -0.27), white, "SmoothPlastic")
		b:Ellipsoid(V(0.26, 0.15, 0.26), CF(-0.38, 0.33, -0.27), red, "SmoothPlastic")
		-- a little shovel in the hands
		b:Rod(V(0.34, 0.76, -0.42), V(0.4, 0.38, -0.36), 0.06, C(150, 98, 56), "Wood")
		b:Box(V(0.18, 0.22, 0.04), CF(0.41, 0.27, -0.35) * ANG(rad(-5), 0, rad(-8)), C(150, 156, 166), "Metal")
	end)
end

R.funny_sock = function(b, _lod)
	local lime, magenta, orange, white = C(150, 220, 60), C(232, 60, 160), C(255, 150, 40), C(246, 246, 240)
	b:CylY(1.8, 0.82, CF(0, 1.25, 0.45), lime, "Fabric")
	b:CylY(0.3, 0.9, CF(0, 2.1, 0.45), white, "Fabric")
	b:Ellipsoid(V(0.82, 0.78, 1.7), CF(0, 0.39, -0.15), lime, "Fabric")
	b:Ellipsoid(V(0.84, 0.74, 0.62), CF(0, 0.42, 0.62), orange, "Fabric")
	b:Ellipsoid(V(0.84, 0.66, 0.6), CF(0, 0.35, -0.76), orange, "Fabric")
	for _, y in { 0.95, 1.3, 1.65 } do
		b:Accent(b:CylY(0.16, 0.85, CF(0, y, 0.45), magenta, "Fabric"))
	end
	b:Detail(function()
		-- googly eyes on the foot: a sock puppet
		for _, s in { -1, 1 } do
			b:Ball(0.34, CF(s * 0.2, 0.72, -0.42), white, "SmoothPlastic")
			b:Ball(0.16, CF(s * 0.2 + 0.03, 0.7, -0.58), P.Ink, "SmoothPlastic")
		end
		for _, p in { V(-0.36, 0.5, -0.1), V(0.37, 0.42, 0.15), V(0.36, 0.55, -0.35) } do
			b:Ellipsoid(V(0.06, 0.16, 0.16), CF(p), magenta, "Fabric")
		end
		b:Ellipsoid(V(0.2, 0.16, 0.06), CF(0, 0.4, -1.06) * ANG(rad(-20), 0, 0), C(255, 120, 120), "Fabric")
		b:CylY(0.02, 0.72, CF(0, 2.25, 0.45), C(60, 92, 30), "Fabric")
	end)
end

R.broken_clock = function(b, _lod)
	local teal, brass, cream, ink, glass = C(70, 172, 162), C(222, 176, 82), C(246, 238, 220), C(28, 28, 34), C(214, 236, 246)
	local face = CF(0, 1.22, 0.05)
	b:CylZ(0.5, 1.9, face, teal, "Metal")
	b:Accent(b:CylZ(0.12, 2.0, face * CF(0, 0, -0.24), brass, "Metal"))
	b:CylZ(0.06, 1.7, face * CF(0, 0, -0.3), cream, "SmoothPlastic")
	b:CylZ(0.04, 1.74, face * CF(0, 0, -0.345), glass, "Glass", { Transparency = 0.6 })
	b:CylZ(0.08, 0.16, face * CF(0, 0, -0.36), ink, "Metal")
	b:Box(V(0.09, 0.46, 0.03), face * CF(0, 0, -0.34) * ANG(0, 0, rad(60)) * CF(0, 0.2, 0), ink, "Metal")
	-- the minute hand has come loose and hangs down
	b:Box(V(0.06, 0.7, 0.03), face * CF(0, 0, -0.35) * ANG(0, 0, rad(168)) * CF(0, 0.32, 0), ink, "Metal")
	for _, s in { -1, 1 } do
		b:Accent(b:Ellipsoid(V(0.76, 0.56, 0.76), CF(s * 0.6, 2.18, 0.05) * ANG(0, 0, rad(-30 * s)), brass, "Metal"))
		b:Ball(0.32, CF(s * 0.56, 0.17, 0.05), brass, "Metal")
	end
	b:Detail(function()
		for k = 0, 3 do
			b:Box(V(0.07, 0.18, 0.03), face * CF(0, 0, -0.335) * ANG(0, 0, rad(90 * k)) * CF(0, 0.7, 0), ink, "SmoothPlastic")
		end
		-- cracks in the glass
		b:Box(V(0.025, 0.8, 0.02), face * CF(0.3, 0.25, -0.37) * ANG(0, 0, rad(25)), P.White, "Glass")
		b:Box(V(0.025, 0.5, 0.02), face * CF(0.45, -0.05, -0.37) * ANG(0, 0, rad(-50)), P.White, "Glass")
		b:Box(V(0.025, 0.45, 0.02), face * CF(0.15, 0.55, -0.37) * ANG(0, 0, rad(70)), P.White, "Glass")
		-- bell striker and knobs
		b:Box(V(0.08, 0.42, 0.08), CF(0, 2.28, 0.05), brass, "Metal")
		b:Ball(0.16, CF(0, 2.5, 0.05), brass, "Metal")
		-- a spring popping out of the side and a lost cog on the ground
		b:Rod(V(0.9, 1.4, 0.1), V(1.12, 1.55, 0.05), 0.05, P.Silver, "Metal")
		b:Rod(V(1.12, 1.55, 0.05), V(1.0, 1.7, 0.1), 0.05, P.Silver, "Metal")
		b:Disc(CF(0.95, 0.04, -0.5), 0.46, 0.08, brass, "Metal")
		for k = 0, 2 do
			b:Box(V(0.62, 0.07, 0.09), CF(0.95, 0.035, -0.5) * ANG(0, rad(60 * k + 10), 0), C(182, 140, 60), "Metal")
		end
	end)
end

R.old_wallet = function(b, _lod)
	local leather, leatherDark, stitch, bill, billDark, brass, card = C(158, 94, 52), C(112, 64, 36), C(232, 196, 132), C(150, 200, 124), C(104, 160, 92), C(232, 186, 84), C(255, 200, 60)
	b:Box(V(1.7, 1.25, 0.16), CF(0.02, 0.625, -0.17), leather, "Leather")
	b:Box(V(1.7, 1.25, 0.16), CF(0.02, 0.625, 0.17), leatherDark, "Leather")
	b:CylY(1.25, 0.5, CF(-0.83, 0.625, 0), leather, "Leather")
	b:Box(V(1.6, 1.15, 0.2), CF(0.08, 0.625, 0), C(52, 30, 18), "Leather")
	-- bank notes and a gold card sticking out of the top
	b:Box(V(1.3, 0.5, 0.04), CF(0.1, 1.25, -0.04) * ANG(0, 0, rad(4)), bill, "SmoothPlastic")
	b:Box(V(1.25, 0.45, 0.04), CF(0.0, 1.22, 0.05) * ANG(0, 0, rad(-6)), billDark, "SmoothPlastic")
	b:Accent(b:Box(V(0.85, 0.5, 0.03), CF(0.42, 1.3, 0.1) * ANG(0, 0, rad(-12)), card, "Foil"))
	b:Box(V(0.5, 0.4, 0.05), CF(0.62, 0.7, -0.27), leatherDark, "Leather")
	b:Accent(b:CylZ(0.06, 0.22, CF(0.7, 0.7, -0.31), brass, "Metal"))
	b:Detail(function()
		local z = -0.255
		b:Box(V(1.44, 0.03, 0.02), CF(0.04, 1.16, z), stitch, "Fabric")
		b:Box(V(1.44, 0.03, 0.02), CF(0.04, 0.09, z), stitch, "Fabric")
		b:Box(V(0.03, 1.07, 0.02), CF(0.77, 0.625, z), stitch, "Fabric")
		b:Box(V(0.03, 1.07, 0.02), CF(-0.69, 0.625, z), stitch, "Fabric")
		b:CylZ(0.05, 0.36, CF(-0.25, 1.24, 0.02) * ANG(0, 0, 0), C(255, 206, 80), "Foil")
		b:Ellipsoid(V(0.42, 0.26, 0.04), CF(-0.3, 0.42, -0.255), C(150, 96, 60), "Leather")
		b:Box(V(0.6, 0.06, 0.035), CF(0.44, 1.33, 0.085) * ANG(0, 0, rad(-12)), C(60, 60, 70), "SmoothPlastic")
	end)
end

R.cracked_phone = function(b, _lod)
	local case, screen, crack, cam = C(250, 112, 72), C(18, 20, 28), C(226, 238, 250), C(34, 34, 40)
	local W, H, T, d = 1.3, 2.6, 0.24, 0.36
	local body = CF(0, H / 2, 0)
	b:Accent(b:Box(V(W, H - d, T), body, case, "SmoothPlastic"))
	b:Accent(b:Box(V(W - d, H, T), body, case, "SmoothPlastic"))
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			b:CylZ(T, d, body * CF(sx * (W - d) / 2, sy * (H - d) / 2, 0), case, "SmoothPlastic")
		end
	end
	b:Box(V(W - 0.16, H - 0.18, 0.03), body * CF(0, 0, -T / 2 - 0.005), screen, "Glass")
	b:Box(V(0.36, 0.08, 0.02), body * CF(0, H / 2 - 0.2, -T / 2 - 0.02), cam, "SmoothPlastic")
	b:Box(V(0.52, 0.52, 0.06), body * CF(-0.3, H / 2 - 0.42, T / 2 + 0.02), cam, "Metal")
	b:Box(V(0.04, 0.42, 0.1), body * CF(W / 2 + 0.01, 0.55, 0), C(200, 90, 60), "SmoothPlastic")
	b:Detail(function()
		-- spider-web cracks around the impact point
		local hx, hy = 0.18, 0.42
		local hit = body * CF(hx, hy, -T / 2 - 0.025)
		local sw, sh = (W - 0.2) / 2, (H - 0.22) / 2
		for i, reach in { 0.95, 0.7, 0.9, 0.55, 0.85, 0.75, 0.6 } do
			local a = rad(i * 52 + 14)
			-- a crack runs from the impact point towards the screen edge (local +Y turned by a)
			local dx, dy = -math.sin(a), math.cos(a)
			local tx = dx ~= 0 and ((dx > 0 and sw or -sw) - hx) / dx or math.huge
			local ty = dy ~= 0 and ((dy > 0 and sh or -sh) - hy) / dy or math.huge
			local len = math.min(tx, ty) * reach
			b:Box(V(0.035, len, 0.012), hit * ANG(0, 0, a) * CF(0, len / 2, 0), crack, "Glass")
		end
		b:Ball(0.12, hit, crack, "Glass")
		b:Box(V(0.3, 0.035, 0.012), body * CF(0, -H / 2 + 0.17, -T / 2 - 0.02), C(90, 90, 100), "SmoothPlastic")
		for _, y in { -0.08, 0.1 } do
			b:CylZ(0.04, 0.18, body * CF(-0.3, H / 2 - 0.42 + y, T / 2 + 0.06), C(70, 96, 140), "Glass")
		end
	end)
end

R.buried_lunchbox = function(b, _lod)
	local blue, blueDark, chrome, sun, stripe, dirt, rust = C(62, 122, 204), C(40, 84, 152), C(208, 212, 220), C(255, 206, 60), C(222, 62, 62), C(125, 92, 60), C(160, 92, 46)
	b:Box(V(1.9, 0.98, 1.0), CF(0, 0.49, 0), blue, "Metal")
	b:Box(V(1.94, 0.26, 1.04), CF(0, 1.12, 0), blueDark, "Metal")
	b:Box(V(1.96, 0.06, 1.06), CF(0, 0.98, 0), chrome, "Metal")
	for _, x in { -0.45, 0.45 } do
		b:Box(V(0.1, 0.24, 0.1), CF(x, 1.35, 0), chrome, "Metal")
	end
	b:Accent(b:Cyl(1.04, 0.18, CF(0, 1.5, 0), C(40, 40, 46), "SmoothPlastic"))
	b:Accent(b:Box(V(0.26, 0.3, 0.06), CF(0, 0.96, -0.53), chrome, "Metal"))
	b:CylZ(0.03, 0.5, CF(-0.45, 0.5, -0.505), sun, "SmoothPlastic")
	b:Box(V(0.72, 0.16, 0.02), CF(0.38, 0.42, -0.505) * ANG(0, 0, rad(18)), stripe, "SmoothPlastic")
	b:Detail(function()
		-- clumps of earth from being buried, rust and a dent
		b:Ellipsoid(V(1.3, 0.56, 0.9), CF(-0.7, 0.28, 0.42), dirt, "Ground")
		b:Ellipsoid(V(0.72, 0.4, 0.06), CF(-0.5, 0.24, -0.505), dirt, "Ground")
		b:Ellipsoid(V(0.5, 0.14, 0.4), CF(0.35, 1.26, 0.22), dirt, "Ground")
		b:Ellipsoid(V(0.3, 0.2, 0.04), CF(0.7, 0.75, -0.505), rust, "CorrodedMetal")
		b:Ellipsoid(V(0.18, 0.14, 0.04), CF(-0.8, 0.25, -0.505), rust, "CorrodedMetal")
		b:Box(V(0.16, 0.16, 0.02), CF(0.62, 0.62, -0.51) * ANG(0, 0, rad(45)), P.White, "SmoothPlastic")
		for _, x in { -0.6, 0.6 } do
			b:Cyl(0.24, 0.1, CF(x, 1.0, 0.53), chrome, "Metal")
		end
	end)
end

R.tiny_treasure_chest = function(b, _lod)
	local wood, gold, goldDark, glow = C(142, 86, 46), C(255, 196, 54), C(200, 136, 30), C(255, 230, 130)
	b:Box(V(1.8, 0.85, 1.2), CF(0, 0.425, 0), wood, "WoodPlanks")
	b:Cyl(1.8, 1.2, CF(0, 0.85, 0), wood, "WoodPlanks")
	b:Box(V(1.84, 0.08, 1.24), CF(0, 0.85, 0), goldDark, "Metal")
	for _, x in { -0.58, 0.58 } do
		b:Box(V(0.14, 0.86, 1.24), CF(x, 0.43, 0), gold, "Metal")
		b:Cyl(0.14, 1.26, CF(x, 0.85, 0), gold, "Metal")
	end
	-- warm light leaking out of the seam, the lock plate and an emerald on the lid
	b:Box(V(1.3, 0.035, 0.02), CF(0, 0.85, -0.63), glow, "Neon")
	b:Accent(b:Box(V(0.36, 0.44, 0.07), CF(0, 0.8, -0.62), gold, "Foil"))
	b:Accent(b:Gem(0.3, CF(0, 1.5, -0.05), P.Emerald, "Glass"))
	b:Detail(function()
		b:Ball(0.1, CF(0, 0.84, -0.66), P.Ink, "SmoothPlastic")
		b:Box(V(0.05, 0.14, 0.02), CF(0, 0.75, -0.66), P.Ink, "SmoothPlastic")
		for _, x in { -0.86, 0.86 } do
			for _, z in { -0.56, 0.56 } do
				b:Box(V(0.14, 0.16, 0.14), CF(x, 0.08, z), goldDark, "Metal")
			end
			b:Disc(CF(x * 1.05, 0.55, 0) * ANG(0, 0, rad(90)), 0.32, 0.05, goldDark, "Metal")
		end
		-- spilled coins and a ruby in front
		for i, p in { V(-0.55, 0.03, -0.95), V(-0.2, 0.03, -1.02), V(0.42, 0.03, -0.92), V(0.72, 0.09, -0.75) } do
			b:Disc(CF(p) * ANG(rad(i == 4 and 30 or 0), rad(i * 40), 0), 0.3, 0.05, C(255, 214, 80), "Foil")
		end
		b:Gem(0.2, CF(0.15, 0.17, -0.98), P.Ruby, "Glass")
	end)
end

R.golden_bone = function(b, _lod)
	local gold, goldDeep, velvet, diamond, shine = C(255, 198, 56), C(212, 148, 30), C(150, 24, 40), C(236, 246, 255), C(255, 250, 214)
	-- resting on a small velvet cushion
	b:Ellipsoid(V(3.3, 0.34, 1.34), CF(0, 0.17, 0), velvet, "Fabric")
	local y = 0.62
	b:Accent(b:Cyl(2.3, 0.5, CF(0, y, 0), gold, "Metal"))
	for _, x in { -1.3, 1.3 } do
		for _, z in { -0.28, 0.28 } do
			b:Ball(0.68, CF(x, y, z), gold, "Foil")
		end
		b:Cyl(0.12, 0.6, CF(x * 0.66, y, 0), goldDeep, "Metal")
	end
	b:Accent(b:Gem(0.32, CF(0, y + 0.3, -0.05), P.Ruby, "Glass"))
	b:Detail(function()
		b:Disc(CF(0, y + 0.24, -0.05), 0.36, 0.06, goldDeep, "Metal")
		for _, x in { -1.3, 1.3 } do
			for _, z in { -0.28, 0.28 } do
				b:Ball(0.14, CF(x + (x > 0 and -0.1 or 0.1), y + 0.31, z), diamond, "Glass")
			end
		end
		for _, x in { -1.62, 1.62 } do
			b:Ball(0.16, CF(x, 0.2, -0.6), goldDeep, "Metal")
			b:Ball(0.16, CF(x, 0.2, 0.6), goldDeep, "Metal")
		end
		b:Ball(0.1, CF(-1.405, y + 0.245, -0.49), shine, "Neon")
		b:Ball(0.1, CF(1.405, y + 0.245, -0.49), shine, "Neon")
	end)
end

R.mini_ufo_toy = function(b, lod)
	local silver, silverDark, dome, alien, cyan, pink, brass = C(204, 210, 220), C(126, 134, 148), C(150, 232, 255), C(110, 222, 92), C(80, 255, 220), C(255, 90, 220), C(222, 176, 82)
	for k = 0, 2 do
		local a = rad(120 * k + 90)
		b:Rod(V(math.cos(a) * 0.6, 0.62, math.sin(a) * 0.6), V(math.cos(a) * 0.95, 0.06, math.sin(a) * 0.95), 0.1, silverDark, "Metal")
	end
	b:Ellipsoid(V(2.8, 0.56, 2.8), CF(0, 0.86, 0), silver, "Metal")
	b:Accent(b:CylY(0.12, 2.86, CF(0, 0.86, 0), silverDark, "Metal"))
	b:Accent(b:Ellipsoid(V(1.9, 0.44, 1.9), CF(0, 1.06, 0), C(226, 230, 238), "Metal"))
	b:Ellipsoid(V(1.16, 1.0, 1.16), CF(0, 1.2, 0), dome, "Glass", { Transparency = 0.4 })
	b:Ball(0.46, CF(0, 1.42, 0), alien, "SmoothPlastic")
	b:Disc(CF(0, 0.59, 0), 0.62, 0.05, cyan, "Neon")
	local lights = lod <= 0 and 8 or 4
	for k = 0, lights - 1 do
		local a = 2 * math.pi * k / lights + rad(22.5)
		b:Ball(0.17, CF(math.cos(a) * 1.42, 0.86, math.sin(a) * 1.42), (k % 2 == 0) and cyan or pink, "Neon")
	end
	b:Detail(function()
		for k = 0, 2 do
			local a = rad(120 * k + 90)
			b:Disc(CF(math.cos(a) * 0.96, 0.04, math.sin(a) * 0.96), 0.26, 0.08, silverDark, "Metal")
		end
		for _, s in { -1, 1 } do
			b:Ellipsoid(V(0.12, 0.17, 0.06), CF(s * 0.1, 1.45, -0.2), P.Ink, "SmoothPlastic")
		end
		b:Rod(V(0, 1.62, 0), V(0, 1.86, 0), 0.04, silverDark, "Metal")
		b:Ball(0.13, CF(0, 1.9, 0), pink, "Neon")
		-- wind-up key at the back: it is a toy
		b:CylZ(0.36, 0.1, CF(0, 0.9, 1.52), brass, "Metal")
		b:Ellipsoid(V(0.5, 0.3, 0.06), CF(-0.22, 0.9, 1.72), brass, "Metal")
		b:Ellipsoid(V(0.5, 0.3, 0.06), CF(0.22, 0.9, 1.72), brass, "Metal")
	end)
end

return R
