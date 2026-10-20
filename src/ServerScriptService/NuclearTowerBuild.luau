-- Builds the NUCLEAR MUTATION TOWER compound (ReplicatedStorage.NuclearLayout) under the lab model:
-- a concrete cooling tower on diagonal legs with a glowing coolant pool and steam at the crown, the
-- dog-paw radiation emblem on its west face, the portal with the WARNING blast door, the dark
-- chamber with the mechanical arm, the loading pad, the control console with its screens, buttons
-- and beacons, barrels of nuclear waste, barriers, pipes and floodlights.
-- Used at build time (the compound is saved in the place, visible in Studio) and by
-- ServerScriptService.NuclearTowerWorld as a fallback when the model is missing.
-- Only CFrame/Size/Color/Material are written; no physics, no Position reads.
local RS = game:GetService("ReplicatedStorage")
local L = require(RS:WaitForChild("NuclearLayout"))

local B = {}
B.MaxParts = 2400

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local CONCRETE = C(200, 196, 188)
local CONCRETE_DARK = C(150, 146, 140)
local STEEL = C(86, 92, 102)
local STEEL_DARK = C(44, 48, 56)
local YELLOW = L.Hazard
local BLACK = C(24, 24, 26)
local TOXIC = L.Toxic
local RED = C(230, 40, 40)

