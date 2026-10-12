--!nocheck
-- EQUIPMENT (dog artifacts, player accessories, cases): lune run tests/equipment.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): EquipmentDefinitions, the
-- Features.Equipment feature through Rules.Action / Normalize / Validate, the bonus sources
-- through Bonuses, Rules.Cooldown, IncomeModel and OfflineEarnings.
local L = require("./lib/economy_env")
local E = L.Require("ReplicatedStorage.DogEconomy.EquipmentDefinitions")
local B = L.Require("ReplicatedStorage.DogEconomy.Bonuses")
local R = L.Require("ServerScriptService.Economy.Rules")
local O = L.Require("ServerScriptService.Economy.OfflineEarnings")
local F = L.Require("ServerScriptService.Economy.Features.Equipment")
local Pricing = L.Require("ReplicatedStorage.DogEconomy.BoostPricing")
local ArtifactSource = L.Require("ReplicatedStorage.DogEconomy.BonusSources.Artifacts")
local AccessorySource = L.Require("ReplicatedStorage.DogEconomy.BonusSources.Accessories")
local Theme = L.Require("StarterGui.ScreenGui.Modules.Kit.Theme")
local Locale = L.Require("ReplicatedStorage.Localization.Equipment")

F.RateLimit = math.huge

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
local function constant(x)
	return function()
		return x
	end
end
local function count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local NOW = 1760000000
L.Time = NOW
local function profile(dogs)
	local p = R.Profile(1, NOW)
	p = R.Normalize(p, 1, NOW)
	p.Cash = 10000000
	p.Bones = 5000
	p.Upgrades.Plot = 4 -- kennels 1..5
	for i, id in ipairs(dogs or {}) do
		local d = R.Mint(p, id, "dog" .. i, {}, NOW, rng(i), "Test", "Normal", true)
		d.AssignedSlot = "DigSlot_" .. i
		d.State = "Digging"
	end
	return p
end
local function action(p, name, args, random)
	return R.Action(p, name, args, NOW, random or rng(3))
end
-- Runs an action on a copy (like the transaction does) and returns ok, message/err, extra, copy.
local function try(p, name, args, random)
	local copy = R.Copy(p)
	local ok, message, extra = pcall(action, copy, name, args, random)
	if ok then
		R.Validate(copy)
	end
	return ok, message, extra, copy
end
local function give(p, id, roll, extra)
	local eq_ = F.Ensure(p)
	local def = E.Def(id)
	local uid = "E1-" .. eq_.Next
	eq_.Next += 1
	local entry = { Uid = uid, Id = id, Rarity = def.Rarity, Roll = roll or 0.5, CreatedAt = NOW, Origin = "Test" }
	for k, v in pairs(extra or {}) do entry[k] = v end
	if def.Kind == "Artifact" then eq_.Artifacts[uid] = entry else eq_.Accessories[uid] = entry end
	eq_.Rev += 1
	return entry
end

