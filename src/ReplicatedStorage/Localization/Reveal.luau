-- Russian of THE REVEAL (ReplicatedStorage.Localization.Reveal, WP-F): "И ЭТО ВСЁ?", the guide to the church, the church
-- cinematic, the teaser for players who are not ready yet, the portal transition (docs/halloween2/DESIGN.md §6).
--   UI      self-localized texts of HalloweenClient.Reveal (NoTranslate labels, world text, toasts it fires itself).
--           Read through L.T(en, lang) / L.UI only; never global (AutoTranslate does not load UI).
--   Exact   none: every server reply the reveal can show ("Come closer to the church", "Watch the church first",
--           "Chapter II is closed", "The Underyard is not ready yet", ...) is already in Localization.Underyard.
--   Patterns none: AutoTranslate runs every module's patterns over every label, and the reveal formats its own
--           numbers (distance in studs-as-metres, "%d m" / "%d м") on NoTranslate labels.
local L = {}

L.UI = {
	-- §6.1 the notification
	["IS THAT ALL?"] = "И ЭТО ВСЁ?",
	["Did you really think it would be that easy?"] = "Вы правда думали, что всё будет настолько просто?",
	["FIND OUT"] = "УЗНАТЬ",
	["PRESS ENTER"] = "НАЖМИ ENTER",
	["PRESS (A)"] = "НАЖМИ (A)",
	["TAP THE BUTTON"] = "НАЖМИ НА КНОПКУ",
	-- §6.2 the guide
	["THE CHURCH"] = "ЦЕРКОВЬ",
	["FOLLOW THE GHOST LIGHTS"] = "ИДИ ЗА ПРИЗРАЧНЫМИ ОГОНЬКАМИ",
	["The church is waiting. Follow the ghost lights."] = "Церковь ждёт. Иди за призрачными огоньками.",
	["DESCEND"] = "СПУСТИСЬ",
	["INTO THE UNDERYARD"] = "В ПОДДВОРЬЕ",
	["The doors are open. Descend into the Underyard."] = "Двери открыты. Спустись в Поддворье.",
	-- §6.3 / §6.5 the church
	["Something is waiting below."] = "Внизу что-то ждёт.",
	["Stand near the church to replay this scene."] = "Подойди к церкви, чтобы пересмотреть эту сцену.",
	-- §6.6 the portal
	["THE DEAD YARD"] = "МЁРТВЫЙ ДВОР",
	["NIGHT OF THE BURIED MOON"] = "НОЧЬ ПОГРЕБЁННОЙ ЛУНЫ",
	["The portal flickered. Try again."] = "Портал мигнул. Попробуй ещё раз.",
}

L.Exact = {}

L.Patterns = {}

-- Russian of a reveal text (UI, then Exact, then the first matching pattern) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local hit = L.UI[text] or L.Exact[text]
	if hit then
		return hit
	end
	for _, rule in ipairs(L.Patterns) do
		local out, n = string.gsub(text, rule[1], rule[2])
		if n > 0 then
			return out
		end
	end
	return nil
end

-- the text in the player's language (`ru` = is the player Russian)
function L.T(en: string, ru: boolean?): string
	if ru then
		return L.Translate(en, "ru") or en
	end
	return en
end

return L
