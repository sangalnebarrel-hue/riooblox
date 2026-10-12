# F12. Ядерная мутационная машина (лаборатория) — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `lab` (основной)

**Сейчас.** 5-procedure kit window (Mutation, Targeting, Extraction, Ascend, Recipes) via LabInfo/LabPreview/LabCommit at a 7.5-stud GeneticsTerminal prompt; local-only 5.5 s camera cinematic around a 31-stud capsule (CentralChamber) inside a building whose interior is only Y1..33; reroll odds = Rules.VariantRows (Config.Variants + world event + DogMutation); flat reroll price; no world event for other players.

**План.** (1) SERVER: new LabRules.Reroll(p,a,now,random,token) + LabService 'LabReroll' {DogUid, Token, Cost, Acknowledge?} dispatched from Runtime.luau:385. Outside Tx: LabAccess.CanUse, no trade, RAM S.Busy[userId], cooldown l.LastAt (3-4 s). Inside rt.Tx:Run({'p:'..uid}): R.Normalize, replay by Token from l.History, d=L.Dog (G.Check), cost=G.RerollCost(d) with R.Check(a.Cost==cost,'Price changed'), free if not l.TutorialComplete, ack required if Variant~='Normal', R.Pay, roll on R.VariantRows(p,now) (identical odds to today), d.Variant=new + R.Discover, l.LastAt/Experiments/new l.Rerolls, slim History row {Procedure='Reroll',From,To,Cost}, FirstDiscoveries['MUTATION:x'], State.Validate+R.Validate. Return {Token, Dog, From, To, Cost, Chances, Show={StartAt,Duration}}; after commit fire LabMutationShow (never affects the result). Fix the PaidDNA taint. (2) PRICE: LabConfig.Reroll={Share=.04, Floor={5000,7000,9000,0,0,0}, Cooldown, FreeFirst}; G.RerollCost=max(Floor[rank], BasePrice*Share) -> 5k/7k/9k/36k/260k/2.2M coins, coins only; simulate with tools/balance_sim.py together with F11. (3) RETIRE: LabConfig.Procedures Enabled=false for Targeting/Extraction/Creation (+recipe Fusion), LabRules.Preview refuses them; keep LabConfig.DNA keys; LabState.Normalize v2 migration: l.LegacyDNA=copy(l.DNA), grant l.RerollCredits (or coins via R.Credit(p,n,false) capped by MaxCash), l.Version=2, idempotent; keep Recipes/History/FirstDiscoveries/TutorialComplete; lab-made dogs and catalyst items untouched (catalysts are normal sellable finds); no pending jobs exist. ASCEND kept server-side as a contextual button (owner decision). (4) WORLD: ServerScriptService/Economy/LabReactorWorld.luau (runtime builder, idempotent Install/Validate, LAYOUT_VERSION, LabReactor_* attributes for reversible hides) called in World.Start before LabService.Start; blueprint constants in ReplicatedStorage/LabReactorConfig.luau. Tube centred (134,477) where CentralChamber stands: base flange r15 Y2.3..5 with lift hatch, glass shell r12 in 3 cylinder sections to Y~90, inner liquid cylinder (Neon/ForceField), 8 metal rings, 6 ribs, electrodes, crown Y88..98 with beacon; anchors CameraHooks{ConsoleView,Low,Orbit,Sky}, LiftStart(Y3), LiftTop(Y16-20), TubeCenter, AudioAnchor, CrownBeam; ModelStreamingMode Atomic, ~150-250 anchored parts, CastShadow off for glass/neon. Hide CentralChamber, replace CentralSkylight by 4 panels around a r14 collar, cut StructuralCrossBeam X=122/144, LanternBeam Z=477, LanternCrossbar X=127/142, part of CrossRoof; move LocationLabelAnchor above the crown; relabel old stations. Console X106..118 x Z465..489 facing -X with SurfaceGui screens; move InteractionAnchor to ~(112,6,477), LabAccess.Distance ~10, prompt 'ACTIVATE / MUTATION MACHINE'. Tag reactor lights/emitters with a WorldDetailQuality exemption attribute. (5) UI: rewrite LabScreen internals into a one-screen console menu (dog grid with G.Fix one-tap fixes, big preview, variant + income bonus, odds bar, price pill, hold-MUTATE, FREE badge, result card with big AGAIN) keeping the Open/Close/Build/ShowResult/SetView API. (6) CINEMATIC: new Modules/LabCinematic.luau (LabPresentation API kept): starts on press (optimistic lift/charge), reply arrives mid-lift, abort cleanly on refusal; ~8 s timeline lift -> charge (liquid rise, 6 pooled energy rings, Beam bolts, slow orbit + tilt through skylight) -> white flash/Bloom spike/:Emit bursts -> colour change to the new variant via a shared VariantVisuals module, shockwave, crown sky beam, rarity-tiered intensity (Void darkest) -> lower dog -> result card; skippable after ~1.5 s; FX pooled in workspace.LocalLabFX (outside the district); LowFX/ReducedMotion/mobile: ~3 s, no orbit, emitters x0.3, FOV<=70, safe-area skip button; UI hidden via N.BeginReward. (7) OTHERS: LabMutationShow to players within ~200 studs, server queue like RewardMachinePresentation (queue.Tail; >6 s wait -> short pulse), nearby clients (StarterPlayerScripts/LabReactorFX.client.luau) show dog clone in tube, liquid colour, flash, crown beam and 'Player X: VOID!' on the console screen without camera changes; owner ignores its own public copy by Token; idle reactor animated client-side at 10-15 Hz only within 150 studs. (8) TESTS: extend tests/lab.luau (odds parity, price curve, price-change refusal, ack, Token replay, dog set unchanged, cooldown, retired procedures refused, v2 migration idempotent + legacy DNA validates, PaidRandom fix) and add tests/lab_reactor.luau for blueprint bounds/prompt in InteriorZone/tube height.

