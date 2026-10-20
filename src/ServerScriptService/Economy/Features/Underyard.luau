-- CHAPTER II · THE UNDERYARD progress (Economy.FeatureRegistry feature, Order 75; docs/halloween2/DESIGN.md §3.2).
-- Saved data (created lazily by the first Chapter II transaction / the first join while Chapter II is on):
--   p.Underyard = {Version = 1,
--     Chapter1 = {Complete, At, Notified},                 latched once true (Chapter2Rules.Chapter1Complete), never un-set
--     RevealSeen, RevealAt, Entered, FirstEnterAt,         church cinematic watched / first portal descent
--     Tutorial = {Step, Done, Refunded, Mark},              Chapter II onboarding (Chapter2Config.Tutorial.Steps)
--     Seals = {["1"] = {Offered, Cleared, Gold, At, Best, Progress}, ... ["7"]},
--     Keys, Fragments,                                      Coffin Keys (cap Coffin.MaxKeys) and cosmetic fragments
--     Daily = {Day, Raw, Eff, Rested, Exchange, Doors, Keys, Resonance,
--              Contracts = {Day, List = {{Id, Goal, Progress, Claimed}}, AllClaimed}},
--     Rested = {Day, Pool},                                 catch-up allowance (§8.3); Day = last full day accounted
--     Dex2Claims = {["3"] = true}, Owned = {Decor = {[id] = true}, Finds = {[id] = true}},
--     Journal = {[key] = unlockedAt}, JournalRead = {[key] = true},
--     Coffins = {Opened, Last = {{Key, Kind, Id, Amount, Rank, Converted, At}}, Crown = {Seconds, Rolls}},
--     PendingDogs = {{Id, Variant, Rank, Source, At}},     dogs won while the dog storage was full (delivered later)
--     Boss = {FinaleClears, FirstClears = {["3"] = true, ...}},
--     Stats = {Perfect, Streaks, Trials, Doors, Spirits, Revives, Downs, ShardsEarned}}
-- Bell Shards / Lucky Dust are p.Resources kinds (DogEconomy.Resources), pickaxe skins p.Halloween.Skins, plot cosmetics
-- p.Decor, showcase finds p.Items, event dogs p.Dogs. Every mutation happens in ServerScriptService.Halloween.Chapter2
-- (Chapter2.Transact); this module only shapes, validates and describes the data. It never requires Rules / Runtime
-- (FeatureRegistry loads it while Rules loads) and keeps unknown keys (a rolled-back server must not erase newer data).
local RS = game:GetService("ReplicatedStorage")

local F = { Name = "Underyard", Order = 75 }

local cache = {}
local function load(name: string): any
	if cache[name] ~= nil then
		return cache[name] or nil
	end
	local folder = RS:FindFirstChild("Halloween")
	local mod = folder and folder:FindFirstChild(name)
	local ok, res = false, nil
	if mod then
		ok, res = pcall(require, mod)
	end
	cache[name] = ok and type(res) == "table" and res or false
	return cache[name] or nil
end
local function C(): any
	return load("Chapter2Config")
end
local function Rules(): any
	return load("Chapter2Rules")
end
F.Config = C
F.Rules = Rules

