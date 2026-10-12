# Приложение к аудиту: списки по подсистемам

Ключевые файлы, сохраняемые поля, remote, объекты мира, точки расширения и найденные баги по каждой подсистеме. Основной текст — docs/OVERHAUL_AUDIT.md.

## Приложение: `data-network` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Хранилище (DataStore или память), экономический цикл раз в 1 с, вход и выход, автосейв 60 с, BindToClose, Request (шлюз DogEconomyRequest: корзина, clean, requestId, ветки), Snapshot, Project (атрибуты, leaderstats, DogInventory, мир), PushTo, рекорды и Global Dig, inbox через MessagingService
- `/home/user/riooblox/src/ServerScriptService/Economy/Transactions.luau` — Run (fast RAM или durable с журналом tx:), Read, Flush/FlushAll/Unload, Suspect/resync, квитанции (2048), резерв supply:, AddCounter, MergeRecords
- `/home/user/riooblox/src/ServerScriptService/Economy/StoreKeys.luau` — Адресация ключей DataStore: длиннее 50 байт → h:<sha256>, метка __LogicalKey против коллизий
- `/home/user/riooblox/src/ServerScriptService/Economy/Engine.luau` — API профиля: Join (замок сессии), Leave, Action, MiningAction, TickAll, BuyLine, GrantSpecial, Trade* (RAM), Records, Authorize
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau` — Схема профиля (Profile), Normalize (мега-сброс, умолчания, нормализация модулей), Validate, Action (диспетчер), формат собаки (Mint/Transfer)
- `/home/user/riooblox/src/ServerScriptService/Economy/FeatureRegistry.luau` — Точка расширения: автозагрузка Features/* с Normalize/Validate/Action/Snapshot
- `/home/user/riooblox/src/ServerScriptService/Economy/Features/Equipment.luau` — Образцовый модуль-фича: p.Equipment, Ensure/Normalize с лечением указателей, Catalogs для Robux, PushTo
- `/home/user/riooblox/src/ServerScriptService/Economy/Features/UpgradeTree.luau` — Образец идемпотентного Normalize с сохранением неизвестных ключей (защита при откате) и проверкой уровня, который показал клиент
- `/home/user/riooblox/src/ServerScriptService/Economy/Features/Passes.luau` — Платные поля (Passes/LuckReserve/ServerLuckCredits), числовые ключи → строки
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — Формат находки (I.Mint), I.Normalize (13 таблиц; стирает Locked), I.Validate (≤1000, D[ItemId])
- `/home/user/riooblox/src/ServerScriptService/Economy/Market.luau` — Рынок и аукционы на durable-ключах reboot1:*, межсерверный inbox, Query
- `/home/user/riooblox/src/ServerScriptService/Economy/PurchaseService.luau` — ProcessReceipt: durable {p:, purchase:}, индекс продуктов, RegisterCatalog, game passes
- `/home/user/riooblox/src/ServerScriptService/Economy/OfflineEarnings.luau` — Офлайн-доход: Join/Checkpoint в каждой транзакции, Claim
- `/home/user/riooblox/src/ServerScriptService/Economy/LeaderboardService.luau` — 7 OrderedDataStore, запись раз в 90 с, чтение раз в 120 с, BindToClose, хук Engine.OnProfileReleased
- `/home/user/riooblox/src/ServerScriptService/Economy/CommunityService.luau` — Король сервера, TOP XP OrderedDataStore, FeedbackRequest (почта через Tx: mailquota/feedback)
- `/home/user/riooblox/src/ServerScriptService/DeveloperInbox.luau` — DataStore DOGROTS_DEVELOPER_INBOX_V1 (16 шардов в день), доступ разработчика
- `/home/user/riooblox/src/ServerScriptService/PlayerDataSetup.server.luau` — Точка входа: Runtime.Start, MuseumService.Start, World.Start
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau` — Version=4, MegaResetVersion=1, SessionSeconds=180, TickSeconds=1, MaxCash, MaxDogs, Layers, Variants (имена — сохранённые данные)
- `/home/user/riooblox/src/ServerScriptService/Economy/YardCommerce.luau` — BulkSell/SellQuote/NPCSell (прямой Tx), проверки посещения, CanSell без защиты избранного
- `/home/user/riooblox/src/ServerScriptService/Economy/LabService.luau` — LabInfo/Preview/Commit: котировка с Token, Signature, Acknowledge, кулдаун; блокируется TradeByUser
- `/home/user/riooblox/src/ServerScriptService/Economy/LabState.luau` — p.Lab Normalize/Validate (Validate требует C.DNA[k] — ловушка запирания)
- `/home/user/riooblox/src/ServerScriptService/Economy/DisplayRules.luau` — p.DisplayDogs: образец ссылок на собственные uid с лечением в Normalize
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningRules.luau` — p.Mining v2: New/Normalize с миграцией v1, OreValue замораживается; PickaxeOwned — позиция в массиве
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Net.luau` — Клиент: Request, Snapshot(maxAge) с общим кэшем, Changed, OnPush(kind)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/MiningClient/Net.luau` — Клиент шахты: Invoke через DogEconomyRequest, состояние из атрибутов Mining*
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Menus.luau` — Старый клиент меню: пустой опрос Snapshot раз в 15 с (L205), Fetch раз в 5 с
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau` — Инвентарь: полный Snapshot на каждое изменение InventoryRevision (не чаще раза в 1,5 с), предсказание BulkSell
- `/home/user/riooblox/tests/payments.luau` — Тесты надёжности: сбои DataStore, гонки чек/автосейв, мега-сброс (образец для новых полей)
- `/home/user/riooblox/tests/economy_loop.luau` — Тест настоящего Runtime.Start: цикл, автосейв, порядок сохранений при выключении
- `/home/user/riooblox/tests/lib/economy_env.luau` — Lune-окружение для запуска настоящих модулей из src (основа новых тестов на миграции)

### Сохраняемые данные

- DataStore DOGROTS_ECONOMY_V1 / p:<UserId> = {Value=<профиль>, Revision, Lock?, Writer?} — запись профиля (Transactions)
- tx:<id> — журнал durable-транзакции {State, Keys, Deadline, Attempt, Writes?, Result, Materialized}; не удаляется
- supply:<DogId> = {Minted}; purchase:<PurchaseId>, support-receipt:<PurchaseId>; event:<week>={Total}; records:<1..5> (глобальные рекорды веса)
- reboot1:book:<assetKey>, reboot1:auctionQueue, reboot1:inbox:<uid>, reboot1:sales:<assetKey>:<day> (рынок); sa:<op>, sl:<uid>:<op>; block-grant:<uid>:<op>, blockacquire:<uid>:<id>; mailquota:<uid>:<day>, feedback:<hour>:<shard>
- DOGROTS_DEVELOPER_INBOX_V1 / day:<date>:<0..15>; OrderedDataStore DOGROTS_LB_*_V2_REBOOT1 (6 штук) и DOGROTS_TOP_XP_V2_REBOOT1
- p.Version=4 (не используется), p.MegaResetVersion=1 (защита мега-сброса, не повышать), p.UserId, p.Created, p.RebootGift
- p.Session={Id=GUID сервера, Expires=now+180, StatsAt} — замок сессии внутри профиля
- p.Cash, p.Bones, p.XP, p.Level, p.Prestige, p.EventTokens, p.Pity, p.LastDig, p.LastSaleAt, p.LastForage, p.TotalExcavations
- p.Dogs{[DogUid]={DogUid,DogId,DisplayName,Rarity,Variant,SerialNumber,Edition,OG,Origin,CreatedAt,Mastery,MasteryXP,AscensionLevel,OwnerHistory[≤100],Ability,PricePaid,OwnerUserId,State,AssignedSlot,NextWorkAt,WorkSequence,FoodDog,Locked?,Favorite?,PaidRandom?,LabRecipe?,LastYield?,...}} ~0,5 КБ на собаку, ≤220 (Capacity) / 250 (MaxDogs)
- p.Items{[ItemUid]={ItemUid,ItemId,Depth,Class,SetId,WeightKg,WeightTier,TierIndex,Mutation,CombinedOdds,SellValue,ValueBreakdown,ValueVersion,Tradeable,Favorite,RecordAtCreation,FoundAt,OriginalFinderUserId,OwnerUserId,IncomeMult?,EventTag?...}} ~0,9 КБ на находку, ≤1000 (HardCap); Locked стирается в I.Normalize
- p.Reservations, p.ItemReservations, p.Listings{listingId=assetKey}, p.TrackedListings(≤50) — эскроу рынка
- p.DisplayDogs{'1'..'3'=DogUid} — стенды собак в DogStorage (DisplayRules)
- p.DogDex, p.VariantDex{[DogId]={[Variant]=true}}, p.DexClaims{'10'=true}, p.DexFavorites
- p.Collection, p.HeavyCollection, p.MutationJournal, p.PersonalRecords, p.ItemSets, p.RecordJobs (только сервер), p.DiscoveryFeed(≤20), p.Loot (устаревшие стопки)
- p.Stats{TotalFinds,TotalDigs,SecretFinds,TotalSellValue,BiggestSale,BestTier,Heaviest,MostValuable,Rarest,BestShowcaseFind,BestShowcaseRelic,Depths,Milestones,Claims,CompletedTrades,...}
- p.Lifetime{TotalPlaytimeSeconds,TotalCoinsEarned,GlobalDigContribution,SupportRobux} — источники лидербордов
- p.Upgrades{[nodeId]=level}, p.UpgradeTreeVersion; p.UnlockedLayers{'1'..'5'=true}, p.CurrentLayer
- p.Mining{Version=2,Strength,PickaxeOwned,PickaxeLevel (позиция в MiningConfig.Pickaxes),WeightOwned,WeightLevel,OreId,OreIndex,OreHP,OreMaxHP,OreValue (замороженная),OreSerial,Hits,OresBroken,CoinsEarned,Collection,...}
- p.Onboarding{Version=3,Status,Step,Seen,Migrated?,CompletedAt?}
- p.Lab{Version=1,DNA{key=n},DiscoveredDNA,Recipes,History(≤40),FirstDiscoveries,Experiments,Tier,LastAt,TutorialComplete,PaidDNA}
- p.OfflineEarnings{Version,PendingCoins,PendingSeconds,Revision,CheckpointAt,Rate,BaseRate,Dogs,Contributors,...}
- p.Cosmetics{[key]=true} (кеннельная косметика + титулы Dex*/Finds*/Set*/Prestige*/Event*/Discovery:*), p.EquippedCosmetic; p.PlotSkins, p.EquippedPlotSkin, p.PlotProgressionVersion
- Платное (переносится мега-сбросом): p.Passes, p.LuckReserve, p.ServerLuckCredits, p.PaidRouletteTickets, p.CommercePurchases, p.Supplies, p.SupplyReserve, p.LuckBoosts, p.Cosmetics, p.Equipment, Lifetime.SupportRobux, платные OwnedBlocks
- p.OwnedBlocks{uid=block}, p.LuckyCredits{tier=n}, p.LuckyOpened, p.LuckyPity, p.BlockOpenReceipts/Order(≤32), p.RouletteTickets, p.NextRouletteTicketAt, p.RouletteReceipts, p.RewardHistory(≤12)
- p.Equipment{Version,Next,Rev,Artifacts(≤120),Accessories(≤80),CaseCredits,Seen,Pity,Opened}
- p.Event{Week,Contribution,Claims}, p.DailyRewards{LastDay,Streak}, p.PlaytimeRewards{Day,Accumulated,StartedAt,Claims,Session}, p.SpecialDiscoveries, p.DogIncome{Total,XPCoins,XPAt}
- p.WorldEventsSeen{[EventId]={FirstSeen,Rarity}}, p.WorldEventClaims{Generation,Count,Objects}, p.NextWorldEventCollect, p.WorldEventRewards
- Замеры: новый профиль 2,3 КБ; 30/60 ≈ 103 КБ; 60/300 ≈ 345 КБ; 220/1000 ≈ 1,16 МБ; защита размера 3,5 МБ (Runtime.luau:37)

### Сеть

- ReplicatedStorage.DogEconomyRequest (RemoteFunction, в плейсе) C→S (action, args, requestId32hex) → ok, result[+StateSnapshot|StatePatch|MiningTargets]; сервер Runtime.Request; клиенты Modules/Net, MiningClient/Net, GUIIntegration, OnboardingGuide, Menus, ServiceMenusController, PawpadController, InventoryController, YardPageController, MuseumPresentation; корзина 8 токенов / 1,5 в секунду
- ReplicatedStorage.DogEconomyOpen (RemoteEvent) S→C (page, message): Lab/Trade/Events/RewardMachine/Collector/UpgradeTree/Storage/маршруты магазинов; отправители LabService, YardCommerce, World/ShopInteriorAccess, GlobalDigService, RewardMachinePresentation, Runtime (приглашение в обмен); клиент GUIIntegration
- ReplicatedStorage.DogEconomyPush (RemoteEvent, создаётся в Runtime.Start) S→C (kind, data); Runtime.PushTo; сейчас только 'EquipmentCredits'; клиент Net.OnPush
- ReplicatedStorage.DiscoveryReveal (RemoteEvent) S→C копия находки + LootSpawn (находки моложе 30 с), из Runtime.Project; клиенты EconomyVisuals, InventoryController, YardPageController
- ReplicatedStorage.DiscoveryAnnouncement (RemoteEvent) S→All (item, isGlobal), не чаще раза в 15 с; клиент EconomyVisuals
- ReplicatedStorage.RewardPresentation (RemoteEvent) S→C/All {Cue,Message,Dog,Announcement,Tier,Credits,Count}; около 12 серверных модулей; клиенты GUIIntegration, LuckyReel, LuckyLifecycleFX
- ReplicatedStorage.RewardRequest (RemoteFunction) C→S (action,a): Catalog, CancelBlockOffer, BuyBlock, OpenBlock, PlaceBlock, CommerceProduct, PaidProduct, RewardMachineInfo/Product/Activate (+Roulette*); RewardService; Allow внутри обработчиков
- ReplicatedStorage.DogKennelOpen (RE) S→C slotName / DogKennelRequest (RF) C→S (Assign|Remove, uid, slot) → Runtime.Request; DogKennelService; клиенты GUIIntegration / ServiceMenusController
- ReplicatedStorage.ShelterRequest (RF) C→S (List|Quote|Sell, a) → ShelterService (Allow 1, рядом с приютом)
- ReplicatedStorage.CommunityFeedbackRequest (RF) C→S (Access|Read|Send, a) → DeveloperInbox (Allow 1, рядом с ящиком)
- ReplicatedStorage.FeedbackRequest (RF) C→S {Text,Category,Request} → CommunityService.Submit (Allow 2, квоты, фильтр текста)
- ReplicatedStorage.CommunityOpen (RE) S→C 'Shelter'|'Feedback'
- ReplicatedStorage.MuseumRead (RF, во время работы) C→S () → Catalog.State, пауза 0,1 с, без корзины; MuseumChanged (RE, во время работы) S→C (state, increased)
- ReplicatedStorage.WorldEvents.GetState (RF, Allow 1) / Changed (RE S→All nextState) / Signal (RE S→C|All {Kind=Reward|Hint|Discovered|Signature|EventReward})
- ReplicatedStorage.RewardMachinePresentation (RE, во время работы) S→All cue → RewardMachineAttractionFX
- Только Studio: Mining.MiningStudioControl, WorldEvents.StudioEventControl, StudioSecretArrival (RF); ServerStorage.DOGROTS_HandleReceipt, DogLineSpawner.SpawnLuckyBlock/SpawnDog, WorldEventService.WorldEventDebug (BindableFunction)
- Bindable: RS.LightingRefreshEvent (сервер); ScreenGui.MenuNavigation/NavigateDistrict/ToggleDistrictMap (клиент)
- Неявные каналы S→C: leaderstats.Coins, Bones (IntValue), около 70 атрибутов игрока (Level, XP, Mining*, MiningRevision, InventoryRevision, Tutorial*, ItemCount/Capacity, IncomePerMinute, SupplyExpires_*, LuckExpires_*, EconomyReady...), папка Player.DogInventory (StringValue + атрибуты на каждую собаку) — видны всем клиентам
- MessagingService: DOGROTS_INBOX_V1 {UserId,Source} (доставка с рынка), DOGROTS_WEIGHT_RECORDS_V2 (баннеры рекордов)

### Объекты мира

- Workspace.DOGROTS_District.04_PlayerYards.Yard_01..08 (атрибуты YardId, OwnerUserId; YardService раздаёт 8 участков при MaxPlayers=60)
- Yard.DigSlot_1..5 (атрибуты DigCenter, Unlocked, SlotIndex; потомок DarkExcavation) — RevealExcavation, кеннели
- Yard.YardSpawn, SellAnchor, StorageAnchor, UpgradeAnchor (+InteractionZone) — проверки посещения YardCommerce/PlotInteractionAccess
- Yard.DogStorage.DisplaySlots.Slot1..3 — PlotShowcase (стенды собак, образец для F3)
- Yard.PlotDevelopment.BestFinds.Slots.{Find,Dog,Relic} — BestFinds (автоматическая витрина)
- Yard.MiningCorner.MiningPad — создаёт MiningWorld.server во время работы; проверка дистанции Mining* в Runtime.Request (≤32)
- Workspace.DOGROTS_District.09_DogPark.LeaderboardPlaza — LeaderboardService
- Workspace.DOGROTS_District.32_WelcomeHub.{ServerKingAnchor, DeveloperMailbox.MailboxBody, DogShelter.SellAnchor, AllTimeLeaderboard (необязательно)} — CommunityService/Shelter/Inbox
- Workspace.DOGROTS_District.05_MutationLab (InteractionAnchor через LabAccess.Model) — гейт LabService
- Workspace.DOGROTS_District.11_Shops.*.InteractionAnchor/ShopInteriorZone — гейт PlotDevelopment.VisitShop и ShopInteriorAccess
- Workspace.DOGROTS_District.NavigationAnchors (13 якорей-зеркал, NavigationSync раз в 1 с) — MapRouting, DistrictTravel
- ServerStorage.DogTemplates (101 модель с RootPart) — Engine.AssetReady, DisplayRules, PlotShowcase
- ReplicatedStorage.DiscoveryModels — модели находок (BestFinds через DiscoveryVisuals)
- Players.MaxPlayers=60 / PreferredPlayers=60 в .rbxl; Workspace.StreamingEnabled=true (MinRadius 64, TargetRadius 1024)

### Точки расширения

- FeatureRegistry: новый модуль ServerScriptService/Economy/Features/<X>.luau с {Name, Order, Normalize, Validate, Action, Snapshot, Catalogs} подключается сам
- PurchaseService.RegisterCatalog / Feature.Catalogs(register) — продукты Robux с durable-чеком {p:, purchase:}
- Runtime.PushTo(player, kind, data) + клиент Net.OnPush(kind, fn) — уведомления сервер → клиент без новых remotes
- Runtime.Request — место для гейтов близости и стоимости действий (как DisplayDog→StorageVisit, Lab*, Mining*); предлагается Registry.Gate/Cost/After
- Runtime.Project — проекция в атрибуты и согласование мира (PlotDevelopment/PlotShowcase/Kennels) после каждого изменения профиля
- Snapshot.Features (F.Snapshot) — данные для UI только на чтение
- Tx:Run с ключом не из быстрых (например 'tradelog:<id>') включает durable-журнал и атомарный commit нескольких профилей
- Engine.OnProfileReleased (лидерборды), Engine.Market.OnInbox (MessagingService)
- Bonuses pipeline (ReplicatedStorage.DogEconomy.BonusSources) — статовые эффекты новых систем без правки Rules
- Rules.Normalize — список переноса мега-сброса (L56) для платных полей
- Тестовые окружения tests/lib/economy_env.luau и tests/payments_lib/loader.luau — Lune-тесты миграций и надёжности

### Улучшить поверх

- Увеличивать InventoryRevision только при изменении сигнатуры инвентаря (как MiningRevision, Runtime.luau:96-102), а не в каждом Project (L163)
- ETag для Snapshot: клиент шлёт известную ревизию, сервер отвечает {NotModified=true} (ревизия из Tx.Versions или сигнатуры вида)
- Убрать Snapshot.Dex (~74 КБ статических определений) или облегчить его до списка ID; убрать пустой 15-секундный опрос Snapshot в Menus.luau:205
- Push 'Trade' обоим участникам, 'InventoryPatch' после находок и продаж, 'Showcase', 'TitleEarned', 'EventPass' через DogEconomyPush
- Рынок: стоимость BuyListing/Bid/CancelListing 3 токена + пауза 2 с, чтение Listing через Market:Cached, RefreshAll только при успехе и только для участников
- BulkSell на сервере пропускает Favorite и витринные находки без явного IncludeProtected
- Приглашение в обмен — заявка без блокировки цели; лимит приглашений на пару; уборка просроченных обменов в TradeRequest
- Durable-подтверждение обмена через дополнительный ключ 'tradelog:<id>' в Tx:Run (журнал без переделки Transactions)
- Хуки FeatureRegistry: Gate(player,action,a), Cost(action), After(player,action,ok,result), явный список Actions
- Повтор входа (Runtime.luau:618) и для BUSY и временных ошибок DataStore, а не только для 'another server'
- Не делать FlushEvents (общий ключ event:<week>) при GlobalDigConfig.Enabled=false
- Engine:Records: проверять RecordJobs в Tx.Cache без глубокой копии профиля раз в 5 с
- Project: обновлять атрибуты DogInventory по разнице, OwnerHistory кодировать только при изменении, BestFinds пересчитывать только при изменении набора находок
- MuseumRead через Runtime.Allow вместо паузы 0,1 с
- Refresh после отклонённого действия не нужен (Runtime.luau:453)
- Тест «старый профиль»: фикстуры без поля, с повреждённым полем и с полем будущей версии + круг JSON для каждой новой фичи
- Один серверный модуль, создающий все новые runtime-remotes в RS.DOGROTS_Net (build.py не создаёт remotes)
- Владельцу: Max Players = 8 (по числу участков) в Creator Hub

### Аккуратный рефакторинг

- Transactions fast-путь: две полные глубокие копии профиля на транзакцию (L454 и L172) плюс копия в Read. Перейти на copy-on-write по ключам верхнего уровня или in-place с журналом отката; прогнать payments/economy_loop и проверить, что трансформы не держат ссылок на профиль
- Snapshot = полный профиль на каждое действие или опрос: разбить на доменные виды (Inventory постранично и с ревизией, Dogs, Trade, Lab, Showcase), сделать единый клиентский store на базе Modules/Net и переводить около 10 контроллеров по одному с совместимостью формы
- Player.DogInventory (StringValue и ~25 атрибутов на собаку, реплицируются всем клиентам): оставить минимум или отдавать только владельцу
- Унифицировать прямые Tx:Run (YardCommerce, Shelter, WorldEvent*, Lucky*, Lab, Onboarding, RewardMachine) под API Engine с одинаковыми Authorize/Normalize/Validate/квитанцией/Refresh
- Облегчить схему находки (~0,9 КБ: ValueBreakdown и копии полей определения) с миграцией ValueVersion. Профиль «кита» уменьшится примерно вдвое, но эти поля читают обмены, рынок и отпечатки
- Захардкоженные 5 слоёв (Rules.Action 'Layer' R.Int(a.Layer,1,5), ReadNextRecordDepth 1..5, GrantSpecial '5', ItemRules rareTail clamp, SignatureRules VoidHound), если F5 добавит слой 6+
- Горячие глобальные ключи рынка (reboot1:auctionQueue в каждой операции, sales:* с капом 20000 > 4 МБ) и размер журналов с двумя профилями
- Ловушки валидаторов (D[DogId], D[ItemId], C.DNA[k], скин): нужна политика «ID только добавляются» + Normalize, который мягко лечит выведенные ID вместо отказа Validate

### Найденные баги

- [Высокая, производительность и трафик] Runtime.luau:163 безусловно увеличивает InventoryRevision в каждом Project (каждый тик с работающими собаками) → InventoryController (раз в ≥1,5 с), ServiceMenusController, UpgradeTreeScreen и серверный EquipmentWorld пересчитываются; открытый инвентарь скачивает полный Snapshot (100 КБ–1,2 МБ) каждые ~1,5–3 с
- [Высокая, CPU] Transactions._runFast делает две глубокие копии всего профиля (L454 copy, L474→_captureProfile L172 copy), Tx:Read ещё одну; замер в Lune: Run 6/15/43 мс и Read 3/9/21 мс для 60/300/1000 находок; MiningHit (до 6 в секунду) = одна fast-транзакция на удар
- [Средняя-высокая, бюджет DataStore] BuyListing/Bid/CancelListing стоят 1 токен; каждое делает некэшированный GetAsync (Market.luau:32 Tx:Read(bk)) до проверок, а провалившиеся внутри транзакции попытки проходят полный журнал tx: и вызывают RefreshAll (Runtime.luau:452); один клиент может съесть ~90 GetAsync в минуту, и тогда тормозят автосейвы и входы
- [Средняя, целостность] Обмен подтверждается fast-транзакцией по двум профилям (Engine.luau:325), а на диск они пишутся отдельно (FlushAllProfiles): падение сервера между сохранениями удваивает или теряет собак, находки и монеты
- [Средняя, гриферство] Engine:TradeRequest сразу записывает TradeByUser для цели (L284): до 240 с цель не может продавать (YardCommerce.luau:50) и пользоваться лабораторией (LabService.luau:23); приглашения повторяемы и каждый раз открывают окно через DogEconomyOpen; просроченный обмен не убирается до Snapshot/Trade (L279)
- [Средняя, потеря данных по ошибке] BulkSell не защищает Favorite (YardCommerce.CanSell L40-44); ItemLock отключён, а I.Normalize стирает x.Locked у всех находок (ItemRules.luau:24) — защита есть только на клиенте
- [Средняя, запирание] Validate без лечения: Rules.Validate D[d.DogId] (L558), I.Validate D[x.ItemId] (ItemRules.luau:279), LabState.Validate C.DNA[k], PlotRules.Validate skin. Удаление ID или DNA-ключа из конфига → Join падает → владелец получает кик при каждом входе
- [Средняя, трафик] Menus.luau:205 скачивает полный Snapshot раз в 15 с при закрытых меню; Snapshot.Dex (Runtime.luau:347) везёт ~74 КБ определений, которые уже есть в ReplicatedStorage; каждое действие возвращает полный StateSnapshot (L464)
- [Средняя, трафик и CPU] Player.DogInventory: StringValue и ~25 атрибутов на каждую собаку под Player (реплицируются всем клиентам); Project перезаписывает их и делает JSONEncode(OwnerHistory) по каждой собаке на каждом Project (Runtime.luau:125-133)
- [Низкая-средняя, конфиг] Players.MaxPlayers=60 в .rbxl при 8 участках (YardService): игроки с 9-го получают WaitingForYard и не проходят проверку Mining* (Runtime.luau:393)
- [Низкая] Повтор входа срабатывает только на текст 'another server' (Runtime.luau:620): 'Account busy' и временные ошибки DataStore кикают сразу
- [Низкая] Global Dig выключен, но FlushEvents пишет общий ключ event:<week> раз в 30 с с каждого сервера (Runtime.luau:713)
- [Низкая] Engine:Records (L362) раз в 5 с копирует профиль каждого игрока только ради проверки пустоты RecordJobs
- [Низкая] Лимит журнала продаж #h<20000 (Market.luau:121) больше 4 МБ на ключ; журнал рыночной транзакции содержит целые профили, книгу и историю и у «китов» может упереться в защиту 3,5 МБ
- [Низкая] Кэш квитанций RAM общий на сервер, 2048 записей (Transactions.luau:60): идемпотентность fast-действий только «по возможности»
- [Низкая] После отклонённого (не упавшего) действия всё равно выполняется Refresh или RefreshAll (Runtime.luau:452-453)
- [Низкая] MuseumRead: до 10 запросов в секунду без общей корзины (MuseumService.luau:20)
- [Инфо] p.Version=4 нигде не используется; FeatureRegistry молча пропускает модуль с упавшим require; прямые Tx:Run пропускают Normalize/Offline.Checkpoint (неоднородно)

## Приложение: `economy` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau` — Authoritative economy constants: StartingCash, MaxCash, Power/Prices/Weights by rarity, Layers+LootValueScale (dog loot per layer), Upgrades, BoostPricing.LayerScale, Supplies, LuckTiers, Cosmetics, XP curve, Prestige, rewards; requires MiningConfig as C.Mining
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/MiningConfig.luau` — Active mining tables: 12 ores (ValueMin/Max, HP, Weight), 7 pickaxes (Price/Strength/Damage/Circles/CoinBonus), 7 weights, LayerValue={1,3,6,12,24}, HitShare. Primary F11 edit target
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningRules.luau` — Pure server-authoritative mining rules: RollOre (value fixed at roll, x LayerMult of deepest layer), Hit payout via ctx.Credit, BuyPickaxe/BuyWeight/Train, v1->v2 migration
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau` — Profile create/normalize/validate, R.Dig (dog income), Cooldown/RollMultiplier/LootLuck, R.Credit/R.Pay, R.MiningAction ctx (Layer=MaxUnlockedLayer), R.Action (Layer unlock, Supply/Luck quotes, Cosmetic, Prestige, rewards)
- `/home/user/riooblox/src/ServerScriptService/Economy/IncomeModel.luau` — Expected income model mirroring Rules.Dig; source of HUD IncomePerMinute, DogStats, OfflineEarnings.Estimate and therefore boost/Robux/case prices. Excludes mining
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Bonuses.luau` — Stat pipeline (12 keys incl. unused DepthSpeed), auto-loads BonusSources/*, ValueFactor
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/BoostPricing.luau` — Income-following prices: Boost (IncomeShare), Coins{MinCash,IncomeMinutes}, Floor by LayerScale, peak-rate tracking (anti-bench)
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/UpgradeTree.luau` — 38-node / 11-branch tree, costs/gates/values; feeds Bonuses via BonusSources/UpgradeTree; full tree 96.47B coins + 14,245 bones
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — Discovery chance, mutations, Mint (fixes IncomeMult and SellValue at find), ExpectedFind; dead I.NPCValue
- `/home/user/riooblox/src/ReplicatedStorage/ItemValuation.luau` — Single item price formula V.Price (used live at NPC sale) and V.Expected (income model); local rarityOf
- `/home/user/riooblox/src/ReplicatedStorage/ItemValueConfig.luau` — Item valuation coefficients, Version=6: Rarity thresholds/multipliers, Depth, BaseScale, WeightTier, Mutation multipliers, soft cap
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DepthDefinitions.luau` — 5 depths: names, IncomeReference (item soft cap), item id lists per depth (JSON-style data)
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/ItemDefinitions.luau` — 108 discovery item definitions (BaseValue, BaseDropChance, Depth, Class, WeightProfile)
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DogDefinitions.luau` — Dog roster; BasePrice=C.Prices[rank], LinePrice for Secrets, PowerBudget
- `/home/user/riooblox/src/ServerScriptService/Economy/Engine.luau` — Transactions per action: TickAll, MiningAction fast path, BuyLine (conveyor), Roll, Trade (RAM trades, Offer Estimated at lines 297-306), GrantSpecial
- `/home/user/riooblox/src/ServerScriptService/Economy/Market.luau` — Cross-server market/auction: listings, 1% fee, 5% tax, inbox settlement, Query with Median24h/7d from sales journal
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Network entry DogEconomyRequest, rate limits, arg cleaning, mining distance check (MiningCorner/MiningPad <=32 studs), Snapshot (full profile copy + IncomeModel), attributes/leaderstats projection, DataStore DOGROTS_ECONOMY_V1
- `/home/user/riooblox/src/ServerScriptService/Economy/OfflineEarnings.luau` — Offline income (20%, 2h, MaxPendingCoins 50B) and BaseRate/PeakRate used by BoostPricing
- `/home/user/riooblox/src/ServerScriptService/Economy/YardCommerce.luau` — Collector sales: SellQuote/NPCSell/BulkSell with live ItemValuation.Price
- `/home/user/riooblox/src/ServerScriptService/Economy/SupplyRules.luau` — Boost timers and paid reserve (MaxSeconds 1h active, PaidCap 6h)
- `/home/user/riooblox/src/ServerScriptService/Economy/FeatureRegistry.luau` — Extension point: Features/*.luau modules with Normalize/Validate/Action/Snapshot
- `/home/user/riooblox/src/ServerScriptService/Economy/StoreKeys.luau` — DataStore key encoding (50-byte limit, sha256 addresses, logical-key marker)
- `/home/user/riooblox/src/ReplicatedStorage/PlotCatalog.luau` — Yard stages (Plot upgrade) and plot skins with fixed Cash (x5) / event+goal gates; F8 baseline
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotRules.luau` — Plot skin buy/claim/equip (direct p.Cash decrement), kennel gating
- `/home/user/riooblox/src/ReplicatedStorage/LabConfig.luau` — Lab costs (Mutation Cash 5000 + 1500/rank, 5 bones/rank), stability; F12 pricing baseline
- `/home/user/riooblox/src/ReplicatedStorage/LabGenetics.luau` — G.Cost (reroll price), G.Chances (variant odds with targeting)
- `/home/user/riooblox/src/ServerScriptService/Economy/LabRules.luau` — Lab preview/apply; Mutation reroll uses R.VariantRows(p) and may downgrade variants
- `/home/user/riooblox/src/ServerScriptService/WorldEventService.luau` — World-event pickups: fixed 40 Cash + 2 Bones + item mint (F7 reward hook)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau` — DOG_RUSH modifiers (DigSpeed .15, Recovery .05, LineSpeed/LineLuck)
- `/home/user/riooblox/tools/balance_sim.py` — Mining balance simulator (reads MiningConfig, prints coins/min per pickaxe x layer); stale dog-income reference line
- `/home/user/riooblox/tests/mining_rules.luau` — 17 mining tests, relational only (monotonic prices, strength gates, Voidbreaker <=2 hits, LayerValue scaling)
- `/home/user/riooblox/tests/income.luau` — Income/pipeline tests; per-key case table lines 324-337 must gain any new Bonuses key
- `/home/user/riooblox/tests/lab.luau` — Pins lab costs (6500 Cash / 5 Bones for rank 1 mutation, 11500 targeting, 2750 extraction, 75000 ascend)
- `/home/user/riooblox/docs/MINING.md` — Mining design doc with ore/pickaxe/weight/coins-per-min tables and the 0.6-1x principle (now outdated)
- `/home/user/riooblox/docs/ECONOMY.md` — Economy doc: income by stage (sections 5, 12), pipeline, offline, pricing

### Сохраняемые данные

- p.Cash: wallet, integer 0..C.MaxCash (9e15); changed only via R.Credit/R.Pay (exception: PlotRules BuyPlotSkin decrements directly)
- p.Bones: secondary currency (tree capstones, lab, cosmetics, Lucky roll)
- p.XP / p.Level: XP curve C.XPForLevel (90*(L-1)^1.65), level gates layers 5/12/22/35, trade at 5, prestige at 35
- p.CurrentLayer (1..5): layer the whole team digs; p.UnlockedLayers {['1'..'5']=true}: deepest contiguous unlocked drives mining LayerValue and boost floors
- p.Upgrades[nodeId]: 6 legacy upgrades (Dig, Storage, Kennel, Plot, DogStorage, Ability) + upgrade-tree node levels; p.UpgradeTreeVersion=1
- p.Prestige: prestige count (cost 12M*(n+1); resets XP/Level/CurrentLayer/Supplies, keeps layers)
- p.Supplies[key]=expiresAt, p.SupplyReserve[key]=paid seconds; p.LuckBoosts / p.LuckReserve (luck tiers)
- p.Mining {Version=2, Strength, PickaxeOwned, PickaxeLevel, WeightOwned, WeightLevel, Hits, OresBroken, CoinsEarned, TrainingReps, OreIndex, OreId, OreMaxHP, OreHP, OreValue (fixed at roll), OreEarned, OreSerial, Combo, BestOre, Collection{OreId=count}, LastHitAt, LastTrainAt, ActiveUntil, TrainingUntil, LastPayout, LastDamage, LastQuality, LastBreak, LastCrit, LastBrokenId, LastBrokenValue}
- p.Dogs[uid] economic fields: DogId, Rarity, Variant (saved names, never rename), Mastery, MasteryXP, AscensionLevel, PricePaid, LastYield, NextWorkAt, WorkSequence, DryStreak, OrbitValue/OrbitCount, AssignedSlot, State, Locked, Favorite, PaidRandom, LabRecipe, OwnerHistory
- p.Items[uid]: discovery instance {ItemId, Depth, Class, WeightKg, TierIndex, WeightTier, Mutation, CombinedOdds, SellValue (mint-time), ValueBreakdown{Version,Rarity,Factors}, ValueVersion (=6), IncomeMult (finder bonus, 0.1..100), SellBonus, FirstFind, EventTag, Favorite, Tradeable, SourceDogUid, RecordAtCreation}; hard cap 1000
- p.ItemReservations, p.Reservations, p.Listings, p.TrackedListings: market escrow / tracking
- p.Collection, p.MutationJournal, p.PersonalRecords, p.HeavyCollection, p.ItemSets, p.RecordJobs, p.DiscoveryFeed (20), p.DexFavorites
- p.Stats (RecordStats): TotalFinds, SecretFinds, TotalSellValue, BiggestSale, CompletedTrades, MostValuable/Heaviest/Rarest, Depths, BestShowcaseFind/Relic
- p.Lifetime {TotalPlaytimeSeconds, TotalCoinsEarned (leaderboard Coins), GlobalDigContribution, SupportRobux}
- p.DogIncome {Total, XPCoins, XPAt}: dog income book for XP pacing
- p.OfflineEarnings {Version=2, PendingCoins (<=50B), PendingSeconds (<=7200), Rate, BaseRate, PeakRate, PeakAt, CheckpointAt, Dogs, Contributors, Revision, Last*}: BaseRate/PeakRate also price boosts, Robux packs, cases, Dogdex coins
- p.Loot: legacy ordinary loot stacks (still sellable via SellLoot)
- p.Cosmetics {key=true}, p.EquippedCosmetic: titles/cosmetics (Finds*, Dex*, Set*, Prestige*, Event*, Discovery:*, shop titles)
- p.PlotSkins, p.EquippedPlotSkin, p.PlotProgressionVersion=1
- p.Event {Week, Contribution, Claims}, p.EventTokens; p.WorldEventClaims {Generation, Count, Objects}, p.NextWorldEventCollect
- p.Lab (LabState: DNA, Recipes, History, TutorialComplete, PaidDNA, LastAt)
- p.Equipment {Rev, Accessories, Artifacts}: bonus sources
- p.DailyRewards {LastDay, Streak}, p.PlaytimeRewards {Day, Accumulated, StartedAt, Claims}
- p.Pity, p.LastSaleAt, p.LastForage, p.SpecialDiscoveries, p.TotalExcavations, p.TreasureMapUntil, p.TimePulseUntil
- p.Version=4 (C.Version), p.MegaResetVersion=1 (never raise without owner decision), p.Session (server lease)
- DataStore DOGROTS_ECONOMY_V1 keys: p:<uid> profile; line:<uid> (ephemeral conveyor order); supply:<dogId> minted counters; event:<week> global dig totals; reboot1:auctionQueue; reboot1:book:<assetKey>; reboot1:inbox:<uid>; reboot1:sales:<assetKey>:<day>; sa:<op> / sl:<uid>:<op> special arrivals; >50-byte keys hashed to h:<sha256[1..48]> by StoreKeys

### Сеть

- ReplicatedStorage.DogEconomyRequest (RemoteFunction, client->server): Runtime.Request(player, action, args, requestId32hex) -> (success, result). Token bucket 8 tokens +1.5/s (MiningHit .25, MiningTrain .5, MarketQuery 3); args cleaned (depth<=3, <=30 keys, strings<=120, |numbers|<=MaxCash). Result carries Message plus StateSnapshot (full profile copy + IncomeModel) or StatePatch (mining/sales)
- DogEconomyRequest actions (economy): Snapshot; MarketQuery (5 s cooldown); Mining* (MiningBegin/End/Hit{Target,Quality,Miss}/Pickaxe{Level}/Weight{Level}/Train/TrainBegin/TrainEnd) with MiningCorner distance check; SellQuote/NPCSell/BulkSell; SellLoot; Supply{Kind,Quote}; Luck{Tier,Quote}; Layer{Layer}; Upgrade/TreeUpgrade (Features.UpgradeTree); Cosmetic{Kind}; BuyPlotSkin/ClaimPlotSkin/EquipPlotSkin{Id}; Prestige; DailyReward; PlaytimeReward{Tier}; DexClaim; SetClaim; RecordClaim; ItemSetClaim; ClaimOffline{PendingId}; List/BuyListing/Bid/CancelListing; Roll{Mode}; EventClaim; TradeRequest{Target}/TradeCancel/Trade{Action=Accept|Offer{Dogs<=6,Items<=6,Cash}|Ready{Version}|Confirm{Version}}; LabInfo/LabPreview/LabCommit; Assign/Remove/DogFavorite/DogLock/ItemFavorite/Forage; Equipment feature actions
- ReplicatedStorage.DogEconomyPush (RemoteEvent server->client, created at runtime by Runtime): push(kind, data)
- ReplicatedStorage.DogEconomyOpen (RemoteEvent server->client): open a page, e.g. ('Trade', 'Trade invitation from X')
- ReplicatedStorage.DiscoveryReveal (server->client: found item payload with LootSpawn), DiscoveryAnnouncement (server->all: rare finds), RewardPresentation (server->client/all: reveal cues, THE DOG arrival)
- Player attributes (server->client replication): IncomePerMinute, Level, XP, XPRequired, Bones, CurrentLayer, LayerName, ItemCount/ItemCapacity/ItemFull, LootFull, PendingCash, DogCapacity, MiningRevision + Mining* attributes (MiningStrength, MiningPickaxe, MiningLayer, MiningOreValue, ...), UnlockedKennels, YardStageName, EquippedPlotSkin; leaderstats.Coins (IntValue)

### Объекты мира

- Workspace.DOGROTS_District.04_PlayerYards/Yard_* (10 children in the place; e.g. 'Yard_02_Copper Corner'): attributes OwnerUserId, YardId, PlotStage, PlotSkin, UnlockedKennels, YardFootprint; children DigSlot_1..5 (kennels), SellAnchor/SellInteractionZone/Vendor (collector for NPCSell), StorageAnchor, UpgradeAnchor/Workshop, YardLandscape (CosmeticGarden hosts the mining corner), LuckyPad_1..3, PlotDevelopment, YardSpawn (verified with a Lune read of build/DOGROTS_MINING.rbxl)
- Yard_*/MiningCorner (Model) with MiningPad: NOT baked in the place (0 instances); built at runtime by ServerScriptService/MiningWorld.server.luau; Runtime.Request requires the player within 32 studs of MiningPad for every Mining* action except MiningEnd/MiningTrainEnd
- Workspace.DOGROTS_District.11_Shops/{UPGRADES, COSMETICS, SUPPLIES, MarketplaceTerminal}: COSMETICS terminal is required for plot skin purchases (PlotDevelopment.VisitShop + ShopInteriorAccess)
- Workspace.DOGROTS_District.05_MutationLab (1082 descendants): lab venue for F12 reroll pricing
- Workspace.DOGROTS_District.08_GlobalDigSite, 06_DogDexMuseum: global dig / Dogdex reward venues (not priced by this subsystem)
- ServerStorage.DogTemplates: dog models used by BestFinds trophies
- Workspace.StreamingEnabled = true (confirmed)

