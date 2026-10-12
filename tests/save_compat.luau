--!nocheck
--!nolint
-- Saved-profile compatibility across the overhaul: lune run tests/save_compat.luau
-- Fixtures: a brand-new player; a "pre-overhaul" profile made with today's Rules (dogs, finds, lab
-- DNA, mining, cosmetics, plot skins) without the overhaul's feature keys; corrupted feature fields;
-- fields of a later build ("future version"); a whale (220 dogs, 1000 finds). For each one:
-- Rules.Normalize twice is idempotent (deep-equal), Rules.Validate passes, a JSON round trip loses
-- nothing, every registered feature's data is in place, and Engine Join -> Leave -> FlushProfile
-- works on the memory store (REAL Runtime, tests/lib/server_world).
--
-- EXTENDING (every overhaul feature does this): add an entry to FEATURES below, keyed by the
-- feature's Name. The test fails while a registered feature has no entry. Fields:
--   Key      the top-level profile key the feature's Normalize creates (nil = optional data)
--   Check(p, fixture)   asserts on the normalized data (fixture = the fixture's name)
--   Corrupt(p)          breaks the feature's saved data (Normalize must heal it)
--   Future(p)           writes data of a later version (Normalize must keep it)
--   Fixture(p, W)       adds the feature's own data to the pre-overhaul profile (optional)
local process = require("@lune/process")
local serde = require("@lune/serde")
local World = require("./lib/server_world")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
-- Deep equality with a path in the message. tolerance: relative slack for numbers (JSON encoders,
-- Roblox's included, do not promise the last bit of a double).
local function diff(a, b, path, tolerance)
	if type(a) ~= type(b) then
		return path .. ": " .. type(a) .. " vs " .. type(b)
	end
	if type(a) == "number" and tolerance and math.abs(a - b) <= tolerance * math.max(1, math.abs(a)) then
		return nil
	end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then
			return path .. ": " .. tostring(a) .. " vs " .. tostring(b)
		end
		return nil
	end
	for k, v in a do
		local d = diff(v, b[k], path .. "." .. tostring(k), tolerance)
		if d then
			return d
		end
	end
	for k in b do
		if a[k] == nil then
			return path .. "." .. tostring(k) .. " is new"
		end
	end
	return nil
end
local function same(a, b, msg, tolerance)
	local d = diff(a, b, "p", tolerance)
	if d then
		error((msg or "") .. " " .. d, 2)
	end
end
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local r = {}
	for k, x in v do
		r[k] = copy(x)
	end
	return r
end

local W = World.new()
local L, R = W.L, W.Rules
local NOW = L.Now
local I = L.Require("ServerScriptService/Economy/ItemRules")
local Items = L.Require("ReplicatedStorage/DogEconomy/ItemDefinitions")
local Dogs = L.Require("ReplicatedStorage/DogEconomy/DogDefinitions")
local Tree = L.Require("ReplicatedStorage/DogEconomy/UpgradeTree")
local SettingsConfig = L.Require("ReplicatedStorage/SettingsConfig")
local Mining = L.Require("ReplicatedStorage/Mining/MiningRules")
local Config = L.Require("ServerScriptService/Economy/Config")

-- ===== Per-feature checks =====
local FEATURES = {
	Payments = {
		-- p.Passes / LuckReserve / ServerLuckCredits exist only once something was bought.
		Corrupt = function(p)
			p.Passes = { [123456] = true }
			p.LuckReserve = "x"
		end,
		Check = function(p, fixture)
			if fixture == "corrupted feature fields" then
				eq(p.Passes["123456"], true, "numeric pass keys become strings")
				eq(p.LuckReserve, nil)
			end
		end,
	},
	UpgradeTree = {
		Key = "Upgrades",
		Check = function(p, fixture)
			eq(type(p.Upgrades), "table")
			truthy(p.UpgradeTreeVersion >= Tree.Version, "tree version")
			if fixture == "corrupted feature fields" then
				eq(p.Upgrades.Dig, 0, "a malformed level of a known node")
				eq(p.Upgrades.Storage, 5, "a fractional level")
				eq(p.Upgrades.LaterNode, 3, "a node of a later build is kept")
				eq(p.Upgrades[3], nil, "a numeric key")
			end
		end,
		-- Bad values inside the table (a lost p.Upgrades would also re-lock kennels: see
		-- docs/OVERHAUL.md, known gaps).
		Corrupt = function(p)
			p.Upgrades.Dig = "x"
			p.Upgrades.Storage = 5.7
			p.Upgrades.LaterNode = 3
			p.Upgrades[3] = 1
		end,
	},
	Settings = {
		Key = "Settings",
		Check = function(p, fixture)
			for _, row in SettingsConfig.Keys do
				truthy(SettingsConfig.Valid(row.Key, p.Settings[row.Key]), "setting " .. row.Key)
				if fixture == "brand-new" or fixture == "pre-overhaul" or fixture == "corrupted feature fields" then
					eq(p.Settings[row.Key], row.Default, "default " .. row.Key)
				end
			end
			if fixture == "future version" then
				eq(p.Settings.Version, 4, "a later version is kept")
				eq(p.Settings.Quality, "High")
				eq(p.Settings.SpatialAudio, true, "a later key is kept")
			else
				eq(p.Settings.Version, 1)
			end
		end,
		Corrupt = function(p)
			p.Settings = { Quality = 5, UIVolume = "loud", ReducedMotion = "yes", Version = -2 }
		end,
		Future = function(p)
			p.Settings = { Version = 4, Quality = "High", SpatialAudio = true }
		end,
	},
	Equipment = {
		Key = "Equipment",
		Check = function(p)
			eq(type(p.Equipment.Artifacts), "table")
			eq(type(p.Equipment.Accessories), "table")
		end,
		Corrupt = function(p)
			p.Equipment = 7
		end,
	},
	Dogdex = {
		Key = "VariantDex",
		Check = function(p)
			for _, d in p.Dogs do
				eq(p.VariantDex[d.DogId][d.Variant], true, "variant of " .. d.DogUid)
			end
		end,
		Corrupt = function(p)
			p.VariantDex = "x"
			p.DexClaims = { [10] = true }
		end,
	},
}

-- ===== Fixtures =====
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local DOG_IDS, ITEM_IDS = {}, {}
for id, def in Dogs do
	if def.Available and not def.Reserved then
		table.insert(DOG_IDS, id)
	end
end
table.sort(DOG_IDS)
for id in Items do
	table.insert(ITEM_IDS, id)
end
table.sort(ITEM_IDS)
local VARIANTS = { "Normal", "Shiny", "Golden", "Corrupted", "Glitched", "Void" }

-- A profile as the pre-overhaul build saved it: today's Rules, then the overhaul keys removed.
local function preOverhaul(uid, dogs, items)
	local random = rng(uid)
	local p = R.Profile(uid, NOW - 86400 * 30)
	p.Upgrades = { Storage = 10, DogStorage = 12, Plot = 2, Dig = 3 }
	p.XP = Config.XPForLevel(25)
	p.Cash, p.Bones = 2500000, 340
	for i = 1, 4 do
		p.UnlockedLayers[tostring(i)] = true
	end
	p.CurrentLayer = 3
	for i = 1, dogs do
		local d = R.Mint(p, DOG_IDS[(i - 1) % #DOG_IDS + 1], "dog" .. i, {}, NOW - i, random, "Test", VARIANTS[(i - 1) % #VARIANTS + 1], true)
		d.Mastery = i % 101
		d.MasteryXP = d.Mastery ^ 2 * 5
		if i % 7 == 0 then
			d.Favorite = true
		end
		if i % 11 == 0 then
			d.Locked = true
		end
		for t = 1, i % 4 do
			R.Transfer(d, p, NOW - t, "Trade")
		end
	end
	for slot = 1, math.min(3, dogs) do
		p.Dogs["dog" .. slot].AssignedSlot = "DigSlot_" .. slot
		p.Dogs["dog" .. slot].State = "Digging"
	end
	for i = 1, items do
		local def = Items[ITEM_IDS[(i - 1) % #ITEM_IDS + 1]]
		local x = I.Mint(p, def, def.BaseDropChance, "item" .. i, NOW - i, random, { ItemCapacity = I.HardCap })
		if i % 9 == 0 then
			x.Favorite = true
		end
	end
	p.Lab.DNA = { CommonDNA = 12, RareDNA = 3, FOOD = 2 }
	p.Lab.Experiments = 4
	p.Mining.PickaxeOwned, p.Mining.PickaxeLevel, p.Mining.Strength, p.Mining.OresBroken = 3, 3, 40, 120
	p.Cosmetics = { Dex10 = true, Finds100 = true, SetExplorers = true }
	p.PlotSkins = { Classic = true, BoneRain = true }
	p.EquippedPlotSkin = "BoneRain"
	p = R.Normalize(p, uid, NOW)
	for name, entry in FEATURES do
		if entry.Fixture then
			entry.Fixture(p, W)
		end
	end
	-- Keys the overhaul adds: absent from every pre-overhaul save.
	p.Settings = nil
	p.Session = nil
	return p
end

local FIXTURES = {
	{ Name = "brand-new", Build = function() return nil end },
	{ Name = "pre-overhaul", Build = function(uid) return preOverhaul(uid, 12, 40) end },
	{
		Name = "corrupted feature fields",
		Build = function(uid)
			local p = preOverhaul(uid, 6, 10)
			for _, entry in FEATURES do
				if entry.Corrupt then
					entry.Corrupt(p)
				end
			end
			return p
		end,
	},
	{
		Name = "future version",
		Build = function(uid)
			local p = preOverhaul(uid, 6, 10)
			for _, entry in FEATURES do
				if entry.Future then
					entry.Future(p)
				end
			end
			-- A top-level key of a feature this build does not know.
			p.FutureFeature = { Version = 3, Slots = { "a", "b" }, Enabled = true }
			return p
		end,
		Check = function(p)
			same(p.FutureFeature, { Version = 3, Slots = { "a", "b" }, Enabled = true }, "unknown key kept")
		end,
	},
	{ Name = "whale", Build = function(uid) return preOverhaul(uid, 220, 1000) end, Whale = true },
}

test("every registered feature has a save_compat entry", function()
	local names = {}
	for _, f in W.Registry.Modules do
		truthy(FEATURES[f.Name], "add tests/save_compat.luau FEATURES." .. f.Name)
		names[f.Name] = true
	end
	for name in FEATURES do
		truthy(names[name], "FEATURES." .. name .. " is not a registered feature")
	end
end)

local uid = 100
for _, fixture in FIXTURES do
	uid += 1
	local id = uid
	local raw = fixture.Build(id)

	test(fixture.Name .. ": Normalize twice is idempotent, Validate passes, JSON loses nothing", function()
		local p = R.Normalize(copy(raw), id, NOW)
		local once = copy(p)
		R.Normalize(p, id, NOW)
		same(p, once, "second Normalize changed")
		R.Validate(p)
		local json = serde.encode("json", p)
		same(serde.decode("json", json), p, "JSON round trip", 1e-12)
		if fixture.Whale then
			eq(R.Count(p.Dogs), 220)
			eq(R.Count(p.Items), 1000)
			truthy(#json < 2 * 1024 * 1024, ("whale profile is %.2f MB"):format(#json / 1048576))
			print(("save_compat: whale profile %.2f MB of JSON"):format(#json / 1048576))
		end
	end)

	test(fixture.Name .. ": every feature's data is in place", function()
		local p = R.Normalize(copy(raw), id, NOW)
		for _, f in W.Registry.Modules do
			local entry = FEATURES[f.Name]
			if entry and entry.Key then
				truthy(p[entry.Key] ~= nil, f.Name .. " creates p." .. entry.Key)
			end
			if entry and entry.Check then
				entry.Check(p, fixture.Name)
			end
		end
		if fixture.Check then
			fixture.Check(p)
		end
	end)

	test(fixture.Name .. ": Join -> Leave -> FlushProfile on the memory store", function()
		local key = "p:" .. id
		if raw ~= nil then
			W.Store.Data[key] = { Revision = 3, Value = copy(raw) }
		end
		local player = W.Join(id)
		local live = W.Profile(id)
		truthy(live.Session and live.Settings, "joined with a session and settings")
		player:SetAttribute("EconomyLeaving", true)
		local left, why = W.Engine:Leave(id, { Timeout = 5 })
		truthy(left, tostring(why))
		local saved, message = W.Tx:FlushProfile(id)
		truthy(saved, tostring(message))
		local stored = W.Store.Data[key].Value
		eq(stored.Session, nil, "released")
		truthy(stored.Settings and stored.Settings.Version >= 1, "settings saved")
		if raw ~= nil then
			eq(R.Count(stored.Dogs), R.Count(raw.Dogs), "dogs kept")
			eq(R.Count(stored.Items), R.Count(raw.Items), "finds kept")
			eq(stored.Cash >= raw.Cash, true, "coins kept")
		end
		local again = R.Normalize(copy(stored), id, NOW)
		R.Validate(again)
		same(serde.decode("json", serde.encode("json", stored)), stored, "the saved record is JSON-safe", 1e-12)
		W.Tx:UnloadProfile(id)
		W.Runtime.Loaded[id] = nil
	end)
end

print(("save_compat: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
