# F11. Баланс дохода — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `economy` (основной)

**Сейчас.** 'Stone' is the per-yard Mining Corner ore pile (Limestone first, 12 ores in MiningConfig.luau:27-51). Ore value = rand(ValueMin..Max) x LayerValue[deepest unlocked layer] {1,3,6,12,24} (MiningRules.RollOre:102), paid per hit via R.Credit and outside the Bonuses pipeline and IncomeModel. Pickaxes 600 / 7.5K / 45K / 260K / 1.6M / 12M (Inferno) / 85M (Voidbreaker). Simulated mining with the stage pickaxe is 40-49% of dog income at L2-L3, 16% at L4 and 12-20% at L5 without the tree, and 1-3% with the full tree (dog income 1.1K->7.74M/min old upgrades, 32.6K->71.3M/min full tree, measured with Rules.IncomeModel). Voidbreaker = about 10 min of a Secret VOID team's income without the tree and 1.2 min with it.

**План.** Phase 1 (data only): in MiningConfig.luau multiply every ore ValueMin/ValueMax by 2 (Limestone 80-110 ... Void Crystal 24K-32K); LayerValue -> {1,3,6,18,48}, which doubles as the F5 per-depth multiplier: Surface 1, Depth1 3, Depth2 6, Depth3 18, Rare 48. Prices: Crystal 4,000,000; Inferno 60,000,000; Voidbreaker 600,000,000; Crystal Weight 1,500,000; Inferno Core 20,000,000; Void Mass 120,000,000; keep Wooden 600 (hardcoded in onboarding text), Stone, Iron, Steel and the first weights. Expected result (simulator, skill 0.6): stage pickaxe vs dogs = L1 4.4K/min (66% of a 5-Common team), L2 29.6K (79%), L3 119K (97%), L4 558K (48%), L5 3.6M (47-80%). Payback: Inferno = 35 min of total income at L4, 6.5 min at L5; Voidbreaker = 58 min at L5 without the tree, 8.4 min with the full tree, about 10 h by mining alone. Bump Config.BalanceVersion; update docs/MINING.md section 3, add an F11 section to docs/ECONOMY.md, fix the reference line in tools/balance_sim.py. Phase 2 (optional): Bonuses key MiningValue, applied as ctx.ValueMult in R.MiningAction -> MiningRules.RollOre and fixed into OreValue at roll. Sources: a new UpgradeTree branch 'MINING' (about +4%/+6%/+10% per level x10, capstone +25% x5, total +3.25) and accessories with Stat='MiningValue'. With phase 2, Voidbreaker can go to 1-1.5B (late-game mining becomes about 21% of full-tree dog income).

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/MiningConfig.luau`
- src/ReplicatedStorage/DogEconomy/Config.luau (BalanceVersion)
- `docs/MINING.md`
- `docs/ECONOMY.md`
- `tools/balance_sim.py`
- phase 2: src/ReplicatedStorage/DogEconomy/Bonuses.luau (Keys), src/ReplicatedStorage/DogEconomy/UpgradeTree.luau (Stats + MINING branch), src/ServerScriptService/Economy/Rules.luau (R.MiningAction ctx), src/ReplicatedStorage/Mining/MiningRules.luau (RollOre value mult), src/ReplicatedStorage/DogEconomy/EquipmentDefinitions.luau, tests/income.luau, tests/upgrade_tree.luau, docs/UPGRADE_TREE.md

**Новые модули.** 
- (phase 2 only) ReplicatedStorage/DogEconomy/BonusSources entries reuse existing modules; no new module needed for phase 1

**Совместимость данных.** No migration: p.Mining stores owned indices (PickaxeOwned/WeightOwned); the current pile keeps its saved OreValue until broken; MiningConfig.Version stays 2; IncomeModel/BoostPricing/Robux packs/offline unaffected (mining is not in them); leaderboard TotalCoinsEarned grows faster.

**Производительность.** Zero runtime cost: same code paths, only numbers change. Phase 2 adds one Bonuses.Global call per ore roll (not per hit), well under 0.1 ms.

**Объём.** S (phase 1) / M (phase 2)

**Риски.** Players saving for Inferno/Voidbreaker see prices jump x5-x7: needs a patch note; owners keep their pickaxes and there is no refund problem. Better mining makes macros more attractive, but ore throughput is capped by the server-issued circles, BreakPause 1.4 s and RespawnDelay (about 30 ores/min with Voidbreaker), so a perfect bot gains only about 10-20% over a skilled player. Early game speeds up (4.4K/min at L1 against a 3.5K Common dog), but level/XP gates stay the binding constraint. If 'stone' was meant as dogs' ordinary loot, the lever would be C.LootValueScale, which moves all dog income and every income-following price: not recommended.


## Аудитор `data-network`

**Сейчас.** MiningConfig: Ores ValueMin/Max (Limestone 40–55, …, VoidCrystal 12k–16k), LayerValue {1,3,6,12,24}, Pickaxes по позиции (Wooden 600, Stone 7,5k, Iron 45k, Steel 260k, Crystal 1,6M, Inferno 12M, Voidbreaker 85M). p.Mining хранит PickaxeOwned/Level как позиции в массиве и OreValue текущей руды (заморожено). C.BalanceVersion='2026-10-11.MINING_V2'. Лут собак — Config.Layers + LootValueScale.

**План.** Для данных достаточно конфига: поднять ValueMin/Max (особенно ранние руды и Limestone) и/или LayerValue; цены Crystal/Inferno/Voidbreaker умножить в N раз. Порядок массива Pickaxes не менять, новые — только в конец: PickaxeOwned — позиция, иначе изменится то, чем игроки владеют. Миграция текущей руды: MiningRules.Normalize v2→v3 — если m.Version<3, пересчитать m.OreValue на коэффициент новая_середина/старая_середина её руды (идемпотентно по версии), затем Version=3. Купленные кирки не трогать (ни возвратов, ни списаний). Поднять C.BalanceVersion. Обновить tools/balance_sim.py, tests/mining_rules.luau и UI магазина (читает тот же конфиг).

**Файлы.** 
- `src/ReplicatedStorage/DogEconomy/MiningConfig.luau`
- src/ReplicatedStorage/Mining/MiningRules.luau (миграция v3)
- src/ReplicatedStorage/DogEconomy/Config.luau (BalanceVersion)
- `tests/mining_rules.luau`
- `tools/balance_sim.py`

**Совместимость данных.** Только Mining.Version (v3). Массивы только дополняются. Остальное сохранённое не меняется.

**Производительность.** Нет.

**Объём.** S (данные) / M (с симуляцией баланса)

**Риски.** Игроки, копящие на топовую кирку, теряют прогресс по цене — нужна коммуникация. Связка с BoostPricing.LayerScale и наборами монет за Robux. Если LayerValue меняется, а OreValue не мигрирован, у текущей руды до разрушения будет старая цена (некритично).


## Аудитор `digging-depth`

**Сейчас.** Активная добыча: MiningConfig.Ores (Известняк 40–55 … Кристалл Пустоты 12 000–16 000) × LayerValue {1,3,6,12,24} по самому глубокому открытому слою (MiningRules.RollOre, ctx.Layer=R.MaxUnlockedLayer). HitShare .35, CoinBonus по кирке. Цены кирок: 600 / 7 500 / 45 000 / 260 000 / 1 600 000 / 12 000 000 / 85 000 000. Ценность текущей руды фиксируется при её броске и сохраняется в p.Mining.OreValue.

**План.** (1) «Камень на участке» — это руда MiningCorner. Поднять ValueMin/ValueMax у частых руд (Limestone, Coal, Copper — ранний ресурс) и/или LayerValue, чтобы на глубине стоимость росла сильнее. Конкретные числа согласовать с владельцем экономики через tools/balance_sim.py: ориентир — активная добыча около 0.6–1× дохода собак на каждой стадии (docs/MINING.md).
(2) Топ-кирки: Price у Crystal, Inferno и Voidbreaker (индексы 5–7) поднять в несколько раз (например ×3–5), сохранив монотонность. tests/mining_rules проверяет рост цен и Wooden=600 на шаге 7 обучения — не трогать первую.
(3) Обновить таблицы в docs/MINING.md и вывод balance_sim.
(4) Опционально, в связке с F5: пул руды по глубине (веса Ores смещаются по CurrentLayer). Только после симуляции.

**Файлы.** 
- `/home/user/riooblox/src/ReplicatedStorage/DogEconomy/MiningConfig.luau`
- `/home/user/riooblox/tools/balance_sim.py`
- `/home/user/riooblox/tests/mining_rules.luau`
- `/home/user/riooblox/docs/MINING.md`
- `/home/user/riooblox/src/ReplicatedStorage/Mining/MiningText.luau`

**Совместимость данных.** PickaxeOwned/PickaxeLevel/WeightOwned — индексы, на них цены не влияют. Сохранённая OreValue текущей руды остаётся до разлома; новая ценность — со следующей руды. При желании одноразово пересчитать через новое поле m.ValueVersion в MiningRules.Normalize. MiningConfig.Version можно поднять до 3 только при изменении схемы.

**Производительность.** Нет влияния.

**Объём.** S (конфиг) + M (симуляция, документация, тесты)

**Риски.** Удешевление или перекос относительно дохода собак; цены в UI магазина берутся из конфига (Shop.luau). Игроки, купившие топ-кирки по старой цене, сохраняют их (PickaxeOwned — индекс). Текущая руда держит старую OreValue до разлома.


## Аудитор `item-models`

**Сейчас.** Цена находки: ItemValuation.Price (ItemValueConfig.Version=6). BulkSell пересчитывает цену вживую (YardCommerce:55), а x.SellValue замораживается при минте и используется в BestFinds.Select, RecordStats, сортировке 'Value' в DiscoveryScreens и в оценке трейда (Engine:301).

**План.** При ребалансе поднять ItemValueConfig.Version. В UI, витрине и трейде показывать живую цену ItemValuation.Price вместо x.SellValue (как CollectorScreen). Витрину F3 ранжировать по редкости, а не по SellValue. Фабрика от цены не зависит.

**Файлы.** 
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/StarterGui/ScreenGui/Modules/DiscoveryScreens.luau`
- `src/ServerScriptService/Economy/Engine.luau`