local MAX = 1e12
local function int(v: any, max: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
		return 0
	end
	return math.min(math.floor(v), max or MAX)
end
local function day(v: any): number
	return type(v) == "number" and v == v and v > -1e9 and v < 1e9 and math.floor(v) or -1
end
local function float(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
		return 0
	end
	return math.min(v, MAX)
end
local function tbl(t: any): { [any]: any }
	return type(t) == "table" and t or {}
end
local function bool(v: any): boolean
	return v == true
end
local function stringSet(t: any, maxKeys: number): { [string]: boolean }
	local out, n = {}, 0
	for k, v in pairs(tbl(t)) do
		if type(k) == "string" and #k <= 60 and v == true then
			n += 1
			if n > maxKeys then
				break
			end
			out[k] = true
		end
	end
	return out
end
-- {[key] = unix time} (legacy true -> 0)
local function timeSet(t: any, maxKeys: number): { [string]: number }
	local out, n = {}, 0
	for k, v in pairs(tbl(t)) do
		if type(k) == "string" and #k <= 40 and (v == true or type(v) == "number") then
			n += 1
			if n > maxKeys then
				break
			end
			out[k] = v == true and 0 or int(v)
		end
	end
	return out
end

local SEALS = 7
F.Stats = { "Perfect", "Streaks", "Trials", "Doors", "Spirits", "Revives", "Downs", "ShardsEarned" }

local function shapeDaily(d: any, limits: any): any
	d = tbl(d)
	d.Day = day(d.Day)
	d.Raw = int(d.Raw)
	d.Rested = int(d.Rested)
	d.Eff = float(d.Eff)
	d.Exchange = int(d.Exchange, 1e6)
	d.Doors = int(d.Doors, 1e6)
	d.Keys = int(d.Keys, 1e6)
	d.Resonance = int(d.Resonance)
	local c = tbl(d.Contracts)
	d.Contracts = c
	c.Day = day(c.Day)
	local list = {}
	for _, row in ipairs(tbl(c.List)) do
		if type(row) == "table" and type(row.Id) == "string" and #row.Id <= 40 then
			table.insert(list, { Id = row.Id, Goal = math.max(1, int(row.Goal, 1e9)), Progress = int(row.Progress, 1e9),
				Claimed = row.Claimed == true })
		end
		if #list >= (limits.Contracts or 6) then
			break
		end
	end
	c.List = list
	c.AllClaimed = c.AllClaimed == true
	return d
end

-- create / heal in place; never throws on any input it can index; keeps unknown keys
function F.Shape(p: any): any
	local u = p.Underyard
	if type(u) ~= "table" then
		u = {}
		p.Underyard = u
	end
	local cfg = C() or {}
	local limits = cfg.Limits or {}
	local maxKeys = cfg.Coffin and cfg.Coffin.MaxKeys or 12
	u.Version = 1
	local c1 = tbl(u.Chapter1)
	u.Chapter1 = c1
	c1.Complete = bool(c1.Complete)
	c1.At = int(c1.At)
	c1.Notified = bool(c1.Notified)
	u.RevealSeen = bool(u.RevealSeen)
	u.RevealAt = int(u.RevealAt)
	u.Entered = bool(u.Entered)
	u.FirstEnterAt = int(u.FirstEnterAt)
	local tut = tbl(u.Tutorial)
	u.Tutorial = tut
	tut.Step = int(tut.Step, 99)
	tut.Done = bool(tut.Done)
	tut.Refunded = bool(tut.Refunded)
	tut.Mark = int(tut.Mark) -- the counter value when the current step began (steps that count from their start)
	local seals = tbl(u.Seals)
	u.Seals = seals
	for i = 1, SEALS do
		local key = tostring(i)
		local s = tbl(seals[key])
		seals[key] = s
		s.Offered = bool(s.Offered)
		s.Cleared = bool(s.Cleared)
		s.Gold = bool(s.Gold) and s.Cleared
		s.Offered = s.Offered or s.Cleared -- a cleared seal was always offered (debug / legacy grants)
		s.At = int(s.At)
		s.Best = int(s.Best, 1e9)
		s.Progress = int(s.Progress, 1e6) -- persistent activity progress (Seal V: door outcomes across days)
	end
	u.Keys = int(u.Keys, maxKeys)
	u.Fragments = int(u.Fragments, cfg.Craft and cfg.Craft.MaxFragments or 99999)
	u.Daily = shapeDaily(u.Daily, limits)
	local rested = tbl(u.Rested)
	u.Rested = rested
	rested.Day = day(rested.Day)
	rested.Pool = int(rested.Pool, cfg.Rested and cfg.Rested.Cap or 750)
	u.Dex2Claims = stringSet(u.Dex2Claims, limits.Dex2Claims or 8)
	local owned = tbl(u.Owned)
	u.Owned = owned
	owned.Decor = stringSet(owned.Decor, limits.OwnedDecor or 40)
	owned.Finds = stringSet(owned.Finds, limits.OwnedFinds or 40)
	u.Journal = timeSet(u.Journal, limits.Journal or 40)
	u.JournalRead = stringSet(u.JournalRead, limits.Journal or 40)
	local coffins = tbl(u.Coffins)
	u.Coffins = coffins
	coffins.Opened = int(coffins.Opened)
	local last = {}
	for _, row in ipairs(tbl(coffins.Last)) do
		if type(row) == "table" and type(row.Key) == "string" and #row.Key <= 40 then
			table.insert(last, { Key = row.Key, Kind = type(row.Kind) == "string" and string.sub(row.Kind, 1, 20) or "",
				Id = type(row.Id) == "string" and string.sub(row.Id, 1, 40) or nil, Amount = int(row.Amount),
				Rank = int(row.Rank, 6), Converted = row.Converted == true or nil, At = int(row.At) })
		end
		if #last >= (limits.CoffinLast or 10) then
			break
		end
	end
	coffins.Last = last
	local crown = tbl(coffins.Crown)
	coffins.Crown = crown
	crown.Seconds = int(crown.Seconds, 1e7)
	crown.Rolls = int(crown.Rolls, 9)
	local pendingDogs = {}
	for _, row in ipairs(tbl(u.PendingDogs)) do
		if type(row) == "table" and type(row.Id) == "string" and #row.Id <= 40 then
			table.insert(pendingDogs, { Id = row.Id, Variant = type(row.Variant) == "string" and string.sub(row.Variant, 1, 40) or nil,
				Rank = int(row.Rank, 6), Source = type(row.Source) == "string" and string.sub(row.Source, 1, 20) or "", At = int(row.At) })
		end
		if #pendingDogs >= (limits.PendingDogs or 12) then
			break
		end
	end
	u.PendingDogs = pendingDogs
	local boss = tbl(u.Boss)
	u.Boss = boss
	boss.FinaleClears = int(boss.FinaleClears)
	boss.FirstClears = stringSet(boss.FirstClears, 8)
	local stats = tbl(u.Stats)
	u.Stats = stats
	for _, k in ipairs(F.Stats) do
		stats[k] = int(stats[k], limits.Stat or MAX)
	end
	return u
end

function F.Normalize(_R: any, p: any, _now: number)
	if p.Underyard == nil then
		return
	end
	local ok = pcall(F.Shape, p)
	if not ok then
		-- never lock a player out over one corrupt sub-table and never silently erase it: park the old copy under a
		-- top-level key nobody touches, start a clean table
		p.UnderyardBroken = p.Underyard
		p.Underyard = nil
		pcall(F.Shape, p)
	end
end

function F.Validate(R: any, p: any)
	local u = p.Underyard
	if u == nil then
		return
	end
	local cfg = C() or {}
	local maxKeys = cfg.Coffin and cfg.Coffin.MaxKeys or 12
	R.Check(type(u) == "table", "Invalid Underyard progress")
	R.Check(type(u.Keys) == "number" and u.Keys >= 0 and u.Keys <= maxKeys and u.Keys == math.floor(u.Keys), "Invalid Coffin Keys")
	R.Check(type(u.Fragments) == "number" and u.Fragments >= 0 and u.Fragments == math.floor(u.Fragments), "Invalid fragments")
	R.Check(type(u.Seals) == "table" and type(u.Daily) == "table" and type(u.Chapter1) == "table", "Invalid Underyard progress")
end

---------------------------------------------------------------------------------------------------------------------
-- Daily state (UTC day): DR counters, exchange, doors, resonance keys, contracts; the rested allowance of the days that
-- passed is accounted before the reset
---------------------------------------------------------------------------------------------------------------------
function F.Cleared(u: any): number
	local n = 0
	for i = 1, SEALS do
		if tbl(tbl(tbl(u).Seals)[tostring(i)]).Cleared == true then
			n += 1
		end
	end
	return n
end

function F.EnsureDaily(p: any, now: number): boolean
	local u = F.Shape(p)
	local cfg, rules = C(), Rules()
	if not cfg or not rules then
		return false
	end
	local today = rules.Day(now)
	if u.Daily.Day == today then
		return false
	end
	rules.RestedUpdate(u.Rested, u.Daily, today, cfg)
	u.Daily = {
		Day = today, Raw = 0, Eff = 0, Rested = 0, Exchange = 0, Doors = 0, Keys = 0, Resonance = 0,
		Contracts = { Day = today, List = rules.PickContracts(tonumber(p.UserId) or 0, today, cfg, F.Cleared(u)), AllClaimed = false },
	}
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Client view (embedded in the Halloween view as .Chapter2, snapshot.Features.Underyard)
---------------------------------------------------------------------------------------------------------------------
local function phaseOverride(): number?
	local ok, v = pcall(function()
		local folder = RS:FindFirstChild("Halloween")
		local st = folder and folder:FindFirstChild("State")
		local c2 = st and st:FindFirstChild("Chapter2")
		return c2 and c2:GetAttribute("PhaseOverride")
	end)
	return ok and type(v) == "number" and v or nil
end
F.PhaseOverride = phaseOverride

local function copySet(t: any): { [string]: any }
	local out = {}
	for k, v in pairs(tbl(t)) do
		out[k] = v
	end
	return out
end

function F.View(p: any, now: number): any
	local cfg, rules = C(), Rules()
	if not cfg or not rules then
		return { Fresh = true }
	end
	local fresh = type(p.Underyard) ~= "table"
	local u
	if fresh then
		local tmp = { UserId = p.UserId }
		u = F.Shape(tmp)
	else
		u = p.Underyard
	end
	local override = phaseOverride()
	local complete, checklist = rules.Chapter1Complete(p, cfg)
	local done = 0
	for _, row in ipairs(checklist) do
		if row.Done then
			done += 1
		end
	end
	local seals = {}
	for i, seal in ipairs(cfg.Seals) do
		local s = u.Seals[tostring(i)] or {}
		local cost, discounted = rules.OfferingCost(i, now, cfg)
		local open = rules.SealOpen(i, now, cfg, override)
		local prev = i == 1 or (u.Seals[tostring(i - 1)] or {}).Cleared == true
		seals[i] = {
			Index = i, Id = seal.Id, Offered = s.Offered == true, Cleared = s.Cleared == true, Gold = s.Gold == true,
			At = s.At or 0, Best = s.Best or 0, Open = open, OpensAt = rules.SealOpensAt(i, cfg), Cost = cost, Discount = discounted,
			Previous = prev, Playable = open and prev and s.Offered == true,
		}
	end
	local daily = u.Daily
	local today = rules.Day(now)
	local current = daily.Day == today
	local rate, left = rules.DRRate(current and daily.Raw or 0, cfg)
	local contracts = {}
	for _, row in ipairs(current and daily.Contracts.List or {}) do
		table.insert(contracts, { Id = row.Id, Goal = row.Goal, Progress = row.Progress, Claimed = row.Claimed })
	end
	local dexHave = {}
	for _, id in ipairs(cfg.Dogs.Order) do
		dexHave[id] = type(p.DogDex) == "table" and p.DogDex[id] == true or false
	end
	local last = {}
	for _, row in ipairs(u.Coffins.Last) do
		table.insert(last, copySet(row))
	end
	local pending = {}
	for _, row in ipairs(u.PendingDogs) do
		table.insert(pending, { Id = row.Id, Rank = row.Rank, Source = row.Source, At = row.At })
	end
	local tutorialStep = u.Tutorial.Done and -1 or u.Tutorial.Step
	return {
		Fresh = fresh or nil, Version = u.Version,
		Chapter1 = { Complete = u.Chapter1.Complete, At = u.Chapter1.At, Notified = u.Chapter1.Notified, Ready = complete,
			Checklist = checklist, Done = done, Total = #checklist },
		RevealSeen = u.RevealSeen, RevealAt = u.RevealAt, Entered = u.Entered, FirstEnterAt = u.FirstEnterAt,
		Tutorial = { Step = u.Tutorial.Step, Done = u.Tutorial.Done, Current = tutorialStep, Total = #cfg.Tutorial.Steps },
		Seals = seals, Cleared = F.Cleared(u), Mask = rules.SealMask(u.Seals, cfg),
		Phase = rules.Phase(now, cfg, override), NextPhaseAt = rules.NextPhaseAt(now, cfg, override),
		Shards = type(p.Resources) == "table" and int(p.Resources.BellShards) or 0,
		Dust = type(p.Resources) == "table" and int(p.Resources.LuckyDust) or 0,
		Keys = u.Keys, MaxKeys = cfg.Coffin.MaxKeys, Fragments = u.Fragments,
		Daily = {
			Day = daily.Day, Today = today, ResetIn = rules.SecondsToNextDay(now), Raw = current and daily.Raw or 0,
			Rested = current and daily.Rested or 0, Eff = current and math.floor(daily.Eff * 100 + .5) / 100 or 0,
			Rate = rate, TierLeft = left == math.huge and -1 or left,
			Exchange = current and daily.Exchange or 0, ExchangeMax = cfg.Exchange.MaxPerDay,
			Doors = current and daily.Doors or 0, DoorsMax = rules.DoorsPerDay(current and u or {}, cfg),
			Keys = current and daily.Keys or 0, Resonance = current and daily.Resonance or 0,
		},
		Contracts = { Day = daily.Contracts.Day, Today = today, List = contracts, AllClaimed = current and daily.Contracts.AllClaimed or false },
		Rested = { Pool = u.Rested.Pool, Cap = cfg.Rested.Cap },
		Dex2 = { Count = rules.Dex2Count(p, cfg), Total = #cfg.Dogs.Order, Claims = copySet(u.Dex2Claims), Dex = dexHave,
			Claimable = rules.Dex2Claimable({ DogDex = p.DogDex, Underyard = u }, cfg) },
		Owned = { Decor = copySet(u.Owned.Decor), Finds = copySet(u.Owned.Finds) },
		Journal = copySet(u.Journal), JournalRead = copySet(u.JournalRead),
		Coffins = { Opened = u.Coffins.Opened, Last = last, CrownRolls = u.Coffins.Crown.Rolls },
		PendingDogs = pending,
		Boss = { FinaleClears = u.Boss.FinaleClears, FirstClears = copySet(u.Boss.FirstClears) },
		Stats = copySet(u.Stats),
	}
end

function F.Snapshot(_R: any, p: any, view: any, now: number)
	view.Underyard = F.View(p, now)
end

return F
