# F5. Глубокая шахта — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `digging-depth` (основной)

**Сейчас.** Глубина есть только в данных: 5 слоёв (Config.Layers и DepthDefinitions; Backyard/Caverns/Ancient Ruins/Cursed Depths/THE VOID), профиль CurrentLayer/UnlockedLayers, действие 'Layer' (Cash + Level, VOID требует Prestige 1). Все собаки игрока копают на CurrentLayer. В мире 5 ям 12×12×0.4 на поверхности каждого участка (DigSlot_N/DarkExcavation, Y 0.8..1.2), собака стоит на верху ямы. Под участком плита Rock 32 стада (IslandMass Y −32..0), ниже пусто до −250; DistrictSafety возвращает на спаун при Y < −85. Свободного места на поверхности нет. StreamingTargetRadius=1024, поэтому вся серверная геометрия приходит каждому клиенту.

**План.** Вариант A (рекомендуется): вертикальная шахта под каждой из 40 ям (12×12), уровни внутри плиты 32 стада. Соответствие: Surface=L1 Backyard (пол Y 1.2, как сейчас), Depth1=L2 Caverns (−7), Depth2=L3 Ruins (−15), Depth3=L4 Cursed (−23), Rare=L5 THE VOID (−31); шаг 8, собака ≤4.2.

СЕРВЕР: новый DeepMineWorld.server + чистый MineGeometry.
(1) На старте (идемпотентно, LAYOUT_VERSION) вычитанием прямоугольников разрезать 16 IslandMass и 16 LivingGround срезов (центры Z 102/114/126/138, 18/30/42/54, −54/−42/−30/−18, −138/−126/−114/−102) и WorkArea/YardFoundation каждого участка; копировать Name, Color, Material и атрибуты. Оригинальный YardFoundation оставить невидимой опорой для A.Frame и MiningWorld (переписать его PlotBase*), куски назвать YardFoundationTile.
(2) На каждый слот — модель yard.DeepMine.Shaft_N (Atomic; владельцу AddPersistentPlayer): Floor (коллизионный), Seal (Y −32.6..−32), 4 невидимых Guard высотой 12 (CanCollide=true, CanQuery=false).
(3) DeepMine.Reconcile(player,p) вызывается из Runtime.Project до Kennels.Reconcile: ShaftOpen = Unlocked and CurrentLayer>=2; Floor → Y уровня; Guard включены при открытой шахте. Атрибуты участка MineLayer/MineDeepest/MineRevision писать только при изменении; у участка без владельца — 1 и всё закрыто.
(4) PlotAppearance (цикл DigSlot): DarkExcavation — крышка, при ShaftOpen show(false); у закрытого слота крышка принудительно коллизионна.
(5) DogKennelService: prepare берёт верх пола из DeepMine.FloorTop(slot). Reconcile при смене слоя перепивотит модели и ставит DigLayer, DigLayerFromY, DigLayerAt. SleepLabelAnchor — у верха шахты. Промпт MANAGE переносится на ApproachPosition (стойка лебёдки), только для владельца.
(6) KennelLootPlacement.Marker — на Floor.

КЛИЕНТ: DeepMineClient + Chunks/LOD/Pool/Transitions/Winch/Gauge, конфиг DeepMine/DepthVisuals (цвета Config.Layers[k].Color).
• Чанк = (участок, слот, полоса k). Полоса k = [Floor(k), Floor(k−1)] в стиле слоя k: Caverns — янтарь, кварц, крепь; Ruins — кладка, голубые глифы, монеты; Cursed — фиолетовый базальт, цепи, туман; VOID — чёрное стекло, искры, кубы.
• LOD: <90 стадов — полный (стены + 4–8 пропсов + 1 свет и 1 эмиттер на участок); 90–220 — только стены; >220 — ничего (видны Rock-грани разреза).
• Бюджет: ≤30 инстансов на полосу, ≤150 на участок, ≤40 инстансов за кадр, пул шаблонов, планировщик раз в 0.25–0.5 с. Свет и частицы класть под DOGROTS_District, чтобы их ограничивал WorldDetailQuality.
• Стриминг как в MiningClient/World.luau.
• Лебёдка-копёр над открытой шахтой (цвета скина), свечение цвета слоя, тотем глубины на участке (5 колец).
• Переход при росте MineLayer: пыль, звук (MiningAudio), тряска только у владельца, локальный твин пола и собак 1.6 с, проявление полосы, баннер. При уменьшении — подъём лебёдкой.
• Peek-камера по MANAGE.

