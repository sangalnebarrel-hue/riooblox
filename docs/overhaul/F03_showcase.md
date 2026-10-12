# F3. Витрина «Мои лучшие находки» — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `plots` (основной)

**Сейчас.** Two separate displays. (1) MY BEST FINDS stand: PlotAppearance.showcase (L140-177) builds 3 pedestals Find/Dog/Relic inside yard.PlotDevelopment at frame (20*sx,0,55), and the stand is destroyed on every Apply. Content is chosen automatically by BestFinds.Select from Stats summaries, Items, DiscoveryFeed and best-rank dog. Exhibits are server clones, so others see them. There is no prompt, menu, preview, rarity FX or explicit save, and the stand parts have no collision. (2) DOG STORAGE dog displays: p.DisplayDogs (3 bays) edited via the DOG STORAGE terminal page (StorageScreen) or MY DOGS when near storage, persisted, protected from the shelter. The walk-up reference is DogKennelService: per-kennel ProximityPrompt -> server owner/distance/Allow check -> DogKennelOpen -> ServiceMenus picker -> DogEconomyRequest with retained requestId.

**План.** 1) Data: Features/Showcase.luau (Order ~50). p.Showcase={Version=1, Mode='Auto'|'Manual', Slots={['1']=ItemUid,...}, Rev}. Normalize: missing -> Mode='Auto' (old players look exactly as today); drop uids no longer owned; dedupe; clear slots above Slots(p). Actions: ShowcaseSet{Slot,Uid|''}, ShowcaseSwap{A,B}, ShowcaseAuto{}, ShowcaseFill{} (fill rarest into Manual). Snapshot: view.Showcase={Slots, Unlocked, Rows}.
2) Shared ReplicatedStorage/ShowcaseRules.luau: Slots(p) from a new PlotCatalog.Stages[n].ShowcaseSlots (proposal 3 at stages 1-4, 4 at 5-7, 5 at 8-9); Holds(p,uid); Rows(p) (Manual, or Auto = today's BestFinds.Select moved here); Token(row). Shared ReplicatedStorage/ItemRarity.luau: tier/color from CombinedOdds+Class+Mutation, thresholds calibrated by a Lune script over ItemDefinitions/WeightProfiles.
3) Protection: YardCommerce.CanSell returns false when Holds (covers BulkSell/SellQuote/NPCSell/SellableItems). ItemRules.Get(p,uid,true) errors 'Remove this find from your showcase first' (covers trade offer/commit Engine L300/L336, lab catalyst LabRules L40, SellItem).
4) Visit check: in Runtime.Request next to DisplayDog->StorageVisit (L424) add Showcase* -> YardCommerce.ShowcaseVisit. ShowcaseVisit uses PlotInteractionAccess with a new zone ShowcaseAnchor->ShowcaseInteractionZone.
5) World/interaction (copy DogKennelService.Start L248-262): new Economy/ShowcaseWorld.luau started from YardCommerce.Start. Per yard, create a persistent Folder 'ShowcaseAnchors' outside PlotDevelopment: the anchor and zone parts computed from A.Frame and sx, plus one Attachment+ProximityPrompt 'ShowcaseSlotPrompt' per pedestal ('PLACE FIND'/'CHANGE', 9-10 studs, hold .15). Triggered -> owner + <=14 studs + Runtime.Allow -> runtime-created RemoteEvent PlotShowcaseOpen(slot,yardId) -> GUIIntegration route (like L176) -> editor. PlotPrompts gates these prompts to the owner. Visitors get a client-local 'VIEW FIND' prompt (museum ViewMuseumEntry pattern) showing name, weight, 1 in N and finder.
6) Editor: Modules/ShowcaseEditor.luau, built with Kit.Window. Top: slot strip with previews and rarity frames. Body: Kit.CardGrid(Kind='Item'), sorted RAREST by default, with filters (class/mutation/depth/favorite) and search; cards Disabled for items pending in a trade or RecordJobs; badge 'ON SHOWCASE'. 'PREVIEW ON STAND' places a client-only ghost clone on the pedestal and tweens the camera; PLACE sends ShowcaseSet with a retained requestId (mutate pattern); WorldSound cues.
7) Rendering, phase 1: BestFinds.Reconcile renders ShowcaseRules.Rows. Extend showcase() to N pedestals, keeping Slots folder and slot names, keeping 'Dog' or updating Stare L23-25. Make foundation and pedestals collidable. Phase 2 (recommended): server publishes yard attribute ShowcaseLayout (compact JSON <=1 KB). Clients render exhibits + rarity FX in a local folder with distance gating: Rare rim light; Epic slow spin + sparkles; Legendary beam/halo + PointLight; Mythic/Secret aura + color cycle + float.
8) Dog pedestal: owner decision. Either keep the centre pedestal as auto best-dog, or make all pedestals items (dogs already have 3 DOG STORAGE bays).
9) Tests: tests/showcase.luau covering legacy=Auto equals BestFinds.Select, set/clear/dupe/foreign uid, slots per stage, BulkSell/NPCSell skip, trade/lab rejection, Normalize after removal, receipt idempotency.

