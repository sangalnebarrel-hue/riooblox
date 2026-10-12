--!nocheck
-- UPGRADE TREE: definitions, purchase rules, saved data, transactions and the stat pipeline.
--   lune run tests/upgrade_tree.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): DogEconomy.UpgradeTree,
-- Features.UpgradeTree, BonusSources.UpgradeTree, Rules, IncomeModel, OfflineEarnings, Engine,
-- Transactions.
local L = require("./lib/economy_env")
local C = L.Require("ReplicatedStorage.DogEconomy.Config")
local T = L.Require("ReplicatedStorage.DogEconomy.UpgradeTree")
local B = L.Require("ReplicatedStorage.DogEconomy.Bonuses")
local PlotCatalog = L.Require("ReplicatedStorage.PlotCatalog")
local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")
local O = L.Require("ServerScriptService.Economy.OfflineEarnings")
local Feature = L.Require("ServerScriptService.Economy.Features.UpgradeTree")

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
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then error((msg or "") .. string.format(" expected %.6g ±%.3g got %.6g", b, tolerance, a), 2) end
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
local function fails(fn, pattern)
	local ok, err = pcall(fn)
	truthy(not ok, "expected an error matching " .. tostring(pattern))
	if pattern then truthy(string.find(tostring(err), pattern, 1, true), "error '" .. tostring(err) .. "' lacks '" .. pattern .. "'") end
	return err
end

local NOW = 1760000000
local function profile(opts)
	opts = opts or {}
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p.Upgrades = table.clone(opts.Upgrades or {})
	p.Cash = opts.Cash or 0
	p.Bones = opts.Bones or 0
	p.XP = C.XPForLevel(opts.Level or 1)
	R.UpdateLevel(p)
	for i = 1, (opts.Layer or 1) do p.UnlockedLayers[tostring(i)] = true end
	p.CurrentLayer = opts.Layer or 1
	p.LastDig = NOW
	for i, id in ipairs(opts.Dogs or {}) do
		local d = R.Mint(p, id, "dog" .. i, {}, NOW, rng(i), "Test", "Normal", true)
		d.AssignedSlot = "DigSlot_" .. i
		d.State = "Digging"
		d.Mastery = opts.Mastery or 0
		d.MasteryXP = (opts.Mastery or 0) ^ 2 * 5
		d.NextWorkAt = NOW
	end
	return p
end
local function buy(p, node, extra)
	local a = { Node = node }
	for k, v in pairs(extra or {}) do a[k] = v end
	return R.Action(p, "TreeUpgrade", a, NOW, rng(3))
end
local LEGACY = { "Dig", "Storage", "Kennel", "Plot", "DogStorage", "Ability" }

