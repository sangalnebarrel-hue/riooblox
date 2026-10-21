-- THE REVEAL (StarterPlayerScripts.HalloweenClient.Reveal, WP-F; docs/halloween2/DESIGN.md §6, §16.2, §24.3).
-- "И ЭТО ВСЁ?" → the church → the portal. Client presentation only: the server owns every flag (C2Notified,
-- C2RevealSeen) and every teleport; this module shows what the player's state says and sends the two "I saw it"
-- requests (never for a replay).
--   §6.1 Notification   HalloweenChapter1Complete and not Chapter2Notified (or Signal C2Reveal), not in a menu /
--                       cinematic / timing-hit session / the main tutorial / combat / a trial: own ScreenGui
--                       DOGROTS_Reveal (DisplayOrder 88, built in pcall). Silence (mixer duck "Reveal" = Silence), black,
--                       a sub swell and a distant toll, the typewriter "И ЭТО ВСЁ?" / "IS THAT ALL?" with a heartbeat thud
--                       per word and a violet / blue chromatic jitter, the second line, light cracks from the screen edges,
--                       an eye opening behind the text, the pulsing FIND OUT button (Activated, Enter / ButtonA; Esc /
--                       ButtonB also find out; nothing before 4 s). Controls frozen through GUIIntegration's lock
--                       (reason "Reveal"); the run is a Cinema.Play without a shot, so death, character removal and a
--                       menu end it with the same guaranteed teardown. FIND OUT: a bell-strike flash, the overlay tears
--                       upward, C2Notified, the guide.
--   §6.2 Guide          PathGuide.Show("Church", {Label = false}) + ghost lights along the route (Budget GhostLights:
--                       12 / 8 / 5) + an objective marker over the crypt door; clears on arrival, when the user drops the
--                       route or when the cinematic plays. Bus "C2Objective" {Key = "Church" | "Descend" | nil, Text}.
--   §6.3 Church         first approach within 46 studs while Chapter2RevealSeen ~= true: Cinema.Play (16 s, skippable
--                       after 3 s): silence, three tolls (tower shake, roof dust, the windows dying, the ground cracking),
--                       the doors swing open, the portal, the title card; then C2RevealSeen. The open end state (doors open,
--                       portal visible and alive, cracks glowing, slit dark) persists for players whose Chapter2RevealSeen
--                       is true; everyone else sees the church closed. All of it is client-local (pivots, Transparency).
--   §6.5 Teaser         a closed church within 70 studs: every 45-90 s a quiet toll, violet light breathing through the
--                       slit and "Something is waiting below." over the door; the DESCEND prompt is hidden client-side for
--                       players who have not finished Chapter I.
--   §6.6 Transition     Signal C2Portal {Dir, Stage}: Start = stretch (FOV), vertical squash, colour drain, reverse whoosh,
--                       the eye / moon flash, black (held until Arrived / Failed, watchdog); Arrived = fade in + title
--                       (THE UNDERYARD + district, or THE DEAD YARD).
--   §24.3 Replays       Bus "C2Replay" {Id = "Reveal" | "Church" | "Portal"}: client-only, no request is ever sent.
-- API (also for tests): Reveal.Start(ctx), Reveal.Notify(opts?), Reveal.PlayChurch(opts?), Reveal.Transition(dir, opts?),
-- Reveal.StartGuide(), Reveal.StopGuide(reason?), Reveal.ApplyChurch(state, force?), Reveal.Tick(), Reveal.State.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Rules = require(Halloween:WaitForChild("RevealRules"))

local Reveal = {}
Reveal.Rules = Rules
local C = Rules.Config
local player = Players.LocalPlayer
local ctx: any = nil
local started = false

local C3 = Color3.fromRGB
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local VIOLET = C3(150, 80, 230)
local VIOLET_HOT = C3(196, 140, 255)
local MOON = C3(150, 200, 255)
local BONE = C3(230, 222, 200)
local INK = C3(16, 12, 26)
local DOOR: Vector3 = Rules.Church.Door
local BELL: Vector3 = Rules.Church.Bell
local PORTAL: Vector3 = Rules.PortalCentre

-- everything the module keeps between frames (read by tests)
local State: any = {
	Note = { Showing = false, StableSince = nil, Shown = 0 },
	Scene = { Playing = false, Pending = false, CooldownUntil = 0, Replay = false },
	Guide = { Active = false, Mode = nil },
	Teaser = { NextAt = nil, Playing = false },
	Portal = { Active = false },
	Church = { Applied = nil, Doors = 0, Portal = 0, Cracks = 0, Glow = 1, Slit = 1 },
}
Reveal.State = State

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("Reveal: " .. msg)
	end
end
local function safe(key: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, tostring(err))
	end
	return ok
end

-- Russian: Localization.Reveal first, then Localization.Underyard (server replies such as "Watch the church first")
local locs: { any }? = nil
local function T(en: string): string
	if not Shared.IsRussian() then
		return en
	end
	if locs == nil then
		local list = {}
		for _, name in ipairs({ "Reveal", "Underyard" }) do
			local ok, m = pcall(function()
				local folder = RS:FindFirstChild("Localization")
				local inst = folder and folder:FindFirstChild(name)
				return inst and require(inst :: any)
			end)
			if ok and type(m) == "table" and type(m.Translate) == "function" then
				table.insert(list, m)
			end
		end
		locs = list
	end
	for _, m in ipairs(locs :: { any }) do
		local ok, ru = pcall(m.Translate, en, "ru")
		if ok and type(ru) == "string" then
			return ru
		end
	end
	return en
end
local function Lp(pair: any): string
	if type(pair) == "table" then
		return Shared.L(pair[1] or "", pair[2])
	end
	return tostring(pair or "")
end
local function metres(studs: number): string
	return string.format(Shared.IsRussian() and "%d м" or "%d m", math.max(0, math.floor(studs + .5)))
end

local function reduced(): boolean
	return Shared.ReducedMotion()
end
local function quality(): string
	return Shared.Quality()
end
local function smooth(x: number): number
	return Rules.Smooth(x)
end
local function tween(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(math.max(0, seconds), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

-- one write for many anchored parts (absolute CFrames, so nothing drifts however often it runs)
local function moveParts(parts: { BasePart }, cfs: { CFrame })
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

local function module(name: string): any
	local m = ctx and ctx.Modules and ctx.Modules[name]
	if m then
		return m
	end
	local inst = script.Parent:FindFirstChild(name)
	if inst then
		local ok, value = pcall(require, inst)
		if ok then
			return value
		end
	end
	return nil
end
local function cinema(): any
	return module("Cinema")
end
local function cs(): any
	return module("Chapter2State")
end
local mixerMod: any = nil
local function mixer(): any
	if mixerMod == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("AudioMixer", 5) :: any)
		end)
		mixerMod = ok and type(m) == "table" and m or false
	end
	return mixerMod or nil
end
local pathMod: any = nil
local function pathGuide(): any
	if pathMod == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("Navigation", 5):WaitForChild("PathGuide", 5) :: any)
		end)
		pathMod = ok and type(m) == "table" and m or false
	end
	return pathMod or nil
end
local function audio(): any
	return ctx and ctx.Audio or nil
end
local function play(cue: string, where: any?, opts: { [string]: any }?)
	local a = audio()
	if a and a.Play and (not a.Has or a.Has(cue)) then
		a.Play(cue, where, opts)
	end
end
local function fxFolder(): Instance
	local fx = ctx and ctx.FX
	if fx and fx.Folder then
		return fx.Folder()
	end
	return workspace
end

local function playerGui(): PlayerGui?
	return player and player:FindFirstChildOfClass("PlayerGui")
end
local function mainGui(): ScreenGui?
	local pg = playerGui()
	local g = pg and pg:FindFirstChild("ScreenGui")
	return (g and g:IsA("ScreenGui")) and g or nil
end
local navMod: any = nil
local function nav(): any
	if navMod then
		return navMod
	end
	local g = mainGui()
	local modules = g and g:FindFirstChild("Modules")
	local inst = modules and modules:FindFirstChild("GUIIntegration")
	if inst then
		local ok, m = pcall(require, inst)
		if ok and type(m) == "table" and type(m.LockControls) == "function" then
			navMod = m
		end
	end
	return navMod
end
-- a ref-counted movement lock: GUIIntegration's (it never fights a menu), Cinema's as the fallback. -> unlock()
local function lockControls(reason: string): () -> ()
	local n = nav()
	if n then
		pcall(n.LockControls, reason)
		local done = false
		return function()
			if not done then
				done = true
				pcall(n.UnlockControls, reason)
			end
		end
	end
	local cin = cinema()
	if cin and cin.LockControls then
		cin.LockControls(reason)
		local done = false
		return function()
			if not done then
				done = true
				cin.Unlock(reason)
			end
		end
	end
	return function() end
end

local function root(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end
local function humanoid(): Humanoid?
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end
local function churchDistance(): number?
	local r = root()
	if not r then
		return nil
	end
	local p = r.Position
	return (Vector3.new(p.X, DOOR.Y, p.Z) - DOOR).Magnitude + math.max(0, math.abs(p.Y - DOOR.Y) - 12)
end

local function toast(en: string, kind: string?)
	Bus.Fire("Toast", { Text = T(en), Kind = kind or "info", NoTranslate = true })
end

-- player-state readers (Chapter2State when present, the replicated attributes otherwise)
local function enabled(): boolean
	return Shared.Chapter2Enabled()
end
local function eligible(): boolean
	local s = cs()
	if s and s.Eligible then
		return s.Eligible() == true
	end
	return player:GetAttribute("HalloweenChapter1Complete") == true
end
local function revealSeen(): boolean
	local s = cs()
	if s and s.RevealSeen then
		return s.RevealSeen() == true
	end
	return player:GetAttribute("Chapter2RevealSeen") == true
end
local function notified(): boolean
	local s = cs()
	if s and s.Notified then
		return s.Notified() == true
	end
	return player:GetAttribute("Chapter2Notified") == true
end
local function entered(): boolean
	local s = cs()
	if s and s.Entered then
		return s.Entered() == true
	end
	return player:GetAttribute("Chapter2Entered") == true
end
local function request(action: string, args: any?): (boolean, any)
	local s = cs()
	if s and s.Request then
		return s.Request(action, args)
	end
	local st = ctx and ctx.State
	if st and st.Request then
		return st.Request(action, args)
	end
	return false, "Not ready"
end

-- the screen-level blockers of the notification (menus, cinematics, overlays, mining, the tutorial, combat, trials)
local OVERLAYS = { "DOGROTS_HalloweenReward", "DOGROTS_HalloweenCinema", "DOGROTS_Cinema", "LabPresentation" }
local function overlayUp(): boolean
	local pg = playerGui()
	if not pg then
		return false
	end
	for _, name in ipairs(OVERLAYS) do
		local g = pg:FindFirstChild(name)
		if g and g:IsA("LayerCollector") and g.Enabled then
			return true
		end
	end
	return false
end
local function environment(): { [string]: any }
	local g = mainGui()
	local hum = humanoid()
	local cin = cinema()
	return {
		Menu = g ~= nil and (g:GetAttribute("OpenMenu") ~= nil or (tonumber(g:GetAttribute("ModalOwnerCount")) or 0) > 0),
		Cinema = (g ~= nil and g:GetAttribute("CinemaActive") == true) or (cin ~= nil and cin.Busy and cin.Busy() == true)
			or State.Scene.Playing or State.Portal.Active,
		Mining = g ~= nil and g:GetAttribute("MiningActive") == true,
		Tutorial = player:GetAttribute("TutorialActive") == true,
		Dead = hum == nil or hum.Health <= 0,
		Combat = player:GetAttribute("HwCombat") == true or player:GetAttribute("HwDowned") == true,
		Trial = (player:GetAttribute("UyTrial") or "") ~= "",
		Overlay = overlayUp(),
	}
end

local function newGui(name: string, order: number): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.DisplayOrder = order
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.None
	end)
	g:SetAttribute("NoTranslate", true)
	g:SetAttribute("CinemaKeep", true)
	g:SetAttribute("HideWithUI", false)
	return g
