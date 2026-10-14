-- Russian strings of the yard MINE (docs/MINE.md), read by DOGROTS_AutoTranslateUI: the world
-- signs (headframe depth sign, kennel winch signs, the FINDS board of every level), the depth
-- names and server answers of the elevator (MineRequest). The MINE ELEVATOR window and the
-- client prompts localize themselves (Kit.T, MineThemes.Ru).
local exact = {
	-- Headframe depth sign and kennel winch signs.
	["DOGS DIG AT"] = "СОБАКИ КОПАЮТ",
	["DIGGING AT"] = "КОПАЕТ НА",
	-- Elevator station / walkway arrow / depot signs (MineStructures.Headframe, MineStructures.Depot).
	["MINE ELEVATOR"] = "ЛИФТ ШАХТЫ",
	["DOWN TO THE MINE"] = "ВНИЗ, В ШАХТУ",
	-- Depth names (MineThemes titles) and depths.
	["BACKYARD"] = "ЗАДНИЙ ДВОР",
	["CAVERNS"] = "ПЕЩЕРЫ",
	["ANCIENT RUINS"] = "ДРЕВНИЕ РУИНЫ",
	["CURSED DEPTHS"] = "ПРОКЛЯТЫЕ ГЛУБИНЫ",
	["THE VOID"] = "ПУСТОТА",
	["0–10 m"] = "0–10 м",
	["10–50 m"] = "10–50 м",
	["50–150 m"] = "50–150 м",
	["150–500 m"] = "150–500 м",
	["500+ m"] = "500+ м",
	-- FINDS board in every level.
	["FINDS AT THIS DEPTH"] = "НАХОДКИ НА ЭТОЙ ГЛУБИНЕ",
	-- Elevator answers (MineWorld: MineRequest "Ride").
	["This depth is still locked"] = "Эта глубина ещё закрыта",
	["Stand at the mine elevator"] = "Подойди к лифту шахты",
	["This yard has no owner"] = "У этого участка нет хозяина",
	["Wait for your character"] = "Подожди появления персонажа",
	["Please wait a moment"] = "Подожди немного",
	["The elevator is moving"] = "Лифт уже едет",
	["The mine is not ready yet"] = "Шахта ещё не готова",
	["Invalid layer"] = "Неверная глубина",
	["THE VOID requires Prestige 1"] = "Для ПУСТОТЫ нужен престиж 1",
}

return {
	Exact = exact,
	Patterns = {
		{ "^Unlock the previous layer and reach level (%d+)$", "Открой предыдущую глубину и достигни уровня %1" },
		{ "^(%d+)–(%d+) m$", "%1–%2 м" },
	},
	Phrases = {},
}
