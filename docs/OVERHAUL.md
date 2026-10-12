## Клиентский фундамент

Волна 0 переработки, ветка B (`docs/OVERHAUL_PLAN.md` §2.2). Здесь общие клиентские помощники, которыми пользуются все следующие фичи: уровень качества и бюджеты, общий планировщик, пулы, LOD, строитель мира из спецификаций, звуки интерфейса, токены Kit и глифы. Плюс инструмент `tools/preview`, который рисует раскладки без Roblox Studio.

### Что где лежит

| Файл | Что делает |
|---|---|
| `ReplicatedStorage/Perf/Quality.luau` | Уровень качества High / Medium / Low, «уменьшение движения», бюджеты по уровню |
| `ReplicatedStorage/Perf/Scheduler.luau` | Один общий Heartbeat для всех периодических задач клиента |
| `ReplicatedStorage/Perf/Pool.luau` | Пул повторяемых объектов |
| `ReplicatedStorage/Perf/Lod.luau` | Уровни детализации по дистанции и пирамиде видимости, путь через тег `DOGROTS_Lod` |
| `ReplicatedStorage/Perf/Maid.luau`, `Perf/Signal.luau` | Уборка соединений и простой сигнал. `Kit/Maid` и `Kit/Signal` теперь пересылают сюда |
| `StarterPlayerScripts/PerfBootstrap.client.luau` | Запускает `Quality` и путь тегов `Lod` сразу после входа |
| `ReplicatedStorage/World/Spec.luau` | Чистые спецификации деталей и преобразования (без Instance) |
| `ReplicatedStorage/World/Builder.luau` | Строит модель из спецификаций, отдельно от мира, Parent одним действием |
| `ReplicatedStorage/UISound.luau` | Звуки интерфейса: именованные сигналы, пул голосов, шины громкости |
| `ServerScriptService/AudioBootstrap.server.luau` | Создаёт `SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient}` при старте сервера |
| `StarterGui/ScreenGui/Modules/Kit/Sound.luau` | Связка Kit → UISound (кнопки, окна, вкладки) |
| `tools/preview/` | Экспорт раскладок и регионов плейса в JSON и рендер в PNG (three.js) |
| `tests/perf.luau`, `tests/world.luau`, `tests/ui_assets.luau`, `tests/perf_lint.luau` | Тесты Lune этой волны |

### Perf.Quality — один уровень качества

```lua
local Quality = require(ReplicatedStorage.Perf.Quality)
Quality.Tier()                  --> "High" | "Medium" | "Low" — уровень, который действует сейчас
Quality.Preference()            --> "Auto" | "High" | "Medium" | "Low"
Quality.Reduced()               --> true, если включено уменьшение движения
Quality.Budget("Lights")        --> бюджет для текущего уровня
Quality.Budget("Lights", "Low") --> бюджет для заданного уровня
Quality.Changed:Connect(function(tier, reduced) end)            -- сменился уровень или «движение»
Quality.PreferenceChanged:Connect(function(preference, tier) end) -- явный выбор игрока (не сторож FPS)
Quality.SetPreference("Low")    -- выбор на сессию
Quality.Claim("Highlights", owner, 3) --> сколько выдано (0…3)
Quality.Release(owner)          -- снять все заявки владельца (или Release(owner, "Highlights"))
Quality.Claimed("Lights"); Quality.Available("Lights"[, tier])
Quality.State()                 -- отладка: все входы и итог
```

**Откуда берётся уровень.** Побеждает последний явный выбор:

1. атрибут игрока `Setting_Quality` (сохранённая настройка; её публикует сервер, ветка A);
2. атрибут `WorldEventFX`, если его записал кто-то другой (кнопка PAWPAD «World Event FX»);
3. иначе `Auto`:
   * `UserGameSettings().SavedQualityLevel`: 1–3 → Low, 4–6 → Medium, 7–10 и «Автоматически» → High;
   * сенсорный экран без клавиатуры — не выше Medium (телефоны начинают с Medium);
   * сторож FPS: первые 15 с не считаются; если средний FPS за блок 10 с ниже 40, уровень снижается на ступень (не больше двух ступеней); через 60 с стабильных 55+ FPS — повышается обратно. Если после повышения в течение 60 с снова пришлось снижать, время возврата удваивается (до 600 с). Пока окно игры не в фокусе (Roblox тогда сам режет FPS), замеры не считаются; один замер длиннее 5 с (клиент стоял) отбрасывается.

