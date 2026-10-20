# CHAPTER I · THE DEAD YARD — rebalance + rare prize philosophy (WP-E)

Contract: `docs/halloween2/DESIGN.md` §12. Every number lives in `src/ReplicatedStorage/Halloween/Config.luau`; each
changed value keeps its old value in a `-- was` comment and the new levers are in `C.Rebalance`. The tables, odds and
hourly rates below are produced by `tools/chapter1_balance.py` from that Config (re-run it after any change:
`python3 -I tools/chapter1_balance.py [--hours 2] [--players 6]`). `tests/chapter1_rebalance.luau` asserts the same
contracts against the real Luau modules.

## 1. Targets

* Pumpkin Lucky Block acquisition **≈ 5× slower** (target 4–6×) for an active grinder; the daily all-quests Pumpkin
  block is untouched (a fair daily floor).
* Passive Halloween generation (event mutations on ordinary yard digs) at **20 %** of before.
* Chase prizes (event dogs, skins, the big mutations) become genuinely rare (§3); a block that misses them still feeds
  the Dust Forge with Lucky Dust.
* Nothing already granted is taken away. Blocks already owned keep the reward table that was frozen into them when they
  were granted (`EventBlocks.Freeze`): no migration of stored blocks. `Config.Season` (the wipe key) is unchanged.

## 2. Every lever, old → new

| Lever | Was | Now | Where |
|---|---|---|---|
| Cauldron TRICK price | 80 flat | 140 base, ×1.2 per TRICK in the same UTC day, rounded to 5, capped at 240 (3× the old price): **140, 170, 200, 240, 240…**; back to 140 at UTC midnight | `Cauldron.TrickCost`, `Rebalance.TrickEscalation`; `Chapter1Rules.TrickPrice`; `Actions` CauldronTrick (`h.Cauldron.TricksToday = {Day, N}`); view `Cauldron.TrickPrice/TricksToday/TrickBase/TrickMax` |
| Perfect Hit candy cap / min | 40 | 20 | `Candy.PerfectHitCap` |
| Candy MinuteCap | 220, after the multipliers | 110, on the **base** amount **before** the multipliers (a Candy Rush / Blood Moon keeps its full value near the cap) | `Candy.MinuteCap`; `Core` ctx.Candy → `Chapter1Rules.MinuteCap` |
| Ore candy | 1–3 | 1–2 | `Ore.Candy`, `Candy.Loot` |
| Dig spot candy | Cursed 2–4, Ghost 2–4, Pumpkin 6–10, Bone 1–3, Treasure 14–24 | ×0.6 rounded, min 1: 1–2, 1–2, 4–6, 1–2, 8–14 | `DigSpots.Types[].Candy` |
| Door candy TREAT / TRICK | 6–14 / 2–5 | 4–9 / 1–3 | `Candy.TreatHouse/TrickHouse` |
| Daily quest candy | 25–50 | ×0.6: 15–30 (DigSpots 27, Perfect 18, EarnCandy 15, BloodMoon 24, BossDamage 30, OpenPumpkin 21, FindMutation 30, MineOre 18, Knock 15) | `Quests.Pool[].Candy` |
| EarnCandy quest | counted every candy, incl. its own quest-claim candy | counts **earned** candy only: quest claims, reward rows, conversions, debug (any NoMult payout, `Candy.Unearned`) never count | `Core` ctx.Candy → `Chapter1Rules.Earned` |
| All-quests bonus | 1 Pumpkin + 30 candy | 1 Pumpkin + 15 candy (the block is unchanged) | `Quests.AllBonus` |
| Blood Moon candy bonus | +50 % | +25 % | `BloodMoon.CandyBonus` |
| Boss candy | I 20–35 … V 80–100 | ×0.6: 12–21, 18–30, 27–42, 36–51, 48–60 | `Boss.Difficulties[].Candy` |
| Boss event-dog drop | DogChance .02/.04/.07/.12/.2, weights Legendary 3 : Mythic 1 | each Legendary dog's absolute chance ×0.05, each Mythic ×0.025: DogChance ×0.04375 (.000875/.00175/.0030625/.00525/.00875) with weights 6 : 1 | `Boss.Difficulties[].DogChance`, `Boss.DogWeights` (marked `[WP-E]`) |
| Boss Cursed Pumpkin | IV .35, V 1 | IV .03, V .08 | `Boss.Difficulties[].CursedBlock` |
| Boss ECLIPSED find | V .03 | V .0003 (Secret ×0.01) | `Boss.Difficulties[5].EclipseChance` |
| Exorcism 2500-soul RARE pumpkin | every player on the server (AFK included) | only players **active in the Dead Yard in the last 180 s** (others get a toast telling them why) | `Exorcism.Milestones[2].ActiveWindow`; `Core.ActiveInYard`; `Exorcism.Recipients` |
| Passive yard event mutations | YardChance .004 / .0015 / .0012 | ×0.2 (.0008 / .0003 / .00024) | `Rebalance.PassiveScale`; `HalloweenHooks.Rows` |
| Pumpkin / Cursed Pumpkin tables | §3 "was" columns | rescaled by `DropRates.Rescale` (§3) at load, Lucky Dust filler | `Config.Rewards` (originals kept in the file), `Rebalance.RarityScale/Filler`, `Rebalance.Was/Odds` |
| Cauldron brew time | StartedAt + 7 days flat (a brew started after Oct 24 could never be claimed) | ready at `min(StartedAt + 7 d, 2026-10-31 18:00 UTC)` for every brew started before the deadline (none is stranded); a brew started after it takes 1 day; Studio fast timers unchanged | `Rebalance.BrewDeadline`; `Chapter1Rules.BrewReadyAt`; `Shared.BrewSeconds(startedAt)` (marked `[WP-E]`); `Actions` CauldronClaim; view `Cauldron.ReadyAt` |

