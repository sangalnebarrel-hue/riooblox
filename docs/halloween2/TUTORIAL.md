# Main tutorial v4 — cinematic, interactive onboarding (WP-O)

The DOGROTS main tutorial teaches the real loop one task at a time. The **server** owns the progress
(`p.Onboarding`, version 4) and decides when a step is done; the **client director** shows the card, points
the camera at the target, outlines it, draws SHOW THE WAY to it and puts a marker over it. There is no NEXT on
task steps: the player does the task, or after 120 s skips that one step. Nothing in the tutorial can leave the
player without a way forward.

| Piece | File |
|---|---|
| Track + every number (shared) | `src/ReplicatedStorage/TutorialConfig.luau` |
| Rules (pure, tested) | `src/ServerScriptService/Economy/OnboardingRules.luau` |
| Request service (positions, free block) | `src/ServerScriptService/Economy/OnboardingService.luau` |
| Player attributes | `src/ServerScriptService/Economy/Runtime.luau` (`projectTutorial`) |
| Client director | `src/StarterGui/ScreenGui/Modules/TutorialDirector.luau` |
| Entry shim (GUIIntegration starts it) | `src/StarterGui/ScreenGui/Modules/OnboardingGuide.luau` |
| HOW TO PLAY (Settings) | `src/StarterGui/ScreenGui/Modules/EconomyScreens.luau` |
| Russian text | `src/ReplicatedStorage/Localization/Tutorial.luau` |
| Tests | `tests/tutorial.luau` (+ `tests/lib/client_env.luau`, a headless fake client) |

## 1. The track

| # | Step | Kind | Done when (server) | Target / marker | SHOW ME destination | Fallback |
|---|---|---|---|---|---|---|
| 0 | WELCOME TO DOGROTS | Intro | `Start` | — | — | SKIP TUTORIAL (hold 1 s) leaves for good |
| 1 | BUY YOUR FIRST DOG | Milestone `DogOwned` | any dog in `p.Dogs` | the nearest **affordable** dog walking on THE DOG's tongue (`03_DogLine.ActiveDogs`, price ≤ Coins); none → the `Tongue` | `DogLine` | `EntranceAnchor` / route pointer |
| 2 | PUT YOUR DOG TO WORK | Milestone `Assigned` | a dog with `AssignedSlot` | first unlocked empty `DigSlot_n` of the player's yard | `MyKennels` | yard route pointer |
| 3 | WAIT FOR THE FIRST DIG | Milestone `Found` | `TotalExcavations > 0` (or finds / loot) | the kennel of the working dog; bar = time to its `NextWorkAt` | `MyKennels` | yard route pointer |
| 4 | COLLECT YOUR LOOT | View `Inventory` | `Seen Inventory` (the BAG opened) or a sale | BAG rail tile ring | — (OPEN MY BAG) | — |
| 5 | SELL A FIND | Milestone `Sold` | `Stats.TotalSellValue > 0` | `SellAnchor`, `Vendor` outlined | `Collector` | yard route pointer |
| 6 | GROW YOUR UPGRADE TREE | Milestone `Upgraded` | any `p.Upgrades[*] > 0` | YARD rail tile ring | — (OPEN UPGRADE TREE) | — |
| 7 | DIG DEEPER: LAYERS | View `Layers` | `Seen Layers` (the panel opened) or Caverns unlocked | YARD tile ring; info line = next layer + its level and price | — (OPEN LAYERS) | — |
| 8 | MINE ORE IN YOUR QUARRY | Milestone `MiningHit` | `Mining.Hits > 0` | `MiningPickaxeShop` until a pickaxe is owned, then `MiningOreCore` | `MiningCorner` | yard route pointer |
| 9 | BUILD YOUR STRENGTH | Milestone `StrengthTrain` | a STRENGTH node (IronGrip…MountainBreaker) or `Mining.Strength > 0` | YARD tile ring | — (OPEN STRENGTH → `UpgradeTreeScreen.Open("IronGrip")`) | UPGRADE TREE page |
| 10 | LUCKY BLOCKS | Arrive `LuckyPad` | `Arrive LuckyPad` checked on the server (+ the free block), `Claim`, a block on a pad, or any block ever opened | the first free `LuckyPad_n` of the yard | `PlayerYards` | CLAIM FREE BLOCK at once when the yard has no pad |
| 11 | THE MUTATION LAB | Arrive `Lab` | `Arrive Lab` checked on the server, or the first mutation / any experiment | `05_MutationLab.InteractionAnchor`, the `NuclearCompound.Console` outlined | `MutationLab` | saved anchor positions |
| 12 | YOUR DOGDEX | View `DogDex` | `Seen DogDex` (the window opened) or a Dex claim | DEX tile ring | — (OPEN DOGDEX) | — |
| 13 | SAFE TRADING | View `Trade` | `Seen Trade` (the window opened) or a completed trade; info = "Trading unlocks at Level 5 (you are Level n)" | TRADE tile ring | — (OPEN TRADE) | — |
| 14 | YOU KNOW THE LOOP! | Final | `Finish` → `Status = Complete` | — | — | — |

