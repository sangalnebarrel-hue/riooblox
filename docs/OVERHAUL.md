# DOGROTS — большая переработка: общие контракты

Документ описывает то, на что опираются все системы переработки (`docs/OVERHAUL_PLAN.md` §2). Решения и порядок работ — в плане; здесь — точные API, имена атрибутов и правила, которые каждая новая фича обязана соблюдать.

## Контракты для систем переработки

Серверный фундамент волны 0 (`docs/OVERHAUL_PLAN.md` §2.1). Новые фичи подключаются через эти контракты и **не правят** `Runtime.Request` и `Runtime.Project`.

### 1. Хуки `FeatureRegistry`

Feature-модуль — это `ServerScriptService/Economy/Features/<X>.luau`. Реестр подхватывает его сам. Полное описание полей — в шапке `Economy/FeatureRegistry.luau`.

**Хуки данных** (внутри транзакции профиля; чистые функции, без yield и без обращений к миру):

| Поле | Когда вызывается | Что делает |
|---|---|---|
| `Name`, `Order` | при загрузке | имя для логов; порядок (меньше — раньше, по умолчанию 100) |
| `Normalize(R,p,now)` | в конце `Rules.Normalize`, в каждой транзакции | создаёт `p.<X>={Version=1,…}`, лечит типы, обрезает по капу |
| `Validate(R,p)` | в конце `Rules.Validate` | только структура; никогда не отклоняет то, что лечит `Normalize` |
| `Action(R,p,action,a,now,random)` | из `Rules.Action` | `nil` — не моё действие; иначе `message[, extra]`. Действие из `Actions` получает **только его владелец** и обязан ответить (`nil` — отказ `Unknown action`); необъявленные имена, как раньше, предлагаются всем фичам по `Order` |
| `Snapshot(R,p,view,now)` | в `Runtime.Snapshot` (в pcall) | кладёт лёгкие данные в `snapshot.Features.<Name>` |

**Хуки запроса** (`Runtime.Request`, remote `DogEconomyRequest`). Они действуют на действия, которые фича перечислила в `Actions`:

| Поле | Что делает |
|---|---|
| `Actions={Name=true,…}` | действия фичи. `Registry.Owner(action)` возвращает фичу-владельца или `nil`. Тест `tests/feature_hooks.luau` падает, если два модуля объявили одно имя или имя совпало с устаревшим действием. Имя с зарезервированным префиксом (`Registry.ReservedPrefixes`, сейчас `Mining`) реестр не регистрирует |
| `Cost(action) -> число` | цена запроса в корзине токенов, от `Registry.MinCost = 0.25` до 8 (по умолчанию 1; корзина на 8 токенов, пополнение 1,5 в секунду, общая для всех remote). Цена вне диапазона (0, NaN, не число) считается за 1, с warn: бесплатный запрос снял бы ограничение частоты с remote, который запускает транзакцию и `Refresh` |
| `Gate(player,action,a,Runtime)` | проверки мира **до** транзакции: близость к витрине или пульту, свой участок. **Пропускают только `nil` и `true`.** Отказ — `Rules.Check(false,'…')`, возврат строки с причиной или `false[, причина]`: однострочный `return Access.CanUse(player, yard, anchor)` — уже рабочий гейт. Любое другое значение (таблица, число) — тоже отказ, с warn. Отказ без своей причины — `Registry.GateRefusal` = `"You cannot do that here"` (RU в `Localization/ServerCore.luau`). Булев гейт должен возвращать именно булево: `return yard ~= nil and Access.CanUse(…)`, а не `yard and …` (при `yard == nil` это `nil`, то есть «пропустить») |
| `Request(player,action,a,receiptId,Runtime) -> ok,result` | полностью свой путь (как `LabService.Request`). Без него действие идёт `Engine:Action → Rules.Action → Registry.Action` |
| `Refresh=true\|false` (или `{[action]=bool}`) | вызывать ли `Runtime.Refresh(player)` после успеха (по умолчанию да). `false` — только для действий, которые не меняют сохранённый профиль (каталоги, оценки, шаги в RAM), или если `Request` фичи сам обновляет то, что изменил (например, обоих участников обмена). Без `Refresh` не запускаются и хуки `Project` |
| `Reply='Snapshot'\|'Patch'\|'None'` (или `{[action]=режим}`) | что получает клиент при успехе: полный `StateSnapshot` (как раньше), `StatePatch` или ничего. `Reply` не зависит от `Refresh` |
| `Patch(player,action,result,p) -> таблица` | лёгкий ответ для `Reply='Patch'`: **новое значение `snapshot.Features.<Name>`** (то же, что кладёт `Snapshot`). Ответ содержит `StatePatch = {Features = {[<Name>] = patch}}`, поэтому клиент сливает патчи всех фич одинаково: заменяет `snapshot.Features[<Name>]`. `p` — `Runtime.Views` (обновлённый, если не `Refresh=false`). Если `Patch` упал или его нет — отправляется полный снимок |
| `ProjectWorld(player,p,Runtime)` | мировая фаза `Runtime.Project`: **до** `PlotDevelopment.Reconcile`, `Kennels.Reconcile` и `PlotShowcase.Reconcile`. Для геометрии участка, на которой стоят собаки и предметы (полы глубокой шахты F5 — до посадки собак в будки). Правила те же, что у `Project` |
| `Project(player,p,Runtime)` | в конце каждого `Runtime.Project`. Публикует атрибуты игрока и участка — **только при изменении значения**. У обоих `Project`-хуков у каждой фичи свой pcall; ошибка — warn не чаще раза в 30 с |

Порядок в `Runtime.Request` для действия фичи:

1. общая проверка: корзина (`Cost`), `Ready`, `clean` (глубина ≤3, ≤30 элементов, строки ≤120), 32-hex `requestId`;
2. `Gate`;
3. `Request` фичи или `Engine:Action`;
4. при успехе — `Runtime.Refresh(player)` (значит, и `ProjectWorld`/`Project` всех фич), если фича не объявила `Refresh=false`, затем ответ по `Reply`. После отказа ничего не обновляется.

Порядок `Runtime.Project`: атрибуты игрока и `DogInventory` → `ProjectWorld` всех фич → `PlotDevelopment` → `Kennels` → `PlotShowcase` → `Project` всех фич. Фичи сортируются по `Order` внутри каждой фазы.

Фича без новых полей работает ровно как раньше. Её действие, не перечисленное в `Actions`, проходит устаревшей веткой `engine:Action` и получает полный снимок.

**Правила имён.** Имя действия уникально, с префиксом фичи, не длиннее 40 символов. Префикс `Mining` зарезервирован за мини-шахтой: `Runtime.Request` проверяет владельца-фичу раньше ветки мини-шахты, поэтому фича с действием `Mining…` обошла бы проверку расстояния, RAM-проверку ударов и `RefreshMining`. Чтобы этого не случилось, `Registry.Add` не регистрирует такие имена (warn и строка в `Registry.Collisions` с `Owner='Runtime'`), а `tests/feature_hooks.luau` сверяет `Registry.ReservedPrefixes` с исходником `Runtime.Request`. Намеренный перехват устаревшего имени (`DexClaim` у `Dogdex`) записывается в `TAKEOVERS` теста.

**Уже объявлены:** `Settings` → `SettingsSave`; `UpgradeTree` → `TreeUpgrade`, `Upgrade`; `Dogdex` → `DexClaim`; `Equipment` → `EquipmentOpenCase`, `EquipArtifact`, `UnequipArtifact`, `EquipAccessory`, `UnequipAccessory`, `SalvageEquipment`, `LockEquipment`.

Пример фичи с хуками:

```lua
local F = { Name = "Showcase", Order = 60 }
F.Actions = { ShowcaseSet = true }
F.Reply = "Patch"
function F.Cost(_action) return 1 end
function F.Gate(player, _action, a, Runtime)
	-- мир: игрок стоит у своего постамента (false — отказ с этой причиной)
	return nearPedestal(player, a.Slot) == true, "Stand at your showcase"
end
function F.Normalize(R, p, now) ... end
function F.Validate(R, p) ... end
function F.Action(R, p, action, a, now, random) ... end
function F.Snapshot(R, p, view, now) view.Showcase = viewOf(p) end
-- ответ: StatePatch = {Features = {Showcase = viewOf(p)}}
function F.Patch(_player, _action, _result, p) return viewOf(p) end
function F.Project(player, p, Runtime) ... end -- атрибуты участка, только при изменении
return F
```

API реестра для тестов и инструментов: `Registry.Add(feature)` (регистрация; повтор имени действия оставляет первого владельца и пишет строку в `Registry.Collisions`), `Registry.Owner`, `Registry.Cost`, `Registry.Gate`, `Registry.Refresh`, `Registry.Reply`, `Registry.Patch`, `Registry.ProjectWorld`, `Registry.Project`, `Registry.Modules`, константы `Registry.MinCost`, `Registry.GateRefusal`, `Registry.ReservedPrefixes`.

### 2. Общие remote: `ReplicatedStorage/Net/Remotes.luau`

Сборка не умеет создавать remote, поэтому их создаёт сервер во время работы, в папке `ReplicatedStorage.DOGROTS_Net`.

| Вызов | Результат |
|---|---|
| `Remotes.Event(name, timeout?)` | `RemoteEvent` |
| `Remotes.Function(name, timeout?)` | `RemoteFunction` |
| `Remotes.Unreliable(name, timeout?)` | `UnreliableRemoteEvent`; если такого класса нет — `RemoteEvent` |

* **Сервер:** находит или создаёт remote (папку — один раз). Никогда не возвращает `nil`. Имя, занятое remote другого вида, — ошибка.
* **Клиент:** ждёт remote сервера через `WaitForChild` (`timeout` секунд, по умолчанию `Remotes.Timeout = 30`). Если не дождался — `nil` и понятный warn. Вызывающий код обязан обработать `nil`.
* **Имя:** буква, затем буквы, цифры или `_`, не длиннее 50 символов. Другое имя — ошибка.
* Каждый `OnServerEvent`/`OnServerInvoke` проверяет типы аргументов и вызывает `Runtime.Allow(player, cost)`.
* Сервер → один игрок по-прежнему проще через `Runtime.PushTo(player, kind, data)` (клиент: `Net.OnPush(kind, fn)`). Свой remote нужен для вещания многим или для «ненадёжного» канала эффектов.

### 3. Настройки игрока: `Features/Settings` + `ReplicatedStorage/SettingsConfig`

Схема (ключи, типы, умолчания) — в `ReplicatedStorage/SettingsConfig.luau`, её читают и сервер, и клиент.

| Ключ | Значения | По умолчанию | Атрибут игрока |
|---|---|---|---|
| `Quality` | `'Auto'`, `'High'`, `'Medium'`, `'Low'` | `'Auto'` | `Setting_Quality` |
| `ReducedMotion` | `true`/`false` | `false` | `Setting_ReducedMotion` |
| `UIVolume` | число 0…1 (хранится с шагом 0,01) | `0.8` | `Setting_UIVolume` |
| `SFXVolume` | число 0…1 | `0.8` | `Setting_SFXVolume` |
| `MusicVolume` | число 0…1 | `0.6` | `Setting_MusicVolume` |
| `TitleDisplay` | `'All'`, `'Mine'`, `'Off'` | `'All'` | `Setting_TitleDisplay` |
| `TradeRequests` | `'All'`, `'Off'` | `'All'` | `Setting_TradeRequests` |
| `HideUIHint` | `true`/`false` | `true` | `Setting_HideUIHint` |

* **Сохранение:** `p.Settings={Version=1, <ключ>=значение…}`. Ключ создаёт `Normalize` фичи (в `R.Profile` его нет). `Normalize` лечит каждый известный ключ: неверный тип или вариант — умолчание; число зажимается в 0…1 и округляется. Ключи более поздней сборки сохраняются как есть (до 16 маленьких скаляров), `Version` не понижается.
* **Действие** `SettingsSave` (стоит 0,5 токена, `Reply='Patch'`):
  * `{Key=k, Value=v}` — одна настройка;
  * `{Values={[k]=v,…}}` — несколько сразу: сохраняются все или ни одна;
  * ответ: `"Settings saved"`, `StatePatch={Features={Settings={…все настройки…}}}` (новое `snapshot.Features.Settings`), полного снимка нет;
  * отказы: `Choose a setting`, `Unknown setting`, `Invalid value for this setting`, `Too many settings` (RU — `Localization/ServerCore.luau`).
* **Клиент** читает `snapshot.Features.Settings` и атрибуты `Setting_<Key>`. Атрибуты пишет `Project` фичи, только при изменении. Когда приходит ответ на `SettingsSave`, атрибуты уже обновлены.
* **Сервер** читает одно значение через `Features.Settings.Get(p, key)` (безопасно к `nil`). Пример для F6: `Settings.Get(p, 'TradeRequests') == 'Off'`. Схема клиента: `SettingsConfig.Read(settings, key)`, `SettingsConfig.Attribute(key)`, `SettingsConfig.Valid(key, value)`, `SettingsConfig.Heal(key, value)` (для неизвестного ключа — `nil`).

### 4. Редкость находок: `ReplicatedStorage/ItemRarity.luau`

Одна редкость находки для всех экранов, карточек, витрины и моделей. Правило то же, что у цены: `ItemValuation.Rarity(def)`. Класс `Secret` — всегда Secret, остальное — по `BaseDropChance` против `ItemValueConfig.Rarity`. Цены не менялись.

| API | Что возвращает |
|---|---|
| `ItemRarity.Tiers` | `{"Common","Uncommon","Rare","Epic","Legendary","Secret"}`, от низшей |
| `ItemRarity.Of(x)` | редкость по `ItemId`, определению или находке (`{ItemId=…}`); `nil` — неизвестный предмет |
| `ItemRarity.Order(tier)` | 1…6, для неизвестной — 0 |
| `ItemRarity.Color(tier)` | `Color3`, **те же значения**, что `Kit.Theme.ItemRarity` (проверяет `tests/item_rarity.luau`); для неизвестной — цвет Common |
| `ItemRarity.Label(tier, lang?)` | `"LEGENDARY"`, при `lang=="ru"` — `"ЛЕГЕНДАРНАЯ"` (`ItemRarity.LabelsRU`, женский род под «находку») |

Мутация — отдельная ось (`Kit.Theme.Mutation`): она меняет цену, но не редкость. Если клиентская ветка поменяет `Kit.Theme.ItemRarity`, нужно так же поменять `ItemRarity.Colors`, иначе тест упадёт.

**Распределение 108 предметов каталога** (`tests/item_rarity.luau` печатает итог):

| Глубина | Common | Uncommon | Rare | Epic | Legendary | Secret | Всего |
|---|---|---|---|---|---|---|---|
| 1 | 7 | 6 | 4 | 2 | 1 | 0 | 20 |
| 2 | 5 | 4 | 6 | 4 | 2 | 0 | 21 |
| 3 | 5 | 6 | 4 | 2 | 3 | 1 | 21 |
| 4 | 4 | 5 | 5 | 3 | 3 | 1 | 21 |
| 5 | 2 | 5 | 5 | 4 | 6 | 3 | 25 |
| **Всего** | **23** | **26** | **24** | **15** | **15** | **5** | **108** |

