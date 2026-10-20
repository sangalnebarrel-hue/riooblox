-- Russian of THE UNDERYARD runtime and the Chapter II onboarding (ReplicatedStorage.Localization.UnderyardFX, WP-H2).
--   UI        the self-localized client text of HalloweenClient.UnderyardFX (district banner, gate signs), Chapter2Guide
--             (the ghost guide's card, the world marker) and the practice-trial presenters Trials.Toll / Trials.Mourner;
--             looked up by those modules only (they set NoTranslate on their labels), so these keys never reach the
--             global auto-translator
--   Exact     English replies / toasts of ServerScriptService.Halloween.Chapter2Tutorial (global keys for
--             DOGROTS_AutoTranslateUI and HalloweenClient.Chapter2State.T: never repeat a key another Localization module
--             or the base dictionary has — "You are downed: wait for a revive" comes from Localization.Combat)
--   Patterns  none: the server replies carry no numbers
-- World signs of 40_Underyard carry their own TextEN / TextRU (UnderyardFX swaps them); step titles and texts of the guide
-- are Chapter2Config.Tutorial pairs; the hints are UnderyardRuntime.GuideSteps pairs.
-- Glossary: Bell Shards = осколки колокола, Black Coffin = Чёрный гроб, Coffin Key = ключ от гроба, Event HP = здоровье
-- события, practice ring = тренировочный круг, the Mourner = Плакальщик, hand-bell = колокольчик, echo = эхо, ghost guide =
-- призрачный проводник, PERFECT = ИДЕАЛЬНО, Bell Seal = печать колокола, altar = алтарь.
local L = {}

L.UI = {
	-- UnderyardFX
	["THE UNDERYARD"] = "ПОДДВОРЬЕ",
	["SEALED · BELL SEAL %s"] = "ЗАПЕЧАТАНО · ПЕЧАТЬ КОЛОКОЛА %s",
	["SEAL %s · %s"] = "ПЕЧАТЬ %s · %s",
	-- Chapter2Guide: the card
	["GHOST GUIDE · STEP %d / %d"] = "ПРИЗРАЧНЫЙ ПРОВОДНИК · ШАГ %d / %d",
	["GHOST GUIDE · COMPLETE"] = "ПРИЗРАЧНЫЙ ПРОВОДНИК · ГОТОВО",
	["STEP %d/%d · %s"] = "ШАГ %d/%d · %s",
	["SHOW ME"] = "ПОКАЖИ",
	["SKIP GUIDE"] = "ПРОПУСТИТЬ",
	["TAP AGAIN TO SKIP"] = "НАЖМИ ЕЩЁ РАЗ",
	["SKIPPING..."] = "ПРОПУСКАЕМ...",
	["GOT IT"] = "ПОНЯТНО",
	["THE UNDERYARD IS YOURS"] = "ПОДДВОРЬЕ ТВОЁ",
	["The pup returns to its bell. Break the Bell Seals one by one: each opens a new district."] =
		"Щенок возвращается к своему колоколу. Ломай печати колокола одну за другой: каждая открывает новый район.",
	["THE UNDERYARD window (rail) shows your seals, contracts, coffins and the journal."] =
		"Окно ПОДДВОРЬЕ (на боковой панели) показывает печати, контракты, гробы и журнал.",
	["Not this time. BEGIN TRIAL again: the guide waits for you."] =
		"В этот раз не вышло. Начни испытание снова: проводник подождёт.",
	-- Chapter2Guide: the world marker
	["ECHO"] = "ЭХО",
	["HAND-BELL"] = "КОЛОКОЛЬЧИК",
	["BLACK COFFIN"] = "ЧЁРНЫЙ ГРОБ",
	["PRACTICE RING"] = "ТРЕНИРОВОЧНЫЙ КРУГ",
	["THE MOURNER"] = "ПЛАКАЛЬЩИК",
	["ALTAR I"] = "АЛТАРЬ I",
	-- Trials.Toll
	["ONLY A PERFECT RINGS THE BELL"] = "ЗВОНИТ ТОЛЬКО ИДЕАЛЬНЫЙ УДАР",
	["ON THE BEAT!"] = "В РИТМ!",
	["Tolls on the beat: %d / %d"] = "Звонов в ритм: %d / %d",
	["Only a PERFECT hit rings the bell"] = "Колокольчик звенит только от ИДЕАЛЬНОГО удара",
	-- Trials.Mourner
	["DODGES THIS ROUND"] = "УКЛОНЕНИЙ В ЭТОМ РАУНДЕ",
	["WATCH THE GLOW"] = "СЛЕДИ ЗА СВЕЧЕНИЕМ",
	["DODGED!"] = "УКЛОНИЛСЯ!",
	["HIT! LEAVE THE GLOW BEFORE IT FILLS"] = "ПОПАДАНИЕ! УХОДИ, ПОКА МЕТКА НЕ ЗАПОЛНИЛАСЬ",
	["DODGE 2 IN ONE ROUND · AGAIN!"] = "2 УКЛОНЕНИЯ ЗА РАУНД · ЕЩЁ РАЗ!",
	["ITS HEART IS OPEN!"] = "ЕГО СЕРДЦЕ ОТКРЫТО!",
	["HEART OPEN · %d s"] = "СЕРДЦЕ ОТКРЫТО · %d с",
	["STRIKE · PERFECT"] = "УДАР · ИДЕАЛЬНО",
	["ONLY A PERFECT HIT COUNTS!"] = "СЧИТАЕТСЯ ТОЛЬКО ИДЕАЛЬНЫЙ УДАР!",
	["ONLY A PERFECT!"] = "ТОЛЬКО ИДЕАЛЬНО!",
	["TOO SLOW · ONE MORE ATTACK"] = "СЛИШКОМ МЕДЛЕННО · ЕЩЁ ОДНА АТАКА",
	["THE MOURNER FALLS!"] = "ПЛАКАЛЬЩИК ПОВЕРЖЕН!",
	["DOWNED · THE GHOST PUP LIFTS YOU UP"] = "ТЫ ПОВЕРЖЕН · ПРИЗРАЧНЫЙ ЩЕНОК ПОДНИМЕТ ТЕБЯ",
	["BACK ON YOUR PAWS!"] = "СНОВА НА ЛАПАХ!",
	["COME BACK INTO THE RING"] = "ВЕРНИСЬ В КРУГ",
	["SAFE"] = "БЕЗОПАСНО",
	["Dodges this round: %d / %d"] = "Уклонений в раунде: %d / %d",
	["Step out of the glowing telegraphs"] = "Уходи из светящихся меток",
	["Its heart is open: strike it with a PERFECT hit"] = "Его сердце открыто: ударь ИДЕАЛЬНО",
}

L.Exact = {
	["This practice is part of the Underyard guide"] = "Эта тренировка — часть проводника по Поддворью",
}

L.Patterns = {}
L.Phrases = {}

-- Russian of an English string of this package (UI first, then Exact) -> string?
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" then
		return nil
	end
	return L.UI[text] or L.Exact[text]
end

return L
