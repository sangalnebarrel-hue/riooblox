-- Russian of CHAPTER II · THE UNDERYARD (ReplicatedStorage.Localization.Underyard, WP-A).
--   UI         self-localized labels (NoTranslate) shared by the Chapter II screens / HUD / FX: currencies, districts,
--              seals, tabs, common buttons. Read through L.Translate / L.UI by the Underyard window, the HUD and FX.
--              Never global.
--   Templates  string.format patterns of those labels; a value may be {one, few, many} (Russian plural of the first
--              number); the daily contract texts are here (Chapter2Config.Contracts.Pool[].Text[1])
--   Exact      English server messages of SSS.Halloween.Chapter2 / Underyard / Seals / Debug and Economy.Features.Underyard
--              (replies, toasts); DOGROTS_AutoTranslateUI loads them for every label in the game (global keys: never
--              repeat a key another Localization module or the base dictionary already has — "Please wait a moment",
--              "Not enough Candy", "Invalid reward", "Something went wrong, try again" come from there)
--   Patterns   {luaPattern, replacement} for server messages with numbers / numerals (anchored)
-- L.Translate(text, lang) -> russian | nil (Exact, UI, then Patterns); L.Plural(n, one, few, many); L.Format(key, ...)
-- Glossary: THE UNDERYARD = Поддворье, Bell Shards = осколки колокола, Lucky Dust = счастливая пыль, Coffin Key = ключ
-- от гроба, Black Coffin = Чёрный гроб, Bell Seal = печать колокола, offering = подношение, trial = испытание,
-- contract = контракт, Toll Box = Копилка звонаря, fragments = фрагменты, THE BELLKEEPER = Звонарь, Event HP = здоровье
-- события, Bell Resonance = резонанс колокола, Dex II = Догдекс II.
local L = {}

function L.Plural(n: number, one: string, few: string, many: string): string
	n = math.abs(math.floor(tonumber(n) or 0))
	local n10, n100 = n % 10, n % 100
	if n10 == 1 and n100 ~= 11 then
		return one
	end
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14) then
		return few
	end
	return many
end
local function shards(n: any): string
	local k = tonumber(n) or 0
	return tostring(n) .. " " .. L.Plural(k, "осколок колокола", "осколка колокола", "осколков колокола")
end
local function keys(n: any): string
	local k = tonumber(n) or 0
	return tostring(n) .. " " .. L.Plural(k, "ключ от гроба", "ключа от гроба", "ключей от гроба")
end