**Файлы.** 
- `src/ServerScriptService/Economy/BestFinds.luau`
- src/ReplicatedStorage/PlotAppearance.luau (showcase() L140-177)
- src/ReplicatedStorage/PlotCatalog.luau (Stages ShowcaseSlots)
- src/ReplicatedStorage/PlotInteractionAccess.luau (zones)
- src/ServerScriptService/Economy/YardCommerce.luau (CanSell, ShowcaseVisit, Start)
- src/ServerScriptService/Economy/ItemRules.luau (I.Get transfer)
- src/ServerScriptService/Economy/Runtime.luau (Request visit check L419-424, Project L164-167)
- src/ServerScriptService/Economy/PlotDevelopment.luau (Reconcile)
- `src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- `src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Stare.luau`
- Inventory/Collector/Trade UIs (ON SHOWCASE badge)

**Новые модули.** 
- `src/ServerScriptService/Economy/Features/Showcase.luau`
- `src/ReplicatedStorage/ShowcaseRules.luau`
- `src/ReplicatedStorage/ItemRarity.luau`
- `src/ServerScriptService/Economy/ShowcaseWorld.luau`
- `src/StarterGui/ScreenGui/Modules/ShowcaseEditor.luau`
- `src/StarterPlayer/StarterPlayerScripts/PlotShowcaseClient.client.luau`
- `src/ReplicatedStorage/Localization/Showcase.luau`
- `tests/showcase.luau`

**Совместимость данных.** No migration: a new p.Showcase field defaults to Auto, so existing players see exactly today's stand. p.Stats.BestShowcase* and p.DisplayDogs are untouched. Uids of removed items are healed in Normalize. The MegaReset carry list is unaffected (cash-only content).

**Производительность.** Phase 1 keeps today's server exhibits (≤5 x avg 29 / max 105 parts) and drops the O(Items) scan by reading cached rows. Phase 2 removes server exhibits; per-stand budget ≤5 models, ≤3 PointLights (Shadows=false), ≤5 emitters enabled under 80 studs, spin/float under 120 studs; one ~1 KB attribute update per change instead of instance churn. Prompt anchors live outside PlotDevelopment so they are not recreated.

**Объём.** L

**Риски.** Protection changes SELL ALL, trade and lab behaviour (needs a clear badge and a one-tap remove). Stare path dependency. Anchors must survive PlotDevelopment rebuilds. The stand has a width limit between the walk (X ±4.5) and the fence (X ±34), so 5 pedestals need a redesigned stand. Streaming: client exhibits only once yard parts have streamed in. Rarity thresholds need calibration.


## Аудитор `data-network`

**Сейчас.** p.DisplayDogs{'1'..'3'} — стенды собак в Yard.DogStorage.DisplaySlots. Действие DisplayDog: гейт commerce.StorageVisit в Runtime.Request, DisplayRules.Assign, Normalize снимает висячие ссылки. Модели строит PlotShowcase.Reconcile из Runtime.Project. BestFinds (Yard.PlotDevelopment.BestFinds.Slots Find/Dog/Relic) выбирается автоматически и полным проходом по находкам в каждом Project. Есть сводки Stats.BestShowcaseFind/Relic/Heaviest/MostValuable/Rarest.

**План.** Модуль Features/Showcase.luau: p.Showcase={Version=1, Slots={['1'..'N']={Kind='Item'|'Dog', Uid}}, Seeded=true}, N≤6–8. Действия 'ShowcaseSet' {Slot,Kind,Uid} и 'ShowcaseClear' {Slot}. Гейт в Runtime.Request (или Registry.Gate): ShowcaseVisit(player) — игрок в своём участке рядом с якорем витрины, тот же PlotInteractionAccess.CanUse, что у StorageVisit. Открытие окна: ProximityPrompt на витрине → DogEconomyOpen 'Showcase' (как YardCommerce.TryOpen). Normalize снимает ссылки на проданное, обменянное, выставленное на рынок или съеденное лабораторией; Validate проверяет только структуру. Защита: BulkSell, Market Create, Trade Offer и катализаторы лаборатории отказывают по витринным uid ('Remove from showcase first'). Мир: ShowcaseWorld.Reconcile(player,p) из Project; токен слота (uid:mutation:weight) пересобирает модель только при изменении; модели из DiscoveryVisuals/LOD (F4). Snapshot.Features.Showcase и push 'Showcase'. Для старых игроков: при первом Normalize заполнить из BestFinds.Select (Find/Relic/Dog) и поставить Seeded=true.

**Файлы.** 
- src/ServerScriptService/Economy/Runtime.luau (гейт, вызов Reconcile в Project)
- src/ServerScriptService/Economy/YardCommerce.luau (BulkSell + ShowcaseVisit)
- src/ServerScriptService/Economy/Market.luau (Create)
- src/ServerScriptService/Economy/Engine.luau (Trade Offer)
- src/ServerScriptService/Economy/LabRules.luau (item() для катализаторов)
- src/ServerScriptService/Economy/BestFinds.luau / PlotDevelopment.luau (замена автоматики)

**Новые модули.** 
- `src/ServerScriptService/Economy/Features/Showcase.luau`
- `src/ServerScriptService/Economy/ShowcaseWorld.luau`
- клиентское окно Showcase (Kit)

**Совместимость данных.** Новый необязательный ключ; у старых профилей он пустой и заполняется из BestFinds. Формат находок и собак не меняется. ID слотов — строки.

**Производительность.** Убрать полный проход BestFinds в каждом Project. Пересборка моделей только по токену. Модели без скриптов, Anchored, CanQuery=false.

**Объём.** M

**Риски.** Между транзакцией и следующим Normalize могут быть висячие ссылки: мир и UI должны быть к ним устойчивы. Слишком большой N бьёт по FPS. Защита от продажи не должна мешать сценарию «обменять витринную вещь» (нужна понятная кнопка «снять»). Участки раздаются на сессию, поэтому раскладку хранить относительно слотов, а не мировых координат.


## Аудитор `economy`

**Сейчас.** BestFinds.Select picks the best find/relic automatically by stored SellValue and the best dog by rank/mastery; PlotShowcase and BestFinds.Reconcile render trophy copies (presentation only). There is no player choice and no persistence of a selection.

**План.** Feature module Features/Showcase.luau with p.Showcase={Version=1, Slots={[1..N]=ItemUid|DogUid}}; actions ShowcaseSet/ShowcaseClear. The selection menu sorts by rarity (ValueBreakdown.Rarity / exported ItemValuation rarity), mutation multiplier, CombinedOdds and live ItemValuation.Price. Showcased items must stay owned: Normalize clears slots whose uid is gone. Selling, trading or listing a showcased item (YardCommerce.CanSell/NPCSell/BulkSell, Engine:Trade Offer, Market:Create) is blocked or asks to confirm unpinning. Rarity effects key off the same rarity ladder as F4.

**Файлы.** 
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/ServerScriptService/Economy/PlotShowcase.luau`
- `src/ServerScriptService/Economy/YardCommerce.luau`
- `src/ServerScriptService/Economy/Engine.luau`
- `src/ServerScriptService/Economy/Market.luau`
- `src/ReplicatedStorage/ItemValuation.luau`

