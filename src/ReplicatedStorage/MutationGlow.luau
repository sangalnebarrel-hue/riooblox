-- MUTATION GLOW: how a mutated dog looks, everywhere (kennels, the dog line, yard displays, the
-- nuclear tower cinematic). Client only. Every variant has its own unmistakable look:
--   Shiny      icy white-blue rim, twinkling star glints, a soft white light, slow shimmer
--   Golden     strong gold fill, falling gold glitter and rising sparkles, a warm light, a shine sweep
--   Corrupted  crimson body under a black-red rim, dark smoke and embers, an unstable flicker
--   Glitched   cyan / magenta / lime colour jumps, pixel bursts, the outline drops out at random
--   Void       the dog darkens to deep violet, violet motes are pulled in, a dark aura, a cold light
-- A kennel dog also shows its mutation while it digs: a "✦ GOLDEN ✦" tag over its name, a spray of
-- variant-coloured sparks at its nose while WorkState is DIGGING, and a burst + flash on every find
-- (WorkSequence). A kennel dog that digs in the MINE (MinePlacement ~= "Surface") also gets a beacon
-- over its pit's winch on the surface ("✦ GOLDEN ✦ / DIGGING BELOW"), so the yard shows it too.
-- Budgets (this module owns them: its folders carry SelfManagedFX, so WorldDetailQuality leaves them
-- alone): the engine draws 31 Highlights at once and other systems use some, so only the
-- MaxHighlights nearest mutated dogs get one; MaxLights lights; MaxEmitting dogs run particles; on
-- Low FX (or touch by default) everything is smaller. Dogs in the mine are not shown to a camera on
-- the surface and the other way round. Your own dogs come first. During the BLACKOUT world event the
-- glow lights and the pit beacon lights go dark, as WorldDetailQuality does with the district's lights
-- (outlines, particles and tags stay; the cinematic's Strong glow is never managed by it).
-- Streaming-safe: a tracked dog whose parts arrive later (or stream out and back) is re-fitted.
--   Glow.Apply(model, variant, opts?) -> handle   one model now. opts.Strong: the cinematic, bigger;
--        opts.Highlight=false: no highlight and no light until the budget gives them; opts.Fit="Rig":
--        fit the volume to the DogRig VisualSize/GroundLocal; opts.Tag: the mutation tag; opts.Dig: the
--        dig spray
--   Glow.Remove(model)
--   Glow.Track(model)    follow the model's Variant (EconomyVisuals); untracks on destroy (Destroying,
--        AncestryChanged, and the budget pass drops any tracked model left without a parent)
--   Glow.IsTracked(model)
--   Glow.Refresh(model)  re-apply a tracked model now (Track calls it when parts stream in or out)
--   Glow.Step(handle, t) one animation step (Start runs it for every handle)
--   Glow.Blackout()      is the BLACKOUT world event active (WorldDetailQuality's rule)
--   Glow.Start()         the budget / animation loop (once)
--   Glow.Colors[variant] the main colour of a variant;  Glow.Styles[variant] its full look
--   Glow.Name(variant)   "GOLDEN" / "ЗОЛОТОЙ" (Glow.Names: both languages)
local Players = game:GetService("Players")
local Run = game:GetService("RunService")

local Glow = {}
Glow.MaxHighlights = 14 -- + SecretAura 6 + hover / lucky / reward / world-event singles stay under 31
Glow.MaxLights = 10 -- 4 on Low FX
Glow.MaxEmitting = 24 -- dogs whose particles run, nearest first (10 on Low FX)
Glow.OwnBonus = 40 -- your own dogs rank as if this many studs nearer
Glow.FarDistance = 260
Glow.LightDistance = 140
Glow.BeaconDistance = 220
Glow.UndergroundY = -30 -- MineLayout.ShellTop: a camera below it is in the mine
Glow.Folder = "MutationGlow"
Glow.SelfManaged = "SelfManagedFX" -- WorldDetailQuality skips emitters / lights under such a folder
Glow.BeaconFolder = "DOGROTS_MutationBeacons" -- in Workspace, outside DOGROTS_District

local C = Color3.fromRGB
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Self-localised text (the labels carry NoTranslate): { English, Russian }. Same words as the lab
-- and the kennel window (Localization.Kennel).
Glow.Names = {
	Shiny = { "SHINY", "БЛЕСТЯЩИЙ" },
	Golden = { "GOLDEN", "ЗОЛОТОЙ" },
	Corrupted = { "CORRUPTED", "ИСКАЖЁННЫЙ" },
	Glitched = { "GLITCHED", "ГЛИТЧЕВЫЙ" },
	Void = { "VOID", "ПУСТОТНЫЙ" },
}
Glow.Text = {
	DiggingBelow = { "DIGGING BELOW", "КОПАЕТ ВНИЗУ" },
}

-- Look of every variant: highlight fill / outline, the light, the emitters (relative to the dog's
-- root box), the animation style of the highlight and the dig spray (Dig: also the pit beacon).
Glow.Styles = {
	Shiny = {
		Color = C(214, 244, 255), Fill = C(235, 250, 255), Outline = C(120, 225, 255),
		FillT = 0.68, OutlineT = 0, Light = { Color = C(200, 240, 255), Brightness = 1.4, Range = 9 },
		Pulse = { Speed = 1.6, Amount = 0.14 },
		Emitters = {
			{ Name = "Twinkle", Texture = SPARKLE, Rate = 9, Lifetime = { 0.5, 1.0 }, Speed = { 0.2, 0.8 }, Size = { 0.0, 0.75, 0.0 },
				Colors = { C(255, 255, 255), C(150, 230, 255) }, Light = 1, Rot = 160 },
			{ Name = "Shimmer", Texture = SPARKLE, Rate = 3, Lifetime = { 1.2, 1.8 }, Speed = { 1.0, 1.6 }, Size = { 0.3, 0.12 },
				Colors = { C(180, 240, 255), C(255, 255, 255) }, Light = 1, Up = 1.5, Transp = { 0.2, 1 } },
		},
		Dig = { Texture = SPARKLE, Colors = { C(255, 255, 255), C(150, 230, 255) }, Size = { 0.35, 0 } },
	},
	Golden = {
		Color = C(255, 199, 54), Fill = C(255, 196, 40), Outline = C(255, 236, 140),
		FillT = 0.5, OutlineT = 0, Light = { Color = C(255, 196, 70), Brightness = 2, Range = 11 },
		Pulse = { Speed = 2.2, Amount = 0.18, Sweep = true },
		Emitters = {
			{ Name = "Glitter", Texture = SPARKLE, Rate = 14, Lifetime = { 0.8, 1.4 }, Speed = { 0.3, 0.9 }, Size = { 0.35, 0.1 },
				Colors = { C(255, 240, 150), C(255, 180, 30) }, Light = 1, Up = -6, Rot = 90 },
			{ Name = "Rise", Texture = SPARKLE, Rate = 6, Lifetime = { 1.0, 1.6 }, Speed = { 2.0, 3.2 }, Size = { 0.5, 0.0 },
				Colors = { C(255, 230, 120), C(255, 160, 20) }, Light = 1, Up = 2 },
		},
		Dig = { Texture = SPARKLE, Colors = { C(255, 236, 140), C(255, 170, 20) }, Size = { 0.4, 0.05 } },
	},
	Corrupted = {
		Color = C(235, 40, 60), Fill = C(150, 0, 22), Outline = C(255, 40, 60),
		FillT = 0.42, OutlineT = 0, Light = { Color = C(255, 30, 50), Brightness = 1.8, Range = 10 },
		Pulse = { Speed = 3.1, Amount = 0.2, Flicker = 0.12 },
		Emitters = {
			{ Name = "DarkSmoke", Texture = SMOKE, Rate = 7, Lifetime = { 1.0, 1.8 }, Speed = { 1.0, 2.2 }, Size = { 0.9, 2.4 },
				Colors = { C(40, 0, 6), C(10, 0, 0) }, Light = 0, Up = 1.5, Transp = { 0.35, 1 }, Influence = 1 },
			{ Name = "Embers", Texture = FIRE, Rate = 10, Lifetime = { 0.5, 1.0 }, Speed = { 1.5, 3.5 }, Size = { 0.28, 0.0 },
				Colors = { C(255, 70, 50), C(140, 0, 20) }, Light = 1, Up = 3, Rot = 200 },
		},
		Dig = { Texture = FIRE, Colors = { C(255, 60, 60), C(90, 0, 10) }, Size = { 0.35, 0 } },
	},
	Glitched = {
		Color = C(40, 239, 213), Fill = C(40, 239, 213), Outline = C(255, 60, 220),
		FillT = 0.5, OutlineT = 0, Light = { Color = C(60, 240, 220), Brightness = 1.6, Range = 10 },
		Pulse = { Speed = 1, Amount = 0, Glitch = { C(40, 239, 213), C(255, 60, 220), C(170, 255, 60), C(255, 255, 255) } },
		Emitters = {
			{ Name = "Pixels", Texture = "", Rate = 16, Lifetime = { 0.08, 0.25 }, Speed = { 0, 0.4 }, Size = { 0.32, 0.32 },
				Colors = { C(40, 239, 213), C(255, 60, 220) }, Light = 1, Rot = 0, Square = true },
			{ Name = "Static", Texture = SPARKLE, Rate = 6, Lifetime = { 0.1, 0.3 }, Speed = { 4, 8 }, Size = { 0.2, 0.0 },
				Colors = { C(255, 255, 255), C(170, 255, 60) }, Light = 1 },
		},
		Dig = { Texture = "", Colors = { C(40, 239, 213), C(255, 60, 220) }, Size = { 0.28, 0.28 }, Square = true },
	},
	Void = {
		Color = C(140, 60, 255), Fill = C(28, 0, 54), Outline = C(178, 100, 255),
		FillT = 0.28, OutlineT = 0, Light = { Color = C(150, 70, 255), Brightness = 1.6, Range = 12 },
		Pulse = { Speed = 1.1, Amount = 0.12 },
		Emitters = {
			{ Name = "Pull", Texture = SPARKLE, Rate = 14, Lifetime = { 0.7, 1.1 }, Speed = { -3.2, -2.2 }, Size = { 0.1, 0.45 },
				Colors = { C(200, 140, 255), C(90, 20, 200) }, Light = 1, Sphere = 2.6, Rot = 220 },
			{ Name = "Aura", Texture = SMOKE, Rate = 5, Lifetime = { 1.4, 2.2 }, Speed = { 0.3, 0.8 }, Size = { 1.6, 3.2 },
				Colors = { C(70, 0, 140), C(10, 0, 30) }, Light = 0.4, Up = 0.8, Transp = { 0.5, 1 } },
		},
		Dig = { Texture = SPARKLE, Colors = { C(200, 140, 255), C(60, 0, 140) }, Size = { 0.35, 0.05 } },
	},
}
Glow.Colors = {}
for name, s in Glow.Styles do Glow.Colors[name] = s.Color end
Glow.Colors.Normal = C(120, 255, 140)

local INK = C(15, 10, 25) -- text outline of the tags
local CAPTION = C(255, 226, 170) -- the winch sign's caption colour

local handles = setmetatable({}, { __mode = "k" }) -- model -> handle
local tracked = {} -- model -> entry {Conns, Pending, Schedule, LastSeq, BeaconTries}
local beacons = {} -- kennel model -> beacon {Part, Emitter, Light, Gui, Name, Caption, Variant}

------------------------------------------------------------------------------------------------
-- language
------------------------------------------------------------------------------------------------
-- The AutoTranslateUI rule: Studio follows the Roblox locale, a live client the player's LocaleId.
function Glow.Lang(): string
	local locale = ""
	pcall(function()
		local service = game:GetService("LocalizationService")
		local player = Players.LocalPlayer
		if Run:IsStudio() or not player then
			locale = service.RobloxLocaleId
		else
			locale = player.LocaleId or service.RobloxLocaleId
		end
	end)
	return string.lower(string.sub(tostring(locale or ""), 1, 2)) == "ru" and "ru" or "en"
end
local function pick(pair: { string }, lang: string?): string
	return (lang or Glow.Lang()) == "ru" and pair[2] or pair[1]
end
function Glow.Name(variant: string?, lang: string?): string
	local pair = variant and Glow.Names[variant]
	if not pair then return string.upper(tostring(variant or "")) end
	return pick(pair, lang)
end
function Glow.T(key: string, lang: string?): string
	local pair = Glow.Text[key]
	return pair and pick(pair, lang) or key
end
local function tagText(variant: string, lang: string?): string
	return "✦ " .. Glow.Name(variant, lang) .. " ✦"
end
-- Tag colour: the variant colour (Void's main violet is too dark on the outline: its rim colour).
local function tagColor(style: any, variant: string): Color3
	return variant == "Void" and style.Outline or style.Color
end

------------------------------------------------------------------------------------------------
-- building blocks
------------------------------------------------------------------------------------------------
-- Is d our own (the glow folder or anything in it)?
local function isOurs(d: Instance, model: Instance): boolean
	local folder = model:FindFirstChild(Glow.Folder)
	return folder ~= nil and (d == folder or d:IsDescendantOf(folder))
end

local function rootOf(model: Model): BasePart?
	local folder = model:FindFirstChild(Glow.Folder)
	local root = model.PrimaryPart
	if not (root and root:IsDescendantOf(model)) then root = model:FindFirstChild("RootPart", true) end
	if root and root:IsA("BasePart") and not (folder and root:IsDescendantOf(folder)) then return root end
	local best, volume = nil, -1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not (folder and d:IsDescendantOf(folder)) then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > volume then best, volume = d, v end
		end
	end
	return best
end

local function partCount(model: Instance): number
	local folder = model:FindFirstChild(Glow.Folder)
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not (folder and d:IsDescendantOf(folder)) then n += 1 end
	end
	return n
end

local function seq(a: number, b: number, c: number?)
	if c then
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.4, b), NumberSequenceKeypoint.new(1, c) })
	end
	return NumberSequence.new(a, b)
