# QA: everything functions as intended

Integration audit after the six design changes (WalkSpeed/JumpPower, simplified plaza + consumable balls,
raised platform + ball arc, tall themed walls + haze, platform-only click/click meter, nine distinct zones).
It replaces the earlier pad-era audit, whose client files (ThrowController, ShopController, ...) no longer exist.
Checked by reading the code end to end plus the offline checks listed in README.md "Checks".

Legend: **PASS** = verified · **FIXED** = fixed in this pass · **OPEN** = known gap.

## 1. Static integrity

| Item | Result | Notes |
|---|---|---|
| Rojo mapping | PASS | shared -> `ReplicatedStorage.Shared`, server -> `ServerScriptService.Server`, client -> `StarterPlayer.StarterPlayerScripts.Client`. |
| Every `require` resolves | PASS | Every `WaitForChild`/`FindFirstChild` name in a `require(...)` matches a file or folder under `src/` (plus `PlayerModule` / Rojo roots). Dynamic requires (WorldBuilder steps, zone decorators, service ORDER) checked by hand. No requires of deleted modules. |
| Compiles | PASS | `luau.compile` (Lune `@lune/luau`) over all 105 `.luau` files in `src/` and `tools/`: 0 errors. |
| No stale names | PASS | No PadsX / PadSize / RequireOnPad / PadRadius / `Leaderboard` tag / PullUpBar / ThrowingMachine / Sprint station references in `src/` or `tools/`. |

## 2. Remotes (`src/shared/Remotes.luau`)

| Remote | Server | Client | Result |
|---|---|---|---|
| ChargeBegin / ChargeRelease | ThrowService: limiter, on platform, queue pos 1 + turn holder, one throw per turn, release floor | UI/init (HUD click / tap / Space / R2) | PASS |
| ThrowResult | ThrowService (all clients; LaunchPos / LandPos / FlightTime / BallId / BallsLeft) | Cutscene (init/Director), BallFlight.client -> Cutscene/Spectator, UI/init (spectator banner) | PASS |
| CutsceneFinished | ThrowService (EarliestFinish = 0.9 x Timeline.EarliestEnd, timeout = Timers.Cutscene from Config/Cutscene) | ui:FinishThrow (Cutscene Director / Reveal close) | PASS |
| UseWhistle | ThrowService | Reveal card (UI/init) | PASS |
| RequestState / StateUpdate | DataService | UI/init -> State | PASS |
| ShopPurchase / EquipBall | ShopService (consumable counts, refuses equip at 0) | Shop screen | PASS |
| Train | TrainingService ("Main", range) | none: the station's ProximityPrompt is the client path | PASS (by design) |
| DogAction | DogService | Dogs screen, Reveal Keep, **Settings (TreatPocketMode / KeepDupes)** | FIXED: Settings looked for a `SetSetting` remote that never existed; it now uses DogAction `SetTreatPocketMode` / `SetKeepDupes`, and State mirrors `PlayerState.Settings`. |
| ClaimDailyWalk | EventService | **HUD "Claim daily walk" banner** | FIXED: the UI kit had no caller (the claim was lost with the old controllers). |
| ClaimBookReward | BookService | Book screen | PASS |
| Broadcast / EventState | BroadcastService, EventService | HUD feed / banner | PASS |

## 3. Tags and attributes

World creates (counts from `tools/worldcheck/run.luau`): YardPlot 6, YardSign 6, DogSpot 72, KennelSign 6,
TrophySpot 6, ThrowPad 1, QueueSpot 5 (`Order` 1-5), TrainingStation 1 (`StationId` "Main"), ShopStand 1
(`ShopId` "Balls"), PlazaSpawn 2, RunawayArea 1, SquirrelPath 8 (`Order`), ZoneBand 9, DistanceMarker 62.
Consumers: TrainingService ("Main"), WorldController (ShopStand -> Balls tab), EventService (RunawayArea,
SquirrelPath by Order), DogService / BookService (yard tags). ThrowService reads `Layout.Platform` only and
sets `OnPlatform` / `ThrowQueuePos`; the HUD reads exactly those. **PASS**

## 4. Flow traces

| # | Flow | Result |
|---|---|---|
| 1 | Join -> data load + migrate -> yard assigned -> CharacterService WalkSpeed 32 / JumpPower 60 -> spawn on the plaza (plateau, Y 40) | PASS |
| 2 | Walk onto the flush deck -> OnPlatform -> queue (ThrowQueue) -> pos 1 moved to the throw spot -> HUD "Click to throw" | PASS |
| 3 | Click -> ChargeBegin -> vertical meter 0-100 -> click -> ChargeRelease -> server Meter.Evaluate -> distance -> consumable ball used up (Tennis at 0, notice) -> roll -> commit -> ThrowResult | PASS |
| 4 | Ball arc 44 -> 0 on `BallFlight.ForThrow(LaunchPos, LandPos)` for everyone; thrower cutscene camera follows the same arc, waits FlightTime, draws no ball of its own | FIXED (the cutscene used to spawn a second ball) |
| 5 | Cutscene -> Reveal card -> FinishThrow + CutsceneFinished -> turn ends after 2 s -> thrower to the back of the line | PASS |
| 6 | Caught dog -> DogService.AddDog -> yard display / kennel; miss -> runaway in the plaza, whistle | PASS |
| 7 | Shop panel: buy `Ball:Glow` -> count +1 and equipped -> HUD chip "x1" -> throw -> count 0 -> EquippedBall = Tennis | PASS |
| 8 | Training: prompt "Train" at the one station -> 0.5 s cooldown, power cap per training level; upgrades in the Yard tab | PASS |
| 9 | Old save (v1, `Balls = {[id] = true}`) -> migration to v2: owned balls become 0 throws, Tennis equipped | PASS (see OPEN) |
| 10 | Lighting.Apply (server only) leaves the client's `ZoneAmbienceCC` alone | FIXED (it adopted any ColorCorrectionEffect by class) |

## 5. Open / needs a Studio playtest

- OPEN: v1 players who bought permanent balls lose them in the v2 migration (by design: no refund/compensation).
- Feel of the flush deck at the cliff edge: edge wall, railing colliders, queue teleports.
- Click/click meter under real latency; prompt visibility on attribute changes; touch input near the jump button.
- Cutscene chase camera along the arc (long throws fly ~2 s with a high apex); camera restore on every branch.
- ZoneAmbience tweens and the Atmosphere haze over 3,200 studs; wall silhouettes; StreamingEnabled.
- Robux ids are 0 placeholders; DataStore session lock and BindToClose need a published place.
