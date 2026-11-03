# Throw a Ball for Dogs — Game Design Document

> Working title. The display name lives in `src/shared/Config/Game.luau` (`Name`). It must never be the name of an existing Roblox game, a real brand or a real character.
>
> Status: v1 build spec. Numbers marked **[tunable: path]** live in that config file. The file that owns a value always wins over this document. Values marked **(proposed)** are this doc's suggested defaults for a config file that another workstream owns. Anything marked **TBD** is a deliberate open question for the user.

---

## Contents

1. Overview & pillars
2. The world: compact T map, one shared platform, 6-player server
3. Core loop
4. Throw and meter maths
5. Zones (nine distinct biomes)
6. Roll pipeline and odds tables
7. Variants
8. Loss, near-miss and runaway design
9. Lucky Streak
10. Protection items
11. Balls (consumable)
12. Training (one station)
13. Economy and the income formula
14. Timers (puppy growth, daily walk, squirrel, offline)
15. Kennel Book and rewards
16. Yards, slots, render cap and dupes
17. Social and broadcasts
18. Monetisation and fair-odds disclosure
19. FTUE: the first two minutes
20. CUTSCENE CONTRACT (the throw cutscene: beats, timings, rules)
21. Tech architecture
22. Data storage (schema v2)
23. Live-ops ideas
24. Risks
25. Appendix: config file index

---

## 1. Overview & pillars

**One line:** Charge a throw, hit the sweet spot, watch the ball sail into one of nine themed zones, and find out which of 720 dogs comes bounding back with it, and whether it actually catches.

**Genre:** Throw-and-collect idler with a skill-timed throw, a rarity-driven reveal and a yard that earns passive income.

**Pillars**

| # | Pillar | What it means in practice |
|---|--------|---------------------------|
| 1 | **Every throw is a little show** | Each throw ends in a reveal. Rarity is held back for suspense, the variant appears as a badge, and the catch beat is a coin flip you can feel. Rarer dogs get longer, louder scenes. |
| 2 | **Skill in, luck out** | The throw itself is skill: you time a meter, and a better release goes further and reaches richer zones. What comes back is luck, and every odd is posted in-game. |
| 3 | **Losses sting but are fair** | A missed catch shows you exactly what you lost, then the dog runs into the plaza where everyone can see it. The visible Lucky Streak and the pre-bought protection items stop a loss from feeling like a scam. |
| 4 | **Your yard is your trophy case** | Dogs roam your yard, earn money and grow from puppy to adult. The Kennel Book is a permanent record of everything you have ever caught. |
| 5 | **Social, not competitive-toxic** | 6 players share a plaza and one throwing platform (they queue for it), and see each other's throws, runaways, squirrel chases and broadcasts. There is no PvP stealing. |

**Explicit non-goals (v1):** no rebirth system, no hunger or care meters, no trading, no PvP stealing, no auto-throw.

---

## 2. The world: compact T map, one shared platform, 6-player server

The source of truth is `src/shared/Config/Layout.luau` (module-level detail: `docs/WORLD.md`). Units are studs. Origin is the centre of the T junction, +Z runs down the stem away from the yards.

**Two levels.** The whole hub (six yards, street, plaza with the ball shop and training area, and the throwing platform) sits on a **plateau at `Layout.HubY` = 40**. The fetch field stays at **`Layout.GroundY` = 0**. The plateau ends along the throw line (Z = 60) in a **stepped rock cliff** (`World/Cliff.luau`: four layered strata of irregular slabs, each stepping further out than the one above, moss caps on the ledges, from under the west wall to under the east wall) that drops 40 studs to the field. Players never go down: railings and an invisible edge wall (`Layout.Edge.GuardHeight` 20, taller than any jump) close the whole plaza front.

```
 Z -180  ~~~~~~~~~~~~~~ scenery wall ~~~~~~~~~~~~~~           } hub PLATEAU, walking surface Y = HubY (40)
 Z -154 ┌Y1┬Y2┬Y3┬Y4┬Y5┬Y6┐   6 player pens (yards) 52 x 100, centres X -140..140, gates face the street
 Z  -54 ├──── STREET ─────┤   X -170..170
 Z  -34     └─ PLAZA ─┘       X -60..60: ONE ball shop (west, "BALL SHOP" sign), ONE training area (east,
             │      │         "TRAINING" sign), 2 spawns, runaway lawn + squirrel loop
 Z   34      [DECK  ]         ONE throwing platform, deck FLUSH with the plaza paving (X -18..18, Z 34..60)
 Z   60  ===throw line=== ▼   deck front edge = plateau edge = distance 0; stepped rock cliff drops 40 studs
             │      │
             │FIELD │         stem X -120..120 at Y = GroundY (0), 9 zone bands by distance
 Z 3260      └──────┘
 Z 3310  ~~~ scenery wall ~~~ side walls from |X| 236 outward, all >= 200 studs tall (hub side on the plateau,
                              field side on the field)
```

| Area | Bounds / values | Contents (world tags) |
|------|-----------------|-----------------------|
| Pens / yards (crossbar) | 6 yards 52 x 100, centres X = -140, -84, -28, 28, 84, 140; CenterZ -104; 4-stud hedge gaps; gates open south onto the street | `YardPlot`, `YardSign` (OwnerLabel), `DogSpot` x12, kennel with `KennelSign` (CountLabel), `TrophySpot` |
| Street | X -170..170, Z -54..-34 | Walkway between the yards and the plaza. |
| Plaza | X -60..60, Z -34..60, Y 40 | `PlazaSpawn` x2, **one** `ShopStand` (ShopId `"Balls"`, at `Layout.Shop`, with its "BALL SHOP" sign), **one** `TrainingStation` (StationId `"Main"`, at `Layout.Training`, with its "TRAINING" sign), `RunawayArea` lawn, `SquirrelPath` waypoints (`Order`) |
| Throwing platform | `Layout.Platform`: deck 36 x 26 set **flush** into the plaza paving (surface Y = 40, `Flush = true`), front edge on the throw line and the cliff edge (Z = 60). No ramp, no steps: players walk straight on from three sides. Low non-colliding front railing (caps below the launch height 44) | `ThrowPad` (PadIndex 1 = the deck), marked throw spot at (0, 40, 56), `QueueSpot` x5 (`Order` 1-5) at X 10, Y 40, beside it |
| Cliff | Z = 60, Y 0..40, from wall to wall; foot reaches Z ~63.8 | Stepped rock strata (`Cliff.luau`); pure scenery (non-colliding, non-queryable). The shortest throw (5 studs) lands past the foot and every arc clears the ledges (`tools/worldcheck/run.luau`). |
| Fetch field (stem) | X -120..120, Z 60..3260; themed aprons out to \|X\| 266 (they run under the walls) | `ZoneBand` (ZoneId) x9, a zone-name arch + themed gate at each band start, `DistanceMarker` (Distance) boards every 100 studs |
| Scenery walls | \|X\| >= 236, Z <= -180, Z >= 3310; >= 200 studs tall | Stepped cliff / hedge tiers coloured by the zone they border; the hub-side runs rise from the plateau, the field runs from the field, cut at the throw line where the cliff joins them; non-colliding scenery |

**Feel target:** a compact social hub with one very long "how far can you throw" runway. Every walk between a yard gate, the platform, the shop and the training area is at most 300 studs (under 10 s at WalkSpeed 32; `tools/worldcheck/run.luau` measures it). From the deck, 40 studs up, you look out and down the stem over nine distinct biomes that fade into an `Atmosphere` haze; the tall themed walls mean the horizon is never flat ground. Colours come from `Zones.luau` `Theme` and `src/shared/Config/WorldTheme.luau`.

**Movement:** every character spawns with WalkSpeed 32 and JumpPower 60 (`Config/Game.luau` `WalkSpeed` / `JumpPower`, applied by `CharacterService` on every spawn).

**No text in the world** except the zone name on each zone arch board, the yard owner signs, the kennel count and the two plaza name signs, **"BALL SHOP"** (`ShopLabel`) and **"TRAINING"** (`TrainingLabel`). The platform, queue spots, distance markers and the field end are blank, colour-coded boards; the UI carries all other text. `tools/worldcheck/run.luau` enforces this allowlist.

**Streaming:** `Workspace.StreamingEnabled` with `StreamingMinRadius` 448 / `StreamingTargetRadius` 1024 (`default.project.json`). The scenery walls, the cliff and the outskirts (plateau block, field underlay, treeline, clouds) are Persistent models, as are each zone's ground, arch, boundary line and landmark, so the horizon and the field silhouette never stream out (about 1,700 always-streamed parts of ~7,100). Field props and ground cover are Atomic models that stream in around the player and around the landing spot (the cutscene calls `RequestStreamAroundAsync(LandPos)`).

