--!nocheck
--!nolint
-- Robux receipts, game passes and profile durability: lune run tests/payments.luau
-- Runs the REAL Economy modules (PurchaseService, CommerceProducts, RoulettePurchases,
-- SupportReceipts, Transactions, Engine, Rules, LuckRules, ServerLuck, PaidRandomPolicy,
-- Features/Passes and the product configs) on a memory DataStore with fault injection and
-- stub MarketplaceService / PolicyService / Players. No real purchases are made.
local task = require("@lune/task")
local L = require("./payments_lib/loader")

local GRANTED = "Enum.ProductPurchaseDecision.PurchaseGranted"
local PENDING = "Enum.ProductPurchaseDecision.NotProcessedYet"
local ROBUX = "Enum.CurrencyType.Robux"
local BUSY = "Account is busy; retry shortly"

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

-- ===== Memory DataStore with latency and faults, wrapped like Runtime's retry store =====
local function newStore()
	local raw = { Data = {}, Down = false, Latency = 0, Reads = 0, Updates = 0, Hook = nil, FailAfterWrite = 0 }
	function raw:Read(k)
		if self.Latency > 0 then
			task.wait(self.Latency)
		end
		if self.Down then
			error("DataStore 502 (injected)")
		end
		self.Reads += 1
		return copy(self.Data[k])
	end
	function raw:Update(k, fn)
		if self.Latency > 0 then
			task.wait(self.Latency)
		end
		if self.Down then
			error("DataStore 502 (injected)")
		end
		self.Updates += 1
		local v = fn(copy(self.Data[k]))
		if v ~= nil then
			self.Data[k] = copy(v)
		end
		if self.Hook then
			self.Hook(k, v)
		end
		-- The write landed but the reply is lost (the caller sees an error).
		if self.FailAfterWrite > 0 and k:sub(1, 2) == "p:" then
			self.FailAfterWrite -= 1
			error("DataStore reply lost (injected)")
		end
		return copy(v)
	end
	local store = { Raw = raw }
	local function retry(fn)
		local last
		for _ = 1, 3 do
			local ok, v = pcall(fn)
			if ok then
				return v
			end
			last = v
		end
		error("DataStore unavailable: " .. tostring(last))
	end
	function store:Read(k)
		return retry(function()
			return raw:Read(k)
		end)
	end
	function store:Update(k, fn)
		return retry(function()
			return raw:Update(k, fn)
		end)
	end
	return store
end

-- ===== A world: real modules, one server session, stub Roblox services =====
local guidCount = 0
local function guid()
	guidCount += 1
	return string.format("%032x", guidCount)
end

