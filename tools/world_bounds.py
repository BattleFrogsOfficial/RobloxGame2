#!/usr/bin/env python3
"""World bounds quick check (agent D) -- static, no Lune needed.

Parses src/shared/Config/Layout.luau (+ Zones.luau, World/Walls.luau constants) and asserts the
map-level contract of the compact T layout:
  * yard / street / plaza / field rectangles tile without overlapping, field starts at the throw line,
  * two levels: the hub (yards, street, plaza, shop, training, throw zone) is on the plateau at Layout.HubY,
    40 studs above the field at Layout.GroundY,
  * the brown throw zone (Layout.ThrowZone) is flush with the plateau (Y = ThrowLine.Y = HubY) with its front edge
    MaxZ on ThrowLine.Z (the cliff edge), inside the plaza; Layout.Platform keeps only ThrowSpot (= the zone centre),
    no QueueSpots / StandRadius,
  * shop, training, the runaway lawn and the throw zone are inside the plaza and do not overlap each other,
  * zone bands are contiguous and end at Layout.Field.MaxZ,
  * the scenery walls stay outside the field (+ margin),
  * straight-line walking estimates (gate -> street -> plaza opening -> target) are <= 300 studs.

The FULL check (real headless build of every part, tags on their ground, spawn clearance, overlap of
every part, grid path-finding around obstacles) is the Lune harness:
    lune run tools/worldcheck/run.luau -- [--no-field]
Run this one with:  python3 tools/world_bounds.py
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "src/shared/Config"
WORLD = ROOT / "src/server/World"
NUM = r"-?\d+(?:\.\d+)?"

fails: list[str] = []
checks = 0


def check(ok: bool, msg: str) -> None:
    global checks
    checks += 1
    if not ok:
        fails.append(msg)


def grab(pattern: str, text: str, what: str) -> re.Match:
    m = re.search(pattern, text, re.S)
    if not m:
        sys.exit(f"PARSE ERROR: could not find {what}")
    return m


def nums(s: str) -> list[float]:
    return [float(x) for x in re.findall(NUM, s)]


def vec(s: str) -> list[list[float]]:
    return [nums(m) for m in re.findall(r"Vector3\.new\(([^)]*)\)", s)]


lay = (CFG / "Layout.luau").read_text(encoding="utf-8")
HUB_Y = float(re.search(rf"Layout\.HubY\s*=\s*({NUM})", lay).group(1)) if re.search(r"Layout\.HubY\s*=", lay) else None
GROUND_Y = float(re.search(rf"Layout\.GroundY\s*=\s*({NUM})", lay).group(1))
if HUB_Y is None:
    sys.exit("PARSE ERROR: Layout.HubY missing")
lay = lay.replace("Layout.HubY", repr(HUB_Y)).replace("Layout.GroundY", repr(GROUND_Y))


def block(name: str) -> str:
    one_line = re.search(rf"Layout\.{name}\s*=\s*\{{[^\n]*\}}", lay)
    if one_line:
        return one_line.group(0)
    return grab(rf"Layout\.{name}\s*=\s*\{{(.*?)\n\}}", lay, f"Layout.{name}").group(0)


def rect(name: str) -> dict[str, float]:
    return {k: float(v) for k, v in re.findall(rf"(\w+)\s*=\s*({NUM})", block(name))}


yb = block("Yards")
YW, _, YD = vec(grab(r"Size\s*=\s*Vector3\.new\([^)]*\)", yb, "Yards.Size").group(0))[0]
YCZ = float(grab(rf"CenterZ\s*=\s*({NUM})", yb, "Yards.CenterZ").group(1))
YCX = nums(grab(r"CentersX\s*=\s*\{([^}]*)\}", yb, "Yards.CentersX").group(1))
STREET, PLAZA, FIELD = rect("Street"), rect("Plaza"), rect("Field")
TL = rect("ThrowLine")
TZ = rect("ThrowZone")
pb = block("Platform")
P_SPOT = nums(grab(r"ThrowSpot\s*=\s*Vector3\.new\(([^)]*)\)", pb, "Platform.ThrowSpot").group(1))
SHOP = nums(grab(r"Layout\.Shop\s*=\s*\{\s*Center\s*=\s*Vector3\.new\(([^)]*)\)", lay, "Shop").group(1))
TRAIN = nums(grab(r"Layout\.Training\s*=\s*\{\s*Center\s*=\s*Vector3\.new\(([^)]*)\)", lay, "Training").group(1))

zones = (CFG / "Zones.luau").read_text(encoding="utf-8")
ZONES = [(m.group(1), float(m.group(2)), float(m.group(3)))
         for m in re.finditer(r'Id\s*=\s*"(\w+)".*?MinDistance\s*=\s*(\d+),\s*MaxDistance\s*=\s*(\d+)', zones)]
walls = (WORLD / "Walls.luau").read_text(encoding="utf-8")
WALL_X = float(grab(rf"Walls\.InnerX\s*=\s*({NUM})", walls, "Walls.InnerX").group(1))


def R(minx, maxx, minz, maxz):
    return (minx, maxx, minz, maxz)


def overlap(a, b) -> bool:
    return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


def inside(a, b) -> bool:
    return a[0] >= b[0] and a[1] <= b[1] and a[2] >= b[2] and a[3] <= b[3]


# ---------------------------------------------------------------- floors
floors = {f"Yard{i + 1}": R(x - YW / 2, x + YW / 2, YCZ - YD / 2, YCZ + YD / 2) for i, x in enumerate(YCX)}
floors["Street"] = R(STREET["MinX"], STREET["MaxX"], STREET["MinZ"], STREET["MaxZ"])
floors["Plaza"] = R(PLAZA["MinX"], PLAZA["MaxX"], PLAZA["MinZ"], PLAZA["MaxZ"])
floors["Field"] = R(FIELD["MinX"], FIELD["MaxX"], FIELD["MinZ"], FIELD["MaxZ"])
names = list(floors)
for i, a in enumerate(names):
    for b in names[i + 1:]:
        check(not overlap(floors[a], floors[b]), f"floors overlap: {a} / {b}")
for i in range(len(YCX)):
    y = floors[f"Yard{i + 1}"]
    check(y[3] == STREET["MinZ"] and y[0] >= STREET["MinX"] and y[1] <= STREET["MaxX"], f"Yard{i + 1} gate not on the street")
check(STREET["MaxZ"] == PLAZA["MinZ"], "plaza does not open off the street")
check(FIELD["MinZ"] == TL["Z"] == PLAZA["MaxZ"], "Field.MinZ / ThrowLine.Z / Plaza.MaxZ must match")

# ---------------------------------------------------------------- levels
check(HUB_Y - GROUND_Y >= 40, f"hub plateau HubY {HUB_Y} must be 40 studs above GroundY {GROUND_Y}")
for name in ("Yards", "Street", "Plaza"):
    y = re.search(rf"\bY\s*=\s*({NUM})", block(name))
    check(y is not None and float(y.group(1)) == HUB_Y, f"Layout.{name}.Y must be HubY")
check(SHOP[1] == HUB_Y and TRAIN[1] == HUB_Y, "shop / training centres must be at HubY")
check("RampBottom" not in pb and "RampTop" not in pb, "no ramp (remove RampBottom / RampTop)")
check("QueueSpots" not in pb and "StandRadius" not in pb, "the queue is gone: remove Platform.QueueSpots / StandRadius")

# ---------------------------------------------------------------- throw zone
zone = R(TZ["MinX"], TZ["MaxX"], TZ["MinZ"], TZ["MaxZ"])
check(TZ["Y"] == TL["Y"] == HUB_Y, "throw zone surface must be ThrowLine.Y = HubY (flush)")
check(abs(zone[3] - TL["Z"]) < 1e-6, "throw zone MaxZ must be ThrowLine.Z (the cliff edge)")
check(zone[1] - zone[0] >= 60 and zone[3] - zone[2] >= 14, "throw zone too small to read as a zone")
check(abs(P_SPOT[0] - (zone[0] + zone[1]) / 2) < 1e-6 and abs(P_SPOT[2] - (zone[2] + zone[3]) / 2) < 1e-6
      and P_SPOT[1] == HUB_Y, "Platform.ThrowSpot must be the throw zone centre at HubY")
shop = R(SHOP[0] - 11, SHOP[0] + 11, SHOP[2] - 2, SHOP[2] + 12)  # Plaza.Shop: 22 wide, counter + 12 deep
train = R(TRAIN[0] - 12, TRAIN[0] + 12, TRAIN[2] - 12, TRAIN[2] + 13)  # 24-stud mat + sign
lawn = R(PLAZA["MinX"] + 4 - 1, -24 + 1, 18 - 1, TZ["MinZ"] - 4 + 1)  # Plaza.Lawn + its 1-stud edge
feats = {"throw zone": zone, "shop": shop, "training": train, "lawn": lawn}
for n, f in feats.items():
    check(inside(f, floors["Plaza"]), f"{n} is not inside the plaza")
fn = list(feats)
for i, a in enumerate(fn):
    for b in fn[i + 1:]:
        check(not overlap(feats[a], feats[b]), f"plaza features overlap: {a} / {b}")

# ---------------------------------------------------------------- zones + walls
prev = 0.0
for zid, lo, hi in ZONES:
    check(lo == prev, f"zone {zid} does not start where the previous ended")
    prev = hi
check(TL["Z"] + prev == FIELD["MaxZ"], "zone bands must end at Layout.Field.MaxZ")
check(WALL_X >= FIELD["MaxX"] + 40, f"walls (|x| = {WALL_X}) too close to the field")
check(WALL_X > STREET["MaxX"], "walls cut through the crossbar")

# ---------------------------------------------------------------- walk estimates (straight lines; flush zone, no ramp)
def ground(a, b) -> float:
    """a, b = (x, z). Street <-> plaza goes through the opening; the plateau is otherwise open."""
    ax, az = a
    bx, bz = b
    pts = [a]
    if (az <= STREET["MaxZ"]) != (bz <= STREET["MaxZ"]):  # street <-> plaza: through the opening
        street_pt = a if az <= STREET["MaxZ"] else b
        ox = max(PLAZA["MinX"] + 2, min(PLAZA["MaxX"] - 2, street_pt[0]))
        pts.append((ox, STREET["MaxZ"] - 1))
    pts.append(b)
    return sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


targets = {f"Gate{i + 1}": (x, YCZ + YD / 2 + 1.5) for i, x in enumerate(YCX)}
targets["Shop"] = (SHOP[0], SHOP[2] - 3.5)
targets["Training"] = (TRAIN[0], TRAIN[2])
worst = (0.0, "")
targets["Zone"] = (P_SPOT[0], P_SPOT[2])
targets["ZoneW"] = (zone[0] + 2, zone[2] + 2)
targets["ZoneE"] = (zone[1] - 2, zone[2] + 2)
tn = list(targets)
for i, a in enumerate(tn):
    for b in tn[i + 1:]:
        d = ground(targets[a], targets[b])
        check(d <= 300, f"walk {a} -> {b} ~{d:.0f} studs > 300")
        if d > worst[0]:
            worst = (d, f"{a} -> {b}")

print(f"world_bounds: {checks} checks; hub at Y {HUB_Y:g}, field at Y {GROUND_Y:g}, flush throw zone; worst walk estimate {worst[1]} {worst[0]:.0f} studs "
      f"({worst[0] / 32:.1f} s at WalkSpeed 32)")
print("(full part-level check: lune run tools/worldcheck/run.luau)")
if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS")
