-- HOLLOW KING (THE UNDERYARD event Secret, WP-K1), the stage arrival
-- (StarterPlayer.StarterPlayerScripts.SecretArrivals.Dogs.HW_HollowKing; run by the base SecretArrivals on every client,
-- ctx = the arrival context: Kit, Scope, Model, Config, Origin, Venue, Wait/Elapsed/Say/Title...).
-- Won anywhere off the tongue (SecretReveal: the Black Coffin shrine, a Crooked Door's rare room, the Last Bark), so it
-- only uses the dog's own spot and facing. 0: the light around the spot dies and a pool of ink opens on the ground behind
-- it. 0.5: a black moon rises behind the spot with a violet rim and one pale sliver of light, moths spiral up out of the
-- pool. 1.2: the king walks out of the dark toward the viewer as an ink silhouette (server clip Walk). 3.2, TOTALITY: the
-- sliver is swallowed, the corona flares, a crown of violet fire drops onto its head, a ring of light runs over the
-- ground and the dog is revealed (server clip Coronation, Mega/HW_HollowKing lands on the same beat). Title at 4.3; from
-- 6.4 the moon sinks, the moths fall into the dog, the pool closes. Everything lives in ctx.Scope (undone on Clean).
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = C(10, 6, 18)
local VIOLET = C(150, 80, 230)
local LILAC = C(218, 176, 255)
local MOON = C(190, 216, 255)
local DARK, RISE, WALK, ARRIVE, TOTAL, TITLE, FADE = 0, .5, 1.2, 3.0, 3.2, 4.3, 6.4
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
	ctx.WhisperStyle = { Font = Enum.Font.FredokaOne, Color = LILAC, Type = .06, Chroma = true }
	local low, hold = ctx.Low, config.Hold
	local reduced = Kit.ReducedMotion()
	local size = Kit.Size(model)
	local unit = math.max(size.Y, 2) / 6.2 -- template studs -> this display's studs
	local ground = ctx:Ground()
	local look = ctx:Pivot().LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > .01 and look.Unit or Vector3.zAxis
	local side = look:Cross(Vector3.yAxis).Unit
	local walkFrom = math.max(size.Z, 4) * 1.1 + 2
	local moonR = math.max(size.Y, 4) * .62
	local moonAt = ground - look * (walkFrom + moonR * 1.2) + Vector3.new(0, size.Y + moonR * .9, 0)
	local function near()
		return Kit.Near(ground, 140)
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
	if near() > .2 then
		scope:Duck(.12, 1) -- the music is cut while the king arrives
	end
	if near() > .15 then
		scope:Grade({ TintColor = C(214, 200, 255), Saturation = -.5 * math.min(1, near() * 1.4), Contrast = .15, Brightness = -.06 * near() }, .9, 1.4)
	end

	-- the dog: an ink silhouette that walks out of the dark (WALK..ARRIVE), revealed at totality
	local vis = scope:Visibility(model)
	local off = scope:Offset(model)
	local shown = -1
	local function show(v)
		if v ~= shown and (math.abs(v - shown) > .01 or v == 0 or v == 1) then
			shown = v
			vis.Set(v)
		end
	end
	show(ctx:Elapsed() < WALK and 1 or 0)
	local silhouette = scope:Highlight(model, INK, VIOLET, 0, 1)
	-- the dog's own ability FX hooks (Models.EventDogs StartFX: crown fire, the soul in its ribs, moth dust)
	local dogFX = nil
	local function startDogFX(intensity)
		if dogFX then
			dogFX.SetIntensity(intensity)
			return
		end
		local ok, h = pcall(function()
			local RS = game:GetService("ReplicatedStorage")
			local folder = RS:FindFirstChild("Halloween") and RS.Halloween:FindFirstChild("Models")
			local mod = folder and (folder:FindFirstChild("EventDogs2") or folder:FindFirstChild("EventDogs"))
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

	-- the pool of ink along the path it walks, with a violet rim
	local poolCenter = ground - look * walkFrom * .55
	local poolR = math.max(size.X, size.Z) * .5 + walkFrom * .5
	local pool = scope:Part({ Name = "InkPool", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = INK,
		Size = Vector3.new(.05, .1, .1), CFrame = CFrame.new(poolCenter + Vector3.new(0, .06, 0)) * UPRIGHT, Transparency = 1 })
	local rim = scope:Part({ Name = "InkRim", Shape = Enum.PartType.Cylinder, Color = VIOLET, Size = Vector3.new(.04, .1, .1),
		CFrame = CFrame.new(poolCenter + Vector3.new(0, .04, 0)) * UPRIGHT, Transparency = 1 })
	local anchor = scope:Anchor(poolCenter + Vector3.new(0, .4, 0), "InkAnchor")
	local smoke = scope:Emitter(anchor, { Texture = Kit.Textures.Smoke, Color = ColorSequence.new(C(40, 16, 70), INK), LightEmission = 0, LightInfluence = .2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top, Drag = 1 })
	smoke.Shape = Enum.ParticleEmitterShape.Disc
	smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	local glow = (not low) and scope:Light(anchor, VIOLET, 18, 0) or nil

	-- the black moon, its violet rim, the pale sliver of last light and the corona rays
	local moon = scope:Part({ Name = "BlackMoon", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = INK, Size = Vector3.one * moonR * 2,
		CFrame = CFrame.new(moonAt), Transparency = 1 })
	local halo = scope:Part({ Name = "BlackMoonHalo", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = VIOLET,
		Size = Vector3.one * moonR * 2.7, CFrame = CFrame.new(moonAt), Transparency = 1 })
	local sliver = scope:Part({ Name = "LastLight", Shape = Enum.PartType.Ball, Color = MOON, Size = Vector3.one * moonR * 2.02, CFrame = CFrame.new(moonAt),
		Transparency = 1 })
	local rays = {}
	for i = 1, low and 8 or 16 do
		rays[i] = scope:Part({ Name = "CoronaRay", Color = i % 2 == 0 and VIOLET or LILAC, Size = Vector3.new(.12, .12, 1), Transparency = 1, CFrame = CFrame.new(moonAt) })
	end
	local moonLight = (not low) and scope:Light(moon, LILAC, moonR * 6, 0) or nil

	-- moths: pale wings flapping round the path, drawn up toward the moon
	local moths = {}
	for i = 1, low and 6 or 14 do
		local wingL = scope:Part({ Name = "MothWing", Material = Enum.Material.SmoothPlastic, Color = i % 3 == 0 and LILAC or C(196, 184, 222),
			Size = Vector3.new(.5, .04, .36) * unit * 1.6, Transparency = 1 })
		local wingR = scope:Part({ Name = "MothWing", Material = Enum.Material.SmoothPlastic, Color = wingL.Color, Size = wingL.Size, Transparency = 1 })
		moths[i] = { L = wingL, R = wingR, Phase = (i - 1) / (low and 6 or 14) * math.pi * 2, Speed = .7 + (i % 5) * .12, H = .6 + (i % 4) * .5,
			Flap = 9 + (i % 3) * 2 }
	end

	-- the crown of violet fire: tongues in a ring, hovering high, falling onto the king's head at totality
	local tongues = {}
	for i = 1, low and 6 or 10 do
		tongues[i] = scope:Part({ Name = "CrownFire", Color = i % 2 == 0 and VIOLET or LILAC, Size = Vector3.new(.2, .6, .2) * unit * 1.4, Transparency = 1 })
	end
	local crownLight = (not low) and scope:Light(scope:Anchor(ground, "CrownAnchor"), LILAC, 14, 0) or nil
	local crownAnchor = crownLight and crownLight.Parent

	local totalAt = nil
	scope:Every(function()
		local el = ctx:Elapsed()
		local camera = workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or (moonAt + look * 30)
		local surge = totalAt and math.exp(-(el - TOTAL) * 2) or 0
		-- the pool
		local open = out3((el - DARK) / .7) * (1 - smooth((el - FADE - .4) / .9))
		local r = poolR * open * (1 + .03 * math.sin(el * 2.6))
		pool.Size = Vector3.new(.05, r * 2 + .01, r * 2 + .01)
		pool.Transparency = open > .01 and 0 or 1
		rim.Size = Vector3.new(.04, r * 2.1 + .02, r * 2.1 + .02)
		rim.Transparency = open > .01 and (.2 - .2 * surge) or 1
		rim.Color = VIOLET:Lerp(WHITE, .45 * surge)
		smoke.Rate = (low and 4 or 11) * open
		if glow then
			glow.Brightness = 1.2 * open + 4 * surge
		end
		-- the walk out of the dark: offset back along its own +Z, silhouette until totality
		local walk = smooth((el - WALK) / (ARRIVE - WALK))
		off.CFrame = CFrame.new(0, 0, walkFrom * (1 - walk))
		show(el < WALK and 1 or 1 - smooth((el - WALK) / .5))
		local reveal = smooth((el - TOTAL) / .9)
		silhouette.FillTransparency = math.clamp(reveal, 0, 1)
		silhouette.OutlineTransparency = el < WALK and 1 or math.clamp(.05 + .9 * smooth((el - TITLE - .6) / 1.4), 0, 1)
		-- the black moon rises, the sliver of last light is swallowed at totality, it sinks after FADE
		local mv = smooth((el - RISE) / 1.4) * (1 - smooth((el - FADE) / 1.2))
		local lift = (1 - smooth((el - RISE) / 1.6)) * moonR * 2.2 + smooth((el - FADE) / 1.4) * moonR * 2.6
		local center = moonAt - Vector3.new(0, lift, 0) + Vector3.new(0, math.sin(el * 1.1) * .15, 0)
		local toCam = camPos - center
		toCam = toCam.Magnitude > .01 and toCam.Unit or -look
		local right = toCam:Cross(Vector3.yAxis)
		right = right.Magnitude > .01 and right.Unit or side
		moon.CFrame = CFrame.new(center + toCam * .3)
		moon.Transparency = 1 - mv
		local cover = smooth((el - RISE) / (TOTAL - RISE))
		sliver.CFrame = CFrame.new(center - toCam * .2 + right * (1 - cover) * moonR * .22)
		sliver.Transparency = mv > .01 and (cover >= .999 and 1 or 1 - mv) or 1
		halo.CFrame = CFrame.new(center)
		halo.Transparency = 1 - mv * (.25 + .35 * surge)
		if moonLight then
			moonLight.Brightness = mv * (.6 + 3 * surge)
		end
		local up = right:Cross(toCam).Unit
		local corona = smooth((el - TOTAL + .1) / .3) * (1 - smooth((el - FADE) / .8)) * mv
		for i, ray in ipairs(rays) do
			local a = (i - 1) / #rays * math.pi * 2 + el * .3
			local len = moonR * (.5 + .35 * math.sin(el * 2.6 + i * 1.3)) * (1 + 1.4 * surge)
			local dir = right * math.cos(a) + up * math.sin(a)
			local p0 = center + toCam * .5 + dir * moonR * 1.05
			local p1 = p0 + dir * len
			ray.Size = Vector3.new(.14, .14, (p1 - p0).Magnitude)
			ray.CFrame = Kit.LookAt((p0 + p1) / 2, p1)
			ray.Transparency = 1 - .85 * corona
		end
		-- moths spiral up from the pool toward the moon, then fall into the king
		local mothVis = smooth((el - RISE) / .8) * (1 - smooth((el - FADE) / .6))
		local into = smooth((el - FADE) / .8)
		for _, m in ipairs(moths) do
			local a = m.Phase + el * m.Speed
			local rr = poolR * (.4 + .5 * math.sin(el * .7 + m.Phase)) * (1 - into)
			local h = (m.H + math.max(0, el - RISE) * .45) * unit * 1.6
			local pos = poolCenter + Vector3.new(math.cos(a) * rr, h, math.sin(a) * rr)
			pos = pos:Lerp(ground + Vector3.new(0, size.Y * .5, 0), into)
			local flap = math.sin(el * m.Flap + m.Phase) * .9
			local base = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
			local w = m.L.Size.X
			m.L.CFrame = base * CFrame.Angles(0, 0, flap) * CFrame.new(w / 2, 0, 0)
			m.R.CFrame = base * CFrame.Angles(0, 0, -flap) * CFrame.new(-w / 2, 0, 0)
			m.L.Transparency = 1 - .9 * mothVis
			m.R.Transparency = 1 - .9 * mothVis
		end
		-- the crown of fire: ignites high above the spot, drops onto the head at totality, burns out as the dog's own
		-- crown takes over
		local head = ground - look * walkFrom * (1 - walk) + look * size.Z * .26 + Vector3.new(0, size.Y * .84, 0)
		local crownVis = smooth((el - TOTAL + .9) / .5) * (1 - smooth((el - TOTAL - 1.6) / .9))
		local drop = smooth((el - TOTAL) / .35)
		local crownAt = head + Vector3.new(0, (1 - drop) * size.Y * .9 + .2 * unit, 0)
		local ringR = .45 * unit * (1 + .8 * (1 - drop))
		for i, tongue in ipairs(tongues) do
			local a = (i - 1) / #tongues * math.pi * 2 + el * 1.4
			local hgt = (.5 + .35 * math.sin(el * 11 + i * 2.1)) * unit * 1.4 * (1 + 1.2 * surge)
			tongue.Size = Vector3.new(.2 * unit * 1.4, hgt, .2 * unit * 1.4)
			tongue.CFrame = CFrame.new(crownAt + Vector3.new(math.cos(a) * ringR, hgt / 2, math.sin(a) * ringR)) * CFrame.Angles(0, -a, .12 * math.sin(el * 7 + i))
			tongue.Transparency = 1 - .9 * crownVis
		end
		if crownLight and crownAnchor then
			crownAnchor.CFrame = CFrame.new(crownAt)
			crownLight.Brightness = 3 * crownVis + 3 * surge
		end
		return true
	end)

	-- 0: the light dies
	if fresh(DARK, .6) then
		cue("Heartbeat", .55)
		cue("Whoosh", .2)
		if not reduced and near() > .3 then
			Kit.Shake(.06, .5)
		end
	end
	if not ctx:Wait(RISE) then
		return
	end
	if fresh(RISE) then
		cue("Glitch", .15)
	end
	if not ctx:Wait(WALK) then
		return
	end
	if fresh(WALK) then
		cue("Heartbeat", .65)
	end
	if not ctx:Wait(TOTAL - .4) then
		return
	end
	if fresh(TOTAL - .4) then
		cue("Heartbeat", .75)
	end
	-- 3.2: TOTALITY - the last light is swallowed, the crown of fire falls onto its head
	if not ctx:Wait(TOTAL) then
		return
	end
	totalAt = TOTAL
	if fresh(TOTAL, .8) then
		cue("Sting", .6)
		cue("Impact", .5)
		scope:Burst(moonAt, VIOLET, 55, { Lifetime = NumberRange.new(.7, 1.5), Speed = NumberRange.new(4, 12), Drag = 2,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(1, 0) }) })
		scope:Burst(ground + Vector3.new(0, size.Y * .9, 0), LILAC, 34, { Lifetime = NumberRange.new(.5, 1.1), Speed = NumberRange.new(5, 12), Drag = 3,
			SpreadAngle = Vector2.new(60, 60), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 0) }) })
		scope:Ring(ground + Vector3.new(0, .15, 0), VIOLET, 1.5, 20, 1.2, { Thickness = .35, Alpha = .05, Segments = 30 })
		scope:Pillar(ground, ground + Vector3.new(0, 40, 0), LILAC, 1.4, 1.1)
		startDogFX(1.8)
		if dogFX then
			dogFX.Burst(18)
		end
		local n = near()
		if n > .05 then
			Kit.Flash(VIOLET, 1 - .4 * n, .55)
			local camera = workspace.CurrentCamera
			if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
				Kit.FOVPunch(-4 * n, .18, 1.1)
			end
			if not reduced then
				Kit.Shake(.1 * n, .5)
			end
		end
	end
	-- 4.3: the card
	if not ctx:Wait(TITLE) then
		return
	end
	ctx:Title()
	if fresh(TITLE, .6) then
		cue("Chime", .45)
	end
	startDogFX(1) -- a late joiner still sees the dog's own fire
	-- 6.4: the moon sinks, the moths fall into the king, the pool closes
	if not ctx:Wait(FADE) then
		return
	end
	if fresh(FADE + .8, 2) then
		task.delay(.8, function()
			if scope.Alive then
				scope:Burst(ground + Vector3.new(0, size.Y * .5, 0), LILAC, 26, { Lifetime = NumberRange.new(.4, .9), Speed = NumberRange.new(2, 6), Drag = 2 })
				cue("Whoosh", .2)
			end
		end)
	end
	ctx:Wait(hold)
end
