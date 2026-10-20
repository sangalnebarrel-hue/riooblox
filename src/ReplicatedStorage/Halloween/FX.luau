-- Shared client VFX helpers for the Halloween event (ReplicatedStorage.Halloween.FX). Client only.
-- Every effect follows begin -> peak -> fade, scales with Shared.Quality() and respects ReducedMotion.
-- Only built-in particle textures are used (sparkles/smoke/fire), so nothing depends on uploaded assets.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = require(script.Parent:WaitForChild("Shared"))

local FX = {}
FX.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
FX.Font = FONT

local folder = nil
function FX.Folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	folder = workspace:FindFirstChild("DOGROTS_HalloweenFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DOGROTS_HalloweenFX"
		folder:SetAttribute("SelfManagedFX", true)
		folder.Parent = workspace
	end
	return folder
end

function FX.Low(): boolean
	return Shared.Low()
end

function FX.Budget(kind: string?): number
	local q = Shared.Quality()
	if q == "Low" then
		return .3
	elseif q == "Medium" then
		return .6
	end
	return 1
end

function FX.Tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

-- anchored, non-interactive, shadowless part in the FX folder
function FX.Part(props: { [string]: any }?): BasePart
	local class = props and props.Class or "Part"
	local p = Instance.new(class)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			if k ~= "Class" and k ~= "Parent" then
				(p :: any)[k] = v
			end
		end
	end
	p.Parent = props and props.Parent or FX.Folder()
	return p
end

local function anchorAt(pos: Vector3, life: number): (BasePart, Attachment)
	local p = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(pos) })
	local a = Instance.new("Attachment")
	a.Parent = p
	Debris:AddItem(p, life)
	return p, a
end

local function seq(a: number, b: number?, c: number?)
	if c then
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(.5, b :: number), NumberSequenceKeypoint.new(1, c) })
	end
	return NumberSequence.new(a, b or a)
end
FX.Seq = seq

