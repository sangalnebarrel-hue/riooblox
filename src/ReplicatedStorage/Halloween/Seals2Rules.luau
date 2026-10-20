-- Pure rules of BELL SEALS V-VII, BELL RESONANCE and the BLACK BELL ASSAULT (ReplicatedStorage.Halloween.Seals2Rules,
-- WP-J; docs/halloween2/DESIGN.md §8.4 items 5-7, §8.6). Requires only config + the pure Hazards module, so Lune tests run
-- it as is (tests/seals_5_7.luau). The server activities (SealDoors, SealChoir, SealBell, Resonance) roll and judge with
-- it; the presenters read the same timing helpers so the screen agrees with the server.
--   CROOKED DOORS  PickOutcome(u, base) · NewDeal(rng, base, {Moth}) -> {Doors = {outcome x4}, Hint?, MothRolled}
--                  RewardChest / ChallengeRewards / MiniBossRewards / RareRoom(rng, base) -> reward rows (ctx.C2Reward)
--                  FindPick(rng, base) · Counts(outcome, won) · SealStep(progress, add, need) -> new, due · DoorsLeft(u, base)
--                  ChallengeWave(kind, court, playerPos, t, cfg, rng) · ChallengeKind(prev, rng) · DoorkeeperAttack(kind, ...)
--   CHOIR HUNT     Judge(quality) · LoopLength / LoopAt(points, s) · Flee(points, s, from, player, dist) · Nearest(pos, list)
--                  Routes(allowed, cfg) · SingAt(i, startedAt, cfg, n) (the deterministic singing schedule)
--   LAST BELL      Toll(center, bands, opts) -> ring hazard defs · ChainNeed / WeakHP(fighters, act) · PulseBright(...)
--                  Burn(keeper, fighters, cfg, rng, frac) -> line + circle defs · Every(range, frac)
--   RESONANCE      Goal(active, base) · Milestone(value, goal, base) · NewMilestones(prev, value, goal, base)
--                  AssaultMaxHP(attackers, base) · AssaultPhase(frac, cfg)
-- Every hazard def returned here is {Shape, Telegraph, Damage, Kind, Source, Delay?, Knock?, DPS?, Linger?} for
-- EventHP.Hazard / HazardWave (which re-checks fairness with Hazards.Sanitize anyway).
local Halloween = script.Parent
local Hazards = require(Halloween:WaitForChild("Hazards"))

local R = {}
R.Hazards = Hazards

local V3 = Vector3.new

local function num(v: any, d: number?): number
	local n = tonumber(v)
	if n == nil or n ~= n then
		return d or 0
	end
	return n
end

local function tbl(v: any): any
	return type(v) == "table" and v or {}
end

local function unit(rng: any): number
	if type(rng) == "function" then
		return rng()
	end
	return rng:NextNumber()
end
R.Unit = unit

local function between(rng: any, lo: number, hi: number): number
	lo, hi = math.floor(num(lo)), math.floor(num(hi))
	if hi <= lo then
		return lo
	end
	return math.min(hi, lo + math.floor(unit(rng) * (hi - lo + 1)))
end
R.Between = between

local function range(rng: any, r: any): number
	if type(r) == "table" then
		return between(rng, r[1] or 0, r[2] or r[1] or 0)
	end
	return math.floor(num(r))
end

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

function R.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- a {start, end} pair at progress frac (0 = start, 1 = end)
function R.Every(r: any, frac: number): number
	if type(r) ~= "table" then
		return num(r)
	end
	return R.Lerp(num(r[1]), num(r[2] or r[1]), frac)
end

