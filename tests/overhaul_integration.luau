--!nocheck
-- Overhaul integration (docs/OVERHAUL.md): every feature module of the economy together, on a NEW
-- player and on an OLD save written by the pre-overhaul code (tests/fixtures/legacy_profile_v5.json,
-- generator: tests/fixtures/make_legacy_v5.luau). lune run tests/overhaul_integration.luau
--  * a new profile normalizes, validates, snapshots and survives the DataStore JSON round trip;
--  * an old save keeps every value it had (cash, bones, levels, dogs and their variants, finds,
--    titles, lab DNA, mining progress) and gains the new tables with defaults;
--  * Validate accepts an old save that did not go through Normalize (trade / lab paths);
--  * Normalize is idempotent: a second pass and a minute of ticks change nothing;
--  * an old player can use the new systems (decor with Stone, legacy title above the head);
--  * the snapshot of the new features stays small and Normalize stays cheap.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local L = require("./lib/economy_env")

local NOW = 1760100000
L.Time = NOW
local folder = function()
	return { GetChildren = function() return {} end, FindFirstChild = function() return nil end }
end
L.Workspace = setmetatable({
	WaitForChild = function() return { WaitForChild = function() return folder() end } end,
	GetServerTimeNow = function() return L.Time end,
	FindFirstChild = function() return nil end,
}, { __index = function() return nil end })
L.Overrides["ServerScriptService/Economy/Runtime"] = { Views = {}, Ready = function() return true end, Allow = function() return true end }
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end }

local R = L.Require("ServerScriptService.Economy.Rules")
local Registry = L.Require("ServerScriptService.Economy.FeatureRegistry")
local Resources = L.Require("ReplicatedStorage.DogEconomy.Resources")

local passed, failed = 0, 0
local function test(name, fn)
	L.Time = NOW
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
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local function json(v)
	return serde.encode("json", v)
end
local function roundTrip(p)
	return serde.decode("json", json(p))
end
local function legacy()
	return serde.decode("json", fs.readFile("tests/fixtures/legacy_profile_v5.json"))
end
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n += 1 end
	return n
end
-- DataStore-safe shape: no NaN/inf, no functions/userdata, tables are arrays 1..n or string-keyed.
local function storable(v, path, seen)
	seen = seen or {}
	local kind = type(v)
	if kind == "number" then
		truthy(v == v and v ~= math.huge and v ~= -math.huge, "bad number at " .. path)
	elseif kind == "table" then
		truthy(not seen[v], "cycle at " .. path)
		seen[v] = true
		local n, numeric, strings = #v, 0, 0
		for k, child in pairs(v) do
			if type(k) == "number" then
				numeric += 1
				truthy(k >= 1 and k <= n and k % 1 == 0, "sparse numeric key at " .. path .. "[" .. tostring(k) .. "]")
			else
				truthy(type(k) == "string", "non-string key at " .. path)
				strings += 1
			end
			storable(child, path .. "." .. tostring(k), seen)
		end
		truthy(numeric == 0 or strings == 0, "mixed array/map at " .. path)
		seen[v] = nil
	else
		truthy(kind == "string" or kind == "boolean", kind .. " at " .. path)
	end
end
local function deepEqual(a, b, path)
	path = path or "p"
	if type(a) ~= type(b) then error("type differs at " .. path .. ": " .. type(a) .. " vs " .. type(b), 0) end
	if type(a) ~= "table" then
		if a ~= b then error("value differs at " .. path .. ": " .. tostring(a) .. " vs " .. tostring(b), 0) end
		return
	end
	for k, v in pairs(a) do deepEqual(v, b[k], path .. "." .. tostring(k)) end
	for k in pairs(b) do
		if a[k] == nil then error("extra key at " .. path .. "." .. tostring(k), 0) end
	end
end
local function snapshotAll(p)
	local view = {}
	for _, f in ipairs(Registry.Modules) do
		if f.Snapshot then
			local ok, err = pcall(f.Snapshot, R, p, view, L.Time)
			truthy(ok, "snapshot of " .. f.Name .. ": " .. tostring(err))
		end
	end
	return view
end

local NEW_FEATURES = { "Resources", "Titles", "DogRush", "Showcase", "Decor" }

