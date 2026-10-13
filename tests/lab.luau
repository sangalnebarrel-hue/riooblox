--!nocheck
-- Genetics lab: shared rules (ReplicatedStorage.LabGenetics), server rules (Economy.LabRules) and the commit
-- protocol (Economy.LabService) on the real modules from src/ (tests/lib/economy_env.luau), the NUCLEAR
-- MUTATION MACHINE (LabConfig.SimpleMode: only 'Mutation' is served, odds and costs unchanged; the machine
-- builder and its layout), old profiles, plus the localization coverage of the lab windows.
-- lune run tests/lab.luau
local fs = require("@lune/fs")
local L = require("./lib/economy_env")

local NOW = 1760000000
L.Time = NOW

-- LabService needs the terminal check and the runtime: a fake terminal (always in reach) and a small runtime
-- (one profile, one RAM transaction) stand in for them.
local access = { Distance = 7.5, Reach = true }
function access.CanUse()
	return access.Reach
end
function access.Model()
	return nil
end
L.Overrides["ReplicatedStorage/LabAccess"] = access
local runtime = { Engine = { TradeByUser = {} }, Tx = {} }
L.Overrides["ServerScriptService/Economy/Runtime"] = runtime

local C = L.Require("ReplicatedStorage.LabConfig")
local G = L.Require("ReplicatedStorage.LabGenetics")
local Defs = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")
local Base = L.Require("ReplicatedStorage.DogEconomy.Config")
local B = L.Require("ReplicatedStorage.DogEconomy.Bonuses")
local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")
local LR = L.Require("ServerScriptService.Economy.LabRules")
local LS = L.Require("ServerScriptService.Economy.LabService")
local Recipes = L.Require("ServerScriptService.Economy.LabRecipeConfig")
local Dict = L.Require("ReplicatedStorage.Localization.Lab")
local Audio = L.Require("ReplicatedStorage.LabAudioConfig")
-- Production templates live in ServerStorage (not in src): every recipe output counts as ready here.
LR.TemplateReady = function(def)
	return def ~= nil
end
-- Real bonus sources (upgrade tree, artifacts...) are set aside so the odds below are the base ones.
local installedSources = table.clone(B.Sources)
table.clear(B.Sources)

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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function near(a, b, tol, msg)
	if math.abs(a - b) > tol then
		error((msg or "") .. string.format(" expected %.6g got %.6g", b, a), 2)
	end
end
local function errors(fn, expected)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error: " .. tostring(expected), 2)
	end
	if expected and not string.find(tostring(err), expected, 1, true) then
		error("expected error '" .. expected .. "' got '" .. tostring(err) .. "'", 2)
	end
	return err
