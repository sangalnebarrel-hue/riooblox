--!nocheck
-- Main tutorial v4 (docs/halloween2/TUTORIAL.md): the shared track (ReplicatedStorage.TutorialConfig), the server rules
-- (Economy.OnboardingRules: each step's completion from profile state, ordering, SKIP THIS STEP timing, the
-- v3 -> v4 migration matrix, veterans never pulled back, the free Lucky Block once and cap aware), the request
-- service (Economy.OnboardingService: Arrive validated against server positions) and the localization of the
-- client director. Runs the real modules from src/ (tests/lib/economy_env.luau). lune run tests/tutorial.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

local NOW = 1760000000
L.Time = NOW
local Vector3 = roblox.Vector3

local TC = L.Require("ReplicatedStorage.TutorialConfig")
local R = L.Require("ServerScriptService.Economy.Rules")
local O = L.Require("ServerScriptService.Economy.OnboardingRules")
local S = L.Require("ServerScriptService.Economy.OnboardingService")
local LuckyConfig = L.Require("ReplicatedStorage.LuckyLifecycleConfig")

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
local function errors(fn, expected)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error: " .. tostring(expected), 2)
	end
	if expected and not string.find(tostring(err), expected, 1, true) then
		error("expected error '" .. expected .. "' got '" .. tostring(err) .. "'", 2)
	end
	return err
end
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end

-- A fresh profile as R.Profile makes it (Onboarding v4, step 0).
local function fresh()
	return R.Profile(1, NOW)
end
local function step(p)
	return p.Onboarding.Step
end
-- Real LuckyLifecycle.AddStored for the free block.
local Lucky = L.Require("ServerScriptService.Economy.LuckyLifecycle")
local function addBlock(p, tier, n, origin, paid)
	return Lucky.AddStored(p, tier, n, origin, paid)
end
local function apply(p, action, now, args, opts)
	return O.Apply(p, action, now or NOW, args, opts)
end
-- Walks a fresh profile to `target` with the real evidence of every step on the way.
local evidence = {}
evidence[1] = function(p)
	p.Dogs.D1 = { DogUid = "D1", DogId = "Breadog", OwnerUserId = 1, AssignedSlot = "", State = "Inventory" }
end
evidence[2] = function(p)
	p.Dogs.D1.AssignedSlot = "DigSlot_1"
end
evidence[3] = function(p)
	p.TotalExcavations = 1
end
evidence[4] = function(p, now)
	apply(p, "Seen", now, { Key = "Inventory" })
end
evidence[5] = function(p)
	p.Stats = p.Stats or {}
	p.Stats.TotalSellValue = 120
end
evidence[6] = function(p)
	p.Upgrades.Dig = 1
end
evidence[7] = function(p, now)
	apply(p, "Seen", now, { Key = "Layers" })
end
evidence[8] = function(p)
	p.Mining.Hits = 1
end
evidence[9] = function(p)
	p.Upgrades.IronGrip = 1
end
evidence[10] = function(p, now)
	apply(p, "Arrive", now, { Key = "LuckyPad" }, { Near = true, AddBlock = addBlock })
end
evidence[11] = function(p, now)
	apply(p, "Arrive", now, { Key = "Lab" }, { Near = true })
end
evidence[12] = function(p, now)
	apply(p, "Seen", now, { Key = "DogDex" })
end
evidence[13] = function(p, now)
	apply(p, "Seen", now, { Key = "Trade" })
end
local function walk(target)
	local p = fresh()
	apply(p, "Start")
	for i = 1, target - 1 do
		evidence[i](p, NOW)
		O.Observe(p, NOW)
	end
	eq(step(p), target, "walk to step " .. target)
	return p
end

------------------------------------------------------------------------------------------------------------------------
-- The track
------------------------------------------------------------------------------------------------------------------------
test("config: 15 contiguous steps, every task step has a flag, keys only on View / Arrive", function()
	eq(TC.Version, 4)
	eq(TC.LastStep, 14)
	eq(O.Version, 4)
	local flags = {}
	for i = 0, TC.LastStep do
		local s = TC.Steps[i]
		truthy(s, "step " .. i)
		if i == 0 then
			eq(s.Kind, "Intro")
		elseif i == TC.LastStep then
			eq(s.Kind, "Final")
		else
			truthy(s.Flag, "flag of " .. i)
			truthy(not flags[s.Flag], "duplicate flag " .. tostring(s.Flag))
			flags[s.Flag] = true
			truthy(s.Kind == "Milestone" or s.Kind == "View" or s.Kind == "Arrive", "kind of " .. i)
			eq((s.Kind == "View" or s.Kind == "Arrive"), s.Key ~= nil, "key of step " .. i)
			truthy(s.Destination or s.Screen, "step " .. i .. " has a destination or a screen")
		end
	end
	for _, key in ipairs({ "LuckyPad", "Lab" }) do
		truthy(TC.Arrive[key] and TC.Arrive[key].Radius > 0 and TC.Arrive[key].Slack > 0, "arrive spec " .. key)
	end
	eq(TC.SkipAfter, 120)
	eq(TC.RequestTimeout, 8)
	eq(TC.FocusSeconds, 2.2)
	eq(TC.TargetWait, 3)
	eq(TC.FreeBlock.Tier, "Common")
	for old = 0, 17 do
		local new = TC.MigrateV3[old]
		truthy(new and new >= 0 and new <= TC.LastStep, "v3 step " .. old .. " maps into the track")
		if old > 0 then
			truthy(new >= TC.MigrateV3[old - 1], "the v3 map never goes backwards at step " .. old)
		end
	end
end)

test("new profiles start v4 at the welcome card and wait for START", function()
	local p = fresh()
	eq(p.Onboarding.Version, 4)
	eq(p.Onboarding.Status, "Active")
	eq(step(p), 0)
	-- even with a dog, the welcome card waits
	evidence[1](p)
	O.Observe(p, NOW)
	eq(step(p), 0)
	local view = apply(p, "Start")
	-- START jumps straight past what the profile already proves
	eq(view.Step, 2)
	eq(view.Active, true)
	eq(p.Onboarding.StepAt, NOW)
end)

test("each step completes from its profile state, in order, and FINISH completes the tutorial", function()
	local p = fresh()
	apply(p, "Start", NOW)
	eq(step(p), 1)
	for i = 1, 13 do
		local before = step(p)
		eq(before, i, "at step " .. i)
		O.Observe(p, NOW + i)
		eq(step(p), i, "step " .. i .. " waits for its own evidence")
		evidence[i](p, NOW + i)
		O.Observe(p, NOW + i)
		eq(step(p), i + 1, "step " .. i .. " completes from its evidence")
		eq(p.Onboarding.StepAt, NOW + i, "StepAt of step " .. (i + 1))
	end
	eq(step(p), 14)
	local view = O.View(p, NOW + 20)
	eq(view.Kind, "Final")
	eq(view.Skippable, false, "the final card is not a skippable step")
	view = apply(p, "Finish", NOW + 20)
	eq(view.Status, "Complete")
	eq(view.Active, false)
	eq(p.Onboarding.CompletedAt, NOW + 20)
	-- the record is stable afterwards
	R.Validate(p)
	eq(p.Onboarding.Status, "Complete")
	eq(step(p), 14)
end)

