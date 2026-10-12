--!nocheck
--!nolint
-- Server hot-path fixes of the overhaul foundation (docs/OVERHAUL.md), on the REAL Runtime
-- (tests/lib/server_world, memory store): lune run tests/hot_paths.luau
--  (a) InventoryRevision moves only when an inventory view's data changes (InventorySignature);
--  (b) LabInfo / LabPreview (read-only) skip Runtime.Refresh;
--  (c) DogInventory: attributes written and OwnerHistory JSON-encoded only when a dog changed;
--  (d) the OfflineEarningsRevision mark the idle HUD notice (Modules.Menus) waits on;
--  (e) Join retries transient failures (busy profile, DataStore errors) before kicking.
local task = require("@lune/task")
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
local function rng()
	return 0.42
end

-- A joined player with three dogs (one in a kennel) and two finds.
local function yard()
	local W = World.new()
	local R, L = W.Rules, W.L
	local I = L.Require("ServerScriptService/Economy/ItemRules")
	local Defs = L.Require("ReplicatedStorage/DogEconomy/ItemDefinitions")
	local player = W.Join(1)
	W.Edit(1, function(p)
		for i, id in { "Breadog", "Sausagedog", "Breadog" } do
			R.Mint(p, id, "dog" .. i, {}, L.Now, rng, "Test", "Normal", true)
		end
		p.Dogs.dog1.AssignedSlot = "DigSlot_1"
		p.Dogs.dog1.State = "Digging"
		for _, uid in { "find1", "find2" } do
			I.Mint(p, Defs.rusty_spoon, 0.16, uid, L.Now, rng, {})
		end
		p.RecordJobs = {}
	end)
	W.Runtime.Refresh(player)
	local function revision()
		return player:GetAttribute("InventoryRevision")
	end
	local function change(fn)
		local before = revision()
		W.Edit(1, fn)
		W.Runtime.Refresh(player)
		return revision() - before
	end
	return W, player, change, revision
end

-- (a) ---------------------------------------------------------------------------------------------
test("digging, income and timers never move InventoryRevision", function()
	local W, player, change = yard()
	eq(change(function(p)
		local d = p.Dogs.dog1
		d.NextWorkAt += 30
		d.WorkSequence += 1
		d.MasteryXP += 2
		d.LastYield = 120
		d.LastAbility = "FoodFinder"
		d.LastAbilityAt = W.L.Now
		d.DryStreak = 3
		p.Cash += 500
		p.XP += 40
		p.LastDig = W.L.Now
		p.Pity = 4
	end), 0)
	eq(change(function() end), 0, "an idle refresh")
	truthy(player:GetAttribute("InventoryRevision") >= 1, "set at join")
end)

test("every inventory change moves InventoryRevision once", function()
	local W, _, change = yard()
	local R, L = W.Rules, W.L
	local I = L.Require("ServerScriptService/Economy/ItemRules")
	local Defs = L.Require("ReplicatedStorage/DogEconomy/ItemDefinitions")
	local cases = {
		{ "a new find", function(p) I.Mint(p, Defs.rusty_spoon, 0.16, "find3", L.Now, rng, {}) end },
		{ "a find leaves", function(p) p.Items.find3 = nil end },
		{ "favourite", function(p) p.Items.find1.Favorite = true end },
		{ "a record flag", function(p) p.Items.find1.RecordAtCreation.Server = true end },
		{ "record check pending", function(p) p.RecordJobs.rusty_spoon = { ItemUid = "find2", ItemId = "rusty_spoon" } end },
		{ "record check done", function(p) p.RecordJobs = {} end },
		{ "a new dog", function(p) R.Mint(p, "Breadog", "dog4", {}, L.Now, rng, "Test", "Normal", true) end },
		{ "a dog leaves", function(p) p.Dogs.dog4 = nil end },
		{ "kennel", function(p) p.Dogs.dog2.AssignedSlot = "DigSlot_2"; p.Dogs.dog2.State = "Digging" end },
		{ "variant", function(p) p.Dogs.dog3.Variant = "Golden" end },
		{ "lock", function(p) p.Dogs.dog3.Locked = true end },
		{ "dog favourite", function(p) p.Dogs.dog3.Favorite = true end },
		{ "mastery level", function(p) p.Dogs.dog1.Mastery = 5 end },
		{ "ascension", function(p) p.Dogs.dog1.AscensionLevel = 1 end },
		{ "equipment", function(p) p.Equipment.Rev += 1 end },
		{ "display dog", function(p) p.DisplayDogs["1"] = "dog3" end },
		{ "lucky credits", function(p) p.LuckyCredits.Rare = 2 end },
		{ "a lucky block", function(p) p.OwnedBlocks.b1 = { Tier = "Rare", State = "Inventory" } end },
		{ "the block is placed", function(p) p.OwnedBlocks.b1.State = "Placed"; p.OwnedBlocks.b1.Slot = 1 end },
		{ "a layer", function(p) p.UnlockedLayers["2"] = true end },
		{ "storage upgrade", function(p) p.Upgrades.Storage = 1 end },
		{ "old loot", function(p) p.Loot.Bone = { Value = 5, Count = 2 } end },
	}
	for _, case in cases do
		eq(change(case[2]), 1, case[1])
	end
	-- Two refreshes of the same change: one bump.
	eq(change(function() end), 0, "nothing new")
end)