-- one-shot particle burst. opts: Color, Color2, Count, Speed {min,max}, Spread, Lifetime {min,max}, Size {start,peak,end},
-- Texture, LightEmission, Drag, Acceleration, Transparency {start,end}, Rotation, Shape ("Sphere"|"Disc"), Direction (Vector3)
function FX.Burst(pos: Vector3, opts: { [string]: any }?)
	opts = opts or {}
	local count = math.max(1, math.floor((opts.Count or 18) * FX.Budget("Particles") + .5))
	local life = opts.Lifetime or { .6, 1.2 }
	local _, att = anchorAt(pos, life[2] + .3)
	if opts.Direction then
		att.CFrame = CFrame.lookAt(Vector3.zero, opts.Direction.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = opts.Texture or FX.Textures.Sparkle
	local c1 = opts.Color or Color3.new(1, 1, 1)
	local c2 = opts.Color2 or c1
	e.Color = ColorSequence.new(c1, c2)
	e.LightEmission = opts.LightEmission or .8
	e.LightInfluence = 0
	local size = opts.Size or { .5, 1, 0 }
	e.Size = seq(size[1], size[2], size[3])
	local tr = opts.Transparency or { 0, 1 }
	e.Transparency = NumberSequence.new(tr[1], tr[2])
	e.Lifetime = NumberRange.new(life[1], life[2])
	local sp = opts.Speed or { 6, 14 }
	e.Speed = NumberRange.new(sp[1], sp[2])
	e.SpreadAngle = Vector2.new(opts.Spread or 180, opts.Spread or 180)
	e.Drag = opts.Drag or 2
	e.Acceleration = opts.Acceleration or Vector3.new(0, -4, 0)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e.ZOffset = opts.ZOffset or .5
	if opts.Shape == "Disc" then
		e.Shape = Enum.ParticleEmitterShape.Disc
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end
	e.Parent = att
	e:Emit(count)
	return e
end

-- continuous emitter at a position for `duration` (fades the rate out over the last third)
function FX.Emit(pos: Vector3, rate: number, duration: number, opts: { [string]: any }?)
	opts = opts or {}
	local life = opts.Lifetime or { .8, 1.6 }
	local _, att = anchorAt(pos, duration + life[2] + .5)
	local e = FX.Burst(pos, opts) -- template
	e.Parent = att
	e.Rate = rate * FX.Budget("Particles")
	task.delay(duration * .66, function()
		if e.Parent then
			e.Rate *= .4
		end
	end)
	task.delay(duration, function()
		if e.Parent then
			e.Enabled = false
		end
	end)
	return e
end

-- flat expanding ring on the ground. opts: Thickness, Height (y offset), Material, Transparency, Normal
function FX.Ring(pos: Vector3, color: Color3, radius: number, duration: number?, opts: { [string]: any }?)
	opts = opts or {}
	duration = duration or .6
	local normal = opts.Normal or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(pos + normal * (opts.Height or .15), pos + normal * 2) * CFrame.Angles(0, math.pi / 2, 0)
	local ring = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Color = color, Material = opts.Material or Enum.Material.Neon,
		Transparency = opts.Transparency or .15, Size = Vector3.new(opts.Thickness or .12, .4, .4), CFrame = cf })
	local inner = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Color = color:Lerp(Color3.new(1, 1, 1), .35),
		Transparency = .55, Size = Vector3.new((opts.Thickness or .12) * .6, .3, .3), CFrame = cf * CFrame.new(.03, 0, 0) })
	FX.Tween(ring, duration, { Size = Vector3.new(opts.Thickness or .12, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	FX.Tween(inner, duration * .8, { Size = Vector3.new((opts.Thickness or .12) * .6, radius * 1.4, radius * 1.4), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(ring, duration + .1)
	Debris:AddItem(inner, duration + .1)
	return ring
end

-- ground ring + a fading dome shell (big impacts)
function FX.Shockwave(pos: Vector3, color: Color3, radius: number, duration: number?)
	duration = duration or .7
	FX.Ring(pos, color, radius, duration, { Thickness = .2 })
	if FX.Low() then
		return
	end
	local dome = FX.Part({ Class = "Part", Shape = Enum.PartType.Ball, Color = color, Transparency = .55, Size = Vector3.one * 1,
		CFrame = CFrame.new(pos), Material = Enum.Material.ForceField })
	FX.Tween(dome, duration, { Size = Vector3.one * radius * 1.6, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(dome, duration + .1)
	FX.Burst(pos + Vector3.new(0, .5, 0), { Color = color, Count = 22, Speed = { radius * .8, radius * 1.4 }, Spread = 70,
		Direction = Vector3.new(0, 1, 0), Lifetime = { .35, .7 }, Size = { .6, 1.1, 0 }, Drag = 6, Shape = "Disc" })
end

-- loot / rare-find beam: grows from the ground, pulses, fades. Returns a handle {Stop()}.
function FX.Beam(pos: Vector3, color: Color3, height: number?, duration: number?)
	height = height or 26
	duration = duration or 4
	local root = Instance.new("Model")
	root.Name = "HalloweenBeam"
	root.Parent = FX.Folder()
	local core = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Color = color, Transparency = .25,
		Size = Vector3.new(.2, 1.1, 1.1), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Parent = root })
	local glow = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Color = color:Lerp(Color3.new(1, 1, 1), .25),
		Transparency = .78, Size = Vector3.new(.2, 3.2, 3.2), CFrame = core.CFrame, Material = Enum.Material.ForceField, Parent = root })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = core
	local up = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	FX.Tween(core, .45, { Size = Vector3.new(height, 1.1, 1.1), CFrame = up }, Enum.EasingStyle.Back)
	FX.Tween(glow, .55, { Size = Vector3.new(height, 3.2, 3.2), CFrame = up }, Enum.EasingStyle.Quart)
	FX.Tween(light, .4, { Brightness = 3 })
	if not FX.Low() then
		FX.Emit(pos + Vector3.new(0, 1, 0), 14, duration * .8, { Color = color, Color2 = Color3.new(1, 1, 1), Speed = { 4, 9 }, Spread = 12,
			Direction = Vector3.new(0, 1, 0), Lifetime = { 1, 1.8 }, Size = { .3, .55, 0 }, Acceleration = Vector3.new(0, 3, 0) })
	end
	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		FX.Tween(core, .6, { Transparency = 1, Size = Vector3.new(height, .1, .1) })
		FX.Tween(glow, .6, { Transparency = 1 })
		FX.Tween(light, .6, { Brightness = 0 })
		Debris:AddItem(root, .7)
	end
	task.delay(duration, stop)
	return { Stop = stop, Model = root }
end

-- tumbling chunks driven by one Heartbeat loop (cheap, deterministic, no physics)
local chunks = {}
local chunkConn = nil
local function stepChunks(dt)
	for i = #chunks, 1, -1 do
		local c = chunks[i]
		c.T += dt
		if c.T >= c.Life or not c.Part.Parent then
			if c.Part.Parent then
				c.Part:Destroy()
			end
			table.remove(chunks, i)
		else
			c.V += Vector3.new(0, -c.G * dt, 0)
			local p = c.Part.Position + c.V * dt
			if p.Y < c.Floor then
				p = Vector3.new(p.X, c.Floor, p.Z)
				c.V = Vector3.new(c.V.X * .5, math.abs(c.V.Y) * .3, c.V.Z * .5)
			end
			c.Part.CFrame = CFrame.new(p) * c.Part.CFrame.Rotation * CFrame.Angles(c.R.X * dt, c.R.Y * dt, c.R.Z * dt)
			local fade = math.clamp((c.T - c.Life * .6) / (c.Life * .4), 0, 1)
			c.Part.Transparency = c.Base + (1 - c.Base) * fade
		end
	end
	if #chunks == 0 and chunkConn then
		chunkConn:Disconnect()
		chunkConn = nil
	end
end

function FX.Debris(pos: Vector3, color: Color3, material: Enum.Material?, count: number?, speed: number?, opts: { [string]: any }?)
	opts = opts or {}
	local n = math.max(2, math.floor((count or 10) * FX.Budget("Debris") + .5))
	local rng = Random.new()
	for _ = 1, n do
		local s = rng:NextNumber(.25, opts.MaxSize or .9)
		local part = FX.Part({ Size = Vector3.new(s, s * rng:NextNumber(.6, 1.2), s * rng:NextNumber(.6, 1.2)), Color = color,
			Material = material or Enum.Material.Slate, CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0) })
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(.6, 1.6), rng:NextNumber(-1, 1)).Unit
		table.insert(chunks, { Part = part, V = dir * (speed or 26) * rng:NextNumber(.5, 1.1), G = 90, T = 0, Life = rng:NextNumber(.9, 1.6),
			R = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)), Floor = (opts.Floor or pos.Y - 6), Base = 0 })
	end
	if not chunkConn then
		chunkConn = RunService.Heartbeat:Connect(stepChunks)
	end
