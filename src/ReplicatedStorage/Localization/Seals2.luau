-- Russian of BELL SEALS V-VII, BELL RESONANCE and the BLACK BELL ASSAULT (ReplicatedStorage.Localization.Seals2, WP-J).
--   Exact     English replies / toasts of ServerScriptService.Halloween.SealDoors, SealChoir, SealBell and Resonance
--             (global keys for DOGROTS_AutoTranslateUI and HalloweenClient.Chapter2State.T: never repeat a key another
--             Localization module or the base dictionary has — "Please wait a moment", "Finish Chapter I first", "No
--             Crooked Door openings left today", "This district is still sealed", "Trial cleared" come from there)
--   Patterns  numbered prompt texts
--   Reasons   C2Trial "Left" / "Failed" reasons of these activities, for the presenters ({en, ru})
-- The presenters (HalloweenClient.Trials.Doors / Choir / Bell / Assault / Resonance) are self-localized (Shared.L with
-- NoTranslate labels); their shared words are in L.UI.
-- Glossary: Crooked Door = кривая дверь, THE DOORKEEPER = Привратник, hidden room = тайная комната, choir spirit = дух хора,
-- THE BELLKEEPER = Звонарь, cursed chain = проклятая цепь, Bell Resonance = резонанс колокола, RESONANT TOLL =
-- резонирующий звон, Resonant Echo = резонирующее эхо, BLACK BELL ASSAULT = штурм Чёрного колокола.
local L = {}

L.Exact = {
	-- SealDoors
	["Unknown door"] = "Неизвестная дверь",
	["Finish your trial first"] = "Сначала закончи испытание",
	["Finish your fight first"] = "Сначала закончи бой",
	["Walk up to the door"] = "Подойди к двери",
	["The door slammed shut. Your opening was returned"] = "Дверь захлопнулась. Попытка возвращена",
	["Nothing to open here"] = "Здесь нечего открывать",
	["This chest is already open"] = "Этот сундук уже открыт",
	["Open the Crooked Doors in Crooked Row"] = "Открывай кривые двери в Кривом ряду",
	["Open a Crooked Door to face it"] = "Открой кривую дверь, чтобы встретиться с этим",
	-- SealBell
	["This chain is not ringing yet"] = "Эта цепь ещё не звенит",
	["The Black Bell Assault is ringing: join it in the arena"] = "Идёт штурм Чёрного колокола: присоединяйся на арене",
	-- Resonance
	["The bell rang for you: a Coffin Key"] = "Колокол прозвонил для тебя: ключ от гроба",
	["THE BLACK BELL FALLS"] = "ЧЁРНЫЙ КОЛОКОЛ ПАЛ",
	["The bell held"] = "Колокол устоял",
	["Step into the arena to join the Assault"] = "Войди на арену, чтобы присоединиться к штурму",
	["The Black Bell is silent"] = "Чёрный колокол молчит",
	-- Studio debug (C2ResonanceDebug)
	["Resonance added"] = "Резонанс добавлен",
	["Assault started"] = "Штурм начат",
	["Assault ended"] = "Штурм окончен",
	["Resonance reset"] = "Резонанс сброшен",
	["Unknown resonance debug command"] = "Неизвестная команда отладки резонанса",
}

L.Patterns = {
	{ "^CROOKED DOOR (%d)$", "КРИВАЯ ДВЕРЬ %1" },
}

L.Phrases = {}

-- reasons a run ended (Seals reasons + this package's own)
L.Reasons = {
	LeftCourt = { "You fled the Door Court", "Ты сбежал со Двора дверей" },
	Time = { "Time is up", "Время вышло" },
	Wipe = { "Everyone was downed", "Все повержены" },
	BledOut = { "You bled out", "Ты истёк кровью" },
	LeftDistrict = { "You left the district", "Ты покинул район" },
	LeftZone = { "You left the Underyard", "Ты покинул Поддворье" },
	Died = { "You died", "Ты погиб" },
	Left = { "You left the trial", "Ты покинул испытание" },
	Abandoned = { "Everyone left", "Все ушли" },
	Ascend = { "You went up", "Ты поднялся наверх" },
	Error = { "Something went wrong", "Что-то пошло не так" },
}

-- shared words of the presenters (self-localized labels)
L.UI = {
	Outcomes = {
		Reward = { "TREASURE", "СОКРОВИЩЕ" },
		Challenge = { "CHALLENGE", "ИСПЫТАНИЕ" },
		MiniBoss = { "THE DOORKEEPER", "ПРИВРАТНИК" },
		Rare = { "HIDDEN ROOM", "ТАЙНАЯ КОМНАТА" },
	},
	OutcomeLines = {
		Reward = { "A chest waited behind the door", "За дверью ждал сундук" },
		Challenge = { "SURVIVE 25 SECONDS IN THE DOOR COURT", "ПРОДЕРЖИСЬ 25 СЕКУНД ВО ДВОРЕ ДВЕРЕЙ" },
		MiniBoss = { "Defeat the Doorkeeper", "Победи Привратника" },
		Rare = { "Open the three chests", "Открой три сундука" },
	},
	Kinds = {
		Shards = { "Bell Shards", "Осколки колокола" },
		Dust = { "Lucky Dust", "Счастливая пыль" },
		Key = { "Coffin Key", "Ключ от гроба" },
		Find = { "Showcase find", "Находка для витрины" },
		Dog = { "Event dog", "Собака события" },
		Fragments = { "Cosmetic Fragments", "Фрагменты косметики" },
		Decor = { "Plot cosmetic", "Украшение участка" },
		Skin = { "Pickaxe skin", "Скин кирки" },
		Bones = { "Bones", "Кости" },
		Cash = { "Coins", "Монеты" },
		Candy = { "Candy", "Конфеты" },
		Title = { "Title", "Титул" },
	},
	-- Russian after a number (+42 осколка колокола): {one, few, many} or one form for every count
	Counted = {
		Shards = { "осколок колокола", "осколка колокола", "осколков колокола" },
		Dust = "счастливой пыли",
		Key = { "ключ от гроба", "ключа от гроба", "ключей от гроба" },
		Fragments = { "фрагмент косметики", "фрагмента косметики", "фрагментов косметики" },
		Bones = { "кость", "кости", "костей" },
		Cash = { "монета", "монеты", "монет" },
		Candy = { "конфета", "конфеты", "конфет" },
	},
}

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
