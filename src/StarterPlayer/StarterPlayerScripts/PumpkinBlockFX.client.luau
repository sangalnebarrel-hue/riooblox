-- PUMPKIN / CURSED PUMPKIN Lucky Block show (StarterPlayer.StarterPlayerScripts.PumpkinBlockFX), client only.
-- The pumpkin models (LuckyBlockVisuals -> Halloween.Models.Pumpkin) carry LuckyShowStyle, so the cube shows
-- (LuckyLifecycleFX / LuckyBlockFX) step aside and this script follows the same attribute contract:
--  * idle on the pad: the carved face warms up with the timer (candle flicker + inner light), READY = lit face and a
--    pulse ring on the owner's pad; the cursed pumpkin smoulders with purple fire.
--  * local OPEN (LocalPlayer LuckyBlockOpeningUid/At, set by the pad prompt and the LuckyBlockUI OPEN button):
--    appear (pop + ground ring) -> shake -> eyes light -> cracks + light rays -> hold until the server's Opened ->
--    BURST (flash, shockwaves, the lobes fly apart, embers/seeds, light) -> a ghost flies out when RewardGhost ->
--    the reward rises above the pad (3D + name). Publishes LuckyChargeUid/LuckyChargeAt (burst - Show.Timing.Charge)
--    so LuckyReel (dog rewards) and RewardScreens' pumpkin card pop exactly at the burst.
--  * spectators (within NEAR studs): a compressed show synced to OpenedAt (skipped when more than LATE_LIMIT late).
--  * Show.Low(): fewer chunks / particles / rays; Show.ReducedMotion(): no shake, pop or camera punch.
-- Works whether or not the event is running: pumpkin blocks stay in inventories after the event.
-- Every FX instance lives in workspace.DOGROTS_LuckyFX (never the district, never the server block model except the
-- one local idle light under the block's RootPart, which dies with the model).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Lucky = RS:WaitForChild("Lucky")
local Show = require(Lucky:WaitForChild("LuckyShow"))
local LuckyAudio = require(Lucky:WaitForChild("LuckyAudio"))
local Halloween = RS:WaitForChild("Halloween", 60)
if not Halloween then
	return
end
local FX = require(Halloween:WaitForChild("FX"))
local okAudio, HAudio = pcall(function()
	return require(Halloween:WaitForChild("Audio"))
end)
if not okAudio then
	HAudio = nil
end
local Pumpkin = require(Halloween:WaitForChild("Models"):WaitForChild("Pumpkin"))

local rgb = Color3.fromRGB
local CHARGE = 2.4 -- local charge length (seconds)
local SPECTATOR = 1.0 -- compressed charge for watchers / unpredicted opens
local HOLD_TIMEOUT = 6.5 -- no Opened this long after the start: the open failed
local PREDICT_WINDOW = 6
local LATE_LIMIT = 1.6
local NEAR = 120 -- camera distance that watches an opening
local AURA_NEAR = 95 -- idle aura distance
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local STYLE = {
	Pumpkin = {
		Glow = rgb(255, 196, 72), Light = rgb(255, 150, 50), Ember = rgb(255, 140, 40), Ember2 = rgb(255, 226, 130),
		Ring = rgb(255, 128, 24), Ring2 = rgb(150, 80, 230), Seed = rgb(250, 232, 170), Flash = rgb(255, 214, 140),
		Smoke = rgb(74, 52, 40), Chunk = rgb(240, 120, 26),
	},
	CursedPumpkin = {
		Glow = rgb(150, 255, 120), Light = rgb(170, 80, 255), Ember = rgb(176, 70, 255), Ember2 = rgb(150, 255, 120),
		Ring = rgb(150, 60, 255), Ring2 = rgb(120, 255, 110), Seed = rgb(60, 24, 84), Flash = rgb(206, 150, 255),
		Smoke = rgb(30, 10, 46), Chunk = rgb(70, 34, 100), Fire = rgb(176, 70, 255), Fire2 = rgb(230, 170, 255),
	},
}
local FACE = { PumpkinEye = true, PumpkinNose = true, PumpkinMouth = true }

--@pure-begin (no Instances: the show timeline)
local P = {}
-- phase edges as fractions of the charge length
P.Edges = { Appear = 0.14, Shake = 0.5, Eyes = 0.66, Cracks = 0.92 }
-- t = 0..1 of the charge: pop scale, rise (studs at block scale 1), shake amplitude, tilt (rad), face glow, crack reveal
function P.Charge(t: number)
	t = math.clamp(t, 0, 1)
	local E = P.Edges
	local pop = 1
	if t < E.Appear then
		local u = t / E.Appear
		-- back-out from .62 to 1
		local c = 1.70158
		local v = u - 1
		pop = 0.62 + 0.38 * (1 + (c + 1) * v * v * v + c * v * v)
	end
	local rise = 0.6 * math.min(1, t / E.Appear)
	local s = math.clamp((t - E.Appear) / (1 - E.Appear), 0, 1)
	local shake = t < E.Appear and 0 or 0.04 + 0.2 * s * s
	local glow = math.clamp((t - E.Shake) / (E.Eyes - E.Shake), 0, 1)
	local cracks = math.clamp((t - E.Eyes) / (E.Cracks - E.Eyes), 0, 1)
	return { Pop = pop, Rise = rise, Shake = shake, Tilt = 0.1 * s, Glow = glow, Cracks = cracks, Freq = 12 + 26 * s }
end
-- the burst moment: never before the charge ends, never before the server said Opened
function P.BurstAt(startAt: number, length: number, openedSeenAt: number?): number?
	if not openedSeenAt then
		return nil
	end
	return math.max(startAt + length, openedSeenAt)
end
-- a watcher sees BlockState=Opened: 'charge' (compressed, starting at OpenedAt), 'burst' (at once) or 'skip'
function P.LatePlan(t: number, openedAt: number?, length: number): (string, number?)
	openedAt = openedAt or t
	local age = t - openedAt
	if age < length then
		return "charge", openedAt
	end
	if age < LATE_LIMIT then
		return "burst", t
	end
	return "skip", nil
end
-- idle face warmth from the pad timer: 0 until half way, up to .6 before READY, 1 when ready
function P.Idle(progress: number, ready: boolean): number
	if ready then
		return 1
	end
	return math.clamp((progress - 0.5) / 0.5, 0, 1) * 0.6
end
--@pure-end

local function now(): number
	return workspace:GetServerTimeNow()
end
local function fxRoot(): Folder
	local root = workspace:FindFirstChild("DOGROTS_LuckyFX")
	if not root then
		root = Instance.new("Folder")
		root.Name = "DOGROTS_LuckyFX"
		root.Parent = workspace
	end
	return root :: Folder
end
local function cameraDistance(pos: Vector3): number
	local cam = workspace.CurrentCamera
	return cam and (cam.CFrame.Position - pos).Magnitude or math.huge
end
local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: any
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or fxRoot()
	return p
end
local function tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end
local function styleOf(m: Instance): string
	local s = m:GetAttribute("LuckyShowStyle")
	return (s == "CursedPumpkin") and "CursedPumpkin" or "Pumpkin"
end

-- sounds: Halloween cue recipes when they exist (WP10a), the Lucky Block recipes otherwise
local function sound(cue: string, where: Instance?, fallback: string?, ...)
	local args = { ... }
	if HAudio and HAudio.Has and HAudio.Has(cue) then
		pcall(HAudio.Play, cue, where)
		return
	end
	if fallback then
		pcall(LuckyAudio.Play, fallback, where, table.unpack(args))
	end
end

---------------------------------------------------------------------------------------------------------------------
-- idle aura on the pad
---------------------------------------------------------------------------------------------------------------------
local rows: { [Model]: any } = {}
local stages: { [string]: any } = {}
local onOpened: (Model) -> ()

local function faceParts(m: Instance): { any }
	local list = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and FACE[d.Name] then
			table.insert(list, { Part = d, Color = d.Color, Material = d.Material })
		end
	end
	return list
end

local function setFace(list: { any }, glowColor: Color3, amount: number)
	for _, f in ipairs(list) do
		local p = f.Part
		if p.Parent then
			if amount > 0.04 then
				p.Material = Enum.Material.Neon
				p.Color = f.Color:Lerp(glowColor, math.clamp(amount, 0, 1))
			else
				p.Material = f.Material
				p.Color = f.Color
			end
		end
	end
end

local function clearAura(row: any)
	if row.Light then
		row.Light:Destroy()
		row.Light = nil
	end
	if row.Fire then
		row.Fire:Destroy()
		row.Fire = nil
	end
	if row.Face then
		setFace(row.Face, Color3.new(), 0)
	end
	row.Lit = false
end

-- a ring of purple fire around a pumpkin: an invisible flat part whose cylinder emitter shape is the ring
local function fireRing(cf: CFrame, diameter: number, rate: number, scale: number, parent: Instance): (BasePart, ParticleEmitter)
	local ring = part({ Name = "PumpkinFireRing", Size = Vector3.new(diameter, 0.2, diameter), Transparency = 1, CFrame = cf, Parent = parent })
	local e = Instance.new("ParticleEmitter")
	e.Texture = FIRE
	e.Color = ColorSequence.new(STYLE.CursedPumpkin.Fire2, STYLE.CursedPumpkin.Fire)
	e.LightEmission = 0.9
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9 * scale), NumberSequenceKeypoint.new(0.45, 1.4 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.45, 0.85)
	e.Speed = NumberRange.new(1.5 * scale, 4 * scale)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Acceleration = Vector3.new(0, 5, 0)
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = rate
	e.Parent = ring
	return ring, e