end
local function fixed(...)
	local list = { ... }
	local i = 0
	return function()
		i += 1
		return list[(i - 1) % #list + 1]
	end
end

local uidCount = 0
local function newUid(prefix)
	uidCount += 1
	return string.format("%s%028d", prefix or "dog-", uidCount):sub(1, 32)
end
-- A profile at level 30 (every lab tier unlocked) with money.
local function profile(opts)
	opts = opts or {}
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p.XP = Base.XPForLevel(opts.Level or 30)
	R.UpdateLevel(p)
	p.Cash = opts.Cash or 10000000
	p.Bones = opts.Bones or 10000
	p.Lab = nil
	R.Normalize(p, 1, NOW)
	return p
end
local function dog(p, id, opts)
	opts = opts or {}
	local uid = newUid()
	local d = R.Mint(p, id, uid, {}, NOW, function()
		return 0.5
	end, "Test", opts.Variant or "Normal", true)
	d.Mastery = opts.Mastery or 0
	d.AscensionLevel = opts.Ascension or 0
	for k, v in pairs(opts.Set or {}) do
		d[k] = v
	end
	return d
end
local function item(p, id)
	local uid = newUid("item")
	local def = I.Definitions[id]
	p.Items[uid] = { ItemUid = uid, ItemId = id, DisplayName = def and def.DisplayName or id, OwnerUserId = p.UserId, Tradeable = true, Favorite = false, SellValue = 10, WeightKg = 0.1 }
	return uid
end

------------------------------------------------------------------------------------------------
-- LabGenetics (shared)
------------------------------------------------------------------------------------------------
test("tags: config override, catalogue aliases, NORMAL fallback", function()
	local t = G.Tags("Breadog")
	eq(#t, 2)
	truthy(table.find(t, "FOOD") and table.find(t, "NORMAL"))
	-- The override table itself is never handed out (callers may not mutate it).
	table.insert(t, "X")
	eq(#C.Genetics.Breadog, 2, "override table untouched")
	truthy(table.find(G.Tags("Sausagedog"), "NORMAL"), "Dachshund -> NORMAL")
	eq(G.Tags({ DogId = "Aurion" })[1], "NORMAL", "Cosmic has no sample: NORMAL")
	for id in pairs(Defs) do
		truthy(#G.Tags(id) > 0, id)
	end
end)

test("eligibility: server order, messages and one-tap fixes", function()
	local p = profile()
	local d = dog(p, "Breadog")
	truthy(G.Check(p, d))
	d.Locked = true
	d.AssignedSlot = "DigSlot_1"
	local ok, code, message = G.Check(p, d)
	eq(ok, false)
	eq(code, "Locked", "locked wins over kennel (Rules.Dog order)")
	eq(message, "Unlock this dog first")
	eq(G.Fix(code, d).Action, "DogLock")
	d.Locked = false
	_, code = G.Check(p, d)
	eq(code, "Kennel")
	eq(G.Fix(code, d).Action, "Remove")
	d.AssignedSlot = ""
	d.State = "Digging"
	_, code = G.Check(p, d)
	eq(code, "Busy")
	d.State = "Inventory"
	d.Favorite = true
	_, code = G.Check(p, d)
	eq(code, "Favorite")
	eq(G.Fix(code, d).Args.Enabled, false)
	d.Favorite = false
	p.DisplayDogs = { ["1"] = d.DogUid }
	_, code = G.Check(p, d)
	eq(code, "Display")
	eq(G.Fix(code, d), nil, "display needs the storage visit")
	p.DisplayDogs = {}
	d.State = "Walking"
	_, code = G.Check(p, d)
	eq(code, "Walking")
	eq(select(2, G.Check(p, nil)), "Missing")
end)

test("valuable dogs: Epic+, variants, ascension, mastery, lab-made, artifacts (nil-safe)", function()
	local p = profile()
	local plain = dog(p, "Breadog")
	eq(#G.ValueReasons(p, plain), 0, "a plain Common is ordinary")
	truthy(table.find(G.ValueReasons(p, dog(p, "MechaShiba")), "Rarity"), "Epic")
	truthy(table.find(G.ValueReasons(p, dog(p, "Breadog", { Variant = "Shiny" })), "Variant"), "Shiny")
	truthy(table.find(G.ValueReasons(p, dog(p, "Breadog", { Ascension = 1 })), "Ascension"))
	truthy(table.find(G.ValueReasons(p, dog(p, "Breadog", { Mastery = 25 })), "Mastery"))
	eq(#G.ValueReasons(p, dog(p, "Breadog", { Mastery = 24 })), 0, "mastery 24 ordinary")
	truthy(table.find(G.ValueReasons(p, dog(p, "Breadog", { Set = { LabRecipe = "GOLDEN_BREAKFAST" } })), "LabMade"))
	-- Equipment data may be missing or malformed: never an error.
	p.Equipment = nil
	eq(#G.Artifacts(p, plain.DogUid), 0)
	p.Equipment = { Artifacts = "broken" }
	eq(#G.Artifacts(p, plain.DogUid), 0)
	p.Equipment = { Version = 1, Artifacts = { a1 = { Uid = "a1", Id = "x", DogUid = plain.DogUid }, a2 = { Uid = "a2", Id = "y" }, a3 = 5 } }
	eq(#G.Artifacts(p, plain.DogUid), 1)
	truthy(table.find(G.ValueReasons(p, plain), "Artifacts"), "wearing an artifact")
end)

test("costs, stability and extraction yields keep the lab formulas", function()
	local p = profile()
	local bread = dog(p, "Breadog")
	local c = G.Cost("Mutation", bread)
	eq(c.Cash, 6500)
	eq(c.Bones, 5)
	c = G.Cost("Targeting", bread)
	eq(c.Cash, 11500)
	eq(c.DNA.CommonDNA, 2)
	eq(G.Cost("Extraction", bread).Cash, 2750)
	eq(G.Cost("Ascend", dog(p, "Breadog", { Ascension = 2 })).Cash, 75000)
	near(G.Stability("Mutation", bread, 0), 65, 1e-9)
	near(G.Stability("Targeting", dog(p, "Breadog", { Mastery = 50, Ascension = 1 }), 18), 48 + 6 + 3 + 18, 1e-9)
	local y = G.Extraction(bread)
	eq(y.CommonDNA, 2)
	eq(y.FOOD, 1)
	eq(y.NORMAL, 1)
	eq(y.RareDNA, nil)
	local king = G.Extraction(dog(p, "KingCorgi", { Variant = "Golden" }))
	eq(king.CommonDNA, 8)
	eq(king.RareDNA, 2)
	eq(king.MutationShards, 2)
	eq(king.ROYAL, 3)
end)

test("reroll odds: rows sum to 100, a catalyst lifts its target, a stabilizer damps Void/Glitched", function()
	local rows = Base.Variants
	local plain = G.Chances(rows, nil, 65, 0)
	local sum = 0
	for _, c in plain do
		sum += c.Percent
	end
	near(sum, 100, 1e-6)
	near(plain[1].Percent, 77, 1e-6, "Normal 7700/10000")
	local golden = G.Chances(rows, C.Affinities.golden_bone, 48, 0)
	local gold = 0
	for _, c in golden do
		if c.Name == "Golden" then
			gold = c.Percent
		end
	end
	near(gold, (500 + 1100 + 48 * 60) / (10000 + 1100 + 48 * 60) * 100, 1e-6, "golden target")
	local damp = G.Chances(rows, C.Affinities.golden_bone, 66, 18)
	for i, c in damp do
		if c.Name == "Void" then
			truthy(c.Percent < golden[i].Percent, "void damped")
		end
	end
end)

test("duplicates and recipe auto-fill pick the cheapest eligible dogs", function()
	local p = profile()
	local main = dog(p, "CoffeeDog", { Ascension = 1 })
	local cheap = dog(p, "CoffeeDog", { Ascension = 1 })
	local shiny = dog(p, "CoffeeDog", { Ascension = 1, Variant = "Shiny" })
	dog(p, "CoffeeDog", { Ascension = 0 }) -- too low
	local locked = dog(p, "CoffeeDog", { Ascension = 2 })
	locked.Locked = true
	local list, blocked = G.Duplicates(p, main)
	eq(#list, 2)
	eq(list[1].DogUid, cheap.DogUid, "cheapest first")
	eq(list[2].DogUid, shiny.DogUid)
	eq(blocked, 1)
	-- Golden Breakfast: Breadog + Coffee Dog + Golden Scarab + DNA.
	local row
	for _, r in LR.Catalog(p, NOW) do
		if r.RecipeId == "GOLDEN_BREAKFAST" then
			row = r
		end
	end
	truthy(row, "known recipe in the book")
	local fill = G.FillRecipe(p, row, main.DogUid)
	local kinds = {}
	for _, m in fill.Missing do
		kinds[m.Kind] = true
	end
	truthy(kinds.Dog and kinds.Item and kinds.DNA, "missing breadog, scarab and DNA")
	local bread = dog(p, "Breadog")
	item(p, "golden_scarab")
	p.Lab.DNA.FOOD = 4
	p.Lab.DNA.CommonDNA = 4
	fill = G.FillRecipe(p, row, main.DogUid)
	eq(#fill.Missing, 0)
	truthy(table.find(fill.Uids, bread.DogUid))
	truthy(table.find(fill.Uids, main.DogUid), "the picked dog is preferred")
	eq(#fill.Items, 1)
	-- Tag recipes: a dog with two tags must not block the second tag (backtracking).
	local tagRow = { RequiredGeneticTags = { "ANGELIC", "ARCANE" }, RequiredItems = {}, RequiredDNA = {} }
	local q = profile()
	local angel = dog(q, "AngelDoggo")
	local divine = dog(q, "DivineDog")
	fill = G.FillRecipe(q, tagRow, nil)
	eq(#fill.Missing, 0)
	eq(#fill.Uids, 2)
	truthy(table.find(fill.Uids, angel.DogUid) and table.find(fill.Uids, divine.DogUid))
end)

test("where to get an unowned species", function()
	local s = G.Sources("Breadog")
	truthy(table.find(s, "DogLine") and table.find(s, "LuckyBlock") and table.find(s, "DogOMatic"))
	truthy(table.find(G.Sources("TheDog"), "ServerArrival"))
	truthy(table.find(G.Sources("Aurion"), "DogOMatic"))
	eq(#G.Sources("NoSuchDog"), 0)
end)

------------------------------------------------------------------------------------------------
-- LabRules
------------------------------------------------------------------------------------------------
test("mutation: first try free, dog survives, variant from the server odds, then paid", function()
	local p = profile()
	local d = dog(p, "Breadog")
	local plan = LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW)
	eq(plan.Cash, 0, "starter reagent")
	eq(plan.HighValue, false, "a Normal reroll can only gain")
	eq(#plan.Consumed, 0)
	local cash = p.Cash
	-- roll 99.99 -> last row (Void); strange roll 99 -> none
	local result = LR.Apply(p, plan, NOW, fixed(0.9999, 0.99), newUid(), {}, newUid("tok"))
	eq(result.Dog.Variant, "Void")
	eq(p.Dogs[d.DogUid].Variant, "Void")
	eq(p.Cash, cash)
	truthy(p.Lab.TutorialComplete)
	errors(function()
		LR.Apply(p, LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW + 1), NOW + 1, fixed(0.5), newUid(), {}, newUid("tok"))
	end, "Chamber cooling down")
	local paid = LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW + 10)
	eq(paid.Cash, 6500)
	eq(paid.HighValue, true, "rerolling Void risks it")
	eq(paid.Reroll, true)
	eq(paid.Confirmation, "REROLL VOID")
	-- The history keeps a slim copy of the dog.
	eq(p.Lab.History[1].Dog.OwnerHistory, nil)
	eq(p.Lab.History[1].Dog.DogUid, d.DogUid)
end)

test("a personal DogMutation bonus changes the lab reroll odds", function()
	local p = profile()
	local d = dog(p, "Breadog")
	local base = LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW).Chances[1].Percent
	table.insert(B.Sources, {
		Name = "TestMutation",
		Global = function(_, _, add)
			add("DogMutation", 0.5)
		end,
	})
	local boosted = LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW).Chances[1].Percent
	table.remove(B.Sources)
	truthy(boosted < base - 5, string.format("Normal share falls with the bonus (%.2f -> %.2f)", base, boosted))
end)

test("targeting: one affinity catalyst, DNA charged, catalyst consumed", function()
	local p = profile()
	p.Lab.TutorialComplete = true
	local d = dog(p, "Breadog")
	local cat = item(p, "golden_scarab")
	errors(function()
		LR.Preview(p, { Procedure = "Targeting", Uids = { d.DogUid }, Items = { cat } }, NOW)
	end, "Not enough Common DNA")
	p.Lab.DNA.CommonDNA = 5
	local plan = LR.Preview(p, { Procedure = "Targeting", Uids = { d.DogUid }, Items = { cat } }, NOW)
	eq(plan.Target.Mutation, "Golden")
	local golden
	for _, c in plan.Chances do
		if c.Name == "Golden" then
			golden = c.Percent
		end
	end
	truthy(golden > 25, "targeted Golden " .. golden)
	LR.Apply(p, plan, NOW, fixed(0.01, 0.99), newUid(), {}, newUid("tok"))
	eq(p.Items[cat], nil, "catalyst used")
	eq(p.Lab.DNA.CommonDNA, 3)
	eq(LR.Public(plan).Target, "Golden")
end)

test("extraction: valuable dogs flagged, artifacts reported, DNA awarded, dog gone", function()
	local p = profile()
	local d = dog(p, "MechaShiba", { Mastery = 30 })
	p.Equipment = { Version = 1, Artifacts = { a1 = { Uid = "a1", Id = "lucky_paw", DogUid = d.DogUid, Slot = 1 } } }
	local plan = LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	eq(plan.HighValue, true)
	eq(plan.Artifacts, 1)
	truthy(table.find(plan.Valuable[d.DogUid], "Rarity") and table.find(plan.Valuable[d.DogUid], "Mastery") and table.find(plan.Valuable[d.DogUid], "Artifacts"))
	local result = LR.Apply(p, plan, NOW, fixed(0.5), newUid(), {}, newUid("tok"))
	eq(p.Dogs[d.DogUid], nil)
	eq(result.ReturnedArtifacts, 1)
	eq(p.Lab.DNA.CommonDNA, G.Extraction({ DogId = "MechaShiba", Mastery = 30, AscensionLevel = 0 }).CommonDNA)
	-- A plain Common is not valuable: a normal confirmation is enough.
	local q = profile()
	local plain = dog(q, "Breadog")
	eq(LR.Preview(q, { Procedure = "Extraction", Uids = { plain.DogUid } }, NOW).HighValue, false)
end)

test("blocked dogs are refused with the shared message", function()
	local p = profile()
	local d = dog(p, "Breadog")
	d.Favorite = true
	errors(function()
		LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	end, "Remove this dog from favorites before a procedure")
	d.Favorite = false
	p.DisplayDogs = { ["2"] = d.DogUid }
	errors(function()
		LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	end, "Remove this dog from its display first")
	p.DisplayDogs = {}
	d.Locked = true
	errors(function()
		LR.Preview(p, { Procedure = "Mutation", Uids = { d.DogUid } }, NOW)
	end, "Unlock this dog first")
end)

test("ascension: two duplicates consumed, main dog kept and ascended", function()
	local p = profile()
	local main = dog(p, "CoffeeDog")
	local a = dog(p, "CoffeeDog")
	local b = dog(p, "CoffeeDog")
	local plan = LR.Preview(p, { Procedure = "Fusion", RecipeId = "ASCEND", Uids = { main.DogUid, a.DogUid, b.DogUid }, PrimaryUid = main.DogUid }, NOW)
	eq(plan.Cash, 25000)
	eq(#plan.Consumed, 2)
	eq(plan.HighValue, false)
	LR.Apply(p, plan, NOW, fixed(0.5), newUid(), {}, newUid("tok"))
	eq(p.Dogs[main.DogUid].AscensionLevel, 1)
	eq(p.Dogs[a.DogUid], nil)
	eq(p.Dogs[b.DogUid], nil)
	local top = dog(p, "CoffeeDog", { Ascension = 3 })
	local c1 = dog(p, "CoffeeDog", { Ascension = 3 })
	local c2 = dog(p, "CoffeeDog", { Ascension = 3 })
	errors(function()
		LR.Preview(p, { Procedure = "Fusion", RecipeId = "ASCEND", Uids = { top.DogUid, c1.DogUid, c2.DogUid }, PrimaryUid = top.DogUid }, NOW)
	end, "Maximum Ascension")
end)

test("known recipe without typed DNA: auto DNA, works above the soft dog capacity", function()
	local p = profile()
	local bread = dog(p, "Breadog")
	local coffee = dog(p, "CoffeeDog")
	local scarab = item(p, "golden_scarab")
	p.Lab.DNA.FOOD = 6
	p.Lab.DNA.CommonDNA = 4
	-- Machine prizes may push a player above the soft capacity (20 here): crafting still works.
	local template = dog(p, "Pizzapup")
	while R.Count(p.Dogs) < R.Capacity(p) + 3 do
		local copy = R.Copy(template)
		copy.DogUid = newUid()
		p.Dogs[copy.DogUid] = copy
	end
	truthy(R.Count(p.Dogs) > R.Capacity(p))
	local args = { Procedure = "Fusion", RecipeId = "GOLDEN_BREAKFAST", Uids = { bread.DogUid, coffee.DogUid }, Items = { scarab } }
	local plan = LR.Preview(p, args, NOW)
	eq(plan.DNA.FOOD, 4)
	eq(plan.Hidden, false)
	local before = R.Count(p.Dogs)
	local softCheck = R.Free
	local result = LR.Apply(p, plan, NOW, fixed(0.01), newUid(), {}, newUid("tok"))
	truthy(result.Success)
	eq(result.Dog.DogId, "Breadog")
	eq(result.Dog.Variant, "Golden")
	eq(R.Count(p.Dogs), before - 1)
	eq(p.Lab.DNA.FOOD, 2)
	eq(p.Items[scarab], nil)
	eq(R.Free, softCheck, "the soft-capacity check is restored")
	eq(R.Free(p), false, "still above the soft capacity for other systems")
	-- The legacy exact-DNA path still matches; a wrong amount does not.
	local q = profile()
	local b2, c2, s2 = dog(q, "Breadog"), dog(q, "CoffeeDog"), item(q, "golden_scarab")
	q.Lab.DNA.FOOD = 9
	q.Lab.DNA.CommonDNA = 9
	truthy(LR.Preview(q, { Procedure = "Fusion", RecipeId = "GOLDEN_BREAKFAST", Uids = { b2.DogUid, c2.DogUid }, Items = { s2 }, DNA = { FOOD = 4, CommonDNA = 4 } }, NOW))
	errors(function()
		LR.Preview(q, { Procedure = "Fusion", RecipeId = "GOLDEN_BREAKFAST", Uids = { b2.DogUid, c2.DogUid }, Items = { s2 }, DNA = { FOOD = 3 } }, NOW)
	end, "No compatible recipe")
end)

test("discovery matches dogs and catalysts, hides the output, charges the recipe DNA", function()
	local p = profile()
	local coffee = dog(p, "CoffeeDog", { Mastery = 5 })
	local dj = dog(p, "DJDoggo", { Mastery = 5 })
	local coin = item(p, "glitched_coin")
	local args = { Procedure = "Creation", RecipeId = "DISCOVER", Uids = { coffee.DogUid, dj.DogUid }, Items = { coin } }
	errors(function()
		LR.Preview(p, args, NOW)
	end, "Not enough")
	p.Lab.DNA.FOOD = 4
	p.Lab.DNA.DIGITAL = 4
	p.Lab.DNA.RareDNA = 2
	local plan = LR.Preview(p, args, NOW)
	eq(plan.RecipeId, "DIGITAL_ROAST")
	eq(plan.Hidden, true)
	local public = LR.Public(plan)
	eq(public.OutputDogId, nil, "hidden output")
	eq(public.RecipeId, "CLASSIFIED")
	local result = LR.Apply(p, plan, NOW, fixed(0.01), newUid(), {}, newUid("tok"))
	truthy(result.Success and result.FirstDiscovery)
	truthy(p.Lab.Recipes.DIGITAL_ROAST)
	eq(p.Lab.DNA.FOOD, 0)
	-- Without the catalyst nothing matches.
	local q = profile()
	local c2, d2 = dog(q, "CoffeeDog", { Mastery = 5 }), dog(q, "DJDoggo", { Mastery = 5 })
	q.Lab.DNA.FOOD, q.Lab.DNA.DIGITAL, q.Lab.DNA.RareDNA = 9, 9, 9
	errors(function()
		LR.Preview(q, { Procedure = "Creation", RecipeId = "DISCOVER", Uids = { c2.DogUid, d2.DogUid } }, NOW)
	end, "No compatible recipe")
end)

test("a failed recipe keeps the dogs and refunds half the DNA", function()
	local p = profile()
	local bread, coffee, scarab = dog(p, "Breadog"), dog(p, "CoffeeDog"), item(p, "golden_scarab")
	p.Lab.DNA.FOOD, p.Lab.DNA.CommonDNA = 4, 4
	local plan = LR.Preview(p, { Procedure = "Fusion", RecipeId = "GOLDEN_BREAKFAST", Uids = { bread.DogUid, coffee.DogUid }, Items = { scarab } }, NOW)
	local result = LR.Apply(p, plan, NOW, fixed(0.999), newUid(), {}, newUid("tok"))
	eq(result.Success, false)
	truthy(p.Dogs[bread.DogUid] and p.Dogs[coffee.DogUid])
	eq(p.Lab.DNA.FOOD, 2)
	eq(p.Lab.DNA.StrangeDNA, 1)
	eq(result.ReturnedArtifacts, 0)
end)

test("catalogue: unique keys, dog counts, success chance, recipe tier gates", function()
	local p = profile()
	local rows = LR.Catalog(p, NOW)
	local keys = {}
	for _, r in rows do
		truthy(r.Key and not keys[r.Key], "unique key " .. tostring(r.Key))
		keys[r.Key] = true
		if r.RecipeId == "DISCOVER" then
			eq(r.RequiredDNA, nil, "hidden rows keep their secrets")
			truthy(r.DogCount >= 2)
		end
	end
	truthy(keys.ASCEND and keys.GOLDEN_BREAKFAST and keys["DISCOVER:1"] and keys["DISCOVER:2"])
	local low = profile({ Level = 6 })
	eq(#LR.Catalog(low, NOW), 0, "below lab tier 4 no recipe")
	errors(function()
		local d = dog(low, "Breadog")
		LR.Preview(low, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	end, "Reach the required lab level first")
	-- Every recipe asks for items that exist and outputs a real dog.
	for _, r in Recipes do
		truthy(Defs[r.OutputDogId], r.RecipeId)
		for itemId in pairs(r.RequiredItems or {}) do
			truthy(I.Definitions[itemId], itemId)
		end
	end
end)

test("the signature binds a preview to the exact dogs and odds", function()
	local p = profile()
	local d = dog(p, "Breadog")
	local a = LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	local b = LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW)
	eq(a.Signature, b.Signature)
	d.Mastery = 60
	eq(LR.Preview(p, { Procedure = "Extraction", Uids = { d.DogUid } }, NOW).Signature ~= a.Signature, true)
end)

------------------------------------------------------------------------------------------------
-- LabService (commit protocol with the acknowledgement)
------------------------------------------------------------------------------------------------
-- The old five-procedure lab (LabConfig.SimpleMode = false, the rollback) for the duration of fn.
local function legacy(fn)
	return function()
		local was = C.SimpleMode
		C.SimpleMode = false
		local ok, err = pcall(fn)
		C.SimpleMode = was
		if not ok then
			error(err, 0)
		end
	end
end

local function service(p)
	runtime.Engine.Get = function()
		return p
	end
	runtime.Engine.Authorize = function() end
	runtime.Engine.Guid = function()
		return newUid("guid")
	end
	runtime.Engine.Random = fixed(0.5, 0.99)
	runtime.Engine.TradeByUser = {}
	runtime.Tx.Run = function(_, keys, fn)
		local v = {}
		for _, k in keys do
			v[k] = k == "p:1" and p or {}
		end
		local ok, result = pcall(fn, v)
		return ok, ok and result or tostring(result)
	end
	return { UserId = 1, DisplayName = "Tester" }
end

test("legacy commit: valuable plans need the acknowledgement; replays are idempotent", legacy(function()
	local p = profile()
	local player = service(p)
	local d = dog(p, "MechaShiba")
	L.Time = NOW
	local ok, info = LS.Request(player, "LabInfo", {}, "r1")
	truthy(ok)
	truthy(#info.VariantRows == #Base.Variants and info.Tier == 5)
	local okP, preview = LS.Request(player, "LabPreview", { Procedure = "Extraction", Uids = { d.DogUid } }, "r2")
	truthy(okP, tostring(preview))
	eq(preview.HighValue, true)
	eq(preview.Signature, nil, "the signature stays on the server")
	errors(function()
		LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true, Extra = 1 }, "r3")
	end, "Unsupported confirmation parameter")
	local okC, refused = LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true }, "r4")
	eq(okC, false)
	truthy(string.find(refused, "Confirm these valuable dogs first", 1, true), refused)
	truthy(p.Dogs[d.DogUid], "nothing consumed")
	local okA, result = LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true, Acknowledge = preview.Token }, "r5")
	truthy(okA, tostring(result))
	eq(p.Dogs[d.DogUid], nil)
	local dna = p.Lab.DNA.CommonDNA
	local okR, replay = LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true, Acknowledge = true }, "r6")
	truthy(okR)
	eq(replay.Token, preview.Token)
	eq(p.Lab.DNA.CommonDNA, dna, "a replay never pays twice")
	-- The old typed phrase still works for one release.
	L.Time = NOW + 20
	local e = dog(p, "MechaShiba")
	local _, preview2 = LS.Request(player, "LabPreview", { Procedure = "Extraction", Uids = { e.DogUid } }, "r7")
	local okT = LS.Request(player, "LabCommit", { Token = preview2.Token, Confirm = true, Typed = "CONSUME 1 DOG" }, "r8")
	truthy(okT)
	-- Away from the terminal nothing works.
	access.Reach = false
	errors(function()
		LS.Request(player, "LabInfo", {}, "r9")
	end, "Enter Mutation Lab")
	access.Reach = true
	L.Time = NOW
end))

test("legacy commit: a dog changed after the preview needs a fresh review", legacy(function()
	local p = profile()
	local player = service(p)
	local d = dog(p, "Breadog")
	local _, preview = LS.Request(player, "LabPreview", { Procedure = "Extraction", Uids = { d.DogUid } }, "s1")
	d.Mastery = 40
	local ok, err = LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true, Acknowledge = true }, "s2")
	eq(ok, false)
	truthy(string.find(err, "Review a fresh preview", 1, true), err)
	truthy(p.Dogs[d.DogUid])
end))

test("legacy mode keeps every procedure and the recipe book", legacy(function()
	local p = profile()
	local player = service(p)
	local _, info = LS.Request(player, "LabInfo", {}, "lg1")
	eq(info.Simple, false)
	truthy(type(info.Recipes) == "table" and #info.Recipes > 0, "recipe book")
	local a, b, c = dog(p, "CoffeeDog"), dog(p, "CoffeeDog"), dog(p, "CoffeeDog")
	local ok, plan = LS.Request(player, "LabPreview", { Procedure = "Fusion", RecipeId = "ASCEND", Uids = { a.DogUid, b.DogUid, c.DogUid }, PrimaryUid = a.DogUid }, "lg2")
	truthy(ok, tostring(plan))
	eq(plan.RecipeId, "ASCEND")
	local cat = item(p, "golden_scarab")
	p.Lab.DNA.CommonDNA = 4
	local okT, target = LS.Request(player, "LabPreview", { Procedure = "Targeting", Uids = { dog(p, "Breadog").DogUid }, Items = { cat } }, "lg3")
	truthy(okT, tostring(target))
	eq(target.Target, "Golden")
end))

------------------------------------------------------------------------------------------------
-- The mutation machine (LabConfig.SimpleMode)
------------------------------------------------------------------------------------------------
test("simple mode is the default and only serves Mutation", function()
	eq(C.SimpleMode, true, "LabConfig.SimpleMode")
	local p = profile()
	local player = service(p)
	local d = dog(p, "Breadog")
	for _, args in {
		{ Procedure = "Extraction", Uids = { d.DogUid } },
		{ Procedure = "Targeting", Uids = { d.DogUid }, Items = { item(p, "golden_scarab") } },
		{ Procedure = "Fusion", RecipeId = "ASCEND", Uids = { d.DogUid, dog(p, "Breadog").DogUid, dog(p, "Breadog").DogUid }, PrimaryUid = d.DogUid },
		{ Procedure = "Creation", RecipeId = "DISCOVER", Uids = { d.DogUid, dog(p, "CoffeeDog").DogUid } },
		{ Uids = { d.DogUid } },
	} do
		errors(function()
			LS.Request(player, "LabPreview", args, "sm")
		end, "The Mutation Machine only rerolls mutations")
	end
	-- Extra items (catalysts, stabilizers, DNA) are gone from the machine.
	for _, extra in { { Items = { item(p, "golden_scarab") } }, { StabilizerUid = item(p, "quartz_crystal") }, { DNA = { CommonDNA = 1 } }, { RecipeId = "" } } do
		local args = { Procedure = "Mutation", Uids = { d.DogUid } }
		for k, v in extra do
			args[k] = v
		end
		errors(function()
			LS.Request(player, "LabPreview", args, "sm2")
		end, "The Mutation Machine takes only a dog")
	end
	truthy(p.Dogs[d.DogUid], "nothing consumed")
	-- A quote that is not a mutation (made before a switch) is refused at commit too.
	LS.Quotes[1] = { Token = string.rep("a", 32), Args = {}, Plan = { Procedure = "Extraction" }, Expires = NOW + 60 }
	errors(function()
		LS.Request(player, "LabCommit", { Token = string.rep("a", 32), Confirm = true }, "sm3")
	end, "The Mutation Machine only rerolls mutations")
	LS.Quotes[1] = nil
	-- Away from the console the machine says where to go.
	access.Reach = false
	errors(function()
		LS.Request(player, "LabInfo", {}, "sm4")
	end, "Walk up to the Mutation Machine console")
	access.Reach = true
end)

test("simple mode LabInfo: real odds with income bonus, costs, free first try, no recipe book", function()
	local p = profile()
	local player = service(p)
	local ok, info = LS.Request(player, "LabInfo", {}, "si1")
	truthy(ok)
	eq(info.Simple, true)
	eq(info.Recipes, nil, "no recipe book")
	eq(info.TutorialComplete, false, "first mutation is free")
	eq(info.Costs.Cash, 5000)
	eq(info.Costs.RankCash, 1500)
	eq(info.Costs.RankBones, 5)
	truthy(info.Machine and info.Machine.Reel > 0, "cinematic timings")
	local expected = { Normal = 77, Shiny = 15, Golden = 5, Corrupted = 2, Glitched = 0.8, Void = 0.2 }
	local bonus = { Normal = 0, Shiny = 0.12, Golden = 0.30, Corrupted = 0.50, Glitched = 0.75, Void = 1.10 }
	local sum = 0
	eq(#info.Odds, 6)
	for i, row in info.Odds do
		eq(row.Name, Base.Variants[i].Name)
		near(row.Percent, expected[row.Name], 1e-9, row.Name)
		near(row.Bonus, bonus[row.Name], 1e-9, row.Name .. " bonus")
		sum += row.Percent
	end
	near(sum, 100, 1e-9)
end)

test("simple mode mutation: free first try, then the old costs per rank and the old odds", function()
	local p = profile()
	local player = service(p)
	local d = dog(p, "Breadog")
	local cash, bones = p.Cash, p.Bones
	local _, plan = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { d.DogUid } }, "mu1")
	eq(plan.Cash, 0)
	eq(plan.Bones, 0)
	eq(plan.StarterReagent, true)
	eq(plan.HighValue, false)
	for i, c in plan.Chances do
		near(c.Percent, Base.Variants[i].Weight / 100, 1e-9, c.Name)
	end
	-- roll 0.95 * 100 = 95 -> Golden (77 + 15 <= 95 < 97); strange roll 0.99 -> none
	runtime.Engine.Random = fixed(0.95, 0.99)
	local ok, result = LS.Request(player, "LabCommit", { Token = plan.Token, Confirm = true }, "mu2")
	truthy(ok, tostring(result))
	eq(result.Dog.Variant, "Golden")
	eq(result.BeforeDog.Variant, "Normal")
	eq(p.Dogs[d.DogUid].Variant, "Golden")
	eq(p.Cash, cash)
	eq(p.Bones, bones)
	truthy(p.Lab.TutorialComplete)
	-- The chamber cools down for 7 s.
	local _, again = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { d.DogUid } }, "mu3")
	local okC, cooling = LS.Request(player, "LabCommit", { Token = again.Token, Confirm = true, Acknowledge = again.Token }, "mu4")
	eq(okC, false)
	truthy(string.find(cooling, "Chamber cooling down", 1, true), cooling)
	-- Paid tries: 5000 + 1500 x rank coins and 5 x rank bones, for every rank.
	L.Time = NOW + 60
	local ranks = {}
	for id, def in Defs do
		if type(def) == "table" and def.Rank and not ranks[def.Rank] and def.Available and def.MutationRules and def.MutationRules.Enabled then
			ranks[def.Rank] = id
		end
	end
	local checked = 0
	for rank, id in ranks do
		local x = dog(p, id)
		local okR, paid = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { x.DogUid } }, "mu5")
		truthy(okR, id .. ": " .. tostring(paid))
		eq(paid.Cash, 5000 + 1500 * rank, id)
		eq(paid.Bones, 5 * rank, id)
		checked += 1
	end
	truthy(checked >= 5, "ranks checked: " .. checked)
	local x = dog(p, "Breadog")
	local _, paid = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { x.DogUid } }, "mu6")
	eq(paid.Cash, 6500)
	eq(paid.Bones, 5)
	local before = p.Cash
	runtime.Engine.Random = fixed(0.5, 0.99)
	local okP, normal = LS.Request(player, "LabCommit", { Token = paid.Token, Confirm = true }, "mu7")
	truthy(okP, tostring(normal))
	eq(normal.Dog.Variant, "Normal", "roll 50 stays Normal")
	eq(p.Cash, before - 6500)
	L.Time = NOW
