# Fetch Legends — Game Design Document

> Working title. The display name lives in `src/shared/Config/Game.luau` (`Name`). It must never be the name of an existing Roblox game, a real brand or a real character.
>
> Status: v1 build spec. Numbers marked **[tunable: path]** live in that config file. The file that owns a value always wins over this document. Values marked **(proposed)** are this doc's suggested defaults for a config file that another workstream owns. Anything marked **TBD** is a deliberate open question for the user.

---

## Contents

1. Overview & pillars
2. The world: T-shaped map and the 6-player server
3. Core loop
4. Throw and meter maths
5. Zones
6. Roll pipeline and odds tables
7. Variants
8. Loss, near-miss and runaway design
9. Lucky Streak
10. Protection items
11. Ball tiers
12. Training
13. Economy and the income formula
14. Timers (puppy growth, daily walk, squirrel, offline)
15. Kennel Book and rewards
16. Yards, slots, render cap and dupes
17. Social and broadcasts
18. Monetisation and fair-odds disclosure
19. FTUE: the first two minutes
20. CUTSCENE CONTRACT (placeholder; TBD items for the user)
21. Tech architecture
22. Data storage
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
| 5 | **Social, not competitive-toxic** | 6 players share a plaza and see each other's throws, runaways, squirrel chases and broadcasts. There is no PvP stealing. |

**Explicit non-goals (v1):** no rebirth system, no hunger or care meters, no trading, no PvP stealing, no auto-throw.

---

## 2. The world: T-shaped map and the 6-player server

The source of truth is `src/shared/Config/Layout.luau`. Units are studs. Origin is the centre of the T junction. +Z runs down the stem, away from the yards, and the ground top is Y = 0.

```
 Z -200 ┌──Y1──┬──Y2──┬──Y3──┬──Y4──┬──Y5──┬──Y6──┐   crossbar: 6 player yards (110 x 120 each)
 Z  -80 ├──────────────── STREET ─────────────────┤   X -380..380
 Z  -40       └──── PLAZA / DOG PARK HUB ────┘         X -120..120: spawn, shops, training, leaderboard
 Z   60             [ THROW LINE: 6 pads ]             pads at X -75,-45,-15,15,45,75
                    │                    │
                    │     FETCH FIELD    │             stem X -120..120, 9 zone bands
 Z 3260             └────────────────────┘
```

| Area | Bounds / values | Contents (world tags) |
|------|-----------------|-----------------------|
| Yards (crossbar) | 6 yards, centres X = -300, -180, -60, 60, 180, 300; CenterZ -140; size 110 x 120; gates open south onto the street | `YardPlot`, `YardSign` (OwnerLabel), `DogSpot` x12, kennel building with `KennelSign` (CountLabel), `TrophySpot` |
| Street | X -380..380, Z -80..-40 | Walkway between the yards and the plaza. Decoration only. |
| Plaza / dog park hub | X -120..120, Z -40..60 | `PlazaSpawn`, `ShopStand` x4 (Balls, Boosts, Yard, Cosmetics), `TrainingStation` x3 (PullUpBar, ThrowingMachine, Sprint), `Leaderboard`, `RunawayArea`, `SquirrelPath` waypoints |
| Throw line | Z = 60, 6 pads of 20 x 1 x 12 | `ThrowPad` (PadIndex 1-6). Pad *i* belongs to the owner of yard *i*. |
| Fetch field (stem) | X -120..120, Z 60..3260 | `ZoneBand` (ZoneId) x9, `DistanceMarker` (Distance) signs |

**Feel target:** a compact social hub with one very long "how far can you throw" runway, in the spirit of the classic throw-and-collect T layout. The yards and the plaza fit on one screen. Looking down the stem you should see the far zones as themed silhouettes so you have something to aspire to. Theme colours come from `Zones.luau` `Theme` and `src/shared/Config/WorldTheme.luau`.