ОТКРЫТИЕ: прежнее действие 'Layer'; плюс мировая «консоль глубины» (промпт владельца открывает ServiceMenus 'Layers') и карточки с превью находок (DepthDefinitions/ItemDefinitions).

RARE ZONES: L5 + «редкие жилы» по EventDepth мировых событий + всплеск на находку с шансом <1% или Secret.

БЕЗОПАСНОСТЬ: Guard 12, коллизионный Floor, спасение из объёма шахты ниже Y 0 на YardSpawn.

Фазы: 1 — визуал по CurrentLayer; 2 (опционально) — d.DigLayer на слот; 3 (опционально) — ходимая галерея под островом (сдвинуть порог DistrictSafety).

Тесты: tests/deep_mine.luau (геометрия: нет перекрытий, сумма объёмов, следы на 8 участках; Reconcile на фейках), расширить tests/kennel.luau (посадка на глубине), тест действия 'Layer'.

**Файлы.** 
- `/home/user/riooblox/src/ServerScriptService/DogKennelService.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/KennelLootPlacement.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/Runtime.luau`
- `/home/user/riooblox/src/ReplicatedStorage/PlotAppearance.luau`
- `/home/user/riooblox/src/ServerScriptService/MiningWorld.server.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau`
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/Config.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/Rules.luau`
- `/home/user/riooblox/src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `/home/user/riooblox/src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `/home/user/riooblox/src/ServerScriptService/DistrictSafety.server.luau`
- `/home/user/riooblox/tests/kennel.luau`
- `/home/user/riooblox/docs/MINING.md`

**Новые модули.** 
- /home/user/riooblox/src/ReplicatedStorage/DeepMine/MineGeometry.luau (чистые функции: следы шахт по атрибутам DigSlot, Y полов, вычитание прямоугольников для плиты; тестируется в Lune)
- /home/user/riooblox/src/ReplicatedStorage/DeepMine/DepthVisuals.luau (визуал по слою 1..5: материалы, цвета, пропсы, FX, свет)
- /home/user/riooblox/src/ServerScriptService/DeepMineWorld.server.luau (установка геометрии и оболочек, Reconcile, перенос состояния на участок)
- /home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DeepMineClient.client.luau + DeepMineClient/{Chunks,LOD,Pool,Transitions,Winch,Gauge}.luau
- `/home/user/riooblox/tests/deep_mine.luau`

**Совместимость данных.** Фаза 1: ноль новых сохраняемых полей. Визуал читает существующие CurrentLayer и UnlockedLayers: старые игроки сразу видят свою глубину (никого не сбрасывать на Surface — это урезало бы доход), новые профили стартуют с CurrentLayer=1 (Surface). Не трогать Config.Version, MegaResetVersion и имена слоёв; не добавлять шестую экономическую глубину (ключи records:<depth>, ItemDefinitions.Depth). Фаза 2: d.DigLayer необязателен (nil = CurrentLayer), миграция не нужна; Rules.Validate проверяет ≤ MaxUnlockedLayer.

**Производительность.** Сервер: +около 256 кусков плиты, +около 200 кусков основания и рабочей зоны, +около 280 частей оболочек (около 540–700 статичных частей); никаких циклов на кадр, работа только при смене слоя или владельца. Клиент: ≤150 частей на полностью построенный участок, обычно ≤3 участка (≤450), ≤6 источников света и ≤6 эмиттеров через WorldDetailQuality, сборка ≤40 инстансов за кадр, пул. Сеть: 3 атрибута на участок + CFrame 5 полов и 5 моделей собак на смену слоя; новых remote нет.

**Объём.** L (фаза 1); фаза 2 — M-L; фаза 3 — L

**Риски.** Разрез плиты во время работы не виден в Studio Edit (только в Play) — задокументировать или позже «запечь» в плейс. PlotAppearance восстанавливает скрытые части по PlotBase* — каждую часть, которую прячет шахта, согласовать с ним. A.Frame и MiningWorld.placement зависят от YardFoundation. Промпты станут недоступны за ограждением, если не перенести их. Дно узкой шахты видно только у края — нужны peek-камера и свечение, иначе вариант B (большой карьер, XL). Мобильный бюджет 8 источников света. Все серверные части у всех клиентов (TargetRadius 1024). Пересечения с F3, F8 и MiningCorner. Кинематика LongDog у ямы. Глубина на собаку в фазе 2 сдвигает баланс.


## Аудитор `data-network`

**Сейчас.** Пять слоёв Config.Layers (Backyard, Caverns, Ancient Ruins, Cursed Depths, THE VOID) с лутом. ItemDefinitions по глубинам (DepthDefinitions '1'..'5'). p.UnlockedLayers{'1'..'5'}, p.CurrentLayer. Действие 'Layer' {Layer 1..5} захардкожено (Rules.luau:480). Атрибуты CurrentLayer/LayerName/MiningLayer. Глобальные рекорды по глубинам records:1..5. MiningConfig.LayerValue (5 значений). Собаки копают ctx.Depth=min(способность, MaxUnlockedLayer).

**План.** Данные: сопоставить Поверхность→1, Глубина 1→2, Глубина 2→3, Глубина 3→4, Редкие зоны→5. Новых ID нет, миграции нет, экономика та же. Вид участка по глубине берётся из p.CurrentLayer (уже реплицируется атрибутом). Если нужна глубина на каждый кеннель: модуль Features/Mine.luau p.Mine={Version=1, SlotDepth={['DigSlot_1']=n}}, действие 'MineSetDepth' {Slot,Depth} (гейт — свой участок). Rules.Dig и IncomeModel/Offline.Estimate читают одно и то же значение (ctx.Depth=min(SlotDepth, MaxUnlockedLayer)). Если всё же нужны новые слои 6+: только добавлять (C.Layers[6], DepthDefinitions['6'], находки с Depth=6, LootValueScale, LayerValue) и исправить захардкоженные пятёрки (Rules.Action 'Layer', Runtime.ReadNextRecordDepth, Engine.GrantSpecial/SpecialTick '5', ItemRules rareTail, SignatureRules VoidHound, UI). Геометрия шахты — на клиенте и только для своего и ближайших участков; сервер лишь проверяет.

**Файлы.** 
- src/ServerScriptService/Economy/Rules.luau (Dig ctx.Depth, Action 'Layer')
- src/ServerScriptService/Economy/IncomeModel.luau / OfflineEarnings.luau (одна и та же глубина)
- src/ServerScriptService/Economy/Runtime.luau (атрибуты глубины, ReadNextRecordDepth)
- src/ReplicatedStorage/DogEconomy/Config.luau, DepthDefinitions.luau, MiningConfig.luau (при 6+)

**Новые модули.** 
- src/ServerScriptService/Economy/Features/Mine.luau (если глубина на кеннель)

**Совместимость данных.** UnlockedLayers — строковые ключи; номера слоёв не перенумеровывать; новые слои только в конец; p.Mine необязателен (nil означает CurrentLayer).

**Производительность.** Сервер не реплицирует куски шахты (Streaming и клиентская геометрия). Новых DataStore-ключей нет.

**Объём.** L (данные и сеть M)

**Риски.** Расхождение онлайн- и офлайн-дохода, если IncomeModel не читает глубину кеннеля. Ключи рекордов records:<depth>. Prestige сбрасывает CurrentLayer=1, но сохраняет UnlockedLayers. Перенумерация слоёв сломает UnlockedLayers и рекорды.


## Аудитор `economy`

**Сейчас.** The economy already has 5 depths: Config.Layers 1..5 (Backyard 0-10m, Caverns 10-50m, Ancient Ruins 50-150m, Cursed Depths 150-500m, THE VOID 500m+) with per-layer loot tables, DepthDefinitions items per depth, ItemValueConfig.Depth/BaseScale, unlock cost/level/prestige (Rules.Action 'Layer', line 479-486), one p.CurrentLayer for the whole team, mining LayerValue by deepest layer; Bonuses key DepthSpeed is reserved but unused.

**План.** Map the F5 levels one-to-one to the existing layers (Surface=1, Depth 1=2, Depth 2=3, Depth 3=4, Rare zones=5). Keep keys UnlockedLayers['1'..'5'], CurrentLayer and item.Depth. Add a pure ReplicatedStorage/DogEconomy/DepthCatalog.luau that joins Config.Layers (name, depth range, cost, level, color), DepthDefinitions (items), MiningConfig depth data and visual theme ids, so the world builder and UI read 'resources per depth' from one place. Optional per-depth ore mix for the mine: MiningConfig.Depths[L].OreWeight={[OreId]=mult}, used by MiningRules.OreWeights(M,luck,layer) inside RollOre, which already receives the layer. Values use the F11 LayerValue {1,3,6,18,48}. Implement 'Rare zones' as timed rare pockets through the existing e.EventDepth/EventDepthLuck path (ItemRules.ItemChance) or a capped Bonuses source, not as a 6th layer. Use DepthSpeed only for a cosmetic depth-progress meter. Keep the mining anchor named MiningCorner/MiningPad if the mine moves underground (Runtime.Request distance check).

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/MiningConfig.luau`
- src/ReplicatedStorage/Mining/MiningRules.luau (OreWeights/RollOre)
- src/ReplicatedStorage/DogEconomy/Config.luau (layer display names only, keep Name for saves/UI)
- src/ServerScriptService/Economy/Runtime.luau (MiningCorner anchor if relocated)
- tests/mining_rules.luau (per-depth weights)

