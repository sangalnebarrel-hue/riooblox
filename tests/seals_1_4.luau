--!nocheck
-- BELL SEALS I-IV (WP-I): the pure rules (ReplicatedStorage.Halloween.SealRules) and the four activity servers
-- (ServerScriptService.Halloween.SealEcho / SealRun / SealMirror / SealMine) on the REAL trials framework
-- (ServerScriptService.Halloween.Seals) with fake players, a manual clock and fake Chapter2 / Underyard / EventHP / Strike
-- modules; then the client trials HUD and presenters (HalloweenClient.Trials) in the headless fake client.
-- Run: lune run tests/seals_1_4.luau
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local V3, CF = roblox.Vector3.new, roblox.CFrame

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function yes(v, msg)
	if not v then
		error(msg or "expected true", 2)
	end
end
local function no(v, msg)
	if v then
		error(msg or "expected false", 2)
	end
end

local Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Layout = L.Require("ReplicatedStorage.Halloween.UnderyardLayout")
local Hazards = L.Require("ReplicatedStorage.Halloween.Hazards")
local Rules = L.Require("ReplicatedStorage.Halloween.SealRules")
local SC = L.Require("ReplicatedStorage.Halloween.SealConfig")

---------------------------------------------------------------------------------------------------------------------
-- pure rules
---------------------------------------------------------------------------------------------------------------------
test("activity numbers: Chapter2Config.Seals[i].Activity wins over SealConfig, every key the servers read exists", function()
	for i = 1, 4 do
		local a = Rules.Activity(i)
		eq(a.Countdown, SC.Countdown, "countdown " .. i)
		for k, v in pairs(Cfg.Seals[i].Activity) do
			eq(a[k], v, "seal " .. i .. " key " .. k)
		end
	end
	local e = Rules.Activity(1)
	for _, k in ipairs({ "Points", "Life", "Trail", "MaxAlive", "ObjectiveShards", "Range", "HitSize", "Lift", "RespawnDelay", "MinJumpDistance" }) do
		yes(e[k] ~= nil, "echo " .. k)
	end
	local r = Rules.Activity(2)
	for _, k in ipairs({ "Checkpoints", "PendulumPeriod", "PendulumDamage", "PendulumKnock", "MaxSpeed", "SpeedSlack", "CheckpointRadius",
		"JumpSlack", "LegTimeSlack", "PendulumArm", "PendulumStrip", "PendulumTelegraph", "MaxViolations" }) do
		yes(r[k] ~= nil, "run " .. k)
	end
	local m = Rules.Activity(3)
	for _, k in ipairs({ "Graves", "Rounds", "WrongPenalty", "ObjectiveShards", "StartAnchor", "TurnRange", "ConsultRange", "TurnCooldown" }) do
		yes(m[k] ~= nil, "mirror " .. k)
	end
	local h = Rules.Activity(4)
	for _, k in ipairs({ "Nodes", "Respawn", "NodeHits", "Rocks", "Gas", "Tunnel", "Unit", "PartyHP", "HazardDelay", "StartAnchor" }) do
		yes(h[k] ~= nil, "mine " .. k)
	end
	eq(h.Rocks.Radius, 6)
	eq(h.Rocks.Telegraph, 1.4)
	eq(h.Rocks.Damage, 18)
	eq(h.Gas.Radius, 5)
	eq(h.Gas.DPS, 6)
	eq(r.PendulumDamage, 12)
	eq(r.MaxSpeed, 72)
	near(r.SpeedSlack, 1.15)
end)