L.UI = {
	-- chapter / window
	["CHAPTER II"] = "ГЛАВА II",
	["CHAPTER I"] = "ГЛАВА I",
	["THE UNDERYARD"] = "ПОДДВОРЬЕ",
	["BENEATH THE LAST BELL"] = "ПОД ПОСЛЕДНИМ КОЛОКОЛОМ",
	["THE UNDERYARD · BENEATH THE LAST BELL"] = "ПОДДВОРЬЕ · ПОД ПОСЛЕДНИМ КОЛОКОЛОМ",
	["IS THAT ALL?"] = "И ЭТО ВСЁ?",
	["Did you really think it would be that easy?"] = "Вы правда думали, что всё будет настолько просто?",
	["FIND OUT"] = "УЗНАТЬ",
	["Something is waiting below."] = "Внизу что-то ждёт.",
	["DESCEND"] = "СПУСТИТЬСЯ",
	["ASCEND"] = "ПОДНЯТЬСЯ",
	["OPEN UNDERYARD"] = "ОТКРЫТЬ ПОДДВОРЬЕ",
	["LOCKED"] = "ЗАКРЫТО",
	["FINISH CHAPTER I"] = "ЗАВЕРШИ ГЛАВУ I",
	-- currencies
	["BELL SHARDS"] = "ОСКОЛКИ КОЛОКОЛА",
	["Bell Shards"] = "Осколки колокола",
	["LUCKY DUST"] = "СЧАСТЛИВАЯ ПЫЛЬ",
	["Lucky Dust"] = "Счастливая пыль",
	["COFFIN KEYS"] = "КЛЮЧИ ОТ ГРОБА",
	["COFFIN KEY"] = "КЛЮЧ ОТ ГРОБА",
	["Coffin Key"] = "Ключ от гроба",
	["FRAGMENTS"] = "ФРАГМЕНТЫ",
	["Cosmetic Fragments"] = "Фрагменты косметики",
	-- tabs / panels
	["SEALS"] = "ПЕЧАТИ",
	["CONTRACTS"] = "КОНТРАКТЫ",
	["COFFIN"] = "ГРОБ",
	["DEX II"] = "ДОГДЕКС II",
	["COLLECTION"] = "КОЛЛЕКЦИЯ",
	["JOURNAL"] = "ЖУРНАЛ",
	["THE BLACK COFFIN"] = "ЧЁРНЫЙ ГРОБ",
	["THE TOLL BOX"] = "КОПИЛКА ЗВОНАРЯ",
	["THE TAILOR OF THE DEAD"] = "ПОРТНОЙ МЁРТВЫХ",
	["DAILY CONTRACTS"] = "ЕЖЕДНЕВНЫЕ КОНТРАКТЫ",
	["CONTRACT BONUS"] = "БОНУС ЗА КОНТРАКТЫ",
	["DROP RATES"] = "ШАНСЫ ВЫПАДЕНИЯ",
	["LAST RESULTS"] = "ПОСЛЕДНИЕ НАГРАДЫ",
	["BELL RESONANCE"] = "РЕЗОНАНС КОЛОКОЛА",
	["RESTED"] = "ОТДОХНУВШИЙ",
	["EVENT HP"] = "ЗДОРОВЬЕ СОБЫТИЯ",
	["REPLAY"] = "ПОВТОРИТЬ",
	-- seal states / buttons
	["BELL SEAL"] = "ПЕЧАТЬ КОЛОКОЛА",
	["OFFER"] = "ПРИНЕСТИ",
	["OFFERING"] = "ПОДНОШЕНИЕ",
	["BEGIN TRIAL"] = "НАЧАТЬ ИСПЫТАНИЕ",
	["LEAVE TRIAL"] = "ПОКИНУТЬ ИСПЫТАНИЕ",
	["SEALED"] = "ЗАПЕЧАТАНО",
	["CLEARED"] = "ПРОЙДЕНО",
	["GOLD"] = "ЗОЛОТО",
	["PLAY"] = "ИГРАТЬ",
	["THE BELL REMEMBERS · -40%"] = "КОЛОКОЛ ПОМНИТ · -40%",
	["CLAIM"] = "ЗАБРАТЬ",
	["CLAIMED"] = "ПОЛУЧЕНО",
	["CRAFT"] = "СОЗДАТЬ",
	["OPEN"] = "ОТКРЫТЬ",
	["BUY"] = "КУПИТЬ",
	["TRIAL CLEARED"] = "ИСПЫТАНИЕ ПРОЙДЕНО",
	["TRIAL FAILED"] = "ИСПЫТАНИЕ ПРОВАЛЕНО",
	["TIME IS UP"] = "ВРЕМЯ ВЫШЛО",
	["DUPLICATE"] = "ДУБЛИКАТ",
	["CONVERTED"] = "ОБМЕНЕНО",
	-- districts (UnderyardLayout.Names)
	["BELL SQUARE"] = "КОЛОКОЛЬНАЯ ПЛОЩАДЬ",
	["FUNERAL CARNIVAL"] = "ПОХОРОННЫЙ КАРНАВАЛ",
	["MOURNING MARSH"] = "ТРАУРНАЯ ТОПЬ",
	["UNDERCRYPT"] = "ПОДКЛЕПЬЕ",
	["CROOKED ROW"] = "КРИВОЙ РЯД",
	["BLACK BELL ARENA"] = "АРЕНА ЧЁРНОГО КОЛОКОЛА",
	-- seals (Chapter2Config.Seals[].Name / Title)
	["ECHO"] = "ЭХО",
	["PROCESSION"] = "ПРОЦЕССИЯ",
	["REFLECTION"] = "ОТРАЖЕНИЕ",
	["HOLLOW"] = "ПУСТОТА",
	["CHOICE"] = "ВЫБОР",
	["CHOIR"] = "ХОР",
	["LAST BELL"] = "ПОСЛЕДНИЙ КОЛОКОЛ",
	["ECHO DIG"] = "ЭХО-РАСКОПКИ",
	["FUNERAL RUN"] = "ПОХОРОННЫЙ ЗАБЕГ",
	["MIRROR GRAVES"] = "ЗЕРКАЛЬНЫЕ МОГИЛЫ",
	["HOLLOW MINE"] = "ПОЛАЯ ШАХТА",
	["CROOKED DOORS"] = "КРИВЫЕ ДВЕРИ",
	["CHOIR HUNT"] = "ОХОТА НА ХОР",
	["LAST BELL TRIAL"] = "ИСПЫТАНИЕ ПОСЛЕДНЕГО КОЛОКОЛА",
	["THE BELLKEEPER"] = "ЗВОНАРЬ",
	["THE DOORKEEPER"] = "ПРИВРАТНИК",
	["BLACK BELL ASSAULT"] = "ШТУРМ ЧЁРНОГО КОЛОКОЛА",
	["RESONANT TOLL"] = "РЕЗОНИРУЮЩИЙ ЗВОН",
	["THE DEAD YARD"] = "МЁРТВЫЙ ДВОР",
	-- titles (Chapter2Config.Titles)
	["HOLLOW CROWN"] = "ПОЛАЯ КОРОНА",
	["THE LAST BARK"] = "ПОСЛЕДНИЙ ЛАЙ",
}

