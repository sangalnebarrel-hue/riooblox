-- Player titles shown above the character (docs/TITLES.md). Feature module (Economy.FeatureRegistry).
-- Definitions, stats and the legacy mapping: ReplicatedStorage.DogEconomy.TitleDefinitions.
-- Saved data:
--   p.Titles = {Version = 1, Unlocked = {[titleId] = unixTime}, Equipped = "" | titleId,
--               Counters = {Stone, StoneSeen, LegendaryFinds, FeedAt}, LegacySeen = string}
--   Counters: lifetime stone collected (p.Resources.Stone only holds the current balance, so every
--   increase of it is added up), Legendary+ finds counted from the discovery feed (started from the
--   distinct Legendary+ items of the collection) and the feed's last processed FoundAt.
--   LegacySeen: the last p.EquippedCosmetic seen. When it changes (first run on an old profile, or the
--   old COSMETICS list equips a collection title) that legacy title becomes the equipped title. The
--   legacy field itself is never written (PlotRules reads it for the plot skin migration).
-- Normalize is cheap: the shape, the stone counter and the legacy check run every pass; the unlock
-- evaluation runs at most every EvalSeconds per player (RAM timestamps keyed by UserId, not saved).
-- Unlocks are permanent. Every owned p.Cosmetics title key becomes the title "legacy:<key>".
-- Action 'TitleEquip' {Id}: "" removes the title; otherwise only an unlocked title (the evaluation runs
-- first, so a title earned seconds ago can be equipped at once).
-- Snapshot: snapshot.Features.Titles = {Version, Equipped, Unlocked = {[id] = time},
--   Progress = {[id] = {Value, Target}}} (regular titles; legacy titles are owned or absent).
-- Project(player, p) (Runtime.Project): player attributes TitleId (equipped id, "" for none; every client
-- draws it above the head), TitleCount (unlocked count) and TitleLatest (the newest unlocked id).
local RS = game:GetService("ReplicatedStorage")
local Defs = require(RS.DogEconomy.TitleDefinitions)
local Resources = require(RS.DogEconomy.Resources)

local F = { Name = "Titles", Order = 60 }
F.EvalSeconds = 15

local lastEval: { [any]: number } = {}
local evalEntries = 0

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
local function num(v: any): number
	return finite(v) and v or 0
end

-- Fills and repairs p.Titles (string keys, finite numbers only). Returns it and whether it was new.
function F.Shape(p: any): (any, boolean)
	local t = p.Titles
	local created = false
	if type(t) ~= "table" then
		t = { Version = 1, Unlocked = {}, Equipped = "", Counters = {} }
		p.Titles = t
		created = true
	end
	t.Version = 1
	if type(t.Unlocked) ~= "table" then
		t.Unlocked = {}
	end
	local bad = nil
	for key, value in pairs(t.Unlocked) do
		if type(key) ~= "string" or #key > 120 or not finite(value) then
			bad = bad or {}
			table.insert(bad, key)
		end
	end
	if bad then
		for _, key in ipairs(bad) do
			local value = t.Unlocked[key]
			t.Unlocked[key] = nil
			-- An unlock with a broken timestamp stays unlocked.
			if type(key) == "string" and #key <= 120 and value then
				t.Unlocked[key] = 0
			end
		end
	end
	if type(t.Equipped) ~= "string" or #t.Equipped > 120 then
		t.Equipped = ""
	end
	if type(t.Counters) ~= "table" then
		t.Counters = {}
	end
	local badCounters = nil
	for key, value in pairs(t.Counters) do
		if type(key) ~= "string" or not finite(value) or value < 0 then
			badCounters = badCounters or {}
			table.insert(badCounters, key)
		end
	end
	if badCounters then
		for _, key in ipairs(badCounters) do
			t.Counters[key] = nil
		end
	end
	if t.LegacySeen ~= nil and type(t.LegacySeen) ~= "string" then
		t.LegacySeen = nil
	end
	return t, created
end

