-- THE REVEAL — pure rules of "И ЭТО ВСЁ?" → the church → the portal (ReplicatedStorage.Halloween.RevealRules, WP-F;
-- docs/halloween2/DESIGN.md §6). Shared by HalloweenClient.Reveal (presentation) and tests/reveal.luau: no services,
-- no instances, only Chapter2Config / UnderyardLayout numbers and datatypes. The server owns every flag (C2Notified,
-- C2RevealSeen); these rules only decide what the client SHOWS and when.
--   R.Config                                presentation timings (seconds), radii (studs), budgets
--   R.NotifyBlocked(s) -> reason?           why the notification may not start now (nil = it may)
--   R.ChurchState(s) -> "Open" | "Closed"   the per-player church end state (doors, portal, cracks, slit)
--   R.PromptVisible(s) -> bool              the DESCEND prompt, shown client-side to eligible players only
--   R.CinematicDue(s) -> bool               the church cinematic should start (first approach)
--   R.TeaserWanted(s) -> bool (not eligible, near the closed church) ; R.TeaserDelay(rng, first) -> seconds
--   R.Objective(s) -> "Church" | "Descend" | nil
--   R.Graphemes(text) -> {string} ; R.Typewriter(text, cfg?) -> {Steps = {{At, Count, Thud}}, Duration}
--   R.DoorOpen(t) -> 0..1 (eased swing of the doors over Config.Church.DoorTime) ; R.DoorPivot(closed, angleDeg, f)
--   R.CrackAlpha(crackT, progress) -> 0..1 ; R.Transition(t) / R.FadeIn(t) -> the portal transition's state
--   R.EdgeCracks(seed, count) -> {{Points = {{x, y}}, Width, Delay}} (screen-space light cracks of the notification)
--   R.Beats() -> {{T, Name}} ; R.Shots() -> camera keys of the church cinematic
--   R.GhostCount(budget) -> 1..Config.Guide.MaxLights
local Cfg = require(script.Parent:WaitForChild("Chapter2Config"))
local Layout = require(script.Parent:WaitForChild("UnderyardLayout"))

local R = {}

local church = Layout.Church
R.Config = {
	-- §6.1 the secret notification (seconds from the moment it starts)
	Notify = {
		Stable = 2.5, -- the wanted + unblocked state must hold this long before it starts (a closing menu, a reward card)
		Retry = 3, -- re-check interval while it is wanted but blocked
		FadeIn = .9, -- screen to black (the mixer ducks everything over DuckFade)
		DuckFade = 1.2,
		Silence = 1.5, -- after the black: nothing but silence
		Swell = 2.4, -- the sub-bass swell + the distant toll
		TypeAt = 3.1, -- the typewriter starts
		Letter = .11, -- seconds per letter
		WordGap = .42, -- extra pause after a word (its heartbeat thud)
		Hold = 1.8, -- the full line holds (chromatic jitter)
		LineFade = 1.1, -- the big line shrinks up, the second line fades in, the light cracks spread
		CrackTime = 1.8,
		EyeOpen = 1.6,
		ButtonDelay = .55, -- after the second line: the FIND OUT button
		InputAfter = 4, -- no tap / key does anything before this (§6.1.5)
		AutoPress = 90, -- an unattended notification finds out by itself
		Tear = .62, -- the overlay tears upward
		Flash = .45,
		ButtonHeight = 72, -- >= 64 px (§6.1.5)
		DisplayOrder = 88,
		Cracks = 7,
	},
	-- §6.3 the church cinematic (≈16 s, skippable after 3 s)
	Church = {
		Duration = 16,
		SkipAfter = 3,
		BlendIn = 2.2,
		BlendOut = 1.3,
		Silence = 2.5, -- after the camera arrives, before BOOM #1 (only the wind bed)
		Booms = { 4.7, 7.0, 9.2 },
		Windows = 1.6, -- BOOM #2: window lights die one by one over this
		CrackTime = 1.5, -- BOOM #3: the cracks spread over this
		TowerShake = .6,
		DoorsAt = 10.4,
		DoorTime = 2.4,
		DoorAngle = 100,
		PortalAt = 11.0,
		PortalTime = 1.6,
		TitleAt = 12.8,
		TitleTime = 2.4,
		Relight = 14.2,
		TriggerRadius = Cfg.Reveal.TriggerRadius or church.TriggerRadius,
		Door = church.Door,
		Bell = church.Bell,
		Cooldown = 8, -- after a cancelled cinematic (death, character removal) before it may trigger again
		ReplayRange = 260, -- a journal replay plays where the church is streamed in
		NeedRange = 60, -- C2Reveal {Need = "Church"}: closer than this the cinematic plays at once
		CracksSettled = .62, -- crack glow (fraction of its reveal) in the lasting open state
	},
	-- §6.5 not yet eligible
	Teaser = {
		Radius = church.TeaserRadius,
		First = { 5, 12 },
		Every = Cfg.Reveal.TeaserEvery or { 45, 90 },
		Breaths = 2,
		Breath = 2.6,
		TextIn = 1, TextHold = 3.2, TextOut = 1.5,
		IdleRange = 140, -- the slit's faint idle glow is animated inside this
	},
	-- §6.2 the guide to the church
	Guide = { Spacing = 18, Lead = 10, MaxLights = 12, MarkerRange = 2200, DescendRange = 160 },
	-- §6.6 the portal transition (both directions)
	Portal = {
		Stretch = 1.05, -- FOV stretch, vertical squash and colour drain
		Eye = .35, -- the giant eye / moon flash
		Black = 1.4, -- fully black from here
		FovAdd = 42,
		Squash = .86, -- share of the screen height the squash bars cover at the end of the stretch
		HoldMax = (Cfg.Portal.TransitionDelay or 1.45) + (Cfg.Portal.StreamTimeout or 6) + 3.5, -- black at most this long
		Settle = .35, -- after "Arrived" before the fade-in
		FadeIn = 1.15,
		TitleTime = 3.2,
	},
}
R.Church = church
R.PortalCentre = church.PortalCentre

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
R.Smooth = smooth

