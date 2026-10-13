--!nocheck
-- PLOT COSMETICS: the MY BEST FINDS showcase (Features.Showcase, ShowcaseRules, the collector's
-- sale protection in YardCommerce) and plot decorations (DecorCatalog, Features.Decor, DecorModels).
--   lune run tests/plot_cosmetics.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau) through Rules.Action / Normalize /
-- Validate, like the economy transaction does.
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
-- Lune's CFrame.lookAt is wrong (tools/qa/scene.luau): modules get a corrected one, before any require.
do
	local Raw = roblox.CFrame
	local function lookAt(at, target, up)
		local look = target - at
		if look.Magnitude < 1e-9 then return Raw.new(at) end
		look = look.Unit
		up = up or roblox.Vector3.new(0, 1, 0)
		local right = look:Cross(up)
		if right.Magnitude < 1e-6 then right = look:Cross(roblox.Vector3.new(0, 0, -1)) end
		if right.Magnitude < 1e-6 then right = look:Cross(roblox.Vector3.new(1, 0, 0)) end
		right = right.Unit
		return Raw.fromMatrix(at, right, right:Cross(look))
	end
	L.CFrame = setmetatable({ lookAt = lookAt, new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then return lookAt(a, b) end
		return Raw.new(...)
	end }, { __index = Raw })
end
local R = L.Require("ServerScriptService.Economy.Rules")
local ItemDefs = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local Rules = L.Require("ReplicatedStorage.DogEconomy.ShowcaseRules")
local Showcase = L.Require("ServerScriptService.Economy.Features.Showcase")
local Decor = L.Require("ServerScriptService.Economy.Features.Decor")
local Catalog = L.Require("ReplicatedStorage.DogEconomy.DecorCatalog")
local Resources = L.Require("ReplicatedStorage.DogEconomy.Resources")
local Locale = L.Require("ReplicatedStorage.Localization.Plot")
local Forge = L.Require("ReplicatedStorage.Forge")

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
local function fails(fn, pattern)
	local ok, err = pcall(fn)
	truthy(not ok, "expected an error matching " .. tostring(pattern))
	if pattern then truthy(string.find(tostring(err), pattern, 1, true), "error '" .. tostring(err) .. "' lacks '" .. pattern .. "'") end
	return err
end
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local function count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local NOW = 1760000000
L.Time = NOW
-- Presence (at the showcase / in the yard) is a world check; tests decide it.
local atShowcase, inYard = true, true
Showcase.Present = function() return atShowcase end
Decor.Present = function() return inYard end

-- Item ids by rarity (ItemValuation rules).
local byRarity = {}
for id in pairs(ItemDefs) do
	local r = Rules.Rarity(id)
	byRarity[r] = byRarity[r] or {}
	table.insert(byRarity[r], id)
end
for _, list in pairs(byRarity) do table.sort(list) end
local function itemOf(rarity) return assert(byRarity[rarity] and byRarity[rarity][1], "no " .. rarity .. " item") end

local function addItem(p, uid, itemId, opts)
	opts = opts or {}
	local def = ItemDefs[itemId]
	local x = {
		ItemUid = uid, ItemId = itemId, DisplayName = def.DisplayName, Depth = def.Depth, Class = def.Class,
		WeightKg = opts.Weight or def.BaseWeightKg, TierIndex = 3, WeightTier = "Normal", WeightProfile = def.WeightProfile,
		BaseWeightKg = def.BaseWeightKg, Mutation = opts.Mutation or "NORMAL", FoundAt = NOW, OwnerUserId = p.UserId,
		OriginalFinderUserId = p.UserId, FoundByUserId = p.UserId, SellValue = opts.Value or 100, CombinedOdds = 10,
		Tradeable = true, RecordAtCreation = { Personal = false, Server = false, Global = false }, Favorite = false,
	}
	p.Items[uid] = x
	return x
end

local function profile(opts)
	opts = opts or {}
	local p = R.Profile(1, NOW)
	p = R.Normalize(p, 1, NOW)
	p.Cash = opts.Cash or 0
	p.Bones = opts.Bones or 0
	p.Upgrades.Plot = (opts.Stage or 1) - 1
	p.Resources = { Stone = opts.Stone or 0 }
	return p
end
local function action(p, name, args)
	return R.Action(p, name, args, NOW, rng(3))