end

local function register(m: Instance)
	if not m:IsA("Model") or rows[m] or m:GetAttribute("LuckyFXClone") or not m:GetAttribute("OwnedBlockUid") then
		return
	end
	if not m:GetAttribute("LuckyShowStyle") then
		return
	end
	local model = m :: Model
	local row = { Model = model, Style = styleOf(model), Conns = {}, Lit = false, Pulse = 0, Phase = math.random() * 10 }
	rows[model] = row
	table.insert(row.Conns, model:GetAttributeChangedSignal("BlockState"):Connect(function()
		if model:GetAttribute("BlockState") == "Opened" then
			onOpened(model)
		end
	end))
	-- the server rebuilt this block (Placed -> Ready) while it was charging: hide the new one too
	local uid = model:GetAttribute("OwnedBlockUid")
	local stage = stages[uid]
	if stage and stage.Alive and stage.Phase ~= "burst" and model:GetAttribute("BlockState") ~= "Opened" then
		stage.Adopt(model)
	end
	if model:GetAttribute("BlockState") == "Opened" then
		task.defer(onOpened, model)
	end
end

local function unregister(m: Model)
	local row = rows[m]
	if not row then
		return
	end
	rows[m] = nil
	for _, c in ipairs(row.Conns) do
		c:Disconnect()
	end
	if row.Light then
		row.Light:Destroy()
	end
	if row.Fire then
		row.Fire:Destroy()
	end
end

local function stepAura(row: any, t: number, dt: number)
	local m = row.Model
	if m:GetAttribute("LuckyOpening") or m:GetAttribute("BlockState") == "Opened" then
		if row.Lit then
			clearAura(row)
		end
		return
	end
	local root = m.PrimaryPart
	if not root then
		return
	end
	local pivot = root.CFrame
	if cameraDistance(pivot.Position) > AURA_NEAR then
		if row.Lit then
			clearAura(row)
		end
		return
	end
	local scale = m:GetScale()
	local state = m:GetAttribute("BlockState")
	local readyAt = tonumber(m:GetAttribute("ReadyAt"))
	local placedAt = tonumber(m:GetAttribute("PlacedAt"))
	local ready = state == "Ready" or (readyAt ~= nil and readyAt <= t)
	local progress = (readyAt and placedAt) and math.clamp((t - placedAt) / math.max(1, readyAt - placedAt), 0, 1) or 0
	local s = STYLE[row.Style]
	local warm = P.Idle(progress, ready)
	-- candle flicker: two incommensurate sines + noise
	local flicker = 0.78 + 0.12 * math.sin(t * 9.3 + row.Phase) + 0.1 * math.noise(t * 3.1, row.Phase)
	row.Face = row.Face or faceParts(m)
	setFace(row.Face, s.Glow, warm * flicker)
	if not row.Light then
		local l = Instance.new("PointLight")
		l.Name = "PumpkinIdleLight"
		l.Shadows = false
		l.Color = s.Light
		l.Range = 11 * scale / 0.68
		l.Brightness = 0
		l.Parent = root
		row.Light = l
	end
	row.Light.Brightness = (row.Style == "CursedPumpkin" and 0.35 or 0.15) + warm * flicker * 1.1
	if row.Style == "CursedPumpkin" and not row.Fire and not Show.Low() then
		local okBox, box, size = pcall(function()
			return m:GetBoundingBox()
		end)
		local ground = okBox and (box.Position.Y - size.Y / 2) or (pivot.Position.Y - 2.1 * scale / 0.68)
		row.Fire = fireRing(CFrame.new(pivot.Position.X, ground + 0.75 * scale / 0.68, pivot.Position.Z), 6.2 * scale / 0.68, 7, scale / 0.68, fxRoot())
	end
	row.Lit = true
	-- READY: a soft ground ring pulses on the owner's pad
	if ready and m:GetAttribute("OwnerUserId") == player.UserId then
		row.Pulse += dt
		if row.Pulse >= 1.8 then
			row.Pulse = 0
			local ok, box, size = pcall(function()
				return m:GetBoundingBox()
			end)
			local ground = ok and (box.Position - Vector3.new(0, size.Y / 2, 0)) or pivot.Position
			FX.Ring(ground, s.Ring, 4.2 * scale / 0.68, 1.2, { Thickness = 0.1, Transparency = 0.35 })
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- opening show
---------------------------------------------------------------------------------------------------------------------
local function publishCharge(uid: string, chargeAt: number)
	player:SetAttribute("LuckyChargeAt", chargeAt)
	player:SetAttribute("LuckyChargeUid", uid)