end
local function frame(parent: Instance, name: string, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Active = false
	for k, v in pairs(props or {}) do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end
local function round(parent: Instance, scale: number?, offset: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0, offset or 0)
	c.Parent = parent
	return c
end
local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function text(parent: Instance, name: string, props: { [string]: any }?, maxSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = FONT
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = BONE
	l.Active = false
	l:SetAttribute("NoTranslate", true)
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	if maxSize then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = maxSize
		c.MinTextSize = 10
		c.Parent = l
	end
	l.Parent = parent
	return l
end

---------------------------------------------------------------------------------------------------------------------
-- the church in the world (38_DeadYard.Church, tools/edits/38_church.luau): cached part lists, rebuilt on stream-in
---------------------------------------------------------------------------------------------------------------------
local cache: any = { Root = nil }
local function deadYard(): Instance?
	local d = workspace:FindFirstChild("DOGROTS_District")
	return d and d:FindFirstChild("38_DeadYard")
end

local function buildCache(churchRoot: Instance): any
	local c: any = { Root = churchRoot, Doors = {}, Portal = nil, PortalParts = {}, PortalLights = {}, Rings = {}, Pupil = nil,
		Cracks = {}, Slit = {}, SlitLights = {}, SealRunes = {}, Dust = {}, Fog = {}, Sig = 0 }
	for _, name in ipairs({ "ChurchDoorL", "ChurchDoorR" }) do
		local m = churchRoot:FindFirstChild(name)
		if m and m:IsA("Model") then
			local closed = m:GetAttribute("ClosedPivot")
			if typeof(closed) ~= "CFrame" then
				closed = m:GetPivot()
			end
			-- every part's offset from the hinge (a rigid model: valid whatever the doors' state is now)
			local primary = m.PrimaryPart
			local base = primary and primary.CFrame or m:GetPivot()
			local rec = { Model = m, Closed = closed, Angle = tonumber(m:GetAttribute("OpenAngle")) or 0, Parts = {}, Rel = {} }
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(rec.Parts, d)
					table.insert(rec.Rel, base:ToObjectSpace(d.CFrame))
					if d:GetAttribute("SealRune") then
						table.insert(c.SealRunes, { Part = d, Color = d.Color })
					end
				end
			end
			table.insert(c.Doors, rec)
		end
	end
	local portal = churchRoot:FindFirstChild("ChurchPortal")
	if portal then
		c.Portal = portal
		local centre = portal:GetAttribute("Centre")
		c.Centre = typeof(centre) == "Vector3" and centre or PORTAL
		local frameCF = CFrame.new(c.Centre)
		for _, d in ipairs(portal:GetDescendants()) do
			if d:IsA("BasePart") then
				local t = tonumber(d:GetAttribute("RevealT"))
				if t then
					table.insert(c.PortalParts, { Part = d, T = t })
				end
				if d.Name == "PortalPupil" then
					c.Pupil = d:FindFirstChildOfClass("SpecialMesh")
				end
			elseif d:IsA("Light") then
				table.insert(c.PortalLights, { Light = d, B = tonumber(d:GetAttribute("RevealBrightness")) or 1 })
			end
		end
		for _, ring in ipairs(portal:GetChildren()) do
			local spin = ring:GetAttribute("Spin")
			if ring:IsA("Model") and type(spin) == "number" then
				local rec = { Spin = spin, Wobble = tonumber(ring:GetAttribute("Wobble")) or 0, Parts = {}, Rel = {} }
				for _, d in ipairs(ring:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(rec.Parts, d)
						table.insert(rec.Rel, frameCF:ToObjectSpace(d.CFrame))
					end
				end
				table.insert(c.Rings, rec)
			end
		end
		c.FrameCF = frameCF
	end
	local cracks = churchRoot:FindFirstChild("ChurchCracks")
	if cracks then
		for _, d in ipairs(cracks:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(c.Cracks, { Part = d, T = tonumber(d:GetAttribute("RevealT")) or 0, At = tonumber(d:GetAttribute("CrackT")) or 0,
					Glow = d.Name == "CrackGlow" })
			end
		end
	end
	for _, d in ipairs(churchRoot:GetChildren()) do
		if d:IsA("BasePart") and d:GetAttribute("ChurchSlit") then
			table.insert(c.Slit, { Part = d, T = tonumber(d:GetAttribute("RevealT")) or .25, Color = d.Color })
			for _, l in ipairs(d:GetChildren()) do
				if l:IsA("Light") then
					table.insert(c.SlitLights, { Light = l, B = tonumber(l:GetAttribute("RevealBrightness")) or 1.5 })
				end
			end
		end
	end
	local fxModel = churchRoot:FindFirstChild("ChurchFX")
	if fxModel then
		for _, d in ipairs(fxModel:GetDescendants()) do
			if d:IsA("Attachment") then
				if d.Name == "ChurchDust" then
					table.insert(c.Dust, d)
				elseif d.Name == "ChurchFog" then
					table.insert(c.Fog, d)
				end
			end
		end
	end
	c.Sig = #c.Doors * 1000 + #c.PortalParts + #c.Cracks * 7 + #c.Slit * 13
	return c
end

-- the cache for the church that is streamed in now (nil parts while it is not)
local function church(): any
	local yard = deadYard()
	local r = yard and yard:FindFirstChild("Church")
	if not r then
		if cache.Root then
			cache = { Root = nil }
			State.Church.Applied = nil
		end
		return cache
	end
	local portal = r:FindFirstChild("ChurchPortal")
	local doorL = r:FindFirstChild("ChurchDoorL")
	if cache.Root ~= r or cache.Portal ~= portal or (cache.Doors[1] and cache.Doors[1].Model ~= doorL) or (doorL and not cache.Doors[1]) then
		cache = buildCache(r)
		State.Church.Applied = nil
	end
	return cache
end

local function setDoors(f: number)
	local c = church()
	local parts, cfs = {}, {}
	for _, d in ipairs(c.Doors or {}) do
		if d.Model.Parent then
			local pivot = Rules.DoorPivot(d.Closed, d.Angle, f)
			for i, p in ipairs(d.Parts) do
				if p.Parent then
					table.insert(parts, p)
					table.insert(cfs, pivot * d.Rel[i])
				end
			end
		end
	end
	safe("doors", moveParts, parts, cfs)
	State.Church.Doors = f
end

-- 0..1: how visible the portal is (parts at their RevealT, lights at their RevealBrightness x pulse)
local function setPortal(a: number, pulse: number?)
	local c = church()
	for _, rec in ipairs(c.PortalParts or {}) do
		local p = rec.Part
		if p.Parent then
			p.Transparency = 1 - (1 - rec.T) * a
		end
	end
	for _, rec in ipairs(c.PortalLights or {}) do
		if rec.Light.Parent then
			rec.Light.Brightness = rec.B * a * (pulse or 1)
		end
	end
	State.Church.Portal = a
end

-- progress 0..1 of the spread, glow = brightness share of the glowing strips (the lasting state glows a little less)
local function setCracks(progress: number, glow: number?)
	local c = church()
	local g = glow or 1
	for _, rec in ipairs(c.Cracks or {}) do
		local p = rec.Part
		if p.Parent then
			local a = Rules.CrackAlpha(rec.At, progress)
			p.Transparency = 1 - (1 - rec.T) * a * (rec.Glow and g or 1)
		end
	end
	State.Church.Cracks = progress
	State.Church.Glow = g
end

-- the slit: a = 0..1 presence, breath = 0..1 extra brightness (teaser)
local function setSlit(a: number, breath: number?)
	local c = church()
	local b = breath or 0
	for _, rec in ipairs(c.Slit or {}) do
		local p = rec.Part
		if p.Parent then
			if a <= 0 then
				p.Transparency = 1
			else
				p.Transparency = 1 - (1 - rec.T * (1 - b)) * a
				p.Color = rec.Color:Lerp(VIOLET_HOT, b * .8)
			end
		end
	end
	for _, rec in ipairs(c.SlitLights or {}) do
		if rec.Light.Parent then
			rec.Light.Brightness = rec.B * b * a
		end
	end
	for _, rec in ipairs(c.SealRunes or {}) do
		if rec.Part.Parent then
			rec.Part.Color = rec.Color:Lerp(VIOLET_HOT, b * a)
		end
	end
	State.Church.Slit = a
end

-- the lasting per-player end state ("Open" | "Closed"); force = re-apply although nothing changed
function Reveal.ApplyChurch(state: string, force: boolean?)
	local c = church()
	if not c.Root then
		return
	end
	local key = state .. ":" .. tostring(c.Sig)
	if not force and State.Church.Applied == key then
		return
	end
	State.Church.Applied = key
	if state == "Open" then
		setDoors(1)
		setPortal(1)
		setCracks(1, C.Church.CracksSettled)
		setSlit(0)
	else
		setDoors(0)
		setPortal(0)
		setCracks(0)
		setSlit(1)
	end
end

-- the DESCEND prompt (server-created on 38_DeadYard.Anchors.Portal), hidden locally for players who may not use it
local function updatePrompt(visible: boolean)
	local yard = deadYard()
	local anchors = yard and yard:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild("Portal")
	if not anchor then
		return
	end
	for _, d in ipairs(anchor:GetChildren()) do
		if d:IsA("ProximityPrompt") and d.Enabled ~= visible then
			d.Enabled = visible
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the open church's life: spinning rings, the swirl, the breathing light, the blinking pupil, the hum
---------------------------------------------------------------------------------------------------------------------
local life: any = { Last = 0, Hum = nil, Blink = 0, NextBlink = 0, Moved = false }
local function restoreRings()
	local c = church()
	if not life.Moved or not c.FrameCF then
		return
	end
	life.Moved = false
	local parts, cfs = {}, {}
	for _, ring in ipairs(c.Rings or {}) do
		for i, p in ipairs(ring.Parts) do
			if p.Parent then
				table.insert(parts, p)
				table.insert(cfs, c.FrameCF * ring.Rel[i])
			end
		end
	end
	safe("rings", moveParts, parts, cfs)
end

local function stepLife(now: number)
	local c = church()
	local visible = State.Church.Portal > .01 and c.FrameCF ~= nil
	local cam = workspace.CurrentCamera
	local near = visible and cam ~= nil and (cam.CFrame.Position - c.Centre).Magnitude < 220
	-- the hum (only near; every client its own loop)
	local r = root()
	local close = visible and r ~= nil and (r.Position - c.Centre).Magnitude < 70
	if close and not life.Hum then
		local a = audio()
		if a and a.Loop and (not a.Has or a.Has("PortalHum")) then
			life.Hum = a.Loop("PortalHum", c.Centre, { Volume = .9 })
		end
	elseif not close and life.Hum then
		life.Hum:Stop(1.2)
		life.Hum = nil
	end
	if not near then
		restoreRings()
		return
	end
	local q = quality()
	local interval = q == "Low" and 1 / 15 or q == "Medium" and 1 / 30 or 0
	if now - life.Last < interval then
		return
	end
	life.Last = now
	local still = reduced()
	-- light pulse (always; gentle)
	local pulse = still and 1 or (.78 + .3 * math.sin(now * 2.3) + .06 * math.sin(now * 7.1))
	for _, rec in ipairs(c.PortalLights or {}) do
		if rec.Light.Parent then
			rec.Light.Brightness = rec.B * State.Church.Portal * pulse
		end
	end
	if still then
		restoreRings()
		return
	end
	-- rings and swirl round the portal axis
	local parts, cfs = {}, {}
	for _, ring in ipairs(c.Rings) do
		local spin = ring.Spin
		if q == "Low" and math.abs(spin) < 1 then
			continue -- Low: only the swirl turns
		end
		local rot = CFrame.Angles(ring.Wobble * math.sin(now * .7), ring.Wobble * math.cos(now * .53), now * spin)
		local base = c.FrameCF * rot
		for i, p in ipairs(ring.Parts) do
			if p.Parent then
				table.insert(parts, p)
				table.insert(cfs, base * ring.Rel[i])
			end
		end
	end
	if #parts > 0 then
		life.Moved = true
		safe("spin", moveParts, parts, cfs)
	end
	-- the pupil blinks now and then
	local pupil = c.Pupil
	if pupil and pupil.Parent then
		if now >= life.NextBlink then
			life.Blink = now
			life.NextBlink = now + 4 + (math.sin(now * 12.9898) * .5 + .5) * 6
		end
		local b = now - life.Blink
		local open = b < .22 and math.abs(b - .11) / .11 or 1
		pupil.Scale = Vector3.new(1, math.max(.08, open), 1)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- §6.1 THE NOTIFICATION
---------------------------------------------------------------------------------------------------------------------
local function notifyTeardown(n: any)
	if n.Done then
		return
	end
	n.Done = true
	for _, conn in ipairs(n.Conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(n.Conns)
	if n.Unlock then
		n.Unlock()
	end
	local m = mixer()
	if m then
		pcall(m.Release, "Reveal", 1.6)
	end
	if n.Swell then
		pcall(function()
			n.Swell:Stop(1)
		end)
	end
	if n.Gui then
		pcall(function()
			n.Gui:Destroy()
		end)
	end
	State.Note.Showing = false
	State.Note.Current = nil
end

-- an almond eye outline from neon strokes (upper + lower lid arcs, each a glow and a core line): Set(open 0..1, alpha)
-- moves the lids apart from the middle line; lashes stand on the upper lid
local ALMOND_SEGMENTS = 14
local function almond(parent: Instance, w: number, h: number, color: Color3, core: Color3, thick: number, z: number, lashes: number?): any
	local holder = frame(parent, "Almond", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(w, h),
		ZIndex = z })
	local segs = {}
	for side = -1, 1, 2 do
		for i = 1, ALMOND_SEGMENTS do
			local glow = frame(holder, "LidGlow", { AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = color, BackgroundTransparency = 1, ZIndex = z })
			round(glow, 1)
			local line = frame(holder, "Lid", { AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = core, BackgroundTransparency = 1, ZIndex = z + 1 })
			round(line, 1)
			table.insert(segs, { Side = side, I = i, Glow = glow, Line = line })
		end
	end
	local rays = {}
	for i = 1, lashes or 0 do
		local ray = frame(holder, "Lash", { AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = color, BackgroundTransparency = 1, ZIndex = z })
		round(ray, 1)
		table.insert(rays, ray)
	end
	local function lid(x: number, open: number, side: number): number
		local u = math.clamp(2 * x / w, -1, 1)
		return h / 2 + side * (h / 2) * open * (1 - u * u) ^ .85
	end
	local eye: any = { Holder = holder, Segs = segs, Rays = rays }
	function eye.Set(open: number, alpha: number)
		local a = math.clamp(alpha, 0, 1)
		for _, sg in ipairs(segs) do
			local x0 = -w / 2 + w * (sg.I - 1) / ALMOND_SEGMENTS
			local x1 = -w / 2 + w * sg.I / ALMOND_SEGMENTS
			local p0 = Vector2.new(x0 + w / 2, lid(x0, open, sg.Side))
			local p1 = Vector2.new(x1 + w / 2, lid(x1, open, sg.Side))
			local d = p1 - p0
			local mid = (p0 + p1) / 2
			local rot = math.deg(math.atan2(d.Y, d.X))
			local len = d.Magnitude + thick
			sg.Line.Position = UDim2.fromOffset(mid.X, mid.Y)
			sg.Line.Size = UDim2.fromOffset(len, thick)
			sg.Line.Rotation = rot
			sg.Line.BackgroundTransparency = 1 - .85 * a
			sg.Glow.Position = UDim2.fromOffset(mid.X, mid.Y)
			sg.Glow.Size = UDim2.fromOffset(len + thick * 2, thick * 4)
			sg.Glow.Rotation = rot
			sg.Glow.BackgroundTransparency = 1 - .3 * a
		end
		local n = #rays
		for i, ray in ipairs(rays) do
			-- lashes along the middle of the upper lid, along its outward normal
			local x = (i - (n + 1) / 2) / n * w * .62
			local y = lid(x, open, -1)
			local dx = 1
			local dy = lid(x + 1, open, -1) - y
			local nx, ny = dy, -dx
			local m = math.sqrt(nx * nx + ny * ny)
			nx, ny = nx / m, ny / m
			if ny > 0 then
				nx, ny = -nx, -ny
			end
			local len = h * (.16 + .05 * (1 - math.abs(i - (n + 1) / 2) / n)) * open
			local cx, cy = w / 2 + x + nx * (len / 2 + thick), y + ny * (len / 2 + thick)
			ray.Position = UDim2.fromOffset(cx, cy)
			ray.Size = UDim2.fromOffset(math.max(2, thick * .8), math.max(1, len))
			ray.Rotation = math.deg(math.atan2(nx, -ny))
			ray.BackgroundTransparency = 1 - .55 * a * math.clamp((open - .6) / .4, 0, 1)
		end
	end
	eye.Set(0, 0)
	return eye
end

-- the eye behind the text (faint): the almond outline, an iris with the moon-blue rim, the slit pupil, a glint; the
-- iris is clipped by a box that opens with the lids
local function buildEye(parent: Instance, w: number, h: number): any
	local outline = almond(parent, w, h, VIOLET, VIOLET_HOT, math.max(2, math.floor(h / 70)), 2, 7)
	outline.Holder.Position = UDim2.fromScale(.5, .45)
	local box = frame(parent, "Eye", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .45), Size = UDim2.fromOffset(w, 0),
		ClipsDescendants = true, ZIndex = 2 })
	local irisD = math.floor(h * .78)
	local iris = frame(box, "Iris", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(irisD, irisD),
		BackgroundColor3 = C3(74, 34, 128), BackgroundTransparency = .74, ZIndex = 2 })
	round(iris, 1)
	stroke(iris, MOON, 2, .6)
	local ring = frame(box, "IrisRing", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
		Size = UDim2.fromOffset(math.floor(irisD * .66), math.floor(irisD * .66)), BackgroundTransparency = 1, ZIndex = 2 })
	round(ring, 1)
	stroke(ring, VIOLET_HOT, 2, .7)
	local pupil = frame(box, "Pupil", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
		Size = UDim2.fromOffset(math.max(6, math.floor(irisD * .18)), math.floor(irisD * .82)), BackgroundColor3 = C3(6, 2, 12),
		BackgroundTransparency = .5, ZIndex = 3 })
	round(pupil, 1)
	local glint = frame(box, "Glint", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, math.floor(irisD * .2), .5, -math.floor(irisD * .22)),
		Size = UDim2.fromOffset(math.max(4, math.floor(irisD * .08)), math.max(4, math.floor(irisD * .08))), BackgroundColor3 = BONE,
		BackgroundTransparency = .65, ZIndex = 3 })
	round(glint, 1)
	local eye: any = { Box = box, H = h, W = w, Outline = outline, Last = -1 }
	function eye.Set(open: number)
		if math.abs(open - eye.Last) < .002 then
			return
		end
		eye.Last = open
		box.Size = UDim2.fromOffset(w, math.floor(h * open))
		outline.Set(open, math.clamp(open * 3, 0, 1) * .55) -- faint: the words stay in front
	end
	return eye