**Совместимость данных.** SellValue на старых предметах можно не трогать — продажа и так считает вживую.

**Производительность.** Нет.

**Объём.** S

**Риски.** Расхождение показанной и выплаченной цены у старых предметов.


## Аудитор `plots`

**Сейчас.** Plot economy: stage cost 8k-3.17M (Config.Upgrades.Plot), +2.5% dug value per stage; skin prices 6k-500k (x5 at load, PlotCatalog L33).

**План.** After the stone/pickaxe rebalance, re-check skin and decor price bands against the new income curves (tools/balance_sim.py) and move prices into explicit catalog values. Prices are not stored in profiles, so changing them needs no migration.

**Файлы.** 
- `src/ReplicatedStorage/PlotCatalog.luau`
- src/ReplicatedStorage/DecorCatalog.luau (new)

**Совместимость данных.** None (owned flags only).

**Производительность.** None.

**Объём.** S

**Риски.** Players who bought at old prices are unaffected; the upgrade_tree test asserts that the PlotCatalog.Cost formula matches.


## Аудитор `lab`

**Сейчас.** Reroll costs 5000+1500*rank coins and 5*rank bones (6.5k..14k), negligible for rare dogs; variant income bonuses Shiny 12%..Void 110% (Config.Variants) feed Rules.Bonus and shelter prices.