Brew catch-up examples (UTC): started Oct 20 09:00 → ready Oct 27 09:00 (7 days, as before) · Oct 24 18:00 → Oct 31
18:00 · Oct 27 → Oct 31 18:00 · Oct 30 23:00 → Oct 31 23:00 (the 1-day minimum) · Nov 2 → Nov 3. A brew started
before the rebalance shipped keeps its StartedAt; only its ready time can move earlier, never later.

Unchanged on purpose: TREAT brew tables and level costs, event DogDex rewards, rare-find candy, Candy Rush, curse, the
TRICK Cursed chance (6 %), event dog abilities (already owned rewards keep their full value).

## 3. Rare prize philosophy (`ReplicatedStorage.Halloween.DropRates`)

`DropRates.Rescale(rows, factors, filler)` keeps every row and changes only its **probability**: each row's chance is
multiplied by the factor of its class and the probability this frees goes to the filler row(s).

| Class (`DropRates.Classify`) | Rows | Factor (`Rebalance.RarityScale`) |
|---|---|---|
| Resource | Kind Cash / Bones / Candy (and Dust) | ×0.5 |
| Common / Rare / Epic | items, decor, mutations, dogs of that rarity | ×0.10 |
| Legendary | | ×0.05 |
| Mythic | | ×0.025 |
| Secret | | ×0.01 |

Filler: **Lucky Dust** — Pumpkin 40–70, Cursed Pumpkin 150–260 (`Rebalance.Filler`), paid to `p.Resources.LuckyDust`
(the Dust Forge currency, DESIGN §14) by `EventBlocks.Apply` / `Core` ctx.Reward. Weights come back as integers on a
1 000 000 scale: every rescaled row's chance equals old × factor within 1e-6 (a row that would round to 0 keeps weight
1, so no prize becomes impossible) and each table sums to exactly 1 000 000. `Config` applies it at load from the
ORIGINAL weights kept in the file (`C.Rebalance.Was`); `C.Rebalance.Odds` holds the reports (`DropRates.Report` gives
the plain odds of any table for UI odds lists). A failure keeps the original tables and warns (Config never throws).
New blocks are stamped `OddsVersion = "hw1-r1"`.