-- Catalogue ------------------------------------------------------------------------------------
test("catalogue: 24 artifacts and 24 accessories, 4 per rarity, valid stats and slots", function()
	eq(#E.Artifacts, 24, "artifacts")
	eq(#E.Accessories, 24, "accessories")
	local ids = {}
	for _, list in ipairs({ E.Artifacts, E.Accessories }) do
		local perRarity = {}
		for _, def in ipairs(list) do
			truthy(not ids[def.Id], "duplicate id " .. def.Id)
			ids[def.Id] = true
			perRarity[def.Rarity] = (perRarity[def.Rarity] or 0) + 1
			truthy(E.RarityIndex[def.Rarity], "rarity " .. def.Id)
			truthy(type(def.Ru) == "string" and def.Ru ~= "" and def.Ru:find("[\208\209]"), "russian name " .. def.Id)
			truthy(def.Min > 0 and def.Max > def.Min, "range " .. def.Id)
			truthy(table.find(B.Keys, def.Stat), "Bonuses key " .. def.Id)
			if def.Kind == "Artifact" then
				truthy(table.find(E.ArtifactStats, def.Stat), "per-dog stat " .. def.Id)
			else
				truthy(table.find(E.AccessoryStats, def.Stat), "global stat " .. def.Id)
				truthy(E.SlotInfo[def.Slot], "slot " .. def.Id)
			end
		end
		for _, rarity in ipairs(E.Rarities) do eq(perRarity[rarity], 4, rarity) end
	end
	-- Every artifact stat exists in four rarities; every accessory slot has pieces.
	for _, stat in ipairs(E.ArtifactStats) do
		local n = 0
		for _, def in ipairs(E.Artifacts) do if def.Stat == stat then n += 1 end end
		eq(n, 4, "artifact stat " .. stat)
	end
	for _, slot in ipairs(E.Slots) do
		local n = 0
		for _, def in ipairs(E.Accessories) do if def.Slot == slot then n += 1 end end
		truthy(n >= 5, "accessory slot " .. slot)
	end
	for _, stat in ipairs(E.AccessoryStats) do
		local n = 0
		for _, def in ipairs(E.Accessories) do if def.Stat == stat then n += 1 end end
		truthy(n >= 2, "accessory stat " .. stat)
	end
end)

test("balance: a Mythic artifact is strong but bounded; accessories are smaller", function()
	for _, def in ipairs(E.Artifacts) do
		truthy(def.Max <= 0.52, "artifact max " .. def.Id .. " " .. def.Max)
		if def.Rarity == "Mythic" then truthy(def.Min >= 0.19, "mythic min " .. def.Id) end
	end
	for _, def in ipairs(E.Accessories) do
		truthy(def.Max <= 0.38, "accessory max " .. def.Id .. " " .. def.Max)
		if def.Stat == "MoneyMult" then truthy(def.Max <= 0.09, "small money multiplier " .. def.Id) end
	end
	-- Higher rarity never rolls below a lower rarity of the same stat.
	for _, list in ipairs({ E.Artifacts, E.Accessories }) do
		for _, a in ipairs(list) do
			for _, b in ipairs(list) do
				if a.Stat == b.Stat and E.RarityIndex[a.Rarity] > E.RarityIndex[b.Rarity] then
					truthy(a.Min >= b.Min and a.Max >= b.Max, a.Id .. " vs " .. b.Id)
				end
			end
		end
	end
	near(E.Value({ Id = "ChronoGear", Roll = 0 }), E.ArtifactById.ChronoGear.Min, 1e-9, "roll 0")
	near(E.Value({ Id = "ChronoGear", Roll = 1 }), E.ArtifactById.ChronoGear.Max, 1e-9, "roll 1")
	near(E.Value({ Id = "ChronoGear", Roll = 7 }), E.ArtifactById.ChronoGear.Max, 1e-9, "roll clamped")
	eq(E.Value({ Id = "Gone", Roll = 1 }), 0, "unknown piece is worth nothing")
end)

test("looks: every piece and case builds from 2..8 valid parts", function()
	local shapes = { B = true, S = true, C = true, W = true }
	local roles = { base = true, trim = true, dark = true, light = true, glow = true, gold = true, white = true, black = true }
	for _, list in ipairs({ E.Artifacts, E.Accessories }) do
		for _, def in ipairs(list) do
			local parts = def.Look and def.Look.Parts
			truthy(parts and #parts >= 2 and #parts <= 8, "part count " .. def.Id)
			local glow = false
			for _, spec in ipairs(parts) do
				truthy(shapes[spec[1]], "shape " .. def.Id)
				truthy(#spec[2] == 3 and #spec[3] == 3, "size/position " .. def.Id)
				truthy(type(spec[5]) == "table" or roles[spec[5]], "colour role " .. def.Id .. " " .. tostring(spec[5]))
				if spec[5] == "glow" then glow = true end
			end
			truthy(glow, "rarity accent part " .. def.Id)
		end
	end
	local Visuals = L.Require("ReplicatedStorage.DogEconomy.EquipmentVisuals")
	local model, bounds = Visuals.Build("VoidWings", { World = true, Scale = 1 })
	truthy(model and #model:GetChildren() == #E.AccessoryById.VoidWings.Look.Parts, "model parts")
	truthy(bounds.Radius > 0.5 and bounds.Radius < 6, "bounds " .. bounds.Radius)
	local anchoredInWorld = false
	for _, part in ipairs(model:GetChildren()) do
		if part.Anchored or part.CanCollide then anchoredInWorld = true end
	end
	eq(anchoredInWorld, false, "worn parts are unanchored and do not collide")
	local case = Visuals.Case("DigCrate")
	truthy(case and #case:GetChildren() >= 6, "case model")
end)

test("rarity colours match the UI kit", function()
	for rarity, rgb in pairs(E.RarityColors) do
		local c = Theme.Rarity[rarity]
		truthy(c, "kit rarity " .. rarity)
		eq(math.floor(c.R * 255 + 0.5), rgb[1], rarity .. " R")
		eq(math.floor(c.G * 255 + 0.5), rgb[2], rarity .. " G")
		eq(math.floor(c.B * 255 + 0.5), rgb[3], rarity .. " B")
	end
end)

test("cases: odds sum to 100, pools exist, Robux products not sold yet", function()
	for _, case in ipairs(E.Cases) do
		local total = 0
		for rarity, w in pairs(case.Odds) do
			truthy(E.RarityIndex[rarity], "rarity " .. case.Id)
			total += w
		end
		near(total, 100, 1e-9, case.Id)
		local pool = E.Pool(case)
		for rarity, w in pairs(case.Odds) do
			if w > 0 then truthy(pool[rarity] and #pool[rarity] > 0, case.Id .. " pool " .. rarity) end
		end
		local sum = 0
		for _, row in ipairs(E.Odds(case)) do sum += row.Chance end
		near(sum, 1, 1e-9, case.Id .. " chances")
		truthy(case.Cash or case.Bones or case.Robux, "payable " .. case.Id)
		truthy(case.Pity and E.RarityIndex[case.Pity.Rarity] and case.Pity.Opens >= 5, "pity " .. case.Id)
		truthy(type(case.Ru) == "string" and case.Ru ~= "", "russian " .. case.Id)
	end
	for _, product in ipairs(E.Products) do
		eq(product.Id, 0, "product id " .. product.Key)
		eq(product.Enabled, false, "product enabled " .. product.Key)
		truthy(E.CaseById[product.Case] and E.CaseById[product.Case].Robux, "robux case " .. product.Key)
	end
end)

test("dog slots by rank: Common 1, Rare 2, Epic 2, Legendary 3, Mythic 3, Secret 4", function()
	local expected = { 1, 2, 2, 3, 3, 4 }
	for rank, n in ipairs(expected) do
		eq(E.DogSlots(rank), n, "rank " .. rank)
		eq(E.DogSlots(E.DogRarities[rank]), n, "rarity " .. E.DogRarities[rank])
		eq(E.DogSlots({ Rank = rank }), n, "def " .. rank)
	end
	local D = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")
	eq(E.DogSlots(D.Breadog), 1, "Breadog")
	eq(E.DogSlots(D.TheDog), 4, "THE DOG")
end)

-- Saved data -----------------------------------------------------------------------------------
test("normalize: defaults for old saves, idempotent, nothing else touched", function()
	local p = R.Profile(1, NOW)
	p.Equipment = nil
	local cash = p.Cash
	p = R.Normalize(p, 1, NOW)
	truthy(type(p.Equipment) == "table", "created")
	for _, key in ipairs({ "Artifacts", "Accessories", "CaseCredits", "Seen", "Pity", "Opened" }) do
		truthy(type(p.Equipment[key]) == "table", key)
	end
	eq(p.Equipment.Version, 1)
	eq(p.Cash, cash, "wallet untouched")
	local rev = p.Equipment.Rev
	R.Normalize(p, 1, NOW)
	eq(p.Equipment.Rev, rev, "a clean profile is not rewritten")
	R.Validate(p)
	-- Validate never rejects what Normalize would heal (trade / lab call it alone).
	local raw = R.Copy(p)
	raw.Equipment = nil
	R.Validate(raw)
	raw.Equipment = { Artifacts = { x = { Id = "Gone", DogUid = "missing", Slot = 9 } } }
	R.Validate(raw)
	raw.Equipment = "broken"
	eq(pcall(R.Validate, raw), false, "non-table equipment rejected")
end)

test("normalize heals dangling dogs, bad slots, doubled slots and bad numbers", function()
	local p = profile({ "Breadog", "KingCorgi" })
	local bread, king = p.Dogs.dog1, p.Dogs.dog2
	local slotsKing = E.DogSlots(L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")[king.DogId])
	local a = give(p, "RustyTrowel", 0.4, { DogUid = bread.DogUid, Slot = 1 })
	local b = give(p, "LuckyPebble", 0.4, { DogUid = bread.DogUid, Slot = 2 }) -- Breadog has 1 slot
	local c = give(p, "CopperCoin", 0.4, { DogUid = "gone", Slot = 1 }) -- dog left (trade / lab)
	local d = give(p, "ChewToy", 0.4, { DogUid = king.DogUid, Slot = 1 })
	local e = give(p, "GoldBone", 0.4, { DogUid = king.DogUid, Slot = 1 }) -- doubled slot
	local f = give(p, "ChronoGear", 3, nil) -- bad roll
	local h1 = give(p, "PaperHat", 0.5, { Slot = "Hat" })
	local h2 = give(p, "MinerHelmet", 0.5, { Slot = "Hat" }) -- two hats
	local wrong = give(p, "RoundSpecs", 0.5, { Slot = "Hat" }) -- face piece in the hat slot
	p.Equipment.CaseCredits.DigCrate = { Free = -3, Paid = 2.7 }
	p.Equipment.Pity.DigCrate = -1
	local before = count(p.Equipment.Artifacts) + count(p.Equipment.Accessories)
	R.Normalize(p, 1, NOW)
	eq(count(p.Equipment.Artifacts) + count(p.Equipment.Accessories), before, "no piece dropped")
	eq(a.DogUid, bread.DogUid, "valid stays")
	eq(b.DogUid, nil, "slot beyond the dog's slots -> bag")
	eq(c.DogUid, nil, "dangling dog -> bag")
	eq(c.Slot, nil)
	local keep = d.Uid < e.Uid and d or e
	local drop = keep == d and e or d
	eq(keep.DogUid, king.DogUid, "lower uid keeps the doubled slot")
	eq(drop.DogUid, nil, "higher uid back in the bag")
	eq(f.Roll, 1, "roll clamped")
	local hats = 0
	for _, x in ipairs({ h1, h2 }) do if x.Slot == "Hat" then hats += 1 end end
	eq(hats, 1, "one hat worn")
	eq(wrong.Slot, nil, "face piece not in the hat slot")
	eq(p.Equipment.CaseCredits.DigCrate.Free, 0)
	eq(p.Equipment.CaseCredits.DigCrate.Paid, 2)
	eq(p.Equipment.Pity.DigCrate, 0)
	truthy(slotsKing >= 2, "KingCorgi has slots")
	R.Validate(p)
	local rev = p.Equipment.Rev
	R.Normalize(p, 1, NOW)
	eq(p.Equipment.Rev, rev, "healed profile stays still")
end)

test("a dog leaving the profile returns its artifacts to the bag (lab / trade / market / shelter)", function()
	local p = profile({ "KingCorgi" })
	local art = give(p, "GoldBone", 0.5, { DogUid = "dog1", Slot = 1 })
	p.Dogs.dog1 = nil
	R.Validate(p) -- no Normalize: still valid
	R.Normalize(p, 1, NOW)
	eq(art.DogUid, nil)
	truthy(p.Equipment.Artifacts[art.Uid], "artifact kept")
end)

-- Cases ----------------------------------------------------------------------------------------
test("open for Coins: server price follows income, pays, adds one piece, honest reel", function()
	local p = profile({ "Breadog" })
	local case = E.CaseById.DigCrate
	local price = E.CashPrice(case, p, NOW)
	eq(price, Pricing.Coins(case.Cash, p, NOW), "same formula as boosts")
	truthy(price >= case.Cash.MinCash, "floor")
	local cash = p.Cash
	local message, extra = action(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash" })
	truthy(type(message) == "string", "message")
	eq(p.Cash, cash - price, "charged the server price")
	eq(count(p.Equipment.Artifacts), 1, "one artifact")
	local opened = extra.Opened
	truthy(p.Equipment.Artifacts[opened.Uid], "stored")
	eq(opened.Kind, "Artifact")
	eq(extra.Reel[extra.WinIndex], opened.Id, "reel lands on the winner")
	eq(#extra.Reel, 32, "reel length")
	for _, id in ipairs(extra.Reel) do truthy(E.ArtifactById[id], "reel shows artifacts only") end
	truthy(opened.Roll >= 0 and opened.Roll <= 1, "roll")
	near(opened.Value, E.Value(opened), 1e-3, "value")
	eq(opened.New, true, "first of its kind")
	eq(p.Equipment.Seen[opened.Id], true)
	eq(p.Equipment.Opened.DigCrate, 1)
	R.Validate(p)
	-- With more income the price rises (an hour of 1,000 coins/s -> 5 minutes = 300,000).
	p.OfflineEarnings = p.OfflineEarnings or {}
	p.OfflineEarnings.BaseRate = 1000
	eq(E.CashPrice(case, p, NOW), Pricing.Round(1000 * 60 * 5), "income-scaled")
end)

test("open: quote is a ceiling, short wallets and wrong payment are refused without changes", function()
	local p = profile()
	local price = E.CashPrice(E.CaseById.DigCrate, p, NOW)
	local ok, _, _, copy = try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash", Quote = price - 10 })
	truthy(ok, "within 5% -> the shown price")
	eq(copy.Cash, p.Cash - (price - 10), "charged the quote")
	ok = try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash", Quote = math.floor(price * 0.5) })
	eq(ok, false, "price moved too far: look again")
	p.Cash = price - 1
	local ok2, err = try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash" })
	eq(ok2, false, "short wallet")
	truthy(tostring(err):find("Not enough"), tostring(err))
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Bones" })), false, "Coins case for Bones")
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "RelicChest", Pay = "Cash" })), false, "Bones case for Coins")
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "Nope", Pay = "Cash" })), false, "unknown case")
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Robux" })), false, "unknown payment")
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "MythicVault", Pay = "Cash" })), false, "Robux case is never sold for Coins")
	eq(count(p.Equipment.Artifacts), 0, "nothing granted")
