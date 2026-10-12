# F1. Навигация «Показать путь» — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `events-nav` (основной)

**Сейчас.** Only a floating BillboardGui marker ('name + N studs') above an invisible client part (DistrictGuide 'LocalDistrictWaypoint'). It is auto-cleared within 13 studs (XZ). The district map overlay has a destination list and a dot schematic (bounds skewed by TheVoid). Navigation API is display-name strings via the NavigateDistrict BindableEvent. Anchors live in Persistent NavigationAnchors (13 keys), so they always exist on the client. The street network is an axis-aligned grid (MainBoulevard x[-18,18] z[146,754], cross streets at z=200/275/335/395/465/535/730, yard promenades x=+-30/+-156, crossings z=-156..156, approach paths in DirectPaths/ConnectedPaths). There are no PathfindingModifiers. Streaming: MinRadius 64, TargetRadius 1024; the district spans ~900 studs.

**План.** 1) Data graph, not runtime pathfinding. Write tools/navgraph_gen.luau (Lune, read-only on the place) that turns the rectangles of PrimaryPaths/DirectPaths/ConnectedPaths into centerline nodes + edges and writes src/ReplicatedStorage/Navigation/NavGraphData.luau ({Nodes={id={Pos=Vector3,Y}}, Edges={{a,b}}}), with hand overrides for stairs/doors (lab glass door, museum entrance). The graph is plain data, so it works while far parts are not streamed in.
2) Notes on PathfindingService. ComputeAsync can be called from a LocalScript, but the client only knows streamed-in geometry (StreamingTargetRadius 1024 / MinRadius 64 here), so 900-stud routes are unreliable. Running it on the server costs CPU and needs a remote. Use it at most as an optional last-mile (<80 studs) inside interiors. Verify the behaviour in Studio; I could not confirm it from code.
3) RoutePlanner (pure module, Lune-testable): nearest-node snap for start/end (projection onto the nearest edge), A* over ~60-120 nodes, corner rounding (fillet radius 4-6 studs), resampling by arc length.
4) Destinations module: extend MapRouting.Locations with Key, Icon, Category and a Resolve(player) function:
   - own plot via player attribute YardSpawnPosition;
   - Mining Corner / Collector / Showcase (F3) via a server-published attribute or a Persistent anchor;
   - each shop terminal (11_Shops InteractionAnchors), Lab console (F12), Museum, DOG-O-MATIC, Shelter, Leaderboards, Dog Line, Mine entrance (F5);
   - current event stage/pickups (Workspace.WorldEventFX models, Rush lane start).
   Keep the MapRouting API unchanged.
5) PathGuide client renderer:
   - one Folder, a pool of chevron Parts (High 32 / Medium 20 / Low 12; Neon, CanCollide/CanQuery/CanTouch=false, CastShadow=false), placed only in a window [s-8, s+60] studs of arc length around the player;
   - flow animation: offset=(t*speed)%spacing at 30 Hz (static with ReducedMotion);
   - orientation from the tangent of the rounded polyline so arrows follow turns smoothly;
   - Y from baked node heights plus a raycast only when an arrow changes segment (cached);
   - optional textured Beam strip with TextureSpeed for GPU flow if the owner uploads a chevron decal.
6) Final pointer: pooled Beam pillar (V.Beam/V.Soft) + ground ring (V.Ring) + bobbing 3D arrow + the existing distance BillboardGui; an off-screen edge arrow in the HUD.
7) Lifecycle:
   - auto-clear within 10 studs or when the destination's ProximityPrompt fires;
   - re-route when the distance from HRP to the polyline is >18 studs for >1.2 s (debounce 1/s);
   - cancel chip '-> LAB 120m [X]' in the HUD.
8) Hook points:
   - DistrictGuide NavigateDistrict handler calls PathGuide.Start(key);
   - fix matching (keys + names + aliases table);
   - every 'GO / SHOW THE WAY' button already calls N.Navigate, so they upgrade for free;
   - the map list gets a 'SHOW PATH' button.