local function world(opts)
	opts = opts or {}
	L.Reset()
	L.Now = opts.Now or 1800000000
	local playersService = L.Instance("Players")
	playersService.PlayerAdded = L.Signal()
	playersService.PlayerRemoving = L.Signal()
	local list = {}
	playersService.GetPlayerByUserId = function(_, id)
		local p = list[id]
		if p and p.Parent then
			return p
		end
		return nil
	end
	playersService.GetPlayers = function()
		local out = {}
		for _, p in list do
			if p.Parent then
				table.insert(out, p)
			end
		end
		return out
	end
	L.Services.Players = playersService
	L.Services.RunService = { IsStudio = function() return false end, IsServer = function() return true end }
	L.Services.HttpService = { GenerateGUID = function() return guid() end, JSONEncode = function() return "{}" end }
	local market = { PromptGamePassPurchaseFinished = L.Signal(), OwnsCalls = 0, Owned = {}, OwnsErrors = 0 }
	function market:UserOwnsGamePassAsync(userId, passId)
		self.OwnsCalls += 1
		if self.OwnsErrors > 0 then
			self.OwnsErrors -= 1
			error("HTTP 500 (injected)")
		end
		if self.OwnsAlwaysError then
			error("HTTP 500 (injected)")
		end
		return self.Owned[passId] == true
	end
	function market:GetDeveloperProductsAsync()
		error("stub: no web access")
	end
	function market:GetProductInfoAsync(id)
		return { IsForSale = true, PriceInRobux = 1, Name = tostring(id) }
	end
	L.Services.MarketplaceService = market
	local policy = { Calls = 0, Restricted = false, Fail = false }
	function policy:GetPolicyInfoForPlayerAsync()
		self.Calls += 1
		if self.Fail then
			error("policy lookup failed (injected)")
		end
		return { ArePaidRandomItemsRestricted = self.Restricted, IsPaidItemTradingAllowed = not self.Restricted }
	end
	L.Services.PolicyService = policy
	local RS = L.Node("ReplicatedStorage")
	local presentation = L.Instance("RemoteEvent")
	presentation.Name = "RewardPresentation"
	presentation.Parent = RS

	local Tx = L.Require("ServerScriptService/Economy/Transactions")
	local Engine = L.Require("ServerScriptService/Economy/Engine")
	local store = opts.Store or newStore()
	local clock = function()
		return L.Now
	end
	local tx = Tx.new(store, clock, guid, { LockWait = opts.LockWait or 12 })
	local runtime = { Tx = tx, Loaded = {}, Views = {}, Closing = false, Refreshes = 0 }
	local session = opts.Session or "S1"
	runtime.Engine = Engine.new(tx, {
		Now = clock,
		Guid = guid,
		Random = function()
			return 0.5
		end,
		Session = session,
		Connected = function(id)
			local p = list[id]
			return p ~= nil and p.Parent ~= nil and not runtime.Closing
		end,
		AssetReady = function()
			return true
		end,
	})
	function runtime.Ready(player)
		return runtime.Loaded[player.UserId] == true and not runtime.Closing
	end
	function runtime.Refresh(player)
		runtime.Refreshes += 1
		if runtime.FailRefresh then
			error("refresh exploded (injected)")
		end
	end
	local W = { L = L, Store = store, Tx = tx, Runtime = runtime, Engine = runtime.Engine, Market = market, Policy = policy, Players = list, RS = RS }
	function W.AddPlayer(uid)
		local p = L.Instance("Player")
		p.Name = "Player" .. uid
		p.UserId = uid
		p.DisplayName = "Tester" .. uid
		p.Parent = playersService
		list[uid] = p
		return p
	end
	function W.Join(uid)
		local ok, result = runtime.Engine:Join(uid)
		assert(ok, "join failed: " .. tostring(result))
		runtime.Loaded[uid] = true
		return ok
	end
	function W.Profile(uid)
		return tx.Cache["p:" .. uid]
	end
	function W.Stored(uid)
		local record = store.Raw.Data["p:" .. uid]
		return record and record.Value
	end
	function W.Receipt(uid, productId, purchaseId, spent)
		return { PlayerId = uid, ProductId = productId, PurchaseId = purchaseId, CurrencyType = ROBUX, CurrencySpent = spent or 10 }
	end
	W.PS = L.Require("ServerScriptService/Economy/PurchaseService")
	W.PS.ProfileWait, W.PS.QueueWait, W.PS.LockWait, W.PS.PassRetryDelay = 5, 20, 20, 0.01
	W.ServerLuck = L.Require("ServerScriptService/Economy/ServerLuck")
	W.Rules = L.Require("ServerScriptService/Economy/Rules")
	W.Luck = L.Require("ServerScriptService/Economy/LuckRules")
	return W
end

local function enabledProducts(W)
	local rows, seen = {}, {}
	local function add(source, row)
		if type(row.Id) == "number" and row.Id > 0 and row.Enabled ~= false and not seen[row.Id] then
			seen[row.Id] = true
			table.insert(rows, { Source = source, Row = row })
		end
	end
	for _, row in L.Require("ReplicatedStorage/CommerceConfig").Products do
		if row.Enabled == true then
			add("CommerceConfig", row)
		end
	end
	for _, row in L.Require("ReplicatedStorage/RewardMachineConfig").TicketProducts or {} do
		if row.Enabled == true then
			add("RewardMachineConfig", row)
		end
	end
	for _, row in L.Require("ReplicatedStorage/LuckyBlockConfig").RobuxProducts or {} do
		add("LuckyBlockConfig", row)
	end
	for _, row in L.Require("ReplicatedStorage/DogEconomy/ShopDefinitions") do
		if row.Kind == "Product" then
			add("ShopDefinitions", row)
		end
	end
	return rows
