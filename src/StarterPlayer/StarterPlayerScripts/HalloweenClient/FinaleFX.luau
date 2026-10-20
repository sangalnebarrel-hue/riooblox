-- THE LAST BELL · the Gravekeeper difficulty V finale on screen (StarterPlayerScripts.HalloweenClient.FinaleFX;
-- docs/halloween2/DESIGN.md §11, §16, §17, §23.2, §24.3). Client only, purely visual: the server (BossFinale, WP-C) runs
-- the finale and publishes RS.Halloween.State.Finale + Signal BossEvent {Kind = "Finale", Stage = ...}.
-- * FALSE VICTORY (FakeDeath {At, Seconds}): music hard stop (AudioMixer duck), a Cinema shot on the collapsing corpse
--   (BossFX plays the collapse), at At+1.2 the fake reward flash ("THE GRAVEKEEPER FALLS!" + a reward card shell), silence
--   to At+3.9, then a rumble + shake + the bell's toll, at At+4.8 the card cracks into ash ("...not yet"), at At+5.4 the
--   Gravekeeper's spirit tears out of the corpse.
-- * THE BELL TOLLS (Bell / ChainActive / ChainHit / ChainBreak / BellToll): the Black Bell (Models.Finale.Bell) descends
--   to BellCF over 2.5 s while the spirit flies into it, four cursed chains shoot out to stone anchor posts behind the rim
--   ramps; the active chain pulses in sync with the server clock (Since / Pulse / Bright: the bright part of each pulse is
--   when Perfect hits count), hits crack it ("IMMUNE" / "MISSED THE TOLL" for hits that do not count), it shatters on
--   ChainBreak; the bell swings and tolls on every BellToll (CombatFX draws the shockwave hazard itself).
-- * THE BURIED CHOIR (Choir / Candle / Round / WeakOpen / Ghosts / GhostBite / GhostDown / Volley): fog (Halloween Lighting
--   layer), six cursed candles rise on the terrace ring (lit / snuffed, a sign + numeral each, a ring that turns green when
--   the candle matches), the target pattern glows on the bell's six sign slots and on a halo of numerals around it, ghost
--   dogs (Models.Finale.GhostDog) run on the FinaleGhost Strike targets, buried weak points (gold mounds) glow on WeakOpen,
--   the spirit throws its volleys from the rim.
-- * THE LAST BARK (Hound / HoundPattern / Bark / Counter): the colossal hound (Models.Finale.Hound) rises behind the pit
--   with the Black Moon (camera-relative backdrop) and moves on the FINALE_HOUND beat (anchored at StartAt), its pose
--   following each pattern; on Bark it lunges so its open jaw meets JawPos (the HoundJaw weak point) with a counter ring
--   and a countdown; Counter hits flinch it and drain its bark points (a big readable bar in the finale panel).
-- * VICTORY (the hound howls, shatters into moths, the Black Moon cracks and breaks, dawn-blue light, the music resolves)
--   and FAIL ("THE BELL SILENCES YOU": a last toll, colour drains, candles die).
-- * The finale panel (own ScreenGui, under the HUD strip): stage, objective, timer, chains / candles / bark points.
-- * Late joiners get the current stage state (no set pieces replayed); the journal replay (Bus C2Replay {Id = "Finale"})
--   plays FakeDeath -> the bell's descent on a client-only memory stage, sends nothing.
-- Robustness: every build / step / event runs in pcall; one session table owns everything (models, guis, lighting layers,
--   ducks, cues, connections, the Cinema handle) and teardown() releases all of it (fight over, zone left, event off). No
--   camera shot while the local player is downed; in-combat shots are cancelled the moment a hazard telegraph appears.
-- Quality: Shared.Budget("FinaleFX") (1 / .7 / .4) scales particles, moths, model detail and lights; ReducedMotion: no shake,
--   no flashes, no in-combat shots (Cinema cuts statically), smaller swings.
-- Music: the soundscape picks FINALE_BELL / _CHOIR / _HOUND from State.Finale (WP-H2); FinaleFX.MusicTheme() gives the same
--   answer and a guard sets it itself when nothing else does (never with MUSIC: OFF).
-- API: FinaleFX.Start(ctx), FinaleFX.Active() -> bool, FinaleFX.Stage() -> string, FinaleFX.MusicTheme() -> theme?, opts,
--   FinaleFX.Replay() (the journal replay), FinaleFX.Debug (offline tests).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FinaleFX = { Started = false }

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi
local WHITE = Color3.new(1, 1, 1)

local VIOLET = RGB(150, 80, 230)
local VIOLET_HOT = RGB(226, 190, 255)
local VIOLET_DEEP = RGB(78, 34, 150)
local GOLD = RGB(255, 200, 70)
local GOLD_HOT = RGB(255, 236, 150)
local CANDLE = RGB(255, 170, 80)
local BONE = RGB(230, 222, 200)
local MOON = RGB(150, 200, 255)
local DAWN = RGB(176, 214, 255)
local SICKLY = RGB(120, 255, 140)
local GREEN_HOT = RGB(206, 255, 196)
local GHOST = RGB(168, 214, 255)
local INK = RGB(16, 12, 26)
local BLOOD = RGB(220, 40, 60)
local ASH = RGB(120, 112, 128)
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

-- presentation timings (§23.2; seconds after the stage's server timestamp)
FinaleFX.Timing = {
	FakeDeath = { Flash = 1.2, Silence = 1.4, Toll = 3.9, Crack = 4.8, Spirit = 5.4, Seconds = 6 },
	Descend = 2.5, -- the bell comes down to BellCF
	DropHeight = 70,
	ChainGrow = .6, AnchorRise = .8,
	CandleRise = 1.2, CandleStagger = .22,
	HoundRise = 3, RiseDepth = 50, BarkIn = .3, BarkOut = .7, LungeMax = 48,
	Victory = { Howl = 2.0, Shatter = 2.2, Crack = { 2.7, 3.3, 3.9 }, Break = 4.4, Dawn = 4.4, Shot = 8.5, Bell = 5.2 },
	FailShot = 4.6,
	EndFade = 3, -- lighting / models fade when the finale is over
	JoinGrace = .6, -- an attribute stage change waits this long for its event before entering "late"
	LeaveAfter = 1.2, -- seconds out of the arena before everything is torn down
	ReplayOrigin = Vector3.new(6000, 900, 6000),
}
FinaleFX.MoonDistance = 420
FinaleFX.MoonRadius = 64

local ROMAN = { "I", "II", "III", "IV", "V", "VI" }
local STAGES = { FakeDeath = true, Bell = true, Choir = true, Hound = true, Victory = true, Fail = true }
local PANEL_STAGES = { Bell = true, Choir = true, Hound = true }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function vecOf(v: any): Vector3?
	if typeof(v) == "Vector3" then
		return v
	elseif type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) then
		return Vector3.new(tonumber(v[1]) :: number, tonumber(v[2]) :: number, tonumber(v[3]) :: number)
	end
	return nil
end
local function cfOf(v: any): CFrame?
	if typeof(v) == "CFrame" then
		return v
	end
	local p = vecOf(v)
	return p and CFrame.new(p) or nil
end
-- "101100" -> {true, false, ...}
local function bitsOf(s: any, n: number?): { boolean }
	local out = {}
	local str = type(s) == "string" and s or ""
	for i = 1, n or 6 do
		out[i] = string.sub(str, i, i) == "1"
	end
	return out
end

