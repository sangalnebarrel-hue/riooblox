-- Player settings schema, shared by the server (Economy.Features.Settings saves them in p.Settings)
-- and clients (the settings window, Perf.Quality, UISound, titles...). Pure data and helpers.
--   Keys                 ordered list {Key, Type='Choice'|'Boolean'|'Number', Default, Options | Min/Max}
--   ByKey[key]           the row of a key
--   Attribute(key)       "Setting_<Key>": the player attribute the server publishes (on change only)
--   Valid(key, value)    true when `value` may be saved as is for `key`
--   Heal(key, value)     a valid value for `key`: `value` itself, a clamped and rounded number, or
--                        the default (wrong type, unknown option, NaN)
--   Defaults()           {[key]=default} for every key
--   Read(settings, key)  the saved value or the default (nil-safe: settings may be nil)
-- Numbers are volumes in 0..1, stored rounded to 0.01. IDs and options are saved data: only add.
local SettingsConfig = {}
SettingsConfig.Version = 1
SettingsConfig.AttributePrefix = "Setting_"
SettingsConfig.Keys = {
	{ Key = "Quality", Type = "Choice", Options = { "Auto", "High", "Medium", "Low" }, Default = "Auto" },
	{ Key = "ReducedMotion", Type = "Boolean", Default = false },
	{ Key = "UIVolume", Type = "Number", Min = 0, Max = 1, Default = 0.8 },
	{ Key = "SFXVolume", Type = "Number", Min = 0, Max = 1, Default = 0.8 },
	{ Key = "MusicVolume", Type = "Number", Min = 0, Max = 1, Default = 0.6 },
	{ Key = "TitleDisplay", Type = "Choice", Options = { "All", "Mine", "Off" }, Default = "All" },
	{ Key = "TradeRequests", Type = "Choice", Options = { "All", "Off" }, Default = "All" },
	{ Key = "HideUIHint", Type = "Boolean", Default = true },
}
SettingsConfig.ByKey = {}
for _, row in ipairs(SettingsConfig.Keys) do
	SettingsConfig.ByKey[row.Key] = row
end

local function round(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

function SettingsConfig.Attribute(key: string): string
	return SettingsConfig.AttributePrefix .. key
end

function SettingsConfig.Valid(key: any, value: any): boolean
	local row = type(key) == "string" and SettingsConfig.ByKey[key] or nil
	if not row then
		return false
	end
	if row.Type == "Boolean" then
		return type(value) == "boolean"
	elseif row.Type == "Number" then
		return type(value) == "number" and value == value and value >= row.Min and value <= row.Max
	end
	return type(value) == "string" and table.find(row.Options, value) ~= nil
end

function SettingsConfig.Heal(key: string, value: any): any
	local row = SettingsConfig.ByKey[key]
	if row.Type == "Number" then
		if type(value) ~= "number" or value ~= value then
			return row.Default
		end
		return round(math.clamp(value, row.Min, row.Max))
	end
	if SettingsConfig.Valid(key, value) then
		return value
	end
	return row.Default
end

function SettingsConfig.Defaults(): { [string]: any }
	local out = {}
	for _, row in ipairs(SettingsConfig.Keys) do
		out[row.Key] = row.Default
	end
	return out
end

function SettingsConfig.Read(settings: any, key: string): any
	local row = SettingsConfig.ByKey[key]
	local value = nil
	if type(settings) == "table" then
		value = settings[key] -- may be false: never `and/or` it
	end
	if row and SettingsConfig.Valid(key, value) then
		return value
	end
	return row and row.Default
end

return SettingsConfig
