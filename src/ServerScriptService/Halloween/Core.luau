-- Server core of NIGHT OF THE BURIED MOON (ServerScriptService.Halloween.Core).
-- * Core.Transact: the one way the event writes a profile (economy Tx:Run, Authorize, Feature.Shape, R.Validate),
--   with a ctx of grant helpers (candy with multipliers and anti-macro caps, bones, coins, items with forced event
--   mutations, event dogs, pumpkin blocks, decor, pickaxe skins, quests, souls).
-- * Core.Queue: per-hit grants merged per player and flushed in ONE transaction per second.
-- * Anti-AFK activity, the Curse (RAM, mirrored to the profile on every write), the personal Candy Rush timer
--   (only ticks while the player is active), Blood Moon participation, player attributes. RAM is authoritative for
--   curse and rush: a silent write every few points / rush seconds and a last write on leave keep the saved copy close.
-- * Core.OnRequest: client actions on ReplicatedStorage.Halloween.Remotes.Request (own token bucket).
-- Chapter I rebalance (docs/halloween2/DESIGN.md §12, Chapter1Rules): the per-minute candy cap applies to the BASE
-- amount before the multipliers (a Candy Rush / Blood Moon keeps its value near the cap); only earned candy progresses
-- the EarnCandy quest (fixed payouts never do); ctx.Dust / reward rows of Kind "Dust" pay Lucky Dust (Resources);
-- Core.ActiveInYard(player, window) tells the exorcists (active in the Dead Yard lately) from AFK players; every view
-- the client gets carries Cauldron.TrickPrice and the catch-up brew ReadyAt (Chapter1Rules.DecorateView).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Rules1 = require(Halloween:WaitForChild("Chapter1Rules"))
local Config = Shared.Config
local Layout = Shared.Layout
local Economy = SSS:WaitForChild("Economy")
local Runtime = require(Economy:WaitForChild("Runtime"))
local R = require(Economy:WaitForChild("Rules"))
local Feature = require(Economy:WaitForChild("Features"):WaitForChild("Halloween"))
local EconConfig = require(RS:WaitForChild("DogEconomy"):WaitForChild("Config"))

local Core = {}
Core.Shared = Shared
Core.Config = Config
Core.Feature = Feature
Core.Runtime = Runtime
Core.Rules = R
Core.Players = {} -- player -> RAM state
Core.Listeners = { Souls = {}, Ready = {} }

local Remotes = Halloween:WaitForChild("Remotes")
local State = Halloween:WaitForChild("State")
local rng = Random.new()

local function I()
	return require(Economy.ItemRules)
end

function Core.Enabled(): boolean
	return Shared.Enabled()
end

function Core.State(player: Player)
	return Core.Players[player]
end

function Core.Root(player: Player): BasePart?
	local ch = player and player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and hum and hum.Health > 0 then
		return root
	end
	return nil
end

function Core.Near(player: Player, pos: Vector3, range: number): boolean
	local root = Core.Root(player)
	return root ~= nil and (root.Position - pos).Magnitude <= range
end

function Core.InZone(player: Player): boolean
	local root = Core.Root(player)
	return root ~= nil and Layout.InZone(root.Position, 2)
end

function Core.ZonePlayers(): { Player }
	local out = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if Core.InZone(pl) then
			table.insert(out, pl)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------------------------------------------------
function Core.Signal(target: any, kind: string, data: any)
	local remote = Remotes:FindFirstChild("Signal")
	if not remote then
		return
	end
	if target == "all" then
		remote:FireAllClients(kind, data)
	elseif target == "zone" then
		for _, pl in ipairs(Core.ZonePlayers()) do
			remote:FireClient(pl, kind, data)
		end
	elseif typeof(target) == "Instance" and target:IsA("Player") and target.Parent then
		remote:FireClient(target, kind, data)
	end
end

function Core.Toast(player: Player, text: string, kind: string?)
	Core.Signal(player, "Toast", { Text = text, Kind = kind or "info" })
end

---------------------------------------------------------------------------------------------------------------------
-- Multipliers
---------------------------------------------------------------------------------------------------------------------
function Core.BloodMoonActive(): boolean
	local bm = State:FindFirstChild("BloodMoon")
	return bm ~= nil and bm:GetAttribute("State") == "ACTIVE"
end

function Core.ServerRushActive(): boolean
	return (State:GetAttribute("ServerRushUntil") or 0) > os.time()
end

function Core.MutationBoost(): number
	return (State:GetAttribute("MutationBoostUntil") or 0) > os.time() and Config.Mutations.ExorcismBoost or 1
end

