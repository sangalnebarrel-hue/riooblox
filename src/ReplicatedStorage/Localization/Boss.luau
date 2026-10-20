-- Russian of THE GRAVEKEEPER's CHAPTER II server text (ReplicatedStorage.Localization.Boss, WP-C; DESIGN §10.4-§11).
--   Exact     English replies of ServerScriptService.Halloween.Boss / BossFinale (Strike refusals, the Studio finale debug);
--             DOGROTS_AutoTranslateUI loads them for every label (global keys: never repeat a key another Localization
--             module has — the Chapter I boss replies live in Localization.Halloween)
--   Patterns  replies with a value
-- Everything the finale shows on screen (stage banners, IMMUNE / MISSED THE TOLL, PERFECT ONLY, the Victory / Fail cards)
-- is self-localized by the clients (BossFX / FinaleFX, WP-N) from the BossEvent payloads.
-- Glossary as in Localization.Halloween: THE GRAVEKEEPER = Смотритель кладбища, pit = яма, finale = финал.
local L = {}

L.Exact = {
	["Climb down into the pit to fight the Gravekeeper"] = "Спустись в яму, чтобы сражаться со Смотрителем",
	-- Studio finale debug (C2Debug {Cmd = "Finale"})
	["Finale started"] = "Финал запущен",
	["The finale needs difficulty V"] = "Для финала нужна сложность V",
	["Unknown finale stage"] = "Неизвестный этап финала",
}

L.Patterns = {
	{ "^Finale stage: (%a+)$", "Этап финала: %1" },
}

L.Phrases = {}

return L
