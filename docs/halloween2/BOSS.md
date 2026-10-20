# THE GRAVEKEEPER · Chapter II server (WP-C)

What the server does since DOGROTS HALLOWEEN PART II, the protocol the clients read, the balance numbers, and how to test
it in Studio. Binding design: `DESIGN.md` §10.4-§10.5, §11, §23 (this file documents the implementation of it).

Code:

| File | Role |
|---|---|
| `src/ServerScriptService/Halloween/Boss.luau` | the fight: pit fighters, Event HP, attacks as hazards, damage scaling, endgame patterns, wipe, rewards, the finale handoff |
| `src/ServerScriptService/Halloween/BossFinale.luau` | difficulty V: false victory + THE BELL TOLLS / THE BURIED CHOIR / THE LAST BARK |
| `src/ReplicatedStorage/Halloween/BossPatterns.luau` | pure: every hazard pattern (endgame + finale), built fair and checked |
| `src/ReplicatedStorage/Halloween/Chapter2Config.luau` | numbers: `Boss` (scaling, attacks, endgame), `Finale`, `BossRewards`, `Combat` |
| `src/ReplicatedStorage/Localization/Boss.luau` | Russian of the new server replies |
| `tests/boss_finale.luau` | 26 tests incl. the DPS simulation (`lune run tests/boss_finale.luau`) |

Small marked edits in other packages' files (`-- [WP-C]`): `EventHP.luau` (hazard `OnHit` callback), `Chapter2.luau`
(`BossReward` accepts a receipt), `tests/lib/economy_env.luau` (optional `L.Task`).

------------------------------------------------------------------------------------------------------------------------
## 1. The fight (all difficulties)

