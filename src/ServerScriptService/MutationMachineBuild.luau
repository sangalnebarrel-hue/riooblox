-- Builds the NUCLEAR MUTATION MACHINE in the Mutation Lab (docs/LAB.md): a glass tube from the hall
-- floor through the roof skylight, stacked metal rings, a heavy pedestal with a loading door, a top cap
-- with coils, antenna and warning lights, a liquid column and energy core, a lift and a placer arm, and
-- the console with the ACTIVATE button. Server-only geometry (MutationMachineWorld.server runs Install);
-- tools/qa scenes call Build directly. Moving parts carry fixed names the client cinematic animates
-- (Modules.LabPresentation): Lift.{Carriage,Mast,Platform}, IntakeDoor, Rotor1/Rotor2 (RotorHub root,
-- welded), ChamberLiquid, LiquidSurface, EnergyRail1..4, PlacerArm.{Turret,Upper,Fore,Claw},
-- ButtonGuard, ButtonDome, LeverL/LeverR, GaugeNeedle*, screens ScreenL/ScreenR/MainSign.
-- Old geometry is never deleted: hidden parts keep their original values in MutationMachine_*
-- attributes (Uninstall restores them).
local RS = game:GetService("ReplicatedStorage")
local Forge = require(RS.Forge)
local L = require(RS.MutationMachineLayout)
local P = Forge.Palette

local B = {}
B.Prefix = "MutationMachine_"
B.MaxParts = 450

local F = L.Frame
local T = L.Tube
local C3 = Color3.fromRGB
local COL = {
	Gun = C3(52, 57, 68),
	GunDark = C3(34, 37, 45),
	Steel = C3(124, 133, 146),
	Light = C3(178, 186, 198),
	Hazard = C3(255, 196, 40),
	Black = C3(24, 24, 30),
	Teal = L.Teal,
	Glass = C3(196, 236, 255),
	Red = C3(255, 52, 52),
	Orange = C3(255, 128, 36),
	Copper = C3(200, 112, 58),
	Screen = C3(14, 22, 34),
}
local SOLID = { CanCollide = true, CanQuery = true }

local function at(x: number, y: number, z: number): CFrame
	return F * CFrame.new(x, y, z)
end
local function lc(cf: CFrame): CFrame
	return F * cf
end
local function polar(a: number, r: number, y: number): Vector3
	return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end
-- Frame on a circle: X = tangent, Y = up, Z = inward (boxes of rings and radial fins).
local function tangentFrame(a: number, r: number, y: number): CFrame
	local pos = polar(a, r, y)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	return F * CFrame.fromMatrix(pos, tangent, Vector3.new(0, 1, 0))
end
local function props(base: { [string]: any }?, extra: { [string]: any }?): { [string]: any }
	local out = {}
	for k, v in pairs(base or {}) do
		out[k] = v
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end
local function named(name: string, base: { [string]: any }?): { [string]: any }
	return props(base, { Name = name })
end

-- Hollow ring of n boxes (segment k is centred at angle k * 2pi / n; k = n/2 faces the console).
local function ring(b: any, y: number, radius: number, height: number, thickness: number, n: number, color: Color3, mat: string, opts: { [string]: any }?, skip: { [number]: boolean }?): { BasePart }
	local out = {}
	local len = 2 * radius * math.tan(math.pi / n) + 0.12
	for k = 0, n - 1 do
		if not (skip and skip[k]) then
			table.insert(out, b:Box(Vector3.new(len, height, thickness), tangentFrame(k * 2 * math.pi / n, radius, y), color, mat, opts))
		end
	end
	return out
end

