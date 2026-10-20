-- Russian of NIGHT OF THE BURIED MOON (ReplicatedStorage.Localization.Halloween, WP9).
--   UI         self-localized labels (NoTranslate) of the Halloween window, HUD, banners, onboarding and the Dead Yard's
--              server prompts; read by Modules.HalloweenScreen and HalloweenClient.HUD / Onboarding. Never global.
--   Templates  string.format patterns of those labels; a value may be {one, few, many} (Russian plural of the first number)
--   Exact      English server messages (Core / Actions / Exorcism / World / Houses / Boss / Debug replies, toasts) and the
--              legacy labels this event adds; DOGROTS_AutoTranslateUI loads them for every label in the game (global keys:
--              never repeat a key another Localization module has: HalloweenItems owns the block / mutation words,
--              HalloweenDogs the dog names and signatures, Navigation the destination names)
--   Patterns   {luaPattern, replacement} for server messages with numbers / names (AutoTranslate runs them in order)
-- L.Translate(text, lang) -> russian | nil (Exact, UI, then Patterns); L.Plural(n, one, few, many).
-- Glossary (shared with the other event modules): Candy = конфеты, Moon Candy = лунные конфеты, Curse = проклятие, Blood Moon =
-- Кровавая Луна, Candy Rush = конфетная лихорадка, Exorcism = экзорцизм, souls = души, THE DEAD YARD = Мёртвый двор,
-- Haunted Cauldron = котёл с привидениями, TRICK / TREAT = гадость / сладость, THE GRAVEKEEPER = Смотритель кладбища,
-- Grave Bell = могильный колокол, Pumpkin Lucky Block = тыквенный счастливый блок, Cursed Pumpkin = проклятая тыква,
-- Haunted Dig Spots = проклятые раскопки, Cursed Treasure = проклятый клад, Event DogDex = Догдекс события.
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
local function candies(n: any): string
	local k = tonumber(n) or 0
	return tostring(n) .. " " .. L.Plural(k, "конфета", "конфеты", "конфет")
end