Явный выбор (High/Medium/Low) сторож и устройство не меняют. Окно настроек (F2) вызывает `SettingsSave` на сервере; сервер возвращает значение атрибутом `Setting_Quality`.

**Ступень сторожа — не выбор игрока.** Она меняет `Tier()`, `WorldEventFX` и вызывает `Changed`, но не `PreferenceChanged`. `WorldEventController` перезапускает идущий ивент только по `PreferenceChanged` (PAWPAD, окно настроек) и только если уровень правда другой; ступень сторожа во время ивента его не трогает (иначе заставка и все эффекты пересобирались бы каждые 10–60 с, как раз когда FPS и так низкий). Следующий ивент начинается уже на новом уровне.

**Уменьшение движения** = настройка доступности Roblox (`GuiService.ReducedMotionEnabled`) **или** сохранённая настройка `Setting_ReducedMotion`. Переключатель PAWPAD «Motion» (атрибут `ReducedMotion`) — явный выбор на эту сессию: он главнее обоих, в том числе может выключить уменьшение, включённое в Roblox. Новое значение `Setting_ReducedMotion` (окно настроек) снова отменяет переключатель. Сохранённое `false` само по себе настройку Roblox не выключает, поэтому значение по умолчанию с сервера доступность не ломает. Окно настроек может показать «включено в Roblox» по `Quality.State().SystemReduced`.

**Совместимость.** Старые скрипты (около 12 штук) читают атрибуты напрямую. `Quality` сам пишет атрибуты игрока, только когда значение меняется:

* `WorldEventFX = Tier()`;
* `LowFX = (Tier() == "Low")` — раньше этот атрибут читали, но не ставил никто;
* `ReducedMotion = Reduced()`.

Своих записей модуль не принимает за выбор игрока. Все `require` на клиенте делят одно состояние; первый вызов запускает модуль.

**Бюджеты (`Quality.Budgets`, §4 плана).**

| Ключ | High | Medium | Low | Что ограничивает |
|---|---|---|---|---|
| `Lights` | 24 | 16 | 8 | видимые источники света в районе (WDQ и фичи) |
| `LightRadius` | 160 | 120 | 85 | дальше этого свет выключен (стады) |
| `Particles` | 64 | 28 | 4 | частиц в секунду на весь район (= `WorldEventConfig.FX`) |
| `EmitterRate` | 8 | 5 | 2 | частиц в секунду на один фоновый эмиттер |
| `EmitterRadius` | 210 | 150 | 90 | дальше этого фоновые эмиттеры выключены |
| `Burst` / `BurstScale` | 300 / 1 | 150 / 0,5 | 45 / 0,15 | «вау-всплеск» за 4 с (F12, F7) |
| `Debris`, `Dogs` | 52, 14 | 24, 8 | 8, 3 | обломки и собаки ивентов (= `WorldEventConfig.FX`) |
| `Highlights` | 8 | 4 | 2 | Highlight одновременно, все системы вместе |
| `Viewports` | 12 | 8 | 4 | видимые ViewportFrame |
| `Arrows` | 32 | 20 | 12 | стрелки пути (F1) |
| `Titles` | 12 | 8 | 8 | титулы над игроками (F10) |
| `DecorParts` / `ShowcaseParts` / `MineParts` | 300 / 150 / 400 | те же | те же | деталей на участок: декор (F8), витрина (F3), видимый уровень шахты (F5) |
| `LabParts` / `LabLights` / `LabEmitters` | 600 / 6 / 4 | те же | те же | машина мутаций (F12) |
| `LodNear` / `LodFar` | 160 / 320 | 120 / 240 | 85 / 160 | дистанции LOD по умолчанию |
| `FeatureMs` | 0,3 | 0,3 | 0,2 | Lua-время одной фичи за кадр |

**Общие бюджеты — заявки.** `Lights`, `Particles`, `Highlights`, `Viewports` (и любой другой ключ) тратят несколько систем сразу. Система, которая сама включает свет, эмиттеры, Highlight или ViewportFrame (всё `FXManaged`, витрина, лаборатория, превью), сначала делает `Quality.Claim(key, owner, n)` и включает не больше выданного. Новая заявка того же владельца заменяет прежнюю; выдаётся не больше остатка после других владельцев. `WorldDetailQuality` заявок не делает и тратит `Quality.Available("Lights")` / `Available("Particles")` — остаток бюджета. Когда уровень падает, заявки не урезаются сами: владелец подписан на `Quality.Changed`, заявляет заново и гасит то, что не выдали. Уходя, владелец вызывает `Quality.Release(owner)` (через Maid). `LabLights` / `LabEmitters` — внутренние лимиты лаборатории; её свет всё равно заявляется из общего `Lights`.

