# QA — Concern 4: Everything functions as intended

Final integration audit (run last, after the overlap / HUD / balance passes). No Luau runtime, Rojo or
selene is available, so everything below was checked by reading code end to end, plus small Python
scripts (require-path resolver, block/bracket balance checker, module-member checker, roster counter).

Legend: **PASS** = verified by reading · **FIXED** = bug found and fixed in this pass · **OPEN** = known gap.

## 1. Static integrity

| Item | Result | Notes |
|---|---|---|
| Rojo mapping (`default.project.json`) | PASS | shared -> `ReplicatedStorage.Shared`, server -> `ServerScriptService.Server`, client -> `StarterPlayer.StarterPlayerScripts.Client`. |
| Every `require` path resolves | PASS | Script resolved every `script.Parent…`/`Shared:WaitForChild(…)` chain against the file tree; 0 missing. Dynamic requires (WorldBuilder steps, zone decorators, service ORDER lists, PlayerModule) checked by hand. |
| No cyclic requires | PASS | Server: Data/Broadcast/Roll are leaves; Dog -> Data,Broadcast; Book/Event/Shop/Leaderboard -> Data,Dog(,Broadcast); Throw -> all of those. Client: State is the leaf; Hud -> State; Notification -> Hud; Throw -> State,Hud; Whistle -> State,Notification; Cutscene -> Hud,Throw,Notification,Whistle. Acyclic. |
| Modules return what callers expect | PASS | Services/controllers return tables with `Start`; zone decorators return functions (Field calls `decorate(ctx)`); every `Alias.Member` reference resolves to a defined member (script check; only exported types left over). |
| Block / bracket balance | PASS | Heuristic tokenizer (handles strings, long comments, if-expressions) finds every `function/if/do/repeat` closed and every `()[]{}` balanced in all 80 `.luau` files. |
| Deprecated APIs (`wait`, `spawn`, `delay`, `tick`, `:connect`) | PASS | None; all `task.*`. No `:=`, `!=`, `++`. |
| Undeclared identifiers | PASS | Crude scan found only type names / annotated params (false positives). |
| Dogs.luau loads | PASS | 720 entries, 0 duplicate ids, 0 duplicate names. 8 zones 54/13/7/3/2/1, MythicMeadow 53/13/7/3/2/2. Module is the array + `All/ById/ByZone/ByZoneRarity/Vocab`; DogCatalog reads `result.All`. |
| Roster vocab handled by DogFactory | PASS | All 14 bodies, 53 patterns, 52 accessories, 4 vfx tiers, 15 unique parts used in data have handlers. Fallbacks: unknown body -> `BodyTypes.Default`, unknown pattern -> no overlay, unknown accessory -> magenta labelled block, unknown unique part -> skipped, bad hex -> default coat. DogService falls back to block dogs if DogFactory fails; DogCatalog falls back to a placeholder roster if Dogs.luau fails. |

## 2. Remotes (src/shared/Remotes.luau)

| Remote | Server handler (validation + rate limit) | Client user | Result |
|---|---|---|---|
| ChargeBegin | ThrowService: limiter, loaded, has pad, not charging/in flight, release->begin floor, on own pad | ThrowController.begin | PASS |
| ChargeRelease | ThrowService: limiter, timing from server clock only; auto-release after 6 s | ThrowController.Release | PASS |
| ThrowResult | fired once per throw to all clients | CutsceneController (thrower cutscene / spectator banner / ball flight) | PASS |
| CutsceneFinished | ThrowService: limiter, string id, owner, EarliestFinish | CutsceneController | FIXED (see 3.3) |
| UseWhistle | ThrowService: limiter, owner, missed, window, owns whistle | WhistlePrompt | PASS |
| RequestState | DataService: limiter, waits for load | StateController (retry/backoff) | PASS |
| StateUpdate | DataService.Push (coalesced per frame) | StateController | PASS |
| ShopPurchase | ShopService: limiter, string ≤100, kind dispatch, per-handler checks | ShopController, YardController (InstantGrow) | PASS |
| EquipBall | ShopService: limiter, owned ball | ShopController | PASS |
| Train | TrainingService: limiter, station id, range check | none (reps come from the server-side ProximityPrompt on each station) | PASS (by design; remote kept as an alternate path) |
| DogAction | DogService: limiter, action whitelist, arg ≤64 | YardController, CutsceneController (Keep), ShopController (TreatPocket mode) | PASS |
| ClaimDailyWalk | EventService: limiter, once per UTC day | NotificationController toast, ShopController | PASS |
| ClaimBookReward | BookService: limiter, zone + milestone whitelist, progress check, once | BookController | PASS |
| Broadcast | BroadcastService.Send/Notify, DogService offline | NotificationController (feed vs toast) | PASS |
| EventState | EventService (Squirrel / RunawayDog / DailyWalk), late joiners resynced | NotificationController, WhistlePrompt (hide on despawn) | PASS |

