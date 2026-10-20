-- Russian for THE UNDERYARD showcase finds (ReplicatedStorage.Localization.UnderyardItems): the 15 find names (as
-- cards show them and in capitals for banners / reveals) and their descriptions. DOGROTS_AutoTranslateUI loads every
-- module in this folder. The data lives in DogEconomy.ItemDefinitions (rows with Event = "Underyard2026" carry RU and
-- DescriptionRU), so this table is built from it and never drifts. Decoration names come from DecorCatalog
-- (Localization.Plot adds them).
local Economy = script.Parent.Parent:WaitForChild("DogEconomy")
local Items = require(Economy:WaitForChild("ItemDefinitions"))

-- Capitals of Latin and Cyrillic text (string.upper only knows ASCII).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x61 and code <= 0x7A) or (code >= 0x0430 and code <= 0x044F) then
			code -= 0x20
		elseif code == 0x0451 then
			code = 0x0401
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local Exact: { [string]: string } = {}
for _, def in pairs(Items) do
	if type(def) == "table" and def.Event == "Underyard2026" and type(def.DisplayName) == "string" and type(def.RU) == "string" then
		Exact[def.DisplayName] = def.RU
		Exact[upper(def.DisplayName)] = upper(def.RU)
		if type(def.Description) == "string" and def.Description ~= "" and type(def.DescriptionRU) == "string" then
			Exact[def.Description] = def.DescriptionRU
		end
	end
end

return {
	Exact = Exact,
	Patterns = {},
	Phrases = {},
	Upper = upper,
}