* **Fighters = alive players inside the pit** (`Layout.InPit`: inside the rim box, below rim level). Only they count for the
  armor scaling (`MaxArmor = BaseArmor × difficulty × (1 + .35 × (fighters − 1))`, armor *fraction* kept when the count
  changes) and only they can hit plates, weak points, mounds, skeletons, rocks and the finale targets ("Climb down into the
  pit to fight the Gravekeeper"). Rim / bell spectators are free to watch: they are never hit, never counted.
* **Event HP** (`EventHP`, WP-B): fighters are in combat zone `"Boss"` (HUD name THE PIT / ЯМА) while they are in the pit;
  leaving the pit leaves the zone (HP is kept 30 s), except while **downed** (crawling out never cancels the downed state).
  The bleed-out spawn is on the north rim, 6 studs behind the top of the north ramp, facing the pit. Downed players are
  never targeted (`EventHP.CanTarget`) and cannot strike.
* **Attacks hurt.** Every telegraphed attack is an EventHP hazard (`HazardWave` in zone "Boss"); the server sends the
  boss animation event with the hazard id, `CombatFX` draws the telegraph, the hazard deals the damage and the knock-back,
  and its `OnHit` adds the Chapter I Curse and sends `BossEvent Knock {Velocity, Curse, Attack, Damage}` to the hit player.
  Skeleton bites are melee (`knock()` deals `BossMath.AttackDamage` through `EventHP.Damage`).

| Attack | Shape | Base dmg (× I .7 / II .9 / III 1.1 / IV 1.3 / V 1.5) | I | II | III | IV | V | Base telegraph |
|---|---|---|---|---|---|---|---|---|
| Stomp | Circle r 9.5 at the boss | 12 | 8 | 11 | 13 | 16 | 18 | 1.2 |
| Slam | Circle r 13, ≤ 16 toward the target | 16 | 11 | 14 | 18 | 21 | 24 | 1.4 |
| Sweep | Cone 120° r 20 | 10 | 7 | 9 | 11 | 13 | 15 | 1.1 |
| Erupt (unfound mound, timeout) | Circle r 10 at the real mound | 14 | 10 | 13 | 15 | 18 | 21 | 1.3 |
| Fake mound (dug) | Circle r 8 at that mound | 8 | 6 | 7 | 9 | 10 | 12 | .9 |
| Rock impact | Circle r 4.5 (3 on the terrace) | 10 | 7 | 9 | 11 | 13 | 15 | the rock's fall (≥ .9) |
| Rock explosion (unbroken 9 s) | Circle r 7 | 14 | 10 | 13 | 15 | 18 | 21 | 1.2 |
| Skeleton bite (melee) | – | 6 | 4 | 5 | 7 | 8 | 9 | – |

Telegraph = base × `TelegraphScale` (1 / 1 / .95 / .9 / .85), never below .9 s (1.2 s at 25+ damage); the impact waits
an extra H10 lead (.35 s) so everyone sees the full telegraph and CANDLELIGHT owners see it earlier. Rock and bone circles
sit on the real surface with a narrow vertical band (`PatternBand` 3.4) so a terrace hit never reaches the floor below.

* **Team wipe** (`EventHP.OnWipe("Boss")`): `BossEvent Wiped {}`, then `finish "Escaped"` / `Escaped {Reason = "Wiped"}`
  (consolation rewards); the downed are bled out to the rim by EventHP, everyone leaves the zone when the fight is released.
* **Rewards**: unchanged Chapter I plan (`Boss.RewardPlan`), plus
  * contributors who **left before the end are parked** in `Boss.Pending[userId][fightId]` and paid on rejoin
    (`PlayerAdded → Boss.ResumePending`), never twice (receipt `hw-boss:<fight>:<userId>`);
  * **Chapter II** (players with `HalloweenChapter1Complete`): after the Chapter I part, `Chapter2.BossReward(player, d,
    {Finale, Receipt = "hw-boss2:<fight>:<userId>"})` for full-reward fighters on III-V (Bell Shards 25 / 40 / 70, the
    first full clear key of III / IV / V, the finale rows); retried with backoff and parked like the rest;
    `BossEvent RewardChapter2 {Difficulty, Finale, FinaleFirst, Rewards}`;
  * every armor credit feeds `C2.Progress(player, "BossDamage", n)` (contract "Deal 2500 damage", stats, resonance);
  * reviving an ally in the pit is contribution (`ReviveScore` .01 × MaxArmor of reward-share score).
* The exorcism D-II fight works as before (summoned without a player, 75 s empty grace until the fight starts).

------------------------------------------------------------------------------------------------------------------------
## 2. Damage scaling (difficulties III-V: `Chapter2Config.Boss.ScaleFrom = 3`)

Per body hit (plates, weak points), in `Boss.luau`:

1. **Armor** = `BossMath.ArmorDamage(raw, …)` = `5 × raw ^ .42` (raw = MiningRules hit damage incl. Strength, PerfectMult,
   combo, crit) × 3 on weak points × (1 + yard-dog bonus ≤ .3) × SYNC (1.5) × H15 (1.25 on weak points) — the bonus
   product capped at 2.25 — × .7 WEAKENED.
2. **SYNC STRIKE**: two players' Perfects on the boss within .5 s → both +50% (the earlier partner gets the bonus
   retroactively: `BossEvent Hit {Sync = true, Retro = true}`).
3. **Soft cap** (`BossMath.CapApply`, per player, rolling 3 s): full value up to `MaxArmorBase(d) × .0045` per second
   (III 56 / IV 90 / V 146 armor/s), 20% beyond. Mechanic damage bypasses 60% of the cap: weak-point hits, the real
   mound (8% MaxArmor), cursed rock shards (3%). The plate shatter bonus (2.5%) is plate damage (capped).
4. **Timing factor** on what lands: a Perfect body hit × `PerfectExtra` **2**, a Good one × `GoodMult` **.75** (the
   plate shatter bonus follows the breaking hit). The cap flattens the gear, the timing survives it.
5. **Difficulty V weak points take Perfect hits only** (`WeakPointPerfectOnly`): a Good hit lands 0 and gets
   `BossEvent Hit {Damage = 0, NeedPerfect = true}`; the weak targets carry `PerfectOnly = true`, StrikeBegin Extra
   `PerfectOnly`, `State.Boss.PerfectOnly`.

Difficulties I / II keep the Chapter I curve (`5 × raw ^ .55`, no cap, no timing factor; SYNC and WEAKENED apply): the
Chapter I gate (beat UNEASY) must not get harder for players who do not hit Perfects.