The exorcism RARE pumpkin (`ctx.Block` MinRank 3) keeps only the Epic+ rows of the (rescaled) table, so it never
contains Lucky Dust; inside it the chances shift with the class factors (table below).

## 4. Numbers (generated by `tools/chapter1_balance.py`)

<!-- generated by tools/chapter1_balance.py --hours 2 --players 6 -->

### Pumpkin / Cursed Pumpkin (rare prize philosophy)

#### PUMPKIN LUCKY BLOCK (filler: Lucky Dust 40-70)

| Row | Kind | Rarity | Class | x | Weight was | Chance was | 1 in (was) | Weight now (1e6) | Chance now | 1 in (now) |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| Coin Pile | Cash | Common | Resource | 0.5 | 2,600 | 25.7044% | 3.9 | 128,522 | 12.8522% | 7.8 |
| 60 Bones | Bones | Common | Resource | 0.5 | 2,200 | 21.7499% | 4.6 | 108,749 | 10.8749% | 9.2 |
| JACK-O'-LANTERN | Decor | Rare | Rare | 0.1 | 1,100 | 10.8749% | 9.2 | 10,875 | 1.0875% | 92 |
| GRAVE STONE | Decor | Rare | Rare | 0.1 | 1,000 | 9.8863% | 10 | 9,886 | 0.9886% | 101 |
| CANDLE CLUSTER | Decor | Epic | Epic | 0.1 | 800 | 7.9090% | 13 | 7,909 | 0.7909% | 126 |
| HAUNTED FIND | Mutation | Epic | Epic | 0.1 | 900 | 8.8977% | 11 | 8,898 | 0.8898% | 112 |
| PUMPKINIZED FIND | Mutation | Legendary | Legendary | 0.05 | 450 | 4.4488% | 22 | 2,224 | 0.2224% | 450 |
| PUMPKIN SMASHER SKIN | Skin | Legendary | Legendary | 0.05 | 160 | 1.5818% | 63 | 791 | 0.079100% | 1,264 |
| BONE PICKAXE SKIN | Skin | Legendary | Legendary | 0.05 | 160 | 1.5818% | 63 | 791 | 0.079100% | 1,264 |
| Pumpkin Pup | Dog | Rare | Rare | 0.1 | 380 | 3.7568% | 27 | 3,757 | 0.3757% | 266 |
| Sheet Shiba | Dog | Epic | Epic | 0.1 | 140 | 1.3841% | 72 | 1,384 | 0.1384% | 723 |
| Bone Corgi | Dog | Epic | Epic | 0.1 | 140 | 1.3841% | 72 | 1,384 | 0.1384% | 723 |
| Frankenpug | Dog | Legendary | Legendary | 0.05 | 34 | 0.3361% | 298 | 168 | 0.016800% | 5,952 |
| Bat Dachshund | Dog | Legendary | Legendary | 0.05 | 34 | 0.3361% | 298 | 168 | 0.016800% | 5,952 |
| Plague Pug | Dog | Mythic | Mythic | 0.025 | 8 | 0.079090% | 1,264 | 20 | 0.002000% | 50,000 |
| Headless Hound | Dog | Mythic | Mythic | 0.025 | 8 | 0.079090% | 1,264 | 20 | 0.002000% | 50,000 |
| Eclipse Dog | Dog | Secret | Secret | 0.01 | 1 | 0.009886% | 10,115 | 1 | 0.000100% | 1,000,000 |
| LUCKY DUST | Dust | Common | filler | - | - | - | - | 714,453 | 71.4453% | 1.4 |

#### CURSED PUMPKIN (filler: Lucky Dust 150-260)

