# DOGROTS — аудит перед большой переработкой

Аудит проведён перед переработкой. Исходник — плейс `DOGROTS_MINING_5.rbxl`: он побайтно совпадает с `build/DOGROTS_MINING.rbxl` на коммите `d38d853` и с резервной копией `place/backups/DOGROTS_MINING_5_pre_overhaul.rbxl` (тег `pre-overhaul-backup`).

Аудит выполнен только на чтение, в 10 параллельных направлениях. Каждый вывод опирается на код из `src/` и на собственные Lune-скрипты, которые читали `.rbxl`. Перед началом `tools/check.sh` был зелёным: сборка, 13 наборов тестов (233 теста) и luau-lsp без новых диагностик.

Разделы:

1. Данные, сохранения и сеть
2. Экономика и баланс
3. Раскопки собак и глубина
4. Модели предметов раскопок
5. Участки, витрина, косметика
6. Лаборатория и мутации
7. Интерфейс, HUD и инвентарь
8. Трейды, титулы, достижения
9. Ивенты (Dog Rush) и навигация
10. Инструменты сборки, тесты, производительность

После разделов идёт приложение со списками: файлы, поля сохранений, remote, точки расширения.

Планы по каждой из 12 новых систем от всех аудиторов собраны в `docs/overhaul/F01…F12_*.md`. Принятые решения записаны в `docs/OVERHAUL_PLAN.md`.

## Главное коротко

### Как устроен проект

* **Код** — это `src/` в стиле Rojo. В нём 341 из 342 скриптов плейса. `tools/build.py` накладывает `src/` на `place/DOGROTS_base.rbxl`.
* **Что умеет сборка.** Она меняет только `Source` у скриптов и создаёт новые скрипты и папки. Детали, модели, GUI-объекты и remote сборка создать не может. Поэтому вся новая геометрия (колба лаборатории, витрины, шахты, декор, стрелки пути) строится кодом во время игры:
  * сервер ставит коллизии и то, что видят все;
  * клиент рисует тяжёлый декор и эффекты.
* **Данные** лежат в одном DataStore `DOGROTS_ECONOMY_V1`, ключ `p:<UserId>`.
  * Модель RAM-first: транзакции идут в памяти, автосейв раз в 60 с, плюс сохранение при выходе и при выключении сервера.
  * Замок сессии хранится внутри профиля.
  * Миграции идемпотентные, по модулям, без общего номера версии.
* **Как подключать новую систему.** Новая система — это модуль `Economy/Features/<X>.luau` с данными под одним ключом `p.X={Version=1,…}`. `FeatureRegistry` подхватывает такой модуль сам.
* **Чего нельзя делать.**
  * Повышать `MegaResetVersion`.
  * Удалять или переименовывать ID из конфигов (собаки, предметы, DNA, скины, слои).
  * Отклонять в `Validate` то, что чинит `Normalize`.
* **Глубина уже есть в данных.** Есть 5 слоёв (Backyard, Caverns, Ancient Ruins, Cursed Depths, THE VOID), поля `CurrentLayer` и `UnlockedLayers`, предметы по глубинам. Чего нет — это визуальной шахты: собаки стоят на 5 ямах на поверхности участка.
* **Стриминг** включён, но почти ничего не выгружает (радиус 1024 на острове около 900 стадов). Поэтому «не грузить шахту целиком» решается только клиентскими чанками с LOD.

### Что можно улучшить поверх текущей системы (без ломки контрактов)

* **Хуки `FeatureRegistry`.** Добавить `Gate`, `Cost`, `Project` и `After`. Тогда новым системам не нужно править горячие места `Runtime.Request` и `Runtime.Project`.
* **Общие клиентские помощники** `Perf/{Quality, Pool, Lod, Scheduler, Maid}`:
  * один источник уровня качества;
  * атрибут `LowFX`, который сейчас читают 12 скриптов и не ставит никто;
  * исключение `FXManaged` в `WorldDetailQuality`, чтобы новые эффекты не гасились молча.
* **Мир из чистых модулей раскладки.** Раскладка описывается спецификациями деталей и проверяется в Lune. Общий строитель `World/Builder` собирает модель отдельно и выставляет Parent одним действием.
* **`InventoryRevision`** увеличивать только при реальном изменении инвентаря. Сейчас открытый инвентарь скачивает полный профиль каждые 1,5 с.
* **Защита избранных находок** (и находок на витрине) от «продать всё» на сервере.
* **Звук интерфейса.** Создать `SoundGroup` UI/SFX/Ambient (сейчас их нет, звуки идут мимо шины) и общий модуль `UISound`.
* **Лаборатория:** простой переброс (reroll) поверх существующих `LabRules`/`LabGenetics` с теми же шансами; старые процедуры выключить флагами, а не удалять.
* **Баланс камня и кирок** меняется только числами: в `MiningConfig` нужна одна правка без миграций.
* **Титулы** собираются из уже сохранённых данных: `Cosmetics` (Dex/Finds/Set/Event/Prestige), `Stats`, `Lifetime`.

### Что требует аккуратного рефакторинга

* **Обмен (trade).**
  * **Критическая гонка Confirm/Offer** (воспроизведена). Её надо исправить в первую очередь.
  * Приглашение блокирует второго игрока.
  * Сделка не атомарна на диске: два профиля сохраняются порознь.
  * Каждый шаг вызывает `RefreshAll`.
  * Нужен новый `TradeService` с журналируемым коммитом.
* **Инвентарь и HUD.** Сейчас сосуществуют три поколения UI. В сумке около 17 контролов, цвета по классу, а не по редкости, нет виртуализации (до ~19 тыс. объектов). Кнопка «продать» не работает вдали от коллекционера. Нужно новое окно на Kit с сохранением точек входа `GUIIntegration` (иначе встанет вся навигация).
* **Шахта под участком.** Нужно вырезать отверстия в плите острова во время работы и согласовать это с `PlotAppearance` (`PlotBase*`), `MiningWorld` и `DogKennelService`. Есть ограничение по высоте: `DistrictSafety` возвращает игрока при Y < −85.
* **Модели предметов.** 108 предметов сделаны на 60 воксельных геометриях (72 предмета делят 24 формы), мутация превращает всё в Neon. Нужна процедурная фабрика с LOD и замена 9 разных путей превью одним фасадом.
* **Dog Rush.** Толпа собак «привязана» к игроку: позиции считаются от игрока каждый кадр, и собаки попадают на крыши и стены. Звуки событий — пустая заглушка. Награда засчитывается и AFK-игроку. Нужны дорожки забега, общий детерминированный расчёт и проверка ловли на сервере.
* **Нагрузка сервера.**
  * Две глубокие копии профиля в каждой быстрой транзакции.
  * `Runtime.Project` на каждом тике: `JSONEncode` истории каждой собаки, запись атрибутов `DogInventory`, которые реплицируются всем.
  * Полный Snapshot (до 1,2 МБ) на каждое действие.
  * Это делается осторожно, с прогоном тестов платежей и экономического цикла.

### Ограничения, о которых нужно знать владельцу

* `Players.MaxPlayers=60` в файле, а участков 8. Игроки с 9-го не получают участок. Проверить настройку размера сервера в Creator Hub.
* Новые картинки, меши и звуки сборка добавить не может. Всё новое сделано процедурно: детали, Beam, частицы, встроенные звуки движка, эмодзи-иконки. Ассеты, загруженные владельцем, подключаются через ID в конфигах.
* В облачной среде нельзя запустить Roblox. Поведение в игре (FPS, анимации, мобильные устройства) проверяется:
  * юнит-тестами чистых модулей в Lune;
  * статическим анализом luau-lsp;
  * рендером раскладок в браузере;
  * финальной проверкой владельцем в Studio по чек-листу.

---

## Данные, сохранения и сеть (data-network)

Аудит read-only. Все утверждения ниже взяты из кода `src/` и из собранного плейса `build/DOGROTS_MINING.rbxl` (Lune-скрипты в scratchpad/tools/data-network). Размеры и время замерены в Lune на настоящих модулях из `src/` (`tests/lib/economy_env.luau`). Цифры ориентировочные: это та же VM Luau, но не сервер Roblox.

### 1. Коротко

* Модель **RAM-first**. Профиль игрока живёт в памяти сервера (`Transactions.Cache['p:<uid>']`). Каждое действие — транзакция в RAM. На диск профиль пишется автосейвом раз в 60 с, при выходе и при выключении сервера (`BindToClose`). Операции, где участвуют несколько ключей или общие ключи (покупки за Robux, рынок, лимитированный выпуск, вход игрока), идут по **журналируемому** пути: `tx:<id>` → блокировки → commit → `Recover`.
* Для игровых данных есть **один** DataStore: `DOGROTS_ECONOMY_V1`. Длинные ключи хешируются в `StoreKeys`. Рядом: 7 OrderedDataStore лидербордов, `DOGROTS_DEVELOPER_INBOX_V1` и 2 топика MessagingService.
* **Замок сессии** лежит внутри самого профиля: `p.Session={Id=<GUID сервера>,Expires=now+180,StatsAt}`. Тик продлевает его, если осталось меньше 90 с. Сохранение проверяет владельца сессии и ревизию записи.
* **Миграции** не завязаны на номер версии. Порядок такой: (1) защита мега-сброса `MegaResetVersion=1`; (2) недостающие поля верхнего уровня берутся из `Rules.Profile`; (3) `Normalize` каждого модуля со своими версиями (Mining v2, Onboarding v3, Equipment.Version, UpgradeTreeVersion, PlotProgressionVersion, Lab.Version=1, OfflineEarnings.Version). Всё это выполняется **в каждой транзакции**, включая тик раз в секунду.
* Сеть. Почти всё идёт через один `RemoteFunction ReplicatedStorage.DogEconomyRequest` → `Runtime.Request` (корзина токенов, проверка аргументов `clean`, requestId) → `Engine` → `Rules.Action` → `FeatureRegistry`. С сервера на клиент идут `DogEconomyOpen` (открыть страницу), `DogEconomyPush` (уведомления по видам, сейчас используется только Equipment), `RewardPresentation`, `Discovery*`. Плюс атрибуты игрока и папка `DogInventory`.
* **Главные проблемы**: (а) клиент тянет **полный профиль** (`Snapshot`, от 100 КБ до 1,2 МБ) по поводу каждого изменения и раз в 15 с даже вхолостую; (б) быстрая транзакция **дважды** делает глубокую копию всего профиля (6–43 мс на транзакцию); (в) рыночные действия расходуют бюджет DataStore без отдельного лимита; (г) сделка (trade) двух профилей не атомарна на диске; (д) приглашение в обмен сразу блокирует второго игрока; (е) валидаторы определений «запирают» игрока, если из конфига удалить ID.

### 2. Файлы и роли

| Файл | Роль |
|---|---|
| `ServerScriptService/PlayerDataSetup.server.luau` | Точка входа: `Runtime.Start()`, затем `MuseumService.Start()` и `World.Start()` |
| `ServerScriptService/Economy/Runtime.luau` (790 строк) | Хранилище (DataStore или память в Studio), экономический цикл раз в 1 с, вход и выход, автосейв, `BindToClose`, `Request` (шлюз remote-запросов), `Snapshot`, `Project` (атрибуты, `leaderstats`, `DogInventory`, согласование мира), `PushTo`, батчи рекордов и Global Dig, inbox через MessagingService |
| `Economy/Transactions.luau` | Слой транзакций: `Run` (fast RAM или durable с журналом), `Read`, `FlushProfile`/`FlushAllProfiles`, resync «подозрительных» профилей, квитанции (кэш на 2048 штук), резервы `supply:`, `AddCounter`, `MergeRecords` |
| `Economy/StoreKeys.luau` | Ключи длиннее 50 байт превращаются в `h:`+SHA-256; метка `__LogicalKey` защищает от коллизий |
| `Economy/Engine.luau` | API профиля: `Join`, `Leave`, `Action`, `MiningAction`, `TickAll`, `ClaimOffline`, `BuyLine`, `Deliver`, `Roll`, `GrantSpecial`, `Trade*` (обмены хранятся в RAM), `Records`, `Authorize` (проверка сессии и подключения) |
| `Economy/Rules.luau` | Схема профиля (`Profile`), `Normalize` (мега-сброс, заполнение умолчаний, нормализация модулей), `Validate`, `Action` (диспетчер: PlotRules → Features → Display → Mining → ItemRules → устаревшие ветки) |
| `Economy/FeatureRegistry.luau` | Подключение модулей `Economy/Features/*`: `Normalize/Validate/Action/Snapshot` (+`Catalogs` для Robux), порядок по `Order` |
| `Economy/Features/{Passes,UpgradeTree,Equipment,Dogdex}.luau` | Действующие модули-фичи, образцы для новых систем |
| `Economy/Config.luau` → `ReplicatedStorage/DogEconomy/Config.luau` | `Version=4`, `MegaResetVersion=1`, `SessionSeconds=180`, `TickSeconds=1`, `MaxCash=9e15`, `MaxDogs=250` и т. д. |
| `Economy/ItemRules.luau` | Формат находок (`I.Mint`), `I.Normalize` (13 таблиц), `I.Validate` (не больше 1000 предметов) |
| `Economy/Market.luau` | Рынок и аукционы на durable-ключах `reboot1:*`, межсерверный inbox |
| `Economy/PurchaseService.luau` | Единственный `ProcessReceipt`: чек = одна durable-транзакция `{p:<uid>, purchase:<id>}`; game passes |
| `Economy/OfflineEarnings.luau` | Чекпойнт офлайн-дохода в каждой транзакции (`IncomeModel`) |
| `Economy/LeaderboardService.luau`, `Economy/CommunityService.luau` | OrderedDataStore для досок (запись раз в 90 с, чтение раз в 120 с, свой `BindToClose`), «король сервера», почта отзывов (через `Tx`) |
| `ServerScriptService/DeveloperInbox.luau` | Отдельный DataStore `DOGROTS_DEVELOPER_INBOX_V1` (16 шардов в день) |
| `Economy/{YardCommerce,ShelterService,LabService,RewardService,RewardMachineService,LuckyLifecycle,ServerLuck,GlobalDigService,OnboardingService,SupportReceipts}.luau`, `WorldEventService/Gameplay.luau` | Вызывают `Tx:Run` на профиле напрямую, в обход `Engine:Action` |
| `StarterGui/ScreenGui/Modules/Net.luau` | Клиент новых окон Kit: `Request`, `Snapshot(maxAge)` (общий кэш), `Changed`, `OnPush(kind)` |
| `StarterPlayerScripts/MiningClient/Net.luau` | Клиент мини-шахты: `Invoke` и состояние из атрибутов `Mining*` |
| `tests/payments.luau`, `tests/economy_loop.luau` (+`payments_lib/loader.luau`, `lib/economy_env.luau`) | Тесты надёжности сохранения: сбои DataStore, гонки чека и автосейва, порядок выключения. Сейчас зелёные: 21/21 и 16/16 |

### 3. Как это работает от начала до конца

**3.1 Вход** (`Runtime.Start` → `added`, Runtime.luau:614).
1. `EconomyReady=false`. `Engine:Join(uid)` — это `Tx:Run({'p:uid'})`. Профиль ещё не загружен в RAM, поэтому `_canFast` отказывает и вызов идёт по **durable**-пути (`_runDurableCore`): создать журнал `tx:<guid>` в состоянии Preparing → прочитать и заблокировать запись `p:uid` → трансформ → Commit с `Writes` (в журнал пишется полная копия профиля) → `Recover` применяет записи. Это примерно 7–9 обращений к DataStore.
2. Трансформ: `R.Normalize` (мега-сброс, умолчания, модули) → проверка сессии (`Session` отсутствует, принадлежит этому серверу или истекла) → `Offline.Join` начисляет офлайн-доход → `p.Session={Id,Expires=now+180,StatsAt}` → собаки в состоянии `Walking` переводятся в `Inventory` → `R.Validate`.
3. Если пришёл ответ «active on another server», вход повторяется до 6 раз с паузой 2,5 с. **Любая другая ошибка** приводит к `Kick('Your data is protected…')` (L618–624).
4. `Runtime.Loaded[uid]=true` → `Refresh` → `Project` (атрибуты, `EconomyReady=true`) → `DrainInbox` (доставка с рынка).

**3.2 Игра.** Действие клиента: `DogEconomyRequest:InvokeServer(action,args,requestId)` → `Runtime.Request` (L367):
* стоимость в корзине (L368): `MarketQuery`=3, `MiningHit`=0,25, `MiningTrain`=0,5, всё остальное 1. Корзина на 8 токенов, пополнение 1,5 в секунду (L314–318), **общая для всех remote**, которые зовут `Runtime.Allow`;
* `Ready`; проверка аргументов `clean` (L320): глубина ≤3, ≤30 элементов в таблице, строки ≤120, числа |x|≤MaxCash, никаких Instance/Vector3. Для `BulkSell` свой валидатор (до 1000 uid);
* `requestId` из 32 hex-символов обязателен для всего, кроме `Snapshot`/`MarketQuery`. `receiptId=uid..':'..id:sub(1,26)`;
* ветки до `Engine:Action`: `DistrictTravel`, `Tutorial`, `Lab*`, `Mining*` (дистанция до `MiningCorner.MiningPad` ≤32), продажа (`YardCommerce`), `BuyPlotSkin/ClaimPlotSkin` (посещение магазина), `DisplayDog` (посещение хранилища), `ClaimOffline`, рынок (`List/BuyListing/Bid/CancelListing`), `Roll`, `EventClaim`, `TradeRequest/TradeCancel/Trade`. Всё прочее идёт в `Engine:Action` → `Tx:Run` → `R.Normalize` → `R.Action` → `Offline.Checkpoint` → `R.Validate`;
* после действия: `Mining*` возвращает `StatePatch` (`RefreshMining`), продажи — `StatePatch` (`RefreshSale`), `Trade/BuyListing/CancelListing/Bid` вызывают `RefreshAll()`, остальные — `Refresh(player)`. **Любой** успешный ответ-таблица получает `StateSnapshot = Runtime.Snapshot(player)`, то есть полный снимок (L463–465).

**3.3 Fast и durable** (`Transactions:Run`, L593). Fast-путь (`_canFast`): ключи только `p:` (загруженные в RAM), эфемерные `line:`/`lucky:`/`eventobject:` и не больше одного `supply:` без жёсткого лимита. Он целиком в RAM: блокировка по ключам → **копия** каждого профиля → трансформ → проверка → `_captureProfile` (**ещё одна копия**) → `Dirty`, `Versions+1`, квитанция. Если в наборе есть любой другой ключ (`purchase:`, `reboot1:*`, `event:`, `sa:`, `blockacquire:`, `mailquota:`…) или профиль не загружен, путь становится **durable**: сначала `_settleLocked` (сохранить «грязный» профиль или перечитать «подозрительный»), затем журнал и `Recover`. После commit итоговые профили публикуются в RAM. Если ответ DataStore потерялся, но запись прошла, профиль помечается Suspect и перечитывается; локальная копия никогда не затирает чужую более новую ревизию (`stale` → `RESYNC`).

**3.4 Автосейв** (`loopOnce`, L718). Раз в 60 с выполняется `Tx:FlushAllProfiles()`. Для каждого грязного профиля: `GetAsync` (UseCache=false) → `UpdateAsync` с проверками (Lock → Recover; Writer-токен «моя запись уже прошла»; сессия другого живого сервера → отказ; ревизия ≠ ожидаемой → Suspect/RESYNC) → `Revision+1`. Перед записью есть защита размера: `JSONEncode > 3 500 000` → ошибка (Runtime.luau:37). После сохранения профили уже вышедших игроков выгружаются.

**3.5 Выход** (`PlayerRemoving`, L632). Ставится атрибут `EconomyLeaving` (после него `Authorize` отказывает) → `ReleaseProfile`: `ServerLuck.Release` → `Engine:Leave` (отмена обмена, чекпойнт playtime/offline, `p.Session=nil`, ожидание до 30 с, если чек держит блокировку) → `FlushProfile`. Если сохранение вернуло «Resynced», цикл повторяется до 3 раз. Затем `UnloadProfile`. Если сохранить не удалось, профиль остаётся в RAM, и следующий автосейв пробует снова. Быстрый перезаход на тот же сервер отслеживает `rejoined()`.

**3.6 Выключение** (`BindToClose`, L649). `Closing=true`. Параллельно для всех игроков `ReleaseProfile(…,true,10)`, ожидание до 25 с. Затем `FlushAllProfiles`, `FlushEvents`, `FlushRecords` и ещё один `FlushAllProfiles`. Одновременно работают `BindToClose` у `LeaderboardService` (до 22 с) и `CommunityService` (до 25 с). Все укладываются в общие 30 с Roblox.

**3.7 Экономический цикл** (L691–764, каждую секунду, со сторожем: «тишина» дольше 20 с перезапускает цикл). Шаги: `Kennels.UpdateWorkVisuals` → `isDue` (сессия истекает меньше чем через 90 с или у назначенной собаки подошёл `NextWorkAt`) → `Engine:TickAll` (по fast-транзакции на игрока с `Timeout=0`; занятый профиль пропускается) → `Refresh` для каждого прошедшего тик. Плюс: Global Dig раз в 30 с (`AddCounter 'event:<week>'`), inbox раз в 120 с, автосейв раз в 60 с, особые находки раз в 10 с, рекорды (`Engine:Records` раз в 5 с по каждому игроку, `FlushRecords` раз в 60 с, чтение глобальной книги раз в 30 с), рыночные расчёты раз в 20 с, `ServerLuck.SyncAll` раз в 30 с.

**3.8 Замок сессии и его границы.** Join отказывает, пока чужая сессия жива (≤180 с). Если сервер упал без `BindToClose`, игрока не пустят на другой сервер до 3 минут: после 15 с повторов его кикнут с просьбой перезайти. RAM-прогресс с последнего автосейва (≤60 с) теряется. Если DataStore лежит дольше 90 с, сессия может истечь на диске. Тогда другой сервер загрузит профиль, а сохранения старого сервера будут отклонены (`conflict`/`stale`). Данные на диске не портятся, теряется только RAM-прогресс старого сервера.

**3.9 Идемпотентность.** Fast-путь: `Tx.Receipts[receiptId]` в RAM, общий кэш сервера на 2048 записей. Повтор с тем же id возвращает тот же ответ. Durable-путь: журнал `tx:<receiptId>` в DataStore, повтор после сбоя восстанавливает результат. Lab, Shelter, Collector используют схему «котировка (Token) → подтверждение» с отпечатком состояния. Чеки Robux опираются на `purchase:<PurchaseId>` в DataStore.

### 4. Хранилища и ключи

| Хранилище | Ключ | Содержимое / кто пишет |
|---|---|---|
| `DOGROTS_ECONOMY_V1` | `p:<UserId>` | `{Value=<профиль>, Revision, Lock?, Writer?}` — Transactions |
| ″ | `tx:<id>` | журнал `{State=Preparing/Committed/Aborted, Keys, Deadline, Attempt, Writes?, Result, Materialized}`. **Никогда не удаляется**; после материализации `Writes=nil` |
| ″ | `supply:<DogId>` | `{Minted}` — серийные номера и лимиты (пачки по 1/8/32) |
| ″ | `purchase:<PurchaseId>`, `support-receipt:<PurchaseId>` | отметки чеков Robux |
| ″ | `event:<week>` | `{Total}` Global Dig (общий ключ всех серверов) |
| ″ | `records:<1..5>` | глобальная книга рекордов веса по глубинам |
| ″ | `reboot1:book:<assetKey>`, `reboot1:auctionQueue`, `reboot1:inbox:<uid>`, `reboot1:sales:<assetKey>:<day>` | рынок (очередь общая для всех серверов) |
| ″ | `sa:<op>`, `sl:<uid>:<op>` | особые прибытия (THE DOG / LONG DOG) |
| ″ | `block-grant:<uid>:<op>`, `blockacquire:<uid>:<id>` | Lucky Blocks |
| ″ | `mailquota:<uid>:<day>`, `feedback:<hour>:<shard>` | почта отзывов (CommunityService) |
| `DOGROTS_DEVELOPER_INBOX_V1` | `day:<YYYY-MM-DD>:<0..15>` | сообщения разработчику |
| OrderedDataStore | `DOGROTS_LB_{SUPPORT,PLAYTIME,COINS,DISCOVERIES,GLOBALDIG,DOGDEX}_V2_REBOOT1`, `DOGROTS_TOP_XP_V2_REBOOT1` | лидерборды (max-merge UpdateAsync) |
| MessagingService | `DOGROTS_INBOX_V1`, `DOGROTS_WEIGHT_RECORDS_V2` | «проверь inbox» и баннеры глобальных рекордов |

### 5. Схема профиля (`p`, верхний уровень, 60+ ключей)

Ядро: `Version=4`, `MegaResetVersion=1`, `UserId`, `Created`, `Session{Id,Expires,StatsAt}`, `Cash`, `Bones`, `XP`, `Level`, `Prestige`, `RebootGift`.
Собаки: `Dogs{[DogUid]=dog}`, `Reservations`, `DisplayDogs{"1".."3"=DogUid}`, `DogDex{[DogId]=true}`, `VariantDex{[DogId]={[Variant]=true}}`, `DexClaims{"10"=true}`, `DexFavorites`, `DogIncome{Total,XPCoins,XPAt}`.
Находки: `Items{[ItemUid]=item}` (≤1000, `I.HardCap`), `ItemReservations`, `Collection`, `HeavyCollection`, `MutationJournal`, `PersonalRecords`, `ItemSets`, `RecordJobs` (не попадает в Snapshot), `DiscoveryFeed` (≤20), `Loot` (устаревшие стопки `{Value,Count}`), `Stats{TotalFinds,…,Heaviest,MostValuable,Rarest,BestShowcaseFind,BestShowcaseRelic,Depths,Milestones,Claims,CompletedTrades}`, `Lifetime{TotalPlaytimeSeconds,TotalCoinsEarned,GlobalDigContribution,SupportRobux}`.
Прогресс: `Upgrades{[nodeId]=level}` + `UpgradeTreeVersion`, `UnlockedLayers{"1".."5"=true}`, `CurrentLayer`, `Mining{Version=2,Strength,PickaxeOwned/Level (позиция в массиве MiningConfig.Pickaxes),WeightOwned/Level,OreId,OreHP,OreValue (замороженная ценность текущей руды),Collection,...}`, `Onboarding{Version=3,Status,Step,Seen,Migrated?}`, `Lab{Version=1,DNA{key=n},DiscoveredDNA,Recipes,History(≤40),FirstDiscoveries,Experiments,Tier,LastAt,TutorialComplete,PaidDNA}`, `OfflineEarnings{Version,PendingCoins,…}`, `SpecialDiscoveries`, `TotalExcavations`, `Pity`, `LastDig`, `LastSaleAt`, `LastForage`.
Косметика и участок: `Cosmetics{[key]=true}` (кеннельная косметика **и коллекционные титулы**: `Dex10..100`, `Finds<n>`, `Set<name>`, `Prestige<n>`, `Event<i>`, `Discovery:<set>:<Normal|Heavy>`), `EquippedCosmetic`, `PlotSkins`, `EquippedPlotSkin`, `PlotProgressionVersion`.
Платное и бусты: `Passes`, `LuckReserve`, `ServerLuckCredits`, `PaidRouletteTickets`, `CommercePurchases`, `Supplies{kind=expiresAt}`, `SupplyReserve`, `LuckBoosts`, `LuckyCredits{tier=n}`, `OwnedBlocks{uid=block}`, `LuckyOpened`, `LuckyPity`, `BlockOpenReceipts/Order` (≤32), `RouletteTickets`, `NextRouletteTicketAt`, `RouletteReceipts`, `RewardHistory` (≤12), `Equipment{Version,Next,Rev,Artifacts(≤120),Accessories(≤80),CaseCredits,Seen,Pity,Opened}`.
Рынок и события: `Listings{listingId=assetKey}`, `TrackedListings` (≤50), `Event{Week,Contribution,Claims}`, `EventTokens`, `DailyRewards`, `PlaytimeRewards`, `WorldEventsSeen`, `WorldEventClaims{Generation,Count,Objects}`, `NextWorldEventCollect`, `WorldEventRewards`.

**Собака** (`R.Mint`, Rules.luau:215): `DogUid, DogId, DisplayName, Rarity, Variant` (Normal/Shiny/Golden/Corrupted/Glitched/Void; имена — сохранённые данные, переименовывать нельзя), `SerialNumber, Edition, OG, Origin, CreatedAt, Mastery(0..100), MasteryXP, AscensionLevel, OwnerHistory[{UserId,At,Type}]≤100 (+EarlierTransfers), Ability, PricePaid, OwnerUserId, State(Inventory|Digging|Walking), AssignedSlot(''|DigSlot_1..5), NextWorkAt, WorkSequence, FoodDog`, по ситуации `Locked, Favorite, PaidRandom, LabRecipe, LastYield, LastAbility(At), DryStreak, OrbitValue/Count`. JSON около 0,5 КБ.
**Находка** (`I.Mint`, ItemRules.luau:182): `ItemUid, ItemId, DisplayName, Depth, Class, SetId, BaseDropChance, EffectiveDropChance, BaseWeightKg, WeightKg, WeightMultiplier, WeightTier, TierIndex(1..10), WeightProfile, WeightTierChance, Mutation, MutationChance, CombinedOdds, FoundAt, FoundByUserId, OriginalFinderUserId, OwnerUserId, SellValue, ValueBreakdown{Version,Rarity,Factors,Raw,Cap}, ValueVersion, Tradeable, RecordAtCreation{Personal,Server,Global,ImprovedGlobal?}, Favorite, SourceDogUid, FirstFind, SellBonus, IncomeMult?, EventTag?, Origin?`. JSON около 0,9 КБ. Это уникальные экземпляры, «количества» нет. `Locked` стирается в каждом `I.Normalize` (ItemRules.luau:24).

**Замеры размера** (Lune, настоящие `R.Mint`/`I.Mint`): новый профиль 2,3 КБ; 30 собак и 60 находок ≈ 103 КБ; 60 собак и 300 находок ≈ 345 КБ; 220 собак и 1000 находок (максимум) ≈ **1,16 МБ** (из них Items 0,9 МБ). Защита стоит на 3,5 МБ, лимит Roblox 4 МБ. Сейчас запас примерно трёхкратный. Но durable-транзакция с двумя «китами» кладёт в журнал оба профиля (около 2,3 МБ).

### 6. Версии и миграции (как старые сохранения обновляются сегодня)

1. `MegaResetVersion` (Rules.luau:53): если у профиля версия ниже `C.MegaResetVersion`, профиль **пересоздаётся**. Переносятся только платные ключи (L56: `PaidRouletteTickets, CommercePurchases, Supplies, SupplyReserve, LuckBoosts, LuckReserve, ServerLuckCredits, Passes, Cosmetics, Equipment` + `Lifetime.SupportRobux` + платные `OwnedBlocks`). **Повышать эту версию нельзя никогда.**
2. Заполнение умолчаний (Rules.luau:69–70): `for k,v in pairs(R.Profile()) do if p[k]==nil then p[k]=v end end`. Работает только на верхнем уровне. `R.Profile` собирается заново в каждой транзакции.
3. `Normalize` модулей (всегда идемпотентны): `PlotRules` (`PlotProgressionVersion`, перенос старых кеннелей в скины), `OnboardingRules` (v3, `Migrated`), `Tickets`, `I.Normalize`, `Lifetime`, `SupplyRules`, `LuckRules`, `DisplayRules` (снимает висячие `DisplayDogs`), `LabState` (`Tier` по уровню), `MiningRules.Normalize` (v1 → v2 по `LEGACY_ORE_IDS`), `Features.*` (Equipment чинит висячие указатели артефактов, UpgradeTree хранит неизвестные узлы как есть «на случай отката», Passes превращает числовые ключи в строки).
4. Находки: `ValueVersion` / `ValueBreakdown.Version` (ItemValueConfig v6). Цена замораживается при находке, массового пересчёта нет.
5. `p.Version=C.Version (4)` записывается, но **ничего не проверяет** (мёртвое поле).

### 7. Сетевая поверхность (все remote в плейсе и созданные во время работы)

| Remote | Тип / где создан | Направление и данные | Сервер | Клиенты | Лимит |
|---|---|---|---|---|---|
| `RS.DogEconomyRequest` | RF, в плейсе | C→S `(action,args,requestId)` → `ok,result` (+`StateSnapshot`/`StatePatch`/`MiningTargets`) | `Runtime.Request` | `Modules/Net`, `MiningClient/Net`, `GUIIntegration` (DistrictTravel), `OnboardingGuide`, `Menus`, `ServiceMenusController`, `PawpadController`, `InventoryController`, `YardPageController`, `MuseumPresentation` | корзина 8 / 1,5 в секунду |
| `RS.DogEconomyOpen` | RE, в плейсе | S→C `(page,message)`: Lab, Trade, Events, RewardMachine, Collector/UpgradeTree/Storage, маршруты магазинов | LabService, YardCommerce, World/ShopInteriorAccess, GlobalDigService, RewardMachinePresentation, Runtime (приглашение в обмен) | `GUIIntegration:172` | — |
| `RS.DogEconomyPush` | RE, **во время работы** (Runtime.Start:585) | S→C `(kind,data)` | `Runtime.PushTo`, сейчас только `Equipment` → `'EquipmentCredits'` | `Net.OnPush` | — |
| `RS.DiscoveryReveal` | RE | S→C копия находки + `LootSpawn` (находки моложе 30 с) | `Runtime.Project` | EconomyVisuals, InventoryController, YardPageController | — |
| `RS.DiscoveryAnnouncement` | RE | S→All `(item,global)` (тир ≥8, Secret, глобальный рекорд; не чаще раза в 15 с) | Runtime | EconomyVisuals | — |
| `RS.RewardPresentation` | RE | S→C/All `{Cue,Message,Dog,Announcement,Tier,Credits,Count}` | около 12 модулей | GUIIntegration, LuckyReel, LuckyLifecycleFX | — |
| `RS.RewardRequest` | RF | C→S `(action,a)`: Catalog, CancelBlockOffer, BuyBlock, OpenBlock, PlaceBlock, CommerceProduct, PaidProduct, RewardMachineInfo/Product/Activate (+ псевдонимы Roulette*) | RewardService | LuckyBlockUI, ProductPricing, RewardScreens, Menus, InventoryController, RewardMachinePreview | внутри обработчиков |
| `RS.DogKennelOpen` / `RS.DogKennelRequest` | RE / RF | S→C slot; C→S `(Assign|Remove,uid,slot)` → `Runtime.Request` | DogKennelService | GUIIntegration / ServiceMenusController | 0,5 + 1 токен |
| `RS.ShelterRequest` | RF | C→S `(List|Quote|Sell,a)` | CommunityServices → ShelterService | CommunityClient | Allow(1) |
| `RS.CommunityFeedbackRequest` | RF | C→S `(Access|Read|Send,a)` | CommunityServices → DeveloperInbox | CommunityClient | Allow(1) + рядом с ящиком |
| `RS.FeedbackRequest` | RF | C→S `{Text,Category,Request}` | CommunityService.Submit | FeedbackScreen | Allow(2), квоты |
| `RS.CommunityOpen` | RE | S→C `'Shelter'|'Feedback'` | CommunityServices | CommunityClient | — |
| `RS.MuseumRead` / `RS.MuseumChanged` | RF / RE, во время работы (MuseumService) | C→S () → state; S→C `(state,increased)` | MuseumService | MuseumPresentation | **0,1 с, без корзины** |
| `RS.WorldEvents.GetState` / `.Changed` / `.Signal` | RF / RE / RE | состояние события; `{Kind=Reward|Hint|Discovered|Signature|EventReward}` | WorldEventService/Gameplay | WorldEventController, WorldEventGameplayFX | Allow(1) |
| `RS.RewardMachinePresentation` | RE, во время работы | S→All cue | RewardMachinePresentation.server | RewardMachineAttractionFX | — |
| Только Studio | `Mining.MiningStudioControl`, `WorldEvents.StudioEventControl`, `RS.StudioSecretArrival` (RF); `ServerStorage.DOGROTS_HandleReceipt`, `DogLineSpawner.SpawnLuckyBlock/SpawnDog`, `WorldEventService.WorldEventDebug` (Bindable) | на живых серверах не создаются (`IsStudio`) | | | |
| Bindable | `RS.LightingRefreshEvent` (сервер); `ScreenGui.MenuNavigation/NavigateDistrict/ToggleDistrictMap` (локально на клиенте) | | | | |

**Неявные каналы S→C.** `leaderstats.Coins`, `Bones` (IntValue). Около 70 атрибутов игрока (`Level`, `XP`, `CurrentLayer`, `Mining*`+`MiningRevision`, `Tutorial*`, `ItemCount/Capacity`, `IncomePerMinute`, `SupplyExpires_*`, `LuckExpires_*`, `InventoryRevision`, `EconomyReady`…). Папка `Player.DogInventory` со StringValue на каждую собаку и атрибутами её полей. Всё это реплицируется **на всех клиентов** сервера, потому что Player виден всем.

**Snapshot** (Runtime.luau:329): `{Features, Profile (полная копия без Session/RecordJobs; у OwnedBlocks убраны Seed/Pool/Variants, добавлены Odds), OfflineEarnings, Meta, Week, EventTotal, SellableItems, DogStats, IncomeEstimate, IncomePerMinute, Storage, EventEnds, Trade, Players, Preview, Now, Dex (копии определений найденных собак, до ~74 КБ, хотя они и так есть в ReplicatedStorage), GlobalRecords, ServerRecords}`.

**Кто опрашивает Snapshot** (каждый сам по себе): `InventoryController` (каждое изменение `InventoryRevision`/`ItemCount`/…, не чаще раза в 1,5 с), `ServiceMenusController` (раз в 5 с + после изменения ревизии), `Menus` (раз в 5 с на открытой странице и **раз в 15 с вхолостую, даже без меню**, Menus.luau:205), `PawpadController` (8 с), `YardPageController` (8 с), `MuseumPresentation`, окна Kit через `Net.Snapshot(maxAge)`.

### 8. Мир, от которого зависит подсистема

* `Workspace.DOGROTS_District.04_PlayerYards.Yard_0N_*` (8 моделей, атрибуты `YardId`, `OwnerUserId`) и их `DigSlot_1..5` (`DigCenter`, `Unlocked`), `YardSpawn`, `SellAnchor`, `StorageAnchor`, `DogStorage.DisplaySlots`, `PlotDevelopment.BestFinds`. `MiningCorner.MiningPad` в статике **нет**: его создаёт `MiningWorld.server` во время работы, и от него зависит проверка дистанции `Mining*` в `Runtime.Request`.
* `09_DogPark.LeaderboardPlaza`, `32_WelcomeHub.{ServerKingAnchor,DeveloperMailbox.MailboxBody,DogShelter.SellAnchor,AllTimeLeaderboard?}`, `05_MutationLab` (`LabAccess`), `11_Shops.*.InteractionAnchor`, `NavigationAnchors` (13 якорей).
* `ServerStorage.DogTemplates` (101 модель). `Engine.AssetReady` и `DisplayRules` проверяют `RootPart`: без шаблона собаку нельзя выпустить.
* `Players.MaxPlayers=60` в `.rbxl` против **8** участков (`YardService`, порядок 4,8,3,7,2,6,1,5). Игроки с 9-го получают `WaitingForYard`: копать вручную не могут, хотя тики у них идут. Нужно сверить с настройкой в Creator Hub.

### 9. Производительность (замеры в Lune на модулях из src)

| Операция | 60 собак / 300 находок | 220 / 1000 |
|---|---|---|
| `Tx:Run` fast (2 глубокие копии) | ~15 мс | ~43 мс |
| `Tx:Read` / `Engine:Get` (1 копия) | ~9 мс | ~21 мс |
| `R.Normalize` / `R.Validate` | <1 мс | ~0,7 мс |
| `JSONEncode` профиля (защита размера при каждом сохранении) | — | ~65 мс |
| Размер профиля / Snapshot | ~345 КБ (+Dex) | ~1,16 МБ (+~74 КБ Dex) |

Обычные пути. Тик игрока = `Run` + `Refresh` (`Get`) + `Project` (перезапись около 25 атрибутов **каждой** собаки и `JSONEncode(OwnerHistory)` каждой собаки, полный проход по `BestFinds` по всем находкам). Клик в меню = `Run` + `Refresh` + `Snapshot` (копия + `IncomeModel` ~13 мс на 250 собак) + отправка 0,1–1,2 МБ. `MiningHit` (до 6 в секунду) = одна fast-транзакция на каждый удар. `Engine:Records` раз в 5 с копирует профиль только ради проверки, пуст ли `RecordJobs`. На 8 «тяжёлых» игроках это десятки–сотни мс CPU в секунду.

### 10. Найденные проблемы (по важности)

1. **Шторм ревизий.** `Runtime.Project` безусловно увеличивает `InventoryRevision` (L163) на каждом тике с работающими собаками. Открытый инвентарь, `ServiceMenus`, `UpgradeTreeScreen` и серверный `EquipmentWorld` пересчитываются. Клиент с открытым инвентарём каждые ~1,5–3 с скачивает полный Snapshot (≈70–800 КБ/с).
2. **Две глубокие копии профиля в каждой fast-транзакции** (Transactions.luau:454 и :172) и ещё одна в `Read`. Главный источник нагрузки CPU сервера (см. §9).
3. **Бюджет DataStore на рынке.** `BuyListing/Bid/CancelListing` стоят 1 токен. Каждое из них делает некэшированный `GetAsync` (`Market:Listing` → `Tx:Read(bk)`, Market.luau:32). Попытки, отклонённые уже внутри транзакции, проходят полный журнал `tx:` и вызывают `RefreshAll()` (Runtime.luau:452). Один клиент может расходовать около 90 GetAsync в минуту при бюджете 60+10×игроков. Тогда начинают тормозить входы и автосейвы всего сервера.
4. **Обмен не атомарен на диске.** `Engine:Trade` подтверждает обмен fast-транзакцией по двум профилям (L325), а сохраняются они порознь (`FlushAllProfiles`). Падение сервера между двумя сохранениями (или сбой сохранения одного из профилей) может удвоить или потерять предметы и монеты.
5. **Блокировка через приглашение.** `TradeRequest` сразу записывает `TradeByUser` для **цели** (Engine.luau:284). Пока висит обмен (до 240 с), цель не может продавать (YardCommerce.luau:50) и пользоваться лабораторией (LabService.luau:23). Приглашения можно повторять, и каждое открывает окно у цели через `DogEconomyOpen`. Просроченный обмен не чистится, пока не придёт Snapshot или Trade, и мешает новым приглашениям.
6. **Избранные находки не защищены на сервере.** `BulkSell` продаёт всё, что принадлежит игроку (`CanSell`, YardCommerce.luau:40). `ItemLock` отключён, а `I.Normalize` стирает `x.Locked` у всех находок (ItemRules.luau:24). Ошибка нового UI «продать всё» необратимо продаст избранное.
7. **Ловушки валидаторов («запирание» профиля).** `Rules.Validate` требует `D[d.DogId]` (L558), `I.Validate` требует `D[x.ItemId]` (ItemRules.luau:279), `LabState.Validate` требует `C.DNA[k]`, `PlotRules.Validate` требует существующий скин. Если удалить ID собаки, находки, DNA-ключ или скин из конфига, `Join` у владельцев падает, и их кикает при каждом входе. Особенно опасно для F12 («убрать лишние предметы»).
8. **Лишний трафик Snapshot.** Пустой опрос раз в 15 с (Menus.luau:205). `Dex` везёт статические определения (~74 КБ, Runtime.luau:347). Каждое действие возвращает полный `StateSnapshot`.
9. **`DogInventory` реплицируется всем.** Каждая собака хранится как StringValue с ~25 атрибутами под Player. Изменения `NextWorkAt`/`WorkSequence`/`LastYield`/`Mastery*` при каждой работе уходят всем клиентам. `OwnerHistory` кодируется в JSON заново для всех собак при каждом `Project`.
10. **Повтор входа слишком узкий.** Повтор срабатывает только на текст «another server» (L620). «Account busy» или сбой DataStore на входе сразу кикают игрока.
11. **Global Dig выключен** (`GlobalDigConfig.Enabled=false`), но `FlushEvents` всё равно пишет общий ключ `event:<week>` раз в 30 с с каждого сервера.
12. **Лимит журнала продаж** `#h<20000` (Market.luau:121) больше 4 МБ на ключ (строка ~250 Б), так что первой сработает защита на 3,5 МБ. Журнал рыночной транзакции включает целиком профили, книгу и историю, поэтому у «китов» он может упереться в предел записи.
13. Кэш квитанций общий на сервер и рассчитан на 2048 записей: идемпотентность RAM-действий работает «по возможности».
14. После отклонённого (но не упавшего) действия всё равно вызывается `Refresh` (L453).
15. `MuseumRead`: до 10 запросов в секунду без общей корзины.
16. `FeatureRegistry` молча пропускает модуль, у которого упал `require` (только `warn`). У такого модуля не выполняются Normalize/Validate, а его действия отвечают «Unknown action».
17. Прямые вызовы `Tx:Run` в обход `Engine:Action` (Shelter, YardCommerce, WorldEvent, Lucky, Lab…) пропускают `Normalize`/`Offline.Checkpoint`, и не все вызывают `Validate` (`LabService` полагается на `L.Apply`). Поведение транзакций неоднородное.
18. `p.Version` нигде не используется. Захардкоженные «5 слоёв» есть в `Rules.Action('Layer')`, `ReadNextRecordDepth`, `GrantSpecial`, ItemRules `rareTail`, SignatureRules VoidHound.

### 11. КОНТРАКТ для новых систем (витрина, титулы, обмен 2.0, глубина, лаборатория, косметика, навигация)

**11.1 Новое сохранённое поле.**
1. Отдельный модуль `ServerScriptService/Economy/Features/<X>.luau`, возвращает `{Name='X',Order=n,Normalize,Validate,Action,Snapshot[,Catalogs]}`. Реестр подхватывает его сам, ничего регистрировать не нужно.
2. Все данные лежат **под одним** ключом верхнего уровня: `p.X={Version=1,...}`. Создаются лениво в `F.Ensure(p)`. **Не добавлять в `R.Profile`**: это шаблон умолчаний и основа мега-сброса. Каждый читатель (UI, Offline-оценка, Project) должен быть устойчив к `nil`.
3. `Normalize(R,p,now)` выполняется **в каждой транзакции**, включая тик раз в секунду. Требования: O(размер своих данных), без yield и без обращений к миру. Чинит типы, обрезает лишнее по капу, снимает висячие ссылки (uid, которых больше нет в `p.Items`/`p.Dogs`), переводит числовые ключи в строки. Миграции только вперёд и идемпотентно: `if (x.Version or 0)<2 then …; x.Version=2 end`. Неизвестные ключи будущих версий **сохранять** (пример: UpgradeTree `UNKNOWN_MAX`), чтобы откат кода не терял данные.
4. `Validate(R,p)` проверяет только структуру, которую гарантирует Normalize. **Никогда не отклонять то, что лечит Normalize, и висячие ссылки**: прямые транзакции (`BulkSell`, Shelter…) зовут `R.Validate` без `Normalize`. Ошибка Validate на входе означает кик игрока.
5. Формат совместим с DataStore и JSON: строковые ключи или плотные массивы 1..n, без смешанных таблиц, без NaN и бесконечности, без Instance/Vector3/CFrame/Color3/EnumItem (позиции хранить целыми клетками сетки, углы — 0..3). Каждая коллекция имеет жёсткий кап, который проверяется в Action и обрезается в Normalize. Бюджет фичи — до ~50 КБ в худшем случае. Весь профиль держать ниже ~2 МБ, потому что durable-обмен кладёт в журнал два профиля.
6. ID из определений (собаки, предметы, руды, кирки, титулы, декор, DNA, скины, глубины) — это **сохранённые данные**. Список только дополняется, переименовывать и удалять нельзя. Вывод из оборота — флагом `Retired/Enabled=false`. Массивы, индексируемые по позиции (`MiningConfig.Pickaxes/Weights`, `Config.Variants`, `Config.Layers`), — только добавление в конец.
7. Если поле содержит купленное за Robux, его ключ нужно добавить в список переноса мега-сброса (Rules.luau:56) и в тест «a Mega Reset carries everything» (`tests/payments.luau`). `C.MegaResetVersion` не трогать.
8. Тест на Lune (`tests/<x>.luau` на `tests/lib/economy_env.luau`). Фикстуры: новый профиль; старый без поля; повреждённое поле; поле «будущей версии». Проверки: `R.Normalize` ×2 идемпотентен; `R.Validate` проходит; круг `serde json encode/decode` ничего не теряет; кап соблюдается; действие работает в норме и с отказами; `Engine:Join` → `Leave` → `FlushProfile` на памяти (по образцу `tests/payments.luau`).

**11.2 Новое действие.**
1. Имя уникальное, с префиксом фичи, ≤40 символов (`ShowcaseSet`, `TitleEquip`, `LabReroll`, `DecorPlace`, `TradeInvite`…). Features работают **раньше** устаревших веток `Rules.Action`, поэтому совпадение имени молча перехватит старое действие.
2. Аргументы должны проходить `clean` (≤30 элементов, глубина ≤3, строки ≤120). Более длинные списки требуют своего валидатора в `Runtime.Request` (как `ValidBulkArgs`).
3. `F.Action(R,p,action,a,now,random)` — чистый трансформ внутри RAM-транзакции: без yield, без обращений к миру и remote. Ошибки через `R.Check` (откат). Цены и шансы считает только сервер. Для схемы «предпросмотр → подтверждение» — котировка в RAM с Token и отпечатком (образец `LabService`).
4. Проверки близости и мира («подойти к витрине или консоли») внутри `F.Action` невозможны: там нет игрока. Их ставить в `Runtime.Request` до `engine:Action`, как `DisplayDog → commerce.StorageVisit`. Лучше расширить `FeatureRegistry` хуками `Gate(player,action,a)`, `Cost(action)` и `After(player,action,ok,result)` (§12).
5. Стоимость в корзине (Runtime.luau:368). Для частых действий отвечать **патчем** (`StatePatch`, как Mining/BulkSell), а не полным `StateSnapshot`.
6. Сервер → клиент: `Runtime.PushTo(player,kind,data)`, на клиенте `Net.OnPush(kind,fn)`. Новый RemoteEvent заводить, только если нужно вещание многим или «ненадёжный» канал VFX. `tools/build.py` **не умеет создавать remotes**, поэтому они создаются сервером при старте, в одном модуле (папка `RS.DOGROTS_Net`), а клиент ждёт их через `WaitForChild(name,30)`. Каждый `OnServerEvent`/`OnServerInvoke` проверяет типы и вызывает `Runtime.Allow`.
7. Данные для UI: `F.Snapshot(R,p,view,now)` → `Snapshot.Features.X`. Маленькие, только для чтения, без падений (их и так оборачивает pcall).

**11.3 Новые глобальные ключи DataStore.** Без необходимости не заводить. Если нужны: батчить (≥30 с), шардировать, читать с кэшем (`Market:Cached`). Записи в общий ключ с разных серверов упираются в поключевые лимиты.

### 12. Что можно улучшить поверх текущей системы (без ломки контрактов)

* Увеличивать `InventoryRevision` только при реальном изменении сигнатуры инвентаря, по образцу `MiningRevision` (Runtime.luau:96–102).
* ETag для Snapshot: `Snapshot` принимает `a.Known`, а сервер отвечает `{NotModified=true}`, если ревизия профиля (`Tx.Versions`) или сигнатура вида не изменились.
* Убрать или облегчить `Snapshot.Dex` (список ID, а определения брать из `ReplicatedStorage`). Убрать пустой 15-секундный опрос в `Menus` или увеличить интервал до 60 с, перейдя на push.
* Push `'Trade'` обоим участникам; `'InventoryPatch'` после находок и продаж; `'Showcase'`, `'TitleEarned'`, `'EventPass'`.
* Рынок: стоимость `BuyListing/Bid/CancelListing` поднять до 3 токенов + пауза 2 с; читать `Listing` через `Market:Cached`; `RefreshAll` только при успехе и только для участников.
* `BulkSell` пропускает `Favorite` (и витрину), если явно не передан `IncludeProtected`.
* Приглашение в обмен становится заявкой без блокировки цели; лимит приглашений; уборка просроченных обменов в `TradeRequest`.
* Durable-подтверждение обмена через дополнительный ключ `tradelog:<id>`: ключ не из быстрых, поэтому включается журнал без переделки `Transactions`.
* Хуки `FeatureRegistry`: `Gate`, `Cost`, `After`, явный список `Actions`.
* Повтор входа и для `BUSY` и временных ошибок DataStore. Не делать `FlushEvents`, пока Global Dig выключен. `Engine:Records` смотрит в `Tx.Cache` без копии.
* `Project`: обновлять атрибуты `DogInventory` по разнице (подпись собаки); `OwnerHistory` кодировать только при изменении; `BestFinds.Select` только при изменении набора находок.
* Владельцу: выставить Max Players = 8 (по числу участков) в Creator Hub.
* Тест «старый профиль» с фикстурами в `tests/`.

### 13. Что требует аккуратного рефакторинга

* **Fast-путь `Transactions` без двух полных копий** (copy-on-write по ключам верхнего уровня или in-place с журналом отката). Это затрагивает гарантии отката и квитанций, поэтому делать с прогоном `tests/payments.luau`, `tests/economy_loop.luau` и проверкой «трансформ не держит ссылок на профиль».
* **Разбить Snapshot на доменные виды** (Inventory с постраничной выдачей и ревизией, Dogs, Trade, Lab, Showcase…) и завести единый клиентский store, расширив `Modules/Net`. Около 10 контроллеров читают `Snapshot.Profile` напрямую, так что переводить их нужно по одному, сохраняя совместимость формы.
* **`DogInventory`**: убрать реплицируемые всем StringValue (оставить минимум, который нужен `EconomyVisuals` и `YardPage`, или отдавать через Snapshot/Push только владельцу).
* **Унификация прямых `Tx:Run`** под одним API Engine (`Authorize`+`Normalize`+`Validate`+квитанция+Refresh).
* **Схема находки** (~0,9 КБ): `ValueBreakdown` и поля, повторяющие определение, вычислять лениво (миграция `ValueVersion`). Профиль «кита» уменьшится вдвое. Рискованно: эти поля читают обмены, рынок, отпечатки и UI.
* **Число глубин больше 5** (см. п. 18 в §10), если F5 действительно добавит новые слои.
* **Горячие глобальные ключи рынка** (`auctionQueue`, `sales:*`) и размер их журналов.

---

## Экономика и баланс (economy)

Аудит только для чтения. Все числа ниже получены одним из трёх способов:
- прочитаны в коде;
- посчитаны на **настоящем** коде через Lune: `Rules.IncomeModel`, `ItemValuation`, `UpgradeTree` (скрипт `scratchpad/tools/economy/stages.luau` на копии `tests/lib/economy_env.luau`);
- получены из симулятора добычи `tools/balance_sim.py`. Его функции импортированы без изменений, свой скрипт — `scratchpad/tools/economy/proposal_sim*.py`.

Репозиторий не изменялся: `git status` пустой.

### 1. Коротко

- **Главный источник денег — собаки.** `Rules.Dig` раз в секунду зачисляет обычную добычу прямо в кошелёк. Находки (предметы) копятся и продаются у сборщика.
- **Все цифры дохода берутся из одной модели.** `Rules.IncomeModel` даёт HUD «+$/мин», оффлайн-доход, цены бустов, Robux-наборы и кейсы.
- **Есть второй, активный источник — мини-шахта на участке.** Её «камень» — это руда; сначала идёт Известняк. Цены руды и кирок лежат в `MiningConfig`. Доход шахты **не проходит через конвейер бонусов** и **не входит в IncomeModel**.
- **Почему шахта стала незаметной.** После этапа 2 (дерево улучшений и экипировка) доход собак вырос в 9–16 раз, а доход шахты остался прежним. Принцип из `docs/MINING.md` («добыча ≈ 0.6–1× дохода собак») больше не выполняется.
  - На слоях 4–5 без дерева шахта даёт 12–20 % дохода собак.
  - С полным деревом — 1–3 %.
- **Топовые кирки поздней игре почти ничего не стоят.** Voidbreaker за 85M — это примерно 10 минут дохода Secret-команды на VOID без дерева и около 1,2 минуты с деревом.

### 2. Файлы и что авторитетно

**Авторитетные копии лежат в `src/ReplicatedStorage/DogEconomy/*`.** Файлы `src/ServerScriptService/Economy/{Config,ItemDefinitions,DepthDefinitions,ShopDefinitions,MutationDefinitions,SetDefinitions,WeightProfiles,DogDefinitions}.luau` — однострочные прокси вида `return require(game:GetService("ReplicatedStorage").DogEconomy.X)`. В них нет перевода строки, поэтому `wc -l` показывает 0. Расхождения между копиями невозможны, а правки делаются только в ReplicatedStorage.

| Файл | Роль |
|---|---|
| `ReplicatedStorage/DogEconomy/Config.luau` | Все базовые числа экономики. Стартовые деньги 4200, `MaxCash` 9e15. `Power`/`Prices`/`Weights` по редкости (стр. 15–19). Слои `Layers` (стр. 52) и `LootValueScale` (стр. 66). Старые улучшения `Upgrades`, `BoostPricing.LayerScale={1,3,8,20,50}` (стр. 82). Также `Supplies`, `LuckTiers`, `Cosmetics`, кривая XP, престиж 12M×(n+1), ежедневные и игровые награды, `C.Mining=MiningConfig` (стр. 150) |
| `ReplicatedStorage/DogEconomy/MiningConfig.luau` | Мини-шахта: 12 руд (стр. 27–51), 7 кирок (стр. 57–85), 7 гирь (стр. 90–105), `LayerValue={1,3,6,12,24}` (стр. 18), `HitShare=.35` |
| `ReplicatedStorage/Mining/MiningRules.luau` | Чистые правила шахты: `RollOre` (стр. 102) фиксирует `OreValue` в момент появления руды; `Hit` (стр. 186) выплачивает через `ctx.Credit`; есть `BuyPickaxe`/`BuyWeight`/`Train` и миграция v1→v2 |
| `ReplicatedStorage/DogEconomy/{ItemDefinitions,DepthDefinitions,WeightProfiles,MutationDefinitions,SetDefinitions}.luau` | Данные находок в виде JSON-таблиц: 108 предметов на 5 глубин, профили веса, 5 мутаций предметов, коллекции |
| `ReplicatedStorage/ItemValuation.luau` + `ItemValueConfig.luau` (Version=6) | Единственная формула цены находки (`V.Price`) и её ожидаемое значение (`V.Expected`). Мягкий предел — `IncomeReference×3600×60` |
| `ReplicatedStorage/DogEconomy/Bonuses.luau` + `BonusSources/{UpgradeTree,Accessories,Artifacts}.luau` | Конвейер бонусов, 12 ключей. Ключ `DepthSpeed` объявлен, но **нигде не используется** |
| `ReplicatedStorage/DogEconomy/BoostPricing.luau` | Цены, которые следуют за доходом: `Boost`, `Coins{MinCash,IncomeMinutes}`, `Floor = Cash×LayerScale[глубже всего открыто]`, пик дохода с полураспадом 6 ч |
| `ReplicatedStorage/DogEconomy/UpgradeTree.luau` | 38 узлов в 11 ветках, 324 уровня. Полное дерево стоит **96,47 млрд** монет и 14 245 костей; одни вершины — 86,2 млрд (посчитано в Lune) |
| `ServerScriptService/Economy/Rules.luau` | Профиль (`R.Profile`/`Normalize`/`Validate`), `R.Dig` (стр. 334), `R.Cooldown`, `R.RollMultiplier`, `R.Credit`/`R.Pay`, `R.MiningAction` (стр. 121), `R.Action` (слои, бусты, удача, косметика, престиж, награды) |
| `ServerScriptService/Economy/IncomeModel.luau` | Ожидаемый доход по тем же функциям, что и `Rules.Dig`, с кэшем форм способностей на 5 минут |
| `ServerScriptService/Economy/ItemRules.luau` | Шанс находки, мутации, `Mint` (`IncomeMult` фиксируется на предмете), `ExpectedFind`. `I.NPCValue` (стр. 168) — **мёртвый код** |
| `ServerScriptService/Economy/{Engine,Market,Transactions,StoreKeys,Runtime}.luau` | Транзакции, конвейер, обмен (`E:Trade`), рынок и аукцион, DataStore, сетевой вход |
| `ServerScriptService/Economy/{OfflineEarnings,SupplyRules,LuckRules,YardCommerce}.luau` + `ReplicatedStorage/OfflineEarningsConfig.luau` | Оффлайн 20 % на 2 часа, таймеры бустов, продажа находок по **живой** цене `Value.Price` |
| `tools/balance_sim.py` | Симулятор шахты: читает `MiningConfig` и только печатает результат |

### 3. Как работает сегодня

**Откуда приходят деньги:**
- `R.Dig` → `payIncome` → `R.Credit` (учитывается в `Lifetime.TotalCoinsEarned` и в лидерборде Coins);
- продажа находок: `YardCommerce` `NPCSell`/`BulkSell`, цена `Value.Price(x)`;
- шахта: `MiningRules.Hit` → `ctx.Credit` → `R.Credit`;
- оффлайн-доход: `OfflineEarnings.Claim`;
- ежедневные и игровые награды (фиксированно 800–28 000);
- подбор предметов во время мировых событий: фиксированные **40 монет и 2 кости** (`WorldEventConfig.Interactions`, `WorldEventService.Interact` стр. 47);
- рынок и обмен (переводы между игроками);
- Robux-наборы (`BoostPricing.Coins`).

**Куда деньги уходят:**
- собаки с конвейера (3,5K–450M, при перекупке цена ×1,3);
- слои (16K / 120K / 900K / 8M плюс пороги уровня 5/12/22/35 и престиж 1 для VOID);
- дерево улучшений (96,5 млрд);
- бусты и удача (доля дохода);
- кирки и гири;
- лаборатория: реролл `5000+1500×ранг` монет и `5×ранг` костей (`LabConfig.Costs`, `LabGenetics.Cost`);
- скины участка 6K–500K (`PlotCatalog.Skins`, цены ×5, стр. 33) и `C.Cosmetics` 50K–1M;
- престиж;
- комиссия рынка 1 % и налог 5 %.

**Доход собак.**
1. `Engine:TickAll` раз в секунду по каждому игроку запускает `R.Normalize` → `R.Dig` → `Offline.Checkpoint` (модель на «тихой» копии только работающих собак) → `R.Validate`.
2. Ценность броска = `item[4] × RollMultiplier`. В `RollMultiplier` входят:
   - `R.Bonus` (вариант, мастерство, вознесение);
   - сила редкости `Power`;
   - старый ограниченный блок (`SetBonus`, `Plot`/`Kennel`, `SellValue` ≤ .5);
   - Golden Biscuit;
   - `Bonuses.ValueFactor` = (1+Income)·MoneyMult·(1+DogPower).

**Находки.**
- `ItemRules.Pick`/`Mint`. Цена считается в момент находки (`x.SellValue`, `ValueVersion`), а у сборщика пересчитывается **заново** по текущему `ItemValueConfig`.
- Поэтому изменение `ItemValueConfig` меняет цену всех старых предметов при продаже.

**Шахта.**
1. Руда выпадает со случайным весом. `Luck` кирки сдвигает выпадение к редкой руде.
2. Стоимость = `rand(ValueMin..ValueMax) × LayerValue[MaxUnlockedLayer]`. Множитель берётся по **самому глубокому открытому** слою, а не по текущему.
3. Каждый удар платит `35 % × доля снятого HP`, удар-разлом платит остаток. `CoinBonus` кирки даёт до ×2.
4. В оплату не входят ни бонусы дерева или экипировки, ни Golden Biscuit.
5. Опыт даётся только за разлом: `2 + тир`.

### 4. Что такое «камень» и сколько он стоит

«Камень, который добывается на участке» — это куча руды мини-шахты `MiningCorner` возле будки K1. Первая и самая частая руда — Известняк 🪨 (30 % выпадений). Есть альтернативное прочтение: обычная добыча собак. Её рычаг — `C.LootValueScale`, но он сдвинет весь доход собак, а вместе с ним бусты, Robux-наборы и оффлайн. Для F11 это **не рекомендуется**.

| Слой | Известняк сейчас | Кристалл Пустоты сейчас | Средний бросок обычной добычи собаки (`Config.Layers` после `LootValueScale`) | Средняя находка (`ItemValuation.Expected` с учётом шансов) |
|---|---|---|---|---|
| 1 Backyard | 40–55 | 12K–16K | 151 | 130 |
| 2 Caverns | 120–165 | 36K–48K | 324 | 385 |
| 3 Ruins | 240–330 | 72K–96K | 634 | 1,2K |
| 4 Cursed | 480–660 | 144K–192K | 1 567 | 4,1K |
| 5 VOID | 960–1 320 | 288K–384K | 3 296 | 13,7K |

### 5. Кирки (MiningConfig стр. 57–85) и доход добычи сейчас

Доход в монетах в минуту — из симулятора: умелость 0,6, сила = требование + 50, 120 минут, одинаковые seed.

| # | Кирка | Цена | Сила | Урон | Круги | Монеты | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Wooden | 600 | 0 | 1 | 1 | +0 | 929 | 2,5K | 5,4K | 13K | 25K |
| 2 | Stone | 7 500 | 25 | 2 | 1 | +0 | 2,2K | 6,7K | 13K | 22K | 52K |
| 3 | Iron | 45 000 | 80 | 4 | 1 | +10 % | 4,6K | 14,8K | 30K | 49K | 116K |
| 4 | Steel | 260 000 | 180 | 6 | 2 | +15 % | 9,5K | 30K | 59K | 108K | 234K |
| 5 | Crystal | 1 600 000 | 340 | 11 | 2 | +30 % | 16K | 51K | 97K | 186K | 382K |
| 6 | **Inferno** | 12 000 000 | 580 | 24 | 3 | +55 % | 27K | 80K | 163K | 318K | 650K |
| 7 | **Voidbreaker** | 85 000 000 | 1000 | 125 | 3 | +100 % | 39K | 124K | 245K | 508K | 903K |

**Топовые и самые редкие кирки** — Inferno и Voidbreaker; Crystal — переходная. Гири: 0 / 3K / 20K / 120K / 750K / 5M / 25M. Voidbreaker требует 1000 силы, а её даёт только последняя гиря, Масса Пустоты (25M).

### 6. Денежная кривая по стадиям (Lune, `Rules.IncomeModel` на реальном коде)

Пороги опыта (`C.XPForLevel`): уровень 5 — 886, 12 — 4 704, 22 — 13 674, 35 — 30 281, 50 — 55 343.

| Стадия | Ключевые траты | Собаки/мин, старые улучшения | + полное дерево | Добыча кирки стадии |
|---|---|---|---|---|
| L1 Backyard | Common 3 500; кирки 600 / 7 500; слой 2 — 16K и уровень 5 | 1,1K (1 Common), 6,6K (5 Common, Plot 4) | 32,6K / 178K | Stone 2,2K |
| L2 Caverns | Rare 22K; Iron 45K; Steel 260K; слой 3 — 120K и уровень 12 | 37,3K (5 Rare, средние улучшения, M20) | 773K | Iron 14,8K (40 %) |
| L3 Ruins | Epic 140K; Crystal 1,6M; слой 4 — 900K и уровень 22 | 122K | 1,84M | Steel 59K (49 %) |
| L4 Cursed | Legendary 900K; Mythic 6,5M; Inferno 12M; престиж 12M·(n+1) с уровня 35; VOID — 8M | 1,16M | 13,6M | Crystal 186K (16 %) |
| L5 VOID | Secret 55–450M; Voidbreaker 85M; дерево 96,5 млрд | 4,52M (Mythic) – 7,74M (Secret) | 45,4M–71,3M | Voidbreaker 0,9M (12–20 %) |

### 7. Предложение F11 (рекомендуемый вариант «B»)

**7.1 Камень дороже на старте и глубже.**
- Все `ValueMin`/`ValueMax` руды умножаются на ×2.
- `LayerValue` {1,3,6,12,24} → **{1,3,6,18,48}**.
- Итог: на слоях 1–3 ×2, на слое 4 ×3, на слое 5 ×4.
- Новые цены руды:

| Руда | Новая цена |
|---|---|
| Известняк | 80–110 |
| Уголь | 130–180 |
| Медь | 210–290 |
| Железо | 340–460 |
| Золото | 600–800 |
| Кварц | 950–1 250 |
| Аметист | 1 500–2 000 |
| Рубин | 2 600–3 400 |
| Изумруд | 4 400–5 800 |
| Алмаз | 7 500–9 500 |
| Метеорит | 13 000–17 000 |
| Кристалл Пустоты | 24 000–32 000 |

- Известняк по глубинам: 80–110 / 240–330 / 480–660 / 1 440–1 980 / 3 840–5 280.
- Это **≈0,6× среднего броска собаки на L1** и **≈1,2–1,6× на L5**.
- Глубину F5 «Поверхность → Глубина 1 → 2 → 3 → Редкие зоны» стоит привязать один к одному к слоям 1..5 и к этим множителям.
- Почему L4/L5 растут сильнее: добыча собак за бросок растёт по слоям ×1 / 2,1 / 4,2 / 10,4 / 21,8, а сверх того собак умножает сила редкости (Legendary 5,4 … Secret 14,5). У игрока такой силы редкости нет.

**7.2 Топовые кирки дороже в несколько раз.**

| Позиция | Сейчас | Предложение | Во сколько раз |
|---|---|---|---|
| Кирка Crystal | 1,6M | 4M | ×2,5 |
| Кирка **Inferno** | 12M | **60M** | ×5 |
| Кирка **Voidbreaker** | 85M | **600M** | ×7 |
| Гиря Crystal Weight | 750K | 1,5M | — |
| Гиря Inferno Core | 5M | 20M | — |
| Гиря Void Mass | 25M | 120M | — |

- Wooden, Stone, Iron, Steel и первые гири остаются как есть. Цена 600 у Wooden прописана текстом в `OnboardingGuide.luau:21` и в `DOGROTS_AutoTranslateUI` (стр. 149, 156).
- Агрессивный вариант — Voidbreaker 1 млрд — имеет смысл только вместе с фазой 2 (п. 7.5).

**7.3 Обоснование: доход в минуту по стадиям, сейчас → после.**

| Стадия | Кирка стадии | Сейчас | После | Доля от дохода собак (старые улучшения) | Доля от полного дерева |
|---|---|---|---|---|---|
| L1 | Stone | 2,2K | 4,4K | 66 % от 5 Common, 4× одной собаки | 2,5 % |
| L2 | Iron | 14,8K | 29,6K | 79 % | 3,8 % |
| L3 | Steel | 59K | 119K | 97 % | 6,5 % |
| L4 | Crystal | 186K | 558K | 48 % | 4,1 % |
| L5 | Voidbreaker | 0,9M | 3,6M | 47–80 % | 5,1 % |

Так восстанавливается документированный принцип «добыча ≈ 0,5–1× дохода собак без дерева». Собаки при этом остаются главным источником дохода.

**7.4 Окупаемость.**
- Inferno за 60M: на L4 — 35 минут общего дохода (собаки + добыча), на L5 — 6,5 минуты без дерева и 0,8 минуты с полным деревом. Сейчас — 9 и 1,5 минуты.
- Voidbreaker за 600M: на L5 — 58 минут общего дохода без дерева и 8,4 минуты с полным деревом. Сейчас — 10 и 1,2 минуты.
- Только добычей Voidbreaker окупается примерно за 10 часов: это престижная цель, а не обязательная покупка.

**7.5 Фаза 2 (по желанию, M): новый ключ `MiningValue` в `Bonuses.Keys`.**
- Ключ фиксируется в `OreValue` в момент выпадения руды — так же, как `IncomeMult` на предметах.
- Источники:
  - новая ветка дерева «MINING»: 3 узла и вершина, суммарно до +3,25;
  - аксессуары со `Stat="MiningValue"`.
- С полным деревом и полной веткой Voidbreaker на L5 даст ≈ 15M/мин, то есть ≈ 21 % дохода собак с деревом. После этого цену Voidbreaker можно поднять до 1–1,5 млрд.

**7.6 Совместимость.**
- Миграция не нужна: `p.Mining` хранит только номера купленных кирок и гирь (`PickaxeOwned`/`WeightOwned`). Уже купленные кирки остаются у игроков.
- Текущая куча руды хранит своё `OreValue` до разлома.
- `MiningConfig.Version` не меняется. Поднять стоит `C.BalanceVersion` — он только пишется в лог.
- IncomeModel, бусты, Robux-наборы и оффлайн не затрагиваются: доход шахты в них не входит.
- Лидерборд Coins (`TotalCoinsEarned`) будет расти быстрее.

**7.7 Что закрепляет текущие числа.**
- `tests/mining_rules.luau` проверяет только соотношения: цены и требования силы растут, Voidbreaker ломает руду за ≤ 2 удара, `M.LayerValue`, `4200 - M.Pickaxes[1].Price`. Вариант B на копии в scratch проходит **17/17 без правок тестов**.
- `tests/lab.luau:199-209, 325, 416` закрепляет цены лаборатории (нужно для F12).
- Для фазы 2: `tests/income.luau:324-337` (таблица ключей конвейера: добавить `MiningValue` без влияния на доход собак), `tests/upgrade_tree.luau:85-110` (правила узлов), `tests/equipment.luau:110`.
- Документы:
  - `docs/MINING.md` §3: таблицы руды, кирок, дохода по слоям и гирь, принцип «0,6–1×»;
  - `docs/ECONOMY.md`: добавить раздел F11;
  - `docs/UPGRADE_TREE.md`: «38 узлов в 11 ветках», «324 уровня» — при новой ветке;
  - `tools/balance_sim.py`: устаревшая строка ориентиров по собакам (стр. 216).

### 8. Сохранённые данные

- **DataStore** `DOGROTS_ECONOMY_V1` через `StoreKeys.Wrap`: ключи длиннее 50 байт заменяются на `h:`+sha256. Ключи:
  - `p:<uid>` (профиль);
  - `line:<uid>` (только в RAM);
  - `supply:<dogId>`, `event:<week>`;
  - `reboot1:auctionQueue`, `reboot1:book:<assetKey>`, `reboot1:inbox:<uid>`, `reboot1:sales:<assetKey>:<day>`;
  - `sa:<op>` / `sl:<uid>:<op>`.
- **Версии:**
  - `p.Version` = `C.Version` = 4;
  - `MegaResetVersion` = 1 — никогда не поднимать без решения владельца (`Rules.Normalize` стр. 48);
  - `p.Mining.Version` = 2;
  - `UpgradeTreeVersion` = 1;
  - `OfflineEarnings.Version` = 2;
  - `ItemValueConfig.Version` = 6 (на предмете — `ValueVersion`);
  - `PlotProgressionVersion` = 1.
- **Поля профиля** — см. список `profileData`.

### 9. Сеть

- **`ReplicatedStorage.DogEconomyRequest`** (RemoteFunction, клиент → сервер, `Runtime.Request`).
  - Ограничение частоты — ведро токенов: 8 токенов, +1,5/с; `MiningHit` стоит 0,25 токена, `MiningTrain` — 0,5, `MarketQuery` — 3.
  - `clean()`: не глубже 3 уровней, не больше 30 полей, строки до 120 символов, числа до `MaxCash`.
  - Ответ: `StateSnapshot` (полная копия профиля) или `StatePatch` (для добычи и продаж).
- **`DogEconomyPush`** — создаётся во время работы.
- **`DogEconomyOpen`**, **`DiscoveryReveal`**, **`DiscoveryAnnouncement`**, **`RewardPresentation`** — RemoteEvent от сервера.
- **Атрибуты игрока:** `IncomePerMinute`, `Level`, `XP`, `Bones`, `CurrentLayer`, `ItemFull`, `MiningRevision` и атрибуты `Mining*`.
- **`leaderstats.Coins`.**

### 10. Мир

- `Workspace.DOGROTS_District.04_PlayerYards/Yard_*`.
  - Атрибуты: `OwnerUserId`, `YardId`, `PlotStage`, `PlotSkin`, `UnlockedKennels`.
  - Дети: `DigSlot_1..5`, `SellAnchor`/`SellInteractionZone`/`Vendor` (сборщик), `UpgradeAnchor`, `Workshop`, `YardLandscape`, `LuckyPad_1..3`.
- `MiningCorner` с `MiningPad` строит `ServerScriptService/MiningWorld` во время работы: в плейсе 0 таких объектов. `Runtime.Request` требует, чтобы игрок стоял не дальше 32 стадов от `MiningPad` (стр. 389–393). Если F5 перенесёт шахту, этот якорь нужно сохранить.
- `11_Shops/COSMETICS`: терминал скинов (`PlotDevelopment.VisitShop`).
- `05_MutationLab`: 1 082 потомка; нужна для F12.

### 11. Клиент и сервер

- Чистые таблицы и формулы общие для клиента и сервера: `Config`, `MiningConfig`, `MiningRules`, `Bonuses`, `BoostPricing`, `UpgradeTree`, `ItemValuation`. Клиент показывает цены тем же кодом.
- Сервер решает всё. Цену буста клиент присылает как `Quote`, допуск ±5 % (`quoted()` в `Rules.luau` стр. 443).
- Удары по руде проверяются по серверным часам с поправкой на пинг. Круги живут только в RAM (`MiningSessions`).

### 12. Производительность

- `TickAll` раз в секунду по каждому игроку: `Normalize` + `Dig` + `IncomeModel` на 5 работающих собаках (≈ 0,4 мс с прогретым кэшем) + `Validate`. Транзакции в RAM, `Timeout=0`.
- `Snapshot` делает **глубокую копию всего профиля** (до 1 000 предметов и 250 собак) и полную `IncomeModel` (по документации ≈ 13 мс на 250 собак). Это происходит после **каждого** успешного `E:Action`. Сетевые всплески могут доходить до сотен КБ.
- Удар по руде идёт облегчённым путём: проверка в RAM, `E:MiningAction` без `Normalize`/`Validate`.

### 13. Найденные проблемы и техдолг

1. Принцип `docs/MINING.md` «добыча 0,6–1× дохода собак» не выполняется: измерено 12–49 % без дерева и 1–3 % с деревом. Ориентиры дохода собак в `balance_sim.py` устарели.
2. Доход шахты обходит конвейер бонусов, поэтому шахта обесценивается поздно в игре.
3. Обмен считает «Estimated» иначе, чем продажа.
   - Для предметов — по сохранённому `x.SellValue` (`Engine.luau:301`), а сборщик платит по живому `Value.Price`.
   - Для собак — только `LinePrice`/`BasePrice` (стр. 306), без варианта, мастерства и вознесения.
4. `BestFinds` и `RecordStats` ранжируют по устаревшему `SellValue`.
5. `I.NPCValue` (`ItemRules.luau:168`) — мёртвый код со своей шкалой {1,1,1,.55,.4}.
6. Количество слоёв (5) прописано вручную: `Rules.luau:480`, `ItemRules.luau:101-102, 111, 171`, `SignatureRules.luau:47`, `Engine.luau:202`, `Runtime.luau:275`, циклы в `DiscoveryScreens`, массивы `ItemValueConfig`/`LootValueScale`/`LayerValue`/`LayerScale`.
7. Ключ `DepthSpeed` объявлен, но не подключён.
8. Реролл в лаборатории стоит фиксированно (не больше 14K монет): монетная часть поздно ничего не значит, реальный ограничитель — кости.
9. Фиксированные награды: подбор во время событий — 40 монет, ежедневные и игровые награды не растут с доходом.
10. `PlotRules` при покупке скина пишет `p.Cash-=d.Cash` напрямую, мимо `R.Pay`.
11. Четыре разных форматтера чисел: `IncomeText.Compact`, `MiningText.Short`, `PriceFormat.Number`, `U.Fmt`.
12. `BoostPricing.Deepest` берёт максимальный открытый ключ, а `Rules.MaxUnlockedLayer` — непрерывную цепочку. На практике это одно и то же.

### 14. Что можно улучшить поверх текущей системы и что требует аккуратного рефакторинга

**Поверх текущей системы:**
- F11 фаза 1 — только данные в `MiningConfig`;
- цены и награды через `BoostPricing.Coins` (`IncomeMinutes`);
- новые источники в `BonusSources` и новые фичи в `Features/*` без правки центральных списков;
- общий модуль цен для обмена и витрины поверх `ItemValuation`;
- экспорт функции редкости из `ItemValuation`.

**Требует аккуратного рефакторинга:**
- ключ `MiningValue` (контракт конвейера и тесты);
- шестой слой или глубина у каждой собаки отдельно (жёсткие пятёрки, ключи кэша `IncomeModel`, оффлайн);
- лёгкий `Snapshot` / дельта-патчи;
- единая цена собаки (сейчас `R.Bonus` только на сервере);
- перевод реролла лаборатории на одну валюту (тесты лаборатории, судьба DNA);
- единый форматтер чисел.

---

## Раскопки собак и глубина (шахта) — digging-depth

> Аудит только для чтения. Каждое утверждение проверено по коду в `src/` или по собранному плейсу `build/DOGROTS_MINING.rbxl` (свои Lune-скрипты лежат в `scratchpad/tools/digging-depth/`). Тесты `tests/kennel.luau` (3/3), `tests/mining_rules.luau` (17/17) и `tests/animations.luau` (12/12) зелёные; в репозитории ничего не менялось.

### 1. Коротко

- **Глубина в данных уже есть. Визуально её нет совсем.** В экономике 5 слоёв: `Config.Layers` и `DogEconomy/DepthDefinitions`:
  1. Backyard;
  2. Caverns;
  3. Ancient Ruins;
  4. Cursed Depths;
  5. THE VOID.

  Профиль хранит `CurrentLayer` (где копают собаки) и `UnlockedLayers`. Слой открывается действием `Layer` за Cash и уровень, а для VOID ещё нужен Prestige 1. Каждый слой даёт свою таблицу обычной добычи (монеты) и свои 20–25 находок. При этом в мире все 5 будок на каждом участке копают на поверхности, в яме 12×12×0.4. Глубину видно только по 6 % оттенку экрана (`EconomyVisuals`) и по тексту в меню.
- **F5 — это визуальный и интерактивный слой поверх существующей пятислойной экономики.** Соответствие один в один: Surface = 1 Backyard, Depth 1 = 2 Caverns, Depth 2 = 3 Ancient Ruins, Depth 3 = 4 Cursed Depths, Rare zone = 5 THE VOID. Для первой фазы новых сохраняемых полей не нужно.
- **Места на поверхности участка нет. Вниз — 32 стада скалы, дальше пустота.** Ниже есть ограничения: на Y < −85 срабатывает возврат упавших (`DistrictSafety`), а `FallenPartsDestroyHeight` = −250. Подробные замеры — в разделе 6.

### 2. Как это работает сейчас (end-to-end)

#### 2.1 Собаки в будках (основной доход)

1. **Назначение.** Клиент отправляет `Assign` в одном из трёх мест:
   - `DogsScreen`;
   - `PawpadController`;
   - меню `ServiceMenus` «Kennels», которое открывается промптом MANAGE через `DogKennelOpen`.

   Запрос идёт через `DogKennelRequest` в `DogKennelService.Handle`, а затем в `Runtime.Request`. Дальше `Engine:Action` вызывает `Rules.Assign` (Rules.luau:432). `PlotRules.Assign` проверяет, что слот `DigSlot_1..5` разблокирован уровнем участка. В профиле записывается `d.AssignedSlot='DigSlot_N'`, `d.State='Digging'` и `d.NextWorkAt`.
2. **Тик.** Каждую 1 с (`Config.TickSeconds`) работает `Runtime.loopOnce` (Runtime.luau:691):
   - сначала `Kennels.UpdateWorkVisuals`;
   - затем `isDue` (:685): игрок «созрел», если у какой-то назначенной собаки прошёл `NextWorkAt`;
   - затем `Engine:TickAll` (Engine.luau:107). Он делает одну RAM-транзакцию на игрока (`Timeout=0`) и вызывает `R.Dig`.
3. **`R.Dig`** (Rules.luau:334), для каждой активной собаки, у которой `now>=NextWorkAt`:
   - `WorkSequence++`;
   - `Signatures.Context` даёт `ctx.Depth=p.CurrentLayer`. Способности вроде `deeper()` могут взять слой +1, но не глубже `R.MaxUnlockedLayer`;
   - броски по `C.Layers[depth].Loot`: монеты сразу идут в кошелёк (`payIncome`), плюс XP, Mastery и Bones;
   - попытки находок: `ItemRules.Pick(depth)` по списку `DepthDefinitions[depth].Items`, затем `I.Mint`;
   - `NextWorkAt=now+cooldown+Work.Duration`. Значения `Config.Work`: Duration 4, BaseCooldown 20, MinCooldown 6, MaxCooldown 30.
4. **Проекция.** После тика вызывается `Runtime.Refresh`, затем `Runtime.Project` (Runtime.luau:105). Он пишет:
   - атрибуты игрока, в том числе `CurrentLayer`, `LayerName` и 25 атрибутов `Mining*`;
   - атрибуты всех записей `DogInventory`.

   Затем вызываются `PlotDevelopment.Reconcile` (PlotAppearance), `Kennels.Reconcile` и `PlotShowcase.Reconcile`. Новые находки младше 30 с уходят владельцу через `DiscoveryReveal` вместе с `LootSpawn` от `KennelLootPlacement.Resolve` (это верх `DarkExcavation` слота собаки).
5. **Модель собаки.** `DogKennelService.prepare`:
   - клонирует `ServerStorage.DogTemplates[VisualAsset]`;
   - `Rig.Prepare` вписывает её в 10×4.2×10, все части становятся Anchored и без коллизий;
   - ставит её на верх `DarkExcavation` (`surface=excavation.Y+Size.Y/2`), у края ямы со стороны будки, лицом к `DigCenter`;
   - добавляет BillboardGui `SleepLabel` (MaxDistance 55, AlwaysOnTop=false);
   - кладёт модель в `Workspace.DOGROTS_District.KennelDogs`.

   Атрибуты работы пишутся только при изменении (`put`): `AnimationName` Work/Idle, `Producing`, `StorageFull`, `FindsFull`, `NextWorkAt`, `WorkSequence`, `WorkCycle`, `AssignedAt`.
6. **Анимация на клиенте.** `DogAnimations.client` в цикле PreSimulation вызывает `DogAnimationPlayer:UpdateKennel`. Цепочка: Idle → Start → Loop → End, плюс акцент Find/Action, который заканчивается ровно в `NextWorkAt`. Цепочки на собаку задаёт `DogDigProfiles`. Анимация двигает только кости (`Bone.Transform`), CFrame модели не трогает. Кости вне экрана не считаются; дальние собаки обновляются раз в 3 кадра (больше 160 стадов) или раз в 8 кадров (больше 320 стадов). Строку статуса («FIND IN 7s») каждый клиент считает сам.
7. **Находка на клиенте.** `EconomyVisuals.client`: клон из `DiscoveryVisuals` ставится на `LootSpawn`. Одновременно не больше 4, исчезает через 6 с или 14 с. Для редких — тост, звук, зум и тряска камеры.

#### 2.2 «Глубина» в данных — что уже есть

| Где | Что |
|---|---|
| `DogEconomy/Config.luau` `C.Layers[1..5]` | Name, Depth-ярлык («0–10m»… «500m+»), Cost (0 / 16 000 / 120 000 / 900 000 / 8 000 000), Level (1/5/12/22/35), Hardness, Color, Event, Loot (7–8 строк, ценность × `LootValueScale`) |
| `DogEconomy/DepthDefinitions.luau` | `["1".."5"]`: Name, IncomeReference (0.25/0.7/2/5/12), NpcCapHours, Items. Находок по слоям: 20 / 21 / 21 / 21 / 25, всего 108; редких (<1 %): 6 / 11 / 10 / 12 / 17; Secret: 0/0/0/1/3. `ServerScriptService/Economy/DepthDefinitions` — просто прокси на этот модуль |
| `ItemDefinitions[id].Depth` | 1..5 у каждого предмета; по нему фильтруют инвентарь и маркет, им пользуются рекорды (`records:<depth>`) и Dogdex |
| Профиль | `CurrentLayer`, `UnlockedLayers{['1']=true}` (Rules.luau:36) |
| `Rules.Action 'Layer'` (Rules.luau:479) | открыть следующий слой (нужен предыдущий и уровень, для 5 — Prestige≥1 захардкожен) за `def.Cost`, +100×L XP; выбор `CurrentLayer` |
| `Prestige` (Rules.luau:537) | нужны уровень 35 и слой 4; сбрасывает `CurrentLayer=1`, `UnlockedLayers` сохраняются |
| Способности | `SignatureRules.Context`: `deeper()` (слой+1, ценность ×.65); бонусы CactusCorgi, Pharaohound и VoidHound по `CurrentLayer`; `Hardness`; TheDog Genesis → Depth 5 |
| Прочее | `MiningConfig.LayerValue={1,3,6,12,24}` (по самому глубокому открытому слою); `BoostPricing.LayerScale`; `WorldEventDefinitions` Depth/DepthLuck (BONE_RAIN 1, CRYSTAL_STORM 2, CURSED_FOG 4, BLACKOUT 4, UFO_INVASION 5); `RecordStats` `p.Stats.Depths[k]={Finds,BestWeight,BestValue,Item}`; `DogDefinitions.LayerAffinity/MinLayer` (MinLayer везде 1); зарезервированный бонус-ключ `DepthSpeed` («для будущей системы глубины», `Bonuses.Keys`, нигде не используется) |
| UI выбора слоя | `ServiceMenusController` mode `Layers` (кнопка двора `DiggingLayers`) и `EconomyScreens` Page `Layers` — две отдельные реализации |

#### 2.3 Активная добыча (Mining Corner, отдельная мини-игра)

- **Сервер.** `MiningWorld.server` (`LAYOUT_VERSION=24`) во время работы строит на каждом участке модель `MiningCorner`, около 45 частей и 7 гирь. Она стоит на краю CosmeticGarden со стороны будки 1: для Yard_04 это (−111.5, 135), площадка 23×18. Модель имеет `ModelStreamingMode.PersistentPerPlayer`, владелец добавлен через `AddPersistentPlayer`. Состояние владельца переносится в атрибуты корнера. Кирка или гиря приваривается к руке.
- **Правила.** Чистые правила — `ReplicatedStorage/Mining/MiningRules` (тестируются в Lune):
  - круги таймингов живут в RAM, `Economy/MiningSessions`;
  - качество удара оценивает сервер с поправкой на пинг;
  - руда и её ценность бросаются при разломе: `ValueMin..Max × LayerValue[MaxUnlockedLayer]`.
- **Маршрут запроса.** `Runtime.Request`, ветка `Mining*`: проверка дистанции не больше 32 стадов до `MiningPad`, предварительная проверка цели в RAM, затем `Engine:MiningAction` — облегчённая транзакция без Normalize/Validate, затем `Runtime.RefreshMining`.
- **Клиент.** `MiningClient` (Net/Anim/FX/Hud/World/Mine/Shop/Gym/Debug). В `World.luau` есть образцовая обработка StreamingEnabled: вид создаётся, как только пришла модель; куски регистрируются по `DescendantAdded`; куча строится, только когда пришёл `MiningOreCore`; при выгрузке ядра удаляется. Это готовый шаблон для чанков шахты.
- **Studio.** `MiningStudioTest.server` — F8-панель, только в Studio; команда `layers` открывает все слои.

#### 2.4 Global Dig (08_GlobalDigSite) — выключен

- `GlobalDigConfig.Enabled=false`. `GlobalDigService.Start` ставит атрибут `ComingSoon` и выключает промпты; `GlobalDigPresentation.client` сразу выходит.
- Карьер с уровнями `UpperLevel=-18` и `LowerLevel=-42` (X 34..204, Z 532..744) содержит **1170 частей. Все прозрачные и без коллизий, ни одного включённого света или SurfaceGui**. Сверху его закрывает `37_AttractionRefresh.GlobalEventComingSoon.OpaqueBlackCuboid` 182×99×214.
- Код, если включить: `Service.Dig` у станции → транзакция → `I.Pick(p.CurrentLayer)` → `I.Mint`, плюс вклад в `event:<week>`.

### 3. Файлы и роли

| Файл | Роль |
|---|---|
| `src/ServerScriptService/DogKennelService.luau` | модели собак в будках, атрибуты работы, промпт MANAGE, обработчик `DogKennelRequest` |
| `src/ServerScriptService/DogKennels.server.luau` | одна строка: `DogKennelService.Start()` |
| `src/ServerScriptService/Economy/KennelLootPlacement.luau` | маркер `LootSpawn` на `DarkExcavation`, `Resolve` → CFrame появления находки |
| `src/ServerScriptService/Economy/Rules.luau` | `Profile`, `Dig`, `Assign`, `Layer`, `Prestige`, `MaxUnlockedLayer`, `MiningAction`, `Storage` |
| `src/ServerScriptService/Economy/SignatureRules.luau` | способности собак, `Context` (Depth), своя копия `maxUnlockedDepth` |
| `src/ServerScriptService/Economy/IncomeModel.luau` | ожидаемый доход (HUD, офлайн); кэш форм по `CurrentLayer` |
| `src/ServerScriptService/Economy/Engine.luau` | транзакции `Action`, `MiningAction`, `Tick`, `TickAll`, `EventClaim` |
| `src/ServerScriptService/Economy/Runtime.luau` | цикл экономики, `Project`/`Refresh`, маршрутизация `Request`, `RevealExcavation` |
| `src/ServerScriptService/Economy/ItemRules.luau` | `Pick(depth)`, `Mint`, `ItemChance` (EventDepth) |
| `src/ServerScriptService/Economy/DepthDefinitions.luau` | прокси на ReplicatedStorage-версию |
| `src/ReplicatedStorage/DogEconomy/DepthDefinitions.luau` | состав находок по глубинам |
| `src/ReplicatedStorage/DogEconomy/Config.luau` | `Layers`, `Work`, `LootValueScale`, Prestige |
| `src/ReplicatedStorage/DogEconomy/MiningConfig.luau` | руда, кирки, гири, `LayerValue` |
| `src/ReplicatedStorage/DogDigProfiles.luau` | цепочки копания по породам |
| `src/ReplicatedStorage/DogAnimationPlayer.luau` | проигрыватель клипов, `UpdateKennel`, подъём над землёй |
| `src/ReplicatedStorage/DogRig.luau` | `Prepare`/`Place`, масштаб и `GroundLocal` |
| `src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau` | анимации собак, отсечение невидимых, ярлыки статуса |
| `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` | оттенок экрана по слою, «+$», показ находок у ямы |
| `src/ServerScriptService/MiningWorld.server.luau` | постройка корнера, перенос состояния, предметы в руке |
| `src/ServerScriptService/Economy/MiningSessions.luau` | круги в RAM |
| `src/ServerScriptService/MiningStudioTest.server.luau` | F8-читы, только Studio |
| `src/ReplicatedStorage/Mining/{MiningRules,MiningModels,MiningText,MiningAudio}.luau` | правила, процедурные модели, тексты, встроенные звуки |
| `src/StarterPlayer/StarterPlayerScripts/MiningClient(.client).luau` + `MiningClient/*` | клиент активной добычи |
| `src/ServerScriptService/Economy/GlobalDigService.luau` + `GlobalDigBootstrap.server.luau` | Global Dig (выключен) |
| `src/StarterPlayer/StarterPlayerScripts/GlobalDigPresentation.client.luau` | презентация карьера (выключена) |
| `src/ReplicatedStorage/PlotAppearance.luau` | стадии и скины участка; показывает и прячет части DigSlot по `PlotBase*`-атрибутам |
| `src/ServerScriptService/DistrictSafety.server.luau` | возврат упавших при Y < −85 |
| UI: `ServiceMenusController.client.luau`, `Modules/EconomyScreens.luau`, `Modules/DogsScreen.luau`, `PawpadController.client.luau` | меню слоёв, будок и назначения |

### 4. Сохранённые данные

- **DataStore** `DOGROTS_ECONOMY_V1` через `StoreKeys.Wrap`: ключи длиннее 50 байт хэшируются.
  - Профиль — ключ `p:<UserId>`.
  - Счётчик Global Dig — `event:<week>`.
  - Глобальные рекорды веса — `records:<depth>`, depth от 1 до 5. **Добавление шестой «экономической» глубины потребует новый ключ и новые данные.**
- **Версии:** `Config.Version=4`, `BalanceVersion="2026-10-11.MINING_V2"`, `MegaResetVersion=1` (не повышать!), `MiningConfig.Version=2`, `p.Mining.Version=2` (миграция v1→v2 в `MiningRules.Normalize`), `p.PlotProgressionVersion=1`.
- **Поля профиля этой подсистемы:**
  - `CurrentLayer`, `UnlockedLayers`, `Prestige`, `LastDig`, `TotalExcavations`, `Pity`;
  - `DogIncome{Total,XPCoins,XPAt}`;
  - `SpecialDiscoveries{LongDogPending,LongDogFoundAt,LastArrivalAt}`;
  - `Dogs[uid]`: AssignedSlot, State, NextWorkAt, WorkSequence, Mastery/MasteryXP, DryStreak/FoodStreak/TreasureStreak, LastAbility(At), LastYield, OrbitValue/Count;
  - `Items[uid]`: Depth, SourceDogUid; `DiscoveryFeed` (20 шт.), `Collection`, `RecordJobs`;
  - `Stats.Depths`;
  - `Upgrades.Plot` (число слотов);
  - `Mining{...}` (около 30 полей: Strength, PickaxeOwned/Level, WeightOwned/Level, OreId/Index/HP/MaxHP/Value/Earned/Serial, Hits, OresBroken, CoinsEarned, Collection, ActiveUntil, TrainingUntil…);
  - `NextCommunityDig`, `Event`, `EventTokens`, `Lifetime.GlobalDigContribution`.
- **Только в RAM:** `MiningSessions` (круги), `Runtime.Views`, атрибуты моделей.

### 5. Сеть

| Канал | Направление | Данные |
|---|---|---|
| `ReplicatedStorage.DogKennelRequest` (RF) | C→S | `(action 'Assign'|'Remove', uid, slotName)` → `ok,message`; лимит `Runtime.Allow(.5)` |
| `ReplicatedStorage.DogKennelOpen` (RE) | S→C | `slotName` (MANAGE у своей будки, ≤14 стадов) |
| `ReplicatedStorage.DogEconomyRequest` (RF) | C→S | `(action,args,requestId32)`: `Layer{Layer}`, `Assign/Remove`, `Mining*` (Begin/End/Hit{Target,Quality,Miss}/Pickaxe{Level}/Weight{Level}/Train/TrainBegin/TrainEnd), `Snapshot`, `EventClaim`; ответ `StatePatch`/`StateSnapshot` |
| `ReplicatedStorage.DiscoveryReveal` (RE) | S→владелец | сводка находки + `LootSpawn{CFrame,DogUid,Slot,YardId,OwnerUserId}` |
| `ReplicatedStorage.DiscoveryAnnouncement` (RE) | S→все | `(x, global)` для TierIndex ≥ 8 или Secret, не чаще раза в 15 с |
| `ReplicatedStorage.DogEconomyOpen` (RE) | S→C | сообщения Global Dig |
| `ReplicatedStorage.RewardPresentation` | S→C | раскрытие LongDog |
| `ReplicatedStorage.Mining.MiningStudioControl` (RF, создаётся в Studio) | C→S | читы |

Через атрибуты по сети идут:

- атрибуты игрока: `CurrentLayer`, `LayerName`, `Mining*` (25 шт.) и `MiningRevision` — видны всем клиентам;
- атрибуты `MiningCorner` (около 20);
- атрибуты модели собаки (около 18);
- атрибуты слота: AssignedDogUid, AssignedOwnerUserId, AssignedDogName, Unlocked, RequiredYardLevel;
- все скалярные поля собаки на `DogInventory/<uid>`.

### 6. Мир: инстансы и замеры

#### 6.1 Участок (Yard_04_Lantern Court, Studio всегда даёт его)

- 8 участков, 2×4, одинаковые; восточные зеркальны по X. На один участок 1 556 инстансов и 1 430 BasePart.
- Атрибуты участка: YardId, OwnerUserId, OwnerDisplayName, PlotStage, PlotSkin, UnlockedKennels, AppearanceRevision. `YardFootprint=110,1.2,66` и `DigSlotSize` нигде в коде не читаются.
- **Основание:** `YardLandscape/YardFoundation` 134×1×70, Grass, Y 0..1, центр (−105, 117). Поверх него:
  - `WorkArea` 47×0.2×62 (X −88.5..−41.5, Z 86..148);
  - `EntryWalk` 124×9 (Z 112.5..121.5);
  - `UtilityApron` (X −171..−149: DogStorage, Vendor, Workshop);
  - `LuckyCourt` (X −134.5..−97.5, Z 86.5..107.5, 3 LuckyPad);
  - `CosmeticGarden` (X −138.5..−99.5, Z 126..148), на нём стоит MiningCorner.
- **DigSlot_1..5** — Model. Атрибуты: DigCenter, DigSize=(12,.4,12), ApproachPosition, SlotIndex, RequiredYardLevel, Unlocked. Содержимое:
  - `DarkExcavation` 12×0.4×12, Ground, Y 0.8..1.2, с Attachment `LootSpawn`;
  - 4 `PitTimber` по краю;
  - будка: KennelFloor/Back/Wall×2/Lintel/Roof×4;
  - SlotMarker, DogBowl;
  - во время работы — `KennelFloor/KennelInteraction` + ProximityPrompt.
- **Центры ям** (западные; восточные — с +X): X −81, −65, −49; слоты 1/3/5 на `zc+13`, слоты 2/4 на `zc−13`. Здесь `zc` — z центральной дорожки участка: −117, −39, 39 или 117.
  - Между ямами по X 4 стада. Между рядами 14 стадов, в них дорожка 9 стадов.
  - Ближайшие ямы соседних участков на одной стороне — 52 стада (по Z). Через улицу — не меньше 98 стадов.
  - Будка стоит за ямой, дорожка — перед ней. `ApproachPosition` (у Yard_04 слот 1: (−81, 2, 122.5)) — это точка у края дорожки.
- **Заблокированный слот:** `DarkExcavation` прозрачна и без коллизий, `PlotDevelopment/FutureGarden` (12×12, Y 1.26) тоже **без коллизий**. Игрок стоит на `WorkArea`/`YardFoundation`.
- `PlotDevelopment/BestFinds` (витрина) занимает место «шестого слота» около (−50, 97), X −55.5..−44.5, Z 85.5..108.5. Объём шахты слота 4 он не пересекает (проверено AABB с учётом поворота).

#### 6.2 Что под участком

- Terrain пустой: `SmoothGrid` всего 2 байта.
- Под всеми участками и улицей лежит плита `01_IslandAndStreets/CohesiveIsland`:
  - `IslandMass` — Rock 360×32×12, срезы по Z через каждые 12 стадов, Y −32..0. Один срез общий для западного участка, улицы и восточного участка;
  - `LivingGround` — Grass, Y −0.4..0, такие же срезы.
- **Под WorkArea ниже −32 нет ничего до −250.** `LayeredCliffs` (до −42) есть только по краю острова, X ±126..±221.
- В объём шахты 12×12 у слота пересекаются только: 2 среза IslandMass + 2 среза LivingGround, `YardFoundation`, `WorkArea`, невидимая `YardCustomization/GroundThemeArea`, `DarkExcavation` и (у закрытого слота) `FutureGarden`.
- Вертикальный бюджет:
  - плита: 32 стада;
  - от −32 до порога возврата `DistrictSafety` (−85): 53 стада ходимого объёма;
  - до `FallenPartsDestroyHeight` −250: 218 стадов.

#### 6.3 Вокруг участка

- Между участками по Z щели по 8 стадов (заборы).
- Между рядами участков улица 76 стадов (DogLine).
- Позади участка 8 стадов плиты, затем обрыв.
- **Свободного места на поверхности нет**: WorkArea занята 5 слотами и витриной, сад — корнером и декором.

#### 6.4 Стриминг

- `StreamingEnabled=true`, `StreamingMinRadius=64`, **`StreamingTargetRadius=1024`**. Остров примерно 430×1000, поэтому почти весь район приходит каждому клиенту.
- Вывод: **серверная геометрия шахты попадёт ко всем**. Её надо держать минимальной, а детали строить на клиенте.
- `MiningCorner` уже `PersistentPerPlayer`. Остальные модели участка — Default.

### 7. Клиент / сервер

- **Сервер решает всё** (экономика, броски, назначения) и строит модели собак и корнер. Анимации на сервере нет.
- **Клиент** делает кости, ярлыки, находки, кучу руды, мини-игру и меню. У клиента нет бросков — только показ серверных результатов.

### 8. Производительность

- **Сервер:**
  - цикл 1 с;
  - `Project` вызывается на каждый «созревший» тик игрока (раз в несколько секунд при 5 собаках) и делает полную проекцию: все атрибуты и все записи `DogInventory`, а также PlotDevelopment, Kennels и PlotShowcase;
  - `Kennels.Reconcile` на каждый Project:
    - пересчитывает `Rules.Team`/`Cooldown`;
    - **обнуляет и снова пишет** атрибуты слотов (см. баг 4);
  - `MiningWorld` — цикл 1 с по владельцам.
- **Клиент:** самый тяжёлый цикл — `DogAnimations` PreSimulation, с culling и прореживанием. `WorldDetailQuality` раз в 0.4 с сканирует все Light и ParticleEmitter района:
  - High: максимум 24 источника света в радиусе 160 и 50 единиц Rate частиц;
  - Low/мобильный: 8 источников в радиусе 85 и 8 единиц Rate.

  Любой новый свет шахты конкурирует за этот бюджет.
- **Мир:**
  - Workspace — 37 587 инстансов;
  - 8 участков — около 11.4K BasePart;
  - мёртвый карьер — 1 340 инстансов;
  - модели собак в будках — в среднем около 52 инстансов, до 40 моделей (около 2.1K).

### 9. Баги и техдолг (найдено)

1. **VOID без Prestige в меню.** `ServiceMenusController.client.luau:249` проверяет `(def.Prestige or 0)`, но в `Config.Layers` поля `Prestige` нет, а Rules.luau:483 захардкодил Prestige 1 для слоя 5. Поэтому карточка VOID показывает UNLOCK/ready без Prestige, а сервер отказывает. Источник правды разделён: `EconomyScreens:200` тоже хардкодит « · Prestige 1».
2. **Устаревший текст Prestige.** `EconomyScreens.luau:203`: «Requires Level 25 … Costs 250000×(P+1)». На самом деле `C.PrestigeLevel=35`, `C.PrestigeBaseCost=12 000 000`.
3. **MANAGE видят гости.** Промпт MANAGE (`DogKennelService.Start`, :254) включён для всех. `PlotPrompts.client` фильтрует только промпты с именем `YardInteraction`, а у этого имя по умолчанию `ProximityPrompt`. Гости видят MANAGE на чужих будках; сервер их молча игнорирует.
4. **Лишние записи атрибутов.** `DogKennelService.Reconcile` на каждый Project ставит 3 атрибута ×5 слотов в nil и обратно (вместо сравнения с текущим значением, как в `put`). Возможный лишний трафик репликации; не подтверждено, схлопывает ли Roblox такие записи в один кадр.
5. **Дорогая проверка ассета.** `DogKennelService.Handle('Assign')` ради неё делает полный `prepare`: Clone + `Rig.Prepare` + `ScaleTo`, затем Destroy.
6. **Мёртвый карьер.** `08_GlobalDigSite`: 1170 невидимых частей без коллизий остаются в Workspace и стримятся. Сверху чёрный куб. Ничего этого не используется (Global Dig выключен).
7. **Global Dig при включении.** `GlobalDigService.Dig` вызывает `I.Free(p)` без доп. ёмкости. Его эффекты не идут через Bonuses-пайплайн (`RareFind`, `IncomeMult`, ёмкость), в отличие от `R.Dig`. Находки там будут слабее.
8. **Три копии «самого глубокого слоя».** `R.MaxUnlockedLayer`, `SignatureRules.maxUnlockedDepth`, `IncomeModel.maxDepth`; плюс похожая логика в `BoostPricing`, `Dogdex`, `DiscoveryScreens`.
9. **Нет теста** на действие `Layer` (разблокировка, цены, Prestige-ворота, выбор) и на сброс `CurrentLayer` при Prestige.
10. **Разные «глубины» у собак и руды.** Ценность руды в шахте считается от самого глубокого открытого слоя (`MiningLayer`), собаки — от `CurrentLayer`. Это осознанное решение, но визуальная глубина F5 не должна это смешать.
11. **Prestige тихо поднимает на поверхность.** Он ставит `CurrentLayer=1` без визуального сигнала: доход падает, пока игрок вручную не выберет слой снова.
12. **Ярлык закроют стены.** Ярлык собаки (`SleepLabel`, AlwaysOnTop=false, MaxDistance 55) привязан к собаке. Если она уйдёт вглубь, стены его перекроют.
13. **Оттенок на весь экран.** `EconomyVisuals` красит весь экран цветом текущего слоя (6 %) везде на карте.
14. **Мёртвые атрибуты.** `YardFootprint` и `DigSlotSize` не используются и не совпадают с реальным основанием 134×70.
15. **Дыра под закрытыми слотами.** Под заблокированным слотом нет собственной коллизии (DarkExcavation и FutureGarden без коллизий). Если вырезать плиту, игрок провалится, пока не появится «крышка».

### 10. Что можно улучшить поверх / что требует аккуратного рефакторинга

**Поверх текущей системы (без ломки):**

- визуальная шахта (F5, вариант A ниже), которая читает уже существующие `CurrentLayer` и `UnlockedLayers`;
- единый источник требований слоя: добавить `Prestige=1` в `Config.Layers[5]` и читать его в Rules и в обоих UI; исправить текст Prestige;
- промпты будок только для владельца, перенести их к `ApproachPosition`;
- писать атрибуты слотов в `Kennels.Reconcile` только при изменении;
- проверять ассет без клонирования (`AssetReady`, как в Runtime);
- визуальные «редкие жилы» в шахте по `WorldEventModifiers.EventDepth`;
- ключ `DepthSpeed` можно использовать для скорости спуска или косметики;
- тест на действие `Layer`;
- карьер — вынести из Workspace, пока Global Dig выключен (сначала поправить `GlobalDigService.Start`: там `WaitForChild` без таймаута), или переиспользовать.

**Требует аккуратного рефакторинга:**

- **Глубина на собаку или слот.** `d.DigLayer` трогает `SignatureRules.Context` (6 мест с `p.CurrentLayer`), ключ кэша `IncomeModel.shapes`, `OfflineEarnings` и баланс.
- **Объединить расчёт самого глубокого слоя** в одну функцию (`Rules.MaxUnlockedLayer`).
- **Разрезать плиту острова и основание участка** (геометрия). Зависимости:
  - `PlotAppearance.A.Frame` и `MiningWorld.placement` берут `YardFoundation` по имени и позиции;
  - `PlotAppearance.show/remember` восстанавливает `Transparency`/`CanCollide` по атрибутам `PlotBase*`.
- **Разделить `Runtime.Project`** на лёгкую проекцию работы собак и полную проекцию профиля.
- **Global Dig** — включить заново на общем пайплайне находок или удалить.

### 11. План F5 «Глубокая шахта» (подробно)

**Варианты:**

- **A (рекомендуется) — вертикальная шахта под каждой будкой.** Шахта 12×12 вырезается под `DarkExcavation` каждого слота, всего 40. Собаки опускаются на уровень `CurrentLayer`. Раскладка будок, промпты, `DigSlot_N`, `AssignedSlot` и PlotDevelopment сохраняются. Вся глубина помещается в существующую плиту 32 стада: снизу у острова ничего не торчит, `DistrictSafety` не трогаем.
- **B — один большой ступенчатый карьер на WorkArea** (L-образный, около 44×38, дорожка мостом). Смотрится эффектнее, но требует перенести будки, витрину, DigBorder/FutureGarden и переписать PlotAppearance. Риск XL.
- **C (позже, опционально) — ходимая «галерея» под островом** (−40..−80, лифт). Потребует сдвинуть порог `DistrictSafety`, добавить навигацию, безопасность и оболочку снаружи острова.

**Геометрия A** (запад; восток зеркален по X):

- Шахты: X `[cx−6,cx+6]`, Z `[cz−6,cz+6]`, где `cx∈{−81,−65,−49}`, `cz=zc±13`.
- Пол уровня (верх `DigFloor`):

  | Уровень | Слой | Верх пола, Y |
  |---|---|---|
  | L1 Surface | Backyard | **1.2** (как сейчас) |
  | L2 | Caverns | **−7** |
  | L3 | Ancient Ruins | **−15** |
  | L4 | Cursed Depths | **−23** |
  | L5 | VOID | **−31** |

  Шаг 8 стадов; собака не выше 4.2 стада (`Rig.Prepare`), запас 3.8. `ShaftSeal` — Y −32.6..−32.
- Срезы плиты, которые затрагиваются (центры Z): 102/114/126/138, 18/30/42/54, −54/−42/−30/−18, −138/−126/−114/−102. Это 16 IslandMass и 16 LivingGround — около 256 кусков вместо 32. Плюс `WorkArea` и `YardFoundation` каждого участка (около 12 кусков на каждый).
- **Оригинальный `YardFoundation` оставить** невидимой опорой: Transparency 1, CanCollide и CanQuery = false, атрибуты `PlotBase*` переписаны. Куски назвать `YardFoundationTile`, и PlotAppearance должен красить их так же. Иначе сломаются `A.Frame` и `MiningWorld.placement`.

**Сервер** (новый `ServerScriptService/DeepMineWorld.server.luau` + чистый модуль `ReplicatedStorage/DeepMine/MineGeometry.luau`):

1. На старте, идемпотентно (`LAYOUT_VERSION`), разрезать плиту по всем 40 следам: вычитание прямоугольников; копировать Name, Color, Material и атрибуты.
2. На слот построить `yard.DeepMine.Shaft_N` (`ModelStreamingMode=Atomic`, у владельца `AddPersistentPlayer`): `Floor`, `Seal` и 4 невидимых `Guard` высотой 12 (CanCollide, CanQuery=false; это препятствия и для Pathfinding). Всего около 280 частей.
3. **`DeepMine.Reconcile(player,p)`** вызывается из `Runtime.Project` **до** `Kennels.Reconcile`:
   - `layer=p.CurrentLayer`;
   - для каждого слота: `ShaftOpen = Unlocked and layer>=2`;
   - Floor → Y уровня; Guard включены, когда шахта открыта;
   - атрибуты участка `MineLayer`, `MineDeepest`, `MineRevision` писать только при изменении.

   Участок без владельца получает Layer 1, все шахты закрыты.
4. `PlotAppearance` (цикл DigSlot): у `DarkExcavation` при `ShaftOpen` — `show(false)`, она служит крышкой. У закрытого или заблокированного слота крышка видима и коллизионна; если нет, её надо сделать коллизионной принудительно.
5. **`DogKennelService`:**
   - `prepare` берёт верх пола из `DeepMine.FloorTop(slot)`;
   - `Reconcile` перепивотит существующие модели, если `DigLayer` изменился, и пишет `DigLayer`, `DigLayerFromY`, `DigLayerAt`;
   - `SleepLabelAnchor` ставится у верха шахты;
   - промпт переносится на `ApproachPosition` (стойка лебёдки) и показывается только владельцу.
6. `KennelLootPlacement.Marker` переносится на `Floor`. `Runtime.RevealExcavation` — оставить поверхность для кинематики (LongDog выключен: `LongDogChance=0`).

**Клиент** (`StarterPlayerScripts/DeepMineClient.client.luau` + модули Chunks/LOD/Pool/Transitions/Winch/Gauge; конфиг `ReplicatedStorage/DeepMine/DepthVisuals.luau`, цвета из `Config.Layers[k].Color`):

- **Чанк = (участок, слот, полоса k).** Полоса k = `[Floor(k), Floor(k−1)]` в стиле слоя k:
  - Caverns — янтарный камень, кристаллы кварца, крепь и фонари;
  - Ruins — кладка, глифы с голубым свечением, монеты;
  - Cursed — фиолетовый базальт, цепи, свечи, туман;
  - VOID — пол из чёрного стекла, звёздные искры, парящие кубы, фиолетовый свет.
- **LOD по расстоянию** от камеры до центра шахты:
  - меньше 90 стадов — полный (панели стен, 4–8 пропсов на активной полосе, 1 свет и 1 эмиттер на участок);
  - 90–220 — только стены;
  - больше 220 — ничего (видны «сырые» Rock-грани разреза).
- **Бюджет и сборка:**
  - бюджет: не больше 30 инстансов на полосу и не больше 150 на полностью построенный участок;
  - очередь сборки — не больше 40 инстансов за кадр;
  - пул по типу полосы (шаблоны строятся процедурно один раз, как `MiningModels`);
  - планировщик раз в 0.25–0.5 с;
  - свет и эмиттеры кладутся под `DOGROTS_District`, чтобы ими управлял `WorldDetailQuality`.
- **Шаблон стриминга** — как в `MiningClient/World.luau`: вид при появлении модели участка или шахты, пересборка, когда приходят или уходят `Floor`/`Guard`.
- **Над открытой шахтой:**
  - **лебёдка-копёр** (A-рама, колесо, трос до собаки; цвета скина из `PlotCatalog` по `PlotSkin`);
  - **луч или свечение** цвета слоя;
  - **тотем глубины** на участке: 5 колец, горят до самого глубокого открытого, текущее выделено. Это престиж, видят и гости.
- **Переход при росте `MineLayer`:**
  1. пыль и трещины, звук-рецепт `MiningAudio`;
  2. тряска только у владельца ближе 40 стадов и без ReducedMotion;
  3. локальный твин пола и собак 1.6 с от `DigLayerFromY`;
  4. проявление полосы;
  5. баннер «DEPTH 1 · CAVERNS».

  При уменьшении — подъём лебёдкой.
- **Находка (F4):** появляется на полу и поднимается по шахте к краю.
- **«Peek»-камера** по MANAGE: короткий наезд в шахту. Это обязательная мера видимости: шахта 12×12 глубиной 32 с дорожки видна только у края.
- **Low FX/мобильный:** без эмиттеров и света, статичное свечение.

**Открытие уровней.** Без изменений: действие `Layer`, Cash + Level, VOID требует Prestige 1. Сверху добавить:

- мировую «консоль глубины» у будок (промпт владельца открывает `ServiceMenus('Layers')`);
- обновлённые карточки слоёв (F2) с превью: топ-находки из `DepthDefinitions` + `ItemDefinitions` и строки `Loot`.

Prestige закрывает шахты на поверхность; предлагать бесплатно спуститься обратно, раз слои открыты.

**Ресурсы и предметы.** Уже есть по слоям (`Loot` и `DepthDefinitions.Items`); **новые экономические глубины не добавлять** (ключи `records:<depth>`, ItemDefinitions).

**Rare zones:**

- L5 VOID;
- плюс «редкие жилы» во время мировых событий с `Depth` (полоса светится, кристаллы). Удача уже есть в `EventDepthLuck`;
- плюс всплеск по шахте на находку с `BaseDropChance<1%` или Secret.

**Данные.** Фаза 1 — **ноль новых сохраняемых полей**. Старые игроки сразу видят свою глубину, новые — Surface (`R.Profile` ставит `CurrentLayer=1`). Фаза 2 (опционально):

- `d.DigLayer` (nil = как `CurrentLayer`) → действие `SlotLayer`;
- правки `SignatureRules`, `IncomeModel` и баланса (прогнать `tools/balance_sim.py` и `tests/income.luau`).

**Как видят другие.** Геометрия шахт и `Floor` серверные, `MineLayer` — атрибут участка, собаки реплицируются. Чанки детерминированы по (YardId, layer, deepest, skin), поэтому у всех одинаковы.

**Безопасность:**

- Guard высотой 12 вокруг открытой шахты (прыжок около 7.2);
- Floor с коллизией как страховка;
- спасение «если персонаж в объёме шахты ниже Y 0 → телепорт на YardSpawn»;
- Guard коллизионные, чтобы F1-Pathfinding их обходил.

**Тесты (Lune):**

- `tests/deep_mine.luau`:
  - `MineGeometry`: куски не пересекаются, объём = исходный − дыры, все куски внутри исходных, следы для 8 участков;
  - `Reconcile` на фейках: открытие и закрытие по Unlocked/Layer/владельцу;
- `tests/kennel.luau`: собака на полу уровня, переход между слоями;
- тест действия `Layer`.

**Studio вручную:** новый игрок, игрок на L4, Prestige, два клиента, эмулятор iPhone SE, Low FX.

**Нагрузка:**

- сервер: +около 540 статичных частей; никаких циклов на кадр, только реакция на смену слоя или владельца;
- клиент: не больше около 450 частей (3 ближних участка), не больше 6 источников света и 6 эмиттеров;
- сеть: 3 атрибута на участок + CFrame 5 полов и 5 собак на смену слоя;
- новых remote нет.

### 12. Риски

- **Разрез плиты в рантайме** не виден в Studio Edit, только в Play. Это нужно задокументировать или позже «запечь» в плейс.
- **PlotAppearance** «оживляет» скрытые части через `PlotBase*`. Каждую часть, которую прячет шахта, надо согласовать с ним.
- **Промпты будок** станут недоступны за ограждением, если не перенести их к `ApproachPosition`.
- **Видимость дна** узкой шахты ограничена. Нужны peek-камера, свечение и тотем; если мало — вариант B.
- **Мобильный бюджет света** (8) и StreamingTargetRadius 1024: всё серверное грузится у всех.
- **Пересечения с F3, F8 и MiningCorner.** Новые украшения (F8) и витрина (F3) должны обходить следы шахт, Guard и лебёдки.
- **Если сделать глубину на собаку (фаза 2)** — сдвиг баланса: игроки оптимизируют слой под способности (CactusCorgi 1/3, Pharaohound 3, VoidHound 5).

---

## Модели предметов раскопок (item-models)

### 1. Коротко
- Находок (discoveries) **108**, по глубинам 20 / 21 / 21 / 21 / 25 (`DepthDefinitions`: Backyard, Caverns, Ancient Ruins, Cursed Depths, THE VOID). Классы: Artifact 66, Treasure 23, Special 14, Secret 4, World Find 1.
- Отдельного поля «редкость» в определении нет. Редкость считается из `BaseDropChance` по порогам `ItemValueConfig.Rarity`: Secret ≤1e-6 или `Class=='Secret'`, Legendary ≤1e-4, Epic ≤1e-3, Rare ≤1e-2, Uncommon ≤0.05, иначе Common. Функция `rarityOf` локальная в `ItemValuation.luau:4-8`, наружу не экспортируется. Готовое значение сохраняется на предмете в `x.ValueBreakdown.Rarity`. Распределение: Common 23, Uncommon 26, Rare 24, Epic 15, Legendary 15, Secret 5 (`huge_statue` попадает в Secret по порогу шанса).
- Все 3D-модели лежат готовыми в place: `ReplicatedStorage.DiscoveryModels` — 108 Model, **3225 Part** (только `Block`, имена `Voxel0..N`), **0 MeshPart**, материалы Plastic 2927 и Neon 298. У всех частей `CastShadow=true`, `Anchored=true`, `CanCollide/CanTouch/CanQuery=false`, PrimaryPart не задан. Это воксельные силуэты: например, `tennis_ball` — 81 кубик 0.45 studs.
- Различных геометрий всего **60** на 108 id. 72 предмета делят геометрию с другими в 24 группах (подробности в §5).
- Генератора этих моделей в репозитории нет (поиск по `Voxel`, `DiscoveryModels` в `tools/` ничего не дал), они авторские из базового place. `tools/build.py` умеет только патчить Source и создавать скрипты и Folder, поэтому **новые модели можно сделать только процедурно в коде** (по образцу `Mining/MiningModels` и `DogEconomy/EquipmentVisuals`) или ассетами, которые владелец загрузит через Studio.

### 2. Как работает сейчас (от начала до конца)
1. **Определения.** `src/ReplicatedStorage/DogEconomy/ItemDefinitions.luau` — один минифицированный `return {...}` на 34 КБ. Поля каждого id: `Id, DisplayName, Depth, Class, SetId, BaseDropChance, BaseWeightKg, WeightProfile, BaseValue, VisualAsset (у всех 108 == Id), ScaleCap (8, у huge_statue 12), MaxWeightMultiplier (0, у huge_statue 50), Description`. Серверная «копия» `ServerScriptService/Economy/ItemDefinitions.luau` — это прокси в 79 байт (`return require(ReplicatedStorage.DogEconomy.ItemDefinitions)`), дублирования данных нет. Так же устроены прокси `MutationDefinitions` и `WeightProfiles`.
2. **Минт (сервер).** `ItemRules.Mint` (`ItemRules.luau:176-199`) бросает вес (`I.Weight`, 10 тиров TINY..WORLD RECORD) и мутацию (`I.MutationRows:142-159`: NORMAL/GOLDEN/RAINBOW/CURSED/GLITCHED, плюс сигнатурная мутация собаки — имя из `SignatureRules` переводится в верхний регистр: BURNED, FROZEN, INFERNAL, RADIOACTIVE, SOLAR, SPORE, TOASTED, CURSED, GLITCHED). Затем пишет запись в `p.Items[uid]`, копию в `p.DiscoveryFeed` (не больше 20), обновляет `Collection`, `MutationJournal`, `HeavyCollection`, `PersonalRecords` и `Stats` (`RecordStats.Find`, в том числе `BestShowcaseFind/BestShowcaseRelic`).
3. **Показ находки на участке.** `Runtime.Project` (`Runtime.luau:105-120`): для каждой записи ленты моложе 30 с, которую сервер ещё не показывал, вызывается `KennelLootPlacement.Resolve`. Она находит собаку по `SourceDogUid` (или по префиксу `ItemUid`), её `AssignedSlot` (`DigSlot_1..5`) и аттачмент `DigSlot_N.DarkExcavation.LootSpawn`. Если всё нашлось, игроку уходит `DiscoveryReveal:FireClient(player, copy(x)+LootSpawn)`. При `TierIndex>=8` или `Secret` всем уходит `DiscoveryAnnouncement:FireAllClients` (не чаще раза в 15 с).
4. **Клиент.** `EconomyVisuals.client.luau:167-215`: `DiscoveryVisuals.Clone(x)` ставится на `LootSpawn.CFrame` прямо в `workspace`. Одновременно живут не больше 4 моделей, каждая живёт 6 с (14 с при `TierIndex>=7`). На модель вешаются `Highlight`, `BillboardGui` (имя, вес, тир) и тост. Для редких находок играет звук `RareBreak`, при TierIndex≥6 — короткий зум FOV, при ≥7 — тряска камеры, при ≥9 — леттербокс. **Постоянно на участке находки не лежат**: есть только этот временный показ и стенд «MY BEST FINDS».
5. **Стенд «MY BEST FINDS».** Геометрию строит `PlotAppearance.showcase()` (`PlotAppearance.luau:140-175`): 3 пьедестала `Slots.{Find,Dog,Relic}`, вывески `Name<Key>`, `Category<Key>`. `PlotDevelopment.Reconcile` → `BestFinds.Reconcile` вызывается на **каждом** `Runtime.Project`. `BestFinds.Select` (`BestFinds.luau:12-28`) **сам** выбирает лучшую находку класса Treasure и лучший артефакт (Artifact/Special/Secret) по `SellValue`, просматривая `Stats` + все `Items` + ленту. На **сервере** модель клонируется через `DiscoveryVisuals.Clone` и подгоняется под 4.5×4.9×4.5 (`BestFinds.clone:36-53`). Игрок ничего не выбирает и со стендом не взаимодействует.
6. **3D-превью в UI.** Используются ViewportFrame, но по **9 разным путям** (таблица в §3). Часть путей идёт через `DiscoveryVisuals.Clone/Preview`, часть клонирует `DiscoveryModels` напрямую.
7. **Музей.** `MuseumCatalog`, `MuseumService`, `MuseumPresentation.client` и `06_DogDexMuseum` (DexSlot_1..100) показывают **только собак**: в музее нет ни одного экспоната-находки (проверено скриптом по 10 284 потомкам). `DexEntryScreen` — тоже только собаки (`MenuModels`). Коллекция находок живёт только в UI (`DiscoveryScreens` → страница Collection).

### 3. Файлы и роли
| Файл | Роль |
|---|---|
| `src/ReplicatedStorage/DogEconomy/ItemDefinitions.luau` | 108 определений; `VisualAsset` — ключ визуала |
| `src/ServerScriptService/Economy/ItemDefinitions.luau` | прокси-require на RS |
| `src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau` | `V.Clone(x)`: клон из `DiscoveryModels`, мутация (все части → Neon), масштаб `(WeightKg/BaseWeightKg)^(1/3)` в пределах [0.25, ScaleCap]. `V.Preview(parent,x,px,py,w,h)`: ViewportFrame с камерой FOV 38 |
| `src/ReplicatedStorage/EconomyRewardVisuals.luau` | процедурные модели наград Cash/Bones/Boost; для `Kind=='Item'` — сырой клон `DiscoveryModels` (строка 4) |
| `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` | показ находки в мире (167-215), тост-баннер (154-166), анонс (216-218), всплывающие «+$X» (55-104), Highlight для вариантных собак (19-39) |
| `src/ServerScriptService/Economy/KennelLootPlacement.luau` | `Marker(slot)`: аттачмент `LootSpawn` на `DarkExcavation`; `Resolve(player,p,item)`: проверка владельца, собаки и слота, расчёт CFrame |
| `src/ServerScriptService/Economy/Runtime.luau` | `Project` (105-120): отправка Reveal и Announcement; `announce` (485-490) |
| `src/ServerScriptService/Economy/BestFinds.luau` | автоподбор и серверные клоны на стенде |
| `src/ReplicatedStorage/PlotAppearance.luau` | геометрия стенда (`showcase`, 140-175), пропуск `PlotShowcase` при перекраске (267) |
| `src/ServerScriptService/Economy/PlotDevelopment.luau` | вызывает `BestFinds.Reconcile`/`Clear` |
| `src/ServerScriptService/Economy/PlotShowcase.luau` + `DisplayRules.luau` | **стенды собак** `DogStorage.DisplaySlots.Slot1..3` (`p.DisplayDogs`) — образец для F3 |
| `src/StarterGui/ScreenGui/Modules/PreviewRenderer.luau` | `P.Item` → `DiscoveryVisuals.Preview`; `P.Scene`/`P.Dog` |
| `src/StarterGui/ScreenGui/Modules/Kit/Preview.luau` | кэш превью kit-карточек (`PerFrame=2`, `MaxFree=48`, `BuildSize=128`), builder `Item` (68-82), `Preview.Register` |
| `src/StarterGui/ScreenGui/Modules/Kit/Cards.luau`, `Kit/Theme.luau` | ItemCard (тег мутации, полоса редкости), `Theme.ItemRarity`, `Theme.Mutation` (все 16 ключей `ItemValueConfig.Mutation`) |
| `src/StarterGui/ScreenGui/Modules/DiscoveryScreens.luau` | Collection / Marketplace / Records / Inspect / Listing / CreateListing (immediate-mode, `V.Item` на каждую карточку) |
| `src/StarterGui/ScreenGui/Modules/CollectorScreen.luau` | продажа: список **всех** находок, `Preview.Item` у каждой |
| `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` | «последняя находка» (120); Trade (255-345) — находки только текстом |
| `src/StarterGui/ScreenGui/Modules/RewardScreens.luau` | превью призов DOG-O-MATIC (44-50) |
| `src/ServerScriptService/RewardMachinePresentation.server.luau` | серверная модель приза-находки на ригe (59-61) |
| `src/StarterGui/ScreenGui/MainWindow/.../InventoryController.client.luau` | основной инвентарь: свой viewport-кэш с виртуализацией по видимости (`preview`, 109-135); коллекция — сырой клон (117) |
| `src/StarterGui/ScreenGui/PawpadController.client.luau` | `showPreview` (150-185), сырой клон (159) |
| `src/StarterGui/ScreenGui/MainWindow/.../YardPageController.client.luau` | последняя находка, сырой клон через `geometry()` (64-87, 150) |
| `src/StarterGui/ScreenGui/ServiceMenusController.client.luau` | NPC-продавец: `discoveries.Clone` (52), виртуализация по видимости |
| `src/ReplicatedStorage/ItemValuation.luau`, `ItemValueConfig.luau` | цена и редкость (Version=6) |
| `src/ReplicatedStorage/Mining/MiningModels.luau`, `DogEconomy/EquipmentVisuals.luau` | **готовые образцы процедурных моделей**: части, роли цветов, стили редкости, свет и искры только в мире |
| `src/StarterPlayer/StarterPlayerScripts/MuseumPresentation.client.luau` | **готовый образец LOD**: только ближние (`NearDistance=43`, `MaxNearModels=18`), бюджет 8 сборок за тик 0.3 с, учёт качества графики и LowFX, стриминг через `DescendantAdded` |

### 4. Ассеты в place (замеры Lune-скриптами)
- `ReplicatedStorage` — 10 306 потомков. Из них `DiscoveryModels` — 3333 (108 моделей + 3225 частей, около 32% ReplicatedStorage), `MenuModels` (собаки) — 5293. Все MeshPart (468) и SurfaceAppearance (335) в RS относятся к собакам. ParticleEmitter в RS нет.
- Частей на модель: в среднем 29.9, максимум 105 (`shiny_marble`, `lost_planet`, `mini_black_hole`), минимум 1 (`the_cube`). По глубинам: D1 — 588 частей (в среднем 29.4), D2 — 504, D3 — 570, D4 — 430, D5 — 1133 (в среднем 45.3).
- Размер обычно 2–3.8 studs; `huge_statue` — 17.5×23.6×20 (13 крупных блоков).
- Стриминг: `StreamingEnabled=true`, `StreamingTargetRadius=1024`, `StreamingMinRadius=64`, у дворов `ModelStreamingMode=Default`.
- Скрипты замеров (вне репозитория): `scratchpad/tools/item-models/{items,models,shapes,table,where,yard,depthparts,stream,museum,classes}.luau`.

### 5. Все предметы: редкость и текущая визуализация
Колонки: глубина, класс, редкость (по `ItemValueConfig`), BaseValue, «частей / из них Neon», общая ли геометрия (в скобках — сколько id делят модель). Последняя колонка — предлагаемый рецепт F4.
| id | D | класс | редкость | BaseValue | сейчас | рецепт F4 (архетип + свои детали) |
|---|---|---|---|---|---|---|
| rusty_spoon | 1 | Treasure | Common | 2 | 45/0 своя | ложка: черпак-эллипсоид + ручка, CorrodedMetal |
| bottle_cap | 1 | Treasure | Common | 2 | 77/0 общая(4 монеты) | крышка: диск + 12–16 зубцов, вмятина |
| chewed_bone | 1 | Treasure | Common | 2 | 5/0 общая(3 кости) | кость: цилиндр + 4 мыщелка + насечки от зубов |
| lost_key | 1 | Treasure | Common | 6 | 19/0 общая(2) | ключ: кольцо из 8 сегментов + стержень + бородка, латунь |
| rubber_duck | 1 | Treasure | Common | 6 | 32/0 своя | уточка: шар-тело, шар-голова, клюв-wedge, глянец |
| toy_car | 1 | Treasure | Common | 6 | 7/0 своя | машинка: кузов, кабина, 4 колеса, фары |
| tennis_ball | 1 | Treasure | Common | 6 | 81/0 общая(5 сфер) | мяч Fabric + 2 дуги шва |
| worm_jar | 1 | Treasure | Uncommon | 6 | 26/0 общая(3 банки) | стеклянная банка + крышка + 2 червя внутри |
| dog_tag | 1 | Treasure | Uncommon | 15 | 12/0 своя | жетон-косточка + кольцо + 3 звена цепочки |
| bent_fork | 1 | Treasure | Uncommon | 15 | 6/0 своя | вилка с изогнутыми зубцами, Metal |
| shiny_marble | 1 | Treasure | Uncommon | 15 | 105/0 общая(3) | стеклянный шар + неоновая спираль внутри |
| garden_gnome | 1 | Artifact | Uncommon | 15 | 8/0 своя | гном: колпак ступенями, борода, тело |
| funny_sock | 1 | Treasure | Uncommon | 15 | 4/0 своя | носок Fabric в полоску |
| broken_clock | 1 | Artifact | Rare | 15 | 80/0 своя | корпус-цилиндр, циферблат, стрелки, трещина Glass |
| old_wallet | 1 | Treasure | Rare | 75 | 3/0 своя | Leather, створки, шов, край купюры |
| cracked_phone | 1 | Artifact | Rare | 75 | 9/0 своя | плита, экран Glass с трещинами, камера |
| buried_lunchbox | 1 | Artifact | Rare | 75 | 6/0 общая(2) | короб, ручка-арка, защёлки |
| tiny_treasure_chest | 1 | Artifact | Epic | 250 | 6/0 общая(2) | сундук: полуцилиндр-крышка, золотые оковки, монеты |
| golden_bone | 1 | Artifact | Epic | 250 | 5/0 общая(3 кости) | кость Foil-золото с гравировкой |
| mini_ufo_toy | 1 | Special | Legendary | 900 | 52/2 своя | диск, купол Glass, огни по ободу, антенна |
| quartz_crystal | 2 | Treasure | Common | 7 | 9/8 общая(10 кристаллов) | 3–4 гранёные призмы, белое стекло |
| large_coal | 2 | Treasure | Common | 7 | 18/0 своя | 5–6 повёрнутых глыб Slate с бликами |
| amethyst | 2 | Treasure | Common | 7 | 9/8 общая(10) | друза на породе, фиолетовые призмы |
| silver_ore | 2 | Treasure | Common | 15 | 24/0 общая(3 самородка) | порода Slate с серебряными жилами Metal |
| gold_nugget | 2 | Treasure | Common | 15 | 24/0 общая(3) | 4–5 оплавленных шаров Foil |
| geode | 2 | Treasure | Uncommon | 15 | 53/8 своя | разрезанная полусфера, кристаллы внутри |
| fossilized_fish | 2 | Artifact | Uncommon | 42 | 9/0 общая(2) | плита Limestone с рельефом скелета |
| ancient_shark_tooth | 2 | Artifact | Uncommon | 42 | 6/0 своя | зазубренный треугольник из wedge, Marble |
| bat_skeleton | 2 | Artifact | Uncommon | 42 | 9/0 общая(2) | крылья-перепонки и череп |
| crystal_skull | 2 | Artifact | Rare | 42 | 11/2 общая(3 черепа) | стеклянный череп со светом в глазницах |
| miner_s_lantern | 2 | Artifact | Rare | 210 | 19/1 своя | каркас Metal, стекло, неоновое пламя, ручка |
| broken_pickaxe | 2 | Artifact | Rare | 210 | 3/0 своя | древко с изломом, головка Metal |
| ancient_miner_helmet | 2 | Artifact | Rare | 210 | 26/0 общая(2 шлема) | каска, поля, налобная лампа |
| meteor_fragment | 2 | Treasure | Rare | 210 | 24/6 общая(3) | базальт CrackedLava со светящимися трещинами |
| red_crystal | 2 | Treasure | Rare | 210 | 9/8 общая(10) | крупная призма + 2 мелкие, красное стекло |
| living_crystal | 2 | Treasure | Epic | 700 | 9/8 общая(10) | кристалл с пульсирующим ядром и корнями |
| fossilized_egg | 2 | Artifact | Epic | 700 | 64/7 общая(3 яйца) | яйцо Slate с трещинами в каменном гнезде |
| miner_s_badge | 2 | Artifact | Epic | 700 | 79/0 своя | щит-звезда, скрещённые кирки |
| head_sized_diamond | 2 | Treasure | Epic | 700 | 9/8 общая(10) | бриллиантовая огранка из клиньев, Reflectance |
| underground_pearl | 2 | Special | Legendary | 2520 | 81/0 общая(5 сфер) | створки раковины + глянцевая жемчужина |
| heart_of_the_cavern | 2 | Special | Legendary | 2520 | 9/8 общая(10) | кристаллическое сердце + орбита осколков |
| ancient_coin | 3 | Artifact | Common | 20 | 77/0 общая(4 монеты) | монета с профилем-барельефом, потёртый край |
| golden_cup | 3 | Artifact | Common | 20 | 18/0 своя | чаша, ножка, основание, Foil |
| pharaoh_mask | 3 | Artifact | Common | 44 | 14/2 своя | лицо и полосатый немес |
| stone_tablet | 3 | Artifact | Common | 44 | 16/0 своя | плита со скруглённым верхом и рунами |
| eye_of_statue | 3 | Artifact | Common | 44 | 75/0 общая(3 глаза) | каменный глаз во фрагменте лица |
| ritual_dagger | 3 | Artifact | Uncommon | 44 | 5/0 общая(3 клинка) | волнистый клинок, рукоять с камнем |
| lost_crown | 3 | Artifact | Uncommon | 120 | 37/9 общая(4 короны) | обод, 5 зубцов, камни |
| ancient_book | 3 | Artifact | Uncommon | 120 | 8/1 общая(2 книги) | переплёт, страницы, застёжка |
| golden_scarab | 3 | Artifact | Uncommon | 120 | 29/0 своя | панцирь-эллипсоид, лапки, крылья |
| broken_sword | 3 | Artifact | Uncommon | 120 | 5/0 общая(3) | клинок с изломом, гарда |
| knight_helmet | 3 | Artifact | Uncommon | 120 | 26/0 общая(2) | шлем-ведро, щель забрала, плюмаж |
| royal_ring | 3 | Artifact | Rare | 600 | 21/1 общая(2 кольца) | тор из 12 сегментов, крупный камень |
| dog_statuette | 3 | Artifact | Rare | 600 | 12/0 общая(2) | сидящая собака, Marble |
| crystal_of_time | 3 | Artifact | Rare | 600 | 9/8 общая(10) | кристалл-песочные часы с кольцами |
| cursed_idol | 3 | Artifact | Rare | 600 | 14/2 своя | тотем с ликом, тёмный ореол |
| sealed_sarcophagus | 3 | Artifact | Epic | 2000 | 3/0 своя | корпус, крышка-фигура, иероглифы |
| eye_of_ancient_god | 3 | Artifact | Epic | 2000 | 75/0 общая(3) | светящийся глаз в золотой оправе, лучи |
| crown_of_forgotten_king | 3 | Artifact | Legendary | 2000 | 37/9 общая(4) | высокая корона, бархат, много камней |
| dragon_egg | 3 | Special | Legendary | 7200 | 64/7 общая(3) | кольца чешуи, огненные трещины |
| golden_dog_idol | 3 | Special | Legendary | 7200 | 12/0 общая(2) | идол Foil на постаменте, рубиновые глаза |
| huge_statue | 3 | World Find | Secret | 14400 | 13/0 своя | сохранить масштаб, детализировать фигуру и постамент |
| cursed_bone | 4 | Artifact | Common | 50 | 6/1 общая(2) | кость с фиолетовыми рунами |
| bloody_coin | 4 | Artifact | Common | 110 | 77/0 общая(4) | монета с потёками |
| broken_horn | 4 | Artifact | Common | 110 | 8/0 общая(2) | изогнутый сегментный рог с изломом |
| demon_tooth | 4 | Artifact | Common | 110 | 8/0 общая(2) | длинный клык с корнем |
| possessed_doll | 4 | Artifact | Uncommon | 110 | 13/1 своя | тряпичная кукла с глазами-пуговицами |
| black_candle | 4 | Artifact | Uncommon | 300 | 2/1 своя | свеча с наплывами воска и пламенем |
| cursed_ring | 4 | Artifact | Uncommon | 300 | 21/1 общая(2) | шипастое кольцо с тёмным камнем |
| demon_skull | 4 | Artifact | Uncommon | 300 | 13/2 своя | череп с рогами |
| frozen_heart | 4 | Artifact | Uncommon | 300 | 34/0 общая(2) | сердце в оболочке Ice |
| soul_fragment | 4 | Artifact | Rare | 1500 | 9/8 общая(10) | полупрозрачный осколок со спиралями |
| eye_in_a_jar | 4 | Artifact | Rare | 1500 | 26/0 общая(3) | банка, жидкость, глаз |
| burning_chain | 4 | Artifact | Rare | 1500 | 50/0 своя | 5–7 звеньев CrackedLava |
| cursed_sword | 4 | Artifact | Rare | 1500 | 5/0 общая(3) | зазубренный тёмный клинок с глазом на гарде |
| book_of_souls | 4 | Artifact | Rare | 1500 | 8/1 общая(2) | переплёт с черепом и цепями |
| demon_crown | 4 | Artifact | Epic | 5000 | 37/9 общая(4) | рога-зубцы, тёмное золото |
| shadow_crystal | 4 | Artifact | Epic | 5000 | 9/8 общая(10) | чёрные призмы с фиолетовым ядром |
| heart_of_the_beast | 4 | Artifact | Epic | 5000 | 34/0 общая(2) | анатомическое сердце с венами |
| black_halo | 4 | Special | Legendary | 18000 | 48/0 своя | тор, шипы, тёмная аура |
| unknown_skull | 4 | Special | Legendary | 18000 | 11/2 общая(3) | асимметричный череп с 3 глазницами |
| the_forbidden_bone | 4 | Special | Legendary | 18000 | 6/1 общая(2) | кость в цепях и печатях |
| normal_bone | 4 | Secret | Secret | 36000 | 5/0 общая(3) | **шутка**: та же кость, что chewed_bone, плюс Secret-аура |
| void_fragment | 5 | Artifact | Common | 264 | 9/8 общая(10) | зубчатый тёмный осколок в рамке |
| anti_matter_cube | 5 | Artifact | Common | 264 | 23/22 общая(2) | каркас рёбер с инвертированным ядром |
| glitched_coin | 5 | Artifact | Uncommon | 264 | 77/0 общая(4) | монета со смещёнными RGB-слоями |
| piece_of_reality | 5 | Artifact | Uncommon | 720 | 12/4 своя | плитка-осколок с «небом» |
| black_star | 5 | Artifact | Uncommon | 720 | 63/24 своя | 5-конечная звезда с короной лучей |
| mini_black_hole | 5 | Artifact | Uncommon | 720 | 105/0 общая(3) | чёрная сфера с аккреционным диском |
| frozen_time | 5 | Artifact | Uncommon | 720 | 8/6 своя | часы внутри кристалла |
| unknown_signal | 5 | Artifact | Rare | 720 | 15/1 своя | антенна-тарелка с волнами |
| alien_skull | 5 | Artifact | Rare | 3600 | 11/2 общая(3) | вытянутый купол с огромными глазницами |
| cosmic_egg | 5 | Artifact | Rare | 3600 | 64/7 общая(3) | яйцо со «звёздной» скорлупой |
| broken_portal | 5 | Artifact | Rare | 3600 | 40/0 своя | кольцо-арка с разломом и вихрем |
| dimension_key | 5 | Artifact | Rare | 3600 | 19/0 общая(2) | ключ с кристаллической бородкой |
| galaxy_in_a_bottle | 5 | Artifact | Epic | 3600 | 26/0 общая(3) | колба со спиральной туманностью |
| eye_of_the_void | 5 | Artifact | Epic | 12000 | 75/0 общая(3) | чёрный глаз с фиолетовой радужкой и щупальцами |
| corrupted_crown | 5 | Artifact | Epic | 12000 | 37/9 общая(4) | ломаная корона с осколками |
| cube_of_nothing | 5 | Artifact | Epic | 12000 | 23/22 общая(2) | идеальный чёрный куб с рамкой ForceField |
| fragment_of_the_moon | 5 | Special | Legendary | 43200 | 81/0 общая(5) | серый осколок с кратерами |
| dead_star | 5 | Special | Legendary | 43200 | 81/0 общая(5) | тёмное ядро и корона остывших лучей |
| piece_of_the_sun | 5 | Special | Legendary | 43200 | 81/0 общая(5) | неоновое ядро с протуберанцами |
| lost_planet | 5 | Special | Legendary | 86400 | 105/0 общая(3) | шар, кольца, луна-спутник |
| dog_from_another_timeline | 5 | Special | Legendary | 86400 | 24/12 своя | голограмма собаки |
| reality_error | 5 | Special | Legendary | 86400 | 51/11 общая(3) | окно «ERROR» с пиксельным распадом |
| null | 5 | Secret | Secret | 86400 | 51/11 общая(3) | пустая рамка с символами null |
| unknown_question | 5 | Secret | Secret | 86400 | 51/11 общая(3) | знак вопроса из сегментов, мерцание |
| the_cube | 5 | Secret | Secret | 86400 | 1/0 своя | **шутка**: один куб + Secret-аура |

Самые вопиющие совпадения геометрии: `tennis_ball` (Common, BaseValue 6) **полностью совпадает** с `dead_star`, `piece_of_the_sun`, `fragment_of_the_moon` (Legendary, 43 200) и с `underground_pearl`. 10 кристаллов (от `quartz_crystal`, Common, до `heart_of_the_cavern`, Legendary) отличаются только цветом. Монеты (4), короны (4), яйца, глаза, черепа, клинки (по 3) — тоже одна геометрия на группу.

### 6. Сохранённые данные (DataStore `DOGROTS_ECONOMY_V1`, ключ `p:<UserId>`, `Config.Version=4`)
- `p.Items[ItemUid]` — запись находки (поля из `ItemRules.Mint`): `ItemUid, ItemId, DisplayName, Depth, Class, SetId, BaseDropChance, EffectiveDropChance, BaseWeightKg, WeightKg, WeightMultiplier, WeightTier, TierIndex(1..10), WeightProfile, WeightTierChance, Mutation, MutationChance, CombinedOdds, FoundAt, FoundByUserId, OriginalFinderUserId, OwnerUserId, SellValue, Tradeable, RecordAtCreation{Personal,Server,Global}, Favorite, SourceDogUid, FirstFind, SellBonus, IncomeMult?, EventTag?, ValueBreakdown{Version,Rarity,Factors,Raw,Cap}, ValueVersion`.
- **Визуальных полей на предмете нет.** Визуал определяется `ItemId`/`VisualAsset`, `Mutation` и `WeightKg`/`TierIndex`, поэтому F4 **не требует миграции сохранений**.
- `p.Collection[ItemId]`, `p.MutationJournal[ItemId][Mutation]`, `p.HeavyCollection` (TierIndex≥4), `p.PersonalRecords[ItemId]`, `p.DiscoveryFeed` (≤20), `p.ItemSets["SET:Normal|Heavy"]`, `p.Cosmetics["Discovery:SET:..."]`, `p.RecordJobs`, `p.ItemReservations`, `p.DexFavorites`, `p.TrackedListings`.
- `p.Stats.BestShowcaseFind/BestShowcaseRelic/Heaviest/MostValuable/Rarest/Depths[d].Item` — краткие сводки, по ним работает `BestFinds`.
- `p.DisplayDogs {"1".."3"=DogUid}` — стенды собак (образец для F3).
- Атрибуты игрока: `ItemCount`, `ItemCapacity`, `LatestFoundItem`, `InventoryRevision`. Вместимость: `50 + 25*Upgrades.Storage + бонусы`, `HardCap=1000`.

### 7. Сеть
- `DiscoveryReveal` (RemoteEvent, сервер → владелец): `Rules.Copy(item)` + `LootSpawn{CFrame,DogUid,Slot,YardId,OwnerUserId}`; один раз на ItemUid за сессию сервера.
- `DiscoveryAnnouncement` (RemoteEvent, сервер → все): `(item, global)` для TierIndex≥8, Secret или глобального рекорда, не чаще раза в 15 с (Secret без ограничения). Уходит **вся** запись предмета, вместе с `ValueBreakdown`.
- `DogEconomyRequest` (RemoteFunction): `Snapshot` (полные `Profile.Items`), `ItemFavorite{Uid,Enabled}`, `BulkSell{Uids}`, `List{Kind='Item',...}`, `MarketQuery{Kind='Item'}`, `Trade{Action='Offer',Items}` (до 6, в `offer.Details` полные копии — `Engine.luau:301`), `ItemSetClaim`, `RecordClaim`. `SellItem` отклоняется (`Runtime.luau:420`), `ItemLock` отключён.
- `RewardRequest`/`RewardPresentation` — призы DOG-O-MATIC, среди них есть находки.
- 3D-модели по сети не передаются: клиент строит их сам из реплицированного `DiscoveryModels`. Исключение — серверные клоны на стендах `BestFinds` и на `RewardMachineRig.CommittedPrize`, они реплицируются всем.

### 8. Объекты мира
- `ReplicatedStorage.DiscoveryModels` (Folder, 108 Model).
- `Workspace.DOGROTS_District.04_PlayerYards.Yard_XX` (10 дворов): `DigSlot_1..5` (атрибуты `DigCenter`, `DigSize=12×0.4×12`, `Unlocked`) → `DarkExcavation` (Part 12×0.4×12, Ground) → `LootSpawn` (Attachment, уже есть в собранном place).
- `Yard_XX.PlotDevelopment.BestFinds` (Model, атрибут `Stage`) → `Slots.{Find,Dog,Relic}` (Part 5.9×0.2×5.9, атрибуты `ExhibitToken`, `CaptionName`) → `Exhibit`; вывески `Name<Key>`/`Category<Key>`/`ShowcaseTitle`. Пересобирается в `PlotAppearance.Apply` при смене стадии.
- `Yard_XX.DogStorage.DisplaySlots.Slot1..3` (+`SlotCaption`), `StorageAnchor` с подсказкой «DOG STORAGE» (`YardCommerce.luau:130`).
- От этих объектов зависит `SecretArrivals/Stare.luau:21-25`: он ищет `BestFinds.Slots.Dog.Exhibit` и `DisplaySlots.*.DisplayDog`.
- `37_AttractionRefresh.RewardMachineRig.CommittedPrize` — серверный приз.
- `06_DogDexMuseum` — **находок в музее нет**.

### 9. Клиент и сервер
Предметы целиком минтит сервер; клиент только показывает. На сервере модели находок клонируют `BestFinds.clone` и `RewardMachinePresentation` (через `DiscoveryVisuals.Clone`, это работает на сервере). Всё остальное — клиентские ViewportFrame и временный показ на участке. `DiscoveryVisuals` требуют обе стороны, поэтому будущая фабрика тоже должна работать на сервере (не трогать клиентские API при require).

### 10. Производительность сейчас
- Постоянно в памяти **у каждого клиента** лежат 3225 частей шаблонов (реплицируются при входе).
- `Menus` опрашивает Snapshot каждые 5 с (`Menus.luau:71-79`; `Update` каждые 0.5 с из `PawpadRuntime.client.luau:20`) и перерисовывает через `canvas:ClearAllChildren()` (`Menus.luau:182-185`). Поэтому `DiscoveryScreens` и `CollectorScreen` **каждые 5 с заново создают все ViewportFrame и клоны**, без виртуализации. Страница Collection для D5 — 1133 части. CreateListing и Collector — по ViewportFrame на **каждую** находку игрока (при 200 находках это примерно 6000 частей).
- Показ находки: до 4 моделей по ≤105 частей, все с `CastShadow`, плюс `Highlight`. Масштаб по весу до ×8 (у huge_statue до ~×3.7 при `MaxWeightMultiplier=50`).
- Хорошие места: `Kit.Preview` (кэш, полка на 48, 2 сборки за кадр, ключ ItemId|Mutation), а также `InventoryController` и `ServiceMenusController` (превью только для видимых карточек).

### 11. Баги и техдолг
1. `DiscoveryVisuals.Clone:9` — при любой мутации из таблицы цветов **все** части становятся Neon, а у RAINBOW каждый воксель получает случайный оттенок. Форма и светотень пропадают. В ViewportFrame у Neon нет bloom, и предмет выглядит плоским пятном. Это и есть те «размытые силуэты».
2. Свой вид есть только у GOLDEN/RAINBOW/CURSED/GLITCHED. Реально выпадающие сигнатурные BURNED, FROZEN, INFERNAL, RADIOACTIVE, SOLAR, SPORE, TOASTED выглядят как NORMAL, хотя цвета для них есть в `Kit.Theme.Mutation`. Фильтры мутаций в `DiscoveryScreens` (строки 44 и 90) знают только 5 значений, поэтому такие предметы нельзя отфильтровать.
3. Девять независимых путей превью, четыре из них обходят `DiscoveryVisuals`: `InventoryController:117`, `PawpadController:159`, `YardPageController:150` (последняя находка показывается без мутации), `EconomyRewardVisuals:4`. Камера и свет везде разные: у `DiscoveryVisuals.Preview` не задан `LightDirection`, у `PreviewRenderer` (-1,-1,-1), FOV 32/35/38.
4. Перестройка всех превью раз в 5 с (§10).
5. `Highlight` на каждый показ (`EconomyVisuals:184`) и на каждую вариантную собаку всех дворов (`EconomyVisuals:24`). Движок рисует одновременно только 31 Highlight — подсветка находок может молча пропадать. Режим AlwaysOnTop по умолчанию светит сквозь стены.
6. `CastShadow=true` у всех 3225 вокселей. Рекордная находка вырастает до 25–30 studs, huge_statue — до ~87 studs над ямой 12×12.
7. Анонс показывает `finder <число UserId>` (`EconomyVisuals:217`), а не имя.
8. `RewardMachineService.luau:90`: в `view.Rarity` пишется **класс** находки (`Treasure`), а не редкость.
9. `InventoryController.luau:57`: в `classColors` есть несуществующие классы Junk/Organic и нет класса 'World Find'.
10. В `EconomyVisuals` таблица `active` держит модели, уже уничтоженные через Debris, а модели показа кладутся прямо в `workspace`.
11. Ветка `DiscoveryScreens` для страницы 'Discoveries' не маршрутизируется из `Menus` (`Menus.luau:197`), похоже на мёртвый код — нужно проверить.
12. Смежное: `YardPageController.geometry` не реже раза в 20 с клонирует весь двор (1555 потомков) во viewport.
13. Ни один путь визуализации находок не покрыт тестами (`tests/` и `tools/verify.luau` их не упоминают).

### 12. Что можно улучшить поверх текущей системы
- Подменить внутренности `DiscoveryVisuals.Clone/Preview` вызовом фабрики, **не меняя сигнатур**. Сразу выиграют все 9 путей, включая серверные `BestFinds` и `RewardMachinePresentation`.
- Вместо «всё в Neon» перекрашивать по ролям; завести вид для всех 16 ключей мутаций и синхронизировать с `Theme.Mutation` (тест `tests/uikit.luau` уже проверяет набор ключей).
- Выключить `CastShadow` у мелких частей; ограничить масштаб показа (например, ≤×3 в мире и отдельный «пьедестал рекорда»); убрать Highlight (вместо него — неоновая кайма, ForceField-оболочка или луч).
- Экспортировать `ItemValuation.Rarity(def)` (чистая функция) и брать её в UI и в `RewardMachineService`.
- Перевести 4 сырых клона на `DiscoveryVisuals`.
- Показывать имя нашедшего вместо числового UserId.

### 13. Что требует аккуратного рефакторинга
- Экраны находок в `Menus` (`DiscoveryScreens`, `CollectorScreen`) перевести на `Kit.CardGrid` + `Kit.Preview`, без перестройки по опросу. Это затрагивает подтверждения продажи и выставления на рынок.
- Отрисовку экспонатов стенда (F3) перенести с сервера на клиент. Это меняет контракт `SecretArrivals/Stare` и `EstateQATests:56-59`, которые ищут `Exhibit` на сервере.
- Убрать `ReplicatedStorage.DiscoveryModels` можно только после перевода всех потребителей. build не умеет удалять инстансы, поэтому варианты такие: серверный `Destroy()` до входа игроков либо удаление владельцем в Studio.
- Пул и LOD для показа находок с учётом F5 (уровни шахты и стриминг).

### 14. План F4: модульная процедурная фабрика `ItemModelFactory`
**Принцип.** Как в `EquipmentVisuals` (Look = список частей `{форма, размер, позиция, поворот, роль, материал, прозрачность}`) и `MiningModels` (seed-RNG, пресеты частиц), но с иерархией **примитивы → архетипы → рецепт предмета**, тегами LOD и бюджетами.

**Модули (новые)**
- `ReplicatedStorage/ItemModels/ItemModelFactory.luau` — API, кэш шаблонов, LOD, применение мутаций и FX.
- `ItemModels/Primitives.luau` — Box, Ball (SpecialMesh Sphere, для эллипсоидов), Cyl, Wedge, CornerWedge, а также составные Ring/Arc (N сегментов), Gem (огранка из клиньев), Spike, Coin, Chain; зеркалирование по X; роли цвета `body/trim/detail/accent/glow/eye/dark`.
- `ItemModels/Archetypes.luau` — Coin, Crystal, Skull, Crown, Egg, Orb, Jar, Blade, Bone, Key, Helmet, Book, Ring, Star, Cube, Statue, Chest, Mask, Tablet, Idol, Portal, Heart, Candle, Device.
- `ItemModels/Recipes/Depth1..Depth5.luau` — по рецепту на `VisualAsset`: архетип + параметры + собственные детали + палитра.
- `ItemModels/MutationLooks.luau` — 16 ключей.
- `ItemModels/RarityFx.luau`.
- `ItemModels/ItemVisualConfig.luau` — бюджеты, дистанции LOD, лимиты.
- `StarterPlayerScripts/ItemExhibits.client.luau` — менеджер мировых экспонатов: показ находок, стенды F3, пул и LOD.
- `ServerStorage/ItemVisualQA.luau` — сетка всех предметов в Studio по LOD и мутациям для скриншотов.
- `tests/item_models.luau`.

**API**
```lua
Factory.Build(spec, opts) -> Model, Bounds{Center, Radius, Size}
  -- spec = {ItemId, Mutation?, WeightKg?, EventTag?}
  -- opts = {Lod = "Hero"|"Card"|"Far", Context = "Viewport"|"World", Fx = bool, Seed?}
Factory.Viewport(parent, spec, opts) -> ViewportFrame   -- камера по Bounds, как EquipmentVisuals.Viewport
Factory.Rarity(itemId) -> "Common".."Secret"            -- через ItemValuation.Rarity
Factory.Purge(); Factory.Stats()
```
Пример рецепта:
```lua
tennis_ball = { Archetype = "Orb", Palette = { body = {198,232,60}, trim = {245,245,235} },
  Params = { Radius = 1.1, Material = "Fabric" },
  Details = { { "Arc", { Radius = 1.12, Thickness = .08, Segments = 10, Tilt = 25 }, Role = "trim", Lod = 1 },
              { "Arc", { Radius = 1.12, Thickness = .08, Segments = 10, Tilt = -25, Yaw = 180 }, Role = "trim", Lod = 1 } } }
```

**LOD**
- L0 «Hero» — все части. Где: viewport ≥160 px, Inspect, редактор витрины, показ находки, ближняя витрина <35 studs.
- L1 «Card» — только части с тегом `Lod<=1`: силуэт и ключевые детали. Где: миниатюры 128 px, витрина на 35–120 studs.
- L2 «Far» — 1–3 части средней окраски плюс луч редкости (Epic и выше). Где: 120–250 studs; дальше рисуется только табличка.
- Переключение с гистерезисом ±10%, пересчёт 3–4 раза в секунду, бюджет 2 сборки за тик (по образцу `MuseumPresentation`).
- При `LowFX`, `WorldEventFX=='Low'` или `SavedQualityLevel<=3`: в мире максимум L1, без частиц и света.
- Кэш: шаблон на `(VisualAsset, Lod)` строится один раз и хранится без родителя (LRU до 64 шаблонов). Использование — `Clone()`. Мутация накладывается на клон (цикл по ≤70 частям). Ключ `Kit.Preview` расширить: `Item|id|mutation|lod`.
- Вариации детерминированы: seed — хэш `ItemId`, поворот кристаллов можно брать от хэша `ItemUid`.

**Бюджеты частей и FX** (huge_statue — исключение, L0 ≤90)
| Редкость | L0 | L1 | L2 | FX в мире | FX в UI (viewport) |
|---|---|---|---|---|---|
| Common | ≤24 | ≤10 | 1 | нет | — |
| Uncommon | ≤30 | ≤12 | 1 | акцентная кайма | обводка |
| Rare | ≤40 | ≤14 | 1–2 | 1 эмиттер Sparkle, Rate ≤3 | шиммер |
| Epic | ≤50 | ≤16 | 2 | Sparkle ≤5/с + PointLight R6 без теней | градиент + шиммер |
| Legendary | ≤60 | ≤18 | 2 + луч | 2 эмиттера ≤10/с, свет R8, орбита из 2–3 осколков | анимированный градиент |
| Secret | ≤70 | ≤20 | 3 + луч | ForceField-аура + 2 эмиттера + свет | радужная рамка |
- Глобальные лимиты на клиент: свет от предметов ≤4, эмиттеров ≤8, мировых L0 ≤8, L1 ≤32, показов ≤4 (как сейчас), живых viewport — видимые карточки + 48 на полке.
- Прозрачных частей (Glass/ForceField) ≤3 на предмет. `CastShadow` только у 1–3 крупных частей. Никаких Highlight.
- ViewportFrame **не рисует** частицы, свет и bloom. В UI редкость и мутация передаются материалами, Neon-акцентами и средствами UI: `Kit.RarityGradient`, шиммер-ImageLabel.
- Стоимость (оценка, проверить microprofiler'ом): L0 примерно в 60 частей — около 0.3–0.8 мс на ПК и 1–3 мс на слабом телефоне, поэтому сборки разносятся по кадрам. Цель по памяти: вместо 3225 постоянных частей — 0, кэш создаётся по требованию (обычно <600 частей).
- Сравнение: страница Collection D5 сейчас — 1133 части и перестройка раз в 5 с; цель — ≤25×12 частей L1, построенных один раз.

**Мутации — по ролям, не «всё в Neon»**
- GOLDEN: основа Foil/Metal золото, акценты Neon.
- RAINBOW: оттенок по HSV вдоль акцентов (в UI ещё UIGradient).
- CURSED: тёмно-красный + CrackedLava и дым (в мире).
- GLITCHED: чередование magenta/cyan плюс «сдвинутый» дубль-осколок.
- FROZEN: Ice-оболочка. INFERNAL: лава и угли. SOLAR: ореол. RADIOACTIVE: зелёный Neon. SPORE: мох. BURNED/TOASTED: обугливание. SPOILED: тусклый. VOID/CORRUPTED/SHINY — по `Theme.Mutation`.
- В мире максимум 2 эмиттера на модель, считая вместе с редкостью.

**Где используется фабрика**
- Показ находки (вместо `EconomyVisuals:167-215`, с пулом RevealRig из 4 слотов).
- Витрина F3 (клиентский рендер по атрибутам слотов).
- Карточки инвентаря, торговли и рынка (`Kit.Preview`, L1).
- Inspect и редактор витрины (L0, вращение на подиуме).
- Приз DOG-O-MATIC (L0 на сервере).
- Коллекция (силуэт L1: `ImageColor3` = чёрный, как сейчас в Kit).

**Этапы**
1. (S) `ItemValuation.Rarity`, конфиг, скелет тестов.
2. (M) Primitives + Factory с откатом на `DiscoveryModels` для id без рецепта (нормализация, новые мутации, без теней); `DiscoveryVisuals` → Factory; перевести 4 сырых клона.
3. (L) Рецепты всех 108 предметов; тесты бюджетов, уникальности силуэтов (кроме шуточных `normal_bone`, `the_cube`) и наличия рецепта для каждого id; QA-сетка в Studio.
4. (M) `ItemExhibits.client`: LOD-менеджер и пул показов.
5. (S) Убрать `DiscoveryModels` из рантайма плюс grep-тест «никто не ссылается на DiscoveryModels».

**Совместимость.** Профиль не меняется. Неизвестный `ItemId` получает рецепт `MysteryRelic`. Старые модели служат запасным вариантом, пока не готовы все рецепты.

---

## Участки игроков, витрина, косметика (plots)

### 1. Коротко: что есть сегодня
* **8 фиксированных участков** `Workspace.DOGROTS_District.04_PlayerYards.Yard_0N_<Name>`. Участок выдаётся на одну сессию. Сохранённого «своего участка» нет: сохраняется только прогресс в профиле.
* **Прогресс участка** складывается из двух частей:
  * стадия: `p.Upgrades.Plot` 0..8, то есть стадии 1..9 (`PlotCatalog.Stages`), она открывает будки 1..5;
  * **один скин на весь участок** из 14 (`p.EquippedPlotSkin`, владение в `p.PlotSkins`).
* **Весь «развивающийся» декор** (заборы, ворота, фонари, сад, крыши, монумент, стенд MY BEST FINDS) **генерирует процедурно СЕРВЕР** через `ReplicatedStorage.PlotAppearance.Apply`. Результат кладётся в модель `yard.PlotDevelopment` и реплицируется всем. При каждой смене стадии, скина или владельца модель **полностью уничтожается и строится заново**.
* **Витрин сейчас две, и ни одна не соответствует F3:**
  1. **«MY BEST FINDS»**: 3 пьедестала `Find / Dog / Relic` в `PlotDevelopment.BestFinds`. Их содержимое **выбирается автоматически** (`BestFinds.Select`) по максимальной SellValue и рангу собаки. Игрок ничего не выбирает. Нет промптов, меню, превью и FX редкости.
  2. **3 «дисплея собак»** в шкафу DOG STORAGE (`DogStorage.DisplaySlots.Slot1..3`). Их выбирает игрок, сохраняются в `p.DisplayDogs`. Правка идёт через терминал DOG STORAGE («MANAGE DOGS» → страница Storage). Промпта на самих стендах нет.
* **Декора как отдельных предметов нет.** Есть только скины целиком. Размещения нет, данных декора в профиле нет. В плейсе лежит **неиспользуемая** папка `YardCustomization` с «сокетами» (KennelSocket, BowlSocket, ShowcaseSocket, CenterpieceSocket, FenceSockets, GroundThemeArea, UpgradeSockets…). Ни один скрипт на неё не ссылается (grep пуст). Часть сокетов уже стоит внутри площадки MiningCorner (KennelSocket (−113,−99) ≈ центр шахты (−111.5,−99)), то есть они устарели.

### 2. Файлы и их роли
| Файл | Роль |
|---|---|
| `ServerScriptService/YardService.server.luau` | Раздаёт участки (Allocator, порядок `{4,8,3,7,2,6,1,5}`). Пишет атрибуты `OwnerUserId/OwnerDisplayName` на участок и `YardId/YardSpawnPosition/WaitingForYard` на игрока. Есть очередь ожидания. `updateSign` ищет `OwnerPlaque`, которого в плейсе нет (no-op) |
| `ServerScriptService/MapAmbience.server.luau` | **ДУБЛЬ той же раздачи** (своя копия Allocator, L3-4, L122-186) плюс табличка владельца `OwnerBillboardAnchor/OwnerBillboard` (аватар и ник, AlwaysOnTop, MaxDistance 400). Оба скрипта включены (Disabled=false, проверено в `build/DOGROTS_MINING.rbxl`) |
| `ServerScriptService/YardAllocator.luau` | Чистая логика Claim/Release |
| `Economy/PlotDevelopment.luau` | `Reconcile(player,p)`: `PlotAppearance.Apply(yard, level, skin)` + `BestFinds.Reconcile`, атрибуты игрока `UnlockedKennels/EquippedPlotSkin/YardStageName`. `VisitShop`: покупка и claim скина только у терминала COSMETICS. `Start`: подписка на `OwnerUserId` каждого участка |
| `Economy/PlotRules.luau` | `Normalize` (миграция v1: `PlotProgressionVersion`, старые GoldenKennel/CyberKennel/VoidAura → скины), `Action` (`BuyPlotSkin/ClaimPlotSkin/EquipPlotSkin`), `Assign` (будка открыта по стадии), `Validate` |
| `ReplicatedStorage/PlotCatalog.luau` | 9 стадий (Name/Slots/Feature) и 14 скинов (цвета, Motif, Rarity, Cash, Event, Goal). **L33 умножает Cash ×5 при загрузке модуля.** Функции `Level/Slots/Cost/Earned/Requirement` |
| `ReplicatedStorage/PlotAppearance.luau` (340 строк) | `Frame(yard)`, `Apply` (перекраска базы + генерация `PlotDevelopment`: roof/lamp/tree/fence/gate/showcase/garden), `Preview` (клон всего участка для ViewportFrame). Смешивает геймплей (видимость, коллизии и промпты будок) и косметику |
| `ReplicatedStorage/PlotGeometry.luau` | Примитивы `Part/Beam/Ring/Sign/Bone/Paw/Crystal/Cluster/Rock/Gear/Clock/Crest`. **Все части Anchored, CanCollide=false, CanQuery=false (L3-10)** |
| `ReplicatedStorage/PlotInteractionAccess.luau` | `CanUse`: владелец + внутри `*InteractionZone` + ≤9 стадов. Зоны только Storage/Sell/Upgrade |
| `Economy/BestFinds.luau` | Автоотбор `Select` (L12-28), клон экспоната (`DiscoveryVisuals.Clone` / `ServerStorage.DogTemplates`, L36-54), `Reconcile/Clear` по `ExhibitToken` |
| `Economy/PlotShowcase.luau` | Модели `DisplayDog` для `p.DisplayDogs` в `DogStorage.DisplaySlots.SlotN` (L13-58) |
| `Economy/DisplayRules.luau` | `Normalize/Assign` для `p.DisplayDogs` (3 слота, только свои собаки, не `Walking`) |
| `Economy/RecordStats.luau` | `Stats.BestShowcaseFind/BestShowcaseRelic/Heaviest/MostValuable/Rarest` (источник BestFinds) |
| `Economy/YardCommerce.luau` | `Yard(player)`, `Visit/StorageVisit`, `CanSell`, BulkSell/SellQuote/NPCSell. `Start`: 3 промпта `YardInteraction` на участке (SELL FINDS / OPEN UPGRADES / MANAGE DOGS) и вызов `PlotShowcase.Start` |
| `Economy/ShelterRules.luau` | Собак на дисплее нельзя сдать в приют (L10) |
| `ServerScriptService/DogKennelService.luau` | **Эталон «подошёл — нажал»**: промпт «MANAGE / DIG KENNEL n» на каждой будке, `Reconcile` моделей собак в `KennelDogs` |
| `Economy/KennelLootPlacement.luau` | Точка появления находки на верхе ямы `DarkExcavation.LootSpawn` |
| `Economy/EstateQATests.luau`, `Economy/PlotDevelopmentTests.luau` | Тесты только для Studio. **Устарели и нигде не вызываются** (см. §9) |
| `StarterPlayerScripts/PlotPrompts.client.luau` | Каждые 0.15 с включает и выключает промпты `YardInteraction` по `CanUse` (только у владельца) |
| `StarterPlayerScripts/PlotSkinMotion.client.luau` | Парение частей `PlotFloat` (30 Гц, ≤230 стадов) и включение тумана `PlotMist` (≤180) |
| `StarterGui/.../Modules/PlotShopScreen.luau` | Экран COSMETICS: список скинов, живое 3D-превью (клон участка), покупка, claim и equip, блок стадии, **список титулов** |
| `StarterGui/.../YardPage/YardPageController.client.luau` | Страница «Мой двор»: статистика, 3D-превью участка (клон всех видимых частей) |
| `StarterGui/ScreenGui/ServiceMenusController.client.luau` + `ServiceMenus/ServiceUI.luau` | Окно «ASSIGN DOG» для будки (режим `Kennels`) |
| `Modules/StorageScreen.luau`, `Modules/DogsScreen.luau` (`displayDog`, `atStorage`) | Выбор дисплеев собак |
| Соседи на участке | `MiningWorld.server` (MiningCorner, `coverGround` следит за PlotDevelopment), `Economy/LuckyLifecycle` (LuckyPad_1..3, промпт CHOOSE BLOCK), `SecretArrivals/Stare` (поворачивает статичных собак на `BestFinds.Slots.Dog.Exhibit` и `DisplaySlots`), `UpgradeTreeScreen` (превью следующей стадии через `PlotAppearance.Preview`), `MapRouting` (цель `PlayerYards` = свой `YardSpawn`) |
| `Modules/Kit/Display.luau` | **Не относится к участкам**: это UI-виджеты кита (Pill/Badge/…) |

### 3. Как это работает от начала до конца

**3.1 Выдача участка.** `PlayerAdded` → `Allocator:Claim` → атрибуты `OwnerUserId/OwnerDisplayName` на участке, `YardId/YardSpawnPosition` на игроке. `RespawnLocation` всегда `DistrictSpawn`, на участке игрок не появляется. Если игроков больше 8, они ждут в очереди `waiting`. Так ведут себя ОБА скрипта, YardService и MapAmbience. Они согласованы только потому, что детерминированы (одинаковый порядок и одинаковые события).
На смену `OwnerUserId` подписаны независимо:
* `PlotDevelopment.Start`: refresh → Apply и BestFinds;
* `PlotShowcase.Start`: Clear и Reconcile;
* `DogKennelService.Start`: `Runtime.Refresh`;
* `MiningWorld`, `LuckyLifecycle`.

Каждый вход и выход игрока даёт 2 полных перестроения PlotDevelopment: сначала `Apply(1,'Classic')`, затем облик нового владельца.

**3.2 Стадии.** Стадию покупают в UPGRADE TREE, узел `Plot`: `Features/UpgradeTree.luau`, цена `Config.Upgrades.Plot {Base=8000, Factor=2.35, Max=8, LevelBase=3, LevelStep=4}`, то есть 8 000 → 3.17M Cash, требуемый уровень 3 → 31. Каждая стадия даёт +2.5% к ценности добычи (`Config.UpgradeEffects.Plot=.025`). `PlotRules.Assign` не даёт поставить собаку в закрытую будку.

**3.3 Скины.** `PlotCatalog.Skins` × `Order`:
* Classic (бесплатный);
* 11 за Cash (после ×5): BoneRain 6 000, GoldenHour 12 000, DogRush 18 000, TreasureFever 25 000, CrystalStorm 70 000, Earthquake 90 000, TimeWarp 120 000, CursedFog 275 000, Blackout 325 000, UFOInvasion 400 000, RainbowRift 500 000;
* 2 Secret, только через claim: NullHour (стадия 8), TheVoid (стадия 9 + Prestige 1 + слой 5).

Claim события засчитывается при `p.WorldEventsSeen[Event]` и `Lifetime.GlobalDigContribution ≥ Goal`. Вклад копится обычной добычей собак (`Rules.Dig`, L414), даже когда Global Dig выключен.

Где что делается:
* Купить и получить по claim можно только внутри COSMETICS: `Runtime.Request` L423 и `Engine:Action` L64 → `PlotDevelopment.VisitShop` → `ShopInteriorAccess.Eligible`.
* Надеть (equip) можно где угодно.
* UI: `PlotShopScreen` (страница `Cosmetics` через `EconomyScreens`).

**3.4 Генерация облика (`PlotAppearance.Apply`, L255-332).**
* Токен `level:skin` кэшируется в weak-таблице по участку. При изменении старая `PlotDevelopment` уничтожается и создаётся новая.
* Проход по всем BasePart в `YardLandscape/DogStorage/Vendor/Workshop/StorageRoofMascot` (≈1 350 частей): перекраска по имени части (`Roof/Trim/Wall/...`), скрытие старых `Post/Rail/EntryPillar/LanternPost`. Исходные значения хранятся в атрибутах `PlotBase*`.
* Будки 1..5: `Unlocked`, `RequiredYardLevel`, видимость и коллизии частей, `ProximityPrompt.Enabled`.
* Генерируются `roof/lamp/fence/gate/garden/showcase`. Стенд `BestFinds` стоит в локальной точке кадра `(20·sx, 0, 55)`, на месте «шестой будки» справа от входа (`sx=-1` у восточных участков 5–8). Сад сдвинут на `MINING_CLEARANCE=9`, чтобы освободить место под MiningCorner.

**3.5 Витрина BEST FINDS.** `RecordStats.Find` при каждой находке обновляет сводки `BestShowcaseFind` (класс Treasure) и `BestShowcaseRelic` (Artifact, Special, Secret) по SellValue. `BestFinds.Select` на каждом `Runtime.Project` перебирает Stats, **все `p.Items` (до 1000)**, `DiscoveryFeed` и собак. Затем `Reconcile` пересоздаёт экспонат только при смене токена `uid:variant:weight`. Экспонаты — серверные клоны (`Exhibit`, `PlotShowcase=true`), максимум 4.5×4.9×4.5 стада. Проданные предметы остаются на витрине как «трофеи», потому что источник — сводки Stats. Из 108 предметов 84 относятся к Artifact/Special/Secret, поэтому на пьедестале «Find» обычно стоит мелкий Treasure.

**3.6 Дисплеи собак.**
* Путь игрока: подойти к DOG STORAGE → промпт `YardInteraction` «MANAGE DOGS» → `DogEconomyOpen('Storage')` → `StorageScreen` (выбрать слот, затем собаку).
* Путь из MY DOGS: `DogsScreen.displayDog` проверяет `atStorage()`; если игрок не у склада, предлагает «SHOW THE WAY».
* Запрос: `DogEconomyRequest('DisplayDog',{Slot,Uid})` → `Runtime.Request` L424 `StorageVisit` → `DisplayRules.Assign`.
* `PlotShowcase.Reconcile` клонирует собаку из `DogTemplates` с подкраской по Variant. Анимаций нет.

**3.7 Модель «подошёл — нажал» у будок (эталон для F3).** `DogKennelService.Start` L248-262:
1. На `KennelFloor` создаётся `Attachment "KennelInteraction"` (3.8 стада вперёд, 1.5 вверх) с `ProximityPrompt` «MANAGE / DIG KENNEL n» (`MaxActivationDistance=10`, `RequiresLineOfSight=false`, `Enabled` берётся из Unlocked).
2. `Triggered` на сервере проверяет: владелец, расстояние ≤14 до attachment, `Runtime.Allow(player,1)`. Затем `DogKennelOpen:FireClient(player, slot.Name)`.
3. `GUIIntegration` L176-179 → `N.OpenService('Kennels',{Slot,YardId})` → `ServiceMenusController.open` (L283-295): Snapshot, сетка доступных собак с ViewportFrame-превью, панель свойств, одна кнопка ASSIGN/REMOVE.
4. `mutate()` (L82-106) отправляет `DogEconomyRequest('Assign'|'Remove',{Uid,Slot}, requestId)`. При обрыве связи requestId сохраняется, повтор безопасен (идемпотентные квитанции `Transactions`).
5. `Rules.Assign` → `Runtime.Refresh` → `DogKennelService.Reconcile` строит модель в `KennelDogs`.

Замечания:
* Ограничение по расстоянию есть только на входе в окно. Само действие `Assign` сервер принимает откуда угодно (так же назначают из MY DOGS и PAWPAD).
* Промпты будок **видны и чужим игрокам**: клиентской фильтрации нет, сервер молча игнорирует нажатие.
* Похожая схема у лаки-падов (`LuckyLifecycle` L308-330 → `RewardPresentation{PadSelector}`).

**3.8 Сервисы участка.** `YardCommerce.Start`: промпты `YardInteraction` (HoldDuration 0.15, RequiresLineOfSight=true, 9 стадов) на `SellAnchor/UpgradeAnchor/StorageAnchor`. `PlotPrompts.client` включает их только владельцу внутри зоны `*InteractionZone` (атрибут `PlotInteractionRegion`). Сервер повторно проверяет `Access.CanUse` в `TryOpen` → `DogEconomyOpen(page)`.

**3.9 Клиентские превью.**
* `PlotShopScreen` (L28-39): `A.Preview` клонирует ВЕСЬ участок (≈1 556 инстансов плюс текущий PlotDevelopment до 2 260) и заново выполняет Apply в ViewportFrame. Это происходит **при каждой отрисовке**, а `Menus` перерисовывает страницу каждые 5 с (`Menus.Fetch` L71-72, `Update` L215). Вызов без pcall.
* `UpgradeTreeScreen` (L960-990): то же, но внутри pcall и с токеном.
* `YardPageController.geometry` (L64-87): копирует все видимые BasePart участка не чаще раза в 20 с, пока открыт «Мой двор».

### 4. Сохранённые данные (DataStore `DOGROTS_ECONOMY_V1`, ключ `p:<UserId>` через `StoreKeys.Wrap`; JSON до 3.5 МБ; `Config.Version=4`, `MegaResetVersion=1`)
| Поле | Смысл |
|---|---|
| `Upgrades.Plot` (0..8) | стадия участка − 1 (`PlotCatalog.Level`) |
| `Upgrades.Kennel` | «KENNEL QUALITY», ценность добычи |
| `PlotSkins {[id]=true}` | купленные или полученные скины, Classic всегда true |
| `EquippedPlotSkin` | надетый скин (если невалиден, Normalize ставит Classic) |
| `PlotProgressionVersion` | флаг миграции (1) |
| `DisplayDogs {['1'..'3']=DogUid}` | дисплеи собак |
| `Stats.BestShowcaseFind / BestShowcaseRelic / Heaviest / MostValuable / Rarest` | сводки находок для BEST FINDS |
| `Cosmetics {}` + `EquippedCosmetic` | старые косметики будок (GoldenKennel/CyberKennel/VoidAura/FounderPlaque) **и титулы** (Finds25, Dex10, Set…, Prestige1). Строка `EquippedCosmetic` общая для обоих |
| `Dogs[uid].AssignedSlot/State/OwnerUserId/Variant/Mastery` | будки, дисплеи |
| `Items`, `DiscoveryFeed` | источник экспонатов |
| `WorldEventsSeen`, `Lifetime.GlobalDigContribution`, `Prestige`, `UnlockedLayers['5']` | условия claim скинов |

Новые поля в профиле можно добавлять двумя способами:
* через `Rules.Profile`: `Rules.Normalize` заполняет отсутствующие ключи значениями по умолчанию;
* через `FeatureRegistry` (`Normalize/Validate/Action/Snapshot`) — рекомендуемый путь.

Мега-сброс переносит только `Cosmetics` и платное (`Rules.Normalize` L56). `PlotSkins/DisplayDogs/Upgrades` по задумке не переносятся.

### 5. Сеть (remotes)
* `DogEconomyRequest` (RemoteFunction, клиент → сервер, `InvokeServer(action,args,requestId32hex)`; `clean()`: строки ≤120, таблицы ≤30, глубина ≤3; token bucket 8 / 1.5 в секунду). Действия участка:
  * `BuyPlotSkin/ClaimPlotSkin {Id}` (только в COSMETICS), `EquipPlotSkin {Id}`;
  * `DisplayDog {Slot,Uid}` (только у DOG STORAGE);
  * `Assign {Uid,Slot}`, `Remove {Uid}`;
  * `Upgrade/TreeUpgrade {Kind='Plot'}`;
  * `SellQuote/NPCSell/BulkSell/SellLoot` (только у сборщика);
  * `Cosmetic {Kind}` (титулы), `RecordClaim {Count}`;
  * `Snapshot`: полная копия профиля.
* `DogEconomyOpen` (RemoteEvent, сервер → клиент, page): `Collector/UpgradeTree/Storage` с участка, `Cosmetics` из магазина.
* `DogKennelOpen` (сервер → клиент, slotName) с промпта будки.
* `DogKennelRequest` (RemoteFunction): серверный `Handle` привязан, **но ни один клиент его не вызывает** (ServiceMenusController объявляет `kennelRemote` L15 и не использует). Мёртвая поверхность.
* `RewardPresentation` (Sell cue, PadSelector), `DiscoveryReveal` (с `LootSpawn` ямы).
* ProximityPrompts на участок:
  * 3× `YardInteraction`;
  * 5× будка «MANAGE»;
  * 3× `PlaceLuckyBlock`;
  * промпты MiningCorner.
* Новые RemoteEvent в сборку добавить нельзя: `build.py` патчит только скрипты и папки. Их нужно создавать в рантайме, как `Runtime.Start` создаёт `DogEconomyPush`.

### 6. Мировые объекты
* `04_PlayerYards` = 12 454 инстанса из 37 587 в Workspace. В его составе 8 участков по 1 556 (941 Part + 488 WedgePart), `EntranceAnchor`, `WorldEventSpawnPoints`.
* Атрибуты участка: `YardId, OwnerUserId, OwnerDisplayName, PlotStage, PlotSkin, UnlockedKennels, AppearanceRevision, DigSlotSize, YardFootprint`.
* Внутри участка:
  * `YardLandscape`: YardFoundation 134×1×70, EntryWalk 124×9, UtilityApron, WorkArea, CosmeticGarden 39×22, LuckyCourt 37×21, PadTrim, скрытые Post×49/Rail×10;
  * `DogStorage` (DisplaySlots/Slot1..3 + SlotCaption, стёкла, Terminal), `Vendor` (521 часть), `Workshop` (618), `StorageRoofMascot`;
  * `DigSlot_1..5` (DarkExcavation 12×0.4×12 + LootSpawn, KennelFloor/Back/Wall/Lintel/Roof, атрибуты `ApproachPosition, DigCenter, DigSize, RequiredYardLevel, SlotIndex, Unlocked, AssignedDogUid…`);
  * `LuckyPad_1..3`, `Sell/Upgrade/StorageAnchor` + `*InteractionZone`, `YardSpawn`, `YardCustomization` (мёртвая);
  * `PlotDevelopment` (в базовом плейсе запечена копия L1 Classic, при старте пересобирается);
  * создаются в рантайме: `MiningCorner`, `OwnerBillboardAnchor`.
* Вне участков: `KennelDogs`, `11_Shops.COSMETICS` (InteractionAnchor (142.8,4.3,335), ShopInteriorZone), `NavigationAnchors.PlayerYards` (0,2,110), `DistrictSpawn`; ассеты `ServerStorage.DogTemplates` (101), `ReplicatedStorage.DiscoveryModels` (108, в среднем 29 частей, максимум 105), `MenuModels` (101, в среднем 5 частей).
* Расположение: центры фундаментов x=±105, z∈{−117,−39,39,117}. Запад — участки 1–4 (склад у x=−153), восток — 5–8 (зеркально).
* **Локальный кадр `A.Frame`**: +Z к воротам и улице (ворота Z=64), −Z к складу, X поперёк (забор X=±34), зеркалирование через `sx`. Занятость в кадре (участок 1, sx=1, по замерам плейса):

| Объект | Положение |
|---|---|
| Постройки склада, лавки и мастерской | Z∈[−67,−40] |
| CosmeticGarden | X∈[−31,−9], Z∈[−33.5,5.5] |
| Площадка MiningCorner | центр (−18·sx, −6.5), 23×18 |
| LuckyCourt | X∈[9.5,30.5], Z∈[−29.5,7.5], пады на X=20, Z=1/−11/−23 |
| Поле будок (WorkArea) | Z∈[16.5,63.5]; ямы 12×12 на X=∓13, Z=24/40/56; домики будок на X=±25 |
| Стенд BEST FINDS | (20·sx, 55), 23×11 |
| Дорожка | X∈[−4.5,4.5] |

  Свободного места мало. Примерно остаются:
  * полоса Z∈[7.5,16.5] (2×≈26×9);
  * глубина сада за шахтой ≈22×15 (её делят с центральными украшениями скинов);
  * полоса перед постройками Z∈[−40,−33.5];
  * линия вдоль забора.

  Цифры оценочные. Нужен автоматический 3D-тест пересечений, как в docs/MINING.md.
* StreamingEnabled=true, MinRadius 64, TargetRadius 1024. Участки в режиме ModelStreamingMode Default (неатомарные).

### 7. Клиент и сервер
* **Сервер** владеет: раздачей участков, профилем, генерацией всего декора (PlotDevelopment), экспонатами (BestFinds, DisplayDog), моделями собак в будках, промптами.
* **Клиент** отвечает за: включение промптов сервиса (PlotPrompts), анимацию парения и тумана (PlotSkinMotion), превью в UI (PlotShopScreen, UpgradeTree, YardPage), окно будки (ServiceMenus), StorageScreen и DogsScreen.
* Прецедент клиентского рендера уже есть: музей (`MuseumPresentation.client` → `workspace.DogDexLocalDisplays`, лимиты `NearDistance/MaxNearModels`, один «бегающий» клиентский промпт VIEW ENTRY). Это готовый шаблон для F3 и F8.

### 8. Производительность (замер: Lune, `PlotAppearance.Apply` на копии Yard_01 из `build/DOGROTS_MINING.rbxl`, число потомков PlotDevelopment)
| Скин | L1 | L5 | L9 |
|---|---|---|---|
| Classic | 61 | 509 | 762 |
| BoneRain | 532 | 743 | 900 |
| GoldenHour | 528 | 811 | 1 071 |
| DogRush | 573 | 789 | 963 |
| TreasureFever | 1 212 | 1 582 | 1 860 |
| CrystalStorm | 701 | 975 | 1 158 |
| Earthquake | 683 | 934 | 1 115 |
| **TimeWarp** | 1 431 | 1 939 | **2 260** |
| CursedFog | 549 | 775 | 967 (3 эмиттера) |
| Blackout | 435 | 674 | 937 |
| UFOInvasion | 564 | 900 | 1 103 |
| RainbowRift | 910 | 1 250 | 1 405 (611 Neon) |
| NullHour | 402 | 573 | 778 (52 PlotFloat) |
| TheVoid | 528 | 767 | 1 056 |

Стенд BEST FINDS — это 37–234 инстанса внутри этих чисел. PointLight: 0 на L1, 4 начиная с L5.

* В худшем случае 8 участков дают +≈18 000 серверных реплицируемых частей поверх 12 454 базовых.
* Каждая смена скина, стадии или владельца — это destroy и create ~0.5–2.2 тыс. частей, которые получают все клиенты. Плюс `task.defer` на каждый потомок в PlotSkinMotion и `coverGround` в MiningWorld.
* Клиент: превью COSMETICS каждые 5 с клонирует ~3–4 тыс. инстансов. «Мой двор» — каждые 20 с.
* Сервер: `BestFinds.Select` O(Items) на каждом `Runtime.Project` (после каждого запроса и каждого тика работы собак).

### 9. Найденные баги и техдолг
1. **Двойная раздача участков**: `YardService.server` и `MapAmbience.server` (оба включены). Каждый ведёт свой Allocator и пишет одни и те же атрибуты. Состояния совпадают только из-за одинакового порядка; любое расхождение (порядок, задержка старта) приведёт к рассинхрону владельцев.
2. `updateSign/OwnerPlaque` в обоих скриптах — no-op: объекта `OwnerPlaque` в плейсе нет (поиск дал 0 совпадений).
3. Промпты «MANAGE» будок (`DogKennelService` L254-256) и «CHOOSE BLOCK» лаки-падов видны гостям на чужих участках. У будок нажатие молча ничего не делает. `PlotPrompts` отслеживает только `YardInteraction`.
4. Весь сгенерированный декор, включая стенд BEST FINDS, пьедесталы, заборы и ворота, **без коллизий** (`PlotGeometry.Part` L7). Сквозь витрину можно пройти.
5. Превью COSMETICS: полный клон участка и Apply на каждой перерисовке, перерисовка каждые 5 с. `A.Preview` без pcall (`PlotShopScreen` L35). При стриминге участок может прийти не полностью, тогда `A.Frame` упадёт на `yard.YardLandscape.YardFoundation` или `yard.StorageAnchor` (L13).
6. `YardPageController.geometry` клонирует все видимые части участка каждые 20 с.
7. Полная перестройка PlotDevelopment при любой смене. Любые объекты внутри (будущие промпты и якоря витрины) уничтожаются.
8. `PlotDevelopmentTests` и `EstateQATests` устарели и не вызываются:
   * ожидают стартовые 300 Cash (сейчас 4 200);
   * BoneRain за 1 200 (сейчас 6 000 после ×5);
   * `n<1800` (TimeWarp L9 = 2 260, TreasureFever = 1 860);
   * отказ `UpgradeVisit('Plot')` (сейчас true).

   Lune-тестов на PlotRules, DisplayRules, BestFinds и PlotAppearance нет. Покрытие есть только у `upgrade_tree.luau` (стадии) и `kennel.luau`.
9. Логика BEST FINDS слабая: «Find» берётся только из Treasure (23 из 108 предметов), остальное попадает в Relic. Выбора, анимации и FX редкости нет.
10. Защиты предметов нет: `ItemLock` отключён (`ItemRules` L24, L204). Есть только Favorite, и он защищает лишь от лаборатории (`LabRules` L40). Для витрины нужен собственный механизм защиты.
11. Дублирование кода:
    * `bounds/visibleBounds` и таблицы подкраски Variant в `PlotShowcase` (L4-12, L28), `BestFinds` (L29-35, L49-50) и `DogKennelService`;
    * `for i=1,3` в `PlotShowcase.Reconcile` при `DisplayRules.Slots=3`;
    * `PlotCatalog` мутирует цены ×5 при загрузке модуля (L33): «Cash» в таблице не совпадает с реальной ценой.
12. `DogKennelRequest` — мёртвый RemoteFunction. Его `Handle` клонирует шаблон собаки на каждый вызов (ограничено Allow 0.5).
13. Правила посещения непоследовательны: `Assign` в будку работает откуда угодно, `DisplayDog` — только у склада.
14. Несколько независимых обработчиков смены владельца с лишними пересборками (PlotDevelopment, PlotShowcase, DogKennelService → Runtime.Refresh).
15. Возможная хрупкость (не подтверждено): `RecordStats.Find` сравнивает `x[k] > s[...][k]` без проверки на nil. Очень старая сводка без поля сломает Mint.

### 10. Что можно улучшить поверх текущей системы, а что требует аккуратного рефакторинга
**Поверх текущей системы (без ломки):**
* F3 в виде фичи `Features/Showcase` с режимом Auto (точно как сейчас) и Manual. Стенд BEST FINDS остаётся, добавляются слоты по стадии.
* Защита экспонатов двумя хуками: `YardCommerce.CanSell` и `ItemRules.Get(...,transfer=true)`.
* Промпты на постоянных якорях вне PlotDevelopment, скопированные с будок. Фильтрация промптов будок и витрины по владельцу в `PlotPrompts`.
* Коллизии у пьедестала и основания витрины.
* Кэш превью по `AppearanceRevision` и pcall в PlotShopScreen. YardPage пересобирает превью только при смене ревизии.
* Общий `ItemRarity` (тир и цвет по CombinedOdds, Class, Mutation).
* Lune-тесты вместо устаревших Studio-тестов.
* Декор v1 с ограниченным бюджетом на сокетах и зонах сетки.

**Требует аккуратного рефакторинга:**
* Один конвейер владения участком: YardService как единственный владелец, табличка MapAmbience подписывается на атрибут. Один сигнал «владелец сменился».
* Перенос КОСМЕТИЧЕСКОЙ генерации PlotDevelopment на клиент: сервер публикует атрибуты `PlotStage/PlotSkin/PlotFrame/PlotMirror/ShowcaseLayout/DecorLayout`, клиент строит декор с LOD. Геймплей (будки, коллизии, промпты) остаётся на сервере. Придётся перенести `coverGround` (MiningWorld), пути в `Stare`, превью и QA.
* Разделение `PlotAppearance` на `PlotGameplay` (сервер) и `PlotArt` (общие билдеры, мотивы как данные вместо цепочек if/elseif), чтобы масштабироваться под F8.
* Явные цены в PlotCatalog.
* Общий модуль нормализации моделей для экспонатов, дисплеев и будок (нужен и F4, и F12).
* Унифицированная фабрика «PlotInteraction» для промптов (будки, витрина, декор, пады): серверная проверка, клиентская фильтрация, единый open-event. Удалить `DogKennelRequest`.

### 11. Риски
* Хуки защиты меняют поведение SELL ALL, обмена и лаборатории. Нужна ясная метка «НА ВИТРИНЕ» и снятие в одно нажатие.
* Тесное размещение на участке: MiningCorner, лаки-пады, будки, ямы (F5), зоны промптов с RequiresLineOfSight.
* Стриминг: клиентский декор нельзя строить, пока не пришёл фундамент участка.
* Модели в сборку добавить нельзя: декор должен быть процедурным, пока владелец не завезёт меши в Studio.
* Обратная совместимость: старые профили без новых полей должны выглядеть как сейчас (режим Auto).
* Зависимости от путей `PlotDevelopment.BestFinds.Slots.Dog.Exhibit` (Stare) и `DogStorage.DisplaySlots` (Stare, StorageScreen).

---

## Лаборатория и мутации (lab)

### 1. Кратко

Сейчас лаборатория — это окно-«мастер» в три шага (собака → действие → подтверждение) с пятью процедурами: **мутация** (переброс варианта), **генное наведение** (катализатор), **извлечение ДНК** («расщепление»), **возвышение** (ASCEND) и **рецепты/эксперименты**. Сервер считает план, подписывает его, а при подтверждении пересчитывает его внутри транзакции профиля (`LabInfo → LabPreview → LabCommit`). Результат мгновенный (отложенных «работ» нет). Потом **только у этого игрока** идёт кинематика камеры у капсулы `CentralChamber`. Другие игроки ничего не видят.

Мутация собаки — это поле `Dog.Variant` (одно из `Config.Variants`: Normal/Shiny/Golden/Corrupted/Glitched/Void). Переброс использует **те же** шансы, что и выпадение варианта у новой собаки: `Rules.VariantRows(p, now)`, то есть веса Config.Variants плюс активное мировое событие плюс личный бонус `DogMutation`.

Здание `05_MutationLab` внутри низкое: ~31 стад от пола до потолка. Труба на 60–100 стадов **не помещается внутри**. Её надо выводить через центральный световой фонарь крыши (подробно в §6 и §10.5).

### 2. Файлы и роли

| Файл | Строк | Роль |
|---|---:|---|
| `src/ServerScriptService/Economy/LabService.luau` | 70 | Серверная точка входа. `Visit` (проверка доступа), `Info`, `Request` (LabInfo/LabPreview/LabCommit, котировки `S.Quotes` в RAM на 120 с, транзакция `rt.Tx:Run`), `TryOpen`, `Start` (создаёт ProximityPrompt `GeneticsPrompt` на `InteractionAnchor`) |
| `src/ServerScriptService/Economy/LabRules.luau` | 263 | Чистая логика процедур: `Preview` (валидация + план + `Signature` через `L.Canonical`), `Public`, `Apply` (все изменения сохранения), `Catalog` (книга рецептов), `Rows` = `R.VariantRows` |
| `src/ServerScriptService/Economy/LabRecipeConfig.luau` | 14 | 3 рецепта (только сервер): GOLDEN_BREAKFAST, DIGITAL_ROAST, ECLIPSE_BLOODLINE |
| `src/ServerScriptService/Economy/LabState.luau` | 16 | `Normalize`/`Validate` блока `p.Lab` (вызываются из `Rules.Profile`, `Rules.Normalize`:91 и `Rules.Validate`:550) |
| `src/ServerScriptService/Economy/MutationDefinitions.luau` | 0 (одна строка) | Реэкспорт `ReplicatedStorage.DogEconomy.MutationDefinitions` |
| `src/ReplicatedStorage/DogEconomy/MutationDefinitions.luau` | 1 | Мутации **предметов** (NORMAL 98 %, GOLDEN 1,2 % ×2,5, RAINBOW 0,4 % ×8, CURSED 0,27 % ×5, GLITCHED 0,13 % ×15). К лаборатории и собакам отношения не имеет: используется в `ItemRules` и `InventoryController` |
| `src/ReplicatedStorage/DogEconomy/Config.luau` | 159 | `C.Variants` (строки 44–48): варианты собак с весами (сумма 10 000) и бонусом к доходу; `C.Ascension={0,.03,.06,.10}`; `C.Prices` |
| `src/ReplicatedStorage/LabConfig.luau` | 30 | Публичный баланс: процедуры и уровни, цены, стабильность, аффинити катализаторов, стабилизаторы, ДНК-ключи, генетика пород, выход ДНК, `HighValue`, цвета вариантов, `Cooldown=7`, `Duration=5.5`, `Distance=7.5` |
| `src/ReplicatedStorage/LabGenetics.luau` | 347 | Общие правила для сервера и клиента: `Check`/`Fix` (почему собака недоступна и как это исправить одной кнопкой), `ValueReasons`, `Cost`, `Stability`, `Chances`, `Extraction`, `Duplicates`, `Catalysts`, `FillRecipe`, `VariantColor` |
| `src/ReplicatedStorage/LabAccess.luau` | 16 | `Model()`, `CanUse(player)`: внутри `InteriorZone`, ≤7,5 стада до `InteractionAnchor`, raycast прямой видимости |
| `src/ReplicatedStorage/LabAudioConfig.luau` | 123 | 12 звуковых сигналов из встроенных звуков Roblox (`AssetIds` = 0), лимит 14 одновременных звуков |
| `src/ReplicatedStorage/Localization/Lab.luau` | 324 | Русские строки: Exact, Patterns, UI, Templates (покрытие проверяет тест) |
| `src/StarterGui/ScreenGui/Modules/LabScreen.luau` | 1869 | Окно на UI-ките: выбор породы (101 вид, поиск, чипы, сортировка, виртуальный список копий), 5 карточек действий, книга рецептов, выбор вручную, банк ДНК, модалка подтверждения с удержанием, экран результата, заставка «ПОКАЗАТЬ ПУТЬ» |
| `src/StarterGui/ScreenGui/Modules/LabPresentation.luau` | 108 | Локальная кинематика: Scriptable-камера из `PresentationCamera`, локальный клон `MechanicalRing` (оригинал скрыт через `LocalTransparencyModifier`), 3–8 неоновых «следов», перекраска PointLight и линз, клон собаки из `ReplicatedStorage.MenuModels`, `Skip()` |
| `src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau` | 22 | Каждые 0,15 с включает и выключает prompt по `Access.CanUse` и переводит его на русский |
| `docs/LAB.md` | 136 | Описание для игрока и владельца |
| `tests/lab.luau` | 782 | 24 теста (прогнал: 24 passed): общие правила, все процедуры на настоящем `LabRules`, протокол `LabService`, локализация, звуки |

Точки входа и связи: `Runtime.luau:385` (диспетчер `LabInfo|LabPreview|LabCommit`), `World.luau:12` (`LabService.Start()`), `GUIIntegration.luau:97-104,116` (`openLab` → `LabScreen.Open`), `EconomyScreens.luau:61,184` (старая страница Lab → `LabScreen.Build`), `OnboardingGuide.luau:27` (шаг 13 «OPEN LAB»), `PawpadController.client.luau:298-317` (старая `LabPage` с секциями Mutation/Ascend/Retire, все ведут в `OpenScreen('Lab')`), `Rules.luau:507` (старые действия `Retire|Mutation|Ascend|Fusion` отклоняются), `DistrictTravel.luau` (телепорт `Lab` → `NavigationAnchors/MutationLab`), `MapRouting.luau:11`, `LocationLabels.luau:12`.

### 3. Как это работает сейчас, от начала до конца

**3.1 Вход.** `LabService.Start` (`World.Start`) создаёт на `05_MutationLab.InteractionAnchor` (125.3, 5.8, 502) ProximityPrompt `GeneticsPrompt` («USE GENETICS LAB», HoldDuration 0,15, MaxActivationDistance 7,5, RequiresLineOfSight). На `Triggered` срабатывает `TryOpen`: проверки `rt.Ready`, `Access.CanUse` и лимит `rt.Allow(player,1)`, затем `DogEconomyOpen:FireClient(player,'Lab')` и `GUIIntegration` → `LabScreen.Open()`. Плитка LAB в HUD открывает то же окно. Если игрок не у терминала, показывается заставка с кнопкой «SHOW THE WAY» → `N.Navigate('Mutation lab')` (метка DistrictGuide).

**3.2 Протокол** (всё через `RemoteFunction DogEconomyRequest`, `Runtime.Request` → `LabService.Request`):
1. `LabInfo {}` → `{Tier, Level, Recipes=L.Catalog, Cooldown, CooldownEndsAt, Now, VariantRows=R.VariantRows(p), TutorialComplete}`.
2. `LabPreview {Procedure, Uids≤3, Items≤4, DNA, RecipeId, StabilizerUid, PrimaryUid}` → `L.Preview` проверяет всё, считает цену, шансы и выход. Сервер кладёт в `S.Quotes[userId]` план с `Token=Engine.Guid()` на 120 с и возвращает публичный план (без подписи; у скрытого рецепта нет результата).
3. `LabCommit {Token, Confirm=true, Acknowledge?, Typed?}`:
   * быстрый ответ из `p.Lab.History` по Token (идемпотентность);
   * проверка котировки;
   * `rt.Tx:Run({'p:uid', ['supply:<OutputDogId>']}, ..., receipt)`. Внутри: `R.Normalize`, повторный `Visit`, нет обмена, план пересчитывается и `Signature` сверяется («Dog, material or odds changed»), ценные собаки требуют `Acknowledge`, затем `L.Apply`.
   * После успеха `Runtime.Request` прикладывает к ответу `StateSnapshot` (`Runtime.luau:454-466`), и клиентский `Net` публикует его.

Атомарность: `Transactions:_runFast` выполняет transform над **копией** профиля и публикует результат только без ошибки. Любой `R.Check` откатывает всё. Повтор клиента (`LabScreen.commit` повторяет запрос при «Connection problem») идёт с тем же Token, и сервер отдаёт запись из History.

**3.3 Действия и что они пишут в сохранение**

| Действие (Procedure) | Уровень (Tier) | Стоимость (`LabGenetics.Cost`) | Изменения профиля (`LabRules.Apply`) |
|---|---|---|---|
| **Mutation** | 1 (L1) | 5000+1500·ранг монет, 5·ранг костей; первая попытка бесплатна (`not l.TutorialComplete`) | `dog.Variant` = бросок по `plan.Chances` (= `R.VariantRows`), `dog.PaidRandom` (см. баг 1), `R.Discover` → `p.DogDex`, `p.VariantDex`; `l.TutorialComplete=true`; с шансом `StrangeChance` +1 `l.DNA.StrangeDNA` |
| **Targeting** | 2 (L5) | 9000+2500·ранг, 7·ранг костей, 2 CommonDNA + 1 катализатор (+ необязательный стабилизатор) | как Mutation, плюс `l.DNA.CommonDNA-=2`, `p.Items[катализатор]=nil`, `p.Items[стабилизатор]=nil` |
| **Extraction** («расщепление») | 3 (L8) | 2000+750·ранг | `p.Dogs[uid]=nil`; `l.DNA[k]+=n` по `G.Extraction` (Common/Rare DNA, MutationShards, пробы генов, CoreFragment); `l.DiscoveredDNA`; `l.PaidDNA=true`, если собака была PaidRandom; артефакты возвращаются через `R.Features.Normalize` |
| **Fusion / ASCEND** | 4 (L12) | 25000·(A+1) монет, 25·(A+1) костей, 2 дубликата | 2 дубликата удаляются, `primary.AscensionLevel+1` (макс. 3), `primary.PaidRandom` |
| **Fusion/Creation — рецепт** | 4/5 (L12/L18) | монеты, кости, ДНК, предметы рецепта | Успех (шанс `60+0,4·стабильность`, ≤98 %): собаки удаляются; `R.Mint(origin LAB_FUSION/LAB_EXPERIMENT, OutputMutation)` → новая собака с `LabRecipe`, `PricePaid=0`; `supply:<DogId>.Minted+1`; `l.Recipes[id]=now`. Неудача: собаки остаются, возвращается половина ДНК, +1 StrangeDNA, монеты и предметы потрачены |
| **Все** | — | — | `R.Pay`; `l.LastAt=now` (остывание 7 с); `l.Experiments+=1`; запись в начало `l.History` (≤40, собака в «тонкой» копии); `l.FirstDiscoveries['MUTATION:'..Variant]`, `['DNA:'..k]`, `['RECIPE:'..id]`; `State.Validate` + `R.Validate` |

Шкала рангов: Common 1 … Secret 6. Дорогие переброски (вариант ≠ Normal) и потеря «ценной» собаки (`G.ValueReasons`: Epic+, вариант, возвышение, мастерство ≥25, коллекционная, лабораторная, с артефактами) требуют удержания кнопки 1,2 с и `Acknowledge`.

**3.4 Варианты собак (мутации).**
* Хранение: `p.Dogs[uid].Variant` (строка). Это **сохранённые данные**, переименовывать нельзя (так написано в комментарии Config:43). Валидные имена — `Rules.VariantNames`. Учёт виденных вариантов: `p.VariantDex[DogId][Variant]=true` (`Rules.Discover`; `Features/Dogdex.luau` ведёт ещё и битовую маску для отображения).
* Шансы (`Config.Variants`, веса из 10 000):

  | Вариант | Шанс | Бонус к доходу |
  |---|---:|---:|
  | Normal | 77 % | +0 % |
  | Shiny | 15 % | +12 % |
  | Golden | 5 % | +30 % |
  | Corrupted | 2 % | +50 % |
  | Glitched | 0,8 % | +75 % |
  | Void | 0,2 % | +110 % |
* Доход: `Rules.Bonus(d) = 1 + Variant.Bonus + min(100, Mastery)·0,0015 + Ascension[A]` (Rules:231). Он входит в `Rules.Dig`:293, в модель дохода и в цену приюта `BasePrice·0,25·Bonus` (`ShelterRules.Rate=.25`).
* `R.VariantRows(p, now)` = `WorldEventModifiers.MutationRows` (событие увеличивает веса мутированных вариантов, Normal забирает остаток) × личный бонус `Bonuses.Global(p).DogMutation` (дерево улучшений, `UpgradeTree.luau:211`; Normal остаётся не меньше половины). Лаборатория и конвейер используют эту же функцию. Lucky Blocks и Dog-o-Matic берут замороженные строки без личного бонуса.

**3.5 Реальные цены переброса сейчас** (проверил своим Lune-скриптом на настоящих модулях):

| Редкость | BasePrice | Переброс | Доля от цены собаки |
|---|---:|---|---:|
| Common | 3 500 | 6 500 + 5 костей | 186 % |
| Rare | 22 000 | 8 000 + 10 | 36 % |
| Epic | 140 000 | 9 500 + 15 | 6,8 % |
| Legendary | 900 000 | 11 000 + 20 | 1,2 % |
| Mythic | 6 500 000 | 12 500 + 25 | 0,19 % |
| Secret | 55 000 000 | 14 000 + 30 | 0,025 % |

Цена почти плоская. На поздней стадии (5 Secret на VOID ≈ 7,9 млн/мин, docs/ECONOMY.md §5) переброс стоит долю секунды дохода.

**3.6 Клиент.** `LabScreen` берёт профиль из `Net.Snapshot`, а шансы и цены — из тех же функций `LabGenetics`, что и сервер. Каждое действие — это `LabPreview`, затем `Kit.Modal` (Hold для ценных), затем `LabCommit`, затем `play()` (`N.BeginReward` прячет окна, кнопка SKIP), затем `LabPresentation.Play`, затем `showResult` (кнопка «ЕЩЁ РАЗ» для мутации). `LabPresentation` длится `result.Duration` (5,5 с), меняет статус локально («CHAMBER SEALED → ANALYSING DNA → …»), на t>0,72 подменяет модель собаки на новую с подсветкой `Highlight` цвета варианта и после этого всё восстанавливает. ReducedMotion/LowFX уменьшают эффекты и отключают камеру.

### 4. Сохранённые данные

DataStore `DOGROTS_ECONOMY_V1` (`Runtime.luau:26`, через `StoreKeys.Wrap`), ключ профиля `p:<UserId>`. Рецепты, создающие собак, трогают ещё `supply:<DogId>` (счётчик серийников).

Блок `p.Lab` (`LabState.Normalize`):
* `Version` — **всегда перезаписывается на 1**, миграций нет.
* `DNA {key=int ≤1e6}`, `DiscoveredDNA {key=true}`, `Recipes {RecipeId=time}`, `History[≤40] {Token, At, Procedure, RecipeId, Secret, Stability, Consumed, DNA, Success, Duration, ReturnedArtifacts, Message, FirstDiscovery, Dog=slim}`, `FirstDiscoveries {'MUTATION:x'|'DNA:x'|'RECIPE:x'=time}`.
* `Experiments` (int), `Tier` (1..5, растёт от `p.Level`), `LastAt` (os.time последней процедуры), `TutorialComplete` (bool, первая мутация бесплатна), `PaidDNA` (bool).

Поля собаки, которые пишет лаборатория: `Variant`, `AscensionLevel`, `PaidRandom`, `LabRecipe`, `Origin='LAB_FUSION'|'LAB_EXPERIMENT'`, `PricePaid=0` (новые собаки). Плюс `p.DogDex`, `p.VariantDex`, `p.Items` (расход катализаторов), `p.Cash`, `p.Bones`.

`LabState.Validate` требует, чтобы **каждый ключ `l.DNA` был в `LabConfig.DNA`**. Иначе `R.Validate` бросает «Invalid DNA inventory» в **любой** транзакции игрока. Это важно для вывода ДНК из обращения (§10.4).

Отложенного состояния (таймеров, «работ в процессе») у лаборатории **нет**: `Apply` мгновенный, `Duration` — только длина кинематики. В RAM живут только `S.Quotes` (120 с, сбрасываются при выходе игрока).

### 5. Сетевая поверхность

* `RemoteFunction ReplicatedStorage.DogEconomyRequest` (client→server, `InvokeServer(action, args, requestId32hex)`): `LabInfo`, `LabPreview`, `LabCommit`. Окно также зовёт `DogLock`/`DogFavorite`/`Remove` (одна кнопка для разблокировки собаки) и `DistrictTravel {Destination='Lab'}`. Общий лимит запросов: `Runtime.allow` (8 токенов, +1,5/с), `clean()` ограничивает аргументы (глубина ≤3, ≤30 ключей, строки ≤120).
* `RemoteEvent ReplicatedStorage.DogEconomyOpen` (server→client) `('Lab')`, когда срабатывает prompt.
* `ProximityPrompt 05_MutationLab.InteractionAnchor.GeneticsPrompt` (Triggered на сервере).
* Отдельного RemoteEvent для показа нет: кинематика чисто локальная.
* Побочный эффект: `LabInfo` и `LabPreview` (только чтение) идут в ветку `Runtime.Refresh(player)` (`Runtime.luau:446-452`), то есть `Runtime.Project` (атрибуты, `PlotDevelopment.Reconcile`, `Kennels.Reconcile`, `PlotShowcase.Reconcile`) на каждое открытие окна и каждый предпросмотр. `LabCommit` получает полный `StateSnapshot` (копию всего профиля).

### 6. Мир: `Workspace.DOGROTS_District.05_MutationLab` (измерено Lune-скриптами по build/DOGROTS_MINING.rbxl)

* Модель целиком (с променадом): X 8…156, Y 0…57, Z 428…527, 983 детали, 13 PointLight, 23 SurfaceGui. Само здание: X 84…156, Z 428…527. `ModelStreamingMode=Default`. В Workspace: StreamingEnabled=true, MinRadius 64, TargetRadius 1024.
* `InteriorZone` (повёрнутая невидимая деталь): X 86…152, **Y 1…33**, Z 430…524. Пол `PanelFloor`: верх Y≈2,29. Под потолком: `CeilingServices` Y 28…36, балки `StructuralCrossBeam` на X=99/122/144 (Y 34,9, идут вдоль Z 448…506). Крыша: крылья Y 33…37, рельсы нефа Y 37…38, **`TechnicalRoof.CentralSkylight`** (стекло, прозрачность 0,94) Y 37,9 над X 96…142 × Z 461…493, решётка `LanternBeam`/`LanternCrossbar` Y 38…39, `CrossRoof` X 142…154, вентустановки до Y 45, антенна до Y 49. Табличка `LocationLabelAnchor` на Y 57 (её ставит `LocationLabelsBootstrap` над `TechnicalRoof`).
* Вход: `EntranceAnchor` и `NavigationAnchors/MutationLab` (78, 3, 477), фасад `GlassFacade` X 78…100 с `LaboratoryAutomaticDoor`.
* **Свободный пол**: центральный неф X 86…125 × Z 458…496 до потолка пуст (там только лампы, `PresentationCamera` (109, 20, 477) и `AudioAnchor` (123, 10, 477)).
* Нынешняя капсула `CentralChamber` (139 деталей): X 125…143, Y 2…33, Z 457…497. `DisplayAnchor` (134, 8, 477) смотрит на −X (ко входу). В ней `MechanicalRing` (112 деталей), `ClearContainment`, `ChamberStatus.StatusText`.
* Станции (декор, тексты устаревших действий): `GeneticsTerminal` X 126…132 Z 497…507 (рядом `InteractionAnchor`), `DNAExtractor` («DNA EXTRACTION»), `FusionStation` («FUSION / CREATE»), `DNAArchive`, `MutationAnalysis`, два `ArchiveSampleCapsule` (X 147…153, Z 460…466 и 488…494), `FusionObservationTank`, `Subject008Chamber` (X 118…134, Z 434…453), `ResearchArchiveWall` (X 150…153).
* Вокруг:
  * север: `08_GlobalDigSite` с Z 532 и чёрный куб `37_AttractionRefresh.GlobalEventComingSoon` (X 33…214, Y −49…50, Z 531…745);
  * юг: `11_Shops/SUPPLIES` (X 115…156, Z 374…416);
  * восток: X 156…~216 до края острова (`CohesiveIsland` X±216). Там сады `ProgressionGardens.Cypress` (X 165…177, Z 509…521) и `PocketGardens.Broadleaf` (X 174…180, Z 484…490);
  * запад: Dog Express (X 25…32) и променад.
* **Вывод:** внутри всего 31 стад высоты, поэтому труба на 60–100 стадов внутри не помещается. Без сноса стен лучше всего поставить трубу на место `CentralChamber` (центр X 134, Z 477) и вывести её через `CentralSkylight` над крышей (до Y ≈ 95). Радиус стеклянной оболочки до 12–13 стадов, фланец основания до 15: капсулы архива на ~17 стадах от центра, `GeneticsTerminal` на ~20. Консоль ставится в пустой неф перед трубой (X 106…118, Z 465…489). Вторая возможность — двор-реактор на востоке (X 160…212 × Z 440…515), но тогда надо открывать заднюю стену и переносить 6 садовых объектов. Подробности в §10.5.
* Прежние Studio-инсталляторы (`MapRefreshInstaller`, `AttractionRefreshInstaller`) трогают лабораторию точечно: скрывают `PromenadeConnection.EntryWalk`, прокладывают `LabApproach`, сдвигают `GlassFacade.WindowCrown` на 0,12. Это **Studio Edit**-инсталляторы (`assertEdit`), их результат сохранён в .rbxl. Наш build умеет патчить только скрипты, поэтому новую геометрию придётся строить во время работы сервера. Прецедент — `MiningWorld.server.luau` (`LAYOUT_VERSION`, `MiningModels.Part`).
* `WorldDetailQuality.client.luau` берёт под контроль **все** PointLight и ParticleEmitter внутри `DOGROTS_District`: каждые 0,4 с ставит Enabled и Rate ≤8 (на слабом железе ≤2), оставляет 24 (8) ближайших света. Исключения — атрибуты `LuckyVisual` и `MuseumLight`. Эффекты кинематики, положенные в карту, будут им «задушены». `LabPresentation` уже держит свои эффекты в отдельной папке `workspace.LocalGeneticsFX`, вне карты.

### 7. Клиент и сервер, производительность

* Сервер: только расчёт и транзакция (≤3 собаки, O(собак) на `FillRecipe`/`Duplicates`). Каждый `LabCommit` возвращает полный снимок профиля. `LabInfo`/`LabPreview` лишний раз запускают `Runtime.Project`.
* Клиент: `LabPrompt` делает Heartbeat каждые 0,15 с; raycast выполняется только внутри зоны. `LabScreen` строит 101 скрытую TextLabel-«пробу» для русского поиска, сетку карточек и ViewportFrame-превью (`Kit.Preview`). `LabPresentation` создаёт 3–8 деталей за показ без пула, крутит RenderStepped-цикл ~5,5 с и клонирует собаку из `MenuModels` (101 модель, всего 569 деталей).
* Звук: всё на встроенных звуках с эффектами, лимит 14.

### 8. Найденные проблемы, баги и техдолг

1. **Баг: обычная мутация помечает собаку `PaidRandom`.** В `LabRules.Apply` стоит `paid=l.PaidDNA==true` для **любой** процедуры. Если игрок хоть раз извлёк PaidRandom-собаку (`l.PaidDNA=true`), то каждый следующий переброс (без ДНК!) и каждое возвышение ставят собаке `PaidRandom=true`. Это ограничивает её обмен и продажу для аккаунтов, где `IsPaidItemTradingAllowed=false` (`PaidItemPolicy`). Подтверждено скриптом: Breadog, `PaidDNA=true`, Mutation: `PaidRandom nil → true`.
2. **Почти плоская цена переброса** (§3.5). Secret — 14 000 монет. Отсюда арбитраж: ~500 перебросов до Void ≈ 7 млн монет + 15 000 костей, а цена Void-Secret в приюте выше на `55M·0,25·1,1 ≈ 15 млн` и доход ×2,1. Кости, вероятно, сдерживают, но их приток я не измерял.
3. `LabInfo`/`LabPreview` вызывают `Runtime.Refresh → Project` (реконсиляция участка, будок, витрины) на запросы только для чтения (`Runtime.luau:446-452`).
4. `LabState.Normalize` жёстко ставит `l.Version=1`: механизма миграций нет. `LabConfig.Version=3` с данными не связан.
5. `LabState.Validate` падает на неизвестных DNA-ключах. Если удалить ключи из `LabConfig.DNA`, профили с ДНК перестанут проходить любую транзакцию.
6. **Семь разных палитр вариантов:** `LabConfig.Colors` (= `Kit/Theme.Variant`, проверяется `tests/uikit.luau:315`), `EconomyVisuals.client:7` (подсветка собак в будках), `DogLineSpawner.server:28`, `PlotShowcase:28`, `BestFinds:50`, `PreviewRenderer:34`, `LuckyLifecycleFX:123`. Например, Corrupted в лаборатории красный (209,64,83), а на собаках в будках и на конвейере фиолетовый. Смена цвета в кинематике не совпадёт с видом собаки в мире.
7. Стабилизатор в обычной мутации **ухудшает** шанс Void/Glitched (`G.Chances`: ×0,55 при `stabilizer>0` без цели) и влияет только на шанс StrangeDNA. Для игрока это контринтуитивно.
8. Кинематику видит только владелец. Статус капсулы и свет меняются локально.
9. `LabPresentation` не использует пул (детали создаются на каждый показ), `P.Seen` растёт за сессию (мелочь). Ход фаз жёстко завязан на имена `CentralChamber/MechanicalRing/EnergyBase/CrownEnergy/MutationNode`.
10. Остатки старого: в `PawpadController` есть `LabPage` с секцией «Retire» (такой процедуры нет). Тексты `EconomyScreens:126` («Mutate · ascend · evolve»), `MapRouting:11`, `OnboardingGuide:27`, станции в мире («DNA EXTRACTION», «FUSION / CREATE») описывают старые действия.
11. `S.Quotes` хранит одну котировку на игрока: новый предпросмотр отменяет открытую модалку («Preview expired»). `LabService.Start` упадёт с индексом по nil, если в карте нет `05_MutationLab`.
12. `LabScreen` (1869 строк) — около 45 % кода приходится на рецепты, наведение, ДНК и ручной выбор (`makeCard/renderCard` ~541–840, `OpenPicker` 1467–1560, `ShowDNA`). Окно перегружено: три шага, 5 карточек, банк ДНК, книга рецептов.

### 9. Что можно улучшить поверх текущей системы / что требует аккуратного рефакторинга

**Поверх (без ломки данных):**
* Новое серверное действие `LabReroll` на уже готовых кирпичах: `G.Check/Fix`, `R.VariantRows`, `R.Pay`, `rt.Tx:Run`, `l.History` по Token, `ValueReasons` для удержания.
* Кривая цены `LabConfig.Reroll` и общая `G.RerollCost` (клиент показывает, сервер списывает).
* Исправить баг 1 одной строкой: `PaidDNA` учитывать только когда тратится ДНК.
* Выключить процедуры флагами `Enabled=false` в `LabConfig.Procedures` вместо удаления кода. Отказ в `LabRules.Preview`.
* Перенести `InteractionAnchor` (имя сохранить) к новой консоли: `LabService.Start`, `LabAccess` и `LabPrompt` продолжат работать.
* `RemoteEvent LabMutationShow` для показа другим игрокам по образцу `RewardMachinePresentation` (серверное время, очередь, режим Personal).
* Убрать `Runtime.Refresh` для `LabInfo`. Вместо полного снимка отдавать небольшой `StatePatch`.
* Свои звуки через `LabAudioConfig.AssetIds`.

**Требует аккуратного рефакторинга:**
* Миграция `p.Lab` до версии 2 (судьба ДНК, `LabState.Validate`, идемпотентность). §10.4.
* Замена `LabScreen` новым меню консоли с сохранением публичного API (`Open/Close/Build/ShowResult/SetView`), на который завязаны `GUIIntegration`, `EconomyScreens`, онбординг и эмуляционные тесты.
* Замена `LabPresentation` таймлайном с пулом объектов и якорями нового реактора, с учётом `WorldDetailQuality`.
* Мировая сборка реактора во время работы сервера: скрыть и разрезать `CentralChamber`, `CentralSkylight`, балки и решётку крыши обратимо (атрибуты `LabReactor_*`); перенести `LocationLabelAnchor`.
* Единый модуль цветов и эффектов вариантов вместо 7 палитр (затрагивает тест `uikit`).
* Решение владельца по возвышению (ASCEND): это работающая механика, а не «расщепление».

### 10. План F12 «Ядерная мутационная машина»

**10.1 Поток игрока.**
1. Игрок подходит к консоли, prompt «АКТИВИРОВАТЬ · МУТАЦИОННАЯ МАШИНА».
2. Открывается полноэкранное меню консоли. Слева карусель или сетка **своих** собак: сначала редкие, у каждой цветная плашка варианта. Занятые собаки помечены замком, а «исправить» делается одной кнопкой (`G.Fix`).
3. По центру крупное 3D-превью, текущий вариант и его +% к доходу.
4. Внизу полоса шансов (6 цветных сегментов), плашка цены (красная, если денег не хватает) и огромная кнопка **МУТИРОВАТЬ**. Если текущий вариант ≠ Normal, кнопку надо удерживать 1,2 с. Первая попытка помечена «БЕСПЛАТНО».
5. Затем кинематика (можно пропустить), потом карточка результата: «БЫЛО → СТАЛО», изменение дохода, большая **ЕЩЁ РАЗ · цена** и «Другая собака».
6. Нет ДНК, рецептов, катализаторов и стабилизаторов.

**10.2 Серверное действие `LabReroll`.**
* Аргументы: `{DogUid, Token(32hex), Cost (цена на экране), Acknowledge?}`. Добавить в диспетчер `Runtime.luau:385`.
* В `LabService.Request` вне транзакции: `Visit` (зона, дистанция, прямая видимость), нет обмена, флаг «уже идёт» в RAM (`S.Busy[userId]`), остывание `now-l.LastAt>=Reroll.Cooldown` (3–4 с, кинематику можно пропустить).
* Внутри `rt.Tx:Run({'p:'..uid}, fn, receipt)` вызывается новый чистый `LabRules.Reroll(p,a,now,random,token)`:
  * `R.Normalize`;
  * повторить по Token из `l.History`;
  * `d=L.Dog(p,uid)` (`G.Check`);
  * `cost=G.RerollCost(d,p)`; `R.Check(a.Cost==cost,'Price changed')` по образцу `quoted()` в Rules;
  * бесплатно, если `not l.TutorialComplete`;
  * для ценного варианта `R.Check(a.Acknowledge==a.Token)`;
  * `R.Pay`;
  * бросок по `R.VariantRows(p,now)`: **ровно те же шансы, что сегодня**, с событиями и `DogMutation`; сегодняшняя `Mutation` без стабилизатора даёт те же проценты;
  * `d.Variant=new`, `R.Discover`; `PaidRandom` не трогать;
  * `l.LastAt`, `l.Experiments+=1`, новое `l.Rerolls+=1`, запись в History `{Token, At, Procedure='Reroll', From, To, Cost, Dog=slim}`, `FirstDiscoveries['MUTATION:'..to]`;
  * `State.Validate` и `R.Validate`.
* Ответ: `{Token, Dog, From, To, Cost, Chances, Show={StartAt=GetServerTimeNow()+.25, Duration}}`. После успеха, вне транзакции и не влияя на результат: `LabMutationShow`.
* «Никогда не терять собаку»: меняется только поле `Variant` той же записи, транзакция работает по копии. Тест проверяет, что набор `DogUid` и все поля, кроме Variant, не изменились.
* Защита от спама: `Runtime.allow`, `l.LastAt`, `S.Busy`, блокировка кнопки на клиенте.

**10.3 Кривая цены** (в `LabConfig.Reroll`, общая функция в `LabGenetics`): `Cash = max(Floor[rank], round(BasePrice[rank]·Share))`, без костей.

Пример при Share=0,04 и Floor={5000,7000,9000,0,0,0}:

| Common | Rare | Epic | Legendary | Mythic | Secret |
|---:|---:|---:|---:|---:|---:|
| 5 000 | 7 000 | 9 000 | 36 000 | 260 000 | 2 200 000 |

Ожидаемая цена Void (≈500 перебросов) — ≈20·BasePrice, а прирост цены в приюте всего 0,275·BasePrice: арбитраж исчезает. Golden-Secret (≈20 перебросов) обойдётся в ≈44 млн и окупится примерно за 1,5 ч дохода. По желанию можно добавить `VariantFactor` для переброса уже мутированной собаки. Числа надо прогнать через `tools/balance_sim.py` вместе с F11.

**10.4 Вывод расщепления и рецептов без поломки сохранений.**
* `LabConfig.Procedures`: Targeting, Extraction, Creation (и рецептные Fusion) получают `Enabled=false`. `LabRules.Preview` отказывает текстом «Процедура перенесена: используй мутационную машину». Код и тесты остаются на один релиз.
* **Ключи `LabConfig.DNA` не удалять** (из-за `LabState.Validate`).
* `LabState.Normalize` → версия 2 (заменить `l.Version=1` на условную миграцию). Однократно: `l.LegacyDNA=copy(l.DNA)`, сам `l.DNA` не трогать; начислить `l.RerollCredits` (бесплатные перебросы по таблице ценности ДНК) **или** монеты через `R.Credit(p,n,false)` с учётом `MaxCash`; поставить `l.Version=2`.
* Миграция идемпотентна, потому что `R.Normalize` вызывается при каждой загрузке и в каждой транзакции.
* `Recipes`, `FirstDiscoveries`, `History`, `Experiments`, `Tier`, `TutorialComplete` сохраняются как есть.
* Лабораторные собаки (`LabRecipe`, `Origin LAB_*`) остаются обычными собаками.
* Катализаторы и стабилизаторы — обычные находки раскопок (`ItemDefinitions`: golden_scarab, quartz_crystal…), их можно продавать, миграция не нужна.
* Отложенных работ нет. `S.Quotes` исчезнут при перезапуске серверов.
* Новые и старые клиенты на одном сервере не встречаются (Roblox обновляет сервер и клиентов вместе).
* Возвышение (ASCEND): **решение владельца**. Рекомендация — сохранить серверный путь и показывать в меню консоли маленькую кнопку «ВОЗВЫСИТЬ» только у собаки, у которой есть 2 готовых дубликата (или перенести в окно собак).

**10.5 Мир: реактор (сборка во время работы сервера по образцу инсталляторов).**
* Новый `ServerScriptService/Economy/LabReactorWorld.luau`. `Install()` идемпотентен, есть `LAYOUT_VERSION`, исходные свойства скрытых деталей пишутся в атрибуты `LabReactor_*` (как `DistrictRefresh_*`), есть `Validate()`. Вызывается из `World.Start` **до** `LabService.Start`.
* Геометрия описывается чистым «чертежом» в `ReplicatedStorage/LabReactorConfig.luau` (размеры, имена якорей), чтобы Lune-тест проверял его без экземпляров.
* Скрыть: весь `CentralChamber` (вместе с `MechanicalRing`), `CentralSkylight` (заменить 4 стеклянными панелями вокруг воротника r≈14), балки `StructuralCrossBeam` X=122 и X=144 (разрезать на сегменты), `LanternBeam` Z=477, `LanternCrossbar` X=127/142, часть `CrossRoof`.
* Построить модель `05_MutationLab/MutationReactor` (`ModelStreamingMode=Atomic`, ~150–250 Anchored деталей, CastShadow=false у стекла и неона, CanQuery=false у декора):
  * основание и фланец r 15 (Y 2,3…5) с люком подъёмника;
  * стеклянная оболочка r 12 (Material Glass, 3 цилиндрических секции до Y≈90);
  * внутренний «жидкостный» цилиндр (Neon/ForceField, цвет = состояние);
  * 8 металлических колец, 6 вертикальных рёбер, электроды;
  * «корона» на вершине (Y 88…98) с маяком;
  * якоря `CameraHooks/{ConsoleView, Low, Orbit, Sky}`, `LiftStart` (Y 3), `LiftTop` (Y≈16–20, собака видна от консоли), `TubeCenter`, `AudioAnchor`, `CrownBeam`.
* Консоль: X 106…118 × Z 465…489, лицом на −X, наклонные экраны (SurfaceGui: «ГОТОВО», имя последнего игрока и результат), большая физическая кнопка. `InteractionAnchor` переносится на ≈(112, 6, 477). Игрок стоит у ≈(103, 3, 477). `LabAccess.Distance` поднять до ~10.
* `LocationLabelAnchor` поднять над короной (`LocationLabels`: `Roof='MutationReactor'` или `Clearance`). Перекрасить тексты старых станций.
* Огни и эмиттеры реактора внутри карты пометить атрибутом-исключением для `WorldDetailQuality` (например `LabReactorFX`, по аналогии с `MuseumLight`). Иначе их будет выключать общий бюджет.

**10.6 Клиентская кинематика (новый `Modules/LabCinematic.luau` вместо `LabPresentation`).**

Таймлайн ~8 с, пропуск после ~1,5 с:
1. **0–0,6 с.** `N.BeginReward` прячет UI, камера плавно уходит на `ConsoleView`. Фаза **начинается по нажатию**, ответ сервера приходит во время подъёма. При ошибке аккуратный откат с текстом «ничего не списано».
2. **0,6–2,2 с.** Подъём: локальный клон платформы (оригинал скрыт через `LocalTransparencyModifier`) с собакой из `MenuModels`, увеличенной до ~12–14 стадов, едет от `LiftStart` к `LiftTop`. Манипуляторы, пар.
3. **2,2–4,6 с.** Заряд: уровень жидкости растёт, 6 колец энергии из пула идут вверх, Beam-разряды на электроды, медленный облёт камерой (`Orbit`) и наклон вверх через фонарь к короне.
4. **4,6–5,4 с.** Вспышка: белый экран, всплеск Bloom/ColorCorrection, `:Emit(n)`, силуэт собаки.
5. **5,4–7 с.** Финал: смена цвета на новый вариант (общий модуль `VariantVisuals`), ударная волна, луч из короны в небо. Сила зависит от редкости: Void — тёмно-фиолетовый вихрь и затемнение, Normal — скромно. Наезд камеры.
6. **7–8 с.** Собака опускается, карточка результата с «ЕЩЁ РАЗ».

Требования:
* Все объекты создаются один раз и переиспользуются. Эффекты лежат вне `DOGROTS_District` (`workspace.LocalLabFX`). Обновлять только пока показ идёт.
* LowFX/ReducedMotion и мобильные: ~3 с, без облёта, эмиттеры ×0,3, FOV ≤70, кнопка пропуска в безопасной зоне.
* Если реактор не подгрузился (стриминг), показать только UI-раскрытие.

**10.7 Что видят другие игроки.**
* Сервер шлёт `LabMutationShow` `{UserId, Name, DogId, From, To, Rarity, StartAt, Duration, Mode}` игрокам в радиусе ~200 стадов от реактора (цикл `FireClient`, ~150 байт, не чаще раза в 4 с на игрока).
* Публичная очередь как в `RewardMachinePresentation` (`queue.Tail`). Если ждать больше ~6 с, вместо полного показа будет короткий «пульс».
* Клиенты рядом (`StarterPlayerScripts/LabReactorFX.client.luau`): клон собаки в трубе, цвет жидкости, вспышка, луч из короны, текст на экране консоли «Игрок X: VOID!». **Без камеры.**
* Владелец свою публичную копию пропускает по Token. Его личная кинематика идёт сразу и не зависит от очереди.
* Сервер ничего не анимирует. В простое реактор «дышит» на клиенте (10–15 Гц, только ближе 150 стадов).

**10.8 Тесты.**
* `tests/lab.luau`: проценты `LabReroll` равны `R.VariantRows`; кривая цены; отказ при сменившейся цене; удержание для ценных; повтор по Token; набор собак неизменен; остывание; выключенные процедуры получают отказ; миграция v2 идемпотентна; старая ДНК проходит `Validate`; баг `PaidRandom` исправлен.
* Новый `tests/lab_reactor.luau`: чертёж внутри острова и здания, консоль и prompt внутри `InteriorZone`, вершина ≥60 стадов над полом, нет пересечений с оставленными станциями.
* Ручная проверка: новый игрок (первый переброс бесплатный, 0–1 собака), старый игрок (ДНК, рецепты, лабораторные собаки), слабый ПК (LowFX), телефон (портрет и ландшафт).

**10.9 Риски и решения владельца.** Судьба ДНК (бесплатные перебросы или монеты), возвышение в меню или в окне собак, Share кривой цены, вариант A (сквозь крышу) или B (двор на востоке). Пересечения: F1 (путь к консоли), F2 (стиль кита), F9 (скрытие UI), F10 (титулы), F11 (баланс).

---

## Интерфейс, HUD, инвентарь (UI)

> Аудит только для чтения. Все утверждения ниже проверены по коду в `src/` и по дампу `build/DOGROTS_MINING.rbxl` (свои скрипты Lune в `scratchpad/tools/ui/`). Если что-то проверить не удалось, это сказано прямо.

### 1. Коротко

* В игре **три поколения UI, и они работают одновременно**:
  1. **(A) Статические страницы `MainWindow`.** Они лежат в .rbxl. Их обслуживают `PawpadController`, `InventoryController`, `YardPageController`, а при старте их перекрашивает `UITheme.ApplyShell/ApplyStandalone`.
  2. **(B) `Modules.Menus`.** UI в immediate-mode: на каждый fetch (раз в 5 с) делается `canvas:ClearAllChildren()` и вся страница строится заново через `UITheme` (`EconomyScreens`, `DiscoveryScreens`, `RewardScreens`, `LuckyBlockUI`, `CommerceShopScreen`, `EventsScreen`, `SuppliesScreen`, `LuckScreen`, `PlotShopScreen`, `StorageScreen`, `OfflineEarningsScreen` и др.).
  3. **(C) Новый `Modules.Kit`** (`docs/UIKIT.md`). Его окна персистентные, `VirtualGrid` и кэш превью работают. На Kit пока переведены только **Dogs, Dogdex (+DexEntry), Lab, UpgradeTree, Equipment (+CaseOpening/ArtifactPanel)** и KitDemo.
* **Инвентарь (BAG) — это поколение (A).** Это статическая `InventoryPage` с 17 кнопками и фильтрами-«циклами». Одни и те же находки показывают ещё 4–5 разных экранов: `DiscoveryScreens`, ServiceMenus «Seller», мёртвые `DiscoveriesPage` и `CollectorScreen`, `Loot`.
* Звуков интерфейса **нет совсем**. SoundGroup `UI` в месте отсутствует. Своих загруженных SFX тоже нет: есть только 14 музыкальных лупов.
* Системы «спрятать весь UI» нет. Есть 20+ ScreenGui, которые создают скрипты во время игры, и десятки BillboardGui (большая часть создаётся в рантайме, в том числе сервером).
* Найдены серьёзные проблемы:
  * отладочный `LocalScript.client.luau` переводит «DOGS» на русский всем игрокам;
  * `BulkSell` продаёт ★-избранное, а «ВЫБРАТЬ ВСЁ → ПРОДАТЬ» работает без подтверждения;
  * кнопка «SELL TO MILO» в сумке не работает вдали от коллекционера;
  * `GUIIntegration.ready()` зависит от регистрации `InventoryController`. Если убрать старый инвентарь, перестанет открываться **любое** меню;
  * клиенты постоянно опрашивают полный `Snapshot` профиля.

### 2. Как устроено сейчас (сквозной поток)

#### 2.1 Слои экрана (PlayerGui)
| ScreenGui | DisplayOrder | Кто создаёт | Примечание |
|---|---|---|---|
| `ScreenGui` (главный, из StarterGui, `ResetOnSpawn=false`, `ScreenInsets=DeviceSafeInsets`, 3105 потомков, 665 текстов) | 0 | место (.rbxl) | HUD, MainWindow, ServiceMenus, Backdrop, InventoryToast, Modules |
| `DOGROTS_LuckyArrivalScreen` / `DOGROTS_LuckyArrivalBanner` | 38 / 39 | `LuckyArrivalFX.client` | |
| `MiningGui` (NoTranslate, KeepFont) | 40 | `MiningClient.client:83` | оверлеи шахты |
| `KitWindows` / `KitModals` / `KitOverlay` | 60 / 62 / 95 | `Kit/Base.Layer` (лениво) | окна, модалки, тосты/тултипы |
| `CommunityServices` | 70 | `CommunityClient.client:18` | Shelter / Feedback, `Enabled` переключается |
| `MiningShop` | 70 | `MiningClient/Shop.luau:16` | магазин кирок, `Enabled` переключается |
| `MiningToast` | 80 | `MiningClient/Hud.luau:15` | |
| `DOGROTS_EventGameplay` | 90 | `WorldEventGameplayFX.client:29` | |
| `DOGROTS_NuclearPugGlow`, `DOGROTS_WrongDogVignette`, `DOGROTS_SecretScreen`, `DOGROTS_SecretMega`, `DOGROTS_SecretWhisper`, `DOGROTS_UnfinishedOutput`, `DOGROTS_EventCinema` | 93–96 | SecretArrivals/*, `WorldEventCataclysm.luau:171` | экранные VFX / кино |
| `MiningDiagnostics`, `DOGROTS_EventAdmin`, `DOGROTS_SecretAdmin` | 200 / 300 / 301 | отладочные панели | |
| Folder `DOGROTS_IncomePopups` (8 BillboardGui) | — | `EconomyVisuals.client:56` | пул «+$X» над собаками |
| BillboardGui `TutorialWorldMarker` | — | `OnboardingGuide.luau:94` | лежит прямо в PlayerGui |

Внутрь **главного** ScreenGui скрипты во время игры добавляют:
* `DistrictGuide` (Frame с `MapOverlay`, BillboardGui `Waypoint`, кнопкой `ClearMarker`);
* `OnboardingGuide`, `WorldEventNotice`, `RewardMachineWorldPanel`, `Confirmation`, `RewardReveal`, `RewardMachineRewardToast`, `RewardMachineOddsOverlay`;
* в `HUD`: `ActiveSupplies` + `SupplyTooltip` (BuffHUD), `IncomeChip` (HUDStatsController), `OfflineEarningsNotice` (Menus), `SimpleSettings` (UITheme), `Quick*` плитки (UITheme.ApplyShell).

#### 2.2 Навигация — `Modules/GUIIntegration.luau`
* Модуль хранит одного владельца навигации `N.Owner`: `HUD`, `Page`, `Screen`, `Service`, `Kit`, `Reward`, `Map`, `Community` или `RewardMachineWorld`.
* `N.Acquire(owner,page)` (стр. 47–85) делает следующее:
  * прячет HUD (`gui.HUD.Visible = owner=='HUD'`), MainWindow, ServiceMenus и показывает Backdrop;
  * блокирует движение (`PlayerModule:GetControls():Disable()` и `ContextActionService` «PawpadMovement») и выключает промпты (`ProximityPromptService.Enabled=false` с запоминанием);
  * ставит атрибуты главного gui: `OpenMenu`, `MenuFamily`, `ModalOwnerCount`.
* Маршрутизация `N.OpenPage` (стр. 99–113, обёртка `dogScreens` на стр. 222–246):
  * `Dogs`/`DogDex` — Kit;
  * `Lab` — Kit (`LabScreen.Open`);
  * `Equipment` — Kit;
  * `Shop`/`Events` — Menus;
  * `Yard`/`Trade` — на десктопе статическая страница, а при `CompactMenus` экран Menus. Получается, **одна функция выглядит по-разному на ПК и телефоне** (стр. 104);
  * `Inventory` — статическая `InventoryPage`;
  * сервисы `Collector|Seller → ServiceMenus Seller`, `Upgrades|DogTraining|Estate|UpgradeTree → UpgradeTreeScreen`, `Kennels → ServiceMenus Kennels`;
  * всё остальное идёт в `N.OpenScreen` → `Menus:Mount`.
* `dispatch()` откладывает вызовы, пока `ready()` (стр. 21) не вернёт true: `screens and switchPage and serviceOpen and inventoryReward`. Значит, без `N.RegisterInventory` из `InventoryController` **очередь навигации не сбрасывается никогда**.
* Клавиши (стр. 196–206): `Esc` (`DismissDialog` / `Close`), `P` (MY YARD / закрыть), `B` (сумка). `M` (карта) обрабатывает `DistrictGuide.client`, геймпад `B` обрабатывает `Kit/Nav`. Подсказок по клавишам в интерфейсе нет: метка «P OPEN / CLOSE» лежит в Sidebar, а его прячет `ApplyStandalone`.
* При первом `require` модуль ещё и **перекрашивает весь GUI** (`Theme.ApplyShell(gui);Theme.ApplyStandalone(gui)`, стр. 9), запускает `BuffHUD` и `OnboardingGuide` (стр. 248–249). То есть модуль навигации — это одновременно стилизатор и стартер HUD.

#### 2.3 Оформление и текст во время игры
* **`UITheme.ApplyShell`** (стр. 427–579) удаляет и заново генерирует иконки, подписи и плитки HUD (`Quick*`). Он проходит по всем 2887 потомкам MainWindow (шрифт Fredoka, обводки) и вызывает `LayoutHUD` (стр. 59–146: две колонки плиток по безопасной зоне, `TouchReserve` под джойстик и прыжок).
* **`UITheme.ApplyStandalone`** (стр. 642–725) превращает MainWindow в отдельные окна: прячет Header и Sidebar, вешает `WindowChrome` на каждую страницу и подписывает `screen.DescendantAdded` так, что **любой новый GuiButton в главном gui получает `EnhanceButton`** (≈10 подключений: hover, press, градиент).
* Стили берутся **клонированием живых инстансов `YardPage`**: `cardTemplate=yard.LatestFoundCard.Main`, `headerTemplate=yard.YardHeader` в UITheme (стр. 7–11), плюс `ServiceUI.Build`. YardPage нельзя удалить, не переписав тему.
* Три глобальных «наблюдателя текста»:
  * `DOGROTS_AutoTranslateUI` (PlayerGui + **workspace**);
  * `DOGROTS_RU_ScreenPatch` (PlayerGui, не уважает `NoTranslate`);
  * `PlaceTypography` (workspace + PlayerGui, принудительный FredokaOne, если нет `KeepFont`).

#### 2.4 Kit (новое поколение)
* Модули: `Kit.luau`, `Kit/Theme` (токены), `Format`, `Layout` (брейкпоинты 700×560), `Lang` (`T(en,ru)`, Words), `Motion` (0.09–0.25 с, Reduced Motion только из `GuiService.ReducedMotionEnabled`), `Base` (Text/Icon/Press/Face/Layer/SafeArea), `Button`, `Controls` (Tabs, SearchBox, Chips, SortSelect), `Display` (теги, ProgressBar, StatRow, Countdown, EmptyState), `Feedback` (Toast, Tooltip, LongPress), `Modal` (Confirm, Alert, hold-to-confirm), `Virtual` (VirtualGrid/List), `Cards` (DogCard/ItemCard/CardGrid), `Preview` (кэш ViewportFrame, 2 штуки в кадр, полка на 48), `Window` (открытие 0.18 с, scale 0.94→1, Back-easing; на телефоне — полноэкранный sheet), `Nav` (связка с GUIIntegration: `Acquire('Kit',Key)`, обёртка `DismissDialog`, геймпад B).
* Данные: `Modules/Net.luau` хранит общий кэш `Snapshot` (maxAge 4 с), сигнал `Net.Changed` и `Net.OnPush(kind)` (RemoteEvent `DogEconomyPush`).

#### 2.5 Какие экраны на чём сделаны
| Экран | Поколение | Файл | Вход |
|---|---|---|---|
| MY DOGS, DOG DETAILS, сравнение | **Kit** | `Modules/DogsScreen.luau` (2280 строк) | плитка DOGS, `OpenPage('Dogs')` |
| DOG INDEX, DexEntry | **Kit** | `Modules/DogdexScreen.luau` | плитка INDEX |
| GENETICS LAB (+LabPicker) | **Kit** | `Modules/LabScreen.luau` (1869) | плитка LAB, терминал `GeneticsPrompt` |
| UPGRADE TREE | **Kit** | `Modules/UpgradeTreeScreen.luau` | Yard, мастерская, онбординг |
| Equipment «SHOP» (аксессуары/артефакты), CaseOpening, ArtifactPanel | **Kit** | `Modules/Equipment/*` | терминал UPGRADES в магазине, DogsScreen |
| BAG / INVENTORY | **(A) статика** | `MainWindow/.../InventoryPage` + `InventoryController.client` + `InventoryView` | плитка BAG, клавиша B |
| MY YARD (ПК) | (A) | `YardPage` + `YardPageController.client` | плитка MY YARD, P |
| TRADE — список игроков (ПК) | (A) | `TradePage` + `PawpadController` | плитка TRADE |
| Dogs/DogDex/Lab/Shop/Events/Discoveries static pages | (A) **мёртвые** (скрыты и не маршрутизируются, но стилизуются и биндятся) | `PawpadController.client` | — |
| Yard (телефон), Trade-сессия, Settings, Help, Extras, Layers, Loot, Upgrades-заглушка | (B) | `Modules/EconomyScreens.luau` | Menus |
| PAW MARKET (Shop) | (B) | `CommerceShopScreen.luau` | плитка SHOP |
| WORLD EVENTS | (B) | `EventsScreen.luau` | плитка EVENTS |
| Supplies, Luck, Offline earnings, YARD STYLES (Cosmetics), DOG STORAGE (витрина собак) | (B) | `SuppliesScreen`, `LuckScreen`, `OfflineEarningsScreen`, `PlotShopScreen`, `StorageScreen` | HUD-бусты, промпты двора |
| DOG-O-MATIC, DOG TOKENS | (B) | `RewardScreens.luau` | машина в мире |
| LUCKY BLOCK odds / pad | (B) | `LuckyBlockUI.luau` | `RewardPresentation` |
| Discoveries/Inspect/Collection/Marketplace/Records/Listing/CreateListing | (B) | `DiscoveryScreens.luau` | терминал MARKETPLACE, ссылки |
| SELL FINDS (Seller), ASSIGN DOG (Kennels), DIGGING LAYERS | ручные фреймы | `ServiceMenusController.client` + `ServiceMenus/ServiceUI` | промпт коллекционера, конура, Yard |
| DOG SHELTER, Feedback | отдельный ScreenGui | `CommunityClient.client` | промпты хаба |
| Магазин кирок, HUD шахты | отдельный ScreenGui | `MiningClient/*` | Mining Corner |
| Карта района, маркер | фрейм в главном gui | `DistrictGuide.client` | M, `NavigateDistrict` |
| Онбординг | фрейм в главном gui | `Modules/OnboardingGuide.luau` | автоматически |

### 3. Файлы и роли (ядро UI)
* `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — владелец навигации, маршрутизация, клавиши P/B/Esc, обработка `DogEconomyOpen`/`DogKennelOpen`/`RewardPresentation`.
* `.../Modules/UITheme.luau` (739 строк) — легаси-токены (`U.Colors`, `U.Rarity`, `U.Tiers`), билдеры (`U.Button/Panel/Text/Grid/Modal/Icon`), перекраска (`ApplyShell`, `ApplyStandalone`, `EnhanceButton`), `LayoutHUD` и `WatchHUD`, `WindowSpecs`/`WindowChrome`, `SafeArea`/`TouchReserve`, процедурные иконки `U.Icon`.
* `.../Modules/Menus.luau` — менеджер окон (B): `Fetch` раз в 5 с, `Render` с полной перестройкой, `Update` раз в 0.5 с (тикер `PawpadRuntime`), холостой опрос раз в 15 с ради кнопки «WHILE YOU WERE AWAY».
* `.../PawpadRuntime.client.luau` — создаёт `Menus`, Heartbeat-тикер 0.5 с, клиентские настройки (Motion → атрибут `ReducedMotion`, «World Event FX», PlayerList). **Ничего не сохраняется.**
* `.../PawpadController.client.luau` — привязки статических страниц (почти все мёртвые), `switch()`, экранная клавиатура поиска `SearchKeyboard`, кнопки PAWPAD/BAG/Close, `MenuNavigation`, кнопки `ViewMuseumEntry` для 100 карточек мёртвого DexGrid.
* `.../PawpadStatsController.client.luau` — Cash/Bones/Lv в шапке MainWindow (шапка скрыта, код фактически холостой).
* `.../HUD/HUDStatsController.client.luau` — уровень и XP, GlobalDig (виджет скрыт), `IncomeChip` («+$X/мин» и «FINDS FULL»).
* `.../HUD/MoneyWidget/MoneyController.client.luau` — кошелёк: плавный отсчёт и авторасширение.
* `.../MainWindow/.../InventoryPage/InventoryController.client.luau` (555) + `InventoryView.luau` (84) — сумка.
* `.../YardPage/YardPageController.client.luau` — MY YARD, 3D-превью двора.
* `.../ServiceMenusController.client.luau` + `ServiceMenus/ServiceUI.luau` — Seller, Kennels, Layers.
* `.../Modules/Kit/*` + `Kit.luau`, `Net.luau`, `PreviewRenderer.luau` — новый UI-кит.
* `.../Modules/BuffHUD.luau` — карточки активных бустов (Heartbeat 4 раза в секунду).
* `.../Modules/OnboardingGuide.luau` — 18-шаговая карточка и мировой маркер (цикл 0.5 с).
* `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau` (2686 строк) — RU-перевод: 1908 точных пар, 108 паттернов, 441 фраза + `ReplicatedStorage/Localization/*.luau` (10 модулей, 1146 строк).
* `.../DOGROTS_RU_ScreenPatch.client.luau` — точечный RU-патч Лаборатории, слоёв и офлайн-награды (дублирует словари).
* `.../PlaceTypography.client.luau` — шрифт Fredoka всем текстам.
* `.../KitDemo.client.luau` — витрина кита, только в Studio (атрибут workspace `KitDemo`, клавиша K).
* `.../LocalScript.client.luau` — **отладочный мусор** (см. баги).
* `.../DistrictGuide.client.luau` — карта района и маркер-«лейбл» (основа для F1).
* `src/ReplicatedStorage/GameIcons.luau` — реестр загруженных иконок (22 id) и preload. `AudioSource.luau`, `LocalAudioManifest.luau` — разрешение аудио (локальные файлы только в Studio при GameId==0). `RewardAudio`, `WorldSound`, `WorldSoundConfig`, `Mining/MiningAudio`, `Lucky/LuckyAudio`, `LabAudioConfig` — звуковые рецепты на встроенных `rbxasset://sounds/*`.

### 4. HUD: каждая кнопка (после `ApplyShell`)
| Элемент | Инстанс | Что делает |
|---|---|---|
| DOGS | `HUD.QuickDogs.Open` (`CandyPage=Dogs`) | `N.OpenPage('Dogs')` → `DogsScreen` (Kit) |
| BAG + «x / y» | `HUD.InventoryWidget.InventoryButton` (+`Capacity`, текст пишет `InventoryController.hud()`) | `OpenPage('Inventory')` → статическая `InventoryPage` |
| MY YARD | `HUD.PawpadWidget.PawpadButton` | `OpenPage('Yard')` → YardPage (ПК) или Menus Yard (телефон) |
| SHOP | `HUD.QuickShop.Open` | Menus → `CommerceShopScreen` (PAW MARKET) |
| INDEX | `HUD.QuickDogDex.Open` | `DogdexScreen` (Kit) |
| LAB | `HUD.QuickLab.Open` | `LabScreen` (Kit; вне терминала показывает сплэш «SHOW THE WAY») |
| TRADE | `HUD.QuickTrade.Open` | ПК: статическая TradePage (список игроков → `TradeRequest`), телефон: Menus Trade |
| EVENTS | `HUD.QuickEvents.Open` | Menus → `EventsScreen` |
| SETTINGS | `HUD.SimpleSettings.Open` | Menus Settings: Motion, Leaderboard, World Event FX, HOW TO PLAY. **Состояние переключателей не показывается** (`EconomyScreens:215` подписывает кнопку просто ключом) |
| «$X» кошелёк | `MoneyWidget.Main.Amount` | только отображение |
| LV / XP | `XPWidget` | только текст (полоса скрыта) |
| «+$X/мин» | `HUD.IncomeChip.Rate` | `OpenPage('Yard')` |
| «FINDS FULL · SELL» | `HUD.IncomeChip.FindsFull` | `N.Notify(SellTip)` + `N.Navigate('Your yard')` |
| WHILE YOU WERE AWAY | `HUD.OfflineEarningsNotice` | `OpenScreen('OfflineEarnings')` |
| Карточки бустов | `HUD.ActiveSupplies.*.Details` | тултип или `OpenScreen('Luck')` |
| CLEAR MARKER | `ScreenGui.DistrictGuide.ClearMarker` | убирает маркер |
| Онбординг: действие / SKIP / «-» | `ScreenGui.OnboardingGuide.Action/Skip/Collapse` | шаг туториала (`Tutorial` remote) / навигация |
| Скрытый `GlobalDigWidget` | `ApplyStandalone` ставит `Visible=false` | HUDStatsController продолжает его обновлять |

Восемь плиток 88×92 px стоят в две колонки по краям экрана (`U.QuickTiles`; Dogs, BAG, Yard, Shop слева; Index, Lab, Trade, Events справа). Плюс SETTINGS, кошелёк, XP, income, бусты, онбординг, уведомления. Бейджей «что-то новое / можно забрать» на плитках нет.

### 5. Инвентарь: каждая кнопка и почему «много кнопок, ничего не понятно»
Структура (дамп `InventoryPage`, 308 потомков, 17 GuiButton) и обработчики в `InventoryController`:
| Контрол | Что делает |
|---|---|
| WindowChrome «MY BAG / Lucky blocks and discoveries» + X | заголовок окна (`UITheme.WindowChrome`) + закрыть |
| `InventoryHeader.Title` «INVENTORY» + `Capacity` | **второй** заголовок + «37 / 50» |
| Tabs: FINDS / COLLECTION / LUCKY BLOCKS | режим: сбрасывает фильтры, сортировку, выбор |
| `Browser.Search` (TextBox) | поиск, debounce 0.15 с |
| `Favorites` «ALL FINDS ↔ FAVORITES» | переключатель (только FINDS) |
| `MoreFilters` «FILTERS» | показывается только на коротком экране, разворачивает панель |
| `Filters.Depth` «ALL DEPTHS» | **цикл** из 5 значений |
| `Filters.Class` «ALL CLASSES»/«ALL TIERS» | цикл (5 классов / тиры блоков) |
| `Filters.Weight` «ALL WEIGHTS» | цикл из **10** тиров веса |
| `Filters.Mutation` «ALL MUTATIONS» | цикл из 5 мутаций |
| `Filters.Sort` «NEWEST» | цикл NEWEST/NAME/HEAVIEST/RAREST/DEPTH |
| Карточка (`Entry_<key>.Main`) | выбрать |
| `CandyStart` «GO TO MY YARD» | пустое состояние → `N.Navigate('Your yard')` |
| `Details.Actions.Favorite` | у находки FAVORITE/UNFAVORITE (`ItemFavorite`), у блока **PLACE / YOUR YARD / OPEN AT PAD** (навигация во двор) |
| `Details.Actions.Lock` | у находки скрыт (сервер отключил `ItemLock`), у блока **CHANCES** → `LuckyOdds` |
| `Details.Actions.Sell` «SELL TO MILO» | `BulkSell{Uids={uid}}` |
| `Details.Actions.Market` «LIST ON MARKET» | ConfirmModal с голым TextBox цены → `List{Kind='Item',Mode='BuyNow'}` |
| ConfirmModal CANCEL / CONFIRM (RETRY) | модалка |
| `MobileBagBack` «BACK TO BAG» | телефон: из деталей обратно в сетку (`UITheme.ApplyStandalone:681`) |

Почему игроку непонятно (конкретно, по коду):
1. **На десктопе одновременно видно 15–17 контролов**: 2 заголовка, 3 вкладки, поиск, избранное, 5 фильтров, сортировка, 2–4 действия и закрыть. Все стилизованы одинаково (`EnhanceButton` красит всё одной голубой «конфетой»), поэтому фильтр не отличить от переключателя или действия.
2. **Фильтры — кнопки-циклы** (`InventoryController:489–498`, `cycle()`). Список значений не виден, каждое нажатие переключает на следующее значение. Тиров веса 10: чтобы дойти до «WORLD RECORD», нужно 10 тапов. Кнопки «сбросить фильтры» нет. Подписи вроде «ALL MUTATIONS» ужаты `TextScaled` до 14 px, а по-русски они длиннее.
3. **Карточка не показывает главного: редкость и цену.** Цвет полосы берётся из класса (`classColors`, стр. 57), а 66 из 108 предметов имеют класс `Artifact`, то есть почти все карточки одинаково фиолетовые. Ключей `Junk`/`Organic` в данных нет, `World Find` отсутствует. Текст «0.0412 kg · NORMAL» показывает «NORMAL» почти на каждой карточке. Редкость (`ItemValuation` / `ValueBreakdown.Rarity`) нигде не выводится.
4. **Панель деталей — стена текста** из 8 строк («Class:», «Weight tier:», «Chance: 1 / 12.3K», «Origin:», «NPC value: … Cash»).
5. **Одни и те же кнопки меняют смысл.** Слот Favorite у блока означает «PLACE / OPEN AT PAD», слот Lock означает «CHANCES». Блокировка предметов существует как кнопка, но на сервере выключена (`ItemRules:204`, `I.Normalize` стирает `Locked`).
6. **SELL TO MILO не работает вдали от коллекционера.** `YardCommerce.BulkSell` вызывает `S.Visit`, а тот требует стоять в `SellInteractionZone` не дальше 9 studs (`PlotInteractionAccess`). Игрок жмёт кнопку и получает ошибку «Visit the collector in your own yard».
7. **Одни и те же предметы в 4–6 разных интерфейсах** с разными фильтрами и словами: InventoryPage (FINDS/COLLECTION), `DiscoveryScreens` (Discoveries/Inspect/Collection/Records — «Sell with Milo in your yard»), ServiceMenus Seller (мультивыбор), мёртвые `DiscoveriesPage` и `CollectorScreen`, `EconomyScreens` Loot. Слова тоже разные: «BAG», «MY BAG», «INVENTORY», «DISCOVERIES», «YOUR FINDS». При полной сумке `RewardScreens:297` «MY ITEMS» ведёт в `DiscoveryScreens Collection`, а не в сумку.
8. Сумка не единая: снаряжение (артефакты и аксессуары) лежит в отдельной «сумке» окна Equipment, а оно ещё и называется «SHOP», как PAW MARKET.
9. Отклик серый: статус-строка внизу и `InventoryToast`, звуков нет, анимаций открытия у статической страницы нет (`main.Visible=true`).
10. Производительность: на каждый предмет создаётся карточка (клон шаблона, 19 потомков) без виртуализации, до `HardCap=1000` (≈19 тыс. инстансов). Snapshot опрашивается раз в 6 с.

### 6. Данные (что UI читает и пишет)
UI сам **ничего не хранит** в DataStore. Все изменения идут через серверные действия `DogEconomyRequest`.
* `p.Items[uid]` (создаётся в `ItemRules.Mint`, стр. 179–200). Поля: `ItemUid, ItemId, DisplayName, Depth, Class, SetId, BaseDropChance, EffectiveDropChance, BaseWeightKg, WeightKg, WeightMultiplier, WeightTier, TierIndex, WeightProfile, WeightTierChance, Mutation, MutationChance, CombinedOdds, FoundAt, FoundByUserId, OriginalFinderUserId, OwnerUserId, SellValue, ValueBreakdown{Version,Rarity,Factors,…}, ValueVersion, Tradeable, RecordAtCreation, Favorite, SourceDogUid, FirstFind, SellBonus, IncomeMult?, EventTag?, PaidRandom?`.
  * UI пишет только `Favorite` (`ItemFavorite`).
  * `Locked` стирается в `I.Normalize`.
* `p.Collection[itemId]=true`, `p.DiscoveryFeed` (20 последних), `p.Stats` (Heaviest/MostValuable/Rarest/BestShowcase*), `p.HeavyCollection`, `p.ItemSets`.
* `p.OwnedBlocks[uid]{Tier,State,Slot,ReadyAt,PurchasedAt,Quantity}`, `p.LuckyCredits[tier]`.
* `p.Dogs[uid].Favorite/Locked` (`DogFavorite`/`DogLock`), `p.DexFavorites`, `p.DexClaims`, `p.DisplayDogs[slot]=DogUid` (`DisplayDog`, StorageScreen).
* `p.Cosmetics` (в том числе титулы Dogdex `Dex10…Dex100` и `Discovery:<set>`), `p.EquippedCosmetic`, `p.PlotSkins`/`p.EquippedPlotSkin`.
* `p.Onboarding` + атрибуты `TutorialStep/TutorialActive/TutorialStatus/TutorialVersion` (действие `Tutorial`).
* Ёмкость сумки = `min(1000, 50 + 25·p.Upgrades.Storage + бонусы)` (`ItemRules.Capacity`).
* Атрибуты игрока, которые читает HUD/UI (ставит `Runtime`): `EconomyReady, Level, XP, XPRequired, ItemCount, ItemCapacity, ItemFull, InventoryRevision, OwnedBlockCount, AvailableBlockCount, ActiveBlockCount, IncomePerMinute, GlobalDigTotal, CurrentLayer, LayerName, YardId, YardLevel, DogCapacity, LatestFoundItem, LuckExpires_<tier>, SupplyExpires_<key>, PendingCash, EventTokens, DogDexCount`. Плюс `leaderstats.Coins` и `player.Bones`.
* **Клиентские настройки не сохраняются:** атрибуты `ReducedMotion`, `WorldEventFX`, `LowFX` и видимость PlayerList сбрасываются при каждом заходе (`PawpadRuntime:6–16`).

### 7. Сеть (remote-поверхность UI)
| Remote | Направление | Использование в UI |
|---|---|---|
| `DogEconomyRequest` (RF) | C→S | `Snapshot`, `ItemFavorite`, `BulkSell`, `List`, `MarketQuery`, `Assign`, `Remove`, `DogFavorite`, `DogLock`, `DexClaim`, `DexFavorite`, `DisplayDog`, `Layer`, `SellLoot`, `Trade{Action=Offer/Ready/Confirm/Accept}`, `TradeRequest`, `TradeCancel`, `Tutorial`, `DistrictTravel`, `EventClaim` и др.; ответ `ok, result` (+`StatePatch`/`StateSnapshot`), третий аргумент — request id (идемпотентность) |
| `DogEconomyOpen` (RE) | S→C | `(page, message)` → `N.OpenPage`/`OpenScreen` (промпты двора, магазинов, лаборатории, приглашение в трейд) |
| `DogKennelOpen` (RE) | S→C | `(slot, yardId)` → ServiceMenus Kennels |
| `DogEconomyPush` (RE) | S→C | `(kind, data)` → `Net.OnPush` (новые экраны) |
| `RewardRequest` (RF) / `RewardPresentation` (RE) | C→S / S→C | DOG-O-MATIC, Lucky Blocks, `PromptFeedback`, `LuckyOffer`, `PadSelector`, `OpenedBlock`, `Cue` |
| `DiscoveryReveal` (RE) | S→C | триггер обновления сумки и YardPage |
| `DogKennelRequest` (RF) | C→S | ServiceMenus |
| `CommunityOpen`, `ShelterRequest`, `FeedbackRequest`, `CommunityFeedbackRequest` | | `CommunityClient` |
| BindableEvent в ScreenGui: `MenuNavigation` (Close/Service/Page), `NavigateDistrict(name)`, `ToggleDistrictMap` | клиент | навигация, маркер, карта |

**Опрос полного `Snapshot` клиентами** (сервер отдаёт глубокую копию профиля, до 1000 предметов с `ValueBreakdown`, и пересчитывает `IncomeModel`):
* `Menus.Update` в холостом режиме (HUD, меню закрыто) — **раз в 15 с у каждого игрока** (`Menus:205`), только ради кнопки офлайн-дохода;
* открытая страница Menus — раз в 5 с плюс полная перестройка;
* сумка — раз в 6 с плюс при каждом изменении атрибутов (троттлинг 1.5 с);
* YardPage — раз в 8 с;
* статические страницы Pawpad — раз в 8 с;
* ServiceMenus — раз в 5 с;
* Kit (`Net.Snapshot`) — общий кэш 4 с.

Серверный лимитер `Runtime.allow` даёт 8 токенов и восстанавливает 1.5 в секунду. Параллельные опросы конкурируют с настоящими действиями, отсюда «Please wait a moment».

### 8. Мировые объекты, от которых зависит UI
* `Workspace.DOGROTS_District.04_PlayerYards.<Yard_NN_*>` (атрибуты `OwnerUserId`, `YardId`) со следующими детьми:
  * `SellAnchor`/`SellInteractionZone`, `StorageAnchor`/`StorageInteractionZone`, `UpgradeAnchor`/`UpgradeInteractionZone` (промпты `YardInteraction` создаёт `YardCommerce.Start`);
  * `DigSlot_1..5` (`AssignedDogUid`, `Unlocked`);
  * `LuckyPad_1..3` (промпт `PlaceLuckyBlock`, атрибуты `LuckyBlockUid`/`LuckyBlockReady` — `InventoryController.padPrompts`);
  * `MiningCorner.{MiningPad, MiningPickaxeShop, MiningOreCore, MiningStrengthRack}` (онбординг);
  * `YardSpawn`, `DogStorage.DisplaySlots` (витрина собак).
  * Каждый двор — ≈1430 частей, 1237 из них видимые: YardPage клонирует их во ViewportFrame.
* `DOGROTS_District.03_DogLine.ActiveDogs` (`PromptFeedback`, `EconomyVisuals`), `KennelDogs`, `11_Shops.InteractionAnchors.Marketplace`, `05_MutationLab` (`LabAccess`), `NavigationAnchors` (через `MapRouting` в `DistrictGuide`).
* `ReplicatedStorage.DiscoveryModels` (108 моделей, 3225 частей) — превью находок; `MenuModels` (101 модель, 569 частей) — превью собак; `WorldEvents.State` (атрибуты `EventId/State/EndTimestamp`); `ServerLuckState`.
* `SoundService.DOGROTS_AUDIO` — в месте есть только SoundGroup `WorldEvents` и `Music`. Групп `UI`/`SFX`, которые ищут `RewardAudio`/`WorldSound`/`LabAudioConfig`, **нет**.
* `PlayerGui.TouchGui.JumpButton` — `UITheme.TouchReserve`.
* В статичном workspace 644 SurfaceGui (вывески), 801 текстовый объект, 5 BillboardGui (4 `LocationLabel` и `DistantPortalEmission`) и всего 3 ProximityPrompt. Остальные промпты и билборды создают скрипты во время игры: `DogBillboard`, `SleepLabel`, `KingLabel`, `BlockTimer`, `OreLabel`, `MiningPopup`, `EconomyCosmetic`, `LuckyDogNameplate` и др.

### 9. Производительность
* **AutoTranslate** (`roots={gui, workspace}`, стр. 16):
  * всем игрокам, **включая англоязычных**, на каждый TextLabel/TextButton/TextBox в PlayerGui и workspace вешается `GetPropertyChangedSignal` и запись в `originals`: старт — около 665 + 801 объектов плюс всё, что создаётся потом;
  * `workspace.DescendantAdded` срабатывает на каждый подгруженный стримингом инстанс (есть ещё два таких же слушателя: PlaceTypography и RU-патч только по PlayerGui);
  * для RU каждая смена текста проходит 108 паттернов `gsub` и до 441 поиска фраз;
  * `cache[source]=source` (стр. 2545) без ограничения растёт на динамических строках с латиницей (таймеры, счётчики) — медленная утечка за долгую сессию.
  * Сам словарь — около 2.6 тыс. строк кода в одном LocalScript.
  * Вывод: утечка и стоимость умеренные, а не катастрофа. Но это архитектурный долг, и его нужно сужать.
* **Menus**: на каждый fetch (5 с) `ClearAllChildren` и пересоздание всех кнопок. Каждая кнопка получает ~10 подключений `EnhanceButton` и 3 текстовых наблюдателя, ViewportFrame собак/предметов клонируются заново. Плюс `canvas:GetDescendants()` раз в 0.5 с (`Menus:211`).
* **YardPage**: клон ~1237 видимых частей двора в ViewportFrame раз в 20 с, пока страница открыта (`YardPageController:59–84,121`).
* **Сумка**: не виртуализирована (см. п. 5), `padPrompts()` раз в 0.5 с **всегда**, даже при закрытой сумке (стр. 539–548).
* **Мёртвые статические страницы**: ≈2257 инстансов и 544 текстовых объекта (DogDexPage — 1512), их на старте стилизуют, переводят и анимируют (`PawpadController:115` вешает `animate` на все TextButton).
* BuffHUD — Heartbeat-раскладка 4 раза в секунду, OnboardingGuide — `render` раз в 0.5 с, PlotPrompts/LabPrompt — Heartbeat около 7 раз в секунду (вне UI-кита).
* Хорошо сделано: `Kit.VirtualGrid` (инстансов по числу видимых ячеек, проверено на 500 карточках), кэш `Kit.Preview`, отсутствие idle-циклов у кита, `Net` с общим кэшем.

### 10. Баги и техдолг (найдено)
1. **`StarterPlayerScripts/LocalScript.client.luau`** — отладочный скрипт. Он печатает локаль, а через 3 с у **каждого** игрока переводит все тексты «DOGS» в PlayerGui ru-ru транслятором (`GetTranslatorForLocaleAsync('ru-ru')` без pcall). Если в облачной таблице локализации есть запись «DOGS», англоязычные увидят «СОБАКИ» на плитке. Есть ли такая запись в облачной таблице, по файлу места проверить нельзя. Скрипт нужно удалить.
2. **Продажа избранного.** `YardCommerce.BulkSell`/`CanSell` не учитывают `Favorite`. ServiceMenus «SELECT ALL» (`ServiceMenusController:150–155`) выбирает все находки, в том числе ★, а «SELL SELECTED» (стр. 268–275) продаёт без подтверждения. `CollectorScreen` «SELL ALL FINDS» тоже без подтверждения (сейчас недостижим: `Collector` переадресован на Seller).
3. `InventoryController` «SELL TO MILO» доступна везде, а сервер требует зону коллекционера (≤9 studs).
4. В `classColors` неверные ключи классов, редкость не показывается (п. 5.3).
5. **Критичная связка:** `GUIIntegration.ready()` требует `N.RegisterInventory` от `InventoryController`. Без него (удаление или переименование старой сумки) `dispatch` копит вызовы вечно, и **никакое меню не откроется**. `N.Notify` (глобальный тост) тоже живёт в `InventoryController`. Подпись ёмкости на плитке BAG пишет тоже он.
6. `EconomyScreens:185` вызывает несуществующую `Screens.Lab` (сейчас недостижимо из-за раннего `return` для Lab).
7. Kit `Motion.Reduced()` не учитывает внутриигровую настройку Motion (атрибут `ReducedMotion`), только `GuiService.ReducedMotionEnabled`. Настройки не сохраняются и не показывают своё состояние.
8. Звуковые группы: `RewardAudio`/`WorldSound` ищут `DOGROTS_AUDIO.UI`, `LabAudioConfig` ищет `SFX`. Их нет, звуки играют без группы, общей громкости UI нет.
9. Палитры расходятся:
   * `EventsScreen.rarityColors` (Common зелёный, Rare фиолетовый, Secret красный);
   * `PawpadController.rarityColors`;
   * `EconomyVisuals.colors` вариантов (Corrupted фиолетовый, Glitched бирюзовый) против `Kit.Theme.Variant` (Corrupted красный, Glitched пурпурный);
   * `InventoryController.classColors`.
10. Одна функция — два интерфейса: Trade/Yard на ПК и телефоне (`GUIIntegration:104`). `DogEconomyOpen 'Trade'` всегда идёт в Menus.
11. Мёртвый код: статические DogsPage, DogDexPage, LabPage, ShopPage, EventsPage, DiscoveriesPage; ветки `PawpadController` renderDogs/renderDex/renderLab/renderDiscoveries/ShopPage; фолбэк `workspace:GetDescendants()` в `showPreview` (стр. 171); `PawpadStatsController` (шапка скрыта); `CollectorScreen`.
12. Захардкоженные цены и тексты: онбординг, карточки 7 и 9 («Wooden Pickaxe (600 Coins)», «7 pickaxes, 7 weights, 12 ores»), продублированные точными ключами в AutoTranslate (стр. 149, 156). При смене баланса (F11) RU-перевод тихо сломается.
13. Клавиши P/B/M не видны в интерфейсе. Два окна называются «SHOP». В сумке два заголовка.
14. Модуль навигации делает побочные действия при `require`: перекраска, BuffHUD, Onboarding. Стили берутся клонированием YardPage (`UITheme:7–11`, `ServiceUI.Build`).
15. RU_ScreenPatch не проверяет `NoTranslate` и дублирует словари AutoTranslate.

### 11. Звуки и иконки: что есть
* **Звук.**
  * Загруженные ассеты есть только у музыки: 14 лупов в `WorldEvents/AudioAssetIds.luau`.
  * `WorldSoundConfig.Cues.Sell.Id=0`. В `MiningAudio`/`LuckyAudio`/`LabAudioConfig` все `AssetIds=0`; они собирают звуки из встроенных `rbxasset://sounds/volume_slider.ogg`, `collide.wav`, `electronicpingshort.wav`, `swordslash.wav`, `action_jump_land.mp3` с эффектами. Есть готовые рецепты `Click`, `Buy` (аккорд), `Deny`, `Whoosh`.
  * `LocalAudioManifest` — локальные файлы только для Studio (`AudioSource.Resolve` при `GameId==0`), в опубликованной игре не работают.
  * **Ни одна кнопка, окно, вкладка или тост UI звука не издаёт.**
* **Иконки.**
  * `UITheme.U.Assets` — 8 картинок плиток HUD (продублированы в `Kit.Theme.Icons`).
  * `GameIcons.Assets` — 22 картинки: Bones, Coins, Dig, Luck, Records, Settings, Star, RewardMachine/Casino, MoneyPocket/Chest/Vault, Ticket*, StorageCrate, EnergySnack, LuckyTreat, RareBlock, Starter*; плюс алиасы и preload.
  * Фолбэк — процедурные глифы из Frame в `UITheme.U.Icon`. `Kit.Icon` резолвит через `GameIcons`.
  * **Нет иконок** для: редкостей, мутаций, глубин, классов предметов, действий (продать, ★, выставить, обмен, замок, глаз/скрыть, маршрут), титулов.

### 12. Что можно улучшить поверх текущей системы
* Удалить `LocalScript.client.luau`. Учитывать атрибут `ReducedMotion` в `Kit.Motion.Reduced()`. Показывать состояние переключателей в Settings.
* Добавить `SoundService.DOGROTS_AUDIO.UI` (SoundGroup) и модуль `UISound`. Подключить его в 3 места кита (`Base.Press` → клик, `Window.Open/Close`, `Feedback.Toast`) и в `UITheme.EnhanceButton` — звуки появятся почти везде сразу.
* Бейджи на плитках HUD: новые находки, награды Dex, готовый Lucky-блок. Данные уже есть в атрибутах.
* В старой сумке: показывать редкость (`ValueBreakdown.Rarity`) и цену (`SellValue`) на карточке, скрывать «NORMAL», кнопку SELL показывать только в зоне коллекционера (`PlotInteractionAccess.CanUse` на клиенте), остановить `padPrompts` при скрытой странице. Это временный пластырь.
* Защитить ★ от массовой продажи на сервере (`YardCommerce.BulkSell`: пропускать `Favorite`, если нет явного флага), а в Seller добавить `Kit.Confirm`.
* Убрать холостой опрос `Menus` (15 с): получать `OfflineEarnings` через `DogEconomyPush` или атрибут `PendingCash` (он уже ставится).
* YardPage: одноразовое превью или статичная картинка вместо клона 1237 частей раз в 20 с.
* Сузить AutoTranslate: не сканировать workspace целиком (только SurfaceGui/BillboardGui вывесок), не кэшировать строки с цифрами, не подключаться у англоязычных игроков. Перенести RU_ScreenPatch в `Localization/*.luau`.

### 13. Что требует аккуратного рефакторинга
* **Вывод из эксплуатации статической `InventoryPage`.** Сначала перенести в новый модуль `N.RegisterInventory` (тосты `N.Notify`) и запись ёмкости HUD. Затем снять привязки в `UITheme.ApplyShell`/`ApplyStandalone`/`AttachNavigation` (`CandyStart`, `MobileBagBack`, стилизация фильтров).
* **Удаление мёртвых статических страниц.** Нужно убрать индексацию в `UITheme` (DogsPage.CandyEmpty, ShopPage), в `PawpadController` (весь блок привязок, SearchKeyboard клонирует `DogsPage.Sort`/`DogCount`) и в `ServiceUI`. YardPage оставить до переписывания темы: это шаблон стилей.
* **Слияние трёх поколений UI в Kit.** GUIIntegration остаётся владельцем навигации, маршруты переключаются по одному через обёртку как `dogScreens`. Ключ окна = имя страницы (`Inventory`, `Trade`, `Shop`, `Events`), чтобы работали клавиша B, атрибут `OpenMenu`, проверки в `Mining`/`LuckyReel`/`Onboarding`.
* **Единые токены.** Сейчас `UITheme.U.Colors`, `Kit.Theme` и `LabConfig.Colors` синхронизируются тестом `tests/uikit.luau`. Нужно сделать `Kit.Theme` источником, а `UITheme` — читающим.
* **Локализация.** Переход с «переводчика всего подряд» на `Kit.T`/словари по фичам с `NoTranslate`. Любое изменение английской строки ломает точный RU-ключ, поэтому нужен тест покрытия, как у кита.
* **Единый слой видимости (F9)** поверх всех ScreenGui и Billboard, с учётом скриптов, которые сами переключают `Enabled`/`Visible`.

### 14. Предлагаемый редизайн инвентаря
Новый Kit-модуль `Modules/Inventory/InventoryScreen.luau`, `Kit.Window{Key='Inventory'}`. Маршрут через `GUIIntegration` (обёртка, как `dogScreens`), клавиша B и плитка BAG работают без изменений.
```
┌ 🎒 МОЯ СУМКА ─────────── 37/50 ▓▓▓▓▓▓▓░░ [ПРОДАТЬ ⇢] ✕ ┐
│ [🎒 НАХОДКИ 37] [🍀 БЛОКИ 2] [📖 КОЛЛЕКЦИЯ 41/108]         │
│ 🔍 Поиск…  ● ● ● ● ● ●  [⚙ Фильтры·2] [↓ Ценность] [★] [☑] │
│ ┌────┐┌────┐┌────┐┌────┐┌────┐ ┃ ┌──────────────────────┐ │
│ │ 3D ││ 3D ││ 3D ││ 3D ││ 3D │ ┃ │      [ большое 3D ]   │ │
│ │Имя ││    ││ ★  ││NEW ││    │ ┃ │ Золотой самородок     │ │
│ │$12K││$800││$3K ││$40 ││$9  │ ┃ │ [ЛЕГЕНДАРНОЕ][GOLDEN] │ │
│ └────┘└────┘└────┘└────┘└────┘ ┃ │ 💰12 400 ⚖3.2кг 🎲1/40K│ │
│  … (VirtualGrid, цвет рамки =  ┃ │ [ ПРОДАТЬ $12 400 ]   │ │
│     редкость)                   ┃ │ [★] [⇄ Рынок] [🏆 Витрина]│ │
└─────────────────────────────────┸─┴──────────────────────┘
Режим ☑: «Выбрано 12 · 💰45 600  [Все показанные, кроме ★] [ПРОДАТЬ]» → Kit.Confirm (удержание, если есть Epic+)
Телефон: сетка на весь экран, детали — нижний лист (Stack-окно), действия — крупные кнопки 48 px.
```
* **Вкладки** (иконка + короткое слово + счётчик): НАХОДКИ / БЛОКИ / КОЛЛЕКЦИЯ. Опционально СНАРЯЖЕНИЕ как ярлык на вкладку сумки `EquipmentScreen`.
* **Фильтры.**
  * Редкость — цветные чипы (`Kit.Chips` Multi) прямо в тулбаре.
  * Глубина, мутация, тир веса — в popup-листе «Фильтры» (`Kit.Overlay.Popup`) с чипами, счётчиком активных фильтров и «Сбросить».
  * Сортировка — `Kit.SortSelect` (Новые / Ценность / Редкость / Вес / Имя, с направлением).
  * ★ — чип-переключатель.
  * Никаких циклов.
* **Карточка** (`Kit.ItemCard`): 3D-превью (`Kit.Preview` 'Item'), имя в одну строку, рамка и тег по **редкости**, тег мутации только если она не NORMAL, чип цены (`Kit.Format.Short(SellValue)`), ★, «NEW» (`FoundAt` > времени последнего открытия, локально или в новом поле), «🏆», если стоит на витрине (F3).
* **Детали**: максимум 3 StatRow (Цена, Вес, Шанс «1 из N»), строка «глубина · класс» мелко, описание. **Одна главная контекстная кнопка**:
  * в зоне коллекционера — «ПРОДАТЬ $X»;
  * вне её — «К КОЛЛЕКЦИОНЕРУ ⇢» (`N.Navigate('Your yard')`, а с F1 — реальный маршрут).
  * Вторичные действия — иконки (★, Рынок через `Kit.Modal` с ценой, комиссией 1% и итогом, Витрина).
* **Массовая продажа**: режим ☑ по образцу `EquipmentScreen` (SelectShown/Salvage/Cancel). «Все показанные» исключает ★. Подтверждение — `Kit.Confirm` с карточками.
  * Тот же экран открывается промптом коллекционера в режиме «продажа» и заменяет ServiceMenus Seller.
* **Блоки**: карточки тиров; действия «ПОСТАВИТЬ НА ПАД ⇢» и «ШАНСЫ» (существующие `N.Navigate`/`OpenScreen('LuckyOdds')`). Таймеры через `Kit.Countdown`, без цикла 0.5 с.
* **Коллекция**: сетка 108 предметов секциями по 5 глубинам с прогресс-барами; ненайденные показаны силуэтами (`Silhouette=true`).
* **Данные**: `Net.Snapshot` + обновление по `InventoryRevision`/`ItemCount` (debounce), `StatePatch` после продажи. Регулярного опроса нет.
* **Сервер**:
  * `BulkSell` — пропускать ★, принимать `{Uids, IncludeFavorites?}` (расширить `ValidBulkArgs`);
  * экспорт `ItemValuation.Rarity(def)` (или использовать `ValueBreakdown.Rarity`);
  * необязательное поле `p.InventorySeenAt`.
  * Всё аддитивно, старые сохранения совместимы.

### 15. Общий план UI overhaul (F2)
* **Токены** (`Kit/Theme` как единственный источник; UITheme читает из него):
  * отступы `Space={4,8,12,16,24,32}`;
  * радиусы (уже есть);
  * высота элементов (кнопка 44/48 на касании, 36 на ПК);
  * шкала текста (Title 30/23, Heading 21/18, Body 17/15, Small 14/13 — уже есть);
  * `IconSize={20,28,40,64}`;
  * `Elevation` (тень и прозрачность);
  * единые палитры редкостей, вариантов и мутаций; убрать локальные копии в EventsScreen, PawpadController, EconomyVisuals, InventoryController;
  * слои `Layer`.
* **Движение**: открытие и закрытие любого окна через `Kit.Window` (0.18/0.14 с). Hover 1.03, press 0.96 (одна реализация `Base.Press`; `EnhanceButton` и `PawpadController.animate` удалить по мере миграции). Переход вкладок — slide 0.12 с. Тосты въезжают сверху. Плитки HUD — «пружина» при появлении бейджа. Всё через `Kit.Motion` с учётом обоих Reduced Motion.
* **Звук** — новый `ReplicatedStorage/UISound.luau`, SoundGroup `DOGROTS_AUDIO.UI`, троттлинг, лимит одновременных звуков (как `MiningAudio.shot`), `AssetIds` под загрузку владельцем, громкость в Settings. Встроенные фолбэки (рецепты уже есть в `MiningAudio`):

  | Сигнал | Встроенный фолбэк |
  |---|---|
  | Hover | `volume_slider.ogg` ×1.6, громкость 0.04 |
  | Click | `MiningAudio.CUES.Click` |
  | Open / Close | Whoosh/ping |
  | Tab | tick |
  | Toggle | tick |
  | Success / Buy | аккорд `Buy` |
  | Error | `Deny` |
  | Reward / Rare | `LuckyAudio.Reveal` |
* **Иконки**: расширить `GameIcons` ключами Rarity*, Mutation*, Depth1..5, Sell, Favorite, Market, Showcase, Route, Eye, Title, Trade, Filter, Sort. Лучше одним загруженным атласом (`ImageRectOffset/Size`, поле `Rect` в реестре). `Kit.Icon(key)` уже резолвит через `GameIcons`.
* **Раскладка HUD** — сохранить `UITheme.LayoutHUD`/`SafeArea`/`TouchReserve`, но перекомпоновать:
  ```
  [Lv◔ 12] $1,234,567  +$3.2K/мин  🦴340        [баннер события / уведомления]        [⚙][👁]
  [🐶 DOGS]                                                                          [⇄ TRADE]
  [🎒 BAG•3]                                                                         [🏆 EVENTS]
  [🛒 SHOP]                                                                          [🗺 ROUTE]
  [📖 INDEX•]                                                                        [⋯ ЕЩЁ]
  [🧪 LAB]                               [контекст: шахта / онбординг]               [бусты ▮▮▮]
  ```
  * Плитки 64–72 px с бейджами. Валюта — сверху слева (сейчас снизу).
  * Одна «полоса уведомлений» сверху по центру для WorldEventNotice, Offline, InventoryToast и Kit.Toast.
  * На телефоне не больше 4 плиток в колонке, остальное в «⋯».
  * Геймпад: группы выбора (`GuiService:AddSelectionParent`), подсказки кнопок (Y = BAG, X = DOGS…).
* **Порядок миграции**:
  1. Фундамент: токены, `UISound`, иконки, Motion, сохранение Settings.
  2. HUD.
  3. Сумка.
  4. Shop / Events / Settings.
  5. Trade (F6).
  6. Yard.
  7. Cosmetics (F8) / Storage+Showcase (F3).
  8. Seller / Kennels / Layers.
  9. LuckyOdds/Pad, Discoveries/Marketplace/Records.
  10. Удаление мёртвых страниц, сужение AutoTranslate.
* **Настройки** сохранять новым необязательным полем `p.Settings` (Motion, Sounds, Music, WorldEventFX, HideHint) через действие `SaveSettings` с белым списком ключей.

### 16. План F9 «Скрыть UI»
* Новый клиентский модуль `Modules/UIVisibility.luau`. Его запускает GUIIntegration (не при `require`, а явным `Start`). API: `Hide()`, `Show()`, `Toggle()`, `IsHidden()`, `Changed`. Состояние публикуется атрибутом `player:SetAttribute('UIHidden')` и атрибутом главного gui.
* **Вход**: клавиша **H** (свободна; F9 занята консолью Roblox), кнопка «👁» рядом с SETTINGS, пункт в Settings. Геймпад — `DPadUp` (проверить конфликты в Studio).
* **Анимация скрытия** (0.22 с, `Kit.Motion`): плитки `U.QuickTiles` уезжают за левый и правый края, счётчики — вниз, баннеры — вверх, бусты — вправо. Только после этого — `Enabled=false`. `LayoutHUD` во время скрытия не переставляет. Появление — в обратном порядке, Back-Out, со stagger 20 мс.
* **Что скрывать**:
  1. **Все ScreenGui в PlayerGui**, в том числе `KitWindows/Modals/Overlay`, `MiningGui`, `MiningShop`, `CommunityServices`, `MiningToast`, баннеры Lucky и созданные позже (`PlayerGui.ChildAdded`). Для каждого запоминается `Enabled` и подписывается `GetPropertyChangedSignal('Enabled')`: пока UI скрыт, новое «желаемое» значение запоминается, а gui снова выключается. При показе восстанавливается ровно сохранённое.
     * Исключения: сам слой кнопки возврата `DOGROTS_UIRestore` (DisplayOrder 1000) и экранные VFX/кино (`DOGROTS_EventCinema`, `NuclearPugGlow`, `WrongDogVignette`, `SecretScreen/Mega`, `EventGameplay`) — пометить атрибутом `UIKeep`.
  2. **BillboardGui**: реестр (weak set) через `workspace.DescendantAdded` и `PlayerGui.DescendantAdded` с момента старта. Стоимость — только `IsA`; полное сканирование нужно только один раз. Скрытие — локальный `Enabled=false` с той же защитой от переключения скриптами (`IncomePopups`, `TutorialWorldMarker`, `Waypoint` лежат внутри главного gui). Вывески SurfaceGui (644) оставить: это мир. Сделать опцию.
  3. **Промпты**: `ProximityPromptService.MaxPromptsVisible=0` с восстановлением, чтобы не конфликтовать с `GUIIntegration.menuControls`, который переключает `Enabled`. Работает ли это свойство как ожидается, проверить в Studio.
  4. **CoreGui**: `StarterGui:GetCoreGuiEnabled` по каждому типу → выключить → восстановить точно (PlayerList ведёт `PawpadRuntime`). Чат — `TextChatService.ChatWindowConfiguration/ChatInputBarConfiguration.Enabled`.
  5. **Имена над персонажами**: локально `Humanoid.DisplayDistanceType=None` и восстановление. Титулы F10 — это BillboardGui, они попадают под реестр.
  6. Стрелки маршрута F1 и другие клиентские 3D-подсказки подписываются на `UIHidden`.
  7. На мобильных опция «скрыть и джойстик» (`GuiService.TouchControlsEnabled`), по умолчанию выключена.
* **Возврат**: H, кнопка «👁» (появляется на 3 с при движении мыши или касании, не перехватывает ввод камеры), геймпад.
  * **Автовозврат без анимации**, если сменился `OpenMenu`: серверное окно (Lucky offer, трейд, награда) не должно открыться невидимым, когда движение заблокировано.
  * Клавиши P/B/M сначала возвращают UI.
* **Данные**: ничего не сохраняется; опционально запоминать «показывать подсказку» в `p.Settings`.

### 17. Риски
* `ready()`-зависимость навигации; стили, клонируемые из YardPage; синхронизация токенов в `tests/uikit.luau`; точные RU-ключи AutoTranslate при правке английских строк.
* Скрипты сами переключают `Enabled`/`Visible`, и F9 может не восстановить их правильно.
* Конфликты владельцев `ProximityPromptService.Enabled` (GUIIntegration, Mining).
* Разные маршруты на ПК и телефоне; длинные русские строки в компактных кнопках; производительность ViewportFrame на слабых телефонах (держать `Preview.PerFrame=2` и полку).
* Сервер-лимитер при переходном периоде, пока старые и новые экраны опрашивают параллельно.

---

## Трейды, титулы, достижения, сообщество (trade-titles)

### 0. Коротко
* **Обмен (trade)** работает целиком на сервере внутри `Economy.Engine` (`E:TradeRequest` / `E:Trade` / `E:CancelTrade`, Engine.luau:270-355). Состояние сессий хранится только в RAM (`Engine.Trades`, `Engine.TradeByUser`). Своп атомарен в RAM: одна быстрая транзакция `Tx:Run({p:a,p:b})`. **В DataStore он не атомарен**: профили потом сохраняются по отдельности автосейвом.
* Клиентский UI сделан двумя параллельными путями. Первый: статичная `TradePage` (PawpadController.renderTrade). Второй: экран `Menus` → `EconomyScreens.Screens.Trade` (EconomyScreens.luau:255-363). Экран перестраивается полностью каждые 5 с (`Menus:Render` → `ClearAllChildren`). Поиска, фильтров, сортировки и превью нет.
* В ходе аудита найдена **критическая уязвимость bait-and-switch** (гонка Confirm/Offer во время yield на PolicyService). Она **подтверждена симуляцией** реального кода. Найден и сильный вектор харассмента: приглашение сразу блокирует цель и насильно открывает ей окно с заблокированным управлением.
* **Титулов над персонажем нет.** «Коллекционные титулы» — это просто ключи в `p.Cosmetics`. Экипированный (`p.EquippedCosmetic`) показывается BillboardGui **над каждой собакой в будках** (EconomyVisuals.client.luau:27-37). Для всех титулов, кроме Dex*, вместо названия выводится сырой ключ.
* Отдельной системы достижений нет. Есть разрозненные «вехи»: Dex-награды, Finds-вехи, наборы, события, престиж, скины участка по `PlotCatalog.Earned`.

### 1. Файлы и роли
| Файл | Роль |
|---|---|
| `src/ServerScriptService/Economy/Engine.luau` | Сервер обмена: `CancelTrade` (270), `TradeRequest` (277), `fingerprint` (286), `Trade` (289: Accept/Offer/Ready/Confirm + коммит). `Leave` (44) отменяет обмен при выходе. |
| `src/ServerScriptService/Economy/Runtime.luau` | Маршрутизация `DogEconomyRequest`: 432-438 (`TradeRequest`, `TradeCancel`, `Trade`). Rate-limit `allow` (314). Фильтр `clean` (320). `Snapshot` (329-366: `Trade`=копия сессии, `Players`=список онлайн со статусом Trading). После каждого успешного шага `Trade` вызывается `RefreshAll()` (452). `PushTo`/`DogEconomyPush` (579-585). |
| `src/ServerScriptService/Economy/Transactions.luau` | RAM-first транзакции. `_canFast` (418) и `_runFast` (435) дают быстрый путь, по нему и идёт трейд. `_runDurable` (561) — журналируемый атомарный путь, сейчас трейдом не используется. |
| `src/ServerScriptService/Economy/Rules.luau` | `R.Dog(p,uid,true)` (99: владение, не Walking, не Locked, не в будке). `R.Pay/R.Credit` (106/111), `R.Transfer` (225: OwnerHistory Type='Trade'). Titles/cosmetics: `Cosmetic` (522), `RecordClaim` (459), `SetClaim` (532), `Prestige` (537). Перенос `Cosmetics` при MegaReset (56). |
| `src/ServerScriptService/Economy/ItemRules.luau` | `I.Get(p,uid,true)` (45: Tradeable + не ждёт проверки рекорда; **Favorite не проверяется**). `I.Transfer` (54). `Discovery:<set>` титулы (212). |
| `src/ServerScriptService/Economy/PaidItemPolicy.luau`, `PaidRandomPolicy.luau` | PolicyService `IsPaidItemTradingAllowed`: кэш 120 с, при промахе **yield**. |
| `LabService.luau` (23,45), `ShelterService.luau` (35,41,52), `ShelterRules.luau` (6), `YardCommerce.luau` (50) | Читают `Engine.TradeByUser[uid]` и блокируют лабораторию, приют и продажу Майло, пока игрок «торгует». Это **контракт**, который надо сохранить. |
| `src/ServerScriptService/Economy/Market.luau` | Кросс-серверный рынок (durable, налог 5%, эскроу). С трейдом не связан, но даёт медианы цен (`M:Query`). |
| `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` | `Screens.Trade` (255-363): список игроков, окно сессии, выбор собак/находок, кнопки UPDATE/LOCK/CONFIRM/CANCEL. |
| `src/StarterGui/ScreenGui/Modules/Menus.luau` | Окна Menus. Опрос Snapshot раз в 5 с (`Fetch`, 70), полная перестройка (`Render`, 177), обход `GetDescendants` каждые 0,5 с (`Update`, 203; запускается из `PawpadRuntime.client.luau:20`). Состояние `TradeDogs/TradeItems` (14). |
| `src/StarterGui/ScreenGui/PawpadController.client.luau` | Статичная `TradePage`: `renderTrade` (277-295), поиск игроков (416), опрос раз в 8 с. |
| `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` | `DogEconomyOpen('Trade')` → `N.OpenScreen('Trade')` (172-175). `N.Acquire` блокирует движение и ProximityPrompts (47-85). |
| `src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau:29` | Шаг 15 туториала описывает текущий поток обмена (текст придётся менять). |
| `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau` | RU-строки обмена (строки 28-133, 334, 502, 1939-1944…). |
| `src/ReplicatedStorage/DogEconomy/DexRewards.luau` | Dex-титулы (`Title='Dex10'…`, `TitleName`). Это единственный источник «красивых» имён титулов. |
| `src/ServerScriptService/Economy/Features/Dogdex.luau` (134-137), `Features/Passes.luau` (12-24), `PurchaseService.luau:79`, `Engine.luau:139` (EventClaim) | Источники записей `p.Cosmetics[...] = true`. |
| `src/ServerScriptService/DogKennelService.luau:196` + `StarterPlayerScripts/EconomyVisuals.client.luau:27-37` | `EquippedCosmetic` копируется атрибутом на модели собак в будках, клиент вешает BillboardGui `EconomyCosmetic` (MaxDistance 40) над **каждой** собакой. |
| `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau:67-77` | Список «YOUR COLLECTION TITLES» в COSMETICS (экипировка через action `Cosmetic`). |
| `src/ServerScriptService/Economy/CommunityService.luau` + `ServerKingPresentation.luau` + `ReplicatedStorage/ServerKingConfig.luau` + `CommunityConfig.luau` | Сообщество: старая доска XP (OrderedStore `DOGROTS_TOP_XP_V2_REBOOT1`), «король сервера» — гигантская голова аватара на `ServerKingMonument` с `KingLabel`, раз в 15 с. Почтовый ящик (`FeedbackRequest`). |
| `src/ServerScriptService/CommunityServices.server.luau`, `CommunityBootstrap.server.luau`, `StarterPlayerScripts/CommunityClient.client.luau` | Приют, обратная связь, UI приюта и обратной связи. **Обмена не касаются.** |
| `src/ServerScriptService/Economy/LeaderboardService.luau`, `LeaderboardRenderer.luau`, `ReplicatedStorage/LeaderboardConfig.luau`, `LifetimeStats.luau`, `RecordStats.luau` | 6 досок all-time (OrderedStore `DOGROTS_LB_*_V2_REBOOT1`), пожизненная статистика и статистика находок, в том числе `Stats.CompletedTrades`. |
| `src/ServerScriptService/Economy/CommunityQATests.luau` | **Мёртвый модуль**: нигде не `require`-ится. |
| `src/ServerScriptService/Economy/FeatureRegistry.luau` | Хуки Normalize/Validate/Action/Snapshot. Это лучшая точка для модуля титулов. |
| `src/StarterGui/ScreenGui/Modules/Kit*`, `Net.luau`, `docs/UIKIT.md` | UI-кит. Прямо предусматривает окно `Key="Trade"`, `VirtualGrid/CardGrid`, `SearchBox`, `Chips`, `SortSelect`, кнопку `Hold`, `Countdown`. `Net.OnPush` нужен для push-обновлений. |

### 2. Обмен сегодня: поток от начала до конца
**Вход.** Боковая кнопка `Sidebar.TradeButton` / HUD `QuickTrade` → `N.OpenPage('Trade')`. Дальше — статичная `TradePage` (десктоп) или экран Menus (компактный режим). Когда сессия есть, всегда открывается экран Menus (`renderTrade` → `OpenScreen`).

**Сервер (RAM-машина состояний в `Engine`):**
1. `TradeRequest {Target}` (Runtime:432 → Engine:277). Проверки: цель онлайн, оба не в обмене, оба уровня ≥ `C.TradeLevel=5` (Config.luau:132). Создаётся `t={Id,Users={a,b},Version=1,Offers={},Ready={},Confirmed={},Expires=now+240,Inviter=a,Accepted=false,UpdatedAt,ConfirmDelay=8}`. **`TradeByUser` сразу ставится обоим.** Цели уходит `DogEconomyOpen:FireClient(target,'Trade',…)`, у неё окно открывается принудительно.
2. `Trade{Action='Accept'}`: принять может только приглашённый.
3. `Trade{Action='Offer', Dogs≤6, Items≤6, Cash}` — полная замена своего предложения. Сервер проверяет `R.Dog(p,uid,true)`, `I.Get(p,uid,true)`, дубликаты uid, `p.Cash>=Cash`, PaidRandom-политику для обоих (вызов с **yield**). Сохраняются `Prints` (отпечаток собаки: Uid/DogId/Variant/Edition/Serial/Mastery/Ascension/AssignedSlot/State; находки: Uid/ItemId/WeightKg/Mutation), `Details` (полные копии) и `Estimated` (cash + `SellValue` находок + `LinePrice|BasePrice` вида собаки). `Version+1`, Ready и Confirmed сбрасываются.
4. `Ready {Version}`: версия совпадает, предложения есть у обоих, с последнего Offer прошло ≥2 с. Когда оба Ready, ставится `ConfirmAfter=now+8`.
5. `Confirm {Version}`: только после `ConfirmAfter`. Когда подтвердили оба → проверка PaidRandom (**yield**) → `t.Committing=true` → `Tx:Run({p:a,p:b}, …, 'trade-'..id)`. Внутри: Authorize (сессия и Connected) обоих, вместимость собак и находок с учётом резервов рынка, повторная сверка отпечатков (`R.Dog`/`I.Get` strict), `Pay/Credit` (Credit с `isEarned=false`, в TotalCoinsEarned не идёт), `R.Transfer` (OwnerHistory `Type='Trade'`), `I.Transfer` (истории владения у находок нет), `Stats.CompletedTrades+=1`, `R.Validate`. Затем `CancelTrade`. Обмен закрывается и при ошибке коммита.
6. `TradeCancel` — любая сторона. `E:Leave` (выход игрока) → `CancelTrade`, если сессия не коммитится.
7. Срок жизни — фиксированные 240 с с момента приглашения, без продления. Истёкшая сессия снимается **лениво**: только при `Snapshot` участника или при Cancel/Leave.

**Что можно передать:** собак (кроме Walking, Locked и стоящих в будке; собаку с витрины `DisplayDogs` — можно), находки (`Tradeable`, без ожидающей проверки рекорда; избранные — можно) и Cash (до `C.MaxCash`). **Нельзя:** Bones, EventTokens, Lucky Blocks, снаряжение и артефакты (артефакты собаки остаются у отправителя: Equipment.luau:9-10), ДНК лаборатории.

**Защиты, которые уже есть:** версия предложения, сброс замков при любом изменении, задержка 2 с перед LOCK, отсчёт 8 с, повторная сверка отпечатков и владения при коммите, проверка вместимости, rate-limit (8 токенов, +1,5/с), `clean()` (≤30 ключей, строки ≤120), PaidRandom-политика, уровень ≥5, блокировка лаборатории, приюта и продажи во время обмена.

**Логирование:** только `Stats.CompletedTrades` и `OwnerHistory` у собак. Журнала обменов в DataStore нет, у находок нет следа «от кого».

**Клиент:** все обновления идут опросом. Окно делает Snapshot раз в 5 с (весь профиль игрока плюс список до 59 игроков) и перестраивает UI с нуля. Пушей «партнёр изменил предложение / принял / отменил» нет.

### 3. Найденные баги и уязвимости (проверены чтением кода; ★ — подтверждено Lune-симуляцией реальных модулей в `scratchpad/tools/trade-titles/tradesim.luau` и `race.luau`)
1. **★ КРИТИЧНО — подмена предложения на последнем шаге (TOCTOU).** В `E:Trade('Confirm')` (Engine.luau:317-323) после того, как подтвердили оба, вызывается `PaidPolicy.Allowed`. Если в любом предложении есть PaidRandom-ассет и кэш политики старше 120 с, вызов уходит в PolicyService и **уступает поток** до установки `t.Committing`. В этот момент второй параллельный запрос `Offer` того же игрока проходит (`not t.Committing`) и заменяет его предложение. Коммит затем читает уже **новое** `t.Offers` (строка 327). Симуляция: атакующий сохранил свою платную собаку и Cash и получил ценную собаку жертвы; жертва не получила ничего. Исправление: снимать `version`/`offers` и ставить `Committing` до любого yield, после yield перепроверять версию, коммитить по замороженной копии.
2. **★ ВЫСОКО — харассмент и блокировка через приглашение.** `TradeRequest` сразу пишет `TradeByUser[target]`: до принятия цель не может пользоваться лабораторией, приютом, продажей Майло и получать другие приглашения. Это длится до 240 с, если цель сама не отменит. Клиент цели получает `N.OpenScreen('Trade')`: меню закрываются, **движение и ProximityPrompts блокируются** (GUIIntegration:47-85, 172-175). Сразу после отмены можно пригласить снова (кулдауна нет), «отклонить / заблокировать / не принимать приглашения» нельзя.
3. **★ ВЫСОКО (надёжность) — своп не атомарен в DataStore.** Оба профиля загружены → `_canFast` → `_runFast`: изменения только в RAM, профили помечены Dirty и сохраняются автосейвом (раз в 60 с) или при выходе **каждый отдельно**. Если сервер упадёт или один `ReleaseProfile` не сохранится между двумя flush, получится дюп одного ассета и потеря другого. Если одну сторону пометят `Suspect` и перечитают из хранилища, обмен откатится только у неё. В симуляции после коммита в хранилище нет ни одного `tx:`-журнала трейда, оба профиля Dirty.
4. **★ СРЕДНЕ — истёкшая сессия не убирается.** После `Expires` запись `TradeByUser` остаётся до Snapshot или отмены. Она продолжает блокировать приглашения («A player is already trading»), лабораторию, приют и продажу.
5. **СРЕДНЕ (нагрузка/DoS) — `RefreshAll()` на каждом успешном шаге `Trade`** (Runtime.luau:452): `Project` для **всех** игроков сервера (MaxPlayers=60: DogInventory до 250 записей с атрибутами, Reconcile участка, будок, витрины). `Accept`/`Offer` можно спамить примерно 1,5 раза в секунду с клиента.
6. **СРЕДНЕ — повторный `Ready` перезапускает `ConfirmAfter`** (Engine:314-315). Партнёр может бесконечно оттягивать финальное подтверждение.
7. **★ НИЗКО/СРЕДНЕ — гифт без лимитов и фарм статистики.** Односторонние обмены (Cash в подарок, налога нет) открывают отмывание через альтов и RMT. Пустые обмены тоже увеличивают `CompletedTrades`: 3 пустых обмена = +3. Если будущий титул или доска опирается на этот счётчик, его можно накрутить.
8. **НИЗКО — выбор на клиенте не сбрасывается.** `state.TradeDogs/TradeItems/TradeCash` (Menus.luau:14) никогда не очищаются и не сверяются с инвентарём. После обмена отданные uid остаются «выбранными» невидимо, следующее UPDATE OFFER падает с «Dog not owned», а счётчик 6/6 занят.
9. **НИЗКО — отсчёт стоит на месте.** Используется `c.Snapshot.Now` (время снапшота), а не `c.Now()` (EconomyScreens:327). «REVIEW 8s» меняется только при опросе раз в 5 с.
10. **НИЗКО — UX и производительность списка.** Находки перебираются `pairs` без сортировки, порядок прыгает при каждом обновлении. Непередаваемые находки и находки с ожидающей проверкой рекорда показаны как выбираемые. До 250 собак и до 1000 находок выводятся кнопками и пересоздаются раз в 5 с, плюс `GetDescendants` каждые 0,5 с.
11. **НИЗКО — оценка обманывает.** `Estimated` не учитывает вариант, мастерство и вознесение собаки. Для находок берётся сохранённый при находке `SellValue`, а Майло продаёт по живой цене `ItemValuation.Price` (YardCommerce:56) — после F11 они разойдутся.
12. **НИЗКО — личность.** Окно сессии показывает только DisplayName (можно выдать себя за другого), @username виден лишь в панели деталей. Приглашение тоже с DisplayName.
13. **НИЗКО — несогласованность.** Избранные находки и собаки с витрины обмениваются (приют собак с витрины запрещает: ShelterRules:10). Флаг `Favorite` переносится получателю.
14. **НИЗКО — уведомлений нет.** Пригласившего не уведомляют о принятии, партнёра — об отмене или выходе. Срок 240 с не показан.
15. **Титулы.** Для не-Dex титулов (`Finds250`, `Discovery:<set>`, `Event3`, `Prestige2`, `Set<X>`, `SupporterTitle`, `FounderPlaque`) в COSMETICS и над собаками выводится сырой ключ: `DexRewards.TitleName` знает только Dex*. Экипированный титул висит над каждой собакой в будке, а не над игроком.
16. **Мёртвый код.** `CommunityQATests` не подключён. Ветка `Rules.Action 'DexClaim'` (528) недостижима: её раньше перехватывает Features/Dogdex. Старые `Dex25/Dex75` остались только в старых сейвах.
17. **Техдолг.** Два параллельных UI обмена (TradePage и Screens.Trade). Сервер обмена вшит в Engine, тестов на трейд в `tests/` нет.

### 4. Титулы, достижения, сообщество сегодня
* **Сохранённые «титулы»** — ключи `p.Cosmetics[key]=true`:
  * `Dex10/30/50/70/90/100` (Features/Dogdex.Claim; имена в DexRewards: DOG SPOTTER … DOGDEX MASTER) и старые `Dex25/Dex75`;
  * `Finds25…Finds2500` (RecordClaim, вехи `RecordStats.Milestones`);
  * `Discovery:<set>` (наборы находок, ItemRules:212); `Set<Set>` (полный набор собак, Rules:536);
  * `Event1..5` (EventClaim, Engine:139); `Prestige<N>` (Rules:540);
  * покупки: `SupporterTitle`, `EventSupporter`, `GoldenKennel`, `VoidAura` (ShopDefinitions, Id=0 — сейчас не продаются);
  * старые платные косметики `C.Cosmetics`: GoldenKennel, CyberKennel, VoidAura, FounderPlaque.
* **Экипировка:** `p.EquippedCosmetic` (одна строка) через action `Cosmetic`. Если ключа нет в `C.Cosmetics`, но он есть в `p.Cosmetics`, это «Collection title equipped» (Rules:524). Значение читает миграция скинов участка `PlotRules.Normalize:14` (однократно, пока нет `PlotProgressionVersion`).
* **Отображение:** только над собаками в будках (`EconomyCosmetic`, 5,6 студа над RootPart собаки, MaxDistance 40). Над игроком своего UI нет. Есть дефолтный ник Roblox (`StarterPlayer.NameDisplayDistance=100`), аксессуары снаряжения на голове, лице, спине и ногах (`EquipmentWorld.Wear`, сварены с персонажем, видны всем) и трейлы событий.
* **«Король сервера»** — лучший по XP на сервере. Гигантская голова аватара над `Workspace.DOGROTS_District.32_WelcomeHub.CommunityCourt.ServerKingMonument`, табличка `KingInfo.KingPresentation`. Над персонажем короля ничего нет.
* **Статистика для условий:** `p.Level`, `p.Prestige`; `p.Stats` (TotalFinds, TotalDigs, SecretFinds, BestTier, LongestStreak, BestDayCount, TotalSellValue, BiggestSale, CompletedTrades, Depths, Milestones/Claims); `p.Lifetime` (TotalPlaytimeSeconds, TotalCoinsEarned, GlobalDigContribution, SupportRobux); `R.MuseumCount(p)`, `p.Collection`, `p.HeavyCollection`, `p.ItemSets`; `p.Mining` (OresBroken, CoinsEarned, PickaxeLevel, Strength); `p.Lab.Experiments`; `p.UnlockedLayers`; `p.WorldEventsSeen`; `p.PlotSkins`, `PlotCatalog.Level(p)`.
* **Готовый образец «достижения»:** `PlotCatalog.Earned(p,id)` / `Requirement(p,id)` — чистые функции, общие для клиента и сервера.

### 5. Сохраняемые данные
* DataStore `DOGROTS_ECONOMY_V1` (через `StoreKeys.Wrap`): `p:<userId>` (весь профиль, записи `{Value,Revision,Lock,Writer}`), журналы `tx:<id>`.
* **У обмена ключей нет.** В профиле от него остаются `Stats.CompletedTrades`, `Dogs[*].OwnerHistory[{UserId,At,Type='Trade'}]` (+`EarlierTransfers`), у находок — `OwnerUserId`.
* Титулы: `p.Cosmetics`, `p.EquippedCosmetic`, `p.DexClaims`, `p.ItemSets`, `p.Stats.Milestones/Claims`, `p.Event.Claims`, `p.Prestige`. `Cosmetics` переживает MegaReset (Rules:56).
* Сообщество: OrderedStore `DOGROTS_TOP_XP_V2_REBOOT1`, `DOGROTS_LB_{SUPPORT,PLAYTIME,COINS,DISCOVERIES,GLOBALDIG,DOGDEX}_V2_REBOOT1`; ключи почты `mailquota:<id>:<day>`, `feedback:<hour>:<n>`.
* Версионирования формата обмена нет (только RAM). `Config.Version`/`BalanceVersion` его не касаются.

### 6. Сеть (remotes)
* `DogEconomyRequest` (RF, C→S, `(action,args,requestId32hex)`): `Snapshot` (несёт `Trade` и `Players[{Id,Name,Username,Level,Status,Trades,Listings}]`), `TradeRequest{Target}`, `TradeCancel{}`, `Trade{Action,Dogs,Items,Cash,Version}`, `Cosmetic{Kind}`, `DexClaim{Count}`, `SetClaim{Set}`, `RecordClaim{Count}`, `EventClaim{Milestone}`, `Prestige{}`.
* `DogEconomyOpen` (RE, S→C): `('Trade', 'Trade invitation from <DisplayName>')` — принудительно открывает окно.
* `DogEconomyPush` (RE, S→C; создаётся в `Runtime.Start`; клиент — `Net.OnPush`): сейчас только `EquipmentCredits`. Для обмена и титулов это готовый канал.
* Сообщество: `FeedbackRequest` (RF, почта), `CommunityFeedbackRequest` (RF), `CommunityOpen` (RE), `ShelterRequest` (RF).
* Атрибуты: у Player примерно 60 атрибутов из `Runtime.Project`, все реплицируются всем клиентам. У моделей собак в будках — `EquippedCosmetic`.

### 7. Инстансы мира и GUI, от которых зависит подсистема
* `StarterGui.ScreenGui.MainWindow.Content.PageContainer.TradePage` (`ServerPlayersPanel.{Search,Players.PlayerCardTemplate,Players.Empty,Title}`, `PlayerDetailsPanel.{Username,Stats,RequestTrade,TradeNotice}`, `Status`); на него ссылается PawpadController.
* `StarterGui.ScreenGui.MainWindow.Sidebar.TradeButton` (CandyPage=Trade), `StarterGui.ScreenGui.HUD.QuickTrade.Open` (пересоздаётся `UITheme`).
* `Workspace.DOGROTS_District.32_WelcomeHub.{ServerKingAnchor, CommunityCourt.ServerKingMonument(.KingInfo, CrownGlow), DeveloperMailbox.MailboxBody(FeedbackPrompt), DogShelter.SellAnchor.ShelterPrompt}`; `AllTimeLeaderboard` опционален.
* `Workspace.DOGROTS_District.09_DogPark.LeaderboardPlaza` (доски Honor/Discovery/Legacy).
* `Workspace.DOGROTS_District.KennelDogs` (модели собак с `EquippedCosmetic`).
* Настройки места: `Players.MaxPlayers=60`, `Workspace.StreamingEnabled=true` (TargetRadius 1024, MinRadius 64), `StarterPlayer.NameDisplayDistance=100`.

### 8. Клиент/сервер и производительность
* Сервер — единственный источник правды. Клиент шлёт только uid и числа, цены и оценки считает сервер.
* Сервер: на коммит одна RAM-транзакция (дёшево). Каждый шаг даёт `RefreshAll` (дорого) и полный Snapshot для вызывающего.
* Клиент: опрос каждые 5 с, полная перестройка окна, `GetDescendants` каждые 0,5 с, сотни и тысячи кнопок без виртуализации.
* Титулы: сейчас до 5 BillboardGui над будками у каждого владельца, создаются и уничтожаются при смене атрибута.

### 9. Что можно улучшить поверх текущей системы
* Хотфикс гонки Confirm (п.3.1). Это ~10 строк в `E:Trade` и не меняет формат.
* Отдельная таблица `Invites` и `TradeByUser` только после Accept. Приглашение — тост с ACCEPT/DECLINE вместо принудительного окна. Кулдаун на пару и на приглашающего, настройка «приглашения: все / друзья / никто».
* Шаг `TradeService.Sweep` в цикле экономики (истечение приглашений и сессий, сессия живёт по бездействию, а не фиксированные 240 с).
* Вместо `RefreshAll` обновлять только двух участников, вместо снапшотов — push `TradeState`.
* Повторный `Ready` не трогает `ConfirmAfter`. Пустые и односторонние обмены не увеличивают `CompletedTrades`.
* Клиент: сбрасывать выбор после закрытия, сверять его с инвентарём, вести отсчёт через `c.Now()`/`Kit.Countdown`, отсортировать и отфильтровать список (Tradeable, ожидание рекорда).
* Титулы: хотя бы словарь имён для всех ключей `p.Cosmetics` (Finds/Discovery/Event/Prestige/Set/Supporter).

### 10. Что требует аккуратного рефакторинга
* Вынести обмен из `Engine` в `Economy/TradeService.luau` + чистый `TradeRules.luau`, сохранив поля `Engine.Trades/TradeByUser` (их читают LabService, ShelterService, YardCommerce, Runtime.Snapshot и tests/lab.luau).
* Коммит через **durable**-путь `Transactions` (журнал + атомарная запись обоих профилей + запись аудита). Проверено симуляцией: `Tx:Run({'p:a','p:b','tl:<id>'}, …, 'trade-<id>')` на загруженных профилях даёт 6 Read и 11 UpdateAsync, оба профиля сразу сохранены и чисты, повтор с тем же id не применяется второй раз.
* Новый UI обмена на Kit (замена двух текущих путей). Перенаправить `GUIIntegration` и убрать `renderTrade` / `Screens.Trade`, статичную `TradePage` оставить скрытой.
* Титулы: отделить «титулы игрока» от «значков над собаками» (`EquippedCosmetic`), не ломая миграцию `PlotRules` и выдачи в `p.Cosmetics`.

### 11. План Trade 2.0 (F6) — кратко
Состояния: Invite → Editing → Locked (оба Ready) → Countdown (`ConfirmAfter`, 5 с, отсчитывает сервер) → Confirmed → Committing → Closed.
* Любое изменение предложения сбрасывает Ready и Confirm, подсвечивает добавленное и удалённое, LOCK разрешается через ≥3 с после последнего изменения.
* Коммит — durable `Tx:Run`, ключ аудита `tl:<tradeId>` и кольцевой журнал `p.TradeHistory` (20 записей).
* Ценность считается на сервере: собаки — каталог × бонус варианта, находки — живая `ItemValuation.Price`, опционально медиана рынка. При перекосе больше 3× — модальное предупреждение и удержание кнопки 2 с.
* UI: окно Kit `Key='Trade'` с двумя колонками «Я даю / Я получаю», слоты 6+6 с превью и подсветкой редкости, внизу виртуальный пикер с поиском, фильтрами (тип, редкость, мутация), сортировкой, группировкой одинаковых (×N со степпером), степпер Cash (10% / 50% / MAX). Большая кнопка-состояние LOCK → кольцо отсчёта → CONFIRM (удержание 1 с). Вкладка истории.
* На телефоне вкладки «ИХ / МОЁ / ДОБАВИТЬ». Обновления push-ом (`Net.OnPush('TradeState')`).

### 12. План титулов (F10) — кратко
* Общий `ReplicatedStorage/DogEconomy/TitleDefinitions.luau`: id, текст EN/RU, иконка, редкость (цвет и градиент из `Kit.Theme.Rarity`), категория, условие. Чистая функция `Progress(p,def)` по образцу `PlotCatalog.Earned`. Старые ключи `p.Cosmetics` сопоставлены с титулами.
* Feature-модуль `Economy/Features/Titles.luau`: `p.Titles={Version=1,Equipped,Unlocked,New,CheckedAt}`, проверка условий не чаще раза в 10 с, action `TitleEquip`.
* Репликация: `player:SetAttribute('TitleId')` в `Runtime.Project` и динамический `ServerKing` из `CommunityService.RefreshKing`.
* Клиентский `TitleTags.client.luau`: пул BillboardGui (один на игрока, Adornee=Head, выше шляпы снаряжения, MaxDistance 60, не больше 12 ближайших, на телефоне 8; переживает стриминг).
* Окно `TitlesScreen` на Kit.
* Над собаками оставить только значки будок (GoldenKennel/CyberKennel/VoidAura), чтобы не было визуального мусора.

### 13. Риски
* Поменяется семантика `TradeByUser`: она теперь ставится только после принятия. Модули-потребители должны продолжить её читать.
* Durable-коммит стоит около 17 запросов к DataStore на обмен и может ждать очередь. Нужен понятный статус «сохраняем…» и повтор с тем же requestId.
* Сопоставление старых титулов: нельзя трогать `EquippedCosmetic`, пока у профиля не прошла миграция `PlotRules` (`PlotProgressionVersion`).
* Решения владельца: лимиты Cash в обмене (RMT/альты), налог, гейт по уровню или возрасту аккаунта.
* 60 игроков: титулы и список игроков нужно ограничивать по дистанции и количеству.
* AutoTranslate: каждая новая строка требует RU-записи (`Localization/Trade.luau`, `Localization/Titles.luau`), тест `tests/uikit.luau` проверяет слова кита.

---

## Ивенты мира (Dog Rush) и навигация по миру (events-nav)

### 1. Кратко
* **Ивенты** — общий для всех серверов детерминированный график (`WorldEventSchedule`): 600 с спокойствия → 60 с WARNING → 240 с ACTIVE → 15 с ENDING. Полный цикл = **915 с (~15,25 мин)**. Сервер (`WorldEventService` + `WorldEventGameplay`) меняет мир (гравитация, скорость ходьбы/прыжка, «язык» DogLine, удача, моды раскопок) и выдаёт награды. Клиент (`WorldEventController` → `WorldEventFX` → `WorldEventSpectacle` + `WorldEventCataclysm`, плюс `WorldEventGameplayFX`, `WorldEventLighting`, `WorldEventAudio`) рисует всё **локально**.
* **Dog Rush (`DOG_RUSH`)** — Common, вес 14 из 99 (THE_VOID_OPENS выключен). Это примерно **14 % циклов**. Моя симуляция с подменённым RNG дала 13,8 % и средний интервал ~7,3 цикла, т.е. **примерно раз в 1 ч 50 мин**, по 4 минуты. Интерактивных объектов у Dog Rush нет: `SpecialObjects` отсутствует, а сигнатура на 60‑й секунде — только визуал.
* **«Багнутые собаки, прилипшие к игроку»** — это блок `WorldProps='DogCrowd'` в `WorldEventFX.luau` (строки 139–155 и 259–279). До 10 клонов `ReplicatedStorage.MenuModels` на каждом кадре ставятся в позицию `near + heading:VectorToWorldSpace(lane,0,-z)`. Здесь `near` — **текущий HumanoidRootPart игрока**, а `heading` зафиксирован по направлению камеры в момент старта ивента. Отсюда эффекты:
  * стая едет вместе с игроком;
  * при беге «по курсу» собаки как будто стоят на месте или «лунной походкой» идут назад;
  * на каждый кадр на каждую собаку делается raycast `ground(world,10)` — собаки запрыгивают на крыши, заборы, конвейер и проходят сквозь здания;
  * у каждого клиента своя стая вокруг себя.
* **Навигация** сейчас — это только **маркер над целью**: BillboardGui «имя + N studs» над невидимой частью `LocalDistrictWaypoint`, плюс оверлей‑«карта» (`DistrictGuide`) со списком точек и схемой из точек‑кнопок. Маршрута, стрелок и обхода препятствий нет.

### 2. Файлы и роли
| Файл | Роль |
|---|---|
| `src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau` | Тайминги (NormalInterval 600, Warning 60, Event 240, Transition 15, Intro 5), Epoch/Seed/ScheduleBlock, ModifierCaps, Interactions (Cooldown 12, PerEvent 10, Distance 17, Lifetime 50, MaxActive 12, SpawnSeconds 18, Cash 40, Bones 2), бюджеты FX High/Medium/Low (Particles/Debris/Dogs 14/8/3), Audio (не используется). |
| `.../WorldEventDefinitions.luau` | 13 строк ивентов (DisplayName, Rarity, Weight, GameplayModifiers, свет, ParticleProfile, WorldProps, SpecialObjects, SignatureSeconds/Duration, Depth/DepthLuck, Mutations) и `perks` (Walk/Jump/Gravity/LineSpeed/LineLuck/SecretLine/BlockChance/BonesPerMinute/MachineAurion/Effects/Reward). `D.PerkLines` даёт текст перков. |
| `.../WorldEventSchedule.luau` | Детерминированный выбор ивента: блоки по 128 циклов, без повтора подряд, буст Rare после серии. `S.At(now)` → {State, EventId, Cycle, Start/End/NextEvent/ActiveEnd}. |
| `.../WorldEventModifiers.luau` | Серверное «текущее событие» (`Set/Active`). `Resolve` подмешивает GameplayModifiers и синергии собак в `Rules.Team` (с капами). `MutationRows` — веса мутаций (Rules.Variant, ItemRules, RewardService, LuckyLifecycle). |
| `.../WorldEventObjects.luau` | Общие билдеры: Part/Particles/Beam/Soft/Ring/RingSet/Ellipsoid и модели пикапов (BonePile, GiantBone, ChargedCrystal, TreasureSpot, CursedCache, AlienDigZone) с маяком‑лучом. |
| `.../WorldEventFX.luau` | Клиентский оркестратор: наземные пропсы (НЛО, разлом, часы, трещины, кристаллы, лучи), «дождь» вокруг игрока, **DogCrowd**, Signature, а также вызовы Spectacle и Cataclysm. |
| `.../WorldEventSpectacle.luau` | «Небесный» сет‑пис перед игроком (~480 studs, ~16° над горизонтом). Для DOG_RUSH это кольцо‑портал (24/36/48 сегментов + glow на High), шар‑ядро и «Лидер» — собака из MenuModels высотой 30 studs с Highlight, прыгающая по небу раз в 8 с. |
| `.../WorldEventCataclysm.luau` | Баннер‑заголовок (ScreenGui `DOGROTS_EventCinema`), «surge» на сигнатуре (для DOG_RUSH это «ALPHA STAMPEDE»: лучи + вспышки + кольца + тряска 1,5 с), такты каждые 1,7 с (DOG_RUSH: «StampedeWake» — 3 неоновые полосы летят 175 studs **относительно позиции игрока**), перекраска поверхностей с `EventTintSurface` (для DOG_RUSH нет). |
| `.../WorldEventLighting.luau` | Клиентский свет/атмосфера/пост‑эффекты/облака/небо по mood‑профилю с аккуратным возвратом; BLACKOUT мигает светом района. |
| `.../WorldEventAudio.luau` + `AudioAssetIds.luau` | Переписаны владельцем (русские комментарии): только музыка (MAIN + трек на каждый ивент, DOG_RUSH = 96136508081960). **`Audio.Cue()` пустая**: все SFX‑кью ивентов немые. |
| `src/ServerScriptService/WorldEventService.luau` | Планировщик (`Tick` раз в 1 с): `Apply` пишет атрибуты в `WorldEvents.State` + `Revision`, `Changed:FireAllClients`, журнал `WorldEventsSeen`, спавн и сбор пикапов (`SpawnObject`, `Interact` через `Runtime.Tx`), Studio‑`Force`. |
| `.../WorldEventGameplay.luau` | Перки на сервере: `workspace.Gravity`, `MovementModifiers.Set/SetJump('Event')`, атрибуты `03_DogLine` (`EventLineScale`, `EventBlockScale`), кости в минуту (Bone Rain), мигание гравитации (NULL HOUR), награда в конце (`G.Reward`). |
| `.../WorldEventBootstrap.server.luau` | Одна строка: `require(script.Parent.WorldEventService).Start()`. |
| `.../WorldEventTestServer.server.luau` + `StarterPlayerScripts/WorldEventTestPanel.client.luau` | Только Studio: RemoteFunction `WorldEvents.StudioEventControl` (start/stop/resume/signature), панель на F6. |
| `StarterPlayerScripts/WorldEventController.client.luau` | Синхронизация по `State.Revision` (+ `Changed` и `GetState` как fallback), карточка‑уведомление, обратный отсчёт, предиктивное скрытие пикапа, обработка `Signal` (Reward/Hint/Discovered/Signature/EventReward), атрибут качества `WorldEventFX` (Medium на тач‑устройствах). |
| `StarterPlayerScripts/WorldEventGameplayFX.client.luau` | Effects: Flashlight, Tractor (лучи НЛО реально поднимают — физика у клиента), Quakes, Trail на всех персонажах, **Zoomies** (18 «speed lines» в ScreenGui `DOGROTS_EventGameplay`, RenderStepped), Glitch; праздник Server Luck. |
| `src/StarterGui/ScreenGui/Modules/EventsScreen.luau` | Страница EVENTS: Daily + Playtime, текущий ивент, «почему ждать», 5 следующих ивентов (детерминированно на клиенте), блок Aurion (DOG‑O‑MATIC). Открывается через `N.OpenPage('Events')` → `N.OpenScreen` → `EconomyScreens`. |
| `src/ServerScriptService/DogLineSpawner.server.luau` | «Язык» (конвейер собак). Скорость = `Stream.Speed(6)·EventLineScale` (клэмп 0,4..2), шанс блока ×`EventBlockScale`. Во время Dog Rush язык ×1,5: сущность раз в ~5,3 с вместо 8 с, лента 304 studs проходится за ~22,6 с вместо ~34 с. |
| `src/ReplicatedStorage/MapRouting.luau` | 13 локаций (Key/Name/Detail/Sealed). `Anchor(key)` = `NavigationAnchors[key].Target.Value` или само зеркало. `Position(key,player)` (особый случай для своего двора — `YardSpawn`). `Bounds()`. **Это шаблон ModuleScript для `tools/build.py` (TEMPLATES) — не удалять и не переименовывать.** |
| `src/ServerScriptService/NavigationSync.server.luau` | Раз в 1 с копирует CFrame Target → зеркало в `NavigationAnchors`. |
| `src/ServerScriptService/Economy/DistrictTravel.luau` | Серверный телепорт к Lab/Museum через `DogEconomyRequest('DistrictTravel')`: проверки персонажа, raycast пола, overlap. **Ни один UI его не вызывает** (`N.Travel` нигде не используется). |
| `src/ServerScriptService/DistrictDoors.server.luau` | Серверные автодвери (атрибут `AutomaticDoor`). В плейсе одна дверь: `05_MutationLab.GlassFacade.LaboratoryAutomaticDoor`. |
| `src/ServerScriptService/DistrictSafety.server.luau` | Возврат при падении (Y < −85). |
| `StarterPlayerScripts/DistrictGuide.client.luau` | Оверлей карты (клавиша M, `ToggleDistrictMap`), список точек, схема, маркер‑Billboard, авто‑сброс ближе 13 studs, обработчик `NavigateDistrict(name)`. |
| `StarterPlayerScripts/DistrictWorldMotion.client.luau` | Локальные анимации пропсов по атрибуту `Motion` (в плейсе 1 объект). Подписан на `DescendantAdded` всего района. |
| `StarterPlayerScripts/WorldSignController.client.luau`, `ReplicatedStorage/WorldSignConfig(.luau,/LocationLabels.luau)`, `ServerScriptService/LocationLabelsBootstrap.server.luau` | Затухание мировых табличек по тегу `ManagedWorldSign` (6 в плейсе). Подписи Shop/Museum/Lab/Shelter берут иконки из `StarterGui.ScreenGui.MainWindow.Sidebar.{ShopButton,DogDexButton,LabButton,DogsButton}.{CandyIcon,CandyCaption}`. `WorldSignController` тоже шаблон LocalScript для build.py. |
| `src/StarterPlayer/StarterPlayerScripts/ExpressMotion.client.luau`, `ServerScriptService/MovementModifiers.luau` | DOG EXPRESS: две полосы ускорения ×2,6 (x = ±26, z −162..740, 148 «Arrow»‑частей ездят по CFrame). `MovementModifiers` перемножает модификаторы (Event×Express, клэмп 0,5..3, WalkSpeed ≤ 72). |

### 3. Как работает Dog Rush сейчас (end to end)
1. **Старт.** `WorldEventService.Tick` (1 Гц) → `Schedule.At(os.time())` → `Apply`: атрибуты `WorldEvents.State` (State, EventId, Cycle, StartTimestamp, EndTimestamp, NextEventTimestamp, ActiveEndTimestamp, Generation=`"<Cycle>:DOG_RUSH"`, Revision), `Modifiers.Set`, `Gameplay.Apply`, `Changed:FireAllClients`, журнал `WorldEventsSeen` каждому игроку (отдельная Tx).
2. **Сервер, пока ACTIVE (240 с):**
   * Walk ×1,35;
   * язык ×1,5 (`EventLineScale`), LineLuck ×1,2 (через `ServerLuck.Ranks` на ранги 4–6);
   * GameplayModifiers: DigSpeed +0,15 и Recovery +0,05 (через `Rules.Team` → `Modifiers.Resolve`);
   * на 60‑й секунде `Signal{Kind='Signature',Duration=18}` всем — без серверного действия.
3. **Клиент:**
   * WARNING‑карточка и отсчёт 10..1;
   * на ACTIVE: `Lighting.Begin`, музыка ивента, `FX.Begin`:
     * DogCrowd (до 10/8/3 собак по High/Medium/Low);
     * эмиттер «лапок» над игроком;
     * Spectacle (портал + Лидер в небе);
     * Cataclysm (баннер «DOG RUSH», такты StampedeWake);
   * `WorldEventGameplayFX`: Zoomies и Trail всем персонажам;
   * через 7 с — карточка перков.
4. **Сигнатура:** Cataclysm.surge «ALPHA STAMPEDE» + `Spectacle.Signature` (ударная волна, всплеск частиц).
5. **Конец (ENDING 15 с):** FX затухают; `Gameplay.Apply(nil)` → `G.Reward`. Награду получают игроки, которые пробыли на сервере ≥ 60 с от `max(join, start)` и у которых `TotalExcavations` выросло на ≥ 4 (`MIN_EVENT_DIGS`). Размер: `BoostPricing.Coins({MinCash=600,IncomeMinutes=1})` = max(600 × LayerScale по самому глубокому слою, 1 минута дохода) + 2 кости. Леджер `WorldEventRewards[generation]`. Затем `Signal{Kind='EventReward'}` + тост `RewardPresentation`.
   * **Важно:** `TotalExcavations` растёт в `Rules.Dig`, который вызывается `Engine:TickAll` для каждого подключённого игрока. Значит, условие «активно копал» выполняется AFK‑игроком с назначенными собаками. Текст на EVENTS («Stay active and DIG») вводит в заблуждение.

### 4. Сохранённые данные (профиль `p:<UserId>` через `Economy.Transactions`, `Runtime.Tx:Run`)
| Поле | Кто пишет / читает | Смысл |
|---|---|---|
| `p.WorldEventsSeen` | `WorldEventService.journal` / `PlotCatalog.Earned/Requirement` | `{[EventId]={FirstSeen,Rarity}}` — «видел ивент». Нужен для разблокировки ивентовых скинов участка (DogRush: + `Lifetime.GlobalDigContribution ≥ 90`, Cash 3600×5). |
| `p.WorldEventClaims` | `WorldEventService.Interact` | `{Generation,Count,Objects={[objectId]=true}}` — пикапы в текущем поколении (≤ 10). |
| `p.NextWorldEventCollect` | `Interact` | Кулдаун сбора, unix + 12 с. |
| `p.WorldEventRewards` | `WorldEventGameplay.Reward` | `{[generation]=unixTime}` — не больше 8 записей, затем сброс в `{}`. |
| `p.Cash`, `p.Bones`, удача (`LuckRules.Add`), предметы (`I.Mint`, Origin=`'WorldEvent:<id>'`) | награды | — |
| `p.Event {Week,Contribution,Claims}`, `p.EventTokens` | `Rules.Normalize`, `Engine` (`EventClaim`/`EventRoll`), `GlobalDigService` | **Другая** (еженедельная community) система. Её рисует легаси `PawpadController.renderEvents` на `MainWindow…EventsPage`. Через `OpenPage('Events')` она, вероятно, недоступна — проверить в Studio. |

Отдельных DataStore‑ключей и версий у ивентов нет: поля добавляются лениво и nil‑safe. У навигации сохранённых данных нет, только атрибуты игрока (`YardId`, `YardSpawnPosition`, `ReducedMotion`, `WorldEventFX`, `OnDogExpress`).

### 5. Сеть
* `ReplicatedStorage.WorldEvents.State` (Folder, атрибуты) — главный канал синхронизации (S→C репликация).
* `WorldEvents.Changed` (RemoteEvent S→C, полное состояние при каждой смене).
* `WorldEvents.Signal` (RemoteEvent S→C): `Reward` / `Hint` (одному), `Discovered` (одному), `Signature` (всем), `EventReward` (одному).
* `WorldEvents.GetState` (RemoteFunction C→S, `Runtime.Allow(player,1)`).
* `WorldEvents.StudioEventControl` (RF, только Studio), `WorldEventService.WorldEventDebug` (BindableFunction, только Studio).
* ProximityPrompt `WorldEventPickupPrompt` на серверных пикапах в `workspace.WorldEventFX`.
* `ReplicatedStorage.RewardPresentation` (S→C: Cue/Message/PromptFeedback/Announcement).
* `DogEconomyRequest('DistrictTravel',{Destination='Lab'|'Museum'},id)` (C→S, кулдаун 2 с; не используется).
* Bindable `StarterGui.ScreenGui.NavigateDistrict:Fire(name)` и `ToggleDistrictMap`. Вызывают `GUIIntegration.N.Navigate`, `Menus` (`c.Go`), `OnboardingGuide`, `LabScreen` (`'Mutation lab'`), `RewardScreens` (`'DOG-O-MATIC PLAZA'`, `'Dog Shelter'`), `UITheme` (`'Factory'`, `'Your yard'`), `PawpadController` (`'Factory'`).
* Атрибуты `03_DogLine.EventLineScale/EventBlockScale`; серверный `workspace.Gravity`.

### 6. Мировые инстансы
* `Workspace.DOGROTS_District.NavigationAnchors` — **ModelStreamingMode=Persistent**, 13 Part + ObjectValue `Target`. Позиции целей:

| Ключ | Позиция цели |
|---|---|
| DogLine | (0, 2, −140) |
| PlayerYards | (0, 2, 110) |
| WelcomeHub | (0, 3, 377) |
| DogDex | (−53, 3, 481) |
| MutationLab | (78, 3, 477) |
| GlobalDigSite | (38, 3, 575), запечатан |
| RewardMachine | (−106, 3, 630) |
| Shops | (94, 3, 335) |
| DogPark | (−100, 3, 238) |
| PortalRuins | (−63, 3, 564) |
| TheVoid | (700.7, 117, −633.3), запечатан |
| Shelter | (87.9, 3, 204.9) |
| Feedback | MailboxBody (0, 6.1, 150) |

  В .rbxl у некоторых зеркал другие координаты; на рантайме их выравнивает `NavigationSync`.
* **Улицы (база для графа маршрутов).** Всё выровнено по осям, Y ≈ 0,2–0,4:
  * `01_IslandAndStreets.PrimaryPaths`: MainBoulevard x ∈ [−18, 18], z ∈ [146, 754]; DistrictConnection на z = 200 / 275 / 335 / 395 / 465 / 535 / 730; промenades дворов x = ±30 и ±156 (z −166..158); YardCrossing на z = −156 / −78 / 0 / 78 / 156;
  * `36_DistrictRefresh.DirectPaths` (подходы к Shelter/Leaderboard/Upgrade/Cosmetics/Supply/Museum/Lab/Machine/Portal/Future…);
  * `37_AttractionRefresh.ConnectedPaths` (`*_Boulevard` / `*_Destination`).
  * PathfindingModifier/PathfindingLink в плейсе нет.
* Дворы: 8 моделей `04_PlayerYards.Yard_0N`, YardSpawn на x = ±28, z = −117 / −39 / 39 / 117. Язык: DogSpawn (0, 2, −168) → DogEnd (0, 2, 136), BeltTread 22 × 304.
* Спавн: `Workspace.DistrictSpawn` (0, 0.4, 377). Сцена ивентов: WelcomeHub + (0, 0, −32), потому что `GlobalDigConfig.Enabled=false`.
* `WorldEventSpawnPoints`: 18 точек (Yards 3, DogPark 2, GlobalDigSite 5, BackDistrict 5, WelcomeHub 3, DogLine 0). 246 частей с `EventTintSurface`, 294 Light в районе (79 «навигационных», родитель WarmLens/PortalEnergy).
* `ReplicatedStorage.MenuModels` (101 модель, скин + кости; например Breadog 2 части / 17 костей). `SoundService.DOGROTS_AUDIO.{Music,WorldEvents}`.
* `Workspace.WorldEventFX` (серверные пикапы). Клиентские папки: `WorldEventClientFX`, `DOGROTS_EpicEvent`, `DOGROTS_Cataclysm`, `DOGROTS_EventGameplayFX`, `LocalDistrictWaypoint`.
* Стриминг: `StreamingEnabled=true`, MinRadius 64, TargetRadius 1024. Persistent только `NavigationAnchors`, `13_TheVoid`, `RewardMachineRig`, `BeltEndPortal`. Протяжённость района примерно x ∈ [−200, 210], z ∈ [−350, 750].

### 7. Клиент / сервер
Сервер авторитетен в состоянии, перках, пикапах (сначала claim в RAM, затем Tx с ключом идемпотентности `eventcollect:<uid>:<id>`) и наградах. Клиент только рисует, кроме тракторных лучей и толчков землетрясения — они меняют скорость собственного персонажа (физика клиента, игрового эффекта нет). Навигация целиком клиентская, кроме неиспользуемого DistrictTravel.

### 8. Производительность
* Клиентские циклы во время ивента:
  * Controller — 12,5 Гц;
  * WorldEventFX — 20 Гц плюс **каждый кадр по каждой DogCrowd‑собаке**: raycast + PivotTo + `DogAnimationPlayer:Step` (сэмплинг костей) + цикл по LocalTransparencyModifier;
  * Spectacle и Cataclysm — по 30 Гц (15 Гц на Low);
  * Zoomies — RenderStepped по 18 Frame.
* 4 отдельных RenderStep для тряски камеры: `DOGROTS_EventGameplayShake` Camera+3, `DOGROTS_EventCamera` +1, `DOGROTS_EpicCamera` +2, `DOGROTS_CataclysmCamera` +3. Две из них на одном приоритете.
* Пик для Dog Rush на High — ~250 частей (кольца по 48 сегментов ×2, 10 собак, кольца surge по 32).
* Полные сканы `GetDescendants` района (~37,5 тыс. инстансов):
  * клиентский `WorldEventLighting.Begin` (поиск Light) на старте **каждого** ивента;
  * `Cataclysm.Begin` (`EventTintSurface`) для ивентов с tint;
  * **серверный** `WorldEventService.points()` при каждом спавне пикапа (каждые 18 с у ивентов со SpecialObjects).
* Навигация дешёвая: 5 Гц и одна Billboard. `DistrictWorldMotion` и `DistrictDoors` подписаны на `DescendantAdded` всего района — при стриминге это тысячи `task.defer`.

### 9. Найденные баги и техдолг
1. **DogCrowd «прилип к игроку»** (`WorldEventFX.luau:139–155, 259–279`). Позиция считается от живого HRP, heading замёрз с камеры на старте, raycast на каждый кадр ставит собак на крыши и в стены, у каждого клиента своя стая.
2. `WorldEventCataclysm.luau:393–398`: «StampedeWake» тоже строится от позиции игрока и пролетает сквозь здания.
3. **`WorldEventAudio.Cue` пустая.** Кью interaction / reward / rare / variation_N / special не звучат, `Config.Audio` не используется.
4. Награда «за активность» достаётся AFK‑игроку (`WorldEventGameplay.luau:216–217` + `Engine:TickAll → Rules.Dig`).
5. У Dog Rush нет интерактива: нет SpecialObjects, сигнатура — только FX.
6. **`DistrictGuide.updateYard` пишет в `locations[2]`.** Это «Developer mailbox» (порядок `MapRouting.Locations`: 1 Shelter, 2 Feedback, 3 DogLine, 4 PlayerYards…). В итоге точка и маркер почтового ящика указывают на двор игрока, а точка двора остаётся на общем входе.
7. `GUIIntegration.OpenScreen('Feedback')` → `Navigate('Feedback')`: совпадения нет (сравнение идёт по `loc.name`, а там «Developer mailbox») → вместо маркера просто открывается карта.
8. Heartbeat `DistrictGuide` (стр. 111–113) перезаписывает позицию «Your yard» (из `YardSpawnPosition`) на `Routing.Position('PlayerYards',player)`. Если свой двор не застримлен, это общий якорь (0, 2, 110).
9. `Routing.Bounds()` включает запечатанный TheVoid (700, 117, −633): точки района сжаты примерно в 20 % ширины схемы.
10. Слушатель `DistrictDirectoryPrompt` мёртвый — такого промпта в плейсе нет. `N.Travel` и `DistrictTravel` — мёртвый код.
11. Если сменить качество FX во время ENDING, `FX.Begin` перезапускает визуал и баннер (`WorldEventController.client.luau:157`), после чего тот обрывается при cleanup.
12. Полные сканы района (п. 8) и 4 конкурирующие тряски камеры.
13. Фиксированные Cash 40 / Bones 2 за пикап не масштабируются с доходом (важно для F11). Награда в конце масштабируется: IncomeMinutes и LayerScale.
14. `LocationLabels.Apply` делает бесконечный `WaitForChild` на `Sidebar.*Button.CandyIcon/CandyCaption`. Если F2 переименует или уберёт кнопки, подписи над зданиями пропадут. Комментарий в bootstrap («six labels») не совпадает с 4 записями.
15. Монолитные if‑цепочки по `def.Id` в FX/Spectacle/Cataclysm. Тестов на расписание, награды и навигацию нет (есть только `tests/machine.luau` на модификаторы).

### 10. Что можно улучшить поверх текущей системы
* Заменить DogCrowd на «забег по полосам» в новом модуле, сохранив `Definitions`/`Schedule`/`Service`. Достаточно флага `Effects.Rush` и guard в `WorldEventFX.setup`.
* Реализовать `Audio.Cue` через `WorldSound`/`RewardAudio`, не трогая музыкальную часть владельца.
* Добавить прогрессию (Rush Pass) отдельным feature‑модулем `Economy/Features/EventPass.luau` (Normalize/Validate/Action/Snapshot) — без правки Rules.
* «Показать путь» — новый клиентский модуль поверх `MapRouting` + граф улиц как данные. `NavigateDistrict` остаётся входной точкой.
* Починить баги 6–9 и 11 точечными правками в `DistrictGuide`.
* Кэшировать `WorldEventSpawnPoints` (CollectionService‑тег или один скан на старте), Light для BLACKOUT, tint‑поверхности.
* Масштабировать награды пикапов через `BoostPricing.Coins`.

### 11. Что требует аккуратного рефакторинга
* Разделить `WorldEventFX`, `Spectacle` и `Cataclysm` на «активности» по ивентам с общим планировщиком, единым CameraShake и бюджетом объектов. Сейчас 5 независимых Heartbeat/RenderStep.
* Переписать `DistrictGuide` на Kit (F2): матчинг по ключам вместо отображаемых имён (имена разбросаны по ~10 вызовам), реальная карта вместо точек.
* Отвязать `LocationLabels` от Sidebar.
* Зарезервированные имена: `MapRouting` и `WorldSignController` — шаблоны `tools/build.py`, удалять или переименовывать нельзя. Публичные API `MapRouting.Anchor/Position/Locations` используют `WorldEventFX`, `Spectacle`, `Economy/World.luau`, `DistrictTravel` — сохранить.
* Состояние ивента дублируется (атрибуты + Changed + GetState); при добавлении полей Rush держать один источник правды (атрибуты State).
* Для F5 (подземные уровни) все `ground()`‑raycast'ы «сверху вниз» (+8…+35 studs) и небесные сет‑писы нужно перевести в режим «под землёй/в помещении».

---

## Инструменты сборки, тесты и производительность (tooling-perf)

> Аудит только для чтения. Все цифры по плейсу получены собственными скриптами Lune из `build/DOGROTS_MINING.rbxl`. Скрипты лежат в `scratchpad/tools/tooling-perf/`: `counts.luau`, `stream.luau`, `rs.luau`, `rs2.luau`, `attrs.luau`, `attrnames.luau`, `lights.luau`, `yrange.luau`, `gui.luau`, `scripts.luau`, `lunecaps.luau`. Тесты запущены командой `lune run tests/*.luau`: 13 файлов, 233 теста, все зелёные, около 96 с. `check.sh` и `build.py` не запускались.

### 1. Сборка: как она работает от начала до конца

```
place/DOGROTS_base.rbxl (не менялся с 1edb1f9)  +  src/**/*.luau
        │  python3 -I tools/build.py
        ▼
build/DOGROTS_MINING.rbxl  +  build/build_report.json   (сейчас: modified 72, created 88 = 82 скрипта + 6 Folder)
        │  lune run tools/verify.luau build/... src .work/analyze
        ▼
каждый src-файл есть в плейсе, класс и Source совпадают, код компилируется (luau.compile);
у новых скриптов нет тегов и атрибутов; Script/LocalScript не Disabled; экспорт sourcemap.json + скриптов
        │  for t in tests/*.luau: lune run $t
        │  analyze_diff.py: luau-lsp analyze, база против сборки; печатаются только НОВЫЕ диагностики
        ▼
зелёный check.sh
```

| Файл | Роль |
|---|---|
| `tools/build.py` | Обходит `src/`, суффикс задаёт класс: `.server.luau` → Script, `.client.luau` → LocalScript, `.luau` → ModuleScript. Сортирует так, чтобы родители шли раньше детей. Для существующего пути меняет только `Source`. Для нового пути создаёт недостающие папки (Folder клонируется с шаблона `ReplicatedStorage/DogEconomy`) и клонирует скрипт с фиксированного шаблона (`ReplicatedStorage/MapRouting`, `StarterPlayerScripts/WorldSignController`, `ServerScriptService/LightingController`). У клона переписываются `Name` и `Source`, очищаются `AttributesSerialize`, `LinkedSource` и `SerializedOverrides`. |
| `tools/rbxl.py` | Патчер бинарного .rbxl, главная цель — точность. Нетронутые чанки пишутся байт-в-байт. Перекодируются только PROP/INST чанки изменённых классов и PRNT. Поддерживаемые типы: STRING, INT32/FLOAT32/ENUM/SHAREDSTRING/INT64/UNIQUEID/SECCAP/BRICKCOLOR, BOOL/FLOAT64/FACES/AXES, COLOR3/VECTOR2/VECTOR3. |
| `tools/verify.luau` | Независимая проверка через rbx-dom (Lune) и экспорт для luau-lsp. Клипы `DogAnimationClips` не экспортируются. |
| `tools/analyze_diff.py` | Сравнивает диагностики luau-lsp базы и сборки. Обычный проход и strict-проход; в strict остаются только `STRICT_KEEP` (неизвестные члены, глобалы, require). Тесты не анализируются. |
| `tools/check.sh` | Последовательно: build → verify → все `tests/*.luau` → analyze. Переменные окружения: `PYTHON`, `LUNE`, `LUAU_LSP`, `LUAU_DEFS`, `WORK`. Кэш анализа базы лежит в `.work/base_analyze` (база не меняется). |
| `tools/balance_sim.py` | Симулятор активной добычи. Читает `MiningConfig.luau` регуляркой `local M=(\{.*?\n\})\n` и считает монеты в минуту по кирке и слою, а также гири. В docstring обещаны сроки окупаемости, но в выводе их **нет**. |

#### Что сборка МОЖЕТ и чего НЕ МОЖЕТ

Проверено по коду и по типам свойств в чанках плейса: `rbxl.Place` + `prop_values`.

| Может | Не может |
|---|---|
| Менять `Source` у любых существующих Script/LocalScript/ModuleScript | Удалять, переименовывать и перемещать инстансы |
| Создавать новые Script/LocalScript/ModuleScript (Enabled, RunContext Legacy, как у шаблона) | Менять любое свойство, кроме `Source`: `Disabled`, `RunContext`, атрибуты, теги |
| Создавать Folder для недостающих папок | Создавать Part/Model/MeshPart/Attachment/ParticleEmitter/GUI. У Part нет кодеков для `CFrame`, `PivotOffset`, `Color3uint8`, `CustomPhysicalProperties`. У Model — для `PrimaryPart` (Ref) и `WorldPivotData` (OptionalCFrame). У ParticleEmitter — для NumberSequence/ColorSequence/NumberRange. У TextLabel — для UDim2/Font/Ref. |
| ModuleScript может быть родителем другого ModuleScript (`X.luau` + `X/Child.luau`) | Создавать RemoteEvent/RemoteFunction/Value. Технически rbxl.py это умеет, но в `build.py` нет шаблонов и соглашения об именах файлов. |
| | Менять свойства Workspace, Lighting, StarterGui, Players, Terrain. Стриминг-радиусы — INT32/ENUM, `set_prop_values` их поддерживает, но обёртки нет. |
| | Добавлять ассеты: меши, картинки, звуки. Их загружает владелец, ID прописываются в конфиг, как в `Mining/MiningAudio.AssetIds`. |

**Подводные камни сборки:**
1. **Если удалить src-файл оригинального скрипта, вернётся его версия из базы.** `src` содержит 341 из 342 скриптов, и сборка всегда стартует с базы. Чтобы «убрать» скрипт, оставляют файл с заглушкой (`-- retired`). Отключить скрипт нельзя: verify требует, чтобы он не был Disabled.
2. **Сборка недетерминирована.** `fresh_unique_id` и `fresh_guid` используют `os.urandom`, поэтому при каждой сборке все 88 созданных инстансов получают новые UniqueId и ScriptGuid. Бинарник `build/` меняется даже при неизменном `src/`.
3. Неоднозначные имена на пути вызывают assert. Например, в `ServerStorage` лежат два Part с именем `LocationLabelAnchor`, класть src под такие имена нельзя.
4. RemoteEvent создаются только во время выполнения: `Replicated:FindFirstChild(n) or Instance.new('RemoteEvent')` (`Economy/Runtime.luau:585`, `MuseumService.luau:17-18`, `RewardMachinePresentation.server.luau:15`).
5. rbx-dom в Lune 0.10.5 **не умеет** читать производное `.Position`, а также `GetPivot`, `PivotTo` и `GetBoundingBox`. Поэтому код строителей мира нельзя прогнать в Lune целиком. Геометрию надо выносить в чистые модули.
6. В `.work/` экспорт (`analyze`, `base_analyze`, `empty_src`). Каталог в `.gitignore`.

### 2. Тесты: как устроены и как добавить новый

| Файл | Тестов | Время | Как загружает код |
|---|---|---|---|
| animations | 12 | 32.5 с | Читает **плейс** (`build/…rbxl`, иначе базу) и запускает клипы плюс `DogAnimationPlayer` из src |
| machine | 12 | 23.3 с | Собственная мини-среда с `luau.load` и `roblox` |
| economy_loop | 16 | 13.0 с | `payments_lib/loader` с настоящими `@lune/task`, memory DataStore и реальным `Runtime.Start()` |
| payments | 21 | 11.4 с | `payments_lib/loader` с внедрением сбоев DataStore |
| equipment | 30 | 9.5 с | `lib/economy_env` |
| income | 31 | 2.7 с | `lib/economy_env` |
| economy_core | 4 | 1.7 с | `lib/economy_env` |
| dogdex, upgrade_tree, lab | 24/24/24 | <0.5 с | `lib/economy_env` плюс проверка, что у каждой строки `T("…")` есть RU-перевод |
| kennel | 3 | 0.2 с | `lib/economy_env` и самописные fake-инстансы с атрибутами |
| mining_rules, uikit | 17/15 | 0.1 с | Прямой `require("../src/…")` чистых модулей |

**`tests/lib/economy_env.luau`.** Индексирует весь `src` при старте, потому что fs в Lune уступает управление, а метаметоды не могут. Дерево — прокси-узлы по раскладке файлов. API:
- `L.Require("ServerScriptService.Economy.Rules")` — путь через точки.
- `L.Overrides["ServerScriptService/Economy/Runtime"]=stub` — путь через `/`.
- `L.Workspace` — фейковый workspace, задаётся до первого require.
- `L.Time` — значение для `os.time`.
- `L.Stubs` — RunService, Players, HttpService, LocalizationService.
- `L.Random` — детерминированный генератор.
- `L.Reset()`.

Учтите: `task.spawn/defer/delay/wait` здесь **ничего не делают**, а `Instance` — настоящий `roblox.Instance`, смешивать его с прокси нельзя.

**`tests/payments_lib/loader.luau`.** Fake-инстансы с атрибутами и детьми. API:
- `L.Instance(class)`, `L.Signal()`.
- `L.Services[name]` для заглушек сервисов.
- `L.Overrides[path]`, `L.Now` (значение `os.time`).
- `L.Fired` — журнал FireClient/FireAllClients.
- `L.Warnings`, `L.Prints`, `L.Reset()`.

Здесь работает **настоящий** `task`.

**Новый тест.** Файл `tests/<name>.luau`; `check.sh` подхватит его сам по маске `tests/*.luau`, подкаталоги `lib/` и `payments_lib/` в маску не попадают. Порядок такой:
1. Шапка `--!nocheck` (при необходимости `--!nolint`) и строка `-- … : lune run tests/<name>.luau`.
2. Свои `test/eq/near/truthy` и счётчики passed/failed.
3. В конце `print(string.format("<name>: %d passed, %d failed", …))` и `error(...)` при провале: check.sh ориентируется на код выхода.
4. Запуск из корня репо (пути `src/...`), uikit поддерживает и `../`.

Держать время теста в пределах секунд: суммарный прогон уже около 96 с.

**Studio-QA внутри плейса (вручную, только в Studio).** `ServerStorage/{BalanceQATests, DogGaitQA, DogVisualQA, DogIntegrationAudit}` и `Economy/{CommunityQATests, EstateQATests, PlotDevelopmentTests}`. Их вызывают из командной строки Studio; рантайм на них не ссылается.

### 3. Как раньше добавлялась геометрия мира

**Установщики в `ServerStorage` — это инструменты режима правки (Edit mode) в Studio, а не рантайм.**

| Модуль | Защита | Корень и метка | Итог в базовом плейсе |
|---|---|---|---|
| `MapRefreshInstaller` (`Version='2026-09-30.4'`) | `assertEdit()`: `IsStudio() and not IsRunning()` | `DOGROTS_District/36_DistrictRefresh`, атрибуты `CodexDistrictRefresh`, `Version`, счётчики | 906 инст., 825 деталей (727 из них позже скрыты), закрыт карьер `08_GlobalDigSite` (`PitCover` 170×210 в (119,−0.31,639)), окна, дорожки, витрина SUPPLIES |
| `AttractionRefreshInstaller` (`Version='2026-10-01.6'`) | `assertEdit()` | `37_AttractionRefresh` (`CodexAttractionRefresh`) | 1921 инст., 1730 деталей, `RewardMachineRig` (Persistent). Атрибут `Version` корня в плейсе = `2026-10-02.DOGOMATIC.Free`, то есть его позже правило что-то, чего в репо нет (не подтверждено) |
| `ShelterInteriorInstaller` (`Version='2026-09-30.1'`) | `assert(IsStudio and not IsRunning)` | `32_WelcomeHub/DogShelter/InteriorFinish` (`CodexShelterInterior`) | 462 инст., `CreatedParts=415`, `CreatedLights=9` |
| `RewardMachineRethemeInstaller` | без assert; идемпотентен (`CapsuleHousing` уже есть, значит возврат) | `RewardMachineRig.CapsuleHousing` | есть в плейсе |
| `AttractionTextRepair` | `not IsRunning()` | таблица путь → текст, атрибут `AttractionOriginalText` | 63 правки |

- **Их никто не вызывает.** Grep по `src` без `ServerStorage/` не находит ни одной ссылки. Результат «запечён» в `place/DOGROTS_base.rbxl`, сами модули импортированы без изменений (e31fac1).
- Обратимость держится на атрибутах-оригиналах на самих деталях: `DistrictRefresh_*`, `AttractionRefresh_*`, `ShelterOriginal_*` плюс флаги `*_Edited`. Это **≈29 тыс. атрибутов** и **2878 скрытых деталей** (Transparency=1).
- По тому же принципу плейс раздут и другими проходами: `ArtOriginalColor/Material` (19 296 × 2, `MapArtDirection`, тоже никем не вызывается) и `PlotBase*` (10 952 × 4, `PlotAppearance.remember`). Всего в Workspace **114 351 атрибут на 24 243 инстансах**. Они реплицируются каждому клиенту.

**Этапы 1–2 этого репозитория строят мир во время выполнения:**
- `ServerScriptService/MiningWorld.server.luau` — эталонный образец. `build(yard)` идемпотентен по `LayoutVersion` (=24): совпало — переиспользуем, иначе `Destroy()` и пересборка. Корню ставится `ModelStreamingMode=PersistentPerPlayer` и вызывается `AddPersistentPlayer(owner)`, оба в pcall с warn. Детали создаются через `ReplicatedStorage/Mining/MiningModels.Part`: Anchored, без коллизий/касаний/запросов по умолчанию. Привязка к якорям участка: `YardFoundation`, `StorageAnchor`, `DigSlot_1`. Кучи руды рисует клиент (`MiningClient/World`), переживает StreamingEnabled (коммит 9b89b12: «модель приходит раньше деталей, никогда не сдаваться на WaitForChild»).
- `ReplicatedStorage/PlotAppearance.Apply`. Кэш токена `level:skin` в памяти; если он изменился, `PlotDevelopment` уничтожается и строится заново.
- `Economy/BestFinds.Reconcile` и `Economy/PlotShowcase.Reconcile`. Диф по токену на слот (`ExhibitToken`), клон пересоздаётся только при изменении.
- `DogLineSpawner`: клоны конвейера `Atomic`, детали приварены к якорному корню (`weldToRoot`), чтобы реплицировался один CFrame на объект, а не ~100.
- Клиентские строители эффектов: `SecretAura`, `Lucky*FX`, `WorldEventSpectacle/Cataclysm`, `MiningClient/FX`.

**Рекомендуемый шаблон для новой геометрии** (гигантская колба лаборатории, стенды витрины, шахта глубины, косметика):
1. **Чистый модуль раскладки** `ReplicatedStorage/<Feature>/<Feature>Layout.luau`. Возвращает массив спецификаций `{Class, Name, Size, CFrame (относительно якоря), Color, Material, Props}` без Instance API. Его можно тестировать в Lune: число деталей не выше бюджета, всё внутри рамки участка, Y ≥ −80, детерминизм.
2. **Общий тонкий строитель** `ReplicatedStorage/World/Builder.luau`, обобщение `MiningModels.Part`. Собирает модель **отдельно от мира** и выставляет `Parent` одним действием. Атрибуты корня: `BuilderId`, `LayoutVersion`, `PartCount`. Идемпотентен по `LayoutVersion`, как MiningWorld.
3. **Стриминг корня.** `Atomic` для мелких цельных объектов до ~200 деталей: стенд, статуя, декор. `PersistentPerPlayer` плюс `AddPersistentPlayer(owner)` для интерактива владельца. Default/Nonatomic для больших зданий.
4. Привязка к якорям из плейса: `05_MutationLab/InteractionAnchor`, `EntranceAnchor`, `NavigationAnchors`, якоря двора. Размеры проверять, как `assert(shop.Architecture.ShopFloor.Size.X==40)` в установщике, но в рантайме — `warn` и пропуск, без ошибки.
5. Старую геометрию скрывать обратимо **без** атрибутов-оригиналов: держать серверную таблицу оригиналов или один флаг, как `CoveredByMiningCorner`.
6. **Тяжёлые декоративные детали строит клиент**: стекло и жидкость в колбе, энергия, частицы, стрелки пути. Папка только для клиента **вне** `DOGROTS_District`, например `workspace.DOGROTS_ClientFX/<Feature>`. Логикой управляют атрибуты небольшого реплицируемого якоря — так устроены кучи руды MiningClient.
7. Сервер не двигает детали каждый кадр. Если без этого никак, применять `weldToRoot`.
8. Клиентские детали: `CanCollide/CanQuery/CanTouch=false`, у мелких `CastShadow=false`. Коллизии строит только сервер.
9. Регистрация через CollectionService-теги (`GetInstanceAddedSignal` переживает стриминг, пример — `WorldSignController`), а не через новые `DescendantAdded` по всему Workspace.
10. В лог печатать `print('DOGROTS_<FEATURE>_READY', ...)`, как прочие системы.

Почему не делать новые Edit-установщики: владельцу пришлось бы запускать их руками, базовый плейс пришлось бы заново импортировать в `place/`, атрибуты раздуют плейс, а в Lune их не проверить. Почему не учить rbxl.py писать Part: нужны кодеки CFrame, Ref, OptionalCFrame, PhysicalProperties, Color3uint8 и прочих типов. Это объём L/XL и риск испортить плейс; сейчас не рекомендуется.

### 4. Данные плейса: детали по зонам (сборка)

| Зона | Инст. | Деталей | Невидимых | Скрыто установщ. | Тень (видимые) | Neon | Glass | Свет | Эмиттеры | SurfaceGui |
|---|---|---|---|---|---|---|---|---|---|---|
| 04_PlayerYards (8 дворов × 1430 деталей) | 12 453 | 11 444 | 1548 | 0 | 3816 | 64 | 64 | 64 | 0 | 232 |
| 06_DogDexMuseum | 10 284 | 9523 | 603 | 491 | 2397 | 377 | 78 | 42 | 0 | 237 |
| 02_DogFactory | 3152 | 3110 | 3 | 0 | 3013 | 24 | 0 | 16 | 2 | 0 |
| 37_AttractionRefresh | 1921 | 1730 | 9 | 0 | 920 | 65 | 7 | 5 | 0 | 24 |
| 32_WelcomeHub | 1892 | 1682 | 61 | 39 | 474 | 48 | 14 | 26 | 0 | 19 |
| 08_GlobalDigSite | 1339 | 1170 | **1170** | **1170** | 0 | 41 | 1 | 23 | 0 | 34 |
| 13_TheVoid (Persistent) | 1140 | 1018 | 36 | 0 | 655 | 321 | 0 | 11 | 11 | 0 |
| 05_MutationLab | 1082 | 983 | 9 | 1 | 472 | 307 | 54 | 13 | 0 | 23 |
| 36_DistrictRefresh | 906 | 825 | 727 | 727 | 15 | 11 | 0 | 6 | 0 | 30 |
| 01_IslandAndStreets | 742 | 692 | 7 | 7 | 593 | 23 | 0 | 23 | 0 | 0 |
| 11_Shops | 537 | 422 | 84 | 74 | 131 | 12 | 18 | 10 | 0 | 25 |
| 27_RewardMachinePlaza | 451 | 371 | 370 | 369 | 1 | 41 | 0 | 8 | 0 | 14 |
| **Workspace всего** | **37 586** | **34 287** | **4662** | **2878** | **12 826** | 1567 | 236 | 294 (0 с тенью) | 13 | 644 |
| ReplicatedStorage | 10 305 | 3794 | | | | | | | | |
| StarterGui/ScreenGui | 3106 | | | | | | | | | |

- Подробно в ReplicatedStorage (уходит каждому клиенту при входе): `MenuModels` 5294 инст. (101 собака, **дубликат** `ServerStorage/DogTemplates`, в том числе 468 MeshPart); `DiscoveryModels` 3334 (108 моделей, 3225 деталей, до **105 деталей** на предмет); `DogAnimationClips` 1559 ModuleScript.
- `StarterGui/ScreenGui` (`ResetOnSpawn=false`): 617 `UITextSizeConstraint`, 587 `UIStroke`, 571 `TextLabel`, 505 `UICorner`, 476 `Frame`, 4 `ViewportFrame`.
- Высоты: дворы Y 0…18, остров уходит до Y −42, `DistrictSafety` возвращает игрока при Y < −85, `FallenPartsDestroyHeight=-250`. Это **жёсткое ограничение для F5**.
- Освещение: `Technology=Future`, `GlobalShadows=true`, Bloom и ColorCorrection включены, DoF выключен. Цикл дня (`LightingConfig.DayCycle={Enabled=true,Minutes=30}`): сервер раз в секунду шагом меняет `ClockTime`.
- `Players.MaxPlayers=60` в файле, а дворов 8. Реальный размер сервера задан в Creator Hub, проверить не удалось.

### 5. Стриминг

- `Workspace`: `StreamingEnabled=true`, `StreamingMinRadius=64`, `StreamingTargetRadius=1024`; `StreamingIntegrityMode`, `StreamOutBehavior` и `ModelStreamingBehavior` стоят в **Default**.
- Persistent-модели в файле: `NavigationAnchors`, `13_TheVoid` (вместе с `DistantVoidAtmosphere`), `37_AttractionRefresh.RewardMachineRig`, `03_DogLine…BeltEndPortal`. Режимы, которые ставит рантайм: `MiningCorner` PersistentPerPlayer, клоны конвейера Atomic. У всех 1200 моделей `LevelOfDetail=Automatic`, `StreamingMesh` нигде не задан. `RequestStreamAroundAsync` в коде не используется.
- Вывод: при радиусе 1024 на острове около 430×1020 и выгрузке по умолчанию (только при нехватке памяти) практически весь район загружен у всех. «Не грузить шахту целиком» (F5) одной галкой StreamingEnabled не решить. Нужны клиентская сборка уровней (как кучи руды) и/или осознанная смена `StreamOutBehavior` и радиусов. Поменять их может только владелец в Studio или расширенный build.py; это изменение настроек плейса.

### 6. Что работает каждый кадр

**Клиент (StarterPlayerScripts и StarterGui), постоянно:**

| Скрипт | Цикл | Стоимость и замечания |
|---|---|---|
| `DogAnimations.client` + `ReplicatedStorage/DogAnimationPlayer` | `PreSimulation`, каждый кадр | Самый тяжёлый, но уже оптимизирован: отсечение по пирамиде видимости (`viewHalfAngle`, `NEAR=30`), шаг 1/3/8 кадров (>160/>320 studs), `PumpPreload(1)` — один декод клипа за кадр, метки `debug.profilebegin`. Образец для LOD. |
| `SecretAura.client` | `RenderStepped`, каждый кадр, ауры через кадр | **Нет отсечения по дистанции** для самой ауры: обновляются все секретные собаки. У витрин каждый кадр вызывается `GetBoundingBox`, создаются `ColorSequence.new` и таблица `a.Row`. PointLight аур лежат вне района и в бюджет `WorldDetailQuality` не входят. Highlight ≤ 6. |
| `WorldSignController` | RenderStepped с аккумулятором | По тегу `ManagedWorldSign` |
| `DistrictWorldMotion` | 30 Гц, отсечение 800 studs | Анимация по атрибуту `Motion=Ring/Belt/Hoist/Float/Drone/Pulse` через `PivotTo` |
| `PlotSkinMotion` | 30 Гц | `PlotFloat`/`PlotMist`; **конфликтует с WorldDetailQuality** за `ParticleEmitter.Enabled` |
| `VoidAtmosphere` | 10 Гц | Если игрок ближе 1800 studs (то есть почти всегда, от спавна около 1230), 4 модели (128 деталей) двигаются через `PivotTo`, raycast, запись Transparency/атрибутов каждый тик |
| `WorldDetailQuality` | 2.5 Гц | См. раздел 7 |
| `ExpressMotion` 12.5 Гц, `ShopInteriorPrompts` 10 Гц, `LabPrompt`/`PlotPrompts` 6.7 Гц, `MuseumPresentation` 3.3 Гц, `GlobalDigPresentation` 2 Гц, `DistrictGuide` 5 Гц, `PawpadRuntime` 2 Гц, `BuffHUD` 4 Гц | с прореживанием | Дёшево |
| `InventoryController` | 2 Гц `padPrompts()`, то есть 8 дворов × слоты, **даже когда инвентарь закрыт**; `scheduleRefresh` раз в 6 с | При открытом инвентаре каждое `InventoryRevision++` (каждый `Runtime.Project`) вызывает **полный `Snapshot` через InvokeServer**, не чаще раза в 1.5 с |
| `MoneyController`, `HUDStatsController` | Heartbeat только пока идёт счётчик, потом Disconnect | Хорошо |
| `SpiderdogAnimation` | RenderStepped | Мёртвый: модели `DOG_097_SPIDERDOG_MODEL` в плейсе нет, скрипт выходит сразу |
| `LocalScript` (без имени) | разово | **Отладочный остаток**: print языка, `GetTranslatorForLocaleAsync` без pcall, через 3 с проходит по PlayerGui |

**Слушатели `DescendantAdded` по всему миру.** Каждый новый или подгруженный инстанс проходит цепочку обработчиков:
- `workspace` целиком: `DOGROTS_AutoTranslateUI`, `PlaceTypography`, `LuckyBlockFX`;
- `DOGROTS_District`: `WorldDetailQuality` (с проходом по предкам `ownedByLucky`), `DistrictWorldMotion` (`task.defer` на **каждый** инстанс), `PlotPrompts`, а на сервере `DistrictDoors`;
- `04_PlayerYards`: `PlotSkinMotion` (`task.defer` на каждый), `SecretAura`;
- PlayerGui: `UITheme` (jump и font), `DOGROTS_RU_ScreenPatch`, AutoTranslate, PlaceTypography.

При входе по этой цепочке проходят около 34 тыс. деталей; потом через неё проходит каждый объект новых фич, которые строят геометрию в районе.

**`DOGROTS_AutoTranslateUI`, 2686 строк, корни `{PlayerGui, workspace}`:**
- На каждый TextLabel/TextButton/TextBox — своё соединение `GetPropertyChangedSignal`, при любой локали.
- На RU-локали при каждом изменении текста с латиницей идёт проход по ~110 gsub-шаблонам (`patterns`) и ~440 `find` (`phrases`). Результат прохода **не кэшируется**: кэшируется только «целая строка → она же».
- `cache[source]=source` для каждой уникальной динамической строки, например `$1.2M` или таймеров. **Таблица растёт без ограничений**, очищается только в `reloadLocale`.
- Обход стоит экранам с `NoTranslate` (Kit, Mining, UpgradeTree, Lab, Dogs) и `KeepFont` для шрифта.

**Сервер:**
- `Economy/Runtime` — цикл раз в 1 с (`Config.TickSeconds=1`): `TickAll` по «должникам», автосейв 60 с, особые находки 10 с, рекорды 5/30/60 с, сторожевой таймер 5/20 с.
- Каждый `Runtime.Project`, то есть каждый тик, когда игроку пора, а это бывает каждые 1–2 с при цикле собаки 10–34 с, делает следующее:
  - пишет около 40 атрибутов игрока и все поля каждой собаки в `DogInventory`;
  - `JSONEncode(OwnerHistory)` для **каждой** собаки;
  - `InventoryRevision++`;
  - `PlotDevelopment.Reconcile`, `BestFinds.Select` (полный проход по `p.Items`), `Kennels.Reconcile`, `PlotShowcase.Reconcile`.
- `DogLineSpawner` на Heartbeat двигает каждую сущность конвейера (сварены — один CFrame; Lucky-блоки с `LuckyFloat` не свариваются) и пишет `LineExitAt` каждый кадр (значение меняется раз в секунду).
- `MovementModifiers` 10 Гц, `DistrictDoors` 20 Гц, `DistrictSafety` 4 Гц, `WorldEventService` и `WorldEventGameplay` 1 Гц, `NavigationSync` 1 Гц, `LightingController` 1 Гц, `MiningWorld` 1 Гц. Всё O(игроков или объектов).

### 7. Есть ли система качества и LOD

**`WorldDetailQuality.client`** — единственный общий бюджет, только для света и частиц, без LOD геометрии. Раз в 0.4 с делает следующее:
- проходит по всем `Light` в `DOGROTS_District`, сейчас 252 под управлением (42 `MuseumLight` и `LuckyVisual` исключены);
- ставит `Shadows=false`, **выключает все**, затем включает ближайшие 24 в радиусе 160 studs (на Low — 8 в радиусе 85);
- **урезает `Rate` каждого `ParticleEmitter` района до ≤8/с (на Low ≤2/с) при общем бюджете 50 (на Low 8)**, дальше 210/90 studs выключает.

Последствие: любой новый эффект внутри района (колба, витрина, косметика) будет молча урезан, а его свет погашен. Работают только `Emit()`-всплески, которые от `Rate` не зависят, или объекты вне района.

**Признак «низкого качества» продублирован примерно в 12 местах, и логика расходится.** Читатели: `WorldDetailQuality`, `VoidAtmosphere`, `ExpressMotion`, `SecretAura`, `SecretArrivals/Kit`, `Lucky/LuckyShow`, `MiningClient/FX`, `RewardMachineWorldFX`, `LabPresentation`, `MuseumPresentation` (через `SavedQualityLevel ≤3`), `WorldEventSpectacle`, `WorldEventCataclysm`.
- Атрибут `WorldEventFX` (High/Medium/Low) переключает настройка PAWPAD (`PawpadRuntime`). Он не сохраняется, живёт одну сессию.
- `WorldEventController` при nil ставит телефонам **Medium**. Из-за этого ветка `(WorldEventFX==nil and TouchEnabled)` в WDQ и VoidAtmosphere почти никогда не срабатывает: телефоны получают полный бюджет High, а итог зависит от порядка запуска скриптов.
- Атрибут `LowFX` читают 12 скриптов, а **не ставит никто**.
- `Kit/Motion` берёт `GuiService.ReducedMotionEnabled`, а не атрибут `ReducedMotion` из настроек PAWPAD.
- Готовая таблица бюджетов уже есть: `WorldEventConfig.FX = {High={Particles=64,Debris=52,Dogs=14}, Medium={28,24,8}, Low={4,8,3}}`.

**Пулы.** Есть `MiningClient/FX` (плавающий текст, ≤16), `EconomyVisuals` («+$X»), `Kit/Virtual` (ячейки списков), `Kit/Preview` (кэш превью: `PerFrame=2`, `MaxFree=48`, статистика Built/Reused/Evicted). **Общего пула 3D-объектов нет.** Найденные предметы в мире (`EconomyVisuals` → `DiscoveryVisuals.Clone`) клонируются заново на каждую находку, одновременно ≤4, у каждого свой Highlight, Debris через 6–14 с.

**Highlight.** Бюджеты у каждой системы свои (`SecretAura` 6, `EconomyVisuals` до 4, `Lucky*`, `LabPresentation`, `WorldEventSpectacle`…). Общего ограничения нет, а у движка лимит около 31 одновременно.

### 8. Главные риски производительности, утечки и баги

1. **WorldDetailQuality гасит новые эффекты**: ≤8 частиц/с на эмиттер и 24 источника света в районе. **PlotSkinMotion и WDQ спорят** за `Enabled` у `PlotMist`: 30 Гц против 2.5 Гц, побеждает последний писавший.
2. **Неограниченный кэш AutoTranslate** — растущая память на RU-сессиях. Тяжёлый проход по шаблонам на каждое изменение текста; соединение на каждый TextLabel в мире.
3. **Цепочки `DescendantAdded`** по workspace и району: всплеск при входе, налог на каждую новую деталь.
4. **SecretAura** без отсечения по дистанции и с `GetBoundingBox` каждый кадр; свет вне бюджета.
5. **Стриминг почти не выгружает**: радиус 1024, Default; `13_TheVoid` Persistent; около 10 тыс. инстансов в ReplicatedStorage при входе (дубликат собак `MenuModels`).
6. **Мёртвый груз**: 4662 невидимых детали (2878 от установщиков, весь `08_GlobalDigSite`), 114 тыс. атрибутов в Workspace.
7. **Сервер, `Runtime.Project` на каждом обновлении**: JSONEncode по каждой собаке, около 40 атрибутов, `InventoryRevision++`. Открытый инвентарь из-за этого тянет полный Snapshot раз в 1.5 с.
8. **Future + GlobalShadows**: 12 826 видимых деталей отбрасывают тень, 236 Glass. Огромная стеклянная колба (F12) стоит дорого.
9. **Нет общего лимита Highlight** на несколько систем.
10. **Звук**: код маршрутизирует в группы `DOGROTS_AUDIO/{Ambient,UI,SFX}`, но в плейсе есть только `Music` и `WorldEvents`. Звуки `WorldAmbience`, `RewardAudio`, `WorldSound` и `LabAudioConfig` идут без SoundGroup, общей громкости SFX нет.
11. **Отладочные остатки**: `StarterPlayerScripts/LocalScript` (print, вызов без pcall); `SpiderdogAnimation` мёртв; `DOGROTS_FindEnglish_TEST` выключен и не лежит в `src`.
12. **Инструменты**: недетерминированная сборка; при удалении src-файла молча возвращается оригинал; в симуляторе баланса нет окупаемости.
13. **Ограничения глубины** для F5: `DistrictSafety` при Y < −85 телепортирует игрока; `FallenPartsDestroyHeight=-250`.

Утечек соединений при выборочной проверке не найдено, кроме AutoTranslate: `originals`/`watching` слабые, но `cache` сильный. Таблицы игроков в `Runtime` чистятся на `PlayerRemoving` (`buckets`, `marketQueries`, `SeenFinds`, `Views`). `DogAnimations` и `SecretAura` отключают обработчики на Destroying/ChildRemoved. Утечку наблюдателя аксессуаров уже исправили (f127ad4).

### 9. Предлагаемый бюджет производительности

| Метрика | High (ПК) | Medium (телефон по умолчанию) | Low |
|---|---|---|---|
| Lua-время клиента на кадр, все системы | ≤ 3 мс | ≤ 4 мс (цель 30+ FPS) | ≤ 4 мс |
| Одна новая фича в установившемся режиме | ≤ 0.3 мс/кадр, со своей меткой `debug.profilebegin` | | |
| Видимые источники света (WDQ + новые) | 24 | 16 | 8 |
| Частицы/с в установившемся режиме, весь район | 64 | 28 | 4 (из `WorldEventFX`) |
| Всплеск «вау-момента» (F12, F7) | ≤ 300 частиц за 4 с, только у вызвавшего игрока и ближайших | ×0.5 | ×0.15 |
| Highlight всего | 8 | 4 | 2 |
| Видимые ViewportFrame | 12 | 8 | 4 |
| Деталей на объект: F4 предмет | LOD0 ≤ 40, LOD1 ≤ 8, дальше 120 studs не показывать | | |
| Деталей на участок: F8 косметика + F3 витрина + F5 видимый уровень | ≤ 300 + ≤ 150 + ≤ 400 сверх текущих 1430 | | |
| F1 путь | ≤ 1 Beam на поворот (≤ 24) + ≤ 40 стрелок из пула | ≤ 28 | ≤ 16 |
| F12 машина мутаций | ≤ 600 деталей, ≤ 6 источников света, ≤ 4 эмиттера постоянно | | |
| Сеть | Нет серверного движения CFrame каждый кадр для новых систем. ≤ 1 запрос на действие игрока. Push-события объединять. Полный Snapshot не чаще раза в 5 с | | |
| Сервер | Без нового Heartbeat. Работа за тик O(игроков), не O(предметов) | | |
| Данные | ≤ 5 КБ на игрока на фичу, без новых ключей DataStore на действие | | |

### 10. Общие помощники для новых фич (предложение)

- **`ReplicatedStorage/Perf/Quality.luau`**, только клиент. API: `Tier()`, `Reduced()`, `Budget(key)`, `Changed`, `SetPreference('Auto'|'High'|'Medium'|'Low')`.
  - Источники: атрибут `WorldEventFX`, `ReducedMotion` + `GuiService.ReducedMotionEnabled`, `UserGameSettings().SavedQualityLevel` (≤3 → Low, ≤6 → Medium), «тач без клавиатуры» → не выше Medium, сторож FPS: на Auto при среднем ниже 40 FPS 10 с снижать на ступень.
  - Таблица бюджетов собирается из `WorldEventConfig.FX` плюс ключи `Lights`, `Highlights`, `Viewports`, `LodNear`/`LodFar`, `Arrows`.
  - **Совместимость**: модуль сам выставляет `LowFX=(tier=='Low')`, и 12 существующих читателей сразу становятся согласованными; `Kit/Motion.Override=Reduced()`.
- **`ReplicatedStorage/Perf/Scheduler.luau`**. Один общий Heartbeat, `Every(hz, name, fn)` с нарезкой по времени (≤ 1 мс на кадр на задачу) и метками profiler. Вместо N отдельных прореженных циклов.
- **`ReplicatedStorage/Perf/Lod.luau`**. `Register(model, {Near, Far, OnLevel=fn(level)})` или тег `DOGROTS_Lod` с атрибутами `LodNear`/`LodFar`. Проверка 5 Гц: дистанция, пирамида видимости (логика из `DogAnimations.viewHalfAngle`), гистерезис ±10 %, не больше 8 переключений за тик. Уровни переключаются через `LocalTransparencyModifier` или перенос в скрытую папку.
- **`ReplicatedStorage/Perf/Pool.luau`**. `Pool.new({Create, Reset, Max, Prewarm, Parent})` → `:Acquire()`, `:Release(o)`, `:Stats()`, `:Destroy()`. Часто используемые объекты (стрелки) остаются в мире и прячутся `Transparency`/`LocalTransparencyModifier`, без смены `Parent`.
- **`ReplicatedStorage/Perf/Maid.luau`**. Вынести `Kit/Maid` в общий доступ для не-UI кода.
- **Интеграция с WDQ**: общий атрибут-исключение `FXManaged=true` на источнике света, эмиттере или предке (вместо подмены через `MuseumLight`). Бюджеты WDQ брать из `Quality.Budget`.
- **PerfProbe**, только Studio: атрибут `workspace.PerfProbe=true` (F6/F7/F8/K/M заняты). Число инстансов по корням, `Stats`-память, данные сети, атрибуты `PartCount` у корней строителей.

### 11. История git и документация

- Ветка `claude/dogrots-major-overhaul-zp7rbc`. Порядок этапа: параллельные ветки worktree `worktree-wf_<id>-<n>` → «Merge stage N branch …» → «Stage N integration: …; rebuild» → ветки исправлений после ревью → «Merge stage N review fixes (…)» → «Rebuild place with the stage N review fixes». Последний коммит — `04b68a8 Back up the place…` (`place/backups/DOGROTS_MINING_5_pre_overhaul.rbxl`).
- Коммиты фич **не трогают `build/`**: в них только `src/`, `docs/<FEATURE>.md` и `tests/<feature>.luau`. Пересборка `build/` (бинарник плюс `build_report.json`) идёт отдельным интеграционным коммитом. Заголовки на английском в стиле «Область: что сделано». В теле — результат проверки («Full check: 107 tests pass, 0 new diagnostics»), трейлеры `Co-Authored-By` и `Claude-Session`.
- Документация: на каждую фичу `docs/<FEATURE>.md` **на русском**. Типичные разделы: где открыть, как работает, баланс (таблицы из симуляторов), данные и сохранения (версии и миграции), «Что изменено в плейсе» (новые и изменённые скрипты), сборка и проверки, звуки и ID ассетов, чек-лист для Studio. Исключение — `docs/UIKIT.md` на английском, справочник разработчика. Картинки лежат в `docs/img/`. Симуляторы экономики и дерева улучшений лежали в scratch вне репозитория (`ECONOMY.md` §11, `UPGRADE_TREE.md` §8).

### 12. Итог

**Что можно улучшить поверх текущей системы:**
- Добавить `Perf/Quality` и через него выставлять `LowFX` и `Kit/Motion.Override`: старые скрипты станут согласованными без правок.
- Добавить в WDQ исключение `FXManaged` и брать бюджеты из Quality. Решить спор PlotSkinMotion↔WDQ: эмиттеры `PlotMist` пометить `FXManaged`.
- Добавить `Perf/{Scheduler, Lod, Pool, Maid}` и `World/Builder` с чистыми модулями раскладки. Новые фичи используют только их.
- В AutoTranslate: LRU-кэш (например, 2000 строк) плюс кэш результатов прохода по шаблонам; по умолчанию `NoTranslate` для окон Kit.
- Оставить заглушки на месте отладочного `LocalScript` и `SpiderdogAnimation`.
- Создавать в рантайме группы `DOGROTS_AUDIO/{UI,SFX,Ambient}`, если их нет.
- `rbxl.py`: детерминированные UniqueId/GUID (sha256 от пути); соглашение «retired» в `build.py`.
- `balance_sim.py`: колонка окупаемости и сценарии цен для F11.
- Новые тесты: `tests/perf_lint.luau` (новые клиентские файлы без своих RenderStepped и DescendantAdded по workspace), `tests/world_layouts.luau` (бюджеты и границы раскладок), `tests/save_compat.luau` с фикстурами старых профилей.
- В `InventoryController`: `padPrompts` только когда инвентарь открыт или по событиям; Snapshot по `Net.Snapshot(maxAge)`.

**Что требует аккуратного рефакторинга:**
- Свести ~12 копий «low/reduced» к `Quality`; заменить слушатели `DescendantAdded` по всему миру на регистрацию по тегам. Затрагивает многие оригинальные скрипты.
- `Runtime.Project`: отслеживать изменения по каждой собаке (без JSONEncode и записи атрибутов каждый раз), `InventoryRevision` только при реальном изменении инвентаря. Затрагивает экономику и UI.
- Убрать 2878 скрытых деталей установщиков и 29 тыс. атрибутов-оригиналов. Сборка не умеет удалять, значит это делается либо в Studio, либо серверной зачисткой при старте по белому списку корней. **Не трогать** `08_GlobalDigSite`, пока не решено, оживлять ли его для F5, и `PlotBase*` (их использует система стадий).
- Ленивая репликация `MenuModels` и `DiscoveryModels` (10 тыс. инстансов при входе).
- Стриминг: `StreamOutBehavior`/радиусы/`ModelStreamingBehavior` — меняет поведение всего плейса, нужен прогон всех WaitForChild-путей.
- Зональный `DistrictSafety` для F5.
- Обучить rbxl.py писать Part (объём XL, не рекомендуется).