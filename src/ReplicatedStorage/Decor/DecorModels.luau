--!strict
-- Plot decoration models built from code (ReplicatedStorage.Forge): one recipe per
-- DecorCatalog id. Docs: docs/PLOT_COSMETICS.md.
--   DecorModels.Has(id) -> boolean
--   DecorModels.Build(id, lod?) -> Model?     a fresh build (tests, QA renders)
--   DecorModels.Get(id, lod?) -> Model?       a clone of the cached template (server world, previews)
-- Conventions: the model stands on Y = 0 around the origin, its front (-Z) faces the yard walkway.
-- Budgets (tests/plot_cosmetics.luau): Small <= 40 parts within 3.2 (X) x 1.8 (Z) at the ground
-- (3.6 x 3 above 3 studs); Large <= 120 parts within 9.6 x 11. Only Lighting pieces carry a light
-- (one PointLight each); the rest glow with Neon accents. Parts are non-collidable except the
-- walls / bases of big buildings and statue plinths (props CanCollide), so paths stay open.
local Forge = require(script.Parent.Parent:WaitForChild("Forge"))

local DecorModels = {}
local Pal = Forge.Palette
local C = Forge.C
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local SOLID = { CanCollide = true }

type Builder = Forge.Builder
local recipes: { [string]: (Builder) -> () } = {}
DecorModels.Recipes = recipes

------------------------------------------------------------------------------------------------
-- Shared shapes
------------------------------------------------------------------------------------------------
-- A cartoon bone along the cf X axis.
local function bone(b: Builder, cf: CFrame, length: number, d: number, color: Color3, mat: string?)
	b:Cyl(length, d, cf, color, mat or "SmoothPlastic")
	for _, x in ipairs({ -length / 2, length / 2 }) do
		for _, z in ipairs({ -d * 0.42, d * 0.42 }) do
			b:Ball(d * 1.35, cf * CF(x, 0, z), color, mat or "SmoothPlastic")
		end
	end
end

-- A sitting dog facing -Z, about 2.9 * s tall. opts: Ears = "pointy" | "floppy" | "tall",
-- Collar = colour, Mat = material, Eyes = colour, Nose = colour, Accent = true (collar accent).
local function dog(b: Builder, cf: CFrame, s: number, color: Color3, opts: any?)
	local o = opts or {}
	local mat = o.Mat or "SmoothPlastic"
	local dark = o.Nose or C(30, 26, 28)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CF(x * s, y * s, z * s)
	end
	b:Ellipsoid(V(1.55, 1.25, 1.75) * s, at(0, 0.62, 0.38), color, mat) -- haunches
	b:Ellipsoid(V(1.3, 1.75, 1.2) * s, at(0, 1.38, -0.12) * ANG(rad(-14), 0, 0), color, mat) -- chest
	for _, x in ipairs({ -0.36, 0.36 }) do
		b:CylY(1.15 * s, 0.38 * s, at(x, 0.62, -0.55), color, mat) -- front legs
		b:Ellipsoid(V(0.46, 0.26, 0.62) * s, at(x, 0.13, -0.72), color, mat) -- front paws
		b:Ellipsoid(V(0.5, 0.3, 0.8) * s, at(x * 1.75, 0.15, 0.05), color, mat) -- hind paws
	end
	b:Ball(1.12 * s, at(0, 2.45, -0.42), color, mat) -- head
	b:Ellipsoid(V(0.62, 0.52, 0.78) * s, at(0, 2.28, -0.98), color, mat) -- snout
	b:Ball(0.24 * s, at(0, 2.42, -1.36), dark, "SmoothPlastic") -- nose
	b:Detail(function()
		for _, x in ipairs({ -0.25, 0.25 }) do
			b:Ball(0.17 * s, at(x, 2.62, -0.9), o.Eyes or dark, o.Eyes and "Neon" or "SmoothPlastic")
		end
	end)
	local ears = o.Ears or "pointy"
	for _, side in ipairs({ -1, 1 }) do
		if ears == "floppy" then
			b:Ellipsoid(V(0.32, 0.85, 0.5) * s, at(side * 0.58, 2.3, -0.35) * ANG(0, 0, rad(side * 12)), color:Lerp(Color3.new(0, 0, 0), 0.15), mat)
		elseif ears == "tall" then
			b:Ellipsoid(V(0.26, 1.25, 0.45) * s, at(side * 0.36, 3.2, -0.3) * ANG(0, 0, rad(side * -8)), color, mat)
		else
			b:Ellipsoid(V(0.3, 0.78, 0.5) * s, at(side * 0.42, 2.98, -0.35) * ANG(0, 0, rad(side * -18)), color, mat)
		end
	end
	b:Rod(at(0, 0.65, 1.1).Position, at(0.25, 1.45, 1.45).Position, 0.26 * s, color, mat) -- tail
	if o.Collar then
		local collar = b:Disc(at(0, 1.98, -0.32) * ANG(rad(-14), 0, 0), 1.02 * s, 0.17 * s, o.Collar, o.CollarMat or "Metal")
		if o.Accent then
			b:Accent(collar)
		end
	end
end