end
-- Runs an action on a copy (like the transaction) and returns ok, message/err, extra, copy.
local function try(p, name, args)
	local copy = R.Copy(p)
	local ok, message, extra = pcall(action, copy, name, args)
	if ok then
		R.Validate(copy)
	end
	return ok, message, extra, copy
end

------------------------------------------------------------------------------------------------
-- Showcase
------------------------------------------------------------------------------------------------
test("new player: empty showcase, valid profile, automatic cases", function()
	local p = profile()
	eq(type(p.Showcase), "table", "Normalize creates the table")
	eq(p.Showcase.Version, 1, "version")
	eq(count(p.Showcase.Slots), 0, "no pins")
	R.Validate(p)
	eq(Rules.Capacity(p), 4, "four cases before stage 5")
	local layout = Rules.Layout(p)
	eq(count(layout.Slots), 0, "nothing to show yet")
end)

test("old profile without Showcase / Decor validates and normalizes", function()
	local p = profile()
	p.Showcase = nil
	p.Decor = nil
	R.Validate(p) -- nil-safe
	Showcase.Validate(R, p)
	Decor.Validate(R, p)
	R.Normalize(p, 1, NOW)
	eq(type(p.Showcase.Slots), "table", "showcase healed")
	eq(type(p.Decor.Owned), "table", "decor healed")
	eq(type(p.Decor.Placed), "table", "decor placed healed")
	R.Validate(p)
end)

test("ShowcaseSet pins an owned find; moving clears the old case; clear returns to auto", function()
	local p = profile()
	addItem(p, "a", itemOf("Common"))
	addItem(p, "b", itemOf("Rare"))
	local ok, msg = try(p, "ShowcaseSet", { Slot = 1, Uid = "a" })
	truthy(ok, msg)
	action(p, "ShowcaseSet", { Slot = 1, Uid = "a" })
	eq(p.Showcase.Slots["1"], "a", "pinned")
	local _, extra = action(p, "ShowcaseSet", { Slot = 3, Uid = "a" })
	eq(p.Showcase.Slots["1"], nil, "old case cleared")
	eq(p.Showcase.Slots["3"], "a", "moved")
	eq(extra.MovedFrom, 1, "reply names the old case")
	action(p, "ShowcaseSet", { Slot = 3, Uid = "b" })
	eq(p.Showcase.Slots["3"], "b", "replaced")
	action(p, "ShowcaseClear", { Slot = 3 })
	eq(p.Showcase.Slots["3"], nil, "cleared")
	fails(function() action(p, "ShowcaseClear", { Slot = 3 }) end, "automatically")
	R.Validate(p)
end)

test("ShowcaseSet refuses finds you do not own, bad cases and the locked fifth case", function()
	local p = profile()
	addItem(p, "a", itemOf("Common"))
	fails(function() action(p, "ShowcaseSet", { Slot = 1, Uid = "nope" }) end, "own")
	fails(function() action(p, "ShowcaseSet", { Slot = 0, Uid = "a" }) end, "case")
	fails(function() action(p, "ShowcaseSet", { Slot = 1.5, Uid = "a" }) end, "case")
	fails(function() action(p, "ShowcaseSet", { Slot = "x", Uid = "a" }) end, "case")
	fails(function() action(p, "ShowcaseSet", { Slot = 5, Uid = "a" }) end, "stage 5")
	fails(function() action(p, "ShowcaseSet", { Slot = 1, Uid = 5 }) end, "find")
	local other = addItem(p, "theirs", itemOf("Common"))
	other.OwnerUserId = 99
	fails(function() action(p, "ShowcaseSet", { Slot = 1, Uid = "theirs" }) end, "own")
	p.Items.theirs = nil
	-- Stage 5 opens the crown case.
	p.Upgrades.Plot = 4
	eq(Rules.Capacity(p), 5, "five cases at stage 5")
	action(p, "ShowcaseSet", { Slot = 5, Uid = "a" })
	eq(p.Showcase.Slots["5"], "a", "crown case")
	R.Validate(p)
end)

test("showcase edits need the player at their own showcase", function()
	local p = profile()
	addItem(p, "a", itemOf("Common"))
	atShowcase = false
	local ok, err = pcall(action, p, "ShowcaseSet", { Slot = 1, Uid = "a" })
	atShowcase = true
	truthy(not ok and string.find(err, "showcase"), tostring(err))
	eq(p.Showcase.Slots["1"], nil, "nothing changed")
end)

