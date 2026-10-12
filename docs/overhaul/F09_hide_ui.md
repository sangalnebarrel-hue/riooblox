# F9. Кнопка «Скрыть UI» — планы интеграции из аудита

Сгенерировано из аудита (docs/OVERHAUL_AUDIT.md). Каждый раздел — взгляд одного аудитора; основной — первый по профилю. Это исходный материал для реализации, а не итоговое решение: решения зафиксированы в docs/OVERHAUL_PLAN.md.


## Аудитор `ui` (основной)

**Сейчас.** No hide-UI feature exists. GUIIntegration toggles HUD.Visible, MainWindow and ProximityPromptService.Enabled per menu owner. 20+ ScreenGuis are created at runtime with DisplayOrder 0-301 (Kit layers, MiningGui/Shop/Toast, CommunityServices, Lucky/Secret/Event FX layers, debug panels). BillboardGuis are mostly runtime-created on the server (DogBillboard, SleepLabel, KingLabel, BlockTimer) and on the client (IncomePopups folder and TutorialWorldMarker in PlayerGui, Waypoint inside the main gui, OreLabel, EconomyCosmetic). Only 3 static ProximityPrompts exist; the rest are runtime. Free keys: H (F9 is the Roblox console).

**План.** Add Modules/UIVisibility.luau, started explicitly from GUIIntegration, with API Hide/Show/Toggle/IsHidden/Changed. It publishes client attributes player.UIHidden and gui.UIHidden.

Toggle: ContextActionService binding for H (+ DPadUp, to be verified), an eye button next to SETTINGS, and an entry in Settings.

Hide sequence:
1. If N.Owner ~= 'HUD', call N.Close().
2. Kit.Motion tween (0.22 s Quad In): U.QuickTiles out to the side edges, counters and IncomeChip down, notices up, ActiveSupplies right, Onboarding faded. LayoutHUD early-returns while hidden.
3. Disable every PlayerGui ScreenGui (Kit layers included) except DOGROTS_UIRestore and layers tagged UIKeep (event cinema / secret vignettes). Record Enabled per gui and guard GetPropertyChangedSignal('Enabled') so scripts that re-enable while hidden only update the remembered value. PlayerGui.ChildAdded handles guis created later.
4. BillboardGuis: a weak registry filled from workspace and PlayerGui DescendantAdded since start, set Enabled=false locally with the same guard. SurfaceGui signs stay by default, with an option to hide them.
5. ProximityPromptService.MaxPromptsVisible = 0, then restore (avoids fighting GUIIntegration over Enabled; verify in Studio).
6. CoreGui: record GetCoreGuiEnabled per type, SetCoreGuiEnabled(All,false), restore exactly. TextChatService ChatWindowConfiguration/ChatInputBarConfiguration Enabled.
7. Other characters' Humanoid.DisplayDistanceType = None locally, restored after.
8. F1 arrows and F10 nameplates listen to UIHidden.

Show: re-enable everything, then tween back in (Back Out, 20 ms stagger).

Auto-restore without animation when gui OpenMenu becomes non-nil (a server-driven modal must never open invisibly while movement is locked); P/B/M keys restore first.

Restore affordance: a 44 px eye button in DOGROTS_UIRestore that appears for 3 s on mouse move or touch and does not sink camera input. Optional mobile 'hide joystick' via GuiService.TouchControlsEnabled, off by default.

