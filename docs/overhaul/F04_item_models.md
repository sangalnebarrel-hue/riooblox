# F4. Модели предметов раскопок — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `item-models` (основной)

**Сейчас.** 108 предметов на 60 различных воксельных геометриях (72 id в 24 общих группах: tennis_ball == dead_star == piece_of_the_sun; 10 одинаковых кристаллов; 4 монеты; 4 короны). ReplicatedStorage.DiscoveryModels: 3225 Block Part, Plastic/Neon, CastShadow у всех, 0 MeshPart. При мутации все части становятся Neon (DiscoveryVisuals:9), вид есть только у 4 мутаций. 9 разных путей превью (4 обходят DiscoveryVisuals). Тестов нет. build.py не умеет добавлять Part/Model, поэтому модели можно сделать только процедурно в коде или ассетами владельца.

**План.** 1) Подготовка: ItemValuation.Rarity(def) (экспорт локальной rarityOf), ItemVisualConfig (бюджеты, дистанции LOD, лимиты света и частиц), скелет tests/item_models.luau. 2) ItemModels/Primitives (Box, Ball через SpecialMesh Sphere, Cyl, Wedge, CornerWedge + составные Ring/Arc/Gem/Spike/Coin/Chain, зеркало, роли цвета) и ItemModelFactory: Build(spec,{Lod=Hero|Card|Far, Context=Viewport|World, Fx}) → Model + Bounds; Viewport(); кэш шаблонов (VisualAsset, Lod) без родителя, LRU 64, Clone на использование; мутация на клоне по ролям; FX редкости только в Context=World. Запасной вариант: если у id нет рецепта — нормализованный клон DiscoveryModels с новой мутацией и без теней. 3) DiscoveryVisuals.Clone/Preview делегируют в фабрику (сигнатуры те же); 4 сырых клона переводятся на фасад; Kit.Preview builders.Item/keyers.Item получают Lod (Card по умолчанию, Hero для больших холдеров). 4) Archetypes (Coin, Crystal, Skull, Crown, Egg, Orb, Jar, Blade, Bone, Key, Helmet, Book, Ring, Star, Cube, Statue, Chest, Mask, Tablet, Idol, Portal, Heart, Candle, Device) и Recipes/Depth1..5 для всех 108 id: архетип + параметры + собственные детали с тегами Lod 0/1 + палитра глубины. Шуточные normal_bone и the_cube остаются намеренно простыми, но с Secret-аурой. 5) MutationLooks для 16 ключей (синхронно с Theme.Mutation), RarityFx по таблице бюджетов (Rare: Sparkle; Epic: + PointLight R6; Legendary: орбита + луч; Secret: ForceField-аура), без Highlight, CastShadow только у 1–3 крупных частей. 6) ItemExhibits.client: LOD-менеджер (L0 <35 studs, L1 35–120, L2 120–250, гистерезис, пересчёт 3–4 раза в с, 2 сборки за тик, учёт LowFX и качества графики) и пул RevealRig на 4 слота вместо EconomyVisuals:167-215. 7) ServerStorage/ItemVisualQA: сетка всех предметов по LOD × мутации для арт-ревью в Studio. 8) После приёмки: DiscoveryModels:Destroy() при старте сервера и grep-тест на отсутствие прямых ссылок.

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau`
- `src/ReplicatedStorage/EconomyRewardVisuals.luau`
- `src/ReplicatedStorage/ItemValuation.luau`
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/ServerScriptService/RewardMachinePresentation.server.luau`
- `src/ServerScriptService/Economy/RewardMachineService.luau`
- `src/StarterGui/ScreenGui/Modules/PreviewRenderer.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Preview.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Theme.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/InventoryPage/InventoryController.client.luau`
- `src/StarterGui/ScreenGui/PawpadController.client.luau`
- `src/StarterGui/ScreenGui/MainWindow/Content/PageContainer/YardPage/YardPageController.client.luau`
- `src/StarterGui/ScreenGui/ServiceMenusController.client.luau`
- `src/StarterGui/ScreenGui/Modules/RewardScreens.luau`