end)

test("open for Bones and with keys; paid keys follow Roblox policy and are kept", function()
	local p = profile()
	local bones = p.Bones
	local _, extra = action(p, "EquipmentOpenCase", { Case = "GlamChest", Pay = "Bones" })
	eq(p.Bones, bones - E.CaseById.GlamChest.Bones, "Bones paid")
	eq(extra.Opened.Kind, "Accessory")
	truthy(E.RarityIndex[extra.Opened.Rarity] >= 2, "Glam Chest has no Commons")
	-- Free key from a reward.
	F.GrantCredits(p, "StarTrunk", 1, false)
	local _, keyed = action(p, "EquipmentOpenCase", { Case = "StarTrunk", Pay = "Credit" })
	eq(keyed.Opened.PaidRandom, nil, "free key: not paid random")
	eq(p.Equipment.CaseCredits.StarTrunk.Free, 0)
	-- Paid key: no player online in this test -> policy says no -> refused, key kept.
	F.GrantCredits(p, "StarTrunk", 2, true)
	local ok, err, _, copy = try(p, "EquipmentOpenCase", { Case = "StarTrunk", Pay = "Credit" })
	eq(ok, false, "paid random blocked")
	truthy(tostring(err):find("unavailable"), tostring(err))
	eq(p.Equipment.CaseCredits.StarTrunk.Paid, 2, "keys kept")
	local _ = copy
	eq(select(1, try(p, "EquipmentOpenCase", { Case = "MythicVault", Pay = "Credit" })), false, "no keys")
end)