**Файлы.** 
- `src/ServerScriptService/Economy/LabService.luau`
- `src/ServerScriptService/Economy/LabRules.luau`
- `src/ServerScriptService/Economy/LabState.luau`
- `src/ServerScriptService/Economy/Runtime.luau`
- `src/ServerScriptService/Economy/World.luau`
- `src/ReplicatedStorage/LabConfig.luau`
- `src/ReplicatedStorage/LabGenetics.luau`
- `src/ReplicatedStorage/LabAccess.luau`
- `src/ReplicatedStorage/LabAudioConfig.luau`
- `src/ReplicatedStorage/Localization/Lab.luau`
- `src/ReplicatedStorage/WorldSignConfig/LocationLabels.luau`
- `src/StarterGui/ScreenGui/Modules/LabScreen.luau`
- `src/StarterGui/ScreenGui/Modules/LabPresentation.luau`
- `src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldDetailQuality.client.luau`
- `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau`
- `src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau`
- `src/ReplicatedStorage/MapRouting.luau`
- `src/StarterGui/ScreenGui/PawpadController.client.luau`
- `tests/lab.luau`
- `docs/LAB.md`

**Новые модули.** 
- src/ServerScriptService/Economy/LabReactorWorld.luau (runtime reactor/console builder, Install/Validate, LAYOUT_VERSION)
- src/ReplicatedStorage/LabReactorConfig.luau (blueprint constants, anchor names, FX budgets, timings)
- src/StarterGui/ScreenGui/Modules/LabCinematic.luau (pooled timeline cinematic; LabPresentation becomes a shim)
- src/StarterPlayer/StarterPlayerScripts/LabReactorFX.client.luau (idle reactor FX + public LabMutationShow handler)
- src/ReplicatedStorage/DogEconomy/VariantVisuals.luau (single variant colour/FX source)
- tests/lab_reactor.luau (blueprint geometry checks)
- RemoteEvent ReplicatedStorage.LabMutationShow (created in LabService.Start)

**Совместимость данных.** p.Lab keeps every existing field; new fields: p.Lab.Version=2, p.Lab.Rerolls, p.Lab.RerollCredits (or one-time coin credit), p.Lab.LegacyDNA (snapshot). p.Lab.DNA left in place and LabConfig.DNA keys kept so LabState.Validate passes. History rows gain Procedure='Reroll' (old rows untouched; the client must tolerate unknown procedures). Dog records change only Variant (as today). Lab-made dogs, catalysts and stabilizers need no migration; there are no pending lab jobs.