end

-- ===== 1. One product index: every enabled ID resolves to exactly one grant =====
test("every enabled product id resolves to exactly one grant", function()
	local W = world()
	local index = W.PS.BuildIndex()
	eq(#index.Problems, 0, "index problems: " .. table.concat(index.Problems, "; "))
	local count = 0
	for _, row in L.Require("ReplicatedStorage/CommerceConfig").Products do
		if row.Enabled == true and row.Id > 0 then
			local entry = index.ById[row.Id]
			truthy(entry and not entry.Ambiguous, row.Key .. " does not resolve")
			truthy(W.PS.Handlers[entry.Kind], "no handler for " .. tostring(entry.Kind))
			-- Alias rows that repeat their offer's ID grant the offer itself.
			eq(entry.Product.Key, row.Alias or row.Key, row.Key)
			count += 1
		end
	end
	for _, row in L.Require("ReplicatedStorage/RewardMachineConfig").TicketProducts do
		if row.Enabled == true and row.Id > 0 then
			local entry = index.ById[row.Id]
			truthy(entry and not entry.Ambiguous and entry.Kind == "Tickets", row.Key)
			count += 1
		end
	end
	truthy(count >= 20, "expected the live catalog, got " .. count)
	truthy(W.PS.Configured(3717327335) and W.PS.Configured(3717453336), "starter kit ids must be configured")
	truthy(W.PS.Configured(), "Configured() with no id")
	truthy(not W.PS.Configured(123), "unknown id must not be configured")
end)

test("an id shared by two different offers is never granted", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	W.PS.RegisterCatalog({ Kind = "Test", Source = "TestConfig", Rows = function()
		return { { Key = "Bogus", Id = 3717462952 } }
	end }, { Grant = function(p)
		p.Bones += 999999
		return "bogus"
	end })
	local index = W.PS.BuildIndex()
	eq(#index.Problems, 1, "problems")
	truthy(not W.PS.Configured(3717462952), "ambiguous id must not count as configured")
	local before = copy(W.Profile(1))
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717462952, "AMB-1")), PENDING)
	eq(W.Profile(1).Bones, before.Bones, "bones")
	eq(W.Profile(1).Cash, before.Cash, "cash")
	eq(W.Store.Raw.Data["purchase:AMB-1"], nil, "no purchase mark")
	-- Unknown product: pending as well, with a loud log line.
	eq(W.PS.HandleReceipt(W.Receipt(1, 42, "UNKNOWN-1")), PENDING)
	local logged = false
	for _, line in L.Warnings do
		if line:find("unknown product ID", 1, true) then
			logged = true
		end
	end
	truthy(logged, "unknown product must be logged")
end)

