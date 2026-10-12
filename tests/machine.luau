--!nolint
-- DOG-O-MATIC with the REAL modules from src/ (lune run tests/machine.luau, from the repo root):
-- RewardMachineService (Request/Info/Pool/Resolve), RewardMachineOdds/Config/Text, Rules,
-- ItemRules, SupplyRules, RouletteTickets, RoulettePurchases, WorldEventModifiers and
-- Economy.Transactions (the RAM fast path every spin uses). Only Roblox services and the
-- Runtime module are stubbed; ServerScriptService.Economy.Features is hidden (features have
-- their own tests). Proves: odds sum to 100%; 1000 consecutive activations with a full Energy
-- Snack timer and near-full storage are never refused for prize deliverability; hard caps are
-- the only storage stop; retries are idempotent (RAM receipt and the profile receipt ring);
-- the Rainbow Rift boost applies only while the event is active and is frozen per activation.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local SRC = fs.isDir("src") and "src" or "../src"

-- Deterministic stand-in for Roblox's Random (unseeded generators get fixed, distinct seeds).
local Random = {}
Random.__index = Random
local unseeded = 0
function Random.new(seed)
	if seed == nil then
		unseeded += 1
		seed = 9157 * unseeded
	end
	local state = math.floor(tonumber(seed) or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ State = state }, Random)
end
function Random:NextNumber(a, b)
	self.State = (self.State * 48271) % 2147483647
	local x = self.State / 2147483647
	if a and b then
		return a + (b - a) * x
	end
	return x
end
function Random:NextInteger(a, b)
	return a + math.floor(self:NextNumber() * (b - a + 1))
end

-- Simulated clock for every sandboxed module (os.time) and the transaction layer.
local SIM = { Now = 1760000000 }
local simOs = setmetatable({ time = function()
	return SIM.Now
end }, { __index = os })
local deferred = {}
local simTask = {
	defer = function(fn, ...)
		table.insert(deferred, table.pack(fn, ...))
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	delay = function() end,
	wait = function()
		return 0
	end,
}
local function drain()
	while #deferred > 0 do
		local job = table.remove(deferred, 1)
		job[1](table.unpack(job, 2, job.n))
	end
end
local warnings = {}

-- Instance-like proxies over the src/ tree (Rojo names: X.luau, X.server.luau, X.client.luau, dirs).
-- The tree is indexed and read up front: Lune's fs yields, which is not allowed inside __index
-- (and would suspend a module half-way through its require).
local hidden = { [SRC .. "/ServerScriptService/Economy/Features"] = true }
local files, dirs, listing, sources = {}, {}, {}, {}
local function walk(dir)
	dirs[dir] = true
	listing[dir] = {}
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
			listing[dir][entry] = true
		elseif entry:match("%.luau$") then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			files[dir .. "/" .. name] = path
			sources[path] = fs.readFile(path)
			listing[dir][name] = true
		end
	end
end
walk(SRC)
local nodes, modules, preload = {}, {}, {}
local Node = {}
local function node(path, parent)
	if nodes[path] then
		return nodes[path]
	end
	if hidden[path] then
		return nil
	end
	local file, dir = files[path], dirs[path]
	if not file and not dir then
		return nil
	end
	local name = path:match("([^/]+)$")
	local self = setmetatable({ Path = path, Name = name, File = file, Dir = dir and path or nil }, Node)
	nodes[path] = self
	return self
end
local methods = {}
function methods:FindFirstChild(name)
	if not rawget(self, "Dir") then
		return nil
	end
	return node(rawget(self, "Dir") .. "/" .. name, self)
end
function methods:WaitForChild(name)
	return methods.FindFirstChild(self, name) or error("sandbox: " .. rawget(self, "Path") .. " has no child " .. tostring(name), 2)
end
function methods:GetChildren()
	local list, seen = {}, {}
	if not rawget(self, "Dir") then
		return list
	end
	for name in pairs(listing[rawget(self, "Dir")] or {}) do
		if not seen[name] then
			seen[name] = true
			local child = node(rawget(self, "Dir") .. "/" .. name, self)
			if child then
				table.insert(list, child)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end
function methods:IsA(class)
	if class == "ModuleScript" then
		return rawget(self, "File") ~= nil and not rawget(self, "File"):find("%.server%.luau$") and not rawget(self, "File"):find("%.client%.luau$")
	elseif class == "Folder" then
		return rawget(self, "File") == nil
	end
	return false