local function surfaceGui(part: BasePart, face: Enum.NormalId, ppsd: number?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "Display"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppsd or 36
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.MaxDistance = 220
	g.Parent = part
	return g
end
local function label(gui: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.TextWrapped = true
	t.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.TextStrokeTransparency = 0.6
	-- Self-localized on the client (Modules.LabPresentation.StartWorld), not by DOGROTS_AutoTranslateUI.
	t:SetAttribute("NoTranslate", true)
	t.Parent = gui
	return t
end

------------------------------------------------------------------------------------------------
-- The machine
------------------------------------------------------------------------------------------------
local function buildPedestal(b: any)
	b:Folder("Pedestal")
	b:CylY(1.4, 25, at(0, 0.7, 0), COL.GunDark, "Metal", named("PedestalBase", SOLID))
	b:CylY(0.3, 25.4, at(0, 1.55, 0), COL.Teal, "Neon", { Name = "PedestalGlow" })
	b:CylY(2.6, 22, at(0, 3.0, 0), COL.Gun, "Metal", named("PedestalMid", SOLID))
	b:Accent(b:CylY(0.2, 17, at(0, T.PedestalTop + 0.1, 0), COL.Teal, "Neon", { Name = "EnergyFloor" }))
	-- Heavy buttresses on the diagonals.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local pos = polar(a, 12.3, 1.9)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		b:Box(Vector3.new(3.2, 3.8, 4.4), F * CFrame.fromMatrix(pos, out:Cross(Vector3.new(0, 1, 0)), Vector3.new(0, 1, 0)), COL.GunDark, "Metal", named("Buttress", SOLID))
		b:Box(Vector3.new(3.4, 0.5, 0.5), F * CFrame.fromMatrix(polar(a, 14.35, 3.2), out:Cross(Vector3.new(0, 1, 0)), Vector3.new(0, 1, 0)), COL.Hazard, "SmoothPlastic", { Name = "ButtressStripe" })
	end
	b:Detail(function()
		for i = 0, 15 do
			local a = (i + 0.5) / 16 * 2 * math.pi
			if math.abs(math.cos(a)) < 0.97 or math.cos(a) > 0 then -- leave the rail entry clear
				b:CylY(0.35, 0.55, F * CFrame.new(polar(a, 11.6, 1.6)), COL.Light, "Metal", { Name = "Bolt" })
			end
		end
	end)
	b:Into(b.Model)
end

local function buildIntake(b: any)
	b:Folder("Intake")
	local n = 10
	local h = T.IntakeTop - T.PedestalTop
	ring(b, T.PedestalTop + h / 2, L.Door.Radius, h, 1.2, n, COL.Gun, "Metal", named("IntakeSegment", SOLID), { [n / 2] = true })
	-- Door segment (faces the console) and its lintel.
	local doorH = L.Door.Top - L.Door.Bottom
	local door = b:Box(Vector3.new(L.Door.Width - 0.2, doorH, 0.9), tangentFrame(math.pi, L.Door.Radius, L.Door.Bottom + doorH / 2), COL.Steel, "DiamondPlate", named("IntakeDoor", SOLID))
	door:SetAttribute("Drop", L.Door.Drop)
	b:Box(Vector3.new(L.Door.Width + 0.1, T.IntakeTop - L.Door.Top, 1.3), tangentFrame(math.pi, L.Door.Radius, (L.Door.Top + T.IntakeTop) / 2), COL.GunDark, "Metal", { Name = "DoorLintel" })
	for _, s in { -1, 1 } do
		b:Box(Vector3.new(0.35, doorH, 1.35), tangentFrame(math.pi + s * 0.335, L.Door.Radius, L.Door.Bottom + doorH / 2), COL.Hazard, "SmoothPlastic", { Name = "DoorJamb" })
	end
	b:Accent(b:Box(Vector3.new(L.Door.Width, 0.25, 1.32), tangentFrame(math.pi, L.Door.Radius, (L.Door.Top + T.IntakeTop) / 2), COL.Orange, "Neon", { Name = "DoorLamp" }))
	-- Heavy collar band where the glass starts, bolted down.
	ring(b, T.IntakeTop + 0.35, 9.25, 0.9, 1.3, n, COL.GunDark, "Metal", { Name = "IntakeCollar" })
	b:Detail(function()
		for k = 0, n - 1 do
			b:CylY(0.25, 0.45, F * CFrame.new(polar((k + 0.5) / n * 2 * math.pi, 9.55, T.IntakeTop + 0.9)), COL.Light, "Metal", { Name = "CollarBolt" })
		end
	end)
	b:Into(b.Model)
end

local function buildChamber(b: any)
	b:Folder("Chamber")
	local glassH = T.GlassTop - T.IntakeTop
	b:CylY(glassH, T.Radius * 2, at(0, T.IntakeTop + glassH / 2, 0), COL.Glass, "Glass", named("ChamberGlass", props(SOLID, { Transparency = 0.62, CastShadow = false })))
	-- Vertical energy rails inside the glass (arcs jump from them in the cinematic).
	for i = 1, T.Rails do
		local a = math.rad(45 + (i - 1) * 90)
		local p = b:Box(Vector3.new(0.38, glassH - 0.4, 0.38), F * CFrame.new(polar(a, T.RailRadius, T.IntakeTop + glassH / 2)), COL.Teal, "Neon", { Name = "EnergyRail" .. i, Transparency = 0.15, CastShadow = false })
		b:Accent(p)
	end
	-- Energy core column on the axis (hidden while the cinematic lifts the dog into the chamber).
	b:Accent(b:CylY(T.InjectorTip - T.FloorTop, 0.9, at(0, (T.InjectorTip + T.FloorTop) / 2, 0), C3(205, 255, 240), "Neon", { Name = "CoreBeam", Transparency = 0.3, CastShadow = false }))
	-- Liquid column (drained = hidden); the cinematic fills it.
	b:CylY(0.2, T.LiquidRadius * 2, at(0, T.LiquidIdle, 0), L.Liquid, "Neon", { Name = "ChamberLiquid", Transparency = 1, CastShadow = false })
	b:CylY(0.12, T.LiquidRadius * 2 - 0.2, at(0, T.LiquidIdle + 0.1, 0), L.Teal, "Neon", { Name = "LiquidSurface", Transparency = 1, CastShadow = false })
	-- Ceiling: glowing membrane, solid upper collar, injector cone pointing down at the dog.
	b:Accent(b:CylY(0.2, T.Radius * 2 - 0.1, at(0, T.GlassTop - 0.15, 0), COL.Teal, "Neon", { Name = "Membrane", Transparency = 0.35, CastShadow = false }))
	b:CylY(1.6, 19.4, at(0, T.GlassTop + 0.8, 0), COL.GunDark, "Metal", named("UpperCollar", SOLID))
	b:Cone(lc(CFrame.new(0, T.GlassTop - 0.2, 0) * CFrame.Angles(math.pi, 0, 0)), T.GlassTop - 0.2 - T.InjectorTip - 0.6, 4.4, 1.0, 3, COL.Steel, "Metal", { Name = "Injector" })
	b:Accent(b:Ball(1.3, at(0, T.InjectorTip + 0.3, 0), COL.Teal, "Neon", { Name = "InjectorTip" }))
	b:Detail(function()
		b:CylY(0.3, 5.2, at(0, T.GlassTop - 1.6, 0), COL.Copper, "Metal", { Name = "InjectorCoil" })
		b:CylY(0.3, 4.2, at(0, T.GlassTop - 3.0, 0), COL.Copper, "Metal", { Name = "InjectorCoil" })
	end)
	-- Light of the chamber (one of the machine's four lights).
	local holder = b:Box(Vector3.new(0.2, 0.2, 0.2), at(0, 23.6, 0), COL.Teal, "SmoothPlastic", { Name = "ChamberLightPart", Transparency = 1, CastShadow = false })
	local light = b:Light(holder, COL.Teal, 26, 1.4, "Point")
	light.Name = "ChamberLight"
	-- Copper coolant pipes on the far side of the tube (they frame it from the console).
	for _, deg in { -58, 58 } do
		local a = math.rad(deg)
		local foot = L.World(polar(a, 12.3, 1.4))
		local top = L.World(polar(a, 12.3, T.GlassTop + 0.8))
		b:Rod(foot, top, 1.2, COL.Copper, "Metal", { Name = "CoolantPipe" })
		b:Rod(top, L.World(polar(a, 9.4, T.GlassTop + 0.8)), 1.2, COL.Copper, "Metal", { Name = "CoolantPipe" })
		b:Ball(1.7, CFrame.new(top), COL.GunDark, "Metal", { Name = "PipeElbow" })
		for _, y in { 8, 18, 27 } do
			b:CylY(0.5, 1.7, F * CFrame.new(polar(a, 12.3, y)), COL.GunDark, "Metal", { Name = "PipeClamp" })
		end
	end
	-- Structural ribs outside the glass (diagonal, never in front of the console view).
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		b:Box(Vector3.new(0.6, glassH + 0.6, 0.34), F * CFrame.fromMatrix(polar(a, 8.72, T.IntakeTop + glassH / 2), Vector3.new(-math.sin(a), 0, math.cos(a)), Vector3.new(0, 1, 0)), COL.Gun, "Metal", { Name = "ChamberRib" })
	end
	b:Into(b.Model)
end

-- Rotor: a hexagonal ring with three neon fins (120-degree symmetry: the idle spin loops seamlessly).
-- RotorHub (anchored, on the tube axis) is the root; the other parts are welded to it.
local function buildRotor(b: any, name: string, y: number)
	local model = b:Folder(name)
	local hub = b:Box(Vector3.new(0.4, 0.4, 0.4), at(0, y, 0), COL.Gun, "SmoothPlastic", { Name = "RotorHub", Transparency = 1, CastShadow = false })
	model.PrimaryPart = hub
	local parts = ring(b, y, 9.4, 0.8, 0.6, 6, COL.Steel, "Metal", { Name = "RotorRing" })
	for k = 0, 2 do
		local a = k * 2 * math.pi / 3
		table.insert(parts, b:Box(Vector3.new(0.6, 1.8, 1.6), tangentFrame(a, 10.4, y), COL.GunDark, "Metal", { Name = "RotorFin" }))
		table.insert(parts, b:Accent(b:Box(Vector3.new(0.66, 1.1, 0.3), tangentFrame(a, 11.25, y), COL.Teal, "Neon", { Name = "RotorLamp" })))
	end
	for _, p in parts do
		p.Anchored = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = hub
		w.Part1 = p
		w.Parent = p
	end
	b:Into(b.Model)
end

local function buildRoofAndColumn(b: any)
	b:Folder("Column")
	local neckBottom = T.GlassTop + 1.6
	b:CylY(T.UpperBottom - 1.4 - neckBottom, 17.6, at(0, (neckBottom + T.UpperBottom - 1.4) / 2, 0), COL.Gun, "Metal", { Name = "Neck" })
	-- Roof deck over the cut skylight (world X 122.5..142, Z 466.5..487.5) and the collar where the tube exits.
	b:Box(Vector3.new(19.5, 0.9, 21), at(-0.75, 35.85, 0), COL.GunDark, "DiamondPlate", named("RoofDeck", SOLID))
	b:CylY(1.4, 20.2, at(0, T.UpperBottom - 0.7, 0), COL.Gun, "Metal", named("RoofCollar", SOLID))
	b:Accent(b:CylY(0.25, 20.6, at(0, T.UpperBottom - 1.3, 0), COL.Teal, "Neon", { Name = "RoofGlow" }))
	-- Upper column: glass, glowing liquid and the core (the district landmark).
	local h = T.UpperTop - T.UpperBottom
	b:CylY(h, T.Radius * 2, at(0, T.UpperBottom + h / 2, 0), COL.Glass, "Glass", { Name = "UpperGlass", Transparency = 0.55, CastShadow = false })
	b:CylY(h - 1.6, 15.8, at(0, T.UpperBottom + h / 2 - 0.6, 0), L.Liquid, "Neon", { Name = "UpperLiquid", Transparency = 0.42, CastShadow = false })
	b:Accent(b:CylY(T.UpperTop + 2 - (T.UpperBottom - 1.6), 2.2, at(0, (T.UpperTop + 2 + T.UpperBottom - 1.6) / 2, 0), C3(205, 255, 240), "Neon", { Name = "Core", CastShadow = false }))
	local holder = b:Box(Vector3.new(0.2, 0.2, 0.2), at(0, 62, 0), COL.Teal, "SmoothPlastic", { Name = "CoreLightPart", Transparency = 1, CastShadow = false })
	local light = b:Light(holder, COL.Teal, 40, 2.2, "Point")
	light.Name = "CoreLight"
	for _, y in { 49.2, 61.2, 73.2 } do
		b:CylY(1.3, 19.4, at(0, y, 0), COL.Gun, "Metal", { Name = "UpperBand" })
		b:Accent(b:CylY(0.25, 19.8, at(0, y, 0), COL.Teal, "Neon", { Name = "UpperBandGlow" }))
	end
	for i = 0, 3 do
		local a = math.rad(i * 90)
		b:Box(Vector3.new(0.8, h, 0.8), F * CFrame.new(polar(a, 9.0, T.UpperBottom + h / 2)), COL.Steel, "Metal", { Name = "UpperRib" })
	end
	-- Struts from the deck corners to the first band.
	for _, corner in { Vector3.new(-10, 36.3, -10), Vector3.new(-10, 36.3, 10), Vector3.new(8.5, 36.3, -10), Vector3.new(8.5, 36.3, 10) } do
		local dir = Vector3.new(corner.X, 0, corner.Z).Unit
		local top = Vector3.new(dir.X * 9.6, 49.2, dir.Z * 9.6)
		b:Rod(L.World(corner), L.World(top), 0.9, COL.Steel, "Metal", { Name = "Strut" })
		b:Box(Vector3.new(1.8, 0.4, 1.8), F * CFrame.new(corner + Vector3.new(0, 0.2, 0)), COL.GunDark, "Metal", { Name = "StrutFoot" })
	end
	b:Into(b.Model)
end

local function buildCap(b: any)
	b:Folder("Cap")
	local top = T.UpperTop
	b:CylY(2.6, 20, at(0, top + 1.3, 0), COL.GunDark, "Metal", { Name = "CapBase" })
	b:Accent(b:CylY(0.3, 20.4, at(0, top + 0.15, 0), COL.Teal, "Neon", { Name = "CapGlow" }))
	b:Ellipsoid(Vector3.new(14.5, 8, 14.5), at(0, top + 3.8, 0), COL.Steel, "Metal", { Name = "CapDome" })
	-- Four tesla coils on the rim.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local base = polar(a, 8.2, top + 2.6)
		b:CylY(4.2, 1.1, F * CFrame.new(base + Vector3.new(0, 2.1, 0)), COL.Copper, "Metal", { Name = "Coil" })
		b:Ellipsoid(Vector3.new(2.8, 0.8, 2.8), F * CFrame.new(base + Vector3.new(0, 4.4, 0)), COL.Light, "Metal", { Name = "CoilTorus" })
		b:Accent(b:Ball(0.9, F * CFrame.new(base + Vector3.new(0, 5.0, 0)), COL.Teal, "Neon", { Name = "CoilSpark" }))
		b:Detail(function()
			b:CylY(0.25, 1.7, F * CFrame.new(base + Vector3.new(0, 1.0, 0)), COL.GunDark, "Metal", { Name = "CoilWinding" })
			b:CylY(0.25, 1.7, F * CFrame.new(base + Vector3.new(0, 2.6, 0)), COL.GunDark, "Metal", { Name = "CoilWinding" })
		end)
	end
	-- Warning lights around the cap and the antenna with the red beacon (a machine light).
	for i = 0, 3 do
		local a = math.rad(i * 90)
		b:Accent(b:Box(Vector3.new(1.4, 0.9, 0.45), tangentFrame(a, 10.05, top + 1.3), COL.Red, "Neon", { Name = "WarningLight" .. (i + 1) }))
	end
	b:CylY(T.Top - 0.6 - (top + 7.4), 0.6, at(0, (T.Top - 0.6 + top + 7.4) / 2, 0), COL.Light, "Metal", { Name = "Antenna" })
	for _, y in { top + 12.8, top + 15.4 } do
		b:Box(Vector3.new(3.2, 0.25, 0.25), at(0, y, 0), COL.Light, "Metal", { Name = "AntennaBar" })
		b:Box(Vector3.new(0.25, 0.25, 3.2), at(0, y, 0), COL.Light, "Metal", { Name = "AntennaBar" })
	end
	local beacon = b:Ball(1.6, at(0, T.Top, 0), COL.Red, "Neon", { Name = "Beacon", CastShadow = false })
	b:Light(beacon, COL.Red, 32, 3, "Point").Name = "BeaconLight"
	b:Into(b.Model)
end

local function buildLift(b: any)
	local Lf = L.Lift
	-- Rail bed from the console bay into the tube.
	b:Folder("Rails")
	local bedFrom, bedTo = -21.5, -10.5
	b:Box(Vector3.new(bedTo - bedFrom, Lf.RailTop - 0.5, 5.2), at((bedFrom + bedTo) / 2, (Lf.RailTop - 0.5) / 2, 0), COL.GunDark, "Metal", named("RailBed", SOLID))
	for _, s in { -1, 1 } do
		b:Accent(b:Box(Vector3.new(bedTo - bedFrom - 0.4, 0.25, 0.1), at((bedFrom + bedTo) / 2, 2.3, s * 2.62), COL.Teal, "Neon", { Name = "RailBedGlow" }))
		b:Box(Vector3.new(-bedFrom + 0.4, 0.5, 0.5), at(bedFrom / 2 + 0.2, Lf.RailTop - 0.25, s * 1.8), COL.Light, "Metal", { Name = "Rail" })
	end
	b:Into(b.Model)
	local lift = b:Folder("Lift")
	local carriage = b:Folder("Carriage")
	carriage.Parent = lift
	local cy = Lf.RailTop + Lf.CarriageHeight / 2
	b:Box(Vector3.new(4.6, Lf.CarriageHeight, 4.4), at(Lf.RestX, cy, 0), COL.Hazard, "SmoothPlastic", { Name = "CarriageBody" })
	b:Box(Vector3.new(4.7, 0.2, 4.5), at(Lf.RestX, cy - 0.2, 0), COL.Black, "SmoothPlastic", { Name = "CarriageStripe" })
	carriage.WorldPivot = at(Lf.RestX, Lf.RailTop, 0)
	b:Into(lift)
	local mast = b:CylY(0.2, 1.3, at(Lf.RestX, Lf.CarriageTop + 0.1, 0), COL.Light, "Metal", { Name = "Mast" })
	mast.Transparency = 1
	local platform = b:Folder("Platform")
	platform.Parent = lift
	local deckY = Lf.RestDeck + Lf.DeckThickness / 2
	b:CylY(Lf.DeckThickness, 5.4, at(Lf.RestX, deckY, 0), COL.Gun, "DiamondPlate", { Name = "Deck" })
	b:Accent(b:CylY(0.22, 5.8, at(Lf.RestX, Lf.RestDeck + 0.12, 0), COL.Teal, "Neon", { Name = "DeckGlow" }))
	for k = 0, 2 do
		local a = math.rad(90 + k * 120)
		b:Box(Vector3.new(0.35, 0.8, 0.35), F * CFrame.new(Vector3.new(Lf.RestX, Lf.RestDeck + Lf.DeckThickness + 0.4, 0) + polar(a, 2.75, 0)), COL.Light, "Metal", { Name = "DeckPost" })
	end
	platform.WorldPivot = at(Lf.RestX, Lf.RestDeck, 0)
	lift.WorldPivot = at(Lf.RestX, Lf.RailTop, 0)
	b:Into(b.Model)
end

local function buildArm(b: any)
	local A = L.Arm
	local pose = L.ArmPose(A.Rest)
	local arm = b:Folder("PlacerArm")
	b:CylY(0.8, 2.6, at(A.Base.X, A.Base.Y + 0.4, A.Base.Z), COL.GunDark, "Metal", named("ArmBase", SOLID))
	local function group(name: string, frame: CFrame, fn: (cf: CFrame) -> ())
		local g = b:Folder(name)
		g.Parent = arm
		fn(lc(frame))
		g.WorldPivot = lc(frame)
		b:Into(arm)
	end
	group("Turret", pose.Turret, function(cf)
		b:CylY(1.4, 2.1, cf * CFrame.new(0, 1.5, 0), COL.Hazard, "SmoothPlastic", { Name = "TurretBody" })
		b:Ball(1.3, cf * CFrame.new(0, A.ShoulderHeight, 0), COL.GunDark, "Metal", { Name = "Shoulder" })
	end)
	group("Upper", pose.Upper, function(cf)
		b:Box(Vector3.new(0.9, 0.9, A.Upper), cf * CFrame.new(0, 0, -A.Upper / 2), COL.Hazard, "SmoothPlastic", { Name = "UpperLink" })
		b:Box(Vector3.new(1.0, 0.25, A.Upper * 0.7), cf * CFrame.new(0, 0.5, -A.Upper / 2), COL.Black, "SmoothPlastic", { Name = "UpperStripe" })
		b:Ball(1.05, cf * CFrame.new(0, 0, -A.Upper), COL.GunDark, "Metal", { Name = "Elbow" })
	end)
	group("Fore", pose.Fore, function(cf)
		b:Box(Vector3.new(0.7, 0.7, A.Fore), cf * CFrame.new(0, 0, -A.Fore / 2), COL.Steel, "Metal", { Name = "ForeLink" })
		b:Detail(function()
			b:Box(Vector3.new(0.3, 0.3, A.Fore * 0.8), cf * CFrame.new(0.45, 0.2, -A.Fore / 2), COL.Black, "SmoothPlastic", { Name = "Hose" })
		end)
	end)
	group("Claw", pose.Claw, function(cf)
		b:CylY(0.7, 1.3, cf * CFrame.new(0, -0.35, 0), COL.GunDark, "Metal", { Name = "Wrist" })
		b:Accent(b:CylY(0.15, 1.0, cf * CFrame.new(0, -0.78, 0), COL.Teal, "Neon", { Name = "ClawLamp" }))
		for _, s in { -1, 1 } do
			b:Box(Vector3.new(0.25, 1.4, 0.5), cf * CFrame.new(0, -1.3, s * 0.55) * CFrame.Angles(s * math.rad(12), 0, 0), COL.Light, "Metal", { Name = "Finger" })
		end
	end)
	b:Into(b.Model)
end

local function gauge(b: any, z: number, y: number, index: number)
	local x = L.Console.DeskFront - 0.08
	b:Cyl(0.16, 1.75, at(x, y, z), COL.GunDark, "Metal", { Name = "GaugeRim" })
	b:Cyl(0.18, 1.45, at(x - 0.03, y, z), C3(232, 240, 228), "SmoothPlastic", { Name = "GaugeFace" })
	local pivot = at(x - 0.14, y, z)
	local needle = b:Box(Vector3.new(0.05, 0.6, 0.09), pivot * CFrame.Angles(math.rad(-50 + index * 17), 0, 0) * CFrame.new(0, 0.25, 0), COL.Red, "Neon", { Name = "GaugeNeedle" .. index })
	needle:SetAttribute("Pivot", pivot)
end

local function screen(b: any, name: string, cf: CFrame, w: number, h: number): BasePart
	local s = b:Box(Vector3.new(0.4, h, w), cf, COL.Screen, "SmoothPlastic", { Name = name })
	b:Box(Vector3.new(0.6, h + 0.5, w + 0.5), cf * CFrame.new(0.25, 0, 0), COL.GunDark, "Metal", { Name = name .. "Bezel" })
	b:Box(Vector3.new(1.1, 0.25, w + 0.7), cf * CFrame.new(-0.2, h / 2 + 0.35, 0), COL.GunDark, "Metal", { Name = name .. "Hood" })
	return s
end

local function buildConsole(b: any)
	local K = L.Console
	local console = b:Folder("Console")
	-- Deck and the operator dais.
	b:Box(Vector3.new(16, 0.5, 20), at(-19, 0.25, 0), COL.GunDark, "DiamondPlate", named("ConsoleDeck", SOLID))
	b:Box(Vector3.new(4, 0.35, 10), at(-29, 0.175, 0), COL.Gun, "DiamondPlate", named("OperatorDais", SOLID))
	b:Detail(function()
		for i = 0, 4 do
			b:Box(Vector3.new(0.9, 0.06, 2), at(-30.6 + 0, 0.38, -4 + i * 2), i % 2 == 0 and COL.Hazard or COL.Black, "SmoothPlastic", { Name = "DaisHazard" })
		end
	end)
	-- Command desk: body, sloped top (rises toward the tube), back.
	b:Box(Vector3.new(K.SlopeTo - K.SlopeFrom, K.SlopeBottom - 0.5, 12), at((K.SlopeFrom + K.SlopeTo) / 2, (K.SlopeBottom + 0.5) / 2, 0), COL.Gun, "Metal", named("DeskBody", SOLID))
	b:Wedge(Vector3.new(12, K.SlopeTop - K.SlopeBottom, K.SlopeTo - K.SlopeFrom), at((K.SlopeFrom + K.SlopeTo) / 2, (K.SlopeBottom + K.SlopeTop) / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), COL.GunDark, "Metal", named("DeskSlope", SOLID))
	b:Box(Vector3.new(1.5, K.SlopeTop - 0.5, 12), at(K.SlopeTo + 0.75, (K.SlopeTop + 0.5) / 2, 0), COL.Gun, "Metal", named("DeskBack", SOLID))
	b:Accent(b:Box(Vector3.new(0.12, 0.28, 11.4), at(K.DeskFront - 0.06, K.SlopeBottom - 0.45, 0), COL.Teal, "Neon", { Name = "DeskGlow" }))
	local front = b:Box(Vector3.new(0.1, 1.4, 7), at(K.DeskFront - 0.05, 1.9, 0), COL.Screen, "SmoothPlastic", { Name = "DeskPlate" })
	local g = surfaceGui(front, Enum.NormalId.Left, 40)
	label(g, "Title", "☢ NUCLEAR MUTATION MACHINE ☢", UDim2.fromScale(0.03, 0.12), UDim2.fromScale(0.94, 0.76), COL.Hazard)
	-- ACTIVATE: hazard rings, base, red dome, hinged glass guard.
	local S = lc(K.Slope)
	b:Disc(S * CFrame.new(0, 0.05, 0), 3.5, 0.1, COL.Hazard, "SmoothPlastic", { Name = "HazardRing" })
	b:Disc(S * CFrame.new(0, 0.12, 0), 2.9, 0.12, COL.Black, "SmoothPlastic", { Name = "HazardInner" })
	b:Disc(S * CFrame.new(0, 0.3, 0), 2.2, 0.3, COL.GunDark, "Metal", { Name = "ButtonBase" })
	local dome = b:Ellipsoid(Vector3.new(1.8, 0.95, 1.8), S * CFrame.new(0, 0.5, 0), COL.Red, "Neon", { Name = "ButtonDome" })
	dome:SetAttribute("Press", 0.28)
	local guard = b:Folder("ButtonGuard")
	local hinge = S * CFrame.new(1.4, 0.18, 0)
	b:Box(Vector3.new(2.7, 1.25, 2.7), S * CFrame.new(0.05, 0.82, 0), C3(190, 225, 255), "Glass", { Name = "GuardCover", Transparency = 0.55, CastShadow = false })
	b:Cyl(2.9, 0.26, hinge * CFrame.Angles(0, math.pi / 2, 0), COL.Light, "Metal", { Name = "GuardHinge" })
	guard.WorldPivot = hinge
	b:Into(console)
	-- Levers either side of the button (pivot at the base, pulled toward the operator).
	for _, s in { { "LeverL", -1 }, { "LeverR", 1 } } do
		local lever = b:Folder(s[1])
		local base = S * CFrame.new(0.3, 0.2, s[2] * K.LeverZ)
		b:Box(Vector3.new(0.8, 0.3, 0.9), base, COL.GunDark, "Metal", { Name = "LeverBase" })
		local tip = base * CFrame.new(-0.4, 1.6, 0)
		b:Rod(base.Position, tip.Position, 0.2, COL.Light, "Metal", { Name = "LeverRod" })
		b:Ball(0.55, tip, s[2] < 0 and COL.Hazard or COL.Red, "SmoothPlastic", { Name = "LeverKnob" })
		lever.WorldPivot = base
		b:Into(console)
	end
	b:Detail(function()
		for i, spec in { { -1.4, -1.8, COL.Teal }, { -1.4, 1.8, COL.Hazard }, { -0.2, -5.0, P.Green }, { -0.2, 5.0, COL.Orange }, { 1.3, -5.0, COL.Teal }, { 1.3, 5.0, COL.Teal } } do
			b:Accent(b:Box(Vector3.new(0.6, 0.16, 0.6), S * CFrame.new(spec[1], 0.08, spec[2]), spec[3], "Neon", { Name = "DeskKey" .. i }))
		end
	end)
	-- Side wings with tall angled screens and gauges.
	for _, side in { -1, 1 } do
		local z = side * 8.2
		b:Box(Vector3.new(12, 2.7, 3.6), at(-21, 1.85, z), COL.Gun, "Metal", named("WingDesk", SOLID))
		b:Wedge(Vector3.new(3.6, 0.9, 12), at(-21, 3.65, z) * CFrame.Angles(0, math.pi / 2, 0), COL.GunDark, "Metal", { Name = "WingSlope" })
		b:Box(Vector3.new(1.0, 4.4, 1.0), at(-16.0, 5.0, side * 8.4), COL.GunDark, "Metal", { Name = "ScreenPost" })
		local yaw = side < 0 and math.rad(33.7) or -math.rad(33.7)
		local s = screen(b, side < 0 and "ScreenL" or "ScreenR", at(-16.4, 9.4, side * 8.4) * CFrame.Angles(0, yaw, 0), 7.6, 4.8)
		local gui = surfaceGui(s, Enum.NormalId.Left, 34)
		if side < 0 then
			label(gui, "Title", "REACTOR", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.24), COL.Hazard)
			label(gui, "Line1", "CORE STABLE", UDim2.fromScale(0.05, 0.36), UDim2.fromScale(0.9, 0.2), COL.Teal)
			label(gui, "Line2", "ENERGY 100%", UDim2.fromScale(0.05, 0.6), UDim2.fromScale(0.9, 0.2), COL.Teal)
			label(gui, "Line3", "PRESS ACTIVATE", UDim2.fromScale(0.05, 0.82), UDim2.fromScale(0.9, 0.14), C3(255, 255, 255))
		else
			label(gui, "Title", "BASE ODDS", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.18), COL.Hazard)
			local rows = require(RS.DogEconomy.Config).Variants
			local total = 0
			for _, v in rows do
				total += v.Weight
			end
			for i, v in rows do
				local y = 0.24 + (i - 1) * 0.125
				local color = (L.WorldColors :: any)[v.Name] or COL.Teal
				label(gui, "Name" .. i, v.Name, UDim2.fromScale(0.08, y), UDim2.fromScale(0.5, 0.11), color, Enum.TextXAlignment.Left)
				local pct = v.Weight / total * 100
				label(gui, "Odds" .. i, (pct >= 1 and string.format("%.0f%%", pct) or string.format("%.1f%%", pct)), UDim2.fromScale(0.6, y), UDim2.fromScale(0.32, 0.11), color, Enum.TextXAlignment.Right)
			end
		end
		gauge(b, side * 7.3, 2.15, side < 0 and 1 or 3)
		gauge(b, side * 9.1, 2.15, side < 0 and 2 or 4)
	end
	-- Hanging title sign over the console (faces the entrance).
	local sign = screen(b, "MainSign", at(-11.6, 28.4, 0), 12, 4.2)
	local sg = surfaceGui(sign, Enum.NormalId.Left, 30)
	label(sg, "Title", "☢ MUTATION MACHINE ☢", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.5), COL.Hazard)
	label(sg, "Status", "READY · PRESS ACTIVATE", UDim2.fromScale(0.06, 0.62), UDim2.fromScale(0.88, 0.3), COL.Teal)
	for _, cable in { { -5.2, 32.0 }, { 5.2, 30.3 } } do
		b:Rod(L.World(Vector3.new(-11.3, 30.6, cable[1])), L.World(Vector3.new(-11.3, cable[2], cable[1])), 0.22, COL.Black, "Metal", { Name = "SignCable" })
	end
	local spot = b:Box(Vector3.new(1.2, 0.3, 1.2), at(-12.4, 26.15, 0), COL.GunDark, "Metal", { Name = "ConsoleLamp" })
	local console = b:Light(spot, C3(200, 230, 255), 24, 1.6, "Spot") :: SpotLight
	console.Name = "ConsoleLight"
	console.Face = Enum.NormalId.Bottom
	console.Angle = 80
	-- Floor cables from the console wings to the pedestal.
	for _, side in { -1, 1 } do
		local c1 = L.World(Vector3.new(-14, 0.3, side * 9.6))
		local c2 = L.World(Vector3.new(-11.5, 0.3, side * 11.2))
		local c3 = L.World(polar(side < 0 and math.rad(-128) or math.rad(128), 12.2, 0.3))
		b:Rod(c1, c2, 0.6, COL.Black, "SmoothPlastic", { Name = "FloorCable" })
		b:Rod(c2, c3, 0.6, COL.Black, "SmoothPlastic", { Name = "FloorCable" })
	end
	b:Into(b.Model)