**Новые модули.** 
- `src/ReplicatedStorage/ItemModels/ItemModelFactory.luau`
- `src/ReplicatedStorage/ItemModels/Primitives.luau`
- `src/ReplicatedStorage/ItemModels/Archetypes.luau`
- src/ReplicatedStorage/ItemModels/Recipes/Depth1.luau … Depth5.luau
- `src/ReplicatedStorage/ItemModels/MutationLooks.luau`
- `src/ReplicatedStorage/ItemModels/RarityFx.luau`
- `src/ReplicatedStorage/ItemModels/ItemVisualConfig.luau`
- `src/StarterPlayer/StarterPlayerScripts/ItemExhibits.client.luau`
- `src/ServerStorage/ItemVisualQA.luau`
- `tests/item_models.luau`

**Совместимость данных.** Профиль не меняется: визуал зависит только от ItemId/VisualAsset, Mutation, WeightKg/TierIndex. Старые предметы автоматически получают новые модели. Для неизвестных и будущих id есть рецепт MysteryRelic, пока работает запасной вариант с DiscoveryModels. Сигнатурные мутации старых предметов (BURNED и др.) начнут отображаться.

**Производительность.** Сейчас: 3225 постоянных частей у каждого клиента; Collection D5 — 1133 части каждые 5 с; Collector/CreateListing — ViewportFrame на каждую находку (около 6000 частей при 200 предметах). Цель: L0 ≤24/30/40/50/60/70 частей по редкости (huge_statue ≤90), L1 ≤10–20, L2 1–3; глобально на клиент свет ≤4, эмиттеров ≤8, мировых L0 ≤8, L1 ≤32, показов ≤4; кэш по требованию (обычно <600 частей); сборка L0 ~0.3–0.8 мс на ПК и 1–3 мс на слабом телефоне (оценка), по 2 сборки за кадр/тик.

**Объём.** XL

**Риски.** Качество примитивных моделей зависит от арт-ревью каждого из 108 рецептов (самая трудоёмкая часть — L). ViewportFrame не рисует частицы, свет и bloom: в UI редкость передаётся только материалами и средствами UI. Сортировка прозрачности для Glass/ForceField (≤3 прозрачных частей на предмет). Время сборки на слабых телефонах — разносить по кадрам, мерить microprofiler'ом. Лимит 31 Highlight (отказаться от Highlight). Ключ кэша Kit.Preview должен включать Lod. Шуточная одинаковость (normal_bone, the_cube) должна остаться. Серверные потребители (BestFinds, RewardMachinePresentation) требуют фабрику без клиентских API. Удаление DiscoveryModels до полного перевода сломает старые пути.


## Аудитор `economy`

**Сейчас.** Item visuals (DiscoveryVisuals) are separate from valuation; rarity is derived in ItemValuation (local rarityOf by BaseDropChance thresholds in ItemValueConfig.Rarity) and stored on new items as ValueBreakdown.Rarity.

**План.** Export V.Rarity(def) (and a mutation tier) from ItemValuation so F4 LOD/effect tiers, F3 showcase effects and UI colours share one ladder (Common/Uncommon/Rare/Epic/Legendary/Secret + Mutation + WeightTier). No value changes.

**Файлы.** 
- `src/ReplicatedStorage/ItemValuation.luau`

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** None for the economy; do not change ItemValueConfig thresholds for visual reasons (that would reprice every item at sale).


## Аудитор `digging-depth`

**Сейчас.** EconomyVisuals: DiscoveryReveal → клон DiscoveryVisuals на верху DarkExcavation (LootSpawn), одновременно не больше 4, исчезает через 6 с или 14 с, Highlight и BillboardGui.

**План.** После F5 находка появляется на полу уровня (Marker на Floor) и поднимается по шахте к краю (твин около 1.2 с; при ReducedMotion — сразу у края), затем показывается у края с эффектом редкости. Использовать новые оптимизированные модели F4 (LOD: дальше 60 стадов — силуэт или без модели).

**Файлы.** 
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `/home/user/riooblox/src/ServerScriptService/Economy/KennelLootPlacement.luau`

**Совместимость данных.** Протокол DiscoveryReveal не меняется (LootSpawn.CFrame).

**Производительность.** Лимит 4 активные модели сохраняется.

**Объём.** S

**Риски.** Находка внутри узкой шахты не видна — поэтому подъём к краю.


## Аудитор `plots`

**Сейчас.** BEST FINDS exhibits use DiscoveryVisuals.Clone (server, BestFinds L36-54) scaled to fit 4.5x4.9x4.5. Item models average 29 parts (max 105). There is no LOD.

