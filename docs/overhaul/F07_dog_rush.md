# F7. Dog Rush — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `events-nav` (основной)

**Сейчас.** DOG_RUSH (Common, weight 14/99, ~14% of 915 s cycles, mean gap ~1 h 50 min, 240 s active).
- Server: Walk x1.35, tongue x1.5 (EventLineScale), LineLuck x1.2, DigSpeed +15%, Recovery +5%. Signature at +60 s is FX-only. End reward is max(600 x LayerScale, 1 min of income) + 2 bones for players present >=60 s with >=4 kennel digs (AFK-satisfiable).
- Client: sky portal + Leader dog (Spectacle), 'ALPHA STAMPEDE' banner/surge and StampedeWake beats relative to the player (Cataclysm), Zoomies speed lines + Trails, and the DogCrowd that follows the player (the bug).
- No interactive objects, no progression, event SFX silent (Audio.Cue stub).

**План.** 1) Remove the follow-player crowd: guard the WorldEventFX DogCrowd block and the Cataclysm DOG_RUSH beat behind `not Effects.Rush`, then delete them once Rush ships. Set DOG_RUSH perks Effects={Rush=true,Zoomies=true,Trail=true} and add Activity='Rush'. Keep Walk/LineSpeed/LineLuck/GameplayModifiers/Reward (economy unchanged).
2) RushSim (shared, pure, deterministic):
   - lanes = authored polylines on the boulevard (recommended: the DOG EXPRESS lanes x=+-26 for z 200..730, plus a hub loop around WelcomeHub where players spawn; avoid the yard section z<160 and the tongue);
   - baked Y, waves every ~20 s seeded by hash(Generation);
   - each runner {Id, Lane, StartTime, Speed, Kind=Normal|Golden|Rainbow, Offset};
   - PositionAt(runner, serverTime).
   Server and client compute the same positions from workspace:GetServerTimeNow(), so moving dogs need no replication.
3) Server WorldEventRush:
   - Start/Stop from WorldEventGameplay.Apply when Activity=='Rush';
   - publish RushSeed/RushWave attributes on WorldEvents.State;
   - RemoteFunction WorldEvents.RushCatch(runnerId) validates: ACTIVE, the runner is alive at t, HRP within 12 studs of PositionAt(t +- 0.35 s), not yet claimed (RAM claim like Interact), per-player cooldown 0.5 s and a per-wave cap; Runtime.Allow rate limit;
   - award via Runtime.Tx with key 'rushcatch:<uid>:<gen>:<runnerId>': Rush Points + a small income-scaled coin/bone bonus (BoostPricing.Coins);
   - Golden/Rainbow runners are rare (1-3 per wave), with a 'first catch' server-wide announcement through Signal.
4) Client RushRenderer (loaded by WorldEventGameplayFX when Effects.Rush):
   - pool of MenuModels dog clones (High 16 / Medium 10 / Low 5), created once and reused across waves;
   - only runners within ~160 studs of the camera get a model (virtualized crowd);
   - DogAnimationPlayer LOD: full Step for the 6 nearest, half rate for the rest, static pose >120 studs;
   - catch by a local ProximityPrompt on the nearest runner or a tap/touch radius -> RushCatch remote;
   - predicted hide like predictPickup.
5) Emotion:
   - 3-2-1 countdown + 'RUSH!' banner (reuse Cataclysm.banner);
   - dust/paw particles at lane heads (pooled emitters, :Emit bursts);
   - FOV kick + confetti + combo counter on catch (ReducedMotion aware);
   - golden runner aura (Highlight with a strict limit);
   - working SFX through a non-empty Audio.Cue (WorldSound);
   - end summary card (Signal Kind='RushSummary': points, catches, best combo, pass progress).
6) Progression (Rush Pass):
   - Economy/Features/EventPass.luau with p.EventPass (see F10/F8 hooks);
   - points from catches, real activity (mining hits, tongue purchases) and staying to the end;
   - 8-10 milestone tiers, claimed via action 'EventPassClaim' through DogEconomyRequest -> FeatureRegistry.Action;
   - rewards: bones, luck tiers (LuckRules.Add), Lucky Block credits, plot decorations (F8), titles (F10);
   - lifetime counters (Caught, Golden, BestCombo) for titles.
7) Make end-reward eligibility use real activity (keep the amounts).
8) Generalize as a WorldEvent 'Activity' interface (Start/Stop/Tick/Catch) so other events (bone catching in BONE_RAIN, etc.) reuse it.