### 2.1 The design target (§10.4): spam ≤ 35% of the mechanics DPS — measured

`tests/boss_finale.luau` runs real fights: the real Boss + Strike (timing circles, MiningRules damage, crits, combos),
two TV-Head / Strength 1100 bots clicking like a human (≥ `Client.HumanGap` .16 s between clicks; like the client, a
circle that runs out is sent as a Miss, which resets the combo — a TV-Head's 5 circles cannot all be clicked at human
speed):

* **SPAM**: Good hits (the oldest circle past 47% of its window) on the body only (plates, else weak points); no
  mechanic.
* **MECHANICS**: Perfect hits (the oldest circle inside 74-91% of its window): weak points when open, cursed rocks, the
  real mound, the skeletons under the shield, else the most cracked plate.

Both in the **same fight** (same phases and invulnerable windows, own soft caps), 3 seeds each, armor per second:

| Difficulty | Spam | Mechanics | Spam / mechanics | Duo kill |
|---|---|---|---|---|
| III NIGHTMARE | 48 /s | 207 /s | **.23** | 65-68 s |
| IV HELL | 65 /s | 296 /s | **.22** | 74-76 s |
| V ??? | 96 /s | 422 /s | **.23** | 81-87 s (to the false victory) |

Solo (the same bots alone; a solo spammer also smashes the skeleton shield and digs the mounds with Good hits):

| | III | IV | V |
|---|---|---|---|
| Mechanics, TV-Head (Mythic) | killed in 62 s (201 /s) | killed in 72 s (277 /s) | false victory in 83 s (391 /s) |
| Spam, TV-Head | killed in 189 s (66 /s) | killed in 217 s (92 /s) | false victory in 245 s (132 /s) |
| Mechanics, Clown Chronomord (Legendary) | killed in 96-99 s (126-130 /s) | – | 126-138 s |
| Mechanics, Toothy Alarm Clock (Epic) | 107-111 s | – | 167-176 s |
| UNEASY (II), Zombie-Frankenstein | Perfects + mechanics: 70 s · Good hits only: 75 s (Chapter I curve) | | |

Max gear still leads (the 20% beyond the cap and bigger weak-point / mechanic hits), but the timing and the mechanics
decide: a spamming TV-Head is slower than a Perfect-hitting Epic pickaxe. Measured along the way (same duo):
`PerfectExtra` 1 / `GoodMult` 1 → spam/mechanics **.57** (the cap equalises both styles); 2 / 1 → **.32-.34** (too close
to the target); the shipped 2 / .75 → **.22-.23**. The plate shatter bonus counts as plate damage (as a mechanic it gave
the spammer up to a third of their armor). The knobs, in `Chapter2Config.Boss`: `PerfectExtra`, `GoodMult`, `SoftCap
{PerSecond, Beyond, MechanicBypass}`, `ScaleFrom`. Re-run the measurement with overrides:

```
BOSS_TEST="DPS design" BOSS_PERFECT=2 BOSS_GOOD=.75 BOSS_BEYOND=.2 BOSS_SEEDS=3 BOSS_DIFFS=345 lune run tests/boss_finale.luau
BOSS_TEST="kill" lune run tests/boss_finale.luau          # solo kill times + the Chapter I gate
```

------------------------------------------------------------------------------------------------------------------------
## 3. Endgame patterns (III / IV / V; `Chapter2Config.Boss.Endgame`, `BossPatterns`)

The first one 16 s after the rise, then 18-26 s (÷ √difficulty speed) after the previous one ended; never while the boss
is underground, never on top of a rock wave, no melee swing during one (the boss stays hittable). Curse 4 per hit.

| Pattern | Shapes | III | IV | V |
|---|---|---|---|---|
| GRAVE LINES | 3 / 4 / 5 Lines (width 6) across the whole pit in parallel 6-stud slots (axis or diagonal), impacting one after another (.45 s apart: the sweep); the free slots are the safe lanes | 20 dmg | 23 | 27 (1.2 s telegraph) |
| LANTERN WALK | a Safe circle r 9 orbiting the arena at 6 studs/s for 8 s, starting near the fighters; outside it 7 HP/s after the 1.2 s grace | 7 /s | 7 /s | 7 /s |
| BONE RAIN | 12 / 15 / 18 Circles r 4 all over the pit (40% aimed at fighters), impacts .18 s apart | 13 | 16 | 18 |