**Новые модули.** 
- `ReplicatedStorage/DogEconomy/DepthCatalog.luau`

**Совместимость данных.** With 1:1 mapping nothing in saves changes; never renumber layers (UnlockedLayers keys, item.Depth, DepthDefinitions keys, market Depth filter).

**Производительность.** No economy cost; world streaming/chunks belong to the world subsystem. DepthCatalog is a static table.

**Объём.** M (economy side, reusing 5 layers); XL if a 6th economic layer or per-dog depth is required

**Риски.** A real 6th layer touches hardcoded 5s (Rules.luau:480, ItemRules.luau:101-102/111/171, SignatureRules.luau:47, Engine.luau:202, Runtime.luau:275, DiscoveryScreens loops) and all 5-element arrays. Per-dog depth breaks the IncomeModel shape cache keys, SignatureRules.Context and offline estimates. Renaming Config.Layers[*].Name affects UI strings and auto-translation.


## Аудитор `item-models`

**Сейчас.** Находка показывается на DigSlot_N.DarkExcavation.LootSpawn (поверхность). 5 глубин предметов = 5 слоёв Config.Layers (Backyard, Caverns, Ancient Ruins, Cursed Depths, THE VOID). Клиент отбрасывает показ, если yard:FindFirstChild(spawn.Slot) не найден (EconomyVisuals:178).