-- ===== 2. Every enabled product is delivered once; re-delivery never grants twice =====
test("every enabled product id is granted, counted and never granted twice", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	local n = 0
	for _, item in enabledProducts(W) do
		n += 1
		local row = item.Row
		local before = copy(W.Profile(1))
		local purchaseId = "DISPATCH-" .. n
		local spent = 10 + n
		eq(W.PS.HandleReceipt(W.Receipt(1, row.Id, purchaseId, spent)), GRANTED, item.Source .. "." .. row.Key)
		local after = W.Profile(1)
		local mark = W.Store.Raw.Data["purchase:" .. purchaseId]
		truthy(mark and mark.Value and mark.Value.Counted == true and mark.Value.Amount == spent, "purchase mark for " .. row.Key)
		eq(after.Lifetime.SupportRobux, before.Lifetime.SupportRobux + spent, "supporter total " .. row.Key)
		-- The saved profile equals RAM: the grant is durable before PurchaseGranted.
		eq(W.Stored(1).Lifetime.SupportRobux, after.Lifetime.SupportRobux, "durable " .. row.Key)
		if item.Source == "RewardMachineConfig" then
			eq(after.PaidRouletteTickets, before.PaidRouletteTickets + row.Count, "tickets " .. row.Key)
		elseif row.Supply then
			truthy(W.L.Require("ServerScriptService/Economy/SupplyRules").EndAt(after, row.Supply) > W.L.Require("ServerScriptService/Economy/SupplyRules").EndAt(before, row.Supply), "supply " .. row.Key)
		else
			local rewards = row.Rewards
			if rewards.Bones then
				eq(after.Bones, before.Bones + rewards.Bones, "bones " .. row.Key)
			end
			if rewards.Coins or rewards.Cash then
				truthy(after.Cash > before.Cash, "coins " .. row.Key)
			end
			if rewards.Luck then
				truthy(W.Luck.EndAt(after, rewards.Luck.Tier) > W.Luck.EndAt(before, rewards.Luck.Tier), "luck " .. row.Key)
			end
			if rewards.ServerLuck then
				local credit = after.ServerLuckCredits["r:" .. purchaseId]
				truthy(credit and credit.Multiplier == rewards.ServerLuck.Multiplier, "server luck credit " .. row.Key)
				truthy(W.ServerLuck.Current() >= 2, "server luck active " .. row.Key)
			end
			if row.Once then
				truthy(after.CommercePurchases[row.Alias or row.Key], "once slot " .. row.Key)
			end
		end
		-- Roblox re-delivers the same receipt: acknowledged, nothing changes.
		local snapshot = copy(W.Profile(1))
		eq(W.PS.HandleReceipt(W.Receipt(1, row.Id, purchaseId, spent)), GRANTED, "redelivery " .. row.Key)
		local again = W.Profile(1)
		eq(again.Cash, snapshot.Cash, "redelivery cash " .. row.Key)
		eq(again.Bones, snapshot.Bones, "redelivery bones " .. row.Key)
		eq(again.PaidRouletteTickets, snapshot.PaidRouletteTickets, "redelivery tickets " .. row.Key)
		eq(again.Lifetime.SupportRobux, snapshot.Lifetime.SupportRobux, "redelivery supporters " .. row.Key)
	end
	truthy(n >= 20, "products tested: " .. n)
	-- The two starter kits that used to be stuck (duplicate IDs) are delivered.
	truthy(W.Profile(1).CommercePurchases.StarterScout and W.Profile(1).CommercePurchases.StarterExplorer, "starter kits delivered")
	-- Players see what arrived (token packs included).
	local tokenCue = false
	for _, f in L.Fired do
		if f.Remote == "RewardPresentation" and type(f.Payload) == "table" and type(f.Payload.Message) == "string" and f.Payload.Message:find("DOG TOKEN", 1, true) then
			tokenCue = true
		end
	end
	truthy(tokenCue, "token packs fire the reward cue")
end)

test("a receipt from the old code (no Counted flag) is acknowledged and counted once", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	-- Granted by the old code, but its second (supporter) transaction failed.
	W.Store.Raw.Data["purchase:LEGACY-1"] = { Revision = 1, Value = { Kind = "Commerce", User = 1, Product = 3717462952, At = 1, Result = { Message = "Pocket Change added" } } }
	local before = copy(W.Profile(1))
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717462952, "LEGACY-1", 19)), GRANTED)
	eq(W.Profile(1).Cash, before.Cash, "no second grant")
	eq(W.Profile(1).Lifetime.SupportRobux, before.Lifetime.SupportRobux + 19, "legacy count added once")
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717462952, "LEGACY-1", 19)), GRANTED)
	eq(W.Profile(1).Lifetime.SupportRobux, before.Lifetime.SupportRobux + 19, "legacy count not added twice")
end)

-- ===== 3. Receipt during profile load =====
test("a receipt that arrives while the profile loads is granted once it is loaded", function()
	local W = world()
	W.AddPlayer(1)
	W.PS.Start(W.Runtime)
	local decision
	task.spawn(function()
		decision = W.PS.HandleReceipt(W.Receipt(1, 3717461474, "LOAD-1"))
	end)
	task.wait(1)
	eq(decision, nil, "must wait for the profile")
	W.Join(1)
	local deadline = os.clock() + 5
	while decision == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	eq(decision, GRANTED)
	eq(W.Profile(1).PaidRouletteTickets, 5, "5 tokens")
	-- A buyer who leaves while loading: pending (Roblox retries on their next join), nothing granted.
	local p2 = W.AddPlayer(2)
	local second
	task.spawn(function()
		second = W.PS.HandleReceipt(W.Receipt(2, 3717461474, "LOAD-2"))
	end)
	task.wait(0.6)
	p2.Parent = nil
	deadline = os.clock() + 5
	while second == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	eq(second, PENDING)
	eq(W.Store.Raw.Data["purchase:LOAD-2"], nil, "nothing granted for the leaver")
end)