Ordering is strict: a step is done only when the steps before it are done, but `Observe` fast-forwards through
every following step whose flag is already set (a player who mined before buying a dog finds the quarry step
done when they get there). Profile evidence never resets ("sold a dog" does not undo "bought a dog").

## 2. Server

### 2.1 Data (`p.Onboarding`)
```lua
{Version = 4, Status = "Active"|"Complete"|"Skipped", Step = 0..14, StepAt = unix,
 Seen = {[flag] = true}, Skipped = {["n"] = true}, FreeBlock = true?, FreeBlockAt = unix?, FreeBlockFull = true?,
 Migrated = true?, From = oldVersion?, CompletedAt?, SkippedAt?}
```
`StepAt` is when the current step started (set by every advance; `Observe` fills it on the first transaction
after a migration). The record stays under 600 bytes.

### 2.2 Migration v3 → v4 (`OnboardingRules.Normalize`)
* No record: an experienced profile (dogs, dex, sales, digs, mining hits or level > 1) is a **migrated veteran**
  (`Complete`, `Migrated = true`), anyone else starts at the welcome card.
* `Complete`, `Skipped` or `Migrated` (any old version): they **stay out** — `Complete`/`Skipped` kept, `Step = 14`.
  The v3 exclusion `and not t.Migrated` is gone: migrated veterans migrate too, and a corrupt "Migrated but
  Active" record becomes `Complete`.
* Active v3 players: old step → `TutorialConfig.MigrateV3` (0→0, 1→1, 2→2, 3→3, 4→5, 5→6, 6→6, 7–10→7,
  11→10, 12–13→11, 14→12, 15→13, 16–17→14), then `Observe` fast-forwards past what the profile proves.
  Versions 1–2 first go through v3's `min(step, 7)`.
* A record **newer** than 4 (a rollback) is left untouched and reported inactive.

### 2.3 Requests — `DogEconomyRequest:InvokeServer("Tutorial", {Action, Key?}, requestId32)`
| Action | Args | Rule |
|---|---|---|
| `Start` | – | welcome card only; moves to 1 and fast-forwards |
| `Seen` | `Key` = `Inventory`/`Layers`/`DogDex`/`Trade` | must be the **current** View step's key; a late report for a past step is harmless; any other key errors |
| `Arrive` | `Key` = `LuckyPad`/`Lab` | current Arrive step; the service measures the character's **server** position: within `Radius + Slack` (LuckyPad 14 + 6 of any `LuckyPad_1..3` of the player's own yard; Lab 22 + 6 of `EntranceAnchor`/`InteractionAnchor`, saved positions as fallback). `LuckyPad` grants the free block |
| `Claim` | – | LUCKY BLOCKS step only; allowed after `SkipAfter` (120 s) or when the player has no Lucky Pad; grants the free block and completes the step |
| `SkipStep` | – | steps 1–13, `now ≥ StepAt + 120`; records `Skipped[step]`, starts the next step's timer |
| `Skip` | – | leaves the tutorial for good (`Status = Skipped`) |
| `Finish` | – | step 14 → `Complete` |

