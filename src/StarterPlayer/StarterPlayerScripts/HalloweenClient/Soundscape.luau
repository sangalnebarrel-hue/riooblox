-- NIGHT OF THE BURIED MOON — soundscape (StarterPlayerScripts.HalloweenClient.Soundscape). WP10a.
-- * Music: the procedural OST (RS.Halloween.Music) — NIGHT anywhere at night, ZONE always inside THE DEAD YARD,
--   BLOOD_WARN (accelerating heartbeat, anchored to the warning) / BLOOD_MOON during a Blood Moon (in or near the yard, or
--   anywhere at night), BOSS while the Gravekeeper fight runs (Enrage layer at phase 5). 3 s crossfades (8 s when the moon
--   sets). Priority: an audible uploaded world-event track > boss > Blood Moon > zone > night > the island's own music.
-- * Suppression of the island's music while Halloween owns it: WorldEventAudio.SetSuppressed("Halloween", on) and the
--   client attribute SoundService.DOGROTS_MusicOwner = "HALLOWEEN" (WorldAmbience patch). Player attribute Music == false
--   (Settings MUSIC: OFF) silences the OST here; the island's tracks honour it themselves (WorldEventAudio, WorldAmbience),
--   so the setting works without the event too. SoundGroup.Volume is never touched.
-- * Ambience beds (Audio.Loop): WindBed (2D, zone / night), GraveAmbience (graveyard), FireCrackle (nearest brazier or the
--   cauldron fire), RedRain + BloodMoonAmbience (Blood Moon). (CauldronFX owns the CauldronBubbles bed.)
-- * Positional one-shots with sensible rates (scaled by Config.Quality[q].Ambient): Howl (far off over the cliffs),
--   ChainRattle (ChainPoint / gate chains), Whisper (behind the listener), CoffinKnock (under the graves), Owl (night);
--   CrowCaw / GhostWoo only as a fallback when AmbientFX (which animates the crows and ghosts and voices them) is absent.
-- API: Soundscape.Theme() -> current music theme | nil; Soundscape.Rates (tunable); Soundscape.Stop().
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local M = {}
M.Rates = { -- seconds between one-shots {min, max} (divided by Config.Quality[q].Ambient)
	Howl = { 35, 80 }, CrowCaw = { 16, 36 }, ChainRattle = { 24, 50 }, Whisper = { 34, 75 }, GhostWoo = { 38, 85 },
	CoffinKnock = { 55, 110 }, Owl = { 40, 90 },
}
M.Fade = { Default = 3, MoonSets = 8, MoonRises = 1.2, Boss = 2 }

local BOSS_OFF = { Idle = true, Defeated = true, Escaped = true, Ended = true, Dead = true, Reward = true, Cooldown = true, Done = true }

local running = false
local current = nil
local beds = {}
local suppressed = {}
local WEA = nil
local Music = nil

function M.Theme(): string?
	return current
end

local function setSuppressed(reason: string, on: boolean)
	if (suppressed[reason] == true) == on then
		return
	end
	suppressed[reason] = on or nil
	if WEA and type(WEA.SetSuppressed) == "function" then
		pcall(WEA.SetSuppressed, reason, on)
	end
end

local function setOwner(on: boolean)
	local want = on and "HALLOWEEN" or nil
	if SoundService:GetAttribute("DOGROTS_MusicOwner") ~= want then
		SoundService:SetAttribute("DOGROTS_MusicOwner", want)
	end
end

local function stopBed(name: string, fade: number?)
	local b = beds[name]
	if b then
		beds[name] = nil
		pcall(function()
			b.Handle:Stop(fade or 1.5)
		end)
	end
end

function M.Stop()
	running = false
	if Music then
		Music.SetTheme(nil, { Fade = 2 })
		Music.Stop(2)
	end
	current = nil
	for name in pairs(beds) do
		stopBed(name, 1)
	end
	setSuppressed("Halloween", false)
	setOwner(false)
end