end

function FX.Smoke(pos: Vector3, color: Color3, size: number?, duration: number?)
	size = size or 4
	return FX.Burst(pos, { Texture = FX.Textures.Smoke, Color = color, Color2 = color:Lerp(Color3.new(0, 0, 0), .4), Count = 10,
		Speed = { size * .4, size * 1.1 }, Lifetime = { (duration or 1.6) * .6, duration or 1.6 }, Size = { size * .5, size, size * 1.4 },
		Transparency = { .35, 1 }, LightEmission = .1, Drag = 3, Acceleration = Vector3.new(0, 2, 0) })
end

-- glowing cracks spreading over a surface (begin: grow, peak: bright, fade)
function FX.Cracks(pos: Vector3, normal: Vector3?, color: Color3, size: number?, duration: number?)
	normal = (normal and normal.Magnitude > 0) and normal.Unit or Vector3.new(0, 1, 0)
	size = size or 6
	duration = duration or 1.6
	local base = CFrame.lookAt(pos + normal * .06, pos + normal * 2)
	local rng = Random.new()
	local n = FX.Low() and 4 or 8
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-.3, .3)
		local len = size * rng:NextNumber(.35, .6)
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local mid = base * CFrame.new(dir * len * .5)
		local seg = FX.Part({ Color = color, Size = Vector3.new(.14, .14, .05), CFrame = mid * CFrame.Angles(0, 0, a) })
		FX.Tween(seg, .18, { Size = Vector3.new(len, .14 + rng:NextNumber(0, .08), .05) }, Enum.EasingStyle.Quad)
		task.delay(duration * .55, function()
			if seg.Parent then
				FX.Tween(seg, duration * .45, { Transparency = 1 })
			end
		end)
		Debris:AddItem(seg, duration + .1)
	end
	FX.Light(pos + normal, color, size * 2, 2, duration * .8)
end

function FX.Light(pos: Vector3, color: Color3, range: number?, brightness: number?, duration: number?)
	local p = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 14
	l.Brightness = 0
	l.Shadows = false
	l.Parent = p
	duration = duration or .8
	FX.Tween(l, duration * .2, { Brightness = brightness or 2 })
	task.delay(duration * .25, function()
		if l.Parent then
			FX.Tween(l, duration * .75, { Brightness = 0 })
		end
	end)
	Debris:AddItem(p, duration + .1)
	return l
end

-- floating world text (+12 CANDY, PERFECT!, numbers)
function FX.Popup(pos: Vector3, text: string, color: Color3?, big: boolean?)
	local p = FX.Part({ Size = Vector3.new(.2, .2, .2), Transparency = 1, CFrame = CFrame.new(pos) })
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(big and 260 or 170, big and 70 or 46)
	g.StudsOffset = Vector3.new(0, 1, 0)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.MaxDistance = 180
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = FONT
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t:SetAttribute("NoTranslate", true)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = big and 3 or 2
	stroke.Color = Color3.fromRGB(28, 12, 40)
	stroke.Parent = t
	local scale = Instance.new("UIScale")
	scale.Scale = .4
	scale.Parent = t
	t.Parent = g
	FX.Tween(scale, .22, { Scale = 1 }, Enum.EasingStyle.Back)
	FX.Tween(g, 1.2, { StudsOffset = Vector3.new(0, big and 6 or 4.5, 0) }, Enum.EasingStyle.Quad)
	task.delay(.75, function()
		if t.Parent then
			FX.Tween(t, .45, { TextTransparency = 1 })
			FX.Tween(stroke, .45, { Transparency = 1 })
		end
	end)
	Debris:AddItem(p, 1.3)
	return g
