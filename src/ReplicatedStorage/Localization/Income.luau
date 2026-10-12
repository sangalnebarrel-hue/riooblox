-- Russian strings for dog income, storage and mutation labels (read by DOGROTS_AutoTranslateUI).
-- Numbers stay outside the translated words: "$1.2K / min" becomes "$1.2K / мин" by pattern.
return {
	Exact = {
		["Income / min"] = "Доход / мин",
		["Income / minute"] = "Доход в минуту",
		["INCOME"] = "ДОХОД",
		["DIGS / MIN"] = "РАСКОПОК / МИН",
		["EFFICIENCY"] = "ЭФФЕКТИВНОСТЬ",
		["Finds storage"] = "Место для находок",
		["SHINY"] = "БЛЕСТЯЩИЙ",
		["CORRUPTED"] = "ИСКАЖЁННЫЙ",
		["Shiny"] = "Блестящий",
		["Golden"] = "Золотой",
		["Corrupted"] = "Искажённый",
		["Glitched"] = "Глитчевый",
		["+25 discovery slots"] = "+25 мест для находок",
		["Your dogs keep finding discoveries for longer before you sell. Finds already stored stay safe when it expires."] = "Собаки дольше находят предметы, прежде чем нужно продавать. Когда эффект закончится, уже сохранённые находки останутся.",
		["Sell your finds at the collector in your yard"] = "Продавай находки у сборщика в своём дворе",
	},
	Patterns = {
		{ "^([~%+]?%$[%d%.,]+%a*) / min$", "%1 / мин" },
		{ "^GLITCHED DOG ON THE TONGUE · (.+)$", "ГЛИТЧЕВАЯ СОБАКА НА ЛЕНТЕ · %1" },
		{ "^VOID DOG ON THE TONGUE · (.+)$", "СОБАКА ПУСТОТЫ НА ЛЕНТЕ · %1" },
		{
			"^Assigned dogs earn (%d+)%% of their income for up to (.+) while you are away%. Claim whenever you are ready%.$",
			"Назначенные собаки приносят %1%% своего дохода до %2, пока тебя нет. Забирай, когда удобно.",
		},
		{ "^x([%d%.]+) vs a plain Common$", "x%1 к обычной собаке" },
	},
	Phrases = {},
}
