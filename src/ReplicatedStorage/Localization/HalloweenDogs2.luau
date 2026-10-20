-- Russian strings of THE UNDERYARD event dogs H09-H16 (ReplicatedStorage.Localization.HalloweenDogs2, WP-K1).
--   UI, Templates   self-localized text for the second event dex page "EVENT · THE UNDERYARD 2026" (DogdexScreen /
--                   the Underyard window read them like Localization.HalloweenDogs); never global
--   Exact           for DOGROTS_AutoTranslateUI: dog names and signatures (cards, name probes, entry window, MY DOGS,
--                   KENNEL, TRADE...), the Hollow King's Secret arrival (whispers, title, banner kicker, venue lines)
--   Patterns        the island-wide banner kicker that names the player who raised the Hollow King
-- Glossary (shared with Localization.Underyard): THE UNDERYARD = Поддворье, Black Coffin = Чёрный гроб, Crooked Door =
-- Кривая дверь, choir spirit = дух хора, Resonance = Резонанс, Event HP = HP события, Bell Shards = осколки колокола.
-- Never repeat an Exact key another Localization module (or the AutoTranslate base dictionary) already has.
return {
	UI = {
		["EVENT · THE UNDERYARD 2026"] = "СОБЫТИЕ · ПОДДВОРЬЕ 2026",
		["THE UNDERYARD 2026"] = "ПОДДВОРЬЕ 2026",
		["THE UNDERYARD · event dogs"] = "ПОДДВОРЬЕ · собаки события",
		["THE UNDERYARD COLLECTION"] = "КОЛЛЕКЦИЯ ПОДДВОРЬЯ",
		["Bell Seals, the Black Coffin, the Crooked Doors and the Last Bark bring them"] =
			"Их приносят печати колокола, Чёрный гроб, Кривые двери и Последний лай",
	},
	Templates = {
		["Event dog · THE UNDERYARD 2026 · #%02d of %d"] = "Собака события · ПОДДВОРЬЕ 2026 · №%02d из %d",
	},
	Exact = {
		-- names
		["Bell Pup"] = "Колокольчик",
		["Candle Corgi"] = "Свечной корги",
		["Mourning Shiba"] = "Скорбная шиба",
		["Coffin Pug"] = "Гробовой мопс",
		["Moth Hound"] = "Мотыльковая гончая",
		["Bridehound"] = "Невеста-гончая",
		["Bellkeeper Wolf"] = "Волк-звонарь",
		["Hollow King"] = "Полый король",
		-- signatures (exact English of DogDefinitions)
		["ECHO EAR: echo points last 4 s longer and the next echo jump target pulses."] =
			"ЭХО-УХО: точки эха живут на 4 с дольше, а цель следующего прыжка эха пульсирует.",
		["CANDLELIGHT: hazard warnings reach you 0.35 s earlier and mine gas hurts 30% less."] =
			"СВЕТ СВЕЧИ: предупреждения об опасности появляются на 0,35 с раньше, а газ в шахте ранит на 30% слабее.",
		["MOURNING VEIL: once per fight you rise again after 8 s downed; revives on you are 40% faster."] =
			"СКОРБНАЯ ВУАЛЬ: раз за бой ты сам поднимаешься через 8 с после падения; тебя воскрешают на 40% быстрее.",
		["COFFIN SENSE: 8% chance a Black Coffin rolls a bonus showcase find; duplicate conversions give 25% more."] =
			"ЧУТЬЁ ГРОБА: 8% шанс, что Чёрный гроб даст бонусную находку для витрины; обмен дубликатов даёт на 25% больше.",
		["MOTH SWARM: 35% chance moths mark the reward Crooked Door; shows you the nearest choir spirit."] =
			"РОЙ МОТЫЛЬКОВ: 35% шанс, что мотыльки отметят Кривую дверь с наградой; показывает ближайшего духа хора.",
		["ETERNAL VOW: +15 max Event HP; you revive allies twice as fast and they rise with a 20 HP shield."] =
			"ВЕЧНАЯ КЛЯТВА: +15 к макс. HP события; ты воскрешаешь союзников вдвое быстрее, и они встают со щитом на 20 HP.",
		["RESONANT HOWL: your Perfect hits count double for Resonance and deal 25% more to chains, bells and weak points."] =
			"РЕЗОНИРУЮЩИЙ ВОЙ: твои идеальные удары считаются за два для Резонанса и наносят на 25% больше цепям, колоколам и слабым местам.",
		["CROWN OF THE UNDERYARD: every 20 active minutes in the Underyard your next Black Coffin rolls one extra showcase find."] =
			"КОРОНА ПОДДВОРЬЯ: каждые 20 активных минут в Поддворье твой следующий Чёрный гроб даёт ещё одну находку для витрины.",
		["Event dog · THE UNDERYARD 2026"] = "Собака события · ПОДДВОРЬЕ 2026",
		-- the Hollow King's Secret arrival (SecretArrivalConfig + SecretArrivals Dogs/Mega HW_HollowKing)
		["HOLLOW KING"] = "ПОЛЫЙ КОРОЛЬ",
		["the last bell has stopped ringing."] = "последний колокол умолк.",
		["something hollow wears the crown now."] = "теперь корону носит что-то пустое.",
		["✦  THE HOLLOW KING RISES  ✦"] = "✦  ПОЛЫЙ КОРОЛЬ ВОССТАЛ  ✦",
		["FROM THE BLACK COFFIN"] = "ИЗ ЧЁРНОГО ГРОБА",
		["BEHIND A CROOKED DOOR"] = "ЗА КРИВОЙ ДВЕРЬЮ",
		["AFTER THE LAST BARK"] = "ПОСЛЕ ПОСЛЕДНЕГО ЛАЯ",
		["IN THE UNDERYARD"] = "В ПОДДВОРЬЕ",
	},
	Patterns = {
		{ "^✦  (.+) RAISED THE HOLLOW KING  ✦$", "✦  %1 ПРОБУДИЛ ПОЛОГО КОРОЛЯ  ✦" },
	},
	Phrases = {},
}
