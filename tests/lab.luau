--!nocheck
-- Genetics lab: shared rules (ReplicatedStorage.LabGenetics), server rules (Economy.LabRules) and the commit
-- protocol (Economy.LabService) on the real modules from src/ (tests/lib/economy_env.luau), plus the
-- localization coverage of the lab window. lune run tests/lab.luau
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

test("commit: valuable plans need the acknowledgement; replays are idempotent", function()
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
end)

test("commit: a dog changed after the preview needs a fresh review", function()
	local p = profile()
	local player = service(p)
	local d = dog(p, "Breadog")
	local _, preview = LS.Request(player, "LabPreview", { Procedure = "Extraction", Uids = { d.DogUid } }, "s1")
	d.Mastery = 40
	local ok, err = LS.Request(player, "LabCommit", { Token = preview.Token, Confirm = true, Acknowledge = true }, "s2")
	eq(ok, false)
	truthy(string.find(err, "Review a fresh preview", 1, true), err)
	truthy(p.Dogs[d.DogUid])
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

test("every lab sound cue the presentation and the window play exists", function()
	for _, cue in { "Console", "Lock", "Scan", "Charge", "Pulse", "Reveal", "Rare", "Select", "Step", "Confirm", "Deny", "Extract" } do
		truthy(Audio.Has(cue), cue)
	end
	local sources = fs.readFile("src/StarterGui/ScreenGui/Modules/LabScreen.luau") .. fs.readFile("src/StarterGui/ScreenGui/Modules/LabPresentation.luau")
	for cue in string.gmatch(sources, "[Cc]ue%('(%w+)'") do
		truthy(Audio.Has(cue), "cue " .. cue)
	end
end)

for _, s in installedSources do
	table.insert(B.Sources, s)
end
print(string.format("lab: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lab tests failed")
end
