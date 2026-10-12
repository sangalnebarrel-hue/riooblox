# DOGROTS UI kit (`StarterGui.ScreenGui.Modules.Kit`)

One look and one behaviour for every new or reworked screen: Lab, upgrade tree, equipment shop,
dog artifacts, Dogdex, item collection, trades, showcase editor, decor placement and events.
Client-only. Source: `src/StarterGui/ScreenGui/Modules/Kit.luau` and `Kit/*.luau`.

```lua
-- From a module in ScreenGui.Modules:  local Kit = require(script.Parent.Kit)
-- From StarterPlayerScripts:
local gui = game.Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
local Kit = require(gui:WaitForChild("Modules"):WaitForChild("Kit"))

local win = Kit.Window.new({
	Key = "Lab", Title = "GENETICS LAB", Subtitle = "Discover new possibilities",
	Accent = Kit.Theme.Colors.purple, Icon = "Lab",
	Tabs = { { Id = "dogs", Text = "DOGS" }, { Id = "recipes", Text = "RECIPES" } },
})
local grid = Kit.CardGrid(win:Page("dogs"), {
	Kind = "Dog",
	Map = function(dog) return { Id = dog.DogUid, Name = dog.DisplayName, Rarity = dog.Rarity,
		Preview = { Kind = "Dog", DogId = dog.DogId, Variant = dog.Variant } } end,
	OnClick = function(dog) print("picked", dog.DogUid) end,
})
grid:SetItems(dogs)
win:Open()
```

Studio demo of every component: set the workspace attribute `KitDemo = true` and press Play
(`StarterPlayerScripts.KitDemo`, Studio only; **K** toggles it).

## Rules

1. **Build once, update in place.** A kit window is persistent. Create it the first time it is
   needed, keep the object, and update labels / call `grid:SetItems()` when data changes.
   Never clear and rebuild the window on a poll: that is what `Modules.Menus` does every 5 s,
   and it is the reason big screens there are slow.
2. **Kit windows live in their own ScreenGui layers** (`KitWindows` 60, `KitModals` 62,
   `KitOverlay` 95). They are not part of `MainWindow`. Do not parent kit controls under the
   main `ScreenGui`: its `ApplyStandalone` forces FredokaOne on every label there, which
   overrides the numeric font. Kit buttons are transparent hit targets with a `Face` frame, so
   its `EnhanceButton` leaves them alone.
3. **Text.** Components take strings that are already localized.
   * Words in the base dictionary or in `ReplicatedStorage.Localization.<Feature>.luau` can be
     passed in English: `DOGROTS_AutoTranslateUI` translates them for Russian players.
   * Self-localized strings use `Kit.T("BUY", "КУПИТЬ")`. Pass `NoTranslate = true` on labels that
     only show such text or numbers.
   * Kit words (`Kit.Word("CANCEL")`, `SEARCH`, `SORT`, `HOLD TO CONFIRM`, ...) are English and
     translated by AutoTranslate. `tests/uikit.luau` checks that every kit word has an entry.
   * Labels using `Theme.FontNumeric` get the `KeepFont` attribute (PlaceTypography skips them).
4. **Phones.** Every window works at 360x640 portrait, 812x375 landscape and desktop. On a
   phone a window is a full-screen sheet inside the safe area. Re-arrange toolbars in
   `win.Resized` (see the example below). `CardGrid` switches to list rows by itself.
5. **Performance.** Lists over ~30 entries use `VirtualGrid` / `CardGrid`. 3D previews only
   come from `Kit.Preview` (cards do this). Give every connection you make to `win.Maid` or
   `component.Maid`. The kit runs no per-frame loop while idle: only active tweens, the preview
   build queue and the shared 1 Hz countdown ticker run, and each stops when it has no work.
6. **ZIndex.** Inside a window body use `ZIndex >= 3`. Every component accepts `ZIndex`.

## Navigation (how the game knows a menu is open)