### Perf.Scheduler — один Heartbeat

```lua
local Scheduler = require(ReplicatedStorage.Perf.Scheduler)
local job = Scheduler.Every(5, "Showcase.Lod", function(dt, deadline)
	-- dt: секунды с прошлого вызова этой задачи
	-- deadline: os.clock(), к которому вызов должен закончиться (1 мс)
	return false -- true = «работа осталась»: продолжить в следующем кадре
end)
job:SetRate(2); job:Stop()
Scheduler.Stats() -- {Jobs, Frames, ByName = {[name] = {Calls, Errors, AvgMs, MaxMs, Hz}}}
```

* **Частота.** Не чаще `hz` раз в секунду; `hz <= 0` или `>= 60` — каждый кадр. После подвисания нет пачки догоняющих вызовов.
* **Нарезка времени.** На вызов — 1 мс (`deadline`). Длинный проход возвращает `true` и продолжается в следующем кадре. Время сверх бюджета становится «долгом», который переносится: задача пропускает кадры, пока долг не погашен, поэтому в среднем она укладывается в ~1 мс на кадр. Все задачи вместе получают 4 мс на кадр; задачи, которым не хватило времени, идут первыми в следующем кадре (по кругу, никто не голодает).
* **Профайлер.** Каждый вызов обёрнут в `debug.profilebegin("Perf:" .. name)`: в MicroProfiler видно, кто сколько стоит.
* **Ошибки.** Вызов в `pcall`; ошибка считается и пишется в `warn` один раз на задачу; расписание задачи не ломается.
* **Задача не должна уступать** (`task.wait`, `WaitForChild`, `InvokeServer`, `PreloadAsync`): то, что ждёт, запускайте через `task.spawn`. Вызовы идут в переиспользуемой сопрограмме-исполнителе (без нового потока на вызов). Если задача всё же уступила, стоит только она: `warn` один раз, повторно она не запускается, пока тот вызов не вернётся, остальные задачи идут дальше. Ошибка после ожидания тоже считается.
* Heartbeat подключён, только пока есть задачи. `Scheduler.new({Clock = ...})` создаёт отдельный планировщик без Heartbeat (для тестов).

Новым фичам свои `RenderStepped`/`Heartbeat`/`Stepped` запрещены: это проверяет `tests/perf_lint.luau`. `WorldDetailQuality` и `PlotSkinMotion` уже переведены на планировщик.

### Perf.Pool

```lua
local arrows = Pool.new({
	Create = function() return makeArrow() end, -- обязательно; Instance или таблица
	Reset = function(arrow) end,                -- при Release
	Max = 32, Prewarm = 8, Parent = folder,
	Hide = "Modifier", -- "Modifier" | "Transparency" | "Folder" | "None" | function(obj, hidden)
	Steal = false,     -- при Max: true — забрать самый старый активный, false — вернуть nil
	OnSteal = function(arrow) end, -- со Steal: прежний пользователь узнаёт, что объект забрали
})
local arrow, lease = arrows:Acquire(); arrows:Release(arrow, lease)
arrows:Stats() -- {Active, Free, Created, Reused, Dropped, Peak, Max}; arrows:Destroy()
```

Объекты один раз ставятся в `Parent` (или туда, куда их поставил сам `Create`) и остаются там:

* `Modifier` (по умолчанию для любого Instance) — свободный объект прячется через `LocalTransparencyModifier = 1`, GUI через `Visible`, свет, эмиттеры, лучи и GUI-слои — через `Enabled = false`. При показе восстанавливается ровно то, что было изменено.
* `Transparency` — то же через `Transparency`, для серверных пулов.
* `Folder` — перенос в скрытую папку и обратно.
* `None` (по умолчанию для таблиц) — ничего, прячет `Reset` или сам вызывающий.

**Аренда.** `Acquire` возвращает объект и номер аренды. `Release(obj, lease)` с устаревшим номером ничего не делает: тот, у кого объект забрали (`Steal`), не освободит его у нового владельца. Пулам со `Steal` (стрелки F1, титулы F10) аренду передавать обязательно, а `OnSteal` — чтобы прежний владелец забыл ссылку. `Release(obj)` без номера освобождает всегда.

### Perf.Lod

