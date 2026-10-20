-- Russian strings of the DOG SHELTER (Modules.ShelterScreen, Economy.ShelterService / ShelterRules).
--   UI, Templates  self-localized window text (labels carry NoTranslate) and the ShelterPrompt texts; read only by
--                  ShelterScreen, so these words never override another screen's translation
--   Exact          server replies of the shelter that no other dictionary has (DOGROTS_AutoTranslateUI and the
--                  window's toasts); shared replies ("Unlock this dog first", "Account is busy; retry shortly"...)
--                  stay with the feature that owns them
--   Patterns       the sale message "<dog> found a new home! +<n> Coins"
-- tests/shelter_e2e.luau checks that every T("...") / F("...") of the window and every reply the server can send has
-- a Russian entry, that no Exact key repeats the base dictionary or another module, and that templates keep their
-- format specifiers.
return {
	UI = {
		-- window, list and filters
		["DOG SHELTER"] = "ПРИЮТ ДЛЯ СОБАК",
		["Find your extra dogs a new home"] = "Найди лишним собакам новый дом",
		["ALL"] = "ВСЕ",
		["SELLABLE"] = "МОЖНО ПРОДАТЬ",
		["PROTECTED"] = "ЗАЩИЩЕНЫ",
		["SELLABLE FIRST"] = "СНАЧАЛА ДОСТУПНЫЕ",
		["RARITY"] = "РЕДКОСТЬ",
		["PRICE"] = "ЦЕНА",
		["EVENT"] = "ИВЕНТ",
		["Every dog is protected"] = "Все собаки защищены",
		["NO DOGS HERE"] = "ЗДЕСЬ НЕТ СОБАК",
		["Try another filter."] = "Попробуй другой фильтр.",
		-- protection labels of the cards
		["LOCKED"] = "ЗАЩИЩЕНА",
		["FAVORITE"] = "ИЗБРАННАЯ",
		["WORKING"] = "РАБОТАЕТ",
		["IN KENNEL"] = "В БУДКЕ",
		["ON DISPLAY"] = "НА ВИТРИНЕ",
		["LISTED"] = "НА РЫНКЕ",
		["RESERVED"] = "В РЕЗЕРВЕ",
		["IN TRADE"] = "В ОБМЕНЕ",
		["UNAVAILABLE"] = "НЕДОСТУПНА",
		-- states
		["LOADING YOUR DOGS…"] = "ЗАГРУЖАЕМ ТВОИХ СОБАК…",
		["RETRYING…"] = "ПРОБУЕМ ЕЩЁ РАЗ…",
		["Asking the reception…"] = "Спрашиваем на ресепшене…",
		["COULD NOT LOAD YOUR DOGS"] = "НЕ УДАЛОСЬ ЗАГРУЗИТЬ СОБАК",
		["RETRY"] = "ПОВТОРИТЬ",
		["The shelter did not answer. Try again."] = "Приют не ответил. Попробуй ещё раз.",
		["Connection interrupted. Try again."] = "Связь прервалась. Попробуй ещё раз.",
		["NO DOGS YET"] = "ПОКА НЕТ СОБАК",
		["Adopt your first dog at the DOG LINE."] = "Возьми первую собаку на СОБАЧЬЕЙ ЛЕНТЕ.",
		["VISIT THE DOG SHELTER"] = "ЗАЙДИ В ПРИЮТ ДЛЯ СОБАК",
		["Talk to the reception inside the shelter to rehome a dog."] = "Подойди к ресепшену в приюте, чтобы найти собаке новый дом.",
		["SHOW THE WAY"] = "ПОКАЗАТЬ ПУТЬ",
		["You walked away from the Dog Shelter"] = "Приют остался позади: окно закрыто",
		-- detail panel
		["CHOOSE A DOG"] = "ВЫБЕРИ СОБАКУ",
		["Tap a dog to see what the shelter pays for it."] = "Нажми на собаку, чтобы узнать, сколько за неё заплатит приют.",
		["EVENT DOG"] = "ИВЕНТОВАЯ СОБАКА",
		["CATALOG VALUE"] = "ЦЕНА ПО КАТАЛОГУ",
		["SHELTER RATE"] = "СТАВКА ПРИЮТА",
		["BONUS"] = "БОНУС",
		["No bonus"] = "Без бонуса",
		["YOU RECEIVE"] = "ТЫ ПОЛУЧИШЬ",
		["WORTH"] = "СТОИТ",
		["The dog leaves your pack for good. Your DogDex discovery stays."] = "Собака навсегда покинет стаю. Открытие в DogDex останется.",
		["Free this dog first to rehome it."] = "Сначала освободи собаку, потом ищи ей новый дом.",
		["BACK"] = "НАЗАД",
		-- actions
		["REVIEW SALE"] = "ПРОВЕРИТЬ ПРОДАЖУ",
		["CONFIRM SALE"] = "ПОДТВЕРДИТЬ ПРОДАЖУ",
		["CANCEL"] = "ОТМЕНА",
		["REVIEW AGAIN"] = "ПРОВЕРИТЬ СНОВА",
		["PRICE EXPIRED"] = "ЦЕНА УСТАРЕЛА",
		["HOLD TO CONFIRM"] = "УДЕРЖИВАЙ ДЛЯ ПОДТВЕРЖДЕНИЯ",
		["Check the price, then confirm."] = "Проверь цену, потом подтверди.",
		["Rare dog: you will hold the button to confirm."] = "Редкая собака: для подтверждения нужно удерживать кнопку.",
		["Event dog: you will hold the button to confirm."] = "Ивентовая собака: для подтверждения нужно удерживать кнопку.",
		["NEW HOME FOUND!"] = "НОВЫЙ ДОМ НАЙДЕН!",
		-- the ShelterPrompt (localized on the client: server prompts are never auto-translated)
		["SELL EXTRA DOGS"] = "ПРОДАТЬ ЛИШНИХ СОБАК",
	},
	Templates = {
		["YOUR DOGS · %d"] = "ТВОИ СОБАКИ · %d",
		["SELLABLE %d · WORTH %s"] = "МОЖНО ПРОДАТЬ: %d · НА %s",
		["Mastery %d · Ascension %d"] = "Мастерство %d · Возвышение %d",
		["Variant +%s"] = "Вариант +%s",
		["Mastery +%s"] = "Мастерство +%s",
		["Ascension +%s"] = "Возвышение +%s",
		["Price held for %s"] = "Цена действует ещё %s",
		["+%s COINS"] = "+%s МОНЕТ",
	},
	Exact = {
		["Please wait for your profile"] = "Подожди, профиль ещё загружается",
		["Too many requests; wait a moment"] = "Слишком много запросов; подожди секунду",
		["Visit the reception inside Dog Shelter"] = "Подойди к ресепшену в приюте для собак",
		["Remove this dog from favorites first"] = "Сначала убери собаку из избранного",
		["Wait for delivery or remove this dog from work"] = "Дождись доставки или сними собаку с работы",
		["Cancel the marketplace listing first"] = "Сначала сними лот с рынка",
		["This dog cannot be rehomed right now"] = "Эту собаку сейчас нельзя отдать в приют",
		["Invalid confirmation"] = "Неверное подтверждение",
		["Confirmation expired; choose the dog again"] = "Подтверждение истекло; выбери собаку ещё раз",
		["Hold the button to confirm this sale"] = "Удерживай кнопку, чтобы подтвердить продажу",
		["Dog changed; review this dog again before selling"] = "Собака изменилась; проверь её ещё раз перед продажей",
		["Dog changed; request a new price"] = "Собака изменилась; узнай новую цену",
		["Unknown shelter action"] = "Неизвестное действие приюта",
	},
	Patterns = {
		{ "^(.+) found a new home! %+(%d+) Coins$", "%1: новый дом найден! +%2 монет" },
	},
	Phrases = {},
}