end

local function makeEmitter(parent: Instance, spec: any, k: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Glow" .. spec.Name
	e.Texture = spec.Texture -- "" renders plain squares (the glitch pixels)
	e.Rate = spec.Rate * k
	e.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	e.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	local s = spec.Size
	e.Size = s[3] and seq(s[1] * k ^ 0.5, s[2] * k ^ 0.5, s[3] * k ^ 0.5) or seq(s[1] * k ^ 0.5, s[2] * k ^ 0.5)
	e.Color = ColorSequence.new(spec.Colors[1], spec.Colors[2])
	e.LightEmission = spec.Light or 1
	e.LightInfluence = spec.Influence or 0
	local tr = spec.Transp or { 0.1, 1 }
	e.Transparency = seq(tr[1], tr[2])
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	local rot = spec.Rot or 40
	e.RotSpeed = NumberRange.new(-rot, rot)
	e.Acceleration = Vector3.new(0, spec.Up or 0, 0)
	e.Drag = 1
	e.ZOffset = 0.5
	if spec.Square then
		e.Rotation = NumberRange.new(0, 0)
		e.RotSpeed = NumberRange.new(0, 0)
		e.Squash = NumberSequence.new(0)
	end
	if spec.Sphere then
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.ShapePartial = 1
	else
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	e.Parent = parent
	return e
end

-- Where the dog is: its centre frame, its size and its feet frame (centre bottom, the dog's
-- orientation). Kennel and line dogs (fit "Rig") use DogRig.Prepare's VisualSize / GroundLocal, which
-- replicate with the model: right even while only the root has streamed in. Displays are scaled and
-- turned after import (those attributes are stale there): their bounding box.
local function frameOf(model: Model, root: BasePart, fit: string?): (CFrame, Vector3, CFrame)
	if fit == "Rig" and model.PrimaryPart == root then
		local size, ground = model:GetAttribute("VisualSize"), model:GetAttribute("GroundLocal")
		if typeof(size) == "Vector3" and typeof(ground) == "Vector3" then
			local pivot = model:GetPivot()
			return pivot * CFrame.new(ground + Vector3.new(0, size.Y / 2, 0)), size, pivot * CFrame.new(ground)
		end
	end
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then cf, size = root.CFrame, root.Size end
	return cf, size, cf * CFrame.new(0, -size.Y / 2, 0)
end

-- The emitter volume: an invisible box over the dog, welded (unanchored, massless) to its root, so it
-- follows the dog anywhere: server moves, the lab's PivotTo, the conveyor tweens.
local function volumeOf(model: Model, root: BasePart, folder: Folder, fit: string?): (BasePart, Vector3, CFrame)
	local cf, size, feet = frameOf(model, root, fit)
	local box = Vector3.new(math.clamp(size.X, 1, 12), math.clamp(size.Y, 1, 10), math.clamp(size.Z, 1, 12))
	local p = Instance.new("Part")
	p.Name = "GlowVolume"
	p.Transparency = 1
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.Anchored = false
	p.Size = box * 0.8
	p.CFrame = cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, p
	weld.Parent = p
	p.Parent = folder
	return p, size, feet
end

-- The dig spray: variant-coloured sparks kicked up at the dog's nose while it digs.
local function makeDig(volume: BasePart, style: any, feet: CFrame, size: Vector3): ParticleEmitter?
	local spec = style.Dig
	if not spec then return nil end
	local att = Instance.new("Attachment")
	att.Name = "GlowDig"
	att.Parent = volume
	att.WorldCFrame = CFrame.new((feet * CFrame.new(0, 0.2, -size.Z * 0.42)).Position)
	local e = Instance.new("ParticleEmitter")
	e.Name = "GlowDigSpray"
	e.Texture = spec.Texture
	e.Color = ColorSequence.new(spec.Colors[1], spec.Colors[2])
	e.Size = NumberSequence.new(spec.Size[1], spec.Size[2])
	e.Transparency = NumberSequence.new(0, 1)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(35, 35)
	e.Speed = NumberRange.new(4, 7)
	e.Acceleration = Vector3.new(0, -14, 0)
	e.Drag = 0.6
	e.Lifetime = NumberRange.new(0.45, 0.85)
	e.Rate = 10
	e.LightEmission = 1
	e.LightInfluence = 0
	e.ZOffset = 0.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	if spec.Square then
		e.Rotation = NumberRange.new(0, 0)
		e.RotSpeed = NumberRange.new(0, 0)
		e.Squash = NumberSequence.new(0)
	end
	e.Enabled = false
	e.Parent = att
	return e
end

local function textLabel(name: string, text: string, color: Color3, parent: Instance): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t:SetAttribute("NoTranslate", true)
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = INK
	stroke.Parent = t
	t.Parent = parent
	return t
end

-- The mutation tag of a kennel dog: one line just above the server's name / status label
-- (SleepLabel, 190 x 46 px on the root's SleepLabelAnchor): 22 px tall, its centre 1.65 of its
-- height above the anchor.
local function makeTag(folder: Folder, root: BasePart, volume: BasePart, size: Vector3, style: any, variant: string): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GlowTag"
	gui:SetAttribute("NoTranslate", true)
	local anchor = root:FindFirstChild("SleepLabelAnchor")
	if anchor and anchor:IsA("Attachment") then
		gui.Adornee = anchor
		gui.SizeOffset = Vector2.new(0, 1.65)
	else
		gui.Adornee = volume
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.8, 0)
	end
	gui.Size = UDim2.fromOffset(170, 22)
	gui.MaxDistance = 55 -- as the SleepLabel
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local label = textLabel("Name", tagText(variant), tagColor(style, variant), gui)
	gui.Parent = folder
	return gui, label
end

function Glow.Remove(model: Instance)
	local h = handles[model]
	handles[model] = nil
	if h then
		if h.Folder then h.Folder:Destroy() end
		if h.Highlight then h.Highlight:Destroy() end
	end
	local old = model:FindFirstChild(Glow.Folder)
	if old then old:Destroy() end
	local hl = model:FindFirstChild("EconomyVariant")
	if hl and hl:IsA("Highlight") then hl:Destroy() end
end

function Glow.Apply(model: Model, variant: string?, opts: any?)
	Glow.Remove(model)
	local style = variant and Glow.Styles[variant]
	if not style then return nil end
	opts = opts or {}
	local root = rootOf(model)
	if not root then return nil end
	local k = opts.Strong and 1.8 or 1
	local folder = Instance.new("Folder")
	folder.Name = Glow.Folder
	-- before it is parented: WorldDetailQuality decides on DescendantAdded
	folder:SetAttribute(Glow.SelfManaged, true)
	folder.Parent = model
	-- the highlight keeps its old name (other scripts look for EconomyVariant)
	local h = Instance.new("Highlight")
	h.Name = "EconomyVariant"
	h.FillColor = style.Fill
	h.OutlineColor = style.Outline
	h.FillTransparency = style.FillT
	h.OutlineTransparency = style.OutlineT
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Enabled = opts.Highlight ~= false
	h.Parent = model
	local volume, size, feet = volumeOf(model, root, folder, opts.Fit)
	local emitters, base = {}, {}
	for _, spec in style.Emitters do
		local e = makeEmitter(volume, spec, k)
		table.insert(emitters, e)
		base[e] = e.Rate
	end
	local light = Instance.new("PointLight")
	light.Name = "GlowLight"
	light.Color = style.Light.Color
	light.Brightness = style.Light.Brightness * (opts.Strong and 1.6 or 1)
	light.Range = style.Light.Range * (opts.Strong and 1.4 or 1)
	light.Shadows = false
	-- a budgeted glow waits for the next pick, as its highlight does (no light over the budget or in a
	-- blackout in the meantime)
	light.Enabled = opts.Highlight ~= false
	light.Parent = volume
	local player = Players.LocalPlayer
	local handle = {
		Model = model, Variant = variant, Style = style, Highlight = h, Folder = folder, Volume = volume,
		Emitters = emitters, BaseRates = base, Light = light, Phase = math.random() * 10, Strong = opts.Strong == true,
		NextGlitch = 0, GlitchFill = style.FillT, Paused = false, Root = root, FlashUntil = 0, Digging = false,
		Underground = (model:GetAttribute("MinePlacement") or "Surface") ~= "Surface",
		Own = player ~= nil and model:GetAttribute("OwnerUserId") == player.UserId,
	}
	if opts.Dig then
		handle.Dig = makeDig(volume, style, feet, size)
		if handle.Dig then base[handle.Dig] = handle.Dig.Rate end
	end
	if opts.Tag then handle.TagGui, handle.Tag = makeTag(folder, root, volume, size, style, variant :: string) end
	handles[model] = handle
	return handle
end

------------------------------------------------------------------------------------------------
-- digging
------------------------------------------------------------------------------------------------
local function lowFX(player: Player?): boolean
	if not player then return false end
	local choice = player:GetAttribute("WorldEventFX")
	if choice == "Low" or player:GetAttribute("LowFX") == true or player:GetAttribute("ReducedMotion") == true then return true end
	if choice == nil then
		-- as WorldDetailQuality: touch devices start on Low until the player picks
		local ok, touch = pcall(function() return game:GetService("UserInputService").TouchEnabled end)
		return ok and touch == true
	end
	return false
end
Glow.LowFX = lowFX

function Glow.SetDigging(handle: any, on: boolean)
	if not handle then return end
	handle.Digging = on
	if handle.Dig then
		local want = on and not handle.Paused
		if handle.Dig.Enabled ~= want then handle.Dig.Enabled = want end
	end
end

-- A find: a burst of sparks at the nose and a short flash of the outline and the light.
function Glow.Burst(handle: any)
	if not handle then return end
	if handle.Dig and not handle.Paused and handle.Dig.Parent then
		handle.Dig:Emit(lowFX(Players.LocalPlayer) and 6 or 16)
	end
	handle.FlashUntil = os.clock() + 0.35
end

------------------------------------------------------------------------------------------------
-- pit beacons (a kennel dog digging in the mine, seen from the yard)
------------------------------------------------------------------------------------------------
local beaconFolder: Folder? = nil
local function beaconRoot(): Folder
	local f = beaconFolder
	if not (f and f.Parent) then
		f = Instance.new("Folder")
		f.Name = Glow.BeaconFolder
		f.Parent = workspace
		beaconFolder = f
	end
	return f :: Folder
end

-- The surface pit of a kennel dog: its owner's yard, DigSlot_N.DigCenter (slot models and their
-- attributes replicate without streaming; the pit part may not have streamed in).
local function pitOf(model: Instance): Vector3?
	local district = workspace:FindFirstChild("DOGROTS_District")
	local yards = district and district:FindFirstChild("04_PlayerYards")
	local owner, slotName = model:GetAttribute("OwnerUserId"), model:GetAttribute("AssignedSlot")
	if not yards or owner == nil or type(slotName) ~= "string" or slotName == "" then return nil end
	for _, yard in yards:GetChildren() do
		if yard:GetAttribute("OwnerUserId") == owner then
			local slot = yard:FindFirstChild(slotName)
			local c = slot and slot:GetAttribute("DigCenter")
			if typeof(c) == "Vector3" then return c end
			local pit = slot and slot:FindFirstChild("DarkExcavation")
			if pit and pit:IsA("BasePart") then return pit.CFrame.Position end
		end
	end
	return nil
