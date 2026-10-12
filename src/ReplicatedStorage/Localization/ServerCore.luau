-- Russian strings for the server foundation of the overhaul (docs/OVERHAUL.md): settings saves,
-- protected finds, feature gates and trade safety refusals. Read by DOGROTS_AutoTranslateUI (exact match first).
return {
	Exact = {
		-- Economy.Features.Settings (SettingsSave).
		["Settings saved"] = "Настройки сохранены",
		["Choose a setting"] = "Выбери настройку",
		["Unknown setting"] = "Неизвестная настройка",
		["Invalid value for this setting"] = "Недопустимое значение настройки",
		["Too many settings"] = "Слишком много настроек за раз",
		["Invalid settings"] = "Настройки повреждены",
		["Invalid settings version"] = "Неверная версия настроек",
		-- Economy.ItemProtection (collector sales, trades, market listings, lab catalysts).
		["Favorite finds are kept; unfavorite to sell"] = "Избранные находки не продаются: сними отметку «избранное»",
		-- Economy.FeatureRegistry: a feature's Gate refused without its own message.
		["You cannot do that here"] = "Здесь этого сделать нельзя",
		-- Engine:Trade safety.
		["Trade is committing"] = "Обмен уже выполняется",
		["Offer changed; review it again"] = "Предложение изменилось, проверь его ещё раз",
	},
	Patterns = {
		{ "^This find is protected %((.+)%)$", "Эта находка защищена (%1)" },
		{ "^Invalid setting (%w+)$", "Недопустимое значение настройки %1" },
	},
	Phrases = {},
}