**Server size:** public servers hold **6 players**, one yard and one throw pad each. **"Max players = 6" is a Studio Game Settings value** (Game Settings → Places → Max Players). It cannot be set from code, so it must be set by hand before publishing. On join the server gives the player the lowest free yard index. That yard and its pad are theirs until they leave, when the yard is cleared and the `YardSign` resets.

**World tags contract** (created by the world builder `src/server/World/**`, consumed by services and the client): `YardPlot`, `YardSign`, `DogSpot`, `KennelSign`, `TrophySpot`, `ThrowPad`, `TrainingStation`, `ShopStand`, `Leaderboard`, `PlazaSpawn`, `RunawayArea`, `SquirrelPath`, `ZoneBand`, `DistanceMarker`. The attributes are listed in the build brief. Services must look things up by tag and attribute, never by instance path.

---

## 3. Core loop

```
 ┌─► Stand on your pad ─► Hold to charge ─► Release on the meter ─► Ball flies (distance)
 │                                                              │
 │                                                     lands in a zone band
 │                                                              │
 │          server rolls: breed (tier -> dog) -> variant -> catch (all before any visuals)
 │                                                              │
 │                         Cutscene: suspense -> dog+rarity -> variant -> catch/fumble -> end card
 │                                   │                                      │
 │                            CAUGHT: dog to yard                MISSED: runs into plaza 60s
 │                            (puppy, 20% income, grows)         (whistle prompt if owned)
 │                                   │
 │                     $/s accrues ─► buy balls / training / slots / boosts
 └──────────────── ThrowPower up, better ball ─► reach further zones ◄──┘
```

**Session rhythm:** throws take about 3-20 s including the cutscene. Training reps fill the gaps between throws. Every 15 min a squirrel event pulls everyone into the plaza. The daily walk is a once-a-day reason to come back. Puppy growth is a "come back later" reason.

---

## 4. Throw and meter maths

### 4.1 Input and authority

1. The client presses throw (mouse, touch or gamepad button) and fires `ChargeBegin()`. The server records `t0 = os.clock()` for that player. The player must be on their own pad, must not be mid-throw and must not be in a cooldown.
2. The client shows a meter that sweeps 0 → 1 → 0. It is a **deterministic triangle wave with period P = 1.6 s**, driven locally from the same start moment.
3. On release the client fires `ChargeRelease()` with **no payload**. The server computes `elapsed = os.clock() - t0` and derives the meter position itself. **The client never sends a position or a distance.**
4. If the server gets no release within `MaxChargeSeconds` (proposed 6 s), it auto-releases at the current position. This stops "hold forever" stalling and simple macros.

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

The small scatter means a player standing on a zone boundary sometimes lands either side, so "barely missed the next zone" moments happen naturally. The landing point is `Z = Layout.DistanceToZ(Distance)` with a small random X inside the field. The zone is the `Zones` entry where `MinDistance ≤ Distance < MaxDistance`. The last zone includes 3200.

---

## 5. Zones

Source: `src/shared/Config/Zones.luau`. There are 9 zones by distance band, and BaseIncome is ×4 per zone.