**Файлы.** 
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (start module, auto-restore on Acquire, P/B keys)
- src/StarterGui/ScreenGui/Modules/UITheme.luau (LayoutHUD respects UIHidden; eye button next to SimpleSettings)
- src/StarterGui/ScreenGui/Modules/EconomyScreens.luau or the new SettingsScreen (toggle entry)
- src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau (react to UIHidden)
- src/StarterPlayer/StarterPlayerScripts/WorldEventCataclysm/SecretArrivals FX layers (set UIKeep attribute)
- src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau (popups respect UIHidden)
- src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau (marker respects UIHidden)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/UIVisibility.luau`
- src/StarterGui/ScreenGui/Modules/UIVisibilityRestore.luau (restore button layer)

**Совместимость данных.** Session-only state. An optional p.Settings.HideHint is the only persisted bit.

**Производительность.** Registry maintained incrementally (IsA check per added instance); a toggle iterates only registered GUIs and billboards, O(hundreds). No per-frame cost while hidden apart from the 3 s hint timer.

**Объём.** M

**Риски.** Scripts that flip Enabled/Visible every tick (BuffHUD 0.25 s, OnboardingGuide 0.5 s, IncomePopups) need the property guard or they will reappear. Restore must reproduce the exact previous state (PlayerList is managed by PawpadRuntime). Conflict over ProximityPromptService ownership with GUIIntegration.menuControls and MiningClient. A server-opened modal while hidden must restore immediately or the player stays locked. A full workspace scan on toggle is too slow on large maps, hence the incremental registry. Mobile users could lose controls if TouchControlsEnabled is touched by default.


## Аудитор `data-network`

**Сейчас.** Сохранённых настроек нет; ReducedMotion берётся из GuiService и атрибутов. Скрытие UI нигде не реализовано.

**План.** Только клиент: переключить видимость ScreenGui и BillboardGui с анимацией. Remote не нужен. Если владелец хочет запоминать выбор между устройствами — модуль Features/Settings.luau: p.Settings={Version=1, HideUIKey=..., ...}, действие 'SettingsSet' {Key,Value} с белым списком ключей (только boolean и малые числа) и Snapshot.Features.Settings.

**Файлы.** 
- клиентский HUD/GUIIntegration

**Новые модули.** 
- `src/StarterPlayer/StarterPlayerScripts/HideUI.client.luau`
- (необязательно) src/ServerScriptService/Economy/Features/Settings.luau

**Совместимость данных.** Нет, или необязательный p.Settings.

**Производительность.** Нет.

**Объём.** S

**Риски.** Не прятать ProximityPrompt и системные окна покупок; push и уведомления, пришедшие при скрытом UI, должны появиться после показа.


## Аудитор `digging-depth`

**Сейчас.** Мировые BillboardGui подсистемы: SleepLabel собак (DogKennelService, MaxDistance 55), MiningNewHint, ярлыки руды (MiningClient), «+$» (EconomyVisuals). Будущие ярлыки F5 (тотем, баннеры).

**План.** Общий флаг скрытия (например атрибут игрока HideUI): DogAnimations.updateLabel, MiningClient World/Hud, EconomyVisuals и DeepMineClient при нём отключают свои BillboardGui и экранные элементы с плавным затуханием.

**Файлы.** 
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`
- `/home/user/riooblox/src/StarterPlayer/StarterPlayerScripts/MiningClient/World.luau`

**Совместимость данных.** Нет.

**Производительность.** Нет.

**Объём.** S

**Риски.** Ярлыки, которые пересоздаются (SleepLabel при каждом prepare), должны проверять флаг при создании.


## Аудитор `item-models`

**Сейчас.** EconomyVisuals создаёт мировые BillboardGui над находками (строка 187), баннер DiscoveryToast в ScreenGui (154), попапы дохода (61); ни один из них не проверяет флаг скрытия UI.