---------------------------------------------------------------------------------------------------------------------
-- decisions
---------------------------------------------------------------------------------------------------------------------
-- s = {Enabled, Eligible, Notified, Replay, Showing, Menu, Cinema, Mining, Tutorial, Dead, Combat, Trial, Overlay}
function R.NotifyBlocked(s: { [string]: any }): string?
	if s.Showing then
		return "Showing"
	end
	if not s.Replay then
		if not s.Enabled then
			return "Closed"
		end
		if not s.Eligible then
			return "Ineligible"
		end
		if s.Notified then
			return "Notified"
		end
	end
	if s.Dead then
		return "Dead"
	end
	if s.Menu then
		return "Menu"
	end
	if s.Cinema then
		return "Cinema"
	end
	if s.Mining then
		return "Mining"
	end
	if s.Tutorial then
		return "Tutorial"
	end
	if s.Combat then
		return "Combat"
	end
	if s.Trial then
		return "Trial"
	end
	if s.Overlay then
		return "Overlay"
	end
	return nil
end

-- s = {Enabled, Eligible, RevealSeen, Pending}: Pending = a cinematic just ended and C2RevealSeen is on its way
function R.ChurchState(s: { [string]: any }): string
	if s.Enabled and s.Eligible and (s.RevealSeen or s.Pending) then
		return "Open"
	end
	return "Closed"
end

function R.PromptVisible(s: { [string]: any }): boolean
	return s.Enabled == true and s.Eligible == true
end

-- s = {Enabled, Eligible, RevealSeen, Distance, Playing, Now, CooldownUntil, Blocked}
function R.CinematicDue(s: { [string]: any }): boolean
	if not s.Enabled or not s.Eligible or s.RevealSeen or s.Playing or s.Blocked then
		return false
	end
	if (s.CooldownUntil or 0) > (s.Now or 0) then
		return false
	end
	return type(s.Distance) == "number" and s.Distance <= R.Config.Church.TriggerRadius
end

-- s = {Enabled, Eligible, State, Distance, Playing}: a player who has not finished Chapter I stands near the closed
-- church (§6.5; an eligible player gets the cinematic instead)
function R.TeaserWanted(s: { [string]: any }): boolean
	return s.Enabled == true and s.Eligible ~= true and s.State == "Closed" and not s.Playing and type(s.Distance) == "number"
		and s.Distance <= R.Config.Teaser.Radius
end

function R.TeaserDelay(rng: any, first: boolean?): number
	local range = first and R.Config.Teaser.First or R.Config.Teaser.Every
	local u = type(rng) == "table" and rng:NextNumber() or (type(rng) == "number" and rng or .5)
	return range[1] + (range[2] - range[1]) * clamp01(u)
end

