-- HALLOWEEN CALENDAR — pure date / stage rules (ReplicatedStorage.Halloween.CalendarRules). docs/halloween2/DESIGN.md §13.
-- Requires nothing (the config is passed in), so Lune tests run it as is (tests/calendar.luau). All times are UTC unix
-- seconds: the server passes os.time(), clients Shared.Now(). No os.date anywhere (it depends on the host's time zone).
--   UnixFromDate(y, m, d, h?, mi?, s?)  calendar date (UTC) -> unix seconds (Howard Hinnant's days-from-civil)
--   Stage(now, cfg) -> 0..8             0 before D-7 (and after cfg.Until), 1 at D-7 00:00 … 7 at D-1, 8 from the target
--   DaysLeft(now, cfg) -> int >= 0      whole days to the target, rounded up (0 on and after the target)
--   NextChange(now, cfg) -> unix?       the next moment Stage changes (nil once nothing changes any more)
--   StageParams(stage, cfg) -> table    cumulative per-stage visuals (cfg.Base, then Stages[1..stage] in order)
--   Effective(now, cfg, force?) -> stage, forced   a valid force (0..8) wins over the date (Studio / debug only)
--   Hash(text) -> 0..1                  deterministic string hash (stable per-part order on every client)
local R = {}

local DAY = 86400

-- days since 1970-01-01 of a proleptic Gregorian date (Hinnant, "chrono-Compatible Low-Level Date Algorithms")
function R.DaysFromCivil(y: number, m: number, d: number): number
	y = math.floor(y)
	m = math.floor(m)
	d = math.floor(d)
	if m <= 2 then
		y -= 1
	end
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400 -- [0, 399]
	local mp = (m + 9) % 12 -- March = 0
	local doy = (153 * mp + 2) // 5 + d - 1 -- [0, 365]
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy -- [0, 146096]
	return era * 146097 + doe - 719468
end

-- inverse (for tests / labels): days since the epoch -> y, m, d
function R.CivilFromDays(z: number): (number, number, number)
	z = math.floor(z) + 719468
	local era = (z >= 0 and z or z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

function R.UnixFromDate(y: number, m: number, d: number, h: number?, mi: number?, s: number?): number
	return R.DaysFromCivil(y, m, d) * DAY + (h or 0) * 3600 + (mi or 0) * 60 + (s or 0)
end

local function dateOf(t: any): number?
	if type(t) ~= "table" or type(t.Year) ~= "number" or type(t.Month) ~= "number" or type(t.Day) ~= "number" then
		return nil
	end
	return R.UnixFromDate(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second)
end

function R.Target(cfg): number
	return assert(dateOf(cfg.Target), "HalloweenCalendarConfig.Target is not a date")
end

function R.Until(cfg): number?
	return dateOf(cfg.Until)
end

local function maxStage(cfg): number
	return #cfg.Stages
end

-- the stage of a moment: stage k starts cfg.Stages[k].From days before the target (From = 0: at the target)
function R.Stage(now: number, cfg): number
	local target = R.Target(cfg)
	local stop = R.Until(cfg)
	if stop and now >= stop then
		return 0
	end
	local stage = 0
	for k = 1, maxStage(cfg) do
		local from = cfg.Stages[k].From or (maxStage(cfg) - k)
		if now >= target - from * DAY then
			stage = k
		end
	end
	return stage
end

function R.DaysLeft(now: number, cfg): number
	local left = R.Target(cfg) - now
	if left <= 0 then
		return 0
	end
	return math.ceil(left / DAY)
end

-- the next moment the stage changes after `now` (a stage start, or cfg.Until); nil when nothing changes any more
function R.NextChange(now: number, cfg): number?
	local target = R.Target(cfg)
	local best = nil
	local function consider(t: number?)
		if t and t > now and (best == nil or t < best) then
			best = t
		end
	end
	for k = 1, maxStage(cfg) do
		consider(target - (cfg.Stages[k].From or (maxStage(cfg) - k)) * DAY)
	end
	consider(R.Until(cfg))
	return best
end

-- a valid forced stage (integer 0..max) wins; anything else is ignored
function R.Effective(now: number, cfg, force: any?): (number, boolean)
	if type(force) == "number" and force == force and force >= 0 and force <= maxStage(cfg) then
		return math.floor(force), true
	end
	return R.Stage(now, cfg), false
end

-- the numeric visual parameters of a stage: cfg.Base, then every stage up to `stage` overrides the keys it lists
local META = { Folder = true, From = true, Label = true, Name = true, Toast = true }
function R.StageParams(stage: number, cfg): { [string]: number }
	local out = {}
	for k, v in pairs(cfg.Base) do
		out[k] = v
	end
	stage = math.clamp(math.floor(tonumber(stage) or 0), 0, maxStage(cfg))
	for i = 1, stage do
		for k, v in pairs(cfg.Stages[i]) do
			if not META[k] and type(v) == "number" then
				out[k] = v
			end
		end
	end
	out.Stage = stage
	return out
end

-- per-parameter blend of two parameter tables (client glide between stages)
function R.Blend(a: { [string]: number }, b: { [string]: number }, t: number): { [string]: number }
	t = math.clamp(t, 0, 1)
	local out = {}
	for k, v in pairs(b) do
		local from = a[k]
		out[k] = type(from) == "number" and from + (v - from) * t or v
	end
	return out
end

-- a * c mod 2^32 for 32-bit a, c, exact in doubles (split a into 16-bit halves)
local function mul32(a: number, c: number): number
	local hi, lo = a // 65536, a % 65536
	return (lo * c + ((hi * (c % 65536)) % 65536) * 65536) % 4294967296
end

-- FNV-1a over the bytes + a murmur3 finaliser -> [0, 1): the same on every machine (no math.random, no tostring of
-- tables), well spread even for names that differ in one character
function R.Hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = mul32(bit32.bxor(h, string.byte(text, i)), 16777619)
	end
	h = bit32.bxor(h, h // 65536)
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, h // 8192)
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, h // 65536)
	return h / 4294967296
end

-- the stage's display label / name / toast in English or Russian (nil for stage 0)
function R.Text(stage: number, cfg, field: string, russian: boolean?): string?
	local row = cfg.Stages[stage]
	local pair = row and row[field]
	if type(pair) ~= "table" then
		return nil
	end
	return (russian and pair[2]) or pair[1]
end

return R
