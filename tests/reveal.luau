--!nolint
-- THE REVEAL (WP-F, docs/halloween2/DESIGN.md §6): lune run tests/reveal.luau
--   1. navigation   the "Church" destination (EN + RU aliases), routes to the church from the spawn and from the Dead
--                   Yard gate (round the boss pit, past the Grave Bell), live sealing, the Underyard escape to the arch
--   2. rules        RevealRules: who sees what when (notification blockers, church state, prompt, cinematic, teaser),
--                   the typewriter (EN / RU graphemes, a thud per word), the door swing, cracks, the portal transition,
--                   the cinematic's beats and shots
--   3. church edit  tools/edits/38_church.luau in the shipped place, twice: one Church model, doors closed at their
--                   ClosedPivot, every portal part hidden, cracks hidden, originals recorded once, Anchors.Portal
--   4. client       HalloweenClient.Reveal headless (tests/lib/client_env): the notification (timing, input gate,
--                   FIND OUT, teardown, C2Notified, the guide), the church end state per player, the cinematic (beats,
--                   C2RevealSeen, skip, cancel), the teaser, the portal transition both ways, replays without requests
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local L = require("./lib/economy_env")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local V = Vector3.new

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("ok   " .. name)
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function check(cond, msg)
	if not cond then
		error(msg or "check failed", 2)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

-----------------------------------------------------------------------------------------------------------------------
-- 1. navigation
-----------------------------------------------------------------------------------------------------------------------
local D = L.Require("ReplicatedStorage.Navigation.Destinations")
local RG = L.Require("ReplicatedStorage.Navigation.RouteGraph")
local Live = L.Require("ReplicatedStorage.Navigation.Live")
local U = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local SPAWN = V(0, 0.6, 377)
local GATE = V(36, 3, 575)
local CHURCH_GOAL = V(128, 0.5, 720)

local function routeTo(from, key)
	RG.Refresh(true)
	return RG.Plan(from, RG.Target(key))
end
local function routeClear(route)
	for i, p in ipairs(route.Points) do
		local b = RG.BlockerAt(p)
		check(b == nil, string.format("point %d (%.0f, %.0f) inside %s", i, p.X, p.Z, b and b.Name or "?"))
		local q = route.Points[i + 1]
		if q then
			local s = RG.SegmentBlocker(p, q)
			check(s == nil, string.format("segment %d crosses %s", i, s and s.Name or "?"))
		end
	end
end
local function has(list, value)
	return table.find(list, value) ~= nil
end

test("church destination: entry after the Dead Yard, Russian names", function()
	local e = D.ByKey.Church
	check(e, "no Church entry")
	check(e.Category == "Attractions" and e.Ru == "Церковь" and e.ShortRu == "ЦЕРКОВЬ", "names")
	local iYard, iChurch
	for i, x in ipairs(D.List) do
		if x.Key == "DeadYard" then
			iYard = i
		elseif x.Key == "Church" then
			iChurch = i
		end
	end
	check(iYard and iChurch == iYard + 1, "Church right after the Dead Yard")
	check(D.Text(e, "Name", "ru") == "Церковь", "Text ru")
end)

test("church destination: EN + RU aliases (case, ё), priority aliases", function()
	for _, alias in ipairs({ "Church", "church", "CHURCH", "Crypt", "Grand Crypt", "grand crypt", "Moon Tower", "Portal", "Underyard",
		"The Underyard", "Церковь", "церковь", "ЦЕРКОВЬ", "Склеп", "склеп", "Портал", "ПОРТАЛ", "Поддворье", "Лунная башня" }) do
		check(D.Resolve(alias) == "Church", "alias " .. alias .. " -> " .. tostring(D.Resolve(alias)))
	end
	check(D.Normalize("ВСЁ") == D.Normalize("все"), "ё folds to е")
	check(D.Resolve("Dead Yard") == "DeadYard", "Dead Yard still resolves to itself")
	check(D.Resolve("Layers") ~= "Church", "the Portal Ruins keep their own aliases")
end)

test("live sealing: Chapter II off seals the church, the event off seals both", function()
	local church, yard = D.ByKey.Church, D.ByKey.DeadYard
	Live.Override = nil
	check(D.Sealed(church) == false and D.Sealed(yard) == false, "open by default")
	check(church.Sealed == false, "the entry's Sealed field is live")
	Live.Override = { Chapter2 = false }
	check(D.Sealed(church) == true and D.Sealed(yard) == false, "chapter II closed")
	Live.Override = { Halloween = false }
	check(D.Sealed(church) == true and D.Sealed(yard) == true, "event off")
	Live.Override = nil
end)

