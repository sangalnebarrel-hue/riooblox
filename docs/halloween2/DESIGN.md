# DOGROTS HALLOWEEN PART II — THE UNDERYARD · Engineering design (contract for all work packages)

Status: binding spec. Every work package (WP) implements exactly the contracts below; when a WP needs something that is
not here, it adds it in its OWN files and documents it in its report. Audits of the existing place live in
`/tmp/claude-0/-home-user-riooblox/da558f97-29b1-5d70-8a0b-9546eb2652ef/scratchpad/audit/A01..A10_*.md` (read the ones
your WP touches; they cite exact file:line of the current code).

Paths: `src/` mirrors the place (Rojo names: `X.server.luau` Script, `X.client.luau` LocalScript, `X.luau` ModuleScript,
a directory `X/` next to a script file = that script's children). RS = ReplicatedStorage, SSS = ServerScriptService,
SPS = StarterPlayer/StarterPlayerScripts, HC = SPS/HalloweenClient, HS = StarterGui/ScreenGui/Modules/HalloweenScreen.

Build: `tools/place_build.luau` writes `src/` + runs `tools/edits/*.luau` (offline builders) onto
`place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl` → `build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl`.
Tools: `LUNE=/tmp/claude-0/-home-user-riooblox/da558f97-29b1-5d70-8a0b-9546eb2652ef/scratchpad/bin/lune`,
luau-lsp + `globalTypes.d.luau` in the same `bin/`. See §21 for how to verify.

------------------------------------------------------------------------------------------------------------------------
## 0. Principles (apply everywhere)

1. **Server authority.** Clients only request; the server validates distance, state, cooldowns, ownership, dates and
   pays. No remote may grant by name ("giveSecretDog" style). Every grant goes through a transaction
   (`Core.Transact` / `Chapter2.Transact` / `Runtime.Tx:Run`) and ends in `R.Validate`.
2. **Config first.** Every balance number lives in `RS/Halloween/Chapter2Config.luau`,
   `RS/Halloween/HalloweenCalendarConfig.luau` or `RS/Halloween/Config.luau` (Chapter I). No balance literals in logic.
3. **Pure rules are separate and tested.** Math (DR, drop tables, dates, damage, salvage value, eligibility) lives in
   pure modules that require nothing but other pure modules and config, so Lune tests can run them
   (`tests/lib/economy_env.luau` → `L.Require("ReplicatedStorage.Halloween.Chapter2Rules")`).
4. **Never break saves.** Additive fields only, nil-safe Shape/heal functions wrapped in `pcall` (a throwing
   Normalize locks a player out — A06 §5). Never change `Config.Season` ("NOTBM_2026", it is a wipe key — A01 §2) and
   never touch `MegaResetVersion`. Saved ids (tiers, dog ids, item ids, skin ids) are permanent.
5. **Feature flags** (§2) switch systems off without deleting data.
6. **Mobile first.** All buttons use `GuiButton.Activated` (Kit/UITheme buttons already do). No hover-only
   affordances. Touch targets ≥ 44 px. Kit windows become full-screen sheets on phones.
7. **Quality scaling.** Every client VFX loop reads `Shared.Quality()` / `Shared.Budget(key)` and new
   `Config.Quality[*]` keys (§17). Mechanics never depend on the quality tier.
8. **No unavailable assets.** No new asset ids. Audio = built-in `rbxasset://sounds/*` through the existing engines
   (Halloween `Audio.luau`, `MiningAudio.luau`, procedural `Music.luau`). Visuals = parts, Neon, beams, particles
   with built-in textures (`rbxasset://textures/particles/*`).
9. **Localization.** Every new player-visible string is EN+RU. Self-localized UI uses `Shared.L(en, ru)` /
   `Kit.T(en, ru)` and sets `NoTranslate=true`; server-sent text goes in a `RS/Localization/<Package>.luau`
   `Exact`/`Patterns` table (one module per WP, never duplicate a key that exists elsewhere). Prompts in the Underyard
   and at the church are localized by the client (§15.3).
10. **Exception-safe presentation.** Every cinematic/overlay is built inside `pcall` with a guaranteed teardown; never
    leave a full-screen input-sinking layer, a Scriptable camera, disabled controls or a disabled
    `ProximityPromptService` behind (these are the root causes of the reported "Shelter does not open" — A04 §8, A07 §9).

------------------------------------------------------------------------------------------------------------------------
## 1. Chapter structure (player-facing)

* **CHAPTER I · THE DEAD YARD** = the current event, kept intact, rebalanced (§12). Mandatory prologue.
* **HalloweenChapter1Complete** (§3.3) unlocks the secret reveal "И ЭТО ВСЁ?" (§6), the church cinematic, the portal
  and **CHAPTER II · THE UNDERYARD — BENEATH THE LAST BELL** (§7-§11).
* Chapter II story = **7 BELL SEALS**, each a different activity, gated by a date schedule (§8.1) and by Bell Shard
  offerings. Collection = Event DogDex II (H09-H16), Black Coffin chase, cosmetics, showcase finds.
* Endgame = Gravekeeper difficulties III-V rebuilt with **Event HP** (§10) and, on difficulty V, the **false victory +
  three post-death phases** (§11).
* The main map runs a **Halloween calendar** D-7 … Oct 31 (§13).

------------------------------------------------------------------------------------------------------------------------
## 2. Feature flags (RS/Halloween/Config.luau, top of file)

```lua
C.HalloweenEventEnabled = true      -- existing master switch (everything Halloween; read at boot)
C.HalloweenChapter1Enabled = true   -- Dead Yard activities: candy economy, ores, dig spots, houses, cauldron, quests,
                                    -- Blood Moon spots, the Gravekeeper. Off = these refuse/stop; zone stays visible.
C.HalloweenChapter2Enabled = true   -- reveal, church portal, Underyard, seals, coffin, contracts, resonance, dex II.
C.HalloweenCalendarEnabled = true   -- main-map calendar stages (D-7..Oct 31).
C.HalloweenBossFinaleEnabled = true -- difficulty V false victory + post-death phases (off = V ends normally).
```
Accessors (RS/Halloween/Shared.luau, added by WP-A): `S.Chapter1Enabled()`, `S.Chapter2Enabled()`,
`S.CalendarEnabled()`, `S.BossFinaleEnabled()` — each = master `S.Enabled()` AND its flag AND the replicated attribute
of the same name on `RS.Halloween.State` (server writes the attributes at boot, so a live server could later flip them).
Player data is never deleted by any flag. Owned pickaxe skins stay usable when the event is off (fix of A03 §10.1:
`Skins.Of` must not depend on `Shared.Enabled()`; `SkinEquip` gets `AllowDisabled`).

------------------------------------------------------------------------------------------------------------------------
## 3. Data

### 3.1 New Resources kinds (RS/DogEconomy/Resources.luau)
`BellShards` {Name "Bell Shards", RU "Осколки колокола", Icon "🔔", Max 1e9} and `LuckyDust` {Name "Lucky Dust",
RU "Счастливая пыль", Icon "✨", Max 1e12}, appended to `Resources.Order`. Missing = 0, no migration. Grant/spend
only through `Resources.Add/Spend` inside a transaction. Projected by `Runtime.Project` as player attributes
`BellShards`, `LuckyDust` (next to `Stone`, Runtime.luau:106-108 and the mining fast path).

### 3.2 `p.Underyard` (owned by new feature `SSS/Economy/Features/Underyard.luau`, `Order = 75`)
`Normalize` = pcall'd `Shape(p)` that heals and never deletes unknown keys (copy the Halloween pattern, A01 §2).
Created lazily (first Chapter2 transaction / first join while Chapter2 is on).
```lua
p.Underyard = {
  Version = 1,
  Chapter1 = { Complete = false, At = 0, Notified = false },   -- latched; never un-set
  RevealSeen = false, RevealAt = 0,                             -- Chapter2RevealSeen (church cinematic watched)
  Entered = false, FirstEnterAt = 0,                            -- first portal descent
  Tutorial = { Step = 0, Done = false },                        -- Chapter II onboarding (§9)
  Seals = { ["1"] = {Offered=false, Cleared=false, Gold=false, At=0, Best=0}, ... ["7"] },
  Keys = 0,                                                     -- Coffin Keys (cap Chapter2Config.Coffin.MaxKeys)
  Fragments = 0,                                                -- cosmetic fragments
  Daily = { Day = -1, Raw = 0, Eff = 0, Exchange = 0, Doors = 0, Keys = 0, Resonance = 0,
            Contracts = { Day = -1, List = {{Id, Goal, Progress, Claimed}}, AllClaimed = false } },
  Rested = { Day = -1, Pool = 0 },                              -- catch-up allowance (§8.3)
  Dex2Claims = { ["3"]=true, ... },                             -- Dex II milestones claimed
  Owned = { Decor = {}, Finds = {} },                           -- ids ever received (duplicate detection)
  Journal = { ["reveal"]=true, ["seal1"]=true, ... },           -- unlocked journal entries (≤40 keys)
  Coffins = { Opened = 0, Last = {} },                          -- Last ≤ 10 newest results
  Boss = { FinaleClears = 0, FirstClears = { ["3"]=true,["4"]=true,["5"]=true,["F"]=true } },
  Stats = { Perfect=0, Streaks=0, Trials=0, Doors=0, Spirits=0, Revives=0, Downs=0, ShardsEarned=0 },
}
```
Size budget: ≤ 6 KB JSON per profile. Lists are capped.

Pickaxe skins (Chapter I and II) stay in `p.Halloween.Skins` (set, cap raised 40 → 64). Plot cosmetics = `p.Decor`
(existing). Showcase finds = `p.Items` records (existing item system). Event dogs = `p.Dogs` (existing).

### 3.3 Chapter I completion — `HalloweenChapter1Complete`
Pure predicate in `Chapter2Rules.Chapter1Complete(p, cfg) -> ok, checklist` using only existing persistent fields:
```
Boss.Best >= Req.BossBest (2)              -- beat THE GRAVEKEEPER on UNEASY or higher
Cauldron.Invested >= Req.Cauldron (300)    -- cauldron level 3 BOILING (the 7-day brew claim is NOT required)
Stats.Knocks >= Req.Knocks (7)             -- knocked 7 doors (lifetime)
Stats.BloodMoons >= Req.BloodMoons (1)     -- took part in a Blood Moon
Stats.Spots >= Req.Spots (10)              -- dug 10 haunted spots
```
(Event dex is a collection, not a main objective: after the drop-rate nerf it must not gate the story.)
Evaluated in every Chapter2 transaction and in the Join transaction; once true it is **latched**
(`p.Underyard.Chapter1.Complete = true, At = now`) and projected as player attribute `HalloweenChapter1Complete`.
Old players are never reset; anyone who already satisfies it is complete on next join. The checklist (5 rows with
current/goal) is shown to players who have not finished (§6.5).

### 3.4 Player attributes (server-written; clients read)
`HalloweenChapter1Complete` bool · `Chapter2RevealSeen` bool · `Chapter2Notified` bool · `Chapter2Entered` bool ·
`BellShards` int · `LuckyDust` int · `CoffinKeys` int · `UySeals` int 0..7 (cleared count) · `UySealMask` string
("1101000": cleared per seal) · `UyInZone` bool · `UyDistrict` string ("" | "BellSquare" | "CrookedRow" |
"FuneralCarnival" | "MourningMarsh" | "Undercrypt" | "BlackBellArena") · `UyTrial` string (active trial id or "") ·
`UyTutorial` int (Ch2 onboarding step, -1 = done) · combat: `HwCombat` bool, `HwHP` number, `HwHPMax` number,
`HwDowned` bool, `HwDownedUntil` number (server time), `HwWeakenedUntil` number, `HwReviveBy` int (userId or 0).

### 3.5 Replicated server state (`RS.Halloween.State` children, each a Folder with attributes; create if missing)
* `Chapter2` {Enabled, Phase (seals open by date 0..7), NextPhaseAt (unix), Start (unix)}
* `Resonance` {Value, Goal, Milestone (0..4), Cycle, BuffUntil, AssaultUntil, Revision}
* `Calendar` {Enabled, Stage (0..8), DaysLeft, Target (unix), Revision}
* `Finale` {State ("" | "FakeDeath" | "Bell" | "Choir" | "Hound" | "Victory" | "Fail"), Stage, StageUntil, Chain,
  ChainsLeft, Candles (string), Pattern (string), HoundHP, HoundMax, CounterUntil, Revision}
* `Assault` {State, EndsAt, HP, MaxHP, Revision} (Black Bell Assault)

------------------------------------------------------------------------------------------------------------------------
## 4. Server architecture

### 4.1 Boot (SSS/Halloween/HalloweenServer.server.luau)
Order after the existing modules (each `start(name, Core, modules)`, pcall'd, a missing module is skipped):
```
World, Core, BloodMoon, Exorcism, Actions, Strike, Ores, DigSpots, Boss, Houses,      -- existing (Chapter I)
Hazards*, EventHP, Chapter2, Underyard, Seals, SealEcho, SealRun, SealMirror, SealMine, SealDoors, SealChoir, SealBell,
Coffin, Resonance, BossFinale, Calendar, Debug                                          -- new
```
(*Hazards is a shared pure module in RS; the server combat helper is `EventHP`.) Chapter I gameplay modules check
`Shared.Chapter1Enabled()` in their `CanHit`/request handlers. Chapter II modules return early from `Start` when
`Shared.Chapter2Enabled()` is false but still register their requests to answer "Chapter II is closed".
`Calendar` runs whenever `CalendarEnabled` (independent of chapters).

### 4.2 `SSS/Halloween/Chapter2.luau` — Chapter II core (WP-A)
```lua
C2.Start(core, modules)
C2.Transact(player, label, fn(p, u, ctx, now) -> result, opts?) -> ok, result|err, raw, cached
   -- wraps core.Transact; inside: u = UnderyardFeature.Shape(p); C2.Latch(p, u, now); fn(...)
   -- ctx = Core ctx + Chapter II helpers below (all inside the same transaction):
   ctx.Shards(n, source)           -> granted   -- applies daily DR (§8.2) unless source is DR-exempt; Resources.Add
   ctx.SpendShards(n)                            -- R.Check fails "Not enough Bell Shards"
   ctx.Dust(n), ctx.Keys(n) (cap), ctx.Fragments(n), ctx.Find(itemId, mutation?) -> copy?,
   ctx.Journal(key), ctx.Contract(id, n)        -- progress a daily contract
   ctx.C2Reward(row)                             -- Kinds: Shards Dust Key Fragments Find Decor Skin Dog Candy Bones
                                                 --   Cash Title; duplicates convert per §9.4; never fails
C2.Eligible(player) -> bool                       -- HalloweenChapter1Complete attr (server-latched)
C2.Phase(now) -> number                           -- seals open by date (Chapter2Config.Seals[i].Opens)
C2.SealOpen(i, now) -> bool ; C2.SealCleared(player, i) -> bool ; C2.Sealsof(player) -> mask
C2.GrantSeal(player, i, info)                     -- called by seal activity modules on server-validated clear
C2.OnTick(fn(player, dt))                         -- 1 s per-player tick hook (core has none, A01 §4)
C2.Progress(player, statKey, n)                   -- queued (like Core.Queue): contracts + stats + resonance
C2.Signal(player|"all"|"underyard", kind, data)   -- Signal kinds prefixed "C2"
C2.View(p, now)                                   -- the client view (embedded in Halloween View as .Chapter2)
```
Requests (on the existing `RS.Halloween.Remotes.Request`, via `core.OnRequest`):
| Action | Args | Cost | Effect |
|---|---|---|---|
| `C2Hello` | – | 3 | view + server phase info |
| `C2Notified` | – | 2 | sets Chapter1.Notified (the "И ЭТО ВСЁ?" screen was shown) |
| `C2RevealSeen` | – | 2 | requires Chapter1 complete, near church (≤60 studs) or `Replay`; sets RevealSeen |
| `C2ContractClaim` | {Id} | 2 | claim a finished daily contract |
| `C2ContractBonus` | – | 3 | all 3 claimed → Coffin Key |
| `C2Exchange` | {Shards 1..40} | 2 | Candy → Shards at `Exchange.CandyPerShard`, daily cap, near Toll Box |
| `C2SealOffer` | {Seal} | 2 | pay offering (catch-up discount §8.3), seal must be open by date, previous cleared, near altar |
| `C2DexClaim` | {Count} | 2 | Dex II milestone |
| `C2Craft` | {Id} | 3 | fragments → chosen cosmetic (§9.5) |
| `C2Journal` | {Key} | 1 | mark entry read |
| `C2Tutorial` | {Step} | 1 | advance Ch2 onboarding when the server condition for Step holds (§9) |
| `C2Debug` | {Cmd,...} | .5 | Studio only (GameId == 0): Shards, Keys, Seal n, Phase n, Complete1, Reveal, Calendar n, Finale, HP |

Signals (`core.Signal`): `C2Toast {Text}`, `C2Shards {Amount, Source, Eff}` (fly-in), `C2Seal {Seal, Stage
("Offered"|"Cleared"|"Gold"), Rewards}`, `C2Contract {Id}`, `C2Key {Amount, Source}`, `C2Reveal {}` (server tells a
newly eligible player to run the notification), `C2Phase {Phase}`.

### 4.3 Other new server modules (owners in §20)
* `Underyard.luau` — zone: portal teleport (both ways), streaming (`RequestStreamAroundAsync`), presence attributes
  (`UyInZone`, `UyDistrict`), district gating (server push-back), fall/void recovery, respawn-into-zone,
  Underyard prompt helper `UY.Prompt(anchorName, props, fn)` on `40_Underyard.Anchors`, church/portal prompt.
* `EventHP.luau` — combat HP, downed/revive/bleed-out, weakened penalty, hazard damage application (§10).
* `Seals.luau` — trial framework: `Seals.Register(i, def)`; runs, timers, party, leave/death handling, rewards via
  `C2.GrantSeal`; each `Seal*.luau` implements one activity (§8.4).
* `Coffin.luau` — Black Coffin open (§9.3).
* `Resonance.luau` — server mechanic + Black Bell Assault (§8.6).
* `BossFinale.luau` — difficulty V finale state machine; `Boss.luau` calls it (§11).
* `Calendar.luau` — HalloweenCalendarService (§13).

### 4.4 Request/remote rules
All actions go through `core.OnRequest(action, fn, {Cost})` → token bucket + arg cleaning. Handlers validate
proximity with server positions (`core.Near(player, pos, radius)`), use generous radii (server sees a lagged client:
+6 studs slack), and return localized-able plain English messages (added to the WP's Localization module).

------------------------------------------------------------------------------------------------------------------------
## 5. Shared modules (RS/Halloween)

| Module | Owner | Content |
|---|---|---|
| `Chapter2Config.luau` | WP-A | ALL Chapter II balance (§8-§11 tables) |
| `HalloweenCalendarConfig.luau` | WP-M | target date, stages, per-stage visuals (§13) |
| `UnderyardLayout.luau` | architect (done) | all Underyard coordinates + anchors (§7) |
| `Chapter2Rules.luau` | WP-A | pure: DR, rested, phase/date math, eligibility, contracts pick, offering cost, coffin roll, duplicate conversion, dex II count |
| `CalendarRules.luau` | WP-M | pure: `UnixFromDate(y,m,d,h)`, `Stage(now, cfg)`, `DaysLeft` |
| `DropRates.luau` | WP-E | pure: philosophy rescale of weighted tables (§12.2) |
| `Hazards.luau` | WP-B | pure: hazard shapes, containment, timing (§10.2) |
| `BossMath.luau` | WP-B | pure: armor damage curve, soft cap, sync bonus, Event HP numbers (§10.4) |
| `DustRules.luau` | WP-D | pure: block value, salvage yield, forge cost (§14) |
| `Models/Finale.luau`, `Models/Coffin.luau`, `Models/EventDogs2.luau`, `PickaxeSkins2.luau` | §20 | client/offline builders |

------------------------------------------------------------------------------------------------------------------------
## 6. The reveal — "И ЭТО ВСЁ?" → church → portal (WP-F)

### 6.1 Secret notification
Trigger: player attribute `HalloweenChapter1Complete == true` AND `Chapter2Notified ~= true` AND not in a menu /
cinematic / mining / main tutorial; first time only (server `C2Notified`). Also fired by server Signal `C2Reveal` the
moment the latch flips. Presentation (own ScreenGui DisplayOrder 88, built in pcall, `HideWithUI=false`):
1. Mixer duck everything to 0 over 1.2 s (§16); screen fades to black (0.9 s); controls frozen (ref-counted lock §15.1).
2. 1.5 s silence, then a slow sub-bass swell (procedural: LAND/WIND rows pitched to .25-.4, long fade) + distant
   bell toll.
3. Typewriter, centred, huge: **И ЭТО ВСЁ?** (EN: "IS THAT ALL?"), letter by letter with a heartbeat thud per
   word; holds 1.8 s; slight chromatic jitter (two offset text copies in violet/blue at 20% alpha).
4. Fades to smaller line: **Вы правда думали, что всё будет настолько просто?** ("Did you really think it would be
   that easy?"); cracks of light spread from screen edges (neon UI strokes), a faint eye shape opens behind the text.
5. Button **УЗНАТЬ** ("FIND OUT"), pulsing, ≥ 64 px tall, Activated + Enter/ButtonA; tap-to-skip disabled for the
   first 4 s; Esc = also "find out" (never a dead end).
6. On press: bell strike flash, the overlay tears upward, controls restored, guide starts (§6.2), `C2Notified`.
Replay from the Journal (§9.6) without side effects.

### 6.2 Guide to the church
If outside the Dead Yard: `PathGuide.Show("Church")` (existing SHOW PATH; WP-F adds `Destinations` entry "Church"
(aliases Church, Crypt, Grand Crypt, Moon Tower, Portal, Underyard, Церковь, Склеп) + `RouteGraph` nodes
`DeadYardPitS`(128,0.2,704)/`DeadYardCrypt`(128,0.5,712), target `Church` = goal (128,0.5,720), pointer
(128,12,728) — A08 §6.4 recipe) plus client ghost lights (small floating blue-violet wisps every 18 studs along the
active route, max 12, LowFX 5) and an objective marker (BillboardGui "THE CHURCH" + distance) at the crypt door.
Inside the zone the same call leads straight to the church. The guide clears on arrival or when the cinematic plays.

### 6.3 Church cinematic (first time an eligible player comes within `Church.TriggerRadius` 46 studs of the crypt
door (128, 0.2, 724) while `Chapter2RevealSeen ~= true`; Replay from Journal anytime)
Duration ≈ 16 s, skippable after 3 s (skip = jump to the open-doors end state). Built on `HC/Cinema.luau` (§16.2).
1. Controls softly locked; HUD/menus fade out (UI hidden via `Cinema` not via HideUI's user toggle).
2. Camera eases (2.2 s) to a low 3/4 shot of the Grand Crypt + Moon Tower; DepthOfField focus on the door; ground fog
   thickens (client parts), music ducked to 0 → 2.5 s of silence (only wind bed).
3. BOOM #1: bell (Moon Tower bell at (128,36.3,737.5)) — spatial toll (layered KNOCK/LAND/LUNGE pitched low + long
   reverb tail) + bass impact; tower and crypt shake (client CFrame offsets on the tower model, 0.6 s); dust
   particles fall from the crypt roof edge; camera impulse.
4. BOOM #2: window lights die one by one (lancet `HwLantern` glass of MoonTower/GrandCrypt → dark, lights → 0).
5. BOOM #3: the ground cracks around the forecourt (client crack decals/neon fissures spread from the door, violet
   glow); camera shake.
6. Doors open by themselves (CryptDoorLeaf hinge models rotate 100° over 2.4 s with a creak); inside: black-violet
   portal (rotating rings, swirling disc, inward particles, violet light pulses); camera pushes in slightly.
7. Title card: "THE UNDERYARD · BENEATH THE LAST BELL" (EN) / "ПОДДВОРЬЕ · ПОД ПОСЛЕДНИМ КОЛОКОЛОМ" (RU).
8. Camera returns, controls restored, `C2RevealSeen`, journal entry "reveal", objective → "DESCEND".
The open-door + portal end state then persists for that player (client-only state, driven by `Chapter2RevealSeen`).

### 6.4 Church geometry changes (offline edit `tools/edits/38_church.luau`, WP-F)
The Grand Crypt doors are currently ajar (`CryptDoorLeaf`, A10 §1.7): rebuild them as two hinge models
(`ModelStreamingMode=Atomic`, PrimaryPart = hinge, closed by default) named `ChurchDoorL/R`; add a sealed light slit
part (`ChurchSlit`, Neon violet, used by the teaser), the portal model `ChurchPortal` inside the crypt (hidden by
default: every part `Transparency=1` in the saved place; client shows it per player), a server anchor
`38_DeadYard.Anchors.Portal` at (128, 3, 729) with ProximityPrompt "DESCEND" (server-created at runtime by
`Underyard.luau`), and a crack-decal set `ChurchCracks` (hidden). Record every changed original with `K.Remember`.

### 6.5 Not yet eligible
Church stays closed for them (doors closed, no portal, prompt hidden client-side and refused server-side). Every
45-90 s while they are within 70 studs: a quiet bell toll from the tower, violet light breathes through `ChurchSlit`,
and a small world text fades in/out above the door: **"Something is waiting below."** / **"Внизу что-то ждёт."**.
The HALLOWEEN window event tab shows a locked "CHAPTER II" card with the §3.3 checklist (n/5).

### 6.6 Portal (DESCEND)
Prompt (HoldDuration .5, range 10) → server: Chapter2 enabled, eligible, `RevealSeen` (else the server tells the
client to play the cinematic first), not in combat → reply OK → client transition (1.4 s): screen stretches (UIScale
+ vertical squash on a full-screen capture frame), colour drains (ColorCorrection Saturation -1), reverse whoosh
(WIND row reversed feel: rising pitch ramp), a giant eye/moon flashes for 0.35 s, black. Meanwhile the server
`RequestStreamAroundAsync(UY.Arrival)` then `PivotTo(UY.Arrival)`; client fades in at the Underyard with the title
"THE UNDERYARD" and the district name. Return: prompt "ASCEND" on the Underyard arrival arch → back to the church
forecourt (128, 3, 712). Server-side cooldown 3 s, refuses while `HwCombat`.

------------------------------------------------------------------------------------------------------------------------
## 7. THE UNDERYARD — world (WP-G world builders, WP-H district builders)

### 7.1 Placement and style
Root `Workspace.DOGROTS_District.40_Underyard` (Model), built offline by `tools/edits/40_underyard.luau` from
`ServerStorage/UnderyardBuild/*.luau` (reuse `ServerStorage/HalloweenBuild/Kit` + `YardKit`; deterministic `Y.Rng`).
Centre (0, 0, 2400); floor top y = 0; zone box x −230..230, y −40..170, z 2160..2720 (≥ 1 400 studs from the island,
outside streaming range 1024; above DistrictSafety's y −85). Budget ≤ 26 000 parts, ≤ 250 lights (verify_world).
Style: crooked gothic stop-motion; exaggerated silhouettes, leaning/twisted architecture, stretched windows, crooked
roofs, spiral roads, black/white stripes as accents only; palette sickly green (120,255,140), violet (150,80,230),
candle orange (255,170,80), moon blue (150,200,255), bone (230,222,200), ink (16,12,26). Original DOGROTS designs —
no copied characters/logos/costumes. Dogs are everywhere in the motif (dog-headed gargoyles, paw-print cobbles,
bone fences, kennel-like crooked houses).
Sky/atmosphere: no visible sun; a huge pale-blue moon and a black eclipse moon; a cavern-ceiling silhouette ring of
stalactites/roots at the zone edge (y 120-170) so it reads "beneath". Boundary = crooked cliffs + invisible 60-tall
colliders.

### 7.2 Districts (UnderyardLayout.Districts; boxes are for presence + gating)
| District | Box / centre | Content | Seal |
|---|---|---|---|
| BELL SQUARE | circle c(0,0,2400) r 62 + ring road r 66-82 | broken giant bell tower (base 24×24, 92 tall, cracked top), arrival arch (N), 7 seal altars around the tower, Black Coffin shrine (W), contracts board (E), Toll Box (E), practice ring (S) | I |
| FUNERAL CARNIVAL | x 75..215 z 2175..2330 | striped dead-circus tent, broken carousel, coffin coaster, tilted ferris wheel, ticket booth | II |
| MOURNING MARSH | x −215..−75 z 2470..2625 | black water, boardwalks, blue fog, glowing flowers, mirror pond with 6 graves | III |
| UNDERCRYPT | x 75..215 z 2470..2625 | catacomb mouth, sunken mine floor (y −16), ore seams, bone walls | IV |
| CROOKED ROW | x −215..−75 z 2175..2330 | leaning houses with eye windows, door wall with 4 crooked doors, door court | V |
| (all districts) | | choir spirits roam | VI |
| BLACK BELL ARENA | circle c(0,0,2625) r 52, approach z 2482..2573 | ring arena, giant Black Bell hanging from a twisted gallows (bell centre (0,58,2625)), 4 chain anchors | VII |

Gates (veiled arches at the ring road): Carnival (68,0,2332) opens after Seal I · Marsh (−68,0,2468) after II ·
Undercrypt (68,0,2468) after III · Crooked Row (−68,0,2332) after IV · Arena (0,0,2486) after VI.
Per-player gating: the client shows a spectral veil + "SEALED · BELL SEAL n" (driven by `UySealMask`); the server
pushes a player who stands inside a district they have not unlocked back to the gate (`Underyard.luau`, 0.5 s poll).

### 7.3 Anchors & per-player state attributes (builder contract)
Every gameplay point is an anchor Part (1×1×1, Transparency 1, Anchored, CanCollide/CanQuery/CanTouch false) in
`40_Underyard.Anchors`, named exactly as in `UnderyardLayout.Anchors`. Builders place geometry AROUND these points and
never move them. Seal-state visuals are attributes on parts/models (client `UnderyardFX` applies them per player):
* `UyShowAtSeal = n` — visible only when the player has cleared ≥ n seals (LocalTransparencyModifier).
* `UyHideAtSeal = n` — hidden once the player has cleared ≥ n seals (e.g. veils, rubble).
* `UyLightAtSeal = n` — Light/Neon brightened from 0 when ≥ n (lamps turning on as the world heals).
* `UyDistrict = "<name>"` on each district root Model.
* `HwLantern`, `HwCandle`, `HwBaseBrightness` (existing flicker contract), `SelfManagedFX = true` on emitter groups.

### 7.4 Rendering QA
`tools/render_preview.py` (WP-G) renders the baked Underyard / church / calendar stages to PNG (top, 2 isometric) from
`tools/export_parts.luau` JSON so reviewers can catch floating objects, empty space and overlaps.

------------------------------------------------------------------------------------------------------------------------
## 8. Chapter II progression and economy (WP-A rules; WP-I/J activities)

### 8.1 Phase schedule (date gates; UTC; Chapter2Config.Seals[i].Opens)
| Seal | Opens (UTC) | Offering (shards) | Activity |
|---|---|---|---|
| I ECHO | 2026-10-20 00:00 | 100 | Echo Dig |
| II PROCESSION | 2026-10-20 00:00 | 200 | Funeral Run |
| III REFLECTION | 2026-10-21 | 300 | Mirror Graves |
| IV HOLLOW | 2026-10-22 | 400 | Hollow Mine |
| V CHOICE | 2026-10-23 | 500 | Crooked Doors (3 door outcomes total; doors are limited per day) |
| VI CHOIR | 2026-10-24 | 650 | Choir Hunt |
| VII LAST BELL | 2026-10-26 | 800 | Last Bell Trial |
A seal is playable when: its date has passed, the previous seal is cleared, and its offering is paid at its altar in
Bell Square. Clearing = server-validated trial success (§8.4). Seals are not a timer: the date gate only opens new
story beats; players always have contracts, coffins, doors, resonance, boss and older trials to play.

### 8.2 Bell Shards and daily diminishing returns
Sources (all server-granted, only in the Underyard / Chapter II systems; passive dog farm = 0):
| Source | Amount | DR? |
|---|---|---|
| Perfect Hit streak (every 5 consecutive Perfects on Underyard targets) | +2 (cap 10 per minute) | yes |
| Echo dig point / hollow ore / choir spirit / trial objective | 1-4 each (per activity table) | yes |
| Trial clear (repeat) | Seal table `Repeat` (20-60) | yes |
| Trial first clear / seal clear | Seal table `First` (150-400) | no |
| Daily contract | 60 each | no |
| Gravekeeper (Ch2-unlocked players, full reward): III / IV / V / finale | 25 / 40 / 70 / 250 | yes (finale first clear exempt) |
| Crooked Door reward outcome | 30-80 | yes |
| Resonance milestone buff | +25% on streak shards for 5 min | – |
| Candy → Shards exchange (Toll Box) | 25 Candy = 1 shard, max 40 shards/day | no (own cap) |
DR (`Chapter2Config.DailyReturns`): by raw shards earned today (UTC): first 500 at 100%, next 500 at 35%, beyond 10%.
`Chapter2Rules.ApplyDR(rawToday, amount, cfg) -> effective, newRawToday` integrates across tier boundaries (exact, not
per-grant rounding drift: keep `Eff` as a float in the profile and grant floor(cumEff) − floor(prevCumEff)).

### 8.3 Catch-up (late players)
* **Rested allowance:** for every full UTC day since `Chapter2Config.Start` (2026-10-20) on which the player earned
  < 500 raw shards, `Rested.Pool += (500 − earned) × .5`, capped at 750; rested shards are consumed before DR tiers
  (they extend the 100% tier).
* **"The Bell remembers":** a seal whose date opened ≥ 2 days ago costs 40% less to offer.
* All seals are already open for late players, so they can progress several seals per day while still hitting DR.

### 8.4 Seal activities (server-validated; Seals framework + one module each; WP-I seals I-IV, WP-J V-VII)
Common: start at the seal altar (prompt "BEGIN TRIAL") or the activity's start point; solo or party (other
eligible players within 30 studs at start join, max 6); a run has a time limit; leaving the district, dying or
bleeding out fails it for that player; server tracks everything (positions sampled at 4 Hz for movement trials).
Ranks: Clear and **Gold** (stricter target; Gold first time = +1 Coffin Key). Each seal clear: cinematic (§16.2: bell
toll, camera on the tower, the seal's altar ignites, the next gate veil dissolves, district lights come on
(`UyLightAtSeal`)), journal entry, rewards (`Chapter2Config.Seals[i].Rewards`): shards First, 1 Coffin Key, plus
Seal I → H09 Bell Pup, Seal IV → H10 Candle Corgi, Seal VII → H11 Mourning Shiba + plot cosmetic "Crooked Bell Tower".

1. **ECHO DIG (Bell Square).** 90 s. Haunted echo points (Strike targets, kind `UyEcho`, 1 circle) appear at the 16
   `EchoPoint_n` anchors; each lives 4.5 s (+4 with H09) then "jumps" (Strike.Move) to another anchor with a
   telegraphed trail; dig it before it jumps. Clear: 12 echoes; Gold: 18 with ≥ 60% Perfect.
2. **FUNERAL RUN (Carnival).** Timing/movement: 10 checkpoint rings (`RunCheckpoint_1..10`) in order within 75 s,
   past swinging coffin pendulums (`RunPendulum_1..3`, period 3.2 s, knockback + 12 Event HP), the turning carousel
   (`RunCarousel`, ride it between checkpoints 5-6), and a coffin conveyor. Server validation: checkpoint order,
   minimum leg time from distance / (max speed 72 × 1.15), no teleport jumps. Clear: finish; Gold: ≤ 55 s.
3. **MIRROR GRAVES (Marsh).** Puzzle: 6 graves around the mirror pond (`MirrorGrave_1..6`) each show a rune facing
   one of 4 directions (prompt "TURN" rotates 90°). The pond reflection (client) shows the target arrangement
   **mirrored left↔right** (grave i reflects grave 7−i). Per-player daily seed, server checks the solution on
   "CONSULT THE POND". 3 rounds of rising difficulty (4, 5, 6 active graves) within 4 min; wrong consult = −15 s.
   Clear: 3 rounds; Gold: no wrong consults.
4. **HOLLOW MINE (Undercrypt).** 4 min run on the mine floor: break 14 hollow ore nodes (Strike kind `UyHollowOre`,
   tier-normalised Power HP) at `MineNode_1..12` (respawning), while hazards (falling rocks: Circle r 6 telegraph 1.4 s
   18 HP; gas vents: Circle r 5 lingering 6 HP/s; collapsing tunnels: Line) hit Event HP. Downed teammates can be
   revived. Clear: 14 cores; Gold: 20 cores without being downed.
5. **CROOKED DOORS (Crooked Row).** Door wall with 4 doors (`Door_1..4`). Door opens per player per day:
   `Doors.PerDay = 3` (+1 with all daily contracts claimed). Each open = server roll (H13 Moth Hound: 35% chance a
   moth marks the reward door before choosing): Reward 40% (chest: shards 30-80, dust, 15% Coffin Key, small chance
   showcase find), Challenge 30% (25 s survival hazard dance in the Door Court), Mini boss 20% ("THE DOORKEEPER",
   Strike target with telegraphed slams, Event HP), Rare room 10% (teleport into the hidden room `RareRoom`: 3
   chests, guaranteed showcase find + 1 Coffin Key + 0.5% H16 roll). Seal V clear = complete 3 door outcomes
   (challenge/miniboss must be won; reward/rare count automatically) — therefore ≥ 1 day.
6. **CHOIR HUNT (all unlocked districts).** 8 min. 7 choir spirits (Strike kind `UyChoir`, single circle that only a
   Perfect catches; a Good hit makes it flee 25 studs) wander along `ChoirPath_*` anchors; a faint melody (each spirit
   sings one note of the Last Bell's song, 3D) is the only hint; H13 Moth Hound shows the nearest. Clear: all 7;
   Gold: ≤ 5 min.
7. **LAST BELL TRIAL (Black Bell Arena).** Mechanic gauntlet vs "THE BELLKEEPER" (spectral sexton holding the Black
   Bell's rope): wave 1 shockwave rings (jump gaps), wave 2 four chain anchors to break with Perfect hits in pulse
   windows (preview of the finale), wave 3 weak-point burn while dodging Line + Circle hazards; Event HP; party up to 6;
   6 min limit. Clear: defeat; Gold: no one bleeds out.

### 8.5 Daily contracts (Chapter2Config.Contracts)
3 per UTC day per player (deterministic seed userId+day, like Chapter I quests), from: Perfect hits in the Underyard
(40), clear any Bell Trial (1), open a Crooked Door (1), catch choir spirits (3), dig echo points (15), break hollow ore
(12), revive an ally (1), deal Gravekeeper damage (2500), earn Bell Shards (250), open a Black Coffin (1), contribute
Resonance (150). Each claim: 60 shards (DR-exempt); all 3 claimed → 1 Coffin Key (`C2ContractBonus`). Unclaimed
contracts expire at UTC midnight.

### 8.6 BELL RESONANCE (server mechanic; Resonance.luau)
Server-wide value from Underyard actions: Perfect 1, streak 3, echo/ore/spirit 4, trial clear 60, door 10, revive 15,
boss damage 1 per 150 armor. Goal = `Base 4000 × clamp(activePlayersInUnderyard / 6, .6, 2)` recomputed each minute;
milestones (fraction of goal): 25% RESONANT TOLL — +25% streak shards for 5 min (Underyard); 50% — 1 Coffin Key to
every player active in the Underyard in the last 3 min (per player ≤ 2 per UTC day); 75% — 6 Resonant Echo spots
in Bell Square for 3 min (bonus shards + resonance); 100% — **BLACK BELL ASSAULT** in the Black Bell Arena: a server
raid (Bellkeeper "Assault" variant, scaled HP by attackers, open to every Chapter II player regardless of seals,
8 min) with shards + key + 2% coffin-grade drop roll; then the counter resets. Late joiners get the current state.
AFK players get nothing (activity window 180 s).

------------------------------------------------------------------------------------------------------------------------
## 9. Rewards (WP-A coffin rules; WP-K content; WP-L UI)

### 9.1 Coffin Keys
Sources: daily contracts bonus (1/day), each seal clear (1), each seal Gold first time (1), first full Gravekeeper
clear on III / IV / V (1 each), finale first clear (3) / repeat (1), resonance 50% (≤ 2/day), Crooked Door reward 15% /
rare room 100%, Dex II milestone 3 (1), Chapter II tutorial (1, guaranteed first coffin). Max stored 12. Never sold.

### 9.2 Black Coffin (Coffin.luau) — opening costs 150 Bell Shards + 1 Coffin Key, at the coffin shrine in Bell Square.
### 9.3 Black Coffin drop table (Chapter2Config.Coffin.Table; weights sum 100 000; shown in the UI as %)
| Group | Rows | Weight | Chance |
|---|---|---|---|
| Lucky Dust 60-120 | 1 | 24 000 | 24% |
| Bell Shards 40-90 (refund) | 1 | 15 000 | 15% |
| Bones 300-600 | 1 | 8 000 | 8% |
| Coins (income 30 min, min 50 000) | 1 | 9 000 | 9% |
| Cosmetic Fragments 1-3 | 1 | 6 000 | 6% |
| Coffin Key (refund) | 1 | 1 500 | 1.5% |
| Showcase finds (15; by tier Common 3 000 ×5, Rare 1 800 ×5, Epic 1 500 ×3, Legendary 700 ×2) | 15 | 29 900 | 29.9% |
| Full plot cosmetic (10 × 150) | 10 | 1 500 | 1.5% |
| Full pickaxe skin (6 × 95; the 7th is Dex-only) | 6 | 570 | 0.57% |
| Event dog H09 220, H10 160, H11 160, H12 120, H13 120 | 5 | 780 | 0.78% |
| Mythic dog H14 32, H15 32 | 2 | 64 | 0.064% |
| SECRET H16 HOLLOW KING | 1 | 4 | 0.004% (1 in 25 000) |
| (filler to 100 000: added to Lucky Dust) | | 3 686 | |
Rolled server-side with a fresh server `Random` (no client seed); the row is recorded in `Coffins.Last`.
**Duplicates (§9.4) are converted, never wasted.** Presentation §9.7.

### 9.4 Duplicates / fallback
A cosmetic (decor, skin) already owned at max, or a showcase find already owned (Owned.Finds), converts:
plot cosmetic → 12 fragments + 400 dust; pickaxe skin → 25 fragments + 800 dust; showcase find → 80 shards + 150 dust
(Legendary find → 3 fragments extra). Dogs are never converted (a duplicate dog is still a dog). If item storage is
full, a find converts as a duplicate and the client says so.

### 9.5 Fragments shop (Bell Square "THE TAILOR OF THE DEAD" panel in the Underyard window)
Craft a chosen plot cosmetic for 45 fragments, a chosen pickaxe skin for 90 (not the Dex-only Secret skin).
(Deterministic bad-luck path; expected ~1-2 crafts over the event for a dedicated player.)

### 9.6 Event Journal
Underyard window tab JOURNAL: entries unlock with story beats: Chapter I summary, `reveal`, `descend`, `seal1..7`,
`finale`, `assault`. Each: title, 2-4 lines of story (EN+RU), date. **Replay** buttons: "И ЭТО ВСЁ?" notification,
church cinematic, each seal cinematic, portal transition, Chapter I guide (`Bus "Onboarding" {Replay=true}`), brew
finale (A04 §11 recipe), finale intro (if seen). Replays never grant or set flags.

### 9.7 Coffin opening presentation (client CoffinFX, WP-K)
The coffin on the shrine (prebuilt model `BlackCoffin` at anchor `CoffinShrine`): chains tighten and snap one by one
(3), candles around flare, lid rattles (shake + knock cues), cracks of light along the seams in the rarity colour,
lid blasts upward and hangs, a light pillar (beam) in rarity colour, card reveal (3D model of the reward: dog /
cosmetic / find / currency icon) with rarity banner. Rare+ adds a ring shockwave; Mythic adds lightning and a slow-mo;
**Secret (H16):** total blackout, music cut, a black moon rises behind the coffin and eclipses, a crown of violet fire,
the Hollow King silhouette walks out, server-wide announcement banner "<name> RAISED THE HOLLOW KING" — designed to be
recorded. Skippable after the lid opens (fast-forward to the card). Duplicates show the conversion on the card.

### 9.8 Content lists (WP-K)
**Event dogs H09-H16** (DogDefinitions rows Index 209-216, `EventDex = "Underyard2026"`, EventIndex 9..16, Acquisition
Event, MuseumExcluded; generalise the post-loop patch in DogDefinitions:148-155 to any `EventDex`). Abilities count
while the dog is assigned to a yard dig slot (same rule as H01-H08). Ability numbers in `Chapter2Config.Dogs`.
| Code | Id | Rank | Name EN / RU | Ability (Chapter II mechanic) |
|---|---|---|---|---|
| H09 | `HW_BellPup` | 2 | Bell Pup / Колокольчик | ECHO EAR: echo points live +4 s longer; the next echo jump target pulses |
| H10 | `HW_CandleCorgi` | 3 | Candle Corgi / Свечной корги | CANDLELIGHT: hazard telegraphs reach you .35 s earlier (Hollow Mine, trials, boss) and mine gas deals −30% |
| H11 | `HW_MourningShiba` | 3 | Mourning Shiba / Скорбная шиба | MOURNING VEIL: once per fight you self-revive after 8 s downed; revives on you are 40% faster |
| H12 | `HW_CoffinPug` | 4 | Coffin Pug / Гробовой мопс | COFFIN SENSE: 8% chance a Black Coffin gives a bonus showcase-find roll; duplicate conversions +25% |
| H13 | `HW_MothHound` | 4 | Moth Hound / Мотыльковая гончая | MOTH SWARM: 35% chance moths mark the reward Crooked Door; shows the nearest choir spirit |
| H14 | `HW_Bridehound` | 5 | Bridehound / Невеста-гончая | ETERNAL VOW: +15 max Event HP; you revive allies 2× faster; an ally you revive gets a 20 HP shield |
| H15 | `HW_BellkeeperWolf` | 5 | Bellkeeper Wolf / Волк-звонарь | RESONANT HOWL: your Perfect hits count ×2 for Resonance and deal +25% to chains/bells/weak points (inside BossMath caps) |
| H16 | `HW_HollowKing` | 6 | Hollow King / Полый король (SECRET) | CROWN OF THE UNDERYARD: every 20 active minutes in the Underyard your next Black Coffin gets one extra showcase-find roll; royal violet aura; unique Secret arrival |
Each needs: voxel rig + procedural clips (pattern of `Models/EventDogs.luau` H01-H08), baked into
`ServerStorage.DogTemplates`, `RS.MenuModels`, `RS.DogAnimationClips` by a new offline edit `tools/edits/30_dogs2.luau`;
localization; H16 also `SecretArrivalConfig` + SecretArrivals entry.
**Dex II milestones** (`Chapter2Config.Dex2Rewards`): 3 dogs → 300 shards + 1 key; 5 → plot cosmetic "Spirit Fence" +
dust 1500; 7 → pickaxe skin "Toothy Alarm"; 8 → Secret skin "Bell Reaper" + title "HOLLOW CROWN".
**Pickaxe skins (cosmetic only; stats from the real tier)**, ids `UY_*`, added to `Config.Skins` with `Chapter = 2`:
`UY_ToothyAlarm` Зубастый Будильник (Epic) · `UY_FateHand` Рука Судьбы · Погребённая (Legendary) · `UY_Laughsaw`
Смехопила · Похоронная (Legendary) · `UY_TVHead` ТВ-Башка · Помехи (Mythic) · `UY_NastyOctopus` Мерзкий Спрут · Болотный
(Mythic) · `UY_GummyHorror` Мармеладный Ужас (Mythic) · `UY_BellReaper` Жнец Колокола (Secret, Dex II 8/8 only). New
designs with Underyard motifs (do not reuse the tier models); each with sound kit (soft impact §16.3), palette,
hit theme, crit text, optional live FX. Module `RS/Halloween/PickaxeSkins2.luau` registers into PickaxeSkins tables.
**Plot cosmetics (decor, `Reward = "Underyard2026"`)**: Crooked Bell Tower (Large, idle: bell swings), Whispering Tree
(Large, branches sway + whisper wisps), Haunted Kennel (Small, door creaks/eyes blink), Spirit Fence (Small, wisps drift),
Coffin Flowerbed (Small), Floating Tombstones (Small, bob), Funeral Lantern Set (Small, flicker), Moon Statue (Large,
moon glows/pulses), Ghost Fountain (Large, ghost water arcs), Animated Grave Gate (Large, gates swing). Recipes in
`RS/Decor/DecorModels.luau` (budgets: Small ≤ 40 parts, Large ≤ 120) + catalog rows + a new client idle-animation loop
(`PlotCosmetics` or `HC/DecorIdle.luau`) driven by attributes `IdleAnim = "Swing"|"Sway"|"Bob"|"Flicker"|"Pulse"|
"Spin"|"Blink"` on parts/models.
**Showcase finds** (ItemDefinitions entries NOT in any DepthDefinitions list, Class "Underyard", BaseDropChance chosen
for the showcase tier, Forge recipes in a new `RS/DogEconomy/ItemModels/Underyard.luau`): Cracked Bell Clapper,
Dead Wedding Ring, Blue Funeral Rose, Crooked House Key, Coffin Nail, Wax Hand, Bottled Whisper, Black Feather, Broken
Pocket Watch, Lost Veil (Common tier ×5 = Coffin Nail, Black Feather, Wax Hand, Crooked House Key, Blue Funeral Rose;
Rare ×5 = Bottled Whisper, Broken Pocket Watch, Lost Veil, Cracked Bell Clapper, Tiny Tombstone; Epic ×3 = Dead
Wedding Ring, Ghost Photograph, Mourning Locket; Legendary ×2 = Bellkeeper Mask, Hollow Heart). Each with a
detailed 3D model (≤ 80 parts) that reads at showcase size, plus a glint/aura attribute for the showcase FX.

------------------------------------------------------------------------------------------------------------------------
## 10. Combat: Event HP, hazards, downed/revive (WP-B)

### 10.1 EventHP.luau (server)
* Combat zones: the Gravekeeper pit while a fight runs (fighters), the Black Bell Arena during trial/assault, the
  Hollow Mine run, Crooked Door challenge/mini boss, Funeral Run (pendulums only). API:
  `EventHP.Enter(player, zoneId, opts{MaxHP?})`, `EventHP.Leave(player, zoneId)`, `EventHP.InCombat(player)`.
* MaxHP 100 (+15 H14). On Enter: HP = MaxHP (never resets mid-fight on re-enter within 30 s).
* `EventHP.Damage(player, amount, source, info) -> applied` — clamps, respects i-frames (0.6 s after a hit),
  shields, Weakened (+25% taken), CANDLELIGHT etc. via `BossMath`. Writes `HwHP`; Signal `Combat {Kind="Hit", UserId,
  Amount, Source, HP}` to the player (+ nearby for floating numbers).
* At 0: **DOWNED** (`HwDowned`, `HwDownedUntil = now + 20`): cannot strike (Strike `CanAct` hook rejects
  `HW:DOWNED`), WalkSpeed 5 (server sets, restored after), excluded from boss targeting, a ProximityPrompt "REVIVE"
  (Hold 2.2 s, range 9, H14 halves, revived player gets 40 HP) appears on the downed character. Self-revive (H11).
* Bleed-out (timer expires): teleport to the zone's edge spawn (pit rim / arena edge / mine entrance), HP 60%,
  **WEAKENED** 25 s (−30% damage dealt, +25% damage taken; `HwWeakenedUntil`). Trials: bleed-out = that player fails
  the trial (party continues). Team wipe (everyone downed) = encounter fails.
* Regen: +2 HP/s after 8 s without damage (not while downed). Outside combat: attributes cleared, HP hidden.
* Humanoid health is never touched; normal deaths (falls) still work as before; Event HP never kills.

### 10.2 Hazards.luau (shared pure) + server/client protocol
Shapes: `Circle{Center, Radius}`, `Ring{Center, Inner, Outer}`, `Line{From, To, Width}`, `Cone{Center, Dir, Angle,
Radius}`, `Safe{Center, Radius}` (inverse: damages everyone OUTSIDE), `Box{CFrame, Size}`. `Hazards.Contains(shape,
pos) -> bool` (Y band ±10 studs unless `Height`). Server spawns: `EventHP.Hazard(zoneId, def)` where def =
`{Id, Shape, Telegraph (≥ 0.9 s, ≥ 1.2 s for Damage ≥ 25), ImpactAt (server time), Damage, Knock?, Linger?, DPS?,
Color?, Kind, Source}` → Signal `Hazard` (to players within 220 studs) → at ImpactAt the server tests every combat
player of that zone (using server positions with a 0.12 s grace rewind tolerance: a player who was outside at either
ImpactAt or ImpactAt−0.12 is spared) and applies damage. Client `CombatFX` draws telegraphs (ground decal/neon rims,
fill growing to impact, line sweeps, safe zone glow) from these signals. **Fairness rules:** every damaging attack is
telegraphed; no single hit above 45% MaxHP at difficulty V (40% for trials); a moving safe zone always moves at
≤ 11 studs/s; at least one safe gap exists for every Ring/Line pattern.

### 10.3 Client CombatHUD (HC/CombatHUD.luau)
Event HP bar (bottom centre above the hotbar / touch controls, between `HUDInnerLeft/Right`; large numerals
"100 / 100", segment ticks every 10, damage chunk lag, red flash + vignette on hit, low-HP heartbeat < 30%), shield
overlay, WEAKENED pill, DOWNED overlay (desaturate, "DOWNED · WAIT FOR A REVIVE" + bleed-out ring timer, ally list
with distance, self-revive button when H11), REVIVE progress ring for the reviver, floating damage numbers. Shown only
while `HwCombat`. Hidden with menus/HideUI. Built in pcall; torn down on CharacterRemoving and when combat ends.

### 10.4 BossMath.luau (shared pure) — damage scaling
* Per-hit armor damage: `ArmorK × raw^ArmorExp` with ArmorExp .55 → **.42** (Chapter2Config.Boss.ArmorExp).
* Per-player soft cap (rolling 3 s window): full value up to `MaxArmorBase(d) × .0045` per second; beyond that 20%.
  Mechanic damage (weak points, chains, real mounds, rocks, counter windows) bypasses 60% of the cap.
* Perfect ×1.0 extra on top of pickaxe PerfectMult (already in raw); Weak point ×3 (existing); **SYNC STRIKE**: when
  ≥ 2 players land Perfect hits on the boss within 0.5 s, both get +50% for those hits.
* WEAKENED −30%. Max-gear players still lead, but mechanics/perfects/coordination dominate (target: a max-gear player
  spamming non-perfect hits does ≤ 35% of the DPS of the same player executing mechanics).
* Rim camping removed: plates/weak points are hittable only from inside the pit (`Layout.InPit`), and only pit
  players count as fighters for armor scaling.

### 10.5 Boss attack damage (Chapter2Config.Boss.Damage; × difficulty mult I .7, II .9, III 1.1, IV 1.3, V 1.5)
Stomp 12, Slam 16, Sweep 10, Erupt 14, FakeMound 8, Bite 6, RockImpact 10, RockExplode 14 (+ curse as before).
Endgame patterns added for difficulties **III, IV, V only** (`Endgame` table): GRAVE LINES (3-5 Line hazards sweeping
across the floor in sequence, 18), LANTERN WALK (Safe zone: a moving lantern circle r 9 drifts around the pit for 8 s;
outside it 7 HP/s after 1.2 s grace), BONE RAIN (12-18 Circle r 4 with staggered impacts, 12), CURSED ROCKS
(existing, waves capped at `Rocks.Waves` per phase on III/IV, unlimited on V), WEAK POINT TIMING (weak points only take
Perfect hits on V). Telegraph times shrink with difficulty but never below §10.2 minimums.

------------------------------------------------------------------------------------------------------------------------
## 11. Gravekeeper difficulty V: false victory + post-death finale (WP-C server, WP-N client)

Only when `BossFinaleEnabled`. Server `BossFinale.luau`, entered from `Boss.luau` instead of `defeat(F)` when
difficulty == 5 (A02 §7 says: keep F alive, do not append Config.Boss.Phases, publish Phase/PhaseName, then call
`finish(F, "Defeated")` once so `grantAll` pays once).
1. **FALSE VICTORY** (≈ 6 s): armor 0 → server publishes `Finale.State = "FakeDeath"`. Client: music hard stop, the boss
   collapses (existing death sequence start), a fake reward flash ("THE GRAVEKEEPER FALLS!" + a reward card shell), then
   2.5 s of silence. Then a rumble, screen shake, the bell begins to toll, the reward card cracks and dissolves to
   ash ("…not yet"), the boss spirit tears out of the corpse.
2. **PHASE I — THE BELL TOLLS.** The Black Bell (giant, black iron with violet runes) descends over the pit centre
   (y 28 above floor); the spirit enters it. Four cursed chains (`N/E/S/W` from the rim anchors to the bell). Raw DPS on
   the bell does nothing (immune; hits show "IMMUNE"). Every 6-8 s the bell emits SHOCKWAVE rings (Ring hazards with a
   gap, 14 dmg ×1.5). One chain at a time is ACTIVE (glows, pulses at 1.2 s period); only **Perfect** hits landed
   during the pulse's bright half count; chain needs `6 + 3 × (fighters − 1)` counted hits. Break all 4.
3. **PHASE II — THE BURIED CHOIR.** Arena changes: fog, the terrace ring sprouts 6 cursed candles; ghost dogs (Strike
   adds, chase + bite 8) spawn in waves; the Gravekeeper spirit attacks from the background (Line volleys from the
   rim, telegraphed). The bell shows a candle pattern (6 lit/unlit); players hit candles to toggle them; matching the
   pattern (3 rounds) exposes 3 BURIED WEAK POINTS (glowing mounds on the floor, Strike kind `FinaleWeak`, any hit,
   tier-normalised HP `10 + 5 × (fighters − 1)` each). Clearing 3 rounds → phase III.
4. **PHASE III — THE LAST BARK.** A huge spectral hound (near-black silhouette, white-violet bones, burning eyes) rises
   behind the pit with a Black Moon behind it. Rhythm/bullet-hell: patterns on a beat (100 BPM): circle bursts, line
   barrages, expanding rings with gaps, moving safe circles; after each pattern the hound BARKS and staggers — a 3 s
   COUNTER WINDOW where its jaw weak point takes Perfect hits only (each counts 1, cap 6 per player per window); hound
   "bark points" = `24 + 10 × (fighters − 1)`. Fail = team wipe or 7 min total → "THE BELL SILENCES YOU" (consolation =
   normal difficulty V full reward without finale extras).
5. **VICTORY** → real reward (§11.1), journal `finale`, cinematic: the hound howls, shatters into moths, the Black Moon
   cracks, dawn-blue light; music resolves.
### 11.1 Finale rewards (Chapter2Config.Finale.Rewards; on top of difficulty V full reward)
First clear: 250 shards (DR-exempt), 3 Coffin Keys, title "THE LAST BARK", plot cosmetic "Moon Statue", 12% H15
Bellkeeper Wolf, 0.4% H16. Repeat: 120 shards (DR), 1 key, 1.5% H15, 0.05% H16, 6% a random Underyard pickaxe skin.

------------------------------------------------------------------------------------------------------------------------
## 12. Chapter I rebalance (WP-E) — numbers in Config.luau, old values kept in comments `-- was X`

### 12.1 Targets
* Pumpkin Lucky Block acquisition ≈ 5× slower (target 4-6×); passive Halloween generation ≈ 20% of today.
* Already-owned rewards untouched; blocks already owned keep their frozen pools (A03 §0).
### 12.2 Changes
| Lever | Was | Now |
|---|---|---|
| Cauldron TRICK price | 80 flat | 140 base, +20% per trick within the same UTC day ("the cauldron grows hungry", cap 3×) |
| Perfect Hit candy cap / min | 40 | 20 |
| Candy MinuteCap | 220 | 110 (applied BEFORE multipliers now: rush/moon keep their value) |
| Ore candy | 1-3 | 1-2 |
| Dig spot candy | per type | ×0.6 (rounded, min 1) |
| Door candy treat/trick | 6-14 / 2-5 | 4-9 / 1-3 |
| Daily quest candy | 25-50 | ×0.6; EarnCandy no longer counts quest/reward candy |
| All-quests bonus | 1 Pumpkin + 30 | 1 Pumpkin + 15 (unchanged block: the daily active anchor) |
| Blood Moon candy bonus | +50% | +25% |
| Boss candy | 20-100 | ×0.6; boss DogChance by philosophy (Legendary ×.05, Mythic ×.025); CursedBlock IV .35→.03, V 1→.08; EclipseChance .03→.0003 |
| Exorcism 2500 block | everyone on server | only players active in the Dead Yard in the last 180 s |
| Passive yard event mutations (YardChance) | .004/.0015/.0012 | ×0.2 |
| Pumpkin / Cursed Pumpkin tables | §A03 4.1-4.2 | rescaled by `DropRates.Rescale` (§12.3) |
| Cauldron brew time | 7 days flat | `min(7 days, EventClaimDeadline − StartedAt)` with deadline 2026-10-31 18:00 UTC (late-starter catch-up, fixes stranded brews) |
Expected candy/hour for an active player: ~3 000 → ~1 400; block price ×1.75-3 within a day → ≈ 5× fewer blocks
per hour of grinding; the daily quest block keeps a fair daily floor.
### 12.3 Rare prize philosophy (`DropRates.Rescale(rows, factors, filler)`)
Each row's **probability** is multiplied by its class factor; the freed probability goes to filler rows. Classes:
resources (Cash, Bones, Candy) ×0.5 · Rare/Epic items, decor, mutations and dogs ×0.10 · Legendary ×0.05 · Mythic
×0.025 · Secret ×0.01. Filler for Pumpkin blocks: `Lucky Dust` (Pumpkin 40-70, Cursed 150-260) — useful (§14), so a
"miss" still feeds the Dust Forge. The function returns integer weights (scale 1e6) and a report used by the UI
(odds) and docs. Factors in `Config.Rebalance.RarityScale`. Tests assert every resulting probability equals
old × factor within 1e-6 and that weights sum to 1e6.

------------------------------------------------------------------------------------------------------------------------
## 13. Halloween calendar (WP-M)

`HalloweenCalendarConfig`: `Target = {Year=2026, Month=10, Day=31}` (UTC 00:00), `CheckEvery = 120` s, `Stages`:
| Stage | From | Folder | Visual (cumulative) |
|---|---|---|---|
| 1 | D-7 | Stage01 | first orange/dead grass patches (≈10% of grass parts tinted), very light fog, a few new crooked trees, dry leaves |
| 2 | D-6 | Stage02 | ≈20% grass, a few pumpkins, first crooked face trees, night ambience slightly darker |
| 3 | D-5 | Stage03 | ≈33% grass, fog up, candles, rare bats, strange night sounds |
| 4 | D-4 | Stage04 | more creepy trees incl. on the sky islands, faces with eyes that sometimes open, building windows that blink |
| 5 | D-3 | Stage05 | > 50% grass, ground fog, distant ghosts, bigger moon, lamps tinted orange/purple |
| 6 | D-2 | Stage06 | most of the map, stronger fog, branches move, more pumpkins, creeping roots, ambient whispers |
| 7 | D-1 | Stage07 | almost fully infected: heavy fog (gameplay visibility kept: Atmosphere Density ≤ .36), crooked trees, orange grass, candles, bats, spectral effects, moon transformation |
| 8 | Oct 31 | Stage08 | full transformation set pieces |
Implementation: stage decorations are prebuilt offline (`tools/edits/41_calendar.luau` from
`ServerStorage/HalloweenCalendarBuild/*`) into `ServerStorage.HalloweenCalendar.Stage01..Stage08` (Folders, saved in
the place, editable in Studio). `SSS/Halloween/Calendar.luau` (server, UTC `os.time()`, checks every 120 s) moves every
stage folder with stage ≤ current into `Workspace.DOGROTS_District.41_HalloweenCalendar` (reparent once; never clones
per heartbeat) and back if the date is reset (Studio), and publishes `State.Calendar`. Client `HC/CalendarFX.luau`
applies per-stage: grass tint fraction on `EventTintSurface` grass parts (deterministic per-part hash order; store
originals; re-apply every 60 s so world-event tint restores don't fight it), Atmosphere/ColorCorrection/moon via a
Halloween `Lighting.Layer("CALENDAR", ...)` (A05 §5.2), lamp tint strength, window blink (museum `BlueWindow`, shelter
glass; Neon + warm colour, restore after), tree eyes (`CalEyes` attr), branch sway (`CalSway`), ghosts, whispers,
quality-scaled. Studio overrides: `CalendarConfig.Studio.ForceStage` and `C2Debug Calendar n`.
`verify_world` budgets the `ServerStorage.HalloweenCalendar` total (≤ 9 000 parts, ≤ 90 lights).

------------------------------------------------------------------------------------------------------------------------
## 14. Lucky Block dismantling (WP-D)

* Feature `SSS/Economy/Features/LuckyDust.luau` (Order 80); actions via `DogEconomyRequest`:
  `DismantleQuote {Uids ≤ 30}` → `{Token, Total, Rows=[{Uid,Tier,Dust,Bonus}] , NeedsConfirm}`;
  `Dismantle {Token, Confirm?}` (Confirm required when any block is rank ≥ 4 Legendary+); `DustForge {Tier}`.
* Eligible: owned, `State == "Stored"`, not opening (`LuckyLifecycle.Opening[uid]`), not in an active trade offer
  (refuse while `TradeByUser`); legacy `LuckyCredits` stacks via `{Credits = {[tier] = n}}`; PaidRandom blocks allowed
  (converted deterministically).
* `DustRules.BlockValue(tier) = min(ConveyorPrice, EV of contents)` (Common 5 000 … Secret min(45M, 10.38M));
  Pumpkin = 600 000, Cursed Pumpkin = 4 000 000 (TradeValue). `Yield = floor(BlockValue × .25 / 100)` dust
  (1 dust ≈ 100 coins of block value; Salvage `.25` in config, allowed range .20-.30). Pumpkin/Cursed also give 15 / 50
  Candy (event resource). **Forge:** craft Common/Rare/Epic/Legendary blocks for `BlockValue / 100` dust (100%);
  no profitable loop exists (proof in tests: any dismantle→forge cycle returns ≤ 0.43× of the original value).
* UI (InventoryScreen block detail): DISMANTLE button (Kit, Activated) → quote card with dust preview → Legendary+
  shows a hold-to-confirm Kit Modal (Danger) → result toast + dust fly-in; multi-select "DISMANTLE ALL COMMON/RARE";
  FORGE tab/panel. Lucky Dust HUD pill appears when > 0.
* Chapter II uses Lucky Dust too (coffin rows, duplicate conversion, filler); dust has no other conversion.

------------------------------------------------------------------------------------------------------------------------
## 15. Fixes to existing systems

### 15.1 Shelter (WP-D2) — implement every A07 defect fix
D1 server Visit radius 26 + reception box; separate Ready/Allow messages; client loading/error/RETRY + one auto-retry.
D2+D4 rebuild the Shelter UI as a Kit window `Modules/ShelterScreen.luau` (`kitScreens.Shelter`, opened by the
server prompt through `DogEconomyOpen`, list built once per List, selection restyles only, virtualized list /
lightweight previews, phone sheet). D3 TTL-based expiry (server time). D5 GUIIntegration: prompts enabled derived from
`Owner == "HUD"` (ref-counted locks, not a saved boolean), wrap `N.Acquire` so it always reaches a consistent state, add
a 1 s watchdog (owner ≠ HUD but no owner surface visible for 2 s → `N.Close()`), touch-friendly close everywhere.
D6 Halloween reward card DisplayOrder 70 → 74. D7 release artifacts after a sale (`R.Features.Normalize`). D8 block
Favorite dogs too ("protected"), keep event dogs sellable but require a confirm hold for rank ≥ 5 and event dogs.
D10 pcall + FindFirstChild loops. D11 prompt HoldDuration 0. D12 clear quote on failure. D13 pcall per row. D14 gamepad
ButtonB/selection. A Shelter sale now counts as a sale for stats/tutorial (`RecordStats.Sale`). Halloween onboarding
fixes (A04 §12.1-2): `O.Begin` respects `blocked()`; token-guarded delayed restores; never re-enable controls owned by
GUIIntegration. **Lune E2E test** `tests/shelter_e2e.luau`: profile with dogs → List → Quote → Sell → balance changed →
flush to a fake store → reload profile (new Engine) → dog absent, coins kept; plus protection cases.

### 15.2 Main tutorial rebuild (WP-O) — §37/§38 of the brief
Server `OnboardingRules` Version 4: track
`0 Welcome → 1 Buy a dog → 2 Assign it → 3 Wait for a dig (find) → 4 Collect the loot → 5 Sell → 6 Upgrade tree →
7 Layers (open the layers panel, see the next layer + its requirement; done when viewed: server-side "Seen" via the
Tutorial action with Key) → 8 Mining Corner (hit ore) → 9 Strength (strength node) → 10 Lucky Blocks (walk to a Lucky Pad
and place/inspect a block, or claim the free Common block the tutorial grants at this step) → 11 Lab (walk to the
Mutation Lab entrance: server proximity check) → 12 DogDex (open the DogDex: Tutorial {Action="Seen", Key="DogDex"}) →
13 Trade (open the Trade screen; info card about trading at level 5) → 14 Done`.
Gameplay steps complete from profile state (Observe) or server-validated `Seen`/proximity; there is no NEXT on
action steps, but each action step offers "SHOW ME" (camera + path again) and, after 120 s without progress, "SKIP
THIS STEP" (server records `Skipped[step]`, continues; never a dead end). Migration v3→v4 maps old steps; Complete /
Skipped / Migrated stay complete (fix the `not t.Migrated` exclusion carefully: veterans are never pulled back in).
Client `Modules/TutorialDirector.luau` replaces `OnboardingGuide`'s UI: a state machine keyed on the server step
(`TutorialStep` attribute), own ScreenGui DisplayOrder 55 (above HUD/guides, below Kit windows 60), Kit card (title,
one sentence, objective + progress, buttons via Activated), per-step: 2.2 s camera focus on the target (Cinema, skippable,
skipped on ReducedMotion), Highlight on the target, `PathGuide.Show(destination)` arrow, world marker. Robustness:
request timeout 8 s (re-enable buttons, show retry), render in pcall, rebinding on CharacterAdded, survives
PlayerGui rebuild (Destroying → restart), target missing → fallback to path + marker at the destination anchor (never
hang), timeout per step for camera/target waits (3 s), no Modal, no hidden overlays above it. The Halloween guide stays
suppressed while the main tutorial runs; the HOW TO PLAY replay uses the director in replay mode.

------------------------------------------------------------------------------------------------------------------------
## 16. Presentation infrastructure (WP-P foundation; used by everyone)

### 16.1 Audio architecture (SoundGroups, offline edit `tools/edits/05_audio.luau`)
```
SoundService.DOGROTS_AUDIO (Folder)            -- ducked by music/secret logic (existing behaviour)
  Music (exists, .7) · WorldEvents (exists, .7) · Ambience (.8, new) · UI (1, new)
SoundService.DOGROTS_SFX (Folder, new)         -- gameplay; ducked only by the Mixer
  Pickaxe (1, new; DOGROTS_MiningSFX is re-parented/created under it) · Boss (1, new) · SFX (1, new)
```
`RS/AudioMixer.luau` (client): `Mixer.Group(name) -> SoundGroup` (Music, Ambience, Pickaxe, Boss, UI, SFX,
WorldEvents), `Mixer.Duck(reason, {Music=.., Ambience=.., ...}, fade)`, `Mixer.Release(reason, fade)` (per-group
baseline; quietest active reason wins), `Mixer.Preset.Cinematic = {Music=.15, Ambience=.35, Pickaxe=.25, Boss=.4,
SFX=.5, UI=.8, WorldEvents=.15}`. Routing changes: Halloween `Audio.Group` → Mixer groups (Ambience, UI, Music child
"Halloween", Boss cues `Group="Boss"`), `MiningAudio` → Pickaxe, `Kit.Sound` → UI, `WorldAmbience` → Ambience,
`SecretArrivals Scope:Duck` → Mixer.
### 16.2 Cinema (HC/Cinema.luau, shared by every cinematic)
`Cinema.Play{Id, Duration, Shot = fn(t, dt) -> CFrame?, Fov?, Focus = {Distance, Radius, Far}?, Letterbox = true,
Skippable = true, SkipAfter = 0.5, LockControls = true, HideUI = true, Duck = "Cinematic", OnSkip, OnDone, Timeline =
{{t, fn}}}` → handle {Done (Signal), Cancel()}. `Cinema.Busy()`. Rules: refuses (returns nil, OnDone(false)) if another
cinematic runs, the camera is not Custom, mining is active or a Kit window is open (unless `Force`); ReducedMotion →
static cuts, no shake; writes `cam.CFrame` every frame at RenderPriority.Camera+1 (so FX.Shake stays non-cumulative);
camera-parented `DepthOfFieldEffect "DOGROTS_CinemaFocus"`; letterbox ScreenGui DO 90 + "TAP TO SKIP"; sets gui
attribute `CinemaActive` (blocked() checks of guides/tutorial respect it); ref-counted control lock
(`Cinema.LockControls(reason)`/`Unlock`) that never fights GUIIntegration; guaranteed restore on error, death,
character removal and `Cancel`. Helpers: `Cinema.Shake(amount, dur)`, `Cinema.Impulse(strength)`, `Cinema.Flash(color,
strength, dur)`, `Cinema.Fade(alpha, dur)`, `Cinema.Title(en, ru, opts)`.
### 16.3 Pickaxe impact redesign (WP-P)
In `MiningAudio.pickaxe()` (A09 §7): drop the KNOCK/LAND thud rows (at ≤ .02) of every kit Hit/Perfect and insert ONE
pooled soft impact (pool of 4: KNOCK/LAND at different speeds, EQ Low +2 Mid 0 High −6, volume scale .45, dur .14,
fade .05), no THUMP distortion, pitch jitter uniform .96-1.04 per hit, never the same sample twice in a row; GainMakeup
2 → 0 on the mining compressor; Break cue softened; Halloween Dig* cues attenuated to .15 when a kit impact also plays.
Weak-point hit (Strike reply `Extra.Weak`/`BossDamage`): juicy cue `WeakPointHit` (crack + low punch + bright tick)
+ camera impulse. Perfect: tick (CLICK) + sparkle (PING arp) + crack (SLASH/CLICK) stack, played with rise pitch; remove
the extra Sparkle duplicate. Everything routed to the Pickaxe group; no clipping (sum of simultaneous voice volumes on a
local hit ≤ 1.1).
### 16.4 Underyard / finale music (procedural, Music.luau themes)
`UNDERYARD` (66 BPM, music-box + low choir drone + pizzicato waltz in D minor), `TRIAL` (108 BPM tense ostinato),
`COFFIN` (sting), `FINALE_BELL` (bell ostinato), `FINALE_CHOIR` (choir pads + heartbeat), `FINALE_HOUND` (100 BPM
driving, the hound pattern beat source), `REVEAL` (sub drones). Soundscape priority: BOSS/FINALE > TRIAL > UNDERYARD
> Blood Moon > ZONE > NIGHT. Underyard ambience beds: wind in a cavern, distant choir, dripping, marsh frogs (Marsh),
carnival organ fragments (Carnival), pickaxe echoes (Undercrypt).

------------------------------------------------------------------------------------------------------------------------
## 17. Performance
* Quality tiers via `Shared.Quality()`; new `Config.Quality` keys for all three tiers: `UnderMotes` (60/30/10),
  `Telegraph` (1/1/.6 detail), `FinaleFX` (1/.7/.4), `CalendarFX` (1/.6/.3), `CoffinFX` (1/.75/.5), `GhostLights`
  (12/8/5). Low: fewer particles, fewer dynamic lights (WorldDetailQuality already caps nearest 24/8), no distant
  animations (> 160 studs), no blur. Mechanics identical.
* World: anchored, shadows only on large solid pieces, lights `Shadows=false`, emitters under `SelfManagedFX` sub-models
  and registered in ParticleGovernor ROOTS (add `40_Underyard`, `41_HalloweenCalendar`). Streaming: district models
  `ModelStreamingMode = Atomic` only where animated; the rest default.
* Server: no per-frame loops over all players beyond 10 Hz combat ticks; hazards tested only against combat players
  of that zone.

------------------------------------------------------------------------------------------------------------------------
## 18. Underyard client (WP-H2 + WP-L)
`HC/UnderyardFX.luau`: zone detection (UnderyardLayout.InZone/Weight incl. Y), Lighting layer `UNDERYARD` (Prio 35:
ClockTime 0.5, Brightness 0.9, Ambient (52,48,92), OutdoorAmbient (60,58,110), ColorShift_Top (90,110,200), Atmosphere
Density .32 Haze 2.4 Color (70,80,140) Decay (30,20,60), Bloom .55/26/1.1, grade Contrast .12 Saturation −.15 Tint
(200,210,255)), seal-state attributes (§7.3), district veils, ambience beds, drifting motes, moths, ghost residents.
Prompts localized client-side. `HC/Chapter2Guide.luau` = Chapter II onboarding (§9). Underyard window (§19).

### 9. (cont.) Chapter II onboarding (server `p.Underyard.Tutorial`, client Chapter2Guide; quality like the cinematics)
A ghost-dog guide (spectral Bell Pup with a lantern) floats ahead; camera focus + highlight + arrow + short cards:
1. **Bell Shards:** "Hit the echoes" — 3 tutorial echo points in Bell Square (`TutorialEcho_1..3`, always on for
   tutorial players); first Perfect streak explained; done when ≥ 10 shards earned.
2. **First Trial:** the Trial of the Toll at the practice ring: ring the hand-bell 5 times in rhythm (5 Perfect hits on
   `TutorialBell`) — done on success.
3. **The Coffin:** camera to the Black Coffin; the tutorial grants 1 Coffin Key + 150 shards; the player opens it
   (guaranteed showcase find row on this first coffin).
4. **Event HP:** step into the practice ring → HP bar appears (`EventHP.Enter("Practice")`).
5. **Combat:** the Mourner dummy telegraphs 3 attacks (Circle, Line, Ring) — dodge 2 of them, then hit its weak spot
   with a Perfect; getting downed demonstrates revive (auto-revive by the ghost guide after 3 s).
6. **First Seal:** go to Altar I, offer 100 shards (the tutorial refunds it once) → Seal I trial unlocked → done.

------------------------------------------------------------------------------------------------------------------------
## 19. UI (WP-L)
* `Modules/UnderyardScreen.luau` — Kit window key "Underyard" (registered in `GUIIntegration.kitScreens`), title "THE
  UNDERYARD", subtitle "BENEATH THE LAST BELL", violet/moon-blue accent, Shards + Keys chips in the header. Tabs:
  **SEALS** (7 seal cards: date lock / offering / play / cleared / gold, story lines, rewards), **CONTRACTS** (3 daily +
  bonus key, reset timer, exchange box), **COFFIN** (keys, price, OPEN (only at the shrine; else SHOW THE WAY), visible
  drop-rate table grouped by tier with exact %, last 10 results), **DEX II** (H09-H16 cards, Dex II milestones,
  OPEN DOGDEX → DogdexScreen second event tab "THE UNDERYARD COLLECTION"), **COLLECTION** (pickaxe skins / plot
  cosmetics / showcase finds owned/unowned, fragments + TAILOR craft), **JOURNAL** (§9.6). Opened from: the HALLOWEEN
  window event tab (CHAPTER II card), a rail tile shown when eligible, prompts in Bell Square (`DogEconomyOpen`).
* HALLOWEEN window: event tab hero gets the CHAPTER II card (locked checklist or "DESCEND"/"OPEN UNDERYARD"); dex tab
  gets a "CHAPTER II" switch to the second page; cosmetics tab lists Chapter I skins only (filter `Chapter ~= 2`).
* `DogdexScreen`: second event tab (EVENT_DEX list) for `Underyard2026`; claims via `C2DexClaim`; reply View → Bus.
* HUD: Bell Shards pill (visible in Underyard or when > 0), Coffin Key chip in the Underyard, Lucky Dust pill when > 0,
  objective strip line for Chapter II (current seal / tutorial step), CombatHUD (§10.3).

------------------------------------------------------------------------------------------------------------------------
## 20. Work packages and file ownership (one owner per existing file; new files are owned by their creator)

| WP | Scope | Owns (existing files it may edit) |
|---|---|---|
| A | Chapter II core: Chapter2Config, Chapter2Rules, Features/Underyard, Chapter2.luau, Resources kinds, Runtime projection, flags + Shared accessors, HalloweenServer start list, Halloween View embed, Localization/Underyard, Debug, tests | `RS/DogEconomy/Resources.luau`, `SSS/Economy/Runtime.luau` (projection lines only), `RS/Halloween/Shared.luau`, `SSS/Halloween/HalloweenServer.server.luau`, `SSS/Economy/Features/Halloween.luau` (View embed + skins cap), `SSS/Halloween/Debug.luau`, Config.luau flags block only |
| B | Combat: Hazards, BossMath, EventHP, CombatFX, CombatHUD, Strike CanAct hook, tests | `SSS/Halloween/Strike.luau`, `SPS/MiningClient/HalloweenStrike.luau` (downed lockout) |
| C | Boss server rework + BossFinale (server) | `SSS/Halloween/Boss.luau`, Config.luau `C.Boss` block |
| N | Boss/finale client: BossFX changes, FinaleFX, Models/Finale | `HC/BossFX.luau`, `RS/Halloween/Models/Boss.luau` |
| D | Lucky Dust dismantle + forge (feature, DustRules, InventoryScreen UI) | `Modules/InventoryScreen.luau`, `SSS/Economy/EventBlocks.luau` (Dust kind) |
| D2 | Shelter + GUIIntegration + Halloween onboarding fixes, ShelterScreen, E2E test | `ShelterService/Rules`, `CommunityServices`, `CommunityClient`, `GUIIntegration`, `Kit/Nav.luau`, `HC/Onboarding.luau`, HS reward-card DisplayOrder line |
| E | Chapter I rebalance + DropRates + brew catch-up + exorcism activity fix + tests | Config.luau (all non-flag, non-Boss blocks), `Actions.luau`, `Core.luau` (MinuteCap order, EarnCandy), `Exorcism.luau`, `HalloweenHooks.luau`, `Ores.luau`, `DigSpots.luau`, `Houses.luau` |
| F | Reveal notification, guide, church edit + cinematic + teaser, portal transition, navigation | `RS/Navigation/{Destinations,RouteGraph}.luau`, `MapRouting.luau`, `HC/HUD.luau` (prompt localizer scope only) |
| G | Underyard world framework: Layout use, edit script, ground/roads/boundary/sky/Bell Square, Anchors, render tool | new files only |
| H | Underyard districts (Carnival, Marsh, Undercrypt, Crooked Row, Arena) | new files only |
| H2 | Underyard runtime: Underyard.luau (zone server), UnderyardFX, lighting layer, ambience, Chapter II onboarding (server steps in Chapter2 via hooks + Chapter2Guide client) | `HC/Lighting.luau`, `HC/Soundscape.luau`, `RS/Halloween/Music.luau`, `HC/ParticleGovernor.luau` |
| I | Seals framework + seals I-IV (server + client) | new files only |
| J | Seals V-VII + Crooked Doors + Choir + Resonance + Black Bell Assault (server + client) | new files only |
| K | Content: dogs H09-H16 (defs, models, bake edit, abilities hooks), pickaxe skins ×7, plot cosmetics ×10 + idle anim, showcase finds ×15, Coffin.luau + CoffinFX | `DogDefinitions.luau`, `PickaxeSkins.luau` (registration hook only), `DecorCatalog.luau`, `DecorModels.luau`, `ItemDefinitions.luau`, `SecretArrivalConfig.luau`, `PlotCosmetics.client.luau`, `BonusSources/BuriedMoon.luau` |
| L | UI: UnderyardScreen, HS changes, DogdexScreen second page, HUD pills/objective | `HalloweenScreen.luau`, `DogdexScreen.luau`, `DogInfo.luau`, `UITheme.luau`, `HC/HUD.luau` (except F's prompt part) |
| M | Calendar: config, rules, service, stage builders + edit, CalendarFX | `HC/MainMapLayer.luau` (cooperation only) |
| O | Main tutorial rebuild | `OnboardingRules`, `OnboardingService`, `OnboardingGuide`, `Runtime.luau` (tutorial attrs), `EconomyScreens.luau` (HOW TO PLAY), `DOGROTS_AutoTranslateUI` (tutorial strings only) |
| P | Audio + presentation foundation: AudioMixer, SoundGroups edit, Cinema, impact redesign, routing | `MiningAudio.luau`, `RS/Halloween/Audio.luau`, `Kit/Sound.luau`, `WorldAmbience.client.luau`, `SecretArrivals/Kit.luau` (duck → Mixer) |
| HC boot | `HalloweenClient.client.luau` module list | WP-A adds every new client module name (missing modules are skipped) |

Cross-package calls go through the APIs in this document. If a WP must touch a file it does not own, it keeps the
change minimal, marks it with `-- [WP-x]` and reports it.

------------------------------------------------------------------------------------------------------------------------
## 21. Verification (every WP before committing)
1. `$LUNE run tools/place_build.luau place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl src <scratch>/wp.rbxl tools/edits`
2. `$LUNE run tools/verify.luau <scratch>/wp.rbxl src <scratch>/an` and `$LUNE run tools/verify_world.luau <scratch>/wp.rbxl`
3. Unit tests: `$LUNE run tests/<yours>.luau` (+ the baseline suite must not get NEW failures; baseline list:
   `/tmp/claude-0/-home-user-riooblox/da558f97-29b1-5d70-8a0b-9546eb2652ef/scratchpad/test_baseline.txt`).
4. Static analysis: `python3 -I tools/analyze_diff.py $BIN/luau-lsp $BIN/globalTypes.d.luau <base_analyze> <scratch>/an src`
   (base export: `/tmp/claude-0/-home-user-riooblox/da558f97-29b1-5d70-8a0b-9546eb2652ef/scratchpad/base_analyze`); fix
   every new diagnostic in your files.
5. Builders: render previews (`tools/render_preview.py`) and look at them.
Never commit build outputs (`build/*.rbxl`) from a WP; the integrator builds once.

------------------------------------------------------------------------------------------------------------------------
## 22. Addendum — exact cross-package APIs (binding)

### 22.1 Server module access
Every server module is started as `M.Start(core, modules)` (`modules` = table of every started module by name, filled
in boot order). Reach other modules **lazily at call time** (`local C2 = modules.Chapter2; if C2 then ... end`), never at
require time and never by requiring sibling modules that are themselves started modules (avoid double state).
Pure shared modules (Config, Rules, Layout, Hazards, BossMath, DustRules, DropRates, CalendarRules) are required normally.

### 22.2 Chapter2 (WP-A) — additions to §4.2
```lua
C2.HasTeamDog(player, dogId) -> bool          -- dog assigned to a yard dig slot (abilities rule, §9.8)
C2.TeamDogs(player) -> {[dogId]=true}
C2.TutorialEvent(player, key)                 -- "Shards" "Toll" "Coffin" "Practice" "Mourner" "SealOffer" (§9)
C2.TrialCleared(player, trialId, info)        -- generic hook for contracts/stats (Seals framework calls it)
C2.Grant(player, label, rows, opts) -> ok, granted   -- transaction granting reward rows (Kinds of ctx.C2Reward)
C2.Eligible(player), C2.Phase(now), C2.SealOpen(i, now), C2.SealCleared(player, i), C2.SealMask(player)
C2.Progress(player, statKey, n)               -- statKeys: Perfect, Streak, Echo, Ore, Spirit, Trial, Door, Revive,
                                              --   BossDamage, Shards, Coffin, Resonance (contracts + stats; queued 1/s)
C2.StreakHit(player, perfect:boolean)         -- Underyard Strike kinds report every judged hit; pays streak shards
```
### 22.3 Underyard zone server (WP-A, `SSS/Halloween/Underyard.luau`)
```lua
UY.InZone(player) -> bool ; UY.District(player) -> string? ; UY.Unlocked(player, districtName) -> bool
UY.Prompt(anchorName, props, fn(player, prompt)) -> ProximityPrompt?   -- on 40_Underyard.Anchors.<anchorName>
UY.Teleport(player, cf, opts?) -> ok           -- RequestStreamAroundAsync + PivotTo + 0.6 s grace (no fall damage logic)
UY.Descend(player) -> ok, err ; UY.Ascend(player) -> ok, err
UY.OnEnter(fn(player)) ; UY.OnLeave(fn(player)) ; UY.Players() -> {Player}
```
Church prompt "DESCEND" (anchor `38_DeadYard.Anchors.Portal`, created at runtime if the saved anchor is absent) and the
arrival arch prompt "ASCEND" are created here. Signals `C2Zone {Inside, District}`, `C2Portal {Dir, Stage}`.

### 22.4 Seals / trials framework (WP-A, `SSS/Halloween/Seals.luau`; activities by WP-I/J/H2)
```lua
Seals.Register(sealIndex, def)      -- a Bell Seal activity (1..7)
Seals.RegisterTrial(id, def)        -- a non-seal trial (tutorial "Toll", "Mourner", "Assault", door challenges)
-- def = {Id, Name = {en, ru}, District, StartAnchor ("SealAltar_n" default), TimeLimit, MaxParty (6), PartyRadius (30),
--        Combat = bool (EventHP zone id = "Trial:<Id>"), Spawn = Vector3 (edge respawn),
--        OnStart(run), OnTick(run, dt), OnLeave(run, player, reason), OnEnd(run, result), Goal(run) -> number,
--        IsGold(run, player) -> bool, Requests = {[action] = fn(run, player, args) -> ok, res}}
-- run = {Id, TrialId, Seal?, Players = {Player}, Leader, StartedAt, EndsAt, Data = {}, Score = {[userId] = n},
--        Total = 0, Goal = n, State = "Running"|"Won"|"Failed"}
Seals.Start(player, trialIdOrSeal) -> ok, run|err   -- checks date/offering/previous seal/district/run-in-progress
Seals.AddScore(run, player?, n) ; Seals.Win(run, perPlayerInfo?) ; Seals.Fail(run, reason) ; Seals.RunOf(player)
Seals.Leave(player, reason)
```
Requests: `C2TrialStart {Seal | Trial}`, `C2TrialLeave {}`, `C2Trial {Action, ...}` (routed to `def.Requests[Action]`
with the caller's run). Signals: `C2Trial {Kind = "Start"|"Score"|"Tick"|"Won"|"Failed"|"Left", TrialId, Seal, RunId,
EndsAt, Players, Score, Total, Goal, Data}`. Player attribute `UyTrial = "<TrialId>:<RunId>"`. Win → `C2.GrantSeal`
(first clear / repeat / gold) and `C2.TrialCleared`.

### 22.5 Client Chapter II state (WP-A, `HC/Chapter2State.luau`)
```lua
CS.Start(ctx) ; CS.View() -> table ; CS.Request(action, args) -> ok, res
CS.Eligible() ; CS.RevealSeen() ; CS.Seals() -> mask string ; CS.SealCleared(i) ; CS.InZone() ; CS.District()
-- Bus events: "C2Changed" (view), "C2Signal" {Kind, Data} (every C2* signal), "C2Zone" {Inside, District}
```
### 22.6 Builders
`ServerStorage/UnderyardBuild/<Name>.luau` returns `{Order = n, Build = function(ctx)}`; ctx = {Root (40_Underyard),
Anchors, Layout (UnderyardLayout), District, Kit (HalloweenBuild.Kit), YardKit, Note(text), Model(name) -> Model under
Root}. Run by `tools/edits/40_underyard.luau` (sorted by Order then name). Orders: 10 Ground/Boundary/Sky, 20 Roads,
30 BellSquare, 35 Gates, 40 FuneralCarnival, 41 CrookedRow, 50 MourningMarsh, 51 Undercrypt, 60 BlackBellArena, 90 FX
markers. Each district builder returns ONE model named after the district with attribute `UyDistrict`.

### 22.7 Ownership corrections
WP-E also owns `SSS/Economy/EventBlocks.luau` (Dust reward kind for the filler) and `SSS/Halloween/Core.luau`
(MinuteCap order, EarnCandy, `Dust` kind in ctx.Reward); it may make a marked minimal edit in `Shared.BrewSeconds` and in
HS to display `View.Cauldron.TrickPrice`. WP-K2 may edit the `C.Skins` block of Config.luau. WP-P owns `Music.luau`
(new themes); WP-H2 wires them in `Soundscape.luau`. WP-M may edit the `ROOTS` table of `tools/verify_world.luau`.