| Row | Kind | Rarity | Class | x | Weight was | Chance was | 1 in (was) | Weight now (1e6) | Chance now | 1 in (now) |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| Cursed Hoard | Cash | Rare | Resource | 0.5 | 1,800 | 19.4133% | 5.2 | 97,066 | 9.7066% | 10 |
| 220 Bones | Bones | Rare | Resource | 0.5 | 1,500 | 16.1777% | 6.2 | 80,889 | 8.0889% | 12 |
| BONE ARCH | Decor | Epic | Epic | 0.1 | 900 | 9.7066% | 10 | 9,707 | 0.9707% | 103 |
| BLOOD MOON FIND | Mutation | Legendary | Legendary | 0.05 | 900 | 9.7066% | 10 | 4,853 | 0.4853% | 206 |
| ECLIPSED FIND | Mutation | Secret | Secret | 0.01 | 120 | 1.2942% | 77 | 129 | 0.012900% | 7,752 |
| GHOST SCYTHE SKIN | Skin | Mythic | Mythic | 0.025 | 420 | 4.5298% | 22 | 1,132 | 0.1132% | 883 |
| LIVING COFFIN SKIN | Skin | Mythic | Mythic | 0.025 | 420 | 4.5298% | 22 | 1,132 | 0.1132% | 883 |
| Sheet Shiba | Dog | Epic | Epic | 0.1 | 900 | 9.7066% | 10 | 9,707 | 0.9707% | 103 |
| Bone Corgi | Dog | Epic | Epic | 0.1 | 900 | 9.7066% | 10 | 9,707 | 0.9707% | 103 |
| Frankenpug | Dog | Legendary | Legendary | 0.05 | 520 | 5.6083% | 18 | 2,804 | 0.2804% | 357 |
| Bat Dachshund | Dog | Legendary | Legendary | 0.05 | 520 | 5.6083% | 18 | 2,804 | 0.2804% | 357 |
| Plague Pug | Dog | Mythic | Mythic | 0.025 | 180 | 1.9413% | 52 | 485 | 0.048500% | 2,062 |
| Headless Hound | Dog | Mythic | Mythic | 0.025 | 180 | 1.9413% | 52 | 485 | 0.048500% | 2,062 |
| Eclipse Dog | Dog | Secret | Secret | 0.01 | 12 | 0.1294% | 773 | 13 | 0.001300% | 76,923 |
| LUCKY DUST | Dust | Rare | filler | - | - | - | - | 779,087 | 77.9087% | 1.3 |

By kind (chance per open, was -> now):

| Kind | Pumpkin was | Pumpkin now | Cursed was | Cursed now |
|---|---:|---:|---:|---:|
| Cash | 25.7044% | 12.8522% | 19.4133% | 9.7066% |
| Bones | 21.7499% | 10.8749% | 16.1777% | 8.0889% |
| Decor | 28.6703% | 2.8670% | 9.7066% | 0.9707% |
| Mutation | 13.3465% | 1.1122% | 11.0009% | 0.4982% |
| Skin | 3.1636% | 0.1582% | 9.0595% | 0.2264% |
| Dog | 7.3653% | 0.6902% | 34.6419% | 2.6005% |
| Dust | 0% | 71.4453% | 0% | 77.9087% |

#### Exorcism RARE PUMPKIN (MinRank 3: only Epic+ rows, renormalised; the Dust filler is Rank 1 and never in it)

| Row | Chance was | Chance now |
|---|---:|---:|
| CANDLE CLUSTER | 28.2187% | 33.2898% |
| HAUNTED FIND | 31.7460% | 37.4526% |
| PUMPKINIZED FIND | 15.8730% | 9.3611% |
| PUMPKIN SMASHER SKIN | 5.6437% | 3.3294% |
| BONE PICKAXE SKIN | 5.6437% | 3.3294% |
| Sheet Shiba | 4.9383% | 5.8254% |
| Bone Corgi | 4.9383% | 5.8254% |
| Frankenpug | 1.1993% | 0.7071% |
| Bat Dachshund | 1.1993% | 0.7071% |
| Plague Pug | 0.2822% | 0.084182% |
| Headless Hound | 0.2822% | 0.084182% |
| Eclipse Dog | 0.035273% | 0.004209% |

