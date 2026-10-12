# F2. Переработка UI и инвентаря — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `ui` (основной)

**Сейчас.** Three UI generations coexist. (A) Static MainWindow pages: Inventory, Yard, Trade on desktop, plus 6 dead pages. (B) Menus immediate-mode screens rebuilt every 5 s: Shop, Events, Settings, Supplies, Luck, Offline, Cosmetics, Storage, DOG-O-MATIC, Lucky odds/pad, Discoveries/Marketplace/Records, Trade session, compact Yard. (C) Kit windows: Dogs, Dogdex, Lab, UpgradeTree, Equipment. HUD: 8 candy tiles of 88x92 in two side columns built at runtime by UITheme.ApplyShell, with counters bottom-left and no badges. No UI sounds anywhere and no UI SoundGroup. Icons: 8 tile images plus 22 GameIcons, nothing for rarity/actions. Motion exists only in Kit; legacy windows pop instantly. The bag has about 17 simultaneous controls, cycle filters, class-coloured cards with no rarity or value, overloaded action buttons, and a SELL button that fails away from the collector. The same items appear in 4-6 different UIs.

**План.** Phase 0, foundations:
- Kit.Theme becomes the single token source (Space, IconSize, Elevation, unified Rarity/Variant/Mutation palettes); UITheme reads from it.
- New UISound module with a UI SoundGroup, built-in fallbacks (MiningAudio recipes) and AssetIds for uploads.
- Kit.Motion honours the ReducedMotion attribute.
- GameIcons extended with a sprite atlas (rarity, mutation, depth, sell, favourite, market, showcase, route, eye, title, filter, sort).
- Persisted p.Settings via a whitelisted SaveSettings action.

Phase 1, HUD:
- New HudController module that reuses LayoutHUD safe-area maths.
- Currency cluster top-left (Cash with income chip, Bones, level ring).
- Notification rail top-centre that merges WorldEventNotice, Offline notice, InventoryToast and Kit.Toast.
- 5 primary tiles left (Dogs, Bag, Shop, Index, Lab) and secondary tiles right (Trade, Events, Route, More); 64-72 px with badges; Settings and the Hide-UI eye icon top-right.
- Phone: at most 4 tiles per column, overflow in More. Gamepad selection groups and button prompts.

Phase 2, Inventory: Kit window Key='Inventory' as specified in section 14 (tabs, chips, popup filters, SortSelect, CardGrid with rarity/value, detail panel with one contextual primary action, bulk-sell mode, lucky blocks, collection), fed by Net cache and attribute-driven refresh. The collector prompt opens it in sell mode, replacing ServiceMenus Seller.

Phase 3, migrate by traffic: Shop (CommerceShopScreen), Events, Settings, Trade (F6), Yard, Cosmetics/Decor (F8), Storage plus Showcase (F3), Kennels, Layers (F5), LuckyOdds/Pad, Discoveries/Marketplace/Records, DOG-O-MATIC. Each is a Kit window behind a GUIIntegration routing wrapper.