test("a sold / traded pin is pruned and the case falls back to the automatic pick", function()
	local p = profile()
	addItem(p, "best", itemOf("Legendary"))
	addItem(p, "mid", itemOf("Rare"))
	addItem(p, "low", itemOf("Common"))
	action(p, "ShowcaseSet", { Slot = 2, Uid = "low" })
	local layout = Rules.Layout(p)
	eq(layout.Slots[2].Uid, "low", "pinned case")
	truthy(layout.Slots[2].Pinned, "flagged pinned")
	eq(layout.Slots[1].Uid, "best", "auto: rarest first")
	eq(layout.Slots[3].Uid, "mid", "auto: next")
	truthy(layout.Slots[1].Auto and not layout.Slots[1].Pinned, "auto flag")
	eq(layout.Auto[1], "best", "auto uid list")
	-- The pinned find leaves the inventory (sold elsewhere, traded, used by the lab).
	p.Items.low = nil
	R.Validate(p) -- structural: a dangling pin is not an error
	R.Normalize(p, 1, NOW)
	eq(p.Showcase.Slots["2"], nil, "pruned")
	layout = Rules.Layout(p)
	eq(layout.Slots[1].Uid, "best", "auto again")
	eq(layout.Slots[2].Uid, "mid", "the freed case shows the next best find")
	eq(layout.Slots[3], nil, "nothing left for case 3")
end)

test("auto fallback also shows find records (trophies) and never repeats a pinned find", function()
	local p = profile()
	addItem(p, "owned", itemOf("Rare"))
	p.Stats.MostValuable = { ItemId = itemOf("Secret"), ItemUid = "sold_secret", DisplayName = "Sold Secret", WeightKg = 1, SellValue = 5000, Mutation = "NORMAL" }
	action(p, "ShowcaseSet", { Slot = 4, Uid = "owned" })
	local layout = Rules.Layout(p)
	eq(layout.Slots[1].Uid, "sold_secret", "record trophy shown")
	eq(layout.Slots[1].Owned, false, "flagged as not owned")
	eq(layout.Slots[4].Uid, "owned", "pin kept")
	for i = 1, 3 do
		truthy(layout.Slots[i] == nil or layout.Slots[i].Uid ~= "owned", "pinned find is not repeated")
	end
	-- A record cannot be pinned: it is not an owned find.
	fails(function() action(p, "ShowcaseSet", { Slot = 1, Uid = "sold_secret" }) end, "own")
end)

test("ranking: rarity, then mutation, then value; effect tiers", function()
	local p = profile()
	addItem(p, "plainEpic", itemOf("Epic"), { Value = 50 })
	addItem(p, "goldEpic", itemOf("Epic"), { Mutation = "GOLDEN", Value = 10 })
	addItem(p, "rare", itemOf("Rare"), { Value = 999999 })
	local layout = Rules.Layout(p)
	eq(layout.Slots[1].Uid, "goldEpic", "mutation breaks the tie")
	eq(layout.Slots[2].Uid, "plainEpic", "then the other epic")
	eq(layout.Slots[3].Uid, "rare", "value never beats rarity")
	eq(Rules.Effect("Legendary", "RAINBOW"), "Mythic", "top mutation lifts legendary")
	eq(Rules.Effect("Legendary", "NORMAL"), "Legendary", "plain legendary")
	eq(Rules.Effect("Secret", "NORMAL"), "Secret", "secret")
	eq(Rules.Effect(nil, nil), "Common", "nil safe")
end)

test("Showcase.Validate is nil-safe and rejects malformed data; Normalize heals it", function()
	local p = profile()
	Showcase.Validate(R, { Showcase = nil })
	addItem(p, "a", itemOf("Common"))
	p.Showcase = { Version = 1, Slots = { ["1"] = "a", ["2"] = "a", ["9"] = "a", [3] = "a", ["4"] = 12 } }
	fails(function() Showcase.Validate(R, p) end)
	Showcase.Normalize(R, p, NOW)
	Showcase.Validate(R, p)
	eq(count(p.Showcase.Slots), 1, "one valid pin left")
	p.Showcase = "broken"
	Showcase.Normalize(R, p, NOW)
	eq(type(p.Showcase.Slots), "table", "rebuilt")
	-- Idempotent.
	Showcase.Normalize(R, p, NOW)
	Showcase.Validate(R, p)
end)

