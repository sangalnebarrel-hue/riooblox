-- Russian for the NIGHT OF THE BURIED MOON items (ReplicatedStorage.Localization.HalloweenItems): the 4 find
-- mutations, the PUMPKIN / CURSED PUMPKIN Lucky Blocks, their reward rows (odds page, reward card, pad popup) and the
-- server messages of the block / decor / trade patches. DOGROTS_AutoTranslateUI loads every module in this folder.
-- Decoration names come from DecorCatalog (Localization.Plot adds them), event dog names from Localization.HalloweenDogs.
return {
	Exact = {
		-- item mutations (pills on every card, reveal toasts, filters)
		["HAUNTED"] = "ПРИЗРАЧНЫЙ",
		["PUMPKINIZED"] = "ТЫКВЕННЫЙ",
		["BLOOD MOON"] = "КРОВАВАЯ ЛУНА",
		["ECLIPSED"] = "ЗАТМЁННЫЙ",
		-- block tiers
		["PUMPKIN LUCKY BLOCK"] = "ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК",
		["CURSED PUMPKIN LUCKY BLOCK"] = "ПРОКЛЯТЫЙ ТЫКВЕННЫЙ БЛОК",
		["🎃 PUMPKIN LUCKY BLOCK"] = "🎃 ТЫКВЕННЫЙ СЧАСТЛИВЫЙ БЛОК",
		["🔮 CURSED PUMPKIN LUCKY BLOCK"] = "🔮 ПРОКЛЯТЫЙ ТЫКВЕННЫЙ БЛОК",
		["PUMPKIN · YOUR LUCKY BLOCK"] = "ТЫКВЕННЫЙ · ТВОЙ СЧАСТЛИВЫЙ БЛОК",
		["CURSED PUMPKIN · YOUR LUCKY BLOCK"] = "ПРОКЛЯТЫЙ ТЫКВЕННЫЙ · ТВОЙ СЧАСТЛИВЫЙ БЛОК",
		["Pumpkin Lucky Block"] = "Тыквенный счастливый блок",
		["Cursed Pumpkin Lucky Block"] = "Проклятый тыквенный блок",
		["PUMPKIN"] = "ТЫКВА",
		["CURSED PUMPKIN"] = "ПРОКЛЯТАЯ ТЫКВА",
		-- reward rows (Halloween.Config.Rewards.Pumpkin / CursedPumpkin)
		["Coin Pile"] = "Груда монет",
		["Cursed Hoard"] = "Проклятый клад",
		["HAUNTED FIND"] = "ПРИЗРАЧНАЯ НАХОДКА",
		["PUMPKINIZED FIND"] = "ТЫКВЕННАЯ НАХОДКА",
		["BLOOD MOON FIND"] = "НАХОДКА КРОВАВОЙ ЛУНЫ",
		["ECLIPSED FIND"] = "ЗАТМЁННАЯ НАХОДКА",
		["GRAVE SHOVEL SKIN"] = "СКИН: МОГИЛЬНАЯ ЛОПАТА",
		["BONE PICKAXE SKIN"] = "СКИН: КОСТЯНАЯ КИРКА",
		["PUMPKIN SMASHER SKIN"] = "СКИН: ТЫКВЕННЫЙ КРУШИТЕЛЬ",
		["GHOST SCYTHE SKIN"] = "СКИН: ПРИЗРАЧНАЯ КОСА",
		["LIVING COFFIN SKIN"] = "СКИН: ЖИВОЙ ГРОБ",
		["SOUL REAPER SKIN"] = "СКИН: ЖНЕЦ ДУШ",
		["REWARD SAVED"] = "НАГРАДА СОХРАНЕНА",
		-- server messages
		["Event reward: open Pumpkin Lucky Blocks to get it"] = "Награда события: открывай тыквенные блоки, чтобы получить",
		["Event Lucky Blocks cannot be traded"] = "Блоки события нельзя обменивать",
		["Event reward table missing for Pumpkin"] = "Таблица наград тыквенного блока недоступна",
		["Unknown pickaxe skin"] = "Неизвестный скин кирки",
		["Open Pumpkin Lucky Blocks to get it"] = "Открывай тыквенные блоки, чтобы получить",
	},
	Patterns = {
		{ "^([%d%.,]+[KMB]?) Coins$", "%1 монет" },
		{ "^([%d%.,]+[KMB]?) Bones$", "%1 костей" },
		{ "^([%d%.,]+[KMB]?) Candy$", "%1 конфет" },
	},
	Phrases = {
		{ "ALL REWARDS · ", "ВСЕ НАГРАДЫ · " },
		{ "HAUNTED FIND · ", "ПРИЗРАЧНАЯ НАХОДКА · " },
		{ "PUMPKINIZED FIND · ", "ТЫКВЕННАЯ НАХОДКА · " },
		{ "BLOOD MOON FIND · ", "НАХОДКА КРОВАВОЙ ЛУНЫ · " },
		{ "ECLIPSED FIND · ", "ЗАТМЁННАЯ НАХОДКА · " },
		{ " · DECORATION MAXED", " · УКРАШЕНИЕ НА МАКСИМУМЕ" },
		{ " · SKIN ALREADY OWNED", " · СКИН УЖЕ ЕСТЬ" },
		{ " · BAG FULL", " · СУМКА ПОЛНА" },
	},
}
