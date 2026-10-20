-- Visuals + feedback of the Halloween ore nodes and Haunted Dig Spots (StarterPlayerScripts.HalloweenClient.SpotFX).
-- The server only places invisible target parts (ServerScriptService.Halloween.Strike, kinds "Ore" / "DigSpot"); this
-- module builds the premium models locally (RS.Halloween.Models.Spots) in workspace.DOGROTS_HalloweenFX (SelfManagedFX)
-- and plays everything around them:
--   spawn      the model rises out of the ground with a dust ring, debris and a thump (dig spots at Blood Moon start)
--   idle       per-type loops (begin -> peak -> fade): glow pulse, particles (embers, ghost smoke, fireflies, green
--              mist, gold sparkles), orbiting shards / bobbing ghost / breathing chest lid, flickering jack-o'-lanterns
--   dig        soil / rock chunks, type particles, a jolt of the model (+ hit pause on Perfect), glow flash, a themed
--              sound layer; details crumble off as HP drops (HwStage parts)
--   break      shatter + shockwave + burst (+ the treasure chest bursting open); rare finds: screen accent, special
--              sound, loot beam coloured by the event mutation (+ Bus RareFind)
--   sink       spots sink back into the ground when the moon ends / they expire
--   companion  when YOU dig a spot a spectral copy of your best assigned dog digs beside it (MenuModels clone,
--              translucent + Highlight); on GHOST SOIL its swings phase through ("MISS") unless your team has an event dog
-- Budgets: Lite models + fewer particles on Low, nearest-N lights, animation only near the camera, ReducedMotion = no jolt.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SpotFX = {}

local TAG = "HalloweenTarget"
local KINDS = { Ore = true, DigSpot = true }
local BUILD_DIST = 230
local ANIM_DIST = 95
local LABEL_DIST = 46
local RISE_TIME = 1.15
local C = Color3.fromRGB

-- particle looks per variant (all built-in textures)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local IDLE = {
	PumpkinOre = { { Point = "Rise", Texture = FIRE, Color = C(255, 140, 40), Color2 = C(255, 60, 20), Rate = 7, Life = { .7, 1.3 }, Speed = { 1.5, 3.5 },
		Size = { .5, .8, 0 }, Accel = Vector3.new(0, 4, 0), Spread = 40, Light = 1 },
		{ Point = "Core", Texture = SPARK, Color = C(255, 200, 90), Rate = 3, Life = { .8, 1.4 }, Speed = { .5, 1.5 }, Size = { .25, .4, 0 }, Light = 1 } },
	GraveStone = { { Point = "Rise", Texture = SPARK, Color = C(150, 255, 170), Rate = 6, Life = { 1, 1.8 }, Speed = { .6, 1.6 }, Size = { .3, .5, 0 },
		Accel = Vector3.new(0, 1.2, 0), Light = 1 },
		{ Point = "Core", Texture = SMOKE, Color = C(120, 220, 140), Rate = 2, Life = { 2, 3 }, Speed = { .3, .8 }, Size = { 1.2, 2.4, 3 }, Trans = { .7, 1 },
			Accel = Vector3.new(0, .4, 0), Light = .3 } },
	MoonShard = { { Point = "Rise", Texture = SPARK, Color = C(200, 140, 255), Color2 = C(255, 255, 255), Rate = 8, Life = { .9, 1.7 }, Speed = { .5, 1.4 },
		Size = { .35, .55, 0 }, Accel = Vector3.new(0, 1.5, 0), Light = 1 },
		{ Point = "Core", Texture = SPARK, Color = C(236, 210, 255), Rate = 4, Life = { .6, 1.2 }, Speed = { .2, .6 }, Size = { .4, .7, 0 }, Light = 1 } },
	CursedSoil = { { Point = "Rise", Texture = FIRE, Color = C(255, 60, 50), Color2 = C(120, 10, 20), Rate = 6, Life = { .8, 1.4 }, Speed = { 1, 2.6 },
		Size = { .35, .55, 0 }, Accel = Vector3.new(0, 3, 0), Spread = 35, Light = 1 },
		{ Point = "Ground", Texture = SMOKE, Color = C(90, 16, 24), Rate = 3, Life = { 2, 3.2 }, Speed = { .4, 1 }, Size = { 1.6, 3, 4 }, Trans = { .55, 1 },
			Accel = Vector3.new(0, .5, 0), Light = 0, Shape = "Disc", Radius = 3.4 } },
	GhostSoil = { { Point = "Rise", Texture = SMOKE, Color = C(210, 240, 255), Rate = 5, Life = { 1.6, 2.6 }, Speed = { .8, 1.8 }, Size = { .8, 1.8, 2.4 },
		Trans = { .45, 1 }, Accel = Vector3.new(0, 1.4, 0), Light = .6, Spread = 25 },
		{ Point = "Ground", Texture = SMOKE, Color = C(180, 220, 255), Rate = 4, Life = { 2.2, 3.4 }, Speed = { .3, .8 }, Size = { 1.4, 2.8, 3.6 },
			Trans = { .6, 1 }, Accel = Vector3.new(0, .2, 0), Light = .4, Shape = "Disc", Radius = 3.6 } },
	PumpkinPatch = { { Point = "Rise", Texture = SPARK, Color = C(255, 210, 90), Rate = 4, Life = { 1.6, 2.6 }, Speed = { .3, .9 }, Size = { .22, .32, 0 },
		Accel = Vector3.new(0, .3, 0), Light = 1, Spread = 180 },
		{ Point = "Core", Texture = FIRE, Color = C(255, 150, 40), Rate = 3, Life = { .4, .8 }, Speed = { .5, 1.2 }, Size = { .3, .5, 0 }, Light = 1 } },
	BoneGrave = { { Point = "Rise", Texture = SMOKE, Color = C(130, 255, 150), Rate = 3, Life = { 2, 3 }, Speed = { .3, .8 }, Size = { 1, 2.2, 3 }, Trans = { .6, 1 },
		Accel = Vector3.new(0, .4, 0), Light = .5 },
		{ Point = "Core", Texture = SPARK, Color = C(170, 255, 180), Rate = 4, Life = { .8, 1.4 }, Speed = { .4, 1 }, Size = { .25, .4, 0 }, Light = 1 } },
	CursedTreasure = { { Point = "Core", Texture = SPARK, Color = C(255, 220, 110), Color2 = C(255, 255, 255), Rate = 12, Life = { .8, 1.6 }, Speed = { 2, 4.5 },
		Size = { .3, .5, 0 }, Accel = Vector3.new(0, -2, 0), Spread = 30, Light = 1 },
		{ Point = "Ground", Texture = FIRE, Color = C(190, 90, 255), Color2 = C(90, 30, 170), Rate = 6, Life = { .8, 1.4 }, Speed = { .6, 1.6 }, Size = { .3, .5, 0 },
			Accel = Vector3.new(0, 2.5, 0), Light = 1, Shape = "Disc", Radius = 4.2 } },
}
-- dig feedback particles per variant
local DIG = {
	CursedSoil = { Color = C(255, 70, 60), Color2 = C(120, 10, 20), Texture = FIRE },
	GhostSoil = { Color = C(220, 245, 255), Color2 = C(140, 200, 255), Texture = SMOKE, Smoke = true },
	PumpkinPatch = { Color = C(255, 150, 40), Color2 = C(255, 230, 140), Texture = SPARK, Seeds = true },
	BoneGrave = { Color = C(236, 226, 200), Color2 = C(150, 255, 170), Texture = SPARK, Bones = true },
	CursedTreasure = { Color = C(255, 214, 90), Color2 = C(190, 90, 255), Texture = SPARK, Coins = true },
	PumpkinOre = { Color = C(255, 140, 40), Color2 = C(255, 220, 120), Texture = FIRE },
	GraveStone = { Color = C(150, 255, 170), Color2 = C(220, 255, 230), Texture = SPARK },
	MoonShard = { Color = C(200, 140, 255), Color2 = C(255, 255, 255), Texture = SPARK },
}

