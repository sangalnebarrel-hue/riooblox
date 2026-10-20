--!nolint
-- THE UNDERYARD runtime + CHAPTER II onboarding (WP-H2): lune run tests/underyard_runtime.luau
--   1. rules     UnderyardRuntime: the §24.2 pendulum formula on server time, spins / drift / blink / flicker, seal-state
--                resolution (show / hide / light, inherited tags, gates and the Assault), the presence weight incl. Y,
--                the soundscape's theme priority (§24.5, finale stages, overrides), the guide's steps / progress / path /
--                pup, the Trial of the Toll and the Mourner state machines and their hazard shapes
--   2. world     the real Underyard builders (tests/lib/underyard_env): every attribute contract UnderyardFX animates is
--                present and classified (carousel, pendulums, bells, swirl, drift islands, eye lids, moons, flames,
--                FX markers, seal tags with their lights, gate veils, bilingual signs), the practice ring props
--   3. server    ServerScriptService.Halloween.Chapter2Tutorial on the REAL Seals + EventHP with fake players, a fake
--                Chapter2 / Underyard / Strike and a manual clock: tutorial echoes, the Trial of the Toll, the Mourner
--                (dodges, the weak spot, a down and the guide's revive, leaving), the step gate and the prompts
--   4. client    Trials.Toll / Trials.Mourner presenters standalone (the §24.1 contract) and HalloweenClient.Chapter2Guide
--                headless (tests/lib/client_env): card per step, progress, skip, blockers, prompts, the pup, the final card
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")
local Vector3 = roblox.Vector3
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

-- the server modules below run on a manual clock and a tiny scheduler (task.spawn runs at once, wait / delay / defer
-- queue on the clock), set before the first require
local CLK = 0
local T = 1761000000
local queue = {}
local schedErrors = {}
local function resume(th, args)
	if coroutine.status(th) == "dead" then
		return
	end
	local ok, err = coroutine.resume(th, table.unpack(args or {}, 1, args and args.n or 0))
	if not ok then
		table.insert(schedErrors, tostring(err))
	end
end
local Task = {}
function Task.spawn(fn, ...)
	local th = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(th, table.pack(...))
	return th
end
function Task.defer(fn, ...)
	local th = coroutine.create(fn)
	table.insert(queue, { At = CLK, Th = th, Args = table.pack(...) })
	return th
end
function Task.delay(t, fn, ...)
	local th = coroutine.create(fn)
	table.insert(queue, { At = CLK + (tonumber(t) or 0), Th = th, Args = table.pack(...) })
	return th
end
function Task.wait(t)
	local th = coroutine.running()
	table.insert(queue, { At = CLK + math.max(tonumber(t) or 0, 1 / 60), Th = th, Args = table.pack() })
	coroutine.yield()
	return t
end
function Task.cancel() end
local function runDue()
	for _ = 1, 10000 do
		local best, bi = nil, nil
		for i, q in ipairs(queue) do
			if q.At <= CLK + 1e-9 and (best == nil or q.At < best.At) then
				best, bi = q, i
			end
		end
		if not best then
			return
		end
		table.remove(queue, bi)
		resume(best.Th, best.Args)
	end
end
L.Task = Task
L.Workspace = setmetatable({
	GetServerTimeNow = function()
		return T
	end,
	FindFirstChild = function()
		return nil
	end,
}, { __index = function()
	return nil
end })
L.Time = T

local R = L.Require("ReplicatedStorage.Halloween.UnderyardRuntime")
local Layout = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local Hazards = L.Require("ReplicatedStorage.Halloween.Hazards")
local Cfg2 = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local TAU = math.pi * 2

-----------------------------------------------------------------------------------------------------------------------
-- 1. rules
-----------------------------------------------------------------------------------------------------------------------
test("pendulum: the §24.2 formula on server time (amp, period, phase), exact at huge server times", function()
	local amp, period, phase = 1.0, 3.2, 2.1
	for _, t in ipairs({ 0, .8, 1.6, 3.2, 17.37, 1761000000.25, 1761000123.9 }) do
		local want = amp * math.sin(TAU * ((t % period) / period) + phase)
		check(near(R.SwingAngle(amp, period, phase, t), want, 1e-9), "t " .. t)
	end
	-- the same angle one period later; a quarter period swings to the full amplitude (no phase)
	check(near(R.SwingAngle(.7, 3.2, 0, 1761000000 + .8), R.SwingAngle(.7, 3.2, 0, 1761000000 + .8 + 3.2), 1e-9), "periodic")
	check(near(R.SwingAngle(.7, 4, 0, 1), .7, 1e-9), "quarter period = amplitude")
	check(R.SwingAngle(1, 0, 0, 5) == 0 and R.SwingAngle(nil, 3, 0, 5) == 0, "degenerate inputs rest")
	-- each of the Funeral Run's three phases (0, 2pi/3, 4pi/3) gives a different angle at the same moment
	local a = {}
	for i = 0, 2 do
		a[i + 1] = R.SwingAngle(1, 3.2, i * TAU / 3, T)
	end
	check(not near(a[1], a[2], 1e-3) and not near(a[2], a[3], 1e-3), "phases differ")
end)

test("spin / drift / bell sway / blink / flicker: bounded and deterministic", function()
	check(near(R.SpinAngle(.35, 0), 0), "spin at 0")
	local a1 = R.SpinAngle(.35, 1761000000)
	check(a1 >= 0 and a1 < TAU, "wrapped")
	check(near(R.SpinAngle(-.35, 10), -R.SpinAngle(.35, 10), 1e-9), "reverse spin")
	for _, t in ipairs({ 0, 3, 77.7, T }) do
		local y, tilt = R.Drift(2.4, 11, t, .3)
		check(math.abs(y) <= 2.4 + 1e-9 and math.abs(tilt) <= .035 + 1e-9, "drift bounds")
		local pitch, roll = R.BellSway(t, 4, 7.2, 0)
		check(math.abs(pitch) <= math.rad(4) + 1e-9 and math.abs(roll) <= math.rad(4) + 1e-9, "sway bounds")
		local c = R.Blink(t, 123)
		check(c >= 0 and c <= 1, "blink 0..1")
		for _, kind in ipairs({ "Candle", "Brazier", "Purple", "Lantern" }) do
			local f = R.Flicker(kind, t, 1.3, 1)
			check(f > .6 and f < 1.4, "flicker " .. kind)
		end
	end
	-- a struck bell swings harder
	local p0 = math.abs(select(1, R.BellSway(1.8, 4, 7.2, 0)))
	local p1 = math.abs(select(1, R.BellSway(1.8, 4, 7.2, 2)))
	check(p1 > p0, "boost")
	-- every eye blinks within two cycles (its moment moves from cycle to cycle), not all at the same moment
	local closedAt = {}
	for seed = 1, 6 do
		for k = 0, 1300 do
			if R.Blink(k / 100, seed) > .9 then
				closedAt[seed] = k
				break
			end
		end
		check(closedAt[seed] ~= nil, "eye " .. seed .. " blinks within 13 s")
	end
	check(closedAt[1] ~= closedAt[2] or closedAt[2] ~= closedAt[3], "blinks are staggered")
end)

test("seal state: show / hide / light from the cleared count", function()
	check(R.Cleared("1101000") == 3 and R.Cleared("") == 0 and R.Cleared(nil) == 0, "mask count")
	local h, l = R.SealVisual(2, nil, nil, 1)
	check(h == true and l == 1, "UyShowAtSeal 2 hidden at 1")
	h, l = R.SealVisual(2, nil, nil, 2)
	check(h == false, "shown at 2")
	h = R.SealVisual(nil, 3, nil, 2)
	check(h == false, "UyHideAtSeal 3 visible at 2")
	h = R.SealVisual(nil, 3, nil, 3)
	check(h == true, "hidden from 3")
	h, l = R.SealVisual(nil, nil, 4, 3)
	check(h == false and l == 0, "UyLightAtSeal 4 dark at 3")
	h, l = R.SealVisual(nil, nil, 4, 7)
	check(l == 1, "lit at 7")
	-- inheritance: the nearest tag of each key wins (a lantern light follows its glass, the glass its model)
	local s1, h1, l1 = R.SealTags({ {}, { UyLightAtSeal = 3 }, { UyLightAtSeal = 5, UyShowAtSeal = 2 } })
	check(s1 == 2 and h1 == nil and l1 == 3, "nearest per key")
	-- gates: open from Layout.Unlock; the Arena also while the Assault runs; an open gate judges its parts as unlocked
	check(R.GateOpen("FuneralCarnival", 1) and not R.GateOpen("FuneralCarnival", 0), "carnival after I")
	check(not R.GateOpen("BlackBellArena", 5) and R.GateOpen("BlackBellArena", 5, true) and R.GateOpen("BlackBellArena", 6), "arena")
	check(R.GateCleared("BlackBellArena", 2, true) == 6 and R.GateCleared("BlackBellArena", 2, false) == 2, "assault veil")
	local hidden = R.SealVisual(nil, Layout.Unlock.BlackBellArena, nil, R.GateCleared("BlackBellArena", 0, true))
	check(hidden, "the Arena veil dissolves for everyone during the Assault")
end)

test("presence weight: Y counts, feathered", function()
	check(R.UnderWeight(Layout.Centre + V(0, 3, 0)) == 1, "centre")
	check(R.UnderWeight(V(0, 3, 400)) == 0, "the island")
	check(near(R.UnderWeight(V(0, Layout.Zone.Min.Y - 20, 2400), 40), .5, 1e-9), "20 below the floor of the zone box")
	check(R.UnderWeight(V(0, Layout.Zone.Max.Y + 41, 2400), 40) == 0, "high above")
	check(near(R.UnderWeight(V(Layout.Zone.Max.X + 10, 3, 2400), 40), .75, 1e-9), "feather on X")
	check(R.UnderWeight(nil) == 0, "no camera")
end)

test("soundscape priority: override > finale > boss > trial > underyard > blood > zone > night", function()
	local function theme(s)
		local base = { MusicOn = true }
		for k, v in pairs(s) do
			base[k] = v
		end
		return R.Theme(base)
	end
	check(R.Theme({ MusicOn = false, Boss = true }) == nil, "music off")
	local t, o, hold = theme({ Override = { Theme = "COFFIN", Fade = .4 }, Boss = true, Trial = true })
	check(t == "COFFIN" and hold and o.Fade == .4, "override first")
	t, o, hold = theme({ Finale = "FakeDeath", Boss = true })
	check(t == nil and hold == true and o.Fade < .2, "the false victory stops the music hard (and holds the island's)")
	t, o = theme({ Finale = "Bell", Boss = true })
	check(t == "FINALE_BELL" and o.Fade == 2, "bell")
	t = theme({ Finale = "Choir" })
	check(t == "FINALE_CHOIR", "choir")
	t, o = theme({ Finale = "Hound", FinaleElapsed = 12.5 })
	check(t == "FINALE_HOUND" and o.Elapsed == 12.5, "hound anchored to the stage start")
	t = theme({ Finale = "Fail" })
	check(t == nil, "defeat: silence")
	t = theme({ Finale = "Victory" })
	check(t == "ZONE", "victory resolves")
	check(theme({ Boss = true, Trial = true, Underyard = true }) == "BOSS", "boss")
	check(theme({ Trial = true, Underyard = true, Blood = "ACTIVE", Reach = true }) == "TRIAL", "trial")
	check(theme({ Underyard = true, Blood = "ACTIVE", Reach = true, Zone = true }) == "UNDERYARD", "underyard over blood moon")
	t, o = theme({ Blood = "WARNING", Reach = true, BloodElapsed = 4 })
	check(t == "BLOOD_WARN" and o.Elapsed == 4, "warning")
	check(theme({ Blood = "ACTIVE", Reach = true }) == "BLOOD_MOON", "blood moon")
	check(theme({ Blood = "ACTIVE", Reach = false, Zone = true }) == "ZONE", "out of reach")
	t, o = theme({ Zone = true, Blood = "ENDING", Current = "BLOOD_MOON" })
	check(t == "ZONE" and o and o.Fade == 8, "the moon sets slowly")
	t, o, hold = theme({ Night = true })
	check(t == "NIGHT" and hold, "night")
	t, o, hold = theme({})
	check(t == nil and not hold, "nothing")
	-- FinaleFX's own fades (its guard sets the same theme when nothing else did)
	check(R.FinaleFades.Bell == 2 and R.FinaleFades.Choir == 2.5 and R.FinaleFades.Hound == 1.5, "fades match FinaleFX")
end)

test("guide: every Chapter2Config step has client hints (EN + RU), progress counters", function()
	for i, def in ipairs(Cfg2.Tutorial.Steps) do
		local g = R.GuideSteps[def.Key]
		check(g ~= nil, "step " .. i .. " " .. tostring(def.Key))
		check(type(g.Hint) == "table" and #g.Hint[1] > 10 and #g.Hint[2] > 10, "hint " .. def.Key)
		check(g.Tip == nil or (#g.Tip[1] > 5 and #g.Tip[2] > 5), "tip " .. def.Key)
		for _, a in ipairs(g.Anchors) do
			check(Layout.Anchor(a) ~= nil, "anchor " .. a)
		end
	end
	local shards = Cfg2.Tutorial.Steps[1]
	local have, need = R.GuideProgress(shards, { Tutorial = { Mark = 40 }, Stats = { ShardsEarned = 46 } })
	check(have == 6 and need == 10, "shards since the step began")
	have = R.GuideProgress(shards, { Tutorial = { Mark = 40 }, Stats = { ShardsEarned = 99 } })
	check(have == 10, "clamped to the goal")
	have, need = R.GuideProgress(Cfg2.Tutorial.Steps[3], { Tutorial = { Mark = 0 }, Coffins = { Opened = 1 } })
	check(have == 1 and need == 1, "coffins")
	check(R.GuideProgress(Cfg2.Tutorial.Steps[2], { Tutorial = { Mark = 0 } }) == nil, "event steps have no counter")
	check(R.GuideProgress(shards, { Tutorial = {}, Stats = { ShardsEarned = 5 } }) == nil, "no mark (old server): no bar")
end)

test("guide path: round the broken bell tower, never through it", function()
	local ob = R.Config.Guide.Obstacles[1]
	for _, pair in ipairs({ { V(0, 3, 2352), V(0, 1, 2462) }, { V(-30, 3, 2400), V(40, 3, 2400) }, { V(12, 3, 2370), V(-14, 3, 2430) } }) do
		local path = R.GuidePath(pair[1], pair[2])
		check(path[1] == pair[1] and path[#path] == pair[2], "ends")
		for i = 2, #path do
			local d = R.SegmentDistance(path[i - 1], path[i], ob.Centre)
			check(d >= ob.Radius - .5, string.format("segment %d passes %.1f from the tower", i, d))
		end
	end
	local straight = R.GuidePath(V(30, 3, 2440), V(0, 1, 2462))
	check(#straight == 2, "a clear way stays straight")
	local p, dir = R.PathPoint(straight, 0)
	check(p == straight[1] and dir.Magnitude > .99, "start")
	p = R.PathPoint(straight, 1e6)
	check(p == straight[2], "clamped end")
	check(near(R.PathLength(straight), (straight[2] - straight[1]).Magnitude, 1e-9), "length")
end)

test("guide pup: leads ahead, circles at the target, waits for a straggler", function()
	local P = R.Config.Guide.Pup
	local me, target = V(0, 3, 2352), V(0, 1, 2462)
	local path = R.GuidePath(me, target)
	local goal, mode = R.PupGoal(path, me, target, 0)
	check(mode == "Lead", mode)
	check(near((goal - me).Magnitude, P.Lead, .6), "lead distance")
	goal, mode = R.PupGoal(R.GuidePath(target + V(4, 0, 0), target), target + V(4, 0, 0), target, 1)
	check(mode == "Circle" and near((V(goal.X, 0, goal.Z) - V(target.X, 0, target.Z)).Magnitude, P.Circle, 1e-3), "circle")
	local _, m2 = R.PupGoal(path, me, target, 0, me + V(0, 0, P.Wait + 5))
	check(m2 == "Wait", "waits")
	local f = R.FocusFrom(target, me, 15, 7)
	check(f.Y > target.Y + 6 and (V(f.X, 0, f.Z) - V(target.X, 0, target.Z)).Magnitude > 14, "focus camera above and away")
end)

test("trial of the toll: only a Perfect counts, five win", function()
	local st = R.TollNew(5)
	local counted, done = R.TollHit(st, false)
	check(not counted and not done and st.Off == 1, "good hit")
	for i = 1, 4 do
		counted, done = R.TollHit(st, true)
		check(counted and not done, "toll " .. i)
	end
	counted, done = R.TollHit(st, true)
	check(counted and done and st.Count == 5 and st.Hits == 6, "five tolls")
	R.TollHit(st, true)
	check(st.Count == 5, "capped")
end)

test("mourner: circle -> line -> ring, two dodges open the heart, a perfect wins", function()
	local now = 100
	local st = R.MournerNew(now)
	check(R.MournerDue(st, now) == nil and R.MournerDue(st, now + R.Config.Mourner.Intro) == "Attack", "intro")
	local kinds = {}
	local function cycle(hits)
		for i = 1, 3 do
			now = st.NextAt
			check(R.MournerDue(st, now) == "Attack", "attack due")
			local kind = R.MournerNextKind(st)
			table.insert(kinds, kind)
			R.MournerAttacked(st, kind, now + 2.35)
			check(R.MournerDue(st, now + 2.35) == nil, "not before the impact + grace")
			now += 2.35 + R.Config.Mourner.Evaluate
			check(R.MournerDue(st, now) == "Evaluate", "evaluate")
			local _, follow = R.MournerResolve(st, hits[i], now)
			if i < 3 then
				check(follow == "Next", "next")
			else
				return follow
			end
		end
		return nil
	end
	-- one dodge only: the round repeats
	local f = cycle({ true, false, true })
	check(f == "Again" and st.Cycle == 2 and st.Dodges == 0, "again")
	check(kinds[1] == "Circle" and kinds[2] == "Line" and kinds[3] == "Ring", "order")
	-- two dodges: the heart opens
	f = cycle({ false, false, true })
	check(f == "Weak" and st.Phase == "Weak" and st.Opened == 1, "weak")
	check(not R.MournerWeakHit(st, false), "a Good hit does not win")
	-- the heart closes unused: one Ring, then it opens again
	check(R.MournerDue(st, st.WeakUntil) == "CloseWeak", "closes")
	R.MournerWeakClosed(st, st.WeakUntil)
	now = st.NextAt
	check(R.MournerNextKind(st) == "Ring", "a ring")
	R.MournerAttacked(st, "Ring", now + 2.35)
	local _, follow = R.MournerResolve(st, true, now + 2.7)
	check(follow == "Weak" and st.Opened == 2, "open again even after a hit")
	check(R.MournerWeakHit(st, true) and st.Phase == "Won", "the perfect wins")
end)

test("mourner: downed mid-attack, revived after 3 s, the sequence resumes", function()
	local st = R.MournerNew(0)
	R.MournerAttacked(st, "Circle", 2.95)
	R.MournerDowned(st, 2.95)
	check(st.Phase == "Downed" and st.Attack == nil and st.Hits == 1, "down")
	check(R.MournerDue(st, 2.95 + 2.9) == nil and R.MournerDue(st, 2.95 + 3) == "Revive", "revive after ReviveAfter")
	check(R.MournerRevived(st, 6) == "Recover" and st.Phase == "Recover", "resume")
	check(R.MournerNextKind(st) == "Line", "continues with the next attack")
	-- downed by the last attack of a round that already had two dodges: the heart opens after the revive
	local s2 = R.MournerNew(0)
	s2.Index, s2.Dodges = 2, 2
	R.MournerAttacked(s2, "Ring", 5)
	R.MournerDowned(s2, 5)
	check(R.MournerRevived(s2, 8) == "Weak" and s2.Phase == "Weak", "weak after the revive")
end)

test("mourner hazards: fair shapes (the circle on the player, the line through them, the ring's gap a quarter turn away)", function()
	local c = Layout.Square.Mourner
	local me = c + V(6, 3, 0)
	local circle = R.MournerShape("Circle", c, me)
	check(Hazards.Contains(Hazards.Circle(circle.Center, circle.Radius), me), "circle hits a player who stays")
	check(not Hazards.Contains(Hazards.Circle(circle.Center, circle.Radius), me + V(0, 0, 8)), "8 studs away is safe")
	local line = R.MournerShape("Line", c, me)
	local lh = Hazards.Line(line.From, line.To, line.Width)
	check(Hazards.Contains(lh, me), "line through the player")
	check(not Hazards.Contains(lh, me + V(0, 0, 5)), "a sidestep is safe")
	local gap = R.MournerGapAngle(c, me, 7)
	local ang = math.deg(math.atan2(me.Z - c.Z, me.X - c.X))
	local diff = math.abs(((gap - ang + 180) % 360) - 180)
	check(near(diff, 90, 1e-6), "gap a quarter turn from the player")
	local ring = R.MournerShape("Ring", c, me, gap)
	local rh = Hazards.Ring(ring.Center, ring.Inner, ring.Outer, ring.Gaps)
	check(Hazards.Contains(rh, me), "the ring hits a player who stays")
	local th = math.rad(gap)
	local safe = V(c.X + math.cos(th) * 8, 3, c.Z + math.sin(th) * 8)
	check(not Hazards.Contains(rh, safe), "the gap is safe")
	check(not Hazards.Contains(rh, c + V(0, 3, 0) + V(14, 0, 0)), "outside the ring is safe")
	-- every attack is fair by the §10.2 rules (telegraph, damage cap for trials)
	for _, kind in ipairs({ "Circle", "Line", "Ring" }) do
		local shape = R.MournerShape(kind, c, me, gap)
		local hz = kind == "Circle" and Hazards.Circle(shape.Center, shape.Radius) or kind == "Line" and Hazards.Line(shape.From, shape.To, shape.Width)
			or Hazards.Ring(shape.Center, shape.Inner, shape.Outer, shape.Gaps)
		local ok, problems = Hazards.Check({ Shape = hz, Telegraph = R.Config.Mourner.Telegraph, ImpactAt = 10, Damage = R.Config.Mourner.Damage, Trial = "Mourner" },
			{ Trial = true })
		check(ok, kind .. ": " .. table.concat(problems or {}, "; "))
	end
end)

test("world contract classification (names / attributes)", function()
	check(R.MarkerKind("MothSwarm_3") == "Moth" and R.MarkerKind("FogPoint") == "Fog" and R.MarkerKind("FogPoint_12") == "Fog", "moth / fog")
	local k, base = R.MarkerKind("GhostPath_4")
	check(k == "Ghost" and base == "GhostPath", "district ghost path")
	check(R.MarkerKind("GhostResident_1") == "Ghost" and R.MarkerKind("WispPath_9") == "Wisp", "ghosts / wisps")
	check(R.MarkerKind("CrowPerch") == nil and R.MarkerKind("MothSwarmer") == nil, "others")
	check(R.MoverKind({ UySpin = .35 }) == "Spin" and R.MoverKind({ UySwing = true, UySwingAmp = 4 }) == "Bell", "spin / bell")
	check(R.MoverKind({ UySwingAmp = 1, UySwingPeriod = 3.2 }) == "Swing" and R.MoverKind({ UySwirl = true }) == "Swirl", "swing / swirl")
	check(R.MoverKind({ UyDrift = 2 }) == "Drift" and R.MoverKind({ UyBlink = true }) == "Eye" and R.MoverKind({ UyTowerBell = true }) == "TowerBell", "drift / eye")
	check(R.MoverKind({ UyMoon = "Pale" }) == "Moon" and R.MoverKind({}) == nil, "moon")
	check(R.FlameKind({ HwLantern = "Purple" }) == "Purple" and R.FlameKind({ HwLantern = "Orange" }) == "Lantern" and R.FlameKind({ HwLantern = true }) == "Lantern",
		"lanterns")
	check(R.FlameKind({ HwCandle = true }) == "Candle" and R.FlameKind({ HwBrazier = true }) == "Brazier" and R.FlameKind({}) == nil, "flames")
end)

-----------------------------------------------------------------------------------------------------------------------
-- 2. world: the real builders
-----------------------------------------------------------------------------------------------------------------------
local E = require("./lib/underyard_env")
local wgame = E.Build()
local wroot = E.Root(wgame)

local function chainOf(inst)
	local out = {}
	local a = inst
	while a and a ~= wroot do
		table.insert(out, a:GetAttributes())
		a = a.Parent
	end
	return out
end

test("world: every animated model is classified with what UnderyardFX needs", function()
	check(wroot ~= nil, "40_Underyard built")
	local kinds = {}
	local byKind = {}
	for _, d in wroot:GetDescendants() do
		if d:IsA("Model") then
			local k = R.MoverKind(d:GetAttributes())
			if k then
				kinds[k] = (kinds[k] or 0) + 1
				byKind[k] = byKind[k] or {}
				table.insert(byKind[k], d)
			end
		end
	end
	check(kinds.Spin == 1, "carousel " .. tostring(kinds.Spin))
	local car = byKind.Spin[1]
	check(car.PrimaryPart and car.PrimaryPart.Name == "CarouselHub", "carousel hub pivot")
	local spinning, deck = 0, nil
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			if not p.CanCollide then
				spinning += 1
			elseif p:GetAttribute("RunCarouselDeck") then
				deck = p
			end
		end
	end
	check(spinning > 20 and deck ~= nil, "visual parts turn, the walkable deck stays (" .. spinning .. ")")
	check(kinds.Swing == 3, "three pendulums " .. tostring(kinds.Swing))
	local phases = {}
	for _, m in byKind.Swing do
		check(m.PrimaryPart ~= nil, "pendulum hinge pivot")
		check(m:GetAttribute("UySwingAxis") == "Z" and m:GetAttribute("UySwingPeriod") == 3.2 and type(m:GetAttribute("UySwingPhase")) == "number", "pendulum attrs")
		phases[m:GetAttribute("UySwingPhase")] = true
	end
	local np = 0
	for _ in phases do
		np += 1
	end
	check(np == 3, "three phases")
	check(kinds.Bell == 1 and byKind.Bell[1].Name == "BlackBell" and byKind.Bell[1].PrimaryPart.Name == "BellCrown", "the Black Bell")
	check(kinds.Swirl == 1 and byKind.Swirl[1].PrimaryPart ~= nil, "portal swirl")
	check(kinds.Drift == 8, "drift islands " .. tostring(kinds.Drift))
	for _, m in byKind.Drift do
		check(m.PrimaryPart ~= nil and m:GetAttribute("UyDriftPeriod") ~= nil, "island pivot / period")
	end
	check(kinds.TowerBell == 1 and byKind.TowerBell[1]:FindFirstChild("BellCrown", true) ~= nil, "tower bell crown")
	check(kinds.Moon == 2, "two moons")
	for _, m in byKind.Moon do
		local want = m:GetAttribute("UyMoon") == "Black" and "CoronaFlare" or "MoonHalo"
		check(m:FindFirstChild(want, true) ~= nil and m.PrimaryPart ~= nil, "moon parts " .. want)
	end
	check(kinds.Eye >= 12, "eye windows " .. tostring(kinds.Eye))
	for _, m in byKind.Eye do
		local lids = 0
		for _, p in m:GetChildren() do
			if p:GetAttribute("LidDir") ~= nil then
				check(type(p:GetAttribute("LidTravel")) == "number", "lid travel")
				lids += 1
			end
		end
		check(lids == 2 and m:FindFirstChild("EyePane") and m:FindFirstChild("EyePupil"), "two lids, pane, pupil")
	end
end)

test("world: flames, FX markers, the conveyor", function()
	local flames, markers = {}, {}
	local belt = nil
	for _, d in wroot:GetDescendants() do
		if d:IsA("BasePart") then
			local k = R.FlameKind(d:GetAttributes())
			if k then
				flames[k] = (flames[k] or 0) + 1
			end
			if d:GetAttribute("UyConveyorSpeed") ~= nil then
				belt = d
			end
		elseif d:IsA("Attachment") then
			local k, base = R.MarkerKind(d.Name)
			if k then
				markers[base] = (markers[base] or 0) + 1
			end
		end
	end
	check((flames.Lantern or 0) + (flames.Purple or 0) + (flames.Green or 0) + (flames.Blue or 0) > 20, "lanterns")
	check((flames.Candle or 0) > 5 and (flames.Brazier or 0) >= 8, "candles / braziers")
	check(markers.MothSwarm == 15 and markers.WispPath == 46 and markers.GhostResident == 15, "FXMarkers")
	check((markers.FogPoint or 0) >= 33 + 6, "fog: FXMarkers + districts " .. tostring(markers.FogPoint))
	check((markers.GhostPath or 0) == 10, "district ghost paths " .. tostring(markers.GhostPath))
	check(belt ~= nil, "conveyor belt")
	local slats = 0
	for _, s in belt.Parent:GetChildren() do
		if s.Name == "BeltSlat" then
			slats += 1
		end
	end
	check(slats > 5, "belt slats beside the belt")
	local fx = wroot:FindFirstChild("FXMarkers")
	check(fx and fx:GetAttribute("SelfManagedFX") == true, "SelfManagedFX root")
end)

test("world: seal tags (lights inherit their glass's tag), gate veils, bilingual signs", function()
	local tagged, lightsLit, lightsTotal = 0, 0, 0
	for _, d in wroot:GetDescendants() do
		if d:IsA("Light") then
			local s, h, l = R.SealTags(chainOf(d))
			if l then
				lightsTotal += 1
				-- dark before its seal, at full after it
				local _, lit0 = R.SealVisual(s, h, l, l - 1)
				local _, lit1 = R.SealVisual(s, h, l, l)
				if lit0 == 0 and lit1 == 1 then
					lightsLit += 1
				end
				check(type(d:GetAttribute("UyBaseBrightness") or d:GetAttribute("HwBaseBrightness") or d.Brightness) == "number", "base brightness")
			end
		elseif d:IsA("BasePart") then
			local s, h, l = R.SealTags(chainOf(d))
			if s or h or l then
				tagged += 1
			end
		end
	end
	check(tagged > 100, "tagged parts " .. tagged)
	check(lightsTotal >= 12 and lightsLit == lightsTotal, string.format("seal lights %d / %d", lightsLit, lightsTotal))
	-- gates: a model per district, veil parts hidden from the unlock, the arena's also during the Assault
	local gates = 0
	for _, g in wroot.Gates:GetChildren() do
		local district = g:GetAttribute("UyGate")
		if district then
			gates += 1
			local need = Layout.Unlock[district]
			local veil = 0
			for _, p in g:GetDescendants() do
				if p:IsA("BasePart") and p:GetAttribute("UyHideAtSeal") ~= nil then
					veil += 1
					check(p:GetAttribute("UyHideAtSeal") == need, "veil seal")
					check(not R.SealVisual(nil, need, nil, need - 1), "visible while sealed")
					check(R.SealVisual(nil, need, nil, need), "gone once open")
				end
			end
			check(veil > 10, "veil parts " .. district)
		end
	end
	check(gates == 5, "five gates")
	-- every world sign carries both languages and NoTranslate
	local signs = 0
	for _, d in wroot:GetDescendants() do
		if d:GetAttribute("TextEN") ~= nil then
			signs += 1
			check(type(d:GetAttribute("TextRU")) == "string" and #d:GetAttribute("TextRU") > 0, "RU on " .. d:GetFullName())
			check(d:GetAttribute("NoTranslate") == true, "NoTranslate on " .. d.Name)
		end
	end
	check(signs > 20, "signs " .. signs)
end)

test("world: the practice ring (pedestal top, hand-bell over its anchor, BellSquare paths the client uses)", function()
	local sq = wroot:FindFirstChild("BellSquare")
	local ring = sq and sq:FindFirstChild("PracticeRing")
	check(ring and ring:FindFirstChild("HandBell") and ring:FindFirstChild("MournerPedestal"), "PracticeRing.HandBell / MournerPedestal")
	local ped = ring.MournerPedestal
	local top = ped.CFrame.Position.Y + math.min(ped.Size.X, ped.Size.Y) / 2
	check(near(top, .7, .05), "pedestal top " .. top)
	local body = ring.HandBell:FindFirstChild("BellBody")
	local anchor = Layout.Anchor("TutorialBell")
	local bp = body.CFrame.Position
	check((V(bp.X, 0, bp.Z) - V(anchor.X, 0, anchor.Z)).Magnitude < 1, "the bell hangs over TutorialBell")
	check(math.abs(bp.Y - (anchor.Y + 1)) < 1.2, "the Strike target (anchor + 1) sits on the bell body")
	check(sq:FindFirstChild("CoffinShrine") and sq.SealAltars:FindFirstChild("SealAltar_1"), "coffin shrine / altar I")
	check(wroot.Anchors:FindFirstChild("TutorialBell") and wroot.Anchors:FindFirstChild("Mourner"), "anchors")
end)

-----------------------------------------------------------------------------------------------------------------------
-- 3. server: Chapter2Tutorial on the real Seals + EventHP
-----------------------------------------------------------------------------------------------------------------------
local EventHP = L.Require("ServerScriptService.Halloween.EventHP")
local Seals = L.Require("ServerScriptService.Halloween.Seals")
local CT = L.Require("ServerScriptService.Halloween.Chapter2Tutorial")

local pos = {}
local everyone = {}
local signals, toasts, shardsQ, events, streak, prompts, ticks = {}, {}, {}, {}, {}, {}, {}
EventHP.Now = function()
	return T
end
EventHP.RootOf = function(pl)
	local p = pos[pl]
	return p and { Position = p } or nil
end
EventHP.PlayerList = function()
	return everyone
end
EventHP.Send = function(to, kind, data)
	table.insert(signals, { To = to, Kind = kind, Data = data })
end
EventHP.Spawn = function(fn, ...)
	fn(...)
end
EventHP.Delay = function(t, fn, ...)
	Task.delay(t, fn, ...)
end
CT.Now = function()
	return T
end
CT.Root = function(pl)
	local p = pos[pl]
	return p and { Position = p } or nil
end
CT.Defer = function(fn)
	Task.defer(fn)
end

local handlers = {}
local core = {
	Transact = function() end,
	OnRequest = function(name, fn)
		handlers[name] = fn
	end,
	Signal = function(to, kind, data)
		table.insert(signals, { To = to, Kind = kind, Data = data })
	end,
	Root = function(pl)
		local p = pos[pl]
		return p and { Position = p } or nil
	end,
	Near = function(pl, at, r)
		local p = pos[pl]
		return p ~= nil and (p - at).Magnitude <= r
	end,
	Rules = { Check = function(c, msg)
		if not c then
			error(msg, 0)
		end
	end },
}
local C2 = {
	TutorialStep = function(pl)
		return pl:GetAttribute("UyTutorial") or 0
	end,
	Eligible = function()
		return true
	end,
	AnchorPos = function(name)
		return Layout.Anchor(name)
	end,
	Toast = function(_, text)
		table.insert(toasts, text)
	end,
	QueueShards = function(pl, n, source)
		table.insert(shardsQ, { pl, n, source })
	end,
	Progress = function() end,
	StreakHit = function(_, perfect)
		table.insert(streak, perfect)
	end,
	TutorialEvent = function(pl, key)
		table.insert(events, key)
		-- the server would advance the step: do the same here
		local step = pl:GetAttribute("UyTutorial") or 0
		if Cfg2.Tutorial.Steps[step] and Cfg2.Tutorial.Steps[step].Event == key then
			pl:SetAttribute("UyTutorial", step + 1)
		end
	end,
	TrialCleared = function() end,
	Grant = function()
		return true
	end,
	GrantSeal = function()
		return true
	end,
	ViewOf = function()
		return { Seals = {} }
	end,
	PhaseOverride = function()
		return nil
	end,
	OnTick = function(fn)
		table.insert(ticks, fn)
	end,
	HasTeamDog = function()
		return false
	end,
}
local UY = {
	InZone = function(pl)
		return pl.Out ~= true
	end,
	District = function()
		return "BellSquare"
	end,
	Unlocked = function()
		return true
	end,
	Prompt = function(anchor, props, fn)
		local key = props.Attributes and props.Attributes.UyTutorialTrial or anchor
		prompts[key] = { Props = props, Fn = fn, Anchor = anchor }
		return {}
	end,
}
local Strike = { Kinds = {}, Targets = {}, NextId = 0 }
function Strike.Register(kind, def)
	Strike.Kinds[kind] = def
end
function Strike.Add(t)
	Strike.NextId += 1
	local target = { Id = Strike.NextId, Kind = t.Kind, Def = Strike.Kinds[t.Kind], Owner = t.Owner, Data = t.Data or {}, Position = t.Position,
		HP = t.HP, Alive = true, Removed = false, Attributes = t.Attributes }
	Strike.Targets[target.Id] = target
	return target
end
function Strike.Remove(target, reason)
	if target.Removed then
		return
	end
	target.Removed, target.Alive, target.EndReason = true, false, reason
	Strike.Targets[target.Id] = nil
end
function Strike.AddCanAct() end
function Strike.End() end
local function live(kind, owner)
	local out = {}
	for _, t in pairs(Strike.Targets) do
		if t.Kind == kind and (owner == nil or t.Owner == owner) then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end
-- one judged hit: the kind's CanHit then OnHit (Strike.Hit's order); a broken target runs OnBreak
local function hit(pl, target, quality)
	local def = target.Def
	local ok, err = def.CanHit(pl, target)
	if not ok then
		return false, err
	end
	local h = { Quality = quality, Applied = 1, Damage = 1 }
	h.Applied = type(def.Damage) == "function" and def.Damage(pl, target, h) or 1
	local extra = def.OnHit(pl, target, h)
	if target.Alive and (tonumber(h.Applied) or 0) > 0 then
		target.HP -= h.Applied
		if target.HP <= 0 then
			target.Alive = false
			if def.OnBreak then
				def.OnBreak(pl, target, {})
			end
			Strike.Remove(target, "Broke")
		end
	end
	return true, extra
end

local modules = { Chapter2 = C2, Underyard = UY, Strike = Strike, EventHP = EventHP }
modules.Seals = Seals
modules.Chapter2Tutorial = CT
EventHP.Start(core, modules)
Seals.Start(core, modules)
CT.Start(core, modules)

local nextUser = 900
local function fakePlayer(at, step)
	nextUser += 1
	local p = { UserId = nextUser, Name = "T" .. nextUser, Parent = true, Character = nil, Attrs = {} }
	function p:GetAttribute(k)
		return self.Attrs[k]
	end
	function p:SetAttribute(k, v)
		self.Attrs[k] = v
	end
	p.Attrs.UyTutorial = step
	pos[p] = at
	table.insert(everyone, p)
	return p
end
local function advance(seconds)
	local steps = math.floor(seconds / .1 + .5)
	for _ = 1, steps do
		CLK += .1
		T += .1
		L.Time = T
		EventHP.Tick(.1)
		runDue()
	end
end
local function trialSignals(pl, kind)
	local out = {}
	for _, s in ipairs(signals) do
		if s.To == pl and s.Kind == "C2Trial" and (kind == nil or s.Data.Kind == kind) then
			table.insert(out, s.Data)
		end
	end
	return out
end
local function lastTrial(pl, kind)
	local list = trialSignals(pl, kind)
	return list[#list]
end

test("server: registration (two trials, two own prompts, three Strike kinds, a tick hook)", function()
	check(Seals.Def("Toll") and Seals.Def("Mourner"), "trials registered")
	check(Seals.Def("Toll").Prompt == false and Seals.Def("Mourner").Prompt == false, "no framework BEGIN TRIAL prompt")
	check(Seals.Def("Toll").Combat == false and Seals.Def("Mourner").Exclusive == false, "per-player runs, own combat zone")
	check(prompts.Toll and prompts.Toll.Anchor == "TutorialBell" and prompts.Mourner and prompts.Mourner.Anchor == "Mourner", "prompts")
	check(prompts.Toll.Props.ActionTextRU and prompts.Toll.Props.ObjectTextRU, "Russian prompt text")
	check(Strike.Kinds.UyTutorialEcho and Strike.Kinds.UyTollBell and Strike.Kinds.UyMournerWeak, "kinds")
	check(#ticks >= 1, "echo tick")
	check(#schedErrors == 0, table.concat(schedErrors, "\n"))
end)

test("server: tutorial echoes exist exactly on step 1 in the zone, pay Echo shards, respawn", function()
	local p = fakePlayer(V(0, 3, 2380), 1)
	for _, fn in ipairs(ticks) do
		fn(p, 1)
	end
	local mine = live("UyTutorialEcho", p)
	check(#mine == 3, "three echoes, got " .. #mine)
	local other = fakePlayer(V(2, 3, 2380), 3)
	local ok, err = hit(other, mine[1], 2)
	check(not ok and err == "HW:NOT_YOURS", "owner only")
	-- 2 Perfect hits (2 + 2 > 3 HP) dig it out
	hit(p, mine[1], 2)
	check(mine[1].Alive, "still there after one")
	hit(p, mine[1], 2)
	check(not mine[1].Alive, "dug out")
	check(#shardsQ == 1 and shardsQ[1][2] == R.Config.TutorialEcho.Shards and shardsQ[1][3] == "Echo", "Echo shards queued")
	check(#streak == 2 and streak[1] == true, "every judged hit feeds the streak")
	for _, fn in ipairs(ticks) do
		fn(p, 1)
	end
	check(#live("UyTutorialEcho", p) == 2, "respawns only after a moment")
	advance(R.Config.TutorialEcho.Respawn + .2)
	for _, fn in ipairs(ticks) do
		fn(p, 1)
	end
	check(#live("UyTutorialEcho", p) == 3, "respawned")
	p.Attrs.UyTutorial = 2
	for _, fn in ipairs(ticks) do
		fn(p, 1)
	end
	check(#live("UyTutorialEcho", p) == 0, "gone with the step")
	p.Attrs.UyTutorial = 1
	p.Out = true
	for _, fn in ipairs(ticks) do
		fn(p, 1)
	end
	check(#live("UyTutorialEcho", p) == 0, "not outside the zone")
end)

test("server: the Trial of the Toll (step gate, Good hits do not count, five Perfects win, TutorialEvent Toll)", function()
	local bell = Layout.Anchor("TutorialBell")
	local p = fakePlayer(bell + V(0, .5, -4), 1)
	table.clear(toasts)
	prompts.Toll.Fn(p)
	check(Seals.RunOf(p) == nil and toasts[1] == "This practice is part of the Underyard guide", "refused off its step: " .. tostring(toasts[1]))
	p.Attrs.UyTutorial = 2
	advance(3.2) -- the framework's start cooldown
	prompts.Toll.Fn(p)
	local run = Seals.RunOf(p)
	check(run and run.TrialId == "Toll" and run.State == "Running", "started")
	check(p:GetAttribute("UyTrial") == "Toll:" .. run.Id, "UyTrial")
	local target = live("UyTollBell", p)[1]
	check(target and target.Owner == p, "the hand-bell target")
	local ok, extra = hit(p, target, 1)
	check(ok and extra.Counted == false and run.Total == 0, "a Good hit rings dully")
	for i = 1, 4 do
		ok, extra = hit(p, target, 2)
		check(ok and extra.Counted and extra.Toll == i, "toll " .. i)
	end
	check(run.State == "Running" and run.Public.Count == 4, "four")
	hit(p, target, 2)
	check(run.State == "Won", "won on the fifth")
	check(table.find(events, "Toll") ~= nil and p:GetAttribute("UyTutorial") == 3, "TutorialEvent Toll advanced the step")
	check(target.Removed, "the bell target is gone")
	check(p:GetAttribute("UyTrial") == "", "out of the trial")
	local tolls = trialSignals(p, "Toll")
	check(#tolls == 6 and tolls[1].Counted == false and tolls[6].Count == 5, "Toll signals")
end)

test("server: the Mourner (own Event HP zone, dodges, the heart, a Perfect wins)", function()
	local centre = CT.MournerGround()
	local p = fakePlayer(centre + V(7, 3, 0), 5)
	advance(3.2)
	prompts.Mourner.Fn(p)
	local run = Seals.RunOf(p)
	check(run and run.TrialId == "Mourner", "started")
	local zone = run.Data.Zone
	check(zone == "Practice:" .. run.Id and EventHP.Zone(p) == zone, "own Event HP zone")
	check(EventHP.Zones[zone].Trial ~= false, "trial damage cap")
	-- intro, then the Circle on the player: step out of it
	advance(R.Config.Mourner.Intro + .2)
	local a1 = lastTrial(p, "MournerAttack")
	check(a1 and a1.Attack == "Circle" and typeof(a1.Target) == "Vector3", "circle telegraph")
	pos[p] = pos[p] + V(0, 0, 9)
	advance(R.Config.Mourner.Telegraph + .35 + R.Config.Mourner.Evaluate + .3)
	local r1 = lastTrial(p, "MournerResult")
	check(r1 and r1.Outcome == "Dodged" and r1.Dodges == 1 and r1.Next == "Next", "dodged the circle")
	-- the Line through the player: stay and take the hit
	advance(R.Config.Mourner.Gap + .2)
	local a2 = lastTrial(p, "MournerAttack")
	check(a2 and a2.Attack == "Line", "line telegraph")
	local hp0 = EventHP.HP(p)
	advance(R.Config.Mourner.Telegraph + .35 + R.Config.Mourner.Evaluate + .3)
	local r2 = lastTrial(p, "MournerResult")
	check(r2 and r2.Outcome == "Hit" and EventHP.HP(p) < hp0, "hit by the line")
	-- the Ring (with a gap): stay in it -> one dodge in the round, the round repeats
	advance(R.Config.Mourner.Gap + .2)
	local a3 = lastTrial(p, "MournerAttack")
	check(a3 and a3.Attack == "Ring" and type(a3.Gap) == "number", "ring telegraph with a gap")
	advance(R.Config.Mourner.Telegraph + .35 + R.Config.Mourner.Evaluate + .3)
	local r3 = lastTrial(p, "MournerResult")
	check(r3 and r3.Outcome == "Hit" and r3.Next == "Again" and run.Data.M.Cycle == 2, "one dodge: again, got " .. tostring(r3 and r3.Next))
	check(run.State == "Running" and not EventHP.IsDowned(p), "three low hits never down a player")
end)

test("server: the Mourner opens its heart after two dodges in a round; only a Perfect wins; the zone is cleaned", function()
	local p = nil
	for pl, _ in pairs(pos) do
		local run = Seals.RunOf(pl)
		if run and run.TrialId == "Mourner" then
			p = pl
		end
	end
	check(p ~= nil, "the running player")
	local run = Seals.RunOf(p)
	local centre = CT.MournerGround()
	local function dodgeNext()
		advance(R.Config.Mourner.Recover + .3)
		local a = lastTrial(p, "MournerAttack")
		if a.Attack == "Ring" then
			local th = math.rad(a.Gap)
			pos[p] = V(centre.X + math.cos(th) * 8, 3, centre.Z + math.sin(th) * 8)
		else
			pos[p] = V(centre.X + 7, 3, centre.Z + 7) + (a.Attack == "Circle" and V(0, 0, 9) or V(-9, 0, 0))
			if a.Attack == "Line" then
				-- step sideways out of the line through the old position
				local dir = (V(a.Target.X, 0, a.Target.Z) - V(centre.X, 0, centre.Z)).Unit
				pos[p] = a.Target + V(-dir.Z, 0, dir.X) * 6
			end
		end
		advance(R.Config.Mourner.Telegraph + .35 + R.Config.Mourner.Evaluate + .3)
		return lastTrial(p, "MournerResult")
	end
	local r = dodgeNext()
	check(r.Outcome == "Dodged", "circle dodged")
	r = dodgeNext()
	check(r.Outcome == "Dodged" and r.Dodges == 2, "line dodged")
	r = dodgeNext()
	check(r.Next == "Weak" and run.Data.M.Phase == "Weak", "the heart opens: " .. tostring(r.Next))
	local weak = live("UyMournerWeak", p)[1]
	check(weak and weak.Owner == p, "weak spot target")
	check(lastTrial(p, "WeakOpen") ~= nil, "WeakOpen signal")
	local ok, extra = hit(p, weak, 1)
	check(ok and extra.Weak and extra.Perfect == false and run.State == "Running", "a Good hit: WeakMiss")
	check(lastTrial(p, "WeakMiss") ~= nil, "WeakMiss signal")
	ok, extra = hit(p, weak, 2)
	check(ok and extra.Perfect and run.State == "Won", "a Perfect wins")
	check(weak.EndReason == "Won", "the heart leaves with reason Won")
	check(table.find(events, "Mourner") ~= nil and p:GetAttribute("UyTutorial") == 6, "TutorialEvent Mourner")
	check(not EventHP.InCombat(p) and EventHP.Zones[run.Data.Zone] == nil, "zone left and forgotten")
end)

test("server: downed in the Mourner's ring -> no bleed-out, the guide revives after 3 s, the run goes on; leaving cleans up", function()
	local centre = CT.MournerGround()
	local p = fakePlayer(centre + V(-7, 3, 0), 5)
	advance(3.2)
	prompts.Mourner.Fn(p)
	local run = Seals.RunOf(p)
	check(run and run.State == "Running", "started")
	advance(1)
	EventHP.Damage(p, 500, "Test")
	check(EventHP.IsDowned(p), "downed")
	check(run.Data.M.Phase == "Downed" and lastTrial(p, "Downed") ~= nil, "Downed signal")
	advance(2) -- past the wipe grace (1.5 s): the bleed-out was called off
	check(EventHP.IsDowned(p) and EventHP.Zone(p) == run.Data.Zone, "still downed in the ring (no bleed-out teleport)")
	advance(1.2)
	check(not EventHP.IsDowned(p), "revived by the guide")
	check(lastTrial(p, "Revived") ~= nil and run.State == "Running", "the run goes on")
	local hp = EventHP.HP(p)
	check(hp >= R.Config.Mourner.ReviveHP - 1, "revive HP " .. tostring(hp))
	-- leaving the trial: zone left, weak spot gone, run failed
	Seals.Leave(p, "Left")
	check(run.State == "Failed" and not EventHP.InCombat(p), "left")
	check(#live("UyMournerWeak", p) == 0, "no weak spot left behind")
	-- (the framework's start cooldown runs on os.clock: wait it out for real)
	require("@lune/task").wait(Cfg2.Trials.Cooldown + .1)
	prompts.Mourner.Fn(p)
	check(Seals.RunOf(p) ~= nil, "can be retried at once (after the start cooldown)")
	Seals.Leave(p, "Left")
	check(#schedErrors == 0, table.concat(schedErrors, "\n"))
end)

test("server: two players practise at the same time (non-exclusive, separate zones and targets)", function()
	local centre = CT.MournerGround()
	local a = fakePlayer(centre + V(5, 3, 3), 5)
	local b = fakePlayer(centre + V(-5, 3, -3), 5)
	advance(3.2)
	prompts.Mourner.Fn(a)
	prompts.Mourner.Fn(b)
	local ra, rb = Seals.RunOf(a), Seals.RunOf(b)
	check(ra and rb and ra ~= rb and ra.Data.Zone ~= rb.Data.Zone, "two runs, two zones")
	check(#ra.Players == 1 and #rb.Players == 1, "solo runs (MaxParty 1)")
	Seals.Leave(a, "Left")
	Seals.Leave(b, "Left")
end)

-----------------------------------------------------------------------------------------------------------------------
-- 4. client: the presenters standalone (§24.1) and the guide headless
-----------------------------------------------------------------------------------------------------------------------
local CE = require("./lib/client_env")
local RSc = CE.MountReplicated()
local hc = CE.Folder("HalloweenClient", CE.Player:FindFirstChild("PlayerScripts"))
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", hc)
local CV = CE.Vector3 or Vector3

-- CollectionService (the tutorial targets)
local CSvc = CE.Service("CollectionService")
local taggedList = {}
local tagAdded, tagRemoved = CE.Signal.new(), CE.Signal.new()
CSvc.GetTagged = function(_, tag)
	return tag == "HalloweenTarget" and taggedList or {}
end
CSvc.GetInstanceAddedSignal = function()
	return tagAdded
end
CSvc.GetInstanceRemovedSignal = function()
	return tagRemoved
end

local mainGui = CE.Instance.new("ScreenGui")
mainGui.Name = "ScreenGui"
mainGui.Parent = CE.PlayerGui
local fxFolder = CE.Folder("DOGROTS_HalloweenFX", CE.Workspace)
local rec = { Audio = {}, Popups = {}, Acts = {}, Faces = 0, Resets = 0, Hurts = 0, Plays = {}, Requests = {}, Toasts = {}, Banners = {} }
local FXf = { Textures = {} }
function FXf.Folder()
	return fxFolder
end
for _, n in ipairs({ "Burst", "Ring", "Smoke", "Shake", "Flash" }) do
	FXf[n] = function() end
end
function FXf.Popup(_, text)
	table.insert(rec.Popups, text)
end
local AudioF = {
	Play = function(cue)
		table.insert(rec.Audio, cue)
	end,
	Has = function()
		return true
	end,
}
local dummyApi = {
	Act = function(state, seconds, hold)
		table.insert(rec.Acts, state)
	end,
	Face = function(p)
		if p then
			rec.Faces += 1
		end
	end,
	Glow = function() end,
	Hurt = function()
		rec.Hurts += 1
	end,
	Reset = function()
		rec.Resets += 1
	end,
	Heart = function()
		return CV.new(0, 4.4, 2462)
	end,
	Built = function()
		return true
	end,
	Model = function()
		return nil
	end,
}
local Bus = CE.Require(RSc.Halloween.Bus)
local SharedC = CE.Require(RSc.Halloween.Shared)
Bus.On("Toast", function(d)
	table.insert(rec.Toasts, d.Text)
end)
local trialsApi = {
	Banner = function(en)
		table.insert(rec.Banners, en)
	end,
}
local pctx = { Shared = SharedC, Bus = Bus, FX = FXf, Audio = AudioF, Modules = { UnderyardFX = { Mourner = function()
	return dummyApi
end } }, Trials = trialsApi }

-- the practice ring in the fake world (the hand-bell, the anchors with the two tutorial prompts)
local district = CE.Model("DOGROTS_District", CE.Workspace)
local uy = CE.Model("40_Underyard", district)
local sqm = CE.Model("BellSquare", uy)
local ringM = CE.Model("PracticeRing", sqm)
local handBell = CE.Model("HandBell", ringM)
local bellParts = {}
for i = 1, 3 do
	table.insert(bellParts, CE.Part("BellBody", CV.new(0, 4.6 - i * .4, 2472), CV.new(.6, .3, .6), handBell))
end
local altars = CE.Model("SealAltars", sqm)
CE.Model("SealAltar_1", altars)
CE.Model("CoffinShrine", sqm)
local anchorsF = CE.Folder("Anchors", uy)
local promptParts = {}
local tutPrompts = {}
for _, row in ipairs({ { "TutorialBell", "Toll" }, { "Mourner", "Mourner" } }) do
	local part = CE.Part(row[1], Layout.Anchor(row[1]), CV.new(1, 1, 1), anchorsF)
	local pr = CE.Instance.new("ProximityPrompt")
	pr.Name = "UyTutorialPrompt"
	pr.Enabled = true
	pr:SetAttribute("UyTutorialTrial", row[2])
	pr.Parent = part
	promptParts[row[2]] = part
	tutPrompts[row[2]] = pr
end

test("client: Trials.Toll presenter (pips, Perfect / off-beat tolls, the win, teardown)", function()
	local P = CE.Require(hc.Trials.Toll)
	check(type(P.Ids) == "table" and P.Ids[1] == "Toll", "Ids")
	local rest = bellParts[1].CFrame
	P.Start(pctx, { RunId = 7, TrialId = "Toll", Data = { Count = 0, Goal = 5 } })
	check(P.Active(), "active")
	local pips = fxFolder:FindFirstChild("UyTollPips")
	check(pips ~= nil, "pips board")
	check(table.find(rec.Banners, "TRIAL OF THE TOLL") ~= nil, "banner through ctx.Trials")
	P.Signal(pctx, "Toll", { Count = 1, Goal = 5, Counted = true })
	CE.Advance(.3)
	check(table.find(rec.Audio, "Toll") ~= nil, "the bell rings")
	local function pip(i)
		return pips:FindFirstChild("Pip" .. i, true)
	end
	local pip1 = pip(1)
	check(pip1.BackgroundColor3 ~= pip(2).BackgroundColor3, "pip 1 lit")
	local n = #rec.Popups
	P.Signal(pctx, "Toll", { Count = 1, Goal = 5, Counted = false })
	check(#rec.Popups == n + 1, "off-beat hint")
	local lines = P.HudLines({ Data = { Count = 1, Goal = 5 } })
	check(lines[1] == "Tolls on the beat: 1 / 5", lines[1])
	P.Update(pctx, { Data = { Count = 3, Goal = 5 } })
	check(pip(3).BackgroundColor3 == pip1.BackgroundColor3, "update lights 3")
	P.Stop(pctx, {}, "Won")
	CE.Advance(2)
	check(not P.Active() and fxFolder:FindFirstChild("UyTollPips") == nil, "torn down after the flourish")
	check(bellParts[1].CFrame == rest, "the bell is back at rest")
	P.Start(pctx, { RunId = 8, TrialId = "Toll", Data = {} })
	P.Stop(pctx, {}, "Failed")
	check(not P.Active() and fxFolder:FindFirstChild("UyTollPips") == nil, "a failure tears down at once")
end)

test("client: Trials.Mourner presenter (dummy beats, the gap marker, verdicts, the heart, the win)", function()
	local P = CE.Require(hc.Trials.Mourner)
	check(P.Ids[1] == "Mourner", "Ids")
	table.clear(rec.Acts)
	CE.Spawn(CV.new(6, 3, 2462))
	P.Start(pctx, { RunId = 9, TrialId = "Mourner", Data = { Need = 2, Dodges = 0, Phase = "Intro", Centre = CV.new(0, 0, 2462) } })
	CE.Advance(.2)
	check(rec.Faces > 0, "the dummy faces the player")
	check(fxFolder:FindFirstChild("UyMournerBoard") ~= nil, "board")
	local now = CE.Unix
	P.Signal(pctx, "MournerAttack", { Attack = "Ring", ImpactAt = now + 2.35, Telegraph = 2, Gap = 90, Target = CV.new(6, 3, 2462) })
	check(rec.Acts[#rec.Acts] == "WindRing", "wind-up")
	check(fxFolder:FindFirstChild("UyMournerGap") ~= nil, "SAFE marker in the gap")
	CE.Advance(2.3)
	check(rec.Acts[#rec.Acts] == "StrikeRing", "strike at the impact")
	P.Signal(pctx, "MournerResult", { Outcome = "Dodged", Dodges = 1, Need = 2, Next = "Next" })
	check(rec.Hurts == 1, "a dodge staggers the dummy")
	check(fxFolder:FindFirstChild("UyMournerGap") == nil, "gap marker cleared")
	local board = fxFolder.UyMournerBoard
	check(board.Board.Callout.Text == "DODGED!", board.Board.Callout.Text)
	P.Signal(pctx, "WeakOpen", { Until = CE.Unix + 15 })
	check(fxFolder:FindFirstChild("UyHeartMark") ~= nil, "heart marker (own, without ctx.Trials.Mark)")
	CE.Advance(.2)
	check(string.find(board.Board.Caption.Text, "HEART OPEN") ~= nil, board.Board.Caption.Text)
	local np = #rec.Popups
	P.Signal(pctx, "WeakMiss", {})
	check(#rec.Popups == np + 1, "ONLY A PERFECT popup")
	P.Signal(pctx, "WeakHit", {})
	check(table.find(rec.Audio, "WeakPointHit") ~= nil, "the strike lands")
	local resets = rec.Resets
	P.Stop(pctx, {}, "Won")
	CE.Advance(3)
	check(not P.Active() and fxFolder:FindFirstChild("UyMournerBoard") == nil, "torn down")
	check(rec.Resets == resets, "the collapse is left to play (no reset on a win)")
	check(P.HudLines({ Data = { Phase = "Weak" } })[1] ~= nil and P.HudLines({ Data = { Dodges = 1, Need = 2 } })[1] == "Dodges this round: 1 / 2", "hud lines")
	P.Start(pctx, { RunId = 10, TrialId = "Mourner", Data = {} })
	P.Stop(pctx, {}, "Failed")
	check(rec.Resets == resets + 1, "a failure resets the dummy")
end)

-- the guide
local view = { Tutorial = { Step = 1, Mark = 20, Current = 1 }, Stats = { ShardsEarned = 24 }, Coffins = { Opened = 0 } }
local CSfake = {
	View = function()
		return view
	end,
	Request = function(action, args)
		table.insert(rec.Requests, { Action = action, Args = args })
		return true, {}
	end,
	T = function(m)
		return m
	end,
}
local cin = { Plays = {} }
function cin.Play(o)
	table.insert(cin.Plays, o)
	return { Id = o.Id }
end
local ghostRig = nil
local Ambient = { Models = {
	Ghost = function(parent)
		local m = CE.Model("HwGhost", parent)
		CE.Part("Body", CV.new(0, 0, 0), CV.new(1, 1, 1), m)
		ghostRig = { Model = m, Update = function() end, Destroy = function(self)
			self.Model:Destroy()
		end }
		return ghostRig
	end,
	GhostPose = function()
		return {}
	end,
} }
local gctx = { Shared = SharedC, Bus = Bus, FX = FXf, Audio = AudioF, Modules = { Chapter2State = CSfake, Cinema = cin, AmbientFX = Ambient,
	UnderyardFX = { Mourner = function()
		return dummyApi
	end } } }
local Guide = CE.Require(hc.Chapter2Guide)
local function guideGui()
	return CE.PlayerGui:FindFirstChild("DOGROTS_Chapter2Guide")
end

test("client: the guide's card per step (title, progress, the way, the pup, the focus)", function()
	CE.Player:SetAttribute("UyInZone", true)
	CE.Player:SetAttribute("UyTutorial", 1)
	CE.Player:SetAttribute("UyTrial", "")
	CE.Spawn(CV.new(0, 3, 2352))
	Guide.Start(gctx)
	CE.Advance(.5)
	local g = guideGui()
	check(g and g.Enabled, "card shown")
	local card = g.Card
	check(card.Head.Kicker.Text == "GHOST GUIDE · STEP 1 / 6", card.Head.Kicker.Text)
	check(card.Title.Text == "BELL SHARDS", card.Title.Text)
	check(card.Progress.Visible and card.Progress.Count.Text == "4 / 10", "progress " .. tostring(card.Progress.Count.Text))
	local st = Guide.State()
	check(st.Pup and st.Chevrons > 0, "pup + chevrons")
	check(st.Prompts.Toll == false and st.Prompts.Mourner == false, "practice prompts hidden on step 1")
	CE.Advance(4)
	check(#cin.Plays >= 1 and cin.Plays[1].Id == "C2Guide" and cin.Plays[1].LockControls == true and cin.Plays[1].HideUI == false, "camera focus")
	-- the pup flies ahead of the player
	CE.Advance(2)
	check(Guide.State().PupMode == "Lead", "leads")
end)

test("client: blockers hide the card only (menu, trial), the step's prompt shows on its step", function()
	mainGui:SetAttribute("OpenMenu", "Shop")
	CE.Advance(.2)
	check(not guideGui().Enabled and Guide.State().Pup, "menu: card off, the pup stays")
	mainGui:SetAttribute("OpenMenu", nil)
	CE.Advance(.2)
	check(guideGui().Enabled, "back")
	CE.Player:SetAttribute("UyTutorial", 2)
	CE.Advance(.3)
	check(guideGui().Card.Title.Text == "FIRST TRIAL", guideGui().Card.Title.Text)
	check(Guide.State().Prompts.Toll == true and Guide.State().Prompts.Mourner == false, "the Toll prompt on step 2")
	check(table.find(rec.Audio, "QuestDone") ~= nil, "a chime for the new step")
	CE.Player:SetAttribute("UyTrial", "Toll:3")
	CE.Advance(.2)
	check(not guideGui().Enabled and Guide.State().Prompts.Toll == false, "in the trial: no card, no prompt")
	Bus.Fire("C2Signal", { Kind = "C2Trial", Data = { Kind = "Failed", TrialId = "Toll", Reason = "Time" } })
	CE.Player:SetAttribute("UyTrial", "")
	CE.Advance(.3)
	check(guideGui().Enabled and string.find(guideGui().Card.Hint.Text, "Not this time") ~= nil, "try again hint")
end)

test("client: the practice ring step asks the server once the player stands in it", function()
	CE.Player:SetAttribute("UyTutorial", 4)
	CE.Advance(.3)
	table.clear(rec.Requests)
	CE.MoveTo(CV.new(1, 3, 2463))
	CE.Advance(1.6)
	local asked = nil
	for _, r in ipairs(rec.Requests) do
		if r.Action == "C2Tutorial" and r.Args.Step == 4 then
			asked = r
		end
	end
	check(asked ~= nil, "C2Tutorial {Step = 4}")
end)

test("client: Russian, leaving the zone, skip (tap twice), no final card after a skip", function()
	CE.Player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(6) -- Shared caches the language for 5 s
	check(string.find(guideGui().Card.Head.Kicker.Text, "ПРИЗРАЧНЫЙ ПРОВОДНИК") ~= nil, guideGui().Card.Head.Kicker.Text)
	check(guideGui().Card.Title.Text == "ЗДОРОВЬЕ СОБЫТИЯ", guideGui().Card.Title.Text)
	CE.Player:SetAttribute("DOGROTS_Language", "en")
	CE.Advance(6)
	CE.Player:SetAttribute("UyInZone", false)
	CE.Advance(.2)
	check(not guideGui().Enabled and not Guide.State().Pup, "out of the zone: nothing")
	CE.Player:SetAttribute("UyInZone", true)
	CE.Advance(.3)
	local skip = guideGui().Card.Buttons.Skip
	table.clear(rec.Requests)
	CE.Click(skip)
	check(skip.Text == "TAP AGAIN TO SKIP" and #rec.Requests == 0, "first tap arms")
	CE.Click(skip)
	CE.Advance(.3)
	check(#rec.Requests == 1 and rec.Requests[1].Args.Skip == true, "second tap skips")
	CE.Player:SetAttribute("UyTutorial", -1)
	CE.Advance(.3)
	check(not guideGui().Enabled and not Guide.State().Final, "no final card after a skip")
	check(Guide.State().Prompts.Toll == false and Guide.State().Prompts.Mourner == false, "prompts stay hidden after the guide")
end)

test("client: the final card after the sixth step (GOT IT), phone layout, teardown", function()
	CE.Player:SetAttribute("UyTutorial", 6)
	CE.Advance(14) -- (well past the skip window)
	CE.Player:SetAttribute("UyTutorial", -1)
	CE.Advance(.3)
	local g = guideGui()
	check(g.Enabled and Guide.State().Final, "final card")
	check(g.Card.Title.Text == "THE UNDERYARD IS YOURS" and g.Card.Buttons.GotIt.Visible, "GOT IT")
	CE.Click(g.Card.Buttons.GotIt)
	CE.Advance(.3)
	check(not guideGui().Enabled and not Guide.State().Final, "closed")
	-- a phone: narrower card, higher above the thumbstick, the pill after a while
	CE.Camera.ViewportSize = roblox.Vector2.new(390, 844)
	CE.UserInputService.TouchEnabled = true
	CE.UserInputService.KeyboardEnabled = false
	CE.Player:SetAttribute("UyTutorial", 3)
	CE.Advance(.3)
	local card = guideGui().Card
	check(card.Size.X.Offset <= 366 and card.Position.Y.Offset == -210, "phone layout " .. card.Size.X.Offset .. " / " .. card.Position.Y.Offset)
	CE.Advance(15)
	check(Guide.State().Collapsed and guideGui().Pill.Visible and not guideGui().Card.Visible, "collapsed to the pill on a small screen")
	CE.Click(guideGui().Pill)
	CE.Advance(.2)
	check(guideGui().Card.Visible, "the pill expands the card")
	CE.UserInputService.TouchEnabled = false
	CE.UserInputService.KeyboardEnabled = true
	Guide.Stop()
	check(guideGui() == nil, "layer destroyed")
	check(tutPrompts.Toll.Enabled == true and tutPrompts.Mourner.Enabled == true, "prompts handed back")
	local errs = {}
	for _, e in ipairs(CE.Errors) do
		table.insert(errs, e)
	end
	for _, w in ipairs(CE.Warnings) do
		if string.find(w, "Chapter2Guide") or string.find(w, "Trials") or string.find(w, "UnderyardFX") then
			table.insert(errs, w)
		end
	end
	check(#errs == 0, table.concat(errs, "\n"))
end)

-----------------------------------------------------------------------------------------------------------------------
-- 5. client: UnderyardFX on a small fake world (the real module, the client_env clock)
-----------------------------------------------------------------------------------------------------------------------
local CFr = roblox.CFrame
local function part(name, at, parent, props)
	local p = CE.Part(name, at, CV.new(1, 1, 1), parent)
	p.Material = roblox.Enum.Material.SmoothPlastic
	p.Color = roblox.Color3.fromRGB(120, 120, 120)
	p.Transparency = 0
	p.CanCollide = false
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return p
end
-- gate (veil hidden from seal I, a sign with both languages)
local gatesM = CE.Model("Gates", uy)
local gate = CE.Model("Gate_FuneralCarnival", gatesM)
gate:SetAttribute("UyGate", "FuneralCarnival")
gate:SetAttribute("UySeal", 1)
local veil = part("VeilStrip", CV.new(68, 6, 2332), gate, { Material = roblox.Enum.Material.Neon, Transparency = .55 })
veil:SetAttribute("UyHideAtSeal", 1)
local plaque = part("SealPlaque", CV.new(68, 13, 2333), gate)
local sgui = CE.Instance.new("SurfaceGui")
sgui:SetAttribute("TextEN", "SEALED")
sgui:SetAttribute("TextRU", "ЗАПЕЧАТАНО")
sgui:SetAttribute("UyHideAtSeal", 1)
sgui.Enabled = true
local slabel = CE.Instance.new("TextLabel")
slabel.Text = "SEALED"
slabel:SetAttribute("TextEN", "SEALED")
slabel:SetAttribute("TextRU", "ЗАПЕЧАТАНО")
slabel.Parent = sgui
sgui.Parent = plaque
-- a pendulum (hinge at 17, the coffin 6 below), the carousel, an eye window, the ghost audience, a seal lamp
local carn = CE.Model("FuneralCarnival", uy)
local pend = CE.Model("RunPendulum_1", carn)
local hinge = part("PendulumHinge", CV.new(132, 17, 2298), pend, { Transparency = 1 })
pend.PrimaryPart = hinge
local coffin = part("PendulumCoffin", CV.new(132, 11, 2298), pend)
pend:SetAttribute("UySwingAmp", 1)
pend:SetAttribute("UySwingPeriod", 3.2)
pend:SetAttribute("UySwingPhase", 0)
pend:SetAttribute("UySwingAxis", "Z")
local car = CE.Model("Carousel", carn)
local hub = part("CarouselHub", CV.new(105, .9, 2215), car, { Transparency = 1 })
car.PrimaryPart = hub
local horse = part("Mount", CV.new(112, 2, 2215), car)
local deckP = part("CarouselDeck", CV.new(105, .6, 2215), car, { CanCollide = true })
car:SetAttribute("UySpin", .35)
car:SetAttribute("UySpinAxis", "Y")
local audience = CE.Model("GhostAudience", carn)
audience:SetAttribute("UyShowAtSeal", 2)
local ghostSeat = part("GhostSitter", CV.new(150, 3, 2240), audience)
local lampGlass = part("LanternGlass", CV.new(120, 6, 2280), carn, { Material = roblox.Enum.Material.Neon })
lampGlass:SetAttribute("UyLightAtSeal", 3)
lampGlass:SetAttribute("HwLantern", "Orange")
local crooked = CE.Model("CrookedRow", uy)
local eye = CE.Model("EyeWindow", crooked)
eye:SetAttribute("UyBlink", true)
eye:SetAttribute("EyeHeight", 2)
local pane = part("EyePane", CV.new(-120, 8, 2260), eye)
local lidTop = part("EyelidTop", CV.new(-120, 9.2, 2259.7), eye)
lidTop:SetAttribute("LidDir", -1)
lidTop:SetAttribute("LidTravel", .74)
local lidRest = lidTop.CFrame
part("EyePupil", CV.new(-120, 8, 2259.8), eye)
-- FX markers (numbered and not)
local fxm = CE.Model("FXMarkers", uy)
fxm:SetAttribute("SelfManagedFX", true)
local holder = part("MothMarkers", CV.new(0, 4, 2400), fxm, { Transparency = 1 })
for _, row in ipairs({ { "MothSwarm_1", CV.new(0, 6, 2410) }, { "FogPoint", CV.new(5, 1, 2410) }, { "GhostResident_1", CV.new(-6, 3, 2410) } }) do
	local a = CE.Instance.new("Attachment")
	a.Name = row[1]
	a.CFrame = CFr.new(row[2] - holder.CFrame.Position)
	a:SetAttribute("Radius", 3)
	a:SetAttribute("Count", 6)
	a.Parent = holder
end

local fxctx = { Shared = SharedC, Bus = Bus, FX = FXf, Audio = AudioF, Modules = { AmbientFX = { Models = {
	Ghost = function(parent)
		local m = CE.Model("HwGhost", parent)
		CE.Part("Sheet", CV.new(0, 0, 0), CV.new(1, 1, 1), m)
		return { Model = m, Update = function() end, SetFade = function() end, Destroy = function()
			m:Destroy()
		end }
	end,
	GhostPose = function()
		return {}
	end,
	Wisp = function(parent)
		local m = CE.Model("HwWisp", parent)
		return { Model = m, Update = function() end, SetFade = function() end, Destroy = function()
			m:Destroy()
		end }
	end,
} } } }
local UFX = CE.Require(hc.UnderyardFX)
local opened = {}
Bus.On("UyGateOpened", function(d)
	table.insert(opened, d.District)
end)

test("client: UnderyardFX applies the seal state, localizes signs, registers movers / markers", function()
	CE.Player:SetAttribute("UySealMask", "0000000")
	CE.Player:SetAttribute("DOGROTS_Language", "en")
	CE.Camera.CFrame = CFr.new(0, 10, 2420)
	CE.MoveTo(CV.new(0, 3, 2420))
	UFX.Start(fxctx)
	CE.Advance(1.5)
	local st = UFX.Stats()
	check(st.Ready, "scanned")
	check(ghostSeat.LocalTransparencyModifier == 1, "UyShowAtSeal 2 hidden at 0 (inherited from its model)")
	check(veil.LocalTransparencyModifier < .5, "the veil shows while sealed")
	check(sgui.Enabled == true, "the SEALED sign shows")
	check(lampGlass.Material == roblox.Enum.Material.SmoothPlastic, "an unlit seal lamp is dark")
	check(slabel.Text == "SEALED", "English sign")
	check(st.Movers == 3 and st.Markers == 3, string.format("movers %d markers %d", st.Movers, st.Markers))
	check(UFX.Cleared() == 0, "cleared")
end)

test("client: UnderyardFX motion: the pendulum follows the §24.2 formula on server time, the carousel turns, eyes blink", function()
	-- the camera next to the carnival + crooked row so they are in range
	CE.Camera.CFrame = CFr.new(60, 10, 2290)
	local maxLid = 0
	for _ = 1, 160 do
		CE.Step(1 / 15)
		maxLid = math.max(maxLid, (lidTop.CFrame.Position - lidRest.Position).Magnitude)
	end
	local off = coffin.CFrame.Position - hinge.CFrame.Position
	local angle = math.atan2(off.X, -off.Y)
	local want = R.SwingAngle(1, 3.2, 0, CE.Unix)
	check(math.abs(angle - want) < .2, string.format("pendulum %.3f vs %.3f", angle, want))
	check(math.abs(off.Magnitude - 6) < 1e-3, "rigid")
	check((horse.CFrame.Position - CV.new(112, 2, 2215)).Magnitude > .01, "the carousel's mounts turn")
	check(deckP.CFrame.Position == CV.new(105, .6, 2215), "the walkable deck does not move")
	check(maxLid > .3, "the eye blinks (lid travel " .. maxLid .. ")")
end)

test("client: UnderyardFX on a new seal: the veil dissolves, the audience fades in, the gate bursts; lamps light at their seal", function()
	CE.Player:SetAttribute("UySealMask", "1100000")
	CE.Advance(.2)
	check(UFX.Stats().Pending, "held until the seal-clear moment")
	CE.Advance(4)
	check(UFX.Cleared() == 2 and not UFX.Stats().Pending, "applied")
	check(ghostSeat.LocalTransparencyModifier == 0, "the audience appears at seal II")
	check(veil.LocalTransparencyModifier == 1 and sgui.Enabled == false, "the veil and the SEALED sign are gone")
	check(table.find(opened, "FuneralCarnival") ~= nil and table.find(rec.Audio, "SealIgnite") ~= nil, "gate burst")
	check(lampGlass.Material == roblox.Enum.Material.SmoothPlastic, "seal III lamp still dark")
	CE.Player:SetAttribute("UySealMask", "1110000")
	Bus.Fire("UySealReveal", {})
	CE.Advance(3)
	check(lampGlass.Material == roblox.Enum.Material.Neon, "lit at seal III")
	-- a lower count (a reset / another profile) applies at once
	CE.Player:SetAttribute("UySealMask", "0000000")
	CE.Advance(.2)
	check(ghostSeat.LocalTransparencyModifier == 1 and veil.LocalTransparencyModifier < .5, "instant rollback")
end)

test("client: UnderyardFX signs follow the language; the Mourner dummy; tutorial echo visuals (owner only)", function()
	CE.Player:SetAttribute("DOGROTS_Language", "ru")
	CE.Advance(6.5)
	check(slabel.Text == "ЗАПЕЧАТАНО", "Russian sign: " .. slabel.Text)
	CE.Player:SetAttribute("DOGROTS_Language", "en")
	CE.Advance(6.5)
	check(slabel.Text == "SEALED", "back to English")
	CE.Camera.CFrame = CFr.new(0, 10, 2445)
	CE.Advance(.5)
	local m = UFX.Mourner()
	check(m and m.Built() and m.Model() ~= nil, "the Mourner stands on its pedestal")
	local heart = m.Heart()
	check(math.abs(heart.Y - 4.4) < .3 and math.abs(heart.Z - 2462) < 1, "its heart is the server's weak spot (y 4.4): " .. tostring(heart))
	-- an echo of mine appears with an orb, someone else's does not
	local mine = part("Target_1", CV.new(-24, 1.6, 2372), CE.Workspace, { Transparency = 1 })
	mine:SetAttribute("Kind", "UyTutorialEcho")
	mine:SetAttribute("OwnerUserId", CE.Player.UserId)
	mine:SetAttribute("HP", 3)
	mine:SetAttribute("MaxHP", 3)
	local theirs = part("Target_2", CV.new(26, 1.6, 2376), CE.Workspace, { Transparency = 1 })
	theirs:SetAttribute("Kind", "UyTutorialEcho")
	theirs:SetAttribute("OwnerUserId", 999)
	tagAdded:Fire(mine)
	tagAdded:Fire(theirs)
	CE.Advance(.3)
	local folder = fxFolder:FindFirstChild("UnderyardFX")
	local orbs = 0
	for _, d in ipairs(folder:GetChildren()) do
		if d.Name == "UyTutorialEchoFX" then
			orbs += 1
		end
	end
	check(orbs == 1, "one orb (mine) " .. orbs)
	mine:SetAttribute("EndReason", "Broke")
	tagRemoved:Fire(mine)
	CE.Advance(.1)
	check(folder:FindFirstChild("UyTutorialEchoFX") == nil and table.find(rec.Audio, "SoulBurst") ~= nil, "dug out: burst")
	-- the weak spot opens the dummy; struck (reason Won) it collapses
	local weak = part("Target_3", CV.new(0, 4.4, 2462), CE.Workspace, { Transparency = 1 })
	weak:SetAttribute("Kind", "UyMournerWeak")
	weak:SetAttribute("OwnerUserId", CE.Player.UserId)
	tagAdded:Fire(weak)
	CE.Advance(.8)
	check(table.find(rec.Audio, "WeakOpen") ~= nil, "the heart opens")
	weak:SetAttribute("EndReason", "Won")
	tagRemoved:Fire(weak)
	CE.Advance(.5)
end)

test("client: UnderyardFX stop restores every part it touched", function()
	UFX.Stop()
	check(ghostSeat.LocalTransparencyModifier == 0 and veil.LocalTransparencyModifier == 0, "parts restored")
	check(sgui.Enabled == true, "gui restored")
	check(lampGlass.Material == roblox.Enum.Material.Neon, "lamp material restored")
	check((coffin.CFrame.Position - CV.new(132, 11, 2298)).Magnitude < 1e-3, "pendulum back at rest")
	check(fxFolder:FindFirstChild("UnderyardFX") == nil, "client folder gone")
	local errs = {}
	for _, e in ipairs(CE.Errors) do
		table.insert(errs, e)
	end
	for _, w in ipairs(CE.Warnings) do
		if string.find(w, "UnderyardFX") then
			table.insert(errs, w)
		end
	end
	check(#errs == 0, table.concat(errs, "\n"))
end)

test("client: Lighting composes UNDERYARD (Prio 35) inside the zone, Y counts, island layers zeroed, back on the island", function()
	local Lt = CE.Require(hc.Lighting)
	local C3 = roblox.Color3.fromRGB
	Lt.Configure({ Shared = SharedC, Layout = SharedC.Layout, Underyard = CE.Require(RSc.Halloween.UnderyardRuntime) })
	Lt.TestGrade = { Enabled = false }
	Lt.NoSkyCreate = true
	local mocks = {
		Lighting = { ClockTime = 14, Brightness = 2, ExposureCompensation = 0, Ambient = C3(128, 128, 128), OutdoorAmbient = C3(128, 128, 128),
			ColorShift_Top = C3(0, 0, 0) },
		Atmo = { Density = .3, Offset = 0, Color = C3(199, 199, 199), Decay = C3(106, 112, 125), Glare = 0, Haze = 0 },
		Bloom = { Intensity = 1, Size = 24, Threshold = 2 },
	}
	Lt.Bind(mocks)
	local clock = 1000
	local function run(cam, seconds, extra)
		for _ = 1, math.floor(seconds * 20) do
			clock += 1 / 20
			local s = { CamPos = cam, Clock = clock, DayFactor = 1, Enabled = true }
			for k, v in pairs(extra or {}) do
				s[k] = v
			end
			Lt.Step(1 / 20, s)
		end
	end
	-- inside the Underyard during a Blood Moon with the boss enraged on the island: nothing of that leaks in
	run(V(0, 20, 2400), 4, { BloodAlpha = 1, Enraged = true })
	local W = Lt.Weights()
	check(W.Under > .99, "under weight " .. W.Under)
	check(math.abs(mocks.Lighting.ClockTime - .5) < .02 and math.abs(mocks.Lighting.Brightness - .9) < .02, "clock / brightness " .. mocks.Lighting.ClockTime)
	check(mocks.Lighting.Ambient == C3(52, 48, 92) or (mocks.Lighting.Ambient.R - 52 / 255) < .01, "ambient")
	check(math.abs(mocks.Atmo.Density - .32) < .01 and math.abs(mocks.Atmo.Haze - 2.4) < .02, "atmosphere")
	check(math.abs(mocks.Bloom.Intensity - .55) < .01 and math.abs(mocks.Bloom.Size - 26) < .1, "bloom")
	-- under the zone box (Y counts): the profile fades out
	run(V(0, -40 - 80, 2400), 4)
	check(Lt.Weights().Under < .01, "far below the cavern floor: not the Underyard")
	-- back on the island by day: the base returns
	run(V(0, 20, 400), 4)
	check(Lt.Weights().Under < .01 and math.abs(mocks.Lighting.ClockTime - 14) < .05, "island base restored " .. mocks.Lighting.ClockTime)
end)

print(string.format("underyard_runtime: %d passed, %d failed", passed, failed))
if failed > 0 then
	require("@lune/process").exit(1)
end