end

local function makeBeacon(pos: Vector3, variant: string, style: any)
	local part = Instance.new("Part")
	part.Name = "Beacon_" .. variant
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(2.6, 0.2, 2.6)
	part.CFrame = CFrame.new(pos)
	local spec = style.Dig
	local e = Instance.new("ParticleEmitter")
	e.Name = "BeaconRise"
	e.Texture = spec.Texture
	e.Color = ColorSequence.new(spec.Colors[1], spec.Colors[2])
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(12, 12)
	e.Speed = NumberRange.new(3, 5)
	e.Lifetime = NumberRange.new(1.2, 1.8)
	e.Size = NumberSequence.new(0.45, 0)
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Rate = 8
	e.LightEmission = 1
	e.LightInfluence = 0
	if spec.Square then
		e.Squash = NumberSequence.new(0)
	else
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
	end
	e.Parent = part
	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = style.Light.Color
	light.Brightness = 1.6
	light.Range = 10
	light.Shadows = false
	light.Enabled = false -- the next pick lights the nearest few
	light.Parent = part
	-- the label hangs over the winch drum (4.6 studs over the pit, the beacon is 1.1 over it)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeaconTag"
	gui:SetAttribute("NoTranslate", true)
	gui.Adornee = part
	gui.StudsOffset = Vector3.new(0, 6.6, 0)
	gui.Size = UDim2.fromOffset(190, 46)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local name = textLabel("Name", tagText(variant), tagColor(style, variant), gui)
	name.Size = UDim2.fromScale(1, 0.58)
	local caption = textLabel("Caption", Glow.T("DiggingBelow"), CAPTION, gui)
	caption.Position = UDim2.fromScale(0, 0.58)
	caption.Size = UDim2.fromScale(1, 0.42)
	gui.Parent = part
	part.Parent = beaconRoot()
	return { Part = part, Emitter = e, Light = light, Gui = gui, Name = name, Caption = caption, Variant = variant }
