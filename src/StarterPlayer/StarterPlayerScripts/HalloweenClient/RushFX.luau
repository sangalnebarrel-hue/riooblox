-- NIGHT OF THE BURIED MOON — Candy Rush presentation (StarterPlayerScripts.HalloweenClient.RushFX). WP10a.
-- * Aura around EVERY character whose server attribute HwRushAura is set (personal rush while active, or a server rush in
--   the yard): wrapped candies orbiting at hip height with a bob, gold/orange sparkles and a soft orange light. Client
--   parts in FX.Folder(); one Heartbeat loop moves them all (BulkMoveTo). Budget: nearest auras High 12 / Medium 7 / Low 3
--   (the local player's always shows), hidden beyond 140 studs.
-- * Local rush start (player.HwRushActive false -> true): candy burst + ring + warm flash, RushStart cue, Bus Banner.
--   Last 10 s of the personal rush: a quiet RushTick each second. Server rush start (State.ServerRushUntil): burst + cue.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local M = {}
M.Max = { High = 12, Medium = 7, Low = 3 }
local C3 = Color3.fromRGB
local CANDY = { C3(255, 128, 24), C3(150, 70, 230), C3(120, 255, 110), C3(255, 92, 170), C3(255, 210, 70) }

function M.Start(ctx)
	local Shared, FX, Audio, Bus = ctx.Shared, ctx.FX, ctx.Audio, ctx.Bus
	if not Shared.Enabled() then
		return
	end
	local player = ctx.Player or Players.LocalPlayer
	local alive = true
	local conns = {}
	local auras = {} -- character -> aura
	local root = Instance.new("Model")
	root.Name = "HalloweenRushAuras"
	root.Parent = FX.Folder()

	local function buildAura(character: Model)
		local m = Instance.new("Model")
		m.Name = "RushAura"
		m.Parent = root
		local a = { Model = m, Parts = {}, Offsets = {}, Character = character, Shown = true, Phase = math.random() * 6 }
		local n = Shared.Low() and 3 or 5
		for i = 1, n do
			local col = CANDY[(i - 1) % #CANDY + 1]
			local body = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Size = Vector3.new(.5, .5, .5), Color = col,
				Material = Enum.Material.SmoothPlastic, Parent = m, Name = "Candy" })
			local twistA = FX.Part({ Class = "WedgePart", Size = Vector3.new(.08, .3, .26), Color = col:Lerp(Color3.new(1, 1, 1), .35),
				Material = Enum.Material.Neon, Parent = m, Name = "Wrap" })
			local twistB = FX.Part({ Class = "WedgePart", Size = Vector3.new(.08, .3, .26), Color = col:Lerp(Color3.new(1, 1, 1), .35),
				Material = Enum.Material.Neon, Parent = m, Name = "Wrap" })
			table.insert(a.Parts, body)
			table.insert(a.Offsets, { I = i, N = n, Kind = 0 })
			table.insert(a.Parts, twistA)
			table.insert(a.Offsets, { I = i, N = n, Kind = 1 })
			table.insert(a.Parts, twistB)
			table.insert(a.Offsets, { I = i, N = n, Kind = 2 })
		end
		local core = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, Parent = m, Name = "AuraCore" })
		a.Core = core
		local light = Instance.new("PointLight")
		light.Color = C3(255, 150, 60)
		light.Range = 10
		light.Brightness = 1.1
		light.Shadows = false
		light.Parent = core
		a.Light = light
		local e = Instance.new("ParticleEmitter")
		e.Texture = FX.Textures.Sparkle
		e.Color = ColorSequence.new(C3(255, 214, 90), C3(255, 120, 30))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = FX.Seq(.12, .3, 0)
		e.Transparency = NumberSequence.new(0, 1)
		e.Lifetime = NumberRange.new(.6, 1.1)
		e.Speed = NumberRange.new(.6, 1.6)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 1.5, 0)
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = ({ High = 7, Medium = 4, Low = 1.5 })[Shared.Quality()] or 4
		e.Parent = core
		a.Emitter = e
		return a
	end

	local function setShown(a, on: boolean)
		if a.Shown == on then
			return
		end
		a.Shown = on
		for _, p in ipairs(a.Parts) do
			p.Transparency = on and 0 or 1
		end
		a.Light.Enabled = on
		a.Emitter.Enabled = on
		a.Emitter:SetAttribute("HwGoverned", nil) -- the owner decides now (ParticleGovernor hands it back)
	end

	local function removeAura(character: Model)
		local a = auras[character]
		if a then
			auras[character] = nil
			-- fade: a little sparkle puff, then gone
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and a.Shown and not Shared.Low() then
				FX.Burst(hrp.CFrame.Position, { Color = C3(255, 200, 80), Color2 = C3(255, 120, 30), Count = 10, Speed = { 3, 6 }, Lifetime = { .4, .8 },
					Size = { .2, .35, 0 } })
			end
			a.Model:Destroy()
		end
	end

	local function watchCharacter(character: Model)
		local function refresh()
			if not alive then
				return
			end
			if character:GetAttribute("HwRushAura") and character.Parent then
				if not auras[character] then
					auras[character] = buildAura(character)
				end
			else
				removeAura(character)
			end
		end
		table.insert(conns, character:GetAttributeChangedSignal("HwRushAura"):Connect(refresh))
		table.insert(conns, character.AncestryChanged:Connect(function()
			if not character.Parent then
				removeAura(character)
			end
		end))
		refresh()
	end
	local function watchPlayer(p: Player)
		if p.Character then
			watchCharacter(p.Character)
		end
		table.insert(conns, p.CharacterAdded:Connect(watchCharacter))
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watchPlayer))

	-- animation (one loop for every aura)
	local list, cfs = {}, {}
	local budgetAcc = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				M.Stop()
				return
			end
			local cam = workspace.CurrentCamera
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			budgetAcc += dt
			if budgetAcc > .5 then -- nearest-N budget
				budgetAcc = 0
				local order = {}
				for character, a in pairs(auras) do
					local hrp = character:FindFirstChild("HumanoidRootPart")
					local d = hrp and (hrp.CFrame.Position - camPos).Magnitude or 1e9
					table.insert(order, { A = a, D = d, Mine = character == player.Character })
				end
				table.sort(order, function(x, y)
					if x.Mine ~= y.Mine then
						return x.Mine
					end
					return x.D < y.D
				end)
				local max = M.Max[Shared.Quality()] or 7
				for i, row in ipairs(order) do
					setShown(row.A, (row.Mine or i <= max) and row.D < 140)
				end
			end
			table.clear(list)
			table.clear(cfs)
			local t = os.clock()
			local reduced = Shared.ReducedMotion()
			local spin = reduced and .6 or 1.9
			for character, a in pairs(auras) do
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if a.Shown and hrp then
					local c = hrp.CFrame.Position
					table.insert(list, a.Core)
					table.insert(cfs, CFrame.new(c))
					for k, part in ipairs(a.Parts) do
						local o = a.Offsets[k]
						local ang = t * spin + a.Phase + (o.I - 1) / o.N * math.pi * 2
						local bob = reduced and 0 or math.sin(t * 2.4 + o.I * 1.3) * .35
						local pos = c + Vector3.new(math.cos(ang) * 2.8, -.4 + bob + (o.I % 2) * .5, math.sin(ang) * 2.8)
						local face = CFrame.new(pos) * CFrame.Angles(0, -ang, 0) * CFrame.Angles(t * 3 + o.I, 0, 0)
						if o.Kind == 1 then
							face = face * CFrame.new(.34, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
						elseif o.Kind == 2 then
							face = face * CFrame.new(-.34, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2)
						end
						table.insert(list, part)
						table.insert(cfs, face)
					end
				end
			end
			if #list > 0 then
				workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end)
		if not ok and not M.Warned then
			M.Warned = true
			warn("Halloween RushFX failed: " .. tostring(err))
		end
	end))

	-- local rush start / ticks
	local wasActive = player:GetAttribute("HwRushActive") == true
	local function burst()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		Audio.Play("RushStart", nil, { Volume = .9 })
		if hrp then
			local p = hrp.CFrame.Position
			FX.Burst(p, { Color = CANDY[1], Color2 = CANDY[5], Count = 30, Speed = { 8, 16 }, Lifetime = { .6, 1.2 }, Size = { .35, .6, 0 } })
			FX.Burst(p + Vector3.new(0, 1, 0), { Color = CANDY[2], Color2 = CANDY[4], Count = 16, Speed = { 5, 10 }, Lifetime = { .5, 1 } })
			FX.Ring(p - Vector3.new(0, 2.6, 0), CANDY[1], 9, .7)
			FX.Light(p, C3(255, 150, 60), 18, 3, .9)
		end
		FX.Flash(C3(255, 150, 60), .12, .45)
	end
	table.insert(conns, player:GetAttributeChangedSignal("HwRushActive"):Connect(function()
		local now = player:GetAttribute("HwRushActive") == true
		if now and not wasActive then
			burst()
			local minutes = math.floor((ctx.Config.CandyRush and ctx.Config.CandyRush.Seconds or 600) / 60 + .5)
			local mult = ctx.Config.CandyRush and ctx.Config.CandyRush.Mult or 2
			Bus.Fire("Banner", { Title = Shared.L(string.format("CANDY RUSH x%d", mult), string.format("КОНФЕТНАЯ ЛИХОРАДКА x%d", mult)),
				Subtitle = Shared.L(string.format("Double candy for %d minutes of active play", minutes),
					string.format("Двойные конфеты на %d минут активной игры", minutes)),
				Color = C3(255, 128, 24), Style = "Rush", Seconds = 3.5, NoTranslate = true })
		end
		wasActive = now
	end))
	local lastTick = -1
	table.insert(conns, player:GetAttributeChangedSignal("HwRushRemaining"):Connect(function()
		local left = player:GetAttribute("HwRushRemaining")
		if player:GetAttribute("HwRushActive") == true and type(left) == "number" and left <= 10 and left > 0 and left ~= lastTick then
			lastTick = left
			Audio.Play("RushTick", nil, { Volume = .6, Pitch = 1 + (10 - left) * .03 })
		end
	end))
	local hwState = RS:WaitForChild("Halloween"):FindFirstChild("State")
	if hwState then
		local lastUntil = hwState:GetAttribute("ServerRushUntil") or 0
		table.insert(conns, hwState:GetAttributeChangedSignal("ServerRushUntil"):Connect(function()
			local u = hwState:GetAttribute("ServerRushUntil") or 0
			if u > lastUntil and u > Shared.Now() and lastUntil <= Shared.Now() then
				local root2 = ctx.State and ctx.State.Root()
				if root2 and ctx.Layout.Weight(root2.CFrame.Position, 120) > 0 then
					burst()
				end
			end
			lastUntil = u
		end))
	end

	function M.Stop()
		if not alive then
			return
		end
		alive = false
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		root:Destroy()
		table.clear(auras)
	end
end

return M
