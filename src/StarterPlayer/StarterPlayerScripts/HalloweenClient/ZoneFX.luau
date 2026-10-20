-- NIGHT OF THE BURIED MOON — Dead Yard atmosphere FX (StarterPlayerScripts.HalloweenClient.ZoneFX). WP10a.
-- Client-only parts/emitters in FX.Folder() (SelfManagedFX, so WorldDetailQuality never touches them), own budgets:
-- * ground mist at the builders' FogPoint attachments (streamed: registered as they arrive; synthetic points from Layout
--   fill in while fewer than 8 are known): the nearest N points within 160 studs get a pooled mist holder (rolling
--   camera-facing smoke + a flat lying layer on High/Medium); pit points are denser and darker;
-- * fog thickening on the approach paving outside the gate as the camera comes closer (GateFX owns the gate itself);
-- * slow drifting fog walls along the fence runs (nearest K segments);
-- * light shafts from the Buried Moon onto the cauldron, the pit, the graveyard, the grand crypt and the broken lab
--   (FaceCamera beams, sway; turn red with the Blood Moon).
-- Blood Moon: denser, redder mist. Budgets: mist High 16 / Medium 10 / Low 4, fence High 10 / Medium 6 / Low 2,
-- shafts High 5 / Medium 3 / Low 1. ReducedMotion: no sway.
local RunService = game:GetService("RunService")

local M = {}
local C3 = Color3.fromRGB
local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

M.Budget = {
	High = { Mist = 16, Fence = 10, Shafts = 5, MistRate = 1.1, Flat = true },
	Medium = { Mist = 10, Fence = 6, Shafts = 3, MistRate = .85, Flat = true },
	Low = { Mist = 4, Fence = 2, Shafts = 1, MistRate = .6, Flat = false },
}