**Файлы.** 
- src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau (DOG_RUSH perks: Effects.Rush, Activity)
- src/ReplicatedStorage/WorldEvents/WorldEventFX.luau (remove/guard DogCrowd)
- src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau (lane-anchored stampede beats)
- src/ReplicatedStorage/WorldEvents/WorldEventAudio.luau (implement Cue as additive SFX layer)
- src/ServerScriptService/WorldEventGameplay.luau (start/stop activity; activity-based eligibility)
- src/ServerScriptService/WorldEventService.luau (create RushCatch remote in Start; Signal kinds)
- src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau (load RushRenderer)
- src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau (RushSummary/catch toasts)
- src/StarterGui/ScreenGui/Modules/EventsScreen.luau (pass track)
- src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau (Rush budgets)

**Новые модули.** 
- `src/ReplicatedStorage/WorldEvents/Rush/RushConfig.luau`
- `src/ReplicatedStorage/WorldEvents/Rush/RushSim.luau`
- `src/ReplicatedStorage/WorldEvents/Rush/RushRenderer.luau`
- `src/ServerScriptService/WorldEventRush.luau`
- `src/ServerScriptService/Economy/Features/EventPass.luau`
- `src/ReplicatedStorage/WorldEvents/EventPassConfig.luau`
- tests/world_events.luau (RushSim determinism, catch validation tolerance, EventPass normalize/claim idempotency, schedule frequency)

**Совместимость данных.** New optional p.EventPass={Version=1,Season,Points,Claimed={},Ledger={[gen..runner]=true bounded},Lifetime={Caught,Golden,BestCombo}} created by EventPass.Normalize. Old profiles get the default and every reader is nil-safe. WorldEventsSeen, WorldEventRewards, WorldEventClaims and NextWorldEventCollect stay unchanged, as does the legacy p.Event/EventTokens. A season reset must never touch lifetime counters.

**Производительность.** No per-frame raycasts (baked lane heights). Model count is bounded by the pool. Animation LOD. One Heartbeat. Server cost is O(1) math per catch request and no moving replicated parts. Network: one attribute set per wave + catch RPCs (rate-limited). Low/mobile budget is 5 models.

**Объём.** XL

**Риски.** Client/server time drift: use GetServerTimeNow on both sides plus the tolerance window. Exploit auto-catch: per-wave cap, position check, cooldown, modest reward. Lane choice must not block the shops/tongue or overlap DOG EXPRESS gameplay (express lanes still speed players). MenuModels clones are skinned meshes, so cap Highlights. Do not change the owner's music logic in WorldEventAudio. Season/reward values need economy review (F11).


## Аудитор `data-network`

**Сейчас.** DOG_RUSH — мировое событие (WorldEventDefinitions; WorldEventService/Gameplay). Подборы в RAM (S.Objects). Награда — Tx:Run на профиле с квитанцией 'eventcollect:<uid>:<objectId>'. Данные: p.WorldEventClaims{Generation,Count,Objects}, p.NextWorldEventCollect, p.WorldEventsSeen, p.WorldEventRewards. Remotes: WorldEvents.Signal/Changed/GetState.

**План.** Модуль Features/EventPass.luau: p.EventPass={Version=1, Season='<id>', XP=0, Tier=0, Claimed={['1']=true}, Totals={DOG_RUSH=n}}. XP начисляется внутри существующей транзакции Interact (EventPass.AddXP(p,amount)) и в Gameplay. Действие 'EventPassClaim' {Tier}: награды через существующие механизмы (R.Credit, LuckyCredits, Cosmetics/Titles F10, Equipment.CaseCredits). Snapshot.Features.EventPass и push 'EventPass'; WorldEvents.Signal получает Kind='Progress'. Собаки события — только клиентские визуалы или серверные NPC без сварки с персонажем; новых сохраняемых сущностей нет.

**Файлы.** 
- src/ServerScriptService/WorldEventService.luau (Interact: AddXP)
- `src/ServerScriptService/WorldEventGameplay.luau`
- src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau (награды и прогрессия)

**Новые модули.** 
- `src/ServerScriptService/Economy/Features/EventPass.luau`
- `src/ReplicatedStorage/EventPassDefinitions.luau`

**Совместимость данных.** Новый необязательный ключ. Смена сезона — сравнение Season в Normalize (старые Claimed хранить в истории или сбрасывать идемпотентно). Существующие поля WorldEvent* не трогать.

**Производительность.** Новых DataStore-обращений нет: RAM-транзакция на подбор, как сейчас. VFX только на клиенте.

**Объём.** M

**Риски.** Инфляция наград (согласовать с экономикой). Interact читает мир внутри трансформа (позиция), оставить проверку и до транзакции. Сезонные ID никогда не переиспользовать.


## Аудитор `economy`