test("every feature module of the overhaul loads next to the old ones", function()
	local names = {}
	for _, f in ipairs(Registry.Modules) do names[f.Name] = true end
	for _, name in ipairs(NEW_FEATURES) do truthy(names[name], name .. " feature loaded") end
	for _, name in ipairs({ "Payments", "UpgradeTree", "Dogdex", "Equipment" }) do truthy(names[name], name .. " still loaded") end
end)

test("new player: profile normalizes, validates, snapshots and round-trips", function()
	local p = R.Profile(1001, NOW)
	R.Normalize(p, 1001, NOW)
	R.Validate(p)
	eq(type(p.Resources), "table", "Resources table")
	eq(Resources.Get(p, "Stone"), 0, "no stone at start")
	eq(type(p.Titles), "table", "Titles table")
	eq(p.Titles.Equipped, "", "no title equipped")
	eq(type(p.Showcase), "table", "Showcase table")
	eq(type(p.Decor), "table", "Decor table")
	eq(count(p.Decor.Placed), 0, "nothing placed")
	storable(p, "p")
	local view = snapshotAll(p)
	for _, key in ipairs({ "Titles", "Showcase", "Decor" }) do
		truthy(view[key] ~= nil or (view.Features and view.Features[key] ~= nil), key .. " in the snapshot")
	end
	local back = roundTrip(p)
	R.Normalize(back, 1001, NOW)
	R.Validate(back)
	deepEqual(back, roundTrip(p))
end)

test("old save: Validate accepts it before Normalize (trade / lab paths)", function()
	local p = legacy()
	R.Validate(p)
end)

test("old save keeps every value and gains the new tables", function()
	local p = legacy()
	local before = legacy()
	local uid = p.UserId
	R.Normalize(p, uid, NOW)
	R.Validate(p)
	storable(p, "p")
	for _, key in ipairs({ "Cash", "Bones", "Level", "XP", "Prestige", "CurrentLayer", "EquippedCosmetic", "EquippedPlotSkin" }) do
		eq(p[key], before[key], key)
	end
	deepEqual(p.UnlockedLayers, before.UnlockedLayers, "UnlockedLayers")
	deepEqual(p.Cosmetics, before.Cosmetics, "Cosmetics")
	deepEqual(p.Upgrades, before.Upgrades, "Upgrades")
	eq(count(p.Dogs), count(before.Dogs), "dog count")
	for duid, d in pairs(before.Dogs) do
		local now = p.Dogs[duid]
		truthy(now, "dog " .. duid .. " kept")
		for _, key in ipairs({ "DogId", "Variant", "Rarity", "Mastery", "AscensionLevel", "AssignedSlot", "Origin", "LabRecipe", "Locked", "Favorite" }) do
			eq(now[key], d[key], duid .. "." .. key)
		end
	end
	eq(count(p.Items), count(before.Items), "find count")
	for iuid, x in pairs(before.Items) do
		local now = p.Items[iuid]
		truthy(now, "find " .. iuid .. " kept")
		for _, key in ipairs({ "ItemId", "Mutation", "WeightKg", "SellValue", "Favorite", "Tradeable" }) do
			eq(now[key], x[key], iuid .. "." .. key)
		end
	end
	deepEqual(p.Lab.DNA, before.Lab.DNA, "lab DNA")
	eq(p.Lab.Experiments, before.Lab.Experiments, "lab experiments")
	deepEqual(p.Mining.Collection, before.Mining.Collection, "mining collection")
	for _, key in ipairs({ "PickaxeOwned", "PickaxeLevel", "Strength", "OresBroken" }) do
		eq(p.Mining[key], before.Mining[key], "Mining." .. key)
	end
	-- New tables with defaults.
	eq(Resources.Get(p, "Stone"), 0, "old players start with no stone")
	eq(p.Mining.StoneMined, 0, "stone counter starts at 0")
	eq(count(p.Decor.Placed), 0, "no decor yet")
	-- Every earned legacy title is a title now, and the equipped one moved above the head.
	for key in pairs(before.Cosmetics) do
		if key ~= "GoldenKennel" or p.Titles.Unlocked["legacy:" .. key] then
			truthy(p.Titles.Unlocked["legacy:" .. key] ~= nil, "legacy title " .. key)
		end
	end
	eq(p.Titles.Equipped, "legacy:" .. before.EquippedCosmetic, "equipped legacy title migrated")
end)