test("snapshot: slots, auto picks, capacity, exhibits and pinned map", function()
	local p = profile()
	addItem(p, "a", itemOf("Rare"))
	addItem(p, "b", itemOf("Common"))
	action(p, "ShowcaseSet", { Slot = 2, Uid = "b" })
	local view = {}
	Showcase.Snapshot(R, p, view, NOW)
	local s = view.Showcase
	eq(s.Capacity, 4, "capacity")
	eq(s.Slots["2"], "b", "pins by case")
	eq(s.Auto["1"], "a", "auto picks by case")
	eq(s.Pinned.b, 2, "pinned map")
	eq(s.Exhibits["1"].Rarity, "Rare", "exhibit rows")
	eq(s.Exhibits["2"].Pinned, true, "exhibit pinned flag")
	eq(Showcase.IsPinned(p, "b"), 2, "IsPinned export")
	eq(Showcase.IsPinned(p, "a"), nil, "auto picks are not pinned")
	eq(Showcase.IsPinned({}, "a"), nil, "nil-safe")
end)

------------------------------------------------------------------------------------------------
-- Collector protection (YardCommerce with a stand-in runtime)
------------------------------------------------------------------------------------------------
local sellProfile
L.Overrides["ServerScriptService/Economy/Runtime"] = {
	Tx = {
		Run = function(_, _keys, fn)
			local copy = R.Copy(sellProfile)
			local ok, result = pcall(fn, { ["p:1"] = copy })
			if ok then sellProfile = copy end
			return ok, result
		end,
	},
	Engine = {
		Authorize = function() end,
		TradeByUser = {},
		Get = function() return sellProfile end,
	},
}
local Commerce = L.Require("ServerScriptService.Economy.YardCommerce")
Commerce.Visit = function() return "yard" end
local player = { UserId = 1 }

test("bulk sale keeps showcased finds and sells the rest", function()
	sellProfile = profile()
	addItem(sellProfile, "pin", itemOf("Rare"))
	addItem(sellProfile, "free", itemOf("Common"))
	action(sellProfile, "ShowcaseSet", { Slot = 1, Uid = "pin" })
	local ok, result = Commerce.BulkSell(player, { Uids = { "pin", "free" } })
	truthy(ok, tostring(result))
	eq(result.Count, 1, "one sold")
	eq(result.SoldUids[1], "free", "the free find")
	eq(result.KeptUids[1], "pin", "the pinned one kept")
	truthy(string.find(result.Message, "showcase", 1, true), "message says why")
	truthy(sellProfile.Items.pin ~= nil and sellProfile.Items.free == nil, "inventory")
end)

