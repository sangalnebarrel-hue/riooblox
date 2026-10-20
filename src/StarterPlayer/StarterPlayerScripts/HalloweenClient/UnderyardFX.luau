-- THE UNDERYARD · client world presentation (StarterPlayerScripts.HalloweenClient.UnderyardFX, WP-H2; DESIGN §7.3,
-- §17, §18, §24.2). Brings Workspace.DOGROTS_District.40_Underyard to life for this player. Every generic world
-- attribute the builders put on parts / models is animated here (activity visuals belong to the trial presenters):
--   * SEAL STATE per player (player attribute UySealMask): UyShowAtSeal = n / UyHideAtSeal = n (LocalTransparencyModifier
--     on parts and decals, a hidden part is also passable for this player; Enabled on guis / beams / trails, Rate on
--     emitters), UyLightAtSeal = n (Light.Brightness from 0 to UyBaseBrightness / HwBaseBrightness — never
--     Light.Enabled —, Neon dark until then). An attribute on a model / folder applies to everything inside it, the
--     part's own attribute wins. More seals while the player watches: veils dissolve, shown parts fade in, lights ramp
--     up — after a running cinematic, or at once on Bus "UySealReveal" {} (the seal-clear cinematic's cue).
--   * GATES (models with UyGate): veils shimmer; signs with TextEN / TextRU (any gui / label in the zone, e.g.
--     "SEALED · BELL SEAL II") are localized here; a gate without a sign gets a client one; the Arena gate opens while
--     the Black Bell Assault runs (RS.Halloween.State.Assault.State == "Active").
--   * MOTION on server time (one pose per model, BulkMoveTo, nearest first, culled by distance and quality):
--     UySpin (+UySpinAxis) carousel (walkable collidable parts never move), pendulums UySwingAmp / UySwingPeriod /
--     UySwingPhase / UySwingAxis with UnderyardRuntime.SwingAngle — the §24.2 formula SealRun's server hazard uses —,
--     UySwing the Black Bell's sway (degrees; Bus "UyBellStrike" {Strength} swings it harder), UyTowerBell (the broken
--     tower's bell, nudged by Bus "UyBellToll"), UySwirl / UySwirlSpeed (the arrival portal), UyDrift / UyDriftPeriod
--     (rock islands), UyBlink eye windows (lids by LidDir x LidTravel, pupils follow the camera), UyConveyorSpeed (belt
--     slats scroll), UyMoon (the Black Moon's corona turns, the pale moon's halo breathes).
--   * LIGHT LIFE: HwLantern / HwCandle / HwBrazier parts flicker (nearest N; Brightness and glass colour only).
--   * AMBIENT LIFE at 40_Underyard.FXMarkers attachments: motes round the camera (Shared.Budget("UnderMotes")), fog banks
--     (FogPoint_n), moth swarms (MothSwarm_n), wisps along WispPath_n loops, ghost residents (GhostResident_n: Pose Sit /
--     Mourn / Wait / Wander, Facing). Low quality: fewer of everything, no distant animation (> 160 studs).
--   * DISTRICT BANNER: entering another district shows its name and its seal (the arrival title is WP-F's: the first
--     district after a portal arrival is skipped).
-- Reduced Motion: decorative motion stops (drift, bell sway, swirl, corona, shimmer); gameplay motion (carousel,
-- pendulums, conveyor) keeps running. Everything is client-local, pcall'd per step and restored by Stop().
-- API: UnderyardFX.Start(ctx) · .Stop() · .Cleared() -> seals shown · .Reveal() (= Bus "UySealReveal") · .Stats()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local M = {}
local player = Players.LocalPlayer
local C3 = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local INK = C3(16, 12, 26)
local WHITE = Color3.new(1, 1, 1)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }

local started = false
local warned: { [string]: boolean } = {}
local mournerApi: any = nil
local stopFn: (() -> ())? = nil
local statsFn: (() -> any)? = nil
local revealFn: (() -> ())? = nil
local clearedFn: (() -> number)? = nil

function M.Stop()
	if stopFn then
		(stopFn :: () -> ())()
	end
end
function M.Stats(): any
	return statsFn and (statsFn :: () -> any)() or {}
end
function M.Reveal()
	if revealFn then
		(revealFn :: () -> ())()
	end
end
function M.Cleared(): number
	return clearedFn and (clearedFn :: () -> number)() or 0
end
-- the practice ring's Mourner dummy (Trials.Mourner drives it): {Act(state, seconds, hold?), Face(pos?), Glow(k), Hurt(),
-- Reset(), Heart() -> Vector3, Built() -> bool, Model() -> Model?} (a handle that waits for the model when it is not built)
function M.Mourner(): any
	return mournerApi
end

local function num(v: any): number?
	return type(v) == "number" and v or nil
end

-- parts posed in one call (falls back to plain CFrame writes where BulkMoveTo is missing)
local bulkOk: boolean? = nil
local function bulk(parts: { BasePart }, cfs: { CFrame })
	if #parts == 0 then
		return
	end
	-- a part that streamed out (no parent) is dropped from this move; its mover forgets it on DescendantRemoving
	for i = 1, #parts do
		if parts[i].Parent == nil then
			local keepP, keepC = {}, {}
			for j, p in ipairs(parts) do
				if p.Parent ~= nil then
					table.insert(keepP, p)
					table.insert(keepC, cfs[j])
				end
			end
			parts, cfs = keepP, keepC
			break
		end
	end
	if #parts == 0 then
		return
	end
	if bulkOk ~= false then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if ok then
			bulkOk = true
			return
		end
		bulkOk = false
	end
	for i, p in ipairs(parts) do
		p.CFrame = cfs[i]
	end
end
M.Bulk = bulk

local function axisAngles(axis: any, a: number): CFrame
	if axis == "X" then
		return ANG(a, 0, 0)
	elseif axis == "Y" then
		return ANG(0, a, 0)
	end
	return ANG(0, 0, a)
end

