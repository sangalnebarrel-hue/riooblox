--!nocheck
-- TRADE SYSTEM 2.0: invitations, sessions, offer rules, the safety flow, the atomic swap, pruning,
-- the value check and the trade window's texts.
--   lune run tests/trade.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): Economy.Engine (trade section),
-- Transactions, Rules, ItemRules, DogEconomy.TradeRules and Localization.Trade.
local fs = require("@lune/fs")
local L = require("./lib/economy_env")
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end, Current = function() return 1 end }
local paidAllowed = false
L.Overrides["ServerScriptService/Economy/PaidItemPolicy"] = { Allowed = function() return paidAllowed end }
local C = L.Require("ReplicatedStorage.DogEconomy.Config")
local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")
local Tx = L.Require("ServerScriptService.Economy.Transactions")
local Engine = L.Require("ServerScriptService.Economy.Engine")
local TR = L.Require("ReplicatedStorage.DogEconomy.TradeRules")
local Valuation = L.Require("ReplicatedStorage.ItemValuation")
local Dict = L.Require("ReplicatedStorage.Localization.Trade")

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

------------------------------------------------------------------------------------------------
-- A real engine over a RAM store (the pattern of tests/upgrade_tree.luau)
------------------------------------------------------------------------------------------------
local T0 = 1760000000
local function world()
	local w = { Now = T0, Online = {}, Pushes = {} }
	L.Time = w.Now
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
	local clock = function() return w.Now end
	w.Tx = Tx.new(store, clock, guid, {})
	w.Engine = Engine.new(w.Tx, {
		Now = clock, Guid = guid, Random = function() return 0.5 end, Session = "S1",
		Connected = function(id) return w.Online[id] ~= false end,
	})
	w.Engine.OnTrade = function(id, event)
		w.Pushes[id] = w.Pushes[id] or {}
		table.insert(w.Pushes[id], R.Copy(event))
	end
	function w.Advance(seconds)
		w.Now += seconds
		L.Time = w.Now
	end
	function w.Last(id, kind)
		local list = w.Pushes[id] or {}
		for i = #list, 1, -1 do
			if kind == nil or list[i].Kind == kind then return list[i] end
		end
		return nil
	end
	function w.Clear() w.Pushes = {} end
	-- Joins `id` and edits the loaded profile (level 10, cash) inside a transaction.
	function w.Join(id, edit, level)
		local ok, err = w.Engine:Join(id)
		truthy(ok, "join " .. id .. ": " .. tostring(err))
		w.Edit(id, function(p)
			p.Cash = 1000000
			p.XP = C.XPForLevel(level or 10)
			R.UpdateLevel(p)
			if edit then edit(p) end
		end)
	end
	function w.Edit(id, fn)
		local ok, err = w.Tx:Run({ "p:" .. id }, function(v)
			fn(v["p:" .. id])
			R.Validate(v["p:" .. id])
			return true
		end)
		truthy(ok, "edit " .. id .. ": " .. tostring(err))
	end
	function w.Profile(id) return w.Tx:Read("p:" .. id) end
	function w.Trade(id, action, args)
		local a = args or {}
		return w.Engine:Trade(id, action, a)
	end
	function w.View(id) return w.Engine:TradeView(id) end
	return w
end

local function dog(p, uid, dogId, variant)
	R.Mint(p, dogId or "Breadog", uid, {}, L.Time, function() return 0.5 end, "Test", variant or "Normal")
	return p.Dogs[uid]
end
local ITEM_IDS = {}
for id in pairs(I.Definitions) do table.insert(ITEM_IDS, id) end
table.sort(ITEM_IDS)
local function item(p, uid, itemId, mutation, weight)
	local def = I.Definitions[itemId or "rusty_spoon"]
	local x = {
		ItemUid = uid, ItemId = def.Id, DisplayName = def.DisplayName, Depth = def.Depth, Class = def.Class, SetId = def.SetId,
		BaseDropChance = def.BaseDropChance, BaseWeightKg = def.BaseWeightKg, WeightKg = def.BaseWeightKg * (weight or 1),
		WeightMultiplier = weight or 1, WeightTier = "Normal", TierIndex = 3, Mutation = mutation or "NORMAL",
		FoundAt = L.Time, FoundByUserId = p.UserId, OriginalFinderUserId = p.UserId, OwnerUserId = p.UserId,
		Tradeable = true, RecordAtCreation = { Personal = false, Server = false, Global = false }, Favorite = false,
	}
	x.SellValue = Valuation.Price(x)
	p.Items[uid] = x
	return x
end

-- 1 and 2 in an accepted session, both with a few dogs and finds.
local function session()
	local w = world()
	w.Join(1, function(p)
		for i = 1, 3 do dog(p, "a" .. i) end
		for i = 1, 3 do item(p, "ai" .. i) end
	end)
	w.Join(2, function(p)
		for i = 1, 3 do dog(p, "b" .. i, "KingCorgi") end
		for i = 1, 2 do item(p, "bi" .. i, "lost_key", "GOLDEN") end
	end)
	w.Engine:TradeRequest(1, 2)
	w.Trade(2, "Accept", { From = 1 })
	return w
end
-- Both offers in, both READY, countdown over.
local function readyToConfirm(w, offer1, offer2)
	w.Trade(1, "Offer", offer1)
	w.Trade(2, "Offer", offer2)
	w.Advance(TR.ReviewSeconds)
	local v = w.View(1).Version
	w.Trade(1, "Ready", { Version = v })
	w.Trade(2, "Ready", { Version = v })
	w.Advance(TR.ConfirmDelay)
	return v
end

------------------------------------------------------------------------------------------------
-- Invitations
------------------------------------------------------------------------------------------------
test("an invitation locks nobody until the target accepts", function()
	local w = world()
	w.Join(1)
	w.Join(2)
	local reply = w.Engine:TradeRequest(1, 2)
	eq(reply.Message, "Trade invitation sent", "reply")
	eq(w.Engine.TradeByUser[1], nil, "sender not trading")
	eq(w.Engine.TradeByUser[2], nil, "target not trading (can sell, use the lab and the shelter)")
	eq(w.View(2), nil, "no session for the target")
	local push = w.Last(2, "Invite")
	truthy(push and push.From == 1 and push.To == 2, "the target got an invite push")
	eq(push.In, TR.InviteSeconds, "expires in")
	local rel = w.Engine:TradeRelation(2, 1, 10, 10)
	truthy(rel.InviteIn and rel.InviteIn.Id == reply.Invite.Id, "the target sees the incoming invitation")
	eq(rel.CanInvite, true, "the target can answer")
	eq(w.Engine:TradeRelation(1, 2, 10, 10).Block, "Sent", "the sender sees it as sent")
	fails(function() w.Engine:TradeRequest(1, 2) end, "Invitation already sent")
end)