**План.** Make the reroll price part of the rebalance: LabConfig.Reroll {Share, Floor[rank]} with G.RerollCost = max(Floor, BasePrice*Share) (proposal Share .04 -> 5k/7k/9k/36k/260k/2.2M); keep variant bonuses and odds unchanged (saved data); run tools/balance_sim.py to check payback (Golden Secret ~44M ~1.5 h of top income) and absence of shelter arbitrage (expected Void cost ~20x BasePrice vs +0.275x shelter value).

**Файлы.** 
- `src/ReplicatedStorage/LabConfig.luau`
- `src/ReplicatedStorage/LabGenetics.luau`
- `tools/balance_sim.py`
- `docs/ECONOMY.md`
- `docs/LAB.md`

**Совместимость данных.** No saved data affected (price is computed).

**Производительность.** None.

**Объём.** S

**Риски.** Players used to 14k-coin Secret rerolls will see a big price jump; communicate in-game. If F11 raises stone value and income, Share may need retuning.


## Аудитор `ui`

**Сейчас.** Prices on screens mostly come from config (MiningClient/Shop reads M.Pickaxes Price/Strength; equipment and upgrades read their definitions). Hardcoded copies exist in OnboardingGuide cards 7 and 9 ('Wooden Pickaxe (600 Coins)', '7 pickaxes, 7 weights, 12 ores') with matching exact Russian keys in DOGROTS_AutoTranslateUI (lines 149, 156). The wallet shows full digits (PriceFormat.Number) and MoneyController widens the label.