test("ordering: later evidence never skips an unfinished earlier step, then fast-forwards", function()
	local p = fresh()
	apply(p, "Start")
	-- mined, upgraded, strength and a trade before even buying a dog
	p.Mining.Hits = 5
	p.Upgrades.Dig = 2
	p.Upgrades.IronGrip = 1
	p.Stats.CompletedTrades = 1
	O.Observe(p, NOW)
	eq(step(p), 1, "still on BUY A DOG")
	evidence[1](p)
	evidence[2](p)
	evidence[3](p)
	O.Observe(p, NOW + 5)
	eq(step(p), 4, "stops at COLLECT (a view step nobody reported yet)")
	evidence[4](p, NOW + 6)
	eq(step(p), 5, "SELL needs a sale")
	evidence[5](p)
	O.Observe(p, NOW + 7)
	eq(step(p), 7, "UPGRADE TREE was already done: on to LAYERS")
	evidence[7](p, NOW + 8)
	eq(step(p), 10, "the quarry and STRENGTH were already done: on to LUCKY BLOCKS")
end)

test("view steps accept only the current step's key; late reports are harmless", function()
	local p = walk(7)
	errors(function()
		apply(p, "Seen", NOW, { Key = "DogDex" })
	end, "not the current tutorial step")
	errors(function()
		apply(p, "Seen", NOW, { Key = "Nonsense" })
	end, "not the current tutorial step")
	eq(step(p), 7)
	-- an Arrive key is not a Seen key
	errors(function()
		apply(p, "Seen", NOW, { Key = "LuckyPad" })
	end)
	apply(p, "Seen", NOW, { Key = "Layers" })
	eq(step(p), 8)
	-- the same report again (a retry after a lost reply) is fine
	local view = apply(p, "Seen", NOW, { Key = "Layers" })
	eq(view.Step, 8)
	eq(p.Onboarding.Seen.Layers, true)
end)

test("SKIP THIS STEP opens 120 s after the step started and records the skip", function()
	local p = walk(8)
	local started = p.Onboarding.StepAt
	eq(O.View(p, started + 119).Skippable, false)
	errors(function()
		apply(p, "SkipStep", started + 119)
	end, "Keep trying")
	eq(step(p), 8)
	eq(O.View(p, started + 120).Skippable, true)
	local view = apply(p, "SkipStep", started + 120)
	eq(view.Step, 9)
	eq(p.Onboarding.Skipped["8"], true)
	eq(p.Onboarding.StepAt, started + 120, "the next step's timer starts now")
	eq(view.Skippable, false)
	-- the next step has its own 120 s
	errors(function()
		apply(p, "SkipStep", started + 200)
	end, "Keep trying")
	apply(p, "SkipStep", started + 240)
	eq(step(p), 10)
	-- the welcome and the final card are never "skip step"
	local q = fresh()
	errors(function()
		apply(q, "SkipStep", NOW + 9999)
	end, "cannot be skipped")
	local r = walk(13)
	apply(r, "SkipStep", r.Onboarding.StepAt + 120)
	eq(step(r), 14)
	errors(function()
		apply(r, "SkipStep", NOW + 99999)
	end, "cannot be skipped")
	eq(TC.CanSkipStep(0, 0, NOW), false)
	eq(TC.CanSkipStep(14, 0, NOW), false)
	eq(TC.CanSkipStep(3, NOW, NOW + 120), true)
end)

test("a skipped step whose evidence arrives later does not move the track backwards", function()
	local p = walk(5)
	apply(p, "SkipStep", p.Onboarding.StepAt + 120)
	eq(step(p), 6)
	evidence[5](p) -- the sale happens after the skip
	O.Observe(p, NOW + 500)
	eq(step(p), 6)
	eq(p.Onboarding.Seen.Sold, true)
end)

test("SKIP (the whole tutorial) is permanent and needs no timer", function()
	local p = walk(3)
	local view = apply(p, "Skip", NOW + 1)
	eq(view.Status, "Skipped")
	eq(view.Active, false)
	eq(p.Onboarding.SkippedAt, NOW + 1)
	evidence[3](p)
	R.Validate(p)
	eq(p.Onboarding.Status, "Skipped")
	errors(function()
		apply(p, "Seen", NOW, { Key = "Inventory" })
	end, "not running")
	errors(function()
		apply(p, "SkipStep", NOW + 999)
	end, "not running")
	-- START never revives it
	apply(p, "Start")
	eq(p.Onboarding.Status, "Skipped")
end)

------------------------------------------------------------------------------------------------------------------------
-- Migration
------------------------------------------------------------------------------------------------------------------------
local function v3(status, oldStep, extra)
	local p = fresh()
	p.Onboarding = { Version = 3, Status = status, Step = oldStep, Seen = {} }
	for k, v in pairs(extra or {}) do
		p.Onboarding[k] = v
	end
	return p
end

test("migration v3 -> v4: every active v3 step maps into the new track (and fast-forwards)", function()
	for old = 0, 17 do
		local p = v3("Active", old)
		O.Normalize(p)
		eq(p.Onboarding.Version, 4, "version after migrating step " .. old)
		eq(p.Onboarding.Status, "Active")
		eq(step(p), TC.MigrateV3[old], "v3 step " .. old)
		eq(p.Onboarding.From, 3)
	end
	-- an old step-7 player who already mined: LAYERS first, then the quarry is skipped at once
	local p = v3("Active", 8)
	p.Dogs.D1 = { DogUid = "D1", DogId = "Breadog", OwnerUserId = 1, AssignedSlot = "DigSlot_1", State = "Digging" }
	p.TotalExcavations = 4
	p.Stats.TotalSellValue = 10
	p.Upgrades.Dig = 1
	p.Mining.Hits = 3
	O.Observe(p, NOW)
	eq(step(p), 7)
	eq(p.Onboarding.StepAt, NOW, "the migrated step's timer starts now")
	apply(p, "Seen", NOW, { Key = "Layers" })
	eq(step(p), 9, "the quarry was done in v3: straight to STRENGTH")
	-- the v3 milestone flags are kept
	local q = v3("Active", 6, { Seen = { DogOwned = true, Assigned = true, Found = true, Sold = true } })
	O.Normalize(q)
	eq(q.Onboarding.Seen.Sold, true)
end)

