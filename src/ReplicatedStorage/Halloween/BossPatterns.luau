-- Hazard patterns of THE GRAVEKEEPER and its difficulty V finale (ReplicatedStorage.Halloween.BossPatterns, WP-C;
-- docs/halloween2/DESIGN.md §10.5, §11, §23). Pure: requires only Hazards, BossMath, Layout and the configs, takes the
-- server time and a random function as arguments, so tests/boss_finale.luau checks every pattern exactly as the server
-- (ServerScriptService.Halloween.Boss / BossFinale) builds it. Every generator returns EventHP hazard defs (absolute
-- ImpactAt, server time) that pass Hazards.Check and, impacting together, Hazards.CheckPattern on the arena floor (a
-- player can always stand somewhere safe): a candidate that fails is redrawn, then thinned until it passes.
--
-- Geometry: the Graveyard Pit of Layout.Pit (floor y -8 at the centre, a 48 x 48 arena floor inside the 60 x 60 rim
-- box, the terrace ring in between). Lines / rings / safe circles lie on the floor (their default Y band of +-10 also
-- covers the terrace); rocks and bone circles sit on the real surface (Models.Boss.Surface) with a narrow band
-- (Height = PatternBand) so a circle on the terrace never hits the floor below it and vice versa.
--
-- API
--   BossPatterns.Config() -> {Boss, Finale, Combat} ; BossPatterns.SetConfig(chapter2Like | nil)   (tests)
--   BossPatterns.Pit() -> {Center, FloorY, TerraceY, Rim, Arena, Half, RimHalf}
--   BossPatterns.Surface(x, z) -> y, kind            Models.Boss.Surface (flat floor without the model module)
--   BossPatterns.Area(radius?) -> {Center, Radius, Step}   the CheckPattern area (the arena floor)
--   BossPatterns.Telegraph(base, difficulty, damage) -> s   base x TelegraphScale[d], never below the §10.2 minimum
--   BossPatterns.Damage(base, difficulty) -> n            BossMath.EventDamage (difficulty mult, 45% cap)
--   BossPatterns.Count({lo, hi}, difficulty) -> n         III = lo .. V = hi
--   BossPatterns.Fair(defs, area?) -> ok, info {Problems, Safe}
--   BossPatterns.Thin(defs, area?) -> defs                drops hazards (last first) until the set is fair
--   BossPatterns.Ground(pos, radius, opts) -> Circle       a circle on the real surface with the narrow band
-- endgame (difficulties III-V; each -> defs, info {Name, StartAt, Duration})
--   BossPatterns.GraveLines(d, now, lead, rand, opts?)   3-5 Lines sweeping across the pit in sequence
--   BossPatterns.LanternWalk(d, now, lead, rand, opts?)  a moving Safe circle (opts.Toward = the fighters' centre)
--   BossPatterns.BoneRain(d, now, lead, rand, opts?)     12-18 staggered Circles (opts.Targets = fighter positions)
-- finale (difficulty V)
--   BossPatterns.Shockwave(now, lead, rand, opts?)       bell toll: 1-2 Rings with a gap
--   BossPatterns.Volley(now, lead, rand, opts?)          spirit Line volley from the rim (opts.Targets)
--   BossPatterns.GhostBite(pos, now, lead)               a ghost dog's telegraphed bite
--   BossPatterns.Hound(name, beatAt, beat, rand, opts?)  "Circles" | "Lines" | "Waves" | "SafeDance" on the beat grid
--                                                        -> defs, beats (pattern length in beats)
local root = script.Parent
local Hazards = require(root:WaitForChild("Hazards"))
local BossMath = require(root:WaitForChild("BossMath"))
local Layout = require(root:WaitForChild("Layout"))

local P = {}

local V3 = Vector3.new

P.Defaults = {
	Boss = {
		TelegraphScale = { 1, 1, .95, .9, .85 },
		Endgame = {
			GraveLines = { Count = { 3, 5 }, Damage = 18, Width = 6, Stagger = .45, Telegraph = 1.5, Knock = 30 },
			LanternWalk = { Radius = 9, Seconds = 8, DPS = 7, Grace = 1.2, Speed = 6 },
			BoneRain = { Count = { 12, 18 }, Radius = 4, Damage = 12, Stagger = .18, Telegraph = 1.4, Aimed = .4, Knock = 20 },
		},
		PatternBand = 3.4,
	},
	Finale = {
		Bell = { ShockwaveDamage = 14, ShockwaveGap = 50, ShockwaveTelegraph = 1.5, DoubleChance = .45 },
		Choir = { GhostBite = 8, GhostBiteRadius = 3.5, VolleyDamage = 14, VolleyTelegraph = 1.4, VolleyWidth = 5 },
		Hound = { BurstDamage = 12, LineDamage = 16, RingDamage = 14, SafeDPS = 7, SafeRadius = 8, SafeSpeed = 9 },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- config
---------------------------------------------------------------------------------------------------------------------
local override: any = nil
local cached: any = nil

local function merge(base: any, src: any): any
	local out = {}
	for k, v in pairs(base) do
		out[k] = type(v) == "table" and merge(v, {}) or v
	end
	if type(src) == "table" then
		for k, v in pairs(src) do
			if type(v) == "table" and type(out[k]) == "table" and #v == 0 then
				out[k] = merge(out[k], v)
			else
				out[k] = v
			end
		end
	end
	return out
end

local function resolve(m: any): any
	local src = type(m) == "table" and m or {}
	return { Boss = merge(P.Defaults.Boss, src.Boss), Finale = merge(P.Defaults.Finale, src.Finale), Combat = src.Combat }
end

function P.Config(): any
	if override then
		return override
	end
	if not cached then
		local m = nil
		pcall(function()
			local inst = root:FindFirstChild("Chapter2Config")
			m = inst and require(inst :: any)
		end)
		cached = resolve(m)
	end
	return cached
end

-- tests: a Chapter2Config-like table over the defaults (nil = the real config again)
function P.SetConfig(tbl: any?)
	override = tbl and resolve(tbl) or nil
	cached = nil
end

---------------------------------------------------------------------------------------------------------------------
-- pit geometry
---------------------------------------------------------------------------------------------------------------------
local pit = Layout.Pit
local CENTER = pit.Center
local ARENA_HALF = (pit.Arena.X1 - pit.Arena.X0) / 2
local RIM_HALF = (pit.Rim.X1 - pit.Rim.X0) / 2

function P.Pit(): any
	return { Center = CENTER, FloorY = pit.FloorY, TerraceY = pit.TerraceY, Rim = pit.Rim, Arena = pit.Arena, Half = ARENA_HALF,
		RimHalf = RIM_HALF }
end

local surfaceFn: any = nil
function P.Surface(x: number, z: number): (number, string)
	if surfaceFn == nil then
		surfaceFn = false
		pcall(function()
			local models = root:FindFirstChild("Models")
			local inst = models and models:FindFirstChild("Boss")
			local m = inst and require(inst :: any)
			if type(m) == "table" and type(m.Surface) == "function" then
				surfaceFn = m.Surface
			end
		end)
	end
	if surfaceFn then
		return surfaceFn(Layout, x, z)
	end
	local r = pit.Rim
	if x < r.X0 or x > r.X1 or z < r.Z0 or z > r.Z1 then
		return Layout.FloorY, "Rim"
	end
	return pit.FloorY, "Floor"
end

function P.Area(radius: number?): any
	return { Center = CENTER, Radius = radius or ARENA_HALF, Step = 2 }
end

---------------------------------------------------------------------------------------------------------------------
-- numbers
---------------------------------------------------------------------------------------------------------------------
local function clampD(d: number): number
	return math.clamp(math.floor(tonumber(d) or 1), 1, 5)
end

function P.Damage(base: number, difficulty: number): number
	return BossMath.EventDamage(base, clampD(difficulty))
end

function P.MinTelegraph(damage: number): number
	local lim = Hazards.Config()
	return (tonumber(damage) or 0) >= lim.HeavyDamage and lim.HeavyTelegraph or lim.MinTelegraph
end

function P.Telegraph(base: number, difficulty: number, damage: number): number
	local scale = P.Config().Boss.TelegraphScale or {}
	local s = tonumber(scale[clampD(difficulty)]) or 1
	return math.max(P.MinTelegraph(damage), (tonumber(base) or 1) * s)
end

function P.Count(range: any, difficulty: number): number
	if type(range) ~= "table" then
		return math.max(1, math.floor(tonumber(range) or 1))
	end
	local lo, hi = range[1] or 1, range[2] or range[1] or 1
	local k = math.clamp((clampD(difficulty) - 3) / 2, 0, 1)
	return math.floor(lo + (hi - lo) * k + .5)
end

---------------------------------------------------------------------------------------------------------------------
-- fairness
---------------------------------------------------------------------------------------------------------------------
function P.Fair(defs: { any }, area: any?): (boolean, any)
	local problems = {}
	for i, d in ipairs(defs) do
		local ok, list = Hazards.Check(d)
		if not ok then
			table.insert(problems, string.format("#%d %s: %s", i, tostring(d.Kind), table.concat(list, "; ")))
		end
	end
	local safeOk, safe = true, 1
	if #defs > 0 then
		safeOk, safe = Hazards.CheckPattern(defs, area or P.Area())
		if not safeOk then
			table.insert(problems, "no safe spot")
		end
	end
	return #problems == 0, { Problems = problems, Safe = safe }
end

-- drop hazards from the end until the set is fair (never returns an unfair set: an empty wave is fair)
function P.Thin(defs: { any }, area: any?): { any }
	local list = table.clone(defs)
	while #list > 0 do
		if P.Fair(list, area) then
			return list
		end
		table.remove(list)
	end
	return list
end

-- a circle on the real surface at (x, z): the centre sits at root height so the narrow band only reaches that level
function P.Ground(pos: Vector3, radius: number, opts: any?): any
	local y = P.Surface(pos.X, pos.Z)
	local band = (opts and opts.Band) or P.Config().Boss.PatternBand or 3.4
	return Hazards.Circle(V3(pos.X, y + 3, pos.Z), radius, { Height = band })
end

local function generate(build: () -> { any }, area: any?): { any }
	local last = {}
	for _ = 1, 8 do
		local defs = build()
		if P.Fair(defs, area) then
			return defs
		end
		last = defs
	end
	return P.Thin(last, area)
end

local function info(name: string, defs: { any }, now: number): any
	local ends = now
	for _, d in ipairs(defs) do
		ends = math.max(ends, Hazards.EndAt(d))
	end
	return { Name = name, StartAt = now, Duration = ends - now, Ends = ends }
end

local function pick(rand: () -> number, n: number): number
	return math.clamp(1 + math.floor(rand() * n), 1, n)
end

local function shuffle<T>(list: { T }, rand: () -> number): { T }
	for i = #list, 2, -1 do
		local j = pick(rand, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function inArena(x: number, z: number, margin: number): (number, number)
	local a = pit.Arena
	return math.clamp(x, a.X0 + margin, a.X1 - margin), math.clamp(z, a.Z0 + margin, a.Z1 - margin)
end

---------------------------------------------------------------------------------------------------------------------
-- ENDGAME (difficulties III-V)
---------------------------------------------------------------------------------------------------------------------
-- GRAVE LINES: n parallel lines across the whole pit, impacting one after another (the sweep), each in its own 6-wide
-- slot of the floor; the free slots are the safe lanes
function P.GraveLines(d: number, now: number, lead: number, rand: () -> number, _opts: any?): ({ any }, any)
	local g = P.Config().Boss.Endgame.GraveLines
	local n = P.Count(g.Count, d)
	local dmg = P.Damage(g.Damage, d)
	local tele = P.Telegraph(g.Telegraph or 1.5, d, dmg)
	local width = g.Width or 6
	local defs = generate(function()
		local angle = ({ 0, 90, 45, 135 })[pick(rand, 4)]
		local a = math.rad(angle)
		local dir = V3(math.cos(a), 0, math.sin(a))
		local perp = V3(-math.sin(a), 0, math.cos(a))
		local half = (angle % 90 == 0) and RIM_HALF + 4 or RIM_HALF * 1.42 + 4
		local slots = {}
		local span = ARENA_HALF + 3
		local count = math.floor(2 * span / width)
		for k = 0, count - 1 do
			table.insert(slots, -span + width / 2 + k * width)
		end
		shuffle(slots, rand)
		local chosen = {}
		for i = 1, math.min(n, #slots - 2) do
			table.insert(chosen, slots[i])
		end
		table.sort(chosen)
		if rand() < .5 then
			local rev = {}
			for i = #chosen, 1, -1 do
				table.insert(rev, chosen[i])
			end
			chosen = rev
		end
		local out = {}
		for i, off in ipairs(chosen) do
			local c = CENTER + perp * off
			table.insert(out, { Shape = Hazards.Line(c - dir * half, c + dir * half, width), Telegraph = tele,
				ImpactAt = now + lead + tele + (i - 1) * (g.Stagger or .45), Damage = dmg, Knock = { Power = g.Knock or 30, Up = 18 },
				Kind = "GraveLine", Source = "Gravekeeper" })
		end
		return out
	end)
	return defs, info("GraveLines", defs, now)
end

-- LANTERN WALK: a lantern-lit safe circle drifts around the arena; outside it the dark burns (DPS after the grace)
function P.LanternWalk(d: number, now: number, lead: number, rand: () -> number, opts: any?): ({ any }, any)
	local lw = P.Config().Boss.Endgame.LanternWalk
	local radius = lw.Radius or 9
	local seconds = lw.Seconds or 8
	local speed = math.min(lw.Speed or 6, (Hazards.Config().MaxSafeSpeed or 11) - .5)
	local orbit = math.clamp(ARENA_HALF - radius - 3, 4, 14)
	local tele = math.max(lw.Grace or 1.2, P.MinTelegraph(0))
	local defs = generate(function()
		-- start near the fighters (their centre seen from the pit centre), then walk around
		local base = rand() * math.pi * 2
		local toward = opts and opts.Toward
		if typeof(toward) == "Vector3" then
			local off = toward - CENTER
			if V3(off.X, 0, off.Z).Magnitude > 1 then
				base = math.atan2(off.Z, off.X)
			end
		end
		local a0 = base + (rand() - .5) * math.rad(120)
		local sign = rand() < .5 and -1 or 1
		local w = speed / orbit
		local path = {}
		for s = 0, math.ceil(seconds) do
			local a = a0 + sign * w * s
			table.insert(path, { At = s, Center = CENTER + V3(math.cos(a) * orbit, 0, math.sin(a) * orbit) })
		end
		local shape = Hazards.Safe(path[1].Center, radius, RIM_HALF * 1.42 + 2, { Path = path })
		return { { Shape = shape, Telegraph = tele, ImpactAt = now + lead + tele, Damage = 0, DPS = lw.DPS or 7, Linger = seconds,
			Kind = "Lantern", Source = "Gravekeeper" } }
	end)
	return defs, info("LanternWalk", defs, now)
end

-- BONE RAIN: bones fall all over the pit (a share aimed at the fighters), impacts staggered
function P.BoneRain(d: number, now: number, lead: number, rand: () -> number, opts: any?): ({ any }, any)
	local br = P.Config().Boss.Endgame.BoneRain
	local n = P.Count(br.Count, d)
	local dmg = P.Damage(br.Damage, d)
	local tele = P.Telegraph(br.Telegraph or 1.4, d, dmg)
	local radius = br.Radius or 4
	local targets = (opts and opts.Targets) or {}
	local defs = generate(function()
		local out, placed = {}, {}
		local r = pit.Rim
		for i = 1, n do
			local pos = nil
			for _ = 1, 14 do
				local x, z
				if #targets > 0 and rand() < (br.Aimed or .4) then
					local t = targets[pick(rand, #targets)]
					x, z = t.X + (rand() - .5) * 6, t.Z + (rand() - .5) * 6
				else
					x, z = r.X0 + 3 + rand() * (r.X1 - r.X0 - 6), r.Z0 + 3 + rand() * (r.Z1 - r.Z0 - 6)
				end
				x, z = math.clamp(x, r.X0 + 2, r.X1 - 2), math.clamp(z, r.Z0 + 2, r.Z1 - 2)
				local ok = true
				for _, q in ipairs(placed) do
					if (V3(x, 0, z) - q).Magnitude < radius + 1.5 then
						ok = false
						break
					end
				end
				if ok then
					pos = V3(x, 0, z)
					break
				end
			end
			if pos then
				table.insert(placed, pos)
				table.insert(out, { Shape = P.Ground(pos, radius), Telegraph = tele, ImpactAt = now + lead + tele + (i - 1) * (br.Stagger or .18),
					Damage = dmg, Knock = { Power = br.Knock or 20, Up = 14 }, Kind = "BoneRain", Source = "Gravekeeper" })
			end
		end
		return out
	end)
	return defs, info("BoneRain", defs, now)
end

---------------------------------------------------------------------------------------------------------------------
-- FINALE (difficulty V)
---------------------------------------------------------------------------------------------------------------------
-- the Black Bell tolls: one shockwave ring (or an inner + an outer one), each with a safe gap; the disc under the bell
-- (Inner) is always safe
function P.Shockwave(now: number, lead: number, rand: () -> number, opts: any?): ({ any }, any)
	local b = P.Config().Finale.Bell
	local dmg = P.Damage(b.ShockwaveDamage or 14, 5)
	local tele = P.Telegraph(b.ShockwaveTelegraph or 1.5, 5, dmg)
	local gap = b.ShockwaveGap or 50
	local outer = RIM_HALF + 4
	local double = (opts and opts.Double) or rand() < (b.DoubleChance or .45)
	local defs = generate(function()
		local a1 = rand() * 360
		local out = {}
		local function ring(inner: number, outerR: number, angle: number, delay: number)
			table.insert(out, { Shape = Hazards.Ring(CENTER, inner, outerR, { { Angle = angle % 360, Width = gap } }), Telegraph = tele,
				ImpactAt = now + lead + tele + delay, Damage = dmg, Knock = { Power = 36, Up = 22 }, Kind = "Shockwave", Source = "Bell" })
		end
		if double then
			ring(6, 19, a1, 0)
			ring(17, outer, a1 + 90 + rand() * 90, .7)
		else
			ring(6, outer, a1, 0)
		end
		return out
	end)
	return defs, info("Shockwave", defs, now)
end

-- the Gravekeeper's spirit throws a volley of grave lines from one side of the rim through the fighters
function P.Volley(now: number, lead: number, rand: () -> number, opts: any?): ({ any }, any)
	local c = P.Config().Finale.Choir
	local dmg = P.Damage(c.VolleyDamage or 14, 5)
	local tele = P.Telegraph(c.VolleyTelegraph or 1.4, 5, dmg)
	local width = c.VolleyWidth or 5
	local targets = (opts and opts.Targets) or {}
	local defs = generate(function()
		local side = pick(rand, 4)
		local sideDir = ({ V3(0, 0, -1), V3(1, 0, 0), V3(0, 0, 1), V3(-1, 0, 0) })[side] -- N E S W (from the centre)
		local along = V3(-sideDir.Z, 0, sideDir.X)
		local n = 2 + (rand() < .4 and 1 or 0)
		local out = {}
		for i = 1, n do
			local from = CENTER + sideDir * (RIM_HALF + 2) + along * ((rand() - .5) * 30)
			local aim
			if #targets > 0 then
				local t = targets[pick(rand, #targets)]
				aim = V3(t.X, CENTER.Y, t.Z) + along * ((rand() - .5) * 8)
			else
				local x, z = inArena(CENTER.X + (rand() - .5) * 40, CENTER.Z + (rand() - .5) * 40, 2)
				aim = V3(x, CENTER.Y, z)
			end
			local dir = V3(aim.X - from.X, 0, aim.Z - from.Z)
			if dir.Magnitude < 4 or dir.Unit:Dot(-sideDir) < .35 then
				dir = -sideDir
			end
			dir = dir.Unit
			local f = V3(from.X, CENTER.Y, from.Z)
			table.insert(out, { Shape = Hazards.Line(f, f + dir * (RIM_HALF * 2 + 6), width), Telegraph = tele,
				ImpactAt = now + lead + tele + (i - 1) * .35, Damage = dmg, Knock = { Power = 30, Up = 16 }, Kind = "Volley", Source = "Spirit" })
		end
		return out
	end)
	return defs, info("Volley", defs, now)
end

function P.GhostBite(pos: Vector3, now: number, lead: number): any
	local c = P.Config().Finale.Choir
	local dmg = P.Damage(c.GhostBite or 8, 5)
	local tele = P.Telegraph(.9, 5, dmg)
	return { Shape = P.Ground(pos, c.GhostBiteRadius or 3.5), Telegraph = tele, ImpactAt = now + lead + tele, Damage = dmg,
		Knock = { Power = 22, Up = 10 }, Kind = "Bite", Source = "Ghost" }
end

-- THE LAST BARK on the beat grid: beatAt = server time of beat 0 of this pattern, beat = 60 / BPM. Every hazard
-- impacts exactly on a beat and is telegraphed for two beats. -> defs, beats
P.HoundPatterns = { "Circles", "Lines", "Waves", "SafeDance" }
function P.Hound(name: string, beatAt: number, beat: number, rand: () -> number, opts: any?): ({ any }, number)
	local h = P.Config().Finale.Hound
	local o = opts or {}
	local targets = o.Targets or {}
	local fighters = math.max(1, tonumber(o.Fighters) or #targets)
	local tele = math.max(2 * beat, P.MinTelegraph(0))
	local out = {}
	local function at(b: number): number
		return beatAt + b * beat
	end
	local function group(build: () -> { any })
		for _, d in ipairs(generate(build)) do
			table.insert(out, d)
		end
	end
	if name == "Circles" then
		local dmg = P.Damage(h.BurstDamage or 12, 5)
		local per = 2 + math.min(3, math.floor(fighters / 2)) + (o.Intensity or 0)
		for b = 2, 7 do
			group(function()
				local list, placed = {}, {}
				for i = 1, per do
					local x, z
					if i <= #targets and rand() < .7 then
						local t = targets[((b + i) % #targets) + 1]
						x, z = t.X + (rand() - .5) * 4, t.Z + (rand() - .5) * 4
					else
						x, z = CENTER.X + (rand() - .5) * 2 * (ARENA_HALF - 3), CENTER.Z + (rand() - .5) * 2 * (ARENA_HALF - 3)
					end
					x, z = inArena(x, z, 2)
					local p = V3(x, 0, z)
					local ok = true
					for _, q in ipairs(placed) do
						if (p - q).Magnitude < 7 then
							ok = false
						end
					end
					if ok then
						table.insert(placed, p)
						table.insert(list, { Shape = P.Ground(p, 5), Telegraph = math.max(tele, P.MinTelegraph(dmg)), ImpactAt = at(b), Damage = dmg,
							Knock = { Power = 24, Up = 14 }, Kind = "Bone", Source = "Hound" })
					end
				end
				return list
			end)
		end
		return out, 8
	elseif name == "Lines" then
		local dmg = P.Damage(h.LineDamage or 16, 5)
		for b = 2, 7 do
			group(function()
				local a = (b % 2 == 0) and 0 or math.pi / 2
				local dir = V3(math.cos(a), 0, math.sin(a))
				local perp = V3(-math.sin(a), 0, math.cos(a))
				local o1 = (rand() - .5) * 2 * (ARENA_HALF - 6)
				local o2 = o1 + (rand() < .5 and -1 or 1) * (16 + rand() * 8)
				if math.abs(o2) > ARENA_HALF then
					o2 = o1 - (o2 - o1)
				end
				local list = {}
				for _, off in ipairs({ o1, o2 }) do
					local c = CENTER + perp * off
					table.insert(list, { Shape = Hazards.Line(c - dir * (RIM_HALF + 4), c + dir * (RIM_HALF + 4), 6),
						Telegraph = math.max(tele, P.MinTelegraph(dmg)), ImpactAt = at(b), Damage = dmg, Knock = { Power = 28, Up = 16 }, Kind = "Line",
						Source = "Hound" })
				end
				return list
			end)
		end
		return out, 8
	elseif name == "Waves" then
		local dmg = P.Damage(h.RingDamage or 14, 5)
		local a0 = rand() * 360
		local step = (rand() < .5 and -1 or 1) * (25 + rand() * 20)
		for k = 0, 4 do
			group(function()
				local inner = 4 + 6 * k
				return { { Shape = Hazards.Ring(CENTER, inner, inner + 6, { { Angle = (a0 + k * step) % 360, Width = 70 } }),
					Telegraph = math.max(tele, P.MinTelegraph(dmg)), ImpactAt = at(2 + k), Damage = dmg, Knock = { Power = 26, Up = 16 }, Kind = "Wave",
					Source = "Hound" } }
			end)
		end
		return out, 8
	elseif name == "SafeDance" then
		local radius = h.SafeRadius or 8
		local speed = math.min(h.SafeSpeed or 9, (Hazards.Config().MaxSafeSpeed or 11) - .5)
		local hop = 2 * beat
		local beats = 10
		group(function()
			local start = CENTER
			if #targets > 0 then
				local t = targets[pick(rand, #targets)]
				local x, z = inArena(t.X, t.Z, radius + 2)
				start = V3(x, CENTER.Y, z)
			end
			local path = { { At = 0, Center = start } }
			local cur = start
			for i = 1, math.floor((beats - 2) / 2) do
				local a = rand() * math.pi * 2
				local dist = speed * hop * (.7 + rand() * .3)
				local x, z = inArena(cur.X + math.cos(a) * dist, cur.Z + math.sin(a) * dist, radius + 2)
				cur = V3(x, CENTER.Y, z)
				table.insert(path, { At = i * hop, Center = cur })
			end
			return { { Shape = Hazards.Safe(start, radius, RIM_HALF * 1.42 + 2, { Path = path }), Telegraph = tele, ImpactAt = at(2), Damage = 0,
				DPS = h.SafeDPS or 7, Linger = (beats - 2) * beat, Kind = "Safe", Source = "Hound" } }
		end)
		return out, beats
	end
	return out, 0
end

return P