**Производительность.** Server: one profile Tx per reroll, no server animation; send a small StatePatch instead of a full StateSnapshot; skip Refresh for LabInfo. Network: LabMutationShow ~150 B at most once per 4 s per player, distance-filtered. Client: ~150-250 anchored reactor parts (Atomic streaming), FX pooled (6 rings, few Beams, pre-made emitters with :Emit), per-frame work only during a show; idle animation 10-15 Hz within 150 studs; LowFX/mobile budgets.

**Объём.** XL

**Риски.** Old saves: removing LabConfig.DNA keys bricks transactions (keep them); migration must be idempotent and must not overflow MaxCash. Economy: a new price curve changes the late-game sink (needs simulation with F11). The tube through the roof needs precise reversible cuts of roof and ceiling parts and moving the location label; streaming: the reactor may not be loaded (fallback to a UI-only reveal). WorldDetailQuality can throttle reactor emitters/lights unless exempted. Public shows can overlap (queue needed). Owner decisions: DNA conversion target, ASCEND placement, Share value, roof-through vs east-court variant.


## Аудитор `data-network`

**Сейчас.** LabService: LabInfo/LabPreview/LabCommit с котировкой Token (120 с), Signature, Acknowledge для ценных, кулдаун 7 с, гейт LabAccess (05_MutationLab InteractionAnchor, Distance 7,5), блокируется TradeByUser. LabRules: Mutation/Targeting/Extraction/Fusion/Ascend/Creation. p.Lab{Version=1, DNA, DiscoveredDNA, Recipes, History≤40, FirstDiscoveries, Experiments, Tier, LastAt, TutorialComplete, PaidDNA}. LabState.Validate требует C.DNA[k]. dog.Variant — имя мутации (сохранённые данные).

**План.** Протокол оставить, сузить до одной процедуры. 'LabRerollQuote' {DogUid} → {Token, Cost{Cash,Bones} (по LabConfig.Costs.Mutation и рангу), Odds=R.VariantRows(p), Expires}. 'LabReroll' {Token, Confirm=true, Acknowledge?} → одна RAM-транзакция: Pay, бросок варианта, R.Discover, History, LastAt; ответ {Dog, From, To, Duration} для анимации (сервер сначала решает, клиент потом показывает). Вещание зрелища соседям — runtime-RemoteEvent 'LabShow' {UserId, DogId, From, To} (S→All рядом с лабораторией) или серверный механизм-модель. Прочие процедуры выключить на сервере (R.Check Procedure=='Mutation' в LabService), код и историю сохранить. Ключи LabConfig.DNA не удалять (LabState.Validate запрёт владельцев). Если владелец хочет убрать DNA: миграция Lab.Version 1→2 в LabState.Normalize — начислить Cash/Bones по курсу, обнулить l.DNA, затем можно перестать показывать. Гейт консоли: перенести якорь LabAccess.Model() на новую консоль.

**Файлы.** 
- `src/ServerScriptService/Economy/LabService.luau`
- `src/ServerScriptService/Economy/LabRules.luau`
- src/ServerScriptService/Economy/LabState.luau (необязательная миграция DNA v2)
- src/ReplicatedStorage/LabConfig.luau (Cooldown ≥ длительности анимации)
- src/ReplicatedStorage/LabAccess.luau (якорь консоли)
- src/ServerScriptService/Economy/Runtime.luau (ветки Lab*, стоимость)

**Новые модули.** 
- runtime-RemoteEvent 'LabShow' (в общем модуле remotes)
- клиентский MutationMachine (VFX, пул)
- tests/lab.luau (дополнить проверкой reroll и миграцией DNA)

**Совместимость данных.** Формат p.Lab тот же. Записи History старых процедур остаются читаемыми. Имена Variant не переименовывать. Необязательная миграция DNA v2 идемпотентна.

**Производительность.** Только RAM-транзакция. Анимация на клиенте. Вещание редкое, только ближайшим.

**Объём.** M (данные и сеть) / L с VFX

**Риски.** Удаление DNA-ключей или процедур из LabConfig без миграции приводит к отказу Validate и кику. Котировка устаревает во время анимации. Двойное нажатие спасают Token и квитанция. PaidRandom должен наследоваться (lab-результат получает PaidRandom входа).