### Точки расширения

- ReplicatedStorage/DogEconomy/BonusSources/*.luau: drop-in bonus sources {Name, Global(p,now,add), Dog(p,d,now,add)} auto-loaded by Bonuses.load(); new stat keys go into Bonuses.Keys (e.g. MiningValue)
- ServerScriptService/Economy/Features/*.luau via FeatureRegistry: Normalize/Validate/Action/Snapshot for new saved systems (Showcase, PlotDecor, Titles, DogRush, Lab 2.0)
- BoostPricing.Coins({MinCash, IncomeMinutes}, p, now) and BoostPricing.Floor/LayerScale: income-following prices and rewards with peak-rate anti-bench protection
- MiningConfig tables (Ores, Pickaxes, Weights, LayerValue) + MiningRules ctx (Layer passed to RollOre): data-only rebalance and per-depth ore mixes
- Config.Layers / DepthDefinitions / ItemValueConfig.Depth/BaseScale / LootValueScale: per-depth resources for F5 (5 depths today)
- UpgradeTree list: add Stat nodes/branches (validated by tests/upgrade_tree.luau)
- ItemValuation.Price / Expected: the single valuation for sale, trade value, showcase ranking; ValueBreakdown.Rarity on items
- IncomeModel.Compute (Rules.IncomeModel): every income number (per-dog CoinsPerMin usable for F12 reroll pricing)
- Market:Query (Median24h/Median7d/RecentSales from reboot1:sales journals): market reference values for F6
- WorldEventModifiers.Resolve / e.EventDepth / EventDepthLuck: temporary rare-zone luck without new layers (F5 rare zones, F7)
- LabConfig.Costs / LabGenetics.Cost: reroll price formula (F12)
- PlotCatalog.Skins fields (Cash, Event, Goal, Stage, Prestige): template for gated cosmetics (F8)
- p.Cosmetics + EquippedCosmetic + RecordStats/Lifetime/Mining counters: achievement criteria for titles (F10)
- Engine:Trade Offer (Estimated, Details, fingerprints): place to attach server-computed trade values (F6)

### Улучшить поверх

- F11 phase 1, data-only in MiningConfig: ore ValueMin/Max x2, LayerValue {1,3,6,12,24} -> {1,3,6,18,48}, Crystal 1.6M->4M, Inferno 12M->60M, Voidbreaker 85M->600M, Crystal Weight 750K->1.5M, Inferno Core 5M->20M, Void Mass 25M->120M; passes tests/mining_rules.luau 17/17 unchanged (verified on a scratch copy)
- Update docs/MINING.md section 3 tables and principle, add an F11 section to docs/ECONOMY.md, refresh the dog-income reference line in tools/balance_sim.py, bump Config.BalanceVersion
- Make fixed rewards income-following with BoostPricing.Coins: world-event pickups (40 Cash today), Dog Rush tiers, optionally daily/playtime rewards (keep MinCash = current values)
- Export item rarity from ItemValuation (V.Rarity(def)) so F3/F4/F6/UI share one rarity ladder instead of re-deriving thresholds (KitDemo already duplicates them)
- Shared pure TradeValue module (items = live ItemValuation.Price, dogs = base price x variant/mastery/ascension, optional market median) used by the server Offer and the trade UI
- Lab reroll price via a LabPricing module (floor x LayerScale or N minutes of income), quoted on preview, charged within 5% on commit (same as Rules.quoted)
- Use the reserved DepthSpeed key only for a cosmetic depth-progress meter (F5) if needed, never as an income gate
- Remove dead I.NPCValue; route PlotRules skin purchases through R.Pay

### Аккуратный рефакторинг

- F11 phase 2: new Bonuses key MiningValue applied in MiningRules.RollOre (fixed into OreValue at roll); requires extending Bonuses.Keys, UpgradeTree.Stats, tests/income.luau case table, tests/upgrade_tree.luau and tests/equipment.luau, docs/UPGRADE_TREE.md counts
- A 6th layer or 'rare zone' as a real economic layer: hardcoded 5s in Rules.luau:480, ItemRules.luau:101-102/111/171, SignatureRules.luau:47, Engine.luau:202, Runtime.luau:275, DiscoveryScreens loops, plus 5-element arrays (ItemValueConfig.Depth/BaseScale, LootValueScale, LayerValue, LayerScale, DepthDefinitions)
- Per-dog depth for F5 (dogs on different levels at once): IncomeModel shape cache keys use p.CurrentLayer, SignatureRules.Context Depth, OfflineEarnings, Snapshot DogStats.MaxDepth; recommended to avoid (keep one team depth)
- Runtime.Snapshot sends a deep copy of the full profile + full IncomeModel after every successful E:Action: move to delta patches or slim views before F2/F6 UIs grow (up to 1000 items)
- Single dog value function shared by client and server (R.Bonus lives in server Rules; Config.Variants is shared) for trade, showcase and lab displays
- Lab reroll to one currency (drop the bones part) and hide Extraction/Fusion/Creation: tests/lab.luau pins costs; DNA balances in p.Lab would be stranded unless converted by a versioned LabState migration
- Unify number formatting (IncomeText.Compact, MiningText.Short, PriceFormat.Number, U.Fmt) into one shared module
- Reconcile stored x.SellValue with live ItemValuation.Price (trade Estimated, BestFinds, RecordStats rank by the stale mint-time value)

### Найденные баги

- Design drift: docs/MINING.md section 3 states that active mining pays about 0.6-1x of dog income at every stage. Simulated with the real MiningConfig against Rules.IncomeModel: 40-49% at L2-L3, 16% at L4, 12-20% at L5 without the tree, 1-3% with the full tree. Mining credits through R.Credit (Rules.luau:124) and ignores the Bonuses pipeline added in stage 2.
- tools/balance_sim.py line 216 prints stale dog-income references ('L2 9k | L3 23-76k | L4 250-420k | L5 0.93-1.4M') that no longer match docs/ECONOMY.md or the current IncomeModel (e.g. 5 Legendary on Cursed = 1.16M/min).
- Trade value inconsistency: Engine:Trade Offer adds the stored x.SellValue (Engine.luau:301, mint-time value) while the collector pays the live ItemValuation.Price(x) (YardCommerce.luau:55/85/98). After an ItemValueConfig change the two diverge. Dogs are valued at LinePrice/BasePrice only (line 306), ignoring variant, mastery and ascension.
- BestFinds.Select and RecordStats (MostValuable, Depths.BestValue) rank by the stored mint-time SellValue, so showcase and record order can be stale against the real sale price.
- Dead code: ItemRules.I.NPCValue (ItemRules.luau:168) is never called and carries its own hardcoded layer scale {1,1,1,.55,.4}.
- Bonuses key DepthSpeed is declared (Bonuses.luau Keys) and tested as a no-op (tests/income.luau:336) but has no consumer.
- Lab reroll price is flat (LabConfig.Costs.Mutation: 5000+1500 x rank Cash, 5 x rank Bones): at most 14K Cash for a Secret against 7.7M-71M/min late income, so the coin sink is ineffective and bones are the only real limiter.
- World-event pickups pay a fixed 40 Cash + 2 Bones (WorldEventConfig.Interactions, WorldEventService.luau:47): negligible after layer 1. Daily and playtime rewards are also fixed (800-28,000).
- PlotRules.Action BuyPlotSkin decrements p.Cash directly (PlotRules.luau:28) instead of R.Pay: no integer/cap validation, inconsistent with every other purchase.
- Runtime.Snapshot deep-copies the entire profile (up to 1000 items, 250 dogs) and runs a full IncomeModel after every successful E:Action (Runtime.luau:332-366 and 457-460): potential network and CPU spikes for large profiles.
- Hardcoded 5-layer assumptions (Rules.luau:480 R.Int(a.Layer,1,5); ItemRules.luau:101-102, 111, 171; SignatureRules.luau:47; Engine.luau:202; Runtime.luau:275; DiscoveryScreens loops) make any extra depth a code change, not a data change.
- Four separate number formatters (IncomeText.Compact, MiningText.Short, PriceFormat.Number, U.Fmt) with slightly different outputs.
- Minor: BoostPricing.Deepest uses the maximum unlocked key while Rules.MaxUnlockedLayer requires a contiguous chain. They are equal in practice because layers unlock in order.

## Приложение: `digging-depth` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ServerScriptService/DogKennelService.luau` — Модели собак в будках (prepare: клон шаблона, Rig.Prepare, посадка на верх DarkExcavation), атрибуты работы (applyWorkState/put), Reconcile на каждый Project, промпт MANAGE (Start:251-262), обработчик DogKennelRequest (Handle)
- `/home/user/riooblox/src/ServerScriptService/DogKennels.server.luau` — Bootstrap: DogKennelService.Start()
- `/home/user/riooblox/src/ServerScriptService/Economy/KennelLootPlacement.luau` — Marker(slot) — Attachment LootSpawn на DarkExcavation; Resolve() — CFrame появления находки для DiscoveryReveal
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau` — R.Profile (CurrentLayer/UnlockedLayers), R.Dig:334 (цикл копания, броски по C.Layers[depth].Loot, находки I.Pick(depth)), R.Assign:432, action Layer:479, Prestige:537, R.MaxUnlockedLayer:127, R.MiningAction:121
- `/home/user/riooblox/src/ServerScriptService/Economy/SignatureRules.luau` — Способности собак; Context:52 задаёт c.Depth=p.CurrentLayer, deeper(), бонусы по слою, своя копия maxUnlockedDepth:44
- `/home/user/riooblox/src/ServerScriptService/Economy/IncomeModel.luau` — Ожидаемый доход (HUD/оффлайн/цены бустов), кэш форм по CurrentLayer и deepest
- `/home/user/riooblox/src/ServerScriptService/Economy/Engine.luau` — Транзакции: Action, MiningAction (облегчённая), Tick/TickAll (R.Dig), EventClaim
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Цикл экономики (loopOnce:691, isDue:685), Project:105 (атрибуты, DiscoveryReveal, Kennels/PlotDevelopment/PlotShowcase reconcile), projectMining:82, Request:367 (ветка Mining*), RevealExcavation:293
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — Pick(depth) по DepthDefinitions, ItemChance (EventDepth), Mint, NPCValue (cap по IncomeReference)
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DepthDefinitions.luau` — 5 глубин: Name, IncomeReference, Items (108 находок)
- `/home/user/riooblox/src/ServerScriptService/Economy/DepthDefinitions.luau` — Прокси на ReplicatedStorage.DogEconomy.DepthDefinitions
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau` — C.Layers (имя, Depth-ярлык, Cost, Level, Color, Loot), C.Work, LootValueScale, Prestige, C.Mining
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/MiningConfig.luau` — Руда (12), кирки (7), гири (7), LayerValue, тайминги
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningRules.luau` — Чистые правила активной добычи: удары, круги, RollOre (LayerMult по самому глубокому слою), покупки, тренировка, миграция v1→v2
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningModels.luau` — Процедурные модели руды/кирок/гирь; образец процедурной генерации для чанков шахты
- `/home/user/riooblox/src/ServerScriptService/MiningWorld.server.luau` — Постройка MiningCorner (LAYOUT_VERSION 24, PersistentPerPlayer), placement() по YardFoundation/StorageAnchor, перенос состояния, предметы в руке
- `/home/user/riooblox/src/ServerScriptService/Economy/MiningSessions.luau` — RAM-сессии кругов таймингов
- `/home/user/riooblox/src/ServerScriptService/MiningStudioTest.server.luau` — F8-панель в Studio (команда layers открывает все слои)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/MiningClient/World.luau` — Клиентский рендер корнера; образцовая обработка StreamingEnabled (syncCore/register/queueRefresh)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/MiningClient.client.luau` — Точка входа клиента добычи (Net/Anim/FX/World первыми, потом Hud/Mine/Shop/Gym/Debug)
- `/home/user/riooblox/src/ReplicatedStorage/DogDigProfiles.luau` — Цепочки копания по породам (Start/Loop/End/Find/Action)
- `/home/user/riooblox/src/ReplicatedStorage/DogAnimationPlayer.luau` — Проигрыватель клипов костей, UpdateKennel:981, ComputeLift
- `/home/user/riooblox/src/ReplicatedStorage/DogRig.luau` — Rig.Prepare/Place: якорение, масштаб, GroundLocal, VisualSize
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau` — Анимации собак в будках и на конвейере, culling, ярлыки статуса
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` — Оттенок экрана по CurrentLayer, «+$» над собаками, показ находки у ямы (DiscoveryReveal)
- `/home/user/riooblox/src/ServerScriptService/Economy/GlobalDigService.luau` — Global Dig (выключен GlobalDigConfig.Enabled=false)
- `/home/user/riooblox/src/ServerScriptService/GlobalDigBootstrap.server.luau` — Bootstrap Global Dig
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/GlobalDigPresentation.client.luau` — Презентация карьера (выходит сразу при Enabled=false)
- `/home/user/riooblox/src/ReplicatedStorage/GlobalDigConfig.luau` — Enabled=false, Cooldown, Contribution, Milestones
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau` — Стадии/скины участка; A.Frame по YardFoundation; цикл DigSlot (show/remember по PlotBase*), DigBorder/FutureGarden
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotRules.luau` — Assign-ворота по числу слотов, миграция PlotProgressionVersion
- `/home/user/riooblox/src/ServerScriptService/DistrictSafety.server.luau` — Возврат упавших при Y < -85
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau` — Меню Layers (карточки слоёв, баг с def.Prestige :249) и Kennels
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` — Вторая реализация страницы Layers/Prestige (устаревший текст :203)
- `/home/user/riooblox/docs/MINING.md` — Документация активной добычи v2
- `/home/user/riooblox/tests/kennel.luau` — Тест работы будок с реальной экономикой (3 теста)
- `/home/user/riooblox/tests/mining_rules.luau` — Тесты MiningRules (17)
- `/home/user/riooblox/tests/animations.luau` — Проверки DogDigProfiles против реальных клипов (12)

### Сохраняемые данные

- DataStore DOGROTS_ECONOMY_V1 (StoreKeys.Wrap, хэш ключей >50 байт): профиль 'p:<UserId>'; 'event:<week>' — счётчик Global Dig; 'records:<depth>' (1..5) — глобальные рекорды веса по глубине
- p.CurrentLayer (int 1..5) — слой, на котором копают ВСЕ собаки игрока; новый профиль 1; Prestige сбрасывает в 1
- p.UnlockedLayers (map '1'..'5' -> true) — открытые слои; сохраняются при Prestige
- p.Prestige — нужен ≥1 для слоя 5 (захардкожено в Rules.Action 'Layer')
- p.Level/p.XP — уровни-ворота слоёв (1/5/12/22/35)
- p.Dogs[uid].AssignedSlot ('' или 'DigSlot_1..5'), State ('Inventory'/'Digging'/'Walking'), NextWorkAt, WorkSequence, Mastery/MasteryXP, DryStreak, FoodStreak, TreasureStreak, LastAbility/LastAbilityAt, LastYield, OrbitValue/OrbitCount, Locked, Favorite
- p.LastDig, p.TotalExcavations, p.Pity — счётчики копания
- p.DogIncome {Total, XPCoins, XPAt} — книга дохода собак (XP раз в минуту)
- p.SpecialDiscoveries {LongDogPending, LongDogFoundAt, LastArrivalAt}
- p.Items[uid].Depth (1..5), .SourceDogUid (для LootSpawn), p.DiscoveryFeed (20), p.Collection, p.RecordJobs
- p.Stats.Depths['1'..'5'] {Finds, BestWeight, BestValue, Item} — статистика по глубинам (основа для титулов F10)
- p.Upgrades.Plot — уровень участка → число слотов (PlotCatalog.Slots); p.PlotProgressionVersion=1
- p.Mining (Version=2): Strength, PickaxeOwned, PickaxeLevel, WeightOwned, WeightLevel, Hits, OresBroken, CoinsEarned, TrainingReps, OreIndex, OreId, OreMaxHP, OreHP, OreValue, OreEarned, OreSerial, Combo, BestOre, Collection, LastHitAt, LastTrainAt, ActiveUntil, TrainingUntil, LastPayout, LastDamage, LastQuality, LastBreak, LastCrit, LastBrokenId, LastBrokenValue
- p.NextCommunityDig, p.Event {Week, Contribution, Claims}, p.EventTokens, p.Lifetime.GlobalDigContribution — Global Dig/недельное событие
- Версии: Config.Version=4, BalanceVersion '2026-10-11.MINING_V2', MegaResetVersion=1 (не повышать), MiningConfig.Version=2
- Только RAM: MiningSessions (круги), Runtime.Views, атрибуты моделей собак/слотов/корнера
- F5 фаза 1 новых сохраняемых полей НЕ требует; фаза 2 (опционально): p.Dogs[uid].DigLayer (nil = следовать CurrentLayer)

### Сеть

- ReplicatedStorage.DogKennelRequest (RemoteFunction, C→S): (action 'Assign'|'Remove', dogUid, slotName) → ok, message; DogKennelService.Handle → Runtime.Request; лимит Runtime.Allow(.5); Assign сначала делает пробный prepare()
- ReplicatedStorage.DogKennelOpen (RemoteEvent, S→C): slotName — владелец нажал MANAGE у своей будки (≤14 стадов, Runtime.Allow(1))
- ReplicatedStorage.DogEconomyRequest (RemoteFunction, C→S): (action, args, requestId 32 hex). Относится к подсистеме: 'Layer' {Layer=1..5}; 'Assign'/'Remove' {Uid,Slot}; 'MiningBegin'/'MiningEnd'/'MiningHit' {Target,Quality,Miss}/'MiningPickaxe' {Level}/'MiningWeight' {Level}/'MiningTrain'/'MiningTrainBegin'/'MiningTrainEnd' (≤32 стада до MiningPad); 'Snapshot'; 'EventClaim' {Milestone}. Ответ: Message + StatePatch (Mining) или StateSnapshot
- ReplicatedStorage.DiscoveryReveal (RemoteEvent, S→владелец): копия находки + LootSpawn {CFrame, DogUid, Slot, YardId, OwnerUserId} (Runtime.Project, находки младше 30 с)
- ReplicatedStorage.DiscoveryAnnouncement (RemoteEvent, S→все): (item, global) для TierIndex≥8 или Secret, не чаще раза в 15 с
- ReplicatedStorage.DogEconomyOpen (RemoteEvent, S→C): ('Events', сообщение) после промпта Global Dig
- ReplicatedStorage.RewardPresentation (RemoteEvent, S→C): раскрытие LongDog из ямы
- ReplicatedStorage.Mining.MiningStudioControl (RemoteFunction, создаётся только в Studio): F8-читы (cash, strength, all, rare, layers, reset)
- Через атрибуты по сети (не remote): у Player — CurrentLayer, LayerName, Mining* (25 шт.), MiningRevision, UnlockedKennels, YardId; у модели собаки — AnimationName, AnimationStartedAt, Producing, StorageFull, FindsFull, WorkState, NextWorkAt, WorkSequence, WorkCycle, AssignedAt, Variant, Mastery, EquippedCosmetic, DogId, DogUid, OwnerUserId, AssignedSlot; у DigSlot — AssignedDogUid, AssignedOwnerUserId, AssignedDogName, Unlocked, RequiredYardLevel; у MiningCorner — OreId, OreHP, …, Active, Training, OwnerUserId, Revision; у DogInventory/<uid> — все скалярные поля собаки
- F5 фаза 1 новых remote не требует: смена слоя идёт существующим 'Layer', отображение — атрибутами участка MineLayer/MineDeepest/MineRevision и DigSlot.ShaftOpen

### Объекты мира

- Workspace.DOGROTS_District.04_PlayerYards.Yard_01..08_* — 8 участков 2×4, по 1556 инстансов и 1430 BasePart; атрибуты YardId, OwnerUserId, OwnerDisplayName, PlotStage, PlotSkin, UnlockedKennels, AppearanceRevision (YardFootprint/DigSlotSize не используются). Западные X −172..−38, восточные 38..172 (зеркальны), Z-полосы шириной 70 с щелями 8 стадов, центры zc = −117/−39/39/117
- …/Yard_*/DigSlot_1..5 (Model): атрибуты DigCenter, DigSize=(12,.4,12), ApproachPosition (край дорожки, напр. (−81,2,122.5)), SlotIndex, RequiredYardLevel, Unlocked; DarkExcavation 12×0.4×12 Ground (Y 0.8..1.2) + Attachment LootSpawn; PitTimber×4; будка KennelFloor/KennelBack/KennelWall×2/KennelLintel/KennelRoof×4, SlotMarker, DogBowl/BowlWater; во время работы KennelFloor.KennelInteraction + ProximityPrompt. Центры ям: X ±81/±65/±49, слоты 1/3/5 на zc+13, 2/4 на zc−13
- …/Yard_*/YardLandscape: YardFoundation 134×1×70 Grass (Y 0..1; на неё ссылаются PlotAppearance.A.Frame и MiningWorld.placement), WorkArea 47×0.2×62 (X −88.5..−41.5), EntryWalk 124×9 (Z 112.5..121.5 у Yard_04), UtilityApron, LuckyCourt, CosmeticGarden; столбы и перила невидимы
- …/Yard_*/PlotDevelopment (во время работы, PlotAppearance): DigBorder, FutureGarden (без коллизий!), Sign, BestFinds (около (−50,97), X −55.5..−44.5, Z 85.5..108.5), EstateLevel
- …/Yard_*/MiningCorner (во время работы, MiningWorld, PersistentPerPlayer) — площадка 23×18 в (∓111.5, zc+18)
- …/Yard_*/YardSpawn, StorageAnchor, SellAnchor, UpgradeAnchor, *InteractionZone
- Workspace.DOGROTS_District.KennelDogs (Folder) — модели собак в будках, имя = DogUid
- Workspace.DOGROTS_District.01_IslandAndStreets.CohesiveIsland: IslandMass Rock 360×32×12 (Y −32..0, срезы Z по 12, общие для обеих сторон и улицы) + LivingGround Grass (Y −0.4..0). Под WorkArea ниже −32 до −250 пусто; Terrain пуст (SmoothGrid 2 байта)
- Workspace.DOGROTS_District.01_IslandAndStreets.LayeredCliffs — только по краю острова (X ±126..±221), до Y −42
- Workspace.DOGROTS_District.08_GlobalDigSite (UpperLevel −18, LowerLevel −42; X 34..204, Z 532..744): 1170 частей, все невидимы и без коллизий; DigPositions/DigStation_1..8, MilestoneCrystals, CommunityProgress, SiteOrigin (143,−42,614)
- Workspace.DOGROTS_District.37_AttractionRefresh.GlobalEventComingSoon.OpaqueBlackCuboid 182×99×214 (CanCollide) и 36_DistrictRefresh.GlobalEventComingSoon (PitCover и т. п., невидимы) — крышка над карьером
- Workspace.DOGROTS_District.NavigationAnchors.PlayerYards (0,2,110), .GlobalDigSite (38,3,575) — цели навигации
- Workspace: StreamingEnabled=true, StreamingMinRadius=64, StreamingTargetRadius=1024 (почти весь район у каждого клиента), FallenPartsDestroyHeight=−250
- ServerStorage.DogTemplates (101 Model, 5294 инстанса) — шаблоны собак для будок
- ReplicatedStorage.DogAnimationClips.<DogId> — клипы для DogDigProfiles
- ServerScriptService.DistrictSafety — телепорт на спаун при Y < −85 (ограничивает любую ходимую шахту под островом)

