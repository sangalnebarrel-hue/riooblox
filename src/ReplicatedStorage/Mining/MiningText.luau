-- Active Mining text. The game's source language is English and DOGROTS_AutoTranslateUI turns it
-- into Russian for ru locales; mining UI changes text often, so it picks the language itself and
-- marks its GUIs NoTranslate (see DOGROTS_AutoTranslateUI).
local Text={}

local T={
 -- server result / error codes (MiningRules: "M:KEY|arg|arg")
 STARTED={'Mining started','Добыча началась'},
 ENDED={'Stopped','Остановлено'},
 TRAIN_STARTED={'Training started','Тренировка началась'},
 MISS={'Missed!','Промах!'},
 STALE={'','',},
 HIT={'Hit! +%1','Удар! +%1'},
 PERFECT={'Perfect! +%1','Идеально! +%1'},
 CRIT={'CRIT! +%1','КРИТ! +%1'},
 BROKE={'%1 broken! +%2','Разбито: %1! +%2'},
 BROKE_STONE={'%1 broken! +%2 · +%3 🪨','Разбито: %1! +%2 · +%3 🪨'}, -- BROKE with a Stone grant (3rd arg)
 EQUIPPED={'Equipped: %1','В руках: %1'},
 BOUGHT={'Bought: %1','Куплено: %1'},
 WEIGHT_EQUIPPED={'Selected: %1','Выбрано: %1'},
 WEIGHT_BOUGHT={'Unlocked: %1','Открыто: %1'},
 TRAINED={'+%1 Strength','+%1 силы'},
 NEED_PICKAXE={'Buy the Wooden Pickaxe at the pickaxe sign first','Сначала купи деревянную кирку у таблички с киркой'},
 SESSION_OVER={'Start mining again at the ore','Подойди к руде и начни добычу снова'},
 TARGET_GONE={'That circle is gone','Этот круг уже исчез'},
 TOO_EARLY={'Too early!','Рано!'},
 TOO_LATE={'Too late!','Поздно!'},
 NOT_READY={'Too fast!','Слишком быстро!'},
 BAD_ITEM={'Unknown item','Нет такого предмета'},
 IN_ORDER={'Unlock them in order','Открываются по порядку'},
 NEED_STRENGTH={'Needs %1 Strength — train with a weight','Нужно %1 силы — потренируйся с гирей'},
 NEED_COINS={'Needs %1 Coins','Нужно %1 монет'},
 NEED_WEIGHT={'Take a weight from the rack first','Сначала возьми гирю на стойке'},
 WEIGHT_CAPPED={'This weight gives no more Strength — unlock the next one','Эта гиря больше не даёт силы — открой следующую'},
 REST={'Catch your breath…','Отдышись…'},
 BAD_ACTION={'Unknown action','Неизвестное действие'},
 -- UI
 MINING_CORNER={'MINING CORNER','МИНИ-ШАХТА'},
 PICKAXES={'PICKAXES','КИРКИ'},
 PICKAXE_SHOP={'PICKAXE MARKET','МАГАЗИН КИРОК'},
 STRENGTH={'STRENGTH','СИЛА'},
 TRAINING={'STRENGTH TRAINING','ТРЕНИРОВКА СИЛЫ'},
 TAP_SIGN={'Tap to open','Нажми, чтобы открыть'},
 PROMPT_MINE={'Mine','Добывать'},
 PROMPT_SHOP={'Open','Открыть'},
 PROMPT_TRAIN={'Train','Тренироваться'},
 OBJ_ORE={'Ore pile','Куча руды'},
 OBJ_SHOP={'Pickaxes','Кирки'},
 OBJ_RACK={'Weights','Гири'},
 WAITING_OWNER={'Waiting for an owner','Ждёт хозяина'},
 NOT_YOURS={'This is not your yard','Это не твой участок'},
 HP={'%1 / %2 HP','%1 / %2 HP'},
 HITS_TO_BREAK={'~%1 hits with your pickaxe','~%1 ударов твоей киркой'},
 EXIT={'EXIT','ВЫЙТИ'},
 COMBO={'COMBO x%1','КОМБО x%1'},
 STRENGTH_VALUE={'Strength %1','Сила %1'},
 DAMAGE={'Damage','Урон'},
 CIRCLES={'Circles','Круги'},
 CRIT_CHANCE={'Crit','Крит'},
 LUCK={'Ore luck','Удача руды'},
 COIN_BONUS={'Coins','Монеты'},
 WINDOW={'Timing','Тайминг'},
 PRICE={'Price','Цена'},
 REQUIRES={'Needs','Нужно'},
 FREE={'FREE','БЕСПЛАТНО'},
 BUY={'BUY','КУПИТЬ'},
 TAKE={'TAKE','ВЗЯТЬ'},
 CLAIM={'CLAIM','ПОЛУЧИТЬ'},
 IN_HAND={'IN HAND','В РУКАХ'},
 SELECTED={'SELECTED','ВЫБРАНО'},
 LOCKED={'LOCKED','ЗАКРЫТО'},
 NEED_MORE_STRENGTH={'NEED STRENGTH','НУЖНА СИЛА'},
 NEED_MORE_COINS={'NEED COINS','НУЖНЫ МОНЕТЫ'},
 PREVIOUS_FIRST={'BUY PREVIOUS','СНАЧАЛА ПРЕДЫДУЩУЮ'},
 YOUR_STRENGTH={'Your Strength: %1','Твоя сила: %1'},
 YOUR_COINS={'Coins: %1','Монеты: %1'},
 STONE={'Stone','Камень'},
 YOUR_STONE={'🪨 Stone: %1','🪨 Камень: %1'},
 STONE_GAIN={'+%1 🪨','+%1 🪨'},
 ORE_STONE={'+%1 🪨','+%1 🪨'},
 STONE_HINT={'🪨 Stone builds plot decor · deeper = more','🪨 Камень — для украшений участка · глубже = больше'},
 STRENGTH_BONUS={'Strength bonus +%1% damage','Бонус силы +%1% урона'},
 LIFT_HINT={'TAP / CLICK FAST TO PUSH THE WEIGHT UP','ЖМИ БЫСТРО, ЧТОБЫ ПОДНЯТЬ ГИРЮ ВВЕРХ'},
 LIFT_HINT_KEY={'or press SPACE','или жми ПРОБЕЛ'},
 LIFT={'LIFT!','ТЯНИ!'},
 REP_DONE={'Rep done!','Подход!'},
 CAP_REACHED={'Max for this weight: %1','Предел этой гири: %1'},
 NEXT_WEIGHT_HINT={'Unlock the next weight to keep growing','Открой следующую гирю, чтобы расти дальше'},
 CHOOSE_WEIGHT={'Pick a weight on the left','Выбери гирю слева'},
 GAIN_PER_REP={'+%1 per lift · up to %2','+%1 за подъём · до %2'},
 MINE_HINT={'Click each circle when the white ring reaches the GOLD ring','Жми на круг, когда белое кольцо дойдёт до ЗОЛОТОГО'},
 MINE_HINT_KEYS={'Click a circle when the white ring reaches the GOLD ring (or press SPACE)','Жми на круг, когда белое кольцо дойдёт до ЗОЛОТОГО (или ПРОБЕЛ)'},
 MINE_HINT_TOUCH={'Tap a circle when the white ring reaches the GOLD ring','Тапни по кругу, когда белое кольцо дойдёт до ЗОЛОТОГО'},
 MINE_HINT_PAD={'Press A when the white ring reaches the GOLD ring','Жми A, когда белое кольцо дойдёт до ЗОЛОТОГО'},
 SELL_HINT={'Short on Coins? Sell loot at your Collector','Не хватает монет? Продай находки Сборщику'},
 NEW_ORE={'New ore: %1','Новая руда: %1'},
 RARE_ORE={'RARE ORE: %1!','РЕДКАЯ РУДА: %1!'},
 ORE_VALUE={'Worth ~%1','Стоит ~%1'},
 NEW_FEATURE={'NEW: MINING CORNER','НОВОЕ: МИНИ-ШАХТА'},
 NEW_FEATURE_TOAST={'New! Your yard has a Mining Corner: buy a pickaxe and break ore for Coins','Новое! На участке есть мини-шахта: купи кирку и разбивай руду за монеты'},
 TUTORIAL_BUY={'Start here: buy the Wooden Pickaxe','Начни здесь: купи деревянную кирку'},
 TUTORIAL_HIT={'Hit the circles on the ore!','Бей по кругам на руде!'},
 TUTORIAL_WEIGHT={'Take the free weight and lift it','Возьми бесплатную гирю и подними её'},
 CONNECTION={'Connection problem, try again','Проблема со связью, попробуй ещё раз'},
 BUSY={'Wait a moment','Подожди немного'},
 COLLECTION={'Ores broken: %1','Разбито руды: %1'},
 STAT_LINE={'Damage %1 · %2 circle(s) · crit %3%','Урон %1 · кругов: %2 · крит %3%'},
}
Text.Table=T