end
function methods:GetAttribute()
	return nil
end
local game
Node.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	if key == "Parent" then
		local path = rawget(self, "Path")
		local up = path:match("^(.*)/[^/]+$")
		if not up or up == SRC then
			return game
		end
		return node(up)
	end
	local child = methods.FindFirstChild(self, key)
	if child then
		return child
	end
	error("sandbox: " .. rawget(self, "Path") .. " has no child " .. tostring(key), 2)
end

local function environment(script)
	return {
		script = script,
		game = game,
		workspace = { GetServerTimeNow = function()
			return SIM.Now
		end },
		require = function(target)
			assert(type(target) == "table" and rawget(target, "Path"), "sandbox require needs a src node")
			local path = rawget(target, "Path")
			if preload[path] ~= nil then
				return preload[path]
			end
			if modules[path] == nil then
				local file = assert(rawget(target, "File"), "not a script: " .. path)
				local source = assert(sources[file], "unindexed " .. file)
				local chunk = luau.load(source, { debugName = path, environment = environment(target) })
				modules[path] = chunk()
			end
			return modules[path]
		end,
		Random = Random,
		task = simTask,
		os = simOs,
		warn = function(...)
			table.insert(warnings, table.concat(table.pack(...), " ", 1, select("#", ...)))
		end,
		print = function() end,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Enum = roblox.Enum,
		Font = roblox.Font,
	}
end

local guidCounter = 0
local Http = {}
function Http:GenerateGUID()
	guidCounter += 1
	local hex = string.format("%032x", guidCounter * 7919 + 0x5eed)
	return hex:sub(1, 8) .. "-" .. hex:sub(9, 12) .. "-" .. hex:sub(13, 16) .. "-" .. hex:sub(17, 20) .. "-" .. hex:sub(21, 32)
end
local signal = { Connect = function()
	return { Disconnect = function() end }
end }
local services = {
	ReplicatedStorage = node(SRC .. "/ReplicatedStorage"),
	ServerScriptService = node(SRC .. "/ServerScriptService"),
	ServerStorage = setmetatable({ Path = "ServerStorage", Name = "ServerStorage" }, Node),
	HttpService = Http,
	RunService = {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return false
		end,
	},
	Players = {
		PlayerAdded = signal,
		PlayerRemoving = signal,
		GetPlayers = function()
			return {}
		end,
		GetPlayerByUserId = function()
			return nil
		end,
	},
	PolicyService = {
		GetPolicyInfoForPlayerAsync = function()
			return { ArePaidRandomItemsRestricted = false }
		end,
	},
	MarketplaceService = {},
	LocalizationService = { RobloxLocaleId = "en-us" },
}
game = setmetatable({
	GetService = function(_, name)
		return services[name] or error("sandbox: service " .. tostring(name))
	end,
}, { __index = function(_, key)
	return services[key]
end })

local function load(path)
	local target = node(SRC .. "/" .. path)
	assert(target, "missing " .. path)
	return environment(target).require(target)
end

-- In-memory durable store and the real transaction layer.
local store, writes = {}, 0
local Store = {}
function Store:Read(key)
	return store[key]
end
function Store:Update(key, fn)
	writes += 1
	local value = fn(store[key])
	if value ~= nil then
		store[key] = value
	end
	return store[key]
end
local Transactions = load("ServerScriptService/Economy/Transactions")
local tx = Transactions.new(Store, function()
	return SIM.Now
end, function()
	return Http:GenerateGUID():gsub("-", "")
end)
local runtime = { Tx = tx, Engine = { AssetReady = function()
	return true
end } }
function runtime.Ready()
	return true
end
function runtime.Allow()
	return true
end
function runtime.Refresh() end
function runtime.Engine:Get(id)
	return tx:Read("p:" .. id)
end
function runtime.Engine:Authorize(p, id)
	assert(p and p.UserId == id, "Profile session unavailable")
end
preload[SRC .. "/ServerScriptService/Economy/Runtime"] = runtime
-- The fake players are plain tables: answer the shared PolicyService helper directly.
preload[SRC .. "/ServerScriptService/Economy/PaidRandomPolicy"] = {
	Allowed = function()
		return true
	end,
	TradingAllowed = function()
		return true
	end,
	Info = function()
		return { Ok = true, PaidRandom = true, Trading = true, At = 0 }
	end,
	Forget = function() end,
}