end

-- full-screen flash (Kit overlay layer is 95; flashes sit just under it)
local flashGui = nil
function FX.Flash(color: Color3?, strength: number?, duration: number?)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	if not flashGui or not flashGui.Parent then
		flashGui = Instance.new("ScreenGui")
		flashGui.Name = "DOGROTS_HalloweenFlash"
		flashGui.IgnoreGuiInset = true
		flashGui.ResetOnSpawn = false
		flashGui.DisplayOrder = 94
		flashGui:SetAttribute("NoTranslate", true)
		flashGui.Parent = player:WaitForChild("PlayerGui")
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or Color3.new(1, 1, 1)
	local s = math.clamp(strength or .5, 0, 1)
	if Shared.ReducedMotion() then
		s *= .5
	end
	f.BackgroundTransparency = 1 - s
	f.Parent = flashGui
	FX.Tween(f, duration or .35, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	Debris:AddItem(f, (duration or .35) + .05)
end

-- moderate camera shake: amount in studs-ish (0..1.5 recommended), decays over duration. No-op with ReducedMotion.
-- Overlapping shakes each keep their own amount + decay and the strongest one shows, so a weak later call (a boss
-- footstep) never stretches a strong shake, and a long weak rumble still runs on after a short strong one.
local shakes = {} -- {Amount, Decay}
local shakeBound = false
function FX.Shake(amount: number?, duration: number?)
	if Shared.ReducedMotion() then
		return
	end
	amount = math.clamp(amount or .4, 0, 1.6)
	if amount <= .001 then
		return
	end
	table.insert(shakes, { Amount = amount, Decay = amount / math.max(.1, duration or .45) })
	if #shakes > 8 then -- keep the list short: drop the weakest
		local weakest = 1
		for i, s in ipairs(shakes) do
			if s.Amount < shakes[weakest].Amount then
				weakest = i
			end
		end
		table.remove(shakes, weakest)
	end
	if shakeBound then
		return
	end
	shakeBound = true
	RunService:BindToRenderStep("DOGROTS_HalloweenShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local amp = 0
		for _, s in ipairs(shakes) do
			amp = math.max(amp, s.Amount)
		end
		if amp <= .001 then
			table.clear(shakes)
			RunService:UnbindFromRenderStep("DOGROTS_HalloweenShake")
			shakeBound = false
			return
		end
		local cam = workspace.CurrentCamera
		if cam then
			local t = os.clock() * 38
			local a = amp * .35
			cam.CFrame = cam.CFrame * CFrame.new(math.noise(t, 1.3) * a, math.noise(t, 7.9) * a, 0)
				* CFrame.Angles(0, 0, math.noise(t, 4.4) * a * .03)
		end
		for i = #shakes, 1, -1 do
			local s = shakes[i]
			s.Amount -= s.Decay * dt
			if s.Amount <= .001 then
				table.remove(shakes, i)
			end
		end
	end)
end

-- soft hit-pause feel without freezing the game: a very short FOV punch. Applied as a decaying OFFSET on top of whatever
-- FOV the camera has (never a captured absolute value), so it cannot leave the FOV narrower when another owner (the
-- HalloweenStrike hit kick, zooms) moves the FOV meanwhile: each frame our last offset is taken back only if nobody else
-- wrote the FOV since; a new punch while one runs restarts the curve without stacking.
local punch = nil -- {T0, Amp, Applied, Written}
function FX.Punch(strength: number?)
	if Shared.ReducedMotion() then
		return
	end
	if not workspace.CurrentCamera then
		return
	end
	local s = math.clamp(strength or 1, 0, 2)
	local running = punch ~= nil
	punch = { T0 = os.clock(), Amp = 2.2 * s, Applied = punch and punch.Applied or 0, Written = punch and punch.Written or nil }
	if running then
		return
	end
	RunService:BindToRenderStep("DOGROTS_HalloweenPunch", Enum.RenderPriority.Camera.Value + 3, function()
		local p = punch
		local cam = workspace.CurrentCamera
		if not p or not cam then
			punch = nil
			RunService:UnbindFromRenderStep("DOGROTS_HalloweenPunch")
			return
		end
		local fov = cam.FieldOfView
		if p.Written and math.abs(fov - p.Written) < 1e-3 then
			fov += p.Applied -- still our value: take the last offset back
		end
		local e = (os.clock() - p.T0) / .16
		p.Applied = e < 1 and p.Amp * (1 - e) ^ 2 or 0
		p.Written = fov - p.Applied
		cam.FieldOfView = p.Written
		if e >= 1 then
			punch = nil
			RunService:UnbindFromRenderStep("DOGROTS_HalloweenPunch")
		end
	end)
end

return FX
