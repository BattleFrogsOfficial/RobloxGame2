# World

Procedural map for **Throw a Ball for Dogs**. `WorldBuilder.Build()` (called first by `Main.server.luau`)
destroys any old `workspace.Map`, removes the template `Baseplate`/`SpawnLocation`, builds a new `Map`
folder detached, applies lighting (server only), runs `WorldCheck`, then parents the map in one go. Every
coordinate comes from `Config/Layout.luau` + `Config/Zones.luau`; every colour/material from
`Config/WorldTheme.luau`. The design view of the same map is `docs/DESIGN.md` section 2.

**Two levels:** the hub (yards, street, plaza, shop, training, throw zone, spawns) is a plateau at
`Layout.HubY` = 40; the fetch field is at `Layout.GroundY` = 0. The plateau ends at the throw line
(Z = 60) in a stepped rock cliff; the brown throw zone is set flush into the plaza at the very edge (no ramp, no pad, no turns).

## Modules (`src/server/World/`)

| File | Builds |
|---|---|
| `WorldBuilder.luau` | entry point; runs each step in `pcall`, prints the part count, sets `Map.PartCount`, runs WorldCheck |
| `Props.luau` | anchored, smooth, non-colliding-by-default helpers: Slab, Block, Cylinder, Ball, Ellipsoid, Sign, Label, Tree, Pine, Bush, Rock, FenceLine, Arch, Tag |
| `Outskirts.luau` | the hub plateau block (top just under HubY, front face behind the cliff), the field-level underlay, treeline behind the yards, tree clumps beside the plaza, clouds (Persistent Model) |
| `Yards.luau` | 6 yards (52 x 100) side by side + the hedge strips between them |
| `Street.luau` | crossbar street, centre dashes, zebra crossings at every gate |
| `Plaza.luau` | ONE ball shop (west, "BALL SHOP" sign), ONE training area (east, "TRAINING" sign), two spawns, the runaway lawn + squirrel loop; paving laid around the throw zone |
| `ThrowZone.luau` | the brown throw zone: a dirt floor strip flush with the plaza (`Layout.ThrowZone` x -50..50, Z 40..60, Y = HubY) with a lighter border, touching the throw line; tagged `ThrowZone` (+ `ThrowPad` PadIndex 1 for older code); nothing collidable inside it |
| `ThrowLine.luau` | white throw line across the plaza front, low railings along the plaza front, ONE invisible edge wall (`Layout.Edge.GuardHeight` 20) so nobody walks or jumps off the cliff |
| `Cliff.luau` | the plateau cliff along the throw line: four stepped rock strata of irregular slabs from wall to wall, moss caps, grass lip; pure scenery (Persistent Model) |
| `Field.luau` | 9 ZoneBand floors, apron strips (run under the walls), side-only zone-name gantries + full-width boundary lines, distance lines + blank marker boards, end backdrop; runs the zone decorators |
| `Zones/Kit.luau` | the fill rules: ground cover over the whole plot (Atomic CoverCells), 20-40 spaced props (Atomic, `PropGap` 6 edge to edge, low props only in the ball-POV corridor), one Persistent landmark at the field edge, boundary + arch helpers; everything non-colliding and non-queryable |
| `Zones/<ZoneId>.luau` | one themed decorator per zone (`return function(ctx)`, seeded): ground, cover, props, landmark, boundary style, particles |
| `Walls.luau` | 200+ stud stepped cliff / hedge walls around the whole map, coloured per zone; hub-side runs on the plateau, field runs on the field; pure scenery (Persistent Model) |
| `Boundaries.luau` | invisible walls around the crossbar and the plaza, on the plateau |
| `Lighting.luau` | ClockTime, ambient, Atmosphere haze, Sky, Bloom, ColorCorrection, SunRays (server only; adopts effects by name, never the client's `ZoneAmbienceCC`) |
| `WorldCheck.luau` | post-build check: tagged parts on their ground, spawn volumes clear, tag counts |

Client side, `src/client/ZoneAmbience.client.luau` blends Lighting and its own `ZoneAmbienceCC` colour
correction toward a per-zone preset while the camera is over the field.

## Map (top view, +Z down the stem, origin = T junction)

```
 Z -180  ~~~~~~~~~~~~~ scenery wall (hedge) ~~~~~~~~~~~~~        } plateau, Y = HubY (40)
 Z -154  +-Y1-+-Y2-+-Y3-+-Y4-+-Y5-+-Y6-+     yards 52 x 100, centres x -140..140 (56 apart)
         | 12 DogSpots, kennel, trophy  |     YardSign over each gate faces the street
 Z  -54  +=GATE=========================+
         |  STREET  x -170..170          |
 Z  -34  +-------------------------------+
                | spawn          spawn |        plaza x -60..60
                | BALL SHOP   TRAINING |        shop (-34, -4), training (34, 2), name signs
                | lawn                 |        lawn (x -56..-24, z 18..56) = RunawayArea + squirrel loop
 Z   40      |  [ BROWN THROW ZONE ]  |        throw zone x -50..50, Z 40..60 (anyone in it can throw)
 Z   60  ====== throw line / cliff edge ======  zone front edge = distance 0; edge wall + railings
         \\\\\ stepped rock cliff 40 -> 0 \\\\  foot at Z ~63.8
                | cover + spaced props |        field x -120..120 at Y = GroundY (0), aprons to |x| 266
                | landmark, boundary   |        9 filled zone bands, boundary line + gantry at each start
 Z 3260         +----- END BACKDROP ----+
 Z 3310  ~~~~~~~~~~~~~ scenery wall ~~~~~~~~~~~  side walls from |x| 236 outward
```

## Tags created (WORLD TAGS CONTRACT)

`YardPlot`, `YardSign` (SurfaceGui TextLabel `OwnerLabel`), `DogSpot` (YardIndex, SpotIndex 1-12),
`KennelSign` (`CountLabel`), `TrophySpot`, `ThrowZone` (the brown floor; also tagged `ThrowPad` PadIndex 1), `TrainingStation` (StationId "Main"), `ShopStand` (ShopId "Balls"), `PlazaSpawn`
(2 SpawnLocations), `RunawayArea` (thin lawn part), `SquirrelPath` (8 waypoints, `Order`), `ZoneBand`
(ZoneId + MinDistance/MaxDistance/ZoneName), `DistanceMarker` (Distance; 2 per 100 studs, 100..3100).

## World text

The only text in the world is the zone name on each zone arch board, the yard owner signs (`OwnerLabel`),
the kennel count (`CountLabel`) and the two plaza name signs "BALL SHOP" (`ShopLabel`) and "TRAINING"
(`TrainingLabel`). The throw zone, distance markers and the end backdrop carry no text.
`tools/worldcheck/run.luau` enforces this allowlist.

## Part count and streaming

About 7,100 parts: field + zones ~5,000 (budget 8,000, `tools/worldcheck/zones.luau`), walls ~630
(budget 1,500), cliff ~320, yards ~1,000, the rest plaza, throw zone, street and outskirts. The real number is
printed at startup and stored in `workspace.Map:GetAttribute("PartCount")`.

`Workspace.StreamingEnabled` (`default.project.json`: `StreamingMinRadius` 448, `StreamingTargetRadius` 1024).
Persistent Models (always streamed): `Walls`, `Cliff`, `Outskirts`, and per zone the `Ground` model, arch,
boundary line and landmark: ~1,730 parts (`tools/worldcheck/run.luau` prints the split and fails above 6,000).
Props and ground-cover cells are Atomic and stream in around the player; the cutscene calls
`RequestStreamAroundAsync(LandPos)` when the ThrowResult arrives, and its ground raycast falls back to
`LandPos.Y` (= `Layout.GroundY`) if the landing area is not in yet.

## Checks

- `lune run tools/worldcheck/run.luau` builds the real world headlessly: WorldCheck, area overlaps,
  plateau + throw zone geometry vs Layout (no ramp, no pad), the cliff face (covered, arcs clear the ledges),
  walls (height, enclosure, outside the field, apron edge hidden under them), Persistent streaming models,
  the landing band (Field fill is reported apart), camera box, world text allowlist, Lighting vs
  `ZoneAmbienceCC`, and walking paths (every route between a yard gate, the throw zone, the shop and the
  training area <= 300 studs).
- `lune run tools/worldcheck/zones.luau`: per-zone checks (ground, cover and prop counts rising by zone,
  prop spacing, corridor heights, landmark, boundary, arch opening, streaming modes, no text outside arch
  boards, part budget).
- `python3 tools/world_bounds.py`: fast static check of Layout / module constants.

## Known gaps / TODO

- Not run in Studio (no Rojo here). The headless checks run the real builder under `@lune/roblox`.
- Streaming behaviour (what a phone keeps at 1024 studs, how fast a landing zone streams in during the
  ball POV) can only be judged on a device.