### Точки расширения

- Runtime.Project (Runtime.luau:105) — место для DeepMine.Reconcile(player,p) до Kennels.Reconcile (как уже сделано для PlotDevelopment, Kennels, PlotShowcase)
- DogKennelService.prepare: вычисление surface — заменить на резолвер DeepMine.FloorTop(slot); Reconcile — точка перепивота моделей при смене DigLayer
- KennelLootPlacement.Marker(slot) — один источник позиции находки; перенести на пол уровня, и DiscoveryReveal с EconomyVisuals заработают на глубине без изменений протокола
- Rules.Action 'Layer' и Prestige — единственная точка смены CurrentLayer; оттуда идёт Refresh, затем Project
- Config.Layers[i] (Color, Event, Depth-ярлык) — источник цветов и тем уровней; новый ReplicatedStorage/DeepMine/DepthVisuals по индексу слоя
- DepthDefinitions[i].Items + ItemDefinitions — превью «что найдёшь на глубине» в UI и декор стен
- Bonuses.Keys 'DepthSpeed' — зарезервированный и неиспользуемый ключ бонусов «для системы глубины» (скорость спуска, косметика, будущая механика)
- WorldEventModifiers: e.EventDepth/EventDepthLuck (BONE_RAIN 1, CRYSTAL_STORM 2, CURSED_FOG 4, BLACKOUT 4, UFO_INVASION 5) — готовый хук для «редких жил» в шахте
- RecordStats p.Stats.Depths[k].Finds/BestValue и UnlockedLayers — данные для титулов глубины (F10)
- Шаблон MiningWorld: серверная постройка во время работы с LAYOUT_VERSION, ModelStreamingMode PersistentPerPlayer + AddPersistentPlayer, перенос состояния владельца в атрибуты модели
- Шаблон MiningClient/World.luau: построение вида, устойчивое к стримингу (появление модели → регистрация частей → сборка, когда пришло ядро)
- WorldDetailQuality — общий бюджет света и частиц для всего под DOGROTS_District (клиентские чанки шахты подключаются, если положить их туда)
- DogDigProfiles — цепочки по породам; сюда же можно добавить «rush»-скорость для F7
- Атрибут DigSlot.ApproachPosition (край дорожки) — готовая точка для переноса промпта будки и цели навигации F1
- PlotInteractionAccess / PlotPrompts — механизм промптов только для владельца (пока покрывает лишь YardInteraction)
- SecretReveal.Show(…, {Venue='Excavation'}) через Runtime.RevealExcavation — кинематика из ямы

### Улучшить поверх

- Визуальная шахта F5 (вариант A) поверх существующих CurrentLayer/UnlockedLayers: без новых сохраняемых полей и без изменений экономики
- Единый источник требований слоя: Prestige=1 в Config.Layers[5], читать его в Rules.Action 'Layer', ServiceMenusController и EconomyScreens; исправить устаревший текст Prestige (уровень 35, 12M×(P+1))
- Промпт MANAGE только для владельца и перенос его к DigSlot.ApproachPosition (стойка лебёдки у дорожки)
- DogKennelService.Reconcile: писать AssignedDogUid/AssignedOwnerUserId/AssignedDogName только при изменении (через put), без цикла «nil и обратно»
- DogKennelService.Handle('Assign'): проверять ассет без полного клонирования и Rig.Prepare (как Runtime AssetReady: шаблон + RootPart)
- SleepLabel собаки: якорь у верха шахты, чтобы ярлык не закрывали стены
- Тотем глубины на участке и цветное свечение шахт — престиж, видно гостям
- «Редкие жилы»: визуал по WorldEventModifiers.EventDepth (удача уже есть)
- Использовать зарезервированный бонус DepthSpeed (скорость спуска или косметика) без влияния на доход
- Lune-тесты на действие 'Layer' (цены, уровни, Prestige-ворота, выбор) и на сброс CurrentLayer при Prestige
- Показ при Prestige: шахты закрываются на поверхность, предложение снова спуститься на открытый слой
- Пока Global Dig выключен, вынести 1170 невидимых частей карьера из Workspace или переиспользовать (сначала поправить WaitForChild без таймаута в GlobalDigService.Start)
- EconomyVisuals: заменить глобальный оттенок экрана по слою на локальную атмосферу у шахты

### Аккуратный рефакторинг

- Разрез плиты острова (CohesiveIsland: 16 IslandMass + 16 LivingGround срезов → около 256 кусков) и разбиение YardFoundation/WorkArea каждого участка. Учесть зависимости: PlotAppearance.A.Frame и MiningWorld.placement берут YardFoundation по имени и позиции; PlotAppearance.remember/show восстанавливает Transparency/CanCollide по PlotBase*; закрытые слоты без коллизий (FutureGarden, скрытая DarkExcavation) требуют крышки
- Глубина на собаку или слот (фаза 2): SignatureRules.Context (6 мест с p.CurrentLayer: c.Depth, deeper(), CactusCorgi, Pharaohound, VoidHound, Hardness), ключ кэша IncomeModel.shapes, refCtx, OfflineEarnings, Runtime dogStats.MaxDepth, UI; прогнать balance_sim и тесты дохода
- Объединить три копии «самого глубокого слоя» (Rules.MaxUnlockedLayer, SignatureRules.maxUnlockedDepth, IncomeModel.maxDepth) и похожие циклы в BoostPricing/Dogdex/DiscoveryScreens
- Runtime.Project вызывается на каждый тик копания и делает полную проекцию (все атрибуты, все записи DogInventory, три Reconcile). Разделить на лёгкую проекцию работы и полную проекцию профиля и писать только изменения
- Две реализации меню слоёв (ServiceMenusController 'Layers' и EconomyScreens 'Layers') — свести в один экран глубины (F2)
- Global Dig: либо удалить мёртвый карьер и сервис, либо включить заново на общем пайплайне находок (I.Free с ёмкостью, Bonuses RareFind/IncomeMult) как публичную «экспедицию»
- DogKennelService: промпты и посадка собак должны учитывать шахту (ограждения перекроют путь к KennelFloor), ярлыки, переход между уровнями

### Найденные баги

- ServiceMenusController.client.luau:249-251: проверка готовности слоя использует def.Prestige, но в Config.Layers поля Prestige нет. Карточка THE VOID показывает UNLOCK без Prestige 1, сервер (Rules.luau:483, захардкожено) отказывает. EconomyScreens.luau:200 тоже хардкодит ' · Prestige 1'
- EconomyScreens.luau:203: подтверждение Prestige пишет 'Requires Level 25 … Costs 250000×(P+1)', а Rules использует C.PrestigeLevel=35 и C.PrestigeBaseCost=12 000 000×(P+1)
- DogKennelService.Start (:254): ProximityPrompt MANAGE создаётся без имени и включён для всех. PlotPrompts.client фильтрует только 'YardInteraction', поэтому гости видят MANAGE на чужих будках, а сервер молча игнорирует нажатие
- DogKennelService.Reconcile: на каждый Runtime.Project ставит AssignedDogUid/AssignedOwnerUserId/AssignedDogName всех слотов в nil и обратно (не через put): лишние записи атрибутов (схлопывание репликации не подтверждено)
- DogKennelService.Handle('Assign'): ради проверки ассета делает полный prepare (Clone + Rig.Prepare + ScaleTo) и Destroy на каждый запрос
- 08_GlobalDigSite: 1170 частей, все Transparency=1 и CanCollide=false, нет включённых ламп и SurfaceGui; всё лежит в Workspace и стримится, хотя Global Dig выключен (GlobalDigConfig.Enabled=false); сверху OpaqueBlackCuboid 182×99×214
- GlobalDigService.Dig (если включить): I.Free(p) без доп. ёмкости и эффекты без Bonuses-пайплайна (RareFind, IncomeMult) — находки слабее и не согласованы с R.Dig
- Нет юнит-теста на Rules.Action 'Layer' (разблокировка, цены, Prestige-ворота) и на сброс CurrentLayer=1 при Prestige
- Prestige молча возвращает CurrentLayer=1 (UnlockedLayers сохраняются): доход падает, пока игрок вручную не выберет слой; визуально это никак не видно
- Заблокированный слот не имеет своей коллизии (DarkExcavation скрыта без коллизий, FutureGarden без коллизий). Это не баг сейчас, но провал при любой вырезке под слотом
- Атрибуты участка YardFootprint=110,1.2,66 и DigSlotSize нигде не читаются и не совпадают с реальным основанием 134×70

## Приложение: `item-models` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/ItemDefinitions.luau` — 108 определений находок (минифицированная таблица на 34 КБ); VisualAsset == Id у всех — будущий ключ рецепта
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemDefinitions.luau` — прокси на 79 байт: require ReplicatedStorage.DogEconomy.ItemDefinitions
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau` — V.Clone (клон из DiscoveryModels, мутация: все части в Neon, масштаб по весу) и V.Preview (ViewportFrame); фасад, который нужно сохранить и перевести на фабрику
- `/home/user/riooblox/src/ReplicatedStorage/EconomyRewardVisuals.luau` — процедурные модели наград Cash/Bones/Boost; для Item — сырой клон DiscoveryModels (строка 4)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` — временный показ находки на участке (167-215: Highlight, BillboardGui, тост, зум, тряска), анонс (216-218), Highlight для вариантных собак (19-39)
- `/home/user/riooblox/src/ServerScriptService/Economy/KennelLootPlacement.luau` — аттачмент LootSpawn на DigSlot_N.DarkExcavation и проверка владельца, собаки и слота для показа
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Project (105-120): отправка DiscoveryReveal и DiscoveryAnnouncement; announce (485-490); вызов PlotDevelopment/PlotShowcase.Reconcile при каждой проекции
- `/home/user/riooblox/src/ServerScriptService/Economy/BestFinds.luau` — стенд MY BEST FINDS: автоподбор Find/Relic по SellValue и серверные клоны DiscoveryVisuals.Clone на Slots
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau` — геометрия стенда BestFinds (showcase(), 140-175) по стадии участка
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotShowcase.luau` — стенды собак DogStorage.DisplaySlots (серверные клоны) — образец взаимодействия для F3
- `/home/user/riooblox/src/ServerScriptService/Economy/DisplayRules.luau` — p.DisplayDogs Normalize/Assign — образец правил для витрины находок F3
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — Mint (176-199): поля записи предмета; MutationRows (142-159): какие мутации реально выпадают; Discover; ItemSetClaim
- `/home/user/riooblox/src/ReplicatedStorage/ItemValuation.luau` — цена и редкость (rarityOf — локальная, строки 4-8; нужно экспортировать)
- `/home/user/riooblox/src/ReplicatedStorage/ItemValueConfig.luau` — пороги редкости по шансу, множители 16 мутаций, Version=6
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/PreviewRenderer.luau` — P.Item → DiscoveryVisuals.Preview; P.Scene/P.Dog для собак и наград
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Preview.luau` — кэш 3D-превью карточек (PerFrame=2, MaxFree=48, BuildSize=128), builder Item, точка расширения Register
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Cards.luau` — ItemCard: тег мутации, полоса и градиент редкости — основа инвентаря и торговли
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Theme.luau` — Theme.ItemRarity, RarityGradient, Mutation (16 ключей, тест синхронизации с ItemValueConfig)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DiscoveryScreens.luau` — Collection/Marketplace/Records/Inspect/Listing/CreateListing: immediate-mode, V.Item на каждую карточку, перестройка каждые 5 с
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/CollectorScreen.luau` — продажа: список всех находок без виртуализации, Preview.Item у каждой
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Menus.luau` — опрос Snapshot раз в 5 с (71-79) и Render через ClearAllChildren (182-185) — причина постоянной пересборки превью
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` — последняя находка (120); Trade (255-345): находки только текстом
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau` — основной инвентарь: viewport-превью только для видимых карточек; сырой клон коллекции (117); устаревшие classColors (57)
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadController.client.luau` — showPreview (150-185), сырой клон DiscoveryModels (159)
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau` — последняя находка через geometry() (64-87, 150), мутация не показывается
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau` — NPC-продавец: discoveries.Clone (52), превью только для видимых
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/RewardScreens.luau` — превью призов DOG-O-MATIC (44-50)
- `/home/user/riooblox/src/ServerScriptService/RewardMachinePresentation.server.luau` — серверная модель приза-находки (59-61)
- `/home/user/riooblox/src/ServerScriptService/Economy/RewardMachineService.luau` — view.Rarity = Class для Item (строка 90) — баг
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/EquipmentVisuals.luau` — образец процедурной модели по данным (Look.Parts, стили редкости, свет и искры только в мире, Viewport/Turn)
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningModels.luau` — образец процедурных моделей без ассетов (seed-RNG, PARTICLES/Emitter)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/MuseumPresentation.client.luau` — образец клиентского LOD и бюджета (NearDistance, MaxNearModels, budget 8/0.3 с, качество графики и LowFX, стриминг)
- `/home/user/riooblox/src/ServerScriptService/Economy/RecordStats.luau` — BestShowcaseFind/Relic, Heaviest/MostValuable/Rarest — источники для стенда
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Stare.luau` — зависит от BestFinds.Slots.Dog.Exhibit и DisplaySlots (строки 21-25) — учесть при переносе витрины на клиент
- `/home/user/riooblox/src/ServerScriptService/Economy/EstateQATests.luau` — проверяет серверные Exhibit на стенде (52-59)
- `/home/user/riooblox/tests/equipment.luau` — образец теста визуала и бюджета частей (looks 2..8 частей, MaxParts/MaxLights)

### Сохраняемые данные

- p.Items[ItemUid] — запись находки: ItemUid, ItemId (=ключ визуала), DisplayName, Depth, Class, SetId, BaseDropChance, EffectiveDropChance, BaseWeightKg, WeightKg, WeightMultiplier, WeightTier, TierIndex 1..10, WeightProfile, WeightTierChance, Mutation (NORMAL/GOLDEN/RAINBOW/CURSED/GLITCHED + сигнатурные BURNED/FROZEN/INFERNAL/RADIOACTIVE/SOLAR/SPORE/TOASTED), MutationChance, CombinedOdds, FoundAt, FoundByUserId, OriginalFinderUserId, OwnerUserId, SellValue (замораживается при минте), Tradeable, RecordAtCreation, Favorite, SourceDogUid, FirstFind, SellBonus, IncomeMult?, EventTag?, ValueBreakdown{Version,Rarity,Factors,Raw,Cap}, ValueVersion. Визуальных полей нет, F4 миграции не требует.
- p.Collection[ItemId]=true — коллекция (силуэт или модель на странице Collection)
- p.MutationJournal[ItemId][Mutation]=true — какие мутации встречались
- p.HeavyCollection[ItemId]=true — находки с TierIndex>=4 (Heavy-сеты)
- p.PersonalRecords[ItemId]={WeightKg,ItemUid,Finder,At} — личные рекорды веса
- p.DiscoveryFeed — последние ≤20 копий находок (источник DiscoveryReveal и последней находки)
- p.ItemSets['SET:Normal|Heavy'] и p.Cosmetics['Discovery:SET:Normal|Heavy'] — завершённые сеты, источник титулов
- p.Stats.BestShowcaseFind / BestShowcaseRelic / Heaviest / MostValuable / Rarest / Depths[d].Item — краткие сводки для стенда MY BEST FINDS и Records
- p.DisplayDogs {'1'..'3'=DogUid} — стенды собак (образец для p.ShowcaseFinds в F3)
- p.RecordJobs, p.ItemReservations, p.TrackedListings, p.DexFavorites — служебные данные предметов
- Атрибуты игрока ItemCount, ItemCapacity, LatestFoundItem, InventoryRevision
- Слоты стенда (атрибуты в мире, не сохраняются): ExhibitToken, CaptionName на Slots.{Find,Dog,Relic}; Stage на BestFinds
- DataStore DOGROTS_ECONOMY_V1, ключ p:<UserId>, Config.Version=4; ItemValueConfig.Version=6 (версия цены на предмете — ValueVersion)