Replies: `OnboardingRules.View` = `{Version, Status, Step, Active, StepAt, Skippable, Kind, Id, ReadyAt = 0,
FreeBlock}` plus `FreeBlock = {Granted, Tier, Uid}` / `{Granted = false, Reason = "Full"}` when the block was
handed out. Errors are plain English with Russian in `Localization/Tutorial.Exact`. The request id makes a retry
idempotent (transaction receipt).

### 2.4 The free Common Lucky Block
Granted **once** (`FreeBlock`), at the LUCKY BLOCKS step, by `Arrive LuckyPad` or `Claim`, with
`LuckyLifecycle.AddStored(p, "Common", 1, "Tutorial", false)` inside the same profile transaction: a normal
stored, **not paid-random** block (A06 §11.1). Cap aware: with `LuckyLifecycleConfig.InventoryCapacity` (60)
blocks stored there is no block (`FreeBlockFull`), the step still completes and the client says why. A player
who completes the step by placing or opening their own block needs no gift.

### 2.5 Player attributes (`Runtime.projectTutorial`, on every projection and the mining fast path)
`TutorialVersion`, `TutorialStep`, `TutorialActive`, `TutorialStatus`, `TutorialReadyAt` (0, kept for old
readers), **`TutorialStepAt`** (unix start of the step) and **`TutorialSkippable`**. The client also computes the
skip timer itself from `TutorialStepAt` and `workspace:GetServerTimeNow()`, so the countdown runs between
projections.

## 3. Client director
* Started once per session by `GUIIntegration` → `OnboardingGuide.Start(gui, N)` → `TutorialDirector.Start`.
  `OnboardingGuide.Replay()` / Settings → HOW TO PLAY → `TutorialDirector.Replay()`.
* Own `ScreenGui DOGROTS_Tutorial`, **DisplayOrder 55** (above the HUD at 0 and the Halloween guide at 45,
  below Kit windows at 60), `ResetOnSpawn = false`, `HideWithUI` (the layer stays Enabled; the card's Visible
  is the switch). The card is the only input-taking object; nothing uses `Modal`.
* Visible when `TutorialActive` and `EconomyReady` (2 s after it), and no menu (`OpenMenu`), modal,
  mining session (`MiningActive`), HIDE UI or other cinematic (`CinemaActive`) is up. The world marker and
  highlight hide with it. The Halloween Dead Yard guide stays suppressed while `TutorialActive`.
* Card (Kit): header band with "TUTORIAL · TASK n / 13", icon, title (two lines when long), one sentence, the
  objective with a progress bar (dig timer, distance to go, 1/2 for the quarry, n / 13 at the end), an info line
  where useful (Coins, next layer, finds in the BAG, trade level), the error line, the hint line, the buttons and
  13 progress dots. Collapse (–/+) shrinks it to a strip. Phone portrait: full width, 235 px above the bottom
  (thumbstick + jump); phone landscape: a low two-column card centred in the HUD's free zone; desktop: 490 px,
  84 px above the bottom (hotbar).
* Buttons (all `GuiButton.Activated` via Kit.Button): START / SHOW ME / OPEN … / FINISH; the second button is
  SKIP TUTORIAL (hold 1 s) on the welcome card, SKIP THIS STEP (disabled with a "SKIP IN m:ss" countdown until
  120 s) on task steps and CLAIM FREE BLOCK on the LUCKY BLOCKS step. In HOW TO PLAY: NEXT / BACK / CLOSE / DONE.