test("selling only showcased finds is refused with a clear message", function()
	sellProfile = profile()
	addItem(sellProfile, "pin", itemOf("Rare"))
	action(sellProfile, "ShowcaseSet", { Slot = 1, Uid = "pin" })
	local cash = sellProfile.Cash
	local ok, err = Commerce.BulkSell(player, { Uids = { "pin" } })
	truthy(not ok, "refused")
	truthy(string.find(tostring(err), "MY BEST FINDS", 1, true), tostring(err))
	eq(sellProfile.Cash, cash, "no coins")
	truthy(sellProfile.Items.pin ~= nil, "still owned")
	-- The appraisal (SellQuote) refuses it too; "sell all" skips it.
	local qok, qerr = pcall(Commerce.Request, player, "SellQuote", { Uids = { "pin" } })
	truthy(not qok and string.find(tostring(qerr), "showcase", 1, true), tostring(qerr))
	addItem(sellProfile, "free", itemOf("Common"))
	local aok, quote = Commerce.Request(player, "SellQuote", { All = true })
	truthy(aok, tostring(quote))
	eq(#quote.Rows, 1, "sell all quote skips the pinned find")
	eq(quote.Rows[1].Uid, "free", "only the free find")
	-- A find pinned after the appraisal is refused at the sale.
	local q2ok, quote2 = Commerce.Request(player, "SellQuote", { Uids = { "free" } })
	truthy(q2ok, tostring(quote2))
	action(sellProfile, "ShowcaseSet", { Slot = 2, Uid = "free" })
	local sok, serr = Commerce.Request(player, "NPCSell", { Token = quote2.Token })
	truthy(not sok and string.find(tostring(serr), "showcase", 1, true), tostring(serr))
	truthy(sellProfile.Items.free ~= nil, "not sold")
	-- After taking it out of the showcase it sells.
	action(sellProfile, "ShowcaseClear", { Slot = 1 })
	local bok, bres = Commerce.BulkSell(player, { Uids = { "pin" } })
	truthy(bok and bres.Count == 1, "sold once unpinned")
end)

------------------------------------------------------------------------------------------------
-- Decor catalog
------------------------------------------------------------------------------------------------
test("catalog: 6 categories x 6 items, prices, gates, names", function()
	eq(#Catalog.Categories, 6, "categories")
	local per, ids = {}, {}
	for _, item in ipairs(Catalog.Items) do
		truthy(not ids[item.Id], "unique id " .. item.Id)
		ids[item.Id] = true
		per[item.Category] = (per[item.Category] or 0) + 1
		truthy(type(item.Name) == "string" and item.Name == string.upper(item.Name) and #item.Name <= 24, item.Id .. " name")
		truthy(type(item.RU) == "string" and #item.RU > 0, item.Id .. " RU")
		truthy(R.Int(item.Stage, 1, 9), item.Id .. " stage")
		truthy(({ Common = 1, Uncommon = 1, Rare = 1, Epic = 1, Legendary = 1, Mythic = 1 })[item.Rarity], item.Id .. " rarity")
		if item.Size == "Small" then
			truthy(item.Cash >= 15000 and item.Cash <= 2000000, item.Id .. " small coins")
			truthy(item.Stone >= 20 and item.Stone <= 1000, item.Id .. " small stone")
		else
			truthy(item.Cash >= 150000 and item.Cash <= 150000000, item.Id .. " large coins")
			truthy(item.Stone >= 150 and item.Stone <= 9000, item.Id .. " large stone")
		end
		if item.Rarity == "Mythic" then truthy((item.Bones or 0) > 0, item.Id .. " mythic costs bones") end
	end
	for _, c in ipairs(Catalog.Categories) do
		eq(per[c.Id], 6, c.Id .. " has six")
		truthy(c.RU and c.Name, "category names")
	end
	-- Prices rise with the stage gate inside every category.
	for _, c in ipairs(Catalog.Categories) do
		local last = nil
		for _, item in ipairs(Catalog.Items) do
			if item.Category == c.Id then
				if last then
					truthy(item.Stage >= last.Stage and item.Cash > last.Cash and item.Stone >= last.Stone, item.Id .. " ladder")
				end
				last = item
			end
		end
	end
	eq(#Catalog.Slots, 20, "slots")
	eq(Catalog.SlotCount.Large, 4, "large slots")
	eq(Catalog.SlotCount.Small, 16, "small slots")
end)

test("slots stay clear of routes, kennel pits, the showcase and the mine headframe zone", function()
	for _, slot in ipairs(Catalog.Slots) do
		local w, d = 3.2, 2.6 -- along z, along x'
		if slot.Size == "Large" then w, d = 9.6, 11 end
		local x0, x1, z0, z1 = math.abs(slot.X) - d / 2, math.abs(slot.X) + d / 2, slot.Z - w / 2, slot.Z + w / 2
		truthy(x0 >= 4.6, slot.Id .. " off the walkway")
		truthy(x1 <= 33, slot.Id .. " inside the fence")
		-- kennel pits (x' 6.6..19.4) at z 17.6..30.4 / 33.6..46.4 / 49.6..62.4
		for _, pit in ipairs({ { 17.6, 30.4 }, { 33.6, 46.4 }, { 49.6, 62.4 } }) do
			truthy(not (x1 > 6.6 and x0 < 19.4 and z1 > pit[1] and z0 < pit[2]), slot.Id .. " clear of a pit")
		end
		if slot.X > 0 then
			truthy(not (x1 > 8 and z1 > 49 and z0 < 61), slot.Id .. " clear of the showcase")
			truthy(not (x1 > 8 and x0 < 32 and z1 > -42 and z0 < -30), slot.Id .. " clear of the headframe zone")
		end
	end
	-- Mirrored yards place the same slot on the other side.
	local f = roblox.CFrame.new(10, 1.2, 20)
	local a = Catalog.SlotCFrame(f, 1, Catalog.SlotById.L1).Position
	local b = Catalog.SlotCFrame(f, -1, Catalog.SlotById.L1).Position
	eq(math.floor(a.X - 10 + 0.5), 15, "x' = +14.75")
	eq(math.floor(b.X - 10 + 0.5), -15, "mirrored")
	-- Decorations face the walkway.
	local cf = Catalog.SlotCFrame(roblox.CFrame.new(), 1, Catalog.SlotById.P1)
	truthy(cf.LookVector.X < -0.99, "faces the walkway")
end)

------------------------------------------------------------------------------------------------
-- Decor feature
------------------------------------------------------------------------------------------------
test("DecorBuy charges coins and Stone; not enough Stone is refused without a charge", function()
	local p = profile({ Cash = 100000, Stone = 30 })
	local ok, msg, extra = try(p, "DecorBuy", { Id = "flower_bed", Quote = 15000 })
	truthy(ok, msg)
	action(p, "DecorBuy", { Id = "flower_bed", Quote = 15000 })
	eq(p.Cash, 85000, "coins")
	eq(Resources.Get(p, "Stone"), 10, "stone")
	eq(p.Decor.Owned.flower_bed, 1, "owned")
	-- Second one: only 10 Stone left.
	local before = R.Copy(p)
	fails(function() action(p, "DecorBuy", { Id = "flower_bed" }) end, "Stone")
	p = before
	eq(p.Cash, 85000, "no charge")
	eq(p.Decor.Owned.flower_bed, 1, "no copy")
	R.Validate(p)
	truthy(extra and extra.Paid and extra.Paid.Stone == 20, "reply has the price")
end)

test("DecorBuy: stage gate, coins, bones, quote and the per-id cap", function()
	local p = profile({ Cash = 10 ^ 12, Stone = 100000, Bones = 0, Stage = 1 })
	fails(function() action(p, "DecorBuy", { Id = "gazebo" }) end, "stage 3")
	fails(function() action(p, "DecorBuy", { Id = "nope" }) end, "Unknown")
	fails(function() action(p, "DecorBuy", { Id = 7 }) end, "Unknown")
	fails(function() action(p, "DecorBuy", { Id = "oak_tree", Quote = 1 }) end, "price")
	p.Upgrades.Plot = 8
	fails(function() action(p, "DecorBuy", { Id = "mini_castle" }) end, "Bones")
	p.Bones = 1000
	action(p, "DecorBuy", { Id = "mini_castle" })
	eq(p.Bones, 800, "bones paid")
	local poor = profile({ Cash = 10, Stone = 1000, Stage = 9 })
	fails(function() action(poor, "DecorBuy", { Id = "oak_tree" }) end, "Coins")
	for _ = 1, Catalog.SlotCount.Large - 1 do action(p, "DecorBuy", { Id = "mini_castle" }) end
	eq(p.Decor.Owned.mini_castle, 4, "one per big spot")
	fails(function() action(p, "DecorBuy", { Id = "mini_castle" }) end, "every")
	R.Validate(p)
end)

test("DecorPlace / DecorRemove: counts, slot sizes, invalid input, presence", function()
	local p = profile({ Cash = 10 ^ 9, Stone = 100000, Stage = 9 })
	action(p, "DecorBuy", { Id = "oak_tree" })
	action(p, "DecorBuy", { Id = "gazebo" })
	action(p, "DecorPlace", { Slot = "P1", Id = "oak_tree" })
	eq(p.Decor.Placed.P1, "oak_tree", "placed")
	fails(function() action(p, "DecorPlace", { Slot = "P2", Id = "oak_tree" }) end, "Buy another")
	fails(function() action(p, "DecorPlace", { Slot = "L1", Id = "oak_tree" }) end, "SMALL")
	fails(function() action(p, "DecorPlace", { Slot = "S1", Id = "gazebo" }) end, "BIG")
	fails(function() action(p, "DecorPlace", { Slot = "Z9", Id = "gazebo" }) end, "spot")
	fails(function() action(p, "DecorPlace", { Slot = "L1", Id = "castle" }) end, "Unknown")
	fails(function() action(p, "DecorPlace", { Slot = "L1", Id = "lighthouse" }) end, "Buy another")
	action(p, "DecorPlace", { Slot = "L1", Id = "gazebo" })
	-- Moving the only copy: place it elsewhere after removing it.
	action(p, "DecorRemove", { Slot = "P1" })
	eq(p.Decor.Placed.P1, nil, "removed")
	eq(p.Decor.Owned.oak_tree, 1, "still owned")
	fails(function() action(p, "DecorRemove", { Slot = "P1" }) end, "empty")
	action(p, "DecorPlace", { Slot = "S3", Id = "oak_tree" })
	-- Replacing a slot's decoration returns the old one.
	action(p, "DecorBuy", { Id = "flower_bed" })
	local _, extra = action(p, "DecorPlace", { Slot = "S3", Id = "flower_bed" })
	eq(extra.Replaced, "oak_tree", "replaced")
	action(p, "DecorPlace", { Slot = "S4", Id = "oak_tree" })
	-- Presence: placing and removing need the player in their own yard; buying works anywhere.
	inYard = false
	fails(function() action(p, "DecorRemove", { Slot = "S4" }) end, "yard")
	fails(function() action(p, "DecorPlace", { Slot = "P2", Id = "oak_tree" }) end, "yard")
	fails(function() action(p, "DecorBuy", { Id = "oak_tree", Slot = "P2" }) end, "yard")
	action(p, "DecorBuy", { Id = "oak_tree" })
	inYard = true
	eq(p.Decor.Owned.oak_tree, 2, "bought from anywhere")
	R.Validate(p)
	local view = {}
	Decor.Snapshot(R, p, view, NOW)
	eq(view.Decor.Placed.L1, "gazebo", "snapshot placed")
	eq(view.Decor.Free.oak_tree, 1, "snapshot free copies")
	eq(view.Decor.Stage, 9, "snapshot stage")
	eq(view.Decor.Stone, Resources.Get(p, "Stone"), "snapshot stone")
end)

test("BUY & PLACE in one request", function()
	local p = profile({ Cash = 10 ^ 9, Stone = 100000, Stage = 4 })
	local _, extra = action(p, "DecorBuy", { Id = "lantern_post", Slot = "S2", Quote = 20000 })
	eq(p.Decor.Placed.S2, "lantern_post", "placed")
	eq(extra.Slot, "S2", "reply")
	local before = R.Copy(p)
	fails(function() action(p, "DecorBuy", { Id = "candy_corner", Slot = "S1" }) end, "BIG")
	eq(before.Cash, p.Cash, "no charge on a wrong spot")
	R.Validate(p)
end)

test("Decor.Validate is nil-safe; Normalize heals excess placements and bad entries", function()
	Decor.Validate(R, { Decor = nil })
	local p = profile()
	p.Decor = { Version = 1, Owned = { oak_tree = 1, future_item = 3, bad = -2, [5] = 1, nan = 0 / 0 }, Placed = { P1 = "oak_tree", P2 = "oak_tree", L1 = "oak_tree", XX = "oak_tree" } }
	fails(function() Decor.Validate(R, p) end)
	Decor.Normalize(R, p, NOW)
	Decor.Validate(R, p)
	eq(p.Decor.Owned.future_item, 3, "unknown ids from a newer build are kept")
	eq(p.Decor.Owned.bad, nil, "negative dropped")
	eq(p.Decor.Owned.nan, nil, "NaN dropped")
	local placed = 0
	for _, id in pairs(p.Decor.Placed) do if id == "oak_tree" then placed += 1 end end
	eq(placed, 1, "one copy placed")
	eq(p.Decor.Placed.L1, nil, "a small decoration never stays on a big spot")
	eq(p.Decor.Placed.XX, nil, "unknown slot dropped")
	Decor.Normalize(R, p, NOW)
	Decor.Validate(R, p)
	p.Decor = 5
	Decor.Normalize(R, p, NOW)
	eq(type(p.Decor.Owned), "table", "rebuilt")
end)

------------------------------------------------------------------------------------------------
-- Decor models (Forge recipes)
------------------------------------------------------------------------------------------------
local Models = L.Require("ReplicatedStorage.Decor.DecorModels")
-- Extent of the parts of a model (only parts whose lowest point is below `belowY`, or at/above it).
local function extent(model, below, belowY)
	local lo, hi
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local plo, phi
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local q = d.CFrame:PointToWorldSpace(d.Size * roblox.Vector3.new(x, y, z) / 2)
						plo = plo and plo:Min(q) or q
						phi = phi and phi:Max(q) or q
					end
				end
			end
			if (below and plo.Y < belowY) or (not below and plo.Y >= belowY) then
				lo = lo and lo:Min(plo) or plo
				hi = hi and hi:Max(phi) or phi
			end
		end
	end
	return lo, hi
end

test("every decoration has a model inside its budgets and slot footprint", function()
	local problems = {}
	for _, item in ipairs(Catalog.Items) do
		local model = Models.Build(item.Id)
		if not model then
			table.insert(problems, item.Id .. ": no model")
		else
			local parts, lights = 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then parts += 1 end
				if d:IsA("Light") then
					lights += 1
					if not d:IsA("PointLight") then table.insert(problems, item.Id .. ": not a PointLight") end
				end
			end
			local budget = item.Size == "Small" and 40 or 120
			if parts > budget then table.insert(problems, string.format("%s: %d parts > %d", item.Id, parts, budget)) end
			if item.Category == "Lighting" then
				if lights ~= 1 then table.insert(problems, item.Id .. ": lighting needs exactly one PointLight") end
			elseif lights > 0 then
				table.insert(problems, item.Id .. ": only lighting may carry a light")
			end
			local function check(lo, hi, w, d, what)
				if not lo then return end
				local tol = 0.06
				if lo.X < -w / 2 - tol or hi.X > w / 2 + tol or lo.Z < -d / 2 - tol or hi.Z > d / 2 + tol then
					table.insert(problems, string.format("%s: %s X %.2f..%.2f Z %.2f..%.2f (limit %.1f x %.1f)", item.Id, what, lo.X, hi.X, lo.Z, hi.Z, w, d))
				end
			end
			if item.Size == "Small" then
				local lo, hi = extent(model, true, 3)
				check(lo, hi, 3.2, 2.6, "ground")
				lo, hi = extent(model, false, 3)
				check(lo, hi, 4.0, 3.4, "top")
			else
				local lo, hi = extent(model, true, math.huge)
				check(lo, hi, 9.6, 11, "footprint")
			end
			-- Nothing collides on small pieces; big ones collide only on a few base / wall parts.
			local solid = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then solid += 1 end
			end
			if item.Size == "Small" and solid > 0 then table.insert(problems, item.Id .. ": small pieces never collide") end
			if solid > 12 then table.insert(problems, item.Id .. ": too many collidable parts") end
			-- LOD 1 builds too and never has more parts.
			local low = Models.Build(item.Id, 1)
			truthy(low and Forge.CountParts(low) <= parts, item.Id .. " lod")
		end
	end
	truthy(#problems == 0, table.concat(problems, "\n"))
	truthy(Models.Get("oak_tree") ~= Models.Get("oak_tree"), "Get returns clones")
end)

------------------------------------------------------------------------------------------------
-- Localization
------------------------------------------------------------------------------------------------
test("every decoration, category and showcase word has Russian", function()
	truthy(type(Locale.Exact) == "table" and type(Locale.Patterns) == "table", "dictionary shape")
	for _, item in ipairs(Catalog.Items) do
		eq(Locale.Exact[item.Name], item.RU, item.Id)
	end
	for _, c in ipairs(Catalog.Categories) do
		eq(Locale.Exact[c.Name], c.RU, c.Id)
	end
	for _, word in ipairs({ "EDIT SHOWCASE", "DECORATE", "MY BEST FINDS", "AUTO", "REMOVE", "BUY & PLACE" }) do
		truthy(Locale.Exact[word], word)
	end
	-- Short generic words keep their plot meaning only inside the two windows: the global
	-- dictionary (FREE = "БЕСПЛАТНО", OWNED = "КУПЛЕНО"...) must not be overridden.
	for _, word in ipairs({ "PLACE", "OWNED", "BIG", "SMALL", "FREE" }) do
		truthy(Locale.UI[word], "UI " .. word)
		eq(Locale.Exact[word], nil, "global " .. word)
	end
	local text = "12.5 kg"
	local hit = false
	for _, rule in ipairs(Locale.Patterns) do
		local out, n = string.gsub(text, rule[1], rule[2])
		if n > 0 then hit = out == "12.5 кг" break end
	end
	truthy(hit, "weight pattern")
end)

print(string.format("plot_cosmetics: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plot_cosmetics tests failed")
end