-- ===== 4. Concurrent receipts are serialized; the tick never throws =====
test("concurrent receipts of one player all arrive while ticks skip the busy profile", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	W.Store.Raw.Latency = 0.01
	local results, done = {}, 0
	for i = 1, 5 do
		task.spawn(function()
			results[i] = W.PS.HandleReceipt(W.Receipt(1, 3717461640, "BURST-" .. i, 100))
			done += 1
		end)
	end
	local ticks, threw, skipped = 0, nil, 0
	while done < 5 do
		local ok, a, b = pcall(W.Engine.TickAll, W.Engine, { 1 })
		if not ok then
			threw = a
		elseif b and b.Skipped and b.Skipped[1] then
			skipped += 1
		end
		ticks += 1
		task.wait(0.02)
	end
	eq(threw, nil, "TickAll threw")
	for i = 1, 5 do
		eq(results[i], GRANTED, "receipt " .. i)
	end
	eq(W.Profile(1).PaidRouletteTickets, 75, "5 x 15 tokens")
	eq(W.Profile(1).Lifetime.SupportRobux, 500, "supporter total")
	truthy(skipped > 0, "ticks skipped the busy profile")
	-- One durable transaction per receipt (was two): count the journals written.
	local journals = 0
	for key in W.Store.Raw.Data do
		if key:sub(1, 3) == "tx:" then
			journals += 1
		end
	end
	eq(journals, 5 + 1, "one journal per receipt (+ join)")
end)

-- ===== 5. Ambiguous commit: the grant must survive =====
local function commitFault(mode)
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	local raw = W.Store.Raw
	local armed = true
	raw.Hook = function(k, v)
		if armed and k:sub(1, 3) == "tx:" and type(v) == "table" and v.State == "Committed" and not v.Materialized and v.Writes and v.Writes["purchase:FAULT-1"] then
			armed = false
			raw.Down = true -- the commit record landed; DataStore goes down before the unlock writes
		end
	end
	local function play(cash)
		return W.Tx:Run({ "p:1" }, function(v)
			v["p:1"].Cash += cash
			return true
		end)
	end
	play(100)
	local bones0 = W.Profile(1).Bones
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717460798, "FAULT-1", 149)), PENDING, "first attempt")
	raw.Down = false
	L.Now += 30
	play(50) -- gameplay continues on RAM
	if mode == "autosave" then
		for _ = 1, 2 do
			L.Now += 60
			W.Tx:FlushProfile(1)
		end
	end
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717460798, "FAULT-1", 149)), GRANTED, "retry")
	L.Now += 60
	local ok = W.Tx:FlushProfile(1)
	truthy(ok, "final flush")
	eq(W.Profile(1).Bones, bones0 + 200, mode .. ": RAM keeps the grant")
	eq(W.Stored(1).Bones, bones0 + 200, mode .. ": DataStore keeps the grant")
	eq(W.Stored(1).Lifetime.SupportRobux, 149, mode .. ": counted once")
	-- More gameplay and saves never lose it again.
	play(5)
	L.Now += 60
	truthy(W.Tx:FlushProfile(1), "later flush")
	eq(W.Stored(1).Bones, bones0 + 200, mode .. ": still saved")
end
test("ambiguous commit then autosave keeps the paid grant", function()
	commitFault("autosave")
end)
test("ambiguous commit then immediate retry keeps the paid grant", function()
	commitFault("retry")
end)