```lua
local handle = Lod.Register(model, {
	Near = 80, Far = 200,  -- по умолчанию Quality.Budget("LodNear"/"LodFar")
	Radius = 6, Cull = true,
	Position = function() return slot.Position end, -- необязательно; так можно регистрировать «слот» без модели
	OnLevel = function(level, handle) end,          -- 0 = полная детализация, 1 = упрощённая, 2 = далеко / скрыто
})
handle.Level; handle:SetRange(near, far); handle:Destroy()
```

* Проверка 5 Гц через `Scheduler`, проход нарезается по времени.
* `OnLevel` вызывается в своём потоке (`task.spawn`): обработчик, который ждёт (строит модель, грузит ассеты), не тормозит проход и не ломает очередь. После ожидания проверяйте `handle.Level` — уровень мог уже смениться.
* Цель-Instance снимается с учёта сама, когда её уничтожают (`Destroying`); `handle:Destroy()` по-прежнему лучший способ.
* Гистерезис ±10 %: граница пересекается наружу только за порогом ×1,1, обратно — внутри порога ×0,9.
* `Cull = true`: объект вне пирамиды камеры и дальше `Near` считается уровнем 2. Логика угла та же, что `viewHalfAngle` в `DogAnimations`.
* За тик применяется не больше `Lod.MaxSwitches` (8) смен уровня, ближние первыми, плюс до `Lod.MaxInitial` (64) первых назначений.
* **Без кода — тегом.** Модель или деталь с тегом `DOGROTS_Lod` (Builder ставит его по `opts.Lod`). Атрибуты `LodNear`, `LodFar`, `LodCull` переопределяют значения по умолчанию. На уровне 1 скрываются потомки с `LodDetail = true`, на уровне 2 — всё, кроме `LodKeep = true` (дальний силуэт). Скрытие — через `LocalTransparencyModifier`. На корень пишется атрибут `LodLevel` (0 / 1 / 2).
* **Только Workspace.** Тег учитывается только у моделей в Workspace и не внутри ViewportFrame / WorldModel: шаблон в ReplicatedStorage и клон в превью (инвентарь, выбор для витрины) LOD не трогает, хотя `Clone()` копирует тег. Модель, которая переехала в Workspace или из него, подключается или отпускается сама; отпущенная показывается целиком.
* **Свет и эффекты в `FXManaged`-модели.** Когда их деталь скрыта, Lod выключает свет, эмиттеры, лучи и GUI и запоминает прежнее `Enabled`; когда деталь снова видна — возвращает, если владелец не включил их сам за это время. Пока деталь видна, Lod их не трогает, так что решения владельца по бюджету не откатываются. Владелец, который меняет эффекты, пока модель скрыта, сверяется с `LodLevel`. В моделях без `FXManaged` эффекты не трогаются (ими владеет `WorldDetailQuality`).

### Perf.Maid и Perf.Signal

`Maid.new()`, `:Give(connection | instance | function | thread | tween | объект с Destroy/Disconnect/Cancel)`, `:Connect(signal, fn)`, `:Set(key, item)` (слот по ключу: прежний предмет убирается), `:Clean()` / `:Destroy()`. `Signal.new()`, `:Connect`, `:Once`, `:Fire`, `:DisconnectAll`. Kit пользуется теми же модулями.

### WorldDetailQuality, PlotSkinMotion и телефоны

* **`FXManaged = true`** на источнике света, эмиттере или любом предке — WDQ его не трогает: не гасит, не урезает `Rate`, не выключает тени. Так новые эффекты (колба, витрина, декор) не гаснут молча. Фича, которая ставит `FXManaged`, сама соблюдает бюджеты `Quality` и заявляет свою долю (`Quality.Claim`). Прежние исключения (`LuckyVisual`, `MuseumLight`) остались.
* Бюджеты WDQ берутся из `Quality`: `Lights` и `Particles` — остаток после заявок (`Available`), `LightRadius`, `EmitterRate`, `EmitterRadius`. При уменьшении движения действует бюджет Low, как и раньше. И свет, и эмиттеры получают бюджет от ближних к дальним (туман своего участка не гаснет из-за дальних). Свойства пишутся, только когда значение меняется.
* **Спор за `PlotMist` устранён.** Владелец всех эмиттеров района — WDQ. `PlotSkinMotion` больше не включает и не выключает `PlotMist` (раньше 30 раз в секунду, поверх бюджета), а только качает `PlotFloat`.
* **Телефоны.** `WorldEventController` больше не ставит свой `WorldEventFX` по умолчанию: уровень даёт `Quality` (тач без клавиатуры → Medium). `VoidAtmosphere` читает `Quality.Tier()` и `Quality.Reduced()`, ветки «`WorldEventFX == nil` и `TouchEnabled`» больше нет.
* PAWPAD «Motion» переключает общий атрибут `ReducedMotion` (а не свою локальную копию).