**План.** Сторона моделей: 1) KennelLootPlacement.Marker ищет LootSpawn уровня шахты, на котором копает собака (атрибут уровня на слоте), с запасным вариантом DarkExcavation. 2) Клиентский показ проверяет YardId и OwnerUserId, а не наличие инстанса слота (чанк уровня может быть выгружен стримингом); если игрок далеко от точки — только тост. 3) Общий модуль ItemModels/DepthPalettes (материалы и цвета глубин) используется и рецептами, и внешним видом уровней шахты. 4) Новые предметы «редких зон» добавляются вместе с рецептами — тест требует рецепт для каждого id.

**Файлы.** 
- `src/ServerScriptService/Economy/KennelLootPlacement.luau`
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- src/ReplicatedStorage/DogEconomy/ItemDefinitions.luau (если новые предметы)
- `src/ReplicatedStorage/DogEconomy/DepthDefinitions.luau`

**Новые модули.** 
- `src/ReplicatedStorage/ItemModels/DepthPalettes.luau`

**Совместимость данных.** Глубина предмета (Depth 1..5) уже хранится; новые зоны добавляются аддитивно.

**Производительность.** Показ остаётся клиентским и не больше 4; FX по бюджету редкости.

**Объём.** M

**Риски.** Нестримящиеся точки показа; камера игрока на поверхности и находка глубоко — нужен вид сверху, тост или маркер. Новые id без рецептов.