-- ===== 6. A busy lock never throws; TickAll skips =====
test("a busy profile lock makes TickAll skip instead of throw, and Run returns false", function()
	local W = world({ LockWait = 0.3 })
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	W.Store.Raw.Latency = 0.08 -- a durable receipt now holds the lock for ~1 s
	local decision
	task.spawn(function()
		decision = W.PS.HandleReceipt(W.Receipt(1, 3717465311, "SLOW-1"))
	end)
	task.wait(0.05)
	truthy(W.Tx.Busy["p:1"], "the receipt holds the profile lock")
	local started = os.clock()
	local ok, ticked, result = pcall(W.Engine.TickAll, W.Engine, { 1 })
	truthy(ok, "TickAll threw: " .. tostring(ticked))
	truthy(ticked == true and result.Skipped[1] == true, "busy profile skipped")
	eq(next(result.Failed), nil, "a skip is not a failure")
	truthy(os.clock() - started < 0.1, "TickAll did not wait for the lock")
	-- A normal action waits LockWait and then returns (never throws).
	local called, runOk, message = pcall(W.Tx.Run, W.Tx, { "p:1" }, function()
		return true
	end)
	truthy(called, "Run threw")
	eq(runOk, false, "busy run")
	eq(message, BUSY, "busy message")
	while decision == nil do
		task.wait(0.05)
	end
	eq(decision, GRANTED, "slow receipt")
	W.Store.Raw.Latency = 0
	local _, tickedAfter, after = pcall(W.Engine.TickAll, W.Engine, { 1 })
	truthy(tickedAfter == true and not after.Skipped[1], "ticks resume once the lock is free")
end)

-- ===== 7. Transactions: stale saves are re-read, lost replies recognised =====
test("a foreign newer save is never overwritten: RAM re-reads it", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.Tx:Run({ "p:1" }, function(v)
		v["p:1"].Cash += 10
		return true
	end)
	-- Something else committed to the saved profile (e.g. a journal applied elsewhere).
	local record = W.Store.Raw.Data["p:1"]
	record.Value.Bones += 777
	record.Revision += 1
	local ok, note = W.Tx:FlushProfile(1)
	truthy(ok, "flush")
	eq(note, "Resynced", "resync reported")
	eq(W.Stored(1).Bones, W.Profile(1).Bones, "RAM adopted the saved profile")
	truthy(W.Stored(1).Bones >= 777, "foreign write kept")
end)

test("a save whose reply was lost is not mistaken for a foreign write", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.Tx:Run({ "p:1" }, function(v)
		v["p:1"].Cash += 10
		return true
	end)
	W.Store.Raw.FailAfterWrite = 1
	local ok, note = W.Tx:FlushProfile(1)
	truthy(ok, "flush")
	eq(note, nil, "no resync needed")
	eq(W.Stored(1).Cash, W.Profile(1).Cash, "saved")
	eq(W.Tx.Dirty["p:1"], nil, "clean")
end)

-- ===== 8. Paid luck reserve =====
test("paid luck beyond the active cap waits in LuckReserve and is never cut", function()
	local W = world()
	local Luck = W.Luck
	local now = L.Now
	local p = W.Rules.Profile(1, now)
	local finish = Luck.AddPaid(p, 5, 8 * 3600, now)
	eq(finish, now + 8 * 3600, "finish")
	eq(p.LuckBoosts["5"], now + Luck.PaidActiveCap, "active part")
	eq(p.LuckReserve["5"], 2 * 3600, "reserve part")
	eq(Luck.EndAt(p, 5), now + 8 * 3600, "EndAt counts the reserve")
	Luck.Normalize(p, now + 3600)
	eq(p.LuckBoosts["5"], now + 3600 + Luck.PaidActiveCap, "reserve feeds the timer")
	eq(p.LuckReserve["5"], 3600, "reserve shrinks")
	eq(Luck.EndAt(p, 5), now + 8 * 3600, "total time kept")
	eq(Luck.Active(p, now + 3600), 5, "tier active")
	truthy(not Luck.CanAdd(p, 5, now, 600), "coin luck cannot stack on stored paid time")
	Luck.AddPaid(p, 5, 18 * 3600, now + 3600)
	truthy(not Luck.CanAddPaid(p, 5, now + 3600, 3600), "prompt refuses past the store cap")
	-- Offline time counts down like before (active + reserve are one timeline).
	Luck.Normalize(p, now + 40 * 3600)
	eq(p.LuckBoosts["5"], nil, "expired")
	eq(p.LuckReserve["5"], nil, "reserve used up")
end)

