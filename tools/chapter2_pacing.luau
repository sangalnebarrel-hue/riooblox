--!nolint
-- CHAPTER II story pacing (brief point 6: an 8-12 h story, collection over days, daily gates + catch-up), computed from
-- the real Chapter2Config through the real Chapter2Rules (ShardGrant = the daily diminishing returns + the rested pool,
-- RestedUpdate, OfferingCost with the late discount, SealOpen dates).
-- The player model is an ordinary active player, not an optimiser:
--   * shards are earned in repeat Bell Trials / Underyard activities at FARM_RAW raw shards per FARM_CYCLE seconds
--   * each day they stop earning once the day's raw shards reach STOP_RAW (past it only 10% would count)
--   * the three daily contracts are claimed on every day they play (DR-exempt), each first clear pays Rewards.First
--   * each trial is cleared on the first try at FIRST_TRY of its time limit (+ OVERHEAD), the harder seals after one
--     failed attempt at its full limit
-- Prints, per start day, the day the seventh seal breaks, the active play minutes and the minutes per played day.
-- usage: lune run tools/chapter2_pacing.luau [offering multiplier]   (the multiplier tries a retune without editing)
local process = require("@lune/process")
local E = require("../tests/lib/economy_env")
local Cfg = E.Require("ReplicatedStorage.Halloween.Chapter2Config")
local R = E.Require("ReplicatedStorage.Halloween.Chapter2Rules")
-- try a catch-up retune without editing the config: PACING_RESTED_CAP=..., PACING_DISCOUNT=...
if tonumber(process.env.PACING_RESTED_CAP) then
	Cfg.Rested.Cap = tonumber(process.env.PACING_RESTED_CAP)
end
if tonumber(process.env.PACING_DISCOUNT) then
	Cfg.Offering.Discount = tonumber(process.env.PACING_DISCOUNT)
end

local P = {}
P.DAY = 86400
P.OVERHEAD = 75 -- s per trial: walk to the start, 3-2-1, results card, the seal cinematic
P.FIRST_TRY = .8 -- share of the time limit a clear takes
P.FAIL_FIRST = { [4] = true, [6] = true, [7] = true } -- seals a player usually fails once
P.FARM_CYCLE = 150 -- s per farming run (a repeat trial / a round of activities, walking included)
P.FARM_RAW = 50 -- raw shards per farming run (objective shards + Repeat)
P.STOP_RAW = (Cfg.DailyReturns.Tiers[2] and Cfg.DailyReturns.Tiers[2].Upto) or 1000
P.ONBOARDING = 8 * 60 -- the Chapter II guide (toll, mourner, first coffin, first offering)

local function trialSeconds(i: number): number
	local seal = Cfg.Seals[i]
	local t = seal.Trial.TimeLimit
	if t == 0 then -- Crooked Doors: three outcomes over the daily door openings (a chest, a challenge, the Doorkeeper)
		t = (Cfg.Trials.Defs.DoorChallenge and Cfg.Trials.Defs.DoorChallenge.TimeLimit or 25)
			+ (Cfg.Trials.Defs.Doorkeeper and Cfg.Trials.Defs.Doorkeeper.TimeLimit or 120) + 60
	end
	local s = t * P.FIRST_TRY + P.OVERHEAD
	if P.FAIL_FIRST[i] then
		s += t + P.OVERHEAD
	end
	return s
end

-- -> {Done = unix day of the seventh seal or nil, Seconds, Days = days played, Bank}
function P.Run(startDay: number, mult: number?): any
	local m = mult or 1
	local daily, rested = { Day = -1, Raw = 0, Rested = 0, Eff = 0 }, { Day = -1, Pool = 0 }
	-- a late starter's rested pool: the absent days since Chapter II opened count as unplayed
	local start = R.StartDay(Cfg)
	for d = start, startDay - 1 do
		R.RestedUpdate(rested, daily, d, Cfg)
		daily.Day, daily.Raw, daily.Rested, daily.Eff = d, 0, 0, 0
	end
	local bank, seconds, played = 0, P.ONBOARDING, 0
	local nextSeal, day = 1, startDay
	while nextSeal <= 7 and day < startDay + 40 do
		R.RestedUpdate(rested, daily, day, Cfg)
		daily.Day, daily.Raw, daily.Rested, daily.Eff = day, 0, 0, 0
		local now = day * P.DAY + 3600
		local playedToday = false
		bank += Cfg.Contracts.PerDay * Cfg.Contracts.Reward.Shards
		while nextSeal <= 7 and R.SealOpen(nextSeal, now, Cfg) do
			local cost = nextSeal == 1 and 0 or math.floor((R.OfferingCost(nextSeal, now, Cfg)) * m)
			while bank < cost and daily.Raw < P.STOP_RAW do
				bank += (R.ShardGrant(daily, rested, P.FARM_RAW, Cfg))
				seconds += P.FARM_CYCLE
				playedToday = true
			end
			if bank < cost then
				break -- tomorrow
			end
			bank -= cost
			seconds += trialSeconds(nextSeal)
			bank += Cfg.Seals[nextSeal].Rewards.First
			playedToday = true
			nextSeal += 1
		end
		if playedToday then
			played += 1
		end
		if nextSeal <= 7 then
			day += 1
		end
	end
	return { Done = nextSeal > 7 and day or nil, Seconds = seconds, Days = math.max(1, played), Bank = bank }
end

function P.Report(mult: number?)
	local start = R.StartDay(Cfg)
	local out = {}
	for _, s in ipairs({ { "on time (Oct 20)", 0 }, { "Oct 22", 2 }, { "Oct 24", 4 }, { "late (Oct 28)", 8 } }) do
		local r = P.Run(start + s[2], mult)
		table.insert(out, { Label = s[1], Result = r })
	end
	return out
end

if process.args[1] ~= nil or not _G.__pacing_lib then
	local mult = tonumber(process.args[1])
	local total = 0
	for i = 2, 7 do
		total += Cfg.Seals[i].Offering
	end
	print(string.format("offerings II-VII: %d x %.2f = %d shards; first clears: %d; farming %d raw / %d s, stop at %d raw a day",
		total, mult or 1, math.floor(total * (mult or 1)), (function()
			local n = 0
			for i = 1, 7 do
				n += Cfg.Seals[i].Rewards.First
			end
			return n
		end)(), P.FARM_RAW, P.FARM_CYCLE, P.STOP_RAW))
	for _, row in ipairs(P.Report(mult)) do
		local r = row.Result
		print(string.format("  %-18s seventh seal %s, %5.1f h active play over %d days (%3.0f min a day)", row.Label,
			r.Done and os.date("!%b %d", r.Done * P.DAY) or "NOT by the 40th day", r.Seconds / 3600, r.Days, r.Seconds / 60 / r.Days))
	end
end

return P
