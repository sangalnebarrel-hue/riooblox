--!nocheck
-- Kennel work state (DogKennelService) against the real economy: lune run tests/kennel.luau
-- The real ServerScriptService.DogKennelService runs over a few fake instances (yard, slot, kennel
-- model, inventory entry); Rules/ItemRules/Config are the real src modules (tests/lib/economy_env).
-- Proves: a full item bag never stops a kennel dog. R.Dig keeps paying its loot into the wallet,
-- so the dog stays on its dig chain (AnimationName Work, Producing) and only reports FindsFull;
-- a stalled economy tick still puts it to rest.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local L = require("./lib/economy_env")
local R = L.Require("ServerScriptService.Economy.Rules")
local I = L.Require("ServerScriptService.Economy.ItemRules")

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
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n += 1 end
	return n
end

-- Fake instances: attributes only (what DogKennelService reads and writes).
local function fake(name, attributes)
	local o = { Name = name, Attributes = attributes or {}, Writes = {}, Children = {} }
	function o:GetAttribute(key) return self.Attributes[key] end
	function o:SetAttribute(key, value)
		self.Attributes[key] = value
		self.Writes[key] = (self.Writes[key] or 0) + 1
	end
	function o:GetChildren() return table.clone(self.Children) end
	function o:FindFirstChild(child)
		for _, c in ipairs(self.Children) do if c.Name == child then return c end end
		return nil
	end
	function o:Destroy() self.Destroyed = true end
	return o
end

-- The real DogKennelService with a stub Runtime (Views) and a fake district.
local runtime = { Views = {}, Loaded = {} }
function runtime.Ready() return true end
function runtime.Allow() return true end
function runtime.Refresh() end
L.Overrides["ServerScriptService/Economy/Runtime"] = runtime
L.Overrides["ReplicatedStorage/DogRig"] = {}
local residents, yards = fake("KennelDogs"), fake("04_PlayerYards")
local district = fake("DOGROTS_District")
district.Children = { residents, yards }
function district:WaitForChild(child) return self:FindFirstChild(child) end
local function loadKennels()
	local path = "src/ServerScriptService/DogKennelService.luau"
	local script = L.Game.ServerScriptService.DogKennelService
	local env = setmetatable({
		script = script,
		game = L.Game,
		workspace = {
			WaitForChild = function(_, child) return child == "DOGROTS_District" and district or nil end,
			GetServerTimeNow = function() return L.Time end,
		},
		require = function(target)
			local p = L.Paths[target]
			assert(p, "require: not a src module")
			return L.Require((p:gsub("/", ".")))
		end,
		os = setmetatable({ time = function() return L.Time end }, { __index = os }),
		warn = function() end,
		print = function() end,
		task = { wait = function() end, spawn = function() end, defer = function() end, delay = function() end },
	}, { __index = _G })
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end
local Kennels = loadKennels()

local NOW = 1760000000
-- One working dog in DigSlot_1 of player 1's yard, its kennel model already placed.
local function setup(fillBag)
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p.UnlockedLayers["1"] = true
	p.CurrentLayer = 1
	p.LastDig = NOW
	local d = R.Mint(p, "Breadog", "dog1", {}, NOW, rng(1), "Test", "Normal", true)
	d.AssignedSlot, d.State, d.NextWorkAt = "DigSlot_1", "Digging", NOW
	if fillBag then
		local capacity = R.Storage(p, NOW).ItemCapacity
		for i = 1, capacity do
			I.Mint(p, I.Definitions.dog_tag, 0.1, "bag" .. i, NOW, rng(100 + i), {})
		end
	end
	runtime.Views[1] = p
	local slot = fake("DigSlot_1")
	local yard = fake("Yard_1", { OwnerUserId = 1 })
	yard.Children = { slot }
	yards.Children = { yard }
	local model = fake("dog1", { OwnerUserId = 1, DogUid = "dog1", AssignedSlot = "DigSlot_1", AnimationName = "Idle" })
	residents.Children = { model }
	local inventory = fake("DogInventory")
	inventory.Children = { fake("dog1") }
	local player = { UserId = 1, DogInventory = inventory }
	Kennels.Reconcile(player, p)
	return p, model, player
end
-- The Runtime main loop: UpdateWorkVisuals, then due dogs dig (R.Dig) and the owner refreshes.
local function run(p, model, player, from, to, ticking, random, log)
	for t = from, to do
		L.Time = t
		Kennels.UpdateWorkVisuals()
		local due = false
		for _, d in pairs(p.Dogs) do if d.AssignedSlot ~= "" and t >= d.NextWorkAt then due = true end end
		if ticking and due then
			R.Dig(p, t, random)
			Kennels.Reconcile(player, p)
		end
		if log then table.insert(log, { T = t, Role = model:GetAttribute("AnimationName"), Producing = model:GetAttribute("Producing"),
			FindsFull = model:GetAttribute("FindsFull"), StorageFull = model:GetAttribute("StorageFull") }) end
	end
end

test("a full item bag: the dog keeps digging and earning, the kennel stays on Work", function()
	local p, model, player = setup(true)
	truthy(R.Storage(p, NOW).ItemFull, "bag is full")
	local cash0, items0 = p.Cash, count(p.Items)
	local log = {}
	run(p, model, player, NOW, NOW + 90, true, rng(9), log)
	local d = p.Dogs.dog1
	truthy(d.WorkSequence >= 3, "the dog dug " .. tostring(d.WorkSequence) .. " times")
	truthy(p.Cash > cash0, "income was paid into the wallet")
	eq(count(p.Items), items0, "no item fits in the full bag")
	truthy(R.Storage(p, L.Time).ItemFull, "bag still full")
	for _, row in ipairs(log) do
		eq(row.Role, "Work", "t+" .. (row.T - NOW) .. " AnimationName")
		eq(row.Producing, true, "t+" .. (row.T - NOW) .. " Producing")
		eq(row.FindsFull, true, "t+" .. (row.T - NOW) .. " FindsFull")
		eq(row.StorageFull, false, "t+" .. (row.T - NOW) .. " StorageFull")
	end
	eq(model:GetAttribute("WorkState"), "DIGGING", "WorkState")
	eq(model.Writes.AnimationName or 0, 1, "role written once")
end)

test("room in the bag: FindsFull clears, the dog keeps working", function()
	local p, model, player = setup(false)
	run(p, model, player, NOW, NOW + 30, true, rng(4))
	eq(model:GetAttribute("AnimationName"), "Work", "role")
	eq(model:GetAttribute("FindsFull"), false, "FindsFull")
end)

test("a stalled economy tick still puts the dog to rest, then it digs again", function()
	local p, model, player = setup(true)
	run(p, model, player, NOW, NOW + 20, true, rng(5))
	eq(model:GetAttribute("AnimationName"), "Work", "working before the stall")
	local deadline = p.Dogs.dog1.NextWorkAt
	run(p, model, player, NOW + 21, deadline + 5, false, rng(6))
	eq(model:GetAttribute("AnimationName"), "Idle", "resting while the tick is stalled")
	eq(model:GetAttribute("Producing"), false, "not producing while stalled")
	run(p, model, player, deadline + 6, deadline + 8, true, rng(7))
	eq(model:GetAttribute("AnimationName"), "Work", "digging again once the tick resumes")
end)

print(string.format("kennel: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("kennel tests failed")
end