### Сеть

- DiscoveryReveal (RemoteEvent, сервер → владелец): Rules.Copy(item) + LootSpawn{CFrame,DogUid,Slot,YardId,OwnerUserId}; Runtime.luau:116, один раз на ItemUid, только если FoundAt моложе 30 с; клиент EconomyVisuals:167, InventoryController:518, YardPageController:194
- DiscoveryAnnouncement (RemoteEvent, сервер → все): (item, global:boolean) для TierIndex>=8 / Secret / глобального рекорда, не чаще раза в 15 с; Runtime.luau:118, 489; клиент EconomyVisuals:216 (показывает числовой UserId нашедшего)
- DogEconomyRequest (RemoteFunction, клиент → сервер): Snapshot (Profile.Items полностью), ItemFavorite{Uid,Enabled}, BulkSell{Uids}, List{Kind='Item',Uid,Mode,Price,Duration}, MarketQuery{Kind='Item',...}, Trade{Action='Offer',Items≤6} (offer.Details — полные копии предметов, Engine.luau:301), ItemSetClaim, RecordClaim; SellItem отклоняется (Runtime:420)
- RewardRequest / RewardPresentation — призы DOG-O-MATIC, в том числе Kind='Item' (серверная модель приза в RewardMachinePresentation:60)
- MuseumRead (RemoteFunction) / MuseumChanged (RemoteEvent) — только собаки, к находкам отношения не имеют
- Предлагается (F3): действие DogEconomyRequest 'ShowcaseAssign'{Slot,Uid} по образцу DisplayRules.Assign; модели по сети не передаются — сервер пишет только атрибуты слотов

### Объекты мира

- ReplicatedStorage.DiscoveryModels — Folder, 108 Model, 3225 Part (только Block 'VoxelN', Plastic 2927 / Neon 298, CastShadow у всех, без PrimaryPart, без MeshPart); реплицируется каждому клиенту; около 32% инстансов ReplicatedStorage
- Workspace.DOGROTS_District.04_PlayerYards.Yard_01..10 (10 дворов, ModelStreamingMode Default; StreamingTargetRadius 1024, MinRadius 64)
- Yard_XX.DigSlot_1..5 (атрибуты DigCenter, DigSize 12×0.4×12, Unlocked, RequiredYardLevel) → DarkExcavation (Part 12×0.4×12, Ground) → LootSpawn (Attachment; создаётся KennelLootPlacement.Marker, если нет; в собранном place есть) — точка показа находки
- Yard_XX.PlotDevelopment.BestFinds (Model, атрибут Stage, строится PlotAppearance.showcase) → Slots.{Find,Dog,Relic} (Part 5.9×0.2×5.9, атрибуты ExhibitToken/CaptionName) → Exhibit (серверный клон); вывески Name<Key>, Category<Key>, ShowcaseTitle
- Yard_XX.DogStorage.DisplaySlots.Slot1..3 (+SlotCaption, DisplayDog) и StorageAnchor/StorageInteractionZone — образец стенда для F3
- Workspace (клиент): модели показа находок кладутся прямо в workspace, одновременно ≤4, Debris через 6/14 с
- DOGROTS_District.37_AttractionRefresh.RewardMachineRig.CommittedPrize — серверная модель приза-находки
- DOGROTS_District.KennelDogs и 03_DogLine.ActiveDogs — вариантные собаки получают Highlight и конкурируют с подсветкой находок за лимит 31
- DOGROTS_District.06_DogDexMuseum (Exhibits.DexSlot_1..100) — только собаки, экспонатов-находок нет

### Точки расширения