Phase 4, cleanup: delete dead static pages and PawpadController blocks, CollectorScreen, PawpadStatsController and LocalScript; make GUIIntegration side-effect free; narrow AutoTranslate to legacy roots and migrate strings to Kit.T and Localization modules.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- `src/StarterGui/ScreenGui/Modules/UITheme.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Theme.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Motion.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Base.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Window.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Feedback.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Controls.luau`
- `src/StarterGui/ScreenGui/Modules/Menus.luau`
- `src/StarterGui/ScreenGui/PawpadController.client.luau`
- `src/StarterGui/ScreenGui/PawpadRuntime.client.luau`
- `src/StarterGui/ScreenGui/HUD/HUDStatsController.client.luau`
- `src/StarterGui/ScreenGui/HUD/MoneyWidget/MoneyController.client.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau`
- `src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `src/StarterGui/ScreenGui/Modules/BuffHUD.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterGui/ScreenGui/Modules/CommerceShopScreen.luau`
- `src/StarterGui/ScreenGui/Modules/EventsScreen.luau`
- `src/ReplicatedStorage/GameIcons.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_RU_ScreenPatch.client.luau`
- src/StarterPlayer/StarterPlayerScripts/LocalScript.client.luau (delete)
- src/ServerScriptService/Economy/YardCommerce.luau (favorite-safe BulkSell)
- src/ReplicatedStorage/ItemValuation.luau (export Rarity)
- `src/ReplicatedStorage/Localization/*.luau`
- `tests/uikit.luau`
- `docs/UIKIT.md`

**Новые модули.** 
- `src/ReplicatedStorage/UISound.luau`
- `src/StarterGui/ScreenGui/Modules/Hud/HudController.luau`
- `src/StarterGui/ScreenGui/Modules/Inventory/InventoryScreen.luau`
- src/StarterGui/ScreenGui/Modules/Inventory/InventoryModel.luau (pure filters/sort/rarity, unit-tested; can absorb InventoryView)
- `src/StarterGui/ScreenGui/Modules/SettingsScreen.luau`
- src/StarterGui/ScreenGui/Modules/ShopScreen.luau (Kit PAW MARKET)
- `src/StarterGui/ScreenGui/Modules/EventsWindow.luau`
- `tests/inventory.luau`

**Совместимость данных.** UI changes need no migration. New optional fields: p.Settings and p.InventorySeenAt. Defaults when absent: settings = current behaviour; all items count as seen. BulkSell favourite protection changes behaviour only for favourited items. ValidBulkArgs must accept an optional IncludeFavorites key; old clients that send only Uids still work.

**Производительность.** Removes idle 15 s Snapshot polling, 5 s full rebuilds, the YardPage 1237-part clone, the non-virtualised bag (up to ~19k instances), dead pages (~2257 instances, 544 texts) and the always-on padPrompts loop. Kit has no idle loop and is push/attribute driven. Sound pooling capped at about 6 concurrent sounds.

**Объём.** XL

**Риски.** Removing InventoryController without re-registering N.RegisterInventory stalls all navigation (ready()). UITheme and ServiceUI clone styles from YardPage. tests/uikit.luau enforces theme sync. AutoTranslate exact keys break on English text edits. Device-specific routes (Trade/Yard) could regress. Kit layers sit outside the main ScreenGui (DisplayOrder 60-95), so Mining/Community overlays at 70 may now sit above Kit windows. A long migration with mixed UIs. Phone performance of many ViewportFrames: keep Preview.PerFrame=2.


## Аудитор `data-network`

**Сейчас.** Инвентарь (InventoryController) скачивает полный Snapshot.Profile (100 КБ–1,2 МБ) на каждое изменение InventoryRevision, а Runtime.Project увеличивает его на каждом тике. Menus опрашивает Snapshot раз в 15 с вхолостую. Около 6 независимых опросчиков. Каждое действие возвращает полный StateSnapshot (только BulkSell отвечает StatePatch). Favorite на сервере не защищён, ItemLock отключён, I.Normalize стирает Locked. Есть клиентский кэш Modules/Net (Snapshot(maxAge), Changed, OnPush).

**План.** 1) Действие только на чтение 'InventoryView' {Kind='Items'|'Dogs'|'Blocks', Page?, Sort?, Filter?} (стоимость 1) отдаёт облегчённые строки {Uid,ItemId,Mutation,TierIndex,WeightKg,SellValue,Favorite,Showcased,Depth} и Revision. 2) Сигнатура инвентаря в Project (набор uid находок и собак, их State/Variant/Favorite, количество блоков, Equipment.Rev); InventoryRevision растёт только при её изменении; Snapshot и InventoryView принимают Known=rev и отвечают NotModified. 3) Push 'InventoryPatch' {Added=[rows],Removed=[uids]} после I.Mint (по месту DiscoveryReveal) и после продаж. 4) Защита на сервере: BulkSell и Market Create пропускают или отклоняют Favorite и витринные находки без IncludeProtected; новое действие 'ItemProtect' {Uids≤30, Enabled} работает через Favorite (не возвращать Locked: его стирает I.Normalize). 5) Расширить Modules/Net до единого клиентского store (кэш по Revision, применение патчей, подписки) и перевести на него новый инвентарь. 6) Убрать Dex из Snapshot только после того, как EconomyScreens/DexEntryScreen перейдут на локальные определения.

**Файлы.** 
- src/ServerScriptService/Economy/Runtime.luau (Project: сигнатура/ревизия, Snapshot: Known/NotModified, Request: InventoryView, стоимость)
- src/ServerScriptService/Economy/YardCommerce.luau (защита в BulkSell)
- src/ServerScriptService/Economy/Market.luau (защита в Create)
- src/ServerScriptService/Economy/ItemRules.luau (действие ItemProtect)
- `src/StarterGui/ScreenGui/Modules/Net.luau`
- src/StarterGui/ScreenGui/Modules/Menus.luau (пустой опрос)
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau`

**Новые модули.** 
- src/ServerScriptService/Economy/Features/Inventory.luau (InventoryView/ItemProtect, Snapshot-сводка)
- src/StarterGui/ScreenGui/Modules/Store.luau (или расширение Net)

**Совместимость данных.** Новых сохранённых полей нет (Favorite уже сохраняется). Showcased берётся из p.Showcase (F3).

**Производительность.** Трафик открытого инвентаря падает с ~70–800 КБ/с до единиц КБ. CPU сервера: исчезают копия Snapshot и IncomeModel на каждый опрос.

**Объём.** L

**Риски.** Около 10 потребителей Snapshot.Profile (старые контроллеры). Форму Snapshot можно только дополнять, пока все не переведены. Предсказание BulkSell на клиенте должно совпадать с серверным пропуском защищённых. Риск устаревших видов при потере push (нужен запасной опрос раз в 30–60 с).


## Аудитор `economy`

**Сейчас.** Economy numbers reach the UI through four formatters (IncomeText.Compact, MiningText.Short, PriceFormat.Number/Coins, U.Fmt). The inventory/discovery screens show ItemValuation.Price (live) in some places and stored SellValue in others (RecordStats). Every action returns a full StateSnapshot.

**План.** Expose one shared NumberFormat (based on IncomeText.Compact, which supports K/M/B/T/Qa) and use it everywhere. In the inventory show the live ItemValuation.Price, the rarity from the exported ItemValuation rarity, and BulkSell totals from SellQuote. Move heavy inventory data to StatePatch deltas to keep the new UI responsive.

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/IncomeText.luau`
- `src/ReplicatedStorage/PriceFormat.luau`
- `src/ReplicatedStorage/Mining/MiningText.luau`
- src/ServerScriptService/Economy/Runtime.luau (Snapshot/patches)

**Новые модули.** 
- ReplicatedStorage/NumberFormat.luau (optional)

**Совместимость данных.** None.

**Производительность.** Delta patches reduce network load: Snapshot today deep-copies up to 1000 items per action.

**Объём.** S (economy contract)

**Риски.** Formatting changes break string-based auto-translation keys (DOGROTS_AutoTranslateUI) if the English templates change.


## Аудитор `digging-depth`

**Сейчас.** Выбор слоя сделан дважды: ServiceMenusController mode 'Layers' (карточки, баг def.Prestige) и EconomyScreens Page 'Layers' (устаревший текст Prestige). Будка открывает ServiceMenus 'Kennels' через DogKennelOpen. Тексты переводит DOGROTS_AutoTranslateUI.

**План.** Один экран «ГЛУБИНА» (новый модуль): 5 крупных карточек.
• Иконка и цвет из Config.Layers[i].Color; глубина-ярлык.
• Чипы требований: Lv, Cash, Prestige из единого поля Config.Layers[i].Prestige.
• Статус: КОПАЮТ ЗДЕСЬ / СПУСТИТЬСЯ / ОТКРЫТЬ / ЗАКРЫТО.
• Превью: 3–4 иконки топ-находок из DepthDefinitions (редкие <1% подсвечены) и строка дохода из IncomeModel по слою.
• Мини-визуал шахты: кольца глубины, как тотем F5.

Кнопка вызывает существующее DogEconomyRequest 'Layer'. Панель будки: собака, слот, глубина, кнопка peek. Убрать дубли из EconomyScreens (оставить ссылку). Звуки и анимации — через общий UIKit.

**Файлы.** 
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau`

**Новые модули.** 
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/DepthScreen.luau`

**Совместимость данных.** Только UI; данные те же (CurrentLayer/UnlockedLayers).

**Производительность.** Превью находок — через пул вьюпортов, не больше 4 одновременно.

**Объём.** M

**Риски.** Две точки входа (кнопка двора DiggingLayers, страница помощи) должны вести в один экран. Ссылки обучения (OnboardingGuide шаг 10 «DOG LINE + DEPTHS»).


## Аудитор `item-models`

**Сейчас.** Инвентарь находок живёт в трёх разных UI: MainWindow InventoryController (свой кэш viewport, превью только видимых), Menus/DiscoveryScreens и CollectorScreen (immediate-mode, ClearAllChildren каждые 5 с, превью на каждую карточку), ServiceMenusController (продавец). Kit.CardGrid + Kit.Preview + ItemCard (полоса редкости, тег мутации) уже есть, но для находок используются только в KitDemo.

**План.** Сторона моделей: все сетки находок переводятся на Kit.CardGrid; Preview={Kind='Item',ItemId,Mutation,Lod='Card'} строит фабрика (L1 ≤10–20 частей) с единой камерой по Bounds. Rarity в карточке берётся из ItemValuation.Rarity. Детальная панель — Hero L0 с вращением (по образцу EquipmentVisuals.Turn). Для коллекции — силуэт (ImageColor3 чёрный). Перестройку по опросу Menus для страниц находок убрать (build-once + SetItems). Дополнительно: реестр PNG-иконок ItemIcons по образцу GameIcons (если владелец загрузит изображения; на телефоне они дешевле), иначе viewport.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/DiscoveryScreens.luau`
- `src/StarterGui/ScreenGui/Modules/CollectorScreen.luau`
- `src/StarterGui/ScreenGui/Modules/Menus.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Preview.luau`
- `src/StarterGui/ScreenGui/ServiceMenusController.client.luau`

**Новые модули.** 
- src/ReplicatedStorage/ItemIcons.luau (опционально, реестр загруженных иконок)

**Совместимость данных.** Данные не меняются; Favorite и фильтры как раньше.

**Производительность.** Вместо ViewportFrame на каждую находку каждые 5 с — только видимые карточки (≤24 × ≤20 частей) плюс полка 48, построенные один раз.

**Объём.** L

**Риски.** Три параллельных инвентаря — нужно решить, какой остаётся, и не сломать продажу и выставление на рынок. Кэш Kit.Preview (MaxFree 48) при больших коллекциях. Локализация (AutoTranslate).


## Аудитор `plots`

**Сейчас.** Plot screens are legacy: PlotShopScreen (Menus/U, rebuilt every 5 s with a whole-yard 3D clone), StorageScreen (DOG STORAGE displays, button-heavy), the MY YARD page (YardPageController clones every visible yard part), and the ServiceMenus 'ASSIGN DOG' kennel picker (ServiceUI clones YardPage styles).

**План.** Port to Kit windows: a 'MY PLOT' window (themes, decor, stage progress), a 'SHOWCASE' editor, a 'DOG DISPLAYS' window replacing StorageScreen, and a kennel picker as a Kit.CardGrid of dogs with one big ASSIGN button. Previews are cached by AppearanceRevision/skin token and use a lightweight builder (ground plate + generated decor, no whole-yard clone). Use icons and rarity frames instead of text blocks, plus hover/press sounds.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`
- `src/StarterGui/ScreenGui/Modules/StorageScreen.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau`
- `src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `src/StarterGui/ScreenGui/ServiceMenus/ServiceUI.luau`
- src/StarterGui/ScreenGui/Modules/UpgradeTreeScreen.luau (EstateView preview)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/PlotWindow.luau`

**Совместимость данных.** None (UI only; same actions).

**Производительность.** Removes the 5 s whole-yard clone and the 20 s yard snapshot clone: a big client win on mobile.

**Объём.** M

**Риски.** Other scripts clone YardPage styles (ServiceUI.Build reads YardPage objects) and DogsScreen/OnboardingGuide reference them: keep or replace those objects carefully.


## Аудитор `lab`

**Сейчас.** LabScreen is a 1869-line, 3-step kit window with 5 action cards, recipe book, manual picker, DNA bank and many texts - the 'too many buttons' problem in concentrated form.

**План.** As part of F12, replace the internals of LabScreen with a single console screen built on the new F2 kit style: icon-first dog grid (rarity frame, variant badge, lock icon + one-tap fix), large 3D preview, 6-segment odds bar, coin price pill, one giant MUTATE button (hold for valuable), result card with big AGAIN; hover/press tweens and LabAudioConfig Select/Step/Confirm/Deny cues; no DNA/recipe/catalyst UI. Keep LabScreen.Open/Close/Build/ShowResult/SetView. Trim Localization/Lab to the new strings (keep server-reply entries).

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/LabScreen.luau`
- `src/ReplicatedStorage/Localization/Lab.luau`
- `tests/lab.luau`

**Совместимость данных.** None.

**Производительность.** Fewer instances than today (no 101 hidden name probes needed if search is simplified; virtualized grid kept).

**Объём.** M

**Риски.** tests/lab.luau checks Russian coverage of every LabScreen string; the emulation harness hooks ShowResult/SetView; phone portrait/landscape layouts must be re-verified.


## Аудитор `trade-titles`

**Сейчас.** Trade UI is a Menus page rebuilt every 5 s with full-width text buttons for every dog/find (EconomyScreens:255-363) plus a static TradePage; titles are a plain button list inside COSMETICS (PlotShopScreen:67-77).

**План.** Build TradeScreen and TitlesScreen on the Kit (docs/UIKIT.md rules: build once/update in place, VirtualGrid for >30 entries, Kit.Preview, Hold-to-confirm, Countdown, Toasts, Reduced Motion). Icons and visual states instead of long text: rarity glow, value bar, state button with countdown ring, disabled-with-reason cards. Hover/press sounds through the shared UI sound helper chosen by the UI overhaul. Phone layout as tabs. Add the 'TradeInvite' actionable toast as a reusable Kit component (Kit.Feedback has only passive toasts today).

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/Kit/Feedback.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/TradeScreen.luau`
- `src/StarterGui/ScreenGui/Modules/TitlesScreen.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/ActionToast.luau`

**Совместимость данных.** Client only; no saved data.

**Производительность.** Removes the 5 s ClearAllChildren rebuild and the 0.5 s GetDescendants walk for the trade page; virtualized grids bound instance counts.

**Объём.** M

**Риски.** Two navigation systems (Menus vs Kit) during the transition; OpenMenu-dependent code (RewardScreens, LuckyReel...) must keep working; AutoTranslate coverage.


## Аудитор `events-nav`

**Сейчас.** EventsScreen is text-heavy: Daily+Playtime, current event, 'why wait' cards, 5 upcoming, Aurion block, mostly U.Text. WorldEventController uses a 640x106 notice card that hides whenever a menu is open. The Cataclysm banner is a GothamBlack TextLabel. DistrictGuide is a legacy 700x490 non-Kit panel with a dot schematic. LocationLabels depend on Sidebar CandyIcon/CandyCaption.

**План.** 1) EventsScreen -> Kit 'Events hub':
   - hero card with event icon, big timer and 3 perk icons (from PerkLines mapped to GameIcons);
   - Rush Pass horizontal milestone track with claim buttons;
   - icon timeline of upcoming events;
   - move Daily/Playtime to their own tab/card.
2) Event notice -> Kit toast with icon, a short line and a progress ring; keep the OpenMenu suppression.
3) District map -> Kit window: icon grid of destinations by category + 'SHOW PATH' per item + a real top-down map (camera-rendered ViewportFrame snapshot or an uploaded image) with a player arrow.
4) Decouple LocationLabels from the Sidebar (take icons from GameIcons) before the Sidebar is redesigned.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/EventsScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau`
- src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau (banner styling)
- `src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau`
- `src/ReplicatedStorage/WorldSignConfig/LocationLabels.luau`

**Новые модули.** 
- src/StarterGui/ScreenGui/Modules/EventsHub.luau (Kit based)
- src/StarterGui/ScreenGui/Modules/DistrictMapScreen.luau (Kit based)

**Совместимость данных.** UI only. Daily/Playtime actions ('DailyReward', 'PlaytimeReward') unchanged.

**Производительность.** Kit windows are built on open and destroyed on close. The countdowns already use Deadline attributes.

**Объём.** M

**Риски.** LocationLabels.Apply WaitForChild on Sidebar buttons hangs if they are renamed. ~10 navigate callers depend on names. Translation patches (DOGROTS_RU_ScreenPatch, AutoTranslate) may key on current texts.


## Аудитор `tooling-perf`

**Сейчас.** The UI kit (Kit/*: Window, Controls, Virtual, Preview, Motion, Maid, Lang) exists, with tests/uikit.luau. Each new text element pays global hooks: UITheme (DescendantAdded on all PlayerGui children), PlaceTypography, AutoTranslateUI (a PropertyChanged connection per label plus the pattern pass in RU), DOGROTS_RU_ScreenPatch. Motion.Reduced ignores the ReducedMotion attribute. The SoundGroups UI/SFX are missing. The inventory refetches the full Snapshot on every InventoryRevision. 4 ViewportFrames in the static GUI; Kit/Preview caches up to 48.

**План.** Tooling/perf part: (1) Every new Kit window sets NoTranslate (localizes via Localization/<Feature>.luau + Kit.T) and KeepFont where Kit chooses fonts, so the global hooks return early. Extend the localization coverage test pattern (dogdex/lab tests) to the new screens. (2) Wire Kit/Motion.Override to Perf/Quality.Reduced(). (3) Create SoundGroups DOGROTS_AUDIO/UI and SFX at runtime (server script, idempotent) and route Kit sounds there; volume from a client setting. (4) Inventory 2.0 uses Net.Snapshot(maxAge=4) plus DogEconomyPush deltas, not a Snapshot per revision; Kit/Virtual for grids (cells pooled), Kit/Preview with PerFrame=2 and the Quality viewport budget (12/8/4 visible). (5) Hover/open animations only via Motion.Tween (instant on Reduced). No per-frame loops in screens; a temporary Heartbeat only while animating, disconnected after, as MoneyController does. (6) Add the new screens to tests/perf_lint allowlists only if they truly need RenderStepped.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/Kit/Motion.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau`
- src/StarterGui/ScreenGui/Modules/UITheme.luau (skip Kit overlays)
- src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau (LRU cache, NoTranslate default for Kit roots)
- src/ReplicatedStorage/WorldSound.luau, RewardAudio.luau (SoundGroup routing)

**Новые модули.** 
- `src/ReplicatedStorage/Perf/Quality.luau`
- src/ServerScriptService/AudioBuses.server.luau (creates UI/SFX/Ambient SoundGroups)
- `src/ReplicatedStorage/Localization/<NewScreens>.luau`
- tests/ui_overhaul.luau (localization coverage + pure layout maths)

**Совместимость данных.** UI-only. Settings stay client attributes unless Settings.Quality/volume is persisted via an Economy feature with a default for old saves.

**Производительность.** Kit windows: zero idle per-frame cost. Snapshot traffic drops from about every 1.5 s to <=1 per 4 s while open. Viewport budget enforced by Quality.

**Объём.** L (UI work itself is other subsystems; the tooling/perf part is M)

**Риски.** Old screens still rely on AutoTranslate; marking too much NoTranslate without Lang entries shows English to RU players, which the coverage tests must catch. UITheme restyle hooks may restyle Kit elements unless excluded.
