-- ECLIPSE DOG, island-wide: "THE MOON WENT OUT" (StarterPlayer.StarterPlayerScripts.SecretArrivals.Mega.HW_EclipseDog;
-- the base Mega runner calls it on every client with the island context m: Sky, Grade, Bloom, Banner, Shockwave, SkyDog,
-- FollowRain, Ring, Pillar, Every, Wait, Fresh...).
-- Night falls over the whole island and a colossal pale moon hangs high beyond the giant head. From 0.4 a black disc slides
-- across it (a heartbeat under it); stars come out as the light dies. At 3.0, TOTALITY (the stage's beat): a diamond-ring
-- flash on the limb, the violet corona and its rays blaze out, a ring of violet light sweeps the island (every player
-- feels it pass), a pillar of night stands on the pad it was won on, and a colossal black silhouette of the Eclipse Dog
-- rises over the horizon against the corona, violet-rimmed, its eyes opening at 4.0 with the banner. Dark violet motes
-- fall around every player. In the Dead Yard the Buried Moon itself goes dark too. From 17 the disc slides off, the
-- light comes back, the silhouette sinks.
local Lighting = game:GetService("Lighting")
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local VOID = C(6, 2, 14)
local VIOLET = C(176, 70, 255)
local LILAC = C(214, 180, 255)
local MOON = C(255, 240, 214)
local CONTACT, TOTAL, EYES, THIRD, LIFT = .4, 3.0, 4.0, 17, 18
-- the eclipse hangs high beyond the giant head (the island faces it), the silhouette's feet far beyond the edge
local SKY = Vector3.new(0, 600, -820)
local R = 150
local FEET = Vector3.new(0, 0, -1150)
local HEIGHT = 520
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

return function(m)
	local low = m.Low
	local Kit = m.Kit
	local base = m.Venue == "Tongue" and m.Stage or m:Ground(m.Origin)
	local face = Vector3.new(0, 0, 1) -- the eclipse faces the island (+Z)

	-- night falls
	local sky = m:Sky({ ClockTime = 0, Brightness = .25, Ambient = C(26, 18, 40), OutdoorAmbient = C(36, 26, 58), ExposureCompensation = -.15 }, 2.5, 5)
	local grade = m:Grade({ TintColor = C(232, 222, 255), Saturation = -.35, Contrast = .14, Brightness = -.02 }, m.Late < 1.5 and 2.5 or .5, 4)
	m:Bloom(.5, 40, 1.05, 2, 3)
	m:Duck(.2, 1.5)
	local drone = m:Drone("Drone", .22, .5, 2.5)
	local atmo = sky and Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		m.Scope:Override(atmo, { Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare })
		m:Tween(atmo, 3, { Density = math.min(atmo.Density, .14), Haze = 0, Glare = 0 })
	end
	if m:Fresh(0, .6) then
		m:Cue("Rumble", nil, .5, 3)
	end

	-- the moon: a pale disc with craters, a faint halo; the black disc in front of it
	local moon = m:Ball({ Name = "EclipseMoon", Color = MOON, Size = Vector3.one * R * 2, Position = SKY, Transparency = 1 })
	local halo = m:Ball({ Name = "EclipseHalo", Material = Enum.Material.ForceField, Color = LILAC, Size = Vector3.one * R * 2.9, Position = SKY, Transparency = 1 })
	local craters = {}
	for i, c in ipairs({ { -.35, .3, .3 }, { .32, -.28, .24 }, { .1, .45, .14 }, { -.42, -.2, .12 }, { .45, .15, .1 } }) do
		craters[i] = m:Part({ Name = "Crater", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = C(222, 200, 176),
			Size = Vector3.new(1, R * 2 * c[3], R * 2 * c[3]), Transparency = 1,
			CFrame = CFrame.new(SKY + Vector3.new(c[1] * R, c[2] * R, math.sqrt(math.max(0, 1 - c[1] * c[1] - c[2] * c[2])) * R + .5)) * CFrame.Angles(0, math.pi / 2, 0) })
	end
	local disc = m:Ball({ Name = "EclipseDisc", Material = Enum.Material.SmoothPlastic, Color = VOID, Size = Vector3.one * (R * 2 + 8), Position = SKY, Transparency = 1 })
	local diamond = m:Ball({ Name = "DiamondRing", Color = WHITE, Size = Vector3.one * 50, Position = SKY, Transparency = 1 })
	-- the corona: a violet ring and rays round the black disc (in the plane facing the island)
	local U, W = Vector3.xAxis, Vector3.yAxis
	local rays = {}
	for i = 1, low and 14 or 26 do
		local a = (i - 1) / (low and 14 or 26) * math.pi * 2
		rays[i] = { Part = m:Line(SKY, SKY + Vector3.new(0, 1, 0), i % 3 == 0 and LILAC or VIOLET, 6, { Name = "CoronaRay", Transparency = 1 }), A = a,
			Len = 70 + (i * 37 % 90), Freq = .8 + (i % 5) * .3 }
	end
	local ringParts = {}
	for i = 1, low and 16 or 32 do
		ringParts[i] = m:Part({ Name = "CoronaRing", Color = VIOLET, Size = Vector3.new(10, 10, 1), Transparency = 1 })
	end

	-- the stars: the same sky for every player (fixed seed), on a far dome
	local rng = Random.new(20261031)
	local stars = {}
	for i = 1, low and 40 or 110 do
		local az, el = rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(14, 80))
		local dir = Vector3.new(math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el))
		stars[i] = { Part = m:Ball({ Name = "Star", Color = i % 7 == 0 and LILAC or WHITE, Size = Vector3.one * rng:NextNumber(5, 11), Position = m.Center + dir * 1250,
			Transparency = 1 }), At = rng:NextNumber(1, 3.2), Freq = rng:NextNumber(1.5, 4), Phase = rng:NextNumber(0, 6) }
	end

	-- the silhouette: black, violet-rimmed, below the horizon until it rises
	local dog = m:SkyDog(HEIGHT, { Clip = "Idle", Fill = BLACK, FillAlpha = 0, Outline = VIOLET })
	local eyes = {}
	local dims = nil
	local function feet(rise: number): CFrame
		return CFrame.lookAt(FEET - Vector3.new(0, HEIGHT * 1.1 * (1 - rise), 0), FEET - Vector3.new(0, HEIGHT * 1.1 * (1 - rise), 0) + face)
	end
	if dog then
		dims = dog.Size
		dog:Pivot(feet(0) * CFrame.new(-dog.Ground))
		dog:SetAlpha(0)
		for i = 1, 2 do
			eyes[i] = m:Ball({ Name = "Eye", Color = VIOLET, Size = Vector3.one * math.max(8, dims.Y * .035), Transparency = 1 })
		end
	end

	-- the Buried Moon over the Dead Yard (BloodMoonFX) goes dark too, wherever it shows
	local fxFolder = workspace:FindFirstChild("DOGROTS_HalloweenFX")
	local hwMoon = fxFolder and fxFolder:FindFirstChild("HalloweenMoon")
	local hwCore = hwMoon and hwMoon:FindFirstChild("MoonCore")
	local hwShade = hwCore and m:Ball({ Name = "BuriedMoonShade", Material = Enum.Material.SmoothPlastic, Color = VOID, Size = Vector3.one, Transparency = 1 })
	local hwRim = hwCore and m:Ball({ Name = "BuriedMoonCorona", Material = Enum.Material.ForceField, Color = VIOLET, Size = Vector3.one, Transparency = 1 })

	local released = false
	local function release()
		if released then
			return
		end
		released = true
		if sky then
			sky.Release()
		end
		m:Tween(grade, 5, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE })
		if drone then
			m:Tween(drone, 4, { Volume = 0 })
		end
	end
	m:Every(function()
		local t = m:Elapsed()
		local show = smooth(t / 1.2) * (1 - smooth((t - 22) / 4))
		-- the black disc: contact -> totality -> third contact
		local cover = smooth((t - CONTACT) / (TOTAL - CONTACT)) - smooth((t - THIRD) / 3)
		local side = t < THIRD and -1 or 1
		local discPos = SKY + face * 18 + Vector3.new(side * (1 - cover) * R * 2.3, (1 - cover) * R * .35 * -side, 0)
		disc.CFrame = CFrame.new(discPos)
		disc.Transparency = show > .01 and 0 or 1
		moon.Transparency = 1 - show
		halo.Transparency = 1 - show * (.2 + .25 * (1 - cover))
		for _, c in ipairs(craters) do
			c.Transparency = 1 - show * .6
		end
		-- totality: corona + diamond ring
		local corona = smooth((t - TOTAL + .15) / .35) * (1 - smooth((t - THIRD) / 1.5)) * show
		local flare = t >= TOTAL and math.exp(-(t - TOTAL) * 1.4) or 0
		for _, r in ipairs(rays) do
			local a = r.A + t * .05
			local len = (r.Len + 40 * math.sin(t * r.Freq + r.A * 3)) * (1 + 1.4 * flare)
			local dir = U * math.cos(a) + W * math.sin(a)
			local p0 = SKY + face * 20 + dir * (R + 6)
			m:SetLine(r.Part, p0, p0 + dir * len, 6 + 8 * flare)
			r.Part.Transparency = 1 - .8 * corona
		end
		local rr = R + 10 + 6 * math.sin(t * 2)
		for i, p in ipairs(ringParts) do
			local a0, a1 = (i - 1) / #ringParts * math.pi * 2, i / #ringParts * math.pi * 2
			local q0 = SKY + face * 19 + U * math.cos(a0) * rr + W * math.sin(a0) * rr
			local q1 = SKY + face * 19 + U * math.cos(a1) * rr + W * math.sin(a1) * rr
			p.Size = Vector3.new(14 + 10 * flare, 14 + 10 * flare, (q1 - q0).Magnitude * 1.08)
			p.CFrame = Kit.LookAt((q0 + q1) / 2, q1)
			p.Color = VIOLET:Lerp(WHITE, .35 * flare)
			p.Transparency = 1 - .85 * corona
		end
		local dr = math.exp(-math.max(0, t - TOTAL + .1) * 4) * smooth((t - TOTAL + .45) / .3)
		diamond.CFrame = CFrame.new(SKY + face * 30 + (U * -.72 + W * .68) * R)
		diamond.Size = Vector3.one * (40 + 120 * dr)
		diamond.Transparency = 1 - dr
		-- stars come out as the light dies, twinkle, fade with the morning
		local starsVis = smooth((t - 1) / 2.5) * (1 - smooth((t - LIFT) / 4))
		for _, s in ipairs(stars) do
			local v = smooth((t - s.At) / 2) * starsVis
			s.Part.Transparency = v > 0 and 1 - v * (.5 + .4 * math.sin(t * s.Freq + s.Phase)) or 1
		end
		-- the silhouette rises against the corona, the eyes open, it sinks with the morning
		if dog then
			local rise = smooth((t - TOTAL) / 3) * (1 - smooth((t - THIRD) / 5))
			dog:Pivot(feet(rise) * CFrame.new(-dog.Ground))
			dog:SetAlpha(math.min(1, rise * 1.5))
			local open = smooth((t - EYES) / .25) * (1 - smooth((t - THIRD) / 2)) * (math.sin(t * 2.7) > .97 and .2 or 1)
			local headY = FEET.Y - HEIGHT * 1.1 * (1 - rise) + dims.Y * .78
			for i, e in ipairs(eyes) do
				e.CFrame = CFrame.new(FEET.X + (i == 1 and -1 or 1) * dims.X * .12, headY, FEET.Z + dims.Z * .42)
				e.Transparency = 1 - open
			end
		end
		-- the Buried Moon: a black disc slides over it on the same beats, a violet rim at totality
		if hwShade and hwCore and hwCore.Parent then
			local camera = workspace.CurrentCamera
			local camPos = camera and camera.CFrame.Position or hwCore.Position
			local toCam = camPos - hwCore.Position
			toCam = toCam.Magnitude > .01 and toCam.Unit or Vector3.zAxis
			local right = toCam:Cross(Vector3.yAxis)
			right = right.Magnitude > .01 and right.Unit or Vector3.xAxis
			local d = hwCore.Size.X
			local visible = hwCore.Transparency < .95
			hwShade.Size = Vector3.one * d * 1.03
			hwShade.CFrame = CFrame.new(hwCore.Position + toCam * d * .6 + right * (1 - cover) * d * 1.15 * side)
			hwShade.Transparency = (visible and show > .01) and 0 or 1
			hwRim.Size = Vector3.one * d * 1.22
			hwRim.CFrame = CFrame.new(hwCore.Position + toCam * d * .4)
			hwRim.Transparency = visible and 1 - .7 * corona or 1
		end
		if t >= LIFT and not released then
			release()
		end
		return true
	end)

	-- 3.0: TOTALITY
	if not m:Wait(TOTAL - .2) then
		return
	end
	if m:Fresh(TOTAL - .2, 1) then
		m:Cue("Heartbeat", nil, .7)
	end
	if not m:Wait(TOTAL) then
		return
	end
	if m:Fresh(TOTAL, 1.2) then
		m:Cue("Sting", nil, .6)
		m:Cue("Boom", nil, .55)
		m:Burst(SKY + face * 40 + (U * -.72 + W * .68) * R, WHITE, 60, { Speed = NumberRange.new(30, 90), Lifetime = NumberRange.new(.6, 1.4),
			Size = NumberSequence.new(8, 0) })
		m:Flash(VIOLET, .55 + .3 * m:Near(220), .6)
		m:Pillar(base, 700, VIOLET, 18, 4.5)
		m:Shockwave(Vector3.new(base.X, m:Ground(m.Center).Y, base.Z), VIOLET, { Speed = 280, Radius = m.Radius + 420, Height = 26, Thickness = 1.8, Alpha = .15,
			OnPass = function()
				m:Cue("Heartbeat", nil, .5)
				m:Flash(VIOLET, .82, .4)
				m:Shake(.16, .4)
				m:FOV(-3, .1, .7)
			end })
		m:Ring(SKY + face * 25, LILAC, R, R * 3.2, 1.8, { U = U, W = W, Thickness = 8, Alpha = .1, Segments = 36 })
	end
	-- the motes: dark violet sparks falling around every player
	local fall = m:FollowRain({ Rate = 32, Texture = Kit.Textures.Spark, Color = ColorSequence.new(LILAC, VIOLET), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.2, 1), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(5, 10), Lifetime = NumberRange.new(6, 9), RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, .2), NumberSequenceKeypoint.new(1, 1) }) }, 70)
	-- 4.0: the eyes open, the banner
	if not m:Wait(EYES) then
		return
	end
	if dog and m:Fresh(EYES, 1.5) then
		dog:Play("Howl", false) -- its signature clip: the colossus howls at the dead moon
	end
	if m:Fresh(EYES, 1.5) then
		m:Cue("Chime", nil, .4)
		m:Banner(m.Config.Title, { Kicker = "✦  THE MOON WENT OUT  ✦", Sub = m.VenueText .. (m.By and ("  ·  " .. string.upper(m.By)) or ""),
			Font = Enum.Font.FredokaOne, Color = m.Color, Hold = 5.5, Shake = .1 })
	end
	if not m:Wait(14) then
		return
	end
	fall.Rate = 0
	-- 17: the disc slides off, the morning comes back
	if not m:Wait(THIRD) then
		return
	end
	if m:Fresh(THIRD, 1.5) then
		m:Cue("Whoosh", nil, .35)
	end
	m:Wait(m.Config.MegaSeconds or 28)
end