test("a luck-only or server-luck-only offer is refused at the prompt when nothing fits", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	local Commerce = L.Require("ServerScriptService/Economy/CommerceProducts")
	local player = W.Players[1]
	truthy(pcall(Commerce.Product, W.Runtime, player, "LuckyServer"), "room: sold")
	eq(W.ServerLuck.Add(5, 7200, "Someone"), 7200, "fill the pool")
	local ok, err = pcall(Commerce.Product, W.Runtime, player, "LuckyServer")
	eq(ok, false, "full pool refuses")
	truthy(tostring(err):find("Server luck is at its limit", 1, true), tostring(err))
	-- Bundles with coins are always sold; their luck parts are kept, never cut.
	truthy(pcall(Commerce.Product, W.Runtime, player, "TurboDigKit"), "bundle still sold")
end)

-- ===== 9. Paid server luck survives a shutdown and restarts elsewhere =====
test("paid server luck is a saved credit: queued, released on shutdown, restarted on the next server", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	eq(W.ServerLuck.Add(5, 7000, "Someone"), 7000, "pool nearly full")
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717458296, "MAX-1", 2999)), GRANTED, "MAX LUCK")
	local credit = W.Profile(1).ServerLuckCredits["r:MAX-1"]
	truthy(credit, "credit saved")
	eq(credit.Queued, 1600, "what did not fit waits")
	eq(credit.Active, 200, "what fit is running")
	eq(credit.Server, "S1", "running on this server")
	truthy(W.Stored(1).ServerLuckCredits["r:MAX-1"], "credit is durable with the receipt")
	-- 100 s later the server shuts down: the unused running time goes back to the credit.
	L.Now += 100
	W.ServerLuck.Release(W.Runtime, 1, true)
	W.Engine:Leave(1)
	truthy(W.Tx:FlushProfile(1), "shutdown save")
	local saved = W.Stored(1).ServerLuckCredits["r:MAX-1"]
	truthy(saved and saved.Queued == 1600 and saved.Active > 0 and saved.Active <= 200, "remaining time saved")
	-- A new server (fresh memory, same DataStore): the buyer joins and the credit restarts.
	local store = W.Store
	local W2 = world({ Store = store, Session = "S2", Now = L.Now + 10 })
	W2.AddPlayer(1)
	W2.Join(1)
	W2.ServerLuck.ActivateFor(W2.Runtime, W2.Players[1])
	local row = W2.Profile(1).ServerLuckCredits["r:MAX-1"]
	eq(row.Queued, 0, "everything restarted")
	eq(row.Server, "S2", "now running on the new server")
	eq(W2.ServerLuck.Current(), 5, "x5 server luck active again")
	-- The buyer leaves normally: their running time stays with that server's players.
	W2.ServerLuck.Release(W2.Runtime, 1, false)
	eq(W2.Profile(1).ServerLuckCredits["r:MAX-1"], nil, "credit handed to the server")
end)

-- ===== 10. Mega Reset never wipes paid data =====
test("a Mega Reset carries everything bought with Robux", function()
	local W = world()
	local R = W.Rules
	local now = L.Now
	local old = R.Profile(1, now)
	old.MegaResetVersion = 0
	old.Cash = 123456
	old.PaidRouletteTickets = 42
	old.CommercePurchases = { StarterScout = 1 }
	old.LuckReserve = { ["5"] = 3600 }
	old.ServerLuckCredits = { ["r:X"] = { Multiplier = 3, Queued = 900, Active = 0, At = 1 } }
	old.Passes = { ["999"] = true }
	old.Cosmetics.SupporterTitle = true
	old.Lifetime.SupportRobux = 500
	local fresh = R.Normalize(old, 1, now)
	truthy(fresh ~= old, "reset ran")
	eq(fresh.PaidRouletteTickets, 42, "tokens")
	truthy(fresh.CommercePurchases.StarterScout, "packs")
	-- The carried reserve feeds the luck timer at once (nothing is lost on the way).
	eq(W.Luck.EndAt(fresh, 5), now + 3600, "paid luck time")
	truthy(fresh.ServerLuckCredits["r:X"], "server luck credit")
	truthy(fresh.Passes["999"], "passes")
	truthy(fresh.Cosmetics.SupporterTitle, "cosmetics")
	eq(fresh.Lifetime.SupportRobux, 500, "supporter total")
	truthy(fresh.Cash ~= 123456, "progress itself was reset")
	eq(L.Require("ServerScriptService/Economy/Config").MegaResetVersion, 1, "MegaResetVersion untouched")
end)