end
local function clearCharge(uid: string)
	if player:GetAttribute("LuckyChargeUid") == uid then
		player:SetAttribute("LuckyChargeUid", nil)
		player:SetAttribute("LuckyChargeAt", nil)
	end
end

-- while a local open charges, the player's own pad prompts are out of reach (a second E would open another block)
local holders = {}
local heldPrompts: { [ProximityPrompt]: number } = {}
local function holdPrompts(stage: any)
	if holders[stage] then
		return
	end
	holders[stage] = true
	local map = workspace:FindFirstChild("DOGROTS_District")
	local yards = map and map:FindFirstChild("04_PlayerYards")
	if not yards then
		return
	end
	for _, yard in ipairs(yards:GetChildren()) do
		for _, pad in ipairs(yard:GetChildren()) do
			if pad.Name:sub(1, 9) == "LuckyPad_" and pad:GetAttribute("LuckyPadOwner") == player.UserId then
				local prompt = pad:FindFirstChild("PlaceLuckyBlock")
				if prompt and prompt:IsA("ProximityPrompt") and heldPrompts[prompt] == nil then
					heldPrompts[prompt] = prompt.MaxActivationDistance
					prompt.MaxActivationDistance = 0
				end
			end
		end
	end
end
local function releasePrompts(stage: any)
	if not holders[stage] then
		return
	end
	holders[stage] = nil
	if next(holders) then
		return
	end
	for prompt, distance in pairs(heldPrompts) do
		if prompt.Parent then
			prompt.MaxActivationDistance = distance
		end
	end
	table.clear(heldPrompts)
end

local function readOpened(m: Model): any
	local kind = m:GetAttribute("RewardKind")
	if kind == nil and m:GetAttribute("RewardDogId") then
		kind = "Dog"
	end
	return {
		Kind = kind, Rank = tonumber(m:GetAttribute("RewardRank")) or 1, Name = m:GetAttribute("RewardName"),
		Ghost = m:GetAttribute("RewardGhost") == true, Id = m:GetAttribute("RewardId") or m:GetAttribute("RewardDogId"),
		ItemId = m:GetAttribute("RewardItemId"), Mutation = m:GetAttribute("RewardMutation"),
		OpenedAt = tonumber(m:GetAttribute("OpenedAt")) or now(),
	}
end

local active = {} -- stages animated by the heartbeat
local function hide(stage: any, d: Instance)
	if d:IsA("BasePart") or d:IsA("Decal") then
		(d :: any).LocalTransparencyModifier = 1
		stage.Hidden[d] = true
	elseif d:IsA("BillboardGui") then
		-- keep the timer billboard visible ("OPENING…")
	end
end
local function restoreOriginal(stage: any)
	for d in pairs(stage.Hidden) do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = 0
		end
	end
	table.clear(stage.Hidden)
	local m = stage.Original
	if m and m.Parent then
		m:SetAttribute("LuckyOpening", nil)
	end
end
local function finish(stage: any)
	if not stage.Alive then
		return
	end
	stage.Alive = false
	releasePrompts(stage)
	for _, c in ipairs(stage.Conns) do
		c:Disconnect()
	end
	table.clear(stage.Conns)
	local m = stage.Original
	if m and m.Parent and m:GetAttribute("BlockState") ~= "Opened" then
		restoreOriginal(stage)
	end
	if stage.Folder then
		stage.Folder:Destroy()
	end
	if stages[stage.Uid] == stage then
		stages[stage.Uid] = nil
	end
	active[stage] = nil
end

local function abort(stage: any)
	if not stage.Alive or stage.Phase == "burst" or stage.Opened then
		return
	end
	if stage.Local then
		clearCharge(stage.Uid)
	end
	local at = stage.Center
	restoreOriginal(stage)
	finish(stage)
	-- a fizzle: a puff of smoke and the real pumpkin comes back
	FX.Smoke(at, rgb(190, 190, 200), 3 * stage.Scale / 0.68, 1)
	sound("PumpkinShake", nil, "Shake", 0.2)
end

