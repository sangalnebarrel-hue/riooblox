-- Kennel dog status labels (DogKennelService creates them, DogAnimations fills them in).
-- The status line changes every second, so DogAnimations localizes it itself from Kennel
-- below and marks the label NoTranslate; Exact/Patterns cover the same English text for
-- DOGROTS_AutoTranslateUI wherever it appears without that attribute.
local Kennel = {
	DIGGING = { "DIGGING", "КОПАЕТ" },
	FIND_IN = { "DIGGING · FIND IN %ds", "КОПАЕТ · НАХОДКА ЧЕРЕЗ %d с" },
	RESTING = { "RESTING", "ОТДЫХАЕТ" },
	STORAGE_FULL = { "STORAGE FULL", "ХРАНИЛИЩЕ ЗАПОЛНЕНО" },
}

return {
	Kennel = Kennel,
	Exact = {
		["DIGGING"] = "КОПАЕТ",
		["RESTING"] = "ОТДЫХАЕТ",
		["STORAGE FULL"] = "ХРАНИЛИЩЕ ЗАПОЛНЕНО",
	},
	Patterns = {
		{ "^DIGGING · FIND IN (%d+)s$", "КОПАЕТ · НАХОДКА ЧЕРЕЗ %1 с" },
		-- The previous server-side label, kept for any place copy that still shows it.
		{ "^RESTING · READY IN (%d+)s$", "ОТДЫХАЕТ · ГОТОВ ЧЕРЕЗ %1 с" },
	},
	Phrases = {},
}
