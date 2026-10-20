-- NIGHT OF THE BURIED MOON progress (Economy.FeatureRegistry feature; ServerScriptService.Economy.Features.Halloween).
-- Saved data (created on the first Halloween transaction; absent on every other profile):
--   p.Halloween = {Version, Season, Candy, Lifetime, Spent, Curse,
--     Cauldron = {Level, Invested, StartedAt, Claimed, Tricks},
--     Quests = {Day, List = {{Id, Goal, Progress, Claimed}}, AllClaimed},
--     Houses = {Day, Knocked = {["1"] = true}}, Rush = {Day, Remaining, Active},
--     Skins = {[skinId] = true}, Skin = "", DexClaims = {["2"] = true}, Boss = {Unlocked, Kills, Best},
--     Onboarded, Seen = {[key] = true}, Stats = {Ore, Spots, Perfect, BossDamage, Knocks, Pumpkins, Mutations, BloodMoons, Tricks}}
-- Skins holds the pickaxe skins of both chapters (Chapter II ids UY_*; up to 64). The view also carries .Chapter2, the
-- CHAPTER II view of Economy.Features.Underyard (p.Underyard), so every Halloween reply / View push updates both.
-- Every mutation happens in ServerScriptService.Halloween (Core.Transact). This module only shapes, validates and
-- describes the data; it never requires Rules/Runtime (FeatureRegistry loads it while Rules loads).
-- Event dogs, mutated finds, pumpkin blocks and decor live in the normal profile tables and stay after the event.
local RS = game:GetService("ReplicatedStorage")

local F = { Name = "Halloween", Order = 70 }

local configCache = nil
local function C()
	if configCache then
		return configCache
	end
	local folder = RS:FindFirstChild("Halloween")
	local mod = folder and folder:FindFirstChild("Config")
	if mod then
		local ok, res = pcall(require, mod)
		if ok then
			configCache = res
		end
	end
	return configCache or { Season = "NOTBM_2026", HalloweenEventEnabled = false, Quests = { PerDay = 0, Pool = {}, Always = {} },
		Cauldron = { Levels = { { Level = 1, Cost = 0 } }, BrewSeconds = 604800 }, CandyRush = { Seconds = 600 }, Skins = { Order = {} },
		DexRewards = {}, Dogs = { Defs = {}, Order = {} }, TrickOrTreat = { Houses = 7 } }
end
F.Config = C

