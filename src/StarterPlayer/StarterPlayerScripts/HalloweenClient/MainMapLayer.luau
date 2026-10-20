-- NIGHT OF THE BURIED MOON — main-map Halloween layer, client side (StarterPlayerScripts.HalloweenClient.MainMapLayer, WP3).
-- * Bat flocks circling the landmarks (THE DOG's witch hat, the welcome arch, the DogDex museum arch, the nuclear tower
--   crown, DOG-O-MATIC): part-built bats with two-segment flapping wings, one BulkMoveTo per frame; only the nearest
--   flocks fly (budget from Shared.Budget("Bats") / Quality), more of them at night.
-- * Rare ghosts drifting across the main map at night (Lighting.DayFactor / IsNight from the LightingController patch,
--   ClockTime fallback; a Blood Moon counts as night) — never inside THE DEAD YARD (its own AmbientFX owns that).
-- * Rare low mist banks rolling over the main map at night (self-managed emitters, budgeted, never in the yard).
-- * Floating candle wisps around the spawn pad; gentle Brightness flicker of the layer's lights (never Enabled: WDQ).
-- * Per-player toggle: MainMapLayer.SetVisible(on) and player attribute HwMapDecor == false hide
--   Workspace.DOGROTS_District.39_HalloweenLayer locally (LocalTransparencyModifier = 1, its lights' Brightness 0, its
--   SurfaceGuis off — streamed-in parts too) and put every recoloured lamp back to its Halloween_OriginalColor; turning
--   it on re-applies Halloween_EventColor. Bus "MapDecor" {Visible} on every change. With Config.MainMapDecorations =
--   false (the server destroys the layer) the lamps are put back locally and nothing runs.
-- * Russian lettering: the layer's SurfaceGui labels are NoTranslate (set by the builder) and localized here (M.RU).
-- API: Start(ctx), SetVisible(on), IsVisible(), Stop(); ApplyLayer / ApplyLamps / FindLamps / Localize (test hooks too).
-- All client parts live in workspace.DOGROTS_HalloweenFX.MainMapLayer (SelfManagedFX). Pure helpers: MainMapLayer.Pure.
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local M = {}
local Pure = {}
M.Pure = Pure

local V3 = Vector3.new
local CF = CFrame.new
local TAU = math.pi * 2

M.Spawn = V3(0, 0.4, 377)
M.Landmarks = {
	{ Name = "TheDog", Center = V3(0, 116, -192), Radius = 44, Height = 12 },
	{ Name = "EntryArch", Center = V3(0, 31, 401), Radius = 18, Height = 3.5 },
	{ Name = "Museum", Center = V3(-72, 76, 481), Radius = 25, Height = 6 },
	{ Name = "Tower", Center = V3(128, 131, 477), Radius = 30, Height = 7 },
	{ Name = "DogOMatic", Center = V3(-154, 97, 630), Radius = 26, Height = 6 },
}
M.Island = { X0 = -235, X1 = 235, Z0 = -275, Z1 = 785, YMin = -12 } -- the main map (not the Void, not a mine)
M.FlockRange = 470 -- a flock flies while the camera is closer than this
M.WispRange = 240

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (exercised by tools/hw_test_wp3.luau)
------------------------------------------------------------------------------------------------------------------
local function hash(i: number, k: number): number
	return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1
end
Pure.Hash = hash

-- night from the server's LightingController attributes (IsNight / DayFactor), else from the clock (same curve)
function Pure.DayFactor(dayFactor: any, isNight: any, clock: number?): number
	if type(dayFactor) == "number" then
		return math.clamp(dayFactor, 0, 1)
	end
	if type(isNight) == "boolean" then
		return isNight and 0 or 1
	end
	local c = (clock or 14) % 24
	return math.clamp((math.cos((c - 13) * math.pi / 12) + .2) * 1.2, 0, 1)
end

-- 0 (day) .. 1 (full night); a Blood Moon makes it night everywhere
function Pure.Darkness(dayFactor: any, isNight: any, clock: number?, blood: number?): number
	return math.max(1 - Pure.DayFactor(dayFactor, isNight, clock), math.clamp(blood or 0, 0, 1))
end

function Pure.IsNight(darkness: number): boolean
	return darkness >= .8
end

-- the decor is visible unless the event layer is off, an explicit SetVisible says so, or HwMapDecor == false
function Pure.Visible(attr: any, override: boolean?, enabled: boolean?): boolean
	if enabled == false then
		return false
	end
	if override ~= nil then
		return override
	end
	return attr ~= false
end

-- what runs at a quality level. bats = Shared.Budget("Bats") (Config.Quality), ghosts = Shared.Budget("Ghosts")
function Pure.Plan(quality: string, bats: number, ghosts: number, darkness: number): { [string]: any }
	local q = quality == "Low" and 1 or quality == "Medium" and 2 or 3
	local flocks = ({ 1, 2, 3 })[q]
	-- the whole main map stays within the Bats budget (+1 per flock for rounding); fewer by day
	local per = math.max(2, math.floor((bats or 6) / flocks * (.55 + .45 * math.clamp(darkness, 0, 1)) + .5))
	return {
		Quality = quality, Flocks = flocks, PerFlock = per, Details = q == 3,
		Wisps = ({ 3, 5, 8 })[q], WispLights = ({ 0, 1, 2 })[q],
		Ghosts = math.clamp(math.min(ghosts or 1, 2), 0, 2), GhostLight = q >= 2,
		Mist = ({ 2, 4, 6 })[q], MistRate = ({ .9, 1.3, 1.6 })[q],
		GhostEvery = q == 1 and { 90, 180 } or { 50, 120 }, MistEvery = { 150, 300 }, MistChance = q == 1 and .35 or .55,
	}
