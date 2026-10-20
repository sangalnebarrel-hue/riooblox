-- HOLLOW KING, world-wide: "THE HOLLOW KING RISES" (StarterPlayer.StarterPlayerScripts.SecretArrivals.Mega.HW_HollowKing,
-- WP-K1; the base Mega runner calls it on every client with the context m: Sky, Grade, Bloom, Banner, Shockwave, SkyDog,
-- FollowRain, Ring, Pillar, Every, Wait, Fresh...).
-- Each client stages it where it stands: on the island the set piece hangs high beyond the giant head (the island faces
-- it); a player down in THE UNDERYARD sees it over the Black Bell Arena at the south end of the cavern instead.
-- 0.3 the light dies and the music is cut. 1.0 a colossal black moon rises with one pale sliver of light on its limb,
-- violet motes of moth-ash start falling around every player. 3.2 TOTALITY (the stage's beat): the sliver is swallowed,
-- a violet corona blazes out, a ring of violet light sweeps the world from the arrival, and the colossal ink silhouette
-- of the Hollow King rises against the moon. 4.2 a crown of violet fire ignites over its head, it plays its Coronation
-- and the banner names who raised it. From 17 the moon sinks and the light comes back.
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = C(8, 4, 16)
local VIOLET = C(150, 80, 230)
local LILAC = C(218, 176, 255)
local MOON = C(190, 216, 255)
local DIM, RISE, TOTAL, CROWN, SINK = .3, 1.0, 3.2, 4.2, 17
-- where the set piece stands for a viewer on the island / in the Underyard cavern
local STAGES = {
	Island = { Sky = Vector3.new(-90, 560, -880), R = 160, Feet = Vector3.new(-90, 0, -1160), Height = 500, Face = Vector3.new(0, 0, 1) },
	Underyard = { Sky = Vector3.new(0, 112, 2800), R = 42, Feet = Vector3.new(0, -4, 2768), Height = 118, Face = Vector3.new(0, 0, -1) },
}
-- the line under the banner: where it was raised (SecretReveal venues of Chapter II)
local VENUES = { Coffin = "FROM THE BLACK COFFIN", RareRoom = "BEHIND A CROOKED DOOR", Finale = "AFTER THE LAST BARK", Underyard = "IN THE UNDERYARD" }
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function inUnderyard(position: Vector3): boolean
	local ok, inside = pcall(function()
		local halloween = RS:FindFirstChild("Halloween")
		local module = halloween and halloween:FindFirstChild("UnderyardLayout")
		return module ~= nil and require(module).InZone(position, 80)
	end)
	return ok and inside == true
end

return function(m)
	local low = m.Low
	local Kit = m.Kit
	local stage = inUnderyard(m:Camera()) and STAGES.Underyard or STAGES.Island
	local SKY, R, FEET, HEIGHT, face = stage.Sky, stage.R, stage.Feet, stage.Height, stage.Face
	local base = m.Venue == "Tongue" and m.Stage or m:Ground(m.Origin)
	local U = face:Cross(Vector3.yAxis).Unit
	local W = Vector3.yAxis

	-- the light dies; the music is cut
	local sky = m:Sky({ ClockTime = 0, Brightness = .12, Ambient = C(20, 12, 34), OutdoorAmbient = C(30, 18, 50), ExposureCompensation = -.25 }, 2, 5)
	local grade = m:Grade({ TintColor = C(226, 212, 255), Saturation = -.5, Contrast = .16, Brightness = -.04 }, m.Late < 1.5 and 2 or .5, 4)
	m:Bloom(.55, 40, 1.0, 2, 3)
	m:Duck(.08, 1.2)
	local drone = m:Drone("Choir", .24, .42, 2.5)
	local atmo = sky and Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		m.Scope:Override(atmo, { Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare })
		m:Tween(atmo, 3, { Density = math.min(atmo.Density, .16), Haze = 0, Glare = 0 })
	end
	if m:Fresh(DIM, .6) then
		m:Cue("Rumble", nil, .55, 3)
	end

	-- the black moon, its violet halo, the sliver of last light and the corona
	local moon = m:Ball({ Name = "HollowMoon", Material = Enum.Material.SmoothPlastic, Color = INK, Size = Vector3.one * R * 2, Position = SKY, Transparency = 1 })
	local halo = m:Ball({ Name = "HollowHalo", Material = Enum.Material.ForceField, Color = VIOLET, Size = Vector3.one * R * 2.8, Position = SKY, Transparency = 1 })
	local sliver = m:Ball({ Name = "HollowLastLight", Color = MOON, Size = Vector3.one * R * 2.03, Position = SKY, Transparency = 1 })
	local rays = {}
	for i = 1, low and 14 or 24 do
		rays[i] = { Part = m:Line(SKY, SKY + Vector3.yAxis, i % 3 == 0 and LILAC or VIOLET, R * .04, { Name = "HollowRay", Transparency = 1 }),
			A = (i - 1) / (low and 14 or 24) * math.pi * 2, Len = R * (.45 + (i * 37 % 60) / 100), Freq = .7 + (i % 5) * .3 }
	end
	-- the crown of fire over the silhouette's head
	local tongues = {}
	for i = 1, low and 8 or 14 do
		tongues[i] = m:Part({ Name = "HollowCrownFire", Color = i % 2 == 0 and VIOLET or LILAC, Size = Vector3.new(4, 10, 4), Transparency = 1 })
	end

	-- the colossal silhouette: ink, violet-rimmed, below the horizon until totality
	local dog = m:SkyDog(HEIGHT, { Clip = "Idle", Fill = BLACK, FillAlpha = 0, Outline = VIOLET })
	local dims = dog and dog.Size or Vector3.new(HEIGHT * .5, HEIGHT, HEIGHT)
	local function feet(rise: number): CFrame
		local at = FEET - Vector3.new(0, HEIGHT * 1.1 * (1 - rise), 0)
		return CFrame.lookAt(at, at + face)
	end
	if dog then
		dog:Pivot(feet(0) * CFrame.new(-dog.Ground))
		dog:SetAlpha(0)
	end

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
		local show = smooth((t - RISE) / 1.6) * (1 - smooth((t - SINK - 3) / 4))
		local lift = (1 - smooth((t - RISE) / 2.2)) * R * 2.4 + smooth((t - SINK) / 5) * R * 2.8
		local center = SKY - Vector3.new(0, lift, 0)
		moon.CFrame = CFrame.new(center + face * 6)
		moon.Transparency = show > .01 and 1 - show or 1
		local cover = smooth((t - RISE) / (TOTAL - RISE))
		sliver.CFrame = CFrame.new(center - face * 4 + U * (1 - cover) * R * .2 + W * (1 - cover) * R * .06)
		sliver.Transparency = (show > .01 and cover < .999) and 1 - show or 1
		local flare = t >= TOTAL and math.exp(-(t - TOTAL) * 1.3) or 0
		halo.CFrame = CFrame.new(center)
		halo.Transparency = 1 - show * (.2 + .3 * flare)
		local corona = smooth((t - TOTAL + .15) / .35) * (1 - smooth((t - SINK) / 1.5)) * show
		for _, r in ipairs(rays) do
			local a = r.A + t * .05
			local len = (r.Len + R * .2 * math.sin(t * r.Freq + r.A * 3)) * (1 + 1.3 * flare)
			local dir = U * math.cos(a) + W * math.sin(a)
			local p0 = center + face * 8 + dir * (R * 1.04)
			m:SetLine(r.Part, p0, p0 + dir * len, R * (.035 + .05 * flare))
			r.Part.Transparency = 1 - .8 * corona
		end
		-- the silhouette rises against the moon, crowned in fire from CROWN, sinks with the morning
		local rise = smooth((t - TOTAL) / 3) * (1 - smooth((t - SINK) / 5))
		if dog then
			dog:Pivot(feet(rise) * CFrame.new(-dog.Ground))
			dog:SetAlpha(math.min(1, rise * 1.5))
		end
		local crown = smooth((t - CROWN) / .5) * (1 - smooth((t - SINK) / 2)) * math.min(1, rise * 1.5)
		local headAt = FEET - Vector3.new(0, HEIGHT * 1.1 * (1 - rise), 0) + face * dims.Z * .28 + W * dims.Y * .86
		local ringR = dims.X * .14
		for i, tongue in ipairs(tongues) do
			local a = (i - 1) / #tongues * math.pi * 2 + t * .9
			local h = HEIGHT * (.07 + .04 * math.sin(t * 9 + i * 1.7)) * (1 + .8 * math.exp(-math.max(0, t - CROWN) * 2))
			local w = HEIGHT * .022
			tongue.Size = Vector3.new(w, h, w)
			tongue.CFrame = CFrame.new(headAt + U * math.cos(a) * ringR + face * math.sin(a) * ringR * .6 + W * h / 2) * CFrame.Angles(0, 0, .1 * math.sin(t * 5 + i))
			tongue.Transparency = 1 - .9 * crown
		end
		if t >= SINK + 1 and not released then
			release()
		end
		return true
	end)

	-- 3.2: TOTALITY
	if not m:Wait(TOTAL - .25) then
		return
	end
	if m:Fresh(TOTAL - .25, 1) then
		m:Cue("Heartbeat", nil, .75)
	end
	if not m:Wait(TOTAL) then
		return
	end
	if m:Fresh(TOTAL, 1.2) then
		m:Cue("Sting", nil, .6)
		m:Cue("Boom", nil, .55)
		m:Flash(VIOLET, .55 + .3 * m:Near(220), .6)
		m:Pillar(base, 700, VIOLET, 16, 4.5)
		m:Shockwave(Vector3.new(base.X, m:Ground(base).Y, base.Z), VIOLET, { Speed = 280, Radius = m.Radius + 420, Height = 24, Thickness = 1.6, Alpha = .15,
			OnPass = function()
				m:Cue("Heartbeat", nil, .5)
				m:Flash(VIOLET, .82, .4)
				m:Shake(.15, .4)
				m:FOV(-3, .1, .7)
			end })
		m:Ring(SKY + face * 10, LILAC, R, R * 3.2, 1.8, { U = U, W = W, Thickness = R * .05, Alpha = .1, Segments = 36 })
	end
	-- moth-ash: violet motes falling round every player
	local fall = m:FollowRain({ Rate = 30, Texture = Kit.Textures.Spark, Color = ColorSequence.new(LILAC, VIOLET), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.2, 1), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(4, 9), Lifetime = NumberRange.new(6, 9), RotSpeed = NumberRange.new(-80, 80), Rotation = NumberRange.new(0, 360),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, .2), NumberSequenceKeypoint.new(1, 1) }) },
		stage == STAGES.Underyard and 40 or 70)
	-- 4.2: the crown of fire, the Coronation, the banner
	if not m:Wait(CROWN) then
		return
	end
	if m:Fresh(CROWN, 1.5) then
		if dog then
			dog:Play("Coronation", false) -- its signature clip: the colossus is crowned
		end
		m:Cue("Chime", nil, .45)
		m:Cue("Boom", nil, .3)
		local kicker = m.By and ("✦  " .. string.upper(m.By) .. " RAISED THE HOLLOW KING  ✦") or "✦  THE HOLLOW KING RISES  ✦"
		m:Banner(m.Config.Title, { Kicker = kicker, Sub = VENUES[m.Venue or ""] or m.VenueText, Font = Enum.Font.FredokaOne, Color = m.Color, Hold = 6,
			Shake = .1 })
	end
	if not m:Wait(14) then
		return
	end
	fall.Rate = 0
	-- 17: the moon sinks, the morning comes back
	if not m:Wait(SINK) then
		return
	end
	if m:Fresh(SINK, 1.5) then
		m:Cue("Whoosh", nil, .35)
	end
	m:Wait(m.Config.MegaSeconds or 30)
end
