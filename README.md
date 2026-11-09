# Split the Ocean for Eggs

An original Roblox egg-collecting idler. Walk up to the ocean, hold click with your **Sea Staff** to charge, and release
to part the sea. Your **Strength** decides how deep the corridor goes and how long it stays open, and your **Luck**
decides how many eggs are down there and how rare they are. Grab an egg and run: the sea rolls back in from the far end,
and if it catches you, you lose the egg. Make it back to the beach and the egg goes to your pen, where it hatches into a
pixel animal that earns money.

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
  World.luau       map: ocean basin, ramps, beaches, cliffs, walls, decor, lighting
  Data.luau        DataStore save/load, session state, state sync to the client
  Split.luau       authoritative sea parting: corridor, eggs, grabs, sweep-back, banking
  Pens.luau        bases: slots, incubation, hatching, wandering animals, income, offline cash
  Training.luau    the Strength pad and weight upgrades
  Shop.luau        Luck upgrades, game passes, developer products
  Rewards.luau     playtime gifts, daily streak, Index rewards
src/client/      StarterPlayerScripts.Client
  init.client.luau boot
  State.luau       client copy of player state + server actions
  Ocean.luau       draws the ocean, the parted corridor, your eggs; hold-to-charge input
  ui/              HUD and windows (Pets, Eggs, Sell, Buy, Index, Shop, Gifts, Daily, hatch cutscene)
tests/
  formulas.spec.luau  tests for Config / Formulas / Format (run with `lune run tests/formulas.spec.luau`)
```

## Tuning

Almost everything is in `src/shared/Config.luau`:

- `Config.Split` controls how strength turns into depth and open time, the egg count, and how long a full charge takes.
- `Config.Ocean.CloseSpeed` sets how fast the sea rolls back (studs/s; players walk at 16).
- `Config.RarityWeights` sets the base rarity odds. Depth and Luck both shift them toward rarer eggs.
- `Config.Eggs` and `Config.Animals` set hatch times, incomes, colours and the voxel template for each animal.
- `Config.Weights`, `Config.Luck` and `Config.Base` set the upgrade costs.

After changing numbers, run the tests. They also print a table of how deep and how long a full-charge split is at
different Strength levels.