end

-- bat i (1..n) of a flock around landmark lm at time t: world position (orbits, figure-8 wobble, height bob)
function Pure.BatPos(lm, i: number, n: number, t: number, seed: number?): Vector3
	seed = seed or 0
	local dir = (i % 3 == 0) and -1 or 1
	local speed = (.42 + .26 * hash(i, 1 + seed)) * dir
	local r = lm.Radius * (.72 + .5 * hash(i, 2 + seed))
	local a = (i - 1) / math.max(1, n) * TAU + seed + speed * t
	local wob = math.sin(t * (.8 + .4 * hash(i, 3 + seed)) + i * 2.1) * lm.Radius * .13
	local y = lm.Center.Y + (hash(i, 4 + seed) - .5) * lm.Height + math.sin(t * (.6 + .5 * hash(i, 5 + seed)) + i * 1.7) * lm.Height * .5
	return V3(lm.Center.X + math.cos(a) * (r + wob), y, lm.Center.Z + math.sin(a) * (r + wob))
end

-- wing angles (inner, outer) in radians: fast flaps with the occasional glide
function Pure.Wing(t: number, i: number): (number, number)
	local f = 5.6 + 2.2 * hash(i, 7)
	local ph = hash(i, 8) * TAU
	local glide = math.clamp(math.sin(t * .35 + ph) * 2.2 + 1.2, 0, 1) -- 0 = gliding, 1 = flapping
	local amp = .2 + .62 * glide
	local s = math.sin(t * f * TAU / 2 + ph)
	local inner = amp * s + .12
	local outer = inner * .55 + amp * .45 * math.sin(t * f * TAU / 2 + ph - .9)
	return inner, outer
end

-- quadratic bezier
function Pure.Bezier(a: Vector3, b: Vector3, c: Vector3, u: number): Vector3
	local v = 1 - u
	return a * (v * v) + b * (2 * v * u) + c * (u * u)
end

-- a ghost route drifting past the player: a gentle curve that passes 15..28 studs from `origin` (never through the
-- camera) and runs 55..80 studs to either side. {From, Mid, To, Duration}; nil if THE DEAD YARD is in the way
function Pure.GhostRoute(rand: () -> number, origin: Vector3, inZone: ((Vector3) -> boolean)?): { [string]: any }?
	for _ = 1, 8 do
		local a = rand() * TAU
		local n = V3(math.cos(a), 0, math.sin(a)) -- toward the pass-by point
		local t = V3(-n.Z, 0, n.X) -- travel direction
		local d = 15 + rand() * 13
		local y = origin.Y + 4 + rand() * 4
		local c = V3(origin.X, y, origin.Z) + n * d
		local from = c - t * (55 + rand() * 25)
		local to = c + t * (55 + rand() * 25) + V3(0, (rand() - .5) * 2, 0)
		local mid = c + n * (rand() * 10) + V3(0, 2 + rand() * 3, 0)
		local ok = true
		if inZone then
			for _, p in ipairs({ from, mid, to, (from + mid) / 2, (mid + to) / 2 }) do
				if inZone(p) then
					ok = false
					break
				end
			end
		end
		if ok then
			local len = (mid - from).Magnitude + (to - mid).Magnitude
			return { From = from, Mid = mid, To = to, Duration = math.clamp(len / (4.2 + rand() * 1.8), 16, 32) }
		end
	end
	return nil
end

