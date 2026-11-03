#!/usr/bin/env python3
"""World bounds check (agent D).

Re-derives every major XZ rectangle of the procedural map from the Luau sources and asserts:
  * floors tile without overlapping (touching edges is fine),
  * functional/props footprints inside each area do not overlap each other,
  * everything sits inside its parent area,
  * walk lanes (plaza queue strip, yard paths, field centre lane) stay clear,
  * zone bands are contiguous and end exactly at Layout.Field.MaxZ.

Constants are parsed with regex from src/shared/Config/Layout.luau, Zones.luau and the World modules,
so editing those files and re-running this script catches drift. Run:  python3 tools/world_bounds.py
"""
from __future__ import annotations

import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "src/shared/Config"
WORLD = ROOT / "src/server/World"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def num_list(s: str) -> list[float]:
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", s)]


def grab(pattern: str, text: str, what: str) -> re.Match:
    m = re.search(pattern, text, re.S)
    if not m:
        sys.exit(f"PARSE ERROR: could not find {what} ({pattern!r})")
    return m


# ---------------------------------------------------------------- Layout.luau
lay = read(CFG / "Layout.luau")
yards_blk = grab(r"Layout\.Yards\s*=\s*\{(.*?)\n\}", lay, "Layout.Yards").group(1)
YARD_W, _, YARD_D = num_list(grab(r"Size\s*=\s*Vector3\.new\(([^)]*)\)", yards_blk, "Yards.Size").group(1))
YARD_CZ = float(grab(r"CenterZ\s*=\s*(-?\d+)", yards_blk, "Yards.CenterZ").group(1))
YARD_CX = num_list(grab(r"CentersX\s*=\s*\{([^}]*)\}", yards_blk, "Yards.CentersX").group(1))
YARD_COUNT = int(grab(r"Count\s*=\s*(\d+)", yards_blk, "Yards.Count").group(1))


