--!nocheck
--!nolint
-- Economy.ItemProtection and its users: collector sales (YardCommerce BulkSell / SellQuote / NPCSell,
-- Snapshot.SellableItems / ProtectedItems, all in the 'Sell' context) and transfers (ItemRules.Get(p, uid, true): trade offers, market
-- listings, lab catalysts): lune run tests/item_protection.luau
-- Runs the REAL Runtime / YardCommerce / Engine on tests/lib/server_world (memory store); the yard
-- visit check is replaced by a stub (no world in Lune).
local process = require("@lune/process")
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
local function fails(fn, pattern)
	local ok, err = pcall(fn)
	truthy(not ok, "expected an error matching " .. tostring(pattern))
	truthy(tostring(err):find(pattern, 1, true), "error '" .. tostring(err) .. "' lacks '" .. pattern .. "'")
end

local SHOWCASE = "This find is on your showcase"
local FAVORITE = "Favorite finds are kept; unfavorite to sell"
-- A world with player `uid` owning finds: plain ones, a favourite and one "on the showcase".
local function shop(uid)
	local W = World.new()
	local L = W.L
	local I = L.Require("ServerScriptService/Economy/ItemRules")
	local Protection = L.Require("ServerScriptService/Economy/ItemProtection")
	local Commerce = L.Require("ServerScriptService/Economy/YardCommerce")
	local Defs = L.Require("ReplicatedStorage/DogEconomy/ItemDefinitions")
	local yard = { Name = "TestYard" }
	Commerce.Visit = function()
		return yard
	end
	local showcase = {}
	-- What a showcase feature registers (one line).
	Protection.Register("Showcase", function(_, itemUid)
		return showcase[itemUid] and SHOWCASE or nil
	end)
	local player = W.Join(uid)
	local function rng()
		return 0.42
	end
	W.Edit(uid, function(p)
		local def = Defs.rusty_spoon
		for _, itemUid in { "plain1", "plain2", "plain3", "fav", "shown" } do
			I.Mint(p, def, def.BaseDropChance, itemUid, L.Now, rng, {})
		end
		p.Items.fav.Favorite = true
		p.RecordJobs = {}
	end)
	showcase.shown = true
	W.Runtime.Refresh(player)
	return W, player, { I = I, Protection = Protection, Commerce = Commerce, Showcase = showcase }
end

test("Register, Reason, IsProtected: contexts, ignore, order, replacement, fail closed", function()
	local W, _, M = shop(1)
	local P, p = M.Protection, W.Profile(1)
	eq(P.Reason(p, "shown"), SHOWCASE, "every context")
	eq(P.Reason(p, "shown", "Transfer"), SHOWCASE)
	eq(P.Reason(p, "plain1", "Sell"), nil)
	eq(P.Reason(p, "missing", "Sell"), nil, "no find, nothing to protect")
	eq(P.Reason(nil, "shown"), nil)
	truthy(P.IsProtected(p, "shown", "Sell"))
	eq(P.IsProtected(p, "shown", "Sell", { Showcase = true }), false, "ignored by name")
	-- Favorite: sales only.
	eq(P.Reason(p, "fav", "Sell"), FAVORITE)
	eq(P.Reason(p, "fav", "Transfer"), nil)
	eq(P.Reason(p, "fav", "Sell", { Favorite = true }), nil)
	eq(P.Contexts.Bulk, nil, "one sale context: the protocol cannot tell one find from a bulk sale")
	-- Context-limited protectors and replacement.
	P.Register("Lending", function(_, uid)
		return uid == "plain3" and "Lent to a friend" or nil
	end, { Transfer = true })
	eq(P.Reason(p, "plain3", "Transfer"), "Lent to a friend")
	eq(P.Reason(p, "plain3", "Sell"), nil)
	P.Register("Lending", function()
		return nil
	end)
	eq(P.Reason(p, "plain3", "Transfer"), nil, "re-registering replaces")
	-- The first reason in registration order wins.
	M.Showcase.fav = true
	eq(P.Reason(p, "fav", "Sell"), FAVORITE)
	M.Showcase.fav = nil
	-- A broken protector protects.
	P.Register("Broken", function()
		error("bug")
	end)
	eq(P.Reason(p, "plain1", "Sell"), "This find is protected (Broken)")
	fails(function()
		P.Register("Bad", function() end, { Nowhere = true })
	end, "Unknown protection context")
	fails(function()
		P.Register("", function() end)
	end, "ItemProtection.Register")
end)