Secret: `the_cube`, `null`, `unknown_question`, `normal_bone` (класс Secret) и `huge_statue` (класс World Find, шанс 1e-6).

### 5. Защита находок: `Economy/ItemProtection.luau`

Один реестр причин, по которым находка должна остаться у владельца. Продажи и передачи спрашивают его, а не проверяют флаги каждой системы сами.

| API | Что делает |
|---|---|
| `Register(name, fn, contexts?)` | `fn(p, uid, item) -> причина\|nil`. Чистая и дешёвая: выполняется в транзакции для каждой находки. `contexts` — подмножество `{Sell=true, Transfer=true}`; `nil` — все. Повторная регистрация имени заменяет защиту |
| `Reason(p, uid, context?, ignore?)` | первая причина в порядке регистрации или `nil`. `context=nil` спрашивает все защиты; `ignore={[name]=true}` пропускает защиты по имени |
| `IsProtected(p, uid, context?, ignore?)` | `true`/`false` |

Контексты:

* `'Sell'` — любая продажа коллекционеру: `BulkSell`, `SellQuote`, `NPCSell`, а также `Runtime.Snapshot.SellableItems`/`ProtectedItems` и `YardCommerce.CanSell`. Одна находка или много — протокол их не различает (кнопка «SELL» у одной находки и «SELL ALL» при одной находке шлют один и тот же `BulkSell {Uids={uid}}`), поэтому контекст один;
* `'Transfer'` — находка уходит из профиля: предложение обмена, лот рынка, катализатор лаборатории (`ItemRules.Get(p, uid, true, ignore?)`).

Защита, которая упала с ошибкой, **защищает** находку (fail closed).

Встроенная защита `Favorite` (`item.Favorite == true`, причина `"Favorite finds are kept; unfavorite to sell"`) действует только для `'Sell'`.

Где спрашивается:

* `BulkSell {Uids, IncludeFavorites?}`. Защищённые находки пропускаются, ответ содержит `SkippedProtected` (сколько осталось). Избранное продаётся только при `IncludeFavorites == true` — и при одном uid тоже; другие защиты флаг не снимает. Если продавать нечего, потому что всё защищено, отказ — с причиной защиты. `ValidBulkArgs` принимает только булев `IncludeFavorites`.
* `SellQuote {All | Uids, IncludeFavorites?}` не берёт защищённые находки в оценку (`SkippedProtected`). `NPCSell` проверяет защиту ещё раз в момент продажи.
* `YardCommerce.CanSell(p, uid, ignore?) -> true | false[, причина]` — то же решение, что у продажи без `IncludeFavorites` (`ignore={Favorite=true}` — с ним).
* `Runtime.Snapshot.SellableItems` — то, что продажа заберёт без `IncludeFavorites` (во время обмена — пусто). `Runtime.Snapshot.ProtectedItems = {[uid] = причина}` — почему остальные находки остаются: интерфейс показывает причину и для избранного предлагает `IncludeFavorites` после подтверждения.
* `ItemRules.Get(p, uid, true, ignore?)` отказывает с причиной защиты. Через неё идут обмен (`Engine:Trade` Offer и коммит), рынок (`Market:Create`), катализаторы лаборатории. `ignore={[защита]=true}` — явное решение игрока снять конкретную защиту (Trade 2.0: `I.Get(p, uid, true, offer.Allow)`); остальные защиты действуют.

Защита витрины (F3) подключается одной строкой:

```lua
require(script.Parent.Parent.ItemProtection).Register("Showcase", function(p, uid)
	return Showcase.Has(p, uid) and "This find is on your showcase" or nil
end)
```

Строку причины нужно перевести в `Localization/<Feature>.luau`.

### 6. Совместимость сохранений: `tests/save_compat.luau`

Фикстуры:

* новый игрок;
* профиль «до переработки», собранный сегодняшними `Rules`: собаки (варианты, будки, избранное, замок, история владельцев), находки, ДНК лаборатории, шахта, косметика, скины участка; ключей переработки в нём нет;
* повреждённые поля фич;
* поля «будущей версии» и неизвестный ключ верхнего уровня;
* «кит»: 220 собак и 1000 находок, JSON 1,11 МБ при лимите теста 2 МБ.

Проверки:

* `Rules.Normalize` дважды даёт то же самое;
* `Rules.Validate` проходит;
* JSON туда и обратно ничего не теряет (числа — с допуском 1e-12: кодировщики JSON, и Roblox тоже, не обещают последний бит double);
* данные каждой фичи на месте;
* `Engine:Join → Leave → FlushProfile` на хранилище в памяти, после чего сохранённая запись снова проходит `Validate`.

**Каждая новая фича добавляет запись в таблицу `FEATURES`** этого теста (по `Name`). Пока записи нет, тест падает. Поля записи:

* `Key` — ключ верхнего уровня, который создаёт `Normalize`;
* `Check(p, fixture)` — проверки нормализованных данных;
* `Corrupt(p)` — как испортить данные фичи (`Normalize` должен вылечить);
* `Future(p)` — данные более поздней версии (`Normalize` должен сохранить);
* `Fixture(p, W)` — свои данные в профиль «до переработки».

Тестовый мир `tests/lib/server_world.luau` — настоящий `Economy.Runtime` на хранилище в памяти. Его используют `feature_hooks`, `settings`, `item_protection`, `hot_paths`, `trade_hotfix` и `save_compat`; новые серверные тесты собираются на нём же.

### 7. Что изменилось в горячих местах

* **`InventoryRevision`** растёт только при реальном изменении того, что показывает инвентарь (`Economy/InventorySignature.luau`). Отслеживается:
  * набор находок, у каждой — `Favorite`, `Tradeable`, флаги `RecordAtCreation`, «идёт проверка рекорда»;
  * набор собак, у каждой — `DogId`, `State`, `AssignedSlot`, `Variant`, `Locked`, `Favorite`, `Mastery`, `AscensionLevel`;
  * Lucky Blocks и `LuckyCredits`;
  * `Equipment.Rev`, собаки на витрине хранилища, слои, улучшения хранилищ, резервы, лоты, старые стопки добычи.

  Работа собаки (`NextWorkAt`, `WorkSequence`, `MasteryXP`, `LastYield`…) и доход ревизию больше не двигают. Открытый инвентарь перестал скачивать полный Snapshot каждые 1,5–3 с. `RefreshSale` двигает ревизию один раз. `UpgradeTreeScreen` теперь слушает `leaderstats.Coins` напрямую: раньше живую цену монет ему приносил каждый тик `InventoryRevision`.
