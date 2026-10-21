--!nolint
-- CHAPTER II pure rules (ReplicatedStorage.Halloween.Chapter2Rules + Chapter2Config): lune run tests/chapter2_rules.luau
-- Dates (UTC), phase schedule, offering discount, daily diminishing returns (exact across tier boundaries and many small
-- grants), the rested allowance, contracts, the Black Coffin table, duplicate conversion, Chapter I completion, dex II,
-- craft, keys, doors, exchange.
local L = require("./lib/economy_env")
local Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local R = L.Require("ReplicatedStorage.Halloween.Chapter2Rules")

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
	if math.abs(a - b) > (eps or 1e-9) then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local DAY = 86400
local START = R.UnixFromDate(2026, 10, 20)

---------------------------------------------------------------------------------------------------------------------
-- dates
---------------------------------------------------------------------------------------------------------------------
test("UnixFromDate matches the UTC calendar", function()
	eq(R.UnixFromDate(1970, 1, 1), 0)
	eq(START, 1792454400, "2026-10-20")
	eq(R.UnixFromDate(2000, 3, 1), 951868800, "leap century")
	eq(R.UnixFromDate(2024, 2, 29, 12, 30), 1709209800, "leap day")
	-- every ~37 days for 160 years against the host's UTC breakdown
	local t = 0
	for _ = 1, 1600 do
		local d = os.date("!*t", t)
		eq(R.UnixFromDate(d.year, d.month, d.day, d.hour, d.min), t - d.sec, os.date("!%Y-%m-%d %H:%M", t))
		t += 37 * DAY + 3671
	end
	eq(R.DateUnix(Cfg.Start), START)
	eq(R.StartDay(Cfg), START // DAY)
	eq(R.Day(START + DAY - 1), START // DAY)
	eq(R.SecondsToNextDay(START + 10), DAY - 10)
end)

test("phase schedule opens the seals on their UTC dates", function()
	eq(R.Phase(START - 1, Cfg), 0, "day before")
	eq(R.Phase(START, Cfg), 2, "Oct 20 00:00 opens I and II")
	eq(R.Phase(START + DAY - 1, Cfg), 2)
	eq(R.Phase(START + DAY, Cfg), 3, "Oct 21")
	eq(R.Phase(START + 2 * DAY, Cfg), 4, "Oct 22")
	eq(R.Phase(START + 3 * DAY, Cfg), 5, "Oct 23")
	eq(R.Phase(START + 4 * DAY, Cfg), 6, "Oct 24")
	eq(R.Phase(START + 5 * DAY, Cfg), 6, "Oct 25")
	eq(R.Phase(START + 6 * DAY, Cfg), 7, "Oct 26")
	eq(R.Phase(START + 60 * DAY, Cfg), 7)
	eq(R.NextPhaseAt(START - 5, Cfg), START)
	eq(R.NextPhaseAt(START, Cfg), START + DAY)
	eq(R.NextPhaseAt(START + 4 * DAY + 5, Cfg), START + 6 * DAY)
	eq(R.NextPhaseAt(START + 7 * DAY, Cfg), 0)
	truthy(R.SealOpen(2, START, Cfg) and not R.SealOpen(3, START, Cfg), "seal open flags")
	-- the Studio override only opens more
	eq(R.Phase(START - DAY, Cfg, 5), 5)
	eq(R.Phase(START + 6 * DAY, Cfg, 2), 7)
	truthy(not R.SealOpen(0, START, Cfg) and not R.SealOpen(8, START + 99 * DAY, Cfg), "out of range")
end)

test("offering cost: the Bell remembers (40% off two days after a seal opened)", function()
	eq(R.OfferingCost(1, START, Cfg), 100)
	eq(R.OfferingCost(1, START + 2 * DAY - 1, Cfg), 100)
	local c, disc = R.OfferingCost(1, START + 2 * DAY, Cfg)
	eq(c, 60)
	truthy(disc, "discount flag")
	eq(R.OfferingCost(3, START + 2 * DAY, Cfg), 900, "seal III opened one day ago")
	eq(R.OfferingCost(3, START + 3 * DAY, Cfg), 540)
	eq(R.OfferingCost(6, START + 6 * DAY, Cfg), 1170)
	eq(R.OfferingCost(7, START + 8 * DAY, Cfg), 1440)
	eq(R.OfferingCost(9, START, Cfg), 0, "unknown seal")
	for i, seal in ipairs(Cfg.Seals) do
		-- the story-length offerings (tests/chapter2_pacing.luau checks what they mean in hours)
		eq(seal.Offering, ({ 100, 600, 900, 1200, 1500, 1950, 2400 })[i], "offering " .. i)
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- Bell Shards: DR + rested
---------------------------------------------------------------------------------------------------------------------
test("DR integral: 500 at 100%, 500 at 35%, then 10%", function()
	eq(R.EffOf(0, Cfg), 0)
	eq(R.EffOf(500, Cfg), 500)
	near(R.EffOf(1000, Cfg), 675, 1e-9)
	near(R.EffOf(2000, Cfg), 775, 1e-9)
	local e, raw = R.ApplyDR(499, 3, Cfg)
	near(e, 1 + 2 * .35, 1e-9, "across the first boundary")
	eq(raw, 502)
	e = R.ApplyDR(990, 20, Cfg)
	near(e, 10 * .35 + 10 * .10, 1e-9, "across the second boundary")
	e = R.ApplyDR(0, 0, Cfg)
	eq(e, 0)
	eq(select(1, R.DRRate(0, Cfg)), 1)
	eq(select(2, R.DRRate(120, Cfg)), 380)
	eq(select(1, R.DRRate(500, Cfg)), .35)
	eq(select(1, R.DRRate(5000, Cfg)), .10)
	truthy(R.Exempt("First", Cfg) and R.Exempt("Contract", Cfg) and not R.Exempt("Streak", Cfg) and not R.Exempt(nil, Cfg), "exempt")
end)

local function grantAll(chunks, pool)
	local daily, rested = { Raw = 0, Rested = 0, Eff = 0 }, { Pool = pool or 0 }
	local total = 0
	for _, n in ipairs(chunks) do
		total += R.ShardGrant(daily, rested, n, Cfg)
	end
	return total, daily, rested
end

test("DR is exact: many small grants pay the same as one big grant", function()
	for _, target in ipairs({ 1, 499, 500, 501, 777, 999, 1000, 1001, 1337, 2500, 4321 }) do
		local ones = table.create(target, 1)
		local small = grantAll(ones)
		local big = grantAll({ target })
		eq(small, big, "raw " .. target)
		eq(big, math.floor(R.EffOf(target, Cfg) + 1e-6), "floor of the integral at " .. target)
	end
	-- uneven chunks (streak 2s, echoes 3s, repeats 35s) never drift
	local rng = R.Lcg(12345)
	local chunks, sum = {}, 0
	while sum < 5000 do
		local n = 1 + math.floor(rng() * 40)
		table.insert(chunks, n)
		sum += n
	end
	local got, daily = grantAll(chunks)
	eq(got, math.floor(R.EffOf(sum, Cfg) + 1e-6), "chunked")
	eq(daily.Raw, sum)
	near(daily.Eff, R.EffOf(sum, Cfg), 1e-6, "Eff float")
	-- every partial sum equals floor(cumulative) (no grant ever pays a rounding error early)
	local d, r, paid, raw = { Raw = 0, Rested = 0 }, { Pool = 0 }, 0, 0
	for _, n in ipairs(chunks) do
		paid += R.ShardGrant(d, r, n, Cfg)
		raw += n
		eq(paid, math.floor(R.EffOf(raw, Cfg) + 1e-6), "partial " .. raw)
	end
	-- negative / NaN / fractional inputs are harmless
	local dd, rr = { Raw = 0 / 0, Rested = -5 }, { Pool = -1 }
	eq(R.ShardGrant(dd, rr, 10.7, Cfg), 10)
	eq(R.ShardGrant(dd, rr, -3, Cfg), 0)
end)

test("rested pool is consumed first and extends the 100% tier", function()
	local got, daily, rested = grantAll({ 2000 }, 750)
	eq(got, 750 + 500 + 175 + 25, "750 rested + DR of the remaining 1250")
	eq(rested.Pool, 0)
	eq(daily.Rested, 750)
	eq(daily.Raw, 1250)
	local small = grantAll(table.create(2000, 1), 750)
	eq(small, got, "small grants with rested")
	local partial = grantAll({ 300 }, 750)
	eq(partial, 300)
end)

test("rested allowance accrues per full UTC day since the start, capped", function()
	local sd = R.StartDay(Cfg)
	-- a player who never played: every full day since the start counts as 0 earned
	local rested, daily = { Day = -1, Pool = 0 }, { Day = -1 }
	eq(R.RestedUpdate(rested, daily, sd, Cfg), 0, "start day: nothing yet")
	eq(rested.Pool, 0)
	R.RestedUpdate(rested, daily, sd + 1, Cfg)
	eq(rested.Pool, 250, "one empty day")
	eq(rested.Day, sd)
	R.RestedUpdate(rested, daily, sd + 1, Cfg)
	eq(rested.Pool, 250, "idempotent within a day")
	-- day sd+1 played: 300 raw + 0 rested -> (500 - 300) x .5 = 100; then sd+2 empty -> 250 (cap 750)
	local d2 = { Day = sd + 1, Raw = 300, Rested = 0 }
	R.RestedUpdate(rested, d2, sd + 3, Cfg)
	eq(rested.Pool, 250 + 100 + 250, "played day + empty day")
	R.RestedUpdate(rested, { Day = sd + 3, Raw = 600, Rested = 0 }, sd + 4, Cfg)
	eq(rested.Pool, 600, "a full day adds nothing")
	R.RestedUpdate(rested, { Day = sd + 4, Raw = 0, Rested = 0 }, sd + 9, Cfg)
	eq(rested.Pool, Cfg.Rested.Cap, "cap")
	-- a late player on Oct 28: 8 empty days -> capped
	local late = { Day = -1, Pool = 0 }
	R.RestedUpdate(late, { Day = -1 }, sd + 8, Cfg)
	eq(late.Pool, Cfg.Rested.Cap)
	-- before the start nothing accrues
	local early = { Day = -1, Pool = 0 }
	eq(R.RestedUpdate(early, { Day = -1 }, sd - 3, Cfg), 0)
	eq(early.Pool, 0)
	R.RestedUpdate(early, { Day = -1 }, sd + 1, Cfg)
	eq(early.Pool, 250, "only days since the start")
	-- rested shards used that day count as earned
	local used = { Day = -1, Pool = 0 }
	R.RestedUpdate(used, { Day = sd, Raw = 100, Rested = 300 }, sd + 1, Cfg)
	eq(used.Pool, 50, "(500 - 400) x .5")
end)

---------------------------------------------------------------------------------------------------------------------
-- seals
---------------------------------------------------------------------------------------------------------------------
local function seals(spec)
	local out = {}
	for i = 1, 7 do
		local c = string.sub(spec, i, i)
		out[tostring(i)] = { Offered = c == "o" or c == "1" or c == "g", Cleared = c == "1" or c == "g", Gold = c == "g" }
	end
	return out
end

test("seal mask, cleared count, offering and playability", function()
	local s = seals("1g1o000")
	eq(R.SealMask(s, Cfg), "1110000")
	eq(R.ClearedCount(s, Cfg), 3)
	eq(R.SealMask(nil, Cfg), "0000000")
	local u = { Seals = s }
	local ok, why = R.CanOffer(u, 4, START + 2 * DAY, Cfg)
	eq(ok, false)
	eq(why, "The offering is already made")
	truthy(R.SealPlayable(u, 4, START + 2 * DAY, Cfg), "IV playable on Oct 22")
	ok, why = R.SealPlayable(u, 4, START + DAY, Cfg)
	eq(why, "This seal has not opened yet")
	ok, why = R.CanOffer(u, 5, START + 5 * DAY, Cfg)
	eq(why, "Clear the previous seal first")
	truthy(R.CanOffer({ Seals = seals("0000000") }, 1, START, Cfg), "first offering")
	ok, why = R.SealPlayable({ Seals = seals("0000000") }, 1, START, Cfg)
	eq(why, "Make the offering at the seal's altar first")
	eq(select(2, R.CanOffer(u, 9, START, Cfg)), "Unknown seal")
	truthy(R.DistrictUnlocked(1, "FuneralCarnival", { FuneralCarnival = 1 }) and not R.DistrictUnlocked(0, "FuneralCarnival",
		{ FuneralCarnival = 1 }) and R.DistrictUnlocked(0, "*", {}), "district gating")
end)

---------------------------------------------------------------------------------------------------------------------
-- contracts
---------------------------------------------------------------------------------------------------------------------
test("daily contracts are deterministic per user and day", function()
	local day = START // DAY
	local a = R.PickContracts(123456789, day, Cfg, 7)
	local b = R.PickContracts(123456789, day, Cfg, 7)
	eq(#a, Cfg.Contracts.PerDay)
	for i = 1, #a do
		eq(a[i].Id, b[i].Id, "same pick")
		eq(a[i].Goal, R.ContractDef(a[i].Id, Cfg).Goal)
		eq(a[i].Progress, 0)
		eq(a[i].Claimed, false)
	end
	local ids = {}
	for _, row in ipairs(a) do
		truthy(not ids[row.Id], "unique ids")
		ids[row.Id] = true
	end
	-- different days / users differ somewhere
	local differs = 0
	for d = 1, 20 do
		local c = R.PickContracts(123456789, day + d, Cfg, 7)
		if c[1].Id ~= a[1].Id or c[2].Id ~= a[2].Id or c[3].Id ~= a[3].Id then
			differs += 1
		end
	end
	truthy(differs >= 15, "lists change across days (" .. differs .. "/20)")
	-- sealed districts never get a contract: nobody with 0 seals draws Ore / Revive / Door / Spirit
	local counts = {}
	for uid = 1, 3000 do
		for _, row in ipairs(R.PickContracts(uid * 7919, day, Cfg, 0)) do
			counts[row.Id] = (counts[row.Id] or 0) + 1
			truthy(R.ContractDef(row.Id, Cfg).MinCleared <= 0, row.Id .. " drawn with 0 seals")
		end
	end
	truthy((counts.Perfect or 0) > 0 and (counts.Coffin or 0) > 0, "pool used")
	-- draw frequencies follow the weights (Perfect 10 vs Coffin 6 within the 0-seal pool)
	truthy(counts.Perfect > counts.Coffin, "weights")
	local all = {}
	for uid = 1, 2000 do
		for _, row in ipairs(R.PickContracts(uid, day, Cfg)) do
			all[row.Id] = true
		end
	end
	for _, row in ipairs(Cfg.Contracts.Pool) do
		truthy(all[row.Id], row.Id .. " never drawn without a seal filter")
	end
	eq(Cfg.Contracts.Reward.Shards, 60)
	eq(Cfg.Contracts.Bonus.Keys, 1)
end)

---------------------------------------------------------------------------------------------------------------------
-- the Black Coffin
---------------------------------------------------------------------------------------------------------------------
test("coffin table sums to 100 000 with the documented chances", function()
	eq(R.CoffinTotal(Cfg), 100000)
	eq(Cfg.Coffin.Filler, 3682, "filler (100 000 - 96 318) goes to Lucky Dust")
	local byKey, keys = {}, {}
	for _, row in ipairs(Cfg.Coffin.Table) do
		truthy(not keys[row.Key], "unique key " .. row.Key)
		keys[row.Key] = true
		byKey[row.Key] = row
		truthy(({ Shards = 1, Dust = 1, Key = 1, Fragments = 1, Find = 1, Decor = 1, Skin = 1, Dog = 1, Bones = 1, Cash = 1 })[row.Kind], "kind " .. row.Kind)
	end
	near(R.CoffinChance(byKey.Dust, Cfg), .27682, 1e-12)
	near(R.CoffinChance(byKey.Shards, Cfg), .15, 1e-12)
	near(R.CoffinChance(byKey.Bones, Cfg), .08, 1e-12)
	near(R.CoffinChance(byKey.Coins, Cfg), .09, 1e-12)
	near(R.CoffinChance(byKey.Fragments, Cfg), .06, 1e-12)
	near(R.CoffinChance(byKey.Key, Cfg), .015, 1e-12)
	near(R.CoffinChance(byKey.HW_HollowKing, Cfg), 1 / 25000, 1e-15, "SECRET 1 in 25 000")
	near(R.CoffinChance(byKey.HW_BellkeeperWolf, Cfg), .00032, 1e-15)
	near(R.CoffinChance(byKey.HW_BellPup, Cfg), .0022, 1e-15)
	near(R.CoffinChance(byKey.uy_hollow_heart, Cfg), .007, 1e-15)
	near(R.CoffinChance(byKey.uy_coffin_nail, Cfg), .03, 1e-15)
	near(R.CoffinChance(byKey.uy_moon_statue, Cfg), .0015, 1e-15)
	near(R.CoffinChance(byKey.UY_TVHead, Cfg), .00095, 1e-15)
	truthy(byKey.UY_BellReaper == nil, "the Dex-only Secret skin is not in the coffin")
	local g = R.CoffinGroups(Cfg)
	near(g.Find, .299, 1e-12, "finds 29.9%")
	near(g.Decor, .015, 1e-12, "decor 1.5%")
	near(g.Skin, .0057, 1e-12, "skins 0.57%")
	near(g.Dog, .0078, 1e-12, "dogs 0.78%")
	near(g.Mythic, .00064, 1e-12, "mythic 0.064%")
	near(g.Secret, .00004, 1e-12, "secret 0.004%")
	local sum = 0
	for _, p in pairs(g) do
		sum += p
	end
	near(sum, 1, 1e-12)
	local finds = 0
	for _ in pairs(Cfg.Finds.Defs) do
		finds += 1
	end
	eq(finds, 15)
	eq(#Cfg.Decor.Order, 10)
	for _, grp in ipairs(Cfg.Coffin.Groups) do
		truthy(g[grp.Id], "display group " .. grp.Id)
	end
end)

test("coffin roll follows the weights, rolls amounts, forces groups, tags duplicates", function()
	local rng = R.Lcg(987654)
	local hits, n = {}, 200000
	for _ = 1, n do
		local row = R.CoffinRoll(rng, Cfg)
		hits[row.Group] = (hits[row.Group] or 0) + 1
		if row.Key == "Dust" then
			truthy(row.Amount >= 60 and row.Amount <= 120, "dust amount " .. tostring(row.Amount))
		elseif row.Key == "Shards" then
			truthy(row.Amount >= 40 and row.Amount <= 90 and row.Source == "Refund", "shards row")
		end
		truthy(row.Weight == nil and row.Min == nil, "rolled copy")
	end
	near(hits.Dust / n, .27682, .006, "dust frequency")
	near(hits.Find / n, .299, .006, "find frequency")
	near(hits.Shards / n, .15, .005, "shards frequency")
	for _ = 1, 500 do
		eq(R.CoffinRoll(rng, Cfg, nil, { Group = "Find" }).Group, "Find")
	end
	local owned = { Decor = { uy_spirit_fence = true }, Skins = { UY_TVHead = true }, Finds = { uy_wax_hand = true } }
	local rows = {}
	for _, row in ipairs(Cfg.Coffin.Table) do
		if row.Key == "uy_spirit_fence" or row.Key == "UY_TVHead" or row.Key == "uy_wax_hand" or row.Key == "uy_lost_veil" then
			table.insert(rows, row)
		end
	end
	local dup, fresh = 0, 0
	for _ = 1, 400 do
		local row = R.CoffinRoll(rng, Cfg, owned, { Rows = rows })
		if row.Key == "uy_lost_veil" then
			truthy(not row.Duplicate, "not owned")
			fresh += 1
		else
			truthy(row.Duplicate, "owned " .. row.Key)
			dup += 1
		end
	end
	truthy(dup > 0 and fresh > 0, "both kinds rolled")
	-- a Random-like object works too
	local obj = { NextNumber = function()
		return .99999
	end }
	eq(R.CoffinRoll(obj, Cfg).Key, Cfg.Coffin.Table[#Cfg.Coffin.Table].Key)
end)

test("duplicate conversion (§9.4) and the Coffin Pug bonus", function()
	local d = R.DuplicateConversion({ Kind = "Decor", Id = "uy_moon_statue" }, Cfg)
	eq(d[1].Kind, "Fragments")
	eq(d[1].Amount, 12)
	eq(d[2].Kind, "Dust")
	eq(d[2].Amount, 400)
	local s = R.DuplicateConversion({ Kind = "Skin", Id = "UY_TVHead" }, Cfg)
	eq(s[1].Amount, 25)
	eq(s[2].Amount, 800)
	local f = R.DuplicateConversion({ Kind = "Find", Id = "uy_wax_hand" }, Cfg)
	eq(#f, 2)
	eq(f[1].Kind, "Shards")
	eq(f[1].Amount, 80)
	eq(f[1].Source, "Duplicate")
	eq(f[2].Amount, 150)
	local leg = R.DuplicateConversion({ Kind = "Find", Id = "uy_hollow_heart" }, Cfg)
	eq(#leg, 3)
	eq(leg[3].Kind, "Fragments")
	eq(leg[3].Amount, 3)
	local pug = R.DuplicateConversion({ Kind = "Skin", Id = "UY_TVHead" }, Cfg, { CoffinPug = true })
	eq(pug[1].Amount, 31)
	eq(pug[2].Amount, 1000)
	local pugFind = R.DuplicateConversion({ Kind = "Find", Id = "uy_coffin_nail" }, Cfg, { CoffinPug = true })
	eq(pugFind[1].Amount, 100)
	eq(pugFind[2].Amount, 188)
	local dog = R.DuplicateConversion({ Kind = "Dog", Id = "HW_HollowKing" }, Cfg)
	eq(dog[1].Amount, 900, "undeliverable rank 6 dog")
	eq(R.DuplicateConversion({ Kind = "Shards" }, Cfg), nil)
	eq(R.DuplicateConversion(nil, Cfg), nil)
end)

---------------------------------------------------------------------------------------------------------------------
-- Chapter I completion
---------------------------------------------------------------------------------------------------------------------
test("Chapter1Complete on sample profiles (complete, partial, missing and legacy fields)", function()
	local full = { Halloween = { Boss = { Best = 2 }, Cauldron = { Invested = 300 }, Stats = { Knocks = 7, BloodMoons = 1, Spots = 10 } } }
	local ok, list = R.Chapter1Complete(full, Cfg)
	truthy(ok, "complete")
	eq(#list, 5)
	for _, row in ipairs(list) do
		truthy(row.Done and row.Goal > 0 and type(row.Text) == "table", "row " .. row.Key)
	end
	local partial = { Halloween = { Boss = { Best = 1 }, Cauldron = { Invested = 1250 }, Stats = { Knocks = 30, BloodMoons = 4, Spots = 2 } } }
	ok, list = R.Chapter1Complete(partial, Cfg)
	eq(ok, false)
	local done = 0
	for _, row in ipairs(list) do
		if row.Done then
			done += 1
		end
	end
	eq(done, 3, "boss I and 2 spots missing")
	eq(list[1].Value, 1)
	eq(list[1].Goal, 2)
	for _, p in ipairs({ {}, { Halloween = "x" }, { Halloween = { Boss = 5 } }, { Halloween = { Boss = { Best = 0 / 0 },
		Cauldron = { Invested = "300" }, Stats = { Knocks = math.huge } } }, "garbage" }) do
		local okP, rows = R.Chapter1Complete(p, Cfg)
		eq(okP, false)
		eq(#rows, 5)
	end
	-- a legacy profile without Stats.Spots (older save) is simply not complete yet
	local legacy = { Halloween = { Boss = { Best = 5, Kills = 9 }, Cauldron = { Invested = 650 }, Stats = { Knocks = 9, BloodMoons = 3 } } }
	eq((R.Chapter1Complete(legacy, Cfg)), false)
	legacy.Halloween.Stats.Spots = 10
	eq((R.Chapter1Complete(legacy, Cfg)), true)
end)

---------------------------------------------------------------------------------------------------------------------
-- dex II, craft, keys, doors, exchange, tutorial
---------------------------------------------------------------------------------------------------------------------
test("dex II count / milestones, tailor prices, key cap, doors, exchange", function()
	local p = { DogDex = { HW_BellPup = true, HW_CandleCorgi = true, HW_MothHound = true, HW_PumpkinPup = true } }
	eq(R.Dex2Count(p, Cfg), 3, "only H09-H16 count")
	local claim = R.Dex2Claimable(p, Cfg)
	eq(#claim, 1)
	eq(claim[1], 3)
	p.Underyard = { Dex2Claims = { ["3"] = true } }
	eq(#R.Dex2Claimable(p, Cfg), 0)
	eq(R.Dex2Reward(8, Cfg).Rows[2].Id, "HollowCrown2026")
	eq(R.Dex2Reward(4, Cfg), nil)
	eq(R.Dex2Count({}, Cfg), 0)
	eq(select(1, R.CraftCost("uy_spirit_fence", Cfg)), 45)
	eq(select(2, R.CraftCost("uy_spirit_fence", Cfg)), "Decor")
	eq(select(1, R.CraftCost("UY_TVHead", Cfg)), 90)
	local c, why = R.CraftCost("UY_BellReaper", Cfg)
	eq(c, nil)
	eq(why, "This skin only comes from the Dex II")
	eq(select(1, R.CraftCost("nope", Cfg)), nil)
	local keys, got, over = R.AddKeys(10, 5, Cfg)
	eq(keys, 12)
	eq(got, 2)
	eq(over, 3)
	eq(R.DoorsPerDay({}, Cfg), 3)
	eq(R.DoorsPerDay({ Daily = { Contracts = { AllClaimed = true } } }, Cfg), 4)
	local s, candy = R.ExchangeQuote(40, 0, Cfg)
	eq(s, 40)
	eq(candy, 1000)
	s, candy = R.ExchangeQuote(30, 25, Cfg)
	eq(s, 15)
	eq(candy, 375)
	eq(select(1, R.ExchangeQuote(5, 40, Cfg)), 0)
	eq(select(1, R.ExchangeQuote(999, 0, Cfg)), 40)
	eq(R.TutorialStep(3, Cfg).Event, "Coffin")
	eq(R.TutorialStep(3, Cfg).Grant.Keys, 1)
	eq(R.TutorialStep(3, Cfg).Grant.Shards, 150)
	eq(R.TutorialStep(99, Cfg), nil)
end)

test("config contract: seals, dogs, keys, quality keys, numbers other packages read", function()
	eq(#Cfg.Seals, 7)
	for i, seal in ipairs(Cfg.Seals) do
		eq(seal.Index, i)
		truthy(type(seal.Name) == "table" and type(seal.Title) == "table" and type(seal.Text) == "table", "texts " .. i)
		truthy(seal.Rewards.First >= 150 and seal.Rewards.First <= 400, "first " .. i)
		truthy(seal.Rewards.Repeat >= 20 and seal.Rewards.Repeat <= 60, "repeat " .. i)
		eq(seal.Rewards.Keys, 1)
		eq(seal.GoldRewards.Keys, 1)
		truthy(seal.Trial.TimeLimit >= 0 and seal.Trial.Goal >= 1, "trial " .. i)
	end
	eq(Cfg.Seals[1].Rewards.Rows[1].Id, "HW_BellPup")
	eq(Cfg.Seals[4].Rewards.Rows[1].Id, "HW_CandleCorgi")
	eq(Cfg.Seals[7].Rewards.Rows[1].Id, "HW_MourningShiba")
	eq(Cfg.Seals[7].Rewards.Rows[2].Id, "uy_crooked_bell_tower")
	eq(Cfg.Seals[1].Trial.TimeLimit, 90)
	eq(Cfg.Seals[2].Gold.Time, 55)
	eq(Cfg.Seals[6].Trial.TimeLimit, 480)
	eq(#Cfg.Dogs.Order, 8)
	for i, id in ipairs(Cfg.Dogs.Order) do
		eq(Cfg.Dogs.Defs[id].Index, 208 + i)
		eq(Cfg.Dogs.Defs[id].EventIndex, 8 + i)
	end
	eq(Cfg.Coffin.MaxKeys, 12)
	eq(Cfg.Coffin.Price.Shards, 150)
	for _, tier in ipairs({ "High", "Medium", "Low" }) do
		for _, key in ipairs({ "UnderMotes", "Telegraph", "FinaleFX", "CalendarFX", "CoffinFX", "GhostLights" }) do
			truthy(type(Cfg.Quality[tier][key]) == "number", tier .. "." .. key)
		end
	end
	eq(Cfg.Quality.High.UnderMotes, 60)
	eq(Cfg.Quality.Low.GhostLights, 5)
	eq(Cfg.Boss.ArmorExp, .42)
	eq(Cfg.Boss.DifficultyMult[5], 1.5)
	eq(Cfg.Combat.MaxHP, 100)
	eq(Cfg.Finale.Rewards.First.Keys, 3)
	eq(Cfg.Exchange.CandyPerShard, 25)
	eq(Cfg.Rested.Cap, 1200)
	eq(#Cfg.Tutorial.Steps, 6)
	eq(#Cfg.Contracts.Pool, 11)
	for _, key in ipairs(Cfg.Journal.Order) do
		truthy(Cfg.Journal.Entries[key], "journal " .. key)
	end
end)

print(string.format("chapter2_rules: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("chapter2_rules tests failed")
end