end

function Glow.RemoveBeacon(model: Instance)
	local b = beacons[model]
	beacons[model] = nil
	if b then b.Part:Destroy() end
end

function Glow.UpdateBeacon(model: Instance)
	local v = model:GetAttribute("Variant")
	local style = type(v) == "string" and Glow.Styles[v] or nil
	local entry = tracked[model]
	local want = style ~= nil and entry ~= nil and model.Parent ~= nil
		and (model:GetAttribute("MinePlacement") or "Surface") ~= "Surface"
	if not want then
		Glow.RemoveBeacon(model)
		return nil
	end
	local c = pitOf(model)
	if not c then
		-- the yard's owner / slot attributes may land after the dog: look again a few times
		if (entry.BeaconTries or 0) < 5 then
			entry.BeaconTries = (entry.BeaconTries or 0) + 1
			task.delay(2, function()
				if tracked[model] == entry then Glow.UpdateBeacon(model) end
			end)
		end
		return nil
	end
	local pos = Vector3.new(c.X, c.Y + 1.1, c.Z)
	local b = beacons[model]
	if b and b.Variant == v and b.Part.Parent and (b.Part.CFrame.Position - pos).Magnitude < 0.05 then return b end
	Glow.RemoveBeacon(model)
	b = makeBeacon(pos, v :: string, style)
	beacons[model] = b
	return b