**Новые модули.** 
- `ServerScriptService/Economy/Features/Showcase.luau`

**Совместимость данных.** New optional p.Showcase; with no selection, fall back to the current automatic BestFinds.Select.

**Производительность.** The Showcase reconcile only runs on change; no per-tick work.

**Объём.** S (economy part)

**Риски.** Stale SellValue in RecordStats/BestFinds gives a wrong order: use live Price. Escrowed (listed) items have left p.Items, so they cannot be showcased.


## Аудитор `digging-depth`

**Сейчас.** Витрина BestFinds строится PlotAppearance/PlotDevelopment на месте «шестого слота» (около (−50,97) у Yard_04, X −55.5..−44.5, Z 85.5..108.5), рядом с рядом будок 2/4. Образец взаимодействия «как у стоек собак» — промпт будки: серверный ProximityPrompt → проверка владельца и дистанции + Runtime.Allow → DogKennelOpen:FireClient(slot) → ServiceMenus.

**План.** Повторить шаблон будки: серверный промпт на витрине (имя для фильтра «только владелец»), RemoteEvent открытия → меню выбора находок; изменения — через DogEconomyRequest (модули BestFinds/PlotShowcase). Учесть зону исключения F5: от края шахты слота 4 (X −59) до витрины 3.5 стада, туда же встанут Guard и лебёдка — не расширять витрину к шахтам.