end

-- Builds the machine model (world coordinates of Layout.Frame). parent: optional.
function B.Build(parent: Instance?): Model
	local b = Forge.Builder(L.Name, { Lod = 0 })
	local model = b.Model
	local root = model.PrimaryPart :: BasePart
	root.CFrame = F
	buildPedestal(b)
	buildIntake(b)
	buildChamber(b)
	for _, r in T.Rotors do
		buildRotor(b, r.Name, r.Y)
	end
	buildRoofAndColumn(b)
	buildCap(b)
	buildLift(b)
	buildArm(b)
	buildConsole(b)
	b:Finish()
	model.WorldPivot = F
	model:SetAttribute("LayoutVersion", L.Version)
	model:SetAttribute("Parts", b.Parts)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	if parent then
		model.Parent = parent
	end
	return model
end

------------------------------------------------------------------------------------------------
-- Reversible edits of the base place
------------------------------------------------------------------------------------------------
local HIDE = { "Transparency", "CanCollide", "CanTouch", "CanQuery", "CastShadow" }
local function remember(o: Instance, key: string)
	local a = B.Prefix .. key
	if o:GetAttribute(a) == nil then
		o:SetAttribute(a, (o :: any)[key])
	end
	o:SetAttribute(B.Prefix .. "Edited", true)