### The Gravekeeper (full reward)

| Difficulty | Candy was | Candy now | Dog chance was | Dog chance now | per Legendary dog was -> now | per Mythic dog was -> now | Cursed block was -> now | ECLIPSED find was -> now |
|---|---|---|---:|---:|---|---|---|---|
| I EASY | 20-35 | 12-21 | 2.0000% | 0.087500% | 0.7500% -> 0.037500% | 0.2500% -> 0.006250% | 0% -> 0% | 0% -> 0% |
| II UNEASY | 30-50 | 18-30 | 4.0000% | 0.1750% | 1.5000% -> 0.075000% | 0.5000% -> 0.012500% | 0% -> 0% | 0% -> 0% |
| III NIGHTMARE | 45-70 | 27-42 | 7.0000% | 0.3063% | 2.6250% -> 0.1313% | 0.8750% -> 0.021875% | 0% -> 0% | 0% -> 0% |
| IV HELL | 60-85 | 36-51 | 12.0000% | 0.5250% | 4.5000% -> 0.2250% | 1.5000% -> 0.037500% | 35.0000% -> 3.0000% | 0% -> 0% |
| V ??? | 80-100 | 48-60 | 20.0000% | 0.8750% | 7.5000% -> 0.3750% | 2.5000% -> 0.062500% | 100.0000% -> 8.0000% | 3.0000% -> 0.030000% |

### TRICK price ladder (per UTC day)

| Trick of the day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| was | 80 | 80 | 80 | 80 | 80 | 80 | 80 | 80 |
| now | 140 | 170 | 200 | 240 | 240 | 240 | 240 | 240 |
| now / was | 1.75x | 2.12x | 2.50x | 3.00x | 3.00x | 3.00x | 3.00x | 3.00x |

### Candy and Pumpkin blocks per hour (model, 2 h of play per UTC day, 6 active players in the yard)

| | before | after | after / before |
|---|---:|---:|---:|
| base candy / minute, mining ore (pre-multiplier) | 54.0 | 31.0 | 0.57 |
| base candy / minute, Blood Moon spots (pre-multiplier) | 56.0 | 30.4 | 0.54 |
| candy / hour from play (incl. rush, Blood Moon, cap) | 3829 | 2088 | 0.55 |
| daily quests + all-quests bonus candy / day | 203 | 119 | 0.59 |
| door candy / day (7 knocks) | 56 | 36 | 0.65 |
| boss candy / day (1 kill, difficulty II) | 50 | 30 | 0.60 |
| **candy / hour (all sources)** | 3983 | 2180 | 0.55 |
| TRICK blocks / hour | 49.79 | 9.52 | 0.19 |
| daily all-quests block / hour | 0.50 | 0.50 | 1.00 |
| exorcism RARE pumpkins / hour | 4.06 | 2.98 | 0.74 |
| **Pumpkin-family blocks / hour** | 54.35 | 13.01 | 0.24 |

Blocks per hour of grinding: **4.2x fewer** (target 4-6x). Without the exorcism share (a solo server): 5.0x.

Sensitivity (hours of play per UTC day):

| hours / day | candy/h before | candy/h after | blocks/h before | blocks/h after | fewer |
|---|---:|---:|---:|---:|---:|
| 0.5 | 5329 | 2940 | 73.39 | 19.56 | 3.8x |
| 1 | 4432 | 2434 | 60.71 | 15.20 | 4.0x |
| 2 | 3983 | 2180 | 54.35 | 13.01 | 4.2x |
| 3 | 3833 | 2096 | 52.22 | 12.27 | 4.3x |
| 5 | 3714 | 2028 | 50.52 | 11.69 | 4.3x |