end

-- light cracks from the screen edges (RevealRules.EdgeCracks): every segment a core line + a soft glow, grown in order
local function buildCracks(parent: Instance, size: Vector2): { any }
	local holder = frame(parent, "Cracks", { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local segs = {}
	local list = Rules.EdgeCracks(1031, C.Notify.Cracks)
	for _, crack in ipairs(list) do
		local pts = crack.Points
		local n = #pts - 1
		for k = 1, n do
			local a = Vector2.new(pts[k][1] * size.X, pts[k][2] * size.Y)
			local b = Vector2.new(pts[k + 1][1] * size.X, pts[k + 1][2] * size.Y)
			local d = b - a
			local len = d.Magnitude
			if len > 1 then
				local rot = math.deg(math.atan2(d.Y, d.X))
				local glow = frame(holder, "CrackGlow", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(0, crack.Width * 4.5),
					BackgroundColor3 = VIOLET, BackgroundTransparency = 1, Rotation = rot, ZIndex = 3 })
				round(glow, 1)
				local core = frame(holder, "Crack", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(0, crack.Width),
					BackgroundColor3 = C3(240, 228, 255), BackgroundTransparency = 1, Rotation = rot, ZIndex = 4 })
				table.insert(segs, { A = a, Dir = d.Unit, Len = len, W = crack.Width, Glow = glow, Core = core,
					Start = crack.Delay + (k - 1) / n * .7, Dur = .7 / n + .05 })
			end
		end
	end
	return segs
end
local function growCracks(segs: { any }, t: number, alpha: number)
	for _, s in ipairs(segs) do
		local k = math.clamp((t - s.Start) / s.Dur, 0, 1)
		if k <= 0 then
			s.Core.BackgroundTransparency = 1
			s.Glow.BackgroundTransparency = 1
		else
			local len = s.Len * k
			local mid = s.A + s.Dir * (len / 2)
			s.Core.Position = UDim2.fromOffset(mid.X, mid.Y)
			s.Core.Size = UDim2.fromOffset(len, s.W)
			s.Glow.Position = UDim2.fromOffset(mid.X, mid.Y)
			s.Glow.Size = UDim2.fromOffset(len + s.W * 2, s.W * 4.5)
			s.Core.BackgroundTransparency = 1 - .95 * alpha
			s.Glow.BackgroundTransparency = 1 - .38 * alpha
		end
	end
end

local function inputHint(): string
	if UserInputService.GamepadEnabled and not UserInputService.TouchEnabled then
		return T("PRESS (A)")
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return T("TAP THE BUTTON")
	end
	return T("PRESS ENTER")
end

local startGuide: (boolean?) -> ()