test("route to the church from the spawn: round the boss pit to the crypt door", function()
	local r, why = routeTo(SPAWN, "Church")
	check(r, "no route: " .. tostring(why))
	check(has(r.Nodes, "DeadYardGate") and has(r.Nodes, "DeadYardPitS") and has(r.Nodes, "DeadYardCrypt"), "nodes " .. table.concat(r.Nodes, ">"))
	check(not has(r.Nodes, "DeadYardPitFloor"), "does not cut across the pit floor")
	local last = r.Points[#r.Points]
	check((last - CHURCH_GOAL).Magnitude < 1.5, "ends at the goal")
	check(r.Length > 300 and r.Length < 650, "length " .. r.Length)
	routeClear(r)
	-- never through the Grave Bell
	for _, p in ipairs(r.Points) do
		check(not (p.X > 140 and p.X < 152 and p.Z > 631 and p.Z < 641), "through the Grave Bell")
	end
end)

test("route to the church from the Dead Yard gate", function()
	local r, why = routeTo(GATE, "Church")
	check(r, "no route: " .. tostring(why))
	check(has(r.Nodes, "DeadYardCrypt"), "nodes " .. table.concat(r.Nodes, ">"))
	check((r.Points[#r.Points] - CHURCH_GOAL).Magnitude < 1.5, "ends at the goal")
	check(r.Length < 330, "length " .. r.Length)
	routeClear(r)
end)

test("route to the church from the boss pit floor", function()
	local r, why = routeTo(V(128, -8, 672), "Church")
	check(r, "no route: " .. tostring(why))
	check((r.Points[#r.Points] - CHURCH_GOAL).Magnitude < 1.5, "ends at the goal")
	check(r.Length < 120, "length " .. r.Length)
end)

test("sealed church: no route while Chapter II is closed; the yard nodes go with the event", function()
	Live.Override = { Chapter2 = false }
	local r, why = routeTo(SPAWN, "Church")
	check(r == nil and why == "sealed", "chapter II closed: " .. tostring(why))
	local y = routeTo(SPAWN, "DeadYard")
	check(y ~= nil, "the Dead Yard itself stays open")
	Live.Override = { Halloween = false }
	local y2, why2 = routeTo(SPAWN, "DeadYard")
	check(y2 == nil and why2 == "sealed", "event off: " .. tostring(why2))
	Live.Override = nil
	check(routeTo(SPAWN, "Church") ~= nil, "back open")
end)

test("Underyard escape: every district leads to the arrival arch", function()
	check(RG.UnderyardEscape(SPAWN, U) == nil, "nothing outside the Underyard")
	local goal = V(U.ReturnPrompt.X, U.Floor + .2, U.ReturnPrompt.Z + 3)
	local starts = {
		V(0, 3, 2352), V(0, 3, 2440), V(150, 0, 2240), V(-150, 0, 2560), V(150, -16, 2560), V(0, 1, 2625), V(-150, 0, 2250),
		V(30, 0, 2395),
	}
	for _, p in ipairs(starts) do
		local r = RG.UnderyardEscape(p, U)
		check(r and r.InUnderyard, "no escape from " .. tostring(p))
		check((r.Points[#r.Points] - goal).Magnitude < .01 and (r.Goal - goal).Magnitude < .01, "ends at the arch")
		check((r.Points[1] - p).Magnitude < .01, "starts at the player")
		check(r.Pointer and math.abs(r.Pointer.Z - U.ArrivalArch.Z) < .01, "pointer over the arch")
		check((goal - U.ReturnPrompt).Magnitude < 10, "the goal is inside the ASCEND prompt's range")
		for i = 2, #r.Points do
			check(U.InZone(r.Points[i], 4), "point " .. i .. " outside the zone")
		end
	end
	-- the Undercrypt mine floor climbs its ramp first
	local deep = RG.UnderyardEscape(V(150, -16, 2560), U)
	local sawBottom, sawTop = false, false
	for _, q in ipairs(deep.Points) do
		sawBottom = sawBottom or (q - U.Undercrypt.RampBottom).Magnitude < 3
		sawTop = sawTop or (q - U.Undercrypt.RampTop).Magnitude < 3
	end
	check(sawBottom and sawTop, "the Undercrypt route takes the ramp")
	-- Bell Square: round the bell tower, never through it
	local centre = V(U.Centre.X, 0, U.Centre.Z)
	local across = RG.UnderyardEscape(V(0, 0, 2452), U)
	for i = 1, #across.Points - 1 do
		local a, b = across.Points[i], across.Points[i + 1]
		local ab = V(b.X - a.X, 0, b.Z - a.Z)
		local t = ab.Magnitude > 0 and math.clamp((V(centre.X - a.X, 0, centre.Z - a.Z)):Dot(ab) / (ab.Magnitude ^ 2), 0, 1) or 0
		local closest = V(a.X, 0, a.Z) + ab * t
		check((closest - centre).Magnitude > 30, "segment " .. i .. " passes through the bell tower")
	end
end)

-----------------------------------------------------------------------------------------------------------------------
-- 2. rules
-----------------------------------------------------------------------------------------------------------------------
local R = L.Require("ReplicatedStorage.Halloween.RevealRules")
local Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Cn, Ch, Ct, Cp = R.Config.Notify, R.Config.Church, R.Config.Teaser, R.Config.Portal

test("config: the §6 numbers", function()
	check(Cn.ButtonHeight >= 64 and Cn.InputAfter == 4 and Cn.DisplayOrder == 88, "notification")
	check(Ch.Duration >= 15 and Ch.Duration <= 17 and Ch.SkipAfter == 3 and Ch.DoorAngle == 100 and Ch.DoorTime == 2.4, "cinematic")
	check(Ch.TriggerRadius == 46 and Ch.NeedRange <= Cfg.Reveal.ChurchRadius, "radii (the server accepts C2RevealSeen there)")
	check(Ct.Radius == 70 and Ct.Every[1] == 45 and Ct.Every[2] == 90, "teaser")
	check(R.Config.Guide.Spacing == 18 and R.Config.Guide.MaxLights == 12, "guide")
	check(Cp.Black <= Cfg.Portal.TransitionDelay, "the screen is black before the server moves the character")
	check(Cp.HoldMax >= Cfg.Portal.TransitionDelay + Cfg.Portal.StreamTimeout, "the black outlasts the server's stream budget")
end)

local BASE = { Enabled = true, Eligible = true, Notified = false }
local function with(extra)
	local s = table.clone(BASE)
	for k, v in pairs(extra) do
		s[k] = v
	end
	return s
end

test("NotifyBlocked: who sees the notification and when", function()
	check(R.NotifyBlocked(BASE) == nil, "free")
	for key, reason in pairs({ Showing = "Showing", Dead = "Dead", Menu = "Menu", Cinema = "Cinema", Mining = "Mining", Tutorial = "Tutorial",
		Combat = "Combat", Trial = "Trial", Overlay = "Overlay" }) do
		check(R.NotifyBlocked(with({ [key] = true })) == reason, key)
	end
	check(R.NotifyBlocked(with({ Enabled = false })) == "Closed", "closed")
	check(R.NotifyBlocked(with({ Eligible = false })) == "Ineligible", "ineligible")
	check(R.NotifyBlocked(with({ Notified = true })) == "Notified", "once")
	-- a replay ignores the flags but not the screen
	check(R.NotifyBlocked({ Replay = true, Notified = true, Eligible = false, Enabled = false }) == nil, "replay")
	check(R.NotifyBlocked({ Replay = true, Menu = true }) == "Menu", "replay waits for the menu")
end)

test("church state, prompt, objective", function()
	check(R.ChurchState({ Enabled = true, Eligible = true, RevealSeen = true }) == "Open", "seen = open")
	check(R.ChurchState({ Enabled = true, Eligible = true, Pending = true }) == "Open", "pending = open")
	check(R.ChurchState({ Enabled = true, Eligible = true }) == "Closed", "not seen = closed")
	check(R.ChurchState({ Enabled = true, Eligible = false, RevealSeen = true }) == "Closed", "ineligible = closed")
	check(R.ChurchState({ Enabled = false, Eligible = true, RevealSeen = true }) == "Closed", "chapter off = closed")
	check(R.PromptVisible({ Enabled = true, Eligible = true }) and not R.PromptVisible({ Enabled = true, Eligible = false }), "prompt")
	check(R.Objective({ Enabled = true, Eligible = true }) == "Church", "objective church")
	check(R.Objective({ Enabled = true, Eligible = true, RevealSeen = true }) == "Descend", "objective descend")
	check(R.Objective({ Enabled = true, Eligible = true, RevealSeen = true, Entered = true }) == nil, "done")
	check(R.Objective({ Enabled = true, Eligible = false }) == nil, "ineligible")
end)

local function with2(s, extra)
	local o = table.clone(s)
	for k, v in pairs(extra) do
		o[k] = v
	end
	return o
end

test("cinematic trigger: first approach within 46 studs only", function()
	local s = { Enabled = true, Eligible = true, RevealSeen = false, Distance = 46, Now = 10, CooldownUntil = 0 }
	check(R.CinematicDue(s), "at 46")
	check(not R.CinematicDue(with2(s, { Distance = 46.5 })), "outside")
	check(not R.CinematicDue(with2(s, { RevealSeen = true })), "seen")
	check(not R.CinematicDue(with2(s, { Playing = true })), "playing")
	check(not R.CinematicDue(with2(s, { Blocked = true })), "blocked")
	check(not R.CinematicDue(with2(s, { CooldownUntil = 11 })), "cooldown")
	check(not R.CinematicDue(with2(s, { Eligible = false })), "ineligible")
	local noCharacter = table.clone(s)
	noCharacter.Distance = nil
	check(not R.CinematicDue(noCharacter), "no character")
end)

test("teaser: players who have not finished Chapter I, near the closed church", function()
	local s = { Enabled = true, Eligible = false, State = "Closed", Distance = 70 }
	check(R.TeaserWanted(s), "at 70")
	check(not R.TeaserWanted(with2(s, { Distance = 71 })), "outside")
	check(not R.TeaserWanted(with2(s, { Eligible = true })), "eligible players get the cinematic")
	check(not R.TeaserWanted(with2(s, { State = "Open" })), "open church")
	check(not R.TeaserWanted(with2(s, { Playing = true })), "while the cinematic plays")
	check(not R.TeaserWanted(with2(s, { Enabled = false })), "chapter off")
	local lo, hi = { NextNumber = function() return 0 end }, { NextNumber = function() return 1 end }
	check(R.TeaserDelay(lo, true) == Ct.First[1] and R.TeaserDelay(hi, true) == Ct.First[2], "first delay")
	check(R.TeaserDelay(lo, false) == 45 and R.TeaserDelay(hi, false) == 90, "45-90 s")
end)

test("ghost lights: 12 / 8 / 5 by quality, clamped", function()
	check(R.GhostCount(nil) == 12 and R.GhostCount(5) == 5 and R.GhostCount(0) == 1 and R.GhostCount(99) == 12, "clamp")
	check(R.GhostCount(Cfg.Quality.High.GhostLights) == 12 and R.GhostCount(Cfg.Quality.Medium.GhostLights) == 8
		and R.GhostCount(Cfg.Quality.Low.GhostLights) == 5, "budgets")
end)

test("typewriter: graphemes (Cyrillic counts once), a thud per word, timing", function()
	check(#R.Graphemes("И ЭТО ВСЁ?") == 10 and #R.Graphemes("IS THAT ALL?") == 12, "graphemes")
	local en = R.Typewriter("IS THAT ALL?")
	check(en.Count == 12 and #en.Steps == 10, "EN steps " .. #en.Steps)
	local thuds = 0
	for i, step in ipairs(en.Steps) do
		if step.Thud then
			thuds += 1
		end
		if i > 1 then
			check(step.At > en.Steps[i - 1].At and step.Count > en.Steps[i - 1].Count, "monotonic")
		end
	end
	check(thuds == 3 and en.Steps[#en.Steps].Count == 12, "EN thuds")
	check(near(en.Duration, 10 * Cn.Letter + 3 * Cn.WordGap, 1e-9), "EN duration")
	local ru = R.Typewriter("И ЭТО ВСЁ?")
	local ruThuds = 0
	for _, step in ipairs(ru.Steps) do
		ruThuds += step.Thud and 1 or 0
	end
	check(ru.Count == 10 and #ru.Steps == 8 and ruThuds == 3, "RU")
	-- the FIND OUT button never appears before input is accepted, and not too late
	for _, w in ipairs({ en, ru }) do
		local buttonAt = Cn.TypeAt + w.Duration + Cn.Hold + Cn.LineFade + Cn.ButtonDelay
		check(buttonAt >= Cn.InputAfter and buttonAt <= 12, "button at " .. buttonAt)
	end
	check(Cn.FadeIn + Cn.Silence <= Cn.TypeAt, "silence before the words")
end)

test("doors: latch jolt, heavy swing, a bounce at the stop", function()
	check(R.DoorOpen(0) == 0 and R.DoorOpen(-1) == 0, "closed")
	check(R.DoorOpen(.29) > 0 and R.DoorOpen(.29) < .04, "latch")
	check(R.DoorOpen(Ch.DoorTime) == 1 and R.DoorOpen(Ch.DoorTime + 5) == 1, "open")
	local prev, peak = 0, 0
	for i = 1, 240 do
		local t = i / 240 * Ch.DoorTime
		local f = R.DoorOpen(t)
		peak = math.max(peak, f)
		if t < .3 + (Ch.DoorTime - .3) * .82 then
			check(f >= prev - 1e-9, "monotonic swing at " .. t)
		end
		prev = f
	end
	check(peak <= 1.02 and peak > 1, "bounce")
	-- both leaves swing INTO the chamber (+Z)
	local hingeL = CFrame.new(125, 6.875, 729.93)
	local hingeR = CFrame.new(131, 6.875, 729.93)
	local tipL = (R.DoorPivot(hingeL, -100, 1) * CFrame.new(2.86, 0, 0)).Position
	local tipR = (R.DoorPivot(hingeR, 100, 1) * CFrame.new(-2.86, 0, 0)).Position
	check(tipL.Z > 732 and tipR.Z > 732, "inward")
	check(tipL.X > 124 and tipL.X < 126 and tipR.X > 130 and tipR.X < 132, "against the side walls")
	check((R.DoorPivot(hingeL, -100, 0).Position - hingeL.Position).Magnitude < 1e-6, "closed pivot")
end)

test("cracks spread from the door outwards", function()
	check(R.CrackAlpha(.5, 0) == 0 and R.CrackAlpha(1, 1) == 1 and R.CrackAlpha(0, 1) == 1, "ends")
	check(R.CrackAlpha(.2, .3) > R.CrackAlpha(.6, .3), "near cracks first")
	local prev = 0
	for i = 0, 50 do
		local a = R.CrackAlpha(.4, i / 50)
		check(a >= prev, "monotonic")
		prev = a
	end
end)

test("portal transition: stretch, eye flash, black at 1.4 s; fade in", function()
	local s0 = R.Transition(0)
	check(s0.Black == 0 and s0.Fov == 0 and s0.Eye == 0, "start")
	local s1 = R.Transition(Cp.Stretch)
	check(near(s1.Fov, Cp.FovAdd) and near(s1.Saturation, -1) and s1.Squash > .8, "stretched")
	local peak = 0
	for i = 0, 40 do
		local t = Cp.Stretch + i / 40 * Cp.Eye
		peak = math.max(peak, R.Transition(t).Flash)
		check(R.Transition(t).Eye >= 0, "eye")
	end
	check(peak > .9, "the moon flashes")
	check(R.Transition(Cp.Black - .1).Black == 0 and R.Transition(Cp.Black).Black == 1, "black at " .. Cp.Black)
	local prev = 0
	for i = 0, 60 do
		local b = R.Transition(i / 60 * 2).Black
		check(b >= prev, "black monotonic")
		prev = b
	end
	check(R.FadeIn(0).Black == 1 and R.FadeIn(Cp.FadeIn).Black == 0, "fade in")
	check(near(R.FadeIn(Cp.FadeIn * 1.4).Saturation, 0) and near(R.FadeIn(Cp.FadeIn).Squash, 0), "colour and bars back")
end)

test("edge cracks: deterministic, on screen, from the edges", function()
	local a, b = R.EdgeCracks(1031, 7), R.EdgeCracks(1031, 7)
	check(serde.encode("json", a) == serde.encode("json", b), "deterministic")
	check(serde.encode("json", a) ~= serde.encode("json", R.EdgeCracks(77, 7)), "seeded")
	check(#a >= 7, "count")
	for i, crack in ipairs(a) do
		for _, p in ipairs(crack.Points) do
			check(p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1, "on screen")
		end
		check(crack.Width > 0 and crack.Delay >= 0 and crack.Delay < 1, "width / delay")
	end
	local first = a[1].Points[1]
	check(first[1] == 0 or first[1] == 1 or first[2] == 0 or first[2] == 1, "starts at an edge")
end)

test("cinematic script: silence, three tolls, doors, portal, title, within 16 s", function()
	local beats = R.Beats()
	local at = {}
	for i, b in ipairs(beats) do
		at[b.Name] = b.T
		if i > 1 then
			check(b.T >= beats[i - 1].T, "sorted")
		end
	end
	check(at.Begin == 0 and at.End == Ch.Duration, "span")
	check(at.Boom1 - at.Arrive >= Ch.Silence - 1e-9, "silence after the camera arrives")
	check(at.Boom2 - at.Boom1 >= 2 and at.Boom3 - at.Boom2 >= 2, "tolls apart")
	check(at.Doors > at.Boom3 and at.Portal > at.Doors and at.Title > at.Portal and at.Relight > at.Title, "order")
	check(at.Doors + Ch.DoorTime < Ch.Duration and at.Title + Ch.TitleTime <= Ch.Duration, "everything finishes")
	check(Ch.SkipAfter < at.Boom1, "skippable before the first toll")
	local shots = R.Shots()
	check(shots[1].T == 0 and shots[#shots].T == Ch.Duration, "shot span")
	local door = R.Church.Door
	for i, k in ipairs(shots) do
		check(k.Eye.Y > 2 and k.Eye.Y < 8, "a low shot")
		check(k.Fov >= 40 and k.Fov <= 80, "fov")
		check((k.At - door).Magnitude < 30, "looks at the church")
		check(k.Eye.Z < door.Z, "in front of the door")
		if i > 1 then
			check(k.T > shots[i - 1].T, "keys sorted")
		end
	end
	check((shots[#shots].Eye - door).Magnitude < (shots[1].Eye - door).Magnitude, "pushes in")
end)

-----------------------------------------------------------------------------------------------------------------------
-- 3. the church edit in the shipped place
-----------------------------------------------------------------------------------------------------------------------
local PLACE = "place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl"
test("church edit: idempotent in the shipped place", function()
	if not fs.isFile(PLACE) then
		print("     (no " .. PLACE .. ": skipped)")
		return
	end
	local Sim = require("../tools/sim")
	local game = roblox.deserializePlace(fs.readFile(PLACE))
	local SS = game:GetService("ServerStorage")
	local HB = SS:FindFirstChild("HalloweenBuild")
	if not HB then
		HB = roblox.Instance.new("Folder")
		HB.Name = "HalloweenBuild"
		HB.Parent = SS
	end
	for _, name in ipairs({ "Kit", "YardKit", "Church" }) do
		local m = HB:FindFirstChild(name)
		if not m then
			m = roblox.Instance.new("ModuleScript")
			m.Name = name
			m.Parent = HB
		end
		m.Source = fs.readFile("src/ServerStorage/HalloweenBuild/" .. name .. ".luau")
	end
	local edit = luau.load(fs.readFile("tools/edits/38_church.luau"), { debugName = "38_church" })()
	local yard = game:GetService("Workspace").DOGROTS_District["38_DeadYard"]
	local function run()
		local report = {}
		edit({ game = game, sim = Sim.new(game), report = report, roblox = roblox, fs = fs, serde = serde })
		return report
	end
	local function snapshot()
		local churches = 0
		for _, c in ipairs(yard:GetChildren()) do
			if c.Name == "Church" then
				churches += 1
			end
		end
		local church = yard:FindFirstChild("Church")
		local parts, cf = 0, {}
		for _, d in ipairs(church:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				local p = d.CFrame.Position
				table.insert(cf, string.format("%s %.3f %.3f %.3f %.3f", d.Name, p.X, p.Y, p.Z, d.Transparency))
			end
		end
		table.sort(cf)
		local anchors = 0
		for _, a in ipairs(yard.Anchors:GetChildren()) do
			if a.Name == "Portal" then
				anchors += 1
			end
		end
		return { Churches = churches, Parts = parts, Sig = table.concat(cf, "|"), Anchors = anchors }
	end
	local r1 = run()
	check(r1.Skipped == nil, "skipped: " .. tostring(r1.Skipped))
	local s1 = snapshot()
	-- the originals the chamber replaced: hidden, first values recorded
	local hidden = {}
	for _, d in ipairs(yard.Crypts.GrandCrypt:GetChildren()) do
		if d:IsA("BasePart") and d:GetAttribute("Halloween_OriginalTransparency") ~= nil and d.Transparency == 1
			and (d.Name == "CellaCore" or d.Name == "CryptDoorLeaf") then
			table.insert(hidden, d)
		end
	end
	check(#hidden >= 3, "core + old leaves hidden (" .. #hidden .. ")")
	for _, d in ipairs(hidden) do
		check(d:GetAttribute("Halloween_OriginalTransparency") < 1, d.Name .. " original recorded")
		check(d.CanCollide == false, d.Name .. " no longer collides")
	end
	local r2 = run()
	local s2 = snapshot()
	check(s1.Churches == 1 and s2.Churches == 1, "one Church model")
	check(s1.Parts == s2.Parts and s1.Parts == r1.Parts and r2.Parts == r1.Parts, "same part count")
	check(s1.Sig == s2.Sig, "identical geometry on the second run")
	check(s2.Anchors == 1, "one Anchors.Portal")
	check(r2.AnchorCreated == nil, "the anchor is reused")
	for _, d in ipairs(hidden) do
		check(d:GetAttribute("Halloween_OriginalTransparency") < 1, d.Name .. " original kept on the second run")
	end
	local church = yard.Church
	check(church:GetAttribute("ChurchEdit") ~= nil, "version attribute")
	for _, name in ipairs({ "ChurchDoorL", "ChurchDoorR" }) do
		local door = church[name]
		check(door.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, name .. " atomic")
		check(door.PrimaryPart and door.PrimaryPart.Name == "Hinge", name .. " hinge")
		local closed = door:GetAttribute("ClosedPivot")
		check(typeof(closed) == "CFrame" and (door.PrimaryPart.CFrame.Position - closed.Position).Magnitude < 1e-4, name .. " closed")
		check(math.abs(door:GetAttribute("OpenAngle")) == 100, name .. " angle")
		local leaf = door:FindFirstChild("Leaf", true)
		check(leaf and leaf.CanCollide and leaf.Transparency == 0, name .. " solid leaf")
	end
	local portal = church.ChurchPortal
	check(portal:GetAttribute("ChurchPortal") == true and portal.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "portal model")
	local portalParts = 0
	for _, d in ipairs(portal:GetDescendants()) do
		if d:IsA("BasePart") then
			portalParts += 1
			check(d.Transparency == 1 and not d.CanCollide and type(d:GetAttribute("RevealT")) == "number", "portal part hidden: " .. d.Name)
		elseif d:IsA("Light") then
			check(d.Brightness == 0 and type(d:GetAttribute("RevealBrightness")) == "number", "portal light dark")
		end
	end
	check(portalParts > 40, "a real portal (" .. portalParts .. " parts)")
	local cracks = 0
	for _, d in ipairs(church.ChurchCracks:GetDescendants()) do
		if d:IsA("BasePart") then
			cracks += 1
			check(d.Transparency == 1 and not d.CanCollide and type(d:GetAttribute("CrackT")) == "number", "crack hidden")
		end
	end
	check(cracks > 20, "cracks " .. cracks)
	check(church.ChurchSlit:GetAttribute("ChurchSlit") == true and church.ChurchSlit.Transparency < 1, "slit glows")
	local dust, fog = 0, 0
	for _, d in ipairs(church.ChurchFX:GetDescendants()) do
		if d:IsA("Attachment") then
			dust += d.Name == "ChurchDust" and 1 or 0
			fog += d.Name == "ChurchFog" and 1 or 0
		end
	end
	check(dust >= 7 and fog >= 4, "dust / fog attachments")
	local anchor = yard.Anchors.Portal
	check((anchor.CFrame.Position - V(128, 3, 729)).Magnitude < .01, "anchor position")
end)

-----------------------------------------------------------------------------------------------------------------------
-- 4. the client (HalloweenClient.Reveal) headless
-----------------------------------------------------------------------------------------------------------------------
local CE = require("./lib/client_env")
local RS = CE.MountReplicated()
local hcFolder = CE.Folder("HalloweenClient", CE.Player:FindFirstChild("PlayerScripts"))
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", hcFolder)

-- recorders and fakes
local log = { Locks = {}, Unlocks = {}, Ducks = {}, Releases = {}, Cues = {}, Shows = {}, Clears = {}, Toasts = {}, Objectives = {} }
local function countOf(list, value)
	local n = 0
	for _, v in ipairs(list) do
		if v == value then
			n += 1
		end
	end
	return n
end
CE.Overrides["ReplicatedStorage/AudioMixer"] = {
	Duck = function(reason, levels, fade)
		table.insert(log.Ducks, reason)
	end,
	Release = function(reason, fade)
		table.insert(log.Releases, reason)
	end,
}
local pgActive = nil
local PG = { Changed = CE.Signal.new(), AheadFrom = V(60, 0.5, 600) }
function PG.Show(key, opts)
	table.insert(log.Shows, { Key = key, Opts = opts })
	pgActive = { Key = key, Remaining = 321 }
	return true
end
function PG.Active()
	return pgActive
end
function PG.Clear(reason)
	table.insert(log.Clears, reason)
	pgActive = nil
end
function PG.Ahead(spacing, count, lead)
	local out = {}
	if not pgActive then
		return out
	end
	for i = 1, count do
		table.insert(out, PG.AheadFrom + V(0, 0, (lead or 0) + (i - 1) * spacing))
	end
	return out
end
CE.Overrides["ReplicatedStorage/Navigation/PathGuide"] = PG

local mainGui = CE.Instance.new("ScreenGui")
mainGui.Name = "ScreenGui"
local mods = CE.Folder("Modules", mainGui)
local navInst = CE.Instance.new("ModuleScript")
navInst.Name = "GUIIntegration"
navInst.Parent = mods
mainGui.Parent = CE.PlayerGui
CE.Overrides["ScreenGui/Modules/GUIIntegration"] = {
	LockControls = function(reason)
		table.insert(log.Locks, reason)
	end,
	UnlockControls = function(reason)
		table.insert(log.Unlocks, reason)
	end,
}

-- a cinema that runs its timeline on the fake clock like HalloweenClient.Cinema (Always entries on a skip, OnDone once)
local cin = { Plays = {}, Titles = {}, Hidden = {}, Shown = {}, Active = nil, Refuse = nil }
function cin.Busy()
	return cin.Active ~= nil, cin.Active and cin.Active.Id
end
function cin.Play(o)
	if cin.Refuse or cin.Active then
		local why = cin.Refuse or "Busy"
		if o.OnDone then
			o.OnDone(false, why)
		end
		return nil, why
	end
	local run = { Id = o.Id, Opts = o, T0 = CE.Now, Fired = {}, Done = false }
	local timeline = {}
	for _, e in ipairs(o.Timeline or {}) do
		table.insert(timeline, { T = e[1], Fn = e[2], Always = e.Always == true })
	end
	table.sort(timeline, function(a, b)
		return a.T < b.T
	end)
	local function fire(e)
		if not e.Done then
			e.Done = true
			local ok, err = pcall(e.Fn, run)
			if not ok then
				table.insert(CE.Errors, "timeline: " .. tostring(err))
			end
		end
	end
	function run.Finish(ok, reason)
		if run.Done then
			return
		end
		run.Done = true
		if run.Conn then
			run.Conn:Disconnect()
		end
		cin.Active = nil
		if o.OnDone then
			o.OnDone(ok, reason, run)
		end
	end
	function run.Skip()
		if run.Done then
			return
		end
		if o.OnSkip then
			o.OnSkip(run)
		end
		for _, e in ipairs(timeline) do
			if e.Always then
				fire(e)
			end
		end
		run.Finish(true, "Skipped")
	end
	function run.Cancel(reason)
		run.Finish(false, reason or "Cancelled")
	end
	run.Conn = CE.Service("RunService").Heartbeat:Connect(function()
		local t = CE.Now - run.T0
		for _, e in ipairs(timeline) do
			if e.T <= t then
				fire(e)
			end
		end
		if o.Shot then
			o.Shot(math.min(t, o.Duration or 0))
		end
		if t >= (o.Duration or 0) then
			run.Finish(true, "Done")
		end
	end)
	cin.Active = run
	table.insert(cin.Plays, run)
	return run
end
function cin.Cancel(reason)
	if cin.Active then
		cin.Active.Finish(false, reason)
	end
end
function cin.Path(keys)
	return function(t)
		return keys[1][2]
	end
end
function cin.LookAt(a, b)
	return CFrame.lookAt(a, b)
end
function cin.Title(en, ru, opts)
	table.insert(cin.Titles, { En = en, Ru = ru, Opts = opts })
	return { Hide = function() end }
end
function cin.HideUI(reason)
	table.insert(cin.Hidden, reason)
end
function cin.ShowUI(reason)
	table.insert(cin.Shown, reason)
end
function cin.LockControls() end
function cin.Unlock() end
function cin.Shake() end
function cin.Impulse() end
function cin.Flash() end

local cs = { E = false, Seen = false, Notified = false, Entered = false, Reply = true, Requests = {} }
local CS = {
	Eligible = function()
		return cs.E
	end,
	RevealSeen = function()
		return cs.Seen
	end,
	Notified = function()
		return cs.Notified
	end,
	Entered = function()
		return cs.Entered
	end,
	Request = function(action, args)
		table.insert(cs.Requests, action)
		return cs.Reply, nil
	end,
}
local audio = {
	Play = function(cue, where, opts)
		table.insert(log.Cues, cue)
	end,
	Loop = function(cue)
		table.insert(log.Cues, cue)
		return { Stop = function() end }
	end,
	Has = function()
		return true
	end,
}
local fxFolder = CE.Folder("HalloweenFX", CE.Workspace)

-- a small church with the edit's contract (38_DeadYard.Church + Anchors.Portal with the DESCEND prompt)
local district = CE.Model("DOGROTS_District", CE.Workspace)
local yard = CE.Model("38_DeadYard", district)
local churchModel = CE.Model("Church", yard)
local function door(name, x, side)
	local m = CE.Model(name, churchModel)
	local hinge = CE.Part("Hinge", V(x, 6.875, 729.93), V(.3, 8.9, .3), m)
	local leaf = CE.Part("Leaf", V(x - side * 1.43, 6.875, 729.93), V(2.86, 8.9, .3), m)
	local rune = CE.Part("SealRune", V(x - side * 2.6, 8.5, 729.7), V(.4, .4, .1), m)
	rune:SetAttribute("SealRune", true)
	rune.Color = roblox.Color3.fromRGB(150, 80, 230)
	leaf.Color = roblox.Color3.fromRGB(46, 48, 58)
	m.PrimaryPart = hinge
	m:SetAttribute("ChurchDoor", true)
	m:SetAttribute("OpenAngle", side < 0 and -100 or 100)
	m:SetAttribute("ClosedPivot", hinge.CFrame)
	return m, leaf
end
local doorL, leafL = door("ChurchDoorL", 125, -1)
local doorR, leafR = door("ChurchDoorR", 131, 1)
local LEAF_L0 = leafL.CFrame
local slit = CE.Part("ChurchSlit", V(128, 6.875, 730.13), V(.18, 8.6, .06), churchModel)
slit:SetAttribute("ChurchSlit", true)
slit:SetAttribute("RevealT", .25)
slit.Transparency = .25
slit.Color = roblox.Color3.fromRGB(120, 58, 196)
local portalModel = CE.Model("ChurchPortal", churchModel)
portalModel:SetAttribute("ChurchPortal", true)
portalModel:SetAttribute("Centre", V(128, 7, 735.2))
local portalParts = {}
for i, t in ipairs({ .02, .3, .12 }) do
	local p = CE.Part(({ "PortalDisc", "PortalGlow", "PortalCore" })[i], V(128, 7, 735.2 + i * .01), V(6, 6, .1), portalModel)
	p:SetAttribute("RevealT", t)
	p.Transparency = 1
	portalParts[p.Name] = p
end
local ring = CE.Model("PortalRingB", portalModel)
ring:SetAttribute("Spin", .55)
ring:SetAttribute("Wobble", .08)
local ringParts = {}
for i = 1, 4 do
	local a = i / 4 * math.pi * 2
	local p = CE.Part("RingSeg", V(128 + math.cos(a) * 3.8, 7 + math.sin(a) * 3.8, 735.2), V(.4, 1.2, .2), ring)
	p:SetAttribute("RevealT", .05)
	p.Transparency = 1
	table.insert(ringParts, { Part = p, CF = p.CFrame })
end
local crackModel = CE.Model("ChurchCracks", churchModel)
local crackParts = {}
for i = 1, 6 do
	local p = CE.Part(i % 2 == 0 and "CrackGlow" or "CrackEdge", V(128 + i, 2.4, 718 - i), V(.3, .05, 2), crackModel)
	p:SetAttribute("CrackT", (i - 1) / 5)
	p:SetAttribute("RevealT", i % 2 == 0 and .05 or 0)
	p.Transparency = 1
	table.insert(crackParts, p)
end
local moonTower = CE.Model("MoonTower", yard)
local shaft = CE.Part("TowerShaft", V(128, 20, 737.5), V(8, 26, 8), moonTower)
CE.Part("BellYoke", V(128, 37.65, 737.5), V(4, .5, .5), moonTower)
local bell = CE.Part("Bell", V(128, 36.3, 737.5), V(3, 3, 3), moonTower)
local SHAFT0, BELL0 = shaft.CFrame, bell.CFrame
local crypts = CE.Model("Crypts", yard)
local grand = CE.Model("GrandCrypt", crypts)
local lancet = CE.Part("LancetGlass", V(122, 9, 727.9), V(1, 3, .2), grand)
lancet.Material = Enum.Material.Neon
lancet.Color = roblox.Color3.fromRGB(150, 200, 255)
lancet:SetAttribute("HwLantern", true)
local anchors = CE.Model("Anchors", yard)
local anchorPart = CE.Part("Portal", V(128, 3, 729), V(1, 1, 1), anchors)
local prompt = CE.Instance.new("ProximityPrompt")
prompt.Name = "UnderyardDescendPrompt"
prompt.Enabled = true
prompt:SetAttribute("ActionTextRU", "СПУСТИТЬСЯ")
prompt.Parent = anchorPart

local Bus = CE.Require(RS.Halloween.Bus)
Bus.On("Toast", function(d)
	table.insert(log.Toasts, d.Text)
end)
Bus.On("C2Objective", function(d)
	table.insert(log.Objectives, d and d.Key or "none")
end)
local Reveal = CE.Require(hcFolder.Reveal)
local St = Reveal.State
local FAR = V(0, 3, 377)
CE.Spawn(FAR)
Reveal.Start({ Modules = { Cinema = cin, Chapter2State = CS }, Audio = audio, FX = { Folder = function()
	return fxFolder
end } })

local function revealGui()
	return CE.PlayerGui:FindFirstChild("DOGROTS_Reveal")
end
local function noteT()
	local n = St.Note.Current
	return n and (CE.Now - n.T0 + n.Offset) or -1
end
local function advanceTo(t)
	while noteT() >= 0 and noteT() < t do
		CE.Step(1 / 20)
	end
end
local function key(code)
	CE.UserInputService.InputBegan:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
end
-- every control lock of `reason` released (the audio duck is checked where it ends: at the teardown)
local function balanced(reason)
	return countOf(log.Locks, reason) == countOf(log.Unlocks, reason)
end
local function ghostLights()
	local n = 0
	for _, d in ipairs(fxFolder:GetDescendants()) do
		if d.Name == "GhostLight" then
			n += 1
		end
	end
	return n
end

test("client: the notification waits for a free, stable moment", function()
	cs.E, cs.Notified = true, false
	mainGui:SetAttribute("OpenMenu", "Shop")
	CE.Advance(5)
	check(not St.Note.Showing and revealGui() == nil, "not over a menu")
	mainGui:SetAttribute("OpenMenu", nil)
	CE.Advance(1)
	check(not St.Note.Showing, "waits for a stable moment")
	CE.Advance(2.2)
	check(St.Note.Showing and revealGui() ~= nil, "shown")
	local g = revealGui()
	check(g.DisplayOrder == 88 and g.IgnoreGuiInset == true and g.ResetOnSpawn == false, "own ScreenGui")
	check(countOf(log.Locks, "Reveal") == 1 and countOf(log.Ducks, "Reveal") == 1, "controls frozen, audio ducked")
	local run = cin.Active
	check(run and run.Id == "Reveal" and run.Opts.HideUI == true and run.Opts.LockControls == false and run.Opts.Shot == nil, "a shotless Cinema run")
end)

test("client: typewriter, the input gate, FIND OUT, teardown, C2Notified, the guide", function()
	local n = St.Note.Current
	local g = revealGui()
	local word = g.Root.Word
	check(word.Text == "IS THAT ALL?" and word.MaxVisibleGraphemes == 0, "starts empty")
	advanceTo(Cn.TypeAt + .3)
	check(word.MaxVisibleGraphemes > 0 and word.MaxVisibleGraphemes < 12, "typing " .. word.MaxVisibleGraphemes)
	-- nothing before 4 s: not the button, not Esc, not Enter
	CE.Click(g.Root.FindOutHolder.FindOut)
	key(Enum.KeyCode.Escape)
	key(Enum.KeyCode.Return)
	check(not n.Pressed and n.Offset == 0, "the first 4 s ignore input")
	advanceTo(n.ButtonAt + .3)
	check(countOf(log.Cues, "RevealWord") == 3, "a thud per word")
	check(countOf(log.Cues, "BellTollFar") == 1, "the distant toll")
	check(word.MaxVisibleGraphemes == 12, "the whole line")
	check(g.Root.Line.TextTransparency < .2 and g.Root.Line.Text == "Did you really think it would be that easy?", "second line")
	local holder = g.Root.FindOutHolder
	check(holder.Visible and holder.FindOut.Text == "FIND OUT", "the button")
	check(holder.FindOut.AbsoluteSize.Y >= 64, "at least 64 px tall")
	check(g.Root.Eye.AbsoluteSize.Y > 20, "the eye opened")
	local lit = 0
	for _, d in ipairs(g.Root.Cracks:GetChildren()) do
		if d.Name == "Crack" and d.BackgroundTransparency < 1 then
			lit += 1
		end
	end
	check(lit > 5, "light cracks " .. lit)
	check(g.Root.Shade.BackgroundTransparency < .01, "black")
	local before = #cs.Requests
	CE.Click(holder.FindOut)
	check(n.Pressed, "pressed")
	check(countOf(log.Cues, "RevealHit") == 1, "the bell-strike")
	CE.Advance(1)
	check(revealGui() == nil and not St.Note.Showing, "the overlay is gone")
	check(balanced("Reveal") and countOf(log.Releases, "Reveal") == countOf(log.Ducks, "Reveal"), "controls and audio back")
	check(cin.Active == nil, "the Cinema run ended")
	CE.Advance(.5)
	check(#cs.Requests == before + 1 and cs.Requests[#cs.Requests] == "C2Notified", "C2Notified sent once")
	check(#log.Shows == 1 and log.Shows[1].Key == "Church" and log.Shows[1].Opts.Label == false, "PathGuide.Show(Church)")
	check(St.Guide.Active and ghostLights() == 12, "12 ghost lights (High)")
	check(log.Objectives[#log.Objectives] == "Church", "objective church")
	check(log.Toasts[#log.Toasts] == "The church is waiting. Follow the ghost lights.", "toast")
	-- the server has not confirmed yet: it must not come back
	CE.Advance(6)
	check(not St.Note.Showing, "shown once")
end)

test("client: ghost lights follow the route; the guide clears with it", function()
	CE.Advance(1)
	local lights = {}
	for _, d in ipairs(fxFolder:GetDescendants()) do
		if d.Name == "GhostLight" then
			table.insert(lights, d)
		end
	end
	local firstZ = math.huge
	for _, l in ipairs(lights) do
		check(l.Transparency < .5, "visible")
		firstZ = math.min(firstZ, l.CFrame.Position.Z)
	end
	check(math.abs(firstZ - (PG.AheadFrom.Z + R.Config.Guide.Lead)) < 1.5, "the first light leads by " .. R.Config.Guide.Lead)
	local marker = nil
	for _, d in ipairs(fxFolder:GetDescendants()) do
		if d.Name == "Marker" then
			marker = d
		end
	end
	check(marker and marker.Card.Title.Text == "THE CHURCH", "marker")
	CE.Advance(3.5)
	check(marker.Card.Sub.Text == "321 m", "distance " .. marker.Card.Sub.Text)
	pgActive = nil
	PG.Changed:Fire(nil, "arrived", "Church")
	CE.Advance(.2)
	check(not St.Guide.Active and ghostLights() == 0, "cleared")
	check(log.Objectives[#log.Objectives] == "none", "objective cleared")
end)

test("client: a replay shows the notification without any request; Esc finds out after 4 s", function()
	cs.Notified = true
	local before = #cs.Requests
	local shows = #log.Shows
	Bus.Fire("C2Replay", { Id = "Reveal" })
	check(St.Note.Showing, "replay shown although notified")
	local n = St.Note.Current
	advanceTo(2)
	key(Enum.KeyCode.Escape)
	check(not n.Pressed, "not before 4 s")
	advanceTo(4.1)
	key(Enum.KeyCode.Escape)
	check(n.Pressed, "Esc = find out")
	CE.Advance(1.5)
	check(revealGui() == nil and balanced("Reveal"), "torn down")
	check(#cs.Requests == before and #log.Shows == shows, "no request, no guide")
end)

test("client: an interrupted notification restores everything and comes back; the watchdog presses", function()
	cs.Notified = false
	St.Note.Sent = nil
	CE.Advance(3.5)
	check(St.Note.Showing, "shown again")
	cin.Cancel("Dead")
	CE.Advance(.1)
	check(revealGui() == nil and not St.Note.Showing and balanced("Reveal"), "torn down on death")
	local before = #cs.Requests
	CE.Advance(4)
	check(St.Note.Showing, "comes back")
	CE.Advance(R.Config.Notify.AutoPress + 2, .1)
	check(not St.Note.Showing and revealGui() == nil and balanced("Reveal"), "the watchdog found out")
	check(cs.Requests[#cs.Requests] == "C2Notified" and #cs.Requests == before + 1, "and reported it")
	cs.Notified = true
	Reveal.StopGuide("test")
end)

local function doorF(leaf)
	return (leaf.CFrame.Position - LEAF_L0.Position).Magnitude
end

test("client: the church end state is per player; the prompt is hidden for ineligible players", function()
	cs.E, cs.Seen = false, false
	CE.Advance(.6)
	check(prompt.Enabled == false, "prompt hidden")
	check((leafL.CFrame.Position - LEAF_L0.Position).Magnitude < 1e-4, "doors closed")
	for _, p in pairs(portalParts) do
		check(p.Transparency == 1, "portal hidden")
	end
	cs.E, cs.Seen = true, true
	CE.Advance(.6)
	check(prompt.Enabled == true, "prompt shown")
	check(leafL.CFrame.Position.Z > 731 and leafR.CFrame.Position.Z > 731, "doors open inward")
	check(near(portalParts.PortalDisc.Transparency, .02, 1e-6) and near(portalParts.PortalGlow.Transparency, .3, 1e-6), "portal at RevealT")
	check(crackParts[6].Transparency < 1 and crackParts[1].Transparency < 1, "cracks glow")
	check(slit.Transparency == 1, "slit dark")
	-- the open portal lives while the camera is near: the rings turn round the portal's centre
	CE.Camera.CFrame = CFrame.new(128, 8, 700)
	CE.Advance(1)
	local moved = (ringParts[1].Part.CFrame.Position - ringParts[1].CF.Position).Magnitude
	check(moved > .05, "rings turn (" .. moved .. ")")
	for _, rp in ipairs(ringParts) do
		local r = (rp.Part.CFrame.Position - V(128, 7, 735.2)).Magnitude
		check(math.abs(r - 3.8) < .05, "on their circle")
	end
	cs.E, cs.Seen = false, false
	CE.Advance(.6)
	for _, rp in ipairs(ringParts) do
		check((rp.Part.CFrame.Position - rp.CF.Position).Magnitude < 1e-4, "rings back in place")
	end
	CE.Camera.CFrame = CFrame.new(0, 10, 20)
	check((leafL.CFrame.Position - LEAF_L0.Position).Magnitude < 1e-4 and portalParts.PortalDisc.Transparency == 1, "closed again")
	check(crackParts[6].Transparency == 1 and slit.Transparency < .5, "cracks hidden, slit glowing")
end)

test("client: the teaser plays for an ineligible player within 70 studs", function()
	cs.E, cs.Seen = false, false
	CE.MoveTo(V(128, 3, 662))
	local tolls = countOf(log.Cues, "BellToll")
	CE.Advance(13, .1)
	check(countOf(log.Cues, "BellToll") == tolls + 1 and St.Teaser.Count == 1, "one quiet toll")
	CE.MoveTo(FAR)
	CE.Advance(8, .1)
	check(not St.Teaser.Playing and fxFolder:FindFirstChild("RevealTeaserText") == nil, "finished and cleaned up")
	-- an eligible player gets no teaser (the cinematic is theirs)
	cs.E, cs.Notified = true, true
	CE.MoveTo(V(128, 3, 660)) -- 64 studs: outside the cinematic's 46
	CE.Advance(20, .1)
	check(St.Teaser.Count == 1, "no teaser for eligible players")
	check(#cin.Plays == 4, "no cinematic outside 46 studs (" .. #cin.Plays .. " runs)")
end)

test("client: the church cinematic on the first approach", function()
	cs.E, cs.Seen, cs.Notified = true, false, true
	local before = #cs.Requests
	CE.MoveTo(V(128, 3, 690))
	CE.Advance(.6)
	local run = cin.Active
	check(run and run.Id == "Church", "playing")
	local o = run.Opts
	check(o.Skippable and o.SkipAfter == 3 and o.LockControls and o.Letterbox and o.HideUI and o.Duration == Ch.Duration, "cinema options")
	check(St.Scene.Playing, "scene")
	local function sceneTo(t)
		while cin.Active == run and CE.Now - run.T0 < t do
			CE.Step(.05)
		end
	end
	sceneTo(Ch.Booms[1] + .2)
	check((shaft.CFrame.Position - SHAFT0.Position).Magnitude > .01, "BOOM #1 shakes the tower")
	check((bell.CFrame.Position - BELL0.Position).Magnitude > .01 or not (bell.CFrame == BELL0), "the bell swings")
	sceneTo(Ch.Booms[1] + Ch.TowerShake + .3)
	check((shaft.CFrame.Position - SHAFT0.Position).Magnitude < 1e-4, "the shake settles")
	sceneTo(Ch.Booms[2] + Ch.Windows + .5)
	check(lancet.Material == Enum.Material.SmoothPlastic and lancet:GetAttribute("HwLocalDim") == .02, "BOOM #2: the windows die")
	sceneTo(Ch.DoorsAt + .9)
	check(St.Church.Doors > 0 and St.Church.Doors < 1, "doors swinging " .. St.Church.Doors)
	CE.Advance(Ch.Duration - Ch.DoorsAt, .05)
	check(cin.Active == nil and not St.Scene.Playing, "ended")
	check(lancet.Material == Enum.Material.Neon and lancet:GetAttribute("HwLocalDim") == nil, "the windows relit")
	check(shaft.CFrame == SHAFT0 and bell.CFrame == BELL0, "the tower and the bell exactly back")
	check(countOf(log.Cues, "BellTollHuge") >= 3 and countOf(log.Cues, "ChurchCreak") == 1 and countOf(log.Cues, "PortalOpen") == 1
		and countOf(log.Cues, "GroundCrack") == 1, "three tolls, the creak, the portal, the cracks")
	local title = cin.Titles[#cin.Titles]
	check(title and title.En == "THE UNDERYARD" and title.Opts.Sub[1] == "BENEATH THE LAST BELL", "title card")
	CE.Advance(.3)
	check(cs.Requests[#cs.Requests] == "C2RevealSeen" and #cs.Requests == before + 1, "C2RevealSeen")
	check(St.Scene.Pending, "pending until the server confirms")
	check(St.Church.Doors == 1 and St.Church.Portal == 1, "open")
	check(leafL.CFrame.Position.Z > 731, "the doors stay open")
	check(log.Objectives[#log.Objectives] == "Descend", "objective descend")
	cs.Seen = true
	CE.Advance(3)
	check(not St.Scene.Pending and #cin.Plays == 5, "confirmed, no second run")
	check(leafL.CFrame.Position.Z > 731 and portalParts.PortalDisc.Transparency < .1, "the open church persists")
end)

test("client: skip jumps to the open end state; a refused request closes the church again", function()
	cs.Seen = false
	St.Scene.Pending = false
	St.Scene.CooldownUntil = 0
	cs.Reply = false
	CE.Advance(.6)
	local run = cin.Active
	check(run and run.Id == "Church", "playing again")
	CE.Advance(3.5)
	local before = #cs.Requests
	run.Skip()
	check(St.Church.Doors == 1 and St.Church.Portal == 1 and not St.Scene.Playing, "end state after the skip")
	CE.Advance(4)
	check(#cs.Requests == before + 3, "three attempts (" .. (#cs.Requests - before) .. ")")
	check(not St.Scene.Pending and St.Scene.CooldownUntil > CE.Now, "pending cleared, cooldown")
	check((leafL.CFrame.Position - LEAF_L0.Position).Magnitude < 1e-4, "closed again " .. tostring(leafL.CFrame.Position) .. " applied " .. tostring(St.Church.Applied) .. " doors " .. St.Church.Doors .. " pending " .. tostring(St.Scene.Pending) .. " playing " .. tostring(St.Scene.Playing))
	cs.Reply = true
end)

test("client: a cancelled cinematic restores the church and cools down", function()
	St.Scene.CooldownUntil = 0
	CE.Advance(.6)
	local run = cin.Active
	check(run and run.Id == "Church", "playing")
	CE.Advance(Ch.DoorsAt + 1)
	local before = #cs.Requests
	run.Cancel("Dead")
	CE.Advance(.6)
	check(not St.Scene.Playing and #cs.Requests == before, "no request")
	check(St.Scene.CooldownUntil > CE.Now, "cooldown")
	check((leafL.CFrame.Position - LEAF_L0.Position).Magnitude < 1e-4 and portalParts.PortalDisc.Transparency == 1, "closed")
	CE.Advance(Ch.Cooldown + 1)
	check(cin.Active and cin.Active.Id == "Church", "plays again after the cooldown")
	cin.Active.Skip()
	cs.Seen = true
	CE.Advance(2)
end)

local function portalGui()
	return CE.PlayerGui:FindFirstChild("DOGROTS_RevealPortal")
end

test("client: the portal transition down — black before the move, the title on arrival", function()
	local cam = CE.Camera
	local fov0 = cam.FieldOfView
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Down", Stage = "Start" } })
	local g = portalGui()
	check(g and g.DisplayOrder == 89, "transition gui")
	check(countOf(log.Locks, "RevealPortal") == 1 and countOf(cin.Hidden, "RevealPortal") == 1 and countOf(log.Ducks, "RevealPortal") == 1,
		"locked, UI hidden, ducked")
	CE.Advance(.8)
	check(cam.FieldOfView > fov0 + 10, "stretch")
	check(g.Top.AbsoluteSize.Y > 50, "squash bars")
	CE.Advance(.7)
	check(g.Black.BackgroundTransparency == 0 and St.Portal.Current.Phase == "Hold", "black at 1.45 s")
	check(cam.FieldOfView == fov0, "fov reset under the black")
	CE.Advance(2)
	check(St.Portal.Current.Phase == "Hold", "holds until the server arrives")
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Down", Stage = "Arrived", District = "FuneralCarnival" } })
	CE.Advance(.5)
	local title = cin.Titles[#cin.Titles]
	check(title.En == "THE UNDERYARD" and title.Opts.Sub[1] == U.Names.FuneralCarnival[1], "title + district")
	check(balanced("RevealPortal"), "controls back with the picture")
	CE.Advance(2)
	check(portalGui() == nil and not St.Portal.Active, "torn down")
	check(countOf(cin.Shown, "RevealPortal") == 1 and countOf(log.Releases, "RevealPortal") == 1 and cam.FieldOfView == fov0, "restored")
	check(cam:FindFirstChild("DOGROTS_PortalGrade") == nil, "grade removed")
end)

test("client: the portal transition up, a failure, and the watchdog", function()
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Up", Stage = "Start" } })
	CE.Advance(1.6)
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Up", Stage = "Arrived" } })
	CE.Advance(.5)
	check(cin.Titles[#cin.Titles].En == "THE DEAD YARD", "the Dead Yard title")
	CE.Advance(2)
	check(portalGui() == nil, "done")
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Down", Stage = "Start" } })
	CE.Advance(1.6)
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Down", Stage = "Failed" } })
	CE.Advance(3)
	check(portalGui() == nil and log.Toasts[#log.Toasts] == "The portal flickered. Try again.", "failure toast")
	Bus.Fire("C2Signal", { Kind = "C2Portal", Data = { Dir = "Down", Stage = "Start" } })
	CE.Advance(Cp.Black + Cp.HoldMax + Cp.FadeIn * 1.4 + 1, .1)
	check(portalGui() == nil and not St.Portal.Active and balanced("RevealPortal"), "the black never sticks")
	check(countOf(cin.Hidden, "RevealPortal") == countOf(cin.Shown, "RevealPortal"), "UI shown again every time")
end)

test("client: replays (portal, church) send nothing", function()
	local before = #cs.Requests
	Bus.Fire("C2Replay", { Id = "Portal" })
	check(St.Portal.Active, "portal replay")
	CE.Advance(Cp.Black + 3)
	check(portalGui() == nil, "portal replay ends by itself")
	CE.MoveTo(V(0, 3, 377))
	Bus.Fire("C2Replay", { Id = "Church" })
	check(log.Toasts[#log.Toasts] == "Stand near the church to replay this scene.", "too far")
	CE.MoveTo(V(128, 3, 650))
	Bus.Fire("C2Replay", { Id = "Church" })
	check(cin.Active and cin.Active.Id == "Church" and St.Scene.Replay, "church replay")
	CE.Advance(Ch.Duration + 1, .1)
	check(not St.Scene.Playing and #cs.Requests == before, "no request after replays")
	check(leafL.CFrame.Position.Z > 731, "the church stays open for a seen player")
end)

test("client: C2Reveal Need=Church guides from afar, plays nearby", function()
	cs.Seen = false
	St.Scene.Pending = false
	St.Scene.CooldownUntil = math.huge -- keep the approach trigger out of it
	CE.MoveTo(FAR)
	local shows = #log.Shows
	Bus.Fire("C2Signal", { Kind = "C2Reveal", Data = { Need = "Church" } })
	check(#log.Shows == shows + 1 and St.Guide.Active, "guide")
	Reveal.StopGuide("test")
	CE.MoveTo(V(128, 3, 672)) -- 52 studs
	Bus.Fire("C2Signal", { Kind = "C2Reveal", Data = { Need = "Church" } })
	check(cin.Active and cin.Active.Id == "Church", "plays at once nearby")
	cin.Active.Skip()
	cs.Seen = true
	CE.Advance(2)
end)

test("client: Russian", function()
	CE.Player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(6)
	Bus.Fire("C2Replay", { Id = "Reveal" })
	local g = revealGui()
	check(g.Root.Word.Text == "И ЭТО ВСЁ?", "the line")
	check(g.Root.Line.Text == "Вы правда думали, что всё будет настолько просто?", "the second line")
	check(g.Root.FindOutHolder.FindOut.Text == "УЗНАТЬ", "the button")
	check(St.Note.Current.Type.Count == 10, "Cyrillic graphemes")
	advanceTo(St.Note.Current.ButtonAt + .2)
	check(g.Root.Word.MaxVisibleGraphemes == 10, "typed")
	CE.Click(g.Root.FindOutHolder.FindOut)
	CE.Advance(1.5)
	check(revealGui() == nil, "done")
	CE.Player:SetAttribute("DOGROTS_Language", nil)
end)

test("client: the real PathGuide leads to the church without its own label, and out of the Underyard", function()
	CE.Overrides["ReplicatedStorage/Navigation/PathGuide"] = nil
	local Guide = CE.Require(RS.Navigation.PathGuide)
	check(Guide ~= PG and type(Guide.Ahead) == "function", "real module")
	CE.MoveTo(SPAWN + V(0, 2.4, 0))
	local ok, why = Guide.Show("Church", { Label = false })
	check(ok, "Show: " .. tostring(why))
	CE.Advance(.5)
	local st = Guide.Active()
	check(st and st.Key == "Church" and not st.Underyard, "active")
	check(st.Length > 300, "a real route (" .. tostring(st.Length) .. ")")
	local label = CE.Workspace:FindFirstChild("DOGROTS_PathGuide", true)
	label = label and label:FindFirstChild("GoalLabel", true)
	check(label and label.Enabled == false, "Label = false: no name card over the goal")
	Guide.Show("Church")
	check(label.Enabled == true, "the default route keeps its card")
	Guide.Show("Church", { Label = false })
	CE.Advance(.3)
	check(label.Enabled == false, "and loses it again")
	local pts = Guide.Ahead(18, 12, 10)
	check(#pts == 12, "12 ghost-light points (" .. #pts .. ")")
	local feet = SPAWN
	check((V(pts[1].X, 0, pts[1].Z) - V(feet.X, 0, feet.Z)).Magnitude < 14, "the first one leads by ~10 studs")
	for i = 2, #pts do
		local gap = (pts[i] - pts[i - 1]).Magnitude
		check(gap <= 18.5 and gap > 6, "spaced along the route (" .. gap .. ")")
	end
	Guide.Clear("test")
	check(Guide.Active() == nil and #Guide.Ahead(18, 12, 10) == 0, "cleared")
	-- in the Underyard every route first climbs to the arch
	CE.MoveTo(V(150, 2.4, 2240))
	ok, why = Guide.Show("Church")
	check(ok, "Show in the Underyard: " .. tostring(why))
	CE.Advance(.5)
	st = Guide.Active()
	check(st and st.Underyard, "routes to the ASCEND arch")
	local last = Guide.Ahead(10, 200, 0)
	check(#last > 3 and (V(last[#last].X, 0, last[#last].Z) - V(0, 0, 2348)).Magnitude < 12, "ends at the arch")
	Guide.Clear("test")
	CE.Overrides["ReplicatedStorage/Navigation/PathGuide"] = PG
	CE.MoveTo(FAR)
	-- the fake workspace has no BulkMoveTo (PathGuide draws its arrows with it): not this test's subject
	for i = #CE.Errors, 1, -1 do
		if string.find(CE.Errors[i], "missing method 'BulkMoveTo'", 1, true) and string.find(CE.Errors[i], "PathGuide", 1, true) then
			table.remove(CE.Errors, i)
		end
	end
end)

test("client: nothing left behind, no errors", function()
	CE.Advance(6)
	check(revealGui() == nil and portalGui() == nil, "no overlay")
	for _, reason in ipairs({ "Reveal", "RevealPortal" }) do
		check(countOf(log.Locks, reason) == countOf(log.Unlocks, reason), reason .. " locks balanced")
		check(countOf(log.Ducks, reason) == countOf(log.Releases, reason), reason .. " ducks balanced")
	end
	check(CE.Camera:FindFirstChild("DOGROTS_PortalGrade") == nil, "no grade")
	check(#CE.Errors == 0, "errors: " .. table.concat(CE.Errors, "\n"))
	local warnings = {}
	for _, w in ipairs(CE.Warnings) do
		if string.find(w, "Reveal") then
			table.insert(warnings, w)
		end
	end
	check(#warnings == 0, "warnings: " .. table.concat(warnings, "\n"))
end)

print(string.format("reveal: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, w in ipairs(CE.Warnings) do
		print("warning: " .. w)
	end
	for _, e in ipairs(CE.Errors) do
		print("error: " .. e)
	end
	error("reveal tests failed")
end