### Passive yard event mutations (per item attempt of an ordinary yard dig)

| Mutation | was | now |
|---|---:|---:|
| HAUNTED | 0.4000% | 0.080000% |
| PUMPKINIZED | 0.1500% | 0.030000% |
| BLOOD MOON (Blood Moon only) | 0.1200% | 0.024000% |

### Chase items: expected opens and hours of play (model above)

| Prize | Pumpkin opens was | Pumpkin opens now | Cursed opens was | Cursed opens now | hours of play was | hours of play now |
|---|---:|---:|---:|---:|---:|---:|
| JACK-O'-LANTERN (Decor) | 9.2 | 92 | - | - | 0.2 | 9.7 |
| GRAVE STONE (Decor) | 10 | 101 | - | - | 0.2 | 10.7 |
| CANDLE CLUSTER (Decor) | 13 | 126 | - | - | 0.2 | 0.9 |
| HAUNTED FIND (Mutation) | 11 | 112 | - | - | 0.2 | 0.8 |
| PUMPKINIZED FIND (Mutation) | 22 | 450 | - | - | 0.4 | 3.3 |
| PUMPKIN SMASHER SKIN (Skin) | 63 | 1,264 | - | - | 1.0 | 9.4 |
| BONE PICKAXE SKIN (Skin) | 63 | 1,264 | - | - | 1.0 | 9.4 |
| Pumpkin Pup (Dog) | 27 | 266 | - | - | 0.6 | 28.2 |
| Sheet Shiba (Dog) | 72 | 723 | 10 | 103 | 0.9 | 5.2 |
| Bone Corgi (Dog) | 72 | 723 | 10 | 103 | 0.9 | 5.2 |
| Frankenpug (Dog) | 298 | 5,952 | 18 | 357 | 2.6 | 40.5 |
| Bat Dachshund (Dog) | 298 | 5,952 | 18 | 357 | 2.6 | 40.5 |
| Plague Pug (Dog) | 1,264 | 50,000 | 52 | 2,062 | 9.1 | 329 |
| Headless Hound (Dog) | 1,264 | 50,000 | 52 | 2,062 | 9.1 | 329 |
| Eclipse Dog (Dog) | 10,115 | 1,000,000 | 773 | 76,923 | 100 | 7,018 |
| BONE ARCH (Decor) | - | - | 10 | 103 | 3.4 | 180 |
| BLOOD MOON FIND (Mutation) | - | - | 10 | 206 | 3.4 | 361 |
| ECLIPSED FIND (Mutation) | - | - | 77 | 7,752 | 25.9 | 13,568 |
| GHOST SCYTHE SKIN (Skin) | - | - | 22 | 883 | 7.4 | 1,546 |
| LIVING COFFIN SKIN (Skin) | - | - | 22 | 883 | 7.4 | 1,546 |