-- ===== 11. Game passes are entitlements =====
test("game pass ownership is synced idempotently and never revoked on a failed query", function()
	local W = world()
	local Definitions = L.Require("ReplicatedStorage/DogEconomy/ShopDefinitions")
	for _, row in Definitions do
		if row.Kind == "Pass" then
			row.Id = 999
		end
	end
	local player = W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	W.Market.Owned[999] = true
	W.Market.OwnsErrors = 1 -- first query fails, the retry succeeds
	local ok = W.PS.SyncPasses(W.Runtime, player)
	truthy(ok, "sync")
	eq(W.Profile(1).Passes["999"], true, "entitled")
	truthy(W.Profile(1).Cosmetics.VoidAura, "benefit applied")
	truthy(W.PS.SyncPasses(W.Runtime, player), "second sync is idempotent")
	-- Roblox cannot be asked: nothing is revoked.
	W.Market.OwnsAlwaysError = true
	W.PS.SyncPasses(W.Runtime, player)
	eq(W.Profile(1).Passes["999"], true, "kept after failed query")
	-- Benefits follow ownership even if the cosmetic was lost.
	W.Tx:Run({ "p:1" }, function(v)
		v["p:1"].Cosmetics.VoidAura = nil
		W.Rules.Normalize(v["p:1"], 1, L.Now)
		return true
	end)
	truthy(W.Profile(1).Cosmetics.VoidAura, "benefit re-derived by Normalize")
	-- Old numeric keys are converted, never dropped.
	local p = W.Rules.Profile(2, L.Now)
	p.Passes = { [999] = true }
	W.Rules.Normalize(p, 2, L.Now)
	eq(p.Passes["999"], true, "numeric key converted")
	eq(p.Passes[999], nil, "numeric key removed")
	for _, row in Definitions do
		if row.Kind == "Pass" then
			row.Id = 0
		end
	end
end)

-- ===== 12. One paid-random policy =====
test("paid random items: one cached PolicyService answer for every caller", function()
	local W = world()
	local player = W.AddPlayer(1)
	W.Join(1)
	local Policy = L.Require("ServerScriptService/Economy/PaidRandomPolicy")
	local Tickets = L.Require("ServerScriptService/Economy/RoulettePurchases")
	local Rewards = L.Require("ServerScriptService/Economy/RewardService")
	local Trading = L.Require("ServerScriptService/Economy/PaidItemPolicy")
	truthy(Tickets.Allowed(player), "allowed")
	truthy(Rewards.Policy(player), "lucky blocks use the same answer")
	truthy(Trading.Allowed(1), "trading uses the same answer")
	eq(W.Policy.Calls, 1, "one PolicyService request")
	-- Restricted accounts: the prompt is refused with a reason.
	Policy.Forget(player)
	W.Policy.Restricted = true
	local ok, err = pcall(Tickets.Product, player, "TicketPack5")
	eq(ok, false, "restricted")
	truthy(tostring(err):find("Unavailable for this account", 1, true), tostring(err))
	-- A failed lookup counts as not allowed and is asked again later.
	Policy.Forget(player)
	W.Policy.Restricted = false
	W.Policy.Fail = true
	eq(Policy.Allowed(player), false, "failure = not allowed")
	W.Policy.Fail = false
	Policy.FailSeconds = 0
	eq(Policy.Allowed(player), true, "retried after a failure")
end)

-- ===== 13. Presentation errors never block the acknowledgment =====
test("a refresh/presentation error after the grant still acknowledges the receipt", function()
	local W = world()
	W.AddPlayer(1)
	W.Join(1)
	W.PS.Start(W.Runtime)
	W.Runtime.FailRefresh = true
	eq(W.PS.HandleReceipt(W.Receipt(1, 3717462952, "REFRESH-1")), GRANTED)
	truthy(W.Store.Raw.Data["purchase:REFRESH-1"], "granted")
end)

print(("payments: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("payments tests failed")
end
