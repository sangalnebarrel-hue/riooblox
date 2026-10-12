# F8. Косметика участков — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `plots` (основной)

**Сейчас.** Only 14 whole-yard skins (Classic, 11 for Cash 6k-500k after the x5, 2 Secret earned), mostly world-event themed. Buy/claim only inside COSMETICS (VisitShop), equip anywhere. All visuals are server-procedural via PlotAppearance (up to 2,260 instances per yard). There are no individual decorations, no placement and no decor data. YardCustomization sockets in the place are unused and partly obsolete (KennelSocket sits inside the MiningCorner area). Free space is small: the yard is crowded by kennels/pits, Lucky court, MiningCorner, buildings and the BEST FINDS stand.

**План.** 1) Keep skins as the 'Yard theme' layer; add an independent 'Decor' layer.
2) Catalog ReplicatedStorage/DecorCatalog.luau. Fields: Id, Name, Category (Building/Plant/Light/Decor/Statue/Zone), Rarity, Price {Cash, Bones?}, Source (Shop | Event:<id> | Achievement:<id> | Stage:<n>), Footprint {W,D} in 4-stud cells, Height, PartBudget, Builder, flags (Light, Particles, Float). Builders: ReplicatedStorage/DecorBuilders/* procedural on PlotGeometry primitives (build.py cannot add models). Dog statues reuse MenuModels with Marble/Gold material (≈5 parts). Example set: Buildings (deluxe doghouse, gazebo, greenhouse, watchtower), Plants (oak, pine, palm, hedge, flower bed, mushroom ring), Lighting (lamp post, string lights between fence posts, lantern, fire pit, neon sign), Decor (bench, fountain, bone pile, flags, crates), Statues (dog statue, trophy, obelisk), Zones (ground themes: meadow, sand, snow, lava rock, crystal floor).
3) Zones ReplicatedStorage/PlotDecorZones.luau. Grid zones in the A.Frame local frame with sx mirroring: Z 7.5..16.5 strips, garden depth behind MiningCorner, strip in front of buildings Z -40..-33.5, fence-line linear sockets, 1-2 landmark sockets (garden pavilion/monument spot). Reserved masks: EntryWalk, pits, kennel houses, ApproachPosition, Lucky pads, MiningCorner pad, BEST FINDS stand, interaction zones, gate. Verified by a Lune 3D overlap test over all 8 yards in the built place (as MINING.md did).
4) Data: Features/Decor.luau. p.Decor={Version=1, Owned={[id]=n}, Layout={[key]={Id,Z,C,R}}, Next, Rev}. Caps: total by stage (e.g. 10+4*stage), per category (Building ≤3, Statue ≤4, Light ≤10, Zone 1 per zone). Actions: DecorBuy{Id,Count,Quote?}, DecorPlace{Id,Zone,Cell,Rot}, DecorMove{Key,Zone,Cell,Rot}, DecorRemove{Key}, DecorReset{}. The server validates footprint and overlap with the shared zone module. Grant API Decor.Grant(p,id,n,source) for events (F7), achievements (F10) and stage rewards.
5) Interaction: 'DECORATE' from the Yard page and a world prompt at the gate/EstateLevel sign (owner, inside own yard), handled by Modules/DecorBuildMode: tilted camera; grid overlay only for the active zone (pooled flat parts/SelectionBoxes); ghost model; rotate; place/move/remove; catalog tray via Kit.CardGrid with Kit.Preview.Register('Decor'); each action is a DogEconomyRequest with a retained requestId. Owner decision: buy at COSMETICS (existing VisitShop rule) or in the tray.
6) Rendering: the server writes yard attributes DecorLayout (compact string) and DecorRev in Runtime.Project. StarterPlayerScripts/PlotDecorRenderer builds into workspace.LocalPlotDecor/Yard_n: pooling by Id; LOD (≤180 studs full, 180-400 silhouette builder, >400 none); build only while the yard's YardFoundation is streamed in; light scheduler (closest 6 per yard, like the museum's); emitters under 100 studs; CanQuery=false; only simple hitboxes collide.
7) UI: rework PlotShopScreen into a Kit 'MY PLOT' window with tabs THEMES / DECOR, lightweight previews (no whole-yard clone); titles move to F10.
8) Prices: bands aligned with stage costs (8k-3.17M) and skins (6k-500k): Common 5-20k, Uncommon 30-90k, Rare 150-400k, Epic 0.8-2M, Legendary 3-8M + Bones; event/achievement items are not purchasable.
9) Optional big win: move PlotAppearance cosmetic generation into the same client renderer (see needsRefactor).
10) Tests: tests/decor.luau (rules, caps, ownership counts, receipts) plus the place overlap test.

**Файлы.** 
- src/ReplicatedStorage/PlotCatalog.luau (stage decor caps)
- src/ReplicatedStorage/PlotAppearance.luau (expose frame/sx; optional client split)
- src/ReplicatedStorage/PlotGeometry.luau (more primitives)
- src/ServerScriptService/Economy/Runtime.luau (Project attributes, Request visit checks)
- `src/ServerScriptService/Economy/PlotDevelopment.luau`
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- `src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau`
- src/ServerScriptService/MiningWorld.server.luau (if generation moves client-side)
- src/ServerScriptService/Economy/Rules.luau (MegaReset carry list only if Robux decor)

**Новые модули.** 
- `src/ReplicatedStorage/DecorCatalog.luau`
- `src/ReplicatedStorage/DecorBuilders/*.luau`
- `src/ReplicatedStorage/PlotDecorZones.luau`
- `src/ServerScriptService/Economy/Features/Decor.luau`
- `src/StarterPlayer/StarterPlayerScripts/PlotDecorRenderer.client.luau`
- `src/StarterGui/ScreenGui/Modules/DecorBuildMode.luau`
- `src/ReplicatedStorage/Localization/Decor.luau`
- `tests/decor.luau`

**Совместимость данных.** New p.Decor field with defaults from the feature Normalize; no migration. PlotSkins/EquippedPlotSkin keep working as the theme layer. Removing a decor item from the catalog must keep it in Owned but skip rendering (never delete). Robux decor would have to be added to the MegaReset carry list (Rules.Normalize L56) and PurchaseService receipts.

**Производительность.** Per-plot budget: decor ≤600 parts, total cosmetic ≤~2,000 (today up to 2,260 generated + ~1,400 base parts); ≤6 PointLights without shadows; ≤3 emitters active; ≤40 animated parts. Network: one ~1-2 KB attribute per change instead of thousands of replicated instances. The client builds only nearby yards with LOD and pooling. Server cost: validation only.

**Объём.** XL

**Риски.** Very little free space; collisions with MiningCorner, lucky pads, pits (F5 shafts), kennel approach points and LOS prompts. Client-only decor is invisible to server pathfinding (F1) and to MiningWorld.coverGround. Streaming may show decor before the base yard streams in. Procedural-only assets cap visual quality until the owner imports meshes in Studio. Build mode on mobile needs careful UX. Every placement must be validated on the server.


## Аудитор `data-network`

**Сейчас.** p.PlotSkins{id=true}, p.EquippedPlotSkin, PlotCatalog (13 скинов, 9 стадий). PlotRules.Action BuyPlotSkin/ClaimPlotSkin/EquipPlotSkin (гейт VisitShop в Runtime.Request и Engine:Action). p.Cosmetics и C.Cosmetics (косметика кеннелей). PlotAppearance.Apply из PlotDevelopment.Reconcile в каждом Project.

**План.** Модуль Features/Decor.luau: p.Decor={Version=1, Owned={[decorId]=count}, Placed={['<cell>']={Id=decorId,R=0..3}}}. Ячейка — целое число в сетке участка, хранится относительно участка, потому что участки раздаются на сессию. Действия: 'DecorBuy' {Id,Quote?} (Cash/Bones; Robux — через Feature.Catalogs → PurchaseService), 'DecorPlace' {Id,Cell,Rot}, 'DecorRemove' {Cell}, 'DecorClear'. Гейт: владелец стоит в своём участке. Validate: Placed ≤ кап (40–60), ячейка в сетке и не на кеннелях или DigSlot, Owned ≥ число размещённых. Мир: DecorWorld.Reconcile по сигнатуре (только при изменении) или клиентская сборка по компактному атрибуту участка. Каталог ReplicatedStorage/DecorCatalog (ID только добавляются).

**Файлы.** 
- src/ServerScriptService/Economy/Runtime.luau (гейт, Reconcile в Project)
- `src/ServerScriptService/Economy/PlotDevelopment.luau`
- src/ServerScriptService/Economy/Rules.luau (список переноса мега-сброса L56, если Decor продаётся за Robux)
- tests/payments.luau (тест переноса)

**Новые модули.** 
- `src/ServerScriptService/Economy/Features/Decor.luau`
- `src/ServerScriptService/Economy/DecorWorld.luau`
- `src/ReplicatedStorage/DecorCatalog.luau`

**Совместимость данных.** Новый необязательный ключ. В DataStore только целые числа и строки, никаких Vector3. ID декора только добавляются. Платное — в список переноса мега-сброса.

**Производительность.** Кап размещений, модели с малым числом частей из шаблонов, пересборка только при изменении, StreamingEnabled (участок — Model с атомарной загрузкой).

**Объём.** L

**Риски.** Рост профиля (60 размещений × ~40 Б ≈ 2,4 КБ — нормально). Коллизии с геометрией участка. Стадии участка меняют доступные клетки. Спорные покупки за Robux.


## Аудитор `economy`

**Сейчас.** Cosmetic sinks are small and fixed: 14 plot skins (12 buyable at 6K-500K after x5, PlotCatalog.luau:33; NULL HOUR and THE VOID are earned), 9 yard stages through the Plot upgrade, C.Cosmetics titles 50K-1M (+100 bones). The purchase goes through PlotRules.Action BuyPlotSkin at the COSMETICS terminal and decrements p.Cash directly. Stage decorations are placed automatically by PlotAppearance; there are no player-placed decorations.

**План.** Add a pure ReplicatedStorage/DecorCatalog.luau: {Id, Category=Building|Plant|Light|Decor|Statue|Zone, Rarity, Cash, Bones?, Requires={Layer?, Prestige?, Event?}, MaxPerPlot, Footprint}. Price tiers are fixed prices of about 10-30 minutes of the target stage's income: Common 25K, Uncommon 150K, Rare 1M, Epic 8M, Legendary 60M (+50 bones), Mythic 500M (+250 bones), Prestige statues 1B+ with Prestige >= N. Event-only items are granted by F7 and never sold. New feature module Features/PlotDecor.luau with p.PlotDecor={Version=1, Owned={[id]=n}, Placed={[slotKey]={Id,Rot}}} and actions DecorBuy/DecorPlace/DecorRemove; validate slot keys against the plot grid; cap placed items (about 40) for performance. No sell-back, or at most 25%, to avoid arbitrage; not tradeable at first. Route purchases through R.Pay.

**Файлы.** 
- src/ServerScriptService/Economy/PlotRules.luau (use R.Pay)
- src/ServerScriptService/Economy/PlotDevelopment.luau (Reconcile placed decor)
- src/ReplicatedStorage/PlotAppearance.luau (world side)
- src/ServerScriptService/Economy/ShopInteriorAccess.luau (where buying is allowed)

**Новые модули.** 
- `ReplicatedStorage/DecorCatalog.luau`
- `ServerScriptService/Economy/Features/PlotDecor.luau`

**Совместимость данных.** New optional p.PlotDecor; keep p.PlotSkins/EquippedPlotSkin/PlotProgressionVersion untouched.

**Производительность.** Server validation is O(placed); world rendering cost is the world subsystem's concern.

**Объём.** M (economy) / L with world placement

**Риски.** Placed decorations raise the part count per plot (performance, streaming); fixed prices get cheap for full-tree players (add Bones and Prestige gates for the top tiers); existing skin prices should not be lowered.


## Аудитор `digging-depth`

**Сейчас.** PlotAppearance раскладывает сад, витрину, забор, ворота и фонари по стадиям и 14 скинам; MINING_CLEARANCE уже отодвигает декор от MiningCorner.

**План.** Ввести зоны исключения шахт (следы 12×12, Guard, лебёдки, тотем) в общий модуль размещения декора; новые украшения не ставить в эти зоны. Лебёдки, копёр и тотем красить цветами скина (PlotCatalog Color/Trim/Glow) — часть «уникальности». Отдельный набор «шахтёрского» декора (вагонетки, рельсы, кристаллы, фонари) как категория косметики.

**Файлы.** 
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau`
- `/home/user/riooblox/src/ReplicatedStorage/PlotCatalog.luau`

**Совместимость данных.** Нет в этой подсистеме.

**Производительность.** Декор — серверные части у всех (TargetRadius 1024).

**Объём.** S (ограничения) / M (набор декора)

**Риски.** Пересечения на 8 участках × 9 стадиях × 14 скинах — нужна автоматическая проверка, как сделано для MiningCorner.


## Аудитор `item-models`

**Сейчас.** Декор участка строится процедурно в PlotAppearance (Part/WedgePart, свои функции P/G.Sign/G.Crest/lamp), без общего словаря примитивов и без LOD.

**План.** Сделать ItemModels/Primitives общим словарём примитивов и использовать формат рецептов и LOD-менеджер ItemExhibits для декора (статуи, растения, свет). Статуи «моих находок» — рецепт предмета с материалом Marble/Foil через фабрику.

**Файлы.** 
- `src/ReplicatedStorage/PlotAppearance.luau`

**Новые модули.** 
- src/ReplicatedStorage/ItemModels/Primitives.luau (общий)

**Совместимость данных.** Не затрагивает данные предметов.

**Производительность.** Общий LOD-менеджер и бюджеты на двор.

**Объём.** M

**Риски.** Смешение бюджетов декора и экспонатов — нужен общий счётчик частей на двор.


## Аудитор `ui`

**Сейчас.** Yard cosmetics UI is PlotShopScreen (legacy Menus 'Cosmetics', YARD STYLES): a list of plot skins (PlotCatalog.Skins), opened from the COSMETICS shop terminal (ShopInteriorAccess route). It is rebuilt every 5 s.

**План.** Kit DecorScreen, Key='Cosmetics':
- Category tabs (Themes/Skins, Buildings, Plants, Lighting, Decor, Statues).
- CardGrid with Kit.Preview.Register('Decor', ...) 3D previews, owned/equipped/price states, Kit.Confirm for purchase.
- 'Place in my yard' handing off to the placement mode built by the plots audit.
- Keep skins as one tab so existing purchases stay visible.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`
- src/StarterGui/ScreenGui/Modules/Kit/Preview.luau (Register)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/DecorScreen.luau`

**Совместимость данных.** Must read the existing p.PlotSkins/EquippedPlotSkin; new decor ownership comes from the plots audit.

**Производительность.** Virtualised grid, cached previews.

**Объём.** M

**Риски.** Purchase flows (Robux vs Cash) need the server-confirmed pattern already used by CommerceShopScreen/ProductPricing.


## Аудитор `trade-titles`

**Сейчас.** Rules.Action 'Cosmetic' (Rules.luau:522-527) treats ANY p.Cosmetics key that is not in C.Cosmetics as an equipable 'collection title'; PlotShopScreen lists every owned non-legacy key as a title.

**План.** If F8 stores decorations/statues/themes as unlocks, keep them OUT of p.Cosmetics: use a new p.PlotDecor / p.DecorOwned table. Otherwise new decor ids become 'titles' that can be equipped into EquippedCosmetic and shown over dogs. Alternatively, have Titles/Cosmetic only accept ids present in TitleDefinitions or C.Cosmetics. Plot titles (e.g. 'MEGA ESTATE OWNER' from PlotCatalog.Level) can be F10 titles.

**Файлы.** 
- `src/ServerScriptService/Economy/Rules.luau`
- `src/StarterGui/ScreenGui/Modules/PlotShopScreen.luau`

**Совместимость данных.** Restricting the 'Cosmetic' action to known ids must still allow every existing owned key (map them in TitleDefinitions first).

**Производительность.** None.

**Объём.** S

**Риски.** Namespace collision between decor unlocks and titles if both use p.Cosmetics.


## Аудитор `events-nav`

**Сейчас.** PlotCatalog has 14 event-themed yard skins. DOG RUSH requires WorldEventsSeen.DOG_RUSH + GlobalDigContribution>=90 + Cash 18000. The legacy weekly milestones set p.Cosmetics['Event'..i].

**План.** Make the Rush Pass / event pass a source of plot decorations (racing flag arch, golden dog statue, paw-print path tiles, trophy podium) through the plot decor catalog of the plots subsystem. EventPass claim grants the decor id into the plot inventory field of that subsystem. Keep the existing event skins and their unlock rules.

**Файлы.** 
- src/ReplicatedStorage/WorldEvents/EventPassConfig.luau (reward rows reference decor ids)
- `src/ServerScriptService/Economy/Features/EventPass.luau`

**Совместимость данных.** Additive grants only; never remove existing PlotSkins/Cosmetics.

**Производительность.** Decor models are owned and budgeted by the plots subsystem.

**Объём.** S

**Риски.** Decor id namespace must be agreed with the plot cosmetics owner.


## Аудитор `tooling-perf`

**Сейчас.** PlotAppearance.Apply rebuilds the whole PlotDevelopment model on level/skin change (9 stages x 14 skins from PlotCatalog), and writes PlotBase* attributes on yard parts (10,952 x 4 already baked). DistrictWorldMotion and PlotSkinMotion animate props by attributes. Each yard already has 1,430 static parts; runtime part counts of PlotDevelopment were not measured (Lune cannot run PlotAppearance: it needs .Position/PivotTo).

**План.** Tooling/perf part: (1) A decoration catalog as data plus pure placement layouts (grid of decoration sockets per yard derived from the PlotAppearance.Frame logic). A Lune test checks the per-plot budget (<=300 parts and <=4 lights for all cosmetics together), no overlap with MiningCorner/BestFinds/showcase/F5 shafts across all 9 stages, and determinism. (2) Each placed decoration is its own small Model (Atomic streaming) built by World/Builder and rebuilt only when that socket's token changes (BestFinds token pattern), not by rebuilding PlotDevelopment. (3) Motion via the existing attributes (Motion=Float/Ring/Pulse, PlotFloat). Lights/emitters marked FXManaged and registered with Quality budgets, so WDQ does not fight them. Lod for small props (hide beyond ~180 studs). (4) A Studio PerfProbe check: worst case of 8 fully decorated yards.

**Файлы.** 
- `src/ReplicatedStorage/PlotAppearance.luau`
- `src/ReplicatedStorage/PlotCatalog.luau`
- `src/ServerScriptService/Economy/PlotDevelopment.luau`
- `src/StarterPlayer/StarterPlayerScripts/PlotSkinMotion.client.luau`
- src/StarterPlayer/StarterPlayerScripts/WorldDetailQuality.client.luau (FXManaged)

**Новые модули.** 
- `src/ReplicatedStorage/Cosmetics/DecorCatalog.luau`
- `src/ReplicatedStorage/Cosmetics/DecorLayout.luau`
- `src/ServerScriptService/Economy/Features/Cosmetics.luau`
- `tests/cosmetics.luau`

**Совместимость данных.** Owned/placed decorations as a new profile field via a Features module; Normalize must keep EquippedPlotSkin and the legacy skin mapping (PlotRules legacy GoldenKennel/CyberKennel/VoidAura).

**Производительность.** Socket-level rebuilds instead of whole PlotDevelopment. Budget enforced in tests. Lights within the Quality budget.

**Объём.** L

**Риски.** Overlaps with the stage props of 9 levels; PlotDevelopment destroy/rebuild would wipe decorations if they are parented inside it, so put them in a sibling folder. Join-time cost of 8 decorated yards.
