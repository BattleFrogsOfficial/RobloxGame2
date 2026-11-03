# World

Procedural map for **Throw a Ball for Dogs**. `WorldBuilder.Build()` (called first by `Main.server.luau`)
destroys any old `workspace.Map`, removes the template `Baseplate`/`SpawnLocation`, builds a new `Map`
folder detached, applies lighting (server only), runs `WorldCheck`, then parents the map in one go. Every
coordinate comes from `Config/Layout.luau` + `Config/Zones.luau`; every colour/material from
`Config/WorldTheme.luau`. The design view of the same map is `docs/DESIGN.md` section 2.

## Modules (`src/server/World/`)

| File | Builds |
|---|---|
| `WorldBuilder.luau` | entry point; runs each step in `pcall`, prints the part count, sets `Map.PartCount`, runs WorldCheck |
| `Props.luau` | anchored, smooth, non-colliding-by-default helpers: Slab, Block, Cylinder, Ball, Ellipsoid, Sign, Label, Tree, Pine, Bush, Rock, FenceLine, Arch, Tag |
| `Outskirts.luau` | grass underlay under everything, treeline behind the yards, tree clumps beside the plaza, clouds |
| `Yards.luau` | 6 yards (52 x 100) side by side + the hedge strips between them |
| `Street.luau` | crossbar street, centre dashes, zebra crossings at every gate |
| `Plaza.luau` | ONE ball shop (west), ONE training area (east), two spawns, the runaway lawn + squirrel loop |
| `Platform.luau` | the ONE raised throwing platform: tower, deck (Y = 40), 30 degree ramp, throw spot, 5 queue spots, railings + invisible guards |
| `ThrowLine.luau` | ground-level throw line in front of the tower, low fence + invisible wall along the plaza's field edge |
| `Field.luau` | 9 ZoneBand floors, apron strips (run under the walls), zone-name arches + themed gates, distance lines + blank marker boards, end backdrop |
| `Zones/Kit.luau` | placement rules for decorators (outer 25% bands, landmark edge, arch / gate helpers) |
| `Zones/<ZoneId>.luau` | one themed decorator per zone (`return function(ctx)`): ground, 15-30 decorations, one landmark, particles |
| `Walls.luau` | 200+ stud stepped cliff / hedge walls around the whole map, coloured per zone; pure scenery |
| `Boundaries.luau` | invisible walls around the crossbar and the plaza |
| `Lighting.luau` | ClockTime, ambient, Atmosphere haze, Sky, Bloom, ColorCorrection, SunRays (server only; adopts effects by name, never the client's `ZoneAmbienceCC`) |
| `WorldCheck.luau` | post-build check: tagged parts on their ground, spawn volumes clear, tag counts |

Client side, `src/client/ZoneAmbience.client.luau` blends Lighting and its own `ZoneAmbienceCC` colour
correction toward a per-zone preset while the camera is over the field.

## Map (top view, +Z down the stem, origin = T junction)

```
 Z -180  ~~~~~~~~~~~~~ scenery wall (hedge) ~~~~~~~~~~~~~
 Z -154  +-Y1-+-Y2-+-Y3-+-Y4-+-Y5-+-Y6-+     yards 52 x 100, centres x -140..140 (56 apart)
         | 12 DogSpots, kennel, trophy  |     YardSign over each gate faces the street
 Z  -54  +=GATE=========================+
         |  STREET  x -170..170          |
 Z  -34  +------+  ramp foot  +----------+
                | spawn |  | spawn |            plaza x -60..60
                | BALL  |R |  TRAINING|         ramp x -6..6, ~30 deg, Z -34..34
                | SHOP  |A |  (Main)  |
                | lawn  |M |          |         lawn (x -56..-24, z 18..56) = RunawayArea + squirrel loop
 Z   34         |      [ DECK Y=40 ]   |        deck x -18..18, Z 34..60, queue spots at x 10
 Z   60  =========== throw line ==========      front edge of the deck = distance 0
                |deco| centre lane |deco|       field x -120..120, aprons to |x| 266
                |25% | |x| < 60    |25% |       9 zone bands, arch at each band start
 Z 3260         +----- END BACKDROP ----+
 Z 3310  ~~~~~~~~~~~~~ scenery wall ~~~~~~~~~~~  side walls from |x| 236 outward
```

## Tags created (WORLD TAGS CONTRACT)

`YardPlot`, `YardSign` (SurfaceGui TextLabel `OwnerLabel`), `DogSpot` (YardIndex, SpotIndex 1-12),
`KennelSign` (`CountLabel`), `TrophySpot`, `ThrowPad` (PadIndex 1: the platform deck), `QueueSpot`
(Order 1-5), `TrainingStation` (StationId "Main"), `ShopStand` (ShopId "Balls"), `PlazaSpawn`
(2 SpawnLocations), `RunawayArea` (thin lawn part), `SquirrelPath` (8 waypoints, `Order`), `ZoneBand`
(ZoneId + MinDistance/MaxDistance/ZoneName), `DistanceMarker` (Distance; 2 per 100 studs, 100..3100).

## World text

The only text in the world is the zone name on each zone arch board, the yard owner signs (`OwnerLabel`)
and the kennel count (`CountLabel`). Shop, training, platform, queue spots, distance markers and the end
backdrop are blank coloured boards. `tools/worldcheck/run.luau` enforces this.

## Part count

About 3,600 parts (budget 6,000): walls ~630, field + zones ~1,700, yards ~1,000, the rest plaza,
platform, street and outskirts. The real number is printed at startup and stored in
`workspace.Map:GetAttribute("PartCount")`.

## Checks

- `lune run tools/worldcheck/run.luau` builds the real world headlessly: WorldCheck, area overlaps,
  platform geometry vs Layout, walls (height, enclosure, outside the field, apron edge hidden under them),
  landing lane, camera box, world text, Lighting vs `ZoneAmbienceCC`, and walking paths (every route
  between a yard gate, the platform, the shop and the training area <= 300 studs).
- `lune run tools/worldcheck/zones.luau`: per-zone checks (ground, decoration count, landmark, arch
  opening, lane clear, no text outside arch boards, part budget).
- `python3 tools/world_bounds.py`: fast static check of Layout / module constants.

## Known gaps / TODO

- Not run in Studio (no Rojo here). The headless checks run the real builder under `@lune/roblox`.
- The stem is 3,200 studs long: with StreamingEnabled the far zones may stream out. Consider
  `StreamingTargetRadius` >= 1024 or `ModelStreamingMode = Persistent` for the arches only.
