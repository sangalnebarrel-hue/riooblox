--!nocheck
--!nolint
-- The REAL Economy.Runtime.Start() loop, autosave and shutdown on the Studio memory store:
--   lune run tests/economy_loop.luau
-- Guards the 1 s economy loop (digging, income and session renewal for every player) against
-- DataStore-bound work, the record batch guard, and the order of the shutdown saves.
local task = require("@lune/task")
local process = require("@lune/process")
local L = require("./payments_lib/loader")
L.Now = 1800000000

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

-- ===== Stub Roblox services (memory DataStore: game.GameId == 0 in Studio) =====
local playersService = L.Instance("Players")
playersService.PlayerAdded = L.Signal()
playersService.PlayerRemoving = L.Signal()
local list = {}
playersService.GetPlayerByUserId = function(_, id)
	local p = list[id]
	return p and p.Parent and p or nil
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
L.Services.RunService = { IsStudio = function() return true end, IsServer = function() return true end }
local guidN = 0
L.Services.HttpService = {
	GenerateGUID = function()
		guidN += 1
		return string.format("%08x-0000-0000-0000-%012x", guidN, guidN)
	end,
	JSONEncode = function() return "{}" end,
}
local market = { PromptGamePassPurchaseFinished = L.Signal() }
function market:GetDeveloperProductsAsync() error("no web access in tests") end
function market:GetProductInfoAsync(id) return { IsForSale = true, PriceInRobux = 1, Name = tostring(id) } end
function market:UserOwnsGamePassAsync() return false end
L.Services.MarketplaceService = market
L.Services.PolicyService = { GetPolicyInfoForPlayerAsync = function() return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true } end }
L.Services.MessagingService = { SubscribeAsync = function() end, PublishAsync = function() end }
L.Services.DataStoreService = { GetDataStore = function() error("tests use the memory store") end }
local closeHandlers = {}
local gameIndex = getmetatable(L.Game).__index
setmetatable(L.Game, { __index = function(t, k)
	if k == "GameId" then return 0 end
	if k == "BindToClose" then return function(_, fn) table.insert(closeHandlers, fn) end end
	return gameIndex(t, k)
end })
local RS = L.Node("ReplicatedStorage")
for _, name in { "RewardPresentation", "DogEconomyRequest", "DiscoveryReveal", "DiscoveryAnnouncement", "DogEconomyOpen" } do
	local remote = L.Instance("RemoteEvent")
	remote.Name = name
	remote.Parent = RS
end
local templates = L.Instance("Folder")
templates.Name = "DogTemplates"
templates.Parent = L.Node("ServerStorage")

-- ===== The real Runtime with two players (world modules stubbed) =====
local Runtime = L.Require("ServerScriptService/Economy/Runtime")
Runtime.Kennels = { UpdateWorkVisuals = function() end, Reconcile = function() end }
local projectFails = false
Runtime.Project = function(player, p)
	Runtime.Views[player.UserId] = p
	player:SetAttribute("EconomyReady", true)
	if projectFails then
		error("Project failed (injected)")
	end
end
Runtime.Start()
for uid = 1, 2 do
	local player = L.Instance("Player")
	player.Name = "P" .. uid
	player.UserId = uid
	player.DisplayName = "P" .. uid
	player.Parent = playersService
	list[uid] = player
	playersService.PlayerAdded:Fire(player)
end
local t0 = os.clock()
while not (Runtime.Loaded[1] and Runtime.Loaded[2]) and os.clock() - t0 < 10 do
	task.wait(0.1)
end
check("two players loaded", Runtime.Loaded[1] and Runtime.Loaded[2])

-- ===== 1. DataStore-bound steps never pause the economy loop =====
-- Market settlement (GetAsync + journaled closes) takes 3 s, and player 1 has a record check
-- while a receipt-like durable transaction holds their profile lock for 3 s.
do
	local realDue = Runtime.Engine.Market.Due
	local settlements = 0
	Runtime.Engine.Market.Due = function()
		settlements += 1
		task.wait(3)
		return 0
	end
	Runtime.Tx:Run({ "p:1" }, function(v)
		local p = v["p:1"]
		p.RecordJobs = p.RecordJobs or {}
		p.RecordJobs.Bone = { ItemId = "Bone", ItemUid = "u1", Depth = 1, WeightKg = 1, OriginalFinderUserId = 1, FoundAt = L.Now }
		return true
	end)
	Runtime.Tx.Busy["p:1"] = "held-by-a-receipt"
	Runtime.LastSettlement, Runtime.LastRecords = 0, 0
	local beats, seen, sampling = {}, Runtime.LoopBeat, true
	local start = os.clock()
	task.spawn(function()
		while sampling do
			if Runtime.LoopBeat ~= seen then
				seen = Runtime.LoopBeat
				table.insert(beats, os.clock())
			end
			task.wait(0.02)
		end
	end)
	task.delay(3, function()
		Runtime.Tx.Busy["p:1"] = nil
	end)
	task.wait(4.5)
	sampling = false
	local gap, last = 0, start
	for _, at in beats do
		gap = math.max(gap, at - last)
		last = at
	end
	gap = math.max(gap, os.clock() - last)
	check("settlement ran", settlements >= 1, settlements)
	check("the economy loop never paused", gap < 2.4, ("longest gap %.2f s"):format(gap))
	-- The harness clock is frozen (L.Now): let the 5 s record schedule fire again.
	Runtime.LastRecords = 0
	task.wait(1.5)
	local jobs = Runtime.Tx.Cache["p:1"].RecordJobs
	check("the skipped record check is collected once the lock is free", jobs and jobs.Bone == nil)
	Runtime.Engine.Market.Due = realDue