def rect_of(name: str) -> dict[str, float]:
    blk = grab(rf"Layout\.{name}\s*=\s*\{{([^}}]*)\}}", lay, f"Layout.{name}").group(1)
    return {k: float(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?\d+(?:\.\d+)?)", blk)}


STREET = rect_of("Street")
PLAZA = rect_of("Plaza")
FIELD = rect_of("Field")
tl_blk = grab(r"Layout\.ThrowLine\s*=\s*\{(.*?)\n\}", lay, "Layout.ThrowLine").group(1)
TL_Z = float(grab(r"Z\s*=\s*(-?\d+)", tl_blk, "ThrowLine.Z").group(1))
PADS_X = num_list(grab(r"PadsX\s*=\s*\{([^}]*)\}", tl_blk, "PadsX").group(1))
PAD_W, PAD_H, PAD_D = num_list(grab(r"PadSize\s*=\s*Vector3\.new\(([^)]*)\)", tl_blk, "PadSize").group(1))

# ---------------------------------------------------------------- Zones.luau
zones_src = read(CFG / "Zones.luau")
ZONES = [
    (m.group(1), float(m.group(2)), float(m.group(3)))
    for m in re.finditer(r'Id\s*=\s*"(\w+)".*?MinDistance\s*=\s*(\d+),\s*MaxDistance\s*=\s*(\d+)', zones_src)
]

# ---------------------------------------------------------------- World module constants
ytxt = read(WORLD / "Yards.luau")
SPOT_SIZE = float(grab(r"SpotSize\s*=\s*(\d+)", ytxt, "SpotSize").group(1))
SPOT_COLS = num_list(grab(r"SpotColsX\s*=\s*\{([^}]*)\}", ytxt, "SpotColsX").group(1))
SPOT_ROWS = num_list(grab(r"SpotRowsZ\s*=\s*\{([^}]*)\}", ytxt, "SpotRowsZ").group(1))
PATH_W = float(grab(r"PathWidth\s*=\s*(\d+)", ytxt, "PathWidth").group(1))
GATE_W = float(grab(r"GateWidth\s*=\s*(\d+)", ytxt, "GateWidth").group(1))
k = grab(r"Kennel\s*=\s*\{\s*X\s*=\s*(-?\d+),\s*Z\s*=\s*(-?\d+),\s*W\s*=\s*(\d+),\s*D\s*=\s*(\d+)", ytxt, "Kennel")
KEN_X, KEN_Z, KEN_W, KEN_D = map(float, k.groups())
t = grab(r"Trophy\s*=\s*\{\s*X\s*=\s*(-?\d+),\s*Z\s*=\s*(-?\d+),\s*Size\s*=\s*(\d+)", ytxt, "Trophy")
TRO_X, TRO_Z, TRO_S = map(float, t.groups())
BUSH_X = float(grab(r"Props\.Bush\(model, Vector3\.new\(cx \+ side \* (\d+)", ytxt, "yard bush X").group(1))
TREE_X = float(grab(r"Props\.Tree\(model, Vector3\.new\(cx \+ side \* (\d+)", ytxt, "yard tree X").group(1))
assert TREE_X == 48, "yard front tree X changed: update the tree boxes"
SIGN_W = num_list(grab(r"SignBoard\s*=\s*Vector3\.new\(([^)]*)\)", ytxt, "SignBoard").group(1))[0]

ptxt = read(WORLD / "Plaza.luau")
lawn = grab(r"Plaza\.Lawn\s*=\s*\{\s*MinX\s*=\s*(-?\d+),\s*MaxX\s*=\s*(-?\d+),\s*MinZ\s*=\s*P\.MinZ\s*\+\s*(\d+),\s*MaxZ\s*=\s*P\.MinZ\s*\+\s*(\d+)", ptxt, "Plaza.Lawn")
LAWN = (float(lawn[1]), float(lawn[2]), PLAZA["MinZ"] + float(lawn[3]), PLAZA["MinZ"] + float(lawn[4]))
tr = grab(r"Plaza\.TrackOuter\s*=\s*\{\s*MinX\s*=\s*(-?\d+),\s*MaxX\s*=\s*(-?\d+),\s*MinZ\s*=\s*P\.MinZ\s*\+\s*(\d+),\s*MaxZ\s*=\s*P\.MinZ\s*\+\s*(\d+)", ptxt, "TrackOuter")
TRACK = (float(tr[1]), float(tr[2]), PLAZA["MinZ"] + float(tr[3]), PLAZA["MinZ"] + float(tr[4]))
TRACK_W = float(grab(r"Plaza\.TrackWidth\s*=\s*(\d+)", ptxt, "TrackWidth").group(1))
SPAWN_SIZE = float(grab(r"Plaza\.SpawnSize\s*=\s*(\d+)", ptxt, "SpawnSize").group(1))
spawn_xs = [float(x) for x in re.findall(r"Vector3\.new\((-?\d+),\s*0,\s*P\.MinZ\s*\+\s*\d+\)", grab(r"Plaza\.Spawns\s*=\s*\{([^\n]*)\}", ptxt, "Spawns").group(1))]
SPAWN_Z = PLAZA["MinZ"] + float(grab(r"Plaza\.Spawns\s*=\s*\{\s*Vector3\.new\(-?\d+,\s*0,\s*P\.MinZ\s*\+\s*(\d+)\)", ptxt, "Spawn Z").group(1))
shopcol = grab(r"Plaza\.ShopColumn\s*=\s*\{\s*MinX\s*=\s*P\.MinX,\s*MaxX\s*=\s*P\.MinX\s*\+\s*(\d+),\s*CentersZ\s*=\s*\{([^}]*)\},\s*Width\s*=\s*(\d+)", ptxt, "ShopColumn")
SHOP_DEPTH, SHOP_ZS, SHOP_W = float(shopcol[1]), num_list(shopcol[2]), float(shopcol[3])
st = {m[0]: (PLAZA["MaxX"] - float(m[1]), float(m[2])) for m in re.findall(r"(\w+)\s*=\s*Vector3\.new\(P\.MaxX\s*-\s*(\d+),\s*0,\s*(-?\d+)\)", ptxt)}
MAT = float(grab(r"Plaza\.StationMat\s*=\s*(\d+)", ptxt, "StationMat").group(1))
SPRINT_Z = float(grab(r"Plaza\.SprintGateZ\s*=\s*(-?\d+)", ptxt, "SprintGateZ").group(1))
lb = grab(r"Plaza\.Leaderboard\s*=\s*\{\s*X\s*=\s*P\.MaxX\s*-\s*(\d+),\s*Z\s*=\s*(-?\d+),\s*Width\s*=\s*(\d+)", ptxt, "Leaderboard")
LB_X, LB_Z, LB_W = PLAZA["MaxX"] - float(lb[1]), float(lb[2]), float(lb[3])
CORNER_TREE_X = float(grab(r"Vector3\.new\(side \* (\d+), Y, z\)\n\s*Props\.Slab\(f, \"Planter\"", ptxt, "corner tree X").group(1))
_tz = grab(r"for _, z in \{ P\.MaxZ - (\d+), P\.MinZ \+ (\d+) \} do", ptxt, "corner tree Z")
CORNER_TREE_ZS = (PLAZA["MaxZ"] - float(_tz[1]), PLAZA["MinZ"] + float(_tz[2]))
BENCH_X = float(grab(r"Props\.Bench\(f, Vector3\.new\(side \* (\d+)", ptxt, "bench X").group(1))

tltxt = read(WORLD / "ThrowLine.luau")
WALL_OFF = float(grab(r"ThrowLine\.WallOffset\s*=\s*(\d+)", tltxt, "WallOffset").group(1))

ktxt = read(WORLD / "Zones/Kit.luau")
assert "Kit.LaneHalf = Kit.FieldHalf * 0.5" in ktxt, "Kit.LaneHalf must keep the centre 50% clear"
FIELD_HALF = (FIELD["MaxX"] - FIELD["MinX"]) / 2
FIELD_CX = (FIELD["MaxX"] + FIELD["MinX"]) / 2
LANE_HALF = FIELD_HALF * 0.5
APRON_HALF = FIELD_HALF + float(grab(r"Kit\.ApronHalf = Kit\.FieldHalf \+ (\d+)", ktxt, "ApronHalf").group(1))
MARKER_X = LANE_HALF + float(grab(r"Kit\.MarkerX = Kit\.LaneHalf \+ (\d+)", ktxt, "MarkerX").group(1))
ARCH_X = FIELD_HALF - float(grab(r"Kit\.ArchX = Kit\.FieldHalf - (\d+)", ktxt, "ArchX").group(1))


# ---------------------------------------------------------------- geometry
@dataclass
class R:
    name: str
    x0: float
    x1: float
    z0: float
    z1: float

    def area_overlap(self, o: "R") -> float:
        dx = min(self.x1, o.x1) - max(self.x0, o.x0)
        dz = min(self.z1, o.z1) - max(self.z0, o.z0)
        return dx * dz if dx > 1e-6 and dz > 1e-6 else 0.0

    def inside(self, o: "R") -> bool:
        e = 1e-6
        return self.x0 >= o.x0 - e and self.x1 <= o.x1 + e and self.z0 >= o.z0 - e and self.z1 <= o.z1 + e

    def __str__(self) -> str:
        return f"{self.name}[x {self.x0:g}..{self.x1:g}, z {self.z0:g}..{self.z1:g}]"


def box(name: str, cx: float, cz: float, w: float, d: float) -> R:
    return R(name, cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2)


errors: list[str] = []
checks = 0


def no_overlap(group: list[R], label: str) -> None:
    global checks
    for i in range(len(group)):
        for j in range(i + 1, len(group)):
            checks += 1
            a = group[i].area_overlap(group[j])
            if a > 0:
                errors.append(f"[{label}] overlap {a:.1f} sq studs: {group[i]} x {group[j]}")


def all_inside(group: list[R], parent: R, label: str) -> None:
    global checks
    for r in group:
        checks += 1
        if not r.inside(parent):
            errors.append(f"[{label}] {r} is outside {parent}")


def clear(group: list[R], lane: R, label: str) -> None:
    global checks
    for r in group:
        checks += 1
        if r.area_overlap(lane) > 0:
            errors.append(f"[{label}] {r} blocks lane {lane}")


# ---------------------------------------------------------------- floors
yards = []
for i, cx in enumerate(YARD_CX, start=1):
    yards.append(R(f"Yard{i}", cx - YARD_W / 2, cx + YARD_W / 2, YARD_CZ - YARD_D / 2, YARD_CZ + YARD_D / 2))
assert len(yards) == YARD_COUNT, "Yards.CentersX length must equal Yards.Count"
edges = sorted([y.x0 for y in yards] + [y.x1 for y in yards])
gap_iv = [(STREET["MinX"], edges[0])] + [(edges[i], edges[i + 1]) for i in range(1, len(edges) - 2, 2)] + [(edges[-1], STREET["MaxX"])]
gaps = [R(f"Gap{i}", a, b, yards[0].z0, yards[0].z1) for i, (a, b) in enumerate(gap_iv) if b > a]
street = R("Street", STREET["MinX"], STREET["MaxX"], STREET["MinZ"], STREET["MaxZ"])
plaza = R("Plaza", PLAZA["MinX"], PLAZA["MaxX"], PLAZA["MinZ"], PLAZA["MaxZ"])
field = R("Field", FIELD["MinX"], FIELD["MaxX"], FIELD["MinZ"], FIELD["MaxZ"])
bands, aprons = [], []
for zid, dmin, dmax in ZONES:
    z0, z1 = TL_Z + dmin, TL_Z + dmax
    bands.append(R(f"ZoneBand_{zid}", FIELD["MinX"], FIELD["MaxX"], z0, z1))
    aprons.append(R(f"ApronW_{zid}", FIELD_CX - APRON_HALF, FIELD["MinX"], z0, z1))
    aprons.append(R(f"ApronE_{zid}", FIELD["MaxX"], FIELD_CX + APRON_HALF, z0, z1))

floors = yards + gaps + [street, plaza] + bands + aprons
no_overlap(floors, "floors")

# crossbar spans the street exactly, yards butt onto the street, plaza butts onto street + field
crossbar = R("Crossbar", STREET["MinX"], STREET["MaxX"], yards[0].z0, yards[0].z1)
covered = sum(r.x1 - r.x0 for r in yards + gaps)
checks += 1
if abs(covered - (crossbar.x1 - crossbar.x0)) > 1e-6:
    errors.append(f"[floors] yards+gaps cover {covered} of crossbar width {crossbar.x1 - crossbar.x0} (holes!)")
for cond, msg in [
    (yards[0].z1 == STREET["MinZ"], "yards must end where the street starts"),
    (PLAZA["MinZ"] == STREET["MaxZ"], "plaza must start where the street ends"),
    (PLAZA["MaxZ"] == TL_Z == FIELD["MinZ"], "plaza ends at the throw line = field start"),
    (PLAZA["MinX"] >= STREET["MinX"] and PLAZA["MaxX"] <= STREET["MaxX"], "plaza (stem) narrower than street (crossbar)"),
    (abs(sum(b.z1 - b.z0 for b in bands) - (FIELD["MaxZ"] - FIELD["MinZ"])) < 1e-6, "zone bands cover the whole field"),
    (all(bands[i].z1 == bands[i + 1].z0 for i in range(len(bands) - 1)), "zone bands contiguous"),
    (len(ZONES) == 9, "9 zones"),
]:
    checks += 1
    if not cond:
        errors.append(f"[layout] {msg}")

# ---------------------------------------------------------------- yards
for i, (yard, cx) in enumerate(zip(yards, YARD_CX), start=1):
    items: list[R] = []
    for row, rz in enumerate(SPOT_ROWS):
        for col, rx in enumerate(SPOT_COLS):
            items.append(box(f"Y{i}Spot{row * len(SPOT_COLS) + col + 1}", cx + rx, YARD_CZ + rz, SPOT_SIZE + 1.2, SPOT_SIZE + 1.2))
    items.append(box(f"Y{i}Kennel", cx + KEN_X, YARD_CZ + KEN_Z, KEN_W + 2, KEN_D + 2))  # incl. roof overhang
    items.append(box(f"Y{i}Trophy", cx + TRO_X, YARD_CZ + TRO_Z, TRO_S + 1, TRO_S + 1))
    for side in (-1, 1):
        items.append(box(f"Y{i}FrontTree{side}", cx + side * 48, yard.z1 - 9, 9 * 0.9 + 1, 9 * 0.9 + 1))
        items.append(box(f"Y{i}Bush{side}", cx + side * BUSH_X, YARD_CZ + 2, 6 * 0.9, 5 * 0.9))
    path = R(f"Y{i}Path", cx - PATH_W / 2, cx + PATH_W / 2, YARD_CZ + SPOT_ROWS[1], yard.z1)
    inner = R(f"Y{i}Inner", yard.x0 + 1.6, yard.x1 - 1.6, yard.z0 + 1.6, yard.z1 - 1.6)  # inside the fence
    no_overlap(items, f"yard{i}")
    all_inside(items, inner, f"yard{i}")
    clear(items, path, f"yard{i} gate path")
    checks += 1
    if SIGN_W / 2 - 1.5 <= GATE_W / 2:
        errors.append(f"[yard{i}] sign posts would stand inside the gate opening")
    checks += 1
    if len(items) - 6 != 12:
        errors.append(f"[yard{i}] expected 12 dog spots")

# ---------------------------------------------------------------- plaza
pl_items: list[R] = []
for n, x in enumerate(spawn_xs, start=1):
    pl_items.append(box(f"Spawn{n}", x, SPAWN_Z, SPAWN_SIZE + 1.6, SPAWN_SIZE + 1.6))
tx0, tx1, tz0, tz1 = TRACK
track_parts = [
    R("TrackN", tx0, tx1, tz0, tz0 + TRACK_W), R("TrackS", tx0, tx1, tz1 - TRACK_W, tz1),
    R("TrackW", tx0, tx0 + TRACK_W, tz0 + TRACK_W, tz1 - TRACK_W), R("TrackE", tx1 - TRACK_W, tx1, tz0 + TRACK_W, tz1 - TRACK_W),
]
lawn_r = R("Lawn/RunawayArea", *LAWN)
pl_items += track_parts + [lawn_r]
gx = tx1 - TRACK_W / 2
for side in (-1, 1):
    pl_items.append(box(f"SprintPillar{side}", gx + side * (TRACK_W / 2 + 2), SPRINT_Z, 1.4, 1.4))
shops = [R(f"Shop{n}", PLAZA["MinX"], PLAZA["MinX"] + SHOP_DEPTH, z - SHOP_W / 2, z + SHOP_W / 2) for n, z in enumerate(SHOP_ZS, 1)]
pl_items += shops
for sid, (sx, sz) in st.items():
    pl_items.append(box(sid, sx, sz, MAT, MAT))
pl_items.append(R("Leaderboard", LB_X - 1, LB_X + 2, LB_Z - LB_W / 2 - 0.7, LB_Z + LB_W / 2 + 0.7))
for side in (-1, 1):
    for z in (-6, 24):
        pl_items.append(box(f"Bench{side}{z}", side * BENCH_X, z, 2.6, 8.2))
    for z in CORNER_TREE_ZS:
        pl_items.append(box(f"CornerTree{side}{z:g}", side * CORNER_TREE_X, z, 11 * 1.1, 11 * 1.1))
pads = [box(f"Pad{n}", x, TL_Z, PAD_W + 1.2, PAD_D + 1.2) for n, x in enumerate(PADS_X, 1)]

# Only the lawn may overlap the track's inner hole; tracks touch the lawn rim but must not overlap it.
no_overlap(pl_items, "plaza")
all_inside([r for r in pl_items], plaza, "plaza")
no_overlap(pl_items + pads, "plaza+pads")
no_overlap(pads, "pads")
queue = R("PadQueueStrip", min(p.x0 for p in pads), max(p.x1 for p in pads), tz1, min(p.z0 for p in pads))
clear(pl_items, queue, "plaza queue")
street_mouth = R("StreetMouth", -40, 40, PLAZA["MinZ"], tz0)  # spawn -> lawn walk
clear([r for r in pl_items if not r.name.startswith("Spawn")], street_mouth, "plaza mouth")
checks += 1
lap = 2 * ((tx1 - tx0 - TRACK_W) + (tz1 - tz0 - TRACK_W))
if lap < 220:
    errors.append(f"[plaza] sprint lap {lap} < Training.Sprint.MinLapStuds 220")

# ---------------------------------------------------------------- throw line / field
wall_z = TL_Z + WALL_OFF
for p in pads:
    checks += 1
    if p.z1 >= wall_z - 0.4 - 0.55:  # rope-fence posts (radius 0.55) sit at wall_z - 0.4
        errors.append(f"[throwline] {p} touches the rope fence / field wall at z {wall_z}")
    checks += 1
    if not (p.x0 >= FIELD["MinX"] and p.x1 <= FIELD["MaxX"]):
        errors.append(f"[throwline] {p} outside field width")
lane = R("CentreLane", FIELD_CX - LANE_HALF, FIELD_CX + LANE_HALF, wall_z, FIELD["MaxZ"])
markers = []
d = 100
while d < FIELD["MaxZ"] - TL_Z:
    for side in (-1, 1):
        markers.append(box(f"Marker{d}{side}", FIELD_CX + side * MARKER_X, TL_Z + d, 10, 2.5))
    d += 100
arches = []
for zid, dmin, _ in ZONES:
    az = TL_Z + dmin + (12 if dmin == 0 else 0)
    for side in (-1, 1):
        arches.append(box(f"Arch{zid}{side}", FIELD_CX + side * ARCH_X, az, 5, 5))
clear(markers + arches, lane, "field lane")
all_inside(markers + arches, field, "field")
no_overlap(markers + arches, "field signage")
checks += 1
if not (LANE_HALF / FIELD_HALF == 0.5):
    errors.append("[field] decor band must be the outer 25% each side")

# ---------------------------------------------------------------- QA overlap extension (docs/qa/OVERLAP.md)
SRC = ROOT / "src"
SVC = SRC / "server/Services"

# --- yards: sign posts / gate pillars vs fence + gate, dog roam reach vs props and each other
GATE_PILLAR_OFF = float(grab(r"local gp = gw \+ (\d+(?:\.\d+)?)", ytxt, "gate pillar offset").group(1))
ROAM_REACH = 9.5  # DogService: RoamRadius = clamp(9.5 - half footprint, 1.5, 6) -> reach <= 9.5 (mythic wings may exceed)
dstxt = read(SVC / "DogService.luau")
checks += 1
if "math.clamp(9.5 - math.max(ext.X, ext.Z) / 2, 1.5, 6)" not in dstxt:
    errors.append("[yard] DogService RoamRadius no longer bounded by a 9.5-stud reach")
for i, (yard, cx) in enumerate(zip(yards, YARD_CX), start=1):
    fence_z = yard.z1 - 1
    sign_posts = [box(f"Y{i}SignPost{s}", cx + s * (SIGN_W / 2 - 1.5), fence_z - 1.25, 1.2, 1.2) for s in (-1, 1)]
    gate_pillars = [box(f"Y{i}GatePillar{s}", cx + s * (GATE_W / 2 + GATE_PILLAR_OFF), fence_z, 2.4, 2.4) for s in (-1, 1)]
    gate_posts = [box(f"Y{i}FenceEndPost{s}", cx + s * (GATE_W / 2 + GATE_PILLAR_OFF), fence_z, 1.1, 1.1) for s in (-1, 1)]
    gate_opening = R(f"Y{i}Gate", cx - GATE_W / 2, cx + GATE_W / 2, fence_z - 3, yard.z1)
    fence_rail = [R(f"Y{i}FrontFenceW", yard.x0 + 1, cx - GATE_W / 2, fence_z - 0.55, fence_z + 0.55),
                  R(f"Y{i}FrontFenceE", cx + GATE_W / 2, yard.x1 - 1, fence_z - 0.55, fence_z + 0.55)]
    no_overlap(sign_posts + fence_rail, f"yard{i} sign posts vs fence")
    clear(sign_posts + gate_pillars + gate_posts, gate_opening, f"yard{i} gate opening")
    reach = []
    for row, rz in enumerate(SPOT_ROWS):
        for col, rx in enumerate(SPOT_COLS):
            reach.append(box(f"Y{i}Roam{row * len(SPOT_COLS) + col + 1}", cx + rx, YARD_CZ + rz, 2 * ROAM_REACH, 2 * ROAM_REACH))
    statics = [
        box(f"Y{i}Kennel", cx + KEN_X, YARD_CZ + KEN_Z, KEN_W + 2, KEN_D + 2),
        box(f"Y{i}Trophy", cx + TRO_X, YARD_CZ + TRO_Z, TRO_S + 1, TRO_S + 1),
    ] + [box(f"Y{i}Bush{s}", cx + s * BUSH_X, YARD_CZ + 2, 6 * 0.9, 5 * 0.9) for s in (-1, 1)] \
      + [box(f"Y{i}FrontTree{s}", cx + s * 48, yard.z1 - 9, 9 * 0.9 + 1, 9 * 0.9 + 1) for s in (-1, 1)]
    no_overlap(reach, f"yard{i} dog roam reach")
    for r in reach:
        clear(statics, r, f"yard{i} dog roam reach")
    all_inside(reach, R("inner", yard.x0 + 1.6, yard.x1 - 1.6, yard.z0 + 1.6, yard.z1 - 1.6), f"yard{i} roam inside fence")

# --- street: zebras inside the street, title-arch pillars on the street/plaza seam, clear of spawns/track/mouth
for i, cx in enumerate(YARD_CX, start=1):
    all_inside([R(f"Zebra{i}", cx - 2 * 3.5 - 1, cx + 2 * 3.5 + 1, STREET["MinZ"] + 3, STREET["MinZ"] + 13)], street, "street zebra")
arch_pillars = [box(f"TitleArchPillar{s}", s * 50, STREET["MaxZ"], 4, 4) for s in (-1, 1)]
checks += 1
if "Props.Arch(folder, \"TitleArch\", Vector3.new(0, Y, s.MaxZ), 100," not in read(WORLD / "Street.luau"):
    errors.append("[street] title arch placement changed: update world_bounds")
all_inside(arch_pillars, R("Street+Plaza", PLAZA["MinX"], PLAZA["MaxX"], STREET["MinZ"], PLAZA["MaxZ"]), "title arch")
clear(arch_pillars, street_mouth, "title arch vs plaza mouth")
no_overlap(arch_pillars + [r for r in pl_items if r.name.startswith(("Spawn", "Track", "Shop", "CornerTree"))], "title arch vs plaza")

# --- plaza: lawn bushes outside the runaway roam rectangle (lawn inset 4), squirrel loop on the track
roam = R("RunawayRoam", LAWN[0] + 4, LAWN[1] - 4, LAWN[2] + 4, LAWN[3] - 4)
bush_in = float(grab(r"\{ l\.MinX \+ (\d+), l\.MinZ \+ \d+ \}", ptxt, "lawn bush inset").group(1))
lawn_bushes = [box(f"LawnBush{n}", x, z, 6 * 0.6, 5 * 0.6) for n, (x, z) in enumerate(
    [(LAWN[0] + bush_in, LAWN[2] + bush_in), (LAWN[1] - bush_in, LAWN[2] + bush_in),
     (LAWN[0] + bush_in, LAWN[3] - bush_in), (LAWN[1] - bush_in, LAWN[3] - bush_in)], 1)]
clear(lawn_bushes, roam, "plaza runaway roam")
all_inside(lawn_bushes, lawn_r, "plaza lawn bushes")
sq = [(tx0 + TRACK_W / 2, tz0 + TRACK_W / 2), (tx1 - TRACK_W / 2, tz0 + TRACK_W / 2),
      (tx1 - TRACK_W / 2, tz1 - TRACK_W / 2), (tx0 + TRACK_W / 2, tz1 - TRACK_W / 2)]
for n, (x, z) in enumerate(sq, 1):
    checks += 1
    if not any(box("wp", x, z, 1, 1).inside(t) for t in track_parts):
        errors.append(f"[plaza] squirrel corner {n} ({x},{z}) not on the track")
blockers = [r for r in pl_items if not r.name.startswith(("Track", "Lawn", "SprintPillar"))]
for n, (x, z) in enumerate(sq, 1):
    nx, nz = sq[n % 4]
    seg = R(f"SquirrelSeg{n}", min(x, nx) - 1, max(x, nx) + 1, min(z, nz) - 1, max(z, nz) + 1)
    clear(blockers, seg, "squirrel path")

# --- field: server landing X stays in the clear lane; markers/arch pillars/band decor are outside it
tstxt = read(SVC / "ThrowService.luau")
checks += 1
if "local laneHalf = (Layout.Field.MaxX - Layout.Field.MinX) * 0.25 - 4" not in tstxt:
    errors.append("[field] ThrowService landing X is no longer clamped into the centre lane")
LAND = R("LandingLane", FIELD_CX - (LANE_HALF - 4), FIELD_CX + (LANE_HALF - 4), wall_z, FIELD["MaxZ"])
clear(markers + arches, LAND, "landing lane")
checks += 1
if "d.CanQuery = false" not in read(WORLD / "Props.luau"):
    errors.append("[field] arch parts must be CanQuery=false (they span the lane; cutscene raycasts the landing)")

# --- zone decorators: every Kit.Band/Apron item's footprint half-extent must fit inside its margin, so it
#     never crosses the lane edge / field edge / zone ends. Kit.pick also records each footprint in ctx.Taken.
FOOTPRINT = {  # zone -> half-extents in call order (worst case over scale + yaw), measured from the module code
    "Backyard": [5.7, 6.0, 3.4, 1.0, 17.2],         # doghouse, tree s1.2, flower bed, toy | house
    "Park": [7.0, 3.6, 4.0, 1.3, 32.0, 11.0],       # tree s1.4, bush, bench, lamp | pond rim, tree s2.2
    "Beach": [11.8, 4.5, 1.3, 4.2, 8.0],            # palm, umbrella+towel, ball, castle | rock
    "Farm": [18.0, 2.7, 3.0, 27.0],                 # crop patch, hay bale, scarecrow | barn + silo
    "Forest": [7.7, 4.7, 1.7, 14.4],                # pine s1.6, log, mushroom | pine s3
    "SnowyPeaks": [7.2, 2.2, 2.0, 36.2],            # snow pine, snowman, ice | mountain s1.3
    "CityRooftops": [4.3, 4.3, 4.0, 13.6],          # vent, water tank, neon sign | tower (axis-aligned)
    "SpaceStation": [9.0, 0.8, 2.9, 5.0, 27.5],     # dome ring, antenna, crate, dish | planet (rings are sky decor)
    "MythicMeadow": [3.7, 3.5, 2.8, 30.0],          # crystal, flower, pillar | island (floating)
}
for zid, _, _ in ZONES:
    ztxt = read(WORLD / f"Zones/{zid}.luau")
    calls = re.findall(r"Kit\.(Band|Apron)\(ctx,\s*(\d+),\s*(\d+)(?:,\s*(\d+))?\)", ztxt)
    fp = FOOTPRINT[zid]
    checks += 1
    if len(calls) != len(fp):
        errors.append(f"[decor {zid}] {len(calls)} Kit calls but {len(fp)} footprints recorded: update FOOTPRINT")
        continue
    for (kind, _cnt, _sp, margin), ext in zip(calls, fp):
        m = float(margin or (4 if kind == "Band" else 8))
        checks += 1
        if ext > m + 1e-6:
            errors.append(f"[decor {zid}] {kind} item footprint {ext} exceeds its margin {m} (crosses lane/field/zone edge)")
for zid in ("Backyard", "Farm"):  # lane-edge fences at LaneHalf + 1.5, post radius 0.55
    checks += 1
    if "Kit.LaneHalf + 1.5" not in read(WORLD / f"Zones/{zid}.luau") or LANE_HALF + 1.5 - 0.55 <= LANE_HALF:
        errors.append(f"[decor {zid}] lane fence moved into the lane")
ktxt2 = read(WORLD / "Zones/Kit.luau")
checks += 1
if "table.insert(takenList" not in ktxt2 or "math.max(spacing * 0.4, radius)" not in ktxt2:
    errors.append("[decor] Kit.pick must record footprints in ctx.Taken and avoid markers by footprint radius")

# --- (b) project structure: Rojo instance paths, remotes, tags/attributes
import json
proj = json.loads(read(ROOT / "default.project.json"))
mapping = {"src/shared": "ReplicatedStorage.Shared", "src/server": "ServerScriptService.Server",
           "src/client": "StarterPlayer.StarterPlayerScripts.Client"}
tree = proj["tree"]
checks += 1
if (tree["ReplicatedStorage"]["Shared"]["$path"], tree["ServerScriptService"]["Server"]["$path"],
        tree["StarterPlayer"]["StarterPlayerScripts"]["Client"]["$path"]) != tuple(mapping):
    errors.append("[rojo] default.project.json mapping differs from the contract")
inst_paths: dict[str, str] = {}
for f in sorted(SRC.rglob("*")):
    if not f.is_file() or f.suffix not in (".luau", ".lua", ".json", ".txt", ".csv", ".model.json", ".rbxm", ".rbxmx", ".toml"):
        continue
    rel = f.relative_to(ROOT).as_posix()
    root = next(k for k in mapping if rel.startswith(k + "/"))
    name = f.name
    for suf in (".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua", ".json", ".txt", ".csv"):
        if name.endswith(suf):
            name = name[: -len(suf)]
            break
    if name == "init":
        name = ""
    inst = mapping[root] + "." + ".".join(p for p in (rel[len(root) + 1:].split("/")[:-1] + [name]) if p)
    key = inst.lower()  # Studio lookups are case-sensitive, but case-only twins break on case-insensitive filesystems
    checks += 1
    if key in inst_paths:
        errors.append(f"[rojo] {rel} and {inst_paths[key]} both map to {inst}")
    inst_paths[key] = rel
rtxt = read(SRC / "shared/Remotes.luau")
names = re.findall(r'"(\w+)"', grab(r"Remotes\.Events\s*=\s*\{(.*?)\}", rtxt, "Events").group(1)) + \
    re.findall(r'"(\w+)"', grab(r"Remotes\.Functions\s*=\s*\{(.*?)\}", rtxt, "Functions").group(1))
checks += 1
if len(names) != len(set(names)):
    errors.append(f"[remotes] duplicate remote names: {sorted(n for n in names if names.count(n) > 1)}")
for f in SRC.rglob("*.luau"):
    for used in re.findall(r'Remotes\.Get\("(\w+)"\)', read(f)):
        checks += 1
        if used not in names:
            errors.append(f"[remotes] {f.relative_to(ROOT)} uses undefined remote {used}")
    if f.name != "Remotes.luau":
        checks += 1
        if re.search(r'Instance\.new\("(Remote|UnreliableRemote)(Event|Function)"\)', read(f)):
            errors.append(f"[remotes] {f.relative_to(ROOT)} creates its own remote outside Remotes.luau")
TAG_ATTRS = {"YardPlot": {"YardIndex"}, "YardSign": {"YardIndex"}, "DogSpot": {"YardIndex", "SpotIndex"},
             "KennelSign": {"YardIndex"}, "TrophySpot": {"YardIndex"}, "ThrowPad": {"PadIndex"},
             "TrainingStation": {"StationId"}, "ShopStand": {"ShopId"}, "Leaderboard": set(), "PlazaSpawn": set(),
             "RunawayArea": set(), "SquirrelPath": {"Order"}, "ZoneBand": {"ZoneId", "MinDistance", "MaxDistance", "ZoneName"},
             "DistanceMarker": {"Distance"}}
seen_tags: dict[str, set[str]] = {}
for f in WORLD.rglob("*.luau"):
    for tag, attrs in re.findall(r'Props\.Tag\(\w+, "(\w+)"(?:, \{([^}]*)\})?\)', read(f)):
        a = set(re.findall(r"(\w+)\s*=", attrs))
        checks += 1
        if tag in seen_tags and seen_tags[tag] != a:
            errors.append(f"[tags] {tag} created with conflicting attributes {seen_tags[tag]} vs {a}")
        seen_tags[tag] = a
for tag, want in TAG_ATTRS.items():
    checks += 1
    if tag not in seen_tags:
        errors.append(f"[tags] world never creates tag {tag}")
    elif seen_tags[tag] != want:
        errors.append(f"[tags] {tag} attributes {seen_tags[tag]} != contract {want}")
runtime_tags = {"YardDog", "RunawayDog", "Squirrel"}
for f in SRC.rglob("*.luau"):
    for tag in re.findall(r'(?:GetTagged|GetInstanceAddedSignal|HasTag)\("(\w+)"\)', read(f)):
        checks += 1
        if tag not in TAG_ATTRS and tag not in runtime_tags:
            errors.append(f"[tags] {f.relative_to(ROOT)} reads unknown tag {tag}")
    for tag in re.findall(r'AddTag\(\w+, "(\w+)"\)', read(f)):
        checks += 1
        if tag in TAG_ATTRS:
            errors.append(f"[tags] {f.relative_to(ROOT)} adds world-contract tag {tag} at runtime")

# ---------------------------------------------------------------- report
total_rects = len(floors) + YARD_COUNT * 21 + len(pl_items) + len(pads) + len(markers) + len(arches)
print(f"world_bounds: {len(ZONES)} zones, {len(yards)} yards, {total_rects} rectangles, {checks} checks")
print(f"  crossbar {crossbar}")
print(f"  street   {street}")
print(f"  plaza    {plaza}")
print(f"  field    {field}  (centre lane |x| < {LANE_HALF:g}, wall at z {wall_z:g})")
for b in bands:
    print(f"    {b}")
if errors:
    print(f"\nFAIL: {len(errors)} problem(s)")
    for e in errors:
        print("  - " + e)
    sys.exit(1)
print("OK: no unintended overlaps")