Cursed rock waves: capped at 3 per phase on III / IV (`State.Boss.RockWaves` = 3), unlimited on V (I / II unchanged).

**Fairness** (every generator, `BossPatterns.Fair`): each def passes `Hazards.Check` (telegraph ≥ .9 s / 1.2 s at 25+,
damage ≤ 45% Event HP, moving shapes ≤ 11 studs/s, rings with a 6-stud gap), and the hazards that land together pass
`Hazards.CheckPattern` on the arena floor (a safe spot always exists). A failing candidate is redrawn (8 tries), then
thinned until it passes. The tests check 150 random seeds per pattern and difficulty, the finale patterns 120 seeds.

------------------------------------------------------------------------------------------------------------------------
## 4. Difficulty V: the false victory and the post-death phases (`BossFinale.luau`)

Only with `Shared.BossFinaleEnabled()` (and not an exorcism fight). Armor 0 in phase 5 → `BossFinale.Begin(F)` instead
of the defeat: the fight table stays alive (Phase 5, `Mode = "Finale"`, armor 0, `PhaseName` = the stage title), every
boss target / hazard / attack / pattern goes, `F.EndsAt` moves past the finale deadline. `finish(F, "Defeated")` runs
exactly once at the end: **Victory** pays the difficulty V reward + the finale rows (`F.FinaleWon`); **Fail** pays the
normal difficulty V full reward without the finale extras.

| Stage | What happens (numbers: `Chapter2Config.Finale`) |
|---|---|
| FakeDeath | 6 s (the client fakes the defeat, then "…not yet") |
| Bell | the Black Bell 28 studs above the floor centre (2.5 s descent), chains N/E/S/W from the ramp tops; one ACTIVE chain at a time: its link hangs 25% of the way to the bell (Strike `FinaleChain`, range 20). Only **Perfect** hits in the **bright 55%** of each **1.2 s pulse** count (ping forgiven up to .25 s, .04 s edge grace; H15 × 1.25); need **6 + 3 × (fighters − 1)** per chain; 1.5 s between chains. Shockwave rings every 6-8 s (one band r 6-34 or an inner + outer band .7 s apart, each with a 50° gap, 21 dmg). |
| Choir | 6 candles on the terrace ring (2 east, 2 west, 1 north, 1 south, off the ramps; `FinaleCandle`, any hit toggles, .45 s per-candle cooldown). Matching the bell's pattern opens 3 buried weak points at 3 of the mound spots for 20 s (`FinaleWeak`, **10 + 5 × (fighters − 1)** tier-normalised hits, any hit, H15 × 1.25); breaking all 3 clears the round, letting them close re-rolls the pattern (same round). 3 rounds. Ghost dogs (`FinaleGhost`, 3 hits) every 14 s: 2 + 1 per extra fighter (≤ 8 alive), chase at 9 studs/s, a telegraphed bite circle r 3.5 (12 dmg) within 6 studs every 2.6 s. Spirit volleys every 5-8 s: 2-3 Lines from one rim side through the fighters (21 dmg). |
| Hound | beat grid from `StartAt` = hound appearance + 3 s, **100 BPM** (.6 s). Patterns in a shuffled cycle, every hazard on a beat with a 2-beat telegraph: Circles (6 bursts of r 5 circles, 18 dmg), Lines (6 beats of 2 parallel lines, 24), Waves (5 expanding rings r 4-34 with a walking 70° gap, 21), SafeDance (a safe circle r 8 hopping every 2 beats at ≤ 9 studs/s, 7 HP/s outside). After each pattern the hound **barks**: a **3 s counter window** on its jaw (`HoundJaw`, 18 studs south of the centre, 10 up) — **Perfect only**, each counts 1 (H15 1.25), **≤ 6 per player per window**; bark points **24 + 10 × (fighters − 1)**. |
| Victory | the bark points run out: `Victory {At, Top}`, `finish(F, "Defeated", "FinaleVictory")`, `C2Announce {Kind = "FinaleClear"}` for every player whose first finale clear it is (+ `Mythic` / `HollowKing` for an H15 / H16 drop) |
| Fail | a team wipe, nobody in the pit for 40 s, or 7 minutes since the false victory: `Fail {Reason = "Wipe" \| "Empty" \| "Time"}`, `finish(F, "Defeated", "FinaleFail")` |