function SpotFX.Start(ctx)
	local player = Players.LocalPlayer
	local Shared, Bus, FX, Audio = ctx.Shared, ctx.Bus, ctx.FX, ctx.Audio
	local L = Shared.L
	local Halloween = RS:WaitForChild("Halloween")
	local Spots = require(Halloween:WaitForChild("Models"):WaitForChild("Spots"))
	local views = {} -- part -> view
	local buildQueue = {}
	local companion = nil

	local function low(): boolean
		return Shared.Low()
	end
	local function reduced(): boolean
		return Shared.ReducedMotion()
	end
	local function play(cue: string, where: any, opts: any?)
		if Audio and Audio.Has and Audio.Has(cue) then
			Audio.Play(cue, where, opts)
		end
	end
	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function infoOf(variant: string?)
		return Spots.Info[variant or ""] or Spots.Info.CursedSoil
	end
	local function accentOf(view): Color3
		return view.Info.Accent or C(255, 200, 120)
	end
	local function soilOf(view): Color3
		return view.Info.Soil or view.Info.Rock or C(70, 56, 44)
	end

	---------------------------------------------------------------------------------------------------------------
	-- model build / placement
	---------------------------------------------------------------------------------------------------------------
	local function groundCF(part: BasePart): CFrame
		local g = part:GetAttribute("Ground")
		local pos = typeof(g) == "Vector3" and g or (part.CFrame.Position - Vector3.new(0, part.Size.Y / 2, 0))
		return CFrame.new(pos) * CFrame.Angles(0, part:GetAttribute("Facing") or 0, 0)
	end

	local function makeEmitters(view)
		local rows = IDLE[view.Variant]
		if not rows then
			return
		end
		local k = FX.Budget("Particles")
		for _, row in ipairs(rows) do
			local att = nil
			for _, a in ipairs(view.Root:GetChildren()) do
				if a:IsA("Attachment") and a.Name == "FXPoint" and a:GetAttribute("FX") == row.Point then
					att = a
				end
			end
			if att then
				local e = Instance.new("ParticleEmitter")
				e.Name = "SpotIdle"
				e.Texture = row.Texture
				e.Color = ColorSequence.new(row.Color, row.Color2 or row.Color)
				e.LightEmission = row.Light or 1
				e.LightInfluence = 0
				e.Lifetime = NumberRange.new(row.Life[1], row.Life[2])
				e.Speed = NumberRange.new(row.Speed[1], row.Speed[2])
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, row.Size[1] * .3), NumberSequenceKeypoint.new(.35, row.Size[2]),
					NumberSequenceKeypoint.new(1, row.Size[3]) })
				local tr = row.Trans or { .1, 1 }
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, tr[1]), NumberSequenceKeypoint.new(1, tr[2]) })
				e.Acceleration = row.Accel or Vector3.zero
				e.SpreadAngle = Vector2.new(row.Spread or 180, row.Spread or 180)
				e.RotSpeed = NumberRange.new(-40, 40)
				e.Rotation = NumberRange.new(0, 360)
				e.Drag = 1
				if row.Shape == "Disc" then
					e.Shape = Enum.ParticleEmitterShape.Disc
					e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
					local holder = Instance.new("Part")
					holder.Name = "EmitterDisc"
					holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
					holder.Transparency = 1
					holder.Size = Vector3.new(row.Radius * 2, .2, row.Radius * 2)
					holder.CFrame = view.Root.CFrame * CFrame.new(att.Position)
					holder.Parent = view.Model
					e.Parent = holder
				else
					e.Parent = att
				end
				e.Rate = 0
				table.insert(view.Emitters, { E = e, Base = row.Rate * k })
			end
		end
	end

	local function build(view)
		if view.Model or not view.Part.Parent then
			return
		end
		local seed = view.Part:GetAttribute("Seed") or 1
		local model = Spots.Build(view.Variant, seed, { Lite = low() })
		if not model then
			return
		end
		view.Model = model
		view.Root = model.PrimaryPart
		view.Base = groundCF(view.Part)
		view.Anim, view.Glows, view.Stages, view.Lights, view.Emitters = {}, {}, {}, {}, {}
		model:PivotTo(view.Base)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local a = d:GetAttribute("HwAnim")
				if a then
					table.insert(view.Anim, { Part = d, Kind = a, Rel = view.Base:ToObjectSpace(d.CFrame), Phase = d:GetAttribute("HwPhase") or 0,
						Speed = d:GetAttribute("HwSpeed") or 1, Amp = d:GetAttribute("HwAmp") or .3, Hinge = d:GetAttribute("HwHinge"),
						Color = d.Color, T = d.Transparency })
				end
				if d:GetAttribute("HwGlow") then
					table.insert(view.Glows, { Part = d, Color = d.Color })
				end
				local st = d:GetAttribute("HwStage")
				if st then
					view.Stages[st] = view.Stages[st] or {}
					table.insert(view.Stages[st], d)
				end
			elseif d:IsA("PointLight") then
				table.insert(view.Lights, { L = d, Base = d:GetAttribute("Base") or d.Brightness })
				d.Enabled = false
			end
		end
		makeEmitters(view)
		-- a tall beacon over the cursed treasure so it can be found across the yard
		if view.Variant == "CursedTreasure" then
			local beacon = Instance.new("Part")
			beacon.Name = "TreasureBeacon"
			beacon.Shape = Enum.PartType.Cylinder
			beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch, beacon.CastShadow = true, false, false, false, false
			beacon.Material = Enum.Material.Neon
			beacon.Color = C(255, 210, 110)
			beacon.Transparency = .72
			beacon.Size = Vector3.new(60, 1.4, 1.4)
			beacon.CFrame = view.Base * CFrame.new(0, 33, 0) * CFrame.Angles(0, 0, math.pi / 2)
			beacon.Parent = model
			table.insert(view.Anim, { Part = beacon, Kind = "Pulse", Rel = view.Base:ToObjectSpace(beacon.CFrame), Phase = 0, Speed = 1, Amp = .2,
				Color = beacon.Color, T = .72 })
		end
		model.Parent = FX.Folder()
		view.Phase = math.random() * 10
		view.Period = 4 + math.random() * 3
		-- spawn: rise from the ground (fresh targets only)
		local born = view.Part:GetAttribute("BornAt") or 0
		if Shared.Now() - born < 2.5 and not view.Risen then
			view.Risen = true
			view.RiseAt = os.clock()
			view.Offset = -((model:GetAttribute("Height") or 3) + 1.2)
			model:PivotTo(view.Base * CFrame.new(0, view.Offset, 0))
			local pos = view.Base.Position
			FX.Ring(pos, soilOf(view):Lerp(C(255, 255, 255), .3), (model:GetAttribute("Radius") or 4) + 4, .7)
			FX.Smoke(pos + Vector3.new(0, 1, 0), soilOf(view):Lerp(C(160, 150, 170), .4), 4, 1.6)
			FX.Debris(pos + Vector3.new(0, .5, 0), soilOf(view), Enum.Material.Ground, 8, 18, { Floor = pos.Y })
			play(view.Kind == "Ore" and "OreBreak" or "DigSoil", pos, { Volume = .6, Pitch = .7 })
			if view.Variant == "CursedTreasure" then
				play("TreasureReveal", pos, { Volume = .8 })
			end
		else
			view.Offset = 0
		end
	end

	local function destroyModel(view)
		if view.Model then
			view.Model:Destroy()
		end
		view.Model = nil
	end

	---------------------------------------------------------------------------------------------------------------
	-- labels (name + HP)
	---------------------------------------------------------------------------------------------------------------
	local function makeLabel(view)
		local g = Instance.new("BillboardGui")
		g.Name = "SpotLabel"
		g.Size = UDim2.fromOffset(220, 52)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.MaxDistance = LABEL_DIST
		g.StudsOffsetWorldSpace = Vector3.new(0, view.Part.Size.Y / 2 + 1.6, 0)
		g:SetAttribute("NoTranslate", true)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, 26)
		name.FontFace = FX.Font
		name.TextScaled = true
		name.TextColor3 = accentOf(view):Lerp(C(255, 255, 255), .35)
		name.TextStrokeTransparency = 0
		name.TextStrokeColor3 = C(28, 12, 40)
		name.Text = Spots.Label(view.Variant, Shared.IsRussian())
		name:SetAttribute("NoTranslate", true)
		name.Parent = g
		local back = Instance.new("Frame")
		back.Position = UDim2.new(.15, 0, 0, 31)
		back.Size = UDim2.new(.7, 0, 0, 10)
		back.BackgroundColor3 = C(18, 10, 28)
		back.BorderSizePixel = 0
		back.Visible = false
		back.Parent = g
		local c1 = Instance.new("UICorner")
		c1.CornerRadius = UDim.new(1, 0)
		c1.Parent = back
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = accentOf(view)
		fill.Parent = back
		local c2 = Instance.new("UICorner")
		c2.CornerRadius = UDim.new(1, 0)
		c2.Parent = fill
		g.Adornee = view.Part
		g.Parent = FX.Folder()
		view.Label, view.LabelBar, view.LabelFill = g, back, fill
	end

	local function updateHP(view)
		local hp, max = view.Part:GetAttribute("HP") or 1, math.max(view.Part:GetAttribute("MaxHP") or 1, 1e-3)
		local frac = math.clamp(hp / max, 0, 1)
		if view.LabelFill then
			view.LabelBar.Visible = frac < .999
			view.LabelFill.Size = UDim2.fromScale(frac, 1)
		end
		-- details crumble off as the target loses HP
		if not view.Model then
			return
		end
		local stage = frac < .25 and 3 or frac < .5 and 2 or frac < .75 and 1 or 0
		for s = (view.Stage or 0) + 1, stage do
			for _, p in ipairs(view.Stages[s] or {}) do
				if p.Parent and p.Transparency < 1 then
					if not low() then
						FX.Debris(p.CFrame.Position, p.Color, p.Material, 2, 16, { Floor = view.Base.Position.Y, MaxSize = .5 })
					end
					p.Transparency = 1
				end
			end
			if view.Kind == "DigSpot" then
				view.Dug = (view.Dug or 0) + .14 -- the heap is dug lower
			end
		end
		view.Stage = math.max(view.Stage or 0, stage)
	end

	---------------------------------------------------------------------------------------------------------------
	-- tracking
	---------------------------------------------------------------------------------------------------------------
	local sink, shatter

	local function attach(part: Instance)
		if views[part] or not part:IsA("BasePart") or not KINDS[part:GetAttribute("Kind") or ""] then
			return
		end
		local view = { Part = part, Kind = part:GetAttribute("Kind"), Variant = part:GetAttribute("Variant") or "CursedSoil", Id = part:GetAttribute("TargetId"),
			Jolt = Vector3.zero, JoltUntil = 0, HoldUntil = 0, FlashUntil = 0 }
		view.Info = infoOf(view.Variant)
		views[part] = view
		table.insert(buildQueue, view)
		makeLabel(view)
		updateHP(view)
		view.Conns = {
			part:GetAttributeChangedSignal("HP"):Connect(function()
				updateHP(view)
			end),
			part:GetAttributeChangedSignal("EndReason"):Connect(function()
				local reason = part:GetAttribute("EndReason")
				if reason == "Broke" then
					shatter(view)
				else
					sink(view)
				end
			end),
		}
	end

	local function detach(part: Instance, keepModel: boolean?)
		local view = views[part]
		if not view then
			return
		end
		views[part] = nil
		for _, c in ipairs(view.Conns or {}) do
			c:Disconnect()
		end
		if view.Label then
			view.Label:Destroy()
		end
		if not keepModel then
			destroyModel(view)
		end
	end

	-- spot sinks back into the ground (moon ended / expired / removed)
	sink = function(view)
		if view.Gone then
			return
		end
		view.Gone = true
		detach(view.Part, true)
		local model = view.Model
		if not model then
			return
		end
		local pos = view.Base.Position
		FX.Smoke(pos + Vector3.new(0, .8, 0), soilOf(view):Lerp(C(150, 140, 160), .4), 4.5, 1.8)
		FX.Ring(pos, soilOf(view):Lerp(C(255, 255, 255), .25), (model:GetAttribute("Radius") or 4) + 3, .9)
		if (pos - camPos()).Magnitude < 80 then
			play("DigSoil", pos, { Volume = .5, Pitch = .6 })
		end
		local depth = (model:GetAttribute("Height") or 3) + 2
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - t0) / 1.3, 0, 1)
			if not model.Parent or a >= 1 then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local e = a * a
			model:PivotTo(view.Base * CFrame.new(math.sin(os.clock() * 40) * .06 * (1 - a), -depth * e, 0))
		end)
	end

	-- the target broke: shatter (treasure: the chest bursts open first)
	shatter = function(view)
		if view.Gone then
			return
		end
		view.Gone = true
		detach(view.Part, true)
		local model = view.Model
		local pos = view.Base and view.Base.Position or view.Part.CFrame.Position
		local accent = accentOf(view)
		local near = (pos - camPos()).Magnitude < 120
		local function burst()
			if near then
				FX.Shockwave(pos + Vector3.new(0, .3, 0), accent, (view.Info.Radius or 4) + 5, .7)
				FX.Burst(pos + Vector3.new(0, 2, 0), { Color = accent, Color2 = C(255, 255, 255), Count = 30, Speed = { 12, 26 }, Lifetime = { .5, 1.1 },
					Size = { .5, .9, 0 }, Drag = 3, Acceleration = Vector3.new(0, -14, 0) })
				FX.Debris(pos + Vector3.new(0, 1.5, 0), soilOf(view), view.Info.Chip or Enum.Material.Ground, 14, 28, { Floor = pos.Y })
				FX.Smoke(pos + Vector3.new(0, 1.2, 0), soilOf(view):Lerp(C(180, 170, 190), .35), 5, 1.6)
				FX.Light(pos + Vector3.new(0, 3, 0), accent, 26, 4, 1)
				local dig = DIG[view.Variant]
				if dig and dig.Bones then
					FX.Debris(pos + Vector3.new(0, 1.5, 0), C(236, 226, 200), Enum.Material.SmoothPlastic, 8, 22, { Floor = pos.Y, MaxSize = .6 })
				elseif dig and dig.Seeds then
					FX.Debris(pos + Vector3.new(0, 1.5, 0), C(255, 128, 24), Enum.Material.SmoothPlastic, 10, 24, { Floor = pos.Y, MaxSize = .7 })
				end
			end
			if view.Kind == "Ore" then
				play("OreBreak", pos)
			else
				play(view.Info.Sound or "DigSoil", pos)
			end
			if model then
				model:Destroy()
			end
		end
		if view.Variant == "CursedTreasure" and model and model.Parent and near then
			-- the lid flies open, a gold geyser, then the mound collapses
			play("TreasureReveal", pos)
			for _, a in ipairs(view.Anim or {}) do
				if a.Kind == "Lid" and a.Part.Parent and a.Hinge then
					local h = view.Base * CFrame.new(a.Hinge)
					local goal = h * CFrame.Angles(-1.6, 0, 0) * h:ToObjectSpace(view.Base * a.Rel)
					FX.Tween(a.Part, .35, { CFrame = goal }, Enum.EasingStyle.Back)
				end
			end
			view.Anim = {}
			FX.Burst(pos + Vector3.new(0, 3.5, 0), { Color = C(255, 214, 90), Color2 = C(255, 255, 220), Count = 40, Speed = { 14, 26 }, Spread = 25,
				Direction = Vector3.new(0, 1, 0), Lifetime = { .8, 1.4 }, Size = { .45, .7, 0 }, Acceleration = Vector3.new(0, -30, 0), Drag = 1 })
			FX.Debris(pos + Vector3.new(0, 3, 0), C(255, 200, 70), Enum.Material.Foil, 14, 26, { Floor = pos.Y, MaxSize = .5 })
			FX.Light(pos + Vector3.new(0, 4, 0), C(255, 210, 110), 30, 5, 1.6)
			task.delay(.9, burst)
		else
			burst()
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- dig feedback
	---------------------------------------------------------------------------------------------------------------
	local function digFeedback(data)
		local part = data.Part
		local view = part and views[part]
		if not view then
			return
		end
		local pos = typeof(data.Position) == "Vector3" and data.Position or part.CFrame.Position
		local normal = typeof(data.Normal) == "Vector3" and data.Normal.Magnitude > .01 and data.Normal.Unit or Vector3.new(0, 1, 0)
		if normal.Y > .995 then
			normal = Vector3.new(.08, 1, .05).Unit -- never exactly vertical (look-at helpers)
		end
		local dig = DIG[view.Variant] or DIG.CursedSoil
		local remote = data.Remote == true
		local k = remote and .5 or 1
		local floorY = view.Base and view.Base.Position.Y or pos.Y - 3
		-- chunks of the soil / rock
		FX.Debris(pos, soilOf(view), view.Info.Chip or Enum.Material.Ground, math.floor((data.Perfect and 7 or 4) * k + .5), data.Perfect and 22 or 16,
			{ Floor = floorY, MaxSize = .6 })
		FX.Burst(pos, { Texture = dig.Texture, Color = dig.Color, Color2 = dig.Color2, Count = math.floor((data.Perfect and 16 or 9) * k + .5),
			Speed = { 5, 12 }, Lifetime = { .4, .9 }, Size = { .3, .6, 0 }, Direction = normal, Spread = 60, Drag = 3, Acceleration = Vector3.new(0, -10, 0),
			Transparency = dig.Smoke and { .4, 1 } or { 0, 1 } })
		if dig.Coins and not remote then
			FX.Debris(pos, C(255, 200, 70), Enum.Material.Foil, data.Perfect and 5 or 3, 18, { Floor = floorY, MaxSize = .4 })
		elseif dig.Bones and not remote then
			FX.Debris(pos, C(236, 226, 200), Enum.Material.SmoothPlastic, data.Perfect and 4 or 2, 18, { Floor = floorY, MaxSize = .5 })
		elseif dig.Seeds and not remote then
			FX.Debris(pos, C(255, 230, 160), Enum.Material.SmoothPlastic, data.Perfect and 5 or 3, 14, { Floor = floorY, MaxSize = .25 })
		end
		if dig.Smoke then
			FX.Smoke(pos, C(220, 240, 255), 2.2, 1.2)
		end
		-- the model jolts (and holds still for the hit pause on a Perfect)
		if view.Model and not reduced() then
			local away = (view.Base.Position - pos)
			away = Vector3.new(away.X, 0, away.Z)
			away = away.Magnitude > .05 and away.Unit or Vector3.new(0, 0, 1)
			view.Jolt = away * (data.Perfect and .32 or .18) * k + Vector3.new(0, -(data.Perfect and .12 or .06) * k, 0)
			view.JoltUntil = os.clock() + (data.HitStop or 0) + .1
			view.HoldUntil = os.clock() + (data.HitStop or 0)
		end
		view.FlashUntil = os.clock() + (data.Perfect and .22 or .12)
		if not remote then
			play(view.Info.Sound or "DigSoil", pos, { Volume = data.Perfect and .55 or .4 })
			if data.Perfect then
				FX.Light(pos + normal, dig.Color, 12, 2.5, .35)
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- companion dog
	---------------------------------------------------------------------------------------------------------------
	local Rig, AnimPlayer = nil, nil
	pcall(function()
		Rig = require(RS:WaitForChild("DogRig", 10))
		AnimPlayer = require(RS:WaitForChild("DogAnimationPlayer", 10))
	end)

	local function removeCompanion(fade: boolean?)
		local c = companion
		companion = nil
		if not c then
			return
		end
		if c.Model and c.Model.Parent then
			if fade then
				FX.Smoke(c.Model:GetPivot().Position + Vector3.new(0, 1.5, 0), C(200, 235, 255), 3, 1.2)
				for _, p in ipairs(c.Parts) do
					FX.Tween(p, .5, { Transparency = 1 })
				end
				if c.Highlight then
					FX.Tween(c.Highlight, .5, { FillTransparency = 1, OutlineTransparency = 1 })
				end
				Debris:AddItem(c.Model, .6)
			else
				c.Model:Destroy()
			end
		end
		if c.Player then
			pcall(function()
				c.Player:Destroy()
			end)
		end
		if c.FX then
			pcall(c.FX.Stop)
		end
	end

	-- event dogs (HW_*) carry their own ability FX hooks (Models.EventDogs.StartFX)
	local EventDogs = nil
	local function eventFX(model: Model, id: any)
		if type(id) ~= "string" or string.sub(id, 1, 3) ~= "HW_" then
			return nil
		end
		if EventDogs == nil then
			local ok, m = pcall(function()
				return require(RS:WaitForChild("Halloween"):WaitForChild("Models"):WaitForChild("EventDogs"))
			end)
			EventDogs = ok and m or false
		end
		if not EventDogs or type(EventDogs.StartFX) ~= "function" then
			return nil
		end
		local ok, h = pcall(EventDogs.StartFX, model, { Low = Shared.Low(), Intensity = .7 })
		return ok and h or nil
	end

	local function spawnCompanion(part: BasePart, info: any)
		removeCompanion(false)
		if type(info) ~= "table" or type(info.Asset) ~= "string" or not Rig then
			return
		end
		local menu = RS:FindFirstChild("MenuModels")
		local template = menu and menu:FindFirstChild(info.Asset)
		if not (template and template:IsA("Model")) then
			return
		end
		local model = template:Clone()
		local ok = pcall(function()
			Rig.Prepare(model, Vector3.new(4.6, 3.6, 4.6))
		end)
		if not ok then
			model:Destroy()
			return
		end
		local view = views[part]
		local base = view and view.Base or groundCF(part)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local toPlayer = root and (root.Position - base.Position) or Vector3.new(0, 0, -1)
		toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		toPlayer = toPlayer.Magnitude > .1 and toPlayer.Unit or Vector3.new(0, 0, -1)
		local side = CFrame.Angles(0, math.rad(70), 0):VectorToWorldSpace(toPlayer)
		local radius = (part:GetAttribute("Radius") or 4) + 1.1
		local at = base.Position + side * radius
		-- face the spot (dogs look along -Z of their pivot)
		local look = (base.Position - at)
		local yaw = math.atan2(-look.X, -look.Z)
		Rig.Place(model, at, CFrame.Angles(0, yaw, 0))
		local parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.CastShadow = false
				d.Transparency = math.max(d.Transparency, .38)
				table.insert(parts, d)
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = math.max(d.Transparency, .4)
			end
		end
		local hl = Instance.new("Highlight")
		hl.FillColor = C(150, 215, 255)
		hl.OutlineColor = C(220, 245, 255)
		hl.FillTransparency = .55
		hl.OutlineTransparency = .1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		model.Name = "SpectralCompanion"
		model.Parent = FX.Folder()
		local animPlayer = nil
		if AnimPlayer then
			pcall(function()
				local id = AnimPlayer.DogIdFor and AnimPlayer.DogIdFor(info.Asset) or info.Id
				animPlayer = AnimPlayer.new(model, info.Id or id)
				local clip = AnimPlayer.ResolveName(info.Id or id, "Work") or AnimPlayer.ResolveName(info.Id or id, "Idle")
				if clip then
					animPlayer:Play(clip, { Looped = true })
				end
			end)
		end
		FX.Smoke(at + Vector3.new(0, 1.2, 0), C(210, 240, 255), 3, 1.2)
		FX.Burst(at + Vector3.new(0, 1.5, 0), { Color = C(200, 235, 255), Count = 14, Speed = { 3, 8 }, Lifetime = { .5, 1 }, Size = { .3, .5, 0 } })
		play("GhostWoo", at, { Volume = .5 })
		companion = { Model = model, Parts = parts, Highlight = hl, Player = animPlayer, Part = part, At = at, NextPuff = 0,
			FX = eventFX(model, info.Id) }
	end

	---------------------------------------------------------------------------------------------------------------
	-- rewards / rare finds / announcements
	---------------------------------------------------------------------------------------------------------------
	local accentGui = nil
	local function screenAccent(color: Color3)
		local pg = player:FindFirstChild("PlayerGui")
		if not pg then
			return
		end
		if not accentGui or not accentGui.Parent then
			accentGui = Instance.new("ScreenGui")
			accentGui.Name = "DOGROTS_HalloweenAccent"
			accentGui.IgnoreGuiInset = true
			accentGui.ResetOnSpawn = false
			accentGui.DisplayOrder = 93
			accentGui:SetAttribute("NoTranslate", true)
			accentGui.Parent = pg
		end
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.Parent = accentGui
		local edges = {
			{ UDim2.new(1, 0, .22, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, .22, 0), UDim2.fromScale(0, .78), 270 },
			{ UDim2.new(.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(.16, 0, 1, 0), UDim2.fromScale(.84, 0), 180 },
		}
		local frames = {}
		for _, e in ipairs(edges) do
			local f = Instance.new("Frame")
			f.Size = e[1]
			f.Position = e[2]
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color
			f.BackgroundTransparency = 1
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			g.Rotation = e[3]
			g.Parent = f
			f.Parent = holder
			table.insert(frames, f)
		end
		local peak = reduced() and .55 or .2
		for _, f in ipairs(frames) do
			FX.Tween(f, .18, { BackgroundTransparency = peak })
		end
		task.delay(.6, function()
			for _, f in ipairs(frames) do
				FX.Tween(f, 1.1, { BackgroundTransparency = 1 })
			end
		end)
		Debris:AddItem(holder, 1.9)
	end

	local function mutationColor(name: string?): Color3
		local def = Shared.MutationDef(name)
		return def and Shared.Color(def.Color) or C(255, 214, 90)
	end
	local function mutationAccent(name: string?): Color3
		local def = Shared.MutationDef(name)
		return def and Shared.Color(def.Accent or def.Color) or C(255, 240, 160)
	end

	local function onReward(d)
		if type(d) ~= "table" then
			return
		end
		local pos = typeof(d.Position) == "Vector3" and d.Position or nil
		local top = pos and pos + Vector3.new(0, 4, 0)
		local candy = tonumber(d.Candy) or 0
		if top and candy > 0 then
			FX.Popup(top, "+" .. candy .. " 🍬", C(255, 170, 60), true)
		end
		play(candy >= 8 and "CandyBig" or "CandyTick")
		local bones = tonumber(d.Bones) or 0
		if top and bones > 0 then
			task.delay(.2, function()
				FX.Popup(top - Vector3.new(0, 1.4, 0), "+" .. bones .. " 🦴", C(236, 226, 200), false)
			end)
		end
		if d.Full then
			Bus.Fire("Toast", { Text = L("Your find storage is full: sell finds to get rare loot", "Хранилище находок заполнено: продай находки, чтобы получать редкую добычу"),
				Kind = "error", NoTranslate = true })
		end
		if (d.Rare or d.GhostLoot or d.Treasure) and companion and companion.FX then
			pcall(companion.FX.Burst, 12) -- the event dog's ability flares on the find
		end
		if d.Rare and type(d.Item) == "table" and pos then
			local item = d.Item
			local color = mutationColor(item.Mutation)
			local accent = mutationAccent(item.Mutation)
			-- RARE FIND: screen accent + special sound + loot beam
			screenAccent(accent)
			FX.Flash(accent, .28, .5)
			play(d.Treasure and "TreasureReveal" or "RareFind")
			FX.Beam(pos + Vector3.new(0, .5, 0), color:Lerp(accent, .4), 34, 5.5)
			FX.Burst(pos + Vector3.new(0, 2.5, 0), { Color = accent, Color2 = C(255, 255, 255), Count = 26, Speed = { 8, 18 }, Lifetime = { .6, 1.2 },
				Size = { .4, .7, 0 }, Drag = 2 })
			local label = (d.GhostLoot and L("GHOST LOOT! ", "ПРИЗРАЧНАЯ ДОБЫЧА! ") or L("RARE FIND! ", "РЕДКАЯ НАХОДКА! ")) .. tostring(item.Mutation or "")
			task.delay(.35, function()
				FX.Popup(pos + Vector3.new(0, 6.5, 0), label, accent, true)
			end)
			Bus.Fire("RareFind", { Item = item, Position = pos })
		end
		if d.Treasure then
			Bus.Fire("Banner", { Title = L("CURSED TREASURE!", "ПРОКЛЯТЫЙ КЛАД!"), Subtitle = L("Dug up under the Blood Moon", "Выкопан под Кровавой Луной"),
				Color = C(190, 90, 255), Style = "Event", Seconds = 3 })
		end
	end

	local function onFind(d)
		if type(d) ~= "table" or d.UserId == player.UserId or typeof(d.Position) ~= "Vector3" then
			return
		end
		if (d.Position - camPos()).Magnitude > 200 then
			return
		end
		local item = type(d.Item) == "table" and d.Item or {}
		FX.Beam(d.Position + Vector3.new(0, .5, 0), mutationColor(item.Mutation):Lerp(mutationAccent(item.Mutation), .4), 26, 4)
		play("Sparkle", d.Position, { Volume = .6 })
	end

	local function onAnnounce(d)
		if type(d) ~= "table" then
			return
		end
		if d.Kind == "TreasureSpawn" then
			Bus.Fire("Toast", { Text = L("A CURSED TREASURE surfaced in the Dead Yard!", "В Мёртвом Дворе показался ПРОКЛЯТЫЙ КЛАД!"), Kind = "event", NoTranslate = true })
			if Shared.InZone((player.Character and player.Character:GetPivot().Position) or Vector3.zero, 4) then
				play("TreasureReveal", nil, { Volume = .55 })
			end
		elseif d.Kind == "TreasureDug" and d.UserId ~= player.UserId then
			local name = type(d.Name) == "string" and d.Name or "?"
			Bus.Fire("Toast", { Text = string.format(L("%s dug up the CURSED TREASURE!", "%s выкопал(а) ПРОКЛЯТЫЙ КЛАД!"), name), Kind = "event", NoTranslate = true })
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- per-frame animation + budgets
	---------------------------------------------------------------------------------------------------------------
	local lightBudget = { High = 8, Medium = 5, Low = 3 }
	local lastLights = 0
	local function step(dt: number)
		local now = os.clock()
		local cam = camPos()
		-- lazy builds: one per frame, nearest first
		if #buildQueue > 0 then
			local bestI, bestD = nil, math.huge
			for i, v in ipairs(buildQueue) do
				if not v.Part.Parent or views[v.Part] ~= v then
					bestI, bestD = i, -1
					break
				end
				local d = (v.Part.CFrame.Position - cam).Magnitude
				if d < bestD then
					bestI, bestD = i, d
				end
			end
			if bestI then
				local v = buildQueue[bestI]
				if bestD < 0 then
					table.remove(buildQueue, bestI)
				elseif bestD <= BUILD_DIST then
					table.remove(buildQueue, bestI)
					build(v)
					updateHP(v)
				end
			end
		end
		local t = now
		for part, view in pairs(views) do
			local model = view.Model
			if model and model.Parent then
				local dist = (view.Base.Position - cam).Magnitude
				-- rise / dig depth / jolt -> model pivot
				local offset = 0
				if view.RiseAt then
					local a = math.clamp((now - view.RiseAt) / RISE_TIME, 0, 1)
					local e = 1 - (1 - a) ^ 3
					offset = view.Offset * (1 - e) + math.sin(a * math.pi) * .35
					if a >= 1 then
						view.RiseAt = nil
						view.Offset = 0
					end
				end
				offset -= view.Dug or 0
				local jolt = Vector3.zero
				if now < view.JoltUntil then
					jolt = view.Jolt
					if now >= view.HoldUntil then
						jolt = view.Jolt * math.clamp((view.JoltUntil - now) / .1, 0, 1)
					end
				end
				local shake = view.RiseAt and Vector3.new(math.sin(now * 37) * .08, 0, math.cos(now * 31) * .08) or Vector3.zero
				local pivot = view.Base * CFrame.new(jolt + shake + Vector3.new(0, offset, 0))
				if pivot ~= view.LastPivot then
					view.LastPivot = pivot
					model:PivotTo(pivot)
				end
				-- idle loop envelope: begin -> peak -> fade
				local ph = ((t + view.Phase) % view.Period) / view.Period
				local env = ph < .35 and (ph / .35) or ph < .55 and 1 or math.max(0, 1 - (ph - .55) / .45)
				env = env * env * (3 - 2 * env)
				local flash = now < view.FlashUntil and 1 or 0
				local animate = dist <= ANIM_DIST and (not low() or dist < 50)
				if animate then
					for _, a in ipairs(view.Anim) do
						local p = a.Part
						if p.Parent then
							if a.Kind == "Orbit" then
								local ang = t * a.Speed * .6
								local cf = CFrame.Angles(0, ang, 0) * a.Rel * CFrame.Angles(0, t * 1.4, 0)
								p.CFrame = pivot * (CFrame.new(0, math.sin(t * 1.7 + a.Phase) * a.Amp, 0) * cf)
							elseif a.Kind == "Bob" then
								p.CFrame = pivot * CFrame.new(0, math.sin(t * a.Speed + a.Phase) * a.Amp, 0) * a.Rel
							elseif a.Kind == "Lid" and a.Hinge then
								local h = CFrame.new(a.Hinge)
								local open = (math.sin(t * 1.6) * .5 + .5) * a.Amp + flash * .1
								p.CFrame = pivot * h * CFrame.Angles(-open, 0, 0) * h:Inverse() * a.Rel
							elseif a.Kind == "Flicker" then
								local n = math.noise(t * 6 + a.Phase, a.Phase) * .5 + .5
								p.Color = a.Color:Lerp(C(255, 255, 255), flash * .4):Lerp(C(0, 0, 0), (1 - n) * .35)
							elseif a.Kind == "Pulse" then
								p.Transparency = math.clamp(a.T + (1 - env) * .35 - flash * .2, 0, 1)
							end
						end
					end
					if flash > 0 or view.WasFlash then
						view.WasFlash = flash > 0
						for _, g in ipairs(view.Glows) do
							if g.Part.Parent then
								g.Part.Color = flash > 0 and g.Color:Lerp(C(255, 255, 255), .45) or g.Color
							end
						end
					end
				end
				-- emitters near the camera only, following the loop
				local on = dist <= (low() and 70 or 130)
				for _, e in ipairs(view.Emitters) do
					e.E.Rate = on and e.Base * (.35 + .65 * env + flash) or 0
				end
				view.Env, view.Dist = env, dist
			end
		end
		-- nearest-N lights (we own these: Enabled is ours to set), brightness follows the loop
		if now - lastLights > .25 then
			lastLights = now
			local list = {}
			for _, view in pairs(views) do
				if view.Model and view.Lights and #view.Lights > 0 then
					table.insert(list, view)
				end
			end
			table.sort(list, function(a, b)
				return (a.Dist or 1e9) < (b.Dist or 1e9)
			end)
			local n = lightBudget[Shared.Quality()] or 6
			for i, view in ipairs(list) do
				for _, l in ipairs(view.Lights) do
					l.L.Enabled = i <= n and (view.Dist or 1e9) < 160
				end
			end
		end
		for _, view in pairs(views) do
			if view.Lights and view.Env then
				local flash = os.clock() < view.FlashUntil and 1.2 or 0
				for _, l in ipairs(view.Lights) do
					if l.L.Enabled then
						l.L.Brightness = l.Base * (.7 + .45 * view.Env) + flash
					end
				end
			end
		end
		-- companion: animation + dirt puffs
		local c = companion
		if c then
			if not (c.Part and c.Part.Parent) or c.Part:GetAttribute("EndReason") then
				removeCompanion(true)
			else
				if c.Player then
					pcall(function()
						c.Player:Step(workspace:GetServerTimeNow())
					end)
				end
				if now >= c.NextPuff then
					c.NextPuff = now + .7 + math.random() * .4
					if not low() then
						FX.Debris(c.At + Vector3.new(0, .4, 0), C(90, 70, 56), Enum.Material.Ground, 2, 10, { Floor = c.At.Y, MaxSize = .35 })
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- wiring
	---------------------------------------------------------------------------------------------------------------
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		attach(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part)
		task.defer(attach, part)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		local view = views[part]
		if view and not view.Gone then
			-- streamed out / removed without a reason: quick fade
			detach(part)
		end
	end)
	-- attributes can arrive a frame after the tag: retry untracked targets
	task.spawn(function()
		while true do
			task.wait(1)
			for _, part in ipairs(CollectionService:GetTagged(TAG)) do
				if not views[part] and not part:GetAttribute("EndReason") then
					attach(part)
				end
			end
			for part, view in pairs(views) do
				if not part:IsDescendantOf(workspace) and not view.Gone then
					detach(part)
				end
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("Halloween SpotFX step failed: " .. tostring(err))
		end
	end)
	Bus.On("StrikeSwing", function(d)
		if type(d) == "table" and KINDS[d.Kind or ""] then
			digFeedback(d)
			if d.Remote and d.Miss then
				local view = d.Part and views[d.Part]
				if view and typeof(d.Position) == "Vector3" then
					FX.Popup(d.Position, L("MISS", "МИМО"), C(170, 220, 255), false)
				end
			end
		end
	end)
	Bus.On("StrikeResult", function(d)
		if type(d) ~= "table" or d.Kind ~= "DigSpot" then
			return
		end
		if type(d.Extra) == "table" and d.Extra.Miss then
			-- ghost soil: the companion's swing phased through
			local at = companion and companion.Model and companion.Model.Parent and companion.Model:GetPivot().Position
			local pos = at and at + Vector3.new(0, 3.2, 0) or (typeof(d.Position) == "Vector3" and d.Position)
			if pos then
				FX.Popup(pos, L("MISS", "МИМО"), C(170, 220, 255), true)
				FX.Smoke(pos - Vector3.new(0, 1, 0), C(210, 240, 255), 2.4, 1)
			end
			play("GhostWoo", pos or nil, { Volume = .45, Pitch = 1.3 })
		end
	end)
	Bus.On("StrikeBegin", function(d)
		if type(d) ~= "table" or d.Kind ~= "DigSpot" or not d.Part then
			return
		end
		local extra = type(d.Extra) == "table" and d.Extra or {}
		spawnCompanion(d.Part, extra.Companion)
		if extra.HeadStart then
			local view = views[d.Part]
			local pos = view and view.Base and view.Base.Position or d.Part.CFrame.Position
			FX.Popup(pos + Vector3.new(0, 4.5, 0), L("NIGHT FLIGHT! -25%", "НОЧНОЙ ПОЛЁТ! -25%"), C(190, 120, 255), true)
			FX.Burst(pos + Vector3.new(0, 2, 0), { Color = C(120, 60, 200), Count = 14, Speed = { 6, 12 }, Lifetime = { .5, 1 }, Size = { .4, .6, 0 } })
		end
	end)
	Bus.On("StrikeEnd", function(d)
		if type(d) == "table" and d.Kind == "DigSpot" then
			task.delay(d.Reason == "broke" and .6 or 0, function()
				removeCompanion(true)
			end)
		end
	end)
	Bus.On("Signal", function(s)
		if type(s) ~= "table" then
			return
		end
		if s.Kind == "SpotReward" then
			onReward(s.Data)
		elseif s.Kind == "Find" then
			onFind(s.Data)
		elseif s.Kind == "SpotAnnounce" then
			onAnnounce(s.Data)
		end
	end)
	-- handles for offline tests / Studio inspection
	SpotFX.Debug = { Views = views, Step = step, UpdateHP = updateHP, Shatter = shatter, Sink = sink, Dig = digFeedback, Reward = onReward,
		Announce = onAnnounce, Find = onFind, Companion = function()
			return companion
		end }
end

return SpotFX
