--!nocheck
--!nolint
-- Trade hotfix (docs/overhaul/F06_trade.md, phase 0) on the REAL Runtime / Engine
-- (tests/lib/server_world, memory store): lune run tests/trade_hotfix.luau
--  * the Confirm/Offer race: the final Confirm waits on PolicyService (a paid-random dog is in the
--    trade); an Offer sent meanwhile must not change what is committed;
--  * Committing is cleared on every exit; a repeated Ready never restarts the review timer;
--  * trade steps refresh only the two participants (not every player of the server).
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
local function request(W, player, args)
	local ok, result = W.Request(player, "Trade", args)
	assert(ok, "Trade " .. tostring(args.Action) .. ": " .. tostring(result))
	return result
end

-- Players 1 (A, offers a paid-random dog) and 2 (B, offers 1000 Cash), past the trade level,
-- invited, accepted, both offers in and both locked; the review delay has passed and A confirmed.
-- Player 3 is a bystander.
local function ready()
	local policy = { Delay = 0, Trading = true }
	local W = World.new({
		Policy = function()
			if policy.Delay > 0 then
				task.wait(policy.Delay)
			end
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = policy.Trading }
		end,
	})
	local R, L = W.Rules, W.L
	local level = L.Require("ReplicatedStorage/DogEconomy/Config").XPForLevel(6)
	local A, B, C = W.Join(1), W.Join(2), W.Join(3)
	for _, uid in { 1, 2, 3 } do
		W.Edit(uid, function(p)
			p.XP = level
			R.UpdateLevel(p)
			p.Cash = 5000
			if uid == 1 then
				local dog = R.Mint(p, "Breadog", "dogA", {}, L.Now, function() return 0.5 end, "Test", "Normal", true)
				dog.PaidRandom = true
			end
		end)
		W.Runtime.Refresh(W.List[uid])
	end
	assert(W.Request(A, "TradeRequest", { Target = 2 }))
	request(W, B, { Action = "Accept" })
	request(W, A, { Action = "Offer", Dogs = { "dogA" }, Items = {}, Cash = 0 })
	request(W, B, { Action = "Offer", Dogs = {}, Items = {}, Cash = 1000 })
	local t = W.Engine.Trades[W.Engine.TradeByUser[1]]
	L.Now += 3
	request(W, A, { Action = "Ready", Version = t.Version })
	request(W, B, { Action = "Ready", Version = t.Version })
	L.Now += 9
	eq(request(W, A, { Action = "Confirm", Version = t.Version }).Message, "Waiting for final confirmation")
	-- The next policy lookup goes to (the yielding) PolicyService again.
	L.Require("ServerScriptService/Economy/PaidRandomPolicy").Cache = {}
	return W, A, B, C, t, policy
end

test("an Offer sent while the final Confirm waits on PolicyService changes nothing", function()
	local W, A, B, _, t, policy = ready()
	local version = t.Version
	local cashA, cashB = W.Profile(1).Cash, W.Profile(2).Cash
	policy.Delay = 0.3
	local done, confirmed, result = false, nil, nil
	task.spawn(function()
		confirmed, result = W.Request(B, "Trade", { Action = "Confirm", Version = version })
		done = true
	end)
	task.wait(0.05)
	local waiting, committing = not done, t.Committing
	-- While B's confirm waits, B tries to take the Cash back.
	local offered, refusal = W.Request(B, "Trade", { Action = "Offer", Dogs = {}, Items = {}, Cash = 0 })
	local deadline = os.clock() + 5
	while not done and os.clock() < deadline do
		task.wait(0.02)
	end
	truthy(done, "the confirm finished")
	-- What was committed is what both players reviewed (before the fix: A lost the dog for 0 Cash).
	eq(W.Profile(1).Cash, cashA + 1000, "A got exactly the reviewed Cash")
	eq(W.Profile(2).Cash, cashB - 1000)
	truthy(W.Profile(2).Dogs.dogA and not W.Profile(1).Dogs.dogA, "B got the dog")
	eq(W.Profile(2).Dogs.dogA.OwnerUserId, 2)
	truthy(confirmed, tostring(result))
	eq(result.Message, "Trade completed")
	eq(offered, false, "the offer during the commit is refused")
	eq(refusal, "Trade is committing")
	truthy(waiting and committing == true, "the commit was marked before it waited on PolicyService")
	eq(t.Version, version, "the reviewed version stands")
	eq(t.Committing, false)
	eq(W.Engine.TradeByUser[1], nil, "the trade is closed")
	eq(W.Engine.TradeByUser[2], nil)
end)