local C = load("ReplicatedStorage/RewardMachineConfig")
local Odds = load("ReplicatedStorage/RewardMachineOdds")
local Text = load("ReplicatedStorage/RewardMachineText")
local Modifiers = load("ReplicatedStorage/WorldEvents/WorldEventModifiers")
local Events = load("ReplicatedStorage/WorldEvents/WorldEventDefinitions")
local E = load("ReplicatedStorage/DogEconomy/Config")
local D = load("ReplicatedStorage/DogEconomy/DogDefinitions")
local R = load("ServerScriptService/Economy/Rules")
local I = load("ServerScriptService/Economy/ItemRules")
local Supply = load("ServerScriptService/Economy/SupplyRules")
local M = load("ServerScriptService/Economy/RewardMachineService")

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
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function sum(rows)
	local n = 0
	for _, row in ipairs(rows) do
		n += row.ChanceUnits
	end
	return n
end
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end
local function aurion(rows)
	for _, row in ipairs(rows) do
		if row.Id == "Aurion" then
			return row
		end
	end
end

local uidSeq = 0
local function newProfile(userId)
	local p = R.Normalize(R.Profile(userId, SIM.Now), userId, SIM.Now)
	tx:_captureProfile("p:" .. userId, p, false)
	return p
end
local function edit(userId, fn)
	local ok, err = tx:Run({ "p:" .. userId }, function(v)
		fn(v["p:" .. userId])
		return true
	end)
	assert(ok, err)
end
local function live(userId)
	return tx.Cache["p:" .. userId]
end
-- A stored dog/item record that passes R.Validate / I.Validate.
local function addDog(p, id)
	uidSeq += 1
	local uid = "fill" .. uidSeq
	local d = R.Mint(p, id or "Breadog", uid, {}, SIM.Now, function()
		return 0.5
	end, "Test", "Normal", true)
	return d
end
local function addItem(p)
	uidSeq += 1
	local def = I.Definitions.dog_tag
	return I.Mint(p, def, 0.1, "item" .. uidSeq, SIM.Now, function()
		return 0.5
	end, {})
end
-- Request ids are 32 hex; the receipt key uses the first 26, so the number goes first.
local function requestId(n)
	return string.format("%08x%024x", n, 0xabc)
end
local function player(userId)
	return { UserId = userId, Name = "Tester" .. userId, DisplayName = "Tester" .. userId, Parent = true }
end
-- Exactly what RewardMachinePresentation.activate does: refusals are raised errors.
local function spin(userId, n)
	local transport, ok, result = pcall(M.Request, player(userId), "RewardMachineActivate", { Request = requestId(n) }, true)
	drain()
	if not transport then
		return false, ok
	end
	return ok, result
end

