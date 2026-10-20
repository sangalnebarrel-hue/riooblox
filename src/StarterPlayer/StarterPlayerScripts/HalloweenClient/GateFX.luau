-- THE DEAD YARD gate, alive (StarterPlayerScripts.HalloweenClient.GateFX), WP10b. Client only.
-- When any character comes within Layout.Gate.OpenRange the two iron leaves (Models with attribute HwGateLeaf = "L"|"R",
-- OpenAngle degrees, pivot = hinge; built CLOSED by WP1) swing inward slowly (unlatch jolt -> 3 s eased swing ->
-- settle) with GateCreak + GateChain, the gate lanterns and braziers flare (Bus "LanternFlare"), the hanging chains
-- rattle (Bus "ChainKick"), fog rolls out through the opening, and a distant choir + howl answers the visitor (local
-- player only, once per 45 s). They close again once nobody is within CloseRange. While you walk up the approach the
-- fog at the threshold (GateFog attachments, fallback: points across the opening) thickens a little; the green
-- brazier flames (HwBrazier parts) burn with client fire particles and lick (AmbientFX flickers their lights).
-- Client-local, so every client animates the leaves from the same rule; late-streaming leaf parts get the current pose.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ambient = require(script.Parent:WaitForChild("AmbientFX"))
local Rig = Ambient.Rig

local V3 = Vector3.new
local RGB = Color3.fromRGB
local rad = math.rad
local IDENT = CFrame.new()
local smooth = Ambient.Smooth
local attPos = Ambient.AttPos

local GateFX = {}

-- swing sign so that the leaf's centre moves along `inward` (pure; tested offline)
function GateFX.SwingSign(pivot: CFrame, center: Vector3, inward: Vector3, angleDeg: number): number
	local function moved(sign)
		local rot = pivot * CFrame.Angles(0, rad(angleDeg) * sign, 0) * pivot:Inverse()
		return (rot * center - center):Dot(inward)
	end
	return moved(1) >= moved(-1) and 1 or -1
end

-- open / close decision with hysteresis (pure). distances = horizontal distances of every character to the gate
function GateFX.WantOpen(isOpen: boolean, distances: { number }, openRange: number, closeRange: number): boolean
	local nearest = math.huge
	for _, d in ipairs(distances) do
		nearest = math.min(nearest, d)
	end
	if isOpen then
		return nearest <= closeRange
	end
	return nearest <= openRange
end

-- eased leaf progress (0 closed .. 1 open) for an animation {From, To, T0, Dur} at time now, incl. the unlatch jolt
function GateFX.Progress(anim: { [string]: number }, now: number): (number, boolean)
	local k = math.clamp((now - anim.T0) / anim.Dur, 0, 1)
	local e = -(math.cos(math.pi * k) - 1) / 2 -- sine in-out: slow start, slow settle
	local p = anim.From + (anim.To - anim.From) * e
	if anim.To > anim.From and now - anim.T0 < .3 then
		p -= math.sin((now - anim.T0) / .3 * math.pi) * .015 -- unlatch: the leaves tug against the latch first
	end
	return p, k >= 1
end