-- ghost fade: 0..1 opacity over the route (fade in 12 %, out 16 %)
function Pure.GhostAlpha(u: number): number
	if u <= 0 or u >= 1 then
		return 0
	end
	local function sm(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	return math.min(sm(u / .12), sm((1 - u) / .16))
end

-- floating candle wisp i around the spawn pad (radius 13..16.5, height ~3.4..5.6)
function Pure.WispPos(i: number, n: number, t: number, center: Vector3, calm: boolean?): Vector3
	local dir = (i % 2 == 0) and -1 or 1
	local r = 13.2 + 3.3 * hash(i, 11)
	local a = (i - 1) / math.max(1, n) * TAU + dir * (.06 + .05 * hash(i, 12)) * t
	local bob = (calm and .18 or .45) * math.sin(t * (.8 + .4 * hash(i, 13)) + i * 1.3)
	return V3(center.X + math.cos(a) * r, center.Y + 3.4 + 1.6 * hash(i, 14) + bob, center.Z + math.sin(a) * r)
end

-- candle-like flicker multiplier (0.78..1.06), deterministic
function Pure.Flicker(t: number, i: number): number
	local n = math.sin(t * 7.3 + i * 1.7) * .5 + math.sin(t * 13.1 + i * 3.1) * .3 + math.sin(t * 2.3 + i) * .2
	return .92 + .14 * n
end

function Pure.OnIsland(p: Vector3): boolean
	local b = M.Island
	return p.X >= b.X0 and p.X <= b.X1 and p.Z >= b.Z0 and p.Z <= b.Z1 and p.Y >= b.YMin
end

-- right-triangle wedge (right angle at f): CFrame + Size of a WedgePart in some local space
function Pure.Wedge(a: Vector3, f: Vector3, c: Vector3, thick: number): (CFrame, Vector3)
	local leg1, leg2 = f - a, c - f
	local zA, yA = leg1.Unit, leg2.Unit
	return CFrame.fromMatrix((a + c) / 2, yA:Cross(zA), yA, zA), V3(thick, leg2.Magnitude, leg1.Magnitude)
end

-- Russian of the layer's world lettering (the builder marks those labels NoTranslate; English kept in HwTextEN)
M.RU = {
	["NIGHT OF THE BURIED MOON"] = "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ",
	["THE DEAD YARD ↑"] = "МЁРТВЫЙ ДВОР ↑",
	["THE DEAD YARD →"] = "МЁРТВЫЙ ДВОР →",
	["← THE DEAD YARD"] = "← МЁРТВЫЙ ДВОР",
}

function M.Localize(label: Instance, russian: boolean)
	if not label:IsA("TextLabel") then
		return
	end
	local en = label:GetAttribute("HwTextEN")
	if type(en) ~= "string" then
		en = label.Text
		label:SetAttribute("HwTextEN", en)
	end
	label.Text = russian and M.RU[en] or en
end

------------------------------------------------------------------------------------------------------------------
-- Local toggle (layer + lamps)
------------------------------------------------------------------------------------------------------------------
local hiddenLightConns = {}

local function applyOne(d: Instance, visible: boolean)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = visible and 0 or 1
	elseif d:IsA("Light") then
		local base = d:GetAttribute("HwBaseBrightness")
		if visible then
			local c = hiddenLightConns[d]
			if c then
				c:Disconnect()
				hiddenLightConns[d] = nil
			end
			if type(base) == "number" then
				d.Brightness = base
			end
		else
			d.Brightness = 0
			if not hiddenLightConns[d] then
				-- WorldEventLighting restores Brightness after an event: keep it dark while hidden
				hiddenLightConns[d] = d:GetPropertyChangedSignal("Brightness"):Connect(function()
					if d.Brightness ~= 0 then
						d.Brightness = 0
					end
				end)
			end
		end
	elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
		(d :: any).Enabled = visible
	end
end

function M.ApplyLayer(layer: Instance, visible: boolean)
	applyOne(layer, visible)
	for _, d in ipairs(layer:GetDescendants()) do
		applyOne(d, visible)
	end
end

local function applyLamp(inst: Instance, visible: boolean)
	local col = inst:GetAttribute(visible and "Halloween_EventColor" or "Halloween_OriginalColor")
	if typeof(col) == "Color3" then
		pcall(function()
			(inst :: any).Color = col
		end)
	end
end

function M.ApplyLamps(list: { Instance }, visible: boolean)
	for _, inst in ipairs(list) do
		if inst.Parent then
			applyLamp(inst, visible)
		end
	end
end

function M.FindLamps(root: Instance): { Instance }
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("Halloween_MapLamp") == true then
			table.insert(out, d)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- Runtime state
------------------------------------------------------------------------------------------------------------------
local S = {
	Started = false, Running = false, Visible = true, Override = nil, Ctx = nil,
	District = nil, Layer = nil, Lamps = nil, Conns = {}, LayerAdded = nil, DistrictAdded = nil,
	Folder = nil, Plan = nil, Dirty = true, NextPlan = 0, Darkness = 0, CamPos = V3(0, 0, 377),
	Flocks = {}, Ghosts = {}, Wisps = nil, Mist = nil, NextGhost = 0, NextMist = 0, Lights = {}, Flames = {},
	Rng = Random.new(),
}
M._State = S

local function rand(): number
	return S.Rng:NextNumber()
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part")
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
	p.Name = props.Name or "MainMapFX"
	p.CFrame = props.CFrame or CF(0, -500, 0)
	p.Parent = props.Parent or S.Folder
	return p
end

local function folder(): Instance
	if S.Folder and S.Folder.Parent then
		return S.Folder
	end
	local root = S.Ctx and S.Ctx.FX and S.Ctx.FX.Folder() or workspace
	local f = root:FindFirstChild("MainMapLayer")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MainMapLayer"
		f:SetAttribute("SelfManagedFX", true)
		f.Parent = root
	end
	S.Folder = f
	return f
end

------------------------------------------------------------------------------------------------------------------
-- Bats
------------------------------------------------------------------------------------------------------------------
local BAT = Color3.fromRGB(24, 16, 32)
local BAT_WING = Color3.fromRGB(34, 22, 44)

local function buildBat(parent: Instance, s: number, details: boolean)
	local bat = { Parts = {}, Rest = {}, Kind = {}, S = s }
	local function add(p: BasePart, rest: CFrame, kind: string)
		table.insert(bat.Parts, p)
		table.insert(bat.Rest, rest)
		table.insert(bat.Kind, kind)
	end
	add(part({ Name = "BatBody", Size = V3(.42, .36, .95) * s, Color = BAT, Mesh = true, Parent = parent }), CF(0, 0, .05 * s), "Body")
	add(part({ Name = "BatHead", Size = V3(.36, .36, .36) * s, Shape = Enum.PartType.Ball, Color = BAT, Parent = parent }), CF(0, .07 * s, -.55 * s), "Body")
	for side = -1, 1, 2 do
		local sf, wf, sb = V3(side * .2, 0, -.25) * s, V3(side * 1.0, 0, -.25) * s, V3(side * .2, 0, .35) * s
		local tip, wb = V3(side * 1.85, 0, -.25) * s, V3(side * 1.0, 0, .3) * s
		local cf1, sz1 = Pure.Wedge(wf, sf, sb, .05)
		local cf2, sz2 = Pure.Wedge(tip, wf, wb, .05)
		add(part({ Class = "WedgePart", Name = "BatWing", Size = sz1, Color = BAT_WING, Parent = parent }), cf1, side < 0 and "L1" or "R1")
		add(part({ Class = "WedgePart", Name = "BatWing", Size = sz2, Color = BAT_WING, Parent = parent }), cf2, side < 0 and "L2" or "R2")
		if details then
			local cfE, szE = Pure.Wedge(V3(side * .06, .2, -.55) * s, V3(side * .17, .2, -.55) * s, V3(side * .17, .45, -.55) * s, .05)
			add(part({ Class = "WedgePart", Name = "BatEar", Size = szE, Color = BAT, Parent = parent }), cfE, "Body")
		end
	end
	if details then
		add(part({ Name = "BatEyes", Size = V3(.22, .05, .05) * s, Color = Color3.fromRGB(255, 96, 60), Material = Enum.Material.Neon, Parent = parent }),
			CF(0, .1 * s, -.72 * s), "Body")
	end
	return bat
end

local function makeFlock(lm, n: number, details: boolean)
	local model = Instance.new("Model")
	model.Name = "BatFlock_" .. lm.Name
	model.Parent = folder()
	local flock = { Landmark = lm, Model = model, Bats = {}, N = n, Seed = hash(#lm.Name, 21) * TAU, Parts = {}, CFs = {} }
	for i = 1, n do
		local bat = buildBat(model, .85 + .4 * hash(i, 31), details)
		bat.I = i
		table.insert(flock.Bats, bat)
		for _, p in ipairs(bat.Parts) do
			table.insert(flock.Parts, p)
		end
	end
	return flock
end

local function destroyFlock(f)
	if f.Model then
		f.Model:Destroy()
	end
end

local function updateFlock(f, t: number)
	local lm, n = f.Landmark, f.N
	local k = 0
	local cfs = f.CFs
	for _, bat in ipairs(f.Bats) do
		local i, s = bat.I, bat.S
		local p0 = Pure.BatPos(lm, i, n, t, f.Seed)
		local p1 = Pure.BatPos(lm, i, n, t + .06, f.Seed)
		local vel = p1 - p0
		local base = vel.Magnitude > 1e-4 and CFrame.lookAt(p0, p0 + vel) or CF(p0)
		local inner, outer = Pure.Wing(t, i)
		local bank = math.clamp((Pure.BatPos(lm, i, n, t + .12, f.Seed) - p1):Dot(base.RightVector) * 1.4, -.5, .5)
		local B = base * CFrame.Angles(0, 0, -bank) * CF(0, -.06 * s * math.sin(t * 9 + i), 0)
		local L1 = B * CF(-.2 * s, 0, 0) * CFrame.Angles(0, 0, -inner) * CF(.2 * s, 0, 0)
		local R1 = B * CF(.2 * s, 0, 0) * CFrame.Angles(0, 0, inner) * CF(-.2 * s, 0, 0)
		local L2 = L1 * CF(-1.0 * s, 0, 0) * CFrame.Angles(0, 0, -outer) * CF(1.0 * s, 0, 0)
		local R2 = R1 * CF(1.0 * s, 0, 0) * CFrame.Angles(0, 0, outer) * CF(-1.0 * s, 0, 0)
		local frames = { Body = B, L1 = L1, R1 = R1, L2 = L2, R2 = R2 }
		for j, rest in ipairs(bat.Rest) do
			k += 1
			cfs[k] = frames[bat.Kind[j]] * rest
		end
	end
	workspace:BulkMoveTo(f.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function planFlocks(cam: Vector3)
	local plan = S.Plan
	local want = {}
	local ranked = {}
	for _, lm in ipairs(M.Landmarks) do
		local d = (lm.Center - cam).Magnitude
		local active = S.Flocks[lm.Name] ~= nil
		if d < M.FlockRange + (active and 50 or 0) then
			table.insert(ranked, { Lm = lm, D = d })
		end
	end
	table.sort(ranked, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(plan.Flocks, #ranked) do
		want[ranked[i].Lm.Name] = ranked[i].Lm
	end
	for name, f in pairs(S.Flocks) do
		if not want[name] or f.N ~= plan.PerFlock or f.Details ~= plan.Details then
			destroyFlock(f)
			S.Flocks[name] = nil
		end
	end
	for name, lm in pairs(want) do
		if not S.Flocks[name] then
			local f = makeFlock(lm, plan.PerFlock, plan.Details)
			f.Details = plan.Details
			S.Flocks[name] = f
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Candle wisps around the spawn pad
------------------------------------------------------------------------------------------------------------------
local function destroyWisps()
	if S.Wisps then
		S.Wisps.Model:Destroy()
		S.Wisps = nil
	end
end

local function makeWisps(plan)
	local model = Instance.new("Model")
	model.Name = "SpawnCandleWisps"
	model.Parent = folder()
	local w = { Model = model, List = {}, N = plan.Wisps, Lights = plan.WispLights }
	for i = 1, plan.Wisps do
		local wax = part({ Name = "WispWax", Shape = Enum.PartType.Cylinder, Size = V3(.7, .28, .28), Color = Color3.fromRGB(246, 232, 200), Parent = model })
		local flame = part({ Name = "WispFlame", Size = V3(.22, .4, .22), Color = Color3.fromRGB(255, 176, 70), Material = Enum.Material.Neon, Mesh = true, Parent = model })
		local halo = part({ Name = "WispHalo", Shape = Enum.PartType.Ball, Size = V3(1.05, 1.05, 1.05), Color = Color3.fromRGB(255, 140, 50),
			Material = Enum.Material.Neon, Transparency = .8, Parent = model })
		local light = nil
		if i <= plan.WispLights then
			light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 150, 60)
			light.Range = 9
			light.Brightness = .7
			light.Shadows = false
			light.Parent = flame
		end
		table.insert(w.List, { Wax = wax, Flame = flame, Halo = halo, Light = light })
	end
	S.Wisps = w
end

local function updateWisps(t: number)
	local w = S.Wisps
	local calm = S.Ctx and S.Ctx.Shared.ReducedMotion() or false
	local parts, cfs = {}, {}
	for i, e in ipairs(w.List) do
		local p = Pure.WispPos(i, w.N, t, M.Spawn, calm)
		local sway = CFrame.Angles(math.sin(t * 1.3 + i) * .08, 0, math.cos(t * 1.1 + i) * .08)
		local base = CF(p) * sway
		table.insert(parts, e.Wax)
		table.insert(cfs, base * CFrame.Angles(0, 0, math.pi / 2))
		table.insert(parts, e.Flame)
		table.insert(cfs, base * CF(0, .58, 0))
		table.insert(parts, e.Halo)
		table.insert(cfs, base * CF(0, .58, 0))
		local fl = Pure.Flicker(t, i)
		e.Halo.Transparency = math.clamp(.86 - (fl - .92) * 1.5, .7, .95)
		if e.Light then
			e.Light.Brightness = .7 * fl
		end
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

------------------------------------------------------------------------------------------------------------------
-- Ghosts
------------------------------------------------------------------------------------------------------------------
local GHOST = Color3.fromRGB(214, 238, 255)
local INK = Color3.fromRGB(22, 14, 34)

local function makeGhost(route, light: boolean)
	local model = Instance.new("Model")
	model.Name = "MainMapGhost"
	model.Parent = folder()
	local g = { Model = model, Route = route, T0 = os.clock(), Parts = {}, Rest = {}, Base = {}, Hem = {}, Sounded = false }
	local function add(p: BasePart, rest: CFrame, base: number, hem: number?)
		table.insert(g.Parts, p)
		table.insert(g.Rest, rest)
		table.insert(g.Base, base)
		if hem then
			g.Hem[#g.Parts] = hem
		end
	end
	local sheet = part({ Name = "GhostSheet", Size = V3(2.6, 3.3, 2.6), Color = GHOST, Material = Enum.Material.Neon, Mesh = true, Transparency = 1, Parent = model })
	add(sheet, CF(0, .2, 0), .42)
	for k = 1, 5 do
		local a = (k - 1) / 5 * TAU + .3
		add(part({ Name = "GhostHem", Size = V3(.95, .95, .95), Shape = Enum.PartType.Ball, Color = GHOST, Material = Enum.Material.Neon, Transparency = 1, Parent = model }),
			CF(math.cos(a) * 1.0, -1.35, math.sin(a) * 1.0), .42, k)
	end
	for s = -1, 1, 2 do
		add(part({ Name = "GhostArm", Size = V3(.55, 1.0, .55), Color = GHOST, Material = Enum.Material.Neon, Mesh = true, Transparency = 1, Parent = model }),
			CF(s * 1.32, -.05, -.15) * CFrame.Angles(0, 0, s * .55), .45)
		add(part({ Name = "GhostEye", Size = V3(.36, .56, .2), Color = INK, Mesh = true, Transparency = 1, Parent = model }), CF(s * .42, .62, -1.16), 0)
	end
	add(part({ Name = "GhostMouth", Size = V3(.42, .52, .2), Color = INK, Mesh = true, Transparency = 1, Parent = model }), CF(0, -.05, -1.22), 0)
	if light then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(150, 210, 255)
		l.Range = 12
		l.Brightness = 0
		l.Shadows = false
		l.Parent = sheet
		g.Light = l
	end
	g.Sheet = sheet
	return g
end

local function updateGhost(g, now: number): boolean
	local r = g.Route
	local u = (now - g.T0) / r.Duration
	if u >= 1 then
		g.Model:Destroy()
		return false
	end
	local alpha = Pure.GhostAlpha(u)
	local calm = S.Ctx and S.Ctx.Shared.ReducedMotion() or false
	local p = Pure.Bezier(r.From, r.Mid, r.To, u)
	local p2 = Pure.Bezier(r.From, r.Mid, r.To, math.min(1, u + .01))
	local dir = V3(p2.X - p.X, 0, p2.Z - p.Z)
	p += V3(0, math.sin(now * 1.6) * (calm and .2 or .55), 0)
	-- drifts along its route but keeps peeking at the player
	local toCam = V3(S.CamPos.X - p.X, 0, S.CamPos.Z - p.Z)
	if dir.Magnitude > 1e-4 and toCam.Magnitude > 1e-4 then
		dir = dir.Unit * .45 + toCam.Unit * .55
	end
	local base = dir.Magnitude > 1e-4 and CFrame.lookAt(p, p + dir) or CF(p)
	base = base * CFrame.Angles(.12, 0, math.sin(now * 1.1) * (calm and .03 or .09))
	local cfs = {}
	for j, rest in ipairs(g.Rest) do
		local cf = base * rest
		local hem = g.Hem[j]
		if hem then
			cf = cf * CF(0, math.sin(now * 5 + hem * 1.3) * .14, 0)
		end
		cfs[j] = cf
		local bt = g.Base[j]
		g.Parts[j].Transparency = 1 - (1 - bt) * alpha
	end
	workspace:BulkMoveTo(g.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if g.Light then
		g.Light.Brightness = .9 * alpha
	end
	if not g.Sounded and alpha > .5 then
		g.Sounded = true
		if (p - S.CamPos).Magnitude < 75 and S.Ctx and S.Ctx.Audio then
			pcall(S.Ctx.Audio.Play, "GhostWoo", g.Sheet, { Volume = .45 })
		end
	end
	return true
end

local function clearGhosts()
	for _, g in ipairs(S.Ghosts) do
		g.Model:Destroy()
	end
	S.Ghosts = {}
end

------------------------------------------------------------------------------------------------------------------
-- Rare mist banks (night)
------------------------------------------------------------------------------------------------------------------
local function ground(): Vector3
	local root = S.Ctx and S.Ctx.Player.Character and S.Ctx.Player.Character:FindFirstChild("HumanoidRootPart")
	local p = root and root.CFrame.Position or S.CamPos
	return V3(p.X, math.max(p.Y - 3, -4), p.Z)
end

local function startMist(plan, now: number)
	local model = Instance.new("Model")
	model.Name = "MainMapMist"
	model.Parent = folder()
	local tex = S.Ctx.FX and S.Ctx.FX.Textures and S.Ctx.FX.Textures.Smoke or "rbxasset://textures/particles/smoke_main.dds"
	local mist = { Model = model, Emitters = {}, Until = now + 45 + rand() * 35, Rate = plan.MistRate, Fading = false, NextMove = 0 }
	local g = ground()
	for i = 1, plan.Mist do
		local a = (i / plan.Mist) * TAU + rand() * .8
		local r = 16 + rand() * 40
		local p = part({ Name = "MistBank", Size = V3(28, 1, 28), Transparency = 1, CFrame = CF(g + V3(math.cos(a) * r, .6, math.sin(a) * r)), Parent = model })
		local e = Instance.new("ParticleEmitter")
		e.Texture = tex
		e.Color = ColorSequence.new(Color3.fromRGB(200, 190, 226), Color3.fromRGB(150, 140, 196))
		e.LightEmission = .05
		e.LightInfluence = .85
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 7), NumberSequenceKeypoint.new(.5, 13), NumberSequenceKeypoint.new(1, 17) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.3, .84), NumberSequenceKeypoint.new(.7, .87),
			NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(7, 11)
		e.Speed = NumberRange.new(.4, 1.2)
		e.SpreadAngle = Vector2.new(180, 12)
		e.Acceleration = V3(.25, .06, 0)
		e.Drag = .4
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-8, 8)
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		e.Rate = 0
		e.Parent = p
		table.insert(mist.Emitters, { Part = p, E = e })
	end
	mist.T0 = now
	S.Mist = mist
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
	task.delay(fast and 0 or 12, function()
		m.Model:Destroy()
	end)
end

local function updateMist(now: number)
	local m = S.Mist
	local fadeIn = math.clamp((now - m.T0) / 6, 0, 1)
	local fadeOut = math.clamp((m.Until - now) / 8, 0, 1)
	local rate = m.Rate * math.min(fadeIn, fadeOut)
	for _, e in ipairs(m.Emitters) do
		e.E.Rate = rate
	end
	if now >= m.NextMove then
		m.NextMove = now + 2.5
		local g = ground()
		for _, e in ipairs(m.Emitters) do
			local p = e.Part.CFrame.Position
			if V3(p.X - g.X, 0, p.Z - g.Z).Magnitude > 75 then
				local a = rand() * TAU
				local r = 25 + rand() * 30
				e.Part.CFrame = CF(g + V3(math.cos(a) * r, .6, math.sin(a) * r))
			end
		end
	end
	if now >= m.Until then
		stopMist()
	end
end

------------------------------------------------------------------------------------------------------------------
-- Layer light flicker (Brightness only; WorldDetailQuality owns Enabled)
------------------------------------------------------------------------------------------------------------------
local function worldEventNormal(): boolean
	local we = RS:FindFirstChild("WorldEvents")
	local st = we and we:FindFirstChild("State")
	local s = st and st:GetAttribute("State")
	return s == nil or s == "NORMAL"
end

local function track(d: Instance)
	if d:IsA("Light") and type(d:GetAttribute("HwBaseBrightness")) == "number" then
		table.insert(S.Lights, d)
	elseif d:IsA("BasePart") and d:GetAttribute("HwCandle") == true then
		table.insert(S.Flames, d)
	end
end

local function collectLights()
	S.Lights, S.Flames = {}, {}
	if not S.Layer then
		return
	end
	for _, d in ipairs(S.Layer:GetDescendants()) do
		track(d)
	end
end

local function flickerLights(t: number)
	-- candle flames breathe (transparency only) near the camera
	for i, f in ipairs(S.Flames) do
		if f.Parent and (f.CFrame.Position - S.CamPos).Magnitude < 120 then
			f.Transparency = math.clamp((1.0 - Pure.Flicker(t * 1.6, i + 40)) * 1.6, 0, .3)
		end
	end
	if not worldEventNormal() then
		return
	end
	for i, l in ipairs(S.Lights) do
		if l.Parent then
			local p = l.Parent:IsA("BasePart") and l.Parent.CFrame.Position or nil
			if p and (p - S.CamPos).Magnitude < 200 then
				l.Brightness = l:GetAttribute("HwBaseBrightness") * Pure.Flicker(t, i)
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Scheduling
------------------------------------------------------------------------------------------------------------------
local function zoneNear(p: Vector3): boolean
	local Layout = S.Ctx and S.Ctx.Layout
	return Layout ~= nil and Layout.InZone(V3(p.X, 0, p.Z), 25)
end

local function replan(now: number)
	local ctx = S.Ctx
	local Shared = ctx.Shared
	local blood = 0
	pcall(function()
		blood = Shared.BloodMoonAlpha(Shared.Now())
	end)
	local dayFactor, isNight = Lighting:GetAttribute("DayFactor"), Lighting:GetAttribute("IsNight")
	local clock = nil
	if dayFactor == nil and isNight == nil then
		pcall(function()
			clock = Lighting.ClockTime
		end)
	end
	S.Darkness = Pure.Darkness(dayFactor, isNight, clock, blood)
	local quality = Shared.Quality()
	local plan = Pure.Plan(quality, Shared.Budget("Bats"), Shared.Budget("Ghosts"), S.Darkness)
	S.Plan = plan
	S.Dirty = false
	-- streamed-out copies leave the tracking lists
	for _, list in ipairs({ S.Lights, S.Flames, S.Lamps or {} }) do
		for i = #list, 1, -1 do
			if not list[i].Parent then
				table.remove(list, i)
			end
		end
	end
	local cam = S.CamPos
	local onIsland = Pure.OnIsland(cam)
	local yardWeight = ctx.Layout and ctx.Layout.Weight(cam, 60) or 0
	-- bats
	if onIsland then
		planFlocks(cam)
	else
		for name, f in pairs(S.Flocks) do
			destroyFlock(f)
			S.Flocks[name] = nil
		end
	end
	-- wisps near the spawn
	local nearSpawn = onIsland and (cam - M.Spawn).Magnitude < M.WispRange
	if nearSpawn and (not S.Wisps or S.Wisps.N ~= plan.Wisps or S.Wisps.Lights ~= plan.WispLights) then
		destroyWisps()
		makeWisps(plan)
	elseif not nearSpawn and S.Wisps then
		destroyWisps()
	end
	-- ghosts (night, outside the yard)
	local night = Pure.IsNight(S.Darkness)
	if not night then
		S.NextGhost = math.max(S.NextGhost, now + 20 + rand() * 25)
	elseif onIsland and yardWeight < .05 and #S.Ghosts < plan.Ghosts and now >= S.NextGhost then
		local route = Pure.GhostRoute(rand, ground(), zoneNear)
		if route then
			table.insert(S.Ghosts, makeGhost(route, plan.GhostLight))
		end
		S.NextGhost = now + plan.GhostEvery[1] + rand() * (plan.GhostEvery[2] - plan.GhostEvery[1])
	end
	-- mist banks (night, rare, outside the yard)
	if S.Mist and (not night or yardWeight > .2 or not onIsland) then
		stopMist()
	elseif not S.Mist and night and onIsland and yardWeight < .05 and now >= S.NextMist then
		S.NextMist = now + plan.MistEvery[1] + rand() * (plan.MistEvery[2] - plan.MistEvery[1])
		if rand() < plan.MistChance then
			startMist(plan, now)
		end
	elseif not night then
		S.NextMist = math.max(S.NextMist, now + 60 + rand() * 60)
	end
end

local function clearFX()
	for name, f in pairs(S.Flocks) do
		destroyFlock(f)
		S.Flocks[name] = nil
	end
	destroyWisps()
	clearGhosts()
	stopMist(true)
end

local function step()
	if not S.Running or not S.Visible then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	S.CamPos = cam.CFrame.Position
	local now = os.clock()
	if S.Dirty or now >= S.NextPlan then
		S.NextPlan = now + 1
		replan(now)
	end
	for _, f in pairs(S.Flocks) do
		updateFlock(f, now)
	end
	if S.Wisps then
		updateWisps(now)
	end
	for i = #S.Ghosts, 1, -1 do
		if not updateGhost(S.Ghosts[i], now) then
			table.remove(S.Ghosts, i)
		end
	end
	if S.Mist then
		updateMist(now)
	end
	flickerLights(now)
end

------------------------------------------------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------------------------------------------------
local function lampsList(): { Instance }
	if S.Lamps then
		return S.Lamps
	end
	S.Lamps = S.District and M.FindLamps(S.District) or {}
	return S.Lamps
end

local function applyVisible(visible: boolean)
	if S.Layer and S.Layer.Parent then
		M.ApplyLayer(S.Layer, visible)
	end
	if not visible or S.Lamps then
		local list = lampsList()
		M.ApplyLamps(list, visible)
	end
	if not visible then
		clearFX()
	else
		S.Dirty = true
	end
end

local function refresh()
	local ctx = S.Ctx
	if not ctx then
		return
	end
	local enabled = ctx.Shared.Enabled() and ctx.Shared.Config.MainMapDecorations ~= false
	local v = Pure.Visible(ctx.Player:GetAttribute("HwMapDecor"), S.Override, enabled)
	if v == S.Visible then
		return
	end
	S.Visible = v
	applyVisible(v)
	if ctx.Bus then
		ctx.Bus.Fire("MapDecor", { Visible = v })
	end
end

function M.SetVisible(on: boolean)
	S.Override = on ~= false
	refresh()
end

function M.IsVisible(): boolean
	return S.Visible
end

function M.Stop()
	S.Running = false
	clearFX()
	for _, c in ipairs(S.Conns) do
		c:Disconnect()
	end
	S.Conns = {}
	for l, c in pairs(hiddenLightConns) do
		c:Disconnect()
		hiddenLightConns[l] = nil
	end
	if S.Folder then
		S.Folder:Destroy()
		S.Folder = nil
	end
end

M._Step = step
M._Replan = replan

function M.Start(ctx)
	if S.Started then
		return
	end
	S.Started = true
	S.Ctx = ctx
	local Shared = ctx.Shared
	local player = ctx.Player
	-- Config.MainMapDecorations = false: the server destroys the layer; the lamps are put back locally too, no FX
	local decorOn = Shared.Config.MainMapDecorations ~= false
	-- the player's choice holds from the first frame (the layer itself is hidden once it is found below)
	S.Visible = Pure.Visible(player:GetAttribute("HwMapDecor"), nil, Shared.Enabled() and decorOn)
	if decorOn then
		S.Running = true
		table.insert(S.Conns, player:GetAttributeChangedSignal("HwMapDecor"):Connect(function()
			S.Override = nil
			refresh()
		end))
		for _, a in ipairs({ "WorldEventFX", "LowFX", "ReducedMotion" }) do
			table.insert(S.Conns, player:GetAttributeChangedSignal(a):Connect(function()
				S.Dirty = true
			end))
		end
		local st = RS:FindFirstChild("Halloween") and RS.Halloween:FindFirstChild("State")
		if st then
			table.insert(S.Conns, st:GetAttributeChangedSignal("Enabled"):Connect(function()
				if not Shared.Enabled() then
					M.Stop()
				end
			end))
		end
		table.insert(S.Conns, RunService.RenderStepped:Connect(step))
	end
	-- the layer (Default streaming: the Model is always there, its parts stream in)
	S.District = workspace:WaitForChild("DOGROTS_District", 60)
	S.Layer = decorOn and S.District and S.District:WaitForChild("39_HalloweenLayer", 30) or nil
	if S.Layer then
		collectLights()
		local function russian(): boolean
			local ok, ru = pcall(Shared.IsRussian)
			return ok and ru == true
		end
		local function localizeAll()
			local ru = russian()
			for _, d in ipairs(S.Layer:GetDescendants()) do
				if d:IsA("TextLabel") then
					M.Localize(d, ru)
				end
			end
		end
		localizeAll()
		table.insert(S.Conns, player:GetAttributeChangedSignal("DOGROTS_Language"):Connect(function()
			task.delay(.1, localizeAll)
		end))
		table.insert(S.Conns, S.Layer.DescendantAdded:Connect(function(d)
			if not S.Visible then
				applyOne(d, false)
			end
			if d:IsA("TextLabel") then
				M.Localize(d, russian())
			end
			track(d)
		end))
	end
	if S.District then
		-- streamed-in lamp copies arrive with the server's (event) colours
		table.insert(S.Conns, S.District.DescendantAdded:Connect(function(d)
			if d:GetAttribute("Halloween_MapLamp") == true then
				if S.Lamps then
					table.insert(S.Lamps, d)
				end
				if not S.Visible then
					applyLamp(d, false)
				end
			end
		end))
	end
	if not S.Visible then
		applyVisible(false)
	end
	if decorOn then
		refresh()
	end
end

return M
