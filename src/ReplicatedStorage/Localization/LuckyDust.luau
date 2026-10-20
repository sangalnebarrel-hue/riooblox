-- Russian strings of LUCKY DUST (dismantling Lucky Blocks, the DUST FORGE), read by
-- StarterPlayer.StarterPlayerScripts.DOGROTS_AutoTranslateUI. The bag (Modules.InventoryScreen) localizes its own
-- labels (Kit.T + NoTranslate); this file covers what reaches the player as English text: the answers of
-- ServerScriptService.Economy.Features.LuckyDust. Keys that already exist in another dictionary are reused there
-- ("Finish your trade first" in Lab, "Your Lucky Block storage is full" in Trade), never repeated here.
local exact = {
	-- Dismantle (DismantleQuote / Dismantle).
	["Choose blocks to dismantle"] = "Выбери блоки для разбора",
	["This block cannot be dismantled"] = "Этот блок нельзя разобрать",
	["You do not have that many blocks of this tier"] = "У тебя нет столько блоков этой редкости",
	["That block is not in your bag"] = "Этого блока нет в сумке",
	["Take that block off its Lucky pad first"] = "Сначала забери этот блок с площадки",
	["That block is opening"] = "Этот блок сейчас открывается",
	["Quote expired; review the blocks again"] = "Оценка устарела; проверь блоки ещё раз",
	["Hold to confirm: Legendary and rarer blocks need a confirmation"] = "Удерживай для подтверждения: легендарные и более редкие блоки нужно подтвердить",
	["Blocks changed; review them again"] = "Блоки изменились; проверь их ещё раз",
	["Dust values changed; review the blocks again"] = "Цена в пыли изменилась; проверь блоки ещё раз",
	["Your Lucky Dust is full"] = "Счастливой пыли больше не помещается",
	["Invalid Lucky Dust data"] = "Неверные данные счастливой пыли",
	-- DUST FORGE (DustForge).
	["This block cannot be forged"] = "Этот блок нельзя выковать",
	["Choose how many blocks to forge"] = "Выбери, сколько блоков выковать",
	["Not enough Lucky Dust"] = "Не хватает счастливой пыли",
	["Forged a Common Lucky Block"] = "Выкован обычный счастливый блок",
	["Forged a Rare Lucky Block"] = "Выкован редкий счастливый блок",
	["Forged an Epic Lucky Block"] = "Выкован эпический счастливый блок",
	["Forged a Legendary Lucky Block"] = "Выкован легендарный счастливый блок",
}

return {
	Exact = exact,
	Patterns = {
		{ "^Dismantle (%d+) blocks? for (%d+) Lucky Dust$", "Разобрать блоков: %1 за %2 счастливой пыли" },
		{ "^Dismantled (%d+) blocks?: %+(%d+) Lucky Dust$", "Разобрано блоков: %1 · +%2 счастливой пыли" },
		{ "^Dismantled (%d+) blocks?: %+(%d+) Lucky Dust · %+(%d+) Candy$", "Разобрано блоков: %1 · +%2 счастливой пыли · +%3 конфет" },
		{ "^Dismantle at most (%d+) blocks at once$", "Можно разобрать не больше %1 блоков за раз" },
		{ "^Forged (%d+) Common Lucky Blocks$", "Выковано обычных счастливых блоков: %1" },
		{ "^Forged (%d+) Rare Lucky Blocks$", "Выковано редких счастливых блоков: %1" },
		{ "^Forged (%d+) Epic Lucky Blocks$", "Выковано эпических счастливых блоков: %1" },
		{ "^Forged (%d+) Legendary Lucky Blocks$", "Выковано легендарных счастливых блоков: %1" },
	},
	Phrases = {},
}