test("Committing is cleared when the commit is refused", function()
	local W, A, B, _, t, policy = ready()
	policy.Trading = false
	local ok, result = W.Request(B, "Trade", { Action = "Confirm", Version = t.Version })
	eq(ok, false)
	truthy(tostring(result):find("Paid-item trading is unavailable", 1, true), tostring(result))
	eq(t.Committing, false)
	eq(W.Profile(1).Dogs.dogA.OwnerUserId, 1, "nothing moved")
	-- The trade is usable again: a new offer, or a cancel.
	ok, result = W.Request(A, "Trade", { Action = "Offer", Dogs = {}, Items = {}, Cash = 0 })
	truthy(ok, tostring(result))
	truthy(W.Request(A, "TradeCancel", {}))
	eq(W.Engine.TradeByUser[1], nil)
end)

test("a trade that expires while the commit waits on PolicyService moves nothing", function()
	local W, _, B, _, t, policy = ready()
	policy.Delay = 0.3
	local done, ok, result = false, nil, nil
	task.spawn(function()
		ok, result = W.Request(B, "Trade", { Action = "Confirm", Version = t.Version })
		done = true
	end)
	task.wait(0.05)
	W.L.Now = t.Expires + 1
	local deadline = os.clock() + 5
	while not done and os.clock() < deadline do
		task.wait(0.02)
	end
	eq(ok, false)
	eq(result, "Trade expired")
	eq(t.Committing, false)
	eq(W.Profile(1).Dogs.dogA.OwnerUserId, 1, "nothing moved")
	eq(W.Profile(2).Cash, 5000)
end)

test("a repeated Ready at the same version never restarts the review timer", function()
	local W = World.new()
	local R, L = W.Rules, W.L
	local level = L.Require("ReplicatedStorage/DogEconomy/Config").XPForLevel(6)
	local A, B = W.Join(1), W.Join(2)
	for _, uid in { 1, 2 } do
		W.Edit(uid, function(p)
			p.XP = level
			R.UpdateLevel(p)
			p.Cash = 5000
		end)
		W.Runtime.Refresh(W.List[uid])
	end
	assert(W.Request(A, "TradeRequest", { Target = 2 }))
	request(W, B, { Action = "Accept" })
	request(W, A, { Action = "Offer", Dogs = {}, Items = {}, Cash = 10 })
	request(W, B, { Action = "Offer", Dogs = {}, Items = {}, Cash = 20 })
	local t = W.Engine.Trades[W.Engine.TradeByUser[1]]
	L.Now += 3
	request(W, A, { Action = "Ready", Version = t.Version })
	request(W, B, { Action = "Ready", Version = t.Version })
	local confirmAfter = t.ConfirmAfter
	truthy(confirmAfter, "review started")
	L.Now += 5
	request(W, A, { Action = "Ready", Version = t.Version })
	request(W, B, { Action = "Ready", Version = t.Version })
	eq(t.ConfirmAfter, confirmAfter, "not restarted")
	L.Now += 3
	eq(request(W, A, { Action = "Confirm", Version = t.Version }).Message, "Waiting for final confirmation", "on time")
	eq(request(W, B, { Action = "Confirm", Version = t.Version }).Message, "Trade completed")
	-- A changed offer still resets the review (Offer clears Ready and ConfirmAfter).
	assert(W.Request(A, "TradeRequest", { Target = 2 }))
	request(W, B, { Action = "Accept" })
	request(W, A, { Action = "Offer", Dogs = {}, Items = {}, Cash = 1 })
	t = W.Engine.Trades[W.Engine.TradeByUser[1]]
	eq(t.ConfirmAfter, nil)
end)

test("trade steps refresh only the two participants", function()
	local W, A, B = ready()
	local counts = {}
	local project = W.Runtime.Project
	W.Runtime.Project = function(player, p)
		counts[player.UserId] = (counts[player.UserId] or 0) + 1
		return project(player, p)
	end
	local t = W.Engine.Trades[W.Engine.TradeByUser[1]]
	W.Request(B, "Trade", { Action = "Confirm", Version = t.Version })
	eq(counts[1], 1, "A refreshed")
	eq(counts[2], 1, "B refreshed")
	eq(counts[3], nil, "the bystander is not")
	eq(W.Runtime.Views[1].Cash, W.Profile(1).Cash, "A's view shows the commit")
	-- A refused step (expired trade) refreshes nobody.
	table.clear(counts)
	local ok = W.Request(A, "Trade", { Action = "Ready", Version = 1 })
	eq(ok, false)
	eq(next(counts), nil)
	W.Runtime.Project = project
end)

print(("trade_hotfix: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