end)

test("simple mode: rerolling a mutated dog needs the held acknowledgement; replays never pay twice", function()
	local p = profile()
	p.Lab.TutorialComplete = true
	local player = service(p)
	local d = dog(p, "Breadog", { Variant = "Golden" })
	local _, plan = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { d.DogUid } }, "hv1")
	eq(plan.HighValue, true)
	eq(plan.Reroll, true)
	eq(plan.FromVariant, "Golden")
	local ok, refused = LS.Request(player, "LabCommit", { Token = plan.Token, Confirm = true }, "hv2")
	eq(ok, false)
	truthy(string.find(refused, "Confirm these valuable dogs first", 1, true), refused)
	eq(p.Dogs[d.DogUid].Variant, "Golden", "untouched")
	local cash = p.Cash
	runtime.Engine.Random = fixed(0.5, 0.99)
	local okA, result = LS.Request(player, "LabCommit", { Token = plan.Token, Confirm = true, Acknowledge = plan.Token }, "hv3")
	truthy(okA, tostring(result))
	eq(result.Dog.Variant, "Normal", "a reroll can lose Golden")
	eq(p.Cash, cash - 6500)
	local okR, replay = LS.Request(player, "LabCommit", { Token = plan.Token, Confirm = true, Acknowledge = true }, "hv4")
	truthy(okR)
	eq(replay.Token, plan.Token)
	eq(p.Cash, cash - 6500, "the replay is answered from the history")
	-- Trades block the machine.
	runtime.Engine.TradeByUser[1] = true
	errors(function()
		LS.Request(player, "LabInfo", {}, "hv5")
	end, "Finish or cancel your trade")
	runtime.Engine.TradeByUser[1] = nil
