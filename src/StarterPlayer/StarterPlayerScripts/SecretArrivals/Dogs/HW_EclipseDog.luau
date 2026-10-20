-- ECLIPSE DOG (NIGHT OF THE BURIED MOON event Secret), the stage arrival
-- (StarterPlayer.StarterPlayerScripts.SecretArrivals.Dogs.HW_EclipseDog; run by the base SecretArrivals on every client,
-- ctx = the arrival context: Kit, Scope, Model, Config, Origin, Venue, Wait/Elapsed/Say/Title...).
-- Won from a Pumpkin Lucky Block on a yard pad (SecretReveal, Venue "Yard"): the pad goes dark. A pool of nothing opens
-- under the block's spot with a violet rim, shards of night rise out of it and circle; above it a small pale moon is
-- slowly eaten by a black disc. At totality (3.0, the island-wide eclipse of Mega/HW_EclipseDog lands on the same beat)
-- the corona flares, a ring of violet light runs over the ground and the dog stands up out of the pool, outlined in
-- violet. Title at 4.0; the shards fall into the dog, the pool closes, the little moon comes back.
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local VOID = C(8, 3, 16)
local VIOLET = C(176, 70, 255)
local LILAC = C(214, 180, 255)
local MOON = C(255, 240, 214)
local POOL, SLIVERS, RISE, TOTAL, TITLE, CLOSE = 0, .6, 1.6, 3.0, 4.0, 5.6
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function out3(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lying flat (axis X -> Y)

return function(ctx)
	local Kit, scope, model, config = ctx.Kit, ctx.Scope, ctx.Model, ctx.Config
	ctx.WhisperStyle = { Font = Enum.Font.FredokaOne, Color = LILAC, Type = .05, Chroma = true }
	local low, hold = ctx.Low, config.Hold
	local reduced = Kit.ReducedMotion()
	local size = Kit.Size(model)
	local ground = ctx:Ground()
	local poolR = math.max(size.X, size.Z) * .55 + 2.2
	local depth = size.Y + .6
	local moonAt = ground + Vector3.new(0, size.Y + 4.5, 0)
	local function near()
		return Kit.Near(ground, 120)
	end
	local joined = ctx:Elapsed()
	local function fresh(t, window)
		return t > joined - (window or .35) and ctx:Elapsed() - t < .6
	end
	local function cue(kind, volume)
		local n = near()
		if n > .05 then
			Kit.Cue(kind, nil, volume * n)
		end
	end
	if near() > .25 then
		scope:Duck(.35, .8)
	end

	-- the dog: hidden, sunk below the pool; rises at RISE..TOTAL
	local vis = scope:Visibility(model)
	local off = scope:Offset(model)
	local shown = -1
	local function show(v)
		if v ~= shown and (math.abs(v - shown) > .01 or v == 0 or v == 1) then
			shown = v
			vis.Set(v)
		end
	end
	show(ctx:Elapsed() < TOTAL + .5 and 1 or 0)
	local halo = scope:Highlight(model, VIOLET, VIOLET, 1, 1)
	-- the dog's own ability FX hooks (EventDogs.StartFX: corona motes / moon shards), flared at totality
	local dogFX = nil
	local function startDogFX(intensity)
		if dogFX then
			dogFX.SetIntensity(intensity)
			return
		end
		local ok, h = pcall(function()
			local RS = game:GetService("ReplicatedStorage")
			local mod = RS:FindFirstChild("Halloween") and RS.Halloween:FindFirstChild("Models") and RS.Halloween.Models:FindFirstChild("EventDogs")
			local E = mod and require(mod)
			return E and E.StartFX and E.StartFX(model, { Low = low, Intensity = intensity })
		end)
		if ok and h then
			dogFX = h
			scope:Add(function()
				pcall(h.Stop)
			end)
		end
	end

	-- the pool: a black disc with a violet rim, darkness rising from it
	local pool = scope:Part({ Name = "VoidPool", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = VOID,
		Size = Vector3.new(.05, .1, .1), CFrame = CFrame.new(ground + Vector3.new(0, .07, 0)) * UPRIGHT, Transparency = 1 })
	local rim = scope:Part({ Name = "VoidRim", Shape = Enum.PartType.Cylinder, Color = VIOLET, Size = Vector3.new(.04, .1, .1),
		CFrame = CFrame.new(ground + Vector3.new(0, .05, 0)) * UPRIGHT, Transparency = 1 })
	local anchor = scope:Anchor(ground + Vector3.new(0, .4, 0), "VoidAnchor")
	local smoke = scope:Emitter(anchor, { Texture = Kit.Textures.Smoke, Color = ColorSequence.new(C(30, 10, 50), VOID), LightEmission = 0, LightInfluence = .2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(1.5, 3.5), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top,
		Drag = 1 })
	smoke.Shape = Enum.ParticleEmitterShape.Disc
	smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	local motes = scope:Emitter(anchor, { Color = ColorSequence.new(LILAC, VIOLET), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(.3, .28), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(.8, 1.6), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2, 0) })
	local glow = (not low) and scope:Light(anchor, VIOLET, 16, 0) or nil

	-- shards of night: thin black blades with a violet edge, circling up out of the pool
	local slivers = {}
	for i = 1, low and 5 or 9 do
		local blade = scope:Part({ Name = "Sliver", Material = Enum.Material.SmoothPlastic, Color = VOID, Size = Vector3.new(.16, 1.5, .55), Transparency = 1,
			CFrame = CFrame.new(ground) })
		local edge = scope:Part({ Name = "SliverEdge", Color = VIOLET, Size = Vector3.new(.06, 1.5, .08), Transparency = 1, CFrame = CFrame.new(ground) })
		slivers[i] = { Blade = blade, Edge = edge, Phase = (i - 1) / (low and 5 or 9) * math.pi * 2, H = .8 + (i % 3) * .55, Spin = 1.2 + (i % 4) * .25,
			Tilt = math.rad(15 + (i % 5) * 9) }
	end

	-- the little moon and its eclipse (balls facing the camera; the black disc slides between)
	local moon = scope:Part({ Name = "LittleMoon", Shape = Enum.PartType.Ball, Color = MOON, Size = Vector3.one * 2.4, CFrame = CFrame.new(moonAt), Transparency = 1 })
	local moonHalo = scope:Part({ Name = "LittleMoonHalo", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = MOON,
		Size = Vector3.one * 4.2, CFrame = CFrame.new(moonAt), Transparency = 1 })
	local shade = scope:Part({ Name = "LittleMoonShade", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = VOID,
		Size = Vector3.one * 2.5, CFrame = CFrame.new(moonAt), Transparency = 1 })
	local corona = {}
	for i = 1, low and 6 or 12 do
		corona[i] = scope:Part({ Name = "CoronaRay", Color = i % 2 == 0 and VIOLET or LILAC, Size = Vector3.new(.08, .08, 1), Transparency = 1,
			CFrame = CFrame.new(moonAt) })
	end
	local moonLight = (not low) and scope:Light(moon, LILAC, 14, 0) or nil

	local totalAt, closed = nil, false
	scope:Every(function(dt)
		local el = ctx:Elapsed()
		local camera = workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or (moonAt + Vector3.new(0, 0, 20))
		-- pool: opens fast, breathes, closes after CLOSE
		local open = out3((el - POOL) / .6) * (1 - smooth((el - CLOSE) / .9))
		local r = poolR * open * (1 + .04 * math.sin(el * 3))
		pool.Size = Vector3.new(.05, r * 2 + .01, r * 2 + .01)
		pool.Transparency = open > .01 and 0 or 1
		rim.Size = Vector3.new(.04, r * 2.12 + .02, r * 2.12 + .02)
		local surge = totalAt and math.exp(-(el - TOTAL) * 2) or 0
		rim.Transparency = open > .01 and (.15 - .15 * surge) or 1
		rim.Color = VIOLET:Lerp(WHITE, .5 * surge)
		smoke.Rate = (low and 4 or 10) * open
		motes.Rate = (low and 4 or 12) * open * (1 + 2 * surge)
		if glow then
			glow.Brightness = 1.5 * open + 4 * surge
		end
		-- the dog rises out of the pool
		local rise = smooth((el - RISE) / (TOTAL + .4 - RISE))
		off.CFrame = CFrame.new(0, -depth * (1 - rise), 0)
		show(1 - smooth((el - RISE - .3) / 1.2))
		halo.FillTransparency = 1 - (.75 * (1 - smooth((el - TOTAL) / 1.6))) * rise
		halo.OutlineTransparency = rise > 0 and math.min(1, .05 + .6 * smooth((el - TITLE - 1) / 1.5) + (1 - rise)) or 1
		-- slivers circle up, then fall into the dog
		local sv = smooth((el - SLIVERS) / .8)
		local into = smooth((el - CLOSE) / .8)
		for _, s in ipairs(slivers) do
			local a = s.Phase + el * s.Spin
			local rr = poolR * (.45 + .6 * sv) * (1 - into)
			local h = s.H * sv + size.Y * .6 * sv + math.sin(el * 2 + s.Phase) * .3
			local pos = ground + Vector3.new(math.cos(a) * rr, h * (1 - into) + size.Y * .5 * into, math.sin(a) * rr)
			local cf = CFrame.new(pos) * CFrame.Angles(0, -a, s.Tilt)
			s.Blade.CFrame = cf
			s.Edge.CFrame = cf * CFrame.new(.1, 0, -.24)
			local alpha = sv * (1 - smooth((el - CLOSE - .5) / .4))
			s.Blade.Transparency = 1 - .95 * alpha
			s.Edge.Transparency = 1 - .9 * alpha
		end
		-- the little moon: appears, is eaten by the disc (totality at TOTAL), the disc slides off after CLOSE
		local mv = smooth((el - .8) / .6) * (1 - smooth((el - CLOSE - 1) / .8))
		local toCam = (camPos - moonAt)
		toCam = toCam.Magnitude > .01 and toCam.Unit or Vector3.zAxis
		local right = toCam:Cross(Vector3.yAxis)
		right = right.Magnitude > .01 and right.Unit or Vector3.xAxis
		local up = right:Cross(toCam).Unit
		local bob = Vector3.new(0, math.sin(el * 1.3) * .15, 0)
		local center = moonAt + bob
		moon.CFrame = CFrame.new(center)
		moonHalo.CFrame = CFrame.new(center)
		moon.Transparency = 1 - mv
		moonHalo.Transparency = 1 - mv * (.25 + .35 * surge)
		local cover = smooth((el - 1.1) / (TOTAL - 1.1)) - smooth((el - CLOSE) / 1.2)
		shade.CFrame = CFrame.new(center + toCam * .35 + right * (1 - cover) * 2.8 * (el < CLOSE and -1 or 1) + up * (1 - cover) * .3)
		shade.Transparency = mv > .01 and 0 or 1
		if moonLight then
			moonLight.Brightness = mv * (1.4 - cover) + 3 * surge
		end
		local cv = smooth((el - TOTAL + .1) / .3) * (1 - smooth((el - CLOSE) / .6))
		for i, ray in ipairs(corona) do
			local a = (i - 1) / #corona * math.pi * 2 + el * .35
			local len = (.8 + .5 * math.sin(el * 3 + i * 1.7)) * (1 + 1.2 * surge)
			local dir = right * math.cos(a) + up * math.sin(a)
			local p0 = center + toCam * .4 + dir * 1.3
			local p1 = p0 + dir * len
			ray.Size = Vector3.new(.08, .08, (p1 - p0).Magnitude)
			ray.CFrame = Kit.LookAt((p0 + p1) / 2, p1)
			ray.Transparency = 1 - .85 * cv
		end
		return true
	end)

	-- 0: the pad goes dark
	if fresh(POOL, .6) then
		cue("Whoosh", .25)
		cue("Heartbeat", .5)
		if not reduced and near() > .3 then
			Kit.Shake(.08, .5)
		end
	end
	if not ctx:Wait(SLIVERS) then
		return
	end
	if fresh(SLIVERS) then
		cue("Glitch", .2)
	end
	if not ctx:Wait(1.8) then
		return
	end
	if fresh(1.8) then
		cue("Heartbeat", .6)
	end
	-- 3.0: TOTALITY - the corona flares, a ring of violet light runs over the ground
	if not ctx:Wait(TOTAL) then
		return
	end
	totalAt = TOTAL
	if fresh(TOTAL, .8) then
		cue("Sting", .55)
		cue("Impact", .45)
		scope:Burst(moonAt, VIOLET, 50, { Lifetime = NumberRange.new(.7, 1.5), Speed = NumberRange.new(4, 12), Drag = 2,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(1, 0) }) })
		scope:Burst(ground + Vector3.new(0, 1, 0), LILAC, 30, { Lifetime = NumberRange.new(.5, 1), Speed = NumberRange.new(6, 14), Drag = 3,
			SpreadAngle = Vector2.new(70, 70), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .4), NumberSequenceKeypoint.new(1, 0) }) })
		scope:Ring(ground + Vector3.new(0, .15, 0), VIOLET, 1.5, 18, 1.1, { Thickness = .35, Alpha = .05, Segments = 28 })
		scope:Pillar(ground, moonAt + Vector3.new(0, 30, 0), LILAC, 1.6, 1.2)
		startDogFX(1.8)
		if dogFX then
			dogFX.Burst(16)
		end
		local n = near()
		if n > .05 then
			Kit.Flash(VIOLET, 1 - .35 * n, .5)
			local camera = workspace.CurrentCamera
			if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
				Kit.FOVPunch(-4 * n, .18, 1.1)
			end
			scope:Grade({ TintColor = C(232, 220, 255), Saturation = -.25 * math.min(1, n * 1.5), Contrast = .12 * math.min(1, n * 1.5) }, .3, 1.6)
		end
	end
	-- 4.0: the card
	if not ctx:Wait(TITLE) then
		return
	end
	ctx:Title()
	if fresh(TITLE, .6) then
		cue("Chime", .45)
	end
	startDogFX(1) -- a late joiner still sees the dog's own glow
	-- 5.6: the shards fall into the dog, the pool closes, the moon comes back
	if not ctx:Wait(CLOSE) then
		return
	end
	closed = true
	if fresh(CLOSE + .8, 2) then
		task.delay(.8, function()
			if scope.Alive then
				scope:Burst(ground + Vector3.new(0, size.Y * .5, 0), VIOLET, 24, { Lifetime = NumberRange.new(.4, .9), Speed = NumberRange.new(2, 6), Drag = 2 })
				cue("Whoosh", .2)
			end
		end)
	end
	local _ = closed
	ctx:Wait(hold)
end
