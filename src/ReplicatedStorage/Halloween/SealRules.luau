-- Pure rules of BELL SEALS I-IV (ReplicatedStorage.Halloween.SealRules, WP-I; docs/halloween2/DESIGN.md §8.4.1-4, §24.2).
-- No services, no instances: the activity servers (ServerScriptService.Halloween.SealEcho / SealRun / SealMirror /
-- SealMine), the client presenters (HalloweenClient.Trials.*) and tests/seals_1_4.luau run exactly the same maths.
--   Activity(i, c2?) -> merged numbers (SealConfig[i] overlaid by Chapter2Config.Seals[i].Activity)
--   ECHO      EchoLife(act, bonus?) · EchoAlive(act, party) · PickPoint(points, taken, from?, minDist, rand) -> index?
--   RUN       SwingAngle(t, amp, period, phase) · SwingRate(...) · PendulumSpec(i, hinge, attrs, act) · FallbackHinge(...)
--             CoffinCFrame(spec, t) · Crossings(spec, t0, t1) -> {{T, K, Dir}} · PendulumHazard(spec, cross, act) -> def
--             MinLegTime(dist, act) · RunSpeed(act) · SegmentClosest(p0, p1, c) · CrossesCheckpoint(p0, p1, c, r, band)
--             NewRunner(start, goAt) · Knocked(st, untilT, act) · RunStep(st, pos, t, cps, act) -> events
--             Rewound(st, t, at) · CarouselLeg(cps, c, r) -> i?
--   MIRROR    Flip(d) · MirrorOf(i) · Facing(d) -> Vector3 · MirrorSeed(userId, day) · MirrorRounds(seed, act) -> rounds
--             Reflection(round) -> {{Grave, At, Dir}} · Solve(reflection) -> target · MirrorCheck(round, current) -> ok, wrong
--             TurnsNeeded(round, current)
--   MINE      NodeHP(act, party) -> hp, unit · OnFloor(pos, layout, act) · ClampFloor(p, layout, margin) · Every(range, roll)
--             RockDef(pos, act) · GasDef(pos, act) · TunnelDef(centre, angle, act, layout) -> hazard defs (Hazards shapes)
-- Orientation of a mirror headstone: d in 0..3 = the rune faces CFrame.Angles(0, d * pi / 2, 0) * +Z (0 = +Z south,
-- 1 = +X east, 2 = -Z north, 3 = -X west); the pond mirrors left <-> right: east <-> west (Flip), grave i <-> grave 7 - i.
local root = script.Parent
local Hazards = require(root:WaitForChild("Hazards"))
local SC = require(root:WaitForChild("SealConfig"))
local C2Cfg = require(root:WaitForChild("Chapter2Config"))

local R = {}
R.Config = SC

local V3 = Vector3.new
local TAU = math.pi * 2
R.TAU = TAU

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end
R.Flat = flat

local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

