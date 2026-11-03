# Balance QA (Concern 3: gameplay is balanced)

Tool: `python3 tools/balance_sim.py [--runs N] [--hours H] [--quick]`. It parses the real
`src/shared/Config/*.luau` and `data/zones/*.csv` on every run, mirrors `Util/Odds`, `Util/Meter`,
`RollService`, `TrainingService`, `ShopService`, `DogService` and `EventService` maths, and simulates a
typical F2P player. The full output is reproduced below the change log.

## Roster gate
- `python3 tools/roster.py check`: PASS (720 dogs, 0 errors, 0 too-similar looks, 0 too-similar names).
- `python3 tools/roster.py build`: rebuilt `src/shared/Data/Dogs.luau` and `data/Roster.xlsx`. No cross-zone collisions were left to fix.
- Forms: 1,425, not the 1,422 in the brief. Mythic Meadow has 27 non-Commons (13+7+3+2+2), so 720 + 235 x 3 = 1,425. The brief's figure was an arithmetic slip.

## Before the pass: the game was broken
The first simulation, run with the configs as written, showed the whole game cleared in about 15 minutes. By then ThrowPower was 2,000 with a Golden ball and income was $900K/s.
The cause was structural. Distance is linear in ThrowPower and zone distances grow linearly, while free
pull-ups gave linear ThrowPower growth and the x1.5-per-level training mult made it super-linear. So the
"grind stat" alone crossed the field. Prices could not fix this, because income (x4 per zone) also grew faster than any price curve.