| # | ZoneId | Name | Distance (studs) | BaseIncome $/s | Dogs (C/U/R/E/L/M) | Target first-reach time* |
|---|--------|------|------------------|----------------|--------------------|-------------------------|
| 1 | Backyard | Backyard | 0 – 100 | 1 | 54/13/7/3/2/1 | 0 min (spawn) |
| 2 | Park | Park | 100 – 250 | 4 | 54/13/7/3/2/1 | ~3 min |
| 3 | Beach | Beach | 250 – 450 | 16 | 54/13/7/3/2/1 | ~15 min |
| 4 | Farm | Farm | 450 – 700 | 64 | 54/13/7/3/2/1 | ~45 min |
| 5 | Forest | Forest | 700 – 1000 | 256 | 54/13/7/3/2/1 | ~2 h |
| 6 | SnowyPeaks | Snowy Peaks | 1000 – 1400 | 1,024 | 54/13/7/3/2/1 | ~5 h |
| 7 | CityRooftops | City Rooftops | 1400 – 1900 | 4,096 | 54/13/7/3/2/1 | ~10 h |
| 8 | SpaceStation | Space Station | 1900 – 2500 | 16,384 | 54/13/7/3/2/1 | ~20 h |
| 9 | MythicMeadow | Mythic Meadow | 2500 – 3200 | 65,536 | **53**/13/7/3/2/**2** | ~40 h+ |

\*These are pacing targets for the balance pass, not values in code. They are reached through ThrowPower and ball tier (sections 11 and 12).

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

Protection is always **bought beforehand** from the Boosts shop stand or the HUD shop. It never comes from a popup during a loss.

| Item | Type | Effect | Acts on | Where tuned |
|------|------|--------|---------|-------------|
| **Sticky Ball** | timed boost (proposed 15 min) | +10 percentage points catch chance on every throw (proposed) | catch roll | Config/Shop.luau, Config/Products.luau |
| **Lucky Biscuit** | timed boost (proposed 15 min) | +0.5 Luck (proposed) | tier/breed roll | Config/Shop.luau |
| **Golden Whistle** | consumable | After a miss, recall the runaway dog into your yard as a catch. Usable from the end-card prompt or while the dog roams (60 s window). | outcome after a miss | Config/Shop.luau |
| **Treat Pocket** | consumable, auto | When a catch roll fails, automatically spend one Treat Pocket for a second catch roll at the same chance. This is resolved server-side before the cutscene; the cutscene shows a "treat toss" beat. | catch roll | Config/Shop.luau |

Rules:
- **Luck boosts act on the breed (tier) roll only. Catch boosts act on the catch roll only.** They never cross over.
- Every active boost shows as a HUD chip with a countdown and is listed in `ThrowResult.Boosts`.
- Treat Pocket has a player toggle (default on) so players can save them for Legendary+ (proposed option: "Only use on Epic+").
- The whistle is validated server-side: the throw must be the player's own missed throw, it must be inside the window, they must own whistles, and it is single-use per throw. It goes through the `UseWhistle` RemoteFunction.

---

## 11. Ball tiers

Balls are **permanent owned tiers**. You buy one once, then equip any you own (`EquipBall`). **[tunable: Config/Balls.luau]** (values proposed):

| Ball | RangeMult | Luck shift | Price (proposed) | Unlock feel |
|------|-----------|------------|------------------|-------------|
| Tennis | 1.00 | 0 | free | starter |
| Rubber | 1.25 | +0.10 | $500 | Park → Beach |
| Frisbee | 1.50 | +0.20 | $25,000 | Farm → Forest |
| Glow | 1.75 | +0.35 | $2.5M | Snowy → City |
| Golden | 2.00 | +0.50 | $250M | Space → Meadow |

To reach Mythic Meadow (2,500 studs) with a Golden ball on a Perfect throw needs ThrowPower ≥ 1,250. With a Tennis ball it needs 2,500, so the balls matter.

---

## 12. Training

ThrowPower is the grind stat. It is permanent, never resets (there is no rebirth) and is saved in `PlayerState.ThrowPower`. **[tunable: Config/Training.luau]**

| Station (`StationId`) | Interaction | Gain per rep (proposed) | Cost | Server cooldown |
|-----------------------|-------------|-------------------------|------|-----------------|
| PullUpBar | click / tap reps | +1 × TrainMult | free | 0.5 s |
| ThrowingMachine | timed rep (mini meter) | +4 × TrainMult | cash per rep, scales with ThrowPower | 1.0 s |
| Sprint | run a lap around the plaza track, checkpoints validated by the server | +12 × TrainMult | free | per lap |

- Starting ThrowPower is 60 (proposed). That gives a Tennis-ball Backyard throw of up to 60 studs, and Park becomes reachable after a few minutes of reps or with a Rubber ball.
- `TrainMult` comes from training upgrades sold at the Yard/Training shop. These are cash sinks that scale ×1.5 per level (proposed).
- The first training purchase is part of the FTUE (section 19).
- Anti-autofarm: see section 21.4.

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

Balls, training upgrades, extra yard slots (geometric price), cosmetics (Bones only) and timed boosts (cash versions of Sticky Ball and Lucky Biscuit priced in $, proposed, so non-payers have access too).

### 13.4 Second currency: Bones

Bones are earned only from squirrel events, the daily walk and Kennel Book milestones. They are spent only on cosmetics (collars, hats, yard decor and pad trails), so they never buy power.

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

You claim it once per UTC day at the plaza's walk sign (`ClaimDailyWalk`). The reward is a cash bonus (proposed: 10 minutes of current income, minimum $100), some Bones, and **one free premium throw**: the next throw counts as having a Golden-ball luck shift plus Sticky Ball for that throw. `LastDailyWalk` stores the UTC day number. `EventState{Kind="DailyWalk"}` lights the sign when it is available.

### 14.3 Squirrel event

- Every **15 min** a squirrel spawns and runs the `SquirrelPath` waypoints (by `Order`) through the plaza for about 45 s. `EventState{Kind="Squirrel"}` carries `EndsAt`.
- The first player to touch it, checked by server distance, wins. One of the winner's dogs "chases it down" in a short world beat and **drops Bones** (proposed 25 + 5 per player in the server).
- Everyone else who was in the plaza during the event gets a small consolation (proposed 3 Bones), which rewards showing up.

### 14.4 Offline earnings

On join, `min(now - lastSeen, 2 h) × current $/s` (proposed 100% rate; **[tunable: Config/Timers.luau → OfflineCapSeconds / OfflineRate]**). It is shown in a "While you were away" toast. Puppy growth also continues offline, uncapped.

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

- **Slots:** a yard starts with **10 slots** (`SlotCount`). More can be bought at the Yard shop stand for cash at geometric prices (proposed), and the Extra Slots gamepass adds slots too. A full yard means a new catch prompts "Yard full: Sell a dog or buy a slot". In the meantime the new dog is held in the kennel and does not earn until a slot is freed. It is never lost.
- **Render cap:** at most **12 dogs roam** the yard (`Layout.Yards.MaxRoamingDogs`), one per `DogSpot` (SpotIndex 1-12). The player chooses which via `DogAction(Display)`; by default the 12 with the highest $/s are shown. The rest live in the **kennel building**, whose `KennelSign.CountLabel` shows "Kennel: N". Kennelled dogs still earn. This cap exists for performance only.
- **Dupes:** if you catch a DogId+Variant you already own, it **auto-sells** for `SellValue` (proposed: 120 s of its adult income) unless you set **Keep** for that rarity (Settings: Keep dupes of Rare+ etc.) or press Keep on the end card. It is still recorded in the book. `DogAction(Sell)` sells a dog manually at the same price.
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
- Cross-server uses `MessagingService` topic `FetchLegends_Broadcast` (proposed). It is throttled to stay well under the MessagingService publish limits: at most one publish per server per 2 s, and excess is queued and dropped after 30 s.
- Spectators see every other player's throw as a **park-view banner** (section 20.5), so the server feels alive.
- The plaza `Leaderboard` (SurfaceGui `List`) ranks players in the server by total $/s, with optional rarest catch.

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
| 0:00 | Spawn at `PlazaSpawn`. The camera pans down the stem to show the far zones, then back to the player. Arrow to your pad. | The yard is auto-assigned and the YardSign shows your name. |
| 0:10 | **Tutorial throw:** "Hold … release in the green!" The meter slows to half speed for this throw only, client and server alike (`IsTutorial`). | Server forces Backyard, a Common and **a guaranteed catch**. |
| 0:20 | **Cutscene** (Common length, ~2 s) → end card "+$1/s". | It cannot be skipped this first time. |
| 0:30 | Guide arrow to your yard. The puppy appears at a DogSpot, a "+$" floater appears, and a tooltip explains puppy → adult (Common: 5 min). | |
| 0:50 | "Throw again!" Second throw with normal odds and normal meter. The catch chance line on the HUD is highlighted. | |
| 1:20 | Cash ≥ the first training upgrade price (seeded starter cash $50, proposed). Arrow to the PullUpBar → **first training purchase** → ThrowPower increases and the reach line updates. | |
| 1:50 | Tooltips for the odds panel, Lucky Streak and Kennel Book, then `TutorialDone = true`. | Each tooltip is shown once. |

---

## 20. CUTSCENE CONTRACT

> **The cutscene is deliberately a placeholder in v1.** The user will design the real one later. Gameplay code may only talk to it through this contract. Lives in `src/shared/Cutscene/**` (contract + placeholder implementation), owned by the client workstream.

### 20.1 Inputs

```lua
Cutscene.Play(result: ThrowResult, opts: { IsThrower: boolean, IsSpectator: boolean }): Handle
-- Handle: { Finished: RBXScriptSignal-like (fires once), Skip: () -> (), CanSkip: () -> boolean }
```

`ThrowResult` (from `Remotes.luau`): `ThrowId, ThrowerUserId, PadIndex, Distance, ZoneId, DogId, Rarity, Variant?, Caught, CatchChance, Boosts, LuckyStreakTriggered, WhistleOwned, WhistleCount, IsTutorial`.

The cutscene **only displays**. It never rolls, never changes state and never decides the outcome. When the thrower's cutscene finishes, the client fires `CutsceneFinished(throwId)`. The server does not wait on it to save anything; it only uses it to unlock the next throw early. Its own timeout is the rarity length + 5 s.

### 20.2 Required beats (in order)

1. **Suspense:** the ball flies and lands, with distance and zone callouts. The rarity is **not yet known** to the viewer. Optional teaser (rarity-coloured light leak) is TBD.
2. **Reveal dog + rarity:** the dog rig (built via `DogFactory`) appears with its name and a rarity banner in the rarity colour.
3. **Reveal variant badge**, if there is one. `VariantFX` applies to the rig.
4. **Catch beat**, which branches:
   - *Caught:* jump → catch → tail wag (Lucky-Streak flourish if `LuckyStreakTriggered`, treat toss if a Treat Pocket saved it).
   - *Missed:* fumble → runs off toward the plaza.
5. **End card:** dog, name, rarity colour, variant badge and **multiplied $/s** (adult value, with "puppy: 20% for now" subtext). On a miss: "Ran off!" plus the Lucky Streak meter, plus the whistle prompt if `WhistleOwned` ("Use Golden Whistle? (N left)").

### 20.3 Timing per rarity (target total length; **[tunable: cutscene config]**)

| Rarity | Total length | Suspense share |
|--------|--------------|----------------|
| Common | ~2 s | minimal |
| Uncommon | ~3 s | short |
| Rare | ~5 s | |
| Epic | ~8 s | |
| Legendary | ~11 s | |
| Mythic | ~15 s | long |

### 20.4 Skippability

- **Commons:** skippable from the **4th Common cutscene onward**, so the first 3 Commons always play. The count is kept per player.
- Uncommon and Rare: skippable (proposed; TBD with the user).
- **Epic, Legendary, Mythic: never skippable.**
- Skipping jumps straight to the end card. It never skips the whistle prompt.

### 20.5 Spectator version

Other players get a **camera-less popup / park-view banner**: a small card near the top of the screen showing "[Player] threw 812 studs → Forest", then the rarity colour, then dog and variant, then ✓ caught or ✗ ran off. It runs at about 50% of the thrower's length and never takes the camera or blocks input. Epic+ banners are larger.

### 20.6 Debug toggle

`Config/Game.luau → CutsceneTestMode = true` adds a HUD button that plays random fake outcomes locally: random zone, dog, rarity and variant, caught or missed, thrower or spectator. Must be **false** in production. The server ignores it.

### 20.7 Open questions for the user (TBD)

- **TBD-1** Camera style: follow the ball, cut to a fixed field camera, or a stylised "TV replay"?
- **TBD-2** Should the suspense beat tease the rarity (light colour, sound) or stay neutral until the reveal?
- **TBD-3** Does the dog run *to the player* on the pad, or does the reveal happen at the landing spot?
- **TBD-4** Music and SFX direction per rarity.
- **TBD-5** Uncommon/Rare skip rules.
- **TBD-6** Should Mythics get per-dog bespoke beats (wings unfurl, extra heads bark)?
- **TBD-7** Spectator banner: also a mini 3-D viewport of the dog?
- **TBD-8** Where the whistle prompt lives: in the end card, or as a separate toast after it?

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

**Server (`src/server/**`)**
- `DataService`: load/save, session lock, autosave.
- `YardService`: assign yards and pads, dog spots, kennel count, trophy.
- `ThrowService`: charge timing, meter, distance, zone.
- `RollService`: tier, dog, variant, catch, Treat Pocket, Lucky Streak.
- `EconomyService`: income tick, offline, sell.
- `TrainingService`, `ShopService` / `ProductService` (`ProcessReceipt`), `BoostService`.
- `TimerService`: growth, daily walk.
- `EventService`: squirrel, runaway dogs.
- `BroadcastService`: server + MessagingService.
- `BookService`, `LeaderboardService`.
- `World/**`: the world builder that creates the tagged parts (D workstream).

**Shared**
- `Config/*`: Layout, Zones, Rarities, Game, Balls, Training, Shop, Timers, Products, WorldTheme.
- `Data/Dogs.luau`: generated roster.
- `Dog/`: `DogFactory`, `BodyTypes`, `VariantFX`.
- `Cutscene/`: contract + placeholder.
- `Util/`: number formatting, RNG, rate limiter, signal.
- `Remotes.luau`.

**Client (`src/client/**`)**
- HUD: cash, $/s, Bones, ThrowPower, reach + catch line, Lucky Streak, boost chips, odds panel, shop, Kennel Book, settings.
- Throw meter, cutscene player, spectator banners, broadcast ticker, yard dog renderer (via `DogFactory`), FTUE guide.

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

- Every outcome is decided on the server: distance, zone, dog, variant, catch, income, purchases and timers.
- The client receives state through `RequestState` (snapshot) and `StateUpdate` (full snapshot after any change; can be optimised to deltas later).
- The client may predict UI only, such as the meter animation.
- The RNG is `Random.new()` per server. Seeds are never exposed.
- Every remote validates argument types, enum values (ballId, stationId, itemId, action), ownership (dogUid belongs to the caller) and context (on own pad, in range of the station or shop stand, using `ShopStand`/`TrainingStation` positions).

### 21.4 Rate limits and anti-autofarm (proposed; `src/shared/Util` RateLimiter, values in Config/Game.luau)

| Remote | Limit |
|--------|-------|
| ChargeBegin / ChargeRelease | 1 throw in flight; next throw allowed after the cutscene finishes or times out; hard min 2 s between throws |
| Train | per-station cooldown (0.5–1 s); max 3 req/s |
| ShopPurchase, DogAction, UseWhistle, Claim* | 5 req/s, token bucket |
| EquipBall | 2 req/s |
| RequestState | 1 per 5 s |

Anti-autofarm measures:
- Throws need physical presence on your own pad.
- Release timing is human-scale. If the release-timing variance is near zero over 50 throws (a perfectly periodic macro), soft-flag it and add meter jitter for that player (proposed).
- Training reps stop crediting after **15 min with no movement or camera input** (AFK).
- Sprint laps are checked with server-validated checkpoints and a minimum lap time.
- Income itself is idle by design, so autofarming the throw is the only thing worth stopping.
- Every rejection is counted. Repeated violations are logged (analytics) but never auto-banned in v1.

---

## 22. Data storage

- **DataStore:** `FetchLegends_Player_v1`, key `u_<UserId>`, with session locking: a lock field with JobId and timestamp, taken over if stale for more than 10 min. The ProfileService pattern is implemented in-house with no external dependency.
- **Schema** = `PlayerState` (see `Remotes.luau`) + `LastSeen`, `CommonCutscenesSeen`, `Settings` (KeepDupes per rarity, TreatPocket mode), `Titles`, `Version` (for migrations).
- **Dogs:** an array of `{Uid, DogId, Variant?, BornAt, GrownAt, Displayed}`. Uid is a GUID. Store `DogId`, never computed income, so tuning income re-prices everyone automatically.
- **Book:** `{[DogId] = {Variants}}`. That is at most 720 keys plus variant lists, comfortably under the 4 MB key limit.
- **Saves** happen on autosave every 60 s, on leave and on `BindToClose`, with retry and exponential backoff. A save right after Legendary+ catches and any Robux purchase is proposed.
- **Receipts:** `ProcessReceipt` records `PurchaseId` in the profile's `Receipts` (last 100) before granting, and returns `PurchaseGranted` only after a successful save. This makes grants idempotent.
- **Leaderboards (global, optional v1.1):** OrderedDataStore for total caught and best $/s.
- Studio: `CutsceneTestMode` and a `Game.luau → UseMockData` flag (proposed) skip DataStores when API access is off.

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
| R6 | Cutscene is a placeholder and might get coupled to gameplay | A strict contract (section 20). The server never waits on the cutscene to save. |
| R7 | MessagingService limits during a burst of Legendaries | Throttle and queue (section 17); drop stale items. |
| R8 | "Max players = 6" forgotten at publish | Pre-publish checklist item: Studio Game Settings → Max Players = 6. The server also handles more than 6 gracefully (extra players get no yard and see a "server full" notice and teleport). |
| R9 | Form count mismatch: the brief says 1,422 forms, but the 53C/2M Meadow gives 27 non-Commons, so 720 + 3 × 235 = **1,425** | The roster generator (`tools/roster.py`) is authoritative. Variant badges are computed from data, not hard-coded. |
| R10 | Throw macros and autoclickers on training | Section 21.4. Since there is no rebirth, idle income is the intended AFK reward, which reduces the incentive to cheat. |
| R11 | DataStore failure losing a Legendary catch | Session lock, save after Legendary+ catch, retry/backoff, never grant from a failed load (kick and retry instead). |

---

## 25. Appendix: config file index

| File | Owns | Owner workstream |
|------|------|------------------|
| `src/shared/Config/Layout.luau` | world coordinates, pads, yards, render cap | shared contract |
| `src/shared/Config/Zones.luau` | 9 zones, distance bands, BaseIncome, theme colours | shared contract |
| `src/shared/Config/Rarities.luau` | tier odds, catch, IncomeMult, PerZone, variants, LuckyStreakMisses | shared contract |
| `src/shared/Remotes.luau` | remote names + payload shapes | shared contract |
| `src/shared/Config/Game.luau` | Name, meter/quality bands, luck formula & caps, rate limits, CutsceneTestMode | C1 server |
| `src/shared/Config/Balls.luau` | ball RangeMult, luck shift, price | C1 server |
| `src/shared/Config/Training.luau` | stations, gains, cooldowns, start ThrowPower, upgrades | C1 server |
| `src/shared/Config/Shop.luau` | in-game shop items, prices, boost effects, slot prices | C1 server |
| `src/shared/Config/Timers.luau` | growth times, daily walk, squirrel cadence, runaway seconds, offline cap | C1 server |
| `src/shared/Config/Products.luau` | gamepass & dev product IDs → effects | C1 server |
| `src/shared/Config/WorldTheme.luau` | materials and colours for the world builder | D world |
| `src/shared/Data/Dogs.luau` | the 720-dog roster (generated) | A roster |