## 3. World tags contract

All 14 tags are created by `src/server/World` via `Props.Tag` with the contract attribute names/types:
YardPlot, YardSign (+SurfaceGui TextLabel `OwnerLabel`), DogSpot (YardIndex, SpotIndex), KennelSign (`CountLabel`),
TrophySpot, ThrowPad (PadIndex), TrainingStation (StationId), ShopStand (ShopId Balls/Boosts/Yard/Cosmetics),
Leaderboard (ScrollingFrame `List`), PlazaSpawn (SpawnLocation), RunawayArea, SquirrelPath (Order), ZoneBand (ZoneId),
DistanceMarker (Distance). Every consumer (DogService, BookService, ThrowService, EventService, TrainingService,
LeaderboardService, ThrowController, ShopController) reads those exact names and has a Layout fallback. **PASS**

## 4. Flow traces

| # | Flow | Result | Notes |
|---|---|---|---|
| 1 | Join -> load -> yard+pad -> sign -> HUD | PASS | DataService session lock + migrate/reconcile -> PlayerLoaded -> DogService assigns yard i (= pad i), sets `YardIndex/PadIndex` attributes, sign "Name's Yard $x/s", StateUpdate + live attributes drive the HUD. 7th player gets a notice (no yard). |
| 2 | Tutorial throw -> Common catch -> cutscene -> puppy -> income -> grows | PASS | Tutorial flag taken at ChargeBegin (both sides use half-speed meter), zone forced Backyard, tier forced Common, catch forced, no variant. Dog committed before ThrowResult, display refreshed at finish, 20 % income while puppy, incomeTick detects growth and rebuilds the model. |
| 3a | Timing -> zone -> roll | PASS | Distance = Power x RangeMult x quality(server elapsed) x scatter; tier (luck) -> uniform dog -> variant -> catch, all before ThrowResult. |
| 3b | Legendary miss: reveal before fumble, runaway 60 s, broadcasts | PASS | Cutscene beats Suspense -> RevealDog -> RevealVariant -> Catch(fumble) -> EndCard. `finish()` broadcasts "A LEGENDARY X ran off from Y" (server + MessagingService for Legendary+) and spawns the plaza runaway for 60 s; catches broadcast "X caught a LEGENDARY …". |
| 3c | Whistle prompt only if owned; recall | PASS | Prompt only when `Whistles > 0`, never a Robux prompt; recall adds the dog, records the Book, despawns the runaway, hides the prompt for everyone's EventState. |
| 3d | Treat Pocket second roll | PASS | One extra catch roll on a miss (mode Always / EpicPlus default / Off), consumes one pocket. |
| 3e | Lucky Streak | PASS | Streak counts Legendary+ misses only; at 2 the next Legendary+ is forced (chance shown 100 %, HUD pips turn "LUCKY!"); catch or whistle recall resets. |
| 3f | Throw cooldown after a skipped Common cutscene | FIXED | Client re-armed the THROW button 0.5 s after the cutscene, but the server floor is 2 s from release; skipping a Common cutscene let the client "charge" a throw the server silently ignored. Client now waits for max(release + 2.25 s, cutscene end + 0.5 s). (`ThrowController.SetCutsceneActive`) |
| 3g | Early CutsceneFinished | FIXED | A finish arriving before `EarliestFinish` (e.g. cutscene error) was dropped, blocking the next throw for cutLen + 8 s. The server now finishes at `EarliestFinish`. (`ThrowService` CutsceneFinished handler) |
| 4 | Shop: ball / training / slots / boost / item / cosmetic, insufficient cash | PASS | Each handler spends via `TrySpendCash` and returns "Need $X" on failure; timed boosts stack duration; dynamic prices match `Computed.Prices`. First training purchase ($50 = starting cash) ends the FTUE. |
| 4b | Robux receipt idempotency | PASS | Receipt id checked before grant, recorded after, saved before `PurchaseGranted`; failed save -> NotProcessedYet and the retry short-circuits on the stored receipt. Id 0 products/passes refused ("not available yet"); PolicyService restriction honoured. |
| 5 | Yard full / dupes / kennel / render cap | PASS | Over slots -> `Held` (no income, kennel); dupes -> `PendingSale`, Keep window toast, auto-sold by the income loop (settled on leave/rejoin); max 12 models (pinned first, then by $/s); kennel sign = total - roaming. |
| 6 | Squirrel / daily walk / offline cap | PASS | Squirrel every 15 min (first after 15 min), winner Bones + yard bone drop + consolation; daily walk once per UTC day (cash, Bones, premium throw); offline earnings `min(away, 2 h) x 50 %`, only if away ≥ 60 s. |
| 7 | Kennel Book milestones | PASS | 25/50/75/100 % of 80 base dogs (client and server agree: 20/40/60/80), cash -> +0.02 permanent luck -> trophy at TrophySpot -> title; one claim each. Variant badges per zone + all-Rainbows. |
| 8 | Leave -> save -> yard freed; BindToClose | FIXED | Leave: releasing callbacks (dupe settlement) -> save with lock release -> yard sign "Free Yard", models/trophies cleared. **Bug:** on shutdown `PlayerRemoving` and `BindToClose` raced — BindToClose skipped sessions already leaving and returned immediately, so those saves could be cut off; and both paths could run the release callbacks twice. BindToClose now also waits for in-flight leave saves (≤25 s) and each path skips work the other already did. (`DataService`) |
| 9 | CutsceneTestMode button | PASS | `Game.CutsceneTestMode = true` shows "Test Cutscene" in the Debug region; fake results (`IsTest`) play locally, never hit the server (no CutsceneFinished, Keep, or Whistle call). |
| 10 | Spectator banner | PASS | Non-throwers get a camera-less banner in the Messages stack (~50 % length, large for Epic+): throw -> rarity + dog + variant -> CAUGHT / RAN OFF. |