end

------------------------------------------------------------------------------------------------
-- tracking
------------------------------------------------------------------------------------------------
-- What a tracked dog is: from its container (EconomyVisuals tracks these three).
local function kindOf(model: Instance): string
	local parent = model.Parent
	local name = parent and parent.Name
	if name == "KennelDogs" then return "Kennel" end
	if name == "ActiveDogs" then return "Line" end
	return "Display"
end
local KIND_OPTS = {
	Kennel = { Highlight = false, Fit = "Rig", Tag = true, Dig = true },
	Line = { Highlight = false, Fit = "Rig" },
	Display = { Highlight = false },
}

-- Re-apply a model's glow when its variant, its root, its container or (displays: their box is
-- fitted to the parts that have streamed in) its parts changed; otherwise keep it.
function Glow.Refresh(model: Instance)
	local v = model:GetAttribute("Variant")
	local h = handles[model]
	if not (type(v) == "string" and Glow.Styles[v]) or model.Parent == nil then
		if h or model:FindFirstChild(Glow.Folder) then Glow.Remove(model) end
		Glow.UpdateBeacon(model)
		return nil
	end
	local root = rootOf(model :: Model)
	if not root then
		if h then Glow.Remove(model) end
		Glow.UpdateBeacon(model)
		return nil
	end
	local kind = kindOf(model)
	local keep = h ~= nil and not h.Strong and h.Variant == v and h.Root == root and root.Parent ~= nil
		and h.Volume.Parent ~= nil and h.Kind == kind
	if keep and kind == "Display" and h.Parts ~= partCount(model) then keep = false end
	if not keep then
		local was = h and { Highlight = h.Highlight.Enabled, Light = h.Light.Enabled }
		h = Glow.Apply(model :: Model, v, KIND_OPTS[kind])
		if h then
			h.Kind = kind
			if kind == "Display" then h.Parts = partCount(model) end
			-- a re-fit keeps what the budget gave (no flicker until the next pick)
			if was then h.Highlight.Enabled, h.Light.Enabled = was.Highlight, was.Light end
		end
	end
	if h then Glow.SetDigging(h, model:GetAttribute("WorkState") == "DIGGING") end
	Glow.UpdateBeacon(model)
	return h
