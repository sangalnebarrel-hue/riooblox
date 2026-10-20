-- Russian of CHAPTER II combat server text (ReplicatedStorage.Localization.Combat, WP-B).
--   Exact     English replies of ServerScriptService.Halloween.EventHP (C2SelfRevive, the Studio combat debug) and the
--             Strike gate message; DOGROTS_AutoTranslateUI loads them for every label (global keys: never repeat a key
--             another Localization module has)
--   Patterns  none: combat replies carry no numbers
--   Codes     server error codes the clients map themselves (MiningClient.HalloweenStrike: HW:DOWNED)
-- The combat HUD, telegraphs, REVIVE prompts and downed markers are self-localized on the client (Shared.L + NoTranslate).
-- Glossary: Event HP = очки здоровья события (ОЗ), DOWNED = повержен, REVIVE = поднять, bleed-out = истечь кровью,
-- WEAKENED = ослаблен, MOURNING VEIL = Скорбная вуаль, Mourning Shiba = Скорбная шиба.
local L = {}

L.Exact = {
	["You are not in a fight"] = "Ты сейчас не в бою",
	["You are not downed"] = "Ты не повержен",
	["MOURNING VEIL needs the Mourning Shiba in your yard team"] = "Для СКОРБНОЙ ВУАЛИ нужна Скорбная шиба в команде двора",
	["MOURNING VEIL was already used in this fight"] = "СКОРБНАЯ ВУАЛЬ уже использована в этом бою",
	["MOURNING VEIL is not ready yet"] = "СКОРБНАЯ ВУАЛЬ ещё не готова",
	["You are downed: wait for a revive"] = "Ты повержен: дождись, пока тебя поднимут",
	-- Studio combat debug (C2CombatDebug)
	["Entered Debug combat"] = "Тестовый бой начат",
	["Left combat"] = "Бой покинут",
	["Hazards spawned"] = "Опасности созданы",
	["Combat hit dealt"] = "Удар по ОЗ нанесён",
	["Combat: downed"] = "Бой: повержен",
	["Combat: revived"] = "Бой: поднят",
	["Combat: shield added"] = "Бой: щит добавлен",
	["Combat: weakened"] = "Бой: ослаблен",
	["Unknown combat debug command"] = "Неизвестная команда отладки боя",
}

L.Patterns = {}
L.Phrases = {}

L.Codes = {
	["HW:DOWNED"] = { "You are downed: wait for a revive", "Ты повержен: дождись, пока тебя поднимут" },
}

return L