### World.Spec и World.Builder — мир из спецификаций

Спецификация — простая таблица: `Class` (`Part`, `WedgePart`, `CornerWedgePart`, `TrussPart`), `Shape` (`Block`, `Ball`, `Cylinder`), `Name`, `Size`, `CFrame` (относительно якоря), `Color`, `Material` (имя `Enum.Material`), `Transparency`, `Reflectance`, `CastShadow`, `CanCollide`, `CanQuery`, `CanTouch`, `Tags`, `Attributes`, `Props`, `Children`. Дети — свет, эмиттеры, вложения, лучи, SurfaceGui с надписью; enum-свойства можно задавать именем (`Face = "Front"`). Луч ссылается на вложения по имени.

```lua
local S = require(ReplicatedStorage.World.Spec)
local base = S.Block("Base", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), S.Mat("Marble", WHITE))
local lamp = S.Ball("Lamp", 1.5, CFrame.new(0, 6, 0), S.Neon(GOLD, { Children = { S.PointLight({ Range = 14 }) } }))
local posts = S.Ring({ S.Cylinder("Post", 5, 0.6, CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.pi / 2)) }, 6, 3.5)
local specs = S.Concat({ base, lamp }, posts, S.MirrorX(leftDecor))
S.PartCount(specs); S.Count(specs); S.Bounds(specs); S.Validate(specs)
```

* **Детали:** `Part`, `Block`, `Ball` (диаметр), `Cylinder` (длина по оси X, как в Roblox), `Wedge` (высокая сторона сзади, +Z), `CornerWedge` (вершина в углу +X +Y −Z), `Truss`.
* **Материалы:** `Mat`, `Neon`, `Glass`, `Metal`, `ForceField`.
* **Дети:** `PointLight`, `SpotLight`, `SurfaceLight`, `Emitter`, `Attachment`, `Beam`, `Label`, `Child`.
* **Преобразования** (возвращают новые списки): `Offset`/`Transform`, `Rotate`, `MirrorX`, `Array`, `Ring`, `Arc` (`Face = "Out" | "In" | "Fixed"`), `Concat`, `Flatten`, `With`, `Merge`.
* **`MirrorX` точный и для детей.** У угловых клиньев поворот на 90° и обмен X/Z. `CFrame` / `Position` детей (вложения) отражаются в системе детали, а грани `Face` и `EmissionDirection` (таблички, SurfaceLight, SpotLight, эмиттеры) меняются Left ↔ Right, так что отражённая табличка смотрит наружу.
* **Запросы:** `Bounds`, `PartCount`, `Count` (детали, свет, эмиттеры, лучи…), `Validate`.
* **Детерминированный генератор** `Rng(seed)` даёт одинаковые числа в Lune и в Roblox.

```lua
local Builder = require(ReplicatedStorage.World.Builder)
local model = Builder.Build(specs, anchorCFrame, {
	Name = "Stand", Parent = folder, BuilderId = "Showcase", LayoutVersion = 3,
	StreamingMode = "Atomic", PersistentPlayer = player, FXManaged = true,
	Lod = { Near = 80, Far = 200 }, Attributes = { Owner = userId },
})
local model, rebuilt = Builder.EnsureBuilt(parent, "MiningCorner", 24, function()
	return Builder.Build(layout(), anchor, { BuilderId = "MiningCorner" }) -- без Parent
end)
-- то же по кусочкам (декор участка, уровень шахты): детали, пока не вышло время кадра
local build = Builder.Begin(specs, anchor, options)
Scheduler.Every(0, "Decor.Build", function(_, deadline)
	local done, model = build:Step(deadline) -- модель готова и стоит в Parent, только когда done
	return not done
end)                                         -- build:Cancel() — бросить и удалить
```