test("a bulk sale bumps InventoryRevision once (RefreshSale), not again on the next refresh", function()
	local W, player, _, revision = yard()
	local Commerce = W.L.Require("ServerScriptService/Economy/YardCommerce")
	Commerce.Visit = function()
		return true
	end
	local before = revision()
	local ok, result = W.Request(player, "BulkSell", { Uids = { "find1" } })
	truthy(ok, tostring(result))
	eq(revision(), before + 1)
	W.Runtime.Refresh(player)
	eq(revision(), before + 1)
	-- Old loot only: nothing an inventory shows.
	W.Edit(1, function(p) p.Loot.Bone = { Value = 5, Count = 1 } end)
	W.Runtime.Refresh(player)
	local afterLoot = revision()
	ok, result = W.Request(player, "SellLoot", {})
	truthy(ok, tostring(result))
	eq(revision(), afterLoot + 1, "the loot stack left")
end)

test("InventorySignature in isolation: first call, removals, unknown shapes", function()
	local W = World.new()
	local S = W.L.Require("ServerScriptService/Economy/InventorySignature")
	local s = S.new()
	local p = { Items = { a = { ItemId = "x", Favorite = false } }, Dogs = {}, RecordJobs = {} }
	eq(s:Changed(p), true, "first call")
	eq(s:Changed(p), false)
	p.Items.b = { ItemId = "x" }
	p.Items.a = nil
	eq(s:Changed(p), true, "same count, other uid")
	eq(s:Changed(p), false)
	eq(s:Changed({}), true, "everything gone")
	eq(s:Changed({}), false)
	eq(s:Changed({ Items = "bad", Dogs = 5, OwnedBlocks = { x = "y" } }), true, "malformed data never errors")
end)

-- (b) ---------------------------------------------------------------------------------------------
test("LabInfo and LabPreview skip the refresh, LabCommit does not", function()
	local W, player = yard()
	local projects = 0
	local project = W.Runtime.Project
	W.Runtime.Project = function(...)
		projects += 1
		return project(...)
	end
	W.L.Overrides["ServerScriptService/Economy/LabService"] = {
		Request = function(_, action)
			return true, { Message = action }
		end,
	}
	for _, action in { "LabInfo", "LabPreview" } do
		local ok, result = W.Request(player, action, {})
		truthy(ok, tostring(result))
		eq(result.StateSnapshot, nil, action .. " carries no snapshot")
	end
	eq(projects, 0, "read-only lab requests")
	local ok = W.Request(player, "LabCommit", {})
	truthy(ok)
	eq(projects, 1, "a commit refreshes")
	W.L.Overrides["ServerScriptService/Economy/LabService"] = nil
	W.Runtime.Project = project
end)

-- (c) ---------------------------------------------------------------------------------------------
test("DogInventory writes only what changed and encodes OwnerHistory only when it grows", function()
	local W, player = yard()
	local R = W.Rules
	local inventory = player:FindFirstChild("DogInventory")
	local entry = inventory:FindFirstChild("dog2")
	eq(entry.Value, "Sausagedog")
	eq(entry:GetAttribute("DogId"), "Sausagedog")
	eq(entry:GetAttribute("OwnerUserId"), 1)
	-- An unchanged dog is not written again: a marker on its entry survives a refresh.
	entry:SetAttribute("Mastery", -1)
	local encodes = W.JsonEncodes
	W.Runtime.Refresh(player)
	eq(entry:GetAttribute("Mastery"), -1, "not rewritten")
	eq(W.JsonEncodes, encodes, "no OwnerHistory encode")
	-- A changed field is written; the history is encoded again only for the dog that moved.
	W.Edit(1, function(p)
		p.Dogs.dog2.Mastery = 7
		p.Dogs.dog1.NextWorkAt += 10
		R.Transfer(p.Dogs.dog3, p, W.L.Now, "Test")
	end)
	W.Runtime.Refresh(player)
	eq(entry:GetAttribute("Mastery"), 7)
	eq(inventory:FindFirstChild("dog1"):GetAttribute("NextWorkAt"), W.Profile(1).Dogs.dog1.NextWorkAt)
	eq(W.JsonEncodes, encodes + 1, "one history changed")
	-- A dog that leaves loses its entry; a new one is written in full.
	W.Edit(1, function(p)
		p.Dogs.dog2 = nil
		R.Mint(p, "Breadog", "dog9", {}, W.L.Now, rng, "Test", "Shiny", true)
	end)
	W.Runtime.Refresh(player)
	eq(inventory:FindFirstChild("dog2"), nil)
	local fresh = inventory:FindFirstChild("dog9")
	truthy(fresh, "new entry")
	eq(fresh:GetAttribute("Variant"), "Shiny")
	eq(W.JsonEncodes, encodes + 2)
end)

