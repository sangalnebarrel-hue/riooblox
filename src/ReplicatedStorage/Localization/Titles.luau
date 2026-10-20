-- Russian strings of the player titles (TITLES window, unlock toasts, server replies) and of the
-- reworked DOG RUSH event (banner, pup chip, chests, prompts, perk line).
--   Exact     read by DOGROTS_AutoTranslateUI (and by Modules.TitlesScreen, which translates itself).
--             Only strings unique to these features: an Exact entry wins over every other dictionary,
--             so generic words ("ALL", "EQUIPPED", category names) stay out of it.
--             Title names and their "how to get" lines live in DogEconomy.TitleDefinitions (Text / RU)
--             and are added here so any other screen that shows them gets Russian too.
--   Window    words the TITLES window shows that the base dictionary already translates (possibly
--             in another form); only the window reads them (AutoTranslate ignores this field).
--   Patterns  formatted lines.
-- tests/titles.luau checks that every T("...") of TitlesScreen has an entry in Exact or Window.
local Titles = require(script.Parent.Parent:WaitForChild("DogEconomy"):WaitForChild("TitleDefinitions"))

local Exact = {
	-- TITLES window
	["Earn titles with achievements and wear one above your head"] = "Получай титулы за достижения и носи один над головой",
	["YOUR TITLE"] = "ТВОЙ ТИТУЛ",
	["NO TITLE"] = "БЕЗ ТИТУЛА",
	["Pick an unlocked title below to show it above your head."] = "Выбери открытый титул ниже, чтобы он появился над твоей головой.",
	["Everyone nearby sees it above your head."] = "Все рядом видят его над твоей головой.",
	["SECRET TITLE"] = "СЕКРЕТНЫЙ ТИТУЛ",
	["Keep exploring to reveal it."] = "Продолжай исследовать, чтобы узнать его.",
	["NO TITLES HERE YET"] = "ЗДЕСЬ ПОКА НЕТ ТИТУЛОВ",
	["Try another category."] = "Попробуй другую категорию.",
	["Loading your titles..."] = "Загружаем твои титулы...",
	["Could not load your titles. Try again."] = "Не удалось загрузить титулы. Попробуй ещё раз.",
	["READY! Equip it."] = "ГОТОВО! Надень его.",
	["NEW TITLE UNLOCKED: "] = "НОВЫЙ ТИТУЛ: ",
	["NEW TITLES UNLOCKED"] = "НОВЫЕ ТИТУЛЫ ОТКРЫТЫ",
	-- Server replies (Features.Titles)
	["Title equipped"] = "Титул надет",
	["Title removed"] = "Титул снят",
	["This title is still locked"] = "Этот титул ещё не открыт",
	["Unknown title"] = "Неизвестный титул",
	["Invalid title"] = "Неверный титул",
	-- DOG RUSH (one name everywhere: СОБАЧИЙ ЗАБЕГ)
	["DOG RUSH"] = "СОБАЧИЙ ЗАБЕГ",
	["Dog Rush"] = "Собачий забег",
	["DOG RUSH!"] = "СОБАЧИЙ ЗАБЕГ!",
	["Catch the runaway golden pups! Chests at 3 · 6 · 10"] = "Лови сбежавших золотых щенков! Сундуки за 3 · 6 · 10",
	["CATCH RUNAWAY PUPS · CHESTS AT 3 / 6 / 10"] = "ЛОВИ СБЕЖАВШИХ ЩЕНКОВ · СУНДУКИ ЗА 3 / 6 / 10",
	["Runaway pup"] = "Сбежавший щенок",
	["RUNAWAY PUP"] = "СБЕЖАВШИЙ ЩЕНОК",
	["NEXT CHEST AT "] = "СУНДУК НА ",
	["ALL CHESTS OPEN!"] = "ВСЕ СУНДУКИ ОТКРЫТЫ!",
	["ALL PUPS CAUGHT!"] = "ВСЕ ЩЕНКИ ПОЙМАНЫ!",
	["PUP CHEST"] = "СУНДУК ЩЕНКА",
	["PACK CHEST"] = "СУНДУК СТАИ",
	["GOLDEN CHEST"] = "ЗОЛОТОЙ СУНДУК",
	["  +1 LUCKY BLOCK"] = "  +1 СЧАСТЛИВЫЙ БЛОК",
	["You caught every pup you can this rush!"] = "Ты поймал всех щенков, которых можно в этом забеге!",
}

local Window = {
	["TITLES"] = "ТИТУЛЫ",
	["REMOVE"] = "СНЯТЬ",
	["EQUIP"] = "НАДЕТЬ",
	["EQUIPPED"] = "НАДЕТ",
	["LOCKED"] = "ЗАКРЫТ",
	["ALL"] = "ВСЕ",
	["OWNED"] = "ОТКРЫТЫЕ",
	["RARITY"] = "РЕДКОСТЬ",
	["PROGRESS"] = "ПРОГРЕСС",
	["NAME"] = "НАЗВАНИЕ",
	["more"] = "ещё",
	["h"] = "ч",
	["Please wait a moment"] = "Подожди немного",
	["Connection problem; try again"] = "Проблема со связью, попробуй ещё раз",
	["Your saved profile is still loading"] = "Твой профиль ещё загружается",
	["CATCH"] = "ПОЙМАТЬ",
	["CHEST"] = "СУНДУК",
}

-- Title names and how-to lines from the definitions (unique strings); categories are window words.
for _, def in ipairs(Titles.List) do
	Exact[def.Text] = def.RU
	if def.How and def.HowRU then
		Exact[def.How] = def.HowRU
	end
end
for _, cat in ipairs(Titles.Categories) do
	Window[cat.Text] = cat.RU
end
for rarity, ru in pairs(Titles.RarityRU) do
	Window[string.upper(rarity)] = ru
end

return {
	Exact = Exact,
	Window = Window,
	Patterns = {
		{ "^NEW TITLE UNLOCKED: (.+)$", "НОВЫЙ ТИТУЛ: %1" },
		{ "^NEXT CHEST AT (%d+)$", "СУНДУК НА %1" },
	},
	Phrases = {},
}
