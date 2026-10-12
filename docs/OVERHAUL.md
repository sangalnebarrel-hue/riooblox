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
| `Action(R,p,action,a,now,random)` | из `Rules.Action` | `nil` — не моё действие; иначе `message[, extra]` |
| `Snapshot(R,p,view,now)` | в `Runtime.Snapshot` (в pcall) | кладёт лёгкие данные в `snapshot.Features.<X>` |

**Хуки запроса** (`Runtime.Request`, remote `DogEconomyRequest`). Они действуют на действия, которые фича перечислила в `Actions`:

| Поле | Что делает |
|---|---|
| `Actions={Name=true,…}` | действия фичи. `Registry.Owner(action)` возвращает фичу-владельца или `nil`. Тест `tests/feature_hooks.luau` падает, если два модуля объявили одно имя или имя совпало с устаревшим действием |
| `Cost(action) -> число` | цена запроса в корзине токенов (по умолчанию 1; корзина на 8 токенов, пополнение 1,5 в секунду, общая для всех remote) |
| `Gate(player,action,a,Runtime)` | проверки мира **до** транзакции: близость к витрине или пульту, свой участок. Отказ — `Rules.Check(false,'…')` или возврат строки с причиной; `nil`/`true` — пропустить |
| `Request(player,action,a,receiptId,Runtime) -> ok,result` | полностью свой путь (как `LabService.Request`). Без него действие идёт `Engine:Action → Rules.Action → Registry.Action` |
| `Reply='Snapshot'\|'Patch'\|'None'` (или `{[action]=режим}`) | что получает клиент при успехе: полный `StateSnapshot` (как раньше), `StatePatch` или ничего |
| `Patch(player,action,result,p) -> таблица` | лёгкий ответ для `Reply='Patch'`; `p` — обновлённый `Runtime.Views`. Если `Patch` упал или его нет — отправляется полный снимок |
| `Project(player,p,Runtime)` | в конце каждого `Runtime.Project`, у каждой фичи свой pcall. Публикует атрибуты игрока и участка — **только при изменении значения**. Ошибка — warn не чаще раза в 30 с |

Порядок в `Runtime.Request` для действия фичи:

1. общая проверка: корзина (`Cost`), `Ready`, `clean` (глубина ≤3, ≤30 элементов, строки ≤120), 32-hex `requestId`;
2. `Gate`;
3. `Request` фичи или `Engine:Action`;
4. при успехе — `Runtime.Refresh(player)` (значит, и `Project` всех фич), затем ответ по `Reply`. После отказа ничего не обновляется.

Фича без новых полей работает ровно как раньше. Её действие, не перечисленное в `Actions`, проходит устаревшей веткой `engine:Action` и получает полный снимок.

**Правила имён.** Имя действия уникально, с префиксом фичи, не длиннее 40 символов. Префикс `Mining` зарезервирован: такие запросы `Runtime.Request` отдаёт мини-шахте раньше фич. Намеренный перехват устаревшего имени (`DexClaim` у `Dogdex`) записывается в `TAKEOVERS` теста.

**Уже объявлены:** `Settings` → `SettingsSave`; `UpgradeTree` → `TreeUpgrade`, `Upgrade`; `Dogdex` → `DexClaim`; `Equipment` → `EquipmentOpenCase`, `EquipArtifact`, `UnequipArtifact`, `EquipAccessory`, `UnequipAccessory`, `SalvageEquipment`, `LockEquipment`.

Пример фичи с хуками:

```lua
local F = { Name = "Showcase", Order = 60 }
F.Actions = { ShowcaseSet = true }
F.Reply = "Patch"
function F.Cost(_action) return 1 end
function F.Gate(player, _action, a, Runtime)
	-- мир: игрок стоит у своего постамента
	if not nearPedestal(player, a.Slot) then return "Stand at your showcase" end
end
function F.Normalize(R, p, now) ... end
function F.Validate(R, p) ... end
function F.Action(R, p, action, a, now, random) ... end
function F.Patch(_player, _action, _result, p) return { Showcase = view(p) } end
function F.Project(player, p, Runtime) ... end -- атрибуты участка, только при изменении
return F
```

API реестра для тестов и инструментов: `Registry.Add(feature)` (регистрация; повтор имени действия оставляет первого владельца и пишет строку в `Registry.Collisions`), `Registry.Owner`, `Registry.Cost`, `Registry.Gate`, `Registry.Reply`, `Registry.Patch`, `Registry.Project`, `Registry.Modules`.

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
  * ответ: `"Settings saved"`, `StatePatch={Settings={…все настройки…}}`, полного снимка нет;
  * отказы: `Choose a setting`, `Unknown setting`, `Invalid value for this setting`, `Too many settings` (RU — `Localization/ServerCore.luau`).
