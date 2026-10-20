-- NIGHT OF THE BURIED MOON — Blood Moon presentation (StarterPlayerScripts.HalloweenClient.BloodMoonFX). WP10a.
-- * THE BURIED MOON: a client-built neon moon (core, craters, maria, rim glow, two halos, blood veins) in the direction of
--   Layout.Moon as seen from the gate, placed at a fixed distance from the camera along that direction (no parallax, little
--   fog depth: it reads like a real moon). Visible wherever the displayed sky is dark (Lighting.Weights().MoonVis; the
--   Lighting module hides the built-in moon by the same weight), biggest over the yard (W.Approach), grows to
--   Layout.Moon.BloodRadius and turns blood red with the Blood Moon alpha; slow pulse during ACTIVE (not ReducedMotion).
-- * Sky reddening: the Lighting module's BLOOD_MOON / BLOOD_SKY layers (outside the yard: a faint red tint only).
-- * Red embers + ash around the camera and a light red rain (High/Medium), budgeted by quality, in/near the yard.
-- * Lantern flicker: every HwLantern light flickers in Brightness only (WorldDetailQuality owns Enabled) while ACTIVE;
--   the original Brightness is kept as Light attribute HwBaseBrightness and restored exactly. FX.Folder attribute
--   HwBloodFlicker (0..1) tells AmbientFX to leave those lights alone meanwhile.
-- * Warning card "BLOOD MOON RISES IN 30s" (own ScreenGui DOGROTS_BloodMoonNotice, below the HUD strip, hidden while a menu
--   is open), last 10 s pulse + heartbeat; at the start: Bus Banner, thunder + lightning, the bell, BloodMoonRise; periodic
--   lightning while ACTIVE; at the end BloodMoonEnd + a toast. Late joiners get the state, never the set pieces.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local M = {}
M.MoonDistance = 230 -- studs from the camera (beyond the yard, above every building, shallow fog)
M.LightningEvery = { 20, 38 }

local C3 = Color3.fromRGB
local MOON = { Core = C3(232, 226, 206), Crater = C3(196, 188, 168), Mare = C3(176, 172, 160), Rim = C3(196, 210, 255),
	Halo = C3(150, 160, 230), Vein = C3(232, 226, 206) }
