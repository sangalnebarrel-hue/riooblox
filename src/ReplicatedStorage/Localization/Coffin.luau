-- Russian of THE BLACK COFFIN (ReplicatedStorage.Localization.Coffin, WP-K4; docs/halloween2/DESIGN.md §9.2-§9.7).
--   UI       self-localized texts of HalloweenClient.CoffinFX (the card, the name plate over the coffin, the banners):
--            NoTranslate labels, read through L.Translate / L.T only; never global (AutoTranslate does not load UI)
--   Exact    English replies of ServerScriptService.Halloween.Coffin (C2CoffinOpen, the shrine prompt's C2CoffinRefused,
--            the Studio preview); DOGROTS_AutoTranslateUI loads them for every label in the game, so no key here repeats
--            one another module already has ("Chapter II is closed", "Finish Chapter I first", "Not enough Bell Shards"
--            are Localization.Underyard's; "Please wait a moment", "Something went wrong, try again" the base ones)
--   Patterns none: the card formats its own numbers on NoTranslate labels
-- Glossary (shared with Localization.Underyard / HalloweenDogs2): Black Coffin = Чёрный гроб, Coffin Key = ключ от гроба,
-- Bell Shards = осколки колокола, Lucky Dust = счастливая пыль, fragments = фрагменты, showcase find = находка для
-- витрины, plot cosmetic = украшение участка, the Hollow King = Полый король, COFFIN SENSE = ЧУТЬЁ ГРОБА, CROWN OF THE
-- UNDERYARD = КОРОНА ПОДДВОРЬЯ, dog storage = хранилище собак.
local L = {}

L.UI = {
	-- the card
	["THE BLACK COFFIN"] = "ЧЁРНЫЙ ГРОБ",
	["YOUR FIRST BLACK COFFIN"] = "ТВОЙ ПЕРВЫЙ ЧЁРНЫЙ ГРОБ",
	["PREVIEW · NOTHING GRANTED"] = "ПРЕДПРОСМОТР · НИЧЕГО НЕ ВЫДАНО",
	["ALSO FROM THE BLACK COFFIN"] = "ЕЩЁ ИЗ ЧЁРНОГО ГРОБА",
	["FROM THE BLACK COFFIN"] = "ИЗ ЧЁРНОГО ГРОБА",
	["SHOWCASE FIND"] = "НАХОДКА ДЛЯ ВИТРИНЫ",
	["PLOT COSMETIC"] = "УКРАШЕНИЕ УЧАСТКА",
	["PICKAXE SKIN"] = "СКИН КИРКИ",
	["EVENT DOG"] = "СОБАКА СОБЫТИЯ",
	["EVENT DOG · %s"] = "СОБАКА СОБЫТИЯ · %s",
	["REWARD"] = "НАГРАДА",
	["LUCKY DUST"] = "СЧАСТЛИВАЯ ПЫЛЬ",
	["BELL SHARDS"] = "ОСКОЛКИ КОЛОКОЛА",
	["BONES"] = "КОСТИ",
	["COINS"] = "МОНЕТЫ",
	["COSMETIC FRAGMENTS"] = "ФРАГМЕНТЫ КОСМЕТИКИ",
	["COFFIN KEY"] = "КЛЮЧ ОТ ГРОБА",
	["CANDY"] = "КОНФЕТЫ",
	["TITLE"] = "ТИТУЛ",
	["JOINED YOUR DOGS"] = "ТЕПЕРЬ СРЕДИ ТВОИХ СОБАК",
	["NEW · ADDED TO YOUR ITEMS"] = "НОВОЕ · ДОБАВЛЕНО В ПРЕДМЕТЫ",
	["NEW · ADDED TO YOUR PLOT COSMETICS"] = "НОВОЕ · ДОБАВЛЕНО В УКРАШЕНИЯ УЧАСТКА",
	["NEW · ADDED TO YOUR PICKAXE SKINS"] = "НОВОЕ · ДОБАВЛЕНО В СКИНЫ КИРКИ",
	["KEY STORAGE FULL"] = "ХРАНИЛИЩЕ КЛЮЧЕЙ ПОЛНО",
	-- why a reward was converted (§9.4)
	["DUPLICATE"] = "ДУБЛИКАТ",
	["STORAGE FULL"] = "ХРАНИЛИЩЕ ПОЛНО",
	["NOT AVAILABLE YET"] = "ПОКА НЕДОСТУПНО",
	["CONVERTED"] = "ОБМЕНЕНО",
	-- conversion / currency chips
	["LUCKY DUST +%s"] = "СЧАСТЛИВАЯ ПЫЛЬ +%s",
	["BELL SHARDS +%s"] = "ОСКОЛКИ КОЛОКОЛА +%s",
	["FRAGMENTS +%s"] = "ФРАГМЕНТЫ +%s",
	["BONES +%s"] = "КОСТИ +%s",
	["COINS +%s"] = "МОНЕТЫ +%s",
	["COFFIN KEYS +%s"] = "КЛЮЧИ ОТ ГРОБА +%s",
	["CANDY +%s"] = "КОНФЕТЫ +%s",
	-- the bonus rows
	["CROWN OF THE UNDERYARD"] = "КОРОНА ПОДДВОРЬЯ",
	["COFFIN SENSE"] = "ЧУТЬЁ ГРОБА",
	["BONUS"] = "БОНУС",
	-- the footer
	["COFFIN KEYS %d  ·  BELL SHARDS %s"] = "КЛЮЧИ ОТ ГРОБА %d  ·  ОСКОЛКИ КОЛОКОЛА %s",
	["CONTINUE"] = "ПРОДОЛЖИТЬ",
	["OPEN AGAIN"] = "ОТКРЫТЬ ЕЩЁ",
	-- the Hollow King (the banner when no Secret arrival names the raiser)
	["✦ SECRET ✦"] = "✦ СЕКРЕТ ✦",
	["%s RAISED THE HOLLOW KING"] = "%s ПРОБУДИЛ ПОЛОГО КОРОЛЯ",
}

L.Exact = {
	["You need a Coffin Key"] = "Нужен ключ от гроба",
	["Come closer to the Black Coffin"] = "Подойди ближе к Чёрному гробу",
	["Make room in your dog storage first"] = "Сначала освободи место в хранилище собак",
	["The Black Coffin opens"] = "Чёрный гроб открывается",
	["Coffin preview"] = "Предпросмотр гроба",
}

L.Patterns = {}

L.Phrases = {}

-- Russian of a coffin text (UI, then Exact, then the first matching pattern) or nil
function L.Translate(text: string, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local hit = L.UI[text] or L.Exact[text]
	if hit then
		return hit
	end
	for _, rule in ipairs(L.Patterns) do
		local ok, out, n = pcall(string.gsub, text, rule[1], rule[2])
		if ok and n > 0 and out ~= text then
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