* **Клиент** читает `snapshot.Features.Settings` и атрибуты `Setting_<Key>`. Атрибуты пишет `Project` фичи, только при изменении. Когда приходит ответ на `SettingsSave`, атрибуты уже обновлены.
* **Сервер** читает одно значение через `Features.Settings.Get(p, key)` (безопасно к `nil`). Пример для F6: `Settings.Get(p, 'TradeRequests') == 'Off'`. Схема клиента: `SettingsConfig.Read(settings, key)`, `SettingsConfig.Attribute(key)`.

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
| `Register(name, fn, contexts?)` | `fn(p, uid, item) -> причина\|nil`. Чистая и дешёвая: выполняется в транзакции для каждой находки. `contexts` — подмножество `{Sell=true, Bulk=true, Transfer=true}`; `nil` — все. Повторная регистрация имени заменяет защиту |
| `Reason(p, uid, context?, ignore?)` | первая причина в порядке регистрации или `nil`. `context=nil` спрашивает все защиты; `ignore={[name]=true}` пропускает защиты по имени |
| `IsProtected(p, uid, context?, ignore?)` | `true`/`false` |

Контексты:

* `'Sell'` — одна выбранная находка (по умолчанию в `YardCommerce.CanSell`);
* `'Bulk'` — все продажи коллекционеру (`BulkSell`, `SellQuote`, `NPCSell`);
* `'Transfer'` — находка уходит из профиля: предложение обмена, лот рынка, катализатор лаборатории (`ItemRules.Get(p, uid, true)`).

Защита, которая упала с ошибкой, **защищает** находку (fail closed).

Встроенная защита `Favorite` (`item.Favorite == true`) действует только для `'Bulk'`.

Где спрашивается:

* `BulkSell {Uids, IncludeFavorites?}`. Защищённые находки пропускаются, ответ содержит `SkippedProtected` (сколько осталось). Избранное продаётся только при `IncludeFavorites == true`; другие защиты флаг не снимает. Если продавать нечего, потому что всё защищено, отказ — с причиной защиты. `ValidBulkArgs` принимает только булев `IncludeFavorites`.
* `SellQuote {All | Uids, IncludeFavorites?}` не берёт защищённые находки в оценку (`SkippedProtected`). `NPCSell` проверяет защиту ещё раз в момент продажи.
* `Runtime.Snapshot.SellableItems` — контекст `'Sell'`: витринные находки исключены, избранное можно продать по одной.
* `ItemRules.Get(p, uid, true)` отказывает с причиной защиты. Через неё идут обмен (`Engine:Trade` Offer и коммит), рынок (`Market:Create`), катализаторы лаборатории.

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
* **`DogInventory`.** Атрибуты собаки пишутся только при изменении поля: у каждой записи есть тень последних записанных значений. `OwnerHistory` кодируется в JSON заново, только когда меняется длина истории, `EarlierTransfers` или последняя строка (история только дописывается).
* **Пустой опрос `Menus`.** Раньше полный Snapshot запрашивался раз в 15 с, даже без открытого меню, — только ради плашки «WHILE YOU WERE AWAY». Теперь сервер публикует атрибут `OfflineEarningsRevision` (`<Revision>:<LastReturnAt>` из `p.OfflineEarnings`; меняется при возвращении с офлайн-монетами и при получении). Меню без открытой страницы запрашивает Snapshot только когда метка сдвинулась. Неудачный запрос повторяется.
* **Повтор входа** (`Runtime.JoinRetry = {Attempts=6, Delay=2.5}`, `Runtime.JoinRetryable(message)`). Раньше повторялась только ошибка «another server». Теперь повторяются и «busy», `DataStore…`, «Storage unavailable», «pending/retry», «expired before commit». Профиль, который не проходит проверку, кикает сразу, как и раньше.
* **Обмен, срочное исправление** (полный Trade 2.0 — F6):
  * `Confirm` фиксирует версию и копию предложений и ставит `t.Committing=true` **до** yield в `PaidPolicy.Allowed`. После него версия проверяется снова, коммит идёт из копии, `Committing` снимается при любом выходе;
  * `Offer`, пришедший во время коммита, получает отказ `Trade is committing`. Тест `tests/trade_hotfix.luau` воспроизводит гонку: на старом коде игрок A отдавал собаку за 0 монет;
  * повторный `Ready` на той же версии не перезапускает 8-секундный таймер проверки;
  * шаг `Trade` обновляет только двух участников, а не весь сервер (`RefreshAll` убран из этой ветки).

### 8. Известные ограничения

* **Старые кнопки «SELL».** `CollectorScreen`, `InventoryController` и `ServiceMenusController` продают одну находку через `BulkSell` с одним uid. Избранную находку теперь нужно сначала снять с избранного (сервер ответит «Favorite finds are kept out of bulk sales»). Новый инвентарь F2 передаёт `IncludeFavorites=true` после явного подтверждения. Предсказание продажи в старом клиенте на мгновение прячет избранное, пока не придёт следующий Snapshot: ревизия инвентаря сдвигается, и клиент его запрашивает.
* **`StatePatch` у `SettingsSave`.** Кэш `Modules/Net` обновляется только из `StateSnapshot`. Окно настроек читает `StatePatch.Settings` или атрибуты `Setting_<Key>`.
* **Ловушка валидатора (не новая).** Если `p.Upgrades` целиком потерян (повреждён не по значениям, а целиком), `PlotRules.Validate` отклоняет собак в будках, которые стали закрытыми, и вход падает. Кроме того, `OnboardingRules.Observe` читает `p.Upgrades` до того, как его лечит `UpgradeTree`. Поэтому `save_compat` портит только значения внутри таблицы.
* **Клиентская часть `Remotes`** проверена на фейковых инстансах. Реальное ожидание `WaitForChild` проверяется в Studio.