L.UI = {
	-- window
	["NIGHT OF THE BURIED MOON"] = "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ",
	["BURIED MOON"] = "ПОГРЕБЁННАЯ ЛУНА",
	["THE DEAD YARD · candy, curses and the Blood Moon"] = "МЁРТВЫЙ ДВОР · конфеты, проклятия и Кровавая Луна",
	["EVENT"] = "СОБЫТИЕ",
	["QUESTS"] = "ЗАДАНИЯ",
	["EVENT DOGDEX"] = "ДОГДЕКС СОБЫТИЯ",
	["CAULDRON"] = "КОТЁЛ",
	["HALLOWEEN"] = "ХЭЛЛОУИН",
	["BOSS"] = "БОСС",
	["COSMETICS"] = "КОСМЕТИКА",
	["The Night of the Buried Moon has ended"] = "Ночь Погребённой Луны закончилась",
	["Something went wrong, try again"] = "Что-то пошло не так, попробуй ещё раз",
	-- EVENT tab
	["HALLOWEEN EVENT"] = "СОБЫТИЕ ХЭЛЛОУИНА",
	["THE DEAD YARD"] = "МЁРТВЫЙ ДВОР",
	["Dig haunted graves, mine moon ore, knock on 7 cursed doors and feed the cauldron. Stay active: the curse rises when you idle."] =
		"Раскапывай проклятые могилы, добывай лунную руду, стучи в 7 проклятых дверей и корми котёл. Не стой на месте: проклятие растёт, пока ты бездельничаешь.",
	["SHOW THE WAY"] = "ПОКАЗАТЬ ПУТЬ",
	["HOW TO PLAY"] = "КАК ИГРАТЬ",
	["YOU ARE IN THE DEAD YARD"] = "ТЫ НА МЁРТВОМ ДВОРЕ",
	["BLOOD MOON"] = "КРОВАВАЯ ЛУНА",
	["+50% CANDY"] = "+50% КОНФЕТ",
	["HAUNTED DIG SPOTS"] = "ПРОКЛЯТЫЕ РАСКОПКИ",
	["BLOOD MOON FINDS"] = "НАХОДКИ КРОВАВОЙ ЛУНЫ",
	["RISES IN"] = "ВЗОЙДЁТ ЧЕРЕЗ",
	["THE BLOOD MOON IS UP! ENDS IN"] = "КРОВАВАЯ ЛУНА ВЗОШЛА! КОНЕЦ ЧЕРЕЗ",
	["THE BLOOD MOON FADES"] = "КРОВАВАЯ ЛУНА МЕРКНЕТ",
	["NEXT BLOOD MOON IN"] = "СЛЕДУЮЩАЯ КРОВАВАЯ ЛУНА ЧЕРЕЗ",
	["SERVER EXORCISM"] = "ЭКЗОРЦИЗМ СЕРВЕРА",
	["Every candy and every objective in the Dead Yard banishes souls. Milestones help the whole server."] =
		"Каждая конфета и каждое задание на Мёртвом дворе изгоняют души. Этапы помогают всему серверу.",
	["SERVER CANDY RUSH"] = "ЛИХОРАДКА СЕРВЕРА",
	["PUMPKIN BLOCK FOR ALL"] = "ТЫКВЕННЫЙ БЛОК ВСЕМ",
	["MUTATIONS x2"] = "МУТАЦИИ x2",
	["THE GRAVEKEEPER"] = "СМОТРИТЕЛЬ КЛАДБИЩА",
	["MOON CANDY"] = "ЛУННЫЕ КОНФЕТЫ",
	["CURSE"] = "ПРОКЛЯТИЕ",
	["Idling in the Dead Yard raises the curse. Above 80% you earn less candy. Dig, mine and fight to lift it."] =
		"Безделье на Мёртвом дворе усиливает проклятие. Выше 80% конфет становится меньше. Копай, добывай руду и сражайся, чтобы снять его.",
	["CANDY RUSH x2"] = "КОНФЕТНАЯ ЛИХОРАДКА x2",
	["Double candy for 10 minutes of active play. Once a day."] = "Двойные конфеты на 10 минут активной игры. Раз в день.",
	["START RUSH"] = "ЗАПУСТИТЬ",
	["CANDY RUSH x2 STARTED"] = "КОНФЕТНАЯ ЛИХОРАДКА x2 ЗАПУЩЕНА",
	["TONIGHT"] = "ЭТОЙ НОЧЬЮ",
	["HALLOWEEN DECOR ON THE MAIN MAP"] = "УКРАШЕНИЯ ХЭЛЛОУИНА НА КАРТЕ",
	["ON"] = "ВКЛ",
	["OFF"] = "ВЫКЛ",
	["COINS"] = "МОНЕТЫ",
	["LUCK BOOST"] = "БУСТ УДАЧИ",
	-- the reward card (claims: event DogDex collection, the cauldron brew, the daily bonus)
	["YOU GOT"] = "ТВОЯ НАГРАДА",
	["BONES"] = "КОСТИ",
	["LUCKY BLOCK"] = "СЧАСТЛИВЫЙ БЛОК",
	["PICKAXE SKIN"] = "СКИН КИРКИ",
	["EVENT DOG"] = "ПЁС СОБЫТИЯ",
	["YARD DECOR"] = "ДЕКОР ДВОРА",
	["MUTATION"] = "МУТАЦИЯ",
	["NEW TITLE"] = "НОВЫЙ ТИТУЛ",
	["COLLECT"] = "ЗАБРАТЬ",
	["Tap to skip"] = "Нажми, чтобы пропустить",
	["COLLECTION REWARD"] = "НАГРАДА ЗА КОЛЛЕКЦИЮ",
	["ALL QUESTS DONE"] = "ВСЕ ЗАДАНИЯ ВЫПОЛНЕНЫ",
	-- QUESTS tab
	["DAILY QUESTS"] = "ЕЖЕДНЕВНЫЕ ЗАДАНИЯ",
	["ALL QUESTS BONUS"] = "БОНУС ЗА ВСЕ ЗАДАНИЯ",
	["CLAIM"] = "ЗАБРАТЬ",
	["CLAIMED"] = "ПОЛУЧЕНО",
	["IN PROGRESS"] = "В ПРОЦЕССЕ",
	["QUEST REWARD"] = "НАГРАДА ЗА ЗАДАНИЕ",
	["DAILY BONUS"] = "ЕЖЕДНЕВНЫЙ БОНУС",
	["Loading quests..."] = "Загружаем задания...",
	["QUEST DONE"] = "ЗАДАНИЕ ВЫПОЛНЕНО",
	["Participate in a Blood Moon"] = "Поучаствуй в Кровавой Луне",
	["Damage the Gravekeeper"] = "Нанеси урон Смотрителю кладбища",
	["Open a Pumpkin Block"] = "Открой тыквенный блок",
	["Find a Halloween mutation"] = "Найди мутацию Хэллоуина",
	-- EVENT DOGDEX tab
	["BURIED MOON 2026"] = "ПОГРЕБЁННАЯ ЛУНА 2026",
	["Event dogs come from Pumpkin Lucky Blocks, the Gravekeeper and the cauldron brew. They stay yours after the event."] =
		"Собаки события выпадают из тыквенных блоков, со Смотрителя кладбища и из зелья котла. Они останутся с тобой и после события.",
	["OPEN DOGDEX"] = "ОТКРЫТЬ ДОГДЕКС",
	["COLLECTION REWARDS"] = "НАГРАДЫ ЗА КОЛЛЕКЦИЮ",
	["BURIED MOON SURVIVOR"] = "ПЕРЕЖИВШИЙ ПОГРЕБЁННУЮ ЛУНУ",
	["DISCOVERED"] = "ОТКРЫТА",
	["NOT FOUND YET"] = "ЕЩЁ НЕ НАЙДЕНА",
	["A secret dog of the Buried Moon. Only the luckiest ever see it."] = "Секретная собака Погребённой Луны. Её видят только самые везучие.",
	["RARE"] = "РЕДКОЕ",
	["EPIC"] = "ЭПИЧЕСКОЕ",
	["LEGENDARY"] = "ЛЕГЕНДАРНОЕ",
	["MYTHIC"] = "МИФИЧЕСКОЕ",
	["SECRET"] = "СЕКРЕТНОЕ",
	["COMMON"] = "ОБЫЧНОЕ",
	-- event dogs (same Russian as Localization.HalloweenDogs)
	["Pumpkin Pup"] = "Тыквенный щенок",
	["Sheet Shiba"] = "Шиба в простыне",
	["Bone Corgi"] = "Корги-скелет",
	["Frankenpug"] = "Франкенмопс",
	["Bat Dachshund"] = "Такса-летучая мышь",
	["Plague Pug"] = "Чумной мопс",
	["Headless Hound"] = "Безголовая гончая",
	["Eclipse Dog"] = "Пёс затмения",
	["+20% Candy from Pumpkin Patch dig spots."] = "+20% конфет с тыквенных мест раскопок.",
	["Can find Ghost Loot: haunted finds at Ghost Soil and in the yard."] = "Находит призрачную добычу: призрачные находки на Призрачной почве и во дворе.",
	["+35% Bones from digs and Bone Graves. Falls apart and rebuilds itself."] = "+35% костей с раскопок и Костяных могил. Рассыпается и собирается обратно.",
	["OVERCHARGE: every 5 digs it supercharges and digs 60% faster for 40 s."] = "ПЕРЕЗАРЯД: каждые 5 раскопок заряжается и 40 с копает на 60% быстрее.",
	["After a find it flies straight to the next dig: +40% speed on the next dig and dig spots start damaged."] =
		"После находки летит прямо к следующей раскопке: +40% скорости следующей раскопки, а места раскопок начинаются повреждёнными.",
	["Strongly raises the mutation chance of its finds and slightly for the whole team."] = "Сильно повышает шанс мутации своих находок и немного — всей команде.",
	["Finds Headless Treasure: bonus coin caches on digs, double Cursed Treasure chance."] =
		"Находит Безголовый клад: тайники с монетами при раскопках и двойной шанс Проклятого клада.",
	["Rarely turns a find into ECLIPSED (x20 value)."] = "Изредка превращает находку в ЗАТМЁННУЮ (ценность x20).",
	-- CAULDRON tab
	["TRICK"] = "ГАДОСТЬ",
	["TREAT"] = "СЛАДОСТЬ",
	["TOP PRIZES"] = "ГЛАВНЫЕ ПРИЗЫ",
	["Stand next to the Haunted Cauldron in the Dead Yard"] = "Подойди к котлу с привидениями на Мёртвом дворе",
	["The cauldron is listening..."] = "Котёл слушает...",
	["Feed candy to the cauldron. The more you invest, the better the brew. One brew per season, ready 7 days after you start."] =
		"Корми котёл конфетами. Чем больше вложишь, тем лучше зелье. Одно зелье за сезон, готово через 7 дней после начала.",
	["NEXT LEVEL"] = "СЛЕД. УРОВЕНЬ",
	["MAX"] = "МАКС.",
	["TOP LEVEL!"] = "ВЫСШИЙ УРОВЕНЬ!",
	["FREE"] = "БЕСПЛАТНО",
	["YOUR BREW"] = "ТВОЁ ЗЕЛЬЕ",
	["CLAIMED THIS SEASON"] = "ПОЛУЧЕНО В ЭТОМ СЕЗОНЕ",
	["NOT STARTED"] = "НЕ НАЧАТО",
	["START BREW"] = "НАЧАТЬ ВАРКУ",
	["READY IN"] = "БУДЕТ ГОТОВО ЧЕРЕЗ",
	["READY!"] = "ГОТОВО!",
	["CLAIM BREW"] = "ЗАБРАТЬ ЗЕЛЬЕ",
	["THE BURIED MOON BREW"] = "ЗЕЛЬЕ ПОГРЕБЁННОЙ ЛУНЫ",
	["Tap a level to see its brew. Every row is granted, not rolled."] = "Нажми на уровень, чтобы увидеть его зелье. Выдаётся всё, без случайностей.",
	["SIMMERING"] = "ТОМИТСЯ",
	["BUBBLING"] = "БУЛЬКАЕТ",
	["BOILING"] = "КИПИТ",
	["OVERFLOWING"] = "БЬЁТ ЧЕРЕЗ КРАЙ",
	["BURIED MOON BREW"] = "ЗЕЛЬЕ ПОГРЕБЁННОЙ ЛУНЫ",
	["PUMPKIN BLOCK"] = "ТЫКВЕННЫЙ БЛОК",
	["CURSED PUMPKIN"] = "ПРОКЛЯТАЯ ТЫКВА",
	["PUMPKIN LUCKY BLOCK added to your Inventory"] = "ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК добавлен в инвентарь",
	["CURSED PUMPKIN LUCKY BLOCK added to your Inventory"] = "ПРОКЛЯТЫЙ ТЫКВЕННЫЙ БЛОК добавлен в инвентарь",
	["RARE PUMPKIN LUCKY BLOCK added to your Inventory"] = "РЕДКИЙ ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК добавлен в инвентарь",
	["RARE CURSED PUMPKIN LUCKY BLOCK added to your Inventory"] = "РЕДКИЙ ПРОКЛЯТЫЙ ТЫКВЕННЫЙ БЛОК добавлен в инвентарь",
	["JACK-O'-LANTERN"] = "СВЕТИЛЬНИК ДЖЕКА",
	["GRAVE STONE"] = "НАДГРОБИЕ",
	["CANDLE CLUSTER"] = "СВЕЧИ",
	["BONE ARCH"] = "КОСТЯНАЯ АРКА",
	["HAUNTED FIND"] = "ПРИЗРАЧНАЯ НАХОДКА",
	["PUMPKINIZED FIND"] = "ТЫКВЕННАЯ НАХОДКА",
	["BLOOD MOON FIND"] = "НАХОДКА КРОВАВОЙ ЛУНЫ",
	["ECLIPSED FIND"] = "ЗАТМЁННАЯ НАХОДКА",
	-- BOSS tab
	["Sleeping under the Graveyard Pit. Ring the bell to wake him."] = "Спит под кладбищенской ямой. Позвони в колокол, чтобы разбудить его.",
	["Ring the Grave Bell at the pit to summon. Beat a difficulty to unlock the next one. Everyone nearby can join the fight."] =
		"Позвони в могильный колокол у ямы, чтобы призвать босса. Победи на сложности, чтобы открыть следующую. Сражаться могут все рядом.",
	["SUMMON"] = "ПРИЗВАТЬ",
	["GO TO THE BELL"] = "К КОЛОКОЛУ",
	["FIGHT ON"] = "ИДЁТ БОЙ",
	["LOCKED"] = "ЗАКРЫТО",
	["DEFEATED"] = "ПОБЕЖДЁН",
	["ECLIPSED finds"] = "ЗАТМЁННЫЕ находки",
	["ARMOR"] = "БРОНЯ",
	["SHIELD · SMASH THE SKELETONS"] = "ЩИТ · РАЗБЕЙ СКЕЛЕТОВ",
	["WEAK POINT OPEN!"] = "СЛАБОЕ МЕСТО ОТКРЫТО!",
	["EASY"] = "ЛЕГКО",
	["UNEASY"] = "ТРЕВОЖНО",
	["NIGHTMARE"] = "КОШМАР",
	["HELL"] = "АД",
	["AWAKENING"] = "ПРОБУЖДЕНИЕ",
	["BURROW"] = "ПОДКОП",
	["SKELETON PACK"] = "СТАЯ СКЕЛЕТОВ",
	["CURSED ROCKS"] = "ПРОКЛЯТЫЕ КАМНИ",
	["ENRAGED"] = "ЯРОСТЬ",
	-- COSMETICS tab
	["PICKAXE SKINS"] = "СКИНЫ КИРОК",
	["Skins only change the look. Every stat still comes from your real pickaxe."] = "Скины меняют только вид. Все характеристики остаются от твоей настоящей кирки.",
	["UNEQUIP"] = "СНЯТЬ",
	["EQUIP"] = "НАДЕТЬ",
	["EQUIPPED"] = "НАДЕТО",
	["Owned forever: keep it after the event."] = "Твой навсегда: останется и после события.",
	["Find it in:"] = "Где найти:",
	["Pumpkin Lucky Block"] = "Тыквенный счастливый блок",
	["Cursed Pumpkin"] = "Проклятая тыква",
	["Grave Shovel"] = "Могильная лопата",
	["Bone Pickaxe"] = "Костяная кирка",
	["Pumpkin Smasher"] = "Тыквенный крушитель",
	["Ghost Scythe"] = "Призрачная коса",
	["Living Coffin"] = "Живой гроб",
	["Soul Reaper"] = "Жнец душ",
	-- HUD
	["BLOOD MOON RISES IN"] = "КРОВАВАЯ ЛУНА ЧЕРЕЗ",
	["SERVER CANDY RUSH x2"] = "ЛИХОРАДКА СЕРВЕРА x2",
	["Earn it in THE DEAD YARD: perfect hits, ore, haunted dig spots, houses, the boss and quests. Spend it at the cauldron."] =
		"Добывай их на МЁРТВОМ ДВОРЕ: идеальные удары, руда, проклятые раскопки, дома, босс и задания. Трать у котла.",
	["The curse rises while you idle in the Dead Yard. Above 80% you earn less candy. Dig, mine, knock and fight to lift it."] =
		"Проклятие растёт, пока ты бездельничаешь на Мёртвом дворе. Выше 80% конфет меньше. Копай, добывай, стучи и сражайся, чтобы снять его.",
	["Every candy and objective in the Dead Yard banishes souls for the whole server."] = "Каждая конфета и задание на Мёртвом дворе изгоняют души для всего сервера.",
	["EXORCISM MILESTONE"] = "ЭТАП ЭКЗОРЦИЗМА",
	["A PUMPKIN BLOCK FOR EVERYONE"] = "ТЫКВЕННЫЙ БЛОК КАЖДОМУ",
	["EVENT MUTATIONS x2"] = "МУТАЦИИ СОБЫТИЯ x2",
	["THE GRAVEKEEPER RISES"] = "СМОТРИТЕЛЬ КЛАДБИЩА ВОССТАЛ",
	["CANDY RUSH x2 · 5 MIN"] = "КОНФЕТНАЯ ЛИХОРАДКА x2 · 5 МИН",
	["PUMPKIN BLOCK FOR EVERYONE"] = "ТЫКВЕННЫЙ БЛОК КАЖДОМУ",
	["RARE PUMPKIN BLOCK FOR EVERYONE"] = "РЕДКИЙ ТЫКВЕННЫЙ БЛОК ДЛЯ ВСЕХ",
	["RARE PUMPKIN BLOCK FOR THE EXORCISTS"] = "РЕДКИЙ ТЫКВЕННЫЙ БЛОК ДЛЯ ЭКЗОРЦИСТОВ", -- [WP-E] Config.Exorcism milestone 2500
	["MUTATION CHANCE x2 · 10 MIN"] = "ШАНС МУТАЦИИ x2 · 10 МИН",
	["Your Candy Rush is over"] = "Твоя конфетная лихорадка закончилась",
	-- server prompts of the Dead Yard (never auto-translated: HalloweenClient.HUD sets them)
	["BREW"] = "ВАРИТЬ",
	["HAUNTED CAULDRON"] = "КОТЁЛ С ПРИВИДЕНИЯМИ",
	["RING"] = "ПОЗВОНИТЬ",
	["GRAVE BELL"] = "МОГИЛЬНЫЙ КОЛОКОЛ",
	["KNOCK"] = "ПОСТУЧАТЬ",
	["TRICK OR TREAT"] = "СЛАДОСТЬ ИЛИ ГАДОСТЬ",
	-- onboarding
	["NEXT"] = "ДАЛЕЕ",
	["SKIP"] = "ПРОПУСТИТЬ",
	["LET'S GO!"] = "ВПЕРЁД!",
	["Everything you do in the Dead Yard drops candy. Watch it fly into your counter at the top."] =
		"Всё, что ты делаешь на Мёртвом дворе, приносит конфеты. Смотри, как они летят в счётчик наверху.",
	["THE CURSE"] = "ПРОКЛЯТИЕ",
	["Standing around raises your curse. Keep digging, mining and fighting: a high curse means less candy."] =
		"Если стоять без дела, проклятие растёт. Копай, добывай руду и сражайся: сильное проклятие — меньше конфет.",
	["During the Blood Moon cursed graves rise in the graveyard. Dig them with your pickaxe for candy and rare finds."] =
		"Под Кровавой Луной на кладбище поднимаются проклятые могилы. Раскапывай их киркой ради конфет и редких находок.",
	["Throw candy into the Haunted Cauldron for Pumpkin Lucky Blocks, or brew a big reward. Knock on the 7 doors once a day."] =
		"Бросай конфеты в котёл с привидениями ради тыквенных блоков или свари большую награду. Стучи в 7 дверей раз в день.",
	["THE BLOOD MOON"] = "КРОВАВАЯ ЛУНА",
	["About every 15 minutes the moon turns red: +50% candy and haunted dig spots. The timer is at the top of your screen."] =
		"Примерно каждые 15 минут луна краснеет: +50% конфет и проклятые раскопки. Таймер — вверху экрана.",
	["Ring the Grave Bell at the pit to wake the boss. Beat him to unlock harder difficulties and better loot."] =
		"Позвони в могильный колокол у ямы, чтобы разбудить босса. Побеждай его, чтобы открыть сложности выше и добычу лучше.",
	["8 Halloween dogs are hiding in pumpkins, brews and boss loot. Quests, the cauldron and everything else are in the HALLOWEEN menu."] =
		"8 хэллоуинских собак прячутся в тыквах, зельях и добыче босса. Задания, котёл и всё остальное — в меню ХЭЛЛОУИН.",
}

