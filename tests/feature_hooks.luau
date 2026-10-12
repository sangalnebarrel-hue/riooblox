--!nocheck
--!nolint
-- FeatureRegistry hooks (Actions, Cost, Gate, Request, Reply/Patch, Project) through the REAL
-- Runtime.Request and Runtime.Project, and the action-name collision rules:
--   lune run tests/feature_hooks.luau
-- Probe features are injected with Registry.Add into a fresh tests/lib/server_world (memory store).
local fs = require("@lune/fs")
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
local function read(path)
	for _, prefix in { "", "../" } do
		local ok, text = pcall(fs.readFile, prefix .. path)
		if ok then
			return text
		end
	end
	error("cannot read " .. path)
end
local function warned(W, needle)
	for _, line in W.L.Warnings do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- ===== A world with two probe features =====
local function probeWorld()
	local W = World.new()
	local log = { Actions = {}, Gates = {}, Requests = {}, Projects = {}, Patches = {} }
	local R = W.Rules
	local engine
	engine = {
		Name = "HookProbe",
		Order = 900,
		Actions = { ProbeSnapshot = true, ProbePatch = true, ProbeNone = true, ProbeGate = true, ProbePricey = true, ProbeBrokenPatch = true },
		Reply = { ProbePatch = "Patch", ProbeNone = "None", ProbeBrokenPatch = "Patch" },
		Cost = function(action)
			return action == "ProbePricey" and 4 or 1
		end,
		Normalize = function(_, p)
			if type(p.HookProbe) ~= "table" then
				p.HookProbe = { Version = 1, Count = 0 }
			end
		end,
		Validate = function(Rules, p)
			if p.HookProbe ~= nil then
				Rules.Check(type(p.HookProbe) == "table" and Rules.Int(p.HookProbe.Count, 0, 1e6), "Invalid probe")
			end
		end,
		Action = function(Rules, p, action, a)
			if not engine.Actions[action] then
				return nil
			end
			table.insert(log.Actions, action)
			Rules.Check(not a.Fail, "Probe refused")
			p.HookProbe.Count += 1
			return "Probe " .. action, { Count = p.HookProbe.Count }
		end,
		Gate = function(player, action, a, runtime)
			table.insert(log.Gates, { Player = player, Action = action, Runtime = runtime })
			if a.Far then
				return "Stand at the probe"
			end
			if a.Boom then
				R.Check(false, "Gate exploded")
			end
			return nil
		end,
		Patch = function(player, action, result, p)
			if action == "ProbeBrokenPatch" then
				error("patch bug")
			end
			table.insert(log.Patches, { Player = player, Action = action, Result = result, Profile = p })
			return { Count = p.HookProbe.Count }
		end,
		Project = function(player, p, runtime)
			table.insert(log.Projects, { Player = player, Profile = p, Runtime = runtime })
			player:SetAttribute("ProbeCount", p.HookProbe and p.HookProbe.Count or -1)
		end,
	}
	-- Order 899: its broken Project runs before HookProbe's, which must still run.
	local custom = {
		Name = "HookCustom",
		Order = 899,
		Actions = { ProbeCustom = true },
		Request = function(player, action, a, receiptId, runtime)
			table.insert(log.Requests, { Player = player, Action = action, Args = a, Receipt = receiptId, Runtime = runtime })
			if a.Fail then
				return false, "Custom refused"
			end
			return true, { Message = "Custom done", Echo = a.Value }
		end,
		Project = function()
			error("project bug")
		end,
	}
	-- Answers an action through Rules.Action without declaring it (the pre-hook style).
	local undeclared = {
		Name = "HookUndeclared",
		Order = 902,
		Action = function(_, p, action)
			if action ~= "ProbeOldStyle" then
				return nil
			end
			p.HookProbe.Count += 10
			return "Old style"
		end,
	}
	W.Registry.Add(engine)
	W.Registry.Add(custom)
	W.Registry.Add(undeclared)
	return W, log, engine, custom
end

local W, log, engine, custom = probeWorld()
-- Every test uses its own player: each has its own 8-token request bucket.
local player = W.Join(1)