* `win:Open()` of a base window calls `GUIIntegration.N.Acquire("Kit", Key)`. Then:
  `N.Owner == "Kit"`, the attributes `OpenMenu = Key` and `MenuFamily = "Kit"` are set on the
  main ScreenGui, the HUD and every other menu hide, and movement and ProximityPrompts lock.
  Mining, Gym, LuckyReel, CommunityServices, event notices and the onboarding guide react to
  `OpenMenu` as for any menu. The main GUI backdrop is hidden because the kit dims the screen
  itself.
* Closing (X, Escape, `win:Close()`) calls `N.Close()` when the kit still owns navigation.
* When navigation moves elsewhere (another menu, `N.OpenScreen`, a reward, respawn), the kit
  windows close. You do not need to watch `OpenMenu` yourself.
* Only one kit window is open at a time: opening another window replaces the current one.
  `Stack = true` opens a window over the current one (details, pickers). Closing it returns to
  the window below.
* **Escape** goes through `N.DismissDialog()`, which the kit wraps. It closes the top kit
  dropdown or modal first, then a stacked window, then the base window. **Gamepad B** does the
  same. `NoNavigation = true` windows leave GUIIntegration alone (tools).
* Pick `Key` = the page name your screen replaces (`"Lab"`, `"Trade"`, `"Events"`...), so the
  sidebar highlight follows. Existing code that compares `OpenMenu` with a fixed value:
  `RewardScreens` (`"RewardMachine"`), `LuckyReel` (`"Reward"`), `LuckyBlockUI` (its page),
  `LabScreen` (`"Lab"`, redraw only, harmless). To route `N.OpenPage("Lab")` to a kit window,
  change the routing in `GUIIntegration.OpenPage` to call your module's `Open()`.

## Window

```lua
local win = Kit.Window.new({
	Key = "Trade",             -- OpenMenu value (default: Title)
	Title = "TRADE", Subtitle = "Swap with players in this server",
	Accent = Color3.fromRGB(41, 204, 168), Icon = "Trade",   -- UITheme.WindowSpecs colours fit
	Tabs = { { Id = "offer", Text = "OFFER" }, { Id = "history", Text = "HISTORY", Badge = 2 } },
	Tab = "offer",             -- initial tab
	MaxSize = Vector2.new(1040, 760),  -- desktop card limit (default)
	Stack = false, NoNavigation = false,
	Sound = true,              -- false: no open / close / button sounds in this window (UISoundOff)
	OnOpen = function(win) end, OnClose = function(win, reason) end,
})
local page = win:Page("offer")      -- a frame visible only on that tab (or win.Body without tabs)
win.Resized:Connect(function(layout) -- {Phone, Landscape, Touch, Width, Height, Window, Safe}
	toolbar.Size = layout.Phone and UDim2.new(1, 0, 0, 84) or UDim2.new(1, 0, 0, 42)
end)
win:Open(); win:Close(); win:Toggle(); win:Destroy()
win:SetTitle("TRADE WITH @bob", "Both players must confirm"); win:SetAccent(color)
win:SetTab("history"); win:SetBadge("history", 3); win:GetLayout()
```

Fields and signals: `win.Body`, `win.IsOpen`, `win.Tab`, `win.Maid` (cleaned on Destroy),
`win.Opened`, `win.Closed(reason)`, `win.Resized(layout)`, `win.TabChanged(id)`.
Module: `Kit.Window.Top()`, `Kit.Window.Count()`, `Kit.Window.CloseAll(reason)`.
The window animates in about 0.18 s: the backdrop fades, the card scales up from 0.94 and fades
in. It closes in 0.14 s. With reduced motion (Roblox's setting, the in-game setting or PAWPAD's
Motion toggle through `Perf.Quality`, or `Kit.Motion.Override = true`) both are instant.
Opening and closing play the `Open` / `Close` interface sounds (see Sounds below).

## Controls

Every constructor is `Kit.X(parent, props)` and returns an object with `.Instance` (its root
GuiObject) and `:Destroy()`. `Size`, `Position`, `AnchorPoint`, `LayoutOrder` and `ZIndex` are
accepted everywhere.

