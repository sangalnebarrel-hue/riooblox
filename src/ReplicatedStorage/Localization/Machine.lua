-- Russian strings for DOG-O-MATIC (rarity-tier prizes, refusal notices, the Rainbow Rift Aurion
-- boost) and for the sealed Global event card/hints. Read by DOGROTS_AutoTranslateUI.
-- Sentences built from live odds localize themselves (RewardMachineText.L + NoTranslate).
local Exact={
	-- Prize rows (drum faces, odds board, CHANCES, token shop)
	["Common Dog"]="Обычная собака",
	["Rare Dog"]="Редкая собака",
	["Epic Dog"]="Эпическая собака",
	["Legendary+ Dog"]="Легендарная+ собака",
	["Dog Tag"]="Жетон собаки",
	["Aurion"]="Аурион",
	["40 Bones"]="40 костей",
	["Energy Snack · 15 min"]="Энергетический перекус · 15 мин",
	["COIN BAG"]="МЕШОК МОНЕТ",
	["TREASURE"]="СОКРОВИЩЕ",
	["ARTIFACT"]="АРТЕФАКТ",
	["BOOST"]="УСИЛЕНИЕ",
	["SAVED"]="СОХРАНЕНО",
	["ACTIVATING…"]="ЗАПУСК…",
	["ACTIVATING..."]="ЗАПУСК...",
	["RESETTING…"]="ПЕРЕЗАПУСК…",
	["MACHINE RESETTING…"]="АВТОМАТ ПЕРЕЗАПУСКАЕТСЯ…",
	["ULTRA RARE!  Aurion"]="СВЕРХРЕДКО!  Аурион",
	["Open DOG-O-MATIC to view reward chances"]="Открой DOG-O-MATIC, чтобы увидеть шансы наград",
	-- Refusals (server) and their actions
	["Your free DOG TOKEN is still recharging"]="Бесплатный жетон собаки ещё восстанавливается",
	["Paid random tickets are unavailable for this account; your tickets are kept"]="Платные случайные награды недоступны для этого аккаунта; твои жетоны сохранены",
	["Paid tickets are unavailable for this account. Free tickets still work."]="Платные жетоны недоступны для этого аккаунта. Бесплатные жетоны работают.",
	["Please wait for this activation to finish"]="Подожди, пока закончится эта активация",
	["Please wait before trying again"]="Подожди немного и попробуй снова",
	["Please wait"]="Подожди",
	["Move closer to DOG-O-MATIC"]="Подойди ближе к DOG-O-MATIC",
	["Your previous activation is still being processed"]="Предыдущая активация ещё обрабатывается",
	["Aurion is preparing to arrive. Please try again shortly."]="Аурион готовится к появлению. Попробуй чуть позже.",
	["Rewards are temporarily unavailable"]="Награды временно недоступны",
	["Reward pool changed; please activate again"]="Набор наград изменился; запусти автомат ещё раз",
	["Activation unavailable; please retry"]="Активация не удалась; попробуй ещё раз",
	["Use the drum at DOG-O-MATIC PLAZA"]="Используй барабан на площади DOG-O-MATIC",
	["Invalid activation"]="Неверная активация",
	["DOG-O-MATIC is loading; please retry"]="DOG-O-MATIC загружается; попробуй ещё раз",
	["Profile session unavailable"]="Сессия профиля недоступна; перезайди в игру",
	["Account is busy; retry shortly"]="Аккаунт занят; попробуй через пару секунд",
	["Loading your profile"]="Загрузка профиля",
	["MANAGE DOGS"]="МОИ СОБАКИ",
	["MY ITEMS"]="МОИ ПРЕДМЕТЫ",
	["GET TOKENS"]="ПОЛУЧИТЬ ЖЕТОНЫ",
	["TOKEN INFO"]="О ЖЕТОНАХ",
	-- Rail, overlay and token shop
	["Drum busy · your reward appears here"]="Барабан занят · награда появится здесь",
	["Your turn on the drum is next"]="Барабан сейчас закрутится для тебя",
	["Every activation uses these exact chances, for free and bought DOG TOKENS."]="Каждая активация использует именно эти шансы — и с бесплатными, и с купленными жетонами.",
	["One DOG TOKEN gives one random reward. Exact chances are shown below."]="Один жетон собаки даёт одну случайную награду. Точные шансы указаны ниже.",
	["REWARD CHANCES · EVERY TOKEN"]="ШАНСЫ НАГРАД · ЛЮБОЙ ЖЕТОН",
	["Paid tokens are delivered after Roblox confirms payment and only work where Roblox allows paid random items."]="Платные жетоны начисляются после подтверждения оплаты Roblox и работают только там, где Roblox разрешает платные случайные награды.",
	-- Rainbow Rift boost (events page)
	["NEXT RAINBOW RIFT"]="СЛЕДУЮЩИЙ РАДУЖНЫЙ РАЗЛОМ",
	-- The sealed Global Dig feature is a coming-soon global event, not "Global dig".
	["GLOBAL EVENT"]="ГЛОБАЛЬНОЕ СОБЫТИЕ",
	["Global event"]="Глобальное событие",
	["GLOBAL EVENT — COMING SOON"]="ГЛОБАЛЬНОЕ СОБЫТИЕ — СКОРО",
	["COMING SOON"]="СКОРО",
}
local Patterns={
	{"^You own the maximum of (%d+) dogs%. Sell or release a dog to spin%.$","У тебя максимум собак: %1. Продай или отпусти собаку, чтобы крутить."},
	{"^Your bag holds the maximum of (%d+) items%. Sell an item to spin%.$","В сумке максимум предметов: %1. Продай предмет, чтобы крутить."},
	{"^(%d+)%.(%d+)%% CHANCE$","%1,%2%% ШАНС"},
	{"^x(%d+) · (%d+)%.(%d+)%% CHANCE$","x%1 · %2,%3%% ШАНС"},
	{"^ULTRA RARE: Aurion  (%d+)%.(%d+)%%$","СВЕРХРЕДКИЙ: Аурион  %1,%2%%"},
	{"^RAINBOW x(%d+): Aurion  (%d+)%.(%d+)%%$","РАДУГА x%1: Аурион  %2,%3%%"},
	{"^AURION · ULTRA RARE · (%d+)%.(%d+)%%$","АУРИОН · СВЕРХРЕДКИЙ · %1,%2%%"},
	{"^AURION · RAINBOW x(%d+) · (%d+)%.(%d+)%%$","АУРИОН · РАДУГА x%1 · %2,%3%%"},
	{"^AURION x(%d+) · RAINBOW RIFT ([%d:]+)$","АУРИОН x%1 · РАДУЖНЫЙ РАЗЛОМ %2"},
	{"^AURION HOWLS · x(%d+) CHANCE$","АУРИОН ВОЕТ · ШАНС x%1"},
	{"^ENDS ([%d:]+)$","ДО КОНЦА %1"},
	{"^FREE DOG TOKEN (%d)/1$","БЕСПЛАТНЫЙ ЖЕТОН %1/1"},
	{"x(%d+) AURION CHANCE ON DOG%-O%-MATIC","ШАНС НА АУРИОНА x%1 В DOG-O-MATIC"},
	{"^([%d,]+) Coins$","%1 монет"},
	{"^([%d,]+) Coins  (%d+)%.(%d+)%%$","%1 монет  %2,%3%%"},
}
-- Odds board rows: "<prize>  12.34%".
local rows={"Common Dog","Rare Dog","Epic Dog","Legendary+ Dog","Dog Tag","40 Bones","Energy Snack · 15 min"}
for _,en in ipairs(rows)do
	local name=Exact[en]
	table.insert(Patterns,{"^"..(en:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]","%%%0")).."  (%d+)%.(%d+)%%$",name.."  %1,%2%%"})
end
return {
	Exact=Exact,
	Patterns=Patterns,
	Phrases={},
}
