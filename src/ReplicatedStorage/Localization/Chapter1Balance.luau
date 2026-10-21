-- Russian of the CHAPTER I REBALANCE server texts (ReplicatedStorage.Localization.Chapter1Balance, WP-E; DESIGN §12).
-- DOGROTS_AutoTranslateUI loads every Localization module: Exact = whole English server messages / toasts (global keys,
-- never repeated in another module), Patterns = {luaPattern, replacement} for messages with numbers. Sources:
--   SSS.Halloween.Actions    CauldronTrick refused because the escalating price rose above the one the player saw
--   SSS.Halloween.Exorcism   the 2500-soul block now goes to exorcists active in the Dead Yard only
--   SSS.Economy.EventBlocks  the Lucky Dust filler row of the rescaled Pumpkin tables (odds name + opened reward)
-- Glossary as in Localization.Halloween: Candy = конфеты, TRICK = гадость, Dead Yard = Мёртвый двор, Lucky Dust =
-- счастливая пыль, exorcist = экзорцист.
local L = {}

L.Exact = {
	["THE DEAD YARD is closed for now"] = "МЁРТВЫЙ ДВОР пока закрыт",
	["The cauldron grew hungrier: the TRICK price changed"] = "Котёл проголодался: цена гадости выросла",
	["Only exorcists active in the Dead Yard got the RARE PUMPKIN LUCKY BLOCK. Play there to share the next one!"] =
		"Редкий тыквенный счастливый блок получили только экзорцисты, игравшие на Мёртвом дворе. Играй там, чтобы получить следующий!",
}

L.Patterns = {
	{ "^LUCKY DUST$", "СЧАСТЛИВАЯ ПЫЛЬ" },
	{ "^([%d,%.]+[KMB]?) Lucky Dust$", "%1 счастливой пыли" },
}

L.Phrases = {}

-- Russian of `text` (Exact, then Patterns) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local exact = L.Exact[text]
	if exact then
		return exact
	end
	for _, rule in ipairs(L.Patterns) do
		local ok, out, n = pcall(string.gsub, text, rule[1], rule[2])
		if ok and n > 0 and out ~= text then
			return out
		end
	end
	return nil
end

return L
