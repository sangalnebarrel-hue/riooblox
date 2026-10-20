-- CHAPTER I · THE DEAD YARD rebalance rules (ReplicatedStorage.Halloween.Chapter1Rules; pure: requires nothing, every
-- function takes the Halloween Config table, so Lune tests run it as is). docs/halloween2/DESIGN.md §12,
-- docs/halloween2/CHAPTER1_BALANCE.md. Used by SSS.Halloween.Core / Actions / Exorcism, Economy.EventBlocks and
-- Shared.BrewSeconds; the numbers live in Config.Cauldron, Config.Candy and Config.Rebalance.
--   R.Day(now) -> UTC day number
--   R.TricksToday(c, now) -> n            TRICKs played in this UTC day (h.Cauldron.TricksToday = {Day, N}; another day,
--                                         a missing or a broken value = 0)
--   R.TrickPrice(c, now, cfg) -> price    "the cauldron grows hungry": Cauldron.TrickCost x (1 + Step)^n, rounded to
--                                         Round, at most Max (Config.Rebalance.TrickEscalation); n = R.TricksToday, so the
--                                         price falls back to the base at UTC midnight
--   R.PriceAt(n, cfg) -> price            the price of the (n + 1)-th TRICK of a day
--   R.TrickPrices(cfg, count) -> {price}  the day's price ladder (UI / docs)
--   R.NoteTrick(c, now) -> n              records one TRICK in c.TricksToday (heals a bad / old value); today's count
--   R.BrewReadyAt(startedAt, cfg) -> unix late-starter catch-up: min(StartedAt + Cauldron.BrewSeconds,
--                                         Rebalance.BrewDeadline.At), never sooner than StartedAt + MinSeconds (1 day);
--                                         0 when the brew has not started
--   R.BrewSeconds(startedAt?, cfg) -> s   length of that brew (nil / 0 startedAt: the full Cauldron.BrewSeconds)
--   R.MinuteCap(used, n, cap) -> allowed, used     the per-minute candy cap, applied to the BASE amount (before the
--                                         curse / rush / Blood Moon multipliers, so those keep their full value)
--   R.Earned(source, opts?, cfg) -> bool  does this candy count as earned (EarnCandy quest)? Fixed payouts (opts.NoMult:
--                                         quest claims, reward rows, conversions, debug) and Config.Candy.Unearned sources
--                                         never do; opts.Earned overrides
--   R.RecentlyActive(lastAt, now, window) -> bool   lastAt within the last `window` seconds (same clock as now)
--   R.DecorateView(view, h, now, cfg, brewSeconds?) -> view
--                                         adds Cauldron.TrickPrice / TricksToday / TrickBase / TrickMax and the catch-up
--                                         ReadyAt to a Features.Halloween view (Core / EventBlocks push it to the client)
local R = {}

local DAY = 86400

local function n0(v: any): number
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

local function escalation(cfg: any): any
	local rb = type(cfg) == "table" and cfg.Rebalance
	return type(rb) == "table" and type(rb.TrickEscalation) == "table" and rb.TrickEscalation or {}
end

local function base(cfg: any): number
	local c = type(cfg) == "table" and cfg.Cauldron
	return math.max(0, n0(type(c) == "table" and c.TrickCost or 0))
end

function R.Day(now: number): number
	return math.floor(n0(now) / DAY)
end

function R.TricksToday(c: any, now: number): number
	local t = type(c) == "table" and c.TricksToday
	if type(t) ~= "table" or n0(t.Day) ~= R.Day(now) then
		return 0
	end
	return math.max(0, math.floor(n0(t.N)))
end

function R.PriceAt(n: number, cfg: any): number
	local b = base(cfg)
	local e = escalation(cfg)
	local step = math.max(0, n0(e.Step))
	local round = math.max(1, n0(e.Round))
	local maxPrice = n0(e.Max) > 0 and n0(e.Max) or math.huge
	n = math.max(0, math.floor(n0(n)))
	local raw = e.Compound == false and b * (1 + step * n) or b * (1 + step) ^ n
	local price = math.floor(raw / round + .5) * round
	return math.max(1, math.floor(math.min(price, maxPrice)))
end

function R.TrickPrice(c: any, now: number, cfg: any): number
	return R.PriceAt(R.TricksToday(c, now), cfg)
end

function R.TrickPrices(cfg: any, count: number): { number }
	local out = {}
	for i = 1, math.max(0, math.floor(n0(count))) do
		out[i] = R.PriceAt(i - 1, cfg)
	end
	return out
end

function R.NoteTrick(c: any, now: number): number
	local n = R.TricksToday(c, now) + 1
	c.TricksToday = { Day = R.Day(now), N = n }
	return n
end

function R.BrewReadyAt(startedAt: number, cfg: any): number
	startedAt = math.floor(n0(startedAt))
	if startedAt <= 0 then
		return 0
	end
	local c = type(cfg) == "table" and cfg.Cauldron or {}
	local full = n0(c.BrewSeconds) > 0 and n0(c.BrewSeconds) or 7 * DAY
	local rb = type(cfg) == "table" and cfg.Rebalance
	local d = type(rb) == "table" and rb.BrewDeadline
	local ready = startedAt + full
	if type(d) == "table" and n0(d.At) > 0 then
		local minSeconds = math.min(full, math.max(0, n0(d.MinSeconds)))
		ready = math.max(math.min(ready, math.floor(n0(d.At))), startedAt + minSeconds)
	end
	return ready
end

function R.BrewSeconds(startedAt: number?, cfg: any): number
	local c = type(cfg) == "table" and cfg.Cauldron or {}
	local full = n0(c.BrewSeconds) > 0 and n0(c.BrewSeconds) or 7 * DAY
	if n0(startedAt) <= 0 then
		return full
	end
	return R.BrewReadyAt(startedAt :: number, cfg) - math.floor(n0(startedAt))
end

function R.MinuteCap(used: number, n: number, cap: number): (number, number)
	used = math.max(0, n0(used))
	n = math.max(0, n0(n))
	local allowed = math.clamp(n, 0, math.max(0, n0(cap) - used))
	return allowed, used + allowed
end

function R.Earned(source: string?, opts: { [string]: any }?, cfg: any): boolean
	if type(opts) == "table" then
		if opts.Earned ~= nil then
			return opts.Earned == true
		end
		if opts.NoMult then
			return false
		end
	end
	local candy = type(cfg) == "table" and cfg.Candy
	local list = type(candy) == "table" and candy.Unearned
	return not (type(list) == "table" and source ~= nil and list[source] == true)
end

function R.RecentlyActive(lastAt: number?, now: number, window: number): boolean
	local at = tonumber(lastAt)
	return at ~= nil and at == at and n0(now) - at <= math.max(0, n0(window))
end

function R.DecorateView(view: any, h: any, now: number, cfg: any, brewSeconds: number?): any
	if type(view) ~= "table" or type(view.Cauldron) ~= "table" or type(h) ~= "table" then
		return view
	end
	local c = type(h.Cauldron) == "table" and h.Cauldron or {}
	local vc = view.Cauldron
	local e = escalation(cfg)
	vc.TrickPrice = R.TrickPrice(c, now, cfg)
	vc.TricksToday = R.TricksToday(c, now)
	vc.TrickBase = R.PriceAt(0, cfg)
	vc.TrickMax = n0(e.Max) > 0 and math.floor(n0(e.Max)) or nil
	local started = math.floor(n0(c.StartedAt))
	if started > 0 then
		vc.ReadyAt = started + (tonumber(brewSeconds) or R.BrewSeconds(started, cfg))
	end
	return view
end

return R
