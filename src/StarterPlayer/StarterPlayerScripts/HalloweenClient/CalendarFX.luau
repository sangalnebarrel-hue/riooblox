-- HALLOWEEN CALENDAR — main-map countdown, client side (StarterPlayerScripts.HalloweenClient.CalendarFX).
-- docs/halloween2/DESIGN.md §13 / §17. The server (ServerScriptService.Halloween.Calendar) publishes the stage 0..8 in
-- ReplicatedStorage.Halloween.State.Calendar and moves the prebuilt stage folders into
-- Workspace.DOGROTS_District.41_HalloweenCalendar; everything that is per player happens here, from the cumulative
-- per-stage numbers of HalloweenCalendarConfig (CalendarRules.StageParams, glided over a few seconds on a change):
-- * DEAD GRASS — a share of the island grass parts (EventTintSurface + Material Grass, the yards excluded) turns to dead
--   colours, nearest the Dead Yard first with a per-part hash (Pure.RankGrass); originals are stored, the tint is
--   re-applied every 60 s and a few seconds after a world event's own colour restore, never during a world event.
-- * LIGHT — a Halloween Lighting layer "CALENDAR" (Prio 15: below the Dead Yard / Underyard looks) for fog, haze, a
--   dusky grade, bloom, clouds and a bigger sky moon; Atmosphere density stays <= HalloweenCalendarConfig.Lighting
--   .MaxDensity (.36) for gameplay visibility. Nights get a little darker from D-6.
-- * THE MOON — halo rings make BloodMoonFX's Buried Moon read bigger from D-3; at D-1 a black eclipse disc starts
--   sliding over it (the moon transformation), on October 31 with a violet corona. Never during a Blood Moon.
-- * LAMPS — the 102 Halloween_MapLamp glasses / lights blend toward calendar orange / violet (through MainMapLayer's
--   SetLampTint, so MainMapLayer stays their only writer).
-- * WINDOWS — the DogDex museum BlueWindow panes and the Dog Shelter glass light up warm and blink (Neon, restored
--   exactly), more often at night.
-- * TREES — CalEyes eyes on the calendar trees open, stare and blink (closed = the saved Transparency 1); CalSway
--   branches (CalBranch models: CalPivot / CalAxis / CalPhase) sway about their base with gusts; candle flames and the
--   calendar lights flicker (Brightness only: WorldDetailQuality owns Enabled).
-- * PRESENCES — bats circling the CalBatRoost points, distant ghosts drifting at the CalGhostPath markers (night),
--   bobbing ghost dogs, spectral wisps and falling dry leaves near the camera, ground mist banks, whispers near the face
--   trees and strange night sounds (Halloween Audio cues), a banner when the stage goes up while you play.
-- Quality: every count / range is scaled by Config.Quality[q].CalendarFX (else HalloweenCalendarConfig.Quality);
-- ReducedMotion: no sway, no falling leaves, calm bobbing. Mechanics never depend on any of this.
-- Respects Shared.CalendarEnabled() and the player's map-decor toggle (MainMapLayer.IsVisible / Bus "MapDecor" /
-- player attribute HwMapDecor): hidden or switched off, everything is put back exactly and the stage folders are hidden
-- locally (LocalTransparencyModifier, lights 0, GUIs off). Nothing runs off the main island (the Underyard, the Void).
-- API: Start(ctx), Stop(), Stage() -> n, Params() -> table, Active() -> bool, Refresh(); Pure.* (tests/calendar.luau).
-- All client parts live in workspace.DOGROTS_HalloweenFX.Calendar (SelfManagedFX).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LightingService = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local HalloweenFolder = RS:WaitForChild("Halloween")
local Cfg = require(HalloweenFolder:WaitForChild("HalloweenCalendarConfig"))
local Rules = require(HalloweenFolder:WaitForChild("CalendarRules"))

local M = {}
local Pure = {}
M.Pure = Pure
M.Warned = false
M.Listening = false

local V3 = Vector3.new
local CF = CFrame.new
local TAU = math.pi * 2

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

M.Island = { X0 = -240, X1 = 240, Z0 = -280, Z1 = 790, YMin = -20, YMax = 260 } -- the main map (not the Void / Underyard)
M.RU = { ["HAPPY HALLOWEEN!"] = "С ХЭЛЛОУИНОМ!" } -- calendar world lettering (NoTranslate + HwTextEN, built by Stage08)

---------------------------------------------------------------------------------------------------------------------
-- Pure helpers (tests/calendar.luau)
---------------------------------------------------------------------------------------------------------------------
local function hash(text: string): number
	return Rules.Hash(text)
end
Pure.Hash = hash

-- deterministic per-part key: the part's name + its rounded position (the same on every client, survives streaming)
function Pure.PartKey(name: string, x: number, z: number): string
	return string.format("%s|%d|%d", name, math.floor(x + .5), math.floor(z + .5))
end

-- grass parts {Key, X, Z} -> ranked list (first = tinted first): nearest the Dead Yard (Grass.Origin) first, mixed with
-- the per-part hash so the front is ragged (Grass.Spread 0 = pure hash, 1 = pure distance)
function Pure.GrassScore(key: string, x: number, z: number, cfg): number
	local g = cfg.Grass
	local d = math.sqrt((x - g.Origin.X) ^ 2 + (z - g.Origin.Z) ^ 2)
	local u = math.clamp(d / g.SpreadRange, 0, 1)
	return (1 - g.Spread) * hash(key) + g.Spread * u
end

function Pure.RankGrass(parts: { any }, cfg): { any }
	local list = table.clone(parts)
	local score = {}
	for _, p in ipairs(list) do
		score[p] = Pure.GrassScore(p.Key, p.X, p.Z, cfg)
	end
	table.sort(list, function(a, b)
		if score[a] ~= score[b] then
			return score[a] < score[b]
		end
		return a.Key < b.Key
	end)
	return list
end

function Pure.TintCount(n: number, share: number): number
	return math.clamp(math.floor(n * math.clamp(share, 0, 1) + .5), 0, n)
end