-- Definitions -------------------------------------------------------------------------------------
test("every node is well formed and drawn on its own spot", function()
	local spots, count = {}, 0
	for id, node in pairs(T.Nodes) do
		count += 1
		eq(node.Id, id, "id")
		truthy(T.BranchById[node.Branch], id .. " branch")
		truthy(type(node.Name) == "string" and node.Name == string.upper(node.Name) and #node.Name <= 22, id .. " name")
		truthy(type(node.Description) == "string" and #node.Description >= 10, id .. " description")
		-- Numbers come from the definitions (PerLevel, PlotCatalog), never from duplicated literals.
		truthy(not string.find(node.Description, "%d"), id .. " description repeats a number: " .. node.Description)
		truthy(R.Int(node.Max, 1, 20), id .. " max")
		truthy(node.Cost.Base > 0 and node.Cost.Factor > 1, id .. " cost")
		truthy(node.Gate.Base >= 1 and node.Gate.Step >= 0, id .. " gate")
		truthy(type(node.X) == "number" and type(node.Y) == "number" and node.Y ~= 0, id .. " position")
		local spot = node.X .. ":" .. node.Y
		truthy(not spots[spot], id .. " shares a spot with " .. tostring(spots[spot]))
		spots[spot] = id
		truthy(node.Legacy or (T.Stats[node.Stat] and B.Keys and table.find(B.Keys, node.Stat)), id .. " stat key")
		truthy(node.Stat ~= "DepthSpeed", id .. ": depth nodes belong to the depth system")
		eq(T.BranchById[node.Branch].Side == "Crown", node.Y < 0, id .. " side")
	end
	eq(#T.Order, count, "order lists every node")
	truthy(count >= 30, "a big tree")
	for _, branch in ipairs(T.Branches) do
		local n = 0
		for _, node in pairs(T.Nodes) do if node.Branch == branch.Id then n += 1 end end
		truthy(n >= 2, branch.Id .. " has nodes")
	end
end)

test("prerequisites form a tree that starts at the hub (no cycles)", function()
	local state = {}
	local function visit(id, depth)
		truthy(depth < 50, "cycle at " .. id)
		if state[id] == "done" then return end
		truthy(state[id] ~= "open", "cycle at " .. id)
		state[id] = "open"
		for parent, need in pairs(T.Nodes[id].Requires) do
			truthy(R.Int(need, 1, T.Nodes[parent].Max), id .. " needs a reachable level of " .. parent)
			visit(parent, depth + 1)
		end
		state[id] = "done"
	end
	for id in pairs(T.Nodes) do visit(id, 0) end
	local hub = 0
	for _, edge in ipairs(T.Edges) do
		truthy(edge.From == "Hub" or T.Nodes[edge.From], "edge from")
		truthy(T.Nodes[edge.To], "edge to")
		if edge.From == "Hub" then hub += 1; eq(next(T.Nodes[edge.To].Requires), nil, "hub edge only for roots") end
	end
	truthy(hub >= 10, "every branch starts at the hub")
end)

test("every level can be bought under the current level cap", function()
	for id, node in pairs(T.Nodes) do
		for level = 0, node.Max - 1 do
			truthy(T.Gate(id, level) <= C.MaxLevel, id .. " level " .. (level + 1) .. " needs player level " .. T.Gate(id, level))
			if level > 0 then truthy(T.Gate(id, level) >= T.Gate(id, level - 1), id .. " gate never drops") end
		end
	end
end)

test("prices are whole numbers that rise with every level; Bones only on capstones", function()
	for id, node in pairs(T.Nodes) do
		local last = 0
		for level = 0, node.Max - 1 do
			local cash, bones = T.Cost(id, level)
			truthy(R.Int(cash, 1, C.MaxCash) and R.Int(bones, 0, C.MaxCash), id .. " integer price")
			truthy(cash > last, id .. " price rises")
			last = cash
			eq(bones > 0, node.Cost.Bones ~= nil, id .. " bones")
		end
		if node.Cost.Bones then truthy(node.Capstone or node.Tier >= 3, id .. " bones on a late node") end
	end
	eq(T.Nice(12345), 12300, "three significant digits")
	eq(T.Nice(999), 999, "small prices exact")
end)

test("the original six upgrades keep their keys, prices, gates, maxima and effects", function()
	for _, kind in ipairs(LEGACY) do
		local node = T.Nodes[kind]
		local def = C.Upgrades[kind]
		truthy(node and node.Legacy, kind .. " is a node")
		eq(node.Max, def.Max, kind .. " max")
		eq(node.PerLevel, C.UpgradeEffects[kind], kind .. " effect")
		for level = 0, def.Max - 1 do
			eq((T.Cost(kind, level)), math.floor(def.Base * def.Factor ^ level), kind .. " price " .. level)
			eq(T.Gate(kind, level), C.UpgradeLevel(kind, level), kind .. " gate " .. level)
			eq(T.XP(kind, level + 1), 25 + (level + 1) * 10, kind .. " xp")
		end
	end
	eq((T.Cost("Plot", 3)), PlotCatalog.Cost(4), "estate price matches PlotCatalog")
end)

-- The window prints effects from the definitions; these are the server's real numbers.
test("shown effects of the original upgrades equal what the server applies", function()
	for level = 0, T.Nodes.DogStorage.Max do
		local p = profile({ Upgrades = { DogStorage = level } })
		eq(R.Capacity(p), T.Value("DogStorage", level), "dog capacity " .. level)
	end
	for level = 0, T.Nodes.Storage.Max do
		local p = profile({ Upgrades = { Storage = level } })
		eq(I.Capacity(p, 0), 50 + T.Value("Storage", level), "discovery slots " .. level)
		eq(R.Storage(p, NOW).LootCapacity, 50 + T.Value("Storage", level), "loot capacity " .. level)
	end
	for level = 0, T.Nodes.Plot.Max do
		local p = profile({ Upgrades = { Plot = level } })
		eq(PlotCatalog.Level(p), T.Value("Plot", level), "yard stage " .. level)
		eq(T.Stage(level), PlotCatalog.Stages[PlotCatalog.Level(p)], "stage row " .. level)
	end
	-- Dug value of the estate and kennels: Rules.RollMultiplier.
	local base = profile({ Dogs = { "Breadog" } })
	local d = base.Dogs.dog1
	local def = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")[d.DogId]
	local blank = B.Global(base, NOW)
	local m0 = R.RollMultiplier(base, d, def, {}, blank, false, nil)
	for _, kind in ipairs({ "Kennel", "Plot" }) do
		local level = T.Nodes[kind].Max
		base.Upgrades = { [kind] = level }
		local value = kind == "Plot" and T.Nodes.Plot.PerLevel * level or T.Value(kind, level)
		near(R.RollMultiplier(base, d, def, {}, blank, false, nil) / m0, 1 + value, 1e-9, kind .. " dug value")
	end
	-- Dig speed: Rules.Cooldown (Mastery 0 rests 20 s at speed 1).
	for level = 0, T.Nodes.Dig.Max do
		base.Upgrades = { Dig = level }
		local cooldown = R.Cooldown(base, d, {}, blank)
		near(20 / cooldown - 1, T.Value("Dig", level), 1e-9, "dig speed " .. level)
	end
	-- Ability power: the same Rules.Dig with the same random numbers pays +2% per level.
	local function earn(level)
		local p = profile({ Dogs = { "Breadog", "Chipdog", "Melondog" }, Layer = 3, Upgrades = { Ability = level } })
		local random = rng(5)
		local cash = p.Cash
		for t = NOW, NOW + 900 do
			L.Time = t
			R.Dig(p, t, random)
			p.Items = {}
		end
		return p.Cash - cash
	end
	local ratio = earn(6) / earn(0)
	near(ratio, 1 + T.Value("Ability", 6), 0.012, "ability power on real digs")
end)

test("stat nodes feed exactly their Bonuses key; the original upgrades add nothing there", function()
	local random = rng(9)
	for _ = 1, 25 do
		local upgrades = {}
		for id, node in pairs(T.Nodes) do upgrades[id] = math.floor(random() * (node.Max + 1)) end
		local p = profile({ Upgrades = upgrades })
		local totals = T.Totals(p)
		local global = B.Global(p, NOW)
		for _, key in ipairs(B.Keys) do near(global[key], totals[key] or 0, 1e-9, key) end
		near(global.MoneyMultFactor, totals.MoneyMultFactor, 1e-9, "money multiplier factor")
	end
	local legacyOnly = profile({ Upgrades = { Dig = 10, Storage = 10, Kennel = 10, Plot = 8, DogStorage = 10, Ability = 6 } })
	local global = B.Global(legacyOnly, NOW)
	for _, key in ipairs(B.Keys) do eq(global[key], 0, "legacy " .. key) end
	-- Money multipliers multiply each other.
	local money = profile({ Upgrades = { PawsOfGold = 5, DogecoinVault = 5 } })
	near(B.Global(money, NOW).MoneyMultFactor, (1 + 5 * T.Nodes.PawsOfGold.PerLevel) * (1 + 5 * T.Nodes.DogecoinVault.PerLevel), 1e-9, "product")
	-- A corrupt level above the maximum never applies more than the maximum.
	local over = profile({ Upgrades = { TreatBudget = 99 } })
	near(B.Global(over, NOW).Income, T.Value("TreatBudget", T.Nodes.TreatBudget.Max), 1e-9, "clamped")
end)

-- Purchases ---------------------------------------------------------------------------------------
test("TreeUpgrade buys one level at the server price and gives XP", function()
	local p = profile({ Cash = 1000000, Level = 5 })
	local xp = p.XP
	local price = T.Cost("TreatBudget", 0)
	local message, extra = buy(p, "TreatBudget")
	eq(p.Upgrades.TreatBudget, 1, "level")
	eq(p.Cash, 1000000 - price, "exact debit")
	eq(p.XP, xp + T.XP("TreatBudget", 1), "xp")
	eq(extra.Node, "TreatBudget", "reply node")
	eq(extra.Level, 1, "reply level")
	eq(extra.Paid.Cash, price, "reply price")
	truthy(string.find(message, "TREAT BUDGET", 1, true), message)
	-- The client cannot name a price: extra fields are ignored.
	local cash = p.Cash
	buy(p, "TreatBudget", { Price = 1, Cost = 1, Quote = 1 })
	eq(p.Cash, cash - T.Cost("TreatBudget", 1), "server price only")
end)

test("player level gate, prerequisites and maximum are enforced", function()
	local p = profile({ Cash = 1e9, Bones = 1e6, Level = 1 })
	fails(function() R.Action(p, "Upgrade", { Kind = "Plot" }, NOW, rng(1)) end, "Reach level 3 for this upgrade")
	eq(p.Upgrades.Plot, nil, "no level")
	eq(p.Cash, 1e9, "no debit")
	p = profile({ Cash = 1e9, Bones = 1e6, Level = 30, Upgrades = { Dig = 2 } })
	fails(function() buy(p, "QuickPaws") end, "Requires DIG SPEED level 3")
	p.Upgrades.Dig = 3
	buy(p, "QuickPaws")
	eq(p.Upgrades.QuickPaws, 1, "unlocked")
	-- Two prerequisites (money multiplier).
	p.Upgrades.SharpShovels = 8
	fails(function() buy(p, "PawsOfGold") end, "Requires FOUR-LEAF COLLAR level 8")
	p.Upgrades.FourLeafCollar = 8
	buy(p, "PawsOfGold")
	eq(p.Upgrades.PawsOfGold, 1, "both met")
	p.Upgrades.TreatBudget = T.Nodes.TreatBudget.Max
	local cash = p.Cash
	fails(function() buy(p, "TreatBudget") end, "Already at maximum")
	eq(p.Cash, cash, "nothing charged at max")
	-- The gate follows the level being bought.
	p = profile({ Cash = 1e9, Level = 5, Upgrades = { TreatBudget = 4 } })
	eq(T.Gate("TreatBudget", 4), 5, "level 5 needs player level 5")
	buy(p, "TreatBudget")
	fails(function() buy(p, "TreatBudget") end, "Reach level 6 for this upgrade")
end)

test("Cash and Bones are both required for capstones; failures change nothing", function()
	local p = profile({ Cash = 1e12, Bones = 0, Level = 50, Upgrades = { MarketSavvy = 10 } })
	local before = R.Copy(p)
	fails(function() buy(p, "DigTycoon") end, "Not enough Cash or Bones")
	eq(p.Cash, before.Cash, "cash")
	eq(p.Upgrades.DigTycoon, nil, "level")
	local cash, bones = T.Cost("DigTycoon", 0)
	p.Bones = bones
	buy(p, "DigTycoon")
	eq(p.Bones, 0, "bones paid")
	eq(p.Cash, before.Cash - cash, "cash paid")
	p = profile({ Cash = 10, Level = 50 })
	fails(function() buy(p, "TreatBudget") end, "Not enough Cash or Bones")
	eq(p.Upgrades.TreatBudget, nil, "poor player")
end)

test("the old Upgrade action follows the same rules (estate keeps its message)", function()
	local p = profile({ Cash = 1e9, Level = 3 })
	local message = R.Action(p, "Upgrade", { Kind = "Plot" }, NOW, rng(1))
	eq(message, "Yard expanded: " .. PlotCatalog.Stages[2].Name, "estate message")
	eq(PlotCatalog.Level(p), 2, "stage 2")
	eq(PlotCatalog.Slots(p), 2, "second kennel open")
	eq(R.Action(p, "Upgrade", { Kind = "Dig" }, NOW, rng(1)), "Upgrade purchased", "old message")
	fails(function() R.Action(p, "Upgrade", { Kind = "QuickPaws" }, NOW, rng(1)) end, "Reach level 8 for this upgrade")
	p.XP = C.XPForLevel(20)
	R.UpdateLevel(p)
	fails(function() R.Action(p, "Upgrade", { Kind = "QuickPaws" }, NOW, rng(1)) end, "Requires DIG SPEED level 3")
	-- Purchases need no visit anywhere (the gate moved out of Runtime / Engine).
	local YardCommerce = L.Require("ServerScriptService.Economy.YardCommerce")
	eq(YardCommerce.UpgradeVisit(nil, "Plot"), true, "estate anywhere")
	eq(YardCommerce.UpgradeVisit(nil, "QuickPaws"), true, "any node anywhere")
	fails(function() YardCommerce.UpgradeVisit(nil, "Nope") end, "Unknown upgrade")
end)

test("malformed requests are refused", function()
	local p = profile({ Cash = 1e9, Level = 50 })
	for _, node in ipairs({ 5, true, {}, "Nope", string.rep("A", 200), "__index", "Hub", "" }) do
		fails(function() R.Action(p, "TreeUpgrade", { Node = node }, NOW, rng(1)) end, "Unknown upgrade")
	end
	fails(function() R.Action(p, "TreeUpgrade", nil, NOW, rng(1)) end, "Unknown upgrade")
	fails(function() R.Action(p, "Upgrade", {}, NOW, rng(1)) end, "Unknown upgrade")
	-- A stale window (it showed another level) cannot buy the next level by accident.
	buy(p, "TreatBudget", { Level = 0 })
	fails(function() buy(p, "TreatBudget", { Level = 0 }) end, "This upgrade changed")
	fails(function() buy(p, "TreatBudget", { Level = "1" }) end, "This upgrade changed")
	buy(p, "TreatBudget", { Level = 1 })
	eq(p.Upgrades.TreatBudget, 2, "two levels")
	eq(R.Count(p.Upgrades), 1, "nothing else written")
end)

test("levels owned before a requirement existed stay owned and keep working", function()
	-- A profile with QuickPaws but no Dig level (prerequisites are checked when buying only).
	local p = profile({ Cash = 1e9, Level = 50, Upgrades = { QuickPaws = 4 } })
	Feature.Normalize(R, p, NOW)
	eq(p.Upgrades.QuickPaws, 4, "kept")
	near(B.Global(p, NOW).DigSpeed, T.Value("QuickPaws", 4), 1e-9, "still applies")
	fails(function() buy(p, "QuickPaws") end, "Requires DIG SPEED level 3")
end)

-- Saved data --------------------------------------------------------------------------------------
test("Normalize heals malformed entries and never touches valid levels", function()
	local p = profile({ Upgrades = { Dig = 7, Plot = 3, Storage = 10, Kennel = 0, DogStorage = 2, Ability = 6, TreatBudget = 2,
		LuckyNose = -3, ShinyPolish = 2.7, RelicRadar = 0 / 0, TurboDig = 99, FutureNode = 4, Bad = "x", [7] = 3 } })
	p.UpgradeTreeVersion = nil
	Feature.Normalize(R, p, NOW)
	local u = p.Upgrades
	eq(u.Dig, 7, "Dig");eq(u.Plot, 3, "Plot");eq(u.Storage, 10, "Storage");eq(u.Kennel, 0, "Kennel");eq(u.DogStorage, 2, "DogStorage")
	eq(u.Ability, 6, "Ability");eq(u.TreatBudget, 2, "TreatBudget")
	eq(u.LuckyNose, 0, "negative");eq(u.ShinyPolish, 2, "fraction");eq(u.RelicRadar, 0, "nan")
	eq(u.TurboDig, T.Nodes.TurboDig.Max, "above max")
	eq(u.FutureNode, 4, "unknown node kept")
	eq(u.Bad, nil, "garbage dropped");eq(u[7], nil, "numeric key dropped")
	eq(p.UpgradeTreeVersion, T.Version, "version")
	Feature.Validate(R, p)
	R.Validate(p)
	-- Idempotent.
	local copy = R.Copy(p.Upgrades)
	Feature.Normalize(R, p, NOW)
	for k, v in pairs(copy) do eq(p.Upgrades[k], v, "idempotent " .. k) end
	p.Upgrades = "corrupt"
	Feature.Normalize(R, p, NOW)
	eq(type(p.Upgrades), "table", "table restored")
end)

test("Validate checks structure only and accepts profiles that were never normalized", function()
	local p = profile({ Upgrades = { Dig = 3, TreatBudget = 2 } })
	p.UpgradeTreeVersion = nil
	Feature.Validate(R, p)
	p.Upgrades = nil
	Feature.Validate(R, p)
	for _, bad in ipairs({ { Dig = -1 }, { Dig = 1.5 }, { Dig = 11 }, { TreatBudget = 0 / 0 }, { TreatBudget = "3" }, { [1] = 2 }, { Future = 5000 } }) do
		p.Upgrades = bad
		fails(function() Feature.Validate(R, p) end)
	end
	p.Upgrades = { Future = 7 }
	Feature.Validate(R, p)
end)

test("an old save (before the tree) loads with every upgrade level unchanged", function()
	local old = profile({ Cash = 12345, Level = 20, Upgrades = { Dig = 10, Storage = 4, Kennel = 3, Plot = 8, DogStorage = 5, Ability = 6 } })
	old.UpgradeTreeVersion = nil
	local saved = R.Copy(old.Upgrades)
	local p = R.Normalize(R.Copy(old), 1, NOW)
	for k, v in pairs(saved) do eq(p.Upgrades[k], v, k) end
	eq(R.Count(p.Upgrades), R.Count(saved), "no new keys")
	eq(p.UpgradeTreeVersion, T.Version, "version set")
	eq(p.Cash, 12345, "wallet untouched")
	R.Validate(p)
end)

test("snapshot reports tree progress", function()
	local p = profile({ Upgrades = { Dig = 3, TreatBudget = 2 } })
	local view = {}
	R.Features.Snapshot(R, p, view, NOW)
	local owned, total = T.Progress(p)
	eq(owned, 5, "owned levels")
	eq(view.UpgradeTree.Levels, owned, "levels")
	eq(view.UpgradeTree.MaxLevels, total, "max levels")
end)

-- Transactions ------------------------------------------------------------------------------------
test("a purchase through Engine:Action is atomic and answered once per request id", function()
	L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end, Current = function() return 1 end }
	local Tx = L.Require("ServerScriptService.Economy.Transactions")
	local Engine = L.Require("ServerScriptService.Economy.Engine")
	local data = {}
	local store = {}
	function store:Read(k) return R.Copy(data[k]) end
	function store:Update(k, fn)
		local v = fn(R.Copy(data[k]))
		if v ~= nil then data[k] = R.Copy(v) end
		return R.Copy(v)
	end
	local n = 0
	local function guid() n += 1; return string.format("%032x", n) end
	local clock = function() return NOW end
	local tx = Tx.new(store, clock, guid, {})
	local engine = Engine.new(tx, { Now = clock, Guid = guid, Random = function() return 0.5 end, Session = "S1" })
	local ok, err = engine:Join(1)
	truthy(ok, "join: " .. tostring(err))
	ok, err = tx:Run({ "p:1" }, function(v)
		local p = v["p:1"]
		p.Cash = 50000
		p.XP = C.XPForLevel(10)
		R.UpdateLevel(p)
		return true
	end)
	truthy(ok, "seed: " .. tostring(err))
	local okA, a = engine:Action(1, "TreeUpgrade", { Node = "TreatBudget" }, "1:request-a")
	local okB, b = engine:Action(1, "TreeUpgrade", { Node = "TreatBudget" }, "1:request-a")
	truthy(okA and okB, "both answered: " .. tostring(a) .. " / " .. tostring(b))
	eq(a.Message, b.Message, "same reply")
	local p = tx:Read("p:1")
	eq(p.Upgrades.TreatBudget, 1, "bought once")
	eq(p.Cash, 50000 - T.Cost("TreatBudget", 0), "charged once")
	-- A refused purchase leaves the profile as it was.
	local before = R.Copy(tx:Read("p:1"))
	local okC, c = engine:Action(1, "TreeUpgrade", { Node = "DigTycoon" }, "1:request-c")
	truthy(not okC and string.find(tostring(c), "Reach level", 1, true), "refused: " .. tostring(c))
	local after = tx:Read("p:1")
	eq(after.Cash, before.Cash, "cash")
	eq(R.Count(after.Upgrades), R.Count(before.Upgrades), "upgrades")
	-- Anywhere: the engine no longer asks for a workshop visit (no player object exists here).
	local okD = engine:Action(1, "Upgrade", { Kind = "Storage" }, "1:request-d")
	truthy(okD, "estate/storage upgrade without a visit")
	eq(tx:Read("p:1").Upgrades.Storage, 1, "storage bought")
	L.Overrides["ServerScriptService/Economy/ServerLuck"] = nil
end)

-- The tree in the economy ---------------------------------------------------------------------------
test("earnings, dog power and money nodes raise the real income model", function()
	local team = { "Breadog", "Chipdog", "Melondog", "Corndoggo", "Tacodach" }
	local base = R.IncomeModel(profile({ Dogs = team, Layer = 2, Mastery = 20 }), NOW).PerMinute
	local function with(upgrades) return R.IncomeModel(profile({ Dogs = team, Layer = 2, Mastery = 20, Upgrades = upgrades }), NOW).PerMinute end
	near(with({ TreatBudget = 10 }) / base, 1 + T.Value("TreatBudget", 10), 0.01, "earnings")
	near(with({ PuppyTraining = 10 }) / base, 1 + T.Value("PuppyTraining", 10), 0.01, "dog power")
	near(with({ PawsOfGold = 5 }) / base, 1 + T.Value("PawsOfGold", 5), 0.01, "money")
	truthy(with({ QuickPaws = 10 }) > base * 1.05, "speed")
	truthy(with({ LuckyNose = 10 }) > base * 1.01, "luck")
	truthy(with({ TreasureSense = 10 }) > base, "rare finds")
	truthy(with({ ShinyPolish = 10 }) > base, "find mutations")
end)

test("speed nodes still pay when dogs already rest the minimum (overflow rolls)", function()
	local team = { "Breadog", "Chipdog" }
	local p = profile({ Dogs = team, Mastery = 100, Upgrades = { Dig = 10 } })
	local before = R.IncomeModel(p, NOW)
	p.Upgrades.QuickPaws = 10
	p.Upgrades.TirelessDiggers = 10
	local after = R.IncomeModel(p, NOW)
	local d1, d2 = before.Dogs.dog1, after.Dogs.dog1
	eq(d1.Cooldown, C.Work.MinCooldown, "at the floor")
	truthy(d2.Overflow > d1.Overflow, "more overflow rolls")
	truthy(after.PerMinute > before.PerMinute * 1.05, "more income")
end)

test("offline, XP, storage and dog-mutation nodes reach their systems", function()
	local team = { "Breadog", "Chipdog" }
	local p = profile({ Dogs = team })
	local rate = O.Estimate(p)
	p.Upgrades.NightShift = 10
	near(O.Estimate(p) / rate, 1 + T.Value("NightShift", 10), 1e-6, "offline earnings")
	local q = profile({ Upgrades = { Storage = 2 } })
	local slots = I.Capacity(q)
	q.Upgrades.BiggerCrates = 10
	eq(I.Capacity(q), slots + T.Value("BiggerCrates", 10), "discovery slots")
	local function mutated(profileOrNil)
		local rows = R.VariantRows(profileOrNil, NOW)
		local total, m = 0, 0
		for i, row in ipairs(rows) do total += row.Weight; if i > 1 then m += row.Weight end end
		return m / total
	end
	local plain = mutated(profile())
	local genes = mutated(profile({ Upgrades = { GoodGenes = 10 } }))
	near(genes / plain, 1 + T.Value("GoodGenes", 10), 1e-6, "mutated dog chance")
	-- XP: the same digs give more XP.
	local function xp(level)
		local r = profile({ Dogs = team, Upgrades = { FastLearner = level } })
		local random = rng(4)
		local start = r.XP
		for t = NOW, NOW + 600 do L.Time = t; R.Dig(r, t, random) end
		return r.XP - start
	end
	truthy(xp(10) > xp(0) * 1.3, "xp gain")
end)

-- Helpers used by the window -------------------------------------------------------------------------
test("status, requirements, text and summary agree with the server rules", function()
	local p = profile({ Cash = 0, Level = 1 })
	eq(T.Status(p, "TreatBudget"), "ready", "unlocked, no cash")
	p.Cash = T.Cost("TreatBudget", 0)
	eq(T.Status(p, "TreatBudget"), "affordable", "affordable")
	eq(T.Status(p, "SharpShovels"), "locked", "needs TREAT BUDGET")
	eq(T.Status(p, "Plot"), "locked", "level gate")
	p.Upgrades.TreatBudget = 10
	eq(T.Status(p, "TreatBudget"), "max", "max")
	local ok, why = T.Check(p, "SharpShovels")
	eq(ok, false, "check")
	eq(why, "Reach level 9 for this upgrade", "first unmet requirement")
	local rows = T.Requirements(profile({ Upgrades = { SharpShovels = 8 } }), "PawsOfGold")
	eq(#rows, 3, "level + two nodes")
	eq(rows[1].Kind, "Level", "level first")
	eq(rows[2].Node, "SharpShovels", "branch order")
	eq(rows[2].Met, true, "met")
	eq(rows[3].Met, false, "unmet")
	-- Bonus text from the definitions.
	eq((T.Text("QuickPaws", 3)), "+6%", "percent")
	eq((T.Text("PawsOfGold", 2)), "x1.06", "multiplier")
	eq((T.Text("BiggerCrates", 4)), "+40", "units")
	eq((T.Text("DogStorage", 2)), "60", "dog count")
	eq((T.Text("Kennel", 3)), "+4.5%", "legacy kennel")
	eq((T.Text("Plot", 0)), PlotCatalog.Stages[1].Name, "stage")
	local summary = {}
	for _, row in ipairs(T.Summary(profile({ Upgrades = { Dig = 5, QuickPaws = 5, TreatBudget = 10, Plot = 2, Kennel = 2 } }))) do summary[row.Id] = row end
	eq(summary.DigSpeed.Text, T.FormatValue("percent", (1 + 5 * C.UpgradeEffects.Dig) * (1 + 5 * T.Nodes.QuickPaws.PerLevel) - 1), "combined speed")
	eq(summary.Income.Text, "+20%", "earnings")
	eq(summary.Estate.Text, "+8%", "estate and kennels")
	eq(summary.Plot.Kennels, 3, "kennels")
	truthy(summary.Value.Active and not summary.Luck.Active, "active flags")
end)

-- Localization ----------------------------------------------------------------------------------
test("every string the tree shows has exactly one Russian translation", function()
	local fs = require("@lune/fs")
	local function read(path) return fs.readFile(path) end
	local base = {}
	local auto = read("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en, ru in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"([^"]*)"') do base[en] = ru end
	local Dict = L.Require("ReplicatedStorage.Localization.UpgradeTree")
	truthy(type(Dict.Exact) == "table" and type(Dict.Patterns) == "table" and type(Dict.Phrases) == "table", "dictionary shape")
	local function russian(ru, what)
		truthy(type(ru) == "string" and ru ~= "", "translation for " .. what)
		truthy(not string.find((ru:gsub("%%[%ds]", ""):gsub("XP", "")), "[A-Za-z]"), "Latin letters in the translation of " .. what .. ": " .. ru)
	end
	for en, ru in pairs(Dict.Exact) do
		truthy(base[en] == nil, "Exact repeats a base dictionary entry (it would override it): " .. en)
		russian(ru, en)
	end
	for en, ru in pairs(Dict.Window) do
		truthy(base[en] ~= nil and base[en] == ru, "Window entry must reuse the base translation: " .. en)
	end
	local function has(en, where)
		truthy(Dict.Exact[en] or Dict.Window[en], "untranslated (" .. where .. "): " .. en)
	end
	for _, branch in ipairs(T.Branches) do has(branch.Name, "branch"); has(branch.Description, "branch") end
	for id, node in pairs(T.Nodes) do has(node.Name, id); has(node.Description, id); has(node.Label, id) end
	for _, stat in pairs(T.Stats) do has(stat.Label, "stat") end
	for _, row in ipairs(T.Summary({})) do has(row.Label, "summary") end
	for _, stage in ipairs(PlotCatalog.Stages) do has(stage.Name, "stage"); has(stage.Feature, "stage") end
	-- Literal strings of the window: L("...") and LF("...", ...).
	local source = read("src/StarterGui/ScreenGui/Modules/UpgradeTreeScreen.luau")
	local count = 0
	for en in string.gmatch(source, '[^%w]L%("([^"]+)"%)') do has(en, "window"); count += 1 end
	for en in string.gmatch(source, 'LF%("([^"]+)"') do
		local ru = Dict.Templates[en]
		truthy(ru, "missing template: " .. en)
		local _, a = string.gsub(en, "%%s", "")
		local _, b = string.gsub(ru, "%%s", "")
		eq(a, b, "placeholders of " .. en)
		count += 1
	end
	truthy(count >= 30, "window strings found: " .. count)
	-- Server replies the window translates.
	for _, en in ipairs({ "Unknown upgrade", "Already at maximum", "Not enough Cash or Bones", "This upgrade changed. Check the new price and try again" }) do has(en, "server") end
	-- Strings added to other screens (AutoTranslate): exact entries.
	for _, en in ipairs({ "UPGRADE TREE", "OPEN UPGRADE TREE", "6 · GROW YOUR UPGRADE TREE", "Estate stages are bought in the UPGRADE TREE.",
		"All upgrades now live in the UPGRADE TREE: dogs, digging, luck, storage and your estate. Buy them anywhere.",
		"Open the UPGRADE TREE (yard workshop, MY YARD or this button). Tap a glowing node, check the bonus it gives and press BUY. Every node has a Cash price and a player-level requirement." }) do
		truthy(Dict.Exact[en] or base[en], "untranslated screen text: " .. en)
	end
	-- Patterns for the estate lines of the YARD STYLES screen.
	local function apply(text)
		for _, rule in ipairs(Dict.Patterns) do text = string.gsub(text, rule[1], rule[2]) end
		return text
	end
	eq(apply("NEXT · DIGGING DUO · 18.8K Cash · Lv. 7"), "NEXT · DIGGING DUO · 18.8K монет · ур. 7", "next stage line")
	eq(apply("3 / 5 kennels · +5% dug value"), "Будок: 3 / 5 · +5% к ценности раскопок", "kennels line")
end)

print(string.format("upgrade_tree: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("upgrade_tree tests failed")
end
