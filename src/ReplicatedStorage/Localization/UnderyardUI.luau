-- Russian of the CHAPTER II windows and HUD (ReplicatedStorage.Localization.UnderyardUI, WP-L).
--   UI         self-localized labels (NoTranslate) of Modules.UnderyardScreen, the CHAPTER II parts of the HALLOWEEN
--              window, the DogDex "THE UNDERYARD COLLECTION" tab and the Chapter II HUD (objective line, chips, banners).
--              Read through ReplicatedStorage.Halloween.UnderyardView (UV.T: this table first, then Localization.Underyard
--              .UI, which already has the shared words: currencies, tabs, seals, districts, common buttons). Never global.
--   Templates  string.format patterns of those labels (UV.F); a value may be {one, few, many}: the Russian plural of the
--              first number argument
--   Exact      English labels other scripts show through DOGROTS_AutoTranslateUI (global keys: never repeat a key of
--              another Localization module or of the base dictionary)
--   Patterns   {luaPattern, replacement} (none: every dynamic text here is formatted by the client)
--   Dogs       the abilities of the Underyard dogs H09-H16 ({en, ru} pairs; numbers from Chapter2Config.Dogs)
-- L.Translate(text, lang) -> russian | nil (Exact, UI); L.Plural(n, one, few, many); L.Format(key, lang, ...).
-- Glossary: see Localization.Underyard (THE UNDERYARD = Поддворье, Bell Shards = осколки колокола, Coffin Key = ключ от
-- гроба, Black Coffin = Чёрный гроб, Bell Seal = печать колокола, Toll Box = Копилка звонаря, Dex II = Догдекс II,
-- THE GRAVEKEEPER = Смотритель кладбища, shrine = святилище, guide = проводник, Tailor of the Dead = Портной мёртвых).
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

