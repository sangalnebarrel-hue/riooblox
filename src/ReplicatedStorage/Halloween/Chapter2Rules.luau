-- Pure rules of CHAPTER II · THE UNDERYARD (ReplicatedStorage.Halloween.Chapter2Rules; docs/halloween2/DESIGN.md §3.3, §8, §9).
-- Requires nothing: every function takes the config table (ReplicatedStorage.Halloween.Chapter2Config) as an argument, so
-- the server (Chapter2.luau, Features/Underyard), clients (UI odds, offering prices) and Lune tests run the same math.
--   Dates (UTC)      UnixFromDate(y, m, d, h?, min?) · DateUnix({Year, Month, Day, Hour}) · Day(now) · StartDay(cfg)
--                    SealOpensAt(i, cfg) · Phase(now, cfg, override?) · NextPhaseAt(now, cfg, override?) · SealOpen(i, now, cfg, override?)
--   Chapter I        Chapter1Complete(p, cfg) -> ok, checklist {{Key, Value, Goal, Done, Text}}
--   Bell Shards      EffOf(raw, cfg) · ApplyDR(rawToday, amount, cfg) -> effective, newRawToday · Exempt(source, cfg)
--                    ShardGrant(daily, rested, amount, cfg) -> granted, fromRested · DRRate(raw, cfg) · RestedUpdate(...)
--   Seals            OfferingCost(i, now, cfg) -> cost, discounted · SealMask(seals) · ClearedCount(seals) · SealPlayable(...)
--   Contracts        PickContracts(userId, day, cfg, cleared?) -> list · ContractDef(id, cfg)
--   Black Coffin     CoffinTotal(cfg) · CoffinChance(row, cfg) · CoffinRoll(rng, cfg, ownedSets?, opts?) -> row
--   Duplicates       DuplicateConversion(row, cfg, opts?) -> rows | nil
--   Dex II / craft   Dex2Count(p, cfg) · Dex2Claimable(p, cfg) · Dex2Reward(count, cfg) · CraftCost(id, cfg) -> cost, kind
--   Keys / misc      AddKeys(keys, n, cfg) -> keys, granted, overflow · DoorsPerDay(u, cfg) · ExchangeQuote(n, today, cfg)
-- Saved numbers stay integers; the only float in the profile is Daily.Eff (cumulative effective shards of the day),
-- always recomputed from the integer raw counters (no accumulated rounding drift).
local R = {}

local EPS = 1e-6

local function num(v: any): number
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end
local function tbl(t: any): { [any]: any }
	return type(t) == "table" and t or {}
end

---------------------------------------------------------------------------------------------------------------------
-- Dates (UTC). Days-from-civil (Howard Hinnant): exact for every Gregorian date, independent of the host time zone and
-- of os.time(table) (which reads local time on some hosts).
---------------------------------------------------------------------------------------------------------------------
function R.UnixFromDate(y: number, m: number, d: number, h: number?, min: number?): number
	y, m, d = math.floor(y), math.floor(m), math.floor(d)
	if m <= 2 then
		y -= 1
	end
	local era = y // 400 -- (Luau // floors, so negative years need no adjustment)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + math.floor(h or 0) * 3600 + math.floor(min or 0) * 60
end

function R.DateUnix(t: any): number
	t = tbl(t)
	return R.UnixFromDate(num(t.Year), num(t.Month), num(t.Day), num(t.Hour), num(t.Minute))
end

function R.Day(now: number): number
	return math.floor(num(now) / 86400)
end

function R.SecondsToNextDay(now: number): number
	return 86400 - math.floor(num(now)) % 86400
end

local startCache = setmetatable({}, { __mode = "k" })
function R.StartUnix(cfg: any): number
	local hit = startCache[cfg]
	if hit then
		return hit
	end
	local v = R.DateUnix(cfg.Start)
	startCache[cfg] = v
	return v
end

function R.StartDay(cfg: any): number
	return R.Day(R.StartUnix(cfg))
end