test("Owner, Cost and Reply read the declared hooks", function()
	local Registry = W.Registry
	eq(Registry.Owner("ProbePatch"), engine)
	eq(Registry.Owner("ProbeCustom"), custom)
	eq(Registry.Owner("ProbeOldStyle"), nil, "undeclared actions have no owner")
	eq(Registry.Owner("Nope"), nil)
	eq(Registry.Owner(5), nil)
	eq(Registry.Cost("ProbePricey"), 4)
	eq(Registry.Cost("ProbePatch"), 1)
	eq(Registry.Cost("ProbeCustom"), 1, "no Cost hook: 1 token")
	eq(Registry.Cost("Nope"), 1)
	eq(Registry.Cost("SettingsSave"), 0.5)
	eq(Registry.Reply("ProbePatch"), "Patch")
	eq(Registry.Reply("ProbeNone"), "None")
	eq(Registry.Reply("ProbeSnapshot"), "Snapshot", "missing from the Reply table")
	eq(Registry.Reply("ProbeCustom"), "Snapshot", "no Reply field")
	eq(Registry.Reply("SettingsSave"), "Patch")
end)

test("a feature action runs Engine:Action -> Rules.Action with the full snapshot by default", function()
	local ok, result = W.Request(player, "ProbeSnapshot", {})
	truthy(ok, tostring(result))
	eq(result.Message, "Probe ProbeSnapshot")
	eq(result.Count, 1, "extra fields are merged")
	truthy(type(result.StateSnapshot) == "table" and type(result.StateSnapshot.Profile) == "table", "full snapshot")
	eq(result.StatePatch, nil)
	eq(W.Profile(1).HookProbe.Count, 1, "saved in the profile")
	local gate = log.Gates[#log.Gates]
	eq(gate.Player, player)
	eq(gate.Action, "ProbeSnapshot")
	eq(gate.Runtime, W.Runtime)
end)

test("Reply='Patch' ships the patch only, Reply='None' ships nothing", function()
	local player = W.Join(11)
	local ok, result = W.Request(player, "ProbePatch", {})
	truthy(ok, tostring(result))
	eq(result.StateSnapshot, nil)
	eq(type(result.StatePatch), "table")
	eq(result.StatePatch.Count, 1)
	local call = log.Patches[#log.Patches]
	eq(call.Player, player)
	eq(call.Action, "ProbePatch")
	eq(call.Result, result)
	eq(call.Profile, W.Runtime.Views[11], "Patch sees the refreshed view")
	eq(call.Profile.HookProbe.Count, 1)
	ok, result = W.Request(player, "ProbeNone", {})
	truthy(ok, tostring(result))
	eq(result.Message, "Probe ProbeNone")
	eq(result.StateSnapshot, nil)
	eq(result.StatePatch, nil)
	eq(W.Runtime.Views[11].HookProbe.Count, 2, "the view is refreshed even without a reply")
end)

test("a failing Patch falls back to a full snapshot, with one warning", function()
	local player = W.Join(12)
	local ok, result = W.Request(player, "ProbeBrokenPatch", {})
	truthy(ok, tostring(result))
	eq(result.StatePatch, nil)
	truthy(type(result.StateSnapshot) == "table", "fallback snapshot")
	truthy(warned(W, "HookProbe.Patch"), "warned")
end)

test("a refused feature action replies the refusal and projects nothing", function()
	local player = W.Join(13)
	local projects = #log.Projects
	local ok, result = W.Request(player, "ProbeSnapshot", { Fail = true })
	eq(ok, false)
	truthy(tostring(result):find("Probe refused", 1, true), tostring(result))
	eq(#log.Projects, projects, "no refresh after a refusal")
end)

test("Gate refusals stop the request before the transaction", function()
	local player = W.Join(14)
	local actions, count = #log.Actions, W.Profile(14).HookProbe.Count
	local ok, result = W.Request(player, "ProbeGate", { Far = true })
	eq(ok, false)
	eq(result, "Stand at the probe")
	ok, result = W.Request(player, "ProbeGate", { Boom = true })
	eq(ok, false)
	eq(result, "Gate exploded")
	eq(#log.Actions, actions, "Action never ran")
	eq(W.Profile(14).HookProbe.Count, count)
	ok, result = W.Request(player, "ProbeGate", {})
	truthy(ok, tostring(result))
	eq(W.Profile(14).HookProbe.Count, count + 1, "an open gate lets the transaction run")
end)

test("Cost spends the shared token bucket", function()
	local spender = W.Join(2)
	truthy(W.Request(spender, "ProbePricey", {}))
	truthy(W.Request(spender, "ProbePricey", {}))
	local ok, result = W.Request(spender, "ProbePricey", {})
	eq(ok, false)
	eq(result, "Please wait a moment")
end)

test("a Request hook takes over after the common validation", function()
	local player = W.Join(15)
	local before = #log.Actions
	local ok, result = W.Request(player, "ProbeCustom", { Value = 7 })
	truthy(ok, tostring(result))
	eq(result.Echo, 7)
	truthy(type(result.StateSnapshot) == "table", "default Reply")
	local call = log.Requests[#log.Requests]
	eq(call.Player, player)
	eq(call.Action, "ProbeCustom")
	eq(call.Args.Value, 7)
	eq(call.Runtime, W.Runtime)
	truthy(type(call.Receipt) == "string" and call.Receipt:match("^15:%x+$") and #call.Receipt == 29, "receipt id " .. tostring(call.Receipt))
	eq(#log.Actions, before, "Engine:Action is not used")
	ok, result = W.Request(player, "ProbeCustom", { Fail = true })
	eq(ok, false)
	eq(result, "Custom refused")
	-- Common validation first: the hook never sees these.
	local requests = #log.Requests
	ok, result = W.Runtime.Request(player, "ProbeCustom", {}, "not-hex")
	eq(ok, false)
	eq(result, "Invalid request ID")
	ok, result = W.Request(player, "ProbeCustom", { Value = string.rep("x", 121) })
	eq(ok, false)
	eq(result, "Invalid request")
	local stranger = W.AddPlayer(3)
	ok, result = W.Request(stranger, "ProbeCustom", {})
	eq(ok, false)
	eq(result, "Your saved profile is still loading")
	eq(#log.Requests, requests)
end)

test("Project hooks run at the end of every Runtime.Project, each in its own pcall", function()
	local projects = #log.Projects
	W.Runtime.Refresh(player)
	eq(#log.Projects, projects + 1)
	local call = log.Projects[#log.Projects]
	eq(call.Player, player)
	eq(call.Runtime, W.Runtime)
	eq(player:GetAttribute("ProbeCount"), W.Profile(1).HookProbe.Count, "published")
	truthy(warned(W, "HookCustom.Project"), "the broken hook warned")
	eq(player:GetAttribute("EconomyReady"), true, "the rest of Project ran")
	-- One warning per 30 s, however often it fails.
	local count = 0
	for _, line in W.L.Warnings do
		if line:find("HookCustom.Project", 1, true) then
			count += 1
		end
	end
	eq(count, 1, "warnings are throttled")
end)

test("features without hooks behave as before", function()
	local player = W.Join(16)
	-- An undeclared action still reaches Registry.Action through the legacy Engine:Action path.
	local before = W.Profile(16).HookProbe.Count
	local ok, result = W.Request(player, "ProbeOldStyle", {})
	truthy(ok, tostring(result))
	eq(result.Message, "Old style")
	truthy(type(result.StateSnapshot) == "table", "legacy snapshot reply")
	eq(W.Profile(16).HookProbe.Count, before + 10)
	-- A real feature without Gate/Request/Reply hooks.
	ok, result = W.Request(player, "TreeUpgrade", { Node = "Dig" })
	eq(ok, false)
	truthy(tostring(result):find("level", 1, true), tostring(result))
end)

test("Registry.Add keeps the first owner of a claimed action", function()
	local collisions = #W.Registry.Collisions
	W.Registry.Add({ Name = "Clash", Actions = { ProbePatch = true } })
	eq(W.Registry.Owner("ProbePatch"), engine)
	eq(#W.Registry.Collisions, collisions + 1)
	local row = W.Registry.Collisions[#W.Registry.Collisions]
	eq(row.Action, "ProbePatch")
	eq(row.Owner, "HookProbe")
	eq(row.Feature, "Clash")
	truthy(warned(W, "Clash also claims ProbePatch"), "warned")
end)

-- ===== Collision rules on the real features =====
local clean = World.new()
local Registry, R = clean.Registry, clean.Rules

-- Every action name the legacy paths answer: Runtime.Request, Rules.Action, PlotRules.Action and
-- ItemRules' I.Action (read from the sources, so a new legacy branch is covered at once).
local function body(source, header)
	local start = source:find(header, 1, true)
	assert(start, "missing " .. header)
	local stop = source:find("\nend\n", start, true)
	return source:sub(start, stop)
end
local LEGACY = {}
for _, part in {
	body(read("src/ServerScriptService/Economy/Runtime.luau"), "function Runtime.Request("),
	body(read("src/ServerScriptService/Economy/Rules.luau"), "function R.Action("),
	body(read("src/ServerScriptService/Economy/PlotRules.luau"), "function S.Action("),
	body(read("src/ServerScriptService/Economy/ItemRules.luau"), "function I.Action("),
} do
	for name in part:gmatch("action%s*[=~]=%s*['\"]([%w_]+)['\"]") do
		LEGACY[name] = true
	end
end
-- Legacy names that features took over on purpose (documented in their headers).
local TAKEOVERS = { DexClaim = "Dogdex" }
-- Prefixes Runtime.Request routes before any feature could see them.
local RESERVED_PREFIX = { "Mining" }

test("the legacy scan sees every known legacy action", function()
	for _, name in {
		"Snapshot", "MarketQuery", "DistrictTravel", "Tutorial", "LabInfo", "LabPreview", "LabCommit", "SellItem", "SellQuote",
		"NPCSell", "BulkSell", "SellLoot", "BuyPlotSkin", "ClaimPlotSkin", "EquipPlotSkin", "DisplayDog", "ClaimOffline", "List",
		"BuyListing", "Bid", "CancelListing", "Roll", "EventClaim", "TradeRequest", "TradeCancel", "Trade", "RecordClaim",
		"TrackListing", "DogFavorite", "DogLock", "DexFavorite", "Forage", "Assign", "Remove", "Layer", "DailyReward",
		"PlaytimeReward", "Retire", "Mutation", "Ascend", "Fusion", "Supply", "Luck", "Cosmetic", "DexClaim", "SetClaim",
		"Prestige", "ItemLock", "ItemFavorite", "ItemSetClaim",
	} do
		truthy(LEGACY[name], "scan missed " .. name)
	end
end)

test("no two features own the same action", function()
	eq(#Registry.Collisions, 0, "Registry.Collisions")
	local owners = {}
	for _, f in Registry.Modules do
		for action, owned in f.Actions or {} do
			if owned then
				truthy(not owners[action], action .. " is owned by " .. tostring(owners[action]) .. " and " .. f.Name)
				owners[action] = f.Name
				eq(Registry.Owner(action), f, "Owner(" .. action .. ")")
			end
		end
	end
	truthy(owners.SettingsSave == "Settings" and owners.TreeUpgrade == "UpgradeTree" and owners.EquipArtifact == "Equipment", "real owners")
end)

test("no feature action shadows a legacy action or a reserved prefix", function()
	for _, f in Registry.Modules do
		for action, owned in f.Actions or {} do
			if owned then
				truthy(type(action) == "string" and #action <= 40, "action name " .. tostring(action))
				truthy(not LEGACY[action] or TAKEOVERS[action] == f.Name, f.Name .. " shadows the legacy action " .. action)
				for _, prefix in RESERVED_PREFIX do
					truthy(action:sub(1, #prefix) ~= prefix, f.Name .. " uses the reserved prefix " .. prefix .. ": " .. action)
				end
			end
		end
	end
end)

test("features answer exactly the actions they declare", function()
	local now = 1800000000
	local p = R.Normalize(nil, 77, now)
	local function rng()
		return 0.5
	end
	for _, f in Registry.Modules do
		if f.Action then
			-- No feature quietly answers a legacy action it does not declare.
			for name in LEGACY do
				if not (f.Actions and f.Actions[name]) then
					local ok, message = pcall(f.Action, R, R.Copy(p), name, {}, now, rng)
					truthy(ok and message == nil, f.Name .. " answers the legacy action " .. name .. ": " .. tostring(message))
				end
			end
			-- A declared action is really answered (a reply or a refusal), never passed on.
			for action, owned in f.Actions or {} do
				if owned then
					local ok, message = pcall(f.Action, R, R.Copy(p), action, {}, now, rng)
					truthy(not ok or message ~= nil, f.Name .. " declares " .. action .. " but passes it on")
				end
			end
		end
	end
end)

print(("feature_hooks: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
