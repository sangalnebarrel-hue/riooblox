-- MineLevels: Forge recipes of the four mine level interiors (client-built on demand by
-- MineClient), in YARD DESIGN coordinates (MineLayout). One call builds one level:
--   local model = MineLevels.Build(layer, { LowFX = false })
--   MineStructures.Place(model, layout)   -- into one yard's world
-- Every level has: themed walls, floor and ceiling over the server shell, an elevator landing with
-- the call panel (Attachment "StopAnchor" on part "CallPanel"), the FINDS board (SurfaceGui
-- "FindsBoard", one cell per DepthDefinitions item: Frame "Item_<id>"), three item pedestals
-- (Attachments "Pedestal1..3"), five dog worksites with an ore vein of that layer's loot table, and
-- the level's own props and effects, then the shared dressing pass (relief, niches and cracks, timber
-- supports and old mine gear, a lamp line, roots, glowing spots, ground fog and dust; dressing()).
-- Budget per level (tests/mine.luau): <= 560 parts, <= 8 lights, <= 8 particle emitters. Animated parts carry attributes the client tweens (MineBob = amplitude in
-- studs, MineBobPeriod = seconds): nothing runs per frame.
local RS = game:GetService("ReplicatedStorage")
local Forge = require(RS:WaitForChild("Forge"))
local Layout = require(script.Parent:WaitForChild("MineLayout"))
local Themes = require(script.Parent:WaitForChild("MineThemes"))

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local Levels = {}
Levels.Budget = { Parts = 560, Lights = 8, Emitters = 8 }

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local IRON = C(70, 74, 82)
local SAFETY = C(244, 192, 44)
local TIMBER = C(122, 82, 50)
local TIMBER_DARK = C(86, 56, 34)

-- Deterministic random numbers (the same level looks the same for every player).
local function rng(seed: number)
	local s = seed % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function(a: number?, b: number?): number
		s = (s * 48271) % 2147483647
		local x = s / 2147483647
		if a and b then
			return a + (b - a) * x
		end
		return x
	end
end