-- the dead colour of a grass part at a depth (0 = original)
function Pure.DeadColor(key: string, orig: Color3, depth: number, cfg): Color3
	local pal = cfg.Grass.Colors
	local c = rgb(pal[math.floor(hash(key .. "#c") * #pal) + 1])
	return orig:Lerp(c, math.clamp(depth, 0, 1))
end

-- a lamp's colour at a calendar tint strength (0 = the event colour)
function Pure.LampColor(key: string, eventColor: Color3, strength: number, cfg): Color3
	if strength <= 0 then
		return eventColor
	end
	local pal = cfg.Lamps.Colors
	local c = rgb(pal[math.floor(hash(key .. "#l") * #pal) + 1])
	return eventColor:Lerp(c, math.clamp(strength, 0, 1))
end

local function qualityScale(quality: string, cfg, gameConfig: any?): number
	local q = gameConfig and gameConfig.Quality and gameConfig.Quality[quality]
	if type(q) == "table" and type(q.CalendarFX) == "number" then
		return q.CalendarFX
	end
	return cfg.Quality[quality] or 1
end
Pure.QualityScale = qualityScale

-- what runs: counts and ranges from the stage parameters and the quality tier
function Pure.Plan(p: { [string]: number }, quality: string, cfg, gameConfig: any?): { [string]: any }
	local q = qualityScale(quality, cfg, gameConfig)
	local low = quality == "Low"
	local function count(v: number, min: number?): number
		if v <= 0 then
			return 0
		end
		return math.max(min or 1, math.floor(v * q + .5))
	end
	return {
		Q = q,
		Quality = quality,
		Bats = count(p.Bats or 0),
		Ghosts = count(p.Ghosts or 0),
		Wisps = count(p.Wisps or 0),
		Mist = (p.Mist or 0) > 0 and math.max(1, math.floor(cfg.Mist.Banks * p.Mist * q + .5)) or 0,
		MistRate = cfg.Mist.Rate * math.clamp(p.Mist or 0, 0, 1) * (low and .7 or 1),
		Leaves = (p.Leaves or 0) > 0 and math.max(1, math.floor(cfg.Leaves.Rate * p.Leaves * q + .5)) or 0,
		SwayRange = cfg.Sway.Range * (low and .5 or (.6 + .4 * q)),
		SwayParts = math.floor(cfg.Sway.MaxParts * q),
		EyeRange = cfg.Eyes.Range * (low and .6 or 1),
		Windows = (p.Windows or 0) * (low and .6 or 1),
		Whispers = p.Whispers or 0,
		Sounds = p.Sounds or 0,
		Halo = p.Halo or 0,
		Eclipse = p.Eclipse or 0,
		Corona = not low,
		GhostDogs = not low,
	}
end

-- eyes: share of the time open (the stage's Eyes) -> how long the next open / closed spell lasts
function Pure.EyeOpenShare(eyes: number): number
	return math.clamp(eyes or 0, 0, .95)
end

function Pure.EyeSpan(open: boolean, share: number, rand: () -> number, cfg): number
	local e = cfg.Eyes
	share = Pure.EyeOpenShare(share)
	if open then
		return e.Open[1] + (e.Open[2] - e.Open[1]) * rand() * (.5 + share)
	end
	local base = e.Closed[1] + (e.Closed[2] - e.Closed[1]) * rand()
	return base * (1.4 - share)
end

-- branch sway angle (radians) at time t: a slow swing, a second harmonic and a rare gust
function Pure.SwayAngle(t: number, phase: number, ampDeg: number, speed: number, gust: number): number
	local a = math.sin(t * speed + phase) * .75 + math.sin(t * speed * 2.3 + phase * 1.7) * .25
	local g = math.max(0, math.sin(t * .21 + phase * .3)) ^ 6 * gust
	return math.rad(ampDeg) * (a + g)
end

-- the CALENDAR Lighting layer profile (full look; the layer weight is the stage's Atmos) at a night factor 0..1
function Pure.Profile(p: { [string]: number }, night: number, cfg): { [string]: any }
	local L = cfg.Lighting
	local fin = math.clamp(p.Finale or 0, 0, 1)
	local function mix(a: { number }, b: { number }?): Color3
		local c = rgb(a)
		if b and fin > 0 then
			c = c:Lerp(rgb(b), fin)
		end
		return c
	end
	local gd, gn = L.GradeDay, L.GradeNight
	local fg = L.Finale and L.Finale.Grade or {}
	night = math.clamp(night, 0, 1)
	local tint = rgb(gd.Tint):Lerp(rgb(gn.Tint), night)
	if fg.Tint and fin > 0 then
		tint = tint:Lerp(rgb(fg.Tint), fin)
	end
	local sat = gd.Saturation + (gn.Saturation - gd.Saturation) * night
	local con = gd.Contrast + (gn.Contrast - gd.Contrast) * night
	if fin > 0 then
		sat += ((fg.Saturation or sat) - sat) * fin
		con += ((fg.Contrast or con) - con) * fin
	end
	local bri = gd.Brightness + (gn.Brightness - gd.Brightness) * night - L.NightDarken * night * math.clamp(p.Dark or 0, 0, 1)
	return {
		Prio = L.Prio,
		Atmo = {
			Density = math.min(L.Atmo.Density, L.MaxDensity), Offset = L.Atmo.Offset, Haze = L.Atmo.Haze, Glare = L.Atmo.Glare,
			Color = mix(L.Atmo.Color, L.Finale and L.Finale.Atmo and L.Finale.Atmo.Color),
			Decay = mix(L.Atmo.Decay, L.Finale and L.Finale.Atmo and L.Finale.Atmo.Decay),
		},
		Bloom = { Intensity = L.Bloom.Intensity, Size = L.Bloom.Size, Threshold = L.Bloom.Threshold },
		Clouds = { Cover = L.Clouds.Cover, Density = L.Clouds.Density, Color = mix(L.Clouds.Color, L.Finale and L.Finale.Clouds and L.Finale.Clouds.Color) },
		Sky = { MoonAngularSize = L.Sky.MoonAngularSize, StarCount = L.Sky.StarCount },
		Grade = { Tint = tint, Saturation = sat, Contrast = con, Brightness = bri },
	}
end

-- a bat circling a roost: position at time t (i of n)
function Pure.BatPos(center: Vector3, i: number, n: number, t: number, cfg): Vector3
	local b = cfg.Bats
	local h1, h2 = hash("bat" .. i), hash("bat#" .. i)
	local r = b.Radius[1] + (b.Radius[2] - b.Radius[1]) * h1
	local dir = (i % 3 == 0) and -1 or 1
	local a = (i - 1) / math.max(1, n) * TAU + dir * (.55 + .4 * h2) * t
	local wob = math.sin(t * (1.1 + h1) + i * 2.3) * r * .18
	local y = b.Height[1] + (b.Height[2] - b.Height[1]) * h2 + math.sin(t * (.7 + h2) + i) * 1.4
	return center + V3(math.cos(a) * (r + wob), y, math.sin(a) * (r + wob))
end

-- wing flap angle (radians) with the occasional glide
function Pure.Wing(t: number, i: number): number
	local ph = hash("wing" .. i) * TAU
	local glide = math.clamp(math.sin(t * .4 + ph) * 2 + 1.1, 0, 1)
	return (.15 + .7 * glide) * math.sin(t * (11 + 3 * hash("wf" .. i)) + ph) + .1
end

-- a distant ghost drifting round a marker (radius r, height h) at phase u 0..1 of its life
function Pure.GhostPos(center: Vector3, r: number, h: number, u: number, seed: number): Vector3
	local a = seed * TAU + u * TAU * .55
	local rr = r * (.75 + .25 * math.sin(u * TAU * 1.3 + seed * 5))
	return center + V3(math.cos(a) * rr, h * .25 * math.sin(u * TAU * 2 + seed * 3), math.sin(a) * rr)
end

-- fade in 15 %, out 20 %
function Pure.Fade(u: number): number
	if u <= 0 or u >= 1 then
		return 0
	end
	local function sm(x: number): number
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	return math.min(sm(u / .15), sm((1 - u) / .2))
end

-- candle-like flicker multiplier, deterministic
function Pure.Flicker(t: number, i: number): number
	local n = math.sin(t * 7.3 + i * 1.7) * .5 + math.sin(t * 13.1 + i * 3.1) * .3 + math.sin(t * 2.3 + i) * .2
	return .9 + .14 * n
end

function Pure.OnIsland(p: Vector3): boolean
	local b = M.Island
	return p.X >= b.X0 and p.X <= b.X1 and p.Z >= b.Z0 and p.Z <= b.Z1 and p.Y >= b.YMin and p.Y <= b.YMax
end

-- night factor 0..1 from the server's LightingController attributes (DayFactor 1 = day), else from the clock (same curve)
function Pure.Darkness(dayFactor: any, isNight: any, clock: number?): number
	if type(dayFactor) == "number" then
		return 1 - math.clamp(dayFactor, 0, 1)
	end
	if type(isNight) == "boolean" then
		return isNight and 1 or 0
	end
	local c = (clock or 14) % 24
	return 1 - math.clamp((math.cos((c - 13) * math.pi / 12) + .2) * 1.2, 0, 1)
end

---------------------------------------------------------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------------------------------------------------------
local S = {
	Started = false, Running = false, Ctx = nil :: any, Conns = {} :: { RBXScriptConnection },
	Stage = 0, Enabled = false, Visible = true, Active = false, KnownStage = nil :: number?,
	Target = Rules.StageParams(0, Cfg), From = Rules.StageParams(0, Cfg), Cur = Rules.StageParams(0, Cfg), GlideT0 = 0, GlideDur = 4,
	Plan = nil :: any, PlanDirty = true, CamPos = V3(0, 0, 377), OnIsland = true, Dark = 0, Blood = 0, YardW = 0,
	Folder = nil :: Folder?, District = nil :: Instance?, Root = nil :: Instance?, StateFolder = nil :: Instance?,
	Rng = Random.new(), NextSlow = 0, NextGrass = 0, GrassAfterEvent = 0, WorldEvent = false,
	-- per subsystem
	Grass = {} :: { any }, GrassByPart = {} :: { [Instance]: any }, GrassApplied = 0,
	Layer = nil :: any, LayerWeight = -1, LampStrength = -1, LampKeys = {} :: { [Instance]: string },
	Windows = {} :: { BasePart }, WindowOrig = {} :: { [BasePart]: any }, WindowLit = {} :: { [BasePart]: number }, NextWindow = 0, NextWindowScan = 0,
	Eyes = {} :: { [Instance]: any }, Sway = {} :: { [Instance]: any }, Flames = {} :: { BasePart }, Lights = {} :: { Light },
	Roosts = {} :: { Attachment }, GhostMarks = {} :: { Attachment }, GhostDogs = {} :: { [Instance]: any }, FaceTrees = {} :: { [Instance]: boolean },
	Bats = {} :: { any }, Ghosts = {} :: { any }, Wisps = nil :: any, Leaves = nil :: any, Mist = nil :: any, Moon = nil :: any,
	NextGhost = 0, NextWhisper = 0, NextSound = 0, BatRoostKey = "", Settled = true, Player = nil :: Player?, RestoreToken = 0,
	GrassInstant = true, SwayAcc = 0,
}
M._State = S

local function rand(): number
	return S.Rng:NextNumber()
end

local function shared()
	return S.Ctx.Shared
end

local function fxFolder(): Folder
	if S.Folder and S.Folder.Parent then
		return S.Folder
	end
	local root = S.Ctx and S.Ctx.FX and S.Ctx.FX.Folder() or workspace
	local f = root:FindFirstChild("Calendar")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Calendar"
		f:SetAttribute("SelfManagedFX", true)
		f.Parent = root
	end
	S.Folder = f :: Folder
	return f :: Folder
end

local function part(props: { [string]: any }): BasePart
	local p: BasePart = Instance.new(props.Class or "Part") :: any
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Size = props.Size or V3(1, 1, 1)
	if props.Shape then
		(p :: any).Shape = props.Shape
	end
	if props.Mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Transparency = props.Transparency or 0
	p.Name = props.Name or "CalendarFX"
	p.CFrame = props.CFrame or CF(0, -500, 0)
	p.Parent = props.Parent or fxFolder()
	return p
end

local function worldEventBusy(): boolean
	local we = RS:FindFirstChild("WorldEvents")
	local st = we and we:FindFirstChild("State")
	local s = st and st:GetAttribute("State")
	return s == "ACTIVE" or s == "ENDING"
end

local function russian(): boolean
	local ok, ru = pcall(shared().IsRussian)
	return ok and ru == true
end

---------------------------------------------------------------------------------------------------------------------
-- DEAD GRASS
---------------------------------------------------------------------------------------------------------------------
local EXCLUDE = {}
for _, n in ipairs(Cfg.Grass.Exclude) do
	EXCLUDE[n] = true
end

local function grassCandidate(d: Instance): boolean
	if not d:IsA("BasePart") or d.Material ~= Enum.Material.Grass or d:GetAttribute("EventTintSurface") ~= true then
		return false
	end
	-- the top-level district child it lives under must not be excluded (the players' yards)
	local node: Instance? = d
	while node and node.Parent and node.Parent ~= S.District do
		node = node.Parent
	end
	return node ~= nil and not EXCLUDE[node.Name]
end

local function trackGrass(d: Instance)
	if S.GrassByPart[d] or not grassCandidate(d) then
		return
	end
	local p = d :: BasePart
	local pos = p.CFrame.Position
	local row = { Part = p, Key = Pure.PartKey(p.Name, pos.X, pos.Z), X = pos.X, Z = pos.Z, Orig = nil :: Color3?, Want = nil :: Color3?,
		Tween = nil :: Tween? }
	row.Score = Pure.GrassScore(row.Key, row.X, row.Z, Cfg)
	if not worldEventBusy() then
		row.Orig = p.Color -- not mid-event: the live colour is the real one
	end
	S.GrassByPart[p] = row
	table.insert(S.Grass, row)
end

local function scanGrass()
	if not S.District then
		return
	end
	for _, d in ipairs(S.District:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("EventTintSurface") == true then
			trackGrass(d)
		end
	end
end

-- colours read back as float32: compare within a fraction of an 8-bit level
local function sameColor(a: Color3?, b: Color3?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < .6 / 255
end
Pure.SameColor = sameColor

local function setColor(row, c: Color3, glide: number)
	local p: BasePart = row.Part
	if row.Tween then
		row.Tween:Cancel() -- a glide still running must never overwrite the new colour
		row.Tween = nil
	end
	if sameColor(p.Color, c) then
		return
	end
	if glide > 0 then
		local tw = TweenService:Create(p, TweenInfo.new(glide, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = c })
		row.Tween = tw
		tw:Play()
	else
		p.Color = c
	end
end

-- tint the ranked share; everything else back to its original. on = false restores every part.
local function applyGrass(on: boolean, glide: number)
	if worldEventBusy() then
		return -- the world event's own tint owns the colours right now (it restores them when it ends)
	end
	-- drop streamed-out parts
	for i = #S.Grass, 1, -1 do
		local row = S.Grass[i]
		if not row.Part.Parent then
			S.GrassByPart[row.Part] = nil
			table.remove(S.Grass, i)
		elseif row.Orig == nil and not sameColor(row.Part.Color, row.Want) then
			row.Orig = row.Part.Color
		end
	end
	table.sort(S.Grass, function(a, b)
		if a.Score ~= b.Score then
			return a.Score < b.Score
		end
		return a.Key < b.Key
	end)
	local n = on and Pure.TintCount(#S.Grass, S.Cur.Grass or 0) or 0
	local depth = S.Cur.GrassDepth or .5
	for i, row in ipairs(S.Grass) do
		local orig = row.Orig
		if orig == nil then
			continue
		end
		local want = (i <= n) and Pure.DeadColor(row.Key, orig, depth, Cfg) or orig
		local gliding = row.Tween ~= nil and row.Tween.PlaybackState == Enum.PlaybackState.Playing
		if not sameColor(row.Want, want) or (not gliding and not sameColor(row.Part.Color, want)) then
			row.Want = want
			setColor(row, want, glide)
		end
	end
	S.GrassApplied = n
end

---------------------------------------------------------------------------------------------------------------------
-- LIGHTING LAYER / LAMPS
---------------------------------------------------------------------------------------------------------------------
local function lightingModule(): any
	return S.Ctx and S.Ctx.Modules and S.Ctx.Modules.Lighting
end

local function updateLayer(on: boolean)
	local L = lightingModule()
	if not (L and L.Layer) then
		return
	end
	local w = on and math.clamp(S.Cur.Atmos or 0, 0, 1) or 0
	if w <= 0 then
		if S.Layer then
			S.Layer:Remove(Cfg.Lighting.Fade)
			S.Layer = nil
			S.LayerWeight = -1
		end
		return
	end
	local night = 0
	local W = L.Weights and L.Weights()
	if W then
		night = W.Night or 0
	end
	-- re-registering the name swaps the profile in place (weight and glide are kept)
	S.Layer = L.Layer("CALENDAR", Pure.Profile(S.Cur, night, Cfg))
	if math.abs(w - S.LayerWeight) > .004 then
		S.LayerWeight = w
		S.Layer:Set(w, Cfg.Lighting.Fade)
	end
end

local function mainMapLayer(): any
	return S.Ctx and S.Ctx.Modules and S.Ctx.Modules.MainMapLayer
end

local function lampKey(inst: Instance): string
	local k = S.LampKeys[inst]
	if not k then
		local pos = Vector3.zero
		local par = inst:IsA("BasePart") and inst or inst.Parent
		if par and par:IsA("BasePart") then
			pos = par.CFrame.Position
		end
		k = Pure.PartKey("lamp", pos.X, pos.Z)
		S.LampKeys[inst] = k
	end
	return k
end

-- lamp tint strength 0..1 (quantised so the lamps are only rewritten on a real change)
local function updateLamps(on: boolean)
	local strength = on and math.floor(math.clamp(S.Cur.Lamps or 0, 0, 1) * 20 + .5) / 20 or 0
	if strength == S.LampStrength then
		return
	end
	S.LampStrength = strength
	local MML = mainMapLayer()
	if MML and MML.SetLampTint then
		if strength <= 0 then
			MML.SetLampTint(nil)
		else
			MML.SetLampTint(function(inst: Instance, ev: Color3): Color3?
				return Pure.LampColor(lampKey(inst), ev, strength, Cfg)
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- WINDOWS
---------------------------------------------------------------------------------------------------------------------
local function scanWindows()
	S.Windows = {}
	if not S.District then
		return
	end
	for _, path in ipairs(Cfg.Windows.Paths) do
		local node: Instance? = S.District
		for i = 1, #path - 1 do
			node = node and node:FindFirstChild(path[i])
		end
		local last = path[#path]
		if node then
			if string.sub(last, 1, 1) == "*" then
				local name = string.sub(last, 2)
				for _, c in ipairs(node:GetChildren()) do
					if c.Name == name and c:IsA("BasePart") then
						table.insert(S.Windows, c)
					end
				end
			else
				local c = node:FindFirstChild(last)
				if c and c:IsA("BasePart") then
					table.insert(S.Windows, c)
				end
			end
		end
	end
end

local function restoreWindow(w: BasePart)
	local o = S.WindowOrig[w]
	S.WindowLit[w] = nil
	if o and w.Parent then
		w.Material = o.Material
		w.Color = o.Color
		w.Transparency = o.Transparency
	end
	S.WindowOrig[w] = nil
end

local function lightWindow(w: BasePart, now: number)
	if not S.WindowOrig[w] then
		S.WindowOrig[w] = { Material = w.Material, Color = w.Color, Transparency = w.Transparency }
	end
	local wc = Cfg.Windows
	w.Material = Enum.Material.Neon
	w.Color = rgb(wc.Colors[math.floor(rand() * #wc.Colors) + 1])
	w.Transparency = wc.Transparency
	local dur = wc.On[1] + (wc.On[2] - wc.On[1]) * rand()
	S.WindowLit[w] = now + dur
	-- a flicker: off and on again once mid-way
	if rand() < wc.Flicker then
		local token = S.WindowLit[w]
		task.delay(dur * .4, function()
			if S.WindowLit[w] == token and w.Parent then
				w.Transparency = .7
				task.delay(.09 + rand() * .1, function()
					if S.WindowLit[w] == token and w.Parent then
						w.Transparency = wc.Transparency
					end
				end)
			end
		end)
	end
end

local function updateWindows(now: number, dt: number)
	if now >= S.NextWindowScan then
		S.NextWindowScan = now + Cfg.Windows.Rescan
		scanWindows()
	end
	for w, untilT in pairs(S.WindowLit) do
		if now >= untilT or not w.Parent then
			restoreWindow(w)
		end
	end
	local rate = (S.Plan and S.Plan.Windows or 0) * (.35 + .65 * S.Dark) -- per minute
	if rate <= 0 or #S.Windows == 0 then
		return
	end
	if rand() < rate / 60 * dt then
		-- a window near the camera that is not lit
		local near = {}
		for _, w in ipairs(S.Windows) do
			if w.Parent and not S.WindowLit[w] and (w.CFrame.Position - S.CamPos).Magnitude < Cfg.Windows.Range then
				table.insert(near, w)
			end
		end
		if #near > 0 then
			lightWindow(near[math.floor(rand() * #near) + 1], now)
		end
	end
end

local function restoreAllWindows()
	for w in pairs(S.WindowOrig) do
		restoreWindow(w)
	end
	S.WindowLit = {}
end

---------------------------------------------------------------------------------------------------------------------
-- CALENDAR ROOT: eyes, sway, flames, lights, markers, lettering
---------------------------------------------------------------------------------------------------------------------
local function eyeGroupOf(p: BasePart): Instance
	return p.Parent or p
end

local function trackRoot(d: Instance)
	if d:IsA("BasePart") then
		if d:GetAttribute("CalEyes") == true then
			local g = eyeGroupOf(d)
			local row = S.Eyes[g]
			if not row then
				row = { Parts = {}, Open = false, Next = 0, Far = d:GetAttribute("CalFar") == true, Pos = d.CFrame.Position, Blink = 0 }
				S.Eyes[g] = row
			end
			table.insert(row.Parts, d)
		elseif d:GetAttribute("HwCandle") == true then
			table.insert(S.Flames, d)
		end
		local sway = d.Parent and d.Parent:GetAttribute("CalSway") == true and d.Parent or nil
		if not sway and d.Parent and d.Parent.Parent and d.Parent.Parent:GetAttribute("CalSway") == true then
			sway = d.Parent.Parent -- a lantern model hanging inside a branch
		end
		if sway then
			local row = S.Sway[sway]
			if not row then
				local pivot = sway:GetAttribute("CalPivot")
				local axis = sway:GetAttribute("CalAxis")
				if typeof(pivot) ~= "Vector3" then
					return
				end
				row = { Parts = {}, Rest = {}, Pivot = pivot, Axis = typeof(axis) == "Vector3" and axis.Unit or V3(1, 0, 0),
					Phase = tonumber(sway:GetAttribute("CalPhase")) or 0, Moved = false }
				row.Speed = Cfg.Sway.Speed[1] + (Cfg.Sway.Speed[2] - Cfg.Sway.Speed[1]) * hash(Pure.PartKey("sway", pivot.X, pivot.Z))
				S.Sway[sway] = row
			end
			table.insert(row.Parts, d)
			table.insert(row.Rest, d.CFrame)
		end
		if d:GetAttribute("CalGhost") == nil and d.Parent and d.Parent:GetAttribute("CalGhost") == true then
			local g = d.Parent
			local row = S.GhostDogs[g]
			if not row then
				row = { Parts = {}, Rest = {}, Phase = hash(d.Parent:GetFullName()) * TAU, Moved = false }
				S.GhostDogs[g] = row
			end
			table.insert(row.Parts, d)
			table.insert(row.Rest, d.CFrame)
		end
	elseif d:IsA("Light") then
		if type(d:GetAttribute("HwBaseBrightness")) == "number" then
			table.insert(S.Lights, d)
		end
	elseif d:IsA("Attachment") then
		if d.Name == "CalBatRoost" then
			table.insert(S.Roosts, d)
		elseif d.Name == "CalGhostPath" then
			table.insert(S.GhostMarks, d)
		end
	elseif d:IsA("TextLabel") then
		local en = d:GetAttribute("HwTextEN")
		if type(en) == "string" then
			d.Text = russian() and M.RU[en] or en
		end
	elseif d:IsA("Model") and d:GetAttribute("CalFace") == true then
		S.FaceTrees[d] = true
	end
end

local function scanRoot()
	S.Eyes, S.Sway, S.Flames, S.Lights, S.Roosts, S.GhostMarks, S.GhostDogs, S.FaceTrees = {}, {}, {}, {}, {}, {}, {}, {}
	if not S.Root then
		return
	end
	for _, d in ipairs(S.Root:GetDescendants()) do
		trackRoot(d)
	end
end

local function pruneRoot()
	for g, row in pairs(S.Eyes) do
		if not g.Parent then
			S.Eyes[g] = nil
		else
			for i = #row.Parts, 1, -1 do
				if not row.Parts[i].Parent then
					table.remove(row.Parts, i)
				end
			end
		end
	end
	for _, map in ipairs({ S.Sway, S.GhostDogs }) do
		for m, row in pairs(map) do
			if not m.Parent then
				map[m] = nil
			else
				for i = #row.Parts, 1, -1 do
					if not row.Parts[i].Parent then
						table.remove(row.Parts, i)
						table.remove(row.Rest, i)
					end
				end
			end
		end
	end
	for _, list in ipairs({ S.Flames :: { any }, S.Lights :: { any }, S.Roosts :: { any }, S.GhostMarks :: { any } }) do
		for i = #list, 1, -1 do
			if not list[i].Parent then
				table.remove(list, i)
			end
		end
	end
	for m in pairs(S.FaceTrees) do
		if not m.Parent then
			S.FaceTrees[m] = nil
		end
	end
end

local function setEyes(row, open: boolean)
	row.Open = open
	for _, p in ipairs(row.Parts) do
		p.Transparency = open and 0 or 1
	end
end

local function updateEyes(now: number, dt: number)
	local share = S.Cur.Eyes or 0
	local range = S.Plan and S.Plan.EyeRange or Cfg.Eyes.Range
	for _, row in pairs(S.Eyes) do
		if share <= 0 then
			if row.Open then
				setEyes(row, false)
			end
		elseif row.Far or (row.Pos - S.CamPos).Magnitude < range then
			if row.Blink > 0 and now >= row.Blink then
				row.Blink = 0
				setEyes(row, true)
			elseif now >= row.Next then
				local open = not row.Open
				setEyes(row, open)
				row.Next = now + Pure.EyeSpan(open, share, rand, Cfg)
			elseif row.Open and row.Blink == 0 and rand() < .25 * dt then
				-- a quick blink while staring
				for _, p in ipairs(row.Parts) do
					p.Transparency = 1
				end
				row.Blink = now + Cfg.Eyes.BlinkTime
			end
		end
	end
end

local function closeAllEyes()
	for _, row in pairs(S.Eyes) do
		setEyes(row, false)
		row.Next, row.Blink = 0, 0
	end
end

local swayParts: { BasePart } = {}
local swayCFs: { CFrame } = {}
local function updateSway(t: number)
	local amp = S.Cur.Sway or 0
	local reduced = shared().ReducedMotion()
	local range = S.Plan and S.Plan.SwayRange or Cfg.Sway.Range
	local budget = S.Plan and S.Plan.SwayParts or Cfg.Sway.MaxParts
	table.clear(swayParts)
	table.clear(swayCFs)
	local n = 0
	for _, row in pairs(S.Sway) do
		local near = amp > 0 and not reduced and (row.Pivot - S.CamPos).Magnitude < range and n + #row.Parts <= budget
		if near then
			local ang = Pure.SwayAngle(t, row.Phase, amp, row.Speed, Cfg.Sway.Gust)
			local pv = CF(row.Pivot)
			local rot = pv * CFrame.fromAxisAngle(row.Axis, ang) * pv:Inverse()
			for i, p in ipairs(row.Parts) do
				n += 1
				swayParts[n] = p
				swayCFs[n] = rot * row.Rest[i]
			end
			row.Moved = true
		elseif row.Moved then
			row.Moved = false
			for i, p in ipairs(row.Parts) do
				n += 1
				swayParts[n] = p
				swayCFs[n] = row.Rest[i]
			end
		end
	end
	if n > 0 then
		workspace:BulkMoveTo(swayParts, swayCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function restoreSway()
	for _, map in ipairs({ S.Sway, S.GhostDogs }) do
		for _, row in pairs(map) do
			if row.Moved then
				row.Moved = false
				for i, p in ipairs(row.Parts) do
					if p.Parent then
						p.CFrame = row.Rest[i]
					end
				end
			end
		end
	end
end

local function updateGhostDogs(t: number)
	if not (S.Plan and S.Plan.GhostDogs) then
		return
	end
	local parts, cfs = {}, {}
	local calm = shared().ReducedMotion()
	for _, row in pairs(S.GhostDogs) do
		local first = row.Rest[1]
		if first and (first.Position - S.CamPos).Magnitude < 140 then
			local dy = math.sin(t * 1.3 + row.Phase) * (calm and .12 or .35)
			local off = CF(0, dy, 0)
			for i, p in ipairs(row.Parts) do
				table.insert(parts, p)
				table.insert(cfs, off * row.Rest[i])
			end
			row.Moved = true
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function flicker(t: number)
	for i, f in ipairs(S.Flames) do
		if f.Parent and (f.CFrame.Position - S.CamPos).Magnitude < Cfg.Candles.Range then
			f.Transparency = math.clamp((1 - Pure.Flicker(t * 1.6, i + 40)) * 1.6, 0, .3)
		end
	end
	if S.WorldEvent then
		return
	end
	for i, l in ipairs(S.Lights) do
		local par = l.Parent
		if par and par:IsA("BasePart") and (par.CFrame.Position - S.CamPos).Magnitude < 200 then
			local base = l:GetAttribute("HwBaseBrightness")
			if type(base) == "number" then
				l.Brightness = base * Pure.Flicker(t, i)
			end
		end
	end
end

local function restoreFlicker()
	for _, l in ipairs(S.Lights) do
		local base = l:GetAttribute("HwBaseBrightness")
		if l.Parent and type(base) == "number" then
			l.Brightness = base
		end
	end
	for _, f in ipairs(S.Flames) do
		if f.Parent then
			f.Transparency = 0
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- BATS
---------------------------------------------------------------------------------------------------------------------
local BAT = Color3.fromRGB(22, 14, 30)

local function makeBat(model: Instance, s: number)
	local body = part({ Name = "CalBatBody", Size = V3(.42, .36, .9) * s, Color = BAT, Mesh = true, Parent = model })
	-- wings: flat wedges (thin axis turned vertical in updateBats), .9 span each, swept back
	local wl = part({ Name = "CalBatWing", Class = "WedgePart", Size = V3(.05, .9, 1.0) * s, Color = BAT, Parent = model })
	local wr = part({ Name = "CalBatWing", Class = "WedgePart", Size = V3(.05, .9, 1.0) * s, Color = BAT, Parent = model })
	local eyes = part({ Name = "CalBatEyes", Size = V3(.22, .05, .05) * s, Color = Color3.fromRGB(255, 110, 60), Material = Enum.Material.Neon, Parent = model })
	return { Body = body, L = wl, R = wr, Eyes = eyes, S = s }
end

local function clearBats()
	for _, f in ipairs(S.Bats) do
		f.Model:Destroy()
	end
	S.Bats = {}
	S.BatRoostKey = ""
end

-- the nearest roosts get the plan's bats (by day only a share of them fly)
local function planBats()
	local want = S.Plan and S.Plan.Bats or 0
	want = math.floor(want * (Cfg.Bats.Night + (1 - Cfg.Bats.Night) * S.Dark) + .5)
	if want <= 0 or #S.Roosts == 0 or not S.OnIsland then
		if #S.Bats > 0 then
			clearBats()
		end
		return
	end
	local ranked = {}
	for _, a in ipairs(S.Roosts) do
		local par = a.Parent
		if par and par:IsA("BasePart") then
			local pos = (par.CFrame * a.CFrame).Position
			local d = (pos - S.CamPos).Magnitude
			if d < Cfg.Bats.Range then
				table.insert(ranked, { Pos = pos, D = d })
			end
		end
	end
	table.sort(ranked, function(a, b)
		return a.D < b.D
	end)
	local roosts = math.min(#ranked, 3)
	local key = tostring(want)
	for i = 1, roosts do
		key ..= string.format("|%d|%d", math.floor(ranked[i].Pos.X), math.floor(ranked[i].Pos.Z))
	end
	if key == S.BatRoostKey then
		return
	end
	clearBats()
	S.BatRoostKey = key
	if roosts == 0 then
		return
	end
	for i = 1, roosts do
		local n = math.max(1, math.floor(want / roosts + (i <= want % roosts and 1 or 0)))
		local model = Instance.new("Model")
		model.Name = "CalendarBats"
		model.Parent = fxFolder()
		local flock = { Model = model, Center = ranked[i].Pos, Bats = {}, Seed = i * 7 }
		for b = 1, n do
			local bat = makeBat(model, .8 + .4 * hash("bs" .. b .. i))
			bat.I = b + flock.Seed
			table.insert(flock.Bats, bat)
		end
		table.insert(S.Bats, flock)
	end
end

local function updateBats(t: number)
	for _, flock in ipairs(S.Bats) do
		local parts, cfs = {}, {}
		local n = #flock.Bats
		for _, bat in ipairs(flock.Bats) do
			local i, s = bat.I, bat.S
			local p0 = Pure.BatPos(flock.Center, i, n, t, Cfg)
			local p1 = Pure.BatPos(flock.Center, i, n, t + .05, Cfg)
			local base = (p1 - p0).Magnitude > 1e-4 and CFrame.lookAt(p0, p1) or CF(p0)
			local w = Pure.Wing(t, i)
			table.insert(parts, bat.Body)
			table.insert(cfs, base)
			table.insert(parts, bat.L)
			table.insert(cfs, base * CF(-.2 * s, 0, 0) * CFrame.Angles(0, 0, -w) * CF(-.45 * s, 0, .1 * s) * CFrame.Angles(0, 0, math.pi / 2))
			table.insert(parts, bat.R)
			table.insert(cfs, base * CF(.2 * s, 0, 0) * CFrame.Angles(0, 0, w) * CF(.45 * s, 0, .1 * s) * CFrame.Angles(0, 0, -math.pi / 2))
			table.insert(parts, bat.Eyes)
			table.insert(cfs, base * CF(0, .06 * s, -.48 * s))
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- DISTANT GHOSTS
---------------------------------------------------------------------------------------------------------------------
local GHOST = rgb(Cfg.Ghosts.Color)
local INK = Color3.fromRGB(22, 14, 34)

local function makeGhost(center: Vector3, radius: number, height: number)
	local model = Instance.new("Model")
	model.Name = "CalendarGhost"
	model.Parent = fxFolder()
	local g = { Model = model, Center = center, R = radius, H = height, Seed = rand(), T0 = os.clock(), Parts = {}, Rest = {}, Base = {} }
	g.Life = Cfg.Ghosts.Life[1] + (Cfg.Ghosts.Life[2] - Cfg.Ghosts.Life[1]) * rand()
	local s = 1.2 + rand() * .5 -- read from far away
	local function add(p: BasePart, rest: CFrame, base: number)
		table.insert(g.Parts, p)
		table.insert(g.Rest, rest)
		table.insert(g.Base, base)
	end
	add(part({ Name = "GhostSheet", Size = V3(2.6, 3.4, 2.6) * s, Color = GHOST, Material = Enum.Material.Neon, Mesh = true, Transparency = 1, Parent = model }), CF(0, .2 * s, 0), .45)
	for k = 1, 4 do
		local a = (k - 1) / 4 * TAU + .4
		add(part({ Name = "GhostHem", Size = V3(1, 1, 1) * s, Shape = Enum.PartType.Ball, Color = GHOST, Material = Enum.Material.Neon, Transparency = 1, Parent = model }),
			CF(math.cos(a) * 1.0 * s, -1.4 * s, math.sin(a) * 1.0 * s), .45)
	end
	for sx = -1, 1, 2 do
		add(part({ Name = "GhostEye", Size = V3(.4, .6, .2) * s, Color = INK, Mesh = true, Transparency = 1, Parent = model }), CF(sx * .44 * s, .66 * s, -1.18 * s), 0)
	end
	table.insert(S.Ghosts, g)
end

local function updateGhosts(now: number)
	for i = #S.Ghosts, 1, -1 do
		local g = S.Ghosts[i]
		local u = (now - g.T0) / g.Life
		if u >= 1 then
			g.Model:Destroy()
			table.remove(S.Ghosts, i)
		else
			local alpha = Pure.Fade(u)
			local p = Pure.GhostPos(g.Center, g.R, g.H, u, g.Seed)
			local p2 = Pure.GhostPos(g.Center, g.R, g.H, math.min(1, u + .01), g.Seed)
			local dir = V3(p2.X - p.X, 0, p2.Z - p.Z)
			local toCam = V3(S.CamPos.X - p.X, 0, S.CamPos.Z - p.Z)
			if dir.Magnitude > 1e-4 and toCam.Magnitude > 1e-4 then
				dir = dir.Unit * .4 + toCam.Unit * .6 -- drifting, but looking at you
			end
			local base = dir.Magnitude > 1e-4 and CFrame.lookAt(p, p + dir) or CF(p)
			base = base * CFrame.Angles(.1, 0, math.sin(now * 1.1 + g.Seed * 9) * .08)
			local cfs = {}
			for j, rest in ipairs(g.Rest) do
				cfs[j] = base * rest
				g.Parts[j].Transparency = 1 - (1 - g.Base[j]) * alpha
			end
			workspace:BulkMoveTo(g.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

local function clearGhosts()
	for _, g in ipairs(S.Ghosts) do
		g.Model:Destroy()
	end
	S.Ghosts = {}
end

local function spawnGhosts(now: number)
	local want = S.Plan and S.Plan.Ghosts or 0
	-- night presences: by day the rate drops to Ghosts.Night
	local nightK = S.Dark >= .5 and 1 or Cfg.Ghosts.Night * S.Dark * 2
	if want <= 0 or #S.GhostMarks == 0 or #S.Ghosts >= want or now < S.NextGhost or not S.OnIsland or S.YardW > .2 then
		return
	end
	local every = Cfg.Ghosts.Every
	S.NextGhost = now + (every[1] + (every[2] - every[1]) * rand()) / math.max(.15, nightK)
	if rand() > nightK then
		return
	end
	local cands = {}
	for _, a in ipairs(S.GhostMarks) do
		local par = a.Parent
		if par and par:IsA("BasePart") then
			local pos = (par.CFrame * a.CFrame).Position
			local d = (pos - S.CamPos).Magnitude
			if d >= Cfg.Ghosts.Range[1] and d <= Cfg.Ghosts.Range[2] then
				table.insert(cands, { Pos = pos, R = tonumber(a:GetAttribute("Radius")) or 14, H = tonumber(a:GetAttribute("Height")) or 4 })
			end
		end
	end
	if #cands > 0 then
		local c = cands[math.floor(rand() * #cands) + 1]
		makeGhost(c.Pos, c.R, c.H)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- WISPS, LEAVES, MIST around the camera
---------------------------------------------------------------------------------------------------------------------
local function ground(): Vector3
	local char = S.Player and S.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local p = root and (root :: BasePart).CFrame.Position or S.CamPos
	return V3(p.X, math.max(p.Y - 3, -4), p.Z)
end

local function clearWisps()
	if S.Wisps then
		S.Wisps.Model:Destroy()
		S.Wisps = nil
	end
end

local function planWisps()
	local n = (S.OnIsland and S.YardW < .3) and (S.Plan and S.Plan.Wisps or 0) or 0
	if S.Wisps and S.Wisps.N == n then
		return
	end
	clearWisps()
	if n <= 0 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "CalendarWisps"
	model.Parent = fxFolder()
	local w = { Model = model, N = n, List = {} }
	for i = 1, n do
		local col = rgb(Cfg.Wisps.Colors[(i - 1) % #Cfg.Wisps.Colors + 1])
		local core = part({ Name = "WispCore", Size = V3(.45, .45, .45), Shape = Enum.PartType.Ball, Color = col, Material = Enum.Material.Neon, Parent = model })
		local halo = part({ Name = "WispHalo", Size = V3(1.3, 1.3, 1.3), Shape = Enum.PartType.Ball, Color = col, Material = Enum.Material.Neon, Transparency = .85, Parent = model })
		local a = hash("wa" .. i) * TAU
		local r = Cfg.Wisps.Radius[1] + (Cfg.Wisps.Radius[2] - Cfg.Wisps.Radius[1]) * hash("wr" .. i)
		table.insert(w.List, { Core = core, Halo = halo, A = a, R = r, Anchor = ground() + V3(math.cos(a) * r, 0, math.sin(a) * r) })
	end
	S.Wisps = w
end

local function updateWisps(t: number)
	local w = S.Wisps
	local calm = shared().ReducedMotion()
	local parts, cfs = {}, {}
	local g = ground()
	local glow = .25 + .75 * S.Dark
	for i, e in ipairs(w.List) do
		-- an anchor that stays in the world and re-seats when the player walks away
		if V3(e.Anchor.X - g.X, 0, e.Anchor.Z - g.Z).Magnitude > Cfg.Wisps.Radius[2] * 1.6 then
			local a = rand() * TAU
			e.Anchor = g + V3(math.cos(a) * e.R, 0, math.sin(a) * e.R)
		end
		local hh = Cfg.Wisps.Height[1] + (Cfg.Wisps.Height[2] - Cfg.Wisps.Height[1]) * (.5 + .5 * math.sin(t * .5 + i))
		local drift = calm and .4 or 2.2
		local p = V3(e.Anchor.X + math.sin(t * .37 + i * 2.1) * drift, g.Y + 3 + hh, e.Anchor.Z + math.cos(t * .31 + i * 1.3) * drift)
		table.insert(parts, e.Core)
		table.insert(cfs, CF(p))
		table.insert(parts, e.Halo)
		table.insert(cfs, CF(p))
		local pulse = .5 + .5 * math.sin(t * 2.2 + i * 1.7)
		e.Core.Transparency = 1 - glow * (.55 + .45 * pulse)
		e.Halo.Transparency = 1 - glow * .15 * (.5 + pulse)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function clearLeaves()
	if S.Leaves then
		S.Leaves.Model:Destroy()
		S.Leaves = nil
	end
end

local function planLeaves()
	local n = (S.OnIsland and S.YardW < .3 and not shared().ReducedMotion()) and (S.Plan and S.Plan.Leaves or 0) or 0
	if S.Leaves and S.Leaves.N == n then
		return
	end
	clearLeaves()
	if n <= 0 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "CalendarLeaves"
	model.Parent = fxFolder()
	local L = { Model = model, N = n, List = {} }
	for i = 1, n do
		local leaf = part({ Name = "DryLeafFX", Size = V3(.55, .05, .4), Color = rgb(Cfg.Leaves.Colors[(i - 1) % #Cfg.Leaves.Colors + 1]), Parent = model })
		table.insert(L.List, { Part = leaf, T0 = os.clock() - rand() * 6, Dur = 5 + rand() * 3, Start = nil :: Vector3?, Seed = rand() * 10 })
	end
	S.Leaves = L
end

local function updateLeaves(now: number)
	local L = S.Leaves
	local parts, cfs = {}, {}
	local g = ground()
	for _, e in ipairs(L.List) do
		local u = (now - e.T0) / e.Dur
		if u >= 1 or not e.Start then
			local a, r = rand() * TAU, rand() * Cfg.Leaves.Radius
			e.Start = g + V3(math.cos(a) * r, 10 + rand() * 5, math.sin(a) * r)
			e.T0, e.Dur, u = now, 5 + rand() * 3, 0
		end
		local s = e.Start :: Vector3
		local fall = (s.Y - g.Y - .2) * u
		local p = s + V3(math.sin(now * 1.7 + e.Seed) * 1.6, -fall, math.cos(now * 1.3 + e.Seed) * 1.2)
		table.insert(parts, e.Part)
		table.insert(cfs, CF(p) * CFrame.Angles(math.sin(now * 3 + e.Seed) * .9, now * 1.5 + e.Seed, math.cos(now * 2.6 + e.Seed) * .8))
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function stopMist(fast: boolean?)
	local m = S.Mist
	if not m then
		return
	end
	S.Mist = nil
	for _, e in ipairs(m.Emitters) do
		e.E.Rate = 0
	end
	if fast then
		m.Model:Destroy()
	else
		task.delay(10, function()
			m.Model:Destroy()
		end)
	end
end

local function planMist()
	local plan = S.Plan
	local n = (S.OnIsland and S.YardW < .2 and plan) and plan.Mist or 0
	if n <= 0 then
		stopMist()
		return
	end
	if S.Mist and S.Mist.N == n then
		for _, e in ipairs(S.Mist.Emitters) do
			e.E.Rate = plan.MistRate
		end
		return
	end
	stopMist(true)
	local model = Instance.new("Model")
	model.Name = "CalendarMist"
	model.Parent = fxFolder()
	local tex = S.Ctx.FX and S.Ctx.FX.Textures and S.Ctx.FX.Textures.Smoke or "rbxasset://textures/particles/smoke_main.dds"
	local col = rgb(Cfg.Mist.Color)
	local mist = { Model = model, N = n, Emitters = {}, NextMove = 0 }
	local g = ground()
	for i = 1, n do
		local a = (i / n) * TAU + rand() * .7
		local r = Cfg.Mist.Radius[1] + rand() * (Cfg.Mist.Radius[2] - Cfg.Mist.Radius[1])
		local p = part({ Name = "MistBank", Size = V3(26, 1, 26), Transparency = 1, CFrame = CF(g + V3(math.cos(a) * r, .5, math.sin(a) * r)), Parent = model })
		local e = Instance.new("ParticleEmitter")
		e.Texture = tex
		e.Color = ColorSequence.new(col, col:Lerp(Color3.fromRGB(120, 110, 160), .4))
		e.LightEmission = .05
		e.LightInfluence = .85
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(.5, 12), NumberSequenceKeypoint.new(1, 16) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.3, .86), NumberSequenceKeypoint.new(.7, .89),
			NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(7, 11)
		e.Speed = NumberRange.new(.3, 1)
		e.SpreadAngle = Vector2.new(180, 10)
		e.Acceleration = V3(.2, .04, 0)
		e.Drag = .4
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-8, 8)
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		e.Rate = plan.MistRate
		e.Parent = p
		table.insert(mist.Emitters, { Part = p, E = e })
	end
	S.Mist = mist
end

local function moveMist(now: number)
	local m = S.Mist
	if not m or now < m.NextMove then
		return
	end
	m.NextMove = now + 2.5
	local g = ground()
	for _, e in ipairs(m.Emitters) do
		local p = e.Part.CFrame.Position
		if V3(p.X - g.X, 0, p.Z - g.Z).Magnitude > Cfg.Mist.Radius[2] * 1.3 then
			local a = rand() * TAU
			local r = Cfg.Mist.Radius[1] + rand() * (Cfg.Mist.Radius[2] - Cfg.Mist.Radius[1])
			e.Part.CFrame = CF(g + V3(math.cos(a) * r, .5, math.sin(a) * r))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- THE MOON (halo + eclipse around BloodMoonFX's Buried Moon)
---------------------------------------------------------------------------------------------------------------------
local function clearMoon()
	if S.Moon then
		S.Moon.Model:Destroy()
		S.Moon = nil
	end
end

local function buildMoon()
	local model = Instance.new("Model")
	model.Name = "CalendarMoon"
	model.Parent = fxFolder()
	local mc = Cfg.Moon
	local mo = {
		Model = model,
		Halo1 = part({ Name = "MoonHalo", Size = V3(2, 2, 2), Shape = Enum.PartType.Ball, Color = rgb(mc.HaloColor), Material = Enum.Material.Neon, Transparency = 1, Parent = model }),
		Halo2 = part({ Name = "MoonHalo", Size = V3(2, 2, 2), Shape = Enum.PartType.Ball, Color = rgb(mc.HaloColor), Material = Enum.Material.Neon, Transparency = 1, Parent = model }),
		Disc = part({ Name = "MoonEclipse", Class = "Part", Shape = Enum.PartType.Cylinder, Size = V3(.2, 2, 2), Color = rgb(mc.EclipseColor), Transparency = 1, Parent = model }),
		Ring = part({ Name = "MoonCorona", Class = "Part", Shape = Enum.PartType.Cylinder, Size = V3(.1, 2, 2), Color = rgb(mc.RingColor), Material = Enum.Material.Neon, Transparency = 1, Parent = model }),
	}
	S.Moon = mo
end

local function updateMoon()
	local plan = S.Plan
	local halo, ecl = plan and plan.Halo or 0, plan and plan.Eclipse or 0
	local fx = S.Ctx.FX and S.Ctx.FX.Folder()
	local moonModel = fx and fx:FindFirstChild("HalloweenMoon")
	local core = moonModel and moonModel:FindFirstChild("MoonCore")
	local L = lightingModule()
	local W = L and L.Weights and L.Weights() or nil
	local vis = W and W.MoonVis or 0
	local blood = W and W.Blood or 0
	local k = vis * math.clamp(1 - blood * 3, 0, 1)
	if (halo <= 0 and ecl <= 0) or not (core and core:IsA("BasePart")) or k < .01 then
		if S.Moon then
			clearMoon()
		end
		return
	end
	if not S.Moon then
		buildMoon()
	end
	local mo = S.Moon
	local cf = core.CFrame -- looks at the camera: local -Z = toward the camera
	local r = core.Size.X / 2
	local hs = Cfg.Moon.HaloScale
	local s1, s2 = r * 2 * (1 + (hs[1] - 1) * halo), r * 2 * (1 + (hs[2] - 1) * halo)
	local face = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) -> local Z
	local slide = (1 - ecl) * 2.1 * r -- the eclipse disc slides in from the upper right
	local parts = { mo.Halo1, mo.Halo2, mo.Disc, mo.Ring }
	local cfs = {
		cf * CF(0, 0, r * 1.4),
		cf * CF(0, 0, r * 1.8),
		cf * CF(slide * .8, slide * .6, -r * 1.06) * face,
		cf * CF(0, 0, r * .3) * face,
	}
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if math.abs(mo.Halo1.Size.X - s1) > s1 * .01 then
		mo.Halo1.Size = V3(s1, s1, s1)
		mo.Halo2.Size = V3(s2, s2, s2)
		mo.Disc.Size = V3(r * .05, r * 2.04, r * 2.04)
		mo.Ring.Size = V3(r * .04, r * 2.5, r * 2.5)
	end
	mo.Halo1.Transparency = 1 - .12 * halo * k
	mo.Halo2.Transparency = 1 - .06 * halo * k
	mo.Disc.Transparency = ecl > 0 and (1 - .96 * k) or 1
	mo.Ring.Transparency = (ecl > .5 and plan.Corona) and (1 - .55 * (ecl - .5) * 2 * k) or 1
end

---------------------------------------------------------------------------------------------------------------------
-- SOUNDS
---------------------------------------------------------------------------------------------------------------------
local function audio(): any
	return S.Ctx and S.Ctx.Audio
end

local function updateSounds(now: number, dt: number)
	local A = audio()
	if not A or not S.OnIsland or S.YardW > .3 then
		return
	end
	-- strange night sounds somewhere out in the dark
	local rate = (S.Plan and S.Plan.Sounds or 0) * (Cfg.Sounds.Night + (1 - Cfg.Sounds.Night) * S.Dark)
	if rate > 0 and now >= S.NextSound and rand() < rate / 60 * dt then
		S.NextSound = now + 4
		local cues = Cfg.Sounds.Cues
		local cue = cues[math.floor(rand() * #cues) + 1]
		local a = rand() * TAU
		local d = Cfg.Sounds.Distance[1] + rand() * (Cfg.Sounds.Distance[2] - Cfg.Sounds.Distance[1])
		pcall(A.Play, cue, S.CamPos + V3(math.cos(a) * d, 4, math.sin(a) * d), { Volume = Cfg.Sounds.Volume })
	end
	-- whispers from the face trees near you (else from the dark right beside you, less often)
	local wr = S.Plan and S.Plan.Whispers or 0
	if wr > 0 and now >= S.NextWhisper and rand() < wr / 60 * dt then
		S.NextWhisper = now + 5
		local best, bestD = nil, Cfg.Whispers.Range
		for m in pairs(S.FaceTrees) do
			local ok, piv = pcall(function()
				return (m :: Model):GetPivot().Position
			end)
			if ok then
				local d = (piv - S.CamPos).Magnitude
				if d < bestD then
					best, bestD = piv, d
				end
			end
		end
		if best then
			pcall(A.Play, "Whisper", best + V3(0, 4, 0), { Volume = Cfg.Whispers.Volume })
		elseif rand() < .4 then
			local a = rand() * TAU
			pcall(A.Play, "Whisper", S.CamPos + V3(math.cos(a) * 9, 0, math.sin(a) * 9), { Volume = Cfg.Whispers.Volume * .8 })
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Visibility of the stage folders (the map-decor toggle)
---------------------------------------------------------------------------------------------------------------------
local hiddenLights: { [Light]: RBXScriptConnection } = {}
local function applyHidden(inst: Instance, visible: boolean)
	local MML = mainMapLayer()
	if MML and MML.ApplyLayer then
		MML.ApplyLayer(inst, visible) -- same rules as the Chapter I layer (lights held at 0 while hidden)
		return
	end
	local list = { inst }
	for _, d in ipairs(inst:GetDescendants()) do
		table.insert(list, d)
	end
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = visible and 0 or 1
		elseif d:IsA("Light") then
			local base = d:GetAttribute("HwBaseBrightness")
			if visible then
				local c = hiddenLights[d]
				if c then
					c:Disconnect()
					hiddenLights[d] = nil
				end
				if type(base) == "number" then
					d.Brightness = base
				end
			else
				d.Brightness = 0
				if not hiddenLights[d] then
					hiddenLights[d] = d:GetPropertyChangedSignal("Brightness"):Connect(function()
						if d.Brightness ~= 0 then
							d.Brightness = 0
						end
					end)
				end
			end
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			(d :: any).Enabled = visible
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------------------------------------------
local function clearCreatures()
	clearBats()
	clearGhosts()
	clearWisps()
	clearLeaves()
	stopMist(true)
	clearMoon()
end

-- the grass back to its originals; during a world event (whose end restores the colours it saved = ours) it waits for
-- the event to finish first
local function restoreGrass()
	S.RestoreToken += 1
	if not worldEventBusy() then
		applyGrass(false, 0)
		return
	end
	local token = S.RestoreToken
	task.spawn(function()
		while worldEventBusy() and S.RestoreToken == token do
			task.wait(1)
		end
		task.wait(Cfg.Grass.AfterEvent)
		if S.RestoreToken == token and not S.Active then
			applyGrass(false, 0)
		end
	end)
end

-- everything back exactly (grass, windows, eyes, sway, flicker, lamps, light layer, creatures)
local function deactivate()
	if not S.Active then
		return
	end
	S.Active = false
	restoreGrass()
	restoreAllWindows()
	closeAllEyes()
	restoreSway()
	restoreFlicker()
	updateLamps(false)
	updateLayer(false)
	clearCreatures()
end

local function readStage(): number
	local f = S.StateFolder
	local v = f and f:GetAttribute("Stage")
	if type(v) == "number" then
		local en = f and f:GetAttribute("Enabled")
		if en == false then
			return 0
		end
		return math.clamp(math.floor(v), 0, Cfg.MaxStage)
	end
	-- no service state (yet): the same pure date rule the server uses
	local ok, s = pcall(Rules.Stage, shared().Now(), Cfg)
	return ok and s or 0
end

local function readVisible(): boolean
	local MML = mainMapLayer()
	if MML and MML.IsVisible then
		return MML.IsVisible() ~= false
	end
	return S.Player == nil or S.Player:GetAttribute("HwMapDecor") ~= false
end

local function banner(stage: number)
	local Bus = S.Ctx.Bus
	if not Bus then
		return
	end
	local ru = russian()
	local label = Rules.Text(stage, Cfg, "Label", ru) or ""
	local name = Rules.Text(stage, Cfg, "Name", ru) or ""
	local toast = Rules.Text(stage, Cfg, "Toast", ru) or ""
	pcall(Bus.Fire, "Banner", { Title = label .. " · " .. name, Subtitle = toast, Color = Color3.fromRGB(255, 140, 50), Style = "Event",
		Seconds = 5, NoTranslate = true })
	local A = audio()
	if A then
		pcall(A.Play, "BellToll", nil, { Volume = .35 })
	end
end

-- re-read the switches / stage / visibility and (de)activate
function M.Refresh()
	if not S.Started then
		return
	end
	local Shared = shared()
	S.Enabled = Shared.CalendarEnabled()
	local stage = S.Enabled and readStage() or 0
	local visible = readVisible()
	if stage ~= S.Stage then
		local up = S.KnownStage ~= nil and stage > S.KnownStage
		S.Stage = stage
		S.From = S.Cur
		S.Target = Rules.StageParams(stage, Cfg)
		S.GlideT0 = os.clock()
		S.GlideDur = S.KnownStage == nil and 0 or 4
		S.Settled = false
		S.PlanDirty = true
		-- the grass follows once the numbers have glided over (newly dead parts fade in over Grass.Glide)
		S.NextGrass = S.GlideT0 + S.GlideDur
		if up and visible and S.Enabled then
			task.spawn(banner, stage)
		end
	end
	S.KnownStage = stage
	if S.Root and visible ~= S.Visible then
		applyHidden(S.Root, visible)
	end
	S.Visible = visible
	local want = S.Enabled and stage > 0 and visible
	if not want then
		deactivate()
	else
		if not S.Active then
			S.Active = true
			S.RestoreToken += 1 -- a pending post-event restore must not undo the new tint
			S.NextGrass = 0
			S.GrassInstant = true -- joining / switching the decor back on: no slow fade
			S.PlanDirty = true
		end
	end
end

local function replan()
	local Shared = shared()
	S.Plan = Pure.Plan(S.Cur, Shared.Quality(), Cfg, Shared.Config)
	S.PlanDirty = false
end

-- 2 Hz: sensing, planning, lighting, lamps, grass, spawners
local function slowTick(now: number)
	local Shared = shared()
	-- glide the parameters toward the stage's numbers (a few seconds after a stage change)
	local u = S.GlideDur > 0 and math.clamp((now - S.GlideT0) / S.GlideDur, 0, 1) or 1
	if not S.Settled then
		S.Cur = Rules.Blend(S.From, S.Target, u)
		S.PlanDirty = true
		S.Settled = u >= 1
	end
	S.Dark = math.max(Pure.Darkness(LightingService:GetAttribute("DayFactor"), LightingService:GetAttribute("IsNight"), LightingService.ClockTime),
		(function()
			local ok, b = pcall(Shared.BloodMoonAlpha, Shared.Now())
			return ok and type(b) == "number" and b or 0
		end)())
	local L = lightingModule()
	local W = L and L.Weights and L.Weights() or nil
	S.Blood = W and W.Blood or 0
	S.YardW = (S.Ctx.Layout and S.Ctx.Layout.Weight) and S.Ctx.Layout.Weight(S.CamPos, 40) or 0
	S.OnIsland = Pure.OnIsland(S.CamPos)
	local busy = worldEventBusy()
	if S.WorldEvent and not busy then
		S.GrassAfterEvent = now + Cfg.Grass.AfterEvent -- its 3 s colour restore first, then ours
	end
	S.WorldEvent = busy
	if S.PlanDirty then
		replan()
	end
	pruneRoot()
	updateLayer(true)
	updateLamps(true)
	if not S.WorldEvent and (now >= S.NextGrass or (S.GrassAfterEvent > 0 and now >= S.GrassAfterEvent)) then
		S.GrassAfterEvent = 0
		S.NextGrass = now + Cfg.Grass.Reapply
		applyGrass(true, S.GrassInstant and 0 or Cfg.Grass.Glide)
		S.GrassInstant = false
	end
	planBats()
	planWisps()
	planLeaves()
	planMist()
	spawnGhosts(now)
end

local function step(dt: number)
	if not S.Active then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	S.CamPos = cam.CFrame.Position
	local now = os.clock()
	if now >= S.NextSlow then
		S.NextSlow = now + .5
		slowTick(now)
	end
	if not S.OnIsland then
		-- off the main map (the Underyard, the Void): nothing animates, nothing near the camera
		if #S.Bats > 0 or S.Wisps or S.Leaves or S.Mist then
			clearCreatures()
		end
		return
	end
	updateEyes(now, dt)
	-- branches and ghost dogs move slowly: 30 Hz is plenty (half the BulkMoveTo work at 60 fps)
	S.SwayAcc += dt
	if S.SwayAcc >= 1 / 30 then
		S.SwayAcc = 0
		updateSway(now)
		updateGhostDogs(now)
	end
	flicker(now)
	updateWindows(now, dt)
	if #S.Bats > 0 then
		updateBats(now)
	end
	updateGhosts(now)
	if S.Wisps then
		updateWisps(now)
	end
	if S.Leaves then
		updateLeaves(now)
	end
	moveMist(now)
	updateSounds(now, dt)
end

function M.Stage(): number
	return S.Stage
end

function M.Params(): { [string]: number }
	return S.Cur
end

function M.Active(): boolean
	return S.Active
end

function M.Stop()
	deactivate()
	S.Running = false
	pcall(function()
		RunService:UnbindFromRenderStep("DOGROTS_CalendarMoon")
	end)
	for _, c in ipairs(S.Conns) do
		c:Disconnect()
	end
	S.Conns = {}
	for l, c in pairs(hiddenLights) do
		c:Disconnect()
		hiddenLights[l] = nil
	end
	if S.Root and not S.Visible then
		applyHidden(S.Root, true)
	end
	if S.Folder then
		S.Folder:Destroy()
		S.Folder = nil
	end
	S.Started = false
end

local function bindRoot(root: Instance)
	S.Root = root
	scanRoot()
	if not S.Visible then
		applyHidden(root, false)
	end
	table.insert(S.Conns, root.DescendantAdded:Connect(function(d)
		trackRoot(d)
		if not S.Visible then
			applyHidden(d, false)
		elseif d:IsA("BasePart") and d:GetAttribute("CalEyes") == true then
			local row = S.Eyes[eyeGroupOf(d)]
			if row then
				d.Transparency = row.Open and 0 or 1
			end
		end
	end))
end

function M.Start(ctx)
	if S.Started then
		return
	end
	S.Started = true
	S.Ctx = ctx
	local Shared = ctx.Shared
	local player = ctx.Player or Players.LocalPlayer
	S.Player = player
	S.Running = true
	-- switches, stage, visibility
	local st = HalloweenFolder:FindFirstChild("State") or HalloweenFolder:WaitForChild("State", 30)
	if st then
		for _, key in ipairs({ "Enabled", "HalloweenCalendarEnabled" }) do
			table.insert(S.Conns, st:GetAttributeChangedSignal(key):Connect(function()
				task.defer(M.Refresh)
			end))
		end
		local function bindState(f: Instance)
			S.StateFolder = f
			for _, key in ipairs({ "Stage", "Enabled" }) do
				table.insert(S.Conns, f:GetAttributeChangedSignal(key):Connect(function()
					task.defer(M.Refresh)
				end))
			end
		end
		local f = st:FindFirstChild(Cfg.StateName)
		if f then
			bindState(f)
		else
			table.insert(S.Conns, st.ChildAdded:Connect(function(c)
				if c.Name == Cfg.StateName and not S.StateFolder then
					bindState(c)
					task.defer(M.Refresh)
				end
			end))
		end
	end
	table.insert(S.Conns, player:GetAttributeChangedSignal("HwMapDecor"):Connect(function()
		task.defer(M.Refresh)
	end))
	for _, a in ipairs({ "WorldEventFX", "LowFX", "ReducedMotion" }) do
		table.insert(S.Conns, player:GetAttributeChangedSignal(a):Connect(function()
			S.PlanDirty = true
		end))
	end
	if ctx.Bus then
		ctx.Bus.On("MapDecor", function()
			if S.Started then
				task.defer(M.Refresh)
			end
		end)
	end
	table.insert(S.Conns, player:GetAttributeChangedSignal("DOGROTS_Language"):Connect(function()
		task.delay(.1, function()
			if S.Root then
				for _, d in ipairs(S.Root:GetDescendants()) do
					if d:IsA("TextLabel") then
						trackRoot(d)
					end
				end
			end
		end)
	end))
	-- the island (grass, windows, lamps) and the live stage root (Default streaming: parts stream in)
	S.District = workspace:WaitForChild("DOGROTS_District", 60)
	if S.District then
		scanGrass()
		scanWindows()
		table.insert(S.Conns, S.District.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and d:GetAttribute("EventTintSurface") == true then
				trackGrass(d)
				if S.Active and S.GrassByPart[d] then
					S.NextGrass = math.min(S.NextGrass, os.clock() + 1) -- a streamed-in copy arrives green: tint it soon
				end
			end
		end))
		local root = S.District:FindFirstChild(Cfg.Root)
		if root then
			bindRoot(root)
		else
			table.insert(S.Conns, S.District.ChildAdded:Connect(function(c)
				if c.Name == Cfg.Root and not S.Root then
					bindRoot(c)
				end
			end))
		end
	end
	S.Visible = readVisible()
	if S.Root and not S.Visible then
		applyHidden(S.Root, false)
	end
	M.Refresh()
	table.insert(S.Conns, RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not M.Warned then
			M.Warned = true
			warn("Halloween calendar FX step failed: " .. tostring(err))
		end
	end))
	-- the moon pieces follow BloodMoonFX's moon, which moves at Camera+3: we go right after it
	RunService:BindToRenderStep("DOGROTS_CalendarMoon", Enum.RenderPriority.Camera.Value + 4, function()
		if S.Active and S.OnIsland then
			local ok = pcall(updateMoon)
			if not ok then
				clearMoon()
			end
		elseif S.Moon then
			clearMoon()
		end
	end)
	-- the event can be switched off (and on again, Studio) on a live server: put everything back / start over
	if st and not M.Listening then
		M.Listening = true
		st:GetAttributeChangedSignal("Enabled"):Connect(function()
			if not Shared.Enabled() then
				if S.Started then
					M.Stop()
				end
			elseif not S.Started then
				task.spawn(M.Start, ctx)
			end
		end)
	end
end

return M
