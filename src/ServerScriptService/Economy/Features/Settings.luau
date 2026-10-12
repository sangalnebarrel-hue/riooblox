-- SETTINGS (feature module, see Economy.FeatureRegistry): the player's own preferences, saved with
-- the profile so they follow the player to every device. Schema and defaults:
-- ReplicatedStorage.SettingsConfig (Quality, ReducedMotion, UIVolume, SFXVolume, MusicVolume,
-- TitleDisplay, TradeRequests, HideUIHint).
--   p.Settings = {Version=1, <Key>=value, ...}   every known key, always valid (Normalize heals);
--                keys of a later build are kept as they are (at most 16 small scalars) so a
--                rollback loses nothing.
-- Action SettingsSave (DogEconomyRequest, cost 0.5 token, Reply='Patch'):
--   {Key=k, Value=v}               one setting
--   {Values={[k]=v, ...}}          several at once (all valid or nothing is saved)
--   -> "Settings saved", StatePatch = {Settings = <all settings>}
-- Clients read snapshot.Features.Settings and the player attributes Setting_<Key> (published by
-- Project, only when a value changes). Server code reads one value with F.Get(p, key) (nil-safe).
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("SettingsConfig"))

local F = { Name = "Settings", Order = 30 }
F.Actions = { SettingsSave = true }
F.Reply = "Patch"

local MAX_UNKNOWN = 16
local MAX_TEXT = 40
local MAX_VERSION = 1000

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
-- A value of a key this build does not know (a later build's setting): small and JSON-safe.
local function keepable(key: any, value: any): boolean
	if type(key) ~= "string" or #key == 0 or #key > MAX_TEXT then
		return false
	end
	return type(value) == "boolean" or finite(value) or (type(value) == "string" and #value <= MAX_TEXT)
end

-- Every known key valid, unknown keys kept within bounds, Version never lowered.
function F.Normalize(_R, p, _now)
	local s = p.Settings
	if type(s) ~= "table" then
		s = {}
		p.Settings = s
	end
	if not (finite(s.Version) and s.Version % 1 == 0 and s.Version >= Config.Version and s.Version <= MAX_VERSION) then
		s.Version = Config.Version
	end
	for _, row in ipairs(Config.Keys) do
		local healed = Config.Heal(row.Key, s[row.Key])
		if s[row.Key] ~= healed then
			s[row.Key] = healed
		end
	end
	local unknown, drop = 0, nil
	for key, value in pairs(s) do
		if key ~= "Version" and not Config.ByKey[key] then
			if keepable(key, value) and unknown < MAX_UNKNOWN then
				unknown += 1
			else
				drop = drop or {}
				table.insert(drop, key)
			end
		end
	end
	for _, key in ipairs(drop or {}) do
		s[key] = nil
	end
end

-- Structure only (what Normalize guarantees). A profile that has not been normalized passes.
function F.Validate(R, p)
	local s = p.Settings
	if s == nil then
		return
	end
	R.Check(type(s) == "table", "Invalid settings")
	R.Check(R.Int(s.Version, 1, MAX_VERSION), "Invalid settings version")
	local unknown = 0
	for key, value in pairs(s) do
		if key ~= "Version" then
			if Config.ByKey[key] then
				R.Check(value == nil or Config.Valid(key, value), "Invalid setting " .. key)
			else
				unknown += 1
				R.Check(unknown <= MAX_UNKNOWN and keepable(key, value), "Invalid settings")
			end
		end
	end
end

-- Every known setting (saved value or default): the client view and the attribute source.
function F.View(p: any): { [string]: any }
	local s = type(p) == "table" and p.Settings or nil
	local out = {}
	for _, row in ipairs(Config.Keys) do
		out[row.Key] = Config.Read(s, row.Key)
	end
	return out
end

function F.Get(p: any, key: string): any
	return Config.Read(type(p) == "table" and p.Settings or nil, key)
end

function F.Cost(_action: string): number
	return 0.5
end

function F.Action(R, p, action, a, _now, _random)
	if action ~= "SettingsSave" then
		return nil
	end
	R.Check(type(a) == "table", "Invalid request")
	-- {key, value} pairs (a list: a missing Value must not vanish from the request).
	local changes = {}
	if a.Values == nil then
		R.Check(a.Key ~= nil, "Choose a setting")
		changes[1] = { a.Key, a.Value }
	else
		R.Check(a.Key == nil and type(a.Values) == "table" and next(a.Values) ~= nil, "Choose a setting")
		for key, value in pairs(a.Values) do
			table.insert(changes, { key, value })
		end
		R.Check(#changes <= #Config.Keys, "Too many settings")
	end
	-- Every value is checked before any is saved.
	for _, change in ipairs(changes) do
		R.Check(type(change[1]) == "string" and Config.ByKey[change[1]] ~= nil, "Unknown setting")
		R.Check(Config.Valid(change[1], change[2]), "Invalid value for this setting")
	end
	F.Normalize(R, p)
	for _, change in ipairs(changes) do
		p.Settings[change[1]] = Config.Heal(change[1], change[2])
	end
	return "Settings saved"
end

function F.Patch(_player, _action, _result, p)
	return { Settings = F.View(p) }
end

-- snapshot.Features.Settings: every setting with its current value.
function F.Snapshot(_R, p, view, _now)
	view.Settings = F.View(p)
end

-- Setting_<Key> player attributes, written only when a value changes.
local published = setmetatable({}, { __mode = "k" })
function F.Project(player, p, _runtime)
	local last = published[player]
	if not last then
		last = {}
		published[player] = last
	end
	for key, value in pairs(F.View(p)) do
		if last[key] ~= value then
			player:SetAttribute(Config.Attribute(key), value)
			last[key] = value
		end
	end
end

return F
