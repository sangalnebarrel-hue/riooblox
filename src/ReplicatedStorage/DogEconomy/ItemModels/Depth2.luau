-- Depth 2 (Caverns) find models: one individual Forge recipe per item (see ItemModels.luau).
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
local SQ3 = math.sqrt(3)

local R = {}

-- A cube turned onto a vertex (body diagonal along +Y); its six middle corners line up with the
-- corners of the hexagonal columns below, so the cube's top three faces make a crystal point.
local TIP_ROT = ANG(0, rad(-15), 0) * CFrame.fromAxisAngle(V(1, 1, 1):Cross(V(0, 1, 0)).Unit, math.acos(1 / SQ3))
-- The same point aimed along -Z (druzy points facing out of a cavity).
local POINT_OUT = ANG(rad(-90), 0, 0) * TIP_ROT

-- Hexagonal crystal standing on cf (base centre) and growing along cf.UpVector: three boxes make
-- the column, a vertex-up cube the three-facet point (a second cube turned 60 degrees adds the
-- other three facets). Returns the parts.
local function crystal(b, cf, radius, height, color, tipColor, mat, props, sixFacets)
	local parts = {}
	for k = 0, 2 do
		table.insert(parts, b:Box(V(radius, height, SQ3 * radius), cf * CF(0, height / 2, 0) * ANG(0, rad(60 * k), 0), color, mat, props))
	end
	local s = radius / 0.8165
	local top = cf * CF(0, height - 0.2887 * s, 0)
	table.insert(parts, b:Box(V(s, s, s), top * TIP_ROT, tipColor, mat, props))
	if sixFacets then
		table.insert(parts, b:Box(V(s, s, s), top * ANG(0, rad(60), 0) * TIP_ROT, tipColor, mat, props))
	end
	return parts
end

-- A small crystal point (one cube on a vertex) of size s at cf, aimed along cf.UpVector.
local function point(b, cf, s, color, mat, props)
	return b:Box(V(s, s, s), cf * TIP_ROT, color, mat or "Glass", props)
end

-- Half the world-space height of a part (exact for blocks, balls, sphere meshes and cylinders).
local function halfHeight(part)
	local cf, h = part.CFrame, part.Size / 2
	local rx, uy, lz = cf.RightVector.Y, cf.UpVector.Y, cf.LookVector.Y
	if part:FindFirstChildOfClass("SpecialMesh") then
		return math.sqrt((rx * h.X) ^ 2 + (uy * h.Y) ^ 2 + (lz * h.Z) ^ 2)
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		return math.min(h.X, h.Y, h.Z)
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		return math.abs(rx) * h.X + math.min(h.Y, h.Z) * math.sqrt(uy * uy + lz * lz)
	end
	return math.abs(rx) * h.X + math.abs(uy) * h.Y + math.abs(lz) * h.Z
end

-- The parts built so far (without the invisible Root).
local function partsOf(b)
	local root = b.Model.PrimaryPart
	local parts = {}
	for _, d in b.Model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			table.insert(parts, d)
		end
	end
	return parts
end

-- Irregular rocks are easier to pose by eye: this moves the finished model so the lowest point
-- of `measured` (the silhouette parts, the same at every lod) rests exactly on Y = 0.
local function settle(b, measured)
	local lowest = math.huge
	for _, d in measured do
		lowest = math.min(lowest, d.CFrame.Position.Y - halfHeight(d))
	end
	if lowest == math.huge then
		return
	end
	local shift = V(0, -lowest, 0)
	for _, d in partsOf(b) do
		d.CFrame = d.CFrame + shift
	end
end

R.quartz_crystal = function(b, lod)
	local clear, milky, tip, rock, rockDark, stain = C(242, 246, 255), C(222, 228, 242), C(252, 253, 255), C(128, 124, 120), C(92, 88, 86), C(190, 124, 66)
	local glass = { Transparency = 0.15 }
	b:Ellipsoid(V(2.3, 0.74, 1.9), CF(0, 0.37, 0.05), rock, "Slate")
	b:Accent(crystal(b, CF(-0.05, 0.4, 0.05) * ANG(rad(-6), 0, rad(6)), 0.44, 2.25, clear, tip, "Glass", glass, lod <= 0))
	crystal(b, CF(0.55, 0.35, -0.12) * ANG(rad(-8), rad(10), rad(-30)), 0.3, 1.5, milky, tip, "Glass", glass)
	crystal(b, CF(-0.6, 0.35, -0.22) * ANG(rad(-14), rad(-15), rad(32)), 0.27, 1.15, clear, tip, "Glass", glass)
	b:Detail(function()
		b:Ellipsoid(V(1.1, 0.5, 0.9), CF(0.75, 0.25, 0.48) * ANG(0, rad(30), 0), rockDark, "Slate")
		crystal(b, CF(0.15, 0.4, 0.5) * ANG(rad(28), rad(20), rad(-8)), 0.22, 0.95, milky, tip, "Glass", glass)
		crystal(b, CF(-0.55, 0.3, 0.45) * ANG(rad(30), 0, rad(25)), 0.17, 0.6, clear, tip, "Glass", glass)
		b:Ellipsoid(V(0.46, 0.08, 0.34), CF(-0.62, 0.66, -0.4) * ANG(rad(-25), 0, rad(10)), stain, "Sandstone")
		b:Ellipsoid(V(0.3, 0.08, 0.26), CF(0.85, 0.58, -0.35) * ANG(rad(-25), 0, rad(-20)), stain, "Sandstone")
	end)
end

R.large_coal = function(b, _lod)
	local coal, coalMid, coalDark, glint = C(52, 52, 58), C(38, 38, 44), C(26, 26, 30), C(150, 162, 186)
	-- faceted lumps: each is a cube on its corner crossed with a second cube (many flat facets)
	local function lump(cf, s, colorA, colorB)
		local a = b:Box(V(s, s * 0.86, s), cf * ANG(rad(45), 0, rad(35.26)), colorA, "Slate")
		b:Box(V(s * 0.84, s * 0.8, s * 0.84), cf * ANG(0, rad(45), 0) * ANG(rad(45), 0, 0), colorB, "Slate")
		return a
	end
	b:Accent(lump(CF(0, 0.9, 0) * ANG(0, rad(20), rad(8)), 1.35, coal, coalMid))
	lump(CF(-0.78, 0.62, 0.3) * ANG(rad(12), rad(-30), 0), 0.95, coalMid, coalDark)
	lump(CF(0.72, 0.55, -0.32) * ANG(rad(-10), rad(50), rad(15)), 0.85, coalDark, coal)
	-- a split-off shard leaning against the front
	b:Wedge(V(0.8, 0.5, 0.62), CF(-0.1, 0.25, -0.8) * ANG(0, rad(200), 0), coalMid, "Slate")
	local core = partsOf(b)
	b:Detail(function()
		lump(CF(0.15, 1.45, 0.25) * ANG(rad(20), rad(10), 0), 0.6, coalMid, coal)
		-- anthracite glints and loose crumbs
		for _, p in { V(-0.35, 1.25, -0.62), V(0.3, 0.95, -0.82), V(-0.95, 0.75, -0.2), V(0.95, 0.85, -0.1), V(0.05, 1.62, -0.1) } do
			b:Box(V(0.12, 0.12, 0.12), CF(p) * ANG(rad(45), rad(30), rad(20)), glint, "Glass")
		end
		b:Box(V(0.24, 0.2, 0.22), CF(1.2, 0.12, 0.45) * ANG(rad(30), rad(20), rad(40)), coal, "Slate")
		b:Box(V(0.2, 0.17, 0.19), CF(-1.15, 0.1, -0.6) * ANG(rad(10), rad(50), rad(20)), coalMid, "Slate")
	end)
	settle(b, core)