test("nine sectors; odds sum to exactly 100%", function()
	eq(#C.Rewards, 9, "rows")
	local pool = Text.Pool()
	eq(#pool, 9, "pool rows")
	eq(sum(pool), C.OddsDenominator, "base sum")
	eq(aurion(pool).ChanceUnits, 20, "aurion base units")
	for index, row in ipairs(pool) do
		eq(row.PrizeIndex, index, "prize index")
	end
	local boosted = Text.Pool(5)
	eq(sum(boosted), C.OddsDenominator, "boosted sum")
	eq(aurion(boosted).ChanceUnits, 100, "aurion boosted units")
	eq(#boosted, 9, "boost adds no row")
	local aurions = 0
	for _, row in ipairs(boosted) do
		if row.Id == "Aurion" then
			aurions += 1
		end
	end
	eq(aurions, 1, "exactly one Aurion row")
	-- The config table itself is never edited by a boost.
	eq(C.Rewards[9].FixedUnits, 20, "config untouched")
end)

test("per-player pool: every tier row splits into released dogs and still sums to 100%", function()
	local p = newProfile(10)
	local pool = M.Pool(p, runtime, SIM.Now)
	eq(sum(pool), C.OddsDenominator, "pool sum")
	local tiers = 0
	for _, row in ipairs(pool) do
		if row.Kind == "DogTier" then
			tiers += 1
			local units = 0
			for _, part in ipairs(row.Breakdown) do
				units += part.ChanceUnits
				truthy(#part.Members > 0, "members")
				for _, id in ipairs(part.Members) do
					local def = D[id]
					eq(def.Rank, part.Rank, "member rank")
					truthy(def.CanDropFromRoulette and id ~= "Aurion", "eligible " .. id)
				end
			end
			eq(units, row.ChanceUnits, "breakdown sum " .. row.Name)
			truthy(row.Featured and D[row.Featured], "featured dog")
		end
	end
	eq(tiers, 4, "tier rows")
	-- Every Common/Rare/Epic/Legendary/Mythic dog the machine may award is reachable.
	local reachable = {}
	for _, row in ipairs(pool) do
		for _, part in ipairs(row.Breakdown or {}) do
			for _, id in ipairs(part.Members) do
				reachable[id] = true
			end
		end
	end
	for id, def in pairs(D) do
		if def.CanDropFromRoulette and def.Rank <= 5 then
			truthy(reachable[id], "unreachable " .. id)
		end
	end
end)

test("Rainbow Rift boosts Aurion only while ACTIVE, from the event perk", function()
	local rift = Events.ById.RAINBOW_RIFT
	truthy(rift.Perks.MachineAurion and rift.Perks.MachineAurion > 1, "perk")
	local p = newProfile(11)
	Modifiers.Set(nil)
	eq(M.EventBoost(SIM.Now), nil, "no event")
	eq(aurion(M.Info(p, runtime, SIM.Now, true, M.EventBoost(SIM.Now)).Rewards).ChanceUnits, 20, "base")
	Modifiers.Set("RAINBOW_RIFT", SIM.Now + 240)
	local boost = M.EventBoost(SIM.Now)
	truthy(boost and boost.EventId == "RAINBOW_RIFT" and boost.Multiplier == rift.Perks.MachineAurion, "boost")
	local info = M.Info(p, runtime, SIM.Now, true, boost)
	eq(aurion(info.Rewards).ChanceUnits, 20 * rift.Perks.MachineAurion, "boosted")
	eq(sum(info.Rewards), C.OddsDenominator, "boosted pool sum")
	truthy(info.ActiveBoost and info.ActiveBoost.Multiplier == rift.Perks.MachineAurion, "info shows the boost")
	-- Another event never boosts the machine.
	Modifiers.Set("DOG_RUSH", SIM.Now + 240)
	eq(M.EventBoost(SIM.Now), nil, "other event")
	-- The boost ends with the event (time past EndsAt, or cleared by WorldEventService).
	Modifiers.Set("RAINBOW_RIFT", SIM.Now + 240)
	eq(M.EventBoost(SIM.Now + 240), nil, "expired")
	Modifiers.Set(nil)
	eq(M.EventBoost(SIM.Now), nil, "cleared")
end)

test("the boost is frozen per activation (event ending mid-request keeps the rolled odds)", function()
	local userId = 12
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 50
	end)
	local frozen = { EventId = "RAINBOW_RIFT", Name = "Rainbow Rift", Multiplier = 5, EndsAt = SIM.Now + 10 }
	Modifiers.Set(nil) -- the event already ended on the server
	local forcedAurion = { PrizeIndex = 9, Kind = "Dog", Id = "Aurion", Name = "Aurion", ChanceUnits = 100, DogId = "Aurion" }
	SIM.Now += 10
	local ok, result = tx:Run({ "p:" .. userId, "supply:Aurion" }, function(v)
		return M.Resolve(v, userId, "rs:12:frozen", "frozenuid", SIM.Now, runtime, true, Random.new(4), forcedAurion, frozen)
	end, "ra:12:frozen")
	truthy(ok, result)
	eq(result.Id, "Aurion", "aurion")
	eq(result.ChanceUnits, 100, "receipt keeps the boosted chance")
	eq(result.EventBoost, "RAINBOW_RIFT", "receipt names the event")
	-- Without the frozen boost the same pre-pick no longer matches the pool: refused, nothing spent.
	local before = live(userId).PaidRouletteTickets
	SIM.Now += 10
	local ok2, err = tx:Run({ "p:" .. userId, "supply:Aurion" }, function(v)
		return M.Resolve(v, userId, "rs:12:stale", "staleuid", SIM.Now, runtime, true, Random.new(5), forcedAurion, nil)
	end, "ra:12:stale")
	eq(ok2, false, "stale boost refused")
	truthy(tostring(err):find("Reward pool changed", 1, true), err)
	eq(live(userId).PaidRouletteTickets, before, "no token spent")
end)

test("1000 consecutive activations: full snack timer + near-full storage never refused", function()
	local userId = 20
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 5000
		p.Supplies.EnergySnack = SIM.Now + E.Supplies.EnergySnack.MaxSeconds -- active timer full
		p.SupplyReserve.EnergySnack = Supply.PaidCap - E.Supplies.EnergySnack.MaxSeconds -- stored cap full
		for _ = 1, R.Capacity(p) - 1 do
			addDog(p)
		end
		for _ = 1, I.Capacity(p) - 1 do
			addItem(p)
		end
	end)
	local refusals, kinds, overflow, converted, sold = {}, {}, 0, 0, 0
	local tokens0 = live(userId).PaidRouletteTickets + live(userId).RouletteTickets
	local successes = 0
	for n = 1, 1000 do
		SIM.Now += C.Cooldown + 1
		local p = live(userId)
		-- Keep the snack timer and its stored reserve full the whole run (as Robux snack packs would).
		do
			edit(userId, function(q)
				q.Supplies.EnergySnack = SIM.Now + E.Supplies.EnergySnack.MaxSeconds
				q.SupplyReserve.EnergySnack = Supply.PaidCap - E.Supplies.EnergySnack.MaxSeconds
			end)
		end
		-- A real player sells dogs long before the 250 hard cap; do the same at 240.
		if count(p.Dogs) >= 240 then
			edit(userId, function(q)
				local removed = 0
				for uid in pairs(q.Dogs) do
					if removed >= 100 then
						break
					end
					q.Dogs[uid] = nil
					removed += 1
				end
				sold += removed
			end)
		end
		local ok, result = spin(userId, n)
		if not ok then
			refusals[tostring(result)] = (refusals[tostring(result)] or 0) + 1
		else
			successes += 1
			kinds[result.Kind] = (kinds[result.Kind] or 0) + 1
			if result.Storage then
				overflow += 1
			end
			if (result.Coins or 0) > 0 then
				converted += 1
			end
			-- Retry the same request id: same receipt, nothing spent twice.
			if n % 25 == 0 then
				local before = live(userId).PaidRouletteTickets
				local again, copy = spin(userId, n)
				truthy(again and copy.Receipt == result.Receipt, "idempotent retry")
				eq(live(userId).PaidRouletteTickets, before, "retry spent a token")
			end
		end
		eq(next(tx.Busy), nil, "lock leak")
	end
	for reason, k in pairs(refusals) do
		print("  refused " .. k .. "x: " .. reason)
	end
	eq(next(refusals), nil, "refusals")
	eq(successes, 1000, "successes")
	local p = live(userId)
	eq(tokens0 - (p.PaidRouletteTickets + p.RouletteTickets), 1000, "tokens spent")
	truthy(kinds.Dog and kinds.Item and kinds.Cash and kinds.Bones and kinds.Boost, "every prize kind won")
	truthy(overflow > 0, "prizes overflowed the soft capacity")
	truthy(converted > 0, "snack overflow became coins")
	truthy(count(p.Items) > I.Capacity(p), "items overflowed the soft capacity")
	truthy(#p.RewardHistory <= 12 and #p.RouletteReceipts <= M.ReceiptRing, "bounded history")
	local okValidate, err = pcall(R.Validate, p)
	truthy(okValidate, err)
	print(string.format("  1000 spins: %d dogs, %d items (%d delivered above soft capacity), %d coin, %d bones, %d snack (%d to coins); sold %d; store writes %d",
		kinds.Dog or 0, kinds.Item or 0, overflow, kinds.Cash or 0, kinds.Bones or 0, kinds.Boost or 0, converted, sold, writes))
end)

test("full coin and bone wallets: prizes are clamped, never refused", function()
	local userId = 26
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 5
		p.Cash = E.MaxCash - 100
		p.Bones = E.MaxCash - 3
	end)
	local pool = M.Pool(live(userId), runtime, SIM.Now)
	for n, index in ipairs({ 6, 7 }) do
		SIM.Now += 10
		local row = pool[index]
		local forced = { PrizeIndex = index, Kind = row.Kind, Id = row.Id, Name = row.Name, ChanceUnits = row.ChanceUnits }
		local ok, result = tx:Run({ "p:" .. userId }, function(v)
			return M.Resolve(v, userId, "rs:26:w" .. n, "walletuid" .. n, SIM.Now, runtime, true, Random.new(n), forced, nil)
		end, "ra:26:w" .. n)
		truthy(ok, result)
	end
	eq(live(userId).Cash, E.MaxCash, "coins clamped to the wallet")
	eq(live(userId).Bones, E.MaxCash, "bones clamped to the wallet")
end)

test("Energy Snack prize: overflow waits in SupplyReserve, never refused", function()
	local userId = 21
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 10
		p.Supplies.EnergySnack = SIM.Now + E.Supplies.EnergySnack.MaxSeconds
		p.SupplyReserve.EnergySnack = 0
	end)
	SIM.Now += 10
	local forced = { PrizeIndex = 8, Kind = "Boost", Id = "EnergySnack", Name = "Energy Snack · 15 min" }
	local pool = M.Pool(live(userId), runtime, SIM.Now)
	forced.ChanceUnits = pool[8].ChanceUnits
	local ok, result = tx:Run({ "p:" .. userId }, function(v)
		return M.Resolve(v, userId, "rs:21:snack", "snackuid", SIM.Now, runtime, true, Random.new(9), forced, nil)
	end, "ra:21:snack")
	truthy(ok, result)
	eq(result.Duration, 900, "full duration granted")
	local p = live(userId)
	eq(p.Supplies.EnergySnack, SIM.Now + E.Supplies.EnergySnack.MaxSeconds, "active timer stays at cap")
	truthy((p.SupplyReserve.EnergySnack or 0) >= 900 - 10, "overflow in reserve")
end)

test("hard caps are the only storage stop, checked for every row (no reroll by filling)", function()
	local userId = 22
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 10
		p.Upgrades.DogStorage = 20 -- capacity reaches the 250 hard cap
		for _ = 1, E.MaxDogs do
			addDog(p)
		end
	end)
	local before = live(userId).PaidRouletteTickets
	SIM.Now += 10
	local ok, err = spin(userId, 5001)
	eq(ok, false, "refused at the hard cap")
	truthy(tostring(err):find("maximum of " .. E.MaxDogs .. " dogs", 1, true), err)
	eq(live(userId).PaidRouletteTickets, before, "no token spent")
	local info = M.Info(live(userId), runtime, SIM.Now, true, nil)
	eq(info.ReasonCode, "DogsHardCap", "reason code")
	-- One dog sold: every prize row is deliverable again.
	edit(userId, function(p)
		local uid = next(p.Dogs)
		p.Dogs[uid] = nil
	end)
	SIM.Now += 10
	local ok2, result = spin(userId, 5002)
	truthy(ok2, tostring(result) .. " dogs=" .. count(live(userId).Dogs))
end)

