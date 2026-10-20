-- Hazard shapes of CHAPTER II combat (ReplicatedStorage.Halloween.Hazards, docs/halloween2/DESIGN.md §10.2). Pure: no
-- services, no instances; the server (ServerScriptService.Halloween.EventHP) tests players against these shapes and the
-- client (HalloweenClient.CombatFX) draws them, so both sides read exactly the same geometry.
--
-- SHAPES (Type field; every position is a world Vector3, angles are degrees in the XZ plane: 0 = +X, 90 = +Z)
--   Circle {Center, Radius}
--   Ring   {Center, Inner, Outer, Gaps = {{Angle, Width}}?}   a band; the gap sectors are safe
--   Line   {From, To, Width}                                   a flat-ended strip (the client sweeps it From -> To)
--   Cone   {Center, Dir (Vector3), Angle (full opening), Radius}
--   Safe   {Center, Radius, Outer?}                            INVERSE: everyone OUTSIDE the circle (inside Outer) is hit
--   Box    {CFrame, Size}                                      oriented box
--   every shape: Height? (vertical half band, default Hazards.Band = 10 studs around the shape's ground height),
--                Path? = {{At = seconds after ImpactAt, Center = Vector3}} (a moving shape: linear between the points)
-- HAZARD DEF (EventHP.Hazard(zoneId, def))
--   {Id, Shape, Telegraph (s), ImpactAt (server time), Damage, Knock? (number | {Power, Up}), Linger? (s after the
--    impact), DPS? (damage per second while lingering), Color? (Color3), Kind (attack name: colour + rules, e.g. "Gas"),
--    Source (who / what)}
-- API
--   Hazards.Circle/Ring/Line/Cone/Safe/Box(...) -> shape          constructors
--   Hazards.Contains(shape, pos, t?) -> bool                       is pos HIT (t = seconds after ImpactAt, moving shapes)
--   Hazards.At(shape, t) -> shape                                  the shape moved along its Path to time t
--   Hazards.Center(shape) -> Vector3                               a representative ground point (signals, raycasts)
--   Hazards.Extent(shape) -> number                                radius of a disc around Center covering the shape
--   Hazards.ShowAt(def, lead?) / EndAt(def) / Progress(def, now, showAt?) / Phase(def, now, showAt?)
--   Hazards.PathSpeed(shape) -> studs/s                            fastest Path segment
--   Hazards.Config() -> limits ; Hazards.SetConfig(tbl | nil)       fairness limits (defaults: Hazards.Defaults)
--   Hazards.Check(def, cfg?) -> ok, problems                       the fairness rules below (cfg overrides limits;
--                                                                  cfg.Trial = true uses TrialHitFrac)
--   Hazards.Sanitize(def, cfg?) -> fixedCopy, problems             makes a def fair (raises telegraphs, clamps damage,
--                                                                  slows paths, opens a ring gap)
--   Hazards.CheckPattern(defs, area {Center, Radius}, cfg?) -> ok, safeFraction   a wave leaves a safe spot
--   Hazards.Encode(def, showAt?) -> compact table ; Hazards.Decode(t) -> def      Signal "Hazard" payload
-- FAIRNESS (Hazards.Config()): every damaging attack is telegraphed (>= .9 s, >= 1.2 s at 25+ damage); no single hit above
-- 45% MaxHP (40% in trials); a moving shape moves at <= 11 studs/s; every Ring leaves a gap a dog can stand in (or a safe
-- inner disc) and every Ring / Line wave leaves a safe spot (CheckPattern).
-- Limits come from ReplicatedStorage.Halloween.Chapter2Config.Combat (MaxHP, Hazards = {MinTelegraph, HeavyTelegraph,
-- HeavyDamage, MaxHitFractionBoss, MaxHitFractionTrial, MaxSafeZoneSpeed, YBand}) when present, else the defaults below.
local root = script.Parent

local Hazards = {}

Hazards.Types = { "Circle", "Ring", "Line", "Cone", "Safe", "Box" }
Hazards.Band = 10
Hazards.Defaults = {
	MinTelegraph = .9,     -- seconds of warning for any damaging hazard
	HeavyTelegraph = 1.2,  -- ... and for a hit of HeavyDamage or more
	HeavyDamage = 25,
	MaxHP = 100,           -- the reference Event HP for the per-hit cap (H14's bonus HP is a bonus, not a budget)
	MaxHitFrac = .45,      -- no single hit above this share of MaxHP (Gravekeeper difficulty V)
	TrialHitFrac = .40,    -- ... in Bell trials (cfg.Trial = true)
	MaxSafeSpeed = 11,     -- studs per second, any moving shape
	MinGapStuds = 6,       -- a ring gap / safe inner disc at least this wide (a player is ~2-3 studs)
	PlayerRadius = 1.5,    -- clearance a safe sample point needs (CheckPattern)
	Band = 10,             -- vertical half band of a shape without Height
}

local limitsOverride: any = nil
local limitsCached: any = nil
local function resolveLimits(src: any): any
	local out = table.clone(Hazards.Defaults)
	if type(src) == "table" then
		for k, v in pairs(src) do
			if type(v) == "number" and out[k] ~= nil then
				out[k] = v
			end
		end
	end
	return out
end

-- the live limits (Chapter2Config.Combat mapped onto Hazards.Defaults)
function Hazards.Config(): any
	if limitsOverride then
		return limitsOverride
	end
	if not limitsCached then
		local flat = {}
		pcall(function()
			local inst = root:FindFirstChild("Chapter2Config")
			local m = inst and require(inst :: any)
			local combat = type(m) == "table" and (m.Combat or m.EventHP)
			if type(combat) ~= "table" then
				return
			end
			flat.MaxHP = combat.MaxHP
			local hz = type(combat.Hazards) == "table" and combat.Hazards or {}
			flat.MinTelegraph, flat.HeavyTelegraph, flat.HeavyDamage = hz.MinTelegraph, hz.HeavyTelegraph, hz.HeavyDamage
			flat.MaxHitFrac = hz.MaxHitFractionBoss or hz.MaxHitFrac
			flat.TrialHitFrac = hz.MaxHitFractionTrial or hz.TrialHitFrac
			flat.MaxSafeSpeed = hz.MaxSafeZoneSpeed or hz.MaxSafeSpeed
			flat.Band = hz.YBand or hz.Band
			flat.MinGapStuds = hz.MinGapStuds
		end)
		limitsCached = resolveLimits(flat)
	end
	return limitsCached
end
-- tests / Studio: limits over the defaults (nil = the real config again)
function Hazards.SetConfig(tbl: any?)
	limitsOverride = tbl and resolveLimits(tbl) or nil
	limitsCached = nil
end
-- (legacy name) the default limits table
Hazards.Limits = Hazards.Defaults

local V3 = Vector3.new
local CODES = { Circle = "C", Ring = "R", Line = "L", Cone = "K", Safe = "S", Box = "B" }
local TYPES = { C = "Circle", R = "Ring", L = "Line", K = "Cone", S = "Safe", B = "Box" }

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function typeOf(shape: any): string?
	if type(shape) ~= "table" then
		return nil
	end
	local t = shape.Type or shape.Kind
	return CODES[t] and t or nil
end
Hazards.TypeOf = typeOf

local function merged(cfg: any): any
	local out = table.clone(Hazards.Config())
	if type(cfg) == "table" then
		for k, v in pairs(cfg) do
			out[k] = v
		end
	end
	return out
end
Hazards.Merged = merged

---------------------------------------------------------------------------------------------------------------------
-- constructors
---------------------------------------------------------------------------------------------------------------------
function Hazards.Circle(center: Vector3, radius: number, opts: any?)
	local s = { Type = "Circle", Center = center, Radius = radius }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

function Hazards.Ring(center: Vector3, inner: number, outer: number, gaps: { any }?, opts: any?)
	local s = { Type = "Ring", Center = center, Inner = inner, Outer = outer, Gaps = gaps }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

function Hazards.Line(from: Vector3, to: Vector3, width: number, opts: any?)
	local s = { Type = "Line", From = from, To = to, Width = width }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

function Hazards.Cone(center: Vector3, dir: Vector3, angle: number, radius: number, opts: any?)
	local s = { Type = "Cone", Center = center, Dir = dir, Angle = angle, Radius = radius }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

function Hazards.Safe(center: Vector3, radius: number, outer: number?, opts: any?)
	local s = { Type = "Safe", Center = center, Radius = radius, Outer = outer }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

function Hazards.Box(cf: CFrame, size: Vector3, opts: any?)
	local s = { Type = "Box", CFrame = cf, Size = size }
	if type(opts) == "table" then
		s.Height, s.Path = opts.Height, opts.Path
	end
	return s
end

---------------------------------------------------------------------------------------------------------------------
-- geometry
---------------------------------------------------------------------------------------------------------------------
-- a representative ground point of the shape (the path start for moving shapes)
function Hazards.Center(shape: any): Vector3
	local t = typeOf(shape)
	if t == "Line" then
		return (shape.From + shape.To) / 2
	elseif t == "Box" then
		return shape.CFrame.Position
	end
	return shape.Center or Vector3.zero
end

-- radius of a disc around Center that covers the whole shape (recipient range, culling, CheckPattern)
function Hazards.Extent(shape: any): number
	local t = typeOf(shape)
	if t == "Circle" or t == "Cone" then
		return num(shape.Radius, 0)
	elseif t == "Ring" then
		return num(shape.Outer, 0)
	elseif t == "Safe" then
		return num(shape.Outer, num(shape.Radius, 0) + 40)
	elseif t == "Line" then
		return flat(shape.To - shape.From).Magnitude / 2 + num(shape.Width, 0) / 2
	elseif t == "Box" then
		local s = shape.Size
		return math.sqrt(s.X * s.X + s.Z * s.Z) / 2
	end
	return 0
end

local function pathPoints(shape: any): { any }?
	local p = shape.Path
	if type(p) ~= "table" or #p == 0 then
		return nil
	end
	return p
end

-- centre of a moving shape at t seconds after its impact (nil when the shape does not move)
function Hazards.PathCenter(shape: any, t: number): Vector3?
	local p = pathPoints(shape)
	if not p then
		return nil
	end
	if t <= num(p[1].At, 0) then
		return p[1].Center
	end
	for i = 2, #p do
		local a, b = p[i - 1], p[i]
		local ta, tb = num(a.At, 0), num(b.At, 0)
		if t <= tb then
			local k = tb > ta and (t - ta) / (tb - ta) or 1
			return a.Center:Lerp(b.Center, math.clamp(k, 0, 1))
		end
	end
	return p[#p].Center
end

-- the shape moved along its Path to time t (seconds after ImpactAt); the same table when it does not move
function Hazards.At(shape: any, t: number?): any
	local p = pathPoints(shape)
	if not p or t == nil then
		return shape
	end
	local c = Hazards.PathCenter(shape, t) :: Vector3
	local out = table.clone(shape)
	local ty = typeOf(shape)
	if ty == "Line" then
		local delta = c - p[1].Center
		out.From, out.To = shape.From + delta, shape.To + delta
	elseif ty == "Box" then
		out.CFrame = shape.CFrame + (c - p[1].Center)
	else
		out.Center = c
	end
	out.Path = nil
	return out
end

local function angleOf(v: Vector3): number
	return math.deg(math.atan2(v.Z, v.X)) % 360
end
Hazards.AngleOf = angleOf

local function angDiff(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return math.abs(d)
end
Hazards.AngleDiff = angDiff

local function inGap(shape: any, angle: number): boolean
	for _, g in ipairs(type(shape.Gaps) == "table" and shape.Gaps or {}) do
		if angDiff(angle, num(g.Angle or g[1], 0)) <= num(g.Width or g[2], 0) / 2 then
			return true
		end
	end
	return false
end
Hazards.InGap = inGap

-- is `pos` hit by the shape (t: seconds after the impact, for moving shapes)
function Hazards.Contains(shape: any, pos: Vector3, t: number?): boolean
	local ty = typeOf(shape)
	if not ty or typeof(pos) ~= "Vector3" then
		return false
	end
	if t ~= nil then
		shape = Hazards.At(shape, t)
	end
	local band = num(shape.Height, Hazards.Config().Band)
	if ty == "Box" then
		local cf: CFrame = shape.CFrame
		local size: Vector3 = shape.Size
		local l = cf:PointToObjectSpace(pos)
		return math.abs(l.X) <= size.X / 2 and math.abs(l.Z) <= size.Z / 2 and math.abs(l.Y) <= math.max(size.Y / 2, band)
	end
	if ty == "Line" then
		local a, b = shape.From, shape.To
		local v = flat(b - a)
		local len2 = v.X * v.X + v.Z * v.Z
		if len2 < 1e-6 then
			return false
		end
		local w = flat(pos - a)
		local k = (w.X * v.X + w.Z * v.Z) / len2
		if k < 0 or k > 1 then
			return false
		end
		local groundY = a.Y + (b.Y - a.Y) * k
		if math.abs(pos.Y - groundY) > band then
			return false
		end
		local perp = (w - v * k).Magnitude
		return perp <= num(shape.Width, 0) / 2
	end
	local c: Vector3 = shape.Center
	if math.abs(pos.Y - c.Y) > band then
		return false
	end
	local d = flat(pos - c)
	local r = d.Magnitude
	if ty == "Circle" then
		return r <= num(shape.Radius, 0)
	elseif ty == "Ring" then
		if r < num(shape.Inner, 0) or r > num(shape.Outer, 0) then
			return false
		end
		return not inGap(shape, angleOf(d))
	elseif ty == "Cone" then
		if r > num(shape.Radius, 0) then
			return false
		end
		if r < .5 then
			return true
		end
		local dir = typeof(shape.Dir) == "Vector3" and flat(shape.Dir) or V3(0, 0, -1)
		if dir.Magnitude < 1e-3 then
			return true
		end
		return angDiff(angleOf(d), angleOf(dir)) <= num(shape.Angle, 0) / 2
	elseif ty == "Safe" then
		if r <= num(shape.Radius, 0) then
			return false
		end
		local outer = tonumber(shape.Outer)
		return outer == nil or r <= outer
	end
	return false
end

-- the fastest segment of a Path in studs per second (0 = still)
function Hazards.PathSpeed(shape: any): number
	local p = pathPoints(shape)
	if not p then
		return 0
	end
	local best = 0
	for i = 2, #p do
		local dt = num(p[i].At, 0) - num(p[i - 1].At, 0)
		local dist = flat(p[i].Center - p[i - 1].Center).Magnitude
		if dist > 1e-3 then
			best = math.max(best, dt > 1e-3 and dist / dt or math.huge)
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------
-- timing (server time)
---------------------------------------------------------------------------------------------------------------------
function Hazards.ShowAt(def: any, lead: number?): number
	return num(def.ImpactAt, 0) - num(def.Telegraph, 0) - (lead or 0)
end

function Hazards.EndAt(def: any): number
	return num(def.ImpactAt, 0) + math.max(0, num(def.Linger, 0))
end

-- 0 at ShowAt .. 1 at ImpactAt (the telegraph fill)
function Hazards.Progress(def: any, now: number, showAt: number?): number
	local s = showAt or Hazards.ShowAt(def)
	local total = math.max(.05, num(def.ImpactAt, 0) - s)
	return math.clamp((now - s) / total, 0, 1)
end

-- "Waiting" (before ShowAt) | "Telegraph" | "Linger" | "Done"
function Hazards.Phase(def: any, now: number, showAt: number?): string
	local s = showAt or Hazards.ShowAt(def)
	if now < s then
		return "Waiting"
	elseif now < num(def.ImpactAt, 0) then
		return "Telegraph"
	elseif now < Hazards.EndAt(def) then
		return "Linger"
	end
	return "Done"
end

---------------------------------------------------------------------------------------------------------------------
-- fairness
---------------------------------------------------------------------------------------------------------------------
local function shapeProblems(shape: any, out: { string })
	local ty = typeOf(shape)
	if not ty then
		table.insert(out, "unknown shape")
		return
	end
	local function pos(v: any, name: string)
		if typeof(v) ~= "Vector3" then
			table.insert(out, ty .. ": " .. name .. " is not a Vector3")
		end
	end
	local function positive(v: any, name: string)
		if not (tonumber(v) and tonumber(v) > 0) then
			table.insert(out, ty .. ": " .. name .. " must be > 0")
		end
	end
	if ty == "Circle" then
		pos(shape.Center, "Center")
		positive(shape.Radius, "Radius")
	elseif ty == "Ring" then
		pos(shape.Center, "Center")
		positive(shape.Outer, "Outer")
		if num(shape.Inner, -1) < 0 or num(shape.Inner, 0) >= num(shape.Outer, 0) then
			table.insert(out, "Ring: needs 0 <= Inner < Outer")
		end
	elseif ty == "Line" then
		pos(shape.From, "From")
		pos(shape.To, "To")
		positive(shape.Width, "Width")
		if typeof(shape.From) == "Vector3" and typeof(shape.To) == "Vector3" and flat(shape.To - shape.From).Magnitude < .5 then
			table.insert(out, "Line: From and To are the same point")
		end
	elseif ty == "Cone" then
		pos(shape.Center, "Center")
		positive(shape.Radius, "Radius")
		if not (num(shape.Angle, 0) > 0 and num(shape.Angle, 0) <= 360) then
			table.insert(out, "Cone: Angle must be in (0, 360]")
		end
	elseif ty == "Safe" then
		pos(shape.Center, "Center")
		positive(shape.Radius, "Radius")
		if shape.Outer ~= nil and num(shape.Outer, 0) <= num(shape.Radius, 0) then
			table.insert(out, "Safe: Outer must be larger than Radius")
		end
	elseif ty == "Box" then
		if typeof(shape.CFrame) ~= "CFrame" then
			table.insert(out, "Box: CFrame is not a CFrame")
		end
		if typeof(shape.Size) ~= "Vector3" or shape.Size.X <= 0 or shape.Size.Z <= 0 then
			table.insert(out, "Box: Size must be a positive Vector3")
		end
	end
end

-- the widest gap of a ring in studs (arc length at the middle of the band)
function Hazards.GapStuds(shape: any): number
	local mid = (num(shape.Inner, 0) + num(shape.Outer, 0)) / 2
	local best = 0
	for _, g in ipairs(type(shape.Gaps) == "table" and shape.Gaps or {}) do
		best = math.max(best, math.rad(num(g.Width or g[2], 0)) * mid)
	end
	return best
end

-- the hit cap for this def: MaxHP x (TrialHitFrac in trials, else MaxHitFrac)
function Hazards.HitCap(cfg: any?): number
	local c = merged(cfg)
	local frac = c.Trial and c.TrialHitFrac or c.MaxHitFrac
	return c.MaxHP * frac
end

function Hazards.Check(def: any, cfg: any?): (boolean, { string })
	local c = merged(cfg)
	local out = {}
	if type(def) ~= "table" then
		return false, { "def is not a table" }
	end
	shapeProblems(def.Shape, out)
	local dmg = num(def.Damage, 0)
	local dps = num(def.DPS, 0)
	local tele = num(def.Telegraph, 0)
	if dmg < 0 or dps < 0 then
		table.insert(out, "negative damage")
	end
	if dmg > 0 or (dps > 0 and num(def.Linger, 0) > 0) then
		local need = dmg >= c.HeavyDamage and c.HeavyTelegraph or c.MinTelegraph
		if tele + 1e-6 < need then
			table.insert(out, string.format("telegraph %.2f s < %.2f s", tele, need))
		end
	end
	local cap = Hazards.HitCap(c)
	if dmg > cap + 1e-6 then
		table.insert(out, string.format("damage %g above the per-hit cap %g", dmg, cap))
	end
	if dps > cap + 1e-6 then
		table.insert(out, string.format("lingering %g damage per second above the per-hit cap %g", dps, cap))
	end
	if typeOf(def.Shape) and pathPoints(def.Shape) then
		local speed = Hazards.PathSpeed(def.Shape)
		if speed > c.MaxSafeSpeed + 1e-6 then
			table.insert(out, string.format("moves at %.1f studs/s > %g", speed, c.MaxSafeSpeed))
		end
	end
	if typeOf(def.Shape) == "Ring" and (dmg > 0 or dps > 0) then
		local inner = num(def.Shape.Inner, 0)
		if Hazards.GapStuds(def.Shape) + 1e-6 < c.MinGapStuds and inner * 2 < c.MinGapStuds then
			table.insert(out, "ring without a safe gap")
		end
	end
	return #out == 0, out
end

-- a fair copy of def (never rejects an attack: the encounter keeps its rhythm, the numbers bend)
function Hazards.Sanitize(def: any, cfg: any?): (any, { string })
	local c = merged(cfg)
	local ok, problems = Hazards.Check(def, c)
	if ok then
		return def, problems
	end
	local out = table.clone(def)
	out.Shape = type(def.Shape) == "table" and table.clone(def.Shape) or def.Shape
	local cap = Hazards.HitCap(c)
	local dmg = math.clamp(num(out.Damage, 0), 0, cap)
	out.Damage = dmg
	out.DPS = math.clamp(num(out.DPS, 0), 0, cap)
	local need = dmg >= c.HeavyDamage and c.HeavyTelegraph or c.MinTelegraph
	if (dmg > 0 or out.DPS > 0) and num(out.Telegraph, 0) < need then
		out.Telegraph = need
	end
	local shape = out.Shape
	if typeOf(shape) and pathPoints(shape) then
		local speed = Hazards.PathSpeed(shape)
		if speed > c.MaxSafeSpeed then
			local k = speed / c.MaxSafeSpeed
			local path = {}
			for i, p in ipairs(shape.Path) do
				path[i] = { At = num(p.At, 0) * k, Center = p.Center }
			end
			shape.Path = path
			if out.Linger then
				out.Linger = num(out.Linger, 0) * k
			end
		end
	end
	if typeOf(shape) == "Ring" and Hazards.GapStuds(shape) < c.MinGapStuds and num(shape.Inner, 0) * 2 < c.MinGapStuds then
		local mid = math.max(1, (num(shape.Inner, 0) + num(shape.Outer, 0)) / 2)
		local width = math.deg((c.MinGapStuds + 1) / mid)
		local gaps = type(shape.Gaps) == "table" and table.clone(shape.Gaps) or {}
		-- a deterministic angle per hazard id (no RNG in a pure module)
		local seed = tonumber(out.Id) or 0
		table.insert(gaps, { Angle = (seed * 137.508) % 360, Width = math.min(120, width) })
		shape.Gaps = gaps
	end
	return out, problems
end

-- does a wave of hazards (all impacting together) leave somewhere to stand inside `area`? Sampled on a polar grid;
-- a sample is safe when it and four points PlayerRadius around it are hit by none of the defs.
function Hazards.CheckPattern(defs: { any }, area: any, cfg: any?): (boolean, number)
	local c = merged(cfg)
	local center: Vector3 = area.Center
	local radius = num(area.Radius, 20)
	local step = math.max(1, num(area.Step, 2))
	local pr = c.PlayerRadius
	local offsets = { Vector3.zero, V3(pr, 0, 0), V3(-pr, 0, 0), V3(0, 0, pr), V3(0, 0, -pr) }
	local total, safe = 0, 0
	local rings = math.max(1, math.floor(radius / step))
	for ri = 0, rings do
		local r = radius * ri / rings
		local n = ri == 0 and 1 or math.max(6, math.floor(2 * math.pi * r / step))
		for i = 1, n do
			local a = (i - 1) / n * math.pi * 2
			local p = center + V3(math.cos(a) * r, 3, math.sin(a) * r)
			total += 1
			local hit = false
			for _, def in ipairs(defs) do
				local damaging = num(def.Damage, 0) > 0 or num(def.DPS, 0) > 0
				if damaging then
					for _, o in ipairs(offsets) do
						if Hazards.Contains(def.Shape, p + o, 0) then
							hit = true
							break
						end
					end
				end
				if hit then
					break
				end
			end
			if not hit then
				safe += 1
			end
		end
	end
	local frac = total > 0 and safe / total or 0
	return safe > 0, frac
end

---------------------------------------------------------------------------------------------------------------------
-- compact serialization (Signal "Hazard"): short keys, gaps / path flattened. Vector3 / CFrame / Color3 travel natively.
---------------------------------------------------------------------------------------------------------------------
local function r3(x: any): number?
	local n = tonumber(x)
	if n == nil then
		return nil
	end
	return math.floor(n * 1000 + .5) / 1000
end

function Hazards.Encode(def: any, showAt: number?): { [string]: any }
	local s = def.Shape or {}
	local ty = typeOf(s)
	local t: { [string]: any } = {
		I = def.Id, T = ty and CODES[ty] or "C", F = r3(def.Telegraph), M = def.ImpactAt, S = showAt or Hazards.ShowAt(def),
		N = r3(def.Damage), L = r3(def.Linger), Y = r3(def.DPS), K = def.Kind, O = type(def.Source) == "string" and def.Source or nil,
		C = typeof(def.Color) == "Color3" and def.Color or nil, H = r3(s.Height),
	}
	if ty == "Line" then
		t.P, t.Q, t.R = s.From, s.To, r3(s.Width)
	elseif ty == "Box" then
		t.X, t.Z = s.CFrame, s.Size
	else
		t.P = s.Center
		if ty == "Ring" then
			t.R, t.R2 = r3(s.Inner), r3(s.Outer)
			if type(s.Gaps) == "table" and #s.Gaps > 0 then
				local g = {}
				for _, gap in ipairs(s.Gaps) do
					table.insert(g, r3(gap.Angle or gap[1]))
					table.insert(g, r3(gap.Width or gap[2]))
				end
				t.G = g
			end
		elseif ty == "Cone" then
			t.R, t.A, t.D = r3(s.Radius), r3(s.Angle), s.Dir
		elseif ty == "Safe" then
			t.R, t.R2 = r3(s.Radius), r3(s.Outer)
		else
			t.R = r3(s.Radius)
		end
	end
	local path = pathPoints(s)
	if path then
		local w = {}
		for _, p in ipairs(path) do
			table.insert(w, r3(p.At))
			table.insert(w, p.Center)
		end
		t.W = w
	end
	if type(def.Knock) == "number" or type(def.Knock) == "table" then
		t.B = true -- knocks back (the client braces the drawing; the velocity itself comes with the hit)
	end
	return t
end

function Hazards.Decode(t: any): any
	if type(t) ~= "table" then
		return nil
	end
	local ty = TYPES[t.T or ""] or "Circle"
	local shape: { [string]: any } = { Type = ty, Height = tonumber(t.H) }
	if ty == "Line" then
		shape.From, shape.To, shape.Width = t.P, t.Q, tonumber(t.R)
	elseif ty == "Box" then
		shape.CFrame, shape.Size = t.X, t.Z
	else
		shape.Center = t.P
		if ty == "Ring" then
			shape.Inner, shape.Outer = tonumber(t.R), tonumber(t.R2)
			if type(t.G) == "table" then
				local gaps = {}
				for i = 1, #t.G - 1, 2 do
					table.insert(gaps, { Angle = tonumber(t.G[i]) or 0, Width = tonumber(t.G[i + 1]) or 0 })
				end
				shape.Gaps = gaps
			end
		elseif ty == "Cone" then
			shape.Radius, shape.Angle, shape.Dir = tonumber(t.R), tonumber(t.A), t.D
		elseif ty == "Safe" then
			shape.Radius, shape.Outer = tonumber(t.R), tonumber(t.R2)
		else
			shape.Radius = tonumber(t.R)
		end
	end
	if type(t.W) == "table" then
		local path = {}
		for i = 1, #t.W - 1, 2 do
			table.insert(path, { At = tonumber(t.W[i]) or 0, Center = t.W[i + 1] })
		end
		shape.Path = path
	end
	return {
		Id = t.I, Shape = shape, Telegraph = tonumber(t.F) or 0, ImpactAt = tonumber(t.M) or 0, ShowAt = tonumber(t.S),
		Damage = tonumber(t.N) or 0, Linger = tonumber(t.L), DPS = tonumber(t.Y), Kind = t.K, Source = t.O, Color = t.C,
		Knock = t.B == true or nil,
	}
end

return Hazards