- DiscoveryVisuals.Clone(x)/Preview(...) — единый фасад; можно заменить внутренности фабрикой без правки 9 потребителей
- Kit.Preview.Register(kind, builder, keyer) и builders.Item/keyers.Item — подключить фабрику с LOD в ключе кэша
- ItemDefinitions[*].VisualAsset — косвенный ключ визуала (все 108 == Id), позволяет перескины и общие рецепты
- Формат Look из EquipmentVisuals ({shape,size,pos,rot,role,material,transparency}) — общий словарь примитивов
- MiningModels.Emitter / PARTICLES (Sparkle/Ember/Void) — пресеты частиц для FX редкости и мутаций
- Паттерн MuseumPresentation (дистанция, MaxNear, бюджет сборок за тик, учёт качества графики, стриминг через DescendantAdded) — для LOD-менеджера экспонатов
- Атрибуты игрока LowFX, WorldEventFX=='Low', ReducedMotion и UserGameSettings.SavedQualityLevel — уровни качества FX
- PlotAppearance.showcase() + Slots folder + атрибуты слотов — место для витрины F3 (больше слотов, подсказка взаимодействия)
- DisplayRules / PlotShowcase / YardCommerce.prompt() — готовый шаблон «подойди к стенду → меню → серверное действие → Reconcile»
- KennelLootPlacement.Marker/Resolve — точка привязки показа к месту копания (для F5 — к уровню шахты)
- ItemValuation (экспортировать Rarity) и Kit.Theme.ItemRarity/Mutation — единые редкость и цвета
- x.EventTag (WorldModifiers.Current при минте) — поверх него можно рисовать значок или FX события
- tests/*.luau подхватываются tools/check.sh автоматически; tests/lib/economy_env.luau умеет require реальных модулей из src (EquipmentVisuals уже строится в Lune)

### Улучшить поверх

- Перевести DiscoveryVisuals.Clone/Preview на ItemModelFactory, сохранив сигнатуры: новые модели сразу во всех 9 путях, включая серверные BestFinds и RewardMachinePresentation
- Мутации: перекраска по ролям и материалам вместо «все части в Neon»; вид для всех 16 ключей ItemValueConfig.Mutation (в том числе сигнатурных BURNED/FROZEN/INFERNAL/RADIOACTIVE/SOLAR/SPORE/TOASTED); расширить фильтры мутаций в DiscoveryScreens
- Выключить CastShadow у мелких частей; ограничить масштаб в мире (×3 + пьедестал рекорда); убрать Highlight у показа находки (кайма, ForceField-оболочка, Beam)
- Экспортировать ItemValuation.Rarity(def) и использовать в UI, в RewardMachineService:90 (сейчас там Class) и в фабрике
- Перевести 4 сырых клона (InventoryController:117, PawpadController:159, YardPageController:150, EconomyRewardVisuals:4) на фасад
- Единая камера и свет превью через Bounds фабрики (как EquipmentVisuals.Viewport)
- Анонс: имя нашедшего вместо UserId; урезать payload DiscoveryAnnouncement (без ValueBreakdown)
- Пул показов RevealRig (4 слота с эмиттерами, светом и табличкой), FX по редкости вместо одного зума
- Исправить classColors в InventoryController (World Find; убрать Junk/Organic)
- Тесты tests/item_models.luau: рецепт для каждого id, бюджеты частей по LOD и редкости, уникальность силуэтов, флаги Anchored/CanQuery/CastShadow, синхронизация мутаций, grep-запрет прямых ссылок на DiscoveryModels

### Аккуратный рефакторинг

- Экраны находок в Menus (DiscoveryScreens: Collection/Marketplace/Records/Inspect/Listing/CreateListing и CollectorScreen) перестраивают все ViewportFrame и клоны каждые 5 с (Menus:71-79, 182-185) и не виртуализированы — перевести на Kit.CardGrid + Kit.Preview (затрагивает подтверждения продажи и выставления на рынок)
- Экспонаты стенда (BestFinds, и PlotShowcase для собак) сейчас серверные клоны — для F3 перенести на клиентский рендер по атрибутам слотов с LOD; обновить SecretArrivals/Stare.luau:21-25 и EstateQATests:52-59
- Удаление ReplicatedStorage.DiscoveryModels (3225 частей у каждого клиента) — только после перевода всех потребителей; build.py не удаляет инстансы, поэтому нужен серверный Destroy до входа игроков или ручное удаление в Studio
- Показ находки EconomyVisuals:167-215 переписать на пул и LOD; под F5 отвязать от обязательного наличия yard.DigSlot на клиенте (строка 178) и брать точку уровня шахты
- Две логики цены: BulkSell пересчитывает Price вживую (YardCommerce:55), а BestFinds.Select, RecordStats и оценка трейда (Engine:301) берут замороженный x.SellValue — после ребаланса F11 нужен единый источник цены для UI и витрины
- Ветка 'Discoveries' в DiscoveryScreens похоже недостижима (Menus:197) — удалить или подключить после проверки

### Найденные баги

- DiscoveryVisuals.luau:9 — любая мутация из таблицы цветов делает ВСЕ части Neon (у RAINBOW случайный оттенок на каждый воксель): форма и светотень пропадают, в ViewportFrame (без bloom) получается плоское пятно
- Свой вид есть только у GOLDEN/RAINBOW/CURSED/GLITCHED (DiscoveryVisuals:3); реально выпадающие сигнатурные BURNED/FROZEN/INFERNAL/RADIOACTIVE/SOLAR/SPORE/TOASTED (SignatureRules → ItemRules.MutationRows) выглядят как NORMAL; фильтры DiscoveryScreens:44,90 знают только 5 мутаций
- 72 из 108 предметов делят 24 геометрии: tennis_ball (Common, 6) совпадает с dead_star/piece_of_the_sun/fragment_of_the_moon (Legendary, 43200) и underground_pearl; 10 кристаллов одинаковы
- Menus.luau:71-79,182-185 — опрос раз в 5 с + ClearAllChildren: DiscoveryScreens и CollectorScreen пересоздают все ViewportFrame и клоны без виртуализации (CreateListing и Collector — по превью на каждую находку)
- Сырые клоны в обход DiscoveryVisuals: PawpadController:159 и YardPageController:150 (последняя находка без мутации), EconomyRewardVisuals:4, InventoryController:117; камера и свет в 9 путях разные
- EconomyVisuals:184 — Highlight на каждый показ находки, и EconomyVisuals:24 — Highlight на каждую вариантную собаку всех дворов; движок рисует ≤31 Highlight, AlwaysOnTop светит сквозь стены
- Все 3225 вокселей с CastShadow=true; масштаб по весу до ×8 (ScaleCap) — рекордные находки 25–30 studs, huge_statue ≈87 studs над ямой 12×12
- EconomyVisuals:217 — тост анонса показывает числовой UserId ('finder 12345'), а FireAllClients отправляет всем полную запись предмета с ValueBreakdown
- RewardMachineService.luau:90 — для призов Item в view.Rarity пишется Class ('Treasure'), а не редкость
- InventoryController.client.luau:57 — classColors содержит несуществующие Junk/Organic и не содержит 'World Find'
- EconomyVisuals — таблица active хранит модели, уже уничтоженные через Debris; модели показа кладутся прямо в workspace
- DiscoveryScreens: ветка c.Page=='Discoveries' не маршрутизируется из Menus (Menus.luau:197) — вероятно мёртвый код (нужно проверить)
- Смежное: YardPageController.geometry() не реже раза в 20 с клонирует весь двор (1555 потомков) во ViewportFrame
- Ни один путь визуализации находок не покрыт тестами (tests/ и tools/verify.luau их не упоминают)

## Приложение: `plots` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ServerScriptService/YardService.server.luau` — Session yard allocation (Allocator order 4,8,3,7,2,6,1,5), owner attributes, waiting queue; updateSign targets missing OwnerPlaque
- `/home/user/riooblox/src/ServerScriptService/MapAmbience.server.luau` — DUPLICATE yard allocation (L3-4, L122-186) + owner billboard (OwnerBillboardAnchor/OwnerBillboard, AlwaysOnTop, 400 studs)
- `/home/user/riooblox/src/ServerScriptService/YardAllocator.luau` — Pure Claim/Release allocator
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotDevelopment.luau` — Reconcile: PlotAppearance.Apply + BestFinds.Reconcile + player attrs; VisitShop (COSMETICS terminal); Start: OwnerUserId listeners
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotRules.luau` — PlotSkins normalize/migration (PlotProgressionVersion), Buy/Claim/EquipPlotSkin actions, kennel unlock Assign gate, Validate
- `/home/user/riooblox/src/ReplicatedStorage/PlotCatalog.luau` — 9 stages + 14 skins (prices x5 mutated at load L33), Level/Slots/Cost/Earned/Requirement
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau` — Frame(yard), Apply (base recolor + kennel unlock + procedural PlotDevelopment incl. BestFinds stand L140-177, garden L181-254), Preview (whole-yard clone)
- `/home/user/riooblox/src/ReplicatedStorage/PlotGeometry.luau` — Procedural primitives; all parts non-collidable/non-query (L3-10)
- `/home/user/riooblox/src/ReplicatedStorage/PlotInteractionAccess.luau` — Owner + interaction-zone + 9-stud check (zones: Storage/Sell/Upgrade only)
- `/home/user/riooblox/src/ServerScriptService/Economy/BestFinds.luau` — Automatic MY BEST FINDS selection (Select L12-28), server exhibit clones (L36-54), Reconcile/Clear by ExhibitToken
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotShowcase.luau` — Dog display models in DogStorage.DisplaySlots from p.DisplayDogs
- `/home/user/riooblox/src/ServerScriptService/Economy/DisplayRules.luau` — p.DisplayDogs Normalize/Assign (3 slots, owned, not Walking)
- `/home/user/riooblox/src/ServerScriptService/Economy/RecordStats.luau` — Stats summaries BestShowcaseFind/Relic, Heaviest, MostValuable, Rarest (BestFinds source)
- `/home/user/riooblox/src/ServerScriptService/Economy/YardCommerce.luau` — Yard lookup, Visit/StorageVisit, CanSell, BulkSell/NPCSell, YardInteraction prompts (Start L115-133)
- `/home/user/riooblox/src/ServerScriptService/DogKennelService.luau` — Reference walk-up model: per-kennel ProximityPrompt (L248-262) -> DogKennelOpen; kennel dog Reconcile; dead DogKennelRequest Handle
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau` — ASSIGN DOG picker opened by kennel prompt; idempotent mutate() with retained requestId (L82-106)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — Routes DogKennelOpen/DogEconomyOpen/RewardPresentation to screens (L170-180)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau` — COSMETICS screen: skins, whole-yard 3D preview per draw, buy/claim/equip, stage block, titles list
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/StorageScreen.luau` — DOG STORAGE page: choose dog displays 1-3
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DogsScreen.luau` — displayDog / atStorage flow (L567-760)
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau` — MY YARD page; clones all visible yard parts into a viewport
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau` — Owner/zone gating of YardInteraction prompts only
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlotSkinMotion.client.luau` — Client float/mist animation with distance caps
- `/home/user/riooblox/src/ServerScriptService/Economy/FeatureRegistry.luau` — Plug-in point for new features (Normalize/Validate/Action/Snapshot)
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Project() calls PlotDevelopment/Kennels/PlotShowcase reconcile (L164-167); Request visit checks (L419-424)
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — I.Get(p,uid,transfer) used by trade/lab/SellItem: hook for showcase protection; ItemLock disabled
- `/home/user/riooblox/src/ServerScriptService/MiningWorld.server.luau` — MiningCorner on CosmeticGarden; coverGround watches PlotDevelopment (L289-317)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Stare.luau` — Depends on BestFinds.Slots.Dog.Exhibit and DogStorage.DisplaySlots paths (L19-25)
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotDevelopmentTests.luau` — Stale Studio-only test (never called)
- `/home/user/riooblox/src/ServerScriptService/Economy/EstateQATests.luau` — Stale Studio-only QA (never called)

### Сохраняемые данные

- Upgrades.Plot (0..8): yard stage-1, PlotCatalog.Level = 1+Plot; bought via UPGRADE TREE node Plot (Config.Upgrades.Plot Base 8000 Factor 2.35 Max 8); +2.5% dug value per level
- Upgrades.Kennel: KENNEL QUALITY dug-value bonus
- PlotSkins {[skinId]=true}: owned whole-yard skins, Classic forced true (PlotRules.Normalize)
- EquippedPlotSkin (string): equipped skin, reset to Classic if unknown/unowned
- PlotProgressionVersion (=1): one-time migration flag (legacy dog slots -> Plot level, GoldenKennel/CyberKennel/VoidAura -> GoldenHour/DogRush/TheVoid)
- DisplayDogs {['1'..'3']=DogUid}: dogs on DOG STORAGE display bays (DisplayRules)
- Stats.BestShowcaseFind / Stats.BestShowcaseRelic: item summaries by highest SellValue (RecordStats.Find) feeding BEST FINDS
- Stats.Heaviest / MostValuable / Rarest: also offered to BestFinds.Select
- Cosmetics {}: legacy kennel cosmetics (GoldenKennel, CyberKennel, VoidAura, FounderPlaque) AND collection titles (Finds<n>, Dex<n>, Set<x>, Prestige<n>)
- EquippedCosmetic (string): equipped title/kennel cosmetic (shown over kennel dogs; read by PlotRules legacy migration)
- Dogs[uid].AssignedSlot ('DigSlot_1..5'), State, OwnerUserId, Variant, Mastery: kennel and display rendering
- Items[uid] (CombinedOdds, Class, Mutation, WeightKg, TierIndex, SellValue, Favorite) and DiscoveryFeed: exhibit sources
- WorldEventsSeen[EVENT], Lifetime.GlobalDigContribution, Prestige, UnlockedLayers['5']: skin claim conditions (PlotCatalog.Earned)
- DataStore DOGROTS_ECONOMY_V1, key 'p:<UserId>' (StoreKeys.Wrap), JSON <= 3.5 MB; Config.Version=4; MegaResetVersion=1 carry list excludes PlotSkins/DisplayDogs/Upgrades
- Runtime player attributes: YardId, YardSpawnPosition, WaitingForYard, YardLevel, UnlockedKennels, EquippedPlotSkin, YardStageName
- Yard attributes: YardId, OwnerUserId, OwnerDisplayName, PlotStage, PlotSkin, UnlockedKennels, AppearanceRevision, DigSlotSize, YardFootprint; DigSlot attrs Unlocked/RequiredYardLevel/SlotIndex/DigCenter/DigSize/ApproachPosition/AssignedDogUid/AssignedOwnerUserId/AssignedDogName; BestFinds slot ExhibitToken; DisplaySlot DogUid; part attrs PlotBase*, PlotFloat, PlotMist, model attr PlotShowcase

### Сеть

- DogEconomyRequest (RemoteFunction, C->S, InvokeServer(action,args,requestId)): BuyPlotSkin{Id}/ClaimPlotSkin{Id} (COSMETICS terminal only), EquipPlotSkin{Id}, DisplayDog{Slot,Uid} (DOG STORAGE zone only), Assign{Uid,Slot}/Remove{Uid} (no proximity check), Upgrade|TreeUpgrade{Kind='Plot'}, SellQuote/NPCSell/BulkSell/SellLoot (collector zone), Cosmetic{Kind} (titles), RecordClaim{Count}, Snapshot{} (full profile copy)
- DogEconomyOpen (RemoteEvent, S->C, page[,message]): 'Collector','UpgradeTree','Storage' from YardInteraction prompts; 'Cosmetics' from COSMETICS ShopTerminalPrompt
- DogKennelOpen (RemoteEvent, S->C, slotName) from kennel MANAGE prompt -> GUIIntegration -> ServiceMenus 'Kennels'
- DogKennelRequest (RemoteFunction, C->S, action,uid,slotName): bound to DogKennelService.Handle but no client caller (dead surface)
- RewardPresentation (RemoteEvent, S->C): Sell cue after NPCSell; PadSelector for lucky pads on the plot
- DiscoveryReveal (RemoteEvent, S->C): find payload with LootSpawn CFrame of the yard pit (KennelLootPlacement)
- ProximityPrompts (server-created): YardInteraction x3/yard (SellAnchor/UpgradeAnchor/StorageAnchor, 9 studs, LOS, hold .15), kennel MANAGE x5/yard (Attachment KennelInteraction, 10 studs), PlaceLuckyBlock x3/yard, MiningCorner prompts, COSMETICS ShopTerminalPrompt
- Planned: PlotShowcaseOpen / PlotInteractionOpen RemoteEvent (S->C, kind,slot,yardId) created at runtime by server Start (build.py cannot add instances)

### Объекты мира

- Workspace.DOGROTS_District.04_PlayerYards (12,454 instances): Yard_01..Yard_08 Models (1,556 each), EntranceAnchor, WorldEventSpawnPoints
- Yard_0N.YardLandscape: YardFoundation 134x1x70 (centers x=+-105, z in -117,-39,39,117), EntryWalk 124x9, UtilityApron, WorkArea 47x62, CosmeticGarden 39x22, LuckyCourt 37x21, PadTrim x6, hidden Post x49 / Rail x10
- Yard_0N.DogStorage (DisplaySlots/Slot1..3 + SlotCaption, DisplayPlinth/Glass, Terminal, StorageTitle), Vendor (521 parts), Workshop (618 parts, ServiceTitle), StorageRoofMascot
- Yard_0N.DigSlot_1..5 (DarkExcavation 12x0.4x12 + LootSpawn attachment, PitTimber, KennelFloor/Back/Wall/Lintel/Roof, SlotMarker, DogBowl) with DigCenter/DigSize/ApproachPosition attrs
- Yard_0N.LuckyPad_1..3, SellAnchor/UpgradeAnchor/StorageAnchor + Sell/Upgrade/StorageInteractionZone (PlotInteractionRegion), YardSpawn
- Yard_0N.PlotDevelopment (generated; base place has baked L1 Classic copy) incl. BestFinds model (Slots/Find|Dog|Relic, NameX/CategoryX signs, ShowcaseTitle) at frame (20*sx,0,55)
- Yard_0N.YardCustomization: unused legacy sockets (KennelSocket, BowlSocket, BedSocket, ToySocket, ShowcaseSocket, LightSocket, SignSocket, CenterpieceSocket, FenceSockets, GroundThemeArea, UpgradeSockets, CosmeticRuntime); some overlap MiningCorner
- Runtime-created: Yard_0N.MiningCorner (MiningWorld, pad 23x18 at frame (-18*sx,0,-6.5)), Yard_0N.OwnerBillboardAnchor (MapAmbience)
- Workspace.DOGROTS_District.KennelDogs (kennel dog models), 11_Shops.COSMETICS (InteractionAnchor, ShopInteriorZone), NavigationAnchors.PlayerYards (0,2,110), DistrictSpawn
- ServerStorage.DogTemplates (101 dogs, avg 5 parts), ReplicatedStorage.DiscoveryModels (108 items, avg 29 / max 105 parts), ReplicatedStorage.MenuModels (101)
- Workspace.StreamingEnabled=true, MinRadius 64, TargetRadius 1024; yards ModelStreamingMode Default

### Точки расширения

- Economy/FeatureRegistry: drop-in Features/Showcase.luau and Features/Decor.luau (Normalize/Validate/Action/Snapshot) without editing Rules
- Rules.Profile defaults auto-fill missing keys on old profiles in Rules.Normalize
- Runtime.Request visit-check block (L419-424): add ShowcaseVisit/DecorVisit like DisplayDog->StorageVisit
- Runtime.Project (L164-167): publish yard attributes (ShowcaseLayout, DecorLayout) and reconcile world
- YardCommerce.CanSell: exclude showcased items from BulkSell/SellQuote/NPCSell/Snapshot.SellableItems
- ItemRules.Get(p,uid,transfer=true): single hook protecting showcased items from trade offers/commit (Engine L300/L336), lab catalysts (LabRules L40) and SellItem
- PlotInteractionAccess zones table: add ShowcaseAnchor->ShowcaseInteractionZone, DecorAnchor zones
- DogKennelService.Start prompt pattern (Attachment + ProximityPrompt + server owner/distance/Allow check + FireClient open)
- GUIIntegration remote routing (DogKennelOpen handler L176) for a new PlotShowcaseOpen/PlotInteractionOpen event
- ServiceMenusController.mutate idempotent requestId pattern for editor actions
- Kit (Window, CardGrid Kind='Item', Preview.Register('Decor', ...)) - UIKIT.md already names showcase editor and decor placement
- PlotCatalog.Stages rows: add ShowcaseSlots/DecorCap per stage as single source of truth
- PlotAppearance.showcase()/garden() and PlotGeometry primitives as procedural builders for decor
- Museum client-local display pattern (MuseumPresentation.client, DogDexLocalDisplays, moving VIEW prompt) for client-rendered exhibits/decor
- PlotSkinMotion attribute-tag animation (PlotFloat/PlotMist) with distance caps for rarity FX
- MenuModels dog templates (avg 5 parts) reusable as dog statues
- MapRouting destinations (PlayerYards -> own YardSpawn) for navigation to showcase/decorate

### Улучшить поверх

- F3 as Features/Showcase with Auto mode (identical to today's BestFinds.Select) and Manual mode; keep the BEST FINDS stand geometry and add stage-gated slots
- Showcase protection via YardCommerce.CanSell and ItemRules.Get(transfer) with 'ON SHOWCASE' badges in inventory/collector/trade
- Per-pedestal ProximityPrompts on persistent anchors outside PlotDevelopment, cloned from the kennel prompt pattern; owner-only gating in PlotPrompts
- Gate kennel MANAGE and lucky pad prompts for non-owners on the client (PlotPrompts) - quick UX fix
- Make showcase foundation/pedestals collidable (override CanCollide on the few structural parts)
- PlotShopScreen: wrap A.Preview in pcall and rebuild only when the selected skin/level token changes (like UpgradeTreeScreen's EstateToken) instead of every 5 s
- YardPageController: rebuild yard preview only when AppearanceRevision changes
- Shared ReplicatedStorage/ItemRarity (tier + color from CombinedOdds/Class/Mutation) for showcase FX, inventory and trade
- BestFinds.Select: read Stats summaries + a cached top-N instead of scanning all Items on every Project
- Replace stale Studio tests with Lune tests (tests/showcase.luau, tests/plot_rules.luau, tests/decor.luau) using tests/lib/economy_env
- Decor v1 on predefined socket/grid zones with a strict part budget (can stay server-built if the client-render refactor is postponed)
- Move titles out of PlotShopScreen into the F10 title UI; keep skins + decor in a Kit 'MY PLOT' window

### Аккуратный рефакторинг

- Single yard-ownership pipeline: remove the duplicate allocator in MapAmbience.server (keep its billboard, subscribe to OwnerUserId), one 'owner changed' signal for PlotDevelopment/PlotShowcase/DogKennelService/MiningWorld/LuckyLifecycle
- Move cosmetic PlotDevelopment generation to clients (attribute-driven: PlotStage/PlotSkin/PlotFrame/PlotMirror/ShowcaseLayout/DecorLayout) with LOD and streaming awareness; keep kennel unlock visibility/collision/prompts server-side; port MiningWorld.coverGround, Stare paths, previews, QA
- Split PlotAppearance into PlotGameplay (server) and PlotArt (shared data-driven motif builders) so F8 can add many pieces without if/elseif chains
- PlotCatalog: explicit prices instead of the x5 mutation at load; single source for stage cost (Config.Upgrades.Plot vs PlotCatalog.Cost)
- Shared display-model normalizer (bounds/scale/tint/strip scripts) used by BestFinds, PlotShowcase, DogKennelService and future F4/F12 visuals
- Unified PlotInteraction prompt factory (kennels, showcase, decor, lucky pads): server check + client gating + one open event; delete dead DogKennelRequest
- Consistent visit policy: decide whether Assign/DisplayDog/Showcase/Decor require proximity on the server

### Найденные баги

- Duplicate yard allocation: YardService.server.luau and MapAmbience.server.luau both run their own Allocator and write the same OwnerUserId/YardId attributes (both Disabled=false in build/DOGROTS_MINING.rbxl); consistent only by determinism
- YardService/MapAmbience updateSign is a no-op: no OwnerPlaque exists in the place (0 matches)
- Kennel 'MANAGE' prompts (DogKennelService L254-256) and lucky pad 'CHOOSE BLOCK' prompts are visible to visitors on other players' yards; kennel trigger silently does nothing (PlotPrompts gates only YardInteraction)
- All generated plot decoration incl. BEST FINDS stand, pedestals, fences and gates has CanCollide=false (PlotGeometry.Part L7): players walk through the showcase
- PlotShopScreen clones the entire yard + runs PlotAppearance.Apply into a ViewportFrame on every Render, and Menus re-renders every 5 s (Menus.Fetch L71-72, Update L215); A.Preview is not pcall-protected and A.Frame indexes yard.YardLandscape.YardFoundation/StorageAnchor directly (can error if parts are streamed out)
- YardPageController.geometry clones every visible yard part (up to ~3.5k) into a viewport every 20 s while MY YARD is open
- PlotDevelopment is fully destroyed and rebuilt (up to 2,260 instances per yard, TimeWarp L9) on every stage/skin/owner change; join+leave each cause two rebuilds replicated to all clients
- PlotDevelopmentTests.luau and EstateQATests.luau are stale and never invoked: they expect 300 starting cash (now 4200), BoneRain 1200 (now 6000), PlotDevelopment < 1800 descendants (TimeWarp L9 = 2260), and UpgradeVisit('Plot') to fail (now returns true)
- BEST FINDS 'Find' pedestal only accepts Treasure class (23/108 item defs); 84 defs go to Relic, so Find usually shows low-value junk; selection is fully automatic (no player choice)
- No item protection exists (ItemLock disabled in ItemRules L24/L204); only Favorite blocks lab use; SELL ALL can sell anything
- DogKennelRequest RemoteFunction is bound (DogKennelService L237) but unused by clients (ServiceMenusController declares kennelRemote L15 and never calls it)
- BestFinds.Select scans all p.Items (<=1000), DiscoveryFeed and Dogs on every Runtime.Project (after each request and each dog work tick)
- Duplicated helpers/constants: bounds/visibleBounds and Variant tint tables in PlotShowcase and BestFinds; PlotShowcase.Reconcile hard-codes 1..3 while DisplayRules.Slots=3; PlotCatalog multiplies skin Cash x5 at module load (L33)
- Inconsistent proximity policy: Assign works from anywhere, DisplayDog requires StorageVisit
- Potential (unconfirmed): RecordStats.Find compares x[k] > s[cat][k] without nil guard; a legacy summary missing the field would error inside I.Mint

## Приложение: `lab` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ServerScriptService/Economy/LabService.luau` — Server entry: Visit/Info/Request (LabInfo, LabPreview, LabCommit with RAM quotes and Tx), TryOpen, Start (creates GeneticsPrompt on InteractionAnchor)
- `/home/user/riooblox/src/ServerScriptService/Economy/LabRules.luau` — Pure procedure rules: Preview (validation + signed plan), Apply (all save-data writes), Catalog, Public, Rows=R.VariantRows
- `/home/user/riooblox/src/ServerScriptService/Economy/LabState.luau` — p.Lab Normalize/Validate (Version hardcoded 1; Validate asserts DNA keys exist in LabConfig.DNA)
- `/home/user/riooblox/src/ServerScriptService/Economy/LabRecipeConfig.luau` — Server-only recipe list (3 recipes)
- `/home/user/riooblox/src/ReplicatedStorage/LabConfig.luau` — Lab balance: procedures/levels, costs, stability, catalysts, stabilizers, DNA keys, genetics, extraction, HighValue, variant Colors, Cooldown/Duration/Distance
- `/home/user/riooblox/src/ReplicatedStorage/LabGenetics.luau` — Shared client/server rules: Check/Fix eligibility, ValueReasons, Cost, Stability, Chances, Extraction, Duplicates, FillRecipe, VariantColor
- `/home/user/riooblox/src/ReplicatedStorage/LabAccess.luau` — Terminal reach check: InteriorZone + 7.5 studs to InteractionAnchor + line-of-sight raycast
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau` — C.Variants (dog mutations: weights/bonuses, lines 40-48), C.Ascension, C.Prices
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau` — VariantRows/Variant/VariantUpgrade (odds incl. world events + DogMutation), Discover (VariantDex), Mint, Bonus (variant income multiplier), Pay, Validate (calls LabState.Validate)
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Request dispatch to LabService (line 385); post-processing Refresh/StateSnapshot (lines 442-466); allow() rate limiter
- `/home/user/riooblox/src/ServerScriptService/Economy/Transactions.luau` — RAM-first atomic Tx:Run (copy-on-commit, receipts) used by LabCommit
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/LabScreen.luau` — 1869-line kit window: 3 steps, species grid, 5 action cards, recipe book/picker, DNA bank, confirm modal with hold, result card, splash with SHOW THE WAY
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/LabPresentation.luau` — Local-only chamber cinematic (camera from PresentationCamera, cloned MechanicalRing, neon traces, light recolor, dog clone from MenuModels, Skip)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau` — Enables prompt by LabAccess.CanUse every 0.15 s and localizes it to Russian
- `/home/user/riooblox/src/ReplicatedStorage/LabAudioConfig.luau` — 12 lab sound cues from built-in Roblox sounds; AssetIds for uploads
- `/home/user/riooblox/src/ReplicatedStorage/Localization/Lab.luau` — Russian dictionary (Exact/Patterns/UI/Templates) for lab window and server replies
- `/home/user/riooblox/src/ServerScriptService/Economy/World.luau` — World.Start calls LabService.Start (ordering hook for a reactor builder)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — openLab routing (lines 97-116), N.BeginReward/EndReward (UI hiding during cinematics), N.Navigate/N.Travel
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldDetailQuality.client.luau` — Global light/emitter culler for everything under DOGROTS_District (affects reactor FX)
- `/home/user/riooblox/src/ServerScriptService/RewardMachinePresentation.server.luau` — Reference pattern for public shared-attraction presentation: server clock, queue, Personal fallback, RemoteEvent
- `/home/user/riooblox/src/ServerScriptService/MiningWorld.server.luau` — Reference pattern for runtime (server-start) world geometry building with LAYOUT_VERSION
- `/home/user/riooblox/tests/lab.luau` — 24 Lune tests of lab rules, protocol, localization, audio (all pass)
- `/home/user/riooblox/docs/LAB.md` — Player/owner documentation of the current lab

### Сохраняемые данные

- p.Lab.Version - always set to 1 by LabState.Normalize (no migration path yet)
- p.Lab.DNA {key=int<=1e6} - DNA inventory from Extraction/failed recipes; keys MUST stay in LabConfig.DNA or LabState.Validate breaks every transaction
- p.Lab.DiscoveredDNA {key=true} - DNA kinds ever owned
- p.Lab.Recipes {RecipeId=os.time} - discovered recipes
- p.Lab.History[<=40] {Token,At,Procedure,RecipeId,Secret,Stability,Consumed,DNA,Success,Duration,ReturnedArtifacts,Message,FirstDiscovery,Dog=slim} - experiment log, also the commit idempotency store (by Token)
- p.Lab.FirstDiscoveries {'MUTATION:<Variant>'|'DNA:<key>'|'RECIPE:<id>'=os.time} - first-time results (any lab result dog incl. ascend/recipe)
- p.Lab.Experiments int - total committed procedures
- p.Lab.Tier 1..5 - unlocked procedure tier derived from p.Level
- p.Lab.LastAt os.time - last procedure (7 s chamber cooldown)
- p.Lab.TutorialComplete bool - first Mutation is free until true
- p.Lab.PaidDNA bool - set when a PaidRandom dog was extracted; currently taints every later reroll/ascend (bug)
- p.Dogs[uid].Variant string (Normal/Shiny/Golden/Corrupted/Glitched/Void) - the dog mutation; saved data, never rename
- p.Dogs[uid].AscensionLevel 0..3 - written by ASCEND
- p.Dogs[uid].PaidRandom bool - propagated by lab Apply
- p.Dogs[uid].LabRecipe / Origin='LAB_FUSION'|'LAB_EXPERIMENT' / PricePaid=0 - recipe-made dogs
- p.DogDex[DogId], p.VariantDex[DogId][Variant]=true - via Rules.Discover on reroll/mint
- p.Items[uid] - catalysts/stabilizers consumed by Targeting/recipes (ordinary dig finds)
- p.Cash, p.Bones - paid via Rules.Pay
- DataStore DOGROTS_ECONOMY_V1 key p:<UserId> (profile); supply:<DogId> {Minted} serial counter touched by recipe mints

### Сеть

- RemoteFunction ReplicatedStorage.DogEconomyRequest client->server InvokeServer('LabInfo', {}, requestId) -> {Tier, Level, Recipes, Cooldown, CooldownEndsAt, Now, VariantRows, TutorialComplete}
- RemoteFunction DogEconomyRequest 'LabPreview' {Procedure, Uids<=3, Items<=4, DNA, RecipeId, StabilizerUid, PrimaryUid} -> public plan {Cash, Bones, DNA, Chances, StrangeChance, Rewards, Consumed, Valuable, HighValue, Destructive, Reroll, SuccessChance, Output*, Token, Expires}
- RemoteFunction DogEconomyRequest 'LabCommit' {Token(32), Confirm=true, Acknowledge?, Typed?} -> result {Token, At, Procedure, RecipeId, Secret, Stability, Consumed, DNA, Success, BeforeDog, Dog, Duration, ReturnedArtifacts, Message, FirstDiscovery} + StateSnapshot (full profile)
- RemoteFunction DogEconomyRequest one-tap fixes used by LabScreen: 'DogLock' {Uid, Enabled=false}, 'DogFavorite' {Uid, Enabled=false}, 'Remove' {Uid}
- RemoteFunction DogEconomyRequest 'DistrictTravel' {Destination='Lab'} - teleport to NavigationAnchors/MutationLab (lab entrance)
- RemoteEvent ReplicatedStorage.DogEconomyOpen server->client FireClient(player,'Lab') when GeneticsPrompt triggers
- ProximityPrompt 05_MutationLab.InteractionAnchor.GeneticsPrompt (server Triggered -> LabService.TryOpen)
- Legacy Rules.Action 'Retire'|'Mutation'|'Ascend'|'Fusion' -> rejected with 'Use the genetics terminal...'
- No lab RemoteEvent for presentation exists (cinematic is local-only); proposed: RemoteEvent LabMutationShow server->nearby clients {UserId, Name, DogId, From, To, Rarity, StartAt, Duration, Mode}; proposed action 'LabReroll' {DogUid, Token, Cost, Acknowledge?}

### Объекты мира

- Workspace.DOGROTS_District.05_MutationLab - Model X8..156 Y0..57 Z428..527 (building X84..156), 983 parts, ModelStreamingMode Default
- 05_MutationLab.InteriorZone - invisible rotated Part, X86..152 Y1..33 Z430..524 (LabAccess zone)
- 05_MutationLab.InteractionAnchor - (125.3,5.8,502) parent of GeneticsPrompt; next to Stations.GeneticsTerminal X126..132 Z497..507
- 05_MutationLab.CentralChamber - X125..143 Y2..33 Z457..497 (139 parts): DisplayAnchor (134,8,477) facing -X, MechanicalRing (112 parts), ClearContainment, ChamberStatus.Lettering.StatusText, EnergyBase/CrownEnergy/MutationNode (used by LabPresentation)
- 05_MutationLab.PresentationCamera (109,20,477), AudioAnchor (123,10,477), EntranceAnchor (78,3,477), LocationLabelAnchor (119,57,477, label 'Lab')
- 05_MutationLab.TechnicalRoof.CentralSkylight - Glass T0.94 at Y37.9 over X96..142 Z461..493; LanternBeam/LanternCrossbar Y38..39; CrossRoof X142..154; AirHandlers X92..102/139..149 up to Y45; Antenna to Y49
- 05_MutationLab.CeilingServices.StructuralCrossBeam at X=99/122/144, Y34.9, along Z448..506 (would cross a tube at X134)
- 05_MutationLab.PanelFloor top Y=2.29; free central nave X86..125 x Z458..496 (only lights/camera anchors)
- 05_MutationLab.Stations (GeneticsTerminal, MutationAnalysis, DNAExtractor, DNAArchive, FusionStation, Reagent/ResearchWorkbench, FusionObservationTank, 2x ArchiveSampleCapsule X147..153), Subject008Chamber X118..134 Z434..453, ResearchArchiveWall X150..153 - decor with outdated texts (DNA EXTRACTION, FUSION / CREATE)
- 05_MutationLab.GlassFacade (LaboratoryAutomaticDoor, LabTitle 'MUTATION LAB'), PromenadeConnection (EntryWalk hidden by MapRefresh)
- Workspace.DOGROTS_District.NavigationAnchors.MutationLab (78,3,477) with Target ObjectValue - used by MapRouting/DistrictTravel/DistrictGuide
- Neighbours: 08_GlobalDigSite from Z532 + 37_AttractionRefresh.GlobalEventComingSoon black cube X33..214 Z531..745; 11_Shops/SUPPLIES X115..156 Z374..416; east court X156..~216 with ProgressionGardens.Cypress X165..177 Z509..521 and PocketGardens.Broadleaf X174..180 Z484..490; island edge X~216
- ReplicatedStorage.MenuModels - 101 dog models (569 parts) cloned by the cinematic; ServerStorage.DogTemplates - recipe output templates (LabRules.TemplateReady)
- workspace.LocalGeneticsFX - client-only FX folder created during the cinematic (outside DOGROTS_District, so WorldDetailQuality does not throttle it)

### Точки расширения

- LabConfig tables (Procedures with new Enabled flags, Costs -> new Reroll curve, Colors, Cooldown, Duration, Distance)
- LabGenetics shared functions (Check/Fix for the dog picker, ValueReasons for hold-confirm, Cost -> add RerollCost, Chances for the odds bar)
- LabRules: add pure Reroll(p,a,now,random,token) beside Preview/Apply; Preview procedure gate for retired procedures
- LabService.Request action dispatch (add 'LabReroll') and LabService.Start (prompt texts, create LabMutationShow RemoteEvent)
- Runtime.Request lab dispatch line 385 and post-processing lines 442-466 (StateSnapshot / Refresh exclusions)
- LabState.Normalize - migration hook to p.Lab.Version=2 (legacy DNA conversion)
- LabAccess - zone/anchor names; moving InteractionAnchor relocates the whole prompt+access logic
- World.Start ordering - place a LabReactorWorld.Install() before LabService.Start()
- LabPresentation.Play(result)/Skip() contract used by LabScreen.play (replace with LabCinematic keeping the same API)
- LabScreen public API Open/Close/Build/ShowResult/SetView/State (GUIIntegration, EconomyScreens, onboarding, emulation harness)
- GUIIntegration N.BeginReward/N.EndReward (UI hiding during cinematic), N.Navigate (SHOW THE WAY)
- MapRouting.Anchor key + Target ObjectValue redirect (inner waypoint to the console for F1)
- LocationLabels config entry Roof/Clearance for the lab label above the new tube
- WorldDetailQuality exemption attributes (LuckyVisual, MuseumLight) - add one for reactor FX
- LabAudioConfig.AssetIds for uploaded SFX; Localization/Lab dictionaries
- RewardMachinePresentation queue/Personal pattern for public shows
- tests/lab.luau harness (fake LabAccess + runtime) for new reroll tests

### Улучшить поверх

- Add server action LabReroll (one round-trip, Token idempotency, expected-cost check, hold-ack for valuable variants) reusing G.Check, R.VariantRows, R.Pay, rt.Tx:Run and p.Lab.History
- Rarity-scaled reroll price curve in LabConfig.Reroll + shared G.RerollCost (client shows, server charges)
- Fix PaidRandom taint: use l.PaidDNA only when the procedure spends DNA (LabRules.Apply)
- Retire Targeting/Extraction/Creation via LabConfig.Procedures Enabled=false (code kept one release) instead of deleting
- Move InteractionAnchor (same name) to the new console so LabService/LabAccess/LabPrompt keep working; change prompt texts to ACTIVATE / MUTATION MACHINE (+RU in LabPrompt.client)
- Public show RemoteEvent LabMutationShow with server-clock StartAt and a queue (RewardMachinePresentation pattern), distance-filtered FireClient
- Skip Runtime.Refresh for read-only LabInfo/LabPreview; send a small StatePatch instead of a full StateSnapshot after rerolls
- Upload real SFX via LabAudioConfig.AssetIds; add reactor idle hum/charge loops
- Update outdated texts: EconomyScreens:126, MapRouting:11, OnboardingGuide:27, station SurfaceGuis, docs/LAB.md
- New titles/achievements fed by p.Lab.Experiments / new p.Lab.Rerolls / FirstDiscoveries['MUTATION:Void']

### Аккуратный рефакторинг

- p.Lab migration to Version 2 (LabState.Normalize currently forces Version=1): legacy DNA snapshot + conversion to RerollCredits or coins, idempotent; keep LabConfig.DNA keys because LabState.Validate asserts them
- Replace 1869-line LabScreen with a simple console menu (pick dog -> cost -> MUTATE -> result/AGAIN) while keeping its public API used by GUIIntegration/EconomyScreens/onboarding
- Replace LabPresentation with a pooled, timeline-based LabCinematic bound to new reactor anchors (CentralChamber/MechanicalRing names disappear); respect WorldDetailQuality and ReducedMotion/LowFX
- Runtime reactor world builder (LabReactorWorld + LabReactorConfig blueprint): reversible hiding/cutting of CentralChamber, CentralSkylight, StructuralCrossBeams X=122/144, LanternBeam/Crossbar, part of CrossRoof; relocate LocationLabelAnchor
- Unify the 7 variant palettes (LabConfig.Colors/Theme.Variant, EconomyVisuals, DogLineSpawner, PlotShowcase, BestFinds, PreviewRenderer, LuckyLifecycleFX) into one VariantVisuals module (tests/uikit.luau checks the lab palette)
- Owner decision + refactor for ASCEND (keep as contextual button or move to Dogs screen)
- Remove legacy PawpadController LabPage sections (Mutation/Ascend/Retire) and tests for retired procedures after one release

### Найденные баги

- LabRules.Apply: `local paid=l.PaidDNA==true` applies to every procedure, so once a player extracted any PaidRandom dog, every later plain Mutation (no DNA spent) or Ascend sets dog.PaidRandom=true, restricting its trade/market for accounts where IsPaidItemTradingAllowed=false (confirmed with a Lune script: Breadog PaidRandom nil -> true after a Mutation with p.Lab.PaidDNA=true)
- Reroll pricing nearly flat (G.Cost: 5000+1500*rank coins, 5*rank bones): Secret 14,000 coins = 0.025% of its 55M BasePrice vs Common 6,500 = 186%; with shelter price BasePrice*0.25*Rules.Bonus, rerolling a Secret to Void (~500 tries ~7M coins + 15k bones) raises its shelter value by ~15M and doubles income - an economic arbitrage (bones may limit it; bone income not measured)
- Runtime.Request sends read-only LabInfo/LabPreview through Runtime.Refresh -> Runtime.Project (PlotDevelopment/Kennels/PlotShowcase Reconcile + attribute writes) on every lab open/preview (Runtime.luau:446-452)
- LabState.Normalize hardcodes p.Lab.Version=1 (no migration mechanism); LabState.Validate asserts every p.Lab.DNA key exists in LabConfig.DNA, so removing DNA keys from config would make R.Validate throw 'Invalid DNA inventory' in every transaction of affected players
- Variant colours are inconsistent across 7 modules (e.g. Corrupted is red 209,64,83 in the lab UI but purple 184,67,233 on kennel dogs in EconomyVisuals.client and 226,92,255 on the conveyor; Glitched purple in lab vs cyan 40,239,213 on kennel dogs)
- A stabilizer used with plain Mutation lowers Void/Glitched odds (LabGenetics.Chances multiplies them by 0.55 when stabilizer>0 and no target) while only reducing StrangeDNA chance - counter-intuitive item effect
- The cinematic and the chamber status/light changes are local only: other players in the lab see nothing
- LabService keeps one quote per player (S.Quotes[userId]); a second preview invalidates an open confirm ('Preview expired'); LabService.Start indexes Access.Model() without a nil check
- Legacy PawpadController LabPage still shows a 'Retire' section (no such procedure) and several texts (EconomyScreens:126, MapRouting:11, OnboardingGuide:27, station SurfaceGuis) describe old lab actions

## Приложение: `ui` — списки


### Ключевые файлы

- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — Navigation owner (N): Acquire/Close/OpenPage/OpenScreen/OpenService/Navigate/Notify, P/B/Esc keys, DogEconomyOpen/DogKennelOpen/RewardPresentation handlers, dispatch/ready() gate (requires InventoryController registration), applies UITheme shell and starts BuffHUD/OnboardingGuide on require
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/UITheme.luau` — Legacy tokens and builders (U.Colors/Rarity/Button/Panel/Modal/Icon), runtime restyle ApplyShell/ApplyStandalone/EnhanceButton (DescendantAdded on main gui), LayoutHUD/WatchHUD/SafeArea/TouchReserve, WindowSpecs/WindowChrome, HUD QuickTiles creation; clones styles from YardPage
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Menus.luau` — Generation-B window manager: Snapshot fetch every 5s, full ClearAllChildren rebuild in Render, 0.5s Update scanning descendants, idle 15s Snapshot poll for OfflineEarnings notice
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadRuntime.client.luau` — Creates Menus, 0.5s Heartbeat ticker, client-only non-persisted settings (ReducedMotion, WorldEventFX, PlayerList)
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadController.client.luau` — Static MainWindow page bindings (mostly dead pages), switch(), SearchKeyboard, HUD PAWPAD/BAG buttons, MenuNavigation, registers switchPage source
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau` — Current BAG: tabs FINDS/COLLECTION/LUCKY BLOCKS, cycle filters, non-virtualized card per item, details actions (Favorite/Lock/Sell/Market) with overloaded meanings, 6s Snapshot poll, 0.5s padPrompts loop, registers N.RegisterInventory (global toast) and writes HUD BAG capacity
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryView.luau` — Pure row projection/filter/sort for the bag (reusable for the new inventory)
- `/home/user/riooblox/src/StarterGui/ScreenGui/HUD/HUDStatsController.client.luau` — Level/XP, GlobalDig (hidden widget), IncomeChip (+$/min, FINDS FULL)
- `/home/user/riooblox/src/StarterGui/ScreenGui/HUD/MoneyWidget/MoneyController.client.luau` — Wallet text with roll-up animation and auto width
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau` — MY YARD static page; clones ~1237 yard parts into a ViewportFrame every 20s; YardPage is also the style template for UITheme/ServiceUI
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau` — Seller (multi-select bulk sell, no confirmation, includes favorites), Kennels assign, Layers; 5s poll
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenus/ServiceUI.luau` — Hand-built frames for ServiceMenus, cloned from YardPage instances
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit.luau` — New UI kit entry (docs/UIKIT.md)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Window.luau` — Kit windows: open/close motion, phone sheet, tabs, stacking, navigation
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Theme.luau` — Kit design tokens (mirrors UITheme, synced by tests/uikit.luau)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Motion.luau` — Tween helper; Reduced() ignores the in-game ReducedMotion attribute
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Base.luau` — Text/Icon/Press(hover-press)/Face/Layer (KitWindows 60, KitModals 62, KitOverlay 95)/SafeArea
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Nav.luau` — Kit <-> GUIIntegration glue (Acquire Kit, DismissDialog wrap, gamepad B)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Virtual.luau` — VirtualGrid/List (bounded instances)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Cards.luau` — DogCard/ItemCard/CardGrid
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Preview.luau` — Cached ViewportFrame previews (2/frame, 48 shelf), Register for new kinds
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Net.luau` — Shared Snapshot cache, Request with request id, Changed signal, DogEconomyPush handlers
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DogsScreen.luau` — Kit reference implementation (search/chips/sort/CardGrid/compare) to copy for the new inventory
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Equipment/EquipmentScreen.luau` — Kit window with bag grid and multi-select salvage bar (pattern for bulk sell); titled SHOP
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/LabScreen.luau` — Kit multi-step genetics lab (F12 replacement target)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/UpgradeTreeScreen.luau` — Kit upgrade tree
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DogdexScreen.luau` — Kit Dogdex + DexEntry
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` — Legacy Menus screens: Yard(compact), Trade, Settings, Help, Extras, Layers, Loot; undefined Screens.Lab call at line 185
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DiscoveryScreens.luau` — Legacy duplicate item UIs: Discoveries/Inspect/Collection/Marketplace/Records/Listing/CreateListing
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/CommerceShopScreen.luau` — PAW MARKET (legacy Menus)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EventsScreen.luau` — WORLD EVENTS (legacy Menus), own rarity palette
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau` — YARD STYLES / Cosmetics (legacy Menus) - F8 target
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/StorageScreen.luau` — DOG STORAGE display dogs (legacy Menus) - the 'stand editing' pattern for F3
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/CollectorScreen.luau` — Dead legacy collector with SELL ALL without confirmation
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/BuffHUD.luau` — Active boost cards on HUD (0.25s Heartbeat layout)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau` — 18-step tutorial card + world marker; hardcoded pickaxe price text
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadStatsController.client.luau` — Header stats of hidden MainWindow header (effectively idle)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau` — RU auto-translation of every text in PlayerGui+workspace (1908 exact, 108 patterns, 441 phrases + Localization/*); perf/leak notes
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DOGROTS_RU_ScreenPatch.client.luau` — Duplicate targeted RU patch (Lab/Layers/Offline), ignores NoTranslate
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlaceTypography.client.luau` — Forces FredokaOne on all texts unless KeepFont
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/LocalScript.client.luau` — Debug leftover that force-translates 'DOGS' labels via ru-ru for every player (delete)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/KitDemo.client.luau` — Studio-only kit showcase (K)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau` — District map (M), Waypoint billboard, ClearMarker, NavigateDistrict handler - F1 hook
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` — Dog variant highlights, EconomyCosmetic title billboards over dogs, pooled IncomePopups billboards in PlayerGui
- `/home/user/riooblox/src/ReplicatedStorage/GameIcons.luau` — Uploaded icon registry (22 ids), aliases, preload
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningAudio.luau` — Built-in sound recipes (Click, Buy, Deny, Whoosh) reusable for UISound
- `/home/user/riooblox/src/ReplicatedStorage/RewardAudio.luau` — Reward cues; looks for missing DOGROTS_AUDIO.UI SoundGroup
- `/home/user/riooblox/src/ReplicatedStorage/AudioSource.luau` — Audio id resolution; LocalAudioManifest files only in Studio GameId==0
- `/home/user/riooblox/src/ServerScriptService/Economy/YardCommerce.luau` — Server BulkSell (no favorite protection, requires collector zone), yard prompts (Collector/UpgradeTree/Storage)
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — Snapshot (full profile copy), request rate limiter (8 tokens,1.5/s), player attributes for HUD, DogEconomyPush
- `/home/user/riooblox/src/ReplicatedStorage/PlotInteractionAccess.luau` — Zone+9 stud rule for collector/storage/upgrade actions
- `/home/user/riooblox/tests/uikit.luau` — Kit unit tests incl. theme sync with UITheme/LabConfig and kit word localization coverage

### Сохраняемые данные

- p.Items[ItemUid]: ItemUid, ItemId, DisplayName, Depth(1-5), Class(Artifact/Treasure/Special/Secret/World Find), WeightKg, WeightTier(10 tiers), TierIndex, Mutation(NORMAL/GOLDEN/RAINBOW/CURSED/GLITCHED), CombinedOdds, BaseDropChance, SellValue, ValueBreakdown{Version,Rarity,Factors,Raw,Cap}, FoundAt, Favorite(bool, only field the UI writes via ItemFavorite), Tradeable, EventTag, Origin, SourceDogUid, FirstFind, IncomeMult; Locked is wiped by ItemRules.Normalize (ItemLock disabled)
- p.Collection[ItemId]=true (discovered set), p.DiscoveryFeed (20 latest finds), p.HeavyCollection, p.ItemSets, p.Stats (Heaviest/MostValuable/Rarest/BestShowcaseFind/BestShowcaseRelic)
- p.OwnedBlocks[uid]{Tier,State(Stored/Placed/Ready),Slot,ReadyAt,PurchasedAt,Quantity} and p.LuckyCredits[tier]=count (Lucky Blocks tab)
- p.Upgrades.Storage -> item capacity = min(1000, 50+25*Storage+bonuses) (ItemRules.Capacity); attribute ItemCapacity/ItemCount
- p.Dogs[uid].Favorite / .Locked (DogFavorite/DogLock), p.DexFavorites, p.DexClaims, p.DisplayDogs[slot]=DogUid (DisplayDog via StorageScreen)
- p.Cosmetics (incl. Dogdex titles Dex10..Dex100, Discovery:<set>:Normal/Heavy) and p.EquippedCosmetic (shown as billboard over dogs); p.PlotSkins/p.EquippedPlotSkin
- p.Onboarding + attributes TutorialStep/TutorialActive/TutorialStatus/TutorialVersion (action 'Tutorial')
- p.Listings (market listings, max 10) created from the bag 'LIST ON MARKET'
- Server-set player attributes read by HUD/UI: EconomyReady, Level, XP, XPRequired, ItemCount, ItemCapacity, ItemFull, InventoryRevision, OwnedBlockCount, AvailableBlockCount, ActiveBlockCount, IncomePerMinute, GlobalDigTotal, CurrentLayer, LayerName, YardId, YardLevel, DogCapacity, LatestFoundItem, LuckExpires_<tier>, SupplyExpires_<key>, PendingCash, EventTokens, DogDexCount; leaderstats.Coins and player.Bones
- Client-only NOT persisted: attributes ReducedMotion, WorldEventFX, LowFX, PlayerList visibility (PawpadRuntime) - reset every session
- Proposed new optional fields (additive, safe for old saves): p.Settings{Motion,Sounds,Music,WorldEventFX,HideHint}, p.InventorySeenAt (NEW badges), p.Showcase{Slots} (F3), p.EquippedTitle (F10)

### Сеть

- DogEconomyRequest (RemoteFunction, client->server): (action, args, requestId) -> ok, result(+StatePatch/StateSnapshot). UI actions: Snapshot, ItemFavorite{Uid,Enabled}, BulkSell{Uids}, List{Kind='Item',Uid,Mode='BuyNow',Price}, MarketQuery, Assign{Uid,Slot}, Remove, DogFavorite, DogLock, DexClaim{Count}, DexFavorite, DisplayDog{Slot,Uid}, Layer{Layer}, SellLoot, Trade{Action=Offer/Ready/Confirm/Accept,...}, TradeRequest{Target}, TradeCancel, Tutorial{Action}, DistrictTravel{Destination}, EventClaim
- DogEconomyOpen (RemoteEvent, server->client): (page, message) -> GUIIntegration OpenPage/OpenScreen (yard prompts Collector/Storage/UpgradeTree, shop terminals, Lab, Events, Trade invite)
- DogKennelOpen (RemoteEvent, server->client): (slot 'DigSlot_N', yardId) -> ServiceMenus Kennels
- DogEconomyPush (RemoteEvent, server->client): (kind, data) -> Net.OnPush handlers (kit screens)
- RewardRequest (RemoteFunction): CancelBlockOffer, RewardMachineInfo, lucky/machine actions
- RewardPresentation (RemoteEvent, server->client): {PromptFeedback|LuckyOffer|PadSelector|OpenedBlock|Message|Announcement|Credits|Cue}
- DiscoveryReveal (RemoteEvent, server->client): triggers bag/yard refresh
- DogKennelRequest (RemoteFunction): ServiceMenus kennel ops
- CommunityOpen (RemoteEvent) + ShelterRequest/FeedbackRequest/CommunityFeedbackRequest (RemoteFunctions): CommunityClient shelter/feedback
- BindableEvents in ScreenGui (client only): MenuNavigation(command 'Close'|'Service'|'Page', name), NavigateDistrict(destinationName), ToggleDistrictMap()
- Client polling of full Snapshot: Menus idle 15s (always), Menus page 5s, Inventory 6s, YardPage 8s, Pawpad static pages 8s, ServiceMenus 5s; server limiter 8 tokens refilling 1.5/s

### Объекты мира

- StarterGui.ScreenGui (main, ResetOnSpawn=false, ScreenInsets=DeviceSafeInsets, 3105 descendants): HUD (PawpadWidget, InventoryWidget, MoneyWidget, XPWidget, GlobalDigWidget, Quick* tiles), MainWindow (Header/Sidebar hidden, Content.PageContainer with 9 pages: Yard, Dogs*, DogDex*(1512 inst), Trade, Lab*, Shop*, Events*, Discoveries*, Inventory; *=dead), ServiceMenus, Backdrop, InventoryToast, Modules, BindableEvents
- Workspace.DOGROTS_District.04_PlayerYards.<Yard_NN_*> (attrs OwnerUserId, YardId): SellAnchor+SellInteractionZone, StorageAnchor+StorageInteractionZone, UpgradeAnchor+UpgradeInteractionZone, DigSlot_1..5, LuckyPad_1..3 (PlaceLuckyBlock prompt, LuckyBlockUid/LuckyBlockReady), MiningCorner (MiningPad, MiningPickaxeShop, MiningOreCore, MiningStrengthRack), YardSpawn, DogStorage.DisplaySlots; ~1430 parts each (1237 visible) cloned by YardPage preview
- Workspace.DOGROTS_District.03_DogLine.ActiveDogs and KennelDogs (EconomyVisuals billboards/highlights, PromptFeedback LuckyPrompt)
- Workspace.DOGROTS_District.11_Shops.InteractionAnchors.Marketplace and shop InteractionAnchors (DogEconomyOpen pages)
- Workspace.DOGROTS_District.05_MutationLab (LabAccess, GeneticsPrompt at InteractionAnchor)
- Workspace static: 644 SurfaceGui, 801 text objects, 5 BillboardGui (LocationLabel x4, DistantPortalEmission), 3 ProximityPrompts; most prompts/billboards are runtime-created
- ReplicatedStorage.DiscoveryModels (108 models, 3225 parts) for item previews; ReplicatedStorage.MenuModels (101 models, 569 parts) for dog previews
- ReplicatedStorage.WorldEvents.State (EventId/State/EndTimestamp attrs) and ServerLuckState (Multiplier/EndsAt)
- SoundService.DOGROTS_AUDIO with only SoundGroups WorldEvents and Music (no UI/SFX group)
- PlayerGui.TouchGui.JumpButton (UITheme.TouchReserve)
- Runtime PlayerGui layers: KitWindows/KitModals/KitOverlay, MiningGui, MiningShop, MiningToast, CommunityServices, LuckyArrival*, Secret*/EventCinema/EventGameplay FX layers, DOGROTS_IncomePopups folder, TutorialWorldMarker