* Per world step on entry: target lookup (waits up to 3 s for streaming, then the destination anchor from
  `RouteGraph.Target(...).Pointer`), Highlight, marker (label, distance, bouncing arrow; gold light column +
  ground ring on Medium/High quality, not for a walking dog), `PathGuide.Show(destination)`, then a **2.2 s camera
  focus** (a 3/4 shot from the player's side, pulled in front of walls): through `HalloweenClient/Cinema.Play`
  when that module exists (`Letterbox = false`, `HideUI = false`, `LockControls = true`, skippable), otherwise an
  own `BindToRenderStep` camera path. None with reduced motion, none for targets farther than 260 studs, none
  while the card is collapsed; it waits (≤ 15 s) for a free camera (the arrival camera) and a visible card. Any
  tap / key skips it. SHOW ME replays focus + path. Menu steps ring the rail tile (BAG, YARD, DEX, TRADE) with a
  pulsing outline and a pointing hand.
* Reports: View steps send `Seen` while their menu is open (`OpenMenu` = `Inventory`/`InventoryDetail`,
  `Layers`, `DogDex`/`DexEntry`, `Trade`); Arrive steps send `Arrive` when the character is within the
  step's `Radius` (every 3 s while there and still current). Reports use their own request slot and never block
  a button.
* A finished task: a success sound, a short pop and a green "✓ TASK DONE!" band.

### 3.1 Robustness
| Risk | Handling |
|---|---|
| A request hangs (Tx lock wait up to 12 s, lost reply) | 8 s timeout → buttons back, "No answer from the server. Tap RETRY."; RETRY resends **the same request id** (server receipt = no double effect); a late reply is ignored |
| A server refusal | its message shows (Russian via `Localization/Tutorial.Exact`, other systems' replies via AutoTranslate); no RETRY |
| An error in render / tick / world code | every render, tick and marker build runs in `pcall`; errors warn once per 30 s and the loop continues |
| Camera left Scriptable | Cinema's guaranteed restore, or the own focus restores `Custom` + subject on finish, skip, error, menu open, CharacterRemoving, step change and Stop |
| Respawn | focus cancelled on CharacterRemoving; target and marker re-resolved 1 s after CharacterAdded |
| Layer destroyed by something else | rebuilt 0.2 s later (max 20 times) |
| Main ScreenGui destroyed | the director stops cleanly (layer, world folder, connections) and a new `Start` builds a new one |
| Target not streamed in / not built (yard, quarry) | 3 s wait, then path + marker at the destination anchor; switches to the real target when it appears |
| No yard / no pad | CLAIM FREE BLOCK offered at once |
| A step that cannot be done | SKIP THIS STEP after 120 s (CLAIM FREE BLOCK at step 10) |

## 4. Localization
Self-localized: every label carries `NoTranslate` and uses `T(en)` = `Localization/Tutorial.UI[en]` in Russian
(`Templates` for formatted strings). Server messages are in `Exact` (merged into DOGROTS_AutoTranslateUI, so they
read in Russian wherever they show). `tests/tutorial.luau` checks that every `T("…")` / `F("…")` string of the
director and every server message has its Russian entry, and that no `Exact` key repeats the base dictionary or
another module. The old 18-card strings in DOGROTS_AutoTranslateUI are no longer shown (left untouched).

## 5. Numbers (`TutorialConfig`)
`SkipAfter` 120 s · `RequestTimeout` 8 s · `FocusSeconds` 2.2 s · `TargetWait` 3 s · `ShowAfter` 2 s ·
`ArriveRetry` 3 s · `Tick` 0.5 s · `RetargetEvery` 4 s · `FreeBlock` Common/"Tutorial" ·
`Arrive.LuckyPad` radius 14 + slack 6 · `Arrive.Lab` radius 22 + slack 6.

## 6. Tests (`lune run tests/tutorial.luau`)
Server (real `Rules`, `OnboardingRules`, `OnboardingService`, `LuckyLifecycle` through `tests/lib/economy_env`):
each step's completion from profile state in order, ordering + fast-forward, view keys only for the current step,
SKIP THIS STEP timing (119 s refused, 120 s accepted, next step's own timer, never on 0 / 14), whole-tutorial
skip, the v3 → v4 matrix (all 18 active steps, Complete/Skipped/Migrated veterans incl. corrupt records, missing
records, v1/v2, a newer record left alone, the R.Normalize / R.Validate pipeline), the free block (once, stored,
not paid-random, cap aware, Claim timing / no pad, own block as evidence), Arrive validated against server
positions (radius + slack, no character, Lab fallback anchors, bad requests), localization coverage.
Client (real Kit + director in `tests/lib/client_env`, a headless fake Roblox client): welcome card + layer
contract (DisplayOrder 55, no Modal, only the card takes input), hold-to-skip, the dog-line target and marker,
path, the own camera focus and its restore (timeout, tap, respawn), retargeting, menu steps (tile ring, OPEN,
Seen when open, card hidden), the skip countdown, the 8 s timeout + RETRY with the same id + refusals, Arrive in
range + CLAIM without a yard, blocking states, collapse, layer rebuild, Russian, HOW TO PLAY replay (no
requests), stop + restart with the main ScreenGui, the Cinema path (options, refusal) and layouts on phone
portrait / landscape / desktop.

## 7. Studio test procedure
1. **Fresh player:** Play Solo in Studio (unpublished place = memory store, so every session is a new profile).
   After ~2 s the WELCOME card appears bottom centre; tap START.
2. **Step 1:** the camera swings to a gold-outlined affordable dog on THE DOG's tongue (2.2 s, tap to skip), the
   arrows lead there, the marker says BUY THIS DOG with the distance. Buy it (prompt) → "✓ TASK DONE!" + step 2.
3. **Steps 2–3:** follow the arrows to your yard, assign the dog at the outlined kennel; watch NEXT DIG IN …s.
4. **Step 4:** the BAG rail tile pulses; OPEN MY BAG → the card hides while the BAG is open and the step
   completes; close it.
5. **Steps 5–9:** sell at the outlined Collector, buy any UPGRADE TREE node, open LAYERS (check the "Next:"
   line), buy a pickaxe at the outlined stall and hit the ore, buy IRON GRIP (OPEN STRENGTH).
6. **Step 10:** walk to a Lucky Pad → toast "+1 FREE COMMON LUCKY BLOCK"; check the BAG has a Common block
   (not paid). For the full-storage case, Stop, enable the `AddStored` line of the temporary Script below (60 stored
   Common blocks, the storage cap) and Play again: at the Lucky Pad → the "storage is full" toast, no block.
7. **Steps 11–14:** walk to the Lab, open the DOGDEX, open TRADE, FINISH.
8. **Skip:** on any task step wait 2 minutes → SKIP THIS STEP; at step 10 → CLAIM FREE BLOCK.
9. **Robustness:** open a menu mid-focus (camera returns), reset the character mid-focus, press H (HIDE UI),
   rotate a phone emulator (portrait / landscape), switch the Studio locale to `ru-ru`.
10. **Replay:** Settings → HOW TO PLAY → NEXT / BACK through all 15 cards; nothing is saved.

Jump to a step / reset (the next projection updates the client): paste into a **temporary Script** in
ServerScriptService before Play and delete it afterwards. Not the command bar: a command-bar `require` gets its own
Runtime instance with an empty memory store, so it never sees the running game's profile.
```lua
local RT = require(game.ServerScriptService.Economy.Runtime)
local p1 = game.Players.PlayerAdded:Wait()
repeat task.wait(1) until RT.Views[p1.UserId] -- the profile is loaded
RT.Tx:Run({"p:" .. p1.UserId}, function(v)
	local t = v["p:" .. p1.UserId].Onboarding
	t.Status, t.Step, t.StepAt, t.FreeBlock, t.FreeBlockFull = "Active", 10, os.time(), nil, nil
	-- full restart instead: t.Step = 0; t.Seen = {}; t.Skipped = {} (profile evidence is re-derived at once)
	-- step 6, full storage: fill the block storage (stored blocks are no Lucky Pad evidence)
	-- require(game.ServerScriptService.Economy.LuckyLifecycle).AddStored(v["p:" .. p1.UserId], "Common", 60, "Test", false)
end)
RT.Refresh(p1)
```