-- shows the notification; opts {Replay = true}: from the Journal (no request, no guide). -> started
function Reveal.Notify(opts: { [string]: any }?): boolean
	local o = opts or {}
	if State.Note.Showing then
		return false
	end
	local cin = cinema()
	local n: any = { Conns = {}, Done = false, Replay = o.Replay == true, Pressed = false, Stage = 0, Offset = 0 }
	State.Note.Showing = true
	State.Note.Current = n
	-- the run itself is a Cinema without a shot: CinemaActive (guides pause), the interface hidden, and death,
	-- character removal or a menu end it through one teardown
	if cin and cin.Play then
		local handle, why = cin.Play({
			Id = "Reveal", Duration = C.Notify.AutoPress + 30, Letterbox = false, Skippable = false, LockControls = false, HideUI = true,
			Duck = false, OnDone = function(_ok, reason)
				if not n.Pressed then
					n.Interrupted = reason
				end
				notifyTeardown(n)
			end,
		})
		if not handle then
			State.Note.Showing = false
			State.Note.Current = nil
			State.Note.Refused = why
			return false
		end
		n.Handle = handle
	end
	local ok, err = pcall(function()
		local pg = playerGui()
		assert(pg, "no PlayerGui")
		n.Unlock = lockControls("Reveal")
		local m = mixer()
		if m then
			m.Duck("Reveal", "Silence", C.Notify.DuckFade)
		end
		local g = newGui("DOGROTS_Reveal", C.Notify.DisplayOrder)
		n.Gui = g
		g.Parent = pg
		local size = g.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			local cam = workspace.CurrentCamera
			size = cam and cam.ViewportSize or Vector2.new(1280, 720)
		end
		local phone = math.min(size.X, size.Y) < 500
		local rootF = frame(g, "Root", { Size = UDim2.fromScale(1, 1) })
		n.Root = rootF
		-- the black (a button: it sinks taps while up and skips the typing after 4 s)
		local shade = Instance.new("TextButton")
		shade.Name = "Shade"
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.BorderSizePixel = 0
		shade.BackgroundColor3 = C3(4, 2, 8)
		shade.BackgroundTransparency = 1
		shade.Size = UDim2.fromScale(1, 1)
		shade.Selectable = false
		shade.Active = true
		shade.ZIndex = 1
		shade:SetAttribute("NoTranslate", true)
		shade.Parent = rootF
		n.Shade = shade
		-- the torn bottom edge (shows while the overlay tears upward)
		local tear = frame(rootF, "TearEdge", { Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), ZIndex = 1 })
		local teeth = math.ceil(size.X / 34) + 1
		for i = 0, teeth do
			local s = 26 + (i * 37 % 11)
			local tooth = frame(tear, "Tooth", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(i * 34, (i % 3) * 3 - 2),
				Size = UDim2.fromOffset(s, s), Rotation = 45, BackgroundColor3 = C3(4, 2, 8), BackgroundTransparency = 1, ZIndex = 1 })
			tooth:SetAttribute("Tooth", true)
		end
		n.Tear = tear
		-- the eye, the cracks
		local eyeW = math.floor(math.min(size.X * .82, size.Y * 1.35))
		n.Eye = buildEye(rootF, eyeW, math.floor(eyeW * .4))
		n.Cracks = buildCracks(rootF, size)
		-- the line: three copies (violet / blue offsets for the chromatic jitter)
		local main = Rules.Typewriter(T("IS THAT ALL?"))
		n.Type = main
		local big = phone and 76 or 124
		n.Shrink = phone and .24 or .38 -- the big line shrinks less on a small screen
		local function line(name: string, color: Color3, transparency: number, z: number): TextLabel
			return text(rootF, name, { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .45), Size = UDim2.fromScale(.92, phone and .22 or .2),
				Text = T("IS THAT ALL?"), TextColor3 = color, TextTransparency = transparency, MaxVisibleGraphemes = 0, ZIndex = z,
				TextStrokeTransparency = 1 }, big)
		end
		n.ShadowA = line("ShadowA", VIOLET, .8, 5)
		n.ShadowB = line("ShadowB", C3(90, 150, 255), .8, 5)
		n.Word = line("Word", BONE, 0, 6)
		local wordStroke = stroke(n.Word, INK, phone and 2 or 3, .2)
		wordStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		-- one scale for the line and its two chromatic copies
		n.Scales = {}
		for _, l in ipairs({ n.Word, n.ShadowA, n.ShadowB }) do
			local sc = Instance.new("UIScale")
			sc.Parent = l
			table.insert(n.Scales, sc)
		end
		n.Sub = text(rootF, "Line", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, phone and .58 or .6),
			Size = UDim2.fromScale(phone and .9 or .78, phone and .12 or .1), Text = T("Did you really think it would be that easy?"),
			TextColor3 = C3(214, 204, 240), TextTransparency = 1, ZIndex = 6 }, phone and 26 or 44)
		local subStroke = stroke(n.Sub, INK, 2, 1)
		subStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		n.SubStroke = subStroke
		-- FIND OUT
		local bw = math.floor(math.min(380, size.X * .72))
		local holder = frame(rootF, "FindOutHolder", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, phone and .79 or .8),
			Size = UDim2.fromOffset(bw, C.Notify.ButtonHeight), ZIndex = 7, Visible = false })
		local glow = frame(holder, "Glow", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, 26, 1, 26),
			BackgroundColor3 = VIOLET, BackgroundTransparency = .78, ZIndex = 7 })
		round(glow, 0, 26)
		local button = Instance.new("TextButton")
		button.Name = "FindOut"
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = C3(36, 12, 62)
		button.Size = UDim2.fromScale(1, 1)
		button.FontFace = FONT
		button.Text = T("FIND OUT")
		button.TextColor3 = C3(242, 234, 255)
		button.TextScaled = true
		button.Selectable = true
		button.Active = true
		button.ZIndex = 8
		button:SetAttribute("NoTranslate", true)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 14)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.PaddingLeft = UDim.new(0, 18)
		pad.PaddingRight = UDim.new(0, 18)
		pad.Parent = button
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 40
		limit.MinTextSize = 18
		limit.Parent = button
		round(button, 0, 18)
		stroke(button, VIOLET_HOT, 3, 0)
		button.Parent = holder
		n.ButtonScale = Instance.new("UIScale")
		n.ButtonScale.Parent = holder
		n.Button = button
		n.Holder = holder
		n.Glow = glow
		n.Hint = text(rootF, "Hint", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, phone and .79 or .8, C.Notify.ButtonHeight / 2 + 12),
			Size = UDim2.fromOffset(bw, 20), Text = inputHint(), TextColor3 = C3(170, 158, 206), TextTransparency = 1, ZIndex = 7 }, 18)
		n.Flash = frame(rootF, "Flash", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(236, 226, 255), BackgroundTransparency = 1, ZIndex = 20 })
		-- the schedule
		local typeEnd = C.Notify.TypeAt + main.Duration
		n.LineAt = typeEnd + C.Notify.Hold
		n.ButtonAt = n.LineAt + C.Notify.LineFade + C.Notify.ButtonDelay
		n.T0 = os.clock()
		n.Thuds = {}
		table.insert(n.Conns, button.Activated:Connect(function()
			Reveal._Press(n)
		end))
		table.insert(n.Conns, shade.Activated:Connect(function()
			Reveal._Skip(n)
		end))
		table.insert(n.Conns, UserInputService.InputBegan:Connect(function(input)
			local k = input.KeyCode
			if k == Enum.KeyCode.Escape or k == Enum.KeyCode.ButtonB then
				Reveal._Press(n, true)
			elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.Space then
				if n.Stage >= 3 then
					Reveal._Press(n)
				else
					Reveal._Skip(n)
				end
			end
		end))
		table.insert(n.Conns, RunService.Heartbeat:Connect(function()
			local okStep, errStep = pcall(Reveal._Step, n)
			if not okStep then
				warnOnce("notestep", tostring(errStep))
				notifyTeardown(n)
				if n.Handle then
					pcall(n.Handle.Cancel)
				end
			end
		end))
		-- the never-a-dead-end watchdog
		task.delay(C.Notify.AutoPress, function()
			if not n.Done and not n.Pressed then
				Reveal._Press(n)
			end
		end)
	end)
	if not ok then
		warnOnce("notebuild", tostring(err))
		notifyTeardown(n)
		if n.Handle then
			pcall(n.Handle.Cancel)
		end
		return false
	end
	State.Note.Shown += 1
	return true
end

-- skip the typing (after InputAfter): everything up to the button at once
function Reveal._Skip(n: any)
	if n.Done or n.Pressed then
		return
	end
	local t = os.clock() - n.T0 + n.Offset
	if t < C.Notify.InputAfter or n.Stage >= 3 then
		return
	end
	n.Offset += math.max(0, n.ButtonAt - t)
end

function Reveal._Step(n: any)
	if n.Done then
		return
	end
	local N = C.Notify
	local t = os.clock() - n.T0 + n.Offset
	local still = reduced()
	if n.Pressed then
		return
	end
	-- 1. black + silence
	n.Shade.BackgroundTransparency = 1 - smooth(t / N.FadeIn)
	-- 2. the swell and the distant toll
	if t >= N.Swell and not n.Swelled then
		n.Swelled = true
		local a = audio()
		if a and a.Loop and (not a.Has or a.Has("SubSwell")) then
			n.Swell = a.Loop("SubSwell", nil, { Volume = .9 })
		end
		play("BellTollFar", nil, { Group = "Cinema", Volume = .8 })
	end
	-- 3. the typewriter with a thud per word
	local count = 0
	if t >= N.TypeAt then
		local tt = t - N.TypeAt
		for i, step in ipairs(n.Type.Steps) do
			if step.At <= tt then
				count = step.Count
				if step.Thud and not n.Thuds[i] then
					n.Thuds[i] = true
					play("RevealWord", nil, { Volume = 1 })
				end
			end
		end
		n.Stage = math.max(n.Stage, 1)
	end
	n.Word.MaxVisibleGraphemes = count
	n.ShadowA.MaxVisibleGraphemes = count
	n.ShadowB.MaxVisibleGraphemes = count
	-- chromatic jitter
	local jitter = (still or count == 0) and 0 or (t < n.LineAt and 3.2 or 1.6)
	local jx = jitter * math.sin(t * 61.7) + jitter * .5 * math.sin(t * 23.3)
	local jy = jitter * .6 * math.cos(t * 47.3)
	local lineK = smooth((t - n.LineAt) / N.LineFade)
	local y = .45 - .15 * lineK
	n.Word.Position = UDim2.fromScale(.5, y)
	n.ShadowA.Position = UDim2.new(.5, -jx - 2, y, -jy)
	n.ShadowB.Position = UDim2.new(.5, jx + 2, y, jy)
	for _, sc in ipairs(n.Scales) do
		sc.Scale = 1 - n.Shrink * lineK
	end
	-- 4. the second line, the light cracks, the eye
	if t >= n.LineAt then
		n.Stage = math.max(n.Stage, 2)
		n.Sub.TextTransparency = 1 - lineK
		n.SubStroke.Transparency = 1 - .8 * lineK
		growCracks(n.Cracks, (t - n.LineAt) * (.7 / N.CrackTime) / .7 * 1.2, 1)
	end
	local eyeK = still and (t >= n.LineAt - .4 and 1 or 0) or smooth((t - (n.LineAt - .4)) / N.EyeOpen)
	n.Eye.Set(eyeK)
	-- 5. FIND OUT (pulsing)
	if t >= n.ButtonAt then
		if n.Stage < 3 then
			n.Stage = 3
			n.Holder.Visible = true
			n.Hint.TextTransparency = .15
		end
		local pulse = still and 0 or (math.sin((t - n.ButtonAt) * 4.2) * .5 + .5)
		n.ButtonScale.Scale = 1 + .05 * pulse
		n.Glow.BackgroundTransparency = .82 - .2 * pulse
	end
end

