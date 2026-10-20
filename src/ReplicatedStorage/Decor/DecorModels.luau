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
	local hub = CF(0, 8.0, -2.0) -- in front of the tower, so the turning sails never cut into it
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
	-- the sails turn on the client (PlotCosmetics idle animations, see THE UNDERYARD section)
	sails:SetAttribute("IdleAnim", "Spin")
	sails:SetAttribute("IdlePivot", hub)
	sails:SetAttribute("IdleAxis", "Z")
	sails:SetAttribute("IdlePeriod", 9)
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
-- HALLOWEEN (NIGHT OF THE BURIED MOON rewards; DecorCatalog categories HauntedSmall / HauntedLarge)
------------------------------------------------------------------------------------------------
local PUMPKIN = C(242, 118, 26)
local PUMPKIN_DARK = C(196, 82, 18)
local CARVED = C(255, 196, 64)
local STEM_GREEN = C(98, 112, 46)
local LEAF_GREEN = C(96, 150, 50)
local TOMB = C(112, 110, 124)
local TOMB_DARK = C(62, 58, 72)
local GHOST_GREEN = C(130, 255, 150)
local WAX = C(238, 228, 204)
local FLAME = C(255, 150, 40)
local FLAME_CORE = C(255, 236, 150)

-- A ribbed pumpkin: lobes (ellipsoids) in a ring around a darker core; cf = centre, d = diameter, h = height.
local function pumpkinBody(b: Builder, cf: CFrame, d: number, h: number, lobes: number, color: Color3)
	b:Ellipsoid(V(d * 0.84, h * 0.96, d * 0.84), cf, color:Lerp(C(120, 40, 8), 0.25), "SmoothPlastic")
	for i = 0, lobes - 1 do
		local a = (i + 0.5) / lobes * math.pi * 2
		b:Ellipsoid(V(d * 0.5, h, d * 0.44), cf * CF(math.cos(a) * d * 0.25, 0, math.sin(a) * d * 0.25) * ANG(0, -a, 0),
			color:Lerp(PUMPKIN_DARK, (i % 2) * 0.22), "SmoothPlastic")
	end
end

-- A carved triangle on a front face (two wedges back to back), centred on cf, w x h, glowing.
local function carvedTriangle(b: Builder, cf: CFrame, w: number, h: number, color: Color3, down: boolean?)
	local flip = down and ANG(0, 0, math.pi) or CFrame.new()
	b:Accent(b:Wedge(V(0.06, h, w / 2), cf * flip * CF(-w / 4, 0, 0) * ANG(0, math.pi / 2, 0), color, "Neon"))
	b:Accent(b:Wedge(V(0.06, h, w / 2), cf * flip * CF(w / 4, 0, 0) * ANG(0, -math.pi / 2, 0), color, "Neon"))
end

recipes.hw_jack_o_lantern = function(b)
	-- straw bale
	local straw = C(214, 176, 92)
	b:Box(V(1.95, 0.56, 1.25), CF(-0.32, 0.28, 0.1), straw, "Fabric")
	b:Box(V(1.99, 0.08, 1.29), CF(-0.32, 0.46, 0.1), C(178, 140, 66), "Fabric")
	for _, x in ipairs({ -0.85, 0.21 }) do
		b:Box(V(0.07, 0.6, 1.3), CF(x, 0.28, 0.1), C(120, 82, 46), "Fabric")
	end
	-- the jack-o'-lantern
	local centre = CF(-0.32, 1.22, 0.1)
	pumpkinBody(b, centre, 1.72, 1.36, 8, PUMPKIN)
	local face = centre * CF(0, 0, -0.84)
	carvedTriangle(b, face * CF(-0.33, 0.2, 0) * ANG(0, math.rad(-22), 0) * ANG(0, 0, math.rad(-8)), 0.38, 0.3, CARVED)
	carvedTriangle(b, face * CF(0.33, 0.2, 0) * ANG(0, math.rad(22), 0) * ANG(0, 0, math.rad(8)), 0.38, 0.3, CARVED)
	carvedTriangle(b, face * CF(0, -0.02, -0.02), 0.18, 0.16, CARVED)
	local mouth = b:Accent(b:Box(V(0.82, 0.16, 0.06), face * CF(0, -0.3, 0.02) * ANG(math.rad(-8), 0, 0), CARVED, "Neon"))
	b:Detail(function()
		-- jagged teeth (dark pumpkin flesh over the glowing mouth) and the mouth's grin corners
		for _, x in ipairs({ -0.18, 0.18 }) do
			b:Box(V(0.13, 0.12, 0.08), face * CF(x, -0.27, -0.01) * ANG(0, 0, math.rad(45)), PUMPKIN_DARK, "SmoothPlastic")
		end
		for _, side in ipairs({ -1, 1 }) do
			b:Accent(b:Box(V(0.2, 0.1, 0.06), face * CF(side * 0.44, -0.22, 0.05) * ANG(0, math.rad(side * 24), math.rad(side * 28)), CARVED, "Neon"))
		end
	end)
	-- stem, curl and leaf
	b:Rod(V(-0.32, 1.82, 0.1), V(-0.26, 2.2, 0.06), 0.2, STEM_GREEN, "Wood")
	b:Rod(V(-0.26, 2.2, 0.06), V(-0.08, 2.32, 0.02), 0.15, STEM_GREEN, "Wood")
	b:Ellipsoid(V(0.55, 0.06, 0.34), CF(-0.62, 1.88, 0.2) * ANG(0, math.rad(30), math.rad(-14)), LEAF_GREEN, "SmoothPlastic")
	-- a small pumpkin beside the bale
	local small = CF(1.02, 0.34, -0.12)
	pumpkinBody(b, small, 0.82, 0.62, 6, C(250, 140, 36))
	b:Rod(V(1.02, 0.62, -0.12), V(1.06, 0.82, -0.14), 0.11, STEM_GREEN, "Wood")
	b:Detail(function()
		-- autumn leaves on the ground
		for i, p in ipairs({ V(-1.25, 0.03, -0.55), V(0.55, 0.03, -0.62), V(1.35, 0.03, 0.45), V(-1.3, 0.03, 0.55) }) do
			local col = ({ C(214, 92, 32), C(178, 52, 30), C(232, 160, 50), C(150, 84, 40) })[i]
			b:Ellipsoid(V(0.42, 0.04, 0.28), CF(p) * ANG(0, math.rad(i * 47), 0), col, "SmoothPlastic")
		end
	end)
	b:Light(mouth, C(255, 150, 50), 12, 1.3)
end

