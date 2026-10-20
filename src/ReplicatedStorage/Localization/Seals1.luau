-- Russian of BELL SEALS I-IV (ReplicatedStorage.Localization.Seals1, WP-I).
--   Exact     English server text of ServerScriptService.Halloween.SealEcho / SealRun / SealMirror / SealMine: request
--             replies, C2TrialMsg toasts, Strike target labels and prompt texts. DOGROTS_AutoTranslateUI loads them for
--             every label in the game; HalloweenClient.Trials translates server replies / C2TrialMsg with L.Translate
--             (global keys: never repeat a key another Localization module or the base dictionary already has).
--   Patterns  {luaPattern, replacement} for server text with numbers (anchored)
-- The trial HUD, results card, presenters and the seal cinematic are self-localized (Shared.L(en, ru), NoTranslate).
-- Glossary (Localization.Underyard): Bell Seal = печать колокола, trial = испытание, echo = эхо, Bell Shards = осколки
-- колокола, hollow ore = полая руда, mirror pond = зеркальный пруд, ring = кольцо, run = забег.
local L = {}

L.Exact = {
	-- SealMirror (requests / prompt replies)
	["Begin the trial at the pond first"] = "Сначала начни испытание у пруда",
	["Unknown grave"] = "Неизвестная могила",
	["Wait for the graves to settle"] = "Подожди, пока могилы успокоятся",
	["This grave sleeps this round"] = "Эта могила в этом раунде спит",
	["Move closer to the grave"] = "Подойди ближе к могиле",
	["The stone is still turning"] = "Камень ещё поворачивается",
	["Stand at the scrying basin to consult the pond"] = "Встань у чаши провидения, чтобы спросить пруд",
	["The pond is still rippling"] = "По пруду ещё идёт рябь",
	-- prompts (the Russian also travels as ActionTextRU / ObjectTextRU attributes)
	["CONSULT THE POND"] = "СПРОСИТЬ ПРУД",
	["MIRROR POND"] = "ЗЕРКАЛЬНЫЙ ПРУД",
	-- Strike target labels (the Russian also travels as LabelRU)
	["HAUNTED ECHO"] = "ПРИЗРАЧНОЕ ЭХО",
	["HOLLOW ORE"] = "ПОЛАЯ РУДА",
}

L.Patterns = {
	{ "^MIRROR GRAVE (%d+)$", "ЗЕРКАЛЬНАЯ МОГИЛА %1" },
}

L.Phrases = {}

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

-- Russian of `text` (Exact, then Patterns) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local exact = L.Exact[text]
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