test("migration matrix: finished, skipped and migrated veterans stay out of the tutorial", function()
	local cases = {
		{ "Complete", 17, nil, "Complete" },
		{ "Complete", 3, nil, "Complete" },
		{ "Skipped", 5, nil, "Skipped" },
		{ "Skipped", 17, nil, "Skipped" },
		{ "Complete", 17, { Migrated = true }, "Complete" },
		-- a migrated veteran whose record says Active (corrupt) is still a veteran
		{ "Active", 2, { Migrated = true }, "Complete" },
		{ "Active", 0, { Migrated = true }, "Complete" },
	}
	for i, case in ipairs(cases) do
		local p = v3(case[1], case[2], case[3])
		-- a veteran profile: lots of evidence for every step
		evidence[1](p)
		evidence[2](p)
		p.TotalExcavations = 9
		O.Observe(p, NOW)
		R.Validate(p)
		eq(p.Onboarding.Status, case[4], "case " .. i)
		eq(p.Onboarding.Version, 4, "case " .. i)
		eq(step(p), 14, "case " .. i)
		eq(O.View(p, NOW).Active, false, "case " .. i .. " inactive")
		-- no action brings them back
		apply(p, "Start")
		eq(O.View(p, NOW).Active, false, "case " .. i .. " after START")
		errors(function()
			apply(p, "Seen", NOW, { Key = "Inventory" })
		end, "not running")
	end
	-- the old exclusion: migrated veterans used to skip every later migration; now they migrate (and stay done)
	local m = v3("Complete", 17, { Migrated = true })
	O.Normalize(m)
	eq(m.Onboarding.Version, 4)
	eq(m.Onboarding.Migrated, true)
	eq(m.Onboarding.CompletedAt, nil, "a migrated veteran has no completion date")
end)

test("migration: missing records, older versions and records from a newer build", function()
	-- no record at all: an experienced player is a migrated veteran, a fresh one starts the tutorial
	local vet = fresh()
	vet.Onboarding = nil
	vet.Level = 3
	O.Normalize(vet)
	eq(vet.Onboarding.Status, "Complete")
	eq(vet.Onboarding.Migrated, true)
	eq(vet.Onboarding.Step, 14)
	local new = fresh()
	new.Onboarding = nil
	O.Normalize(new)
	eq(new.Onboarding.Status, "Active")
	eq(new.Onboarding.Step, 0)
	-- version 2 (and 1): v3 first moved them to min(step, 7), then the v3 map
	local v2 = fresh()
	v2.Onboarding = { Version = 2, Status = "Active", Step = 12, Seen = {} }
	O.Normalize(v2)
	eq(v2.Onboarding.Step, TC.MigrateV3[7])
	local v1 = fresh()
	v1.Onboarding = { Version = 1, Status = "Active", Step = 3 }
	O.Normalize(v1)
	eq(v1.Onboarding.Step, 3)
	eq(type(v1.Onboarding.Seen), "table")
	-- garbage is healed, not fatal
	local bad = fresh()
	bad.Onboarding = { Version = "x", Status = 42, Step = "nope", Seen = 7 }
	O.Normalize(bad)
	eq(bad.Onboarding.Version, 4)
	eq(bad.Onboarding.Status, "Active")
	eq(bad.Onboarding.Step, 0)
	-- a record written by a newer build is left alone (rollback safety)
	local future = fresh()
	future.Onboarding = { Version = 5, Status = "Active", Step = 21, Seen = { Whatever = true }, Extra = "keep" }
	O.Observe(future, NOW)
	eq(future.Onboarding.Version, 5)
	eq(future.Onboarding.Step, 21)
	eq(future.Onboarding.Extra, "keep")
	local view = O.View(future, NOW)
	eq(view.Active, false, "an unknown future track is not driven by this build")
	eq(view.Step, 14)
	for _, action in ipairs({ "Start", "SkipStep", "Skip", "Claim" }) do
		errors(function()
			apply(future, action, NOW + 999, nil, { NoPad = true, AddBlock = addBlock })
		end, "not running")
	end
	eq(future.Onboarding.Step, 21, "untouched by any action")
	-- the whole profile pipeline (R.Normalize / R.Validate) migrates too
	local whole = fresh()
	whole.Onboarding = { Version = 3, Status = "Active", Step = 13, Seen = {} }
	whole.Session = { Id = "s", Expires = NOW + 100 }
	R.Normalize(whole, 1, NOW)
	R.Validate(whole)
	eq(whole.Onboarding.Version, 4)
	eq(whole.Onboarding.Step, 11)
end)

------------------------------------------------------------------------------------------------------------------------
-- The free Lucky Block
------------------------------------------------------------------------------------------------------------------------
local function blocksOf(p, origin)
	local list = {}
	for _, b in pairs(p.OwnedBlocks or {}) do
		if not origin or b.Origin == origin then
			table.insert(list, b)
		end
	end
	return list
end