**Server size:** public servers hold **6 players**, one yard each, all sharing the one throwing platform. **"Max players = 6" is a Studio Game Settings value** (Game Settings → Places → Max Players). It cannot be set from code, so it must be set by hand before publishing. On join the server gives the player the lowest free yard index. That yard is theirs until they leave, when it is cleared and the `YardSign` resets.

**Platform queue:** a player is *on the platform* while their root is inside the deck rectangle (`Layout.Platform` Center / Size grown by `Game.Platform.EdgeMargin` 1.5) and no lower than the deck minus `Game.Platform.YTolerance` (the deck is flush, so the rectangle, not the height, decides). Players join a FIFO queue as they arrive (`ThrowQueue`). Position 1 has the turn and is moved onto the throw spot; the others are moved onto the queue spots in order. Each turn is one throw. The turn ends `Game.Throw.MinSecondsBetweenThrows` after that throw finishes, and the thrower goes to the back. A turn-holder who does not start within `Game.Platform.TurnStartSeconds` (15 s) also goes to the back, and walking off the platform leaves the line. The server publishes the player attributes `OnPlatform` (boolean) and `ThrowQueuePos` (0 = not queued, 1 = your turn, 2+ = place in line).

**World tags contract** (created by `src/server/World/**`, consumed by services and the client): `YardPlot`, `YardSign`, `DogSpot`, `KennelSign`, `TrophySpot`, `ThrowPad`, `QueueSpot`, `TrainingStation`, `ShopStand`, `PlazaSpawn`, `RunawayArea`, `SquirrelPath`, `ZoneBand`, `DistanceMarker`. Services look things up by tag and attribute, never by instance path. `src/server/World/WorldCheck.luau` checks after every build that each tagged part sits on its ground (the deck for `ThrowPad` / `QueueSpot`), that spawn volumes are clear and that the tag counts match.

---

## 3. Core loop

```
 ┌─► Walk onto the deck ─► Queue on the platform ─► Your turn: "Click to throw"
 │                                                              │
 │          click: the vertical meter starts (0-100) ─► click again to release
 │                                                              │
 │     equipped consumable ball used up (back to Tennis at 0) ─► ball arcs off the cliff (Y 44) to the field (Y 0)
 │                                                              │
 │          server rolls: breed (tier -> dog) -> variant -> catch (all before any visuals)
 │                                                              │
 │     Cutscene: wind-up -> ball POV -> landing -> dog hops in -> "1 out of N" -> caught/missed -> reveal card
 │                                   │                                      │
 │                            CAUGHT: dog to your pen            MISSED: runs into the plaza 60 s
 │                            (puppy, 20% income, grows)         (whistle prompt if owned)
 │                                   │
 │          $/s accrues ─► buy balls (per throw) / training / slots / boosts in the shop panel
 └──────────────── ThrowPower up, better ball ─► reach further zones ◄──┘
```

**Session rhythm:** a throw takes about 5-25 s including the cutscene (5.5 s Common ... 12 s Mythic to the end card, plus the card), then the next player in line throws. Training reps at the one training station fill the gaps between turns. Every 15 min a squirrel event pulls everyone into the plaza. The daily walk is a once-a-day reason to come back. Puppy growth is a "come back later" reason.

---

## 4. Throw and meter maths

### 4.1 Input and authority

1. **The throw UI is hidden unless you are on the platform.** While `OnPlatform` is true and `ThrowQueuePos == 1`, the HUD shows the equipped ball and a **"Click to throw"** prompt ("Tap to throw" on touch). Waiting players see their place in line instead.
2. **Click once** (mouse button 1, tap, Space or gamepad R2) to start: the client fires `ChargeBegin()` and the server records `t0 = os.clock()`. The server accepts it only from the player at queue position 1 who is on the platform, not mid-throw, not in a cooldown, and who has not thrown this turn.
3. The **vertical power meter** (`src/client/UI/Components/PowerMeter.luau`) appears and fills and empties with the live value in numbers (0-100, ticks at 0/25/50/75/100). It is a **deterministic triangle wave with period P = 1.6 s** (`Util/Meter.luau`), driven locally from the same start moment.
4. **Click again** to release: the client fires `ChargeRelease()` with **no payload**. The server computes `elapsed = os.clock() - t0` and derives the meter position itself. **The client never sends a position or a distance.**
5. If the server gets no release within `MaxChargeSeconds` (6 s), it auto-releases at the current position. This stops stalling and simple macros. The meter and prompt also hide while a panel (shop, book, settings) is open.

Latency mostly cancels out, because both events take roughly the same one-way delay to arrive. Jitter (± tens of ms) is the residual error, and the sweet-spot width is tuned to tolerate about 60 ms of it (see Risks).

### 4.2 Meter position

```
phase = (elapsed mod P) / P              -- 0..1
pos   = 1 - | 2*phase - 1 |              -- triangle: 0 at t=0, 1 at t=0.8 s, 0 at t=1.6 s
```

### 4.3 Timing quality (proposed; **[tunable: Config/Game.luau → Meter]**)

| Band | Meter pos | Quality multiplier | Window per sweep |
|------|-----------|--------------------|------------------|
| **Perfect** | pos ≥ 0.92 | 1.00 | ±64 ms around the peak (128 ms) |
| Good | 0.75 ≤ pos < 0.92 | lerp 0.80 → 0.97 | |
| OK | pos < 0.75 | 0.35 + 0.45 × (pos / 0.75) | |

A minimum charge of 0.25 s is required (`MinChargeSeconds`). An earlier release is a "flub" at quality 0.35. The HUD shows the band name ("PERFECT!") on release.

### 4.4 Distance

```
Distance = ThrowPower × Ball.RangeMult × Quality × (1 + scatter)
scatter  ~ Uniform(-0.02, +0.02)   -- server-side only (proposed)
Distance = clamp(Distance, 5, Layout.Field.MaxZ - Layout.ThrowLine.Z)   -- 5 .. 3200
```

The small scatter means a player standing on a zone boundary sometimes lands either side, so "barely missed the next zone" moments happen naturally. The landing point is `Z = Layout.DistanceToZ(Distance)` with a small random X in the middle half of the field (|x| ≤ 56; the field around it is filled, but nothing there collides or answers raycasts). The zone is the `Zones` entry where `MinDistance ≤ Distance < MaxDistance`. The last zone includes 3200.