L.Templates = {
	["%d / %d"] = "%d / %d",
	["%s / %s"] = "%s / %s",
	["%ds"] = "%d с",
	["%d EVENT DOGS FOUND"] = { "НАЙДЕНА %d СОБАКА СОБЫТИЯ", "НАЙДЕНО %d СОБАКИ СОБЫТИЯ", "НАЙДЕНО %d СОБАК СОБЫТИЯ" },
	["%s / %s to the next level"] = "%s / %s до следующего уровня",
	["%s%% Cursed Pumpkin"] = "%s%% проклятая тыква",
	["%s%% event dog"] = "%s%% собака события",
	["ACTIVE · %s LEFT"] = "ИДЁТ · ОСТАЛОСЬ %s",
	["ARMOR %s / %s"] = "БРОНЯ %s / %s",
	["Armor x%s"] = "Броня x%s",
	["Rewards x%s"] = "Награды x%s",
	["BREW REWARDS AT LEVEL %d · %s"] = "ЗЕЛЬЕ УРОВНЯ %d · %s",
	["Cauldron brew L%s+"] = "Зелье котла ур. %s+",
	["Cauldron level %d · %s"] = "Котёл: уровень %d · %s",
	["Daily quests claimed: %d / %d"] = "Ежедневных заданий получено: %d / %d",
	["Defeat %s first"] = "Сначала победи на %s",
	["Doors knocked today: %d / %d"] = "Дверей сегодня: %d / %d",
	["Event DogDex %d/8"] = "Догдекс события %d/8",
	["FIGHT IN PROGRESS · %s %s"] = "ИДЁТ БОЙ · %s %s",
	["Fighters: %d"] = "Бойцов: %d",
	["Gravekeeper: up to %s unlocked"] = "Смотритель: открыто до %s",
	["LEVEL %d · %s"] = "УРОВЕНЬ %d · %s",
	["Lifetime %s  ·  Spent %s"] = "Всего %s  ·  Потрачено %s",
	["NEW QUESTS IN %s"] = "НОВЫЕ ЗАДАНИЯ ЧЕРЕЗ %s",
	["NEXT LEVEL · %s"] = "СЛЕД. УРОВЕНЬ · %s",
	["Next: %s souls · %s"] = "Далее: %s душ · %s",
	["READY · %s"] = "ГОТОВО · %s",
	["Right now: x%s candy"] = "Сейчас: x%s конфет",
	["SERVER RUSH x2 · %s"] = "ЛИХОРАДКА СЕРВЕРА x2 · %s",
	["The Gravekeeper rests. Next summon in %s"] = "Смотритель отдыхает. Призыв через %s",
	["Throw %d candy into the cauldron and get a PUMPKIN LUCKY BLOCK. Sometimes it comes out CURSED."] = {
		"Брось %d конфету в котёл и получи ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК. Иногда он выходит ПРОКЛЯТЫМ.",
		"Брось %d конфеты в котёл и получи ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК. Иногда он выходит ПРОКЛЯТЫМ.",
		"Брось %d конфет в котёл и получи ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК. Иногда он выходит ПРОКЛЯТЫМ.",
	},
	["Tricks played: %d"] = "Сыграно гадостей: %d",
	["USED TODAY · NEW IN %s"] = "СЕГОДНЯ УЖЕ БЫЛА · НОВАЯ ЧЕРЕЗ %s",
	["You need %d candy"] = { "Нужна %d конфета", "Нужно %d конфеты", "Нужно %d конфет" },
	["Your best: %s"] = "Твой рекорд: %s",
	["x%s CANDY NOW"] = "x%s КОНФЕТ СЕЙЧАС",
	-- daily quests (Config.Quests.Pool texts; goal = the first number)
	["Dig %d Haunted Spots"] = { "Раскопай %d проклятую могилу", "Раскопай %d проклятые могилы", "Раскопай %d проклятых могил" },
	["Get %d Perfect Hits"] = { "Сделай %d идеальный удар", "Сделай %d идеальных удара", "Сделай %d идеальных ударов" },
	["Earn %d Candy"] = { "Заработай %d конфету", "Заработай %d конфеты", "Заработай %d конфет" },
	["Break %d Halloween ores"] = { "Разбей %d хэллоуинскую руду", "Разбей %d хэллоуинские руды", "Разбей %d хэллоуинских руд" },
	["Knock on %d doors"] = { "Постучи в %d дверь", "Постучи в %d двери", "Постучи в %d дверей" },
}

