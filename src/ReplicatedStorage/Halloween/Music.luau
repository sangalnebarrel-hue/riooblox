-- Procedural Halloween OST (ReplicatedStorage.Halloween.Music), client only. WP10a.
-- The game ships no uploaded music the event can rely on, so every theme is sequenced live from the built-in
-- rbxasset sounds (music box = re-pitched PING, bass bongs, LAND heartbeats/impacts, KNOCK snares, looped drones).
-- Optional upgrade: Config.Music.OstAssetId / BloodMoonAssetId (uploaded ids) replace the procedural NIGHT/ZONE and
-- BLOOD_MOON themes once they are really audible (IsLoaded and TimeLength > 0); otherwise the recipe plays.
--
-- API
--   Music.Start()                         create the voice pools + Heartbeat sequencer (idempotent)
--   Music.SetTheme(name|nil, opts?)       crossfade to NIGHT | ZONE | BLOOD_WARN | BLOOD_MOON | BOSS | nil (silence)
--                                         opts {Fade = seconds (default Config.Music.Crossfade = 3), Elapsed = seconds
--                                         since the theme's musical start (anchors BLOOD_WARN to the warning timestamp)}
--   Music.SetLayer(theme, layer, gain)    optional layers inside a theme (BOSS "Enrage")
--   Music.SetMaster(v)                    0..1 (music setting x world-event-track-audible), smoothed over 1.5 s
--   Music.Stop(fade?)                     fade everything out and stop the sequencer
--   Music.Snapshot()                      {Theme, Gains = {name = gain}, Voices, Master, Uploads}
--   Music.Player / Music.Themes / Music.Instruments   pure sequencer + data (tools/hw_test_wp10a.luau)
-- Mix: every voice plays in SoundService.DOGROTS_AUDIO.Halloween (Audio.Group "Music", compressor, ducked with the island's
-- music by Secret arrivals / Lab silence). Crossfades move each theme's Gain linearly toward its target (equal-power curve
-- on the voices); SoundGroup.Volume is never written. Voice budget: 12 simultaneous voices (6 on Low; Low also drops the
-- "Rich" layers: drones, choir, octave doubling, plucks).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local root = script.Parent
local Config = require(root:WaitForChild("Config"))
local Audio = require(root:WaitForChild("Audio"))
local Shared = nil -- lazily (quality)

local Music = {}
local SRC = Audio.Sources
Music.ROOT = 1 -- PlaybackSpeed of semitone 0 (A) for melodic voices; the PING sample's pitch is unknown: tune by ear
Music.LOOKAHEAD = .06 -- schedule notes this far ahead of the clock
Music.LATE = .25 -- notes later than this (hitch) are skipped, never bunched
Music.Cap = { High = 12, Medium = 10, Low = 6 }
Music.UploadVolume = .55

---------------------------------------------------------------------------------------------------------------------
-- Instruments (pooled voices). Speed = base PlaybackSpeed; melodic voices also multiply ROOT*2^(semi/12).
---------------------------------------------------------------------------------------------------------------------
local EQ = function(l, m, h)
	return { LowGain = l, MidGain = m, HighGain = h }
end
local I = {}
Music.Instruments = I
I.Box = { Id = SRC.PING, Speed = 1, Volume = .15, Dur = 1.5, Fade = .55, Pool = 6, Tail = "Hall", Melodic = true,
	Fx = { EqualizerSoundEffect = EQ(-8, 0, 3) }, Pluck = "Pluck" }
I.Pluck = { Id = SRC.TICK, Speed = 3.2, Volume = .03, Dur = .12, Fade = .04, Pool = 3, Rich = true }
I.Bass = { Id = SRC.PING, Speed = 1, Volume = .2, Dur = 2.6, Fade = 1, Pool = 3, Tail = "Crypt", Melodic = true,
	Fx = { EqualizerSoundEffect = EQ(8, -2, -16) } }
I.Heart = { Id = SRC.LAND, Speed = .42, Volume = .3, Dur = .45, Fade = .15, Pool = 3,
	Fx = { EqualizerSoundEffect = EQ(10, -2, -30), DistortionSoundEffect = { Level = .45 } } }
I.Clock = { Id = SRC.CLICK, Speed = .7, Volume = .05, Dur = .22, Fade = .08, Pool = 2, Fx = { EqualizerSoundEffect = EQ(-6, 2, -4) } }
I.Bell = { Id = SRC.PING, Speed = .5, Volume = .26, Dur = 3.6, Fade = 1.6, Pool = 3, Tail = "Crypt", Melodic = true,
	Fx = { EqualizerSoundEffect = EQ(6, 0, -10) } }