function GateFX.Start(ctx)
	local Shared, Layout, Bus, FX, Audio = ctx.Shared, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio
	local player = Players.LocalPlayer
	local rng = Random.new()
	local G = Layout.Gate
	local gatePos = G.Center
	local inward = -G.Facing
	local folder = Instance.new("Folder")
	folder.Name = "Gate"
	folder.Parent = FX.Folder()

	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Layout.Zone.Center
	end
	local function flat(a: Vector3, b: Vector3): number
		return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	-------------------------------------------------------------------------------------------------------------
	-- markers
	-------------------------------------------------------------------------------------------------------------
	local leaves = {} -- model -> leaf
	local leafList = {}
	local leafOfPart = {} -- part -> leaf
	local fogPts = {} -- GateFog attachments
	local braziers = {} -- flame part -> {Part, Size, CF, Phase, Cluster}
	local clusters = {} -- one fire emitter per brazier: {Pos, Bottom, Width, Emitter, Count}
	local progress = 0
	local applyLeaves -- (below)

	-- Streaming: a leaf Model can reach the client before its parts, so GetPivot() at registration is a bounding box, not
	-- the hinge. The pivot is the HingeStile's (PrimaryPart's) closed CFrame, taken when that part actually arrives; until
	-- then the leaf stays put. The server never moves the leaves, so every part arrives (and streams back in) closed.
	local function leafTransform(leaf): CFrame
		local a = progress * leaf.OpenAngle
		if not leaf.Pivot or math.abs(a) < 1e-4 then
			return IDENT
		end
		if not leaf.Sign then
			local sum, n = V3(), 0
			for _, p in ipairs(leaf.Parts) do
				sum += leaf.Closed[p].Position
				n += 1
			end
			local center = n > 1 and sum / n or (leaf.Pivot.Position + V3(0, 0, leaf.Side == "L" and 4 or -4))
			leaf.Sign = GateFX.SwingSign(leaf.Pivot, center, inward, leaf.OpenAngle)
		end
		return leaf.Pivot * CFrame.Angles(0, rad(a) * leaf.Sign, 0) * leaf.Pivot:Inverse()
	end
	local function addLeafPart(leaf, p: BasePart)
		if leaf.Closed[p] then
			return
		end
		leaf.Closed[p] = p.CFrame
		leafOfPart[p] = leaf
		table.insert(leaf.Parts, p)
		if not leaf.Pivot and (p.Name == "HingeStile" or p == leaf.Model.PrimaryPart) then
			leaf.Pivot = p.CFrame
			if progress ~= 0 then
				applyLeaves() -- the parts that came first get the current pose too
			end
		elseif progress ~= 0 then
			p.CFrame = leafTransform(leaf) * p.CFrame
		end
	end
	local function removeLeafPart(p: BasePart)
		local leaf = leafOfPart[p]
		if leaf then
			leafOfPart[p] = nil
			leaf.Closed[p] = nil
			local i = table.find(leaf.Parts, p)
			if i then
				table.remove(leaf.Parts, i)
			end
		end
	end
	local function dropLeaf(model: Model)
		local leaf = leaves[model]
		leaves[model] = nil
		leaf.Conn:Disconnect()
		for _, p in ipairs(leaf.Parts) do
			leafOfPart[p] = nil
		end
		local i = table.find(leafList, leaf)
		if i then
			table.remove(leafList, i)
		end
	end
	local function registerLeaf(model: Model)
		if leaves[model] then
			return
		end
		local sign = tonumber(model:GetAttribute("OpenSign"))
		local leaf = { Model = model, Side = model:GetAttribute("HwGateLeaf"), Parts = {}, Closed = {}, Pivot = nil,
			OpenAngle = tonumber(model:GetAttribute("OpenAngle")) or 100, Sign = (sign == 1 or sign == -1) and sign or nil }
		leaves[model] = leaf
		table.insert(leafList, leaf)
		-- the PrimaryPart reference can resolve after its part arrived
		leaf.Conn = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			local pp = model.PrimaryPart
			if not leaf.Pivot and pp and leaf.Closed[pp] then
				leaf.Pivot = leaf.Closed[pp]
				if progress ~= 0 then
					applyLeaves()
				end
			end
		end)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				addLeafPart(leaf, d)
			end
		end
	end
	local function leafAncestor(inst: Instance): any
		local a = inst.Parent
		while a do
			local leaf = leaves[a]
			if leaf then
				return leaf
			end
			a = a.Parent
		end
		return nil
	end
	local function onAdded(inst: Instance)
		local leaf = inst:IsA("BasePart") and leafAncestor(inst)
		if inst:IsA("Model") and inst:GetAttribute("HwGateLeaf") ~= nil then
			registerLeaf(inst)
		elseif leaf then
			addLeafPart(leaf, inst :: BasePart) -- parts streaming in after their leaf Model
		elseif inst:IsA("Attachment") and inst.Name == "GateFog" then
			fogPts[inst] = true
		elseif inst:IsA("BasePart") and inst:GetAttribute("HwBrazier") == true and flat(inst.CFrame.Position, gatePos) < 40 then
			if not braziers[inst] then
				local pos = inst.CFrame.Position
				local cl = nil
				for _, c in ipairs(clusters) do
					if flat(c.Pos, pos) < 3.5 then
						cl = c
					end
				end
				if not cl then
					cl = { Pos = pos, Bottom = pos.Y, Width = 1, Count = 0 }
					table.insert(clusters, cl)
				end
				cl.Count += 1
				cl.Bottom = math.min(cl.Bottom, pos.Y - inst.Size.Y / 2)
				cl.Width = math.max(cl.Width, inst.Size.X)
				braziers[inst] = { Part = inst, Size = inst.Size, CF = inst.CFrame, Phase = rng:NextNumber(0, 10), Cluster = cl }
			end
		end
	end
	task.spawn(function()
		local yard = nil
		while not yard do
			local d = workspace:FindFirstChild("DOGROTS_District")
			yard = d and d:FindFirstChild("38_DeadYard")
			if not yard then
				task.wait(1)
			end
		end
		yard.DescendantAdded:Connect(onAdded)
		yard.DescendantRemoving:Connect(function(inst)
			fogPts[inst :: any] = nil
			if leaves[inst :: any] then
				dropLeaf(inst :: any) -- streamed out as a whole: a fresh registration when it comes back
			elseif leafOfPart[inst :: any] then
				removeLeafPart(inst :: any)
			end
			local b = braziers[inst :: any]
			if b then
				braziers[inst :: any] = nil
				local cl = b.Cluster
				cl.Count -= 1
				if cl.Count <= 0 then
					if cl.Emitter then
						cl.Emitter.Parent:Destroy()
					end
					local i = table.find(clusters, cl)
					if i then
						table.remove(clusters, i)
					end
				end
			end
		end)
		for i, inst in ipairs(yard:GetDescendants()) do
			onAdded(inst)
			if i % 4000 == 0 then
				task.wait()
			end
		end
	end)

	function applyLeaves()
		local parts, cfs = {}, {}
		for _, leaf in ipairs(leafList) do
			if leaf.Model.Parent then
				local T = leafTransform(leaf)
				for _, p in ipairs(leaf.Parts) do
					if p.Parent then
						table.insert(parts, p)
						table.insert(cfs, T * leaf.Closed[p])
					end
				end
			end
		end
		if #parts > 0 then
			Rig.Bulk(parts, cfs)
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- fog at the threshold
	-------------------------------------------------------------------------------------------------------------
	local fogEmitters = {}
	local fogKey = ""
	local function rebuildFog()
		for _, e in ipairs(fogEmitters) do
			e.Parent:Destroy()
		end
		table.clear(fogEmitters)
		local pts = {}
		for a in pairs(fogPts) do
			if a.Parent then
				table.insert(pts, attPos(a))
			end
		end
		if #pts == 0 then
			for _, z in ipairs({ G.Opening.Z0 + 3, (G.Opening.Z0 + G.Opening.Z1) / 2, G.Opening.Z1 - 3 }) do
				table.insert(pts, V3(gatePos.X + 1.5, Layout.FloorY + .4, z))
			end
		end
		local maxN = Shared.Low() and 1 or 4
		for k, pos in ipairs(pts) do
			if k > maxN then
				break
			end
			local p = FX.Part({ Name = "HwGateFog", Size = V3(3, .4, 5), Transparency = 1, CFrame = CFrame.new(pos), Parent = folder })
			local e = Instance.new("ParticleEmitter")
			e.Texture = FX.Textures.Smoke
			e.Color = ColorSequence.new(RGB(160, 150, 196), RGB(96, 86, 130))
			e.LightEmission = .08
			e.LightInfluence = .5
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(.5, 7), NumberSequenceKeypoint.new(1, 10) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.3, .7), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(4, 6.5)
			e.Speed = NumberRange.new(.6, 1.6)
			e.SpreadAngle = Vector2.new(40, 40)
			e.EmissionDirection = Enum.NormalId.Left -- -X: out through the gate, toward the visitors
			e.Acceleration = V3(-.25, .12, 0)
			e.Drag = .7
			e.RotSpeed = NumberRange.new(-15, 15)
			e.Rotation = NumberRange.new(0, 360)
			e.Shape = Enum.ParticleEmitterShape.Box
			e.Rate = 0
			e.Parent = p
			table.insert(fogEmitters, e)
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- braziers: green fire particles + flame lick (lights: AmbientFX)
	-------------------------------------------------------------------------------------------------------------
	local function ensureBrazierFire(b)
		if b.Emitter and b.Emitter.Parent then
			return
		end
		local p = FX.Part({ Name = "HwBrazierFire", Size = V3(b.Width * .9, .2, b.Width * .9), Transparency = 1,
			CFrame = CFrame.new(b.Pos.X, b.Bottom + .25, b.Pos.Z), Parent = folder })
		local e = Instance.new("ParticleEmitter")
		e.Texture = FX.Textures.Fire
		e.Color = ColorSequence.new(RGB(190, 255, 140), RGB(50, 190, 80))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.max(.8, b.Width * .8)), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .25), NumberSequenceKeypoint.new(.7, .5), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(.45, .8)
		e.Speed = NumberRange.new(2.5, 5)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(10, 10)
		e.RotSpeed = NumberRange.new(-80, 80)
		e.Rotation = NumberRange.new(0, 360)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Rate = 0
		e.Parent = p
		b.Emitter = e
	end

	-------------------------------------------------------------------------------------------------------------
	-- open / close
	-------------------------------------------------------------------------------------------------------------
	local isOpen = false
	local anim = nil
	local fogSurge = 0
	local brazierSurge = 0
	local nextChoir = 0
	local function playOpening()
		local cam = camPos()
		if flat(cam, gatePos) > 160 then
			return
		end
		local top = gatePos + V3(0, 9, 0)
		Audio.Play("GateCreak", gatePos + V3(0, 6, 0))
		Audio.Play("GateChain", top, { Delay = .15 })
		Bus.Fire("LanternFlare", { Position = gatePos + V3(0, 8, 0), Radius = 34, Strength = 2.2, Seconds = 2.6, Color = RGB(210, 255, 200) })
		Bus.Fire("ChainKick", { Position = gatePos + V3(0, 10, 0), Radius = 28, Strength = 1.4 })
		Audio.Play("LanternFlare", gatePos + V3(2, 8, 0), { Delay = .1 })
		fogSurge = 1
		brazierSurge = 1
		-- the yard answers the one who arrives: distant choir + howl
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local now = os.clock()
		if root and root:IsA("BasePart") and flat(root.CFrame.Position, gatePos) < G.OpenRange + 14 and now >= nextChoir then
			nextChoir = now + 45
			local choir = gatePos + V3(48, 12, 30)
			for k, pitch in ipairs({ .84, 1.0, 1.26 }) do
				Audio.Play("GhostWoo", choir, { Volume = .5, Pitch = pitch, Delay = .3 + k * .12 })
			end
			Audio.Play("Howl", gatePos + V3(85, 10, 90), { Volume = .9, Delay = 1.6, Pitch = rng:NextNumber(.9, 1.05) })
		end
	end
	local function playClosing()
		if flat(camPos(), gatePos) > 160 then
			return
		end
		Audio.Play("GateCreak", gatePos + V3(0, 6, 0), { Pitch = .86 })
		Audio.Play("GateChain", gatePos + V3(0, 9, 0), { Delay = 2.4, Volume = .8 })
		Bus.Fire("ChainKick", { Position = gatePos + V3(0, 10, 0), Radius = 28, Strength = .8 })
		fogSurge = math.max(fogSurge, .5)
	end
	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		local now = os.clock()
		local to = open and 1 or 0
		local dur = (open and 3 or 3.3) * math.max(.35, math.abs(to - progress))
		anim = { From = progress, To = to, T0 = now, Dur = dur }
		if open then
			playOpening()
		else
			playClosing()
		end
	end

	local function distances(): { number }
		local out = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and (not hum or hum.Health > 0) then
				table.insert(out, flat(root.CFrame.Position, gatePos))
			end
		end
		return out
	end

	-------------------------------------------------------------------------------------------------------------
	-- main loop
	-------------------------------------------------------------------------------------------------------------
	local checkAt, fogAt, slowAt = 0, 0, 0
	local lastFogN = -1
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, .1)
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				return
			end
			if now - checkAt > .2 then
				checkAt = now
				setOpen(GateFX.WantOpen(isOpen, distances(), G.OpenRange, G.CloseRange))
			end
			if anim then
				local p, done = GateFX.Progress(anim, now)
				progress = math.clamp(p, -.05, 1)
				applyLeaves()
				if done then
					progress = anim.To
					applyLeaves()
					anim = nil
				end
			end
			local cam = camPos()
			local dist = flat(cam, gatePos)
			-- fog: thickens a little as you walk up the approach, rolls out when the gate opens
			if now - fogAt > 1 then
				fogAt = now
				local n = 0
				for _ in pairs(fogPts) do
					n += 1
				end
				if n ~= lastFogN then
					lastFogN = n
					rebuildFog()
				end
			end
			fogSurge = math.max(0, fogSurge - dt / 3)
			brazierSurge = math.max(0, brazierSurge - dt / 2)
			local approach = 1 - math.clamp((dist - 12) / 90, 0, 1)
			local budget = FX.Budget("Particles")
			local rate = dist < 150 and (.35 + 1.6 * approach * approach + 4 * fogSurge) * budget or 0
			for _, e in ipairs(fogEmitters) do
				e.Rate = rate
			end
			-- braziers: one fire emitter per brazier, every flame tongue licks
			for _, cl in ipairs(clusters) do
				local near = flat(cl.Pos, cam) < 130
				if near then
					ensureBrazierFire(cl)
				end
				if cl.Emitter then
					cl.Emitter.Rate = near and (12 + 18 * brazierSurge) * budget or 0
				end
			end
			for _, b in pairs(braziers) do
				if b.Part.Parent then
					if flat(b.CF.Position, cam) < 70 and now - slowAt > 1 / 20 then
						local t = now + b.Phase
						local lick = 1 + .12 * math.noise(t * 4, b.Phase) + .06 * math.sin(t * 11) + .25 * brazierSurge
						local lean = math.noise(t * 1.5, b.Phase + 4) * .06
						b.Part.Size = V3(b.Size.X, b.Size.Y * lick, b.Size.Z)
						b.Part.CFrame = b.CF * CFrame.new(0, b.Size.Y * (lick - 1) / 2, 0) * CFrame.Angles(lean, 0, lean * .6)
					end
				end
			end
			if now - slowAt > 1 / 20 then
				slowAt = now
			end
		end)
		if not ok then
			warn("GateFX: " .. tostring(err))
		end
	end)
end

return GateFX