-- server replies / toasts (English from SSS.Halloween.*, Economy.Features.Halloween) and the legacy labels of this event
L.Exact = {
	-- the Eclipse Dog's island-wide arrival banner (SecretArrivals Mega/HW_EclipseDog)
	["✦  THE MOON WENT OUT  ✦"] = "✦  ЛУНА ПОГАСЛА  ✦",
	-- world signs of THE DEAD YARD (WP2 SurfaceGuis, translated by DOGROTS_AutoTranslateUI, which reads Exact only)
	["HOLLOW LANE"] = "ПУСТОЙ ПЕРЕУЛОК",
	["TRICK OR TREAT"] = "СЛАДОСТЬ ИЛИ ГАДОСТЬ",
	["KEEP OUT"] = "НЕ ВХОДИТЬ",
	["CEMETERY"] = "КЛАДБИЩЕ",
	["FOREVER A GOOD BOY"] = "НАВСЕГДА ХОРОШИЙ МАЛЬЧИК",
	["GOOD BOY"] = "ХОРОШИЙ МАЛЬЧИК",
	["GOOD GIRL"] = "ХОРОШАЯ ДЕВОЧКА",
	["DUG TOO DEEP"] = "КОПАЛ СЛИШКОМ ГЛУБОКО",
	["DANGER · MUTAGEN"] = "ОПАСНО · МУТАГЕН",
	["MUTATION LAB · ANNEX B"] = "ЛАБОРАТОРИЯ МУТАЦИЙ · КОРПУС Б",
	["CAULDRON"] = "КОТЁЛ",
	["THE PIT"] = "ЯМА",
	["BROKEN LAB"] = "РАЗРУШЕННАЯ ЛАБОРАТОРИЯ",
	["CRYPTS"] = "СКЛЕПЫ",
	["CLOSED"] = "ЗАКРЫТО",
	["THE GRAVE BELL"] = "МОГИЛЬНЫЙ КОЛОКОЛ", -- Grave Bell belfry friezes (Pit.lua)
	["RING TO SUMMON"] = "ПОЗВОНИ, ЧТОБЫ ПРИЗВАТЬ",
	-- Core
	["The Night of the Buried Moon has ended"] = "Ночь Погребённой Луны закончилась",
	["Your saved profile is still loading"] = "Твой профиль ещё загружается",
	["Dog grant not declared"] = "Выдача собаки не объявлена",
	["Dog asset unavailable"] = "Модель собаки недоступна",
	["Unknown skin"] = "Неизвестный скин",
	["Unknown action"] = "Неизвестное действие",
	["Not ready"] = "Ещё не готово",
	-- TradeScreen blockReason for event blocks (lead integration, WP5 request)
	["Event block: it cannot be traded"] = "Блок события: его нельзя обменять",
	-- "Your dog storage is full", "Connection problem; try again", "Invalid request" and "Please wait a moment"
	-- are already translated by the base Localization modules (Dogs/Trade/Lab/Titles)
	-- Economy.Features.Halloween
	["Invalid Halloween progress"] = "Ошибка прогресса Хэллоуина",
	["Invalid Candy balance"] = "Ошибка баланса конфет",
	["Not enough Candy"] = "Не хватает конфет",
	-- Actions
	["Invalid quest"] = "Неверное задание",
	["This quest is not part of today's list"] = "Этого задания нет в сегодняшнем списке",
	["Already claimed"] = "Уже получено",
	["Quest not finished yet"] = "Задание ещё не выполнено",
	["Already claimed today"] = "Сегодня уже получено",
	["Finish and claim every daily quest first"] = "Сначала выполни и забери все ежедневные задания",
	["Your Candy Rush is already running"] = "Твоя конфетная лихорадка уже идёт",
	["Candy Rush used today. Come back tomorrow!"] = "Конфетная лихорадка на сегодня потрачена. Приходи завтра!",
	["Come closer to the Haunted Cauldron"] = "Подойди ближе к котлу с привидениями",
	["Your Lucky Block storage is full. Open a block first"] = "Хранилище счастливых блоков заполнено. Сначала открой блок",
	["Invalid amount"] = "Неверное количество",
	["Your brew is finished for this season"] = "Твоё зелье в этом сезоне уже сварено",
	["The cauldron is already at the top level"] = "Котёл уже на высшем уровне",
	["Start a brew first"] = "Сначала начни варку",
	["The brew is not ready yet"] = "Зелье ещё не готово",
	["You don't own this skin"] = "У тебя нет этого скина",
	["Invalid reward"] = "Неверная награда",
	["Discover more Buried Moon dogs first"] = "Сначала открой больше собак Погребённой Луны",
	["Invalid key"] = "Неверный ключ",
	["Quest reward claimed"] = "Награда за задание получена",
	["Daily bonus claimed"] = "Ежедневный бонус получен",
	["CANDY RUSH x2 started"] = "Конфетная лихорадка x2 запущена",
	["Your brew is simmering"] = "Твоё зелье томится",
	["The Buried Moon Brew is ready!"] = "Зелье Погребённой Луны готово!",
	["Event DogDex reward claimed"] = "Награда Догдекса события получена",
	["Skin removed"] = "Скин снят",
	-- Houses (WP10b)
	["You already knocked on this door today. Come back tomorrow!"] = "Ты уже стучал в эту дверь сегодня. Приходи завтра!",
	["Walk up to the door to knock"] = "Подойди к двери, чтобы постучать",
	["Invalid house"] = "Неверный дом",
	["The porch skeleton slipped back into the house"] = "Скелет с крыльца сбежал обратно в дом",
	["This skeleton is haunting another player"] = "Этот скелет преследует другого игрока",
	-- THE GRAVEKEEPER (WP8)
	["Too late!"] = "Слишком поздно!",
	["The Gravekeeper is not here this season"] = "Смотрителя кладбища в этом сезоне нет",
	["The Gravekeeper cannot be fought right now"] = "Со Смотрителем сейчас нельзя сразиться",
	["The Gravekeeper is already awake"] = "Смотритель уже проснулся",
	["Unknown difficulty"] = "Неизвестная сложность",
	["Ring the Grave Bell"] = "Позвони в могильный колокол",
	["Defeat the previous difficulty first"] = "Сначала победи на предыдущей сложности",
	["Ring the Grave Bell at the pit to summon the Gravekeeper"] = "Позвони в могильный колокол у ямы, чтобы призвать Смотрителя",
	["The Gravekeeper has fallen"] = "Смотритель кладбища повержен",
	["The Gravekeeper is changing form!"] = "Смотритель меняет облик!",
	["THE GRAVEKEEPER IS SHIELDED - smash the skeleton dogs!"] = "СМОТРИТЕЛЬ ПОД ЩИТОМ — разбей собак-скелетов!",
	-- the legacy WORLD FEATURES card (EconomyScreens) and the HALLOWEEN tile tooltip
	["THE DEAD YARD"] = "МЁРТВЫЙ ДВОР",
	["Night of the Buried Moon"] = "Ночь Погребённой Луны",
	-- Studio debug panel replies (SSS.Halloween.Debug)
	["Unknown event dog"] = "Неизвестная собака события",
	["Block storage full"] = "Хранилище блоков заполнено",
	["Boss module missing"] = "Модуль босса не найден",
	["Unknown debug command"] = "Неизвестная команда отладки",
	["Curse set"] = "Проклятие изменено",
	["Blood Moon warning started"] = "Предупреждение о Кровавой Луне запущено",
	["Blood Moon is up"] = "Кровавая Луна взошла",
	["Back to the schedule"] = "Снова по расписанию",
	["Souls added"] = "Души добавлены",
	["Daily state reset"] = "Ежедневный прогресс сброшен",
	["All skins granted"] = "Все скины выданы",
	["The Gravekeeper rises"] = "Смотритель кладбища восстал",
	["Brew ready"] = "Зелье готово",
	["Guide will show on the next visit"] = "Обучение покажется при следующем визите",
	["Candy Rush refilled"] = "Конфетная лихорадка восполнена",
	["Halloween ore respawned"] = "Хэллоуинская руда появилась снова",
	["No free dig point"] = "Нет свободного места раскопок",
}