-- FIND OUT (escape = true: Esc / ButtonB, accepted after InputAfter even before the button)
function Reveal._Press(n: any, escape: boolean?)
	if n.Done or n.Pressed then
		return
	end
	local t = os.clock() - n.T0 + n.Offset
	if t < C.Notify.InputAfter then
		return -- nothing (not even Esc) acts in the first seconds: no accidental skip of the reveal
	end
	if not escape and n.Stage < 3 and t < C.Notify.AutoPress then
		Reveal._Skip(n)
		return
	end
	n.Pressed = true
	play("RevealHit", nil, { Volume = 1 })
	play("BellTollHuge", nil, { Group = "Cinema", Volume = .55 })
	task.spawn(function()
		local okFx = pcall(function()
			n.Flash.BackgroundTransparency = .1
			tween(n.Flash, C.Notify.Flash, { BackgroundTransparency = 1 })
			if reduced() then
				tween(n.Root, C.Notify.Tear, { Position = UDim2.fromScale(0, 0) })
				for _, d in ipairs(n.Root:GetDescendants()) do
					if d:IsA("GuiObject") then
						tween(d, C.Notify.Tear, { BackgroundTransparency = 1 })
						if d:IsA("TextLabel") or d:IsA("TextButton") then
							tween(d, C.Notify.Tear, { TextTransparency = 1 })
						end
					end
				end
			else
				for _, tooth in ipairs(n.Tear:GetChildren()) do
					if tooth:IsA("Frame") then
						tooth.BackgroundTransparency = 0
					end
				end
				tween(n.Root, C.Notify.Tear, { Position = UDim2.fromScale(0, -1.15) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			end
		end)
		task.wait(C.Notify.Tear + .05)
		local wasReplay = n.Replay
		notifyTeardown(n)
		if n.Handle then
			pcall(n.Handle.Skip)
		end
		if not okFx then
			warnOnce("tear", "tear effect failed")
		end
		if not wasReplay then
			State.Note.Sent = true
			task.spawn(function()
				for attempt = 1, 3 do
					local okReq = request("C2Notified")
					if okReq then
						break
					end
					if attempt < 3 then
						task.wait(2)
					end
				end
			end)
			if not revealSeen() and enabled() then
				startGuide(true)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- §6.2 THE GUIDE (route + ghost lights + objective marker)
---------------------------------------------------------------------------------------------------------------------
local guide: any = State.Guide
local function guideFolder(): Instance
	local f = guide.Folder
	if f and f.Parent then
		return f
	end
	f = Instance.new("Folder")
	f.Name = "DOGROTS_RevealGuide"
	f.Parent = fxFolder()
	guide.Folder = f
	return f
end

local function buildMarker(mode: string)
	if guide.Marker then
		guide.Marker.Anchor:Destroy()
		guide.Marker = nil
	end
	local folder = guideFolder()
	local anchor = Instance.new("Part")
	anchor.Name = "RevealMarker"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(.2, .2, .2)
	anchor.CFrame = CFrame.new(mode == "Descend" and Vector3.new(PORTAL.X, 12.6, 727.5) or Vector3.new(DOOR.X, 15.4, 725))
	anchor.Parent = folder
	local board = Instance.new("BillboardGui")
	board.Name = "Marker"
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = mode == "Descend" and C.Guide.DescendRange or C.Guide.MarkerRange
	board.Size = UDim2.fromOffset(236, 76)
	board.ResetOnSpawn = false
	board:SetAttribute("NoTranslate", true)
	board.Parent = anchor
	local card = frame(board, "Card", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(22, 10, 38), BackgroundTransparency = .16 })
	round(card, 0, 14)
	stroke(card, VIOLET_HOT, 2.5, .05)
	-- the eye glyph
	local glyph = frame(card, "Glyph", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 12, .5, 0), Size = UDim2.fromOffset(40, 24),
		BackgroundColor3 = C3(40, 16, 70), BackgroundTransparency = .1 })
	round(glyph, 1)
	stroke(glyph, VIOLET_HOT, 2, 0)
	local iris = frame(glyph, "Iris", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = MOON, BackgroundTransparency = .1 })
	round(iris, 1)
	local pupil = frame(iris, "Pupil", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(4, 13),
		BackgroundColor3 = INK })
	round(pupil, 1)
	local title = text(card, "Title", { Position = UDim2.fromOffset(62, 9), Size = UDim2.new(1, -72, 0, 30), TextXAlignment = Enum.TextXAlignment.Left,
		Text = mode == "Descend" and T("DESCEND") or T("THE CHURCH"), TextColor3 = C3(240, 232, 255) }, 26)
	local sub = text(card, "Sub", { Position = UDim2.fromOffset(62, 42), Size = UDim2.new(1, -72, 0, 22), TextXAlignment = Enum.TextXAlignment.Left,
		Text = mode == "Descend" and T("INTO THE UNDERYARD") or T("FOLLOW THE GHOST LIGHTS"), TextColor3 = MOON }, 18)
	-- a bobbing arrow under the card
	local arrow = text(board, "Arrow", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 1, -2), Size = UDim2.fromOffset(30, 22),
		Text = "▼", TextColor3 = VIOLET_HOT }, 22)
	guide.Marker = { Anchor = anchor, Board = board, Title = title, Sub = sub, Arrow = arrow, Mode = mode }
end

local function clearLights()
	for _, w in ipairs(guide.Lights or {}) do
		pcall(function()
			w.Core:Destroy()
			w.Halo:Destroy()
		end)
	end
	guide.Lights = {}
end

local function buildLights()
	clearLights()
	local n = Rules.GhostCount(Shared.Budget("GhostLights"))
	local folder = guideFolder()
	local trail = quality() == "High"
	for i = 1, n do
		local core = Instance.new("Part")
		core.Name = "GhostLight"
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(.55, .55, .55)
		core.Material = Enum.Material.Neon
		core.Color = C3(220, 204, 255)
		core.Transparency = 1
		core.Anchored = true
		core.CanCollide = false
		core.CanQuery = false
		core.CanTouch = false
		core.CastShadow = false
		core.Parent = folder
		local halo = core:Clone()
		halo.Name = "GhostHalo"
		halo.Size = Vector3.new(1.35, 1.35, 1.35)
		halo.Color = C3(140, 96, 240)
		halo.Parent = folder
		if trail then
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Rate = 5
			e.Lifetime = NumberRange.new(.6, 1)
			e.Speed = NumberRange.new(.2, .6)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(C3(200, 170, 255), C3(120, 170, 255))
			e.LightEmission = 1
			e.Parent = core
		end
		table.insert(guide.Lights, { Core = core, Halo = halo, Pos = nil, Phase = i * 1.3, Shown = 0 })
	end
end

function Reveal.StopGuide(reason: string?)
	if guide.Conn then
		pcall(function()
			guide.Conn:Disconnect()
		end)
		guide.Conn = nil
	end
	local wasActive = guide.Active
	guide.Active = false
	clearLights()
	if guide.Marker and guide.Marker.Mode == "Church" then
		guide.Marker.Anchor:Destroy()
		guide.Marker = nil
	end
	if wasActive and reason ~= "switched" and reason ~= "cleared" then
		local pg = pathGuide()
		local active = pg and pg.Active and pg.Active()
		if active and active.Key == "Church" then
			pcall(pg.Clear, reason or "cleared")
		end
	end
	if wasActive then
		Bus.Fire("C2Objective", { Key = nil })
	end
end

-- the route to the church with its ghost lights and marker (toast = say so)
startGuide = function(toastIt: boolean?)
	if not enabled() then
		return
	end
	Reveal.StopGuide("restart")
	local pg = pathGuide()
	if pg and pg.Show then
		local ok = pcall(pg.Show, "Church", { Label = false })
		if not ok then
			warnOnce("guide", "PathGuide.Show failed")
		end
	end
	guide.Active = true
	guide.Started = os.clock()
	buildLights()
	buildMarker("Church")
	if pg and pg.Changed then
		guide.Conn = pg.Changed:Connect(function(st, why, key)
			if st == nil and key == "Church" then
				Reveal.StopGuide(why == "arrived" and "arrived" or "cleared")
			elseif st ~= nil and st.Key ~= "Church" then
				Reveal.StopGuide("switched")
			end
		end)
	end
	Bus.Fire("C2Objective", { Key = "Church", Text = { "Go to the church", "Иди к церкви" } })
	if toastIt then
		toast("The church is waiting. Follow the ghost lights.", "info")
	end
end
function Reveal.StartGuide()
	startGuide(false)
end