function M.Start(ctx)
	if started then
		return
	end
	local Shared, Bus, FX, Audio = ctx.Shared, ctx.Bus, ctx.FX, ctx.Audio
	if not (Shared and Shared.Chapter2Enabled()) then
		return
	end
	local okR, R = pcall(function()
		return require(RS:WaitForChild("Halloween"):WaitForChild("UnderyardRuntime")) :: any
	end)
	if not okR or type(R) ~= "table" then
		warn("UnderyardFX: UnderyardRuntime missing")
		return
	end
	started = true
	local Layout = R.Layout
	local Cfg = R.Config
	local C2Cfg: any = nil
	pcall(function()
		C2Cfg = require(RS.Halloween:WaitForChild("Chapter2Config")) :: any
	end)
	local Loc: any = nil
	pcall(function()
		local folder = RS:FindFirstChild("Localization")
		local mod = folder and folder:FindFirstChild("UnderyardFX")
		Loc = mod and require(mod) :: any
	end)
	local function T(en: string): string
		if Shared.IsRussian() and Loc and Loc.UI then
			return Loc.UI[en] or en
		end
		return en
	end
	local function pair(p: any): string
		if type(p) == "table" then
			return Shared.L(p[1] or "", p[2])
		end
		return tostring(p or "")
	end
	local Ambient: any = ctx.Modules and ctx.Modules.AmbientFX or nil -- Rig + part models (ghost, wisp) when present

	local conns: { RBXScriptConnection } = {}
	local alive = true
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "UnderyardFX"
	fxFolder.Parent = FX.Folder()

	local function quality(): string
		return Shared.Quality()
	end
	local function reduced(): boolean
		return Shared.ReducedMotion()
	end
	local function serverNow(): number
		local ok, t = pcall(function()
			return workspace:GetServerTimeNow()
		end)
		return ok and t or os.clock()
	end
	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Layout.Centre
	end
	local mainGui: any = nil
	local function gui(): any
		if mainGui and mainGui.Parent then
			return mainGui
		end
		local pg = player:FindFirstChildOfClass("PlayerGui")
		mainGui = pg and pg:FindFirstChild("ScreenGui")
		return mainGui
	end
	local function cinemaActive(): boolean
		local g = gui()
		return g ~= nil and g:GetAttribute("CinemaActive") == true
	end

	---------------------------------------------------------------------------------------------------------------
	-- registry
	---------------------------------------------------------------------------------------------------------------
	local root: Instance? = nil
	local leaves: { [Instance]: any } = {} -- seal-state leaves (parts, lights, guis, emitters, beams, decals)
	local containers: { [Instance]: any } = {} -- tagged models / folders {Show, Hide, Light}
	local gates: { [Instance]: any } = {} -- gate models {Model, District, Seal, Open, Sign?}
	local movers: { [Instance]: any } = {}
	local moverList: { any } = {}
	local flames: { [Instance]: any } = {}
	local flameList: { any } = {}
	local texts: { [Instance]: boolean } = {}
	local markers: { [string]: { [Instance]: any } } = { Moth = {}, Fog = {}, Wisp = {}, Ghost = {} }
	local conveyors: { [Instance]: any } = {}
	local anim: { [any]: boolean } = {} -- leaves gliding to their target
	local cleared = R.Cleared(player:GetAttribute("UySealMask"))
	local assault = false
	local pending: any = nil
	local ready = false
	local stats = { Leaves = 0, Movers = 0, Flames = 0, Markers = 0, Moved = 0, Ghosts = 0, Moths = 0, Wisps = 0, Fog = 0 }

	local function ownSeal(inst: Instance): (number?, number?, number?)
		return num(inst:GetAttribute("UyShowAtSeal")), num(inst:GetAttribute("UyHideAtSeal")), num(inst:GetAttribute("UyLightAtSeal"))
	end

	-- nearest tagged values (per key: the instance itself, then its tagged parts / models / folders upwards — a lantern
	-- glass's PointLight follows the glass's UyLightAtSeal, a part its model's) and the gate this instance belongs to
	local function inherited(inst: Instance): (number?, number?, number?, any)
		local show, hide, light = ownSeal(inst)
		local gate = nil
		local a = inst.Parent
		local depth = 0
		while a and a ~= root and depth < 14 do
			local c = containers[a]
			local s2, h2, l2 = nil, nil, nil
			if c then
				s2, h2, l2 = c.Show, c.Hide, c.Light
			elseif a:IsA("BasePart") then
				s2, h2, l2 = ownSeal(a)
			end
			show = show or s2
			hide = hide or h2
			light = light or l2
			if not gate then
				gate = gates[a]
			end
			a = a.Parent
			depth += 1
		end
		return show, hide, light, gate
	end

	local function effective(rec: any): number
		if rec.Gate then
			return R.GateCleared(rec.Gate.District, cleared, assault)
		end
		return cleared
	end

	-- writers ------------------------------------------------------------------------------------------------------
	local function paintGlass(part: any, base: Color3, f: number, lit: number)
		local col = base
		if f > 1 then
			col = base:Lerp(WHITE, math.clamp((f - 1) * .3, 0, .4))
		elseif f < 1 then
			col = base:Lerp(INK, math.clamp((1 - f) * .5, 0, .5))
		end
		if lit < 1 then
			col = col:Lerp(INK, (1 - lit) * Cfg.Seal.UnlitDark)
		end
		if part.Color ~= col then
			part.Color = col
		end
	end

	local function writeLight(rec: any)
		local l = rec.Inst :: any
		local b = rec.Base * rec.Lit * (rec.Flicker or 1)
		if math.abs(l.Brightness - b) > .004 or (b == 0 and l.Brightness ~= 0) or (rec.Lit == 1 and rec.Flicker == 1 and l.Brightness ~= b) then
			l.Brightness = b
		end
		rec.Written = l.Brightness
	end

	local function write(rec: any)
		local inst = rec.Inst :: any
		local kind = rec.Kind
		if kind == "Part" then
			local ltm = 1 - rec.Vis * (1 - (rec.Shim or 0))
			if math.abs(inst.LocalTransparencyModifier - ltm) > .004 or ((ltm == 0 or ltm == 1) and inst.LocalTransparencyModifier ~= ltm) then
				inst.LocalTransparencyModifier = ltm
			end
			if rec.BaseCollide then
				local want = rec.Vis > .5
				if inst.CanCollide ~= want then
					inst.CanCollide = want
				end
			end
			if rec.Neon then
				local mat = rec.Lit > .04 and Enum.Material.Neon or Enum.Material.SmoothPlastic
				if inst.Material ~= mat then
					inst.Material = mat
				end
				local fl = flames[inst]
				paintGlass(inst, rec.BaseColor, fl and fl.F or 1, rec.Lit)
			end
		elseif kind == "Light" then
			writeLight(rec)
		elseif kind == "Gui" then
			local on = rec.BaseEnabled and rec.Vis > .5
			if inst.Enabled ~= on then
				inst.Enabled = on
			end
		elseif kind == "Emitter" then
			local rate = rec.BaseRate * (rec.Vis >= .999 and 1 or 0) * rec.Lit
			if inst.Rate ~= rate then
				inst.Rate = rate
			end
		elseif kind == "Beam" then
			local on = rec.BaseEnabled and rec.Vis > .5 and rec.Lit > .5
			if inst.Enabled ~= on then
				inst.Enabled = on
			end
		elseif kind == "Decal" then
			local ltm = 1 - rec.Vis
			pcall(function()
				if math.abs(inst.LocalTransparencyModifier - ltm) > .004 or ((ltm == 0 or ltm == 1) and inst.LocalTransparencyModifier ~= ltm) then
					inst.LocalTransparencyModifier = ltm
				end
			end)
		end
	end

	local function restore(rec: any)
		local inst = rec.Inst :: any
		if not inst.Parent then
			return
		end
		pcall(function()
			if rec.Kind == "Part" then
				inst.LocalTransparencyModifier = 0
				if rec.BaseCollide then
					inst.CanCollide = true
				end
				if rec.Neon then
					inst.Material = rec.BaseMaterial
					inst.Color = rec.BaseColor
				end
			elseif rec.Kind == "Light" then
				inst.Brightness = rec.Base
			elseif rec.Kind == "Gui" or rec.Kind == "Beam" then
				inst.Enabled = rec.BaseEnabled
			elseif rec.Kind == "Emitter" then
				inst.Rate = rec.BaseRate
			elseif rec.Kind == "Decal" then
				inst.LocalTransparencyModifier = 0
			end
		end)
	end

	-- target of a leaf from the seal state; instant = no glide (first sight / streamed in / a reset)
	local function apply(rec: any, instant: boolean)
		local hidden, lit = R.SealVisual(rec.Show, rec.Hide, rec.LightAt, effective(rec))
		rec.VisTo = hidden and 0 or 1
		rec.LitTo = lit
		if instant then
			rec.Vis, rec.Lit = rec.VisTo, rec.LitTo
			anim[rec] = nil
			write(rec)
		elseif rec.Vis ~= rec.VisTo or rec.Lit ~= rec.LitTo then
			anim[rec] = true
		end
	end

	local function lightBase(l: any): number
		local b = l:GetAttribute("UyBaseBrightness")
		if type(b) ~= "number" then
			b = l:GetAttribute("HwBaseBrightness")
		end
		if type(b) ~= "number" then
			b = l.Brightness
			l:SetAttribute("HwBaseBrightness", b)
		end
		return b
	end

	local function addLeaf(inst: Instance, kind: string, show: number?, hide: number?, light: number?, gate: any)
		local rec: any = { Inst = inst, Kind = kind, Show = show, Hide = hide, LightAt = light, Gate = gate, Vis = 1, Lit = 1, Shim = 0 }
		local i = inst :: any
		if kind == "Part" then
			rec.BaseCollide = i.CanCollide == true
			rec.BaseColor = i.Color
			rec.BaseMaterial = i.Material
			rec.Neon = light ~= nil and i.Material == Enum.Material.Neon
			rec.Veil = gate ~= nil and hide ~= nil and i.Material == Enum.Material.Neon and i.Transparency >= .3
			rec.Phase = R.SeedOf(i.Position) * .013
		elseif kind == "Light" then
			rec.Base = lightBase(i)
			rec.Flicker = 1
		elseif kind == "Gui" or kind == "Beam" then
			rec.BaseEnabled = i.Enabled
		elseif kind == "Emitter" then
			rec.BaseRate = i.Rate
		end
		leaves[inst] = rec
		stats.Leaves += 1
		apply(rec, true)
		return rec
	end

	-- movers -------------------------------------------------------------------------------------------------------
	local moverKind = R.MoverKind

	local EYE_PARTS = { EyelidTop = true, EyelidBottom = true, EyePupil = true, EyeGlint = true }
	local function wantsPart(rec: any, p: BasePart): boolean
		if rec.Kind == "Spin" then
			return not p.CanCollide -- the walkable deck / centre column are round: they never need to turn
		elseif rec.Kind == "Eye" then
			return EYE_PARTS[p.Name] == true
		elseif rec.Kind == "Moon" then
			return p.Name == "CoronaFlare" or p.Name == "MoonHalo"
		end
		return true
	end

	local function resolvePivot(rec: any): CFrame?
		if rec.Pivot then
			return rec.Pivot
		end
		local m = rec.Model :: Model
		local pp: BasePart? = m.PrimaryPart
		if rec.Kind == "TowerBell" then
			local crown = m:FindFirstChild("BellCrown", true)
			if crown and crown:IsA("BasePart") then
				rec.Pivot = CF((crown :: BasePart).Position + V3(0, .9, 0))
			end
		elseif pp then
			rec.Pivot = pp.CFrame
		elseif rec.Kind == "Eye" then
			local pane = m:FindFirstChild("EyePane")
			if pane and pane:IsA("BasePart") then
				rec.Pivot = (pane :: BasePart).CFrame
			end
		end
		if rec.Pivot then
			rec.Seed = R.SeedOf((rec.Pivot :: CFrame).Position)
			for i, rest in ipairs(rec.Rest) do
				rec.Rel[i] = (rec.Pivot :: CFrame):ToObjectSpace(rest)
			end
		end
		return rec.Pivot
	end

	local function moverPart(rec: any, p: BasePart)
		if rec.Index[p] or not wantsPart(rec, p) then
			return
		end
		table.insert(rec.Parts, p)
		table.insert(rec.Rest, p.CFrame)
		local i = #rec.Parts
		rec.Index[p] = i
		if rec.Pivot then
			rec.Rel[i] = (rec.Pivot :: CFrame):ToObjectSpace(p.CFrame)
		end
		if rec.Kind == "Eye" then
			rec.Info[i] = { Dir = num(p:GetAttribute("LidDir")), Travel = num(p:GetAttribute("LidTravel")), Name = p.Name }
		elseif rec.Kind == "Moon" then
			rec.Info[i] = { Name = p.Name, Base = p.Transparency }
		end
	end

	local function addMover(model: Model, a: { [string]: any }, kind: string)
		if movers[model] then
			return
		end
		local rec: any = { Model = model, Kind = kind, Attr = a, Parts = {}, Rest = {}, Rel = {}, Index = {}, Info = {}, Pivot = nil,
			Seed = 0, Boost = 0, Moved = false }
		movers[model] = rec
		table.insert(moverList, rec)
		stats.Movers += 1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				moverPart(rec, d)
			end
		end
		resolvePivot(rec)
	end

	local function moverOf(inst: Instance): any
		local a = inst.Parent
		local depth = 0
		while a and a ~= root and depth < 10 do
			local m = movers[a]
			if m then
				return m
			end
			a = a.Parent
			depth += 1
		end
		return nil
	end

	-- flames -------------------------------------------------------------------------------------------------------
	local flameKind = R.FlameKind

	local addLight
	local function addFlame(p: BasePart, kind: string)
		if flames[p] then
			return
		end
		local rec: any = { Part = p, Kind = kind, Phase = R.SeedOf(p.Position) * .017, Lights = {}, BaseColor = p.Color, Pos = p.Position, F = 1,
			Active = false }
		flames[p] = rec
		table.insert(flameList, rec)
		stats.Flames += 1
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("Light") then
				addLight(c)
			end
		end
	end

	addLight = function(l: Light)
		local rec = leaves[l]
		if not rec then
			local show, hide, light, gate = inherited(l)
			rec = addLeaf(l, "Light", show, hide, light, gate)
		end
		local parent = l.Parent
		local fl = parent and flames[parent]
		if fl and not table.find(fl.Lights, rec) then
			table.insert(fl.Lights, rec)
		end
	end

	-- texts --------------------------------------------------------------------------------------------------------
	local function localize(inst: Instance)
		local en, ru = inst:GetAttribute("TextEN"), inst:GetAttribute("TextRU")
		if type(en) ~= "string" then
			return
		end
		local want = (Shared.IsRussian() and type(ru) == "string") and ru or en
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			local l = inst :: any
			if l.Text ~= want then
				l.Text = want
			end
		elseif inst:IsA("LayerCollector") then
			local label = inst:FindFirstChildWhichIsA("TextLabel", true)
			if label and label:GetAttribute("TextEN") == nil and (label :: TextLabel).Text ~= want then
				(label :: TextLabel).Text = want
			end
		end
	end

	-- classification ------------------------------------------------------------------------------------------------
	local function add(inst: Instance)
		if not root then
			return
		end
		if inst:IsA("Model") or inst:IsA("Folder") then
			local a = inst:GetAttributes()
			if a.UyShowAtSeal ~= nil or a.UyHideAtSeal ~= nil or a.UyLightAtSeal ~= nil then
				containers[inst] = { Show = num(a.UyShowAtSeal), Hide = num(a.UyHideAtSeal), Light = num(a.UyLightAtSeal) }
			end
			if inst:IsA("Model") then
				if type(a.UyGate) == "string" and not gates[inst] then
					local district = a.UyGate :: string
					gates[inst] = { Model = inst, District = district, Seal = num(a.UySeal) or Layout.Unlock[district] or 0, At = os.clock(),
						Open = R.GateOpen(district, cleared, assault) }
				end
				local kind = moverKind(a)
				if kind then
					addMover(inst :: Model, a, kind)
				end
			end
			return
		end
		if inst:IsA("BasePart") then
			local p = inst :: BasePart
			local a = p:GetAttributes()
			local fk = flameKind(a)
			if fk then
				addFlame(p, fk)
			end
			if a.UyConveyorSpeed ~= nil and not conveyors[p] then
				conveyors[p] = { Belt = p, Speed = num(a.UyConveyorSpeed) or 0, Slats = nil }
			end
			local show, hide, light, gate = inherited(p)
			if show or hide or light then
				if not leaves[p] then
					addLeaf(p, "Part", show, hide, light, gate)
				end
			end
			local m = moverOf(p)
			if m then
				moverPart(m, p)
				if not m.Pivot then
					resolvePivot(m)
				end
			end
			return
		end
		if inst:IsA("Light") then
			addLight(inst :: Light)
			return
		end
		if inst:IsA("Attachment") then
			local kind, base = R.MarkerKind(inst.Name)
			if kind and not markers[kind][inst] then
				markers[kind][inst] = { Att = inst, Kind = kind, Base = base }
				stats.Markers += 1
			end
			return
		end
		if inst:GetAttribute("TextEN") ~= nil then
			texts[inst] = true
			localize(inst)
		end
		local kind = nil
		if inst:IsA("LayerCollector") then
			kind = "Gui"
		elseif inst:IsA("ParticleEmitter") then
			kind = "Emitter"
		elseif inst:IsA("Beam") or inst:IsA("Trail") then
			kind = "Beam"
		elseif inst:IsA("Decal") then
			kind = "Decal"
		end
		if kind and not leaves[inst] then
			local show, hide, light, gate = inherited(inst)
			if show or hide or light then
				addLeaf(inst, kind, show, hide, light, gate)
			end
		end
	end

	-- a mover part leaving (streaming out): drop it from its mover's pose lists
	local function forgetMoverPart(p: BasePart)
		local m = moverOf(p)
		local i = m and m.Index[p]
		if not (m and i) then
			return
		end
		local parts, rest, rel, info = {}, {}, {}, {}
		table.clear(m.Index)
		for j, q in ipairs(m.Parts) do
			if j ~= i then
				table.insert(parts, q)
				local k = #parts
				rest[k], rel[k], info[k] = m.Rest[j], m.Rel[j], m.Info[j]
				m.Index[q] = k
			end
		end
		m.Parts, m.Rest, m.Rel, m.Info = parts, rest, rel, info
		if #m.Parts == 0 then
			m.Pivot = nil -- resolved again when the model streams back in
		end
	end

	local function remove(inst: Instance)
		if inst:IsA("BasePart") then
			pcall(forgetMoverPart, inst :: BasePart)
			if inst.Name == "BeltSlat" then
				for _, c in pairs(conveyors) do
					if c.Slats and table.find(c.Slats, inst) then
						c.Slats = nil -- rebuilt from the belt's siblings
					end
				end
			end
		end
		local rec = leaves[inst]
		if rec then
			leaves[inst] = nil
			anim[rec] = nil
			stats.Leaves -= 1
		end
		containers[inst] = nil
		texts[inst] = nil
		conveyors[inst] = nil
		local g = gates[inst]
		if g then
			gates[inst] = nil
			if g.Sign then
				g.Sign:Destroy()
			end
		end
		local fl = flames[inst]
		if fl then
			flames[inst] = nil
			local i = table.find(flameList, fl)
			if i then
				table.remove(flameList, i)
			end
			stats.Flames -= 1
		end
		local mv = movers[inst]
		if mv then
			movers[inst] = nil
			local i = table.find(moverList, mv)
			if i then
				table.remove(moverList, i)
			end
			stats.Movers -= 1
		end
		if inst:IsA("Attachment") then
			for _, set in pairs(markers) do
				if set[inst] then
					set[inst] = nil
					stats.Markers -= 1
				end
			end
		end
	end

	-- root: the first scan is spread over frames (the zone holds up to 26 000 parts)
	local rootConns: { RBXScriptConnection } = {}
	local function detachRoot()
		for _, c in ipairs(rootConns) do
			c:Disconnect()
		end
		table.clear(rootConns)
		for _, rec in pairs(leaves) do
			restore(rec)
		end
		for _, mv in ipairs(moverList) do
			if mv.Moved then
				pcall(bulk, mv.Parts, mv.Rest)
			end
		end
		table.clear(leaves)
		table.clear(containers)
		for _, g in pairs(gates) do
			if g.Sign then
				g.Sign:Destroy()
			end
		end
		table.clear(gates)
		table.clear(movers)
		table.clear(moverList)
		table.clear(flames)
		table.clear(flameList)
		table.clear(texts)
		table.clear(conveyors)
		table.clear(anim)
		for _, set in pairs(markers) do
			table.clear(set)
		end
		stats.Leaves, stats.Movers, stats.Flames, stats.Markers = 0, 0, 0, 0
		root = nil
		ready = false
	end

	local function attachRoot(r: Instance)
		root = r
		table.insert(rootConns, r.DescendantAdded:Connect(function(d)
			if alive and root == r and ready then
				local ok, err = pcall(add, d)
				if not ok and not warned.Warned then
					warned.Warned = true
					warn("UnderyardFX: register failed: " .. tostring(err))
				end
			end
		end))
		table.insert(rootConns, r.DescendantRemoving:Connect(function(d)
			if root == r then
				pcall(remove, d)
			end
		end))
		task.spawn(function()
			local list = r:GetDescendants()
			for i, d in ipairs(list) do
				if not alive or root ~= r then
					return
				end
				pcall(add, d)
				if i % 1500 == 0 then
					task.wait()
				end
			end
			if alive and root == r then
				ready = true
				-- anything that arrived while the first scan ran
				for _, d in ipairs(r:GetDescendants()) do
					if not (leaves[d] or containers[d] or movers[d] or flames[d]) then
						pcall(add, d)
					end
				end
			end
		end)
	end

	local function findRoot()
		local district = workspace:FindFirstChild("DOGROTS_District")
		local r = district and district:FindFirstChild("40_Underyard")
		if r ~= root then
			if root then
				detachRoot()
			end
			if r then
				attachRoot(r)
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- seal state: changes, reveal timing, the Arena under the Assault
	---------------------------------------------------------------------------------------------------------------
	local function gateBurst(g: any)
		local pos = g.Model:GetPivot().Position + V3(0, 7, 0)
		local veil = g.Model:FindFirstChild("VeilCentre", true)
		if veil and veil:IsA("Attachment") then
			local p = veil.Parent
			pos = (p and p:IsA("BasePart")) and ((p :: BasePart).CFrame * (veil :: Attachment).CFrame).Position or (veil :: Attachment).WorldPosition
		end
		pcall(function()
			FX.Burst(pos, { Color = C3(190, 150, 255), Color2 = C3(150, 200, 255), Count = 44, Speed = { 3, 9 }, Size = { .45, .7, 0 },
				Lifetime = { 1, 1.8 }, Acceleration = V3(0, 2, 0), Drag = 3 })
			FX.Ring(pos - V3(0, 6, 0), C3(170, 120, 255), 12, 1.2)
		end)
		pcall(Audio.Play, "SealIgnite", pos, { Volume = .8 })
		Bus.Fire("UyGateOpened", { District = g.District, Position = pos })
	end

	local function setCleared(n: number, instant: boolean)
		cleared = n
		for _, rec in pairs(leaves) do
			apply(rec, instant)
		end
		for _, g in pairs(gates) do
			local open = R.GateOpen(g.District, cleared, assault)
			if open and not g.Open and not instant then
				gateBurst(g)
			end
			g.Open = open
		end
	end

	local function onMask()
		local n = R.Cleared(player:GetAttribute("UySealMask"))
		if n == cleared and not pending then
			return
		end
		if not ready or n < cleared then
			pending = nil
			setCleared(n, true)
			return
		end
		pending = { Cleared = n, Since = os.clock() }
	end

	local function revealNow()
		if pending then
			local n = pending.Cleared
			pending = nil
			setCleared(n, false)
		end
	end
	revealFn = revealNow
	clearedFn = function()
		return cleared
	end

	local function assaultState(): boolean
		local st = RS.Halloween:FindFirstChild("State")
		local f = st and st:FindFirstChild("Assault")
		return f ~= nil and f:GetAttribute("State") == "Active"
	end

	---------------------------------------------------------------------------------------------------------------
	-- motion
	---------------------------------------------------------------------------------------------------------------
	local MC = Cfg.Motion
	local function bellBoost(rec: any, dt: number)
		if rec.Boost > 0 then
			rec.Boost = math.max(0, rec.Boost - dt * MC.Bell.StrikeDecay)
		end
	end

	local function poseMover(rec: any, t: number, cam: Vector3, dt: number)
		local pivot = rec.Pivot :: CFrame
		local a = rec.Attr
		local kind = rec.Kind
		local cfs = table.create(#rec.Parts)
		if kind == "Eye" then
			local seed = rec.Seed
			local c = R.Blink(t, seed)
			local eyeH = num(rec.Model:GetAttribute("EyeHeight")) or 2
			local look = cam - pivot.Position
			look = look.Magnitude > .1 and look.Unit or V3(0, 0, 1)
			local shift = eyeH * MC.PupilShift
			for i, p in ipairs(rec.Parts) do
				local rest = rec.Rest[i]
				local info = rec.Info[i] or {}
				if info.Dir and info.Travel then
					cfs[i] = rest + rest.UpVector * (info.Dir * info.Travel * c)
				else
					local dx = math.clamp(look:Dot(rest.RightVector), -1, 1) * shift
					local dy = math.clamp(look:Dot(rest.UpVector), -1, 1) * shift * .6
					cfs[i] = rest + rest.RightVector * dx + rest.UpVector * dy
				end
			end
			bulk(rec.Parts, cfs)
			return
		end
		if kind == "Moon" then
			if a.UyMoon == "Black" then
				local ang = R.SpinAngle(MC.MoonCorona, t)
				local moved, mcf = {}, {}
				for i, p in ipairs(rec.Parts) do
					if (rec.Info[i] or {}).Name == "CoronaFlare" and rec.Rel[i] then
						table.insert(moved, p)
						table.insert(mcf, pivot * ANG(ang, 0, 0) * rec.Rel[i])
					end
				end
				bulk(moved, mcf)
			else
				local k = .5 + .5 * math.sin(R.Phase01(t, 9) * math.pi * 2)
				for i, p in ipairs(rec.Parts) do
					local info = rec.Info[i]
					if info and info.Name == "MoonHalo" then
						local ltm = k * .45
						if math.abs(p.LocalTransparencyModifier - ltm) > .01 then
							p.LocalTransparencyModifier = ltm
						end
					end
				end
			end
			return
		end
		if kind == "Swing" or kind == "Spin" then
			-- (gameplay motion: always on)
		elseif reduced() then
			return
		end
		local off
		if kind == "Spin" then
			off = axisAngles(a.UySpinAxis or "Y", R.SpinAngle(num(a.UySpin) or 0, t))
		elseif kind == "Swing" then
			local amp = num(a.UySwingAmp) or 0
			if a.UySwingUnit == "Deg" then
				amp = math.rad(amp)
			end
			off = axisAngles(a.UySwingAxis or "Z", R.SwingAngle(amp, num(a.UySwingPeriod) or 3.2, num(a.UySwingPhase) or 0, t))
		elseif kind == "Bell" then
			bellBoost(rec, dt)
			local pitch, roll = R.BellSway(t, num(a.UySwingAmp) or MC.Bell.AmpDeg, num(a.UySwingPeriod) or MC.Bell.Period, rec.Boost)
			off = ANG(pitch, 0, roll)
		elseif kind == "TowerBell" then
			bellBoost(rec, dt)
			local pitch, roll = R.BellSway(t, MC.TowerBell.AmpDeg, MC.TowerBell.Period, rec.Boost)
			off = ANG(pitch, 0, roll)
		elseif kind == "Swirl" then
			off = ANG(0, 0, R.SpinAngle(num(a.UySwirlSpeed) or MC.Swirl, t))
		elseif kind == "Drift" then
			local y, tilt = R.Drift(num(a.UyDrift) or 2, num(a.UyDriftPeriod) or 11, t, rec.Seed * .01)
			off = CF(0, y, 0) * ANG(tilt, 0, tilt * .6)
		else
			return
		end
		local target = pivot * off
		for i = 1, #rec.Parts do
			local rel = rec.Rel[i]
			cfs[i] = rel and target * rel or rec.Rest[i]
		end
		bulk(rec.Parts, cfs)
		rec.Moved = true
	end

	local function conveyorStep(c: any, t: number)
		local belt = c.Belt :: BasePart
		if not c.Slats then
			c.Slats = {}
			c.SlatRest = {}
			local parent = belt.Parent
			if parent then
				for _, s in ipairs(parent:GetChildren()) do
					if s:IsA("BasePart") and s.Name == "BeltSlat" then
						table.insert(c.Slats, s)
						table.insert(c.SlatRest, (s :: BasePart).CFrame)
					end
				end
			end
			local dir = belt.CFrame.LookVector
			c.Dir = dir
			local lo, hi = math.huge, -math.huge
			for _, rest in ipairs(c.SlatRest) do
				local along = (rest.Position - belt.Position):Dot(dir)
				lo, hi = math.min(lo, along), math.max(hi, along)
			end
			c.Lo, c.Span = lo, (hi - lo) + MC.ConveyorSpacing
		end
		if #c.Slats == 0 then
			return
		end
		local o = (t * math.abs(c.Speed)) % MC.ConveyorSpacing
		if c.Speed < 0 then
			o = -o
		end
		local cfs = table.create(#c.Slats)
		for i, rest in ipairs(c.SlatRest) do
			local along = (rest.Position - belt.Position):Dot(c.Dir)
			local moved = c.Lo + ((along - c.Lo + o) % c.Span)
			cfs[i] = rest + c.Dir * (moved - along)
		end
		bulk(c.Slats, cfs)
	end

	---------------------------------------------------------------------------------------------------------------
	-- flames
	---------------------------------------------------------------------------------------------------------------
	local FC = Cfg.Flicker
	local activeFlames: { any } = {}
	local function pickFlames(cam: Vector3)
		local maxN = R.Pick(FC.Count, quality())
		local cand = {}
		for _, f in ipairs(flameList) do
			if f.Part.Parent then
				local d = (f.Pos - cam).Magnitude
				if d < FC.Range then
					table.insert(cand, { F = f, D = d })
				end
			end
		end
		table.sort(cand, function(x, y)
			return x.D < y.D
		end)
		local keep = {}
		for i = 1, math.min(maxN, #cand) do
			keep[cand[i].F] = true
		end
		-- flames leaving the set go back to their steady light
		for _, f in ipairs(activeFlames) do
			if not keep[f] and f.Part.Parent then
				f.F = 1
				for _, lr in ipairs(f.Lights) do
					lr.Flicker = 1
					writeLight(lr)
				end
				local leaf = leaves[f.Part]
				paintGlass(f.Part, f.BaseColor, 1, leaf and leaf.Lit or 1)
			end
		end
		table.clear(activeFlames)
		for f in pairs(keep) do
			table.insert(activeFlames, f)
		end
	end

	local function flickerStep(t: number)
		for _, f in ipairs(activeFlames) do
			local part = f.Part :: BasePart
			if part.Parent then
				local fv = R.Flicker(f.Kind, t, f.Phase, 1)
				f.F = fv
				for _, lr in ipairs(f.Lights) do
					lr.Flicker = fv
					if lr.Inst.Parent then
						writeLight(lr)
					end
				end
				local leaf = leaves[part]
				if part.Material == Enum.Material.Neon or (leaf and leaf.Neon) then
					paintGlass(part, leaf and leaf.BaseColor or f.BaseColor, fv, leaf and leaf.Lit or 1)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- ambient life
	---------------------------------------------------------------------------------------------------------------
	local AC = Cfg.Ambient
	local function attPos(att: Attachment): Vector3
		local p = att.Parent
		if p and p:IsA("BasePart") then
			return ((p :: BasePart).CFrame * att.CFrame).Position
		end
		local ok, w = pcall(function()
			return att.WorldPosition
		end)
		return ok and w or Vector3.zero
	end

	local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Transparency = transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		return p
	end

	-- motes round the camera
	local motes: any = nil
	local function ensureMotes(): any
		if motes and motes.Part.Parent then
			return motes
		end
		local part = newPart("UyMotes", V3(AC.Motes.Radius * 2, AC.Motes.Height, AC.Motes.Radius * 2), WHITE, nil, 1)
		part.Parent = fxFolder
		local list = {}
		for i, col in ipairs({ C3(120, 255, 140), C3(170, 120, 255), C3(150, 200, 255) }) do
			local e = Instance.new("ParticleEmitter")
			e.Name = "Motes" .. i
			e.Texture = FX.Textures and FX.Textures.Sparkle or "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(col)
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .06), NumberSequenceKeypoint.new(.5, .2), NumberSequenceKeypoint.new(1, .05) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .25), NumberSequenceKeypoint.new(.8, .35),
				NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(AC.Motes.Lifetime * .7, AC.Motes.Lifetime * 1.2)
			e.Speed = NumberRange.new(.2, .7)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = V3(0, .12, 0)
			e.RotSpeed = NumberRange.new(-30, 30)
			e.Rate = 0
			pcall(function()
				e.Shape = Enum.ParticleEmitterShape.Box
				e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			end)
			e.Parent = part
			table.insert(list, e)
		end
		motes = { Part = part, Emitters = list }
		return motes
	end

	local function motesStep(inside: boolean, cam: Vector3)
		if not inside then
			if motes and motes.Part.Parent then
				for _, e in ipairs(motes.Emitters) do
					e.Rate = 0
				end
			end
			return
		end
		local m = ensureMotes()
		local count = math.max(0, tonumber(Shared.Budget("UnderMotes")) or 0)
		local rate = count / AC.Motes.Lifetime / #m.Emitters
		for _, e in ipairs(m.Emitters) do
			if math.abs(e.Rate - rate) > .01 then
				e.Rate = rate
			end
		end
		m.Part.CFrame = CF(cam.X, math.max(Layout.Floor + AC.Motes.Height * .5 - 2, cam.Y - 3), cam.Z)
	end

	-- fog banks (pool reassigned to the nearest FogPoint markers)
	local fogPool: { any } = {}
	local function fogEmitter(): any
		local part = newPart("UyFog", V3(10, 2, 10), WHITE, nil, 1)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Fog"
		e.Texture = FX.Textures and FX.Textures.Smoke or "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(C3(78, 84, 140), C3(56, 50, 96))
		e.LightEmission = .15
		e.LightInfluence = .4
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.3, .78), NumberSequenceKeypoint.new(.7, .82),
			NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(7, 11)
		e.Speed = NumberRange.new(.2, .8)
		e.SpreadAngle = Vector2.new(180, 10)
		e.RotSpeed = NumberRange.new(-6, 6)
		e.Rotation = NumberRange.new(0, 360)
		e.Rate = 0
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		e.Parent = part
		part.Parent = fxFolder
		return { Part = part, E = e, Marker = nil }
	end

	local function fogStep(inside: boolean, cam: Vector3)
		local want = inside and R.Pick(AC.Fog.Count, quality()) or 0
		local cand = {}
		if want > 0 then
			for att in pairs(markers.Fog) do
				if att.Parent then
					local pos = attPos(att :: Attachment)
					local d = (pos - cam).Magnitude
					if d < AC.Fog.Range then
						table.insert(cand, { Att = att, Pos = pos, D = d })
					end
				end
			end
			table.sort(cand, function(x, y)
				return x.D < y.D
			end)
		end
		for i = 1, math.max(#fogPool, math.min(want, #cand)) do
			local c = cand[i]
			local slot = fogPool[i]
			if c and i <= want then
				if not slot then
					slot = fogEmitter()
					fogPool[i] = slot
				end
				if slot.Marker ~= c.Att then
					slot.Marker = c.Att
					local att = c.Att :: Attachment
					local radius = num(att:GetAttribute("Radius")) or 10
					local density = num(att:GetAttribute("Density")) or .6
					local abyss = att:GetAttribute("Abyss") == true
					slot.Part.Size = V3(radius * 1.6, abyss and 6 or 2, radius * 1.6)
					slot.Part.CFrame = CF(c.Pos)
					local s = abyss and { 18, 30 } or { 7, 13 }
					slot.E.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s[1] * .6), NumberSequenceKeypoint.new(1, s[2]) })
					slot.E.Rate = (abyss and 2.2 or 1.1) * density * (radius / 10)
				end
			elseif slot then
				slot.Marker = nil
				slot.E.Rate = 0
			end
		end
		stats.Fog = math.min(want, #cand)
	end

	-- moths: tiny pale wings fluttering round their swarm marker
	local swarms: { [Instance]: any } = {}
	local function buildSwarm(att: Attachment, scale: number): any
		local count = math.clamp(math.floor((num(att:GetAttribute("Count")) or 8) * scale + .5), 1, AC.Moths.Max)
		local radius = num(att:GetAttribute("Radius")) or 3
		local model = Instance.new("Model")
		model.Name = "UyMoths"
		local parts, moths = {}, {}
		local seed = R.SeedOf(attPos(att))
		for i = 1, count do
			local h = R.Hash(seed, i)
			local wl = newPart("MothWing", V3(.34, .03, .24), C3(232, 224, 205), Enum.Material.SmoothPlastic, .08)
			local wr = newPart("MothWing", V3(.34, .03, .24), C3(232, 224, 205), Enum.Material.SmoothPlastic, .08)
			wl.Parent, wr.Parent = model, model
			table.insert(parts, wl)
			table.insert(parts, wr)
			table.insert(moths, { R = radius * (.35 + .65 * h), W = (.9 + 1.4 * R.Hash(seed, i + 40)) * (h < .5 and 1 or -1), P = h * 6.28,
				Hy = (R.Hash(seed, i + 80) - .5) * 1.6, F = 14 + 8 * R.Hash(seed, i + 120) })
		end
		model.Parent = fxFolder
		return { Att = att, Model = model, Parts = parts, Moths = moths, Seen = os.clock() }
	end

	local function mothsStep(inside: boolean, cam: Vector3, t: number, update: boolean)
		local q = quality()
		local maxS = inside and R.Pick(AC.Moths.Swarms, q) or 0
		local cand = {}
		if maxS > 0 then
			for att in pairs(markers.Moth) do
				if att.Parent then
					local pos = attPos(att :: Attachment)
					local d = (pos - cam).Magnitude
					if d < AC.Moths.Range then
						table.insert(cand, { Att = att, D = d })
					end
				end
			end
			table.sort(cand, function(x, y)
				return x.D < y.D
			end)
		end
		local keep = {}
		for i = 1, math.min(maxS, #cand) do
			keep[cand[i].Att] = true
		end
		local n = 0
		for att, sw in pairs(swarms) do
			if not keep[att] then
				sw.Model:Destroy()
				swarms[att] = nil
			end
		end
		for att in pairs(keep) do
			if not swarms[att] then
				swarms[att] = buildSwarm(att :: Attachment, R.Pick(AC.Moths.Scale, q))
			end
		end
		if not update then
			return
		end
		for att, sw in pairs(swarms) do
			local c = attPos(att :: Attachment)
			local cfs = table.create(#sw.Parts)
			for i, m in ipairs(sw.Moths) do
				local th = m.P + t * m.W
				local pos = c + V3(math.cos(th) * m.R, m.Hy + math.sin(t * 1.7 + m.P) * .45, math.sin(th) * m.R)
				local tangent = V3(-math.sin(th), 0, math.cos(th)) * (m.W > 0 and 1 or -1)
				local body = CFrame.lookAt(pos, pos + tangent)
				local flap = math.sin(t * m.F + m.P) * .9
				cfs[i * 2 - 1] = body * ANG(0, 0, flap) * CF(-.17, 0, 0)
				cfs[i * 2] = body * ANG(0, 0, -flap) * CF(.17, 0, 0)
				n += 1
			end
			bulk(sw.Parts, cfs)
		end
		stats.Moths = n
	end

	-- wisps along the WispPath loops (AmbientFX's wisp model)
	local wisps: { any } = {}
	local paths: { [string]: any } = {}
	local pathsAt = -1e9
	local function rebuildPaths()
		table.clear(paths)
		for att in pairs(markers.Wisp) do
			if att.Parent then
				local a = att :: Attachment
				local name = tostring(a:GetAttribute("Path") or "Path")
				local p = paths[name]
				if not p then
					p = { Points = {}, Loop = a:GetAttribute("Loop") == true }
					paths[name] = p
				end
				table.insert(p.Points, { I = num(a:GetAttribute("Index")) or 0, Pos = attPos(a) })
			end
		end
		for _, p in pairs(paths) do
			table.sort(p.Points, function(x, y)
				return x.I < y.I
			end)
			local pts = {}
			for _, row in ipairs(p.Points) do
				table.insert(pts, row.Pos)
			end
			if p.Loop and #pts > 2 then
				table.insert(pts, pts[1])
			end
			p.Poly = pts
			p.Length = R.PathLength(pts)
		end
	end

	local function wispsStep(inside: boolean, cam: Vector3, t: number, dt: number)
		local want = (inside and Ambient and Ambient.Models and Ambient.Models.Wisp) and R.Pick(AC.Wisps.Count, quality()) or 0
		if os.clock() - pathsAt > 5 then
			pathsAt = os.clock()
			rebuildPaths()
		end
		local names = {}
		for name, p in pairs(paths) do
			if p.Length and p.Length > 4 then
				table.insert(names, name)
			end
		end
		table.sort(names)
		if #names == 0 then
			want = 0
		end
		while #wisps > want do
			local w = table.remove(wisps)
			if w then
				pcall(function()
					w.Rig:Destroy()
				end)
			end
		end
		while #wisps < want do
			local i = #wisps + 1
			local name = names[(i - 1) % #names + 1]
			local col = i % 2 == 0 and C3(170, 120, 255) or C3(130, 255, 160)
			local ok, rig = pcall(Ambient.Models.Wisp, fxFolder, { Color = col })
			if not ok or not rig then
				break
			end
			table.insert(wisps, { Rig = rig, Path = name, D = R.Hash(i, 3) * (paths[name].Length or 1), Dir = 1, Phase = i * 1.3 })
		end
		local n = 0
		for _, w in ipairs(wisps) do
			local p = paths[w.Path]
			if p and p.Poly and #p.Poly >= 2 and (p.Length or 0) > 0 then
				local len = p.Length
				w.D += AC.Wisps.Speed * dt * w.Dir
				if p.Loop then
					w.D %= len
				elseif w.D > len or w.D < 0 then
					w.Dir = -w.Dir
					w.D = math.clamp(w.D, 0, len)
				end
				local pos = R.PathPoint(p.Poly, w.D)
				pos += V3(math.sin(t * 1.3 + w.Phase) * .6, math.sin(t * 2.1 + w.Phase) * .5, math.cos(t * 1.1 + w.Phase) * .6)
				if (pos - cam).Magnitude < AC.Wisps.Range then
					w.Rig:Update(CF(pos))
					w.Rig:SetFade(0)
					n += 1
				else
					w.Rig:SetFade(1)
				end
			end
		end
		stats.Wisps = n
	end

	-- ghost residents: spectral dogs idling at their markers (shy when someone comes close)
	local ghosts: { [Instance]: any } = {}
	local function ghostsStep(inside: boolean, cam: Vector3, t: number, dt: number)
		local Models = Ambient and Ambient.Models
		local maxG = (inside and Models and Models.Ghost) and R.Pick(AC.Ghosts.Count, quality()) or 0
		local cand = {}
		if maxG > 0 then
			for att in pairs(markers.Ghost) do
				if att.Parent then
					local pos = attPos(att :: Attachment)
					local d = (pos - cam).Magnitude
					if d < AC.Ghosts.Range then
						table.insert(cand, { Att = att, Pos = pos, D = d })
					end
				end
			end
			table.sort(cand, function(x, y)
				return x.D < y.D
			end)
		end
		local keep = {}
		for i = 1, math.min(maxG, #cand) do
			keep[cand[i].Att] = cand[i].Pos
		end
		for att, g in pairs(ghosts) do
			if not keep[att] then
				pcall(function()
					g.Rig:Destroy()
				end)
				ghosts[att] = nil
			end
		end
		local ch = player.Character
		local root2 = ch and ch:FindFirstChild("HumanoidRootPart")
		local me = root2 and (root2 :: BasePart).Position or cam
		local n = 0
		for att, pos in pairs(keep) do
			local g = ghosts[att]
			if not g then
				local a = att :: Attachment
				local ok, rig = pcall(Models.Ghost, fxFolder, { Color = C3(176, 208, 255), Core = C3(160, 110, 255) })
				if ok and rig then
					local facing = a:GetAttribute("Facing")
					local f = typeof(facing) == "Vector3" and V3(facing.X, 0, facing.Z) or V3(0, 0, -1)
					f = f.Magnitude > .01 and f.Unit or V3(0, 0, -1)
					-- GhostResident markers name their pose; a district's GhostPath_n spot is a wandering, floating spirit
					local mk = markers.Ghost[att]
					local pose = a:GetAttribute("Pose") or ((mk and mk.Base == "GhostPath") and "Wander" or "Wait")
					g = { Rig = rig, Pose = tostring(pose), Yaw = math.atan2(-f.X, -f.Z), Phase = R.Hash(R.SeedOf(pos), 5) * 6.28,
						Fade = 1 }
					ghosts[att] = g
				end
			end
			if g then
				local shy = (me - pos).Magnitude < AC.Ghosts.Shy
				local target = shy and .82 or .25
				g.Fade += (target - g.Fade) * math.min(1, dt / AC.Ghosts.Fade)
				local bob = reduced() and 0 or math.sin(t * 1.2 + g.Phase) * .22
				local yaw = g.Yaw
				local base = pos
				local lookOff = 0
				local poseName = g.Pose
				if poseName == "Wander" and not reduced() then
					local th = g.Phase + t * .35
					base = pos + V3(math.cos(th) * 3.5, 0, math.sin(th) * 3.5)
					yaw = math.atan2(math.sin(th), -math.cos(th)) -- facing along the circle
				elseif poseName == "Wait" then
					local d = me - pos
					if d.Magnitude < 26 then
						local want = math.atan2(-d.X, -d.Z)
						lookOff = math.clamp(((want - yaw + math.pi) % (2 * math.pi)) - math.pi, -.7, .7)
					end
				end
				local drop = poseName == "Sit" and 1.05 or (poseName == "Mourn" and .35 or 0)
				local rootCF = CF(base + V3(0, -2.3 - drop + bob, 0)) * ANG(0, yaw, 0)
				local pose = Models.GhostPose(reduced() and 0 or t + g.Phase, math.deg(lookOff))
				if poseName == "Mourn" then
					pose.Head = (pose.Head or CF()) * ANG(math.rad(-26), 0, 0)
					pose.Body = (pose.Body or CF()) * ANG(math.rad(-8), 0, 0)
				elseif poseName == "Sit" then
					pose.Body = (pose.Body or CF()) * ANG(math.rad(10), 0, 0)
				end
				g.Rig:Update(rootCF, pose)
				g.Rig:SetFade(g.Fade)
				n += 1
			end
		end
		stats.Ghosts = n
	end

	-- gate veils shimmer (visible veil parts near the camera)
	local function veilStep(cam: Vector3, t: number)
		local amp = (reduced() or quality() == "Low") and 0 or AC.Veil.Shimmer
		for _, rec in pairs(leaves) do
			if rec.Veil and rec.Vis > .5 and not anim[rec] then
				local part = rec.Inst :: BasePart
				local near = (part.Position - cam).Magnitude < AC.Veil.Range
				local s = near and amp * (.5 + .5 * math.sin(t * 1.9 + rec.Phase + part.Position.Y * .35)) or 0
				if math.abs(s - rec.Shim) > .01 then
					rec.Shim = s
					write(rec)
				end
			end
		end
	end

	-- a client sign on gates that have none ("SEALED · BELL SEAL n")
	local function gateSigns()
		for _, g in pairs(gates) do
			if os.clock() - g.At > 4 and g.HasSign == nil then
				local has = false
				for _, d in ipairs(g.Model:GetDescendants()) do
					if d:IsA("LayerCollector") then
						has = true
						break
					end
				end
				g.HasSign = has
			end
			local open = R.GateOpen(g.District, cleared, assault)
			if g.HasSign == false and not open and not g.Sign then
				local holder = newPart("UyGateSign", V3(1, 1, 1), WHITE, nil, 1)
				holder.CFrame = CF(g.Model:GetPivot().Position + V3(0, 11, 0))
				local bb = Instance.new("BillboardGui")
				bb.Name = "Sign"
				bb.Size = UDim2.fromOffset(260, 56)
				bb.MaxDistance = 110
				bb.LightInfluence = 0
				bb.AlwaysOnTop = false
				bb:SetAttribute("NoTranslate", true)
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.FontFace = FONT
				label.TextScaled = true
				label.TextColor3 = C3(225, 200, 255)
				label.TextStrokeColor3 = INK
				label.TextStrokeTransparency = .2
				label:SetAttribute("NoTranslate", true)
				local roman = ROMAN[g.Seal] or tostring(g.Seal)
				label.Text = string.format(T("SEALED · BELL SEAL %s"), roman)
				label.Parent = bb
				bb.Parent = holder
				holder.Parent = fxFolder
				g.Sign = holder
			elseif g.Sign and open then
				g.Sign:Destroy()
				g.Sign = nil
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE PRACTICE RING: the Mourner dummy (Models.Mourner) idles on its pedestal; Trials.Mourner drives its wind-ups and
	-- strikes through M.Mourner(); the onboarding's own Strike targets (invisible server parts of kinds UyTutorialEcho /
	-- UyTollBell / UyMournerWeak, owner only) get their visuals here: ghostly echo orbs, a glow under the hand-bell, the
	-- dummy's ribcage opening on its heart (and its collapse when the heart is struck).
	---------------------------------------------------------------------------------------------------------------
	local MournerModel: any = nil
	pcall(function()
		MournerModel = require(RS.Halloween:WaitForChild("Models"):WaitForChild("Mourner")) :: any
	end)
	local PR = { Build = 170, Anim = 120, Rate = 30, Top = .7, Turn = 6, Blend = .35 }
	local dummyState: any = { Act = nil, FaceAt = nil, Glow = 1, GlowTo = 1, Weak = false, Yaw = 0, BlendFrom = nil, BlendAt = 0, Last = nil }
	local dummy: any = nil -- {Rig}
	local dummyAcc = 0
	local function dummyBase(): CFrame
		local p = Layout.Square.Mourner
		return CF(p.X, Layout.Floor + PR.Top, p.Z)
	end
	local function act(state: string, seconds: number?, hold: number?)
		local now = os.clock()
		if dummyState.Last then
			dummyState.BlendFrom, dummyState.BlendAt = dummyState.Last, now
		end
		dummyState.Act = { State = state, Start = now, Dur = math.max(.05, seconds or .6), Hold = hold or 0 }
	end
	mournerApi = {
		Act = act,
		Face = function(pos: Vector3?)
			dummyState.FaceAt = pos
		end,
		Glow = function(k: number)
			dummyState.GlowTo = k
		end,
		Hurt = function()
			act("Hurt", .45, 0)
		end,
		Reset = function()
			act(dummyState.Weak and "Open" or "Idle", .4, dummyState.Weak and math.huge or 0)
			dummyState.FaceAt = nil
			dummyState.GlowTo = dummyState.Weak and 2 or 1
		end,
		Heart = function(): Vector3
			if dummy and dummy.Rig then
				return dummy.Rig:BoneWorld("Heart").Position
			end
			return dummyBase().Position + V3(0, MournerModel and MournerModel.HeartY or 3.7, 0)
		end,
		Built = function(): boolean
			return dummy ~= nil
		end,
		Model = function(): Model?
			return dummy and dummy.Rig and dummy.Rig.Model or nil
		end,
	}

	local function dummyStep(cam: Vector3, dt: number)
		if not MournerModel then
			return
		end
		local base = dummyBase()
		local d = (base.Position - cam).Magnitude
		local want = root ~= nil and d < PR.Build
		if want and not dummy then
			local ok, rig = pcall(MournerModel.Build, fxFolder, { Lite = quality() == "Low", Light = quality() ~= "Low" })
			if ok and rig then
				dummy = { Rig = rig }
			end
		elseif not want and dummy then
			pcall(function()
				dummy.Rig:Destroy()
			end)
			dummy = nil
		end
		if not dummy or d > PR.Anim then
			return
		end
		dummyAcc += dt
		if dummyAcc < 1 / PR.Rate then
			return
		end
		local adt = dummyAcc
		dummyAcc = 0
		local now = os.clock()
		local t = reduced() and 0 or now
		-- the pose: the running act (held on its last frame for Hold seconds), else idle
		local a = dummyState.Act
		local pose
		if a then
			local k = (now - a.Start) / a.Dur
			if k >= 1 and now - a.Start - a.Dur >= a.Hold then
				dummyState.BlendFrom, dummyState.BlendAt = dummyState.Last, now
				dummyState.Act = nil
				pose = MournerModel.Pose("Idle", t, 0)
			else
				pose = MournerModel.Pose(a.State, t, math.min(1, k))
			end
		else
			pose = MournerModel.Pose(dummyState.Weak and "Open" or "Idle", t, 1)
		end
		if dummyState.BlendFrom then
			local w = (now - dummyState.BlendAt) / PR.Blend
			if w >= 1 then
				dummyState.BlendFrom = nil
			else
				pose = MournerModel.Blend(dummyState.BlendFrom, pose, w * w * (3 - 2 * w))
			end
		end
		dummyState.Last = pose
		-- facing: the player in a run (Face), else the plaza (-Z)
		local yawTo = 0
		local f = dummyState.FaceAt
		if typeof(f) == "Vector3" then
			local dir = V3(f.X - base.X, 0, f.Z - base.Z)
			if dir.Magnitude > .5 then
				yawTo = math.atan2(-dir.X, -dir.Z)
			end
		end
		local diff = ((yawTo - dummyState.Yaw + math.pi) % (2 * math.pi)) - math.pi
		dummyState.Yaw += diff * math.min(1, adt * PR.Turn)
		dummyState.Glow += (dummyState.GlowTo - dummyState.Glow) * math.min(1, adt * 5)
		local rig = dummy.Rig
		rig:Update(base * ANG(0, dummyState.Yaw, 0), pose)
		rig:Glow(dummyState.Glow + (dummyState.Weak and .25 * math.sin(now * 6) or 0))
	end

	-- the onboarding's targets
	local TUTORIAL_KINDS = { UyTutorialEcho = true, UyTollBell = true, UyMournerWeak = true }
	local tutorialTargets: { [Instance]: any } = {}
	local function echoVisual(part: BasePart): any
		local m = Instance.new("Model")
		m.Name = "UyTutorialEchoFX"
		local col = C3(150, 200, 255)
		local shell = newPart("EchoShell", V3(2.2, 2.2, 2.2), col, Enum.Material.Neon, .72)
		shell.Shape = Enum.PartType.Ball
		shell.Parent = m
		local core = newPart("EchoCore", V3(.9, .9, .9), C3(235, 245, 255), Enum.Material.Neon, .05)
		core.Shape = Enum.PartType.Ball
		core.Parent = m
		local ears = {}
		for _, sx in ipairs({ -1, 1 }) do
			local ear = newPart("EchoEar", V3(.18, .9, .55), col, Enum.Material.Neon, .55)
			ear.Parent = m
			table.insert(ears, { Part = ear, Side = sx })
		end
		local eyes = {}
		for _, sx in ipairs({ -1, 1 }) do
			local eye = newPart("EchoEye", V3(.2, .26, .1), INK, Enum.Material.SmoothPlastic, 0)
			eye.Shape = Enum.PartType.Ball
			eye.Parent = m
			table.insert(eyes, { Part = eye, Side = sx })
		end
		local ring = newPart("EchoRing", V3(.08, 3.4, 3.4), C3(190, 150, 255), Enum.Material.Neon, .55)
		ring.Shape = Enum.PartType.Cylinder
		ring.Parent = m
		pcall(function()
			local e = Instance.new("ParticleEmitter")
			e.Texture = FX.Textures and FX.Textures.Sparkle or "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(col, C3(200, 160, 255))
			e.LightEmission = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(1, 0) })
			e.Lifetime = NumberRange.new(.8, 1.4)
			e.Speed = NumberRange.new(.4, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Rate = quality() == "Low" and 3 or 8
			e.Parent = core
			if quality() ~= "Low" then
				local l = Instance.new("PointLight")
				l.Color = col
				l.Range = 9
				l.Brightness = 1.1
				l.Shadows = false
				l.Parent = core
			end
		end)
		m.Parent = fxFolder
		return { Model = m, Shell = shell, Core = core, Ears = ears, Eyes = eyes, Ring = ring, Part = part, Seed = R.SeedOf(part.Position) }
	end
	local function poseEcho(v: any, t: number)
		local part = v.Part :: BasePart
		local bob = reduced() and 0 or math.sin(t * 2.1 + v.Seed) * .35
		local c = CF(part.Position + V3(0, bob, 0))
		local cam = workspace.CurrentCamera
		local face = c
		if cam then
			local dir = V3(cam.CFrame.Position.X - c.X, 0, cam.CFrame.Position.Z - c.Z)
			if dir.Magnitude > .5 then
				face = CF(c.Position) * ANG(0, math.atan2(dir.X, dir.Z) + math.pi, 0)
			end
		end
		local hpFrac = math.clamp((tonumber(part:GetAttribute("HP")) or 1) / math.max(1, tonumber(part:GetAttribute("MaxHP")) or 1), 0, 1)
		local pulse = 1 + (reduced() and 0 or .06 * math.sin(t * 4 + v.Seed))
		local parts, cfs = { v.Shell, v.Core, v.Ring }, { face, face * CF(0, 0, -.25), CF(c.Position) * ANG(0, t * 1.4, 0) * ANG(.45, 0, math.pi / 2) }
		v.Shell.Size = V3(2.2, 2.2, 2.2) * pulse * (.75 + .25 * hpFrac)
		for _, e in ipairs(v.Ears) do
			table.insert(parts, e.Part)
			table.insert(cfs, face * CF(e.Side * .72, .95, .1) * ANG(0, 0, e.Side * (.35 + .15 * math.sin(t * 3 + v.Seed))))
		end
		for _, e in ipairs(v.Eyes) do
			table.insert(parts, e.Part)
			table.insert(cfs, face * CF(e.Side * .32, .25, -1.02))
		end
		bulk(parts, cfs)
	end
	local function addTarget(part: Instance)
		if tutorialTargets[part] or not part:IsA("BasePart") then
			return
		end
		local kind = part:GetAttribute("Kind")
		if not TUTORIAL_KINDS[kind] or part:GetAttribute("OwnerUserId") ~= player.UserId then
			return
		end
		local rec: any = { Kind = kind, Part = part }
		tutorialTargets[part] = rec
		if kind == "UyTutorialEcho" then
			rec.Visual = echoVisual(part :: BasePart)
			pcall(function()
				FX.Burst((part :: BasePart).Position, { Color = C3(150, 200, 255), Count = 12, Speed = { 2, 5 }, Lifetime = { .4, .8 }, Size = { .25, .4, 0 } })
			end)
		elseif kind == "UyTollBell" then
			local square = root and root:FindFirstChild("BellSquare")
			local ring = square and square:FindFirstChild("PracticeRing")
			local bell = ring and ring:FindFirstChild("HandBell")
			if bell and bell:IsA("Model") then
				local hl = Instance.new("Highlight")
				hl.Name = "UyTollGlow"
				hl.FillColor = C3(255, 206, 110)
				hl.OutlineColor = C3(255, 236, 190)
				hl.FillTransparency = .7
				hl.OutlineTransparency = .2
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.Adornee = bell
				hl.Parent = fxFolder
				rec.Highlight = hl
			end
		elseif kind == "UyMournerWeak" then
			dummyState.Weak = true
			dummyState.GlowTo = 2
			act("Open", .6, math.huge)
			pcall(Audio.Play, "WeakOpen", (part :: BasePart).Position, { Volume = .8 })
		end
	end
	local function removeTarget(part: Instance)
		local rec = tutorialTargets[part]
		if not rec then
			return
		end
		tutorialTargets[part] = nil
		local reason = part:GetAttribute("EndReason")
		if rec.Visual then
			local pos = rec.Visual.Core.Position
			rec.Visual.Model:Destroy()
			if reason == "Broke" then
				pcall(function()
					FX.Burst(pos, { Color = C3(150, 200, 255), Color2 = C3(200, 160, 255), Count = 26, Speed = { 4, 10 }, Lifetime = { .5, 1.1 },
						Size = { .3, .5, 0 } })
					FX.Ring(V3(pos.X, Layout.Floor + .2, pos.Z), C3(150, 200, 255), 6, .7)
				end)
				pcall(Audio.Play, "SoulBurst", pos, { Volume = .7, Pitch = 1.2 })
			end
		end
		if rec.Highlight then
			rec.Highlight:Destroy()
		end
		if rec.Kind == "UyMournerWeak" then
			dummyState.Weak = false
			dummyState.GlowTo = 1
			if reason == "Won" then
				act("Defeat", 1.3, 5)
			else
				act("Idle", .5, 0)
			end
		end
	end
	local function tutorialStep(t: number)
		for part, rec in pairs(tutorialTargets) do
			if not part.Parent then
				removeTarget(part)
			elseif rec.Visual then
				pcall(poseEcho, rec.Visual, t)
			end
		end
	end
	table.insert(conns, CollectionService:GetInstanceAddedSignal("HalloweenTarget"):Connect(function(part)
		pcall(addTarget, part)
	end))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal("HalloweenTarget"):Connect(function(part)
		pcall(removeTarget, part)
	end))
	for _, part in ipairs(CollectionService:GetTagged("HalloweenTarget")) do
		pcall(addTarget, part)
	end

	---------------------------------------------------------------------------------------------------------------
	-- district banner
	---------------------------------------------------------------------------------------------------------------
	local districtSeal: { [string]: number } = {}
	if C2Cfg and C2Cfg.Seals then
		for i, s in ipairs(C2Cfg.Seals) do
			if type(s.District) == "string" and not districtSeal[s.District] then
				districtSeal[s.District] = i
			end
		end
	end
	local banner: any = nil
	local lastDistrict = ""
	local arrivalAt = -1e9
	local bannerToken = 0
	local function bannerBlocked(): boolean
		local g = gui()
		if not g then
			return false
		end
		return g:GetAttribute("CinemaActive") == true or g:GetAttribute("OpenMenu") ~= nil or g:GetAttribute("UIHidden") == true
	end
	local function showBanner(district: string)
		local names = Layout.Names[district]
		if not names or bannerBlocked() then
			return
		end
		bannerToken += 1
		local token = bannerToken
		pcall(function()
			if banner then
				banner:Destroy()
				banner = nil
			end
			local pg = player:FindFirstChildOfClass("PlayerGui")
			if not pg then
				return
			end
			local sg = Instance.new("ScreenGui")
			sg.Name = "DOGROTS_UnderyardBanner"
			sg.DisplayOrder = 42
			sg.ResetOnSpawn = false
			sg.IgnoreGuiInset = true
			pcall(function()
				sg.ScreenInsets = Enum.ScreenInsets.None
			end)
			sg:SetAttribute("HideWithUI", true)
			sg:SetAttribute("NoTranslate", true)
			local seal = districtSeal[district]
			local open = R.GateOpen(district, cleared, assault)
			local sub
			if seal and C2Cfg then
				local s = C2Cfg.Seals[seal]
				if open then
					sub = string.format(T("SEAL %s · %s"), ROMAN[seal] or tostring(seal), pair(s.Title))
				else
					sub = string.format(T("SEALED · BELL SEAL %s"), ROMAN[Layout.Unlock[district] or seal] or tostring(seal))
				end
			end
			local top = 0.16
			local g = gui()
			local stripBottom = g and tonumber(g:GetAttribute("HwStripBottom"))
			local frame = Instance.new("Frame")
			frame.Name = "Banner"
			frame.AnchorPoint = Vector2.new(.5, 0)
			frame.BackgroundTransparency = 1
			frame.Size = UDim2.new(.9, 0, 0, 96)
			frame.Position = stripBottom and UDim2.new(.5, 0, 0, stripBottom + 14) or UDim2.fromScale(.5, top)
			frame.Parent = sg
			local function text(name: string, txt: string, y: number, h: number, color: Color3, size: number): TextLabel
				local l = Instance.new("TextLabel")
				l.Name = name
				l.BackgroundTransparency = 1
				l.AnchorPoint = Vector2.new(.5, 0)
				l.Position = UDim2.new(.5, 0, 0, y)
				l.Size = UDim2.new(1, 0, 0, h)
				l.FontFace = FONT
				l.Text = txt
				l.TextScaled = true
				l.TextColor3 = color
				l.TextStrokeColor3 = INK
				l.TextStrokeTransparency = .35
				l.TextTransparency = 1
				l.TextStrokeTransparency = 1
				l:SetAttribute("NoTranslate", true)
				local c = Instance.new("UITextSizeConstraint")
				c.MaxTextSize = size
				c.MinTextSize = 10
				c.Parent = l
				l.Parent = frame
				return l
			end
			local kicker = text("Kicker", T("THE UNDERYARD"), 0, 18, C3(176, 150, 230), 16)
			local title = text("Title", pair(names), 20, 48, C3(236, 228, 255), 46)
			local subtitle = sub and text("Sub", sub, 70, 22, open and C3(150, 200, 255) or C3(255, 140, 170), 20) or nil
			local lines = {}
			for _, side in ipairs({ -1, 1 }) do
				local ln = Instance.new("Frame")
				ln.Name = "Line"
				ln.BorderSizePixel = 0
				ln.BackgroundColor3 = C3(170, 120, 255)
				ln.BackgroundTransparency = 1
				ln.AnchorPoint = Vector2.new(side < 0 and 1 or 0, .5)
				ln.Position = UDim2.new(.5, side * 130, 0, 44)
				ln.Size = UDim2.fromOffset(0, 2)
				local grad = Instance.new("UIGradient")
				grad.Transparency = NumberSequence.new(side < 0 and 1 or 0, side < 0 and 0 or 1)
				grad.Parent = ln
				ln.Parent = frame
				table.insert(lines, ln)
			end
			sg.Parent = pg
			banner = sg
			local BC = Cfg.Banner
			local function fade(alpha: number, dur: number)
				for _, l in ipairs({ kicker, title, subtitle }) do
					if l then
						TweenService:Create(l, TweenInfo.new(dur, Enum.EasingStyle.Quad), { TextTransparency = alpha, TextStrokeTransparency = alpha > .9 and 1 or .35 })
							:Play()
					end
				end
				for _, ln in ipairs(lines) do
					TweenService:Create(ln, TweenInfo.new(dur, Enum.EasingStyle.Quad),
						{ BackgroundTransparency = alpha > .9 and 1 or .2, Size = UDim2.fromOffset(alpha > .9 and 0 or 150, 2) }):Play()
				end
			end
			if not reduced() then
				frame.Position = frame.Position + UDim2.fromOffset(0, 10)
				TweenService:Create(frame, TweenInfo.new(BC.FadeIn + .3, Enum.EasingStyle.Quad), { Position = frame.Position - UDim2.fromOffset(0, 10) })
					:Play()
			end
			fade(0, BC.FadeIn)
			task.delay(BC.FadeIn + BC.Hold, function()
				if bannerToken == token and sg.Parent then
					fade(1, BC.FadeOut)
					task.delay(BC.FadeOut + .1, function()
						if sg.Parent then
							sg:Destroy()
						end
						if banner == sg then
							banner = nil
						end
					end)
				end
			end)
		end)
	end

	local function onDistrict(district: string)
		if district == lastDistrict then
			return
		end
		local prev = lastDistrict
		lastDistrict = district
		if district == "" or prev == "" then
			return -- arrival / leaving: the portal transition has its own title
		end
		if os.clock() - arrivalAt < Cfg.Banner.AfterArrival then
			return
		end
		showBanner(district)
	end

	---------------------------------------------------------------------------------------------------------------
	-- the loop
	---------------------------------------------------------------------------------------------------------------
	local SC = Cfg.Seal
	local acc = { Move = 0, Flame = 0, Slow = 1, Ambient = 0, Veil = 0, Assert = 0 }
	local lang = Shared.IsRussian()
	local langForceUntil = 0 -- after a language switch: re-localize every pass until Shared's language cache has caught up

	local function step(dt: number)
		local cam = camPos()
		local t = serverNow()
		local q = quality()
		local near = Layout.Weight(cam, AC.Range) > 0
		local inside = Layout.Weight(cam, Cfg.Lighting.Feather) > .5
		-- seal glides (every frame while any runs)
		if next(anim) then
			for rec in pairs(anim) do
				if not rec.Inst.Parent then
					anim[rec] = nil
				else
					local vSpeed = rec.VisTo > rec.Vis and 1 / SC.FadeIn or 1 / SC.Dissolve
					if rec.Vis < rec.VisTo then
						rec.Vis = math.min(rec.VisTo, rec.Vis + dt * vSpeed)
					elseif rec.Vis > rec.VisTo then
						rec.Vis = math.max(rec.VisTo, rec.Vis - dt * vSpeed)
					end
					if rec.Lit < rec.LitTo then
						rec.Lit = math.min(rec.LitTo, rec.Lit + dt / SC.LightRamp)
					elseif rec.Lit > rec.LitTo then
						rec.Lit = math.max(rec.LitTo, rec.Lit - dt / SC.LightRamp)
					end
					write(rec)
					if rec.Vis == rec.VisTo and rec.Lit == rec.LitTo then
						anim[rec] = nil
					end
				end
			end
		end
		-- pending reveal: after the seal-clear cinematic (or its cue), else shortly
		if pending then
			local waited = os.clock() - pending.Since
			if (not cinemaActive() and waited >= SC.Delay) or waited >= SC.CinemaWait then
				revealNow()
			end
		end
		-- 1 Hz housekeeping
		acc.Slow += dt
		if acc.Slow >= 1 then
			acc.Slow = 0
			findRoot()
			local a = assaultState()
			if a ~= assault then
				assault = a
				setCleared(cleared, not ready)
			end
			if near then
				pickFlames(cam)
				gateSigns()
			end
			local ru = Shared.IsRussian()
			if ru ~= lang or os.clock() < langForceUntil then
				lang = ru
				for inst in pairs(texts) do
					if inst.Parent then
						localize(inst)
					end
				end
			end
		end
		pcall(dummyStep, cam, dt)
		if next(tutorialTargets) then
			tutorialStep(os.clock())
		end
		if not near then
			-- far away (the island): ambient life goes, nothing animates
			if next(swarms) or #wisps > 0 or next(ghosts) or (motes and motes.Part.Parent) then
				motesStep(false, cam)
				fogStep(false, cam)
				mothsStep(false, cam, t, false)
				wispsStep(false, cam, t, dt)
				ghostsStep(false, cam, t, dt)
			end
			return
		end
		-- movers
		acc.Move += dt
		local rate = R.Pick(MC.Rate, q)
		if acc.Move >= 1 / rate then
			local mdt = acc.Move
			acc.Move = 0
			local range = R.Pick(MC.Range, q)
			local sky = R.Pick(MC.SkyRange, q)
			local moved = 0
			for _, rec in ipairs(moverList) do
				if rec.Pivot and #rec.Parts > 0 then
					local d = ((rec.Pivot :: CFrame).Position - cam).Magnitude
					local limit = (rec.Kind == "Drift" or rec.Kind == "Moon") and sky or range
					if d <= limit then
						local ok, err = pcall(poseMover, rec, t, cam, mdt)
						if ok then
							moved += 1
						elseif not warned.WarnedMove then
							warned.WarnedMove = true
							warn("UnderyardFX: motion failed: " .. tostring(err))
						end
					end
				elseif not rec.Pivot then
					resolvePivot(rec)
				end
			end
			for _, c in pairs(conveyors) do
				if c.Belt.Parent and (c.Belt.Position - cam).Magnitude <= range then
					pcall(conveyorStep, c, t)
				end
			end
			mothsStep(inside, cam, t, true)
			stats.Moved = moved
		end
		-- flames
		acc.Flame += dt
		if acc.Flame >= 1 / FC.Rate then
			acc.Flame = 0
			flickerStep(t)
		end
		-- veil shimmer (15 Hz) + light re-assert (a world event's BLACKOUT may restore stale brightness)
		acc.Veil += dt
		if acc.Veil >= 1 / 15 then
			acc.Veil = 0
			veilStep(cam, t)
		end
		acc.Assert += dt
		if acc.Assert >= SC.Assert then
			acc.Assert = 0
			for _, rec in pairs(leaves) do
				if rec.Kind == "Light" and rec.Inst.Parent and rec.Written and math.abs((rec.Inst :: any).Brightness - rec.Written) > .01 then
					writeLight(rec)
				end
			end
		end
		-- ambient life (10 Hz bookkeeping, wisps / ghosts animated at the same rate)
		acc.Ambient += dt
		if acc.Ambient >= .1 then
			local adt = acc.Ambient
			acc.Ambient = 0
			motesStep(inside, cam)
			fogStep(inside, cam)
			wispsStep(inside, cam, t, adt)
			ghostsStep(inside, cam, t, adt)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- wiring
	---------------------------------------------------------------------------------------------------------------
	local function stop()
		if not alive then
			return
		end
		alive = false
		started = false
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
		detachRoot()
		for _, sw in pairs(swarms) do
			sw.Model:Destroy()
		end
		table.clear(swarms)
		for _, w in ipairs(wisps) do
			pcall(function()
				w.Rig:Destroy()
			end)
		end
		table.clear(wisps)
		for _, g in pairs(ghosts) do
			pcall(function()
				g.Rig:Destroy()
			end)
		end
		table.clear(ghosts)
		if dummy then
			pcall(function()
				dummy.Rig:Destroy()
			end)
			dummy = nil
		end
		for part in pairs(tutorialTargets) do
			pcall(removeTarget, part)
		end
		mournerApi = nil
		if banner then
			banner:Destroy()
			banner = nil
		end
		fxFolder:Destroy()
	end
	stopFn = stop
	statsFn = function()
		local s = table.clone(stats)
		s.Cleared = cleared
		s.Pending = pending ~= nil
		s.Ready = ready
		s.Assault = assault
		s.Animating = 0
		for _ in pairs(anim) do
			s.Animating += 1
		end
		return s
	end

	table.insert(conns, player:GetAttributeChangedSignal("UySealMask"):Connect(function()
		pcall(onMask)
	end))
	table.insert(conns, player:GetAttributeChangedSignal("DOGROTS_Language"):Connect(function()
		langForceUntil = os.clock() + 6.5 -- the next 1 Hz passes re-localize (Shared.IsRussian caches for 5 s)
	end))
	local busConns = {
		Bus.On("UySealReveal", function()
			pcall(revealNow)
		end),
		Bus.On("UyBellStrike", function(d)
			local s = type(d) == "table" and tonumber(d.Strength) or 1
			for _, rec in ipairs(moverList) do
				if rec.Kind == "Bell" then
					rec.Boost = math.min(MC.Bell.StrikeMax, rec.Boost + (s or 1))
				end
			end
		end),
		Bus.On("UyBellToll", function(d)
			local arena = type(d) == "table" and d.Arena == true
			for _, rec in ipairs(moverList) do
				if (arena and rec.Kind == "Bell") or (not arena and rec.Kind == "TowerBell") then
					rec.Boost = math.min(MC.Bell.StrikeMax, rec.Boost + 1.2)
				end
			end
		end),
		Bus.On("C2Zone", function(d)
			if type(d) == "table" then
				pcall(onDistrict, d.Inside and tostring(d.District or "") or "")
			end
		end),
		Bus.On("C2Signal", function(sig)
			if type(sig) == "table" and sig.Kind == "C2Portal" and type(sig.Data) == "table" and sig.Data.Stage == "Arrived" then
				arrivalAt = os.clock()
				lastDistrict = sig.Data.Dir == "Down" and tostring(sig.Data.District or "BellSquare") or ""
			end
		end),
	}
	table.insert(conns, Players.PlayerRemoving:Connect(function(pl)
		if pl == player then
			for _, c in ipairs(busConns) do
				c.Disconnect()
			end
		end
	end))
	local st = RS.Halloween:FindFirstChild("State")
	if st then
		table.insert(conns, st:GetAttributeChangedSignal("HalloweenChapter2Enabled"):Connect(function()
			if not Shared.Chapter2Enabled() then
				for _, c in ipairs(busConns) do
					c.Disconnect()
				end
				stop()
			end
		end))
	end
	lastDistrict = (player:GetAttribute("UyInZone") == true and tostring(player:GetAttribute("UyDistrict") or "")) or ""
	findRoot()
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		local ok, err = pcall(step, math.min(dt, .25))
		if not ok and not warned.WarnedStep then
			warned.WarnedStep = true
			warn("UnderyardFX step failed: " .. tostring(err))
		end
	end))
end

return M