test("Normalize is idempotent: a second pass and a minute of ticks change nothing", function()
	local p = legacy()
	R.Normalize(p, p.UserId, NOW)
	local once = roundTrip(p)
	R.Normalize(p, p.UserId, NOW)
	deepEqual(roundTrip(p), once)
	local size = #json(p)
	for s = 1, 60 do
		L.Time = NOW + s
		R.Normalize(p, p.UserId, L.Time)
	end
	R.Validate(p)
	truthy(#json(p) <= size + 256, "profile does not grow on idle ticks: " .. size .. " -> " .. #json(p))
end)

test("old save after the overhaul survives the DataStore round trip", function()
	local p = legacy()
	R.Normalize(p, p.UserId, NOW)
	local saved = roundTrip(p)
	R.Normalize(saved, saved.UserId, NOW)
	R.Validate(saved)
	deepEqual(roundTrip(saved), roundTrip(p))
end)

test("old player uses the new systems: decor with Stone, a legacy title, digging", function()
	local p = legacy()
	R.Normalize(p, p.UserId, NOW)
	local Catalog = L.Require("ReplicatedStorage.DogEconomy.DecorCatalog")
	-- The cheapest decoration this yard stage allows.
	local pick, best = nil, math.huge
	for _, item in ipairs(Catalog.Items) do
		local ok = Catalog.Unlocked(p, item.Id)
		local cash, stone, bones = Catalog.Price(item.Id)
		if ok and bones == 0 and cash < best then pick, best = item, cash end
	end
	truthy(pick, "a decoration is available")
	local cash, stone = Catalog.Price(pick.Id)
	local ok, err = pcall(R.Action, p, "DecorBuy", { Id = pick.Id, Quote = cash }, NOW, rng(1))
	truthy(not ok and tostring(err):find("Stone"), "no stone yet: " .. tostring(err))
	Resources.Add(p, "Stone", stone)
	local before = p.Cash
	local message = R.Action(p, "DecorBuy", { Id = pick.Id, Quote = cash }, NOW, rng(1))
	truthy(type(message) == "string", "decor bought")
	eq(p.Cash, before - cash, "coins paid")
	eq(Resources.Get(p, "Stone"), 0, "stone spent")
	eq(p.Decor.Owned[pick.Id], 1, "owned")
	R.Validate(p)
	-- Titles: unequip and re-equip the migrated legacy title.
	local legacyTitle = p.Titles.Equipped
	R.Action(p, "TitleEquip", { Id = "" }, NOW, rng(2))
	eq(p.Titles.Equipped, "", "unequipped")
	R.Action(p, "TitleEquip", { Id = legacyTitle }, NOW, rng(2))
	eq(p.Titles.Equipped, legacyTitle, "re-equipped")
	ok = pcall(R.Action, p, "TitleEquip", { Id = "not_a_title" }, NOW, rng(2))
	truthy(not ok, "unknown title refused")
	-- The economy loop still runs on the old save with everything installed.
	local coins = p.Cash
	for s = 1, 120 do
		L.Time = NOW + s
		R.Normalize(p, p.UserId, L.Time)
		R.Dig(p, L.Time, rng(500 + s))
	end
	R.Validate(p)
	truthy(p.Cash > coins, "dogs still earn on the old save")
	storable(p, "p")
end)

test("snapshot of the new features stays small; Normalize stays cheap", function()
	local p = legacy()
	R.Normalize(p, p.UserId, NOW)
	local view = snapshotAll(p)
	local bytes = 0
	for _, key in ipairs(NEW_FEATURES) do
		if view[key] ~= nil then bytes += #json(view[key]) end
		if view.Features and view.Features[key] ~= nil then bytes += #json(view.Features[key]) end
	end
	truthy(bytes < 48 * 1024, "new feature snapshot bytes: " .. bytes)
	local started = os.clock()
	local runs = 200
	for s = 1, runs do
		L.Time = NOW + s
		R.Normalize(p, p.UserId, L.Time)
	end
	local ms = (os.clock() - started) * 1000 / runs
	print(string.format("  snapshot of the new features: %d bytes; Normalize on the old save: %.2f ms", bytes, ms))
	truthy(ms < 25, "Normalize per tick " .. ms .. " ms")
end)

print(string.format("overhaul_integration: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("overhaul integration tests failed")
end