**Distance is horizontal** and measured from the throw line (the deck's front edge), so raising the platform did not change any distance or zone. The deck only changes the flight: the ball leaves the hand at `LaunchPos = ThrowSpot + (0, Game.Throw.LaunchHeight, 0)` (Y = 44) and lands at `LandPos = (landX, 0, ThrowLine.Z + Distance)`. `src/shared/Util/BallFlight.luau` solves a true ballistic parabola between the two (flight time `0.7 + d/1800` s clamped to 0.7-2.2 s, apex `0.22 × d` clamped to 15-260 studs above the launch). The server times the throw with it and sends `LaunchPos`, `LandPos` and `FlightTime` in `ThrowResult`; every client draws the ball on that same arc (`src/client/BallFlight.client.luau`) and the cutscene camera follows it.

---

## 5. Zones (nine distinct biomes)

Source: `src/shared/Config/Zones.luau` (bands, income, theme colours); look: `src/server/World/Field.luau` + `src/server/World/Zones/<ZoneId>.luau`; ambience: `src/client/ZoneAmbience.client.luau`. There are 9 zones by distance band, and BaseIncome is ×4 per zone.

| # | ZoneId | Name | Distance (studs) | BaseIncome $/s | Dogs (C/U/R/E/L/M) | Look (ground · props · landmark) |
|---|--------|------|------------------|----------------|--------------------|----------------------------------|
| 1 | Backyard | Backyard | 0 – 100 | 1 | 54/13/7/3/2/1 | mown lawn · picket fences, kennels, flower beds, toys · stacked doghouse tower |
| 2 | Park | Park | 100 – 250 | 4 | 54/13/7/3/2/1 | park grass + paths · trees, benches, lamps, duck pond, fountain · clock tower (no numerals) |
| 3 | Beach | Beach | 250 – 450 | 16 | 54/13/7/3/2/1 | sand + sea strips · palms, umbrellas, sand castles, lifeguard tower · lighthouse |
| 4 | Farm | Farm | 450 – 700 | 64 | 54/13/7/3/2/1 | tilled ground · barn, silo, crop rows, hay bales, scarecrows, tractor · windmill |
| 5 | Forest | Forest | 700 – 1000 | 256 | 54/13/7/3/2/1 | dark grass + leaf litter · dense pines, logs, mushrooms, fireflies · giant tree |
| 6 | SnowyPeaks | Snowy Peaks | 1000 – 1400 | 1,024 | 54/13/7/3/2/1 | snow · snowy pines, drifts, ice rocks, snowmen, snowfall · mountain peak |
| 7 | CityRooftops | City Rooftops | 1400 – 1900 | 4,096 | 54/13/7/3/2/1 | concrete roof deck · AC units, water towers, blank neon billboards · stepped skyscraper |
| 8 | SpaceStation | Space Station | 1900 – 2500 | 16,384 | 54/13/7/3/2/1 | diamond-plate deck · modules, solar arrays, dishes, domes, stars · rocket on its pad |
| 9 | MythicMeadow | Mythic Meadow | 2500 – 3200 | 65,536 | **53**/13/7/3/2/**2** | pastel glacier ground · crystals, giant flowers, floating islets · crystal spire |

Every zone's plot (the **whole field width**, |x| ≤ 120, over its distance band) is **filled** in three layers (`src/server/World/Zones/Kit.luau`, seeded so every build is identical):

1. **Ground cover:** 200+ tiny one-part items (flowers, tufts, pebbles, shells, snow lumps, leaves, cracks, puddles) over the whole plot, density rising zone by zone; grouped into Atomic `CoverCell` models (80 × 60 studs).
2. **Spaced props:** 20-40 mid-size props per zone (trees, boulders, bales, umbrellas, AC units, crystals…), each an Atomic model, at least `Kit.PropGap` (6) studs apart edge to edge and as far from the landmark, boundary, arch pillars and distance markers, so every landing spot has open ground for the dog. Inside the ball-POV corridor (|x| ≤ 30) only low props (≤ 10 studs).
3. **One landmark** at the field edge (doghouse tower, clock tower, lighthouse, windmill, giant tree, mountain peak, skyscraper, rocket, crystal spire), Persistent so it is visible from the platform.

Each zone starts with a **full-width boundary** (a low picket / hedge / dune / rail / logs / ice / parapet / bulkhead / crystal line across x -120..120) plus a side-only zone-name gantry (nothing crosses the middle). Everything in the field except the `ZoneBand` floors is non-colliding and non-queryable, so the ball, the landing raycast and the camera pass through; each zone's ground model, arch, boundary and landmark are Persistent, props and cover stream (section 2). Particles where they fit, and a matching section of the scenery walls. When the camera is over a zone (the cutscene flies into it), `ZoneAmbience.client.luau` tweens Lighting (ClockTime, Ambient), the Atmosphere colour and a client-only `ZoneAmbienceCC` colour correction toward that zone's preset (e.g. sunset Farm, dusk City, night Space, violet Meadow), and back to the server's defaults over the platform, plaza and yards. `tools/worldcheck/zones.luau` checks each zone (ground, cover and prop counts and spacing, landmark, boundary, streaming modes, part budget < 8,000 for the field).

First-reach pacing (median F2P, `tools/balance_sim.py`, throw cycle = the real cutscene budgets): Farm ~28 min, Forest ~1 h, Snowy Peaks ~1.1 h, City Rooftops ~2 h, Space Station ~3.5 h, Mythic Meadow ~6 h. These are simulation results, not values in code; they come from ThrowPower and the ball tiers (sections 11 and 12).

Total roster: **720 base dogs** (9 × 80). Mythic Meadow trades one Common for a second Mythic, so it still has 80 dogs. The roster is generated by `tools/roster.py` into `src/shared/Data/Dogs.luau`, with the source data in `data/**`.

---

## 6. Roll pipeline and odds tables

### 6.1 Order (server, all before `ThrowResult` is sent)

1. **Zone** from distance (section 4.4).
2. **Tier roll:** start from `Rarities.Tiers[*].Odds`, then apply **luck** (ball luck shift + luck boosts + Kennel Book permanent luck). Formula (proposed, **[tunable: Config/Game.luau → Luck]**): multiply every non-Common tier's odds by `(1 + Luck)`. Common absorbs the difference so the total stays 1. Luck is capped so that Common odds never fall below 0.40.
3. **Dog roll:** pick uniformly among that zone's dogs of the rolled tier.
4. **Variant roll** (non-Common only): Rainbow, then Shadow, then Gold (section 7).
5. **Catch roll:** `CatchChance = clamp(Tier.Catch + catch boosts, 0, 0.99)`. If the Lucky Streak is armed and the tier is Legendary+, the catch is set to 1 (section 9). The tutorial throw is also forced to a catch.
6. **Treat Pocket second roll** if the first roll missed and the player has one (section 10).
7. Save the outcome, then broadcast `ThrowResult` to all clients and start the cutscene.

The outcome is fixed and persisted before any visuals start. Leaving mid-cutscene does not change the result. Caught dogs are already in your data.

### 6.2 Tier odds (base, no luck)

| Tier | Odds | 1 in | Catch | Income mult | Colour |
|------|------|------|-------|-------------|--------|
| Common | 75% | 1.33 | 95% | ×1 | grey |
| Uncommon | 17% | 5.9 | 90% | ×2.5 | green |
| Rare | 5.5% | 18 | 80% | ×6 | blue |
| Epic | 2% | 50 | 65% | ×15 | purple |
| Legendary | 0.4% | 250 | 45% | ×50 | orange |
| Mythic | 0.1% | 1,000 | 30% | ×200 | pink-red |

### 6.3 Per-dog odds (chance a given throw into that zone rolls one specific dog)

`per-dog = TierOdds / dogs-of-that-tier-in-zone`

| Tier | Dogs/zone | Per-dog appear | 1 in | Per-dog **own** (appear × catch) | 1 in |
|------|-----------|----------------|------|----------------------------------|------|
| Common | 54 | 1.389% | 72 | 1.319% | 76 |
| Uncommon | 13 | 1.308% | 76 | 1.177% | 85 |
| Rare | 7 | 0.786% | 127 | 0.629% | 159 |
| Epic | 3 | 0.667% | 150 | 0.433% | 231 |
| Legendary | 2 | 0.200% | 500 | 0.090% | 1,111 |
| Mythic | 1 | 0.100% | 1,000 | 0.030% | 3,333 |
| *Meadow Common* | 53 | 1.415% | 71 | 1.344% | 74 |
| *Meadow Mythic* | 2 | 0.050% | 2,000 | 0.015% | 6,667 |

"Own" figures are without boosts and without the Lucky Streak. With the streak (section 9), the effective long-run catch rate is about 54% for Legendary (1 in ~926 to own a specific Legendary) and about 46% for Mythic (1 in ~2,190).

### 6.4 Example with luck

A Golden ball (Luck 0.5, proposed) multiplies the non-Common tiers by 1.5: Uncommon 25.5%, Rare 8.25%, Epic 3%, Legendary 0.6%, Mythic 0.15%. Common drops to 62.5%. The odds panel always shows the **player's live odds** with their current luck, next to the base odds.

### 6.5 Odds panel (in-game, always available)

A HUD button opens a panel showing:
- tier odds (base and current, with active luck sources listed),
- catch chance per tier (base and current),
- variant chances,
- per-dog odds for the zone you are currently reaching,
- the Lucky Streak rule.

Before each throw the HUD also shows a line for your current reach, for example **"Reach: Beach • Catch: Common 95% … Mythic 30% (+10% Sticky Ball)"**.

---

## 7. Variants

Source: `Rarities.Variants`. Only non-Common dogs can roll a variant. The roll order is Rainbow → Shadow → Gold → none, and each is checked against its own chance. With these small numbers the effective chances are essentially the listed values.

| Variant | Chance | Income mult | Visual (runtime `VariantFX`, `src/shared/Dog/`) |
|---------|--------|-------------|--------------------------------------------------|
| Gold | 5% | ×3 | metallic gold coat + sparkle particles |
| Shadow | 1.5% | ×7 | black coat + purple smoke + glowing eyes |
| Rainbow | 0.3% | ×15 | HSV-cycling coat + trail |
| none | ~93.2% | ×1 | |

- A variant appears as a **badge** and never as a word in the dog's name.
- Variants stack with rarity. A Rainbow Mythic is 200 × 15 = ×3,000.
- **Form count:** 720 base dogs + 3 variants × each non-Common dog. Standard zones have 26 non-Commons. Mythic Meadow has 27 (13+7+3+2+2). That gives 26 × 8 + 27 = **235 non-Common dogs → 705 variant forms → 1,425 forms total**. The brief says "1,422", which would only be right if Meadow had 26 non-Commons. See Risks R9. The roster generator is the authority.

---

## 8. Loss, near-miss and runaway design

A loss must feel **dramatic, readable and recoverable**. It must never feel like a cheat.

**Reveal order on a miss (locked):**
1. Suspense beat (the rarity is still hidden).
2. **Dog + rarity revealed first.** You see exactly what you nearly got.
3. **Variant badge** if one was rolled.
4. **Fumble:** the dog jumps, the ball bounces off its nose, and an "ohhh" sting plays.
5. **It runs off.** The dog sprints off-camera toward the plaza.
6. End card in its "missed" form: "**Ran off!** [Name] • LEGENDARY • $X/s" in the rarity colour, with the Lucky Streak meter visibly ticking up.
7. If the player owns a Golden Whistle: **"Use Golden Whistle? (N left)"** prompt. It is never shown to players who own none, and **a Robux purchase prompt is never shown mid-loss**.

**Runaway dog:** the server spawns the missed dog (with its variant FX) in the `RunawayArea` of the plaza for **60 s** (proposed **[tunable: Config/Timers.luau → RunawaySeconds]**). It wanders, visible to everyone and nameplated "Ran off from [Player]". `EventState{Kind="RunawayDog"}` drives a small timer UI. In v1 the runaway is not catchable by other players (TBD for v1.1, see Live-ops).

**Broadcasts** (section 17): "A LEGENDARY [Name] ran off from X!" goes to the server; Legendary+ also goes cross-server.

**Near-miss levers:** the distance scatter at zone edges ("PERFECT! …3 studs short of Farm") and the catch-beat animation, which plays the ball grazing the dog's mouth on a miss.

---

## 9. Lucky Streak

- It is **visible**: a HUD meter with 2 pips is shown next to the throw button, labelled "Lucky Streak".
- **Counter:** consecutive Legendary+ catch failures (after any Treat Pocket second roll). Commons through Epics do not touch it.
- When the counter reaches `Rarities.LuckyStreakMisses` (= 2), the meter glows "ARMED". **The next Legendary+ roll is a guaranteed catch**, and `ThrowResult.LuckyStreakTriggered = true` adds a special flourish to the catch beat.
- Reset to 0 on any Legendary+ catch, whether natural, streak or Treat Pocket. A **Golden Whistle recall also counts as a catch** and resets the counter (proposed; avoids double-dipping on protection).
- It persists in `PlayerState.LuckyStreak` and across sessions.
- Long-run effect: per Legendary+ cycle, expected catches = 1 and expected attempts = 1 + q + q², so the effective catch rate is 54.0% for Legendary (p = .45) and 45.7% for Mythic (p = .30). The counter is shared across Legendary and Mythic.

---

## 10. Protection items

Protection is always **bought beforehand** in the shop panel (Boosts / Items tabs). It never comes from a popup during a loss.

| Item | Type | Effect | Acts on | Where tuned |
|------|------|--------|---------|-------------|
| **Sticky Ball** | timed boost (proposed 15 min) | +10 percentage points catch chance on every throw (proposed) | catch roll | Config/Shop.luau, Config/Products.luau |
| **Lucky Biscuit** | timed boost (proposed 15 min) | +0.5 Luck (proposed) | tier/breed roll | Config/Shop.luau |
| **Golden Whistle** | consumable | After a miss, recall the runaway dog into your yard as a catch. Usable from the end-card prompt or while the dog roams (60 s window). | outcome after a miss | Config/Shop.luau |
| **Treat Pocket** | consumable, auto | When a catch roll fails, automatically spend one Treat Pocket for a second catch roll at the same chance. This is resolved server-side before the cutscene; the cutscene shows a "treat toss" beat. | catch roll | Config/Shop.luau |

Rules:
- **Luck boosts act on the breed (tier) roll only. Catch boosts act on the catch roll only.** They never cross over.
- Every active boost shows as a HUD chip with a countdown and is listed in `ThrowResult.Boosts`.
- Treat Pocket has a player setting with three modes, `Always`, `EpicPlus` (default) and `Off` (`Shop.TreatPocketModes`). It is stored server-side in `Settings.TreatPocketMode` and changed from the Settings panel through `DogAction("SetTreatPocketMode", mode)`.
- The whistle is validated server-side: the throw must be the player's own missed throw, it must be inside the window, they must own whistles, and it is single-use per throw. It goes through the `UseWhistle` RemoteFunction.

---

## 11. Balls (consumable)

**Every ball except the Tennis Ball is consumable: one purchase = one throw** (`Uses = 1`). The Tennis Ball is free, unlimited and always available. **[tunable: Config/Balls.luau]**

| Ball | Id | RangeMult | Luck shift | Price per throw | Consumable |
|------|----|-----------|------------|-----------------|------------|
| Tennis Ball | `Tennis` | 1.00 | 0 | free | no (unlimited) |
| Rubber Ball | `Rubber` | 1.25 | +0.10 | $50 | yes, 1 throw |
| Flying Disc | `FlyingDisc` | 1.50 | +0.20 | $500 | yes, 1 throw |
| Glow Ball | `Glow` | 1.75 | +0.35 | $10,000 | yes, 1 throw |
| Golden Ball | `Golden` | 2.00 | +0.50 | $250,000 | yes, 1 throw |

- **Buying:** in the shop panel's Balls tab (`ShopPurchase("Ball:<id>")`), or from the ball shop counter in the plaza, whose prompt opens that tab. Each purchase adds `Uses` throws to `PlayerState.Balls[id]` (capped at `Balls.MaxOwned` = 9,999) and equips that ball. Purchases repeat: buy five Glow Balls to get five Glow throws.
- **Equipping:** `EquipBall(id)` equips any ball you have throws of; the server refuses a consumable with 0 left. `ShopPurchase("Ball:Tennis")` / `EquipBall("Tennis")` always works.
- **Using up:** when a throw is accepted (on release), the equipped consumable is used up: its count drops by 1. At 0 the entry is removed, `EquippedBall` falls back to `Tennis` and the player gets a notice ("That was your last Glow Ball: back to the Tennis Ball."). `ThrowResult.BallId` is the ball that was thrown and `BallsLeft` the throws left of it.
- **Showing it:** the HUD's throw prompt shows the equipped ball's icon and the "xN" count, and each shop card shows the count you hold. `PlayerStats.Ball(state)` (the ball the next throw uses) is the one source for both the server and the UI.
- To reach Mythic Meadow (2,500 studs) with a Golden Ball on a Perfect throw needs ThrowPower ≥ 1,250; with a Tennis Ball it needs 2,500. So balls stay the "big throw" decision: a Golden throw costs $250,000 each, and players spend them on the throws that matter. In the balance sim a player who never buys balls stalls at Farm.

---

## 12. Training (one station)

ThrowPower is the grind stat. It is permanent, never resets (there is no rebirth) and is saved in `PlayerState.ThrowPower`. **[tunable: Config/Training.luau]**

There is **one training station** in the plaza: the `TrainingStation`-tagged mat at `Layout.Training`, StationId `"Main"`.

| Station (`StationId`) | Interaction | Gain per rep | Cost | Server cooldown |
|-----------------------|-------------|--------------|------|-----------------|
| Main ("Training Station") | its ProximityPrompt "Train" (press E / tap), or the `Train("Main")` remote, within `InteractRange` (14 studs) | +1.0 × TrainMult | free | 0.5 s |

- Starting ThrowPower is 60 (`Game.StartingThrowPower`). That gives a Tennis-ball Backyard throw of up to 60 studs, and Park becomes reachable after a few minutes of reps or with a Rubber Ball.
- **Training upgrades are kept** (shop panel → Yard tab, `ShopPurchase("Training")`, `Training.UpgradeCost`: $50 × 2.6^(level-1), 29 levels). Each level does two things: raises the **power cap** (`Training.Upgrades.Caps`, 100 at level 0 up to 2,000 at level 29) and multiplies rep gains (`TrainMult` = 1.03^level). Reps cannot push ThrowPower past the cap, so each upgrade is the gate to the next zone and reps are the short grind (~20-70 s of reps per level) that fills it. The HUD shows "Power X/cap" while below the cap.
- The first training purchase is part of the FTUE (section 19).
- Anti-autofarm: reps stop crediting after `Game.AfkSeconds` (15 min) without movement; see section 21.4.

---

## 13. Economy and the income formula

### 13.1 Income per dog

```
$/s = Zone.BaseIncome × Rarity.IncomeMult × (1 + Offset) × Variant.IncomeMult × GrowthFactor
Offset       = per-dog constant in 0.00 .. 0.20 (from the roster, so dogs in a tier aren't identical)
Variant mult = 1 (none) | 3 Gold | 7 Shadow | 15 Rainbow
GrowthFactor = 0.20 while a puppy, 1.00 once grown (no partial lerp in v1)
```

Examples (adult, offset 0):

| Dog | $/s |
|-----|-----|
| Backyard Common | 1 |
| Beach Rare | 16 × 6 = 96 |
| Forest Epic Gold | 256 × 15 × 3 = 11,520 |
| Meadow Mythic | 65,536 × 200 = 13.1M |
| Meadow Mythic Rainbow | ≈ 196.6M |

Gamepass multipliers (e.g. 2× Cash) apply on top, at payout.

### 13.2 Payout

The server ticks income once per second. It adds up all owned dogs, not only the 12 that are rendered. The HUD shows Cash plus "+$X/s". Values above 1e6 are shown compactly (K, M, B, T, Qa…) using the formatter in `src/shared/Util/**`.

### 13.3 Sinks

Consumable balls (paid per throw, section 11), training upgrades, extra yard slots (geometric price), cosmetics (Bones only) and timed boosts (cash versions of Sticky Ball and Lucky Biscuit priced in $, so non-payers have access too). All of them are bought in the shop panel (tabs Balls, Boosts, Yard, Items, Style, Robux); the plaza's one ball shop counter opens it on the Balls tab.

### 13.4 Second currency: Bones

Bones are earned only from squirrel events, the daily walk and Kennel Book milestones. They are spent only on cosmetics (collars, hats, yard decor and paw-print trails), so they never buy power.

---

## 14. Timers

**[tunable: Config/Timers.luau]**

### 14.1 Puppy growth (real time, continues offline)

| Rarity | Grow time (proposed) |
|--------|----------------------|
| Common | 5 min |
| Uncommon | 15 min |
| Rare | 45 min |
| Epic | 2 h |
| Legendary | 6 h |
| Mythic | 12 h |

`BornAt` and `GrownAt` are stored per dog. Puppies render at about 0.6 scale and earn 20%. The **Instant Grow** dev product grows one chosen puppy now. Variants do not change grow time.

### 14.2 Daily walk

You claim it once per UTC day by clicking the "Claim daily walk" banner at the top of the HUD (`ClaimDailyWalk`). The reward is a cash bonus (proposed: 10 minutes of current income, minimum $100), some Bones, and **one free premium throw**: the next throw counts as having a Golden-ball luck shift plus Sticky Ball for that throw. `LastDailyWalk` stores the UTC day number. `EventState{Kind="DailyWalk"}` shows the banner when it is available.

### 14.3 Squirrel event

- Every **15 min** a squirrel spawns and runs the `SquirrelPath` waypoints (by `Order`) through the plaza for about 45 s. `EventState{Kind="Squirrel"}` carries `EndsAt`.
- The first player to touch it, checked by server distance, wins. One of the winner's dogs "chases it down" in a short world beat and **drops Bones** (proposed 25 + 5 per player in the server).
- Everyone else who was in the plaza during the event gets a small consolation (proposed 3 Bones), which rewards showing up.

### 14.4 Offline earnings

On join, `min(now - lastSeen, 2 h) × current $/s × 0.5` (50% rate after the balance pass, so a full 2 h away pays 1 h of income; **[tunable: Config/Timers.luau → OfflineCapSeconds / OfflineRate]**). It is shown in a "While you were away" toast. Puppy growth also continues offline, uncapped.

---

## 15. Kennel Book and rewards

- The book records every dog form **ever** caught, permanently, even after a dog is sold. Storage: `Book[DogId] = { Variants = {"Gold", …} }`.
- It is browsable by zone. Uncaught dogs show as silhouettes with their rarity frame, and caught ones show the rig preview.
- **Per-zone milestones** on that zone's 80 base dogs, claimed via `ClaimBookReward(zoneId, milestone)`:

| Milestone | Dogs | Reward (proposed) |
|-----------|------|-------------------|
| 25% | 20 | Cash (scaled by zone BaseIncome, e.g. 600 s of that zone's Common income × 10) |
| 50% | 40 | **Permanent luck** +0.02 (stacks across zones; max +0.18 total) |
| 75% | 60 | **Yard trophy statue** for that zone at `TrophySpot` |
| 100% | 80 | **Title** (e.g. "Beach Legend") shown on the nameplate |

- **Variant completion badges** (Roblox badges) are separate: one per zone per variant, earned by catching every non-Common dog of that zone in that variant. That is 27 badges, plus an optional global "All Rainbows" badge.

---

## 16. Yards, slots, render cap and dupes

- **Slots:** a yard starts with **10 slots** (`SlotCount`). More can be bought in the shop panel's Yard tab for cash at geometric prices (`Shop.Slots`), and the Extra Slots gamepass adds slots too. A full yard means a new catch prompts "Yard full: Sell a dog or buy a slot". In the meantime the new dog is held in the kennel and does not earn until a slot is freed. It is never lost.
- **Render cap:** at most **12 dogs roam** the yard (`Layout.Yards.MaxRoamingDogs`), one per `DogSpot` (SpotIndex 1-12). The player chooses which via `DogAction(Display)`; by default the 12 with the highest $/s are shown. The rest live in the **kennel building**, whose `KennelSign.CountLabel` shows "Kennel: N". Kennelled dogs still earn. This cap exists for performance only.
- **Dupes:** if you catch a DogId+Variant you already own, it **auto-sells** for `SellValue` (proposed: 120 s of its adult income) unless you set **Keep** for that rarity (Settings panel; stored server-side in `Settings.KeepDupes` and changed through `DogAction("SetKeepDupes", "<Rarity>=true|false")`) or press Keep on the end card. It is still recorded in the book. `DogAction(Sell)` sells a dog manually at the same price.
- **Owner sign:** `YardSign.OwnerLabel` shows the owner's display name and total $/s.

---

## 17. Social and broadcasts

| Event | Scope | Text |
|-------|-------|------|
| Catch Rare+ | server | "X caught a RARE [Name]!" |
| Catch Legendary+ | server + **cross-server** | "X caught a LEGENDARY [Name]!" (with variant badge) |
| Miss Epic+ | server | "An EPIC [Name] ran off from X!" |
| Miss Legendary+ | server + **cross-server** | "A MYTHIC [Name] ran off from X!" |
| Squirrel won | server | "X's dog caught the squirrel!" |

- Sent through the `Broadcast` remote with `{Kind, Text, Rarity?, Variant?, Global}`. The text is coloured by rarity in a top-centre ticker and the chat system channel.
- Cross-server uses `MessagingService` topic `ThrowABallForDogs_Broadcast` (proposed). It is throttled to stay well under the MessagingService publish limits: at most one publish per server per 2 s, and excess is queued and dropped after 30 s.
- Spectators see every other player's throw as a **park-view banner** (section 20.5), so the server feels alive.
- There is no in-world leaderboard board. `leaderstats` (Income $/s, Cash) show in the Roblox player list (`LeaderboardService`); global boards are a v1.1 idea.

---

## 18. Monetisation and fair-odds disclosure

Principles: no pay-to-win stealing, no purchase popup during a loss, every paid random influence shows exact odds before purchase, and everything paid is also earnable or not needed to finish the game. IDs live in **Config/Products.luau**; in-game prices and effects live in **Config/Shop.luau**.

**Gamepasses (permanent)**

| Pass | Effect |
|------|--------|
| 2× Cash | ×2 all income |
| Extra Yard Slots | +10 slots |
| Fast Growth | puppies grow 2× faster |
| VIP | nameplate tag, VIP cosmetics, +10% Bones |
| Lucky Paw | permanent +0.25 Luck (random influence, odds disclosed) |

**Developer products (consumable)**

| Product | Effect |
|---------|--------|
| Sticky Ball (15 min) | +10 pp catch |
| Lucky Biscuit (15 min) | +0.5 Luck |
| Golden Whistle ×1 / ×3 | recall a runaway |
| Treat Pocket ×3 | second catch rolls |
| Instant Grow | grow one puppy |
| Cash packs | scaled to current income |
| Server Luck (15 min) | +0.25 Luck for everyone in the server; announced with the buyer's name |

**Fair-odds disclosure:** any product that changes a random outcome (Lucky Paw, Lucky Biscuit, Server Luck, Sticky Ball, Treat Pocket) shows the **before/after odds table** on its shop card before the purchase button. The server also calls `PolicyService:GetPolicyInfoForPlayerAsync` and, where `ArePaidRandomItemsRestricted` is true, **hides or disables paid products that influence random outcomes** for that player (they keep the cash-priced versions). Purchases are handled in `ProcessReceipt` with idempotent receipt records (section 22).

---

## 19. FTUE: the first two minutes

| Time | Beat | Notes |
|------|------|-------|
| 0:00 | Spawn at a `PlazaSpawn` on the plaza. An arrow points to the throwing platform at the cliff edge (walk straight onto the flush deck). | The yard is auto-assigned and the YardSign shows your name. |
| 0:10 | On the deck (queue if others are there). **Tutorial throw:** "Click to throw", then click again near the top of the meter. The meter runs at half speed for this throw only, client and server alike (`IsTutorial`). | Server forces Backyard, a Common and **a guaranteed catch**. |
| 0:20 | **Cutscene** (Common length, ~5.5 s) → end card "+$1/s". | It cannot be skipped this first time. |
| 0:30 | Guide arrow to your yard. The puppy appears at a DogSpot, a "+$" floater appears, and a tooltip explains puppy → adult (Common: 5 min). | |
| 0:50 | "Throw again!" Second turn (back of the line if others are queued) with normal odds and normal meter. The catch chance line on the HUD is highlighted. | |
| 1:20 | Cash ≥ the first training upgrade price (starter cash $50). Arrow to the training station → a few reps, then the shop panel's Yard tab → **first training purchase** → the power cap rises and the reach line updates. | Starter cash could instead buy one Rubber Ball throw; the guide points at training first. |
| 1:50 | Tooltips for the odds panel, Lucky Streak and Kennel Book, then `TutorialDone = true`. | Each tooltip is shown once. |

---

## 20. CUTSCENE CONTRACT

> **The throw cutscene (v1, built).** Client: `src/client/Cutscene/**` (controller `init`, `Director` = the thrower's sequence, `Spectator`, `Rig` = avatar throw, `Ball`, `DogActor`, `Effects`, `Sfx`, `Overlay` = counter / Skip / fallback UI, `TestPanel`, `Janitor`). Shared pure maths, Lune-tested: `src/shared/Cutscene/` (`Timeline`, `OddsCounter`, `Path`, `Shots`, `FakeResult`). **Every timing and tunable is one commented table: `src/shared/Config/Cutscene.luau`.**

### 20.1 Inputs and authority

- Everything is decided by the server before the cutscene starts. The cutscene only shows the `ThrowResult` (`ThrowId, ThrowerUserId, Distance, ZoneId, DogId, Rarity, Variant, Caught, CatchChance, LaunchPos, LandPos, FlightTime, LuckyStreakTriggered, TreatPocketUsed, WhistleOwned, WhistleCount`, plus `BallId`, `Status`, `DogUid`). `Timeline.Validate` normalises flags and never changes an outcome.
- It starts at the **meter release** (`ui.ThrowReleased`, fired by the HUD release, including the 6 s auto-release); a `ThrowResult` that arrives during the wind-up / flight is buffered into the running session. A result with no local release starts a session itself.
- On arrival the client calls `Players.LocalPlayer:RequestStreamAroundAsync(LandPos)` (pcall, task.spawn) so the landing zone streams in.
- The odds counter's target is display-only (posted odds); nothing the client could tamper with feeds an outcome.
- The thrower's camera is `Scriptable` and the whole HUD is hidden while it plays; controls are off and `Humanoid.AutoRotate` is off (the avatar is turned to face the field).

### 20.2 Beats (in order)

1. **Wind-up** (`WindUp.Duration` 1.2 s, release frame at `ReleaseAt` 0.95 s). The camera sweeps a half circle (`SweepTime` 0.9 s, round the throwing-arm side) from the default view to a low front shot at chest height looking at the face. The avatar winds up (body turns, arm back and up, one knee up) and throws overhand: uploaded `AnimationIds.WindUp/Throw` when both are non-zero, else procedural Motor6D C0 keyframes (`Config.Pose`, R15 and R6, every C0 restored). The ball (`Balls.ById[BallId].Color`) follows the right hand until the release frame.
2. **Launch + ball POV.** Whoosh, small camera shake, the camera whips (`WhipTime` 0.2 s) to just behind and `PovUp` 3.5 studs above the ball, looking along its travel (pitch follows 45% of the climb), FOV 78. On-screen flight = `result.FlightTime` remapped from the server's 1.0-2.3 s into **1.5-4 s**; the `Util/BallFlight` arc is time-scaled, starts in the hand, blends into the arc over 0.3 s and lands exactly on `LandPos`. Trail + looped wind whose volume / pitch rise with speed.
3. **Landing** (last 25% of the flight). The camera eases up and back to a wide shot (30 back, 24 up) looking down at the landing spot; the ball touches `LandPos` and makes 3 decaying bounces. Per-zone dust / splash / sparks + sound (`ImpactFX`: grass, sand, snow, roof grit, metal clank + sparks on the Space Station, crystal glitter in the Meadow).
4. **The dog arrives** (`Beats.DogArrive` 0.6-1.5 s). The real `DogId` model (`DogFactory` + `VariantFX`) hops in from off camera (inside the field edges) and stops beside the ball; the camera holds wide, then pushes in.
5. **The odds counter** (`Beats.Counter` 1.5 s Common ... 4 s Mythic). "1 out of 1" counts up to this dog's odds: every number to 30, then growing steps (≤ 90 ticks), ease-in, always landing exactly on the target, a rising-pitch click per tick. The text starts white and snaps (scale punch + one-frame flash) to each rarity colour as it crosses that tier's "1 in X" in this zone, climbing white → grey → green → blue → purple → orange → pink, and stops on the dog's colour; then the name, rarity tag and variant badge appear under it.
   **Target** = `floor(1 / (Odds.TierOdds(luck, DogCatalog.ZoneTiers(zone))[rarity] / #DogCatalog.ZoneTierList(zone, rarity)))`, luck = `State.Luck()` captured at the release — the Odds panel's own functions and rounding (its `FormatNumber.Compact` floors, so the counter's final number formats to the panel's text). Examples: Backyard Mythic, no luck: 0.1% / 1 = 1 in 1,000; Farm Legendary with the Golden Ball (luck 0.5): 0.6% / 2 = 1 in 333. `Counter.IncludeCatch = true` multiplies by the catch chance (the panel's "This dog" column).
6. **Outcome** (`Beats.Outcome`). Caught: the dog picks up the ball, turns and hops toward the hub with the camera following from behind, then is removed (DogService already put the real dog in the pen). Missed: sniff, look at the camera, bolt out of frame, sad sting. Lucky Streak / Treat Pocket catches add a flourish line under the counter. Then the Reveal end card (`ui:ShowReveal`): CAUGHT, or RAN OFF with the whistle prompt only if `WhistleOwned`. Every exit from the card (OK, Whistle, Keep, timer) closes it exactly once.
7. **Return.** The camera tweens back (`Return.Time` 0.5 s), `CameraType` / `CameraSubject` / FOV are restored, the HUD reappears and `ui:FinishThrow(throwId)` sends `CutsceneFinished` exactly once (only for throws the server sent).

### 20.3 Timing per rarity (`Config/Cutscene.luau`, at the 1.5 s reference flight; release → end card)

| Rarity | Release | Flight | Settle | Dog | Counter | Hold | Outcome | **Total** |
|---|---|---|---|---|---|---|---|---|
| Common | 0.95 | 1.5 | 0.2 | 0.6 | 1.5 | 0.25 | 0.5 | **5.5 s** |
| Uncommon | 0.95 | 1.5 | 0.25 | 0.8 | 2.0 | 0.35 | 0.65 | **6.5 s** |
| Rare | 0.95 | 1.5 | 0.3 | 1.0 | 2.5 | 0.45 | 0.8 | **7.5 s** |
| Epic | 0.95 | 1.5 | 0.35 | 1.2 | 3.0 | 0.6 | 1.4 | **9.0 s** |
| Legendary | 0.95 | 1.5 | 0.4 | 1.4 | 3.5 | 0.75 | 2.0 | **10.5 s** |
| Mythic | 0.95 | 1.5 | 0.5 | 1.5 | 4.0 | 1.05 | 2.5 | **12.0 s** |

A longer throw adds up to 2.5 s of flight. `tools/tests/cutscene.luau` sums every beat per rarity against `Budget`. The Reveal end card then closes itself after `EndCard.AutoClose` (5 s Common ... 10 s Mythic) unless the player closes it first.

**Server timeout.** `Config/Timers.luau` computes `Timers.Cutscene[rarity]` from this file: `Budget + (Flight.Max - ReferenceFlight) + Fallback.HoldMax + EndCard.AutoClose + Return.Time` = **16.5 / 18.5 / 20.5 / 23 / 25.5 / 28 s** (Common ... Mythic). `ThrowService` finishes a throw on its own at release + `FlightTime` + that + `Timers.CutscenePadding` (5 s) if no `CutsceneFinished` arrives, so it never cuts a real cutscene short. A `CutsceneFinished` sooner than `0.9 × Timeline.EarliestEnd` (the Skip point, or the short-Common end, at this throw's on-screen flight) is held to that time. The platform turn ends `MinSecondsBetweenThrows` after the throw finishes, so the next player in line waits for the real cutscene, never for the timeout unless the thrower disconnects or stalls. The HUD's own safety unlock (`ui.Config.ReleaseSafetySeconds` = `Timeline.SafetySeconds()`, ~11.6 s) only covers a release the server refused.

### 20.4 Rules

- **Skip:** a Skip button appears when the counter starts (`Skip.FromBeat`); Legendary and Mythic can never be skipped (`Skip.Never`). Skipping cleans the scene and jumps to the end card with the correct outcome.
- **Settings.HideCommonReveals** ("Short Common reveals"): a Common plays wind-up + flight + landing, then the end card (no dog, no counter).
- **Late result:** if no `ThrowResult` has arrived by the release frame the ball flies an estimated arc (the server's distance formula without scatter) and blends into the real one when it arrives; at touchdown it holds the landing shot up to `Fallback.HoldMax` 3 s, then shows "The ball rolled away..." and unlocks without `CutsceneFinished`. A result that still arrives later only shows the end card (and then reports once).
- **Reduced motion** (`Settings.ReducedMotion`): no sweep / whip / push-in / follow / shakes / counter punches; hard cuts between the front, POV, wide and close shots.
- **Cleanup:** the whole sequence is `pcall`-wrapped; finish, skip, any error, death (`Humanoid.Died`) or character removal destroy every instance, connection, sound, tween and render binding (two `Janitor`s), restore every C0, the camera and the HUD, and unlock.
- **Spectators:** other clients get no camera work. `src/client/BallFlight.client.luau` → `Cutscene/Spectator` animates the thrower's avatar locally (procedural C0s do not replicate; uploaded animations replicate by themselves) and flies the same time-scaled ball, which bounces and rests for 6 s. The UI shows its Spectator banner.

### 20.5 Test place

`Config/Game.luau → CutsceneTestMode = true` adds a "Test cutscene" pill (right-middle; under the side menu on touch) that opens a kit Panel: a button per rarity × Caught / Missed × with / without a variant (variant choice cycles Gold / Shadow / Rainbow / Random), "Play random" and "Loop random" (back-to-back outcomes; the pill becomes "Stop loop"). Every outcome is a local fake from `FakeResult` (random zone and distance, real roster dog), flagged `IsTest`, never sent to the server (no `CutsceneFinished`, whistle / keep do nothing). Must be **false** in production.

### 20.6 Checks

`tools/tests/cutscene.luau` (budgets, config, flight remap, skip / short-Common / fallback rules, fakes), `cutscene_counter.luau` (target = Odds panel for every zone × tier × luck, colour climb, tick schedule), `cutscene_path.luau` (arc sampling, retarget, bounces, pose, camera shots), `cutscene_director.luau` (every branch end-to-end under the UI emulator with a virtual clock: camera / HUD / C0 restored, nothing left behind, `CutsceneFinished` exactly once), `cutscene_compile.luau`; `tools/uicheck` scenarios `cutscene-*` (counter at each colour, stopped with name / badge / flourish, Skip, fallback, test panel). PNGs in `docs/qa/cutscene/`. Camera feel, animation look, sounds and particle look can only be judged in Studio.

---

## 21. Tech architecture

### 21.1 Rojo layout

| Source | Roblox location |
|--------|-----------------|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

`default.project.json` holds exactly this mapping. The code is Luau, with `--!strict` where practical.

### 21.2 Modules

**Server (`src/server/`)** — `Main.server.luau` creates the remotes, builds the world, then starts the services in this order:
- `DataService`: load/save, session lock, autosave, migrations (schema v2), live attributes.
- `CharacterService`: WalkSpeed 32 / JumpPower 60 on every spawn.
- `BroadcastService`: server + MessagingService announcements.
- `DogService`: yard assignment, dogs, slots, dupes, growth, income tick, offline earnings, yard display, kennel sign, `DogAction` (incl. `SetKeepDupes` / `SetTreatPocketMode`).
- `BookService`: Kennel Book, milestones, trophies, variant badges.
- `EventService`: squirrel, runaway dogs, daily walk.
- `ThrowService`: platform presence + queue, charge timing, meter, distance, ball use-up, landing / flight (`BallFlight`), roll, `ThrowResult`, cutscene finish, Golden Whistle. Uses `ThrowQueue` (pure FIFO, Lune-tested) and `RollService` (pure rolls: tier, dog, variant, catch, Treat Pocket, Lucky Streak).
- `ShopService`: cash / Bones purchases (balls, training, slots, boosts, items, cosmetics), `EquipBall`, `ProcessReceipt`, game passes.
- `TrainingService`: the one station ("Main"), prompt + `Train` remote, power cap, AFK cut-off.
- `LeaderboardService`: `leaderstats` only.
- `World/**`: the world builder (`WorldBuilder`, `Outskirts`, `Yards`, `Street`, `Plaza`, `Platform`, `ThrowLine`, `Cliff`, `Field`, `Zones/*`, `Boundaries`, `Walls`, `Lighting`, `WorldCheck`; see `docs/WORLD.md`).

**Shared (`src/shared/`)**
- `Config/*`: Layout, Zones, Rarities, Game, Balls, Training, Shop, Timers, Products, WorldTheme, Icons, Cutscene.
- `Data/Dogs.luau`: generated roster.
- `Dog/`: `DogFactory`, `BodyTypes`, `DogAnimator`, `VariantFX`.
- `Cutscene/`: pure, Lune-tested cutscene maths: `Timeline` (beat plan, skip / short-Common / fallback rules, `EarliestEnd`, `Validate`), `OddsCounter` ("1 out of N" target, ticks, colour steps), `Path` (arc sampling, retarget, bounces, endpoints), `Shots` (camera shots, pose), `FakeResult` (test-panel fakes). All numbers from `Config/Cutscene.luau`.
- `Util/`: `BallFlight` (the throw arc), `Meter`, `PlayerStats` (derived stats incl. `Ball` / `BallCount`), `Odds`, `DogCatalog`, `FormatNumber`, `Rng`, `RateLimiter`, `Signal`, `Table`.
- `UI/PixelIcons.luau` (generated by `tools/icons.py`), `Remotes.luau`.

**Client (`src/client/`)**
- `Main.client.luau`: the only entry script. Starts the UI (`PlaceholderCutscene = false`), then `Cutscene` (`src/client/Cutscene/init.luau`: the thrower's cutscene → Reveal card → `ui:FinishThrow` → `CutsceneFinished`; if it fails to start, the UI's built-in end card takes over so throws still finish) and `Controllers/WorldController` (yard / runaway dog animation, shop counter prompt).
- `Cutscene/`: `init` (controller: release → `Director` session, ThrowResult buffering, `RequestStreamAroundAsync(LandPos)`, test panel), `Director` (the thrower's sequence, camera, skip, fallback, cleanup), `Spectator` (other players' throws: avatar + ball, no camera), `Rig` (procedural / uploaded throw), `Ball`, `DogActor`, `Effects` (impact FX, ground raycast with a `GroundY` fallback), `Sfx`, `Overlay` (counter / Skip / fallback UI), `TestPanel` (only when `Game.CutsceneTestMode`), `Janitor`.
- `UI/`: `init.luau` (wires remotes), `State`, `Router`, `Theme`, `Motion`, `Make`; `Screens/` HUD (currencies, boost chips, Lucky Streak, event banner, throw prompt + `Components/PowerMeter` vertical meter, queue line), Shop, Dogs, Book, Odds, Settings, Reveal, Spectator; `Components/` (Button, Card, Panel, Tabs, VirtualGrid, Toast, Icon, …).
- `BallFlight.client.luau`: other players' throws: hands each `ThrowResult` to `Cutscene/Spectator` (the thrower's own throw is the cutscene's).
- `ZoneAmbience.client.luau`: per-zone lighting ambience (section 5).

**Dog visuals are data.** There is one shared quadruped rig with 14 body types (toy, small_terrier, long_low, small_fluffy, corgi_type, medium_lean, medium_stocky, medium_fluffy, large_lean, large_athletic, large_fluffy, giant, giant_fluffy, poodle_type). Each dog is defined by body + scale + two coat colours + pattern + accessory + vfx tier, plus unique parts for Mythic. Rarity visual budget:

| Rarity | Visual budget |
|--------|---------------|
| Common | body + coat + simple marking |
| Uncommon | + pattern |
| Rare | + accessory |
| Epic | + signature accessory + idle particles |
| Legendary | + unique coat texture + aura |
| Mythic | + unique mesh parts (extra heads, wings, halo…) + full VFX |

Variants are applied at runtime by `VariantFX`.

### 21.3 Server authority

- Every outcome is decided on the server: distance, zone, dog, variant, catch, ball use-up, income, purchases and timers.
- The client receives state through `RequestState` (snapshot) and `StateUpdate` (full snapshot after any change; can be optimised to deltas later), plus the player attributes `OnPlatform` / `ThrowQueuePos`.
- The client may predict UI only, such as the meter animation and the ball arc.
- The RNG is `Random.new()` per server. Seeds are never exposed.
- Every remote validates argument types, enum values (ballId, stationId, itemId, action), ownership (dogUid belongs to the caller) and context (on the platform with the turn, in range of the training station).

### 21.4 Rate limits and anti-autofarm (`src/shared/Util/RateLimiter.luau`, values in Config/Game.luau `RateLimits`)

| Remote | Limit |
|--------|-------|
| ChargeBegin / ChargeRelease | one throw per turn; 1 throw in flight; hard min 2 s release → next ChargeBegin; 2 req/s |
| Train | 0.5 s station cooldown; 3 req/s |
| ShopPurchase, DogAction, UseWhistle, Claim* | 5 req/s, token bucket |
| EquipBall | 2 req/s |
| RequestState | 1 per 5 s |

Anti-autofarm measures:
- Throws need physical presence on the platform and the turn; an idle turn-holder goes to the back after 15 s.
- Release timing is human-scale. If the release-timing variance is near zero over 50 throws (a perfectly periodic macro), soft-flag it and add meter jitter for that player (proposed).
- Training reps stop crediting after **15 min with no movement** (AFK).
- Income itself is idle by design, so autofarming the throw is the only thing worth stopping.
- Every rejection is counted. Repeated violations are logged (analytics) but never auto-banned in v1.

---

## 22. Data storage (schema v2)

- **DataStore:** `ThrowABallForDogs_Player_v1`, key `u_<UserId>`, record `{ Data = PlayerState, Lock = { JobId, Time }? }`, with session locking taken over if stale for more than 10 min. The ProfileService pattern is implemented in-house with no external dependency.
- **Schema version 2** (`Version = 2`). `PlayerState` (see `Remotes.luau`): `Cash, Bones, ThrowPower, Balls, EquippedBall, SlotCount, Dogs, Book, BookRewards, Boosts, Whistles, TreatPockets, LuckyStreak, LastDailyWalk, TutorialDone, TutorialThrowDone, TrainingLevel, PermanentLuck, PremiumThrows, Settings { KeepDupes, TreatPocketMode }, Cosmetics, Titles, EquippedTitle, Trophies, VariantBadges, CommonCutscenesSeen, Stats, Receipts, LastSeen`.
- **Balls (v2):** `Balls = { [ballId] = remaining throws }` for consumable balls only (whole numbers ≥ 1, ≤ 9,999; absent = 0). The Tennis Ball is never stored. `EquippedBall` must name a ball with throws left, else it is reset to `Tennis` on load.
- **Migration v1 → v2:** v1 saves held permanent ownership `{ [ballId] = true }`. Those entries become 0 throws (dropped), the Tennis Ball entry is removed and `EquippedBall` is reset to `Tennis`. Everything else carries over; missing keys are filled from the defaults (`Table.Reconcile`) and bad numbers are sanitised. Migrations run in order from the stored `Version` (0 = pre-versioned).
- **Dogs:** an array of `{Uid, DogId, Variant?, BornAt, GrownAt, Displayed, …}`. Uid is a GUID. Store `DogId`, never computed income, so tuning income re-prices everyone automatically.
- **Book:** `{[DogId] = {Variants}}`. That is at most 720 keys plus variant lists, comfortably under the 4 MB key limit.
- **Saves** happen on autosave every 60 s, on leave and on `BindToClose`, with retry and exponential backoff, plus right after a Legendary+ throw and any Robux purchase.
- **Receipts:** `ProcessReceipt` records `PurchaseId` in the profile's `Receipts` (last 100) before granting, and returns `PurchaseGranted` only after a successful save. This makes grants idempotent.
- **Leaderboards (global, optional v1.1):** OrderedDataStore for total caught and best $/s.
- Studio: `Game.UseMockData` (or no API access) uses an in-memory mock store.

---

## 23. Live-ops ideas

- **Dog Show (v1.1):** a weekly server event. Players enter one dog, and a judge scores it on rarity, variant, cosmetics and a little randomness. Winners get Bones and a rosette cosmetic. Spectators vote for a "People's Choice".
- **Visiting breed days:** for 24 h, one zone's specific dog gets ×3 tier-internal weight, announced in the plaza ("Today in the Park: the Sunfleck Spaniel!"). It is disclosed in the odds panel because it changes per-dog odds.
- Catchable runaways: let other players try to coax a runaway with treats, splitting a reward with the original thrower (needs anti-grief design).
- Seasonal zones and skins (Snowy Peaks in winter decor), limited cosmetic collars for Bones.
- Weekend server luck (+0.1 for everyone), always shown in the odds panel.
- Adding new zones beyond Mythic Meadow requires extending the stem (`Layout.Field.MaxZ`).

---

## 24. Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | Network jitter makes Perfect releases feel unfair on high-ping or mobile devices | Server-timed window of ±64 ms tolerates ~60 ms of jitter. Consider an optional client-reported phase cross-checked within tolerance (v1.1). Collect analytics on the Perfect rate by platform. |
| R2 | Losing a Mythic feels rage-inducing | Reveal-first order, visible Lucky Streak, Treat Pocket and whistle bought beforehand, and the runaway is visible but never stolen. |
| R3 | Paid luck seen as gambling or not allowed in some regions | Disclosed before/after odds, PolicyService gating, cash-priced alternatives. |
| R4 | 720 dogs × 3 variants in-world is too heavy | One rig + data, 12-dog render cap per yard, kennel for the rest, VFX budgets per rarity, and runaway/spectator rigs pooled. |
| R5 | Exponential income (×4 per zone, up to ×3,000 multipliers) makes numbers overflow display or balance | Compact number formatter, Luau doubles (safe to ~1e15 exactly; display beyond is fine), and a balance pass on ball/upgrade prices. |
| R6 | The cutscene gets coupled to gameplay, or a client never reports `CutsceneFinished` | The cutscene only displays the `ThrowResult` (section 20). The server commits and saves the outcome before sending it, finishes the throw on its own after `Timers.Cutscene[rarity]` + padding (computed from `Config/Cutscene.luau`), and ignores a `CutsceneFinished` sooner than `Timeline.EarliestEnd`. |
| R7 | MessagingService limits during a burst of Legendaries | Throttle and queue (section 17); drop stale items. |
| R8 | "Max players = 6" forgotten at publish | Pre-publish checklist item: Studio Game Settings → Max Players = 6. The server also handles more than 6 gracefully (extra players get no yard and see a "server full" notice and teleport). |
| R9 | Form count mismatch: the brief says 1,422 forms, but the 53C/2M Meadow gives 27 non-Commons, so 720 + 3 × 235 = **1,425** | The roster generator (`tools/roster.py`) is authoritative. Variant badges are computed from data, not hard-coded. |
| R10 | Throw macros and autoclickers on training | Section 21.4. Since there is no rebirth, idle income is the intended AFK reward, which reduces the incentive to cheat. |
| R11 | DataStore failure losing a Legendary catch | Session lock, save after Legendary+ catch, retry/backoff, never grant from a failed load (kick and retry instead). |

---

## 25. Appendix: config file index

| File | Owns | Owner workstream |
|------|------|------------------|
| `src/shared/Config/Layout.luau` | world coordinates: `HubY` (plateau 40) / `GroundY` (field 0), yards, street, plaza, throw line (Y 40), flush platform (deck, throw spot, queue spots), cliff edge guard, shop + training positions, field, render cap | shared contract |
| `src/shared/Config/Zones.luau` | 9 zones, distance bands, BaseIncome, theme colours | shared contract |
| `src/shared/Config/Rarities.luau` | tier odds, catch, IncomeMult, PerZone, variants, LuckyStreakMisses | shared contract |
| `src/shared/Remotes.luau` | remote names + payload shapes | shared contract |
| `src/shared/Config/Game.luau` | Name, WalkSpeed / JumpPower, meter/quality bands, throw (LaunchHeight, scatter), platform queue (StandRadius tolerance, TurnStartSeconds), luck caps, rate limits, CutsceneTestMode | C1 server |
| `src/shared/Config/Balls.luau` | ball RangeMult, luck shift, price per purchase, Consumable / Uses, MaxOwned | C1 server |
| `src/shared/Config/Training.luau` | the one station ("Main"): gain, cooldown, range; upgrades (cost, mult, power caps) | C1 server |
| `src/shared/Config/Shop.luau` | in-game shop items, prices, boost effects, slot prices | C1 server |
| `src/shared/Config/Timers.luau` | growth times, daily walk, squirrel cadence, runaway seconds, offline cap; the server cutscene timeout `Cutscene[rarity]` (computed from `Config/Cutscene.luau`) + `CutscenePadding` | C1 server |
| `src/shared/Config/Cutscene.luau` | every throw-cutscene timing and tunable, one comment each: per-rarity beats + budgets, wind-up / pose, flight remap + POV camera, landing + impact FX, dog, odds counter, outcome, end card auto-close, return, skip / short Common / fallback / reduced motion / spectator / test rules, sound ids | cutscene |
| `src/shared/Config/Products.luau` | gamepass & dev product IDs → effects | C1 server |
| `src/shared/Config/WorldTheme.luau` | materials and colours for the world builder: plaza, platform, walls (per zone), field, lighting + Atmosphere haze | D world |
| `src/shared/Config/Icons.luau` | uploaded pixel-icon asset ids (icons are generated by `tools/icons.py`) | UI |
| `src/shared/Data/Dogs.luau` | the 720-dog roster (generated) | A roster |