## Аудитор `economy`

**Сейчас.** Lab reroll ('Mutation'): cost = LabConfig.Costs.Mutation {Cash=5000, RankCash=1500, RankBones=5} through LabGenetics.Cost (6.5K..14K Cash, 5..30 Bones). The first reroll is free (TutorialComplete). Odds = R.VariantRows(p) (conveyor variant table, Normal 77% / Void 0.2%, plus the GOOD GENES DogMutation bonus) with stability/targeting (G.Chances). The result can downgrade the dog. Late game the coin part is negligible (14K against 7.7M-71M/min income); bones are the real limiter. Variant bonus Shiny .12 ... Void 1.10 multiplies dog loot (R.Bonus).

**План.** Add a pure ReplicatedStorage/DogEconomy/LabPricing.luau: Reroll(p,d,now) = BoostPricing.Round(max(Floor[rank] x LayerScale[deepest], Minutes[rank] x BoostPricing.Rate(p,now) x 60 / 5)), with Floor = {6500,8000,9500,11000,12500,14000} (current prices, so early game is unchanged) and Minutes = {0.5,0.75,1,1.5,2,3} minutes of an average working dog's income. Use the peak-tracked rate so benching dogs does not lower the price. Results: Common L1 6.5K (as today); Secret VOID without the tree about 4.6M; with the full tree about 43M; about 20 rolls on average for Golden, about 500 for Void (a chase sink). LabPreview returns the quote and LabCommit charges at most quote x1.05 (Rules.quoted pattern). One currency (Cash) as the owner asked: drop RankBones, or keep it as a deliberate decision. Define 'new mutation' semantics explicitly: if the current variant is excluded, a Normal dog always mutates (+22% expected loot), so price it about x1.5 or keep Normal in the pool. Hide Extraction/Targeting/Fusion/Creation in the UI but keep the server paths for existing DNA, or convert DNA once with a versioned LabState migration.

**Файлы.** 
- `src/ReplicatedStorage/LabConfig.luau`
- src/ReplicatedStorage/LabGenetics.luau (G.Cost delegates to LabPricing)
- src/ServerScriptService/Economy/LabRules.luau (Preview quote / Apply charge)
- src/ServerScriptService/Economy/LabState.luau (DNA conversion migration if menus are removed)
- tests/lab.luau (lines 199-209, 325, 416 pin current costs)
- `docs/LAB.md`

**Новые модули.** 
- `ReplicatedStorage/DogEconomy/LabPricing.luau`

**Совместимость данных.** Variant names are saved data (VariantDex, trades, market): never rename. Existing p.Lab DNA/Recipes must stay valid or be converted idempotently; LabConfig.Version bump if the quote format changes.

**Производительность.** One BoostPricing.Rate read per preview; negligible.

**Объём.** S-M

**Риски.** An income-linked price makes rerolls feel expensive to high earners, so tune Minutes against the 'press again' goal (the animation length, 7 s cooldown + 5.5 s, already bounds spend rate). Changing reroll semantics changes variant inflation (Void dogs +110% income). PaidRandom propagation must stay for paid DNA.


## Аудитор `item-models`

**Сейчас.** Лаборатория расходует находки: LabRecipeConfig.RequiredItems (golden_scarab, glitched_coin, void_fragment) и катализаторы/стабилизаторы LabGenetics (C.Affinities/C.Stabilizers по ItemId). В LabScreen находки показываются только текстом.

**План.** Если новая машина убирает предметы из лаборатории, визуальной части менять нечего. Нужно учесть, что исчезает расход находок (вопрос экономики), а мутации собак визуально не связаны с MutationLooks предметов — палитры держать раздельно.

**Файлы.** 
- `src/ServerScriptService/Economy/LabRecipeConfig.luau`
- `src/ReplicatedStorage/LabGenetics.luau`

**Совместимость данных.** Не затрагивает p.Items.

**Производительность.** Нет.

**Объём.** S

**Риски.** Сохранённые состояния лаборатории со ссылками на ItemUid катализаторов.


## Аудитор `plots`

**Сейчас.** DisplayDogs dogs are excluded from the lab (LabGenetics L42) and the shelter (ShelterRules L10). Display dogs and the BEST FINDS dog are tinted by Variant with duplicated tables (PlotShowcase L28-29, BestFinds L49-52). The lab consumes items through I.Get(transfer) (LabRules L40, L217).