**План.** New F4 models flow into the showcase automatically through DiscoveryVisuals.Clone. Agree on an LOD convention (e.g. children LOD0/LOD1 or a builder flag) so ShowcaseClient/inventory use a low variant beyond ~60 studs. Keep the rarity FX layer (F3) independent of the model. Budget ≤60 parts per showcase exhibit.

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau`
- `src/ServerScriptService/Economy/BestFinds.luau`

**Совместимость данных.** None.

**Производительность.** Bounded by the per-stand budget above.

**Объём.** S

**Риски.** Scale/fit logic assumes bounding boxes of visible parts; new mesh models with transparent helpers must keep Transparency<1 rules consistent.


## Аудитор `ui`

**Сейчас.** Bag and collection previews clone ReplicatedStorage.DiscoveryModels (108 models, 3225 parts) per visible card. InventoryController builds its own ViewportFrame per visible card without a cache; Kit.Preview 'Item' uses DiscoveryVisuals.Clone (mutations recolour parts to Neon).

**План.** UI side:
- The new inventory, showcase and trade screens use only Kit.Preview (cache, 2 per frame, 48-shelf).
- If F4 introduces detailed models with LOD, register an 'Item' builder that picks a lightweight 'menu LOD' variant for cards and the detailed one only for the detail panel.
- Rarity effects in UI as UIGradient border shimmer (Legendary+) and coloured glow, not ParticleEmitters inside ViewportFrames.
- Silhouettes for undiscovered items via the Silhouette flag.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/Kit/Preview.luau`
- `src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau`
- `src/StarterGui/ScreenGui/Modules/Kit/Cards.luau`

**Совместимость данных.** None (ItemId keys unchanged).

**Производительность.** Bounded viewports equal to visible cells; shelf reuse.

**Объём.** S

**Риски.** Heavier models multiply viewport cost on phones; keep a parts budget for the menu LOD.


## Аудитор `tooling-perf`

**Сейчас.** Item models are ReplicatedStorage.DiscoveryModels (108 models, 3,225 parts, max 105 per model) replicated to every client at join. DiscoveryVisuals.Clone clones a model and, for mutations, turns every part Neon. EconomyVisuals clones a fresh model per find (<=4 active, Highlight each, Debris 6-14 s). Kit/Preview caches viewport previews. Meshes cannot be added by the build.

**План.** Tooling/perf part: (1) Procedural item definitions as pure data (ItemModels/<id> part specs with LOD0 <=40 parts, LOD1 <=8 parts, materials from a palette, accent parts tagged for mutation emissive instead of all-Neon). A Lune test checks the per-item budget, determinism and bounding size vs ItemDefinitions.ScaleCap. (2) A runtime builder with an LRU cache keyed ItemId:Mutation:LOD (Perf/Pool per key), used by EconomyVisuals world drops, BestFinds/showcase and Kit/Preview through Preview.Register('Item', ...). (3) World drops go through Perf/Lod: LOD0 <40 studs, LOD1 <120, hidden beyond. Release models to the pool instead of Debris/Destroy. Rarity glow as one emitter plus light within the Quality budget; Highlight only for Legendary+ under the shared Highlight budget. (4) Keep DiscoveryModels as a fallback until all 108 items have procedural specs; later stop replicating DiscoveryModels (lazy).

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/DiscoveryVisuals.luau`
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- src/StarterGui/ScreenGui/Modules/Kit/Preview.luau (Register Item kind)
- `src/StarterGui/ScreenGui/Modules/PreviewRenderer.luau`
- src/ServerScriptService/Economy/BestFinds.luau (server clone path)

**Новые модули.** 
- src/ReplicatedStorage/ItemModels/ItemModelSpecs.luau (+ per-family files)
- `src/ReplicatedStorage/ItemModels/ItemModelBuilder.luau`
- `src/ReplicatedStorage/Perf/Pool.luau`
- `src/ReplicatedStorage/Perf/Lod.luau`
- `tests/item_models.luau`

**Совместимость данных.** Visual only. ItemId/Mutation keys unchanged; items without a new spec fall back to DiscoveryModels.

**Производительность.** Fewer parts per item than today's max of 105. Pooled reuse removes clone churn per find. No all-Neon mutated models (cheaper bloom).

**Объём.** L

**Риски.** Art quality from plain parts has limits. Without MeshParts (owner upload) 'individually detailed' needs careful part design. Server clones for BestFinds must use the same builder (shared module) to stay consistent.
