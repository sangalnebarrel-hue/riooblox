-- Russian strings of SHOW THE WAY (Navigation: district map, route chip, WHERE TO GO? window),
-- read by StarterPlayer.StarterPlayerScripts.DOGROTS_AutoTranslateUI. The new labels localize
-- themselves (Kit.T / NoTranslate); this file covers the English texts that still reach
-- AutoTranslate: every destination name, short name and subtitle (also used by other screens and
-- MapRouting.Locations), the map captions and the words other modules show next to a route.
local Destinations = require(script.Parent.Parent:WaitForChild("Navigation"):WaitForChild("Destinations"))

local exact = {
	-- Window, chips, buttons.
	["WHERE TO GO?"] = "КУДА ИДТИ?",
	["Pick a place: glowing arrows will lead you there"] = "Выбери место — светящиеся стрелки приведут тебя туда",
	["Choose a place: glowing arrows on the ground will lead you there."] = "Выбери место — светящиеся стрелки на земле приведут тебя туда.",
	["Follow the glowing arrows!"] = "Иди по светящимся стрелкам!",
	["SHOW PATH"] = "ПОКАЗАТЬ ПУТЬ",
	["SHOW THE PATH"] = "ПОКАЗАТЬ ПУТЬ",
	["ON ROUTE"] = "В ПУТИ",
	["● ON ROUTE"] = "● В ПУТИ",
	["YOU ARE HERE!"] = "ТЫ НА МЕСТЕ!",
	["N — this window · M — district map"] = "N — это окно · M — карта района",
	["Your yard is not ready yet"] = "Участок ещё не готов",
	["Your yard is not ready yet. Try again in a moment."] = "Участок ещё не готов. Попробуй через минуту.",
	["This place is not on the map"] = "Этого места нет на карте",
	["This place is not on the map."] = "Этого места нет на карте.",
	-- The previous map texts (kept for older labels).
	["CLEAR MARKER"] = "УБРАТЬ МЕТКУ",
	["CLEAR ROUTE"] = "УБРАТЬ МАРШРУТ",
	["Nuclear mutation machine"] = "Ядерная мутационная машина",
	["SEALED / FUTURE AREA"] = "ЗАКРЫТО / БУДУЩАЯ ЗОНА",
}

-- Every destination: name and subtitle (the chip's one-word short names localize themselves:
-- words like "LAB" or "MARKET" are left to the dictionaries of the screens that own them).
for _, entry in ipairs(Destinations.List) do
	for _, field in ipairs({ "Name", "Detail" }) do
		local en = entry[field]
		local ru = Destinations.Text(entry, field, "ru")
		if type(en) == "string" and type(ru) == "string" and en ~= ru and exact[en] == nil then
			exact[en] = ru
		end
	end
end

return {
	Exact = exact,
	Patterns = {
		{ "^On route: (.+) · (%d+) m$", "В пути: %1 · %2 м" },
	},
	Phrases = {},
}