---------------------------------------------------------------------------------------------------------------------
-- CROOKED DOORS
---------------------------------------------------------------------------------------------------------------------
-- the outcome of a roll u in [0, 1) over Chapter2Config.Doors.Outcomes weights (Reward 40 / Challenge 30 / MiniBoss 20 /
-- Rare 10)
function R.PickOutcome(u: number, base: any): string
	local rows = base.Doors.Outcomes
	local total = 0
	for _, row in ipairs(rows) do
		total += math.max(0, num(row.Weight))
	end
	local x = math.clamp(num(u), 0, 1 - 1e-9) * total
	for _, row in ipairs(rows) do
		x -= math.max(0, num(row.Weight))
		if x < 0 then
			return row.Id
		end
	end
	return rows[#rows].Id
end

-- a deal = what waits behind each of the four doors for the player's next opening (i.i.d. rolls, so a blind pick keeps
-- the 40/30/20/10 odds). opts.Moth (H13 Moth Hound in the yard team): with MothChance a moth marks one reward door
-- BEFORE the choice (when one exists).
function R.NewDeal(rng: any, base: any, opts: any?): any
	local o = tbl(opts)
	local deal = { Doors = {}, Hint = nil, MothRolled = false }
	local count = num(o.Count, 4)
	for i = 1, count do
		deal.Doors[i] = R.PickOutcome(unit(rng), base)
	end
	if o.Moth then
		deal.MothRolled = true
		if unit(rng) < num(base.Doors.MothChance) then
			local rewards = {}
			for i, outcome in ipairs(deal.Doors) do
				if outcome == "Reward" then
					table.insert(rewards, i)
				end
			end
			if #rewards > 0 then
				deal.Hint = rewards[math.clamp(1 + math.floor(unit(rng) * #rewards), 1, #rewards)]
			end
		end
	end
	return deal
end

-- one showcase find, weighted like the Black Coffin (Chapter2Config.Finds.TierWeight)
function R.FindPick(rng: any, base: any): string
	local finds = base.Finds
	local total = 0
	for _, id in ipairs(finds.Order) do
		total += num(finds.TierWeight[finds.Defs[id].Tier])
	end
	local x = unit(rng) * total
	for _, id in ipairs(finds.Order) do
		x -= num(finds.TierWeight[finds.Defs[id].Tier])
		if x < 0 then
			return id
		end
	end
	return finds.Order[#finds.Order]
end

-- the reward chest behind a Reward door: shards 30-80 (DR source "Door"), dust, 15% Coffin Key, a small find chance
function R.RewardChest(rng: any, base: any): { any }
	local d = base.Doors.Reward
	local rows = {
		{ Kind = "Shards", Amount = range(rng, d.Shards), Source = "Door" },
		{ Kind = "Dust", Amount = range(rng, d.Dust) },
	}
	if unit(rng) < num(d.KeyChance) then
		table.insert(rows, { Kind = "Key", Amount = 1, Source = "Door" })
	end
	if unit(rng) < num(d.FindChance) then
		table.insert(rows, { Kind = "Find", Id = R.FindPick(rng, base) })
	end
	return rows
end

-- a won 25 s challenge
function R.ChallengeRewards(rng: any, base: any): { any }
	local d = base.Doors.Challenge
	return { { Kind = "Shards", Amount = range(rng, d.Shards), Source = "Door" }, { Kind = "Dust", Amount = range(rng, d.Dust) } }
end

-- THE DOORKEEPER defeated (every member of the fight)
function R.MiniBossRewards(rng: any, base: any): { any }
	local d = base.Doors.MiniBoss
	local rows = { { Kind = "Shards", Amount = range(rng, d.Shards), Source = "Door" }, { Kind = "Dust", Amount = range(rng, d.Dust) } }
	if unit(rng) < num(d.KeyChance) then
		table.insert(rows, { Kind = "Key", Amount = 1, Source = "Door" })
	end
	return rows
end

-- the hidden room: three chests (shuffled) = a guaranteed showcase find · Coffin Key(s) · Lucky Dust; the 0.5% HOLLOW
-- KING roll joins the dust chest. -> {Chests = {{rows}, {rows}, {rows}}, Rows = all rows, HollowKing = bool}
function R.RareRoom(rng: any, base: any): any
	local d = base.Doors.Rare
	local findRows = {}
	for _ = 1, math.max(1, math.floor(num(d.Finds, 1))) do
		table.insert(findRows, { Kind = "Find", Id = R.FindPick(rng, base) })
	end
	local keyRows = { { Kind = "Key", Amount = math.max(1, math.floor(num(d.Keys, 1))), Source = "Rare" } }
	local dustRows = { { Kind = "Dust", Amount = range(rng, d.Dust) } }
	local king = unit(rng) < num(d.HollowKingChance)
	if king then
		local def = base.Dogs.Defs.HW_HollowKing
		table.insert(dustRows, { Kind = "Dog", Id = "HW_HollowKing", Rank = def and def.Rank or 6 })
	end
	local chests = { findRows, keyRows, dustRows }
	-- Fisher-Yates: which chest holds what is a surprise
	for i = #chests, 2, -1 do
		local j = math.clamp(1 + math.floor(unit(rng) * i), 1, i)
		chests[i], chests[j] = chests[j], chests[i]
	end
	local all = {}
	for _, list in ipairs(chests) do
		for _, row in ipairs(list) do
			table.insert(all, row)
		end
	end
	return { Chests = chests, Rows = all, HollowKing = king }
end

-- does an outcome count for Seal V? Reward and Rare always; a challenge / mini boss only when won
function R.Counts(outcome: string, won: boolean?): boolean
	if outcome == "Reward" or outcome == "Rare" then
		return true
	end
	return (outcome == "Challenge" or outcome == "MiniBoss") and won == true
end

-- persistent Seal V progress: new total and how many seal clears (first / repeat) became due with this step
function R.SealStep(progress: number, add: number, need: number): (number, number)
	progress = math.max(0, math.floor(num(progress)))
	add = math.max(0, math.floor(num(add)))
	need = math.max(1, math.floor(num(need, 3)))
	local new = progress + add
	return new, math.floor(new / need) - math.floor(progress / need)
end

-- door openings left today (Chapter2Config.Doors.PerDay, +ContractBonus when all of today's contracts are claimed)
function R.DoorsLeft(u: any, base: any, today: number?): (number, number)
	local daily = tbl(tbl(u).Daily)
	local contracts = tbl(daily.Contracts)
	local max = num(base.Doors.PerDay) + (contracts.AllClaimed == true and num(base.Doors.ContractBonus) or 0)
	local used = (today == nil or daily.Day == today) and num(daily.Doors) or 0
	return math.max(0, max - used), max
end

-- the door challenge: wave kinds in a shuffled cycle, never the same kind twice in a row
R.ChallengeKinds = { "Stomp", "Cross", "Ripple", "Lanes" }
function R.ChallengeKind(prev: string?, rng: any): string
	local pool = {}
	for _, k in ipairs(R.ChallengeKinds) do
		if k ~= prev then
			table.insert(pool, k)
		end
	end
	return pool[math.clamp(1 + math.floor(unit(rng) * #pool), 1, #pool)]
end

local function hz(shape: any, telegraph: number, damage: number, kind: string, source: string, extra: any?): any
	local d = { Shape = shape, Telegraph = telegraph, Damage = damage, Kind = kind, Source = source }
	for k, v in pairs(tbl(extra)) do
		d[k] = v
	end
	return d
end

local function dirAt(a: number): Vector3
	return V3(math.cos(a), 0, math.sin(a))
end

-- ring doorways: `count` gaps of `width` degrees starting at `start`
local function gaps(start: number, count: number, width: number): { any }
	local out = {}
	for k = 0, count - 1 do
		table.insert(out, { Angle = (start + k * 360 / count) % 360, Width = width })
	end
	return out
end
R.Gaps = gaps

-- one wave of the 25 s hazard dance. court = {Center, Radius}; t = seconds since the start (telegraphs shorten);
-- cfg = Seals2Config.Doors.Challenge. -> hazard defs (all impact together, except the Finale's moving safe circle)
function R.ChallengeWave(kind: string, court: any, playerPos: Vector3, t: number, cfg: any, rng: any, seconds: number?): { any }
	local frac = math.clamp(num(t) / math.max(1, num(seconds, 25)), 0, 1)
	local tele = R.Every(cfg.Telegraph, frac)
	local dmg = num(cfg.Damage)
	local center: Vector3 = court.Center
	local p = V3(playerPos.X, center.Y, playerPos.Z)
	-- keep the target inside the court (a player at the rim still gets a fair pattern around the court)
	local off = flat(p - center)
	if off.Magnitude > num(court.Radius) then
		p = center + off.Unit * num(court.Radius)
	end
	local out = {}
	local a0 = unit(rng) * math.pi * 2
	if kind == "Stomp" then
		local s = cfg.Stomp
		table.insert(out, hz(Hazards.Circle(p, s.Radius), tele, dmg, "Stomp", "DoorChallenge"))
		for k = 1, num(s.Extra) do
			local a = a0 + k * math.pi * 2 / math.max(1, num(s.Extra))
			table.insert(out, hz(Hazards.Circle(p + dirAt(a) * s.Spread, s.Radius), tele, dmg, "Stomp", "DoorChallenge"))
		end
	elseif kind == "Cross" then
		local s = cfg.Cross
		for k = 0, 1 do
			local d = dirAt(a0 + k * math.pi / 2)
			table.insert(out, hz(Hazards.Line(p - d * s.Length / 2, p + d * s.Length / 2, s.Width), tele, dmg, "Line", "DoorChallenge"))
		end
	elseif kind == "Lanes" then
		local s = cfg.Lanes
		local d = dirAt(a0)
		local side = V3(-d.Z, 0, d.X)
		local n = math.max(1, num(s.Count))
		for k = 1, n do
			local o = (k - (n + 1) / 2) * num(s.Spacing)
			local c = p + side * o
			table.insert(out, hz(Hazards.Line(c - d * s.Length / 2, c + d * s.Length / 2, s.Width), tele, dmg, "Line", "DoorChallenge"))
		end
	elseif kind == "Ripple" then
		local s = cfg.Ripple
		table.insert(out, hz(Hazards.Ring(center, s.Inner, s.Outer, gaps(math.deg(a0), s.Gaps, s.GapWidth)), tele, dmg, "Ring",
			"DoorChallenge"))
	elseif kind == "Finale" then
		-- a moving safe circle: stay inside it (everyone outside takes DPS while it lingers)
		local s = cfg.Finale
		local a = a0
		local orbit = num(court.Radius) * .35
		local start = center + dirAt(a) * orbit
		local path = { { At = 0, Center = start } }
		local pos, at = start, 0
		-- hops across the court at Speed until the safe circle has outlived its Linger
		for _ = 1, 6 do
			a += math.pi * (.55 + .2 * unit(rng))
			local nxt = center + dirAt(a) * orbit
			at += (nxt - pos).Magnitude / math.max(1, num(s.Speed))
			table.insert(path, { At = at, Center = nxt })
			pos = nxt
			if at >= num(s.Linger) then
				break
			end
		end
		table.insert(out, hz(Hazards.Safe(start, s.Radius, num(court.Radius) + 14, { Path = path }), math.max(tele, num(s.Telegraph)), 0,
			"Safe", "DoorChallenge", { DPS = s.DPS, Linger = s.Linger }))
	end
	return out
end

-- one attack of THE DOORKEEPER (keeper = its ground position, target = a fighter's position)
function R.DoorkeeperAttack(kind: string, keeper: Vector3, target: Vector3, cfg: any, rng: any, second: Vector3?): { any }
	local a = cfg.Attacks[kind]
	local out = {}
	if not a then
		return out
	end
	local t = V3(target.X, keeper.Y, target.Z)
	local dir = flat(t - keeper)
	if dir.Magnitude < .5 then
		dir = dirAt(unit(rng) * math.pi * 2)
	end
	dir = dir.Unit
	if kind == "Slam" then
		table.insert(out, hz(Hazards.Circle(t, a.Radius), a.Telegraph, a.Damage, "Slam", "Doorkeeper"))
		if second then
			table.insert(out, hz(Hazards.Circle(V3(second.X, keeper.Y, second.Z), a.Radius), a.Telegraph, a.Damage, "Slam", "Doorkeeper"))
		end
	elseif kind == "Sweep" then
		table.insert(out, hz(Hazards.Cone(keeper, dir, a.Angle, a.Radius), a.Telegraph, a.Damage, "Sweep", "Doorkeeper"))
	elseif kind == "Ring" then
		local start = math.deg(math.atan2(dir.Z, dir.X)) + 180 + (unit(rng) - .5) * 60
		table.insert(out, hz(Hazards.Ring(keeper, a.Inner, a.Outer, gaps(start, 1, a.GapWidth)), a.Telegraph, a.Damage, "Ring", "Doorkeeper"))
	elseif kind == "Charge" then
		table.insert(out, hz(Hazards.Line(keeper, keeper + dir * a.Length, a.Width), a.Telegraph, a.Damage, "Line", "Doorkeeper",
			{ Knock = { Power = 40, Up = 18 } }))
	end
	return out
end

-- a weighted attack kind (Seals2Config.Doors.Doorkeeper.Attacks[*].Weight), never the same twice in a row when possible
function R.AttackKind(cfg: any, prev: string?, rng: any): string
	local names = {}
	for name in pairs(cfg.Attacks) do
		table.insert(names, name)
	end
	table.sort(names)
	local total = 0
	for _, name in ipairs(names) do
		if name ~= prev then
			total += num(cfg.Attacks[name].Weight, 1)
		end
	end
	local x = unit(rng) * total
	for _, name in ipairs(names) do
		if name ~= prev then
			x -= num(cfg.Attacks[name].Weight, 1)
			if x < 0 then
				return name
			end
		end
	end
	return names[1]
end

---------------------------------------------------------------------------------------------------------------------
-- CHOIR HUNT
---------------------------------------------------------------------------------------------------------------------
-- only a Perfect catches a choir spirit; a Good hit scares it away
function R.Judge(quality: number?): string
	return quality == 2 and "Catch" or "Flee"
end

-- closed loop through `points` (the last point joins the first)
function R.LoopLength(points: { Vector3 }): number
	local n, total = #points, 0
	for i = 1, n do
		total += (points[i % n + 1] - points[i]).Magnitude
	end
	return total
end

-- position at arc length s along the loop -> pos, segment index (1..n), distance into that segment, segment length
function R.LoopAt(points: { Vector3 }, s: number): (Vector3, number, number, number)
	local n = #points
	if n == 0 then
		return Vector3.zero, 1, 0, 0
	elseif n == 1 then
		return points[1], 1, 0, 0
	end
	local total = R.LoopLength(points)
	if total <= 0 then
		return points[1], 1, 0, 0
	end
	s = num(s) % total
	for i = 1, n do
		local a, b = points[i], points[i % n + 1]
		local len = (b - a).Magnitude
		if s <= len or i == n then
			local k = len > 0 and math.clamp(s / len, 0, 1) or 0
			return a:Lerp(b, k), i, s, len
		end
		s -= len
	end
	return points[1], 1, 0, 0
end

-- arc length of the vertex i
function R.VertexS(points: { Vector3 }, i: number): number
	local s = 0
	for k = 1, math.clamp(i, 1, #points) - 1 do
		s += (points[k + 1] - points[k]).Magnitude
	end
	return s
end

-- where does a startled spirit at arc length s flee to? dist along the loop, the way that ends farther from the player
-- -> new s, position
function R.Flee(points: { Vector3 }, s: number, player: Vector3, dist: number): (number, Vector3)
	local total = R.LoopLength(points)
	if total <= 0 then
		return s, points[1] or Vector3.zero
	end
	local fwd = (s + dist) % total
	local back = (s - dist) % total
	local pf = R.LoopAt(points, fwd)
	local pb = R.LoopAt(points, back)
	if flat(pf - player).Magnitude >= flat(pb - player).Magnitude then
		return fwd, pf
	end
	return back, pb
end

-- the nearest entry of list = {{Id, Position}} to pos (flat distance) -> entry, distance
function R.Nearest(pos: Vector3, list: { any }): (any, number)
	local best, bestD = nil, math.huge
	for _, e in ipairs(list) do
		if e.Position then
			local d = flat(e.Position - pos).Magnitude
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best, bestD
end

-- the wander routes of the seven spirits: Seals2Config.Choir.Routes whose district is allowed (allowed(name) -> bool);
-- a route in a district the party may not enter is replaced by a Bell Square ring-road route
function R.Routes(allowed: (string) -> boolean, cfg: any): { any }
	local out = {}
	local fallback = {}
	for _, route in ipairs(cfg.Routes) do
		if route.District == "BellSquare" then
			table.insert(fallback, route)
		end
	end
	local k = 0
	for _, route in ipairs(cfg.Routes) do
		if allowed(route.District) then
			table.insert(out, route)
		else
			k += 1
			table.insert(out, fallback[(k - 1) % math.max(1, #fallback) + 1] or route)
		end
	end
	return out
end

-- spirit i of n sings at server times startedAt + phase + k * SingEvery: the next time >= now
function R.SingAt(i: number, startedAt: number, cfg: any, n: number, now: number): number
	local every = math.max(.5, num(cfg.SingEvery, 3.6))
	local phase = (i - 1) / math.max(1, n) * every
	local first = num(startedAt) + phase
	if now <= first then
		return first
	end
	return first + math.ceil((now - first) / every) * every
end

---------------------------------------------------------------------------------------------------------------------
-- LAST BELL TRIAL / BLACK BELL ASSAULT
---------------------------------------------------------------------------------------------------------------------
-- one toll of the Black Bell: expanding ring bands around `center`, each with doorways turned from the previous band's.
-- opts = {Bands = {{inner, outer}}, Gaps, GapWidth, GapTurn, Stagger, Telegraph, Damage, Start (degrees), Kind, Source}
function R.Toll(center: Vector3, opts: any): { any }
	local out = {}
	local start = num(opts.Start)
	for k, band in ipairs(opts.Bands) do
		local g = gaps(start + (k - 1) * num(opts.GapTurn), math.max(1, num(opts.Gaps, 2)), num(opts.GapWidth, 46))
		table.insert(out, hz(Hazards.Ring(center, band[1], band[2], g), num(opts.Telegraph, 1.3), num(opts.Damage, 14),
			opts.Kind or "Shockwave", opts.Source or "Bell", { Delay = (k - 1) * num(opts.Stagger) }))
	end
	return out
end

-- counted Perfect hits a chain needs / Power HP of the weak point, by fighters (Chapter2Config.Seals[7].Activity)
function R.ChainNeed(fighters: number, act: any): number
	return math.max(1, math.floor(num(act.ChainHits, 6) + num(act.ChainHitsPerFighter, 3) * math.max(0, math.floor(num(fighters, 1)) - 1)))
end

function R.WeakHP(fighters: number, act: any): number
	return math.max(1, num(act.WeakHP, 30) + num(act.WeakHPPerFighter, 10) * math.max(0, math.floor(num(fighters, 1)) - 1))
end

-- is server time `now` inside the bright part of a chain pulse that started at `since`? (+ grace seconds of latency
-- forgiveness after each bright part)
function R.PulseBright(now: number, since: number, period: number, bright: number, grace: number?): boolean
	period = math.max(.1, num(period, 1.2))
	local t = num(now) - num(since)
	if t < 0 then
		return false
	end
	local inPulse = t % period
	local edge = math.clamp(num(bright, .55), 0, 1) * period
	return inPulse <= edge + math.max(0, num(grace))
end

-- one volley of the weak-point burn: Lines from the keeper through fighters + Circles on fighters
-- fighters = {Vector3}; frac = remaining weak HP fraction (for the caller's pacing only); cfg = Seals2Config.Bell.Burn
function R.Burn(keeper: Vector3, fighters: { Vector3 }, cfg: any, rng: any): { any }
	local out = {}
	local line, circle = cfg.Line, cfg.Circle
	local order = table.clone(fighters)
	for i = #order, 2, -1 do
		local j = math.clamp(1 + math.floor(unit(rng) * i), 1, i)
		order[i], order[j] = order[j], order[i]
	end
	for k = 1, math.min(num(line.Count), #order) do
		local p = V3(order[k].X, keeper.Y, order[k].Z)
		local d = flat(p - keeper)
		if d.Magnitude < 1 then
			d = dirAt(unit(rng) * math.pi * 2)
		end
		d = d.Unit
		table.insert(out, hz(Hazards.Line(keeper, keeper + d * line.Length, line.Width), line.Telegraph, line.Damage, "Line", "Bellkeeper"))
	end
	for k = 1, math.min(num(circle.Max), #order) do
		local p = V3(order[k].X, keeper.Y, order[k].Z)
		table.insert(out, hz(Hazards.Circle(p, circle.Radius), circle.Telegraph, circle.Damage, "Bone", "Bellkeeper",
			{ Delay = .35 * (k - 1) }))
	end
	return out
end

-- the shared Bellkeeper of the Assault: HP scales with everyone who joined (BaseHP x HPPerAttacker per attacker)
function R.AssaultMaxHP(attackers: number, base: any): number
	local a = base.Resonance.Assault
	return math.max(1, num(a.BaseHP, 400) * num(a.HPPerAttacker, 1) * math.max(1, math.floor(num(attackers, 1))))
end

-- phase index (1..#Phases) by the remaining HP fraction (Seals2Config.Resonance.Assault.Phases)
function R.AssaultPhase(frac: number, cfg: any): number
	for i, ph in ipairs(cfg.Phases) do
		if num(frac) > num(ph.Above) then
			return i
		end
	end
	return #cfg.Phases
end

---------------------------------------------------------------------------------------------------------------------
-- BELL RESONANCE
---------------------------------------------------------------------------------------------------------------------
-- Goal = Base x clamp(active Underyard players / PlayerDivisor, Clamp[1], Clamp[2])
function R.Goal(active: number, base: any): number
	local r = base.Resonance
	local k = math.clamp(math.max(0, num(active)) / math.max(1, num(r.PlayerDivisor, 6)), num(r.Clamp[1], .6), num(r.Clamp[2], 2))
	return math.max(1, math.floor(num(r.Base, 4000) * k + .5))
end

-- the highest milestone reached (0..#Milestones) by value / goal
function R.Milestone(value: number, goal: number, base: any): number
	local frac = num(value) / math.max(1, num(goal))
	local best = 0
	for i, m in ipairs(base.Resonance.Milestones) do
		if frac + 1e-9 >= num(m.At) then
			best = i
		end
	end
	return best
end

-- milestones newly reached since `prev` (in order; a big jump or a lowered goal can pass several at once)
function R.NewMilestones(prev: number, value: number, goal: number, base: any): { number }
	local out = {}
	local now = R.Milestone(value, goal, base)
	for i = math.max(0, math.floor(num(prev))) + 1, now do
		table.insert(out, i)
	end
	return out
end

return R