L.Templates = {
	["BELL SEAL %s"] = "ПЕЧАТЬ КОЛОКОЛА %s",
	["SEALED · BELL SEAL %s"] = "ЗАПЕЧАТАНО · ПЕЧАТЬ КОЛОКОЛА %s",
	["OPENS IN %s"] = "ОТКРОЕТСЯ ЧЕРЕЗ %s",
	["NEW CONTRACTS IN %s"] = "НОВЫЕ КОНТРАКТЫ ЧЕРЕЗ %s",
	["%d / %d"] = "%d / %d",
	["%d%% EFFICIENCY"] = "ЭФФЕКТИВНОСТЬ %d%%",
	["CHAPTER II · %d / %d"] = "ГЛАВА II · %d / %d",
	["Offer %d Bell Shards"] = { "Принеси %d осколок колокола", "Принеси %d осколка колокола", "Принеси %d осколков колокола" },
	["+%d BELL SHARDS"] = { "+%d ОСКОЛОК КОЛОКОЛА", "+%d ОСКОЛКА КОЛОКОЛА", "+%d ОСКОЛКОВ КОЛОКОЛА" },
	["%d COFFIN KEYS"] = { "%d КЛЮЧ ОТ ГРОБА", "%d КЛЮЧА ОТ ГРОБА", "%d КЛЮЧЕЙ ОТ ГРОБА" },
	["%d FRAGMENTS"] = { "%d ФРАГМЕНТ", "%d ФРАГМЕНТА", "%d ФРАГМЕНТОВ" },
	["%d Candy -> %d Bell Shards"] = "%d конфет -> %d осколков колокола",
	["Rested: %d shards at 100%%"] = "Отдых: %d осколков по 100%%",
	["Today %d / %d"] = "Сегодня %d / %d",
	["Doors today: %d / %d"] = "Дверей сегодня: %d / %d",
	-- daily contracts (Chapter2Config.Contracts.Pool; goal = the first number)
	["Land %d Perfect Hits in the Underyard"] = { "Сделай %d идеальный удар в Поддворье", "Сделай %d идеальных удара в Поддворье",
		"Сделай %d идеальных ударов в Поддворье" },
	["Clear any Bell Trial"] = "Пройди любое испытание колокола",
	["Dig %d echo points"] = { "Раскопай %d точку эха", "Раскопай %d точки эха", "Раскопай %d точек эха" },
	["Earn %d Bell Shards"] = { "Заработай %d осколок колокола", "Заработай %d осколка колокола", "Заработай %d осколков колокола" },
	["Deal %d damage to THE GRAVEKEEPER"] = "Нанеси СМОТРИТЕЛЮ КЛАДБИЩА %d урона",
	["Open a Black Coffin"] = "Открой Чёрный гроб",
	["Contribute %d Bell Resonance"] = "Внеси %d резонанса колокола",
	["Break %d hollow ore cores"] = { "Разбей %d полое рудное ядро", "Разбей %d полых рудных ядра", "Разбей %d полых рудных ядер" },
	["Revive an ally"] = "Подними союзника",
	["Open a Crooked Door"] = "Открой кривую дверь",
	["Catch %d choir spirits"] = { "Поймай %d духа хора", "Поймай %d духов хора", "Поймай %d духов хора" },
}