-- dynamic server messages (anchored; AutoTranslate runs every rule on every label)
L.Patterns = {
	{ "^Invested (%d+) Candy$", function(n)
		return "Вложено " .. candies(n)
	end },
	{ "^CAULDRON LEVEL (%d+)$", "КОТЁЛ · УРОВЕНЬ %1" },
	{ "^TREAT! %+(%d+) Candy$", function(n)
		return "СЛАДОСТЬ! +" .. candies(n)
	end },
	{ "^TRICK! %+(%d+) Candy$", function(n)
		return "ГАДОСТЬ! +" .. candies(n)
	end },
	{ "^The porch skeleton crumbles! %+(%d+) Candy$", function(n)
		return "Скелет с крыльца рассыпался! +" .. candies(n)
	end },
	{ "^Lucky Block storage full: %+(%d+) Candy instead$", function(n)
		return "Хранилище счастливых блоков заполнено: +" .. candies(n) .. " вместо блока"
	end },
	{ "^The Gravekeeper rests for (%d+) more seconds$", "Смотритель отдыхает ещё %1 с" },
	{ "^(Grave Shovel) equipped$", "Надет скин: Могильная лопата" },
	{ "^(Bone Pickaxe) equipped$", "Надет скин: Костяная кирка" },
	{ "^(Pumpkin Smasher) equipped$", "Надет скин: Тыквенный крушитель" },
	{ "^(Ghost Scythe) equipped$", "Надет скин: Призрачная коса" },
	{ "^(Living Coffin) equipped$", "Надет скин: Живой гроб" },
	{ "^(Soul Reaper) equipped$", "Надет скин: Жнец душ" },
	{ "^%+(%d+) Candy$", function(n)
		return "+" .. candies(n)
	end },
	{ "^(HW_%w+) granted$", "Выдано: %1" },
	{ "^Pumpkin block granted$", "Тыквенный блок выдан" },
	{ "^Cursed Pumpkin block granted$", "Проклятая тыква выдана" },
	{ "^Spawned (%w+)$", "Создано: %1" },
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

return L