**План.** Generate onboarding texts from MiningConfig with string.format and add pattern-based RU entries (Localization module patterns) instead of exact keys. Check that very large prices fit buttons (use Kit.Format.Short on chips, full digits on confirm dialogs). No UI logic change beyond that.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau`
- `src/ReplicatedStorage/Localization/Core.luau`

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** A silent RU translation regression if only the English text changes.


## Аудитор `trade-titles`

**Сейчас.** Trade 'Estimated' value uses stored item SellValue (frozen at find, ItemRules:195) and dog LinePrice/BasePrice; Milo sells at live ItemValuation.Price (YardCommerce:56). Cash trading is unlimited.

**План.** Trade value display must use the same live server valuation as sales (ItemValuation.Price after rebalance; dog catalog x variant), so the rebalance does not make trade estimates disagree with Milo prices. Re-check Cash cap/tax decisions after income rises (bigger cash gifts between alts).

**Файлы.** 
- `src/ReplicatedStorage/ItemValuation.luau`

**Новые модули.** 
- `src/ReplicatedStorage/TradeValue.luau`

**Совместимость данных.** Do not rewrite stored SellValue on items; compute live.

**Производительность.** Valuation per offered asset only (<=12 per side).

**Объём.** S

**Риски.** Players may treat the estimate as a guarantee; label it clearly.


## Аудитор `events-nav`

**Сейчас.** End rewards are income-relative (BoostPricing.Coins: max(MinCash x LayerScale[deepest], IncomeMinutes x team rate)), so they follow any income rebalance automatically. Pickup rewards are flat Cash=40/Bones=2 (WorldEventConfig.Interactions). Event GameplayModifiers (DigSpeed, SellValue, Luck...) multiply the dig economy through Modifiers.Resolve with ModifierCaps.

**План.** After the stone/pickaxe rebalance:
- re-check MinCash floors per event rarity;
- switch pickup Cash to Pricing.Coins({MinCash=40,IncomeMinutes=0.25});
- size Rush catch and pass rewards in income-minutes, not absolute coins;
- verify with tools/balance_sim.py that events stay a bonus (<~5-10% of hourly income).

**Файлы.** 
- `src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau`
- src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau (Reward rows)
- src/ServerScriptService/WorldEventService.luau (Interact reward)

**Совместимость данных.** No data change.

**Производительность.** None.

**Объём.** S

**Риски.** Too-generous Rush rewards could become an AFK or exploit farm. Keep them tied to verified catches with caps.


## Аудитор `tooling-perf`

**Сейчас.** tools/balance_sim.py simulates mining from MiningConfig (12 ores Limestone..VoidCrystal, 7 pickaxes Wooden 600 .. Voidbreaker 85,000,000, LayerValue={1,3,6,12,24}) and prints coins/min per pickaxe x layer (e.g. Voidbreaker L5 about 972k/min); no payback column. tests/mining_rules.luau covers the rules; Config.BalanceVersion is printed at server start.

**План.** Tooling part: (1) Extend balance_sim.py with a payback table (price / coins-per-min at the layer where the pickaxe is typically bought), a --price-scale / --ore-scale scenario flag and a comparison against the dog income references already printed (L1..L5). Keep the 'local M={...}\n' format of MiningConfig, which the regex parser needs. (2) Add assertions to tests/mining_rules.luau or a new tests/balance.luau: top-tier pickaxe prices >= N x the previous values (the owner's 'several times'), monotonic price/benefit, early ore value increase preserves the tutorial step (Wooden 600 affordable in the onboarding window). (3) Bump Config.BalanceVersion and document the tables in docs/MINING.md / docs/ECONOMY.md (Russian), as stage docs do.

**Файлы.** 
- `tools/balance_sim.py`
- `src/ReplicatedStorage/DogEconomy/MiningConfig.luau`
- src/ReplicatedStorage/DogEconomy/Config.luau (BalanceVersion)
- `tests/mining_rules.luau`
- `docs/MINING.md`
- `docs/ECONOMY.md`

**Новые модули.** 
- `tests/balance.luau`

**Совместимость данных.** Players who already own top pickaxes keep them (prices only affect future purchases). Ore value changes apply to new hits only; no saved values to migrate.

**Производительность.** None.

**Объём.** S

**Риски.** The simulator's regex parser breaks if MiningConfig's table layout changes. Dog income and offline earnings references must be re-run through the economy simulators that live outside the repo (scratch) — bring them into tools/ so they are versioned.