```lua
local buy = Kit.Button(page, { Text = "BUY", Style = "success", Price = 125000, -- price chip "125K"
	Size = UDim2.fromOffset(200, 46), OnClick = function() ... end })
-- Style: "primary" | "secondary" | "danger" | "ghost" | "success" | "gold"; Color overrides.
-- Icon = "Shop" (icon key or asset id), PriceIcon = "Bones", PriceText = "FREE", Disabled = true,
-- Hold = 1 (seconds to hold before OnClick: hold-to-confirm).
-- Sound = true / nil (default cues), false (silent) or { Hover = "Hover", Press = "Press" }
-- (UISound cue names or false; a hold button plays its Press cue when the hold starts).
buy:SetBusy(true)   -- pulsing dots, clicks ignored (use while a request is in flight)
buy:SetDisabled(true); buy:SetText("OWNED"); buy:SetStyle("secondary"); buy:SetPrice(nil)

local search = Kit.SearchBox(page, { Placeholder = Kit.Word("SEARCH"), Debounce = 0.25,
	OnChange = function(text) refilter() end })        -- debounced while typing, instant on Enter
search:GetText(); search:SetText("", true --[[silent]])

local chips = Kit.Chips(page, { Multi = true, Options = {
	{ Id = "Legendary", Text = "LEGENDARY", Color = Kit.Theme.RarityColor("Legendary") } },
	OnChange = function(selected) end })  -- Multi: array of ids; single: id or nil (AllowNone = false to forbid nil)

local sort = Kit.SortSelect(page, { Options = { { Id = "rarity", Text = "RARITY" },
	{ Id = "name", Text = "NAME", Descending = false } }, Selected = "rarity",
	OnChange = function(id, descending) end }) -- dropdown + direction arrow; sort:Set(id, desc, silent)

local tabs = Kit.Tabs(page, { Tabs = { { Id = "a", Text = "A" } }, OnChange = function(id) end })
```

## Display

```lua
Kit.RarityTag(parent, "Legendary")          -- gradient for Legendary / Mythic / Secret; :SetRarity(r)
Kit.VariantTag(parent, dog.Variant)         -- hidden for Normal; :SetVariant(v)
Kit.MutationTag(parent, item.Mutation)      -- hidden for NORMAL; :SetMutation(m)
Kit.Pill(parent, { Text = "NEW", Color = Kit.Theme.Colors.green })   -- :Set(text, color), :SetVisible(b)
Kit.Badge(parent, { Text = "3" })           -- small counter
local bar = Kit.ProgressBar(parent, { Value = 0.35, Text = "35 / 100", Color = Kit.Theme.Success })
bar:SetValue(0.5)                           -- tweens; bar:SetValue(0.5, true) is instant
local row = Kit.StatRow(parent, { Label = "DIG SPEED", Value = 12, Next = 15, Format = "short", Icon = "Dig" })
-- "12  → 15  (+3)", green if better (HigherIsBetter = false for cooldowns); row:Set(value, next)
-- Format: "short" | "number" | "percent" | "mult" | "duration" | "clock" | function(v) -> string
Kit.Countdown(parent, { EndsAt = event.EndsAt, Prefix = Kit.T("ENDS IN ", "ДО КОНЦА "),
	Style = "clock", OnDone = function() end })  -- server clock, 1 Hz, no polling; :SetEndsAt(t)
Kit.EmptyState(parent, { Icon = "Dogs", Title = Kit.Word("NO_RESULTS"), Body = Kit.Word("TRY_FILTERS"),
	ActionText = "SHOW THE WAY", OnAction = fn })
```

## Feedback