end

R.amethyst = function(b, lod)
	local shell, shellDark, rim, cavity, purple, lilac = C(134, 118, 104), C(96, 86, 78), C(236, 230, 240), C(74, 30, 116), C(150, 70, 222), C(204, 154, 252)
	-- a cathedral geode: a tall rock shell split open at the front, lined with amethyst points
	b:Ellipsoid(V(2.4, 0.5, 1.8), CF(0, 0.25, 0.1), shellDark, "Slate")
	b:Ellipsoid(V(2.5, 3.1, 1.7), CF(0, 1.6, 0.2), shell, "Slate")
	b:Ellipsoid(V(2.06, 2.66, 0.9), CF(0, 1.62, -0.3), rim, "Marble")
	b:Accent(b:Ellipsoid(V(1.8, 2.36, 0.9), CF(0, 1.62, -0.36), cavity, "Glass"))
	local points = {
		{ 0, 1.6, 0.5, purple }, { -0.42, 2.1, 0.42, lilac }, { 0.4, 2.2, 0.4, purple }, { -0.35, 1.05, 0.44, lilac },
		{ 0.38, 1.2, 0.46, purple }, { 0, 2.6, 0.34, lilac }, { -0.6, 1.6, 0.34, purple }, { 0.62, 1.7, 0.32, lilac },
		{ 0.05, 0.8, 0.34, purple }, { -0.2, 2.45, 0.3, purple }, { 0.25, 0.95, 0.3, lilac }, { -0.15, 1.3, 0.3, lilac },
	}
	local count = lod <= 0 and #points or 6
	for i = 1, count do
		local p = points[i]
		local x, y, s = p[1], p[2], p[3]
		local u, w = x / 0.9, (y - 1.62) / 1.18
		local depth = 0.45 * math.sqrt(math.max(0, 1 - u * u - w * w))
		b:Box(V(s, s, s), CF(x, y, -0.36 - depth + 0.2 * s) * ANG(rad(w * 25), rad(-u * 25), 0) * POINT_OUT, p[4], "Glass")
	end
	b:Detail(function()
		-- two long points growing out of the cavity
		crystal(b, CF(-0.15, 2.05, -0.62) * ANG(rad(-62), 0, rad(18)), 0.2, 0.5, purple, lilac, "Glass", nil)
		crystal(b, CF(0.2, 1.35, -0.66) * ANG(rad(-75), 0, rad(-20)), 0.17, 0.42, lilac, lilac, "Glass", nil)
	end)
end

