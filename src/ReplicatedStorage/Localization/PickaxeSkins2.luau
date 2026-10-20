-- Russian for the Chapter II pickaxe skins of THE UNDERYARD (ReplicatedStorage.Localization.PickaxeSkins2, WP-K2):
-- the seven skin names as Config.Skins.Names sends them (server replies, reward rows, coffin cards), their upper-case
-- forms and "<NAME> SKIN" reward labels, the traits and lore lines, and the "<Name> equipped" reply of SkinEquip.
-- DOGROTS_AutoTranslateUI loads every module in this folder. Self-localized UI reads PickaxeSkins2.List (RU, TraitRU,
-- LoreRU) directly. Never repeat an Exact key another Localization module already has (Chapter I skins: Halloween /
-- HalloweenDogs / HalloweenItems).
return {
	Exact = {
		-- names (Config.Skins.Names)
		["Toothy Alarm"] = "Зубастый будильник",
		["Buried Hand of Fate"] = "Рука Судьбы · Погребённая",
		["Funeral Laughsaw"] = "Смехопила · Похоронная",
		["Static TV-Head"] = "ТВ-Башка · Помехи",
		["Marsh Octopus"] = "Мерзкий спрут · Болотный",
		["Gummy Horror"] = "Мармеладный ужас",
		["Bell Reaper"] = "Жнец колокола",
		["TOOTHY ALARM"] = "ЗУБАСТЫЙ БУДИЛЬНИК",
		["BURIED HAND OF FATE"] = "РУКА СУДЬБЫ · ПОГРЕБЁННАЯ",
		["FUNERAL LAUGHSAW"] = "СМЕХОПИЛА · ПОХОРОННАЯ",
		["STATIC TV-HEAD"] = "ТВ-БАШКА · ПОМЕХИ",
		["MARSH OCTOPUS"] = "МЕРЗКИЙ СПРУТ · БОЛОТНЫЙ",
		["GUMMY HORROR"] = "МАРМЕЛАДНЫЙ УЖАС",
		["BELL REAPER"] = "ЖНЕЦ КОЛОКОЛА",
		-- reward labels
		["TOOTHY ALARM SKIN"] = "СКИН: ЗУБАСТЫЙ БУДИЛЬНИК",
		["BURIED HAND OF FATE SKIN"] = "СКИН: РУКА СУДЬБЫ · ПОГРЕБЁННАЯ",
		["FUNERAL LAUGHSAW SKIN"] = "СКИН: СМЕХОПИЛА · ПОХОРОННАЯ",
		["STATIC TV-HEAD SKIN"] = "СКИН: ТВ-БАШКА · ПОМЕХИ",
		["MARSH OCTOPUS SKIN"] = "СКИН: МЕРЗКИЙ СПРУТ · БОЛОТНЫЙ",
		["GUMMY HORROR SKIN"] = "СКИН: МАРМЕЛАДНЫЙ УЖАС",
		["BELL REAPER SKIN"] = "СКИН: ЖНЕЦ КОЛОКОЛА",
		-- traits
		["Cosmetic · funeral alarm clock · snapping teeth · twin bell hammers"] = "Косметика · похоронный будильник · клацающие зубы · два молота-колокола",
		["Cosmetic · a pale hand from the grave · hourglass pick · sand that never runs out"] = "Косметика · бледная рука из могилы · кирка-песочные часы · песок, который не кончается",
		["Cosmetic · dead-circus saw blade · ribbon stripes · a grin that never stops"] = "Косметика · пила мёртвого цирка · полосы-ленты · ухмылка, которая не гаснет",
		["Cosmetic · a crooked old TV on a pole · static eyes · rabbit-ear antennas"] = "Косметика · кривой старый телевизор на шесте · глаза из помех · антенны-рожки",
		["Cosmetic · a marsh octopus coiled round a shovel · glowing spots · bog drips"] = "Косметика · болотный спрут, обвивший лопату · светящиеся пятна · болотные капли",
		["Cosmetic · translucent gummy skull · gummy-worm picks · jelly that drips forever"] = "Косметика · прозрачный мармеладный череп · кирки из мармеладных червей · вечно капающее желе",
		["Cosmetic · SECRET · the Black Bell's scythe · a violet moon for a blade"] = "Косметика · СЕКРЕТ · коса Чёрного колокола · фиолетовая луна вместо лезвия",
		-- lore
		["It rang once at every funeral in the Underyard, and nobody ever woke up. Now it rings on every hit, just in case."] = "Он звонил на каждых похоронах в Поддворье, и никто так и не проснулся. Теперь он звенит при каждом ударе, на всякий случай.",
		["Somebody was buried holding their own hourglass. The hand dug its way back up, and it is not letting go of the time it has left."] = "Кого-то похоронили с собственными песочными часами в руке. Рука прокопала путь наверх и не отпустит оставшееся время.",
		["The Funeral Carnival closed a hundred years ago. The saw from its last act still spins, and still thinks the joke is funny."] = "Похоронный карнавал закрылся сто лет назад. Пила из его последнего номера всё ещё крутится и всё ещё считает шутку смешной.",
		["It only shows one channel, and that channel is watching you back. Do not change it. It does not like that."] = "Он ловит лишь один канал, и этот канал смотрит на тебя. Не переключай. Ему это не нравится.",
		["Pulled out of the Mourning Marsh still holding a gravedigger's shovel. It refuses to give it back, so now it digs with you."] = "Его вытащили из Скорбного болота вместе с лопатой могильщика. Возвращать её он отказался, так что теперь копает вместе с тобой.",
		["The candy shop in the Underyard sold only one flavour: regret. This one came out of the mould grinning."] = "Кондитерская Поддворья продавала только один вкус: сожаление. Этот вышел из формы уже с ухмылкой.",
		["Only those who found every dog of the Underyard ever hear it ring. When it tolls, the moon answers."] = "Его звон слышат лишь те, кто нашёл всех собак Поддворья. Когда он бьёт, луна отвечает.",
	},
	Patterns = {
		{ "^Toothy Alarm equipped$", "Надет скин: Зубастый будильник" },
		{ "^Buried Hand of Fate equipped$", "Надет скин: Рука Судьбы · Погребённая" },
		{ "^Funeral Laughsaw equipped$", "Надет скин: Смехопила · Похоронная" },
		{ "^Static TV%-Head equipped$", "Надет скин: ТВ-Башка · Помехи" },
		{ "^Marsh Octopus equipped$", "Надет скин: Мерзкий спрут · Болотный" },
		{ "^Gummy Horror equipped$", "Надет скин: Мармеладный ужас" },
		{ "^Bell Reaper equipped$", "Надет скин: Жнец колокола" },
	},
}