### Точки расширения

- GUIIntegration routing wrapper pattern (dogScreens, lines 222-246): wrap N.OpenPage/N.OpenScreen to send a page key to a Kit module (Inventory, Trade, Shop, Events, Showcase, Decor, Titles, Mutator)
- N.RegisterInventory / N.Notify: replace the legacy toast sink with Kit.Toast (must stay registered or dispatch never flushes)
- Kit.Window Key = existing page names so OpenMenu checks, B/P keys and sidebar logic keep working
- Main gui attributes OpenMenu, MenuFamily, ModalOwnerCount, CompactMenus, LandscapeMenus, HUDInnerLeft/HUDInnerRight and U.HUD table (layout zones for new HUD widgets)
- UITheme.LayoutHUD / U.QuickTiles: add or remove HUD tiles and badges; WatchHUD for relayout
- Kit.Preview.Register(kind, builder, keyer): Decor, Title and LOD item previews
- Kit components: CardGrid, Chips, SortSelect, SearchBox, Confirm(hold), Countdown, EmptyState, Toast, Tooltip, LongPress
- Net.Snapshot/Net.Changed/Net.OnPush(kind) + Runtime.PushTo(player,kind,data) for push-driven UI instead of polling
- DogEconomyOpen(page) from server prompts: new world interactions (showcase, mutator console, decor) open Kit windows
- NavigateDistrict BindableEvent / N.Navigate(destination): every SHOW THE WAY CTA already funnels here - a single place to plug F1 real paths
- ReplicatedStorage.Localization/<Feature>.luau {Exact,Patterns,Phrases} and Kit.T(en,ru) + NoTranslate/KeepFont attributes
- GameIcons.Assets/Aliases (extend with an atlas) and Kit.Icon/Base.IconImage resolution
- Audio AssetIds tables (MiningAudio/LuckyAudio/LabAudioConfig/WorldSoundConfig) - pattern for a UISound module with built-in fallbacks
- Player attributes as reactive UI data (InventoryRevision, ItemCount, IncomePerMinute...) and a new client attribute UIHidden for F9

### Улучшить поверх

- Delete StarterPlayerScripts/LocalScript.client.luau (debug ru-ru 'DOGS' translator for everyone)
- Kit.Motion.Reduced() should also honour player attribute ReducedMotion; Settings buttons should show ON/OFF state
- Create SoundService.DOGROTS_AUDIO.UI SoundGroup + ReplicatedStorage/UISound.luau; hook Kit Base.Press (click/hover), Window.Open/Close, Tabs, Feedback.Toast and UITheme.EnhanceButton -> sounds nearly everywhere with a few call sites
- Server favorite protection in YardCommerce.BulkSell (skip Favorite unless explicitly allowed) and Kit.Confirm on ServiceMenus Seller SELL SELECTED / SELECT ALL excluding favorites
- Bag stop-gap: show rarity (ValueBreakdown.Rarity) + value chip on cards, hide NORMAL, show SELL only inside collector zone (PlotInteractionAccess.CanUse client-side) else a 'GO TO COLLECTOR' CTA; stop padPrompts loop when hidden
- Remove Menus idle 15s Snapshot poll; drive the offline notice from PendingCash attribute or DogEconomyPush
- YardPage: one-shot or static preview instead of cloning ~1237 parts every 20s
- HUD badges (new finds, claimable Dex rewards, ready Lucky block) from existing attributes
- Narrow AutoTranslate: skip English players, do not scan whole workspace, do not cache strings with digits; fold RU_ScreenPatch into Localization modules
- Unify rarity/variant palettes (EventsScreen, PawpadController, EconomyVisuals, InventoryController) onto Kit.Theme
- Show keyboard shortcut hints (P/B/M/H) as small key glyphs on HUD tiles for desktop
- Rename the Equipment window ('SHOP') to avoid clashing with PAW MARKET

### Аккуратный рефакторинг

- Retiring the static InventoryPage: move N.RegisterInventory/N.Notify sink and HUD BAG capacity writing first, then remove UITheme ApplyShell/ApplyStandalone/AttachNavigation references (CandyStart, MobileBagBack, filter styling)
- Removing dead static pages (DogsPage, DogDexPage, LabPage, ShopPage, EventsPage, DiscoveriesPage ~2257 instances): clean UITheme and PawpadController references (SearchKeyboard clones DogsPage.Sort/DogCount, DexGrid buttons)
- Decoupling UITheme/ServiceUI from YardPage instances used as style templates (cardTemplate, headerTemplate, ActionButtons)
- Making GUIIntegration a pure navigation module (no ApplyShell/BuffHUD/Onboarding side effects on require) and relaxing ready() so a missing legacy registrar cannot stall all menus
- Migrating Menus (B) screens to Kit one by one with routing wrappers; eliminating ClearAllChildren rebuild polling
- Single design-token source: Kit.Theme authoritative, UITheme reading from it (tests/uikit.luau sync)
- Localization architecture: from global text interception (AutoTranslate on PlayerGui+workspace) to self-localized Kit.T + per-feature dictionaries with coverage tests; exact keys break on every English text edit
- One device-independent route per feature (Trade/Yard currently differ between desktop and CompactMenus)
- Unifying item UIs (InventoryPage, DiscoveryScreens Discoveries/Collection/Records, ServiceMenus Seller, CollectorScreen, Loot) into one Inventory window with modes
- Global UI visibility layer (F9) that coordinates with scripts that toggle Enabled/Visible themselves and with GUIIntegration prompt/movement locks

### Найденные баги

- src/StarterPlayer/StarterPlayerScripts/LocalScript.client.luau: debug leftover. After 3 s it translates every PlayerGui text 'DOGS' with the ru-ru translator for EVERY player; GetTranslatorForLocaleAsync is called without pcall. If the cloud table has 'DOGS', English players see Russian on the DOGS HUD tile (cloud table not checkable from the file).
- Favourited items are not sell-protected: YardCommerce.CanSell/BulkSell ignore Favorite. ServiceMenusController SELECT ALL (lines 150-155) selects favourites, and SELL SELECTED (268-275) sells without confirmation. CollectorScreen 'SELL ALL FINDS' also has no confirmation (currently unreachable).
- InventoryController 'SELL TO MILO' is shown anywhere, but the server BulkSell requires standing inside SellInteractionZone within 9 studs (PlotInteractionAccess); away from the collector it fails with 'Visit the collector in your own yard'.
- InventoryController classColors uses non-existent classes Junk/Organic and lacks 'World Find'. 66 of 108 items are 'Artifact', so cards are uniformly purple. Item rarity (ItemValuation / ValueBreakdown.Rarity) is never shown in the bag.
- GUIIntegration.ready() (line 21) requires inventoryReward from InventoryController's N.RegisterInventory. Removing or renaming the legacy bag would leave every N.OpenPage/OpenScreen queued forever. N.Notify (global toast) and the HUD BAG capacity label also live in InventoryController.
- Bag is not virtualised: one cloned card (19 descendants) per item, up to HardCap 1000 (~19k instances); a full Snapshot poll every 6 s while open.
- InventoryController padPrompts loop runs every 0.5 s forever, even when the bag is closed (lines 539-548).
- Menus idle poll: every player requests a full profile Snapshot every 15 s while no menu is open (Menus.Update line 205), only for the offline-earnings notice.
- Menus.Render does canvas:ClearAllChildren and rebuilds the whole page on every 5 s fetch (recreating ViewportFrames, EnhanceButton connections and translation watchers); Menus.Update scans all canvas descendants every 0.5 s.
- YardPageController clones all ~1237 visible parts of the yard into a ViewportFrame every 20 s while MY YARD is open.
- EconomyScreens.luau line 185 calls undefined Screens.Lab (unreachable today because Lab routes earlier).
- Kit.Motion.Reduced() ignores the in-game Motion setting (player attribute ReducedMotion); settings (Motion, WorldEventFX, PlayerList) are not persisted and the Settings buttons do not show their state (EconomyScreens line 215).
- Missing SoundService.DOGROTS_AUDIO.UI / SFX SoundGroups: RewardAudio and WorldSound look up 'UI', LabAudioConfig looks up 'SFX'; there are no UI sounds at all.
- Inconsistent palettes: EventsScreen rarityColors (Common green, Rare purple, Secret red), PawpadController rarityColors, and EconomyVisuals variant colours (Corrupted purple, Glitched teal) vs Kit.Theme.Variant (Corrupted red, Glitched magenta).
- Same feature, different UI by device: Trade and Yard open static pages on desktop and Menus screens on CompactMenus (GUIIntegration line 104); DogEconomyOpen 'Trade' always uses Menus.
- Dead static pages (DogsPage, DogDexPage, LabPage, ShopPage, EventsPage, DiscoveriesPage; ~2257 instances, 544 text objects) are still restyled, translated and animated at startup. PawpadController keeps bindings, including a workspace:GetDescendants() fallback in showPreview (line 171).
- DOGROTS_AutoTranslateUI watches every text object in PlayerGui and workspace for all players, including English ones. The cache grows without bound on dynamic strings (cache[source]=source, line 2545). DOGROTS_RU_ScreenPatch ignores the NoTranslate attribute and duplicates dictionaries.
- Hardcoded balance text in OnboardingGuide ('Wooden Pickaxe (600 Coins)', '7 pickaxes, 7 weights, 12 ores') duplicated as exact RU keys in AutoTranslate (lines 149, 156): a balance change silently breaks the translation.
- RewardScreens ItemsHardCap 'MY ITEMS' (line 297) opens DiscoveryScreens Collection instead of the bag; there are 4-6 parallel UIs for the same items.
- Keyboard shortcuts P/B/M are undiscoverable (the Sidebar with 'P OPEN / CLOSE' is hidden by ApplyStandalone). Two windows are titled SHOP (PAW MARKET and Equipment). The bag shows two titles (WindowChrome 'MY BAG' and the in-page 'INVENTORY').