* **`LabInfo` / `LabPreview`** (только чтение) больше не вызывают `Runtime.Refresh`.
* **`DogInventory`.** Атрибуты собаки пишутся только при изменении поля: у каждой собаки есть тень последних записанных значений. `OwnerHistory` кодируется в JSON заново, только когда меняется длина истории, `EarlierTransfers` или последняя строка (история только дописывается). Тени лежат в обычной таблице `[player][dogUid]`, а не в слабой таблице с ключами-инстансами: Roblox может собрать Lua-обёртку живого инстанса, и тень пропала бы. Тень держит свою запись: пересозданная запись (или новый `Player` после быстрого перезахода) пишется целиком. Тень удаляется вместе с собакой и на `PlayerRemoving`.
* **Пустой опрос `Menus`.** Раньше полный Snapshot запрашивался раз в 15 с, даже без открытого меню, — только ради плашки «WHILE YOU WERE AWAY». Теперь сервер публикует атрибут `OfflineEarningsRevision` (`<Revision>:<LastReturnAt>` из `p.OfflineEarnings`; меняется при возвращении с офлайн-монетами и при получении). Меню без открытой страницы запрашивает Snapshot только когда метка сдвинулась. Неудачный запрос повторяется.
* **Повтор входа** (`Runtime.JoinRetry = {Attempts=6, Delay=2.5}`, `Runtime.JoinRetryable(message)`). Раньше повторялась только ошибка «another server». Теперь повторяются и «busy», `DataStore…`, «Storage unavailable», «pending/retry», «expired before commit». Профиль, который не проходит проверку, кикает сразу, как и раньше.
* **Обмен, срочное исправление** (полный Trade 2.0 — F6):
  * `Confirm` фиксирует версию и копию предложений и ставит `t.Committing=true` **до** yield в `PaidPolicy.Allowed`. После него версия проверяется снова, коммит идёт из копии, `Committing` снимается при любом выходе;
  * `Offer`, пришедший во время коммита, получает отказ `Trade is committing`. Тест `tests/trade_hotfix.luau` воспроизводит гонку: на старом коде игрок A отдавал собаку за 0 монет;
  * повторный `Ready` на той же версии не перезапускает 8-секундный таймер проверки;
  * шаг `Trade` обновляет только двух участников, а не весь сервер (`RefreshAll` убран из этой ветки).

### 8. Известные ограничения

* **Старые кнопки «SELL» (осознанное изменение).** `CollectorScreen`, `InventoryController` и `ServiceMenusController` продают одну находку через `BulkSell` с одним uid. До переработки так продавалась и избранная находка; теперь её нужно сначала снять с избранного (сервер ответит «Favorite finds are kept; unfavorite to sell»). Иначе нельзя: «SELL ALL FINDS» при единственной находке шлёт тот же запрос, и избранное ушло бы без подтверждения. `SellableItems` и `ProtectedItems` говорят ровно то же, что сервер. Новый инвентарь F2 передаёт `IncludeFavorites=true` после явного подтверждения. Предсказание продажи в старом клиенте на мгновение прячет избранное, пока не придёт следующий Snapshot: ревизия инвентаря сдвигается, и клиент его запрашивает.
* **`StatePatch.Features` на клиенте.** Кэш `Modules/Net` пока обновляется только из `StateSnapshot`, а `Menus` применяет только поля продаж. Клиентский фундамент сливает `StatePatch.Features[<Name>]` в `snapshot.Features[<Name>]` кэша. До этого окно настроек читает `StatePatch.Features.Settings` или атрибуты `Setting_<Key>`.
* **Ловушка валидатора (не новая).** Если `p.Upgrades` целиком потерян (повреждён не по значениям, а целиком), `PlotRules.Validate` отклоняет собак в будках, которые стали закрытыми, и вход падает. Кроме того, `OnboardingRules.Observe` читает `p.Upgrades` до того, как его лечит `UpgradeTree`. Поэтому `save_compat` портит только значения внутри таблицы.
* **Клиентская часть `Remotes`** проверена на фейковых инстансах. Реальное ожидание `WaitForChild` проверяется в Studio.


## Клиентский фундамент

Волна 0 переработки, ветка B (`docs/OVERHAUL_PLAN.md` §2.2). Здесь общие клиентские помощники, которыми пользуются все следующие фичи: уровень качества и бюджеты, общий планировщик, пулы, LOD, строитель мира из спецификаций, звуки интерфейса, токены Kit и глифы. Плюс инструмент `tools/preview`, который рисует раскладки без Roblox Studio.

### Что где лежит

| Файл | Что делает |
|---|---|
| `ReplicatedStorage/Perf/Quality.luau` | Уровень качества High / Medium / Low, «уменьшение движения», бюджеты по уровню |
| `ReplicatedStorage/Perf/Scheduler.luau` | Один общий Heartbeat для всех периодических задач клиента |
| `ReplicatedStorage/Perf/Pool.luau` | Пул повторяемых объектов |
| `ReplicatedStorage/Perf/Lod.luau` | Уровни детализации по дистанции и пирамиде видимости, путь через тег `DOGROTS_Lod` |
| `ReplicatedStorage/Perf/Maid.luau`, `Perf/Signal.luau` | Уборка соединений и простой сигнал. `Kit/Maid` и `Kit/Signal` теперь пересылают сюда |
| `StarterPlayerScripts/PerfBootstrap.client.luau` | Запускает `Quality` и путь тегов `Lod` сразу после входа |
| `ReplicatedStorage/World/Spec.luau` | Чистые спецификации деталей и преобразования (без Instance) |
| `ReplicatedStorage/World/Builder.luau` | Строит модель из спецификаций, отдельно от мира, Parent одним действием |
| `ReplicatedStorage/UISound.luau` | Звуки интерфейса: именованные сигналы, пул голосов, шины громкости |
| `ServerScriptService/AudioBootstrap.server.luau` | Создаёт `SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient}` при старте сервера |
| `StarterGui/ScreenGui/Modules/Kit/Sound.luau` | Связка Kit → UISound (кнопки, окна, вкладки) |
| `tools/preview/` | Экспорт раскладок и регионов плейса в JSON и рендер в PNG (three.js) |
| `tests/perf.luau`, `tests/world.luau`, `tests/ui_assets.luau`, `tests/perf_lint.luau` | Тесты Lune этой волны |

### Perf.Quality — один уровень качества

```lua
local Quality = require(ReplicatedStorage.Perf.Quality)
Quality.Tier()                  --> "High" | "Medium" | "Low" — уровень, который действует сейчас
Quality.Preference()            --> "Auto" | "High" | "Medium" | "Low"
Quality.Reduced()               --> true, если включено уменьшение движения
Quality.Budget("Lights")        --> бюджет для текущего уровня
Quality.Budget("Lights", "Low") --> бюджет для заданного уровня
Quality.Changed:Connect(function(tier, reduced) end)            -- сменился уровень или «движение»
Quality.PreferenceChanged:Connect(function(preference, tier) end) -- явный выбор игрока (не сторож FPS)
Quality.SetPreference("Low")    -- выбор на сессию
Quality.Claim("Highlights", owner, 3) --> сколько выдано (0…3)
Quality.Release(owner)          -- снять все заявки владельца (или Release(owner, "Highlights"))
Quality.Claimed("Lights"); Quality.Available("Lights"[, tier])
Quality.State()                 -- отладка: все входы и итог
```

**Откуда берётся уровень.** Побеждает последний явный выбор:

1. атрибут игрока `Setting_Quality` (сохранённая настройка; её публикует сервер, ветка A);
2. атрибут `WorldEventFX`, если его записал кто-то другой (кнопка PAWPAD «World Event FX»);
3. иначе `Auto`:
   * `UserGameSettings().SavedQualityLevel`: 1–3 → Low, 4–6 → Medium, 7–10 и «Автоматически» → High;
   * сенсорный экран без клавиатуры — не выше Medium (телефоны начинают с Medium);
   * сторож FPS: первые 15 с не считаются; если средний FPS за блок 10 с ниже 40, уровень снижается на ступень (не больше двух ступеней); через 60 с стабильных 55+ FPS — повышается обратно. Если после повышения в течение 60 с снова пришлось снижать, время возврата удваивается (до 600 с). Пока окно игры не в фокусе (Roblox тогда сам режет FPS), замеры не считаются; один замер длиннее 5 с (клиент стоял) отбрасывается.

Явный выбор (High/Medium/Low) сторож и устройство не меняют. Окно настроек (F2) вызывает `SettingsSave` на сервере; сервер возвращает значение атрибутом `Setting_Quality`.