test("durable idempotency: the profile receipt ring answers after the RAM cache forgets", function()
	local userId = 23
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 10
	end)
	SIM.Now += 10
	local ok, first = spin(userId, 7001)
	truthy(ok, first)
	-- Evict every RAM receipt (as after 2,048 other operations).
	tx.Receipts, tx.ReceiptOrder = {}, {}
	local before = live(userId).PaidRouletteTickets + live(userId).RouletteTickets
	SIM.Now += 1 -- still inside the 7 s reset: a NEW request would be refused
	local again, copy = spin(userId, 7001)
	truthy(again, copy)
	eq(copy.Receipt, first.Receipt, "same receipt")
	truthy(copy.Duplicate, "flagged duplicate")
	eq(live(userId).PaidRouletteTickets + live(userId).RouletteTickets, before, "nothing spent twice")
	eq(live(userId).RouletteReceipts[1].Receipt, first.Receipt, "ring entry")
end)

test("draw frequencies follow the disclosed slots (20,000 pre-picks)", function()
	local p = newProfile(24)
	local pool = M.Pool(p, runtime, SIM.Now)
	local picker = Random.new(2024)
	local hits = {}
	local N = 20000
	for _ = 1, N do
		local row = Odds.Pick(pool, picker:NextInteger(1, C.OddsDenominator), C.OddsDenominator)
		hits[row.PrizeIndex] = (hits[row.PrizeIndex] or 0) + 1
		if row.Kind == "DogTier" then
			local id = M.PickMember(row, picker)
			truthy(id and M.IsMember(row, id), "member")
		end
	end
	for _, row in ipairs(pool) do
		local expected = N * row.Chance
		local tolerance = 5 * math.sqrt(math.max(1, expected)) + 2
		truthy(math.abs((hits[row.PrizeIndex] or 0) - expected) <= tolerance, row.Name .. " frequency " .. tostring(hits[row.PrizeIndex]))
	end
end)