end

function Glow.Untrack(model: Instance)
	local entry = tracked[model]
	tracked[model] = nil
	if entry then
		for _, c in entry.Conns do c:Disconnect() end
	end
	Glow.Remove(model)
	Glow.RemoveBeacon(model)
end

function Glow.IsTracked(model: Instance): boolean
	return tracked[model] ~= nil
end

-- Tracking: every dog with a Variant attribute, nearest ones get a highlight.
function Glow.Track(model: Instance)
	if not model:IsA("Model") or tracked[model] then return end
	local entry = { Conns = {}, Pending = false, LastSeq = tonumber(model:GetAttribute("WorkSequence")) or 0, BeaconTries = 0 }
	tracked[model] = entry
	-- one refresh per frame however many parts stream in
	local function schedule()
		if entry.Pending then return end
		entry.Pending = true
		task.defer(function()
			entry.Pending = false
			if tracked[model] == entry then Glow.Refresh(model) end
		end)
	end
	entry.Schedule = schedule
	local function on(signal: any, fn: (...any) -> ())
		table.insert(entry.Conns, signal:Connect(fn))
	end
	on(model:GetAttributeChangedSignal("Variant"), schedule)
	-- streaming: the Model arrives before its parts, and parts stream out and back in
	on(model.DescendantAdded, function(d)
		if d:IsA("BasePart") and not isOurs(d, model) then schedule() end
	end)
	on(model.DescendantRemoving, function(d)
		local h = handles[model]
		if h and d == h.Root then
			-- the welded volume must never outlive its root
			Glow.Remove(model)
			schedule()
		end
	end)
	on(model:GetAttributeChangedSignal("WorkState"), function()
		Glow.SetDigging(handles[model], model:GetAttribute("WorkState") == "DIGGING")
	end)
	on(model:GetAttributeChangedSignal("WorkSequence"), function()
		local n = tonumber(model:GetAttribute("WorkSequence")) or 0
		if n > entry.LastSeq then Glow.Burst(handles[model]) end
		entry.LastSeq = n
	end)
	on(model.AncestryChanged, function()
		if model.Parent == nil then
			Glow.Untrack(model)
		else
			schedule() -- moved to another container: its kind may differ
		end
	end)
	-- Destroy disconnects the model's connections before a deferred AncestryChanged handler runs;
	-- Destroying still reaches its handlers (Glow.Pick also drops tracked models left without a parent)
	on(model.Destroying, function() Glow.Untrack(model) end)
	Glow.Refresh(model)