local count = 0
local function P(parent, name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.Parent = parent
	count += 1
	return p
end
local function solid(p) p.CanCollide = true; p.CanQuery = true; return p end
local function cyl(parent, name, axisCF, length, diameter, color, mat, props)
	-- cylinder whose axis is the X axis of axisCF
	local p = P(parent, name, V(length, diameter, diameter), axisCF, color, mat, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function cylY(parent, name, cf, height, diameter, color, mat, props)
	return cyl(parent, name, cf * ANG(0, 0, rad(90)), height, diameter, color, mat, props)
end
local function ball(parent, name, d, cf, color, mat, props)
	local p = P(parent, name, V(d, d, d), cf, color, mat, props)
	p.Shape = Enum.PartType.Ball
	return p
end
local function blob(parent, name, size, cf, color, mat, props)
	local p = P(parent, name, size, cf, color, mat, props)
	local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Parent = p
	return p
end
local function wedge(parent, name, size, cf, color, mat, props)
	local p = Instance.new("WedgePart")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.Parent = parent
	count += 1
	return p
end
local function bar(parent, name, a, b, w, color, mat, props)
	local d = b - a
	local len = d.Magnitude
	local look = d.Unit
	local right = look:Cross(V(0, 1, 0))
	if right.Magnitude < 1e-3 then right = V(1, 0, 0) end
	return P(parent, name, V(w, len, w), CFrame.fromMatrix((a + b) / 2, right.Unit, look), color, mat, props)
end
local function model(parent, name)
	local m = Instance.new("Model"); m.Name = name; m.Parent = parent; return m
end
local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end
local function emitter(parent, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end
local function gui(part, name, face, ppm)
	local g = Instance.new("SurfaceGui")
	g.Name = name; g.Face = face; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = ppm or 50
	g.LightInfluence = 0; g.MaxDistance = 400; g.Parent = part
	return g
end
local function label(parent, name, text, pos, size, color, props)
	local t = Instance.new("TextLabel")
	t.Name = name; t.BackgroundTransparency = 1; t.Text = text; t.Position = pos; t.Size = size; t.TextColor3 = color
	t.TextScaled = true; t.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	if props then for k, v in pairs(props) do (t :: any)[k] = v end end
	t.Parent = parent
	return t
end
local function frame(parent, name, pos, size, color, props)
	local f = Instance.new("Frame")
	f.Name = name; f.Position = pos; f.Size = size; f.BackgroundColor3 = color; f.BorderSizePixel = 0
	if props then for k, v in pairs(props) do (f :: any)[k] = v end end
	f.Parent = parent
	return f
end
local function corner(f, r) local c = Instance.new("UICorner"); c.CornerRadius = r or UDim.new(0, 12); c.Parent = f; return c end
local function stroke(f, color, th) local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = th or 4; s.Parent = f; return s end

-- Deterministic pseudo random (same compound everywhere).
local function rng(seed)
	local state = seed * 9301 + 49297
	return function(a, b)
		state = (state * 9301 + 49297) % 233280
		local r = state / 233280
		return a + (b - a) * r
	end
end

local GROUND = L.Ground
local CENTER = L.Center
local W = L.West

------------------------------------------------------------------------------------------------
-- The radiation trefoil with a paw (flat, in the frame's XY plane, front = -Z)
------------------------------------------------------------------------------------------------
local function trefoil(parent, frameCF, R, opts)
	opts = opts or {}
	local depth = opts.Depth or 0.18
	local yellow = opts.Yellow or YELLOW
	local black = opts.Black or BLACK
	local glow = opts.Glow or TOXIC
	-- discs (cylinder axis = disc X = the frame's -Z, outwards)
	local disc = frameCF * ANG(0, rad(90), 0)
	cyl(parent, "EmblemBack", disc * CF(-0.18, 0, 0), depth, R * 2.12, black, Enum.Material.Metal)
	cyl(parent, "EmblemDisc", disc * CF(0.02, 0, 0), depth, R * 2, yellow, Enum.Material.SmoothPlastic)
	-- three blades centred at 30, 150, 270 degrees, each 60 degrees wide
	local rIn, rOut = R * 0.42, R * 0.9
	local slices = 7
	for _, centre in ipairs({ 30, 150, 270 }) do
		for i = 0, slices - 1 do
			local a = rad(centre - 30 + (i + 0.5) * 60 / slices)
			local rm = (rIn + rOut) / 2
			local width = 2 * rOut * math.sin(rad(60 / slices) / 2) * 1.12
			P(parent, "Blade", V(width, rOut - rIn, depth), frameCF * CF(math.cos(a) * rm, math.sin(a) * rm, -depth * 1.1) * ANG(0, 0, a - math.pi / 2), black, Enum.Material.SmoothPlastic, { CastShadow = false })
		end
	end
	-- centre: black disc with a glowing paw
	cyl(parent, "EmblemHub", disc * CF(depth * 1.2, 0, 0), depth, R * 0.68, black, Enum.Material.SmoothPlastic, { CastShadow = false })
	local paw = model(parent, "Paw")
	local s = R * 0.068
	blob(paw, "PawPad", V(2.4 * s, 2.0 * s, 0.3), frameCF * CF(0, -0.55 * s, -depth * 2.4), glow, Enum.Material.Neon, { CastShadow = false })
	for i, t in ipairs({ { -1.35, 0.75 }, { -0.48, 1.45 }, { 0.48, 1.45 }, { 1.35, 0.75 } }) do
		blob(paw, "PawToe" .. i, V(0.95 * s, 1.15 * s, 0.3), frameCF * CF(t[1] * s, t[2] * s, -depth * 2.4) * ANG(0, 0, -t[1] * 0.25), glow, Enum.Material.Neon, { CastShadow = false })
	end
	-- glow ring round the edge
	local n = 32
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local r = R * 1.06
		P(parent, "EmblemRing", V(2 * r * math.sin(math.pi / n) * 1.05, 0.28, 0.12), frameCF * CF(math.cos(a) * r, math.sin(a) * r, -depth * 1.4) * ANG(0, 0, a - math.pi / 2), glow, Enum.Material.Neon, { CastShadow = false })
	end
end
B.Trefoil = trefoil

------------------------------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------------------------------
local function buildGround(root)
	local g = model(root, "Grounds")
	local Pz = L.Plaza
	solid(P(g, "Plaza", V(Pz.X1 - Pz.X0, 1, Pz.Z1 - Pz.Z0), CF((Pz.X0 + Pz.X1) / 2, GROUND - 0.5, (Pz.Z0 + Pz.Z1) / 2), C(132, 132, 128), Enum.Material.Concrete))
	-- concrete tiles (darker joints)
	for x = Pz.X0 + 8, Pz.X1 - 8, 8 do P(g, "Joint", V(0.15, 0.05, Pz.Z1 - Pz.Z0 - 2), CF(x, GROUND + 0.01, (Pz.Z0 + Pz.Z1) / 2), C(104, 104, 100), Enum.Material.Concrete, { CastShadow = false }) end
	for z = Pz.Z0 + 8, Pz.Z1 - 8, 8 do P(g, "Joint", V(Pz.X1 - Pz.X0 - 2, 0.05, 0.15), CF((Pz.X0 + Pz.X1) / 2, GROUND + 0.01, z), C(104, 104, 100), Enum.Material.Concrete, { CastShadow = false }) end
	-- walkway from the entrance to the console: yellow edge lines and arrows
	for _, z in ipairs({ 471.5, 482.5 }) do P(g, "WalkLine", V(L.Console.Operator.X - Pz.X0 - 2, 0.06, 0.35), CF((Pz.X0 + L.Console.Operator.X) / 2, GROUND + 0.03, z), YELLOW, Enum.Material.SmoothPlastic, { CastShadow = false }) end
	for i = 0, 2 do
		local x = Pz.X0 + 3 + i * 3.4
		for s = -1, 1, 2 do P(g, "WalkArrow", V(1.6, 0.06, 0.4), CF(x, GROUND + 0.035, 477 + s * 0.5) * ANG(0, rad(-35 * s), 0), YELLOW, Enum.Material.Neon, { CastShadow = false }) end
	end
	-- hazard stripes round the tower foot
	local n = 64
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local r = L.Tower.BaseRadius + 2.2
		P(g, "FootStripe", V(2 * r * math.sin(math.pi / n) * 1.03, 0.07, 1.2), CF(CENTER + V(math.cos(a) * r, 0.04, math.sin(a) * r)) * ANG(0, -a + math.pi / 2, 0), i % 2 == 0 and YELLOW or BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
	end
end

local function buildTower(root)
	local t = model(root, "Tower")
	local T = L.Tower
	local N = T.Facets
	local shell = model(t, "Shell")
	local portalSpan = math.asin((L.Portal.Width / 2 + 0.8) / 24)
	for bi = 1, #T.Bands - 1 do
		local y0, y1 = T.Bands[bi], T.Bands[bi + 1]
		local r0, r1 = L.Radius(y0), L.Radius(y1)
		local ym = (y0 + y1) / 2
		local band = model(shell, "Band" .. bi)
		for j = 0, N - 1 do
			local a = (j + 0.5) / N * math.pi * 2
			local delta = math.abs(((a - W + math.pi) % (math.pi * 2)) - math.pi)
			if not (delta < portalSpan and y1 <= 26) then
				local outward = V(math.cos(a), 0, math.sin(a))
				local tangent = V(-math.sin(a), 0, math.cos(a))
				local along = (outward * (r1 - r0) + V(0, y1 - y0, 0)).Unit
				local width = 2 * math.max(r0, r1) * math.sin(math.pi / N) * 1.035 + 0.12
				local height = math.sqrt((y1 - y0) ^ 2 + (r1 - r0) ^ 2) + 0.12
				local rm = (r0 + r1) / 2 - T.Thickness / 2
				local pos = CENTER + V(math.cos(a) * rm, ym, math.sin(a) * rm)
				-- weathering: darker low down, vertical soot streaks, a red / white crown band
				local color = CONCRETE:Lerp(CONCRETE_DARK, math.clamp(1 - ym / 60, 0, 1) * 0.35)
				if (j % 7 == 3 or j % 11 == 5) and ym > 60 then color = color:Lerp(C(110, 108, 104), 0.25) end
				local mat = Enum.Material.Concrete
				if y0 >= 106 then color = (j % 2 == 0) and RED or C(240, 238, 232); mat = Enum.Material.SmoothPlastic end
				local f = P(band, "Facet", V(width, height, T.Thickness), CFrame.fromMatrix(pos, tangent, along), color, mat)
				f:SetAttribute("Angle", a)
				f:SetAttribute("Y", ym)
				f.CanCollide = y0 < 40
			end
		end
	end
	-- the ring beam on the legs and the crown lip
	local function ringOf(name, y, rOff, h, depth, color, mat, n)
		local rr = L.Radius(y) + rOff
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi * 2
			local delta = math.abs(((a - W + math.pi) % (math.pi * 2)) - math.pi)
			if not (name == "RingBeam" and delta < portalSpan) then
				P(t, name, V(2 * rr * math.sin(math.pi / n) * 1.04, h, depth), CF(CENTER + V(math.cos(a) * rr, y, math.sin(a) * rr)) * ANG(0, -a + math.pi / 2, 0), color, mat)
			end
		end
	end
	ringOf("RingBeam", T.Bands[1] - 0.4, 0, 1.4, 2.2, CONCRETE_DARK, Enum.Material.Concrete, 36)
	ringOf("CrownLip", T.Height + 0.4, 0.2, 1.0, 1.4, C(70, 68, 66), Enum.Material.Concrete, 36)
	-- glowing rim inside the crown
	local rim = model(t, "CrownGlow")
	for i = 0, 23 do
		local a = (i + 0.5) / 24 * math.pi * 2
		local rr = L.Radius(T.Height) - 1.4
		P(rim, "RimGlow", V(2 * rr * math.sin(math.pi / 24) * 1.05, 0.5, 0.4), CF(CENTER + V(math.cos(a) * rr, T.Height - 1.6, math.sin(a) * rr)) * ANG(0, -a + math.pi / 2, 0), TOXIC, Enum.Material.Neon, { CastShadow = false })
	end
	-- diagonal legs (V pairs) under the shell
	local legs = model(t, "Legs")
	local nLegs = 28
	local yTop = T.Bands[1] - 1
	for k = 0, nLegs - 1 do
		local a = (k + 0.5) / nLegs * math.pi * 2
		local delta = math.abs(((a - W + math.pi) % (math.pi * 2)) - math.pi)
		if delta > portalSpan + 0.08 then
			local top = CENTER + V(math.cos(a) * (L.Radius(yTop) - 0.6), yTop, math.sin(a) * (L.Radius(yTop) - 0.6))
			for s = -1, 1, 2 do
				local b = a + s * (math.pi / nLegs) * 0.9
				local foot = CENTER + V(math.cos(b) * (T.BaseRadius + 0.6), 0, math.sin(b) * (T.BaseRadius + 0.6))
				solid(bar(legs, "Leg", foot, top, 1.0, CONCRETE_DARK, Enum.Material.Concrete))
			end
		end
	end
	-- coolant pool and the core glow inside (seen from the crown and between the legs)
	local core = model(t, "Core")
	cylY(core, "CoolantPool", CF(CENTER + V(0, 0.6, 0)), 0.5, (T.BaseRadius - 1.5) * 2, C(60, 220, 110), Enum.Material.Neon, { CastShadow = false, Transparency = 0.15 })
	cylY(core, "PoolRim", CF(CENTER + V(0, 0.35, 0)), 0.7, (T.BaseRadius - 0.6) * 2, C(60, 64, 70), Enum.Material.Metal)
	local column = cylY(core, "CoreColumn", CF(CENTER + V(0, 22, 0)), 42, 4, TOXIC, Enum.Material.Neon, { CastShadow = false, Transparency = 0.45 })
	light(column, "PointLight", { Name = "CoreLight", Color = TOXIC, Range = 40, Brightness = 2.2, Shadows = false })
	for i = 1, 5 do
		local y = 4 + i * 7
		cylY(core, "CoreRing", CF(CENTER + V(0, y, 0)), 0.6, 7, C(70, 74, 82), Enum.Material.Metal)
	end
	-- steam at the crown
	local steam = P(t, "CrownSteam", V(L.Radius(T.Height) * 1.6, 1, L.Radius(T.Height) * 1.6), CF(CENTER + V(0, T.Height + 1, 0)), C(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
	emitter(steam, "Steam", {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 7, Lifetime = NumberRange.new(9, 14), Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(10, 10), Acceleration = V(1.2, 1.5, 0.6), Drag = 0.4, LightInfluence = 1, LightEmission = 0.05,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(0.5, 34), NumberSequenceKeypoint.new(1, 52) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.72), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(C(250, 250, 250), C(214, 220, 226)), RotSpeed = NumberRange.new(-12, 12), Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Top, Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	return t
end

local function buildEmblem(root)
	local e = model(root, "Emblem")
	local R = L.Emblem.Radius
	local f = L.ShellFrame(W, L.Emblem.Y, 0.55)
	trefoil(e, f, R)
	-- the title under the emblem
	local tf = L.ShellFrame(W, L.Emblem.Y - R - 4.2, 0.4)
	local sign = P(e, "EmblemTitle", V(26, 3.6, 0.3), tf, BLACK, Enum.Material.Metal)
	local g = gui(sign, "TitleGui", Enum.NormalId.Front, 30)
	local bg = frame(g, "Bg", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BLACK)
	stroke(bg, YELLOW, 6)
	label(bg, "Title", "☢ NUCLEAR MUTATION ☢", UDim2.fromScale(0.03, 0.08), UDim2.fromScale(0.94, 0.84), YELLOW, { TextStrokeTransparency = 0.6 })
	return e
end

local function hazardFrame(parent, cf, w, h, thick, depth)
	-- yellow / black chevron border round an opening (cf = opening centre, front = -Z)
	local seg = 1.1
	local function run(name, from, to)
		local d = to - from
		local n = math.max(1, math.floor(d.Magnitude / seg + 0.5))
		for i = 0, n - 1 do
			local a = from + d * (i / n)
			local b = from + d * ((i + 1) / n)
			local mid = (a + b) / 2
			local look = (b - a).Unit
			local right = look:Cross(V(0, 0, 1))
			P(parent, name, V((b - a).Magnitude + 0.02, thick, depth), cf * CFrame.fromMatrix(mid, look, V(0, 0, 1):Cross(look)), i % 2 == 0 and YELLOW or BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
		end
	end
	local hw, hh = w / 2 + thick / 2, h / 2 + thick / 2
	run("Chevron", V(-hw, -hh, 0), V(-hw, hh, 0))
	run("Chevron", V(-hw, hh, 0), V(hw, hh, 0))
	run("Chevron", V(hw, hh, 0), V(hw, -hh, 0))
end

local function buildPortal(root)
	local p = model(root, "Portal")
	local Po, D = L.Portal, L.Door
	local zc = CENTER.Z
	local x0, x1 = Po.Front, Po.Back
	local depth = x1 - x0
	local xc = (x0 + x1) / 2
	local sideW = (Po.Width - D.Width) / 2
	-- pillars and the header block
	for s = -1, 1, 2 do
		local z = zc + s * (D.Width / 2 + sideW / 2)
		solid(P(p, "Pillar", V(depth, Po.Height, sideW), CF(xc, GROUND + Po.Height / 2, z), CONCRETE, Enum.Material.Concrete))
		P(p, "PillarEdge", V(0.4, Po.Height, sideW + 0.2), CF(x0 - 0.15, GROUND + Po.Height / 2, z), CONCRETE_DARK, Enum.Material.Concrete)
	end
	local headerH = Po.Height - D.Height
	local roof = model(p, "TechnicalRoof")
	solid(P(roof, "Header", V(depth, headerH, D.Width + 0.2), CF(xc, GROUND + D.Height + headerH / 2, zc), CONCRETE, Enum.Material.Concrete))
	P(roof, "HeaderCap", V(depth + 1, 0.8, Po.Width + 1), CF(xc, GROUND + Po.Height + 0.4, zc), CONCRETE_DARK, Enum.Material.Concrete)
	-- chevron frame round the door opening
	local openCF = CF(x0 - 0.12, GROUND + D.Height / 2, zc) * ANG(0, rad(-90), 0)
	hazardFrame(p, openCF, D.Width, D.Height, 0.7, 0.25)
	-- sign over the door
	local sign = P(p, "PortalSign", V(0.3, 3.2, 13), CF(x0 - 0.3, GROUND + D.Height + 3.6, zc), BLACK, Enum.Material.Metal)
	local g = gui(sign, "SignGui", Enum.NormalId.Left, 40)
	local bg = frame(g, "Bg", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BLACK)
	stroke(bg, YELLOW, 6)
	label(bg, "Title", "☢ MUTATION REACTOR ☢", UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.94, 0.8), YELLOW)
	-- rotating beacons on the header (the cinematic spins their lights)
	for s = -1, 1, 2 do
		local base = CF(x0 + 1.2, GROUND + Po.Height + 0.8, zc + s * (Po.Width / 2 - 1.2))
		cylY(p, "BeaconBase", base * CF(0, 0.2, 0), 0.4, 1.4, STEEL_DARK, Enum.Material.Metal)
		local dome = ball(p, "Beacon", 1.2, base * CF(0, 0.85, 0), RED, Enum.Material.Neon, { Transparency = 0.15, CastShadow = false })
		light(dome, "SpotLight", { Name = "BeaconLight", Color = RED, Range = 40, Angle = 45, Brightness = 0, Face = Enum.NormalId.Front, Shadows = false })
	end
	-- the blast door (a model the cinematic lifts)
	local door = model(p, "BlastDoor")
	local leafCF = CF(L.DoorX, GROUND + D.Height / 2, zc) * ANG(0, rad(-90), 0) -- front (-Z) faces west
	local leaf = P(door, "Leaf", V(D.Width, D.Height, D.Thickness), leafCF, C(58, 62, 70), Enum.Material.DiamondPlate)
	solid(leaf)
	door.PrimaryPart = leaf
	-- stripes at the bottom and the side ribs
	for i = 0, 7 do
		P(door, "LeafStripe", V(D.Width / 8 + 0.02, 1.1, 0.1), leafCF * CF(-D.Width / 2 + (i + 0.5) * D.Width / 8, -D.Height / 2 + 0.6, -D.Thickness / 2 - 0.04), i % 2 == 0 and YELLOW or BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
	end
	for s = -1, 1, 2 do P(door, "LeafRib", V(0.5, D.Height - 0.4, 0.3), leafCF * CF(s * (D.Width / 2 - 0.4), 0, -D.Thickness / 2 - 0.1), STEEL, Enum.Material.Metal) end
	local face = P(door, "LeafFace", V(D.Width - 1.4, D.Height - 2.2, 0.08), leafCF * CF(0, 0.6, -D.Thickness / 2 - 0.06), BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
	local fg = gui(face, "WarningGui", Enum.NormalId.Front, 40)
	local fbg = frame(fg, "Bg", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), C(18, 18, 20))
	stroke(fbg, YELLOW, 10)
	label(fbg, "Icon", "☢", UDim2.fromScale(0.25, 0.05), UDim2.fromScale(0.5, 0.42), YELLOW)
	label(fbg, "Warning", "WARNING", UDim2.fromScale(0.05, 0.47), UDim2.fromScale(0.9, 0.24), RED, { TextStrokeTransparency = 0.3, TextStrokeColor3 = C(60, 0, 0) })
	label(fbg, "Sub", "MUTATION IN PROGRESS", UDim2.fromScale(0.08, 0.74), UDim2.fromScale(0.84, 0.13), YELLOW)
	label(fbg, "Sub2", "AUTHORIZED DOGS ONLY", UDim2.fromScale(0.12, 0.87), UDim2.fromScale(0.76, 0.09), C(200, 200, 200))
	-- steam vents beside the door (puff when it opens)
	for s = -1, 1, 2 do
		local vent = P(p, "DoorVent", V(0.6, 0.6, 0.6), CF(x0 - 0.4, GROUND + 1.2, zc + s * (D.Width / 2 + 1.2)), STEEL_DARK, Enum.Material.Metal)
		emitter(vent, "DoorSteam", { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 0, Enabled = false, Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(10, 16), SpreadAngle = Vector2.new(18, 18), Acceleration = V(0, 6, 0), Drag = 2,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 7) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			EmissionDirection = Enum.NormalId.Left, Color = ColorSequence.new(C(240, 245, 250)) })
	end
	return p
end

local function buildChamber(root)
	local ch = model(root, "Chamber")
	local Ch, D = L.Chamber, L.Door
	local zc = CENTER.Z
	local x0, x1 = Ch.Front, Ch.Back
	local xc, depth = (x0 + x1) / 2, x1 - x0
	P(ch, "ChamberFloor", V(depth, 0.3, D.Width), CF(xc, GROUND + 0.15, zc), STEEL_DARK, Enum.Material.DiamondPlate)
	P(ch, "ChamberCeiling", V(depth, 0.4, D.Width), CF(xc, GROUND + Ch.Height + 0.2, zc), STEEL_DARK, Enum.Material.Metal)
	P(ch, "ChamberBack", V(0.4, Ch.Height, D.Width), CF(x1 - 0.2, GROUND + Ch.Height / 2, zc), C(30, 32, 36), Enum.Material.Metal)
	for s = -1, 1, 2 do P(ch, "ChamberWall", V(depth, Ch.Height, 0.3), CF(xc, GROUND + Ch.Height / 2, zc + s * (D.Width / 2 - 0.15)), C(34, 36, 40), Enum.Material.Metal) end
	-- red danger strips and a dim red light
	for s = -1, 1, 2 do
		P(ch, "ChamberStrip", V(depth - 1, 0.25, 0.1), CF(xc, GROUND + Ch.Height - 1.2, zc + s * (D.Width / 2 - 0.35)), RED, Enum.Material.Neon, { CastShadow = false })
	end
	local lamp = P(ch, "ChamberLamp", V(1, 0.2, 1), CF(xc, GROUND + Ch.Height - 0.1, zc), RED, Enum.Material.Neon, { CastShadow = false })
	light(lamp, "PointLight", { Name = "ChamberLight", Color = RED, Range = 14, Brightness = 1.4, Shadows = false })
	for i = 0, 2 do P(ch, "Rail", V(depth - 0.6, 0.15, 0.25), CF(xc, GROUND + 0.38, zc - 2 + i * 2), STEEL, Enum.Material.Metal) end
	return ch
end

local function buildArm(root)
	local arm = model(root, "MutationArm")
	local A = L.Arm
	local yellow, dark = C(255, 190, 20), C(40, 42, 48)
	cylY(arm, "Mount", CF(A.Base + V(0, 1.4, 0)), 0.6, 2.8, dark, Enum.Material.Metal)
	P(arm, "Turret", V(2.2, 1.4, 2.2), CF(A.Base + V(0, 0.9, 0)), dark, Enum.Material.Metal)
	ball(arm, "Shoulder", 1.7, CF(A.Base), dark, Enum.Material.Metal)
	P(arm, "UpperArm", V(1.15, A.Upper, 1.15), CF(A.Base), yellow, Enum.Material.Metal)
	P(arm, "UpperPiston", V(0.35, A.Upper * 0.8, 0.35), CF(A.Base), C(200, 205, 214), Enum.Material.Metal)
	ball(arm, "Elbow", 1.4, CF(A.Base), dark, Enum.Material.Metal)
	P(arm, "ForeArm", V(0.95, A.Fore, 0.95), CF(A.Base), yellow, Enum.Material.Metal)
	P(arm, "ForePiston", V(0.3, A.Fore * 0.8, 0.3), CF(A.Base), C(200, 205, 214), Enum.Material.Metal)
	ball(arm, "Wrist", 1.1, CF(A.Base), dark, Enum.Material.Metal)
	P(arm, "Palm", V(1.6, 0.6, 1.6), CF(A.Base), dark, Enum.Material.DiamondPlate)
	local eye = ball(arm, "ArmEye", 0.45, CF(A.Base), RED, Enum.Material.Neon, { CastShadow = false })
	for i = 1, 3 do
		P(arm, "Finger" .. i .. "A", V(0.32, 1.2, 0.32), CF(A.Base), STEEL, Enum.Material.Metal)
		P(arm, "Finger" .. i .. "B", V(0.26, 1.0, 0.26), CF(A.Base), C(220, 224, 230), Enum.Material.Metal)
	end
	L.PoseArm(arm, A.Rest, 0.2)
	-- the eye follows the palm
	local palm = arm:FindFirstChild("Palm")
	eye.CFrame = palm.CFrame * CF(-0.9, 0, 0)
	return arm
end

local function buildPad(root)
	local pad = model(root, "LoadingPad")
	local c = L.Pad.Center
	local R = L.Pad.Radius
	cylY(pad, "PadBase", CF(c + V(0, 0.15, 0)), 0.3, R * 2 + 0.6, STEEL_DARK, Enum.Material.Metal)
	local top = cylY(pad, "PadTop", CF(c + V(0, 0.32, 0)), 0.06, R * 2 - 0.6, C(70, 76, 84), Enum.Material.DiamondPlate)
	local n = 24
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		P(pad, "PadStripe", V(2 * R * math.sin(math.pi / n) * 1.05, 0.08, 0.55), CF(c + V(math.cos(a) * (R - 0.05), 0.33, math.sin(a) * (R - 0.05))) * ANG(0, -a + math.pi / 2, 0), i % 2 == 0 and YELLOW or BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
	end
	local glow = model(pad, "PadPaw")
	local base = CF(c + V(0, 0.37, 0)) * ANG(rad(-90), 0, 0) -- XY plane lying flat, -Z up
	blob(glow, "PawPad", V(1.8, 1.4, 0.12), base * CF(0.3, 0, 0) * ANG(0, 0, rad(90)), TOXIC, Enum.Material.Neon, { CastShadow = false })
	for i, t in ipairs({ { -1.05, 0.55 }, { -0.4, 1.05 }, { 0.4, 1.05 }, { 1.05, 0.55 } }) do
		blob(glow, "PawToe", V(0.62, 0.78, 0.12), base * CF(-t[2] - 0.2, t[1], 0), TOXIC, Enum.Material.Neon, { CastShadow = false })
	end
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		ball(pad, "PadLight", 0.4, CF(c + V(math.cos(a) * (R + 0.1), 0.4, math.sin(a) * (R + 0.1))), TOXIC, Enum.Material.Neon, { CastShadow = false })
	end
	top:SetAttribute("PadCenter", true)
	return pad
end

local function screenGui(part, name, face, ppm)
	local g = gui(part, name, face, ppm)
	g.MaxDistance = 120
	local bg = frame(g, "Bg", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), C(8, 18, 14))
	local grad = Instance.new("UIGradient"); grad.Color = ColorSequence.new(C(14, 40, 26), C(4, 10, 8)); grad.Rotation = 90; grad.Parent = bg
	stroke(bg, C(40, 90, 60), 4)
	return g, bg
end

local function buildConsole(root)
	local con = model(root, "Console")
	local cc = L.Console
	local x, z = cc.Center.X, cc.Center.Z
	local w, d = cc.Width, cc.Depth
	local deskTop = GROUND + cc.DeskTop
	local body = C(52, 58, 66)
	solid(P(con, "Desk", V(d, cc.DeskTop - 0.6, w), CF(x, GROUND + (cc.DeskTop - 0.6) / 2, z), body, Enum.Material.Metal))
	P(con, "DeskKick", V(d + 0.2, 0.5, w + 0.2), CF(x, GROUND + 0.25, z), STEEL_DARK, Enum.Material.Metal)
	-- the sloped control panel, tilted towards the operator (west)
	local slope = CF(x - 0.2, deskTop - 0.2, z) * ANG(0, 0, rad(22))
	local panel = P(con, "Panel", V(d + 0.4, 0.4, w + 0.2), slope, C(36, 40, 46), Enum.Material.Metal)
	local top = slope * CF(0, 0.22, 0)
	-- big START button under a hinged guard
	local btnCF = top * CF(-0.6, 0, 0)
	cylY(con, "StartRing", btnCF * CF(0, 0.05, 0), 0.15, 1.9, YELLOW, Enum.Material.SmoothPlastic)
	cylY(con, "StartButton", btnCF * CF(0, 0.32, 0), 0.5, 1.35, RED, Enum.Material.Neon, { CastShadow = false })
	local guard = P(con, "StartGuard", V(1.9, 0.12, 1.9), btnCF * CF(0, 0.75, 0), C(255, 214, 40), Enum.Material.Glass, { Transparency = 0.45 })
	guard:SetAttribute("Hinge", btnCF * CF(0.95, 0.75, 0))
	-- rows of small keys
	local keyColors = { C(80, 255, 120), C(255, 200, 40), C(80, 180, 255), C(255, 80, 80), C(220, 120, 255), C(255, 255, 255) }
	local idx = 0
	for row = 0, 2 do
		for col = 0, 5 do
			idx += 1
			local zOff = (col - 2.5) * 0.62 + (col >= 3 and 2.9 or -2.9)
			local k = P(con, "Key" .. idx, V(0.42, 0.18, 0.42), top * CF(0.75 - row * 0.62, 0.1, zOff * 0.62), keyColors[(idx - 1) % #keyColors + 1], Enum.Material.Neon, { CastShadow = false })
			k:SetAttribute("BaseColor", k.Color)
		end
	end
	-- levers and gauges
	for i = 1, 4 do
		local lz = z + (i - 2.5) * 0.8
		local base = top * CF(0.9, 0.1, (i - 2.5) * 0.8)
		P(con, "LeverSlot", V(0.9, 0.06, 0.18), base, BLACK, Enum.Material.Metal)
		local lever = P(con, "Lever" .. i, V(0.12, 1.0, 0.12), base * CF(0, 0.5, 0), C(200, 204, 210), Enum.Material.Metal)
		ball(con, "LeverKnob" .. i, 0.32, base * CF(0, 1.02, 0), i % 2 == 0 and RED or BLACK, Enum.Material.SmoothPlastic)
		lever:SetAttribute("Base", base)
	end
	for i = 1, 2 do
		local gcf = top * CF(-0.15, 0.08, (i == 1 and -1 or 1) * 3.9)
		cyl(con, "Gauge" .. i, gcf * ANG(0, 0, rad(90)), 0.12, 1.3, C(240, 240, 232), Enum.Material.SmoothPlastic)
		local needle = P(con, "Needle" .. i, V(0.06, 0.05, 0.55), gcf * CF(0, 0.08, 0.2), RED, Enum.Material.Neon, { CastShadow = false })
		needle:SetAttribute("Base", gcf * CF(0, 0.08, 0))
	end
	local led = P(con, "LedStrip", V(0.12, 0.12, w - 0.6), top * CF(1.35, 0.06, 0), TOXIC, Enum.Material.Neon, { CastShadow = false })
	-- the main screen on two posts above the desk (above the operator's eye line)
	for s = -1, 1, 2 do P(con, "ScreenPost", V(0.35, 5.6, 0.35), CF(x + 1.3, GROUND + cc.DeskTop + 2.6, z + s * 3.4), STEEL_DARK, Enum.Material.Metal) end
	local screenCF = CF(x + 1.25, GROUND + cc.DeskTop + 4.6, z) * ANG(0, 0, rad(-12))
	P(con, "ScreenFrame", V(0.5, 3.9, 7.4), screenCF * CF(0.1, 0, 0), STEEL_DARK, Enum.Material.Metal)
	local main = P(con, "MainScreen", V(0.12, 3.4, 6.8), screenCF * CF(-0.2, 0, 0), C(10, 20, 16), Enum.Material.Glass, { CastShadow = false })
	local g, bg = screenGui(main, "MainScreenGui", Enum.NormalId.Left, 70)
	label(bg, "Title", "☢ NUCLEAR MUTATION REACTOR", UDim2.fromScale(0.03, 0.04), UDim2.fromScale(0.94, 0.16), TOXIC)
	label(bg, "Reel", "READY", UDim2.fromScale(0.05, 0.26), UDim2.fromScale(0.9, 0.38), C(220, 255, 230), { TextStrokeTransparency = 0.5 })
	label(bg, "Status", "PLACE A DOG ON THE PAD", UDim2.fromScale(0.05, 0.68), UDim2.fromScale(0.9, 0.12), C(160, 220, 180))
	local bars = frame(bg, "Bars", UDim2.fromScale(0.06, 0.84), UDim2.fromScale(0.88, 0.12), C(0, 0, 0), { BackgroundTransparency = 1 })
	for i = 1, 16 do frame(bars, "Bar" .. i, UDim2.fromScale((i - 1) / 16 + 0.005, 0.5), UDim2.fromScale(1 / 16 - 0.01, 0.5), TOXIC) end
	-- beacons on the screen frame
	for s = -1, 1, 2 do
		local dome = ball(con, "Beacon", 0.8, screenCF * CF(0.1, 2.25, s * 3.2), RED, Enum.Material.Neon, { Transparency = 0.15, CastShadow = false })
		light(dome, "SpotLight", { Name = "BeaconLight", Color = RED, Range = 28, Angle = 45, Brightness = 0, Face = Enum.NormalId.Front, Shadows = false })
	end
	-- side wings with their screens
	for s = -1, 1, 2 do
		local wz = z + s * (w / 2 + 1.3)
		solid(P(con, "Wing", V(d, cc.DeskTop + 1.2, 2.4), CF(x + 0.2, GROUND + (cc.DeskTop + 1.2) / 2, wz), body, Enum.Material.Metal))
		local scr = P(con, s < 0 and "LeftScreen" or "RightScreen", V(0.12, 2, 2.1), CF(x - 1.38, GROUND + cc.DeskTop + 0.1, wz) * ANG(0, 0, rad(18)), C(10, 20, 16), Enum.Material.Glass, { CastShadow = false })
		local _, sbg = screenGui(scr, "ScreenGui", Enum.NormalId.Left, 80)
		if s < 0 then
			label(sbg, "Title", "RADIATION", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.18), YELLOW)
			local meter = frame(sbg, "Meter", UDim2.fromScale(0.1, 0.3), UDim2.fromScale(0.8, 0.5), C(30, 30, 30))
			frame(meter, "Fill", UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1), TOXIC)
			label(sbg, "Value", "0.3 Sv", UDim2.fromScale(0.05, 0.82), UDim2.fromScale(0.9, 0.16), C(200, 255, 210))
		else
			label(sbg, "Title", "DNA SCAN", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.18), C(120, 220, 255))
			local helix = frame(sbg, "Helix", UDim2.fromScale(0.05, 0.25), UDim2.fromScale(0.9, 0.7), C(0, 0, 0), { BackgroundTransparency = 1 })
			for i = 1, 10 do
				frame(helix, "DotA" .. i, UDim2.fromScale((i - 1) / 10, 0.2), UDim2.fromScale(0.07, 0.12), C(120, 220, 255))
				frame(helix, "DotB" .. i, UDim2.fromScale((i - 1) / 10, 0.7), UDim2.fromScale(0.07, 0.12), C(255, 120, 220))
			end
		end
		-- blinking lamps on the wing tops
		for k = 0, 3 do
			local lamp = ball(con, "WingLamp", 0.32, CF(x + 0.2 - 1 + k * 0.62, GROUND + cc.DeskTop + 1.35, wz), keyColors[(k + (s > 0 and 2 or 0)) % #keyColors + 1], Enum.Material.Neon, { CastShadow = false })
			lamp:SetAttribute("BaseColor", lamp.Color)
		end
	end
	-- the operator's mat
	P(con, "OperatorMat", V(3, 0.08, 5), CF(cc.Operator + V(0, 0.04, 0)), C(30, 30, 34), Enum.Material.Rubber, { CastShadow = false })
	return con
end

local function barrel(parent, cf, r, toppled, leaking)
	local b = model(parent, "WasteBarrel")
	local yellowish = toppled and C(214, 176, 30) or YELLOW:Lerp(C(150, 130, 60), r(0, 0.35))
	local h, d = 2.9, 2.1
	local base = toppled and (cf * CF(0, d / 2, 0) * ANG(0, 0, rad(90)) * CF(0, -0.0, 0)) or (cf * CF(0, h / 2, 0))
	solid(cylY(b, "Drum", base, h, d, yellowish, Enum.Material.Metal))
	for _, y in ipairs({ -0.75, 0.75 }) do cylY(b, "Hoop", base * CF(0, y, 0), 0.16, d + 0.08, BLACK, Enum.Material.Metal) end
	cylY(b, "Lid", base * CF(0, h / 2 + 0.03, 0), 0.08, d - 0.25, C(90, 80, 40), Enum.Material.Metal)
	local sticker = P(b, "Sticker", V(1.0, 1.0, 0.05), base * CF(0, 0, -d / 2 - 0.02), YELLOW, Enum.Material.SmoothPlastic, { CastShadow = false })
	local sg = gui(sticker, "Trefoil", Enum.NormalId.Front, 60)
	sg.MaxDistance = 90
	label(sg, "Icon", "☢", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BLACK)
	if leaking then
		for i = 1, 3 do
			blob(b, "Drip", V(0.25, 0.6, 0.25), base * CF(r(-0.6, 0.6), h / 2 - 0.4 - i * 0.35, -d / 2 - 0.05), TOXIC, Enum.Material.Neon, { CastShadow = false })
		end
	end
	return b
end

local function buildBarrels(root)
	local folder = model(root, "WasteBarrels")
	for _, c in ipairs(L.Barrels) do
		local r = rng(c[4])
		local cluster = model(folder, "Cluster")
		for i = 1, c[3] do
			local a = (i / c[3]) * math.pi * 2 + r(-0.3, 0.3)
			local rr = i == 1 and 0 or (1.9 + r(0, 0.6))
			local pos = V(c[1] + math.cos(a) * rr, GROUND, c[2] + math.sin(a) * rr)
			barrel(cluster, CF(pos) * ANG(0, r(0, 6.28), 0), r, false, i % 3 == 0)
		end
		-- a glowing puddle under every cluster
		cylY(cluster, "Puddle", CF(c[1] + 1.2, GROUND + 0.04, c[2] + 0.6), 0.06, 4.4 + r(0, 2), TOXIC, Enum.Material.Neon, { CastShadow = false, Transparency = 0.25 })
	end
	-- the toppled, leaking barrel by the pad
	local spill = model(folder, "Spill")
	barrel(spill, CF(L.Spill.Barrel) * ANG(0, rad(35), 0), rng(99), true, true)
	local puddle = cylY(spill, "SpillPuddle", CF(L.Spill.Puddle), 0.06, 6.5, TOXIC, Enum.Material.Neon, { CastShadow = false, Transparency = 0.2 })
	light(puddle, "PointLight", { Name = "SpillLight", Color = TOXIC, Range = 10, Brightness = 1.2, Shadows = false })
	emitter(puddle, "Bubbles", { Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 4, Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(25, 25), Size = NumberSequence.new(0.35, 0), Color = ColorSequence.new(TOXIC), LightEmission = 1, EmissionDirection = Enum.NormalId.Right })
end

local function buildBarriers(root)
	local f = model(root, "Barriers")
	local Pz = L.Plaza
	local function run(a, b, gapFrom, gapTo)
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 6))
		for i = 0, n - 1 do
			local p0 = a + d * (i / n)
			local p1 = a + d * ((i + 1) / n)
			local mid = (p0 + p1) / 2
			local skip = gapFrom and (mid.Z > gapFrom and mid.Z < gapTo)
			if not skip then
				local look = (p1 - p0).Unit
				local cf = CFrame.lookAt(mid + V(0, GROUND + 0.6, 0), mid + V(0, GROUND + 0.6, 0) + look)
				solid(P(f, "Barrier", V(1, 1.2, (p1 - p0).Magnitude - 0.2), cf, CONCRETE, Enum.Material.Concrete))
				for k = 0, 3 do
					P(f, "BarrierStripe", V(1.02, 0.35, 1.2), cf * CF(0, 0.2, -((p1 - p0).Magnitude / 2) + 0.8 + k * ((p1 - p0).Magnitude - 1.6) / 3) * ANG(rad(35), 0, 0), k % 2 == 0 and YELLOW or BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
				end
			end
		end
	end
	run(V(Pz.X0 + 0.5, 0, Pz.Z0 + 0.5), V(Pz.X1 - 0.5, 0, Pz.Z0 + 0.5))
	run(V(Pz.X1 - 0.5, 0, Pz.Z0 + 0.5), V(Pz.X1 - 0.5, 0, Pz.Z1 - 0.5))
	run(V(Pz.X1 - 0.5, 0, Pz.Z1 - 0.5), V(Pz.X0 + 0.5, 0, Pz.Z1 - 0.5))
	run(V(Pz.X0 + 0.5, 0, Pz.Z1 - 0.5), V(Pz.X0 + 0.5, 0, Pz.Z0 + 0.5), 466, 488)
	-- DANGER signs at the entrance
	for s = -1, 1, 2 do
		local base = CF(Pz.X0 + 1.5, GROUND, 477 + s * 12)
		P(f, "SignPost", V(0.3, 6, 0.3), base * CF(0, 3, 0), STEEL_DARK, Enum.Material.Metal)
		local board = P(f, "DangerSign", V(0.25, 3.2, 4.6), base * CF(-0.2, 5.2, 0), BLACK, Enum.Material.Metal)
		local g = gui(board, "DangerGui", Enum.NormalId.Left, 50)
		g.MaxDistance = 150
		local bg = frame(g, "Bg", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), YELLOW)
		stroke(bg, BLACK, 10)
		label(bg, "Icon", "☢", UDim2.fromScale(0.3, 0.04), UDim2.fromScale(0.4, 0.46), BLACK)
		label(bg, "Title", "DANGER", UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.88, 0.24), RED)
		label(bg, "Sub", "RADIATION ZONE", UDim2.fromScale(0.06, 0.74), UDim2.fromScale(0.88, 0.18), BLACK)
		local back = board:Clone(); back.Parent = f
		for _, gg in ipairs(back:GetChildren()) do if gg:IsA("SurfaceGui") then gg.Face = Enum.NormalId.Right end end
	end
end

local function buildPipes(root)
	local f = model(root, "Pipes")
	for _, a in ipairs({ rad(25), rad(-25), rad(180 + 55), rad(180 - 55) }) do
		local out = V(math.cos(a), 0, math.sin(a))
		local start = CENTER + out * (L.Tower.BaseRadius - 1) + V(0, 4.5, 0)
		local bend = CENTER + out * (L.Tower.BaseRadius + 12) + V(0, 4.5, 0)
		local down = bend - V(0, 4.6, 0)
		local p1 = bar(f, "Pipe", start, bend, 2.2, C(96, 120, 104), Enum.Material.Metal)
		solid(p1)
		bar(f, "Pipe", bend, down, 2.2, C(96, 120, 104), Enum.Material.Metal)
		ball(f, "PipeElbow", 2.4, CF(bend), C(86, 108, 94), Enum.Material.Metal)
		for k = 1, 3 do
			local q = start + (bend - start) * (k / 4)
			local look = (bend - start).Unit
			P(f, "Flange", V(2.8, 2.8, 0.35), CFrame.lookAt(q, q + look), C(70, 74, 80), Enum.Material.Metal)
		end
		local valveAt = start + (bend - start) * 0.5 + V(0, 1.7, 0)
		bar(f, "ValveStem", valveAt - V(0, 0.6, 0), valveAt + V(0, 0.4, 0), 0.25, STEEL_DARK, Enum.Material.Metal)
		cylY(f, "ValveWheel", CF(valveAt + V(0, 0.45, 0)), 0.2, 1.8, RED, Enum.Material.Metal)
		local vent = P(f, "PipeVent", V(0.5, 0.5, 0.5), CF(valveAt + V(0, 0.9, 0)), STEEL_DARK, Enum.Material.Metal, { Transparency = 1 })
		emitter(vent, "Hiss", { Texture = "rbxasset://textures/particles/smoke_main.dds", Rate = 1.2, Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(12, 12), Size = NumberSequence.new(0.8, 3.5), Transparency = NumberSequence.new(0.5, 1), Color = ColorSequence.new(C(245, 248, 250)), EmissionDirection = Enum.NormalId.Top })
	end
end

local function buildLights(root)
	local f = model(root, "Floodlights")
	local Pz = L.Plaza
	for _, c in ipairs({ { Pz.X0 + 3, Pz.Z0 + 3 }, { Pz.X0 + 3, Pz.Z1 - 3 }, { Pz.X1 - 3, Pz.Z0 + 3 }, { Pz.X1 - 3, Pz.Z1 - 3 } }) do
		local base = V(c[1], GROUND, c[2])
		solid(P(f, "LightPole", V(0.6, 16, 0.6), CF(base + V(0, 8, 0)), STEEL_DARK, Enum.Material.Metal))
		local aim = CENTER + V(0, 40, 0)
		local head = P(f, "Floodlight", V(2.4, 1.4, 0.8), CFrame.lookAt(base + V(0, 16.4, 0), aim), C(255, 250, 230), Enum.Material.Neon, { CastShadow = false })
		light(head, "SpotLight", { Color = C(255, 245, 225), Range = 60, Angle = 38, Brightness = 2.2, Face = Enum.NormalId.Front, Shadows = false })
	end
end

------------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------------
function B.Build(lab)
	local old = lab:FindFirstChild(L.Name)
	if old then old:Destroy() end
	count = 0
	local root = Instance.new("Model")
	root.Name = L.Name
	root:SetAttribute("Version", L.Version)
	buildGround(root)
	buildTower(root)
	buildEmblem(root)
	buildPortal(root)
	buildChamber(root)
	buildArm(root)
	buildPad(root)
	buildConsole(root)
	buildBarrels(root)
	buildBarriers(root)
	buildPipes(root)
	buildLights(root)
	root:SetAttribute("Parts", count)
	root.Parent = lab
	return root
end

return B