```lua
Kit.Toast("Saved!", { Kind = "success" })  -- "info" | "success" | "warn" | "error"; never blocks input
-- At most 3 toasts are visible; the rest wait in a queue. Repeating the text of a visible toast shows "×2".

Kit.Tooltip(button.Instance, "Dig speed of all your dogs", { Title = "DIG" })
-- mouse hover (0.35 s), gamepad selection, touch long-press; content can be function() -> body, title
local press = Kit.LongPress(card, function() showDetails() end)  -- touch hold 0.45 s or right click
if press.Consumed() then return end      -- in the click handler: ignore the click after a long press

local ok = Kit.Confirm("BUY 5 TREATS?", "+10% dig speed for 10 minutes."):Await()   -- yields
Kit.Confirm("RELEASE 3 DOGS?", "They leave forever.", {
	Danger = true,                -- red, hold-to-confirm 1 s (Hold = seconds to change, 0 = off)
	Cards = { dogCardData1, dogCardData2, dogCardData3 }, CardKind = "Dog",  -- what will be lost
	ConfirmText = "RELEASE",
}):Then(function(confirmed) if confirmed then send("Release", uids) end end)
Kit.Alert("SAVED", "Your showcase layout was saved.")
-- Kit.Modal(props): Title, Body, Cards, CardKind, Content = function(frame, width) end,
-- ContentHeight, ConfirmText, CancelText, Danger, Hold, ConfirmStyle, NoCancel, Accent, Width.
-- The result object: :Then(fn), :Await(), :Cancel(), .Done, .Result. Cancel, the backdrop,
-- Escape / B and the owning window closing all resolve false.
```

## Virtual lists and cards

`Kit.VirtualGrid` creates cells only for what is on screen, plus one row above and below, and
recycles them while scrolling. Cells are keyed by item id, so `SetItems` with fresh data keeps
the cell, and the 3D preview, of every item that stays visible, and keeps the scroll offset.
The number of instances depends on the viewport, not on the data (tested with 500 items).

```lua
local grid = Kit.VirtualGrid(page, {
	CellSize = Vector2.new(160, 90),  -- min cell width x row height, or function(viewW, viewH) -> Vector2
	Gap = 10, Padding = 10, MaxColumns = nil, Columns = nil,
	Create = function(frame) return buildRow(frame) end,          -- once per pooled cell
	Bind = function(cell, item, index) cell.Label.Text = item.Name end,
	Unbind = function(cell, item) end, Layout = function(cell, w, h) end,
	Key = function(item) return item.Uid end,   -- default: Id / Uid / DogUid / ItemUid / Key
	Empty = { Title = Kit.Word("NO_RESULTS") }, -- EmptyState props shown for an empty list
})
grid:SetItems(list)                        -- keeps the scroll offset
grid:SetItems(filtered, { ResetScroll = true })  -- a new filter: back to the top
grid:SetItems(live, { Anchor = true })     -- items inserted above: the first visible item stays put
grid:RefreshKey(uid)                       -- re-bind one visible item (selection toggled)
grid:Refresh(); grid:ScrollToKey(uid, true); grid:ForEachVisible(fn); grid:GetStats()
Kit.VirtualList(page, { RowHeight = 64, Create = ..., Bind = ... })  -- one column
```

**Cards.** `Kit.CardGrid(parent, props)` is a `VirtualGrid` of `DogCard` / `ItemCard` cells. On
narrow screens (`ListBelow`, default 500 px) or when the view is too short for cards (landscape
phones), it shows compact list rows instead.

```lua
local grid = Kit.CardGrid(page, {
	Kind = "Dog",                      -- or "Item"
	Map = function(dog) return cardData end,  -- default: items are card data already
	OnClick = function(dog, index, card) end, OnLongPress = function(dog, index, card) end,
	CardSize = Vector2.new(156, 206), RowHeight = 76, RowMinWidth = 300, ListBelow = 500,
})
```

Card data (all optional except `Id`):

| Field | Meaning |
|---|---|
| `Id` | stable key (dog uid, item uid, species id) |
| `Name`, `Subtitle` | title; the subtitle shows in list rows without stats |
| `Rarity` | `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic`, `Secret`: tag, glow and border colour |
| `Preview` | `{Kind="Dog", DogId, Variant, Silhouette}`, `{Kind="Item", ItemId, Mutation, Silhouette}`, `{Kind="Image", Image}` or a registered kind |
| `Variant` / `Mutation` | the tag (Normal / NORMAL hidden); `Tag`, `TagColor` override it |
| `Stats` | up to 3 chips: `{ {Text = "⛏ 1.2/s"}, {Text = "x1.3", Color = c} }` |
| `Count` | owned copies, `×N` badge when > 1 |
| `Badge`, `BadgeColor` | corner pill (`"NEW"`) |
| `Selected` | accent border and a check mark |
| `Disabled`, `DisabledReason` | white veil; clicking shows the reason as a toast instead of OnClick |
| `Locked` | dark veil with a lock |