## Приложение: `trade-titles` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ServerScriptService/Economy/Engine.luau` — Trade server state machine: CancelTrade (270), TradeRequest (277), fingerprint (286), Trade Accept/Offer/Ready/Confirm + RAM commit (289-355); Leave cancels trade (44)
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — DogEconomyRequest routing for TradeRequest/TradeCancel/Trade (432-438), RefreshAll after every successful Trade step (452), Snapshot Trade view + Players list (329-366), rate limit allow (314), clean (320), PushTo/DogEconomyPush (579-585), Project sets player attributes (105-168)
- `/home/user/riooblox/src/ServerScriptService/Economy/Transactions.luau` — RAM-first transactions; trade uses _runFast (435); _runDurable (561) is the journaled atomic path to use for Trade 2.0
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau` — R.Dog strict eligibility (99), Pay/Credit (106/111), Transfer + OwnerHistory (225); Cosmetic equip (522), RecordClaim Finds titles (459), SetClaim (532), Prestige (537); MegaReset carry list incl. Cosmetics (56)
- `/home/user/riooblox/src/ServerScriptService/Economy/ItemRules.luau` — I.Get transfer checks (45: Tradeable, RecordJob; no Favorite check), I.Transfer (54), Discovery:<set> title (212), item SellValue frozen at find (195)
- `/home/user/riooblox/src/ServerScriptService/Economy/PaidRandomPolicy.luau` — PolicyService IsPaidItemTradingAllowed with 120 s cache; yields on miss (root of the Confirm race)
- `/home/user/riooblox/src/ServerScriptService/Economy/PaidItemPolicy.luau` — P.Allowed(user) wrapper used by Engine trade and Market
- `/home/user/riooblox/src/ServerScriptService/Economy/LabService.luau` — Consumer of Engine.TradeByUser (23,45): blocks lab while trading
- `/home/user/riooblox/src/ServerScriptService/Economy/ShelterService.luau` — Consumer of Engine.TradeByUser (35,41,52) via ShelterRules.Eligible
- `/home/user/riooblox/src/ServerScriptService/Economy/YardCommerce.luau` — Consumer of Engine.TradeByUser (50): blocks Milo bulk sell; CanSell (40); live ItemValuation price (56)
- `/home/user/riooblox/src/ServerScriptService/Economy/Market.luau` — Cross-server durable market (escrow, 5% tax, sales history medians in Query 272) - valuation source and design reference
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` — Current trade UI Screens.Trade (255-363): player list, session view, dog/find toggles, UPDATE/LOCK/CONFIRM/CANCEL
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Menus.luau` — Menus windows: 5 s Snapshot poll (Fetch 70), full rebuild (Render 177 ClearAllChildren), Update every 0.5 s (203); persistent TradeDogs/TradeItems state (14)
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadController.client.luau` — Static TradePage renderer renderTrade (277-296), player search (416), 8 s refresh loop
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — Navigation owner; DogEconomyOpen 'Trade' force-opens trade screen (172-175); Acquire locks movement/prompts (47-85); page routing (99-130)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Net.luau` — Client Net.Request/Snapshot/OnPush (DogEconomyPush) - push channel for Trade 2.0 and title unlocks
- `/home/user/riooblox/docs/UIKIT.md` — UI kit contract (Window Key='Trade', VirtualGrid/CardGrid, SearchBox, Chips, SortSelect, Hold buttons, Countdown, Confirm modal)
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DexRewards.luau` — Only pretty title names (Dex10..Dex100 TitleName)
- `/home/user/riooblox/src/ServerScriptService/Economy/Features/Dogdex.luau` — Dex claim grants p.Cosmetics[tier.Title] (134-137); shadows Rules DexClaim
- `/home/user/riooblox/src/ServerScriptService/Economy/Features/Passes.luau` — Game-pass cosmetics re-derived from ownership (Apply 12-24)
- `/home/user/riooblox/src/ServerScriptService/Economy/FeatureRegistry.luau` — Normalize/Validate/Action/Snapshot hooks - home for Features/Titles.luau
- `/home/user/riooblox/src/ServerScriptService/DogKennelService.luau` — Copies profile.EquippedCosmetic onto kennel dog models (196)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` — EconomyCosmetic BillboardGui over every kennel dog (27-37) - current only 'title' display
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau` — COSMETICS 'YOUR COLLECTION TITLES' equip list (67-77), raw ids for non-Dex titles
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotRules.luau` — One-time migration reads p.EquippedCosmetic (14) - constraint for F10 migration
- `/home/user/riooblox/src/ReplicatedStorage/PlotCatalog.luau` — Earned/Requirement pure condition pattern (38-58) to copy for title unlocks
- `/home/user/riooblox/src/ServerScriptService/Economy/CommunityService.luau` — Legacy XP board, Server King selection every 15 s (RefreshKing 60), developer mailbox (Submit 67)
- `/home/user/riooblox/src/ServerScriptService/Economy/ServerKingPresentation.luau` — Giant king avatar head + KingLabel billboard on ServerKingMonument
- `/home/user/riooblox/src/ServerScriptService/Economy/LeaderboardService.luau` — 6 all-time OrderedStore boards; Cache per category usable for dynamic 'Top N' titles
- `/home/user/riooblox/src/ServerScriptService/Economy/RecordStats.luau` — p.Stats incl. CompletedTrades, TotalFinds, SecretFinds, BestTier, milestones
- `/home/user/riooblox/src/ServerScriptService/Economy/LifetimeStats.luau` — p.Lifetime playtime/coins/globaldig/support (title conditions)
- `/home/user/riooblox/src/ServerScriptService/Economy/EquipmentWorld.luau` — Welded hat/face/back/feet accessories on characters (AttachPoint 47) - overhead title must clear hats
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau` — Tutorial step 15 describes current trade flow (29)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau` — RU translations of all trade strings
- `/home/user/riooblox/src/ServerScriptService/Economy/CommunityQATests.luau` — Dead module (never required)
- `/tmp/claude-0/-home-user-riooblox/31f25513-e9ea-5617-95f8-e2b4b703717b/scratchpad/tools/trade-titles/tradesim.luau` — Audit simulation of the real Engine trade flow (invite lock, stale expiry, gifts, empty trades, RAM-only commit, durable swap feasibility) - basis for tests/trade.luau
- `/tmp/claude-0/-home-user-riooblox/31f25513-e9ea-5617-95f8-e2b4b703717b/scratchpad/tools/trade-titles/race.luau` — Reproduction of the critical Confirm/Offer race (bait-and-switch) through PaidRandomPolicy yield

### Сохраняемые данные

- p.Stats.CompletedTrades (RecordStats.Normalize): +1 per side on every committed trade, including empty/one-sided ones (farmable)
- p.Dogs[uid].OwnerHistory[] {UserId, At, Type='Trade'|'Mint'|'Rebuy'|'BuyNow'|'Auction'} capped at 100, + EarlierTransfers counter (Rules.Transfer)
- p.Dogs[uid].OwnerUserId/State/AssignedSlot reset by Rules.Transfer; Favorite carried over
- p.Items[uid].OwnerUserId (ItemRules.Transfer; no owner history; Favorite carried over; SellValue frozen at find time)
- p.Cash (trade cash moves with R.Pay/R.Credit isEarned=false, not counted in Lifetime.TotalCoinsEarned)
- p.Cosmetics {[key]=true}: title/cosmetic unlocks - Dex10/30/50/70/90/100 (+legacy Dex25/Dex75), Finds25..Finds2500, Discovery:<setKey>, Set<SetName>, Event1..5, Prestige<N>, SupporterTitle, EventSupporter, GoldenKennel, CyberKennel, VoidAura, FounderPlaque; carried through MegaReset (Rules.Normalize:56)
- p.EquippedCosmetic (string): currently equipped cosmetic/collection title; drives kennel dog badges; read by PlotRules one-time migration when PlotProgressionVersion is nil
- p.DexClaims, p.ItemSets, p.Stats.Milestones/Claims, p.Event.Claims: claim ledgers behind title unlocks
- p.Lifetime {TotalPlaytimeSeconds, TotalCoinsEarned, GlobalDigContribution, SupportRobux}: title conditions + leaderboards
- p.Stats {TotalFinds, TotalDigs, SecretFinds, BestTier, LongestStreak, BestDayCount, TotalSellValue, BiggestSale, Heaviest, MostValuable, Rarest, Depths}: title conditions
- p.Level/XP, p.Prestige, p.UnlockedLayers, p.Mining.{OresBroken,CoinsEarned,PickaxeLevel,Strength}, p.Lab.Experiments, p.WorldEventsSeen, p.PlotSkins: title conditions
- DataStore DOGROTS_ECONOMY_V1 keys 'p:<userId>' (record {Value,Revision,Lock,Writer}) and 'tx:<id>' journals; trades write no keys of their own today
- OrderedDataStores DOGROTS_TOP_XP_V2_REBOOT1 (CommunityConfig) and DOGROTS_LB_{SUPPORT,PLAYTIME,COINS,DISCOVERIES,GLOBALDIG,DOGDEX}_V2_REBOOT1 (LeaderboardConfig)
- Mailbox keys mailquota:<id>:<day>, feedback:<hour>:<userId%16> (CommunityService.Submit)
- RAM only: Engine.Trades[tid]={Id,Users,Version,Offers{[uidStr]={Dogs,Cash,Prints,Details,Items,ItemPrints,Estimated}},Ready,Confirmed,Expires,Inviter,Accepted,UpdatedAt,ConfirmDelay,ConfirmAfter,Committing}; Engine.TradeByUser[userId]=tid (contract read by LabService/ShelterService/YardCommerce/Runtime.Snapshot/tests/lab.luau)
- PROPOSED p.Titles={Version=1, Equipped='', Unlocked={[id]=unixTime}, New={[id]=true}, CheckedAt}
- PROPOSED p.TradeHistory ring (<=20) {Id, With, At, Gave{dogs,items,cash}, Got{...}, Value}; p.Stats.TradePartners (unique count) + bounded recent partner list; p.Settings.TradeRequests='All'|'Off'

### Сеть

- DogEconomyRequest (RemoteFunction, C->S) action 'TradeRequest' {Target:userId} -> Engine:TradeRequest; no receipt; sets TradeByUser for both immediately
- DogEconomyRequest action 'TradeCancel' {} -> Engine:CancelTrade (either participant)
- DogEconomyRequest action 'Trade' {Action='Accept'|'Offer'|'Ready'|'Confirm', Dogs={uid<=6}, Items={uid<=6}, Cash:int, Version:int} -> Engine:Trade; on success Runtime.RefreshAll() + StateSnapshot reply
- DogEconomyRequest action 'Snapshot' -> includes Trade (copy of session incl. Offers.Details) and Players[{Id,Name(DisplayName),Username,Level,Status,Trades,Listings}]
- DogEconomyRequest actions for titles: 'Cosmetic' {Kind} (equip collection title / buy legacy cosmetic), 'DexClaim' {Count}, 'SetClaim' {Set}, 'RecordClaim' {Count}, 'EventClaim' {Milestone}, 'Prestige' {}
- DogEconomyOpen (RemoteEvent, S->C) ('Trade', 'Trade invitation from <DisplayName>') -> client GUIIntegration force-opens trade screen and locks controls
- DogEconomyPush (RemoteEvent, S->C, created in Runtime.Start; client Net.OnPush(kind)) - currently only 'EquipmentCredits'; PROPOSED kinds 'TradeInvite', 'TradeState', 'TradeClosed', 'TitleUnlocked'
- FeedbackRequest (RemoteFunction, C->S) {Text, Category, Request} -> CommunityService.Submit (mailbox, proximity 22 studs, TextService filter)
- CommunityFeedbackRequest (RemoteFunction, C->S) -> DeveloperInbox.Request (proximity 18)
- CommunityOpen (RemoteEvent, S->C) 'Shelter' | 'Feedback'
- ShelterRequest (RemoteFunction, C->S) -> ShelterService.Request (blocked while TradeByUser set)
- Replicated attributes: Player.{Level,XP,...~60 from Runtime.Project}; kennel dog model attribute EquippedCosmetic (DogKennelService:196). PROPOSED Player attributes TitleId (string) and ServerKing (bool)

### Объекты мира

- StarterGui.ScreenGui.MainWindow.Content.PageContainer.TradePage (ServerPlayersPanel.Search/Players.PlayerCardTemplate/Players.Empty/Title, PlayerDetailsPanel.Username/Stats/RequestTrade/TradeNotice, Status) - indexed by PawpadController; keep instance even if hidden
- StarterGui.ScreenGui.MainWindow.Sidebar.TradeButton (CandyPage=Trade) - sidebar entry
- StarterGui.ScreenGui.HUD.QuickTrade.Open (CandyPage=Trade) - HUD shortcut, rebuilt at runtime by UITheme (Quick* frames)
- Workspace.DOGROTS_District.32_WelcomeHub.ServerKingAnchor + CommunityCourt.ServerKingMonument (KingInfo SurfaceGui KingPresentation, CrownGlow) - Server King presentation (CommunityService WaitForChild on these)
- Workspace.DOGROTS_District.32_WelcomeHub.DeveloperMailbox.MailboxBody (FeedbackPrompt) and DogShelter.SellAnchor.ShelterPrompt - community services
- Workspace.DOGROTS_District.09_DogPark.LeaderboardPlaza (attributes Categories=6, Boards=3; Honor/Discovery/Legacy board parts) - LeaderboardRenderer SurfaceGuis
- Workspace.DOGROTS_District.KennelDogs - kennel dog models carrying EquippedCosmetic attribute; EconomyVisuals hangs EconomyCosmetic billboards here
- Players.MaxPlayers=60, Workspace.StreamingEnabled=true (TargetRadius 1024, MinRadius 64), StarterPlayer.NameDisplayDistance=100 - drive title culling and player-list sizing
- Player characters: EquipmentWorld welded accessory models (Hat on Head top, Face, Back, Feet) - overhead title offset must account for Hat; no existing BillboardGui on characters
- No static trade world location exists (only Workspace.DOGROTS_District.13_TheVoid has a static BillboardGui; all others are runtime-created)

### Точки расширения

- Economy.FeatureRegistry: drop-in Features/Titles.luau with Normalize/Validate/Action('TitleEquip')/Snapshot - no central list to edit
- Transactions:Run with an extra durable key (e.g. 'tl:<tradeId>') forces the journaled _runDurable path: atomic two-profile commit + audit record + idempotent replay by request id (verified in scratch simulation)
- Engine.Trades / Engine.TradeByUser tables: keep as the shared contract while moving logic to a new TradeService
- Runtime.Request routing (Runtime.luau:432-438) - add TradeService.Request(player, action, args, receiptId) like LabService/OnboardingService routes
- Runtime.PushTo + DogEconomyPush + client Net.OnPush: real-time TradeState / TradeInvite / TitleUnlocked without polling
- Runtime loopOnce step(): add 'trades' sweep (expiry) and cheap title evaluation
- Runtime.Project: single place to set Player attribute TitleId
- CommunityService.RefreshKing (15 s): set ServerKing attribute for a dynamic crown title
- LeaderboardService.Active.Cache[categoryKey]: top-10 rows for optional dynamic 'Top N' titles
- PlotCatalog.Earned/Requirement pattern: shared pure unlock/progress functions for titles
- Kit (Window Key='Trade'/'Titles', CardGrid/VirtualGrid, SearchBox, Chips, SortSelect, Button Hold, Countdown, Confirm Cards, Preview.Register) for both new screens
- GUIIntegration.OpenPage/OpenScreen routing: send 'Trade' to TradeScreen.Open() as is done for Lab
- ReplicatedStorage.Localization/<Feature>.luau + DOGROTS_AutoTranslateUI for RU strings
- ItemValuation.Price / DogDefinitions BasePrice + Config.Variants bonus / Market Query medians: server-side trade value display
- EquipmentWorld.Prefix accessory models on characters: client can measure hat height for title offset
- tests/payments_lib/loader.luau + memory store: proven harness for a new tests/trade.luau and tests/titles.luau

### Улучшить поверх

- Hotfix the Confirm race in Engine:Trade: capture version and a deep copy of t.Offers and set t.Committing before calling PaidPolicy.Allowed; re-check version after the call; commit from the frozen copy
- Make invitations non-blocking: separate Invites table, set TradeByUser only on Accept; replace forced N.OpenScreen with an Accept/Decline toast; per-pair and per-inviter cooldowns; decline/ignore option
- Add a periodic sweep that cancels expired invites/sessions (fixes stale TradeByUser blocking lab/shelter/sell)
- Refresh only the two participants instead of Runtime.RefreshAll on trade steps; push TradeState instead of full snapshots
- Ignore repeated Ready (do not restart ConfirmAfter once both are ready)
- Do not count empty/one-sided trades in CompletedTrades; track unique partners
- Client: clear TradeDogs/TradeItems/TradeCash when a session closes and prune against inventory; countdown via c.Now()/Kit.Countdown; sort finds; hide non-Tradeable/record-pending items
- Show @username + avatar + level in the session header and in invites
- Exclude Favorite items and displayed dogs by default (selectable with a warning) and reset Favorite on transfer
- Give every p.Cosmetics key a readable name (Finds/Discovery/Event/Prestige/Set/Supporter) in DexRewards-like table
- Remove dead code: CommunityQATests (or wire it into tests), Rules.Action 'DexClaim' branch

### Аккуратный рефакторинг

- Move trade logic out of Engine.luau into Economy/TradeService.luau + pure TradeRules.luau while keeping Engine.Trades/TradeByUser fields for LabService, ShelterService, YardCommerce, Runtime.Snapshot and tests/lab.luau
- Switch the trade commit to the durable Transactions path (journal + atomic write of both profiles + 'tl:<id>' audit) and handle its latency (status 'Saving...', retry with same request id)
- Replace both current trade UIs (PawpadController.renderTrade static page and EconomyScreens.Screens.Trade in Menus) with one Kit window; keep TradePage instances hidden because code indexes them
- Separate 'player titles' (new p.Titles + overhead billboard) from kennel dog badges (p.EquippedCosmetic) without breaking PlotRules migration or existing p.Cosmetics grants
- Server valuation module shared by trade value display and Milo sale (live ItemValuation.Price, not stored SellValue)

### Найденные баги

- CRITICAL (reproduced in scratch race.luau): Engine:Trade 'Confirm' (Engine.luau:317-327) calls PaidPolicy.Allowed after both confirmations and before setting t.Committing. When a PaidRandom asset is in either offer and the 120 s policy cache is stale, the call yields; a parallel 'Offer' from the same player then replaces their offer, and the commit reads the new t.Offers. Result: the attacker keeps their assets and receives the victim's (bait-and-switch).
- HIGH (reproduced): TradeRequest sets TradeByUser for the target before acceptance (Engine:284). The invitee is blocked from lab (LabService:23,45), shelter (ShelterService:35-52) and Milo sale (YardCommerce:50) for up to 240 s. Client force-opens the trade screen with controls and ProximityPrompts disabled (GUIIntegration:172-175, 47-85). Re-invite right after cancel has no cooldown, and there is no decline/ignore option: harassment and grief vector.
- HIGH (verified): trade commit runs on the RAM fast path (_canFast/_runFast); the two profiles are flushed separately later (autosave 60 s, PlayerRemoving). A crash or failed save between flushes, or a Suspect resync of one side, half-applies the trade (one asset duplicated, another lost). No trade journal or audit record exists.
- MEDIUM (reproduced): expired trades are only cleared lazily by Snapshot/Cancel/Leave; TradeByUser stays set after Expires and keeps blocking invites, lab, shelter and selling.
- MEDIUM: every successful Trade step (Accept/Offer/Ready/Confirm) calls Runtime.RefreshAll() (Runtime.luau:452), i.e. Project for up to 60 players. It is spammable at about 1.5 req/s per client (server load / DoS).
- MEDIUM: repeated 'Ready' with the same version re-sets ConfirmAfter=now+8 (Engine:314-315), so a partner can delay final confirm forever.
- LOW-MEDIUM (reproduced): one-sided gifts (e.g. Cash only) are allowed with no limit or tax (alt funneling/RMT), and empty-vs-empty trades increment Stats.CompletedTrades (stat farming for future titles/boards).
- LOW: client trade selection state (Menus state TradeDogs/TradeItems/TradeCash) is never cleared or pruned. After a completed trade, given uids stay 'selected' invisibly: the next UPDATE OFFER fails with 'Dog not owned' and the 6-slot counter is consumed.
- LOW: trade review countdown uses c.Snapshot.Now (time of last snapshot) instead of c.Now(), so 'REVIEW Ns' only changes on the 5 s poll (EconomyScreens:327).
- LOW: finds list iterated with pairs (order changes each refresh); non-Tradeable and record-pending items shown as selectable; up to 250 dog + 1000 item buttons rebuilt every 5 s plus GetDescendants every 0.5 s (Menus Render/Update).
- LOW: 'Estimated' value ignores dog variant/mastery/ascension and uses the frozen item SellValue instead of the live ItemValuation.Price used by Milo.
- LOW: trade session view and invite identify the partner only by DisplayName (impersonation); @username is shown only in the details panel.
- LOW (verified): Favorite items and dogs on yard display can be traded (shelter forbids displayed dogs); the Favorite flag is carried to the recipient.
- LOW: no push notifications. The inviter is not told about acceptance, the partner is not told about cancel/leave; the fixed 240 s lifetime from invite is not shown.
- TITLES: non-Dex collection titles (Finds250, Discovery:<set>, Event3, Prestige2, Set<X>, SupporterTitle, FounderPlaque) display raw keys in COSMETICS (PlotShopScreen:74) and over kennel dogs (EconomyVisuals:33), because DexRewards.TitleName only knows Dex*. The equipped title is drawn over every kennel dog instead of the player.
- DEAD CODE: CommunityQATests.luau is never required; Rules.Action 'DexClaim' branch (Rules:528) is unreachable because Features/Dogdex handles DexClaim first (legacy Dex25/Dex75 keys exist only in old saves).
- TECH DEBT: two parallel trade UIs (PawpadController.renderTrade static TradePage and EconomyScreens.Screens.Trade); trade server logic embedded in Engine; no tests/ coverage for trading.

## Приложение: `events-nav` — списки


### Ключевые файлы

- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau` — 13 event rows + perks (DOG_RUSH: Walk 1.35, LineSpeed 1.5, LineLuck 1.2, Effects Zoomies/Trail, Reward MinCash 600/IncomeMinutes 1/Bones 2), PerkLines
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau` — Timings (600/60/240/15), interactions, FX budgets, caps
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventSchedule.luau` — Deterministic global schedule (S.At, S.Event, S.Period=915s)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventModifiers.luau` — Server active-event state; Resolve into Rules.Team; MutationRows
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventFX.luau` — Client FX orchestrator; contains the buggy DogCrowd (lines 139-155, 259-279)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventSpectacle.luau` — Sky set pieces (DOG_RUSH portal + Leader dog)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau` — Title banner, surge (ALPHA STAMPEDE), sustained beats (StampedeWake relative to player), tint surfaces
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventLighting.luau` — Client lighting moods, BLACKOUT light flicker (full district scan)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventAudio.luau` — Owner-written music-only audio; Audio.Cue is an empty stub
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventObjects.luau` — Reusable builders (Beam/Soft/Ring/Particles) and pickup models
- `/home/user/riooblox/src/ServerScriptService/WorldEventService.luau` — Scheduler tick, State attributes, journal WorldEventsSeen, pickups SpawnObject/Interact, Studio Force
- `/home/user/riooblox/src/ServerScriptService/WorldEventGameplay.luau` — Server perks (gravity, movement, tongue attrs), bones per minute, end reward G.Reward
- `/home/user/riooblox/src/ServerScriptService/WorldEventBootstrap.server.luau` — Starts WorldEventService
- `/home/user/riooblox/src/ServerScriptService/WorldEventTestServer.server.luau` — Studio-only StudioEventControl remote
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau` — Client state sync, notices, FX lifecycle, Signal handling
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau` — Effects: Zoomies, Trail, Flashlight, Tractor, Quakes, Glitch; server luck celebration
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldEventTestPanel.client.luau` — Studio F6 control panel
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EventsScreen.luau` — EVENTS page (daily/playtime, current, upcoming, Aurion)
- `/home/user/riooblox/src/ServerScriptService/DogLineSpawner.server.luau` — Tongue conveyor; reads EventLineScale/EventBlockScale
- `/home/user/riooblox/src/ServerScriptService/Economy/ServerLuck.luau` — Ranks(): applies LineLuck/SecretLine of active event
- `/home/user/riooblox/src/ReplicatedStorage/PlotCatalog.luau` — Event-gated plot skins (DogRush requires WorldEventsSeen.DOG_RUSH + GlobalDigContribution goal)
- `/home/user/riooblox/src/ReplicatedStorage/MapRouting.luau` — Location list, Anchor/Position/Bounds; build.py ModuleScript template (do not rename)
- `/home/user/riooblox/src/ServerScriptService/NavigationSync.server.luau` — Syncs NavigationAnchors mirrors to Target CFrames every second
- `/home/user/riooblox/src/ServerScriptService/Economy/DistrictTravel.luau` — Server teleport to Lab/Museum (unused by UI)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau` — District map overlay, waypoint billboard, NavigateDistrict handler (contains locations[2] bug)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DistrictWorldMotion.client.luau` — Local prop motion by Motion attribute
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldSignController.client.luau` — Distance fade of ManagedWorldSign; build.py LocalScript template
- `/home/user/riooblox/src/ReplicatedStorage/WorldSignConfig/LocationLabels.luau` — Building labels using Sidebar button icons (coupled to F2)
- `/home/user/riooblox/src/ServerScriptService/DistrictDoors.server.luau` — Server auto doors (lab door)
- `/home/user/riooblox/src/ServerScriptService/DistrictSafety.server.luau` — Fall recovery
- `/home/user/riooblox/src/ServerScriptService/MovementModifiers.luau` — Walk/jump multiplier stack (Event x Express)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/ExpressMotion.client.luau` — Precedent for flowing ground arrows (DOG EXPRESS)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/GUIIntegration.luau` — N.Navigate -> NavigateDistrict; N.Travel (dead); Feedback navigate bug
- `/home/user/riooblox/src/ServerScriptService/Economy/FeatureRegistry.luau` — Plug-in point for new saved feature data (EventPass)

### Сохраняемые данные

- p.WorldEventsSeen = {[EventId]={FirstSeen=unix, Rarity}} - written by WorldEventService.journal on each ACTIVE start; read by PlotCatalog.Earned/Requirement for event plot skins
- p.WorldEventClaims = {Generation='<cycle>:<id>', Count, Objects={[objectId]=true}} - pickups collected in the current event generation (cap Interactions.PerEvent=10)
- p.NextWorldEventCollect = unix seconds - pickup cooldown (12 s)
- p.WorldEventRewards = {[generation]=unix} - end-of-event reward ledger (max 8 entries, then reset to {})
- p.TotalExcavations - read (not written) by WorldEventGameplay for end-reward eligibility (>=4 digs during event); incremented by Rules.Dig on every kennel dig
- p.Cash / p.Bones / luck tier (LuckRules.Add) / minted items with Origin='WorldEvent:<EventId>' - reward sinks
- p.Lifetime.GlobalDigContribution - read by PlotCatalog for event skin Goal
- p.Event {Week,Contribution,Claims} and p.EventTokens - separate legacy weekly community event (Engine EventClaim/EventRoll), not world events
- Navigation: no saved data; player attributes YardId, YardSpawnPosition (server YardService/MapAmbience), ReducedMotion, WorldEventFX (client-only), OnDogExpress/ExpressDirection (server)
- Profile document key 'p:<UserId>' via Economy.Transactions (Runtime.Tx:Run with idempotency keys eventcollect:<uid>:<objectId>)

### Сеть

- ReplicatedStorage.WorldEvents.State (Folder attributes, S->C replication): State, EventId, Cycle, StartTimestamp, EndTimestamp, NextEventTimestamp, ActiveEndTimestamp, Generation, Revision
- ReplicatedStorage.WorldEvents.Changed (RemoteEvent S->C, FireAllClients(fullState) on every change)
- ReplicatedStorage.WorldEvents.Signal (RemoteEvent S->C): {Kind='Signature',EventId,Duration} all; {Kind='Reward',EventId,Reward={Cash,Bones,Item?},Position,ObjectId}; {Kind='Hint',Message,ObjectId}; {Kind='Discovered',EventId}; {Kind='EventReward',EventId,Reward={Coins,Bones,LuckTier,LuckSeconds}}
- ReplicatedStorage.WorldEvents.GetState (RemoteFunction C->S, returns S.Current, Runtime.Allow(player,1))
- ReplicatedStorage.WorldEvents.StudioEventControl (RemoteFunction C->S, Studio only: start/stop/resume/signature)
- ServerScriptService.WorldEventService.WorldEventDebug (BindableFunction, Studio only)
- ProximityPrompt 'WorldEventPickupPrompt' on server pickups in Workspace.WorldEventFX -> WorldEventService.Interact
- ReplicatedStorage.RewardPresentation (RemoteEvent S->C): {Cue}, {Message}, {PromptFeedback}, {Announcement,Tier}
- ReplicatedStorage.DogEconomyRequest action 'DistrictTravel' {Destination='Lab'|'Museum'} (RemoteFunction C->S; unused by UI)
- StarterGui.ScreenGui.NavigateDistrict (BindableEvent, client): Fire(displayName) from GUIIntegration.N.Navigate, Menus c.Go, OnboardingGuide, LabScreen, RewardScreens, UITheme, PawpadController
- StarterGui.ScreenGui.ToggleDistrictMap (BindableEvent, client) from PawpadRuntime openMap
- Attributes 03_DogLine.EventLineScale / EventBlockScale (server -> DogLineSpawner)
- workspace.Gravity set by server (replicated)

### Объекты мира

- Workspace.DOGROTS_District.NavigationAnchors (Model, ModelStreamingMode=Persistent): 13 Parts DogLine, PlayerYards, WelcomeHub, DogDex, MutationLab, GlobalDigSite, RewardMachine, Shops, DogPark, PortalRuins, TheVoid, Shelter, Feedback, each with ObjectValue Target -> <Area>.EntranceAnchor (Feedback -> 32_WelcomeHub.DeveloperMailbox.MailboxBody)
- Workspace.DOGROTS_District.01_IslandAndStreets.PrimaryPaths (MainBoulevard x[-18,18] z[146,754]; DistrictConnection z=200/275/335/395/465/535/730; yard promenades x=+-30,+-156; YardCrossing z=-156/-78/0/78/156) - basis for a nav graph
- Workspace.DOGROTS_District.36_DistrictRefresh.DirectPaths and 37_AttractionRefresh.ConnectedPaths - approach paths to every attraction
- Workspace.DOGROTS_District.33_DogExpress: ExpressLane parts Outbound (-26,0.3,289) / Return (26,0.3,289) size 6x902, SpeedMultiplier 2.6; 148 'Arrow' parts animated by ExpressMotion - candidate stampede lanes
- Workspace.DOGROTS_District.03_DogLine (DogSpawn (0,2,-168), DogEnd (0,2,136), BeltTread, ActiveDogs, EntranceAnchor) - EventLineScale/EventBlockScale attributes
- Workspace.DOGROTS_District.04_PlayerYards.Yard_01..08 (YardSpawn at x=+-28, z=-117/-39/39/117; attributes OwnerUserId, YardId)
- Workspace.DOGROTS_District.*.WorldEventSpawnPoints (18 points: 04_PlayerYards 3, 09_DogPark 2, 08_GlobalDigSite 5, 31_BackDistrictExpansion 5, 32_WelcomeHub 3, 03_DogLine 0)
- Workspace.DOGROTS_District.08_GlobalDigSite.SiteOrigin (event stage when GlobalDigConfig.Enabled; currently false -> WelcomeHub stage)
- 246 BaseParts with attribute EventTintSurface; 294 Lights in district (79 under WarmLens/PortalEnergy are navigation-exempt in BLACKOUT)
- Workspace.DistrictSpawn (SpawnLocation (0,0.4,377))
- Workspace.WorldEventFX (Folder for server pickups)
- ReplicatedStorage.MenuModels (101 skinned dog models used by DogCrowd/Spectacle actors)
- SoundService.DOGROTS_AUDIO.Music / WorldEvents SoundGroups
- Workspace.DOGROTS_District.05_MutationLab.GlassFacade.LaboratoryAutomaticDoor (only AutomaticDoor)
- Location label targets: 11_Shops.COSMETICS, 06_DogDexMuseum, 05_MutationLab, 32_WelcomeHub.DogShelter (roofs Architecture/SteppedNavyRoof/TechnicalRoof; existing LocationLabelAnchor parts; 6 ManagedWorldSign tags)
- StarterGui.ScreenGui.MainWindow.Sidebar.{ShopButton,DogDexButton,LabButton,DogsButton}.{CandyIcon,CandyCaption} (required by LocationLabels.Apply)
- Client-created: Workspace.WorldEventClientFX, DOGROTS_EpicEvent, DOGROTS_Cataclysm, DOGROTS_EventGameplayFX, LocalDistrictWaypoint; PlayerGui DOGROTS_EventGameplay (DisplayOrder 90), DOGROTS_EventCinema (95)
- Workspace streaming: StreamingEnabled=true, MinRadius 64, TargetRadius 1024; Persistent models: NavigationAnchors, 13_TheVoid, 37_AttractionRefresh.RewardMachineRig, 03_DogLine...BeltEndPortal

### Точки расширения

- WorldEventDefinitions rows + perks table: add Effects flags (client reads in WorldEventGameplayFX.start) and an Activity key for new per-event gameplay
- WorldEventGameplay.Apply/Tick/Reward: per-event server hooks called on every state change and at 1 Hz
- WorldEventService.SpawnObject/Interact + WorldEventObjects.Build kinds: server-authoritative pickups with RAM claim + Tx idempotency pattern
- WorldEvents.Signal Kind dispatch on client (WorldEventController) for new messages (e.g. RushCatch, RushSummary)
- WorldEvents.State attributes as single replicated source of truth (add RushSeed etc.)
- Economy/FeatureRegistry: new Features/<Name>.luau module with Normalize/Validate/Action/Snapshot for saved progression (EventPass) and DogEconomyRequest actions
- BoostPricing.Coins/Boost: income-relative reward sizing (economy-safe)
- MapRouting.Locations/Anchor/Position + NavigationAnchors (Persistent) + NavigationSync for moving targets
- StarterGui.ScreenGui.NavigateDistrict BindableEvent / GUIIntegration.N.Navigate as the single 'go to' entry for all UI
- WorldEventObjects V.Beam/V.Soft/V.Ring/V.Particles reusable for path final pointer
- ExpressMotion arrow animation pattern and DOG EXPRESS lanes
- Player attributes WorldEventFX/LowFX/ReducedMotion as quality switches
- CollectionService tag ManagedWorldSign + WorldSignController for world labels (and a future HideUI multiplier)
- WorldEventModifiers.MutationRows for event-boosted mutation odds (new lab reroll)
- ItemRules depth boost (def.Depth==e.EventDepth) for mapping events to new mine depths

### Улучшить поверх

- Replace DogCrowd with a lane-based Rush stampede behind an Effects.Rush flag (keep Definitions/Schedule/Service untouched)
- Implement WorldEventAudio.Cue via WorldSound/RewardAudio without touching the owner's music logic
- Add Rush Pass progression as Economy/Features/EventPass.luau (no Rules.luau edits)
- Add 'Show path' as a new client module over MapRouting + data nav graph; NavigateDistrict stays the entry point
- Fix DistrictGuide bugs: locations[2] yard overwrite, 'Feedback' name mismatch, Heartbeat overwriting YardSpawnPosition, Bounds including TheVoid, dead DistrictDirectoryPrompt listener
- Cache WorldEventSpawnPoints (server), BLACKOUT lights and tint surfaces (client) instead of full GetDescendants scans
- Scale pickup Cash/Bones with BoostPricing.Coins so they matter after the F11 rebalance
- Make end-reward eligibility count real activity (mining hits, tongue purchases, catches) rather than AFK kennel digs, keeping the amount
- Guard FX re-Begin during ENDING when the FX quality setting changes
- Add Lune tests: schedule determinism/frequency, reward eligibility, nav graph connectivity

### Аккуратный рефакторинг

- WorldEventFX / WorldEventSpectacle / WorldEventCataclysm: monolithic per-event if-chains and 5 independent Heartbeat/RenderStep loops; move to per-event activity modules with one scheduler and an object budget
- Unify 4 camera-shake RenderStep bindings into one CameraShake service (respect ReducedMotion once)
- DistrictGuide: string display-name matching spread across ~10 call sites -> key-based destinations; legacy non-Kit UI; schematic without real map
- LocationLabels hard dependency on Sidebar buttons (CandyIcon/CandyCaption) - decouple before F2
- Duplicate state channels (State attributes + Changed + GetState) - keep attributes as the single source when adding Rush fields
- All ground() raycasts cast from +8..+35 studs downward and sky set pieces assume surface play - need an indoor/underground mode for F5 mine levels and the F12 lab interior
- Reserved names: MapRouting and WorldSignController are build.py templates; MapRouting public API used by WorldEventFX, Spectacle, Economy/World, DistrictTravel

### Найденные баги