-- Generic English server errors that can reach the mining UI.
local GENERIC={
 ['Please wait a moment']='Подожди немного',
 ['Your saved profile is still loading']='Профиль ещё загружается',
 ['Stand at your Mining Corner']='Подойди к своей мини-шахте',
 ['Not enough Cash or Bones']='Недостаточно монет',
 ['Cash limit reached']='Достигнут предел монет',
 ['Invalid request']='Неверный запрос',
 ['Profile session unavailable']='Сессия профиля недоступна',
 ['Account is busy; retry shortly']='Аккаунт занят, попробуй ещё раз',
}

local isRussianCache=nil
function Text.IsRussian()
 if isRussianCache~=nil then return isRussianCache end
 local ok,locale=pcall(function()
  local Players=game:GetService('Players');local LS=game:GetService('LocalizationService')
  local player=Players.LocalPlayer
  if game:GetService('RunService'):IsStudio()or not player then return LS.RobloxLocaleId end
  return player.LocaleId or LS.RobloxLocaleId
 end)
 isRussianCache=ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'or false
 return isRussianCache
end
function Text.ResetLocale()isRussianCache=nil end

local function fill(template,args)
 return (template:gsub('%%(%d)',function(i)return tostring(args[tonumber(i)]or'')end))
end

function Text.Get(key,...)
 local row=T[key];if not row then return key end
 return fill(Text.IsRussian()and row[2]or row[1],{...})