## Аудитор `plots`

**Сейчас.** Each kennel pit is DarkExcavation 12x0.4x12 at y≈1. DogKennelService places the dog on the pit top (L120-133). KennelLootPlacement puts LootSpawn at the pit top. PlotAppearance draws DigBorder/FutureGarden around pits (L293-310). The plot subsystem does not use the yard underground.

**План.** Coordinate with the deep-mine owner. Reserve the shaft/elevator footprint in PlotDecorZones. Make the PlotAppearance pit decorations follow the new pit geometry (or move them into the mine module). Keep the DigSlot_n attributes (DigCenter/DigSize/ApproachPosition) as the contract. Showcase/decor must not cover pit areas, and any plot 'mine entrance' building becomes a reserved landmark socket.

**Файлы.** 
- src/ReplicatedStorage/PlotAppearance.luau (pit section)
- `src/ServerScriptService/Economy/KennelLootPlacement.luau`
- src/ReplicatedStorage/PlotDecorZones.luau (new)

**Совместимость данных.** None from the plot side.

**Производительность.** Mine chunks should stream separately; plot decor must not double-draw over shafts.

**Объём.** M

**Риски.** Breaking LootSpawn or dog placement if the pit top changes; MiningCorner clearance.


## Аудитор `ui`

**Сейчас.** Depth UI lives in three places: ServiceMenus Layers (hand-built cards, Layer action), EconomyScreens Layers (Menus) and the Inventory 'Depth' cycle filter. Depth names are hardcoded in DOGROTS_RU_ScreenPatch (CAVERNS, ANCIENT RUINS, CURSED DEPTHS, THE VOID) and in AutoTranslate exact keys. There is no HUD depth indicator apart from the LayerName/CurrentLayer attributes and the EconomyVisuals tint.

**План.** UI side:
- One Kit 'Depths' window: vertical ladder Surface → Depth 1-3 → Rare zones with lock state, cost and level, plus a 'GO DOWN' action. It replaces ServiceMenus Layers and EconomyScreens Layers, routed via services.Layers.
- HUD chip with the current depth icon (attributes CurrentLayer/LayerName).
- Inventory depth filter becomes chips with depth icons and colours (Config.Layers colours).
- Move depth names to Localization modules instead of RU_ScreenPatch.

