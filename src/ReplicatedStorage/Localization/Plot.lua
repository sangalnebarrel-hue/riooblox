-- Russian for plot cosmetics: the MY BEST FINDS showcase (stand, prompts, editor window) and
-- plot decorations (catalog, prompts, window, server replies). Loaded by DOGROTS_AutoTranslateUI;
-- the windows (ShowcaseScreen / DecorScreen) also read UI directly through Kit.T.
local Catalog = require(script.Parent.Parent:WaitForChild("DogEconomy"):WaitForChild("DecorCatalog"))

local Exact = {
	-- World: stand, prompts
	["MY BEST FINDS"] = "МОИ ЛУЧШИЕ НАХОДКИ",
	["EDIT SHOWCASE"] = "ИЗМЕНИТЬ ВИТРИНУ",
	["DECORATE"] = "УКРАСИТЬ",
	["YOUR NEXT RECORD AWAITS"] = "ТВОЙ СЛЕДУЮЩИЙ РЕКОРД ВПЕРЕДИ",
	-- Showcase window
	["SHOWCASE"] = "ВИТРИНА",
	["Choose the finds your visitors see"] = "Выбери находки, которые увидят гости",
	["AUTO"] = "АВТО",
	["PINNED"] = "ВЫБРАНО",
	["EMPTY"] = "ПУСТО",
	["LOCKED"] = "ЗАКРЫТО",
	["REMOVE"] = "УБРАТЬ",
	["CASE"] = "ВИТРИНА",
	["CROWN CASE"] = "КОРОННАЯ ВИТРИНА",
	["YOUR FINDS"] = "ТВОИ НАХОДКИ",
	["RECORD"] = "РЕКОРД",
	["ON DISPLAY"] = "НА ВИТРИНЕ",
	["No finds yet"] = "Пока нет находок",
	["Your dogs dig up finds: the rarest ones go on display here."] = "Собаки выкапывают находки: самые редкие можно выставить здесь.",
	["Tap a find to put it in the selected case."] = "Нажми на находку, чтобы поставить её в выбранную витрину.",
	["Walk up to your showcase to change it"] = "Подойди к своей витрине, чтобы изменить её",
	["Empty cases show your best finds automatically."] = "Пустые витрины сами показывают твои лучшие находки.",
	["This case already shows your best find automatically"] = "Эта витрина уже сама показывает твою лучшую находку",
	["Choose a find you own"] = "Выбери свою находку",
	["Choose a showcase case"] = "Выбери витрину",
	-- Decor window
	["PLOT DECOR"] = "УКРАШЕНИЯ УЧАСТКА",
	["Make your yard one of a kind"] = "Сделай свой участок неповторимым",
	["BUY & PLACE"] = "КУПИТЬ И ПОСТАВИТЬ",
	["BUY"] = "КУПИТЬ",
	["SPOTS"] = "МЕСТА",
	["ALL SPOTS"] = "ВСЕ МЕСТА",
	["Walk into your yard to place decorations"] = "Зайди на свой участок, чтобы ставить украшения",
	["This spot is already empty"] = "Это место уже пустое",
	["This decoration needs a BIG spot"] = "Этому украшению нужно БОЛЬШОЕ место",
	["This decoration needs a SMALL spot"] = "Этому украшению нужно МАЛОЕ место",
	["Choose a decor spot"] = "Выбери место для украшения",
	["Unknown decoration"] = "Неизвестное украшение",
	["Not enough Coins"] = "Не хватает монет",
	["Stone"] = "Камень",
	["STONE"] = "КАМЕНЬ",
	["Choose a spot on the left, then a decoration."] = "Выбери место слева, затем украшение.",
	["Walk up to a glowing ring in your yard and press DECORATE."] = "Подойди к светящемуся кругу на участке и нажми «УКРАСИТЬ».",
}
-- Short generic words with a plot-specific meaning: read only by DecorScreen / ShowcaseScreen
-- (not merged into the global dictionary, where FREE means "БЕСПЛАТНО", OWNED "КУПЛЕНО"...).
local UI = {
	["PLACE"] = "ПОСТАВИТЬ",
	["OWNED"] = "ЕСТЬ",
	["BIG"] = "БОЛЬШОЕ",
	["SMALL"] = "МАЛОЕ",
	["FREE"] = "СВОБОДНО",
}
for _, c in ipairs(Catalog.Categories) do
	Exact[c.Name] = c.RU
end
for _, item in ipairs(Catalog.Items) do
	Exact[item.Name] = item.RU
end

return {
	Exact = Exact,
	UI = UI,
	Patterns = {
		-- Nameplate weight line on the stand.
		{ "^([%d%.,]+) kg$", "%1 кг" },
		-- Server replies.
		{ "^(.+) is on display in case (%d)$", "%1 теперь на витрине %2" },
		{ "^Case (%d) shows your best find automatically$", "Витрина %1 сама показывает твою лучшую находку" },
		{ "^The fifth case opens at yard stage (%d)$", "Пятая витрина открывается на стадии участка %1" },
		{ "^(.+) is in your showcase%. Take it out of MY BEST FINDS before selling$", "%1 стоит на витрине. Убери её из «МОИХ ЛУЧШИХ НАХОДОК», чтобы продать" },
		{ "^This find is in your showcase%. Take it out of MY BEST FINDS first$", "Эта находка стоит на витрине. Сначала убери её из «МОИХ ЛУЧШИХ НАХОДОК»" },
		{ "^(%d+) finds are in your showcase%. Take them out of MY BEST FINDS before selling$", "На витрине %1 находок. Убери их из «МОИХ ЛУЧШИХ НАХОДОК», чтобы продать" },
		{ "^(.-) · (%d+) kept in your showcase$", "%1 · %2 оставлено на витрине" },
		{ "^Unlocks at yard stage (%d)$", "Откроется на стадии участка %1" },
		{ "^Not enough Stone: (%d+) needed %(mine Limestone at your Mining Corner%)$", "Не хватает камня: нужно %1 (добывай известняк в мини-шахте на участке)" },
		{ "^Not enough Bones: (%d+) needed$", "Не хватает костей: нужно %1" },
		{ "^Buy another (.+) first$", "Сначала купи ещё: %1" },
		{ "^You already own one for every big spot$", "У тебя уже есть по одному на каждое большое место" },
		{ "^You already own one for every small spot$", "У тебя уже есть по одному на каждое малое место" },
		{ "^The price changed: (%d+) Coins now%. Check and buy again$", "Цена изменилась: теперь %1 монет. Проверь и купи снова" },
		{ "^BIG SPOT (%d+)$", "БОЛЬШОЕ МЕСТО %1" },
		{ "^SMALL SPOT (%d+)$", "МАЛОЕ МЕСТО %1" },
	},
	Phrases = {},
}