For a single card outside a grid: `local card = Kit.DogCard.new(frame); card:Layout(w, h); card:Bind(data)`.

**Previews (`Kit.Preview`).** Cards create a ViewportFrame only while they are bound to a
visible cell. Showing the same key again does nothing, so nothing is re-cloned on a rebind.
Previews that leave the screen are parked on a hidden shelf (up to `Preview.MaxFree = 48`) and
reused by the next card with the same key. New previews are built at most
`Preview.PerFrame = 2` per frame. Dogs use `Modules.PreviewRenderer` (MenuModels, variant tint,
idle pose). Items use `DogEconomy.DiscoveryVisuals`. To add a kind (accessories, decor):

```lua
Kit.Preview.Register("Decor", function(spec, parent)
	local view = Instance.new("ViewportFrame") ... ; view.Parent = parent; return view
end, function(spec) return spec.DecorId end)
-- then card data Preview = { Kind = "Decor", DecorId = "lamp" }
```

`Kit.Preview.Slot(holderFrame)` gives the same caching to any frame (`:Show(spec)`, `:Clear()`).
`Kit.Preview.Purge()` drops the shelf (call it when a big screen closes and memory matters).

## Tokens and helpers

* `Kit.Theme`: `Font` (FredokaOne), `FontNumeric` (BuilderSans Bold), `Colors` (same keys as
  `UITheme.U.Colors`), `Surface`, `Backdrop`, `Ink`, `InkMuted`, `Accent`, `Success`, `Danger`,
  `Warning`, `Rarity`, `ItemRarity`, `RarityGradient`, `Variant`, `Mutation`, `Icons`, `Radius`,
  `TextSize` / `TextSizeCompact`, `Motion` (durations), `Layer`, and the scales `Space`
  (XXS 2 … XXL 32), `Radius` XS…XL (4 / 8 / 12 / 14 / 18, the same values as Small / Button /
  Card / Window), `IconSize` (XS 14 … Hero 72), `Elevation` (Flat / Low / Mid / High: shadow
  `Offset`, `Transparency`) with `ShadowColor`, extra `Motion` durations (Hover, Pop, Toast,
  Stagger, Celebrate) and `Easing` (Standard, Enter, Exit, Emphasis, Linear: `{Style, Direction}`
  for `Kit.Motion.Tween`). Existing values never change. Functions: `RarityColor(r)`,
  `RarityOrder(r)` (sorting: Common 1 … Secret 7), `VariantColor(v)`, `MutationColor(m)`,
  `OnColor(bg)` (readable text colour), `Lighten`, `Darken`, `Hex` (RichText), `Size(name, phone)`.
  Colours mirror UITheme and LabConfig; `tests/uikit.luau` fails if they drift apart.
* `Kit.Format`: `Short(1234567)` → `1.23M` (K/M/B/T/Qa/Qi, truncated), `Number` → `1,234,567`,
  `Percent(0.125)` → `12.5%` (`{Signed = true}` → `+12.5%`), `Mult(1.25)` → `x1.25`,
  `Odds(0.001)` → `1 in 1,000`, `Duration(3725, Kit.Lang())` → `1h 02m` / `1ч 02м`,
  `Clock(65)` → `01:05`, `Delta(a, b, higherIsBetter)` → `delta, "up"|"down"|"same", better`.
* `Kit.Layout`: the pure maths behind windows and grids (`Classify`, `WindowRect`, `Columns`,
  `VisibleRange`, `CanvasHeight`, `CellPosition`, `MaxCells`, `ClampScroll`, `ScrollToReveal`).
* `Kit.Lang()` → `"ru"` / `"en"` (same rule as AutoTranslate), `Kit.T(en, ru)`, `Kit.Word(key)`,
  `Kit.Now()` (server unix time from `workspace:GetServerTimeNow()`).