## 5. Changes in this pass

- `src/server/Services/DataService.luau` — BindToClose waits for in-flight PlayerRemoving saves and clears sessions it saved; PlayerRemoving skips callbacks/save already done by BindToClose; Book comment corrected (Variants is an array).
- `src/server/Services/ThrowService.luau` — early CutsceneFinished schedules the finish at EarliestFinish instead of being dropped.
- `src/client/Controllers/ThrowController.luau` — post-cutscene throw re-arm respects the server's release->ChargeBegin floor.

## 6. Open / notes

- OPEN: the `Train` remote has no client caller (training uses server ProximityPrompts); harmless, kept for a future "train" button.
- OPEN: if the server ignores a ChargeBegin (e.g. lag puts you just off the pad server-side), the client shows a charge and then falls back to Idle after 4 s with no message beyond the server's "Stand on your throw pad" hint.
- OPEN: Cosmetics are purchasable but not yet rendered (documented client TODO); global leaderboards are v1.1.
- OPEN: all Robux product/pass/badge ids are 0 placeholders.

## 7. Needs Studio playtest

1. Studio script analysis on every module (no luau-analyze here): confirm zero errors under `--!strict`.
2. Rojo sync produces the expected tree; `.md` files are ignored; `RollService.spec` runs from the command bar.
3. WorldBuilder completes without warnings; PartCount reasonable; players spawn on a PlazaSpawn (check the first player in Play Solo isn't spawned before the map exists).
4. With StreamingEnabled on: pad markers, shop stand prompts and yard dog animation still bind (they listen for tag-added signals / fall back to Layout).
5. DogFactory models: `Model:ScaleTo` on unparented models, welds hold after `PivotTo`, DogAnimator Motor6D animation on server-owned anchored-root rigs, VariantFX Rainbow cycling and Shadow eyes.
6. Meter feel: client needle vs server timing under real latency (perfect releases land in Perfect), tutorial half-speed meter.
7. Cutscene camera restore after each branch (catch / fumble / skip / error), HUD and controls re-enabled, queued second throw.
8. DataStore: session lock hand-off between servers, BindToClose saves on shutdown (published place), receipt retry path.
9. MessagingService cross-server broadcasts (published place only).
10. ProximityPrompt ranges on the thin training mats and shop counters; Sprint lap distance counting.
11. Squirrel movement/catch radius, runaway dog roaming inside the RunawayArea, bone drop visuals.
12. Leaderboard SurfaceGui readability, yard sign / kennel sign text, trophy placement on TrophySpot.
13. HUD at phone/tablet sizes with real CoreGui insets (layout validated offline in docs/qa/HUD.md).