L.UI = {
	-- window / header
	["UNDERYARD"] = "ПОДДВОРЬЕ",
	["CHAPTER II IS SEALED"] = "ГЛАВА II ЗАПЕЧАТАНА",
	["Finish Chapter I in the Dead Yard to break the seals below the church."] =
		"Заверши главу I на Мёртвом дворе, чтобы ломать печати под церковью.",
	["Descend through the church in the Dead Yard"] = "Спустись через церковь на Мёртвом дворе",
	["No answer from the server. Try again."] = "Сервер не ответил. Попробуй ещё раз.",
	["Something went wrong, try again"] = "Что-то пошло не так, попробуй ещё раз",
	["SHOW THE WAY"] = "ПОКАЗАТЬ ПУТЬ",
	["DETAILS"] = "ПОДРОБНЕЕ",
	["CANCEL"] = "ОТМЕНА",
	["NEW"] = "НОВОЕ",
	["MAX"] = "МАКС",
	["FREE"] = "БЕСПЛАТНО",
	["just now"] = "только что",
	-- rarity words
	["COMMON"] = "ОБЫЧНЫЙ",
	["RARE"] = "РЕДКИЙ",
	["EPIC"] = "ЭПИЧЕСКИЙ",
	["LEGENDARY"] = "ЛЕГЕНДАРНЫЙ",
	["MYTHIC"] = "МИФИЧЕСКИЙ",
	["SECRET"] = "СЕКРЕТНЫЙ",
	-- months (journal dates)
	["Jan"] = "янв",
	["Feb"] = "фев",
	["Mar"] = "мар",
	["Apr"] = "апр",
	["May"] = "мая",
	["Jun"] = "июн",
	["Jul"] = "июл",
	["Aug"] = "авг",
	["Sep"] = "сен",
	["Oct"] = "окт",
	["Nov"] = "ноя",
	["Dec"] = "дек",
	-- SEALS
	["BELL SEALS"] = "ПЕЧАТИ КОЛОКОЛА",
	["ALL DISTRICTS"] = "ВСЕ РАЙОНЫ",
	["FIRST CLEAR"] = "ПЕРВОЕ ПРОХОЖДЕНИЕ",
	["REPEAT CLEAR"] = "ПОВТОРНОЕ ПРОХОЖДЕНИЕ",
	["READY"] = "ГОТОВО",
	["BREAK THE SEAL BEFORE"] = "СНАЧАЛА ПРЕДЫДУЩАЯ",
	["IN A TRIAL"] = "ИДЁТ ИСПЫТАНИЕ",
	["PLAY AGAIN"] = "ИГРАТЬ СНОВА",
	["TO THE DOORS"] = "К ДВЕРЯМ",
	["New seals open by date. Older trials, contracts and coffins are always open."] =
		"Новые печати открываются по датам. Прошлые испытания, контракты и гробы открыты всегда.",
	["Earn Bell Shards: contracts, echoes, trials, the Gravekeeper and the Toll Box."] =
		"Зарабатывай осколки колокола: контракты, эхо, испытания, Смотритель кладбища и Копилка звонаря.",
	["Your guide pays this first offering."] = "Это первое подношение оплатит твой проводник.",
	["The altars stand in Bell Square, below the church."] = "Алтари стоят на Колокольной площади, под церковью.",
	["Every seal is open. The Last Bell waits."] = "Все печати открыты. Последний колокол ждёт.",
	["THE LAST BELL IS SILENT"] = "ПОСЛЕДНИЙ КОЛОКОЛ МОЛЧИТ",
	["Contracts, coffins and the Gravekeeper still wait below"] = "Внизу всё ещё ждут контракты, гробы и Смотритель кладбища",
	["Open the Crooked Doors in Crooked Row"] = "Открывай кривые двери в Кривом ряду",
	["no wrong answers"] = "без ошибок",
	["never downed"] = "ни разу не упасть",
	["nobody bleeds out"] = "никто не погиб",
	-- CONTRACTS
	["IN PROGRESS"] = "В ПРОЦЕССЕ",
	["ALL CONTRACTS DONE"] = "ВСЕ КОНТРАКТЫ ВЫПОЛНЕНЫ",
	["Claim all three contracts of the day: 1 Coffin Key and one more Crooked Door opening today."] =
		"Забери все три контракта дня: 1 ключ от гроба и ещё одно открытие кривой двери сегодня.",
	["FULL FOR TODAY"] = "НА СЕГОДНЯ ВСЁ",
	["NOT ENOUGH CANDY"] = "МАЛО КОНФЕТ",
	["BELL SHARDS TODAY"] = "ОСКОЛКИ КОЛОКОЛА СЕГОДНЯ",
	-- COFFIN
	["BELL SQUARE · THE SHRINE"] = "КОЛОКОЛЬНАЯ ПЛОЩАДЬ · СВЯТИЛИЩЕ",
	["BLACK COFFIN"] = "ЧЁРНЫЙ ГРОБ",
	["Keys come from the daily contract bonus, every Bell Seal (and its Gold), the Gravekeeper III-V, Bell Resonance, Crooked Doors and the Dex II. Never sold."] =
		"Ключи дают бонус за ежедневные контракты, каждая печать колокола (и её золото), Смотритель кладбища III-V, резонанс колокола, кривые двери и Догдекс II. Никогда не продаются.",
	["Exact chances of one opening. Duplicates convert into fragments, Lucky Dust or shards."] =
		"Точные шансы одного открытия. Дубликаты превращаются во фрагменты, счастливую пыль или осколки.",
	["DUPLICATES"] = "ДУБЛИКАТЫ",
	["No coffin opened yet."] = "Ты ещё не открывал гроб.",
	["THE COFFIN OPENS"] = "ГРОБ ОТКРЫВАЕТСЯ",
	["NEED A COFFIN KEY"] = "НУЖЕН КЛЮЧ ОТ ГРОБА",
	["Claim all three contracts today for a key, or break a seal."] = "Забери все три контракта сегодня ради ключа или сломай печать.",
	["The shrine stands in Bell Square, below the church."] = "Святилище стоит на Колокольной площади, под церковью.",
	["Walk up to the shrine to open the coffin."] = "Подойди к святилищу, чтобы открыть гроб.",
	["OPEN THE COFFIN"] = "ОТКРОЙ ГРОБ",
	-- DEX II
	["THE UNDERYARD COLLECTION"] = "КОЛЛЕКЦИЯ ПОДДВОРЬЯ",
	["Eight dogs live below the last bell: seals, the Black Coffin, the Gravekeeper's last stand and one hidden room hold them."] =
		"Под последним колоколом живут восемь собак: их хранят печати, Чёрный гроб, последний бой Смотрителя кладбища и одна тайная комната.",
	["OPEN DOGDEX"] = "ОТКРЫТЬ ДОГДЕКС",
	["DEX II MILESTONES"] = "ЭТАПЫ ДОГДЕКСА II",
	["DEX II REWARD"] = "НАГРАДА ДОГДЕКСА II",
	["A secret of the Underyard. Only a crowned few ever see it."] = "Тайна Поддворья. Её видят лишь немногие коронованные.",
	["DISCOVERED"] = "НАЙДЕН",
	["NOT FOUND YET"] = "ЕЩЁ НЕ НАЙДЕН",
	["WHERE TO FIND IT"] = "ГДЕ НАЙТИ",
	-- COLLECTION
	["PICKAXE SKINS"] = "СКИНЫ КИРОК",
	["PLOT COSMETICS"] = "КОСМЕТИКА УЧАСТКА",
	["SHOWCASE FINDS"] = "НАХОДКИ ДЛЯ ВИТРИНЫ",
	["SEW IT?"] = "СШИТЬ?",
	["SEWN FOR YOU"] = "СШИТО ДЛЯ ТЕБЯ",
	["The Black Coffin and the Crooked Doors. A duplicate turns into shards and Lucky Dust."] =
		"Чёрный гроб и кривые двери. Дубликат превращается в осколки и счастливую пыль.",
	["A large plot cosmetic with its own idle animation."] = "Большая косметика для участка с собственной анимацией.",
	["A small plot cosmetic with its own idle animation."] = "Маленькая косметика для участка с собственной анимацией.",
	["The Black Coffin, Bell Seals, the Dex II or the Tailor of the Dead."] = "Чёрный гроб, печати колокола, Догдекс II или Портной мёртвых.",
	["A pickaxe skin only changes the look: every stat still comes from your real pickaxe."] =
		"Скин кирки меняет только внешний вид: все характеристики по-прежнему берутся от твоей настоящей кирки.",
	["Only the Dex II gives it: find all eight Underyard dogs."] = "Его даёт только Догдекс II: найди всех восьми собак Поддворья.",
	["The Black Coffin, the Dex II, the Gravekeeper's last stand or the Tailor of the Dead."] =
		"Чёрный гроб, Догдекс II, последний бой Смотрителя кладбища или Портной мёртвых.",
	["OWNED"] = "ЕСТЬ",
	["IN YOUR COLLECTION"] = "В ТВОЕЙ КОЛЛЕКЦИИ",
	["MISSING"] = "НЕТ",
	["DEX II 8 / 8"] = "ДОГДЕКС II 8 / 8",
	["DEX II ONLY"] = "ТОЛЬКО ДОГДЕКС II",
	-- JOURNAL
	["EVENT JOURNAL"] = "ЖУРНАЛ СОБЫТИЯ",
	["Every story beat of both chapters. Replays never change your progress."] =
		"Все сюжетные моменты обеих глав. Повторы никогда не меняют твой прогресс.",
	["Go to the Haunted Cauldron in the Dead Yard to replay the brew"] = "Подойди к котлу с привидениями на Мёртвом дворе, чтобы повторить варево",
}

