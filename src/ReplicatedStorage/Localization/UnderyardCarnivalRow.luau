-- Russian of the world signs in THE UNDERYARD's FUNERAL CARNIVAL and CROOKED ROW (ReplicatedStorage.Localization.
-- UnderyardCarnivalRow, WP-H1). The signs are SurfaceGuis built offline by ServerStorage.UnderyardBuild.FuneralCarnival /
-- .CrookedRow; DOGROTS_AutoTranslateUI translates world text through `Exact` (global keys: never repeat a key another
-- Localization module or the base dictionary has; tests/underyard_carnival_row.luau checks both directions).
-- Digits (checkpoint, door and house numbers) and grave names carry NoTranslate and are not listed here.
-- Glossary: FUNERAL CARNIVAL = Похоронный карнавал, FUNERAL RUN = Похоронный забег, CROOKED ROW = Кривой ряд,
-- the Door Court = Двор дверей, coffin = гроб.
return {
	Exact = {
		-- FUNERAL CARNIVAL
		["THE FUNERAL CARNIVAL"] = "ПОХОРОННЫЙ КАРНАВАЛ",
		["TICKETS"] = "БИЛЕТЫ",
		["ADMIT ONE · NO RETURN"] = "ВХОД ДЛЯ ОДНОГО · БЕЗ ВОЗВРАТА",
		["THE FUNERAL RUN"] = "ПОХОРОННЫЙ ЗАБЕГ",
		["START LINE"] = "ЛИНИЯ СТАРТА",
		["FINISH LINE"] = "ЛИНИЯ ФИНИША",
		["THE LAST SHOW"] = "ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ",
		["GHOST-GO-ROUND"] = "ПРИЗРАЧНАЯ КАРУСЕЛЬ",
		["WHEEL OF FATE"] = "КОЛЕСО СУДЬБЫ",
		["COFFIN COASTER"] = "ГРОБОВЫЕ ГОРКИ",
		["COFFIN WORKS"] = "ГРОБОВАЯ ФАБРИКА",
		["THE GREAT DOGINI"] = "ВЕЛИКИЙ ДОГИНИ",
		["THE HEADLESS HOUND"] = "БЕЗГОЛОВЫЙ ПЁС",
		["LAST SHOW TONIGHT"] = "ПОСЛЕДНЕЕ ШОУ СЕГОДНЯ",
		["CANDY FLOSS"] = "САХАРНАЯ ВАТА",
		["BONE CORN"] = "КОСТЯНОЙ ПОПКОРН",
		["SKULL TOSS"] = "БРОСЬ ЧЕРЕП",
		["LUCKY BONES"] = "СЧАСТЛИВЫЕ КОСТИ",
		["RING THE BELL"] = "ПОЗВОНИ В КОЛОКОЛ",
		["THE FORTUNE HOUND"] = "ПЁС-ПРЕДСКАЗАТЕЛЬ",
		-- CROOKED ROW
		["13 CROOKED ROW"] = "КРИВОЙ РЯД, 13",
		["THE DOOR COURT"] = "ДВОР ДВЕРЕЙ",
		["CHOOSE YOUR DOOR"] = "ВЫБЕРИ СВОЮ ДВЕРЬ",
		["THE HOLLOW HOARD"] = "ПОЛАЯ СОКРОВИЩНИЦА",
	},
	Patterns = {},
	Phrases = {},
}