**Сейчас.** Dog Rush is a world event (WorldEventDefinitions.luau:4: GameplayModifiers DigSpeed .15, Recovery .05; line 30: LineSpeed 1.5, LineLuck 1.2). Events run about every 10 min for 240 s. Pickups pay a fixed 40 Cash + 2 Bones + an item (WorldEventConfig.Interactions; WorldEventService.Interact line 47), at most 10 per event with a 12 s cooldown. The DogRush plot skin costs 18,000 Cash (3600 x5), needs Goal 90 digs and the event seen. There is no progression or reward ladder.

**План.** New feature module ServerScriptService/Economy/Features/DogRush.luau (Normalize/Action/Snapshot) with p.DogRush={Version=1, Season (week) or Generation, Points, Claims={}}. Points come from digs during the event (R.Dig contribution while e.EventId=='DOG_RUSH'), pickups and goals. Reward ladder priced with BoostPricing.Coins: tier coins {MinCash=2000..10000, IncomeMinutes=3..10}, Bones 15-60, LuckyCredits (Rare -> Epic -> Legendary block), a timed EnergySnack through a new free-grant SupplyRules.AddFree that respects MaxSeconds, and at the top an exclusive decor (F8) and a title (F10). Caps: coins per event <= about 20 IncomeMinutes, per week <= about 120. Change the pickup Cash from the fixed 40 to BoostPricing.Coins({MinCash=40, IncomeMinutes=.25}). Claims are idempotent (receipt ids, like the existing 'eventcollect:').

**Файлы.** 
- `src/ServerScriptService/WorldEventService.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau`
- src/ServerScriptService/Economy/Rules.luau (points hook in R.Dig or via WorldEventService)
- src/ServerScriptService/Economy/SupplyRules.luau (AddFree)
- src/ReplicatedStorage/PlotCatalog.luau (DogRush skin stays)

**Новые модули.** 
- `ServerScriptService/Economy/Features/DogRush.luau`
- ReplicatedStorage/DogRushConfig.luau (reward ladder)

**Совместимость данных.** New optional field p.DogRush (nil means fresh). The existing PlotSkins.DogRush and WorldEventsSeen are kept.

**Производительность.** Points accrue inside existing transactions; no extra DataStore keys.

**Объём.** M

**Риски.** Inflation if IncomeMinutes is set too high; AFK farming (keep presence checks: pickups need distance <= 17); grants must never use the paid path (SupplyRules.AddPaid, PaidRandom).


## Аудитор `digging-depth`

**Сейчас.** DOG_RUSH (WorldEventDefinitions) даёт GameplayModifiers DigSpeed .15 и Recovery .05 на копание в будках (через Team effects). Визуально собаки в будках не меняются: DogAnimationPlayer.UpdateKennel играет цепочку ×1.0, акценты обязаны быть ×1.0 (правило DogDigProfiles).

**План.** Вместо собак, бегущих рядом с игроком, — «rush» собак в своих шахтах: клиент читает WorldEvents.State (EventId=DOG_RUSH, ACTIVE), DogAnimationPlayer получает множитель скорости для Loop (например 1.3); акценты остаются ×1.0 и по-прежнему заканчиваются в NextWorkAt. Пул пыли и искр по шахтам (только видимые, Low FX — выкл.), билборд «RUSH!». Сервер уже ускоряет находки.

**Файлы.** 
- `/home/user/riooblox/src/ReplicatedStorage/DogAnimationPlayer.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau`

**Совместимость данных.** Нет.

**Производительность.** Частицы через бюджет WorldDetailQuality.

**Объём.** S-M

**Риски.** Синхронизация акцентов с NextWorkAt при ускоренном цикле; tests/animations.luau.


## Аудитор `item-models`

**Сейчас.** DOG_RUSH — мировое событие (WorldEventDefinitions:4) без собственных предметов. На находках событие отмечается x.EventTag (ItemRules:193), визуально не показывается.

**План.** Сторона моделей: если в новых наградах будут предметы или трофеи — добавить рецепты; оверлей события по EventTag (значок или цвет FX) в фабрике; пул RevealRig переиспользуется для эффектов наград, без новых постоянных объектов.

**Файлы.** 
- `src/ReplicatedStorage/ItemModels/RarityFx.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventDefinitions.luau`

**Совместимость данных.** EventTag уже сохраняется.

**Производительность.** Общие лимиты: ≤8 эмиттеров, ≤4 света от предметов.

**Объём.** S

**Риски.** Перегрузка частицами во время события — общий глобальный бюджет FX.


## Аудитор `plots`

**Сейчас.** Event-themed plot skins already exist (DogRush etc.), claimable via WorldEventsSeen + GlobalDigContribution (PlotCatalog.Earned).

**План.** Expose Decor.Grant(p,id,n,source) and add event-exclusive decor (racing flags, trophy statue, event banner) as Dog Rush progression rewards; optionally show event trophies on the plot.