-- the personal rush of this UTC day (a rush left running at midnight stops; the next write starts the new day's)
local function rushOn(st): boolean
	return st ~= nil and st.RushActive == true and (st.RushRemaining or 0) > 0 and st.RushDay == Feature.Day(os.time())
end

function Core.RushActive(player: Player): boolean
	return rushOn(Core.Players[player])
end

function Core.Multiplier(player: Player): (number, { [string]: number })
	local st = Core.Players[player]
	local parts = {}
	parts.Curse = Shared.CurseMultiplier(st and st.Curse or 0)
	local rush = Core.RushActive(player) and Config.CandyRush.Mult or 1
	local server = Core.ServerRushActive() and Config.CandyRush.ServerMult or 1
	parts.Rush = math.max(rush, server)
	parts.BloodMoon = (Core.BloodMoonActive() and st and st.InZone) and (1 + Config.BloodMoon.CandyBonus) or 1
	return parts.Curse * parts.Rush * parts.BloodMoon, parts
end

---------------------------------------------------------------------------------------------------------------------
-- Activity / curse
---------------------------------------------------------------------------------------------------------------------
function Core.Activity(player: Player, kind: string?)
	local st = Core.Players[player]
	if not st then
		return
	end
	st.LastActivity = os.clock()
	local relief = kind and Config.Curse.Relief[kind]
	if relief then
		st.Curse = math.max(0, st.Curse - relief)
	end
end

function Core.AddCurse(player: Player, amount: number)
	local st = Core.Players[player]
	if st then
		st.Curse = math.clamp(st.Curse + amount, 0, 100)
	end
end

local function isActive(st): boolean
	return os.clock() - (st.LastActivity or -1e9) <= Config.Activity.Window
end
Core.IsActive = function(player: Player): boolean
	local st = Core.Players[player]
	return st ~= nil and isActive(st)
end

-- an exorcist: active (an action within Activity.Window) inside the Dead Yard at some second of the last `window`
-- seconds (st.YardActiveAt, stamped by the 1 s tick). AFK players and players elsewhere on the island are not.
function Core.ActiveInYard(player: Player, window: number): boolean
	local st = Core.Players[player]
	return st ~= nil and st.Ready == true and Rules1.RecentlyActive(st.YardActiveAt, os.clock(), window)
end

---------------------------------------------------------------------------------------------------------------------
-- Transactions
---------------------------------------------------------------------------------------------------------------------
local function dogsOfRows(rows: { any }?): { string }
	local out = {}
	for _, row in ipairs(rows or {}) do
		if type(row) == "table" and row.Kind == "Dog" and type(row.Id) == "string" and not table.find(out, row.Id) then
			table.insert(out, row.Id)
		end
	end
	return out
end
Core.DogsOf = dogsOfRows

local function makeCtx(player: Player, p: any, h: any, v: any, now: number, dogs: { string }, after: { () -> () }, st: any)
	local ctx = { Touched = false, Granted = {}, SoulCount = 0, Completed = {} }
	local function note(kind, amount, extra)
		local row = { Kind = kind, Amount = amount }
		for k, x in pairs(extra or {}) do
			row[k] = x
		end
		table.insert(ctx.Granted, row)
		return row
	end

	function ctx.Quest(id: string, n: number?)
		local done = Feature.QuestProgress(p, id, n or 1, now)
		if done then
			table.insert(ctx.Completed, done.Id)
		end
	end

	function ctx.Stat(key: string, n: number?)
		h.Stats[key] = (h.Stats[key] or 0) + (n or 1)
	end

	function ctx.Souls(n: number)
		ctx.SoulCount += math.max(0, n or 0)
	end

	function ctx.Relief(kind: string)
		Core.Activity(player, kind)
	end

	function ctx.After(fn: () -> ())
		table.insert(after, fn)
	end

	-- candy with multipliers (curse, rush, blood moon) and the per-minute anti-macro cap. The cap counts the BASE
	-- amount, before the multipliers (Chapter1Rules.MinuteCap), so a Candy Rush or a Blood Moon keeps its full value
	-- near the cap. o = {NoMult, NoCap, Earned}: only earned candy progresses the EarnCandy quest (Chapter1Rules.Earned:
	-- quest claims, reward rows, conversions and other fixed payouts never do).
	function ctx.Candy(n: number, source: string?, o: { [string]: any }?): number
		o = o or {}
		n = math.max(0, n or 0)
		if n <= 0 then
			return 0
		end
		-- THE DEAD YARD switched off: activities earn no candy (fixed payouts and reward rows still pay)
		if not Shared.Chapter1Enabled() and Rules1.Earned(source, o, Config) then
			return 0
		end
		if not o.NoCap and st then
			local clock = os.clock()
			if clock - st.MinuteStart >= 60 then
				st.MinuteStart, st.MinuteCandy = clock, 0
			end
			n, st.MinuteCandy = Rules1.MinuteCap(st.MinuteCandy, n, Config.Candy.MinuteCap)
			if n <= 0 then
				return 0
			end
		end
		local mult = o.NoMult and 1 or Core.Multiplier(player)
		local raw = n * mult
		local amount = math.floor(raw)
		if rng:NextNumber() < raw - amount then
			amount += 1
		end
		amount = Feature.AddCandy(p, amount)
		if amount > 0 then
			if Rules1.Earned(source, o, Config) then
				ctx.Quest("EarnCandy", amount)
			end
			ctx.Souls(amount * (Config.Exorcism.Souls.Candy or 1))
			note("Candy", amount, { Source = source })
		end
		return amount
	end

	-- Lucky Dust (Resources "LuckyDust", the Dust Forge currency). n or {min, max}; 0 when this build has no Lucky Dust
	function ctx.Dust(n: any): number
		local amount = n
		if type(n) == "table" then
			local lo = math.floor(tonumber(n[1]) or 0)
			local hi = math.max(lo, math.floor(tonumber(n[2]) or lo))
			amount = rng:NextInteger(lo, hi)
		end
		amount = math.max(0, math.floor(tonumber(amount) or 0))
		local Resources = require(RS.DogEconomy.Resources)
		if amount <= 0 or not Resources.Kinds.LuckyDust then
			return 0
		end
		amount = Resources.Add(p, "LuckyDust", amount)
		if amount > 0 then
			ctx.Touched = true
			note("Dust", amount)
		end
		return amount
	end

	function ctx.Spend(n: number)
		Feature.Spend(R, p, n)
	end

	function ctx.Bones(n: number): number
		n = math.max(0, math.floor(n or 0))
		n = math.min(n, EconConfig.MaxCash - p.Bones)
		if n > 0 then
			p.Bones += n
			ctx.Touched = true
			note("Bones", n)
		end
		return n
	end

	function ctx.Coins(spec: any): number
		local amount = 0
		if type(spec) == "number" then
			amount = spec
		elseif type(spec) == "table" then
			amount = require(RS.DogEconomy.BoostPricing).Coins(spec, p, now)
		end
		amount = math.clamp(math.floor(amount), 0, math.max(0, EconConfig.MaxCash - p.Cash))
		if amount > 0 then
			R.Credit(p, amount)
			ctx.Touched = true
			note("Cash", amount)
		end
		return amount
	end

	function ctx.XP(n: number)
		if n and n > 0 then
			R.AddXP(p, math.floor(n))
			ctx.Touched = true
		end
	end

	-- a generated find (rolled on the player's deepest layer unless Depth/ItemId given), optional forced mutation
	function ctx.Item(o: { [string]: any }?): any
		o = o or {}
		local Items = I()
		if not Items.Free(p) then
			return nil
		end
		local seed = rng:NextInteger(1, 2147483646)
		local r = Random.new(seed)
		local roll = function()
			return r:NextNumber()
		end
		local e = R.Team(p, now)
		local def, chance = nil, nil
		if type(o.ItemId) == "string" and Items.Definitions[o.ItemId] then
			def = Items.Definitions[o.ItemId]
			chance = def.BaseDropChance
		end
		local depth = math.clamp(math.floor(o.Depth or R.MaxUnlockedLayer(p) or 1), 1, 5)
		for _ = 1, 12 do
			if def then
				break
			end
			def, chance = Items.Pick(depth, roll, e)
		end
		for _ = 1, 12 do
			if def then
				break
			end
			def, chance = Items.Pick(1, roll, e)
		end
		if not def then
			return nil
		end
		if type(o.Mutation) == "string" then
			e.ForceMutation = o.Mutation
			e.ForceMutationChance = o.MutationChance or .001
		end
		local x = Items.Mint(p, def, chance, Runtime.Engine.Guid(), now, roll, e)
		x.Origin = o.Origin or "Halloween"
		ctx.Touched = true
		if Shared.IsEventMutation(x.Mutation) then
			ctx.Stat("Mutations", 1)
			ctx.Quest("FindMutation", 1)
		end
		local copy = R.Copy(x)
		note("Item", 1, { Item = copy })
		return copy
	end

	function ctx.Dog(dogId: string, variant: string?): any
		R.Check(table.find(dogs, dogId) ~= nil, "Dog grant not declared")
		R.Check(Runtime.Engine.AssetReady(dogId), "Dog asset unavailable")
		R.Check(R.Free(p), "Your dog storage is full")
		local key = "supply:" .. dogId
		local supply = v[key] or {}
		v[key] = supply
		local dog = R.Mint(p, dogId, Runtime.Engine.Guid(), supply, now, Runtime.Engine.Random, "BuriedMoon", variant, true)
		dog.PricePaid = 0
		ctx.Touched = true
		local copy = R.Copy(dog)
		note("Dog", 1, { Dog = copy, Id = dogId })
		return copy
	end

	-- minRank: a reward floor without a new tier (the exorcism "RARE PUMPKIN BLOCK"). AddStored freezes an event block's
	-- reward table at once; the floor keeps only rows of Rank >= minRank in that frozen Pool, which is what the block opens
	-- from (LuckyLifecycle.Open / EventBlocks.Pick) and the chances it shows (snapshot Odds). Never an empty pool.
	function ctx.Block(tier: string, n: number?, minRank: number?): { string }?
		n = math.max(1, math.floor(n or 1))
		local cap = require(RS.LuckyLifecycleConfig).InventoryCapacity or 60
		if R.Count(p.OwnedBlocks or {}) + n > cap then
			return nil
		end
		local ids = require(Economy.LuckyLifecycle).AddStored(p, tier, n, "BuriedMoon", false)
		minRank = math.floor(tonumber(minRank) or 1)
		for _, uid in ipairs(minRank > 1 and ids or {}) do
			local b = p.OwnedBlocks[uid]
			local kept = {}
			for _, row in ipairs(type(b) == "table" and type(b.Pool) == "table" and b.Pool or {}) do
				if (tonumber(row.Rank) or 1) >= minRank then
					table.insert(kept, row)
				end
			end
			if #kept > 0 then
				b.Pool, b.MinRank = kept, minRank
			end
		end
		ctx.Touched = true
		note("Block", n, { Id = tier, MinRank = minRank > 1 and minRank or nil })
		return ids
	end

	function ctx.Decor(id: string): boolean
		local Decor = require(Economy.Features.Decor)
		Decor.Normalize(R, p, now)
		local cap = require(RS.DogEconomy.DecorCatalog).MaxOwned(id)
		local have = p.Decor.Owned[id] or 0
		if have >= cap then
			return false
		end
		p.Decor.Owned[id] = have + 1
		ctx.Touched = true
		note("Decor", 1, { Id = id })
		return true
	end

	function ctx.Skin(id: string): boolean
		R.Check(Config.Skins.Names[id] ~= nil, "Unknown skin")
		if h.Skins[id] then
			return false
		end
		h.Skins[id] = true
		note("Skin", 1, { Id = id })
		return true
	end

	-- generic reward row (Config.Rewards.*, quests, exorcism, dex, boss). Never fails on a full inventory:
	-- converts (Config.Rewards.Conversion) instead and marks Converted.
	function ctx.Reward(row: any): any
		local conv = Config.Rewards.Conversion
		local kind = row.Kind
		local out = { Kind = kind, Id = row.Id, Name = row.Name, Rarity = row.Rarity, Rank = row.Rank }
		if kind == "Candy" then
			out.Amount = ctx.Candy(row.Amount or 0, "Reward", { NoMult = true, NoCap = true })
		elseif kind == "Bones" then
			out.Amount = ctx.Bones(row.Amount or 0)
		elseif kind == "Dust" then
			out.Amount = ctx.Dust(row.Amount or 0)
			if out.Amount <= 0 then -- no Lucky Dust in this build (or a zero row): bones instead, never a failure
				out.Converted = true
				out.Kind, out.Amount = "Bones", ctx.Bones(conv.DecorBones)
			end
		elseif kind == "Cash" then
			out.Amount = ctx.Coins(row.Coins or row.Amount or 0)
		elseif kind == "Decor" then
			if not ctx.Decor(row.Id) then
				out.Converted = true
				out.Kind, out.Amount = "Bones", ctx.Bones(conv.DecorBones)
			end
		elseif kind == "Skin" then
			if not ctx.Skin(row.Id) then
				out.Converted = true
				out.Kind, out.Amount = "Candy", ctx.Candy(conv.SkinCandy, "Duplicate", { NoMult = true, NoCap = true })
			end
		elseif kind == "Dog" then
			if not R.Free(p) or not Runtime.Engine.AssetReady(row.Id) then
				out.Converted = true
				out.Kind, out.Amount = "Candy", ctx.Candy(conv.DogCandyPerRank * (row.Rank or 2), "Dog", { NoMult = true, NoCap = true })
			else
				out.Dog = ctx.Dog(row.Id, row.Variant)
			end
		elseif kind == "Mutation" then
			out.Item = ctx.Item({ Mutation = row.Id, MutationChance = row.Chance or .001, Origin = "Halloween" })
			if not out.Item then
				out.Converted = true
				out.Kind, out.Amount = "Candy", ctx.Candy(conv.MutationCandy, "Mutation", { NoMult = true, NoCap = true })
			end
		elseif kind == "Block" then
			local n = row.Amount or 1
			if not ctx.Block(row.Id or "Pumpkin", n, row.MinRank) then
				out.Converted = true
				out.Kind, out.Amount = "Candy", ctx.Candy(conv.BlockCandy * n, "Block", { NoMult = true, NoCap = true })
			else
				out.Amount = n
			end
		elseif kind == "Luck" then
			local LuckRules = require(Economy.LuckRules)
			LuckRules.Add(p, row.Tier or 2, row.Seconds or 300, now)
			ctx.Touched = true
		else
			error("Unknown reward kind " .. tostring(kind), 0)
		end
		return out
	end

	return ctx
end
Core.MakeCtx = makeCtx -- tests: the grant ctx of one transaction (makeCtx(player, p, h, v, now, dogs, after, st))

-- the client view of a profile: Features.Halloween.View + the Chapter I rebalance fields (TRICK price of the moment,
-- the catch-up brew time)
function Core.View(p: any, now: number): any
	local view = Feature.View(p, now)
	local h = type(p) == "table" and p.Halloween or nil
	if type(h) == "table" and type(h.Cauldron) == "table" then
		Rules1.DecorateView(view, h, now, Config, Shared.BrewSeconds(h.Cauldron.StartedAt))
	end
	return view
end

-- opts = {Dogs = {dogId...}, Rows = {...} (dog ids are taken from reward rows), Refresh = bool, Receipt = string,
--         Timeout = number, EvenIfDisabled = bool, Silent = bool (no View push: background saves)}
-- -> ok, result|err, raw, cached. Receipt ids are server-made only (never from client args). cached = true: the receipt
-- had already committed and Transactions returned that earlier reply without running fn, so nothing new happened (no
-- sync, souls, quest signals, refresh or after-hooks); callers must not broadcast or toast it again.
function Core.Transact(player: Player, label: string, fn: (any, any, any, number) -> any, opts: { [string]: any }?): (boolean, any, any, boolean?)
	opts = opts or {}
	if not opts.EvenIfDisabled and not Shared.Enabled() then
		return false, "The Night of the Buried Moon has ended"
	end
	if not player or not player.Parent or not Runtime.Ready(player) then
		return false, "Your saved profile is still loading"
	end
	local st = Core.Players[player]
	local uid = player.UserId
	local key = "p:" .. uid
	local dogs = table.clone(opts.Dogs or {})
	for _, id in ipairs(dogsOfRows(opts.Rows)) do
		if not table.find(dogs, id) then
			table.insert(dogs, id)
		end
	end
	local keys = { key }
	for _, id in ipairs(dogs) do
		table.insert(keys, "supply:" .. id)
	end
	local after = {}
	local nonce = HttpService:GenerateGUID(false) -- tells this run's reply from a cached receipt reply
	local ok, result = Runtime.Tx:Run(keys, function(v)
		table.clear(after)
		local p = v[key]
		Runtime.Engine:Authorize(p, uid)
		local now = os.time()
		local h = Feature.Shape(p)
		Feature.EnsureDaily(p, now)
		-- RAM is authoritative for the curse and (same UTC day) the rush timer; the profile keeps a saved copy
		local rush0 = nil
		if st and st.Ready then -- (a state still waiting for join() to load the saved copy must not overwrite it)
			h.Curse = math.floor(st.Curse * 10 + .5) / 10
			if st.RushDay == h.Rush.Day and st.RushRemaining ~= nil then
				h.Rush.Remaining = math.clamp(math.floor(st.RushRemaining), 0, Config.CandyRush.Seconds)
				h.Rush.Active = st.RushActive == true and h.Rush.Remaining > 0
				rush0 = { Day = h.Rush.Day, Remaining = h.Rush.Remaining, Active = h.Rush.Active }
			end
		end
		local ctx = makeCtx(player, p, h, v, now, dogs, after, st)
		local res = fn(p, h, ctx, now)
		R.Validate(p)
		local r = h.Rush
		-- RAM takes the profile's rush only when this transaction set it (RushStart, a new UTC day, a debug refill)
		local rushSet = rush0 == nil or r.Day ~= rush0.Day or r.Remaining ~= rush0.Remaining or r.Active ~= rush0.Active
		return { Nonce = nonce, Result = res, View = Core.View(p, now), Touched = ctx.Touched, Souls = ctx.SoulCount,
			Completed = ctx.Completed, Granted = ctx.Granted, Candy = h.Candy, RushSet = rushSet, Curse = h.Curse }
	end, opts.Receipt, opts.Timeout and { Timeout = opts.Timeout } or nil)
	if not ok then
		return false, result
	end
	if type(result) ~= "table" or result.Nonce ~= nonce then
		-- cached receipt reply: fn did not run now, and its view is old (re-syncing it would roll the rush timer back)
		local res = type(result) == "table" and result.Result or nil
		if type(res) == "table" and res.View == nil and st then
			res.View = st.View
		end
		return true, res, result, true
	end
	if st and st.Ready then
		st.RushDirty, st.SavedCurse = 0, result.Curse -- the saved copy now matches RAM
	end
	Core.Sync(player, result.View, result.RushSet, opts.Silent and not result.RushSet) -- (a new UTC day is always pushed)
	if opts.Refresh or result.Touched then
		task.defer(function()
			if player.Parent and Runtime.Ready(player) and not player:GetAttribute("EconomyLeaving") then
				Runtime.Refresh(player)
			end
		end)
	end
	if result.Souls and result.Souls > 0 then
		for _, fnSouls in ipairs(Core.Listeners.Souls) do
			task.spawn(fnSouls, result.Souls, player)
		end
	end
	for _, id in ipairs(result.Completed or {}) do
		local def = Feature.QuestDef(id)
		Core.Signal(player, "QuestComplete", { Id = id, Text = def and def.Text, Goal = def and def.Goal })
	end
	for _, f in ipairs(after) do
		task.spawn(f)
	end
	if type(result.Result) == "table" and result.Result.View == nil then
		result.Result.View = result.View
	end
	return true, result.Result, result, false
end

---------------------------------------------------------------------------------------------------------------------
-- Per-second grant queue (strike hits etc.)
---------------------------------------------------------------------------------------------------------------------
function Core.Queue(player: Player, op: { [string]: any }): number
	local st = Core.Players[player]
	if not st or not st.Ready then
		return 0
	end
	local q = st.Queue
	if not q then
		q = { Candy = 0, Bones = 0, Souls = 0, Quest = {}, Stat = {}, Relief = {} }
		st.Queue = q
	end
	local predicted = 0
	if op.Candy and op.Candy > 0 then
		local cap = op.Source == "Perfect" and Config.Candy.PerfectHitCap or nil
		local amount = op.Candy
		if cap then
			local clock = os.clock()
			if clock - st.PerfectStart >= 60 then
				st.PerfectStart, st.PerfectCount = clock, 0
			end
			amount = math.clamp(amount, 0, math.max(0, cap - st.PerfectCount))
			st.PerfectCount += amount
		end
		q.Candy += amount
		predicted = math.floor(amount * Core.Multiplier(player) + .5)
	end
	q.Bones += op.Bones or 0
	q.Souls += op.Souls or 0
	for id, n in pairs(op.Quest or {}) do
		q.Quest[id] = (q.Quest[id] or 0) + n
	end
	for k, n in pairs(op.Stat or {}) do
		q.Stat[k] = (q.Stat[k] or 0) + n
	end
	for _, kind in ipairs(op.Relief or {}) do
		Core.Activity(player, kind)
	end
	return predicted
end

local function applyQueue(ctx, q)
	if q.Candy > 0 then
		ctx.Candy(q.Candy, "Queue")
	end
	if q.Bones > 0 then
		ctx.Bones(q.Bones)
	end
	for id, n in pairs(q.Quest) do
		ctx.Quest(id, n)
	end
	for k, n in pairs(q.Stat) do
		ctx.Stat(k, n)
	end
	ctx.Souls(q.Souls)
end

local function flushQueue(player: Player, st)
	local q = st.Queue
	if not q then
		return
	end
	st.Queue = nil
	local ok, err = Core.Transact(player, "Queue", function(_p, _h, ctx)
		applyQueue(ctx, q)
	end, { Timeout = 2 })
	if not ok then
		-- busy profile (dig tick / trade): retry next second, merged with anything queued meanwhile
		local cur = st.Queue
		if cur then
			cur.Candy += q.Candy
			cur.Bones += q.Bones
			cur.Souls += q.Souls
			for id, n in pairs(q.Quest) do
				cur.Quest[id] = (cur.Quest[id] or 0) + n
			end
			for k, n in pairs(q.Stat) do
				cur.Stat[k] = (cur.Stat[k] or 0) + n
			end
		else
			st.Queue = q
		end
		if type(err) == "string" and not string.find(err, "busy") then
			warn("Halloween queue flush failed: " .. err)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Player attributes / client sync
---------------------------------------------------------------------------------------------------------------------
local function setAttr(inst: Instance?, name: string, value: any)
	if inst and inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end
Core.SetAttr = setAttr

-- rushSet: the transaction set the profile's rush (Core.Transact). Otherwise RAM keeps its own countdown (with the
-- fractions the whole-second profile copy drops), so neither that copy nor an older view rolls the timer back.
-- The curse is never taken from a view (RAM only; join() loads the saved copy once).
function Core.Sync(player: Player, view: any, rushSet: boolean?, silent: boolean?)
	local st = Core.Players[player]
	if not view or not player.Parent then
		return
	end
	setAttr(player, "MoonCandy", view.Candy or 0)
	setAttr(player, "HwBossUnlocked", view.Boss and view.Boss.Unlocked or 1)
	local skin = view.Skin
	setAttr(player, "PickaxeSkin", (type(skin) == "string" and skin ~= "") and skin or nil)
	if st and view.Rush and (rushSet or st.RushRemaining == nil) then
		st.RushDay = view.Rush.Day
		st.RushRemaining = view.Rush.Remaining
		st.RushActive = view.Rush.Active
	end
	if st then
		st.View = view
	end
	if not silent then
		Core.Signal(player, "View", { View = view })
	end
end

local function tickPlayer(player: Player, st, dt: number)
	local root = Core.Root(player)
	local inZone = root ~= nil and Layout.InZone(root.Position, 2)
	st.InZone = inZone
	-- movement (walking: not idle, but no activity)
	local moving = false
	if root then
		local pos = root.Position
		if st.LastPos then
			local d = Vector3.new(pos.X - st.LastPos.X, 0, pos.Z - st.LastPos.Z).Magnitude
			st.MoveDist = st.MoveDist * .8 + math.min(d, 40)
		end
		st.LastPos = pos
		moving = st.MoveDist > Config.Activity.MoveStuds * .5
	end
	local active = isActive(st) and root ~= nil -- a dead player (no live root) burns no rush seconds and earns no credit
	local clock = os.clock()
	if active and inZone then
		st.YardActiveAt = clock -- Core.ActiveInYard (the exorcism block goes to recent exorcists only)
	end
	-- curse: rises only while the player is really idle in the zone. Walking is not idle (it holds the curse, but it
	-- is no activity: Candy Rush and Blood Moon participation still need actions), nor is a first-visit guide card
	-- (st.CurseFrozenUntil, Actions "OnboardingStep"). IdleGrace counts from the last action, step or card.
	if moving or clock < (st.CurseFrozenUntil or 0) then
		st.NotIdleAt = clock
	end
	local idleFor = clock - math.max(st.LastActivity or -1e9, st.NotIdleAt or -1e9)
	if inZone then
		if not active and idleFor > Config.Curse.IdleGrace then
			st.Curse += Config.Curse.RisePerSecond * dt
		end
	else
		st.Curse -= Config.Curse.DecayOutside * dt
	end
	st.Curse = math.clamp(st.Curse, 0, 100)
	-- personal candy rush: only ticks while the player is really active. It does not stack with a server Candy Rush
	-- (Multiplier takes the larger), so while one at least as strong runs, the personal timer waits instead of
	-- burning the daily seconds for nothing.
	local outshone = Core.ServerRushActive() and Config.CandyRush.ServerMult >= Config.CandyRush.Mult
	if rushOn(st) and active and not outshone then
		st.RushRemaining = math.max(0, st.RushRemaining - dt)
		st.RushDirty = (st.RushDirty or 0) + dt
		if st.RushRemaining <= 0 then
			st.RushActive = false
			st.RushDirty = math.huge
			Core.Signal(player, "Rush", { Ended = true })
		end
	end
	-- keep the saved copy close to RAM (rejoining must neither refund rush seconds nor clear the curse; the leave
	-- write can lose the race with the economy's own release): a silent write every few rush seconds / curse points
	local due = (st.RushDirty or 0) >= Config.CandyRush.SaveEvery
		or math.abs(st.Curse - (st.SavedCurse or st.Curse)) >= Config.Curse.SaveStep
	if due and (clock - (st.SaveTry or -1e9) >= Config.Curse.SaveEvery or st.RushDirty == math.huge) then
		st.SaveTry = clock
		if st.RushDirty == math.huge then
			st.RushDirty = Config.CandyRush.SaveEvery -- the end of the rush is written now; still due if this write fails
		end
		task.spawn(Core.Transact, player, "Save", function() end, { Timeout = 2, Silent = true })
	end
	-- blood moon participation
	local bm = State:FindFirstChild("BloodMoon")
	if bm and bm:GetAttribute("State") == "ACTIVE" and inZone and active then
		local cycle = bm:GetAttribute("Cycle")
		if st.BMCycle ~= cycle then
			st.BMCycle, st.BMSeconds, st.BMCredited = cycle, 0, false
		end
		st.BMSeconds += dt
		if not st.BMCredited and st.BMSeconds >= Config.BloodMoon.ParticipationSeconds then
			st.BMCredited = true
			task.spawn(function()
				local ok = Core.Transact(player, "BloodMoon", function(_p, _h, ctx)
					ctx.Quest("BloodMoon", 1)
					ctx.Stat("BloodMoons", 1)
				end)
				if not ok and st.BMCycle == cycle then
					st.BMCredited = false -- busy / not loaded: the next active tick of this moon tries again
				end
			end)
		end
	end
	-- attributes (only on change)
	setAttr(player, "MoonCurse", math.floor(st.Curse * 2 + .5) / 2)
	setAttr(player, "HwInZone", inZone)
	setAttr(player, "HwActive", active)
	setAttr(player, "HwRushActive", rushOn(st))
	setAttr(player, "HwRushRemaining", math.ceil(st.RushRemaining or 0)) -- whole seconds left (counts 600, 599, ... 1)
	local mult = Core.Multiplier(player)
	setAttr(player, "HwCandyMult", math.floor(mult * 20 + .5) / 20)
	local aura = (Core.RushActive(player) and active) or (Core.ServerRushActive() and inZone)
	setAttr(player.Character, "HwRushAura", aura or nil)
end
Core.TickPlayer = tickPlayer -- tests: one 1 s tick of a player's RAM state

---------------------------------------------------------------------------------------------------------------------
-- Requests (RS.Halloween.Remotes.Request)
---------------------------------------------------------------------------------------------------------------------
local handlers = {}
function Core.OnRequest(action: string, fn: (Player, any) -> (boolean, any), opts: { [string]: any }?)
	handlers[action] = { Fn = fn, Cost = opts and opts.Cost or 1, AllowDisabled = opts and opts.AllowDisabled == true }
end

local buckets = {}
local function allow(player: Player, cost: number): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { Tokens = 14, At = now }
		buckets[player] = b
	end
	b.Tokens = math.min(14, b.Tokens + (now - b.At) * 7)
	b.At = now
	if b.Tokens < cost then
		return false
	end
	b.Tokens -= cost
	return true
end

-- tests / Studio: forget a player's request bucket
function Core.ClearRate(player: Player)
	buckets[player] = nil
end

local function clean(value: any, depth: number): boolean
	if depth > 3 then
		return false
	end
	local kind = typeof(value)
	if kind == "string" then
		return #value <= 120
	elseif kind == "number" then
		return value == value and math.abs(value) <= 1e15
	elseif kind == "boolean" or kind == "nil" then
		return true
	elseif kind == "table" then
		local n = 0
		for k, x in pairs(value) do
			n += 1
			if n > 30 or (type(k) ~= "string" and type(k) ~= "number") or not clean(x, depth + 1) then
				return false
			end
		end
		return true
	end
	return false
end

-- THE DEAD YARD activities switched by Config.HalloweenChapter1Enabled (DESIGN §2): off = they refuse. Claims of what a
-- player already earned (CauldronClaim, QuestClaim, QuestBonus, DexClaim) and cosmetics stay open.
local CHAPTER1_ACTIONS = { RushStart = true, CauldronTrick = true, CauldronInvest = true, CauldronBrew = true, HouseKnock = true,
	BossSummon = true }
Core.Chapter1Actions = CHAPTER1_ACTIONS

local function dispatch(player: Player, action: any, args: any)
	if type(action) ~= "string" or #action > 40 then
		return false, "Invalid request"
	end
	if CHAPTER1_ACTIONS[action] and Shared.Enabled() and not Shared.Chapter1Enabled() then
		return false, "THE DEAD YARD is closed for now"
	end
	local h = handlers[action]
	if not h then
		return false, "Unknown action"
	end
	if not h.AllowDisabled and not Shared.Enabled() then
		return false, "The Night of the Buried Moon has ended"
	end
	if args == nil then
		args = {}
	end
	if type(args) ~= "table" or not clean(args, 0) then
		return false, "Invalid request"
	end
	if not allow(player, h.Cost) then
		return false, "Please wait a moment"
	end
	local ok, a, b = pcall(h.Fn, player, args)
	if not ok then
		local msg = tostring(a)
		if string.find(msg, ":%d+:") then
			warn("Halloween request " .. action .. " failed: " .. msg)
			return false, "Something went wrong, try again"
		end
		return false, msg
	end
	return a, b
end
Core.Dispatch = dispatch

---------------------------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------------------------
local function join(player: Player)
	local st = { Ready = false, Curse = 0, LastActivity = -1e9, MoveDist = 0, MinuteStart = os.clock(), MinuteCandy = 0,
		PerfectStart = os.clock(), PerfectCount = 0, InZone = false, BMSeconds = 0 }
	Core.Players[player] = st
	for _ = 1, 120 do
		if not player.Parent or Core.Players[player] ~= st then
			return
		end
		if Runtime.Ready(player) then
			break
		end
		task.wait(1)
	end
	if not Runtime.Ready(player) then
		return
	end
	local ok, p = pcall(function()
		return Runtime.Engine:Get(player.UserId)
	end)
	if ok and type(p) == "table" and type(p.Halloween) == "table" then
		st.Curse = tonumber(p.Halloween.Curse) or 0
	end
	st.SavedCurse = st.Curse
	st.Ready = true
	-- Strength training (the Upgrade Tree STRENGTH branch) clears the curse too
	local lastStrength = player:GetAttribute("MiningStrengthTree") or 0
	player:GetAttributeChangedSignal("MiningStrengthTree"):Connect(function()
		local v = player:GetAttribute("MiningStrengthTree") or 0
		if v > lastStrength then
			Core.Activity(player, "Strength")
		end
		lastStrength = v
	end)
	local okT = Core.Transact(player, "Join", function() end)
	if not okT then
		task.delay(5, function()
			if player.Parent then
				Core.Transact(player, "Join", function() end)
			end
		end)
	end
	for _, fn in ipairs(Core.Listeners.Ready) do
		task.spawn(fn, player)
	end
end

function Core.OnReady(fn: (Player) -> ())
	table.insert(Core.Listeners.Ready, fn)
	for player, st in pairs(Core.Players) do
		if st.Ready then
			task.spawn(fn, player)
		end
	end
end

function Core.OnSouls(fn: (number, Player?) -> ())
	table.insert(Core.Listeners.Souls, fn)
end

function Core.Start()
	if Core.Started then
		return
	end
	Core.Started = true
	local remote = Remotes:WaitForChild("Request")
	remote.OnServerInvoke = dispatch
	Players.PlayerAdded:Connect(function(player)
		task.spawn(join, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(join, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local st = Core.Players[player]
		if st and st.Ready then
			-- last write of the RAM state (curse, rush timer, queued grants) while this server still owns the session. It
			-- never waits for the lock: when the economy's own PlayerRemoving released the profile first, Authorize
			-- refuses it (nothing is written or saved twice) and the copy of the last silent save stands (tickPlayer).
			local q = st.Queue
			st.Queue = nil
			pcall(Core.Transact, player, "Leave", function(_p, _h, ctx)
				if q then
					applyQueue(ctx, q)
				end
			end, { Timeout = 0, Silent = true })
		end
		Core.Players[player] = nil
		buckets[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 3)
			last = now
			for player, st in pairs(Core.Players) do
				if st.Ready and player.Parent then
					local ok, err = pcall(tickPlayer, player, st, dt)
					if not ok then
						warn("Halloween tick failed: " .. tostring(err))
					end
					if st.Queue then
						task.spawn(flushQueue, player, st)
					end
				end
			end
		end
	end)
end

function Core.NewId(): string
	return (HttpService:GenerateGUID(false):gsub("-", ""))
end

return Core