* Модель собирается отдельно от мира и ставится в `Parent` одним действием. `WorldPivot` = якорь. Атрибуты `BuilderId`, `LayoutVersion`, `PartCount`.
* Режим стриминга и `AddPersistentPlayer` ставятся в `pcall`, как в `MiningWorld`; `AddPersistentPlayer` работает только на сервере.
* По умолчанию детали `Anchored`, `CanCollide`/`CanQuery`/`CanTouch = false`, если спецификация не просит иного.
* `CastShadow`, если он не задан: выключен у Neon, Glass, ForceField, у деталей прозрачнее 0,5 и у деталей меньше 4 стадов по всем осям. В плейсе уже около 12 800 видимых деталей с тенью.
* `EnsureBuilt` переиспользует ребёнка с той же `LayoutVersion`, иначе строит заново. Все остальные дети с этим именем (старые версии, дубликаты) уничтожаются. `LayoutVersion` модели всегда равна аргументу `version` (если `buildFn` поставил другую — `warn`), поэтому повторные вызовы не перестраивают модель.
* **Лучи** ищут вложения по имени сначала в своей верхней детали, потом во всей сборке (с `warn`, если имя не уникально). Поэтому копии из `Array` / `Ring` / `Arc` / `MirrorX` соединяются каждая со своими вложениями.
* **Большие сборки на клиенте** (декор до 300 деталей на участок, уровень шахты до 400, несколько участков при входе) — через `Builder.Begin` и задачу планировщика, а не одним `Build`: так соблюдается общий бюджет 1 мс на задачу.

Раскладки фич — чистые модули `ReplicatedStorage/<Feature>/<Feature>Layout.luau`, которые возвращают спецификации. Их проверяют в Lune (бюджет деталей, границы, детерминизм) и смотрят через `tools/preview`.

### tools/preview — посмотреть раскладку без Studio

```sh
cd tools/preview && npm install    # один раз: three + playwright-core (node_modules в .gitignore)
# из корня репозитория:
lune run tools/preview/export.luau tools/preview/out/stand.json --file tools/preview/samples/stand.luau
lune run tools/preview/export.luau out.json --module ReplicatedStorage.Lab.FlaskLayout --call Build --args '[2]'
lune run tools/preview/export.luau out.json --place build/DOGROTS_MINING.rbxl --path "Workspace/DOGROTS_District/05_MutationLab" --max 20000
node tools/preview/render.mjs tools/preview/out/stand.json tools/preview/out/stand --angles iso,front,top,close
```

* **Источники.** Функция модуля из `src`, файл Luau, JSON со спецификациями или все видимые детали под путями плейса. MeshPart и Union рисуются ограничивающим боксом, полупрозрачно.
* **Сцена.** Студийный свет, мягкие тени, сетка 4 стада.
* **Материалы.** Neon светится с bloom, Glass прозрачное и глянцевое, металлы отражают. У остальных материалов передаются цвет и шероховатость.
* **Камеры:** `iso`, `front` (смотрит на грань −Z), `back`, `side`, `top`, `close`. Кадр подгоняется под границы.

Примеры: `docs/img/overhaul/preview_sample_stand.png` (стенд из `Spec`) и `preview_sample_place.png` (NPC из плейса: его скосы из клиньев подтверждают ориентацию `WedgePart`). Подробности: `tools/preview/README.md`.

### UISound — звуки интерфейса

```lua
local UISound = require(ReplicatedStorage.UISound)
UISound.Play("Success")
UISound.Play("Coin", { Pitch = 1.2, Volume = 0.8, Bus = "SFX", From = guiObject })
local binding = UISound.Bind(button)                   -- наведение + нажатие; binding:Disconnect()
UISound.Bind(button, { Hover = "Hover", Press = false })
UISound.Start()                                       -- клиент: громкость из настроек → шины (PerfBootstrap)
```