-- server replies / toasts (English from SSS.Halloween.Chapter2 / Underyard / Seals / Debug, Economy.Features.Underyard)
L.Exact = {
	-- Chapter2
	["Chapter II is closed"] = "Глава II закрыта",
	["Finish Chapter I first"] = "Сначала заверши главу I",
	["Not enough Bell Shards"] = "Не хватает осколков колокола",
	["No Crooked Door openings left today"] = "Сегодня кривые двери больше не открываются",
	["Unknown seal"] = "Неизвестная печать",
	["Make the offering at the seal's altar first"] = "Сначала принеси подношение к алтарю печати",
	["This seal has not opened yet"] = "Эта печать ещё не открылась",
	["Clear the previous seal first"] = "Сначала сломай предыдущую печать",
	["The offering is already made"] = "Подношение уже принесено",
	["Trial cleared again"] = "Испытание пройдено снова",
	["Come closer to the church"] = "Подойди ближе к церкви",
	["Invalid contract"] = "Неверный контракт",
	["This contract is not part of today's list"] = "Этого контракта нет в сегодняшнем списке",
	["Contract already claimed"] = "Контракт уже получен",
	["Contract not finished yet"] = "Контракт ещё не выполнен",
	["Contract reward claimed"] = "Награда за контракт получена",
	["Contract bonus already claimed today"] = "Бонус за контракты сегодня уже получен",
	["Finish and claim every contract first"] = "Сначала выполни и забери все контракты",
	["Contract bonus claimed"] = "Бонус за контракты получен",
	["Choose how many shards to buy"] = "Выбери, сколько осколков купить",
	["Come closer to the Toll Box"] = "Подойди ближе к Копилке звонаря",
	["The Toll Box is full for today. Come back tomorrow!"] = "Копилка звонаря на сегодня полна. Приходи завтра!",
	["Bell Shards bought"] = "Осколки колокола куплены",
	["Come closer to the seal's altar"] = "Подойди ближе к алтарю печати",
	["Offering accepted"] = "Подношение принято",
	["Discover more Underyard dogs first"] = "Сначала открой больше собак Поддворья",
	["Dex II reward claimed"] = "Награда Догдекса II получена",
	["Unknown cosmetic"] = "Неизвестная косметика",
	["This skin only comes from the Dex II"] = "Этот скин можно получить только в Догдексе II",
	["Not enough fragments"] = "Не хватает фрагментов",
	["This cosmetic is not available yet"] = "Эта косметика пока недоступна",
	["You already own this cosmetic"] = "У тебя уже есть эта косметика",
	["Cosmetic crafted"] = "Косметика создана",
	["Invalid entry"] = "Неверная запись",
	["This entry is still locked"] = "Эта запись ещё закрыта",
	["Guide skipped"] = "Обучение пропущено",
	["Invalid step"] = "Неверный шаг",
	["Step complete"] = "Шаг выполнен",
	["Finish this step first"] = "Сначала выполни этот шаг",
	-- Economy.Features.Underyard
	["Invalid Underyard progress"] = "Ошибка прогресса Поддворья",
	["Invalid Coffin Keys"] = "Ошибка ключей от гроба",
	["Invalid fragments"] = "Ошибка фрагментов",
	-- Underyard (zone)
	["You can't use the portal during a fight"] = "Во время боя портал недоступен",
	["Watch the church first"] = "Сначала загляни в церковь",
	["The Underyard is not ready yet"] = "Поддворье ещё не готово",
	["The Underyard pulled you back up"] = "Поддворье вытянуло тебя обратно",
	-- Seals (trials)
	["This trial is not ready yet"] = "Это испытание ещё не готово",
	["Unknown trial"] = "Неизвестное испытание",
	["You are already in a trial"] = "Ты уже проходишь испытание",
	["Go down to the Underyard first"] = "Сначала спустись в Поддворье",
	["This district is still sealed"] = "Этот район ещё запечатан",
	["Walk to the trial's start"] = "Подойди к началу испытания",
	["This trial is already running. Wait for it to end"] = "Это испытание уже идёт. Подожди, пока оно закончится",
	["You can't start this trial now"] = "Сейчас это испытание начать нельзя",
	["Trial over"] = "Испытание окончено",
	["Trial cleared"] = "Испытание пройдено",
	["You are not in a trial"] = "Ты не проходишь испытание",
	["Unknown trial action"] = "Неизвестное действие испытания",
	["Go to the trial's start point"] = "Иди к началу испытания",
	-- Studio debug (C2Debug)
	["Chapter II module missing"] = "Модуль главы II не найден",
	["Chapter I complete"] = "Глава I завершена",
	["The reveal will play again"] = "Открытие покажется снова",
	["Contracts finished"] = "Контракты выполнены",
	["Calendar module missing"] = "Модуль календаря не найден",
	["Finale module missing"] = "Модуль финала не найден",
	["Finale started"] = "Финал запущен",
	["Event HP module missing"] = "Модуль здоровья события не найден",
	["Event HP on"] = "Здоровье события включено",
	["Underyard module missing"] = "Модуль Поддворья не найден",
	["Descending"] = "Спуск",
	["Your dog storage is full! The dog waits in the Underyard and comes to you as soon as you make room."] =
		"Хранилище собак заполнено! Собака подождёт в Поддворье и придёт, как только освободится место.",
	["A dog from the Underyard joined your dog storage!"] = "Собака из Поддворья пришла в твоё хранилище!",
	["No dog is waiting"] = "Никакая собака не ждёт",
	["Ascending"] = "Подъём",
}