local function stepGuide(now: number)
	if not guide.Active then
		return
	end
	local pg = pathGuide()
	local points = {}
	if pg and pg.Ahead then
		local ok, res = pcall(pg.Ahead, C.Guide.Spacing, #guide.Lights, C.Guide.Lead)
		if ok and type(res) == "table" then
			points = res
		end
	end
	local still = reduced()
	for i, w in ipairs(guide.Lights) do
		local target = points[i]
		if target then
			local bob = still and 0 or math.sin(now * 2.1 + w.Phase) * .35
			local goal = target + Vector3.new(0, 2.3 + bob, 0)
			w.Pos = w.Pos and w.Pos:Lerp(goal, .18) or goal
			w.Shown = math.min(1, w.Shown + .08)
		else
			w.Shown = math.max(0, w.Shown - .08)
		end
		if w.Pos then
			w.Core.CFrame = CFrame.new(w.Pos)
			w.Halo.CFrame = CFrame.new(w.Pos)
		end
		local flicker = still and 1 or (.85 + .15 * math.sin(now * 5.3 + w.Phase * 3))
		w.Core.Transparency = 1 - .9 * w.Shown * flicker
		w.Halo.Transparency = 1 - .3 * w.Shown * flicker
	end
end

local function stepMarker(now: number)
	local mk = guide.Marker
	if not mk or not mk.Board.Parent then
		return
	end
	if not reduced() then
		mk.Arrow.Position = UDim2.new(.5, 0, 1, -2 + math.floor(math.sin(now * 3) * 4))
	end
	if mk.Mode == "Church" then
		local pg = pathGuide()
		local active = pg and pg.Active and pg.Active()
		local d = active and active.Key == "Church" and active.Remaining or churchDistance()
		if d and (not guide.Started or now - guide.Started > 3) then
			mk.Sub.Text = metres(d)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- §6.3 THE CHURCH CINEMATIC
---------------------------------------------------------------------------------------------------------------------
local scene: any = State.Scene

-- the lit windows of the Grand Crypt + Moon Tower (top to bottom), the tower's parts and its bell
local WINDOW_NAMES = { MoonDisc = true, DialMoon = true, OculusGlass = true, LucarneSlit = true, LancetGlassHead = true, BelfryGlow = true,
	FinialCrescent = true, MoonRune = true }
local BELL_NAMES = { Bell = true, BellLip = true, BellCrown = true, BellClapper = true }
local function windows(): { any }
	local yard = deadYard()
	local list = {}
	local roots = {}
	local crypts = yard and yard:FindFirstChild("Crypts")
	table.insert(roots, crypts and crypts:FindFirstChild("GrandCrypt") or nil)
	table.insert(roots, yard and yard:FindFirstChild("MoonTower") or nil)
	for _, r in ipairs(roots) do
		for _, d in ipairs(r:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon and (d:GetAttribute("HwLantern") ~= nil or WINDOW_NAMES[d.Name]) then
				local lights = {}
				for _, l in ipairs(d:GetChildren()) do
					if l:IsA("Light") then
						table.insert(lights, { Light = l, B = l.Brightness })
					end
				end
				table.insert(list, { Part = d, Material = d.Material, Color = d.Color, Dim = d:GetAttribute("HwLocalDim"), Lights = lights,
					Y = d.Position.Y })
			elseif d:IsA("BasePart") and d.Name == "UplightLens" then
				local lights = {}
				for _, l in ipairs(d:GetChildren()) do
					if l:IsA("Light") then
						table.insert(lights, { Light = l, B = l.Brightness, Keep = .25 })
					end
				end
				table.insert(list, { Part = d, Material = d.Material, Color = d.Color, Dim = d:GetAttribute("HwLocalDim"), Lights = lights,
					Y = d.Position.Y - 100, KeepGlass = true })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Y > b.Y
	end)
	return list
end

local function dimWindow(w: any, k: number)
	local p = w.Part
	if not p.Parent then
		return
	end
	if k >= 1 then
		if not w.KeepGlass then
			p:SetAttribute("HwLocalDim", .02)
			p.Material = Enum.Material.SmoothPlastic
			p.Color = w.Color:Lerp(INK, .7)
		end
	end
	for _, rec in ipairs(w.Lights) do
		if rec.Light.Parent then
			rec.Light.Brightness = rec.B * ((rec.Keep or 0) + (1 - (rec.Keep or 0)) * (1 - k))
		end
	end
end
local function restoreWindow(w: any, k: number)
	local p = w.Part
	if not p.Parent then
		return
	end
	if k > 0 and not w.KeepGlass then
		p.Material = w.Material
		p.Color = w.Color
		p:SetAttribute("HwLocalDim", w.Dim)
	end
	for _, rec in ipairs(w.Lights) do
		if rec.Light.Parent then
			local from = rec.B * (rec.Keep or 0)
			rec.Light.Brightness = from + (rec.B - from) * k
		end
	end
end

local function tower(): any
	local yard = deadYard()
	local t = yard and yard:FindFirstChild("MoonTower")
	if not t then
		return nil
	end
	local rec = { Parts = {}, Base = {}, Bell = {}, BellBase = {} }
	local yoke = nil
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then
			if BELL_NAMES[d.Name] then
				table.insert(rec.Bell, d)
				table.insert(rec.BellBase, d.CFrame)
			else
				table.insert(rec.Parts, d)
				table.insert(rec.Base, d.CFrame)
				if d.Name == "BellYoke" then
					yoke = d.Position
				end
			end
		end
	end
	rec.Pivot = CFrame.new(BELL.X, 13.2, BELL.Z)
	rec.BellPivot = CFrame.new(yoke or (BELL + Vector3.new(0, 1.35, 0)))
	return rec
end

-- one writer for the tower: the shake (decaying wobble round its base) and the bell's swing (round its yoke). Parts
-- are only written while something moves (plus one settling write after it stops), never every frame of the scene.
local function stepTower(tw: any, now: number): boolean
	local shakeK = tw.ShakeAt and (now - tw.ShakeAt) / C.Church.TowerShake or 2
	local swingT = tw.SwingAt and (now - tw.SwingAt) or 1e9
	local envelope = tw.SwingAt and tw.SwingAmp * math.exp(-swingT / 2.4) or 0
	local swing = envelope * math.sin(swingT * 2 * math.pi / 1.7)
	local shaking = shakeK < 1
	local swinging = envelope > .002
	local writeTower = shaking or tw.ShakeDirty
	local writeBell = writeTower or swinging or tw.SwingDirty
	tw.ShakeDirty = shaking
	tw.SwingDirty = swinging
	if not writeBell then
		return false
	end
	local offset = CFrame.new()
	if shaking then
		local a = (1 - shakeK) ^ 2
		offset = CFrame.new(math.sin(now * 53) * .28 * a, 0, math.cos(now * 47) * .28 * a)
			* CFrame.Angles(math.sin(now * 41) * .006 * a, 0, math.cos(now * 37) * .006 * a)
	end
	local towerCF = tw.Pivot * offset * tw.Pivot:Inverse()
	local parts, cfs = {}, {}
	if writeTower then
		for i, p in ipairs(tw.Parts) do
			if p.Parent then
				table.insert(parts, p)
				table.insert(cfs, towerCF * tw.Base[i])
			end
		end
	end
	local bellCF = towerCF * tw.BellPivot * CFrame.Angles(swinging and swing or 0, 0, 0) * tw.BellPivot:Inverse()
	for i, p in ipairs(tw.Bell) do
		if p.Parent then
			table.insert(parts, p)
			table.insert(cfs, bellCF * tw.BellBase[i])
		end
	end
	safe("tower", moveParts, parts, cfs)
	return shaking or swinging
end
local function restoreTower(tw: any)
	if not tw then
		return
	end
	local parts, cfs = {}, {}
	for i, p in ipairs(tw.Parts) do
		if p.Parent then
			table.insert(parts, p)
			table.insert(cfs, tw.Base[i])
		end
	end
	for i, p in ipairs(tw.Bell) do
		if p.Parent then
			table.insert(parts, p)
			table.insert(cfs, tw.BellBase[i])
		end
	end
	safe("towerback", moveParts, parts, cfs)
end

local function dustEmitters(att: Attachment): (ParticleEmitter, ParticleEmitter)
	local dust = att:FindFirstChild("RevealDust") :: ParticleEmitter?
	local grit = att:FindFirstChild("RevealGrit") :: ParticleEmitter?
	if not dust then
		local e = Instance.new("ParticleEmitter")
		e.Name = "RevealDust"
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Rate = 0
		e.Lifetime = NumberRange.new(1.6, 2.6)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(35, 35)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Acceleration = Vector3.new(0, -5, 0)
		e.Drag = 1.2
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(1, 1.8) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(.6, .75), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(C3(146, 136, 128), C3(92, 86, 80))
		e.LightInfluence = 1
		e.Parent = att
		dust = e
	end
	if not grit then
		local e = Instance.new("ParticleEmitter")
		e.Name = "RevealGrit"
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Rate = 0
		e.Lifetime = NumberRange.new(.8, 1.3)
		e.Speed = NumberRange.new(.5, 2)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Acceleration = Vector3.new(0, -32, 0)
		e.Size = NumberSequence.new(.14)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .1), NumberSequenceKeypoint.new(1, .6) })
		e.Color = ColorSequence.new(C3(60, 54, 50))
		e.LightInfluence = 1
		e.Parent = att
		grit = e
	end
	return dust :: ParticleEmitter, grit :: ParticleEmitter
end

local function dustBurst(kind: string, strength: number)
	local c = church()
	local q = quality()
	local mult = (q == "Low" and .35 or q == "Medium" and .65 or 1) * strength
	for _, att in ipairs(c.Dust or {}) do
		if att.Parent and (att:GetAttribute("Kind") == kind or kind == "All") then
			local dust, grit = dustEmitters(att)
			dust:Emit(math.max(1, math.floor(12 * mult)))
			grit:Emit(math.max(1, math.floor(8 * mult)))
		end
	end
	play("DustFall", Vector3.new(DOOR.X, 15, 724), { Group = "Cinema", Volume = .9 })
end

local function fogOn(sc: any)
	local c = church()
	local q = quality()
	local rate = q == "Low" and 1 or q == "Medium" and 2 or 3.2
	sc.Fog = {}
	for _, att in ipairs(c.Fog or {}) do
		if att.Parent then
			local e = Instance.new("ParticleEmitter")
			e.Name = "RevealFog"
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Rate = rate
			e.Lifetime = NumberRange.new(6, 9)
			e.Speed = NumberRange.new(.3, .9)
			e.SpreadAngle = Vector2.new(180, 8)
			e.EmissionDirection = Enum.NormalId.Top
			e.Acceleration = Vector3.new(0, .04, 0)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-8, 8)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 12) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.25, .84), NumberSequenceKeypoint.new(.75, .88),
				NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(C3(118, 104, 150))
			e.LightInfluence = 1
			e:SetAttribute("HwParticlePriority", true)
			e.Parent = att
			e:Emit(q == "Low" and 1 or 3)
			table.insert(sc.Fog, e)
		end
	end
end
local function fogOff(sc: any)
	for _, e in ipairs(sc.Fog or {}) do
		pcall(function()
			e.Enabled = false
			Debris:AddItem(e, 10)
		end)
	end
	sc.Fog = {}
end

local function portalSuck(on: boolean)
	local c = church()
	local portal = c.Portal
	local disc = portal and portal:FindFirstChild("PortalDisc")
	if not disc then
		return
	end
	local e = disc:FindFirstChild("RevealSuck") :: ParticleEmitter?
	if on and not e then
		local q = quality()
		local p = Instance.new("ParticleEmitter")
		p.Name = "RevealSuck"
		p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		p.Shape = Enum.ParticleEmitterShape.Sphere
		p.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		p.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		p.Rate = q == "Low" and 8 or q == "Medium" and 16 or 26
		p.Lifetime = NumberRange.new(.9, 1.3)
		p.Speed = NumberRange.new(2.6, 3.4)
		p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .32), NumberSequenceKeypoint.new(1, .05) })
		p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .9), NumberSequenceKeypoint.new(.3, .2), NumberSequenceKeypoint.new(1, 1) })
		p.Color = ColorSequence.new(C3(200, 150, 255), MOON)
		p.LightEmission = 1
		p:SetAttribute("HwParticlePriority", true)
		p.Parent = disc
	elseif not on and e then
		e:Destroy()
	end
end