local opensCache = setmetatable({}, { __mode = "k" })
function R.SealOpensAt(i: number, cfg: any): number
	local list = opensCache[cfg]
	if not list then
		list = {}
		for k, seal in ipairs(cfg.Seals) do
			list[k] = R.DateUnix(seal.Opens)
		end
		opensCache[cfg] = list
	end
	return list[i] or math.huge
end

-- seals open by date (0..#Seals). override (Studio C2Debug "Phase n") can only open more, never close
function R.Phase(now: number, cfg: any, override: number?): number
	local n = 0
	for i = 1, #cfg.Seals do
		if num(now) >= R.SealOpensAt(i, cfg) then
			n = i
		else
			break
		end
	end
	return math.max(n, math.clamp(math.floor(num(override)), 0, #cfg.Seals))
end

-- unix time the next seal opens (0 when every seal is open)
function R.NextPhaseAt(now: number, cfg: any, override: number?): number
	local phase = R.Phase(now, cfg, override)
	if phase >= #cfg.Seals then
		return 0
	end
	return R.SealOpensAt(phase + 1, cfg)
end

function R.SealOpen(i: number, now: number, cfg: any, override: number?): boolean
	return i >= 1 and i <= #cfg.Seals and R.Phase(now, cfg, override) >= i
end

---------------------------------------------------------------------------------------------------------------------
-- Chapter I completion (§3.3): existing persistent fields only, nil-safe on legacy / partial profiles
---------------------------------------------------------------------------------------------------------------------
function R.Chapter1Values(p: any): { [string]: number }
	local h = type(p) == "table" and tbl(p.Halloween) or {}
	local boss, cauldron, stats = tbl(h.Boss), tbl(h.Cauldron), tbl(h.Stats)
	return {
		BossBest = math.floor(num(boss.Best)),
		Cauldron = math.floor(num(cauldron.Invested)),
		Knocks = math.floor(num(stats.Knocks)),
		BloodMoons = math.floor(num(stats.BloodMoons)),
		Spots = math.floor(num(stats.Spots)),
	}
end

function R.Chapter1Complete(p: any, cfg: any): (boolean, { any })
	local values = R.Chapter1Values(p)
	local req = cfg.Chapter1.Req
	local list, ok = {}, true
	for _, row in ipairs(cfg.Chapter1.Checklist) do
		local goal = num(req[row.Key])
		local value = values[row.Key] or 0
		local done = value >= goal
		ok = ok and done
		table.insert(list, { Key = row.Key, Value = value, Goal = goal, Done = done, Text = row.Text })
	end
	return ok, list
end

---------------------------------------------------------------------------------------------------------------------
-- Bell Shards: daily diminishing returns (§8.2) + rested allowance (§8.3)
---------------------------------------------------------------------------------------------------------------------
-- cumulative effective shards for `raw` DR-applicable raw shards earned today (piecewise linear, exact per tier)
function R.EffOf(raw: number, cfg: any): number
	raw = math.max(0, num(raw))
	local eff, lo = 0, 0
	for _, tier in ipairs(cfg.DailyReturns.Tiers) do
		local hi = tier.Upto or math.huge
		if raw > lo then
			eff += (math.min(raw, hi) - lo) * tier.Rate
		end
		if raw <= hi then
			break
		end
		lo = hi
	end
	return eff
end

-- effective (float) value of `amount` raw shards on top of `rawToday`, and the new raw counter
function R.ApplyDR(rawToday: number, amount: number, cfg: any): (number, number)
	rawToday = math.max(0, num(rawToday))
	amount = math.max(0, num(amount))
	local after = rawToday + amount
	return R.EffOf(after, cfg) - R.EffOf(rawToday, cfg), after
end

-- current DR rate (for the UI) and raw shards left in the current tier (math.huge in the last one)
function R.DRRate(rawToday: number, cfg: any): (number, number)
	rawToday = math.max(0, num(rawToday))
	for _, tier in ipairs(cfg.DailyReturns.Tiers) do
		local hi = tier.Upto or math.huge
		if rawToday < hi then
			return tier.Rate, hi - rawToday
		end
	end
	local tiers = cfg.DailyReturns.Tiers
	return tiers[#tiers].Rate, math.huge
end

function R.Exempt(source: any, cfg: any): boolean
	return type(source) == "string" and cfg.DailyReturns.Exempt[source] == true
end

-- the day's cumulative effective amount (float): rested shards (100%) + DR integral of the raw counter
function R.DailyEff(daily: any, cfg: any): number
	return math.max(0, num(daily.Rested)) + R.EffOf(daily.Raw, cfg)
end

-- one DR-applicable grant of `amount` raw shards. Mutates daily {Raw, Rested, Eff} and rested {Pool}.
-- The rested pool is consumed first at 100% (it extends the full tier); the rest runs through the DR tiers.
-- Returns the integer shards to pay now (floor(cumulative after) - floor(cumulative before)) and the rested part.
function R.ShardGrant(daily: any, rested: any, amount: number, cfg: any): (number, number)
	amount = math.max(0, math.floor(num(amount)))
	daily.Raw = math.max(0, math.floor(num(daily.Raw)))
	daily.Rested = math.max(0, math.floor(num(daily.Rested)))
	rested.Pool = math.max(0, math.floor(num(rested.Pool)))
	local before = R.DailyEff(daily, cfg)
	local fromPool = math.min(amount, rested.Pool)
	rested.Pool -= fromPool
	daily.Rested += fromPool
	daily.Raw += amount - fromPool
	local after = R.DailyEff(daily, cfg)
	daily.Eff = after
	local granted = math.floor(after + EPS) - math.floor(before + EPS)
	return math.max(0, granted), fromPool
end

-- Rested allowance: every FULL UTC day since Start (and before `today`) not yet accounted adds
-- (PerDay - raw shards earned that day) x Fraction, capped. `daily` is the profile's daily record (it may still hold
-- the last played day: that day's raw + rested counts as earned). Mutates rested {Day, Pool}; returns the added amount.
function R.RestedUpdate(rested: any, daily: any, today: number, cfg: any): number
	local rc = cfg.Rested
	local from = math.max(R.StartDay(cfg), math.floor(num(rested.Day)) + 1)
	local to = math.floor(num(today)) - 1 -- the last full day
	rested.Pool = math.max(0, num(rested.Pool))
	if to < from then
		rested.Day = math.max(math.floor(num(rested.Day)), math.min(to, math.floor(num(today)) - 1))
		return 0
	end
	local days = to - from + 1
	local added = 0
	local dDay = math.floor(num(daily and daily.Day or -1))
	if dDay >= from and dDay <= to then
		local earned = math.max(0, num(daily.Raw)) + math.max(0, num(daily.Rested))
		added += math.max(0, rc.PerDay - earned) * rc.Fraction
		days -= 1
	end
	added += days * rc.PerDay * rc.Fraction
	local before = rested.Pool
	rested.Pool = math.min(rc.Cap, math.floor(before + added + EPS))
	rested.Day = to
	return math.max(0, rested.Pool - before)
end

---------------------------------------------------------------------------------------------------------------------
-- Seals
---------------------------------------------------------------------------------------------------------------------
-- "The Bell remembers": a seal whose date opened >= DiscountAfterDays ago costs Discount less
function R.OfferingCost(i: number, now: number, cfg: any): (number, boolean)
	local seal = cfg.Seals[i]
	if not seal then
		return 0, false
	end
	local opens = R.SealOpensAt(i, cfg)
	local off = cfg.Offering
	if num(now) >= opens + off.DiscountAfterDays * 86400 then
		return math.floor(seal.Offering * (1 - off.Discount) + .5), true
	end
	return seal.Offering, false
end

local function sealRow(seals: any, i: number): any
	return tbl(tbl(seals)[tostring(i)])
end
R.SealRow = sealRow

function R.ClearedCount(seals: any, cfg: any?): number
	local n = 0
	for i = 1, cfg and #cfg.Seals or 7 do
		if sealRow(seals, i).Cleared == true then
			n += 1
		end
	end
	return n
end

-- "1101000": cleared per seal
function R.SealMask(seals: any, cfg: any?): string
	local out = table.create(cfg and #cfg.Seals or 7, "0")
	for i = 1, #out do
		out[i] = sealRow(seals, i).Cleared == true and "1" or "0"
	end
	return table.concat(out)
end

-- may a player with Underyard data `u` offer seal i now? -> ok, reason
function R.CanOffer(u: any, i: number, now: number, cfg: any, override: number?): (boolean, string?)
	if not cfg.Seals[i] then
		return false, "Unknown seal"
	end
	if not R.SealOpen(i, now, cfg, override) then
		return false, "This seal has not opened yet"
	end
	local seals = tbl(u).Seals
	if i > 1 and sealRow(seals, i - 1).Cleared ~= true then
		return false, "Clear the previous seal first"
	end
	if sealRow(seals, i).Offered == true then
		return false, "The offering is already made"
	end
	return true, nil
end

-- may a player start the trial of seal i now (date + previous cleared + offered)? -> ok, reason
function R.SealPlayable(u: any, i: number, now: number, cfg: any, override: number?): (boolean, string?)
	if not cfg.Seals[i] then
		return false, "Unknown seal"
	end
	if not R.SealOpen(i, now, cfg, override) then
		return false, "This seal has not opened yet"
	end
	local seals = tbl(u).Seals
	if i > 1 and sealRow(seals, i - 1).Cleared ~= true then
		return false, "Clear the previous seal first"
	end
	if sealRow(seals, i).Offered ~= true then
		return false, "Make the offering at the seal's altar first"
	end
	return true, nil
end

-- district gating (§7.2): cleared seals needed per district (UnderyardLayout.Unlock)
function R.DistrictUnlocked(cleared: number, district: string?, unlock: { [string]: number }): boolean
	if district == nil or district == "" or district == "*" then
		return true
	end
	return num(cleared) >= num(unlock[district])
end

---------------------------------------------------------------------------------------------------------------------
-- Daily contracts (§8.5): deterministic per userId + UTC day (own Park-Miller generator: identical on every host)
---------------------------------------------------------------------------------------------------------------------
local function lcg(seed: number): () -> number
	local state = math.floor(num(seed)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
R.Lcg = lcg

function R.ContractDef(id: any, cfg: any): any
	for _, row in ipairs(cfg.Contracts.Pool) do
		if row.Id == id then
			return row
		end
	end
	return nil
end

-- cleared: seals the player has cleared when the list is drawn (contracts with MinCleared above it are skipped)
function R.PickContracts(userId: number, day: number, cfg: any, cleared: number?): { any }
	local cc = cfg.Contracts
	local rand = lcg((math.floor(num(userId)) % 2147483) * 7919 + math.floor(num(day)) * 104729 + 911)
	local pool = {}
	for _, row in ipairs(cc.Pool) do
		if num(row.MinCleared) <= (cleared == nil and math.huge or num(cleared)) and num(row.Weight) > 0 then
			table.insert(pool, row)
		end
	end
	local out = {}
	while #out < cc.PerDay and #pool > 0 do
		local total = 0
		for _, row in ipairs(pool) do
			total += row.Weight
		end
		local x = rand() * total
		local pick = #pool
		for k, row in ipairs(pool) do
			x -= row.Weight
			if x < 0 then
				pick = k
				break
			end
		end
		local row = table.remove(pool, pick)
		table.insert(out, { Id = row.Id, Goal = row.Goal, Progress = 0, Claimed = false })
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The Black Coffin (§9.3)
---------------------------------------------------------------------------------------------------------------------
function R.CoffinTotal(cfg: any): number
	local sum = 0
	for _, row in ipairs(cfg.Coffin.Table) do
		sum += num(row.Weight)
	end
	return sum
end

-- exact probability (0..1) of one row
function R.CoffinChance(row: any, cfg: any): number
	local total = R.CoffinTotal(cfg)
	return total > 0 and num(row.Weight) / total or 0
end

-- probability of every display group (Group -> 0..1)
function R.CoffinGroups(cfg: any): { [string]: number }
	local total, out = R.CoffinTotal(cfg), {}
	for _, row in ipairs(cfg.Coffin.Table) do
		out[row.Group] = (out[row.Group] or 0) + num(row.Weight) / total
	end
	return out
end

local function unit(rng: any): number
	if type(rng) == "function" then
		return rng()
	end
	return rng:NextNumber()
end

local function between(rng: any, lo: number, hi: number): number
	lo, hi = math.floor(lo), math.floor(hi)
	if hi <= lo then
		return lo
	end
	return math.min(hi, lo + math.floor(unit(rng) * (hi - lo + 1)))
end
R.Between = between

-- a reward row with its amount rolled (Min/Max) and duplicate flag. ownedSets = {Decor = {[id]=true}, Skins = {..},
-- Finds = {..}} marks Duplicate (presentation only: the weights never change). opts.Group forces one display group
-- (the tutorial's first coffin rolls "Find"); opts.Rows replaces the table.
function R.CoffinRoll(rng: any, cfg: any, ownedSets: any?, opts: any?): any
	opts = tbl(opts)
	local rows = opts.Rows or cfg.Coffin.Table
	local pool = rows
	if type(opts.Group) == "string" then
		pool = {}
		for _, row in ipairs(rows) do
			if row.Group == opts.Group then
				table.insert(pool, row)
			end
		end
		if #pool == 0 then
			pool = rows
		end
	end
	local total = 0
	for _, row in ipairs(pool) do
		total += math.max(0, num(row.Weight))
	end
	local x = unit(rng) * total
	local pick = pool[#pool]
	for _, row in ipairs(pool) do
		x -= math.max(0, num(row.Weight))
		if x < 0 then
			pick = row
			break
		end
	end
	local out = {}
	for k, v in pairs(pick) do
		out[k] = v
	end
	out.Weight = nil
	if pick.Min and pick.Max then
		out.Amount = between(rng, pick.Min, pick.Max)
		out.Min, out.Max = nil, nil
	end
	local owned = tbl(ownedSets)
	if out.Kind == "Decor" and tbl(owned.Decor)[out.Id] then
		out.Duplicate = true
	elseif out.Kind == "Skin" and tbl(owned.Skins)[out.Id] then
		out.Duplicate = true
	elseif out.Kind == "Find" and tbl(owned.Finds)[out.Id] then
		out.Duplicate = true
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Duplicates / fallback (§9.4): a cosmetic already owned at max, a find already owned, or an undeliverable dog
---------------------------------------------------------------------------------------------------------------------
-- opts.CoffinPug: H12 in the yard team (+DuplicateBonus on every amount). Returns the conversion rows or nil (kind
-- never converts).
function R.DuplicateConversion(row: any, cfg: any, opts: any?): { any }?
	opts = tbl(opts)
	local dup = cfg.Duplicates
	local mult = opts.CoffinPug and (1 + dup.CoffinPugBonus) or 1
	local function amt(n: number): number
		return math.floor(n * mult + .5)
	end
	local kind = type(row) == "table" and row.Kind
	if kind == "Decor" then
		return { { Kind = "Fragments", Amount = amt(dup.Decor.Fragments) }, { Kind = "Dust", Amount = amt(dup.Decor.Dust) } }
	elseif kind == "Skin" then
		return { { Kind = "Fragments", Amount = amt(dup.Skin.Fragments) }, { Kind = "Dust", Amount = amt(dup.Skin.Dust) } }
	elseif kind == "Find" then
		local out = { { Kind = "Shards", Amount = amt(dup.Find.Shards), Source = "Duplicate" }, { Kind = "Dust", Amount = amt(dup.Find.Dust) } }
		local def = cfg.Finds.Defs[row.Id]
		local tier = row.Tier or (def and def.Tier)
		if tier == "Legendary" then
			table.insert(out, { Kind = "Fragments", Amount = amt(dup.Find.LegendaryFragments) })
		end
		return out
	elseif kind == "Dog" then
		local def = cfg.Dogs.Defs[row.Id]
		local rank = math.max(1, math.floor(num(row.Rank) > 0 and num(row.Rank) or (def and def.Rank or 2)))
		return { { Kind = "Shards", Amount = amt(dup.DogShardsPerRank * rank), Source = "Duplicate" } }
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Dex II (§9.8) and the tailor (§9.5)
---------------------------------------------------------------------------------------------------------------------
function R.Dex2Count(p: any, cfg: any): number
	local dex = type(p) == "table" and tbl(p.DogDex) or {}
	local n = 0
	for _, id in ipairs(cfg.Dogs.Order) do
		if dex[id] then
			n += 1
		end
	end
	return n
end

function R.Dex2Reward(count: number, cfg: any): any
	for _, tier in ipairs(cfg.Dex2Rewards) do
		if tier.Count == count then
			return tier
		end
	end
	return nil
end

-- milestone counts reached and not yet claimed (p.Underyard.Dex2Claims)
function R.Dex2Claimable(p: any, cfg: any): { number }
	local have = R.Dex2Count(p, cfg)
	local claims = type(p) == "table" and tbl(tbl(p.Underyard).Dex2Claims) or {}
	local out = {}
	for _, tier in ipairs(cfg.Dex2Rewards) do
		if have >= tier.Count and not claims[tostring(tier.Count)] then
			table.insert(out, tier.Count)
		end
	end
	return out
end

-- fragments needed to craft `id` and its kind ("Decor" | "Skin"), or nil + reason (the Dex-only Secret skin is never
-- crafted)
function R.CraftCost(id: any, cfg: any): (number?, string?)
	if type(id) ~= "string" then
		return nil, "Unknown cosmetic"
	end
	if cfg.Decor.Defs[id] then
		return cfg.Craft.Decor, "Decor"
	end
	local skin = cfg.Skins.Defs[id]
	if skin then
		if skin.DexOnly then
			return nil, "This skin only comes from the Dex II"
		end
		return cfg.Craft.Skin, "Skin"
	end
	return nil, "Unknown cosmetic"
end

---------------------------------------------------------------------------------------------------------------------
-- Keys, doors, exchange
---------------------------------------------------------------------------------------------------------------------
-- key cap (Coffin.MaxKeys): -> new key count, keys granted, overflow (not stored)
function R.AddKeys(keys: number, n: number, cfg: any): (number, number, number)
	keys = math.max(0, math.floor(num(keys)))
	n = math.max(0, math.floor(num(n)))
	local room = math.max(0, cfg.Coffin.MaxKeys - keys)
	local granted = math.min(room, n)
	return keys + granted, granted, n - granted
end

-- Crooked Door openings today (+1 with all of today's contracts claimed)
function R.DoorsPerDay(u: any, cfg: any): number
	local daily = tbl(tbl(u).Daily)
	local contracts = tbl(daily.Contracts)
	return cfg.Doors.PerDay + (contracts.AllClaimed == true and cfg.Doors.ContractBonus or 0)
end

-- Toll Box: shards bought now (clipped by the daily cap) and their candy price
function R.ExchangeQuote(n: number, exchangedToday: number, cfg: any): (number, number)
	local ex = cfg.Exchange
	n = math.clamp(math.floor(num(n)), 0, ex.MaxPerRequest)
	local room = math.max(0, ex.MaxPerDay - math.floor(num(exchangedToday)))
	local shards = math.min(n, room)
	return shards, shards * ex.CandyPerShard
end

-- tutorial step definition by id
function R.TutorialStep(step: number, cfg: any): any
	for _, row in ipairs(cfg.Tutorial.Steps) do
		if row.Id == step then
			return row
		end
	end
	return nil
end

return R