* **Сигналы:** `Hover`, `Press`, `Open`, `Close`, `Tab`, `Toggle`, `Success`, `Error`, `Reward`, `Coin`, `Whoosh`, `Pop`, `Rare`, `Epic`, `Legendary`, `Countdown`, `Lock`. Они собраны из встроенных звуков движка, которые проект уже использует (`volume_slider.ogg`, `collide.wav`, `electronicpingshort.wav`, `swordslash.wav`, `action_jump_land.mp3`; как в `MiningAudio`, `LabAudioConfig`, `LuckyAudio`), слоями с разной высотой. Владелец может загрузить свои звуки и прописать `UISound.AssetIds[cue] = id` (0 = встроенный рецепт).
* **Пул:** не больше 6 звуков одновременно. Наведение никогда не обрывает другой звук; важные сигналы (`Success`, `Reward`, `Legendary`…) могут забрать самый старый голос того же или меньшего приоритета. У каждого сигнала своя пауза: спам наведением не слышен.
* **Шины.** `ServerScriptService.AudioBootstrap` создаёт `SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient}`; `Music` и `WorldEvents` уже есть в плейсе. Туда же сами попадают звуки `RewardAudio`, `WorldSound`, `LabAudioConfig` и музыка `WorldAmbience`, которые раньше шли мимо шины. На клиенте `UISound.Start()` (его вызывает `PerfBootstrap` при входе) сразу ставит громкость групп UI и SFX из атрибутов `Setting_UIVolume` / `Setting_SFXVolume` (0…1, по умолчанию 1) и следит за изменениями атрибутов и за группами, которые реплицируются позже. Так ползунки F2 работают и для звуков, которые сами идут в шину (лаборатория в SFX, награды и звуки мира в UI), даже если ни один сигнал UISound ещё не играл. Если группы ещё нет, сигнал всё равно играет, а громкость настройки применяется к самому звуку. Приглушение музыки во время секретных сцен (`SecretArrivals/Kit`) не трогает шины UI и SFX.
* **Kit.** `Kit.Button` звучит при наведении и нажатии; кнопка с удержанием — в начале и в конце удержания. `Sound = true` или не задан — сигналы по умолчанию, `false` — без звука, `{Hover = cue | false, Press = cue | false}` — свои сигналы (и для кнопки с удержанием). `Kit.Window` звучит при открытии и закрытии; `Sound = false` ставит на окно атрибут `UISoundOff`, и замолкает всё внутри. `Kit.Tabs` звучит при смене вкладки. Атрибут `UISoundOff = true` на любом GUI-предке глушит поддерево.

### Kit: токены, движение, иконки

* **`Kit.Theme`, только добавления:**
  * `Space` (XXS 2 … XXL 32);
  * шкала `Radius` (XS 4 … XL 18; совпадает с Small, Button, Card, Window);
  * `IconSize` (XS 14 … Hero 72);
  * `Elevation` (Flat, Low, Mid, High: смещение и прозрачность тени) и `ShadowColor`;
  * новые длительности `Motion` (Hover, Pop, Toast, Stagger, Celebrate);
  * `Easing` (Standard, Enter, Exit, Emphasis, Linear).

  Прежние значения не менялись (это проверяет `tests/uikit.luau`).
* **`Kit.Motion.Reduced()`** учитывает `Perf.Quality.Reduced()`, то есть настройку Roblox, `Setting_ReducedMotion` и PAWPAD. `Motion.Override` по-прежнему главнее.
* **`GameIcons.Glyph(name[, group])`** — глифы, которые Roblox рисует без загрузки:
  * редкость: Common ● … Secret ❖; это простые фигуры, их окрашивает `TextColor3`;
  * классы находок: Treasure, Artifact, Special, Secret, World Find;
  * действия: продать, избранное, замок, обмен, витрина, мутация, маршрут, глаз и скрыть, настройки, фильтр, сортировка, поиск, закрыть, назад и другие;
  * места: лаборатория, магазин, музей, участок, шахта, ивенты.

  Неизвестное имя даёт `GameIcons.GlyphFallback` («•»). Регистр не важен, есть псевдонимы (`Favorite`, `Show`, `Mining`…). `Kit.Icon` с ключом без картинки показывает этот глиф вместо «★». Прежние экспорты `GameIcons` не менялись.

### Уборка

* `StarterPlayerScripts/LocalScript` — отладочный остаток: печать локали, перезапись всех надписей «DOGS», вызов `GetTranslatorForLocaleAsync` без `pcall`. Заменён заглушкой `-- retired`; файл нельзя удалить, иначе сборка вернёт копию из базы.
* **`DOGROTS_AutoTranslateUI`:**
  * Кэш облачного переводчика ограничен: два поколения по 1000 строк (≈LRU на 2000).
  * Добавлен такой же ограниченный кэш итогов `translateUI`. Повторный текст больше не проходит заново ~550 шаблонов и фраз.
  * Оба кэша очищаются при смене локали. Кэш итогов очищается ещё раз, когда переводчик загрузился: надписи, изменившиеся во время загрузки, не застревают без облачного перевода.
  * Поведение не изменилось: старый и новый скрипт на 7 392 строках (словари, динамические фразы, 5 000 уникальных цен), по три прохода, дали 22 176 одинаковых результатов.

### perf-lint

`tests/perf_lint.luau` проверяет каждый файл в `src/StarterPlayer`, `src/StarterGui` и `src/ReplicatedStorage`:

* подключения `RenderStepped`, `Heartbeat`, `Stepped`, `PreSimulation`, `PostSimulation`, `PreRender`, `PreAnimation` (`:Connect`, `:ConnectParallel`) и `BindToRenderStep`;
* `DescendantAdded` по всему Workspace, в том числе через псевдонимы и через циклы по списку `{gui, workspace}`.

Сегодняшние нарушители записаны в `BASELINE` (файл → число), поэтому существующий код проходит. Новое нарушение роняет тест с подсказкой: `Perf.Scheduler.Every` или теги CollectionService. Если файл стал чище, тест просит уменьшить число. `Perf/Scheduler` разрешён. Текущие числа печатает `lune run tests/perf_lint.luau --report`.

### Что изменено в плейсе

* **Новые скрипты:**
  * `ReplicatedStorage/Perf/{Quality,Scheduler,Pool,Lod,Maid,Signal}`;
  * `ReplicatedStorage/World/{Spec,Builder}`;
  * `ReplicatedStorage/UISound`;
  * `StarterPlayerScripts/PerfBootstrap`;
  * `ServerScriptService/AudioBootstrap`;
  * `ScreenGui/Modules/Kit/Sound`.
* **Изменённые скрипты:**
  * `WorldDetailQuality`, `PlotSkinMotion`, `WorldEventController`, `VoidAtmosphere`;
  * `PawpadRuntime`, `SecretArrivals/Kit`;
  * `Kit/{Maid,Signal,Motion,Button,Window,Controls,Theme,Base}`;
  * `GameIcons`, `DOGROTS_AutoTranslateUI`;
  * `LocalScript` (заглушка).
* **Во время работы появляются:**
  * группы звука `UI`, `SFX`, `Ambient` в `SoundService.DOGROTS_AUDIO`;
  * атрибуты игрока `LowFX`, `WorldEventFX`, `ReducedMotion`;
  * атрибут `LodLevel` на моделях с тегом `DOGROTS_Lod`;
  * 6 объектов `Sound` с именем `DOGROTS_UISound` в `SoundService` (пул).

### Чек-лист для Studio (клиентская часть)

1. **Play Solo.** Убедиться, что:
   * у игрока есть атрибуты `WorldEventFX` (High на ПК), `LowFX = false` и `ReducedMotion`;
   * в `SoundService.DOGROTS_AUDIO` есть группы `UI`, `SFX` и `Ambient`.
2. **PAWPAD → «World Event FX».** Уровень меняется по кругу High → Medium → Low; при Low `LowFX = true`; идущий ивент перезапускается с новой плотностью эффектов. Сторож FPS (например, в эмуляторе слабого устройства) идущий ивент не перезапускает.
3. **PAWPAD → «Motion».** Окна Kit открываются без анимации; повторное нажатие возвращает анимацию. То же при включённом «Уменьшении движения» в настройках Roblox: первое нажатие возвращает анимацию.
4. **Эмуляция телефона (Device Emulator).** После входа `WorldEventFX = Medium`; источников света вокруг не больше 16.
5. **MicroProfiler (Ctrl+F6).** Видны метки `Perf:WorldDetailQuality`, `Perf:PlotSkinMotion`, `Perf:Quality.Watchdog`, `Perf:Lod`, у новых фич — `Perf:<name>`. Ни одна не держит больше ~1 мс в кадре.
6. **Окно Kit (`KitDemo = true`).**
   * Наведение и нажатие кнопок дают тихий щелчок; при открытии и закрытии окна и при смене вкладки тоже есть звук.
   * Спам наведением не трещит.
   * Атрибут игрока `Setting_UIVolume = 0` (вручную в Studio или из окна настроек F2) глушит звуки UI, `1` возвращает их.
   * Сразу после входа, ничего не нажимая: `Setting_SFXVolume = 0.2` делает тише звуки лаборатории (группа `DOGROTS_AUDIO/SFX` получает `Volume = 0.2`).
7. **Участок с туманом `PlotMist`.** Туман не мигает. При Low эмиттеров вокруг почти нет.
8. **Memory (F9 → Memory).** После долгой игры на русском `LuaHeap` не растёт без конца: кэши AutoTranslate ограничены.

### Проверки

`tools/check.sh` — сборка, verify, все `tests/*.luau` (в том числе `perf`, `world`, `ui_assets`, `perf_lint`, `uikit`) и luau-lsp без новых диагностик.