Finale reward-share score (share of MaxArmor, on top of the armor dealt before the false victory): counted chain hit
.004, a candle flipped to the right state .002, a weak point .02 (split by damage), a ghost .006, a counted jaw hit .006.

------------------------------------------------------------------------------------------------------------------------
## 5. Protocol (as implemented; additive fields beyond DESIGN §23 in *italics*)

`RS.Halloween.State.Boss` keeps every attribute (A02 §5.8) plus *`RockWaves`* (cap, 0 = unlimited), *`Pattern`*,
*`PatternUntil`*, *`PerfectOnly`*; `Enraged` is false during the finale; `Mode` gains `"Finale"`.

`BossEvent` (Core Signal, mostly to the Dead Yard zone):

| Kind | Payload |
|---|---|
| Rise | Difficulty, Numeral, Name, Reason, SummonerId, SummonerName, Position, Duration, FightId, *Endgame*, *PerfectOnly*, *Finale* |
| Attack | Attack, Stage "Telegraph" \| "Impact", Position, Radius, Angle?, Direction, Telegraph, ImpactAt, **HazardId**, Hits |
| Pattern | **Name** ("GraveLines" \| "LanternWalk" \| "BoneRain"), **StartAt**, **Duration**, **HazardIds** |
| Rocks | Wave, Waves, *Unlimited*, Rocks {{Key, Position, LandAt, Radius, *HazardId*}}, **HazardIds** |
| RockLand / RockExplode / Erupt | as before + *HazardId* (the hazard deals the damage; Hits is empty) |
| FakeMound | TargetId, Position, UserId, Hits, *HazardId*, *ImpactAt* |
| Knock (to the hit player) | Velocity, Curse, Attack, *Damage* |
| Hit (to the hitter) | Damage (what landed after cap + timing), Weak, Slot, Crit, Quality, Armor, TargetId, DogBonus, *Sync*, *Retro*, *NeedPerfect* |
| WeakPoint | Open, Slots, Until, *PerfectOnly* |
| **Wiped** | Difficulty, Position (then `Escaped {Reason = "Wiped"}`) |
| Defeated | Difficulty, Numeral, Top, Position, Duration, *Finale* ("Victory" \| "Fail": the finale already played the death), *FinaleReason* |
| Reward | as before + *Finale*, *FinaleRun*, *Chapter2* (a `RewardChapter2` follows) |
| *RewardChapter2* | Difficulty, Finale, FinaleFirst, Rewards (`ctx.C2Reward` outs) |
| Finale | Stage + the §23.2 payloads below |

`BossEvent Finale` stages (§23.2): FakeDeath {At, Seconds, *Silence*, *Deadline*} · Bell {StartAt, BellCF, Chains {N, E,
S, W}, Pulse, Bright, Need, *Order*, *Descend*} · ChainActive {Key, Since, Pulse, Bright, Need, Hits, *TargetId*,
*Position*} · ChainHit {Key, Hits, Need, UserId, Counted, *Reason* ("Immune" = not a Perfect, "Toll" = outside the bright
part)} · ChainBreak {Key, Left} · BellToll {At, *HazardIds*, *Rings*} · Choir {StartAt, Candles {{Position, Lit,
*TargetId*}}, Pattern ("010110"), Round, Rounds} · Candle {Index, Lit, UserId, *Candles*, *Match*} · Round {Round, Pattern,
Cleared, *Reset*} · WeakOpen {Points {{Id, Position}}, Until, *Round*} · Ghosts {Count, *Spawns*} · *GhostBite* {Key,
TargetId, UserId, Position, HazardId, ImpactAt} · *GhostDown* {Key, TargetId, UserId, Position} · *Volley* {At, From,
HazardIds} · Hound {StartAt, Bpm, HoundCF, MoonDir, HP, Max, *JawPos*} · HoundPattern {Name, BeatAt, Beats, *HazardIds*,
*BarkAt*} · Bark {At, CounterUntil, JawPos, *TargetId*} · Counter {HP, Max, UserId, Hits, *Counted*, *Reason* ("Closed" |
"Perfect" | "Cap", sent to the hitter only)} · Victory {At, Top {{UserId, Name, Score}}} · Fail {Reason, *At*}.

