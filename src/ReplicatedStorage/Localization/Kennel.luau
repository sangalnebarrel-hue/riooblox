-- Russian strings of the KENNEL window (Modules.KennelScreen): the dog picker of one dig kennel.
--   UI, Templates  self-localized window text (labels carry NoTranslate); read only by KennelScreen
--                  (it falls back to Localization.Dogs.UI / Templates for the shared dog words)
--   Exact, Patterns, Phrases  for DOGROTS_AutoTranslateUI (none needed: the server replies the window
--                  shows are already in the base dictionary / Localization.Dogs.Exact)
-- tools/test_kennel.luau checks that every T("...") / F("...") of the window has an entry here or in
-- Localization.Dogs, and that every template keeps its format specifiers.
return {
	UI = {
		-- window and toolbar
		["Choose a dog to dig here"] = "Выбери, кто будет копать здесь",
		["Loading..."] = "Загрузка...",
		["Search dogs"] = "Поиск собак",
		["Search"] = "Поиск",
		["BEST"] = "ЛУЧШИЕ",
		["INCOME"] = "ДОХОД",
		["MUTATION"] = "МУТАЦИЯ",
		["NAME"] = "ИМЯ",
		["IDLE"] = "БЕЗ ДЕЛА",
		["WORKING"] = "РАБОТАЮТ",
		["✨ MUTATED"] = "✨ С МУТАЦИЕЙ",
		-- IN THIS KENNEL
		["IN THIS KENNEL"] = "В ЭТОЙ БУДКЕ",
		["EMPTY KENNEL"] = "БУДКА ПУСТАЯ",
		["Pick a dog and press PUT TO WORK"] = "Выбери собаку и нажми «ОТПРАВИТЬ КОПАТЬ»",
		["REMOVE"] = "УБРАТЬ",
		-- cards and SELECTED DOG
		["NO MUTATION"] = "БЕЗ МУТАЦИИ",
		["SELECTED DOG"] = "ВЫБРАННАЯ СОБАКА",
		["Tap a dog to see it here"] = "Нажми на собаку, чтобы увидеть её здесь",
		["COINS / MIN"] = "МОНЕТ / МИН",
		["EFFICIENCY"] = "ЭФФЕКТИВНОСТЬ",
		["MUTATION BONUS"] = "БОНУС МУТАЦИИ",
		["In storage"] = "В хранилище",
		["Digging in this kennel"] = "Копает в этой будке",
		["On the way to your yard"] = "Идёт к тебе на участок",
		["ARRIVING"] = "В ПУТИ",
		["Same income as now"] = "Доход такой же, как сейчас",
		-- the button
		["PUT TO WORK"] = "ОТПРАВИТЬ КОПАТЬ",
		["SWAP"] = "ЗАМЕНИТЬ",
		["MOVE HERE"] = "ПЕРЕВЕСТИ СЮДА",
		["REMOVE FROM KENNEL"] = "УБРАТЬ ИЗ БУДКИ",
		["Select a dog"] = "Выбери собаку",
		["Wait until your dog arrives in your yard"] = "Подожди, пока собака дойдёт до участка",
		-- empty states
		["NO DOGS YET"] = "ПОКА НЕТ СОБАК",
		["Adopt a dog at the DOG LINE, then put it to work here."] = "Возьми собаку на СОБАЧЬЕЙ ЛЕНТЕ и отправь её копать сюда.",
		["SHOW THE WAY"] = "ПОКАЗАТЬ ПУТЬ",
		["NO DOGS HERE"] = "ЗДЕСЬ НЕТ СОБАК",
		["Try another search or filter."] = "Попробуй другой поиск или фильтр.",
		["NO OTHER DOGS"] = "ДРУГИХ СОБАК НЕТ",
		["Adopt more dogs at the DOG LINE."] = "Возьми ещё собак на СОБАЧЬЕЙ ЛЕНТЕ.",
		-- rarity and mutation names on the window's own tags (one form for the whole window)
		["COMMON"] = "ОБЫЧНЫЙ",
		["RARE"] = "РЕДКИЙ",
		["EPIC"] = "ЭПИЧЕСКИЙ",
		["LEGENDARY"] = "ЛЕГЕНДАРНЫЙ",
		["MYTHIC"] = "МИФИЧЕСКИЙ",
		["SECRET"] = "СЕКРЕТНЫЙ",
		["SHINY"] = "БЛЕСТЯЩИЙ",
		["GOLDEN"] = "ЗОЛОТОЙ",
		["CORRUPTED"] = "ИСКАЖЁННЫЙ",
		["GLITCHED"] = "ГЛИТЧЕВЫЙ",
		["VOID"] = "ПУСТОТНЫЙ",
	},
	Templates = {
		["KENNEL %d"] = "БУДКА %d",
		["Now digging: %s"] = "Сейчас копает: %s",
		["⛏ KENNEL %d"] = "⛏ БУДКА %d",
		["Digging in kennel %d"] = "Копает в будке %d",
		["$%s / min"] = "$%s / мин",
		["▲ +$%s / min more than now"] = "▲ на $%s / мин больше, чем сейчас",
		["▼ −$%s / min less than now"] = "▼ на $%s / мин меньше, чем сейчас",
		-- MOVE HERE: a dog from another kennel leaves that kennel empty
		["▼ −$%s / min · kennel %d will be empty"] = "▼ на $%s / мин меньше · будка %d опустеет",
		["Same income · kennel %d will be empty"] = "Доход тот же · будка %d опустеет",
		["%s digs in kennel %d"] = "%s копает в будке %d",
		["%s digs in kennel %d · %s went to storage"] = "%s копает в будке %d · %s — в хранилище",
		["%s returned to storage"] = "%s возвращается в хранилище",
		["%s moved here · kennel %d is free"] = "%s теперь здесь · будка %d свободна",
		["%d / %d SHOWN"] = "ПОКАЗАНО %d ИЗ %d",
		["DOGS: %d"] = "СОБАК: %d",
	},
	Exact = {},
	Patterns = {},
	Phrases = {},
}