function FinaleFX.Start(ctx)
	if FinaleFX.Started then
		return
	end
	FinaleFX.Started = true
	local Shared, Config, Layout, Bus, FX, Audio = ctx.Shared, ctx.Config, ctx.Layout, ctx.Bus, ctx.FX, ctx.Audio
	local player = ctx.Player or Players.LocalPlayer
	local L = Shared.L
	local T = FinaleFX.Timing
	local Halloween = RS:WaitForChild("Halloween")
	local ModelsFolder = Halloween:WaitForChild("Models")
	local Models = require(ModelsFolder:WaitForChild("Finale"))
	local BossModels = require(ModelsFolder:WaitForChild("Boss"))
	local stateRoot = Halloween:WaitForChild("State")
	local C2Cfg: any = nil
	pcall(function()
		local m = Halloween:FindFirstChild("Chapter2Config")
		C2Cfg = m and require(m) or nil
	end)
	local FC = (C2Cfg and C2Cfg.Finale) or {}
	local Mixer: any = nil
	pcall(function()
		local m = RS:FindFirstChild("AudioMixer")
		Mixer = m and require(m) or nil
	end)
	local Music: any = nil
	pcall(function()
		local m = Halloween:FindFirstChild("Music")
		Music = m and require(m) or nil
	end)
	local PIT = Layout.Pit.Center

	---------------------------------------------------------------------------------------------------------------
	-- small helpers
	---------------------------------------------------------------------------------------------------------------
	local function now(): number
		return Shared.Now()
	end
	local function finaleFolder(): Instance?
		return stateRoot:FindFirstChild("Finale")
	end
	local function FA(name: string): any
		local f = finaleFolder()
		return f and f:GetAttribute(name)
	end
	local function BA(name: string): any
		local f = stateRoot:FindFirstChild("Boss")
		return f and f:GetAttribute(name)
	end
	local function reduced(): boolean
		return Shared.ReducedMotion()
	end
	local function budget(): number
		local ok, v = pcall(Shared.Budget, "FinaleFX")
		local n = ok and tonumber(v) or 1
		if not n or n <= 0 then
			n = 1
		end
		return math.clamp(n, .2, 1)
	end
	local function play(cue: string, where: any?, opts: any?)
		if not (Audio and Audio.Play) then
			return
		end
		if Audio.Has and not Audio.Has(cue) then
			return
		end
		pcall(Audio.Play, cue, where, opts)
	end
	local function cinema(): any
		local m = ctx.Modules and ctx.Modules.Cinema
		if m then
			return m
		end
		local ok, c = pcall(function()
			local inst = script.Parent and script.Parent:FindFirstChild("Cinema")
			return inst and require(inst :: ModuleScript)
		end)
		return ok and c or nil
	end
	local function shake(amount: number, dur: number)
		local c = cinema()
		if c and c.Shake then
			pcall(c.Shake, amount, dur)
		elseif FX and FX.Shake then
			FX.Shake(amount, dur)
		end
	end
	local function impulse(strength: number)
		local c = cinema()
		if c and c.Impulse then
			pcall(c.Impulse, strength)
		end
	end
	local function flash(color: Color3, strength: number, dur: number)
		if reduced() then
			return
		end
		local c = cinema()
		if c and c.Flash then
			pcall(c.Flash, color, strength, dur)
		elseif FX and FX.Flash then
			FX.Flash(color, strength, dur)
		end
	end
	local function title(en: string, ru: string, opts: any?): any
		local c = cinema()
		if c and c.Title then
			local ok, h = pcall(c.Title, en, ru, opts)
			return ok and h or nil
		end
		Bus.Fire("Banner", { Title = L(en, ru), Subtitle = opts and opts.Sub and L(opts.Sub[1], opts.Sub[2]) or nil, Color = opts and opts.Color or VIOLET,
			Style = "Boss", Seconds = opts and opts.Duration or 3.5, NoTranslate = true })
		return nil
	end
	local function banner(en: string, ru: string, subEn: string?, subRu: string?, color: Color3?, seconds: number?)
		Bus.Fire("Banner", { Title = L(en, ru), Subtitle = subEn and L(subEn, subRu) or nil, Color = color or VIOLET, Style = "Boss",
			Seconds = seconds or 3.2, NoTranslate = true })
	end
	local function popup(pos: Vector3, text: string, color: Color3?, big: boolean?)
		if FX and FX.Popup then
			pcall(FX.Popup, pos, text, color, big)
		end
	end
	local function myRoot(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return (r and r:IsA("BasePart")) and r or nil
	end
	local function camPos(): Vector3
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or PIT
	end
	local function downed(): boolean
		return player:GetAttribute("HwDowned") == true
	end
	-- in or near the Dead Yard (the finale signals go to the zone; spectators on the rim see it all)
	local function nearArena(): boolean
		local r = myRoot()
		local p = r and r.CFrame.Position or camPos()
		return flat(p - PIT).Magnitude < 150 or Layout.InZone(p, 12)
	end
	local function look(at: Vector3, target: Vector3): CFrame
		return BossModels.Look(at, target)
	end
	local function moveParts(parts: { BasePart }, cfs: { CFrame })
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for i, p in ipairs(parts) do
				p.CFrame = cfs[i]
			end
		end
	end
	local function eachPart(root: Instance, fn: (BasePart) -> ())
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				fn(d)
			end
		end
	end
	-- an anchored model made one rigid assembly: every part welded to the PrimaryPart, so moving the root moves it all
	local function rigidify(m: Model): BasePart?
		local root = m.PrimaryPart
		if not root then
			return nil
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root then
				local w = Instance.new("Weld")
				w.Name = "FinaleWeld"
				w.Part0 = root
				w.Part1 = d
				w.C0 = root.CFrame:Inverse() * d.CFrame
				w.Parent = d
				d.Anchored = false
				d.Massless = true
			end
		end
		root.Anchored = true
		return root
	end
	local function setModelFade(m: Instance, k: number)
		-- k = 0 visible .. 1 gone (keeps every part's own transparency as the floor)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = math.clamp(k, 0, 1)
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				if d:GetAttribute("FinaleBase") == nil then
					d:SetAttribute("FinaleBase", d.Brightness)
				end
				d.Brightness = (d:GetAttribute("FinaleBase") or 1) * (1 - math.clamp(k, 0, 1))
			end
		end
	end
	local function mainGui(): ScreenGui?
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("ScreenGui")
		return (g and g:IsA("ScreenGui")) and g or nil
	end
	local function newGui(class: string, props: { [string]: any }, parent: Instance?): any
		local o: any = Instance.new(class)
		for k, v in pairs(props) do
			o[k] = v
		end
		if parent then
			o.Parent = parent
		end
		return o
	end
	local function corner(o: Instance, r: any)
		local c = Instance.new("UICorner")
		c.CornerRadius = r == "pill" and UDim.new(.5, 0) or UDim.new(0, tonumber(r) or 10)
		c.Parent = o
	end
	local function stroke(o: Instance, color: Color3, thick: number, tr: number?): UIStroke
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thick
		s.Transparency = tr or 0
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = o
		return s
	end
	local function label(parent: Instance, props: { [string]: any }): TextLabel
		local t = newGui("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextScaled = true, TextColor3 = props.Color or WHITE,
			Text = props.Text or "", Size = props.Size or UDim2.fromScale(1, 1), Position = props.Position or UDim2.new(),
			AnchorPoint = props.AnchorPoint or Vector2.zero, TextXAlignment = props.AlignX or Enum.TextXAlignment.Center,
			ZIndex = props.ZIndex or 2, Name = props.Name or "Label", TextTransparency = props.Transparency or 0 }, parent)
		t:SetAttribute("NoTranslate", true)
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = props.Max or 28
		lim.MinTextSize = props.Min or 9
		lim.Parent = t
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = props.Stroke or 2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
		return t
	end
	local function tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
		tw:Play()
		return tw
	end
	local function billboard(adornee: Instance, size: UDim2, offset: Vector3?, maxDist: number?, onTop: boolean?): BillboardGui
		local g = Instance.new("BillboardGui")
		g.Size = size
		g.StudsOffset = offset or Vector3.zero
		g.LightInfluence = 0
		g.AlwaysOnTop = onTop == true
		g.MaxDistance = maxDist or 260
		g.ResetOnSpawn = false
		g:SetAttribute("NoTranslate", true)
		g.Adornee = adornee
		g.Parent = adornee
		return g
	end
	local function targetsFolder(): Instance?
		local live = workspace:FindFirstChild("HalloweenLive")
		return live and live:FindFirstChild("Targets")
	end
	-- live finale Strike targets of a kind: {[TargetId] = part}
	local function targetsOf(kind: string): { [any]: BasePart }
		local out = {}
		local f = targetsFolder()
		if f then
			for _, p in ipairs(f:GetChildren()) do
				if p:IsA("BasePart") and p:GetAttribute("Kind") == kind and p:GetAttribute("EndReason") == nil then
					local id = p:GetAttribute("TargetId")
					if id ~= nil then
						out[id] = p
					end
				end
			end
		end
		return out
	end
	local function targetById(id: any): BasePart?
		local f = targetsFolder()
		if not f or id == nil then
			return nil
		end
		for _, p in ipairs(f:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("TargetId") == id then
				return p
			end
		end
		return nil
	end

	---------------------------------------------------------------------------------------------------------------
	-- the session: everything one finale builds lives here, so a single teardown releases it all
	---------------------------------------------------------------------------------------------------------------
	local S: any = nil
	local LIGHT_PROFILES = {
		FINALE_FAKE = { Prio = 46, Grade = { Tint = RGB(222, 216, 240), Saturation = -.4, Contrast = .14 } },
		FINALE_BELL = { Prio = 45,
			Lighting = { Ambient = RGB(70, 54, 110), OutdoorAmbient = RGB(92, 70, 140), ColorShift_Top = RGB(130, 80, 220) },
			Atmo = { Density = .33, Color = RGB(84, 64, 140), Decay = RGB(40, 20, 80), Haze = 2.0, Glare = 0 },
			Grade = { Tint = RGB(232, 220, 255), Saturation = -.05, Contrast = .16 },
			Bloom = { Intensity = .6, Size = 30, Threshold = 1.15 } },
		FINALE_CHOIR = { Prio = 46,
			Lighting = { Ambient = RGB(64, 70, 104), OutdoorAmbient = RGB(84, 96, 140), ColorShift_Top = RGB(110, 140, 220) },
			Atmo = { Density = .46, Offset = .3, Color = RGB(104, 116, 150), Decay = RGB(54, 60, 96), Haze = 2.8, Glare = 0 },
			Grade = { Tint = RGB(220, 232, 255), Saturation = -.18, Contrast = .12 },
			Bloom = { Intensity = .7, Size = 34, Threshold = 1.05 } },
		FINALE_HOUND = { Prio = 47,
			Lighting = { ClockTime = 0, Brightness = 1.2, Ambient = RGB(58, 36, 92), OutdoorAmbient = RGB(78, 48, 120), ColorShift_Top = RGB(160, 80, 255) },
			Atmo = { Density = .36, Color = RGB(56, 30, 92), Decay = RGB(24, 8, 48), Haze = 2.2, Glare = .3 },
			Grade = { Tint = RGB(226, 206, 255), Saturation = .02, Contrast = .22 },
			Bloom = { Intensity = .75, Size = 34, Threshold = 1.0 }, Sky = { MoonAngularSize = 0, StarCount = 600 } },
		FINALE_DAWN = { Prio = 48,
			Lighting = { ClockTime = 5.9, Brightness = 2.0, ExposureCompensation = .3, Ambient = RGB(120, 146, 196), OutdoorAmbient = RGB(150, 178, 226),
				ColorShift_Top = RGB(170, 206, 255) },
			Atmo = { Density = .22, Offset = .1, Color = RGB(170, 196, 236), Decay = RGB(96, 120, 170), Haze = 1.2, Glare = .5 },
			Grade = { Tint = RGB(226, 238, 255), Saturation = -.02, Contrast = .06, Brightness = .04 },
			Bloom = { Intensity = .55, Size = 30, Threshold = 1.2 } },
		FINALE_FAIL = { Prio = 49,
			Lighting = { Ambient = RGB(46, 42, 60), OutdoorAmbient = RGB(58, 54, 74) },
			Atmo = { Density = .4, Color = RGB(48, 44, 62), Decay = RGB(20, 18, 30), Haze = 2.4 },
			Grade = { Tint = RGB(196, 188, 222), Saturation = -.75, Contrast = .26, Brightness = -.06 } },
	}
	FinaleFX.Moods = LIGHT_PROFILES

	local teardown -- (defined below)

	-- geometry: the live pit (defaults <- replicated attributes <- payloads) or the replay's memory stage
	local function liveGeometry(): any
		local d = Models.Defaults(Layout, FC)
		local G = { Pit = PIT, BellCF = d.BellCF, Anchors = d.Chains, ChainAlong = d.ChainAlong, Candles = d.Candles, HoundCF = d.HoundCF,
			MoonDir = d.MoonDir, JawPos = d.JawPos, FloorY = Layout.Pit.FloorY }
		local bcf = cfOf(FA("BellCF"))
		if bcf then
			G.BellCF = bcf
		end
		local hcf = cfOf(FA("HoundCF"))
		if hcf then
			G.HoundCF = hcf
		end
		local jaw = vecOf(FA("JawPos"))
		if jaw then
			G.JawPos = jaw
		end
		return G
	end

	local function newSession(replay: boolean?): any
		local folder = Instance.new("Folder")
		folder.Name = replay and "DOGROTS_FinaleReplay" or "DOGROTS_Finale"
		folder:SetAttribute("SelfManagedFX", true)
		folder.Parent = FX.Folder()
		local s = {
			Replay = replay == true, Root = folder, Stage = "", Entered = {}, Cues = {}, Conns = {}, Ducks = {}, Layers = {}, Guis = {},
			Chains = {}, Anchors = {}, Candles = {}, Ghosts = {}, Weak = {}, Halo = {}, Debris = {}, Moths = {}, Popups = {},
			FightId = FA("FightId"), G = if replay then nil else liveGeometry(), StageClock = os.clock(), Born = os.clock(), Q = budget(),
		}
		return s
	end
	local function ensureSession(): any
		if S and S.Replay then
			teardown("Live", true)
		end
		if not S then
			S = newSession(false)
		end
		return S
	end
	-- run fn at server time `at` (or now when past); cues die with the session
	local function cue(at: number, fn: () -> (), name: string?)
		if not S then
			return
		end
		table.insert(S.Cues, { At = at, Fn = fn, Name = name })
	end
	local function stepCues()
		if not S then
			return
		end
		local t = now()
		local due = {}
		for i = #S.Cues, 1, -1 do
			local c = S.Cues[i]
			if t >= c.At then
				table.remove(S.Cues, i)
				table.insert(due, c)
			end
		end
		table.sort(due, function(a, b)
			return a.At < b.At
		end)
		for _, c in ipairs(due) do
			local ok, err = pcall(c.Fn)
			if not ok then
				warn("Halloween FinaleFX cue " .. tostring(c.Name) .. ": " .. tostring(err))
			end
			if not S then
				return
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- audio ducks + the music guard
	---------------------------------------------------------------------------------------------------------------
	local function duck(reason: string, levels: any, fade: number?)
		if not (S and Mixer and Mixer.Duck) then
			return
		end
		local key = "Finale:" .. reason
		local ok = pcall(Mixer.Duck, key, levels, fade)
		if ok then
			S.Ducks[key] = true
		end
	end
	local function release(reason: string, fade: number?)
		if not (S and Mixer and Mixer.Release) then
			return
		end
		local key = "Finale:" .. reason
		if S.Ducks[key] then
			S.Ducks[key] = nil
			pcall(Mixer.Release, key, fade)
		end
	end

	-- the finale theme for the current stage (the soundscape's answer; also used by the guard below)
	local function wantedTheme(): (string?, any)
		if not S or S.Replay then
			return nil, nil
		end
		local st = S.Stage
		if st == "Bell" then
			return "FINALE_BELL", { Fade = 2 }
		elseif st == "Choir" then
			return "FINALE_CHOIR", { Fade = 2.5 }
		elseif st == "Hound" then
			local start = (S.Hound and S.Hound.Start) or tonumber(FA("StartAt")) or tonumber(FA("StageStart")) or now()
			return "FINALE_HOUND", { Fade = 1.5, Elapsed = math.max(0, now() - start) }
		end
		return nil, nil
	end
	function FinaleFX.MusicTheme(): (string?, any)
		return wantedTheme()
	end
	local function musicGuard()
		if not (S and Music and Music.Theme and Music.SetTheme) or player:GetAttribute("Music") == false then
			return
		end
		local theme, opts = wantedTheme()
		if not theme or os.clock() - (S.StageClock or 0) < 1.2 then
			return -- the soundscape gets the first word
		end
		if Music.Theme() ~= theme then
			pcall(Music.SetTheme, theme, opts)
			S.MusicForced = theme
		end
	end
	local function handMusicBack()
		if not (S and S.MusicForced and Music and Music.Theme) then
			return
		end
		if Music.Theme() == S.MusicForced then
			local ss = ctx.Modules and ctx.Modules.Soundscape
			local theme = ss and ss.Theme and ss.Theme() or nil
			if theme == S.MusicForced then
				theme = nil
			end
			pcall(Music.SetTheme, theme, { Fade = 3 })
		end
		S.MusicForced = nil
	end

	---------------------------------------------------------------------------------------------------------------
	-- lighting moods (Halloween Lighting layers; a camera grade when the compositor is absent)
	---------------------------------------------------------------------------------------------------------------
	local function lightingModule(): any
		local m = ctx.Modules and ctx.Modules.Lighting
		return (m and m.Layer) and m or nil
	end
	local function setMood(name: string?, fade: number?)
		if not S then
			return
		end
		S.Mood = name
		local lm = lightingModule()
		if lm then
			if name and not S.Layers[name] and LIGHT_PROFILES[name] then
				local ok, h = pcall(lm.Layer, name, LIGHT_PROFILES[name])
				if ok and h then
					S.Layers[name] = h
				end
			end
			for n, h in pairs(S.Layers) do
				pcall(h.Set, h, n == name and 1 or 0, fade or 2)
			end
			return
		end
		-- fallback: a camera colour grade only
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local g = S.Grade
		if not (g and g.Parent) then
			g = Instance.new("ColorCorrectionEffect")
			g.Name = "DOGROTS_FinaleGrade"
			g.Parent = cam
			S.Grade = g
		end
		local p = name and LIGHT_PROFILES[name] and LIGHT_PROFILES[name].Grade or {}
		tween(g, fade or 2, { TintColor = p.Tint or WHITE, Saturation = p.Saturation or 0, Contrast = p.Contrast or 0, Brightness = p.Brightness or 0 })
	end

	---------------------------------------------------------------------------------------------------------------
	-- cinematics (Cinema): never while downed; in-combat shots end the moment a hazard telegraph appears
	---------------------------------------------------------------------------------------------------------------
	local function stopShot(reason: string?)
		if S and S.Cine then
			local h = S.Cine
			S.Cine = nil
			pcall(function()
				if h.Running and h.Running() then
					h.Cancel()
				end
			end)
			local _ = reason
		end
	end
	-- opts: Id, Duration, Shot, Focus, InCombat, LockControls, Force, Letterbox, SkipAfter, Retry (seconds to keep trying
	-- while a timing session / menu blocks the camera)
	local function shot(opts: any): boolean
		-- (the journal replay runs one cinematic over the whole memory: no shots inside it)
		if not S or S.Replay or downed() then
			return false
		end
		if opts.InCombat and reduced() then
			return false
		end
		local c = cinema()
		if not (c and c.Play) then
			return false
		end
		stopShot("Replaced")
		local h, why = c.Play({
			Id = opts.Id, Duration = opts.Duration, Shot = opts.Shot, Focus = opts.Focus, Fov = opts.Fov, Letterbox = opts.Letterbox ~= false,
			Skippable = true, SkipAfter = opts.SkipAfter or .8, LockControls = opts.LockControls ~= false, HideUI = opts.HideUI ~= false,
			Duck = false, Force = opts.Force, BlendIn = opts.BlendIn or .7, BlendOut = opts.BlendOut or .7, Timeline = opts.Timeline,
			OnDone = function()
				if S and S.Cine and S.Cine.Id == opts.Id then
					S.Cine = nil
				end
			end,
		})
		if h and not S then
			-- (the session ended while the shot started)
			pcall(h.Cancel)
			return false
		end
		if h then
			h.InCombat = opts.InCombat == true
			S.Cine = h
			return true
		end
		if opts.Retry and opts.Retry > 0 and (why == "Mining" or why == "Busy" or why == "Camera") then
			local left = opts.Retry - .25
			local o2 = table.clone(opts)
			o2.Retry = left
			o2.Duration = math.max(.8, (opts.Duration or 3) - .25)
			cue(now() + .25, function()
				if S and not S.Cine then
					shot(o2)
				end
			end, "ShotRetry")
		end
		return false
	end

	---------------------------------------------------------------------------------------------------------------
	-- the finale panel (stage, objective, timer, chains / candles / bark points)
	---------------------------------------------------------------------------------------------------------------
	local function destroyPanel()
		if S and S.Panel then
			local p = S.Panel
			S.Panel = nil
			if p.Gui then
				p.Gui:Destroy()
			end
		end
	end
	local function buildPanel(): any
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return nil
		end
		local main = mainGui()
		local gui = newGui("ScreenGui", { Name = "DOGROTS_FinaleHUD", DisplayOrder = 42, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			IgnoreGuiInset = main and main.IgnoreGuiInset or false })
		gui:SetAttribute("HideWithUI", true)
		gui:SetAttribute("NoTranslate", true)
		local frame = newGui("Frame", { Name = "Panel", AnchorPoint = Vector2.new(.5, 0), BackgroundColor3 = INK, BackgroundTransparency = .18,
			BorderSizePixel = 0, Active = false }, gui)
		corner(frame, 14)
		local edge = stroke(frame, VIOLET, 2, .1)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(RGB(46, 26, 74), RGB(14, 10, 24))
		grad.Parent = frame
		local p: any = { Gui = gui, Frame = frame, Edge = edge, Cells = {}, Pips = {}, LagFrac = 1, Built = os.clock() }
		p.Title = label(frame, { Name = "Title", AlignX = Enum.TextXAlignment.Left, Max = 22, Color = VIOLET_HOT })
		p.Goal = label(frame, { Name = "Goal", AlignX = Enum.TextXAlignment.Left, Max = 15, Min = 8, Color = BONE, Stroke = 1.5 })
		p.Timer = label(frame, { Name = "Timer", AlignX = Enum.TextXAlignment.Right, Max = 20, Color = GOLD_HOT })
		-- the bar row (chains / candles / bark points)
		p.Track = newGui("Frame", { Name = "Track", BackgroundColor3 = RGB(10, 6, 16), BorderSizePixel = 0 }, frame)
		corner(p.Track, 8)
		stroke(p.Track, WHITE, 1.5, .7)
		p.Lag = newGui("Frame", { Name = "Lag", BackgroundColor3 = RGB(255, 236, 220), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, p.Track)
		corner(p.Lag, 8)
		p.Fill = newGui("Frame", { Name = "Fill", BackgroundColor3 = VIOLET, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, p.Track)
		corner(p.Fill, 8)
		p.Num = label(p.Track, { Name = "Num", Max = 18, Color = WHITE, ZIndex = 3 })
		-- pulse lamp (bell: the bright part of the chain's pulse) / counter chip (hound)
		p.Chip = newGui("Frame", { Name = "Chip", BackgroundColor3 = VIOLET_DEEP, BorderSizePixel = 0, Visible = false }, frame)
		corner(p.Chip, "pill")
		p.ChipStroke = stroke(p.Chip, WHITE, 2, .2)
		p.ChipText = label(p.Chip, { Name = "Text", Max = 16, Color = WHITE, ZIndex = 3 })
		-- six candle cells / four chain pips
		for i = 1, 6 do
			local c = newGui("Frame", { Name = "Cell" .. i, BackgroundColor3 = RGB(30, 22, 40), BorderSizePixel = 0, Visible = false }, frame)
			corner(c, 8)
			local st = stroke(c, ASH, 2, .1)
			local mark = newGui("Frame", { Name = "Target", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .2), Size = UDim2.fromScale(.42, .26),
				BackgroundColor3 = VIOLET_HOT, BorderSizePixel = 0, ZIndex = 3 }, c)
			corner(mark, "pill")
			local num = label(c, { Name = "Num", Max = 18, Color = WHITE, ZIndex = 3, Position = UDim2.fromScale(0, .32), Size = UDim2.fromScale(1, .66),
				Text = ROMAN[i] })
			p.Cells[i] = { Frame = c, Stroke = st, Mark = mark, Num = num }
		end
		for i, key in ipairs(Models.Keys) do
			local pip = newGui("Frame", { Name = "Pip" .. key, BackgroundColor3 = RGB(30, 22, 40), BorderSizePixel = 0, Visible = false }, frame)
			corner(pip, "pill")
			local st = stroke(pip, VIOLET, 2, .3)
			local t = label(pip, { Name = "Key", Max = 16, Color = WHITE, ZIndex = 3, Text = key })
			p.Pips[i] = { Frame = pip, Stroke = st, Text = t, Key = key }
		end
		gui.Parent = pg
		return p
	end
	local function placePanel(p: any)
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local narrow = touch or vp.X < 760
		local w = math.floor(math.min(narrow and 360 or 500, vp.X - 32))
		local h = narrow and 70 or 84
		local main = mainGui()
		local top = main and tonumber(main:GetAttribute("HwStripBottom")) or nil
		local y = (top and top > 0) and top + 8 or (narrow and 64 or 76)
		local key = w .. "x" .. h .. "@" .. y
		if p.Layout == key then
			return
		end
		p.Layout = key
		p.Frame.Position = UDim2.new(.5, 0, 0, y)
		p.Frame.Size = UDim2.fromOffset(w, h)
		local pad = narrow and 10 or 14
		local th = narrow and 20 or 24
		p.Title.Position, p.Title.Size = UDim2.fromOffset(pad, 5), UDim2.fromOffset(math.floor(w * .62), th)
		p.Timer.Position, p.Timer.Size = UDim2.fromOffset(w - pad - 90, 5), UDim2.fromOffset(90, th)
		p.Goal.Position, p.Goal.Size = UDim2.fromOffset(pad, 5 + th), UDim2.fromOffset(w - pad * 2, narrow and 14 or 17)
		local rowY = 5 + th + (narrow and 16 or 20)
		local rowH = h - rowY - 7
		p.RowY, p.RowH, p.Pad, p.W = rowY, rowH, pad, w
		local chipW = narrow and 96 or 120
		p.Track.Position, p.Track.Size = UDim2.fromOffset(pad, rowY), UDim2.fromOffset(w - pad * 2 - chipW - 8, rowH)
		p.Chip.Position, p.Chip.Size = UDim2.fromOffset(w - pad - chipW, rowY), UDim2.fromOffset(chipW, rowH)
		local cw = math.floor((w - pad * 2 - 5 * 6) / 6)
		for i, c in ipairs(p.Cells) do
			c.Frame.Position = UDim2.fromOffset(pad + (i - 1) * (cw + 6), rowY - 2)
			c.Frame.Size = UDim2.fromOffset(cw, rowH + 2)
		end
		local pw = math.floor(rowH * 1.25)
		for i, pip in ipairs(p.Pips) do
			pip.Frame.Position = UDim2.fromOffset(pad + (i - 1) * (pw + 6), rowY)
			pip.Frame.Size = UDim2.fromOffset(pw, rowH)
		end
	end
	local function clock(sec: number): string
		sec = math.max(0, math.floor(sec + .5))
		return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
	end
	local function setBar(p: any, frac: number, color: Color3, text: string)
		frac = math.clamp(frac, 0, 1)
		p.Fill.Size = UDim2.fromScale(frac, 1)
		p.Fill.Visible = frac > .003
		p.Fill.BackgroundColor3 = color
		if frac > p.LagFrac then
			p.LagFrac = frac
		else
			p.LagFrac = math.max(frac, p.LagFrac - .006)
		end
		p.Lag.Size = UDim2.fromScale(p.LagFrac, 1)
		p.Num.Text = text
	end
	local function updatePanel()
		if not S or S.Replay then
			return
		end
		local st = S.Stage
		if not PANEL_STAGES[st] or not nearArena() then
			destroyPanel()
			return
		end
		local p = S.Panel
		if not (p and p.Gui and p.Gui.Parent) then
			local ok, built = pcall(buildPanel)
			if not ok or not built then
				return
			end
			S.Panel = built
			p = built
		end
		local main = mainGui()
		local hidden = main ~= nil and (main:GetAttribute("OpenMenu") ~= nil or main:GetAttribute("UIHidden") == true or main:GetAttribute("CinemaActive") == true)
		p.Gui.Enabled = not hidden
		if hidden then
			return
		end
		placePanel(p)
		local t = now()
		local deadline = tonumber(FA("Deadline")) or 0
		p.Timer.Text = deadline > t and clock(deadline - t) or ""
		p.Timer.TextColor3 = (deadline > t and deadline - t < 60) and RGB(255, 120, 120) or GOLD_HOT
		for _, c in ipairs(p.Cells) do
			c.Frame.Visible = false
		end
		for _, pip in ipairs(p.Pips) do
			pip.Frame.Visible = false
		end
		p.Track.Visible, p.Chip.Visible = false, false
		if st == "Bell" then
			p.Title.Text = L("THE BELL TOLLS", "КОЛОКОЛ ЗВОНИТ")
			p.Edge.Color = VIOLET
			local active = tostring(FA("Chain") or "")
			local hits, need = tonumber(FA("ChainHits")) or 0, tonumber(FA("ChainNeed")) or 0
			local since, pulse, bright = tonumber(FA("ChainSince")) or 0, tonumber(FA("Pulse")) or 1.2, tonumber(FA("Bright")) or .55
			local isBright = active ~= "" and pulse > 0 and ((t - since) % pulse) / pulse < bright
			p.Goal.Text = active ~= "" and L("PERFECT hits on the glowing chain while it shines", "ИДЕАЛЬНЫЕ удары по светящейся цепи, пока она сияет")
				or L("The chains are taking hold...", "Цепи натягиваются...")
			-- chain pips (broken / active / waiting) then the active chain's progress
			local pipsW = 0
			for i, pip in ipairs(p.Pips) do
				local ch = S.Chains[pip.Key]
				local broken = ch and ch.Broken
				pip.Frame.Visible = true
				pip.Text.Text = broken and "✕" or pip.Key
				pip.Frame.BackgroundColor3 = broken and RGB(20, 16, 26) or (pip.Key == active and (isBright and VIOLET_HOT or VIOLET) or RGB(40, 30, 60))
				pip.Stroke.Color = pip.Key == active and WHITE or VIOLET
				pip.Stroke.Transparency = broken and .7 or .1
				pipsW = i * (pip.Frame.Size.X.Offset + 6)
			end
			p.Track.Visible = active ~= ""
			p.Track.Position = UDim2.fromOffset(p.Pad + pipsW + 4, p.RowY)
			p.Track.Size = UDim2.fromOffset(math.max(40, p.W - p.Pad * 2 - pipsW - 4 - p.Chip.Size.X.Offset - 8), p.RowH)
			setBar(p, need > 0 and hits / need or 0, isBright and VIOLET_HOT or VIOLET, need > 0 and (hits .. " / " .. need) or "")
			p.Chip.Visible = active ~= ""
			p.Chip.BackgroundColor3 = isBright and VIOLET_HOT or RGB(30, 20, 46)
			p.ChipText.Text = isBright and L("NOW!", "СЕЙЧАС!") or L("WAIT", "ЖДИ")
			p.ChipText.TextColor3 = isBright and INK or BONE
		elseif st == "Choir" then
			p.Title.Text = L("THE BURIED CHOIR", "ПОГРЕБЁННЫЙ ХОР")
			p.Edge.Color = MOON
			local round, rounds = tonumber(FA("Round")) or 1, tonumber(FA("Rounds")) or 3
			local weakUntil = tonumber(FA("WeakUntil")) or 0
			if weakUntil > t then
				local left = 0
				for _, w in pairs(S.Weak) do
					if not w.Gone then
						left += 1
					end
				end
				p.Goal.Text = L("Dig up the glowing weak points! ", "Раскопай светящиеся слабые места! ") .. clock(weakUntil - t)
				p.Track.Visible = true
				p.Track.Position = UDim2.fromOffset(p.Pad, p.RowY)
				p.Track.Size = UDim2.fromOffset(p.W - p.Pad * 2 - p.Chip.Size.X.Offset - 8, p.RowH)
				setBar(p, math.clamp((weakUntil - t) / math.max(1, (FC.Choir and FC.Choir.WeakSeconds) or 20), 0, 1), GOLD,
					L("WEAK POINTS ", "СЛАБЫЕ МЕСТА ") .. left)
			else
				p.Goal.Text = L("Strike the candles until they match the bell", "Бей по свечам, пока они не совпадут с колоколом")
				local target = bitsOf(FA("Pattern"))
				local now6 = bitsOf(FA("Candles"))
				for i, c in ipairs(p.Cells) do
					c.Frame.Visible = true
					c.Frame.BackgroundColor3 = now6[i] and CANDLE:Lerp(RGB(60, 30, 10), .25) or RGB(26, 20, 36)
					c.Mark.BackgroundColor3 = target[i] and VIOLET_HOT or RGB(50, 40, 64)
					c.Mark.BackgroundTransparency = target[i] and 0 or .2
					c.Stroke.Color = now6[i] == target[i] and SICKLY or RGB(255, 110, 110)
				end
			end
			p.Chip.Visible = true
			p.Chip.BackgroundColor3 = RGB(30, 26, 52)
			p.ChipText.Text = L("ROUND ", "РАУНД ") .. round .. "/" .. rounds
			p.ChipText.TextColor3 = MOON
		elseif st == "Hound" then
			p.Title.Text = L("THE LAST BARK", "ПОСЛЕДНИЙ ЛАЙ")
			p.Edge.Color = VIOLET_HOT
			local hp, max = tonumber(FA("HoundHP")) or 0, tonumber(FA("HoundMax")) or 0
			if S.Hound and S.Hound.HP then
				hp, max = S.Hound.HP, S.Hound.Max or max
			end
			local counterUntil = tonumber(FA("CounterUntil")) or 0
			local counter = counterUntil > t
			p.Goal.Text = counter and L("COUNTER! PERFECT hits on its open jaw", "КОНТРУДАР! ИДЕАЛЬНЫЕ удары по раскрытой пасти")
				or L("Dodge the patterns - strike when it barks", "Уклоняйся от атак - бей, когда она лает")
			p.Track.Visible = true
			p.Track.Position = UDim2.fromOffset(p.Pad, p.RowY)
			p.Track.Size = UDim2.fromOffset(p.W - p.Pad * 2 - p.Chip.Size.X.Offset - 8, p.RowH)
			setBar(p, max > 0 and hp / max or 0, counter and GOLD or VIOLET, max > 0 and (math.ceil(hp) .. " / " .. max) or "")
			p.Chip.Visible = true
			local blink = counter and (math.floor(os.clock() * 6) % 2 == 0)
			p.Chip.BackgroundColor3 = counter and (blink and GOLD_HOT or GOLD) or RGB(30, 20, 46)
			p.ChipText.Text = counter and (L("COUNTER ", "КОНТР ") .. string.format("%.1f", counterUntil - t)) or L("BARK POINTS", "ОЧКИ ЛАЯ")
			p.ChipText.TextColor3 = counter and INK or BONE
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE FALSE VICTORY: the fake reward card that cracks into ash
	---------------------------------------------------------------------------------------------------------------
	local function buildCard(): any
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return nil
		end
		local gui = newGui("ScreenGui", { Name = "DOGROTS_FinaleCard", DisplayOrder = 74, ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
		gui:SetAttribute("CinemaKeep", true)
		gui:SetAttribute("NoTranslate", true)
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local scale = math.clamp(math.min(vp.X / 520, vp.Y / 420), .55, 1.15)
		local card = newGui("Frame", { Name = "Card", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .44), Size = UDim2.fromOffset(380, 236),
			BackgroundColor3 = RGB(40, 26, 12), BorderSizePixel = 0, Active = false }, gui)
		corner(card, 18)
		local edge = stroke(card, GOLD, 3, 0)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(RGB(92, 60, 20), RGB(30, 18, 10))
		g.Parent = card
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = scale * .4
		uiScale.Parent = card
		local head = label(card, { Name = "Head", Text = L("VICTORY!", "ПОБЕДА!"), Color = GOLD_HOT, Max = 34, Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 40) })
		local sub = label(card, { Name = "Sub", Text = L("THE GRAVEKEEPER FALLS!", "СМОТРИТЕЛЬ ПОВЕРЖЕН!"), Color = WHITE, Max = 22,
			Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 28) })
		local rows = {}
		for i, txt in ipairs({ L("+??? CANDY", "+??? КОНФЕТ"), L("+??? BONES", "+??? КОСТЕЙ"), L("??? REWARD", "??? НАГРАДА") }) do
			local r = newGui("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(28, 92 + (i - 1) * 42), Size = UDim2.new(1, -56, 0, 34),
				BackgroundColor3 = RGB(20, 12, 6), BackgroundTransparency = .25, BorderSizePixel = 0 }, card)
			corner(r, 10)
			label(r, { Name = "Text", Text = txt, Color = GOLD, Max = 18, Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4) })
			table.insert(rows, r)
		end
		gui.Parent = pg
		tween(uiScale, .5, { Scale = scale }, Enum.EasingStyle.Back)
		return { Gui = gui, Card = card, Edge = edge, Scale = uiScale, Base = scale, Head = head, Sub = sub, Rows = rows, Cracks = {}, Ash = {} }
	end
	local function crackCard(c: any)
		if not (c and c.Card and c.Card.Parent) then
			return
		end
		-- jagged crack lines spreading from an impact point, the gold turns to grey
		local pts = { { .52, .3 }, { .44, .46 }, { .58, .62 }, { .48, .8 }, { .55, 1 } }
		local branches = { { 2, .2, .55 }, { 3, .8, .5 }, { 4, .3, .95 }, { 1, .76, .12 } }
		local function line(a: { number }, b: { number }, w: number)
			local ax, ay = a[1] * 380, a[2] * 236
			local bx, by = b[1] * 380, b[2] * 236
			local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
			local f = newGui("Frame", { Name = "Crack", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
				Size = UDim2.fromOffset(len, w), Rotation = math.deg(math.atan2(by - ay, bx - ax)), BackgroundColor3 = VIOLET_HOT, BorderSizePixel = 0,
				ZIndex = 6, BackgroundTransparency = 1 }, c.Card)
			tween(f, .25, { BackgroundTransparency = 0 })
			table.insert(c.Cracks, f)
		end
		for i = 1, #pts - 1 do
			line(pts[i], pts[i + 1], 4)
		end
		for _, b in ipairs(branches) do
			line(pts[b[1]], { b[2], b[3] }, 2.5)
		end
		tween(c.Edge, .6, { Color = ASH })
		tween(c.Head, .6, { TextColor3 = ASH })
		tween(c.Sub, .6, { TextColor3 = RGB(170, 160, 180) })
		c.Shake = os.clock()
	end
	local function ashCard(c: any)
		if not (c and c.Card and c.Card.Parent) then
			return
		end
		-- the card burns away to ash: flakes drift up and out, the card fades and sinks
		local n = math.floor(26 * (S and S.Q or 1))
		for i = 1, n do
			local fl = newGui("Frame", { Name = "Ash", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(rand(20, 360), rand(20, 216)),
				Size = UDim2.fromOffset(rand(4, 10), rand(4, 10)), Rotation = rand(0, 90), BackgroundColor3 = (i % 3 == 0) and VIOLET or ASH,
				BorderSizePixel = 0, ZIndex = 7 }, c.Card)
			local life = rand(.9, 1.6)
			tween(fl, life, { Position = fl.Position + UDim2.fromOffset(rand(-90, 90), rand(-180, -60)), Rotation = rand(-180, 180), BackgroundTransparency = 1 },
				Enum.EasingStyle.Sine)
			table.insert(c.Ash, fl)
		end
		for _, d in ipairs(c.Card:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, .8, { TextTransparency = 1 })
				local s = d:FindFirstChildOfClass("UIStroke")
				if s then
					tween(s, .8, { Transparency = 1 })
				end
			elseif d:IsA("Frame") and d.Name ~= "Ash" then
				tween(d, .9, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, .9, { Transparency = 1 })
			end
		end
		tween(c.Card, 1.1, { BackgroundTransparency = 1, Position = UDim2.fromScale(.5, .47) })
		tween(c.Scale, 1.1, { Scale = c.Base * .92 })
	end
	local function destroyCard()
		if S and S.Card then
			local c = S.Card
			S.Card = nil
			if c.Gui then
				c.Gui:Destroy()
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE GRAVEKEEPER'S SPIRIT
	---------------------------------------------------------------------------------------------------------------
	local function corpseCore(): Vector3
		if S and S.ReplayCorpse then
			return S.ReplayCorpse.Core
		end
		local bfx = ctx.Modules and ctx.Modules.BossFX
		if bfx and bfx.CorpsePos then
			local ok, p = pcall(bfx.CorpsePos)
			if ok and typeof(p) == "Vector3" then
				return p
			end
		end
		local cf = BA("BossCF")
		if typeof(cf) == "CFrame" then
			return Vector3.new(cf.Position.X, Layout.Pit.FloorY + 7, cf.Position.Z)
		end
		local G = S and S.G
		return (G and G.Pit or PIT) + V3(0, 7, 0)
	end
	local function spawnSpirit(from: Vector3): any
		if S.Spirit then
			return S.Spirit
		end
		local m = Models.Spirit()
		local rig = BossModels.Rig(m)
		m.Parent = S.Root
		local sp = { Model = m, Rig = rig, Pos = from, Mode = "Tear", T0 = os.clock(), From = from, Cur = {}, Visible = true }
		m:PivotTo(CF(from))
		S.Spirit = sp
		return sp
	end
	local function spiritBurst(pos: Vector3, big: boolean?)
		local q = S and S.Q or 1
		FX.Burst(pos, { Color = SICKLY, Color2 = VIOLET, Count = math.floor((big and 60 or 26) * q), Speed = { 8, big and 26 or 14 },
			Lifetime = { .5, 1.2 }, Size = { .7, 1.3, 0 } })
		FX.Light(pos, SICKLY, big and 60 or 30, big and 5 or 3, .8)
	end
	local function spiritVisible(sp: any, on: boolean)
		if sp.Visible == on then
			return
		end
		sp.Visible = on
		setModelFade(sp.Model, on and 0 or 1)
	end
	local function stepSpirit(dt: number)
		local sp = S and S.Spirit
		if not sp then
			return
		end
		local t = os.clock()
		local e = t - sp.T0
		local G = S.G
		local hover = (G and G.Pit or PIT) + V3(0, 16, 0)
		local pos = sp.Pos
		local k = 1
		if sp.Mode == "Tear" then
			-- torn out of the corpse: a violent rise with a shudder, then it hangs over the pit
			local a = smooth(e / 1.3)
			pos = sp.From:Lerp(hover, a) + V3(math.sin(e * 31) * .3 * (1 - a), math.sin(a * PI) * 4, 0)
			if e > 1.3 then
				sp.Mode = "Hover"
			end
		elseif sp.Mode == "Hover" then
			pos = hover + V3(math.sin(t * 1.3) * 1.5, math.sin(t * 2.1) * .8, math.cos(t * 1.1) * 1.2)
		elseif sp.Mode == "Fly" then
			-- into the bell, into the hound, back from the rim: a curved dash to sp.To over sp.Dur
			local a = smooth(e / (sp.Dur or 1))
			local mid = sp.From:Lerp(sp.To, .5) + V3(0, 8, 0)
			pos = sp.From:Lerp(mid, a):Lerp(mid:Lerp(sp.To, a), a)
			if e >= (sp.Dur or 1) then
				local done = sp.OnArrive
				sp.OnArrive = nil
				sp.Mode = sp.After or "Hidden"
				sp.T0 = t
				if done then
					pcall(done)
				end
			end
		elseif sp.Mode == "Throw" then
			pos = sp.To + V3(0, math.sin(t * 2) * .5, 0)
			k = 1 + math.sin(math.clamp(e / .7, 0, 1) * PI) * .8
			if e > 1.4 then
				spiritBurst(pos + V3(0, 7, 0), false)
				sp.Mode = "Hidden"
			end
		end
		if sp.Mode == "Hidden" then
			spiritVisible(sp, false)
			return
		end
		spiritVisible(sp, true)
		sp.Pos = pos
		local face = flat(camPos() - pos)
		if sp.Mode == "Throw" and sp.Face then
			face = flat(sp.Face - pos)
		end
		local yaw = face.Magnitude > .1 and math.atan2(-face.X, -face.Z) or 0
		sp.Rig.Root.CFrame = CF(pos) * ANG(0, yaw, 0)
		local P = Models.SpiritPose(t, math.min(1, k))
		if sp.Mode == "Throw" then
			local a = math.sin(math.clamp(e / .7, 0, 1) * PI)
			P.ArmL = ANG(1.1 * a, 0, -.2)
			P.ArmR = ANG(1.1 * a, 0, .2)
			P.Jaw = ANG(-.9 * a, 0, 0)
		end
		local kk = 1 - math.exp(-dt * 12)
		for name, m in pairs(sp.Rig.Motors) do
			local cur = sp.Cur[name] or CF()
			cur = cur:Lerp(P[name] or CF(), kk)
			sp.Cur[name] = cur
			m.Transform = cur
		end
	end
	local function spiritFly(to: Vector3, dur: number, after: string?, onArrive: (() -> ())?)
		local sp = S and S.Spirit
		if not sp then
			return
		end
		sp.From = sp.Pos
		sp.To = to
		sp.Dur = dur
		sp.After = after
		sp.OnArrive = onArrive
		sp.Mode = "Fly"
		sp.T0 = os.clock()
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE BLACK BELL
	---------------------------------------------------------------------------------------------------------------
	local function bellRootCF(b: any): CFrame
		return b.CF * CF(Models.BellHang) + V3(0, b.Drop or 0, 0)
	end
	local function bellCenter(b: any): Vector3
		return (bellRootCF(b) * CF(-Models.BellHang)).Position
	end
	local function bellSwingCF(b: any): CFrame
		return b.SwingCF or CF()
	end
	-- world position of a chain eye on the bell, following its swing
	local function bellEye(b: any, key: string): Vector3
		local loc = b.Eyes[key] or V3(0, -5, 0)
		return (bellRootCF(b) * bellSwingCF(b) * CF(loc)).Position
	end
	local function buildBell(cf: CFrame): any
		local q = S.Q
		local m = Models.Bell({ Detail = q })
		m.Name = "TheBlackBell"
		-- the chain eyes, relative to the root (the hang point), read before the rig moves anything
		local root = m.PrimaryPart :: BasePart
		local eyes = {}
		local slots = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Attachment") and string.sub(d.Name, 1, 9) == "ChainEye_" then
				local parent = d.Parent :: BasePart
				eyes[string.sub(d.Name, 10)] = root.CFrame:PointToObjectSpace((parent.CFrame * d.CFrame).Position)
			elseif d:IsA("Model") and d:GetAttribute("Slot") then
				local glyph, rim = {}, {}
				for _, p in ipairs(d:GetDescendants()) do
					if p:IsA("BasePart") then
						if p.Name == "Glyph" then
							table.insert(glyph, p)
						elseif p.Name == "SlotRim" then
							table.insert(rim, p)
						end
					end
				end
				slots[d:GetAttribute("Slot")] = { Glyph = glyph, Rim = rim }
			end
		end
		local runes, rimGlow, soul, light, crack = {}, {}, nil, nil, nil
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Rune" then
					table.insert(runes, d)
				elseif d.Name == "RimGlow" then
					table.insert(rimGlow, d)
				elseif d.Name == "SoulGlow" then
					soul = d
				elseif d.Name == "Crack" then
					table.insert(runes, d)
				end
			elseif d:IsA("PointLight") then
				if d.Parent and d.Parent.Name == "BellLight" then
					light = d
				elseif d.Parent and d.Parent.Name == "CrackLight" then
					crack = d
				end
			end
		end
		local rig = BossModels.Rig(m)
		m.Parent = S.Root
		local b = { Model = m, Rig = rig, CF = cf, Drop = 0, Eyes = eyes, Slots = slots, Runes = runes, RimGlow = rimGlow, Soul = soul, Light = light,
			CrackLight = crack, Swing = nil, SwingCF = CF(), Glow = 0, RuneBase = {} }
		for _, r in ipairs(runes) do
			b.RuneBase[r] = r.Color
		end
		rig.Root.CFrame = bellRootCF(b)
		-- the chain it hangs from, up into the dark
		local upper, uh = Models.Chain(math.floor(26 * math.max(.6, q)), { Detail = q, LinkLength = 3.2 })
		upper.Name = "HangChain"
		upper.Parent = S.Root
		b.Upper, b.UpperH = upper, uh
		return b
	end
	local function layUpper(b: any)
		if not b.UpperH then
			return
		end
		local top = bellRootCF(b).Position
		local parts, cfs = Models.LayChain(b.UpperH, { top, top + V3(0, 75, 0) })
		moveParts(parts, cfs)
	end
	local function bellToll(b: any, strength: number?)
		local s = strength or 1
		local dir = math.random() * 2 * PI
		b.Swing = { T0 = os.clock(), Amp = math.rad((reduced() and 4 or 11) * s), Dir = dir }
		b.Glow = 1
		local c = bellCenter(b)
		play("BellTollHuge", c, { Volume = .9 * s, Group = "Boss" })
		FX.Ring(c + V3(0, -12.6, 0), VIOLET_HOT, 18 * s, 1.1, { Normal = V3(0, 1, 0), Thickness = .2, Transparency = .3 })
		FX.Light(c + V3(0, -10, 0), VIOLET, 60, 4 * s, .9)
		Bus.Fire("LanternFlare", { Position = c, Radius = 200, Strength = -.8, Seconds = .35 })
		Bus.Fire("ChainKick", { Position = c, Radius = 60, Strength = 1.2 * s })
	end
	local function setPatternDisplay(pattern: { boolean }?, candles: { boolean }?)
		local b = S and S.Bell
		if not b then
			return
		end
		for i, slot in pairs(b.Slots) do
			local on = pattern and pattern[i] == true
			for _, p in ipairs(slot.Glyph) do
				p.Color = on and VIOLET_HOT or RGB(46, 24, 84)
			end
			for _, p in ipairs(slot.Rim) do
				p.Color = on and VIOLET or RGB(46, 24, 84)
			end
			local h = S.Halo[i]
			if h then
				h.Target = on
				h.Match = candles ~= nil and pattern ~= nil and candles[i] == pattern[i]
			end
		end
	end
	local function stepBell(dt: number)
		local b = S and S.Bell
		if not b then
			return
		end
		local t = os.clock()
		-- the descent: from DropHeight above to BellCF over Descend (server clock), a heavy settle at the end
		if b.DescendAt then
			local e = (now() - b.DescendAt) / T.Descend
			if e >= 1 then
				b.DescendAt = nil
				b.Drop = 0
			else
				local k = 1 - (1 - math.clamp(e, 0, 1)) ^ 3
				b.Drop = T.DropHeight * (1 - k) + math.sin(math.clamp(e, 0, 1) * PI * 3) * .6 * (1 - e)
			end
		end
		if b.Rise then
			-- after the victory the silenced bell is drawn back up into the dark
			local e = math.clamp((t - b.Rise) / 4, 0, 1)
			b.Drop = T.DropHeight * 1.4 * smooth(e)
		end
		-- the swing (damped) and the hang sway
		local ang = 0
		local dir = 0
		if b.Swing then
			local e = t - b.Swing.T0
			if e > 4 then
				b.Swing = nil
			else
				ang = b.Swing.Amp * math.exp(-e * .9) * math.sin(e * 2 * PI / 1.9)
				dir = b.Swing.Dir
			end
		end
		local sway = reduced() and 0 or math.sin(t * .7) * math.rad(.6)
		b.SwingCF = ANG(ang * math.cos(dir) + sway, 0, ang * math.sin(dir))
		b.Rig.Root.CFrame = bellRootCF(b)
		local bell = b.Rig.Motors.Bell
		if bell then
			bell.Transform = b.SwingCF
		end
		local clap = b.Rig.Motors.Clapper
		if clap then
			clap.Transform = ANG(-ang * .6 * math.cos(dir), 0, -ang * .6 * math.sin(dir))
		end
		layUpper(b)
		-- the glow (tolls, the spirit inside, the hound's beat)
		b.Glow = math.max(0, b.Glow - dt * 1.6)
		local beat = 0
		if S.Stage == "Hound" and S.Hound and S.Hound.BeatKick then
			beat = S.Hound.BeatKick * .5
		end
		local g = math.max(b.Glow, beat)
		for _, r in ipairs(b.Runes) do
			r.Color = (b.RuneBase[r] or VIOLET_DEEP):Lerp(VIOLET_HOT, g)
		end
		for _, r in ipairs(b.RimGlow) do
			r.Color = VIOLET_DEEP:Lerp(VIOLET_HOT, g)
		end
		local inside = b.SoulIn and 1 or 0
		if b.Soul then
			b.Soul.Transparency = 1 - (.22 * inside + .25 * g)
		end
		if b.Light then
			b.Light.Brightness = 1.2 * inside + 4 * g
		end
		if b.CrackLight then
			b.CrackLight.Brightness = .8 + 2 * g
		end
		-- the pattern halo: six numerals floating round the lip
		local c = bellCenter(b)
		for i, h in pairs(S.Halo) do
			local a = (i - 1) / 6 * 2 * PI + PI / 6
			local p = c + V3(math.sin(a) * 16, -13 + math.sin(t * 1.4 + i) * .4, -math.cos(a) * 16)
			h.Part.CFrame = CF(p)
			if h.Fill then
				local col = h.Target and CANDLE or RGB(34, 26, 46)
				h.Fill.BackgroundColor3 = col
				h.Stroke.Color = h.Match and SICKLY or (h.Target and GOLD_HOT or ASH)
			end
		end
	end
	local function buildHalo()
		if not S.Bell or next(S.Halo) then
			return
		end
		for i = 1, 6 do
			local p = FX.Part({ Name = "HaloAnchor" .. i, Size = V3(.4, .4, .4), Transparency = 1, Parent = S.Root, CFrame = CF(bellCenter(S.Bell)) })
			local g = billboard(p, UDim2.fromOffset(46, 46), nil, 320, false)
			local fill = newGui("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(34, 26, 46), BorderSizePixel = 0 }, g)
			corner(fill, "pill")
			local st = stroke(fill, ASH, 3, 0)
			label(fill, { Name = "Num", Text = ROMAN[i], Max = 22, Color = WHITE })
			S.Halo[i] = { Part = p, Gui = g, Fill = fill, Stroke = st, Target = false, Match = false }
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE CURSED CHAINS (anchor posts behind the ramp tops, links laid anchor -> hit point -> bell eye)
	---------------------------------------------------------------------------------------------------------------
	local function chainAnchor(key: string): Vector3
		local G = S.G
		return (G.Anchors and G.Anchors[key]) or (G.Pit + V3(0, 9, -34))
	end
	local function outwardOf(key: string): Vector3
		local d = flat(chainAnchor(key) - S.G.Pit)
		return d.Magnitude > .1 and d.Unit or V3(0, 0, -1)
	end
	local function buildAnchor(key: string): any
		if S.Anchors[key] then
			return S.Anchors[key]
		end
		local a = chainAnchor(key)
		local base = a + outwardOf(key) * 4.5
		local ground = S.Replay and a.Y or math.min(a.Y, Layout.FloorY + .05)
		local h = 8
		local m = Models.ChainAnchor(h)
		m.Name = "ChainAnchor_" .. key
		local cf = look(V3(base.X, ground, base.Z), V3(S.G.Pit.X, ground, S.G.Pit.Z))
		m:PivotTo(cf)
		local ring = (m.PrimaryPart :: BasePart):FindFirstChild("Ring") :: Attachment?
		local ringLocal = ring and ring.CFrame.Position or V3(0, h - 1, -2)
		local root = rigidify(m)
		m.Parent = S.Root
		local rec = { Model = m, Root = root, CF = cf, RingLocal = ringLocal, Born = os.clock(), Rise = 1 }
		S.Anchors[key] = rec
		return rec
	end
	local function anchorRing(rec: any): Vector3
		return (rec.CF * CF(0, -12 * (1 - backOut(rec.Rise)), 0) * CF(rec.RingLocal)).Position
	end
	-- the chain's polyline: ring -> the hittable link (the server's target, else a quarter of the way to the bell) -> eye
	local function chainPath(ch: any): { Vector3 }
		local b = S.Bell
		local ring = anchorRing(ch.Anchor)
		local eye = b and bellEye(b, ch.Key) or (S.G.BellCF.Position + V3(0, 10, 0))
		local hit = ch.HitPos
		if not hit then
			local tp = ch.TargetId and targetById(ch.TargetId)
			hit = tp and tp.Position or chainAnchor(ch.Key):Lerp(S.G.BellCF.Position, S.G.ChainAlong or .25)
		end
		local out = Models.ChainPath(ring, hit, .5, 3)
		local rest = Models.ChainPath(hit, eye, 1.4, 8)
		for i = 2, #rest do
			table.insert(out, rest[i])
		end
		return out
	end
	local function buildChain(key: string, grow: boolean): any
		local existing = S.Chains[key]
		if existing and not existing.Broken then
			return existing
		end
		if existing and existing.Model then
			existing.Model:Destroy()
		end
		local anchor = buildAnchor(key)
		local ch = { Key = key, Anchor = anchor, Hits = 0, Need = 0, Heat = 0 }
		local path = chainPath(ch)
		local len = 0
		for i = 1, #path - 1 do
			len += (path[i + 1] - path[i]).Magnitude
		end
		local m, h = Models.Chain(math.clamp(math.floor(len / 2.34), 6, 40), { Detail = S.Q })
		m.Name = "CursedChain_" .. key
		m.Parent = S.Root
		ch.Model, ch.H = m, h
		ch.Grow = grow and 0 or 1
		ch.GrowAt = os.clock()
		ch.Dirty = true
		ch.Base = {}
		for _, link in ipairs(h.Links) do
			for _, p in ipairs(link.Parts) do
				ch.Base[p] = p.Color
			end
		end
		S.Chains[key] = ch
		return ch
	end
	local function layChain(ch: any)
		if not (ch.H and ch.Model and ch.Model.Parent) then
			return
		end
		local parts, cfs = Models.LayChain(ch.H, chainPath(ch), smooth(ch.Grow or 1))
		moveParts(parts, cfs)
	end
	local function setActiveChain(key: string?, since: number?, pulse: number?, bright: number?)
		for k, ch in pairs(S.Chains) do
			ch.Active = k == key
			if k == key then
				ch.Since = since or now()
				ch.Pulse = pulse or tonumber(FA("Pulse")) or 1.2
				ch.Bright = bright or tonumber(FA("Bright")) or .55
				ch.LastPulse = nil
			end
		end
	end
	local function shatterChain(ch: any)
		if ch.Broken then
			return
		end
		ch.Broken = true
		ch.Active = false
		local m = ch.Model
		if not m then
			return
		end
		local center = Vector3.zero
		local n = 0
		local q = S.Q
		for i, link in ipairs(ch.H.Links) do
			for _, p in ipairs(link.Parts) do
				local pos = p.CFrame.Position
				center += pos
				n += 1
				if (i + #link.Parts) % (q < .6 and 2 or 1) == 0 then
					table.insert(S.Debris, { Part = p, V = V3(rand(-14, 14), rand(6, 22), rand(-14, 14)), R = V3(rand(-8, 8), rand(-8, 8), rand(-8, 8)),
						T = 0, Life = rand(1.1, 1.8) })
					p.Color = VIOLET_HOT
				else
					p.Transparency = 1
				end
			end
		end
		center = n > 0 and center / n or chainAnchor(ch.Key)
		FX.Burst(center, { Color = VIOLET_HOT, Color2 = VIOLET, Count = math.floor(50 * q), Speed = { 10, 26 }, Lifetime = { .4, .9 }, Size = { .6, 1, 0 } })
		FX.Light(center, VIOLET, 50, 5, .7)
		play("ChainBreak", center)
		task.delay(2.2, function()
			if m.Parent then
				m:Destroy()
			end
		end)
	end
	local function stepChains(dt: number)
		if not S then
			return
		end
		local t = os.clock()
		local st = now()
		local swinging = S.Bell and (S.Bell.Swing ~= nil or S.Bell.DescendAt ~= nil)
		for _, rec in pairs(S.Anchors) do
			if rec.Rise < 1 then
				rec.Rise = math.clamp((t - rec.Born) / T.AnchorRise, 0, 1)
				rec.Root.CFrame = rec.CF * CF(0, -12 * (1 - backOut(rec.Rise)), 0)
			end
		end
		for _, ch in pairs(S.Chains) do
			if not ch.Broken and ch.Model and ch.Model.Parent then
				if ch.Grow < 1 then
					ch.Grow = math.clamp((t - ch.GrowAt) / T.ChainGrow, 0, 1)
					ch.Dirty = true
					if ch.Grow >= 1 then
						local eye = S.Bell and bellEye(S.Bell, ch.Key) or nil
						if eye then
							FX.Burst(eye, { Color = VIOLET_HOT, Color2 = BONE, Count = math.floor(16 * S.Q), Speed = { 6, 12 }, Lifetime = { .3, .6 } })
							play("CoffinChain", eye, { Volume = .7 })
						end
					end
				end
				if swinging or ch.Dirty or ch.Anchor.Rise < 1 then
					ch.Dirty = false
					layChain(ch)
				end
				-- the pulse: the bright part of each period (server clock) when Perfect hits count; a wave runs up the chain
				local bright, wave = false, 0
				if ch.Active and ch.Pulse and ch.Pulse > 0 then
					local ph = ((st - (ch.Since or st)) % ch.Pulse) / ch.Pulse
					bright = ph < (ch.Bright or .55)
					wave = ph
					local idx = math.floor((st - (ch.Since or st)) / ch.Pulse)
					if bright and ch.LastPulse ~= idx then
						ch.LastPulse = idx
						play("ChainPulse", chainAnchor(ch.Key):Lerp(S.G.BellCF.Position, .3), { Volume = .8 })
					end
				end
				ch.Heat = math.max(0, (ch.Heat or 0) - dt * 2.5)
				local frac = (ch.Need and ch.Need > 0) and math.clamp(ch.Hits / ch.Need, 0, 1) or 0
				local n = #ch.H.Links
				for i, link in ipairs(ch.H.Links) do
					local glow = link.Glow
					if ch.Active then
						local pos = (i - .5) / n
						local wk = bright and (1 - math.clamp(math.abs(pos - wave / (ch.Bright or .55)) * 3, 0, 1)) or 0
						glow.Color = (bright and VIOLET_HOT or VIOLET_DEEP):Lerp(WHITE, math.max(wk, ch.Heat) * .7)
						glow.Transparency = bright and .02 or .45
						for _, p in ipairs(link.Parts) do
							if p ~= glow then
								p.Color = (ch.Base[p] or BONE):Lerp(bright and VIOLET or VIOLET_DEEP, (bright and .55 or .2) + frac * .3)
							end
						end
					elseif not ch.Idle then
						glow.Color = VIOLET_DEEP
						glow.Transparency = .35
						for _, p in ipairs(link.Parts) do
							if p ~= glow then
								p.Color = ch.Base[p] or p.Color
							end
						end
					end
				end
				ch.Idle = not ch.Active
			end
		end
		-- links flying off broken chains
		for i = #S.Debris, 1, -1 do
			local d = S.Debris[i]
			d.T += dt
			local p = d.Part
			if not p.Parent or d.T >= d.Life then
				table.remove(S.Debris, i)
				if p.Parent then
					p.Transparency = 1
				end
			else
				d.V += V3(0, -60 * dt, 0)
				local cf = p.CFrame
				p.CFrame = CF(cf.Position + d.V * dt) * (cf - cf.Position) * ANG(d.R.X * dt, d.R.Y * dt, d.R.Z * dt)
				p.Transparency = math.clamp((d.T - d.Life * .5) / (d.Life * .5), 0, 1)
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE CURSED CANDLES
	---------------------------------------------------------------------------------------------------------------
	local function buildCandle(i: number, pos: Vector3, lit: boolean, rise: boolean): any
		local c = S.Candles[i]
		if c then
			return c
		end
		local m = Models.Candle(i)
		local G = S.G
		local cf = look(pos, V3(G.Pit.X, pos.Y, G.Pit.Z))
		m:PivotTo(cf)
		Models.SetCandleLit(m, lit)
		local root = rigidify(m)
		m.Parent = S.Root
		local light = nil
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("PointLight") then
				light = d
			end
		end
		-- a ring on the ground that turns green when this candle matches the bell
		local ring = FX.Part({ Class = "Part", Shape = Enum.PartType.Cylinder, Name = "MatchRing", Size = V3(.12, 6.4, 6.4), Color = ASH,
			Transparency = .35, CFrame = CF(pos + V3(0, .08, 0)) * ANG(0, 0, PI / 2), Parent = S.Root })
		local tag = billboard(root :: BasePart, UDim2.fromOffset(40, 40), V3(0, 15, 0), 240, false)
		local fill = newGui("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(34, 26, 46), BorderSizePixel = 0 }, tag)
		corner(fill, "pill")
		local st = stroke(fill, ASH, 3, 0)
		label(fill, { Name = "Num", Text = ROMAN[i] or tostring(i), Max = 20, Color = WHITE })
		c = { Index = i, Model = m, Root = root, CF = cf, Pos = pos, Lit = lit, Light = light, Ring = ring, Tag = tag, TagFill = fill, TagStroke = st,
			Born = os.clock() + (rise and (i - 1) * T.CandleStagger or -10), Rise = rise and 0 or 1 }
		S.Candles[i] = c
		if not rise and root then
			root.CFrame = cf
		end
		return c
	end
	local function setCandleLit(c: any, lit: boolean, fx: boolean)
		if c.Lit == lit then
			return
		end
		c.Lit = lit
		Models.SetCandleLit(c.Model, lit)
		if fx then
			local tip = c.Pos + V3(0, 12, 0)
			if lit then
				FX.Burst(tip, { Color = CANDLE, Color2 = GOLD_HOT, Count = math.floor(18 * S.Q), Speed = { 3, 8 }, Lifetime = { .3, .7 }, Size = { .4, .7, 0 } })
				FX.Light(tip, CANDLE, 18, 3, .5)
				play("CandleLight", tip, { Pitch = .9 + c.Index * .05 })
			else
				FX.Smoke(tip, ASH, 2, 1.2)
				play("CandleSnuff", tip, { Pitch = .9 + c.Index * .05 })
			end
			play("ChoirNote", tip, { Volume = .5, Pitch = ({ 1, 1.122, 1.26, 1.335, 1.498, 1.682 })[c.Index] or 1 })
		end
	end
	local function stepCandles(_dt: number)
		if not S then
			return
		end
		local t = os.clock()
		local pattern = bitsOf(FA("Pattern"))
		local candles = bitsOf(FA("Candles"))
		local hasState = type(FA("Pattern")) == "string" and FA("Pattern") ~= ""
		for i, c in pairs(S.Candles) do
			if c.Sink then
				local e = math.clamp((t - c.Sink) / 1.2, 0, 1)
				c.Root.CFrame = c.CF * CF(0, -11 * smooth(e), 0)
				if e >= 1 and not c.Gone then
					c.Gone = true
					c.Model:Destroy()
					c.Ring:Destroy()
				end
			elseif c.Rise < 1 and c.Root then
				local e = math.clamp((t - c.Born) / T.CandleRise, 0, 1)
				if e > 0 and c.Rise == 0 then
					FX.Debris(c.Pos + V3(0, .6, 0), RGB(58, 44, 38), Enum.Material.Ground, 8, 20, { MaxSize = .9, Floor = c.Pos.Y + .1 })
					FX.Smoke(c.Pos + V3(0, 1, 0), RGB(90, 80, 100), 3, 1.2)
					play("GroundCrack", c.Pos, { Volume = .5 })
				end
				c.Rise = math.max(e, 1e-3)
				c.Root.CFrame = c.CF * CF(0, -11 * (1 - backOut(e)), 0)
			end
			if not c.Gone then
				local match = hasState and pattern[i] == c.Lit
				c.Ring.Color = hasState and (match and SICKLY or RGB(255, 96, 96)) or ASH
				c.TagFill.BackgroundColor3 = c.Lit and CANDLE or RGB(34, 26, 46)
				c.TagStroke.Color = hasState and (match and SICKLY or (pattern[i] and GOLD_HOT or ASH)) or ASH
				if c.Light and c.Lit then
					c.Light.Brightness = 1.4 + math.sin(t * 13 + i) * .25 + math.sin(t * 7.3 + i * 2) * .15
				end
				local _ = candles
			end
		end
	end
	local function sinkCandles()
		for _, c in pairs(S.Candles) do
			if not c.Sink then
				c.Sink = os.clock()
				if c.Tag then
					c.Tag:Destroy()
					c.Tag = nil
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- BURIED WEAK POINTS (gold mounds on the FinaleWeak targets)
	---------------------------------------------------------------------------------------------------------------
	local function buildWeak(id: any, pos: Vector3, untilAt: number?): any
		if S.Weak[id] then
			return S.Weak[id]
		end
		local m = Models.WeakMound(tonumber(id) or #S.Weak + 1)
		local cf = CF(pos)
		m:PivotTo(cf * CF(0, -4, 0))
		local glow, core = nil, nil
		for _, d in ipairs(m:GetDescendants()) do
			if d.Name == "WeakGlow" then
				glow = d
			elseif d.Name == "WeakCore" then
				core = d
			end
		end
		local root = rigidify(m)
		m.Parent = S.Root
		local hl = Instance.new("Highlight")
		hl.FillColor = GOLD
		hl.OutlineColor = WHITE
		hl.FillTransparency = .8
		hl.OutlineTransparency = .1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = m
		local light = nil
		if S.Q >= .5 and core then
			light = Instance.new("PointLight")
			light.Color = GOLD
			light.Range = 16
			light.Brightness = 2
			light.Shadows = false
			light.Parent = core
		end
		local tag = billboard(root :: BasePart, UDim2.fromOffset(110, 40), V3(0, 7, 0), 200, true)
		local tl = label(tag, { Name = "Left", Text = "", Max = 24, Color = GOLD_HOT })
		local w = { Id = id, Model = m, Root = root, CF = cf, Born = os.clock(), Glow = glow, Light = light, Tag = tag, TagText = tl, Until = untilAt }
		S.Weak[id] = w
		FX.Debris(pos + V3(0, 1, 0), RGB(58, 44, 38), Enum.Material.Ground, 12, 24, { MaxSize = 1.1, Floor = pos.Y + .1 })
		FX.Burst(pos + V3(0, 2, 0), { Color = GOLD_HOT, Color2 = GOLD, Count = math.floor(24 * S.Q), Speed = { 4, 10 }, Lifetime = { .5, 1 } })
		FX.Light(pos + V3(0, 2, 0), GOLD, 22, 4, .8)
		return w
	end
	local function removeWeak(w: any, broke: boolean)
		if w.Gone then
			return
		end
		w.Gone = true
		local pos = w.CF.Position
		if broke then
			FX.Burst(pos + V3(0, 3, 0), { Color = GOLD_HOT, Color2 = WHITE, Count = math.floor(50 * S.Q), Speed = { 10, 24 }, Lifetime = { .4, .9 },
				Size = { .6, 1.1, 0 } })
			FX.Shockwave(pos + V3(0, .3, 0), GOLD, 12, .7)
			FX.Debris(pos + V3(0, 2, 0), RGB(58, 44, 38), Enum.Material.Ground, 16, 30, { MaxSize = 1.2, Floor = pos.Y + .1 })
			play("WeakPointHit", pos)
			play("ArmorBreak", pos, { Pitch = .8 })
		else
			FX.Smoke(pos + V3(0, 1.5, 0), RGB(90, 76, 66), 4, 1.2)
		end
		w.Sink = os.clock()
		if w.Tag then
			w.Tag:Destroy()
			w.Tag = nil
		end
	end
	local function stepWeak(_dt: number)
		if not S then
			return
		end
		local t = os.clock()
		local live = targetsOf("FinaleWeak")
		local st = now()
		for id, w in pairs(S.Weak) do
			if w.Sink then
				local e = math.clamp((t - w.Sink) / .8, 0, 1)
				w.Root.CFrame = w.CF * CF(0, -4 * smooth(e), 0)
				if e >= 1 then
					w.Model:Destroy()
					S.Weak[id] = nil
				end
			else
				local rise = math.clamp((t - w.Born) / .7, 0, 1)
				w.Root.CFrame = w.CF * CF(0, -4 * (1 - backOut(rise)), 0)
				local pulse = .5 + .5 * math.sin(t * 7)
				if w.Glow then
					w.Glow.Transparency = .5 + pulse * .25
				end
				if w.Light then
					w.Light.Brightness = 1.6 + pulse * 1.4
				end
				local left = (w.Until or 0) - st
				if w.TagText then
					w.TagText.Text = left > 0 and (L("DIG! ", "КОПАЙ! ") .. math.ceil(left)) or L("DIG!", "КОПАЙ!")
					w.TagText.TextColor3 = (left > 0 and left < 4) and RGB(255, 120, 60) or GOLD_HOT
				end
				-- the target broke (EndReason Broke) or went away / the window closed
				if not S.Replay and rise >= 1 and not live[id] then
					local part = targetById(id)
					removeWeak(w, part ~= nil and part:GetAttribute("EndReason") == "Broke")
				elseif w.Until and st > w.Until + .5 then
					removeWeak(w, false)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- GHOST DOGS (on the FinaleGhost Strike targets)
	---------------------------------------------------------------------------------------------------------------
	local function ghostGround(part: BasePart): Vector3
		local g = part:GetAttribute("Ground")
		if typeof(g) == "Vector3" then
			return Vector3.new(part.Position.X, g.Y, part.Position.Z)
		end
		return Vector3.new(part.Position.X, Layout.Pit.FloorY, part.Position.Z)
	end
	local function newGhost(id: any, part: BasePart): any
		local seed = tonumber(part:GetAttribute("Seed")) or tonumber(part:GetAttribute("Key")) or 1
		local m = Models.GhostDog(seed, { Detail = S.Q })
		local rig = BossModels.Rig(m)
		m.Parent = S.Root
		local pos = ghostGround(part)
		local look3 = part.CFrame.LookVector
		local v = { Id = id, Part = part, Model = m, Rig = rig, Pos = pos, Yaw = math.atan2(-look3.X, -look3.Z), Spawn = os.clock(), Cur = {}, Speed = 0,
			Phase = math.random() * 10 }
		rig.Root.CFrame = CF(pos) * ANG(0, v.Yaw, 0) * CF(0, .5, 0)
		FX.Burst(pos + V3(0, 1, 0), { Texture = FX.Textures.Smoke, Color = GHOST, Color2 = RGB(60, 80, 140), Count = 8, Speed = { 2, 5 }, Lifetime = { .6, 1.1 },
			Size = { 1.5, 2.5, 3 }, Transparency = { .35, 1 }, LightEmission = .3 })
		return v
	end
	local function removeGhost(id: any, broke: boolean)
		local v = S.Ghosts[id]
		if not v then
			return
		end
		S.Ghosts[id] = nil
		local pos = v.Pos + V3(0, 2.4, 0)
		if broke then
			FX.Burst(pos, { Color = GHOST, Color2 = WHITE, Count = math.floor(30 * S.Q), Speed = { 6, 16 }, Lifetime = { .4, .9 }, Size = { .5, .9, 0 } })
			FX.Debris(pos, BONE, Enum.Material.SmoothPlastic, 6, 18, { MaxSize = .5, Floor = v.Pos.Y + .2 })
			play("GhostDogBark", pos, { Pitch = 1.35, Volume = .6 })
		else
			FX.Smoke(pos, GHOST, 2.5, 1)
		end
		v.Model:Destroy()
	end
	local function syncGhosts()
		if not S or S.Replay then
			return
		end
		local live = targetsOf("FinaleGhost")
		for id, part in pairs(live) do
			if not S.Ghosts[id] then
				local ok, v = pcall(newGhost, id, part)
				if ok and v then
					S.Ghosts[id] = v
				end
			else
				S.Ghosts[id].Part = part
			end
		end
		for id, v in pairs(S.Ghosts) do
			if not live[id] then
				local reason = v.Part and v.Part:GetAttribute("EndReason")
				removeGhost(id, reason == "Broke" or v.Down == true)
			end
		end
	end
	local function stepGhosts(dt: number)
		if not S then
			return
		end
		local t = os.clock()
		for _, v in pairs(S.Ghosts) do
			local part = v.Part
			if part and part.Parent then
				local goal = ghostGround(part)
				local before = v.Pos
				v.Pos = v.Pos:Lerp(goal, 1 - math.exp(-dt * 10))
				local lv = part.CFrame.LookVector
				local want = math.atan2(-lv.X, -lv.Z)
				local diff = (want - v.Yaw + PI) % (2 * PI) - PI
				v.Yaw += diff * (1 - math.exp(-dt * 8))
				local speed = (v.Pos - before).Magnitude / math.max(dt, 1e-3)
				v.Speed = v.Speed * .8 + speed * .2
			end
			local spawnK = math.clamp((t - v.Spawn) / .7, 0, 1)
			local mode, k = "Run", math.clamp(v.Speed / 7, .15, 1)
			if spawnK < 1 then
				mode, k = "Spawn", spawnK
			elseif v.BiteAt and t - v.BiteAt < .5 then
				mode, k = "Bite", (t - v.BiteAt) / .5
			end
			local P = Models.GhostPose(mode, t + v.Phase, k)
			local lunge = mode == "Bite" and math.sin(k * PI) or 0
			local bob = math.abs(math.sin((t + v.Phase) * 5.5)) * .3 * (mode == "Run" and k or 0)
			v.Rig.Root.CFrame = CF(v.Pos + V3(0, -3.2 * (1 - backOut(spawnK)) + .4 + bob, 0)) * ANG(0, v.Yaw, 0) * CF(0, .5, -lunge * 1.4)
			local kk = 1 - math.exp(-dt * 14)
			for name, m in pairs(v.Rig.Motors) do
				local cur = v.Cur[name] or CF()
				cur = cur:Lerp(P[name] or CF(), kk)
				v.Cur[name] = cur
				m.Transform = cur
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- THE LAST BARK + THE BLACK MOON
	---------------------------------------------------------------------------------------------------------------
	local function buildMoon(dir: Vector3): any
		if S.Moon then
			S.Moon.Dir = dir
			return S.Moon
		end
		local m = Models.BlackMoon(FinaleFX.MoonRadius)
		m.Parent = S.Root
		local cracks, shards, disc = {}, {}, {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "MoonCrack" then
					table.insert(cracks, d)
				elseif d.Name == "MoonShard" then
					table.insert(shards, d)
				elseif d.Name ~= "Root" then
					table.insert(disc, d)
				end
			end
		end
		local mo = { Model = m, Dir = dir.Unit, Born = os.clock(), Cracks = cracks, Shards = shards, Disc = disc, Stage = 0 }
		S.Moon = mo
		return mo
	end
	local function crackMoon(stage: number)
		local mo = S and S.Moon
		if not mo or mo.Broken then
			return
		end
		mo.Stage = stage
		for _, c in ipairs(mo.Cracks) do
			if (c:GetAttribute("Stage") or 9) <= stage then
				c.Transparency = 0
			end
		end
		play("GroundCrack", nil, { Group = "Cinema", Volume = .8, Pitch = .6 + stage * .1 })
		flash(DAWN, .12 * stage, .4)
	end
	local function breakMoon()
		local mo = S and S.Moon
		if not mo or mo.Broken then
			return
		end
		mo.Broken = os.clock()
		for _, d in ipairs(mo.Disc) do
			tween(d, 1.2, { Transparency = 1 })
		end
		for _, c in ipairs(mo.Cracks) do
			tween(c, .8, { Transparency = 1 })
		end
		for _, s in ipairs(mo.Shards) do
			s.Transparency = 0
		end
		mo.ShardFrom = {}
		for _, s in ipairs(mo.Shards) do
			mo.ShardFrom[s] = s.CFrame
		end
		play("RevealHit", nil, { Group = "Cinema", Volume = .8 })
		flash(DAWN, .45, 1.2)
	end
	local function stepMoon(_dt: number)
		local mo = S and S.Moon
		if not mo then
			return
		end
		local cp = camPos()
		local e = math.clamp((os.clock() - mo.Born) / 3, 0, 1)
		local dir = (mo.Dir - V3(0, .45 * (1 - smooth(e)), 0))
		dir = dir.Magnitude > .01 and dir.Unit or mo.Dir
		local pos = cp + dir * FinaleFX.MoonDistance
		local face = look(pos, cp) * ANG(0, 0, os.clock() * .03)
		if mo.Broken then
			-- shards fly out from where the moon stood, the rest is gone
			local be = os.clock() - mo.Broken
			for _, s in ipairs(mo.Shards) do
				local from = mo.ShardFrom and mo.ShardFrom[s]
				local d = s:GetAttribute("Dir")
				if from and typeof(d) == "Vector3" then
					local rel = mo.Face0 and mo.Face0:VectorToWorldSpace(d) or d
					s.CFrame = from + rel * be * 70 + V3(0, -be * be * 20, 0)
					s.Transparency = math.clamp(be / 2.2, 0, 1)
				end
			end
			if be > 2.5 then
				mo.Model:Destroy()
				S.Moon = nil
			end
			return
		end
		mo.Face0 = face
		mo.Model:PivotTo(face)
	end

	local function houndRootBase(h: any): CFrame
		return h.CF * Models.HoundRootOffset
	end
	local function buildHound(cf: CFrame, start: number, bpm: number): any
		if S.Hound then
			return S.Hound
		end
		local q = S.Q
		local m = Models.Hound({ Detail = q })
		local eyes, jawCore, jawHalo, mouth = {}, nil, nil, nil
		local parts = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "EyeCore" or d.Name == "EyeHalo" or d.Name == "EyeFlame" then
					table.insert(eyes, { Part = d, Base = d.Transparency })
				elseif d.Name == "JawCore" then
					jawCore = d
				elseif d.Name == "JawHalo" then
					jawHalo = d
				elseif d.Name == "MouthGlow" then
					mouth = d
				end
				if d.Transparency < .9 and d.Name ~= "Bone" then
					table.insert(parts, d)
				end
			end
		end
		local rig = BossModels.Rig(m)
		m.Parent = S.Root
		local light = nil
		if jawCore then
			light = Instance.new("PointLight")
			light.Color = VIOLET_HOT
			light.Range = 40
			light.Brightness = 0
			light.Shadows = false
			light.Parent = jawCore
		end
		local h = { Model = m, Rig = rig, CF = cf, Start = start, Bpm = bpm > 0 and bpm or 100, Cur = {}, Eyes = eyes, JawCore = jawCore, JawHalo = jawHalo,
			Mouth = mouth, Light = light, Parts = parts, Lunge = 0, LungeOff = Vector3.zero, BeatKick = 0, LastBeat = -1 }
		rig.Root.CFrame = houndRootBase(h) * CF(0, -T.RiseDepth, 0)
		S.Hound = h
		return h
	end
	local function houndBeat(h: any): number
		if Music and Music.Theme and Music.Theme() == "FINALE_HOUND" and Music.Beat then
			local ok, _, _, beat = pcall(Music.Beat, "FINALE_HOUND")
			if ok and type(beat) == "number" and beat > 0 then
				return beat
			end
		end
		return (now() - h.Start) * h.Bpm / 60
	end
	local function startBark(h: any, at: number, untilAt: number, jaw: Vector3?)
		h.Bark = { At = at, Until = untilAt, Jaw = jaw or (S.G and S.G.JawPos) }
		-- where the full lunge pose puts the jaw; the rest of the way is a move of the whole (spectral) body
		local P = Models.HoundPose("Bark", 0, 1, 0)
		local jp = Models.JawPoint(h.Model, P, houndRootBase(h))
		local target = h.Bark.Jaw
		local off = (jp and target) and (target - jp) or Vector3.zero
		if off.Magnitude > T.LungeMax then
			off = off.Unit * T.LungeMax
		end
		h.LungeOff = off
	end
	local function counterGui(h: any)
		if h.CounterTag or not h.JawCore then
			return
		end
		local g = billboard(h.JawCore, UDim2.fromOffset(170, 74), V3(0, 6, 0), 300, true)
		local t = label(g, { Name = "Text", Text = L("COUNTER!", "КОНТРУДАР!"), Max = 30, Color = GOLD_HOT, Size = UDim2.fromScale(1, .6) })
		local n = label(g, { Name = "Left", Text = "", Max = 22, Color = WHITE, Position = UDim2.fromScale(0, .58), Size = UDim2.fromScale(1, .42) })
		h.CounterTag, h.CounterText, h.CounterLeft = g, t, n
	end
	local function shatterHound(h: any)
		if h.Shattered then
			return
		end
		h.Shattered = os.clock()
		-- the hound comes apart into a cloud of moths
		local q = S.Q
		local count = math.floor(70 * q)
		local pool = h.Parts
		for i = 1, count do
			local p = pool[math.random(1, math.max(1, #pool))]
			if p and p.Parent then
				local pos = p.CFrame.Position + V3(rand(-1.5, 1.5), rand(-1.5, 1.5), rand(-1.5, 1.5))
				local body = FX.Part({ Name = "Moth", Size = V3(.3, .3, .9), Color = i % 4 == 0 and VIOLET_HOT or (i % 3 == 0 and MOON or RGB(40, 30, 60)),
					CFrame = CF(pos), Parent = S.Root, Material = Enum.Material.Neon })
				local wl = FX.Part({ Name = "MothWing", Class = "WedgePart", Size = V3(.1, .9, 1.1), Color = RGB(30, 22, 44), CFrame = CF(pos), Parent = S.Root,
					Material = Enum.Material.SmoothPlastic })
				local wr = FX.Part({ Name = "MothWing", Class = "WedgePart", Size = V3(.1, .9, 1.1), Color = RGB(30, 22, 44), CFrame = CF(pos), Parent = S.Root,
					Material = Enum.Material.SmoothPlastic })
				local out = (pos - (h.CF.Position + V3(0, 26, 0)))
				out = out.Magnitude > .1 and out.Unit or V3(0, 1, 0)
				table.insert(S.Moths, { Body = body, L = wl, R = wr, Pos = pos, V = out * rand(6, 16) + V3(0, rand(6, 14), 0), T = 0, Life = rand(2.4, 4),
					Flap = rand(0, 6), Spin = rand(-2, 2) })
			end
		end
		for _, p in ipairs(h.Parts) do
			if p.Parent then
				tween(p, .9, { Transparency = 1 })
			end
		end
		FX.Burst(h.CF.Position + V3(0, 28, 0), { Color = VIOLET_HOT, Color2 = MOON, Count = math.floor(80 * q), Speed = { 10, 30 }, Lifetime = { .8, 1.6 },
			Size = { .8, 1.4, 0 } })
		play("Moths", h.CF.Position + V3(0, 26, 0), { Volume = 1 })
		play("SoulBurst", h.CF.Position + V3(0, 26, 0))
		task.delay(1.2, function()
			if h.Model.Parent then
				h.Model:Destroy()
			end
		end)
	end
	local function stepMoths(dt: number)
		if not S then
			return
		end
		for i = #S.Moths, 1, -1 do
			local m = S.Moths[i]
			m.T += dt
			if m.T >= m.Life or not m.Body.Parent then
				table.remove(S.Moths, i)
				m.Body:Destroy()
				m.L:Destroy()
				m.R:Destroy()
			else
				m.V = m.V * (1 - dt * .4) + V3(math.sin(m.T * 3 + m.Flap) * 6, 1.5, math.cos(m.T * 2.6 + m.Flap) * 6) * dt
				m.Pos += m.V * dt
				local dir = m.V.Magnitude > .1 and m.V.Unit or V3(0, 1, 0)
				local base = look(m.Pos, m.Pos + dir)
				local flap = math.sin(m.T * 26 + m.Flap) * .9
				m.Body.CFrame = base
				m.L.CFrame = base * CF(-.35, 0, 0) * ANG(0, 0, flap) * CF(-.3, 0, 0) * ANG(0, PI / 2, 0)
				m.R.CFrame = base * CF(.35, 0, 0) * ANG(0, 0, -flap) * CF(.3, 0, 0) * ANG(0, -PI / 2, 0)
				local fade = math.clamp((m.T - m.Life * .6) / (m.Life * .4), 0, 1)
				m.Body.Transparency = fade
				m.L.Transparency = fade
				m.R.Transparency = fade
			end
		end
	end
	local function stepHound(dt: number)
		local h = S and S.Hound
		if not h or h.Shattered then
			return
		end
		local t = os.clock()
		local st = now()
		local beat = houndBeat(h)
		local bi = math.floor(beat)
		if bi ~= h.LastBeat and beat >= 0 then
			h.LastBeat = bi
			h.BeatKick = 1
		end
		h.BeatKick = math.max(0, h.BeatKick - dt * 4)
		-- which pose: rising, a pattern, the bark lunge, the victory howl, or looming
		local riseK = math.clamp(1 - (h.Start - st) / T.HoundRise, 0, 1)
		if h.Late then
			riseK = 1
		end
		local name, k = "Loom", 1
		local bark = h.Bark
		local lungeTarget = 0
		if h.Howl then
			name, k = "Howl", smooth((t - h.Howl) / .6)
		elseif riseK < 1 then
			name, k = "Rise", riseK
		elseif bark and st >= bark.At and st <= bark.Until + T.BarkOut then
			local inK = smooth((st - bark.At) / T.BarkIn)
			local outK = 1 - smooth((st - bark.Until) / T.BarkOut)
			name, k = "Bark", math.min(inK, outK)
			lungeTarget = k
		elseif h.Pattern and st >= h.Pattern.BeatAt - .3 and st < (h.Pattern.Until or math.huge) then
			name, k = h.Pattern.Name, smooth((st - h.Pattern.BeatAt + .3) / .5)
		end
		if bark and st > bark.Until + T.BarkOut then
			h.Bark = nil
			if h.CounterTag then
				h.CounterTag:Destroy()
				h.CounterTag = nil
			end
		end
		h.Lunge = lungeTarget
		local P = Models.HoundPose(name, t, k * (reduced() and .7 or 1), beat)
		local depth = -T.RiseDepth * (1 - backOut(riseK))
		local bounce = (reduced() or name == "Bark") and 0 or h.BeatKick * .35
		h.Rig.Root.CFrame = houndRootBase(h) * CF(0, depth - bounce, 0) + h.LungeOff * h.Lunge
		local kk = 1 - math.exp(-dt * (name == "Bark" and 16 or 9))
		for bone, m in pairs(h.Rig.Motors) do
			local cur = h.Cur[bone] or CF()
			cur = cur:Lerp(P[bone] or CF(), kk)
			h.Cur[bone] = cur
			m.Transform = cur
		end
		-- burning eyes flare on the beat; the jaw core shows while the counter window is open
		local flare = h.BeatKick
		for _, e in ipairs(h.Eyes) do
			e.Part.Transparency = math.clamp(e.Base - flare * .25, 0, 1)
		end
		local counter = bark and st >= bark.At and st <= bark.Until
		if h.JawCore then
			local pulse = .5 + .5 * math.sin(t * 12)
			h.JawCore.Transparency = counter and 0 or 1
			if h.JawHalo then
				h.JawHalo.Transparency = counter and (.35 + pulse * .3) or 1
			end
			if h.Light then
				h.Light.Brightness = counter and (3 + pulse * 2) or (.6 + flare)
				h.Light.Color = counter and GOLD_HOT or VIOLET_HOT
			end
		end
		if h.Mouth then
			h.Mouth.Transparency = counter and 0 or .2
		end
		if counter then
			counterGui(h)
			if h.CounterLeft then
				h.CounterLeft.Text = string.format("%.1f", math.max(0, bark.Until - st))
			end
			-- an expanding gold ring around the jaw every half second
			if not h.RingAt or t - h.RingAt > .5 then
				h.RingAt = t
				local jp = bark.Jaw or (h.JawCore and h.JawCore.Position)
				if jp then
					FX.Ring(jp, GOLD, 7, .5, { Normal = (camPos() - jp).Magnitude > .1 and (camPos() - jp).Unit or V3(0, 1, 0), Thickness = .25, Transparency = .2 })
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- stage entries (late = joined mid-stage: build the state, play no set pieces)
	---------------------------------------------------------------------------------------------------------------
	local function enterFakeDeath(at: number, late: boolean)
		S.Stage = "FakeDeath"
		S.StageClock = os.clock()
		S.Entered.FakeDeath = true
		local F = T.FakeDeath
		if late and now() - at > 1.5 then
			setMood("FINALE_FAKE", 1)
			return
		end
		duck("HardStop", { Music = 0, WorldEvents = 0, Ambience = .35 }, .08)
		setMood("FINALE_FAKE", .4)
		local corpse = corpseCore()
		-- the shot: a slow push on the fallen Gravekeeper from the north side, rising a little at the toll
		if not S.Replay then
			local north = flat(Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus)
			north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
			local eye0 = corpse + north * 34 + V3(0, 14, 0)
			local eye1 = corpse + north * 24 + V3(0, 9, 0)
			shot({ Id = "FinaleFakeDeath", Duration = math.max(1, at + F.Seconds + .6 - now()), Retry = 1.2, SkipAfter = 1.5,
				Shot = function(e)
					local k = smooth(e / (F.Seconds + .6))
					return look(eye0:Lerp(eye1, k), corpse + V3(0, -2 + k * 6, 0))
				end, Focus = { Target = corpse, Radius = 14, Far = .4 } })
		end
		cue(at + F.Flash, function()
			S.Card = S.Card or buildCard()
			flash(GOLD_HOT, .55, .6)
			play("TreasureReveal", nil, { Group = "Cinema", Volume = .8 })
		end, "FakeFlash")
		cue(at + F.Silence, function()
			duck("Silence", "Silence", .5)
		end, "Silence")
		cue(at + F.Toll, function()
			release("Silence", .3)
			play("SubSwell", nil, { Group = "Cinema" })
			play("GroundCrack", corpse, { Group = "Cinema", Volume = 1, Pitch = .7 })
			play("BellTollHuge", nil, { Group = "Cinema", Volume = 1, Pitch = .92 })
			shake(.7, 1.8)
			impulse(1.4)
			flash(VIOLET, .25, .5)
			FX.Cracks(Vector3.new(corpse.X, (S.G and S.G.FloorY or Layout.Pit.FloorY) + .1, corpse.Z), V3(0, 1, 0), VIOLET, 18, 3.5)
			Bus.Fire("LanternFlare", { Position = corpse, Radius = 220, Strength = -.95, Seconds = .6 })
		end, "Toll")
		cue(at + F.Crack, function()
			if S.Card then
				crackCard(S.Card)
				play("CoffinChainSnap", nil, { Group = "Cinema", Volume = .8 })
			end
		end, "Crack")
		cue(at + F.Crack + .5, function()
			if S.Card then
				ashCard(S.Card)
			end
			title("...not yet", "...ещё нет", { Size = "Large", Color = VIOLET_HOT, Duration = 1.6, Position = "Center" })
		end, "Ash")
		cue(at + F.Crack + 2.2, function()
			destroyCard()
		end, "CardGone")
		cue(at + F.Spirit, function()
			local from = corpseCore()
			spawnSpirit(from)
			spiritBurst(from, true)
			play("SoulBurst", from)
			play("BossRoar", from, { Pitch = 1.4, Volume = .7 })
			shake(.5, .8)
			release("HardStop", 1.5)
		end, "Spirit")
	end

	local function enterBell(d: any, late: boolean)
		S.Stage = "Bell"
		S.StageClock = os.clock()
		S.Entered.Bell = true
		destroyCard()
		release("Silence", .3)
		release("HardStop", 1.5)
		local G = S.G
		local bcf = cfOf(d.BellCF) or G.BellCF
		G.BellCF = bcf
		if type(d.Chains) == "table" then
			for k, v in pairs(d.Chains) do
				local p = vecOf(v)
				if p then
					G.Anchors[k] = p
				end
			end
		end
		local start = tonumber(d.StartAt) or tonumber(FA("StageStart")) or now()
		local descend = tonumber(d.Descend) or T.Descend
		setMood("FINALE_BELL", late and 1 or 3)
		if not S.Bell then
			S.Bell = buildBell(bcf)
		end
		local b = S.Bell
		b.CF = bcf
		local arrive = start + descend
		if late or now() >= arrive then
			b.Drop = 0
			b.DescendAt = nil
			b.SoulIn = true
			for _, key in ipairs(Models.Keys) do
				buildChain(key, false)
			end
			-- broken chains (late join): the ones before the active one in the server's order
			local left = tonumber(FA("ChainsLeft")) or 4
			local active = tostring(FA("Chain") or "")
			local order = type(d.Order) == "table" and d.Order or Models.Keys
			local brokenCount = 4 - left
			if brokenCount > 0 then
				local idx = table.find(order, active)
				for i = 1, brokenCount do
					local key = idx and order[((idx - 1 - i) % 4) + 1] or order[i]
					local ch = S.Chains[key]
					if ch then
						ch.Broken = true
						if ch.Model then
							ch.Model:Destroy()
						end
					end
				end
			end
			if active ~= "" then
				setActiveChain(active, tonumber(FA("ChainSince")), tonumber(FA("Pulse")), tonumber(FA("Bright")))
			end
			if S.Spirit then
				spiritVisible(S.Spirit, false)
				S.Spirit.Mode = "Hidden"
			end
			return
		end
		-- the descent + the spirit flying into the bell + the chains shooting out to the anchors
		b.DescendAt = start
		b.Drop = T.DropHeight
		play("BellCreak", bcf.Position + V3(0, 30, 0), { Volume = 1 })
		play("Thunder", nil, { Volume = .5 })
		title("THE BELL TOLLS", "КОЛОКОЛ ЗВОНИТ", { Sub = { "Break its four chains: PERFECT hits while they shine", "Разбей четыре цепи: ИДЕАЛЬНЫЕ удары, пока они сияют" },
			Size = "Large", Duration = 3.4, Position = "Upper", Color = VIOLET_HOT })
		if not S.Spirit then
			spawnSpirit(corpseCore() + V3(0, 6, 0))
			S.Spirit.Mode = "Hover"
		end
		cue(arrive - .7, function()
			if S.Spirit and S.Bell then
				spiritFly(bellCenter(S.Bell) + V3(0, -4, 0), .65, "Hidden", function()
					if S and S.Bell then
						S.Bell.SoulIn = true
						spiritBurst(bellCenter(S.Bell) + V3(0, -10, 0), true)
					end
				end)
			end
		end, "SpiritIn")
		cue(arrive, function()
			if S.Bell then
				bellToll(S.Bell, 1.1)
				shake(.8, 1)
				impulse(1.2)
				FX.Shockwave(Vector3.new(bcf.Position.X, G.FloorY + .2, bcf.Position.Z), VIOLET, 30, 1)
			end
		end, "Arrive")
		for i, key in ipairs(Models.Keys) do
			cue(start + 1.2 + i * .12, function()
				buildAnchor(key)
				local a = chainAnchor(key)
				FX.Debris(a, RGB(70, 68, 84), Enum.Material.Slate, 8, 20, { MaxSize = 1, Floor = a.Y - 1 })
				play("GroundCrack", a, { Volume = .6 })
			end, "Anchor" .. key)
			cue(arrive - .15 + i * .14, function()
				buildChain(key, true)
			end, "Chain" .. key)
		end
		-- a shot of the descent (cancelled by the first hazard telegraph)
		local look0 = bcf.Position + V3(0, T.DropHeight * .6, 0)
		local north = flat(Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus)
		north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
		local eye = G.Pit + north * 30 + V3(0, 6, 0)
		shot({ Id = "FinaleBell", Duration = math.max(1, arrive + 1.1 - now()), InCombat = true, Retry = .6,
			Shot = function(e)
				local k = smooth(e / (descend + .8))
				return look(eye + V3(0, k * 3, 0), look0:Lerp(bcf.Position, k))
			end, Focus = { Target = bcf.Position, Radius = 20, Far = .3 } })
	end

	local function enterChoir(d: any, late: boolean)
		S.Stage = "Choir"
		S.StageClock = os.clock()
		S.Entered.Choir = true
		local G = S.G
		setMood("FINALE_CHOIR", late and 1 or 3.5)
		-- the chains are gone by now
		for _, ch in pairs(S.Chains) do
			if not ch.Broken then
				shatterChain(ch)
			end
		end
		for _, rec in pairs(S.Anchors) do
			rec.Sink = os.clock()
		end
		if not S.Bell then
			S.Bell = buildBell(G.BellCF)
			S.Bell.SoulIn = true
		end
		buildHalo()
		-- candles: the payload, else the live targets, else the defaults
		local list = {}
		if type(d.Candles) == "table" then
			for i, row in pairs(d.Candles) do
				local idx = tonumber(i) or i
				if type(row) == "table" then
					local p = vecOf(row.Position)
					if p and type(idx) == "number" then
						list[idx] = { Pos = p, Lit = row.Lit == true }
					end
				end
			end
		end
		if next(list) == nil then
			local lit = bitsOf(FA("Candles"))
			for _, part in pairs(targetsOf("FinaleCandle")) do
				local idx = tonumber(part:GetAttribute("Index"))
				if idx then
					local g = part:GetAttribute("Ground")
					list[idx] = { Pos = typeof(g) == "Vector3" and g or part.Position - V3(0, 2.5, 0), Lit = part:GetAttribute("Lit") == true or lit[idx] }
				end
			end
		end
		if next(list) == nil then
			local lit = bitsOf(FA("Candles"))
			for i, p in ipairs(G.Candles or {}) do
				list[i] = { Pos = p, Lit = lit[i] }
			end
		end
		for i, row in pairs(list) do
			buildCandle(i, row.Pos, row.Lit, not late)
		end
		setPatternDisplay(bitsOf(d.Pattern or FA("Pattern")), bitsOf(FA("Candles")))
		if not late then
			title("THE BURIED CHOIR", "ПОГРЕБЁННЫЙ ХОР", { Sub = { "Light the candles to match the bell", "Зажги свечи как на колоколе" }, Size = "Large",
				Duration = 3.4, Position = "Upper", Color = MOON })
			play("ChoirNote", G.Pit + V3(0, 12, 0), { Volume = .8, Pitch = 1 })
			play("ChoirNote", G.Pit + V3(0, 12, 0), { Volume = .6, Pitch = 1.26, Delay = .25 })
			play("ChoirNote", G.Pit + V3(0, 12, 0), { Volume = .6, Pitch = 1.498, Delay = .5 })
			if S.Bell then
				bellToll(S.Bell, .7)
			end
		end
	end

	local function enterHound(d: any, late: boolean)
		S.Stage = "Hound"
		S.StageClock = os.clock()
		S.Entered.Hound = true
		local G = S.G
		local hcf = cfOf(d.HoundCF) or cfOf(FA("HoundCF")) or G.HoundCF
		G.HoundCF = hcf
		local jaw = vecOf(d.JawPos) or vecOf(FA("JawPos"))
		if jaw then
			G.JawPos = jaw
		end
		local md = vecOf(d.MoonDir)
		if md and md.Magnitude > .01 then
			G.MoonDir = md.Unit
		end
		local start = tonumber(d.StartAt) or tonumber(FA("StartAt")) or now()
		local bpm = tonumber(d.Bpm) or tonumber(FA("Bpm")) or 100
		setMood("FINALE_HOUND", late and 1 or 3)
		sinkCandles()
		for id in pairs(S.Ghosts) do
			removeGhost(id, false)
		end
		for _, w in pairs(S.Weak) do
			removeWeak(w, false)
		end
		for i, h in pairs(S.Halo) do
			h.Gui:Destroy()
			h.Part:Destroy()
			S.Halo[i] = nil
		end
		local h = buildHound(hcf, start, bpm)
		h.HP = tonumber(d.HP) or tonumber(FA("HoundHP"))
		h.Max = tonumber(d.Max) or tonumber(FA("HoundMax"))
		h.Late = late or now() >= start
		buildMoon(G.MoonDir)
		if late then
			if S.Moon then
				S.Moon.Born = os.clock() - 10
			end
			local cu = tonumber(FA("CounterUntil")) or 0
			if cu > now() then
				startBark(h, now(), cu, G.JawPos)
			end
			return
		end
		-- the spirit leaves the bell for the hound; the hound rises with the moon
		if S.Bell then
			S.Bell.SoulIn = false
			local from = bellCenter(S.Bell) + V3(0, -6, 0)
			if not S.Spirit then
				spawnSpirit(from)
			end
			S.Spirit.Pos = from
			spiritVisible(S.Spirit, true)
			spiritFly(hcf.Position + V3(0, 26, 0), 1.4, "Hidden", function()
				if S and S.Hound then
					spiritBurst(S.Hound.CF.Position + V3(0, 26, 0), true)
				end
			end)
		end
		FX.Cracks(hcf.Position + V3(0, .2, -4), V3(0, 1, 0), VIOLET, 22, 4)
		FX.Burst(hcf.Position + V3(0, 2, 0), { Texture = FX.Textures.Smoke, Color = RGB(40, 24, 66), Color2 = RGB(10, 6, 20), Count = math.floor(30 * S.Q),
			Speed = { 6, 16 }, Lifetime = { 1.2, 2.4 }, Size = { 6, 10, 14 }, Transparency = { .3, 1 }, LightEmission = .1, Spread = 70, Direction = V3(0, 1, 0) })
		play("BossEmerge", hcf.Position, { Pitch = .7, Volume = 1 })
		play("SubSwell", nil, { Group = "Cinema", Volume = .8 })
		shake(.6, T.HoundRise)
		cue(start - .2, function()
			if S.Hound then
				play("HoundHowl", S.Hound.CF.Position + V3(0, 40, 0), { Volume = 1 })
				impulse(1)
			end
		end, "RiseHowl")
		title("THE LAST BARK", "ПОСЛЕДНИЙ ЛАЙ", { Sub = { "Dodge to the beat - strike its jaw when it barks", "Уклоняйся в ритм - бей в пасть, когда она лает" },
			Size = "Huge", Duration = 3.2, Position = "Upper", Color = VIOLET_HOT })
		-- a look at the rise (until the first telegraph)
		local north = flat(Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus)
		north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
		local eye = G.Pit + north * 22 + V3(0, 4, 0)
		local headAt = hcf.Position + V3(0, 34, 0)
		shot({ Id = "FinaleHound", Duration = math.max(1, start + .6 - now()), InCombat = true, Retry = .6, Fov = 62,
			Shot = function(e)
				local k = smooth(e / T.HoundRise)
				return look(eye, headAt + V3(0, -16 * (1 - k), 0))
			end })
	end

	local function enterVictory(d: any, late: boolean)
		S.Stage = "Victory"
		S.StageClock = os.clock()
		S.Entered.Victory = true
		stopShot("Victory")
		local at = tonumber(d.At) or tonumber(FA("StageStart")) or now()
		local V = T.Victory
		S.EndAt = at + V.Shot + 1
		if late and now() - at > 2 then
			setMood("FINALE_DAWN", 2)
			S.EndAt = now() + 2
			return
		end
		duck("Victory", { Music = 0, WorldEvents = 0, Ambience = .4 }, .6)
		local G = S.G
		local h = S.Hound
		local houndHead = h and (h.CF.Position + V3(0, 40, 0)) or (G.Pit + V3(0, 20, 30))
		if h then
			h.Howl = os.clock()
			h.Bark = nil
			h.LungeOff = Vector3.zero
		end
		play("HoundHowl", houndHead, { Volume = 1.1 })
		shake(.5, 1.6)
		for _, ch in pairs(S.Chains) do
			if not ch.Broken then
				shatterChain(ch)
			end
		end
		sinkCandles()
		-- the top fighters
		local names = {}
		for i, row in ipairs(type(d.Top) == "table" and d.Top or {}) do
			if i <= 3 and type(row) == "table" then
				table.insert(names, tostring(row.Name or "?"))
			end
		end
		local subEn = #names > 0 and ("Top: " .. table.concat(names, ", ")) or "The Gravekeeper sleeps at last"
		local subRu = #names > 0 and ("Лучшие: " .. table.concat(names, ", ")) or "Смотритель наконец уснул"
		cue(at + V.Shatter, function()
			if S.Hound then
				shatterHound(S.Hound)
			end
			flash(MOON, .35, .8)
		end, "Shatter")
		for i, ct in ipairs(V.Crack) do
			cue(at + ct, function()
				crackMoon(i)
			end, "MoonCrack" .. i)
		end
		cue(at + V.Break, function()
			breakMoon()
		end, "MoonBreak")
		cue(at + V.Dawn, function()
			setMood("FINALE_DAWN", 2.5)
			local lm = ctx.Modules and ctx.Modules.Lighting
			if lm and lm.Flash and not reduced() then
				pcall(lm.Flash, .7, .9)
			end
			play("SealComplete", nil, { Group = "Cinema", Volume = .9 })
			play("TrialWin", nil, { Group = "Cinema", Volume = .7, Delay = .4 })
			title("THE LAST BARK FADES", "ПОСЛЕДНИЙ ЛАЙ УМОЛК", { Sub = { subEn, subRu }, Size = "Huge", Duration = 4, Color = DAWN, SubColor = GOLD_HOT })
			release("Victory", 4)
		end, "Dawn")
		cue(at + V.Bell, function()
			if S.Bell then
				S.Bell.Rise = os.clock()
				S.Bell.SoulIn = false
			end
		end, "BellRise")
		-- the victory shot: up the pit toward the hound and the cracking moon
		local north = flat(Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus)
		north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
		local eye0 = G.Pit + north * 28 + V3(0, 6, 0)
		local eye1 = G.Pit + north * 40 + V3(0, 22, 0)
		local target = houndHead
		shot({ Id = "FinaleVictory", Duration = V.Shot, Retry = 1, SkipAfter = 1.5, Fov = 64,
			Shot = function(e)
				local k = smooth(e / V.Shot)
				local up = (S and S.Moon and not S.Moon.Broken) and (camPos() + (S.Moon.Dir * 60)) or target + V3(0, 30, 0)
				return look(eye0:Lerp(eye1, k), target:Lerp(up, smooth((e - 2.5) / 3) * .5))
			end })
	end

	local function enterFail(d: any, late: boolean)
		S.Stage = "Fail"
		S.StageClock = os.clock()
		S.Entered.Fail = true
		stopShot("Fail")
		local at = tonumber(d.At) or tonumber(FA("StageStart")) or now()
		S.EndAt = at + T.FailShot + 1.5
		setMood("FINALE_FAIL", late and 1 or 1.6)
		if late and now() - at > 2 then
			return
		end
		duck("Fail", { Music = 0, WorldEvents = 0, Ambience = .3 }, .4)
		local G = S.G
		local bellPos = S.Bell and bellCenter(S.Bell) or G.BellCF.Position
		if S.Bell then
			bellToll(S.Bell, 1.3)
		else
			play("BellTollHuge", bellPos, { Pitch = .8 })
		end
		play("BellTollHuge", nil, { Group = "Cinema", Pitch = .7, Volume = 1 })
		play("TrialFail", nil, { Volume = .8, Delay = 1.2 })
		shake(.6, 1.4)
		for _, c in pairs(S.Candles) do
			if c.Lit and not c.Gone then
				setCandleLit(c, false, true)
			end
		end
		for _, ch in pairs(S.Chains) do
			ch.Active = false
		end
		if S.Hound then
			S.Hound.Bark = nil
			S.Hound.LungeOff = Vector3.zero
			S.Hound.Sink = os.clock()
		end
		local reason = tostring(d.Reason or FA("Reason") or "")
		local subEn, subRu = "Its toll is the last thing you hear.", "Его звон - последнее, что вы слышите."
		if reason == "Wipe" then
			subEn, subRu = "The whole pit fell.", "Пала вся яма."
		elseif reason == "Time" then
			subEn, subRu = "The night ran out.", "Ночь закончилась."
		elseif reason == "Empty" then
			subEn, subRu = "Nobody stayed in the pit.", "В яме никого не осталось."
		end
		title("THE BELL SILENCES YOU", "КОЛОКОЛ ЗАСТАВИЛ ВАС УМОЛКНУТЬ", { Sub = { subEn, subRu }, Size = "Large", Duration = 3.8, Color = RGB(196, 170, 255),
			SubColor = BONE })
		local c = cinema()
		if c and c.Fade and not reduced() then
			pcall(c.Fade, .55, 1.4, { Color = RGB(8, 4, 14), MaxHold = 4 })
			cue(at + 3.2, function()
				pcall(c.Fade, 0, 1.2)
			end, "FailFadeOut")
		end
		-- a slow look up at the bell
		local north = flat(Layout.Boss.Camera.Eye - Layout.Boss.Camera.Focus)
		north = north.Magnitude > .1 and north.Unit or V3(0, 0, -1)
		local eye = G.Pit + north * 18 + V3(0, 3, 0)
		shot({ Id = "FinaleFail", Duration = T.FailShot, Retry = .8, SkipAfter = 1,
			Shot = function(e)
				local k = smooth(e / T.FailShot)
				return look(eye + V3(0, k * 2, 0), bellPos:Lerp(bellPos + V3(0, -8, 0), 1 - k))
			end })
	end

	local function enterStage(stage: string, d: any, late: boolean)
		if not STAGES[stage] then
			return
		end
		ensureSession()
		if S.Entered[stage] then
			return
		end
		d = type(d) == "table" and d or {}
		S.Pending = nil
		if stage == "FakeDeath" then
			enterFakeDeath(tonumber(d.At) or tonumber(FA("StageStart")) or now(), late)
		elseif stage == "Bell" then
			enterBell(d, late)
		elseif stage == "Choir" then
			enterChoir(d, late)
		elseif stage == "Hound" then
			enterHound(d, late)
		elseif stage == "Victory" then
			enterVictory(d, late)
		elseif stage == "Fail" then
			enterFail(d, late)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- teardown (everything the session built), late-join sync
	---------------------------------------------------------------------------------------------------------------
	teardown = function(_reason: string?, instant: boolean?)
		local s = S
		if not s then
			return
		end
		S = nil
		pcall(function()
			if s.Cine and s.Cine.Running and s.Cine.Running() then
				s.Cine.Cancel()
			end
		end)
		for _, c in ipairs(s.Conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(s.Cues)
		for key in pairs(s.Ducks) do
			if Mixer and Mixer.Release then
				pcall(Mixer.Release, key, instant and .2 or 1.5)
			end
		end
		for _, h in pairs(s.Layers) do
			pcall(h.Remove, h, instant and .2 or T.EndFade)
		end
		if s.Grade then
			local g = s.Grade
			if instant then
				g:Destroy()
			else
				tween(g, T.EndFade, { TintColor = WHITE, Saturation = 0, Contrast = 0, Brightness = 0 })
				task.delay(T.EndFade + .1, function()
					g:Destroy()
				end)
			end
		end
		if s.Panel and s.Panel.Gui then
			s.Panel.Gui:Destroy()
		end
		if s.Card and s.Card.Gui then
			s.Card.Gui:Destroy()
		end
		for _, m in ipairs(s.Moths) do
			m.Body:Destroy()
			m.L:Destroy()
			m.R:Destroy()
		end
		-- music handed back to the soundscape
		local prev = S
		S = s
		pcall(handMusicBack)
		S = prev
		local root = s.Root
		if instant or not root then
			if root then
				root:Destroy()
			end
		else
			-- a short dissolve, then gone
			pcall(function()
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("BasePart") then
						tween(d, 1.2, { LocalTransparencyModifier = 1 })
					elseif d:IsA("BillboardGui") then
						d.Enabled = false
					end
				end
			end)
			task.delay(1.3, function()
				root:Destroy()
			end)
		end
	end
	FinaleFX.Teardown = teardown

	local function syncState()
		if not Shared.Enabled() then
			if S then
				teardown("Disabled", true)
			end
			return
		end
		if S and S.Replay then
			if FA("State") ~= nil and FA("State") ~= "" then
				teardown("Live", true) -- a real finale outranks the journal replay
			else
				return
			end
		end
		local st = tostring(FA("State") or "")
		if st == "" then
			if S then
				if S.EndAt and now() < S.EndAt then
					return -- the victory / fail presentation finishes first
				end
				teardown("Ended", false)
			end
			return
		end
		if not nearArena() then
			if S then
				S.AwaySince = S.AwaySince or os.clock()
				if os.clock() - S.AwaySince > T.LeaveAfter then
					teardown("Left", true)
				end
			end
			return
		end
		if S then
			S.AwaySince = nil
			local fight = FA("FightId")
			if fight ~= nil and S.FightId ~= nil and fight ~= S.FightId then
				teardown("NewFight", true)
			end
		end
		if not STAGES[st] then
			return
		end
		ensureSession()
		if S.FightId == nil then
			S.FightId = FA("FightId")
		end
		if not S.Entered[st] then
			-- give the stage's own event a moment (it carries the richer payload), then enter late from the attributes
			S.Pending = S.Pending or { Stage = st, Since = os.clock() }
			if S.Pending.Stage ~= st then
				S.Pending = { Stage = st, Since = os.clock() }
			end
			if os.clock() - S.Pending.Since >= T.JoinGrace then
				local late = true
				local start = tonumber(FA("StageStart")) or 0
				if st == "FakeDeath" and now() - start < 1.5 then
					late = false
				end
				enterStage(st, { At = start, StartAt = (st == "Hound") and FA("StartAt") or start }, late)
			end
		end
		-- the hound's bark points (the attributes are the truth; events only animate)
		if S.Hound then
			local hp, max = tonumber(FA("HoundHP")), tonumber(FA("HoundMax"))
			if hp and max and max > 0 then
				S.Hound.HP, S.Hound.Max = hp, max
			end
		end
		-- candles follow the attribute too (a missed Candle event never leaves a wrong flame)
		if st == "Choir" then
			local lit = bitsOf(FA("Candles"))
			if type(FA("Candles")) == "string" and FA("Candles") ~= "" then
				for i, c in pairs(S.Candles) do
					if not c.Gone and c.Lit ~= lit[i] and os.clock() - (c.ToggledAt or 0) > .8 then
						setCandleLit(c, lit[i], false)
					end
				end
			end
			setPatternDisplay(bitsOf(FA("Pattern")), lit)
		end
	end
	FinaleFX.Sync = syncState

	---------------------------------------------------------------------------------------------------------------
	-- events
	---------------------------------------------------------------------------------------------------------------
	local function hitPopup(d: any, pos: Vector3)
		local mine = d.UserId == player.UserId
		if d.Counted then
			FX.Cracks(pos, (camPos() - pos).Magnitude > .1 and (camPos() - pos).Unit or V3(0, 1, 0), VIOLET_HOT, mine and 4 or 2.5, .8)
			FX.Burst(pos, { Color = WHITE, Color2 = VIOLET_HOT, Count = math.floor((mine and 22 or 10) * S.Q), Speed = { 6, 14 }, Lifetime = { .25, .6 } })
			play("WeakPointHit", pos, { Volume = mine and .9 or .5, Pitch = 1.1 })
			if mine then
				local need = tonumber(d.Need) or 0
				popup(pos + V3(0, 3, 0), need > 0 and (tostring(d.Hits or 0) .. " / " .. need) or "+1", VIOLET_HOT, true)
				impulse(.5)
			end
		elseif mine then
			if d.Reason == "Toll" then
				popup(pos + V3(0, 3, 0), L("MISSED THE TOLL", "МИМО ЗВОНА"), RGB(255, 140, 140), true)
			else
				popup(pos + V3(0, 3, 0), L("IMMUNE", "НЕУЯЗВИМО"), ASH, true)
			end
			play("ChainPulse", pos, { Volume = .4, Pitch = .7 })
		end
	end

	local function onFinale(d: any)
		if type(d) ~= "table" or not Shared.Enabled() then
			return
		end
		local stage = d.Stage
		if STAGES[stage] then
			if not nearArena() and stage ~= "Victory" and stage ~= "Fail" then
				return
			end
			if (stage == "Victory" or stage == "Fail") and not (S and not S.Replay) and not nearArena() then
				return
			end
			enterStage(stage, d, false)
			return
		end
		if not S or S.Replay then
			return
		end
		local G = S.G
		if stage == "ChainActive" then
			local key = tostring(d.Key or "")
			if S.Chains[key] and S.Chains[key].Broken then
				S.Chains[key] = nil -- a late joiner guessed wrong: this one is alive
			end
			local ch = buildChain(key, false)
			ch.TargetId = d.TargetId
			ch.HitPos = vecOf(d.Position)
			ch.Need = tonumber(d.Need) or 0
			ch.Hits = tonumber(d.Hits) or 0
			ch.Dirty = true
			setActiveChain(key, tonumber(d.Since), tonumber(d.Pulse), tonumber(d.Bright))
			local p = ch.HitPos or chainAnchor(key):Lerp(G.BellCF.Position, G.ChainAlong or .25)
			FX.Burst(p, { Color = VIOLET_HOT, Color2 = WHITE, Count = math.floor(20 * S.Q), Speed = { 4, 10 }, Lifetime = { .4, .8 } })
			play("ChainPulse", p, { Volume = 1, Pitch = 1.2 })
		elseif stage == "ChainHit" then
			local key = tostring(d.Key or "")
			local ch = S.Chains[key]
			if ch then
				ch.Hits = tonumber(d.Hits) or ch.Hits
				ch.Need = tonumber(d.Need) or ch.Need
				if d.Counted then
					ch.Heat = 1
				end
			end
			local pos = (ch and ch.HitPos) or chainAnchor(key):Lerp(G.BellCF.Position, G.ChainAlong or .25)
			hitPopup(d, pos)
		elseif stage == "ChainBreak" then
			local key = tostring(d.Key or "")
			local ch = S.Chains[key]
			if ch then
				shatterChain(ch)
			end
			if S.Bell then
				bellToll(S.Bell, .8)
				S.Bell.Glow = 1
			end
			shake(.6, .6)
			local left = tonumber(d.Left) or 0
			if left > 0 then
				banner("CHAIN BROKEN!", "ЦЕПЬ РАЗБИТА!", left .. " LEFT", "ОСТАЛОСЬ: " .. left, VIOLET_HOT, 2.2)
			else
				banner("THE BELL IS FREE!", "КОЛОКОЛ СВОБОДЕН!", "Something stirs beneath the pit...", "Под ямой что-то шевелится...", VIOLET_HOT, 2.6)
			end
		elseif stage == "BellToll" then
			local at = tonumber(d.At) or now()
			-- the swing peaks as the ring hits
			cue(at - .55, function()
				if S.Bell then
					bellToll(S.Bell, 1)
				end
			end, "Toll")
		elseif stage == "Candle" then
			local c = S.Candles[tonumber(d.Index) or 0]
			if c then
				c.ToggledAt = os.clock()
				setCandleLit(c, d.Lit == true, true)
			end
			if d.Match and S.Bell then
				S.Bell.Glow = 1
				play("SealIgnite", S.Bell and bellCenter(S.Bell) or nil, { Volume = .7 })
			end
			setPatternDisplay(bitsOf(FA("Pattern")), bitsOf(d.Candles or FA("Candles")))
		elseif stage == "Round" then
			setPatternDisplay(bitsOf(d.Pattern), bitsOf(FA("Candles")))
			if S.Bell then
				S.Bell.Glow = 1
			end
			if d.Cleared then
				banner("THE CHOIR FALTERS!", "ХОР ДРОГНУЛ!", L("Round ", "Раунд ") .. tostring(d.Round or "") .. L(" cleared", " пройден"), nil, MOON, 2.4)
				play("SealComplete", nil, { Group = "Cinema", Volume = .5 })
			elseif d.Reset then
				banner("THE WEAK POINTS SINK", "СЛАБЫЕ МЕСТА УШЛИ", "A new pattern on the bell", "Новый узор на колоколе", ASH, 2.4)
			else
				banner("A NEW PATTERN", "НОВЫЙ УЗОР", "Match the bell again", "Повтори узор колокола", MOON, 2)
			end
		elseif stage == "WeakOpen" then
			local untilAt = tonumber(d.Until)
			for _, pt in ipairs(type(d.Points) == "table" and d.Points or {}) do
				local p = type(pt) == "table" and vecOf(pt.Position)
				if p then
					buildWeak(pt.Id, p, untilAt)
				end
			end
			banner("BURIED WEAK POINTS!", "ПОГРЕБЁННЫЕ СЛАБЫЕ МЕСТА!", "Dig them up before they sink", "Раскопай, пока не ушли", GOLD, 2.6)
			play("WeakOpen", G.Pit, { Volume = 1 })
		elseif stage == "Ghosts" then
			play("GhostDogBark", G.Pit, { Volume = .9 })
			play("GhostDogBark", G.Pit, { Volume = .7, Pitch = 1.2, Delay = .2 })
			syncGhosts()
		elseif stage == "GhostBite" then
			local v = S.Ghosts[d.TargetId]
			if v then
				v.BiteAt = os.clock()
				play("GhostDogBark", v.Pos, { Volume = .8 })
			end
		elseif stage == "GhostDown" then
			local v = S.Ghosts[d.TargetId]
			if v then
				v.Down = true
				removeGhost(d.TargetId, true)
			end
		elseif stage == "Volley" then
			local from = vecOf(d.From)
			if from then
				if not S.Spirit then
					spawnSpirit(from)
				end
				local sp = S.Spirit
				sp.To = from + V3(0, 2, 0)
				sp.Face = G.Pit
				sp.Mode = "Throw"
				sp.T0 = os.clock()
				spiritBurst(sp.To + V3(0, 7, 0), false)
				play("GhostWoo", sp.To, { Volume = .8 })
			end
		elseif stage == "HoundPattern" then
			local h = S.Hound
			if h then
				local beatAt = tonumber(d.BeatAt) or now()
				h.Pattern = { Name = tostring(d.Name or "Circles"), BeatAt = beatAt, Until = tonumber(d.BarkAt) or (beatAt + (tonumber(d.Beats) or 8) * 60 / h.Bpm) }
				play("HoundBark", h.CF.Position + V3(0, 40, 0), { Volume = .5, Pitch = 1.3 })
			end
		elseif stage == "Bark" then
			local h = S.Hound
			if h then
				local at = tonumber(d.At) or now()
				startBark(h, at, tonumber(d.CounterUntil) or (at + 3), vecOf(d.JawPos))
				cue(at, function()
					if S.Hound then
						play("HoundBark", S.Hound.CF.Position + V3(0, 30, 0), { Volume = 1.2 })
						shake(.9, .7)
						impulse(1.4)
						local jp = S.Hound.Bark and S.Hound.Bark.Jaw
						if jp then
							FX.Shockwave(jp, GOLD, 14, .6)
							FX.Burst(jp, { Color = GOLD_HOT, Color2 = VIOLET_HOT, Count = math.floor(40 * S.Q), Speed = { 10, 22 }, Lifetime = { .4, .8 } })
						end
						banner("COUNTER!", "КОНТРУДАР!", "PERFECT hits on its open jaw", "ИДЕАЛЬНЫЕ удары по раскрытой пасти", GOLD, 1.8)
					end
				end, "Bark")
			end
		elseif stage == "Counter" then
			local h = S.Hound
			if h then
				h.HP = tonumber(d.HP) or h.HP
				h.Max = tonumber(d.Max) or h.Max
				local jp = (h.Bark and h.Bark.Jaw) or (h.JawCore and h.JawCore.Position) or G.JawPos
				local mine = d.UserId == player.UserId
				if d.Counted ~= false then
					-- the jaw flinches, sparks, a big number for our own hit
					h.Cur.Head = (h.Cur.Head or CF()) * ANG(.12, 0, rand(-.05, .05))
					FX.Burst(jp, { Color = GOLD_HOT, Color2 = WHITE, Count = math.floor((mine and 28 or 12) * S.Q), Speed = { 8, 18 }, Lifetime = { .3, .6 } })
					play("WeakPointHit", jp, { Volume = mine and 1 or .5 })
					if mine then
						popup(jp + V3(0, 4, 0), "-1", GOLD_HOT, true)
						impulse(.6)
					end
				elseif mine then
					local why = d.Reason == "Perfect" and L("PERFECT ONLY", "ТОЛЬКО ИДЕАЛЬНО") or (d.Reason == "Cap" and L("ENOUGH FOR THIS BARK", "ХВАТИТ НА ЭТОТ ЛАЙ")
						or L("TOO LATE", "ПОЗДНО"))
					popup(jp + V3(0, 4, 0), why, ASH, true)
				end
			end
		end
	end
	FinaleFX.Event = onFinale

	---------------------------------------------------------------------------------------------------------------
	-- the journal replay (client-only): FakeDeath -> the bell's descent on a memory stage
	---------------------------------------------------------------------------------------------------------------
	local function replayCollapse(rc: any, dt: number)
		-- the Gravekeeper sinks to the floor (a short version of BossFX's death pose)
		local e = os.clock() - rc.T0
		local d = smooth((e - .4) / 2)
		local s = smooth(e / .5) * (1 - d)
		local P = {
			Pelvis = ANG(-.12 * s - .1 * d, 0, .1 * d), Chest = ANG(-.08 * s - .1 * d, 0, -.08 * d), Neck = ANG(-.5 * s - .7 * d, .2 * d, 0),
			Head = ANG(-.3 * s - .35 * d, 0, .3 * d), Jaw = ANG(-.6 * s - .8 * d, 0, 0), ArmR = ANG(-.2 * d, 0, -.75 * d), ArmL = ANG(-.2 * d, 0, .75 * d),
			ThighR = ANG(-.4 * d, 0, -.6 * d), ThighL = ANG(-.4 * d, 0, .6 * d), ShinR = ANG(.9 * d, 0, 0), ShinL = ANG(.9 * d, 0, 0),
		}
		local y = -5.5 * d - 10 * smooth((e - 5.6) / 1.6)
		rc.Rig.Root.CFrame = rc.CF * CF(0, 1 + y, 0)
		local kk = 1 - math.exp(-dt * 8)
		for name, m in pairs(rc.Rig.Motors) do
			local cur = rc.Cur[name] or CF()
			cur = cur:Lerp(P[name] or CF(), kk)
			rc.Cur[name] = cur
			m.Transform = cur
		end
	end
	local function startReplay(): boolean
		if S then
			return false -- a live finale (or a replay) is on
		end
		local c = cinema()
		if not (c and c.Play) then
			return false
		end
		S = newSession(true)
		local O = T.ReplayOrigin
		local stage = Models.ReplayStage()
		stage:PivotTo(CF(O))
		stage.Parent = S.Root
		local anchors = {}
		for _, key in ipairs(Models.Keys) do
			local post = stage:FindFirstChild("Anchor_" .. key) :: Model?
			local root = post and post.PrimaryPart
			local ring = root and root:FindFirstChild("Ring")
			if root and ring and ring:IsA("Attachment") then
				anchors[key] = (root.CFrame * ring.CFrame).Position
			end
		end
		S.G = { Pit = O, BellCF = CF(O + V3(0, 28, 0)), Anchors = anchors, ChainAlong = .3, Candles = {}, HoundCF = CF(O + V3(0, 0, 50)),
			MoonDir = V3(0, .35, 1).Unit, JawPos = O + V3(0, 10, 18), FloorY = O.Y }
		-- the replay's own anchor posts are part of the stage: chains hook straight into their rings
		for key, p in pairs(anchors) do
			S.Anchors[key] = { Model = nil, Root = nil, CF = CF(p), RingLocal = Vector3.zero, Born = 0, Rise = 1 }
		end
		-- lights for the memory
		for i = 1, (S.Q >= .7 and 3 or 1) do
			local a = i / 3 * 2 * PI
			local holder = FX.Part({ Name = "MemoryLight", Size = V3(.2, .2, .2), Transparency = 1, CFrame = CF(O + V3(math.cos(a) * 20, 24, math.sin(a) * 20)),
				Parent = S.Root })
			local l = Instance.new("PointLight")
			l.Color = i == 1 and VIOLET or MOON
			l.Range = 60
			l.Brightness = 1.6
			l.Shadows = false
			l.Parent = holder
		end
		-- the Gravekeeper, falling
		local boss = BossModels.Build()
		boss.Name = "MemoryGravekeeper"
		local rig = BossModels.Rig(boss)
		boss.Parent = S.Root
		local bcf = CF(O) * ANG(0, PI * .15, 0)
		S.ReplayCorpse = { Model = boss, Rig = rig, CF = bcf, T0 = os.clock(), Cur = {}, Core = O + V3(0, 7, 0) }
		local at = now() + .4
		local F = T.FakeDeath
		enterFakeDeath(at, false)
		local bellStart = at + F.Seconds
		cue(bellStart, function()
			if S and S.ReplayCorpse then
				local m = S.ReplayCorpse.Model
				S.ReplayCorpse = nil
				for _, p in ipairs(m:GetDescendants()) do
					if p:IsA("BasePart") then
						tween(p, 1.2, { Transparency = 1 })
					end
				end
				task.delay(1.3, function()
					m:Destroy()
				end)
			end
			enterBell({ StartAt = bellStart, BellCF = S.G.BellCF, Descend = T.Descend }, false)
		end, "ReplayBell")
		local total = F.Seconds + T.Descend + 3.2
		-- one cinematic over the whole replay: low behind the corpse, then up to the bell
		local eye0 = O + V3(-26, 12, -30)
		local eye1 = O + V3(-30, 8, -34)
		local h = c.Play({ Id = "FinaleReplay", Duration = total, Force = true, Skippable = true, SkipAfter = .8, Duck = false, BlendIn = 0, BlendOut = .4,
			Shot = function(e)
				if e < F.Seconds then
					local k = smooth(e / F.Seconds)
					return look(eye0:Lerp(eye0 + V3(8, -4, 8), k), O + V3(0, 4 + k * 4, 0))
				end
				local k = smooth((e - F.Seconds) / (T.Descend + 1))
				return look(eye1, (O + V3(0, 60, 0)):Lerp(O + V3(0, 26, 0), k))
			end,
			OnDone = function()
				if S and S.Replay then
					teardown("ReplayDone", true)
				end
			end })
		if not h then
			teardown("ReplayRefused", true)
			return false
		end
		S.Cine = h
		h.Fade(1, 0, { MaxHold = 2 })
		h.Fade(0, .8)
		return true
	end
	FinaleFX.Replay = startReplay

	---------------------------------------------------------------------------------------------------------------
	-- wiring + the frame loop
	---------------------------------------------------------------------------------------------------------------
	local function step(dt: number)
		if not S then
			return
		end
		stepCues()
		if not S then
			return
		end
		if S.ReplayCorpse then
			replayCollapse(S.ReplayCorpse, dt)
		end
		stepSpirit(dt)
		stepBell(dt)
		stepChains(dt)
		stepCandles(dt)
		stepWeak(dt)
		stepGhosts(dt)
		stepHound(dt)
		stepMoon(dt)
		stepMoths(dt)
		-- the card shudders as it cracks
		if S.Card and S.Card.Shake and S.Card.Card and S.Card.Card.Parent then
			local e = os.clock() - S.Card.Shake
			local a = math.max(0, 1 - e / .6) * 6
			S.Card.Card.Rotation = math.sin(e * 60) * a * .4
		end
		-- anchors sink with the chains gone
		for key, rec in pairs(S.Anchors) do
			if rec.Sink and rec.Root then
				local e = math.clamp((os.clock() - rec.Sink) / 1.5, 0, 1)
				rec.Root.CFrame = rec.CF * CF(0, -12 * smooth(e), 0)
				if e >= 1 then
					rec.Model:Destroy()
					S.Anchors[key] = nil
				end
			end
		end
		-- the hound sinks back into the dark when the bell silences you
		if S.Hound and S.Hound.Sink and not S.Hound.Shattered then
			local e = math.clamp((os.clock() - S.Hound.Sink) / 3, 0, 1)
			S.Hound.Rig.Root.CFrame = houndRootBase(S.Hound) * CF(0, -T.RiseDepth * smooth(e), 0)
		end
	end

	local lastSync, lastGhost, lastPanel = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		if t - lastSync >= .25 then
			lastSync = t
			local ok, err = pcall(syncState)
			if not ok then
				warn("Halloween FinaleFX sync: " .. tostring(err))
			end
		end
		if not S then
			return
		end
		if not S.Replay and t - lastGhost >= .2 then
			lastGhost = t
			pcall(syncGhosts)
			pcall(musicGuard)
		end
		local ok, err = pcall(step, dt)
		if not ok then
			warn("Halloween FinaleFX step: " .. tostring(err))
		end
		if t - lastPanel >= .1 then
			lastPanel = t
			local okP, errP = pcall(updatePanel)
			if not okP then
				warn("Halloween FinaleFX panel: " .. tostring(errP))
				destroyPanel()
			end
		end
	end)

	Bus.On("Signal", function(s)
		if type(s) == "table" and s.Kind == "BossEvent" and type(s.Data) == "table" and s.Data.Kind == "Finale" then
			local ok, err = pcall(onFinale, s.Data)
			if not ok then
				warn("Halloween FinaleFX: " .. tostring(err))
			end
		end
	end)
	Bus.On("C2Replay", function(d)
		if type(d) == "table" and d.Id == "Finale" then
			local ok, err = pcall(startReplay)
			if not ok then
				warn("Halloween FinaleFX replay: " .. tostring(err))
				teardown("ReplayError", true)
			end
		end
	end)
	-- a hazard telegraph appeared: the fight needs the player's own camera back
	Bus.On("CombatHazard", function()
		if S and S.Cine and S.Cine.InCombat then
			stopShot("Hazard")
		end
	end)
	player:GetAttributeChangedSignal("HwDowned"):Connect(function()
		if downed() and S and S.Cine and not S.Replay then
			stopShot("Downed")
		end
	end)
	local function watchFolder()
		local f = finaleFolder()
		if f then
			f.AttributeChanged:Connect(function(name)
				if name == "State" or name == "FightId" then
					pcall(syncState)
				end
			end)
			return true
		end
		return false
	end
	if not watchFolder() then
		local conn
		conn = stateRoot.ChildAdded:Connect(function(c)
			if c.Name == "Finale" then
				conn:Disconnect()
				watchFolder()
			end
		end)
	end

	function FinaleFX.Active(): boolean
		return S ~= nil and not S.Replay
	end
	function FinaleFX.Stage(): string
		return S and S.Stage or ""
	end
	-- offline tests drive the module through these
	FinaleFX.Debug = {
		Event = onFinale,
		Step = function(dt: number)
			step(dt)
			updatePanel()
		end,
		Sync = syncState,
		SyncGhosts = syncGhosts,
		Session = function()
			return S
		end,
		Teardown = teardown,
		Replay = startReplay,
		MusicGuard = musicGuard,
		Wanted = wantedTheme,
	}
end

return FinaleFX