**План.** The F3 hook automatically blocks consuming showcased items. If F12 changes how mutations are represented (field or visuals), update the display dog tint (shared display-model util) so plots show the new mutation look, and keep the DisplayDogs exclusion in the new machine.

**Файлы.** 
- `src/ServerScriptService/Economy/PlotShowcase.luau`
- `src/ServerScriptService/Economy/BestFinds.luau`
- `src/ReplicatedStorage/LabGenetics.luau`

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** A mutation reroll on a displayed dog changes its Variant token: the existing reconcile handles re-cloning.


## Аудитор `ui`

**Сейчас.** LabScreen is a 1869-line Kit window with steps: species grid → dog → action (mutation, gene targeting, DNA extraction, fusion/ascend, experimental recipes) → recipe and catalyst picker (LabPicker stacked window) → result card (AGAIN / NEW EXPERIMENT), plus a DNA bank. Outside the terminal it shows a splash with SHOW THE WAY. It is opened by GeneticsPrompt (LabPrompt.client controls Enabled) and the HUD LAB tile via GUIIntegration openLab(). The world cinematic is in LabPresentation (cues from LabAudioConfig). RU_ScreenPatch carries lab procedure names.

**План.** UI side of the new mutation machine:
- New MutatorScreen (Kit Window Key='Lab' so existing routes and OpenMenu checks keep working) opened by an ACTIVATE prompt on the console.
- Step 1: dog carousel or CardGrid with the current variant/mutation tag.
- Step 2: a big cost card (currency icon, reroll cost, odds table collapsed behind 'chances').
- Step 3: one giant MUTATE button (hold 0.5 s on first use).
- On press the window collapses to a minimal bottom bar (SKIP) while the world cinematic plays; then a result card shows old → new mutation, a rarity flash and a prominent 'AGAIN · cost'.
- Reuse LabAudioConfig cues and the Kit.Motion reduced-motion path.
- Keep LabScreen code dormant behind a flag until the new flow is verified, then remove splitting, recipes, DNA and picker UI and the RU_ScreenPatch lab names.