end

-- ===== 2. A failing refresh never stops the global record batch for good =====
do
	local function queue(itemId, weight)
		Runtime.RecordQueue[2] = Runtime.RecordQueue[2] or {}
		Runtime.RecordQueue[2][itemId] = {
			Row = { WeightKg = weight, ItemUid = "u-" .. itemId, Finder = 1, At = L.Now },
			Job = { ItemId = itemId, ItemUid = "u-" .. itemId, Depth = 2, WeightKg = weight, OriginalFinderUserId = 1, FoundAt = L.Now, TierIndex = 1, Class = "Common", DisplayName = itemId },
		}
	end
	projectFails = true
	queue("Pebble", 3)
	local called = pcall(Runtime.FlushRecords)
	projectFails = false
	check("a failing finder refresh does not escape the batch", called)
	check("the batch guard is released", Runtime.FlushingRecords == false, Runtime.FlushingRecords)
	queue("Fossil", 5)
	Runtime.FlushRecords()
	local book = Runtime.Tx.Store.Data["records:2"]
	check("later batches still merge records", book and book.Value and book.Value.Pebble and book.Value.Fossil)
end

-- ===== 3. A quick rejoin to this server while the leave save is still running =====
-- The old PlayerRemoving must neither clear the new session's runtime state nor end its session.
do
	local store = Runtime.Tx.Store
	local rawUpdate = store.Update
	store.Update = function(self, k, fn)
		if k == "p:2" then
			task.wait(1.5) -- a slow save
		end
		return rawUpdate(self, k, fn)
	end
	local old = list[2]
	playersService.PlayerRemoving:Fire(old)
	task.wait()
	old.Parent = nil
	task.wait(0.3)
	local new = L.Instance("Player")
	new.Name = "P2"
	new.UserId = 2
	new.DisplayName = "P2"
	new.Parent = playersService
	list[2] = new
	playersService.PlayerAdded:Fire(new)
	task.wait(3.5)
	store.Update = rawUpdate
	check("the rejoined player is ready", Runtime.Ready(new) and true or false)
	check("the rejoined profile stays in RAM", Runtime.Tx.Loaded["p:2"] == true)
	local p = Runtime.Tx.Cache["p:2"]
	check("the rejoined session is live", p and p.Session ~= nil)
	-- A late release of the old player (lock wait, retry) never ends the connected player's session.
	Runtime.ReleaseProfile(2, false, 1)
	p = Runtime.Tx.Cache["p:2"]
	check("a late leave of the old player keeps the new session", p and p.Session ~= nil)
	-- The rejoined player leaves normally: released and unloaded.
	playersService.PlayerRemoving:Fire(new)
	task.wait()
	new.Parent = nil
	local deadline = os.clock() + 5
	while Runtime.Loaded[2] and os.clock() < deadline do
		task.wait(0.05)
	end
	local saved = store.Data["p:2"]
	check("a normal leave still releases the session", saved and saved.Value and saved.Value.Session == nil)
	check("and unloads the profile", Runtime.Tx.Loaded["p:2"] == nil)
end

-- ===== 4. Shutdown saves player data before the community counter =====
-- Player 1's release save fails once; the counter write is slow. The retry of the player save
-- must not wait behind the counter (the whole shutdown has 30 s).
do
	local store = Runtime.Tx.Store
	local rawUpdate = store.Update
	local profileFailures, savedAt, closeStart = 1, nil, nil
	store.Update = function(self, k, fn)
		if k:sub(1, 6) == "event:" then
			task.wait(3) -- a slow counter write (retries and back-off on a turbulent DataStore)
			error("DataStore 502 (injected)")
		end
		if k == "p:1" then
			if profileFailures > 0 then
				profileFailures -= 1
				error("DataStore 502 (injected)")
			end
			local result = rawUpdate(self, k, fn)
			if result and result.Value and result.Value.Session == nil and not savedAt then
				savedAt = os.clock() - closeStart
			end
			return result
		end
		return rawUpdate(self, k, fn)
	end
	Runtime.AccumulateEvent(25)
	closeStart = os.clock()
	local closedAt
	task.spawn(function()
		for _, fn in closeHandlers do
			fn()
		end
		closedAt = os.clock() - closeStart
	end)
	while not closedAt and os.clock() - closeStart < 20 do
		task.wait(0.05)
	end
	check("shutdown finished", closedAt ~= nil)
	check("the failed release save is retried before the counter flush", savedAt ~= nil and savedAt < 1.5, savedAt)
	local other = store.Data["p:2"]
	check("the other player is released", other and other.Value and other.Value.Session == nil)
	store.Update = rawUpdate
end

print(("economy_loop: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