R.silver_ore = function(b, lod)
	local rock, rockDark, rockLight, silver, silverDark = C(128, 120, 114), C(92, 86, 84), C(150, 142, 134), C(234, 238, 246), C(176, 184, 198)
	-- a rounded grey boulder with broken angular chunks, silver breaking out along a vein
	local body = CF(0, 0.7, 0.05) * ANG(0, rad(10), 0)
	local size = V(2.25, 1.4, 1.95)
	b:Ellipsoid(size, body, rock, "Granite")
	b:Box(V(0.95, 0.85, 0.85), CF(-0.68, 0.74, 0.28) * ANG(rad(25), rad(-30), rad(20)), rockDark, "Granite")
	b:Wedge(V(1.1, 0.5, 0.9), CF(0.55, 1.28, 0.35) * ANG(0, rad(150), rad(10)), rockLight, "Granite")
	b:Box(V(0.8, 0.6, 0.7), CF(0.64, 0.48, -0.36) * ANG(rad(-15), rad(35), rad(20)), rockDark, "Granite")
	-- a point on the boulder's surface in direction d (local), pushed out by `out`
	local function surface(d, out)
		local u = d.Unit
		local k = 1 / math.sqrt((u.X / (size.X / 2)) ^ 2 + (u.Y / (size.Y / 2)) ^ 2 + (u.Z / (size.Z / 2)) ^ 2)
		return body:PointToWorldSpace(u * (k + out))
	end
	b:Accent(b:Ball(0.5, CF(surface(V(0.35, 0.35, -1), -0.08)), silver, "Foil"))
	b:Accent(b:Ball(0.38, CF(surface(V(-0.45, 0.1, -1), -0.06)), silver, "Foil"))
	-- the vein: a string of silver beads across the front and over the top
	local vein = { V(-0.8, -0.35, -1), V(-0.5, -0.15, -1), V(-0.2, 0.0, -1), V(0.1, 0.2, -1), V(0.25, 0.6, -1), V(0.2, 1, -0.6), V(0.1, 1, -0.2) }
	local beads = lod <= 0 and #vein or 3
	for i = 1, beads do
		local d = (i - 1) / (#vein - 1)
		b:Ball(0.22 - d * 0.06, CF(surface(vein[i], -0.04)), (i % 2 == 0) and silverDark or silver, "Metal")
	end
	local core = partsOf(b)
	b:Detail(function()
		b:Ball(0.24, CF(surface(V(0.9, 0.2, -0.6), -0.05)), silver, "Foil")
		b:Ball(0.18, CF(surface(V(-0.2, 1, 0.5), -0.03)), silverDark, "Foil")
		b:Ball(0.16, CF(surface(V(0.6, -0.4, -1), -0.03)), silver, "Metal")
	end)
	settle(b, core)
end

R.gold_nugget = function(b, _lod)
	local gold, goldDark, goldLight, iron, ironDark, sand, quartz = C(255, 194, 50), C(204, 140, 26), C(255, 224, 110), C(92, 90, 96), C(60, 58, 64), C(214, 186, 130), C(244, 242, 236)
	-- a prospector's pan with the nugget sitting in a little sand
	b:CylY(0.3, 2.4, CF(0, 0.15, 0), iron, "Metal")
	b:CylY(0.04, 2.08, CF(0, 0.29, 0), ironDark, "Metal")
	b:Ellipsoid(V(1.7, 0.24, 1.5), CF(0.1, 0.32, 0.1), sand, "Sand")
	b:Accent(b:Ellipsoid(V(1.25, 0.85, 1.0), CF(0, 0.72, 0) * ANG(0, rad(20), rad(8)), gold, "Metal"))
	b:Ellipsoid(V(0.8, 0.7, 0.75), CF(-0.45, 0.84, 0.2) * ANG(rad(20), rad(-30), 0), goldDark, "Metal")
	b:Accent(b:Ellipsoid(V(0.7, 0.6, 0.65), CF(0.42, 0.95, -0.15) * ANG(rad(-15), rad(40), rad(10)), goldLight, "Foil"))
	b:Ellipsoid(V(0.55, 0.5, 0.5), CF(0.05, 1.2, 0.12) * ANG(rad(10), 0, rad(-20)), gold, "Metal")
	b:Ellipsoid(V(0.5, 0.45, 0.55), CF(0.55, 0.62, 0.35) * ANG(0, rad(-25), 0), goldDark, "Metal")
	b:Detail(function()
		b:Ellipsoid(V(0.3, 0.24, 0.22), CF(-0.2, 1.05, -0.38) * ANG(rad(-30), rad(20), 0), quartz, "Marble")
		b:Ellipsoid(V(0.22, 0.18, 0.2), CF(0.62, 1.05, 0.2), quartz, "Marble")
		b:Ellipsoid(V(0.16, 0.08, 0.14), CF(0.1, 1.42, 0.0), goldDark, "Metal")
		b:Ellipsoid(V(0.14, 0.08, 0.12), CF(-0.58, 1.1, 0.12), C(150, 100, 20), "Metal")
		b:Ball(0.24, CF(-0.75, 0.38, -0.55), gold, "Foil")
		b:Ball(0.18, CF(0.85, 0.36, -0.55), goldLight, "Foil")
		b:Ball(0.14, CF(-0.2, 0.34, -0.8), gold, "Foil")
	end)
end

R.geode = function(b, lod)
	local shell, shellDark, white, blue, deep, spark, pale = C(152, 128, 106), C(112, 94, 80), C(242, 242, 246), C(80, 146, 222), C(30, 50, 110), C(214, 240, 255), C(150, 200, 250)
	-- the two halves of a round geode, opened like a book and tipped back so the hollow shows
	local crystals = {
		{ 0, 0.02, 0.38 }, { 0.3, 0.16, 0.3 }, { -0.28, 0.2, 0.3 }, { 0.12, -0.32, 0.3 },
		{ -0.3, -0.22, 0.28 }, { 0.38, -0.16, 0.24 }, { -0.04, 0.4, 0.26 }, { -0.44, 0.02, 0.22 },
	}
	local function halfCF(s)
		return CF(s * 0.84, 0.85, 0.1) * ANG(0, rad(24 * s), 0) * ANG(rad(32), 0, 0)
	end
	for _, s in { -1, 1 } do
		local half = halfCF(s)
		-- shell: a short rim band, a rounded back and a lump that breaks the round outline
		b:CylZ(0.3, 1.76, half * CF(0, 0, 0.15), shell, "Slate")
		b:Ellipsoid(V(1.76, 1.76, 0.9), half * CF(0, 0, 0.3), shellDark, "Slate")
		-- cut face: a thin white agate rim, a blue band, then the hollow full of crystals
		b:CylZ(0.03, 1.68, half * CF(0, 0, -0.005), white, "Marble")
		b:Accent(b:CylZ(0.03, 1.5, half * CF(0, 0, -0.015), blue, "Glass"))
		b:CylZ(0.03, 1.32, half * CF(0, 0, -0.025), deep, "Slate")
		for i = 1, (lod <= 0 and #crystals or 1) do
			local c = crystals[i]
			point(b, half * CF(c[1], c[2], -0.02) * ANG(rad(-90), 0, 0) * ANG(0, rad(i * 47), 0), c[3], (i % 2 == 0) and pale or spark, "Glass")
		end
	end
	local core = partsOf(b)
	b:Detail(function()
		-- lumps that break the round outline of each half, and a broken chip lying in front
		for _, s in { -1, 1 } do
			b:Ellipsoid(V(0.9, 0.8, 0.6), halfCF(s) * CF(s * 0.55, 0.3, 0.42), shell, "Slate")
		end
		b:Ellipsoid(V(0.5, 0.26, 0.4), CF(0.05, 0.13, -0.95) * ANG(0, rad(25), 0), shell, "Slate")
		b:Ellipsoid(V(0.36, 0.06, 0.28), CF(0.05, 0.26, -0.95) * ANG(0, rad(25), 0), blue, "Glass")
	end)
	settle(b, core)
end

R.fossilized_fish = function(b, lod)
	local slab, slabDark, bone, boneDark, socket = C(220, 204, 166), C(186, 168, 130), C(150, 104, 60), C(116, 78, 44), C(70, 50, 34)
	local top = 0.3
	b:Box(V(2.6, top, 1.6), CF(0, top / 2, 0) * ANG(0, rad(4), 0), slab, "Limestone")
	b:Box(V(1.0, top - 0.04, 0.8), CF(1.05, (top - 0.04) / 2, 0.58) * ANG(0, rad(35), 0), slabDark, "Limestone")
	-- the fish lies on its side, head to the left
	local y = top + 0.02
	b:Accent(b:Ellipsoid(V(0.66, 0.14, 0.52), CF(-0.92, y, 0.02) * ANG(0, rad(-8), 0), bone, "Sandstone"))
	b:Accent(b:Cyl(1.55, 0.1, CF(-0.02, y, 0), bone, "Sandstone"))
	local ribs = lod <= 0 and 7 or 4
	for i = 1, ribs do
		local x = -0.58 + (i - 1) * (1.06 / (ribs - 1))
		local len = 0.66 - math.abs(x + 0.15) * 0.42
		b:Box(V(0.05, 0.05, len), CF(x, y, 0) * ANG(0, rad(-16), 0), bone, "Sandstone")
	end
	for _, s in { -1, 1 } do
		b:Box(V(0.5, 0.05, 0.08), CF(0.94, y, s * 0.13) * ANG(0, rad(30 * s), 0), bone, "Sandstone")
	end
	b:Detail(function()
		b:Ball(0.14, CF(-1.02, y + 0.02, -0.06), socket, "Slate")
		b:Box(V(0.32, 0.04, 0.04), CF(-1.1, y + 0.03, 0.12) * ANG(0, rad(-20), 0), boneDark, "Sandstone")
		for i = 0, 2 do
			b:Box(V(0.04, 0.04, 0.3), CF(-0.2 + i * 0.2, y, -0.42) * ANG(0, rad(-25), 0), boneDark, "Sandstone")
			b:Box(V(0.04, 0.04, 0.24), CF(0.0 + i * 0.18, y, 0.4) * ANG(0, rad(25), 0), boneDark, "Sandstone")
		end
		b:Box(V(1.3, 0.02, 0.03), CF(0.2, top + 0.005, -0.6) * ANG(0, rad(12), 0), slabDark, "Slate")
		b:Disc(CF(-0.95, top + 0.02, 0.55), 0.3, 0.04, boneDark, "Sandstone")
		b:Disc(CF(-0.95, top + 0.03, 0.55), 0.16, 0.04, bone, "Sandstone")
	end)
end

R.ancient_shark_tooth = function(b, _lod)
	local enamel, enamelLight, root, rootDark, band = C(204, 198, 182), C(232, 228, 214), C(150, 110, 70), C(104, 74, 46), C(70, 66, 64)
	local baseY, H, Wd, T = 0.6, 1.55, 1.36, 0.16
	-- the blade: two thin wedges back to back make the triangle, lenses give it a thick middle and sharp edges
	b:Accent(b:Wedge(V(T, H, Wd / 2), CF(Wd / 4, baseY + H / 2, 0) * ANG(0, rad(-90), 0), enamel, "Marble"))
	b:Accent(b:Wedge(V(T, H, Wd / 2), CF(-Wd / 4, baseY + H / 2, 0) * ANG(0, rad(90), 0), enamel, "Marble"))
	b:Ellipsoid(V(0.86, 1.2, 0.42), CF(0, baseY + 0.52, 0), enamel, "Marble")
	b:Ellipsoid(V(0.36, 0.7, 0.28), CF(0, baseY + 1.0, 0), enamel, "Marble")
	b:Box(V(1.38, 0.12, 0.3), CF(0, baseY + 0.02, 0), band, "Slate")
	-- the wide root with its notch underneath
	b:Ellipsoid(V(1.52, 0.68, 0.46), CF(0, 0.34, 0), root, "Sandstone")
	b:Detail(function()
		b:Ellipsoid(V(0.34, 0.3, 0.48), CF(0, 0.16, 0), rootDark, "Sandstone")
		-- serrated edges
		for _, s in { -1, 1 } do
			for i = 1, 5 do
				local t = 0.08 + i * 0.13
				local x, y = s * (Wd / 2) * (1 - t), baseY + H * t
				b:Box(V(0.08, 0.08, T * 0.9), CF(x, y, 0) * ANG(0, 0, rad(45)), enamelLight, "Marble")
			end
		end
		b:Ellipsoid(V(0.3, 0.2, 0.06), CF(0.32, 0.36, -0.22), rootDark, "Sandstone")
	end)
end

R.bat_skeleton = function(b, lod)
	local slab, slabDark, bone, boneShade, membrane = C(70, 70, 80), C(48, 48, 56), C(240, 232, 212), C(204, 194, 170), C(72, 54, 52)
	-- a dark slab propped up at the back, the skeleton spread out on it
	local slabCF = CF(0, 0.355, 0.05) * ANG(rad(-16), 0, 0)
	b:Box(V(2.7, 0.24, 1.65), slabCF, slab, "Basalt")
	b:Wedge(V(2.6, 0.46, 1.5), CF(0, 0.23, 0.1), slabDark, "Basalt")
	local function at(x, z, lift)
		return slabCF:PointToWorldSpace(V(x, 0.12 + (lift or 0.05), z))
	end
	-- skull with big ears, facing the front
	b:Accent(b:Ellipsoid(V(0.46, 0.26, 0.54), slabCF * CF(0, 0.2, -0.55), bone, "Limestone"))
	b:Rod(at(0, -0.32), at(0, 0.62), 0.09, bone, "Limestone")
	for _, s in { -1, 1 } do
		local shoulder, elbow, wrist = at(s * 0.1, -0.2), at(s * 0.62, -0.46), at(s * 1.12, -0.58)
		b:Rod(shoulder, elbow, 0.09, bone, "Limestone")
		b:Rod(elbow, wrist, 0.08, bone, "Limestone")
		-- three long finger bones fan out backwards
		local tips = { at(s * 1.32, 0.25), at(s * 0.6, 0.68), at(s * 1.0, 0.62) }
		for i = 1, (lod <= 0 and 3 or 2) do
			b:Rod(wrist, tips[i], 0.06, boneShade, "Limestone")
		end
	end
	b:Detail(function()
		b:Ellipsoid(V(0.24, 0.16, 0.3), slabCF * CF(0, 0.18, -0.86), bone, "Limestone")
		for _, s in { -1, 1 } do
			b:Wedge(V(0.06, 0.3, 0.26), slabCF * CF(s * 0.24, 0.19, -0.5) * ANG(0, rad(30 * s), rad(90 * s)), bone, "Limestone")
			b:Ellipsoid(V(0.66, 0.03, 0.48), slabCF * CF(s * 1.05, 0.13, 0.1) * ANG(0, rad(30 * s), 0), membrane, "Fabric")
			b:Ellipsoid(V(0.5, 0.03, 0.38), slabCF * CF(s * 0.74, 0.13, 0.36) * ANG(0, rad(-10 * s), 0), membrane, "Fabric")
			b:Rod(at(s * 0.06, 0.6), at(s * 0.3, 0.84), 0.05, boneShade, "Limestone")
			b:Ball(0.07, slabCF * CF(s * 0.06, 0.14, -0.98), P.White, "SmoothPlastic")
		end
		for _, z in { -0.12, 0.06 } do
			b:Rod(at(-0.22, z), at(0.22, z), 0.05, boneShade, "Limestone")
		end
	end)
end

R.crystal_skull = function(b, lod)
	local glass, glassDeep, socket, glow, stone, gold = C(196, 236, 255), C(150, 206, 236), C(26, 44, 86), C(90, 230, 255), C(52, 48, 60), C(240, 190, 70)
	local skull = { Transparency = 0.18 }
	b:CylY(0.3, 1.5, CF(0, 0.15, 0.05), stone, "Granite")
	b:Accent(b:Ellipsoid(V(1.5, 1.35, 1.6), CF(0, 1.4, 0.12), glass, "Glass", skull))
	b:Accent(b:Ellipsoid(V(1.2, 0.95, 1.1), CF(0, 1.0, -0.28), glass, "Glass", skull))
	b:Ellipsoid(V(0.88, 0.36, 0.8), CF(0, 0.55, -0.32), glassDeep, "Glass", skull)
	for _, s in { -1, 1 } do
		b:Ellipsoid(V(0.36, 0.3, 0.5), CF(s * 0.44, 0.98, -0.55), glass, "Glass", skull)
		b:Ellipsoid(V(0.42, 0.38, 0.2), CF(s * 0.27, 1.18, -0.8), socket, "Glass")
	end
	b:Ellipsoid(V(0.18, 0.24, 0.12), CF(0, 0.9, -0.84), socket, "Glass")
	b:Box(V(0.62, 0.16, 0.12), CF(0, 0.68, -0.7), C(232, 246, 255), "Glass")
	b:Detail(function()
		b:CylY(0.08, 1.38, CF(0, 0.33, 0.05), gold, "Metal")
		for _, s in { -1, 1 } do
			b:Ball(0.12, CF(s * 0.27, 1.17, -0.89), glow, "Neon")
		end
		for i = -1, 1 do
			b:Box(V(0.025, 0.16, 0.02), CF(i * 0.16, 0.68, -0.765), socket, "Glass")
		end
		-- the seam of the skull bones and the temples, carved into the crystal
		b:Ellipsoid(V(0.06, 1.36, 1.5), CF(0, 1.41, 0.14), glassDeep, "Glass", skull)
		for _, s in { -1, 1 } do
			b:Ellipsoid(V(0.12, 0.42, 0.5), CF(s * 0.7, 1.22, -0.25), glassDeep, "Glass", skull)
		end
	end)
end

R.miner_s_lantern = function(b, lod)
	local iron, ironDark, brass, glass, flame = C(78, 78, 86), C(52, 52, 58), C(222, 174, 76), C(255, 238, 196), C(255, 186, 64)
	b:CylY(0.36, 1.2, CF(0, 0.18, 0), iron, "Metal")
	b:Ellipsoid(V(0.96, 1.3, 0.96), CF(0, 1.02, 0), glass, "Glass", { Transparency = 0.45 })
	b:Accent(b:Ellipsoid(V(0.2, 0.42, 0.2), CF(0, 0.92, 0), flame, "Neon"))
	for k = 0, 3 do
		local a = rad(90 * k + 45)
		b:Rod(V(math.cos(a) * 0.5, 0.36, math.sin(a) * 0.5), V(math.cos(a) * 0.46, 1.72, math.sin(a) * 0.46), 0.07, ironDark, "Metal")
	end
	b:CylY(0.32, 0.5, CF(0, 1.82, 0), iron, "Metal")
	b:Accent(b:Cone(CF(0, 1.66, 0), 0.5, 1.04, 0.36, lod <= 0 and 3 or 2, brass, "Metal"))
	-- the wire bail handle
	b:Rod(V(-0.52, 1.7, 0), V(-0.36, 2.78, 0), 0.06, ironDark, "Metal")
	b:Rod(V(-0.38, 2.76, 0), V(0.38, 2.76, 0), 0.07, ironDark, "Metal")
	b:Rod(V(0.36, 2.78, 0), V(0.52, 1.7, 0), 0.06, ironDark, "Metal")
	b:Detail(function()
		b:CylY(0.1, 1.04, CF(0, 0.4, 0), brass, "Metal")
		b:CylY(0.05, 1.0, CF(0, 0.8, 0), ironDark, "Metal")
		b:CylY(0.05, 0.98, CF(0, 1.32, 0), ironDark, "Metal")
		b:CylY(0.12, 0.22, CF(0, 2.08, 0), brass, "Metal")
		b:CylY(0.16, 0.14, CF(0, 0.66, 0), brass, "Metal")
		b:CylZ(0.14, 0.16, CF(0.3, 0.2, -0.6), brass, "Metal")
		b:Box(V(0.36, 0.18, 0.03), CF(-0.15, 0.2, -0.6), brass, "Metal")
		b:Ball(0.1, CF(-0.52, 1.7, 0), brass, "Metal")
		b:Ball(0.1, CF(0.52, 1.7, 0), brass, "Metal")
	end)
end

R.broken_pickaxe = function(b, _lod)
	local wood, woodDark, leather, steel, edge, brass = C(150, 98, 56), C(104, 66, 38), C(84, 52, 32), C(132, 140, 152), C(214, 222, 232), C(222, 174, 76)
	-- standing on its snapped handle, one pick arm broken off
	b:CylY(2.18, 0.22, CF(0, 1.13, 0), wood, "Wood")
	b:CylY(0.55, 0.27, CF(0, 0.75, 0), leather, "Leather")
	b:Accent(b:Box(V(0.42, 0.44, 0.36), CF(0, 2.2, 0), steel, "Metal"))
	-- intact arm curving down to a point on the left
	local left = CF(-0.2, 2.22, 0) * ANG(0, 0, rad(8))
	b:Accent(b:Box(V(0.8, 0.26, 0.28), left * CF(-0.4, 0, 0), steel, "Metal"))
	b:Accent(b:Wedge(V(0.28, 0.26, 0.62), left * CF(-1.1, 0, 0) * ANG(0, rad(90), 0), edge, "Metal"))
	-- broken arm on the right with a bright fresh break
	local right = CF(0.2, 2.22, 0) * ANG(0, 0, rad(-8))
	b:Box(V(0.5, 0.26, 0.28), right * CF(0.25, 0, 0), steel, "Metal")
	b:Box(V(0.2, 0.2, 0.3), right * CF(0.5, 0.02, 0) * ANG(0, 0, rad(40)), edge, "Metal")
	b:Detail(function()
		-- splinters at the snapped end of the handle
		b:Wedge(V(0.1, 0.32, 0.08), CF(-0.05, 0.16, 0.04) * ANG(math.pi, 0, 0), woodDark, "Wood")
		b:Wedge(V(0.08, 0.24, 0.08), CF(0.06, 0.12, -0.04) * ANG(math.pi, rad(90), 0), wood, "Wood")
		b:Wedge(V(0.07, 0.2, 0.07), CF(0.02, 0.1, 0.07) * ANG(math.pi, rad(200), 0), woodDark, "Wood")
		b:CylY(0.06, 0.29, CF(0, 0.5, 0), brass, "Metal")
		b:CylY(0.06, 0.29, CF(0, 1.0, 0), brass, "Metal")
		b:CylZ(0.4, 0.09, CF(0, 2.2, 0), brass, "Metal")
		-- the snapped-off tip lies on the ground
		b:Wedge(V(0.26, 0.22, 0.5), CF(0.75, 0.13, -0.15) * ANG(0, rad(110), rad(90)), edge, "Metal")
	end)
end

R.ancient_miner_helmet = function(b, _lod)
	local leather, leatherDark, crest, brass, silver, lamp = C(122, 82, 48), C(92, 60, 36), C(104, 68, 40), C(222, 174, 76), C(210, 214, 222), C(255, 222, 130)
	b:Ellipsoid(V(2.25, 0.14, 2.35), CF(0, 0.08, 0.05), leatherDark, "Leather")
	b:CylY(0.62, 1.72, CF(0, 0.39, 0), leather, "Leather")
	b:Ellipsoid(V(1.72, 1.36, 1.72), CF(0, 0.7, 0), leather, "Leather")
	-- the ridge follows the dome from front to back
	b:Ellipsoid(V(0.2, 1.4, 1.76), CF(0, 0.7, 0), crest, "Leather")
	-- a brass oil lamp mounted on the front
	b:Box(V(0.36, 0.5, 0.1), CF(0, 0.6, -0.86), brass, "Metal")
	b:CylZ(0.36, 0.42, CF(0, 0.84, -1.0), brass, "Metal")
	b:Accent(b:CylZ(0.06, 0.66, CF(0, 0.84, -1.2), silver, "Metal"))
	b:Accent(b:CylZ(0.04, 0.44, CF(0, 0.84, -1.235), lamp, "Neon"))
	b:Detail(function()
		for k = 0, 7 do
			local a = rad(45 * k + 22.5)
			b:Ball(0.1, CF(math.cos(a) * 0.86, 0.5, math.sin(a) * 0.86), brass, "Metal")
		end
		b:Ellipsoid(V(0.5, 0.3, 0.06), CF(0.55, 1.0, -0.62) * ANG(rad(-35), rad(-35), 0), leatherDark, "Leather")
		b:CylY(0.24, 0.16, CF(0, 1.1, -1.0), brass, "Metal")
		b:Box(V(0.06, 0.5, 0.14), CF(0.87, 0.3, 0.0), leatherDark, "Leather")
		b:Box(V(0.08, 0.16, 0.18), CF(0.9, 0.18, 0.0), brass, "Metal")
	end)
end

R.meteor_fragment = function(b, lod)
	local crust, crustDark, iron, glow, pit = C(66, 52, 46), C(42, 34, 30), C(178, 180, 190), C(255, 112, 30), C(28, 22, 22)
	-- smoothed by its fall through the air: rounded lobes of dark fusion crust
	b:Ellipsoid(V(2.1, 1.3, 1.8), CF(0, 0.65, 0) * ANG(0, rad(15), rad(5)), crust, "CrackedLava")
	b:Ellipsoid(V(1.2, 1.0, 1.1), CF(0.6, 0.85, 0.4) * ANG(rad(20), rad(30), 0), crustDark, "Basalt")
	b:Ellipsoid(V(1.0, 0.8, 1.0), CF(-0.7, 0.42, -0.45) * ANG(0, rad(-20), rad(15)), crustDark, "Basalt")
	b:Ellipsoid(V(0.9, 0.7, 0.8), CF(-0.45, 1.0, 0.35) * ANG(rad(25), rad(35), rad(15)), crust, "Basalt")
	-- glowing seams across the top and front
	local seams = {
		{ V(-0.6, 1.24, -0.3), V(0.0, 1.32, -0.1) },
		{ V(0.0, 1.32, -0.1), V(0.5, 1.17, -0.45) },
		{ V(0.5, 1.17, -0.45), V(0.62, 0.6, -0.86) },
		{ V(-0.3, 0.9, -0.84), V(0.3, 0.75, -0.9) },
		{ V(-0.3, 0.9, -0.84), V(-0.75, 0.62, -0.88) },
	}
	for i = 1, (lod <= 0 and #seams or 2) do
		b:Accent(b:Beam(seams[i][1], seams[i][2], 0.08, glow, "Neon"))
	end
	local core = partsOf(b)
	b:Detail(function()
		-- shiny iron-nickel spots and the thumbprint pits of the fusion crust, one still glowing
		b:Ellipsoid(V(0.4, 0.3, 0.1), CF(-0.55, 0.62, -0.84) * ANG(rad(10), rad(30), 0), iron, "Metal")
		b:Ellipsoid(V(0.3, 0.08, 0.26), CF(0.3, 1.38, 0.25) * ANG(rad(15), 0, rad(-10)), iron, "Metal")
		b:Ellipsoid(V(0.26, 0.2, 0.08), CF(1.0, 0.7, -0.2) * ANG(0, rad(70), 0), iron, "Metal")
		for _, p in { V(-0.2, 1.33, 0.4), V(0.75, 1.12, 0.2), V(-0.95, 0.85, 0.1) } do
			b:Ball(0.26, CF(p), pit, "Basalt")
		end
		b:Ball(0.2, CF(0.2, 0.42, -0.86), glow, "Neon")
	end)
	settle(b, core)
end

R.red_crystal = function(b, lod)
	local ruby, rubyDark, tip, rock, rockDark, core = C(226, 30, 62), C(160, 14, 42), C(255, 96, 120), C(58, 48, 54), C(40, 34, 40), C(255, 60, 90)
	local glass = { Transparency = 0.1 }
	b:Ellipsoid(V(1.5, 0.6, 1.3), CF(0, 0.3, 0.05), rock, "Basalt")
	b:Accent(b:Ball(0.56, CF(0, 0.72, 0), core, "Neon"))
	-- shards burst out of one point in every upward direction: a spiky red star
	local origin = CF(0, 0.7, 0)
	local shards = {
		{ 0, 0, 2.3, 0.34 },
		{ 45, 42, 1.55, 0.26 }, { 135, 40, 1.6, 0.26 }, { 225, 44, 1.5, 0.26 }, { 315, 38, 1.65, 0.26 },
		{ 0, 72, 1.15, 0.22 }, { 90, 70, 1.2, 0.22 }, { 180, 74, 1.1, 0.22 }, { 270, 68, 1.2, 0.22 },
	}
	for i, s in shards do
		local cf = origin * ANG(0, rad(s[1]), 0) * ANG(rad(s[2]), 0, 0)
		local color = (i % 2 == 0) and rubyDark or ruby
		if lod <= 0 then
			local parts = b:Prism(cf, s[4], s[3], s[4] * 1.6, color, "Glass", glass)
			parts[2].Color = tip
			parts[3].Color = tip
			if i == 1 then
				b:Accent(parts)
			end
		else
			local part = b:Box(V(s[4], s[3], s[4]), cf * CF(0, s[3] / 2, 0), color, "Glass", glass)
			if i == 1 then
				b:Accent(part)
			end
		end
	end
	b:Detail(function()
		b:Ellipsoid(V(0.8, 0.4, 0.7), CF(0.6, 0.2, 0.45) * ANG(0, rad(30), 0), rockDark, "Basalt")
	end)
end

R.living_crystal = function(b, lod)
	local emerald, jade, vein, moss, root, leaf = C(36, 196, 112), C(110, 226, 150), C(150, 255, 170), C(70, 112, 50), C(86, 62, 42), C(96, 180, 70)
	local glass = { Transparency = 0.12 }
	b:Ellipsoid(V(1.7, 0.5, 1.5), CF(0, 0.25, 0.05), moss, "Grass")
	local mainCF = CF(0, 0.35, 0) * ANG(rad(-4), 0, rad(4))
	local radius, height = 0.46, 2.25
	crystal(b, mainCF, radius, height, emerald, jade, "Glass", glass, lod <= 0)
	crystal(b, CF(0.55, 0.3, 0.1) * ANG(rad(6), rad(20), rad(-28)), 0.28, 1.2, jade, jade, "Glass", glass)
	-- glowing veins on the three front faces of the main crystal
	local apothem = radius * SQ3 / 2
	for i, phi in { 210, 270, 330 } do
		local a = rad(phi)
		local len = height * (i == 2 and 0.85 or 0.62)
		local cf = mainCF * CF(math.cos(a) * (apothem + 0.012), 0.12 + len / 2, math.sin(a) * (apothem + 0.012)) * ANG(0, rad(90 - phi), 0)
		b:Accent(b:Box(V(0.07, len, 0.02), cf, vein, "Neon"))
	end
	b:Detail(function()
		crystal(b, CF(-0.5, 0.3, 0.2) * ANG(rad(10), rad(-10), rad(30)), 0.22, 0.85, emerald, jade, "Glass", glass)
		-- branches of the veins
		local a = rad(270)
		local face = mainCF * CF(math.cos(a) * (apothem + 0.012), 0, math.sin(a) * (apothem + 0.012)) * ANG(0, rad(90 - 270), 0)
		b:Box(V(0.05, 0.5, 0.02), face * CF(0.12, 1.3, 0) * ANG(0, 0, rad(-35)), vein, "Neon")
		b:Box(V(0.05, 0.4, 0.02), face * CF(-0.11, 0.85, 0) * ANG(0, 0, rad(35)), vein, "Neon")
		-- roots crawling out over the ground
		for k = 0, 4 do
			local yaw = rad(72 * k + 20)
			local d1 = V(math.cos(yaw), 0, math.sin(yaw))
			local d2 = V(math.cos(yaw + 0.5), 0, math.sin(yaw + 0.5))
			local p0 = d1 * 0.6 + V(0, 0.22, 0)
			local p1 = d1 * 1.0 + V(0, 0.1, 0)
			local p2 = p1 + d2 * 0.42 + V(0, -0.04, 0)
			b:Rod(p0, p1, 0.15, root, "Wood")
			b:Rod(p1, p2, 0.1, root, "Wood")
		end
		-- a sprout and glowing spores in the moss
		b:Ellipsoid(V(0.08, 0.36, 0.2), CF(0.35, 0.6, -0.45) * ANG(rad(-25), 0, rad(-20)), leaf, "Grass")
		b:Ellipsoid(V(0.08, 0.3, 0.18), CF(0.42, 0.58, -0.38) * ANG(rad(-10), 0, rad(30)), leaf, "Grass")
		b:Ball(0.1, CF(-0.4, 0.46, -0.5), vein, "Neon")
		b:Ball(0.08, CF(0.62, 0.36, -0.36), vein, "Neon")
	end)
end

R.fossilized_egg = function(b, lod)
	local shell, shellDark, spot, amber, eye, sand, stone, stoneDark = C(204, 188, 156), C(150, 130, 100), C(170, 150, 118), C(255, 150, 40), C(190, 255, 80), C(214, 188, 136), C(130, 124, 118), C(100, 96, 92)
	b:Ellipsoid(V(2.2, 0.3, 2.1), CF(0, 0.15, 0), sand, "Sand")
	-- a nest of round stones
	local stones = lod <= 0 and 7 or 4
	for k = 0, stones - 1 do
		local a = 2 * math.pi * k / stones + 0.3
		local size = 0.5 + ((k * 37) % 5) * 0.04
		b:Ellipsoid(V(size, size * 0.7, size * 0.9), CF(math.cos(a) * 0.95, size * 0.33, math.sin(a) * 0.9) * ANG(0, -a, 0), (k % 2 == 0) and stone or stoneDark, "Slate")
	end
	local egg = CF(0, 1.12, 0.05) * ANG(rad(6), 0, rad(-6))
	b:Ellipsoid(V(1.55, 2.06, 1.55), egg, shell, "Sandstone")
	-- the shell has cracked open at the front: a glowing amber hollow with an eye looking out
	b:Ellipsoid(V(0.78, 0.62, 0.2), egg * CF(0.12, 0.3, -0.7) * ANG(rad(-10), rad(8), 0), shellDark, "Slate")
	b:Accent(b:Ellipsoid(V(0.6, 0.46, 0.16), egg * CF(0.12, 0.3, -0.76) * ANG(rad(-10), rad(8), 0), amber, "Neon"))
	b:Detail(function()
		b:Ellipsoid(V(0.24, 0.2, 0.08), egg * CF(0.18, 0.32, -0.83) * ANG(rad(-10), rad(8), 0), eye, "Neon")
		b:Box(V(0.04, 0.16, 0.04), egg * CF(0.18, 0.32, -0.87) * ANG(rad(-10), rad(8), 0), P.Ink, "SmoothPlastic")
		for _, p in { V(-0.45, 0.6, -0.48), V(0.5, -0.35, -0.5), V(-0.55, -0.3, 0.45), V(0.2, 0.75, 0.5) } do
			local n = p.Unit
			b:Ellipsoid(V(0.26, 0.2, 0.06), egg * CF(p * 1.0) * CF(n * 0.05) * ANG(math.asin(-n.Y), math.atan2(-n.X, -n.Z), 0), spot, "Sandstone")
		end
		-- cracks running away from the hole
		b:Box(V(0.04, 0.5, 0.04), egg * CF(-0.32, 0.62, -0.62) * ANG(rad(-35), 0, rad(30)), shellDark, "Slate")
		b:Box(V(0.04, 0.4, 0.04), egg * CF(0.5, 0.0, -0.58) * ANG(rad(10), 0, rad(-40)), shellDark, "Slate")
		-- broken shell fragments on the sand
		b:Ellipsoid(V(0.4, 0.08, 0.3), CF(-0.62, 0.32, -0.62) * ANG(rad(10), rad(30), rad(-15)), shell, "Sandstone")
		b:Ellipsoid(V(0.28, 0.07, 0.22), CF(0.45, 0.31, -0.78) * ANG(rad(-10), rad(-20), rad(12)), shell, "Sandstone")
	end)
end

R.miner_s_badge = function(b, _lod)
	local gold, goldDark, enamel, steel, wood, ribbonRed, ribbonBlue = C(255, 198, 56), C(206, 142, 32), C(30, 52, 120), C(212, 218, 228), C(150, 98, 56), C(206, 40, 52), C(40, 80, 170)
	local centre = CF(0, 1.12, 0)
	-- a sixteen-point sunburst: two big squares and two smaller ones turned in between
	b:Box(V(1.58, 1.58, 0.1), centre, gold, "Metal")
	b:Box(V(1.58, 1.58, 0.1), centre * ANG(0, 0, rad(45)), gold, "Metal")
	b:Box(V(1.3, 1.3, 0.12), centre * ANG(0, 0, rad(22.5)), goldDark, "Metal")
	b:Box(V(1.3, 1.3, 0.12), centre * ANG(0, 0, rad(67.5)), goldDark, "Metal")
	b:Accent(b:CylZ(0.16, 1.34, centre * CF(0, 0, -0.04), gold, "Foil"))
	b:CylZ(0.16, 1.12, centre * CF(0, 0, -0.06), enamel, "SmoothPlastic")
	-- crossed pickaxes
	for _, s in { -1, 1 } do
		local arm = centre * CF(0, 0, -0.16) * ANG(0, 0, rad(40 * s))
		b:Box(V(0.09, 0.95, 0.05), arm, wood, "Wood")
		b:Box(V(0.5, 0.11, 0.06), arm * CF(0, 0.42, 0) * ANG(0, 0, rad(-8 * s)), steel, "Metal")
	end
	b:Accent(b:Gem(0.28, centre * CF(0, 0, -0.2), P.Ruby, "Glass"))
	b:Detail(function()
		-- ribbon bar on top and rivets around the medallion
		b:Box(V(0.8, 0.34, 0.08), CF(0, 2.24, 0.02), ribbonRed, "Fabric")
		b:Box(V(0.26, 0.34, 0.085), CF(0, 2.24, 0.02), P.White, "Fabric")
		b:Box(V(0.1, 0.34, 0.09), CF(0, 2.24, 0.02), ribbonBlue, "Fabric")
		b:Box(V(0.9, 0.06, 0.1), CF(0, 2.05, 0.02), goldDark, "Metal")
		for k = 0, 7 do
			local a = rad(45 * k + 22.5)
			b:Ball(0.08, centre * CF(math.cos(a) * 0.6, math.sin(a) * 0.6, -0.13), goldDark, "Metal")
		end
	end)
end

R.head_sized_diamond = function(b, lod)
	local marble, gold, ice, iceDeep, iceLight, tableTop = C(232, 230, 236), C(255, 198, 56), C(206, 236, 255), C(160, 204, 244), C(232, 246, 255), C(214, 238, 255)
	local props = { Transparency = 0.1 }
	-- display stand: marble column, gold cup and four claws
	b:CylY(0.5, 1.2, CF(0, 0.25, 0), marble, "Marble")
	b:CylY(0.1, 1.32, CF(0, 0.55, 0), gold, "Metal")
	local girdleY, Rg, crownH, tableR, pavH = 1.72, 1.25, 0.42, 0.68, 1.1
	local sectors = lod <= 0 and 8 or 4
	local width = 2 * Rg * math.tan(math.pi / sectors) * 1.02
	for k = 0, sectors - 1 do
		local a = 2 * math.pi * (k + 0.5) / sectors
		local d = V(math.cos(a), 0, math.sin(a))
		-- pavilion facet: a wedge upside down, deepest at the axis
		local pos = V(0, girdleY - pavH / 2, 0) + d * (Rg / 2)
		b:Wedge(V(width, pavH, Rg), CFrame.fromMatrix(pos, V(d.Z, 0, -d.X), V(0, -1, 0), -d), (k % 2 == 0) and iceDeep or ice, "Glass", props)
		-- crown facet: sloping up from the girdle to the table
		local cpos = V(0, girdleY + crownH / 2, 0) + d * ((Rg + tableR) / 2)
		b:Wedge(V(width * 0.85, crownH, Rg - tableR), CFrame.fromMatrix(cpos, V(-d.Z, 0, d.X), V(0, 1, 0), -d), (k % 2 == 0) and iceLight or ice, "Glass", props)
	end
	b:Accent(b:CylY(crownH, tableR * 2, CF(0, girdleY + crownH / 2, 0), tableTop, "Glass", props))
	b:Accent(b:CylY(0.08, Rg * 2, CF(0, girdleY, 0), iceLight, "Glass", props))
	b:Detail(function()
		for k = 0, 3 do
			local a = rad(90 * k + 45)
			b:Rod(V(math.cos(a) * 0.6, 0.58, math.sin(a) * 0.6), V(math.cos(a) * 1.2, girdleY + 0.08, math.sin(a) * 1.2), 0.1, gold, "Metal")
			b:Ball(0.16, CF(math.cos(a) * 1.22, girdleY + 0.1, math.sin(a) * 1.22), gold, "Metal")
		end
		-- glints
		b:Box(V(0.36, 0.05, 0.05), CF(-0.3, girdleY + crownH + 0.02, -0.2) * ANG(0, rad(30), 0), P.White, "Neon")
		b:Box(V(0.05, 0.05, 0.36), CF(-0.3, girdleY + crownH + 0.02, -0.2) * ANG(0, rad(30), 0), P.White, "Neon")
	end)
end

R.underground_pearl = function(b, _lod)
	local shell, shellDark, nacre, nacreDeep, pearl, glow, sand = C(118, 106, 98), C(84, 76, 72), C(236, 220, 240), C(196, 186, 236), C(252, 246, 240), C(150, 255, 240), C(196, 176, 140)
	-- the lower valve with its mother-of-pearl lining
	b:Ellipsoid(V(2.2, 0.6, 1.9), CF(0, 0.3, -0.05), shell, "Slate")
	b:Ellipsoid(V(1.86, 0.3, 1.58), CF(0, 0.5, -0.07), nacre, "Marble")
	-- the upper valve swung open on its hinge at the back
	local lid = CF(0, 0.52, 0.82) * ANG(rad(62), 0, 0) * CF(0, 0.06, -0.92)
	b:Ellipsoid(V(2.1, 0.46, 1.84), lid * CF(0, 0.12, 0), shellDark, "Slate")
	b:Ellipsoid(V(1.8, 0.24, 1.54), lid * CF(0, -0.06, 0), nacreDeep, "Marble")
	b:Accent(b:Ball(0.9, CF(0, 0.98, -0.12), pearl, "SmoothPlastic", { Reflectance = 0.25 }))
	b:Accent(b:CylY(0.04, 1.2, CF(0, 0.65, -0.12), glow, "Neon", { Transparency = 0.35 }))
	b:Ball(0.14, CF(-0.2, 1.24, -0.42), P.White, "Neon")
	b:Detail(function()
		-- growth ridges on both valves
		for i = -2, 2 do
			b:Ellipsoid(V(0.12, 0.1, 1.5), lid * CF(i * 0.36, 0.3, 0.05) * ANG(0, rad(i * 12), 0), shell, "Slate")
		end
		for i = -1, 1 do
			b:Ellipsoid(V(0.16, 0.36, 1.4), CF(i * 0.62, 0.3, -0.08) * ANG(0, rad(i * 18), 0), shellDark, "Slate")
		end
		b:Cyl(0.9, 0.16, CF(0, 0.5, 0.85), shellDark, "Slate")
		-- two seed pearls and the sand bed
		b:Ball(0.2, CF(0.55, 0.66, -0.35), pearl, "SmoothPlastic", { Reflectance = 0.25 })
		b:Ball(0.15, CF(-0.6, 0.64, 0.05), pearl, "SmoothPlastic", { Reflectance = 0.25 })
		b:Ellipsoid(V(2.6, 0.16, 2.3), CF(0, 0.08, 0.1), sand, "Sand")
		b:Ellipsoid(V(0.3, 0.22, 0.26), CF(1.15, 0.11, -0.6), shellDark, "Slate")
		b:Ellipsoid(V(0.24, 0.18, 0.2), CF(-1.1, 0.09, -0.75), shell, "Slate")
	end)
end

R.heart_of_the_cavern = function(b, lod)
	local ruby, rubyLight, core, rock, rockDark, gold, crack = C(196, 16, 48), C(255, 84, 112), C(255, 60, 96), C(52, 44, 50), C(36, 30, 36), C(255, 196, 54), C(255, 80, 40)
	local glass = { Transparency = 0.12 }
	b:Ellipsoid(V(2.2, 0.82, 1.8), CF(0, 0.41, 0.05), rock, "Basalt")
	-- the heart: a square on its corner plus two round lobes on its upper sides
	local a = 1.25
	local h = CF(0, 1.62, 0)
	local half = a / math.sqrt(2)
	b:Box(V(a, a, 0.8), h * ANG(0, 0, rad(45)), ruby, "Glass", glass)
	for _, s in { -1, 1 } do
		b:Ellipsoid(V(a, a, 0.8), h * CF(s * half / 2, half / 2, 0), ruby, "Glass", glass)
	end
	-- a raised inner heart (the cut facet) and the glowing core through it
	if lod <= 0 then
		local k = 0.62
		b:Box(V(a * k, a * k, 0.86), h * CF(0, 0.08, 0) * ANG(0, 0, rad(45)), rubyLight, "Glass", glass)
		for _, s in { -1, 1 } do
			b:Ellipsoid(V(a * k, a * k, 0.86), h * CF(s * half * k / 2, 0.08 + half * k / 2, 0), rubyLight, "Glass", glass)
		end
	end
	b:Accent(b:Ellipsoid(V(0.7, 0.7, 1.0), h * CF(0, 0.22, 0), core, "Neon"))
	b:Accent(b:CylY(0.16, 0.5, CF(0, 0.82, 0), gold, "Metal"))
	b:Detail(function()
		b:Box(V(1.0, 0.7, 0.8), CF(-0.72, 0.61, 0.4) * ANG(rad(20), rad(30), rad(10)), rockDark, "Basalt")
		b:Box(V(0.8, 0.6, 0.7), CF(0.78, 0.52, -0.3) * ANG(rad(-10), rad(-25), rad(15)), rockDark, "Basalt")
		-- glowing cracks in the rock
		b:Beam(V(-0.6, 0.66, -0.6), V(-0.1, 0.8, -0.45), 0.06, crack, "Neon")
		b:Beam(V(0.2, 0.8, -0.5), V(0.75, 0.55, -0.62), 0.06, crack, "Neon")
		b:Beam(V(0.4, 0.75, 0.55), V(0.85, 0.5, 0.3), 0.06, crack, "Neon")
		-- small shards growing around the heart
		b:Prism(CF(-0.75, 0.55, -0.25) * ANG(rad(-15), 0, rad(35)), 0.18, 0.5, 0.25, ruby, "Glass", glass)
		b:Prism(CF(0.7, 0.55, 0.2) * ANG(rad(15), 0, rad(-40)), 0.16, 0.4, 0.22, ruby, "Glass", glass)
	end)
end

return R