end
-- Pick between an English and a Russian literal.
function Text.L(en,ru)return Text.IsRussian()and ru or en end

-- Compact number: 1234 -> 1.2K, 95000000 -> 95M.
function Text.Short(n)
 n=math.floor(tonumber(n)or 0)
 local a=math.abs(n)
 local function f(v,s)local t=string.format('%.1f',v):gsub('%.0$','');return t..s end
 if a>=1e12 then return f(n/1e12,'T')end
 if a>=1e9 then return f(n/1e9,'B')end
 if a>=1e6 then return f(n/1e6,'M')end
 if a>=1e4 then return f(n/1e3,'K')end
 return tostring(n)
end

-- Display name of an ore / pickaxe / weight definition.
function Text.Name(def)
 if not def then return '?' end
 return Text.IsRussian()and(def.RU or def.Name or def.Id)or(def.Name or def.Id)
end

-- Turns a server message ("M:KEY|a|b" or plain English) into display text.
-- lookup: optional function(id,key)->definition used to name ore / pickaxe / weight ids.
function Text.Message(message,lookup)
 if type(message)~='string'then return tostring(message)end
 local body=message:match('^M:(.+)$')
 if not body then
  if Text.IsRussian()then return GENERIC[message]or message end
  return message
 end
 local parts=string.split(body,'|')
 local key=table.remove(parts,1)
 -- "M:BROKE|ore|coins|stone": the stone line only when the break stored some.
 local template=(key=='BROKE'and(tonumber(parts[3])or 0)>0)and'BROKE_STONE'or key
 for i,a in ipairs(parts)do
  local def=lookup and lookup(a,key)
  if def then parts[i]=Text.Name(def)elseif tonumber(a)then parts[i]=Text.Short(tonumber(a))end
 end
 return Text.Get(template,table.unpack(parts))
end
function Text.Key(message)
 return type(message)=='string'and message:match('^M:([%w_]+)')or nil
end

return Text