end)

test("an old profile with DNA, history, recipes and ascended lab dogs stays valid and can mutate", function()
	local p = profile()
	local asc = dog(p, "Breadog", { Ascension = 2, Mastery = 30 })
	asc.LabRecipe = "GOLDEN_BREAKFAST"
	asc.Origin = "LAB_FUSION"
	local history = {}
	for i = 1, C.MaxHistory do
		table.insert(history, { Token = string.format("%032d", i), At = NOW - 1000 - i, Procedure = i % 2 == 0 and "Extraction" or "Fusion", RecipeId = i % 2 == 1 and "ASCEND" or nil, Consumed = {}, DNA = { CommonDNA = 2 }, Success = true })
	end
	p.Lab = {
		Version = 1,
		DNA = { CommonDNA = 12, FOOD = 3, StrangeDNA = 2, MutationShards = 4 },
		DiscoveredDNA = { CommonDNA = true },
		Recipes = { GOLDEN_BREAKFAST = NOW - 5000 },
		History = history,
		Experiments = 55,
		TutorialComplete = true,
		PaidDNA = true,
		LastAt = NOW - 3600,
	}
	R.Normalize(p, 1, NOW)
	R.Validate(p)
	eq(p.Lab.DNA.CommonDNA, 12)
	truthy(p.Lab.DiscoveredDNA.FOOD and p.Lab.DiscoveredDNA.StrangeDNA, "discovered from the bank")
	truthy(p.Lab.FirstDiscoveries and p.Lab.Tier >= 1, "old profile gets the new fields")
	local player = service(p)
	local _, plan = LS.Request(player, "LabPreview", { Procedure = "Mutation", Uids = { asc.DogUid } }, "old1")
	eq(plan.Cash, 6500)
	eq(plan.HighValue, false, "an ascended Normal dog can only gain")
	runtime.Engine.Random = fixed(0.80, 0.99)
	local ok, result = LS.Request(player, "LabCommit", { Token = plan.Token, Confirm = true }, "old2")
	truthy(ok, tostring(result))
	eq(result.Dog.Variant, "Shiny")
	local d = p.Dogs[asc.DogUid]
	eq(d.AscensionLevel, 2, "ascension (and its income) kept")
	eq(d.LabRecipe, "GOLDEN_BREAKFAST")
	eq(d.Origin, "LAB_FUSION")
	eq(#p.Lab.History, C.MaxHistory, "history stays capped")
	eq(p.Lab.History[1].Token, plan.Token)
	eq(p.Lab.DNA.CommonDNA, 12, "DNA bank untouched")
	eq(p.Lab.Recipes.GOLDEN_BREAKFAST, NOW - 5000)
	R.Normalize(p, 1, NOW)
	R.Validate(p)
	-- A fresh profile (new player) has a valid lab too.
	local q = R.Profile(2, NOW)
	R.Normalize(q, 2, NOW)
	R.Validate(q)
	truthy(not q.Lab.TutorialComplete, "new player: first mutation free")
end)

------------------------------------------------------------------------------------------------
-- The machine: layout maths and the builder
------------------------------------------------------------------------------------------------
-- Lune's CFrame.lookAt is wrong (tools/qa/scene.luau): the builder and the layout get a fixed copy.
do
	local roblox = require("@lune/roblox")
	local Raw = roblox.CFrame
	local function lookAt(at, target, up)
		local look = target - at
		if look.Magnitude < 1e-9 then
			return Raw.new(at)
		end
		look = look.Unit
		up = up or roblox.Vector3.new(0, 1, 0)
		local right = look:Cross(up)
		if right.Magnitude < 1e-6 then
			right = look:Cross(roblox.Vector3.new(0, 0, -1))
		end
		right = right.Unit
		return Raw.fromMatrix(at, right, right:Cross(look))
	end
	L.CFrame = setmetatable({ lookAt = lookAt }, { __index = Raw })
end
local Layout = L.Require("ReplicatedStorage.MutationMachineLayout")
local Build = L.Require("ServerScriptService.MutationMachineBuild")
local Instance = require("@lune/roblox").Instance
local V3 = require("@lune/roblox").Vector3
local CF = L.CFrame

local function aabb(p)
	local lo, hi
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local v = p.CFrame:PointToWorldSpace(V3.new(p.Size.X * x / 2, p.Size.Y * y / 2, p.Size.Z * z / 2))
				lo = lo and V3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
				hi = hi and V3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
			end
		end
	end
	return lo, hi
end

test("arm inverse kinematics reaches its targets with fixed link lengths", function()
	for _, target in { Layout.Arm.Rest, Layout.Arm.Place } do
		local pose = Layout.ArmPose(target)
		local shoulder, elbow, wrist = pose.Upper.Position, pose.Fore.Position, pose.Claw.Position
		near((elbow - shoulder).Magnitude, Layout.Arm.Upper, 1e-4, "upper link")
		near((wrist - elbow).Magnitude, Layout.Arm.Fore, 1e-4, "forearm")
		near((wrist - target).Magnitude, 0, 1e-3, "reaches the target")
		near(pose.Upper.LookVector:Dot((elbow - shoulder).Unit), 1, 1e-4, "upper frame looks along the link")
	end
	-- Out of reach: the arm stretches toward the target instead of breaking.
	local far = Layout.ArmPose(Layout.Arm.Base + V3.new(-40, 5, 0))
	truthy(far.Claw.Position.X < Layout.Arm.Base.X, "stretches toward it")
end)

test("colour reel slows down and lands on the result (near miss before Normal)", function()
	local names = {}
	for _, v in Base.Variants do
		table.insert(names, v.Name)
	end
	for _, result in { "Normal", "Shiny", "Golden", "Void" } do
		local steps = Layout.ReelSteps(result, C.Machine.Reel, names)
		truthy(#steps >= 8, "enough steps")
		eq(steps[#steps].Name, result)
		eq(steps[#steps - 1].Name, result == "Normal" and "Shiny" or "Normal")
		near(steps[#steps].At, C.Machine.Reel, 1e-6)
		for i = 3, #steps do
			truthy(steps[i].At - steps[i - 1].At > steps[i - 1].At - steps[i - 2].At, "decelerates")
		end
	end
	local total = 0
	for _, k in { "Activate", "Load", "Rise", "Reel", "Hold", "Reveal" } do
		total += C.Machine[k]
	end
	truthy(total >= 6 and total <= 9, "cinematic 6-9 s: " .. total)
	truthy(C.Machine.Reduced <= 3, "short version")
end)

test("the machine model: part and light budgets, animated names, clear of the hall structure", function()
	local m = Build.Build(nil)
	local parts, lights = 0, 0
	local names = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			names[d.Name] = true
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			lights += 1
		end
		if d:IsA("Model") or d:IsA("Folder") then
			names[d.Name] = true
		end
	end
	truthy(parts <= Build.MaxParts and parts <= 450, "parts " .. parts)
	truthy(parts >= 150, "a big machine: " .. parts)
	truthy(lights <= 4, "lights " .. lights)
	for _, name in { "Lift", "Carriage", "Mast", "Platform", "IntakeDoor", "Rotor1", "Rotor2", "RotorHub", "ChamberLiquid", "LiquidSurface", "CoreBeam",
		"EnergyRail1", "EnergyRail2", "EnergyRail3", "EnergyRail4", "Membrane", "InjectorTip", "ChamberLightPart", "Core", "UpperLiquid", "Beacon",
		"WarningLight1", "PlacerArm", "Turret", "Upper", "Fore", "Claw", "ButtonGuard", "ButtonDome", "LeverL", "LeverR", "GaugeNeedle1", "GaugeNeedle4",
		"ScreenL", "ScreenR", "MainSign", "DeskPlate", "ConsoleLamp" } do
		truthy(names[name], "named part " .. name)
	end
	for _, r in Layout.Tube.Rotors do
		local rotor = m:FindFirstChild(r.Name)
		truthy(rotor.PrimaryPart and rotor.PrimaryPart.Name == "RotorHub" and rotor.PrimaryPart.Anchored, r.Name .. " hub")
		for _, d in rotor:GetDescendants() do
			if d:IsA("BasePart") and d ~= rotor.PrimaryPart then
				truthy(not d.Anchored and d:FindFirstChildOfClass("WeldConstraint"), "welded " .. d.Name)
			end
		end
	end
	for _, screen in { "ScreenL", "ScreenR", "MainSign" } do
		local gui = m:FindFirstChild(screen, true):FindFirstChild("Display")
		truthy(gui and #gui:GetChildren() >= 2, screen .. " texts")
	end
	-- Hall structure the tube passes between (world AABBs): ceiling cross beams, the cross roof, air handlers,
	-- the archive capsules behind the pedestal.
	local blocked = {
		{ V3.new(121.35, 34.2, 447.5), V3.new(122.65, 35.6, 506.5) },
		{ V3.new(143.35, 34.2, 447.5), V3.new(144.65, 35.6, 506.5) },
		{ V3.new(142.0, 37.0, 460.0), V3.new(154.0, 38.4, 494.0) },
		{ V3.new(139.0, 38.3, 449.0), V3.new(149.0, 44.9, 459.0) },
		{ V3.new(139.0, 38.3, 495.0), V3.new(149.0, 44.9, 505.0) },
		{ V3.new(146.8, 2.0, 459.8), V3.new(153.2, 16.3, 466.2) },
		{ V3.new(146.8, 2.0, 487.8), V3.new(153.2, 16.3, 494.2) },
	}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local lo, hi = aabb(d)
			for i, box in blocked do
				local clear = hi.X <= box[1].X + 0.05 or lo.X >= box[2].X - 0.05 or hi.Y <= box[1].Y + 0.05 or lo.Y >= box[2].Y - 0.05 or hi.Z <= box[1].Z + 0.05 or lo.Z >= box[2].Z - 0.05
				truthy(clear, d.Name .. " hits hall structure " .. i)
			end
			if hi.Y < 36 then
				truthy(lo.X >= 84.5 and hi.X <= 153.5 and lo.Z >= 447.5 and hi.Z <= 506.5, d.Name .. " inside the hall")
			end
		end
	end
	-- The tube rises through the roof as a landmark.
	local beacon = m:FindFirstChild("Beacon", true)
	truthy(beacon.CFrame.Position.Y > 95, "beacon high above the roof")
end)

test("the ACTIVATE anchor is inside the lab zone and within reach of the operator", function()
	local anchor = Layout.World(Layout.Anchor)
	-- InteriorZone: centre (119, 17, 477), X 85.5..152.5, Y 1..33, Z 430.5..523.5
	truthy(anchor.X > 85.5 and anchor.X < 152.5 and anchor.Y > 1 and anchor.Y < 33 and anchor.Z > 430.5 and anchor.Z < 523.5, "inside the zone")
	local operator = Layout.World(V3.new(-29.2, 3.35, 0)) -- HumanoidRootPart on the dais
	truthy((operator - anchor).Magnitude < C.Distance - 1.5, "reach " .. (operator - anchor).Magnitude)
	local side = Layout.World(V3.new(-28.5, 3.0, 5.5))
	truthy((side - anchor).Magnitude < C.Distance, "reach from the side of the desk")
end)

test("install hides the old chamber and cuts the roof reversibly, uninstall restores everything", function()
	local function part(name, parent, cf, size, props)
		local p = Instance.new("Part")
		p.Name = name
		p.CFrame = cf
		p.Size = size
		for k, v in props or {} do
			p[k] = v
		end
		p.Parent = parent
		return p
	end
	local lab = Instance.new("Model")
	lab.Name = "05_MutationLab"
	local chamber = Instance.new("Model")
	chamber.Name = "CentralChamber"
	chamber.Parent = lab
	local glass = part("ClearContainment", chamber, CF.new(134, 14.2, 477), V3.new(18.5, 14, 14), { Transparency = 0.94, CanCollide = true })
	local light = Instance.new("PointLight")
	light.Parent = glass
	local gui = Instance.new("SurfaceGui")
	gui.Parent = glass
	local roof = Instance.new("Model")
	roof.Name = "TechnicalRoof"
	roof.Parent = lab
	local sky = part("CentralSkylight", roof, CF.new(119, 37.9, 477), V3.new(46, 0.2, 32), { Transparency = 0.94 })
	local beamAxis = part("LanternBeam", roof, CF.new(119, 38.2, 477), V3.new(47, 0.7, 0.6))
	local beamEdge = part("LanternBeam", roof, CF.new(119, 38.2, 461), V3.new(47, 0.7, 0.6))
	local bar = part("LanternCrossbar", roof, CF.new(127, 38.2, 477), V3.new(0.5, 0.7, 33))
	local barOther = part("LanternCrossbar", roof, CF.new(111, 38.2, 477), V3.new(0.5, 0.7, 33))
	local anchorCF = CF.new(125.3, 5.8, 502)
	local anchor = part("InteractionAnchor", lab, anchorCF, V3.new(0.2, 0.2, 0.2), { Transparency = 1 })
	local machine = Build.Install(lab)
	eq(machine.Parent, lab)
	eq(glass.Transparency, 1)
	eq(glass.CanCollide, false)
	near(glass:GetAttribute("MutationMachine_Transparency"), 0.94, 1e-6)
	eq(light.Enabled, false)
	eq(gui.Enabled, false)
	eq(sky.Transparency, 1)
	eq(beamAxis.Transparency, 1)
	eq(beamEdge.Transparency, 0, "other lantern beams stay")
	eq(bar.Transparency, 1)
	eq(barOther.Transparency, 0, "other crossbars stay")
	local cut = machine:FindFirstChild("RoofCut")
	truthy(cut and cut:FindFirstChild("SkylightWest") and cut:FindFirstChild("SkylightNorth") and cut:FindFirstChild("SkylightSouth") and cut:FindFirstChild("LanternBeamWest"), "trimmed copies")
	near(cut.SkylightWest.Transparency, 0.94, 1e-6, "copies keep the look")
	eq(cut.SkylightWest:GetAttribute("MutationMachine_Edited"), nil, "copies carry no restore attributes")
	near((anchor.CFrame.Position - Layout.World(Layout.Anchor)).Magnitude, 0, 1e-4, "anchor at the console")
	-- Installing twice keeps a single machine and the true originals.
	Build.Install(lab)
	local machines = 0
	for _, c in lab:GetChildren() do
		if c.Name == Layout.Name then
			machines += 1
		end
	end
	eq(machines, 1)
	near(glass:GetAttribute("MutationMachine_Transparency"), 0.94, 1e-6)
	local restored = Build.Uninstall(lab)
	truthy(restored >= 6, "restored " .. restored)
	eq(lab:FindFirstChild(Layout.Name), nil)
	near(glass.Transparency, 0.94, 1e-6)
	eq(glass.CanCollide, true)
	eq(light.Enabled, true)
	eq(gui.Enabled, true)
	near(sky.Transparency, 0.94, 1e-6)
	eq(beamAxis.Transparency, 0)
	eq(bar.Transparency, 0)
	near((anchor.CFrame.Position - anchorCF.Position).Magnitude, 0, 1e-4, "anchor back")
	for _, o in { glass, light, sky, beamAxis, bar, anchor } do
		for k in o:GetAttributes() do
			truthy(not string.find(k, "MutationMachine_", 1, true), "leftover attribute " .. k)
		end
	end
end)

------------------------------------------------------------------------------------------------
-- Localization and audio of the window
------------------------------------------------------------------------------------------------
test("every string the lab window shows has a Russian entry", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/LabScreen.luau")
	local missing = {}
	local function has(en)
		return Dict.UI[en] ~= nil or Dict.Exact[en] ~= nil
	end
	local seen = 0
	for en in string.gmatch(source, "%f[%w_]T%('([^']*)'%)") do
		seen += 1
		en = en:gsub("\\n", "\n")
		if not has(en) then
			table.insert(missing, "T: " .. en)
		end
	end
	truthy(seen > 80, "T() literals found: " .. seen)
	for en in string.gmatch(source, "%f[%w_]F%('([^']*)'") do
		seen += 1
		local ru = Dict.Templates[en]
		if not ru then
			table.insert(missing, "F: " .. en)
		else
			local function specs(s)
				local out = {}
				for spec in string.gmatch((s:gsub("%%%%", "")), "%%[%d%.]*[dsf]") do
					table.insert(out, spec)
				end
				return table.concat(out, ",")
			end
			if specs(en) ~= specs(ru) then
				table.insert(missing, "format mismatch: " .. en)
			end
		end
	end
	-- Dynamic keys: action titles / descriptions / buttons, statuses, fixes, value reasons, DNA, variants, rarities,
	-- catalysts, recipe names and hints.
	for key in string.gmatch(source, "Title='([^']*)'") do
		if not has(key) then table.insert(missing, "Title: " .. key) end
	end
	for key in string.gmatch(source, "Desc='([^']*)'") do
		if not has(key) then table.insert(missing, "Desc: " .. key) end
	end
	for key in string.gmatch(source, "Confirm='([^']*)'") do
		if not has(key) then table.insert(missing, "Confirm: " .. key) end
	end
	for _, list in { { "DOG", "ACTION", "CONFIRM", "PICK A DOG", "CHOOSE AN ACTION" }, { "ON THE WAY", "LOCKED", "IN KENNEL", "WORKING", "FAVORITE", "ON DISPLAY", "UNAVAILABLE", "GONE" }, { "UNLOCK", "UNFAVORITE", "REMOVE FROM KENNEL", "RETURN TO STORAGE" }, { "Epic or rarer", "mutated variant", "ascended", "high mastery", "collectible edition", "lab-made", "wears artifacts" } } do
		for _, key in list do
			if not has(key) then table.insert(missing, "word: " .. key) end
		end
	end
	for _, v in Base.Variants do
		if not has(v.Name) then table.insert(missing, "variant: " .. v.Name) end
	end
	for _, r in { "COMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC", "SECRET" } do
		if not has(r) then table.insert(missing, "rarity: " .. r) end
	end
	for k, en in pairs(C.DNA) do
		if not has(en) then table.insert(missing, "dna: " .. k) end
	end
	for id in pairs(C.Affinities) do
		if not has(I.Definitions[id].DisplayName) then table.insert(missing, "catalyst: " .. id) end
	end
	for id in pairs(C.Stabilizers) do
		if not has(I.Definitions[id].DisplayName) then table.insert(missing, "crystal: " .. id) end
	end
	for _, r in Recipes do
		if not has(r.Name) then table.insert(missing, "recipe: " .. r.Name) end
		if not has(r.Hint) then table.insert(missing, "hint: " .. r.RecipeId) end
	end
	for code, message in pairs(G.Messages) do
		if not has(message) then table.insert(missing, "message: " .. code) end
	end
	for _, f in { "UNLOCK", "UNFAVORITE", "REMOVE FROM KENNEL", "RETURN TO STORAGE" } do
		truthy(has(f), f)
	end
	if #missing > 0 then
		error(#missing .. " missing:\n  " .. table.concat(missing, "\n  "))
	end
end)

test("every string of the mutation machine window, cinematic and screens has Russian", function()
	local missing = {}
	local function has(en)
		return Dict.UI[en] ~= nil or Dict.Exact[en] ~= nil
	end
	local function specs(s)
		local out = {}
		for spec in string.gmatch((s:gsub("%%%%", "")), "%%[%d%.]*[dsf]") do
			table.insert(out, spec)
		end
		return table.concat(out, ",")
	end
	local seen = 0
	for _, path in { "src/StarterGui/ScreenGui/Modules/MutationLabScreen.luau", "src/StarterGui/ScreenGui/Modules/LabPresentation.luau" } do
		local source = fs.readFile(path)
		for en in string.gmatch(source, "%f[%w_]T%('([^']*)'%)") do
			seen += 1
			if not has(en) then
				table.insert(missing, path .. " T: " .. en)
			end
		end
		for en in string.gmatch(source, "%f[%w_]F%('([^']*)'") do
			seen += 1
			local ru = Dict.Templates[en]
			if not ru then
				table.insert(missing, path .. " F: " .. en)
			elseif specs(en) ~= specs(ru) then
				table.insert(missing, "format mismatch: " .. en)
			end
		end
	end
	truthy(seen > 40, "literals found: " .. seen)
	-- Status words, fixes and server replies the window shows.
	for _, key in { "LOCKED", "IN KENNEL", "WORKING", "FAVORITE", "ON THE WAY", "ON DISPLAY", "UNAVAILABLE", "UNLOCK", "UNFAVORITE", "REMOVE FROM KENNEL", "RETURN TO STORAGE", "Not enough Coins or Bones", "Chamber cooling down" } do
		if not has(key) then
			table.insert(missing, "word: " .. key)
		end
	end
	for _, v in Base.Variants do
		if not has(v.Name) then
			table.insert(missing, "variant: " .. v.Name)
		end
	end
	-- Texts the server writes on the machine's screens (self-localized by the cinematic module).
	local build = fs.readFile("src/ServerScriptService/MutationMachineBuild.luau")
	local screens = 0
	for en in string.gmatch(build, 'label%([%w_]+, "[%w_]+", "([^"]*)"') do
		screens += 1
		if not (Dict.Machine[en] or Dict.UI[en]) then
			table.insert(missing, "screen: " .. en)
		end
	end
	truthy(screens >= 6, "screen texts found: " .. screens)
	-- The prompt words.
	local prompt = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau")
	truthy(string.find(prompt, "АКТИВАЦИЯ", 1, true) and string.find(prompt, "МУТАЦИОННАЯ МАШИНА", 1, true), "prompt in Russian")
	if #missing > 0 then
		error(#missing .. " missing:\n  " .. table.concat(missing, "\n  "))
	end
end)

test("lab dictionary never overrides the base dictionary with a different text", function()
	local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	local base = {}
	for en, ru in string.gmatch(source, '%[%"([^"]+)%"%]%s*=%s*"([^"]*)"') do
		base[en] = ru
	end
	for en, ru in pairs(Dict.Exact) do
		truthy(base[en] == nil or base[en] == ru, "Localization.Lab Exact overrides a base entry: " .. en)
	end
	-- Server replies of the lab rules are covered.
	local rules = fs.readFile("src/ServerScriptService/Economy/LabRules.luau") .. fs.readFile("src/ServerScriptService/Economy/LabService.luau")
	local missing = {}
	local found = 0
	for message in string.gmatch(rules, "[Cc]heck%([^\n]-,'([^']+)'%)") do
		found += 1
		if not Dict.Exact[message] and not string.find(message, "%.%.") then
			table.insert(missing, message)
		end
	end
	truthy(found > 30, "server checks found: " .. found)
	if #missing > 0 then
		error("server messages without Russian:\n  " .. table.concat(missing, "\n  "))
	end
end)

-- A commit can be refused by the transaction layer ("Account is busy; retry shortly", "Saving your progress;
-- retry shortly"): those replies have their Russian in other dictionaries, so the lab's toasts of server
-- replies must stay translatable (no NoTranslate) instead of showing English to Russian players.
test("server replies in lab toasts stay translatable by DOGROTS_AutoTranslateUI", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/LabScreen.luau") .. fs.readFile("src/StarterGui/ScreenGui/Modules/MutationLabScreen.luau")
	local calls, bad = 0, {}
	for call in string.gmatch(source, "toast%(said%b()[^)]*%)") do
		calls += 1
		if not string.find(call, ",true%)$") then
			table.insert(bad, call)
		end
	end
	truthy(calls >= 4, "server-reply toasts found: " .. calls)
	truthy(#bad == 0, "toast without the server flag: " .. table.concat(bad, " | "))
	truthy(select(2, string.gsub(source, "NoTranslate=server~=true", "")) >= 2, "toast() keeps NoTranslate for the windows' own texts only")
	local known = {}
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local dict = L.Require("ReplicatedStorage.Localization." .. string.gsub(name, "%.luau$", ""))
		for en in pairs(type(dict) == "table" and dict.Exact or {}) do
			known[en] = true
		end
	end
	for _, reply in { "Account is busy; retry shortly", "Saving your progress; retry shortly", "Profile save is busy; retry shortly" } do
		truthy(known[reply], "shared reply has a Russian entry: " .. reply)
	end
end)

test("every lab sound cue the presentation and the window play exists", function()
	for _, cue in { "Console", "Lock", "Scan", "Charge", "Pulse", "Reveal", "Rare", "Select", "Step", "Confirm", "Deny", "Extract", "Activate", "Servo", "Fill", "Tick", "Arc" } do
		truthy(Audio.Has(cue), cue)
	end
	local sources = fs.readFile("src/StarterGui/ScreenGui/Modules/LabScreen.luau")
		.. fs.readFile("src/StarterGui/ScreenGui/Modules/LabPresentation.luau")
		.. fs.readFile("src/StarterGui/ScreenGui/Modules/MutationLabScreen.luau")
	local n = 0
	for cue in string.gmatch(sources, "[Cc]ue%('(%w+)'") do
		n += 1
		truthy(Audio.Has(cue), "cue " .. cue)
	end
	truthy(n >= 15, "cues found: " .. n)
end)

for _, s in installedSources do
	table.insert(B.Sources, s)
end
print(string.format("lab: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lab tests failed")
end