-- A cluster of leafy ellipsoids around `center` (canopy), deterministic.
local function canopy(b: Builder, center: Vector3, size: Vector3, colors: { Color3 }, n: number)
	local offsets = {
		V(0, 0.2, 0), V(-0.45, -0.05, 0.1), V(0.45, 0, -0.1), V(0.05, 0.1, 0.42), V(-0.05, -0.1, -0.42),
		V(0.25, 0.45, 0.15), V(-0.25, 0.4, -0.15),
	}
	for i = 1, math.min(n, #offsets) do
		local off = offsets[i]
		local scale = i == 1 and 1 or 0.72
		b:Ellipsoid(size * scale, CF(center + V(off.X * size.X, off.Y * size.Y, off.Z * size.Z)), colors[(i - 1) % #colors + 1], "Grass")
	end
end

-- A low round base mound / plate (ground contact).
local function plate(b: Builder, w: number, d: number, h: number, color: Color3, mat: string?, props: any?)
	return b:Box(V(w, h, d), CF(0, h / 2, 0), color, mat or "Slate", props)
end

-- Crenellated wall top along X (castles).
local function crenels(b: Builder, cf: CFrame, length: number, color: Color3, mat: string)
	local n = math.max(2, math.floor(length / 1.1))
	for i = 0, n - 1 do
		if i % 2 == 0 then
			b:Box(V(length / n, 0.55, 0.62), cf * CF(-length / 2 + (i + 0.5) * length / n, 0.27, 0), color, mat)
		end
	end
end

------------------------------------------------------------------------------------------------
-- BUILDINGS (Large)
------------------------------------------------------------------------------------------------
recipes.doghouse_deluxe = function(b)
	local wall, trim, roofC = C(196, 72, 58), C(250, 236, 205), C(64, 70, 92)
	plate(b, 8.6, 8.4, 0.35, C(170, 160, 146), "Cobblestone", SOLID)
	-- House body
	b:Box(V(6.2, 3.8, 5.6), CF(0, 0.35 + 1.9, 0.6), wall, "WoodPlanks", SOLID)
	b:Box(V(6.5, 0.35, 5.9), CF(0, 0.35 + 0.18, 0.6), trim, "WoodPlanks")
	for _, x in ipairs({ -3.15, 3.15 }) do
		b:Box(V(0.3, 3.8, 0.3), CF(x, 0.35 + 1.9, -2.2), trim, "WoodPlanks")
		b:Box(V(0.3, 3.8, 0.3), CF(x, 0.35 + 1.9, 3.4), trim, "WoodPlanks")
	end
	-- Gabled roof, ridge from front to back, with a ridge cap
	b:Roof(V(6.6, 2.1, 6.9), CF(0, 4.15 + 1.05, 0.6) * ANG(0, math.pi / 2, 0), roofC, "Slate")
	b:Box(V(0.45, 0.4, 7.0), CF(0, 6.25, 0.6), trim, "WoodPlanks")
	-- Arched doorway
	b:Box(V(2.2, 2.2, 0.2), CF(0, 0.35 + 1.1, -2.22), C(40, 26, 22), "SmoothPlastic")
	b:CylZ(0.2, 2.2, CF(0, 0.35 + 2.2, -2.22), C(40, 26, 22), "SmoothPlastic")
	b:Ring(CF(0, 0.35 + 2.2, -2.3) * ANG(math.pi / 2, 0, 0), 1.2, 0.22, trim, "WoodPlanks", 10)
	-- Bone plaque above the door
	bone(b, CF(0, 4.75, -2.85), 1.6, 0.32, Pal.Bone)
	-- Windows
	b:Detail(function()
		for _, x in ipairs({ -3.2, 3.2 }) do
			b:Box(V(0.15, 1.1, 1.3), CF(x, 2.6, 0.9), C(150, 210, 240), "Glass")
			b:Box(V(0.2, 1.35, 0.15), CF(x, 2.6, 0.9), trim, "WoodPlanks")
			b:Box(V(0.2, 0.15, 1.55), CF(x, 2.6, 0.9), trim, "WoodPlanks")
		end
	end)
	-- Chimney
	b:Box(V(0.9, 2.2, 0.9), CF(2, 5.9, 2.4), C(150, 70, 56), "Brick")
	b:Box(V(1.1, 0.25, 1.1), CF(2, 7.05, 2.4), C(90, 86, 86), "Slate")
	-- Porch: food bowl, water bowl, a bone and a welcome mat
	b:Box(V(2.4, 0.06, 1.3), CF(0, 0.38, -3.2), C(84, 132, 72), "Fabric")
	b:CylY(0.35, 1.0, CF(-2.6, 0.52, -3.4), C(220, 60, 60), "SmoothPlastic")
	b:CylY(0.08, 0.8, CF(-2.6, 0.7, -3.4), C(140, 90, 50), "SmoothPlastic")
	b:CylY(0.35, 1.0, CF(2.6, 0.52, -3.4), C(60, 120, 220), "SmoothPlastic")
	b:CylY(0.08, 0.8, CF(2.6, 0.68, -3.4), Pal.Water, "Glass")
	bone(b, CF(1.2, 0.5, -3.7) * ANG(0, rad(25), 0), 1.1, 0.22, Pal.Bone)
	-- Name sign post
	b:Box(V(0.18, 1.6, 0.18), CF(-3.6, 1.15, -3.6), Pal.WoodDark, "Wood")
	b:Box(V(1.4, 0.6, 0.12), CF(-3.6, 1.8, -3.66), trim, "WoodPlanks")
	b:Accent(b:Box(V(1.0, 0.18, 0.04), CF(-3.6, 1.8, -3.73), C(255, 196, 60), "Neon"))
end

recipes.gazebo = function(b)
	local white, roofC, floor = C(246, 242, 232), C(70, 110, 120), C(186, 150, 110)
	b:Disc(CF(0, 0.3, 0), 9.2, 0.6, C(170, 164, 150), "Slate", SOLID)
	b:Disc(CF(0, 0.65, 0), 8.6, 0.1, floor, "WoodPlanks")
	-- Front steps
	for i = 1, 2 do
		b:Box(V(3, 0.3, 0.8), CF(0, 0.15 * i, -4.4 - (2 - i) * 0.7), C(170, 164, 150), "Slate")
	end
	local r = 3.7
	local posts = {}
	for i = 0, 5 do
		local a = rad(i * 60 + 30)
		local x, z = math.sin(a) * r, -math.cos(a) * r
		table.insert(posts, V(x, 0, z))
		b:CylY(4.6, 0.42, CF(x, 0.7 + 2.3, z), white, "Marble", SOLID)
		b:Box(V(0.6, 0.25, 0.6), CF(x, 0.82, z), white, "Marble")
	end
	-- Railings between posts (front opening left free)
	for i = 1, 6 do
		local a, c = posts[i], posts[i % 6 + 1]
		local mid = (a + c) / 2
		if mid.Z > -2 then
			b:Beam(V(a.X, 1.9, a.Z), V(c.X, 1.9, c.Z), 0.16, white, "Marble")
			b:Beam(V(a.X, 1.0, a.Z), V(c.X, 1.0, c.Z), 0.12, white, "Marble")
			b:Detail(function()
				for t = 1, 3 do
					local p = a:Lerp(c, t / 4)
					b:CylY(0.9, 0.12, CF(p.X, 1.45, p.Z), white, "Marble")
				end
			end)
		end
	end
	-- Ring beam and roof
	for i = 1, 6 do
		local a, c = posts[i], posts[i % 6 + 1]
		b:Beam(V(a.X, 5.3, a.Z), V(c.X, 5.3, c.Z), 0.32, white, "Marble")
	end
	b:Cone(CF(0, 5.45, 0), 2.9, 9.3, 0.6, 5, roofC, "Slate")
	b:Disc(CF(0, 5.5, 0), 9.6, 0.2, white, "Marble")
	b:CylY(0.9, 0.18, CF(0, 8.7, 0), Pal.Gold, "Metal")
	b:Accent(b:Ball(0.5, CF(0, 9.25, 0), Pal.Gold, "Metal"))
	-- Hanging lantern and planters
	b:Rod(V(0, 5.3, 0), V(0, 4.3, 0), 0.06, Pal.Iron, "Metal")
	b:Accent(b:Box(V(0.5, 0.65, 0.5), CF(0, 4.0, 0), C(255, 214, 140), "Neon"))
	b:Box(V(0.65, 0.12, 0.65), CF(0, 4.35, 0), Pal.Iron, "Metal")
	for _, x in ipairs({ -2.3, 2.3 }) do
		b:Box(V(1.2, 0.8, 0.9), CF(x, 0.4, -4.6), C(150, 110, 80), "WoodPlanks")
		canopy(b, V(x, 1.15, -4.6), V(1.1, 0.7, 0.9), { Pal.Leaf, C(240, 120, 170) }, 2)
	end
end

recipes.treehouse = function(b)
	local bark, wood, roofC = C(110, 76, 50), C(176, 128, 84), C(170, 70, 50)
	b:Disc(CF(0, 0.08, 0.6), 4.2, 0.16, C(98, 140, 70), "Grass")
	-- Trunk with roots
	b:CylY(7.4, 1.9, CF(0, 3.7, 0.8), bark, "Wood", SOLID)
	for i = 0, 3 do
		local a = rad(i * 90 + 45)
		b:Wedge(V(0.8, 1.2, 1.4), CF(math.sin(a) * 1.15, 0.6, 0.8 - math.cos(a) * 1.15) * ANG(0, -a + math.pi, 0), bark, "Wood")
	end
	-- Platform with railing
	b:Box(V(6.4, 0.35, 6.0), CF(0, 4.6, 0.4), wood, "WoodPlanks", SOLID)
	for _, x in ipairs({ -2.6, 2.6 }) do
		b:Rod(V(x, 4.45, -2.1), V(x * 0.4, 1.8, -0.4), 0.28, bark, "Wood")
		b:Rod(V(x, 4.45, 2.6), V(x * 0.4, 1.8, 1.6), 0.28, bark, "Wood")
	end
	for _, z in ipairs({ -2.5, 3.3 }) do
		b:Box(V(6.2, 0.14, 0.14), CF(0, 5.6, z), wood, "WoodPlanks")
	end
	for _, x in ipairs({ -3.1, 3.1 }) do
		b:Box(V(0.14, 0.14, 5.8), CF(x, 5.6, 0.4), wood, "WoodPlanks")
		for _, z in ipairs({ -2.5, 3.3 }) do
			b:Box(V(0.2, 1.1, 0.2), CF(x, 5.2, z), wood, "WoodPlanks")
		end
	end
	-- Cabin
	b:Box(V(3.8, 2.6, 3.2), CF(0.4, 4.78 + 1.3, 1.2), C(206, 160, 104), "WoodPlanks", SOLID)
	b:Roof(V(4.4, 1.5, 3.9), CF(0.4, 4.78 + 2.6 + 0.75, 1.2), roofC, "Slate")
	b:Box(V(1.0, 1.7, 0.12), CF(0.4, 4.78 + 0.85, -0.42), C(80, 52, 34), "WoodPlanks")
	b:Detail(function()
		b:Box(V(0.9, 0.8, 0.1), CF(-0.9, 6.3, -0.42), C(150, 210, 240), "Glass")
		b:Box(V(0.9, 0.8, 0.1), CF(1.7, 6.3, -0.42), C(150, 210, 240), "Glass")
	end)
	-- Ladder
	for _, x in ipairs({ -2.05, -1.25 }) do
		b:Box(V(0.16, 4.6, 0.16), CF(x, 2.3, -2.75) * ANG(rad(-8), 0, 0), wood, "WoodPlanks")
	end
	b:Detail(function()
		for i = 1, 5 do
			b:Box(V(0.95, 0.12, 0.14), CF(-1.65, i * 0.78, -2.62 - i * 0.11 + 0.4), wood, "WoodPlanks")
		end
	end)
	-- Canopy above
	canopy(b, V(0, 9.4, 0.8), V(5.4, 3.0, 5.4), { Pal.Leaf, C(88, 160, 70), C(60, 128, 56) }, 7)
	-- Swing
	for _, x in ipairs({ 1.6, 2.4 }) do
		b:Rod(V(x, 4.4, -2.0), V(x, 1.4, -2.0), 0.05, C(200, 180, 140), "Fabric")
	end
	b:Box(V(1.1, 0.14, 0.45), CF(2.0, 1.35, -2.0), C(200, 60, 60), "WoodPlanks")
end

recipes.windmill = function(b)
	local wall, roofC, wood = C(240, 232, 214), C(150, 70, 52), C(120, 84, 56)
	b:Disc(CF(0, 0.2, 0.8), 7.4, 0.4, C(150, 146, 140), "Cobblestone", SOLID)
	-- Tapered tower
	local tiers = { { 6.0, 3.0 }, { 5.3, 3.0 }, { 4.6, 3.0 } }
	local y = 0.4
	for i, t in ipairs(tiers) do
		b:CylY(t[2], t[1], CF(0, y + t[2] / 2, 0.8), wall, "SmoothPlastic", i == 1 and SOLID or nil)
		b:CylY(0.25, t[1] + 0.2, CF(0, y + t[2], 0.8), wood, "WoodPlanks")
		y += t[2]
	end
	-- Cap
	b:Cone(CF(0, y, 0.8), 2.8, 5.0, 0.5, 4, roofC, "Slate")
	b:Accent(b:Ball(0.45, CF(0, y + 2.95, 0.8), Pal.Gold, "Metal"))
	-- Door and windows
	b:Box(V(1.3, 2.0, 0.3), CF(0, 1.4, -2.15), C(90, 56, 36), "WoodPlanks")
	b:CylZ(0.3, 1.3, CF(0, 2.4, -2.15), C(90, 56, 36), "WoodPlanks")
	b:Detail(function()
		b:Box(V(0.8, 0.9, 0.2), CF(0, 5.2, -1.8), C(150, 210, 240), "Glass")
		b:Box(V(0.7, 0.8, 0.2), CF(-1.6, 4.2, -1.4) * ANG(0, rad(35), 0), C(150, 210, 240), "Glass")
		b:Box(V(0.7, 0.8, 0.2), CF(1.6, 4.2, -1.4) * ANG(0, rad(-35), 0), C(150, 210, 240), "Glass")
	end)
	-- Hub and four lattice sails (an X, so the span stays inside the spot)
	local hub = CF(0, 8.0, -1.7)
	b:CylZ(1.2, 0.9, hub * CF(0, 0, 0.3), wood, "Wood")
	b:Accent(b:Ball(0.6, hub * CF(0, 0, -0.35), Pal.Gold, "Metal"))
	local sails = b:Folder("Sails")
	for i = 0, 3 do
		local a = rad(45 + i * 90)
		local dir = V(math.sin(a), math.cos(a), 0)
		local tip = hub.Position + dir * 4.4
		b:Beam(hub.Position, tip, 0.22, wood, "Wood")
		local mid = hub.Position + dir * 2.7
		b:Box(V(1.15, 3.0, 0.08), CF(mid) * ANG(0, 0, -a) * CF(0.62, 0, -0.08), C(236, 226, 200), "Fabric")
		b:Detail(function()
			b:Box(V(0.08, 3.0, 0.1), CF(mid) * ANG(0, 0, -a) * CF(1.2, 0, -0.06), wood, "Wood")
		end)
	end
	b:Into(b.Model)
	sails:SetAttribute("SpinAxis", "Z")
	-- Balcony
	b:Ring(CF(0, 3.45, 0.8), 3.1, 0.14, wood, "Wood", 12)
	b:Detail(function()
		-- flower boxes
		b:Box(V(1.6, 0.4, 0.5), CF(0, 3.55, -2.45), wood, "WoodPlanks")
		canopy(b, V(0, 3.9, -2.45), V(1.4, 0.45, 0.45), { C(240, 90, 120), C(255, 210, 80) }, 2)
	end)
end

recipes.lighthouse = function(b)
	local red, white = C(214, 52, 52), C(245, 245, 240)
	-- Rocky island
	b:Ellipsoid(V(8.6, 1.6, 8.6), CF(0, 0.3, 0.6), C(120, 114, 108), "Slate", SOLID)
	b:Ellipsoid(V(2.4, 1.8, 2.2), CF(-3.0, 0.5, -1.6), C(132, 126, 118), "Slate")
	b:Ellipsoid(V(2.0, 1.4, 2.0), CF(3.1, 0.4, -1.2), C(110, 104, 98), "Slate")
	b:Disc(CF(0, 1.1, 0.6), 5.2, 0.3, C(170, 164, 150), "Cobblestone")
	-- Striped tapered tower
	local y = 1.25
	for i = 1, 5 do
		local d = 3.8 - i * 0.3
		b:CylY(2.2, d, CF(0, y + 1.1, 0.6), i % 2 == 1 and red or white, "SmoothPlastic", i == 1 and SOLID or nil)
		y += 2.2
	end
	-- Gallery + railing
	b:Disc(CF(0, y + 0.15, 0.6), 3.9, 0.3, C(40, 44, 52), "Metal")
	b:Ring(CF(0, y + 0.85, 0.6), 1.85, 0.1, C(40, 44, 52), "Metal", 12)
	b:Detail(function()
		for i = 0, 5 do
			local a = rad(i * 60)
			b:CylY(0.7, 0.08, CF(math.sin(a) * 1.85, y + 0.6, 0.6 + math.cos(a) * 1.85), C(40, 44, 52), "Metal")
		end
	end)
	-- Lantern room
	b:CylY(1.7, 2.2, CF(0, y + 1.15, 0.6), C(200, 235, 255), "Glass", { Transparency = 0.45 })
	b:Accent(b:Ball(1.1, CF(0, y + 1.15, 0.6), C(255, 236, 150), "Neon"))
	b:Ellipsoid(V(2.5, 1.5, 2.5), CF(0, y + 2.3, 0.6), red, "SmoothPlastic")
	b:CylY(0.6, 0.15, CF(0, y + 3.25, 0.6), C(40, 44, 52), "Metal")
	b:Accent(b:Ball(0.35, CF(0, y + 3.6, 0.6), Pal.Gold, "Metal"))
	-- Door, windows and a little boat
	b:Box(V(1.1, 1.8, 0.3), CF(0, 2.15, -1.12), C(60, 74, 96), "WoodPlanks")
	b:Detail(function()
		for i = 1, 3 do
			b:Box(V(0.55, 0.75, 0.2), CF(0, 2.0 + i * 2.2, -1.25 + i * 0.13), C(255, 230, 150), "Neon")
		end
	end)
	b:Ellipsoid(V(1.4, 0.55, 2.6), CF(-3.2, 0.95, 2.6) * ANG(0, rad(20), 0), C(230, 190, 80), "WoodPlanks")
	b:Rod(V(-3.2, 1.0, 2.6), V(-3.2, 2.8, 2.6), 0.08, Pal.WoodDark, "Wood")
	b:Wedge(V(0.06, 1.4, 0.9), CF(-3.2, 2.0, 2.15), white, "Fabric")
end

recipes.mini_castle = function(b)
	local stone, dark, roofC = C(176, 170, 162), C(120, 114, 108), C(70, 80, 150)
	plate(b, 9.4, 9.4, 0.3, C(110, 150, 80), "Grass")
	local h = 4.2
	-- Walls (front with gate, sides, back)
	local half = 3.45
	b:Box(V(2.0, h, 0.8), CF(-2.4, 0.3 + h / 2, -half), stone, "Cobblestone", SOLID)
	b:Box(V(2.0, h, 0.8), CF(2.4, 0.3 + h / 2, -half), stone, "Cobblestone", SOLID)
	b:Box(V(2.8, 1.3, 0.8), CF(0, 0.3 + h - 0.65, -half), stone, "Cobblestone")
	b:Box(V(2.6, h - 1.3, 0.1), CF(0, 0.3 + (h - 1.3) / 2, -half - 0.05), C(40, 30, 28), "SmoothPlastic")
	b:Detail(function()
		for i = -2, 2 do
			b:Box(V(0.12, h - 1.4, 0.12), CF(i * 0.5, 0.3 + (h - 1.3) / 2, -half - 0.15), Pal.Iron, "Metal")
		end
		for j = 1, 3 do
			b:Box(V(2.6, 0.12, 0.12), CF(0, 0.3 + j * 0.75, -half - 0.15), Pal.Iron, "Metal")
		end
	end)
	b:Box(V(7.2, h, 0.8), CF(0, 0.3 + h / 2, half), stone, "Cobblestone", SOLID)
	b:Box(V(0.8, h, 7.2), CF(-half, 0.3 + h / 2, 0), stone, "Cobblestone", SOLID)
	b:Box(V(0.8, h, 7.2), CF(half, 0.3 + h / 2, 0), stone, "Cobblestone", SOLID)
	crenels(b, CF(-2.4, 0.3 + h, -half), 2.0, stone, "Cobblestone")
	crenels(b, CF(2.4, 0.3 + h, -half), 2.0, stone, "Cobblestone")
	crenels(b, CF(0, 0.3 + h, half), 5.6, stone, "Cobblestone")
	crenels(b, CF(-half, 0.3 + h, 0) * ANG(0, math.pi / 2, 0), 5.6, stone, "Cobblestone")
	crenels(b, CF(half, 0.3 + h, 0) * ANG(0, math.pi / 2, 0), 5.6, stone, "Cobblestone")
	-- Corner towers with cone roofs and flags
	for _, x in ipairs({ -half, half }) do
		for _, z in ipairs({ -half, half }) do
			b:CylY(6.2, 2.0, CF(x, 0.3 + 3.1, z), dark, "Cobblestone", SOLID)
			b:CylY(0.35, 2.3, CF(x, 0.3 + 6.3, z), stone, "Cobblestone")
			b:Cone(CF(x, 6.75, z), 2.6, 2.4, 0.2, 4, roofC, "Slate")
			b:Rod(V(x, 9.3, z), V(x, 10.6, z), 0.08, Pal.Iron, "Metal")
			b:Accent(b:Box(V(0.9, 0.5, 0.05), CF(x + 0.45, 10.3, z), C(220, 50, 60), "Fabric"))
			b:Detail(function()
				b:Box(V(0.3, 0.7, 0.1), CF(x, 4.2, z - 1.1), C(40, 30, 28), "SmoothPlastic")
			end)
		end
	end
	-- Keep
	b:Box(V(3.4, 6.0, 3.0), CF(0, 0.3 + 3.0, 1.2), stone, "Cobblestone", SOLID)
	b:Box(V(3.7, 0.3, 3.3), CF(0, 6.45, 1.2), dark, "Cobblestone")
	crenels(b, CF(0, 6.6, -0.3), 3.6, stone, "Cobblestone")
	crenels(b, CF(0, 6.6, 2.7), 3.6, stone, "Cobblestone")
	b:CylY(2.4, 1.6, CF(0, 0.3 + 6.0 + 1.2, 1.2), dark, "Cobblestone")
	b:Cone(CF(0, 8.7, 1.2), 2.6, 2.1, 0.2, 4, roofC, "Slate")
	b:Rod(V(0, 11.2, 1.2), V(0, 12.8, 1.2), 0.1, Pal.Iron, "Metal")
	b:Accent(b:Box(V(1.3, 0.7, 0.06), CF(0.65, 12.4, 1.2), Pal.Gold, "Fabric"))
	-- Banners and glowing windows
	b:Detail(function()
		for _, x in ipairs({ -2.4, 2.4 }) do
			b:Box(V(0.9, 1.6, 0.06), CF(x, 3.2, -half - 0.44), roofC, "Fabric")
			b:Accent(b:Box(V(0.4, 0.4, 0.04), CF(x, 3.4, -half - 0.48), Pal.Gold, "Neon"))
		end
		b:Box(V(0.6, 0.9, 0.1), CF(0, 5.2, -0.32), C(255, 210, 120), "Neon")
	end)
	-- Moat bridge
	b:Box(V(2.6, 0.2, 1.1), CF(0, 0.32, -4.4), C(140, 100, 64), "WoodPlanks")
end

------------------------------------------------------------------------------------------------
-- PLANTS (Small)
------------------------------------------------------------------------------------------------
recipes.flower_bed = function(b)
	local wood = C(150, 104, 64)
	b:Box(V(3.0, 0.55, 1.6), CF(0, 0.275, 0), wood, "WoodPlanks")
	b:Box(V(2.8, 0.1, 1.4), CF(0, 0.56, 0), C(78, 54, 40), "Ground")
	for _, x in ipairs({ -1.55, 1.55 }) do
		b:Box(V(0.14, 0.7, 0.14), CF(x, 0.35, -0.82), Pal.WoodDark, "Wood")
		b:Box(V(0.14, 0.7, 0.14), CF(x, 0.35, 0.82), Pal.WoodDark, "Wood")
	end
	local colors = { C(255, 90, 120), C(255, 210, 70), C(170, 110, 255), C(255, 150, 60), C(250, 250, 255) }
	local i = 0
	for row = 0, 1 do
		for col = 0, 4 do
			i += 1
			local x = -1.1 + col * 0.55 + row * 0.25
			local z = -0.35 + row * 0.62
			local h = 0.55 + ((i * 37) % 5) * 0.06
			b:CylY(h, 0.08, CF(x, 0.6 + h / 2, z), Pal.Leaf, "SmoothPlastic")
			b:Ball(0.36, CF(x, 0.62 + h, z), colors[(i - 1) % #colors + 1], "SmoothPlastic")
			b:Detail(function()
				b:Ball(0.14, CF(x, 0.66 + h, z - 0.12), C(255, 230, 120), "SmoothPlastic")
			end)
		end
	end
	canopy(b, V(0, 0.75, 0.05), V(2.6, 0.4, 1.1), { Pal.Leaf }, 1)
end

recipes.oak_tree = function(b)
	local bark = C(112, 80, 54)
	b:Disc(CF(0, 0.06, 0), 1.7, 0.12, C(96, 150, 70), "Grass")
	b:CylY(3.2, 0.75, CF(0, 1.6, 0), bark, "Wood")
	b:CylY(1.6, 0.55, CF(0.05, 3.9, 0), bark, "Wood")
	for i, dir in ipairs({ V(-0.9, 1.0, 0.1), V(0.85, 1.1, -0.2), V(0.1, 1.0, 0.6) }) do
		local from = V(0, 2.8 + i * 0.35, 0)
		b:Rod(from, from + dir, 0.28, bark, "Wood")
	end
	for _, a in ipairs({ 0, 120, 240 }) do
		local r = rad(a)
		b:Wedge(V(0.3, 0.45, 0.6), CF(math.sin(r) * 0.42, 0.22, math.cos(r) * 0.42) * ANG(0, r + math.pi, 0), bark, "Wood")
	end
	canopy(b, V(0, 5.3, 0), V(2.4, 2.1, 2.0), { C(76, 146, 60), C(62, 128, 52), C(96, 164, 70) }, 7)
	b:Detail(function()
		for _, p in ipairs({ V(0.9, 5.0, -1.0), V(-1.0, 5.6, -0.8), V(0.3, 6.3, -0.9) }) do
			b:Ball(0.22, CF(p), C(200, 140, 70), "SmoothPlastic") -- acorns
		end
	end)
end

recipes.hedge_arch = function(b)
	local hedge = C(66, 128, 56)
	for _, x in ipairs({ -1.18, 1.18 }) do
		b:Box(V(0.75, 0.3, 0.75), CF(x, 0.15, 0), C(150, 146, 140), "Slate")
		b:Box(V(0.85, 3.0, 0.85), CF(x, 1.8, 0), hedge, "Grass")
	end
	local n = 7
	for i = 0, n - 1 do
		local a = math.pi * (i + 0.5) / n
		local x, y = math.cos(a) * 1.18, 3.3 + math.sin(a) * 1.1
		b:Ellipsoid(V(0.95, 0.95, 0.85), CF(x, y, 0), i % 2 == 0 and hedge or C(80, 144, 64), "Grass")
	end
	b:Detail(function()
		local colors = { C(255, 120, 160), C(255, 255, 255), C(255, 200, 80) }
		local spots = { V(-1.45, 2.4, -0.43), V(1.4, 3.1, -0.43), V(-0.7, 4.3, -0.4), V(0.6, 4.4, -0.4), V(0, 4.55, -0.35), V(-1.4, 1.2, -0.43), V(1.45, 1.6, -0.43) }
		for i, p in ipairs(spots) do
			b:Ball(0.26, CF(p), colors[(i - 1) % #colors + 1], "SmoothPlastic")
		end
	end)
	-- Stepping stones under the arch
	for i = -1, 1 do
		b:Disc(CF(i * 0.05, 0.05, i * 0.55), 0.6, 0.1, C(170, 166, 160), "Slate")
	end
end

recipes.palm_tree = function(b)
	local trunk = C(164, 122, 80)
	b:Ellipsoid(V(1.8, 0.4, 1.5), CF(0, 0.1, 0), Pal.Sand, "Sand")
	local pos = V(0, 0.2, 0.15)
	local segs = 7
	local top = pos
	for i = 1, segs do
		local nxt = V(math.sin(i * 0.22) * 0.25, 0.2 + i * 0.85, 0.15 - i * 0.03)
		b:Rod(top, nxt, 0.62 - i * 0.03, i % 2 == 0 and trunk or trunk:Lerp(Color3.new(0, 0, 0), 0.12), "Wood")
		top = nxt
	end
	-- Fronds: drooping flattened leaves in a star
	local leaf = C(70, 150, 60)
	for i = 0, 6 do
		local a = rad(i * (360 / 7) + 10)
		local dir = V(math.sin(a), 0, math.cos(a))
		local reach = 1.35
		local mid = top + dir * reach * 0.55 + V(0, 0.15, 0)
		local tip = top + dir * reach + V(0, -0.65, 0)
		b:Ellipsoid(V(0.55, 0.1, 1.15), CFrame.lookAt(mid, tip), i % 2 == 0 and leaf or C(90, 168, 70), "Grass")
		b:Ellipsoid(V(0.4, 0.08, 0.9), CFrame.lookAt(tip:Lerp(mid, 0.3), tip + dir * 0.4 + V(0, -0.5, 0)), leaf, "Grass")
	end
	for i = 0, 2 do
		local a = rad(i * 120 + 40)
		b:Ball(0.36, CF(top + V(math.sin(a) * 0.32, -0.3, math.cos(a) * 0.32)), C(120, 84, 46), "SmoothPlastic")
	end
	b:Detail(function()
		b:Ellipsoid(V(0.7, 0.3, 0.6), CF(0.75, 0.25, -0.45), C(240, 210, 160), "Sand")
		b:Ball(0.3, CF(-0.6, 0.3, -0.5), C(250, 240, 220), "SmoothPlastic") -- shell
	end)
end

recipes.cherry_blossom = function(b)
	local bark = C(84, 56, 48)
	b:Ring(CF(0, 0.12, 0), 0.72, 0.24, C(170, 166, 160), "Slate", 10)
	b:Disc(CF(0, 0.08, 0), 1.4, 0.1, C(96, 150, 70), "Grass")
	b:Rod(V(0, 0, 0), V(0.15, 2.2, 0), 0.6, bark, "Wood")
	b:Rod(V(0.15, 2.2, 0), V(-0.55, 3.6, 0.1), 0.42, bark, "Wood")
	b:Rod(V(0.15, 2.2, 0), V(0.75, 3.9, -0.2), 0.38, bark, "Wood")
	b:Rod(V(-0.55, 3.6, 0.1), V(-1.2, 4.4, 0.3), 0.22, bark, "Wood")
	b:Rod(V(0.75, 3.9, -0.2), V(1.25, 4.7, 0.2), 0.2, bark, "Wood")
	local pinks = { C(255, 182, 210), C(250, 150, 190), C(255, 214, 230) }
	canopy(b, V(0, 4.9, 0), V(2.5, 1.7, 2.0), pinks, 7)
	b:Detail(function()
		for i, p in ipairs({ V(-0.9, 0.11, -0.6), V(0.7, 0.11, -0.7), V(1.2, 0.11, 0.4), V(-1.2, 0.11, 0.5), V(0.1, 0.11, -0.85) }) do
			b:Disc(CF(p) * ANG(0, i, 0), 0.32, 0.04, pinks[(i - 1) % 3 + 1], "SmoothPlastic")
		end
		-- a paper lantern
		b:Rod(V(0.9, 4.0, -0.6), V(0.9, 3.4, -0.6), 0.04, C(40, 30, 30), "SmoothPlastic")
		b:Accent(b:Ellipsoid(V(0.5, 0.6, 0.5), CF(0.9, 3.1, -0.6), C(255, 110, 90), "Neon"))
	end)
end

recipes.giant_mushroom = function(b)
	local stem, cap = C(244, 236, 220), C(214, 44, 52)
	b:Disc(CF(0, 0.06, 0), 1.7, 0.12, C(80, 130, 64), "Grass")
	b:CylY(0.6, 1.0, CF(0, 0.3, 0), stem, "SmoothPlastic")
	b:CylY(3.2, 0.8, CF(0, 2.1, 0), stem, "SmoothPlastic")
	b:Ring(CF(0, 2.6, 0), 0.45, 0.18, C(250, 246, 236), "SmoothPlastic", 8) -- skirt
	b:Ellipsoid(V(3.5, 1.9, 2.9), CF(0, 4.25, 0), cap, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V(3.2, 0.3, 2.6), CF(0, 3.55, 0), C(255, 214, 150), "Neon")) -- glowing gills
	-- White spots on the cap surface (cap: ellipsoid 3.5 x 1.9 x 2.9 centred at y 4.25).
	for _, xz in ipairs({ { 0, 0 }, { -0.95, -0.6 }, { 1.0, -0.45 }, { -0.5, 0.8 }, { 0.75, 0.85 }, { -1.4, 0.2 }, { 1.4, 0.05 }, { 0.1, -1.1 } }) do
		local x, z = xz[1], xz[2]
		local y = 4.25 + 0.95 * math.sqrt(math.max(0, 1 - (x / 1.75) ^ 2 - (z / 1.45) ^ 2))
		b:Ellipsoid(V(0.55, 0.2, 0.55), CF(x, y, z) * ANG(rad(z * 28), 0, rad(-x * 28)), C(255, 250, 240), "SmoothPlastic")
	end
	-- Little mushrooms at the foot
	for i, x in ipairs({ -1.1, 1.15 }) do
		local h = 0.5 + i * 0.12
		b:CylY(h, 0.22, CF(x, h / 2, -0.4), stem, "SmoothPlastic")
		b:Ellipsoid(V(0.65, 0.36, 0.6), CF(x, h + 0.08, -0.4), i == 1 and C(255, 170, 60) or cap, "SmoothPlastic")
	end
end

------------------------------------------------------------------------------------------------
-- LIGHTING (Small, one PointLight each)
------------------------------------------------------------------------------------------------
recipes.lantern_post = function(b)
	local iron = C(44, 48, 56)
	b:CylY(0.35, 1.1, CF(0, 0.175, 0), iron, "Metal")
	b:CylY(0.5, 0.7, CF(0, 0.6, 0), iron, "Metal")
	b:CylY(4.2, 0.28, CF(0, 2.95, 0), iron, "Metal")
	b:Ring(CF(0, 1.2, 0), 0.22, 0.12, Pal.Gold, "Metal", 6)
	b:Box(V(0.75, 0.15, 0.75), CF(0, 5.08, 0), iron, "Metal")
	b:Box(V(0.62, 0.85, 0.62), CF(0, 5.6, 0), C(255, 236, 170), "Glass", { Transparency = 0.25 })
	local core = b:Accent(b:Ball(0.42, CF(0, 5.6, 0), C(255, 220, 140), "Neon"))
	for _, x in ipairs({ -0.33, 0.33 }) do
		for _, z in ipairs({ -0.33, 0.33 }) do
			b:Box(V(0.07, 0.9, 0.07), CF(x, 5.6, z), iron, "Metal")
		end
	end
	b:Cone(CF(0, 6.05, 0), 0.6, 0.95, 0.15, 3, iron, "Metal")
	b:Ball(0.2, CF(0, 6.72, 0), Pal.Gold, "Metal")
	b:Detail(function()
		-- a hanging flower basket on a small arm
		b:Beam(V(0, 4.1, 0), V(0.95, 4.1, 0), 0.08, iron, "Metal")
		b:Ellipsoid(V(0.55, 0.4, 0.55), CF(0.95, 3.75, 0), C(110, 76, 50), "Wood")
		canopy(b, V(0.95, 3.95, 0), V(0.55, 0.3, 0.55), { C(255, 120, 160) }, 1)
	end)
	b:Light(core, C(255, 214, 150), 14, 1.1)
end

recipes.brazier = function(b)
	local iron = C(52, 50, 52)
	b:Disc(CF(0, 0.06, 0), 1.6, 0.12, C(110, 104, 98), "Slate")
	for i = 0, 2 do
		local a = rad(i * 120)
		b:Rod(V(math.sin(a) * 0.62, 0.1, math.cos(a) * 0.62), V(math.sin(a) * 0.3, 1.9, math.cos(a) * 0.3), 0.16, iron, "Metal")
	end
	b:Ring(CF(0, 1.0, 0), 0.42, 0.1, iron, "Metal", 6)
	b:CylY(0.25, 0.5, CF(0, 1.95, 0), iron, "Metal")
	b:Cone(CF(0, 2.0, 0), 0.7, 0.6, 1.45, 3, iron, "Metal")
	b:Ring(CF(0, 2.72, 0), 0.72, 0.14, Pal.Bronze, "Metal", 10)
	for i = 0, 4 do
		local a = rad(i * 72)
		b:Ball(0.36, CF(math.sin(a) * 0.38, 2.68, math.cos(a) * 0.38), C(40, 26, 22), "Slate")
	end
	local flame = b:Accent(b:Ellipsoid(V(1.0, 0.9, 1.0), CF(0, 3.05, 0), C(255, 110, 30), "Neon"))
	b:Accent(b:Ellipsoid(V(0.4, 1.3, 0.4), CF(-0.12, 3.6, 0.1) * ANG(0, 0, rad(12)), C(255, 150, 40), "Neon"))
	b:Accent(b:Ellipsoid(V(0.45, 0.9, 0.45), CF(0.05, 3.45, -0.05), C(255, 220, 90), "Neon"))
	b:Detail(function()
		b:Accent(b:Ellipsoid(V(0.35, 0.6, 0.35), CF(-0.28, 3.2, 0.2), C(255, 160, 40), "Neon"))
		b:Accent(b:Ellipsoid(V(0.3, 0.5, 0.3), CF(0.3, 3.1, 0.18), C(255, 160, 40), "Neon"))
	end)
	b:Light(flame, C(255, 150, 70), 16, 1.4)
end

recipes.string_lights = function(b)
	local wood = C(120, 86, 56)
	for _, x in ipairs({ -1.38, 1.38 }) do
		b:Box(V(0.42, 0.3, 0.42), CF(x, 0.15, 0), C(140, 136, 130), "Slate")
		b:Box(V(0.26, 4.4, 0.26), CF(x, 2.5, 0), wood, "WoodPlanks")
		b:Ball(0.32, CF(x, 4.75, 0), wood, "Wood")
	end
	b:Box(V(3.0, 0.2, 0.2), CF(0, 4.55, 0), wood, "WoodPlanks")
	-- Sagging wire with bulbs
	local colors = { C(255, 90, 90), C(255, 220, 90), C(90, 220, 140), C(90, 170, 255), C(230, 120, 255) }
	local n = 9
	local prev: Vector3? = nil
	local center: BasePart? = nil
	for i = 0, n - 1 do
		local t = i / (n - 1)
		local x = -1.3 + t * 2.6
		local y = 4.4 - math.sin(t * math.pi) * 0.75
		local p = V(x, y, -0.05)
		if prev then
			b:Rod(prev, p, 0.04, C(30, 30, 34), "SmoothPlastic")
		end
		prev = p
		if i > 0 and i < n - 1 then
			local bulb = b:Accent(b:Ellipsoid(V(0.2, 0.3, 0.2), CF(p + V(0, -0.2, 0)), colors[(i - 1) % #colors + 1], "Neon"))
			if i == 4 then
				center = bulb
			end
		end
	end
	-- Lower garland
	b:Detail(function()
		for i = 0, 4 do
			local t = i / 4
			b:Accent(b:Ball(0.16, CF(-1.25 + t * 2.5, 3.35 - math.sin(t * math.pi) * 0.35, -0.05), colors[(i + 2) % #colors + 1], "Neon"))
		end
	end)
	b:Detail(function()
		b:Box(V(1.6, 0.5, 0.1), CF(0, 4.95, -0.1), C(250, 240, 220), "WoodPlanks")
	end)
	if center then
		b:Light(center, C(255, 220, 170), 14, 0.9)
	end
end

recipes.neon_paw_sign = function(b)
	local frame, back = C(40, 42, 52), C(22, 20, 34)
	for _, x in ipairs({ -1.2, 1.2 }) do
		b:Box(V(0.5, 0.3, 0.6), CF(x, 0.15, 0), frame, "Metal")
		b:Box(V(0.2, 2.2, 0.2), CF(x, 1.4, 0.1), frame, "Metal")
	end
	b:Box(V(3.0, 2.7, 0.22), CF(0, 3.65, 0.1), back, "SmoothPlastic")
	b:Box(V(3.2, 0.16, 0.3), CF(0, 5.06, 0.1), frame, "Metal")
	b:Box(V(3.2, 0.16, 0.3), CF(0, 2.24, 0.1), frame, "Metal")
	-- Neon border
	b:Accent(b:Box(V(2.8, 0.08, 0.06), CF(0, 4.88, -0.04), C(80, 230, 255), "Neon"))
	b:Accent(b:Box(V(2.8, 0.08, 0.06), CF(0, 2.42, -0.04), C(80, 230, 255), "Neon"))
	b:Accent(b:Box(V(0.08, 2.46, 0.06), CF(-1.4, 3.65, -0.04), C(80, 230, 255), "Neon"))
	b:Accent(b:Box(V(0.08, 2.46, 0.06), CF(1.4, 3.65, -0.04), C(80, 230, 255), "Neon"))
	-- Paw print
	local pink = C(255, 80, 190)
	local pad = b:Accent(b:Ellipsoid(V(1.2, 0.95, 0.12), CF(0, 3.3, -0.06), pink, "Neon"))
	for i, p in ipairs({ V(-0.62, 3.95, -0.06), V(-0.22, 4.28, -0.06), V(0.22, 4.28, -0.06), V(0.62, 3.95, -0.06) }) do
		b:Accent(b:Ellipsoid(V(0.42, 0.55, 0.12), CF(p) * ANG(0, 0, rad((i - 2.5) * -14)), pink, "Neon"))
	end
	b:Detail(function()
		-- little cables and a bolt row
		for _, x in ipairs({ -0.8, 0, 0.8 }) do
			b:Ball(0.1, CF(x, 2.32, -0.05), C(200, 200, 210), "Metal")
		end
	end)
	b:Light(pad, C(255, 120, 210), 13, 1.0)
end

recipes.crystal_lamp = function(b)
	local rock, cyan = C(84, 82, 96), C(90, 220, 255)
	b:Ellipsoid(V(2.4, 0.9, 1.7), CF(0, 0.35, 0), rock, "Slate")
	b:Ellipsoid(V(1.2, 0.8, 1.0), CF(-0.9, 0.45, -0.2), C(100, 96, 112), "Slate")
	b:CylY(1.4, 0.9, CF(0, 1.3, 0), C(60, 58, 70), "Slate")
	b:Ring(CF(0, 1.95, 0), 0.6, 0.16, Pal.Silver, "Metal", 8)
	local core = b:Accent(b:Box(V(0.32, 2.5, 0.32), CF(0, 3.25, 0), C(200, 250, 255), "Neon"))
	b:Prism(CF(0, 1.95, 0), 0.75, 2.4, 0.7, cyan, "Glass", { Transparency = 0.25 })
	b:Prism(CF(-0.55, 1.9, 0.1) * ANG(0, 0, rad(18)), 0.45, 1.5, 0.45, C(140, 120, 255), "Glass", { Transparency = 0.2 })
	b:Prism(CF(0.55, 1.9, -0.05) * ANG(0, rad(30), rad(-20)), 0.4, 1.3, 0.4, cyan, "Glass", { Transparency = 0.2 })
	b:Detail(function()
		for i, p in ipairs({ V(0.8, 0.75, -0.4), V(-0.4, 0.75, -0.55), V(0.95, 0.6, 0.45) }) do
			b:Prism(CF(p) * ANG(rad(i * 9), rad(i * 40), rad(-i * 12)), 0.22, 0.45, 0.22, i == 2 and C(140, 120, 255) or cyan, "Glass")
		end
	end)
	b:Light(core, cyan, 15, 1.2)
end

recipes.spotlight_tower = function(b)
	local steel, yellow = C(120, 128, 138), C(240, 196, 40)
	local hx, hz = 1.25, 0.7
	b:Box(V(2.9, 0.3, 1.7), CF(0, 0.15, 0), C(110, 110, 114), "Concrete")
	local corners = { V(-hx, 0.3, -hz), V(hx, 0.3, -hz), V(hx, 0.3, hz), V(-hx, 0.3, hz) }
	local topY = 6.6
	local tops = {}
	for i, c in ipairs(corners) do
		local t = V(c.X * 0.55, topY, c.Z * 0.6)
		tops[i] = t
		b:Rod(c, t, 0.18, steel, "Metal")
	end
	b:Detail(function()
		for _, level in ipairs({ 2.2, 4.4 }) do
			local f = (level - 0.3) / (topY - 0.3)
			for i = 1, 4 do
				local a, c = corners[i]:Lerp(tops[i], f), corners[i % 4 + 1]:Lerp(tops[i % 4 + 1], f)
				b:Rod(a, c, 0.1, steel, "Metal")
			end
			local a, c = corners[1]:Lerp(tops[1], f - 0.3), corners[2]:Lerp(tops[2], f)
			b:Rod(a, c, 0.08, steel, "Metal")
		end
	end)
	b:Box(V(2.2, 0.2, 1.4), CF(0, topY + 0.1, 0), yellow, "Metal")
	b:Box(V(0.1, 0.5, 1.4), CF(-1.1, topY + 0.45, 0), yellow, "Metal")
	b:Box(V(0.1, 0.5, 1.4), CF(1.1, topY + 0.45, 0), yellow, "Metal")
	-- Lamp head on a yoke, tilted up towards the yard
	b:Box(V(0.2, 0.9, 0.2), CF(-0.62, topY + 0.65, 0), C(50, 54, 60), "Metal")
	b:Box(V(0.2, 0.9, 0.2), CF(0.62, topY + 0.65, 0), C(50, 54, 60), "Metal")
	local head = CF(0, topY + 1.15, -0.05) * ANG(rad(25), 0, 0)
	b:CylZ(1.2, 1.15, head, C(50, 54, 60), "Metal")
	local lens = b:Accent(b:CylZ(0.1, 0.95, head * CF(0, 0, -0.62), C(255, 250, 220), "Neon"))
	b:Detail(function()
		b:Ring(head * CF(0, 0, -0.6) * ANG(math.pi / 2, 0, 0), 0.55, 0.1, yellow, "Metal", 10)
		b:Accent(b:Ball(0.22, CF(0, topY + 1.85, 0.35), C(255, 60, 60), "Neon")) -- beacon
	end)
	b:Light(lens, C(255, 246, 220), 18, 1.3)
end

------------------------------------------------------------------------------------------------
-- DECOR (Small)
------------------------------------------------------------------------------------------------
recipes.signpost = function(b)
	local wood = C(140, 98, 60)
	b:Ellipsoid(V(1.0, 0.45, 0.9), CF(0, 0.15, 0), C(140, 136, 130), "Slate")
	b:CylY(5.0, 0.32, CF(0, 2.5, 0), Pal.WoodDark, "Wood")
	local signs = {
		{ y = 4.55, yaw = 0, color = C(220, 70, 60), dir = 1 },
		{ y = 3.9, yaw = 25, color = C(60, 150, 220), dir = -1 },
		{ y = 3.3, yaw = -20, color = C(240, 190, 60), dir = 1 },
	}
	for _, s in ipairs(signs) do
		local cf = CF(0, s.y, 0) * ANG(0, rad(s.yaw), 0)
		b:Box(V(1.7, 0.5, 0.12), cf * CF(s.dir * 0.75, 0, -0.18), s.color, "WoodPlanks")
		b:Wedge(V(0.12, 0.5, 0.4), cf * CF(s.dir * 1.8, 0, -0.18) * ANG(0, s.dir * math.pi / 2, 0), s.color, "WoodPlanks")
		b:Detail(function()
			b:Box(V(1.2, 0.12, 0.04), cf * CF(s.dir * 0.75, 0, -0.26), C(250, 245, 230), "SmoothPlastic")
		end)
	end
	-- Paw plate and a cap
	b:Ball(0.4, CF(0, 5.1, 0), wood, "Wood")
	b:Detail(function()
		b:Ellipsoid(V(0.35, 0.28, 0.06), CF(0, 1.7, -0.17), Pal.Bone, "SmoothPlastic")
		for i = -1, 1 do
			b:Ball(0.13, CF(i * 0.14, 1.92 + (i == 0 and 0.05 or 0), -0.17), Pal.Bone, "SmoothPlastic")
		end
	end)
	b:Detail(function()
		canopy(b, V(0.35, 0.35, -0.3), V(0.6, 0.35, 0.5), { Pal.Leaf, C(255, 210, 80) }, 2)
	end)
end

recipes.bone_pile = function(b)
	b:Ellipsoid(V(3.0, 0.55, 1.7), CF(0, 0.1, 0), C(120, 88, 60), "Ground")
	local rows: { { Cf: CFrame, Len: number } } = {
		{ Cf = CF(-0.6, 0.38, -0.25) * ANG(0, rad(15), 0), Len = 1.4 },
		{ Cf = CF(0.55, 0.4, 0.2) * ANG(0, rad(-25), 0), Len = 1.5 },
		{ Cf = CF(0.1, 0.62, -0.1) * ANG(0, rad(65), rad(8)), Len = 1.3 },
		{ Cf = CF(-0.2, 0.85, 0.15) * ANG(0, rad(-5), rad(-10)), Len = 1.2 },
		{ Cf = CF(0.9, 0.75, -0.25) * ANG(0, rad(40), rad(25)), Len = 0.9 },
	}
	for _, r in ipairs(rows) do
		bone(b, r.Cf, r.Len, 0.24, Pal.Bone)
	end
	b:Detail(function()
		-- the golden one on top
		bone(b, CF(-0.1, 1.1, -0.05) * ANG(0, rad(30), rad(15)), 0.9, 0.22, Pal.Gold, "Metal")
		b:Ellipsoid(V(0.5, 0.35, 0.4), CF(-1.15, 0.3, 0.35), C(110, 80, 56), "Ground")
	end)
end

recipes.bench_set = function(b)
	local wood, iron = C(170, 112, 62), C(44, 46, 54)
	for _, x in ipairs({ -1.35, 1.35 }) do
		b:Box(V(0.14, 1.0, 1.1), CF(x, 0.5, 0.05), iron, "Metal")
		b:Box(V(0.14, 0.9, 0.12), CF(x, 1.35, 0.55) * ANG(rad(-10), 0, 0), iron, "Metal")
		b:Box(V(0.14, 0.12, 0.9), CF(x, 1.25, 0.05), iron, "Metal") -- armrest
	end
	for i = 0, 2 do
		b:Box(V(3.0, 0.1, 0.3), CF(0, 0.92, -0.35 + i * 0.34), wood, "WoodPlanks")
	end
	for i = 0, 1 do
		b:Box(V(3.0, 0.28, 0.08), CF(0, 1.3 + i * 0.4, 0.58 + i * 0.07) * ANG(rad(-10), 0, 0), wood, "WoodPlanks")
	end
	b:Detail(function()
		-- a dog bowl, a newspaper and a little sign
		b:CylY(0.25, 0.7, CF(1.1, 0.12, -0.65), C(220, 70, 70), "SmoothPlastic")
		b:CylY(0.06, 0.55, CF(1.1, 0.24, -0.65), C(140, 90, 50), "SmoothPlastic")
		b:Box(V(0.6, 0.06, 0.45), CF(-0.6, 0.99, -0.1) * ANG(0, rad(12), 0), C(235, 235, 225), "SmoothPlastic")
		b:Box(V(0.7, 0.18, 0.04), CF(0, 1.5, 0.66) * ANG(rad(-10), 0, 0), Pal.Gold, "Metal")
	end)
	-- Cushion
	b:Box(V(1.0, 0.16, 0.7), CF(0.6, 1.04, -0.05), C(80, 140, 210), "Fabric")
end

recipes.picnic_set = function(b)
	local wood = C(176, 124, 74)
	-- Table
	for _, x in ipairs({ -0.55, 0.55 }) do
		b:Box(V(0.16, 1.0, 0.16), CF(x, 0.5, 0), Pal.WoodDark, "Wood")
	end
	b:Box(V(1.8, 0.12, 1.2), CF(0, 1.05, 0), wood, "WoodPlanks")
	-- Checkered cloth
	for i = 0, 3 do
		for j = 0, 2 do
			if (i + j) % 2 == 0 then
				b:Box(V(0.45, 0.03, 0.4), CF(-0.68 + i * 0.45, 1.13, -0.4 + j * 0.4), C(220, 60, 60), "Fabric")
			end
		end
	end
	b:Box(V(1.84, 0.02, 1.24), CF(0, 1.12, 0), C(250, 248, 240), "Fabric")
	-- Stools
	for _, x in ipairs({ -1.25, 1.25 }) do
		b:CylY(0.7, 0.18, CF(x, 0.35, 0), Pal.WoodDark, "Wood")
		b:CylY(0.15, 0.7, CF(x, 0.75, 0), wood, "WoodPlanks")
	end
	-- Basket, plates, a cake
	b:Box(V(0.55, 0.32, 0.38), CF(0.35, 1.3, 0.15), C(190, 140, 80), "Fabric")
	b:Rod(V(0.12, 1.45, 0.15), V(0.58, 1.45, 0.15), 0.05, C(150, 100, 60), "Wood")
	b:Detail(function()
		b:CylY(0.04, 0.4, CF(-0.45, 1.16, -0.25), C(250, 250, 255), "SmoothPlastic")
		b:CylY(0.04, 0.4, CF(-0.45, 1.16, 0.3), C(250, 250, 255), "SmoothPlastic")
		b:CylY(0.22, 0.32, CF(-0.45, 1.29, -0.25), C(250, 210, 230), "SmoothPlastic")
		b:Ball(0.12, CF(-0.45, 1.44, -0.25), C(220, 40, 60), "SmoothPlastic")
		bone(b, CF(-0.4, 1.2, 0.3) * ANG(0, rad(30), 0), 0.35, 0.09, Pal.Bone)
	end)
	b:Box(V(2.9, 0.04, 1.6), CF(0, 0.02, 0), C(110, 160, 90), "Fabric")
end

recipes.treasure_chest = function(b)
	local wood, gold = C(130, 78, 44), Pal.Gold
	b:Box(V(2.2, 1.1, 1.3), CF(0, 0.55, 0.1), wood, "WoodPlanks")
	for _, x in ipairs({ -0.9, 0, 0.9 }) do
		b:Box(V(0.16, 1.14, 1.34), CF(x, 0.55, 0.1), Pal.GoldDark, "Metal")
	end
	-- Lid open backwards
	local hinge = CF(0, 1.1, 0.75)
	local lid = hinge * ANG(rad(110), 0, 0)
	b:Box(V(2.2, 0.2, 1.3), lid * CF(0, -0.1, -0.65), wood, "WoodPlanks")
	b:Cyl(2.2, 0.7, lid * CF(0, -0.25, -0.65), wood, "WoodPlanks")
	b:Box(V(0.2, 0.45, 0.14), CF(0, 0.85, -0.58), gold, "Metal")
	-- Treasure heap
	b:Ellipsoid(V(1.9, 0.5, 1.05), CF(0, 1.12, 0.1), gold, "Metal")
	local gems = { C(220, 30, 70), C(40, 200, 120), C(60, 120, 230) }
	for i, p in ipairs({ V(-0.5, 1.35, 0), V(0.45, 1.3, 0.2), V(0.05, 1.42, -0.15) }) do
		b:Accent(b:Gem(0.28, CF(p), gems[i], "Glass"))
	end
	b:Detail(function()
		for i, p in ipairs({ V(-1.25, 0.05, -0.55), V(1.3, 0.05, -0.45), V(1.05, 0.05, -0.75), V(-0.9, 0.05, -0.8) }) do
			b:Disc(CF(p) * ANG(rad(i * 7), i, 0), 0.32, 0.06, gold, "Metal")
		end
		b:Accent(b:Ellipsoid(V(0.35, 0.5, 0.35), CF(0.75, 1.55, 0.1), C(255, 240, 160), "Neon")) -- sparkle
		b:Box(V(0.1, 0.45, 0.04), CF(-0.75, 1.5, 0.2) * ANG(0, 0, rad(30)), C(200, 200, 210), "Metal") -- a dagger
	end)
end

recipes.fountain = function(b)
	local stone, water = C(206, 200, 190), C(90, 180, 235)
	-- Half-round basin against a back wall (fits a path spot)
	b:Box(V(3.0, 0.7, 0.5), CF(0, 0.35, 0.62), stone, "Marble")
	b:Box(V(3.0, 0.7, 1.2), CF(0, 0.35, 0.05), stone, "Marble")
	b:Box(V(2.6, 0.12, 1.0), CF(0, 0.66, 0.05), water, "Glass", { Transparency = 0.25 })
	b:Box(V(3.2, 0.16, 1.5), CF(0, 0.76, 0.1), C(186, 180, 170), "Marble")
	-- Back wall with arch top
	b:Box(V(2.4, 2.4, 0.4), CF(0, 1.9, 0.7), stone, "Marble")
	b:CylZ(0.4, 2.4, CF(0, 3.1, 0.7), stone, "Marble")
	b:Box(V(2.6, 0.18, 0.5), CF(0, 0.92, 0.7), C(186, 180, 170), "Marble")
	-- Dog head spout
	local head = CF(0, 2.35, 0.35)
	b:Ball(0.9, head, C(196, 190, 180), "Marble")
	b:Ellipsoid(V(0.45, 0.38, 0.55), head * CF(0, -0.15, -0.45), C(196, 190, 180), "Marble")
	for _, x in ipairs({ -0.36, 0.36 }) do
		b:Ellipsoid(V(0.22, 0.55, 0.35), head * CF(x, 0.25, 0.05) * ANG(0, 0, rad(x * 30)), C(186, 180, 170), "Marble")
	end
	-- Water arc and splash
	b:Accent(b:Rod(V(0, 2.1, -0.15), V(0, 1.35, -0.5), 0.18, water, "Glass", { Transparency = 0.2 }))
	b:Rod(V(0, 1.35, -0.5), V(0, 0.75, -0.35), 0.16, water, "Glass", { Transparency = 0.25 })
	b:Detail(function()
		b:Ring(CF(0, 0.74, -0.35), 0.28, 0.06, C(220, 245, 255), "Neon", 6)
		b:Accent(b:Ellipsoid(V(0.5, 0.35, 0.5), CF(0, 3.55, 0.6), Pal.Gold, "Metal")) -- crest
		b:Ellipsoid(V(0.4, 0.12, 0.3), CF(-0.9, 0.7, -0.1), C(240, 110, 60), "SmoothPlastic") -- goldfish
	end)
end

------------------------------------------------------------------------------------------------
-- STATUES (Large)
------------------------------------------------------------------------------------------------
local function plinth(b: Builder, w: number, h: number, color: Color3, trim: Color3, mat: string?)
	b:Box(V(w + 1.2, 0.4, w + 1.2), CF(0, 0.2, 0), trim, mat or "Marble", SOLID)
	b:Box(V(w, h, w), CF(0, 0.4 + h / 2, 0), color, mat or "Marble", SOLID)
	b:Box(V(w + 0.4, 0.3, w + 0.4), CF(0, 0.4 + h + 0.15, 0), trim, mat or "Marble")
	return 0.4 + h + 0.3
end

-- A paved square around a statue with round hedges on the corners and two front lamps (neon).
local function plaza(b: Builder, size: number, paving: Color3, edge: Color3, lamps: Color3?)
	b:Box(V(size, 0.12, size), CF(0, 0.06, 0), paving, "Cobblestone")
	b:Box(V(size + 0.3, 0.1, 0.3), CF(0, 0.09, -size / 2), edge, "Slate")
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			b:Ball(1.2, CF(x * (size / 2 - 0.7), 0.6, z * (size / 2 - 0.7)), C(70, 132, 60), "Grass")
		end
	end
	if lamps then
		b:Detail(function()
			for _, x in ipairs({ -1, 1 }) do
				local at = CF(x * (size / 2 - 0.7), 0, -(size / 2 - 2.0))
				b:CylY(2.2, 0.18, at * CF(0, 1.1, 0), C(44, 46, 54), "Metal")
				b:Accent(b:Ball(0.45, at * CF(0, 2.35, 0), lamps, "Neon"))
			end
		end)
	end
end

recipes.bone_obelisk = function(b)
	local stone, trim = C(196, 186, 168), C(150, 142, 128)
	plaza(b, 9.2, C(176, 168, 152), trim, C(255, 220, 150))
	local top = plinth(b, 4.0, 1.2, stone, trim, "Slate")
	-- Tapered shaft
	local y: number = top
	for i = 1, 4 do
		local w = 2.9 - i * 0.34
		b:Box(V(w, 2.4, w), CF(0, y + 1.2, 0), stone, "Slate", i == 1 and SOLID or nil)
		y += 2.4
	end
	-- Gold pyramidion
	local tip = 1.3
	for i = 0, 3 do
		b:Wedge(V(1.54, tip, 0.77), CF(0, y + tip / 2, 0) * ANG(0, i * math.pi / 2, 0) * CF(0, 0, -0.385), Pal.Gold, "Metal")
	end
	b:Accent(b:Ball(0.45, CF(0, y + tip + 0.15, 0), C(255, 236, 150), "Neon"))
	-- Bone relief on the front and sides
	bone(b, CF(0, top + 3.9, -1.32) * ANG(0, 0, math.pi / 2), 2.9, 0.5, Pal.Bone)
	b:Detail(function()
		bone(b, CF(-1.2, top + 2.6, 0) * ANG(0, math.pi / 2, math.pi / 2), 1.8, 0.36, Pal.Bone)
		bone(b, CF(1.2, top + 2.6, 0) * ANG(0, math.pi / 2, math.pi / 2), 1.8, 0.36, Pal.Bone)
		for i = 1, 3 do
			b:Box(V(1.9 - i * 0.25, 0.1, 0.06), CF(0, top + 6.0 + i * 0.6, -1.07 + i * 0.09), trim, "Slate")
		end
	end)
	b:Accent(b:Box(V(2.0, 0.24, 0.06), CF(0, top - 0.25, -2.62), Pal.Gold, "Neon"))
	-- Bones at the foot
	bone(b, CF(-3.0, 0.45, -3.0) * ANG(0, rad(30), 0), 1.4, 0.3, Pal.Bone)
	bone(b, CF(3.0, 0.45, -3.0) * ANG(0, rad(-30), 0), 1.4, 0.3, Pal.Bone)
end

recipes.trophy_column = function(b)
	local marble, trim = C(240, 238, 232), C(200, 196, 188)
	plaza(b, 9.2, C(214, 210, 200), trim, C(255, 230, 160))
	local top = plinth(b, 3.8, 1.1, marble, trim)
	-- Fluted column
	b:CylY(7.0, 2.4, CF(0, top + 3.5, 0), marble, "Marble", SOLID)
	b:Detail(function()
		for i = 0, 7 do
			local a = rad(i * 45)
			b:Box(V(0.14, 6.8, 0.14), CF(math.sin(a) * 1.2, top + 3.5, math.cos(a) * 1.2), trim, "Marble")
		end
	end)
	b:CylY(0.4, 3.0, CF(0, top + 0.2, 0), trim, "Marble")
	b:Box(V(3.3, 0.5, 3.3), CF(0, top + 7.25, 0), trim, "Marble")
	b:Box(V(2.8, 0.35, 2.8), CF(0, top + 7.67, 0), marble, "Marble")
	-- Trophy cup (x1.4)
	local base = top + 7.85
	local k = 1.4
	local gold = Pal.Gold
	b:Box(V(1.2, 0.35, 1.2) * k, CF(0, base + 0.17 * k, 0), Pal.WoodDark, "Wood")
	b:CylY(0.7 * k, 0.3 * k, CF(0, base + 0.7 * k, 0), gold, "Metal")
	b:Cone(CF(0, base + 1.0 * k, 0), 1.7 * k, 0.6 * k, 1.9 * k, 4, gold, "Metal")
	b:Ring(CF(0, base + 2.72 * k, 0), 0.95 * k, 0.14 * k, Pal.GoldDark, "Metal", 12)
	for _, x in ipairs({ -1, 1 }) do
		b:Ring(CF(x * 1.05 * k, base + 2.0 * k, 0) * ANG(math.pi / 2, 0, 0), 0.42 * k, 0.14 * k, gold, "Metal", 8)
	end
	b:Accent(b:Ball(0.5 * k, CF(0, base + 2.0 * k, -0.82 * k), C(255, 240, 160), "Neon"))
	b:Detail(function()
		-- laurel at the cup base and a plaque on the plinth
		for i = 0, 5 do
			local a = rad(-60 + i * 24)
			b:Ellipsoid(V(0.25, 0.12, 0.45) * k, CF(math.sin(a) * 1.1 * k, base + 0.35 * k, -0.55 * k) * ANG(0, a, rad(30)), C(80, 150, 70), "SmoothPlastic")
		end
		b:Box(V(2.0, 0.7, 0.08), CF(0, top - 0.7, -1.96), gold, "Metal")
	end)
end

recipes.knight_dog = function(b)
	local stone, steel = C(170, 172, 178), C(190, 198, 210)
	local k = 2.0
	plaza(b, 9.2, C(150, 146, 140), C(110, 106, 100), C(255, 200, 120))
	local top = plinth(b, 4.6, 1.1, C(150, 146, 140), C(120, 116, 112), "Slate")
	local cf = CF(0, top, 0.2)
	dog(b, cf, k, stone, { Ears = "floppy", Mat = "Slate", Collar = Pal.Gold, Accent = true })
	-- Helmet with plume
	local head = cf * CF(0, 2.45 * k, -0.42 * k)
	b:Ellipsoid(V(1.65, 1.0, 1.65) * (k / 1.35), head * CF(0, 0.47, 0.07), steel, "Metal")
	b:Box(V(0.26, 1.1, 0.26), head * CF(0, 0.96, -1.06), steel, "Metal")
	b:Accent(b:Ellipsoid(V(0.5, 1.5, 2.2), head * CF(0, 1.6, 0.35), C(220, 50, 60), "Fabric"))
	-- Shield at the side, sword planted in front
	b:Ellipsoid(V(0.3, 2.8, 2.2), cf * CF(1.85, 2.0, -0.6) * ANG(0, rad(-20), 0), C(60, 90, 170), "Metal")
	b:Accent(b:Box(V(0.1, 1.4, 0.3), cf * CF(2.0, 2.05, -0.65) * ANG(0, rad(-20), 0), Pal.Gold, "Metal"))
	b:Box(V(0.1, 0.3, 1.1), cf * CF(2.0, 2.2, -0.62) * ANG(0, rad(-20), 0), Pal.Gold, "Metal")
	local hilt = cf * CF(-1.4, 0, -1.85)
	b:Box(V(0.32, 3.6, 0.1), hilt * CF(0, 1.85, 0), steel, "Metal")
	b:Box(V(1.25, 0.24, 0.26), hilt * CF(0, 3.75, 0), Pal.Gold, "Metal")
	b:Box(V(0.24, 0.85, 0.24), hilt * CF(0, 4.25, 0), Pal.Leather, "Fabric")
	b:Ball(0.38, hilt * CF(0, 4.8, 0), Pal.Gold, "Metal")
	b:Detail(function()
		-- a cape and banners on the plinth
		b:Wedge(V(2.0, 2.8, 0.7), cf * CF(0, 2.3, 1.3) * ANG(0, math.pi, 0), C(170, 40, 50), "Fabric")
		for _, x in ipairs({ -1.7, 1.7 }) do
			b:Box(V(0.9, 1.1, 0.06), CF(x, top - 0.8, -2.65), C(170, 40, 50), "Fabric")
			b:Accent(b:Box(V(0.36, 0.36, 0.04), CF(x, top - 0.7, -2.69), Pal.Gold, "Metal"))
		end
	end)
end

recipes.pharaoh_dog = function(b)
	local sand, black, gold, blue = C(222, 196, 140), C(36, 34, 40), Pal.Gold, C(40, 90, 190)
	local k = 2.0
	b:Box(V(9.4, 0.12, 9.6), CF(0, 0.06, 0.2), C(214, 190, 136), "Sand")
	-- Stepped sandstone base
	for i = 0, 2 do
		local w = 7.2 - i * 1.3
		b:Box(V(w, 0.6, w), CF(0, 0.3 + i * 0.6, 0.6), sand:Lerp(C(255, 255, 255), i * 0.05), "Sandstone", SOLID)
	end
	local top = 1.8
	-- Anubis-like sitting dog
	local cf = CF(0, top, 0.7)
	dog(b, cf, k, black, { Ears = "tall", Collar = gold, Eyes = C(80, 230, 255), Accent = true })
	-- Nemes headdress over the head
	local head = cf * CF(0, 2.45 * k, -0.42 * k)
	b:Ellipsoid(V(2.4, 0.9, 2.0), head * CF(0, 0.58, 0.18), gold, "Metal")
	for _, x in ipairs({ -1, 1 }) do
		b:Box(V(0.64, 2.1, 0.84), head * CF(x * 0.95, -0.85, 0.22), blue, "SmoothPlastic")
		b:Detail(function()
			b:Box(V(0.66, 0.2, 0.86), head * CF(x * 0.95, -0.5, 0.22), gold, "Metal")
			b:Box(V(0.66, 0.2, 0.86), head * CF(x * 0.95, -1.2, 0.22), gold, "Metal")
		end)
	end
	-- Obelisks
	for _, x in ipairs({ -3.8, 3.8 }) do
		b:Box(V(0.9, 4.6, 0.9), CF(x, 2.3, -3.2), sand, "Sandstone")
		for i = 0, 3 do
			b:Wedge(V(0.9, 0.6, 0.45), CF(x, 4.9, -3.2) * ANG(0, i * math.pi / 2, 0) * CF(0, 0, -0.225), gold, "Metal")
		end
		b:Detail(function()
			b:Accent(b:Box(V(0.36, 0.36, 0.04), CF(x, 3.3, -3.67), C(80, 230, 255), "Neon"))
			b:Box(V(0.5, 0.12, 0.04), CF(x, 2.4, -3.67), blue, "SmoothPlastic")
		end)
	end
	b:Detail(function()
		-- hieroglyph band on the front step and two scarab jars
		for i = -3, 3 do
			b:Box(V(0.26, 0.34, 0.04), CF(i * 0.8, 0.32, -3.03), i % 2 == 0 and blue or gold, "SmoothPlastic")
		end
		for _, x in ipairs({ -2.3, 2.3 }) do
			b:CylY(0.9, 0.7, CF(x, 2.25, -1.4), C(200, 160, 90), "SmoothPlastic")
			b:Accent(b:Ball(0.4, CF(x, 2.8, -1.4), C(80, 230, 255), "Neon"))
		end
	end)
end

recipes.golden_dog_statue = function(b)
	local marble, gold = C(240, 236, 228), Pal.Gold
	local k = 2.2
	-- Round stepped marble pedestal
	b:CylY(0.5, 9.2, CF(0, 0.25, 0), C(200, 196, 188), "Marble", SOLID)
	b:CylY(0.5, 8.0, CF(0, 0.75, 0), marble, "Marble", SOLID)
	b:CylY(1.8, 5.4, CF(0, 1.9, 0), marble, "Marble", SOLID)
	b:Ring(CF(0, 2.85, 0), 2.75, 0.24, gold, "Metal", 16)
	b:Accent(b:Ring(CF(0, 1.02, 0), 3.95, 0.14, C(255, 220, 120), "Neon", 18))
	local top = 2.8
	local cf = CF(0, top, 0.25)
	dog(b, cf, k, gold, { Ears = "pointy", Mat = "Metal", Collar = C(220, 40, 60), CollarMat = "SmoothPlastic" })
	-- Crown on the head
	local head = cf * CF(0, 2.45 * k, -0.42 * k)
	b:CylY(0.6, 1.4, head * CF(0, 1.2, 0), gold, "Metal")
	b:Detail(function()
		for i = 0, 4 do
			local a = rad(i * 72)
			b:Wedge(V(0.36, 0.6, 0.28), head * CF(math.sin(a) * 0.6, 1.8, math.cos(a) * 0.6) * ANG(0, a, 0), gold, "Metal")
		end
		b:Accent(b:Gem(0.42, head * CF(0, 1.2, -0.72), C(220, 30, 70), "Glass"))
		-- a bone held between the front paws
		bone(b, CF(0, top + 0.4, -1.75), 2.0, 0.4, C(255, 236, 160), "Metal")
	end)
end

recipes.cosmic_dog = function(b)
	local void, glow = C(40, 22, 80), C(170, 80, 255)
	-- Dais with a glowing ring
	b:CylY(0.4, 7.6, CF(0, 0.2, 0), C(30, 26, 48), "Slate", SOLID)
	b:Accent(b:Ring(CF(0, 0.42, 0), 3.5, 0.14, glow, "Neon", 18))
	b:CylY(2.0, 0.7, CF(0, 1.4, 0), C(60, 56, 80), "Metal")
	-- Planet with a tilted ring and a moon
	b:Ball(4.4, CF(0, 4.3, 0), C(70, 50, 140), "SmoothPlastic")
	b:Ball(1.3, CF(-1.2, 5.0, -1.6), C(110, 80, 190), "SmoothPlastic")
	b:Ring(CF(0, 4.2, 0) * ANG(rad(16), 0, rad(-10)), 3.4, 0.28, C(255, 200, 120), "Neon", 20)
	-- The dog sitting on top of the planet
	local k = 1.5
	local top = 6.25
	local cf = CF(0, top, 0.1)
	dog(b, cf, k, void, { Ears = "pointy", Collar = glow, CollarMat = "Neon", Eyes = C(120, 240, 255), Accent = true })
	b:Detail(function()
		-- star spots on the dog and orbiting stars
		local spots = { V(0.35, 1.5, -0.75), V(-0.4, 1.0, -0.6), V(0.5, 0.7, 0.6), V(-0.3, 2.9, -0.8), V(0.15, 2.0, -0.85) }
		for _, p in ipairs(spots) do
			b:Accent(b:Ball(0.2, cf * CF(p * k), C(255, 255, 255), "Neon"))
		end
		for i = 0, 3 do
			local a = rad(i * 90 + 20)
			b:Accent(b:Gem(0.42, CF(math.sin(a) * 3.9, 4.6 + (i % 2) * 2.2, math.cos(a) * 3.9), C(255, 240, 160), "Neon"))
		end
	end)
	-- Halo above the head
	b:Accent(b:Ring(cf * CF(0, 3.55 * k, -0.42 * k), 0.8, 0.12, C(120, 240, 255), "Neon", 10))
end

------------------------------------------------------------------------------------------------
-- THEMED ZONES (Large)
------------------------------------------------------------------------------------------------
recipes.zen_garden = function(b)
	local sand, wood = C(232, 224, 200), C(130, 90, 60)
	-- Raised wooden frame with raked sand
	b:Box(V(9.2, 0.35, 9.6), CF(0, 0.175, 0.4), wood, "WoodPlanks")
	b:Box(V(8.6, 0.12, 9.0), CF(0, 0.4, 0.4), sand, "Sand")
	b:Detail(function()
		for i = 0, 6 do
			b:Box(V(5.8, 0.05, 0.08), CF(-1.2, 0.47, -3.0 + i * 0.55), C(214, 206, 182), "Sand")
		end
		b:Ring(CF(2.2, 0.47, 1.6), 1.4, 0.08, C(214, 206, 182), "Sand", 12)
		b:Ring(CF(2.2, 0.47, 1.6), 1.8, 0.08, C(214, 206, 182), "Sand", 14)
	end)
	-- Rocks
	b:Ellipsoid(V(1.6, 1.2, 1.3), CF(2.2, 0.75, 1.6), C(110, 108, 104), "Slate")
	b:Ellipsoid(V(1.0, 0.8, 0.9), CF(-2.8, 0.6, -1.2), C(124, 120, 116), "Slate")
	b:Ellipsoid(V(0.7, 0.5, 0.6), CF(-2.0, 0.5, -0.6), C(98, 96, 92), "Slate")
	-- Bonsai on a stone
	b:Box(V(1.4, 0.6, 1.0), CF(-2.6, 0.75, 2.6), C(150, 146, 140), "Slate")
	b:Rod(V(-2.6, 1.0, 2.6), V(-2.3, 2.0, 2.6), 0.3, C(90, 60, 44), "Wood")
	b:Rod(V(-2.3, 2.0, 2.6), V(-2.9, 2.6, 2.5), 0.2, C(90, 60, 44), "Wood")
	b:Ellipsoid(V(1.5, 0.6, 1.0), CF(-2.25, 2.25, 2.6), C(60, 120, 60), "Grass")
	b:Ellipsoid(V(1.0, 0.5, 0.8), CF(-2.95, 2.75, 2.5), C(70, 136, 66), "Grass")
	-- Stone lantern
	local lx, lz = 3.1, -2.8
	b:Box(V(0.9, 0.3, 0.9), CF(lx, 0.6, lz), C(150, 146, 140), "Slate")
	b:CylY(1.2, 0.35, CF(lx, 1.35, lz), C(150, 146, 140), "Slate")
	b:Box(V(0.8, 0.7, 0.8), CF(lx, 2.3, lz), C(150, 146, 140), "Slate")
	b:Accent(b:Box(V(0.5, 0.4, 0.82), CF(lx, 2.3, lz), C(255, 214, 140), "Neon"))
	b:Wedge(V(1.2, 0.45, 0.6), CF(lx, 2.88, lz - 0.3) * ANG(0, math.pi, 0), C(120, 116, 112), "Slate")
	b:Wedge(V(1.2, 0.45, 0.6), CF(lx, 2.88, lz + 0.3), C(120, 116, 112), "Slate")
	-- Bamboo fence at the back
	for i = 0, 8 do
		b:CylY(2.6 + (i % 3) * 0.25, 0.25, CF(-4.0 + i * 1.0, 1.65, 4.75), C(170, 180, 90), "Wood")
	end
	b:Box(V(9.0, 0.12, 0.1), CF(0, 1.4, 4.6), C(120, 90, 50), "Fabric")
	b:Box(V(9.0, 0.12, 0.1), CF(0, 2.4, 4.6), C(120, 90, 50), "Fabric")
	-- Little red bridge over a pond
	b:Box(V(2.4, 0.06, 1.6), CF(0.6, 0.44, -2.4), C(80, 150, 200), "Glass", { Transparency = 0.2 })
	for i = 0, 3 do
		b:Box(V(0.5, 0.12, 1.0), CF(-0.15 + i * 0.5, 0.75 + math.sin((i + 0.5) / 4 * math.pi) * 0.35, -2.4), C(200, 60, 50), "WoodPlanks")
	end
	b:Ball(0.35, CF(1.2, 0.5, -2.1), C(250, 140, 60), "SmoothPlastic")
end

recipes.candy_corner = function(b)
	b:Box(V(9.2, 0.25, 9.6), CF(0, 0.125, 0.4), C(255, 214, 230), "SmoothPlastic")
	b:Detail(function()
		for i = 0, 3 do
			b:Box(V(9.2, 0.03, 0.6), CF(0, 0.26, -3.6 + i * 2.4), C(255, 240, 248), "SmoothPlastic")
		end
	end)
	-- Giant lollipops
	local lolli: { { P: Vector3, H: number, Col: Color3 } } = {
		{ P = V(-3.2, 0, 2.6), H = 5.2, Col = C(255, 80, 140) },
		{ P = V(3.0, 0, 3.0), H = 4.4, Col = C(90, 200, 255) },
		{ P = V(-1.0, 0, 4.0), H = 3.6, Col = C(160, 240, 90) },
	}
	for _, l in ipairs(lolli) do
		local p, h, col = l.P, l.H, l.Col
		b:CylY(h, 0.25, CF(p.X, h / 2, p.Z), C(250, 250, 250), "SmoothPlastic")
		b:CylZ(0.35, 2.2, CF(p.X, h + 0.9, p.Z), col, "SmoothPlastic")
		b:Accent(b:CylZ(0.38, 1.3, CF(p.X, h + 0.9, p.Z), C(255, 255, 255), "SmoothPlastic"))
		b:CylZ(0.4, 0.55, CF(p.X, h + 0.9, p.Z), col, "SmoothPlastic")
	end
	-- Candy canes (arch + stick)
	for _, x in ipairs({ -3.8, 3.6 }) do
		local z = -2.2
		for i = 0, 4 do
			b:CylY(0.8, 0.45, CF(x, 0.4 + i * 0.8, z), i % 2 == 0 and C(230, 40, 50) or C(255, 255, 255), "SmoothPlastic")
		end
		for i = 0, 3 do
			local a = math.pi * (i + 0.5) / 4
			local dir = x < 0 and 1 or -1
			b:Ball(0.5, CF(x + dir * (0.5 - math.cos(a) * 0.5), 4.2 + math.sin(a) * 0.5, z), i % 2 == 0 and C(255, 255, 255) or C(230, 40, 50), "SmoothPlastic")
		end
	end
	-- Gumdrops, a donut and a cupcake
	local gum = { C(255, 90, 90), C(255, 220, 70), C(120, 220, 120), C(170, 120, 255) }
	for i, p in ipairs({ V(-1.8, 0, -3.0), V(-0.9, 0, -3.6), V(0.4, 0, -3.3), V(1.4, 0, -3.8) }) do
		b:Ellipsoid(V(0.9, 0.9, 0.9), CF(p.X, 0.55, p.Z), gum[i], "Glass", { Transparency = 0.1 })
	end
	b:Ring(CF(1.6, 0.75, 0.2) * ANG(rad(75), 0, 0), 0.8, 0.6, C(220, 160, 90), "SmoothPlastic", 10)
	b:Ring(CF(1.6, 0.8, 0.12) * ANG(rad(75), 0, 0), 0.8, 0.5, C(255, 140, 200), "SmoothPlastic", 10)
	local cx, cz = -1.2, 1.0
	b:Cone(CF(cx, 0.25, cz), 1.1, 1.4, 1.8, 2, C(250, 200, 120), "SmoothPlastic")
	b:Ellipsoid(V(2.0, 1.2, 2.0), CF(cx, 1.6, cz), C(255, 160, 210), "SmoothPlastic")
	b:Ball(0.45, CF(cx, 2.3, cz), C(220, 30, 50), "SmoothPlastic")
	b:Detail(function()
		for i = 0, 5 do
			local a = rad(i * 60)
			b:Box(V(0.18, 0.06, 0.06), CF(cx + math.sin(a) * 0.6, 1.95, cz + math.cos(a) * 0.6) * ANG(0, a, 0), gum[i % 4 + 1], "Neon")
		end
	end)
	-- Chocolate bench
	b:Box(V(2.4, 0.5, 0.9), CF(1.4, 0.5, 3.2), C(110, 64, 40), "SmoothPlastic")
	b:Detail(function()
		for i = 0, 2 do
			b:Box(V(0.7, 0.1, 0.8), CF(0.6 + i * 0.8, 0.8, 3.2), C(130, 78, 50), "SmoothPlastic")
		end
	end)
end

recipes.pirate_cove = function(b)
	local sand, wood, darkWood = Pal.Sand, C(130, 88, 52), C(80, 54, 36)
	b:Ellipsoid(V(9.6, 0.7, 10.4), CF(0, 0.05, 0.2), sand, "Sand")
	b:Box(V(3.4, 0.08, 2.6), CF(-2.4, 0.38, -3.0), C(70, 160, 210), "Glass", { Transparency = 0.25 })
	-- Ship bow sticking out of the sand
	local bow = CF(1.4, 0, 2.2) * ANG(0, rad(-25), 0)
	b:Wedge(V(3.2, 2.4, 3.2), bow * CF(0, 1.2, -1.6), wood, "WoodPlanks", SOLID)
	b:Box(V(3.2, 2.4, 2.6), bow * CF(0, 1.2, 1.3), wood, "WoodPlanks", SOLID)
	b:Box(V(3.4, 0.3, 5.9), bow * CF(0, 2.5, -0.1), darkWood, "WoodPlanks")
	b:Rod(bow * CF(0, 2.6, -3.0).Position, bow * CF(0, 3.6, -4.4).Position, 0.25, darkWood, "Wood") -- bowsprit
	-- Mast with the Jolly Roger
	local mastBase = bow * CF(0, 2.6, 1.0)
	b:Rod(mastBase.Position, (mastBase * CF(0, 6.0, 0)).Position, 0.4, darkWood, "Wood")
	b:Box(V(0.12, 0.12, 2.6), mastBase * CF(0, 4.6, 0), darkWood, "Wood")
	b:Box(V(0.06, 2.4, 2.2), mastBase * CF(0, 3.3, 0), C(236, 226, 200), "Fabric")
	b:Box(V(1.5, 1.0, 0.05), mastBase * CF(0.75, 5.5, 0), C(24, 24, 28), "Fabric")
	b:Accent(b:Ball(0.42, mastBase * CF(0.75, 5.6, -0.04), C(245, 245, 240), "SmoothPlastic"))
	b:Detail(function()
		b:Box(V(0.6, 0.08, 0.04), mastBase * CF(0.75, 5.25, -0.04) * ANG(0, 0, rad(35)), C(245, 245, 240), "SmoothPlastic")
		b:Box(V(0.6, 0.08, 0.04), mastBase * CF(0.75, 5.25, -0.04) * ANG(0, 0, rad(-35)), C(245, 245, 240), "SmoothPlastic")
	end)
	-- Treasure chest
	local chest = CF(-2.8, 0.35, 1.5) * ANG(0, rad(20), 0)
	b:Box(V(1.6, 0.9, 1.0), chest * CF(0, 0.45, 0), C(130, 78, 44), "WoodPlanks")
	b:Box(V(1.7, 0.18, 1.1), chest * CF(0, 0.95, 0), Pal.GoldDark, "Metal")
	b:Accent(b:Ellipsoid(V(1.3, 0.4, 0.8), chest * CF(0, 1.05, 0), Pal.Gold, "Metal"))
	-- Cannon
	local cannon = CF(-0.6, 0.35, -3.6) * ANG(0, rad(-15), 0)
	b:Box(V(1.1, 0.5, 1.6), cannon * CF(0, 0.3, 0), darkWood, "WoodPlanks")
	for _, x in ipairs({ -0.62, 0.62 }) do
		b:Cyl(0.15, 0.8, cannon * CF(x, 0.35, 0.45), C(60, 40, 30), "Wood")
		b:Cyl(0.15, 0.8, cannon * CF(x, 0.35, -0.45), C(60, 40, 30), "Wood")
	end
	b:CylZ(2.0, 0.6, cannon * CF(0, 0.85, -0.3) * ANG(rad(10), 0, 0), C(40, 40, 46), "Metal")
	b:Ball(0.75, cannon * CF(0, 0.85, 0.55), C(40, 40, 46), "Metal")
	-- Barrels and cannonballs
	for i, p in ipairs({ V(3.3, 0, -1.4), V(3.6, 0, -2.6) }) do
		b:CylY(1.3, 1.0, CF(p.X, 0.55 + 0.65, p.Z), C(150, 100, 60), "WoodPlanks")
		b:Ring(CF(p.X, 0.85 + (i - 1) * 0.1, p.Z), 0.52, 0.1, C(60, 60, 66), "Metal", 8)
	end
	for i = 0, 2 do
		b:Ball(0.4, CF(0.9 + (i % 2) * 0.42, 0.55 + math.floor(i / 2) * 0.35, -2.9 + (i == 2 and 0.2 or 0)), C(40, 40, 46), "Metal")
	end
	-- A small palm
	local trunk = C(164, 122, 80)
	local p0 = V(-3.6, 0.3, 4.0)
	local prev = p0
	for i = 1, 4 do
		local nxt = p0 + V(i * 0.18, i * 1.0, -i * 0.05)
		b:Rod(prev, nxt, 0.42, trunk, "Wood")
		prev = nxt
	end
	for i = 0, 4 do
		local a = rad(i * 72)
		local tip = prev + V(math.sin(a) * 1.5, -0.6, math.cos(a) * 1.5)
		b:Ellipsoid(V(0.5, 0.08, 1.6), CFrame.lookAt((prev + tip) / 2 + V(0, 0.2, 0), tip), C(80, 160, 64), "Grass")
	end
end

recipes.ice_corner = function(b)
	local ice, snow = C(170, 220, 250), C(245, 250, 255)
	b:Box(V(9.2, 0.3, 9.6), CF(0, 0.15, 0.4), snow, "Snow")
	b:Box(V(3.2, 0.06, 2.2), CF(-2.6, 0.32, -3.0), C(150, 210, 245), "Ice")
	-- Igloo
	local ix, iz = 1.6, 2.0
	b:Ellipsoid(V(5.0, 3.6, 5.0), CF(ix, 0.3, iz), snow, "Snow", SOLID)
	b:Detail(function()
		for i = 1, 2 do
			b:Ring(CF(ix, 0.3 + i * 0.6, iz), 2.5 - i * 0.18, 0.08, C(210, 230, 245), "Snow", 14)
		end
	end)
	b:CylZ(1.6, 1.8, CF(ix, 1.0, iz - 2.3), snow, "Snow")
	b:CylZ(0.1, 1.2, CF(ix, 1.0, iz - 3.12), C(40, 60, 90), "SmoothPlastic")
	-- Ice crystals
	for i, p in ipairs({ V(-3.4, 0.3, 2.8), V(-2.6, 0.3, 3.6), V(3.8, 0.3, -1.6) }) do
		b:Prism(CF(p) * ANG(rad(i * 6), rad(i * 37), rad((i - 2) * 8)), 0.8 - i * 0.1, 2.4 - i * 0.4, 0.7, ice, "Ice", { Transparency = 0.15 })
	end
	b:Accent(b:Prism(CF(-3.0, 0.3, 3.2) * ANG(0, rad(20), rad(-14)), 0.35, 1.6, 0.4, C(140, 230, 255), "Neon"))
	-- Snow dog
	local sd = CF(-1.6, 0.3, -0.4)
	b:Ball(1.9, sd * CF(0, 0.85, 0.3), snow, "Snow")
	b:Ball(1.3, sd * CF(0, 2.15, 0), snow, "Snow")
	b:Ellipsoid(V(0.6, 0.45, 0.65), sd * CF(0, 2.05, -0.75), snow, "Snow")
	b:Ball(0.22, sd * CF(0, 2.15, -1.08), C(30, 30, 34), "SmoothPlastic")
	for _, x in ipairs({ -0.45, 0.45 }) do
		b:Ellipsoid(V(0.3, 0.75, 0.45), sd * CF(x, 2.9, 0.05) * ANG(0, 0, rad(x * -30)), snow, "Snow")
		b:Ball(0.15, sd * CF(x * 0.55, 2.4, -0.55), C(30, 30, 34), "SmoothPlastic")
	end
	b:Accent(b:Ring(sd * CF(0, 1.6, 0.1), 0.62, 0.22, C(220, 50, 60), "Fabric", 8)) -- scarf
	b:Detail(function()
		-- snow piles and a little sled
		for i, p in ipairs({ V(3.6, 0.3, 3.8), V(-3.8, 0.3, -2.8), V(3.4, 0.3, -3.6) }) do
			b:Ellipsoid(V(1.6 - i * 0.2, 0.7, 1.3), CF(p), snow, "Snow")
		end
		b:Box(V(0.8, 0.12, 1.6), CF(3.2, 0.55, 0.0), C(200, 60, 50), "WoodPlanks")
		for _, x in ipairs({ -0.35, 0.35 }) do
			b:Box(V(0.08, 0.2, 1.8), CF(3.2 + x, 0.4, 0.0), C(60, 60, 66), "Metal")
		end
	end)
end

recipes.haunted_corner = function(b)
	local ground, stone = C(54, 48, 60), C(120, 118, 128)
	b:Box(V(9.2, 0.25, 9.6), CF(0, 0.125, 0.4), ground, "Ground")
	-- Dead tree
	local bark = C(60, 48, 46)
	b:Rod(V(2.8, 0.2, 3.0), V(2.6, 5.2, 3.0), 0.9, bark, "Wood")
	local branches = { { V(2.6, 3.4, 3.0), V(1.2, 5.0, 2.6) }, { V(2.6, 4.2, 3.0), V(3.9, 5.8, 3.4) }, { V(2.6, 5.0, 3.0), V(2.0, 6.6, 3.2) }, { V(1.2, 5.0, 2.6), V(0.6, 5.6, 2.2) }, { V(3.9, 5.8, 3.4), V(4.3, 6.4, 3.0) } }
	for _, br in ipairs(branches) do
		b:Rod(br[1], br[2], 0.32, bark, "Wood")
	end
	b:Accent(b:Ellipsoid(V(0.45, 0.6, 0.3), CF(1.25, 4.4, 2.6), C(140, 255, 120), "Neon")) -- hanging lantern
	b:Rod(V(1.25, 5.0, 2.6), V(1.25, 4.7, 2.6), 0.04, C(30, 30, 34), "SmoothPlastic")
	-- Tombstones
	for i, p in ipairs({ V(-3.0, 0, 2.6), V(-1.2, 0, 3.4), V(0.6, 0, 2.2) }) do
		local tilt = ANG(rad((i - 2) * 6), 0, rad((i - 2) * -5))
		b:Box(V(1.2, 1.5, 0.3), CF(p.X, 0.95, p.Z) * tilt, stone, "Slate")
		b:CylZ(0.3, 1.2, CF(p.X, 1.7, p.Z) * tilt, stone, "Slate")
		b:Detail(function()
			b:Box(V(0.12, 0.6, 0.04), CF(p.X, 1.25, p.Z - 0.17) * tilt, C(80, 78, 88), "Slate")
			b:Box(V(0.45, 0.12, 0.04), CF(p.X, 1.4, p.Z - 0.17) * tilt, C(80, 78, 88), "Slate")
		end)
		b:Ellipsoid(V(1.3, 0.3, 1.6), CF(p.X, 0.25, p.Z - 0.9), C(70, 58, 52), "Ground")
	end
	-- Broken fence
	for i = 0, 5 do
		if i ~= 3 then
			b:Box(V(0.16, 1.6 - (i % 2) * 0.3, 0.12), CF(-4.0 + i * 0.9, 1.0, -3.8) * ANG(0, 0, rad((i % 3 - 1) * 8)), C(70, 60, 56), "Wood")
		end
	end
	b:Box(V(4.8, 0.12, 0.1), CF(-1.8, 1.3, -3.8) * ANG(0, 0, rad(4)), C(70, 60, 56), "Wood")
	-- Pumpkins with glowing faces
	for i, p in ipairs({ V(1.6, 0, -2.4), V(2.8, 0, -2.9), V(-0.4, 0, -1.4) }) do
		local s = 1.1 - i * 0.15
		b:Ellipsoid(V(1.3, 1.0, 1.2) * s, CF(p.X, 0.25 + 0.5 * s, p.Z), C(240, 120, 30), "SmoothPlastic")
		b:CylY(0.35 * s, 0.18 * s, CF(p.X, 0.25 + 1.05 * s, p.Z), C(70, 110, 40), "Wood")
		b:Accent(b:Box(V(0.6, 0.18, 0.05) * s, CF(p.X, 0.25 + 0.4 * s, p.Z - 0.6 * s), C(255, 220, 90), "Neon"))
		b:Detail(function()
			for _, x in ipairs({ -0.22, 0.22 }) do
				b:Accent(b:Wedge(V(0.2, 0.2, 0.05) * s, CF(p.X + x * s, 0.25 + 0.68 * s, p.Z - 0.6 * s), C(255, 220, 90), "Neon"))
			end
		end)
	end
	-- Little ghost
	local gh = CF(-2.6, 2.2, -0.6)
	b:Ellipsoid(V(1.2, 1.6, 1.0), gh, C(240, 245, 255), "SmoothPlastic", { Transparency = 0.25 })
	b:Ball(0.9, gh * CF(0, 0.75, 0), C(240, 245, 255), "SmoothPlastic", { Transparency = 0.25 })
	for _, x in ipairs({ -0.18, 0.18 }) do
		b:Ball(0.18, gh * CF(x, 0.85, -0.42), C(20, 20, 30), "SmoothPlastic")
	end
	b:Detail(function()
		-- purple mist patches
		for _, p in ipairs({ V(-1.0, 0.27, 0.8), V(1.4, 0.27, 0.6), V(-3.2, 0.27, -2.2) }) do
			b:Accent(b:Ellipsoid(V(2.2, 0.08, 1.6), CF(p), C(150, 80, 220), "Neon", { Transparency = 0.55 }))
		end
	end)
end

recipes.space_pad = function(b)
	local metal, white = C(120, 126, 140), C(240, 242, 248)
	-- Launch pad
	b:CylY(0.5, 8.8, CF(0, 0.25, 0.4), C(70, 74, 86), "Concrete", SOLID)
	b:Accent(b:Ring(CF(0, 0.52, 0.4), 3.6, 0.14, C(80, 230, 255), "Neon", 18))
	b:CylY(0.12, 3.6, CF(0, 0.56, 0.4), C(240, 196, 40), "Metal")
	b:Detail(function()
		for i = 0, 3 do
			local a = rad(i * 90 + 45)
			b:Box(V(0.5, 0.06, 2.0), CF(math.sin(a) * 2.6, 0.54, 0.4 + math.cos(a) * 2.6) * ANG(0, a, 0), C(240, 196, 40), "Metal")
		end
	end)
	-- Rocket
	local r = CF(0, 0.6, 0.4)
	b:CylY(5.0, 1.8, r * CF(0, 2.9, 0), white, "SmoothPlastic", SOLID)
	b:Cone(r * CF(0, 5.4, 0), 2.4, 1.8, 0.2, 5, C(220, 50, 60), "SmoothPlastic")
	b:CylY(0.5, 1.9, r * CF(0, 1.5, 0), C(220, 50, 60), "SmoothPlastic")
	b:CylY(0.7, 1.3, r * CF(0, 0.1, 0), metal, "Metal")
	for i = 0, 3 do
		local a = rad(i * 90)
		b:Wedge(V(0.18, 1.8, 1.0), r * CF(math.sin(a) * 1.15, 1.2, math.cos(a) * 1.15) * ANG(0, a + math.pi, 0), C(220, 50, 60), "SmoothPlastic")
	end
	b:CylZ(0.12, 0.8, r * CF(0, 3.9, -0.88), C(60, 70, 90), "Metal")
	b:Accent(b:CylZ(0.1, 0.6, r * CF(0, 3.9, -0.92), C(120, 220, 255), "Neon"))
	b:Accent(b:Ellipsoid(V(1.0, 0.9, 1.0), r * CF(0, -0.15, 0), C(255, 160, 60), "Neon"))
	-- Service tower
	local t = CF(3.0, 0.5, 2.6)
	for _, x in ipairs({ -0.5, 0.5 }) do
		for _, z in ipairs({ -0.5, 0.5 }) do
			b:Box(V(0.16, 6.6, 0.16), t * CF(x, 3.3, z), C(200, 70, 50), "Metal")
		end
	end
	b:Detail(function()
		for i = 1, 4 do
			b:Box(V(1.16, 0.1, 1.16), t * CF(0, i * 1.5, 0), C(200, 70, 50), "Metal")
		end
	end)
	b:Box(V(2.0, 0.16, 0.3), t * CF(-1.4, 4.6, -0.9), C(200, 70, 50), "Metal")
	b:Accent(b:Ball(0.3, t * CF(0, 6.8, 0), C(255, 60, 60), "Neon"))
	-- Satellite dish
	local d = CF(-3.2, 0.5, 2.8)
	b:CylY(1.6, 0.3, d * CF(0, 0.8, 0), metal, "Metal")
	b:Ellipsoid(V(2.2, 0.5, 2.2), d * CF(0, 1.9, 0) * ANG(rad(-50), rad(30), 0), white, "SmoothPlastic")
	b:Rod((d * CF(0, 1.9, 0)).Position, (d * CF(0.3, 2.6, -0.6)).Position, 0.08, metal, "Metal")
	-- Moon rocks
	for i, p in ipairs({ V(-3.4, 0.5, -2.6), V(3.4, 0.5, -2.4), V(-2.6, 0.5, -3.4) }) do
		b:Ellipsoid(V(1.1 - i * 0.15, 0.7, 0.9), CF(p), C(150, 150, 160), "Slate")
	end
end

------------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------------
function DecorModels.Has(id: string): boolean
	return recipes[id] ~= nil
end

function DecorModels.Build(id: string, lod: number?): Model?
	local fn = recipes[id]
	if not fn then
		return nil
	end
	local b = Forge.Builder(id, { Lod = lod or 0 })
	local ok, err = pcall(fn :: any, b)
	if not ok then
		warn("DOGROTS decor model " .. id .. ": " .. tostring(err))
		b.Model:Destroy()
		return nil
	end
	local model = b:Finish()
	model:SetAttribute("DecorId", id)
	return model
end

local templates: { [string]: Model | false } = {}
function DecorModels.Get(id: string, lod: number?): Model?
	local key = id .. "#" .. tostring(lod or 0)
	local cached = templates[key]
	if cached == nil then
		local built = DecorModels.Build(id, lod)
		templates[key] = built or false
		cached = built or false
	end
	if cached then
		return (cached :: Model):Clone()
	end
	return nil
end

return DecorModels