**Файлы.** 
- `src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_RU_ScreenPatch.client.luau`
- `src/ReplicatedStorage/Localization/*.luau`

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/DepthsScreen.luau`

**Совместимость данных.** Uses the existing p.CurrentLayer/UnlockedLayers; new depths must be additive indices.

**Производительность.** Negligible.

**Объём.** S

**Риски.** Renaming layers breaks RU exact keys; keep layer index keys stable.


## Аудитор `events-nav`

**Сейчас.** Events carry Depth/DepthLuck (BONE_RAIN 1, CRYSTAL_STORM 2, CURSED_FOG 4, BLACKOUT 4, UFO 5) used by ItemRules (def.Depth==e.EventDepth boost). All event FX are surface-oriented:
- ground() raycasts cast from +8..+35 studs down;
- sky spectacle ~480 studs in front;
- client lighting overrides ClockTime/Atmosphere globally.

**План.** 1) Map event Depth to the new mine levels (Surface/D1/D2/D3/Rare) in WorldEventDefinitions so the existing ItemRules boost targets the right level.
2) Add a client 'Zone' attribute (Surface / Mine:<level> / Interior) and an indoor mode for WorldEventFX/Spectacle/Cataclysm/Lighting:
   - skip sky set pieces and rain;
   - render a small local variant (dust, crystals glowing in the mine walls);
   - do not override ClockTime underground.
3) Navigation destination 'Mine entrance' + per-level entrances in the nav graph.

**Файлы.** 
- `src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventFX.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventSpectacle.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventLighting.luau`

**Новые модули.** 
- src/ReplicatedStorage/WorldEvents/WorldEventZones.luau (zone resolver + indoor variants)

**Совместимость данных.** None (Depth numbers are config).

**Производительность.** Fewer objects underground (skip sky), so it improves FPS.

**Объём.** M

**Риски.** Raycasts from above would hit the surface ceiling over the mine. Lighting conflicts with the mine's own lighting system. Coordinate with the digging-depth subsystem.


## Аудитор `tooling-perf`

**Сейчас.** Mining happens on a surface MiningCorner per yard (MiningWorld, PersistentPerPlayer). Ore piles render client-side. DepthDefinitions/Config.Layers exist (economy layers). Constraints: yards sit at Y 0..18 on a floating island whose underside reaches Y -42; DistrictSafety teleports players below Y -85; FallenPartsDestroyHeight=-250. Streaming radius 1024 with default stream-out, so nothing is really unloaded. The global quarry 08_GlobalDigSite (MainDescent, LowerExcavation, AncientSanctuary) exists but all 1,170 parts are hidden with DistrictRefresh_* originals and covered by PitCover.

**План.** Tooling/perf part: (1) Depth geometry as pure chunk layouts (DepthLayout.luau: per level a shaft segment, walls, ore niches, lights; <=400 parts per level). Lune tests check the budget, that every chunk stays inside the yard footprint, Y >= -80 (or a zone-aware DistrictSafety) and that chunk boundaries match. (2) The server builds only collision shells (floors, ramps, walls) per yard, with ModelStreamingMode Atomic per level and PersistentPerPlayer for the owner's current level. Decoration (ore veins, glow, particles, props) is built client-side from the layout only for the level the camera is on ±1, with Perf/Lod and Perf/Pool, in DOGROTS_ClientFX/Depth. This gives real dynamic loading independent of the streaming settings. (3) Dogs working inside levels reuse the DogAnimations culling: dogs on levels the camera is not on are not stepped (extend the visibility test with level occlusion). (4) If deeper than about -80 is required, make DistrictSafety zone-aware (registered mine volumes) as a careful change, with a test. (5) Optionally revive the hidden quarry geometry by restoring the DistrictRefresh_* originals at runtime instead of new parts, if the design wants a shared deep zone.

**Файлы.** 
- src/ServerScriptService/MiningWorld.server.luau (shared placement frame)
- src/ServerScriptService/DistrictSafety.server.luau (zone-aware threshold)
- src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau (level-aware visibility)
- `src/StarterPlayer/StarterPlayerScripts/MiningClient/World.luau`
- src/ServerScriptService/DogKennelService.luau (dog positions per level)

**Новые модули.** 
- `src/ReplicatedStorage/Depth/DepthLayout.luau`
- `src/ServerScriptService/DepthWorld.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/DepthClient.client.luau`
- `src/ReplicatedStorage/World/Builder.luau`
- `tests/depth_layout.luau`

**Совместимость данных.** Depth progress per player is a new field via an Economy feature with Normalize default 'Surface'. Existing p.CurrentLayer/Mining state must map onto levels without loss (old saves start at Surface with current layers still unlocked).

**Производительность.** Server parts per yard: collision shells only (<=120 per level). Client: at most 2 levels decorated at once; chunk build time-sliced through Perf/Scheduler (<=1 ms/frame). No server per-frame motion.

**Объём.** XL

**Риски.** Island underside (Y -42) means shafts would be visible from below unless enclosed or illusory. The DistrictSafety and FallenPartsDestroyHeight limits. 8 yards x levels could exceed the memory budget if the server builds decoration. Streaming settings changes are place-wide.