-- s = {Enabled, Eligible, RevealSeen, Entered}
function R.Objective(s: { [string]: any }): string?
	if not s.Enabled or not s.Eligible then
		return nil
	end
	if not s.RevealSeen then
		return "Church"
	end
	if not s.Entered then
		return "Descend"
	end
	return nil
end

function R.GhostCount(budget: number?): number
	return math.clamp(math.floor(tonumber(budget) or R.Config.Guide.MaxLights), 1, R.Config.Guide.MaxLights)
end

---------------------------------------------------------------------------------------------------------------------
-- the typewriter: one entry per grapheme (UTF-8 code point; Cyrillic counts once), a thud at the end of every word
---------------------------------------------------------------------------------------------------------------------
function R.Graphemes(text: string): { string }
	local out = {}
	local ok = pcall(function()
		for _, code in utf8.codes(text) do
			table.insert(out, utf8.char(code))
		end
	end)
	if not ok then
		table.clear(out)
		for i = 1, #text do
			table.insert(out, string.sub(text, i, i))
		end
	end
	return out
end

-- -> {Steps = {{At = seconds after the start, Count = graphemes shown, Thud = a word just ended}}, Duration, Count}
function R.Typewriter(text: string, cfg: { [string]: any }?): { [string]: any }
	local c = cfg or R.Config.Notify
	local g = R.Graphemes(text)
	local steps = {}
	local t = 0
	for i, ch in ipairs(g) do
		local nextCh = g[i + 1]
		local wordEnd = ch ~= " " and (nextCh == nil or nextCh == " ")
		if ch ~= " " then
			table.insert(steps, { At = t, Count = i, Thud = wordEnd })
			t += c.Letter
			if wordEnd then
				t += c.WordGap
			end
		end
	end
	return { Steps = steps, Duration = t, Count = #g }
end

---------------------------------------------------------------------------------------------------------------------
-- the church: doors, cracks
---------------------------------------------------------------------------------------------------------------------
-- 0..1 swing of the doors t seconds after they start: a stuck jolt, a heavy ease-in-out swing, a small bounce at the stop
function R.DoorOpen(t: number): number
	local T = R.Config.Church.DoorTime
	if t <= 0 then
		return 0
	end
	if t < .3 then
		return .035 * math.sin(t / .3 * math.pi * .5) -- the latch gives
	end
	local k = (t - .3) / (T - .3)
	if k >= 1 then
		return 1
	end
	local f = .035 + (1 - .035) * smooth(k)
	if k > .82 then
		f += math.sin((k - .82) / .18 * math.pi) * .018 -- the leaves hit the stops
	end
	return math.min(f, 1.02)
end

-- the hinge pivot of a door `f` of the way open (closed = ClosedPivot attribute, angleDeg = OpenAngle attribute)
function R.DoorPivot(closed: CFrame, angleDeg: number, f: number): CFrame
	return closed * CFrame.Angles(0, math.rad(angleDeg * f), 0)
end

-- alpha of a crack piece (CrackT = its place in the spread, 0 at the door) while the spread runs at `progress` (0..1)
function R.CrackAlpha(crackT: number, progress: number): number
	return clamp01((progress * 1.12 - crackT) / .12)
end

---------------------------------------------------------------------------------------------------------------------
-- the portal transition (§6.6): t seconds after "Start"
---------------------------------------------------------------------------------------------------------------------
-- -> {Fov (added degrees), Squash (0..1 of the screen height covered by the bars), Saturation (0..-1), Eye (0..1),
--     Flash (0..1), Black (0..1)}
function R.Transition(t: number): { [string]: number }
	local P = R.Config.Portal
	local k = clamp01(t / P.Stretch)
	local e = k * k -- accelerating stretch
	local eye = 0
	local flash = 0
	if t >= P.Stretch then
		-- the eye opens fast, the moon flashes white in its pupil, then everything goes black
		local u = (t - P.Stretch) / P.Eye
		eye = clamp01(u * 3)
		flash = u > .55 and clamp01(1 - math.abs(u - .78) / .22) or 0
	end
	return {
		Fov = P.FovAdd * e,
		Squash = P.Squash * smooth(k),
		Saturation = -smooth(t / (P.Stretch * .85)),
		Eye = eye,
		Flash = flash,
		Black = clamp01((t - (P.Black - .08)) / .08),
	}
end

-- the fade back in, t seconds after it starts
function R.FadeIn(t: number): { [string]: number }
	local P = R.Config.Portal
	local k = smooth(t / P.FadeIn)
	return { Black = 1 - k, Saturation = -(1 - smooth(t / (P.FadeIn * 1.4))), Squash = P.Squash * (1 - smooth(t / (P.FadeIn * .8))) }
end

---------------------------------------------------------------------------------------------------------------------
-- the notification's light cracks: polylines from the screen edges towards the centre (normalized 0..1 coordinates)
---------------------------------------------------------------------------------------------------------------------
local function lcg(seed: number): () -> number
	local s = math.floor(math.abs(seed)) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end
R.Lcg = lcg

function R.EdgeCracks(seed: number, count: number?): { any }
	local rnd = lcg(seed)
	local n = count or R.Config.Notify.Cracks
	local out = {}
	for i = 1, n do
		-- start on the frame edge, spread around the screen (left, right, top, bottom in turn)
		local side = (i - 1) % 4
		local u = .12 + .76 * rnd()
		local x, y
		if side == 0 then
			x, y = 0, u
		elseif side == 1 then
			x, y = 1, u
		elseif side == 2 then
			x, y = u, 0
		else
			x, y = u, 1
		end
		local dirX, dirY = .5 - x, .5 - y
		local len = math.sqrt(dirX * dirX + dirY * dirY)
		dirX, dirY = dirX / len, dirY / len
		local pts = { { x, y } }
		local steps = 4 + math.floor(rnd() * 3)
		local reach = .2 + .14 * rnd()
		for k = 1, steps do
			local jitter = (rnd() - .5) * .9
			local ca, sa = math.cos(jitter), math.sin(jitter)
			local dx, dy = dirX * ca - dirY * sa, dirX * sa + dirY * ca
			local step = reach / steps * (.7 + .6 * rnd())
			x, y = math.clamp(x + dx * step, 0, 1), math.clamp(y + dy * step, 0, 1)
			table.insert(pts, { x, y })
		end
		table.insert(out, { Points = pts, Width = 2 + rnd() * 2, Delay = (i - 1) / n * .5 })
		-- a short branch from the middle of every second crack
		if i % 2 == 0 and #pts >= 3 then
			local mid = pts[math.floor(#pts / 2) + 1]
			local bx, by = mid[1], mid[2]
			local ang = (rnd() > .5 and 1 or -1) * (.6 + .5 * rnd())
			local ca, sa = math.cos(ang), math.sin(ang)
			local dx, dy = dirX * ca - dirY * sa, dirX * sa + dirY * ca
			local branch = { { bx, by } }
			for _ = 1, 2 do
				bx, by = math.clamp(bx + dx * .05, 0, 1), math.clamp(by + dy * .05, 0, 1)
				table.insert(branch, { bx, by })
			end
			table.insert(out, { Points = branch, Width = 1.5, Delay = (i - 1) / n * .5 + .35 })
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- the church cinematic's script (§6.3)
---------------------------------------------------------------------------------------------------------------------
function R.Beats(): { { [string]: any } }
	local c = R.Config.Church
	local list = {
		{ T = 0, Name = "Begin" },
		{ T = c.BlendIn, Name = "Arrive" },
		{ T = c.Booms[1], Name = "Boom1" },
		{ T = c.Booms[2], Name = "Boom2" },
		{ T = c.Booms[3], Name = "Boom3" },
		{ T = c.DoorsAt, Name = "Doors" },
		{ T = c.PortalAt, Name = "Portal" },
		{ T = c.TitleAt, Name = "Title" },
		{ T = c.Relight, Name = "Relight" },
		{ T = c.Duration, Name = "End" },
	}
	table.sort(list, function(a, b)
		return a.T < b.T
	end)
	return list
end

-- camera keys {T, Eye, At, Fov}: a low 3/4 shot of the Grand Crypt + Moon Tower that drifts closer through the tolls,
-- then a push in towards the door while it opens
function R.Shots(): { { [string]: any } }
	local V = Vector3.new
	return {
		{ T = 0, Eye = V(143, 4.2, 701), At = V(128, 22.5, 733), Fov = 70 },
		{ T = 10.1, Eye = V(141.2, 4.0, 703.5), At = V(128, 21.5, 733), Fov = 68 },
		{ T = 12.6, Eye = V(133.5, 4.6, 707.5), At = V(128, 7.6, 732), Fov = 56 },
		{ T = 16, Eye = V(132.2, 4.4, 710.5), At = V(128, 7.2, 733), Fov = 54 },
	}
end

return R