## Changes made
| File | Change | Why |
|---|---|---|
| Config/Training.luau | NEW `Upgrades.Caps` table + `Training.PowerCap(level)`: reps cannot raise ThrowPower above the cap for the current upgrade level (100 at L0 ... 2,000 at L29). `MaxLevel` 40 -> 29 (= #Caps-1) | Each training upgrade now gates the next zone (cash = dogs gates progress). Reps are the short fill (about 20-70 s of pull-ups per level). |
| Config/Training.luau | `MultBase` 1.5 -> 1.03, `CostGrowth` 3.2 -> 2.6 (BaseCost stays $50 = starter cash) | Fills stay a short grind. The cost curve matches the income curve. |
| Config/Training.luau | PullUp Gain 1 -> 0.5; Machine Gain 4 -> 3 and CashPerRepPerPower 0.25 -> 0.1; Sprint 12 (kept) | Pull-up 0.8 TP/s, Sprint ~0.87 TP/s (free, needs laps), Machine 3 TP/s (paid speed-up). |
| server/Services/TrainingService.luau | Gain clamps to `PowerCap(level)`; the message "Power cap N reached: buy a Training upgrade" | Enforces the cap. |
| Util/PlayerStats.luau | `Computed.PowerCap`; posted luck/catch include a banked **premium throw** (Golden-ball luck, +10% catch unless Sticky Ball) | The odds panel and catch chips did not match what ThrowService rolls when a premium throw is spent automatically. |
| client ThrowController / ShopController | HUD "Power X/cap"; Training tab shows cap now -> next | Makes the cap visible. |
| Config/Balls.luau | Flying Disc 25K -> 50K, Glow 2.5M -> 5M, Golden 250M -> 3B (range/luck unchanged) | Balls land at ~3 m / 14 m / 1 h / 3 h. |
| Config/Shop.luau | Slot `CostGrowth` 2.5 -> 4.5 | Slots grew to 100 within 30 min. Now ~45 by 1 h and ~95 by 30 h. |
| Config/Shop.luau | Whistle IncomeSeconds 600 -> 300, Treat Pocket 300 -> 120, `DefaultTreatPocketMode` "Always" -> "EpicPlus" | "Always" wasted pockets on Commons. Both consumables are now worth carrying. |
| Config/Shop.luau | Cosmetics x2.5 Bones (total 715 -> 1,750); Book 25% cash kept at 6000 x zone BaseIncome (tested 36000: it skipped Beach/Farm early) | All cosmetics were affordable in ~10 h. Now ~22-25 h. |
| Config/Timers.luau | `OfflineRate` 1.0 -> 0.5 (cap stays 2 h) | At 100% rate, offline pay was 63% of all income for a 1 h/day player. |
| docs/DESIGN.md | §11 ball prices, §12 training (cap, gains), §14.4 offline rate | Kept in sync. **Rarities odds unchanged**, so the §6 odds tables are still correct. |

## Posted odds vs RollService (verified by reading)
- The tier odds panel uses `Odds.TierOdds(luck)`, the same function `RollService.RollTier` uses. Every zone contains all six tiers, so renormalisation never differs.
- The luck sources are the same in both: ball, boosts, book, Lucky Paw, server luck, and now the premium throw. The luck cap (Common >= 40%) is shared.
- Catch chips and the panel use `Odds.CatchChance` plus the Lucky Streak override. This matches `RollCatch`.
- Variant odds use `Odds.VariantChances`, which rolls Rainbow, then Shadow, then Gold. This matches `RollVariant`.
- Not shown: the Treat Pocket second roll (an effective c + (1-c)c). TODO: add a line to the odds panel.

## Findings (from the run below)
- **Pacing:** within about 20% of every target. Park 4m, Beach 14m, Farm 43m (target 35), Forest 63m, Snowy 2h, City 4h, Space 7.7h, Mythic Meadow 16.9h (target 15h+). First training purchase at 74 s, the FTUE path modelled.
- **Big finds:** median times are first Epic 6 m, first Legendary ~25 m, first Mythic ~1.5 h (P90 6 h). This comes from ~13 throws/min with skippable Commons. The odds were kept. If Mythics should feel rarer, lengthen throw cycles (`MinSecondsBetweenThrows`) rather than odds.
- **Useless items:**
  - The Throwing Machine barely matters under the cap. It saves seconds of filling, not progress. This is acceptable as a convenience.
  - Book 25% cash is small mid- and late-game (luck, trophy and title carry the book).
  - Dupe auto-sell is <1% of income. That is sensible for a dupe, which is worth 120 s of its income.
- **Game-breaking:** nothing found. A lucky early Mythic gives a temporary jump of 1-2 zones.
- **Consumables:**
  - A Golden Whistle kept for Legendary+ is the best cash buy (Mythic Meadow 15.1 h vs 16.9 h).
  - Lucky Biscuit, Sticky Ball and Treat Pocket are mild (+5-20% income).
- **Robux:**
  - 2x Cash is the strongest pass: about 3x income and Mythic Meadow ~35% sooner (11.1 h). That is strong but not a skip.
  - Lucky Paw, Extra Slots and Fast Growth are each worth +5-15% (Mythic Meadow ~16.1 h).
  - All passes together: 11.0 h.
- **Sensitivity:**
  - Offline matters. 30-min sessions reach Mythic Meadow in 12.7 h of play, and 3-h sessions do not reach it within 20 h.
  - Timing skill matters a lot: Mythic Meadow in 8 h at mean quality 0.85, and Space in 13.3 h at 0.60.
  - Both are intended levers.

## Known gaps / TODO
- The sim's F2P player shops greedily cheapest-first and claims book rewards instantly. Real players are less optimal.
- Squirrel bones assume one join per 15 min of play.
- The posted odds do not mention the Treat Pocket second roll.
- `Products` Robux prices and ids are still 0 placeholders.

---

# Throw a Ball for Dogs balance simulation

Generated by `python3 tools/balance_sim.py --runs 60 --hours 30`. Medians over 60 runs.

## Analytic

Timing quality (release error sd 0.46s): mean 0.700, median 0.715, P10 0.377, P90 1.000; Perfect-band share 11%

| Zone | Min dist | ThrowPower for median throw (Tennis / Rubber / Flying Disc / Glow / Golden) | Common $/s | Mythic $/s |
|---|---|---|---|---|
| Backyard | 0 | 0 / 0 / 0 / 0 / 0 | 1.0 | 200.0 |
| Park | 100 | 140 / 112 / 94 / 80 / 70 | 4.0 | 800.0 |
| Beach | 250 | 350 / 280 / 233 / 200 / 175 | 16.0 | 3.20K |
| Farm | 450 | 629 / 504 / 420 / 360 / 315 | 64.0 | 12.80K |
| Forest | 700 | 979 / 783 / 653 / 560 / 490 | 256.0 | 51.20K |
| Snowy Peaks | 1000 | 1398 / 1119 / 932 / 799 / 699 | 1.02K | 204.80K |
| City Rooftops | 1400 | 1957 / 1566 / 1305 / 1119 / 979 | 4.10K | 819.20K |
| Space Station | 1900 | 2656 / 2125 / 1771 / 1518 / 1328 | 16.38K | 3.28M |
| Mythic Meadow | 2500 | 3495 / 2796 / 2330 / 1997 / 1748 | 65.54K | 13.11M |

| Ball | Range | Luck | Price | Common | Uncommon | Rare | Epic | Legendary | Mythic | E[income/throw] vs Tennis |
|---|---|---|---|---|---|---|---|---|---|---|
| Tennis Ball | x1.00 | +0.00 | 0.0 | 75.00% | 17.00% | 5.50% | 2.00% | 0.40% | 0.10% |  x1.00 |
| Rubber Ball | x1.25 | +0.10 | 500.0 | 72.50% | 18.70% | 6.05% | 2.20% | 0.44% | 0.11% |  x1.04 |
| Flying Disc | x1.50 | +0.20 | 50.00K | 70.00% | 20.40% | 6.60% | 2.40% | 0.48% | 0.12% |  x1.09 |
| Glow Ball | x1.75 | +0.35 | 5.00M | 66.25% | 22.95% | 7.43% | 2.70% | 0.54% | 0.14% |  x1.15 |
| Golden Ball | x2.00 | +0.50 | 3.00B | 62.50% | 25.50% | 8.25% | 3.00% | 0.60% | 0.15% |  x1.22 |

Variant odds per non-Common: Gold 4.910%, Shadow 1.496%, Rainbow 0.300% (none 93.29%). Expected variant income mult per non-Common: x1.230

Training rates at level L (TP/s x 1.5^L): Pull-Up 0.80 (at 1.6 reps/s), Throwing Machine 3.00 (costs max($5, TP x 0.10)/rep), Sprint 0.87 (one lap of 220 studs at WalkSpeed 16 = 13.8s)

| Training level | Cost | Gain mult |
|---|---|---|
| 1 | 50.0 | x1.0 |
| 2 | 130.0 | x1.1 |
| 3 | 338.0 | x1.1 |
| 4 | 878.0 | x1.1 |
| 5 | 2.28K | x1.2 |
| 6 | 5.94K | x1.2 |
| 8 | 40.16K | x1.3 |
| 10 | 271.48K | x1.3 |
| 12 | 1.84M | x1.4 |
| 15 | 32.25M | x1.6 |

| Slot purchase # | Slots after | Cost |
|---|---|---|
| 1 | 15 | 250.0 |
| 2 | 20 | 1.12K |
| 3 | 25 | 5.06K |
| 4 | 30 | 22.78K |
| 5 | 35 | 102.52K |
| 6 | 40 | 461.32K |
| 7 | 45 | 2.08M |
| 8 | 50 | 9.34M |

## F2P baseline: milestones (median play time)

| Milestone | Target | Median | P10 run | P90 run | Reached in 30h |
|---|---|---|---|---|---|
| First training purchase | < 2m | 74s | 74s | 74s | 100% |
| Reach Park (median throw lands there) | 5m | 4m | 4m | 4m | 100% |
| Reach Beach (median throw lands there) | 15m | 14m | 13m | 15m | 100% |
| Reach Farm (median throw lands there) | 35m | 43m | 39m | 45m | 100% |
| Reach Forest (median throw lands there) | 60m | 63m | 62m | 63m | 100% |
| Reach Snowy Peaks (median throw lands there) | 2.0h | 2.0h | 2.0h | 2.0h | 100% |
| Reach City Rooftops (median throw lands there) | 4.0h | 4.0h | 3.2h | 4.0h | 100% |
| Reach Space Station (median throw lands there) | 8.0h | 7.7h | 7.0h | 8.0h | 100% |
| Reach Mythic Meadow (median throw lands there) | 15.0h | 16.9h | 15.1h | 18.1h | 100% |
| First throw lands in Park | - | 5m | 5m | 5m | 100% |
| First throw lands in Beach | - | 8m | 8m | 10m | 100% |
| First throw lands in Farm | - | 24m | 22m | 26m | 100% |
| First throw lands in Forest | - | 60m | 57m | 61m | 100% |
| First throw lands in Snowy Peaks | - | 63m | 63m | 64m | 100% |
| First throw lands in City Rooftops | - | 2.1h | 2.0h | 2.1h | 100% |
| First throw lands in Space Station | - | 4.0h | 3.2h | 4.1h | 100% |
| First throw lands in Mythic Meadow | - | 6.1h | 5.3h | 6.9h | 100% |
| First Uncommon caught | - | 88s | 74s | 3m | 100% |
| First Rare caught | - | 2m | 78s | 6m | 100% |
| First Epic caught | - | 6m | 81s | 13m | 100% |
| First Legendary caught | - | 24m | 7m | 64m | 100% |
| First Mythic caught | - | 94m | 25m | 5.9h | 100% |
| First Gold variant caught | - | 6m | 119s | 15m | 100% |
| First Shadow variant caught | - | 20m | 3m | 56m | 100% |
| First Rainbow variant caught | - | 65m | 20m | 3.1h | 100% |
| Buy Rubber Ball | - | 3m | 3m | 3m | 100% |
| Buy Flying Disc | - | 14m | 13m | 15m | 100% |
| Buy Glow Ball | - | 60m | 60m | 60m | 100% |
| Buy Golden Ball | - | 3.0h | 3.0h | 3.0h | 100% |

## F2P baseline: curve at checkpoints (medians)

| Play time | Income $/s | ThrowPower | Training lvl | Ball | Slots | Median-throw zone | Cash on hand |
|---|---|---|---|---|---|---|---|
| 5m | 9.6 | 185.0 | 5 | Rubber | 20 | Park | 3.38K |
| 15m | 285.7 | 255.0 | 8 | Flying Disc | 35 | Beach | 25.34K |
| 30m | 1.24K | 320.0 | 10 | Flying Disc | 40 | Beach | 236.58K |
| 60m | 5.71K | 420.0 | 12 | Flying Disc | 45 | Farm | 3.45M |
| 2.0h | 164.93K | 700.0 | 16 | Glow | 60 | Forest | 112.09M |
| 3.0h | 635.41K | 900.0 | 19 | Glow | 65 | Snowy Peaks | 927.91M |
| 5.0h | 4.68M | 1.10K | 21 | Golden | 70 | City Rooftops | 8.87B |
| 10.0h | 54.77M | 1.43K | 24 | Golden | 85 | Space Station | 269.25B |
| 15.0h | 128.43M | 1.65K | 26 | Golden | 90 | Space Station | 1.16T |
| 20.0h | 201.22M | 1.75K | 27 | Golden | 90 | Mythic Meadow | 3.74T |
| 30.0h | 356.22M | 1.88K | 28 | Golden | 95 | Mythic Meadow | 10.28T |

## Purchases: cost in minutes of income at the moment of purchase (median)

| Purchase | Median play time | Cost | Minutes of income it cost |
|---|---|---|---|
| Training L1 | 74s | 50.0 | 3.8 |
| Training L2 | 110s | 130.0 | 0.8 |
| Training L3 | 2m | 338.0 | 1.0 |
| Slots ->15 | 2m | 250.0 | 1.0 |
| Ball Rubber | 3m | 500.0 | 1.1 |
| Training L4 | 3m | 878.0 | 1.8 |
| Slots ->20 | 3m | 1.12K | 2.4 |
| Training L5 | 3m | 2.28K | 4.8 |
| Slots ->25 | 6m | 5.06K | 4.1 |
| Training L6 | 7m | 5.94K | 2.5 |
| Training L7 | 7m | 15.45K | 6.1 |
| Slots ->30 | 9m | 22.78K | 5.5 |
| Training L8 | 12m | 40.16K | 4.8 |
| Ball Flying Disc | 14m | 50.00K | 3.8 |
| Slots ->35 | 15m | 102.52K | 6.5 |
| Training L9 | 17m | 104.41K | 4.3 |
| Training L10 | 22m | 271.48K | 7.8 |
| Slots ->40 | 28m | 461.32K | 8.0 |
| Training L11 | 34m | 705.84K | 6.5 |
| Training L12 | 41m | 1.84M | 11.2 |
| Slots ->45 | 49m | 2.08M | 9.5 |
| Training L13 | 60m | 4.77M | 6.7 |
| Ball Glow | 60m | 5.00M | 5.3 |
| Slots ->50 | 60m | 9.34M | 9.5 |
| Training L14 | 60m | 12.41M | 12.6 |
| Training L15 | 60m | 32.25M | 28.5 |
| Slots ->55 | 73m | 42.04M | 15.6 |
| Training L16 | 91m | 83.86M | 16.5 |
| Slots ->60 | 114m | 189.17M | 19.9 |
| Training L17 | 2.0h | 218.04M | 11.0 |
| Training L18 | 2.0h | 566.91M | 27.4 |
| Slots ->65 | 2.1h | 851.27M | 37.3 |
| Training L19 | 2.9h | 1.47B | 38.6 |
| Ball Golden | 3.0h | 3.00B | 47.7 |
| Slots ->70 | 3.4h | 3.83B | 47.4 |
| Training L20 | 4.0h | 3.83B | 32.6 |
| Training L21 | 4.0h | 9.96B | 56.0 |
| Slots ->75 | 5.0h | 17.24B | 52.1 |
| Training L22 | 5.0h | 25.91B | 58.5 |
| Training L23 | 6.0h | 67.36B | 100.0 |
| Slots ->80 | 7.0h | 77.57B | 68.4 |
| Training L24 | 7.7h | 175.13B | 95.9 |
| Slots ->85 | 9.0h | 349.07B | 129.7 |
| Training L25 | 10.0h | 455.33B | 129.7 |
| Training L26 | 12.0h | 1.18T | 220.5 |
| Slots ->90 | 14.0h | 1.57T | 218.4 |
| Training L27 | 16.8h | 3.08T | 324.4 |
| Slots ->95 | 21.0h | 7.07T | 499.1 |
| Training L28 | 25.0h | 8.00T | 456.2 |

## Where the money came from / went (median share over 30h)

Earned: Active 46.0%, Offline 45.8%, Sell 0.6%, Daily 7.6%, Book 0.0%

Spent: Training 58.9%, Ball 0.0%, Slots 41.1%, Boosts 0.0%, Items 0.0%, MachineReps 0.0%

Catches by tier (median): Common 13650, Uncommon 6001, Rare 1744, Epic 515, Legendary 84, Mythic 17

Misses by tier (median): Common 723, Uncommon 673, Rare 427, Epic 278, Legendary 70, Mythic 23

Bones after 30h: 2429 (all cosmetics cost 1750)

## Scenarios vs F2P baseline (medians)

| Scenario | Income @3h | Income @10h | Zone @10h | Reach Farm | Reach Snowy | Reach City | Reach Space | Reach Mythic Meadow | First Legendary | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| F2P baseline | 635.41K | 54.77M | Space Station | 43m | 2.0h | 4.0h | 7.7h | 16.9h | 24m |  |
| No Throwing Machine (pull-ups only) | 616.80K | 59.56M | Space Station | 46m | 2.1h | 4.1h | 7.6h | 16.5h | 38m | checks the machine matters |
| Buys Lucky Biscuit when cheap | 689.93K | 58.56M | Space Station | 43m | 2.0h | 4.0h | 7.4h | 16.6h | 39m | cash boost |
| Buys Sticky Ball when cheap | 646.59K | 59.38M | Space Station | 43m | 2.0h | 4.0h | 7.9h | 16.9h | 39m | cash boost |
| Carries a Golden Whistle (Legendary+) | 686.47K | 100.93M | Space Station | 43m | 2.0h | 4.0h | 7.0h | 15.1h | 39m | cash consumable |
| Carries a Treat Pocket (EpicPlus mode) | 761.75K | 66.53M | Space Station | 45m | 2.0h | 4.0h | 7.4h | 17.1h | 39m | cash consumable |
| Casual: 30-min sessions | 1.64M | 89.83M | Space Station | 32m | 93m | 2.9h | 5.5h | 12.7h | 40m | same play hours, 2x the offline gaps |
| Grinder: 3-h sessions | 258.95K | 26.54M | City Rooftops | 43m | 3.0h | 5.6h | 11.0h | never | 39m | fewer offline top-ups |
| Weak timing (mean quality 0.60) | 473.95K | 39.59M | City Rooftops | 62m | 3.2h | 7.0h | 13.3h | never | 29m |  |
| Skilled timing (mean quality 0.85) | 1.36M | 128.33M | Mythic Meadow | 30m | 63m | 2.9h | 4.0h | 8.0h | 29m |  |
| Robux: 2x Cash pass | 2.05M | 181.35M | Space Station | 35m | 117m | 3.0h | 5.3h | 11.1h | 29m | gamepass |
| Robux: Extra Slots pass | 694.87K | 64.03M | Space Station | 42m | 2.0h | 4.0h | 7.5h | 16.1h | 29m | gamepass |
| Robux: Fast Growth pass | 718.22K | 63.02M | Space Station | 39m | 2.0h | 3.9h | 7.3h | 16.1h | 39m | gamepass |
| Robux: Lucky Paw pass | 657.54K | 65.69M | Space Station | 41m | 2.0h | 4.0h | 7.3h | 16.1h | 25m | gamepass |
| Robux: all passes | 2.91M | 197.72M | Space Station | 29m | 98m | 2.9h | 5.0h | 11.0h | 23m | whale |

(Scenario runs are capped at 20h of play; 'never' = not within that window.)

