--!nocheck
-- Player titles (docs/TITLES.md): lune run tests/titles.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): the definitions (DogEconomy.TitleDefinitions),
-- the server feature (Economy.Features.Titles through Rules.Normalize / Rules.Action / FeatureRegistry),
-- the legacy cosmetic migration, the snapshot and the player attributes, the window's pure item list
-- (Modules.TitlesScreen.Items) and the Russian strings (Localization.Titles), plus a cost check:
-- evaluating 200 rich profiles stays fast.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local L = require("./lib/economy_env")
local Titles = L.Require("ReplicatedStorage.DogEconomy.TitleDefinitions")
local DexRewards = L.Require("ReplicatedStorage.DogEconomy.DexRewards")
local D = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")
local ItemDefs = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local R = L.Require("ServerScriptService.Economy.Rules")
local PlotRules = L.Require("ServerScriptService.Economy.PlotRules")
local Feature = L.Require("ServerScriptService.Economy.Features.Titles")
local Dict = L.Require("ReplicatedStorage.Localization.Titles")

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
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end
local function truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end
local function refused(fn, needle)
	local ok, err = pcall(fn)
	if ok then error("expected a refusal" .. (needle and (" (" .. needle .. ")") or ""), 2) end
	if needle and not string.find(tostring(err), needle, 1, true) then error("wrong refusal: " .. tostring(err), 2) end
	return tostring(err)
end
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local NOW = 1760000000
L.Time = NOW
local nextUid = 1000
local function profile(opts)
	opts = opts or {}
	nextUid += 1
	local uid = opts.Uid or nextUid
	L.Time = NOW
	local p = R.Profile(uid, NOW)
	p = R.Normalize(p, uid, NOW)
	return p
end
local function museum(n)
	local ids = {}
	for _, def in pairs(D) do
		if not def.MuseumExcluded and def.Index >= 1 and def.Index <= 100 then ids[def.Index] = def.Id end
	end
	local out = {}
	for i = 1, n do table.insert(out, ids[i]) end
	return out