I.Ost = { Id = SRC.PING, Speed = 1, Volume = .13, Dur = .15, Fade = .05, Pool = 4, Tail = "Hall", Melodic = true,
	Fx = { EqualizerSoundEffect = EQ(2, 4, -6), DistortionSoundEffect = { Level = .15 } } }
I.Hit = { Id = SRC.LAND, Speed = .25, Volume = .42, Dur = 1.2, Fade = .5, Pool = 3, Tail = "Crypt",
	Fx = { DistortionSoundEffect = { Level = .8 }, EqualizerSoundEffect = EQ(10, 0, -20) } }
I.Snare = { Id = SRC.KNOCK, Speed = .55, Volume = .2, Dur = .35, Fade = .12, Pool = 2,
	Fx = { EqualizerSoundEffect = EQ(-4, 6, 0), DistortionSoundEffect = { Level = .3 } } }
I.Stab = { Id = SRC.PING, Speed = 1, Volume = .17, Dur = .75, Fade = .3, Pool = 2, Tail = "Hall", Melodic = true,
	Fx = { DistortionSoundEffect = { Level = .55 }, EqualizerSoundEffect = EQ(6, 3, -12) } }
I.Alarm = { Id = SRC.PING, Speed = 1, Volume = .1, Dur = .5, Fade = .2, Pool = 2, Tail = "Hall", Melodic = true,
	Fx = { EqualizerSoundEffect = EQ(-6, 2, 4) } }

-- Looped beds inside themes. Vol/Speed: number or {from, to} ramp over Ramp seconds of theme time; Lfo = {depth, period}.
local L = {}
Music.Loops = L
L.Drone = { Id = SRC.PING, Speed = .5, Vol = .045, Rich = true, Lfo = { .25, 7 },
	Fx = { TremoloSoundEffect = { Frequency = 4.5, Depth = .25, Duty = .5 }, EqualizerSoundEffect = EQ(6, -2, -14) } }
L.DroneFifth = { Id = SRC.PING, Speed = .749, Vol = .03, Rich = true, Lfo = { .3, 9 },
	Fx = { TremoloSoundEffect = { Frequency = 3.8, Depth = .3, Duty = .5 }, EqualizerSoundEffect = EQ(6, -2, -14) } }
L.Wind = { Id = SRC.WIND, Speed = .5, Vol = .035, Lfo = { .4, 11 },
	Fx = { EqualizerSoundEffect = EQ(4, -2, -12), FlangeSoundEffect = { Depth = .6, Mix = .5, Rate = .12 } } }
L.Rumble = { Id = SRC.WIND, Speed = { .35, .5 }, Vol = { .04, .14 }, Ramp = 30,
	Fx = { EqualizerSoundEffect = EQ(10, -6, -30) } }
L.Tension = { Id = SRC.PING, Speed = { .98, 1.06 }, Vol = { .0, .035 }, Ramp = 30, Rich = true,
	Fx = { TremoloSoundEffect = { Frequency = 7, Depth = .6, Duty = .5 }, EqualizerSoundEffect = EQ(-8, 0, 2) } }
L.Choir = { Id = SRC.PING, Speed = .5, Vol = .03, Rich = true, Lfo = { .45, 6 },
	Fx = { ChorusSoundEffect = { Depth = .45, Mix = .7, Rate = 1.2 }, TremoloSoundEffect = { Frequency = .4, Depth = .5, Duty = .5 }, EqualizerSoundEffect = EQ(2, 3, -12) } }
L.ChoirThird = { Id = SRC.PING, Speed = .5 * 2 ^ (3 / 12), Vol = .022, Rich = true, Lfo = { .5, 8 },
	Fx = { ChorusSoundEffect = { Depth = .5, Mix = .7, Rate = .9 }, TremoloSoundEffect = { Frequency = .33, Depth = .5, Duty = .5 }, EqualizerSoundEffect = EQ(2, 3, -12) } }
L.Low = { Id = SRC.WIND, Speed = .3, Vol = .06, Lfo = { .3, 5 }, Fx = { EqualizerSoundEffect = EQ(10, -6, -30) } }
L.BossDrone = { Id = SRC.PING, Speed = .33, Vol = .05, Rich = true, Lfo = { .2, 4 },
	Fx = { TremoloSoundEffect = { Frequency = 6, Depth = .35, Duty = .5 }, DistortionSoundEffect = { Level = .3 }, EqualizerSoundEffect = EQ(8, -2, -16) } }

