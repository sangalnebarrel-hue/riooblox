--!nocheck
--!nolint
-- A server world for tests (not a test itself): the REAL Economy.Runtime on the Studio memory store,
-- loaded through tests/payments_lib/loader (fake instances, the real @lune/task scheduler), with stub
-- Players / RunService / HttpService / PolicyService / MessagingService / MarketplaceService, the
-- place remotes in ReplicatedStorage and an empty ServerStorage.DogTemplates.
--   local World = require("./lib/server_world")
--   local W = World.new({ Now = 1800000000, Policy = fn(player) -> info?, Start = false })
--   W.L, W.Runtime, W.Rules, W.Engine, W.Tx, W.Store (Runtime's memory store: Store.Data[key])
--   W.AddPlayer(uid) -> player        a connected Player (not joined)
--   W.Join(uid) -> player             AddPlayer + Engine:Join + Runtime.Loaded + first Refresh
--   W.Request(player, action, args)   Runtime.Request with a fresh 32-hex request id
--   W.Edit(uid, fn(p))                fn on the RAM profile inside a transaction (Tx:Run)
--   W.Profile(uid)                    the RAM profile (Tx.Cache) to read
--   W.JsonEncodes                     HttpService:JSONEncode calls so far
--   W.CloseHandlers                   functions given to game:BindToClose
-- Start=true also runs Runtime.Start() (economy loop, PlayerAdded joins): end such a test with
-- process.exit, as tests/economy_loop.luau does.
local L = require("../payments_lib/loader")

local World = {}

function World.new(opts)
	opts = opts or {}
	L.Reset()
	L.Now = opts.Now or 1800000000
	local W = { L = L, List = {}, JsonEncodes = 0, CloseHandlers = {}, Requests = 0 }
	local playersService = L.Instance("Players")
	playersService.PlayerAdded = L.Signal()
	playersService.PlayerRemoving = L.Signal()
	playersService.GetPlayerByUserId = function(_, id)
		local p = W.List[id]
		return p and p.Parent and p or nil
	end
	playersService.GetPlayers = function()
		local out = {}
		for _, p in W.List do
			if p.Parent then
				table.insert(out, p)
			end
		end
		return out
	end
	W.PlayersService = playersService
	L.Services.Players = playersService
	L.Services.RunService = { IsStudio = function() return true end, IsServer = function() return true end, IsClient = function() return false end }
	local guidN = 0
	L.Services.HttpService = {
		GenerateGUID = function()
			guidN += 1
			return string.format("%08x-0000-0000-0000-%012x", guidN, guidN)
		end,
		JSONEncode = function()
			W.JsonEncodes += 1
			return "[]"
		end,
	}
	local market = { PromptGamePassPurchaseFinished = L.Signal() }
	function market:GetDeveloperProductsAsync() error("no web access in tests") end
	function market:GetProductInfoAsync(id) return { IsForSale = true, PriceInRobux = 1, Name = tostring(id) } end
	function market:UserOwnsGamePassAsync() return false end
	L.Services.MarketplaceService = market
	W.PolicyCalls = 0
	L.Services.PolicyService = {
		GetPolicyInfoForPlayerAsync = function(_, player)
			W.PolicyCalls += 1
			if opts.Policy then
				return opts.Policy(player)
			end
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
		end,
	}
	L.Services.MessagingService = { SubscribeAsync = function() end, PublishAsync = function() end }
	L.Services.DataStoreService = { GetDataStore = function() error("tests use the memory store") end }
	-- The loader's own game lookup, captured once (every world wraps it again).
	World.GameIndex = World.GameIndex or getmetatable(L.Game).__index
	setmetatable(L.Game, { __index = function(t, k)
		if k == "GameId" then return 0 end
		if k == "BindToClose" then return function(_, fn) table.insert(W.CloseHandlers, fn) end end
		return World.GameIndex(t, k)
	end })
	local RS = L.Node("ReplicatedStorage")
	for _, name in { "RewardPresentation", "DiscoveryReveal", "DiscoveryAnnouncement", "DogEconomyOpen" } do
		local remote = L.Instance("RemoteEvent")
		remote.Name = name
		remote.Parent = RS
	end
	local request = L.Instance("RemoteFunction")
	request.Name = "DogEconomyRequest"
	request.Parent = RS
	local templates = L.Instance("Folder")
	templates.Name = "DogTemplates"
	templates.Parent = L.Node("ServerStorage")
	W.RS = RS

	W.Runtime = L.Require("ServerScriptService/Economy/Runtime")
	W.Rules = L.Require("ServerScriptService/Economy/Rules")
	W.Registry = L.Require("ServerScriptService/Economy/FeatureRegistry")
	W.Engine = W.Runtime.Engine
	W.Tx = W.Runtime.Tx
	W.Store = W.Tx.Store

	function W.AddPlayer(uid)
		local player = L.Instance("Player")
		player.Name = "Player" .. uid
		player.UserId = uid
		player.DisplayName = "Tester" .. uid
		player.Kick = function(self, message)
			self.Kicked = message
		end
		player.Parent = playersService
		W.List[uid] = player
		return player
	end
	function W.Join(uid)
		local player = W.List[uid] or W.AddPlayer(uid)
		local ok, result = W.Engine:Join(uid)
		assert(ok, "join failed: " .. tostring(result))
		W.Runtime.Loaded[uid] = true
		W.Runtime.Refresh(player)
		return player
	end
	function W.Request(player, action, args)
		W.Requests += 1
		-- Receipts use the first 26 hex digits: the counter lives there.
		return W.Runtime.Request(player, action, args, string.format("%026x", W.Requests) .. "abcdef")
	end
	function W.Edit(uid, fn)
		local key = "p:" .. uid
		local ok, result = W.Tx:Run({ key }, function(v)
			fn(v[key])
			return true
		end)
		assert(ok, "edit failed: " .. tostring(result))
	end
	function W.Profile(uid)
		return W.Tx.Cache["p:" .. uid]
	end
	if opts.Start then
		W.Runtime.Start()
	end
	return W
end

return World