**Файлы.** 
- `/home/user/riooblox/src/ServerScriptService/Economy/BestFinds.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/PlotShowcase.luau`
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau`

**Совместимость данных.** Нет в этой подсистеме.

**Производительность.** Нет.

**Объём.** S (часть, касающаяся этой подсистемы)

**Риски.** Наложение на ограждения шахт и стойки лебёдок; гостям не показывать промпт (тот же баг, что у MANAGE).


## Аудитор `item-models`

**Сейчас.** Стенд PlotDevelopment.BestFinds (PlotAppearance.showcase:140-175): 3 слота Find/Dog/Relic. BestFinds.Select сам выбирает лучшую находку и лучший артефакт по SellValue (Stats + все Items + лента) на каждом Runtime.Project. Сервер клонирует DiscoveryVisuals.Clone под 4.5×4.9×4.5. Выбора игрока, сохранения выбора, взаимодействия и FX нет. Стенды собак DogStorage.DisplaySlots работают через подсказку StorageAnchor → StorageScreen → DisplayRules.Assign → PlotShowcase.Reconcile.

**План.** Сторона моделей: 1) Новое поле профиля p.ShowcaseFinds={Version=1,Slots={['1']=ItemUid,...}} (6 слотов, открываются по PlotStage) и ShowcaseRules по образцу DisplayRules: Normalize выкидывает проданные, переданные и выставленные на рынок uid; Assign проверяет владельца и отсутствие в трейде и листинге. 2) Действие 'ShowcaseAssign'{Slot,Uid} в DogEconomyRequest (Runtime:371 clean args). 3) Подсказка на стенде через YardCommerce.prompt() ('MY BEST FINDS','Showcase','EDIT SHOWCASE'), только для владельца, по образцу StorageAnchor. 4) Kit-окно ShowcaseEditor: CardGrid своих находок (сортировка по редкости и цене, фильтр по редкости), Hero-превью L0 с вращением, кнопки слотов. 5) Сервер больше не клонирует модели: BestFinds.Reconcile пишет атрибуты слотов ItemId, Mutation, WeightKg, TierIndex, Rarity, Token, OwnerUserId. Если игрок ничего не выбрал — текущий автоподбор BestFinds.Select как запасной вариант (старые игроки ничего не теряют). 6) ItemExhibits.client рисует экспонаты всех стримящихся дворов через фабрику с LOD и FX редкости (свет и эмиттеры по глобальному бюджету, у своего участка приоритет). 7) PlotAppearance.showcase расширить под 6 пьедесталов и стеклянные колпаки с подсветкой по редкости; сохранить имя 'BestFinds' и Slots.Dog для SecretArrivals.

**Файлы.** 
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/ReplicatedStorage/PlotAppearance.luau`
- `src/ServerScriptService/Economy/PlotDevelopment.luau`
- `src/ServerScriptService/Economy/YardCommerce.luau`
- `src/ServerScriptService/Economy/Runtime.luau`
- `src/ServerScriptService/Economy/Rules.luau`
- src/ServerScriptService/Economy/YardCommerce.luau (BulkSell — не продавать выставленное без подтверждения)
- `src/StarterGui/ScreenGui/Modules/CollectorScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Stare.luau`
- `src/ServerScriptService/Economy/EstateQATests.luau`