L.Templates = {
	-- objective line / header
	["Finish Chapter I: %d / %d"] = "Заверши главу I: %d / %d",
	["GUIDE %d / %d"] = "ОБУЧЕНИЕ %d / %d",
	["Opens in %s"] = "Откроется через %s",
	["Offer at Altar %s: the guide pays it"] = "Подношение у алтаря %s: платит проводник",
	["Offer %d Bell Shards at Altar %s"] = { "Принеси %d осколок колокола к алтарю %s", "Принеси %d осколка колокола к алтарю %s",
		"Принеси %d осколков колокола к алтарю %s" },
	["Earn %d more Bell Shards for the offering"] = { "Заработай ещё %d осколок колокола на подношение",
		"Заработай ещё %d осколка колокола на подношение", "Заработай ещё %d осколков колокола на подношение" },
	["Begin the trial: %s"] = "Начни испытание: %s",
	["Break Bell Seal %s"] = "Сломай печать колокола %s",
	-- seals
	["ALTAR %s"] = "АЛТАРЬ %s",
	["BREAK SEAL %s FIRST"] = "СНАЧАЛА ПЕЧАТЬ %s",
	["NEED %s MORE"] = "НУЖНО ЕЩЁ %s",
	["Time limit %s · party up to %d"] = "Лимит времени %s · отряд до %d",
	["The trial starts at %s"] = "Начало испытания: %s",
	["+%d COFFIN KEYS"] = { "+%d КЛЮЧ ОТ ГРОБА", "+%d КЛЮЧА ОТ ГРОБА", "+%d КЛЮЧЕЙ ОТ ГРОБА" },
	["BELL SEAL %s opens in %s"] = "ПЕЧАТЬ КОЛОКОЛА %s откроется через %s",
	["Bell Shards today: %d%% efficiency"] = "Осколки колокола сегодня: эффективность %d%%",
	["%d more at this rate"] = "ещё %d по этой ставке",
	["rested %d"] = "отдых %d",
	["%d objectives"] = { "%d задание", "%d задания", "%d заданий" },
	["%d%% Perfect"] = "%d%% идеальных",
	["within %s"] = "за %s",
	-- contracts / Toll Box
	["%s / %s"] = "%s / %s",
	["Every contract pays %d Bell Shards at full value, even on a busy day."] = {
		"Каждый контракт даёт %d осколок колокола по полной цене, даже в насыщенный день.",
		"Каждый контракт даёт %d осколка колокола по полной цене, даже в насыщенный день.",
		"Каждый контракт даёт %d осколков колокола по полной цене, даже в насыщенный день." },
	["%d Moon Candy buys 1 Bell Shard. Up to %d shards a day, never less after a busy day."] = {
		"%d лунная конфета = 1 осколок колокола. До %d осколков в день, даже после насыщенного дня.",
		"%d лунные конфеты = 1 осколок колокола. До %d осколков в день, даже после насыщенного дня.",
		"%d лунных конфет = 1 осколок колокола. До %d осколков в день, даже после насыщенного дня." },
	["%d Candy · you have %s"] = { "%d конфета · у тебя %s", "%d конфеты · у тебя %s", "%d конфет · у тебя %s" },
	["%d earned today"] = "сегодня заработано: %d",
	["The first %d shards of a day count in full, the next %d at 35%%, the rest at 10%%. Contracts, first clears and the Toll Box are never reduced."] =
		"Первые %d осколков за день идут полностью, следующие %d — по 35%%, остальные — по 10%%. Контракты, первые прохождения и Копилка звонаря никогда не урезаются.",
	-- coffin
	["Open it at the shrine for %d Bell Shards and %d Coffin Key. Every chance is shown below; duplicates are converted, never wasted."] = {
		"Открой его у святилища за %d осколок колокола и %d ключ от гроба. Все шансы указаны ниже; дубликаты обмениваются, а не пропадают.",
		"Открой его у святилища за %d осколка колокола и %d ключ от гроба. Все шансы указаны ниже; дубликаты обмениваются, а не пропадают.",
		"Открой его у святилища за %d осколков колокола и %d ключ от гроба. Все шансы указаны ниже; дубликаты обмениваются, а не пропадают." },
	["Plot cosmetic you own: %d fragments + %d Lucky Dust. Pickaxe skin you own: %d fragments + %d Lucky Dust. Showcase find you own: %d Bell Shards + %d Lucky Dust. Dogs are always dogs."] =
		"Повтор косметики участка: фрагменты %d + счастливая пыль %d. Повтор скина кирки: фрагменты %d + счастливая пыль %d. Повтор находки для витрины: осколки колокола %d + счастливая пыль %d. Собаки всегда остаются собаками.",
	["Coffins opened: %d"] = "Открыто гробов: %d",
	["%d min ago"] = "%d мин назад",
	["%d h ago"] = "%d ч назад",
	["1 in %s"] = "1 из %s",
	["TOTAL %s"] = "ВСЕГО %s",
	-- dex II / collection
	["%d UNDERYARD DOGS FOUND"] = { "НАЙДЕНА %d СОБАКА ПОДДВОРЬЯ", "НАЙДЕНО %d СОБАКИ ПОДДВОРЬЯ", "НАЙДЕНО %d СОБАК ПОДДВОРЬЯ" },
	["Fragments from duplicates and the Black Coffin buy any plot cosmetic for %d and any pickaxe skin for %d. The Tailor never sews the Dex II secret skin."] =
		"Фрагменты из дубликатов и Чёрного гроба обмениваются на любую косметику участка за %d и любой скин кирки за %d. Секретный скин Догдекса II Портной не шьёт.",
	["Need %d more fragments"] = { "Нужен ещё %d фрагмент", "Нужно ещё %d фрагмента", "Нужно ещё %d фрагментов" },
	["THE TAILOR OF THE DEAD sews %s for %d fragments. You keep it forever."] = {
		"ПОРТНОЙ МЁРТВЫХ сошьёт: %s за %d фрагмент. Это останется у тебя навсегда.",
		"ПОРТНОЙ МЁРТВЫХ сошьёт: %s за %d фрагмента. Это останется у тебя навсегда.",
		"ПОРТНОЙ МЁРТВЫХ сошьёт: %s за %d фрагментов. Это останется у тебя навсегда." },
	["CRAFT · %d FRAGMENTS"] = { "СОЗДАТЬ · %d ФРАГМЕНТ", "СОЗДАТЬ · %d ФРАГМЕНТА", "СОЗДАТЬ · %d ФРАГМЕНТОВ" },
}

