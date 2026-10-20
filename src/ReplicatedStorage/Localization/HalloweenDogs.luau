-- Russian strings of the NIGHT OF THE BURIED MOON event dogs (ReplicatedStorage.Localization.HalloweenDogs, WP4).
--   UI, Templates   self-localized text of the DOGDEX event tab "EVENT · BURIED MOON 2026" (Modules.DogdexScreen reads
--                   them after Localization.Dogs); never global
--   Exact           for DOGROTS_AutoTranslateUI: dog names and signatures (cards, name probes, entry window, MY DOGS,
--                   KENNEL, TRADE...), the Eclipse Dog's secret-arrival whispers and title
-- Event mutation names (HAUNTED, ECLIPSED ...) belong to Localization.HalloweenItems (WP5); event UI to
-- Localization.Halloween (WP9). Never repeat an Exact key another Localization module already has.
return {
	UI = {
		["EVENT · BURIED MOON 2026"] = "СОБЫТИЕ · ПОГРЕБЁННАЯ ЛУНА 2026",
		["BURIED MOON 2026"] = "ПОГРЕБЁННАЯ ЛУНА 2026",
		["NIGHT OF THE BURIED MOON · event dogs"] = "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ · собаки события",
		["NIGHT OF THE BURIED MOON"] = "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ",
		["The event is over"] = "Событие завершилось",
		["The event is over. Event dogs can still be traded."] = "Событие завершилось. Собак события всё ещё можно выменять.",
		["Pumpkin Lucky Blocks, the Haunted Cauldron and the Gravekeeper drop them"] = "Их дают тыквенные счастливые блоки, Котёл с привидениями и Смотритель кладбища",
		["Reward claimed!"] = "Награда получена!",
		["EVENT OVER"] = "КОНЕЦ СОБЫТИЯ",
		["Pumpkin Lucky Block"] = "Тыквенный счастливый блок",
		["Cursed Pumpkin Lucky Block"] = "Проклятый тыквенный счастливый блок",
		["Pumpkin Lucky Blocks"] = "Тыквенные счастливые блоки",
		["Cursed Pumpkins"] = "Проклятые тыквы",
		["Haunted Cauldron"] = "Котёл с привидениями",
		["The Gravekeeper"] = "Смотритель кладбища",
		["Event rewards in the Dead Yard"] = "Награды события на Мёртвом дворе",
		["BURIED MOON SURVIVOR"] = "ПЕРЕЖИВШИЙ ПОГРЕБЁННУЮ ЛУНУ",
		["Grave Shovel"] = "Могильная лопата",
		["Bone Pickaxe"] = "Костяная кирка",
		["Pumpkin Smasher"] = "Тыквенный крушитель",
		["Ghost Scythe"] = "Призрачная коса",
		["Living Coffin"] = "Живой гроб",
		["Soul Reaper"] = "Жнец душ",
	},
	Templates = {
		["🍬 %d Candy"] = "🍬 %d конфет",
		["⛏ %s skin"] = "⛏ скин «%s»",
		["BURIED MOON reward for %d dogs: %s"] = "Награда ПОГРЕБЁННОЙ ЛУНЫ за %d собак: %s",
		["%d / %d DISCOVERED"] = "ОТКРЫТО %d ИЗ %d",
		["Event dog · BURIED MOON 2026 · #%02d of %d"] = "Собака события · ПОГРЕБЁННАЯ ЛУНА 2026 · №%02d из %d",
	},
	Exact = {
		-- names
		["Pumpkin Pup"] = "Тыквенный щенок",
		["Sheet Shiba"] = "Шиба в простыне",
		["Bone Corgi"] = "Корги-скелет",
		["Frankenpug"] = "Франкенмопс",
		["Bat Dachshund"] = "Такса-летучая мышь",
		["Plague Pug"] = "Чумной мопс",
		["Headless Hound"] = "Безголовая гончая",
		["Eclipse Dog"] = "Пёс затмения",
		-- signatures (exact English of DogDefinitions / Halloween Config)
		["+20% Candy from Pumpkin Patch dig spots."] = "+20% конфет с тыквенных мест раскопок.",
		["Can find Ghost Loot: haunted finds at Ghost Soil and in the yard."] = "Находит призрачную добычу: призрачные находки на Призрачной почве и во дворе.",
		["+35% Bones from digs and Bone Graves. Falls apart and rebuilds itself."] = "+35% костей с раскопок и Костяных могил. Рассыпается и собирается обратно.",
		["OVERCHARGE: every 5 digs it supercharges and digs 60% faster for 40 s."] = "ПЕРЕЗАРЯД: каждые 5 раскопок заряжается и 40 с копает на 60% быстрее.",
		["After a find it flies straight to the next dig: +40% speed on the next dig and dig spots start damaged."] = "После находки летит прямо к следующей раскопке: +40% скорости следующей раскопки, а места раскопок начинаются повреждёнными.",
		["Strongly raises the mutation chance of its finds and slightly for the whole team."] = "Сильно повышает шанс мутации своих находок и немного — всей команде.",
		["Finds Headless Treasure: bonus coin caches on digs, double Cursed Treasure chance."] = "Находит Безголовый клад: тайники с монетами при раскопках и двойной шанс Проклятого сокровища.",
		["Rarely turns a find into ECLIPSED (x20 value)."] = "Изредка превращает находку в ЗАТМЕНИЕ (ценность x20).",
		-- the Eclipse Dog's secret arrival (SecretArrivalConfig)
		["ECLIPSE DOG"] = "ПЁС ЗАТМЕНИЯ",
		["the moon went out."] = "луна погасла.",
		["something black is standing where it fell."] = "там, где она упала, стоит что-то чёрное.",
	},
	Patterns = {},
	Phrases = {},
}
