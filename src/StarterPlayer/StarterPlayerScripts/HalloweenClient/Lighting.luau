-- NIGHT OF THE BURIED MOON — the one Halloween lighting writer (StarterPlayerScripts.HalloweenClient.Lighting). WP10a.
--
-- Priority layers, composited every frame just before rendering (RenderStep First+1, after Mega's Context:Sky):
--   NIGHT 10        subtle Halloween night tint everywhere while the server's day cycle says night (Lighting.DayFactor)
--   ZONE 20         THE DEAD YARD profile (camera inside the yard, 44-stud feather): dark-blue/violet moonlight, soft fog,
--                   bloom for the pumpkins / lanterns, readable — never pitch black
--   BLOOD_SKY 25    outside the yard during a Blood Moon: a faint red tint only (no clock change)
--   BLOOD_MOON 30   inside the yard during a Blood Moon: red sky, thicker fog, red moonlight, contrast
--   UNDERYARD 35    [WP-H2] THE UNDERYARD (camera inside UnderyardLayout.Zone incl. Y, 40-stud feather): beneath the last
--                   bell — deep night, violet-blue cavern air, thick haze, bloom for the lanterns, no clouds / stars /
--                   built-in moon (the zone has its own moons); NIGHT / ZONE / BLOOD_* / BOSS_ENRAGE are zeroed inside
--   BOSS_ENRAGE 40  inside the yard while State.Boss.Phase == 5: redder, harder
--   MOON_HIDE 90    hides the built-in moon wherever BloodMoonFX's moon (Layout.Moon) is visible
--   FLASH 95        lightning (Lighting.Flash), + any layer pushed by other modules (Lighting.Layer)
-- Channels (drive pattern, note 07 §2.4/§7.2): Lighting {ClockTime, Brightness, ExposureCompensation, Ambient,
-- OutdoorAmbient, ColorShift_Top}, the place's own Atmosphere (never a second one), DOGROTS_BloomEffect, Terrain Clouds,
-- our client Sky DOGROTS_HalloweenSky {MoonAngularSize, StarCount}. Camera grade DOGROTS_HalloweenGrade (camera CC).
--
-- Ownership rules (nothing may stay stuck):
--   * a key is written only while some layer wants it; an external write since our last write becomes the new base, so
--     releasing restores the LIVE value (the server's 1 Hz day cycle keeps running underneath);
--   * every value we write is quantised and remembered for 15 min: when another writer that captured one of OUR values as
--     its "original" (WorldEventLighting.Begin, MineClient Mood, Mega Context:Sky, Scope:Override) later puts it back, we
--     recognise it and restore the true base — whether or not we are still driving that key;
--   * yield (release everything, keep only the camera grade at 0.6x) while a world event is ACTIVE/ENDING, while
--     WorldEventLighting.Active, while the Mine mood grade exists, or during a Secret arrival hold; the Sky channel only
--     yields to world events whose mood drives the Sky. Resume happens only inside RenderStep;
--   * [WP-H2] inside THE UNDERYARD (W.Under > .5) nothing but the Mine mood makes it yield: island world-event moods and
--     Secret arrivals never light the cavern (WorldEventLighting's DOGROTS_EventGrade is switched off locally there and
--     back on when the camera leaves);
--   * event switched off (State.Enabled false) -> everything released, grade/sky destroyed, a watcher keeps repairing
--     echoes for 15 min; zone exit / Blood Moon end -> the layer weights glide to 0 and the keys are released exactly.
-- API: Lighting.Start(ctx), Lighting.Weights() -> {Zone, Night, Blood, BloodZone, Enrage, MoonVis, Approach, Under,
--      Yielded, YieldReason}, Lighting.Flash(strength, duration), Lighting.Layer(name, profile) -> {Set(weight, fade), Remove()},
--      Lighting.Profiles (tunable), Lighting.Shutdown(), Lighting.Core / Lighting.Step / Lighting.Bind (offline tests).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LightingService = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local M = {}
local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

M.ZoneFeather = 44 -- studs outside the yard's footprint where the zone profile fades out (camera position)
M.ApproachFeather = 260 -- W.Approach: 0..1 closeness to the yard (moon size, approach effects)
M.YieldGradeScale = .6 -- camera grade strength kept while a world event / cinematic owns Lighting
M.UnderFeather = 40 -- [WP-H2] studs around UnderyardLayout.Zone (incl. Y) where the UNDERYARD profile fades out
M.UnderTau = .35 -- [WP-H2] weight glide (the portal transition hides the switch)
M.UnderInside = .5 -- [WP-H2] above this weight the camera counts as inside the Underyard (yield rules)
M.HistorySeconds = 900 -- how long our own written values are remembered (echo repair)

---------------------------------------------------------------------------------------------------------------------
-- Profiles (WorldEventLighting mood keys). Tune in Studio; see the WP10a report for the reasoning.
---------------------------------------------------------------------------------------------------------------------
M.Profiles = {
	NIGHT = { Prio = 10,
		Lighting = { Ambient = C3(98, 98, 148), OutdoorAmbient = C3(112, 112, 168), ColorShift_Top = C3(30, 34, 72) },
		Atmo = { Density = .14, Color = C3(126, 118, 170), Decay = C3(62, 50, 104), Haze = .9, Glare = 0 },
		Grade = { Tint = C3(246, 242, 255), Saturation = .03, Contrast = .04 },
		Bloom = { Intensity = .28, Size = 26, Threshold = 1.55 },
		Clouds = { Color = C3(156, 146, 200) },
		Sky = { MoonAngularSize = 14 },
	},
	ZONE = { Prio = 20,
		Lighting = { ClockTime = 23.4, Brightness = 1.45, ExposureCompensation = .24, Ambient = C3(78, 76, 126),
			OutdoorAmbient = C3(100, 98, 158), ColorShift_Top = C3(88, 100, 176) },
		Atmo = { Density = .28, Offset = .24, Color = C3(96, 90, 150), Decay = C3(40, 30, 82), Glare = 0, Haze = 1.7 },
		Grade = { Tint = C3(234, 230, 255), Saturation = .05, Contrast = .1, Brightness = .02 },
		Bloom = { Intensity = .5, Size = 28, Threshold = 1.28 },
		Clouds = { Cover = .56, Density = .34, Color = C3(72, 60, 104) },
		Sky = { StarCount = 1800 },
	},
	BLOOD_SKY = { Prio = 25,
		Atmo = { Color = C3(190, 110, 120), Decay = C3(110, 40, 52) },
		Grade = { Tint = C3(255, 214, 208), Contrast = .05 },
		Clouds = { Color = C3(170, 80, 90) },
		Sky = { MoonAngularSize = 26 },
	},
	BLOOD_MOON = { Prio = 30,
		Lighting = { ClockTime = .2, Brightness = 1.25, ExposureCompensation = .2, Ambient = C3(106, 50, 62),
			OutdoorAmbient = C3(150, 64, 76), ColorShift_Top = C3(190, 48, 44) },
		Atmo = { Density = .37, Offset = .2, Color = C3(150, 46, 58), Decay = C3(72, 12, 26), Glare = .4, Haze = 2.2 },
		Grade = { Tint = C3(255, 210, 204), Saturation = .04, Contrast = .17, Brightness = -.01 },
		Bloom = { Intensity = .62, Size = 32, Threshold = 1.12 },
		Clouds = { Cover = .66, Density = .4, Color = C3(112, 26, 36) },
		Sky = { StarCount = 700 },
	},
	BOSS_ENRAGE = { Prio = 40,
		Lighting = { ExposureCompensation = .22, Ambient = C3(112, 44, 56), OutdoorAmbient = C3(154, 58, 70), ColorShift_Top = C3(210, 52, 40) },
		Atmo = { Density = .34, Color = C3(136, 34, 44), Decay = C3(64, 8, 18), Glare = .25, Haze = 2 },
		Grade = { Tint = C3(255, 204, 198), Saturation = .07, Contrast = .2 },
		Bloom = { Intensity = .62, Size = 30, Threshold = 1.1 },
	},
	-- [WP-H2] THE UNDERYARD (DESIGN §18). Defines every key the lower layers drive, so nothing of the island leaks in.
	UNDERYARD = { Prio = 35,
		Lighting = { ClockTime = .5, Brightness = .9, ExposureCompensation = .26, Ambient = C3(52, 48, 92), OutdoorAmbient = C3(60, 58, 110),
			ColorShift_Top = C3(90, 110, 200) },
		Atmo = { Density = .32, Offset = .1, Color = C3(70, 80, 140), Decay = C3(30, 20, 60), Glare = 0, Haze = 2.4 },
		Grade = { Tint = C3(200, 210, 255), Saturation = -.15, Contrast = .12, Brightness = 0 },
		Bloom = { Intensity = .55, Size = 26, Threshold = 1.1 },
		Clouds = { Cover = 0, Density = 0, Color = C3(40, 36, 70) },
		Sky = { MoonAngularSize = 0, StarCount = 0 },
	},
	MOON_HIDE = { Prio = 90, Sky = { MoonAngularSize = 0 } },
	FLASH = { Prio = 95,
		Lighting = { Brightness = 3.4, ExposureCompensation = .7, Ambient = C3(200, 150, 160), OutdoorAmbient = C3(230, 170, 180) },
		Grade = { Tint = WHITE, Brightness = .1 },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- Core (pure: blend, quantise, channels) — exercised offline by tools/hw_test_wp10a.luau
---------------------------------------------------------------------------------------------------------------------
local Core = {}
M.Core = Core
Core.Keys = {
	Lighting = { "ClockTime", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "ColorShift_Top" },
	Atmo = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	Bloom = { "Intensity", "Size", "Threshold" },
	Clouds = { "Cover", "Density", "Color" },
	Sky = { "MoonAngularSize", "StarCount" },
}
Core.Quant = { ClockTime = .005, Brightness = .002, ExposureCompensation = .002, Density = .001, Offset = .001, Glare = .002,
	Haze = .002, Intensity = .002, Size = .05, Threshold = .002, Cover = .002, MoonAngularSize = .05, StarCount = 1 }

function Core.Smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Core.Blend(key: string, a: any, b: any, t: number): any
	if key == "ClockTime" then -- the short way round the dial
		local d = (b - a) % 24
		if d > 12 then
			d -= 24
		end
		return (a + d * t) % 24
	end
	if typeof(a) == "Color3" then
		return a:Lerp(b, t)
	end
	return a + (b - a) * t
end

-- Quantise + fingerprint: our values sit on a grid shifted by 0.37 of a step (colours: k +/- 0.37 of an 8-bit level), so a
-- value written by the server / an event (integers, presets, 1 Hz lerps) practically never equals one of ours exactly —
-- that is what makes the echo detection safe. The shift is far below anything visible.
local FP = .37
local function fpComponent(c: number): number
	local k = math.clamp(math.floor(c * 255 + .5), 0, 255)
	return (k + (k >= 255 and -FP or FP)) / 255
end
function Core.Quantize(key: string, v: any): any
	if typeof(v) == "Color3" then
		return Color3.new(fpComponent(v.R), fpComponent(v.G), fpComponent(v.B))
	elseif type(v) == "number" then
		if key == "StarCount" then
			return math.floor(v + .5)
		end
		local q = Core.Quant[key] or .001
		local r = (math.floor(v / q - FP + .5) + FP) * q
		if key == "ClockTime" then
			r %= 24
		end
		return r
	end
	return v
end

-- ClockTime arcs. "The short way round" flips sides when the base clock passes the target's antipode (11.4 h for the
-- yard's 23.4 h), which would jump a partial blend by 24*W hours. So a clock layer keeps the arc it chose (ClockArc) while
-- its weight is partial (it picks the short way again at weight 0 / 1, where the arc can't show). Only if the base drifts
-- far onto the long way (someone idling in the feather band for game hours) does the layer's clock weight (ClockWeight)
-- glide to the NEARER end — 0 below W .5, 1 above (the clock there doesn't depend on the arc) — where the arc goes back to
-- the short way, then glide back to W: the visible swing stays within |arc| * min(W, 1 - W) hours. Leaving (W -> 0) or
-- entering (W -> 1) mid-glide, or W crossing .5, unwinds the glide first, so the clock never jumps. Core.ClockStep (once
-- per frame) owns that state; Composite only reads it (layers without it: the short way).
function Core.ClockArc(a: number, b: number, prev: number?): number
	local d = (b - a) % 24
	if prev ~= nil then
		if math.abs(d - 24 - prev) < math.abs(d - prev) then
			d -= 24 -- the branch nearest the arc held so far
		end
	elseif d > 12 then
		d -= 24
	end
	return d
end
M.ClockGlide = 4 -- s: clock-weight glide while a held arc has to change sides
M.ClockHoldMax = 14 -- h: the longest arc a layer keeps holding

function Core.ClockStep(layers, base: number?, dt: number)
	local v = base
	for _, layer in ipairs(layers) do
		local t = layer.Profile.Lighting
		t = t and t.ClockTime
		if t ~= nil then
			local w = math.clamp(layer.Weight, 0, 1)
			local boost = layer.ClockBoost or 0
			if v == nil or (w <= 0 and boost <= 0) then
				layer.ClockArc, layer.ClockWeight, layer.ClockBoost, layer.ClockGlideTo = nil, nil, nil, nil
			else
				local edge = w <= 0 or w >= 1
				local short = Core.ClockArc(v, t)
				local arc = short
				if layer.ClockArc ~= nil and (boost > 0 or not edge) then
					arc = Core.ClockArc(v, t, layer.ClockArc) -- hold the arc (the switch happens only where it can't show)
				end
				local wantGlide = not edge and math.abs(arc) > M.ClockHoldMax
				if wantGlide and boost <= 0 then
					layer.ClockGlideTo = w >= .5 and 1 or 0
				end
				local toward = layer.ClockGlideTo or 1
				if wantGlide and (toward == 1) == (w >= .5) then
					boost = math.min(1, boost + dt / M.ClockGlide)
				else
					boost = math.max(0, boost - dt / M.ClockGlide) -- unwind: back to W along the held arc
				end
				local k = Core.Smooth(boost)
				local wc = toward == 1 and w + (1 - w) * k or w * (1 - k)
				if boost >= 1 then
					arc = short -- wc is exactly 0 or 1 here
				end
				layer.ClockArc, layer.ClockWeight, layer.ClockBoost = arc, wc, boost
				v = (v + arc * wc) % 24
			end
		end
	end
end

-- layers: array sorted by Prio of {Weight, Profile}; returns the quantised composite or nil if no layer wants the key
function Core.Composite(layers, channel: string, key: string, base: any): any
	local v, any = base, false
	for _, layer in ipairs(layers) do
		local w = layer.Weight
		local cw = key == "ClockTime" and layer.ClockWeight or nil -- (a clock glide still unwinding after W reached 0)
		if w > 0 or (cw and cw > 0) then
			local t = layer.Profile[channel]
			t = t and t[key]
			if t ~= nil and base ~= nil then
				if key == "ClockTime" then
					v = (v + Core.ClockArc(v, t, layer.ClockArc) * (cw or math.min(1, w))) % 24
				else
					v = Core.Blend(key, v, t, math.min(1, w))
				end
				any = true
			end
		end
	end
	if not any then
		return nil
	end
	return Core.Quantize(key, v)
end

-- camera grade composite (neutral = white / 0)
function Core.Grade(layers, scaleFor)
	local tint, sat, con, bri, total = WHITE, 0, 0, 0, 0
	for _, layer in ipairs(layers) do
		local g = layer.Profile.Grade
		local w = layer.Weight * (scaleFor and scaleFor(layer) or 1)
		if g and w > 0 then
			w = math.min(1, w)
			tint = tint:Lerp(g.Tint or WHITE, w)
			sat += ((g.Saturation or 0) - sat) * w
			con += ((g.Contrast or 0) - con) * w
			bri += ((g.Brightness or 0) - bri) * w
			total = math.max(total, w)
		end
	end
	return tint, sat, con, bri, total
end

-- Roblox stores these properties as float32: a double composite never equals its read-back exactly, so compare with a
-- tolerance far below the quantisation steps (otherwise every key would be rewritten every frame)
function Core.Same(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= 1e-5 * math.max(1, math.abs(a))
	end
	return a == b
end
local same = Core.Same

local function hkey(v: any): any
	if typeof(v) == "Color3" then
		return string.format("%.5f|%.5f|%.5f", v.R, v.G, v.B)
	end
	return v
end
Core.HKey = hkey

local Channel = {}
Channel.__index = Channel
Core.Channel = Channel

function Channel.new(name: string, object: any, keys: { string })
	return setmetatable({ Name = name, Object = object, Keys = keys, Base = {}, Written = {}, History = {}, Count = 0,
		Yielded = false, Ext = {}, PreBase = {}, Fights = 0 }, Channel)
end

function Channel:Ours(k: string, v: any): boolean
	local h = self.History[k]
	return h ~= nil and v ~= nil and h[hkey(v)] ~= nil and v ~= self.Base[k]
end

function Channel:Remember(k: string, v: any, now: number)
	if v == nil or v == self.Base[k] then
		return
	end
	local h = self.History[k]
	if not h then
		h = {}
		self.History[k] = h
	end
	local key = hkey(v)
	if h[key] == nil then
		self.Count += 1
	end
	h[key] = now
end

function Channel:Prune(now: number, keep: number)
	for _, h in pairs(self.History) do
		for key, t in pairs(h) do
			if now - t > keep then
				h[key] = nil
				self.Count -= 1
			end
		end
	end
end

-- one frame in which we may write. targetFn(key, base) -> composite or nil (= not ours this frame).
-- External writes while we drive: an isolated one (the server's 1 Hz day cycle) becomes the new base; a rapid run (3 writes
-- less than .6 s apart: a tween / per-frame writer we were not told about) never does — the pre-run base is kept, so a
-- fight can't leave its values behind as "ours".
Channel.RunGap = .6
function Channel:Drive(targetFn, now: number)
	local o = self.Object
	self.Yielded = false
	for _, k in ipairs(self.Keys) do
		local cur = o[k]
		local w = self.Written[k]
		local echo = false
		if w == nil or cur ~= w then
			if self:Ours(k, cur) then
				echo = true -- one of OUR old values came back: keep the true base
			elseif w ~= nil then
				local t = self.Ext[k]
				if not t then
					t = {}
					self.Ext[k] = t
				end
				local last = t[#t]
				if not last or now - last > Channel.RunGap then
					self.PreBase[k] = self.Base[k]
					table.clear(t)
				end
				table.insert(t, now)
				if #t > 3 then
					table.remove(t, 1)
				end
				if #t >= 3 then
					self.Base[k] = self.PreBase[k] -- a fight: keep the base from before it started
					self.Fights += 1
				else
					self.Base[k] = cur
				end
			else
				self.Base[k] = cur -- not driving: follow the live value
			end
		end
		local base = self.Base[k]
		local v = base ~= nil and targetFn(k, base) or nil
		if v ~= nil then
			if not same(v, cur) then
				o[k] = v
				self:Remember(k, o[k], now)
			end
			self.Written[k] = o[k]
		else
			if echo and base ~= nil then
				o[k] = base -- repair
			elseif w ~= nil and cur == w then
				o[k] = base -- release: still ours -> the live base comes back
			end
			self.Written[k] = nil
		end
	end
end

-- hand everything back (restore only what is still ours) and stop touching the object until the next Drive
function Channel:Yield()
	if self.Yielded then
		return
	end
	self.Yielded = true
	for k, w in pairs(self.Written) do
		if self.Object[k] == w and self.Base[k] ~= nil then
			self.Object[k] = self.Base[k]
		end
	end
	table.clear(self.Written)
end

function Channel:Driving(): boolean
	return next(self.Written) ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------
local W = { Zone = 0, Night = 0, Blood = 0, BloodZone = 0, Enrage = 0, MoonVis = 0, Approach = 0, Flash = 0, ShownDark = 0,
	Under = 0, Yielded = false, YieldReason = nil, Active = false }
M.W = W
local layers = {} -- {Name, Prio, Profile, Weight, Target?, Rate?}
local layerByName = {}
local channels = {} -- name -> Channel
local objects = {} -- name -> object (bound)
local grade = nil -- camera ColorCorrectionEffect
local ownSky = nil
local ctxRef = nil
local Layout = nil
local Shared = nil
local Under: any = nil -- [WP-H2] RS.Halloween.UnderyardRuntime (UnderWeight); nil in a place without Chapter II
local flash = { T = 0, Dur = 0, Strength = 0, Second = false }
local lastPrune = 0
local janitorUntil = 0

local function addLayer(name: string, profile)
	local l = layerByName[name]
	if l then
		l.Profile = profile
		return l
	end
	l = { Name = name, Prio = profile.Prio or 50, Profile = profile, Weight = 0 }
	layerByName[name] = l
	table.insert(layers, l)
	table.sort(layers, function(a, b)
		return a.Prio < b.Prio
	end)
	return l
end
for name, p in pairs(M.Profiles) do
	addLayer(name, p)
end

local function smoothTo(cur: number, target: number, dt: number, tau: number): number
	local v = cur + (target - cur) * (1 - math.exp(-dt / math.max(.01, tau)))
	if math.abs(v - target) < .002 then
		v = target
	end
	return v
end

-- server day factor -> night weight (full night at DayFactor <= .05, none from .5)
function Core.NightTarget(day: number): number
	return 1 - Core.Smooth((day - .05) / .45)
end
-- darkness of a displayed ClockTime (same curve as the server's day cycle)
function Core.Dark(clock: number): number
	local day = math.clamp((math.cos((clock - 13) * math.pi / 12) + .2) * 1.2, 0, 1)
	return Core.NightTarget(day)
end

---------------------------------------------------------------------------------------------------------------------
-- Step: weights from the sensed world, then channels. s = {Now, Clock, CamPos, DayFactor, ActualClock, BloodAlpha,
-- Enraged, YieldAll, YieldReason, YieldSky, Enabled, ReducedMotion}
---------------------------------------------------------------------------------------------------------------------
local function layerWeights(dt: number, s)
	local zoneT = (s.CamPos and Layout) and Layout.Weight(s.CamPos, M.ZoneFeather) or 0
	W.Zone = smoothTo(W.Zone, zoneT, dt, .6)
	local day = s.DayFactor
	W.Night = smoothTo(W.Night, day and Core.NightTarget(day) or 0, dt, 2)
	W.Blood = math.clamp(s.BloodAlpha or 0, 0, 1)
	W.Enrage = smoothTo(W.Enrage, s.Enraged and 1 or 0, dt, 1.2)
	W.Approach = (s.CamPos and Layout) and Layout.Weight(s.CamPos, M.ApproachFeather) or 0
	-- [WP-H2] THE UNDERYARD: its own weight (Y counts); every island layer is zeroed inside it
	local underT = (s.CamPos and Under) and Under.UnderWeight(s.CamPos, M.UnderFeather) or 0
	W.Under = smoothTo(W.Under, underT, dt, M.UnderTau)
	local outside = 1 - W.Under
	W.BloodZone = W.Blood * W.Zone
	-- flash envelope
	local fw = 0
	if flash.Dur > 0 then
		flash.T += dt
		local t = flash.T / flash.Dur
		if t >= 1 then
			flash.Dur = 0
		else
			fw = (t < .08 and t / .08 or (1 - (t - .08) / .92) ^ 2) * flash.Strength
			if flash.Second and t > .22 and t < .32 then
				fw = math.max(fw, flash.Strength * .7)
			end
		end
	end
	W.Flash = fw
	layerByName.NIGHT.Weight = W.Night * outside
	layerByName.ZONE.Weight = W.Zone * outside
	layerByName.BLOOD_SKY.Weight = W.Blood * (1 - W.Zone) * .35 * outside
	layerByName.BLOOD_MOON.Weight = W.BloodZone * outside
	layerByName.BOSS_ENRAGE.Weight = W.Enrage * W.Zone * outside
	layerByName.UNDERYARD.Weight = W.Under
	layerByName.FLASH.Weight = fw
	-- the Buried Moon (BloodMoonFX) replaces the built-in moon wherever the DISPLAYED sky is dark: the clock we are about
	-- to render (our composite), not the property (the server's 1 Hz replication overwrites it between our frames).
	-- BloodMoonFX scales it by W.Approach; fixed direction = no parallax, so both moons are never visible together.
	local shown = s.ActualClock or 0
	if not s.YieldAll then
		local ch = channels.Lighting
		local base = ch and ch.Base.ClockTime or shown
		Core.ClockStep(layers, base, dt)
		local v = Core.Composite(layers, "Lighting", "ClockTime", base)
		if v ~= nil then
			shown = v
		end
	else
		Core.ClockStep(layers, nil, dt) -- not driving the clock: the arcs start afresh
	end
	W.ShownDark = Core.Dark(shown)
	local moonT = W.ShownDark
	if s.YieldSky then
		moonT = 0 -- a world-event mood owns the sky (its own moon)
	end
	W.MoonVis = smoothTo(W.MoonVis, moonT, dt, .5)
	layerByName.MOON_HIDE.Weight = W.MoonVis
	for i = #layers, 1, -1 do
		local l = layers[i]
		if l.Target ~= nil then -- pushed layers (Lighting.Layer)
			local rate = dt / math.max(.05, l.Fade or 1)
			if l.Weight < l.Target then
				l.Weight = math.min(l.Target, l.Weight + rate)
			else
				l.Weight = math.max(l.Target, l.Weight - rate)
			end
			if l.Remove and l.Weight <= 0 then
				layerByName[l.Name] = nil
				table.remove(layers, i)
			end
		end
	end
end

local function wantsSky(): boolean
	for _, l in ipairs(layers) do
		if l.Weight > 0 and l.Profile.Sky then
			return true
		end
	end
	return false
end

-- Our client Sky (the place ships without one; a Sky object visibly changes the daytime skybox): created only while the
-- displayed sky is dark and a Sky layer wants it, removed again (Sky channel released first) once no layer wants it or
-- the displayed sky turns light, so the place is left exactly as it was. Never while a world-event mood drives the sky.
M.SkyDarkOn, M.SkyDarkOff, M.SkyLinger = .5, .15, 2
local skyIdle = 0
local function releaseSky()
	local ch = channels.Sky
	if ch and ch.Object == ownSky then
		pcall(function()
			ch:Yield()
		end)
		channels.Sky = nil
	end
	if objects.Sky == ownSky then
		objects.Sky = nil
	end
	if ownSky then
		ownSky:Destroy()
		ownSky = nil
	end
	skyIdle = 0
end

local function ensureSky()
	if objects.Sky and objects.Sky.Parent then
		return
	end
	if ownSky and ownSky.Parent then
		M.Bind({ Sky = ownSky })
		return
	end
	if LightingService:FindFirstChildOfClass("Sky") then
		return -- someone else's sky (e.g. a world event's): never stack a second one
	end
	ownSky = Instance.new("Sky")
	ownSky.Name = "DOGROTS_HalloweenSky" -- default textures = the default skybox; only the moon size / stars are driven
	ownSky.Parent = LightingService
	M.Bind({ Sky = ownSky })
end

local function ensureGrade(enabledWeight: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	if not grade then
		if enabledWeight <= .005 then
			return nil
		end
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "DOGROTS_HalloweenGrade"
		grade.Enabled = false
	end
	if grade.Parent ~= cam then
		grade.Parent = cam
	end
	return grade
end

local function applyGrade(s)
	local scale = function(layer)
		if s.YieldAll and layer.Name ~= "FLASH" then
			return M.YieldGradeScale
		end
		return 1
	end
	local tint, sat, con, bri, total = Core.Grade(layers, scale)
	local g = M.TestGrade or ensureGrade(total)
	if not g then
		return
	end
	local on = total > .005
	if g.Enabled ~= on then
		g.Enabled = on
	end
	if on then
		tint = Core.Quantize("Tint", tint)
		if g.TintColor ~= tint then
			g.TintColor = tint
		end
		sat, con, bri = math.floor(sat * 500 + .5) / 500, math.floor(con * 500 + .5) / 500, math.floor(bri * 500 + .5) / 500
		if g.Saturation ~= sat then
			g.Saturation = sat
		end
		if g.Contrast ~= con then
			g.Contrast = con
		end
		if g.Brightness ~= bri then
			g.Brightness = bri
		end
	end
end

-- bind / rebind the objects the channels drive (missing objects simply have no channel). Tests pass mocks.
function M.Bind(objs: { [string]: any })
	for name, obj in pairs(objs) do
		local ch = channels[name]
		if ch and ch.Object ~= obj then
			pcall(function()
				ch:Yield()
			end)
			channels[name] = nil
			ch = nil
		end
		if obj and not ch then
			channels[name] = Channel.new(name, obj, Core.Keys[name])
		end
		objects[name] = obj
	end
end

function M.Step(dt: number, s)
	local now = s.Clock or os.clock()
	if s.Enabled == false then
		for _, ch in pairs(channels) do
			ch:Yield()
		end
		W.Active = false
		return
	end
	W.Active = true
	layerWeights(dt, s)
	W.Yielded = s.YieldAll == true
	W.YieldReason = s.YieldReason
	local skyWanted = wantsSky() and not s.YieldSky
	if skyWanted and W.ShownDark >= M.SkyDarkOn and not M.NoSkyCreate then
		ensureSky()
	end
	if ownSky and not s.YieldSky then
		if skyWanted and W.ShownDark >= M.SkyDarkOff then
			skyIdle = 0
		else
			skyIdle += dt
			if skyIdle >= M.SkyLinger then
				releaseSky()
			end
		end
	end
	for name, ch in pairs(channels) do
		local yield = (name == "Sky") and s.YieldSky or (name ~= "Sky" and s.YieldAll)
		if yield then
			ch:Yield()
		else
			local okObj = ch.Object ~= nil
			if okObj then
				ch:Drive(function(key, base)
					local v = Core.Composite(layers, name, key, base)
					if v ~= nil and key == "StarCount" then
						v = math.floor(v + .5)
					end
					return v
				end, now)
			end
		end
	end
	applyGrade(s)
	if now - lastPrune > 5 then
		lastPrune = now
		for _, ch in pairs(channels) do
			ch:Prune(now, M.HistorySeconds)
		end
	end
end

-- release-only frame (event switched off): repairs echoes of our old values, writes nothing of its own
local function janitorStep(s)
	local now = s.Clock or os.clock()
	for name, ch in pairs(channels) do
		local yield = (name == "Sky") and s.YieldSky or (name ~= "Sky" and s.YieldAll)
		if yield then
			ch:Yield()
		else
			ch:Drive(function()
				return nil
			end, now)
		end
	end
end
M.JanitorStep = janitorStep

function M.Weights()
	return W
end

function M.Flash(strength: number?, duration: number?)
	local reduced = Shared and Shared.ReducedMotion() or false
	flash.T = 0
	flash.Dur = math.max(.1, duration or .6) * (reduced and 1.6 or 1)
	flash.Strength = math.clamp(strength or .8, 0, 1) * (reduced and .45 or 1)
	flash.Second = not reduced
end

-- extra layer for other modules (e.g. a local "trick fog"): profile uses the same keys; weight glides over `fade` s
function M.Layer(name: string, profile)
	local l = addLayer("X_" .. name, profile)
	l.Target = l.Target or 0
	l.Remove = nil
	return {
		Set = function(_, weight: number, fade: number?)
			l.Target = math.clamp(weight or 0, 0, 1)
			l.Fade = fade or 1
		end,
		Remove = function(_, fade: number?)
			l.Target = 0
			l.Fade = fade or 1
			l.Remove = true
		end,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Runtime sensing
---------------------------------------------------------------------------------------------------------------------
local WEL = nil
local weState = nil
local secretCache, secretAt = false, -1
local function secretBusy(now: number): boolean
	if now - secretAt < .25 then
		return secretCache
	end
	secretAt = now
	local d = workspace:FindFirstChild("DOGROTS_District")
	d = d and d:FindFirstChild("03_DogLine")
	d = d and d:FindFirstChild("ActiveDogs")
	local busy = false
	if d then
		local t = workspace:GetServerTimeNow()
		for _, e in ipairs(d:GetChildren()) do
			local h = e:GetAttribute("ArrivalHoldUntil")
			if type(h) == "number" and h > t then
				busy = true
				break
			end
		end
	end
	secretCache = busy
	return busy
end

local BOSS_OFF = { Idle = true, Defeated = true, Escaped = true, Ended = true, Dead = true, Reward = true, Cooldown = true, Done = true }
local function bossEnraged(): boolean
	local st = RS:FindFirstChild("Halloween")
	st = st and st:FindFirstChild("State")
	local b = st and st:FindFirstChild("Boss")
	if not b then
		return false
	end
	return b:GetAttribute("Phase") == 5 and not BOSS_OFF[tostring(b:GetAttribute("State"))]
end
M.BossEnraged = bossEnraged

local function bindWorld()
	local atmo = LightingService:FindFirstChild("DOGROTS_Atmosphere")
	if not (atmo and atmo:IsA("Atmosphere")) then
		atmo = LightingService:FindFirstChildOfClass("Atmosphere")
	end
	local bloom = LightingService:FindFirstChild("DOGROTS_BloomEffect")
	if bloom and not bloom:IsA("BloomEffect") then
		bloom = nil
	end
	local clouds = workspace.Terrain and workspace.Terrain:FindFirstChildOfClass("Clouds")
	local want = { Lighting = LightingService, Atmo = atmo or false, Bloom = bloom or false, Clouds = clouds or false }
	for name, obj in pairs(want) do
		if obj == false then
			local ch = channels[name]
			if ch then
				pcall(function()
					ch:Yield()
				end)
				channels[name] = nil
			end
			objects[name] = nil
		elseif objects[name] ~= obj then
			M.Bind({ [name] = obj })
		end
	end
	if objects.Sky and not objects.Sky.Parent then
		channels.Sky = nil
		objects.Sky = nil
	end
end

local sense = { }
local function senseWorld()
	local s = sense
	s.Clock = os.clock()
	s.Now = Shared.Now()
	local cam = workspace.CurrentCamera
	s.CamPos = cam and cam.CFrame.Position or nil
	local day = LightingService:GetAttribute("DayFactor")
	if type(day) ~= "number" then
		local ch = channels.Lighting
		local clock = ch and ch.Base.ClockTime or LightingService.ClockTime -- the server's value, not ours
		day = math.clamp((math.cos((clock - 13) * math.pi / 12) + .2) * 1.2, 0, 1)
	end
	s.DayFactor = day
	s.ActualClock = LightingService.ClockTime
	local bm = Shared.BloodMoonState(s.Now)
	s.BloodAlpha = Shared.BloodMoonAlpha(s.Now, bm)
	s.BloodState = bm.State
	s.Enraged = bossEnraged()
	local wes = weState and weState:GetAttribute("State")
	local eventOwns = wes == "ACTIVE" or wes == "ENDING"
	local welActive = WEL ~= nil and WEL.Active == true
	local mine = LightingService:FindFirstChild("DOGROTS_MineGrade") ~= nil
	local secret = secretBusy(s.Clock)
	-- [WP-H2] inside THE UNDERYARD only the Mine mood yields: no island world-event mood / Secret arrival hold down there
	local under = W.Under > M.UnderInside or (s.CamPos ~= nil and Under ~= nil and Under.UnderWeight(s.CamPos, M.UnderFeather) > M.UnderInside)
	s.Under = under
	if under then
		eventOwns, welActive, secret = false, false, false
	end
	s.YieldAll = eventOwns or welActive or mine or secret
	s.YieldReason = eventOwns and "WorldEvent" or welActive and "WorldEventLighting" or mine and "MineMood" or secret and "Secret" or nil
	local moodSky = false
	if eventOwns or welActive then
		local id = weState and weState:GetAttribute("EventId")
		local mood = WEL and WEL.Moods and id and WEL.Moods[id]
		moodSky = mood ~= nil and mood.Sky ~= nil
		if WEL and WEL.Active and WEL.SkyBase ~= nil then
			moodSky = true
		end
	end
	s.YieldSky = moodSky
	s.Enabled = Shared.Enabled()
	return s
end

local function publish()
	local f = ctxRef and ctxRef.FX and ctxRef.FX.Folder()
	if not f then
		return
	end
	for attr, v in pairs({ HwZoneWeight = W.Zone, HwNight = W.Night, HwBlood = W.Blood, HwMoonVis = W.MoonVis, HwUnderWeight = W.Under }) do
		local old = f:GetAttribute(attr)
		if type(old) ~= "number" or math.abs(old - v) > .02 or (v == 0 and old ~= 0) or (v == 1 and old ~= 1) then
			f:SetAttribute(attr, math.floor(v * 100 + .5) / 100)
		end
	end
	if f:GetAttribute("HwLightingYield") ~= W.Yielded then
		f:SetAttribute("HwLightingYield", W.Yielded)
	end
end

-- [WP-H2] WorldEventLighting's grade (Lighting.DOGROTS_EventGrade) stays off while the camera is in THE UNDERYARD: an
-- island world-event colour never tints the cavern. Only Enabled is touched (WEL writes the grade values every frame and
-- never Enabled; its Stop destroys the object), and only a grade we switched off is switched back on.
local eventGradeOff: any = nil
local function eventGrade(under: boolean)
	local g = LightingService:FindFirstChild("DOGROTS_EventGrade")
	if eventGradeOff and eventGradeOff ~= g then
		if eventGradeOff.Parent then
			eventGradeOff.Enabled = true
		end
		eventGradeOff = nil
	end
	if under and g and g:IsA("ColorCorrectionEffect") and g.Enabled then
		g.Enabled = false
		eventGradeOff = g
	elseif not under and eventGradeOff then
		if eventGradeOff.Parent then
			eventGradeOff.Enabled = true
		end
		eventGradeOff = nil
	end
end
M.EventGrade = eventGrade

local bound = false
local janitorBound = false
function M.Shutdown()
	if bound then
		RunService:UnbindFromRenderStep("DOGROTS_HalloweenLighting")
		bound = false
	end
	pcall(eventGrade, false)
	for _, ch in pairs(channels) do
		pcall(function()
			ch:Yield()
		end)
	end
	if grade then
		grade:Destroy()
		grade = nil
	end
	W.Active = false
	-- keep repairing echoes (a world event / mine mood that captured one of our values may restore it later)
	janitorUntil = os.clock() + M.HistorySeconds
	if not janitorBound then
		janitorBound = true
		local acc = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < .5 then
				return
			end
			acc = 0
			if os.clock() > janitorUntil or bound then
				conn:Disconnect()
				janitorBound = false
				if not bound and ownSky and not (WEL and WEL.Active) then
					ownSky:Destroy()
					ownSky = nil
					channels.Sky, objects.Sky = nil, nil
				end
				return
			end
			pcall(function()
				local s = senseWorld()
				janitorStep(s)
				if ownSky and ownSky.Parent and not s.YieldSky and not (WEL and WEL.Active) then
					local ch = channels.Sky
					if ch then
						ch:Yield()
					end
					ownSky:Destroy()
					ownSky = nil
					channels.Sky, objects.Sky = nil, nil
				end
			end)
		end)
	end
end

-- ctx = {Shared, Layout, FX?} (Start calls it; offline tests call it directly and drive Bind/Step themselves)
function M.Configure(ctx)
	ctxRef = ctx
	Shared = ctx.Shared
	Layout = ctx.Layout
	-- [WP-H2] the Underyard presence weight (tests pass ctx.Underyard; a place without Chapter II simply has none)
	Under = ctx.Underyard
	if Under == nil then
		local ok, m = pcall(function()
			local hw = RS:FindFirstChild("Halloween")
			local mod = hw and hw:FindFirstChild("UnderyardRuntime")
			return mod and require(mod) :: any
		end)
		Under = ok and type(m) == "table" and m or nil
	end
end

function M.Start(ctx)
	M.Configure(ctx)
	if not Shared.Enabled() then
		return
	end
	pcall(function()
		local we = RS:WaitForChild("WorldEvents", 20)
		weState = we and we:WaitForChild("State", 10)
		local mod = we and we:FindFirstChild("WorldEventLighting")
		if mod then
			WEL = require(mod) -- the same table WorldEventController drives (Active / Moods / SkyBase)
		end
	end)
	bindWorld()
	local acc, rebindAcc = 0, 0
	bound = true
	RunService:BindToRenderStep("DOGROTS_HalloweenLighting", Enum.RenderPriority.First.Value + 1, function(dt)
		local ok, err = pcall(function()
			rebindAcc += dt
			if rebindAcc > 1 then
				rebindAcc = 0
				bindWorld()
			end
			local s = senseWorld()
			if not s.Enabled then
				M.Shutdown()
				return
			end
			eventGrade(s.Under == true) -- [WP-H2]
			M.Step(dt, s)
			acc += dt
			if acc > .2 then
				acc = 0
				publish()
			end
		end)
		if ok then
			M.Errors = 0
		else
			M.Errors = (M.Errors or 0) + 1
			if not M.Warned then
				M.Warned = true
				warn("Halloween Lighting step failed: " .. tostring(err))
			end
			if M.Errors >= 30 then -- never freeze on our last values: hand everything back
				pcall(M.Shutdown)
			end
		end
	end)
	-- the event can come back on (Studio): restart cleanly
	local st = RS:FindFirstChild("Halloween") and RS.Halloween:FindFirstChild("State")
	if st and not M.Listening then
		M.Listening = true
		st:GetAttributeChangedSignal("Enabled"):Connect(function()
			if Shared.Enabled() and not bound then
				M.Start(ctx)
			end
		end)
	end
end

return M