9) Fix bugs: locations[2], Feedback key, Heartbeat yard overwrite, Bounds excluding sealed locations.

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau`
- src/ReplicatedStorage/MapRouting.luau (additive only: Icon/Category fields, Bounds skips Sealed)
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (N.Navigate accepts keys)
- src/ServerScriptService/NavigationSync.server.luau (only if new moving anchors)
- src/ReplicatedStorage/WorldEvents/WorldEventObjects.luau (reuse builders, no change needed)

**Новые модули.** 
- tools/navgraph_gen.luau (offline generator, Lune)
- `src/ReplicatedStorage/Navigation/NavGraphData.luau`
- `src/ReplicatedStorage/Navigation/RoutePlanner.luau`
- `src/ReplicatedStorage/Navigation/Destinations.luau`
- src/StarterPlayer/StarterPlayerScripts/PathGuide.client.luau (or Modules/PathGuide.luau driven by DistrictGuide)
- tests/navgraph.luau (connectivity: every non-sealed Location reachable; nodes lie inside walkable path rectangles of the place)

**Совместимость данных.** No saved data. Only new player attributes (e.g. MiningCornerPosition, ShowcasePosition) published by the server. Existing NavigateDistrict callers that pass display names keep working through the alias table.

**Производительность.** Bounded pool (<=32 parts + 1 pillar + 1 ring), never thousands of objects. A* on ~100 nodes is microseconds; replans at most 1/s. Arrow updates run at 30 Hz only inside a ~70-stud window. No per-frame raycasts (heights cached). Zero network traffic. Mobile: thicker arrows, fewer of them, 48px+ buttons.

**Объём.** L

**Риски.** The graph must be regenerated when geometry changes (installers or F5/F12 rebuilds): add the test to tools/check.sh. Stairs and the lab glass door need manual edges. Changing the display names used by ~10 callers must be done through aliases. MapRouting must not be renamed (build.py template). Billboard and arrow visibility should respect the F9 HideUI decision (keep arrows, hide HUD chip).


## Аудитор `data-network`

**Сейчас.** Сохранённых данных нет. MapRouting (13 NavigationAnchors, Routing.Position, у участка — YardSpawn). Действие DistrictTravel через DogEconomyRequest телепортирует только к Lab/Museum (пауза 2 с). PathfindingService нигде не используется. StreamingEnabled (MinRadius 64), поэтому на клиенте нет дальней геометрии для локального поиска пути.

**План.** Отрисовка целиком на клиенте (пул стрелок). Маршрут берётся (а) из заранее собранного графа точек `ReplicatedStorage.NavGraph` (узлы и рёбра числами, генерируется из плейса Lune-скриптом) — без сети; либо (б) из серверного действия 'NavRoute' {Destination} в Runtime.Request рядом с DistrictTravel: сервер (видит всю карту) вызывает PathfindingService:CreatePath/ComputeAsync и возвращает плоский массив координат (≤256 точек). Кэш на (Destination, клетка старта 16×16) на 60 с, стоимость 1 токен, пауза 2 с на игрока. В профиль ничего не пишется; признак «подсказка показана» класть в существующий p.Onboarding.Seen через действие Tutorial.

**Файлы.** 
- src/ServerScriptService/Economy/Runtime.luau (ветка 'NavRoute' и стоимость)
- src/ReplicatedStorage/MapRouting.luau (каталог назначений)
- src/ServerScriptService/Economy/DistrictTravel.luau (общий белый список назначений)

**Новые модули.** 
- src/ServerScriptService/Economy/NavRoute.luau (поиск пути на сервере + кэш)
- src/ReplicatedStorage/NavGraph.luau (граф, если вариант (а))
- src/StarterPlayer/StarterPlayerScripts/NavArrows.client.luau (пул стрелок, не на сервере)

**Совместимость данных.** Нет изменений сохранений.

**Производительность.** ComputeAsync на сервере занимает единицы–десятки мс, кэш и лимит обязательны. На клиенте не больше ~40 частей в пуле, обновление по Heartbeat без создания объектов.

**Объём.** M (сетевая часть S)

**Риски.** Двери и закрытые зоны (DistrictDoors, Sealed-локации) — маршрут не должен вести внутрь. Участки других игроков. ComputeAsync может выдавать нестабильные пути на динамической геометрии, нужен запасной вариант через граф. Ответ сервера большой, если не сжать.


## Аудитор `digging-depth`

**Сейчас.** NavigationAnchors.PlayerYards (0,2,110) — общая точка; у DigSlot есть атрибут ApproachPosition (край дорожки).

**План.** Цели «Мои будки/шахты» и «Консоль глубины» вычисляются для игрока на клиенте: свой участок по атрибуту YardId → DigSlot_1.ApproachPosition / позиция консоли. Маршрут должен заканчиваться у ApproachPosition, а не в шахте. Guard шахт коллизионные (или PathfindingModifier PassThrough=false), чтобы PathfindingService их обходил. Финальная стрелка — на стойке лебёдки.

**Файлы.** 
- `/home/user/riooblox/src/ReplicatedStorage/MapRouting.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau`

**Совместимость данных.** Нет.

**Производительность.** Нет.

**Объём.** S (в рамках F1)

**Риски.** Маршрут через открытые шахты, если Guard без коллизий; узкие щели 4 стада между шахтами.


## Аудитор `plots`

**Сейчас.** MapRouting destination 'PlayerYards' resolves to the player's own YardSpawn (MapRouting L25-28); NavigationAnchors.PlayerYards sits at (0,2,110); DogsScreen offers 'SHOW THE WAY' to the yard when display editing needs DOG STORAGE.

**План.** Add plot sub-destinations: own showcase (persistent ShowcaseAnchor), DOG STORAGE (StorageAnchor), kennels, DECORATE entry. Expose them via MapRouting.Anchor-style lookups that read YardId-matched anchors created by ShowcaseWorld/Decor, so the route ends with the final pointer at the stand. Keep EntryWalk free of decor (PlotDecorZones reserved mask) so the arrow route stays valid; client-only decor is ignored by path computation or given hitboxes.

**Файлы.** 
- `src/ReplicatedStorage/MapRouting.luau`
- src/StarterGui/ScreenGui/Modules/DogsScreen.luau (navigate)
- src/StarterGui/ScreenGui/Modules/ShowcaseEditor.luau (new)

**Совместимость данных.** None.

**Производительность.** Negligible; anchors are a few parts per yard.

**Объём.** S

**Риски.** With StreamingEnabled the anchors may not exist on the client: use attributes or yard-frame math as a fallback.


## Аудитор `lab`

**Сейчас.** Lab splash 'SHOW THE WAY' calls N.Navigate('Mutation lab') -> DistrictGuide marker at NavigationAnchors/MutationLab (78,3,477, entrance, Target ObjectValue); N.Travel('Lab') teleports to the entrance via DistrictTravel.

**План.** Expose the lab as a path destination whose final pointer is the new console: add an inner waypoint (e.g. NavigationAnchors/MutationConsole or MutationReactor.CameraHooks.ConsoleApproach at ~(103,3,477)) and a route segment entrance (78,3,477) -> nave along Z=477 -> console. Keep MapRouting key 'MutationLab' for DistrictTravel (teleport stays at the entrance); the F1 path service should accept a sub-target so the arrow trail ends at the console, not the door. LabScreen splash keeps calling N.Navigate(S.Destination).

**Файлы.** 
- `src/ReplicatedStorage/MapRouting.luau`
- `src/StarterGui/ScreenGui/Modules/LabScreen.luau`
- `src/ServerScriptService/Economy/LabReactorWorld.luau`

**Совместимость данных.** None (no saved data).

**Производительность.** Negligible for the lab part.

**Объём.** S

**Риски.** The path must avoid the tube base and console collision; with streaming the inner waypoint may not be loaded when the route starts (use static coordinates from LabReactorConfig).


## Аудитор `ui`

**Сейчас.** DistrictGuide.client places a single BillboardGui 'Waypoint' (text + distance) on an invisible part, chosen from MapRouting.Locations via the map (M), the DistrictDirectoryPrompt, or the NavigateDistrict BindableEvent. Every 'SHOW THE WAY' / Destination CTA (Kit screens, OnboardingGuide, IncomeChip, InventoryPage CandyStart, Lab splash) calls N.Navigate(destination), which fires NavigateDistrict. ClearMarker is the only control.

**План.** UI side only; the path engine belongs to the navigation subsystem.
- Keep N.Navigate/NavigateDistrict as the single entry point, so every existing CTA automatically gets the real route.
- Replace the marker logic inside the NavigateDistrict handler with a call to a PathGuide module (client arrows, pooled).
- Add a Kit 'ROUTE' sheet (HUD tile 'Route' or map button) listing MapRouting.Locations with icons and distance; selecting one starts the route.
- Replace ClearMarker with a pill 'Route: LAB · 120 studs [STOP]' in the HUD notification rail.
- Arrows hide on player.UIHidden (F9) and when a menu is open (OpenMenu).
- Arrival triggers Kit.Toast and a sound cue.

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau`
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (N.Navigate unchanged)
- src/ReplicatedStorage/MapRouting.luau (read)
- src/StarterGui/ScreenGui/Modules/UITheme.luau (HUD slot for route pill)

