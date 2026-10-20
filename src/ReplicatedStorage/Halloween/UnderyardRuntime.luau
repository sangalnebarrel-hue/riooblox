-- THE UNDERYARD runtime rules (ReplicatedStorage.Halloween.UnderyardRuntime, WP-H2; docs/halloween2/DESIGN.md §7.3,
-- §9 "Chapter II onboarding", §16.4, §17, §18, §24.2, §24.5). Pure: no instances, no services; time is passed in. Shared
-- by the client presentation (HalloweenClient.UnderyardFX / Lighting / Soundscape / Chapter2Guide, Trials/Toll and
-- Trials/Mourner), the server onboarding trials (ServerScriptService.Halloween.Chapter2Tutorial) and
-- tests/underyard_runtime.luau.
--   R.Config                             every WP-H2 number (presentation budgets, the onboarding trials, the guide)
--   motion (server time t, seconds):
--     R.SwingAngle(amp, period, phase, t) = amp * sin(2*pi*(t mod period)/period + phase)   §24.2 pendulums; SealRun's
--                                          server hazard uses the same formula and time base (workspace server time)
--     R.SpinAngle(speed, t)               carousel / portal swirl angle (rad), wrapped so huge server times stay exact
--     R.Drift(amp, period, t, phase)      bob offset + tilt of the drifting rock islands
--     R.BellSway(t, ampDeg, period, boost) -> pitch, roll (rad) of the Black Bell / the broken tower bell
--     R.Blink(t, seed) -> 0..1 lid closure  ·  R.Flicker(kind, t, phase, amp) -> brightness factor
--   seal state (§7.3): R.Cleared(mask) · R.SealVisual(show, hide, light, cleared) -> hidden, lit
--     R.GateOpen(district, cleared, assault) (UnderyardLayout.Unlock + the Black Bell Assault) · R.SealTags(chain)
--   world contract (the builders' attributes / names, ServerStorage.UnderyardBuild): R.MoverKind(attrs) ·
--     R.FlameKind(attrs) · R.MarkerKind(name) -> kind, base (MothSwarm / FogPoint / WispPath / GhostResident /
--     GhostPath markers, numbered "_n" or not) · R.GhostLift (marker height above its floor)
--   presence: R.UnderWeight(pos, feather?) (UnderyardLayout.Weight: Y counts)
--   music: R.Theme(s) -> theme?, opts?, hold, reason   (§24.5: override > BOSS/FINALE_* > TRIAL > UNDERYARD > Blood Moon >
--     ZONE > NIGHT; hold = the Halloween soundscape keeps the island's music silent even when the theme is nil)
--   guide: R.GuidePath(from, to, obstacles?) -> {Vector3} · R.PathLength(path) · R.PathPoint(path, distance) ·
--     R.GuideSteps (the six steps' client side) · R.GuideProgress(stepDef, view) -> have, need · R.PupGoal(...)
--   onboarding trials: R.TollNew / R.TollHit (Trial of the Toll) · R.MournerNew / R.MournerDue / R.MournerAttacked /
--     R.MournerResolve / R.MournerDowned / R.MournerRevived / R.MournerWeakHit / R.MournerShape (the Mourner)
local Layout = require(script.Parent:WaitForChild("UnderyardLayout"))

local R = {}
R.Layout = Layout
local TAU = math.pi * 2
local V3 = Vector3.new

---------------------------------------------------------------------------------------------------------------------
-- Config (WP-H2). Quality-tier tables are {High, Medium, Low}; Shared.Budget("UnderMotes") (Chapter2Config.Quality)
-- sizes the drifting motes.
---------------------------------------------------------------------------------------------------------------------
R.Config = {
	-- Lighting layer UNDERYARD (HalloweenClient.Lighting): camera presence weight, glide
	Lighting = { Feather = 40, Tau = .35, Inside = .5 },
	Motion = {
		Rate = { High = 30, Medium = 20, Low = 12 }, -- animation updates per second
		Range = { High = 260, Medium = 200, Low = 160 }, -- movers farther than this from the camera rest (§17)
		SkyRange = { High = 900, Medium = 700, Low = 0 }, -- drifting islands / moon corona (Low: static)
		Bell = { AmpDeg = 4, Period = 7.2, Cross = .62, StrikeDecay = 1.8, StrikeMax = 3.5 }, -- the Black Bell (UySwing)
		TowerBell = { AmpDeg = 1.1, Period = 9.5 }, -- the broken tower's bell (UyTowerBell)
		Swirl = .8, -- rad/s when UySwirlSpeed is missing
		Blink = { Cycle = 6.5, Duration = .24, Double = .25 },
		PupilShift = .12, -- x EyeHeight: how far a pupil follows the camera
		ConveyorSpacing = 2.2, -- belt slat pitch (FuneralCarnival CoffinConveyor)
		MoonCorona = .03, -- rad/s: the Black Moon's flares turn
	},
	-- seal-state transitions while the player watches (§7.3)
	Seal = { FadeIn = 1.2, Dissolve = 2.2, LightRamp = 2.4, CinemaWait = 14, Delay = .6, UnlitDark = .72, Assert = 2 },
	-- HwLantern / HwCandle / HwBrazier life in the Underyard (Brightness / glass colour only, never Light.Enabled)
	Flicker = { Rate = 15, Count = { High = 28, Medium = 16, Low = 6 }, Range = 120 },
	Ambient = {
		Range = 420, -- the camera must be this close to the zone for any ambient life
		Motes = { Radius = 44, Height = 20, Lifetime = 7.5 }, -- live motes = Shared.Budget("UnderMotes")
		Fog = { Count = { High = 10, Medium = 6, Low = 3 }, Range = 160 },
		Moths = { Swarms = { High = 6, Medium = 4, Low = 2 }, Range = 90, Scale = { High = 1, Medium = .6, Low = .3 }, Max = 14 },
		Wisps = { Count = { High = 6, Medium = 4, Low = 2 }, Speed = 4.5, Range = 220 },
		Ghosts = { Count = { High = 10, Medium = 6, Low = 3 }, Range = 140, Shy = 7, Fade = .8 },
		Veil = { Range = 150, Shimmer = .3 },
	},
	Banner = { Hold = 2.6, FadeIn = .45, FadeOut = .8, AfterArrival = 6 },
	Sound = {
		Bed = .85, -- UnderyardBed volume in the zone
		Organ = { Range = 150, Every = { 9, 20 }, Hold = { 5, 11 } }, -- the Funeral Carnival's calliope in fragments
		Rates = { -- seconds between one-shots {min, max} (divided by Shared.Budget("Ambient"))
			BellTollFar = { 50, 110 }, Whisper2 = { 26, 60 }, Moths = { 14, 30 }, MarshFrog = { 6, 16 }, CaveDrip = { 4, 11 },
			UyPickEcho = { 9, 22 }, DoorCreak = { 30, 70 }, GhostDogBark = { 45, 100 },
		},
		UrgentAt = 15, -- seconds left in a trial when TRIAL's "Urgent" layer comes in
		FrenzyAt = .35, -- hound HP fraction below which FINALE_HOUND's "Frenzy" layer comes in
	},
	-- the onboarding (§9): ghost-dog guide, cards, focus
	Guide = {
		ArriveDelay = 3.5, -- seconds after the portal arrival before the guide speaks (WP-F's arrival title first)
		Request = 8, -- request timeout
		Focus = 2.4, -- camera focus seconds (Cinema)
		AutoCheck = 3, -- seconds a satisfied step may wait before the client asks the server to check it (C2Tutorial)
		Pup = { Lead = 7, Height = 5.5, Speed = 18, Wait = 26, Circle = 3.6, Arrive = 13 },
		Arrow = { Step = 4, Max = 64, Speed = 6 },
		Obstacles = { { Centre = V3(0, 0, 2400), Radius = 19 } }, -- the broken bell tower
		SkipHold = 1, -- seconds SKIP GUIDE must be held
		DoneHold = 9,
	},
	-- server: tutorial echoes (step 1 "Bell Shards") — per player, only while that player is on step 1 in the Underyard
	TutorialEcho = { HP = 3, Shards = 2, Respawn = 2.5, Radius = 2.2, Range = 12, Lift = 1.6, Kind = "UyTutorialEcho" },
	-- server: the Trial of the Toll (step 2): 5 Perfect hits on the hand-bell
	Toll = { Goal = 5, Range = 12, Kind = "UyTollBell" },
	-- server: the Mourner (step 5): Circle / Line / Ring telegraphs, dodge 2, then a Perfect on the weak spot
	Mourner = {
		Kind = "UyMournerWeak",
		Damage = 10, Telegraph = 2.0, Intro = 2.6, Gap = 2.4, Recover = 3.0, Evaluate = .35, NeedDodges = 2,
		WeakWindow = 15, WeakLift = 4.4, WeakRadius = 1.6, WeakRange = 14,
		ReviveAfter = 3, ReviveHP = 60, ResumeAfter = 2.5, FarRadius = 24,
		Circle = 5.5, LineWidth = 5, LineFrom = 1.5, LineLength = 18, RingInner = 3.6, RingOuter = 13, RingGap = 64,
		Color = { 170, 110, 255 },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
-- deterministic 0..1 hash of two numbers (integer arithmetic stays exact in doubles)
function R.Hash(a: number, b: number): number
	local x = math.floor(math.abs(a)) % 1000003
	local y = math.floor(math.abs(b)) % 1000003
	local h = (x * 73856093 + y * 19349663 + 12345) % 2147483647
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h / 2147483647
end

-- a stable seed for an instance position (same on every client)
function R.SeedOf(pos: Vector3): number
	return math.floor(pos.X * 7.13 + pos.Y * 3.71 + pos.Z * 5.37) % 100003
end

function R.Smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function R.Pick(byQuality: any, quality: string?): any
	if type(byQuality) ~= "table" then
		return byQuality
	end
	local v = byQuality[quality or "High"]
	if v == nil then
		v = byQuality.High
	end
	return v
end

---------------------------------------------------------------------------------------------------------------------
-- motion
---------------------------------------------------------------------------------------------------------------------
function R.Phase01(t: number, period: number): number
	if not period or period <= 0 then
		return 0
	end
	return (t % period) / period
end

-- §24.2: angle = Amp * sin(2*pi*(serverTime mod Period)/Period) (+ the builder's UySwingPhase)
function R.SwingAngle(amp: number, period: number, phase: number?, t: number): number
	if not period or period <= 0 or not amp then
		return 0
	end
	return amp * math.sin(TAU * ((t % period) / period) + (phase or 0))
end

-- angle of something turning at `speed` rad/s, wrapped on its own period (a server time of 1.7e9 s keeps full precision)
function R.SpinAngle(speed: number, t: number): number
	if not speed or speed == 0 then
		return 0
	end
	local period = TAU / math.abs(speed)
	local a = TAU * ((t % period) / period)
	return speed < 0 and -a or a
end

-- the drifting rock islands: vertical bob (studs) and a gentle tilt (rad)
function R.Drift(amp: number, period: number, t: number, phase: number?): (number, number)
	local p = phase or 0
	local y = R.SwingAngle(amp or 0, period or 10, p, t)
	local tilt = R.SwingAngle(.035, (period or 10) * 1.37, p + 1.3, t)
	return y, tilt
end

-- a hanging bell's slow two-axis sway; boost (0..) adds a struck swing on top -> pitch (X), roll (Z) in radians
function R.BellSway(t: number, ampDeg: number, period: number, boost: number?): (number, number)
	local a = math.rad(ampDeg or 0) * (1 + (boost or 0))
	local p = period or 7
	local pitch = R.SwingAngle(a, p, 0, t)
	local roll = R.SwingAngle(a * R.Config.Motion.Bell.Cross, p * 1.618, .9, t)
	return pitch, roll
end

-- lid closure 0..1 of a blinking eye (UyBlink) at time t; every eye blinks once per cycle at its own moment, sometimes twice
function R.Blink(t: number, seed: number): number
	local cfg = R.Config.Motion.Blink
	local cycle, dur = cfg.Cycle, cfg.Duration
	local u = (t + (seed % 997) * .731) / cycle
	local k = math.floor(u)
	local at = (u - k) * cycle
	local start = R.Hash(seed, k) * (cycle - dur * 3)
	local function lid(x: number): number
		if x < 0 or x > dur then
			return 0
		end
		return math.sin(math.pi * x / dur)
	end
	local c = lid(at - start)
	if R.Hash(seed + 31, k) < cfg.Double then
		c = math.max(c, lid(at - start - dur * 1.55))
	end
	return c
end

-- brightness factor of a flame / lantern (smooth sums of sines: pure and the same on every client)
function R.Flicker(kind: string?, t: number, phase: number, amp: number?): number
	local a = amp or 1
	local p = phase or 0
	if kind == "Candle" then
		return 1 + a * (.14 * math.sin(t * 7.3 + p) + .08 * math.sin(t * 13.1 + p * 1.7) + .05 * math.sin(t * 23.7 + p * .6))
	elseif kind == "Brazier" then
		return 1 + a * (.16 * math.sin(t * 5.9 + p) + .1 * math.sin(t * 11.3 + p * 2.3) + .06 * math.sin(t * 19.1 + p * .4))
	elseif kind == "Purple" or kind == "Green" or kind == "Blue" then
		return 1 + a * (.1 * math.sin(t * 1.7 + p) + .04 * math.sin(t * 4.9 + p * 1.3))
	end
	return 1 + a * (.08 * math.sin(t * 2.3 + p) + .05 * math.sin(t * 6.7 + p * 1.9) + .03 * math.sin(t * 15.2 + p))
end

---------------------------------------------------------------------------------------------------------------------
-- seal state (§7.3)
---------------------------------------------------------------------------------------------------------------------
function R.Cleared(mask: any): number
	if type(mask) ~= "string" then
		return 0
	end
	local n = 0
	for _ in string.gmatch(mask, "1") do
		n += 1
	end
	return n
end

-- hidden: UyShowAtSeal = n (visible once >= n seals are cleared) / UyHideAtSeal = n (hidden from n on);
-- lit: UyLightAtSeal = n (lights / Neon at full only from n on) -> 1, else 0
function R.SealVisual(show: any, hide: any, light: any, cleared: number): (boolean, number)
	local c = tonumber(cleared) or 0
	local hidden = false
	if type(show) == "number" and c < show then
		hidden = true
	end
	if type(hide) == "number" and c >= hide then
		hidden = true
	end
	local lit = 1
	if type(light) == "number" and c < light then
		lit = 0
	end
	return hidden, lit
end

-- is a district gate open for this player (UnderyardLayout.Unlock; the Arena also while the Black Bell Assault runs)
function R.GateOpen(district: string, cleared: number, assault: boolean?): boolean
	local need = Layout.Unlock[district]
	if need == nil then
		return true
	end
	if district == "BlackBellArena" and assault then
		return true
	end
	return (tonumber(cleared) or 0) >= need
end

-- the cleared count a gate's own parts are judged with (an open gate counts as unlocked)
function R.GateCleared(district: string?, cleared: number, assault: boolean?): number
	if district and Layout.Unlock[district] and R.GateOpen(district, cleared, assault) then
		return math.max(cleared, Layout.Unlock[district])
	end
	return cleared
end

-- the seal tags that apply to an instance: `chain` = the attribute tables of the instance itself and then its ancestors
-- (nearest first; a lantern's PointLight inherits its glass part's tags, a part its model's). The nearest value of
-- each key wins -> show?, hide?, light?
function R.SealTags(chain: { { [string]: any } }): (number?, number?, number?)
	local show, hide, light = nil, nil, nil
	for _, a in ipairs(chain) do
		if show == nil and type(a.UyShowAtSeal) == "number" then
			show = a.UyShowAtSeal
		end
		if hide == nil and type(a.UyHideAtSeal) == "number" then
			hide = a.UyHideAtSeal
		end
		if light == nil and type(a.UyLightAtSeal) == "number" then
			light = a.UyLightAtSeal
		end
	end
	return show, hide, light
end

---------------------------------------------------------------------------------------------------------------------
-- world contract (ServerStorage.UnderyardBuild: WP-G Sky / BellSquare / Gates / FXMarkers, WP-H1 FuneralCarnival /
-- CrookedRow, WP-H3 MourningMarsh / Undercrypt / BlackBellArena)
---------------------------------------------------------------------------------------------------------------------
-- the animation a Model's attributes ask for (nil = static)
function R.MoverKind(a: { [string]: any }): string?
	if a.UySpin ~= nil then
		return "Spin" -- the carousel (UySpin rad/s, UySpinAxis)
	elseif a.UySwing == true then
		return "Bell" -- the Black Bell (UySwingAmp in degrees)
	elseif a.UySwingAmp ~= nil and a.UySwingPeriod ~= nil then
		return "Swing" -- the Funeral Run pendulums (UySwingAmp rad, UySwingPeriod s, UySwingPhase rad, UySwingAxis)
	elseif a.UySwirl == true or a.UySwirlSpeed ~= nil then
		return "Swirl" -- the arrival portal
	elseif a.UyDrift ~= nil then
		return "Drift" -- the rock islands in the sky
	elseif a.UyBlink == true then
		return "Eye" -- Crooked Row's eye windows (lids LidDir x LidTravel)
	elseif a.UyTowerBell == true then
		return "TowerBell" -- the broken tower's bell
	elseif type(a.UyMoon) == "string" then
		return "Moon" -- "Pale" (halo breathes) / "Black" (corona flares turn)
	end
	return nil
end

-- the flicker of a lantern glass / candle flame / brazier part (nil = not a flame)
function R.FlameKind(a: { [string]: any }): string?
	local lan = a.HwLantern
	if type(lan) == "string" then
		if lan == "Purple" or lan == "Green" or lan == "Blue" then
			return lan
		end
		return "Lantern"
	elseif lan == true then
		return "Lantern"
	end
	if a.HwCandle == true then
		return "Candle"
	end
	if a.HwBrazier == true then
		return "Brazier"
	end
	return nil
end

-- FX marker attachments: FXMarkers numbers them ("MothSwarm_3"), the district builders do not ("FogPoint")
R.MarkerBases = { MothSwarm = "Moth", FogPoint = "Fog", WispPath = "Wisp", GhostResident = "Ghost", GhostPath = "Ghost" }
-- how high above its floor a marker sits (ghosts hover a little under it)
R.GhostLift = { GhostResident = 2.6, GhostPath = 4 }

function R.MarkerKind(name: string): (string?, string?)
	if type(name) ~= "string" then
		return nil, nil
	end
	local base = string.match(name, "^(%a+)_%d+$") or name
	local kind = R.MarkerBases[base]
	if kind then
		return kind, base
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------------------------------
-- presence
---------------------------------------------------------------------------------------------------------------------
function R.UnderWeight(pos: Vector3?, feather: number?): number
	if typeof(pos) ~= "Vector3" then
		return 0
	end
	return Layout.Weight(pos :: Vector3, feather or R.Config.Lighting.Feather)
end

---------------------------------------------------------------------------------------------------------------------
-- music priority (§24.5)
---------------------------------------------------------------------------------------------------------------------
-- finale stages (RS.Halloween.State.Finale.State): false = the music stops (the false victory: a hard stop; the defeat),
-- a theme name otherwise. Fades match HalloweenClient.FinaleFX.MusicTheme (its guard only acts when nothing else did).
R.FinaleThemes = { FakeDeath = false, Bell = "FINALE_BELL", Choir = "FINALE_CHOIR", Hound = "FINALE_HOUND", Victory = "ZONE",
	Fail = false }
R.FinaleFades = { FakeDeath = .08, Bell = 2, Choir = 2.5, Hound = 1.5, Victory = 6, Fail = .6 }

-- s = {MusicOn, Override = {Theme, Fade}?, Finale = stage?, FinaleElapsed, Boss, Trial, Underyard, Blood ("WARNING" |
--      "ACTIVE" | "ENDING" | other), BloodElapsed, Reach, Zone, Night, Current}
-- -> theme?, opts?, hold, reason
function R.Theme(s: { [string]: any }): (string?, { [string]: any }?, boolean, string)
	if not s.MusicOn then
		return nil, nil, false, "Off"
	end
	local o = s.Override
	if type(o) == "table" and type(o.Theme) == "string" then
		return o.Theme, { Fade = tonumber(o.Fade) or .4 }, true, "Override"
	end
	local fin = s.Finale and R.FinaleThemes[s.Finale]
	if fin ~= nil then
		local fade = R.FinaleFades[s.Finale] or 1.5
		if fin == false then
			return nil, { Fade = fade }, true, "Finale"
		end
		local opts: { [string]: any } = { Fade = fade }
		if fin == "FINALE_HOUND" then
			-- every client shares the hound's beat: the theme is anchored to the stage's musical start
			opts.Elapsed = math.max(0, tonumber(s.FinaleElapsed) or 0)
		end
		return fin, opts, true, "Finale"
	end
	if s.Boss then
		return "BOSS", { Fade = 2 }, true, "Boss"
	end
	if s.Trial then
		return "TRIAL", { Fade = 1.5 }, true, "Trial"
	end
	if s.Underyard then
		return "UNDERYARD", { Fade = s.Current == "TRIAL" and 2.5 or 3 }, true, "Underyard"
	end
	if s.Blood == "WARNING" and s.Reach then
		return "BLOOD_WARN", { Elapsed = math.max(0, tonumber(s.BloodElapsed) or 0) }, true, "Blood"
	end
	if s.Blood == "ACTIVE" and s.Reach then
		return "BLOOD_MOON", { Fade = s.Current == "BLOOD_WARN" and 1.2 or 3 }, true, "Blood"
	end
	-- the moon sets slowly (8 s) into whatever plays next
	local setting = s.Current == "BLOOD_MOON" and s.Blood == "ENDING"
	local opts = setting and { Fade = 8 } or nil
	if s.Zone then
		return "ZONE", opts, true, "Zone"
	end
	if s.Night then
		return "NIGHT", opts, true, "Night"
	end
	return nil, opts, false, "None"
end

---------------------------------------------------------------------------------------------------------------------
-- guide path: straight, or round the circular obstacles it would cross (the bell tower)
---------------------------------------------------------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

-- distance from c to the segment a-b (flat)
local function segDistance(a: Vector3, b: Vector3, c: Vector3): number
	local ab = flat(b - a)
	local len2 = ab:Dot(ab)
	if len2 < 1e-9 then
		return flat(c - a).Magnitude
	end
	local k = math.clamp(flat(c - a):Dot(ab) / len2, 0, 1)
	return flat(a + ab * k - c).Magnitude
end
R.SegmentDistance = segDistance

function R.GuidePath(from: Vector3, to: Vector3, obstacles: { any }?): { Vector3 }
	local path = { from }
	local margin = 4
	for _, ob in ipairs(obstacles or R.Config.Guide.Obstacles) do
		local c, r = ob.Centre, ob.Radius
		local last = path[#path]
		local outA = flat(last - c).Magnitude > r
		local outB = flat(to - c).Magnitude > r
		if outA and outB and segDistance(last, to, c) < r then
			local a0 = math.atan2(last.Z - c.Z, last.X - c.X)
			local a1 = math.atan2(to.Z - c.Z, to.X - c.X)
			local d = (a1 - a0) % TAU
			if d > math.pi then
				d -= TAU -- the shorter way round
			end
			local steps = math.max(1, math.ceil(math.abs(d) / math.rad(40)))
			local rr = r + margin
			for i = 0, steps do
				local a = a0 + d * i / steps
				local y = last.Y + (to.Y - last.Y) * (i / steps)
				table.insert(path, V3(c.X + math.cos(a) * rr, y, c.Z + math.sin(a) * rr))
			end
		end
	end
	table.insert(path, to)
	return path
end

function R.PathLength(path: { Vector3 }): number
	local len = 0
	for i = 2, #path do
		len += (path[i] - path[i - 1]).Magnitude
	end
	return len
end

-- the point `dist` studs along the polyline (clamped to its ends) and the direction there
function R.PathPoint(path: { Vector3 }, dist: number): (Vector3, Vector3)
	local n = #path
	if n == 0 then
		return Vector3.zero, V3(0, 0, -1)
	end
	if n == 1 or dist <= 0 then
		local dir = n > 1 and (path[2] - path[1]) or V3(0, 0, -1)
		return path[1], dir.Magnitude > 1e-6 and dir.Unit or V3(0, 0, -1)
	end
	local left = dist
	for i = 2, n do
		local a, b = path[i - 1], path[i]
		local seg = (b - a).Magnitude
		if left <= seg or i == n then
			local k = seg > 1e-6 and math.clamp(left / seg, 0, 1) or 1
			local dir = seg > 1e-6 and (b - a).Unit or V3(0, 0, -1)
			return a:Lerp(b, k), dir
		end
		left -= seg
	end
	return path[n], V3(0, 0, -1)
end

---------------------------------------------------------------------------------------------------------------------
-- the guide (client side of Chapter2Config.Tutorial.Steps; keys = Steps[i].Key)
--   Target  what the guide points at: "Echo" (the nearest tutorial echo, else the TutorialEcho anchors), "HandBell",
--           "Coffin", "Ring", "Mourner", "Altar"
--   Hint    the card's second line {en, ru}; Tip an optional third (shown on wide screens / after a while)
---------------------------------------------------------------------------------------------------------------------
R.GuideSteps = {
	Shards = { Target = "Echo", Anchors = { "TutorialEcho_1", "TutorialEcho_2", "TutorialEcho_3" },
		Hint = { "Ghostly echoes float over the plaza: dig them with your pickaxe for Bell Shards.",
			"Над площадью парят призрачные эхо: копай их киркой и получай осколки колокола." },
		Tip = { "5 PERFECT hits in a row make a STREAK: bonus shards!", "5 ИДЕАЛЬНЫХ ударов подряд — это СЕРИЯ: бонусные осколки!" },
		Progress = { "Bell Shards earned", "Получено осколков" } },
	Toll = { Target = "HandBell", Anchors = { "TutorialBell" },
		Hint = { "Walk to the hand-bell by the practice ring and BEGIN TRIAL.", "Подойди к колокольчику у тренировочного круга и начни испытание." },
		Tip = { "Only a PERFECT hit rings it on the beat.", "Только ИДЕАЛЬНЫЙ удар звенит в ритм." } },
	Coffin = { Target = "Coffin", Anchors = { "CoffinShrine" },
		Hint = { "The guide left you a Coffin Key and 150 Bell Shards. Open the Black Coffin at its shrine.",
			"Проводник оставил тебе ключ от гроба и 150 осколков. Открой Чёрный гроб у его святилища." },
		Tip = { "Every coffin holds a prize: skins, cosmetics, showcase finds, even dogs.",
			"В каждом гробу награда: скины, украшения, находки для витрины и даже собаки." },
		Progress = { "Coffins opened", "Открыто гробов" } },
	Practice = { Target = "Ring", Anchors = { "PracticeRing" },
		Hint = { "Step into the practice ring: your EVENT HP bar appears.", "Встань в тренировочный круг: появится полоска ЗДОРОВЬЯ СОБЫТИЯ." },
		Tip = { "Attacks down here hit your Event HP, never your character.", "Атаки здесь бьют по здоровью события, а не по персонажу." } },
	Mourner = { Target = "Mourner", Anchors = { "Mourner" },
		Hint = { "BEGIN TRIAL at the Mourner. Step out of its glowing telegraphs: dodge 2 attacks.",
			"Начни испытание у Плакальщика. Уходи из светящихся меток: уклонись от 2 атак." },
		Tip = { "Then strike its glowing heart with a PERFECT hit.", "Потом ударь в его светящееся сердце ИДЕАЛЬНЫМ ударом." } },
	SealOffer = { Target = "Altar", Anchors = { "SealAltar_1" },
		Hint = { "Every Bell Seal needs an offering at its altar. Offer at Altar I: the guide pays this first one.",
			"Каждой печати нужно подношение у алтаря. Принеси его к алтарю I: первое оплатит проводник." },
		Tip = { "Then BEGIN TRIAL at the altar to break Seal I.", "Затем начни испытание у алтаря, чтобы сломать печать I." } },
}

-- progress of a step that completes from profile state (Chapter2Config.Tutorial.Steps[].Auto) in the client view
-- (Chapter2State.View(): Tutorial.Mark is the step's starting value) -> have, need (nil when the step has no counter)
function R.GuideProgress(def: any, view: any): (number?, number?)
	if type(def) ~= "table" or type(view) ~= "table" then
		return nil, nil
	end
	local t = type(view.Tutorial) == "table" and view.Tutorial or {}
	local mark = tonumber(t.Mark)
	local value = nil
	if def.Auto == "ShardsEarned" then
		value = type(view.Stats) == "table" and tonumber(view.Stats.ShardsEarned) or nil
	elseif def.Auto == "CoffinOpened" then
		value = type(view.Coffins) == "table" and tonumber(view.Coffins.Opened) or nil
	else
		return nil, nil
	end
	if value == nil or mark == nil then
		return nil, nil
	end
	local need = tonumber(def.Goal) or 1
	return math.clamp(value - mark, 0, need), need
end

-- where the ghost pup floats: Lead studs ahead of the player along the guide path, or circling the target once the
-- player is close -> position (feet level of the hover, the client adds Height + bob), mode "Lead" | "Circle" | "Wait"
function R.PupGoal(path: { Vector3 }, player: Vector3, target: Vector3, t: number, pupAt: Vector3?): (Vector3, string)
	local P = R.Config.Guide.Pup
	local d = flat(target - player).Magnitude
	if d <= P.Arrive then
		local a = t * .9
		return target + V3(math.cos(a) * P.Circle, 0, math.sin(a) * P.Circle), "Circle"
	end
	-- the pup waits (turned back) when the player fell far behind it
	if pupAt and flat(pupAt - player).Magnitude > P.Wait then
		return pupAt, "Wait"
	end
	local len = R.PathLength(path)
	local along = math.clamp(P.Lead, 0, math.max(0, len - P.Circle))
	local pos = R.PathPoint(path, along)
	return pos, "Lead"
end

-- a camera focus on a target seen from where the player stands (higher and a little to the side, never inside it)
function R.FocusFrom(target: Vector3, player: Vector3, dist: number?, height: number?): Vector3
	local dir = flat(player - target)
	dir = dir.Magnitude > .5 and dir.Unit or V3(0, 0, -1)
	local side = V3(-dir.Z, 0, dir.X)
	return target + dir * (dist or 15) + side * 4 + V3(0, height or 7, 0)
end

---------------------------------------------------------------------------------------------------------------------
-- the Trial of the Toll (step 2): only a Perfect rings the hand-bell on the beat
---------------------------------------------------------------------------------------------------------------------
function R.TollNew(goal: number?): { [string]: any }
	return { Count = 0, Goal = goal or R.Config.Toll.Goal, Hits = 0, Off = 0 }
end

-- -> counted, done
function R.TollHit(st: { [string]: any }, perfect: boolean): (boolean, boolean)
	st.Hits += 1
	if perfect then
		st.Count = math.min(st.Goal, st.Count + 1)
		return true, st.Count >= st.Goal
	end
	st.Off += 1
	return false, st.Count >= st.Goal
end

---------------------------------------------------------------------------------------------------------------------
-- the Mourner (step 5): Circle -> Line -> Ring per cycle; a cycle with >= NeedDodges dodges opens the weak spot, else
-- the cycle repeats. Downed -> revived after ReviveAfter; an unused weak spot closes after WeakWindow, one Ring later it
-- opens again. Phases: Intro, Recover (waiting for the next attack), Telegraph (an attack in the air), Weak, Downed, Won.
---------------------------------------------------------------------------------------------------------------------
R.MournerOrder = { "Circle", "Line", "Ring" }

function R.MournerNew(now: number): { [string]: any }
	return { Phase = "Intro", Cycle = 1, Index = 0, Dodges = 0, NextAt = now + R.Config.Mourner.Intro, Attack = nil, WeakUntil = 0,
		ReviveAt = 0, Retry = false, Hits = 0, Dodged = 0, Downs = 0, Opened = 0 }
end

-- what the server must do now: "Attack" | "Evaluate" | "CloseWeak" | "Revive" | nil
function R.MournerDue(st: { [string]: any }, now: number): string?
	local ph = st.Phase
	if (ph == "Intro" or ph == "Recover") and now >= st.NextAt then
		return "Attack"
	elseif ph == "Telegraph" and st.Attack and now >= st.Attack.ImpactAt + R.Config.Mourner.Evaluate then
		return "Evaluate"
	elseif ph == "Weak" and now >= st.WeakUntil then
		return "CloseWeak"
	elseif ph == "Downed" and now >= st.ReviveAt then
		return "Revive"
	end
	return nil
end

-- the kind of the next attack
function R.MournerNextKind(st: { [string]: any }): string
	if st.Retry then
		return "Ring"
	end
	return R.MournerOrder[math.clamp(st.Index + 1, 1, #R.MournerOrder)]
end

function R.MournerAttacked(st: { [string]: any }, kind: string, impactAt: number)
	if not st.Retry then
		st.Index += 1
	end
	st.Phase = "Telegraph"
	st.Attack = { Kind = kind, ImpactAt = impactAt }
end

-- after an attack landed: hit = the player lost Event HP to it -> outcome, follow-up ("Weak" | "Again" | "Next")
function R.MournerResolve(st: { [string]: any }, hit: boolean, now: number): (string, string)
	local cfg = R.Config.Mourner
	st.Attack = nil
	local outcome = hit and "Hit" or "Dodged"
	if hit then
		st.Hits += 1
	else
		st.Dodges += 1
		st.Dodged += 1
	end
	if st.Retry then
		st.Retry = false
		st.Phase = "Weak"
		st.WeakUntil = now + cfg.WeakWindow
		st.Opened += 1
		return outcome, "Weak"
	end
	if st.Index >= #R.MournerOrder then
		if st.Dodges >= cfg.NeedDodges then
			st.Phase = "Weak"
			st.WeakUntil = now + cfg.WeakWindow
			st.Opened += 1
			return outcome, "Weak"
		end
		st.Cycle += 1
		st.Index = 0
		st.Dodges = 0
		st.Phase = "Recover"
		st.NextAt = now + cfg.Recover
		return outcome, "Again"
	end
	st.Phase = "Recover"
	st.NextAt = now + cfg.Gap
	return outcome, "Next"
end

-- the weak spot closed unused: one Ring, then it opens again
function R.MournerWeakClosed(st: { [string]: any }, now: number)
	st.Phase = "Recover"
	st.Retry = true
	st.NextAt = now + R.Config.Mourner.Recover
end

function R.MournerDowned(st: { [string]: any }, now: number)
	st.Downs += 1
	st.Phase = "Downed"
	st.ReviveAt = now + R.Config.Mourner.ReviveAfter
	if st.Attack then
		-- the attack that downed the player counts as a hit; the sequence resumes after the revive
		st.Attack = nil
		st.Hits += 1
		if st.Index >= #R.MournerOrder and not st.Retry then
			if st.Dodges >= R.Config.Mourner.NeedDodges then
				st.AfterRevive = "Weak"
			else
				st.Cycle += 1
				st.Index = 0
				st.Dodges = 0
			end
		end
	end
end

function R.MournerRevived(st: { [string]: any }, now: number): string
	local cfg = R.Config.Mourner
	if st.AfterRevive == "Weak" then
		st.AfterRevive = nil
		st.Phase = "Weak"
		st.WeakUntil = now + cfg.ResumeAfter + cfg.WeakWindow
		st.Opened += 1
		return "Weak"
	end
	st.Phase = "Recover"
	st.NextAt = now + cfg.ResumeAfter
	return "Recover"
end

-- a hit on the weak spot: only a Perfect while it is open wins
function R.MournerWeakHit(st: { [string]: any }, perfect: boolean): boolean
	if st.Phase ~= "Weak" or not perfect then
		return false
	end
	st.Phase = "Won"
	return true
end

-- the telegraph of an attack as plain data (Hazards.Circle / Line / Ring arguments):
--   Circle on the player, Line from the Mourner through the player, Ring round the Mourner with one gap
-- gapAngle (degrees, 0 = +X, 90 = +Z) only for the Ring; the server picks it a quarter turn away from the player.
function R.MournerShape(kind: string, centre: Vector3, target: Vector3, gapAngle: number?): { [string]: any }
	local cfg = R.Config.Mourner
	local c = V3(centre.X, centre.Y, centre.Z)
	if kind == "Circle" then
		return { Type = "Circle", Center = V3(target.X, c.Y, target.Z), Radius = cfg.Circle }
	elseif kind == "Line" then
		local d = flat(target - c)
		d = d.Magnitude > .5 and d.Unit or V3(0, 0, 1)
		return { Type = "Line", From = c + d * cfg.LineFrom, To = c + d * cfg.LineLength, Width = cfg.LineWidth }
	end
	return { Type = "Ring", Center = c, Inner = cfg.RingInner, Outer = cfg.RingOuter,
		Gaps = { { Angle = (gapAngle or 0) % 360, Width = cfg.RingGap } } }
end

-- the gap of the Ring a quarter turn from where the player stands (left or right by the seed): they must move to it
function R.MournerGapAngle(centre: Vector3, target: Vector3, seed: number): number
	local d = flat(target - centre)
	local a = d.Magnitude > .5 and math.deg(math.atan2(d.Z, d.X)) or 0
	return (a + (R.Hash(seed, 7) < .5 and 90 or -90)) % 360
end

return R