test("BulkSell skips favourites and protected finds and counts them", function()
	local W, player = shop(1)
	local cash = W.Profile(1).Cash
	local ok, result = W.Request(player, "BulkSell", { Uids = { "plain1", "fav", "shown" } })
	truthy(ok, tostring(result))
	eq(#result.SoldUids, 1)
	eq(result.SoldUids[1], "plain1")
	eq(result.SkippedProtected, 2)
	eq(result.StatePatch.SoldUids[1], "plain1", "the patch lists only what was sold")
	local p = W.Profile(1)
	eq(p.Items.plain1, nil)
	truthy(p.Items.fav and p.Items.shown, "kept")
	truthy(p.Cash > cash, "paid")
end)

test("IncludeFavorites sells favourites, never other protected finds", function()
	local W, player = shop(1)
	local ok, result = W.Request(player, "BulkSell", { Uids = { "fav", "shown", "plain1" }, IncludeFavorites = true })
	truthy(ok, tostring(result))
	eq(#result.SoldUids, 2)
	eq(result.SkippedProtected, 1)
	eq(W.Profile(1).Items.fav, nil, "favourite sold on request")
	truthy(W.Profile(1).Items.shown, "the showcase find stays")
end)

test("a bulk sale of protected finds only is refused with the reason", function()
	local W, player = shop(1)
	local ok, result = W.Request(player, "BulkSell", { Uids = { "shown" } })
	eq(ok, false)
	eq(result, SHOWCASE)
	ok, result = W.Request(player, "BulkSell", { Uids = { "fav" } })
	eq(ok, false)
	eq(result, FAVORITE)
	truthy(W.Profile(1).Items.fav and W.Profile(1).Items.shown)
end)

test("ValidBulkArgs accepts IncludeFavorites only as a boolean", function()
	local W, player, M = shop(1)
	local valid = M.Commerce.ValidBulkArgs
	truthy(valid({ Uids = { "a" } }))
	truthy(valid({ Uids = { "a" }, IncludeFavorites = false }))
	truthy(valid({ Uids = { "a" }, IncludeFavorites = true }))
	eq(valid({ Uids = { "a" }, IncludeFavorites = "yes" }), false)
	eq(valid({ Uids = { "a" }, Extra = 1 }), false)
	local ok, result = W.Request(player, "BulkSell", { Uids = { "plain1" }, IncludeFavorites = 1 })
	eq(ok, false)
	eq(result, "Invalid request")
end)

test("SellQuote leaves protected finds out; NPCSell re-checks at the sale", function()
	local W, player, M = shop(1)
	local ok, quote = W.Request(player, "SellQuote", { All = true })
	truthy(ok, tostring(quote))
	eq(#quote.Rows, 3, "the three plain finds")
	eq(quote.SkippedProtected, 2)
	for _, row in quote.Rows do
		truthy(row.Uid:match("^plain"), row.Uid)
	end
	ok, quote = W.Request(player, "SellQuote", { Uids = { "plain2", "fav" } })
	truthy(ok, tostring(quote))
	eq(#quote.Rows, 1)
	eq(quote.SkippedProtected, 1)
	ok, quote = W.Request(player, "SellQuote", { Uids = { "plain2", "fav" }, IncludeFavorites = true })
	truthy(ok, tostring(quote))
	eq(#quote.Rows, 2, "favourites on request")
	ok, quote = W.Request(player, "SellQuote", { Uids = { "shown" } })
	eq(ok, false)
	eq(quote, SHOWCASE)
	-- Protected after the appraisal: the sale is refused and nothing is sold.
	ok, quote = W.Request(player, "SellQuote", { Uids = { "plain2" } })
	truthy(ok, tostring(quote))
	M.Showcase.plain2 = true
	local sold, result = W.Request(player, "NPCSell", { Token = quote.Token })
	eq(sold, false)
	eq(result, SHOWCASE)
	truthy(W.Profile(1).Items.plain2, "kept")
	M.Showcase.plain2 = nil
	sold, result = W.Request(player, "NPCSell", { Token = quote.Token })
	truthy(sold, tostring(result))
	eq(W.Profile(1).Items.plain2, nil)
end)

test("CanSell and the snapshot match what a sale does", function()
	local W, player, M = shop(1)
	local p = W.Profile(1)
	local can, why = M.Commerce.CanSell(p, "plain1")
	eq(can, true)
	eq(why, nil)
	can, why = M.Commerce.CanSell(p, "fav")
	eq(can, false)
	eq(why, FAVORITE)
	eq(M.Commerce.CanSell(p, "fav", { Favorite = true }), true, "IncludeFavorites")
	can, why = M.Commerce.CanSell(p, "shown", { Favorite = true })
	eq(can, false)
	eq(why, SHOWCASE)
	can, why = M.Commerce.CanSell(p, "missing")
	eq(can, false)
	eq(why, nil, "not owned: no protection reason")
	local ok, snapshot = W.Request(player, "Snapshot", {})
	truthy(ok, tostring(snapshot))
	truthy(snapshot.SellableItems.plain1 and snapshot.SellableItems.plain2, "sellable")
	eq(snapshot.SellableItems.fav, nil, "a sale without IncludeFavorites keeps it")
	eq(snapshot.SellableItems.shown, nil)
	eq(snapshot.ProtectedItems.fav, FAVORITE, "why it stays")
	eq(snapshot.ProtectedItems.shown, SHOWCASE)
	eq(snapshot.ProtectedItems.plain1, nil)
	-- Each one-find SELL button of the old clients sends exactly this, and the server agrees.
	local sold, result = W.Request(player, "BulkSell", { Uids = { "fav" } })
	eq(sold, false)
	eq(result, snapshot.ProtectedItems.fav)
	sold, result = W.Request(player, "BulkSell", { Uids = { "plain1" } })
	truthy(sold and snapshot.SellableItems.plain1, tostring(result))
end)

test("transfers refuse protected finds with the protector's reason", function()
	local W, player, M = shop(1)
	local p = W.Profile(1)
	fails(function()
		M.I.Get(p, "shown", true)
	end, SHOWCASE)
	eq(M.I.Get(p, "fav", true).ItemUid, "fav", "favourites can still be offered")
	eq(M.I.Get(p, "shown", false).ItemUid, "shown", "reading is not a transfer")
	-- An explicit player override (Trade 2.0 toggles) skips the named protectors only.
	eq(M.I.Get(p, "shown", true, { Showcase = true }).ItemUid, "shown")
	fails(function()
		M.I.Get(p, "shown", true, { Favorite = true })
	end, SHOWCASE)
	-- Market listing.
	fails(function()
		W.Engine.Market:Create(1, { Mode = "BuyNow", Price = 100, Kind = "Item", Uid = "shown" })
	end, SHOWCASE)
	-- Trade offer (both players past the trade level).
	local other = W.Join(2)
	local level = W.L.Require("ReplicatedStorage/DogEconomy/Config").XPForLevel(6)
	for _, uid in { 1, 2 } do
		W.Edit(uid, function(q)
			q.XP = level
			W.Rules.UpdateLevel(q)
		end)
		W.Runtime.Refresh(W.List[uid])
	end
	truthy(W.Request(player, "TradeRequest", { Target = 2 }))
	truthy(W.Request(other, "Trade", { Action = "Accept" }))
	local ok, result = W.Request(player, "Trade", { Action = "Offer", Dogs = {}, Items = { "shown" }, Cash = 0 })
	eq(ok, false)
	eq(result, SHOWCASE)
	ok, result = W.Request(player, "Trade", { Action = "Offer", Dogs = {}, Items = { "plain1" }, Cash = 0 })
	truthy(ok, tostring(result))
	-- Lab catalyst (LabRules reads catalysts with ItemRules.Get(p, uid, true)).
	local Lab = W.L.Require("ServerScriptService/Economy/LabRules")
	fails(function()
		Lab.Preview(W.Profile(1), { Procedure = "Targeting", Uids = {}, Items = { "shown" } }, W.L.Now)
	end, SHOWCASE)
end)

print(("item_protection: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