---------------------------------------------------------------------------------------------------------------------
-- Themes. Notes = {beat, semitone (A = 0), length in beats, velocity}.
---------------------------------------------------------------------------------------------------------------------
local MELODY = { -- A harmonic minor waltz, 16 bars of 3/4 (A A' / B)
	{ 0, 0, 1, .8 }, { 1, 3, 1, .6 }, { 2, 7, 1, .6 }, { 3, 5, 1, .7 }, { 4, 3, 1, .6 }, { 5, 2, 1, .6 }, { 6, 3, 1, .7 }, { 7, 0, 1, .6 },
	{ 8, -5, 1, .6 }, { 9, -1, 2, .8 }, { 11, 2, 1, .5 }, { 12, 0, 1, .8 }, { 13, 3, 1, .6 }, { 14, 7, 1, .6 }, { 15, 8, 1, .8 },
	{ 16, 7, 1, .6 }, { 17, 5, 1, .6 }, { 18, 3, 1, .7 }, { 19, 2, 1, .6 }, { 20, -1, 1, .7 }, { 21, 0, 3, .9 },
	{ 24, 12, 1, .7 }, { 25, 11, 1, .6 }, { 26, 8, 1, .6 }, { 27, 7, 2, .75 }, { 29, 5, 1, .5 }, { 30, 8, 1, .7 }, { 31, 7, 1, .6 },
	{ 32, 5, 1, .6 }, { 33, 3, 2, .7 }, { 35, 2, 1, .5 }, { 36, 3, 1, .7 }, { 37, 5, 1, .6 }, { 38, 7, 1, .6 }, { 39, 8, 1, .75 },
	{ 40, 11, 1, .7 }, { 41, 12, 1, .8 }, { 42, 11, 1, .6 }, { 43, 8, 1, .6 }, { 44, 7, 1, .6 }, { 45, -1, 1, .7 }, { 46, 0, 2, .85 },
}
local BASS = {
	{ 0, -24, 3, .9 }, { 3, -19, 3, .8 }, { 6, -24, 3, .8 }, { 9, -17, 3, .85 }, { 12, -24, 3, .9 }, { 15, -16, 3, .8 }, { 18, -17, 3, .8 }, { 21, -24, 3, .9 },
	{ 24, -16, 3, .85 }, { 27, -17, 3, .8 }, { 30, -19, 3, .8 }, { 33, -21, 3, .8 }, { 36, -19, 3, .8 }, { 39, -16, 3, .85 }, { 42, -17, 3, .85 }, { 45, -24, 3, .9 },
}
local function pick(notes, fn)
	local out = {}
	for _, n in ipairs(notes) do
		local r = fn(n)
		if r then
			table.insert(out, r)
		end
	end
	table.sort(out, function(a, b)
		return a[1] < b[1]
	end)
	return out
end
local function grid(beats, step, fn)
	local out = {}
	local i = 0
	local b = 0
	while b < beats - 1e-6 do
		local n = fn(i, b)
		if n then
			table.insert(out, n)
		end
		i += 1
		b = i * step
	end
	return out
end
local OCTAVE = pick(MELODY, function(n)
	local bar = math.floor(n[1] / 3)
	if (bar >= 4 and bar <= 7) or bar >= 12 then
		return { n[1], n[2] + 12, n[3], n[4] * .45 }
	end
	return nil
end)
local WALTZ_HEART = grid(48, 3, function(i, b)
	return { b, 0, 1, (i % 4 == 0) and .85 or .6 }
end)
local WALTZ_CLOCK = grid(48, 1, function(i, b)
	if i % 3 == 0 then
		return nil
	end
	return { b, (i % 3 == 1) and 0 or 5, .5, .5 }
end)

-- Blood Moon warning: heartbeat ("lub-dub") accelerating 0.9 s -> 0.5 s over the 30 s warning (Bpm 60: beat = second)
local WARN_HEART = {}
do
	local t = 0
	local span = (Config.BloodMoon and Config.BloodMoon.Warning) or 30
	while t < span + 1.5 do
		local k = math.clamp(t / span, 0, 1)
		local vel = .55 + .4 * k
		table.insert(WARN_HEART, { t, 0, .3, vel })
		table.insert(WARN_HEART, { t + .18, 0, .3, vel * .7 })
		t += .9 + (.5 - .9) * k
	end
	table.sort(WARN_HEART, function(a, b)
		return a[1] < b[1]
	end)
end

-- Blood Moon: 104 BPM 4/4 ostinato in 8ths, the tritone (6) carries the dread; harmony A / F / D / E every 2 bars
local OST_PAT = { 0, 3, 0, 6, 0, 3, 2, -1 }
local OST_SHIFT = { 0, 0, -4, -4, -7, -7, -5, -5 }
local BM_OST = grid(32, .5, function(i, b)
	local bar = math.floor(b / 4)
	local vel = (i % 8 == 0) and .85 or (i % 2 == 0) and .62 or .5
	return { b, -12 + OST_PAT[i % 8 + 1] + OST_SHIFT[bar + 1], .5, vel }
end)
local BM_BELL = { { 0, 0, 4, .9 }, { 0, -12, 4, .45 }, { 8, 0, 4, .8 }, { 16, 0, 4, .9 }, { 16, -12, 4, .45 }, { 24, 0, 4, .8 } }
local BM_HIT = grid(32, 4, function(i, b)
	return { b, 0, 1, (i % 2 == 0) and .85 or .7 }
end)
table.insert(BM_HIT, { 30.5, 0, 1, .6 })
local BM_LEAD = { { 16, 12, 1, .6 }, { 17, 11, 1, .5 }, { 18, 8, 1, .5 }, { 19, 7, 2, .6 }, { 22, 6, 2, .7 },
	{ 24, 12, 1, .6 }, { 25, 11, 1, .5 }, { 26, 8, 1, .5 }, { 27, 5, 2, .6 }, { 30, -1, 2, .65 } }
local BM_SNARE = grid(32, 2, function(_, b)
	if b < 16 then
		return nil
	end
	return { b + 1, 0, .5, .5 }
end)

-- Boss (THE GRAVEKEEPER): 120 BPM, D phrygian 8th ostinato, timpani hits, snares, stabs; "Enrage" layer at phase 5
local BOSS_PAT = { 0, 1, 0, 3, 0, 1, 5, 3 }
local BOSS_SHIFT = { 0, 0, 1, 1, -2, -2, 0, 0 }
local BOSS_OST = grid(32, .5, function(i, b)
	local bar = math.floor(b / 4)
	return { b, -19 + BOSS_PAT[i % 8 + 1] + BOSS_SHIFT[bar + 1], .5, (i % 4 == 0) and .8 or .55 }
end)
local BOSS_HIT = {}
for bar = 0, 7 do
	table.insert(BOSS_HIT, { bar * 4, 0, 1, .85 })
	table.insert(BOSS_HIT, { bar * 4 + 1.5, 0, 1, .55 })
	table.insert(BOSS_HIT, { bar * 4 + 2, 0, 1, .7 })
end
local BOSS_SNARE = {}
for bar = 0, 7 do
	table.insert(BOSS_SNARE, { bar * 4 + 1, 0, .5, .55 })
	table.insert(BOSS_SNARE, { bar * 4 + 3, 0, .5, .6 })
	if bar % 4 == 3 then
		table.insert(BOSS_SNARE, { bar * 4 + 3.5, 0, .25, .3 })
	end
end
table.sort(BOSS_SNARE, function(a, b)
	return a[1] < b[1]
end)
local BOSS_STAB = { { 0, -7, 1, .7 }, { 8, -6, 1, .7 }, { 16, -9, 1, .7 }, { 24, -7, 1, .7 }, { 30, -1, 1.5, .8 } }
local BOSS_ALARM = grid(32, 1, function(i, b)
	return { b, (i % 2 == 0) and 0 or 6, .5, (i % 4 == 0) and .8 or .55 }
end)
local BOSS_ENRAGE_HIT = grid(32, 1, function(i, b)
	if i % 4 == 0 then
		return nil
	end
	return { b, 0, .5, .45 }
end)

local T = {}
Music.Themes = T
T.NIGHT = { Bpm = 72, Beats = 48, Upload = "OstAssetId", Parts = {
	{ Inst = "Box", Notes = MELODY, Priority = 1 },
	{ Inst = "Bass", Notes = BASS, Priority = 2 },
}, Loops = { "Wind" } }
T.ZONE = { Bpm = 84, Beats = 48, Upload = "OstAssetId", Parts = {
	{ Inst = "Box", Notes = MELODY, Priority = 1 },
	{ Inst = "Bass", Notes = BASS, Priority = 2 },
	{ Inst = "Box", Notes = OCTAVE, Rich = true },
	{ Inst = "Heart", Notes = WALTZ_HEART, Priority = 2 },
	{ Inst = "Clock", Notes = WALTZ_CLOCK },
}, Loops = { "Drone", "DroneFifth" } }
T.BLOOD_WARN = { Bpm = 60, Beats = 34, NoLoop = true, Parts = {
	{ Inst = "Heart", Notes = WARN_HEART, Priority = 1 },
}, Loops = { "Rumble", "Tension" } }
T.BLOOD_MOON = { Bpm = 104, Beats = 32, Upload = "BloodMoonAssetId", Parts = {
	{ Inst = "Ost", Notes = BM_OST, Priority = 1 },
	{ Inst = "Bell", Notes = BM_BELL, Priority = 1 },
	{ Inst = "Hit", Notes = BM_HIT, Priority = 2 },
	{ Inst = "Box", Notes = BM_LEAD },
	{ Inst = "Snare", Notes = BM_SNARE },
}, Loops = { "Choir", "ChoirThird", "Low" } }
T.BOSS = { Bpm = 120, Beats = 32, Parts = {
	{ Inst = "Ost", Notes = BOSS_OST, Priority = 1 },
	{ Inst = "Hit", Notes = BOSS_HIT, Priority = 1 },
	{ Inst = "Snare", Notes = BOSS_SNARE, Priority = 2 },
	{ Inst = "Stab", Notes = BOSS_STAB, Priority = 2 },
	{ Inst = "Alarm", Notes = BOSS_ALARM, Layer = "Enrage" },
	{ Inst = "Hit", Notes = BOSS_ENRAGE_HIT, Layer = "Enrage" },
}, Loops = { "BossDrone", "Low" } }

---------------------------------------------------------------------------------------------------------------------
-- Pure sequencer: one Player per theme (gain ramp + note cursors on a shared musical clock)
---------------------------------------------------------------------------------------------------------------------
local Player = {}
Player.__index = Player
Music.Player = Player

function Player.new(name: string, theme)
	return setmetatable({ Name = name, Theme = theme, Gain = 0, Target = 0, Fade = 3, Origin = nil, Cursors = {}, Layers = {},
		Started = 0 }, Player)
end

-- (re)start the musical clock so that `elapsed` seconds of the theme have already passed at `now`
function Player:Begin(now: number, elapsed: number?)
	-- the clock starts one look-ahead in the future, so even the first note is scheduled ahead like every other one
	self.Origin = now + Music.LOOKAHEAD - (elapsed or 0)
	self.Started += 1
	local spb = 60 / self.Theme.Bpm
	for pi, part in ipairs(self.Theme.Parts) do
		local c = { I = 1, Loop = 0 }
		-- skip notes that are already in the past (anchored start): never play a burst of old notes
		while part.Notes[c.I] and self.Origin + part.Notes[c.I][1] * spb < now - Music.LATE do
			c.I += 1
		end
		if not part.Notes[c.I] then
			c.I, c.Loop = 1, self.Theme.NoLoop and math.huge or 1
		end
		self.Cursors[pi] = c
	end
end

function Player:PartGain(part): number
	if part.Layer then
		return self.Layers[part.Layer] or 0
	end
	return 1
end

-- advance: ramps Gain toward Target (linear, `Fade` seconds for 0<->1) and emits every note whose time falls inside
-- [now - LATE, now + LOOKAHEAD]. emit(player, part, note, at). Returns false when silent and idle.
function Player:Step(now: number, dt: number, emit)
	local rate = dt / math.max(.05, self.Fade)
	if self.Gain < self.Target then
		self.Gain = math.min(self.Target, self.Gain + rate)
	elseif self.Gain > self.Target then
		self.Gain = math.max(self.Target, self.Gain - rate)
	end
	if self.Gain <= 0 and self.Target <= 0 then
		self.Origin = nil
		return false
	end
	if not self.Origin then
		self:Begin(now, self.PendingElapsed)
		self.PendingElapsed = nil
	end
	local theme = self.Theme
	local spb = 60 / theme.Bpm
	local loopBeats = theme.Beats
	for pi, part in ipairs(theme.Parts) do
		local c = self.Cursors[pi]
		local notes = part.Notes
		if c and #notes > 0 and c.Loop ~= math.huge then
			local guard = 0
			while guard < 256 do
				guard += 1
				local n = notes[c.I]
				local at = self.Origin + (c.Loop * loopBeats + n[1]) * spb
				if at > now + Music.LOOKAHEAD then
					break
				end
				if at < now - loopBeats * spb then -- a long hitch: jump whole loops instead of walking them
					if theme.NoLoop then
						c.Loop = math.huge
						break
					end
					local skip = math.floor((now - at) / (loopBeats * spb))
					c.Loop += math.max(1, skip)
					continue
				end
				if at >= now - Music.LATE then
					emit(self, part, n, at)
				end
				c.I += 1
				if c.I > #notes then
					c.I = 1
					c.Loop = theme.NoLoop and math.huge or c.Loop + 1
					if c.Loop == math.huge then
						break
					end
				end
			end
		end
	end
	return true
end

-- equal-power crossfade curve applied to the voices
function Music.Amp(gain: number): number
	return math.sin(math.clamp(gain, 0, 1) * math.pi / 2)
end

-- pure voice gate: may a note of `priority` start now? (active = number of sounding voices)
function Music.Gate(active: number, cap: number, priority: number?): boolean
	if active < cap then
		return true
	end
	-- melody / ostinato may use 2 reserve voices (they steal the oldest pooled voice); everything else drops at the cap
	return priority == 1 and active < cap + 2
end

---------------------------------------------------------------------------------------------------------------------
-- Runtime (voices, loops, uploads)
---------------------------------------------------------------------------------------------------------------------
local players = {}
for name, theme in pairs(T) do
	players[name] = Player.new(name, theme)
end
Music.Players = players
local state = { Theme = nil, Master = 1, MasterTarget = 1, Started = false, Conn = nil, Voices = {}, Pools = {}, Loops = {},
	Uploads = {}, Folder = nil, Group = nil, Tails = {} }
Music.State = state

local function quality(): string
	if not Shared then
		local ok, s = pcall(function()
			return require(root:WaitForChild("Shared"))
		end)
		Shared = ok and s or false
	end
	if Shared then
		local ok, q = pcall(Shared.Quality)
		if ok and type(q) == "string" then
			return q
		end
	end
	return "High"
end
local lowCache, lowAt = false, -10
local function isLow(): boolean
	local now = os.clock()
	if now - lowAt > 2 then
		lowAt = now
		lowCache = quality() == "Low"
	end
	return lowCache
end
Music.IsLow = isLow

local function tail(name: string?): SoundGroup
	local g = state.Group
	if not name then
		return g
	end
	local t = state.Tails[name]
	if t and t.Parent == g then
		return t
	end
	t = Instance.new("SoundGroup")
	t.Name = "HalloweenMusic" .. name
	t.Volume = 1
	local r = Instance.new("ReverbSoundEffect")
	if name == "Crypt" then
		r.DecayTime, r.WetLevel, r.DryLevel = 6, 0, -4
	else
		r.DecayTime, r.WetLevel, r.DryLevel = 3.2, -4, -1
	end
	r.Density, r.Diffusion = 1, 1
	r.Parent = t
	t.Parent = g
	state.Tails[name] = t
	return t
end

local function newSound(id: string, fx, group: SoundGroup, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = "HalloweenMusicVoice"
	s.SoundId = id
	s.Volume = 0
	s.Looped = looped
	for class, props in pairs(fx or {}) do
		local e = Instance.new(class)
		for k, v in pairs(props) do
			(e :: any)[k] = v
		end
		e.Parent = s
	end
	s.SoundGroup = group
	s.Parent = state.Folder
	return s
end

local function pool(instName: string)
	local p = state.Pools[instName]
	if p then
		return p
	end
	local def = I[instName]
	p = { Def = def, Voices = {}, Next = 1 }
	for i = 1, def.Pool or 2 do
		p.Voices[i] = { Sound = newSound(def.Id, def.Fx, tail(def.Tail), false), EndAt = 0, Token = 0 }
	end
	state.Pools[instName] = p
	return p
end

local function activeVoices(now: number): number
	local n = 0
	for _, p in pairs(state.Pools) do
		for _, v in ipairs(p.Voices) do
			if v.EndAt > now then
				n += 1
			end
		end
	end
	for _, lp in pairs(state.Loops) do
		if lp.Sound.IsPlaying and lp.Sound.Volume > .002 then
			n += 1
		end
	end
	return n
end

local function sound(instName: string, semi: number, volume: number, len: number?)
	local p = pool(instName)
	local def = p.Def
	local v = p.Voices[p.Next]
	p.Next = p.Next % #p.Voices + 1
	local s = v.Sound
	v.Token += 1
	local token = v.Token
	if v.Tween then
		v.Tween:Cancel()
		v.Tween = nil
	end
	local speed = def.Speed * 2 ^ (semi / 12) * (def.Melodic and Music.ROOT or 1)
	s.PlaybackSpeed = math.clamp(speed, .05, 8)
	s.Volume = math.clamp(volume, 0, 1.5)
	s.TimePosition = 0
	s:Play()
	local dur = math.min(def.Dur, math.max(def.Fade + .05, (len or def.Dur) + def.Fade))
	v.EndAt = os.clock() + dur
	task.delay(math.max(0, dur - def.Fade), function()
		if v.Token ~= token or not s.Parent then
			return
		end
		v.Tween = TweenService:Create(s, TweenInfo.new(def.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 })
		v.Tween:Play()
		task.delay(def.Fade + .02, function()
			if v.Token == token and s.Parent then
				s:Stop()
			end
		end)
	end)
end

local function cap(): number
	return Music.Cap[quality()] or 12
end

-- emit callback of the runtime players: schedules the note on its pooled voice
local function emit(player, part, note, at)
	if part.Rich and isLow() then
		return
	end
	local layerGain = player:PartGain(part)
	if layerGain <= .01 then
		return
	end
	local def = I[part.Inst]
	if not def then
		return
	end
	local amp = Music.Amp(player.Gain) * layerGain * state.Master * (Config.Music.Volume or .5) * 2
	if amp <= .005 then
		return
	end
	local now = os.clock()
	if not Music.Gate(activeVoices(now), cap(), part.Priority) then
		return
	end
	local spb = 60 / player.Theme.Bpm
	local vol = def.Volume * (note[4] or .7) * amp
	local function go()
		sound(part.Inst, note[2] or 0, vol, (note[3] or 1) * spb)
		if def.Pluck and not isLow() then
			sound(def.Pluck, note[2] or 0, I[def.Pluck].Volume * (note[4] or .7) * amp)
		end
	end
	local delay = at - (player.ClockNow or now)
	if delay > .005 then
		task.delay(delay, go)
	else
		go()
	end
end

local function loopValue(v, k: number): number
	if type(v) == "table" then
		return v[1] + (v[2] - v[1]) * math.clamp(k, 0, 1)
	end
	return v
end

local function updateLoops(name: string, player, clock: number, silent: boolean?)
	local theme = player.Theme
	local live = state.Loops
	local low = isLow()
	for _, loopName in ipairs(theme.Loops or {}) do
		local key = name .. ":" .. loopName
		local def = L[loopName]
		local lp = live[key]
		local amp = Music.Amp(player.Gain) * state.Master * (Config.Music.Volume or .5) * 2
		local want = def and not silent and player.Gain > 0 and not (def.Rich and low) and amp > .002
		if want and not lp then
			lp = { Sound = newSound(def.Id, def.Fx, state.Group, true), Def = def, Phase = math.random() * 6 }
			lp.Sound:Play()
			live[key] = lp
		end
		if lp then
			if not want then
				lp.Sound:Stop()
				lp.Sound:Destroy()
				live[key] = nil
			else
				local elapsed = player.Origin and (clock - player.Origin) or 0
				local k = def.Ramp and elapsed / def.Ramp or 0
				local lfo = 1
				if def.Lfo then
					lfo = 1 - def.Lfo[1] * (.5 + .5 * math.sin((clock + lp.Phase) * math.pi * 2 / def.Lfo[2]))
				end
				local vol = loopValue(def.Vol, k) * lfo * amp
				if math.abs(lp.Sound.Volume - vol) > .0005 then
					lp.Sound.Volume = vol
				end
				local sp = math.clamp(loopValue(def.Speed, k), .05, 8)
				if math.abs(lp.Sound.PlaybackSpeed - sp) > .001 then
					lp.Sound.PlaybackSpeed = sp
				end
			end
		end
	end
end

-- uploaded track per theme (optional): "pending" until audible, "failed" after 8 s -> procedural
local function upload(name: string, player, clock: number): boolean
	local key = player.Theme.Upload
	local id = key and Config.Music[key]
	if type(id) ~= "number" or id <= 0 then
		return false
	end
	local u = state.Uploads[key]
	if not u then
		u = { Sound = newSound("rbxassetid://" .. math.floor(id), nil, state.Group, true), Since = clock, Status = "Pending" }
		u.Sound:Play()
		state.Uploads[key] = u
	end
	if u.Status == "Pending" then
		if u.Sound.IsLoaded and u.Sound.TimeLength > 0 then
			u.Status = "Ok"
		elseif clock - u.Since > 8 then
			u.Status = "Failed"
			u.Sound:Stop()
		end
	end
	if u.Status ~= "Ok" then
		return false
	end
	if not u.Sound.IsPlaying then
		u.Sound:Play()
	end
	u.Owner = name
	return true
end

local function step(dt: number)
	local clock = os.clock()
	-- master smoothing (1.5 s)
	local mrate = dt / 1.5
	if state.Master < state.MasterTarget then
		state.Master = math.min(state.MasterTarget, state.Master + mrate)
	elseif state.Master > state.MasterTarget then
		state.Master = math.max(state.MasterTarget, state.Master - mrate)
	end
	local uploadGain = {}
	for name, player in pairs(players) do
		player.ClockNow = clock
		local usesUpload = player.Gain > 0 and upload(name, player, clock) or false
		if usesUpload then
			local key = player.Theme.Upload
			uploadGain[key] = math.max(uploadGain[key] or 0, Music.Amp(player.Gain))
			-- keep the ramp moving without emitting notes
			player:Step(clock, dt, function() end)
		else
			player:Step(clock, dt, emit)
		end
		updateLoops(name, player, clock, usesUpload)
	end
	for key, u in pairs(state.Uploads) do
		if u.Status == "Ok" then
			local v = (uploadGain[key] or 0) * state.Master * Music.UploadVolume * (Config.Music.Volume or .5) * 2
			if math.abs(u.Sound.Volume - v) > .001 then
				u.Sound.Volume = v
			end
		end
	end
end
Music.Step = step

function Music.Start()
	if state.Started then
		return
	end
	state.Started = true
	local f = SoundService:FindFirstChild("DOGROTS_HalloweenMusic")
	if not f then
		f = Instance.new("Folder")
		f.Name = "DOGROTS_HalloweenMusic"
		f.Parent = SoundService
	end
	state.Folder = f
	state.Group = Audio.Group("Music")
	state.Conn = RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not state.Warned then
			state.Warned = true
			warn("Halloween Music step failed: " .. tostring(err))
		end
	end)
end

function Music.SetTheme(name: string?, opts: { [string]: any }?)
	opts = opts or {}
	local fade = opts.Fade or Config.Music.Crossfade or 3
	if name ~= nil and not players[name] then
		warn("Halloween Music: unknown theme " .. tostring(name))
		name = nil
	end
	if name == state.Theme and opts.Elapsed == nil then
		return
	end
	state.Theme = name
	for n, p in pairs(players) do
		p.Fade = fade
		if n == name then
			p.Target = 1
			if opts.Elapsed ~= nil and (p.Origin == nil or p.Gain <= 0) then
				p.Origin = nil
				p.PendingElapsed = opts.Elapsed
			end
		else
			p.Target = 0
		end
	end
end

function Music.Theme(): string?
	return state.Theme
end

function Music.SetLayer(theme: string, layer: string, gain: number)
	local p = players[theme]
	if p then
		p.Layers[layer] = math.clamp(gain or 0, 0, 1)
	end
end

function Music.SetMaster(v: number)
	state.MasterTarget = math.clamp(v or 0, 0, 1)
end

function Music.Stop(fade: number?)
	Music.SetTheme(nil, { Fade = fade or 2 })
	task.delay((fade or 2) + .3, function()
		if state.Theme ~= nil or not state.Started then
			return
		end
		if state.Conn then
			state.Conn:Disconnect()
			state.Conn = nil
		end
		state.Started = false
		for _, lp in pairs(state.Loops) do
			lp.Sound:Destroy()
		end
		table.clear(state.Loops)
		for _, u in pairs(state.Uploads) do
			u.Sound:Destroy()
		end
		table.clear(state.Uploads)
		for _, p in pairs(state.Pools) do
			for _, v in ipairs(p.Voices) do
				v.Token += 1
				v.Sound:Destroy()
			end
		end
		table.clear(state.Pools)
		for _, p in pairs(players) do
			p.Gain, p.Target, p.Origin = 0, 0, nil
		end
	end)
end

function Music.Snapshot()
	local gains = {}
	for n, p in pairs(players) do
		gains[n] = p.Gain
	end
	local uploads = {}
	for k, u in pairs(state.Uploads) do
		uploads[k] = u.Status
	end
	return { Theme = state.Theme, Gains = gains, Voices = state.Started and activeVoices(os.clock()) or 0, Master = state.Master,
		Uploads = uploads }
end

return Music
