# World (agent D)

Procedural map for **Throw a Ball for Dogs**. `WorldBuilder.Build()` (called first by `Main.server.luau`)
destroys any old `workspace.Map`, removes the template `Baseplate`/`SpawnLocation`, builds a new
`Map` folder detached, applies lighting, then parents it in one go. Every coordinate comes from
`Config/Layout.luau` + `Config/Zones.luau`; every colour/material from `Config/WorldTheme.luau`.

## Modules

| File | Builds |
|---|---|
| `WorldBuilder.luau` | entry point; runs each step in `pcall`, prints the part count, sets `Map.PartCount` |
| `Props.luau` | anchored, smooth, non-colliding-by-default helpers: Slab, Block, Cylinder, Ball, Ellipsoid, Sign, Label, Tree, Pine, Bush, Rock, Bench, Lamp, FenceLine, Arch, Wall, Tag |
| `Outskirts.luau` | grass underlay under everything, hills + treeline behind the yards, tree clumps beside the plaza, clouds |
| `Yards.luau` | 6 yards + the hedge strips between them |
| `Street.luau` | crossbar street, centre dashes, zebra crossings at every gate, title arch over the junction |
| `Plaza.luau` | hub: spawns, lawn (RunawayArea), running track + Sprint gate, squirrel loop, 4 shops, 2 training rigs, leaderboard, benches/trees |
| `ThrowLine.luau` | throw line, 6 numbered pads, rope fence + invisible wall at Z = ThrowLine.Z + 8 |
| `Field.luau` | 9 ZoneBand floors, apron strips, zone arches, distance lines + markers, end backdrop |
| `Zones/Kit.luau` | placement rules for decorators (outer-25% band / apron, avoids markers + arch pillars) |
| `Zones/<ZoneId>.luau` | one themed decorator per zone, each `return function(ctx)` |
| `Lighting.luau` | ClockTime, ambient, Atmosphere, Sky, Bloom, ColorCorrection, SunRays (idempotent) |
| `Boundaries.luau` | invisible walls around the crossbar and the plaza |

## Map (top view, +Z down the stem, origin = T junction)

```
 Z -200  +--Y1--+ +--Y2--+ +--Y3--+ +--Y4--+ +--Y5--+ +--Y6--+    hills / treeline behind (unreachable)
         |grid  | |      | |      | |      | |      | |      |    each yard 110x120: 12 DogSpots (4x3),
         |kennel| |  ...  hedge strips (10 wide) between yards   |    kennel + KennelSign, TrophySpot,
 Z  -80  +=GATE=+ +=GATE=+ +=GATE=+ +=GATE=+ +=GATE=+ +=GATE=+    YardSign over the gate faces the street
         |=========== STREET  x -380..380 (zebra at each gate) ===========|
 Z  -40  +---------------+--[ TITLE ARCH ]--+---------------+
                         | SHOPS  spawn spawn  TRAIN |         plaza x -120..120
                         | Balls  .-track---.  Pull  |         lawn = RunawayArea (x -40..40, z -12..32)
                         | Boosts | lawn    |S Mach. |         running track loop = SquirrelPath (10 wp)
                         | Yard   '---------'  Leader|         S = Sprint start gate (east straight)
                         | Bones  bench    bench board|
 Z   60                  |[1] [2] [3] [4] [5] [6]  |         THROW LINE, pads at x -75..75
 Z   68                  |~~~~ rope fence + wall ~~~|         players stop here
                         |deco|   centre lane  |deco|         Backyard   0-100
                         |25% |   (|x| < 60)   |25% |  apron  Park     100-250   arches at band starts,
                         |    |   kept clear   |    |  props  Beach    250-450   markers every 100
                         |    |                |    |  x to   Farm     450-700
                         |    |                |    |  +-220  Forest   700-1000
                         |    |                |    |         Snowy Peaks 1000-1400
                         |    |                |    |         City Rooftops 1400-1900
                         |    |                |    |         Space Station 1900-2500
 Z 3260                  +--------- END BACKDROP ---+         Mythic Meadow 2500-3200
```

## Tags created (WORLD TAGS CONTRACT)

`YardPlot`, `YardSign` (SurfaceGui TextLabel `OwnerLabel`), `DogSpot` (YardIndex, SpotIndex 1-12, spot 1-4
= row nearest the gate), `KennelSign` (`CountLabel`), `TrophySpot`, `ThrowPad` (PadIndex),
`TrainingStation` (StationId; the tagged part is the station mat / Sprint start line), `ShopStand`
(ShopId; tagged part = the counter), `Leaderboard` (SurfaceGui `ScrollingFrame` `List`), `PlazaSpawn`
(2 SpawnLocations), `RunawayArea` (thin lawn part), `SquirrelPath` (10 invisible waypoints, `Order` 1-10),
`ZoneBand` (ZoneId + MinDistance/MaxDistance/ZoneName), `DistanceMarker` (Distance; 2 per 100 studs,
100..3100 — 3200 is the end backdrop).

## Part-count estimate (~3,000; budget 6,000)

| Area | Parts |
|---|---|
| Yards (6 x ~165, fences dominate) + hedge gaps | ~1,010 |
| Street + title arch | ~80 |
| Plaza | ~155 |
| Throw line | ~65 |
| Field structure (bands, aprons, arches, 31 x 2 markers, lines) | ~380 |
| Zone decorators (9 x 70-190) | ~1,080 |
| Outskirts + boundaries | ~175 |

The real number is printed at startup and stored in `workspace.Map:GetAttribute("PartCount")`.

## Checks

`python3 tools/world_bounds.py` parses Layout/Zones and the World module constants and asserts no
unintended XZ overlaps (floors tile, yard and plaza props don't collide, queue strip / gate paths /
centre lane stay clear, sprint lap >= 220 studs).
Since the final QA pass it also checks gate openings, dog roam reach in yards, the title arch, lawn bushes vs
the runaway roam area, the squirrel loop, the server landing lane, per-zone decor footprints vs their Kit
margins, and project structure (Rojo paths, remotes, tag attributes). Findings: `docs/qa/OVERLAP.md`.

## Known gaps / TODO

- Not run in Studio (no Rojo/Luau toolchain here). Reviewed by reading.
- The pad number on the pad's Top face assumes SurfaceGui Top orientation; an upright "PAD n" board
  backs it up either way.
- ShopStands get no ProximityPrompt from the world (the client/ShopService owns interaction).
- The stem is 3,200 studs long: with StreamingEnabled the far zones may stream out. Consider
  `StreamingTargetRadius` >= 1024 or set the zone models' `ModelStreamingMode = Persistent` for the
  arches only.
- Zone arch boards cross the centre lane at Y 34-44 (above dogs). They are CanCollide/CanQuery false, so the
  visual-only ball can pass through a board for a frame on long throws that land just past an arch.