local MAX = 1e12
local function int(v: any, max: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
		return 0
	end
	return math.min(math.floor(v), max or MAX)
end
local function num(v: any, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v then
		return lo
	end
	return math.clamp(v, lo, hi)
end
local function tbl(t: any): { [any]: any }
	return type(t) == "table" and t or {}
end
local function stringSet(t: any, maxKeys: number?): { [string]: boolean }
	local out = {}
	local n = 0
	for k, v in pairs(tbl(t)) do
		if type(k) == "string" and #k <= 60 and v == true then
			n += 1
			if n > (maxKeys or 200) then
				break
			end
			out[k] = true
		end
	end
	return out
end

function F.Day(now: number): number
	return math.floor(now / 86400)
end

local STATS = { "Ore", "Spots", "Perfect", "BossDamage", "Knocks", "Pumpkins", "Mutations", "BloodMoons", "Tricks", "Treasures" }

-- create / heal in place; never throws; keeps unknown keys (a rolled-back server must not erase newer data)
function F.Shape(p: any): any
	local h = p.Halloween
	if type(h) ~= "table" then
		h = {}
		p.Halloween = h
	end
	local cfg = C()
	h.Version = 1
	if h.Season ~= cfg.Season then
		-- a new season keeps cosmetics and lifetime counters, everything else starts over
		h.Season = cfg.Season
		h.Candy, h.Spent, h.Curse = 0, 0, 0
		h.Cauldron, h.Quests, h.Houses, h.Rush, h.DexClaims, h.Onboarded, h.Seen = nil, nil, nil, nil, nil, false, nil
	end
	h.Candy = int(h.Candy)
	h.Lifetime = math.max(int(h.Lifetime), h.Candy)
	h.Spent = int(h.Spent)
	h.Curse = num(h.Curse, 0, 100)
	local c = tbl(h.Cauldron)
	h.Cauldron = c
	c.Level = math.clamp(int(c.Level), 1, math.max(1, #cfg.Cauldron.Levels))
	c.Invested = int(c.Invested)
	c.StartedAt = int(c.StartedAt)
	c.Claimed = c.Claimed == true
	c.Tricks = int(c.Tricks)
	local q = tbl(h.Quests)
	h.Quests = q
	q.Day = type(q.Day) == "number" and math.floor(q.Day) or -1
	local list = {}
	for _, row in ipairs(tbl(q.List)) do
		if type(row) == "table" and type(row.Id) == "string" and #row.Id <= 40 then
			table.insert(list, { Id = row.Id, Goal = math.max(1, int(row.Goal, 1e9)), Progress = int(row.Progress, 1e9), Claimed = row.Claimed == true })
		end
		if #list >= 12 then
			break
		end
	end
	q.List = list
	q.AllClaimed = q.AllClaimed == true
	local houses = tbl(h.Houses)
	h.Houses = houses
	houses.Day = type(houses.Day) == "number" and math.floor(houses.Day) or -1
	houses.Knocked = stringSet(houses.Knocked, 20)
	local rush = tbl(h.Rush)
	h.Rush = rush
	rush.Day = type(rush.Day) == "number" and math.floor(rush.Day) or -1
	rush.Remaining = math.min(int(rush.Remaining), cfg.CandyRush.Seconds)
	rush.Active = rush.Active == true and rush.Remaining > 0
	h.Skins = stringSet(h.Skins, 64) -- Chapter I + Chapter II pickaxe skins (was 40)
	h.Skin = type(h.Skin) == "string" and h.Skins[h.Skin] and h.Skin or ""
	h.DexClaims = stringSet(h.DexClaims, 20)
	local boss = tbl(h.Boss)
	h.Boss = boss
	boss.Unlocked = math.clamp(int(boss.Unlocked), 1, 5)
	boss.Kills = int(boss.Kills)
	boss.Best = math.clamp(int(boss.Best), 0, 5)
	h.Onboarded = h.Onboarded == true
	h.Seen = stringSet(h.Seen, 60)
	local stats = tbl(h.Stats)
	h.Stats = stats
	for _, k in ipairs(STATS) do
		stats[k] = int(stats[k])
	end
	return h
end

function F.Normalize(_R: any, p: any, _now: number)
	if p.Halloween ~= nil then
		local ok = pcall(F.Shape, p)
		if not ok then
			p.Halloween = nil -- never let a corrupt sub-table break the economy tick
		end
	end
end

function F.Validate(R: any, p: any)
	local h = p.Halloween
	if h == nil then
		return
	end
	R.Check(type(h) == "table", "Invalid Halloween progress")
	R.Check(type(h.Candy) == "number" and h.Candy >= 0 and h.Candy <= MAX and h.Candy == math.floor(h.Candy), "Invalid Candy balance")
	R.Check(type(h.Cauldron) == "table" and type(h.Quests) == "table" and type(h.Skins) == "table", "Invalid Halloween progress")
end

---------------------------------------------------------------------------------------------------------------------
-- Daily state (quests, houses, candy rush): reset at the UTC day boundary
---------------------------------------------------------------------------------------------------------------------
local function pickQuests(uid: number, day: number): { any }
	local cfg = C().Quests
	local rng = Random.new((uid % 2147483) * 7919 + day * 104729)
	local chosen, used = {}, {}
	local byId = {}
	for _, row in ipairs(cfg.Pool) do
		byId[row.Id] = row
	end
	for _, id in ipairs(cfg.Always or {}) do
		if byId[id] and #chosen < cfg.PerDay then
			table.insert(chosen, byId[id])
			used[id] = true
		end
	end
	local rest = {}
	for _, row in ipairs(cfg.Pool) do
		if not used[row.Id] then
			table.insert(rest, row)
		end
	end
	while #chosen < cfg.PerDay and #rest > 0 do
		local i = rng:NextInteger(1, #rest)
		table.insert(chosen, table.remove(rest, i))
	end
	local out = {}
	for _, row in ipairs(chosen) do
		table.insert(out, { Id = row.Id, Goal = row.Goal, Progress = 0, Claimed = false })
	end
	return out
end

function F.EnsureDaily(p: any, now: number): boolean
	local h = F.Shape(p)
	local day = F.Day(now)
	local changed = false
	if h.Quests.Day ~= day then
		h.Quests = { Day = day, List = pickQuests(tonumber(p.UserId) or 0, day), AllClaimed = false }
		changed = true
	end
	if h.Houses.Day ~= day then
		h.Houses = { Day = day, Knocked = {} }
		changed = true
	end
	if h.Rush.Day ~= day then
		h.Rush = { Day = day, Remaining = C().CandyRush.Seconds, Active = false }
		changed = true
	end
	return changed
end

function F.QuestDef(id: string)
	for _, row in ipairs(C().Quests.Pool) do
		if row.Id == id then
			return row
		end
	end
	return nil
end

-- returns the quest row when this progress just completed it
function F.QuestProgress(p: any, id: string, n: number, now: number): any
	F.EnsureDaily(p, now)
	local h = p.Halloween
	for _, row in ipairs(h.Quests.List) do
		if row.Id == id and not row.Claimed and row.Progress < row.Goal then
			row.Progress = math.min(row.Goal, row.Progress + math.max(0, math.floor(n)))
			if row.Progress >= row.Goal then
				return row
			end
		end
	end
	return nil
end

function F.AddCandy(p: any, n: number): number
	local h = F.Shape(p)
	n = int(n)
	local room = math.max(0, (C().Candy and C().Candy.Max or MAX) - h.Candy)
	n = math.min(n, room)
	h.Candy += n
	h.Lifetime = math.min(MAX, h.Lifetime + n)
	return n
end

function F.Spend(R: any, p: any, n: number)
	local h = F.Shape(p)
	n = int(n)
	R.Check(h.Candy >= n, "Not enough Candy")
	h.Candy -= n
	h.Spent += n
end

function F.HasSkin(p: any, id: string): boolean
	local h = type(p) == "table" and p.Halloween
	return type(h) == "table" and type(h.Skins) == "table" and h.Skins[id] == true
end

-- cumulative candy needed to reach each cauldron level
function F.CauldronThresholds(): { number }
	local out, sum = {}, 0
	for i, row in ipairs(C().Cauldron.Levels) do
		sum += row.Cost or 0
		out[i] = sum
	end
	return out
end

function F.EventDexCount(p: any): number
	local n = 0
	for id in pairs(C().Dogs.Defs) do
		if type(p.DogDex) == "table" and p.DogDex[id] then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------------
-- Client view (snapshot.Features.Halloween and every Halloween request reply)
---------------------------------------------------------------------------------------------------------------------
-- CHAPTER II view (Features.Underyard.View), never able to break the Chapter I view
local underyard: any = nil
local function chapter2View(p: any, now: number): any
	if underyard == nil then
		local mod = script.Parent:FindFirstChild("Underyard")
		local ok, res = false, nil
		if mod then
			ok, res = pcall(require, mod)
		end
		underyard = ok and type(res) == "table" and type(res.View) == "function" and res or false
	end
	if not underyard then
		return nil
	end
	local ok, view = pcall(underyard.View, p, now)
	return ok and view or nil
end
F.Chapter2View = chapter2View

function F.View(p: any, now: number): any
	local cfg = C()
	local h = type(p.Halloween) == "table" and p.Halloween or nil
	if not h then
		return { Season = cfg.Season, Enabled = cfg.HalloweenEventEnabled, Candy = 0, Lifetime = 0, Fresh = true,
			Chapter2 = chapter2View(p, now) }
	end
	local quests = {}
	for _, row in ipairs(h.Quests.List or {}) do
		local def = F.QuestDef(row.Id) or {}
		table.insert(quests, { Id = row.Id, Goal = row.Goal, Progress = row.Progress, Claimed = row.Claimed, Text = def.Text,
			Candy = def.Candy, Bones = def.Bones })
	end
	local c = h.Cauldron
	local thresholds = F.CauldronThresholds()
	local brew = cfg.Cauldron.BrewSeconds
	local okShared, Shared = pcall(function()
		return require(RS.Halloween.Shared)
	end)
	if okShared and Shared then
		brew = Shared.BrewSeconds()
	end
	local dex = {}
	for _, id in ipairs(cfg.Dogs.Order) do
		dex[id] = type(p.DogDex) == "table" and p.DogDex[id] == true or false
	end
	return {
		Season = h.Season, Enabled = cfg.HalloweenEventEnabled, Candy = h.Candy, Lifetime = h.Lifetime, Spent = h.Spent,
		Curse = math.floor(h.Curse * 10 + .5) / 10, Day = F.Day(now), ResetIn = 86400 - now % 86400,
		Cauldron = { Level = c.Level, Invested = c.Invested, StartedAt = c.StartedAt, Claimed = c.Claimed, Tricks = c.Tricks,
			ReadyAt = c.StartedAt > 0 and c.StartedAt + brew or 0, Next = thresholds[c.Level + 1], Thresholds = thresholds },
		Quests = { Day = h.Quests.Day, List = quests, AllClaimed = h.Quests.AllClaimed },
		Houses = { Day = h.Houses.Day, Knocked = h.Houses.Knocked },
		Rush = { Day = h.Rush.Day, Remaining = h.Rush.Remaining, Active = h.Rush.Active, Max = cfg.CandyRush.Seconds },
		Skins = h.Skins, Skin = h.Skin, DexClaims = h.DexClaims, Dex = dex, DexCount = F.EventDexCount(p),
		Boss = { Unlocked = h.Boss.Unlocked, Kills = h.Boss.Kills, Best = h.Boss.Best },
		Onboarded = h.Onboarded, Seen = h.Seen, Stats = h.Stats,
		Chapter2 = chapter2View(p, now),
	}
end

function F.Snapshot(_R: any, p: any, view: any, now: number)
	view.Halloween = F.View(p, now)
end

return F