test("paid keys open where policy allows and the piece is flagged PaidRandom", function()
	local Players = L.Stubs.Players
	local player = { UserId = 1, Parent = Players }
	local saved = Players.GetPlayerByUserId
	Players.GetPlayerByUserId = function(_, id) return id == 1 and player or nil end
	local Policy = L.Require("ServerScriptService.Economy.PaidRandomPolicy")
	local savedInfo = Policy.Info
	Policy.Info = function() return { Ok = true, PaidRandom = true, Trading = false, At = os.clock() } end
	local ok, err = pcall(function()
		local p = profile()
		F.GrantCredits(p, "MythicVault", 1, true)
		local _, extra = action(p, "EquipmentOpenCase", { Case = "MythicVault", Pay = "Credit" })
		eq(extra.Opened.PaidRandom, true, "flagged")
		eq(p.Equipment.Artifacts[extra.Opened.Uid].PaidRandom, true, "stored flag")
		eq(p.Equipment.CaseCredits.MythicVault.Paid, 0)
		truthy(E.RarityIndex[extra.Opened.Rarity] >= E.RarityIndex.Rare, "vault odds")
	end)
	Players.GetPlayerByUserId = saved
	Policy.Info = savedInfo
	if not ok then error(err, 0) end
end)

test("bag capacity: a full bag refuses to open (and charges nothing)", function()
	local p = profile()
	for i = 1, E.Capacity.Accessory do give(p, "PaperHat", i / 200) end
	local cash = p.Cash
	local ok, err = try(p, "EquipmentOpenCase", { Case = "StyleBox", Pay = "Cash" })
	eq(ok, false)
	truthy(tostring(err):find("full"), tostring(err))
	eq(p.Cash, cash)
	-- The artifact bag is separate.
	truthy(select(1, try(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash" })), "artifact bag has room")
end)

test("pity: the 30th open in a row without Epic+ is Epic or better, then the streak resets", function()
	local p = profile()
	local rarities = {}
	for i = 1, 31 do
		local _, extra = action(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash" }, constant(0))
		rarities[i] = extra.Opened.Rarity
		if i == 30 then eq(extra.Opened.Pity, true, "pity flag") end
	end
	for i = 1, 29 do eq(rarities[i], "Common", "roll 0 is Common " .. i) end
	truthy(E.RarityIndex[rarities[30]] >= E.RarityIndex.Epic, "30th: " .. rarities[30])
	eq(rarities[31], "Common", "streak reset")
	eq(p.Equipment.Pity.DigCrate, 1)
end)

test("odds: 200,000 rolls match the published chances", function()
	for _, caseId in ipairs({ "DigCrate", "RelicChest", "MythicVault" }) do
		local case = E.CaseById[caseId]
		local counts, n, random = {}, 200000, rng(17)
		for _ = 1, n do
			local rarity = F.RollRarity(case, 0, random)
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		for _, row in ipairs(E.Odds(case)) do
			near((counts[row.Rarity] or 0) / n, row.Chance, math.max(0.003, row.Chance * 0.06), caseId .. " " .. row.Rarity)
		end
	end
end)

-- Equipping ------------------------------------------------------------------------------------
test("artifacts: equip, replace (reported), move between dogs, slots by rank, unequip", function()
	local p = profile({ "Breadog", "KingCorgi" })
	local a = give(p, "RustyTrowel", 0.5)
	local b = give(p, "TurboPaws", 0.5)
	local _, extra = action(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog1", Slot = 1 })
	eq(a.DogUid, "dog1")
	eq(extra.Replaced, nil)
	local _, extra2 = action(p, "EquipArtifact", { Uid = b.Uid, DogUid = "dog1", Slot = 1 })
	eq(extra2.Replaced, a.Uid, "old one reported")
	eq(a.DogUid, nil, "old one back in the bag")
	eq(b.DogUid, "dog1")
	eq(select(1, try(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog1", Slot = 2 })), false, "Breadog has one slot")
	eq(select(1, try(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog9", Slot = 1 })), false, "not owned")
	eq(select(1, try(p, "EquipArtifact", { Uid = "nope", DogUid = "dog1", Slot = 1 })), false, "unknown artifact")
	eq(select(1, try(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog1", Slot = 1.5 })), false, "fractional slot")
	local _, moved = action(p, "EquipArtifact", { Uid = b.Uid, DogUid = "dog2", Slot = 2 })
	eq(moved.MovedFrom, "dog1", "moved")
	eq(b.DogUid, "dog2")
	action(p, "UnequipArtifact", { Uid = b.Uid })
	eq(b.DogUid, nil)
	eq(b.Slot, nil)
	p.Dogs.dog1.State = "Walking"
	eq(select(1, try(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog1", Slot = 1 })), false, "dog still walking in")
	R.Validate(p)
end)

test("accessories: one per slot, swap returns the old one, take off by slot", function()
	local p = profile()
	local hat1 = give(p, "PaperHat", 0.5)
	local hat2 = give(p, "RoyalCrown", 0.5)
	local face = give(p, "StarShades", 0.5)
	action(p, "EquipAccessory", { Uid = hat1.Uid })
	action(p, "EquipAccessory", { Uid = face.Uid })
	local _, extra = action(p, "EquipAccessory", { Uid = hat2.Uid })
	eq(extra.Replaced, hat1.Uid)
	eq(hat1.Slot, nil)
	eq(hat2.Slot, "Hat")
	eq(face.Slot, "Face")
	action(p, "UnequipAccessory", { Slot = "Face" })
	eq(face.Slot, nil)
	eq(select(1, try(p, "UnequipAccessory", { Slot = "Face" })), false, "nothing there")
	eq(select(1, try(p, "UnequipAccessory", { Slot = "Tail" })), false, "unknown slot")
end)

-- Bonuses --------------------------------------------------------------------------------------
test("an artifact boosts only its dog; accessories boost every dog", function()
	local p = profile({ "KingCorgi", "KingCorgi" })
	local speed = give(p, "ChronoGear", 1)
	action(p, "EquipArtifact", { Uid = speed.Uid, DogUid = "dog1", Slot = 1 })
	local one, two = B.Dog(p, p.Dogs.dog1, NOW), B.Dog(p, p.Dogs.dog2, NOW)
	near(one.DigSpeed, E.ArtifactById.ChronoGear.Max, 1e-9, "dog1 gets it")
	eq(two.DigSpeed, 0, "dog2 does not")
	eq(B.Global(p, NOW).DigSpeed, 0, "not global")
	-- Real effect: dog1 rests less than dog2.
	local c1 = R.Cooldown(p, p.Dogs.dog1)
	local c2 = R.Cooldown(p, p.Dogs.dog2)
	truthy(c1 < c2, "cooldown " .. c1 .. " < " .. c2)
	-- Accessory: global.
	local aura = give(p, "RainbowAura", 0.5)
	action(p, "EquipAccessory", { Uid = aura.Uid })
	near(B.Global(p, NOW).Income, E.Value(aura), 1e-9, "global income")
	near(B.For(p, p.Dogs.dog2, NOW).Income, E.Value(aura), 1e-9, "every dog")
	-- Taking it off removes the bonus (the index follows Equipment.Rev).
	action(p, "UnequipArtifact", { Uid = speed.Uid })
	eq(B.Dog(p, p.Dogs.dog1, NOW).DigSpeed, 0, "removed")
end)

test("per-dog caps; several stats add up on one dog", function()
	local p = profile({ "TheDog" })
	for slot = 1, 4 do
		local a = give(p, "ChronoGear", 1)
		action(p, "EquipArtifact", { Uid = a.Uid, DogUid = "dog1", Slot = slot })
	end
	near(B.Dog(p, p.Dogs.dog1, NOW).DigSpeed, E.ArtifactCaps.DigSpeed, 1e-9, "capped")
	local q = profile({ "TheDog" })
	local x = give(q, "MidasBell", 0.5)
	local y = give(q, "FortuneEye", 0.5)
	action(q, "EquipArtifact", { Uid = x.Uid, DogUid = "dog1", Slot = 1 })
	action(q, "EquipArtifact", { Uid = y.Uid, DogUid = "dog1", Slot = 2 })
	local totals = ArtifactSource.Totals(q, q.Dogs.dog1)
	near(totals.Income, E.Value(x), 1e-9)
	near(totals.Luck, E.Value(y), 1e-9)
end)

test("income model: an Income artifact raises its dog's coins per minute only", function()
	local p = profile({ "KingCorgi", "KingCorgi" })
	local before = R.IncomeModel(p, NOW)
	local bell = give(p, "MidasBell", 1)
	action(p, "EquipArtifact", { Uid = bell.Uid, DogUid = "dog1", Slot = 1 })
	local after = R.IncomeModel(p, NOW)
	local ratio = after.Dogs.dog1.CoinsPerMin / before.Dogs.dog1.CoinsPerMin
	near(ratio, 1 + E.ArtifactById.MidasBell.Max, 0.01, "dog1 x(1+income)")
	near(after.Dogs.dog2.CoinsPerMin, before.Dogs.dog2.CoinsPerMin, 1e-6, "dog2 unchanged")
end)

test("offline earnings follow an Offline accessory; shelter value ignores artifacts", function()
	local p = profile({ "KingCorgi" })
	local base = O.Estimate(p)
	local wings = give(p, "AngelWings", 1)
	action(p, "EquipAccessory", { Uid = wings.Uid })
	local boosted = O.Estimate(p)
	near(boosted / base, 1 + E.AccessoryById.AngelWings.Max, 0.01, "offline x(1+bonus)")
	local bonus = R.Bonus(p.Dogs.dog1)
	local art = give(p, "TitanHarness", 1)
	action(p, "EquipArtifact", { Uid = art.Uid, DogUid = "dog1", Slot = 1 })
	eq(R.Bonus(p.Dogs.dog1), bonus, "R.Bonus (shelter prices) untouched")
end)

-- Salvage and lock -----------------------------------------------------------------------------
test("salvage: Bones by rarity; locked, worn and duplicate pieces refused", function()
	local p = profile({ "KingCorgi" })
	local a = give(p, "ChronoGear", 0.5)
	local b = give(p, "PaperHat", 0.5)
	local c = give(p, "GoldBone", 0.5)
	local bones = p.Bones
	local _, extra = action(p, "SalvageEquipment", { Uids = { a.Uid, b.Uid } })
	eq(extra.Bones, E.Salvage.Mythic + E.Salvage.Common)
	eq(p.Bones, bones + extra.Bones)
	eq(p.Equipment.Artifacts[a.Uid], nil)
	eq(p.Equipment.Accessories[b.Uid], nil)
	action(p, "LockEquipment", { Uid = c.Uid, Enabled = true })
	eq(c.Locked, true)
	eq(select(1, try(p, "SalvageEquipment", { Uids = { c.Uid } })), false, "locked")
	action(p, "LockEquipment", { Uid = c.Uid, Enabled = false })
	eq(c.Locked, nil)
	action(p, "EquipArtifact", { Uid = c.Uid, DogUid = "dog1", Slot = 1 })
	eq(select(1, try(p, "SalvageEquipment", { Uids = { c.Uid } })), false, "equipped")
	action(p, "UnequipArtifact", { Uid = c.Uid })
	eq(select(1, try(p, "SalvageEquipment", { Uids = { c.Uid, c.Uid } })), false, "duplicate uid")
	eq(select(1, try(p, "SalvageEquipment", { Uids = {} })), false, "empty")
	eq(select(1, try(p, "SalvageEquipment", { Uids = { c.Uid, x = 1 } })), false, "holes / extra keys")
	local many = {}
	for i = 1, E.MaxSalvageBatch + 1 do many[i] = give(p, "PaperHat", 0.1).Uid end
	eq(select(1, try(p, "SalvageEquipment", { Uids = many })), false, "batch limit")
	truthy(p.Equipment.Artifacts[c.Uid], "nothing lost on refusals")
end)

test("salvage economics: no case returns more Bones than it costs", function()
	for _, case in ipairs(E.Cases) do
		local expected = 0
		for _, row in ipairs(E.Odds(case)) do expected += row.Chance * E.Salvage[row.Rarity] end
		if case.Bones then truthy(expected < case.Bones * 0.4, case.Id .. " " .. expected) end
	end
end)

-- Snapshot and Robux ---------------------------------------------------------------------------
test("snapshot: Features.Equipment shape per contract", function()
	local p = profile({ "KingCorgi" })
	action(p, "EquipmentOpenCase", { Case = "DigCrate", Pay = "Cash" })
	action(p, "EquipmentOpenCase", { Case = "StyleBox", Pay = "Cash" })
	local art = give(p, "GoldBone", 0.5)
	action(p, "EquipArtifact", { Uid = art.Uid, DogUid = "dog1", Slot = 1 })
	local view = {}
	R.Features.Snapshot(R, p, view, NOW)
	local s = view.Equipment
	truthy(s, "present")
	eq(#s.Artifacts, 2)
	eq(#s.Accessories, 1)
	for _, key in ipairs({ "CaseCredits", "Cases", "DogSlots", "Capacity", "Equipped", "ByDog" }) do truthy(type(s[key]) == "table", key) end
	eq(type(s.PaidAllowed), "boolean")
	eq(s.DogSlots.Secret, 4)
	eq(s.ByDog.dog1[1], art.Uid)
	local digCrate
	for _, row in ipairs(s.Cases) do if row.Id == "DigCrate" then digCrate = row end end
	eq(digCrate.Cash, E.CashPrice(E.CaseById.DigCrate, p, NOW), "server price")
	eq(digCrate.Pity.Count, p.Equipment.Pity.DigCrate)
	truthy(#digCrate.Odds >= 5, "odds rows")
	for _, row in ipairs(s.Cases) do eq(#row.Products, 0, "no Robux product on sale yet " .. row.Id) end
	local entry = s.Artifacts[1]
	for _, key in ipairs({ "Uid", "Id", "Rarity", "Roll", "Value", "Stat" }) do truthy(entry[key] ~= nil, "entry " .. key) end
end)

test("Robux keys: catalog registration and receipt grant (credits only)", function()
	local registered = {}
	F.Catalogs(function(catalog, handler)
		table.insert(registered, { Catalog = catalog, Handler = handler })
	end)
	eq(#registered, 1)
	local catalog, handler = registered[1].Catalog, registered[1].Handler
	eq(catalog.Kind, "EquipmentCases")
	eq(#catalog.Rows(), #E.Products)
	eq(catalog.Sold(E.Products[1]), false, "not on sale")
	local p = profile()
	local result = handler.Grant(p, E.ProductByKey.MythicVault5, { Now = NOW })
	eq(p.Equipment.CaseCredits.MythicVault.Paid, 5)
	eq(result.Count, 5)
	eq(count(p.Equipment.Artifacts), 0, "nothing opened by the receipt")
	R.Validate(p)
end)

test("Robux key packs are offered only where paid random items are allowed (unknown = not allowed)", function()
	local Players = L.Stubs.Players
	local player = { UserId = 1, Parent = Players }
	local savedGet = Players.GetPlayerByUserId
	Players.GetPlayerByUserId = function(_, id) return id == 1 and player or nil end
	local Policy = L.Require("ServerScriptService.Economy.PaidRandomPolicy")
	local product = E.ProductByKey.MythicVault1
	local savedId, savedEnabled = product.Id, product.Enabled
	product.Id, product.Enabled = 990001, true
	local function vaultProducts(p)
		local view = {}
		R.Features.Snapshot(R, p, view, NOW)
		for _, row in ipairs(view.Equipment.Cases) do
			if row.Id == "MythicVault" then return #row.Products, view.Equipment end
		end
		return -1
	end
	local ok, err = pcall(function()
		local p = profile()
		Policy.Cache[1] = nil
		local n, s = vaultProducts(p)
		eq(s.PaidKnown, false, "policy not known yet")
		eq(n, 0, "unknown policy: nothing offered")
		Policy.Cache[1] = { At = os.clock(), Ok = true, PaidRandom = false, Trading = false }
		n, s = vaultProducts(p)
		eq(s.PaidAllowed, false)
		eq(n, 0, "restricted account: no key pack offered")
		Policy.Cache[1] = { At = os.clock(), Ok = true, PaidRandom = true, Trading = false }
		n, s = vaultProducts(p)
		eq(s.PaidAllowed, true)
		eq(n, 1, "allowed account: the enabled key pack is offered")
	end)
	Players.GetPlayerByUserId = savedGet
	Policy.Cache[1] = nil
	product.Id, product.Enabled = savedId, savedEnabled
	if not ok then error(err, 0) end
end)

test("worn accessories: the player watcher's connections are disconnected when the player leaves", function()
	local Players = L.Stubs.Players
	local function signal()
		local s = { Handlers = {} }
		function s:Connect(fn)
			local c = { Connected = true }
			function c:Disconnect() self.Connected = false end
			table.insert(s.Handlers, { Fn = fn, C = c })
			return c
		end
		function s:Fire(...)
			for _, h in ipairs(s.Handlers) do
				if h.C.Connected then h.Fn(...) end
			end
		end
		return s
	end
	local savedAdded, savedRemoving = Players.PlayerAdded, Players.PlayerRemoving
	local added, removing = signal(), signal()
	Players.PlayerAdded, Players.PlayerRemoving = added, removing
	local ok, err = pcall(function()
		local World = L.Require("ServerScriptService.Economy.EquipmentWorld")
		World.Views = { [7] = profile(), [8] = profile() }
		local function makePlayer(userId)
			local attribute, characterAdded = signal(), signal()
			local character = { Parent = true }
			function character:GetChildren() return {} end
			local player = { UserId = userId, Parent = Players, Character = character, CharacterAdded = characterAdded, Attribute = attribute }
			function player:GetAttributeChangedSignal() return attribute end
			return player
		end
		local function connections(player)
			local list = {}
			for _, h in ipairs(player.Attribute.Handlers) do table.insert(list, h.C) end
			for _, h in ipairs(player.CharacterAdded.Handlers) do table.insert(list, h.C) end
			return list
		end
		World.Start()
		local player = makePlayer(7)
		added:Fire(player)
		World.Apply(player) -- the first dress (deferred in the game)
		World.Apply(player, true) -- a respawn
		removing:Fire(player)
		eq(World.Applied[player], nil, "entry dropped")
		eq(#connections(player), 2, "watcher connections")
		for _, c in ipairs(connections(player)) do eq(c.Connected, false, "watcher disconnected on leave") end
		-- A player seen twice (PlayerAdded and Start's GetPlayers loop) gets one watcher only.
		local other = makePlayer(8)
		added:Fire(other)
		added:Fire(other)
		eq(#connections(other), 2, "one watcher")
		removing:Fire(other)
		for _, c in ipairs(connections(other)) do eq(c.Connected, false, "second player's watcher disconnected") end
	end)
	Players.PlayerAdded, Players.PlayerRemoving = savedAdded, savedRemoving
	if not ok then error(err, 0) end
end)

test("localization: every server message of the feature has a Russian entry", function()
	local messages = {
		"Unknown case", "Choose how to pay", "Your artifact bag is full: salvage some artifacts first",
		"Your accessory bag is full: salvage some accessories first", "Opening too fast; wait a moment",
		"This case is not sold for Coins", "This case is not sold for Bones", "You have no keys for this case",
		"Paid random items are unavailable for this account; your keys are kept", "Artifact equipped", "Artifact replaced",
		"Accessory equipped", "Accessory taken off", "Artifact returned to your bag", "Nothing is equipped there",
		"EQUIPMENT", "OPEN EQUIPMENT", "Equipment, cosmetics and supplies",
	}
	for _, m in ipairs(messages) do truthy(Locale.Exact[m] and Locale.Exact[m]:find("[\208\209]"), "ru " .. m) end
	local samples = {
		"This dog has 3 artifact slots", "Salvaged 2 pieces for 13 Bones", "Unlock Gold Bone before salvaging it",
		"The price changed with your income: 3200 Coins now. Check and open again",
		"5 keys for MYTHIC VAULT added · open it in the EQUIPMENT shop",
	}
	for _, text in ipairs(samples) do
		local hit = false
		for _, rule in ipairs(Locale.Patterns) do
			if text:find(rule[1]) then hit = true end
		end
		truthy(hit, "pattern for " .. text)
	end
end)

print(string.format("equipment: %d passed, %d failed", passed, failed))
if failed > 0 then
	error(failed .. " equipment test(s) failed")
end