-- Lifetime stone: every increase of the balance (an old player's balance counts once).
local function countStone(p: any, c: any)
	local stone = Resources.Get(p, "Stone")
	if c.StoneSeen == nil then
		c.Stone = math.max(num(c.Stone), stone)
	elseif stone > c.StoneSeen then
		c.Stone = num(c.Stone) + (stone - c.StoneSeen)
	end
	c.StoneSeen = stone
	-- Mining keeps an exact lifetime count (MiningRules: p.Mining.StoneMined); the balance deltas
	-- above miss stone mined between a decor purchase and the next pass, so the larger one wins.
	local mined = type(p.Mining) == "table" and num(p.Mining.StoneMined) or 0
	if mined > num(c.Stone) then
		c.Stone = mined
	end
end

-- Discovery feed: Legendary or Secret finds since the last pass.
local function countFeed(p: any, c: any)
	local feed = type(p.DiscoveryFeed) == "table" and p.DiscoveryFeed or {}
	local mark = c.FeedAt
	local newest = finite(mark) and mark or 0
	if mark == nil then
		-- First pass: the distinct Legendary+ items already collected start the counter.
		c.LegendaryFinds = math.max(num(c.LegendaryFinds), Defs.LegendaryCollected(p))
		for _, x in ipairs(feed) do
			if type(x) == "table" and finite(x.FoundAt) and x.FoundAt > newest then
				newest = x.FoundAt
			end
		end
	else
		for _, x in ipairs(feed) do
			if type(x) == "table" and finite(x.FoundAt) and x.FoundAt > mark then
				if Defs.IsLegendaryItem(x.ItemId) then
					c.LegendaryFinds = num(c.LegendaryFinds) + 1
				end
				if x.FoundAt > newest then
					newest = x.FoundAt
				end
			end
		end
	end
	c.FeedAt = newest
end

-- Unlocks every title whose condition is met and every owned legacy title. Returns the new ids.
function F.Evaluate(_R: any, p: any, now: number): { string }
	local t = F.Shape(p)
	local uid = p.UserId
	if uid ~= nil then
		if lastEval[uid] == nil then
			evalEntries += 1
			if evalEntries > 2000 then
				table.clear(lastEval)
				evalEntries = 1
			end
		end
		lastEval[uid] = now
	end
	local c = t.Counters
	countStone(p, c)
	countFeed(p, c)
	local fresh = {}
	local ctx = Defs.Context(p, c)
	for _, def in ipairs(Defs.List) do
		if t.Unlocked[def.Id] == nil and Defs.Met(def, ctx) then
			t.Unlocked[def.Id] = now
			table.insert(fresh, def.Id)
		end
	end
	if type(p.Cosmetics) == "table" then
		for key, owned in pairs(p.Cosmetics) do
			if owned == true and type(key) == "string" then
				local id = Defs.LegacyId(key)
				if t.Unlocked[id] == nil and #id <= 120 and Defs.Legacy(key) then
					t.Unlocked[id] = now
					table.insert(fresh, id)
				end
			end
		end
	end
	return fresh
end

function F.ResetCache()
	table.clear(lastEval)
	evalEntries = 0
end

function F.Normalize(R: any, p: any, now: number)
	local t, created = F.Shape(p)
	countStone(p, t.Counters)
	-- The legacy equipped title (once on an old profile, and whenever the old list equips one).
	local legacy = type(p.EquippedCosmetic) == "string" and p.EquippedCosmetic or ""
	if t.LegacySeen ~= legacy then
		t.LegacySeen = legacy
		if legacy ~= "" and type(p.Cosmetics) == "table" and p.Cosmetics[legacy] == true and Defs.Legacy(legacy) then
			local id = Defs.LegacyId(legacy)
			if #id <= 120 then
				if t.Unlocked[id] == nil then
					t.Unlocked[id] = now
				end
				t.Equipped = id
			end
		end
	end
	-- A new (or just migrated) p.Titles is evaluated at once; afterwards every EvalSeconds.
	local last = p.UserId ~= nil and lastEval[p.UserId] or nil
	if created or last == nil or now - last >= F.EvalSeconds or now < last then
		F.Evaluate(R, p, now)
	end
	if t.Equipped ~= "" and (t.Unlocked[t.Equipped] == nil or Defs.Get(t.Equipped) == nil) then
		t.Equipped = ""
	end
end

function F.Validate(R: any, p: any)
	local t = p.Titles
	if t == nil then
		return
	end
	R.Check(type(t) == "table" and type(t.Unlocked) == "table", "Invalid titles")
	R.Check(t.Equipped == nil or type(t.Equipped) == "string", "Invalid equipped title")
	R.Check(t.Counters == nil or type(t.Counters) == "table", "Invalid title counters")
end

function F.Action(R: any, p: any, action: string, a: any, now: number, _random: any)
	if action ~= "TitleEquip" then
		return nil
	end
	local t = F.Shape(p)
	local id = type(a) == "table" and a.Id or nil
	R.Check(type(id) == "string" and #id <= 120, "Invalid title")
	if id == "" then
		t.Equipped = ""
		return "Title removed", { Title = "" }
	end
	R.Check(Defs.Get(id) ~= nil, "Unknown title")
	if t.Unlocked[id] == nil then
		F.Evaluate(R, p, now)
	end
	R.Check(t.Unlocked[id] ~= nil, "This title is still locked")
	t.Equipped = id
	return "Title equipped", { Title = id }
end

function F.Snapshot(_R: any, p: any, view: any, _now: number)
	local t = type(p.Titles) == "table" and p.Titles or {}
	local unlocked = {}
	for id, at in pairs(type(t.Unlocked) == "table" and t.Unlocked or {}) do
		if type(id) == "string" then
			unlocked[id] = num(at)
		end
	end
	local ctx = Defs.Context(p, type(t.Counters) == "table" and t.Counters or {})
	local progress = {}
	for _, def in ipairs(Defs.List) do
		local value, target = Defs.Progress(def, ctx)
		progress[def.Id] = { Value = value, Target = target }
	end
	view.Titles = {
		Version = Defs.Version,
		Equipped = type(t.Equipped) == "string" and t.Equipped or "",
		Unlocked = unlocked,
		Progress = progress,
	}
end

-- Player attributes every client reads (PlayerTitles, the title window's unlock toasts).
function F.Project(player: Player, p: any)
	local t = type(p) == "table" and type(p.Titles) == "table" and p.Titles or nil
	local id = t and type(t.Equipped) == "string" and t.Equipped or ""
	if player:GetAttribute("TitleId") ~= id then
		player:SetAttribute("TitleId", id)
	end
	local n, latest, latestAt = 0, "", -1
	for key, at in pairs(t and type(t.Unlocked) == "table" and t.Unlocked or {}) do
		n += 1
		local time = num(at)
		if type(key) == "string" and (time > latestAt or (time == latestAt and key > latest)) then
			latest, latestAt = key, time
		end
	end
	if player:GetAttribute("TitleCount") ~= n then
		player:SetAttribute("TitleCount", n)
	end
	if player:GetAttribute("TitleLatest") ~= latest then
		player:SetAttribute("TitleLatest", latest)
	end
end

return F