function M.Start(ctx)
	local Shared, Layout, Audio = ctx.Shared, ctx.Layout, ctx.Audio
	if not Shared.Enabled() or running then
		return
	end
	running = true
	local player = ctx.Player or Players.LocalPlayer
	Music = require(RS:WaitForChild("Halloween"):WaitForChild("Music"))
	Music.Start()
	pcall(function()
		local we = RS:WaitForChild("WorldEvents", 20)
		local mod = we and we:WaitForChild("WorldEventAudio", 10)
		if mod then
			WEA = require(mod) -- the same table WorldEventController uses
		end
	end)
	if WEA and type(WEA.SetSuppressed) ~= "function" then
		warn("Halloween Soundscape: WorldEventAudio.SetSuppressed missing (patch not applied); main music cannot be suppressed")
	end
	local weState = RS:FindFirstChild("WorldEvents") and RS.WorldEvents:FindFirstChild("State")
	local hwState = RS.Halloween:FindFirstChild("State")
	local bossFolder = hwState and hwState:FindFirstChild("Boss")

	-- markers in the Dead Yard (streamed: register as they arrive)
	local marks = { CrowPerch = {}, ChainPoint = {}, GhostPath = {}, Brazier = {} }
	local function classify(d: Instance): string?
		if d:IsA("Attachment") then
			if d.Name == "CrowPerch" then
				return "CrowPerch"
			elseif d.Name == "ChainPoint" then
				return "ChainPoint"
			elseif string.sub(d.Name, 1, 10) == "GhostPath_" then
				return "GhostPath"
			end
		elseif d:IsA("BasePart") and d:GetAttribute("HwBrazier") then
			return "Brazier"
		end
		return nil
	end
	local function addMark(d: Instance)
		local kind = classify(d)
		if kind then
			marks[kind][d] = true
		end
	end
	local function removeMark(d: Instance)
		for _, set in pairs(marks) do
			set[d] = nil
		end
	end
	task.spawn(function()
		local district = workspace:WaitForChild("DOGROTS_District", 60)
		local yard = district and district:WaitForChild("38_DeadYard", 120)
		if not yard then
			return
		end
		for _, d in ipairs(yard:GetDescendants()) do
			addMark(d)
		end
		yard.DescendantAdded:Connect(addMark)
		yard.DescendantRemoving:Connect(removeMark)
	end)
	local function markPos(d: Instance): Vector3?
		if d:IsA("Attachment") then
			local p = d.Parent
			return (p and p:IsA("BasePart")) and (p.CFrame * d.CFrame).Position or d.WorldPosition
		elseif d:IsA("BasePart") then
			return d.CFrame.Position
		end
		return nil
	end
	local function nearestMarks(kind: string, from: Vector3, range: number, maxN: number?): { Vector3 }
		local out = {}
		for d in pairs(marks[kind]) do
			if d.Parent then
				local p = markPos(d)
				if p and (p - from).Magnitude <= range then
					table.insert(out, p)
				end
			end
		end
		if maxN and #out > maxN then
			table.sort(out, function(a, b)
				return (a - from).Magnitude < (b - from).Magnitude
			end)
			for i = #out, maxN + 1, -1 do
				out[i] = nil
			end
		end
		return out
	end

	local function bed(name: string, cue: string, where: any, volume: number)
		local b = beds[name]
		if volume <= .015 then
			if b then
				stopBed(name, 1.5)
			end
			return
		end
		if b and b.Where ~= where then
			stopBed(name, 1.2)
			b = nil
		end
		if not b then
			local h = Audio.Loop(cue, where, { Volume = 1 })
			h:SetVolume(0)
			b = { Handle = h, Where = where, Volume = 0 }
			beds[name] = b
		end
		if math.abs(b.Volume - volume) > .02 then
			b.Volume = volume
			b.Handle:SetVolume(volume, .4)
		end
	end

	-- one-shot timers
	local rng = Random.new()
	local nextAt = {}
	local function due(kind: string, now: number, factor: number): boolean
		local r = M.Rates[kind]
		if not nextAt[kind] then
			nextAt[kind] = now + rng:NextNumber(r[1], r[2]) * .5 / factor
			return false
		end
		if now < nextAt[kind] then
			return false
		end
		nextAt[kind] = now + rng:NextNumber(r[1], r[2]) / math.max(.15, factor)
		return true
	end

	local zoneIn, nightOn = false, false
	local lastBossLayer = -1
	local GRAVE = Vector3.new((Layout.Graveyard.X0 + Layout.Graveyard.X1) / 2, 3, (Layout.Graveyard.Z0 + Layout.Graveyard.Z1) / 2)
	local CAULDRON_FIRE = Layout.Cauldron.Center + Vector3.new(0, 1, 0)
	local gateFires = { Layout.Gate.PillarL + Vector3.new(-2, 9, 0), Layout.Gate.PillarR + Vector3.new(-2, 9, 0) }

	local function tick()
		local now = Shared.Now()
		local clock = os.clock()
		if not Shared.Enabled() then
			M.Stop()
			return
		end
		local cam = workspace.CurrentCamera
		local listener = cam and cam.CFrame.Position or Vector3.zero
		local root = ctx.State and ctx.State.Root() or nil
		local pos = root and root.CFrame.Position or listener
		-- zone (HRP; hysteresis) / night (Lighting weights; hysteresis)
		local zw = Layout.Weight(pos, 40)
		if zoneIn and zw < .2 then
			zoneIn = false
		elseif not zoneIn and zw > .6 then
			zoneIn = true
		end
		local near = Layout.Weight(pos, 130) > .05 -- the boulevard by the gate / the lab side (the spawn is ~154 studs away)
		local lw = ctx.Modules and ctx.Modules.Lighting and ctx.Modules.Lighting.Weights and ctx.Modules.Lighting.Weights()
		local nightW = lw and lw.Active and lw.Night or nil
		if nightW == nil then
			local day = game:GetService("Lighting"):GetAttribute("DayFactor")
			nightW = type(day) == "number" and (1 - math.clamp((day - .05) / .45, 0, 1)) or 0
		end
		if nightOn and nightW < .3 then
			nightOn = false
		elseif not nightOn and nightW > .55 then
			nightOn = true
		end
		local bm = Shared.BloodMoonState(now)
		local bmAlpha = Shared.BloodMoonAlpha(now, bm)
		local bossState = bossFolder and bossFolder:GetAttribute("State")
		local bossPhase = bossFolder and bossFolder:GetAttribute("Phase") or 0
		local boss = type(bossPhase) == "number" and bossPhase >= 1 and not BOSS_OFF[tostring(bossState)]
			and (zoneIn or Layout.InPit(pos))
		local musicOn = player:GetAttribute("Music") ~= false
		-- an uploaded world-event track that is really audible owns the music (a running event's track counts while it
		-- fades in, also from MUSIC: OFF: switching music back on then never blips the OST)
		local wes = weState and weState:GetAttribute("State")
		local eventAudible = false
		if wes == "ACTIVE" or wes == "ENDING" then
			local em = SoundService:FindFirstChild("DogrotsEventMusic")
			eventAudible = em ~= nil and em:IsA("Sound") and em.IsPlaying and em.TimeLength > 0
				and (em.Volume > .02 or (WEA ~= nil and WEA.Current ~= nil))
		end
		-- theme
		local theme, opts = nil, nil
		local reach = zoneIn or nightOn or near
		if not musicOn then
			theme = nil
		elseif boss then
			theme = "BOSS"
			opts = { Fade = M.Fade.Boss }
		elseif bm.State == "WARNING" and reach then
			theme = "BLOOD_WARN"
			opts = { Elapsed = math.max(0, now - (bm.WarningTimestamp or now)) }
		elseif bm.State == "ACTIVE" and reach then
			theme = "BLOOD_MOON"
			opts = { Fade = current == "BLOOD_WARN" and M.Fade.MoonRises or M.Fade.Default }
		elseif zoneIn then
			theme = "ZONE"
		elseif nightOn then
			theme = "NIGHT"
		end
		if theme ~= "BLOOD_MOON" and current == "BLOOD_MOON" and bm.State == "ENDING" then
			opts = { Fade = M.Fade.MoonSets }
		end
		if theme ~= current then
			current = theme
			Music.SetTheme(theme, opts)
		end
		if theme == "BOSS" then
			local layer = bossPhase == 5 and 1 or 0
			if layer ~= lastBossLayer then
				lastBossLayer = layer
				Music.SetLayer("BOSS", "Enrage", layer)
			end
		end
		Music.SetMaster(eventAudible and 0 or 1)
		setSuppressed("Halloween", theme ~= nil)
		setOwner(theme ~= nil)

		-- ambience beds
		local q = Shared.Budget("Ambient")
		if q <= 0 then
			q = .35
		end
		local camZone = Layout.Weight(listener, 40)
		bed("Wind", "WindBed", nil, math.clamp(camZone + (nightOn and .3 or 0) * (1 - camZone) * (near and 1 or .5), 0, 1))
		local dGrave = (listener - GRAVE).Magnitude
		bed("Grave", "GraveAmbience", GRAVE, (dGrave < (beds.Grave and 170 or 150)) and 1 or 0)
		-- nearest fire: streamed-in braziers (HwBrazier) else the gate pillars, or the cauldron fire
		local fires = nearestMarks("Brazier", listener, 80, 6)
		if #fires == 0 then
			for _, p in ipairs(gateFires) do
				if (p - listener).Magnitude < 80 then
					table.insert(fires, p)
				end
			end
		end
		if (CAULDRON_FIRE - listener).Magnitude < 80 then
			table.insert(fires, CAULDRON_FIRE)
		end
		local best, bestD = nil, math.huge
		for _, p in ipairs(fires) do
			local d = (p - listener).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
		if best and beds.Fire and (beds.Fire.Where - best).Magnitude < 2 then
			best = beds.Fire.Where -- same source (avoid restarting on tiny moves)
		end
		bed("Fire", "FireCrackle", best, best and 1 or 0)
		local bmActive = bm.State == "ACTIVE" or bm.State == "ENDING"
		bed("RedRain", "RedRain", nil, bmActive and bmAlpha * camZone or 0)
		bed("BloodAmb", "BloodMoonAmbience", nil, bmActive and bmAlpha * math.max(camZone, near and .3 or 0) or 0)

		-- one-shots
		local inside = camZone > .5
		local rate = q * (bmActive and 1.5 or 1)
		if (inside or (nightOn and near)) and due("Howl", clock, rate) then
			local a = rng:NextNumber(-.35, 1.9) -- mostly east / south: the cliffs and the void
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local at = listener + dir * rng:NextNumber(170, 260) + Vector3.new(0, 30, 0)
			Audio.Play("Howl", at, { Volume = rng:NextNumber(.7, 1), Pitch = rng:NextNumber(.92, 1.08) })
			if rng:NextNumber() < .35 then
				Audio.Play("Howl", at + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40)),
					{ Volume = .65, Pitch = 1.19, Delay = rng:NextNumber(.5, .9) })
			end
		end
		local ambientFX = ctx.Modules and ctx.Modules.AmbientFX ~= nil
		if inside and not ambientFX and due("CrowCaw", clock, rate) then
			local perches = nearestMarks("CrowPerch", listener, 70)
			local at = #perches > 0 and perches[rng:NextInteger(1, #perches)] or nil
			if at then
				Audio.Play("CrowCaw", at, { Volume = rng:NextNumber(.7, 1) })
			end
		end
		if inside and due("ChainRattle", clock, rate) then
			local pts = nearestMarks("ChainPoint", listener, 60)
			if #pts == 0 and (Layout.Gate.Center - listener).Magnitude < 60 then
				pts = { Layout.Gate.Center + Vector3.new(0, 12, rng:NextNumber(-8, 8)) }
			end
			if #pts > 0 then
				Audio.Play("ChainRattle", pts[rng:NextInteger(1, #pts)], { Volume = rng:NextNumber(.6, .9) })
			end
		end
		if inside and cam and due("Whisper", clock, rate) then
			local at = (cam.CFrame * CFrame.new(rng:NextNumber(-6, 6), rng:NextNumber(-1, 2), rng:NextNumber(8, 14))).Position
			Audio.Play("Whisper", at, { Volume = rng:NextNumber(.6, .9) })
		end
		if inside and not ambientFX and due("GhostWoo", clock, rate) then
			local pts = nearestMarks("GhostPath", listener, 90)
			if #pts > 0 then
				Audio.Play("GhostWoo", pts[rng:NextInteger(1, #pts)] + Vector3.new(0, 3, 0), { Volume = rng:NextNumber(.6, .9) })
			end
		end
		if inside and dGrave < 75 and due("CoffinKnock", clock, rate) then
			local g = Layout.Graveyard
			local at = Vector3.new(rng:NextNumber(g.X0 + 4, g.X1 - 4), -1, rng:NextNumber(g.Z0 + 4, g.Z1 - 4))
			if (at - listener).Magnitude < 60 then
				Audio.Play("CoffinKnock", at, { Volume = .8 })
			end
		end
		if nightOn and (inside or near) and due("Owl", clock, rate) then
			local a = rng:NextNumber(0, math.pi * 2)
			Audio.Play("Owl", listener + Vector3.new(math.cos(a) * 70, 25, math.sin(a) * 70), { Volume = .7 })
		end
	end

	task.spawn(function()
		while running do
			local ok, err = pcall(tick)
			if not ok and not M.Warned then
				M.Warned = true
				warn("Halloween Soundscape tick failed: " .. tostring(err))
			end
			task.wait(.25)
		end
	end)
	-- the Music setting reacts at once
	player:GetAttributeChangedSignal("Music"):Connect(function()
		if running then
			pcall(tick)
		end
	end)
end

return M