-- plays the cinematic; opts {Replay = true}: from the Journal (nothing is sent). -> started, refusal?
function Reveal.PlayChurch(opts: { [string]: any }?): (boolean, string?)
	local o = opts or {}
	if scene.Playing then
		return false, "Busy"
	end
	local cin = cinema()
	if not cin or not cin.Play then
		return false, "NoCinema"
	end
	local c = church()
	if not c.Root then
		return false, "Streaming"
	end
	scene.Playing = true
	scene.Replay = o.Replay == true
	local sc: any = { Anims = {}, Windows = nil, Tower = nil, Title = nil, Ended = false }
	scene.Current = sc
	Reveal.StopGuide("cinematic")
	local CH = C.Church
	-- the camera: a low 3/4 shot drifting closer, then the push in to the door
	local keys = Rules.Shots()
	local path = {}
	for _, k in ipairs(keys) do
		table.insert(path, { k.T, cin.LookAt and cin.LookAt(k.Eye, k.At) or CFrame.lookAt(k.Eye, k.At) })
	end
	local shot = cin.Path(path)
	local function fov(t: number): number
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if t <= b.T then
				return a.Fov + (b.Fov - a.Fov) * smooth((t - a.T) / math.max(.01, b.T - a.T))
			end
		end
		return keys[#keys].Fov
	end
	local function anim(dur: number, fn: (number) -> ())
		table.insert(sc.Anims, { T0 = os.clock(), Dur = dur, Fn = fn })
	end
	local function finalState()
		sc.Anims = {}
		setDoors(1)
		setPortal(1)
		setCracks(1, CH.CracksSettled)
		setSlit(0)
		portalSuck(true)
		if sc.Windows then
			for _, w in ipairs(sc.Windows) do
				restoreWindow(w, 1)
			end
			sc.Windows = nil
		end
		if sc.Tower then
			restoreTower(sc.Tower)
			sc.Tower = nil
		end
		fogOff(sc)
		State.Church.Applied = nil
	end
	local function cleanup()
		if sc.Ended then
			return
		end
		sc.Ended = true
		if sc.Conn then
			sc.Conn:Disconnect()
			sc.Conn = nil
		end
		sc.Anims = {}
		if sc.Windows then
			for _, w in ipairs(sc.Windows) do
				restoreWindow(w, 1)
			end
			sc.Windows = nil
		end
		if sc.Tower then
			restoreTower(sc.Tower)
			sc.Tower = nil
		end
		fogOff(sc)
		if sc.Title then
			pcall(sc.Title.Hide, .4)
		end
		scene.Playing = false
		scene.Current = nil
	end
	local function boom(i: number)
		play("BellTollHuge", BELL, { Volume = 1 })
		if cin.Impulse then
			cin.Impulse(1 + .25 * i)
		end
		if cin.Shake then
			cin.Shake(.35 + .15 * i, .7)
		end
		local tw = sc.Tower
		if tw then
			if i == 1 and not reduced() then
				tw.ShakeAt = os.clock()
			end
			tw.SwingAt = os.clock()
			tw.SwingAmp = .32 + .06 * i
		end
	end
	local timeline = {
		{ 0, function()
			setDoors(0)
			setPortal(0)
			setCracks(0)
			setSlit(1)
			fogOn(sc)
			sc.Tower = tower()
			sc.Conn = RunService.Heartbeat:Connect(function()
				local now = os.clock()
				for i = #sc.Anims, 1, -1 do
					local a = sc.Anims[i]
					local k = math.clamp((now - a.T0) / a.Dur, 0, 1)
					local okA = pcall(a.Fn, k)
					if k >= 1 or not okA then
						table.remove(sc.Anims, i)
					end
				end
				if sc.Tower then
					stepTower(sc.Tower, now)
				end
			end)
		end },
		{ CH.Booms[1], function()
			boom(1)
			dustBurst("All", 1)
		end },
		{ CH.Booms[2], function()
			boom(2)
			dustBurst("Roof", .6)
			sc.Windows = windows()
			local list = sc.Windows
			local n = #list
			anim(CH.Windows + .3, function(k)
				for i, w in ipairs(list) do
					local start = (i - 1) / math.max(1, n) * CH.Windows
					local local01 = math.clamp((k * (CH.Windows + .3) - start) / .3, 0, 1)
					dimWindow(w, local01)
				end
			end)
		end },
		{ CH.Booms[3], function()
			boom(3)
			dustBurst("Roof", .8)
			play("GroundCrack", DOOR + Vector3.new(0, 0, -6), { Group = "Cinema", Volume = 1 })
			anim(CH.CrackTime, function(k)
				setCracks(smooth(k), 1)
			end)
		end },
		{ CH.DoorsAt, function()
			play("ChurchCreak", DOOR + Vector3.new(0, 5, 5), { Volume = 1 })
			anim(CH.DoorTime + .1, function(k)
				setDoors(Rules.DoorOpen(k * (CH.DoorTime + .1)))
			end)
			anim(.6, function(k)
				setSlit(1 - k, k * .8)
			end)
		end },
		{ CH.PortalAt, function()
			play("PortalOpen", c.Centre or PORTAL, { Volume = 1 })
			portalSuck(true)
			anim(CH.PortalTime, function(k)
				setPortal(smooth(k), 1 + 1.4 * math.sin(k * math.pi))
			end)
			if cin.Flash then
				cin.Flash(VIOLET, .28, .7)
			end
		end },
		{ CH.TitleAt, function()
			if cin.Title then
				sc.Title = cin.Title(Cfg.Name[1], Cfg.Name[2], { Sub = Cfg.Subtitle, Duration = CH.TitleTime, Size = "Large", Position = "Upper",
					Color = BONE, SubColor = MOON })
			end
		end },
		{ CH.Relight, function()
			local list = sc.Windows
			sc.Windows = nil
			if list then
				anim(1.2, function(k)
					for _, w in ipairs(list) do
						restoreWindow(w, k)
					end
				end)
			end
		end, Always = true },
		{ CH.Duration - .05, function()
			finalState()
		end, Always = true },
	}
	local handle, why = cin.Play({
		Id = "Church", Duration = CH.Duration, Shot = shot, Fov = fov, Focus = { Target = DOOR + Vector3.new(0, 6.5, 5), Radius = 14, Far = .32, Near = .06 },
		Letterbox = true, Skippable = true, SkipAfter = CH.SkipAfter, LockControls = true, HideUI = true,
		Duck = { Music = 0, WorldEvents = 0, Ambience = .45, Pickaxe = .15, Boss = .15, SFX = .4, UI = .6 },
		BlendIn = CH.BlendIn, BlendOut = CH.BlendOut, Timeline = timeline,
		OnSkip = function()
			finalState()
			if sc.Title then
				pcall(sc.Title.Hide, .3)
			end
		end,
		OnDone = function(ok, reason)
			cleanup()
			if ok then
				finalState()
				if not scene.Replay then
					scene.Pending = true
					task.spawn(function()
						local sent = false
						for attempt = 1, 3 do
							local okReq = request("C2RevealSeen", {})
							if okReq then
								sent = true
								break
							end
							if attempt < 3 then
								task.wait(1.5)
							end
						end
						if not sent and not revealSeen() then
							scene.Pending = false
							scene.CooldownUntil = os.clock() + C.Church.Cooldown
							State.Church.Applied = nil
						end
					end)
					Bus.Fire("C2Objective", { Key = "Descend", Text = { "Descend into the Underyard", "Спустись в Поддворье" } })
					toast("The doors are open. Descend into the Underyard.", "success")
				end
			else
				scene.CooldownUntil = os.clock() + C.Church.Cooldown
				State.Church.Applied = nil
			end
		end,
	})
	if not handle then
		cleanup()
		State.Church.Applied = nil
		scene.Refused = why
		return false, why
	end
	return true, nil
end

---------------------------------------------------------------------------------------------------------------------
-- §6.5 THE TEASER (a closed church, a player nearby)
---------------------------------------------------------------------------------------------------------------------
local teaser: any = State.Teaser
local function playTeaser()
	if teaser.Playing then
		return
	end
	local c = church()
	if not c.Root or #c.Slit == 0 then
		return
	end
	teaser.Playing = true
	teaser.Count = (teaser.Count or 0) + 1
	play("BellToll", BELL, { Volume = .45, Pitch = .94 })
	task.delay(.8, play, "Whisper2", DOOR + Vector3.new(0, 4, 4), { Volume = .7 })
	local T_ = C.Teaser
	local anchor = Instance.new("Part")
	anchor.Name = "RevealTeaserText"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(.2, .2, .2)
	anchor.CFrame = CFrame.new(DOOR.X, 13.7, 726.6)
	anchor.Parent = fxFolder()
	local board = Instance.new("BillboardGui")
	board.Name = "Teaser"
	board.Adornee = anchor
	board.Size = UDim2.fromScale(13, 1.5)
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.MaxDistance = C.Teaser.Radius + 30
	board:SetAttribute("NoTranslate", true)
	board.Parent = anchor
	local label = text(board, "Text", { Size = UDim2.fromScale(1, 1), Text = T("Something is waiting below."), TextColor3 = C3(212, 188, 255),
		TextTransparency = 1 })
	local lstroke = stroke(label, INK, 2, 1)
	lstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local t0 = os.clock()
	local total = math.max(T_.Breaths * T_.Breath, T_.TextIn + T_.TextHold + T_.TextOut) + .2
	local conn: RBXScriptConnection? = nil
	local function finish()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		teaser.Playing = false
		pcall(function()
			anchor:Destroy()
		end)
		if State.Church.Slit > 0 then
			safe("teaserend", setSlit, 1)
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		local ok = pcall(function()
			local t = os.clock() - t0
			if State.Church.Slit > 0 and not scene.Playing then
				local b = t < T_.Breaths * T_.Breath and math.sin(math.pi * ((t % T_.Breath) / T_.Breath)) ^ 2 or 0
				setSlit(1, b)
			end
			local a
			if t < T_.TextIn then
				a = t / T_.TextIn
			elseif t < T_.TextIn + T_.TextHold then
				a = 1
			else
				a = 1 - (t - T_.TextIn - T_.TextHold) / T_.TextOut
			end
			a = math.clamp(a, 0, 1)
			label.TextTransparency = 1 - .95 * a
			lstroke.Transparency = 1 - .7 * a
			if not reduced() then
				board.StudsOffsetWorldSpace = Vector3.new(0, .5 * t / total, 0)
			end
			if t >= total or scene.Playing then
				finish()
			end
		end)
		if not ok then
			finish()
		end
	end)
	-- belt and braces
	task.delay(total + 2, function()
		if teaser.Playing then
			finish()
		end
	end)
end
Reveal.PlayTeaser = playTeaser

---------------------------------------------------------------------------------------------------------------------
-- §6.6 THE PORTAL TRANSITION (Signal C2Portal {Dir, Stage}; Bus C2Replay {Id = "Portal"})
---------------------------------------------------------------------------------------------------------------------
local portalState: any = State.Portal

local function transitionGui(): any
	local pg = playerGui()
	assert(pg, "no PlayerGui")
	local g = newGui("DOGROTS_RevealPortal", 89)
	local size = Vector2.new(1280, 720)
	local cam = workspace.CurrentCamera
	if cam then
		size = cam.ViewportSize
	end
	local top = frame(g, "Top", { AnchorPoint = Vector2.new(0, 0), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0),
		BackgroundTransparency = 0, ZIndex = 2 })
	local bottom = frame(g, "Bottom", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C3(0, 0, 0), BackgroundTransparency = 0, ZIndex = 2 })
	-- the giant eye / moon: an almond outline whose lids part over the moon iris and its slit pupil
	local d = math.floor(math.min(size.X * .95, size.Y * 2))
	local eh = math.floor(d * .42)
	local eyeBox = frame(g, "Eye", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(d, eh),
		ZIndex = 3, Visible = false })
	local outline = almond(eyeBox, d, eh, VIOLET, VIOLET_HOT, math.max(3, math.floor(eh / 48)), 4, 9)
	local open = frame(eyeBox, "Open", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(d, 0),
		ClipsDescendants = true, ZIndex = 3 })
	local moonD = math.floor(eh * .84)
	local moon = frame(open, "Moon", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(moonD, moonD),
		BackgroundColor3 = C3(206, 226, 255), ZIndex = 3 })
	round(moon, 1)
	stroke(moon, MOON, 3, .2)
	local pupil = frame(open, "Pupil", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
		Size = UDim2.fromOffset(math.floor(moonD * .16), math.floor(moonD * .9)), BackgroundColor3 = C3(4, 0, 10), ZIndex = 4 })
	round(pupil, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = eyeBox
	local black = frame(g, "Black", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 0), BackgroundTransparency = 1, ZIndex = 6 })
	local flash = frame(g, "Flash", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(232, 240, 255), BackgroundTransparency = 1, ZIndex = 7 })
	g.Parent = pg
	return { Gui = g, Top = top, Bottom = bottom, Eye = eyeBox, EyeScale = scale, Black = black, Flash = flash, Outline = outline, Open = open,
		D = d, H = eh, Moon = moon, Pupil = pupil }
end

local function transitionTeardown(p: any)
	if p.Done then
		return
	end
	p.Done = true
	if p.Conn then
		pcall(function()
			p.Conn:Disconnect()
		end)
	end
	if p.Unlock then
		p.Unlock()
	end
	local cin = cinema()
	if p.Hidden and cin and cin.ShowUI then
		pcall(cin.ShowUI, "RevealPortal")
	end
	local m = mixer()
	if m then
		pcall(m.Release, "RevealPortal", 1.2)
	end
	local cam = workspace.CurrentCamera
	if cam and p.BaseFov then
		pcall(function()
			cam.FieldOfView = p.BaseFov
		end)
	end
	if p.Grade then
		pcall(function()
			p.Grade:Destroy()
		end)
	end
	if p.UI then
		pcall(function()
			p.UI.Gui:Destroy()
		end)
	end
	portalState.Active = false
	portalState.Current = nil
end