end
function B.Hide(o: Instance)
	if o:IsA("BasePart") then
		for _, k in HIDE do
			remember(o, k)
		end
		o.Transparency = 1
		o.CanCollide = false
		o.CanTouch = false
		o.CanQuery = false
		o.CastShadow = false
	elseif o:IsA("Decal") or o:IsA("Texture") then
		remember(o, "Transparency")
		;(o :: any).Transparency = 1
	elseif o:IsA("SurfaceGui") or o:IsA("BillboardGui") or o:IsA("Light") or o:IsA("ParticleEmitter") or o:IsA("Beam") or o:IsA("Trail") or o:IsA("ProximityPrompt") then
		remember(o, "Enabled")
		;(o :: any).Enabled = false
	end
end
function B.HideTree(o: Instance)
	B.Hide(o)
	for _, d in o:GetDescendants() do
		B.Hide(d)
	end
end
-- Restores everything B.Hide / B.Move changed under root.
function B.Restore(root: Instance): number
	local n = 0
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, o in list do
		if o:GetAttribute(B.Prefix .. "Edited") then
			for _, k in { "Transparency", "CanCollide", "CanTouch", "CanQuery", "CastShadow", "Enabled", "CFrame" } do
				local a = B.Prefix .. k
				local v = o:GetAttribute(a)
				if v ~= nil then
					(o :: any)[k] = v
					o:SetAttribute(a, nil)
				end
			end
			o:SetAttribute(B.Prefix .. "Edited", nil)
			n += 1
		end
	end
	return n
