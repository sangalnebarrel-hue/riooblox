--!nolint
-- CHAPTER II story pacing (brief point 6): lune run tests/chapter2_pacing.luau
-- The real Chapter2Config through the real Chapter2Rules (tools/chapter2_pacing.luau, an ordinary active player):
--   * on time (Oct 20): 6-9 h of active Chapter II play (plus Chapter I for a new player: the 8-12 h story), never
--     finished before the seventh seal opens, spread over a week (not one evening)
--   * a player who starts on Oct 24 or Oct 28 still breaks the seventh seal before the claim deadline, with a
--     reasonable daily session (catch-up: the rested pool + the late offering discount)
_G.__pacing_lib = true
local P = require("../tools/chapter2_pacing")
local E = require("./lib/economy_env")
local Cfg = E.Require("ReplicatedStorage.Halloween.Chapter2Config")
local R = E.Require("ReplicatedStorage.Halloween.Chapter2Rules")

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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local START = R.StartDay(Cfg)
local DAY = 86400
local SEVENTH = math.floor(R.SealOpensAt(7, Cfg) / DAY)
local cd = Cfg.ClaimDeadline
local DEADLINE = math.floor(R.UnixFromDate(cd.Year, cd.Month, cd.Day, cd.Hour or 0) / DAY)

test("on time: 6-9 h of active play over a week, never before the seventh seal opens", function()
	local r = P.Run(START)
	truthy(r.Done, "the story is never finished")
	local h = r.Seconds / 3600
	truthy(h >= 6 and h <= 9, string.format("%.1f h of active play", h))
	truthy(r.Done >= SEVENTH, "finished before the seventh seal opens")
	truthy(r.Days >= 7, "played over " .. r.Days .. " days (one evening is not enough)")
	truthy(r.Seconds / 60 / r.Days <= 75, string.format("%.0f min a day", r.Seconds / 60 / r.Days))
end)

test("late starters catch up before the claim deadline with a reasonable daily session", function()
	for _, late in ipairs({ 4, 6, 8 }) do
		local r = P.Run(START + late)
		truthy(r.Done and r.Done < DEADLINE, "start day +" .. late .. " does not finish before the deadline")
		truthy(r.Seconds / 60 / r.Days <= 120, string.format("start +%d: %.0f min a day", late, r.Seconds / 60 / r.Days))
	end
end)

test("the first clears never pay for the next offering by themselves (the story needs play between seals)", function()
	for i = 2, 7 do
		truthy(Cfg.Seals[i - 1].Rewards.First < Cfg.Seals[i].Offering, "seal " .. (i - 1) .. "'s first clear pays seal " .. i)
	end
end)

print(string.format("chapter2_pacing: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("chapter2_pacing tests failed")
end