`RS.Halloween.State.Finale`: State, *Stage* (1 FakeDeath … 6 Fail), StageStart, StageUntil, Chain, ChainsLeft, ChainHits,
ChainNeed, *ChainSince*, *Pulse*, *Bright*, Candles, Pattern, Round, Rounds, *WeakUntil*, HoundHP, HoundMax, CounterUntil,
Bpm, *StartAt*, *BellCF*, *HoundCF*, *JawPos*, *Deadline*, *Reason*, *FightId*, Revision — enough for a late joiner to
rebuild the scene. All finale hazards are EventHP hazards of zone "Boss".

Strike kinds: BossPlate / BossWeak (Damage = the armor before the cap; *EventMult*), BossMound / BossSkeleton /
CursedRock (Power, WEAKENED applied), FinaleChain (attr Key, Since, Pulse, Bright, Need, Hits), FinaleCandle (Index, Lit),
FinaleWeak, FinaleGhost (Key), HoundJaw (Until).

`Signal "C2Announce" {Kind = "FinaleClear" | "Mythic" | "HollowKing", Name, UserId, DogId?}` to all players (§24.4).

------------------------------------------------------------------------------------------------------------------------
## 6. Testing in Studio

Debug requests (Studio places only):

```lua
local R = game.ReplicatedStorage.Halloween.Remotes.Request
R:InvokeServer("Debug", {Cmd = "Boss", Difficulty = 4})        -- summon any difficulty at once (no cooldown)
R:InvokeServer("C2Debug", {Cmd = "Finale"})                     -- difficulty V straight to the false victory
R:InvokeServer("C2Debug", {Cmd = "Finale", Stage = "Choir"})    -- jump the running finale: Bell | Choir | Hound | Win | Fail
R:InvokeServer("C2CombatDebug", {Cmd = "Down"})                 -- downed (wipe test with one player)
R:InvokeServer("C2Debug", {Cmd = "Complete1"})                  -- Chapter I latch: Chapter II boss rewards
```

Checklist:

1. Summon III with two players, one on the north rim: the rim player has no HP bar, cannot hit a plate ("Climb down into
   the pit…"), is never hit; the armor is the solo armor until they jump in.
2. Attacks draw as EventHP telegraphs (no double BossFX telegraph), hurt (Event HP numbers), knock back and add Curse.
3. Within ~20 s of the rise an endgame pattern starts (banner + telegraphs), every pattern leaves a lane / gap / circle.
4. Phase 4 on IV: exactly 3 rock waves; on V they keep coming. Weak points on V: Good hits show 0 / "PERFECT ONLY".
5. Get downed alone → Wiped banner, Escaped, consolation reward; bleed-out spawn on the north rim.
6. Leave the server mid-fight after dealing damage, rejoin after the fight: the reward arrives.
7. `C2Debug Finale` → the false victory, then each stage; break a chain with Perfects in the bright pulse (Good hits
   say IMMUNE, late Perfects MISSED THE TOLL); match the candles; break the 3 weak points; counter the barks; Victory pays
   once (one Defeated, one Reward, one RewardChapter2) and `State.Finale` resets 12 s later.
8. `C2Debug Finale` + `C2CombatDebug Down` → Fail {Wipe}; the normal V reward arrives.
9. Turn `Config.HalloweenBossFinaleEnabled` off: difficulty V ends with the normal death.

Automated: `lune run tests/boss_finale.luau` (about 8 minutes, most of it the DPS simulation; `BOSS_TEST=finale` runs
only the finale tests).