local BLOOD = { Core = C3(214, 44, 40), Crater = C3(120, 14, 22), Mare = C3(150, 22, 28), Rim = C3(255, 70, 52),
	Halo = C3(220, 30, 40), Vein = C3(110, 6, 16) }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function M.Start(ctx)
	local Shared, Layout, FX, Audio, Bus = ctx.Shared, ctx.Layout, ctx.FX, ctx.Audio, ctx.Bus
	if not Shared.Enabled() then
		return
	end
	local Config = ctx.Config
	local player = ctx.Player or Players.LocalPlayer
	local LightingMod = ctx.Modules and ctx.Modules.Lighting
	local alive = true
	local conns = {}
	local built = {}

	---------------------------------------------------------------------------------------------------------------
	-- the moon
	---------------------------------------------------------------------------------------------------------------
	local gate = Layout.Gate.Center + Vector3.new(0, 6, 0)
	local toMoon = Layout.Moon.Position - gate
	local DIR = toMoon.Unit
	local TAN = Layout.Moon.Radius / toMoon.Magnitude -- angular radius as seen from the gate
	local GROW = (Layout.Moon.BloodRadius or Layout.Moon.Radius * 1.6) / Layout.Moon.Radius
	local model = Instance.new("Model")
	model.Name = "HalloweenMoon"
	model.Parent = FX.Folder()
	table.insert(built, model)
	local parts = {} -- {Part, Kind, Offset (unit-radius local CFrame), Size (unit), BaseT}
	local function piece(kind: string, shape: Enum.PartType, size: Vector3, offset: CFrame, baseT: number)
		local p = FX.Part({ Class = "Part", Shape = shape, Size = size, Color = MOON[kind] or MOON.Core, Transparency = 1,
			Material = Enum.Material.Neon, Parent = model })
		p.Name = "Moon" .. kind
		table.insert(parts, { Part = p, Kind = kind, Offset = offset, Size = size, BaseT = baseT })
		return p
	end
	local FACE = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) -> local Z (toward the camera after lookAt)
	piece("Halo", Enum.PartType.Ball, Vector3.one * 3.7, CFrame.new(0, 0, .8), .95)
	piece("Halo", Enum.PartType.Ball, Vector3.one * 2.7, CFrame.new(0, 0, .4), .87)
	piece("Rim", Enum.PartType.Ball, Vector3.one * 2.09, CFrame.new(), .55)
	piece("Core", Enum.PartType.Ball, Vector3.one * 2, CFrame.new(), 0)
	local function onFace(x: number, y: number, d: number, kind: string, baseT: number)
		local z = -math.sqrt(math.max(0, 1 - x * x - y * y)) - .015
		piece(kind, Enum.PartType.Cylinder, Vector3.new(.03, d, d), CFrame.new(x, y, z) * FACE, baseT)
	end
	onFace(-.28, .22, .62, "Mare", .35)
	onFace(.25, -.3, .48, "Mare", .4)
	onFace(.12, .42, .26, "Crater", 0)
	onFace(-.46, -.18, .2, "Crater", 0)
	onFace(.44, .12, .16, "Crater", .1)
	onFace(-.08, -.52, .14, "Crater", .1)
	onFace(.02, .05, .1, "Crater", .15)
	onFace(-.6, .3, .1, "Crater", .15)
	-- blood veins (thin strips across the face, only during the Blood Moon)
	local function vein(x: number, y: number, len: number, rot: number)
		local z = -math.sqrt(math.max(0, 1 - x * x - y * y)) - .025
		piece("Vein", Enum.PartType.Block, Vector3.new(len, .025, .02), CFrame.new(x, y, z) * CFrame.Angles(0, 0, rot), 1)
	end
	vein(.1, .1, .9, .5)
	vein(-.2, -.25, .7, -.7)
	vein(.35, -.05, .5, 1.3)
	local cfs = table.create(#parts)
	local list = table.create(#parts)
	for i, row in ipairs(parts) do
		list[i] = row.Part
	end
	local lastScale, lastBlood, lastVis = -1, -1, -1

	local function moonFrame()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local W = LightingMod and LightingMod.Weights and LightingMod.Weights() or nil
		local vis = W and W.MoonVis or 0
		local blood = W and W.Blood or Shared.BloodMoonAlpha(Shared.Now())
		local approach = W and W.Approach or 0
		if vis < .01 and lastVis < .01 then
			return
		end
		local camPos = cam.CFrame.Position
		local grow = smooth(blood)
		local pulse = 1
		if blood > .9 and not Shared.ReducedMotion() then
			pulse = 1 + .025 * math.sin(os.clock() * 1.4)
		end
		local radius = M.MoonDistance * TAN * (.82 + .18 * approach) * (1 + (GROW - 1) * grow) * pulse
		local pos = camPos + DIR * M.MoonDistance
		local cf = CFrame.lookAt(pos, camPos)
		local resize = math.abs(radius - lastScale) > radius * .002
		for i, row in ipairs(parts) do
			local o = row.Offset
			cfs[i] = cf * CFrame.new(o.Position * radius) * o.Rotation
			if resize then
				row.Part.Size = row.Size * radius
			end
		end
		if resize then
			lastScale = radius
		end
		workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if math.abs(blood - lastBlood) > .004 or math.abs(vis - lastVis) > .004 then
			lastBlood, lastVis = blood, vis
			for _, row in ipairs(parts) do
				local p = row.Part
				p.Color = (MOON[row.Kind] or MOON.Core):Lerp(BLOOD[row.Kind] or BLOOD.Core, grow)
				local baseT = row.BaseT
				if row.Kind == "Vein" then
					baseT = 1 - .75 * grow
				elseif row.Kind == "Halo" then
					baseT = baseT - .06 * grow
				end
				p.Transparency = 1 - (1 - baseT) * vis
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- sky particles around the camera (embers rising, ash drifting down, a light red rain)
	---------------------------------------------------------------------------------------------------------------
	local sky = FX.Part({ Size = Vector3.new(70, 16, 70), Transparency = 1, Name = "BloodMoonSky" })
	table.insert(built, sky)
	local function emitter(props)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.LightInfluence = 0
		for k, v in pairs(props) do
			(e :: any)[k] = v
		end
		e.Parent = sky
		return e
	end
	local embers = emitter({ Texture = FX.Textures.Sparkle, Color = ColorSequence.new(C3(255, 120, 50), C3(200, 20, 30)), LightEmission = 1,
		Size = FX.Seq(.16, .26, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .15),
			NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(.6, 2),
		SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(1.1, .9, .5), Drag = .3, RotSpeed = NumberRange.new(-90, 90),
		EmissionDirection = Enum.NormalId.Top })
	local ash = emitter({ Texture = FX.Textures.Smoke, Color = ColorSequence.new(C3(70, 52, 58), C3(34, 24, 30)), LightEmission = 0,
		LightInfluence = .6, Size = FX.Seq(.22, .3, .1), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(.2, .3), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(.3, 1), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(1.4, -1.1, .7), Drag = .5,
		RotSpeed = NumberRange.new(-40, 40), EmissionDirection = Enum.NormalId.Bottom })
	local rain = emitter({ Texture = FX.Textures.Sparkle, Color = ColorSequence.new(C3(200, 24, 34)), LightEmission = .35,
		Size = NumberSequence.new(.07), Transparency = NumberSequence.new(.35), Lifetime = NumberRange.new(.7, 1),
		Speed = NumberRange.new(48, 58), SpreadAngle = Vector2.new(4, 4), Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(2.5), EmissionDirection = Enum.NormalId.Bottom })
	local RATES = { High = { 22, 14, 36 }, Medium = { 13, 8, 16 }, Low = { 5, 3, 0 } }
	local lastRates = { -1, -1, -1 }
	local function particles(strength: number, zone: number)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local r = RATES[Shared.Quality()] or RATES.High
		local want = { r[1] * strength, r[2] * strength, r[3] * strength * zone }
		for i, e in ipairs({ embers, ash, rain }) do
			local v = math.floor(want[i] * 2 + .5) / 2
			if v ~= lastRates[i] then
				lastRates[i] = v
				e.Rate = v
				e.Enabled = v > 0
			end
		end
		if strength > 0 then
			local p = cam.CFrame.Position
			sky.CFrame = CFrame.new(p.X, p.Y + 6, p.Z)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- lantern flicker (HwLantern lights, Brightness only)
	---------------------------------------------------------------------------------------------------------------
	local lanterns = {} -- light -> {Seed, Part}
	local function addLantern(d: Instance)
		if d:IsA("BasePart") and d:GetAttribute("HwLantern") ~= nil then
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("Light") then
					if c:GetAttribute("HwBaseBrightness") == nil then
						c:SetAttribute("HwBaseBrightness", c.Brightness)
					end
					lanterns[c] = { Seed = math.random() * 100, Part = d }
				end
			end
		elseif d:IsA("Light") and d.Parent and d.Parent:IsA("BasePart") and d.Parent:GetAttribute("HwLantern") ~= nil then
			if d:GetAttribute("HwBaseBrightness") == nil then
				d:SetAttribute("HwBaseBrightness", d.Brightness)
			end
			lanterns[d] = { Seed = math.random() * 100, Part = d.Parent }
		end
	end
	task.spawn(function()
		local district = workspace:WaitForChild("DOGROTS_District", 60)
		local yard = district and district:WaitForChild("38_DeadYard", 120)
		if not yard or not alive then
			return
		end
		for _, d in ipairs(yard:GetDescendants()) do
			addLantern(d)
		end
		table.insert(conns, yard.DescendantAdded:Connect(addLantern))
		table.insert(conns, yard.DescendantRemoving:Connect(function(d)
			lanterns[d] = nil
		end))
	end)
	local flickerOn = false
	local function restoreLanterns()
		for light in pairs(lanterns) do
			local b = light:GetAttribute("HwBaseBrightness")
			if light.Parent and type(b) == "number" then
				light.Brightness = b
			end
		end
	end
	local function flicker(strength: number)
		local f = FX.Folder()
		local pub = math.floor(strength * 20 + .5) / 20
		if f:GetAttribute("HwBloodFlicker") ~= pub then
			f:SetAttribute("HwBloodFlicker", pub)
		end
		if strength <= .001 then
			if flickerOn then
				flickerOn = false
				restoreLanterns()
			end
			return
		end
		flickerOn = true
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local t = os.clock()
		local reduced = Shared.ReducedMotion()
		for light, row in pairs(lanterns) do
			local base = light:GetAttribute("HwBaseBrightness")
			if light.Parent and type(base) == "number" then
				local part = row.Part
				if part.Parent and (part.CFrame.Position - camPos).Magnitude < 220 then
					local n = math.noise(t * (reduced and 2.5 or 7) + row.Seed, row.Seed * .37)
					local drop = (not reduced and math.noise(t * 2.1 + row.Seed * 3, 1.7) < -.42) and .15 or 1
					local fl = math.clamp(.62 + n * .7, .15, 1.25) * drop
					light.Brightness = base * (1 + (fl - 1) * strength)
				else
					light.Brightness = base
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- warning card
	---------------------------------------------------------------------------------------------------------------
	local FONT = FX.Font
	local gui, card, title, sub, titleScale = nil, nil, nil, nil, nil
	local function mainGui()
		local pg = player:FindFirstChildOfClass("PlayerGui")
		return pg and pg:FindFirstChild("ScreenGui")
	end
	local function buildCard()
		if gui and gui.Parent then
			return
		end
		local pg = player:WaitForChild("PlayerGui")
		gui = Instance.new("ScreenGui")
		gui.Name = "DOGROTS_BloodMoonNotice"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 86
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui:SetAttribute("HideWithUI", true)
		gui:SetAttribute("NoTranslate", true)
		gui.Enabled = false
		card = Instance.new("Frame")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(.5, 0)
		card.BackgroundColor3 = C3(24, 6, 18)
		card.BackgroundTransparency = .1
		card.Size = UDim2.fromOffset(440, 70)
		card.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = C3(200, 30, 50)
		stroke.Thickness = 2
		stroke.Transparency = .05
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(C3(255, 255, 255), C3(150, 120, 140))
		grad.Parent = card
		local icon = Instance.new("Frame")
		icon.Name = "Moon"
		icon.AnchorPoint = Vector2.new(0, .5)
		icon.Position = UDim2.new(0, 14, .5, 0)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.BackgroundColor3 = C3(214, 44, 40)
		icon.Parent = card
		local ic = Instance.new("UICorner")
		ic.CornerRadius = UDim.new(1, 0)
		ic.Parent = icon
		local ig = Instance.new("UIGradient")
		ig.Rotation = 35
		ig.Color = ColorSequence.new(C3(255, 120, 90), C3(110, 8, 18))
		ig.Parent = icon
		local is = Instance.new("UIStroke")
		is.Color = C3(255, 80, 64)
		is.Thickness = 2
		is.Transparency = .35
		is.Parent = icon
		for i, c in ipairs({ { .28, .3, .22 }, { .62, .58, .16 }, { .4, .7, .12 } }) do
			local cr = Instance.new("Frame")
			cr.Name = "Crater" .. i
			cr.AnchorPoint = Vector2.new(.5, .5)
			cr.Position = UDim2.fromScale(c[1], c[2])
			cr.Size = UDim2.fromScale(c[3], c[3])
			cr.BackgroundColor3 = C3(120, 14, 22)
			cr.BackgroundTransparency = .25
			cr.Parent = icon
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(1, 0)
			cc.Parent = cr
		end
		local function label(name: string, size: number, color: Color3, y: number, h: number)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.FontFace = FONT
			t.TextColor3 = color
			t.TextSize = size
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Position = UDim2.new(0, 70, 0, y)
			t.Size = UDim2.new(1, -82, 0, h)
			t:SetAttribute("NoTranslate", true)
			local s = Instance.new("UIStroke")
			s.Color = C3(50, 0, 12)
			s.Thickness = 1.5
			s.Parent = t
			t.Parent = card
			return t
		end
		title = label("Title", 25, C3(255, 222, 208), 8, 30)
		sub = label("Sub", 15, C3(232, 176, 196), 40, 20)
		titleScale = Instance.new("UIScale")
		titleScale.Parent = title
		gui.Parent = pg
		table.insert(built, gui)
	end
	local function placeCard()
		if not card then
			return
		end
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local touch = vp.X < 900 or vp.Y < 500
		local w = math.min(touch and 340 or 440, vp.X - 24)
		card.Size = UDim2.fromOffset(w, touch and 58 or 70)
		title.TextSize = touch and 19 or 25
		sub.TextSize = touch and 12 or 15
		title.Position = UDim2.new(0, touch and 60 or 70, 0, touch and 6 or 8)
		sub.Position = UDim2.new(0, touch and 60 or 70, 0, touch and 32 or 40)
		local main = mainGui()
		local l = main and main:GetAttribute("HUDInnerLeft")
		local r = main and main:GetAttribute("HUDInnerRight")
		local top = main and main:GetAttribute("HUDFreeTop")
		local x = (type(l) == "number" and type(r) == "number" and r > l) and (l + r) / 2 or vp.X / 2
		local y = (type(top) == "number" and top or (touch and 120 or 144)) + (touch and 60 or 72) -- below the HUD event strip
		local strip = main and main:GetAttribute("HwStripBottom") -- the HUD strip (+ boss bar) publishes its bottom edge
		if type(strip) == "number" and strip > 0 then
			y = strip + 8
		end
		card.Position = UDim2.fromOffset(x, y)
	end
	local cardShown = false
	local lastSecond = -1
	local function showCard(on: boolean)
		if on == cardShown then
			return
		end
		cardShown = on
		if on then
			buildCard()
			placeCard()
			gui.Enabled = true
			card.BackgroundTransparency = 1
			if Shared.ReducedMotion() then
				card.BackgroundTransparency = .1
			else
				local p = card.Position
				card.Position = p - UDim2.fromOffset(0, 16)
				TweenService:Create(card, TweenInfo.new(.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = p, BackgroundTransparency = .1 }):Play()
			end
		elseif gui then
			gui.Enabled = false
		end
	end
	local candyPct = math.floor(((Config.BloodMoon and Config.BloodMoon.CandyBonus) or .5) * 100 + .5)
	local function updateCard(bm, now: number)
		if not cardShown then
			return
		end
		local left = math.max(0, math.ceil((bm.StartTimestamp or now) - now))
		title.Text = Shared.L(string.format("BLOOD MOON RISES IN %ds", left), string.format("КРОВАВАЯ ЛУНА ВЗОЙДЁТ ЧЕРЕЗ %d С", left))
		sub.Text = Shared.L(string.format("Haunted dig spots · +%d%% candy · THE DEAD YARD", candyPct),
			string.format("Проклятые раскопки · +%d%% конфет · МЁРТВЫЙ ДВОР", candyPct))
		local main = mainGui()
		local hidden = main ~= nil and (main:GetAttribute("OpenMenu") ~= nil or main:GetAttribute("UIHidden") == true)
		card.Visible = not hidden
		if left ~= lastSecond then
			lastSecond = left
			placeCard()
			if left <= 10 and left > 0 then
				if not Shared.ReducedMotion() then
					titleScale.Scale = 1.16
					TweenService:Create(titleScale, TweenInfo.new(.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end
				local sc = ctx.Modules and ctx.Modules.Soundscape
				local theme = sc and sc.Theme and sc.Theme()
				if theme ~= "BLOOD_WARN" and not hidden then
					Audio.Play("Heartbeat", nil, { Volume = .35 + .04 * (10 - left) })
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- set pieces
	---------------------------------------------------------------------------------------------------------------
	local function inZoneW(): number
		local W = LightingMod and LightingMod.Weights and LightingMod.Weights()
		return W and W.Zone or 0
	end
	local function lightning(strength: number, thunderDelay: number, volume: number)
		if LightingMod and LightingMod.Flash then
			LightingMod.Flash(strength, .55)
		end
		Audio.Play("Thunder", nil, { Volume = volume, Delay = thunderDelay, Pitch = math.random() * .2 + .9 })
	end
	local function onRise()
		local zone = inZoneW()
		Bus.Fire("Banner", { Title = Shared.L("BLOOD MOON", "КРОВАВАЯ ЛУНА"),
			Subtitle = Shared.L(string.format("The Buried Moon has risen · haunted dig spots · +%d%% candy", candyPct),
				string.format("Погребённая луна взошла · проклятые раскопки · +%d%% конфет", candyPct)),
			Color = C3(200, 30, 50), Style = "BloodMoon", Seconds = 4.5, NoTranslate = true })
		lightning(.9, .05, .95)
		Audio.Play("BloodMoonRise", nil, { Volume = .55 + .45 * zone })
		local bellD = (workspace.CurrentCamera and (workspace.CurrentCamera.CFrame.Position - Layout.Bell.Position).Magnitude) or 1e9
		if bellD < 260 then
			Audio.Play("BellToll", Layout.Bell.Position + Vector3.new(0, 6, 0), { Delay = .9 })
			Audio.Play("BellToll", Layout.Bell.Position + Vector3.new(0, 6, 0), { Delay = 3.4, Volume = .8 })
		else
			Audio.Play("BellToll", nil, { Delay = .9, Volume = .35 })
		end
		FX.Flash(C3(255, 70, 60), .14 + .1 * zone, .9)
		if zone > .5 then
			FX.Shake(.35, .8)
		end
	end
	local function onSet()
		Audio.Play("BloodMoonEnd", nil, { Volume = .4 + .5 * inZoneW() })
		Bus.Fire("Toast", { Text = Shared.L("The Blood Moon sets… the dead go back to sleep.", "Кровавая Луна заходит… мёртвые снова засыпают."),
			Kind = "Info", NoTranslate = true })
	end

	---------------------------------------------------------------------------------------------------------------
	-- loops
	---------------------------------------------------------------------------------------------------------------
	local lastKey, lastState = nil, nil
	local nextLightning = os.clock() + 12
	local slowAcc, flickAcc = 0, 0
	RunService:BindToRenderStep("DOGROTS_HalloweenMoon", Enum.RenderPriority.Camera.Value + 3, function()
		if alive then
			local ok, err = pcall(moonFrame)
			if not ok and not M.Warned then
				M.Warned = true
				warn("Halloween moon frame failed: " .. tostring(err))
			end
		end
	end)
	local function cleanup()
		if not alive then
			return
		end
		alive = false
		RunService:UnbindFromRenderStep("DOGROTS_HalloweenMoon")
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		restoreLanterns()
		pcall(function()
			FX.Folder():SetAttribute("HwBloodFlicker", 0)
		end)
		for _, inst in ipairs(built) do
			inst:Destroy()
		end
	end
	M.Stop = cleanup
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				cleanup()
				return
			end
			local now = Shared.Now()
			slowAcc += dt
			flickAcc += dt
			local W = LightingMod and LightingMod.Weights and LightingMod.Weights() or nil
			local blood = W and W.Blood or 0
			local zone = W and W.Zone or 0
			local approach = W and W.Approach or 0
			if flickAcc >= .05 then
				flickAcc = 0
				local bm = Shared.BloodMoonState(now)
				local strength = 0
				if bm.State == "ACTIVE" or bm.State == "ENDING" then
					strength = math.clamp((Shared.BloodMoonAlpha(now, bm) - .25) / .75, 0, 1)
				end
				flicker(strength)
				particles(blood > .3 and math.clamp((blood - .3) / .7, 0, 1) * (zone + .25 * approach * (1 - zone)) or 0, zone)
			end
			if slowAcc < .2 then
				return
			end
			slowAcc = 0
			local bm = Shared.BloodMoonState(now)
			local key = tostring(bm.State) .. ":" .. tostring(bm.Cycle)
			if key ~= lastKey then
				local prev = lastState
				lastKey, lastState = key, bm.State
				if bm.State == "WARNING" then
					if now - (bm.WarningTimestamp or now) < 4 then
						Audio.Play("BloodMoonWarn", nil, { Volume = .5 + .4 * zone })
					end
				elseif bm.State == "ACTIVE" then
					if now - (bm.StartTimestamp or 0) < 4 then -- (late joiners after 4 s get the state only)
						onRise()
					end
					nextLightning = os.clock() + 9 + math.random() * 8
				elseif bm.State == "ENDING" and prev == "ACTIVE" then
					onSet()
				end
			end
			showCard(bm.State == "WARNING" and (bm.StartTimestamp or 0) - now > .4)
			updateCard(bm, now)
			-- periodic lightning while the moon is up (in / near the yard)
			if bm.State == "ACTIVE" and (zone > .3 or approach > .4) and os.clock() >= nextLightning then
				local q = Shared.Budget("Ambient")
				nextLightning = os.clock() + (M.LightningEvery[1] + math.random() * (M.LightningEvery[2] - M.LightningEvery[1])) / math.max(.35, q)
				lightning(.45 + math.random() * .25, .3 + math.random() * 1.1, .4 + .3 * zone)
			end
		end)
		if not ok then
			pcall(restoreLanterns) -- a failing tick must not leave a lantern at a flickered brightness
			flickerOn = false
			if not M.WarnedTick then
				M.WarnedTick = true
				warn("Halloween BloodMoonFX tick failed: " .. tostring(err))
			end
		end
	end))
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(placeCard))
	end
end

return M
