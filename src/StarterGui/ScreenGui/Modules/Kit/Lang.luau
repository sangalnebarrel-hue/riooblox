-- Language helpers.
--  * Lang.Get() -> "ru" | "en": the same locale rule as DOGROTS_AutoTranslateUI and Mining.MiningText.
--  * Lang.T(en, ru): pick a self-localized string (set NoTranslate on labels that only show those).
--  * Lang.Word(key): a kit-internal English word ("SEARCH", "CANCEL"...). These are left to
--    DOGROTS_AutoTranslateUI, which translates them through exact entries (base dictionary or
--    ReplicatedStorage.Localization.Kit); tests/uikit.luau checks every word has one.
local Lang = {}

Lang.Words = {
	SEARCH = "SEARCH",
	SORT = "SORT",
	FILTERS = "FILTERS",
	CANCEL = "CANCEL",
	CONFIRM = "CONFIRM",
	HOLD = "HOLD TO CONFIRM",
	CLOSE = "CLOSE",
	BACK = "BACK",
	OK = "OK",
	EMPTY = "EMPTY",
	NOTHING = "NOTHING HERE YET",
	NO_RESULTS = "NO RESULTS",
	TRY_FILTERS = "Try another search or filter.",
	LOADING = "LOADING",
	LOCKED = "LOCKED",
	OWNED = "OWNED",
	NOT_OWNED = "NOT OWNED",
	SELECTED = "SELECTED",
	NEW = "NEW",
	ALL = "ALL",
	CLEAR = "CLEAR",
	READY = "READY",
	DETAILS = "DETAILS",
	MAX = "MAX",
	FREE = "FREE",
	UNAVAILABLE = "UNAVAILABLE",
}

-- Rarity, variant and mutation words shown by tags are upper-case English (AutoTranslate has
-- exact entries for them).
function Lang.Upper(name: string?): string
	return string.upper(tostring(name or ""))
end

function Lang.Word(key: string): string
	return (Lang.Words :: any)[key] or key
end

-- "ru" or "en". Override (set by tests or a settings toggle) wins.
Lang.Override = nil :: string?
local cached: string? = nil
local watching = false

local function readLocale(): string?
	local ok, locale = pcall(function()
		local Players = game:GetService("Players")
		local LocalizationService = game:GetService("LocalizationService")
		local player = Players.LocalPlayer
		if game:GetService("RunService"):IsStudio() or not player then
			return LocalizationService.RobloxLocaleId
		end
		return player.LocaleId or LocalizationService.RobloxLocaleId
	end)
	if ok and type(locale) == "string" then
		return locale
	end
	return nil
end

local function watch()
	if watching then
		return
	end
	watching = true
	pcall(function()
		local reset = function()
			cached = nil
		end
		local player = game:GetService("Players").LocalPlayer
		if player then
			player:GetPropertyChangedSignal("LocaleId"):Connect(reset)
		end
		game:GetService("LocalizationService"):GetPropertyChangedSignal("RobloxLocaleId"):Connect(reset)
	end)
end

function Lang.Get(): string
	local override = (Lang :: any).Override
	if type(override) == "string" then
		return override
	end
	local known = cached
	if known then
		return known
	end
	local locale = readLocale()
	local result = (locale and string.lower(string.sub(locale, 1, 2)) == "ru") and "ru" or "en"
	cached = result
	watch()
	return result
end

function Lang.T(en: string, ru: string?): string
	if ru and Lang.Get() == "ru" then
		return ru
	end
	return en
end

return Lang