**Файлы.** 
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (openLab)
- `src/StarterGui/ScreenGui/Modules/LabScreen.luau`
- `src/StarterGui/ScreenGui/Modules/LabPresentation.luau`
- `src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau`
- `src/ReplicatedStorage/LabAudioConfig.luau`
- `src/StarterPlayer/StarterPlayerScripts/DOGROTS_RU_ScreenPatch.client.luau`

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/Lab/MutatorScreen.luau`

**Совместимость данных.** UI-only on this side; keep reading existing dog Variant/Mutation fields.

**Производительность.** A single window; the cinematic budget follows LabPresentation and Reduced Motion.

**Объём.** L

**Риски.** Server lab actions and data belong to the lab audit; existing DNA/catalyst balances in saves must stay visible or be converted. The HUD LAB tile currently opens the splash anywhere; with a console-only flow it should show a route (F1). The cinematic must lock input safely and always restore controls.


## Аудитор `trade-titles`

**Сейчас.** LabService blocks lab use while Engine.TradeByUser is set (LabService.luau:23,45); lab mutations change dog fields that are not part of the trade fingerprint (Variant is, mutation/genes may not be).

**План.** The new lab machine must keep the TradeByUser check. Before Trade 2.0 ships, extend the dog fingerprint in TradeRules to include every field the new mutation reroll changes, so a dog mutated between offer and commit invalidates the offer. With invites no longer locking players (F6), the lab is blocked only during accepted sessions.

**Файлы.** 
- `src/ServerScriptService/Economy/LabService.luau`
- `src/ServerScriptService/Economy/Engine.luau`

**Новые модули.** 
- `src/ServerScriptService/Economy/TradeRules.luau`

**Совместимость данных.** No saved data change.

**Производительность.** None.

**Объём.** S

**Риски.** A fingerprint missing the new mutation field would let a dog change after the partner reviewed it.


## Аудитор `events-nav`

**Сейчас.** Nav anchor MutationLab -> 05_MutationLab.EntranceAnchor (78,3,477). DistrictTravel 'Lab' requires the anchor to be inside 05_MutationLab. The LabScreen 'SHOW THE WAY' button navigates to 'Mutation lab'. The BLACKOUT lighting flicker affects every district Light except those under WarmLens/PortalEnergy. GOLDEN_HOUR / CURSED_FOG / RAINBOW_RIFT / NULL_HOUR boost mutation weights via WorldEventModifiers.MutationRows.

**План.** 1) Keep 05_MutationLab.EntranceAnchor (or retarget the NavigationAnchors.MutationLab Target) at the new console approach, and add a 'Lab console' destination for the path guide.
2) Mark mutation-machine lights with an exemption attribute (e.g. EventLightExempt) that WorldEventLighting skips, so the wow animation is not broken by BLACKOUT.
3) If the reroll uses mutation rows, show an 'event boost' badge during mutation-boosting events (reuse MutationRows).
4) Suppress event camera shakes and the title banner while the mutation cinematic plays (central CameraShake owner).

**Файлы.** 
- `src/ReplicatedStorage/WorldEvents/WorldEventLighting.luau`
- src/ReplicatedStorage/MapRouting.luau (only if a new key is added)
- src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau / PathGuide

**Совместимость данных.** None.

**Производительность.** Exemption check is a cheap attribute read during the one-time light capture.

**Объём.** S

**Риски.** Moving the EntranceAnchor outside 05_MutationLab breaks the DistrictTravel validation. Event FX cinematics overlapping the lab cinematic.


## Аудитор `tooling-perf`

**Сейчас.** 05_MutationLab: 983 parts (307 Neon, 54 Glass, 13 lights), anchors InteractionAnchor/EntranceAnchor/InteriorZone/PresentationCamera. LabPresentation (client) uses BindToRenderStep/RenderStepped and its own low/reduced checks. WorldDetailQuality would cap any in-lab emitter to 8/s and switch lights off beyond the nearest 24. Future lighting with GlobalShadows makes large transparent glass expensive.

**План.** Tooling/perf part: (1) Machine shell (tube frame, console, platform, collisions) as a pure layout module plus a server build through World/Builder anchored to 05_MutationLab.InteractionAnchor, LayoutVersion, Default streaming for the big shell and Atomic for the console. Hide old lab props reversibly via a server-side table (no new attributes). Budget <=600 parts, <=6 lights. (2) All 'energy inside the tube' (liquid columns, rings, arcs, particles, flashes) client-side in DOGROTS_ClientFX/Lab, built when within ~150 studs (Perf/Lod), idle loop via Perf/Scheduler at 30 Hz and paused when the camera is far or off-screen. Lights and emitters marked FXManaged and counted in Quality budgets. (3) The mutation cinematic is a client timeline module (pure keyframe table tested in Lune for duration/ordering) using Emit() bursts within the 'hero' budget, with a Reduced variant (no flashes or shake) and a Low variant. Only the triggering client gets the full show; others nearby get a reduced one driven by one server event. (4) Glass: one or a few large thin glass parts with low transparency layering; avoid stacking many transparent layers; prefer ForceField/Neon accents over refractive glass.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/LabPresentation.luau`
- `src/StarterGui/ScreenGui/Modules/LabScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau`
- src/StarterPlayer/StarterPlayerScripts/WorldDetailQuality.client.luau (FXManaged)
- src/ServerScriptService/Economy/LabService.luau (single mutate action, result event)

**Новые модули.** 
- `src/ReplicatedStorage/Lab/MachineLayout.luau`
- `src/ServerScriptService/LabMachineWorld.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/LabMachineFX.client.luau`
- `src/ReplicatedStorage/Lab/MutationTimeline.luau`
- `tests/lab_machine.luau`

**Совместимость данных.** The lab rework removes splitting/extra items from the UI only; existing saved lab state (LabState, recipe outputs) must remain readable. Keep server actions backward compatible or normalize old pending operations.

**Производительность.** Shell <=600 parts on the server. Client FX only near the lab. The cinematic is <=4 s of bursts within the hero budget. No per-frame server work.

**Объём.** XL (tooling/perf part M)

**Риски.** WDQ neutering if FXManaged is not added first. Future-lighting cost of big glass on mobile. LabPresentation's camera BindToRenderStep must be released on every exit path.