* `Kit.Maid.new()` (`:Give(connection | instance | function | thread | object)`,
  `:Connect(signal, fn)`, `:Set(key, item)` keyed slot, `:Clean()`), `Kit.Signal.new()`
  (`:Connect`, `:Once`, `:Fire`, `:DisconnectAll`). Both are `ReplicatedStorage.Perf.Maid` /
  `Perf.Signal`, shared with non-UI code.
* `Kit.Motion.Tween(inst, seconds, goals, style?, direction?)`: use it for your own animations so
  reduced motion applies (`Kit.Motion.Reduced()` follows `Perf.Quality.Reduced()`;
  `Kit.Motion.Override` wins).
* `Kit.Text(parent, props)` (kit label: `Text`, `TextSize`, `Color`, `Font = "numeric"`,
  `AlignX`, `Wrap`, `Scaled`, `Stroke`, `Rich`, `NoTranslate`...), `Kit.Icon(parent, key, props)`
  (an image when the key has one, otherwise a text glyph: kit glyphs, then
  `ReplicatedStorage.GameIcons.Glyph(key)` for rarities, actions and places),
  `Kit.New(class, props, parent)`, `Kit.Corner`, `Kit.Stroke`, `Kit.Padding`.
* `Kit.Stats()`: counts of windows, modals, toasts, countdowns and preview cache numbers (debug).
* `Kit.SetNavigation(N | false, mainGui)`: override the navigation owner (tools, tests).

## Sounds

Kit controls play `ReplicatedStorage.UISound` cues: `Kit.Button` hover and press (hold buttons:
press when the hold starts, `Success` when it completes), `Kit.Window` open / close, `Kit.Tabs`
hover and `Tab` on a change. `Sound = false` on a button silences it, `{Hover = false}` drops
only the hover sound (hold buttons too); on a window it sets the
`UISoundOff` attribute on the window root, which silences everything inside (any GUI subtree can
use that attribute). For your own feedback call `UISound.Play("Success")` (cues: Hover, Press,
Open, Close, Tab, Toggle, Success, Error, Reward, Coin, Whoosh, Pop, Rare, Epic, Legendary,
Countdown, Lock) or `UISound.Bind(button)`. Sounds go through the `DOGROTS_AUDIO/UI` bus, whose
volume follows `Setting_UIVolume` from join on (`UISound.Start()`, called by PerfBootstrap; the
`SFX` bus follows `Setting_SFXVolume`); at most 6 play at once and hover spam is throttled.

## Data refresh pattern

```lua
local function refresh(snapshot)          -- called by your fetch / DogEconomyPush handler
	local list = filterAndSort(snapshot.Profile.Dogs)
	grid:SetItems(list)                   -- cells keyed by uid; nothing rebuilt
	win:SetBadge("dogs", #list)
	title.Text = Kit.Format.Short(snapshot.Profile.Cash)
end
```

Keep per-screen UI state (filter, sort, selection) in your module, not in the instances, and
call `grid:RefreshKey(uid)` after toggling a selection. Use `button:SetBusy(true)` while a request
runs, and show the server reply with `Kit.Toast(message, {Kind = ok and "success" or "error"})`.

## Testing

* `tests/uikit.luau` (run by `tools/check.sh`) covers formatting, the grid and window maths,
  theme sync with UITheme / LabConfig / Config.Variants / ItemValueConfig, and localization
  coverage of kit words.
* The runtime emulation scenarios (real place, real GUIIntegration, kit and KitDemo at
  1920x1080, 812x375 and 390x844) live outside the repo in
  `scratchpad/work/big/scratch/uikit/harness/`. `run_uikit.luau` checks bounded cell and
  instance counts while scrolling 500 dog cards, keyed refresh, filters, modals (cancel,
  Escape, hold-to-confirm), stacked windows, navigation hand-over, toasts, countdowns, reduced
  motion, every control's interaction and that every window fits the safe area.
  `run_uikit_ru.luau` runs the real AutoTranslate with a Russian locale and checks the kit
  words.
* In Studio, use the Device Emulator (phones in both orientations) with the KitDemo. Also try
  Reduced Motion (Roblox settings) and a gamepad (B closes, selection starts on the close
  button).