end
local function legendaryItems(n)
	local out = {}
	for id in pairs(Titles.LegendaryItems) do table.insert(out, id) end
	table.sort(out)
	local picked = {}
	for i = 1, math.min(n, #out) do table.insert(picked, out[i]) end
	return picked
end
local function unlocked(p, id)
	return p.Titles.Unlocked[id] ~= nil
end
local function evaluate(p, now)
	return Feature.Evaluate(R, p, now or NOW)
end
-- A rich profile: every stat above (or below) the bars.
local function rich(p)
	p.Stats.TotalFinds = 3000
	p.Stats.SecretFinds = 1
	p.Stats.CompletedTrades = 60
	for _, id in ipairs(museum(100)) do p.DogDex[id] = true end
	for i = 1, 5 do p.UnlockedLayers[tostring(i)] = true end
	p.Lifetime.TotalCoinsEarned = 2e12
	p.Lifetime.TotalPlaytimeSeconds = 400000
	p.Prestige = 3
	p.Mining.OresBroken = 3000
	p.Lab.Experiments = 30
	p.DogRush = { Version = 1, Generation = "", Caught = 0, Claimed = {}, Lifetime = 250, Best = 12, Chests = 9 }
	p.WorldEventsSeen = { BONE_RAIN = { FirstSeen = NOW }, DOG_RUSH = { FirstSeen = NOW }, GOLDEN_HOUR = { FirstSeen = NOW }, EARTHQUAKE = { FirstSeen = NOW }, TIME_WARP = { FirstSeen = NOW }, NULL_HOUR = { FirstSeen = NOW } }
	p.VariantDex = { Breadog = { Normal = true, Shiny = true, Golden = true, Void = true } }
	for i = 1, 12 do p.VariantDex["Dog" .. i] = { Shiny = true } end
	for _, id in ipairs(legendaryItems(12)) do p.Collection[id] = true end
	local heavy = 0
	for id in pairs(ItemDefs) do
		if heavy < 20 then p.HeavyCollection[id] = true; heavy += 1 end
	end
	p.Resources = { Stone = 2000 }
	for i = 1, 45 do
		local uid = string.format("%032x", 90000 + i)
		p.Dogs[uid] = { DogUid = uid, DogId = "Breadog", Variant = "Normal", OwnerUserId = p.UserId, State = "Inventory", AssignedSlot = "", Mastery = 0, MasteryXP = 0 }
	end
	return p
end

-- Definitions ------------------------------------------------------------------------------------
test("definitions: ~30 valid titles (ids, texts, icons, rarity, colours, category, condition)", function()
	truthy(#Titles.List >= 30, "at least 30 titles, got " .. #Titles.List)
	local ids, perRarity = {}, {}
	for _, def in ipairs(Titles.List) do
		truthy(type(def.Id) == "string" and #def.Id > 0 and #def.Id <= 40 and string.match(def.Id, "^%w+$"), "id " .. tostring(def.Id))
		truthy(not ids[def.Id], "unique id " .. def.Id)
		ids[def.Id] = true
		eq(Titles.ById[def.Id], def, "ById")
		eq(Titles.Get(def.Id), def, "Get")
		truthy(type(def.Text) == "string" and def.Text ~= "" and def.Text == string.upper(def.Text), "upper-case text " .. def.Id)
		truthy(type(def.RU) == "string" and def.RU ~= "", "russian " .. def.Id)
		truthy(type(def.Icon) == "string" and def.Icon ~= "", "icon " .. def.Id)
		truthy(Titles.RarityRank[def.Rarity] ~= nil, "rarity " .. def.Id)
		perRarity[def.Rarity] = (perRarity[def.Rarity] or 0) + 1
		truthy(Titles.CategoryById[def.Category] ~= nil and def.Category ~= "Legacy", "category " .. def.Id)
		truthy(type(Titles.Stats[def.Stat]) == "function", "stat " .. def.Id)
		truthy(type(def.Target) == "number" and def.Target > 0 and def.Target < math.huge, "target " .. def.Id)
		truthy(type(def.How) == "string" and def.How ~= "" and type(def.HowRU) == "string" and def.HowRU ~= "", "how to get " .. def.Id)
		local rank = Titles.RarityRank[def.Rarity]
		if rank >= Titles.RarityRank.Epic then
			truthy(type(def.Gradient) == "table" and #def.Gradient >= 2, "Epic and above use a gradient: " .. def.Id)
			for _, c in ipairs(def.Gradient) do truthy(typeof(c) == "Color3", "gradient colour " .. def.Id) end
		else
			truthy(typeof(def.Color) == "Color3" and def.Gradient == nil, "one colour below Epic: " .. def.Id)
		end
		truthy(#Titles.Colors(def) >= 1, "colours")
		truthy(Titles.Style(def) == Titles.Styles[def.Rarity], "style")
		if def.Rarity == "Secret" then truthy(def.Hidden == true, "secret titles are hidden: " .. def.Id) end
	end
	for _, rarity in ipairs(Titles.Rarities) do
		truthy((perRarity[rarity] or 0) >= 1, "a title of every rarity: " .. rarity)
		truthy(Titles.Styles[rarity] ~= nil and Titles.RarityRU[rarity] ~= nil, "style + russian rarity " .. rarity)
	end
	-- The examples the owner asked for.
	for _, id in ipairs({ "FirstFind", "TreasureHunter", "LegendaryDigger", "DogMaster", "Collector", "RockBreaker", "Stonemason", "DeepDigger", "VoidWalker", "MadScientist", "Trader", "Millionaire", "Billionaire", "Veteran", "Prestige", "DogWrangler" }) do
		truthy(Titles.ById[id], "title " .. id)
	end
	eq(Titles.ById.TreasureHunter.Icon, "💎")
	eq(Titles.ById.LegendaryDigger.Icon, "🏆")
	eq(Titles.ById.DogMaster.Icon, "🐕")
	-- Dog Wrangler tiers 10 / 50 / 200 pups.
	local tiers = {}
	for _, def in ipairs(Titles.List) do if def.Stat == "Pups" then table.insert(tiers, def.Target) end end
	table.sort(tiers)
	eq(table.concat(tiers, ","), "10,50,200", "pup tiers")
end)

test("styles: animation only from Legendary, sparkles from Mythic, gradients from Epic", function()
	for _, rarity in ipairs(Titles.Rarities) do
		local s = Titles.Styles[rarity]
		local rank = Titles.RarityRank[rarity]
		eq(s.Gradient == true, rank >= Titles.RarityRank.Epic, "gradient " .. rarity)
		eq(s.Animated == true, rank >= Titles.RarityRank.Legendary, "animated " .. rarity)
		eq(s.Sparkle == true, rank >= Titles.RarityRank.Mythic, "sparkle " .. rarity)
		eq(s.Glow == true, rank >= Titles.RarityRank.Rare, "glow " .. rarity)
	end
end)

-- Fresh and old profiles -------------------------------------------------------------------------
test("new player: p.Titles is created, nothing unlocked, nothing equipped, valid", function()
	local p = profile()
	truthy(type(p.Titles) == "table", "titles table")
	eq(p.Titles.Version, 1)
	eq(p.Titles.Equipped, "")
	eq(next(p.Titles.Unlocked), nil, "no unlocks for a brand new player")
	R.Validate(p)
	eq(p.EquippedCosmetic, "", "legacy field untouched")
end)

test("old player without Titles: Normalize builds it, Validate accepts nil and the result", function()
	local p = profile()
	p.Titles = nil
	Feature.Validate(R, p) -- nil is fine
	Feature.ResetCache()
	R.Normalize(p, p.UserId, NOW)
	truthy(type(p.Titles) == "table" and type(p.Titles.Unlocked) == "table" and type(p.Titles.Counters) == "table", "rebuilt")
	R.Validate(p)
	-- Broken saved data is healed, never rejected.
	p.Titles = { Version = "x", Unlocked = { FirstFind = 0 / 0, [5] = 1, Trader = 12 }, Equipped = 7, Counters = { Stone = -1, LegendaryFinds = 3 } }
	Feature.Normalize(R, p, NOW)
	eq(p.Titles.Unlocked.FirstFind, 0, "a broken timestamp stays unlocked")
	eq(p.Titles.Unlocked[5], nil, "numeric key dropped")
	eq(p.Titles.Unlocked.Trader, 12)
	eq(p.Titles.Equipped, "")
	eq(p.Titles.Counters.LegendaryFinds, 3)
	R.Validate(p)
end)

-- Unlock evaluation ------------------------------------------------------------------------------
test("unlocks from stats: finds, depth, dogdex, wealth, mining, lab, trades, prestige, pups, events", function()
	local p = rich(profile())
	local fresh = evaluate(p)
	truthy(#fresh >= 30, "many unlocks at once: " .. #fresh)
	for _, def in ipairs(Titles.List) do
		truthy(unlocked(p, def.Id), "unlocked " .. def.Id)
		eq(p.Titles.Unlocked[def.Id], NOW, "unlock time " .. def.Id)
	end
	-- Permanent: losing the stat later does not take the title away.
	p.Stats.TotalFinds = 0
	evaluate(p, NOW + 100)
	truthy(unlocked(p, "TreasureHunter"), "kept")
end)

test("thresholds: just below stays locked, at the bar unlocks", function()
	local p = profile()
	p.Stats.TotalFinds = 499
	for _, id in ipairs(museum(24)) do p.DogDex[id] = true end
	p.Lifetime.TotalCoinsEarned = 999999
	p.UnlockedLayers["2"], p.UnlockedLayers["3"] = true, true
	p.DogRush = { Lifetime = 9 }
	evaluate(p)
	truthy(unlocked(p, "FirstFind") and unlocked(p, "TreasureSeeker"), "small find titles")
	truthy(not unlocked(p, "TreasureHunter"), "499 finds is not 500")
	truthy(not unlocked(p, "DogMaster"), "24 dogs is not 25")
	truthy(not unlocked(p, "Millionaire"), "999,999 coins")
	truthy(unlocked(p, "CaveExplorer") and unlocked(p, "RuinRaider") and not unlocked(p, "DeepDigger"), "depth 3")
	truthy(not unlocked(p, "DogWrangler"), "9 pups")
	p.Stats.TotalFinds = 500
	p.DogDex[museum(25)[25]] = true
	p.Lifetime.TotalCoinsEarned = 1e6
	p.DogRush.Lifetime = 10
	evaluate(p, NOW + 20)
	truthy(unlocked(p, "TreasureHunter") and unlocked(p, "DogMaster") and unlocked(p, "Millionaire") and unlocked(p, "DogWrangler"), "at the bar")
	-- Depth needs every layer before it (a gap does not count).
	local q = profile()
	q.UnlockedLayers["5"] = true
	evaluate(q)
	truthy(not unlocked(q, "VoidWalker"), "THE VOID alone without the layers before it")
end)

test("throttle: Normalize evaluates at most every 15 s per player (RAM only)", function()
	Feature.ResetCache()
	local p = profile()
	Feature.Normalize(R, p, NOW) -- evaluates now
	p.Stats.TotalFinds = 1
	Feature.Normalize(R, p, NOW + 5)
	truthy(not unlocked(p, "FirstFind"), "not before 15 s")
	Feature.Normalize(R, p, NOW + 15)
	truthy(unlocked(p, "FirstFind"), "after 15 s")
	-- Nothing about the throttle is saved.
	for key in pairs(p.Titles) do
		truthy(key == "Version" or key == "Unlocked" or key == "Equipped" or key == "Counters" or key == "LegacySeen", "saved key " .. key)
	end
end)

test("counters: lifetime stone adds every increase, spending does not reduce it", function()
	Feature.ResetCache()
	local p = profile()
	p.Resources = { Stone = 100 }
	Feature.Normalize(R, p, NOW)
	eq(p.Titles.Counters.Stone, 100, "the balance an old player has counts")
	p.Resources.Stone = 400
	Feature.Normalize(R, p, NOW + 1)
	eq(p.Titles.Counters.Stone, 400)
	p.Resources.Stone = 50 -- spent on decor
	Feature.Normalize(R, p, NOW + 2)
	eq(p.Titles.Counters.Stone, 400, "spending keeps the lifetime total")
	p.Resources.Stone = 700
	Feature.Normalize(R, p, NOW + 3)
	eq(p.Titles.Counters.Stone, 1050)
	evaluate(p, NOW + 30)
	truthy(unlocked(p, "Stonemason"), "1,000 stone")
end)

test("counters: Legendary finds start from the collection, then every new feed entry counts", function()
	Feature.ResetCache()
	local p = profile()
	p.Titles = nil -- an old player's first pass
	local items = legendaryItems(3)
	for _, id in ipairs(items) do p.Collection[id] = true end
	p.DiscoveryFeed = { { ItemId = items[1], ItemUid = "a", FoundAt = NOW - 50 } }
	evaluate(p)
	eq(p.Titles.Counters.LegendaryFinds, 3, "distinct collected")
	eq(p.Titles.Counters.FeedAt, NOW - 50)
	-- Repeats of the same legendary item count from now on; ordinary items do not.
	local plain
	for id, def in pairs(ItemDefs) do if def.BaseDropChance > 0.01 then plain = id; break end end
	table.insert(p.DiscoveryFeed, 1, { ItemId = plain, ItemUid = "b", FoundAt = NOW - 10 })
	for i = 1, 7 do table.insert(p.DiscoveryFeed, 1, { ItemId = items[1], ItemUid = "l" .. i, FoundAt = NOW - 9 + i }) end
	evaluate(p, NOW + 20)
	eq(p.Titles.Counters.LegendaryFinds, 10)
	truthy(unlocked(p, "LegendaryDigger"), "10 Legendary+ finds")
	evaluate(p, NOW + 40)
	eq(p.Titles.Counters.LegendaryFinds, 10, "the same feed entries are never counted twice")
end)

-- Legacy cosmetics -------------------------------------------------------------------------------
test("legacy: every owned cosmetic title becomes a title, names via DexRewards.TitleName", function()
	local keys = { "Dex10", "Dex25", "Dex30", "Dex100", "SetFood", "Discovery:BURIED_JUNK:Normal", "Discovery:CRYSTAL_VEIN:Heavy", "Finds25", "Finds2500", "Prestige1", "Prestige5", "Event3", "GoldenKennel", "CyberKennel", "VoidAura", "FounderPlaque", "SupporterTitle", "EventSupporter", "SomeFutureThing" }
	for _, key in ipairs(keys) do
		local def = Titles.Legacy(key)
		truthy(def, "legacy title for " .. key)
		eq(def.Id, "legacy:" .. key)
		eq(Titles.Get("legacy:" .. key), def, "Get by id")
		truthy(def.Legacy and def.Category == "Legacy" and def.Text ~= "" and def.RU ~= "" and def.Icon ~= "", "fields " .. key)
		truthy(Titles.RarityRank[def.Rarity], "rarity " .. key)
		truthy(#Titles.Colors(def) >= 1, "colours " .. key)
	end
	eq(Titles.Legacy("Dex30").Text, DexRewards.TitleName("Dex30"), "Dogdex title name")
	eq(Titles.Legacy("Dex30").RU, "КОЛЛЕКЦИОНЕР СОБАК")
	eq(Titles.Legacy("Dex25").Text, "DOGDEX 25", "an old-only Dex title keeps a name")
	eq(Titles.Legacy("Discovery:BURIED_JUNK:Normal").Text, "BURIED JUNK")
	eq(Titles.Legacy("Discovery:CRYSTAL_VEIN:Heavy").Text, "HEAVY CRYSTAL VEIN")
	eq(Titles.Legacy("SetFood").Text, "FOOD SET")
	eq(Titles.Legacy("Finds2500").Text, "2500 FINDS")
	eq(Titles.Legacy("GoldenKennel").Text, "GOLDEN KENNEL")
	eq(Titles.Legacy(""), nil)
	eq(Titles.Legacy("bad key with spaces"), nil, "junk keys are not titles")
	eq(Titles.Get("legacy:"), nil)
	eq(Titles.Get("NotATitle"), nil)
end)

test("migration: an old profile keeps every earned title and wears its equipped one", function()
	Feature.ResetCache()
	local p = profile()
	p.Titles = nil
	p.Cosmetics = { Dex30 = true, GoldenKennel = true, Finds100 = true, ["Discovery:BURIED_JUNK:Normal"] = true, SetFood = true, Prestige2 = true, Event3 = true, Unused = false }
	p.EquippedCosmetic = "Dex30"
	p.PlotProgressionVersion = nil
	local before = R.Copy(p.Cosmetics)
	R.Normalize(p, p.UserId, NOW)
	for key, owned in pairs(before) do
		eq(unlocked(p, "legacy:" .. key), owned == true, "legacy title " .. key)
	end
	eq(p.Titles.Equipped, "legacy:Dex30", "the equipped collection title moves above the head")
	eq(p.EquippedCosmetic, "Dex30", "the legacy field is never written")
	eq(p.EquippedPlotSkin, "Classic", "plot skin migration unaffected (Dex30 is not a skin)")
	-- Once: equipping another title is not overridden by the next Normalize.
	R.Action(p, "TitleEquip", { Id = "legacy:GoldenKennel" }, NOW + 1, rng(1))
	R.Normalize(p, p.UserId, NOW + 2)
	eq(p.Titles.Equipped, "legacy:GoldenKennel")
	-- The old COSMETICS list still works: equipping a collection title there shows it.
	R.Action(p, "Cosmetic", { Kind = "Finds100" }, NOW + 3, rng(1))
	R.Normalize(p, p.UserId, NOW + 4)
	eq(p.Titles.Equipped, "legacy:Finds100", "old list equip followed")
	R.Validate(p)
end)

test("migration: the plot skin migration of an old kennel cosmetic still works", function()
	Feature.ResetCache()
	local p = profile()
	p.Titles = nil
	p.PlotProgressionVersion = nil
	p.Cosmetics = { GoldenKennel = true }
	p.EquippedCosmetic = "GoldenKennel"
	R.Normalize(p, p.UserId, NOW)
	eq(p.EquippedPlotSkin, "GoldenHour", "PlotRules still reads EquippedCosmetic")
	eq(p.Titles.Equipped, "legacy:GoldenKennel")
	eq(p.EquippedCosmetic, "GoldenKennel")
	PlotRules.Normalize(p)
	eq(p.EquippedPlotSkin, "GoldenHour")
end)

-- Equip ------------------------------------------------------------------------------------------
test("TitleEquip: only unlocked titles, '' removes, unknown / invalid ids refused", function()
	Feature.ResetCache()
	local p = profile()
	refused(function() R.Action(p, "TitleEquip", { Id = "VoidWalker" }, NOW, rng(1)) end, "This title is still locked")
	refused(function() R.Action(p, "TitleEquip", { Id = "NotATitle" }, NOW, rng(1)) end, "Unknown title")
	refused(function() R.Action(p, "TitleEquip", { Id = 5 }, NOW, rng(1)) end, "Invalid title")
	refused(function() R.Action(p, "TitleEquip", {}, NOW, rng(1)) end, "Invalid title")
	refused(function() R.Action(p, "TitleEquip", { Id = "legacy:GoldenKennel" }, NOW, rng(1)) end, "This title is still locked")
	-- A title earned seconds ago can be equipped at once (the action evaluates first).
	p.Stats.TotalFinds = 1
	local message, extra = R.Action(p, "TitleEquip", { Id = "FirstFind" }, NOW + 1, rng(1))
	eq(message, "Title equipped")
	eq(extra.Title, "FirstFind")
	eq(p.Titles.Equipped, "FirstFind")
	eq(R.Action(p, "TitleEquip", { Id = "" }, NOW + 2, rng(1)), "Title removed")
	eq(p.Titles.Equipped, "")
	R.Validate(p)
end)

test("Normalize drops an equipped title that is not unlocked or no longer exists", function()
	Feature.ResetCache()
	local p = profile()
	p.Titles.Unlocked.Gone = NOW
	p.Titles.Equipped = "Gone"
	Feature.Normalize(R, p, NOW)
	eq(p.Titles.Equipped, "", "unknown title")
	p.Titles.Equipped = "VoidWalker"
	Feature.Normalize(R, p, NOW + 1)
	eq(p.Titles.Equipped, "", "locked title")
end)

-- Snapshot and projection ------------------------------------------------------------------------
test("snapshot: Equipped, Unlocked and Progress {Value, Target} of every title", function()
	Feature.ResetCache()
	local p = profile()
	p.Stats.TotalFinds = 120
	R.Normalize(p, p.UserId, NOW)
	R.Action(p, "TitleEquip", { Id = "TreasureSeeker" }, NOW, rng(1))
	local view = {}
	R.Features.Snapshot(R, p, view, NOW)
	local t = view.Titles
	truthy(t, "view.Titles")
	eq(t.Equipped, "TreasureSeeker")
	truthy(t.Unlocked.FirstFind and t.Unlocked.TreasureSeeker, "unlocked set")
	for _, def in ipairs(Titles.List) do
		local pr = t.Progress[def.Id]
		truthy(pr and type(pr.Value) == "number" and pr.Target == def.Target, "progress " .. def.Id)
	end
	eq(t.Progress.TreasureHunter.Value, 120)
	-- JSON-safe (DataStore and remotes): string keys, finite numbers.
	local decoded = serde.decode("json", serde.encode("json", p.Titles))
	eq(decoded.Equipped, "TreasureSeeker")
	eq(decoded.Unlocked.FirstFind, p.Titles.Unlocked.FirstFind)
end)

test("Project: TitleId / TitleCount / TitleLatest player attributes", function()
	local attrs = {}
	local fake = {
		SetAttribute = function(_, k, v) attrs[k] = v end,
		GetAttribute = function(_, k) return attrs[k] end,
	}
	Feature.Project(fake, { Titles = { Equipped = "FirstFind", Unlocked = { FirstFind = 10, Trader = 30, Veteran = 20 } } })
	eq(attrs.TitleId, "FirstFind")
	eq(attrs.TitleCount, 3)
	eq(attrs.TitleLatest, "Trader")
	Feature.Project(fake, {})
	eq(attrs.TitleId, "", "no titles yet")
	eq(attrs.TitleCount, 0)
	truthy(string.find(fs.readFile("src/ServerScriptService/Economy/Runtime.luau"), "Features.Titles).Project(player,p)", 1, true), "Runtime.Project projects the title")
end)

-- Cost -------------------------------------------------------------------------------------------
test("cost: evaluating 200 rich profiles stays fast", function()
	local profiles = {}
	for i = 1, 200 do
		local p = rich(profile())
		p.Titles.Unlocked = {}
		p.Cosmetics = { Dex10 = true, Dex30 = true, GoldenKennel = true, ["Finds" .. (i % 7 + 1) * 25] = true }
		profiles[i] = p
	end
	local start = os.clock()
	for _, p in ipairs(profiles) do evaluate(p) end
	local full = os.clock() - start
	-- A pass with everything already unlocked (the usual case) and the per-second Normalize.
	start = os.clock()
	for _, p in ipairs(profiles) do evaluate(p, NOW + 30) end
	local again = os.clock() - start
	start = os.clock()
	for round = 1, 5 do
		for _, p in ipairs(profiles) do Feature.Normalize(R, p, NOW + 31 + round) end
	end
	local normalize = (os.clock() - start) / 5
	print(string.format("titles cost: first evaluation of 200 profiles %.1f ms, again %.1f ms, throttled Normalize %.2f ms", full * 1000, again * 1000, normalize * 1000))
	truthy(full < 1.5, "200 evaluations under 1.5 s in Lune: " .. full)
	truthy(again < 1.5, "repeat under 1.5 s: " .. again)
	truthy(normalize < 0.25, "throttled Normalize of 200 profiles under 250 ms: " .. normalize)
end)

-- Window list and strings ------------------------------------------------------------------------
test("window items: categories, owned filter, sorts, legacy cards, ready titles, secrets hidden", function()
	-- TitlesScreen needs Kit (client); run its pure Items() with stub modules.
	L.Overrides["StarterGui/ScreenGui/Modules/Kit"] = { Lang = function() return "en" end, Theme = {}, Format = {} }
	L.Overrides["StarterGui/ScreenGui/Modules/Net"] = {}
	L.Overrides["ReplicatedStorage/TitleBadge"] = {}
	local Screen = L.Require("StarterGui.ScreenGui.Modules.TitlesScreen")
	local view = {
		Equipped = "legacy:Dex30",
		Unlocked = { FirstFind = NOW, ["legacy:Dex30"] = NOW, ["legacy:GoldenKennel"] = NOW },
		Progress = { TreasureSeeker = { Value = 60, Target = 50 }, TreasureHunter = { Value = 60, Target = 500 }, VoidTamer = { Value = 0, Target = 1 } },
	}
	local all = Screen.Items(view, "all", "rarity", true)
	eq(#all, #Titles.List + 2, "every title + the owned legacy ones")
	eq(all[1].Id, "legacy:Dex30", "the equipped title first")
	local byId = {}
	for _, item in ipairs(all) do byId[item.Id] = item end
	truthy(byId.TreasureSeeker.Unlocked and byId.TreasureSeeker.Ready, "met but not yet saved = ready to equip")
	truthy(not byId.TreasureHunter.Unlocked, "locked")
	truthy(byId.VoidTamer.Hidden, "secret stays hidden")
	local owned = Screen.Items(view, "owned", "rarity", true)
	eq(#owned, 4, "owned: FirstFind, ready TreasureSeeker, 2 legacy")
	local legacy = Screen.Items(view, "Legacy", "name", false)
	eq(#legacy, 2)
	local digging = Screen.Items(view, "Digging", "progress", true)
	for _, item in ipairs(digging) do eq(item.Def.Category, "Digging") end
	-- Rarity sort, descending: Secret before Common (equipped aside).
	local sorted = Screen.Items({ Equipped = "", Unlocked = {}, Progress = {} }, "all", "rarity", true)
	truthy(Titles.Rank(sorted[1].Def) >= Titles.Rank(sorted[#sorted].Def), "rarity order")
	local ascending = Screen.Items({ Equipped = "", Unlocked = {}, Progress = {} }, "all", "rarity", false)
	eq(Titles.Rank(ascending[1].Def), 1, "common first ascending")
	L.Overrides["StarterGui/ScreenGui/Modules/Kit"] = nil
	L.Overrides["StarterGui/ScreenGui/Modules/Net"] = nil
	L.Overrides["ReplicatedStorage/TitleBadge"] = nil
end)

test("Russian: every window string, every title, every server reply", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/TitlesScreen.luau")
	local count = 0
	for en in string.gmatch(source, '[^%w]T%("([^"]+)"%)') do
		count += 1
		truthy(Dict.Exact[en] or Dict.Window[en], "Russian for window string: " .. en)
	end
	truthy(count >= 20, "window strings found: " .. count)
	for _, def in ipairs(Titles.List) do
		eq(Dict.Exact[def.Text], def.RU, "title " .. def.Text)
		eq(Dict.Exact[def.How], def.HowRU, "how " .. def.Id)
	end
	for _, message in ipairs({ "Title equipped", "Title removed", "This title is still locked", "Unknown title", "Invalid title" }) do
		truthy(Dict.Exact[message], "server reply " .. message)
		truthy(string.find(fs.readFile("src/ServerScriptService/Economy/Features/Titles.luau"), '"' .. message .. '"', 1, true), "reply in the feature: " .. message)
	end
	for _, cat in ipairs(Titles.Categories) do eq(Dict.Window[cat.Text], cat.RU, "category " .. cat.Id) end
	-- Generic words stay out of Exact (they would override other screens' translations).
	for _, word in ipairs({ "ALL", "EQUIPPED", "DIGGING", "DOGS", "LOCKED", "OWNED", "NAME", "EPIC" }) do
		eq(Dict.Exact[word], nil, "not an exact override: " .. word)
	end
end)

test("old kennel-dog title billboard is gone; titles render above players", function()
	local visuals = fs.readFile("src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau")
	truthy(not string.find(visuals, "EconomyCosmetic", 1, true), "no title billboard over kennel dogs")
	local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlayerTitles.client.luau")
	truthy(string.find(client, "MaxDistance", 1, true) and string.find(client, "AlwaysOnTop = false", 1, true), "billboard settings")
	truthy(string.find(client, "MAX_ANIMATED = 12", 1, true) and string.find(client, "ANIMATE_DISTANCE = 50", 1, true), "animation budget")
	truthy(string.find(client, '"TitleId"', 1, true), "reads the TitleId attribute")
end)

print(string.format("titles: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("titles tests failed")
end
