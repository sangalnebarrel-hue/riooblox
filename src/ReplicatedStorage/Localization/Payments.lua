-- Russian strings for Robux purchases and the payment safety messages (payments update).
-- Read by StarterPlayer.StarterPlayerScripts.DOGROTS_AutoTranslateUI (exact match first).
local names={
	['Scout Kit']='Набор разведчика',
	['Explorer Kit']='Набор исследователя',
	['Pack Captain Kit']='Набор вожака стаи',
	['Lucky Server']='Счастливый сервер',
	['Super Lucky Server']='Очень удачный сервер',
	['Ultra Lucky Server']='Сверхудачный сервер',
	['MAX LUCK']='МАКСИМАЛЬНАЯ УДАЧА',
	['Turbo Dig Kit']='Набор быстрой копки',
	['Collector Kit']='Набор коллекционера',
	['Pocket Change']='Карманные деньги',
	['Pocket of Coins']='Горсть монет',
	['Chest of Coins']='Сундук монет',
	['Treasure Chest']='Сундук сокровищ',
	['Vault of Coins']='Хранилище монет',
	['Mega Treasure Hoard']='Огромный клад',
	['Energy Snack']='Энергетический перекус',
	['Storage Crate']='Ящик хранения',
	['Golden Biscuit']='Золотое печенье',
	['Lucky Treat']='Счастливое лакомство',
}
local exact={
	-- Purchase refusals (shown on the BUY button area before any payment).
	['Server luck is at its limit right now. Try again in a few minutes.']='Удача сервера уже на максимуме. Попробуй через несколько минут.',
	['This boost already has the most time stored; use some first']='У этого бонуса уже накоплено максимум времени; сначала используй часть',
	['Six hours already stored; use some before adding more']='Уже накоплено шесть часов; используй часть, прежде чем добавлять',
	['You already own this pack']='Этот набор у тебя уже есть',
	['Coin storage is full']='Хранилище монет заполнено',
	['Unavailable for this account']='Недоступно для этого аккаунта',
	-- Safety messages when the profile is busy saving.
	['Account is busy; retry shortly']='Аккаунт занят, попробуй ещё раз',
	['Saving your progress; retry shortly']='Сохраняем прогресс, попробуй чуть позже',
	['Profile save is busy; retry shortly']='Профиль сохраняется, попробуй чуть позже',
	-- Delivered purchases.
	['DOGROTS Supporter unlocked']='Поддержка DOGROTS открыта',
	['Golden Kennel Title unlocked']='Титул «Золотая будка» открыт',
	['Event Supporter unlocked']='Поддержка событий открыта',
	['Void Aura Title unlocked']='Титул «Аура пустоты» открыт',
}
for en,ru in pairs(names)do exact[en..' added']=ru..': получено'end
return {
	Exact=exact,
	Patterns={
		{'^1 DOG TOKEN added · spin at the DOG%-O%-MATIC$','Жетон собаки: +1 · крути в DOG-O-MATIC'},
		{'^(%d+) DOG TOKENS added · spin at the DOG%-O%-MATIC$','Жетоны собак: +%1 · крути в DOG-O-MATIC'},
		{'^(.+) ACTIVATED x(%d+) SERVER LUCK!$','%1: УДАЧА СЕРВЕРА x%2 ВКЛЮЧЕНА!'},
	},
	Phrases={},
}