test("free block: granted once at the Lucky Pad, a stored free Common block", function()
	local p = walk(10)
	eq(#blocksOf(p, "Tutorial"), 0)
	local view = apply(p, "Arrive", NOW + 3, { Key = "LuckyPad" }, { Near = true, AddBlock = addBlock })
	eq(view.Step, 11)
	truthy(view.FreeBlock and view.FreeBlock.Granted, "reply says granted")
	local list = blocksOf(p, "Tutorial")
	eq(#list, 1)
	local b = list[1]
	eq(b.Tier, "Common")
	eq(b.State, "Stored")
	eq(b.PaidRandom, false, "a gift is never a paid random item")
	eq(b.OwnerUserId, 1)
	eq(view.FreeBlock.Uid, b.Uid)
	eq(p.Onboarding.FreeBlock, true)
	eq(p.Onboarding.FreeBlockAt, NOW + 3)
	-- a retried report and a CLAIM later never grant a second one
	apply(p, "Arrive", NOW + 4, { Key = "LuckyPad" }, { Near = true, AddBlock = addBlock })
	errors(function()
		apply(p, "Claim", NOW + 9999, nil, { NoPad = true, AddBlock = addBlock })
	end, "not the current tutorial step")
	eq(#blocksOf(p, "Tutorial"), 1)
	R.Validate(p)
	-- the rules alone never grant twice either
	eq(O.GrantFreeBlock(p, p.Onboarding, NOW, addBlock), nil)
	eq(#blocksOf(p, "Tutorial"), 1)
end)

test("free block: cap aware (full storage: no block, the step still completes)", function()
	local p = walk(10)
	for i = 1, LuckyConfig.InventoryCapacity do
		local uid = string.format("%032x", 900000 + i)
		p.OwnedBlocks[uid] = { Uid = uid, OwnerUserId = 1, Tier = "Common", State = "Stored", PurchasedAt = NOW, PaidRandom = false, Origin = "Test" }
	end
	local view = apply(p, "Arrive", NOW, { Key = "LuckyPad" }, { Near = true, AddBlock = addBlock })
	eq(view.Step, 11)
	eq(view.FreeBlock.Granted, false)
	eq(view.FreeBlock.Reason, "Full")
	eq(count(p.OwnedBlocks), LuckyConfig.InventoryCapacity, "nothing over the cap")
	eq(p.Onboarding.FreeBlockFull, true)
	eq(p.Onboarding.FreeBlock, nil)
end)

test("free block: CLAIM needs the 120 s timer or no pad at all; placing your own block also completes the step", function()
	local p = walk(10)
	local started = p.Onboarding.StepAt
	errors(function()
		apply(p, "Claim", started + 30, nil, { NoPad = false, AddBlock = addBlock })
	end, "Walk to a Lucky Pad")
	eq(#blocksOf(p, "Tutorial"), 0)
	local view = apply(p, "Claim", started + 120, nil, { NoPad = false, AddBlock = addBlock })
	eq(view.Step, 11)
	eq(#blocksOf(p, "Tutorial"), 1)
	-- no yard / pad: CLAIM works at once
	local q = walk(10)
	apply(q, "Claim", q.Onboarding.StepAt + 1, nil, { NoPad = true, AddBlock = addBlock })
	eq(step(q), 11)
	eq(#blocksOf(q, "Tutorial"), 1)
	-- a block placed on a pad (or one ever opened) is the evidence: no free block needed
	local r = walk(10)
	local uid = string.format("%032x", 777)
	r.OwnedBlocks[uid] = { Uid = uid, OwnerUserId = 1, Tier = "Rare", State = "Placed", Slot = 1 }
	O.Observe(r, NOW)
	eq(step(r), 11)
	eq(#blocksOf(r, "Tutorial"), 0)
	local s = walk(10)
	s.LuckyOpened = { Common = 1 }
	O.Observe(s, NOW)
	eq(step(s), 11)
end)

------------------------------------------------------------------------------------------------------------------------
-- The service: Arrive validated with server positions
------------------------------------------------------------------------------------------------------------------------
local function fakeRuntime(p)
	local rt = { Profile = p, Calls = 0 }
	rt.Engine = { Authorize = function() end }
	rt.Tx = {
		Run = function(_, keys, fn)
			rt.Calls += 1
			-- a transform works on a copy: an error rolls back (as Transactions does)
			local copy = R.Copy(rt.Profile)
			local ok, result = pcall(fn, { [keys[1]] = copy })
			if not ok then
				return false, result
			end
			rt.Profile = copy
			return true, result
		end,
	}
	return rt
end
local player = { UserId = 1, Name = "Tester" }
local world = { Position = nil, Points = {} }
S.World.Position = function()
	return world.Position
end
S.World.Points = function(_, key)
	return world.Points[key] or {}
end
local requestId = 0
local function request(rt, args)
	requestId += 1
	return S.Request(rt, player, args, "1:" .. requestId)
end

test("service: Arrive at a Lucky Pad is checked against the server position (radius + slack)", function()
	local rt = fakeRuntime(walk(10))
	local pad = Vector3.new(-104, 1.4, -59)
	world.Points.LuckyPad = { pad, Vector3.new(-116, 1.4, -59) }
	local reach = TC.Arrive.LuckyPad.Radius + TC.Arrive.LuckyPad.Slack
	world.Position = pad + Vector3.new(reach + 2, 2, 0)
	local ok, err = request(rt, { Action = "Arrive", Key = "LuckyPad" })
	eq(ok, false)
	truthy(string.find(tostring(err), "Lucky Pad", 1, true), tostring(err))
	eq(rt.Profile.Onboarding.Step, 10, "refused: nothing changed")
	eq(#blocksOf(rt.Profile, "Tutorial"), 0)
	-- no character (dead / respawning): refused
	world.Position = nil
	ok = request(rt, { Action = "Arrive", Key = "LuckyPad" })
	eq(ok, false)
	-- inside the slack (a lagged client): accepted
	world.Position = pad + Vector3.new(reach - 1, 0, 0)
	local result
	ok, result = request(rt, { Action = "Arrive", Key = "LuckyPad" })
	eq(ok, true, tostring(result))
	eq(result.Step, 11)
	truthy(result.FreeBlock and result.FreeBlock.Granted, "free block in the reply")
	eq(#blocksOf(rt.Profile, "Tutorial"), 1)
	eq(rt.Profile.Onboarding.Seen.LuckyPad, true)
end)

test("service: Arrive at the Mutation Lab, the saved anchors as fallback, bad requests", function()
	local rt = fakeRuntime(walk(11))
	world.Points.Lab = nil
	-- the real Points: no workspace in Lune -> the config fallback anchors
	local real = L.Require("ServerScriptService.Economy.OnboardingService")
	truthy(real == S)
	local Points = S.World.Points
	S.World.Points = function(p, key)
		if key == "Lab" then
			local list = {}
			for _, v in ipairs(TC.Arrive.Lab.Fallback) do
				table.insert(list, v)
			end
			return list
		end
		return Points(p, key)
	end
	world.Position = Vector3.new(66 - 40, 3, 477)
	local ok = request(rt, { Action = "Arrive", Key = "Lab" })
	eq(ok, false)
	eq(rt.Profile.Onboarding.Step, 11)
	world.Position = Vector3.new(66 - 20, 3, 477)
	local result
	ok, result = request(rt, { Action = "Arrive", Key = "Lab" })
	eq(ok, true, tostring(result))
	eq(result.Step, 12)
	S.World.Points = Points
	-- validation of the request shape
	local okCall, err = pcall(request, rt, { Action = "Teleport" })
	eq(okCall, false, "unknown action")
	okCall, err = pcall(S.Request, rt, player, { Action = "Arrive", Key = "Moon" }, "x")
	eq(okCall, false)
	truthy(string.find(tostring(err), "Invalid tutorial step", 1, true), tostring(err))
	okCall = pcall(S.Request, rt, player, { Action = "Seen", Key = string.rep("x", 40) }, "x")
	eq(okCall, false)
	okCall = pcall(S.Request, rt, player, { Action = "Next" }, "x")
	eq(okCall, false, "v3's NEXT is gone (no info cards any more)")
end)

test("service: CLAIM with no Lucky Pad found, SkipStep and Seen through the request path", function()
	local rt = fakeRuntime(walk(10))
	world.Points.LuckyPad = {}
	local ok, result = request(rt, { Action = "Claim" })
	eq(ok, true, tostring(result))
	eq(result.Step, 11)
	eq(#blocksOf(rt.Profile, "Tutorial"), 1)
	-- a step that runs too short cannot be skipped through the service either
	L.Time = rt.Profile.Onboarding.StepAt + 10
	ok, result = request(rt, { Action = "SkipStep" })
	eq(ok, false)
	truthy(string.find(tostring(result), "Keep trying", 1, true))
	ok, result = request(rt, { Action = "Arrive", Key = "Lab" })
	eq(ok, false)
	L.Time = NOW
end)

test("rules: the range check is a plain distance to any point", function()
	local points = { Vector3.new(0, 0, 0), Vector3.new(100, 0, 0) }
	eq(O.WithinAny(Vector3.new(5, 0, 0), points, 6), true)
	eq(O.WithinAny(Vector3.new(50, 0, 0), points, 6), false)
	eq(O.WithinAny(Vector3.new(97, 0, 0), points, 6), true)
	eq(O.WithinAny(nil, points, 6), false)
	eq(O.WithinAny(Vector3.new(0, 0, 0), {}, 6), false)
end)

test("View: what Runtime projects (TutorialStepAt, TutorialSkippable) and Rules integration", function()
	local p = walk(6)
	local view = O.View(p, p.Onboarding.StepAt + 5)
	eq(view.Version, 4)
	eq(view.Step, 6)
	eq(view.Id, "Upgrade")
	eq(view.Kind, "Milestone")
	eq(view.StepAt, p.Onboarding.StepAt)
	eq(view.Skippable, false)
	eq(O.View(p, p.Onboarding.StepAt + 121).Skippable, true)
	eq(view.ReadyAt, 0)
	-- the profile defaults are v4 and R.Validate keeps the record valid
	local q = fresh()
	q.Session = { Id = "s", Expires = NOW + 100 }
	R.Normalize(q, 1, NOW)
	R.Validate(q)
	eq(q.Onboarding.Version, 4)
	eq(type(q.Onboarding.Skipped), "table")
	-- the record stays small
	local size = #require("@lune/serde").encode("json", walk(14).Onboarding)
	truthy(size < 600, "onboarding record " .. size .. " bytes")
end)

------------------------------------------------------------------------------------------------------------------------
-- Localization
------------------------------------------------------------------------------------------------------------------------
local Dict = L.Require("ReplicatedStorage.Localization.Tutorial")
local function russian(ru, what)
	truthy(type(ru) == "string" and ru ~= "", "translation for " .. what)
	-- no untranslated English words left (DOGROTS / DOGDEX / UPGRADE TREE style proper names are allowed)
	local stripped = ru:gsub("DOGROTS", ""):gsub("DOG%-O%-MATIC", ""):gsub("%%[%ds%.]+", "")
	truthy(not string.find(stripped, "[A-Za-z][A-Za-z][A-Za-z]"), "Latin words in the translation of " .. what .. ": " .. ru)
end

test("every server message of the tutorial has a Russian Exact entry", function()
	local sources = fs.readFile("src/ServerScriptService/Economy/OnboardingRules.luau") .. fs.readFile("src/ServerScriptService/Economy/OnboardingService.luau")
	local found = 0
	for message in string.gmatch(sources, "assert%b()") do
		for text in string.gmatch(message, "'([^']+)'") do
			if text:find(" ") then
				found += 1
				russian(Dict.Exact[text], text)
			end
		end
	end
	for message in string.gmatch(sources, "R%.Check%b()") do
		for text in string.gmatch(message, "'([^']+)'") do
			if text:find(" ") then
				found += 1
				russian(Dict.Exact[text], text)
			end
		end
	end
	truthy(found >= 8, "found " .. found .. " messages")
end)

test("every string of the director has exactly one Russian entry and no Exact key repeats another dictionary", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/TutorialDirector.luau")
	local seen = 0
	for en in string.gmatch(source, 'T%("([^"]+)"%)') do
		seen += 1
		russian(Dict.UI[en] or Dict.Exact[en], en)
	end
	for en in string.gmatch(source, 'F%("([^"]+)"') do
		seen += 1
		local ru = Dict.Templates[en]
		russian(ru, en)
		local _, a = en:gsub("%%", "")
		local _, b = ru:gsub("%%", "")
		eq(a, b, "format arguments of " .. en)
	end
	truthy(seen >= 60, "director strings found: " .. seen)
	for en, ru in pairs(Dict.UI) do
		russian(ru, en)
	end
	-- Exact entries are merged into DOGROTS_AutoTranslateUI: none may override the base dictionary or another module
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	local base = {}
	for en in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"') do
		base[en] = true
	end
	for en, ru in pairs(Dict.Exact) do
		truthy(not base[en], "Exact repeats a base dictionary entry: " .. en)
		russian(ru, en)
	end
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		if name ~= "Tutorial.luau" then
			local other = L.Require("ReplicatedStorage.Localization." .. name:gsub("%.luau$", ""))
			for en in pairs(type(other) == "table" and other.Exact or {}) do
				truthy(Dict.Exact[en] == nil, "Exact key also in Localization/" .. name .. ": " .. en)
			end
		end
	end
end)

test("the director never sinks input: no Modal, its own layer between the HUD and kit windows", function()
	local source = fs.readFile("src/StarterGui/ScreenGui/Modules/TutorialDirector.luau")
	truthy(not source:find("Modal%s*=%s*true"), "Modal = true")
	truthy(not source:find("MouseButton1Click"), "MouseButton1Click instead of Activated")
	truthy(source:find("DisplayOrder = 55", 1, true), "DisplayOrder 55")
	truthy(source:find("pcall", 1, true), "render in pcall")
	local shim = fs.readFile("src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau")
	truthy(shim:find("function Guide.Replay", 1, true) and shim:find("function Guide.Start", 1, true), "OnboardingGuide keeps Start / Replay")
end)

------------------------------------------------------------------------------------------------------------------------
-- The client director, headless (tests/lib/client_env.luau runs the real Kit + Modules.TutorialDirector)
------------------------------------------------------------------------------------------------------------------------
local CE = require("./lib/client_env")
local CV3 = roblox.Vector3
local RSFake = CE.MountReplicated()
local remote = CE.Instance.new("RemoteFunction")
remote.Name = "DogEconomyRequest"
remote.Parent = RSFake
-- the world the steps point at (positions of the real place)
local district = CE.Model("DOGROTS_District", CE.Workspace)
local line = CE.Model("03_DogLine", district)
CE.Part("EntranceAnchor", CV3.new(0, 2, -140), CV3.new(1, 1, 1), line)
local tongue = CE.Model("Tongue", line)
CE.Part("Belt", CV3.new(0, 1, -60), CV3.new(14, 1, 150), tongue)
local activeDogs = CE.Folder("ActiveDogs", line)
local function lineDog(name, z, price)
	local dog = CE.Model(name, activeDogs)
	dog.PrimaryPart = CE.Part("RootPart", CV3.new(0, 3, z), CV3.new(3, 3, 5), dog)
	dog:SetAttribute("DogId", name)
	dog:SetAttribute("CurrentPrice", price)
	dog:SetAttribute("OwnerUserId", 0)
	dog:SetAttribute("State", "OnLine")
	return dog
end
local cheapDog = lineDog("Breadog", -100, 3500)
lineDog("Golddog", -110, 9000000)
local yards = CE.Model("04_PlayerYards", district)
local yard = CE.Model("Yard_02", yards)
yard:SetAttribute("OwnerUserId", 1)
yard:SetAttribute("YardId", 2)
local slot1 = CE.Model("DigSlot_1", yard)
slot1:SetAttribute("Unlocked", true)
CE.Part("DarkExcavation", CV3.new(-81, 0.2, -26), CV3.new(12, 0.4, 12), slot1)
local vendor = CE.Model("Vendor", yard)
CE.Part("Stall", CV3.new(-155, 4, -15), CV3.new(6, 8, 6), vendor)
CE.Part("SellAnchor", CV3.new(-153.9, 4.7, -15), CV3.new(1, 1, 1), yard)
local pads = {}
for i, x in ipairs({ -104, -116, -128 }) do
	pads[i] = CE.Part("LuckyPad_" .. i, CV3.new(x, 1.4, -59), CV3.new(8, 0.3, 8), yard)
end
local corner = CE.Model("MiningCorner", yard)
CE.Part("MiningPickaxeShop", CV3.new(-90, 3, -60), CV3.new(6, 6, 4), corner)
CE.Part("MiningOreCore", CV3.new(-95, 3, -75), CV3.new(6, 6, 6), corner)
local labModel = CE.Model("05_MutationLab", district)
CE.Part("EntranceAnchor", CV3.new(66, 3, 477), CV3.new(1, 1, 1), labModel)
CE.Part("InteractionAnchor", CV3.new(77, 3.9, 477), CV3.new(1, 1, 1), labModel)
local console = CE.Model("Console", CE.Model("NuclearCompound", labModel))
CE.Part("Desk", CV3.new(80, 3, 477), CV3.new(4, 3, 6), console)
-- the local player as Runtime projects it
local P = CE.Player
local stats = CE.Folder("leaderstats", P)
local coinsValue = CE.Instance.new("IntValue")
coinsValue.Name = "Coins"
coinsValue.Value = 4200
coinsValue.Parent = stats
local inventory = CE.Folder("DogInventory", P)
for k, v in pairs({ EconomyReady = true, TutorialVersion = 4, TutorialActive = true, TutorialStatus = "Active", TutorialStep = 0,
	TutorialStepAt = CE.Unix, TutorialSkippable = false, YardId = 2, Level = 1, ItemCount = 0, MiningPickaxeOwned = 0, MiningLayer = 1 }) do
	P:SetAttribute(k, v)
end
local function setStep(n)
	P:SetAttribute("TutorialStepAt", math.floor(CE.Unix))
	P:SetAttribute("TutorialSkippable", false)
	P:SetAttribute("TutorialStep", n)
end
CE.Spawn(CV3.new(0, 3, -125))
-- fakes for SHOW THE WAY, the HUD rail and GUIIntegration's navigation
local pathShows = {}
local pathActive = nil
CE.Overrides["ReplicatedStorage/Navigation/PathGuide"] = {
	Show = function(key)
		table.insert(pathShows, key)
		pathActive = { Key = key }
		return true
	end,
	Clear = function()
		pathActive = nil
	end,
	Active = function()
		return pathActive
	end,
}
local mainGui = CE.MainGui()
local tiles = {}
for i, key in ipairs({ "Dogs", "Inventory", "Yard", "DogDex", "Trade" }) do
	local root = CE.Instance.new("Frame")
	root.Name = key .. "Tile"
	root.Position = roblox.UDim2.fromOffset(12, 120 + i * 70)
	root.Size = roblox.UDim2.fromOffset(62, 62)
	root.Parent = mainGui.HUD
	table.insert(tiles, { key = key, root = root })
end
CE.Overrides["Modules/UITheme"] = { QuickTiles = tiles }
local opened = {}
local nav = {
	OpenPage = function(page)
		table.insert(opened, page)
	end,
	OpenScreen = function(page)
		table.insert(opened, page)
	end,
	Close = function()
		table.insert(opened, "Close")
	end,
}
-- the server: records every Tutorial request and answers like OnboardingService (a handler can override)
local calls = {}
local serverHandler = nil
CE.OnInvoke = function(_, action, payload, id)
	eq(action, "Tutorial")
	table.insert(calls, { Action = payload.Action, Key = payload.Key, Id = id })
	if serverHandler then
		return serverHandler(payload, id)
	end
	return true, { Step = P:GetAttribute("TutorialStep") }
end
local function lastCall()
	return calls[#calls]
end
local Director = CE.Require(mainGui.Modules.TutorialDirector)
local controller = Director.Start(mainGui, nav)
local function layer()
	return CE.PlayerGui:FindFirstChild("DOGROTS_Tutorial")
end
local function card()
	local l = layer()
	return l and l:FindFirstChild("TutorialCard")
end
local function caption(button)
	return button.Content.Caption.Text
end
-- seconds shown by a "SKIP IN m:ss" / "CLAIM IN m:ss" caption (nil when it is not a countdown)
local function countdown(text, word)
	local m, sec = string.match(text, "^" .. word .. " IN (%d+):(%d%d)$")
	return m and tonumber(m) * 60 + tonumber(sec) or nil
end
local function near(value, lo, hi, what)
	truthy(value and value >= lo and value <= hi, what .. ": " .. tostring(value) .. " not in " .. lo .. ".." .. hi)
end
local function worldFolder()
	return CE.Workspace:FindFirstChild("DOGROTS_TutorialWorld")
end
local function marker()
	local folder = worldFolder()
	local anchor = folder and folder:FindFirstChild("TutorialMarker")
	return anchor and anchor:FindFirstChild("Marker")
end
local function highlight()
	local folder = worldFolder()
	return folder and folder:FindFirstChild("TutorialHighlight")
end
local function noErrors(where)
	for _, e in ipairs(CE.Errors) do
		error(where .. ": runtime error " .. e, 2)
	end
	for _, w in ipairs(CE.Warnings) do
		if w:find("tutorial", 1, true) then
			error(where .. ": warning " .. w, 2)
		end
	end
end

test("director: the welcome card shows after EconomyReady, in its own layer, START starts", function()
	eq(Director.Running(), true)
	CE.Advance(0.5)
	truthy(not card().Visible, "the card waits for the arrival camera (ShowAfter)")
	CE.Advance(2.5)
	local l, c = layer(), card()
	eq(l.DisplayOrder, 55)
	eq(l.ResetOnSpawn, false)
	eq(l:GetAttribute("HideWithUI"), true)
	truthy(CE.Shown(c), "card on screen")
	eq(c.Title.Text, "WELCOME TO DOGROTS")
	eq(caption(c.Primary), "START")
	eq(caption(c.Secondary), "SKIP TUTORIAL")
	-- nothing in the layer sinks input except the card and its buttons; nothing is Modal
	for _, d in ipairs(l:GetDescendants()) do
		truthy(d.Modal ~= true, "Modal on " .. d.Name)
		if d:IsA("GuiObject") and d.Active and not d:IsA("GuiButton") then
			eq(d, c, "only the card takes input: " .. d:GetFullName())
		end
	end
	-- leaving the whole tutorial needs a hold, a tap does nothing
	local before = #calls
	eq(c.Hint.Text, "Already know the game? Hold SKIP TUTORIAL.")
	CE.Click(c.Secondary)
	eq(#calls, before, "a tap on SKIP TUTORIAL does not leave")
	c.Secondary.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown })
	CE.Advance(0.2)
	eq(lastCall().Action, "Skip", "holding it does")
	CE.Click(c.Primary)
	eq(lastCall().Action, "Start")
	eq(#lastCall().Id, 32, "a 32-hex request id")
	setStep(1)
	CE.Advance(0.6)
	noErrors("welcome")
end)

test("director: a world step points at an affordable dog, draws the way, focuses the camera and restores it", function()
	local c = card()
	eq(c.Title.Text, "BUY YOUR FIRST DOG")
	eq(caption(c.Primary), "SHOW ME")
	local m = marker()
	truthy(m, "world marker")
	eq(m.Label.Text, "BUY THIS DOG")
	eq(m.Adornee, cheapDog.PrimaryPart, "the marker rides on the affordable dog, not the 9M one")
	eq(highlight().Adornee, cheapDog)
	eq(pathShows[#pathShows], "DogLine")
	-- the 2.2 s focus (own camera path: no Cinema module in this place)
	CE.Advance(0.3)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Scriptable, "focus running")
	truthy(CE.Bound.DOGROTS_TutorialFocus, "bound to the camera render step")
	eq(c.Hint.Text, "Tap anywhere to skip")
	CE.Advance(2.5)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "camera restored")
	eq(CE.Bound.DOGROTS_TutorialFocus, nil, "render step unbound")
	-- SHOW ME replays it; a tap skips it at once
	CE.Click(c.Primary)
	CE.Advance(0.1)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Scriptable)
	CE.Tap()
	CE.Advance(0.05)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "skipped by a tap")
	-- dying mid-focus never strands the camera
	CE.Click(c.Primary)
	CE.Advance(0.1)
	CE.Spawn(CV3.new(0, 3, -125))
	CE.Advance(0.1)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "restored on CharacterRemoving")
	-- the dog gets bought: the marker moves on (no affordable dog left -> THE DOG's tongue)
	cheapDog:SetAttribute("OwnerUserId", 99)
	CE.Advance(4.5)
	eq(marker().Label.Text, "THE DOG")
	noErrors("buy dog")
end)

test("director: menu steps open their menu, ring the HUD tile and report Seen when the menu is open", function()
	setStep(4)
	CE.Advance(0.6)
	local c = card()
	eq(c.Title.Text, "COLLECT YOUR LOOT")
	eq(caption(c.Primary), "OPEN MY BAG")
	eq(marker(), nil, "a menu step has no world marker")
	eq(pathActive, nil, "the previous step's route was cleared")
	local ring = layer().TileRing
	truthy(ring.Visible, "the BAG tile is ringed")
	eq(ring.Position.X.Offset, 12 - 5)
	CE.Click(c.Primary)
	eq(opened[#opened], "Inventory")
	local before = #calls
	mainGui:SetAttribute("OpenMenu", "Inventory")
	CE.Advance(0.6)
	truthy(not c.Visible, "the card hides behind the menu")
	eq(#calls, before + 1)
	eq(lastCall().Action, "Seen")
	eq(lastCall().Key, "Inventory")
	mainGui:SetAttribute("OpenMenu", nil)
	setStep(7)
	CE.Advance(0.6)
	eq(c.Title.Text, "DIG DEEPER: LAYERS")
	eq(c.Info.Text, "Next: CAVERNS · Level 5 · 16K Coins", "the next layer and its requirement")
	CE.Click(c.Primary)
	eq(opened[#opened], "Layers")
	mainGui:SetAttribute("OpenMenu", "Layers")
	CE.Advance(0.6)
	eq(lastCall().Key, "Layers")
	mainGui:SetAttribute("OpenMenu", nil)
	noErrors("menu steps")
end)

test("director: SKIP THIS STEP unlocks after 120 s with a countdown", function()
	setStep(5)
	CE.Advance(0.6)
	local c = card()
	eq(c.Title.Text, "SELL A FIND")
	near(countdown(caption(c.Secondary), "SKIP"), 118, 120, "countdown at the start")
	eq(c.Secondary.Active, false, "disabled while counting down")
	local before = #calls
	CE.Click(c.Secondary)
	eq(#calls, before, "a disabled button sends nothing")
	CE.Advance(60)
	near(countdown(caption(c.Secondary), "SKIP"), 58, 61, "countdown after a minute")
	CE.Advance(61)
	eq(caption(c.Secondary), "SKIP THIS STEP")
	eq(c.Secondary.Active, true)
	CE.Click(c.Secondary)
	eq(lastCall().Action, "SkipStep")
	noErrors("skip step")
end)

test("director: a lost request times out after 8 s; RETRY resends the same id; server errors are shown", function()
	setStep(14)
	CE.Advance(0.6)
	local c = card()
	eq(c.Title.Text, "YOU KNOW THE LOOP!")
	eq(caption(c.Primary), "FINISH")
	serverHandler = function()
		CE.task.wait(30) -- never answers in time
		return true, {}
	end
	CE.Click(c.Primary)
	local first = lastCall()
	eq(first.Action, "Finish")
	CE.Advance(1)
	eq(c.Primary.Active, false, "busy while waiting")
	CE.Advance(7.5)
	eq(c.Error.Text, "No answer from the server. Tap RETRY.")
	eq(caption(c.Primary), "RETRY")
	eq(c.Primary.Active, true, "buttons come back")
	serverHandler = function()
		return false, "Finish the tutorial tasks first"
	end
	CE.Click(c.Primary)
	eq(lastCall().Action, "Finish")
	eq(lastCall().Id, first.Id, "RETRY reuses the request id (the server receipt makes it idempotent)")
	CE.Advance(0.2)
	eq(c.Error.Text, "Finish the tutorial tasks first")
	eq(caption(c.Primary), "FINISH", "a server refusal is an answer, not a lost request: no RETRY")
	serverHandler = nil
	CE.Click(c.Primary)
	CE.Advance(0.2)
	eq(c.Error.Text, "")
	-- the slow first reply arriving late changes nothing
	CE.Advance(30)
	eq(c.Error.Text, "")
	noErrors("timeout")
end)

test("director: Arrive is reported in range; the free block reply shows a toast", function()
	setStep(10)
	CE.Advance(0.6)
	local c = card()
	eq(c.Title.Text, "LUCKY BLOCKS")
	eq(marker().Label.Text, "LUCKY PAD · FREE BLOCK")
	near(countdown(caption(c.Secondary), "CLAIM"), 118, 120, "claim countdown")
	local before = #calls
	CE.Advance(4)
	eq(#calls, before, "far away: nothing reported")
	truthy(c.Objective.Progress.Text.Text:find("m TO GO", 1, true), "distance left")
	serverHandler = function(payload)
		if payload.Action == "Arrive" then
			return true, { Step = 11, FreeBlock = { Granted = true, Tier = "Common" } }
		end
		return true, {}
	end
	CE.MoveTo(pads[1].Position + CV3.new(4, 3, 0))
	CE.Advance(0.6)
	eq(lastCall().Action, "Arrive")
	eq(lastCall().Key, "LuckyPad")
	serverHandler = nil
	-- no yard (no pads): CLAIM FREE BLOCK is offered at once
	local savedYard = P:GetAttribute("YardId")
	P:SetAttribute("YardId", 7)
	setStep(11)
	CE.Advance(0.6)
	setStep(10)
	CE.Advance(4)
	eq(caption(c.Secondary), "CLAIM FREE BLOCK")
	CE.Click(c.Secondary)
	eq(lastCall().Action, "Claim")
	P:SetAttribute("YardId", savedYard)
	setStep(11)
	CE.Advance(0.6)
	eq(c.Title.Text, "THE MUTATION LAB")
	eq(highlight().Adornee, console, "the START MUTATION console is outlined")
	noErrors("arrive")
end)

test("director: hidden while blocked, collapsible, rebuilt when destroyed, Russian text", function()
	local c = card()
	mainGui:SetAttribute("MiningActive", true)
	CE.Advance(0.6)
	truthy(not c.Visible, "hidden during a mining session")
	eq(marker().Enabled, false, "world marker hidden too")
	mainGui:SetAttribute("MiningActive", nil)
	mainGui:SetAttribute("UIHidden", true)
	CE.Advance(0.6)
	truthy(not c.Visible, "hidden with HIDE UI")
	mainGui:SetAttribute("UIHidden", nil)
	CE.Advance(0.6)
	truthy(c.Visible)
	local fullHeight = c.Size.Y.Offset
	CE.Click(c.Collapse)
	CE.Advance(0.6)
	truthy(c.Size.Y.Offset < fullHeight * 0.5, "collapsed to a strip")
	truthy(not c.Body.Visible)
	CE.Click(c.Collapse)
	CE.Advance(0.6)
	eq(c.Size.Y.Offset, fullHeight)
	-- something destroys the layer: it comes back
	layer():Destroy()
	CE.Advance(0.6)
	truthy(layer() and card(), "layer rebuilt")
	truthy(card().Visible, "and shown again")
	-- Russian
	local Lang = CE.Require(mainGui.Modules.Kit.Lang)
	Lang.Override = "ru"
	CE.Advance(0.6)
	eq(card().Title.Text, "ЛАБОРАТОРИЯ МУТАЦИЙ")
	eq(caption(card().Primary), "ПОКАЖИ")
	Lang.Override = nil
	CE.Advance(0.6)
	noErrors("blocked / rebuilt")
end)

test("director: HOW TO PLAY replays every card client-only; the end of the tutorial clears the world", function()
	P:SetAttribute("TutorialActive", false)
	P:SetAttribute("TutorialStatus", "Complete")
	CE.Advance(0.6)
	truthy(not card().Visible, "no card once the tutorial is over")
	eq(marker(), nil, "world cleared")
	eq(highlight(), nil)
	local before = #calls
	Director.Replay()
	CE.Advance(0.6)
	local c = card()
	truthy(c.Visible)
	eq(c.Kicker.Text, "HOW TO PLAY · 1 / 15")
	eq(caption(c.Primary), "NEXT")
	eq(caption(c.Secondary), "CLOSE")
	for i = 2, 15 do
		CE.Click(c.Primary)
		CE.Advance(0.4)
		eq(c.Kicker.Text, string.format("HOW TO PLAY · %d / 15", i))
	end
	eq(caption(c.Primary), "DONE")
	CE.Click(c.Secondary)
	CE.Advance(0.4)
	eq(c.Kicker.Text, "HOW TO PLAY · 14 / 15", "BACK")
	CE.Advance(3)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom)
	CE.Click(c.Primary)
	CE.Advance(0.2)
	CE.Click(c.Primary)
	CE.Advance(0.4)
	truthy(not c.Visible, "DONE closes the replay")
	eq(#calls, before, "a replay never talks to the server")
	eq(marker(), nil)
	noErrors("replay")
end)

test("director: stops with the main ScreenGui and can start again", function()
	local folder = worldFolder()
	mainGui:Destroy()
	CE.Advance(0.6)
	eq(Director.Running(), false)
	eq(layer(), nil, "its layer is gone")
	truthy(not folder.Parent, "its world folder is gone")
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom)
	local again = CE.MainGui()
	local Director2 = CE.Require(again.Modules.TutorialDirector)
	P:SetAttribute("TutorialActive", true)
	setStep(2)
	Director2.Start(again, nav)
	CE.Advance(3)
	truthy(card() and card().Visible, "a new director runs")
	eq(card().Title.Text, "PUT YOUR DOG TO WORK")
	noErrors("restart")
end)

test("director: the focus goes through HalloweenClient.Cinema when it exists (and respects a refusal)", function()
	local hc = CE.Instance.new("LocalScript")
	hc.Name = "HalloweenClient"
	hc.Parent = CE.Player.PlayerScripts
	local module = CE.Instance.new("ModuleScript")
	module.Name = "Cinema"
	module.Parent = hc
	local plays = {}
	local refuse = false
	CE.Overrides["HalloweenClient/Cinema"] = {
		Play = function(opts)
			table.insert(plays, opts)
			if refuse then
				opts.OnDone(false)
				return nil
			end
			return { Cancel = function() end }
		end,
	}
	setStep(5)
	CE.Advance(0.6)
	local c = card()
	eq(c.Title.Text, "SELL A FIND")
	local before = #plays
	CE.Click(c.Primary) -- SHOW ME
	CE.Advance(0.2)
	truthy(#plays > before, "Cinema.Play was used")
	local opts = plays[#plays]
	eq(opts.Duration, TC.FocusSeconds)
	eq(opts.LockControls, true)
	eq(opts.Letterbox, false, "no letterbox over the card")
	eq(opts.HideUI, false)
	eq(opts.Skippable, true)
	eq(opts.Duck, false, "no music duck for a 2 s look")
	truthy(opts.BlendIn > 0 and opts.BlendOut > 0 and opts.BlendIn + opts.BlendOut < opts.Duration, "Cinema blends in and out")
	local shot = opts.Shot(1.1)
	eq(typeof(shot), "CFrame")
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom, "Cinema owns the camera, not the director")
	eq(c.Hint.Text, "Tap anywhere to skip")
	opts.OnDone(true)
	CE.Advance(0.6)
	truthy(c.Hint.Text ~= "Tap anywhere to skip", "focus over")
	-- refused (another cinematic): no own fallback camera either
	refuse = true
	CE.Click(c.Primary)
	CE.Advance(0.2)
	eq(CE.Camera.CameraType, roblox.Enum.CameraType.Custom)
	eq(CE.Bound.DOGROTS_TutorialFocus, nil)
	hc:Destroy()
	noErrors("cinema")
end)

test("director: the card fits phone portrait, phone landscape and desktop screens", function()
	local function check(size, touch, what)
		CE.Screen = size
		CE.UserInputService.TouchEnabled = touch
		layer():SetAttribute("Resize", (layer():GetAttribute("Resize") or 0) + 1)
		CE.Advance(0.6)
		local c = card()
		local w, h = c.Size.X.Offset, c.Size.Y.Offset
		local bottom = c.Position.Y.Offset
		truthy(w <= size.X - 20, what .. ": width " .. w)
		truthy(bottom - h >= 0 and bottom <= size.Y, what .. ": vertical fit " .. (bottom - h) .. ".." .. bottom)
		truthy(c.Primary.Size.Y.Offset >= 40, what .. ": touch-sized buttons")
		return c
	end
	check(roblox.Vector2.new(1280, 720), false, "desktop")
	local portrait = check(roblox.Vector2.new(390, 844), true, "phone portrait")
	eq(portrait.Size.X.Offset, 390 - 24)
	truthy(portrait.Position.Y.Offset <= 844 - 235 + 1, "clear of the thumbstick and jump button")
	local landscape = check(roblox.Vector2.new(844, 390), true, "phone landscape")
	truthy(landscape.Size.Y.Offset <= 390 * 0.62, "a low card in landscape: " .. landscape.Size.Y.Offset)
	truthy(landscape.Primary.Position.X.Offset > landscape.Size.X.Offset / 2, "buttons in the right column")
	CE.Screen = roblox.Vector2.new(1280, 720)
	CE.UserInputService.TouchEnabled = false
	CE.Advance(0.6)
	noErrors("layout")
end)

print(string.format("tutorial: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tutorial tests failed")
end