-- dir "Down" (into the Underyard) | "Up"; opts {Replay = true}: no teleport is waited for
function Reveal.Transition(dir: string, opts: { [string]: any }?): boolean
	local o = opts or {}
	if portalState.Active then
		return false
	end
	local p: any = { Dir = dir == "Up" and "Up" or "Down", Replay = o.Replay == true, T0 = os.clock(), Phase = "Out", Done = false }
	portalState.Active = true
	portalState.Current = p
	portalState.Count = (portalState.Count or 0) + 1
	local ok, err = pcall(function()
		local cin = cinema()
		-- a cinematic running now (the church, a seal) gives way: the portal wins
		if cin and cin.Busy and cin.Busy() and cin.Cancel then
			cin.Cancel("Portal")
		end
		p.Unlock = lockControls("RevealPortal")
		if cin and cin.HideUI then
			cin.HideUI("RevealPortal")
			p.Hidden = true
		end
		local m = mixer()
		if m then
			m.Duck("RevealPortal", { Music = .1, Ambience = .2, WorldEvents = .1, Pickaxe = .15, Boss = .3, SFX = .45, UI = .7 }, .5)
		end
		local cam = workspace.CurrentCamera
		p.BaseFov = cam and cam.FieldOfView or 70
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "DOGROTS_PortalGrade"
		grade.Parent = cam
		p.Grade = grade
		p.UI = transitionGui()
		play("PortalReverse", nil, { Volume = 1, Delay = .15 })
		local still = reduced()
		p.Conn = RunService.Heartbeat:Connect(function()
			local okStep, errStep = pcall(function()
				local P = C.Portal
				local now = os.clock()
				local t = now - p.T0
				local ui = p.UI
				local vh = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or 720
				if p.Phase == "Out" then
					local s = Rules.Transition(t)
					if workspace.CurrentCamera and not still then
						workspace.CurrentCamera.FieldOfView = math.clamp(p.BaseFov + s.Fov, 20, 115)
					end
					local bar = math.floor(vh * s.Squash / 2)
					ui.Top.Size = UDim2.new(1, 0, 0, bar)
					ui.Bottom.Size = UDim2.new(1, 0, 0, bar)
					grade.Saturation = s.Saturation
					grade.Contrast = .25 * -s.Saturation
					grade.TintColor = C3(255, 255, 255):Lerp(C3(196, 176, 255), -s.Saturation * .6)
					ui.Eye.Visible = s.Eye > 0
					ui.EyeScale.Scale = 1.35 - .35 * s.Eye
					if s.Eye > 0 then
						ui.Open.Size = UDim2.fromOffset(ui.D, math.floor(ui.H * s.Eye))
						ui.Outline.Set(s.Eye, 1)
					end
					ui.Moon.BackgroundTransparency = 1 - s.Eye
					ui.Pupil.BackgroundTransparency = 1 - s.Eye
					ui.Flash.BackgroundTransparency = 1 - .9 * s.Flash
					ui.Black.BackgroundTransparency = 1 - s.Black
					if t >= P.Black + .05 then
						p.Phase = "Hold"
						p.HoldAt = now
						ui.Eye.Visible = false
						ui.Flash.BackgroundTransparency = 1
						ui.Black.BackgroundTransparency = 0
						play("PortalWhoosh", nil, { Volume = .9 })
						if workspace.CurrentCamera then
							workspace.CurrentCamera.FieldOfView = p.BaseFov
						end
						if p.Replay then
							p.Arrived = true
							p.ReadyAt = now + .45
						end
					end
				elseif p.Phase == "Hold" then
					if (p.Arrived or p.Failed) and not p.ReadyAt then
						p.ReadyAt = now + P.Settle
					end
					if (p.ReadyAt and now >= p.ReadyAt) or now - p.HoldAt > P.HoldMax then
						p.Phase = "In"
						p.InAt = now
						if p.Failed then
							toast("The portal flickered. Try again.", "warn")
						elseif cin and cin.Title then
							if p.Dir == "Down" then
								local names = Layout.Names[p.District or "BellSquare"] or Layout.Names.BellSquare
								cin.Title(Cfg.Name[1], Cfg.Name[2], { Sub = names, Duration = P.TitleTime, Size = "Large", Position = "Upper", Color = BONE,
									SubColor = MOON, Delay = .25 })
							else
								cin.Title("THE DEAD YARD", "МЁРТВЫЙ ДВОР", { Sub = { "NIGHT OF THE BURIED MOON", "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ" },
									Duration = P.TitleTime, Size = "Large", Position = "Upper", Color = BONE, SubColor = C3(255, 170, 80), Delay = .25 })
							end
						end
						-- the controls come back as the picture does
						if p.Unlock then
							p.Unlock()
							p.Unlock = nil
						end
					end
				else
					local s = Rules.FadeIn(now - p.InAt)
					ui.Black.BackgroundTransparency = 1 - s.Black
					grade.Saturation = s.Saturation
					grade.Contrast = .25 * -s.Saturation
					local bar = math.floor(vh * s.Squash / 2)
					ui.Top.Size = UDim2.new(1, 0, 0, bar)
					ui.Bottom.Size = UDim2.new(1, 0, 0, bar)
					if now - p.InAt >= P.FadeIn * 1.4 then
						transitionTeardown(p)
					end
				end
			end)
			if not okStep then
				warnOnce("portalstep", tostring(errStep))
				transitionTeardown(p)
			end
		end)
		-- the watchdog: whatever happens, the screen comes back
		task.delay(C.Portal.Black + C.Portal.HoldMax + C.Portal.FadeIn * 1.4 + 3, function()
			if not p.Done then
				transitionTeardown(p)
			end
		end)
	end)
	if not ok then
		warnOnce("portalbuild", tostring(err))
		transitionTeardown(p)
		return false
	end
	return true
end

local function onPortal(data: any)
	if type(data) ~= "table" then
		return
	end
	local stage = data.Stage
	if stage == "Start" then
		if State.Note.Current then
			-- (never: a notification blocks the prompt) keep the screens from stacking
			return
		end
		Reveal.Transition(data.Dir == "Up" and "Up" or "Down")
	elseif stage == "Arrived" or stage == "Failed" then
		local p = portalState.Current
		if p and not p.Replay then
			if stage == "Arrived" then
				p.Arrived = true
				p.District = type(data.District) == "string" and data.District ~= "" and data.District or nil
			else
				p.Failed = true
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the steady loop (4 Hz): state, the church end state, the prompt, triggers, the teaser, the notification
---------------------------------------------------------------------------------------------------------------------
local rng = Random.new(os.clock() * 1000 % 100000)
function Reveal.Tick()
	local now = os.clock()
	local on = enabled()
	local isEligible = on and eligible()
	local seen = revealSeen()
	local c = church()
	-- the prompt
	updatePrompt(Rules.PromptVisible({ Enabled = on, Eligible = isEligible }))
	-- the church end state (the cinematic owns the church while it plays)
	if seen then
		scene.Pending = false
	end
	local wanted = Rules.ChurchState({ Enabled = on, Eligible = isEligible, RevealSeen = seen, Pending = scene.Pending })
	if not scene.Playing and c.Root then
		Reveal.ApplyChurch(wanted)
	end
	local dist = churchDistance()
	-- the cinematic on the first approach
	local env = environment()
	local blocked = env.Menu or env.Cinema or env.Mining or env.Dead or env.Combat or env.Trial or env.Overlay or State.Note.Showing
	if Rules.CinematicDue({ Enabled = on, Eligible = isEligible, RevealSeen = seen or scene.Pending, Distance = dist, Playing = scene.Playing,
		Now = now, CooldownUntil = scene.CooldownUntil, Blocked = blocked }) and c.Root then
		if not (notified() or State.Note.Sent) and Reveal.Notify() then
			-- "IS THAT ALL?" first (§6.1): the cinematic follows on the first tick after FIND OUT (Note.Sent, not Showing)
		else
			local started, why = Reveal.PlayChurch()
			if not started and why ~= "Busy" then
				scene.CooldownUntil = now + 2
			end
		end
	end
	-- the teaser
	if Rules.TeaserWanted({ Enabled = on, Eligible = isEligible, State = wanted, Distance = dist, Playing = scene.Playing }) and c.Root then
		if not teaser.NextAt then
			teaser.NextAt = now + Rules.TeaserDelay(rng, true)
		elseif now >= teaser.NextAt and not teaser.Playing then
			playTeaser()
			teaser.NextAt = now + Rules.TeaserDelay(rng, false)
		end
	else
		teaser.NextAt = nil
	end
	-- the notification (a stable unblocked moment first)
	local note = State.Note
	local reason = Rules.NotifyBlocked({ Enabled = on, Eligible = isEligible, Notified = notified() or note.Sent == true, Showing = note.Showing,
		Menu = env.Menu, Cinema = env.Cinema, Mining = env.Mining, Tutorial = env.Tutorial, Dead = env.Dead, Combat = env.Combat,
		Trial = env.Trial, Overlay = env.Overlay })
	if reason == nil then
		note.StableSince = note.StableSince or now
		if now - note.StableSince >= (note.Poked and 1.2 or C.Notify.Stable) then
			note.StableSince = nil
			note.Poked = false
			Reveal.Notify()
		end
	else
		note.StableSince = nil
	end
	-- the DESCEND objective after the reveal (marker near the church until the first descent)
	if guide.Marker and guide.Marker.Mode == "Descend" then
		if not on or entered() or not seen then
			guide.Marker.Anchor:Destroy()
			guide.Marker = nil
			Bus.Fire("C2Objective", { Key = nil })
		end
	elseif on and seen and not entered() and not guide.Active and dist and dist < C.Guide.DescendRange and not scene.Playing then
		buildMarker("Descend")
	end
	if not on and guide.Active then
		Reveal.StopGuide("closed")
	end
end

-- the near-church frame work (portal life, the slit's idle glow, ghost lights, the marker)
local idleAt = 0
local function frameStep()
	local now = os.clock()
	stepLife(now)
	stepGuide(now)
	stepMarker(now)
	if now - idleAt > .1 then
		idleAt = now
		if State.Church.Slit > 0 and not teaser.Playing and not scene.Playing then
			local dist = churchDistance()
			if dist and dist < C.Teaser.IdleRange and not reduced() then
				setSlit(1, .12 + .1 * math.sin(now * 1.3))
			end
		end
	end
end

-- C2Reveal {Need = "Church"}: the DESCEND prompt was used before the church was seen
local function needChurch()
	local dist = churchDistance()
	if dist and dist <= C.Church.NeedRange then
		scene.CooldownUntil = 0
		local started = Reveal.PlayChurch()
		if not started then
			toast("Watch the church first", "warn")
		end
	elseif not guide.Active then
		startGuide(true)
	end
end

local function onReplay(data: any)
	local id = type(data) == "table" and data.Id or data
	if id == "Reveal" then
		Reveal.Notify({ Replay = true })
	elseif id == "Church" then
		local dist = churchDistance()
		if not dist or dist > C.Church.ReplayRange or not church().Root then
			toast("Stand near the church to replay this scene.", "warn")
			return
		end
		local ok, why = Reveal.PlayChurch({ Replay = true })
		if not ok and why == "Menu" then
			-- replays are started from the Journal window: try again once it has closed
			task.delay(.6, function()
				Reveal.PlayChurch({ Replay = true })
			end)
		end
	elseif id == "Portal" then
		Reveal.Transition("Down", { Replay = true })
	end
end

function Reveal.Start(c: any)
	if started then
		return
	end
	started = true
	ctx = c
	Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" then
			return
		end
		if sig.Kind == "C2Reveal" then
			local data = sig.Data
			if type(data) == "table" and data.Need == "Church" then
				needChurch()
			else
				State.Note.Poked = true
			end
		elseif sig.Kind == "C2Portal" then
			onPortal(sig.Data)
		end
	end)
	Bus.On("C2Replay", function(data)
		safe("replay", onReplay, data)
	end)
	for _, attr in ipairs({ "HalloweenChapter1Complete", "Chapter2Notified", "Chapter2RevealSeen", "Chapter2Entered" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			State.Church.Applied = nil
			State.Note.Poked = true
		end)
	end
	player.CharacterRemoving:Connect(function()
		if teaser.Playing then
			teaser.Playing = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		safe("frame", frameStep)
	end)
	task.spawn(function()
		while true do
			safe("tick", Reveal.Tick)
			task.wait(.25)
		end
	end)
end

return Reveal