local function facing(pos: Vector3, dx: number, dz: number): CFrame
	return Layout.Facing(pos, V(dx, 0, dz))
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- An invisible emission volume (emitters spawn inside their part's box).
local function volume(b: any, name: string, size: Vector3, cf: CFrame): BasePart
	return b:Box(size, cf, C(255, 255, 255), "SmoothPlastic", { Name = name, Transparency = 1, CastShadow = false })
end

------------------------------------------------------------------------------------------------
-- Shared pieces
------------------------------------------------------------------------------------------------
local function walls(b: any, ctx: any)
	local t, R, F, H = ctx.Theme, ctx.R, ctx.F, ctx.H
	local c = Layout.Chamber
	local mat = t.RockMaterial
	local tones = { t.Rock, t.RockDark, t.RockLight or t.Rock }
	-- Liners over the server shell: the level's own floor, ceiling and wall colours.
	local sx = Layout.Shaft
	local cx, cz, w, d = (c.X0 + c.X1) / 2, (c.Z0 + c.Z1) / 2, c.X1 - c.X0, c.Z1 - c.Z0
	local fm0 = t.FloorMaterial or mat
	b:Box(V(w, 0.1, d), CF(cx, F + 0.05, cz), t.Floor:Lerp(t.RockDark, 0.2), fm0, { Name = "FloorLiner", CastShadow = false })
	b:Box(V(w, 0.2, d), CF(cx, ctx.Top - 0.1, cz), t.RockDark, mat, { Name = "CeilingLiner", CastShadow = false })
	b:Box(V(0.2, H, d), CF(c.X0 + 0.1, F + H / 2, cz), t.RockDark, mat, { Name = "WallLiner", CastShadow = false })
	b:Box(V(0.2, H, d), CF(c.X1 - 0.1, F + H / 2, cz), t.RockDark, mat, { Name = "WallLiner", CastShadow = false })
	b:Box(V(w, H, 0.2), CF(cx, F + H / 2, c.Z1 - 0.1), t.RockDark, mat, { Name = "WallLiner", CastShadow = false })
	local nearW = sx.X - sx.Half - c.X0
	b:Box(V(nearW, H, 0.2), CF(c.X0 + nearW / 2, F + H / 2, c.Z0 + 0.1), t.RockDark, mat, { Name = "WallLiner", CastShadow = false })
	b:Box(V(c.X1 - sx.X - sx.Half, H, 0.2), CF((sx.X + sx.Half + c.X1) / 2, F + H / 2, c.Z0 + 0.1), t.RockDark, mat, { Name = "WallLiner", CastShadow = false })
	-- Side walls (x' = X0 / X1): slabs leaning out of the wall, between and behind the worksites.
	for _, side in { -1, 1 } do
		local wx = side < 0 and c.X0 or c.X1
		for i = 0, 5 do
			local z = c.Z0 + 4 + i * 7.8 + R(-1.2, 1.2)
			local hgt = H * R(0.55, 1.0)
			local depth = R(2.6, 4.2)
			local cf = CF(wx - side * depth * 0.3, F + hgt / 2 - 0.5, z) * ANG(rad(R(-6, 6)), rad(R(-14, 14)), rad(side * R(2, 8)))
			b:Box(V(depth, hgt, R(6.5, 9.5)), cf, tones[(i % 3) + 1], mat, { Name = "WallRock" })
		end
	end
	-- Far wall (z' = Z1).
	for i = 0, 5 do
		local x = c.X0 + 4 + i * 8.6 + R(-1.5, 1.5)
		local hgt = H * R(0.5, 1.0)
		local depth = R(2.6, 4.4)
		local cf = CF(x, F + hgt / 2 - 0.5, c.Z1 - depth * 0.3) * ANG(rad(R(-8, -2)), rad(R(-14, 14)), rad(R(-6, 6)))
		b:Box(V(R(6.5, 9.5), hgt, depth), cf, tones[((i + 1) % 3) + 1], mat, { Name = "WallRock" })
	end
	-- Near wall west of the board (the board, landing and shaft take x' 0..26).
	for i = 0, 2 do
		local x = c.X0 + 3.5 + i * 7.5
		local hgt = H * R(0.6, 1.0)
		local cf = CF(x, F + hgt / 2 - 0.5, c.Z0 + 1) * ANG(rad(R(2, 8)), rad(R(-12, 12)), 0)
		b:Box(V(R(6, 8), hgt, 3.2), cf, tones[(i % 3) + 1], mat, { Name = "WallRock" })
	end
	-- Floor: large flat patches in the floor tones and rubble along the walls.
	local fm = t.FloorMaterial or mat
	for i = 1, 5 do
		local cf = CF(R(c.X0 + 8, c.X1 - 8), F + 0.06 + i * 0.01, R(c.Z0 + 8, c.Z1 - 6)) * ANG(0, rad(R(0, 180)), 0)
		b:Box(V(R(10, 18), 0.12, R(7, 13)), cf, (i % 2 == 0) and t.Floor or (t.Floor:Lerp(t.RockDark, 0.35)), fm, { Name = "FloorPatch", CastShadow = false })
	end
	ctx.Detail(function()
		for i = 1, 10 do
			local side = i % 2 == 0 and -1 or 1
			local x = side < 0 and c.X0 + R(1.5, 3) or c.X1 - R(1.5, 3)
			local z = R(c.Z0 + 4, c.Z1 - 2)
			local s = R(0.9, 2.2)
			b:Ellipsoid(V(s * 1.4, s, s * 1.2), CF(x, F + s * 0.35, z) * ANG(0, rad(R(0, 180)), 0), tones[(i % 3) + 1], mat, { Name = "Rubble" })
		end
	end)
end

-- Elevator landing, call panel (prompt anchor), FINDS board and the item pedestals.
local function landing(b: any, ctx: any)
	local t, F = ctx.Theme, ctx.F
	local s = Layout.Shaft
	local z0 = s.Z + s.Half -- -32: the chamber's near wall
	b:Box(V(10.4, 0.3, 4.2), CF(s.X, F + 0.15, z0 + 2.1), IRON, "DiamondPlate", { Name = "LandingDeck", CastShadow = false })
	b:Box(V(10.4, 0.06, 0.4), CF(s.X, F + 0.33, z0 + 4.0), SAFETY, "SmoothPlastic", { Name = "LandingStripe", CastShadow = false })
	for _, x in { s.X - s.Half - 0.6, s.X + s.Half + 0.6 } do
		b:Box(V(0.8, 9.4, 0.8), CF(x, F + 4.7, z0 + 0.3), SAFETY, "Metal", { Name = "LandingPost", CanCollide = true })
	end
	local panel = b:Box(V(1.1, 1.7, 0.3), CF(s.X - s.Half - 2.2, F + 3.3, z0 + 0.3), C(50, 54, 60), "Metal", { Name = "CallPanel" })
	b:Box(V(0.36, 0.36, 0.1), panel.CFrame * CF(0, 0.35, 0.18), C(90, 255, 130), "Neon", { Name = "CallLamp", CastShadow = false })
	b:Box(V(0.36, 0.36, 0.1), panel.CFrame * CF(0, -0.25, 0.18), C(255, 200, 70), "Neon", { Name = "CallLamp", CastShadow = false })
	local anchor = Instance.new("Attachment")
	anchor.Name = "StopAnchor"
	anchor.Position = V(0, 0, 1.2)
	anchor.Parent = panel
	-- Landing lamp (one of the level's lights).
	local lamp = b:Box(V(1.2, 0.5, 0.7), CF(s.X, F + 10.6, z0 + 0.9), C(255, 230, 180), "Neon", { Name = "LandingLamp", CastShadow = false })
	local light = b:Light(lamp, C(255, 222, 170), 26, 1.3, "Spot")
	;(light :: SpotLight).Face = Enum.NormalId.Bottom
	;(light :: SpotLight).Angle = 100

	-- FINDS board on the near wall: one cell per item of this depth (DepthDefinitions).
	local bx, bw, bh = 6.6, 12, 6.2
	local frameColor = t.RockDark:Lerp(C(0, 0, 0), 0.25)
	local board = b:Box(V(bw, bh, 0.3), CF(bx, F + 1.4 + bh / 2, z0 + 0.35), C(24, 22, 26), "SmoothPlastic", { Name = "FindsBoard" })
	for _, row in { { 0, bh / 2 + 0.2, bw + 0.8, 0.4 }, { 0, -bh / 2 - 0.2, bw + 0.8, 0.4 }, { -bw / 2 - 0.2, 0, 0.4, bh }, { bw / 2 + 0.2, 0, 0.4, bh } } do
		b:Box(V(row[3], row[4], 0.5), board.CFrame * CF(row[1], row[2], 0), frameColor, t.RockMaterial, { Name = "BoardFrame" })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FindsBoardGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 44
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Name = "Back"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C(18, 16, 22)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = t.Accent
	stroke.Thickness = 5
	stroke.Parent = bg
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.03, 0.02)
	title.Size = UDim2.fromScale(0.7, 0.13)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = t.Accent
	title.Text = "FINDS AT THIS DEPTH"
	title.Parent = bg
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromScale(0.72, 0.02)
	count.Size = UDim2.fromScale(0.25, 0.13)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = C(240, 240, 246)
	count.Text = ""
	count:SetAttribute("NoTranslate", true)
	count.Parent = bg
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.03, 0.17)
	grid.Size = UDim2.fromScale(0.94, 0.8)
	grid.Parent = bg
	local items = ctx.Items
	local cols = #items > 20 and 5 or 4
	local rows = math.max(1, math.ceil(#items / cols))
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromScale(0.012, 0.02)
	layout.CellSize = UDim2.fromScale(1 / cols - 0.012, 1 / rows - 0.02)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, id in items do
		local cell = Instance.new("Frame")
		cell.Name = "Item_" .. id
		cell.LayoutOrder = i
		cell.BackgroundColor3 = C(40, 38, 46)
		cell.BorderSizePixel = 0
		cell.Parent = grid
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = cell
		local mark = Instance.new("TextLabel")
		mark.Name = "Mark"
		mark.BackgroundTransparency = 1
		mark.Position = UDim2.fromScale(0.02, 0.1)
		mark.Size = UDim2.fromScale(0.2, 0.8)
		mark.Font = Enum.Font.GothamBlack
		mark.TextScaled = true
		mark.TextColor3 = C(120, 118, 130)
		mark.Text = "?"
		mark:SetAttribute("NoTranslate", true)
		mark.Parent = cell
		local name = Instance.new("TextLabel")
		name.Name = "ItemName"
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromScale(0.22, 0.08)
		name.Size = UDim2.fromScale(0.76, 0.84)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextWrapped = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = C(150, 148, 160)
		name.Text = ctx.ItemName(id)
		name.Parent = cell
	end
	-- Pedestals for three featured finds (models placed by the client on "PedestalN").
	for i = 1, 3 do
		local x = -9.5 + (i - 1) * 3.6
		local base = b:CylY(1.3, 1.9, CF(x, F + 0.65, z0 + 2.4), t.RockLight or t.Rock, t.RockMaterial, { Name = "Pedestal" })
		local top = b:CylY(0.18, 2.2, CF(x, F + 1.38, z0 + 2.4), t.Accent, "Neon", { Name = "PedestalGlow", CastShadow = false })
		local a = Instance.new("Attachment")
		a.Name = "Pedestal" .. i
		a.Position = V(0, 0.09, 0)
		a.Parent = top
		base:SetAttribute("MinePedestal", i)
	end
end

-- The five worksites: a dig pit and the level's ore vein against the wall, a slot plate.
local function worksites(b: any, ctx: any)
	local t, F = ctx.Theme, ctx.F
	for slot, site in Layout.Worksites do
		local dir = site.Dir
		local node = facing(V(site.X + dir * 2.7, F, site.Z), -dir, 0) -- front faces the dog
		ctx.Node(b, ctx, slot, node)
		b:Ellipsoid(V(4.2, 0.5, 5.2), CF(site.X + dir * 0.4, F + 0.02, site.Z), t.RockDark:Lerp(C(0, 0, 0), 0.45), "Ground", { Name = "DigPit", CastShadow = false })
		ctx.Detail(function()
			for k = -1, 1, 2 do
				b:Ellipsoid(V(1.2, 0.7, 1.0), CF(site.X - dir * 1.2, F + 0.25, site.Z + k * 2.6) * ANG(0, k, 0), t.Rock, t.RockMaterial, { Name = "DigSpoil" })
			end
		end)
		local wallX = dir < 0 and Layout.Chamber.X0 or Layout.Chamber.X1
		local plate = b:Box(V(0.2, 1.4, 1.4), CF(wallX - dir * 0.9, F + 7.4, site.Z), C(30, 28, 32), "Metal", { Name = "SlotPlate" })
		local gui = Instance.new("SurfaceGui")
		gui.Face = dir < 0 and Enum.NormalId.Right or Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = t.Accent
		label.Text = tostring(slot)
		label:SetAttribute("NoTranslate", true)
		label.Parent = gui
	end
end

local function stalactites(b: any, ctx: any, count: number, color: Color3, tip: Color3?, mat: string?)
	local R, c = ctx.R, Layout.Chamber
	for i = 1, count do
		local x = R(c.X0 + 3, c.X1 - 3)
		local z = R(c.Z0 + 5, c.Z1 - 3)
		if not (x > 12 and z < -22) then -- keep the landing clear
			-- Dripstone: a wide rounded root in the ceiling and a long narrow spike below it.
			local len = R(3, 7)
			local d = R(1.2, 2.4)
			local m = mat or ctx.Theme.RockMaterial
			b:Ellipsoid(V(d * 1.6, len * 0.7, d * 1.5), CF(x, ctx.Top, z), color, m, { Name = "StalactiteRoot" })
			local spike = b:Ellipsoid(V(d * 0.7, len * 1.3, d * 0.65), CF(x + d * 0.08, ctx.Top - len * 0.35, z), color, m, { Name = "Stalactite" })
			if tip then
				spike.Color = tip
				spike.Material = Enum.Material.Neon
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- CAVERNS: blue-grey rock, stalactites, glowing blue crystals, dripping water, coal and fossils
------------------------------------------------------------------------------------------------
local function crystalCluster(b, cf, scale, color, glow, count)
	local out = {}
	local spec = { { 0, 0, 0, 1.0, 3.2 }, { 0.9, 0, 0.4, 0.7, 2.2 }, { -0.8, 0, 0.5, 0.6, 1.8 }, { 0.2, 0, -0.9, 0.55, 1.6 } }
	for i, s in spec do
		if count and i > count then
			break
		end
		local lean = ANG(rad(s[3] * 22), rad(i * 70), rad(-s[1] * 20))
		local parts = b:Prism(cf * CF(s[1] * scale, 0, s[3] * scale) * lean, s[4] * scale, s[5] * scale, 0.9 * scale * s[4], i == 1 and glow or color, "Glass", { Name = "Crystal", Accent = true })
		for _, p in parts do
			table.insert(out, p)
		end
	end
	return out
end

local function cavernsNode(b, ctx, slot, n)
	local t = ctx.Theme
	-- Rock outcrop backing every vein.
	b:Box(V(5.4, 4.2, 3.0), n * CF(0, 2.0, 0.6) * ANG(rad(-8), 0, rad(4)), t.RockDark, "Slate", { Name = "Outcrop" })
	if slot == 1 then -- quartz crystal vein
		crystalCluster(b, n * CF(0, 1.4, -0.6), 0.75, C(200, 230, 255), C(150, 220, 255))
	elseif slot == 2 then -- coal and iron seam
		for i = 0, 3 do
			b:Box(V(1.2, 0.8, 0.5), n * CF(-1.8 + i * 1.2, 1.2 + (i % 2) * 1.3, -1.0) * ANG(i, i * 0.6, 0), C(26, 26, 30), "Basalt", { Name = "Coal" })
		end
		b:Ball(0.5, n * CF(0.9, 2.9, -1.1), C(176, 120, 92), "Metal", { Name = "IronGlint" })
	elseif slot == 3 then -- fossil bones in the rock
		b:Cyl(3.6, 0.5, n * CF(0, 2.2, -1.0) * ANG(0, 0, rad(12)), t.Floor:Lerp(C(240, 228, 200), 0.75), "Marble", { Name = "FossilSpine" })
		for i = -1, 1 do
			b:Cyl(1.6, 0.28, n * CF(i * 1.0, 2.2 + 0.8, -1.05) * ANG(0, 0, rad(80 + i * 6)), C(234, 222, 194), "Marble", { Name = "FossilRib" })
		end
		b:Ellipsoid(V(1.3, 0.9, 0.8), n * CF(2.0, 2.6, -1.0), C(234, 222, 194), "Marble", { Name = "FossilSkull" })
	elseif slot == 4 then -- gold nuggets
		for i = 0, 3 do
			b:Ellipsoid(V(0.7, 0.5, 0.6), n * CF(-1.4 + i * 0.95, 1.0 + (i % 2) * 1.6, -1.15), Forge.Palette.Gold, "Metal", { Name = "Nugget", Accent = true })
		end
	else -- a split geode with a crystal heart
		b:Ball(2.6, n * CF(0, 1.5, -0.8), C(110, 104, 112), "Slate", { Name = "Geode" })
		crystalCluster(b, n * CF(0, 1.4, -1.6) * ANG(rad(-70), 0, 0), 0.4, C(190, 120, 255), C(210, 150, 255))
	end
end

local function caverns(b: any, ctx: any)
	local t, R, F = ctx.Theme, ctx.R, ctx.F
	stalactites(b, ctx, 11, t.RockLight, nil)
	-- Stalagmites rising from the floor.
	for _, p in { { -8, 6 }, { -14, -6 }, { 4, 9 }, { 10, -8 }, { -3, -12 } } do
		local h, d = R(3.5, 6.5), R(1.8, 2.8)
		b:Ellipsoid(V(d * 1.5, h * 0.8, d * 1.4), CF(p[1], F, p[2]), t.Rock, "Slate", { Name = "StalagmiteBase" })
		b:Ellipsoid(V(d * 0.7, h * 1.5, d * 0.66), CF(p[1] + 0.2, F + h * 0.3, p[2]), t.RockLight, "Slate", { Name = "Stalagmite" })
	end
	-- Ceiling relief under the island.
	for i = 1, 3 do
		b:Ellipsoid(V(R(14, 20), R(3, 5), R(10, 14)), CF(-16 + i * 11, ctx.Top + 0.6, R(-18, 6)), t.RockDark, "Slate", { Name = "CeilingRock" })
	end
	-- Glowing crystal clusters: big ones on the floor (three carry the blue lights), more along
	-- the walls and hanging from the ceiling.
	local clusters = {
		{ -6, -20, 1.9, 4 }, { 9, 10, 2.2, 4 }, { -16, 7, 1.6, 4 }, { 2, -3, 1.3, 3 },
		{ -22.5, -9, 1.4, 3 }, { 24.5, -4, 1.3, 3 }, { 12, 13, 1.5, 3 }, { -10, 13, 1.2, 3 },
	}
	for i, c in clusters do
		local lean = (c[1] < -20 and ANG(0, 0, rad(-28))) or (c[1] > 22 and ANG(0, 0, rad(28))) or (c[2] > 12 and ANG(rad(-25), 0, 0)) or CFrame.identity
		local parts = crystalCluster(b, CF(c[1], F, c[2]) * lean * ANG(0, rad(i * 40), 0), c[3], C(110, 190, 255), t.Glow, c[4])
		if i <= 3 then
			b:Light(parts[1], t.Glow, 22, 1.6, "Point")
		end
	end
	for i, p in { { -12, -10 }, { 6, -14 }, { -2, 6 } } do
		crystalCluster(b, CF(p[1], ctx.Top, p[2]) * ANG(math.pi, rad(i * 50), 0), 1.1, C(130, 200, 255), t.Glow, 3)
	end
	-- Underground pool with dripping water.
	local pool = CF(-6, F, 1)
	b:Ellipsoid(V(13, 0.6, 9), pool * CF(0, 0.05, 0), C(30, 36, 46), "Slate", { Name = "PoolBasin" })
	b:Ellipsoid(V(11.5, 0.2, 7.6), pool * CF(0, 0.32, 0), t.Water, "Glass", { Name = "PoolWater", Transparency = 0.25, Reflectance = 0.2, CastShadow = false })
	local drips = volume(b, "DripSource", V(8, 0.4, 5), CF(-6, ctx.Top - 1.2, 1))
	emitter(drips, {
		Texture = SPARKLE,
		Rate = ctx.LowFX and 1.2 or 3,
		Lifetime = NumberRange.new(1.2, 1.6),
		Speed = NumberRange.new(0, 0.5),
		Acceleration = V(0, -34, 0),
		Size = NumberSequence.new(0.22),
		Color = ColorSequence.new(C(170, 220, 255)),
		LightEmission = 0.6,
		Transparency = NumberSequence.new(0.15),
		EmissionDirection = Enum.NormalId.Bottom,
	})
	local mist = volume(b, "PoolMist", V(11, 1, 7), pool * CF(0, 1.2, 0))
	emitter(mist, {
		Texture = SMOKE,
		Rate = ctx.LowFX and 0.6 or 1.6,
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(0.1, 0.4),
		Size = NumberSequence.new(5, 9),
		Color = ColorSequence.new(C(150, 190, 230)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-10, 10),
	})
	local glints = volume(b, "CrystalGlints", V(40, 6, 30), CF(1, F + 3, -6))
	emitter(glints, {
		Texture = SPARKLE,
		Rate = ctx.LowFX and 2 or 6,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(0, 0.2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(C(160, 220, 255)),
		LightEmission = 1,
	})
	-- Mine cart on a short rail spur and two timber support frames.
	local rail = CF(10, F, -4) * ANG(0, rad(12), 0)
	for _, x in { -0.9, 0.9 } do
		b:Box(V(0.25, 0.25, 16), rail * CF(x, 0.35, 0), C(120, 110, 100), "Metal", { Name = "Rail" })
	end
	for i = -3, 3 do
		b:Box(V(2.8, 0.25, 0.5), rail * CF(0, 0.15, i * 2.3), TIMBER_DARK, "WoodPlanks", { Name = "Sleeper" })
	end
	local cart = rail * CF(0, 0, 3)
	b:Box(V(2.4, 1.6, 3.2), cart * CF(0, 1.5, 0), C(96, 70, 48), "WoodPlanks", { Name = "Cart", CanCollide = true })
	b:Box(V(2.6, 0.25, 3.4), cart * CF(0, 2.35, 0), IRON, "Metal", { Name = "CartRim" })
	for _, p in { { -1.2, -1.0 }, { 1.2, -1.0 }, { -1.2, 1.0 }, { 1.2, 1.0 } } do
		b:Cyl(0.3, 0.9, cart * CF(p[1], 0.65, p[2]), C(40, 40, 44), "Metal", { Name = "CartWheel" })
	end
	for i = 0, 2 do
		b:Ellipsoid(V(0.9, 0.7, 0.9), cart * CF(-0.6 + i * 0.6, 2.55, -0.8 + i * 0.7), i == 1 and C(150, 220, 255) or C(40, 40, 46), i == 1 and "Glass" or "Basalt", { Name = "CartLoad" })
	end
	local lantern = b:Box(V(0.6, 0.8, 0.6), cart * CF(1.4, 3.0, -1.4), C(255, 196, 110), "Neon", { Name = "CartLantern", CastShadow = false })
	b:Light(lantern, C(255, 186, 110), 14, 1.1, "Point")
	for _, z in { -10, 6 } do
		local frame = CF(-2, F, z)
		for _, x in { -5, 5 } do
			b:Box(V(0.8, 14, 0.8), frame * CF(x, 7, 0), TIMBER, "WoodPlanks", { Name = "Prop", CanCollide = true })
		end
		b:Box(V(11.6, 0.9, 0.9), frame * CF(0, 14.2, 0), TIMBER_DARK, "WoodPlanks", { Name = "Cap" })
	end
end

------------------------------------------------------------------------------------------------
-- ANCIENT RUINS: sandstone pillars, glyph walls, broken statues, gold glints, sand dust
------------------------------------------------------------------------------------------------
local function glyphPanel(part: BasePart, face: Enum.NormalId, color: Color3, seed: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Glyphs"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 14
	gui.LightInfluence = 1
	gui.Parent = part
	local R = rng(seed)
	local cols, rows = 7, 5
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local kind = math.floor(R(0, 4))
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale((c + 0.5) / cols, (r + 0.5) / rows)
			if kind == 0 then -- disc (sun)
				f.Size = UDim2.fromScale(0.07, 0.11)
				local k = Instance.new("UICorner")
				k.CornerRadius = UDim.new(0.5, 0)
				k.Parent = f
			elseif kind == 1 then -- standing bar (figure)
				f.Size = UDim2.fromScale(0.025, 0.14)
			elseif kind == 2 then -- diamond (eye)
				f.Size = UDim2.fromScale(0.06, 0.06)
				f.Rotation = 45
			else -- horizon (water)
				f.Size = UDim2.fromScale(0.09, 0.025)
			end
			f.Parent = gui
		end
	end
	return gui
end

local function pottery(b, cf, scale, color)
	b:Ellipsoid(V(1.4, 1.8, 1.4) * scale, cf * CF(0, 0.9 * scale, 0), color, "Sandstone", { Name = "Amphora" })
	b:CylY(0.7 * scale, 0.6 * scale, cf * CF(0, 1.95 * scale, 0), color, "Sandstone", { Name = "AmphoraNeck" })
	b:CylY(0.12 * scale, 0.85 * scale, cf * CF(0, 2.3 * scale, 0), color:Lerp(C(0, 0, 0), 0.2), "Sandstone", { Name = "AmphoraLip" })
end

local function goldPile(b, cf, scale)
	b:Ellipsoid(V(2.6, 0.9, 2.2) * scale, cf * CF(0, 0.3 * scale, 0), Forge.Palette.Gold, "Metal", { Name = "GoldPile", Accent = true })
	for i = 0, 3 do
		local a = i * 1.7
		b:Disc(cf * CF(math.cos(a) * 1.3 * scale, 0.06, math.sin(a) * 1.1 * scale) * ANG(rad(10 * i), 0, rad(8)), 0.55 * scale, 0.08, Forge.Palette.Gold, "Metal", { Name = "Coin", Accent = true })
	end
end

local function ruinsNode(b, ctx, slot, n)
	local t = ctx.Theme
	b:Box(V(5.4, 4.6, 3.0), n * CF(0, 2.2, 0.6) * ANG(rad(-6), 0, rad(-3)), t.RockDark, "Sandstone", { Name = "Outcrop" })
	if slot == 1 then -- stone tablet with glyphs
		local tab = b:Box(V(2.6, 3.2, 0.5), n * CF(0, 2.0, -1.1) * ANG(rad(-8), 0, 0), C(150, 144, 132), "Slate", { Name = "Tablet" })
		glyphPanel(tab, Enum.NormalId.Front, C(70, 62, 52), 31)
	elseif slot == 2 then -- golden idol in a niche
		b:Box(V(1.2, 0.5, 1.2), n * CF(0, 1.1, -1.0), t.RockLight, "Sandstone", { Name = "IdolBase" })
		b:Ellipsoid(V(0.9, 1.4, 0.8), n * CF(0, 2.0, -1.0), Forge.Palette.Gold, "Metal", { Name = "Idol", Accent = true })
		b:Ball(0.8, n * CF(0, 2.95, -1.0), Forge.Palette.Gold, "Metal", { Name = "IdolHead", Accent = true })
		b:Box(V(0.14, 0.14, 0.1), n * CF(0, 3.0, -1.42), C(40, 220, 140), "Neon", { Name = "IdolEye" })
	elseif slot == 3 then -- ancient coin cache
		goldPile(b, n * CF(0, 0.2, -1.2), 0.8)
		b:Box(V(1.6, 1.0, 1.1), n * CF(1.2, 0.5, -0.4) * ANG(0, 0.4, 0), C(110, 72, 40), "WoodPlanks", { Name = "Chest" })
	elseif slot == 4 then -- pottery
		pottery(b, n * CF(-0.9, 0, -1.0), 0.8, C(176, 104, 64))
		pottery(b, n * CF(0.8, 0, -1.2) * ANG(0, 0, rad(70)), 0.65, C(196, 128, 76))
	else -- statue fragment: a giant stone paw
		b:Ellipsoid(V(3.0, 1.4, 2.4), n * CF(0, 0.7, -1.0), t.RockLight, "Sandstone", { Name = "StatuePaw" })
		for i = -1, 1 do
			b:Ball(0.8, n * CF(i * 0.9, 0.7, -2.1), t.RockLight, "Sandstone", { Name = "StatueToe" })
		end
	end
end

local function ruins(b: any, ctx: any)
	local t, R, F, H = ctx.Theme, ctx.R, ctx.F, ctx.H
	local top = ctx.Top
	-- Colonnade: six pillars (two broken) with bases and capitals.
	local pillars = { { -12, -18, false }, { 6, -18, true }, { -12, -4, false }, { 6, -4, false }, { -12, 9, true }, { 6, 9, false } }
	for i, p in pillars do
		local base = CF(p[1], F, p[2])
		b:Box(V(3.4, 0.9, 3.4), base * CF(0, 0.45, 0), t.RockDark, "Sandstone", { Name = "PillarBase", CanCollide = true })
		local height = p[3] and R(5, 9) or H - 1.6
		b:CylY(height, 2.5, base * CF(0, 0.9 + height / 2, 0), t.Rock, "Sandstone", { Name = "Pillar", CanCollide = true })
		if not p[3] then
			b:Box(V(3.4, 0.8, 3.4), base * CF(0, H - 0.4, 0), t.RockDark, "Sandstone", { Name = "Capital" })
		else
			-- the fallen drum lies beside it
			b:Cyl(4, 2.4, CF(p[1] + 3.2, F + 1.2, p[2] + 1.5) * ANG(0, rad(30 + i * 20), 0), t.Rock, "Sandstone", { Name = "FallenDrum", CanCollide = true })
		end
	end
	-- Lintel beams across the colonnade.
	for _, z in { -18, -4, 9 } do
		b:Box(V(20, 1.2, 1.6), CF(-3, top - 0.6, z), t.RockDark, "Sandstone", { Name = "Lintel" })
	end
	-- Glyph walls: tall panels on the far wall and the west wall, glyphs in gold leaf.
	local eastPanel = b:Box(V(0.6, 8, 14), CF(Layout.Chamber.X1 - 1.4, F + 13, -6), t.RockLight, "Sandstone", { Name = "GlyphWall" })
	glyphPanel(eastPanel, Enum.NormalId.Left, C(196, 150, 60), 11)
	local westPanel = b:Box(V(0.6, 8, 12), CF(Layout.Chamber.X0 + 1.4, F + 13, -9), t.RockLight, "Sandstone", { Name = "GlyphWall" })
	glyphPanel(westPanel, Enum.NormalId.Right, C(108, 72, 38), 23)
	-- Broken dog statue: plinth, seated body, the head lying on the floor.
	local statue = CF(-3, F, 3) * ANG(0, rad(180), 0)
	b:Box(V(4.6, 1.6, 4.6), statue * CF(0, 0.8, 0), t.RockDark, "Sandstone", { Name = "Plinth", CanCollide = true })
	b:Ellipsoid(V(3.0, 4.2, 3.6), statue * CF(0, 3.6, 0.3), t.RockLight, "Sandstone", { Name = "StatueBody" })
	b:Ellipsoid(V(2.6, 1.2, 1.6), statue * CF(0, 1.9, -1.4), t.RockLight, "Sandstone", { Name = "StatueLegs" })
	b:Box(V(0.6, 0.6, 0.6), statue * CF(0.4, 5.9, 0.2) * ANG(0.4, 0.3, 0.2), t.RockLight, "Sandstone", { Name = "StatueNeck" })
	local head = CF(1.5, F, -3.5) * ANG(rad(16), rad(40), rad(78))
	b:Ellipsoid(V(2.2, 2.0, 2.4), head * CF(0, 1.1, 0), t.RockLight, "Sandstone", { Name = "StatueHead" })
	b:Ellipsoid(V(1.0, 0.9, 1.6), head * CF(0, 0.9, -1.4), t.RockLight, "Sandstone", { Name = "StatueSnout" })
	b:Wedge(V(0.5, 1.6, 0.9), head * CF(0.6, 2.4, 0.2), t.RockLight, "Sandstone", { Name = "StatueEar" })
	b:Wedge(V(0.5, 1.6, 0.9), head * CF(-0.6, 2.4, 0.2), t.RockLight, "Sandstone", { Name = "StatueEar" })
	b:Ball(0.35, head * CF(0.45, 1.35, -1.05), Forge.Palette.Gold, "Neon", { Name = "StatueEye" })
	-- Gold, pottery and sand dunes.
	goldPile(b, CF(-17, F, -11), 1.0)
	goldPile(b, CF(14, F, 8), 0.8)
	pottery(b, CF(-18, F, 2), 1.0, C(176, 104, 64))
	pottery(b, CF(-16.6, F, 3.6), 0.8, C(196, 128, 76))
	pottery(b, CF(12, F, -9), 0.9, C(168, 96, 58))
	for i = 1, 4 do
		b:Ellipsoid(V(R(8, 13), R(0.8, 1.5), R(5, 8)), CF(R(-20, 20), F - 0.2, R(-24, 10)) * ANG(0, rad(R(0, 180)), 0), t.RockLight, "Sand", { Name = "Dune", CastShadow = false })
	end
	-- Temple facade on the far wall: steps, two columns, entablature, pediment, dark doorway,
	-- and two guardian dog statues.
	local temple = CF(-3, F, Layout.Chamber.Z1 - 2.2)
	for i = 0, 2 do
		b:Box(V(18 - i * 2, 0.8, 3.4 - i * 0.8), temple * CF(0, 0.4 + i * 0.8, -1.2 + i * 0.4 - 1.6), t.RockDark, "Sandstone", { Name = "TempleStep", CanCollide = true })
	end
	b:Box(V(5, 9, 0.6), temple * CF(0, 6.9, 0.6), C(20, 14, 10), "SmoothPlastic", { Name = "TempleDoor" })
	b:Box(V(5.8, 0.4, 0.8), temple * CF(0, 11.6, 0.3), Forge.Palette.Gold, "Metal", { Name = "DoorGold", Accent = true })
	for _, x in { -5.2, 5.2 } do
		b:CylY(10, 1.8, temple * CF(x, 7.4, -0.4), t.RockLight, "Sandstone", { Name = "TempleColumn", CanCollide = true })
		b:Box(V(2.4, 0.6, 2.4), temple * CF(x, 12.6, -0.4), t.RockDark, "Sandstone", { Name = "TempleCapital" })
	end
	b:Box(V(15, 1.6, 2.6), temple * CF(0, 13.7, -0.2), t.Rock, "Sandstone", { Name = "Entablature" })
	b:Roof(V(2.6, 3.2, 15.6), temple * CF(0, 16.1, -0.2) * ANG(0, math.pi / 2, 0), t.RockLight, "Sandstone", { Name = "Pediment" })
	b:Ball(1.2, temple * CF(0, 16.4, -1.4), Forge.Palette.Gold, "Neon", { Name = "SunDisc", CastShadow = false })
	for _, x in { -9.5, 3.5 } do
		local g = temple * CF(x, 2.4, -2.6)
		b:Box(V(2.2, 1.4, 2.6), g * CF(0, 0.7, 0), t.RockDark, "Sandstone", { Name = "GuardPlinth" })
		b:Ellipsoid(V(1.6, 2.6, 2.2), g * CF(0, 2.6, 0.2), t.RockLight, "Sandstone", { Name = "GuardBody" })
		b:Ellipsoid(V(1.2, 1.2, 1.6), g * CF(0, 4.3, -0.4), t.RockLight, "Sandstone", { Name = "GuardHead" })
		b:Wedge(V(0.35, 1.2, 0.6), g * CF(0.4, 5.2, -0.2), t.RockLight, "Sandstone", { Name = "GuardEar" })
		b:Wedge(V(0.35, 1.2, 0.6), g * CF(-0.4, 5.2, -0.2), t.RockLight, "Sandstone", { Name = "GuardEar" })
		b:Box(V(1.3, 0.25, 0.25), g * CF(0, 3.6, -1.0), Forge.Palette.Gold, "Metal", { Name = "GuardCollar", Accent = true })
	end
	-- A sarcophagus with a golden mask, broken pillar pieces and hanging roots.
	local sarc = CF(14, F, -1) * ANG(0, rad(90), 0)
	b:Box(V(2.6, 1.6, 6), sarc * CF(0, 0.8, 0), t.RockLight, "Sandstone", { Name = "Sarcophagus", CanCollide = true })
	b:Box(V(2.4, 0.5, 5.6), sarc * CF(0.6, 1.9, 0.2) * ANG(0, rad(8), rad(-6)), t.Rock, "Sandstone", { Name = "SarcophagusLid" })
	b:Ellipsoid(V(1.3, 0.5, 1.6), sarc * CF(0, 1.62, -2.0), Forge.Palette.Gold, "Metal", { Name = "GoldMask", Accent = true })
	for i, p in { { -9, 13, 30 }, { 9, -12, -50 } } do
		b:CylY(1.1, 2.6, CF(p[1], F + 0.55, p[2]), t.Rock, "Sandstone", { Name = "PillarStump" })
		b:Box(V(1.6, 1.0, 1.4), CF(p[1] + 2, F + 0.5, p[2] - 1) * ANG(0, rad(p[3]), rad(10 * i)), t.RockLight, "Sandstone", { Name = "Rubble" })
	end
	for i = 1, 8 do
		local x, z = R(-20, 22), R(-22, 10)
		local len = R(3, 7)
		b:Box(V(0.18, len, 0.18), CF(x, top - len / 2, z) * ANG(rad(R(-8, 8)), 0, rad(R(-8, 8))), C(92, 76, 48), "Wood", { Name = "Root" })
	end
	-- Wall torches (fire emitters) and the gold glow light.
	for i, p in { { Layout.Chamber.X0 + 0.9, -24, 1 }, { Layout.Chamber.X1 - 0.9, -6, -1 } } do
		local sconce = b:Box(V(0.5, 1.4, 0.5), CF(p[1], F + 6.5, p[2]), IRON, "Metal", { Name = "Sconce" })
		local flame = b:Ball(0.7, sconce.CFrame * CF(0, 1.0, 0), C(255, 160, 60), "Neon", { Name = "TorchFlame", CastShadow = false })
		b:Light(flame, C(255, 160, 80), 22, 1.6, "Point")
		emitter(flame, {
			Texture = FIRE,
			Rate = ctx.LowFX and 6 or 14,
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(1, 2),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.1) }),
			Color = ColorSequence.new(C(255, 190, 90), C(255, 90, 30)),
			LightEmission = 1,
			Transparency = NumberSequence.new(0.2),
			EmissionDirection = Enum.NormalId.Top,
		})
	end
	local goldLight = b:Ball(0.6, CF(-17, F + 1.2, -11), Forge.Palette.Gold, "Neon", { Name = "GoldShine", CastShadow = false })
	b:Light(goldLight, C(255, 200, 90), 14, 1.2, "Point")
	local dust = volume(b, "SandDust", V(44, 14, 40), CF(1, F + 8, -9))
	emitter(dust, {
		Texture = SMOKE,
		Rate = ctx.LowFX and 3 or 8,
		Lifetime = NumberRange.new(6, 10),
		Speed = NumberRange.new(0.2, 0.6),
		Size = NumberSequence.new(0.25, 0.5),
		Color = ColorSequence.new(C(236, 206, 150)),
		Transparency = NumberSequence.new(0.55),
		LightEmission = 0.3,
		Drag = 0.5,
	})
	local glints = volume(b, "GoldGlints", V(40, 4, 34), CF(-2, F + 2, -6))
	emitter(glints, {
		Texture = SPARKLE,
		Rate = ctx.LowFX and 2 or 5,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0, 0.1),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(C(255, 220, 120)),
		LightEmission = 1,
	})
end

------------------------------------------------------------------------------------------------
-- CURSED DEPTHS: black rock, red lava cracks, bones, chains, red fog, embers
------------------------------------------------------------------------------------------------
local function bone(b, cf, len, color)
	b:Cyl(len, 0.32, cf, color, "Marble", { Name = "Bone" })
	for _, x in { -len / 2, len / 2 } do
		b:Ball(0.55, cf * CF(x, 0, 0.12), color, "Marble", { Name = "BoneKnob" })
	end
end

local function skull(b, cf, scale, color)
	b:Ball(1.3 * scale, cf * CF(0, 0.65 * scale, 0), color, "Marble", { Name = "Skull" })
	b:Box(V(0.9, 0.45, 0.8) * scale, cf * CF(0, 0.25 * scale, -0.3 * scale), color, "Marble", { Name = "Jaw" })
	for _, x in { -0.26, 0.26 } do
		b:Ball(0.36 * scale, cf * CF(x * scale, 0.75 * scale, -0.55 * scale), C(255, 40, 30), "Neon", { Name = "SkullEye" })
	end
end

local function chain(b, top, links, color)
	for i = 0, links - 1 do
		local cf = top * CF(0, -0.75 * i, 0) * ANG(0, (i % 2) * math.pi / 2, 0)
		b:Box(V(0.18, 0.95, 0.5), cf, color, "Metal", { Name = "ChainLink" })
	end
end

local function cursedNode(b, ctx, slot, n)
	local t = ctx.Theme
	b:Box(V(5.4, 4.4, 3.0), n * CF(0, 2.1, 0.6) * ANG(rad(-7), 0, rad(5)), t.RockDark, "Basalt", { Name = "Outcrop" })
	if slot == 1 then -- cursed ore: black rock veined with red light
		for i = 0, 2 do
			b:Box(V(0.18, 2.6, 0.12), n * CF(-1.4 + i * 1.3, 2.2, -1.0) * ANG(0, 0, rad(25 - i * 22)), t.Glow, "Neon", { Name = "CurseVein" })
		end
		b:Ellipsoid(V(2.2, 1.6, 1.4), n * CF(0, 0.8, -1.2), C(30, 20, 26), "Basalt", { Name = "CursedOre" })
	elseif slot == 2 then -- bone pile
		bone(b, n * CF(-0.6, 0.35, -1.2) * ANG(0, 0.5, 0), 2.6, t.Bone)
		bone(b, n * CF(0.6, 0.6, -0.9) * ANG(0, -0.8, 0.2), 2.2, t.Bone)
		skull(b, n * CF(0, 0.7, -1.6), 0.8, t.Bone)
	elseif slot == 3 then -- ember vein
		for i = 0, 3 do
			b:Ball(0.6, n * CF(-1.5 + i, 1.0 + (i % 2) * 1.4, -1.1), t.Lava, "Neon", { Name = "Ember" })
		end
	elseif slot == 4 then -- obsidian idol
		b:Box(V(1.3, 0.6, 1.3), n * CF(0, 0.3, -1.1), C(40, 30, 36), "Basalt", { Name = "IdolBase" })
		b:Wedge(V(1.0, 2.6, 1.0), n * CF(0, 1.9, -1.1), C(14, 10, 16), "Glass", { Name = "ObsidianIdol" })
		b:Ball(0.3, n * CF(0, 2.5, -1.62), t.Glow, "Neon", { Name = "IdolEye" })
	else -- dark meteor
		b:Ball(2.2, n * CF(0, 1.1, -1.2), C(26, 22, 30), "CrackedLava", { Name = "DarkMeteor" })
		b:Ball(2.5, n * CF(0, 1.1, -1.2), t.Lava, "ForceField", { Name = "MeteorHeat", Transparency = 0.4, CastShadow = false })
	end
end

local function cursed(b: any, ctx: any)
	local t, R, F = ctx.Theme, ctx.R, ctx.F
	stalactites(b, ctx, 12, t.RockDark, t.Glow, "Basalt")
	-- Lava cracks across the floor and a lava pool.
	local cracks = { { -18, -22, 30 }, { -8, -14, -20 }, { 2, -6, 50 }, { 12, 2, -35 }, { -14, 4, 15 }, { -4, 10, -60 }, { 8, -16, 70 }, { 16, -2, 10 } }
	for _, c in cracks do
		local cf = CF(c[1], F + 0.08, c[2]) * ANG(0, rad(c[3]), 0)
		b:Box(V(R(5, 9), 0.1, R(0.25, 0.5)), cf, t.Lava, "Neon", { Name = "LavaCrack", CastShadow = false })
		b:Box(V(R(2, 4), 0.1, R(0.2, 0.35)), cf * CF(R(2, 4), 0, 0.6) * ANG(0, rad(R(-40, 40)), 0), t.Glow, "Neon", { Name = "LavaCrack", CastShadow = false })
	end
	local pool = CF(-4, F, -2)
	b:Ellipsoid(V(10.5, 0.9, 8), pool * CF(0, 0.1, 0), C(22, 14, 16), "Basalt", { Name = "PoolCrust" })
	local lava = b:Ellipsoid(V(8.6, 0.3, 6.2), pool * CF(0, 0.45, 0), t.Lava, "Neon", { Name = "LavaPool", CastShadow = false })
	b:Light(lava, C(255, 90, 40), 26, 2.0, "Point")
	-- Bones and skulls scattered in heaps.
	for i, p in { { -16, -8 }, { 10, 10 }, { 14, -10 }, { 2, -18 } } do
		bone(b, CF(p[1], F + 0.2, p[2]) * ANG(0, i * 0.9, 0), R(2, 3), t.Bone)
		bone(b, CF(p[1] + 0.8, F + 0.35, p[2] + 0.6) * ANG(0, i * 2.1, 0.15), R(1.6, 2.4), t.Bone)
		skull(b, CF(p[1] - 0.6, F, p[2] - 0.8) * ANG(0, rad(i * 70), 0), 1.0, t.Bone)
	end
	-- Chains from the ceiling, one holding a cage.
	for i, p in { { -14, -16 }, { -2, 8 }, { 8, -12 }, { 14, 6 } } do
		chain(b, CF(p[1], ctx.Top - 0.4, p[2]), i == 2 and 8 or 7 + (i % 2) * 3, C(60, 56, 60))
	end
	local cage = CF(-2, ctx.Top - 8.2, 8)
	b:Box(V(3, 0.3, 3), cage * CF(0, -3.2, 0), C(50, 46, 50), "Metal", { Name = "CageFloor" })
	b:Box(V(3, 0.3, 3), cage * CF(0, 0, 0), C(50, 46, 50), "Metal", { Name = "CageTop" })
	for _, x in { -1.4, 0, 1.4 } do
		for _, z in { -1.4, 1.4 } do
			b:Box(V(0.14, 3.2, 0.14), cage * CF(x, -1.6, z), C(60, 56, 60), "Metal", { Name = "CageBar" })
		end
	end
	skull(b, cage * CF(0, -3.05, 0), 0.6, t.Bone)
	-- The skeleton of a giant beast: spine, arched ribs and a horned skull.
	local spineY, spineZ = F + 5.4, 8.5
	b:Cyl(18, 0.9, CF(-3, spineY, spineZ) * ANG(0, 0, rad(-4)), t.Bone, "Marble", { Name = "Spine" })
	for i = 0, 5 do
		local x = -10 + i * 2.8
		for _, k in { -1, 1 } do
			local a = V(x, spineY - i * 0.12, spineZ)
			local m = V(x + 0.2, F + 3.6, spineZ + k * 3.4)
			local f = V(x + 0.5, F + 0.3, spineZ + k * 3.9)
			b:Rod(a, m, 0.42, t.Bone, "Marble", { Name = "Rib" })
			b:Rod(m, f, 0.36, t.Bone, "Marble", { Name = "Rib" })
		end
	end
	local beast = CF(8.5, F + 2.6, spineZ) * ANG(0, rad(-90), rad(-14))
	b:Ellipsoid(V(3.4, 3.0, 4.6), beast, t.Bone, "Marble", { Name = "BeastSkull" })
	b:Box(V(2.6, 0.7, 3.2), beast * CF(0, -1.4, -1.0) * ANG(rad(14), 0, 0), t.Bone, "Marble", { Name = "BeastJaw" })
	for _, k in { -1, 1 } do
		b:Wedge(V(0.6, 2.6, 1.2), beast * CF(k * 1.2, 2.2, 0.8) * ANG(rad(-30), 0, rad(-k * 20)), C(40, 30, 32), "Basalt", { Name = "BeastHorn" })
		b:Ball(0.7, beast * CF(k * 0.8, 0.4, -1.9), t.Glow, "Neon", { Name = "BeastEye", CastShadow = false })
	end
	-- Candles on a black altar.
	local altar = CF(14, F, -2)
	b:Box(V(4, 2.4, 2.4), altar * CF(0, 1.2, 0), C(30, 22, 28), "Basalt", { Name = "Altar", CanCollide = true })
	for i = -1, 1 do
		b:CylY(0.6 + (i + 1) * 0.3, 0.35, altar * CF(i * 1.2, 2.4 + 0.3 + (i + 1) * 0.15, 0), C(30, 26, 30), "SmoothPlastic", { Name = "Candle" })
		b:Ball(0.28, altar * CF(i * 1.2, 2.75 + (i + 1) * 0.3, 0), C(255, 120, 60), "Neon", { Name = "CandleFlame", CastShadow = false })
	end
	-- Red lights and the fog / ember emitters.
	for _, p in { { -16, 6 }, { 12, -18 } } do
		local glow = b:Ball(0.8, CF(p[1], F + 0.8, p[2]), t.Glow, "Neon", { Name = "CurseGlow", CastShadow = false })
		b:Light(glow, C(255, 50, 40), 22, 1.5, "Point")
	end
	local fog = volume(b, "RedFog", V(44, 2, 40), CF(1, F + 1.2, -9))
	emitter(fog, {
		Texture = SMOKE,
		Rate = ctx.LowFX and 2 or 5,
		Lifetime = NumberRange.new(7, 11),
		Speed = NumberRange.new(0.1, 0.5),
		Size = NumberSequence.new(7, 12),
		Color = ColorSequence.new(C(170, 30, 30), C(90, 10, 20)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.15,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8),
	})
	local embers = volume(b, "Embers", V(40, 1, 34), CF(1, F + 0.6, -8))
	emitter(embers, {
		Texture = SPARKLE,
		Rate = ctx.LowFX and 4 or 12,
		Lifetime = NumberRange.new(3, 6),
		Speed = NumberRange.new(1.5, 3),
		Acceleration = V(0, 1.5, 0),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(C(255, 160, 60), C(255, 40, 20)),
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
	})
end

------------------------------------------------------------------------------------------------
-- THE VOID (rare zone): black void, floating rock islands, starfield sparkles, violet rifts
------------------------------------------------------------------------------------------------
local function voidCrystal(b, cf, scale, color, count)
	local out = {}
	for i, s in { { 0, 0, 1, 3.6 }, { 0.8, 0.3, 0.6, 2.2 }, { -0.7, -0.4, 0.55, 2.0 } } do
		if count and i > count then
			break
		end
		local parts = b:Prism(cf * CF(s[1] * scale, 0, s[2] * scale) * ANG(rad(s[2] * 25), rad(i * 50), rad(-s[1] * 22)), s[3] * scale, s[4] * scale, s[3] * scale, color, "Neon", { Name = "VoidCrystal", Accent = true, CastShadow = false })
		for _, p in parts do
			table.insert(out, p)
		end
	end
	return out
end

local function island(b, cf, size, t, R)
	local parts = {}
	table.insert(parts, b:Box(V(size, size * 0.28, size * 0.8), cf * ANG(0, rad(R(0, 90)), rad(R(-4, 4))), t.RockLight, "Basalt", { Name = "IslandTop" }))
	table.insert(parts, b:Ellipsoid(V(size * 0.95, size * 0.9, size * 0.78), cf * CF(0, -size * 0.3, 0), t.Rock, "Basalt", { Name = "IslandBelly" }))
	for _, p in b:Cone(cf * CF(size * 0.08, -size * 0.6, 0) * ANG(math.pi, 0, 0), size * 0.75, size * 0.42, 0.15, 2, t.RockDark, "Basalt", { Name = "IslandRoot" }) do
		table.insert(parts, p)
	end
	for _, p in voidCrystal(b, cf * CF(size * 0.18, size * 0.14, 0), size * 0.13, t.Glow, 2) do
		table.insert(parts, p)
	end
	return parts
end

local function voidNode(b, ctx, slot, n)
	local t = ctx.Theme
	b:Box(V(5.4, 4.2, 3.0), n * CF(0, 2.0, 0.6) * ANG(rad(-6), 0, rad(-4)), t.Rock, "Basalt", { Name = "Outcrop" })
	if slot == 1 then -- void crystals
		voidCrystal(b, n * CF(0, 0.2, -1.0), 0.65, t.Glow)
	elseif slot == 2 then -- black star shard
		b:Ball(1.6, n * CF(0, 1.6, -1.1), C(8, 6, 12), "SmoothPlastic", { Name = "BlackStar" })
		b:Ball(2.1, n * CF(0, 1.6, -1.1), t.Glow, "ForceField", { Name = "StarHalo", Transparency = 0.3, CastShadow = false })
	elseif slot == 3 then -- reality data: glitch cubes
		for i = 0, 3 do
			b:Box(V(0.7, 0.7, 0.7), n * CF(-1.2 + i * 0.8, 1.0 + (i % 2) * 1.2, -1.1) * ANG(i, i * 0.7, 0), i % 2 == 0 and t.Cyan or t.Glow, "Neon", { Name = "DataCube", CastShadow = false })
		end
	elseif slot == 4 then -- solar fragment
		b:Ball(1.3, n * CF(0, 1.4, -1.2), C(255, 180, 60), "Neon", { Name = "SolarFragment", CastShadow = false })
		for i = 0, 3 do
			b:Box(V(0.15, 0.15, 1.6), n * CF(0, 1.4, -1.2) * ANG(0, rad(i * 45), rad(90)), C(255, 220, 120), "Neon", { Name = "SolarRay", CastShadow = false })
		end
	else -- lost planet with a ring
		b:Ball(1.8, n * CF(0, 1.7, -1.2), C(70, 130, 220), "Slate", { Name = "LostPlanet" })
		b:Disc(n * CF(0, 1.7, -1.2) * ANG(rad(20), 0, rad(15)), 3.0, 0.08, t.Cyan, "Neon", { Name = "PlanetRing", CastShadow = false })
	end
end

local function void(b: any, ctx: any)
	local t, R, F = ctx.Theme, ctx.R, ctx.F
	local c = Layout.Chamber
	-- Neon grid in the black glass floor.
	for i = 0, 5 do
		local x = c.X0 + 4 + i * 8.4
		b:Box(V(0.18, 0.06, c.Z1 - c.Z0 - 6), CF(x, F + 0.12, (c.Z0 + c.Z1) / 2 + 2), t.Glow, "Neon", { Name = "GridLine", Transparency = 0.35, CastShadow = false })
	end
	for i = 0, 4 do
		local z = c.Z0 + 6 + i * 9.4
		b:Box(V(c.X1 - c.X0 - 6, 0.06, 0.18), CF((c.X0 + c.X1) / 2, F + 0.12, z), t.Glow, "Neon", { Name = "GridLine", Transparency = 0.35, CastShadow = false })
	end
	-- Floating rock islands drifting under the ceiling (bobbing tweened by the client).
	local spots = { { -12, -14, 5 }, { 6, 4, 6.5 }, { -6, 9, 4 }, { 14, -6, 4.5 }, { -16, 0, 3.5 }, { 2, -20, 3 } }
	for i, s in spots do
		local cf = CF(s[1], F + 12 + (i % 3) * 2.6, s[2])
		local parts = island(b, cf, s[3], t, R)
		for _, p in parts do
			p:SetAttribute("MineBob", 0.8 + (i % 3) * 0.4)
			p:SetAttribute("MineBobPeriod", 3.2 + i * 0.45)
		end
	end
	-- Violet rifts: jagged neon shards in a crack of the far and west walls.
	for k, base in { CF(-4, F + 6, c.Z1 - 1.2), CF(c.X0 + 1.2, F + 7, -10) * ANG(0, rad(90), 0) } do
		for i = 0, 5 do
			local y = (i - 2.5) * 1.9
			b:Box(V(0.5 + (i % 2) * 0.6, 2.2, 0.2), base * CF(math.sin(i * 1.7 + k) * 0.9, y, 0) * ANG(0, 0, rad((i % 2 == 0 and 1 or -1) * 24)), i % 3 == 0 and t.Cyan or t.Glow, "Neon", { Name = "Rift", CastShadow = false })
		end
		b:Box(V(3.4, 12, 0.1), base * CF(0, 0, -0.1), t.Glow, "ForceField", { Name = "RiftHaze", Transparency = 0.55, CastShadow = false })
	end
	-- A broken portal ring and void crystal clusters (carrying the violet lights).
	local portal = CF(10, F + 6.5, 8) * ANG(0, rad(-30), 0)
	b:Ring(portal * ANG(math.pi / 2, 0, 0), 4.2, 0.6, t.RockLight, "Basalt", 14, { Name = "Portal" })
	b:Disc(portal * ANG(math.pi / 2, 0, 0), 7.6, 0.1, t.Glow, "ForceField", { Name = "PortalSurface", Transparency = 0.45, CastShadow = false })
	local lit = 0
	for i, p in { { -18, -20 }, { 0, -8 }, { -10, 8 }, { 16, -16 } } do
		local parts = voidCrystal(b, CF(p[1], F, p[2]) * ANG(0, rad(i * 60), 0), 1.0 + (i % 2) * 0.3, i % 2 == 0 and t.Cyan or t.Glow)
		if lit < 3 then
			lit += 1
			b:Light(parts[1], i % 2 == 0 and t.Cyan or t.Glow, 22, 1.6, "Point")
		end
	end
	local portalLight = b:Ball(0.6, CF(portal.Position), t.Glow, "Neon", { Name = "PortalCore", CastShadow = false })
	b:Light(portalLight, t.Glow, 20, 1.4, "Point")
	-- Starfield sparkles filling the volume and a slow violet haze.
	local stars = volume(b, "Starfield", V(46, ctx.H - 2, 42), CF(1, F + ctx.H / 2, -9))
	emitter(stars, {
		Texture = SPARKLE,
		Rate = ctx.LowFX and 8 or 22,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(0, 0.15),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(t.Star, C(190, 160, 255)),
		LightEmission = 1,
	})
	local haze = volume(b, "VoidHaze", V(44, 3, 40), CF(1, F + 1.5, -9))
	emitter(haze, {
		Texture = SMOKE,
		Rate = ctx.LowFX and 1 or 3,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.1, 0.3),
		Size = NumberSequence.new(8, 13),
		Color = ColorSequence.new(C(90, 40, 160), C(20, 10, 40)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.85), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-6, 6),
	})
	-- The heart of the rare zone: a small black hole with a glowing accretion ring, bobbing.
	local heart = CF(-2, F + 13.5, -4) * ANG(rad(18), rad(30), 0)
	local heartParts = {}
	table.insert(heartParts, b:Ball(3.2, heart, C(4, 2, 8), "SmoothPlastic", { Name = "BlackHole", CastShadow = false }))
	table.insert(heartParts, b:Ball(4.4, heart, t.Glow, "ForceField", { Name = "EventHorizon", Transparency = 0.35, CastShadow = false }))
	for _, p in b:Ring(heart, 4.4, 0.45, t.Glow, "Neon", 18, { Name = "AccretionRing", CastShadow = false }) do
		table.insert(heartParts, p)
	end
	for _, p in b:Ring(heart * ANG(0, 0, rad(4)), 5.6, 0.22, t.Cyan, "Neon", 14, { Name = "AccretionRing", Transparency = 0.3, CastShadow = false }) do
		table.insert(heartParts, p)
	end
	for _, p in heartParts do
		p:SetAttribute("MineBob", 0.9)
		p:SetAttribute("MineBobPeriod", 4.6)
	end
	-- Stars set into the black walls and the ceiling.
	for i = 1, 26 do
		local face = i % 4
		local pos
		if face == 0 then
			pos = V(R(c.X0 + 2, c.X1 - 2), ctx.Top - 0.25, R(c.Z0 + 2, c.Z1 - 2))
		elseif face == 1 then
			pos = V(c.X0 + 0.25, R(F + 4, ctx.Top - 1), R(c.Z0 + 2, c.Z1 - 2))
		elseif face == 2 then
			pos = V(c.X1 - 0.25, R(F + 4, ctx.Top - 1), R(c.Z0 + 2, c.Z1 - 2))
		else
			pos = V(R(c.X0 + 2, c.X1 - 2), R(F + 5, ctx.Top - 1), c.Z1 - 0.25)
		end
		b:Ball(R(0.2, 0.55), CF(pos), i % 5 == 0 and t.Cyan or t.Star, "Neon", { Name = "Star", CastShadow = false })
	end
end

------------------------------------------------------------------------------------------------
-- DRESSING: the shared pass that makes every level feel lived-in and deep. Walls get relief
-- slabs, cracks and lit niches between the worksites; old mining gear (timber sets, a toppled
-- cart, rail pieces, planks) lies along the walls; a lamp line hangs from the ceiling; roots,
-- glowing mushrooms / crystals, low ground fog and dust motes add the atmosphere. Lights are
-- accents only (two per level). The landing (x' > 12, z < -22), the worksites and the middle of
-- the chamber stay clear.
------------------------------------------------------------------------------------------------
local DRESS = {
	[2] = { Glow = C(110, 220, 255), Glow2 = C(170, 255, 230), Fog = C(120, 160, 200), Root = C(96, 76, 58), Roots = true, Mush = C(90, 230, 255) },
	[3] = { Glow = C(255, 196, 80), Glow2 = C(255, 150, 60), Fog = C(214, 180, 130), Root = C(110, 90, 60), Roots = true, Mush = C(255, 210, 120) },
	[4] = { Glow = C(255, 70, 40), Glow2 = C(255, 140, 60), Fog = C(140, 40, 40), Root = C(60, 40, 40), Roots = false, Mush = C(255, 90, 60) },
	[5] = { Glow = C(176, 92, 255), Glow2 = C(90, 224, 255), Fog = C(80, 50, 130), Root = C(40, 30, 60), Roots = false, Mush = C(200, 120, 255) },
}
local function clearOfSites(x: number, z: number, pad: number): boolean
	for _, site in Layout.Worksites do
		if math.abs(x - site.X) < pad and math.abs(z - site.Z) < pad + 2 then
			return false
		end
	end
	if x > 10 and z < -20 then
		return false -- landing
	end
	return true
end
local function dressing(b: any, ctx: any)
	local t, R, F, H = ctx.Theme, ctx.R, ctx.F, ctx.H
	local d = DRESS[ctx.Layer] or DRESS[2]
	local c = Layout.Chamber
	local mat = t.RockMaterial
	local tones = { t.Rock, t.RockDark, t.RockLight or t.Rock }
	-- RELIEF: leaning slabs and bulges low on the side walls, between the worksites.
	local wallSpots = { { -1, -24 }, { -1, -9 }, { -1, 4.5 }, { 1, -21 }, { 1, -5.5 }, { 1, 8.5 } }
	for i, w in wallSpots do
		local side, z = w[1], w[2]
		local x = side < 0 and c.X0 + 1.4 or c.X1 - 1.4
		local hgt = R(4, 8)
		b:Ellipsoid(V(R(3, 4.5), hgt, R(4, 6)), CF(x, F + hgt * 0.35, z) * ANG(rad(R(-8, 8)), rad(R(0, 180)), rad(side * R(4, 12))), tones[(i % 3) + 1], mat, { Name = "WallBulge" })
		-- A crack running up the wall above it.
		for k = 0, 2 do
			b:Box(V(0.12, R(1.6, 2.6), 0.5), CF(side < 0 and c.X0 + 0.35 or c.X1 - 0.35, F + 5 + k * 2.1, z + R(-1.2, 1.2)) * ANG(rad(R(-25, 25)), 0, 0), t.RockDark:Lerp(C(0, 0, 0), 0.6), "SmoothPlastic", { Name = "Crack", CastShadow = false })
		end
	end
	-- NICHES: dark recesses in the far wall, each with a little glowing crystal or candle stub.
	for i, x in { -10, 2, 14 } do
		local z = c.Z1 - 0.5
		b:Box(V(3.2, 2.6, 1.0), CF(x, F + 3.4 + (i % 2) * 1.2, z), t.RockDark:Lerp(C(0, 0, 0), 0.55), "SmoothPlastic", { Name = "Niche", CastShadow = false })
		b:Box(V(3.6, 0.35, 1.3), CF(x, F + 2.0 + (i % 2) * 1.2, z - 0.2), tones[2], mat, { Name = "NicheSill" })
		local glow = i % 2 == 0 and d.Glow or d.Glow2
		b:Prism(CF(x - 0.5, F + 2.2 + (i % 2) * 1.2, z - 0.1) * ANG(0, rad(i * 40), rad(8)), 0.35, 1.3, 0.3, glow, "Neon", { Name = "NicheCrystal", CastShadow = false })
		b:Prism(CF(x + 0.4, F + 2.2 + (i % 2) * 1.2, z - 0.2) * ANG(0, rad(i * 25), rad(-12)), 0.25, 0.9, 0.22, glow, "Neon", { Name = "NicheCrystal", CastShadow = false })
	end
	-- TIMBER SETS along the side walls and a sagging crossbeam; planks on the floor.
	for _, z in { -12.5, 6.5 } do
		for _, side in { -1, 1 } do
			local x = side < 0 and c.X0 + 2.6 or c.X1 - 2.6
			if clearOfSites(x, z, 3.5) then
				b:Box(V(0.7, H - 2, 0.7), CF(x, F + (H - 2) / 2, z) * ANG(0, 0, rad(side * 3)), TIMBER, "WoodPlanks", { Name = "Prop" })
				b:Box(V(0.9, 0.9, 4.2), CF(x, F + H - 1.6, z), TIMBER_DARK, "WoodPlanks", { Name = "PropCap" })
				b:Box(V(0.5, 3.2, 0.5), CF(x - side * 1.1, F + H - 3.2, z) * ANG(0, 0, rad(side * 40)), TIMBER_DARK, "WoodPlanks", { Name = "PropBrace" })
			end
		end
	end
	for i = 1, 4 do
		local x, z = R(c.X0 + 4, c.X1 - 6), R(c.Z0 + 6, c.Z1 - 3)
		if clearOfSites(x, z, 4) and math.abs(x) > 6 then
			b:Box(V(0.5, 0.18, R(3, 5)), CF(x, F + 0.12, z) * ANG(0, rad(R(0, 180)), rad(R(-6, 6))), i % 2 == 0 and TIMBER or TIMBER_DARK, "WoodPlanks", { Name = "Plank" })
		end
	end
	-- A toppled ore cart and a stretch of old rail by the far wall.
	local cart = CF(-4, F, c.Z1 - 4.5) * ANG(0, rad(18), rad(78))
	b:Box(V(2.2, 1.5, 3.0), cart * CF(0, 1.2, 0), C(86, 64, 46), "WoodPlanks", { Name = "ToppledCart" })
	b:Box(V(2.4, 0.22, 3.2), cart * CF(0, 2.0, 0), IRON, "Metal", { Name = "CartRim" })
	for _, p in { { -1.1, -1.0 }, { 1.1, -1.0 } } do
		b:Cyl(0.3, 0.9, cart * CF(p[1], 0.45, p[2]), C(40, 40, 44), "Metal", { Name = "CartWheel" })
	end
	for k = 0, 2 do
		b:Ellipsoid(V(0.9, 0.6, 0.9), CF(-2.6 + k * 0.9, F + 0.3, c.Z1 - 6 + (k % 2) * 0.6), k == 1 and d.Glow or t.RockDark, k == 1 and "Neon" or mat, { Name = "SpilledOre", CastShadow = false })
	end
	local rail = CF(4, F, c.Z1 - 3) * ANG(0, rad(90), 0)
	for _, x in { -0.9, 0.9 } do
		b:Box(V(0.22, 0.22, 11), rail * CF(x, 0.3, 0), C(110, 100, 92), "Metal", { Name = "Rail" })
	end
	for i = -2, 2 do
		b:Box(V(2.6, 0.2, 0.5), rail * CF(0, 0.12, i * 2.2) * ANG(0, rad(R(-6, 6)), 0), TIMBER_DARK, "WoodPlanks", { Name = "Sleeper" })
	end
	-- LAMP LINE: a cable along the ceiling with hanging bulbs (one warm light in the middle).
	local z = -6
	local a, bb = V(c.X0 + 3, ctx.Top - 1.2, z), V(c.X1 - 6, ctx.Top - 1.6, z + 6)
	b:Rod(a, bb, 0.08, C(30, 30, 34), "Metal", { Name = "LampCable" })
	for i = 1, 5 do
		local p = a:Lerp(bb, i / 6) - V(0, 0.15 + math.sin(i / 6 * math.pi) * 0.6, 0)
		b:Rod(p, p - V(0, 0.8, 0), 0.05, C(30, 30, 34), "Metal", { Name = "LampDrop" })
		local bulb = b:Ball(0.42, CF(p - V(0, 1.0, 0)), C(255, 214, 150), "Neon", { Name = "CaveBulb", CastShadow = false })
		if i == 3 then
			b:Light(bulb, C(255, 196, 130), 20, 0.9, "Point")
		end
	end
	-- ROOTS hanging from the ceiling (the upper levels lie under the island's soil).
	if d.Roots then
		for i = 1, 9 do
			local x, zz = R(c.X0 + 3, c.X1 - 3), R(c.Z0 + 4, c.Z1 - 2)
			local len = R(2.5, 6)
			local top = V(x, ctx.Top - 0.1, zz)
			local mid = top + V(R(-0.6, 0.6), -len * 0.55, R(-0.6, 0.6))
			local tip = mid + V(R(-0.5, 0.5), -len * 0.45, R(-0.5, 0.5))
			b:Rod(top, mid, R(0.18, 0.32), d.Root, "Wood", { Name = "Root" })
			b:Rod(mid, tip, R(0.08, 0.16), d.Root:Lerp(C(0, 0, 0), 0.2), "Wood", { Name = "Root" })
		end
	end
	-- GLOWING SPOTS: mushrooms (or embers) in two corners, one coloured accent light.
	local spots = { { c.X0 + 3.5, c.Z1 - 3.5 }, { c.X1 - 4, c.Z1 - 3 } }
	for i, sp in spots do
		for k = 1, 5 do
			local x, zz = sp[1] + R(-2, 2), sp[2] + R(-1.5, 1.5)
			local hgt = R(0.5, 1.4)
			b:Box(V(0.18, hgt, 0.18), CF(x, F + hgt / 2, zz), C(220, 220, 210), "SmoothPlastic", { Name = "MushStem" })
			b:Ellipsoid(V(R(0.6, 1.2), 0.35, R(0.6, 1.2)), CF(x, F + hgt, zz), k % 2 == 0 and d.Mush or d.Glow2, "Neon", { Name = "MushCap", CastShadow = false })
		end
		if i == 1 then
			local holder = b:Box(V(0.3, 0.3, 0.3), CF(sp[1], F + 1.5, sp[2]), d.Mush, "SmoothPlastic", { Name = "GlowSpot", Transparency = 1, CastShadow = false })
			b:Light(holder, d.Mush, 16, 1.2, "Point")
		end
	end
	ctx.Detail(function()
		-- Small stalagmites and pebbles scattered near the walls.
		for i = 1, 10 do
			local side = i % 2 == 0 and -1 or 1
			local x = side < 0 and c.X0 + R(3, 6) or c.X1 - R(3, 6)
			local zz = R(c.Z0 + 4, c.Z1 - 2)
			if clearOfSites(x, zz, 3.5) then
				local h = R(1, 2.6)
				b:Ellipsoid(V(h * 0.6, h, h * 0.6), CF(x, F + h * 0.35, zz), tones[(i % 3) + 1], mat, { Name = "SmallStalagmite" })
			end
		end
	end)
	-- GROUND FOG (low, very transparent) and floating dust motes.
	local fog = volume(b, "GroundFog", V(c.X1 - c.X0 - 6, 1.2, c.Z1 - c.Z0 - 6), CF((c.X0 + c.X1) / 2, F + 0.8, (c.Z0 + c.Z1) / 2))
	emitter(fog, {
		Texture = SMOKE,
		Rate = ctx.LowFX and 1 or 3,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.1, 0.4),
		Size = NumberSequence.new(6, 11),
		Color = ColorSequence.new(d.Fog),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.15,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-6, 6),
		Acceleration = V(0, 0.05, 0),
	})
	if not ctx.LowFX then
		local dust = volume(b, "DustMotes", V(c.X1 - c.X0 - 4, ctx.H - 4, c.Z1 - c.Z0 - 4), CF((c.X0 + c.X1) / 2, F + ctx.H / 2, (c.Z0 + c.Z1) / 2))
		emitter(dust, {
			Texture = SPARKLE,
			Rate = 5,
			Lifetime = NumberRange.new(4, 7),
			Speed = NumberRange.new(0.05, 0.3),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(d.Glow:Lerp(C(255, 255, 255), 0.6)),
			LightEmission = 0.8,
			Transparency = NumberSequence.new(0.35),
			Acceleration = V(0, -0.02, 0),
		})
	end
	-- THEMED EXTRAS.
	if ctx.Layer == 2 then
		-- Cavern: a blue crystal cluster bursting out of the near wall and drip stains.
		crystalCluster(b, CF(-16, F + 4, c.Z0 + 0.8) * ANG(rad(-70), 0, 0), 0.9, C(120, 200, 255), t.Glow, 4)
		for i = 1, 4 do
			b:Box(V(0.6, R(2, 4), 0.1), CF(R(c.X0 + 4, -2), F + 6, c.Z1 - 0.15), t.Water:Lerp(C(0, 0, 0), 0.3), "Glass", { Name = "DripStain", Transparency = 0.4, CastShadow = false })
		end
	elseif ctx.Layer == 3 then
		-- Ruins: broken column stubs, sand drifts and a fallen lintel.
		for i, p in { { -12, 9 }, { 8, 10 }, { -6, -14 } } do
			local h = R(2, 4.5)
			b:CylY(h, 1.6, CF(p[1], F + h / 2, p[2]) * ANG(rad(R(-6, 6)), 0, rad(R(-6, 6))), t.RockLight, "Sandstone", { Name = "ColumnStub" })
			b:Ellipsoid(V(3.4, 0.6, 2.6), CF(p[1] + 1, F + 0.15, p[2] + 0.8), t.Floor:Lerp(C(255, 230, 170), 0.25), "Sand", { Name = "SandDrift" })
			if i == 1 then
				b:Box(V(7, 1.2, 1.4), CF(p[1] + 3, F + 0.6, p[2] - 2) * ANG(0, rad(30), rad(6)), t.RockLight, "Sandstone", { Name = "FallenLintel" })
			end
		end
	elseif ctx.Layer == 4 then
		-- Cursed: glowing lava cracks across the floor and a skull pile.
		for i = 1, 6 do
			local x, zz = R(c.X0 + 6, c.X1 - 8), R(c.Z0 + 6, c.Z1 - 4)
			if clearOfSites(x, zz, 4) then
				b:Box(V(R(2.5, 5), 0.06, 0.25), CF(x, F + 0.1, zz) * ANG(0, rad(R(0, 180)), 0), t.Lava, "Neon", { Name = "LavaCrack", CastShadow = false })
			end
		end
		for i = 1, 3 do
			skull(b, CF(c.X0 + 4 + i * 0.9, F + 0.35 + (i == 2 and 0.5 or 0), c.Z1 - 7 + (i % 2) * 0.7) * ANG(0, rad(i * 40), 0), 0.8, t.Bone)
		end
	elseif ctx.Layer == 5 then
		-- Void: floating shards that bob, and violet rift lines on the walls.
		for i = 1, 6 do
			local x, zz = R(c.X0 + 6, c.X1 - 8), R(c.Z0 + 6, c.Z1 - 4)
			local shard = b:Prism(CF(x, F + R(6, 12), zz) * ANG(rad(R(-30, 30)), rad(R(0, 180)), rad(R(-30, 30))), R(0.4, 0.8), R(1.4, 2.6), 0.4, i % 2 == 0 and t.Glow or t.Cyan, "Neon", { Name = "FloatingShard", CastShadow = false })
			for _, p in shard do
				p:SetAttribute("MineBob", R(0.4, 0.9))
				p:SetAttribute("MineBobPeriod", R(2.5, 4.5))
			end
		end
		for i = 1, 4 do
			local side = i % 2 == 0 and -1 or 1
			b:Box(V(0.1, R(3, 6), 0.3), CF(side < 0 and c.X0 + 0.3 or c.X1 - 0.3, F + R(4, 10), R(c.Z0 + 6, c.Z1 - 4)) * ANG(rad(R(-30, 30)), 0, 0), t.Glow, "Neon", { Name = "RiftLine", CastShadow = false })
		end
	end
end

------------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------------
local BUILDERS = {
	[2] = { Main = caverns, Node = cavernsNode },
	[3] = { Main = ruins, Node = ruinsNode },
	[4] = { Main = cursed, Node = cursedNode },
	[5] = { Main = void, Node = voidNode },
}

local depthItems = nil
local itemDefs = nil
local function items(layer: number): { string }
	if depthItems == nil then
		local ok, d = pcall(function()
			return require(RS:WaitForChild("DogEconomy"):WaitForChild("DepthDefinitions"))
		end)
		depthItems = ok and d or {}
	end
	local row = depthItems[tostring(layer)]
	return row and row.Items or {}
end
function Levels.ItemName(id: string): string
	if itemDefs == nil then
		local ok, d = pcall(function()
			return require(RS:WaitForChild("DogEconomy"):WaitForChild("ItemDefinitions"))
		end)
		itemDefs = ok and d or {}
	end
	local def = itemDefs[id]
	return def and def.DisplayName or id
end
Levels.Items = items

-- options: LowFX (fewer particles, no detail parts).
function Levels.Build(layer: number, options: { LowFX: boolean? }?): Model
	local level = Layout.Levels[layer]
	assert(level, "MineLevels.Build: layer 2..5")
	local recipe = BUILDERS[layer]
	local low = options and options.LowFX == true
	local b = Forge.Builder("MineLevel_" .. Themes[layer].Key, { Lod = low and 1 or 0 })
	local ctx = {
		Layer = layer,
		Theme = Themes[layer],
		F = level.Floor,
		Top = level.Ceiling,
		H = level.Ceiling - level.Floor,
		R = rng(layer * 7919 + 17),
		LowFX = low,
		Node = recipe.Node,
		Items = items(layer),
		ItemName = Levels.ItemName,
		Detail = function(fn)
			b:Detail(fn)
		end,
	}
	walls(b, ctx)
	landing(b, ctx)
	worksites(b, ctx)
	recipe.Main(b, ctx)
	dressing(b, ctx)
	local model = b:Finish()
	model:SetAttribute("MineLayer", layer)
	return model
end

-- Counts for the budget tests: parts, lights, emitters.
function Levels.Count(model: Instance): (number, number, number)
	local parts, lights, emitters = 0, 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return parts, lights, emitters
end

return Levels