-- dynamic server messages (anchored; AutoTranslate runs every rule on every label)
L.Patterns = {
	{ "^BELL SEAL ([IVX]+) BROKEN$", "ПЕЧАТЬ КОЛОКОЛА %1 СЛОМАНА" },
	{ "^SEALED · BELL SEAL ([IVX]+)$", "ЗАПЕЧАТАНО · ПЕЧАТЬ КОЛОКОЛА %1" },
	{ "^%+(%d+) Bell Shards$", function(n)
		return "+" .. shards(n)
	end },
	{ "^%+(%d+) Coffin Keys$", function(n)
		return "+" .. keys(n)
	end },
	{ "^%+(%d+) fragments$", function(n)
		return "+" .. n .. " " .. L.Plural(tonumber(n) or 0, "фрагмент", "фрагмента", "фрагментов")
	end },
	{ "^%+(%d+) Lucky Dust$", "+%1 счастливой пыли" },
	{ "^Seals cleared: (%d+)$", "Печатей сломано: %1" },
	{ "^Offering made: seal (%d+)$", "Подношение принесено: печать %1" },
	{ "^Phase (%d+)$", "Фаза %1" },
	{ "^Guide step (%-?%d+)$", "Шаг обучения %1" },
	{ "^Rested pool (%d+)$", "Запас отдыха %1" },
	{ "^Calendar stage (%w+)$", "Стадия календаря %1" },
	{ "^Damage (%d+)$", "Урон %1" },
}

L.Phrases = {}

-- Russian of `text` (Exact, UI, then Patterns) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local exact = L.Exact[text] or L.UI[text]
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

-- a Templates entry formatted in `lang` (the Russian plural follows the first number argument)
function L.Format(key: string, lang: string?, ...: any): string
	local tpl = lang == "ru" and L.Templates[key] or nil
	if type(tpl) == "table" then
		local first = select(1, ...)
		tpl = L.Plural(tonumber(first) or 0, tpl[1], tpl[2], tpl[3])
	end
	local ok, out = pcall(string.format, tpl or key, ...)
	return ok and out or key
end

return L