-- Pixel letters for engravings ({x, y, w, h} in units of u around the letter's centre).
local GLYPHS = {
	R = { { -1, 0, 1, 5 }, { 0, 2, 2, 1 }, { 1, 1, 1, 1 }, { 0, 0, 2, 1 }, { 0.75, -1.5, 1, 2 } },
	I = { { 0, 0, 1, 5 } },
	P = { { -1, 0, 1, 5 }, { 0, 2, 2, 1 }, { 1, 1, 1, 1 }, { 0, 0, 2, 1 } },
}
local function engrave(b: Builder, cf: CFrame, text: string, u: number, color: Color3)
	local x = -(#text - 1) * 2.3 * u
	for i = 1, #text do
		for _, r in ipairs(GLYPHS[string.sub(text, i, i)] or {}) do
			-- the front face looks along -Z: the viewer's right is local -X
			b:Box(V(r[3] * u, r[4] * u, 0.04), cf * CF(-(x + r[1] * u), r[2] * u, 0), color, "Slate")
		end
		x += 4.6 * u
	end
end

recipes.hw_grave_stone = function(b)
	-- footing, headstone with a round top, R.I.P., a carved paw and a ghost-green crack
	b:Box(V(1.8, 0.28, 0.78), CF(0, 0.14, 0.42), C(84, 80, 94), "Slate")
	local stone = CF(0, 1.12, 0.42) * ANG(math.rad(-4), 0, math.rad(3))
	b:Box(V(1.36, 1.5, 0.34), stone, TOMB, "Slate")
	b:CylZ(0.34, 1.36, stone * CF(0, 0.75, 0), TOMB, "Slate")
	b:Box(V(1.5, 0.14, 0.42), stone * CF(0, -0.68, 0), TOMB_DARK, "Slate")
	local front = stone * CF(0, 0, -0.18)
	engrave(b, front * CF(0, 0.62, 0), "RIP", 0.065, TOMB_DARK)
	b:Ellipsoid(V(0.36, 0.3, 0.04), front * CF(0, -0.2, 0), TOMB_DARK, "Slate")
	for _, t in ipairs({ { -0.2, 0.04 }, { -0.07, 0.12 }, { 0.07, 0.12 }, { 0.2, 0.04 } }) do
		b:Ellipsoid(V(0.12, 0.15, 0.04), front * CF(t[1], t[2], 0), TOMB_DARK, "Slate")
	end
	b:Detail(function()
		-- the crack glows ghost green
		b:Accent(b:Box(V(0.05, 0.42, 0.04), front * CF(0.42, 0.38, -0.005) * ANG(0, 0, math.rad(18)), GHOST_GREEN, "Neon"))
		b:Accent(b:Box(V(0.05, 0.3, 0.04), front * CF(0.5, 0.06, -0.005) * ANG(0, 0, math.rad(-22)), GHOST_GREEN, "Neon"))
		b:Accent(b:Box(V(0.04, 0.22, 0.04), front * CF(0.37, -0.18, -0.005) * ANG(0, 0, math.rad(30)), GHOST_GREEN, "Neon"))
		-- moss
		b:Ellipsoid(V(0.5, 0.16, 0.42), stone * CF(-0.48, 0.92, 0), C(72, 112, 54), "Grass")
		b:Ellipsoid(V(0.62, 0.14, 0.5), stone * CF(0.38, -0.72, -0.02), C(64, 104, 50), "Grass")
	end)
	-- the grave mound in front, a little skull and a candle
	b:Ellipsoid(V(1.5, 0.36, 0.95), CF(0, 0.08, -0.38), C(78, 58, 44), "Ground")
	b:Ellipsoid(V(1.0, 0.24, 0.6), CF(-0.1, 0.2, -0.4), C(92, 70, 52), "Ground")
	local skull = CF(0.55, 0.3, -0.62) * ANG(0, math.rad(-25), math.rad(-10))
	b:Ball(0.36, skull, C(232, 222, 196), "SmoothPlastic")
	b:Box(V(0.22, 0.12, 0.16), skull * CF(0, -0.15, -0.1), C(222, 210, 182), "SmoothPlastic")
	for _, x in ipairs({ -0.07, 0.07 }) do
		b:Ball(0.1, skull * CF(x, 0.02, -0.15), C(30, 26, 36), "SmoothPlastic")
	end
	b:CylY(0.42, 0.14, CF(-0.65, 0.42, -0.5), WAX, "SmoothPlastic")
	b:Accent(b:Ellipsoid(V(0.1, 0.18, 0.1), CF(-0.65, 0.72, -0.5), FLAME, "Neon"))
end

recipes.hw_candle_cluster = function(b)
	-- mossy rock with melted wax, seven candles of every height on it
	b:Ellipsoid(V(2.7, 0.5, 1.6), CF(0, 0.12, 0), C(84, 82, 92), "Slate")
	b:Ellipsoid(V(1.4, 0.4, 1.1), CF(-0.55, 0.28, 0.12), C(96, 94, 104), "Slate")
	b:Ellipsoid(V(1.9, 0.08, 1.2), CF(0.05, 0.36, -0.02), WAX:Lerp(C(255, 255, 255), 0.1), "SmoothPlastic")
	local rows = {
		{ -0.62, 0.12, 1.55, 0.3 }, { -0.2, -0.28, 1.15, 0.27 }, { 0.32, 0.18, 1.32, 0.28 }, { 0.75, -0.22, 0.82, 0.24 },
		{ -0.98, -0.22, 0.72, 0.22 }, { 0.98, 0.25, 0.58, 0.22 }, { 0.12, -0.5, 0.5, 0.2 },
	}
	local tallest
	for i, r in ipairs(rows) do
		local base = 0.38
		local cf = CF(r[1], base + r[3] / 2, r[2]) * ANG(math.rad((i % 3 - 1) * 3), 0, math.rad((i % 2 == 0 and 1 or -1) * 2))
		b:CylY(r[3], r[4], cf, i % 3 == 0 and C(226, 214, 188) or WAX, "SmoothPlastic")
		local top = cf * CF(0, r[3] / 2, 0)
		local flame = b:Accent(b:Ellipsoid(V(r[4] * 0.62, r[4] * 1.2, r[4] * 0.62), top * CF(0, r[4] * 0.72, 0), FLAME, "Neon"))
		b:Accent(b:Ball(r[4] * 0.32, top * CF(0, r[4] * 0.55, 0), FLAME_CORE, "Neon"))
		if i <= 4 then
			b:Detail(function()
				b:Ellipsoid(V(r[4] * 0.42, r[3] * 0.4, r[4] * 0.32), cf * CF(r[4] * 0.42, r[3] * 0.18, -r[4] * 0.2), WAX:Lerp(C(255, 250, 235), 0.4), "SmoothPlastic")
			end)
		end
		if i == 1 then
			tallest = flame
		end
	end
	b:Detail(function()
		-- an iron dish under the tallest candle and a tiny skull keeping watch
		b:Disc(CF(-0.62, 0.4, 0.12), 0.62, 0.06, C(54, 52, 58), "Metal")
		local skull = CF(1.12, 0.52, -0.42) * ANG(0, math.rad(-30), 0)
		b:Ball(0.3, skull, C(232, 222, 196), "SmoothPlastic")
		b:Box(V(0.18, 0.1, 0.14), skull * CF(0, -0.13, -0.08), C(222, 210, 182), "SmoothPlastic")
		for _, x in ipairs({ -0.06, 0.06 }) do
			b:Ball(0.08, skull * CF(x, 0.02, -0.13), C(30, 26, 36), "SmoothPlastic")
		end
		b:Ellipsoid(V(0.55, 0.12, 0.4), CF(-1.05, 0.34, 0.45), C(70, 110, 52), "Grass")
	end)
	b:Light(tallest, C(255, 168, 70), 13, 1.25)
end

recipes.hw_bone_arch = function(b)
	local bone = Pal.Bone
	local boneShade = C(214, 200, 168)
	-- ground: dark soil, flagstones under the arch
	b:Box(V(9.2, 0.16, 7.4), CF(0, 0.08, 0.6), C(62, 52, 46), "Ground")
	for i, z in ipairs({ -2.3, -1.0, 0.3, 1.6, 2.9 }) do
		b:Box(V(1.7 - (i % 2) * 0.3, 0.1, 1.05), CF((i % 2 - 0.5) * 0.24, 0.2, z) * ANG(0, math.rad((i % 3 - 1) * 6), 0), C(108, 104, 114), "Slate")
	end
	-- two vertebra pillars
	local R = 3.25
	for _, side in ipairs({ -1, 1 }) do
		local x = side * R
		b:Box(V(1.7, 0.5, 1.7), CF(x, 0.4, 0.4), C(92, 88, 100), "Slate", SOLID)
		for k = 0, 3 do
			local y = 1.0 + k * 1.15
			b:CylY(0.66, 1.34 - k * 0.06, CF(x, y, 0.4), k % 2 == 0 and bone or boneShade, "SmoothPlastic", k == 0 and SOLID or nil)
			b:CylY(0.5, 0.86, CF(x, y + 0.56, 0.4), boneShade:Lerp(C(150, 136, 110), 0.3), "SmoothPlastic")
			b:Box(V(0.62, 0.3, 0.34), CF(x - side * 0.86, y + 0.05, 0.4) * ANG(0, 0, math.rad(side * 16)), bone, "SmoothPlastic")
		end
		b:Ball(1.25, CF(x, 5.55, 0.4), bone, "SmoothPlastic")
	end
	-- the arch: two great ribs meeting under the skull
	local centre = V(0, 5.55, 0.4)
	local n = 12
	local last
	for i = 0, n do
		local a = math.pi * i / n
		local p = centre + V(math.cos(a) * R, math.sin(a) * R * 0.92, 0)
		if last then
			b:Rod(last, p, 0.78 - math.sin(a) * 0.12, i % 2 == 0 and bone or boneShade, "SmoothPlastic")
		end
		last = p
	end
	b:Detail(function()
		-- knuckles where the two great ribs meet the pillars and each other
		for _, i in ipairs({ 3, 9 }) do
			local a = math.pi * i / n
			b:Ball(0.95, CF(centre + V(math.cos(a) * R, math.sin(a) * R * 0.92, 0)), boneShade, "SmoothPlastic")
		end
	end)
	-- the dog skull keystone (glowing green eyes) facing the walkway
	local skull = CF(0, 8.7, 0.25) * ANG(math.rad(-8), 0, 0)
	b:Ellipsoid(V(2.0, 1.7, 1.9), skull, bone, "SmoothPlastic")
	b:Ellipsoid(V(1.15, 0.82, 1.5), skull * CF(0, -0.38, -1.1), bone, "SmoothPlastic")
	b:Ellipsoid(V(0.9, 0.42, 1.25), skull * CF(0, -0.85, -0.95), boneShade, "SmoothPlastic") -- jaw
	for _, x in ipairs({ -0.46, 0.46 }) do
		b:Ellipsoid(V(0.56, 0.5, 0.2), skull * CF(x, 0.08, -0.86), C(28, 22, 34), "SmoothPlastic")
		b:Accent(b:Ball(0.26, skull * CF(x, 0.08, -0.93), C(130, 255, 120), "Neon"))
		b:Ellipsoid(V(0.42, 0.9, 0.5), skull * CF(x * 1.6, 0.62, 0.15) * ANG(0, 0, math.rad(x > 0 and -20 or 20)), boneShade, "SmoothPlastic")
	end
	b:Ball(0.22, skull * CF(0, -0.32, -1.86), C(30, 24, 34), "SmoothPlastic")
	b:Detail(function()
		for _, x in ipairs({ -0.36, -0.12, 0.12, 0.36 }) do
			b:Wedge(V(0.12, 0.22, 0.1), skull * CF(x, -0.66, -1.62) * ANG(math.pi, 0, 0), C(248, 244, 228), "SmoothPlastic")
		end
		for _, x in ipairs({ -0.38, 0.38 }) do
			b:Wedge(V(0.14, 0.3, 0.12), skull * CF(x, -0.72, -1.5) * ANG(math.pi, 0, 0), C(248, 244, 228), "SmoothPlastic")
		end
	end)
	-- two lanterns hanging under the arch
	for _, x in ipairs({ -1.25, 1.25 }) do
		local inner = math.sin(math.acos(math.clamp(x / R, -1, 1))) * R * 0.92
		local top = V(x, 5.55 + inner - 0.3, 0.4)
		local at = top - V(0, 1.15, 0)
		b:Rod(top, at + V(0, 0.42, 0), 0.06, C(46, 44, 52), "Metal")
		b:Box(V(0.5, 0.1, 0.5), CF(at + V(0, 0.36, 0)), C(46, 44, 52), "Metal")
		b:Accent(b:Box(V(0.38, 0.58, 0.38), CF(at), C(150, 255, 130), "Neon", { Transparency = 0.1 }))
		b:Box(V(0.5, 0.08, 0.5), CF(at - V(0, 0.33, 0)), C(46, 44, 52), "Metal")
	end
	-- ribs breaking out of the ground on both sides
	b:Detail(function()
		for _, side in ipairs({ -1, 1 }) do
			for k, z in ipairs({ -1.9, 1.3 }) do
				local x0 = side * (R + 0.62 + (k % 2) * 0.12)
				local prev = V(x0, 0.1, z)
				for j = 1, 3 do
					local a = j / 3 * math.pi * 0.42
					local p = V(x0 + side * math.sin(a) * 0.55, 0.1 + math.sin(a * 1.6) * (1.2 + k * 0.25), z + math.cos(a) * 0.15)
					b:Rod(prev, p, 0.24 - j * 0.03, boneShade, "SmoothPlastic")
					prev = p
				end
			end
		end
	end)
	-- pumpkins at the pillar feet and a ghost-purple mist pool under the arch
	for _, side in ipairs({ -1, 1 }) do
		local c = CF(side * (R - 0.15), 0.52, -1.25)
		pumpkinBody(b, c, 0.95, 0.72, 5, PUMPKIN)
		b:Rod(V(side * (R - 0.15), 0.86, -1.25), V(side * (R - 0.1), 1.05, -1.27), 0.12, STEM_GREEN, "Wood")
		local face = c * CF(0, 0, -0.47)
		b:Accent(b:Box(V(0.12, 0.1, 0.05), face * CF(-0.16, 0.1, 0) * ANG(0, 0, math.rad(45)), CARVED, "Neon"))
		b:Accent(b:Box(V(0.12, 0.1, 0.05), face * CF(0.16, 0.1, 0) * ANG(0, 0, math.rad(45)), CARVED, "Neon"))
		b:Accent(b:Box(V(0.4, 0.07, 0.05), face * CF(0, -0.12, 0), CARVED, "Neon"))
	end
	b:Detail(function()
		b:Accent(b:Ellipsoid(V(4.4, 0.05, 3.4), CF(0, 0.3, 0.4), C(110, 54, 180), "Neon", { Transparency = 0.78 }))
		b:Accent(b:Ellipsoid(V(2.4, 0.05, 1.8), CF(0.3, 0.33, -0.4), C(150, 90, 230), "Neon", { Transparency = 0.72 }))
	end)
end

------------------------------------------------------------------------------------------------
-- THE UNDERYARD (Halloween Chapter II rewards; DecorCatalog categories UnderyardSmall / UnderyardLarge)
------------------------------------------------------------------------------------------------
-- The crooked gothic stop-motion look of the Underyard district: leaning silhouettes, stretched lancet
-- windows, dog motifs everywhere; palette ink / bone / moon blue / violet / sickly green / candle orange.
-- Idle animations (StarterPlayerScripts.PlotCosmetics) are attributes on a part or on a sub-model (b:Folder):
--   IdleAnim    "Swing" | "Sway" | "Bob" | "Spin"  move the parts about a pivot
--               "Flicker" | "Pulse" | "Blink"      glow / visibility only (nothing moves)
--   IdlePivot   CFrame in the build frame (model space); default the part's own CFrame / the group's centre
--   IdleAxis    "X" | "Y" | "Z" axis of IdlePivot (defaults: Swing X, Sway Z, Spin Y)
--   IdleAmp     degrees (Swing, Sway), studs (Bob), 0..1 strength (Flicker, Pulse)
--   IdlePeriod  seconds per cycle (per turn for Spin, mean gap between blinks for Blink)
--   IdlePhase   0..1 offset of the cycle; IdleTurn: extra yaw (degrees) of a Bob
-- Moving parts are never collidable, moving groups never nest, and every pose of a swing stays inside the
-- slot footprint (tests/underyard_cosmetics.luau). DecorModels.Build tags a model that has any with DecorIdle = n.
local UY = {
	Ink = C(16, 12, 26),
	Night = C(40, 34, 56),
	Slate = C(62, 58, 78),
	Stone = C(96, 92, 112),
	StoneLight = C(150, 146, 166),
	Bone = C(230, 222, 200),
	BoneShade = C(192, 180, 154),
	Iron = C(42, 40, 52),
	Bronze = C(138, 104, 66),
	Wood = C(58, 44, 46),
	WoodLight = C(92, 72, 66),
	Bark = C(56, 46, 52),
	Moss = C(70, 98, 66),
	Soil = C(48, 38, 40),
	Violet = C(150, 80, 230),
	Glow = C(190, 132, 255),
	Moon = C(150, 200, 255),
	MoonCore = C(226, 240, 255),
	Ghost = C(120, 255, 140),
	Spirit = C(150, 236, 255),
	Candle = C(255, 170, 80),
	Wax = C(232, 224, 206),
	Rose = C(64, 112, 232),
	RoseDark = C(36, 64, 168),
	Leaf = C(52, 78, 60),
}
local function idle(target: Instance, kind: string, o: { [string]: any }?)
	target:SetAttribute("IdleAnim", kind)
	if o then
		for k, v in o do
			target:SetAttribute("Idle" .. k, v)
		end
	end
end

-- A flat triangle in the XY plane of cf (base centre at cf, apex towards +Y), t thick along Z.
local function spike(b: Builder, cf: CFrame, w: number, h: number, t: number, color: Color3, mat: string?, props: { [string]: any }?): { BasePart }
	return {
		b:Wedge(V(t, h, w / 2), cf * CF(-w / 4, h / 2, 0) * ANG(0, math.pi / 2, 0), color, mat, props),
		b:Wedge(V(t, h, w / 2), cf * CF(w / 4, h / 2, 0) * ANG(0, -math.pi / 2, 0), color, mat, props),
	}
end

-- A stretched gothic lancet window on a wall (cf = bottom centre, looking along cf -Z): glowing glass.
local function lancet(b: Builder, cf: CFrame, w: number, h: number, color: Color3): { BasePart }
	local out = spike(b, cf * CF(0, h, 0), w, w * 0.85, 0.1, color, "Neon")
	table.insert(out, b:Box(V(w, h, 0.1), cf * CF(0, h / 2, 0), color, "Neon"))
	return out
end

-- A dog skull looking along cf -Z (gargoyles, finials, lanterns), about 1.1 * s long, glowing eye sockets.
local function dogSkull(b: Builder, cf: CFrame, s: number, bone: Color3, eye: Color3, ears: boolean?)
	b:Ball(0.8 * s, cf, bone, "SmoothPlastic")
	b:Ellipsoid(V(0.46, 0.38, 0.66) * s, cf * CF(0, -0.14 * s, -0.46 * s), bone, "SmoothPlastic")
	for _, x in ipairs({ -1, 1 }) do
		b:Accent(b:Ball(0.2 * s, cf * CF(x * 0.17 * s, 0.04 * s, -0.31 * s), eye, "Neon"))
		if ears then
			b:Wedge(V(0.12, 0.36, 0.26) * s, cf * CF(x * 0.24 * s, 0.4 * s, 0.06 * s) * ANG(0, 0, rad(x * -14)), bone, "SmoothPlastic")
		end
	end
end

-- A wax candle standing on cf (base centre); returns the flame.
local function candle(b: Builder, cf: CFrame, h: number, d: number, wax: Color3?): BasePart
	b:CylY(h, d, cf * CF(0, h / 2, 0), wax or UY.Wax, "SmoothPlastic")
	return b:Accent(b:Ellipsoid(V(d * 0.6, d * 1.25, d * 0.6), cf * CF(0, h + d * 0.55, 0), UY.Candle, "Neon"))
end

-- A ghost wisp: a glowing head with a curling tail trailing along cf +Z; returns the head.
local function wisp(b: Builder, cf: CFrame, s: number, color: Color3): BasePart
	local head = b:Accent(b:Ball(0.44 * s, cf, color, "Neon", { Transparency = 0.12 }))
	b:Ellipsoid(V(0.32, 0.3, 0.66) * s, cf * CF(0, -0.05 * s, 0.4 * s) * ANG(rad(14), 0, 0), color, "Neon", { Transparency = 0.38 })
	b:Ellipsoid(V(0.17, 0.16, 0.5) * s, cf * CF(0.06 * s, -0.18 * s, 0.8 * s) * ANG(rad(28), rad(16), 0), color, "Neon", { Transparency = 0.58 })
	return head
end

-- A rounded headstone standing on cf (bottom centre), facing cf -Z.
local function headstone(b: Builder, cf: CFrame, w: number, h: number, t: number, color: Color3)
	b:Box(V(w, h - w / 2, t), cf * CF(0, (h - w / 2) / 2, 0), color, "Slate")
	b:CylZ(t, w, cf * CF(0, h - w / 2, 0), color, "Slate")
end

-- A paw print lying on the ground (cf = pad centre), toes towards cf -Z.
local function pawPrint(b: Builder, cf: CFrame, s: number, color: Color3, mat: string)
	b:Ellipsoid(V(0.72, 0.06, 0.6) * s, cf, color, mat)
	for i, x in ipairs({ -0.36, -0.13, 0.13, 0.36 }) do
		local lift = (i == 2 or i == 3) and 0.1 or 0
		b:Ellipsoid(V(0.24, 0.06, 0.3) * s, cf * CF(x * s, 0, (-0.52 - lift) * s), color, mat)
	end
end

-- Round rods through points (crooked iron, trunks, branches); ds = diameters per segment.
local function path(b: Builder, pts: { Vector3 }, ds: { number }, color: Color3, mat: string, props: { [string]: any }?)
	for i = 1, #pts - 1 do
		b:Rod(pts[i], pts[i + 1], ds[math.min(i, #ds)], color, mat, props)
	end
end

-- Crooked Bell Tower (Large, Seal VII): a leaning three-tier tower on a plinth, violet lancets, a stopped clock, dog
-- gargoyles, an open belfry whose bronze bell swings, and a bent spire crowned by a crescent moon.
recipes.uy_crooked_bell_tower = function(b)
	b:Box(V(9.0, 0.24, 9.0), CF(0, 0.12, 0.4), UY.Night, "Slate")
	b:Box(V(4.8, 1.0, 4.8), CF(0, 0.74, 0.8), UY.Slate, "Cobblestone", SOLID)
	b:Box(V(2.6, 0.5, 0.8), CF(0, 0.49, -2.0), UY.Slate, "Cobblestone")
	b:Detail(function()
		pawPrint(b, CF(0.25, 0.25, -3.25) * ANG(0, rad(-8), 0), 0.9, UY.Stone, "Slate")
	end)
	-- tier 1: crooked door with an iron knocker, a violet lancet over it
	local f1 = CF(0, 1.24, 0.9)
	b:Box(V(3.6, 4.4, 3.6), f1 * CF(0, 2.2, 0), UY.Stone, "Slate", SOLID)
	b:Box(V(4.1, 0.32, 4.1), f1 * CF(0, 4.56, 0), UY.Slate, "Slate")
	b:Box(V(1.3, 1.7, 0.14), f1 * CF(0, 0.85, -1.82), UY.Wood, "WoodPlanks")
	b:CylZ(0.14, 1.3, f1 * CF(0, 1.7, -1.82), UY.Wood, "WoodPlanks")
	b:Ball(0.24, f1 * CF(0.38, 0.95, -1.92), UY.Iron, "Metal")
	b:Accent(lancet(b, f1 * CF(0, 2.75, -1.81), 0.7, 0.9, UY.Glow))
	b:Detail(function()
		for _, side in ipairs({ -1, 1 }) do
			b:Accent(lancet(b, f1 * CF(side * 1.81, 1.5, 0.2) * ANG(0, side * -math.pi / 2, 0), 0.6, 1.5, UY.Glow))
		end
		b:Accent(b:Box(V(0.07, 0.8, 0.07), f1 * CF(-1.2, 3.25, -1.81) * ANG(0, 0, rad(24)), UY.Ghost, "Neon"))
		b:Accent(b:Box(V(0.07, 0.5, 0.07), f1 * CF(-1.02, 2.72, -1.81) * ANG(0, 0, rad(-18)), UY.Ghost, "Neon"))
		b:Ellipsoid(V(1.3, 0.55, 0.3), f1 * CF(1.15, 0.3, -1.8), UY.Moss, "Grass")
		b:Ellipsoid(V(0.3, 1.5, 0.9), f1 * CF(1.8, 0.8, -1.0), UY.Moss, "Grass")
	end)
	-- tier 2 leans and twists: a stopped clock, two slits, dog gargoyles on the ledge
	b:Detail(function()
		for _, x in ipairs({ -1.72, 1.72 }) do
			for k = 0, 2 do
				b:Box(V(0.3, 0.62, 0.3), f1 * CF(x, 0.55 + k * 1.35, -1.72), UY.StoneLight, "Slate")
			end
		end
	end)
	local f2 = f1 * CF(0.18, 4.72, 0) * ANG(0, rad(7), rad(-4.5))
	b:Box(V(3.1, 4.05, 3.1), f2 * CF(0, 1.78, 0), UY.Stone, "Slate")
	b:Box(V(3.6, 0.3, 3.6), f2 * CF(0, 3.9, 0), UY.Slate, "Slate")
	local clock = f2 * CF(0, 2.35, -1.56)
	b:CylZ(0.16, 1.95, clock, UY.Iron, "Metal")
	b:CylZ(0.12, 1.62, clock * CF(0, 0, -0.06), UY.Bone, "SmoothPlastic")
	b:Box(V(0.12, 0.5, 0.05), clock * CF(0, 0, -0.14) * ANG(0, 0, rad(160)) * CF(0, 0.22, 0), UY.Ink, "SmoothPlastic")
	b:Box(V(0.08, 0.7, 0.05), clock * CF(0, 0, -0.15) * ANG(0, 0, rad(-12)) * CF(0, 0.32, 0), UY.Ink, "SmoothPlastic")
	b:Accent(b:Ball(0.18, clock * CF(0, 0, -0.16), UY.Glow, "Neon"))
	b:Detail(function()
		for _, x in ipairs({ -0.8, 0.8 }) do
			b:Accent(lancet(b, f2 * CF(x, 0.3, -1.56), 0.36, 0.6, UY.Glow))
		end
	end)
	local t2 = f2 * CF(0, 4.05, 0)
	for _, side in ipairs({ -1, 1 }) do
		dogSkull(b, t2 * CF(side * 1.55, 0.14, -1.55) * ANG(0, rad(side * -40), 0) * ANG(rad(-18), 0, 0), 1.0, UY.StoneLight, UY.Ghost, true)
	end
	-- belfry: four posts, a violet glow on the floor (the tower's light) and the swinging bell
	local f3 = t2 * CF(0.22, 0, 0) * ANG(0, rad(-6), rad(-5))
	b:Box(V(3.3, 0.52, 3.3), f3 * CF(0, 0.02, 0), UY.Slate, "Slate")
	local glow = b:Accent(b:CylY(0.06, 2.1, f3 * CF(0, 0.31, 0), UY.Violet, "Neon", { Transparency = 0.3 }))
	for _, x in ipairs({ -1.35, 1.35 }) do
		for _, z in ipairs({ -1.35, 1.35 }) do
			b:Box(V(0.5, 3.5, 0.5), f3 * CF(x, 1.95, z), UY.Stone, "Slate")
		end
	end
	b:Box(V(3.8, 0.42, 3.8), f3 * CF(0, 3.85, 0), UY.Slate, "Slate")
	b:Box(V(3.0, 0.34, 0.34), f3 * CF(0, 3.47, 0), UY.Wood, "Wood")
	b:Light(glow, UY.Violet, 16, 1.1)
	local pivot = f3 * CF(0, 3.3, 0)
	local bell = b:Folder("Bell")
	b:Box(V(0.3, 0.4, 0.3), pivot * CF(0, -0.15, 0), UY.Iron, "Metal")
	b:Ellipsoid(V(1.3, 0.7, 1.3), pivot * CF(0, -0.6, 0), UY.Bronze, "Metal")
	b:Cone(pivot * CF(0, -2.25, 0), 1.7, 1.95, 1.2, 4, UY.Bronze, "Metal")
	b:Disc(pivot * CF(0, -2.2, 0), 2.1, 0.18, C(104, 78, 50), "Metal")
	b:Accent(b:Disc(pivot * CF(0, -1.72, 0), 1.82, 0.1, UY.Glow, "Neon"))
	b:Rod((pivot * CF(0, -0.9, 0)).Position, (pivot * CF(0, -2.25, 0)).Position, 0.12, UY.Iron, "Metal")
	b:Ball(0.36, pivot * CF(0, -2.42, 0), UY.Iron, "Metal")
	b:Detail(function()
		b:Accent(b:Box(V(0.07, 0.6, 0.07), pivot * CF(0.32, -1.3, -0.74) * ANG(rad(-14), 0, rad(18)), UY.Glow, "Neon"))
	end)
	b:Into(b.Model)
	idle(bell, "Swing", { Pivot = pivot, Axis = "Z", Amp = 14, Period = 2.8 })
	-- bent spire: a slate pyramid, a crooked needle and a crescent-moon finial
	local f4 = f3 * CF(0.12, 3.92, 0) * ANG(0, rad(10), rad(-7))
	for i = 0, 3 do
		b:Wedge(V(3.5, 2.85, 1.75), f4 * ANG(0, i * math.pi / 2, 0) * CF(0, 1.42, -0.875), UY.Night, "Slate")
	end
	local apex = f4 * CF(0, 2.3, 0)
	local p1, p2, p3 = (apex * CF(0.06, 0.8, 0)).Position, (apex * CF(0.32, 1.5, 0.04)).Position, (apex * CF(0.72, 2.0, 0.08)).Position
	path(b, { apex.Position, p1, p2 }, { 0.5, 0.32 }, UY.Night, "Slate")
	b:Rod(p2, p3, 0.16, UY.Iron, "Metal")
	local moon = CF(p3) * CF(0.12, 0.5, 0)
	for k = 0, 3 do
		local a0, a1 = rad(70 + k * 55), rad(70 + (k + 1) * 55)
		b:Accent(b:Rod((moon * CF(math.cos(a0) * 0.42, math.sin(a0) * 0.42, 0)).Position, (moon * CF(math.cos(a1) * 0.42, math.sin(a1) * 0.42, 0)).Position, 0.17 - math.abs(k - 1.5) * 0.04, UY.Moon, "Neon"))
	end
	-- dog-skull lanterns on the plaza corners, candles on the plinth, two old graves at the back
	for _, x in ipairs({ -3.6, 3.6 }) do
		local at = CF(x, 0.24, -3.4)
		b:CylY(0.3, 0.6, at * CF(0, 0.15, 0), UY.Iron, "Metal")
		b:CylY(2.7, 0.2, at * CF(0, 1.5, 0), UY.Iron, "Metal")
		dogSkull(b, at * CF(0, 3.1, 0) * ANG(0, rad(x > 0 and -18 or 18), 0), 0.8, UY.Bone, UY.Ghost, true)
	end
	for i, p in ipairs({ V(-1.95, 1.24, -1.2), V(-1.55, 1.24, -1.42), V(2.0, 1.24, -1.3) }) do
		candle(b, CF(p), 0.5 + (i % 2) * 0.28, 0.2)
	end
	b:Detail(function()
		headstone(b, CF(-3.4, 0.24, 3.4) * ANG(0, rad(12), 0) * ANG(rad(-6), 0, rad(5)), 0.9, 1.3, 0.22, UY.Stone)
		headstone(b, CF(3.5, 0.24, 3.2) * ANG(0, rad(-20), 0) * ANG(rad(4), 0, rad(-7)), 0.8, 1.1, 0.22, UY.Stone)
	end)
end

-- Whispering Tree (Large): a twisted dead tree on a grave mound with a hollow face that whispers (eyes blink,
-- mouth glows), four swaying branches with lanterns and a crow, and whisper wisps circling the trunk.
recipes.uy_whispering_tree = function(b)
	local T = V(0, 0, 1.2) -- trunk foot
	b:Ellipsoid(V(8.8, 1.0, 9.2), CF(0, 0.05, 0.6), UY.Soil, "Ground")
	b:Ellipsoid(V(5.6, 0.5, 5.8), CF(0.2, 0.32, 0.9), UY.Moss:Lerp(UY.Soil, 0.45), "Grass")
	for i = 0, 4 do
		local a = rad(i * 72 + 20)
		local tip = V(math.cos(a) * 2.6, 0.12, T.Z + math.sin(a) * 2.6)
		path(b, { T + V(0, 1.0, 0), T + V(math.cos(a) * 1.3, 0.55, math.sin(a) * 1.3), tip }, { 0.62, 0.36 }, UY.Bark, "Wood")
	end
	-- the twisted trunk (S-curve) with knots at the joints, splitting at the top
	local pts = { T + V(0, 0.1, 0), T + V(0.35, 2.0, -0.1), T + V(-0.15, 3.8, 0.05), T + V(0.3, 5.4, -0.1), T + V(0.05, 6.9, 0) }
	local ds = { 2.0, 1.7, 1.4, 1.1 }
	path(b, pts, ds, UY.Bark, "Wood")
	for i = 2, 4 do
		b:Ball((ds[i - 1] + ds[i]) / 2, CF(pts[i]), UY.Bark, "Wood")
	end
	path(b, { pts[5], pts[5] + V(-0.4, 1.1, 0.1) }, { 0.32 }, UY.Bark, "Wood")
	path(b, { pts[5], pts[5] + V(0.5, 0.9, -0.2) }, { 0.26 }, UY.Bark, "Wood")
	-- the hollow face (front): blinking eyes and a whispering mouth
	local face = CF(0.12, 2.8, T.Z - 0.86)
	b:Ellipsoid(V(1.05, 1.35, 0.5), face, UY.Ink, "SmoothPlastic")
	for _, x in ipairs({ -0.22, 0.22 }) do
		idle(b:Accent(b:Ball(0.2, face * CF(x, 0.28, -0.18), UY.Spirit, "Neon")), "Blink", { Period = 4.5 })
	end
	idle(b:Accent(b:Ellipsoid(V(0.46, 0.2, 0.12), face * CF(0, -0.3, -0.2), UY.Spirit, "Neon")), "Pulse", { Amp = 0.7, Period = 1.7 })
	-- four branches, each a swaying group: crooked limb, a twig, two claw twigs and what hangs from it
	local function branch(name: string, h: number, yaw: number, reach: number, period: number, phase: number, extra: ((CFrame, Vector3) -> ())?)
		local base = CF(T + V(0, h, 0)) * ANG(0, rad(yaw), 0)
		local group = b:Folder(name)
		local b1 = (base * CF(0, 0.85, -1.35 * reach)).Position
		local b2 = (base * CF(0.1, 1.1, -2.6 * reach)).Position
		local b3 = (base * CF(-0.05, 0.6, -3.4 * reach)).Position
		path(b, { base.Position, b1, b2, b3 }, { 0.58, 0.4, 0.24 }, UY.Bark, "Wood")
		path(b, { b1, (base * CF(0.45, 1.75, -1.6 * reach)).Position }, { 0.17 }, UY.Bark, "Wood")
		b:Detail(function()
			path(b, { b3, (base * CF(0.25, 0.75, -3.85 * reach)).Position }, { 0.1 }, UY.Bark, "Wood")
			path(b, { b3, (base * CF(-0.3, 0.3, -3.8 * reach)).Position }, { 0.1 }, UY.Bark, "Wood")
		end)
		if extra then
			extra(base, b2)
		end
		b:Into(b.Model)
		idle(group, "Sway", { Pivot = base, Axis = "X", Amp = 3.5, Period = period, Phase = phase })
	end
	local function lantern(_: CFrame, at: Vector3)
		local bottom = at - V(0, 1.15, 0)
		b:Rod(at, bottom, 0.05, UY.Iron, "Metal")
		b:CylY(0.12, 0.5, CF(bottom - V(0, 0.06, 0)), UY.Iron, "Metal")
		idle(b:Accent(b:Box(V(0.36, 0.5, 0.36), CF(bottom - V(0, 0.36, 0)), UY.Ghost, "Neon", { Transparency = 0.15 })), "Flicker", { Amp = 0.55 })
		b:CylY(0.1, 0.46, CF(bottom - V(0, 0.66, 0)), UY.Iron, "Metal")
	end
	branch("BranchFrontLeft", 4.9, 70, 1.1, 4.6, 0, lantern)
	branch("BranchFrontRight", 5.5, -62, 1.05, 5.3, 0.4, lantern)
	branch("BranchBackLeft", 6.1, 135, 0.95, 4.9, 0.7, function(base: CFrame)
		-- a crow perched on the limb, looking out to the yard
		local crow = base * CF(0, 1.3, -1.95) * ANG(0, rad(-150), 0)
		b:Ellipsoid(V(0.42, 0.46, 0.78), crow, UY.Ink, "SmoothPlastic")
		b:Ball(0.36, crow * CF(0, 0.3, -0.32), UY.Ink, "SmoothPlastic")
		b:Wedge(V(0.1, 0.12, 0.26), crow * CF(0, 0.28, -0.6) * ANG(0, math.pi, 0), C(170, 150, 90), "SmoothPlastic")
		b:Accent(b:Ball(0.08, crow * CF(0.1, 0.36, -0.45), UY.Ghost, "Neon"))
		b:Wedge(V(0.3, 0.1, 0.5), crow * CF(0, -0.05, 0.55), UY.Ink, "SmoothPlastic")
	end)
	branch("BranchBackRight", 6.6, -125, 0.95, 5.8, 0.2)
	-- whisper wisps circling the trunk
	local ring = b:Folder("Whispers")
	for i, h in ipairs({ 1.7, 2.6, 3.2, 2.1 }) do
		local a = rad(i * 90 + 20)
		local at = CF(T + V(math.cos(a) * 2.45, h, math.sin(a) * 2.45)) * ANG(0, -a, 0) -- tail trails along the turn
		idle(wisp(b, at, 0.95, i % 2 == 0 and UY.Spirit or UY.Glow), "Pulse", { Amp = 0.45, Period = 2.2, Phase = i * 0.25 })
	end
	b:Into(b.Model)
	idle(ring, "Spin", { Pivot = CF(T), Axis = "Y", Period = 16 })
	-- graves at the foot: a headstone, a leaning cross, candles and glowing mushrooms between the roots
	headstone(b, CF(-2.6, 0.25, -1.9) * ANG(0, rad(18), 0) * ANG(rad(-6), 0, rad(4)), 0.95, 1.3, 0.24, UY.Stone)
	local cross = CF(2.5, 0.25, -1.7) * ANG(0, rad(-22), 0) * ANG(0, 0, rad(-8))
	b:Box(V(0.22, 1.5, 0.2), cross * CF(0, 0.75, 0), UY.Wood, "Wood")
	b:Box(V(0.85, 0.2, 0.2), cross * CF(0, 1.08, 0), UY.Wood, "Wood")
	candle(b, CF(-1.95, 0.32, -2.3), 0.42, 0.18)
	candle(b, CF(1.95, 0.32, -2.15), 0.3, 0.16)
	b:Detail(function()
		for i, p in ipairs({ V(-1.4, 0.32, 0.0), V(1.5, 0.3, 0.3), V(-0.8, 0.3, 2.6) }) do
			local h = 0.3 + i * 0.07
			b:CylY(h, 0.1, CF(p + V(0, h / 2, 0)), UY.Bone, "SmoothPlastic")
			b:Accent(b:Ellipsoid(V(0.36, 0.16, 0.36), CF(p + V(0, h, 0)), UY.Glow, "Neon"))
		end
	end)
end

-- Haunted Kennel (Small): a crooked doghouse; the door creaks to and fro in front of a dark doorway where two
-- eyes blink. A dog-skull plaque, a flickering lantern on the gable and a food bowl with a bone.
recipes.uy_haunted_kennel = function(b)
	b:Box(V(3.0, 0.16, 1.9), CF(0, 0.08, 0.15), UY.Soil, "Ground")
	local body = CF(0, 0.94, 0.15) * ANG(0, 0, rad(2))
	b:Box(V(2.3, 1.56, 1.35), body, UY.WoodLight, "WoodPlanks")
	for _, x in ipairs({ -1.15, 1.15 }) do
		b:Box(V(0.18, 1.62, 0.18), body * CF(x, 0, -0.66), UY.Wood, "Wood")
	end
	-- gable roof (ridge front to back), the gable wall and a ridge cap
	local top = body * CF(0, 0.78, 0)
	for _, side in ipairs({ -1, 1 }) do
		b:Box(V(1.78, 0.14, 1.75), top * CF(side * 0.66, 0.53, 0) * ANG(0, 0, rad(side * -37)), UY.Night, "Slate")
	end
	spike(b, top * CF(0, 0, -0.65), 2.3, 0.88, 0.1, UY.WoodLight, "WoodPlanks")
	b:Box(V(0.22, 0.16, 1.85), top * CF(0, 1.02, 0), UY.Iron, "Metal")
	-- the doorway: darkness with two blinking eyes
	b:Box(V(0.8, 0.82, 0.06), body * CF(0, -0.37, -0.69), UY.Ink, "SmoothPlastic")
	b:CylZ(0.06, 0.8, body * CF(0, 0.04, -0.69), UY.Ink, "SmoothPlastic")
	for _, x in ipairs({ -0.15, 0.15 }) do
		idle(b:Accent(b:Ball(0.14, body * CF(x, 0.02, -0.73), UY.Ghost, "Neon")), "Blink", { Period = 3.6, Phase = 0.2 })
	end
	-- the creaking half door (a stable door: the eyes stay visible above it), hinged left, standing ajar
	local hinge = body * CF(-0.4, -0.52, -0.74)
	local ajar = hinge * ANG(0, rad(32), 0)
	local door = b:Folder("Door")
	b:Box(V(0.78, 0.52, 0.07), ajar * CF(0.39, 0, 0), UY.Wood, "WoodPlanks")
	for _, y in ipairs({ -0.14, 0.14 }) do
		b:Box(V(0.8, 0.07, 0.09), ajar * CF(0.4, y, 0), UY.Iron, "Metal")
	end
	b:Into(b.Model)
	idle(door, "Swing", { Pivot = hinge, Axis = "Y", Amp = 9, Period = 3.4 })
	-- dog-skull plaque and a little lantern on the gable
	dogSkull(b, top * CF(0, 0.36, -0.74), 0.55, UY.Bone, UY.Glow)
	path(b, { (top * CF(0.75, -0.06, -0.62)).Position, (top * CF(0.75, -0.06, -0.92)).Position, (top * CF(0.75, -0.24, -0.92)).Position }, { 0.05, 0.04 }, UY.Iron, "Metal")
	idle(b:Accent(b:Box(V(0.2, 0.26, 0.2), top * CF(0.75, -0.38, -0.92), UY.Candle, "Neon")), "Flicker", { Amp = 0.6 })
	-- food bowl with a bone
	b:CylY(0.24, 0.66, CF(1.0, 0.28, -0.58), C(120, 40, 52), "SmoothPlastic")
	b:CylY(0.04, 0.52, CF(1.0, 0.41, -0.58), UY.Ink, "SmoothPlastic")
	b:Cyl(0.5, 0.1, CF(1.0, 0.46, -0.58) * ANG(0, rad(30), rad(12)), UY.Bone, "SmoothPlastic")
	for _, x in ipairs({ -0.26, 0.26 }) do
		b:Ball(0.15, CF(1.0, 0.46, -0.58) * ANG(0, rad(30), rad(12)) * CF(x, 0, 0), UY.Bone, "SmoothPlastic")
	end
	b:Detail(function()
		-- claw scratches by the door, a round side window, moss
		for i = 0, 2 do
			b:Box(V(0.035, 0.4, 0.03), body * CF(0.62 + i * 0.1, -0.35, -0.685) * ANG(0, 0, rad(-14)), C(150, 124, 108), "Wood")
		end
		b:Cyl(0.06, 0.42, body * CF(1.16, 0.15, 0.2), UY.Ink, "SmoothPlastic")
		b:Ellipsoid(V(0.7, 0.2, 0.5), CF(-1.1, 0.18, -0.45), UY.Moss, "Grass")
	end)
end

-- Spirit Fence (Small, Dex II milestone 5): a crooked bone fence between two dog-skull posts, a spectral chain,
-- and three ghost wisps drifting above it.
recipes.uy_spirit_fence = function(b)
	b:Box(V(3.1, 0.14, 0.9), CF(0, 0.07, 0), UY.Soil, "Ground")
	for _, x in ipairs({ -1.24, 1.24 }) do
		b:Box(V(0.42, 1.95, 0.42), CF(x, 1.1, 0), UY.Stone, "Slate")
		b:Box(V(0.56, 0.16, 0.56), CF(x, 2.14, 0), UY.Slate, "Slate")
		dogSkull(b, CF(x, 2.5, -0.02) * ANG(0, rad(x > 0 and -14 or 14), 0), 0.62, UY.Bone, UY.Ghost)
	end
	for i, x in ipairs({ -0.66, -0.22, 0.22, 0.66 }) do
		local h = 1.45 + ((i * 37) % 4) * 0.12
		local cf = CF(x, 0.14, 0) * ANG(0, 0, rad((i % 2 == 0 and 1 or -1) * (1.5 + i * 0.6)))
		b:CylY(h, 0.17, cf * CF(0, h / 2, 0), UY.Bone, "SmoothPlastic")
		b:Ellipsoid(V(0.34, 0.22, 0.24), cf * CF(0, h, 0), UY.BoneShade, "SmoothPlastic")
	end
	for _, y in ipairs({ 0.55, 1.3 }) do
		b:Rod(V(-1.05, y, 0.04), V(1.05, y + 0.05, 0.04), 0.09, UY.Iron, "Metal")
	end
	b:Detail(function()
		for k = 1, 5 do
			local t = k / 6
			local p = V(-1.24 + 2.48 * t, 2.12 - math.sin(t * math.pi) * 0.42, -0.24)
			b:Accent(b:Ellipsoid(V(0.28, 0.14, 0.08), CF(p) * ANG(k % 2 == 0 and math.pi / 2 or 0, 0, rad((t - 0.5) * 60)), UY.Ghost, "Neon", { Transparency = 0.35 }))
		end
	end)
	for i, p in ipairs({ V(-0.55, 3.0, -0.1), V(0.25, 3.45, 0.05), V(0.85, 2.85, -0.05) }) do
		local group = b:Folder("Wisp" .. i)
		local at = CF(p) * ANG(0, rad(i == 1 and 100 or -100), 0) -- tails trail towards the middle
		wisp(b, at, 0.78, i == 2 and UY.Spirit or UY.Ghost)
		b:Into(b.Model)
		idle(group, "Bob", { Pivot = CF(p), Amp = 0.28, Period = 3.2 + i * 0.45, Phase = i * 0.3, Turn = 12 })
	end
end

-- Coffin Flowerbed (Small): an open coffin turned planter, blue funeral roses and glowing bell flowers, a silver
-- cross on the head board and two candles at its foot.
recipes.uy_coffin_flowerbed = function(b)
	local wood, trim = C(58, 40, 46), C(150, 140, 160)
	local outline = { V(-1.5, 0, -0.42), V(-0.65, 0, -0.72), V(1.5, 0, -0.5), V(1.5, 0, 0.5), V(-0.65, 0, 0.72), V(-1.5, 0, 0.42) }
	for i = 1, #outline do
		local a, c = outline[i], outline[i % #outline + 1]
		local mid = (a + c) / 2
		local len = (c - a).Magnitude
		b:Box(V(len + 0.12, 0.6, 0.14), CF(mid.X, 0.3, mid.Z) * ANG(0, -math.atan2(c.Z - a.Z, c.X - a.X), 0), wood, "WoodPlanks")
	end
	b:Box(V(2.1, 0.44, 1.12), CF(0.42, 0.24, 0), UY.Soil, "Ground")
	b:Box(V(0.9, 0.44, 0.92), CF(-1.0, 0.24, 0), UY.Soil, "Ground")
	b:Box(V(0.08, 0.62, 0.08), CF(-1.5, 0.82, 0), trim, "Metal")
	b:Box(V(0.08, 0.08, 0.38), CF(-1.5, 0.95, 0), trim, "Metal")
	for i, p in ipairs({ V(-0.95, 0, -0.18), V(-0.25, 0, 0.22), V(0.55, 0, -0.2), V(1.15, 0, 0.18) }) do
		local h = 0.5 + ((i * 29) % 3) * 0.13
		local cf = CF(p.X, 0.46, p.Z) * ANG(rad((i % 2) * 8 - 4), 0, rad((i % 3 - 1) * 7))
		b:CylY(h, 0.07, cf * CF(0, h / 2, 0), UY.Leaf, "SmoothPlastic")
		b:Ellipsoid(V(0.36, 0.26, 0.36), cf * CF(0, h + 0.06, 0), UY.Rose, "SmoothPlastic")
		b:Ball(0.2, cf * CF(0, h + 0.15, 0), UY.RoseDark, "SmoothPlastic")
	end
	for i, p in ipairs({ V(-0.55, 0, 0.3), V(0.15, 0, -0.32), V(0.95, 0, 0.32) }) do
		local h = 0.38 + i * 0.06
		b:CylY(h, 0.06, CF(p.X, 0.46 + h / 2, p.Z), UY.Leaf, "SmoothPlastic")
		idle(b:Accent(b:Ellipsoid(V(0.22, 0.28, 0.22), CF(p.X, 0.5 + h, p.Z), i == 2 and UY.Ghost or UY.Glow, "Neon")), "Pulse", { Amp = 0.55, Period = 2.6, Phase = i * 0.3 })
	end
	for i, p in ipairs({ V(-0.4, 0.47, -0.42), V(0.85, 0.47, 0.05), V(-1.15, 0.47, 0.32) }) do
		b:Ellipsoid(V(0.42, 0.06, 0.2), CF(p) * ANG(0, rad(i * 55), 0), UY.Leaf, "SmoothPlastic")
	end
	candle(b, CF(1.42, 0, -0.78), 0.5, 0.18)
	candle(b, CF(1.42, 0, 0.78), 0.34, 0.16)
	b:Detail(function()
		for _, x in ipairs({ -0.2, 0.75 }) do
			b:Box(V(0.36, 0.08, 0.06), CF(x, 0.36, -0.68), trim, "Metal")
		end
	end)
end

-- Floating Tombstones (Small): a grave mound in a violet rune ring; three tombstones (round, cross, small) hover
-- above it and bob, each trailing a clod of earth and a ghostly glow.
recipes.uy_floating_tombstones = function(b)
	b:Ellipsoid(V(3.1, 0.38, 1.85), CF(0, 0.1, 0), UY.Soil, "Ground")
	b:Ellipsoid(V(2.5, 0.26, 1.4), CF(0, 0.16, 0), UY.Moss:Lerp(UY.Soil, 0.5), "Grass")
	idle(b:Accent(b:Ellipsoid(V(2.75, 0.04, 1.6), CF(0, 0.29, 0), UY.Violet, "Neon", { Transparency = 0.4 })), "Pulse", { Amp = 0.5, Period = 3.0 })
	b:Ellipsoid(V(2.45, 0.05, 1.3), CF(0, 0.3, 0), UY.Soil, "Ground")
	local function float(name: string, at: CFrame, period: number, phase: number, turn: number, build: (CFrame) -> ())
		local group = b:Folder(name)
		build(at)
		b:Ellipsoid(V(0.62, 0.36, 0.34), at * CF(0.04, -0.2, 0) * ANG(0, rad(20), rad(8)), UY.Soil, "Ground")
		b:Accent(b:Ellipsoid(V(0.6, 0.5, 0.3), at * CF(0, -0.55, 0), UY.Spirit, "Neon", { Transparency = 0.72 }))
		b:Into(b.Model)
		idle(group, "Bob", { Pivot = at, Amp = 0.24, Period = period, Phase = phase, Turn = turn })
	end
	float("StoneRound", CF(0, 1.15, 0.12) * ANG(rad(-5), 0, rad(4)), 3.6, 0, 5, function(at: CFrame)
		headstone(b, at, 0.95, 1.4, 0.24, UY.Stone)
		b:Box(V(0.1, 0.5, 0.04), at * CF(0, 0.72, -0.13), UY.Slate, "Slate")
		b:Box(V(0.34, 0.1, 0.04), at * CF(0, 0.84, -0.13), UY.Slate, "Slate")
		b:Accent(b:Box(V(0.05, 0.42, 0.04), at * CF(0.28, 0.36, -0.13) * ANG(0, 0, rad(20)), UY.Glow, "Neon"))
	end)
	float("StoneCross", CF(-1.05, 0.8, -0.05) * ANG(0, rad(14), rad(-6)), 4.2, 0.35, -6, function(at: CFrame)
		b:Box(V(0.5, 0.24, 0.3), at * CF(0, 0.12, 0), UY.Slate, "Slate")
		b:Box(V(0.24, 1.25, 0.2), at * CF(0, 0.85, 0), UY.Stone, "Slate")
		b:Box(V(0.78, 0.22, 0.2), at * CF(0, 1.1, 0), UY.Stone, "Slate")
	end)
	float("StoneSmall", CF(1.05, 0.88, 0.0) * ANG(rad(4), rad(-18), rad(7)), 3.9, 0.7, 7, function(at: CFrame)
		headstone(b, at, 0.8, 1.05, 0.22, UY.StoneLight:Lerp(UY.Stone, 0.5))
		b:Detail(function()
			b:Ellipsoid(V(0.5, 0.16, 0.3), at * CF(-0.16, 0.95, 0), UY.Moss, "Grass")
		end)
	end)
	b:Detail(function()
		local skull = CF(0.55, 0.36, -0.62) * ANG(0, rad(-25), 0)
		b:Ball(0.3, skull, UY.Bone, "SmoothPlastic")
		for _, x in ipairs({ -0.06, 0.06 }) do
			b:Ball(0.08, skull * CF(x, 0.02, -0.13), UY.Ink, "SmoothPlastic")
		end
	end)
	candle(b, CF(-0.55, 0.28, -0.62), 0.36, 0.15)
	candle(b, CF(-0.35, 0.28, -0.7), 0.22, 0.13)
end

-- Funeral Lantern Set (Small, one light): a crooked iron shepherd's post crowned with a dog skull, two gabled funeral
-- lanterns swinging from its arms, a third lantern on the ground and candles at the footing; every flame flickers.
recipes.uy_funeral_lanterns = function(b)
	local glassColor = C(255, 206, 140)
	b:Box(V(1.1, 0.4, 0.95), CF(-0.6, 0.2, 0.15), UY.Slate, "Slate")
	local P = { V(-0.6, 0.35, 0.15), V(-0.5, 2.2, 0.15), V(-0.7, 3.8, 0.2), V(-0.6, 4.85, 0.15) }
	path(b, P, { 0.3, 0.25, 0.2 }, UY.Iron, "Metal")
	b:CylY(0.16, 0.42, CF(P[2]), UY.Bronze, "Metal")
	dogSkull(b, CF(P[4] + V(0, 0.28, -0.04)), 0.58, UY.Bone, UY.Candle)
	path(b, { V(-0.66, 4.35, 0.17), V(0.2, 4.78, 0.15), V(0.85, 4.62, 0.15), V(0.97, 4.34, 0.15) }, { 0.15, 0.12, 0.1 }, UY.Iron, "Metal")
	path(b, { V(-0.64, 3.55, 0.18), V(-1.12, 3.86, 0.15), V(-1.27, 3.64, 0.15) }, { 0.13, 0.1 }, UY.Iron, "Metal")
	-- a gabled lantern hanging from `hook`; returns its flame
	local function hanging(name: string, hook: Vector3, period: number, phase: number): BasePart
		local group = b:Folder(name)
		local top = hook - V(0, 0.3, 0)
		b:Rod(hook, top, 0.06, UY.Iron, "Metal")
		b:Wedge(V(0.66, 0.3, 0.33), CF(top - V(0, 0.15, 0.165)), UY.Iron, "Metal")
		b:Wedge(V(0.66, 0.3, 0.33), CF(top - V(0, 0.15, -0.165)) * ANG(0, math.pi, 0), UY.Iron, "Metal")
		b:Box(V(0.56, 0.78, 0.56), CF(top - V(0, 0.69, 0)), glassColor, "Glass", { Transparency = 0.4 })
		local fire = b:Accent(b:Ellipsoid(V(0.22, 0.4, 0.22), CF(top - V(0, 0.7, 0)), UY.Candle, "Neon"))
		idle(fire, "Flicker", { Amp = 0.6, Phase = phase })
		b:Box(V(0.64, 0.1, 0.64), CF(top - V(0, 1.12, 0)), UY.Iron, "Metal")
		b:Detail(function()
			for _, x in ipairs({ -0.28, 0.28 }) do
				b:Box(V(0.06, 0.8, 0.06), CF(top + V(x, -0.69, -0.28)), UY.Iron, "Metal")
			end
		end)
		b:Into(b.Model)
		idle(group, "Swing", { Pivot = CF(hook), Axis = "X", Amp = 7, Period = period, Phase = phase })
		return fire
	end
	local flame = hanging("LanternRight", V(0.97, 4.32, 0.15), 2.7, 0)
	hanging("LanternLeft", V(-1.27, 3.62, 0.15), 3.2, 0.45)
	-- a candle lantern on the ground and candles at the footing
	b:Box(V(0.52, 0.08, 0.52), CF(0.95, 0.04, -0.2), UY.Iron, "Metal")
	b:Box(V(0.44, 0.58, 0.44), CF(0.95, 0.37, -0.2), glassColor, "Glass", { Transparency = 0.4 })
	idle(b:Accent(b:Ellipsoid(V(0.16, 0.3, 0.16), CF(0.95, 0.38, -0.2), UY.Candle, "Neon")), "Flicker", { Amp = 0.6, Phase = 0.7 })
	b:Wedge(V(0.52, 0.28, 0.26), CF(0.95, 0.8, -0.33), UY.Iron, "Metal")
	b:Wedge(V(0.52, 0.28, 0.26), CF(0.95, 0.8, -0.07) * ANG(0, math.pi, 0), UY.Iron, "Metal")
	candle(b, CF(-0.95, 0.4, -0.14), 0.44, 0.16)
	candle(b, CF(-0.3, 0.4, -0.18), 0.28, 0.15)
	b:Light(flame, UY.Candle, 14, 1.2)
end

-- Moon Statue (Large): a moonstone dog howling on a stepped plinth; behind it a full moon in an iron ring glows and
-- breathes (the statue's light), with star charms on wires, candles and moon lamps.
recipes.uy_moon_statue = function(b)
	local stone = C(178, 184, 206)
	local stoneShade = C(150, 156, 182)
	b:Box(V(9.0, 0.2, 9.0), CF(0, 0.1, 0.4), UY.Night, "Slate")
	b:Accent(b:CylY(0.04, 7.6, CF(0, 0.21, 0.4), UY.Moon, "Neon", { Transparency = 0.55 }))
	b:CylY(0.05, 7.0, CF(0, 0.22, 0.4), UY.Night, "Slate")
	b:Box(V(5.0, 0.5, 5.0), CF(0, 0.45, 0.4), UY.Slate, "Slate", SOLID)
	b:Box(V(3.8, 1.4, 3.8), CF(0, 1.4, 0.4), UY.Stone, "Slate", SOLID)
	b:Box(V(4.2, 0.3, 4.2), CF(0, 2.25, 0.4), UY.Slate, "Slate")
	-- crescent inlay on the plinth front
	local plaque = CF(0, 1.42, 0.4 - 1.92)
	for k = 0, 3 do
		local a0, a1 = rad(75 + k * 52), rad(75 + (k + 1) * 52)
		b:Accent(b:Rod((plaque * CF(math.cos(a0) * 0.45, math.sin(a0) * 0.45, 0)).Position, (plaque * CF(math.cos(a1) * 0.45, math.sin(a1) * 0.45, 0)).Position, 0.16 - math.abs(k - 1.5) * 0.04, UY.Moon, "Neon"))
	end
	-- the howling dog
	local s = 1.15
	local d = CF(0, 2.4, 0.45)
	local function at(x: number, y: number, z: number): CFrame
		return d * CF(x * s, y * s, z * s)
	end
	b:Ellipsoid(V(1.9, 1.45, 2.1) * s, at(0, 0.72, 0.5), stone, "Marble")
	b:Ellipsoid(V(1.5, 2.1, 1.35) * s, at(0, 1.65, -0.05) * ANG(rad(6), 0, 0), stone, "Marble")
	for _, x in ipairs({ -0.42, 0.42 }) do
		b:CylY(1.4 * s, 0.42 * s, at(x, 0.72, -0.62), stone, "Marble")
		b:Ellipsoid(V(0.5, 0.3, 0.72) * s, at(x, 0.15, -0.82), stoneShade, "Marble")
		b:Ellipsoid(V(0.55, 0.34, 0.95) * s, at(x * 2.15, 0.17, 0.2), stoneShade, "Marble")
	end
	local head = at(0, 3.25, 0.1) * ANG(rad(38), 0, 0)
	b:Ellipsoid(V(0.95, 1.3, 1.0) * s, at(0, 2.6, 0.0) * ANG(rad(24), 0, 0), stone, "Marble")
	b:Ball(1.2 * s, head, stone, "Marble")
	b:Ellipsoid(V(0.6, 0.5, 1.0) * s, head * CF(0, 0.02 * s, -0.68 * s), stone, "Marble")
	b:Ellipsoid(V(0.48, 0.24, 0.8) * s, head * CF(0, -0.32 * s, -0.55 * s) * ANG(rad(-14), 0, 0), stoneShade, "Marble")
	b:Ball(0.26 * s, head * CF(0, 0.1 * s, -1.18 * s), UY.Ink, "SmoothPlastic")
	for _, x in ipairs({ -1, 1 }) do
		b:Ellipsoid(V(0.3, 0.9, 0.48) * s, head * CF(x * 0.36 * s, 0.32 * s, 0.4 * s) * ANG(rad(-55), 0, rad(x * -12)), stoneShade, "Marble")
	end
	b:Detail(function()
		for _, x in ipairs({ -1, 1 }) do
			b:Box(V(0.2, 0.05, 0.05) * s, head * CF(x * 0.24 * s, 0.25 * s, -0.5 * s) * ANG(0, 0, rad(x * 12)), UY.Ink, "SmoothPlastic")
		end
	end)
	path(b, { (at(0.3, 0.3, 1.45)).Position, (at(1.2, 0.2, 1.3)).Position, (at(1.5, 0.3, 0.6)).Position }, { 0.36 * s, 0.26 * s }, stone, "Marble")
	-- the moon in its iron ring, held by a crooked post rising behind the plinth
	local moonAt = CF(0, 8.7, 2.45)
	-- the moon turns very slowly in its ring (its craters drift round) while it breathes light
	local turning = b:Folder("Moon")
	local moon = b:Accent(b:CylZ(0.42, 4.3, moonAt, UY.MoonCore, "Neon"))
	idle(moon, "Pulse", { Amp = 0.28, Period = 4.0 })
	b:Detail(function()
		for _, c in ipairs({ { -0.8, 0.6, 0.9 }, { 0.75, -0.4, 0.7 }, { 0.2, 1.1, 0.5 }, { -0.5, -0.9, 0.45 } }) do
			b:CylZ(0.06, c[3], moonAt * CF(c[1], c[2], -0.23), C(172, 200, 236), "SmoothPlastic")
		end
	end)
	b:Into(b.Model)
	idle(turning, "Spin", { Pivot = moonAt, Axis = "Z", Period = 48 })
	idle(b:Accent(b:CylZ(0.1, 5.3, moonAt * CF(0, 0, 0.3), UY.Moon, "Neon", { Transparency = 0.7 })), "Pulse", { Amp = 0.6, Period = 4.0 })
	b:Ring(moonAt * ANG(math.pi / 2, 0, 0), 2.32, 0.18, UY.Iron, "Metal", 14)
	path(b, { V(0, 2.4, 2.3), V(0.18, 4.4, 2.42), V(-0.1, 6.45, 2.45) }, { 0.32, 0.26 }, UY.Iron, "Metal")
	for _, x in ipairs({ -1, 1 }) do
		b:Rod(V(x * 1.2, 2.4, 2.2), V(x * 1.55, 6.95, 2.45), 0.14, UY.Iron, "Metal")
	end
	-- star charms on wires
	for i, p in ipairs({ V(-3.0, 10.4, 2.45), V(3.1, 9.9, 2.45), V(-3.2, 7.2, 2.45) }) do
		local from = moonAt.Position + (p - moonAt.Position).Unit * 2.4
		b:Rod(from, p, 0.07, UY.Iron, "Metal")
		idle(b:Accent(b:Ball(0.4, CF(p), UY.MoonCore, "Neon")), "Pulse", { Amp = 0.7, Period = 2.2, Phase = i * 0.33 })
	end
	b:Light(moon, UY.Moon, 20, 1.4)
	-- candles at the plinth front, moon lamps at the plaza corners, a wreath of blue roses
	for i, p in ipairs({ V(-1.75, 2.4, -1.25), V(-1.45, 2.4, -1.45), V(1.7, 2.4, -1.35) }) do
		candle(b, CF(p), 0.42 + (i % 2) * 0.22, 0.18)
	end
	for _, x in ipairs({ -3.7, 3.7 }) do
		b:CylY(2.4, 0.2, CF(x, 1.4, -3.5), UY.Iron, "Metal")
		b:CylY(0.2, 0.52, CF(x, 0.3, -3.5), UY.Iron, "Metal")
		idle(b:Accent(b:Ball(0.62, CF(x, 2.85, -3.5), UY.Moon, "Neon")), "Pulse", { Amp = 0.35, Period = 4.0 })
	end
	b:Detail(function()
		for i = 0, 4 do
			local a = rad(200 + i * 35)
			b:Ball(0.32, CF(math.cos(a) * 0.55, 0.84, 0.4 - 2.3 + math.sin(a) * 0.12), i % 2 == 0 and UY.Rose or UY.RoseDark, "SmoothPlastic")
		end
	end)
end

-- Ghost Fountain (Large): an octagonal basin of ghost water, a tiered pedestal crowned by a dog skull, ghost-water
-- arcs that slowly turn around it (top and middle tier), two wisps rising from the water and candles on the rim.
recipes.uy_ghost_fountain = function(b)
	local O = V(0, 0, 0.4)
	b:Box(V(9.0, 0.18, 9.0), CF(0, 0.09, 0.4), UY.Night, "Slate")
	b:CylY(0.06, 8.6, CF(O + V(0, 0.2, 0)), UY.Slate, "Cobblestone")
	local R = 3.3
	for i = 0, 7 do
		local a = rad(i * 45)
		local cf = CF(O + V(math.sin(a) * R, 0, math.cos(a) * R)) * ANG(0, a, 0)
		b:Box(V(2.85, 1.1, 0.42), cf * CF(0, 0.75, 0), UY.Stone, "Slate", SOLID)
		b:Detail(function()
			b:Box(V(2.95, 0.18, 0.62), cf * CF(0, 1.38, 0), UY.Slate, "Slate")
		end)
	end
	b:CylY(0.2, 6.5, CF(O + V(0, 0.3, 0)), UY.Ink, "SmoothPlastic")
	idle(b:Accent(b:CylY(0.06, 6.3, CF(O + V(0, 1.0, 0)), UY.Spirit, "Neon", { Transparency = 0.38 })), "Pulse", { Amp = 0.45, Period = 3.4 })
	-- tiered pedestal
	b:CylY(1.0, 1.9, CF(O + V(0, 0.8, 0)), UY.Stone, "Slate")
	b:CylY(1.6, 0.7, CF(O + V(0, 2.1, 0)), UY.StoneLight, "Slate")
	b:Cone(CF(O + V(0, 2.8, 0)), 0.6, 0.9, 2.6, 2, UY.Stone, "Slate")
	b:Disc(CF(O + V(0, 3.42, 0)), 2.75, 0.16, UY.Slate, "Slate")
	idle(b:Accent(b:Disc(CF(O + V(0, 3.48, 0)), 2.45, 0.06, UY.Spirit, "Neon", { Transparency = 0.3 })), "Pulse", { Amp = 0.45, Period = 3.4, Phase = 0.3 })
	b:CylY(1.3, 0.48, CF(O + V(0, 4.1, 0)), UY.StoneLight, "Slate")
	b:Cone(CF(O + V(0, 4.6, 0)), 0.45, 0.6, 1.55, 2, UY.Stone, "Slate")
	b:Disc(CF(O + V(0, 5.08, 0)), 1.65, 0.12, UY.Slate, "Slate")
	dogSkull(b, CF(O + V(0, 5.5, 0)) * ANG(rad(-8), 0, 0), 0.9, UY.Bone, UY.Spirit, true)
	-- turning ghost-water arcs: four from the top bowl, four from the middle bowl (offset by 45 degrees)
	local arcs = b:Folder("Arcs")
	local function arc(a: number, r0: number, y0: number, r1: number, y1: number, lift: number, n: number, d0: number)
		local pts = {}
		for k = 0, n do
			local t = k / n
			local r = r0 + (r1 - r0) * t
			local y = y0 + (y1 - y0) * t + lift * 4 * t * (1 - t)
			table.insert(pts, O + V(math.sin(a) * r, y, math.cos(a) * r))
		end
		for k = 1, n do
			b:Accent(b:Rod(pts[k], pts[k + 1], d0 - (k - 1) * 0.03, UY.Spirit, "Neon", { Transparency = 0.32 }))
		end
		b:Accent(b:Ellipsoid(V(0.62, 0.12, 0.62), CF(pts[n + 1]), UY.MoonCore, "Neon", { Transparency = 0.45 }))
	end
	for i = 0, 3 do
		arc(rad(i * 90 + 45), 0.72, 5.05, 2.75, 1.05, 1.4, 4, 0.26)
		arc(rad(i * 90), 1.3, 3.45, 2.35, 1.05, 0.55, 3, 0.2)
	end
	b:Into(b.Model)
	idle(arcs, "Spin", { Pivot = CF(O), Axis = "Y", Period = 14 })
	-- wisps rising from the water
	for i, x in ipairs({ -1.55, 1.55 }) do
		local p = O + V(x, 1.75, (i == 1 and -0.5 or 0.55))
		local group = b:Folder("Wisp" .. i)
		wisp(b, CF(p) * ANG(0, rad(i * 120), 0) * ANG(rad(60), 0, 0), 0.9, UY.Spirit)
		b:Into(b.Model)
		idle(group, "Bob", { Pivot = CF(p), Amp = 0.35, Period = 3.8 + i * 0.8, Phase = i * 0.4, Turn = 20 })
	end
	-- candles on the front rim, lily pads with glowing flowers
	for i = -1, 1, 2 do
		local a = rad(180 + i * 45)
		local p = O + V(math.sin(a) * R, 1.38, math.cos(a) * R)
		candle(b, CF(p + V(-0.25 * i, 0.09, 0)), 0.5, 0.18)
		candle(b, CF(p + V(0.22 * i, 0.09, 0.05)), 0.32, 0.16)
	end
	b:Detail(function()
		for i, p in ipairs({ V(-1.9, 1.04, 1.8), V(2.1, 1.04, -1.2), V(0.4, 1.04, 2.5) }) do
			b:Ellipsoid(V(0.8, 0.06, 0.7), CF(O + p) * ANG(0, rad(i * 70), 0), UY.Leaf, "SmoothPlastic")
			b:Accent(b:Ball(0.26, CF(O + p + V(0.1, 0.12, 0)), UY.Glow, "Neon"))
		end
	end)
end

-- Grave Gate (Large): two stone pillars crowned with dog skulls, an iron arch with a little bell, and two wrought-iron
-- gate leaves standing ajar that creak open and shut by themselves; graves and a dead sapling behind.
recipes.uy_grave_gate = function(b)
	b:Box(V(9.4, 0.14, 3.0), CF(0, 0.07, 0), UY.Soil, "Ground")
	b:Box(V(6.4, 0.12, 4.2), CF(0, 0.06, 3.1), UY.Soil:Lerp(UY.Moss, 0.25), "Ground")
	b:Detail(function()
		for i, z in ipairs({ -1.0, 0.1, 1.3, 2.5 }) do
			b:Box(V(1.3 - (i % 2) * 0.2, 0.08, 0.9), CF((i % 2 - 0.5) * 0.2, 0.17, z) * ANG(0, rad((i % 3 - 1) * 7), 0), UY.Stone, "Slate")
		end
	end)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 3.35
		b:Box(V(1.5, 0.5, 1.5), CF(x, 0.39, 0), UY.Slate, "Slate", SOLID)
		b:Box(V(1.1, 5.0, 1.1), CF(x, 3.14, 0), UY.Stone, "Slate", SOLID)
		b:Box(V(1.45, 0.35, 1.45), CF(x, 5.8, 0), UY.Slate, "Slate")
		b:Detail(function()
			b:Box(V(1.24, 0.2, 1.24), CF(x, 2.2, 0), UY.Slate, "Slate")
		end)
		dogSkull(b, CF(x, 6.35, -0.05) * ANG(0, rad(side * -10), 0), 1.05, UY.Bone, UY.Ghost, true)
		-- a glowing paw sigil on the pillar face
		local sigil = CF(x, 3.9, -0.56)
		b:Accent(b:Ellipsoid(V(0.46, 0.4, 0.06), sigil, UY.Glow, "Neon"))
		for k, t in ipairs({ { -0.26, 0.3 }, { 0, 0.4 }, { 0.26, 0.3 } }) do
			b:Accent(b:Ellipsoid(V(0.16, 0.2, 0.06), sigil * CF(t[1], t[2], 0) * ANG(0, 0, rad((k - 2) * -18)), UY.Glow, "Neon"))
		end
		candle(b, CF(x - side * 0.15, 0.64, -0.62), 0.45, 0.18)
	end
	-- the iron arch and its little bell
	local n = 6
	local last: Vector3? = nil
	for k = 0, n do
		local a = math.pi * k / n
		local p = V(math.cos(a) * 2.7, 5.95 + math.sin(a) * 1.95, 0)
		if last then
			b:Rod(last, p, 0.16, UY.Iron, "Metal")
		end
		last = p
	end
	local hook = V(0, 7.85, 0)
	local bell = b:Folder("ArchBell")
	b:Rod(hook, hook - V(0, 0.35, 0), 0.05, UY.Iron, "Metal")
	b:Ellipsoid(V(0.46, 0.3, 0.46), CF(hook - V(0, 0.42, 0)), UY.Bronze, "Metal")
	b:Cone(CF(hook - V(0, 1.0, 0)), 0.58, 0.66, 0.42, 2, UY.Bronze, "Metal")
	b:Disc(CF(hook - V(0, 0.98, 0)), 0.74, 0.06, C(104, 78, 50), "Metal")
	b:Ball(0.16, CF(hook - V(0, 1.08, 0)), UY.Iron, "Metal")
	b:Into(b.Model)
	idle(bell, "Swing", { Pivot = CF(hook), Axis = "X", Amp = 10, Period = 2.4 })
	-- the two gate leaves, hinged at the pillars and standing ajar inwards
	local function leaf(name: string, side: number, rest: number, period: number, phase: number)
		local hinge = CF(side * 2.78, 0, 0)
		local f = hinge * ANG(0, rad(rest), 0)
		local group = b:Folder(name)
		local dir = -side -- along local X towards the middle
		local L = 2.62
		b:Box(V(0.16, 4.0, 0.16), f * CF(dir * 0.08, 2.3, 0), UY.Iron, "Metal")
		b:Box(V(0.14, 3.55, 0.14), f * CF(dir * (L - 0.07), 2.08, 0), UY.Iron, "Metal")
		for _, y in ipairs({ 0.62, 2.2, 3.55 }) do
			b:Box(V(L, 0.12, 0.1), f * CF(dir * L / 2, y, 0), UY.Iron, "Metal")
		end
		for k = 1, 4 do
			local x = dir * L * k / 5
			local h = 4.3 - 0.44 * k / 5 + 0.22 + (k % 2) * 0.12
			b:Box(V(0.07, h - 0.3, 0.07), f * CF(x, 0.3 + (h - 0.3) / 2, 0), UY.Iron, "Metal")
			b:Ball(0.16, f * CF(x, h + 0.04, 0), UY.Iron, "Metal")
		end
		path(b, { (f * CF(dir * 0.1, 4.3, 0)).Position, (f * CF(dir * L * 0.5, 4.0, 0)).Position, (f * CF(dir * (L - 0.07), 3.86, 0)).Position }, { 0.1, 0.09 }, UY.Iron, "Metal")
		b:CylZ(0.08, 0.72, f * CF(dir * L * 0.5, 2.9, 0), UY.Iron, "Metal")
		b:Accent(b:CylZ(0.1, 0.24, f * CF(dir * L * 0.5, 2.9, 0), UY.Glow, "Neon"))
		b:Into(b.Model)
		idle(group, "Swing", { Pivot = hinge, Axis = "Y", Amp = 6, Period = period, Phase = phase })
	end
	leaf("GateLeft", -1, -14, 5.2, 0)
	leaf("GateRight", 1, 20, 4.6, 0.5)
	-- fence stubs beyond the pillars
	for _, side in ipairs({ -1, 1 }) do
		for _, x in ipairs({ 4.25, 4.7 }) do
			b:Box(V(0.08, 2.0, 0.08), CF(side * x, 1.1, 0), UY.Iron, "Metal")
		end
		b:Box(V(0.68, 0.1, 0.08), CF(side * 4.45, 1.75, 0), UY.Iron, "Metal")
	end
	-- graves and a dead sapling behind the gate
	headstone(b, CF(-1.9, 0.12, 3.6) * ANG(0, rad(10), 0) * ANG(rad(-5), 0, rad(5)), 0.9, 1.3, 0.22, UY.Stone)
	headstone(b, CF(1.9, 0.12, 3.1) * ANG(0, rad(-14), 0) * ANG(rad(4), 0, rad(-6)), 0.8, 1.1, 0.22, UY.StoneLight:Lerp(UY.Stone, 0.6))
	path(b, { V(-3.6, 0.12, 3.9), V(-3.5, 1.8, 3.85), V(-3.75, 3.1, 3.9) }, { 0.3, 0.2 }, UY.Bark, "Wood")
	path(b, { V(-3.5, 1.8, 3.85), V(-2.9, 2.6, 3.7) }, { 0.12 }, UY.Bark, "Wood")
	path(b, { V(-3.62, 2.5, 3.88), V(-4.2, 3.2, 4.0) }, { 0.1 }, UY.Bark, "Wood")
	b:Detail(function()
		local crow = CF(3.35, 6.35, 0.45) * ANG(0, rad(160), 0)
		b:Ellipsoid(V(0.42, 0.46, 0.78), crow * CF(0, 0.6, 0), UY.Ink, "SmoothPlastic")
		b:Ball(0.36, crow * CF(0, 0.9, -0.32), UY.Ink, "SmoothPlastic")
		b:Wedge(V(0.1, 0.12, 0.26), crow * CF(0, 0.88, -0.6) * ANG(0, math.pi, 0), C(170, 150, 90), "SmoothPlastic")
	end)
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
	-- tag models with idle animations so the client loop finds them without walking every decoration
	local animated = 0
	for _, d in model:GetDescendants() do
		if d:GetAttribute("IdleAnim") ~= nil then
			animated += 1
		end
	end
	if animated > 0 then
		model:SetAttribute("DecorIdle", animated)
	end
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