**Новые модули.** 
- `src/ServerScriptService/Economy/ShowcaseRules.luau`
- `src/StarterGui/ScreenGui/Modules/ShowcaseEditor.luau`
- src/StarterPlayer/StarterPlayerScripts/ItemExhibits.client.luau (общий с F4)

**Совместимость данных.** Новое поле добавляется аддитивно и нормализуется в I.Normalize/Rules.Profile; при отсутствии работает автоподбор. Хранятся только ItemUid, а Normalize чистит висячие ссылки после продажи и трейда.

**Производительность.** Сервер: 0 частей экспонатов вместо 2 клонов на двор (до 105 частей каждый). Клиент: L0 ≤8 экспонатов, L1 ≤32, остальные L2 или скрыты; пересчёт LOD 3–4 раза в с.

**Объём.** L

**Риски.** Кнопка SELL ALL (CollectorScreen шлёт все uid) продаст выставленные предметы — сервер должен исключать их или требовать подтверждения. Перенос экспонатов на клиент ломает контракт Stare.luau и EstateQATests. Чужие стенды под стримингом появляются с задержкой (нужен DescendantAdded). Нагрузка при 10 стендах × 6 слотов — только через LOD и бюджет.


## Аудитор `ui`

**Сейчас.** The editing pattern to copy already exists. The DOG STORAGE prompt (YardCommerce.Start, StorageAnchor + StorageInteractionZone, YardInteraction prompt enabled by PlotPrompts.client) sends DogEconomyOpen('Storage') to StorageScreen (legacy Menus): choose display slot 1-3, then PLACE a dog via the DisplayDog action; the server PlotShowcase builds models. BestFinds.Select picks trophies automatically; the player cannot choose finds.

