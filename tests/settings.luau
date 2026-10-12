--!nocheck
--!nolint
-- SETTINGS: ReplicatedStorage.SettingsConfig + Economy.Features.Settings (saved p.Settings, the
-- SettingsSave action, snapshot, Setting_<Key> attributes): lune run tests/settings.luau
-- Pure parts on tests/lib/economy_env; the request path on the REAL Runtime (tests/lib/server_world).
local process = require("@lune/process")
local serde = require("@lune/serde")
local L = require("./lib/economy_env")
local R = L.Require("ServerScriptService.Economy.Rules")
local F = L.Require("ServerScriptService.Economy.Features.Settings")
local Config = L.Require("ReplicatedStorage.SettingsConfig")

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
local function fails(fn, pattern)
	local ok, err = pcall(fn)
	truthy(not ok, "expected an error matching " .. tostring(pattern))
	truthy(tostring(err):find(pattern, 1, true), "error '" .. tostring(err) .. "' lacks '" .. pattern .. "'")
end
local function same(a, b, path)
	path = path or "p"
	if type(a) ~= type(b) then
		error(path .. ": " .. type(a) .. " vs " .. type(b), 2)
	end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then
			error(path .. ": " .. tostring(a) .. " vs " .. tostring(b), 2)
		end
		return
	end
	for k, v in a do
		same(v, b[k], path .. "." .. tostring(k))
	end
	for k in b do
		if a[k] == nil then
			error(path .. "." .. tostring(k) .. " missing", 2)
		end
	end
end

local NOW = 1760000000
local DEFAULTS = { Version = 1, Quality = "Auto", ReducedMotion = false, UIVolume = 0.8, SFXVolume = 0.8, MusicVolume = 0.6, TitleDisplay = "All", TradeRequests = "All", HideUIHint = true }
local function profile(settings)
	L.Time = NOW
	local p = R.Profile(1, NOW)
	p.Settings = settings
	return R.Normalize(p, 1, NOW)
end
local function save(p, a)
	return R.Action(p, "SettingsSave", a, NOW, function()
		return 0.5
	end)
end

