# Split the Ocean for Eggs

An original Roblox egg-collecting idler. Walk up to the ocean, hold click with your **Sea Staff** to charge, and release
to part the sea. Your **Strength** decides how deep the corridor goes, and your **Luck** decides how many eggs are down
there and how rare they are. The walls of water start closing the moment the sea opens: grab an egg and get out before
they meet, or you're thrown back onto the beach without it. Back on land the egg goes into your inventory; place it anywhere in your plot and it hatches
into a pixel animal that earns money. The rarer the animal, the bigger it is.

Only you see your parted sea and your eggs. Everyone else sees you walk into the closed ocean.

The full design is in [`docs/DESIGN.md`](docs/DESIGN.md).

## Run it in Studio

1. Install the tools listed in `rokit.toml` (`rokit install`), or install [Rojo](https://rojo.space) 7.4 yourself.
2. In this folder run:
   ```bash
   rojo serve
   ```
3. In Roblox Studio, open a new **Baseplate** place, open the Rojo plugin and click **Connect**.
4. Press **Play**. The whole map (beaches, ocean basin, pens, decor) is built by code at startup, so there are no
   models to import.

To build a place file instead:

```bash
rojo build -o SplitTheOcean.rbxl
```

Or, without Rojo, with [Lune](https://lune-org.github.io/docs):

```bash
lune run tools/build-place.luau
```

That writes `SplitTheOceanForEggs_build<N>.rbxl`, where N is `Config.Build` in `src/shared/Config.luau`. The same
number is shown in small print at the top of the screen in game. Bump it whenever you hand someone a new file.

### Server size

There are 5 bases per server, so set **Game Settings → Places → Max Players** to **5** before publishing. A 6th player
can still play and earn money but has no base to place eggs or show animals in.

### Saving in Studio

Progress saves with DataStores. In Studio, turn on **Game Settings → Security → Enable Studio Access to API
Services**, otherwise the game runs normally but won't save (it tells you so in-game).

### Robux items

Game passes and developer products are listed in `src/shared/Config.luau` (`Config.Passes`, `Config.Products`) with
`id = 0`. While an ID is `0`:

- **In Studio** buying it grants it for free, so you can test every item.
- **In a live server** it says the item isn't set up yet.

Create the passes and products in the Creator Dashboard and paste their IDs into `Config.luau` before publishing.

## Project layout

```
src/shared/      ReplicatedStorage.Shared
  Config.luau      every tunable: eggs, animals, rarities, costs, rewards, Robux items
  Formulas.luau    split size / timing, egg rolls, luck, prices (shared by server + client)
  Voxel.luau       builds the pixel eggs, animals, staff, barbells and palm trees out of Parts
  Format.luau      1.1K / 2.5M number and mm:ss time formatting
  Remotes.luau     creates / finds every RemoteEvent and RemoteFunction
  Signal.luau      tiny local event helper
src/server/      ServerScriptService.Server
  init.server.luau boot order + the validated UI action router
  World.luau       map: one shore, bases, walls, seabed, headlands, decor, lighting
  Data.luau        DataStore save/load, session state, state sync to the client
  Split.luau       authoritative sea parting: corridor, closing walls, eggs, grabs, carrying
  Pens.luau        bases: slots, incubation, hatching, wandering animals, income, offline cash
  Training.luau    the Strength pad (automatic reps) and weight upgrades
  Shop.luau        Luck upgrades, game passes, developer products
  Rewards.luau     playtime gifts, daily streak, Index rewards
  Leaderboards.luau the three global leaderboards on the back wall
src/client/      StarterPlayerScripts.Client
  init.client.luau boot
  State.luau       client copy of player state + server actions
  Ocean.luau       draws the ocean, the parting cutscene, the closing corridor, your eggs; charging
  Depths.luau      the inside of a parted sea: zone lines, kelp, mist, fish, falling water
  Placement.luau   picking a spot in your plot for an egg from the inventory
  Ragdoll.luau     goes limp and flies back to shore when the sea catches you
  Poses.luau       limb animation for the staff cast and barbell reps (R6 and R15)
  Guide.luau       new-player objective text and the trail of arrows on the ground
  PenAnimals.luau  hops the animals along the walks the server publishes
  ui/              HUD and windows (Pets, Eggs, Sell, Buy, Index, Shop, Gifts, Daily, hatch cutscene)
  ui/Layout.luau   where every HUD element sits, as data
  ui/Weights.luau  the weights stall's barbell menu
tests/
  formulas.spec.luau  tests for the balance math and number formatting
  game.spec.luau      a full playthrough of the real server + client code
  layout.spec.luau    proves no HUD elements overlap on ten screen sizes
  pacing.sim.luau     a bot that plays the economy and reports how long each tier takes
  harness/Roblox.luau the fake Roblox engine the playthrough runs on
```

## Tests

The tests run outside Studio with [Lune](https://lune-org.github.io/docs) (`cargo install lune`, or add it with
Rokit). From the repo root:

```bash
lune run tests/formulas.spec.luau
```

```bash
lune run tests/game.spec.luau
```

```bash
lune run tests/layout.spec.luau
```

```bash
lune run tests/pacing.sim.luau
```

`pacing.sim.luau` is not a pass/fail test: a simple bot plays the economy and prints how long each egg tier took to
reach and how Strength, depth, Luck and income grow over 8 hours.

`game.spec.luau` boots the real server and client scripts on a small fake engine. Lune supplies real Roblox Instances,
so a wrong property name, a wrong value type or an enum item that doesn't exist fails the test the same way it would
error in Studio. The harness adds events, a virtual clock, remotes, tweens and in-memory DataStores. The playthrough
joins a player, parts the sea (cutscene included), grabs an egg, banks it on land and places it in the plot, gets caught by the
closing walls, hatches, earns, trains, buys upgrades, claims rewards, tests every shop item, manages the inventory,
fills a server, checks the leaderboards, saves, and rejoins two hours later.

`layout.spec.luau` checks the HUD layout data for overlaps, including with Roblox's own UI, on desktop, tablet and phone
screens.

The fake engine does not model Roblox's script security or physics. It cannot check what things look like or how the physics feels, so play it in Studio too.

## Tuning

Almost everything is in `src/shared/Config.luau`:

- `Config.Split` controls how Strength turns into depth and width, how long the walls take to close, the egg count,
  and how long a full charge takes.
- `Config.Casts` sets the three casts (basic split, Super Split, Poseidon's Wrath): chance, Luck multiplier, cutscene
  length and wall height.
- `Config.SizeByTier` sets how much bigger each rarity tier's animals are.
- `Config.RarityWeights` sets the base rarity odds, and `Config.Zones` the luck zones by depth (name, luck
  multiplier, color). Luck and the zone's luck shift the odds toward rarer eggs.
- `Config.Eggs` and `Config.Animals` set hatch times, incomes, colours and the voxel template for each animal.
- `Config.Weights`, `Config.Luck` and `Config.Base` set the upgrade costs.

After changing numbers, run the tests. `formulas.spec.luau` also prints a table of how deep and how long a full-charge
split is at different Strength levels.