end
local function move(o: BasePart, cf: CFrame)
	remember(o, "CFrame")
	o.CFrame = cf
end

local function find(parent: Instance?, name: string, test: (p: BasePart) -> boolean): BasePart?
	if not parent then
		return nil
	end
	for _, c in parent:GetChildren() do
		if c.Name == name and c:IsA("BasePart") and test(c) then
			return c
		end
	end
	return nil
end

-- Cuts the roof where the tube passes: the skylight, the lantern beam on the axis and the crossbar the
-- tube crosses are hidden and replaced by trimmed copies (parented to the machine).
local function cutRoof(lab: Instance, machine: Model)
	local roof = lab:FindFirstChild("TechnicalRoof")
	local folder = Instance.new("Folder")
	folder.Name = "RoofCut"
	folder.Parent = machine
	local function piece(src: BasePart, name: string, center: Vector3, size: Vector3)
		local p = src:Clone()
		for k in p:GetAttributes() do
			p:SetAttribute(k, nil)
		end
		for _, d in p:GetChildren() do
			d:Destroy()
		end
		p.Name = name
		p.CFrame = CFrame.new(center)
		p.Size = size
		p.Parent = folder
	end
	local skylight = find(roof, "CentralSkylight", function()
		return true
	end)
	if skylight then
		piece(skylight, "SkylightWest", Vector3.new(109.25, 37.9, 477), Vector3.new(26.5, 0.2, 32))
		piece(skylight, "SkylightNorth", Vector3.new(132.25, 37.9, 463.75), Vector3.new(19.5, 0.2, 5.5))
		piece(skylight, "SkylightSouth", Vector3.new(132.25, 37.9, 490.25), Vector3.new(19.5, 0.2, 5.5))
		B.Hide(skylight)
	end
	local beam = find(roof, "LanternBeam", function(p)
		return math.abs(p.CFrame.Position.Z - 477) < 1
	end)
	if beam then
		piece(beam, "LanternBeamWest", Vector3.new(109, 38.2, 477), Vector3.new(27, 0.7, 0.6))
		B.Hide(beam)
	end
	local bar = find(roof, "LanternCrossbar", function(p)
		return math.abs(p.CFrame.Position.X - 127) < 1
	end)
	if bar then
		piece(bar, "LanternCrossbarNorth", Vector3.new(127, 38.2, 463.5), Vector3.new(0.5, 0.7, 6))
		piece(bar, "LanternCrossbarSouth", Vector3.new(127, 38.2, 490.5), Vector3.new(0.5, 0.7, 6))
		B.Hide(bar)
	end
end

-- Installs the machine into Workspace.DOGROTS_District.05_MutationLab (idempotent).
function B.Install(lab: Instance): Model
	local old = lab:FindFirstChild(L.Name)
	if old then
		B.Uninstall(lab)
	end
	local chamber = lab:FindFirstChild("CentralChamber")
	if chamber then
		B.HideTree(chamber)
	end
	local machine = B.Build(nil)
	cutRoof(lab, machine)
	local anchor = lab:FindFirstChild("InteractionAnchor")
	if anchor and anchor:IsA("BasePart") then
		move(anchor, CFrame.new(L.World(L.Anchor)) * CFrame.Angles(0, -math.pi / 2, 0))
	end
	machine.Parent = lab
	return machine
end

function B.Uninstall(lab: Instance): number
	local machine = lab:FindFirstChild(L.Name)
	if machine then
		machine:Destroy()
	end
	return B.Restore(lab)
end

return B
