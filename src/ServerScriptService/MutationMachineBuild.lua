-- Builds the NUCLEAR MUTATION MACHINE in the Mutation Lab (docs/LAB.md): a glass tube from the hall
-- floor through the roof skylight, stacked metal rings, a heavy pedestal with a loading door, a liquid
-- column and energy core, a lift and a placer arm; above the roof the giant reactor column (a twisted
-- hyperboloid cooling tower: steel lattice, glass drums with glowing joint rings, a coolant pool, the
-- plasma column with a DNA double helix, a crown with tesla coils, steam and the beacon spire); in the
-- hall the mega console (command desk with ACTIVATE, wings with key matrices, knobs, the master switch
-- and the throttle bank, instrument towers with screens, meters and gauges). Server-only geometry
-- (MutationMachineWorld.server runs Install); tools/qa scenes call Build directly. Moving parts carry
-- fixed names the client cinematic animates (Modules.LabPresentation): Lift.{Carriage,Mast,Platform},
-- IntakeDoor, Rotor1/Rotor2 (RotorHub root, welded), ChamberLiquid, LiquidSurface, EnergyRail1..4,
-- PlacerArm.{Turret,Upper,Fore,Claw}, ButtonGuard, ButtonDome, LeverL/LeverR, Throttle1..4 and
-- MasterSwitch (Swing attribute), GaugeNeedle*, screens ScreenL/ScreenR/MainSign; the idle show lights
-- UpperBandGlow (Band), Helix*, Core, UpperLiquid, PoolSurface, PanelKey, PanelLamp, MeterSeg (Index),
-- WingGlow/DeskGlow and the panels' Led (Row / Col) and Bar (Index) frames.
-- Old geometry is never deleted: hidden parts keep their original values in MutationMachine_*
-- attributes (Uninstall restores them).
local RS = game:GetService("ReplicatedStorage")
local Forge = require(RS.Forge)
local L = require(RS.MutationMachineLayout)
local P = Forge.Palette

local B = {}
B.Prefix = "MutationMachine_"
B.MaxParts = 1300

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

------------------------------------------------------------------------------------------------
-- The giant column above the roof (Layout.Tower): a hyperboloid cooling tower
------------------------------------------------------------------------------------------------
local W = L.Tower
local STEAM = "rbxasset://textures/particles/smoke_main.dds"