test("Info normalizes the read copy (Robux snack reserve) and never gates on prizes", function()
	local userId = 25
	newProfile(userId)
	edit(userId, function(p)
		p.PaidRouletteTickets = 3
		p.Supplies.EnergySnack = SIM.Now - 1
		p.SupplyReserve.EnergySnack = 4 * 3600
	end)
	SIM.Now += 30
	local ok, info = M.Request(player(userId), "RewardMachineInfo", {}, false)
	truthy(ok, info)
	eq(info.CanSpin, true, "can spin")
	eq(info.UnavailableReason, nil, "no reason")
end)

test("RU dictionary covers the generated machine strings", function()
	local L = load("ReplicatedStorage/Localization/Machine")
	local function ru(text)
		if L.Exact[text] then
			return L.Exact[text]
		end
		for _, rule in ipairs(L.Patterns) do
			local out, n = text:gsub(rule[1], rule[2])
			if n > 0 then
				return out
			end
		end
		return nil
	end
	local base, boosted = Text.Pool(), Text.Pool(5)
	for _, pool in ipairs({ base, boosted }) do
		for _, row in ipairs(pool) do
			local title = Text.FaceTitle(C.Rewards[row.PrizeIndex])
			truthy(row.Coins or ru(title), "face title " .. title)
			truthy(ru(Text.FaceSubtitle(row)), "subtitle " .. Text.FaceSubtitle(row))
			local board = Text.BoardRow(row)
			if not row.Coins then
				truthy(ru(board), "board row " .. board)
			end
		end
		truthy(ru(Text.Plaque(aurion(pool))), "plaque " .. Text.Plaque(aurion(pool)))
	end
	eq(ru(Text.BoardRow(aurion(boosted))), "РАДУГА x5: Аурион  1,00%", "boosted board row")
	eq(ru("2,400 Coins  26.60%"), "2,400 монет  26,60%", "coin board row")
	eq(ru(string.format("You own the maximum of %d dogs. Sell or release a dog to spin.", E.MaxDogs)), "У тебя максимум собак: 250. Продай или отпусти собаку, чтобы крутить.", "hard cap")
	eq(ru("AURION HOWLS · x5 CHANCE"), "АУРИОН ВОЕТ · ШАНС x5", "boost banner")
	eq(ru("✦ x5 AURION CHANCE ON DOG-O-MATIC"), "✦ ШАНС НА АУРИОНА x5 В DOG-O-MATIC", "perk line")
	-- Every refusal the server can send has a Russian line.
	for _, reason in ipairs({ "Your free DOG TOKEN is still recharging", "Paid random tickets are unavailable for this account; your tickets are kept",
		"Please wait for this activation to finish", "Move closer to DOG-O-MATIC", "Please wait before trying again", "Your previous activation is still being processed",
		"Aurion is preparing to arrive. Please try again shortly.", "Rewards are temporarily unavailable", "Reward pool changed; please activate again",
		"Activation unavailable; please retry", "GLOBAL EVENT", "GLOBAL EVENT — COMING SOON" }) do
		truthy(ru(reason), "missing RU: " .. reason)
	end
	-- The perk line exists on Rainbow Rift only, first in the list (the COMING UP cards show two).
	eq(Events.PerkLines(Events.ById.RAINBOW_RIFT)[1], "x5 AURION CHANCE ON DOG-O-MATIC", "rainbow perk line")
	for id, def in pairs(Events.ById) do
		if id ~= "RAINBOW_RIFT" then
			truthy(not def.Perks.MachineAurion, "only Rainbow boosts Aurion: " .. id)
		end
	end
end)

print(string.format("machine: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("machine tests failed")
end