test("the schema lists the eight settings with valid defaults", function()
	eq(#Config.Keys, 8)
	for _, row in Config.Keys do
		eq(Config.ByKey[row.Key], row)
		truthy(Config.Valid(row.Key, row.Default), row.Key .. " default")
		eq(DEFAULTS[row.Key], row.Default, row.Key)
		eq(Config.Attribute(row.Key), "Setting_" .. row.Key)
	end
	eq(Config.Read(nil, "Quality"), "Auto")
	eq(Config.Read({ Quality = "Ultra" }, "Quality"), "Auto")
	eq(Config.Read({ Quality = "Low" }, "Quality"), "Low")
	-- Unknown keys (a newer build's setting, a bad attribute name) are nil-safe everywhere.
	eq(Config.Heal("FutureKey", 1), nil, "Heal of an unknown key")
	eq(Config.Heal(nil, 1), nil)
	eq(Config.Valid("FutureKey", 1), false)
	eq(Config.Read({ FutureKey = 1 }, "FutureKey"), nil)
end)

test("Normalize creates p.Settings with every default (R.Profile does not)", function()
	eq(R.Profile(1, NOW).Settings, nil, "not in the profile template")
	local p = profile(nil)
	same(p.Settings, DEFAULTS)
	p = profile("garbage")
	same(p.Settings, DEFAULTS)
end)

test("bad types and values are healed, valid values kept", function()
	local p = profile({ Version = "x", Quality = 5, ReducedMotion = "yes", UIVolume = "loud", SFXVolume = 1.7, MusicVolume = -3, TitleDisplay = "Mine", TradeRequests = "Nope", HideUIHint = false })
	same(p.Settings, { Version = 1, Quality = "Auto", ReducedMotion = false, UIVolume = 0.8, SFXVolume = 1, MusicVolume = 0, TitleDisplay = "Mine", TradeRequests = "All", HideUIHint = false })
	p = profile({ UIVolume = 0 / 0, SFXVolume = math.huge, MusicVolume = 0.333333 })
	eq(p.Settings.UIVolume, 0.8, "NaN")
	eq(p.Settings.SFXVolume, 1, "inf is clamped")
	eq(p.Settings.MusicVolume, 0.33, "rounded to 0.01")
	R.Validate(p)
end)

test("a later build's version and keys survive (bounded)", function()
	local s = { Version = 3, Quality = "High", NewThing = "x", Flag = true, Ratio = 0.5, Big = string.rep("y", 80), Nested = {}, [7] = "numeric key" }
	for i = 1, 20 do
		s["Extra" .. i] = i
	end
	local p = profile(s)
	eq(p.Settings.Version, 3, "never lowered")
	eq(p.Settings.Quality, "High")
	eq(p.Settings.Big, nil, "long text dropped")
	eq(p.Settings.Nested, nil, "tables dropped")
	eq(p.Settings[7], nil, "non-string keys dropped")
	local unknown = 0
	for key in p.Settings do
		if key ~= "Version" and not Config.ByKey[key] then
			unknown += 1
		end
	end
	eq(unknown, 16, "at most 16 unknown keys")
	R.Validate(p)
	eq(profile({ Version = 0 }).Settings.Version, 1)
	eq(profile({ Version = 2.5 }).Settings.Version, 1)
end)

test("Normalize is idempotent and JSON-safe", function()
	for _, s in { nil, "x", { Quality = 5 }, { Version = 9, A = 1, B = "b", MusicVolume = 0.123 } } do
		local p = profile(s)
		local first = R.Copy(p.Settings)
		F.Normalize(R, p, NOW)
		R.Normalize(p, 1, NOW)
		same(p.Settings, first)
		same(serde.decode("json", serde.encode("json", p.Settings)), first)
	end
end)

test("Validate passes healed data and refuses real corruption", function()
	local p = profile(nil)
	R.Validate(p)
	p.Settings = nil
	R.Validate(p) -- not normalized yet: nil-safe
	p.Settings = { Version = 1, Quality = "Ultra" }
	fails(function()
		F.Validate(R, p)
	end, "Invalid setting Quality")
	p.Settings = { Version = 0 }
	fails(function()
		F.Validate(R, p)
	end, "Invalid settings version")
	p.Settings = "x"
	fails(function()
		F.Validate(R, p)
	end, "Invalid settings")
end)

test("SettingsSave saves one valid value", function()
	local p = profile(nil)
	eq(save(p, { Key = "Quality", Value = "Low" }), "Settings saved")
	eq(p.Settings.Quality, "Low")
	save(p, { Key = "UIVolume", Value = 0.337 })
	eq(p.Settings.UIVolume, 0.34, "stored rounded")
	save(p, { Key = "ReducedMotion", Value = true })
	eq(p.Settings.ReducedMotion, true)
	save(p, { Key = "TitleDisplay", Value = "Off" })
	eq(p.Settings.TitleDisplay, "Off")
	R.Validate(p)
end)

test("SettingsSave refuses bad requests and changes nothing", function()
	local p = profile(nil)
	local before = R.Copy(p.Settings)
	for _, case in {
		{ { Key = "Nope", Value = 1 }, "Unknown setting" },
		{ { Key = 5, Value = 1 }, "Unknown setting" },
		{ { Key = "UIVolume", Value = 2 }, "Invalid value for this setting" },
		{ { Key = "UIVolume", Value = 0 / 0 }, "Invalid value for this setting" },
		{ { Key = "UIVolume", Value = "0.5" }, "Invalid value for this setting" },
		{ { Key = "Quality", Value = "Ultra" }, "Invalid value for this setting" },
		{ { Key = "ReducedMotion", Value = 1 }, "Invalid value for this setting" },
		{ { Key = "HideUIHint" }, "Invalid value for this setting" },
		{ {}, "Choose a setting" },
		{ { Values = {} }, "Choose a setting" },
		{ { Values = "x" }, "Choose a setting" },
		{ { Key = "Quality", Value = "Low", Values = { Quality = "Low" } }, "Choose a setting" },
	} do
		fails(function()
			save(p, case[1])
		end, case[2])
	end
	same(p.Settings, before)
end)

test("a batch saves all or nothing", function()
	local p = profile(nil)
	eq(save(p, { Values = { Quality = "Medium", MusicVolume = 0.25, TradeRequests = "Off" } }), "Settings saved")
	eq(p.Settings.Quality, "Medium")
	eq(p.Settings.MusicVolume, 0.25)
	eq(p.Settings.TradeRequests, "Off")
	fails(function()
		save(p, { Values = { Quality = "High", UIVolume = 5 } })
	end, "Invalid value for this setting")
	eq(p.Settings.Quality, "Medium", "nothing of a refused batch is saved")
	local all = {}
	for _, row in Config.Keys do
		all[row.Key] = row.Default
	end
	save(p, { Values = all })
	all.Extra = 1
	fails(function()
		save(p, { Values = all })
	end, "Too many settings")
end)

test("snapshot, patch and readers carry every setting", function()
	local p = profile({ Quality = "High" })
	local view = {}
	F.Snapshot(R, p, view, NOW)
	eq(view.Settings.Quality, "High")
	eq(view.Settings.Version, nil, "only the settings")
	-- Patch is the new snapshot.Features.Settings (the registry wraps it in StatePatch.Features).
	local patch = F.Patch(nil, "SettingsSave", {}, p)
	same(patch, view.Settings)
	local defaults = F.View({})
	for _, row in Config.Keys do
		eq(defaults[row.Key], row.Default)
	end
	eq(F.Get(p, "Quality"), "High")
	eq(F.Get({}, "TradeRequests"), "All")
	eq(F.Get(nil, "HideUIHint"), true)
	eq(F.Cost("SettingsSave"), 0.5)
end)

test("Project publishes Setting_<Key> attributes only when a value changes", function()
	local writes = {}
	local player = {
		Attributes = {},
		SetAttribute = function(self, k, v)
			table.insert(writes, k)
			self.Attributes[k] = v
		end,
	}
	local p = profile({ SFXVolume = 0.5 })
	F.Project(player, p)
	eq(#writes, 8, "first publish writes every setting")
	eq(player.Attributes.Setting_SFXVolume, 0.5)
	eq(player.Attributes.Setting_Quality, "Auto")
	eq(player.Attributes.Setting_HideUIHint, true)
	table.clear(writes)
	F.Project(player, p)
	eq(#writes, 0, "nothing changed")
	save(p, { Key = "Quality", Value = "Low" })
	F.Project(player, p)
	eq(#writes, 1)
	eq(writes[1], "Setting_Quality")
	eq(player.Attributes.Setting_Quality, "Low")
end)

-- ===== The request path on the REAL Runtime =====
local World = require("./lib/server_world")
local W = World.new()
local player = W.Join(1)
-- What snapshot.Features.Settings holds right now (the patch must carry the same).
local function snapshotSettings(world)
	local _, snapshot = world.Request(player, "Snapshot", {})
	return snapshot.Features.Settings
end

test("SettingsSave through Runtime.Request: a small patch, attributes and the saved profile", function()
	eq(player:GetAttribute("Setting_Quality"), "Auto", "published at join")
	local ok, result = W.Request(player, "SettingsSave", { Key = "Quality", Value = "Low" })
	truthy(ok, tostring(result))
	eq(result.Message, "Settings saved")
	eq(result.StateSnapshot, nil, "no full snapshot")
	same(result.StatePatch, { Features = { Settings = snapshotSettings(W) } }, "StatePatch.Features.Settings only")
	eq(result.StatePatch.Features.Settings.Quality, "Low")
	eq(player:GetAttribute("Setting_Quality"), "Low")
	eq(W.Profile(1).Settings.Quality, "Low")
	ok, result = W.Request(player, "SettingsSave", { Values = { MusicVolume = 0.1, HideUIHint = false } })
	truthy(ok, tostring(result))
	eq(player:GetAttribute("Setting_MusicVolume"), 0.1)
	eq(player:GetAttribute("Setting_HideUIHint"), false)
	ok, result = W.Request(player, "SettingsSave", { Key = "Quality", Value = "Ultra" })
	eq(ok, false)
	truthy(tostring(result):find("Invalid value", 1, true), tostring(result))
	local _, snapshot = W.Request(player, "Snapshot", {})
	eq(snapshot.Features.Settings.Quality, "Low")
	eq(snapshot.Features.Settings.MusicVolume, 0.1)
end)

print(("settings: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