**Файлы.** 
- src/ServerScriptService/Economy/Features/Decor.luau (new)
- Dog Rush reward tables

**Совместимость данных.** Grants land in p.Decor.Owned; no migration.

**Производительность.** Within the decor budget.

**Объём.** S

**Риски.** Reward grants must be idempotent per receipt.


## Аудитор `ui`

**Сейчас.** Event UI: WorldEventNotice (UITheme panel inside the main gui, shown 4-6 s, hidden when a menu is open), EventsScreen (Menus), the DOGROTS_EventGameplay ScreenGui (90) and the EventCinema layer (95). No reward-progress HUD.

**План.** UI side:
- An event banner component in the HUD notification rail: icon, name, Kit.Countdown, progress bar towards the next reward tier; tapping opens an Events Kit window with a reward track (claim buttons with Hold for big rewards).
- Sound cues for start, milestone and end.
- Respects UIHidden and keeps cinema layers via UIKeep.

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau`
- `src/StarterGui/ScreenGui/Modules/EventsScreen.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau`

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/EventsWindow.luau`

**Совместимость данных.** Reward progression data is owned by the events audit.

**Производительность.** One banner, 1 Hz shared countdown.

**Объём.** S

**Риски.** Notice suppression while menus are open must stay. Avoid duplicating the WorldEventCataclysm title cinema.


## Аудитор `trade-titles`

**Сейчас.** Event rewards grant p.Cosmetics['Event'..i] (Engine:139) and plot skins via PlotCatalog.Earned (WorldEventsSeen + GlobalDigContribution); no title display.

**План.** Let the Dog Rush rework grant titles through TitleDefinitions (Requires = event progression stat or a granted p.Cosmetics key such as 'DogRush:<tier>'). Push 'TitleUnlocked' for the wow moment and offer EQUIP directly in the reward popup. Seasonal titles get Category='Event' and keep working after the event (saved in Unlocked).

**Файлы.** 
- `src/ServerScriptService/Economy/Engine.luau`
- `src/ServerScriptService/WorldEventService.luau`

**Новые модули.** 
- `src/ReplicatedStorage/DogEconomy/TitleDefinitions.luau`

**Совместимость данных.** Keep existing Event1..5 keys; map them to titles instead of renaming.

**Производительность.** None beyond F10.

**Объём.** S

**Риски.** Event titles must not be farmable by alts; define them from the player's own contribution stats.


## Аудитор `tooling-perf`

**Сейчас.** Dog Rush: WorldEventDefinitions DOG_RUSH {Walk=1.35, LineSpeed=1.5, LineLuck=1.2, Effects={Zoomies,Trail}}; client FX in WorldEventSpectacle (actor dogs 'Leader'), WorldEventCataclysm (StampedeWake parts, beams, bursts) and WorldEventGameplayFX (speed-lines GUI). Tier budgets WorldEventConfig.FX {Particles 64/28/4, Debris 52/24/8, Dogs 14/8/3}. DogAnimationPlayer has a DOG_RUSH branch.

**План.** Tooling/perf part: (1) Runner dogs client-side only, from a Perf/Pool of dog rigs (cloned once from MenuModels), animated through DogAnimationPlayer with the DogAnimations culling/LOD; never parented to or welded to the player character. Path them along authored lanes (reuse the RouteGraph from F1 or event lanes), anchored, CFrame-driven at <=30 Hz via Perf/Scheduler. Cap by Quality.Budget('Dogs') = existing FX.Dogs (14/8/3), with only 2 runners near other players. (2) VFX bursts via Emit() within the Particles budget; reward moments use the 'hero burst' budget. (3) Lune tests for the lane generator (no lane through buildings or players' yards) and the event reward/progression rules in economy_env.

**Файлы.** 
- `src/ReplicatedStorage/WorldEvents/WorldEventSpectacle.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau`
- src/ReplicatedStorage/WorldEvents/WorldEventConfig.luau (budgets)
- src/ReplicatedStorage/DogAnimationPlayer.luau (if a runner role is needed)

**Новые модули.** 
- `src/StarterPlayer/StarterPlayerScripts/DogRushRunners.client.luau`
- `src/ReplicatedStorage/Perf/Pool.luau`
- `tests/dog_rush.luau`

**Совместимость данных.** New rewards and progression saved via an Economy feature with defaults. Event state stays in WorldEvents.State attributes.

**Производительность.** No server-moved dogs (zero replication). Pooled rigs (no clone per wave). Animation LOD as DogAnimations.

**Объём.** L

**Риски.** Dog rig clone cost on first use (preload during the WARNING phase). Highlight/particle stacking with other systems is handled by the shared budgets.