**Ступень сторожа — не выбор игрока.** Она меняет `Tier()`, `WorldEventFX` и вызывает `Changed`, но не `PreferenceChanged`. `WorldEventController` перезапускает идущий ивент только по `PreferenceChanged` (PAWPAD, окно настроек) и только если уровень правда другой; ступень сторожа во время ивента его не трогает (иначе заставка и все эффекты пересобирались бы каждые 10–60 с, как раз когда FPS и так низкий). Следующий ивент начинается уже на новом уровне.

**Уменьшение движения** = настройка доступности Roblox (`GuiService.ReducedMotionEnabled`) **или** сохранённая настройка `Setting_ReducedMotion`. Переключатель PAWPAD «Motion» (атрибут `ReducedMotion`) — явный выбор на эту сессию: он главнее обоих, в том числе может выключить уменьшение, включённое в Roblox. Новое значение `Setting_ReducedMotion` (окно настроек) снова отменяет переключатель. Сохранённое `false` само по себе настройку Roblox не выключает, поэтому значение по умолчанию с сервера доступность не ломает. Окно настроек может показать «включено в Roblox» по `Quality.State().SystemReduced`.

**Совместимость.** Старые скрипты (около 12 штук) читают атрибуты напрямую. `Quality` сам пишет атрибуты игрока, только когда значение меняется:

* `WorldEventFX = Tier()`;
* `LowFX = (Tier() == "Low")` — раньше этот атрибут читали, но не ставил никто;
* `ReducedMotion = Reduced()`.

Своих записей модуль не принимает за выбор игрока. Все `require` на клиенте делят одно состояние; первый вызов запускает модуль.

**Бюджеты (`Quality.Budgets`, §4 плана).**

| Ключ | High | Medium | Low | Что ограничивает |
|---|---|---|---|---|
| `Lights` | 24 | 16 | 8 | видимые источники света в районе (WDQ и фичи) |
| `LightRadius` | 160 | 120 | 85 | дальше этого свет выключен (стады) |
| `Particles` | 64 | 28 | 4 | частиц в секунду на весь район (= `WorldEventConfig.FX`) |
| `EmitterRate` | 8 | 5 | 2 | частиц в секунду на один фоновый эмиттер |
| `EmitterRadius` | 210 | 150 | 90 | дальше этого фоновые эмиттеры выключены |
| `Burst` / `BurstScale` | 300 / 1 | 150 / 0,5 | 45 / 0,15 | «вау-всплеск» за 4 с (F12, F7) |
| `Debris`, `Dogs` | 52, 14 | 24, 8 | 8, 3 | обломки и собаки ивентов (= `WorldEventConfig.FX`) |
| `Highlights` | 8 | 4 | 2 | Highlight одновременно, все системы вместе |
| `Viewports` | 12 | 8 | 4 | видимые ViewportFrame |
| `Arrows` | 32 | 20 | 12 | стрелки пути (F1) |
| `Titles` | 12 | 8 | 8 | титулы над игроками (F10) |
| `DecorParts` / `ShowcaseParts` / `MineParts` | 300 / 150 / 400 | те же | те же | деталей на участок: декор (F8), витрина (F3), видимый уровень шахты (F5) |
| `LabParts` / `LabLights` / `LabEmitters` | 600 / 6 / 4 | те же | те же | машина мутаций (F12) |
| `LodNear` / `LodFar` | 160 / 320 | 120 / 240 | 85 / 160 | дистанции LOD по умолчанию |
| `FeatureMs` | 0,3 | 0,3 | 0,2 | Lua-время одной фичи за кадр |

**Общие бюджеты — заявки.** `Lights`, `Particles`, `Highlights`, `Viewports` (и любой другой ключ) тратят несколько систем сразу. Система, которая сама включает свет, эмиттеры, Highlight или ViewportFrame (всё `FXManaged`, витрина, лаборатория, превью), сначала делает `Quality.Claim(key, owner, n)` и включает не больше выданного. Новая заявка того же владельца заменяет прежнюю; выдаётся не больше остатка после других владельцев. `WorldDetailQuality` заявок не делает и тратит `Quality.Available("Lights")` / `Available("Particles")` — остаток бюджета. Когда уровень падает, заявки не урезаются сами: владелец подписан на `Quality.Changed`, заявляет заново и гасит то, что не выдали. Уходя, владелец вызывает `Quality.Release(owner)` (через Maid). `LabLights` / `LabEmitters` — внутренние лимиты лаборатории; её свет всё равно заявляется из общего `Lights`.

### Perf.Scheduler — один Heartbeat

```lua
local Scheduler = require(ReplicatedStorage.Perf.Scheduler)
local job = Scheduler.Every(5, "Showcase.Lod", function(dt, deadline)
	-- dt: секунды с прошлого вызова этой задачи
	-- deadline: os.clock(), к которому вызов должен закончиться (1 мс)
	return false -- true = «работа осталась»: продолжить в следующем кадре
end)
job:SetRate(2); job:Stop()
Scheduler.Stats() -- {Jobs, Frames, ByName = {[name] = {Calls, Errors, AvgMs, MaxMs, Hz}}}
```

* **Частота.** Не чаще `hz` раз в секунду; `hz <= 0` или `>= 60` — каждый кадр. После подвисания нет пачки догоняющих вызовов.
* **Нарезка времени.** На вызов — 1 мс (`deadline`). Длинный проход возвращает `true` и продолжается в следующем кадре. Время сверх бюджета становится «долгом», который переносится: задача пропускает кадры, пока долг не погашен, поэтому в среднем она укладывается в ~1 мс на кадр. Все задачи вместе получают 4 мс на кадр; задачи, которым не хватило времени, идут первыми в следующем кадре (по кругу, никто не голодает).
* **Профайлер.** Каждый вызов обёрнут в `debug.profilebegin("Perf:" .. name)`: в MicroProfiler видно, кто сколько стоит.
* **Ошибки.** Вызов в `pcall`; ошибка считается и пишется в `warn` один раз на задачу; расписание задачи не ломается.
* **Задача не должна уступать** (`task.wait`, `WaitForChild`, `InvokeServer`, `PreloadAsync`): то, что ждёт, запускайте через `task.spawn`. Вызовы идут в переиспользуемой сопрограмме-исполнителе (без нового потока на вызов). Если задача всё же уступила, стоит только она: `warn` один раз, повторно она не запускается, пока тот вызов не вернётся, остальные задачи идут дальше. Ошибка после ожидания тоже считается.
* Heartbeat подключён, только пока есть задачи. `Scheduler.new({Clock = ...})` создаёт отдельный планировщик без Heartbeat (для тестов).

Новым фичам свои `RenderStepped`/`Heartbeat`/`Stepped` запрещены: это проверяет `tests/perf_lint.luau`. `WorldDetailQuality` и `PlotSkinMotion` уже переведены на планировщик.

### Perf.Pool

```lua
local arrows = Pool.new({
	Create = function() return makeArrow() end, -- обязательно; Instance или таблица
	Reset = function(arrow) end,                -- при Release
	Max = 32, Prewarm = 8, Parent = folder,
	Hide = "Modifier", -- "Modifier" | "Transparency" | "Folder" | "None" | function(obj, hidden)
	Steal = false,     -- при Max: true — забрать самый старый активный, false — вернуть nil
	OnSteal = function(arrow) end, -- со Steal: прежний пользователь узнаёт, что объект забрали
})
local arrow, lease = arrows:Acquire(); arrows:Release(arrow, lease)
arrows:Stats() -- {Active, Free, Created, Reused, Dropped, Peak, Max}; arrows:Destroy()
```

Объекты один раз ставятся в `Parent` (или туда, куда их поставил сам `Create`) и остаются там:

* `Modifier` (по умолчанию для любого Instance) — свободный объект прячется через `LocalTransparencyModifier = 1`, GUI через `Visible`, свет, эмиттеры, лучи и GUI-слои — через `Enabled = false`. При показе восстанавливается ровно то, что было изменено.
* `Transparency` — то же через `Transparency`, для серверных пулов.
* `Folder` — перенос в скрытую папку и обратно.
* `None` (по умолчанию для таблиц) — ничего, прячет `Reset` или сам вызывающий.

**Аренда.** `Acquire` возвращает объект и номер аренды. `Release(obj, lease)` с устаревшим номером ничего не делает: тот, у кого объект забрали (`Steal`), не освободит его у нового владельца. Пулам со `Steal` (стрелки F1, титулы F10) аренду передавать обязательно, а `OnSteal` — чтобы прежний владелец забыл ссылку. `Release(obj)` без номера освобождает всегда.

### Perf.Lod

```lua
local handle = Lod.Register(model, {
	Near = 80, Far = 200,  -- по умолчанию Quality.Budget("LodNear"/"LodFar")
	Radius = 6, Cull = true,
	Position = function() return slot.Position end, -- необязательно; так можно регистрировать «слот» без модели
	OnLevel = function(level, handle) end,          -- 0 = полная детализация, 1 = упрощённая, 2 = далеко / скрыто
})
handle.Level; handle:SetRange(near, far); handle:Destroy()
```

* Проверка 5 Гц через `Scheduler`, проход нарезается по времени.
* `OnLevel` вызывается в своём потоке (`task.spawn`): обработчик, который ждёт (строит модель, грузит ассеты), не тормозит проход и не ломает очередь. После ожидания проверяйте `handle.Level` — уровень мог уже смениться.
* Цель-Instance снимается с учёта сама, когда её уничтожают (`Destroying`); `handle:Destroy()` по-прежнему лучший способ.
* Гистерезис ±10 %: граница пересекается наружу только за порогом ×1,1, обратно — внутри порога ×0,9.
* `Cull = true`: объект вне пирамиды камеры и дальше `Near` считается уровнем 2. Логика угла та же, что `viewHalfAngle` в `DogAnimations`.
* За тик применяется не больше `Lod.MaxSwitches` (8) смен уровня, ближние первыми, плюс до `Lod.MaxInitial` (64) первых назначений.
* **Без кода — тегом.** Модель или деталь с тегом `DOGROTS_Lod` (Builder ставит его по `opts.Lod`). Атрибуты `LodNear`, `LodFar`, `LodCull` переопределяют значения по умолчанию. На уровне 1 скрываются потомки с `LodDetail = true`, на уровне 2 — всё, кроме `LodKeep = true` (дальний силуэт). Скрытие — через `LocalTransparencyModifier`. На корень пишется атрибут `LodLevel` (0 / 1 / 2).
* **Только Workspace.** Тег учитывается только у моделей в Workspace и не внутри ViewportFrame / WorldModel: шаблон в ReplicatedStorage и клон в превью (инвентарь, выбор для витрины) LOD не трогает, хотя `Clone()` копирует тег. Модель, которая переехала в Workspace или из него, подключается или отпускается сама; отпущенная показывается целиком.
* **Свет и эффекты в `FXManaged`-модели.** Когда их деталь скрыта, Lod выключает свет, эмиттеры, лучи и GUI и запоминает прежнее `Enabled`; когда деталь снова видна — возвращает, если владелец не включил их сам за это время. Пока деталь видна, Lod их не трогает, так что решения владельца по бюджету не откатываются. Владелец, который меняет эффекты, пока модель скрыта, сверяется с `LodLevel`. В моделях без `FXManaged` эффекты не трогаются (ими владеет `WorldDetailQuality`).

### Perf.Maid и Perf.Signal

`Maid.new()`, `:Give(connection | instance | function | thread | tween | объект с Destroy/Disconnect/Cancel)`, `:Connect(signal, fn)`, `:Set(key, item)` (слот по ключу: прежний предмет убирается), `:Clean()` / `:Destroy()`. `Signal.new()`, `:Connect`, `:Once`, `:Fire`, `:DisconnectAll`. Kit пользуется теми же модулями.

### WorldDetailQuality, PlotSkinMotion и телефоны

* **`FXManaged = true`** на источнике света, эмиттере или любом предке — WDQ его не трогает: не гасит, не урезает `Rate`, не выключает тени. Так новые эффекты (колба, витрина, декор) не гаснут молча. Фича, которая ставит `FXManaged`, сама соблюдает бюджеты `Quality` и заявляет свою долю (`Quality.Claim`). Прежние исключения (`LuckyVisual`, `MuseumLight`) остались.
* Бюджеты WDQ берутся из `Quality`: `Lights` и `Particles` — остаток после заявок (`Available`), `LightRadius`, `EmitterRate`, `EmitterRadius`. При уменьшении движения действует бюджет Low, как и раньше. И свет, и эмиттеры получают бюджет от ближних к дальним (туман своего участка не гаснет из-за дальних). Свойства пишутся, только когда значение меняется.
* **Спор за `PlotMist` устранён.** Владелец всех эмиттеров района — WDQ. `PlotSkinMotion` больше не включает и не выключает `PlotMist` (раньше 30 раз в секунду, поверх бюджета), а только качает `PlotFloat`.
* **Телефоны.** `WorldEventController` больше не ставит свой `WorldEventFX` по умолчанию: уровень даёт `Quality` (тач без клавиатуры → Medium). `VoidAtmosphere` читает `Quality.Tier()` и `Quality.Reduced()`, ветки «`WorldEventFX == nil` и `TouchEnabled`» больше нет.
* PAWPAD «Motion» переключает общий атрибут `ReducedMotion` (а не свою локальную копию).

### World.Spec и World.Builder — мир из спецификаций

Спецификация — простая таблица: `Class` (`Part`, `WedgePart`, `CornerWedgePart`, `TrussPart`), `Shape` (`Block`, `Ball`, `Cylinder`), `Name`, `Size`, `CFrame` (относительно якоря), `Color`, `Material` (имя `Enum.Material`), `Transparency`, `Reflectance`, `CastShadow`, `CanCollide`, `CanQuery`, `CanTouch`, `Tags`, `Attributes`, `Props`, `Children`. Дети — свет, эмиттеры, вложения, лучи, SurfaceGui с надписью; enum-свойства можно задавать именем (`Face = "Front"`). Луч ссылается на вложения по имени.

```lua
local S = require(ReplicatedStorage.World.Spec)
local base = S.Block("Base", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), S.Mat("Marble", WHITE))
local lamp = S.Ball("Lamp", 1.5, CFrame.new(0, 6, 0), S.Neon(GOLD, { Children = { S.PointLight({ Range = 14 }) } }))
local posts = S.Ring({ S.Cylinder("Post", 5, 0.6, CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.pi / 2)) }, 6, 3.5)
local specs = S.Concat({ base, lamp }, posts, S.MirrorX(leftDecor))
S.PartCount(specs); S.Count(specs); S.Bounds(specs); S.Validate(specs)
```