("opens" = expected blocks of that tier opened for one copy; "hours" = expected hours of play at the model's block, boss and exorcism rates, all sources combined)


## 5. Model assumptions (`ASSUME` in `tools/chapter1_balance.py`)

One engaged player, solo numbers, curse kept below 60 % (multiplier 1):

* 45 Perfect hits per minute attempted (capped by `PerfectHitCap`), 6 ore breaks per minute between Blood Moons
  (A01 §5), rare-find chance 6 % per break / per spot type, rare-find candy 3–8.
* Blood Moon ACTIVE 150 s of every 915 s cycle; during it 3 haunted dig spots per minute (type weights from Config).
* Personal Candy Rush ×2 for 600 s of the day's play; Blood Moon bonus in the zone; the cap applied as the version says
  (old: after multipliers at 220; new: before multipliers at 110).
* Per UTC day: 5 daily quests (Perfect + EarnCandy + 3 average others) and the all-quests bonus, 7 door knocks
  (TreatChance 62 %, porch skeleton bounty on 12 % of tricks), one solo Gravekeeper II kill (perf 1).
* Every candy goes into TRICKs at that day's price ladder (old: 80 flat). The daily all-quests block counts once per day.
* Exorcism: 6 players active in the Dead Yard each feeding souls (1 per candy, 3 per ore, 6 per spot, 20 per quest),
  5000 souls per cycle + a 5-minute summoned Gravekeeper fight; the active player gets every RARE pumpkin (before: so
  did everyone on the server, AFK included).
* Chase-item hours combine TRICK Pumpkins (94 %) + the daily block, TRICK Cursed Pumpkins (6 %), exorcism RARE pumpkins
  and the boss dog drop; one-off sources (TREAT brew, event dex) are left out.

Result: candy per hour ≈ 0.55× (≈ 4 000 → ≈ 2 200 with rush and Blood Moon included), Pumpkin-family blocks per hour
≈ 4.2× fewer (5.0× on a server without other exorcists), within the 4–6× target at every session length.

## 6. Implementation map

| File | What |
|---|---|
| `src/ReplicatedStorage/Halloween/DropRates.luau` (new, pure) | `Scale`, `Classify(row)`, `Factor(row, factors)`, `Rescale(rows, factors, filler) -> rows, report`, `Report(rows)`, `ScaleChance(chance, rows, factors) -> chance, weights`, `Expected(chance)` |
| `src/ReplicatedStorage/Halloween/Chapter1Rules.luau` (new, pure) | `Day`, `TricksToday(c, now)`, `TrickPrice(c, now, cfg)`, `PriceAt(n, cfg)`, `TrickPrices(cfg, count)`, `NoteTrick(c, now)`, `BrewReadyAt(startedAt, cfg)`, `BrewSeconds(startedAt?, cfg)`, `MinuteCap(used, n, cap)`, `Earned(source, opts?, cfg)`, `RecentlyActive(lastAt, now, window)`, `DecorateView(view, h, now, cfg, brewSeconds?)` |
| `Config.luau` | every lever above, `C.Rebalance`, the load-time rescale (bottom of the file) |
| `SSS/Halloween/Core.luau` | MinuteCap before multipliers, EarnCandy only from earned candy, `ctx.Dust(n | {min,max})`, `Dust` kind in `ctx.Reward`, `Core.View(p, now)` (the client view + TRICK price + catch-up ReadyAt), `Core.ActiveInYard(player, window)`, `Core.MakeCtx` (tests) |
| `SSS/Halloween/Actions.luau` | CauldronTrick `{MaxPrice?}` escalating price (refused when dearer than the price on the player's button), reply `{Price, TricksToday, NextPrice}`; CauldronClaim with the catch-up time |
| `SSS/Halloween/Exorcism.luau` | `Ex.Recipients(players, milestone, core) -> exorcists, others`; the 2500-soul block to exorcists only |
| `SSS/Economy/HalloweenHooks.luau` | YardChance × `PassiveScale` |
| `SSS/Economy/EventBlocks.luau` | `Dust` row kind (Rows / Apply → `Resources.Add(p, "LuckyDust", n)`, the art falls back to the name), `OddsVersion`, the decorated view after an open |
| `RS/Halloween/Shared.luau` (marked) | `Shared.BrewSeconds(startedAt?)` |
| `HalloweenScreen.luau` (marked) | cauldron page: the TRICK price of the moment (button, body, hint), "the price rises with every trick today" hint (RU/EN), `MaxPrice` on TRICK, the TREAT text mentions the Oct 31 catch-up |
| `RS/Localization/Chapter1Balance.luau` (new) | RU of the new server texts (price changed, exorcism notice, Lucky Dust names) |
| `RS/Localization/Halloween.luau` (marked) | UI entry for the renamed milestone "RARE PUMPKIN BLOCK FOR THE EXORCISTS" |
| `tests/chapter1_rebalance.luau` (new) | the contracts of this document against the real modules |
| `tools/chapter1_balance.py` (new) | this document's numbers |