- WorldEventFX.luau:139-155,259-279 (DogCrowd): dogs positioned every frame at near(live HRP)+heading offset, heading frozen at event start camera look, per-dog per-frame raycast from 10 studs above lands them on roofs/walls; pack translates with the player and each client has its own pack - the 'buggy dogs attached to the player'
- WorldEventCataclysm.luau:393-398: DOG_RUSH beat 'StampedeWake' spawned relative to the player and flies 175 studs through buildings
- WorldEventAudio.luau: Audio.Cue() is an empty stub, so every event SFX cue (interaction, reward, rare, variation_N, special) is silent; WorldEventConfig.Audio is unused
- WorldEventGameplay.luau:216-217: 'actively dug' requirement is TotalExcavations delta >=4, which kennel dogs satisfy automatically via Engine:TickAll->Rules.Dig, so AFK players qualify (EventsScreen text says 'Stay active and DIG')
- DistrictGuide.client.luau:121-124: updateYard writes locations[2] / MapDot_2, which is 'Developer mailbox' (MapRouting.Locations order: Shelter, Feedback, DogLine, PlayerYards...), so the mailbox dot/marker point at the player's yard and the yard dot stays at the generic entrance
- GUIIntegration.luau:117 OpenScreen('Feedback') -> Navigate('Feedback'): DistrictGuide matches loc.name ('Developer mailbox'), not the key, so it just opens the map instead of placing the marker
- DistrictGuide.client.luau:111-113: every 0.2 s selected.pos is replaced with Routing.Position('PlayerYards',player), which falls back to the generic (0,2,110) anchor when the own yard is not streamed in, overriding YardSpawnPosition
- MapRouting.Bounds includes sealed TheVoid at (700,117,-633), so district map dots are squeezed into ~20% of the schematic width
- DistrictGuide listens for ProximityPrompt 'DistrictDirectoryPrompt' that does not exist in the place (dead path); GUIIntegration.N.Travel / DistrictTravel server action is never called
- WorldEventController.client.luau:157: changing WorldEventFX quality during ENDING calls FX.Begin, which resets 'ending' and replays the banner, then visuals pop off at cleanup
- WorldEventService.luau:12-25 points(): full DOGROTS_District:GetDescendants() (~37.5k) on every pickup spawn (every 18 s during events with SpecialObjects) on the server
- WorldEventLighting.luau:101-104: full district descendant scan for Lights at every event start on the client; lights streamed in later are not affected by BLACKOUT
- Four camera shake RenderStep bindings (DOGROTS_EventGameplayShake Camera+3, DOGROTS_EventCamera +1, DOGROTS_EpicCamera +2, DOGROTS_CataclysmCamera +3) stack independently
- WorldEventConfig Interactions Cash=40/Bones=2 per pickup are flat and not income-scaled (negligible late game)
- LocationLabelsBootstrap comment says six labels; LocationLabels.Locations has four (place has 6 ManagedWorldSign tags) - informational

## Приложение: `tooling-perf` — списки


### Ключевые файлы

- `/home/user/riooblox/tools/build.py` — Builder: applies src/*.luau onto place/DOGROTS_base.rbxl. Changes only Source; creates new scripts/Folders from fixed templates (TEMPLATES); writes build/build_report.json
- `/home/user/riooblox/tools/rbxl.py` — Fidelity-first binary rbxl patcher; untouched chunks byte-for-byte. Supported prop types: STRING/INT32/FLOAT32/ENUM/SHAREDSTRING/INT64/UNIQUEID/SECCAP/BRICKCOLOR/BOOL/FLOAT64/FACES/AXES/COLOR3/VECTOR2/VECTOR3; no CFrame/Ref/OptCFrame/PhysProps/Color3uint8/sequences, so it cannot clone Parts/Models. fresh_unique_id/fresh_guid use os.urandom (non-deterministic)
- `/home/user/riooblox/tools/verify.luau` — Lune/rbx-dom verification: src files present with identical Source, compile, new scripts have no tags/attributes, not Disabled; exports sourcemap for luau-lsp
- `/home/user/riooblox/tools/analyze_diff.py` — luau-lsp analyze diff base vs build (new diagnostics only, plus strict pass filtered by STRICT_KEEP); src scripts only, tests are not analyzed
- `/home/user/riooblox/tools/check.sh` — Full gate: build -> verify -> every tests/*.luau -> analyze (env PYTHON/LUNE/LUAU_LSP/LUAU_DEFS/WORK)
- `/home/user/riooblox/tools/balance_sim.py` — Active-mining balance simulator; parses MiningConfig 'local M={...}' by regex; prints coins/min per pickaxe x layer and weights; payback promised in docstring but not printed
- `/home/user/riooblox/tests/lib/economy_env.luau` — Test loader: proxy tree over src layout; L.Require(dotted), L.Overrides[slash path], L.Workspace, L.Time, L.Stubs, L.Random, L.Reset; task.* are no-ops
- `/home/user/riooblox/tests/payments_lib/loader.luau` — Test loader with fake instances (attrs/children), real @lune/task, L.Services, L.Overrides, L.Now, L.Fired, L.Instance, L.Signal
- `/home/user/riooblox/tests/animations.luau` — Pattern for place-based tests: deserializes build (or base) place and runs src modules over real place instances
- `/home/user/riooblox/tests/kennel.luau` — Pattern: hand-made fake instances (attributes only) around a real server module
- `/home/user/riooblox/src/ServerStorage/MapRefreshInstaller.luau` — Studio-Edit-only installer (assertEdit) -> 36_DistrictRefresh; reversible via DistrictRefresh_* attributes; never called at runtime
- `/home/user/riooblox/src/ServerStorage/AttractionRefreshInstaller.luau` — Studio-Edit-only installer -> 37_AttractionRefresh (RewardMachineRig Persistent); reversible via AttractionRefresh_*; not called at runtime
- `/home/user/riooblox/src/ServerStorage/ShelterInteriorInstaller.luau` — Studio-Edit-only installer -> DogShelter.InteriorFinish; ShelterOriginal_* attributes
- `/home/user/riooblox/src/ServerStorage/RewardMachineRethemeInstaller.luau` — Additive idempotent CapsuleHousing installer (no Edit assert); not called
- `/home/user/riooblox/src/ServerStorage/AttractionTextRepair.luau` — Edit-mode text repair table (AttractionOriginalText); not called
- `/home/user/riooblox/src/ServerScriptService/MiningWorld.server.luau` — Reference runtime world builder: idempotent build() by LayoutVersion=24, ModelStreamingMode PersistentPerPlayer + AddPersistentPlayer(owner), anchors from yard
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningModels.luau` — Shared procedural part helper (Models.Part/Ore/Pickaxe/Weld) used by server and client; base for a general World/Builder
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau` — Runtime plot decoration builder (Apply token cache, destroy/rebuild PlotDevelopment); writes PlotBase* attributes on yard parts
- `/home/user/riooblox/src/ServerScriptService/Economy/BestFinds.luau` — Auto-selected Find/Dog/Relic stand per yard, per-slot ExhibitToken diff; Select iterates all items each refresh
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotShowcase.luau` — Yard display dogs (DisplaySlots Slot1..3), token diff per slot
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldDetailQuality.client.luau` — Only shared light/particle budget: every 0.4 s keeps nearest 24 (8 low) lights and caps every district emitter to <=8/s, 50 total
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau` — RU auto-translator over PlayerGui and workspace; per-label PropertyChanged connection; unbounded cache; ~110 patterns + ~440 phrases per text change
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/SecretAura.client.luau` — RenderStepped auras for secret dogs; no distance culling; GetBoundingBox per frame for displays; unbudgeted lights; MAX_HIGHLIGHTS=6
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/VoidAtmosphere.client.luau` — 10 Hz Void presentation; PivotTo of 4 ring models (128 parts) within 1800 studs
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldAmbience.client.luau` — Background music; routes to missing SoundGroup 'Ambient' (nil)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau` — PreSimulation dog animation driver with view culling, distance LOD 1/3/8 frames, profiler labels (reference LOD pattern)
- `/home/user/riooblox/src/ReplicatedStorage/DogAnimationPlayer.luau` — Bone.Transform sampler, clip cache, PumpPreload one decode per frame
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DistrictWorldMotion.client.luau` — Attribute-driven local prop motion (Motion=Ring/Belt/Hoist/Float/Drone/Pulse), 30 Hz, 800-stud cutoff; DescendantAdded+task.defer per instance
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlotSkinMotion.client.luau` — PlotFloat/PlotMist yard motion at 30 Hz; conflicts with WDQ over emitter Enabled
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlaceTypography.client.luau` — Forces FredokaOne on every text in workspace/PlayerGui (KeepFont opt-out), connection per label
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/LocalScript.client.luau` — Debug leftover: prints locale, GetTranslatorForLocaleAsync without pcall, scans PlayerGui
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau` — Sets default WorldEventFX (Medium on touch-only, High otherwise) when nil
- `/home/user/riooblox/src/StarterGui/ScreenGui/PawpadRuntime.client.luau` — Settings: Motion -> ReducedMotion attribute, 'World Event FX' cycles High/Medium/Low (session only)
- `/home/user/riooblox/src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau` — Existing tier budgets FX={High={Particles=64,Debris=52,Dogs=14},Medium={28,24,8},Low={4,8,3}}
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau` — 1 s economy loop, autosave, watchdog; Project() rewrites ~40 attributes and every dog per refresh, bumps InventoryRevision
- `/home/user/riooblox/src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau` — Full Snapshot InvokeServer on every InventoryRevision (>=1.5 s) while open; padPrompts loop at 2 Hz even when closed
- `/home/user/riooblox/src/ServerScriptService/DogLineSpawner.server.luau` — Server Heartbeat conveyor mover; weldToRoot to replicate one CFrame per entity; Atomic streaming
- `/home/user/riooblox/src/ServerScriptService/DistrictSafety.server.luau` — Teleports characters below Y<-85 back to spawn (constraint for depth levels)
- `/home/user/riooblox/src/ServerScriptService/LightingController.server.luau` — Server day cycle stepping ClockTime every 1 s (30 min cycle)
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Preview.luau` — Viewport preview cache (PerFrame=2, MaxFree=48, stats) - reuse for item/showcase previews
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/Kit/Motion.luau` — Tween helper honoring GuiService.ReducedMotionEnabled / Motion.Override (not the ReducedMotion attribute)
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau` — Clones a DiscoveryModels item per find at LootSpawn (<=4 active, Highlight each, Debris 6-14 s); no pooling
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau` — Item model clone from ReplicatedStorage.DiscoveryModels; mutations turn every part Neon

### Сохраняемые данные

- This subsystem does not save any profile fields or DataStore keys.
- Player attribute WorldEventFX ('High'|'Medium'|'Low'): client-only, session-only. Default is set by WorldEventController (Medium on touch-only devices, High otherwise); cycled by the PAWPAD setting; read by WDQ, VoidAtmosphere, Lucky, Mining FX and others.
- Player attribute ReducedMotion (bool): client-only, session-only; toggled by PAWPAD 'Motion' (and the Studio WorldEventTestPanel).
- Player attribute LowFX: read by 12 client scripts but set by nobody (dead switch). The proposed Quality module would set it.
- Kit/Motion reduced motion = GuiService.ReducedMotionEnabled or Motion.Override; it ignores the ReducedMotion attribute.
- Place-level build metadata: build/build_report.json {modified[], created[]} (72 modified, 88 created); verify.luau reads it.
- Installer metadata baked into the place: 36_DistrictRefresh {CodexDistrictRefresh, Version=2026-09-30.4, Parts=825, Windows=164, WindowOpenings=112, Fonts=754, PathSegments=15, Lights=6}; 37_AttractionRefresh {CodexAttractionRefresh, Version=2026-10-02.DOGOMATIC.Free, Parts=1732, RewardMachineParts=811, RoofSegments=512, WindowSegments=314, RepairEdits=99, PathSegments=29}; DogShelter.InteriorFinish {CodexShelterInterior, Version=2026-09-30.1, CreatedParts=415, CreatedLights=9, Original*CFrame}.
- Reversible-original attributes in Workspace: DistrictRefresh_* (11,952), AttractionRefresh_* (17,024), ShelterOriginal_* (112), AttractionOriginalText (63), ArtOriginalColor/Material (19,296 each), PlotBaseTransparency/Color/Collide/Material (10,952 each). 114,351 attributes in total on 24,243 instances.
- Runtime builder versioning: MiningCorner LayoutVersion=24 attribute; PlotAppearance in-memory token level:skin; BestFinds slot ExhibitToken attribute.
- Proposed (new, optional): profile Settings.Quality ('Auto' default when missing) via an Economy/Features module Normalize; old saves are unaffected because the field is absent until it is set.

### Сеть

- The subsystem owns no remotes. The build cannot create RemoteEvents; every remote is created at runtime by server scripts (FindFirstChild(name) or Instance.new).
- DogEconomyRequest (RemoteFunction, client->server): 'Snapshot' is polled by InventoryController on every InventoryRevision change, at most every 1.5 s while the inventory is open, and returns the full profile. This is the main network perf risk; Net.Snapshot(maxAge) is the shared cached alternative.
- DogEconomyPush (RemoteEvent, server->client, created in Runtime.luau:585): coalesced notifications; Net.OnPush(kind) on the client.
- DiscoveryReveal (RemoteEvent, server->client): one per new find with LootSpawn; EconomyVisuals clones the item model and InventoryController refreshes.
- DiscoveryAnnouncement (RemoteEvent, server->all clients): rare finds, throttled to 15 s.
- WorldEvents/Changed, Signal (RemoteEvent) and GetState (RemoteFunction): world event state; clients read attributes on ReplicatedStorage.WorldEvents.State.
- Studio-only, created at runtime only in Studio: Mining/MiningStudioControl (RemoteFunction, F8 panel), WorldEvents/StudioEventControl (RemoteFunction, F6 panel), ReplicatedStorage/StudioSecretArrival (RemoteFunction, F7), ServerStorage/DOGROTS_HandleReceipt (BindableFunction), DogLineSpawner SpawnLuckyBlock/SpawnDog (BindableFunction, unpublished Studio only), WorldEventService/WorldEventDebug (BindableFunction).
- Bindables used for perf/lighting: ReplicatedStorage/LightingRefreshEvent (BindableEvent, server).

### Объекты мира

- Workspace.StreamingEnabled=true, StreamingMinRadius=64, StreamingTargetRadius=1024; StreamingIntegrityMode, StreamOutBehavior and ModelStreamingBehavior are all Default; FallenPartsDestroyHeight=-250. These can only be changed in Studio, or with a build.py extension (INT32/ENUM types are supported by rbxl.set_prop_values).
- Lighting: Technology=Future, GlobalShadows=true, ShadowSoftness .35; children DOGROTS_Atmosphere, DOGROTS_BloomEffect (on), DOGROTS_ColorCorrectionEffect (on), DOGROTS_DepthOfFieldEffect (off).
- Workspace.DOGROTS_District (Model, 37,581 instances). Persistent models: NavigationAnchors (13 anchor parts, e.g. MutationLab at (78,3,477), GlobalDigSite at (38,3,575)), 13_TheVoid and its DistantVoidAtmosphere, 37_AttractionRefresh.RewardMachineRig, 03_DogLine...BeltEndPortal.
- DOGROTS_District.04_PlayerYards: 8 yards (Yard_01..08), each 1,556 instances / 1,430 parts, Y 0..18, about 125x62 studs; anchors YardFoundation, StorageAnchor, DigSlot_1, YardSpawn; runtime children PlotDevelopment (PlotAppearance), MiningCorner (MiningWorld), DogStorage.DisplaySlots.
- DOGROTS_District.05_MutationLab: 983 parts (307 Neon, 54 Glass, 13 lights); InteractionAnchor, EntranceAnchor, InteriorZone, PresentationCamera, CentralChamber, Subject008Chamber, Stations.
- DOGROTS_District.08_GlobalDigSite: 1,170 parts, all hidden by MapRefreshInstaller (DistrictRefresh_* originals kept); MainDescent, LowerExcavation, AncientSanctuary, DigPositions; covered by 36_DistrictRefresh.GlobalEventComingSoon.PitCover (170x210 at 119,-0.31,639).
- DOGROTS_District.36_DistrictRefresh (Folder, 906 instances; 727 of its 825 parts hidden later) and 37_AttractionRefresh (Folder, 1,921 instances: ArchitectureRepairs, RewardMachineRig with CapsuleHousing, ConnectedPaths, GlobalEventComingSoon).
- DOGROTS_District.32_WelcomeHub.DogShelter.InteriorFinish (ShelterInteriorInstaller output).
- DOGROTS_District.01_IslandAndStreets: Y -42..21 (island underside); DistrictSafety recovers players below Y -85.
- DOGROTS_District.13_TheVoid.RiftEffects: OuterRiftRing/InnerRiftRing/InnerVortex/FarVortex (128 parts) moved by VoidAtmosphere at 10 Hz.
- ReplicatedStorage.MenuModels (5,294 instances, duplicate of ServerStorage.DogTemplates), ReplicatedStorage.DiscoveryModels (108 item models, 3,225 parts, max 105 per model), ReplicatedStorage.DogAnimationClips (1,559 ModuleScripts).
- SoundService.DOGROTS_AUDIO: only Music and WorldEvents SoundGroups; code references missing Ambient/UI/SFX groups.
- StarterGui.ScreenGui (ResetOnSpawn=false, 3,106 instances, 4 ViewportFrames).
- Workspace.WorldEventFX folder; runtime client folders DOGROTS_SecretAuras, DOGROTS_LuckyFX; server folder DOGROTS_SecretReveals.
- Build templates (must exist exactly once): ReplicatedStorage/MapRouting (ModuleScript), StarterPlayer/StarterPlayerScripts/WorldSignController (LocalScript), ServerScriptService/LightingController (Script), ReplicatedStorage/DogEconomy (Folder).
- StarterPlayerScripts.DOGROTS_FindEnglish_TEST: the only script not in src; Disabled.

### Точки расширения

- tests/*.luau is auto-discovered by check.sh: drop a new file there (subfolders lib/ and payments_lib/ are not run as tests).
- tests/lib/economy_env.luau: L.Require('A.B.C'), L.Overrides['A/B/C']=stub, L.Workspace (set before the first require), L.Time, L.Stubs[service], L.Reset().
- tests/payments_lib/loader.luau: L.Services[name], L.Overrides[path], L.Now, L.Fired (FireClient log), L.Instance/L.Signal fakes, real task.
- Place-based tests: deserialize build/DOGROTS_MINING.rbxl (fallback place/DOGROTS_base.rbxl), as tests/animations.luau does; keep geometry math in pure modules because Lune lacks Position/GetPivot/PivotTo/GetBoundingBox.
- build.py TEMPLATES / CLEAR: the place to add a retire convention or deterministic ids. rbxl.Place.set_prop_values can patch INT32/ENUM properties (e.g. Workspace streaming) if explicitly added.
- verify.luau: add assertions (e.g. expected Workspace streaming values, retired-script list).
- analyze_diff.py NOISE / STRICT_KEEP lists.
- balance_sim.py load_config()/simulate(): extend with payback and price scenarios (F11).
- Runtime world builders: MiningModels.Part helper; MiningWorld build() + LayoutVersion pattern; PlotAppearance.Apply token; BestFinds/PlotShowcase per-slot token.
- WorldDetailQuality opt-outs: 'MuseumLight' attribute on lights, 'LuckyVisual' attribute on an ancestor (proposed generic 'FXManaged').
- DistrictWorldMotion attributes: Motion=Ring|Belt|Hoist|Float|Drone|Pulse with Travel, Phase, AngularSpeed, Period, Anchor, CableName: free client-side prop animation for F8/F12 props inside the district.
- PlotSkinMotion attributes: PlotFloat (BasePart bobbing), PlotMist (ParticleEmitter distance toggle).
- AutoTranslate opt-out: NoTranslate attribute on a label or LayerCollector ancestor. PlaceTypography opt-out: KeepFont.
- CollectionService tag registry pattern (WorldSignController 'ManagedWorldSign', ArchitecturalLightController 'SecondaryArchitectureLight').
- WorldEventConfig.FX tier budgets (Particles/Debris/Dogs) and player attribute WorldEventFX: seed for a shared Quality module.
- Kit/Preview.Register(kind, builder, keyer) for new preview kinds (decor, titles, showcase items); Kit/Virtual for pooled list cells; Kit/Maid for cleanup.
- Economy.FeatureRegistry (Features/*.luau: Normalize/Validate/Action/Snapshot) for any new saved setting (e.g. Settings.Quality).
- debug.profilebegin/profileend labels (DogAnimations) for MicroProfiler measurement of each new system.
- Studio-only panels gated by RunService:IsStudio(); keys F6/F7/F8/K/M/P/B/E/F are already bound, so use a workspace attribute toggle for a PerfProbe.

### Улучшить поверх

- Add ReplicatedStorage/Perf/Quality.luau (tier from WorldEventFX, ReducedMotion, GuiService.ReducedMotionEnabled, SavedQualityLevel, touch-only, FPS watchdog) and make it set player LowFX and Kit/Motion.Override, so the 12 existing low-FX readers become consistent without edits.
- Add Perf/Scheduler (one shared Heartbeat, time-sliced, profiler labels), Perf/Lod (tag or Register API, 5 Hz, frustum + hysteresis), Perf/Pool (Acquire/Release/Stats) and a shared Maid; require new features to use them.
- Add a generic 'FXManaged' opt-out and Quality-driven budgets to WorldDetailQuality; mark PlotMist emitters FXManaged to end the PlotSkinMotion vs WDQ conflict.
- Add ReplicatedStorage/World/Builder.luau plus pure <Feature>Layout modules (spec tables), so geometry budgets and bounds are unit-tested in Lune.
- AutoTranslateUI: bounded LRU cache, cache the pattern/phrase pass result per source string, NoTranslate by default for Kit windows and new world billboards.
- Create the missing SoundGroups (DOGROTS_AUDIO/UI, SFX, Ambient) at runtime when absent, so UI sounds (F2) get volume buses.
- Neutralize debug leftovers by replacing their Source with a stub: StarterPlayerScripts/LocalScript and SpiderdogAnimation (the model does not exist).
- rbxl.py: derive UniqueId/ScriptGuid from sha256(path), so identical src gives a byte-identical build.
- build.py: a documented 'retired' convention (stub source), so removing a src file never resurrects the base script silently.
- balance_sim.py: print payback minutes per pickaxe and layer, and accept a --price-scale scenario for F11.
- New tests: tests/perf_lint.luau (new client files must not add raw RenderStepped/Heartbeat or workspace-wide DescendantAdded outside an allowlist), tests/world_layouts.luau (part budgets, bounds, determinism), tests/save_compat.luau (old-profile fixtures through Rules.Normalize/Validate and every Feature.Normalize, run twice for idempotency).
- InventoryController: run padPrompts only while the Lucky Blocks tab is shown or on yard attribute changes; use Net.Snapshot(maxAge) instead of a raw Snapshot per revision.
- SecretAura: distance cull (e.g. skip auras beyond 250 studs or off-screen), cache display boxes (they are static), reuse ColorSequence objects, register its lights with the shared light budget.
- Add a Studio-only PerfProbe (workspace attribute PerfProbe=true): instance counts per root, Stats memory/network, PartCount attributes of builder roots.
- Document in each new feature doc a 'Производительность' section with measured MicroProfiler time, instance counts and network KB/s against the budget table.

### Аккуратный рефакторинг

- Consolidate ~12 duplicated low/reduced-motion checks (WDQ, VoidAtmosphere, ExpressMotion, SecretAura, SecretArrivals/Kit, LuckyShow, MiningClient/FX, RewardMachineWorldFX, LabPresentation, MuseumPresentation, WorldEventSpectacle, WorldEventCataclysm) onto Perf/Quality. Touches many original scripts.
- Replace workspace/district-wide DescendantAdded scanners (AutoTranslate, PlaceTypography, LuckyBlockFX, WDQ, DistrictWorldMotion, PlotPrompts, PlotSkinMotion, SecretAura) with tag-based registries; needs careful streaming-in/out handling.
- Runtime.Project: per-dog dirty tracking (no JSONEncode(OwnerHistory) or attribute rewrite per refresh), and bump InventoryRevision only when inventory content changed. Touches economy and UI refresh contracts.
- Remove dead geometry: 2,878 installer-hidden parts and ~29k reversible-original attributes, plus 19k x2 ArtOriginal* attributes. The build cannot delete, so this is either a Studio edit (new base place import) or a whitelisted server-start cleanup. Must exclude 08_GlobalDigSite (possible F5 reuse) and PlotBase* (used by the stage system).
- Lazy replication of ReplicatedStorage.MenuModels (5,294 instances, duplicate of DogTemplates) and DiscoveryModels (3,334) to cut join-time memory, e.g. on-demand clones into a per-player folder.
- Streaming configuration (StreamOutBehavior Opportunistic, smaller StreamingTargetRadius, ModelStreamingBehavior Improved): changes behavior of the whole place; every WaitForChild into streamed parts must be re-verified.
- Zone-aware DistrictSafety (do not teleport players inside a registered mine volume) if depth levels must go below Y -85.
- Extend rbxl.py with CFrame/Ref/OptionalCFrame/PhysicalProperties/Color3uint8 codecs to write Parts at build time. XL effort and place-corruption risk; not recommended for this overhaul.
- Day cycle: move ClockTime interpolation to the client (server publishes only a time base) to avoid 1 s stepping and replication. Lighting-wide change.

### Найденные баги

- WorldDetailQuality caps the Rate of every ParticleEmitter under DOGROTS_District to <=8/s (2 on Low) with a 50 (8) total budget, and disables every light except the nearest 24 (8). New in-district VFX and lights are silently neutered (WorldDetailQuality.client.luau Heartbeat body).
- PlotSkinMotion (30 Hz, sets PlotMist emitter Enabled by distance <180) and WorldDetailQuality (2.5 Hz, sets Enabled=amount>0) fight over the same ParticleEmitter.Enabled; the last writer wins.
- Inconsistent mobile tiering: WDQ and VoidAtmosphere treat '(WorldEventFX==nil and TouchEnabled)' as low, but WorldEventController sets WorldEventFX='Medium' on touch devices when nil. Phones therefore usually get the High light/particle budget in WDQ (which treats only 'Low' as low), and the outcome depends on script start order.
- Player attribute LowFX is read by 12 scripts but never set anywhere.
- Kit/Motion ignores the PAWPAD ReducedMotion attribute (it only reads GuiService.ReducedMotionEnabled / Motion.Override), so the in-game Motion setting does not affect Kit windows.
- DOGROTS_AutoTranslateUI: cache[source]=source for every unique Latin string (dynamic numbers/timers) grows without bound on RU sessions; the pattern/phrase pass (~110 gsub + ~440 find) reruns on every text change because its result is not cached.
- WorldAmbience, RewardAudio, WorldSound and LabAudioConfig route sounds to SoundGroups DOGROTS_AUDIO.Ambient/UI/SFX, which do not exist in the place (only Music and WorldEvents), so SoundGroup becomes nil and there is no volume bus.
- StarterPlayerScripts/LocalScript is a debug leftover running in production: prints, calls LocalizationService:GetTranslatorForLocaleAsync('ru-ru') without pcall, rewrites 'DOGS' labels after 3 s.
- SpiderdogAnimation.client is dead code: DOG_097_SPIDERDOG_MODEL does not exist in the place.
- SecretAura updates every aura every other frame regardless of distance and calls GetBoundingBox per frame for display auras; its PointLights live outside the district and are outside any light budget.
- InventoryController runs padPrompts() every 0.5 s even when the inventory is closed, and refetches the full 'Snapshot' on every InventoryRevision bump (Runtime.Project bumps it on every refresh).
- tools/rbxl.py fresh_unique_id/fresh_guid use os.urandom: the build output differs on every run even with unchanged src (88 created instances).
- tools/build.py never removes instances: deleting the src file of an original script silently reverts it to the base place version instead of removing it.
- tools/balance_sim.py docstring promises pickaxe payback times but the output prints none.
- 37_AttractionRefresh root Version attribute is '2026-10-02.DOGOMATIC.Free' while AttractionRefreshInstaller.Version is '2026-10-01.6'. The place was edited after this installer by something not in the repo, so re-running Install/Uninstall could regress those edits (unconfirmed which).