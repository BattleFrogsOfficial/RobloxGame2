# Throw a Ball for Dogs

An original Roblox throw-and-collect idler. Hold to charge, release on the meter's sweet spot, and the ball
lands in one of 9 zones down a long fetch field. A dog from that zone chases it. If it catches the ball, it
joins your yard and earns $/s. If it fumbles, it runs off into the plaza. The full design is in
[`docs/DESIGN.md`](docs/DESIGN.md).

## Syncing with Rojo

The project uses a standard [Rojo](https://rojo.space) layout, defined in `default.project.json`:

| Folder        | Roblox location                                   |
|---------------|---------------------------------------------------|
| `src/shared`  | `ReplicatedStorage.Shared`                        |
| `src/server`  | `ServerScriptService.Server`                      |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`       |

```sh
rojo serve                      # then click "Connect" in the Rojo Studio plugin
rojo build -o ThrowABallForDogs.rbxl # or build a place file
```

Studio setup:
- Game Settings → Places → **Max Players = 6**. There is one yard and one throw pad per player.
- Game Settings → Security → **Enable Studio Access to API Services** if you want real DataStores. Without it,
  the server falls back to an in-memory store automatically. `Config/Game.luau → UseMockData` forces that.
- `Config/Game.luau → CutsceneTestMode = true` adds the client debug button that plays random cutscene outcomes.
- Robux ids in `Config/Products.luau` are `0` placeholders. Purchases of an id of 0 are refused with "Not available yet".

Lint with selene (`selene.toml`, `std = "roblox"`).

## Project structure

```
default.project.json
docs/DESIGN.md                 design doc (agent B)
data/**, tools/roster.py       dog roster source + generator (agent A)
src/shared/
  Remotes.luau                 network contract (remote names + payloads)
  Config/                      Layout, Zones, Rarities (shared contracts)
                               Game, Balls, Training, Shop, Timers, Products (server/balance)
                               WorldTheme (world)
  Data/Dogs.luau               GENERATED roster (720 dogs) - do not hand edit
  Util/                        Rng, RateLimiter, Signal, FormatNumber, Table,
                               Meter (throw meter maths), Odds (tier/catch/variant odds),
                               DogCatalog (roster index), PlayerStats (derived HUD numbers)
  Dog/                         DogFactory rig builder, BodyTypes, VariantFX (client agent)
  Cutscene/                    cutscene contract + placeholder (client agent)
src/server/
  Main.server.luau             bootstrap: Remotes.Init -> World.WorldBuilder.Build() -> services
  World/                       world builder (agent D)
  Services/                    DataService, BroadcastService, DogService, BookService, EventService,
                               ThrowService, RollService (pure), ShopService, TrainingService,
                               LeaderboardService
  Tests/RollService.spec.luau  roll distribution checks
src/client/                    HUD, meter, cutscene player, shop, book... (client agent)
```

### Agent areas

| Area | Owner | Paths |
|------|-------|-------|
| A roster | roster agent | `data/**`, `tools/roster.py`, `src/shared/Data/Dogs.luau` |
| B docs | design agent | `docs/DESIGN.md` |
| C1 server | server agent | `default.project.json`, `src/server/**` (except `World/`), `src/shared/Config/{Game,Balls,Training,Shop,Timers,Products}.luau`, `src/shared/Util/**` |
| C2 client | client agent | `src/client/**`, `src/shared/Dog/**`, `src/shared/Cutscene/**` |
| D world | world agent | `src/server/World/**`, `src/shared/Config/WorldTheme.luau` |

## Server notes for the client and world agents

**Authority.** The client only sends `ChargeBegin()` and `ChargeRelease()`. The server times the hold with
`os.clock()`, evaluates `Util/Meter` (a triangle wave with period 1.6 s, half speed on the tutorial throw),
and decides the distance, zone, dog, variant and catch. It commits the result to data before it fires
`ThrowResult` to every client. The player must stand within `Game.Throw.PadRadius` of their own `ThrowPad`.

**Live values.** Player attributes are updated every second: `Cash`, `Bones`, `ThrowPower`, `IncomePerSec`.
Others are set when they change: `YardIndex`, `PadIndex`, `Title`, `PaidRandomItemsRestricted`, `LastTrainGain`.
`StateUpdate` sends a full snapshot when something changes and every 10 s. The snapshot adds
`Computed = PlayerStats.Compute(...)`, which holds luck and its sources, catch chances per tier, live tier odds,
reach zone, prices and active boosts. It also adds `Passes` and `ServerLuckUntil`.

**Extra PlayerState fields** (beyond the shape in `Remotes.luau`): `Version`, `TutorialThrowDone`,
`TrainingLevel`, `PermanentLuck`, `PremiumThrows`, `Settings{KeepDupes, TreatPocketMode}`, `Cosmetics`,
`Titles`, `EquippedTitle`, `Trophies`, `VariantBadges`, `CommonCutscenesSeen`, `LastSeen`, `Stats`.
- Each dog record can also carry `Locked`, `Held` (the yard is full, so the dog waits without earning) and
  `PendingSale` (a dupe in its Keep window).
- `Book[DogId] = {Count, FirstAt, Variants = {"Gold", ...}}`.
- `BookRewards[ZoneId]["25"|"50"|"75"|"100"] = true`.

**Extra ThrowResult fields:** `ThrowerName`, `DogName`, `LuckyStreak`, `Quality`, `MeterPos`,
`Band` ("Perfect"/"Good"/"OK"/"Flub"), `BallId`, `StartPosition`, `LandingPosition`, `TreatPocketUsed`,
`PremiumThrow`, `Income` (adult $/s), `IncomeNow`, `DogUid`, `Status` ("Added"/"Held"/"PendingSale"/nil),
`CutsceneSeconds`, `CanSkip`, `ServerTime`.
- The thrower fires `CutsceneFinished(throwId)` when the cutscene ends. Otherwise the server times out after
  `CutsceneSeconds + Timers.CutscenePadding`.
- Non-skippable cutscenes cannot finish before 60% of their length.

**ShopPurchase item ids:** `Ball:<id>`, `Training`, `Slots`, `Boost:StickyBall|LuckyBiscuit`,
`Item:GoldenWhistle|TreatPocket`, `Cosmetic:<id>`, `Product:<key>[:<dogUid>]` (Robux, so `InstantGrow` takes a
puppy uid), `Pass:<key>`.

**DogAction actions:** `Keep`, `Sell`, `Display`, `Kennel` (from the contract), plus these extras:
- `Auto`: clears the display pin.
- `Lock`: toggles lock.
- `SetKeepDupes`: pass `"<Rarity>"` to toggle, or `"<Rarity>=true|false"`.
- `SetTreatPocketMode`: pass `"Always"|"EpicPlus"|"Off"`.

The second argument is the dog uid or the setting value.

`Keep` on a `PendingSale` dupe cancels the auto-sale. On any other dog it toggles `Locked`.

**Broadcast kinds:** `Catch`, `Miss`, `Recall`, `Squirrel`, `ServerLuck`, `Offline` (also carries `Amount`,
`Seconds`), and personal notices: `Notice`, `Hint`, `Training`, `Dupe`, `YardFull`, `AutoSell`, `Growth`, `Badge`,
`Purchase`.

**World tags read by the server:**

| Tag | What the server does with it |
|-----|------------------------------|
| `YardSign` | sets `OwnerLabel` |
| `DogSpot` | gets the dog models |
| `KennelSign` | sets `CountLabel` |
| `TrophySpot` | gets the trophy statues |
| `ThrowPad` | pad position |
| `TrainingStation` | gets a ProximityPrompt |
| `Leaderboard` | fills `List` |
| `RunawayArea` | where runaway dogs wander |
| `SquirrelPath` | squirrel route, by `Order` |

If any tag is missing, the server falls back to `Layout.luau` coordinates.

**Models the server creates:**
- `workspace.YardDogs.Yard_<i>`: dog models tagged `YardDog`, with attributes `OwnerUserId`, `DogUid`, `DogId`,
  `Rarity`, `Variant`, `IsPuppy`, `HomePosition`, `RoamRadius`. They are placed statically, and the client may
  animate their roaming.
- `workspace.WorldEvents`: runaway dogs (`RunawayDog` tag) and the squirrel.
- `workspace.YardTrophies`: trophy statues.
- Dog models come from `Shared.Dog.DogFactory.Build(def, {Variant, IsPuppy})` when that module exists, and from
  a block dog otherwise.

## Tests

From the Studio command bar while the game is running on the server:

```lua
require(game.ServerScriptService.Server.Tests["RollService.spec"])()
```

It checks the tier odds, luck shift and cap, zone renormalisation, the uniform dog pick, variant and catch
rates, the Lucky Streak (including the ~54% long-run Legendary rate), the tutorial guarantee, Treat Pocket
and seeded determinism.