-- clone the pad block locally; remember every part relative to the pivot
local function makeClone(stage: any, m: Model)
	local ok, clone = pcall(function()
		return m:Clone()
	end)
	if not ok or not clone then
		return false
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LayerCollector") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sound") or d:IsA("ProximityPrompt")
			or d:IsA("LuaSourceContainer") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Highlight") or (d:IsA("Attachment") and d.Name == "PumpkinIdleFire") then
			d:Destroy()
		end
	end
	for _, name in ipairs({ "OwnedBlockUid", "OwnerUserId", "BlockState", "LuckyVisual", "LuckyOpening", "OpenMessage", "RewardDogId", "RewardKind" }) do
		clone:SetAttribute(name, nil)
	end
	clone:SetAttribute("LuckyFXClone", true) -- before parenting: no aura script dresses it
	clone.Name = "PumpkinOpeningClone"
	local pivot = stage.Pivot
	stage.Parts, stage.Face, stage.Cracks, stage.Lobes, stage.Base = {}, {}, {}, {}, {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.LocalTransparencyModifier = 0
			local entry = { Part = d, Rel = pivot:ToObjectSpace(d.CFrame), Size = d.Size, Color = d.Color, Material = d.Material, T = d.Transparency }
			table.insert(stage.Parts, entry)
			if FACE[d.Name] then
				table.insert(stage.Face, entry)
			elseif d.Name == "PumpkinRim" then
				stage.Rims = stage.Rims or {}
				table.insert(stage.Rims, entry)
			elseif d.Name == "PumpkinCrack" then
				table.insert(stage.Cracks, entry)
			elseif d.Name == "PumpkinLobe" or d.Name == "RootPart" then
				table.insert(stage.Lobes, entry)
			elseif d.Name == "PumpkinBase" or d.Name == "PumpkinBone" or d.Name == "PumpkinSkull" or d.Name == "PumpkinRune" or d.Name == "PumpkinMini" then
				table.insert(stage.Base, entry)
			end
		end
	end
	if #stage.Parts == 0 then
		clone:Destroy()
		return false
	end
	-- the hidden cracks reveal in a fixed order (front first)
	table.sort(stage.Cracks, function(a, b)
		return a.Rel.Position.Z < b.Rel.Position.Z
	end)
	for i, c in ipairs(stage.Cracks) do
		c.At = (i - 1) / math.max(1, #stage.Cracks)
	end
	clone.Parent = stage.Folder
	stage.Clone = clone
	return true
end

-- place the whole clone: base pivot * motion (rigid) — PivotTo is one engine call
local function placeClone(stage: any, motion: CFrame)
	if stage.Clone and stage.Clone.Parent then
		stage.Clone:PivotTo(stage.Pivot * motion)
	end
end

local function lightRays(stage: any)
	if stage.Rays or not stage.Clone then
		return
	end
	stage.Rays = {}
	local n = stage.Low and 3 or #stage.Cracks
	local s = stage.S
	for i = 1, math.min(n, #stage.Cracks) do
		local c = stage.Cracks[i].Part
		local dir = (c.CFrame.Position - stage.Clone:GetPivot().Position)
		dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
		if dir.Magnitude > 0.01 then
			dir = dir.Unit
			local len = 2.6 * stage.Scale / 0.68
			local ray = part({ Name = "PumpkinRay", Shape = Enum.PartType.Block, Color = s.Glow, Transparency = 0.45,
				Size = Vector3.new(0.12 * stage.Scale, 0.12 * stage.Scale, 0.1),
				CFrame = CFrame.lookAt(c.CFrame.Position, c.CFrame.Position + dir), Parent = stage.Clone })
			table.insert(stage.Rays, { Part = ray, Dir = dir, Len = len, Born = os.clock(), From = c })
		end
	end
end

local function stepRays(stage: any)
	if not stage.Rays then
		return
	end
	local clock = os.clock()
	for _, r in ipairs(stage.Rays) do
		if r.Part.Parent and r.From.Parent then
			local grow = math.clamp((clock - r.Born) / 0.35, 0, 1)
			local len = r.Len * grow * (0.85 + 0.15 * math.sin(clock * 30 + r.Len))
			local from = r.From.CFrame.Position
			r.Part.Size = Vector3.new(r.Part.Size.X, r.Part.Size.Y, math.max(0.1, len))
			r.Part.CFrame = CFrame.lookAt(from + r.Dir * len / 2, from + r.Dir * (len + 1))
		end
	end
end

-- seconds -> timeline value
local function chargeT(stage: any): number
	return (now() - stage.StartAt) / stage.Len
end

local function beat(stage: any, key: string, fn: () -> ())
	if not stage.Beats[key] then
		stage.Beats[key] = true
		fn()
	end
end

local function stepCharge(stage: any, t: number, dt: number)
	local c = P.Charge(t)
	local reduced = stage.Reduced
	local scale = stage.Scale
	-- pop (scale) during the appear phase: ScaleTo on the clone, then the rigid motion
	if t < P.Edges.Appear and not reduced then
		local target = stage.CloneScale * c.Pop
		if stage.Clone and math.abs(stage.Clone:GetScale() - target) > 1e-3 then
			stage.Clone:ScaleTo(target)
		end
	elseif stage.Clone and math.abs(stage.Clone:GetScale() - stage.CloneScale) > 1e-3 then
		stage.Clone:ScaleTo(stage.CloneScale)
	end
	local motion = CFrame.new(0, c.Rise * scale / 0.68, 0)
	if not reduced and c.Shake > 0 then
		local clock = os.clock()
		local a = c.Shake * scale / 0.68
		local f = c.Freq
		motion *= CFrame.new(math.noise(clock * f, 1.7) * a, math.abs(math.noise(clock * f, 4.1)) * a * 0.6, math.noise(clock * f, 9.3) * a)
			* CFrame.Angles(math.noise(clock * f * 0.7, 2.2) * c.Tilt, math.noise(clock * f * 0.5, 5.5) * c.Tilt * 0.5, math.noise(clock * f * 0.7, 7.7) * c.Tilt)
	end
	placeClone(stage, motion)
	-- the face lights up (eyes, nose, grin): dark holes -> glowing Neon
	local s = stage.S
	if c.Glow > 0 then
		local flicker = 0.85 + 0.15 * math.sin(os.clock() * 40)
		for _, f in ipairs(stage.Face) do
			f.Part.Material = Enum.Material.Neon
			f.Part.Color = f.Color:Lerp(s.Glow, math.clamp(c.Glow * flicker, 0, 1))
		end
		-- the cut flesh around the holes catches the glow
		for _, f in ipairs(stage.Rims or {}) do
			f.Part.Color = f.Color:Lerp(s.Glow, 0.45 * c.Glow)
		end
	end
	-- cracks spread
	if c.Cracks > 0 then
		for _, cr in ipairs(stage.Cracks) do
			local local01 = math.clamp((c.Cracks - cr.At * 0.8) / 0.25, 0, 1)
			cr.Part.Transparency = 1 - local01
		end
		lightRays(stage)
		stepRays(stage)
	end
	if stage.Light then
		stage.Light.Brightness = 0.4 + c.Glow * 2 + c.Cracks * 2.5
		stage.Light.Range = (8 + c.Cracks * 8) * scale / 0.68
	end
	if stage.Fire then
		stage.Fire.Rate = (stage.Low and 6 or 16) + 40 * c.Cracks
	end
	-- beats
	local E = P.Edges
	if t >= 0.02 then
		beat(stage, "pop", function()
			sound("BlockPop", stage.Anchor, "Whoosh", 1.2)
			FX.Ring(stage.Ground, s.Ring2, 4.6 * scale / 0.68, 0.7, { Thickness = 0.12 })
		end)
	end
	for i, at in ipairs({ 0.18, 0.27, 0.35, 0.42, 0.47 }) do
		if t >= at then
			beat(stage, "shake" .. i, function()
				sound("PumpkinShake", stage.Anchor, "Shake", 0.3 + i * 0.1)
			end)
		end
	end
	if t >= E.Shake then
		beat(stage, "eyes", function()
			pcall(LuckyAudio.Play, "Charge", stage.Anchor, stage.Rank, math.max(0.3, stage.StartAt + stage.Len - now()))
			FX.Light(stage.Center, s.Glow, 14 * scale / 0.68, 2.5, 0.6)
		end)
	end
	for i, at in ipairs({ 0.68, 0.77, 0.86 }) do
		if t >= at then
			beat(stage, "crack" .. i, function()
				sound("PumpkinCrack", stage.Anchor, "Crack")
				if not stage.Low then
					FX.Burst(stage.Center, { Color = s.Ember, Color2 = s.Ember2, Count = 8, Speed = { 4, 9 }, Lifetime = { 0.3, 0.6 }, Size = { 0.25, 0.4, 0 } })
				end
			end)
		end
	end
end

-- the reward rising above the pad: a 3D model (when there is one) and its name for everyone near
local function showReward(stage: any, info: any)
	local s = stage.S
	local scale = stage.Scale / 0.68
	local rank = math.clamp(math.floor(tonumber(info.Rank) or 1), 1, 6)
	local color = Show.World[rank] or s.Glow
	local holder = Instance.new("Folder")
	holder.Name = "PumpkinReward"
	holder.Parent = fxRoot()
	Debris:AddItem(holder, 4.2)
	local anchor = part({ Name = "RewardAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(stage.Center + Vector3.new(0, 1.2 * scale, 0)), Parent = holder })
	-- 3D art (not for dogs: the roulette / the dog itself is the reveal)
	local model = nil
	if info.Kind ~= "Dog" then
		local ok, built = pcall(function()
			local row = { Kind = info.Kind, Id = info.Id, Name = info.Name }
			if info.Kind == "Mutation" and info.ItemId then
				row.Item = { ItemId = info.ItemId, Mutation = info.Mutation or "NORMAL" }
			end
			return require(RS:WaitForChild("EconomyRewardVisuals")).Build(row)
		end)
		if ok and built then
			model = built
		end
	end
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.CastShadow = false
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
				d:Destroy()
			end
		end
		local okBox, _, size = pcall(function()
			return model:GetBoundingBox()
		end)
		local extent = okBox and math.max(size.X, size.Y, size.Z) or 2
		local fit = (2.4 * scale) / math.max(extent, 0.1)
		pcall(function()
			model:ScaleTo(model:GetScale() * fit)
		end)
		model.Parent = holder
		local start = os.clock()
		local base = stage.Center + Vector3.new(0, 0.6 * scale, 0)
		-- spin about the art's own centre, not its pivot
		local okCentre, centre = pcall(function()
			return (model:GetBoundingBox()).Position
		end)
		local localOffset = okCentre and model:GetPivot():PointToObjectSpace(centre) or Vector3.zero
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local age = os.clock() - start
			if age > 3.6 or not model.Parent then
				conn:Disconnect()
				if model.Parent then
					model:Destroy()
				end
				return
			end
			local up = math.min(1, age / 0.8)
			local ease = 1 - (1 - up) ^ 3
			local shrink = age > 3.0 and math.max(0.05, 1 - (age - 3.0) / 0.6) or 1
			model:PivotTo(CFrame.new(base + Vector3.new(0, ease * 2.6 * scale + math.sin(age * 3) * 0.15, 0)) * CFrame.Angles(0, age * 2.2, 0)
				* CFrame.new(-localOffset))
			if shrink < 1 and not model:GetAttribute("Shrinking") then
				model:SetAttribute("Shrinking", true)
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						tween(d, 0.55, { Transparency = 1 })
					end
				end
			end
		end)
		FX.Burst(base + Vector3.new(0, 2.6 * scale, 0), { Color = color, Color2 = Color3.new(1, 1, 1), Count = 16, Speed = { 3, 7 }, Lifetime = { 0.5, 1 }, Size = { 0.3, 0.5, 0 } })
	end
	-- name plate
	local gui = Instance.new("BillboardGui")
	gui.Name = "PumpkinRewardLabel"
	gui.Size = UDim2.fromOffset(300, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (model and 5.2 or 3.4) * scale, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = anchor
	gui.Parent = holder
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
	nameLabel.FontFace = FX.Font
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Text = string.upper(tostring(info.Name or info.Kind or "REWARD"))
	nameLabel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
	stroke.Parent = nameLabel
	local rarity = Instance.new("TextLabel")
	rarity.BackgroundTransparency = 1
	rarity.Position = UDim2.fromScale(0, 0.6)
	rarity.Size = UDim2.new(1, 0, 0.4, 0)
	rarity.FontFace = FX.Font
	rarity.TextScaled = true
	rarity.TextColor3 = color
	rarity.Text = (Show.Names.EN[rank] or "COMMON")
	rarity.Parent = gui
	local stroke2 = Instance.new("UIStroke")
	stroke2.Thickness = 2
	stroke2.Color = Color3.fromRGB(24, 10, 36)
	stroke2.Parent = rarity
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.3
	uiScale.Parent = gui
	tween(uiScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(gui, 3.2, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 1.2 * scale, 0) })
	task.delay(3.2, function()
		if nameLabel.Parent then
			tween(nameLabel, 0.5, { TextTransparency = 1 })
			tween(rarity, 0.5, { TextTransparency = 1 })
			tween(stroke, 0.5, { Transparency = 1 })
			tween(stroke2, 0.5, { Transparency = 1 })
		end
	end)
	if rank >= 5 then
		FX.Beam(stage.Ground, color, 22 * scale, 2.6)
	end
	sound("Sparkle", anchor, "Reveal", rank)
end

-- the ghost: rises out of the burst in a spiral, looks around, fades
local function releaseGhost(stage: any)
	local scale = stage.Scale / 0.68
	local okGhost, ghost = pcall(Pumpkin.Ghost, 2.6 * scale)
	if not okGhost or not ghost then
		return
	end
	local parts = {}
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			table.insert(parts, { Part = d, T = d.Transparency })
			d.Transparency = 1
		end
	end
	ghost.Parent = fxRoot()
	local cursed = stage.Style == "CursedPumpkin"
	if cursed then
		for _, p in ipairs(parts) do
			if p.Part.Name ~= "GhostEye" and p.Part.Name ~= "GhostMouth" then
				p.Part.Color = p.Part.Color:Lerp(rgb(190, 150, 255), 0.35)
			end
		end
	end
	local hems = {}
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "GhostHem" then
			table.insert(hems, { Part = d, Rel = ghost:GetPivot():ToObjectSpace(d.CFrame) })
		end
	end
	local start = os.clock()
	local origin = stage.Center
	local life = 2.7
	local spin = (stage.Seed % 2 == 0) and 1 or -1
	sound("GhostWoo", ghost.PrimaryPart, "Whoosh", 0.7)
	local lastPuff = 0
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local age = os.clock() - start
		if age >= life or not ghost.Parent then
			conn:Disconnect()
			if ghost.Parent then
				ghost:Destroy()
			end
			return
		end
		local u = age / life
		local a = spin * (age * 3.4)
		local r = (1.2 + u * 2.4) * scale
		local h = (1 + (u ^ 0.8) * 15) * scale
		local pos = origin + Vector3.new(math.cos(a) * r, h + math.sin(age * 6) * 0.25 * scale, math.sin(a) * r)
		local ahead = origin + Vector3.new(math.cos(a + spin * 0.4) * r, h + 0.6 * scale, math.sin(a + spin * 0.4) * r)
		local cf = CFrame.lookAt(pos, ahead) * CFrame.Angles(0, 0, math.sin(age * 5) * 0.2)
		ghost:PivotTo(cf)
		for i, hm in ipairs(hems) do
			hm.Part.CFrame = cf * hm.Rel * CFrame.new(0, math.sin(age * 9 + i) * 0.08 * scale, 0)
		end
		local alpha = math.clamp(age / 0.25, 0, 1) * math.clamp((life - age) / 0.8, 0, 1)
		for _, p in ipairs(parts) do
			p.Part.Transparency = 1 - (1 - p.T) * alpha
		end
		if not stage.Low and age - lastPuff > 0.22 then
			lastPuff = age
			FX.Burst(pos - Vector3.new(0, 0.8 * scale, 0), { Texture = SMOKE, Color = cursed and rgb(200, 170, 255) or rgb(230, 240, 255), Count = 2,
				Speed = { 0.5, 1.5 }, Lifetime = { 0.5, 0.9 }, Size = { 0.6 * scale, 1 * scale, 1.4 * scale }, Transparency = { 0.6, 1 }, LightEmission = 0.3, Drag = 2,
				Acceleration = Vector3.new(0, 1, 0) })
		end
	end)
end

local function burst(stage: any)
	if stage.Phase == "burst" then
		return
	end
	stage.Phase = "burst"
	stage.BurstClock = os.clock()
	local info = stage.Opened or {}
	local s = stage.S
	local scale = stage.Scale / 0.68
	local center = stage.Clone and stage.Clone:GetPivot().Position or stage.Center
	local cursed = stage.Style == "CursedPumpkin"
	if stage.Local then
		-- the reward card / roulette may already wait for this moment: keep the published time honest
		clearCharge(stage.Uid)
	end
	-- flash ball
	local flash = part({ Name = "PumpkinFlash", Shape = Enum.PartType.Ball, Color = s.Flash, Transparency = 0.1, Size = Vector3.one * 1.5 * scale,
		CFrame = CFrame.new(center), Parent = stage.Folder })
	tween(flash, 0.38, { Size = Vector3.one * 10 * scale, Transparency = 1 }, Enum.EasingStyle.Quart)
	FX.Shockwave(stage.Ground, s.Ring, 13 * scale, 0.7)
	task.delay(0.08, function()
		FX.Ring(stage.Ground, s.Ring2, 9 * scale, 0.6, { Thickness = 0.16 })
	end)
	if cursed and not stage.Low then
		task.delay(0.16, function()
			FX.Ring(stage.Ground, rgb(20, 6, 34), 16 * scale, 0.9, { Thickness = 0.3, Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
		end)
	end
	FX.Light(center, s.Light, 24 * scale, 4, 1.2)
	-- particles: embers + seeds (pumpkin) / purple fire + green sparks + black smoke (cursed)
	FX.Burst(center, { Color = s.Ember, Color2 = s.Ember2, Count = cursed and 50 or 60, Speed = { 10 * scale, 24 * scale }, Lifetime = { 0.6, 1.3 },
		Size = { 0.5 * scale, 0.9 * scale, 0 }, Acceleration = Vector3.new(0, -10, 0) })
	if cursed then
		FX.Burst(center, { Texture = FIRE, Color = s.Fire, Color2 = s.Fire2, Count = 26, Speed = { 6 * scale, 14 * scale }, Lifetime = { 0.5, 1 },
			Size = { 1.4 * scale, 2.2 * scale, 0 }, LightEmission = 0.9, Acceleration = Vector3.new(0, 8, 0) })
		FX.Smoke(center, s.Smoke, 5 * scale, 1.8)
	else
		FX.Burst(center, { Color = s.Seed, Count = 30, Speed = { 8 * scale, 18 * scale }, Lifetime = { 0.8, 1.4 }, Size = { 0.25 * scale, 0.3 * scale, 0.2 * scale },
			Texture = SPARK, LightEmission = 0.2, Acceleration = Vector3.new(0, -40, 0), Drag = 1 })
		FX.Smoke(center, s.Smoke, 4 * scale, 1.4)
	end
	sound("PumpkinBurst", stage.Anchor, nil)
	pcall(LuckyAudio.Play, "Burst", stage.Anchor, stage.Rank)
	if stage.Local and not stage.Reduced then
		pcall(function()
			FX.Flash(s.Flash, 0.3, 0.35)
			if Show.CameraFree() then
				FX.Shake(0.55, 0.5)
				FX.Punch(0.9)
			end
		end)
	end
	-- the pumpkin flies apart: lobes, face and stem become tumbling chunks; the pedestal fades away
	local chunks = {}
	local rng = Random.new(stage.Seed)
	local maxChunks = stage.Low and 14 or 60
	for _, e in ipairs(stage.Parts) do
		local p = e.Part
		if p.Parent then
			local isBase = table.find(stage.Base, e) ~= nil
			if isBase then
				tween(p, 0.9, { Transparency = 1 })
			elseif p.Name == "PumpkinCrack" or p.Name == "PumpkinRay" then
				p:Destroy()
			elseif #chunks < maxChunks and (p.Name == "PumpkinLobe" or FACE[p.Name] or p.Name == "PumpkinStem" or p.Name == "PumpkinLeaf" or p.Name == "PumpkinFlame" or p.Name == "PumpkinThorn" or p.Name == "PumpkinRim") then
				local dir = p.CFrame.Position - center
				dir = Vector3.new(dir.X, math.max(dir.Y, 0) + 0.6, dir.Z)
				dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, 1, 0)
				table.insert(chunks, { Part = p, V = dir * rng:NextNumber(14, 26) * scale + Vector3.new(0, rng:NextNumber(4, 10) * scale, 0),
					R = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)), Base = p.Transparency })
				if FACE[p.Name] then
					p.Material = Enum.Material.Neon
					p.Color = s.Glow
				end
			else
				p:Destroy()
			end
		end
	end
	if stage.Rays then
		for _, r in ipairs(stage.Rays) do
			if r.Part.Parent then
				r.Part:Destroy()
			end
		end
		stage.Rays = nil
	end
	if stage.Fire then
		stage.Fire.Rate = 0
	end
	local floorY = stage.Ground.Y
	local start = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local age = os.clock() - start
		if age > 1.5 or not stage.Folder or not stage.Folder.Parent then
			conn:Disconnect()
			return
		end
		for _, ch in ipairs(chunks) do
			local p = ch.Part
			if p.Parent then
				ch.V += Vector3.new(0, -70 * dt, 0)
				local pos = p.CFrame.Position + ch.V * dt
				if pos.Y < floorY + p.Size.Y * 0.3 then
					pos = Vector3.new(pos.X, floorY + p.Size.Y * 0.3, pos.Z)
					ch.V = Vector3.new(ch.V.X * 0.45, math.abs(ch.V.Y) * 0.3, ch.V.Z * 0.45)
				end
				p.CFrame = CFrame.new(pos) * p.CFrame.Rotation * CFrame.Angles(ch.R.X * dt, ch.R.Y * dt, ch.R.Z * dt)
				local fade = math.clamp((age - 0.7) / 0.7, 0, 1)
				p.Transparency = ch.Base + (1 - ch.Base) * fade
			end
		end
	end)
	if info.Ghost and not stage.NoGhost then
		task.delay(0.12, function()
			releaseGhost(stage)
		end)
	end
	task.delay(info.Ghost and 0.45 or 0.25, function()
		showReward(stage, info)
	end)
	task.delay(1.7, function()
		finish(stage)
	end)
end

local function animate(stage: any)
	active[stage] = true
end

local function startStage(m: Model, uid: string, isLocal: boolean, startAt: number, length: number): any
	local pivot = m:GetPivot()
	if cameraDistance(pivot.Position) > NEAR then
		return nil
	end
	local scale = m:GetScale()
	local okBox, boxCf, boxSize = pcall(function()
		return m:GetBoundingBox()
	end)
	local bottom = okBox and boxCf.Position.Y - boxSize.Y / 2 or pivot.Position.Y - (3.1 * scale)
	local style = styleOf(m)
	local stage: any = {
		Uid = uid, Local = isLocal, StartAt = startAt, Len = length, Phase = "charge", Alive = true, Conns = {}, Hidden = {}, Beats = {},
		Rank = Show.Rank(m:GetAttribute("LuckyBlockTier") or m:GetAttribute("LuckyRank") or 4), Low = Show.Low(), Reduced = Show.ReducedMotion(),
		Pivot = pivot, Center = pivot.Position, Ground = Vector3.new(pivot.Position.X, bottom, pivot.Position.Z), Scale = scale > 0 and scale or 0.68,
		Style = style, S = STYLE[style], Seed = 7,
	}
	for i = 1, #uid do
		stage.Seed = (stage.Seed * 31 + string.byte(uid, i)) % 2147483646
	end
	stage.Folder = Instance.new("Folder")
	stage.Folder.Name = "PumpkinOpening"
	stage.Folder.Parent = fxRoot()
	function stage.Adopt(model: Model)
		if stage.Original == model then
			return
		end
		stage.Original = model
		model:SetAttribute("LuckyOpening", true)
		for _, d in ipairs(model:GetDescendants()) do
			hide(stage, d)
		end
		table.insert(stage.Conns, model.DescendantAdded:Connect(function(d)
			hide(stage, d)
		end))
		table.insert(stage.Conns, model:GetAttributeChangedSignal("OpenMessage"):Connect(function()
			if stage.Original == model then
				abort(stage)
			end
		end))
	end
	stages[uid] = stage
	local built, err = pcall(function()
		assert(makeClone(stage, m), "no clone")
		stage.CloneScale = stage.Clone:GetScale()
		stage.Adopt(m)
		stage.Anchor = part({ Name = "PumpkinCore", Size = Vector3.one * 0.2, Transparency = 1, CFrame = pivot, Parent = stage.Folder })
		local l = Instance.new("PointLight")
		l.Color = stage.S.Light
		l.Range = 8
		l.Brightness = 0.4
		l.Shadows = false
		l.Parent = stage.Anchor
		stage.Light = l
		if style == "CursedPumpkin" and not stage.Low then
			local k = stage.Scale / 0.68
			local _, e = fireRing(CFrame.new(stage.Ground + Vector3.new(0, 0.75 * k, 0)), 6.2 * k, 8, k * 1.25, stage.Folder)
			stage.Fire = e
		end
	end)
	if not built then
		warn("PumpkinBlockFX opening: " .. tostring(err))
		restoreOriginal(stage)
		finish(stage)
		return nil
	end
	if isLocal then
		-- LuckyReel / the pumpkin card pop at LuckyChargeAt + Show.Timing.Charge = our burst
		publishCharge(uid, startAt + length - Show.Timing.Charge)
		holdPrompts(stage)
	end
	animate(stage)
	return stage
end

local function stepStage(stage: any, dt: number)
	if not stage.Alive then
		active[stage] = nil
		return
	end
	if stage.Phase ~= "charge" and stage.Phase ~= "hold" then
		return
	end
	local t = chargeT(stage)
	if t >= 1 then
		if stage.Opened then
			burst(stage)
			return
		end
		stage.Phase = "hold"
		if now() - stage.StartAt > HOLD_TIMEOUT then
			abort(stage)
			return
		end
	end
	local ok, err = pcall(stepCharge, stage, math.min(t, 1), dt)
	if not ok then
		warn("PumpkinBlockFX charge: " .. tostring(err))
		if stage.Local then
			clearCharge(stage.Uid)
		end
		restoreOriginal(stage)
		finish(stage)
	end
end

local function modelForUid(uid: string): Model?
	for m in pairs(rows) do
		if m.Parent and m:GetAttribute("OwnedBlockUid") == uid then
			return m
		end
	end
	return nil
end

-- local prediction: the player just pressed OPEN on one of their own ready pumpkins
local function onPrediction()
	local uid = player:GetAttribute("LuckyBlockOpeningUid")
	if type(uid) ~= "string" or uid == "" then
		-- cleared: by GUIIntegration on success (OpenedBlock) or by LuckyBlockUI on failure
		for _, stage in pairs(stages) do
			if stage.Local and not stage.Opened then
				task.delay(1.2, function()
					if stages[stage.Uid] == stage and not stage.Opened and player:GetAttribute("LuckyBlockOpeningUid") ~= stage.Uid then
						abort(stage)
					end
				end)
			end
		end
		return
	end
	local at = tonumber(player:GetAttribute("LuckyBlockOpeningAt"))
	local t = now()
	if at and t - at > PREDICT_WINDOW then
		return
	end
	if stages[uid] then
		return
	end
	local m = modelForUid(uid)
	if not m or m:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	local state = m:GetAttribute("BlockState")
	if state ~= "Ready" and state ~= "Placed" then
		return
	end
	startStage(m, uid, true, t, CHARGE)
end

-- BlockState became Opened: feed a running charge, or play the short version
onOpened = function(m: Model)
	local uid = m:GetAttribute("OwnedBlockUid")
	if type(uid) ~= "string" then
		return
	end
	local info = readOpened(m)
	local stage = stages[uid]
	if stage and stage.Alive then
		if not stage.Opened then
			stage.Opened = info
		else
			-- the payload came first (RewardPresentation); the model adds the ghost flag / item for the art
			stage.Opened.Ghost = stage.Opened.Ghost or info.Ghost
			stage.Opened.ItemId = stage.Opened.ItemId or info.ItemId
			stage.Opened.Mutation = stage.Opened.Mutation or info.Mutation
		end
		return
	end
	local mine = m:GetAttribute("OwnerUserId") == player.UserId
	local t = now()
	local plan, startAt = P.LatePlan(t, info.OpenedAt, SPECTATOR)
	if plan == "skip" then
		return
	end
	if mine then
		startAt = t -- the opener's clock: the burst lands SPECTATOR from now
	end
	local length = plan == "burst" and 0.05 or SPECTATOR
	local s = startStage(m, uid, mine, startAt or t, length)
	if s then
		s.Opened = info
	end
end

---------------------------------------------------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------------------------------------------------
local function hookFolder(folder: Instance)
	for _, m in ipairs(folder:GetChildren()) do
		register(m)
	end
	folder.ChildAdded:Connect(register)
	folder.ChildRemoved:Connect(function(m)
		if m:IsA("Model") then
			unregister(m)
		end
	end)
end
local blocks = workspace:FindFirstChild("OwnedLuckyBlocks")
if blocks then
	hookFolder(blocks)
else
	local conn
	conn = workspace.ChildAdded:Connect(function(c)
		if c.Name == "OwnedLuckyBlocks" and c:IsA("Folder") then
			conn:Disconnect()
			hookFolder(c)
		end
	end)
end

-- the pad prompt (LuckyLifecycleFX sets the same attributes; setting them twice is harmless)
PPS.PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= "PlaceLuckyBlock" or prompt.ActionText ~= "OPEN BLOCK" then
		return
	end
	local pad = prompt.Parent
	local uid = pad and pad:GetAttribute("LuckyBlockUid")
	if type(uid) == "string" and uid ~= "" and player:GetAttribute("LuckyBlockOpeningUid") ~= uid then
		player:SetAttribute("LuckyBlockOpeningAt", workspace:GetServerTimeNow())
		player:SetAttribute("LuckyBlockOpeningUid", uid)
	end
end)
player:GetAttributeChangedSignal("LuckyBlockOpeningUid"):Connect(onPrediction)
player:GetAttributeChangedSignal("LuckyBlockOpeningAt"):Connect(onPrediction)