* **Детали:** `Part`, `Block`, `Ball` (диаметр), `Cylinder` (длина по оси X, как в Roblox), `Wedge` (высокая сторона сзади, +Z), `CornerWedge` (вершина в углу +X +Y −Z), `Truss`.
* **Материалы:** `Mat`, `Neon`, `Glass`, `Metal`, `ForceField`.
* **Дети:** `PointLight`, `SpotLight`, `SurfaceLight`, `Emitter`, `Attachment`, `Beam`, `Label`, `Child`.
* **Преобразования** (возвращают новые списки): `Offset`/`Transform`, `Rotate`, `MirrorX`, `Array`, `Ring`, `Arc` (`Face = "Out" | "In" | "Fixed"`), `Concat`, `Flatten`, `With`, `Merge`.
* **`MirrorX` точный и для детей.** У угловых клиньев поворот на 90° и обмен X/Z. `CFrame` / `Position` детей (вложения) отражаются в системе детали, а грани `Face` и `EmissionDirection` (таблички, SurfaceLight, SpotLight, эмиттеры) меняются Left ↔ Right, так что отражённая табличка смотрит наружу.
* **Запросы:** `Bounds`, `PartCount`, `Count` (детали, свет, эмиттеры, лучи…), `Validate`.
* **Детерминированный генератор** `Rng(seed)` даёт одинаковые числа в Lune и в Roblox.

```lua
local Builder = require(ReplicatedStorage.World.Builder)
local model = Builder.Build(specs, anchorCFrame, {
	Name = "Stand", Parent = folder, BuilderId = "Showcase", LayoutVersion = 3,
	StreamingMode = "Atomic", PersistentPlayer = player, FXManaged = true,
	Lod = { Near = 80, Far = 200 }, Attributes = { Owner = userId },
})
local model, rebuilt = Builder.EnsureBuilt(parent, "MiningCorner", 24, function()
	return Builder.Build(layout(), anchor, { BuilderId = "MiningCorner" }) -- без Parent
end)
-- то же по кусочкам (декор участка, уровень шахты): детали, пока не вышло время кадра
local build = Builder.Begin(specs, anchor, options)
Scheduler.Every(0, "Decor.Build", function(_, deadline)
	local done, model = build:Step(deadline) -- модель готова и стоит в Parent, только когда done
	return not done
end)                                         -- build:Cancel() — бросить и удалить
```

* Модель собирается отдельно от мира и ставится в `Parent` одним действием. `WorldPivot` = якорь. Атрибуты `BuilderId`, `LayoutVersion`, `PartCount`.
* Режим стриминга и `AddPersistentPlayer` ставятся в `pcall`, как в `MiningWorld`; `AddPersistentPlayer` работает только на сервере.
* По умолчанию детали `Anchored`, `CanCollide`/`CanQuery`/`CanTouch = false`, если спецификация не просит иного.
* `CastShadow`, если он не задан: выключен у Neon, Glass, ForceField, у деталей прозрачнее 0,5 и у деталей меньше 4 стадов по всем осям. В плейсе уже около 12 800 видимых деталей с тенью.
* `EnsureBuilt` переиспользует ребёнка с той же `LayoutVersion`, иначе строит заново. Все остальные дети с этим именем (старые версии, дубликаты) уничтожаются. `LayoutVersion` модели всегда равна аргументу `version` (если `buildFn` поставил другую — `warn`), поэтому повторные вызовы не перестраивают модель.
* **Лучи** ищут вложения по имени сначала в своей верхней детали, потом во всей сборке (с `warn`, если имя не уникально). Поэтому копии из `Array` / `Ring` / `Arc` / `MirrorX` соединяются каждая со своими вложениями.
* **Большие сборки на клиенте** (декор до 300 деталей на участок, уровень шахты до 400, несколько участков при входе) — через `Builder.Begin` и задачу планировщика, а не одним `Build`: так соблюдается общий бюджет 1 мс на задачу.

Раскладки фич — чистые модули `ReplicatedStorage/<Feature>/<Feature>Layout.luau`, которые возвращают спецификации. Их проверяют в Lune (бюджет деталей, границы, детерминизм) и смотрят через `tools/preview`.

### tools/preview — посмотреть раскладку без Studio

```sh
cd tools/preview && npm install    # один раз: three + playwright-core (node_modules в .gitignore)
# из корня репозитория:
lune run tools/preview/export.luau tools/preview/out/stand.json --file tools/preview/samples/stand.luau
lune run tools/preview/export.luau out.json --module ReplicatedStorage.Lab.FlaskLayout --call Build --args '[2]'
lune run tools/preview/export.luau out.json --place build/DOGROTS_MINING.rbxl --path "Workspace/DOGROTS_District/05_MutationLab" --max 20000
node tools/preview/render.mjs tools/preview/out/stand.json tools/preview/out/stand --angles iso,front,top,close
```

* **Источники.** Функция модуля из `src`, файл Luau, JSON со спецификациями или все видимые детали под путями плейса. MeshPart и Union рисуются ограничивающим боксом, полупрозрачно.
* **Сцена.** Студийный свет, мягкие тени, сетка 4 стада.
* **Материалы.** Neon светится с bloom, Glass прозрачное и глянцевое, металлы отражают. У остальных материалов передаются цвет и шероховатость.
* **Камеры:** `iso`, `front` (смотрит на грань −Z), `back`, `side`, `top`, `close`. Кадр подгоняется под границы.

Примеры: `docs/img/overhaul/preview_sample_stand.png` (стенд из `Spec`) и `preview_sample_place.png` (NPC из плейса: его скосы из клиньев подтверждают ориентацию `WedgePart`). Подробности: `tools/preview/README.md`.

### UISound — звуки интерфейса

```lua
local UISound = require(ReplicatedStorage.UISound)
UISound.Play("Success")
UISound.Play("Coin", { Pitch = 1.2, Volume = 0.8, Bus = "SFX", From = guiObject })
local binding = UISound.Bind(button)                   -- наведение + нажатие; binding:Disconnect()
UISound.Bind(button, { Hover = "Hover", Press = false })
UISound.Start()                                       -- клиент: громкость из настроек → шины (PerfBootstrap)
```

* **Сигналы:** `Hover`, `Press`, `Open`, `Close`, `Tab`, `Toggle`, `Success`, `Error`, `Reward`, `Coin`, `Whoosh`, `Pop`, `Rare`, `Epic`, `Legendary`, `Countdown`, `Lock`. Они собраны из встроенных звуков движка, которые проект уже использует (`volume_slider.ogg`, `collide.wav`, `electronicpingshort.wav`, `swordslash.wav`, `action_jump_land.mp3`; как в `MiningAudio`, `LabAudioConfig`, `LuckyAudio`), слоями с разной высотой. Владелец может загрузить свои звуки и прописать `UISound.AssetIds[cue] = id` (0 = встроенный рецепт).
* **Пул:** не больше 6 звуков одновременно. Наведение никогда не обрывает другой звук; важные сигналы (`Success`, `Reward`, `Legendary`…) могут забрать самый старый голос того же или меньшего приоритета. У каждого сигнала своя пауза: спам наведением не слышен.
* **Шины.** `ServerScriptService.AudioBootstrap` создаёт `SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient}`; `Music` и `WorldEvents` уже есть в плейсе. Туда же сами попадают звуки `RewardAudio`, `WorldSound`, `LabAudioConfig` и музыка `WorldAmbience`, которые раньше шли мимо шины. На клиенте `UISound.Start()` (его вызывает `PerfBootstrap` при входе) сразу ставит громкость групп UI и SFX из атрибутов `Setting_UIVolume` / `Setting_SFXVolume` (0…1, по умолчанию 1) и следит за изменениями атрибутов и за группами, которые реплицируются позже. Так ползунки F2 работают и для звуков, которые сами идут в шину (лаборатория в SFX, награды и звуки мира в UI), даже если ни один сигнал UISound ещё не играл. Если группы ещё нет, сигнал всё равно играет, а громкость настройки применяется к самому звуку. Приглушение музыки во время секретных сцен (`SecretArrivals/Kit`) не трогает шины UI и SFX.
* **Kit.** `Kit.Button` звучит при наведении и нажатии; кнопка с удержанием — в начале и в конце удержания. `Sound = true` или не задан — сигналы по умолчанию, `false` — без звука, `{Hover = cue | false, Press = cue | false}` — свои сигналы (и для кнопки с удержанием). `Kit.Window` звучит при открытии и закрытии; `Sound = false` ставит на окно атрибут `UISoundOff`, и замолкает всё внутри. `Kit.Tabs` звучит при смене вкладки. Атрибут `UISoundOff = true` на любом GUI-предке глушит поддерево.