**План.** Подписать BillboardGui показа, тост и попапы на общий флаг HideUI (атрибут игрока или ScreenGui) с плавным исчезновением; сами 3D-модели и FX остаются для скриншотов.

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/EconomyVisuals.client.luau`

**Совместимость данных.** Нет.

**Производительность.** Нет.

**Объём.** S

**Риски.** BillboardGui не в ScreenGui — без явной подписки не скроются.


## Аудитор `plots`

**Сейчас.** World GUIs on plots: MapAmbience OwnerBillboard (AlwaysOnTop, MaxDistance 400), kennel SleepLabel billboards (55 studs), EconomyCosmetic title billboards over kennel dogs (40 studs), many ProximityPrompts; the showcase/estate SurfaceGuis are part of the scene.

**План.** The Hide-UI controller also toggles ProximityPromptService.Enabled and the BillboardGuis under 04_PlayerYards and KennelDogs (or those tagged 'HideWithUI' via CollectionService), with a fade. SurfaceGuis stay visible. Pause showcase/decor editor prompts while hidden.

**Файлы.** 
- src/ServerScriptService/MapAmbience.server.luau (tag billboard)
- src/ServerScriptService/DogKennelService.luau (tag SleepLabel)

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** GUIIntegration also toggles ProximityPromptService.Enabled for menus: restore the right state.


## Аудитор `lab`

**Сейчас.** The lab cinematic hides windows via N.BeginReward/N.EndReward (GUIIntegration) and shows a SKIP button on Kit.Overlay.

**План.** When F9 adds a global 'UI hidden' state (e.g. a ScreenGui attribute), LabCinematic must hide UI during the show and restore the user's F9 choice afterwards; the SKIP button and result card must appear even if UI was hidden by F9, or be replaced by a tap-to-skip gesture; the console prompt must stay usable while UI is hidden.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/LabCinematic.luau`
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`

**Совместимость данных.** None.

**Производительность.** None.

**Объём.** S

**Риски.** Conflicting owners of UI visibility (Reward owner vs Hide-UI) can leave the HUD hidden after a cinematic.


## Аудитор `trade-titles`

**Сейчас.** No hide-UI; the trade invite force-opens a window; world billboards (EconomyCosmetic, IncomePopups...) are separate from ScreenGui.

**План.** Hide UI must also suppress the new TradeInviteToast (queue the invite or auto-decline after its 30 s timer) and the client TitleTags layer (title billboards parented to a PlayerGui folder toggled by the same flag). An option keeps other players' titles for video.

**Файлы.** 
- `src/StarterGui/ScreenGui/Modules/GUIIntegration.luau`

**Новые модули.** 
- `src/StarterPlayer/StarterPlayerScripts/TitleTags.client.luau`
- `src/StarterGui/ScreenGui/Modules/TradeInviteToast.luau`

**Совместимость данных.** Client only.

**Производительность.** Disabling billboards also saves render cost.

**Объём.** S

**Риски.** An incoming invite must never re-show UI while hidden.


## Аудитор `events-nav`

**Сейчас.** No hide-UI concept. My subsystem's UI surfaces:
- notice Frame inside the main ScreenGui;
- ScreenGui DOGROTS_EventGameplay (DisplayOrder 90: Zoomies, glitch bars, server-luck banner);
- ScreenGui DOGROTS_EventCinema (95: event title);
- DistrictGuide overlay + Waypoint BillboardGui + ClearMarker button;
- world BillboardGuis: LocationLabels (ManagedWorldSign), tongue dog billboards (DogLineSpawner), pickup prompts.

**План.** Central player attribute 'HideUI' (set by the F9 button with a tween).
- WorldEventController: notice hidden while HideUI.
- Cataclysm and GameplayFX ScreenGuis: Enabled=false, or tween a CanvasGroup.
- DistrictGuide: hide the overlay, the HUD chip and the marker billboard; keep ground arrows optional (setting).
- WorldSignController: multiply alpha by (1-hide) so world labels fade too.
- ProximityPrompts: ProximityPromptService.Enabled toggle (client).
- Keep world VFX (screenshots want them).

**Файлы.** 
- `src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau`
- `src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/WorldSignController.client.luau`

**Новые модули.** 
- src/StarterGui/ScreenGui/Modules/UIVisibility.luau (shared HideUI state + helpers; owned by the UI subsystem)

**Совместимость данных.** None (client attribute; optional per-viewer preference).

**Производительность.** Negligible.

**Объём.** S

**Риски.** Server-created billboards (tongue labels) need client-side handling via tag or attribute. Do not hide prompts needed for mobile without an obvious restore button.


## Аудитор `tooling-perf`

**Сейчас.** The main ScreenGui (3,106 instances, ResetOnSpawn=false) plus runtime GUIs (DistrictGuide frame inside ScreenGui, Kit Overlay, Studio panels, CoreGui PlayerList toggled by PAWPAD). World BillboardGuis (dog labels, kennel labels) are separate.

**План.** Tooling/perf part: one client module UiVisibility.luau that tweens a CanvasGroup/GroupTransparency or the ScreenGui's top frames and then sets Enabled=false (disabled ScreenGuis cost nothing to render). It also lists other LayerCollectors in PlayerGui and optionally world BillboardGuis owned by our systems (via a tag 'DOGROTS_HideableWorldUI'). Respects Quality.Reduced (instant). No per-frame loop; restore state on toggle. A Lune test for the pure state machine (stack of hide reasons such as screenshot mode or cutscene, so systems that temporarily hide UI do not fight).

**Файлы.** 
- src/StarterGui/ScreenGui/Modules/GUIIntegration.luau (input binding; keys B/P/M/K/E/F are taken)
- src/StarterGui/ScreenGui/PawpadRuntime.client.luau (settings entry)

**Новые модули.** 
- `src/StarterGui/ScreenGui/Modules/UiVisibility.luau`
- `tests/ui_visibility.luau`

**Совместимость данных.** None.

**Производительность.** Disabled ScreenGuis save GUI render and layout cost while hidden.

**Объём.** S

**Риски.** Scripts that set Visible/Enabled on their own GUIs while hidden (EconomyVisuals toast, WorldEventController notices) may re-show them; route them through UiVisibility.IsHidden().