-- Park-Miller (the same generator as Chapter2Rules.Lcg: identical on every host)
local function lcg(seed: number): () -> number
	local state = math.floor(num(seed, 1)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
R.Lcg = lcg

-- the activity numbers of seal i: SealConfig[i] overlaid by Chapter2Config.Seals[i].Activity (that table wins)
function R.Activity(i: number, c2: any?): { [string]: any }
	local cfg = c2 or C2Cfg
	local out: { [string]: any } = {}
	for k, v in pairs(SC[i] or {}) do
		out[k] = v
	end
	local seal = cfg.Seals and cfg.Seals[i]
	for k, v in pairs(seal and seal.Activity or {}) do
		out[k] = v
	end
	if out.Countdown == nil then
		out.Countdown = SC.Countdown
	end
	return out
end

-- the run's members as Strike target attribute UyMembers (",uid,uid,": HalloweenStrike shows the target's prompt only to
-- them, the presenters draw only their own run's targets)
function R.Members(players: { any }): string
	local out = { "" }
	for _, pl in ipairs(players or {}) do
		local uid = type(pl) == "number" and pl or nil
		if uid == nil then
			local ok, id = pcall(function()
				return (pl :: any).UserId
			end)
			uid = ok and tonumber(id) or nil
		end
		if uid then
			table.insert(out, tostring(uid))
		end
	end
	table.insert(out, "")
	return #out > 2 and table.concat(out, ",") or ""
end

-- is userId listed in a UyMembers string?
function R.IsMember(members: any, userId: number): boolean
	return type(members) == "string" and string.find(members, "," .. tostring(userId) .. ",", 1, true) ~= nil
end

-- a number in [range[1], range[2]] for a roll in [0, 1)
function R.Every(range: any, roll: number): number
	if type(range) ~= "table" then
		return num(range, 0)
	end
	local a, b = num(range[1], 0), num(range[2] or range[1], 0)
	return a + (b - a) * math.clamp(roll, 0, 1)
end

---------------------------------------------------------------------------------------------------------------------
-- I · ECHO DIG
---------------------------------------------------------------------------------------------------------------------
-- seconds an echo stays on one point before it jumps (H09 Bell Pup: + EchoLifeBonus)
function R.EchoLife(act: any, bonus: number?): number
	return num(act.Life, 4.5) + math.max(0, bonus or 0)
end

-- echoes alive at once for a party of `party`
function R.EchoAlive(act: any, party: number): number
	local base = num(act.MaxAlive, 3)
	local extra = math.floor(num(act.PartyAlive, 0) * math.max(0, (party or 1) - 1))
	return math.clamp(base + extra, 1, math.max(base, num(act.MaxAliveCap, base)))
end

-- a free point index (taken[i] = true for occupied ones) at least minDist (flat) away from `from`; the distance rule
-- is relaxed when nothing qualifies; nil when every point is taken
function R.PickPoint(points: { Vector3 }, taken: { [number]: any }, from: Vector3?, minDist: number, rand: () -> number): number?
	local function list(useDist: boolean): { number }
		local out = {}
		for i, p in ipairs(points) do
			if not taken[i] and (not useDist or from == nil or flat(p - from).Magnitude >= minDist) then
				table.insert(out, i)
			end
		end
		return out
	end
	local c = list(true)
	if #c == 0 then
		c = list(false)
	end
	if #c == 0 then
		return nil
	end
	return c[math.clamp(math.floor(rand() * #c) + 1, 1, #c)]
end

---------------------------------------------------------------------------------------------------------------------
-- II · FUNERAL RUN — pendulums (§24.2) and the checkpoint / leg-time validation
---------------------------------------------------------------------------------------------------------------------
-- angle = Amp * sin(2 pi * (serverTime mod Period) / Period + Phase): the formula and time base of HalloweenClient
-- UnderyardFX (UySwingAmp / UySwingPeriod / UySwingPhase on RunPendulum_i, applied as Hinge * Angles(0, 0, angle))
function R.SwingAngle(t: number, amp: number, period: number, phase: number?): number
	local p = num(period, 0) > 0 and period or 1
	return num(amp, 0) * math.sin(TAU * (t % p) / p + num(phase, 0))
end

function R.SwingRate(t: number, amp: number, period: number, phase: number?): number
	local p = num(period, 0) > 0 and period or 1
	return num(amp, 0) * TAU / p * math.cos(TAU * (t % p) / p + num(phase, 0))
end

-- spec of pendulum `index` from its hinge CFrame (pivot; LookVector = lane direction) and the model's attributes
function R.PendulumSpec(index: number, hinge: CFrame, attrs: { [string]: any }?, act: any): { [string]: any }
	local a: { [string]: any } = attrs or {}
	return {
		Index = index,
		Hinge = hinge,
		Amp = num(a.UySwingAmp, num(act.PendulumAmp, 1)),
		Period = math.max(.2, num(a.UySwingPeriod, num(act.PendulumPeriod, 3.2))),
		Phase = num(a.UySwingPhase, (index - 1) * num(act.PendulumPhaseStep, 0)),
		Arm = num(act.PendulumArm, 12),
		GroundY = hinge.Position.Y - num(act.PendulumPivotY, 17),
	}
end

-- the hinge when RunPendulum_i is not in the place: above the layout point, facing along the nearest leg of the course
function R.FallbackHinge(pos: Vector3, path: { Vector3 }, act: any): CFrame
	local best, bd = nil, math.huge
	for k = 1, #path - 1 do
		local a, b = flat(path[k]), flat(path[k + 1])
		local ab = b - a
		local len2 = ab:Dot(ab)
		if len2 > 1e-6 then
			local t = math.clamp((flat(pos) - a):Dot(ab) / len2, 0, 1)
			local d = (a + ab * t - flat(pos)).Magnitude
			if d < bd then
				bd, best = d, ab.Unit
			end
		end
	end
	local dir = best or V3(0, 0, -1)
	return CFrame.new(pos.X, pos.Y + num(act.PendulumPivotY, 17), pos.Z) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0)
end

-- the swinging coffin's centre at server time t
function R.CoffinCFrame(spec: any, t: number): CFrame
	local a = R.SwingAngle(t, spec.Amp, spec.Period, spec.Phase)
	return spec.Hinge * CFrame.Angles(0, 0, a) * CFrame.new(0, -spec.Arm, 0)
end

-- the passes of the coffin through the lane centre (angle = 0) in [t0, t1): {T, K (pass number), Dir (+1 = moving
-- towards the hinge's +X / RightVector, -1 = towards -X)}
function R.Crossings(spec: any, t0: number, t1: number): { any }
	local P = spec.Period
	local half = P / 2
	local off = -spec.Phase / TAU * P
	local out = {}
	local k = math.ceil((t0 - off) / half - 1e-9)
	local sign = num(spec.Amp, 1) >= 0 and 1 or -1
	for _ = 1, 64 do
		local t = off + k * half
		if t >= t1 then
			break
		end
		if t >= t0 then
			table.insert(out, { T = t, K = k, Dir = (k % 2 == 0 and 1 or -1) * sign })
		end
		k += 1
	end
	return out
end

-- the knock-back velocity of a pass: ALONG the swing (the hinge's RightVector x the pass direction), never along the
-- lane, plus the upward part
function R.SwingKnock(spec: any, dir: number, act: any): Vector3
	local right = flat(spec.Hinge.RightVector)
	if right.Magnitude < 1e-3 then
		right = V3(1, 0, 0)
	end
	return right.Unit * (dir >= 0 and 1 or -1) * num(act.PendulumKnock, 70) + V3(0, num(act.PendulumKnockUp, 30), 0)
end

-- the Event HP hazard of one pass: a Box strip across the lane under the hinge, impact at the pass. The knock-back is
-- not the hazard's own radial Knock (that would push along the lane from the strip's centre line): SealRun applies
-- R.SwingKnock from the hazard's OnHit, in the direction the coffin swings.
function R.PendulumHazard(spec: any, cross: any, act: any): { [string]: any }
	local h: CFrame = spec.Hinge
	local look = flat(h.LookVector)
	if look.Magnitude < 1e-3 then
		look = V3(0, 0, -1)
	end
	look = look.Unit
	local strip = act.PendulumStrip or { 14, 8, 4.6 }
	local centre = V3(h.Position.X, spec.GroundY + num(strip[2], 8) / 2, h.Position.Z)
	local cf = CFrame.new(centre) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	return {
		Shape = Hazards.Box(cf, V3(num(strip[1], 14), num(strip[2], 8), num(strip[3], 4.6))),
		Telegraph = num(act.PendulumTelegraph, 1),
		ImpactAt = cross.T,
		Damage = num(act.PendulumDamage, 12),
		Kind = "Pendulum",
		Source = "Pendulum",
		Pendulum = spec.Index,
		Swing = cross.Dir,
		KnockVelocity = R.SwingKnock(spec, cross.Dir, act),
	}
end

-- minimum time of a leg of `dist` studs: distance / (max speed x slack) (§8.4.2)
function R.MinLegTime(dist: number, act: any): number
	return math.max(0, dist) / (num(act.MaxSpeed, 72) * num(act.SpeedSlack, 1.15))
end

-- closest approach (flat) of the segment p0 -> p1 to c: distance, k in [0, 1] along the segment, the segment's Y at k
function R.SegmentClosest(p0: Vector3, p1: Vector3, c: Vector3): (number, number, number)
	local a, b, q = flat(p0), flat(p1), flat(c)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local k = len2 > 1e-9 and math.clamp((q - a):Dot(ab) / len2, 0, 1) or 0
	local d = (a + ab * k - q).Magnitude
	return d, k, p0.Y + (p1.Y - p0.Y) * k
end

function R.CrossesCheckpoint(p0: Vector3, p1: Vector3, c: Vector3, radius: number, band: number): (boolean, number)
	local d, k, y = R.SegmentClosest(p0, p1, c)
	return d <= radius and math.abs(y - c.Y) <= band, k
end

-- the fastest honest speed (studs / s): Activity.MaxSpeed x Activity.SpeedSlack (72 x 1.15; covers the conveyor belt
-- and the carousel deck carrying a top-speed runner)
function R.RunSpeed(act: any): number
	return num(act.MaxSpeed, 72) * num(act.SpeedSlack, 1.15)
end

-- a runner (server state): legs are measured between the points where the sampled path passed each ring (the closest
-- approach to its centre), and since the last fresh segment (GO / a rewind) in total; Credit / LegCredit are seconds a
-- pendulum knock-back may have saved
function R.NewRunner(start: Vector3, goAt: number): { [string]: any }
	return { Next = 1, LegFrom = start, LegAt = goAt, SegAt = goAt, SegDist = 0, Credit = 0, LegCredit = 0, Last = nil, LastAt = 0,
		MovedAt = 0, KnockUntil = -1e9, Violations = 0, Times = {}, Done = false, FinishAt = nil, Rewind = false }
end

-- a pendulum knock-back hit the runner: faster samples are allowed until `untilT`, and the legs get a time credit
function R.Knocked(st: any, untilT: number, act: any)
	if untilT > st.KnockUntil then
		local credit = num(act.KnockSpeed, 0) * num(act.KnockGrace, 0) / R.RunSpeed(act)
		st.Credit += credit
		st.LegCredit += credit
		st.KnockUntil = untilT
	end
end

-- one 4 Hz server sample of a runner -> events (in order):
--   {Kind = "Jump", Distance, Allowed}      moved farther than possible since its last move (teleport): rewind
--   {Kind = "TooFast", Index, Leg, Min}     reached ring Index faster than the distance allows (this leg, or all legs
--                                           since GO / the last rewind): not credited, rewind
--   {Kind = "Checkpoint", Index, Time, Leg} ring Index credited at server time Time (interpolated on the segment)
--   {Kind = "Finish", Time}                 the last ring
-- After a "Jump" / "TooFast" st.Rewind = true: the caller puts the runner back on its last ring and calls
-- R.Rewound(st, t, at); every violation counts (st.Violations).
function R.RunStep(st: any, pos: Vector3, t: number, cps: { Vector3 }, act: any): { any }
	local events = {}
	if st.Done or st.Rewind then
		return events
	end
	if st.Last == nil then
		st.Last, st.LastAt, st.MovedAt = pos, t, t
	end
	local p0: Vector3 = st.Last
	local d = flat(pos - p0).Magnitude
	local moved = d > .05
	local sinceMove = math.max(0, t - st.MovedAt)
	local speed = R.RunSpeed(act)
	local stepSpeed = speed + (t < st.KnockUntil and num(act.KnockSpeed, 0) or 0)
	local allowed = stepSpeed * sinceMove + num(act.JumpSlack, 8)
	if moved and d > allowed then
		st.Violations += 1
		st.Rewind = true
		table.insert(events, { Kind = "Jump", Distance = d, Allowed = allowed })
		return events
	end
	local r = num(act.CheckpointRadius, 7) + num(act.CheckpointSlack, 0)
	local band = num(act.CheckpointBand, 12)
	local slack = num(act.LegTimeSlack, .25)
	local from = p0
	local fromAt = st.LastAt
	-- at most two rings per sample (a fast runner over two close rings)
	for _ = 1, 2 do
		local c = cps[st.Next]
		if not c then
			break
		end
		local hit, k = R.CrossesCheckpoint(from, pos, c, r, band)
		if not hit then
			break
		end
		local at = from:Lerp(pos, k)
		local tc = fromAt + (t - fromAt) * k
		local legDist = flat(at - st.LegFrom).Magnitude
		local leg = tc - st.LegAt
		local minLeg = R.MinLegTime(legDist, act) - slack - st.LegCredit
		local minAll = R.MinLegTime(st.SegDist + legDist, act) - slack - st.Credit
		if leg + 1e-6 < minLeg or tc - st.SegAt + 1e-6 < minAll then
			st.Violations += 1
			st.Rewind = true
			table.insert(events, { Kind = "TooFast", Index = st.Next, Leg = leg, Min = minLeg, Total = tc - st.SegAt, MinTotal = minAll })
			return events
		end
		st.Times[st.Next] = tc
		table.insert(events, { Kind = "Checkpoint", Index = st.Next, Time = tc, Leg = leg })
		st.SegDist += legDist
		st.LegFrom, st.LegAt, st.LegCredit = at, tc, 0
		st.Next += 1
		if st.Next > #cps then
			st.Done, st.FinishAt = true, tc
			table.insert(events, { Kind = "Finish", Time = tc })
			break
		end
		from, fromAt = at, tc
	end
	if moved then
		st.MovedAt = t
	end
	st.Last, st.LastAt = pos, t
	return events
end

-- the runner was put back at `at` (its last ring, or where it began) at server time t: a fresh segment starts there
function R.Rewound(st: any, t: number, at: Vector3)
	st.Rewind = false
	st.Last, st.LastAt, st.MovedAt = nil, t, t
	st.LegFrom, st.LegAt, st.SegAt, st.SegDist = at, t, t, 0
	st.Credit, st.LegCredit = 0, 0
end

-- the leg (i -> i + 1) whose straight line crosses the carousel deck nearest to its centre, or nil
function R.CarouselLeg(cps: { Vector3 }, centre: Vector3, radius: number): number?
	local best, bd = nil, math.huge
	for i = 1, #cps - 1 do
		local d = R.SegmentClosest(cps[i], cps[i + 1], centre)
		if d <= radius and d < bd then
			best, bd = i, d
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------
-- III · MIRROR GRAVES
---------------------------------------------------------------------------------------------------------------------
R.Graves = 6

function R.Flip(d: number): number
	return (4 - (math.floor(d) % 4)) % 4
end

function R.MirrorOf(i: number, n: number?): number
	return (n or R.Graves) + 1 - i
end

-- world facing of orientation d (0 = +Z, 1 = +X, 2 = -Z, 3 = -X), exact (no float drift)
local FACING = { [0] = V3(0, 0, 1), [1] = V3(1, 0, 0), [2] = V3(0, 0, -1), [3] = V3(-1, 0, 0) }
function R.Facing(d: number): Vector3
	return FACING[math.floor(d) % 4]
end

-- per-player daily seed (the run leader's): the same three puzzles all UTC day
function R.MirrorSeed(userId: number, day: number): number
	local u = math.floor(math.abs(num(userId, 0))) % 2147483
	local d = math.floor(num(day, 0)) % 1000003
	return (u * 48271 + d * 69621 + 12345) % 2147483646 + 1
end

-- the rounds of one puzzle: {{Index, Active = {sorted grave numbers}, Target = {[i] = d}, Start = {[i] = d}}}
function R.MirrorRounds(seed: number, act: any): { any }
	local rand = lcg(seed)
	local n = math.floor(num(act.Graves, R.Graves))
	local rounds = {}
	for r, count in ipairs(act.Rounds or { 4, 5, 6 }) do
		count = math.clamp(math.floor(num(count, n)), 1, n)
		local order = {}
		for i = 1, n do
			order[i] = i
		end
		for i = n, 2, -1 do
			local j = math.floor(rand() * i) + 1
			order[i], order[j] = order[j], order[i]
		end
		local active = {}
		for i = 1, count do
			table.insert(active, order[i])
		end
		table.sort(active)
		local target, start = {}, {}
		for i = 1, n do
			target[i] = math.floor(rand() * 4) % 4
			start[i] = math.floor(rand() * 4) % 4
		end
		local need = math.ceil(count * num(act.MinWrongShare, .75) - 1e-9)
		local wrong = 0
		for _, g in ipairs(active) do
			if start[g] ~= target[g] then
				wrong += 1
			end
		end
		for _, g in ipairs(active) do
			if wrong >= need then
				break
			end
			if start[g] == target[g] then
				start[g] = (target[g] + 1 + math.floor(rand() * 3)) % 4
				wrong += 1
			end
		end
		rounds[r] = { Index = r, Active = active, Target = target, Start = start }
	end
	return rounds
end

-- what the pond shows: for every active grave g its rune appears at the mirrored place 7 - g, facing Flip(target)
function R.Reflection(round: any, n: number?): { any }
	local out = {}
	for _, g in ipairs(round.Active) do
		table.insert(out, { Grave = g, At = R.MirrorOf(g, n), Dir = R.Flip(round.Target[g]) })
	end
	return out
end

-- the arrangement the reflection asks for (what a player has to work out): target[g] = Flip(shown direction)
function R.Solve(reflection: { any }): { [number]: number }
	local out = {}
	for _, e in ipairs(reflection) do
		out[e.Grave] = R.Flip(e.Dir)
	end
	return out
end

-- every active grave turned to its target? -> ok, misaligned count
function R.MirrorCheck(round: any, current: { [number]: number }): (boolean, number)
	local wrong = 0
	for _, g in ipairs(round.Active) do
		if (math.floor(num(current[g], -1)) % 4) ~= round.Target[g] then
			wrong += 1
		end
	end
	return wrong == 0, wrong
end

-- quarter turns still needed (each TURN adds one quarter: d -> d + 1)
function R.TurnsNeeded(round: any, current: { [number]: number }): number
	local n = 0
	for _, g in ipairs(round.Active) do
		n += (round.Target[g] - math.floor(num(current[g], 0))) % 4
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- IV · HOLLOW MINE
---------------------------------------------------------------------------------------------------------------------
-- node HP (tier-normalised: NodeHits plain Wooden hits for one player, + PartyHP per extra member) and the HP unit
function R.NodeHP(act: any, party: number): (number, number)
	local unit = num(act.Unit, 10)
	local mult = 1 + num(act.PartyHP, 0) * math.max(0, (party or 1) - 1)
	return math.max(unit, math.floor(num(act.NodeHits, 7) * unit * mult + .5)), unit
end

local function floorBox(layout: any): (Vector3, Vector3, number)
	local f = layout.Undercrypt.Floor
	return f.Min, f.Max, layout.Undercrypt.FloorY
end

-- a position on the sunken mine floor (inside the floor box, up to FloorBand above it)
function R.OnFloor(pos: Vector3, layout: any, act: any): boolean
	local a, b, y = floorBox(layout)
	return pos.X >= a.X - 2 and pos.X <= b.X + 2 and pos.Z >= a.Z - 2 and pos.Z <= b.Z + 2 and pos.Y >= y - 3
		and pos.Y <= y + num(act.FloorBand, 7)
end

-- p moved inside the floor box (shrunk by margin), on the floor height
function R.ClampFloor(p: Vector3, layout: any, margin: number?): Vector3
	local a, b, y = floorBox(layout)
	local m = margin or 0
	return V3(math.clamp(p.X, a.X + m, b.X - m), y, math.clamp(p.Z, a.Z + m, b.Z - m))
end

function R.RockDef(pos: Vector3, act: any): { [string]: any }
	local c = act.Rocks or {}
	return { Shape = Hazards.Circle(pos, num(c.Radius, 6)), Telegraph = num(c.Telegraph, 1.4), Damage = num(c.Damage, 18), Kind = "Rock",
		Source = "HollowMine" }
end

function R.GasDef(pos: Vector3, act: any): { [string]: any }
	local c = act.Gas or {}
	return { Shape = Hazards.Circle(pos, num(c.Radius, 5)), Telegraph = num(c.Telegraph, 1.2), Damage = 0, DPS = num(c.DPS, 6),
		Linger = num(c.Linger, 6), Kind = "Gas", Source = "HollowMine" }
end

-- a collapsing tunnel: a Line of Tunnel.Length through `centre` at `angle` (radians), clipped to the floor box
function R.TunnelDef(centre: Vector3, angle: number, act: any, layout: any): { [string]: any }
	local c = act.Tunnel or {}
	local a, b, y = floorBox(layout)
	local m = num(act.FloorMargin, 0)
	local half = num(c.Length, 40) / 2
	local lo, hi = V3(a.X + m, y, a.Z + m), V3(b.X - m, y, b.Z - m)
	local p = V3(math.clamp(centre.X, lo.X, hi.X), y, math.clamp(centre.Z, lo.Z, hi.Z))
	-- Liang-Barsky clip of p + dir * s, s in [-half, half], to the (shrunk) floor rectangle
	local function clipped(ang: number): (Vector3, number, number)
		local dir = V3(math.cos(ang), 0, math.sin(ang))
		local s0, s1 = -half, half
		for _, axis in ipairs({ "X", "Z" }) do
			local q, d = (p :: any)[axis], (dir :: any)[axis]
			local l, h = (lo :: any)[axis], (hi :: any)[axis]
			if math.abs(d) > 1e-9 then
				local ta, tb = (l - q) / d, (h - q) / d
				if ta > tb then
					ta, tb = tb, ta
				end
				s0, s1 = math.max(s0, ta), math.min(s1, tb)
			end
		end
		return dir, s0, s1
	end
	local dir, s0, s1 = clipped(angle)
	if s1 - s0 < half then
		-- squeezed into a corner: the perpendicular crosses the floor instead
		local dir2, t0, t1 = clipped(angle + math.pi / 2)
		if t1 - t0 > s1 - s0 then
			dir, s0, s1 = dir2, t0, t1
		end
	end
	return { Shape = Hazards.Line(p + dir * s0, p + dir * s1, num(c.Width, 8)), Telegraph = num(c.Telegraph, 1.6), Damage = num(c.Damage, 22),
		Kind = "Collapse", Source = "HollowMine" }
end

return R
