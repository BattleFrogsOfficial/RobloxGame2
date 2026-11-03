# QA: Nothing overlaps

> **Historical.** This overlap pass predates the plaza redesign: the six pads, the leaderboard board and the
> three training stations it mentions no longer exist (one raised platform with a ramp, one ball shop, one
> training station). The current checks are `python3 tools/world_bounds.py`, `lune run tools/worldcheck/run.luau`
> and `lune run tools/worldcheck/zones.luau`.

Final QA pass, concern 1. To re-run the checks: `python3 tools/world_bounds.py` (now 7,710 checks) and `python3 tools/roster.py check`.
Both pass.

## (a) World geometry

I read every World module (WorldBuilder, Outskirts, Yards, Street, Plaza, ThrowLine, Field, Boundaries, Props,
Zones/Kit and the 9 zone decorators) and compared them with what `world_bounds.py` models. The script reads its
constants from the Luau sources, so it should catch drift.

Already covered and passing: floors tile the T exactly (6 yards + hedge gaps = the 760-wide crossbar; street, plaza,
field and aprons all touch with no overlap). The 9 zone bands are contiguous from 60 to 3260 and sit inside the
field. There are 12 DogSpots per yard inside the fence, clear of the kennel (including its roof overhang), the
trophy, the trees and the gate path. Shops, stations, the leaderboard, spawns, track, lawn and benches don't
overlap. The pads are clear of the rope fence. Markers and arches stay out of the centre lane.

Added to the script:
- Yard gate opening clear of the gate pillars, fence end posts and sign posts. Sign posts don't touch the front fence.
- Dog roam reach (9.5 studs around each spot): no overlap between neighbours, and clear of the kennel, trophy,
  bushes and trees. It stays inside the fence.
- Street zebras sit inside the street. Title-arch pillars sit on the street/plaza seam, clear of the spawn mouth,
  the spawns, the track, the shops and the corner trees.
- Lawn bushes stay outside the runaway-dog roam rectangle (the lawn inset by 4). The 4 corners of the squirrel loop
  are on the track, and its segments are clear of every plaza prop.
- The server landing X is clamped into the lane. Markers and arch pillars are outside the landing lane. Arch parts
  are CanQuery=false.
- Per-zone decor: each Kit.Band/Apron call's worst-case footprint must be no larger than its margin, which keeps it
  off the lane edge, the field edge and the zone ends. The Kit must record each footprint so items from different
  calls can't overlap.

### Fixes made
| Issue | Fix |
|---|---|
| Server landing X was `padX ± 40` clamped to ±110, so balls and cutscene dogs landed in the decor bands (trees, crop patches, markers, arch pillars) | `ThrowService`: `landX = 0.5·padX + 0.5·U(±40)`, clamped to the lane (±56). Updated the comment in `Config/Game.luau` |
| Cutscene `groundAt` raycasts from Y=300, so a landing under a zone arch put the dog on top of the board | `Props.Arch` sets CanQuery=false on every arch part (visual only) |
| Separate `Kit.Band`/`Apron` calls only kept their own items apart, so trees could sit in doghouses, bales in crop patches, palms over umbrellas | `Kit.pick` keeps `ctx.Taken` (centre + footprint radius = margin). `Field` seeds `Taken = {}` per zone. Marker/arch avoidance now uses the footprint radius |
| Footprints larger than their margins: Park trees (into the lane), Beach palm fronds (6 studs over the lane), Forest/Snowy pines, logs, umbrellas, bales, Backyard flower beds (overlapping the lane fence), toys; on the apron, Snowy mountains (12 studs into the field, crossing zones), City towers (into the parapet), Forest pines, Park trees and pond rim, Farm silo (into the next zone) | Margins and spacing adjusted in each zone module; mountain scale capped at 1.3 |
| Yard gate pillars and fence end posts stuck 0.2–0.55 studs into the 18-stud gate | Pillar centre moved to `gw + 1.2`, and the fence now ends inside the pillar |
| Yard dogs roam a fixed 6 studs, so giant dogs (about 14 long) overlapped neighbours (rows are 20 apart) and the corner bushes | `DogService`: `RoamRadius = clamp(9.5 - halfFootprint, 1.5, 6)`. Yard bushes moved from ±48 to ±49 |
| Lawn corner bushes sat inside the runaway roam rectangle | Moved 2 studs in from the lawn rim |

Simulating the decor fill rate (Python RNG, 20 seeds) shows the call counts are nearly always met. The worst cases
were 2 of 4 Backyard apron houses, 4 of 6 Beach rocks and 6 of 7 mountains.

## (b) Project structure
- `default.project.json` matches the contract exactly.
- No two files map to the same instance path, including case-only collisions. There are no `init` files.
- The 15 remotes are unique and only `Remotes.luau` creates them. Every `Remotes.Get` name is defined.
  `ReplicatedStorage.Remotes` (folder) and `Shared.Remotes` (module) are different paths.
- Tags: each world tag is created with one attribute set that matches the contract. Consumers read only contract
  tags, plus the runtime tags `YardDog`, `RunawayDog` and `Squirrel`, which don't collide. No runtime code adds a
  world tag.

## (c) Data
`roster.py check` passes: 720 dogs, 0 errors, 0 look-alike pairs and 0 near-duplicate names. A separate scan of
`Dogs.luau` found 720 unique ids and 720 unique names (case-insensitive).

## Known gaps
- Long throws that land within about 50 studs past a zone arch pass visually through the arch board (Y 34–44). It
  doesn't block anything (CanCollide/CanQuery are false).
- Space Station planet rings (in the sky, Y ≥ 60) extend over the field edge. Mythic dogs with large wings can go
  past the 9.5-stud roam reach (the radius bottoms out at 1.5).
- A giant runaway dog at the edge of the roam area can clip a lawn corner bush (the bush is non-colliding).
- Decor placement uses Roblox `Random`, so the footprint guarantees are rule-based, not exact positions.