### Kit: токены, движение, иконки

* **`Kit.Theme`, только добавления:**
  * `Space` (XXS 2 … XXL 32);
  * шкала `Radius` (XS 4 … XL 18; совпадает с Small, Button, Card, Window);
  * `IconSize` (XS 14 … Hero 72);
  * `Elevation` (Flat, Low, Mid, High: смещение и прозрачность тени) и `ShadowColor`;
  * новые длительности `Motion` (Hover, Pop, Toast, Stagger, Celebrate);
  * `Easing` (Standard, Enter, Exit, Emphasis, Linear).

  Прежние значения не менялись (это проверяет `tests/uikit.luau`).
* **`Kit.Motion.Reduced()`** учитывает `Perf.Quality.Reduced()`, то есть настройку Roblox, `Setting_ReducedMotion` и PAWPAD. `Motion.Override` по-прежнему главнее.
* **`GameIcons.Glyph(name[, group])`** — глифы, которые Roblox рисует без загрузки:
  * редкость: Common ● … Secret ❖; это простые фигуры, их окрашивает `TextColor3`;
  * классы находок: Treasure, Artifact, Special, Secret, World Find;
  * действия: продать, избранное, замок, обмен, витрина, мутация, маршрут, глаз и скрыть, настройки, фильтр, сортировка, поиск, закрыть, назад и другие;
  * места: лаборатория, магазин, музей, участок, шахта, ивенты.

  Неизвестное имя даёт `GameIcons.GlyphFallback` («•»). Регистр не важен, есть псевдонимы (`Favorite`, `Show`, `Mining`…). `Kit.Icon` с ключом без картинки показывает этот глиф вместо «★». Прежние экспорты `GameIcons` не менялись.

### Уборка

* `StarterPlayerScripts/LocalScript` — отладочный остаток: печать локали, перезапись всех надписей «DOGS», вызов `GetTranslatorForLocaleAsync` без `pcall`. Заменён заглушкой `-- retired`; файл нельзя удалить, иначе сборка вернёт копию из базы.
* **`DOGROTS_AutoTranslateUI`:**
  * Кэш облачного переводчика ограничен: два поколения по 1000 строк (≈LRU на 2000).
  * Добавлен такой же ограниченный кэш итогов `translateUI`. Повторный текст больше не проходит заново ~550 шаблонов и фраз.
  * Оба кэша очищаются при смене локали. Кэш итогов очищается ещё раз, когда переводчик загрузился: надписи, изменившиеся во время загрузки, не застревают без облачного перевода.
  * Поведение не изменилось: старый и новый скрипт на 7 392 строках (словари, динамические фразы, 5 000 уникальных цен), по три прохода, дали 22 176 одинаковых результатов.

### perf-lint

`tests/perf_lint.luau` проверяет каждый файл в `src/StarterPlayer`, `src/StarterGui` и `src/ReplicatedStorage`:

* подключения `RenderStepped`, `Heartbeat`, `Stepped`, `PreSimulation`, `PostSimulation`, `PreRender`, `PreAnimation` (`:Connect`, `:ConnectParallel`) и `BindToRenderStep`;
* `DescendantAdded` по всему Workspace, в том числе через псевдонимы и через циклы по списку `{gui, workspace}`.

Сегодняшние нарушители записаны в `BASELINE` (файл → число), поэтому существующий код проходит. Новое нарушение роняет тест с подсказкой: `Perf.Scheduler.Every` или теги CollectionService. Если файл стал чище, тест просит уменьшить число. `Perf/Scheduler` разрешён. Текущие числа печатает `lune run tests/perf_lint.luau --report`.

### Что изменено в плейсе

* **Новые скрипты:**
  * `ReplicatedStorage/Perf/{Quality,Scheduler,Pool,Lod,Maid,Signal}`;
  * `ReplicatedStorage/World/{Spec,Builder}`;
  * `ReplicatedStorage/UISound`;
  * `StarterPlayerScripts/PerfBootstrap`;
  * `ServerScriptService/AudioBootstrap`;
  * `ScreenGui/Modules/Kit/Sound`.
* **Изменённые скрипты:**
  * `WorldDetailQuality`, `PlotSkinMotion`, `WorldEventController`, `VoidAtmosphere`;
  * `PawpadRuntime`, `SecretArrivals/Kit`;
  * `Kit/{Maid,Signal,Motion,Button,Window,Controls,Theme,Base}`;
  * `GameIcons`, `DOGROTS_AutoTranslateUI`;
  * `LocalScript` (заглушка).
* **Во время работы появляются:**
  * группы звука `UI`, `SFX`, `Ambient` в `SoundService.DOGROTS_AUDIO`;
  * атрибуты игрока `LowFX`, `WorldEventFX`, `ReducedMotion`;
  * атрибут `LodLevel` на моделях с тегом `DOGROTS_Lod`;
  * 6 объектов `Sound` с именем `DOGROTS_UISound` в `SoundService` (пул).

### Чек-лист для Studio (клиентская часть)

1. **Play Solo.** Убедиться, что:
   * у игрока есть атрибуты `WorldEventFX` (High на ПК), `LowFX = false` и `ReducedMotion`;
   * в `SoundService.DOGROTS_AUDIO` есть группы `UI`, `SFX` и `Ambient`.
2. **PAWPAD → «World Event FX».** Уровень меняется по кругу High → Medium → Low; при Low `LowFX = true`; идущий ивент перезапускается с новой плотностью эффектов. Сторож FPS (например, в эмуляторе слабого устройства) идущий ивент не перезапускает.
3. **PAWPAD → «Motion».** Окна Kit открываются без анимации; повторное нажатие возвращает анимацию. То же при включённом «Уменьшении движения» в настройках Roblox: первое нажатие возвращает анимацию.
4. **Эмуляция телефона (Device Emulator).** После входа `WorldEventFX = Medium`; источников света вокруг не больше 16.
5. **MicroProfiler (Ctrl+F6).** Видны метки `Perf:WorldDetailQuality`, `Perf:PlotSkinMotion`, `Perf:Quality.Watchdog`, `Perf:Lod`, у новых фич — `Perf:<name>`. Ни одна не держит больше ~1 мс в кадре.
6. **Окно Kit (`KitDemo = true`).**
   * Наведение и нажатие кнопок дают тихий щелчок; при открытии и закрытии окна и при смене вкладки тоже есть звук.
   * Спам наведением не трещит.
   * Атрибут игрока `Setting_UIVolume = 0` (вручную в Studio или из окна настроек F2) глушит звуки UI, `1` возвращает их.
   * Сразу после входа, ничего не нажимая: `Setting_SFXVolume = 0.2` делает тише звуки лаборатории (группа `DOGROTS_AUDIO/SFX` получает `Volume = 0.2`).
7. **Участок с туманом `PlotMist`.** Туман не мигает. При Low эмиттеров вокруг почти нет.
8. **Memory (F9 → Memory).** После долгой игры на русском `LuaHeap` не растёт без конца: кэши AutoTranslate ограничены.

### Проверки

`tools/check.sh` — сборка, verify, все `tests/*.luau` (в том числе `perf`, `world`, `ui_assets`, `perf_lint`, `uikit`) и luau-lsp без новых диагностик.