local function emitter(part: BasePart, name: string, spec: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in spec do
		(e :: any)[k] = v
	end
	e.Parent = part
	return e
end
local function holder(b: any, name: string, size: Vector3, cf: CFrame): BasePart
	return b:Box(size, cf, COL.Teal, "SmoothPlastic", { Name = name, Transparency = 1, CastShadow = false })
end

-- Flat panel between two horizontal chords (a glass facet of a drum) centred at angle a: inner-circle
-- radii r0 at height y0 and r1 at y1, width w (the wider chord, so the drum has no gaps).
local function facet(b: any, a: number, r0: number, y0: number, r1: number, y1: number, w: number, color: Color3, mat: string, opts: { [string]: any }?): BasePart
	local u = Vector3.new(math.cos(a), 0, math.sin(a))
	local p0 = u * r0 + Vector3.new(0, y0, 0)
	local p1 = u * r1 + Vector3.new(0, y1, 0)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	return b:Box(Vector3.new(w, (p1 - p0).Magnitude + 0.06, 0.3), F * CFrame.fromMatrix((p0 + p1) / 2, tangent, (p1 - p0).Unit), color, mat, opts)
end

local function buildTower(b: any)
	b:Folder("Column")
	-- Neck through the roof, the roof deck over the cut skylight (world X 122.5..142, Z 466.5..487.5)
	-- and the collar where the tube exits.
	local neckBottom = T.GlassTop + 1.6
	b:CylY(T.UpperBottom - 1.4 - neckBottom, 17.6, at(0, (neckBottom + T.UpperBottom - 1.4) / 2, 0), COL.Gun, "Metal", { Name = "Neck" })
	b:Box(Vector3.new(19.5, 0.9, 21), at(-0.75, 35.85, 0), COL.GunDark, "DiamondPlate", named("RoofDeck", SOLID))
	b:CylY(1.4, 20.2, at(0, T.UpperBottom - 0.7, 0), COL.Gun, "Metal", named("RoofCollar", SOLID))
	b:Accent(b:CylY(0.25, 20.6, at(0, T.UpperBottom - 1.3, 0), COL.Teal, "Neon", { Name = "RoofGlow" }))
	local n = W.Facets
	-- Foot ring on the roof and the buttresses around it (they stay inside the roof's air handlers).
	local footR = L.TowerRadius(W.Bottom)
	ring(b, (W.Plinth + W.Bottom) / 2, footR - 0.3, W.Bottom - W.Plinth, 2.4, n, COL.GunDark, "Metal", named("TowerFoot", SOLID))
	for i = 0, 7 do
		local a = (i + 0.5) * math.pi / 4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		-- Wedge: the tall face (local +Z) leans on the foot ring, the slope runs down outwards.
		b:Wedge(Vector3.new(1.2, 4.2, 2.6), F * CFrame.fromMatrix(polar(a, footR + 1.2, W.Plinth + 2.1), out:Cross(Vector3.new(0, 1, 0)), Vector3.new(0, 1, 0)), COL.Gun, "Metal", { Name = "FootButtress" })
	end
	-- Glass shell: one drum of flat facets between each pair of joints, a glowing ring at every joint
	-- (UpperBandGlow, attribute Band = joint index from the foot: the client's rainbow waves climb them).
	for i = 1, #W.Drums - 1 do
		local y0, y1 = W.Drums[i], W.Drums[i + 1]
		local r0, r1 = L.TowerRadius(y0) - W.Inset, L.TowerRadius(y1) - W.Inset
		local w = 2 * math.max(r0, r1) * math.tan(math.pi / n) + 0.08
		for k = 0, n - 1 do
			facet(b, k * 2 * math.pi / n, r0, y0, r1, y1, w, COL.Glass, "Glass", { Name = "TowerGlass", Transparency = 0.62, CastShadow = false })
		end
	end
	for i, y in W.Drums do
		local glow = ring(b, y, L.TowerRadius(y) - 0.45, 0.8, 1.1, n, COL.Teal, "Neon", { Name = "UpperBandGlow", CastShadow = false })
		for _, p in glow do
			p:SetAttribute("Band", i)
		end
		b:Accent(glow)
	end
	-- The twisted steel lattice: both families of the hyperboloid's straight generators, foot -> waist
	-- -> crown (a Shukhov tower; the rods stay just outside the glass).
	for section = 1, 2 do
		for k = 0, W.Rods - 1 do
			for _, s in { 1, -1 } do
				local p0, p1 = L.TowerRod(section, k, s)
				b:Rod(L.World(p0), L.World(p1), 0.7, COL.Steel, "Metal", { Name = "TowerRod" })
			end
		end
	end
	-- Coolant pool at the foot (UpperLiquid), the plasma column on the axis (Core) in its glass sheath.
	local poolBottom = T.UpperBottom + 0.1
	local poolR = L.TowerGlass(W.PoolTop) - 0.35
	b:CylY(W.PoolTop - poolBottom, poolR * 2, at(0, (W.PoolTop + poolBottom) / 2, 0), L.Liquid, "Neon", { Name = "UpperLiquid", Transparency = 0.45, CastShadow = false })
	b:Accent(b:CylY(0.2, poolR * 2 + 0.1, at(0, W.PoolTop, 0), COL.Teal, "Neon", { Name = "PoolSurface", Transparency = 0.2, CastShadow = false }))
	local coreBottom = T.UpperBottom - 1.6
	b:Accent(b:CylY(W.Hub - coreBottom, 2.6, at(0, (W.Hub + coreBottom) / 2, 0), C3(205, 255, 240), "Neon", { Name = "Core", CastShadow = false }))
	b:CylY(W.Top - W.PoolTop, 5.2, at(0, (W.Top + W.PoolTop) / 2, 0), COL.Glass, "Glass", { Name = "CoreSheath", Transparency = 0.72, CastShadow = false })
	-- DNA double helix around the plasma column: two strands of glowing bases, backbones and rungs.
	local H = W.Helix
	local dy = H.Pitch * H.Step / 360
	local count = math.floor((H.Top - H.Bottom) / dy)
	local last: { Vector3 }? = nil
	for i = 0, count do
		local y = H.Bottom + i * dy
		local a = math.rad(i * H.Step)
		local pa, pb = polar(a, H.Radius, y), polar(a + math.pi, H.Radius, y)
		b:Accent(b:Ball(1.5, F * CFrame.new(pa), COL.Teal, "Neon", { Name = "HelixA", CastShadow = false }))
		b:Accent(b:Ball(1.5, F * CFrame.new(pb), COL.Hazard, "Neon", { Name = "HelixB", CastShadow = false }))
		b:Rod(L.World(pa), L.World(pb), 0.3, C3(225, 255, 245), "Neon", { Name = "HelixRung", Transparency = 0.35, CastShadow = false })
		if last then
			b:Rod(L.World(last[1]), L.World(pa), 0.42, COL.Teal, "Neon", { Name = "HelixSpineA", Transparency = 0.2, CastShadow = false })
			b:Rod(L.World(last[2]), L.World(pb), 0.42, COL.Hazard, "Neon", { Name = "HelixSpineB", Transparency = 0.2, CastShadow = false })
		end
		last = { pa, pb }
	end
	-- Light of the pool and its bubbles.
	b:Light(holder(b, "CoreLightPart", Vector3.new(0.2, 0.2, 0.2), at(0, 52, 0)), COL.Teal, 48, 2.4, "Point").Name = "CoreLight"
	emitter(holder(b, "PoolBubbleSource", Vector3.new(poolR * 1.3, 0.2, poolR * 1.3), at(0, poolBottom + 1.2, 0)), "PoolBubbles", {
		Rate = 14,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(6, 6),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(C3(220, 255, 245)),
		LightEmission = 1,
		LightInfluence = 0,
	})
	b:Into(b.Model)
end

-- The crown: heavy rim with a glowing lip, struts to the hub, tesla coils, warning lights, the spire with
-- the beacon and the cooling-tower steam (Steam: white plumes; SteamGlow: the column's colour).
local function buildCrown(b: any)
	b:Folder("Cap")
	local top = W.Top
	local n = W.Facets
	local rimR = L.TowerRadius(top)
	ring(b, top + 0.9, rimR - 0.2, 1.8, 2.0, n, COL.GunDark, "Metal", { Name = "CrownRim" })
	b:Accent(ring(b, top + 1.95, rimR - 0.2, 0.3, 2.1, n, COL.Teal, "Neon", { Name = "CapGlow", CastShadow = false }))
	local hub = Vector3.new(0, W.Hub, 0)
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		b:Rod(L.World(polar(a, rimR - 0.7, top + 1.8)), L.World(hub), 0.9, COL.Steel, "Metal", { Name = "CrownStrut" })
	end
	b:Ball(4.2, at(0, W.Hub, 0), COL.GunDark, "Metal", { Name = "CrownHub" })
	b:Accent(b:CylY(0.5, 4.7, at(0, W.Hub, 0), COL.Teal, "Neon", { Name = "CapGlow", CastShadow = false }))
	-- Four tesla coils on the rim.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local base = polar(a, rimR - 0.2, top + 1.8)
		b:CylY(5.0, 1.3, F * CFrame.new(base + Vector3.new(0, 2.5, 0)), COL.Copper, "Metal", { Name = "Coil" })
		b:Ellipsoid(Vector3.new(3.2, 0.9, 3.2), F * CFrame.new(base + Vector3.new(0, 5.2, 0)), COL.Light, "Metal", { Name = "CoilTorus" })
		b:Accent(b:Ball(1.1, F * CFrame.new(base + Vector3.new(0, 5.9, 0)), COL.Teal, "Neon", { Name = "CoilSpark" }))
		b:Detail(function()
			b:CylY(0.3, 1.9, F * CFrame.new(base + Vector3.new(0, 1.2, 0)), COL.GunDark, "Metal", { Name = "CoilWinding" })
			b:CylY(0.3, 1.9, F * CFrame.new(base + Vector3.new(0, 3.1, 0)), COL.GunDark, "Metal", { Name = "CoilWinding" })
		end)
	end
	-- Warning lights on the rim's outer face and the spire with the red beacon (a machine light).
	for i = 0, 3 do
		b:Accent(b:Box(Vector3.new(1.8, 1.0, 0.45), tangentFrame(math.rad(i * 90), rimR + 0.95, top + 0.9), COL.Red, "Neon", { Name = "WarningLight" .. (i + 1) }))
	end
	b:CylY(T.Top - 0.8 - (W.Hub + 2), 0.9, at(0, (T.Top - 0.8 + W.Hub + 2) / 2, 0), COL.Light, "Metal", { Name = "Antenna" })
	for _, y in { W.Hub + 9, W.Hub + 15 } do
		b:Box(Vector3.new(4.2, 0.3, 0.3), at(0, y, 0), COL.Light, "Metal", { Name = "AntennaBar" })
		b:Box(Vector3.new(0.3, 0.3, 4.2), at(0, y, 0), COL.Light, "Metal", { Name = "AntennaBar" })
	end
	local beacon = b:Ball(2.4, at(0, T.Top, 0), COL.Red, "Neon", { Name = "Beacon", CastShadow = false })
	b:Light(beacon, COL.Red, 44, 3, "Point").Name = "BeaconLight"
	b:Light(holder(b, "CrownLightPart", Vector3.new(0.2, 0.2, 0.2), at(0, top - 3, 0)), COL.Teal, 56, 2.2, "Point").Name = "CrownLight"
	local vent = holder(b, "SteamVent", Vector3.new(rimR * 1.3, 0.2, rimR * 1.3), at(0, top + 1.2, 0))
	emitter(vent, "Steam", {
		Texture = STEAM,
		Rate = 3,
		Lifetime = NumberRange.new(10, 15),
		Speed = NumberRange.new(7, 11),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 9), NumberSequenceKeypoint.new(0.4, 22), NumberSequenceKeypoint.new(1, 38) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.55), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(C3(236, 242, 248), C3(200, 210, 222)),
		Acceleration = Vector3.new(1.6, 0.4, 0.8),
		Drag = 0.25,
		RotSpeed = NumberRange.new(-12, 12),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.05,
		LightInfluence = 0.7,
	})
	emitter(vent, "SteamGlow", {
		Texture = STEAM,
		Rate = 1.2,
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(5, 8),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 24) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(COL.Teal),
		RotSpeed = NumberRange.new(-20, 20),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.7,
		LightInfluence = 0,
	})
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

------------------------------------------------------------------------------------------------
-- The mega console
------------------------------------------------------------------------------------------------
local RAINBOW = { C3(255, 70, 90), C3(255, 150, 40), C3(255, 225, 60), C3(80, 235, 120), C3(60, 220, 255), C3(120, 120, 255), C3(220, 90, 255) }
local function rainbow(i: number): Color3
	return RAINBOW[(i - 1) % #RAINBOW + 1]
end

-- Round gauge facing -X (the operator); the needle turns about the pivot's X axis.
local function gauge(b: any, x: number, y: number, z: number, index: number)
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

-- Panel furniture on a surface frame (Y = the panel's normal). PanelKey caps, PanelLamp domes and the
-- glow strips are what the client's idle show and the cinematic light up.
local function key(b: any, cf: CFrame, d: number, color: Color3, round: boolean?)
	if round then
		b:Disc(cf * CFrame.new(0, 0.06, 0), d + 0.2, 0.12, COL.Black, "Metal", { Name = "KeyCollar" })
		b:Accent(b:Disc(cf * CFrame.new(0, 0.17, 0), d, 0.22, color, "Neon", { Name = "PanelKey" }))
	else
		b:Accent(b:Box(Vector3.new(d, 0.16, d), cf * CFrame.new(0, 0.08, 0), color, "Neon", { Name = "PanelKey" }))
	end
end
local function lamp(b: any, cf: CFrame, d: number, color: Color3)
	b:Accent(b:Ellipsoid(Vector3.new(d, d * 0.8, d), cf, color, "Neon", { Name = "PanelLamp", CastShadow = false }))
end
local function toggle(b: any, cf: CFrame, up: boolean)
	b:Box(Vector3.new(0.5, 0.12, 0.36), cf * CFrame.new(0, 0.06, 0), COL.Light, "Metal", { Name = "ToggleBase" })
	b:Box(Vector3.new(0.09, 0.5, 0.09), cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(up and -24 or 24)) * CFrame.new(0, 0.25, 0), COL.Light, "Metal", { Name = "ToggleLever" })
end
local function knob(b: any, cf: CFrame, d: number)
	b:Disc(cf * CFrame.new(0, 0.2, 0), d, 0.4, COL.Black, "SmoothPlastic", { Name = "Knob" })
	b:Box(Vector3.new(0.1, 0.08, d * 0.42), cf * CFrame.new(0, 0.42, -d * 0.22), COL.Hazard, "Neon", { Name = "KnobMark" })
end

-- Screen furniture (SurfaceGui frames, no parts): LED grids (Frames named Led, attributes Row / Col)
-- and equalizers (Frames named Bar, attribute Index, standing on the box's floor).
local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3, corner: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(corner, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end
local function leds(gui: Instance, x: number, y: number, w: number, h: number, rows: number, cols: number)
	local box = frame(gui, "LedMatrix", UDim2.fromScale(x, y), UDim2.fromScale(w, h), COL.Black)
	box.BackgroundTransparency = 0.2
	for r = 1, rows do
		for c = 1, cols do
			local led = frame(box, "Led", UDim2.fromScale((c - 0.85) / cols, (r - 0.85) / rows), UDim2.fromScale(0.7 / cols, 0.7 / rows), Color3.fromHSV(((c + r) / (cols + rows)) % 1, 0.7, 1), 0.3)
			led:SetAttribute("Row", r)
			led:SetAttribute("Col", c)
		end
	end
end
local function bars(gui: Instance, x: number, y: number, w: number, h: number, count: number)
	local box = frame(gui, "Scope", UDim2.fromScale(x, y), UDim2.fromScale(w, h), C3(8, 16, 24))
	for i = 1, count do
		local bar = frame(box, "Bar", UDim2.fromScale((i - 0.9) / count, 1), UDim2.fromScale(0.8 / count, 0.25 + 0.6 * ((i * 7) % 5) / 5), Color3.fromHSV(i / count, 0.75, 1))
		bar.AnchorPoint = Vector2.new(0, 1)
		bar:SetAttribute("Index", i)
	end
end

-- The console (operator side): the command desk with ACTIVATE in the middle, wings either side of the
-- walkway (knobs, key matrices, the master switch and the throttle bank, LED panels) and the two
-- instrument towers behind the desk (reactor / odds screens, level meters, gauges, keys, lamps).
-- Moving parts for the cinematic: ButtonGuard, ButtonDome, LeverL/LeverR, Throttle1..4 and
-- MasterSwitch (folders turned about their pivot's Z axis by the Swing attribute), GaugeNeedle1..4.
local function buildConsole(b: any)
	local K = L.Console
	local console = b:Folder("Console")
	-- Deck under the whole U and the operator dais.
	local deckFrom, deckTo = K.WingFrom - 0.5, -11
	local deckW = 2 * K.WingOuter + 0.8
	b:Box(Vector3.new(deckTo - deckFrom, 0.5, deckW), at((deckFrom + deckTo) / 2, 0.25, 0), COL.GunDark, "DiamondPlate", named("ConsoleDeck", SOLID))
	b:Box(Vector3.new(0.3, 0.12, deckW), at(deckFrom + 0.15, 0.56, 0), COL.Hazard, "SmoothPlastic", { Name = "DeckEdge" })
	b:Box(Vector3.new(4, 0.25, 10), at(-29, 0.625, 0), COL.Gun, "DiamondPlate", named("OperatorDais", SOLID))
	b:Detail(function()
		for i = 0, 4 do
			b:Box(Vector3.new(0.9, 0.06, 2), at(-30.6, 0.77, -4 + i * 2), i % 2 == 0 and COL.Hazard or COL.Black, "SmoothPlastic", { Name = "DaisHazard" })
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
	for i, spec in { { -1.4, -1.8, COL.Teal }, { -1.4, 1.8, COL.Hazard }, { -0.2, -5.0, P.Green }, { -0.2, 5.0, COL.Orange }, { 1.3, -5.0, COL.Teal }, { 1.3, 5.0, COL.Teal } } do
		b:Accent(b:Box(Vector3.new(0.6, 0.16, 0.6), S * CFrame.new(spec[1], 0.08, spec[2]), spec[3], "Neon", { Name = "DeskKey" .. i }))
	end
	-- A row of toggles in front of the levers and two trim knobs behind them.
	for _, side in { -1, 1 } do
		for i, z in { 2.6, 3.3, 4.0 } do
			toggle(b, S * CFrame.new(-1.65, 0, side * z), (i + (side > 0 and 1 or 0)) % 2 == 0)
		end
		knob(b, S * CFrame.new(1.45, 0, side * 2.45), 0.75)
	end

	-- Wings (the U arms either side of the walkway).
	local wingLen = K.WingTo - K.WingFrom
	local wingX = (K.WingFrom + K.WingTo) / 2
	local depth = K.WingOuter - K.WingInner
	local rise = K.WingHigh - K.WingLow
	local tilt = math.atan(rise / depth)
	local panelH = 2.8
	for _, side in { -1, 1 } do
		local zMid = side * (K.WingInner + K.WingOuter) / 2
		local desk = b:Box(Vector3.new(wingLen, K.WingLow, depth), at(wingX, K.WingLow / 2, zMid), COL.Gun, "Metal", named("WingDesk", SOLID))
		b:Wedge(Vector3.new(wingLen, rise, depth), at(wingX, K.WingLow + rise / 2, zMid) * CFrame.Angles(0, side < 0 and math.pi or 0, 0), COL.GunDark, "Metal", named("WingSlope", SOLID))
		b:Accent(b:Box(Vector3.new(wingLen - 0.4, 0.22, 0.12), at(wingX, K.WingLow - 0.35, side * (K.WingInner - 0.06)), COL.Teal, "Neon", { Name = "WingGlow" }))
		-- Frame on the slope: X along the wing (toward the tube), Y = its normal; v is measured outwards.
		local surface = at(wingX, K.WingLow + rise / 2, zMid) * CFrame.Angles(-side * tilt, 0, 0)
		local function on(u: number, v: number): CFrame
			return surface * CFrame.new(u, 0, side * v)
		end
		-- Knob bank (behind the operator), a key matrix beside the operator, lamps along the low edge.
		for i, v in { -1.2, 0, 1.2 } do
			knob(b, on(-5.1, v), 0.85)
			key(b, on(-3.85, v), 0.6, rainbow(i + (side > 0 and 3 or 0)), true)
		end
		for r, v in { -1.3, 0, 1.3 } do
			for c = 1, 5 do
				key(b, on(-3.0 + (c - 1) * 0.95, v), 0.62, rainbow(c + r + (side > 0 and 2 or 0)))
			end
		end
		for i = 1, 6 do
			lamp(b, on(-5.5 + (i - 1) * 2.2, -1.95) * CFrame.new(0, 0.12, 0), 0.42, rainbow(i + (side > 0 and 4 or 0)))
		end
		if side > 0 then
			-- Throttle bank by the command desk: four levers leaning back to the operator, pushed toward
			-- the tube during the cinematic.
			for i = 1, 4 do
				local base = on(3.6, -1.35 + (i - 1) * 0.9)
				b:Box(Vector3.new(2.2, 0.12, 0.36), base * CFrame.new(0, 0.06, 0), COL.Black, "SmoothPlastic", { Name = "ThrottleSlot" })
				local lever = b:Folder("Throttle" .. i)
				local pivotCF = base * CFrame.new(0, 0.12, 0)
				local handle = pivotCF * CFrame.Angles(0, 0, math.rad(28))
				b:Box(Vector3.new(0.16, 1.5, 0.16), handle * CFrame.new(0, 0.75, 0), COL.Light, "Metal", { Name = "ThrottleRod" })
				b:Box(Vector3.new(0.34, 0.34, 0.6), handle * CFrame.new(0, 1.55, 0), rainbow(i * 2), "SmoothPlastic", { Name = "ThrottleGrip" })
				lever.WorldPivot = pivotCF
				lever:SetAttribute("Swing", math.rad(-56))
				b:Into(console)
			end
		else
			-- Master knife switch (rests open; the cinematic slams it shut) and two big keys.
			local hingeU, contactU = 1.9, 4.5
			b:Box(Vector3.new(contactU - hingeU + 1.0, 0.12, 1.5), on((hingeU + contactU) / 2, 0) * CFrame.new(0, 0.06, 0), COL.Black, "SmoothPlastic", { Name = "SwitchBase" })
			b:Box(Vector3.new(0.3, 0.5, 0.9), on(hingeU, 0) * CFrame.new(0, 0.37, 0), COL.Copper, "Metal", { Name = "SwitchHinge" })
			b:Box(Vector3.new(0.3, 0.5, 0.9), on(contactU, 0) * CFrame.new(0, 0.37, 0), COL.Copper, "Metal", { Name = "SwitchContact" })
			local switch = b:Folder("MasterSwitch")
			local pivotCF = on(hingeU, 0) * CFrame.new(0, 0.5, 0)
			local blade = pivotCF * CFrame.Angles(0, 0, math.rad(65))
			local len = contactU - hingeU
			b:Box(Vector3.new(len + 0.3, 0.1, 0.5), blade * CFrame.new(len / 2, 0, 0), COL.Copper, "Metal", { Name = "SwitchBlade" })
			b:Cyl(0.9, 0.34, blade * CFrame.new(len + 0.2, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), COL.Red, "SmoothPlastic", { Name = "SwitchHandle" })
			switch.WorldPivot = pivotCF
			switch:SetAttribute("Swing", math.rad(-65))
			b:Into(console)
			key(b, on(5.4, -0.9), 0.7, COL.Red, true)
			key(b, on(5.4, 0.9), 0.7, P.Green, true)
		end
		-- Upright LED panel along the outer edge (faces the walkway) with a row of lamps on top.
		local panel = b:Box(Vector3.new(wingLen - 0.8, panelH, 0.5), at(wingX, K.WingHigh + panelH / 2 - 0.1, side * (K.WingOuter - 0.25)), COL.GunDark, "Metal", { Name = "WingPanel" })
		local pg = surfaceGui(panel, side > 0 and Enum.NormalId.Front or Enum.NormalId.Back, 36)
		local titles = side < 0 and { "COOLANT", "PLASMA", "DNA SYNC" } or { "RADIATION", "GENOME", "OVERDRIVE" }
		for i, text in titles do
			label(pg, "Title" .. i, text, UDim2.fromScale(0.02 + (i - 1) * 0.33, 0.03), UDim2.fromScale(0.3, 0.22), i == 2 and COL.Hazard or COL.Teal)
		end
		leds(pg, 0.02, 0.3, 0.55, 0.65, 3, 14)
		bars(pg, 0.6, 0.3, 0.38, 0.65, 12)
		for i = 1, 7 do
			lamp(b, at(wingX - 5.1 + (i - 1) * 1.7, K.WingHigh + panelH - 0.1 + 0.2, side * (K.WingOuter - 0.25)), 0.5, rainbow(i + (side > 0 and 2 or 5)))
		end
		-- The wing's back end faces the hall entrance.
		local rear = surfaceGui(desk, Enum.NormalId.Left, 36)
		label(rear, "Title", "☢ DOGROTS REACTOR ☢", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.3), COL.Hazard)
		leds(rear, 0.08, 0.45, 0.84, 0.45, 2, 8)
	end

	-- Instrument towers behind the command desk (the gap between them keeps the bay and the tube in view).
	local towerX = (K.TowerFront + K.TowerBack) / 2
	local towerD = K.TowerBack - K.TowerFront
	local towerW = K.TowerOuter - K.TowerInner
	for _, side in { -1, 1 } do
		local zc = side * (K.TowerInner + K.TowerOuter) / 2
		b:Box(Vector3.new(towerD, K.TowerTop - 0.5, towerW), at(towerX, (K.TowerTop + 0.5) / 2, zc), COL.Gun, "Metal", named("InstrumentTower", SOLID))
		b:Box(Vector3.new(towerD + 0.4, 0.4, towerW + 0.4), at(towerX, K.TowerTop + 0.2, zc), COL.GunDark, "Metal", { Name = "TowerCap" })
		local sw, sh = 5.6, 3.4
		local s = screen(b, side < 0 and "ScreenL" or "ScreenR", at(K.TowerFront - 0.2, 8.6, side * (K.TowerOuter - 0.3 - sw / 2)), sw, sh)
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
		-- Level meter by the gap (MeterSeg Index 1..8 from the bottom), gauges and keys under the screen,
		-- three lamps on the roof.
		local mz = side * (K.TowerInner + 0.55)
		b:Box(Vector3.new(0.1, 5.7, 1.1), at(K.TowerFront - 0.03, 7.65, mz), COL.Black, "SmoothPlastic", { Name = "MeterBack" })
		for i = 1, 8 do
			local seg = b:Box(Vector3.new(0.12, 0.52, 0.8), at(K.TowerFront - 0.09, 5.1 + (i - 0.5) * 0.66, mz), Color3.fromHSV(0.33 - (i - 1) / 7 * 0.33, 0.85, 1), "Neon", { Name = "MeterSeg", CastShadow = false })
			seg:SetAttribute("Index", i)
			b:Accent(seg)
		end
		gauge(b, K.TowerFront - 0.08, 5.8, side * 5.55, side < 0 and 1 or 3)
		gauge(b, K.TowerFront - 0.08, 5.8, side * 7.45, side < 0 and 2 or 4)
		for r, y in { 5.3, 6.25 } do
			for c, z in { 9.1, 10.05 } do
				key(b, at(K.TowerFront, y, side * z) * CFrame.Angles(0, 0, math.pi / 2), 0.62, rainbow(r * 2 + c + (side > 0 and 3 or 0)), true)
			end
		end
		for i, z in { 4.6, 7.1, 9.6 } do
			lamp(b, at(towerX, K.TowerTop + 0.6, side * z), 0.8, ({ COL.Red, COL.Hazard, P.Green })[i])
		end
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
	local light = b:Light(spot, C3(200, 230, 255), 24, 1.6, "Spot") :: SpotLight
	light.Name = "ConsoleLight"
	light.Face = Enum.NormalId.Bottom
	light.Angle = 80
	-- Floor cables from the instrument towers to the pedestal.
	for _, side in { -1, 1 } do
		local c1 = L.World(Vector3.new(K.TowerBack + 0.2, 0.75, side * 9.6))
		local c2 = L.World(Vector3.new(-11.5, 0.3, side * 11.6))
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
	buildTower(b)
	buildCrown(b)
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