**Новые модули.** 
- src/StarterGui/ScreenGui/Modules/RouteScreen.luau (destination picker)
- PathGuide client module (owned by the navigation audit)

**Совместимость данных.** None.

**Производительность.** The picker is static; arrow pooling is handled in the PathGuide design.

**Объём.** M

**Риски.** Destination names are matched loosely in the DistrictGuide handler (Factory, Event headquarters, Paw square, Your yard); keep that alias table. Sealed locations must still show their hint. Must not leak arrow parts on respawn or streaming-out.


## Аудитор `tooling-perf`

**Сейчас.** DistrictGuide.client shows a marker plus distance text above the target at 5 Hz (markerPart, BillboardGui). There is no PathfindingService anywhere. MapRouting gives the anchor positions; NavigationAnchors (13 parts) are Persistent, so they are always on the client. Walkable street geometry exists as 36_DistrictRefresh.DirectPaths (15 segments, square turns), 37_AttractionRefresh.ConnectedPaths (27) and 01_IslandAndStreets.PrimaryPaths. Under streaming the client does not hold the whole map, so client-side pathfinding over geometry is unreliable.

**План.** Tooling/perf part: (1) Pure module ReplicatedStorage/Navigation/RouteGraph.luau: hand-authored waypoint graph (nodes along DirectPaths/ConnectedPaths/PrimaryPaths, plus a door node per destination from MapRouting.Anchor/EntranceAnchor) with A*, corner smoothing (Catmull-Rom or arc fillets) and resampling into a polyline with per-point tangents. Fully unit-testable in Lune: every MapRouting.Locations key reachable, no segment crosses a building footprint (list of AABBs), path length within 1.3x of straight line. (2) Client renderer RouteArrows.client using Perf/Pool: prefer Beam segments between pooled Attachments with an arrow texture and TextureSpeed, so the flow animation costs no Lua per frame; segment count is the number of corners (<=24). Optionally pooled arrow parts (<=40 High, 28 Medium, 16 Low from Quality.Budget('Arrows')) slid along the polyline at 30 Hz via Perf/Scheduler, only within 120 studs of the player. Final pointer: one pooled model with a ground ring at the target. Re-trim the drawn path from the player's projected position at 5 Hz; recompute the route only when the player leaves a 12-stud corridor. (3) Parent everything under workspace.DOGROTS_ClientFX/Route (outside the district, so WDQ and DistrictWorldMotion scanners skip it). Set CanCollide/CanQuery/CanTouch false and CastShadow false.

**Файлы.** 
- src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau (call the route renderer instead of, or in addition to, markerPart)
- src/ReplicatedStorage/MapRouting.luau (expose door/entrance points)
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (N.Navigate entry)

**Новые модули.** 
- `src/ReplicatedStorage/Navigation/RouteGraph.luau`
- `src/ReplicatedStorage/Navigation/RouteSmooth.luau`
- `src/StarterPlayer/StarterPlayerScripts/RouteArrows.client.luau`
- `src/ReplicatedStorage/Perf/Pool.luau`
- `src/ReplicatedStorage/Perf/Scheduler.luau`
- `tests/navigation.luau`

**Совместимость данных.** No saved data. An optional 'last destination' can stay client-only.

**Производительность.** Beams with TextureSpeed: 0 Lua/frame for the flow animation. Pool capped by tier; route rebuild at most every 0.2 s and only on corridor exit. Instance count <=70 total.

**Объём.** M

**Риски.** An arrow texture asset must be uploaded by the owner (the build cannot add assets); otherwise fall back to WedgePart arrows. The hand-authored graph must be kept in sync with geometry changes (F5/F12 entrances), which the Lune footprint test catches.