end

------------------------------------------------------------------------------------------------
-- animation and budgets
------------------------------------------------------------------------------------------------
-- One animation step of a handle (t = os.clock()).
function Glow.Step(handle: any, t: number)
	local s = handle.Style
	local h = handle.Highlight
	if not (h and h.Parent) then return end
	local flash = t < (handle.FlashUntil or 0)
	local lightK = (handle.Strong and 1.6 or 1) * (flash and 2.2 or 1)
	local pulse = s.Pulse
	local wave = math.sin((t + handle.Phase) * pulse.Speed * math.pi * 2)
	if pulse.Glitch then
		if t >= handle.NextGlitch then
			local list = pulse.Glitch
			local c = list[math.random(1, #list)]
			h.FillColor = c
			h.OutlineColor = list[math.random(1, #list)]
			handle.GlitchFill = 0.35 + math.random() * 0.4
			h.OutlineTransparency = math.random() < 0.18 and 1 or 0
			handle.Light.Color = c
			if handle.Tag then handle.Tag.TextColor3 = c end
			handle.NextGlitch = t + (math.random() < 0.25 and 0.04 or 0.12 + math.random() * 0.45)
		end
		h.FillTransparency = math.clamp((handle.GlitchFill or s.FillT) - (flash and 0.25 or 0), 0, 1)
		handle.Light.Brightness = s.Light.Brightness * lightK
		return
	end
	local fill = s.FillT - wave * pulse.Amount
	if pulse.Flicker and math.random() < pulse.Flicker then fill = math.min(1, fill + 0.35) end
	if pulse.Sweep then
		-- a bright shine passes over the gold every few seconds
		local x = ((t + handle.Phase) % 3.2) / 3.2
		if x < 0.18 then fill = fill - math.sin(x / 0.18 * math.pi) * 0.3 end
	end
	if flash then fill -= 0.25 end
	h.FillTransparency = math.clamp(fill, 0, 1)
	handle.Light.Brightness = s.Light.Brightness * lightK * (0.8 + 0.25 * wave)
end

local function setIf(inst: any, prop: string, value: any)
	if inst[prop] ~= value then inst[prop] = value end
end
-- Particles on / off and their rates (Low FX: at most 4 a second each, the cinematic 8).
local function setParticles(h: any, run: boolean, low: boolean)
	h.Paused = not run
	local cap = h.Strong and 8 or 4
	for _, em in h.Emitters do
		local base = h.BaseRates[em] or em.Rate
		setIf(em, "Rate", low and math.min(base, cap) or base)
		setIf(em, "Enabled", run)
	end
	if h.Dig then
		local base = h.BaseRates[h.Dig] or h.Dig.Rate
		setIf(h.Dig, "Rate", low and math.min(base, 4) or base)
		setIf(h.Dig, "Enabled", run and h.Digging == true)
	end
end

-- The BLACKOUT world event, read as WorldDetailQuality reads it (ReplicatedStorage.WorldEvents.State:
-- State ACTIVE and EventId BLACKOUT). Missing objects mean no event.
function Glow.Blackout(): boolean
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("WorldEvents")
	local state = events and events:FindFirstChild("State")
	return state ~= nil and state:GetAttribute("State") == "ACTIVE" and state:GetAttribute("EventId") == "BLACKOUT"
end

-- Who gets the highlight / light / particle budget (every Glow.PickInterval while started).
-- blackout: the BLACKOUT world event (nil: read it now); no glow or beacon light then.
function Glow.Pick(eye: Vector3, low: boolean, blackout: boolean?)
	if blackout == nil then blackout = Glow.Blackout() end
	local eyeUnder = eye.Y < Glow.UndergroundY
	-- a tracked model that went away without its events (Destroy drops a deferred AncestryChanged
	-- handler, and most tracked dogs never get a handle): untrack it, so `tracked` never piles up
	local gone = {}
	for model in tracked do
		if model.Parent == nil then table.insert(gone, model) end
	end
	for _, model in gone do Glow.Untrack(model) end
	local list, stale = {}, {}
	for model, h in handles do
		local live = model.Parent ~= nil and h.Volume ~= nil and h.Volume.Parent ~= nil and h.Root ~= nil
			and h.Root.Parent ~= nil and h.Root:IsDescendantOf(model)
		if not live then
			if tracked[model] then table.insert(stale, model) end
		else
			local d = (h.Volume.CFrame.Position - eye).Magnitude
			-- a dog in the mine is not shown to a camera on the surface, nor the other way round
			local hidden = not h.Strong and h.Underground ~= eyeUnder
			table.insert(list, { H = h, D = d, Hidden = hidden, Score = d - (h.Own and Glow.OwnBonus or 0) })
		end
	end
	-- a root that went away unnoticed: drop the volume, look again
	for _, model in stale do
		local entry = tracked[model]
		Glow.Remove(model)
		if entry then entry.Schedule() end
	end
	table.sort(list, function(a, b) return a.Score < b.Score end)
	local hlBudget = low and math.floor(Glow.MaxHighlights / 2) or Glow.MaxHighlights
	local lightBudget = blackout and 0 or (low and 4 or Glow.MaxLights)
	local fxBudget = low and 10 or Glow.MaxEmitting
	local hl, lights, fx = 0, 0, 0
	for _, e in list do
		local h = e.H
		local far = e.Hidden or e.D > Glow.FarDistance
		if h.Strong then
			-- the cinematic keeps its own highlight; paused only beyond FarDistance
			setParticles(h, not far, low)
			setIf(h.Light, "Enabled", not far)
		else
			local showHl = not far and hl < hlBudget
			if showHl then hl += 1 end
			setIf(h.Highlight, "Enabled", showHl)
			local showLight = not far and e.D < Glow.LightDistance and lights < lightBudget
			if showLight then lights += 1 end
			setIf(h.Light, "Enabled", showLight)
			local run = not far and fx < fxBudget
			if run then fx += 1 end
			setParticles(h, run, low)
			if h.TagGui then setIf(h.TagGui, "Enabled", not e.Hidden) end
		end
	end
	-- pit beacons: only seen from the surface; the nearest few light up (none in a blackout)
	local beaconBudget = blackout and 0 or (low and 2 or 6)
	local blist = {}
	for model, b in beacons do
		if model.Parent == nil or not b.Part.Parent then
			Glow.RemoveBeacon(model)
		else
			table.insert(blist, { B = b, D = (b.Part.CFrame.Position - eye).Magnitude })
		end
	end
	table.sort(blist, function(a, b) return a.D < b.D end)
	local beaconLights = 0
	for _, e in blist do
		local b = e.B
		local on = not eyeUnder and e.D < Glow.BeaconDistance
		local lit = on and e.D < Glow.LightDistance and beaconLights < beaconBudget
		if lit then beaconLights += 1 end
		setIf(b.Emitter, "Rate", low and 4 or 8)
		setIf(b.Emitter, "Enabled", on)
		setIf(b.Light, "Enabled", lit)
		setIf(b.Gui, "Enabled", on)
	end
	return list, blist
end

-- The tags in the player's language (again when it changes).
function Glow.Relabel()
	local lang = Glow.Lang()
	for _, h in handles do
		if h.Tag and h.Tag.Parent then h.Tag.Text = tagText(h.Variant, lang) end
	end
	for _, b in beacons do
		if b.Name.Parent then
			b.Name.Text = tagText(b.Variant, lang)
			b.Caption.Text = Glow.T("DiggingBelow", lang)
		end
	end
end

Glow.PickInterval = 0.35
local started = false
function Glow.Start()
	if started then return end
	started = true
	local player = Players.LocalPlayer
	local lastPick, lastAnim = 0, 0
	pcall(function()
		player:GetPropertyChangedSignal("LocaleId"):Connect(Glow.Relabel)
		game:GetService("LocalizationService"):GetPropertyChangedSignal("RobloxLocaleId"):Connect(Glow.Relabel)
	end)
	Run.Heartbeat:Connect(function()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		if not camera then return end
		if now - lastPick > Glow.PickInterval then
			lastPick = now
			Glow.Pick(camera.CFrame.Position, lowFX(player))
		end
		if now - lastAnim > 1 / 20 then
			lastAnim = now
			for model, handle in handles do
				if model.Parent and (not handle.Paused or handle.Highlight.Enabled) then Glow.Step(handle, now) end
			end
		end
	end)
end

return Glow