test("accepting starts a session for both with empty offers", function()
	local w = world()
	w.Join(1)
	w.Join(2)
	w.Engine:TradeRequest(1, 2)
	local reply = w.Trade(2, "Accept", { From = 1 })
	eq(reply.Message, "Trade accepted", "reply")
	truthy(w.Engine.TradeByUser[1] and w.Engine.TradeByUser[1] == w.Engine.TradeByUser[2], "both in one session")
	eq(w.Last(1, "Started").By, 2, "the inviter is told")
	truthy(w.Last(2, "Started"), "the invitee too")
	local view = w.View(1)
	eq(#view.Offers["1"].Dogs, 0, "empty offer 1")
	eq(#view.Offers["2"].Items, 0, "empty offer 2")
	eq(view.Partner, 2, "partner")
	eq(next(w.Engine.TradeInvites), nil, "the invitation is used up")
	fails(function() w.Engine:TradeRequest(1, 2) end, "Finish your current trade first")
end)

test("inviting back accepts the other player's invitation", function()
	local w = world()
	w.Join(1)
	w.Join(2)
	w.Engine:TradeRequest(1, 2)
	local reply = w.Engine:TradeRequest(2, 1)
	eq(reply.Message, "Trade accepted", "auto accept")
	truthy(w.Engine.TradeByUser[1] and w.Engine.TradeByUser[2], "session")
end)

test("level, self and busy targets are refused", function()
	local w = world()
	w.Join(1)
	w.Join(2)
	w.Join(3, nil, 2)
	w.Join(4)
	fails(function() w.Engine:TradeRequest(1, 3) end, "Trading unlocks at level " .. C.TradeLevel)
	fails(function() w.Engine:TradeRequest(1, 1) end, "Choose an online player")
	w.Online[5] = false
	fails(function() w.Engine:TradeRequest(1, 5) end, "Choose an online player")
	eq(w.Engine:TradeRelation(1, 3, 10, 2).Block, "TheirLevel", "their level")
	eq(w.Engine:TradeRelation(3, 1, 2, 10).Block, "Level", "my level")
	w.Engine:TradeRequest(1, 2)
	w.Trade(2, "Accept")
	fails(function() w.Engine:TradeRequest(4, 2) end, "That player is busy in another trade")
	eq(w.Engine:TradeRelation(4, 2, 10, 10).Block, "Busy", "busy")
end)

test("a decline starts the sender's cooldown and tells the sender", function()
	local w = world()
	w.Join(1)
	w.Join(3)
	w.Engine:TradeRequest(1, 3)
	eq(w.Trade(3, "Decline", { From = 1 }).Message, "Invitation declined", "reply")
	eq(next(w.Engine.TradeInvites), nil, "gone")
	local push = w.Last(1, "InviteGone")
	truthy(push and push.Reason == "Declined", "sender told")
	fails(function() w.Engine:TradeRequest(1, 3) end, "before inviting this player again")
	truthy(w.Engine:TradeRelation(1, 3, 10, 10).Cooldown > 0, "cooldown shown")
	eq(w.Engine:TradeRelation(1, 3, 10, 10).Block, "Cooldown", "blocked by the cooldown")
	-- The cooldown is per sender -> target: the target can still invite.
	w.Advance(TR.InviteCooldown + 1)
	eq(w.Engine:TradeRequest(1, 3).Message, "Trade invitation sent", "after the cooldown")
end)

test("unanswered invitations expire, are pruned and leave nothing in RAM", function()
	local w = world()
	w.Join(1)
	for id = 2, 5 do w.Join(id) end
	w.Engine:TradeRequest(1, 2)
	w.Engine:TradeRequest(1, 3)
	w.Engine:TradeRequest(1, 4)
	fails(function() w.Engine:TradeRequest(1, 5) end, "pending invitations")
	w.Advance(TR.InviteSeconds)
	fails(function() w.Trade(2, "Accept", { From = 1 }) end, "This invitation has expired")
	w.Engine:PruneTrades()
	eq(next(w.Engine.TradeInvites), nil, "invitations pruned")
	eq(w.Last(2, "InviteGone").Reason, "Expired", "target told")
	fails(function() w.Engine:TradeRequest(1, 2) end, "before inviting this player again")
	w.Advance(TR.InviteCooldown)
	w.Engine:PruneTrades()
	eq(next(w.Engine.TradeCooldowns), nil, "cooldowns pruned")
	eq(next(w.Engine.Trades), nil, "no sessions")
	eq(next(w.Engine.TradeByUser), nil, "nobody trading")
end)

test("withdrawing an invitation removes it for the target", function()
	local w = world()
	w.Join(1)
	w.Join(2)
	w.Engine:TradeRequest(1, 2)
	eq(w.Engine:TradeCancel(1, { Target = 2 }).Message, "Invitation withdrawn", "withdrawn")
	eq(next(w.Engine.TradeInvites), nil, "gone")
	eq(w.Last(2, "InviteGone").Reason, "Withdrawn", "target told")
end)

------------------------------------------------------------------------------------------------
-- Offers
------------------------------------------------------------------------------------------------
test("an offer holds up to 9 dogs and 9 finds", function()
	local w = world()
	w.Join(1, function(p)
		for i = 1, 10 do dog(p, "d" .. i) end
		for i = 1, 10 do item(p, "x" .. i) end
	end)
	w.Join(2)
	w.Engine:TradeRequest(1, 2)
	w.Trade(2, "Accept")
	local dogs, items = {}, {}
	for i = 1, 10 do table.insert(dogs, "d" .. i); table.insert(items, "x" .. i) end
	fails(function() w.Trade(1, "Offer", { Dogs = dogs }) end, "Maximum 9 dogs per trade")
	fails(function() w.Trade(1, "Offer", { Items = items }) end, "Maximum 9 finds per trade")
	table.remove(dogs)
	table.remove(items)
	w.Trade(1, "Offer", { Dogs = dogs, Items = items, Cash = 500 })
	local offer = w.View(1).Offers["1"]
	eq(#offer.Dogs, 9, "nine dogs")
	eq(#offer.Items, 9, "nine finds")
	eq(offer.Cash, 500, "cash")
	truthy(offer.Details.d1.Value > 0 and offer.Details.x1.Value == w.Profile(1).Items.x1.SellValue, "values")
	eq(offer.Details.d1.OwnerHistory, nil, "slim details")
	fails(function() w.Trade(1, "Offer", { Dogs = { "d1", "d1" } }) end, "Duplicate DogUid")
	fails(function() w.Trade(1, "Offer", { Cash = 2000000 }) end, "Not enough Cash")
	fails(function() w.Trade(1, "Offer", { Dogs = { "b1" } }) end, "Dog not owned")
end)

test("protected dogs and finds are refused with clear messages", function()
	local w = world()
	w.Join(1, function(p)
		dog(p, "locked").Locked = true
		dog(p, "working").AssignedSlot = "DigSlot_1"
		dog(p, "shown")
		p.DisplayDogs = { ["1"] = "shown" }
		dog(p, "walking").State = "Walking"
		dog(p, "paid").PaidRandom = true
		item(p, "fav").Favorite = true
		item(p, "notrade").Tradeable = false
		local x = item(p, "record")
		p.RecordJobs[x.ItemId] = R.Copy(x)
	end)
	w.Join(2)
	w.Engine:TradeRequest(1, 2)
	w.Trade(2, "Accept")
	fails(function() w.Trade(1, "Offer", { Dogs = { "locked" } }) end, "Unlock this dog first")
	fails(function() w.Trade(1, "Offer", { Dogs = { "working" } }) end, "Remove this dog from its kennel first")
	fails(function() w.Trade(1, "Offer", { Dogs = { "shown" } }) end, "Remove this dog from its display first")
	fails(function() w.Trade(1, "Offer", { Dogs = { "walking" } }) end, "Wait for delivery")
	fails(function() w.Trade(1, "Offer", { Dogs = { "paid" } }) end, "Paid-item trading is unavailable")
	fails(function() w.Trade(1, "Offer", { Items = { "fav" } }) end, "Remove this find from favourites first")
	fails(function() w.Trade(1, "Offer", { Items = { "notrade" } }) end, "This item cannot be transferred")
	fails(function() w.Trade(1, "Offer", { Items = { "record" } }) end, "Record check pending")
	paidAllowed = true
	w.Trade(1, "Offer", { Dogs = { "paid" } })
	paidAllowed = false
	eq(#w.View(1).Offers["1"].Dogs, 1, "a paid dog where both may trade it")
end)

------------------------------------------------------------------------------------------------
-- Safety flow
------------------------------------------------------------------------------------------------
test("READY waits for the review time and any change resets both READY flags", function()
	local w = session()
	w.Trade(1, "Offer", { Dogs = { "a1" } })
	local v = w.View(1).Version
	fails(function() w.Trade(1, "Ready", { Version = v }) end, "Review the newest offer")
	w.Advance(TR.ReviewSeconds)
	fails(function() w.Trade(1, "Ready", { Version = v - 1 }) end, "Offer changed")
	eq(w.Trade(1, "Ready", { Version = v }).Message, "Ready. Waiting for your partner", "ready 1")
	eq(w.Last(2, "Changed").By, 1, "the partner sees it live")
	w.Trade(2, "Ready", { Version = v })
	local view = w.View(2)
	truthy(view.Ready["1"] and view.Ready["2"], "both ready")
	eq(view.ConfirmIn, TR.ConfirmDelay, "countdown")
	-- The partner adds a find: both flags and the countdown reset, the version moves.
	w.Trade(2, "Offer", { Items = { "bi1" } })
	view = w.View(1)
	eq(next(view.Ready), nil, "READY reset for both")
	eq(view.ConfirmIn, nil, "countdown reset")
	eq(view.Version, v + 1, "version")
	truthy(view.ReviewIn > 0, "review time again")
	-- UNREADY drops only your own flag and any confirmation.
	w.Advance(TR.ReviewSeconds)
	w.Trade(1, "Ready", { Version = view.Version })
	w.Trade(2, "Ready", { Version = view.Version })
	w.Trade(2, "Unready")
	view = w.View(1)
	eq(view.Ready["1"], true, "1 still ready")
	eq(view.Ready["2"], nil, "2 not ready")
	eq(view.ConfirmIn, nil, "no countdown")
end)

test("CONFIRM is refused before both READY and before the countdown ends", function()
	local w = session()
	w.Trade(1, "Offer", { Dogs = { "a1" } })
	w.Advance(TR.ReviewSeconds)
	local v = w.View(1).Version
	fails(function() w.Trade(1, "Confirm", { Version = v }) end, "Both players must press READY first")
	w.Trade(1, "Ready", { Version = v })
	w.Trade(2, "Ready", { Version = v })
	fails(function() w.Trade(1, "Confirm", { Version = v }) end, "Safety countdown is still running")
	w.Advance(TR.ConfirmDelay - 1)
	fails(function() w.Trade(2, "Confirm", { Version = v }) end, "Safety countdown is still running")
	w.Advance(1)
	eq(w.Trade(1, "Confirm", { Version = v }).Message, "Confirmed. Waiting for your partner", "first confirm")
	eq(w.Profile(1).Dogs.a1.OwnerUserId, 1, "nothing moves on one confirm")
	fails(function() w.Trade(1, "Ready", { Version = v + 5 }) end, "Offer changed")
	fails(function() w.Trade(2, "Ready", { Version = v - 1 }) end, "Offer changed")
	-- Adding something now drops the first confirmation too.
	w.Trade(1, "Offer", { Dogs = { "a1", "a2" } })
	eq(next(w.View(2).Confirmed), nil, "confirmation reset")
end)

test("the second CONFIRM swaps dogs, finds and cash atomically", function()
	local w = session()
	local before1, before2 = w.Profile(1), w.Profile(2)
	local v = readyToConfirm(w, { Dogs = { "a1", "a2" }, Items = { "ai1" }, Cash = 1000 }, { Dogs = { "b1" }, Items = { "bi1", "bi2" }, Cash = 250 })
	w.Trade(2, "Confirm", { Version = v })
	local result = w.Trade(1, "Confirm", { Version = v })
	eq(result.Message, "Trade completed", "reply")
	eq(result.CompletedWith, 2, "partner for the projection")
	local p, q = w.Profile(1), w.Profile(2)
	eq(p.Dogs.a1, nil, "a1 left 1")
	eq(q.Dogs.a1.OwnerUserId, 2, "a1 owned by 2")
	eq(q.Dogs.a2.OwnerUserId, 2, "a2 owned by 2")
	eq(p.Dogs.b1.OwnerUserId, 1, "b1 owned by 1")
	eq(p.Dogs.b1.OwnerHistory[#p.Dogs.b1.OwnerHistory].Type, "Trade", "history")
	eq(q.Items.ai1.OwnerUserId, 2, "find to 2")
	eq(p.Items.bi1.OwnerUserId, 1, "find to 1")
	eq(p.Items.bi2.OwnerUserId, 1, "second find to 1")
	eq(p.Cash, before1.Cash - 1000 + 250, "cash 1")
	eq(q.Cash, before2.Cash - 250 + 1000, "cash 2")
	eq(p.Stats.CompletedTrades, before1.Stats.CompletedTrades + 1, "trades 1")
	eq(q.Stats.CompletedTrades, before2.Stats.CompletedTrades + 1, "trades 2")
	eq(R.Count(p.Dogs) + R.Count(q.Dogs), R.Count(before1.Dogs) + R.Count(before2.Dogs), "no dog lost or duplicated")
	eq(I.Count(p.Items) + I.Count(q.Items), I.Count(before1.Items) + I.Count(before2.Items), "no find lost or duplicated")
	eq(w.Engine.TradeByUser[1], nil, "session over 1")
	eq(w.Engine.TradeByUser[2], nil, "session over 2")
	eq(next(w.Engine.Trades), nil, "no session left")
	local done = w.Last(2, "Completed")
	truthy(done and done.Offers["1"] and #done.Offers["1"].Dogs == 2, "both told what moved")
	truthy(w.Last(1, "Completed"), "1 told")
end)

test("an old profile without the trade counter still completes a trade", function()
	local w = session()
	w.Edit(2, function(p) p.Stats.CompletedTrades = nil end)
	local v = readyToConfirm(w, { Cash = 10 }, { Cash = 20 })
	w.Trade(1, "Confirm", { Version = v })
	w.Trade(2, "Confirm", { Version = v })
	eq(w.Profile(2).Stats.CompletedTrades, 1, "counter created")
end)

test("a full storage refuses READY, and a commit that cannot fit changes nothing", function()
	local w = session()
	-- READY pre-check: 2 cannot take another dog.
	w.Edit(2, function(p)
		for i = R.Count(p.Dogs) + 1, R.Capacity(p) do dog(p, "fill" .. i) end
	end)
	w.Trade(1, "Offer", { Dogs = { "a1" } })
	w.Advance(TR.ReviewSeconds)
	local v = w.View(1).Version
	fails(function() w.Trade(1, "Ready", { Version = v }) end, "Your partner's dog storage is full")
	fails(function() w.Trade(2, "Ready", { Version = v }) end, "Your dog storage is full")
	-- A find instead of the dog fits; then 2's find storage fills up after both pressed READY.
	local v2 = readyToConfirm(w, { Items = { "ai1" } }, { Cash = 5 })
	w.Edit(2, function(p)
		for i = I.Count(p.Items) + 1, I.Capacity(p) do item(p, "late" .. i) end
	end)
	local before1, before2 = w.Profile(1), w.Profile(2)
	w.Trade(2, "Confirm", { Version = v2 })
	fails(function() w.Trade(1, "Confirm", { Version = v2 }) end, "Your partner's find storage is full")
	local p, q = w.Profile(1), w.Profile(2)
	eq(I.Count(p.Items), I.Count(before1.Items), "1 finds untouched")
	eq(I.Count(q.Items), I.Count(before2.Items), "2 finds untouched")
	eq(p.Items.ai1.OwnerUserId, 1, "the find stayed")
	eq(p.Cash, before1.Cash, "cash 1 untouched")
	eq(q.Cash, before2.Cash, "cash 2 untouched")
	eq(q.Stats.CompletedTrades, before2.Stats.CompletedTrades, "no trade counted")
	local view = w.View(1)
	truthy(view, "the session stays open to fix the offer")
	eq(next(view.Ready), nil, "READY reset after the failure")
	eq(next(view.Confirmed), nil, "confirmations reset")
	eq(w.Last(2, "Failed").Message, "Your find storage is full", "the partner is told from their side")
	eq(w.Last(1, "Failed").Message, "Your partner's find storage is full", "and the confirmer from theirs")
end)

test("a dog that changed after the offer stops the commit", function()
	local w = session()
	local v = readyToConfirm(w, { Dogs = { "a1" } }, { Items = { "bi1" } })
	w.Edit(1, function(p) p.Dogs.a1.Locked = true end)
	w.Trade(2, "Confirm", { Version = v })
	fails(function() w.Trade(1, "Confirm", { Version = v }) end, "Unlock this dog first")
	eq(w.Profile(1).Dogs.a1.OwnerUserId, 1, "kept")
	eq(w.Profile(2).Items.bi1.OwnerUserId, 2, "kept")
	w.Edit(2, function(p) p.Items.bi1.Favorite = true end)
	w.Edit(1, function(p) p.Dogs.a1.Locked = false end)
	w.Advance(TR.ReviewSeconds)
	w.Trade(1, "Ready", { Version = v })
	w.Trade(2, "Ready", { Version = v })
	w.Advance(TR.ConfirmDelay)
	w.Trade(1, "Confirm", { Version = v })
	fails(function() w.Trade(2, "Confirm", { Version = v }) end, "favourites")
end)

------------------------------------------------------------------------------------------------
-- Ending sessions
------------------------------------------------------------------------------------------------
test("leaving the server cancels the session and the invitations", function()
	local w = session()
	w.Join(3)
	w.Trade(1, "Offer", { Dogs = { "a1" } })
	fails(function() w.Engine:TradeRequest(3, 1) end, "busy in another trade")
	w.Online[2] = false
	local ok = w.Engine:Leave(2)
	truthy(ok, "left")
	eq(w.Engine.TradeByUser[1], nil, "1 free again")
	eq(next(w.Engine.Trades), nil, "session gone")
	eq(w.Last(1, "Left").By, 2, "1 told the partner left")
	eq(w.Profile(1).Dogs.a1.OwnerUserId, 1, "nothing moved")
end)

test("a cancel ends the session for both", function()
	local w = session()
	eq(w.Engine:TradeCancel(2).Message, "Trade cancelled", "reply")
	eq(w.Engine.TradeByUser[1], nil, "1 free")
	eq(w.Last(1, "Cancelled").By, 2, "1 told")
end)

test("an idle session expires and a session with a missing player is closed", function()
	local w = session()
	w.Advance(TR.SessionIdle)
	w.Engine:PruneTrades()
	eq(next(w.Engine.Trades), nil, "idle session pruned")
	eq(w.Last(2, "Expired").Kind, "Expired", "told")
	w = session()
	w.Online[1] = false
	w.Engine:PruneTrades()
	eq(next(w.Engine.TradeByUser), nil, "orphaned session pruned")
end)

------------------------------------------------------------------------------------------------
-- Value check
------------------------------------------------------------------------------------------------
test("fairness numbers are sane and never block a trade", function()
	local f = TR.Fairness(300, 100)
	eq(f.Warn, true, "3x warns")
	eq(f.Level, "Over", "over")
	eq(f.Share, 0.75, "share")
	f = TR.Fairness(100, 100)
	eq(f.Level, "Fair", "fair")
	eq(f.Warn, false, "no warning")
	eq(f.Share, 0.5, "even")
	eq(TR.Fairness(0, 0).Level, "Empty", "empty")
	eq(TR.Fairness(0, 50).Level, "Under", "a gift to you")
	eq(TR.Fairness(0, 50).Warn, false, "receiving never warns")
	eq(TR.Fairness(10, 0).Ratio, 999, "capped ratio")
	eq(TR.Fairness(299, 100).Warn, false, "just under 3x")
	local common = TR.DogValue({ DogId = "Breadog", Variant = "Normal" })
	local legendary = TR.DogValue({ DogId = "KingCorgi", Variant = "Normal" })
	local void = TR.DogValue({ DogId = "Breadog", Variant = "Void" })
	truthy(common > 0 and legendary > common * 10, "rarity raises the value")
	truthy(void > common * 5, "variant raises the value")
	eq(TR.DogValue({ DogId = "NoSuchDog" }), 0, "unknown dog")
	eq(TR.ItemValue({ SellValue = 1234 }), 1234, "finds use their sale value")
	eq(TR.DogRarity({ DogId = "KingCorgi" }), "Legendary", "dog rarity")
	truthy(TR.IsBig("Legendary") and TR.IsBig("Secret") and not TR.IsBig("Epic"), "Legendary+")
	-- In a session: what you give vs what you get, from each side.
	local w = session()
	w.Trade(1, "Offer", { Dogs = { "a1" }, Cash = 100 })
	w.Trade(2, "Offer", { Dogs = { "b1", "b2" } })
	local mine, theirs = w.View(1).Fairness, w.View(2).Fairness
	eq(mine.Give, TR.DogValue(w.Profile(1).Dogs.a1) + 100, "give = dog + cash")
	eq(mine.Get, theirs.Give, "symmetric")
	eq(mine.Give, theirs.Get, "symmetric 2")
	eq(theirs.Warn, true, "2 gives two Legendaries for a Common")
	eq(mine.Level, "Under", "1 gets far more")
	-- The warning does not stop the trade.
	w.Advance(TR.ReviewSeconds)
	local v = w.View(1).Version
	w.Trade(1, "Ready", { Version = v })
	w.Trade(2, "Ready", { Version = v })
	w.Advance(TR.ConfirmDelay)
	w.Trade(1, "Confirm", { Version = v })
	eq(w.Trade(2, "Confirm", { Version = v }).Message, "Trade completed", "an unfair trade still completes")
end)

------------------------------------------------------------------------------------------------
-- Compatibility and texts
------------------------------------------------------------------------------------------------
test("the trade view keeps the fields of the old snapshot", function()
	local w = session()
	w.Trade(1, "Offer", { Dogs = { "a1" }, Items = { "ai1" }, Cash = 5 })
	local view = w.View(2)
	for _, key in ipairs({ "Id", "Users", "Version", "Offers", "Ready", "Confirmed", "Expires", "Inviter", "Accepted", "UpdatedAt", "ConfirmDelay", "Details" }) do
		truthy(view[key] ~= nil, "field " .. key)
	end
	local offer = view.Offers["1"]
	for _, key in ipairs({ "Dogs", "Items", "Cash", "Prints", "ItemPrints", "Details", "Estimated" }) do
		truthy(offer[key] ~= nil, "offer field " .. key)
	end
	eq(view.Details.a1.DisplayName, w.Profile(1).Dogs.a1.DisplayName, "merged details (dog)")
	eq(view.Details.ai1.Mutation, "NORMAL", "merged details (find)")
	eq(view.Accepted, true, "accepted")
	eq(view.Inviter, 1, "inviter")
	-- Runtime keeps Snapshot.Trade / Snapshot.Players and routes the three trade actions.
	local runtime = fs.readFile("src/ServerScriptService/Economy/Runtime.luau")
	truthy(string.find(runtime, "Trade=tradeView,Players=online", 1, true), "snapshot fields")
	truthy(string.find(runtime, "action=='TradeRequest' then return true,engine:TradeRequest(id,a.Target)", 1, true), "TradeRequest")
	truthy(string.find(runtime, "action=='TradeCancel' then return true,engine:TradeCancel(id,a)", 1, true), "TradeCancel")
	truthy(string.find(runtime, "action=='Trade' then return true,engine:Trade(id,a.Action,a)", 1, true), "Trade")
	truthy(not string.find(runtime, "DogEconomyOpen:FireClient(target,'Trade'", 1, true), "no forced window for the target")
	truthy(string.find(runtime, "Runtime.Engine.OnTrade=Runtime.PushTrade", 1, true), "pushes wired")
	-- Selling, the lab and the shelter still check TradeByUser (set only for accepted sessions).
	for _, file in ipairs({ "YardCommerce", "LabService", "ShelterService" }) do
		truthy(string.find(fs.readFile("src/ServerScriptService/Economy/" .. file .. ".luau"), "TradeByUser", 1, true), file)
	end
end)

test("trade action arguments pass Runtime.clean (30 entries, depth 3)", function()
	local function clean(value, depth)
		if depth > 3 then return false end
		local kind = typeof(value)
		if kind == "string" then return #value <= 120
		elseif kind == "number" then return value == value and math.abs(value) <= C.MaxCash
		elseif kind == "boolean" or kind == "nil" then return true
		elseif kind == "table" then
			local n = 0
			for k, v in pairs(value) do
				n += 1
				if n > 30 or (type(k) ~= "string" and type(k) ~= "number") or not clean(v, depth + 1) then return false end
			end
			return true
		end
		return false
	end
	local dogs, items = {}, {}
	for i = 1, TR.MaxDogs do table.insert(dogs, string.rep("a", 32) .. i) end
	for i = 1, TR.MaxItems do table.insert(items, string.rep("b", 32) .. i) end
	truthy(clean({ Action = "Offer", Dogs = dogs, Items = items, Cash = C.MaxCash }, 0), "a full offer passes")
	truthy(TR.MaxDogs <= 30 and TR.MaxItems <= 30, "limits fit")
end)

-- Every Exact entry and pattern AutoTranslate knows: the base dictionary and every feature dictionary.
local function dictionaries()
	local exact, patterns = {}, {}
	for en, ru in string.gmatch(fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau"), '%[%"([^"]+)%"%]%s*=%s*"([^"]*)"') do
		exact[en] = ru
	end
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local dict = L.Require("ReplicatedStorage.Localization." .. string.gsub(name, "%.luau$", ""))
		for en, ru in pairs(type(dict) == "table" and dict.Exact or {}) do exact[en] = ru end
		for _, rule in ipairs(type(dict) == "table" and dict.Patterns or {}) do table.insert(patterns, rule) end
	end
	return function(message)
		if exact[message] then return true end
		for _, rule in ipairs(patterns) do
			if string.find(message, rule[1]) then return true end
		end
		return false
	end
end

test("every trade text and server message has Russian", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/TradeScreen.luau")
	local missing = {}
	local seen = 0
	for en in string.gmatch(source, "%f[%w_]T%(\"([^\"]*)\"%)") do
		seen += 1
		if not (Dict.UI[en] or Dict.Exact[en]) then table.insert(missing, "T: " .. en) end
	end
	local function specs(s)
		local out = {}
		for spec in string.gmatch((s:gsub("%%%%", "")), "%%[%d%.]*[dsf]") do table.insert(out, spec) end
		return table.concat(out, ",")
	end
	for en in string.gmatch(source, "%f[%w_]F%(\"([^\"]*)\"") do
		seen += 1
		local ru = Dict.Templates[en]
		if not ru then
			table.insert(missing, "F: " .. en)
		elseif specs(en) ~= specs(ru) then
			table.insert(missing, "format mismatch: " .. en)
		end
	end
	truthy(seen > 40, "texts found: " .. seen)
	-- Server replies of the trade code (the Engine trade section and the rules it reuses): every
	-- dictionary AutoTranslate loads counts (shared replies keep their Russian elsewhere).
	local known = dictionaries()
	local engine = fs.readFile("src/ServerScriptService/Economy/Engine.luau")
	local section = engine:sub(engine:find("TRADES 2.0", 1, true), engine:find("RAM-only: hands this profile", 1, true))
	local found = 0
	for line in string.gmatch(section, "[^\n]+") do
		if not string.find(line, "^%s*%-%-") then
			for message in string.gmatch(line, '"([A-Z][^"]-)"') do
				-- Fragments of a concatenation ("Maximum "..n..) are checked whole below.
				if #message > 12 and string.find(message, " ", 1, true) and not string.find(message, " $") and not string.find(message, "DOGROTS", 1, true) then
					found += 1
					if not known(message) then table.insert(missing, "server: " .. message) end
				end
			end
		end
	end
	truthy(found > 20, "server messages found: " .. found)
	for _, message in ipairs({
		"Unlock this dog first", "Remove this dog from its kennel first", "Wait for delivery", "Dog not owned",
		"This item cannot be transferred", "Record check pending; retry shortly", "Item not owned", "Not enough Cash or Bones",
		"Trading unlocks at level 5 for both players", "Wait 12s before inviting this player again", "Maximum 9 dogs per trade",
		"Maximum 9 finds per trade", "You already have 3 pending invitations", "Finish your trade before selling",
		"Your dog storage is full", "Your partner's dog storage is full", "Your find storage is full", "Your partner's find storage is full",
		"Paid-item trading is unavailable for a participant", "Invalid DogUid", "Invalid ItemUid", "Cash limit reached",
		"Please wait a moment", "Account is busy; retry shortly",
	}) do
		if not known(message) then table.insert(missing, "reply: " .. message) end
	end
	if #missing > 0 then error(#missing .. " missing:\n  " .. table.concat(missing, "\n  ")) end
end)

test("trade dictionary entries agree with the other dictionaries", function()
	local base = {}
	for en, ru in string.gmatch(fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau"), '%[%"([^"]+)%"%]%s*=%s*"([^"]*)"') do
		base[en] = ru
	end
	local others = {}
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		if name ~= "Trade.luau" then
			local dict = L.Require("ReplicatedStorage.Localization." .. string.gsub(name, "%.luau$", ""))
			for en, ru in pairs(type(dict) == "table" and dict.Exact or {}) do others[en] = ru end
		end
	end
	local clash = {}
	for en, ru in pairs(Dict.Exact) do
		if (base[en] and base[en] ~= ru) or (others[en] and others[en] ~= ru) then table.insert(clash, en) end
	end
	if #clash > 0 then error("different Russian for: " .. table.concat(clash, ", ")) end
	for _, rule in ipairs(Dict.Patterns) do
		truthy(type(rule[1]) == "string" and type(rule[2]) == "string", "pattern rule")
		truthy(pcall(string.find, "x", rule[1]), "valid pattern " .. rule[1])
	end
end)

------------------------------------------------------------------------------------------------
-- The trade window, end to end: two Modules.TradeScreen instances (players 1 and 2) over a mock UI
-- kit and a mock Modules.Net wired to the real Engine (pushes delivered like Runtime.PushTrade).
-- Every button, card and push the players use goes through the window's own code.
------------------------------------------------------------------------------------------------
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector2, UDim2 = roblox.Vector2, roblox.UDim2
local Theme = L.Require("StarterGui.ScreenGui.Modules.Kit.Theme")
local Format = L.Require("StarterGui.ScreenGui.Modules.Kit.Format")
local SCREEN = fs.readFile("src/StarterGui/ScreenGui/Modules/TradeScreen.luau")

-- A tiny scheduler: task.spawn runs at once, task.wait / task.delay wake on advance().
local function scheduler()
	local s = { Now = 0, Waiting = {}, Errors = {} }
	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(s.Errors, tostring(err))
		end
	end
	function s.spawn(fn, ...)
		resume(coroutine.create(fn), ...)
	end
	s.task = {
		spawn = function(fn, ...) s.spawn(fn, ...) end,
		defer = function(fn, ...) s.spawn(fn, ...) end,
		wait = function(t)
			table.insert(s.Waiting, { Co = coroutine.running(), At = s.Now + (t or 0) })
			return coroutine.yield()
		end,
		delay = function(t, fn, ...)
			table.insert(s.Waiting, { Fn = fn, Args = table.pack(...), At = s.Now + (t or 0) })
		end,
	}
	function s.advance(dt, onStep)
		local target = s.Now + dt
		local steps = 0
		while true do
			local best, index = nil, nil
			for i, w in ipairs(s.Waiting) do
				if w.At <= target and (not best or w.At < best.At) then best, index = w, i end
			end
			if not best then break end
			steps += 1
			assert(steps < 5000, "runaway scheduler (a loop that never stops)")
			table.remove(s.Waiting, index)
			s.Now = math.max(s.Now, best.At)
			if onStep then onStep() end
			if best.Co then resume(best.Co) else s.spawn(best.Fn, table.unpack(best.Args, 1, best.Args.n)) end
		end
		s.Now = target
		if onStep then onStep() end
	end
	return s
end

local function signal()
	local sig = { Fns = {} }
	function sig:Connect(fn)
		table.insert(self.Fns, fn)
		return { Disconnect = function() end }
	end
	sig.Once = sig.Connect
	function sig:Fire(...)
		for _, fn in ipairs(self.Fns) do fn(...) end
	end
	return sig
end
local raws = setmetatable({}, { __mode = "k" })
local function fake(class)
	local raw = { ClassName = class or "Frame", Name = class or "Frame", Children = {}, Attributes = {}, Signals = {}, Visible = true, Text = "", AbsoluteSize = Vector2.new(1920, 1080) }
	local obj
	obj = setmetatable({}, {
		__index = function(_, k)
			local v = raw[k]
			if v ~= nil then return v end
			if k == "SetAttribute" then return function(_, a, x) raw.Attributes[a] = x end end
			if k == "GetAttribute" then return function(_, a) return raw.Attributes[a] end end
			if k == "FindFirstChildWhichIsA" or k == "FindFirstChildOfClass" then
				return function(_, c) for _, ch in ipairs(raw.Children) do if ch.ClassName == c then return ch end end; return nil end
			end
			if k == "FindFirstChild" then
				return function(_, n) for _, ch in ipairs(raw.Children) do if ch.Name == n then return ch end end; return nil end
			end
			if k == "GetChildren" then return function() return table.clone(raw.Children) end end
			if k == "GetPropertyChangedSignal" then
				return function(_, p) raw.Signals["P:" .. p] = raw.Signals["P:" .. p] or signal(); return raw.Signals["P:" .. p] end
			end
			if k == "IsFocused" then return function() return raw.Focused == true end end
			if k == "ReleaseFocus" or k == "CaptureFocus" or k == "Destroy" then return function() end end
			if k == "IsA" then return function(_, c) return c == raw.ClassName end end
			if k == "Position" or k == "Size" then return UDim2.new() end
			if k == "AnchorPoint" then return Vector2.zero end
			raw.Signals[k] = raw.Signals[k] or signal()
			return raw.Signals[k]
		end,
		__newindex = function(_, k, v)
			if k == "Parent" and v and raws[v] then table.insert(raws[v].Children, obj) end
			raw[k] = v
		end,
	})
	raws[obj] = raw
	return obj
end

local function makeKit(env)
	local Kit = { Theme = Theme, Format = Format }
	Kit.Lang = function() return env.Lang end
	Kit.T = function(en, ru) return env.Lang == "ru" and ru or en end
	Kit.Word = function(k) return k end
	Kit.Now = function() return env.ServerNow() end
	Kit.Motion = {
		Reduced = function() return false end,
		Tween = function(inst, _, goals) for k, v in pairs(goals) do inst[k] = v end; return nil end,
	}
	local layer = fake("ScreenGui")
	Kit.Overlay = { Top = function() return layer end }
	local function parented(o, parent) if parent then o.Parent = parent end; return o end
	Kit.New = function(class, props, parent)
		local o = fake(class)
		for k, v in pairs(props or {}) do o[k] = v end
		return parented(o, parent)
	end
	Kit.Text = function(parent, props)
		local o = fake("TextLabel")
		o.Text = props and props.Text or ""
		o.Name = props and props.Name or "Label"
		return parented(o, parent)
	end
	Kit.Icon = function(parent) return parented(fake("ImageLabel"), parent) end
	Kit.Corner = function(parent) return parented(fake("UICorner"), parent) end
	Kit.Stroke = function(parent, color, thickness)
		local o = fake("UIStroke")
		o.Color, o.Thickness = color, thickness
		return parented(o, parent)
	end
	Kit.Padding = function(parent) return parented(fake("UIPadding"), parent) end
	local function component(parent)
		local c = { Instance = parented(fake("Frame"), parent) }
		function c:Destroy() end
		return c
	end
	Kit.Button = function(parent, props)
		local b = component(parent)
		b.Props = props or {}
		b.Text, b.Style, b.Disabled, b.Busy, b.OnClick = b.Props.Text or "", b.Props.Style, b.Props.Disabled == true, false, b.Props.OnClick
		function b:SetText(t) self.Text = t end
		function b:SetStyle(s) self.Style = s end
		function b:SetDisabled(d) self.Disabled = d == true end
		function b:SetBusy(x) self.Busy = x == true end
		function b:SetOnClick(fn) self.OnClick = fn end
		function b:Click()
			if self.Disabled or self.Busy or not self.OnClick then return false end
			env.Sched.spawn(self.OnClick)
			return true
		end
		return b
	end
	Kit.Pill = function(parent, props)
		local p = component(parent)
		p.Text = props and props.Text or ""
		function p:Set(t) if t ~= nil then self.Text = t end end
		function p:SetVisible(v) self.Instance.Visible = v end
		function p:SetGradient() end
		return p
	end
	Kit.ProgressBar = function(parent, props)
		local p = component(parent)
		p.Value = props and props.Value or 0
		function p:SetValue(v) self.Value = v end
		function p:SetColor(c) self.Color = c end
		function p:SetText(t) self.Text = t end
		return p
	end
	Kit.Countdown = function(parent, props)
		local c = component(parent)
		c.Props = props or {}
		function c:SetEndsAt(e)
			self.EndsAt, self.Done = e, false
			if not e or e <= env.ServerNow() then
				self.Done = true
				if self.Props.OnDone then env.Sched.spawn(self.Props.OnDone) end
			end
		end
		table.insert(env.Countdowns, c)
		return c
	end
	Kit.SearchBox = function(parent, props)
		local s = component(parent)
		s.Props = props
		function s:SetText(t, silent) self.Text = t; if not silent and props.OnChange then env.Sched.spawn(props.OnChange, t) end end
		return s
	end
	Kit.Chips = function(parent, props) local c = component(parent); c.Props = props; return c end
	Kit.SortSelect = function(parent, props) local c = component(parent); c.Props = props; return c end
	Kit.Tabs = function(parent, props)
		local t = component(parent)
		t.Props, t.Selected, t.Badges = props, props.Selected, {}
		function t:Select(id, silent)
			local changed = self.Selected ~= id
			self.Selected = id
			if changed and not silent and props.OnChange then env.Sched.spawn(props.OnChange, id) end
		end
		function t:SetBadge(id, text) self.Badges[id] = text end
		return t
	end
	Kit.Tooltip = function(_, content) return { Content = content, Destroy = function() end } end
	Kit.Toast = function(text, opts) table.insert(env.Toasts, { Text = text, Kind = opts and opts.Kind }) end
	Kit.Confirm = function(title, body, opts)
		local m = { Title = title, Body = body, Opts = opts }
		function m:Then(fn) self.Fn = fn; return self end
		table.insert(env.Modals, m)
		return m
	end
	local function grid(parent, props)
		local g = component(parent)
		g.Props, g.Cells, g.Items = props, {}, {}
		local function bindAll()
			for i, item in ipairs(g.Items) do
				local key = props.Key and props.Key(item, i) or i
				local cell = g.Cells[key]
				if not cell then
					local frame = fake("Frame")
					frame.ZIndex = 5
					cell = props.Create and props.Create(frame, g) or frame
					g.Cells[key] = cell
					if props.Layout then props.Layout(cell, 300, 70); props.Layout(cell, 150, 200) end
				end
				if props.Bind then props.Bind(cell, item, i) end
			end
		end
		function g:SetItems(list) self.Items = list; bindAll() end
		function g:Refresh() bindAll() end
		function g:Cell(i) local item = self.Items[i]; return item and self.Cells[props.Key and props.Key(item, i) or i] end
		function g:Destroy() for _, cell in pairs(self.Cells) do if props.Destroy then props.Destroy(cell) end end end
		if props.CellSize then props.CellSize(400, 300); props.CellSize(200, 100) end
		return g
	end
	Kit.VirtualGrid = grid
	Kit.VirtualList = grid
	Kit.DogCard = {
		new = function(frame)
			local card = { Frame = frame }
			function card:Bind(data) self.Data = data end
			function card:Layout(w, h) self.W, self.H = w, h end
			function card:Destroy() end
			function card:Click()
				if self.Data and self.Data.Disabled then
					if self.Data.DisabledReason then table.insert(env.Toasts, { Text = self.Data.DisabledReason, Kind = "warn" }) end
					return
				end
				if self.OnClick then self.OnClick(self) end
			end
			return card
		end,
	}
	Kit.Window = {
		new = function(props)
			local win = { Props = props, Body = fake("Frame"), IsOpen = false, Resized = signal() }
			function win:Open() self.IsOpen = true; if props.OnOpen then env.Sched.spawn(props.OnOpen, self) end end
			function win:Close() self.IsOpen = false; if props.OnClose then env.Sched.spawn(props.OnClose, self, "close") end end
			function win:Destroy() self.IsOpen = false end
			function win:SetTitle(t, s) self.TitleText, self.SubtitleText = t, s end
			function win:GetLayout() return env.Layout end
			env.Win = win
			return win
		end,
	}
	return Kit
end

local DESKTOP = { Phone = false, Landscape = false, Width = 1176, Height = 650 }
local PORTRAIT = { Phone = true, Landscape = false, Width = 344, Height = 520 }
local LANDSCAPE = { Phone = true, Landscape = true, Width = 790, Height = 300 }

-- Two players in the world of session() but not yet trading, each with a window.
local function clients()
	local w = world()
	w.Join(1, function(p)
		for i = 1, 3 do dog(p, "a" .. i) end
		for i = 1, 3 do item(p, "ai" .. i, "rusty_spoon", "NORMAL", 1 + i / 10) end
		dog(p, "alocked").Locked = true
	end)
	w.Join(2, function(p)
		for i = 1, 2 do dog(p, "b" .. i, "KingCorgi") end
		item(p, "bi1", "lost_key", "GOLDEN")
	end)
	local sched = scheduler()
	local names = { [1] = "Ann", [2] = "Bob" }
	local server, envs = {}, {}
	local queue = {}
	local function rows(id)
		local out = {}
		local mine = w.Profile(id)
		for other = 1, 2 do
			if other ~= id then
				local p = w.Profile(other)
				local row = { Id = other, Name = names[other], Username = string.lower(names[other]), Level = p.Level,
					Status = w.Engine.TradeByUser[other] and "Trading" or "Online", Trades = 0, Listings = 0 }
				for k, v in pairs(w.Engine:TradeRelation(id, other, mine.Level, p.Level)) do row[k] = v end
				table.insert(out, row)
			end
		end
		return out
	end
	function server.Snapshot(id)
		w.Engine:PruneTrades()
		return R.Copy({ Profile = w.Profile(id), Trade = w.Engine:TradeView(id), Players = rows(id), Now = w.Now })
	end
	function server.Flush()
		while #queue > 0 do
			local push = table.remove(queue, 1)
			local env = envs[push.To]
			for _, fn in ipairs(env and env.Handlers[push.Kind] or {}) do sched.spawn(fn, R.Copy(push.Data)) end
		end
	end
	w.Engine.OnTrade = function(id, event)
		local payload = R.Copy(event)
		payload.Names = {}
		for _, k in ipairs({ "By", "From", "To" }) do
			if payload[k] then payload.Names[tostring(payload[k])] = names[payload[k]] end
		end
		table.insert(queue, { To = id, Kind = "Trade", Data = { Event = payload, Trade = w.Engine:TradeView(id), Players = rows(id), Now = w.Now } })
		if payload.Kind == "Invite" and payload.To == id then table.insert(queue, { To = id, Kind = "TradeInvite", Data = payload }) end
	end
	function server.Request(id, action, a)
		local ok, success, result = pcall(function()
			if action == "TradeRequest" then return true, w.Engine:TradeRequest(id, a.Target) end
			if action == "TradeCancel" then return true, w.Engine:TradeCancel(id, a) end
			if action == "Trade" then return true, w.Engine:Trade(id, a.Action, a) end
			error("unknown action " .. tostring(action))
		end)
		if not ok then return false, tostring(success) end
		return success, R.Copy(result)
	end
	local function load(id)
		local env = { Lang = "en", Toasts = {}, Modals = {}, Countdowns = {}, Handlers = {}, Changed = {}, Layout = DESKTOP, Sched = sched, Requests = {} }
		env.ServerNow = function() return w.Now end
		local Kit = makeKit(env)
		local Net = {}
		local function publish(snapshot)
			env.Last = snapshot
			for _, fn in ipairs(env.Changed) do sched.spawn(fn, R.Copy(snapshot)) end
		end
		Net.Changed = { Connect = function(_, fn) table.insert(env.Changed, fn) end }
		function Net.OnPush(kind, fn)
			env.Handlers[kind] = env.Handlers[kind] or {}
			table.insert(env.Handlers[kind], fn)
		end
		function Net.Cached() return env.Last end
		function Net.Snapshot()
			local snapshot = server.Snapshot(id)
			server.Flush()
			publish(snapshot)
			return snapshot
		end
		function Net.Request(action, args)
			table.insert(env.Requests, { Action = action, Args = R.Copy(args) })
			local ok, result = server.Request(id, action, R.Copy(args or {}))
			if ok and type(result) == "table" then result.StateSnapshot = server.Snapshot(id) end
			server.Flush() -- pushes fired during the request arrive before the reply
			if ok and type(result) == "table" then publish(result.StateSnapshot) end
			return ok, result
		end
		local main = { GetAttribute = function(_, a) if a == "OpenMenu" then return env.OpenMenu end end }
		local playerGui = { FindFirstChild = function(_, n) return n == "ScreenGui" and main or nil end }
		local function player(uid)
			return { UserId = uid, DisplayName = names[uid], Name = string.lower(names[uid] or "?"),
				GetAttribute = function() return nil end,
				FindFirstChild = function(_, n) return n == "PlayerGui" and playerGui or nil end }
		end
		local PlayersService = { LocalPlayer = player(id), GetPlayerByUserId = function(_, uid) return names[uid] and player(uid) or nil end }
		local RS = L.Game:GetService("ReplicatedStorage")
		local KIT, NET = {}, {}
		local game = { GetService = function(_, name)
			if name == "Players" then return PlayersService end
			if name == "ReplicatedStorage" then return RS end
			return { GetInsetArea = function() error("no insets in tests") end }
		end }
		local sandbox = setmetatable({
			game = game,
			script = { Parent = { Kit = KIT, Net = NET } },
			require = function(target)
				if target == KIT then return Kit end
				if target == NET then return Net end
				local path = L.Paths[target]
				assert(path, "require of an unknown module")
				return L.Require((string.gsub(path, "/", ".")))
			end,
			task = sched.task,
			os = setmetatable({ clock = function() return sched.Now end, time = function() return math.floor(w.Now) end }, { __index = os }),
			Enum = roblox.Enum, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2, UDim = roblox.UDim, Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence, Random = L.Random,
			warn = function(...) table.insert(sched.Errors, "warn: " .. table.concat({ ... }, " ")) end,
			print = function() end,
		}, { __index = _G })
		env.S = luau.load(SCREEN, { debugName = "TradeScreen#" .. id, environment = sandbox })()
		env.S.Start()
		envs[id] = env
		return env
	end
	local a, b = load(1), load(2)
	-- Time moves for the server and both windows together; countdown labels fire when they end.
	local function advance(dt)
		sched.advance(dt, function()
			w.Now = T0 + sched.Now
			L.Time = math.floor(w.Now)
			for _, env in ipairs({ a, b }) do
				for _, c in ipairs(env.Countdowns) do
					if c.EndsAt and not c.Done and c.EndsAt <= w.Now then
						c.Done = true
						if c.Props.OnDone then sched.spawn(c.Props.OnDone) end
					end
				end
			end
		end)
		server.Flush()
	end
	return w, a, b, advance, sched
end
local function lastToast(env, needle)
	for i = #env.Toasts, 1, -1 do
		if string.find(env.Toasts[i].Text, needle, 1, true) then return env.Toasts[i] end
	end
	return nil
end
local function noErrors(sched)
	if #sched.Errors > 0 then error("window errors:\n  " .. table.concat(sched.Errors, "\n  ")) end
end

test("window: invite popup, accept, picker, value check, READY, countdown, hold to confirm", function()
	local w, a, b, advance, sched = clients()
	-- Ann opens TRADE: the lobby lists Bob with an enabled TRADE button.
	a.S.Open()
	noErrors(sched)
	truthy(a.Win and a.Win.IsOpen, "Ann's window is open")
	local st = a.S._State
	eq(#st.PlayerRows, 1, "Bob listed")
	-- Invite with the row's TRADE button.
	local u = a.S._UI()
	local cell = u.Players:Cell(1)
	truthy(cell and cell.Item and cell.Item.Id == 2, "Bob's row is bound")
	eq(cell.Button.Text, "TRADE", "TRADE button")
	eq(cell.Button.Disabled, false, "enabled")
	truthy(cell.Button:Click(), "clicked")
	noErrors(sched)
	truthy(lastToast(a, "Invitation sent to Bob"), "sender toast")
	eq(w.Engine.TradeByUser[2], nil, "Bob is not locked")
	-- Bob's window is closed: he gets a popup, not a window.
	eq(b.Win, nil, "no forced window for Bob")
	local banner = b.S._Banner()
	truthy(banner and banner.Root.Visible, "invite popup shown")
	eq(banner.Title.Text, "Ann wants to trade", "popup title")
	-- Ann's row now offers CANCEL (withdraw) and shows the time left.
	cell = u.Players:Cell(1)
	eq(cell.Button.Text, "CANCEL", "sent")
	-- Bob accepts from the popup: both windows show the session.
	truthy(banner.Yes:Click(), "accept")
	noErrors(sched)
	truthy(b.Win and b.Win.IsOpen, "Bob's window opened after accepting")
	truthy(w.Engine.TradeByUser[1] and w.Engine.TradeByUser[2], "session started")
	truthy(a.S._State.Trade and b.S._State.Trade, "both windows hold the session")
	local ua, ub = a.S._UI(), b.S._UI()
	eq(ua.Session.Visible, true, "Ann sees the session")
	eq(ub.Session.Visible, true, "Bob sees the session")
	eq(ua.Center.Main.Text, "ADD SOMETHING", "empty trade")
	eq(ua.Center.Main.Disabled, true, "nothing to accept yet")
	-- Bob picks a dog (Legendary) in the picker: the draft shows at once, one request after the pause.
	local pick = ub.Picker.Grid:Cell(1)
	truthy(pick and pick.Item.Kind == "Dog", "dog card")
	pick.Card:Click()
	eq(ub.Center.Main.Text, "SAVING…", "saving")
	advance(0.5)
	noErrors(sched)
	eq(#w.View(2).Offers["2"].Dogs, 1, "Bob's dog is in the server offer")
	truthy(lastToast(a, "Bob changed the offer"), "Ann told live")
	eq(#ua.Get.Grid.Items, 1, "Ann's GET column shows it")
	-- Ann: the locked dog is refused in the window with its reason.
	local lockedCell = nil
	for i = 1, #ua.Picker.Grid.Items do
		local c = ua.Picker.Grid:Cell(i)
		if c.Item.Uids[1] == "alocked" then lockedCell = c end
	end
	truthy(lockedCell and lockedCell.Item.Card.Disabled, "locked dog disabled")
	lockedCell.Card:Click()
	truthy(lastToast(a, "Locked: unlock it"), "reason shown")
	-- Ann adds two identical finds with the stepper and 1.5k coins.
	ua.Picker.Tabs:Select("items")
	noErrors(sched)
	local group = ua.Picker.Grid:Cell(1)
	truthy(group and group.Item.Stepper and group.Item.Stepper.Of == 3, "3 identical finds grouped")
	group.Plus:Click()
	group = ua.Picker.Grid:Cell(1)
	group.Plus:Click()
	group = ua.Picker.Grid:Cell(1)
	eq(group.Amount.Text, "2/3", "stepper count")
	ua.Give.CashBox.Text = "1.5k"
	ua.Give.CashBox.FocusLost:Fire()
	advance(0.5)
	noErrors(sched)
	local offer = w.View(1).Offers["1"]
	eq(#offer.Items, 2, "two finds offered")
	eq(offer.Cash, 1500, "1.5k parsed")
	-- The cheapest copies go first (your best copy stays).
	truthy(not table.find(offer.Items, "ai3"), "the heaviest copy stayed home")
	eq(#ua.Give.Grid.Items, 1, "identical finds are one card")
	eq(ua.Give.Grid.Items[1].Card.Count, 2, "x2")
	-- Value check: Ann gives coins and junk for a Legendary.
	eq(ua.Center.Verdict.Text, "YOU GET MUCH MORE", "Ann's verdict")
	eq(ub.Center.Verdict.Text, "YOU GIVE MUCH MORE", "Bob's verdict")
	-- READY after the review pause, on both sides.
	eq(ua.Center.Main.Text, "CHECK THE OFFER…", "review pause")
	advance(2.1)
	eq(ua.Center.Main.Text, "READY", "READY")
	truthy(ua.Center.Main:Click(), "Ann READY")
	noErrors(sched)
	eq(ua.Center.Main.Text, "WAITING FOR BOB", "waiting for Bob")
	truthy(ub.Center.Main:Click(), "Bob READY")
	noErrors(sched)
	eq(ua.Center.Main.Text, "SAFETY CHECK…", "countdown")
	eq(ua.Center.Main.Disabled, true, "confirm locked during the countdown")
	advance(TR.ConfirmDelay + 0.1)
	noErrors(sched)
	eq(ua.Center.Main.Text, "HOLD TO CONFIRM", "confirm unlocked")
	eq(ua.Center.Main.Props.Hold, 1, "hold-to-confirm 1 s")
	-- Ann confirms (no summary: she gets more); Bob gives a Legendary: summary modal first.
	truthy(ua.Center.Main:Click(), "Ann confirms")
	noErrors(sched)
	eq(#a.Modals, 0, "no summary for Ann")
	truthy(lastToast(b, "Ann confirmed"), "Bob told")
	truthy(ub.Center.Main:Click(), "Bob holds")
	eq(#b.Modals, 1, "summary modal for Bob")
	local modal = b.Modals[1]
	eq(modal.Opts.Danger, true, "held confirm in the summary")
	truthy(#modal.Opts.Cards == 2, "both sides listed: " .. #modal.Opts.Cards)
	modal.Fn(true)
	noErrors(sched)
	-- Done: profiles swapped, both back in the lobby, celebration toast.
	eq(w.Profile(1).Dogs.b1 and w.Profile(1).Dogs.b1.OwnerUserId, 1, "Ann got the Legendary")
	eq(w.Profile(2).Items.ai1.OwnerUserId, 2, "Bob got a find")
	eq(a.S._State.Trade, nil, "Ann's session closed")
	eq(b.S._State.Trade, nil, "Bob's session closed")
	eq(ua.Lobby.Visible, true, "back to the lobby")
	truthy(lastToast(a, "Trade complete"), "success toast")
	truthy(lastToast(b, "Trade complete"), "success toast 2")
	advance(30)
	noErrors(sched)
end)

test("window: decline, cooldown on the button, phone layouts and Russian", function()
	local w, a, b, advance, sched = clients()
	a.S.Open()
	b.S.Open()
	local ua, ub = a.S._UI(), b.S._UI()
	ua.Players:Cell(1).Button:Click()
	noErrors(sched)
	-- Bob has the window open: the invitation is in his INVITATIONS list.
	eq(#ub.Invites.Items, 1, "listed for Bob")
	truthy(lastToast(b, "Ann wants to trade"), "Bob told")
	ub.Invites:Cell(1).No:Click()
	noErrors(sched)
	truthy(lastToast(a, "Bob declined your invitation"), "Ann told")
	local cell = ua.Players:Cell(1)
	eq(cell.Button.Disabled, true, "cooldown")
	truthy(string.find(cell.Button.Text, "WAIT", 1, true), "WAIT on the button: " .. cell.Button.Text)
	advance(TR.InviteCooldown + 1)
	noErrors(sched)
	cell = ua.Players:Cell(1)
	eq(cell.Button.Text, "TRADE", "TRADE again after the cooldown")
	-- Phones and Russian: build a session and lay it out every way.
	cell.Button:Click()
	ub.Players:Cell(1).Button:Click() -- Bob answers with ACCEPT on Ann's row
	noErrors(sched)
	truthy(w.Engine.TradeByUser[1], "session")
	for _, layout in ipairs({ PORTRAIT, LANDSCAPE, DESKTOP }) do
		a.Layout, b.Layout = layout, layout
		a.Win.Resized:Fire(layout)
		b.Win.Resized:Fire(layout)
		noErrors(sched)
	end
	a.Lang = "ru"
	a.S._UI().Picker.Tabs:Select("items")
	advance(1)
	noErrors(sched)
	eq(a.S._UI().Center.Main.Text, "ДОБАВЬ ЧТО-НИБУДЬ", "Russian main button")
	-- Bob leaves: Ann is told and returns to the lobby.
	w.Online[2] = false
	w.Engine:Leave(2)
	advance(0.1)
	noErrors(sched)
	eq(a.S._State.Trade, nil, "session gone")
	truthy(lastToast(a, "Bob"), "told about Bob")
end)

print(string.format("trade: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("trade tests failed")
end
