-- MineStructures: Forge recipes of the mine's fixed structures, in YARD DESIGN coordinates
-- (see MineLayout). Callers place a built model with Structures.Place(model, layout).
--   Headframe()   server, every yard: steel headframe over the shaft, big spoked wheel, cables,
--                 hoist drum, collar, gate, the depth sign (SurfaceGui "DepthSign") and the
--                 elevator prompt anchor (Attachment "PromptAnchor" on part "Gate")
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
local S = {}

local STEEL = C(150, 58, 42) -- headframe paint (deep rust red)
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
-- Headframe (server)
------------------------------------------------------------------------------------------------
-- Built around the shaft centre on the ground; local +x = design +x' (towards the hoist),
-- local +z = design +z (towards the yard centre).
function S.Headframe(): Model
	local b = Forge.Builder("MineHeadframe")
	local s = Layout.Shaft
	local O = CF(s.X, Layout.GroundY, s.Z)
	local h = s.Half -- 4
	-- COLLAR: concrete curb around the 8 x 8 opening, steel corner plates.
	local cw, ch = 1.6, 0.8
	for i, row in { { 0, -(h + cw / 2), 2 * h + 2 * cw, cw }, { 0, h + cw / 2, 2 * h + 2 * cw, cw }, { -(h + cw / 2), 0, cw, 2 * h }, { h + cw / 2, 0, cw, 2 * h } } do
		collide(b:Box(V(row[3], ch, row[4]), O * CF(row[1], ch / 2, row[2]), CONCRETE, "Concrete", { Name = "Collar" .. i }))
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:Box(V(cw + 0.1, 0.12, cw + 0.1), O * CF(x * (h + cw / 2), ch + 0.06, z * (h + cw / 2)), IRON, "DiamondPlate", { Name = "CollarPlate" })
		end
	end
	-- Edge of the opening: a dark band reads as depth from above.
	b:Box(V(2 * h, 0.05, 0.25), O * CF(0, ch + 0.03, h - 0.12), SAFETY, "SmoothPlastic", { Name = "EdgeStripe" })
	b:Box(V(2 * h, 0.05, 0.25), O * CF(0, ch + 0.03, -h + 0.12), SAFETY, "SmoothPlastic", { Name = "EdgeStripe" })

	-- TOWER: four legs tapering from the collar corners to the head platform.
	local top = 17
	local footR, headR = h + 0.8, 2.6
	local function leg(x, z, y)
		local f = (y - ch) / (top - ch)
		local r = footR + (headR - footR) * f
		return O * V(x * r, y, z * r)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:Beam(leg(x, z, ch), leg(x, z, top), 0.7, STEEL, "Metal", { Name = "Leg" })
			b:Box(V(1.3, 0.3, 1.3), CF(leg(x, z, ch) + V(0, 0.15, 0)), IRON, "Metal", { Name = "LegShoe" })
		end
	end
	-- Girts at two heights on every face, X braces (the gate face -x is open below the first girt).
	local girts = { ch, 6.2, 11.6, top }
	for gi = 2, 3 do
		local y = girts[gi]
		for _, pair in { { { -1, -1 }, { 1, -1 } }, { { -1, 1 }, { 1, 1 } }, { { -1, -1 }, { -1, 1 } }, { { 1, -1 }, { 1, 1 } } } do
			b:Beam(leg(pair[1][1], pair[1][2], y), leg(pair[2][1], pair[2][2], y), 0.45, STEEL_DARK, "Metal", { Name = "Girt" })
		end
	end
	for gi = 1, 3 do
		local y0, y1 = girts[gi], girts[gi + 1]
		for _, face in { { { -1, -1 }, { 1, -1 } }, { { -1, 1 }, { 1, 1 } }, { { 1, -1 }, { 1, 1 } }, { { -1, -1 }, { -1, 1 } } } do
			local gateFace = face[1][1] == -1 and face[2][1] == -1
			if not (gateFace and gi == 1) then
				local a0, a1 = face[1], face[2]
				b:Beam(leg(a0[1], a0[2], y0), leg(a1[1], a1[2], y1), 0.3, STEEL_DARK, "Metal", { Name = "Brace" })
				if gi ~= 2 or not gateFace then
					b:Beam(leg(a1[1], a1[2], y0), leg(a0[1], a0[2], y1), 0.3, STEEL_DARK, "Metal", { Name = "Brace" })
				end
			end
		end
	end

	-- HEAD PLATFORM: steel deck reaching out over the backstays, yellow railing.
	local deckX0, deckX1 = -3.2, 5.8
	local deckCF = O * CF((deckX0 + deckX1) / 2, top + 0.2, 0)
	b:Box(V(deckX1 - deckX0, 0.4, 6.2), deckCF, IRON, "DiamondPlate", { Name = "HeadDeck" })
	for _, z in { -3, 3 } do
		b:Box(V(deckX1 - deckX0, 0.2, 0.2), O * CF((deckX0 + deckX1) / 2, top + 1.6, z), SAFETY, "Metal", { Name = "Rail" })
	end
	b:Box(V(0.2, 0.2, 6.2), O * CF(deckX0, top + 1.6, 0), SAFETY, "Metal", { Name = "Rail" })
	for _, x in { deckX0, deckX1 } do
		for _, z in { -3, 3 } do
			b:Box(V(0.2, 1.6, 0.2), O * CF(x, top + 1.0, z), SAFETY, "Metal", { Name = "RailPost" })
		end
	end
	-- Warning beacon.
	b:Ball(0.7, O * CF(deckX0 + 0.4, top + 2.1, -3), C(255, 70, 40), "Neon", { Name = "Beacon" })

	-- HEAD SHEAVE: the big spoked wheel, its rim tangent over the shaft centre.
	local R = 3.4
	local wheelC = O * CF(R, top + 0.4 + R + 0.5, 0)
	for _, z in { -1.1, 1.1 } do
		b:Box(V(1.4, R + 0.6, 0.5), wheelC * CF(0, -(R + 0.6) / 2, z), STEEL_DARK, "Metal", { Name = "Bearing" })
	end
	local wheel = b:Folder("Wheel")
	b:Ring(wheelC * ANG(math.pi / 2, 0, 0), R, 0.5, IRON, "Metal", 18, { Name = "Rim" })
	b:Ring(wheelC * ANG(math.pi / 2, 0, 0), R - 0.55, 0.22, SAFETY, "Metal", 14, { Name = "Groove" })
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi
		b:Rod(wheelC.Position, (wheelC * CF(math.cos(a) * (R - 0.3), math.sin(a) * (R - 0.3), 0)).Position, 0.24, IRON, "Metal", { Name = "Spoke" })
	end
	b:CylZ(1.0, 1.1, wheelC, SAFETY, "Metal", { Name = "Hub" })
	b:CylZ(2.6, 0.35, wheelC, IRON, "Metal", { Name = "Axle" })
	b:Into(b.Model)
	wheel:SetAttribute("SpinAxisZ", true)

	-- BACKSTAYS from the head down to the ground towards the hoist (+x).
	local stayFoot = 11.2
	for _, z in { -2.8, 2.8 } do
		b:Beam(O * V(deckX1 - 0.3, top, z), O * V(stayFoot, ch, z * 1.25), 0.6, STEEL, "Metal", { Name = "Backstay" })
		collide(b:Box(V(1.6, 0.8, 1.6), O * CF(stayFoot, 0.4, z * 1.25), CONCRETE, "Concrete", { Name = "StayFooting" }))
	end
	b:Beam(O * V(8.4, 6.2, -3.3), O * V(8.4, 6.2, 3.3), 0.4, STEEL_DARK, "Metal", { Name = "StayTie" })

	-- HOIST: winding drum on a concrete base, motor housing.
	local hoist = O * CF(8.4, 0, 0)
	collide(b:Box(V(3.6, 0.7, 5.6), hoist * CF(0, 0.35, 0), CONCRETE, "Concrete", { Name = "HoistBase" }))
	for _, z in { -2.2, 2.2 } do
		b:Box(V(1.6, 2.1, 0.5), hoist * CF(0, 1.75, z), IRON, "Metal", { Name = "DrumStand" })
	end
	b:CylZ(4.0, 2.4, hoist * CF(0, 2.5, 0), C(60, 60, 64), "Metal", { Name = "Drum" })
	for _, z in { -1.9, 1.9 } do
		b:CylZ(0.25, 3.0, hoist * CF(0, 2.5, z), SAFETY, "Metal", { Name = "DrumFlange" })
	end
	collide(b:Box(V(1.8, 1.7, 1.6), hoist * CF(1.7, 1.55, -1.7), C(66, 108, 74), "Metal", { Name = "Motor" }))

	-- CABLES: wheel -> drum, and the hoist rope down the shaft centre to the collar.
	local rimTop = wheelC * CF(math.cos(math.rad(35)) * R, math.sin(math.rad(35)) * R, 0)
	b:Rod(rimTop.Position, (hoist * CF(-0.2, 3.65, 0)).Position, 0.18, ROPE, "Metal", { Name = "Cable" })
	b:Rod((wheelC * CF(-R, 0, 0)).Position, (O * CF(0, ch + 1.2, 0)).Position, 0.18, ROPE, "Metal", { Name = "HoistRope" })

	-- GATE on the walkway side (-x): posts, striped bar, call panel with a lamp.
	local gateX = -(h + cw)
	for _, z in { -h, h } do
		collide(b:Box(V(0.5, 3.6, 0.5), O * CF(gateX - 0.3, ch + 1.8, z), SAFETY, "Metal", { Name = "GatePost" }))
	end
	local gate = b:Box(V(0.3, 0.35, 2 * h), O * CF(gateX - 0.3, ch + 3.3, 0), C(30, 30, 30), "Metal", { Name = "Gate" })
	for i = -3, 3 do
		b:Box(V(0.32, 0.37, 0.55), O * CF(gateX - 0.3, ch + 3.3, i * 1.1), SAFETY, "SmoothPlastic", { Name = "GateStripe" })
	end
	local panel = b:Box(V(0.3, 1.4, 1.0), O * CF(gateX - 0.6, ch + 1.6, -h - 0.9), C(52, 56, 62), "Metal", { Name = "CallPanel" })
	b:Box(V(0.12, 0.35, 0.35), panel.CFrame * CF(-0.18, 0.25, 0), C(80, 255, 120), "Neon", { Name = "CallLamp" })
	b:Box(V(0.5, ch + 0.9, 0.5), O * CF(gateX - 0.6, (ch + 0.9) / 2, -h - 0.9), IRON, "Metal", { Name = "PanelPost" })
	local promptAnchor = Instance.new("Attachment")
	promptAnchor.Name = "PromptAnchor"
	promptAnchor.Position = V(-0.6, -1.2, 0)
	promptAnchor.Parent = gate

	-- SAFETY RAIL round the other three sides of the collar.
	local rr = h + cw + 0.4
	for _, row in { { 0, -rr, 2 * rr, 0.18 }, { 0, rr, 2 * rr, 0.18 }, { rr, 0, 0.18, 2 * rr } } do
		b:Box(V(row[3], 0.18, row[4]), O * CF(row[1], ch + 2.2, row[2]), SAFETY, "Metal", { Name = "CollarRail" })
	end
	for _, p in { { -rr, -rr }, { rr, -rr }, { -rr, rr }, { rr, rr } } do
		b:Box(V(0.22, 2.2, 0.22), O * CF(p[1], ch + 1.1, p[2]), SAFETY, "Metal", { Name = "CollarRailPost" })
	end

	-- FLOODLIGHTS on the upper girt, aimed into the shaft and at the collar.
	for _, z in { -1, 1 } do
		local lamp = b:Box(V(0.9, 0.6, 0.9), CF(leg(-1, z, 11.6) + V(0.6, -0.5, -z * 0.6)), C(255, 236, 190), "Neon", { Name = "Floodlight", CastShadow = false })
		local light = b:Light(lamp, C(255, 226, 170), 22, 1.6, "Spot")
		;(light :: SpotLight).Face = Enum.NormalId.Bottom
		;(light :: SpotLight).Angle = 80
	end

	-- DEPTH SIGN on the +z face (towards the yard), between the legs.
	local signY = 8.6
	local sign = b:Box(V(5.2, 2.9, 0.3), O * CF(0, signY, footR - (footR - headR) * (signY - ch) / (top - ch) + 0.35), C(36, 30, 26), "Metal", { Name = "DepthSign" })
	b:Box(V(5.6, 0.3, 0.45), sign.CFrame * CF(0, 1.6, 0), SAFETY, "Metal", { Name = "SignTrim" })
	b:Box(V(5.6, 0.3, 0.45), sign.CFrame * CF(0, -1.6, 0), SAFETY, "Metal", { Name = "SignTrim" })
	-- The sign faces +z: its Back face (+Z local) points at the yard.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DepthSignGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.1
	gui.MaxDistance = 140
	gui.Parent = sign
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
	local function label(name, text, y, h2, color, font)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.92, h2)
		t.Position = UDim2.fromScale(0.04, y)
		t.Font = font or Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.TextStrokeTransparency = 0.5
		t.Parent = bg
		return t
	end
	label("Caption", "DOGS DIG AT", 0.06, 0.2, C(255, 226, 170), Enum.Font.GothamBold)
	label("Layer", Themes[1].Title, 0.3, 0.42, Themes[1].Accent)
	label("Depth", Themes[1].Depth, 0.74, 0.2, C(230, 230, 236), Enum.Font.GothamBold)

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
		t.Font = i == 1 and Enum.Font.GothamBold or Enum.Font.GothamBlack
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
------------------------------------------------------------------------------------------------
function S.Cage(): Model
	local b = Forge.Builder("MineCage")
	local w, hgt = 6.8, 8.2
	local hw = w / 2
	collide(b:Box(V(w, 0.3, w), CF(0, -0.15, 0), IRON, "DiamondPlate", { Name = "CageFloor" }))
	b:Box(V(w, 0.3, w), CF(0, hgt, 0), STEEL_DARK, "Metal", { Name = "CageRoof" })
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:Box(V(0.35, hgt, 0.35), CF(x * (hw - 0.17), hgt / 2, z * (hw - 0.17)), SAFETY, "Metal", { Name = "CagePost" })
		end
	end
	-- Closed sides (+X, -Z): steel mesh; gate sides (-X, +Z): bars and a top rail.
	b:Box(V(0.1, hgt - 1, w - 0.4), CF(hw - 0.1, hgt / 2, 0), C(90, 96, 104), "DiamondPlate", { Name = "CageMesh", Transparency = 0.45 })
	b:Box(V(w - 0.4, hgt - 1, 0.1), CF(0, hgt / 2, -hw + 0.1), C(90, 96, 104), "DiamondPlate", { Name = "CageMesh", Transparency = 0.45 })
	for i = -2, 2 do
		b:Box(V(0.12, 3.2, 0.12), CF(-hw + 0.1, 1.6, i * 1.25), IRON, "Metal", { Name = "GateBar" })
		b:Box(V(0.12, 3.2, 0.12), CF(i * 1.25, 1.6, hw - 0.1), IRON, "Metal", { Name = "GateBar" })
	end
	b:Box(V(0.18, 0.18, w - 0.4), CF(-hw + 0.1, 3.2, 0), SAFETY, "Metal", { Name = "GateRail" })
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