**План.** UI side:
- Server adds a ShowcaseAnchor + ShowcaseInteractionZone with a YardInteraction prompt 'MY BEST FINDS' that sends DogEconomyOpen('Showcase').
- GUIIntegration wrapper routes 'Showcase' to a new Kit window, ShowcaseScreen.
- Top: slot strip (3-6 pedestals) with rarity glow and the current item preview.
- Below: CardGrid of owned finds (Kit.Preview Item), sorted by rarity then value, with rarity chips and search.
- Tap card, then tap slot, or 'PLACE IN SLOT N'; 'REMOVE'; Kit.Confirm for replacing.
- The new Inventory shows a 'ON SHOWCASE' badge plus a 'Showcase' secondary action, and warns before selling, listing or trading a showcased item.
- The same window is reachable from the inventory, but placing still requires the zone to match the 'walk up to the stand' rule (server PlotInteractionAccess).

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- src/StarterGui/ScreenGui/Modules/StorageScreen.luau (later also to Kit)
- src/ServerScriptService/Economy/YardCommerce.luau (prompt)
- src/ReplicatedStorage/PlotInteractionAccess.luau (zone name)
- src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau (automatic: tracks YardInteraction)
- new Inventory screen

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/ShowcaseScreen.luau`

**Совместимость данных.** New optional p.Showcase{Slots={[n]=ItemUid}}; absent means empty, falling back to the current automatic BestFinds selection.

**Производительность.** CardGrid virtualised; one preview per visible card plus 6 slot previews.

**Объём.** M

**Риски.** Items on the showcase must be protected or auto-removed on sale, listing or trade (server). Older yards lack the anchor geometry (world audit). Keep Key distinct from 'Storage'.


## Аудитор `trade-titles`

**Сейчас.** PlotShowcase/BestFinds are presentation-only today (auto-picked best find/relic/dog, BestFinds.Select). Trade eligibility does not look at showcases; displayed dogs (DisplayDogs) are tradeable and Display.Normalize silently drops them after transfer (verified).

**План.** When F3 lets players pin chosen finds/dogs to the plot showcase (new saved list), TradeRules eligibility must treat pinned assets as 'On showcase'. Either block them with the reason 'Remove from showcase first' (like ShelterRules does for displays), or allow them with a warning and auto-unpin in the commit transform. Expose a shared helper (Showcase.IsPinned(p,uid)) used by TradeService, ShelterRules, Market:Create and lab material pickers.

**Файлы.** 
- `src/ServerScriptService/Economy/ShelterRules.luau`
- `src/ServerScriptService/Economy/Market.luau`
- `src/ServerScriptService/Economy/DisplayRules.luau`

**Новые модули.** 
- `src/ServerScriptService/Economy/TradeRules.luau`

**Совместимость данных.** Showcase pin list is new data; the commit must clean pins of assets that left the profile (Normalize already does this for DisplayDogs).

**Производительность.** Negligible.

**Объём.** S

**Риски.** Inconsistent rules between trade, shelter, market and lab if each module re-implements eligibility.


## Аудитор `tooling-perf`

**Сейчас.** There is already an automatic 'Best Finds' stand per yard (Economy/BestFinds.luau: slots Find/Dog/Relic chosen by SellValue/rank, ExhibitToken diff, models cloned server-side from DiscoveryVisuals/DogTemplates) and player-chosen display dogs (Economy/PlotShowcase.luau: DogStorage.DisplaySlots Slot1..3 from p.DisplayDogs). Both reconcile on every Runtime.Project. SecretAura auto-attaches auras to secret dogs in yards.

**План.** Tooling/perf part: (1) Showcase layout as a pure module (ShowcaseLayout.luau: stand plinths/glass relative to a yard anchor next to DisplaySlots), unit-tested for footprint/no-overlap with MiningCorner/PlotDevelopment (reuse MiningWorld placement() frame) and for a budget of <=150 parts. (2) Server builds the stand once per yard (World/Builder, LayoutVersion), ModelStreamingMode Atomic; exhibits keep the existing token-diff approach (only rebuild a slot when its token changes). Move the 'select best' work out of every Project, e.g. recompute only on InventoryRevision/selection change. (3) Rarity effects client-side via Perf/Lod (near: emitter + light marked FXManaged and counted in the Quality light budget; far: off). Highlight only through a shared budget, never one per slot. (4) Interaction mirrors the kennel/display prompts (PlotPrompts pattern, ProximityPrompt on the stand). The selection preview reuses Kit/Preview.

**Файлы.** 
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/ServerScriptService/Economy/PlotShowcase.luau`
- src/ServerScriptService/Economy/Runtime.luau (Project: call showcase reconcile only on change)
- `src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau`
- src/StarterPlayer/StarterPlayerScripts/SecretAura.client.luau (respect the shared budget)

**Новые модули.** 
- `src/ReplicatedStorage/Showcase/ShowcaseLayout.luau`
- `src/ReplicatedStorage/World/Builder.luau`
- `src/StarterPlayer/StarterPlayerScripts/ShowcaseFX.client.luau`
- `src/ReplicatedStorage/Perf/Lod.luau`
- `tests/showcase.luau`

**Совместимость данных.** New selection field (e.g. p.Showcase={slot->ItemUid}) added through an Economy/Features module with Normalize defaulting to the current BestFinds auto-selection, so old saves show the same stand. Do not reuse p.DisplayDogs keys.

**Производительность.** Server: no O(items) scan per refresh. Client: rarity FX only within ~60 studs (Lod) and counted in the Quality light budget. <=150 parts per stand.

**Объём.** M

**Риски.** Must not overlap MiningCorner (MINING_CLEARANCE) or PlotDevelopment stage props across 9 levels x 14 skins; put this check in the Lune layout test. SecretAura will add auras to secret exhibits automatically, which must stay within the budget.