test("§24.2 pendulum: angle = Amp sin(2 pi (t mod P) / P + Phase) on the server clock, passes every P / 2", function()
	local act = Rules.Activity(2)
	local hinge = CF.new(10, 17, 20) * CF.Angles(0, .7, 0)
	local spec = Rules.PendulumSpec(2, hinge, { UySwingAmp = 1, UySwingPeriod = 3.2, UySwingPhase = 2.0943951023931953 }, act)
	for _, t in ipairs({ 0, .4, 1.7, 1760000000.13, 1760000123.9 }) do
		local want = 1 * math.sin(2 * math.pi * (t % 3.2) / 3.2 + 2.0943951023931953)
		near(Rules.SwingAngle(t, spec.Amp, spec.Period, spec.Phase), want, 1e-9, "angle at " .. t)
	end
	-- phase 0 = exactly the DESIGN §24.2 formula
	for _, t in ipairs({ .1, 2.5, 99.99 }) do
		near(Rules.SwingAngle(t, 1.3, 3.2, 0), 1.3 * math.sin(2 * math.pi * (t % 3.2) / 3.2), 1e-12)
	end
	local t0 = 1760000000
	local passes = Rules.Crossings(spec, t0, t0 + 6.4)
	eq(#passes, 4, "two passes per period")
	for i, p in ipairs(passes) do
		near(Rules.SwingAngle(p.T, spec.Amp, spec.Period, spec.Phase), 0, 1e-6, "angle zero at a pass")
		if i > 1 then
			near(p.T - passes[i - 1].T, 1.6, 1e-6, "half a period apart")
			eq(p.Dir, -passes[i - 1].Dir, "alternating swing direction")
		end
		-- the pass direction is the sign of the angular velocity
		local rate = Rules.SwingRate(p.T, spec.Amp, spec.Period, spec.Phase)
		eq(p.Dir, rate > 0 and 1 or -1, "dir follows the rate")
		-- the coffin hangs straight under the hinge at a pass
		local c = Rules.CoffinCFrame(spec, p.T)
		near((c.Position - (hinge.Position - V3(0, act.PendulumArm, 0))).Magnitude, 0, 1e-4, "coffin under the hinge")
	end
	-- at a quarter period the coffin is out to the side by Arm * sin(Amp)
	local quarter = passes[1].T + .8
	local c = Rules.CoffinCFrame(spec, quarter)
	local side = hinge:PointToObjectSpace(c.Position)
	near(math.abs(side.X), act.PendulumArm * math.sin(1), 1e-3, "full swing across the lane")
end)

test("pendulum hazard: a fair Box strip across the lane under the hinge, impact at the pass, knock-back", function()
	local act = Rules.Activity(2)
	local hinge = CF.new(132, 17, 2298) * CF.Angles(0, math.pi / 2, 0)
	local spec = Rules.PendulumSpec(1, hinge, nil, act)
	local pass = Rules.Crossings(spec, 1000, 1004)[1]
	local def = Rules.PendulumHazard(spec, pass, act)
	eq(def.Kind, "Pendulum")
	eq(def.ImpactAt, pass.T)
	eq(def.Damage, 12)
	-- the knock-back throws ALONG the swing (never along the lane), the way the coffin moves at this pass
	eq(def.Knock, nil, "no radial hazard knock")
	local kv = def.KnockVelocity
	near(kv:Dot(hinge.RightVector), pass.Dir * act.PendulumKnock, 1e-6, "along the swing")
	near(kv:Dot(Rules.Flat(hinge.LookVector).Unit), 0, 1e-6, "not along the lane")
	near(kv.Y, act.PendulumKnockUp, 1e-6, "lift")
	local next = Rules.Crossings(spec, pass.T + .01, pass.T + 3)[1]
	near(Rules.PendulumHazard(spec, next, act).KnockVelocity:Dot(hinge.RightVector), -pass.Dir * act.PendulumKnock, 1e-6, "the next pass throws the other way")
	yes(def.Telegraph >= Cfg.Combat.Hazards.MinTelegraph, "telegraph >= the minimum")
	local ok, problems = Hazards.Check(def, { Trial = true })
	yes(ok, "fair: " .. table.concat(problems or {}, "; "))
	-- the strip covers the lane centre and both lane edges under the hinge, not a runner 6 studs before it
	local right, look = hinge.RightVector, hinge.LookVector
	local ground = V3(132, 3, 2298)
	yes(Hazards.Contains(def.Shape, ground), "lane centre")
	yes(Hazards.Contains(def.Shape, ground + right * 5.5), "right edge of the lane")
	yes(Hazards.Contains(def.Shape, ground - right * 5.5), "left edge of the lane")
	no(Hazards.Contains(def.Shape, ground + look * 6), "a runner before the strip is safe")
	no(Hazards.Contains(def.Shape, ground - look * 6), "a runner after the strip is safe")
	-- without the place's hinge model: the layout point, the lane direction of the nearest leg, the phase spread
	local path = { Layout.Carnival.RunStart }
	for _, p in ipairs(Layout.Carnival.Checkpoints) do
		table.insert(path, p)
	end
	local fb = Rules.FallbackHinge(Layout.Carnival.Pendulums[1], path, act)
	near(fb.Position.Y, 17)
	local legDir = Rules.Flat(Layout.Carnival.Checkpoints[2] - Layout.Carnival.Checkpoints[1]).Unit
	near(math.abs(fb.LookVector:Dot(legDir)), 1, 1e-3, "faces along the leg it hangs over")
	near(Rules.PendulumSpec(3, fb, nil, act).Phase, 2 * 2.0943951023931953, 1e-9, "phase spread (i - 1) * 2 pi / 3")
end)

-- a runner along a polyline at `speed` studs / s, sampled at 4 Hz from t0 -> {{T, Pos}}
local function samples(points, speed, t0, dt)
	dt = dt or .25
	local out = { { T = t0, Pos = points[1] } }
	local t, seg, along = t0, 1, 0
	while seg < #points do
		t += dt
		local left = speed * dt
		local pos = nil
		while left > 0 and seg < #points do
			local a, b = points[seg], points[seg + 1]
			local len = (b - a).Magnitude
			if along + left < len then
				along += left
				left = 0
				pos = a:Lerp(b, along / len)
			else
				left -= len - along
				seg += 1
				along = 0
				pos = points[seg]
			end
		end
		table.insert(out, { T = t, Pos = pos })
	end
	return out
end

local function course(start)
	local pts = { start }
	for i = 1, 10 do
		table.insert(pts, Layout.Anchor("RunCheckpoint_" .. i))
	end
	return pts
end

test("leg-time anti-cheat: a top-speed runner finishes, teleports and sustained speed hacks are caught", function()
	local act = Rules.Activity(2)
	local cps = {}
	for i = 1, 10 do
		cps[i] = Layout.Anchor("RunCheckpoint_" .. i)
	end
	local start = Layout.Anchor("RunStart")
	local function runAt(speed)
		local st = Rules.NewRunner(start, 5000)
		local evs = {}
		for _, s in ipairs(samples(course(start), speed, 5000)) do
			for _, e in ipairs(Rules.RunStep(st, s.Pos, s.T, cps, act)) do
				table.insert(evs, e)
			end
			if st.Rewind then
				break
			end
		end
		return st, evs
	end
	for _, speed in ipairs({ 16, 30, 72, 80 }) do
		local st, evs = runAt(speed)
		yes(st.Done, "honest " .. speed .. " studs/s finishes")
		eq(st.Violations, 0, "no violation at " .. speed)
		local n = 0
		for _, e in ipairs(evs) do
			if e.Kind == "Checkpoint" then
				n += 1
				eq(e.Index, n, "rings in order")
			end
		end
		eq(n, 10)
	end
	-- the course is long enough that a 72 studs/s runner needs its time: finish time ~ distance / speed
	local st72 = runAt(72)
	local dist = 0
	local pts = course(start)
	for i = 2, #pts do
		dist += Rules.Flat(pts[i] - pts[i - 1]).Magnitude
	end
	yes(st72.FinishAt - 5000 > dist / 72 - 1, "finish time follows the distance")
	-- sustained speed hacks (1.25x and 1.6x the maximum) fail the legs-since-GO check before the finish
	for _, speed in ipairs({ 104, 125 }) do
		local st, evs = runAt(speed)
		no(st.Done, "speed hack " .. speed .. " does not finish")
		yes(st.Rewind and st.Violations == 1, "a violation")
		local kind = evs[#evs].Kind
		if speed < 110 then
			eq(kind, "TooFast", "caught by the leg time at " .. speed)
		else
			yes(kind == "TooFast" or kind == "Jump", "caught at " .. speed)
		end
	end
	-- a teleport: from the start straight onto ring 4 in one sample
	local st = Rules.NewRunner(start, 5000)
	Rules.RunStep(st, start, 5000.25, cps, act)
	local evs = Rules.RunStep(st, cps[4], 5000.5, cps, act)
	eq(evs[1].Kind, "Jump", "teleport detected")
	eq(st.Next, 1, "nothing credited")
	-- skipping rings: running around rings 1 and 2 straight to ring 3 never counts it
	st = Rules.NewRunner(start, 5000)
	for _, s in ipairs(samples({ start, V3(100, 3, 2270), cps[3] }, 20, 5000)) do
		Rules.RunStep(st, s.Pos, s.T, cps, act)
	end
	eq(st.Next, 1, "ring 3 does not count before rings 1 and 2")
	-- a rewind starts a fresh segment at the last ring
	st = Rules.NewRunner(start, 5000)
	Rules.RunStep(st, start, 5000.25, cps, act)
	Rules.RunStep(st, cps[3], 5000.5, cps, act)
	yes(st.Rewind)
	Rules.Rewound(st, 5001, start)
	no(st.Rewind)
	eq(st.LegAt, 5001)
	eq(st.SegDist, 0)
	local finished = false
	for _, s in ipairs(samples(course(start), 30, 5001)) do
		Rules.RunStep(st, s.Pos, s.T, cps, act)
		finished = finished or st.Done
	end
	yes(finished, "finishes honestly after a rewind")
	eq(st.Violations, 1)
end)

test("leg-time: a pendulum knock-back is forgiven (fast samples and a time credit), lagged positions still count", function()
	local act = Rules.Activity(2)
	local cps = {}
	for i = 1, 10 do
		cps[i] = Layout.Anchor("RunCheckpoint_" .. i)
	end
	local start = Layout.Anchor("RunStart")
	local st = Rules.NewRunner(start, 100)
	Rules.RunStep(st, start, 100.25, cps, act)
	-- knocked: 34 studs sideways in one .25 s sample would be a jump, inside the knock window it is not
	local away = Rules.Flat(start - cps[1]).Unit
	local p = start + away * 34
	local plain = Rules.NewRunner(start, 100)
	Rules.RunStep(plain, start, 100.25, cps, act)
	local evs = Rules.RunStep(plain, p, 100.5, cps, act)
	eq(evs[1] and evs[1].Kind, "Jump", "without a knock it is a jump")
	Rules.Knocked(st, 101.5, act)
	evs = Rules.RunStep(st, p, 100.5, cps, act)
	eq(#evs, 0, "no jump while knocked")
	yes(st.Credit > 0, "time credit")
	-- a network stall: the server sees no movement for 1 s, then the whole distance at once
	st = Rules.NewRunner(start, 200)
	Rules.RunStep(st, start, 200.25, cps, act)
	Rules.RunStep(st, start, 200.5, cps, act)
	Rules.RunStep(st, start, 200.75, cps, act)
	Rules.RunStep(st, start, 201, cps, act)
	evs = Rules.RunStep(st, start + Rules.Flat(cps[1] - start).Unit * 60, 201.25, cps, act)
	for _, e in ipairs(evs) do
		yes(e.Kind == "Checkpoint", "60 studs after a 1 s stall is honest at 72 studs/s (" .. e.Kind .. ")")
	end
	no(st.Rewind, "no rewind after a stall")
	-- a lagged sample that misses the ring centre by 8 studs still credits it (radius + slack)
	st = Rules.NewRunner(start, 300)
	local side = V3(-(cps[1] - start).Z, 0, (cps[1] - start).X).Unit * 8
	local path = { start, cps[1] + side, cps[2] }
	local got = false
	for _, s in ipairs(samples(path, 25, 300)) do
		for _, e in ipairs(Rules.RunStep(st, s.Pos, s.T, cps, act)) do
			got = got or (e.Kind == "Checkpoint" and e.Index == 1)
		end
	end
	yes(got, "ring 1 credited from 8 studs off-centre")
end)

test("the carousel leg is found geometrically from the layout (the lane crosses the deck)", function()
	local cps = {}
	for i = 1, 10 do
		cps[i] = Layout.Carnival.Checkpoints[i]
	end
	local leg = Rules.CarouselLeg(cps, Layout.Carnival.Carousel.Centre, Layout.Carnival.Carousel.Radius)
	yes(leg ~= nil, "a leg crosses the carousel")
	local d = Rules.SegmentClosest(cps[leg], cps[leg + 1], Layout.Carnival.Carousel.Centre)
	yes(d <= Layout.Carnival.Carousel.Radius)
end)

test("mirror: daily seed is deterministic per player and day; rounds of 4 / 5 / 6 graves, mostly wrong at the start", function()
	local act = Rules.Activity(3)
	local a1 = Rules.MirrorRounds(Rules.MirrorSeed(12345, 20380), act)
	local a2 = Rules.MirrorRounds(Rules.MirrorSeed(12345, 20380), act)
	local b = Rules.MirrorRounds(Rules.MirrorSeed(12345, 20381), act)
	local c = Rules.MirrorRounds(Rules.MirrorSeed(54321, 20380), act)
	local function key(rounds)
		local s = {}
		for _, r in ipairs(rounds) do
			table.insert(s, table.concat(r.Active, ",") .. "|")
			for i = 1, 6 do
				table.insert(s, r.Target[i] .. r.Start[i])
			end
		end
		return table.concat(s)
	end
	eq(key(a1), key(a2), "same player, same day: same puzzle")
	yes(key(a1) ~= key(b), "a new UTC day: a new puzzle")
	yes(key(a1) ~= key(c), "another player: another puzzle")
	-- over many seeds: sizes, distinct sorted graves, directions 0..3, at least 3/4 of the active graves start wrong
	for s = 1, 400 do
		local rounds = Rules.MirrorRounds(Rules.MirrorSeed(s * 7919, 20380 + s % 9), act)
		eq(#rounds, 3)
		for r, round in ipairs(rounds) do
			eq(#round.Active, act.Rounds[r], "round size")
			local seen = {}
			for k, g in ipairs(round.Active) do
				yes(g >= 1 and g <= 6 and not seen[g], "distinct grave")
				seen[g] = true
				if k > 1 then
					yes(g > round.Active[k - 1], "sorted")
				end
			end
			for i = 1, 6 do
				yes(round.Target[i] >= 0 and round.Target[i] <= 3 and round.Start[i] >= 0 and round.Start[i] <= 3, "direction 0..3")
			end
			local ok, wrong = Rules.MirrorCheck(round, round.Start)
			no(ok, "never solved at the start")
			yes(wrong >= math.ceil(#round.Active * act.MinWrongShare - 1e-9), "mostly wrong at the start")
		end
	end
end)

test("mirror: the pond shows grave i at 7 - i with east <-> west flipped; solving the reflection = the solution", function()
	eq(Rules.MirrorOf(1), 6)
	eq(Rules.MirrorOf(2), 5)
	eq(Rules.MirrorOf(3), 4)
	eq(Rules.Flip(0), 0)
	eq(Rules.Flip(1), 3)
	eq(Rules.Flip(2), 2)
	eq(Rules.Flip(3), 1)
	-- facings match CFrame.Angles(0, d * pi / 2, 0) * +Z (the stone's turn)
	for d = 0, 3 do
		local look = (CF.Angles(0, d * math.pi / 2, 0)):VectorToWorldSpace(V3(0, 0, 1))
		near((look - Rules.Facing(d)).Magnitude, 0, 1e-6, "facing " .. d)
	end
	-- a left <-> right mirror: east and west swap, north and south stay
	near(Rules.Facing(Rules.Flip(1)).X, -1)
	near(Rules.Facing(Rules.Flip(0)).Z, 1)
	local act = Rules.Activity(3)
	for s = 1, 50 do
		local rounds = Rules.MirrorRounds(Rules.MirrorSeed(s, 1), act)
		for _, round in ipairs(rounds) do
			local refl = Rules.Reflection(round)
			eq(#refl, #round.Active)
			for _, e in ipairs(refl) do
				eq(e.At, 7 - e.Grave, "reflected place")
			end
			local target = Rules.Solve(refl)
			local current = table.clone(round.Start)
			for g, d in pairs(target) do
				current[g] = d
			end
			local ok, wrong = Rules.MirrorCheck(round, current)
			yes(ok, "the reflection's solution solves the round")
			eq(wrong, 0)
			-- reading the reflection literally (without mirroring) is wrong whenever a target faces east or west
			local literal = table.clone(round.Start)
			local sideways = false
			for _, e in ipairs(refl) do
				literal[e.Grave] = e.Dir
				sideways = sideways or e.Dir == 1 or e.Dir == 3
			end
			if sideways then
				no((Rules.MirrorCheck(round, literal)), "the mirror matters")
			end
			-- turns needed: each TURN is +1 quarter
			local turns = Rules.TurnsNeeded(round, round.Start)
			local cur = table.clone(round.Start)
			for _, g in ipairs(round.Active) do
				while cur[g] ~= round.Target[g] do
					cur[g] = (cur[g] + 1) % 4
					turns -= 1
				end
			end
			eq(turns, 0, "TurnsNeeded counts quarter turns")
		end
	end
end)

test("mine numbers: node HP scales with the party, hazards are fair and stay on the mine floor", function()
	local act = Rules.Activity(4)
	local hp1, unit = Rules.NodeHP(act, 1)
	eq(unit, act.Unit)
	eq(hp1, act.NodeHits * act.Unit, "solo: NodeHits plain Wooden hits")
	local hp6 = Rules.NodeHP(act, 6)
	eq(hp6, math.floor(act.NodeHits * act.Unit * (1 + act.PartyHP * 5) + .5))
	local floor = Layout.Undercrypt.Floor
	local inside = V3((floor.Min.X + floor.Max.X) / 2, Layout.Undercrypt.FloorY + 3, (floor.Min.Z + floor.Max.Z) / 2)
	yes(Rules.OnFloor(inside, Layout, act))
	no(Rules.OnFloor(Layout.Anchor("MineEntrance"), Layout, act), "the entrance above is not the floor")
	for _, def in ipairs({ Rules.RockDef(inside, act), Rules.GasDef(inside, act), Rules.TunnelDef(inside, 1.1, act, Layout) }) do
		local ok, problems = Hazards.Check(def, { Trial = true })
		yes(ok, def.Kind .. " fair: " .. table.concat(problems or {}, "; "))
	end
	eq(Rules.RockDef(inside, act).Shape.Radius, 6)
	eq(Rules.RockDef(inside, act).Telegraph, 1.4)
	eq(Rules.RockDef(inside, act).Damage, 18)
	local gas = Rules.GasDef(inside, act)
	eq(gas.Kind, "Gas", "H10 -30% applies to Kind Gas")
	eq(gas.DPS, 6)
	yes(gas.Linger > 0)
	-- a tunnel through a corner is clipped to the floor box (shrunk by FloorMargin)
	local corner = V3(floor.Min.X + 2, 0, floor.Min.Z + 2)
	for _, ang in ipairs({ 0, .5, 1.2, 2.4 }) do
		local t = Rules.TunnelDef(corner, ang, act, Layout).Shape
		for _, p in ipairs({ t.From, t.To }) do
			yes(p.X >= floor.Min.X + act.FloorMargin - 1e-6 and p.X <= floor.Max.X - act.FloorMargin + 1e-6, "x inside")
			yes(p.Z >= floor.Min.Z + act.FloorMargin - 1e-6 and p.Z <= floor.Max.Z - act.FloorMargin + 1e-6, "z inside")
			near(p.Y, Layout.Undercrypt.FloorY)
		end
		yes((t.To - t.From).Magnitude <= act.Tunnel.Length + 1e-6)
		-- a tunnel line always leaves a safe side: a player 5 studs off the line is outside it
		local mid = (t.From + t.To) / 2 + V3(0, 3, 0)
		local dir = Rules.Flat(t.To - t.From).Unit
		local off = V3(-dir.Z, 0, dir.X) * (act.Tunnel.Width / 2 + 1)
		no(Hazards.Contains(t, mid + off), "a step aside is safe")
	end
end)

test("echo numbers: life (+ H09), alive count with the party, free points far enough away", function()
	local act = Rules.Activity(1)
	eq(Rules.EchoLife(act), 4.5)
	eq(Rules.EchoLife(act, Cfg.Dogs.Defs.HW_BellPup.EchoLifeBonus), 8.5, "H09 Bell Pup: +4 s")
	eq(Rules.EchoAlive(act, 1), act.MaxAlive)
	yes(Rules.EchoAlive(act, 6) > act.MaxAlive, "a party gets more echoes")
	yes(Rules.EchoAlive(act, 40) <= act.MaxAliveCap, "capped")
	local pts = Layout.EchoPoints
	eq(#pts, 16)
	local rand = Rules.Lcg(7)
	for _ = 1, 200 do
		local from = pts[math.floor(rand() * 16) + 1]
		local taken = { [3] = true, [9] = true }
		local i = Rules.PickPoint(pts, taken, from, act.MinJumpDistance, rand)
		yes(i and not taken[i], "a free point")
		yes(Rules.Flat(pts[i] - from).Magnitude >= act.MinJumpDistance, "far enough")
	end
	local all = {}
	for i = 1, 16 do
		all[i] = true
	end
	eq(Rules.PickPoint(pts, all, nil, 0, rand), nil, "nothing free")
end)

---------------------------------------------------------------------------------------------------------------------
-- the activity servers on the real Seals framework
---------------------------------------------------------------------------------------------------------------------
local everyone = {}
L.Stubs.Players.GetPlayers = function()
	return everyone
end
local pos = {}
local signals = {}
local requests = {}
local prompts = {}
local hazards = {}
local cancelled = {}
local progress = {}
local shards = {}
local streaks = {}
local teleports = {}
local abilities = {}
local zones = {}
local roots = {}
local nextUser = 900

local function fakePart()
	local p = { Attrs = {}, Parent = true }
	function p:SetAttribute(k, v)
		self.Attrs[k] = v
	end
	function p:GetAttribute(k)
		return self.Attrs[k]
	end
	return p
end

local function fakePlayer(at)
	nextUser += 1
	local p = { UserId = nextUser, Name = "P" .. nextUser, DisplayName = "Dog" .. nextUser, Parent = true, Character = nil, Attrs = {} }
	function p:GetAttribute(k)
		return self.Attrs[k]
	end
	function p:SetAttribute(k, v)
		self.Attrs[k] = v
	end
	pos[p] = at
	table.insert(everyone, p)
	return p
end

local function gone(...)
	for _, pl in ipairs({ ... }) do
		local i = table.find(everyone, pl)
		if i then
			table.remove(everyone, i)
		end
		pl.Parent = nil
	end
end

local fakeCore = {
	Transact = function() end,
	OnRequest = function(name, fn)
		requests[name] = fn
	end,
	Signal = function(to, kind, data)
		table.insert(signals, { To = to, Kind = kind, Data = data })
	end,
	Root = function(pl)
		local p = pos[pl]
		if not p then
			return nil
		end
		roots[pl] = roots[pl] or {}
		roots[pl].Position = p
		return roots[pl]
	end,
	Near = function(pl, p, r)
		local q = pos[pl]
		return q ~= nil and (q - p).Magnitude <= r
	end,
	Rules = { Check = function(c, m)
		if not c then
			error(m, 0)
		end
	end },
}

-- Strike: targets are plain tables (the kinds' callbacks are driven by the tests the way Strike.Hit would)
local Strike = { Kinds = {}, Targets = {}, NextId = 0 }
function Strike.Register(kind, def)
	def.Kind = kind
	Strike.Kinds[kind] = def
	return def
end
function Strike.Add(t)
	Strike.NextId += 1
	local cf = t.CFrame or CF.new(t.Position)
	local part = fakePart()
	part.CFrame = cf
	for k, v in pairs(t.Attributes or {}) do
		part.Attrs[k] = v
	end
	part.Attrs.Label, part.Attrs.LabelRU, part.Attrs.Ground, part.Attrs.Facing = t.Name, t.NameRU, t.Ground, t.Facing
	local target = { Id = Strike.NextId, Kind = t.Kind, Def = Strike.Kinds[t.Kind], Part = part, HP = t.HP, MaxHP = t.MaxHP, Unit = t.Unit,
		Position = cf.Position, Data = t.Data or {}, Owner = t.Owner, Shared = t.Shared ~= false, Alive = true, Contributors = {}, Panel = t.Panel,
		Size = t.Size }
	Strike.Targets[target.Id] = target
	return target
end
function Strike.Move(target, cf)
	target.Position = cf.Position
	target.Part.CFrame = cf
end
function Strike.Remove(target, reason)
	if target.Removed then
		return
	end
	target.Removed, target.Alive = true, false
	target.Part.Attrs.EndReason = reason
	Strike.Targets[target.Id] = nil
	if target.Def.OnRemove then
		target.Def.OnRemove(target, reason)
	end
end
function Strike.All(kind)
	local out = {}
	for _, t in pairs(Strike.Targets) do
		if t.Kind == kind and t.Alive then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end
-- a judged hit the way Strike.Hit runs it: gates, OnHit, damage, break (OnBreak + Remove)
function Strike.Hit(player, target, quality, power)
	local def = target.Def
	if target.Shared == false and target.Owner ~= nil and target.Owner ~= player then
		return false, "HW:NOT_YOURS"
	end
	local ok, err = def.CanHit(player, target)
	if not ok then
		return false, err
	end
	local hit = { Quality = quality, Power = power or 1, Damage = 10, Player = player }
	if type(def.Damage) == "function" then
		hit.Applied = def.Damage(player, target, hit)
	elseif def.Damage == "Power" then
		hit.Applied = hit.Power * target.Unit
	else
		hit.Applied = hit.Damage
	end
	local extra = def.OnHit and def.OnHit(player, target, hit)
	local applied = math.clamp(hit.Applied or 0, 0, target.HP)
	target.HP -= applied
	local c = target.Contributors[player.UserId] or { Player = player, Damage = 0, Hits = 0 }
	c.Damage += applied
	c.Hits += 1
	target.Contributors[player.UserId] = c
	if target.HP <= 1e-6 then
		target.Alive = false
		if def.OnBreak then
			def.OnBreak(player, target, { Killer = player, Contributors = target.Contributors })
		end
		Strike.Remove(target, "Broke")
		return true, { Broke = true, Extra = extra }
	end
	return true, { Extra = extra }
end

local Chapter2 = {
	Eligible = function()
		return true
	end,
	ViewOf = function()
		local seals = {}
		for i = 1, 7 do
			seals[i] = { Offered = true, Cleared = true }
		end
		return { Seals = seals }
	end,
	PhaseOverride = function()
		return 7
	end,
	AnchorPos = function(name)
		return Layout.Anchor(name)
	end,
	Toast = function() end,
	Progress = function(pl, key, n)
		table.insert(progress, { Player = pl, Key = key, N = n })
	end,
	QueueShards = function(pl, n, source)
		table.insert(shards, { Player = pl, N = n, Source = source })
	end,
	StreakHit = function(pl, perfect)
		table.insert(streaks, { Player = pl, Perfect = perfect })
	end,
	Ability = function(pl, id)
		local a = abilities[pl.UserId]
		return a and a[id] and Cfg.Dogs.Defs[id] or nil
	end,
	GrantSeal = function()
		return true
	end,
	TrialCleared = function() end,
	TutorialEvent = function() end,
	Grant = function() end,
}
local Underyard = {
	InZone = function()
		return true
	end,
	Unlocked = function()
		return true
	end,
	District = function(pl)
		return pos[pl] and Layout.District(pos[pl]) or nil
	end,
	Prompt = function(anchor, props, fn)
		local p = { Anchor = anchor, Props = props, Fn = fn }
		prompts[anchor .. ":" .. (props.Name or "")] = p
		return p
	end,
	Teleport = function(pl, cf)
		table.insert(teleports, { Player = pl, CFrame = cf })
		return true
	end,
}
local EventHP = {
	SetZone = function(id, opts)
		zones[id] = opts
	end,
	Enter = function() end,
	Leave = function() end,
	OnBleedOut = function() end,
	Hazard = function(zone, def)
		table.insert(hazards, { Zone = zone, Def = def, At = L.Time })
		return #hazards
	end,
	HazardWave = function(zone, defs)
		local ids = {}
		for _, d in ipairs(defs) do
			table.insert(hazards, { Zone = zone, Def = d })
			table.insert(ids, #hazards)
		end
		return ids
	end,
	CancelHazards = function(zone, ids)
		table.insert(cancelled, { Zone = zone, Ids = ids })
		return 0
	end,
}
local modules = { Chapter2 = Chapter2, Underyard = Underyard, EventHP = EventHP, Strike = Strike }

local Seals = L.Require("ServerScriptService.Halloween.Seals")
modules.Seals = Seals
Seals.Start(fakeCore, modules)
local Echo = L.Require("ServerScriptService.Halloween.SealEcho")
local Run = L.Require("ServerScriptService.Halloween.SealRun")
local Mirror = L.Require("ServerScriptService.Halloween.SealMirror")
local Mine = L.Require("ServerScriptService.Halloween.SealMine")
local roll = Rules.Lcg(99)
for _, m in ipairs({ Echo, Run, Mirror, Mine }) do
	m.Now = function()
		return L.Time
	end
	if m.Roll then
		m.Roll = roll
	end
end
Mirror.Day = function()
	return 20380
end
Run.Teleport = function(pl, cf)
	table.insert(teleports, { Player = pl, CFrame = cf })
end
Echo.Start(fakeCore, modules)
Run.Start(fakeCore, modules)
Mirror.Start(fakeCore, modules)
Mine.Start(fakeCore, modules)

local function advance(seconds, run, step)
	step = step or .1
	local n = math.floor(seconds / step + .5)
	for _ = 1, n do
		L.Time += step
		if run and run.State == "Running" then
			run.Def.OnTick(run, step)
		end
	end
end

local function signalsOf(kind, sub)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == kind and (sub == nil or (type(s.Data) == "table" and s.Data.Kind == sub)) then
			table.insert(out, s)
		end
	end
	return out
end

local function alive(kind, run)
	local out = {}
	for _, t in ipairs(Strike.All(kind)) do
		if not run or t.Data.Run == run then
			table.insert(out, t)
		end
	end
	return out
end

test("registration: Strike kinds, seal defs, start anchors, the Event HP zones, the mirror prompts", function()
	local echo = Strike.Kinds.UyEcho
	yes(echo, "UyEcho kind")
	eq(echo.Verb, "DIG")
	eq(echo.Perfect, false, "no Chapter I candy on Underyard targets")
	local ore = Strike.Kinds.UyHollowOre
	yes(ore, "UyHollowOre kind")
	eq(ore.Damage, "Power", "tier-normalised HP")
	eq(ore.EventMult, "Apply", "WEAKENED miners deal less")
	eq(ore.Perfect, false)
	eq(Seals.Def(1).Id, "EchoDig")
	eq(Seals.Def(2).Id, "FuneralRun")
	eq(Seals.Def(2).Combat, true, "pendulums hit Event HP")
	eq(Seals.Def(2).Exclusive, false, "parallel runs share one pendulum schedule")
	eq(Seals.Def(2).StartAnchor, "RunStart")
	eq(Seals.Def(3).StartAnchor, "PondConsult")
	eq(Seals.Def(3).WinAtGoal, true)
	eq(Seals.Def(4).StartAnchor, "MineEntrance")
	eq(Seals.Def(4).Combat, true)
	yes(zones["Trial:FuneralRun"] and zones["Trial:HollowMine"], "zones named for the HP bar")
	for g = 1, 6 do
		local p = prompts["MirrorGrave_" .. g .. ":UyMirrorTurn"]
		yes(p, "TURN prompt on grave " .. g)
		eq(p.Props.Attributes.UyTrialOnly, "MirrorGraves")
		yes(p.Props.ActionTextRU, "Russian action text")
	end
	local consult = prompts["PondConsult:UyMirrorConsult"]
	yes(consult, "CONSULT THE POND prompt")
	-- TURN / CONSULT never compete: different keys (keyboard and gamepad), tight ranges, spots apart (the geometry of
	-- the built marsh is checked in tests/seals_1_4_client.luau)
	local turn1 = prompts["MirrorGrave_1:UyMirrorTurn"]
	yes(turn1.Props.KeyboardKeyCode ~= consult.Props.KeyboardKeyCode, "different keyboard keys")
	yes(turn1.GamepadKeyCode ~= nil and turn1.GamepadKeyCode ~= consult.GamepadKeyCode, "different gamepad buttons")
	local act3 = Rules.Activity(3)
	eq(turn1.Props.MaxActivationDistance, act3.TurnPromptRange)
	eq(consult.Props.MaxActivationDistance, act3.ConsultPromptRange)
	local pond = Layout.Anchor("MirrorPond")
	for g = 1, 6 do
		local spot = Mirror.TurnSpot(g)
		local stone = Layout.Anchor("MirrorGrave_" .. g)
		near(Rules.Flat(spot - pond).Magnitude - Rules.Flat(stone - pond).Magnitude, act3.TurnOffset, 1e-3, "TURN on the outer side of grave " .. g)
	end
	local gap = (Mirror.TurnSpot(1) - Mirror.ConsultSpot()).Magnitude
	yes(gap > act3.TurnPromptRange and gap > act3.ConsultPromptRange, "grave 1's TURN and CONSULT spots " .. gap .. " studs apart")
	yes(prompts["RunStart:UyTrialPrompt"], "BEGIN TRIAL at the run start (framework)")
	yes(prompts["MineEntrance:UyTrialPrompt"], "BEGIN TRIAL at the mine entrance (framework)")
end)

test("ECHO DIG: countdown, rises, digs, Perfect share, streaks, contracts, shards, respawn", function()
	local leader = fakePlayer(Layout.Anchor("SealAltar_1"))
	local ok, run = Seals.Start(leader, 1)
	yes(ok, tostring(run))
	eq(run.Public.GoAt, run.StartedAt + SC.Countdown, "GO after the countdown")
	near(run.EndsAt - run.Public.GoAt, Cfg.Seals[1].Trial.TimeLimit, 1e-6, "90 s from GO")
	advance(1, run)
	eq(#alive("UyEcho", run), 0, "nothing before GO")
	advance(2.5, run)
	yes(#alive("UyEcho", run) >= 1, "first echo rose at GO")
	advance(1.5, run)
	local echoes = alive("UyEcho", run)
	eq(#echoes, Rules.Activity(1).MaxAlive, "MaxAlive echoes")
	local seen = {}
	for _, t in ipairs(echoes) do
		local i = t.Data.Index
		no(seen[i], "one echo per point")
		seen[i] = true
		eq(t.Part.Attrs.UyRun, run.Id)
		eq(t.Part.Attrs.UyMembers, "," .. leader.UserId .. ",", "only the members get the prompt")
		eq(t.Shared, true, "echoes are the run's (members only: CanHit + UyMembers), never one owner's")
		eq(t.Panel, false, "no strike panel (the trial HUD shows the run)")
		yes(t.Part.Attrs.ExpireAt > L.Time, "life")
	end
	-- a stranger cannot dig them
	local stranger = fakePlayer(Layout.Anchor("SealAltar_1"))
	local okHit, err = Strike.Hit(stranger, echoes[1], 2)
	no(okHit)
	eq(err, "HW:NOT_YOURS")
	-- 18 digs, 11 Perfect: Gold (>= 60%)
	table.clear(progress)
	table.clear(shards)
	table.clear(streaks)
	local digs, perfects = 0, 0
	while digs < 18 do
		local list = alive("UyEcho", run)
		if #list == 0 then
			advance(.3, run)
		else
			local perfect = perfects < 11
			local okDig = Strike.Hit(leader, list[1], perfect and 2 or 1)
			yes(okDig, "dig")
			digs += 1
			perfects += perfect and 1 or 0
			eq(list[1].Removed, true, "one hit digs it")
		end
	end
	eq(run.Total, 18)
	eq(run.Data.Hits, 18)
	eq(run.Data.Perfects, 11)
	eq(run.Public.Dug, 18)
	eq(#streaks, 18, "every dig is a judged streak hit")
	local echoN, shardN = 0, 0
	for _, p in ipairs(progress) do
		if p.Key == "Echo" then
			echoN += p.N
		end
	end
	for _, s in ipairs(shards) do
		eq(s.Source, "Echo")
		shardN += s.N
	end
	eq(echoN, 18, "contract / stat progress per dig")
	eq(shardN, 18 * Cfg.Seals[1].Activity.ObjectiveShards, "objective shards per dig")
	yes(Seals.DefaultGold(run, leader), "18 with 61% Perfect = Gold")
	run.Data.Perfects = 10
	no(Seals.DefaultGold(run, leader), "55% Perfect is not Gold")
	run.Data.Perfects = 11
	-- respawns keep MaxAlive up
	advance(2, run)
	eq(#alive("UyEcho", run), Rules.Activity(1).MaxAlive, "respawned")
	-- the run ends: every echo goes
	Seals.Fail(run, "Test")
	eq(#alive("UyEcho", run), 0, "removed at the end")
	gone(leader, stranger)
end)

test("ECHO DIG: telegraphed jumps to a free point far away; H09 Bell Pup: longer life and the next point shown", function()
	local leader = fakePlayer(Layout.Anchor("SealAltar_1"))
	local ok, run = Seals.Start(leader, 1)
	yes(ok, tostring(run))
	advance(SC.Countdown + .2, run)
	local t = alive("UyEcho", run)[1]
	yes(t, "an echo")
	local from = t.Position
	local expire = t.Part.Attrs.ExpireAt
	local act = Rules.Activity(1)
	advance(expire - act.Trail - L.Time + .05, run)
	local jumpTo = t.Part.Attrs.JumpTo
	yes(jumpTo, "the jump is telegraphed")
	near(t.Part.Attrs.JumpAt, expire, 1e-6, "lands at the end of its life")
	yes(Rules.Flat(jumpTo - Rules.Flat(from) - V3(0, 0, 0)).Magnitude >= 0, "a point")
	yes(Rules.Flat(jumpTo - from).Magnitude >= act.MinJumpDistance - 1e-6, "far enough away")
	advance(act.Trail + .1, run)
	yes(t.Alive, "the same echo")
	near(Rules.Flat(t.Position - jumpTo).Magnitude, 0, 1e-6, "moved there")
	eq(t.Part.Attrs.JumpTo, nil, "trail cleared")
	near(t.Part.Attrs.ExpireAt - t.Part.Attrs.LifeFrom, act.Life, 1e-6, "a fresh life")
	-- never two echoes on one point after many jumps
	advance(20, run)
	local seen = {}
	for _, e in ipairs(alive("UyEcho")) do
		no(seen[e.Data.Index], "one echo per point")
		seen[e.Data.Index] = true
	end
	Seals.Fail(run, "Test")
	-- H09
	local pup = fakePlayer(Layout.Anchor("SealAltar_1"))
	abilities[pup.UserId] = { HW_BellPup = true }
	ok, run = Seals.Start(pup, 1)
	yes(ok, tostring(run))
	eq(run.Public.Pup, true)
	advance(SC.Countdown + .2, run)
	local e = alive("UyEcho", run)[1]
	near(e.Part.Attrs.Life, 8.5, 1e-6, "ECHO EAR: +4 s")
	yes(e.Part.Attrs.NextPos, "ECHO EAR: the next jump target is known (pulses)")
	local nextPos = e.Part.Attrs.NextPos
	advance(e.Part.Attrs.ExpireAt - L.Time + .1, run)
	near(Rules.Flat(e.Position - nextPos).Magnitude, 0, 1e-6, "it jumped where the pup said")
	Seals.Fail(run, "Test")
	gone(leader, pup)
end)

test("ECHO DIG: a party shares the echoes (more alive, everyone may dig, before GO nobody)", function()
	local a = fakePlayer(Layout.Anchor("SealAltar_1"))
	local b = fakePlayer(Layout.Anchor("SealAltar_1") + V3(4, 0, 0))
	local c = fakePlayer(Layout.Anchor("SealAltar_1") + V3(0, 0, 5))
	local ok, run = Seals.Start(a, 1)
	yes(ok, tostring(run))
	eq(#run.Players, 3, "party joined")
	advance(.5, run)
	advance(SC.Countdown + 2, run)
	local list = alive("UyEcho", run)
	eq(#list, Rules.EchoAlive(Rules.Activity(1), 3))
	eq(list[1].Shared, true, "party echoes are shared")
	yes(Strike.Hit(b, list[1], 1), "a member digs")
	eq(run.Score[b.UserId], 1)
	Seals.Fail(run, "Test")
	gone(a, b, c)
end)

local function runTo(run, player, pts, speed, t0)
	for _, s in ipairs(samples(pts, speed, t0)) do
		L.Time = s.T
		pos[player] = s.Pos
		if run.State ~= "Running" then
			break
		end
		run.Def.OnTick(run, .25)
		run.Def.OnSample(run, player, s.Pos, s.T)
	end
end

test("FUNERAL RUN: rings in order, splits, finish, Gold <= 55 s, pendulum hazards on the server clock", function()
	local start = Layout.Anchor("RunStart")
	local runner = fakePlayer(start)
	table.clear(hazards)
	local ok, run = Seals.Start(runner, 2)
	yes(ok, tostring(run))
	eq(run.Public.Checkpoints, 10)
	yes(run.Public.Carousel and run.Public.Carousel > 0, "carousel leg published")
	local goAt = run.Public.GoAt
	-- pendulum passes are scheduled ahead of their telegraph, each once
	for _ = 1, 20 do
		L.Time += .1
		run.Def.OnTick(run, .1)
	end
	yes(#hazards > 0, "pendulum hazards")
	-- a pass that really hits throws the runner along the coffin's swing and allows the flight in the leg check
	local h1 = hazards[1].Def
	yes(type(h1.OnHit) == "function", "OnHit")
	roots[runner] = nil
	h1.OnHit(runner, 12)
	local thrown = roots[runner] and roots[runner].AssemblyLinearVelocity
	yes(thrown, "knock-back applied")
	near((thrown - h1.KnockVelocity).Magnitude, 0, 1e-9, "the swing's knock")
	local spec1 = Run.Pendulums()[h1.Pendulum]
	near(math.abs(Rules.Flat(thrown):Dot(Rules.Flat(spec1.Hinge.LookVector).Unit)), 0, 1e-6, "never along the lane")
	near(run.Data.Run.Runners[runner.UserId].KnockUntil, h1.ImpactAt + Rules.Activity(2).KnockGrace, 1e-9, "knock allowance")
	local keys = {}
	for _, h in ipairs(hazards) do
		eq(h.Zone, "Trial:FuneralRun")
		eq(h.Def.Kind, "Pendulum")
		local k = h.Def.Pendulum .. ":" .. h.Def.ImpactAt
		no(keys[k], "one hazard per pass")
		keys[k] = true
		yes(h.Def.ImpactAt - h.At >= h.Def.Telegraph, "scheduled before its telegraph has to show")
		local spec = Run.Pendulums()[h.Def.Pendulum]
		near(Rules.SwingAngle(h.Def.ImpactAt, spec.Amp, spec.Period, spec.Phase), 0, 1e-6, "impact = the coffin's pass (same formula)")
	end
	-- an honest run at 16 studs/s (walk speed) finishes inside the time limit
	L.Time = goAt
	runTo(run, runner, course(start), 30, goAt)
	eq(run.State, "Won", "finished = won")
	local fin = run.Public.Finish[tostring(runner.UserId)]
	yes(fin and fin > 0, "finish time")
	local won = signalsOf("C2Trial", "Won")
	local last = won[#won].Data
	eq(last.Gold[tostring(runner.UserId)], fin <= 55, "Gold = finish <= 55 s")
	eq(#signalsOf("C2Trial", "Checkpoint") >= 10, true, "a split per ring")
	gone(runner)
end)

test("FUNERAL RUN: a teleport puts the runner back on its last ring; too many violations end the run", function()
	local start = Layout.Anchor("RunStart")
	local runner = fakePlayer(start)
	local ok, run = Seals.Start(runner, 2)
	yes(ok, tostring(run))
	local goAt = run.Public.GoAt
	local cps = Run.Checkpoints()
	L.Time = goAt
	runTo(run, runner, { start, cps[1], cps[2] }, 25, goAt)
	eq(run.Public.Progress[tostring(runner.UserId)], 2, "two rings")
	table.clear(teleports)
	L.Time += .25
	pos[runner] = cps[6]
	run.Def.OnSample(run, runner, cps[6], L.Time)
	eq(#teleports, 1, "rewound")
	near(Rules.Flat(teleports[1].CFrame.Position - cps[2]).Magnitude, 0, 1e-6, "back on ring 2")
	local rw = signalsOf("C2Trial", "Rewind")
	eq(rw[#rw].Data.Reason, "Jump")
	eq(run.Public.Progress[tostring(runner.UserId)], 2, "nothing credited")
	-- keep cheating: out of the run
	for _ = 1, Rules.Activity(2).MaxViolations + 1 do
		if run.State ~= "Running" then
			break
		end
		L.Time += .25
		pos[runner] = cps[2]
		run.Def.OnSample(run, runner, cps[2], L.Time)
		L.Time += .25
		pos[runner] = cps[9]
		run.Def.OnSample(run, runner, cps[9], L.Time)
	end
	eq(run.State, "Failed", "out of the run")
	eq(run.Left[runner.UserId], "Invalid")
	gone(runner)
end)

test("FUNERAL RUN: party - finishers win when the clock runs out, the others are out (Time); pendulum telegraphs cancel", function()
	local start = Layout.Anchor("RunStart")
	local a = fakePlayer(start)
	local b = fakePlayer(start + V3(3, 0, 0))
	table.clear(cancelled)
	local ok, run = Seals.Start(a, 2)
	yes(ok, tostring(run))
	eq(#run.Players, 2)
	runTo(run, a, course(start), 30, run.Public.GoAt)
	eq(run.State, "Running", "b still running")
	L.Time = run.EndsAt + .1
	run.Def.OnTimeUp(run)
	eq(run.State, "Won", "the finisher wins")
	eq(run.Left[b.UserId], "Time", "the other is out")
	yes(#cancelled > 0, "no runs left: future pendulum telegraphs cancelled")
	gone(a, b)
end)

test("MIRROR GRAVES: turns, a wrong consult costs 15 s and Gold, three rounds solve the seal (leader's daily seed)", function()
	local pondStand = Layout.Anchor("PondConsult")
	local p = fakePlayer(pondStand)
	local ok, run = Seals.Start(p, 3)
	yes(ok, tostring(run))
	local st = run.Data.Mirror
	eq(st.Seed, Rules.MirrorSeed(p.UserId, 20380), "leader's daily seed")
	eq(run.Public.Round, 1)
	eq(#run.Public.Active, 4)
	eq(#run.Public.Reflection, 4)
	-- before GO the stones are still
	local okT, err = Mirror.Turn(p, run.Public.Active[1])
	no(okT)
	eq(err, "Wait for the graves to settle")
	L.Time = run.Public.GoAt + .1
	-- a sleeping grave refuses, a far grave refuses
	local sleeping = nil
	for g = 1, 6 do
		if not table.find(run.Public.Active, g) then
			sleeping = g
		end
	end
	pos[p] = Layout.Anchor("MirrorGrave_" .. sleeping)
	okT, err = Mirror.Turn(p, sleeping)
	no(okT)
	eq(err, "This grave sleeps this round")
	-- the active grave farthest from the basin (grave 1's island touches it)
	local g1, far = nil, -1
	for _, g in ipairs(run.Public.Active) do
		local d = (Layout.Anchor("MirrorGrave_" .. g) - pondStand).Magnitude
		if d > far then
			g1, far = g, d
		end
	end
	pos[p] = pondStand
	okT, err = Mirror.Turn(p, g1)
	no(okT)
	eq(err, "Move closer to the grave")
	-- a wrong consult: -15 s, a mistake
	local ends = run.EndsAt
	local okC, res = Mirror.Consult(p)
	yes(okC)
	eq(res.Cleared, false)
	yes(res.Wrong >= 1)
	near(run.EndsAt, ends - Cfg.Seals[3].Activity.WrongPenalty, 1e-6, "-15 s")
	eq(run.Data.Mistakes, 1)
	-- solve every round from what the pond shows (mirrored back)
	local function solveRound()
		local target = Rules.Solve(run.Public.Reflection)
		for g, d in pairs(target) do
			pos[p] = Layout.Anchor("MirrorGrave_" .. g)
			local guard = 0
			while run.Data.Mirror.Current[g] ~= d do
				L.Time += Rules.Activity(3).TurnCooldown + .01
				local okTurn, e2 = Mirror.Turn(p, g)
				yes(okTurn, tostring(e2))
				guard += 1
				yes(guard <= 4, "at most 3 quarter turns")
			end
		end
		pos[p] = pondStand
		L.Time += Rules.Activity(3).ConsultCooldown + .01
		return Mirror.Consult(p)
	end
	for r = 1, 3 do
		local okR, resR = solveRound()
		yes(okR and resR.Cleared, "round " .. r)
		if r < 3 then
			eq(run.Public.Round, r + 1)
			eq(#run.Public.Active, Cfg.Seals[3].Activity.Rounds[r + 1])
			L.Time += Rules.Activity(3).RoundPause + .05
		end
	end
	eq(run.State, "Won", "three rounds = the seal")
	local won = signalsOf("C2Trial", "Won")
	eq(won[#won].Data.Gold[tostring(p.UserId)], false, "a wrong consult loses Gold")
	gone(p)
	-- a clean solve is Gold
	local q = fakePlayer(pondStand)
	ok, run = Seals.Start(q, 3)
	yes(ok, tostring(run))
	L.Time = run.Public.GoAt + .1
	p = q
	for _ = 1, 3 do
		local okR = solveRound()
		yes(okR)
		L.Time += Rules.Activity(3).RoundPause + .05
	end
	eq(run.State, "Won")
	won = signalsOf("C2Trial", "Won")
	eq(won[#won].Data.Gold[tostring(q.UserId)], true, "no wrong consults = Gold")
	gone(q)
end)

test("MIRROR GRAVES: not in the trial -> the prompts answer politely; requests route through C2Trial", function()
	local p = fakePlayer(Layout.Anchor("PondConsult"))
	local okT, err = Mirror.Turn(p, 1)
	no(okT)
	eq(err, "Begin the trial at the pond first")
	table.clear(signals)
	prompts["MirrorGrave_1:UyMirrorTurn"].Fn(p)
	local msg = signalsOf("C2TrialMsg")
	eq(#msg, 1)
	eq(msg[1].Data.Text, "Begin the trial at the pond first")
	local ok, run = Seals.Start(p, 3)
	yes(ok, tostring(run))
	L.Time = run.Public.GoAt + .1
	local okR, res = requests.C2Trial(p, { Action = "Consult" })
	yes(okR)
	eq(res.Cleared, false)
	Seals.Fail(run, "Test")
	gone(p)
end)

test("HOLLOW MINE: nodes with party HP, cores with progress + shards, Gold 20 without downs ends the run", function()
	local entrance = Layout.Anchor("MineEntrance")
	local a = fakePlayer(entrance)
	local ok, run = Seals.Start(a, 4)
	yes(ok, tostring(run))
	near(run.EndsAt - run.Public.GoAt, Cfg.Seals[4].Trial.TimeLimit, 1e-6, "4 min from GO")
	advance(SC.Countdown + 1.2, run)
	local nodes = alive("UyHollowOre", run)
	eq(#nodes, 12, "every mine node")
	local hp = Rules.NodeHP(Rules.Activity(4), 1)
	eq(nodes[1].HP, hp)
	eq(nodes[1].Panel, false)
	eq(nodes[1].Part.Attrs.UyMembers, "," .. a.UserId .. ",", "only the members get the prompt")
	table.clear(progress)
	table.clear(shards)
	-- break 20 cores with plain hits of power 1
	local cores = 0
	while run.State == "Running" and cores < 20 do
		local list = alive("UyHollowOre", run)
		if #list == 0 then
			advance(1, run)
		else
			local t = list[1]
			while t.Alive do
				Strike.Hit(a, t, 1, 1)
			end
			cores += 1
		end
	end
	eq(cores, 20)
	eq(run.State, "Won", "the Gold total collapses the mine early")
	local won = signalsOf("C2Trial", "Won")
	eq(won[#won].Data.Gold[tostring(a.UserId)], true, "20 cores, never downed = Gold")
	local ore, sh = 0, 0
	for _, pr in ipairs(progress) do
		if pr.Key == "Ore" then
			ore += pr.N
		end
	end
	for _, s in ipairs(shards) do
		eq(s.Source, "Ore")
		sh += s.N
	end
	eq(ore, 20)
	eq(sh, 20 * Cfg.Seals[4].Activity.ObjectiveShards)
	eq(#alive("UyHollowOre", run), 0, "nodes removed at the end")
	gone(a)
end)

test("HOLLOW MINE: hazards only aim at miners on the floor, are fair through Hazards.Check, a downed miner is not Gold", function()
	local entrance = Layout.Anchor("MineEntrance")
	local a = fakePlayer(entrance)
	local b = fakePlayer(entrance + V3(2, 0, 2))
	local ok, run = Seals.Start(a, 4)
	yes(ok, tostring(run))
	eq(#run.Players, 2)
	eq(alive("UyHollowOre", run)[1], nil, "no nodes before GO")
	advance(SC.Countdown + 1, run)
	eq(alive("UyHollowOre", run)[1].HP, Rules.NodeHP(Rules.Activity(4), 2), "party HP")
	table.clear(hazards)
	advance(20, run)
	eq(#hazards, 0, "nobody on the floor: no hazards")
	local floorY = Layout.Undercrypt.FloorY
	pos[a] = V3(150, floorY + 3, 2560)
	pos[b] = V3(170, floorY + 3, 2580)
	advance(60, run)
	yes(#hazards > 5, "hazards while miners work the floor")
	local kinds = {}
	for _, h in ipairs(hazards) do
		eq(h.Zone, "Trial:HollowMine")
		kinds[h.Def.Kind] = true
		local okFair, problems = Hazards.Check(h.Def, { Trial = true })
		yes(okFair, h.Def.Kind .. ": " .. table.concat(problems or {}, "; "))
		local c = Hazards.Center(h.Def.Shape)
		yes(Rules.OnFloor(V3(c.X, floorY + 1, c.Z), Layout, Rules.Activity(4)), h.Def.Kind .. " on the floor")
		if h.Def.Kind == "Rock" then
			local da = Rules.Flat(c - pos[a]).Magnitude
			local db = Rules.Flat(c - pos[b]).Magnitude
			yes(math.min(da, db) <= Rules.Activity(4).RockSpread + 1e-6, "a rock lands next to a miner")
		end
	end
	yes(kinds.Rock and kinds.Gas and kinds.Collapse, "falling rocks, gas vents and collapses")
	-- b goes down: b is never Gold, a can still be
	run.Downed[b.UserId] = true
	run.Total = 20
	no(Seals.DefaultGold(run, b), "downed = no Gold")
	yes(Seals.DefaultGold(run, a), "a was never downed")
	Seals.Fail(run, "Test")
	yes(#cancelled > 0, "hazards cancelled at the end")
	gone(a, b)
end)

test("localization: every server message of the four activities has Russian, no key repeats another dictionary", function()
	local fs = require("@lune/fs")
	local own = L.Require("ReplicatedStorage.Localization.Seals1")
	local function cyrillic(s)
		return type(s) == "string" and string.find(s, "[\208\209]") ~= nil
	end
	local missing = {}
	for _, file in ipairs({ "SealEcho", "SealRun", "SealMirror", "SealMine" }) do
		local src = fs.readFile("src/ServerScriptService/Halloween/" .. file .. ".luau")
		for text in string.gmatch(src, 'return false, "([^"]+)"') do
			if string.sub(text, 1, 3) ~= "HW:" and not own.Exact[text] then
				table.insert(missing, text)
			end
		end
	end
	eq(#missing, 0, "untranslated: " .. table.concat(missing, " | "))
	eq(own.Translate("MIRROR GRAVE 4", "ru"), "ЗЕРКАЛЬНАЯ МОГИЛА 4")
	local base = {}
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"') do
		base[en] = true
	end
	local others = {}
	for _, f in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local name = f:gsub("%.luau$", "")
		if name ~= "Seals1" then
			local okLoad, dict = pcall(L.Require, "ReplicatedStorage.Localization." .. name)
			if okLoad and type(dict) == "table" then
				others[name] = dict
			end
		end
	end
	for en, ru in pairs(own.Exact) do
		no(base[en], "repeats a base entry: " .. en)
		for name, dict in pairs(others) do
			no(dict.Exact and dict.Exact[en], "repeats Localization." .. name .. ": " .. en)
		end
		yes(cyrillic(ru), "Russian for " .. en)
	end
end)

print(string.format("seals_1_4 (server): %d passed, %d failed", passed, failed))
return { Passed = passed, Failed = failed }