function M.Start(ctx)
	local Shared, Layout, FX = ctx.Shared, ctx.Layout, ctx.FX
	if not Shared.Enabled() then
		return
	end
	local LightingMod = ctx.Modules and ctx.Modules.Lighting
	local root = Instance.new("Model")
	root.Name = "HalloweenZoneFX"
	root.Parent = FX.Folder()
	local alive = true
	local conns = {}

	local MIST_COLOR = { C3(112, 106, 164), C3(70, 62, 112) }
	local MIST_BLOOD = { C3(150, 70, 92), C3(84, 26, 44) }
	local function smokeEmitter(parent: Instance, props)
		local e = Instance.new("ParticleEmitter")
		e.Texture = FX.Textures.Smoke
		e.LightEmission = .05
		e.LightInfluence = .45
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Top
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-6, 6)
		e.Rate = 0
		e.Enabled = false
		for k, v in pairs(props) do
			(e :: any)[k] = v
		end
		e.Parent = parent
		return e
	end

	---------------------------------------------------------------------------------------------------------------
	-- fog points
	---------------------------------------------------------------------------------------------------------------
	local fogPoints = {} -- Attachment -> true
	local ghostPoints = {} -- GhostPath_n attachments (the milestone souls)
	local synthetic = {}
	for _, p in ipairs(Layout.DigPoints) do
		table.insert(synthetic, p + Vector3.new(0, .4, 0))
	end
	for _, p in ipairs({ Layout.Pit.Center, Layout.Pit.Center + Vector3.new(-14, 0, -12), Layout.Pit.Center + Vector3.new(14, 0, 12),
		Layout.Cauldron.Center + Vector3.new(-18, 0, 10), Layout.Cauldron.Center + Vector3.new(18, 0, 10),
		Vector3.new(70, .2, 576), Vector3.new(128, .2, 576), Vector3.new(184, .2, 576), Vector3.new(128, .2, 716),
		Vector3.new(186, .2, 700), Vector3.new(176, .2, 640) }) do
		table.insert(synthetic, p + Vector3.new(0, .4, 0))
	end
	task.spawn(function()
		local district = workspace:WaitForChild("DOGROTS_District", 60)
		local yard = district and district:WaitForChild("38_DeadYard", 120)
		if not yard or not alive then
			return
		end
		local function add(d: Instance)
			if d:IsA("Attachment") and d.Name == "FogPoint" then
				fogPoints[d] = true
			elseif d:IsA("Attachment") and string.sub(d.Name, 1, 10) == "GhostPath_" then
				ghostPoints[d] = true
			end
		end
		for _, d in ipairs(yard:GetDescendants()) do
			add(d)
		end
		table.insert(conns, yard.DescendantAdded:Connect(add))
		table.insert(conns, yard.DescendantRemoving:Connect(function(d)
			fogPoints[d] = nil
			ghostPoints[d] = nil
		end))
	end)

	local holders = {} -- pooled mist holders {Part, Roll, Flat, Key, Pit}
	local function holder(i: number)
		local h = holders[i]
		if h then
			return h
		end
		local part = FX.Part({ Size = Vector3.new(12, 1.4, 12), Transparency = 1, Parent = root, Name = "MistHolder" })
		local roll = smokeEmitter(part, { Color = ColorSequence.new(MIST_COLOR[1], MIST_COLOR[2]),
			Size = NumberSequence.new({ kp(0, 5), kp(.5, 9), kp(1, 12) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(.3, .84), kp(.7, .86), kp(1, 1) }),
			Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(.2, .6), SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(.25, .02, .12), Drag = .4 })
		local flat = smokeEmitter(part, { Color = ColorSequence.new(MIST_COLOR[1], MIST_COLOR[2]),
			Size = NumberSequence.new({ kp(0, 10), kp(.5, 15), kp(1, 18) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(.35, .9), kp(.7, .91), kp(1, 1) }),
			Lifetime = NumberRange.new(10, 14), Speed = NumberRange.new(.05, .12), SpreadAngle = Vector2.new(0, 0),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Acceleration = Vector3.new(.15, 0, .08), Drag = .2 })
		h = { Part = part, Roll = roll, Flat = flat, Key = nil, Pit = false, Rate = -1, Blood = -1 }
		holders[i] = h
		return h
	end

	local function candidates(camPos: Vector3, range: number)
		local list = {}
		local real = 0
		for a in pairs(fogPoints) do
			if a.Parent then
				real += 1
				local holderPart = a.Parent
				local p = (holderPart and holderPart:IsA("BasePart")) and (holderPart.CFrame * a.CFrame).Position or a.WorldPosition
				local d = (p - camPos).Magnitude
				if d <= range then
					table.insert(list, { Key = a, Pos = p, D = d })
				end
			end
		end
		if real < 8 then
			for i, p in ipairs(synthetic) do
				local d = (p - camPos).Magnitude
				if d <= range then
					table.insert(list, { Key = "s" .. i, Pos = p, D = d })
				end
			end
		end
		table.sort(list, function(a, b)
			return a.D < b.D
		end)
		return list
	end

	local function updateMist(camPos: Vector3, budget, blood: number)
		local list = candidates(camPos, 160)
		local n = math.min(budget.Mist, #list)
		local chosen = {}
		for i = 1, n do
			chosen[list[i].Key] = list[i]
		end
		-- holders keep their point while it stays chosen; the rest are reassigned (pool size = budget)
		local free = {}
		for i = 1, budget.Mist do
			local h = holder(i)
			local c = h.Key ~= nil and chosen[h.Key] or nil
			if c then
				h.Target = c
				chosen[h.Key] = nil
			else
				h.Key, h.Target = nil, nil
				table.insert(free, h)
			end
		end
		for i = budget.Mist + 1, #holders do -- quality went down: park the extra holders
			local h = holders[i]
			h.Key, h.Target = nil, nil
			if h.Rate ~= 0 then
				h.Rate = 0
				h.Roll.Enabled, h.Flat.Enabled = false, false
			end
		end
		for _, c in pairs(chosen) do
			local h = table.remove(free)
			if not h then
				break
			end
			h.Key = c.Key
			h.Target = c
			h.Pit = c.Pos.Y < -2
			h.Blood = -1
			h.Part.CFrame = CFrame.new(c.Pos + Vector3.new(0, .8, 0))
			h.Part.Size = h.Pit and Vector3.new(16, 2, 16) or Vector3.new(12, 1.4, 12)
		end
		for i = 1, budget.Mist do
			local h = holders[i]
			if h then
				local rate = 0
				if h.Target then
					local fade = math.clamp(1 - (h.Target.D - 80) / 80, 0, 1)
					rate = budget.MistRate * fade * (h.Pit and 1.35 or 1) * (1 + .6 * blood)
				end
				rate = math.floor(rate * 10 + .5) / 10
				if rate ~= h.Rate then
					h.Rate = rate
					h.Roll.Rate = rate
					h.Roll.Enabled = rate > 0
					h.Flat.Rate = rate * .45
					h.Flat.Enabled = rate > 0 and budget.Flat
				end
				local b = math.floor(blood * 20 + .5) / 20
				if b ~= h.Blood then
					h.Blood = b
					local c1 = MIST_COLOR[1]:Lerp(MIST_BLOOD[1], b)
					local c2 = MIST_COLOR[2]:Lerp(MIST_BLOOD[2], b)
					if h.Pit then
						c1, c2 = c1:Lerp(C3(40, 30, 60), .35), c2:Lerp(C3(20, 14, 32), .35)
					end
					h.Roll.Color = ColorSequence.new(c1, c2)
					h.Flat.Color = ColorSequence.new(c1, c2)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- gate approach fog
	---------------------------------------------------------------------------------------------------------------
	local gateFog = {}
	for i, x in ipairs({ 17, 24, 30.5 }) do
		local part = FX.Part({ Size = Vector3.new(7, 1.6, 18), Transparency = 1, Parent = root, Name = "GateFog" .. i,
			CFrame = CFrame.new(x, 1.3, Layout.Gate.Center.Z) })
		gateFog[i] = smokeEmitter(part, { Color = ColorSequence.new(C3(120, 112, 170), C3(64, 56, 104)),
			Size = NumberSequence.new({ kp(0, 4), kp(.5, 8), kp(1, 10) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(.3, .8), kp(.7, .83), kp(1, 1) }),
			Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(.2, .5), SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(-.2, .03, 0), Drag = .4 })
	end
	local lastGate = -1
	local function updateGate(camPos: Vector3, blood: number)
		local d = (camPos - Layout.Gate.Approach).Magnitude
		local p = math.clamp(1 - (d - 20) / 90, 0, 1)
		local rate = math.floor(p * 1.6 * (1 + .4 * blood) * 10 + .5) / 10
		if rate ~= lastGate then
			lastGate = rate
			for _, e in ipairs(gateFog) do
				e.Rate = rate
				e.Enabled = rate > 0
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- fence fog walls
	---------------------------------------------------------------------------------------------------------------
	local fence = {}
	for _, run in ipairs(Layout.FenceRuns) do
		local a = Vector3.new(run[1], 0, run[2])
		local b = Vector3.new(run[3], 0, run[4])
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(len / 36 + .5))
		for i = 1, n do
			local c = a + dir * (len * (i - .5) / n)
			table.insert(fence, { Pos = Vector3.new(c.X, 2.6, c.Z), Dir = dir, Len = len / n })
		end
	end
	local function fenceEmitter(seg)
		if seg.Emitter then
			return seg.Emitter
		end
		local yaw = math.atan2(-seg.Dir.Z, seg.Dir.X)
		local part = FX.Part({ Size = Vector3.new(seg.Len, 5, 3), Transparency = 1, Parent = root, Name = "FenceFog",
			CFrame = CFrame.new(seg.Pos) * CFrame.Angles(0, yaw, 0) })
		seg.Emitter = smokeEmitter(part, { Color = ColorSequence.new(C3(84, 74, 128), C3(48, 40, 80)),
			Size = NumberSequence.new({ kp(0, 6), kp(.5, 10), kp(1, 12) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(.3, .87), kp(.7, .89), kp(1, 1) }),
			Lifetime = NumberRange.new(9, 13), Speed = NumberRange.new(.1, .3), SpreadAngle = Vector2.new(40, 40),
			Acceleration = seg.Dir * .15 + Vector3.new(0, .02, 0), Drag = .3 })
		seg.Rate = -1
		return seg.Emitter
	end
	local function updateFence(camPos: Vector3, budget, blood: number)
		local order = {}
		for i, seg in ipairs(fence) do
			local d = (seg.Pos - camPos).Magnitude
			if d < 170 then
				table.insert(order, { I = i, D = d })
			end
		end
		table.sort(order, function(a, b)
			return a.D < b.D
		end)
		local on = {}
		for k = 1, math.min(budget.Fence, #order) do
			on[order[k].I] = order[k].D
		end
		for i, seg in ipairs(fence) do
			local d = on[i]
			local rate = 0
			if d then
				rate = math.floor(.7 * math.clamp(1 - (d - 90) / 80, 0, 1) * (1 + .5 * blood) * 10 + .5) / 10
			end
			if rate > 0 or seg.Emitter then
				local e = fenceEmitter(seg)
				if rate ~= seg.Rate then
					seg.Rate = rate
					e.Rate = rate
					e.Enabled = rate > 0
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- moon light shafts
	---------------------------------------------------------------------------------------------------------------
	local toMoon = (Layout.Moon.Position - (Layout.Gate.Center + Vector3.new(0, 6, 0))).Unit
	local targets = {
		Layout.Cauldron.Center + Vector3.new(0, .4, 0),
		Vector3.new(Layout.Pit.Center.X, Layout.Pit.FloorY + .3, Layout.Pit.Center.Z),
		Vector3.new((Layout.Graveyard.X0 + Layout.Graveyard.X1) / 2, .4, 664),
		Layout.Crypts.Grand.Door + Vector3.new(0, .4, -6),
		Vector3.new((Layout.BrokenLab.X0 + Layout.BrokenLab.X1) / 2 - 8, .4, (Layout.BrokenLab.Z0 + Layout.BrokenLab.Z1) / 2),
	}
	local shafts = {}
	local SHAFT = C3(170, 182, 255)
	local SHAFT_BLOOD = C3(255, 76, 64)
	local function shaft(i: number)
		if shafts[i] then
			return shafts[i]
		end
		local target = targets[i]
		local top = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, Parent = root, Name = "ShaftTop",
			CFrame = CFrame.new(target + toMoon * 150) })
		local bottom = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, Parent = root, Name = "ShaftBottom",
			CFrame = CFrame.new(target) })
		local a0 = Instance.new("Attachment")
		a0.Parent = top
		local a1 = Instance.new("Attachment")
		a1.Parent = bottom
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0, beam.Width1 = 9, 17
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(SHAFT)
		beam.Transparency = NumberSequence.new(1)
		beam.Enabled = false
		beam.Parent = top
		local s = { Beam = beam, Top = top, Target = target, Phase = i * 1.7, Vis = -1, Blood = -1 }
		shafts[i] = s
		return s
	end
	local function updateShafts(camPos: Vector3, budget, vis: number, blood: number, dtAcc: number)
		local reduced = Shared.ReducedMotion()
		local t = os.clock()
		for i = 1, #targets do
			local want = i <= budget.Shafts and vis > .02 and (targets[i] - camPos).Magnitude < 260
			local s = shafts[i]
			if want then
				s = shaft(i)
				local v = math.floor(vis * 40 + .5) / 40
				if v ~= s.Vis then
					s.Vis = v
					local a = function(x)
						return 1 - (1 - x) * v
					end
					s.Beam.Transparency = NumberSequence.new({ kp(0, 1), kp(.25, a(.93)), kp(.75, a(.9)), kp(1, a(.97)) })
				end
				local b = math.floor(blood * 20 + .5) / 20
				if b ~= s.Blood then
					s.Blood = b
					s.Beam.Color = ColorSequence.new(SHAFT:Lerp(SHAFT_BLOOD, b))
				end
				s.Beam.Enabled = true
				if not reduced then
					local sway = Vector3.new(math.sin(t * .3 + s.Phase) * 3, 0, math.cos(t * .23 + s.Phase) * 3)
					s.Top.CFrame = CFrame.new(s.Target + toMoon * 150 + sway)
				end
			elseif s and s.Beam.Enabled then
				s.Beam.Enabled = false
			end
		end
	end


	---------------------------------------------------------------------------------------------------------------
	-- SERVER EXORCISM milestone: the Dead Yard gives up its souls (Signal "Milestone", everyone within ~420 studs)
	-- Souls rise from the fog points, graves and ghost paths, spiral in over the pit and feed a soul pillar that
	-- erupts into the sky with ground rings, a sky burst, every lantern flaring and a light flash (the Gravekeeper
	-- milestone: blood red). Budget: souls High 30 / Medium 18 / Low 8 (ReducedMotion: half, no flash).
	---------------------------------------------------------------------------------------------------------------
	M.SoulBudget = { High = 30, Medium = 18, Low = 8 }
	local souls = {} -- {Part, Tail = {parts}, Start, T0, Dur, Spin, R0}
	local function soulSources(n: number): { Vector3 }
		local list = {}
		for a in pairs(fogPoints) do
			if a.Parent then
				local hp = a.Parent
				table.insert(list, ((hp and hp:IsA("BasePart")) and (hp.CFrame * a.CFrame).Position or a.WorldPosition) + Vector3.new(0, 1.2, 0))
			end
		end
		for a in pairs(ghostPoints) do
			if a.Parent then
				local hp = a.Parent
				table.insert(list, ((hp and hp:IsA("BasePart")) and (hp.CFrame * a.CFrame).Position or a.WorldPosition) + Vector3.new(0, .8, 0))
			end
		end
		if #list < n then
			for _, p in ipairs(synthetic) do
				table.insert(list, p + Vector3.new(0, 1, 0))
			end
		end
		-- a spread pick: shuffle and take n
		local rng = Random.new()
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
		local out = {}
		for i = 1, math.min(n, #list) do
			out[i] = list[i]
		end
		return out
	end
	local pillarTop = Vector3.new(Layout.Pit.Center.X, Layout.Pit.FloorY + 46, Layout.Pit.Center.Z)
	local function milestoneMoment(d)
		local cam = workspace.CurrentCamera
		if not cam or not Shared.Enabled() then
			return
		end
		local camPos = cam.CFrame.Position
		if (camPos - Layout.Pit.Center).Magnitude > 420 then
			return
		end
		local boss = d.Kind == "Boss"
		local col = boss and C3(255, 70, 80) or C3(130, 255, 140)
		local hot = boss and C3(255, 190, 170) or C3(225, 255, 230)
		local reduced = Shared.ReducedMotion()
		local n = M.SoulBudget[Shared.Quality()] or 18
		if reduced then
			n = math.ceil(n / 2)
		end
		local floor = Vector3.new(Layout.Pit.Center.X, Layout.Pit.FloorY + .3, Layout.Pit.Center.Z)
		-- 0: the pit answers - a ground ring, the souls wake
		FX.Ring(floor, col, 34, 1.4, { Thickness = .35 })
		ctx.Audio.Play("SoulRise")
		local rng = Random.new()
		for i, from in ipairs(soulSources(n)) do
			local p = FX.Part({ Name = "HwSoul", Shape = Enum.PartType.Ball, Size = Vector3.one * .9, Color = hot, Transparency = 1,
				CFrame = CFrame.new(from), Parent = root })
			local tail = {}
			for k = 1, (Shared.Low() and 1 or 3) do
				tail[k] = FX.Part({ Name = "HwSoulTail", Shape = Enum.PartType.Ball, Size = Vector3.one * (.75 - k * .15), Color = col, Transparency = 1,
					CFrame = CFrame.new(from), Parent = root })
			end
			table.insert(souls, { Part = p, Tail = tail, Hist = {}, Start = from, T0 = os.clock() + rng:NextNumber(0, 1.4), Dur = rng:NextNumber(2.2, 3.0),
				Spin = rng:NextNumber(1.6, 2.6) * (i % 2 == 0 and 1 or -1), R0 = rng:NextNumber(6, 14), Col = col })
		end
		-- 1.8: the pillar erupts; 2.4: the sky burst; lanterns + light flash
		task.delay(1.8, function()
			if not alive then
				return
			end
			FX.Beam(floor, col, 70, 5.5)
			FX.Shockwave(floor + Vector3.new(0, .2, 0), col, 26, 1.1)
			ctx.Bus.Fire("LanternFlare", { Position = Layout.Pit.Center, Radius = 220, Strength = 2, Seconds = 3, Color = col })
			if not reduced and LightingMod and LightingMod.Flash then
				pcall(LightingMod.Flash, .6, 1.2)
			end
			if (camPos - floor).Magnitude < 160 then
				FX.Shake(.2, .6)
			end
			if boss then
				ctx.Audio.Play("Thunder")
			end
		end)
		task.delay(3.4, function()
			if not alive then
				return
			end
			FX.Burst(pillarTop, { Color = hot, Color2 = col, Count = 60, Speed = { 18, 40 }, Spread = 180, Lifetime = { 1, 2 }, Size = { 1, 1.8, 0 },
				Acceleration = Vector3.new(0, -6, 0), Drag = 1.5 })
			FX.Light(pillarTop, col, 90, 6, 2)
			FX.Ring(pillarTop, col, 40, 1.6, { Thickness = .5 })
			ctx.Audio.Play("ExorcismPulse", pillarTop, { Volume = 1.4 })
		end)
	end
	M.MilestoneMoment = milestoneMoment
	local function stepSouls()
		local now = os.clock()
		for i = #souls, 1, -1 do
			local s = souls[i]
			local k = (now - s.T0) / s.Dur
			if k >= 1 or not s.Part.Parent then
				FX.Burst(s.Part.CFrame.Position, { Color = s.Col, Count = 3, Speed = { 2, 5 }, Lifetime = { .3, .6 }, Size = { .4, .6, 0 } })
				s.Part:Destroy()
				for _, t in ipairs(s.Tail) do
					t:Destroy()
				end
				table.remove(souls, i)
			elseif k >= 0 then
				-- rise, then spiral in over the pit onto the pillar
				local e = k * k * (3 - 2 * k)
				local base = s.Start:Lerp(pillarTop, e)
				local lift = math.sin(k * math.pi) * 10
				local r = s.R0 * (1 - e)
				local a = s.Spin * k * math.pi * 2
				local pos = base + Vector3.new(math.cos(a) * r, lift, math.sin(a) * r)
				s.Part.CFrame = CFrame.new(pos)
				local alpha = math.clamp(k / .12, 0, 1) * math.clamp((1 - k) / .1, 0, 1)
				s.Part.Transparency = 1 - .9 * alpha
				table.insert(s.Hist, 1, pos)
				if #s.Hist > 12 then
					table.remove(s.Hist)
				end
				for j, t in ipairs(s.Tail) do
					local h = s.Hist[math.min(#s.Hist, j * 3)] or pos
					t.CFrame = CFrame.new(h)
					t.Transparency = 1 - (.65 - j * .15) * alpha
				end
			end
		end
	end
	ctx.Bus.On("Signal", function(sig)
		if type(sig) == "table" and sig.Kind == "Milestone" and type(sig.Data) == "table" then
			local ok, err = pcall(milestoneMoment, sig.Data)
			if not ok then
				warn("Halloween ZoneFX milestone: " .. tostring(err))
			end
		end
	end)

	---------------------------------------------------------------------------------------------------------------
	local slow, fast = 1, 0
	local function cleanup()
		if not alive then
			return
		end
		alive = false
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		root:Destroy()
	end
	M.Stop = cleanup
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		slow += dt
		fast += dt
		if #souls > 0 then
			local okS, errS = pcall(stepSouls)
			if not okS then
				warn("Halloween ZoneFX souls: " .. tostring(errS))
				for _, so in ipairs(souls) do
					so.Part:Destroy()
					for _, t in ipairs(so.Tail) do
						t:Destroy()
					end
				end
				table.clear(souls)
			end
		end
		if fast < .1 then
			return
		end
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				cleanup()
				return
			end
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			local camPos = cam.CFrame.Position
			local budget = M.Budget[Shared.Quality()] or M.Budget.High
			local W = LightingMod and LightingMod.Weights and LightingMod.Weights() or nil
			local blood = W and W.Blood or Shared.BloodMoonAlpha(Shared.Now())
			local zone = W and W.Zone or Layout.Weight(camPos, 44)
			local approach = W and W.Approach or Layout.Weight(camPos, 260)
			local moonVis = W and W.MoonVis or 0
			updateShafts(camPos, budget, moonVis * math.max(zone, approach * .5), blood, fast)
			fast = 0
			if slow >= .5 then
				slow = 0
				updateMist(camPos, budget, blood)
				updateGate(camPos, blood)
				updateFence(camPos, budget, blood)
			end
		end)
		if not ok and not M.Warned then
			M.Warned = true
			warn("Halloween ZoneFX failed: " .. tostring(err))
		end
	end))
end

return M