-- labels other scripts show through DOGROTS_AutoTranslateUI (global keys)
L.Exact = {}

L.Patterns = {}
L.Phrases = {}

-- the abilities of the Underyard dogs (Chapter2Config.Dogs: EchoLifeBonus, TelegraphLead, ...)
L.Dogs = {
	HW_BellPup = {
		Ability = { "Echo Ear", "Эхо-ушко" },
		Text = { "Echo points live 4 s longer and the next echo jump target pulses.",
			"Точки эха живут на 4 с дольше, а следующая цель прыжка эха пульсирует." },
	},
	HW_CandleCorgi = {
		Ability = { "Candlelight", "Свет свечи" },
		Text = { "Hazard warnings reach you 0.35 s earlier (Hollow Mine, trials, the boss) and mine gas deals 30% less.",
			"Предупреждения об опасности приходят на 0,35 с раньше (Полая шахта, испытания, босс), а газ шахты наносит на 30% меньше." },
	},
	HW_MourningShiba = {
		Ability = { "Mourning Veil", "Траурная вуаль" },
		Text = { "Once per fight you get back up by yourself after 8 s downed; allies revive you 40% faster.",
			"Раз за бой ты сам поднимаешься через 8 с после падения; союзники поднимают тебя на 40% быстрее." },
	},
	HW_CoffinPug = {
		Ability = { "Coffin Sense", "Чутьё на гробы" },
		Text = { "8% chance a Black Coffin gives a bonus showcase-find roll; duplicate conversions give 25% more.",
			"8% шанс, что Чёрный гроб даст дополнительную попытку на находку для витрины; обмен дубликатов даёт на 25% больше." },
	},
	HW_MothHound = {
		Ability = { "Moth Swarm", "Рой мотыльков" },
		Text = { "35% chance moths mark the reward Crooked Door; shows the nearest choir spirit.",
			"35% шанс, что мотыльки отметят наградную кривую дверь; показывает ближайшего духа хора." },
	},
	HW_Bridehound = {
		Ability = { "Eternal Vow", "Вечная клятва" },
		Text = { "+15 max Event HP; you revive allies twice as fast and an ally you revive gets a 20 HP shield.",
			"+15 к максимуму здоровья события; ты поднимаешь союзников вдвое быстрее, а поднятый союзник получает щит на 20 здоровья." },
	},
	HW_BellkeeperWolf = {
		Ability = { "Resonant Howl", "Резонирующий вой" },
		Text = { "Your Perfect hits count twice for Bell Resonance and deal 25% more to chains, bells and weak points.",
			"Твои идеальные удары засчитываются в резонанс колокола дважды и наносят на 25% больше цепям, колоколам и слабым местам." },
	},
	HW_HollowKing = {
		Ability = { "Crown of the Underyard", "Корона Поддворья" },
		Text = { "Every 20 active minutes in the Underyard your next Black Coffin gets one extra showcase-find roll. A royal violet aura.",
			"Каждые 20 активных минут в Поддворье твой следующий Чёрный гроб получает дополнительную попытку на находку для витрины. Королевская фиолетовая аура." },
	},
}

-- Russian of `text` (Exact, UI) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	return L.Exact[text] or L.UI[text]
end

-- a Templates entry formatted in `lang` (the Russian plural follows the first number argument)
function L.Format(key: string, lang: string?, ...: any): string
	local tpl: any = lang == "ru" and L.Templates[key] or nil
	if type(tpl) == "table" then
		local n = 0
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "number" then
				n = v
				break
			end
		end
		tpl = L.Plural(n, tpl[1], tpl[2], tpl[3])
	end
	local ok, out = pcall(string.format, tpl or key, ...)
	return ok and out or key
end

return L