-- the server's answer: the reward payload confirms the open even before the model's attributes replicate; a plain
-- Message while a local charge waits means the open failed
task.spawn(function()
	local remote = RS:WaitForChild("RewardPresentation", 30)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	remote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		local opened = data.OpenedBlock
		if type(opened) == "table" and type(opened.BlockUid) == "string" then
			local stage = stages[opened.BlockUid]
			if stage and stage.Alive and not stage.Opened then
				local item = type(opened.Item) == "table" and opened.Item or nil
				stage.Opened = {
					Kind = opened.Kind, Rank = tonumber(opened.Rank) or (type(opened.Dog) == "table" and 4) or 1,
					Name = opened.Name or (type(opened.Dog) == "table" and opened.Dog.DisplayName) or nil, Ghost = opened.Ghost == true,
					Id = opened.Id, ItemId = item and item.ItemId, Mutation = item and item.Mutation, OpenedAt = now(),
				}
			end
			return
		end
		if type(data.Message) == "string" and not data.Credits and not data.Message:find("reward: %+") then
			for _, stage in pairs(stages) do
				if stage.Local and not stage.Opened then
					abort(stage)
				end
			end
		end
	end)
end)

local auraClock = 0
RunService.Heartbeat:Connect(function(dt)
	for stage in pairs(active) do
		stepStage(stage, dt)
	end
	auraClock += dt
	if auraClock < 0.08 then
		return
	end
	local step = auraClock
	auraClock = 0
	local t = now()
	for m, row in pairs(rows) do
		if not m.Parent then
			unregister(m)
		else
			local ok, err = pcall(stepAura, row, t, step)
			if not ok then
				warn("PumpkinBlockFX aura: " .. tostring(err))
				unregister(m)
			end
		end
	end
end)
