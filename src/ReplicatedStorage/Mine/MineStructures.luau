-- MineStructures: Forge recipes of the mine's fixed structures, in YARD DESIGN coordinates
-- (see MineLayout). Callers place a built model with Structures.Place(model, layout).
--   Headframe(o)  server, every yard: the elevator station over the shaft (it replaced the yard
--                 Workshop): steel tower with freight doors, porch, machine room with the spoked
--                 head sheave ("Wheel"), counterweight, UPGRADE TREE kiosk (S.Kiosk), the depth
--                 sign (SurfaceGui "DepthSign"), depth lamps and the elevator prompt anchor
--                 (Attachment "PromptAnchor" on part "Gate"). With Layout.StationYaw ~= 0 (the
--                 station stands in the yard's service row) it is turned to face the yard and
--                 never gets the annex; else o.Annex adds the hoist house behind the shaft
--   Depot(cf)     ore depot for a free Workshop lot (unused since MineWorld layout v3: the
--                 station itself stands on the Workshop lot)
--   Shell()       server, every yard: the always-present rock column under the island that
--                 encloses the four levels (floors, walls, slabs, stalactites; <= 12 parts/level)
--   Winch(slotCF) server: rope winch over a kennel pit while the dogs dig in the mine
--   Cage()        client: the elevator cage (floor at the model origin, front = -Z)
--   Lining()      client: timber sets, strata bands, guide rails and lamps along the shaft
local Forge = require(script.Parent.Parent:WaitForChild("Forge"))
local Layout = require(script.Parent:WaitForChild("MineLayout"))
local Themes = require(script.Parent:WaitForChild("MineThemes"))

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local S = {}

local STEEL_DARK = C(96, 40, 32)
local IRON = C(70, 74, 82)
local SAFETY = C(244, 192, 44)
local CONCRETE = C(150, 144, 134)
local TIMBER = C(122, 82, 50)
local TIMBER_DARK = C(86, 56, 34)
local ROPE = C(40, 40, 44)

-- Moves every part of a design-space model into the world of one yard. In a mirrored yard the
-- parts' own X axes keep their handedness, so faces named along X (Left / Right) and attachment
-- offsets along X are mirrored too: a sign or a prompt stays on the side it was designed for.
local function swapFace(face: Enum.NormalId): Enum.NormalId
	if face == Enum.NormalId.Left then
		return Enum.NormalId.Right
	elseif face == Enum.NormalId.Right then
		return Enum.NormalId.Left
	end
	return face
end
function S.Place(model: Instance, layout: any)
	local mirrored = layout.Sx < 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = layout:ToWorld(d.CFrame)
		elseif mirrored then
			if d:IsA("Attachment") then
				d.CFrame = Layout.MirrorCF(d.CFrame, -1)
			elseif d:IsA("SurfaceGui") or d:IsA("FaceInstance") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				(d :: any).Face = swapFace((d :: any).Face)
			elseif d:IsA("ParticleEmitter") then
				d.EmissionDirection = swapFace(d.EmissionDirection)
			end
		end
	end
	if model:IsA("Model") and model.PrimaryPart then
		model.WorldPivot = model.PrimaryPart.CFrame
	end
end

local function collide(part: BasePart, on: boolean?)
	part.CanCollide = on ~= false
	part.CanQuery = on ~= false
	return part
end

------------------------------------------------------------------------------------------------
-- Elevator station (server): "Headframe"
------------------------------------------------------------------------------------------------
-- The mine elevator of every yard, built over the shaft (design x' 16..24, z -40..-32; with
-- MineLayout.Origin that is the old Workshop lot of the SERVICE ROW, yard x' 20..28, z -58..-50,
-- beside the DOG STORAGE and the collector). It replaces the yard Workshop (MineWorld moves the
-- Workshop out of the yard). Designed with the doorway on -x' and then turned by
-- Layout.StationYaw (90 deg) about the shaft axis so the doorway faces +z (the yard): the "-x'"
-- pieces below end up in front (+z), "+x'" pieces at the back, "+z" pieces on the fence side.
-- In the yard (yard x', z) the turned station covers: tower x' 18.65..29.35, z -59.35..-48.65
-- (its front 1 stud before the storage / collector piers), porch and canopy x' 17.6..30.4 to about
-- z -44, counterweight channel back z -62 (the back fence foot is at z -63.3).
-- Pieces in DESIGN coordinates before the turn, walkway (-x') first:
--   (the UPGRADE TREE kiosk that stood at x' 8..10.4 was removed)
--   porch          x' 10.3..14.8, z -42.4..-29.6: plated deck, canopy with lamps, arrows, the
--                  surface stop stands under the canopy (Layout.SurfaceArrival, 7.8 studs out
--                  from the shaft axis)
--   tower          x' 14.65..25.35, z -41.35..-30.65, to y 21.2: steel tower round the shaft,
--                  freight doors (vertical bi-parting, client-animated), glowing frame, the
--                  "Gate" lintel (NavTarget, Attachment "PromptAnchor"), MINE ELEVATOR sign,
--                  depth lamps "DepthLamp1..5" (MineWorld colours them), glass window onto the
--                  cage, the depth sign (SurfaceGui "DepthSignGui"; row station: on the
--                  machine-room front over the doorway) and down-chevrons on +z
--   machine room   y 21.2..27.3 with lit windows, the head sheave (Model "Wheel", part "Axle")
--                  on the roof, the counterweight (Model "Counterweight", client-animated) in a
--                  channel on the +x' face
--   annex          (options.Annex, never for the row station: yards whose Workshop stood behind
--                  the shaft) the hoist house over the old Workshop lot, x' 16..32.4,
--                  z -62.6..-42, with its chimney
-- Every part is anchored; only what a player can bump into collides (and the canopy, so the
-- default camera's occlusion keeps out of the tower). Nothing collides inside the shaft opening.
-- Local design space: x' (+ towards the yard fence), z (+ towards the yard centre), y = world y
-- (row station: before the turn).
local RUST = C(186, 72, 50)
local RUST_DARK = C(118, 44, 36)
local CREAM = C(240, 226, 196)
local ROOF = C(58, 66, 86)
local BRICK = C(194, 104, 76)
local CAVE = C(110, 214, 255) -- cave glow (caverns crystal blue)
local WARM = C(255, 220, 150)
local GOLD = C(255, 196, 54)
local TEAL = C(44, 150, 128)
local INK = C(28, 26, 30)

-- UPGRADE TREE kiosk: MineWorld moves the yard's UpgradeAnchor / UpgradeInteractionZone here.
S.Kiosk = {
	Anchor = V(8.0, 4.4, -31.6),
	Zone = CF(4.6, 5.5, -31.0),
	ZoneSize = V(7.6, 9, 5.2),
}
-- The client cage's hoist rope ends in the machine room floor (MineClient fits it every move).
S.RopeTopY = 21.2
S.CageHeight = 8.2
-- Freight doors: how far each leaf slides (studs, world Y) to close the doorway.
S.DoorTravel = 4.5

local function surfaceGui(part: BasePart, name: string, face: Enum.NormalId, pps: number, maxDistance: number): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.Parent = part
	local bg = Instance.new("Frame")
	bg.Name = "Back"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C(26, 22, 22)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	return gui, bg
end

local function text(parent: Instance, name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?, noTranslate: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = value
	t.TextStrokeTransparency = 0.6
	if noTranslate then
		t:SetAttribute("NoTranslate", true)
	end
	t.Parent = parent
	return t
end

-- Yellow / black hazard band on a face: a yellow strip with dark diagonal stripes.
-- cf: centre of the band's front face, its X axis along the band, -Z out of the face.
local function hazard(b: any, cf: CFrame, length: number, height: number, name: string)
	b:Box(V(length, height, 0.08), cf, SAFETY, "SmoothPlastic", { Name = name, CastShadow = false })
	b:Detail(function()
		local n = math.floor(length / 1.1)
		for i = 1, n do
			local x = -length / 2 + (i - 0.5) * length / n
			b:Box(V(0.32, height * 1.15, 0.04), cf * CF(x, 0, -0.05) * ANG(0, 0, rad(-40)), INK, "SmoothPlastic", { Name = name .. "Stripe", CastShadow = false })
		end
	end)
end

-- A neon "V" chevron pointing down: centre of the V's arms, in the plane of cf (cf -Z out).
local function chevron(b: any, cf: CFrame, size: number, color: Color3, name: string)
	for _, k in { -1, 1 } do
		b:Box(V(0.42 * size, 2.0 * size, 0.2), cf * CF(k * 0.62 * size, 0, 0) * ANG(0, 0, rad(-k * 40)), color, "Neon", { Name = name, CastShadow = false })
	end
end

-- Glowing cave crystals (a small cluster of prisms) standing on cf.
local function crystals(b: any, cf: CFrame, scale: number, count: number)
	local spec = { { 0, 0, 0, 0.55, 2.2 }, { 0.5, 0.2, 0.3, 0.4, 1.5 }, { -0.45, -0.25, 0.4, 0.36, 1.2 }, { 0.15, -0.5, -0.5, 0.32, 1.0 } }
	for i = 1, math.min(count, #spec) do
		local s = spec[i]
		local lean = ANG(rad(s[3] * 30), rad(i * 67), rad(-s[2] * 35))
		b:Prism(cf * CF(s[2] * scale, 0, s[3] * scale) * lean, s[4] * scale, s[5] * scale, s[4] * scale * 0.9, i == 1 and CAVE or C(170, 236, 255), i == 1 and "Neon" or "Glass", { Name = "StationCrystal", CastShadow = false })
	end
end

local function boulder(b: any, cf: CFrame, size: Vector3, tone: Color3)
	b:Ellipsoid(size, cf, tone, "Slate", { Name = "StationRock" })
end

-- The hoist house over the old Workshop lot (design x' 16..32.4, z -62.6..-42).
local function annex(b: any)
	local x0, x1, z0, z1 = 16.2, 32.2, -62.4, -42.2
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local w, d = x1 - x0, z1 - z0
	local base, eave = 1.8, 12.0
	collide(b:Box(V(w + 0.4, 0.9, d + 0.4), CF(cx, 1.35, cz), CONCRETE, "Concrete", { Name = "HoistPlinth" }))
	local hgt = eave - base
	local yc = (base + eave) / 2
	collide(b:Box(V(w, hgt, 0.6), CF(cx, yc, z1 - 0.3), BRICK, "Brick", { Name = "HoistWall" }))
	collide(b:Box(V(w, hgt, 0.6), CF(cx, yc, z0 + 0.3), BRICK, "Brick", { Name = "HoistWall" }))
	collide(b:Box(V(0.6, hgt, d - 1.2), CF(x0 + 0.3, yc, cz), BRICK, "Brick", { Name = "HoistWall" }))
	collide(b:Box(V(0.6, hgt, d - 1.2), CF(x1 - 0.3, yc, cz), BRICK, "Brick", { Name = "HoistWall" }))
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			b:Box(V(1.1, hgt + 0.6, 1.1), CF(x, yc + 0.3, z), CREAM, "Concrete", { Name = "HoistPilaster" })
		end
	end
	-- Cornice and the gable roof (ridge along x', the slopes face the yard and the back).
	b:Box(V(w + 1.4, 0.6, d + 0.8), CF(cx, eave + 0.3, cz), CREAM, "Concrete", { Name = "HoistCornice" })
	b:Roof(V(w + 1.2, 3.6, d + 0.6), CF(cx, eave + 0.6 + 1.8, cz), ROOF, "Slate", { Name = "HoistRoof" })
	-- Roof lantern: a raised clerestory with glowing panes along the ridge.
	b:Box(V(9, 1.6, 2.6), CF(cx, eave + 0.6 + 3.6 + 0.2, cz), CREAM, "Concrete", { Name = "HoistLantern" })
	for _, k in { -1, 1 } do
		b:Box(V(7.6, 0.9, 0.12), CF(cx, eave + 4.5, cz + k * 1.32), WARM, "Neon", { Name = "HoistLanternGlow", CastShadow = false })
	end
	b:Box(V(9.6, 0.35, 3.2), CF(cx, eave + 5.35, cz), ROOF, "Slate", { Name = "HoistLanternCap" })
	-- Lit arched windows on the yard face (right of the tower) and the fence side.
	local function window(cf: CFrame, width: number, height: number)
		b:Box(V(width, height, 0.12), cf, WARM, "Neon", { Name = "HoistWindow", CastShadow = false })
		b:CylZ(0.12, width, cf * CF(0, height / 2, 0), WARM, "Neon", { Name = "HoistWindowArch", CastShadow = false })
		b:Box(V(width + 0.6, 0.3, 0.5), cf * CF(0, -height / 2 - 0.15, 0.1), CREAM, "Concrete", { Name = "HoistSill" })
		b:Detail(function()
			b:Box(V(0.14, height, 0.16), cf * CF(0, 0, -0.04), RUST_DARK, "Metal", { Name = "HoistMullion" })
			b:Box(V(width, 0.14, 0.16), cf * CF(0, 0.2, -0.04), RUST_DARK, "Metal", { Name = "HoistMullion" })
		end)
	end
	for _, x in { 26.6, 30.85 } do
		window(CF(x, 6.4, z1 + 0.04), 1.5, 4.6)
	end
	for _, z in { -46.5, -52.3, -58.1 } do
		window(CF(x1 + 0.04, 6.4, z) * ANG(0, math.pi / 2, 0), 2.2, 4.6)
	end
	-- Door with a lamp and a little step on the yard face.
	b:Box(V(2.3, 4.6, 0.2), CF(28.8, 4.1, z1 + 0.05), C(92, 60, 40), "WoodPlanks", { Name = "HoistDoor" })
	b:Box(V(2.9, 0.4, 0.4), CF(28.8, 6.6, z1 + 0.15), CREAM, "Concrete", { Name = "HoistDoorHead" })
	b:Box(V(0.6, 0.6, 0.4), CF(28.8, 7.3, z1 + 0.25), WARM, "Neon", { Name = "HoistDoorLamp", CastShadow = false })
	-- Chimney stack with bands and a warning light, a little smoke.
	local stack = CF(29.6, 0, -58.6)
	for i = 0, 3 do
		b:CylY(4.6, 2.3 - i * 0.12, stack * CF(0, eave + 1.5 + i * 4.5, 0), i % 2 == 0 and RUST or CREAM, "Brick", { Name = "Chimney" })
	end
	local stackTop = eave + 1.5 + 3 * 4.5 + 2.3
	b:CylY(0.6, 2.4, stack * CF(0, stackTop + 0.3, 0), RUST_DARK, "Metal", { Name = "ChimneyCap" })
	local warn = b:Ball(0.7, stack * CF(0, stackTop + 1.0, 0), C(255, 60, 40), "Neon", { Name = "ChimneyBeacon", CastShadow = false })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ChimneySmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 1.2
	smoke.Lifetime = NumberRange.new(5, 8)
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.Size = NumberSequence.new(1.6, 6)
	smoke.Color = ColorSequence.new(C(200, 200, 205))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	smoke.RotSpeed = NumberRange.new(-12, 12)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.LightInfluence = 1
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = warn
	-- Cable gantry from the machine room down to the hoist house roof.
	for _, x in { 22.8, 25.0 } do
		b:Beam(V(x, 22.0, -41.6), V(x, 16.4, -51.0), 0.35, RUST_DARK, "Metal", { Name = "Gantry" })
		b:Rod(V(x + 0.6, 22.4, -41.6), V(x + 0.6, 16.8, -51.0), 0.22, ROPE, "Metal", { Name = "GantryCable" })
	end
	b:Detail(function()
		for i = 1, 3 do
			local t = i / 4
			local p = V(23.9, 22.0 + (16.4 - 22.0) * t, -41.6 + (-51.0 + 41.6) * t)
			b:Box(V(2.6, 0.22, 0.3), CF(p), RUST_DARK, "Metal", { Name = "GantryTie" })
		end
		-- Crates and a barrel by the door.
		b:Box(V(1.3, 1.3, 1.3), CF(26.4, 1.65, -41.3) * ANG(0, rad(12), 0), C(150, 104, 60), "WoodPlanks", { Name = "Crate" })
	end)
end

function S.Headframe(options: { Annex: boolean? }?): Model
	local b = Forge.Builder("MineHeadframe")
	local s = Layout.Shaft
	local SX, SZ, G = s.X, s.Z, Layout.GroundY
	local TC, TOP = 4.7, 21.2 -- column centre offset from the shaft axis, tower body top
	local front = SX - TC - 0.65 -- x' 14.65: front face of the tower (the walkway side)
	-- Service-row station (Layout.StationYaw ~= 0): built as designed, then turned about the shaft
	-- axis at the end so the doorway faces the yard; the pieces that would land behind the tower
	-- (outside the lot) are left out or moved beside it.
	local row = (Layout.StationYaw or 0) ~= 0
	-- The service strip (UtilityApron) is paved 0.25 above the lawn: deck dressing sits on top of it.
	local DECK = row and 0.27 or 0

	------------------------------------------------------------------------------------------------
	-- TOWER: four columns round the 8 x 8 opening, panel walls, the doorway on -x'.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			collide(b:Box(V(1.3, TOP - G, 1.3), CF(SX + x * TC, (G + TOP) / 2, SZ + z * TC), RUST_DARK, "Metal", { Name = "TowerColumn" }))
			b:Box(V(1.7, 0.5, 1.7), CF(SX + x * TC, G + 0.25, SZ + z * TC), CONCRETE, "Concrete", { Name = "ColumnFoot" })
		end
	end
	local span = 2 * TC - 1.3 -- 8.1 between the columns
	local wallY, wallH = (G + TOP) / 2, TOP - G
	collide(b:Box(V(0.6, wallH, span), CF(SX + 4.6, wallY, SZ), RUST, "Metal", { Name = "TowerWall" }))
	collide(b:Box(V(span, wallH, 0.6), CF(SX, wallY, SZ - 4.6), RUST, "Metal", { Name = "TowerWall" }))
	-- +z wall with a tall window onto the cage (the yard watches the elevator).
	local wz = SZ + 4.6
	collide(b:Box(V(span, 1.2, 0.6), CF(SX, G + 0.6, wz), RUST, "Metal", { Name = "TowerWall" }))
	collide(b:Box(V(span, TOP - 9.8, 0.6), CF(SX, (9.8 + TOP) / 2, wz), RUST, "Metal", { Name = "TowerWall" }))
	for _, k in { -1, 1 } do
		collide(b:Box(V(1.85, 7.6, 0.6), CF(SX + k * 3.125, 6.0, wz), RUST, "Metal", { Name = "TowerWall" }))
	end
	collide(b:Box(V(4.4, 7.6, 0.15), CF(SX, 6.0, wz + 0.15), C(170, 225, 255), "Glass", { Name = "ShaftWindow", Transparency = 0.6, CastShadow = false }))
	for _, row in { { 0, 9.9, 4.9, 0.3 }, { 0, 2.1, 4.9, 0.3 }, { -2.35, 6.0, 0.3, 8.0 }, { 2.35, 6.0, 0.3, 8.0 } } do
		b:Box(V(row[3], row[4], 0.25), CF(SX + row[1], row[2], wz + 0.38), CREAM, "Metal", { Name = "WindowFrame" })
	end
	-- Header panel over the doorway (the door opening: z -40..-32, y 1..10).
	collide(b:Box(V(0.6, TOP - 10, span), CF(SX - 4.6, (10 + TOP) / 2, SZ), RUST, "Metal", { Name = "TowerWall" }))
	-- Cream bands round the tower and a concrete skirting.
	for _, y in { 10.4, 16.0 } do
		b:Box(V(0.25, 0.45, span + 2.6), CF(SX + TC + 0.78, y, SZ), CREAM, "Metal", { Name = "TowerBand" })
		b:Box(V(span + 2.6, 0.45, 0.25), CF(SX, y, SZ - TC - 0.78), CREAM, "Metal", { Name = "TowerBand" })
	end
	b:Box(V(span + 2.6, 0.45, 0.25), CF(SX, 16.0, SZ + TC + 0.78), CREAM, "Metal", { Name = "TowerBand" })
	b:Box(V(0.4, 0.9, span), CF(SX + TC + 0.3, G + 0.45, SZ), CONCRETE, "Concrete", { Name = "Skirting" })
	b:Box(V(span, 0.9, 0.4), CF(SX, G + 0.45, SZ - TC - 0.3), CONCRETE, "Concrete", { Name = "Skirting" })
	b:Detail(function()
		-- Rivets down the corner columns.
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				for y = 3, 19, 4 do
					b:Ball(0.28, CF(SX + x * (TC + 0.66), y, SZ + z * TC), IRON, "Metal", { Name = "Rivet", CastShadow = false })
				end
			end
		end
		-- Service ladder up the -z face to the machine room.
		for _, x in { 22.0, 23.1 } do
			b:Box(V(0.18, TOP - G, 0.18), CF(x, (G + TOP) / 2, SZ - TC - 0.95), SAFETY, "Metal", { Name = "LadderRail" })
		end
		for y = 2.5, TOP - 1, 1.6 do
			b:Box(V(1.1, 0.12, 0.12), CF(22.55, y, SZ - TC - 0.95), IRON, "Metal", { Name = "LadderRung" })
		end
	end)

	------------------------------------------------------------------------------------------------
	-- DOORWAY: threshold, glowing frame, the hazard lintel "Gate", call panel, freight doors.
	collide(b:Box(V(1.3, 0.12, 8), CF(front + 0.65, G + DECK + 0.04, SZ), SAFETY, "DiamondPlate", { Name = "Threshold" }))
	b:Detail(function()
		for i = -3, 3 do
			b:Box(V(1.32, 0.04, 0.3), CF(front + 0.65, G + DECK + 0.11, SZ + i * 1.1) * ANG(0, rad(40), 0), INK, "SmoothPlastic", { Name = "ThresholdStripe", CastShadow = false })
		end
	end)
	for _, k in { -1, 1 } do
		b:Box(V(0.14, 9.0, 0.3), CF(front - 0.06, G + 4.5, SZ + k * 3.95), WARM, "Neon", { Name = "DoorGlow", CastShadow = false })
	end
	b:Box(V(0.14, 0.3, 8.2), CF(front - 0.06, G + 9.0, SZ), WARM, "Neon", { Name = "DoorGlow", CastShadow = false })
	local gate = collide(b:Box(V(1.0, 1.0, span + 2.8), CF(front + 0.25, 10.5, SZ), SAFETY, "Metal", { Name = "Gate" }))
	hazard(b, CF(front - 0.27, 10.5, SZ) * ANG(0, math.pi / 2, 0), span + 2.6, 0.8, "GateHazard")
	local promptAnchor = Instance.new("Attachment")
	promptAnchor.Name = "PromptAnchor"
	-- In the doorway, in front of the doors at chest height (design x' 13, y 4.4).
	promptAnchor.Position = V(13.0 - (front + 0.25), 4.4 - 10.5, 0)
	promptAnchor.Parent = gate
	-- Call panel on the left jamb: a big green "down" button.
	local panel = b:Box(V(0.25, 1.8, 1.0), CF(front - 0.15, 4.6, SZ - TC), C(46, 50, 58), "Metal", { Name = "CallPanel" })
	b:Ball(0.55, panel.CFrame * CF(-0.16, 0.35, 0), C(80, 255, 130), "Neon", { Name = "CallButton", CastShadow = false })
	b:Ball(0.4, panel.CFrame * CF(-0.14, -0.35, 0), C(255, 196, 70), "Neon", { Name = "CallButton", CastShadow = false })
	-- Freight doors (open: the upper leaf sits behind the header panel, the lower leaf under the
	-- threshold). MineClient slides them shut while the cage is away (attribute Slide = Y move).
	local doors = b:Folder("Doors")
	local leafX = SX - 4.12
	local travel = S.DoorTravel
	for _, spec in { { "DoorUpper", 1, -travel }, { "DoorLower", -1, travel } } do
		local leaf = b:Folder(spec[1])
		leaf:SetAttribute("Slide", spec[3])
		local open = spec[2] * travel
		local y = G + travel / 2 + (spec[2] > 0 and travel or 0) + open -- closed centre + open offset
		b:Box(V(0.24, travel, 8.1), CF(leafX, y, SZ), RUST_DARK, "Metal", { Name = "DoorLeaf", CastShadow = false })
		local edge = spec[2] > 0 and -travel / 2 + 0.35 or travel / 2 - 0.35
		hazard(b, CF(leafX - 0.13, y + edge, SZ) * ANG(0, math.pi / 2, 0), 8.0, 0.6, "DoorHazard")
		if spec[2] > 0 then
			b:Box(V(0.26, 0.7, 3.4), CF(leafX, y + 0.6, SZ), C(30, 44, 60), "Glass", { Name = "DoorSlot", CastShadow = false })
		else
			b:Box(V(0.26, 0.9, 8.1), CF(leafX, y - travel / 2 + 0.6, SZ), IRON, "DiamondPlate", { Name = "DoorKick", CastShadow = false })
		end
		b:Into(doors)
	end
	b:Into(b.Model)

	------------------------------------------------------------------------------------------------
	-- FRONT FACE above the canopy: MINE ELEVATOR sign and the depth lamps.
	local sign = b:Box(V(0.3, 3.8, span + 1.4), CF(front - 0.2, 16.3, SZ), C(30, 26, 26), "Metal", { Name = "ElevatorSign" })
	b:Box(V(0.4, 0.3, span + 1.8), sign.CFrame * CF(0, 2.05, 0), SAFETY, "Metal", { Name = "SignTrim" })
	b:Box(V(0.4, 0.3, span + 1.8), sign.CFrame * CF(0, -2.05, 0), SAFETY, "Metal", { Name = "SignTrim" })
	local _, signBg = surfaceGui(sign, "ElevatorSignGui", Enum.NormalId.Left, 50, 160)
	local signStroke = Instance.new("UIStroke")
	signStroke.Color = GOLD
	signStroke.Thickness = 6
	signStroke.Parent = signBg
	text(signBg, "Title", "MINE ELEVATOR", 0.05, 0.08, 0.9, 0.5, C(255, 236, 170))
	text(signBg, "Arrows", "▼   ▼   ▼", 0.1, 0.6, 0.8, 0.32, CAVE, Enum.Font.FredokaOne, true)
	local plate = b:Box(V(0.3, 1.5, span), CF(front - 0.15, 19.4, SZ), C(24, 22, 26), "Metal", { Name = "DepthPlate" })
	for i = 1, 5 do
		local theme = Themes[i]
		b:Ball(0.85, plate.CFrame * CF(-0.25, 0, (i - 3) * 1.55), theme.Accent, "Neon", { Name = "DepthLamp" .. i, CastShadow = false })
	end

	------------------------------------------------------------------------------------------------
	-- +Z FACE (towards the yard; row station: the fence side): the depth sign (row station: on the
	-- machine-room front), down-chevrons and the paw emblem.
	local signZ = SZ + TC + 0.8
	-- Row station: the sign hangs on the machine-room front (over the doorway), facing the yard.
	local signCF = row and CF(SX - TC - 1.35, 24.3, SZ) * ANG(0, -math.pi / 2, 0) or CF(SX, 13.0, signZ)
	local depthSign = b:Box(V(7.2, 4.4, 0.3), signCF, C(36, 30, 26), "Metal", { Name = "DepthSign" })
	b:Box(V(7.6, 0.3, 0.45), depthSign.CFrame * CF(0, 2.35, 0), SAFETY, "Metal", { Name = "SignTrim" })
	b:Box(V(7.6, 0.3, 0.45), depthSign.CFrame * CF(0, -2.35, 0), SAFETY, "Metal", { Name = "SignTrim" })
	-- The sign faces +z: its Back face (+Z local) points at the yard.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DepthSignGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.1
	gui.MaxDistance = 160
	gui.Parent = depthSign
	local bg = Instance.new("Frame")
	bg.Name = "Back"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C(28, 24, 22)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.Color = Themes[1].Accent
	stroke.Thickness = 8
	stroke.Parent = bg
	text(bg, "Caption", "DOGS DIG AT", 0.04, 0.06, 0.92, 0.2, C(255, 226, 170), Enum.Font.FredokaOne)
	text(bg, "Layer", Themes[1].Title, 0.04, 0.3, 0.92, 0.42, Themes[1].Accent)
	text(bg, "Depth", Themes[1].Depth, 0.04, 0.74, 0.92, 0.2, C(230, 230, 236), Enum.Font.FredokaOne)
	for i, y in { 18.6, 17.0 } do
		chevron(b, CF(SX, y, signZ + 0.05) * ANG(0, math.pi, 0), i == 1 and 0.9 or 1.0, CAVE, "DownChevron")
	end

	------------------------------------------------------------------------------------------------
	-- MACHINE ROOM on top of the tower, lit windows all round.
	local mr0, mr1 = TOP, 27.0
	b:Box(V(12.2, 0.6, 12.2), CF(SX, mr0 + 0.3, SZ), STEEL_DARK, "Metal", { Name = "MachineFloor" })
	local lowTop, winTop = mr0 + 1.9, mr0 + 4.2
	for _, f in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongX = f[1] == 0
		local cf = CF(SX + f[1] * 5.6, 0, SZ + f[2] * 5.6)
		local function piece(name: string, len: number, y0: number, y1: number, offset: number, color: Color3, mat: string)
			local size = alongX and V(len, y1 - y0, 0.4) or V(0.4, y1 - y0, len)
			local off = alongX and V(offset, 0, 0) or V(0, 0, offset)
			b:Box(size, cf * CF(off.X, (y0 + y1) / 2, off.Z), color, mat, { Name = name })
		end
		piece("MachineWall", 11.2, mr0 + 0.6, lowTop, 0, CREAM, "Concrete")
		piece("MachineWall", 11.2, winTop, mr1, 0, CREAM, "Concrete")
		for i = -1, 1 do
			piece("MachineWindow", 2.6, lowTop, winTop, i * 3.5, WARM, "Neon")
		end
		for i = -1, 1, 2 do
			piece("MachineMullion", 0.9, lowTop, winTop, i * 1.75, CREAM, "Concrete")
		end
	end
	b:Box(V(10.6, winTop - lowTop, 10.6), CF(SX, (lowTop + winTop) / 2, SZ), C(40, 36, 34), "SmoothPlastic", { Name = "MachineCore", CastShadow = false })
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:Box(V(0.8, mr1 - mr0, 0.8), CF(SX + x * 5.6, (mr0 + mr1) / 2, SZ + z * 5.6), RUST_DARK, "Metal", { Name = "MachinePost" })
		end
	end
	b:Box(V(13.2, 0.3, 13.2), CF(SX, mr1 + 0.05, SZ), SAFETY, "Metal", { Name = "RoofTrim" })
	b:Box(V(13.0, 0.5, 13.0), CF(SX, mr1 + 0.45, SZ), ROOF, "Slate", { Name = "MachineRoof" })
	local roofY = mr1 + 0.7
	-- DOGROTS paw emblem on the yard side of the machine room.
	local paw = CF(SX, mr0 + 3.05, SZ + 5.85)
	b:Disc(paw * ANG(math.pi / 2, 0, 0), 2.6, 0.2, INK, "Metal", { Name = "PawBadge" })
	b:Ellipsoid(V(1.0, 0.8, 0.2), paw * CF(0, -0.3, 0.12), GOLD, "Neon", { Name = "PawPad", CastShadow = false })
	for i = -1.5, 1.5 do
		local a = rad(i * 32)
		b:Ball(0.42, paw * CF(math.sin(a) * 0.82, 0.25 + math.cos(a) * 0.45, 0.12), GOLD, "Neon", { Name = "PawToe", CastShadow = false })
	end
	-- Beacons on the roof corners.
	for _, z in { -1, 1 } do
		b:Box(V(0.3, 1.4, 0.3), CF(SX - 5.9, roofY + 0.7, SZ + z * 5.9), IRON, "Metal", { Name = "BeaconMast" })
		b:Ball(0.75, CF(SX - 5.9, roofY + 1.6, SZ + z * 5.9), C(255, 70, 40), "Neon", { Name = "Beacon", CastShadow = false })
	end
	b:Detail(function()
		b:Box(V(2.2, 1.2, 1.6), CF(SX - 2.6, roofY + 0.6, SZ - 3.6), IRON, "Metal", { Name = "RoofVent" })
		b:Box(V(2.4, 0.2, 1.8), CF(SX - 2.6, roofY + 1.3, SZ - 3.6), STEEL_DARK, "Metal", { Name = "RoofVentCap" })
	end)

	------------------------------------------------------------------------------------------------
	-- HEAD SHEAVE on an A-frame on the roof; its rim is tangent over the shaft axis (the cage
	-- rope) on one side and over the counterweight channel on the other.
	local R = 3.4
	local wheelC = CF(SX + R, roofY + R + 0.9, SZ)
	for _, z in { -1.5, 1.5 } do
		for _, x in { SX + 0.6, SX + 2 * R - 0.6 } do
			b:Beam(V(x, roofY, SZ + z), V(SX + R, wheelC.Y, SZ + z * 0.95), 0.45, RUST, "Metal", { Name = "SheaveLeg" })
		end
		b:Box(V(1.0, 1.0, 0.5), CF(SX + R, wheelC.Y, SZ + z * 0.95), STEEL_DARK, "Metal", { Name = "Bearing" })
	end
	b:Beam(V(SX + 0.9, roofY + 1.0, SZ - 1.5), V(SX + 0.9, roofY + 1.0, SZ + 1.5), 0.3, RUST_DARK, "Metal", { Name = "SheaveTie" })
	b:Beam(V(SX + 2 * R - 0.9, roofY + 1.0, SZ - 1.5), V(SX + 2 * R - 0.9, roofY + 1.0, SZ + 1.5), 0.3, RUST_DARK, "Metal", { Name = "SheaveTie" })
	local wheel = b:Folder("Wheel")
	b:Ring(wheelC * ANG(math.pi / 2, 0, 0), R, 0.5, IRON, "Metal", 18, { Name = "Rim" })
	b:Ring(wheelC * ANG(math.pi / 2, 0, 0), R - 0.55, 0.22, SAFETY, "Metal", 14, { Name = "Groove" })
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi
		b:Rod(wheelC.Position, (wheelC * CF(math.cos(a) * (R - 0.3), math.sin(a) * (R - 0.3), 0)).Position, 0.24, i % 2 == 0 and RUST or IRON, "Metal", { Name = "Spoke" })
	end
	b:CylZ(1.0, 1.1, wheelC, SAFETY, "Metal", { Name = "Hub" })
	b:CylZ(2.9, 0.35, wheelC, IRON, "Metal", { Name = "Axle" })
	b:Into(b.Model)
	wheel:SetAttribute("SpinAxisZ", true)
	b:Rod(V(SX, wheelC.Y, SZ), V(SX, roofY - 0.1, SZ), 0.2, ROPE, "Metal", { Name = "HoistRope" })

	------------------------------------------------------------------------------------------------
	-- COUNTERWEIGHT channel on the +x' face; the weight rides it when the cage moves.
	local cwX = SX + 2 * R -- x' 26.8, under the sheave's far rim
	b:Box(V(0.3, 19.6, 3.4), CF(SX + TC + 0.85, G + 10.2, SZ), STEEL_DARK, "Metal", { Name = "ChannelBack" })
	for _, k in { -1, 1 } do
		b:Box(V(2.6, 19.6, 0.3), CF(cwX - 0.2, G + 10.2, SZ + k * 1.55), SAFETY, "Metal", { Name = "ChannelRail" })
	end
	b:Box(V(2.8, 0.4, 3.6), CF(cwX - 0.2, G + 0.2, SZ), CONCRETE, "Concrete", { Name = "ChannelBuffer" })
	local cwY = 12.0
	local cw = b:Folder("Counterweight")
	cw:SetAttribute("Travel", 7.5)
	b:Box(V(2.0, 3.0, 2.4), CF(cwX - 0.1, cwY, SZ), STEEL_DARK, "Metal", { Name = "Weight" })
	for _, y in { -0.8, 0.8 } do
		b:Box(V(2.05, 0.45, 2.45), CF(cwX - 0.1, cwY + y, SZ), SAFETY, "SmoothPlastic", { Name = "WeightBand" })
	end
	b:Box(V(0.5, 0.6, 0.5), CF(cwX, cwY + 1.8, SZ), IRON, "Metal", { Name = "WeightHook" })
	b:Into(b.Model)
	local counterRope = b:Rod(V(cwX, wheelC.Y, SZ), V(cwX, cwY + 2.1, SZ), 0.18, ROPE, "Metal", { Name = "CounterRope" })
	counterRope:SetAttribute("TopY", wheelC.Y)

	------------------------------------------------------------------------------------------------
	-- PORCH: plated deck, canopy on two posts, pendant lamps, floor arrows.
	local px0, px1 = 10.6, front + 0.15
	collide(b:Box(V(px1 - px0, 0.12, 12), CF((px0 + px1) / 2, G + DECK + 0.04, SZ), IRON, "DiamondPlate", { Name = "PorchDeck" }))
	for i = 0, 1 do
		local x = 12.0 + i * 1.5
		for _, k in { -1, 1 } do
			b:Box(V(0.36, 0.03, 1.7), CF(x, G + DECK + 0.115, SZ + k * 0.62) * ANG(0, rad(-k * 42), 0), SAFETY, "SmoothPlastic", { Name = "FloorArrow", CastShadow = false })
		end
	end
	b:Detail(function()
		for i = 0, 5 do
			b:Box(V(0.4, 0.03, 2.0), CF(px0 + 0.25, G + DECK + 0.115, SZ - 5 + i * 2), i % 2 == 0 and SAFETY or INK, "SmoothPlastic", { Name = "DeckEdge", CastShadow = false })
		end
	end)
	for _, k in { -1, 1 } do
		local z = SZ + k * 6.0
		collide(b:Box(V(0.6, 10.0, 0.6), CF(10.9, G + 5.0, z), RUST_DARK, "Metal", { Name = "CanopyPost" }))
		b:Box(V(0.9, 0.4, 0.9), CF(10.9, G + 0.2, z), CONCRETE, "Concrete", { Name = "CanopyPostFoot" })
		b:Beam(V(10.9, 9.2, z), V(13.4, 10.95, z), 0.3, RUST_DARK, "Metal", { Name = "CanopyBrace" })
	end
	collide(b:Box(V(front - 10.3, 0.45, 12.8), CF((10.3 + front) / 2, 11.22, SZ), RUST, "Metal", { Name = "Canopy" }))
	b:Box(V(0.3, 0.75, 12.8), CF(10.25, 11.1, SZ), SAFETY, "Metal", { Name = "CanopyFascia" })
	b:Box(V(0.12, 0.14, 12.4), CF(10.06, 10.8, SZ), WARM, "Neon", { Name = "CanopyGlow", CastShadow = false })
	b:Box(V(front - 10.3, 0.12, 12.9), CF((10.3 + front) / 2, 11.5, SZ), CREAM, "Metal", { Name = "CanopyTrim" })
	for _, k in { -1, 1 } do
		local z = SZ + k * 3.4
		b:Box(V(0.12, 0.6, 0.12), CF(12.4, 10.7, z), IRON, "Metal", { Name = "LampStem" })
		b:CylY(0.35, 1.0, CF(12.4, 10.35, z), STEEL_DARK, "Metal", { Name = "LampShade" })
		local bulb = b:Ball(0.6, CF(12.4, 10.0, z), WARM, "Neon", { Name = "PorchLamp", CastShadow = false })
		b:Light(bulb, C(255, 214, 150), 15, 1.15, "Point")
	end

	-- (The UPGRADE TREE kiosk and its UPGRADES sign in front of the mine were removed: the tree opens
	-- from the menu, MY YARD and the HUD; nothing stands in front of the elevator any more.)

	------------------------------------------------------------------------------------------------
	-- BASE: rocks with glowing cave crystals, glowing cracks: "the caves start right here".
	local rock, rockDark = C(116, 126, 142), C(84, 92, 108)
	boulder(b, CF(SX + 6.0, G + 0.7, SZ + 4.9) * ANG(0, rad(20), 0), V(3.0, 2.2, 2.4), rock)
	-- (Row station: this corner lands behind the tower, so the small rock keeps 1.4 studs off the back
	-- fence line and the skins' fence dressing.)
	local rockB = row and CF(SX + 6.6, G + 0.5, SZ + 3.6) or CF(SX + 7.4, G + 0.5, SZ + 4.0)
	boulder(b, rockB * ANG(0, rad(-30), 0), V(2.0, 1.5, 1.8), rockDark)
	crystals(b, CF(SX + 6.2, G + 1.2, SZ + 4.8) * ANG(rad(-15), 0, rad(10)), 1.0, 4)
	boulder(b, CF(front - 0.3, G + 0.6, SZ + 5.3) * ANG(0, rad(40), 0), V(2.2, 1.6, 1.4), rock)
	crystals(b, CF(front - 0.2, G + 0.9, SZ + 5.2) * ANG(rad(-20), 0, 0), 0.7, 3)
	local glowRock = b:Ellipsoid(V(1.0, 0.7, 1.0), CF(SX + 6.3, G + 1.8, SZ + 4.8), CAVE, "Neon", { Name = "StationCrystalCore", CastShadow = false })
	b:Light(glowRock, CAVE, 11, 1.2, "Point")
	for i, c in (row and {} or { { 25.9, -33.2, 25 }, { 27.6, -39.0, -15 }, { 28.0, -40.9, 60 }, { 31.0, -38.6, -70 } }) do
		local cf = CF(c[1], G + 0.03, c[2]) * ANG(0, rad(c[3]), 0)
		b:Box(V(2.6, 0.04, 0.22), cf, CAVE, "Neon", { Name = "GlowCrack", CastShadow = false })
		b:Box(V(1.4, 0.04, 0.16), cf * CF(1.6, 0, 0.35) * ANG(0, rad(i % 2 == 0 and 35 or -35), 0), CAVE, "Neon", { Name = "GlowCrack", CastShadow = false })
	end

	------------------------------------------------------------------------------------------------
	-- +X' SIDE (row station: behind the tower, outside the lot, so only barrels and crates beside
	-- the tower): transformer, cable conduits into the tower, barrels and crates.
	if row then
		-- Beside the tower on the fence side (after the turn: x' +7.1..+7.6 from the shaft axis),
		-- standing on the service-strip paving (0.25 above the lawn).
		local pave = G + 0.25
		collide(b:CylY(1.7, 1.3, CF(SX + 2.0, pave + 0.85, SZ + 7.2), C(60, 110, 160), "Metal", { Name = "Barrel" }))
		collide(b:CylY(1.7, 1.3, CF(SX + 3.6, pave + 0.85, SZ + 7.6), RUST, "Metal", { Name = "Barrel" }))
		collide(b:Box(V(1.6, 1.6, 1.6), CF(SX - 0.2, pave + 0.8, SZ + 7.1) * ANG(0, rad(15), 0), C(150, 104, 60), "WoodPlanks", { Name = "Crate" }))
		b:Box(V(1.2, 1.2, 1.2), CF(SX - 0.1, pave + 2.2, SZ + 7.15) * ANG(0, rad(-10), 0), C(170, 122, 72), "WoodPlanks", { Name = "Crate" })
	else
		local tf = CF(30.7, G, -35.1)
		collide(b:Box(V(3.0, 3.2, 3.4), tf * CF(0, 1.6, 0), C(66, 108, 74), "Metal", { Name = "Transformer" }))
		b:Box(V(3.2, 0.3, 3.6), tf * CF(0, 3.35, 0), STEEL_DARK, "Metal", { Name = "TransformerLid" })
		for _, z in { -0.9, 0.9 } do
			b:CylY(0.8, 0.5, tf * CF(-0.6, 3.9, z), CREAM, "Ceramic", { Name = "Insulator" })
		end
		-- Lightning bolt on the transformer's yard side.
		for i, seg in { { -0.25, 0.5, 25 }, { 0.1, 0, -30 }, { -0.1, -0.5, 25 } } do
			b:Box(V(0.25, 0.75, 0.06), tf * CF(seg[1], 1.7 + seg[2], 1.72) * ANG(0, 0, rad(seg[3])), SAFETY, "Neon", { Name = "Bolt" .. i, CastShadow = false })
		end
		for _, y in { 2.4, 2.9 } do
			b:Rod(V(29.2, y, -33.9), V(SX + TC + 0.7, y + 1.4, -33.9), 0.22, STEEL_DARK, "Metal", { Name = "Conduit" })
		end
		b:Detail(function()
			for i = 0, 3 do
				b:Box(V(0.12, 2.4, 3.0), tf * CF(1.56, 1.6, -1.2 + i * 0.8), IRON, "Metal", { Name = "Fin" })
			end
		end)
		collide(b:CylY(1.7, 1.3, CF(31.1, G + 0.85, -31.0), C(60, 110, 160), "Metal", { Name = "Barrel" }))
		collide(b:CylY(1.7, 1.3, CF(31.7, G + 0.85, -32.4), RUST, "Metal", { Name = "Barrel" }))
		collide(b:Box(V(1.6, 1.6, 1.6), CF(29.3, G + 0.8, -30.95) * ANG(0, rad(15), 0), C(150, 104, 60), "WoodPlanks", { Name = "Crate" }))
		b:Box(V(1.2, 1.2, 1.2), CF(29.4, G + 2.2, -30.9) * ANG(0, rad(-10), 0), C(170, 122, 72), "WoodPlanks", { Name = "Crate" })
	end

	------------------------------------------------------------------------------------------------
	-- WALKWAY SIDE: lamp post with a "down to the mine" arrow sign (not for the row station: it
	-- would stand on the service-row walk; the MINE ELEVATOR sign faces the yard there).
	if not row then
		local postCF = CF(9.2, G, -41.4)
		collide(b:Box(V(0.4, 7.4, 0.4), postCF * CF(0, 3.7, 0), STEEL_DARK, "Metal", { Name = "SignPost" }))
		b:Box(V(0.9, 1.0, 0.9), postCF * CF(0, 7.7, 0), WARM, "Neon", { Name = "PostLantern", CastShadow = false })
		b:Box(V(1.2, 0.25, 1.2), postCF * CF(0, 8.3, 0), STEEL_DARK, "Metal", { Name = "PostLanternCap" })
		local arrow = b:Box(V(0.2, 1.1, 3.6), postCF * CF(0.15, 5.4, 1.4), C(30, 26, 26), "Metal", { Name = "ArrowSign" })
		local _, arrowBg = surfaceGui(arrow, "ArrowSignGui", Enum.NormalId.Left, 50, 90)
		arrowBg.BackgroundColor3 = C(40, 34, 30)
		text(arrowBg, "Title", "DOWN TO THE MINE", 0.04, 0.1, 0.92, 0.8, C(255, 226, 170))
	end

	if options and options.Annex and not row then
		annex(b)
	end

	local model = b:Finish()
	-- Turn the whole station about the shaft axis (Layout.StationYaw): the doorway faces +z. The
	-- invisible Forge root (the model's PrimaryPart / pivot) stays at the design origin, inside
	-- the yard, as for every other mine model.
	if row then
		local turn = CF(SX, 0, SZ) * ANG(0, Layout.StationYaw, 0) * CF(-SX, 0, -SZ)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= model.PrimaryPart then
				d.CFrame = turn * d.CFrame
			end
		end
	end
	return model
end

------------------------------------------------------------------------------------------------
-- Ore depot (server, the mirrored yards): fills the old Workshop lot when the Workshop stood on
-- the far side of the yard from the shaft. origin: the lot centre at design y = 0 (heights below are
-- design heights; the deck rests on the yard paving), -Z = towards the
-- back fence (the depot faces the yard). Ore carts on a siding, a hopper, crates, a lamp and a
-- sign pointing at the mine elevator (which is on the other side: design +x').
------------------------------------------------------------------------------------------------
function S.Depot(origin: CFrame, arrow: string?): Model
	local b = Forge.Builder("MineDepot")
	local O = origin
	collide(b:Box(V(14.6, 0.7, 12.6), O * CF(0, 1.55, -0.6), CONCRETE, "Concrete", { Name = "DepotPlatform" }))
	b:Box(V(14.8, 0.15, 0.4), O * CF(0, 1.95, 5.6), SAFETY, "SmoothPlastic", { Name = "DepotEdge", CastShadow = false })
	local top = 1.9
	-- Siding along x'.
	for _, z in { 2.1, 3.7 } do
		b:Box(V(13.6, 0.22, 0.22), O * CF(0, top + 0.31, z), C(120, 110, 100), "Metal", { Name = "Rail" })
	end
	for i = -3, 3 do
		b:Box(V(0.5, 0.2, 2.6), O * CF(i * 1.95, top + 0.1, 2.9), TIMBER_DARK, "WoodPlanks", { Name = "Sleeper" })
	end
	b:Box(V(0.6, 0.9, 2.4), O * CF(-6.9, top + 0.45, 2.9), SAFETY, "Metal", { Name = "BufferStop" })
	local loads = { CAVE, GOLD }
	for i, x in { -3.4, 2.2 } do
		local cart = O * CF(x, top, 2.9)
		collide(b:Box(V(3.0, 1.5, 2.2), cart * CF(0, 1.25, 0), C(96, 70, 48), "WoodPlanks", { Name = "OreCart" }))
		b:Box(V(3.2, 0.25, 2.4), cart * CF(0, 2.05, 0), IRON, "Metal", { Name = "CartRim" })
		for _, p in { { -1.0, -1.1 }, { 1.0, -1.1 }, { -1.0, 1.1 }, { 1.0, 1.1 } } do
			b:CylZ(0.25, 0.8, cart * CF(p[1], 0.45, p[2]), C(40, 40, 44), "Metal", { Name = "CartWheel" })
		end
		for k = 0, 2 do
			b:Ellipsoid(V(0.9, 0.7, 0.9), cart * CF(-0.8 + k * 0.8, 2.25, (k % 2 == 0) and 0.3 or -0.3), k == 1 and loads[i] or C(70, 72, 80), k == 1 and "Neon" or "Slate", { Name = "CartLoad", CastShadow = false })
		end
	end
	-- Ore hopper on a timber trestle at the back.
	local hopper = O * CF(1.0, top, -3.4)
	for _, x in { -1.8, 1.8 } do
		for _, z in { -1.6, 1.6 } do
			collide(b:Box(V(0.5, 6.4, 0.5), hopper * CF(x, 3.2, z), TIMBER, "WoodPlanks", { Name = "HopperLeg" }))
		end
	end
	b:Box(V(4.6, 2.2, 4.0), hopper * CF(0, 7.5, 0), C(110, 76, 46), "WoodPlanks", { Name = "Hopper" })
	b:Wedge(V(3.6, 1.6, 3.2), hopper * CF(0, 5.6, 0) * ANG(math.pi, 0, 0), C(96, 64, 40), "WoodPlanks", { Name = "HopperChute" })
	b:Ellipsoid(V(4.2, 1.2, 3.4), hopper * CF(0, 8.6, 0), C(70, 72, 80), "Slate", { Name = "OrePile" })
	crystals(b, hopper * CF(-0.6, 8.8, 0.2), 0.6, 3)
	-- Crates and a lamp post with a sign towards the elevator.
	collide(b:Box(V(1.8, 1.8, 1.8), O * CF(-5.6, top + 0.9, -3.6) * ANG(0, rad(10), 0), C(150, 104, 60), "WoodPlanks", { Name = "Crate" }))
	b:Box(V(1.4, 1.4, 1.4), O * CF(-5.5, top + 2.5, -3.5) * ANG(0, rad(-14), 0), C(170, 122, 72), "WoodPlanks", { Name = "Crate" })
	collide(b:Box(V(1.6, 1.6, 1.6), O * CF(-3.6, top + 0.8, -4.4) * ANG(0, rad(-6), 0), C(140, 96, 56), "WoodPlanks", { Name = "Crate" }))
	local post = O * CF(6.6, top, 4.9)
	collide(b:Box(V(0.4, 7.2, 0.4), post * CF(0, 3.6, 0), STEEL_DARK, "Metal", { Name = "DepotLampPost" }))
	local lantern = b:Box(V(0.9, 1.0, 0.9), post * CF(0, 7.6, 0), WARM, "Neon", { Name = "DepotLantern", CastShadow = false })
	b:Light(lantern, C(255, 214, 150), 14, 1.0, "Point")
	b:Box(V(1.2, 0.25, 1.2), post * CF(0, 8.2, 0), STEEL_DARK, "Metal", { Name = "DepotLanternCap" })
	local sign = b:Box(V(3.8, 1.2, 0.2), post * CF(-1.6, 5.4, 0.25), C(30, 26, 26), "Metal", { Name = "DepotSign" })
	local _, bg = surfaceGui(sign, "DepotSignGui", Enum.NormalId.Back, 50, 90)
	bg.BackgroundColor3 = C(40, 34, 30)
	text(bg, "Title", "MINE ELEVATOR", 0.03, 0.1, 0.76, 0.8, C(255, 226, 170))
	text(bg, "Arrow", arrow or "►", 0.8, 0.05, 0.17, 0.9, SAFETY, Enum.Font.FredokaOne, true)
	local model = b:Finish()
	return model
end

------------------------------------------------------------------------------------------------
-- Shell (server): the rock column that hangs under the island and encloses the levels.
------------------------------------------------------------------------------------------------
local function box(b, name, x0, x1, y0, y1, z0, z1, color, mat, props)
	local p = b:Box(V(x1 - x0, y1 - y0, z1 - z0), CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat, props)
	p.Name = name
	return p
end

function S.Shell(): Model
	local b = Forge.Builder("MineShell")
	local c, w = Layout.Chamber, Layout.Wall
	local sh = Layout.Shaft
	local top, bottom = Layout.ShellTop, Layout.Bottom
	local rock, dark = Themes.ShellRock, Themes.ShellDark
	local X0, X1, Z0, Z1 = c.X0 - w, c.X1 + w, sh.Z - sh.Half - w, c.Z1 + w -- outer footprint
	local solid = { CanCollide = true, CanQuery = true, CastShadow = true }
	-- Walls (one tall box per side for all four levels).
	box(b, "WallWest", X0, c.X0, bottom, top, Z0, Z1, rock, "Rock", solid)
	box(b, "WallEast", c.X1, X1, bottom, top, Z0, Z1, rock, "Rock", solid)
	box(b, "WallFar", c.X0, c.X1, bottom, top, c.Z1, Z1, rock, "Rock", solid)
	box(b, "WallNear", c.X0, sh.X - sh.Half, bottom, top, Z0, c.Z0, rock, "Rock", solid)
	box(b, "WallNearEast", sh.X + sh.Half, c.X1, bottom, top, Z0, c.Z0, rock, "Rock", solid)
	box(b, "ShaftBack", sh.X - sh.Half, sh.X + sh.Half, bottom, top, Z0, sh.Z - sh.Half, rock, "Rock", solid)
	-- Slabs between the levels (the chamber footprint; the shaft lies outside it).
	for layer = 2, 4 do
		local upper, lower = Layout.Levels[layer], Layout.Levels[layer + 1]
		box(b, "Slab" .. layer, c.X0, c.X1, lower.Ceiling, upper.Floor, c.Z0, c.Z1, rock, "Rock", solid)
	end
	box(b, "Bottom", X0, X1, bottom, Layout.Levels[5].Floor, Z0, Z1, rock, "Rock", solid)
	-- Invisible landings in the shaft at every stop: nobody falls down the shaft (the cage and
	-- its anchored rider pass through them).
	for layer = 1, 4 do
		local y = Layout.StopY(layer) :: number
		box(b, "Landing" .. layer, sh.X - sh.Half, sh.X + sh.Half, y - 1, y, sh.Z - sh.Half, sh.Z + sh.Half, rock, "SmoothPlastic", {
			Transparency = 1,
			CanCollide = true,
			CanQuery = false,
			CastShadow = false,
		})
	end

	-- SILHOUETTE: rock cladding, a tapering bottom and stalactites so the column reads as rock
	-- hanging under the island. Cladding slabs sit outside the 4-stud walls: their tilt moves an
	-- inner face by at most ~2.3 studs, so nothing reaches a chamber or the shaft.
	local cx, cz = (X0 + X1) / 2, (Z0 + Z1) / 2
	local hx, hz = (X1 - X0) / 2, (Z1 - Z0) / 2
	local light = rock:Lerp(C(150, 160, 160), 0.18)
	local tones = { rock, dark, light, rock }
	-- Bands: from just inside the island rock down to the bottom, one per level.
	local bands = { { -26, -68 }, { -66, -102 }, { -100, -136 }, { -134, bottom - 2 } }
	for i, band in bands do
		local y0, y1 = band[1], band[2]
		local hgt, yc = y0 - y1, (y0 + y1) / 2
		local shrink = (i - 1) * 1.6 -- deeper bands step inwards: the column tapers
		local t = 5
		local tx = 9.4 - (i - 1) * 1.3 -- the sides towards the neighbouring yards close most of the gap
		local function slab(name, size, pos, rx, ry, rz, tone)
			b:Box(size, CF(pos) * ANG(math.rad(rx), math.rad(ry), math.rad(rz)), tones[tone], i % 2 == 0 and "Slate" or "Rock", { Name = name, CanCollide = true })
		end
		local k = i % 2 == 0 and 1 or -1
		slab("Cladding", V(tx, hgt, Z1 - Z0 + 4 - shrink), V(X0 - tx / 2 + 1.2, yc, cz + k * 1.2), 3 * k, 2 * k, -2.5, (i % 4) + 1)
		slab("Cladding", V(tx, hgt, Z1 - Z0 + 2 - shrink), V(X1 + tx / 2 - 1.2, yc + k, cz - k * 1.5), -2 * k, -3 * k, 2.5, ((i + 1) % 4) + 1)
		slab("Cladding", V(X1 - X0 + 3 - shrink, hgt, t), V(cx + k * 1.4, yc - k, Z1 + t / 2 - 1.2), -2.5, 2 * k, 2 * k, ((i + 2) % 4) + 1)
		slab("Cladding", V(X1 - X0 + 1 - shrink, hgt, t), V(cx - k, yc, Z0 - t / 2 + 1.2), 2.5, -2 * k, -3 * k, ((i + 3) % 4) + 1)
	end
	-- Tapering bottom: stacked, shrinking, twisted blocks.
	local taper = { { 0.84, 9, 7 }, { 0.6, 8, -11 }, { 0.36, 8, 16 } }
	local y = bottom - 1
	for i, t in taper do
		y -= t[2] / 2
		b:Box(V((X1 - X0) * t[1], t[2], (Z1 - Z0) * t[1]), CF(cx + (i - 2) * 1.5, y, cz + (i - 2) * 2) * ANG(0, math.rad(t[3]), 0), i % 2 == 1 and dark or rock, "Rock", { Name = "Taper" })
		y -= t[2] / 2 - 0.6
	end
	-- Hanging stalactites under the taper.
	local tips = { { 0, 0, 18, 9 }, { -0.42, 0.3, 11, 6 }, { 0.4, -0.35, 12, 6.5 }, { 0.3, 0.45, 8, 5 }, { -0.35, -0.42, 9, 5 } }
	for _, t in tips do
		b:Cone(CF(cx + t[1] * hx, y + 1, cz + t[2] * hz) * ANG(math.pi, 0, 0), t[3], t[4], 0.5, 2, rock, "Rock", { Name = "Stalactite" })
	end
	local model = b:Finish()
	return model
end

------------------------------------------------------------------------------------------------
-- Kennel winch (server): over a surface pit while its dog digs down in the mine.
------------------------------------------------------------------------------------------------
-- pitCF: the pit's centre on its top surface, LookVector from the kennel towards the pit.
-- Built directly in world space (pits are already placed). The sign SurfaceGui "WinchSign".
function S.Winch(pitCF: CFrame, accent: Color3): Model
	local b = Forge.Builder("MineWinch")
	local O = pitCF
	b:Disc(O * CF(0, 0.03, 0), 3.4, 0.08, C(8, 8, 10), "SmoothPlastic", { Name = "Hole" })
	b:Disc(O * CF(0, 0.06, 0), 4.0, 0.06, C(60, 44, 30), "Ground", { Name = "HoleRim" })
	for _, x in { -1, 1 } do
		b:Beam(O * V(x * 2.6, 0, -1.6), O * V(x * 2.4, 4.6, 0), 0.32, TIMBER, "WoodPlanks", { Name = "WinchLeg" })
		b:Beam(O * V(x * 2.6, 0, 1.6), O * V(x * 2.4, 4.6, 0), 0.32, TIMBER, "WoodPlanks", { Name = "WinchLeg" })
	end
	b:Cyl(5.2, 0.7, O * CF(0, 4.6, 0), TIMBER_DARK, "Wood", { Name = "WinchDrum" })
	b:Box(V(0.2, 1.0, 0.2), O * CF(2.75, 4.2, 0), IRON, "Metal", { Name = "WinchCrank" })
	b:Rod((O * V(0, 4.3, 0)), (O * V(0, 0.05, 0)), 0.12, ROPE, "Fabric", { Name = "WinchRope" })
	b:CylY(0.7, 0.8, O * CF(0, 1.6, 0), C(110, 80, 50), "WoodPlanks", { Name = "WinchBucket" })
	-- Sign on a post at the pit corner, facing the kennel side (-look).
	local post = b:Box(V(0.3, 3.4, 0.3), O * CF(-3.2, 1.7, -3.4), TIMBER_DARK, "WoodPlanks", { Name = "WinchSignPost" })
	local board = b:Box(V(3.4, 1.5, 0.2), post.CFrame * CF(0, 1.1, -0.25), C(46, 34, 26), "WoodPlanks", { Name = "WinchSign" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WinchSignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.2
	gui.MaxDistance = 60
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C(36, 26, 20)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.Color = accent
	stroke.Thickness = 5
	stroke.Parent = bg
	for i, row in { { "Caption", "DIGGING AT", 0.06, 0.36, C(255, 226, 170) }, { "Layer", "", 0.46, 0.46, accent } } do
		local t = Instance.new("TextLabel")
		t.Name = row[1]
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.92, row[4])
		t.Position = UDim2.fromScale(0.04, row[3])
		t.Font = i == 1 and Enum.Font.FredokaOne or Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = row[5]
		t.Text = row[2]
		t.Parent = bg
	end
	local model = b:Finish()
	model.PrimaryPart.CFrame = O
	model.WorldPivot = O
	return model
end

------------------------------------------------------------------------------------------------
-- Cage (client): floor centre at the origin, gates on the -X (surface) and +Z (levels) sides.
-- Row station (Layout.StationYaw ~= 0): the surface doorway faces +Z too, so -X is closed mesh.
------------------------------------------------------------------------------------------------
function S.Cage(): Model
	local b = Forge.Builder("MineCage")
	local w, hgt = 6.8, 8.2
	local hw = w / 2
	local row = (Layout.StationYaw or 0) ~= 0
	collide(b:Box(V(w, 0.3, w), CF(0, -0.15, 0), IRON, "DiamondPlate", { Name = "CageFloor" }))
	b:Box(V(w, 0.3, w), CF(0, hgt, 0), STEEL_DARK, "Metal", { Name = "CageRoof" })
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:Box(V(0.35, hgt, 0.35), CF(x * (hw - 0.17), hgt / 2, z * (hw - 0.17)), SAFETY, "Metal", { Name = "CagePost" })
		end
	end
	-- Closed sides (+X, -Z; row station also -X): steel mesh; gate sides: bars and a top rail.
	b:Box(V(0.1, hgt - 1, w - 0.4), CF(hw - 0.1, hgt / 2, 0), C(90, 96, 104), "DiamondPlate", { Name = "CageMesh", Transparency = 0.45 })
	b:Box(V(w - 0.4, hgt - 1, 0.1), CF(0, hgt / 2, -hw + 0.1), C(90, 96, 104), "DiamondPlate", { Name = "CageMesh", Transparency = 0.45 })
	if row then
		b:Box(V(0.1, hgt - 1, w - 0.4), CF(-hw + 0.1, hgt / 2, 0), C(90, 96, 104), "DiamondPlate", { Name = "CageMesh", Transparency = 0.45 })
	end
	for i = -2, 2 do
		if not row then
			b:Box(V(0.12, 3.2, 0.12), CF(-hw + 0.1, 1.6, i * 1.25), IRON, "Metal", { Name = "GateBar" })
		end
		b:Box(V(0.12, 3.2, 0.12), CF(i * 1.25, 1.6, hw - 0.1), IRON, "Metal", { Name = "GateBar" })
	end
	if not row then
		b:Box(V(0.18, 0.18, w - 0.4), CF(-hw + 0.1, 3.2, 0), SAFETY, "Metal", { Name = "GateRail" })
	end
	b:Box(V(w - 0.4, 0.18, 0.18), CF(0, 3.2, hw - 0.1), SAFETY, "Metal", { Name = "GateRail" })
	b:Box(V(0.4, 1.2, 0.4), CF(0, hgt + 0.75, 0), IRON, "Metal", { Name = "CageHook" })
	b:Rod(V(0, hgt + 1.3, 0), V(0, hgt + 40, 0), 0.18, ROPE, "Metal", { Name = "CageRope" })
	local lamp = b:Box(V(0.9, 0.25, 0.9), CF(0, hgt - 0.3, 0), C(255, 238, 200), "Neon", { Name = "CageLamp", CastShadow = false })
	b:Light(lamp, C(255, 226, 180), 18, 1.4, "Point")
	local model = b:Finish()
	return model
end
S.CageRopeLength = 38.7

------------------------------------------------------------------------------------------------
-- Shaft lining (client): from the surface down to the Void stop, in design coordinates.
------------------------------------------------------------------------------------------------
function S.Lining(): Model
	local b = Forge.Builder("MineLining")
	local s = Layout.Shaft
	local h = s.Half
	local x0, x1, z0, z1 = s.X - h, s.X + h, s.Z - h, s.Z + h
	local t = 0.25 -- board thickness
	local function walls(y0, y1, color, mat, open)
		-- open: skip the +z wall (the chamber side of a stop)
		local hgt, cy = y0 - y1, (y0 + y1) / 2
		b:Box(V(t, hgt, 2 * h), CF(x0 + t / 2, cy, s.Z), color, mat, { Name = "LiningWall" })
		b:Box(V(t, hgt, 2 * h), CF(x1 - t / 2, cy, s.Z), color, mat, { Name = "LiningWall" })
		b:Box(V(2 * h, hgt, t), CF(s.X, cy, z0 + t / 2), color, mat, { Name = "LiningWall" })
		if not open then
			b:Box(V(2 * h, hgt, t), CF(s.X, cy, z1 - t / 2), color, mat, { Name = "LiningWall" })
		end
	end
	-- Island strata.
	for _, band in Themes.IslandStrata do
		walls(band.Top, band.Bottom, band.Color, band.Material, false)
	end
	-- Timber sets every 6 studs through the island.
	for y = -1, -31, -6 do
		local beam = 0.55
		b:Box(V(2 * h, beam, beam), CF(s.X, y, z0 + 0.5), TIMBER, "WoodPlanks", { Name = "Set" })
		b:Box(V(2 * h, beam, beam), CF(s.X, y, z1 - 0.5), TIMBER, "WoodPlanks", { Name = "Set" })
		b:Box(V(beam, beam, 2 * h - 1.1), CF(x0 + 0.5, y, s.Z), TIMBER_DARK, "WoodPlanks", { Name = "Set" })
		b:Box(V(beam, beam, 2 * h - 1.1), CF(x1 - 0.5, y, s.Z), TIMBER_DARK, "WoodPlanks", { Name = "Set" })
	end
	for _, px in { x0 + 0.45, x1 - 0.45 } do
		for _, pz in { z0 + 0.45, z1 - 0.45 } do
			b:Box(V(0.5, 33, 0.5), CF(px, 1 - 16.5, pz), TIMBER_DARK, "WoodPlanks", { Name = "Post" })
		end
	end
	-- Below the island: themed strata between the stops, rock at the stops (open to the chamber).
	local prevFloor = Layout.IslandBottom
	for layer = 2, 5 do
		local level = Layout.Levels[layer]
		local theme = Themes[layer]
		if level.Ceiling < prevFloor - 0.1 then
			local strata = theme.Strata
			local span = prevFloor - level.Ceiling
			for i = 1, 3 do
				local a = prevFloor - span * (i - 1) / 3
				local c2 = prevFloor - span * i / 3
				walls(a, c2, strata[i], theme.RockMaterial, false)
			end
		end
		walls(level.Ceiling, level.Floor, theme.RockDark, theme.RockMaterial, true)
		-- Landing lintel and sill at the stop.
		b:Box(V(2 * h + 1.2, 1.0, 0.8), CF(s.X, level.Floor + 9.4, z1 + 0.2), IRON, "Metal", { Name = "StopLintel" })
		prevFloor = level.Floor
	end
	-- Guide rails for the cage on both side walls, full depth.
	local railTop, railBottom = 1, Layout.Levels[5].Floor
	for _, px in { x0 + 0.45, x1 - 0.45 } do
		b:Box(V(0.3, railTop - railBottom, 0.5), CF(px, (railTop + railBottom) / 2, s.Z), C(120, 124, 130), "Metal", { Name = "GuideRail" })
	end
	-- Lamps every ~10 studs, alternating walls, all the way down.
	local i = 0
	for y = -6, Layout.Levels[5].Floor + 6, -10 do
		i += 1
		local onEast = i % 2 == 0
		local lamp = b:Box(V(0.3, 0.6, 0.9), CF(onEast and (x1 - 0.42) or (x0 + 0.42), y, z0 + 1.6), C(255, 214, 140), "Neon", { Name = "ShaftLamp", CastShadow = false })
		lamp:SetAttribute("ShaftLampY", y)
	end
	local model = b:Finish()
	return model
end

return S
