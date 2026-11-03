#!/usr/bin/env python3
"""World bounds quick check (agent D) -- static, no Lune needed.

Parses src/shared/Config/Layout.luau (+ Zones.luau, World/Walls.luau constants) and asserts the
map-level contract of the compact T layout:
  * yard / street / plaza / field rectangles tile without overlapping, field starts at the throw line,
  * the platform deck sits at ThrowLine.Y with its front edge on ThrowLine.Z, StandRadius covers it,
    5 queue spots on the deck, ramp slope <= 35 degrees,
  * shop, training, ramp and deck are inside the plaza and do not overlap each other,
  * zone bands are contiguous and end at Layout.Field.MaxZ,
  * the scenery walls stay outside the field (+ margin),
  * straight-line walking estimates (gate -> street -> around the ramp foot -> target) are <= 300 studs.

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
pb = block("Platform")


def pvec(key: str) -> list[float]:
    return nums(grab(rf"{key}\s*=\s*Vector3\.new\(([^)]*)\)", pb, f"Platform.{key}").group(1))


P_CENTER, P_SIZE, P_SPOT = pvec("Center"), pvec("Size"), pvec("ThrowSpot")
P_RB, P_RT = pvec("RampBottom"), pvec("RampTop")
P_RADIUS = float(grab(rf"StandRadius\s*=\s*({NUM})", pb, "StandRadius").group(1))
P_RAMPW = float(grab(rf"RampWidth\s*=\s*({NUM})", pb, "RampWidth").group(1))
P_QUEUE = vec(grab(r"QueueSpots\s*=\s*\{(.*?)\n\t\}", pb, "QueueSpots").group(1))
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

# ---------------------------------------------------------------- platform
deck = R(P_CENTER[0] - P_SIZE[0] / 2, P_CENTER[0] + P_SIZE[0] / 2, P_CENTER[2] - P_SIZE[2] / 2, P_CENTER[2] + P_SIZE[2] / 2)
check(P_CENTER[1] == TL["Y"] and TL["Y"] >= 40, "deck surface must be ThrowLine.Y (>= 40)")
check(abs(deck[3] - TL["Z"]) < 1e-6, "deck front edge must be ThrowLine.Z")
check(abs(P_SPOT[2] - deck[3]) <= 6 and P_SPOT[1] == TL["Y"], "ThrowSpot must be at the deck front, on the deck")
for cx, cz in ((deck[0], deck[2]), (deck[0], deck[3]), (deck[1], deck[2]), (deck[1], deck[3])):
    check(math.hypot(cx - P_SPOT[0], cz - P_SPOT[2]) <= P_RADIUS, "StandRadius does not cover the deck")
check(len(P_QUEUE) == 5, "need 5 queue spots")
for q in P_QUEUE:
    check(deck[0] < q[0] < deck[1] and deck[2] < q[2] < deck[3] and q[1] == TL["Y"], f"queue spot {q} not on the deck")
slope = math.degrees(math.atan((P_RT[1] - P_RB[1]) / (P_RT[2] - P_RB[2])))
check(slope <= 35, f"ramp slope {slope:.1f} > 35 deg")
check(P_RT[2] == deck[2], "ramp top must meet the deck back edge")
ramp = R(P_RB[0] - P_RAMPW / 2 - 1, P_RB[0] + P_RAMPW / 2 + 1, P_RB[2], P_RT[2])
shop = R(SHOP[0] - 11, SHOP[0] + 11, SHOP[2] - 2, SHOP[2] + 12)  # Plaza.Shop: 22 wide, counter + 12 deep
train = R(TRAIN[0] - 12, TRAIN[0] + 12, TRAIN[2] - 12, TRAIN[2] + 13)  # 24-stud mat + sign
feats = {"deck": deck, "ramp": ramp, "shop": shop, "training": train}
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

# ---------------------------------------------------------------- walk estimates (straight lines via the ramp foot)
foot = (P_RB[0], P_RB[2] - 1.5)
ramp_len = math.dist((P_RB[1], P_RB[2]), (P_RT[1], P_RT[2])) + math.dist((P_RT[0], P_RT[2]), (P_SPOT[0], P_SPOT[2]))
edge = P_RAMPW / 2 + 2


def ground(a, b) -> float:
    """a, b = (x, z). Paths between plaza halves go around the ramp foot; street<->plaza via the opening."""
    ax, az = a
    bx, bz = b
    pts = [a]
    if az > STREET["MaxZ"] and bz > STREET["MaxZ"] and ax * bx < 0:  # opposite plaza halves: round the ramp foot
        pts += [(math.copysign(edge, ax), STREET["MaxZ"] - 2), (math.copysign(edge, bx), STREET["MaxZ"] - 2)]
    elif (az <= STREET["MaxZ"]) != (bz <= STREET["MaxZ"]):  # street <-> plaza: through the opening
        street_pt, plaza_pt = (a, b) if az <= STREET["MaxZ"] else (b, a)
        ox = max(PLAZA["MinX"] + 2, min(PLAZA["MaxX"] - 2, street_pt[0]))
        if plaza_pt[1] > STREET["MaxZ"] and abs(plaza_pt[0]) > edge and abs(ox) < edge:
            ox = math.copysign(edge, plaza_pt[0])
        pts += [(ox, STREET["MaxZ"] - 1)]
        if street_pt is b:
            pts = [a, pts[-1]]
    pts.append(b)
    return sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


targets = {f"Gate{i + 1}": (x, YCZ + YD / 2 + 1.5) for i, x in enumerate(YCX)}
targets["Shop"] = (SHOP[0], SHOP[2] - 3.5)
targets["Training"] = (TRAIN[0], TRAIN[2])
worst = (0.0, "")
tn = list(targets) + ["Platform"]
for i, a in enumerate(tn):
    for b in tn[i + 1:]:
        if b == "Platform":
            d = ground(targets[a], foot) + 1.5 + ramp_len
        else:
            d = ground(targets[a], targets[b])
        check(d <= 300, f"walk {a} -> {b} ~{d:.0f} studs > 300")
        if d > worst[0]:
            worst = (d, f"{a} -> {b}")

print(f"world_bounds: {checks} checks; ramp {slope:.1f} deg; worst walk estimate {worst[1]} {worst[0]:.0f} studs "
      f"({worst[0] / 32:.1f} s at WalkSpeed 32)")
print("(full part-level check: lune run tools/worldcheck/run.luau)")
if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS")