-- (d) ---------------------------------------------------------------------------------------------
test("OfflineEarningsRevision moves on a claim or a return, not on refreshes", function()
	local W, player = yard()
	local mark = player:GetAttribute("OfflineEarningsRevision")
	truthy(type(mark) == "string", "published at join")
	W.Edit(1, function(p) p.Cash += 10 end)
	W.Runtime.Refresh(player)
	eq(player:GetAttribute("OfflineEarningsRevision"), mark)
	W.Edit(1, function(p) p.OfflineEarnings.Revision += 1 end)
	W.Runtime.Refresh(player)
	truthy(player:GetAttribute("OfflineEarningsRevision") ~= mark, "a claim")
	mark = player:GetAttribute("OfflineEarningsRevision")
	W.Edit(1, function(p) p.OfflineEarnings.LastReturnAt = W.L.Now + 1 end)
	W.Runtime.Refresh(player)
	truthy(player:GetAttribute("OfflineEarningsRevision") ~= mark, "a return")
end)

-- (e) ---------------------------------------------------------------------------------------------
test("JoinRetryable: transient failures only", function()
	local W = World.new()
	local retryable = W.Runtime.JoinRetryable
	for _, message in {
		"Account is active on another server. Retry shortly.",
		"Player data is active on another server; retry later",
		"Account is busy; retry shortly",
		"Account busy; please retry",
		"DataStore unavailable: 502: API Services rejected request",
		"Storage unavailable. Operation pending; retry the same request.",
		"Transaction pending; retry with the same request ID",
		"Transaction expired before commit",
		"Saving your progress; retry shortly",
	} do
		truthy(retryable(message), message)
	end
	for _, message in { "Invalid inventory record", "Profile owner mismatch", "Item hard cap exceeded", "Saved profile is missing; refusing to resync" } do
		eq(retryable(message), false, message)
	end
end)

-- The real PlayerAdded join of Runtime.Start (economy loop running), with fast retries.
local live = World.new({ Start = true })
live.Runtime.JoinRetry.Delay = 0.05
local joins = 0
local join = live.Engine.Join
live.Engine.Join = function(...)
	joins += 1
	return join(...)
end
local function arrive(uid)
	joins = 0
	local player = live.AddPlayer(uid)
	live.PlayersService.PlayerAdded:Fire(player)
	local deadline = os.clock() + 5
	while not live.Runtime.Loaded[uid] and not player.Kicked and os.clock() < deadline do
		task.wait(0.02)
	end
	return player
end

test("a join that hits a DataStore failure is retried, not kicked", function()
	local store = live.Store
	local update = store.Update
	local failures = 2 -- the journal write and its abort: one whole attempt
	store.Update = function(self, k, fn)
		if failures > 0 and k:sub(1, 3) == "tx:" then
			failures -= 1
			error("DataStore 502 (injected)")
		end
		return update(self, k, fn)
	end
	local player = arrive(41)
	store.Update = update
	eq(player.Kicked, nil, "not kicked")
	truthy(live.Runtime.Loaded[41], "loaded")
	eq(joins, 2, "one retry")
	eq(player:GetAttribute("EconomyReady"), true)
end)

test("a busy profile is waited for (bounded), a broken one kicks at once", function()
	-- Another live server holds the session: every attempt is used, then the kick.
	live.Store.Data["p:42"] = { Revision = 1, Value = { UserId = 42, MegaResetVersion = 1, Session = { Id = "other-server", Expires = live.L.Now + 600 } } }
	local busy = arrive(42)
	truthy(busy.Kicked, "kicked in the end")
	eq(joins, live.Runtime.JoinRetry.Attempts)
	-- A saved profile that cannot validate: no retries.
	live.Store.Data["p:43"] = { Revision = 1, Value = { UserId = 43, MegaResetVersion = 1, Dogs = { x = { DogUid = "x", DogId = "NoSuchDog", OwnerUserId = 43 } } } }
	local broken = arrive(43)
	truthy(broken.Kicked and broken.Kicked:find("Invalid inventory record", 1, true), tostring(broken.Kicked))
	eq(joins, 1)
end)

print(("hot_paths: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
