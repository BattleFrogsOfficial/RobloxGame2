#!/usr/bin/env python3
"""Throw a Ball for Dogs dog roster tool.

Usage:
    python3 tools/roster.py check   # validate data/zones/*.csv, nonzero exit on failure
    python3 tools/roster.py build   # check, then write src/shared/Data/Dogs.luau + data/Roster.xlsx

Source of truth: data/zones/<ZoneId>.csv (80 rows per zone).
Zone base incomes are parsed from src/shared/Config/Zones.luau and rarity numbers
from src/shared/Config/Rarities.luau, so a balance pass there flows through on rebuild
(edit the income column, then check).
"""
from __future__ import annotations

import csv
import math
import os
import re
import sys
from itertools import combinations

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONES_DIR = os.path.join(ROOT, "data", "zones")
ZONES_LUAU = os.path.join(ROOT, "src", "shared", "Config", "Zones.luau")
RARITIES_LUAU = os.path.join(ROOT, "src", "shared", "Config", "Rarities.luau")
OUT_LUAU = os.path.join(ROOT, "src", "shared", "Data", "Dogs.luau")
OUT_XLSX = os.path.join(ROOT, "data", "Roster.xlsx")

# --------------------------------------------------------------------------------------
# VOCABULARY (also emitted into Dogs.luau as Dogs.Vocab)
# --------------------------------------------------------------------------------------
BODIES = [
    "toy", "small_terrier", "long_low", "small_fluffy", "corgi_type", "medium_lean",
    "medium_stocky", "medium_fluffy", "large_lean", "large_athletic", "large_fluffy",
    "giant", "giant_fluffy", "poodle_type",
]

# Natural markings: allowed at every rarity (Commons use only these).
PATTERNS_NATURAL = [
    "none", "socks", "blaze", "mask", "saddle", "tuxedo", "tan_points", "eye_patch",
    "merle", "brindle", "spotted", "ticked", "sable", "piebald", "roan", "dapple", "harlequin",
]
# Stylised patterns: Uncommon and up.
PATTERNS_FANCY = [
    "tiger_stripe", "star_freckles", "sunburst", "frost_tips", "lightning_streak",
    "wave_stripes", "leaf_dapple", "heart_patch", "checker", "polka_dots", "ember_tips", "zigzag",
]
# Unique coat textures: Legendary (each used by exactly one Legendary) and Mythic.
PATTERNS_TEXTURE = [
    "galaxy_swirl", "lava_crackle", "aurora_shimmer", "marble_veins", "crystal_facets",
    "stardust", "storm_cloud", "molten_metal", "opal_sheen", "coral_reef", "bark_rings",
    "circuit_lines", "nebula", "ice_glaze", "flame_lick", "moss_velvet", "tidal_foam",
    "rose_vine", "sunflare", "petal_storm", "neon_grid", "honeycomb", "thunder_scales",
    "pearl_luster",
]
PATTERNS = PATTERNS_NATURAL + PATTERNS_FANCY + PATTERNS_TEXTURE

# Everyday accessories: Rare and up.
ACCESSORIES_REGULAR = [
    "bandana", "collar_bell", "sunglasses", "lifeguard_whistle", "straw_hat", "scarf",
    "goggles", "beanie", "bow_tie", "flower_crown", "raincoat", "life_vest", "backpack",
    "headphones", "baseball_cap", "monocle", "top_hat", "saddlebag", "spiked_collar",
    "earmuffs", "snow_boots", "aviator_cap", "space_helmet", "cowbell", "leaf_wreath",
    "pearl_necklace", "hard_hat", "chef_hat", "sailor_cap", "hoodie", "lantern",
    "tool_belt", "binoculars", "ranger_hat", "antenna_headband",
]
# Signature accessories: required for Epic, allowed for Legendary/Mythic.
ACCESSORIES_SIGNATURE = [
    "cape", "crown", "captain_hat", "wizard_hat", "knight_helm", "pirate_hat",
    "laurel_wreath", "royal_collar", "rune_collar", "star_cloak", "crystal_tiara",
    "samurai_helm", "astronaut_suit", "jet_pack", "trident", "sheriff_star",
]
ACCESSORIES = ["none"] + ACCESSORIES_REGULAR + ACCESSORIES_SIGNATURE

VFX = ["none", "sparkle", "aura", "full"]

UNIQUE_PARTS = [
    "two_heads", "three_heads", "wings", "halo", "horns", "flame_mane", "star_tail",
    "crystal_spikes", "antlers", "nine_tails", "third_eye", "fins", "unicorn_horn",
    "ghost_tail", "shell_back", "ring_orbit", "cloud_paws", "leaf_mane",
]

RARITY_ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
RARITY_LETTER = {"Common": "c", "Uncommon": "u", "Rare": "r", "Epic": "e", "Legendary": "l", "Mythic": "m"}
REQUIRED_VFX = {"Common": "none", "Uncommon": "none", "Rare": "none", "Epic": "sparkle",
                "Legendary": "aura", "Mythic": "full"}
# Zone exceptions to Rarities.Tiers[*].PerZone
ZONE_COUNT_OVERRIDES = {"MythicMeadow": {"Common": 53, "Mythic": 2}}

# Variant words never appear in names (variants are badges). Real breed names allowlisted.
BANNED_NAME_TOKENS = {"gold", "golden", "shadow", "shadows", "shadowy", "rainbow", "rainbows"}
BANNED_NAME_ALLOW = {"golden retriever", "goldendoodle"}

COLUMNS = ["id", "zone", "rarity", "order_in_tier", "name", "body", "scale", "coat_primary",
           "coat_secondary", "pattern", "accessory", "vfx", "unique_parts", "income", "flavor"]

DELTA_E_SIMILAR = 12.0
NAME_RATIO_LIMIT = 0.85


# --------------------------------------------------------------------------------------
# Config parsing
# --------------------------------------------------------------------------------------
def load_zones():
    text = open(ZONES_LUAU, encoding="utf-8").read()
    zones = []
    for m in re.finditer(r'Id\s*=\s*"(\w+)",\s*Name\s*=\s*"([^"]+)",\s*Order\s*=\s*(\d+).*?BaseIncome\s*=\s*([\d.]+)',
                         text, re.S):
        zones.append({"Id": m.group(1), "Name": m.group(2), "Order": int(m.group(3)),
                      "BaseIncome": float(m.group(4))})
    zones.sort(key=lambda z: z["Order"])
    if len(zones) != 9:
        raise SystemExit(f"expected 9 zones in Zones.luau, parsed {len(zones)}")
    return zones


def load_rarities():
    text = open(RARITIES_LUAU, encoding="utf-8").read()
    tiers = {}
    pat = (r'(\w+)\s*=\s*\{\s*Odds\s*=\s*([\d.]+),\s*Catch\s*=\s*([\d.]+),\s*IncomeMult\s*=\s*([\d.]+),'
           r'\s*Color\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\),\s*PerZone\s*=\s*(\d+)')
    for m in re.finditer(pat, text):
        tiers[m.group(1)] = {"Odds": float(m.group(2)), "Catch": float(m.group(3)),
                             "IncomeMult": float(m.group(4)),
                             "Color": (int(m.group(5)), int(m.group(6)), int(m.group(7))),
                             "PerZone": int(m.group(8))}
    variants = {}
    for m in re.finditer(r'(Gold|Shadow|Rainbow)\s*=\s*\{\s*Chance\s*=\s*([\d.]+),\s*IncomeMult\s*=\s*([\d.]+)', text):
        variants[m.group(1)] = {"Chance": float(m.group(2)), "IncomeMult": float(m.group(3))}
    missing = [r for r in RARITY_ORDER if r not in tiers]
    if missing:
        raise SystemExit(f"Rarities.luau missing tiers: {missing}")
    return tiers, variants


def expected_counts(zone_id, tiers):
    c = {r: tiers[r]["PerZone"] for r in RARITY_ORDER}
    c.update(ZONE_COUNT_OVERRIDES.get(zone_id, {}))
    return c


# --------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------
def norm_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def levenshtein_within(a: str, b: str, k: int) -> int:
    """Levenshtein distance, early exit returning k+1 when it exceeds k."""
    if abs(len(a) - len(b)) > k:
        return k + 1
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        best = i
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
            if cur[j] < best:
                best = cur[j]
        if best > k:
            return k + 1
        prev = cur
    return prev[-1]


def hex_to_rgb(h: str):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def rgb_to_lab(rgb):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.0
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(h1, h2):
    a, b = rgb_to_lab(hex_to_rgb(h1)), rgb_to_lab(hex_to_rgb(h2))
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def expected_income(base, mult, order, count):
    offset = 0.0 if count <= 1 else 0.2 * (order - 1) / (count - 1)
    return round(base * mult * (1 + offset), 2)


def load_rows(zones):
    rows = []
    errors = []
    for z in zones:
        path = os.path.join(ZONES_DIR, f"{z['Id']}.csv")
        if not os.path.exists(path):
            errors.append(f"missing {os.path.relpath(path, ROOT)}")
            continue
        with open(path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            if reader.fieldnames != COLUMNS:
                errors.append(f"{z['Id']}.csv: header must be {','.join(COLUMNS)}")
                continue
            for i, r in enumerate(reader, 2):
                r["_line"] = f"{z['Id']}.csv:{i}"
                try:
                    r["order_in_tier"] = int(r["order_in_tier"])
                    r["scale"] = float(r["scale"])
                    r["income"] = float(r["income"])
                except ValueError as e:
                    errors.append(f"{r['_line']}: bad number ({e})")
                    continue
                r["unique_parts"] = [p for p in r["unique_parts"].split(";") if p] if r["unique_parts"] else []
                rows.append(r)
    return rows, errors


# --------------------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------------------
def run_check(verbose=True):
    zones = load_zones()
    tiers, _ = load_rarities()
    zone_by_id = {z["Id"]: z for z in zones}
    rows, errors = load_rows(zones)
    similar = []
    near_names = []
    hexre = re.compile(r"^#[0-9A-F]{6}$")

    # ---- counts
    for z in zones:
        exp = expected_counts(z["Id"], tiers)
        zr = [r for r in rows if r["zone"] == z["Id"]]
        if len(zr) != sum(exp.values()):
            errors.append(f"{z['Id']}: {len(zr)} dogs, expected {sum(exp.values())}")
        for rar in RARITY_ORDER:
            tier_rows = [r for r in zr if r["rarity"] == rar]
            if len(tier_rows) != exp[rar]:
                errors.append(f"{z['Id']}: {len(tier_rows)} {rar}, expected {exp[rar]}")
            orders = sorted(r["order_in_tier"] for r in tier_rows)
            if orders != list(range(1, len(tier_rows) + 1)):
                errors.append(f"{z['Id']} {rar}: order_in_tier must be 1..{len(tier_rows)}")
            # income
            n = len(tier_rows)
            for r in tier_rows:
                want = expected_income(z["BaseIncome"], tiers[rar]["IncomeMult"], r["order_in_tier"], n)
                if abs(r["income"] - want) > 0.0051:
                    errors.append(f"{r['_line']} {r['name']}: income {r['income']} != {want}")
            by_order = sorted(tier_rows, key=lambda r: r["order_in_tier"])
            for a, b in zip(by_order, by_order[1:]):
                if b["income"] < a["income"]:
                    errors.append(f"{z['Id']} {rar}: income not increasing at order {b['order_in_tier']}")

    # ---- per-row field validation
    ids = {}
    names = {}
    legendary_textures = {}
    combos = {}
    for r in rows:
        L = f"{r['_line']} {r['name']!r}"
        rar = r["rarity"]
        if rar not in RARITY_ORDER:
            errors.append(f"{L}: unknown rarity {rar}")
            continue
        if r["zone"] not in zone_by_id:
            errors.append(f"{L}: unknown zone {r['zone']}")
            continue
        want_id = f"{r['zone'].lower()}_{RARITY_LETTER[rar]}{r['order_in_tier']:02d}"
        if r["id"] != want_id:
            errors.append(f"{L}: id {r['id']} should be {want_id}")
        if r["id"] in ids:
            errors.append(f"{L}: duplicate id {r['id']} (also {ids[r['id']]})")
        ids[r["id"]] = r["_line"]
        # names
        if not r["name"].strip() or not r["name"].isascii():
            errors.append(f"{L}: name must be non-empty ASCII")
        nn = norm_name(r["name"])
        if nn in names:
            errors.append(f"{L}: name duplicates {names[nn]}")
        names[nn] = f"{r['name']} ({r['id']})"
        tokens = set(re.findall(r"[a-z]+", r["name"].lower()))
        if tokens & BANNED_NAME_TOKENS and r["name"].lower() not in BANNED_NAME_ALLOW:
            errors.append(f"{L}: name contains a variant word {sorted(tokens & BANNED_NAME_TOKENS)}")
        if not r["flavor"].strip() or not r["flavor"].isascii():
            errors.append(f"{L}: flavor must be non-empty ASCII")
        # vocab
        if r["body"] not in BODIES:
            errors.append(f"{L}: unknown body {r['body']}")
        if r["pattern"] not in PATTERNS:
            errors.append(f"{L}: unknown pattern {r['pattern']}")
        if r["accessory"] not in ACCESSORIES:
            errors.append(f"{L}: unknown accessory {r['accessory']}")
        if r["vfx"] not in VFX:
            errors.append(f"{L}: unknown vfx {r['vfx']}")
        for p in r["unique_parts"]:
            if p not in UNIQUE_PARTS:
                errors.append(f"{L}: unknown unique part {p}")
        for col in ("coat_primary", "coat_secondary"):
            if not hexre.match(r[col]):
                errors.append(f"{L}: {col} {r[col]!r} must be #RRGGBB (uppercase)")
        if not (0.6 <= r["scale"] <= 2.2):
            errors.append(f"{L}: scale {r['scale']} outside 0.6..2.2")
        # rarity visual budget
        if r["vfx"] != REQUIRED_VFX[rar]:
            errors.append(f"{L}: {rar} vfx must be {REQUIRED_VFX[rar]}")
        if rar != "Mythic" and r["unique_parts"]:
            errors.append(f"{L}: only Mythics have unique parts")
        if rar == "Mythic" and not r["unique_parts"]:
            errors.append(f"{L}: Mythic needs unique parts")
        if rar == "Common":
            if r["pattern"] not in PATTERNS_NATURAL:
                errors.append(f"{L}: Common pattern must be a natural marking")
            if r["accessory"] != "none":
                errors.append(f"{L}: Commons wear no accessory")
        elif rar == "Uncommon":
            if r["pattern"] == "none" or r["pattern"] in PATTERNS_TEXTURE:
                errors.append(f"{L}: Uncommon needs a natural/fancy pattern (not none/texture)")
            if r["accessory"] != "none":
                errors.append(f"{L}: Uncommons wear no accessory")
        elif rar == "Rare":
            if r["pattern"] in PATTERNS_TEXTURE:
                errors.append(f"{L}: Rare cannot use a Legendary texture")
            if r["accessory"] not in ACCESSORIES_REGULAR:
                errors.append(f"{L}: Rare needs an everyday accessory")
        elif rar == "Epic":
            if r["pattern"] in PATTERNS_TEXTURE:
                errors.append(f"{L}: Epic cannot use a Legendary texture")
            if r["accessory"] not in ACCESSORIES_SIGNATURE:
                errors.append(f"{L}: Epic needs a signature accessory")
        elif rar == "Legendary":
            if r["pattern"] not in PATTERNS_TEXTURE:
                errors.append(f"{L}: Legendary needs a unique coat texture")
            elif r["pattern"] in legendary_textures:
                errors.append(f"{L}: texture {r['pattern']} already used by {legendary_textures[r['pattern']]}")
            else:
                legendary_textures[r["pattern"]] = r["name"]
        key = (r["body"], r["coat_primary"], r["coat_secondary"], r["pattern"], r["accessory"])
        if key in combos:
            errors.append(f"{L}: identical look to {combos[key]} {key}")
        combos[key] = f"{r['name']} ({r['id']})"

    # ---- too-similar within zone
    for z in zones:
        zr = [r for r in rows if r["zone"] == z["Id"]]
        for a, b in combinations(zr, 2):
            if a["body"] != b["body"] or a["pattern"] != b["pattern"] or a["accessory"] != b["accessory"]:
                continue
            try:
                d1 = max(delta_e(a["coat_primary"], b["coat_primary"]), delta_e(a["coat_secondary"], b["coat_secondary"]))
                d2 = max(delta_e(a["coat_primary"], b["coat_secondary"]), delta_e(a["coat_secondary"], b["coat_primary"]))
            except ValueError:
                continue
            d = min(d1, d2)
            if d < DELTA_E_SIMILAR:
                similar.append(f"{z['Id']}: {a['name']} ~ {b['name']} [{a['body']}, {a['pattern']}, {a['accessory']}] dE={d:.1f}")

    # ---- similar names game-wide
    nlist = list(names.items())
    for (na, la), (nb, lb) in combinations(nlist, 2):
        m = max(len(na), len(nb))
        k = int(m * (1 - NAME_RATIO_LIMIT))  # ratio > 0.85  <=>  dist < m*0.15
        d = levenshtein_within(na, nb, k)
        if d <= k:
            ratio = 1 - d / m
            if ratio > NAME_RATIO_LIMIT:
                near_names.append(f"{la}  ~  {lb}  (ratio {ratio:.2f})")

    ok = not errors and not similar and not near_names
    if verbose:
        print("=" * 72)
        print("FETCH LEGENDS ROSTER CHECK")
        print("=" * 72)
        print(f"Dogs loaded: {len(rows)} across {len({r['zone'] for r in rows})} zones")
        hdr = "zone".ljust(14) + "".join(r[:4].rjust(6) for r in RARITY_ORDER) + "  total"
        print(hdr)
        for z in zones:
            zr = [r for r in rows if r["zone"] == z["Id"]]
            print(z["Id"].ljust(14) + "".join(str(sum(1 for r in zr if r["rarity"] == rr)).rjust(6)
                                              for rr in RARITY_ORDER) + str(len(zr)).rjust(7))
        bodies = {b: sum(1 for r in rows if r["body"] == b) for b in BODIES}
        print("Body usage: " + ", ".join(f"{b}={n}" for b, n in bodies.items()))
        print(f"Forms incl. variants: {len(rows) + 3 * sum(1 for r in rows if r['rarity'] != 'Common')}")
        print("-" * 72)
        print(f"Errors: {len(errors)}")
        for e in errors:
            print("  ERROR " + e)
        print(f"Too-similar look pairs (same zone/body/pattern/accessory, both coats dE<{DELTA_E_SIMILAR:.0f}): {len(similar)}")
        for s in similar:
            print("  SIMILAR " + s)
        print(f"Too-similar names (Levenshtein ratio > {NAME_RATIO_LIMIT}): {len(near_names)}")
        for s in near_names:
            print("  NAME " + s)
        print("-" * 72)
        print("RESULT: PASS" if ok else "RESULT: FAIL")
    return ok, rows, zones, tiers


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------
def luau_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def luau_list(items):
    return "{ " + ", ".join(luau_str(i) for i in items) + " }" if items else "{}"


def fmt_num(x: float) -> str:
    s = f"{x:.2f}".rstrip("0").rstrip(".")
    return s if s else "0"


def build_luau(rows, zones):
    order = {z["Id"]: z["Order"] for z in zones}
    rows = sorted(rows, key=lambda r: (order[r["zone"]], RARITY_ORDER.index(r["rarity"]), r["order_in_tier"]))
    out = []
    w = out.append
    w("--!strict")
    w("-- GENERATED by tools/roster.py build. DO NOT EDIT BY HAND.")
    w("-- Source: data/zones/<ZoneId>.csv  ->  python3 tools/roster.py check  ->  python3 tools/roster.py build")
    w("--")
    w("-- The module is the dog array itself (ipairs / #Dogs work) plus index fields:")
    w("--   Dogs.All            : { Dog }                         same array")
    w("--   Dogs.ById[id]       : Dog")
    w("--   Dogs.ByZone[zone]   : { Dog }                         ordered by rarity then order")
    w("--   Dogs.ByZoneRarity[zone][rarity] : { Dog }             for 'uniform within tier' rolls")
    w("--   Dogs.Vocab          : vocab lists (bodies, patterns, accessories, vfx, unique parts)")
    w("-- Income is base $/s for an ADULT dog before variant mult (puppy/variant handled by the server).")
    w("")
    w("export type Dog = {")
    w("\tId: string,")
    w("\tName: string,")
    w("\tZone: string,")
    w("\tRarity: string,")
    w("\tOrderInTier: number,")
    w("\tBody: string,")
    w("\tScale: number,")
    w("\tCoatPrimary: string, -- \"#RRGGBB\"")
    w("\tCoatSecondary: string, -- \"#RRGGBB\"")
    w("\tPattern: string,")
    w("\tAccessory: string, -- \"none\" when absent")
    w("\tVfx: string, -- none | sparkle | aura | full")
    w("\tUniqueParts: { string }, -- Mythic only")
    w("\tIncome: number,")
    w("\tFlavor: string,")
    w("}")
    w("")
    w("export type Vocab = {")
    for k in ("Bodies", "PatternsNatural", "PatternsFancy", "PatternsTexture", "Patterns",
              "AccessoriesRegular", "AccessoriesSignature", "Accessories", "Vfx", "UniqueParts", "Rarities"):
        w(f"\t{k}: {{ string }},")
    w("}")
    w("")
    w("export type DogsModule = {")
    w("\t[number]: Dog,")
    w("\tAll: { Dog },")
    w("\tById: { [string]: Dog },")
    w("\tByZone: { [string]: { Dog } },")
    w("\tByZoneRarity: { [string]: { [string]: { Dog } } },")
    w("\tVocab: Vocab,")
    w("\tCount: number,")
    w("}")
    w("")
    w("local Vocab: Vocab = {")
    for k, v in (("Bodies", BODIES), ("PatternsNatural", PATTERNS_NATURAL), ("PatternsFancy", PATTERNS_FANCY),
                 ("PatternsTexture", PATTERNS_TEXTURE), ("Patterns", PATTERNS),
                 ("AccessoriesRegular", ACCESSORIES_REGULAR), ("AccessoriesSignature", ACCESSORIES_SIGNATURE),
                 ("Accessories", ACCESSORIES), ("Vfx", VFX), ("UniqueParts", UNIQUE_PARTS),
                 ("Rarities", RARITY_ORDER)):
        w(f"\t{k} = {luau_list(v)},")
    w("}")
    w("")
    w("local list: { Dog } = {")
    cur_zone = None
    for r in rows:
        if r["zone"] != cur_zone:
            cur_zone = r["zone"]
            w(f"\t-- {cur_zone}")
        w("\t{ " + ", ".join([
            f"Id = {luau_str(r['id'])}", f"Name = {luau_str(r['name'])}", f"Zone = {luau_str(r['zone'])}",
            f"Rarity = {luau_str(r['rarity'])}", f"OrderInTier = {r['order_in_tier']}",
            f"Body = {luau_str(r['body'])}", f"Scale = {fmt_num(r['scale'])}",
            f"CoatPrimary = {luau_str(r['coat_primary'])}", f"CoatSecondary = {luau_str(r['coat_secondary'])}",
            f"Pattern = {luau_str(r['pattern'])}", f"Accessory = {luau_str(r['accessory'])}",
            f"Vfx = {luau_str(r['vfx'])}", f"UniqueParts = {luau_list(r['unique_parts'])}",
            f"Income = {fmt_num(r['income'])}", f"Flavor = {luau_str(r['flavor'])}",
        ]) + " },")
    w("}")
    w("")
    w("local ById: { [string]: Dog } = {}")
    w("local ByZone: { [string]: { Dog } } = {}")
    w("local ByZoneRarity: { [string]: { [string]: { Dog } } } = {}")
    w("for _, dog in list do")
    w("\tById[dog.Id] = dog")
    w("\tlocal zoneList: { Dog } = ByZone[dog.Zone] or {}")
    w("\tByZone[dog.Zone] = zoneList")
    w("\ttable.insert(zoneList, dog)")
    w("\tlocal byRarity: { [string]: { Dog } } = ByZoneRarity[dog.Zone] or {}")
    w("\tByZoneRarity[dog.Zone] = byRarity")
    w("\tlocal tierList: { Dog } = byRarity[dog.Rarity] or {}")
    w("\tbyRarity[dog.Rarity] = tierList")
    w("\ttable.insert(tierList, dog)")
    w("end")
    w("")
    w("local module: any = list")
    w("module.All = list")
    w("module.ById = ById")
    w("module.ByZone = ByZone")
    w("module.ByZoneRarity = ByZoneRarity")
    w("module.Vocab = Vocab")
    w(f"module.Count = {len(rows)}")
    w("")
    w("return module :: DogsModule")
    os.makedirs(os.path.dirname(OUT_LUAU), exist_ok=True)
    with open(OUT_LUAU, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")


def build_xlsx(rows, zones, tiers):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter

    def tint(rgb, f=0.65):
        return "".join(f"{int(c + (255 - c) * f):02X}" for c in rgb)

    fills = {r: PatternFill("solid", fgColor=tint(tiers[r]["Color"])) for r in RARITY_ORDER}
    head_fill = PatternFill("solid", fgColor="2B2D42")
    head_font = Font(bold=True, color="FFFFFF")
    headers = ["Id", "Zone", "Rarity", "Order", "Name", "Body", "Scale", "CoatPrimary", "CoatSecondary",
               "Pattern", "Accessory", "Vfx", "UniqueParts", "Income $/s", "Flavor"]
    widths = [16, 13, 11, 7, 28, 15, 7, 12, 13, 15, 18, 8, 26, 12, 70]
    order = {z["Id"]: z["Order"] for z in zones}
    srt = sorted(rows, key=lambda r: (order[r["zone"]], RARITY_ORDER.index(r["rarity"]), r["order_in_tier"]))

    def dog_sheet(ws, data):
        ws.append(headers)
        for c in ws[1]:
            c.fill, c.font = head_fill, head_font
        for r in data:
            ws.append([r["id"], r["zone"], r["rarity"], r["order_in_tier"], r["name"], r["body"], r["scale"],
                       r["coat_primary"], r["coat_secondary"], r["pattern"], r["accessory"], r["vfx"],
                       ";".join(r["unique_parts"]), r["income"], r["flavor"]])
            row = ws.max_row
            for c in ws[row]:
                c.fill = fills[r["rarity"]]
            for col, key in ((8, "coat_primary"), (9, "coat_secondary")):
                cell = ws.cell(row=row, column=col)
                cell.fill = PatternFill("solid", fgColor=r[key][1:])
                cr, cg, cb = hex_to_rgb(r[key])
                lum = 0.299 * cr + 0.587 * cg + 0.114 * cb
                cell.font = Font(color="000000" if lum > 140 else "FFFFFF")
            ws.cell(row=row, column=14).number_format = "#,##0.00"
        for i, wd in enumerate(widths, 1):
            ws.column_dimensions[get_column_letter(i)].width = wd
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{ws.max_row}"

    wb = Workbook()
    summ = wb.active
    summ.title = "Summary"
    all_ws = wb.create_sheet("All")
    dog_sheet(all_ws, srt)
    for z in zones:
        dog_sheet(wb.create_sheet(z["Id"]), [r for r in srt if r["zone"] == z["Id"]])

    # Summary
    sh = ["Rarity", "Dogs", "Forms (incl. variants)", "Breed odds", "Catch chance", "Income mult",
          "Min income $/s", "Max income $/s"] + [z["Id"] for z in zones]
    summ.append(sh)
    for c in summ[1]:
        c.fill, c.font = head_fill, head_font
    for rar in RARITY_ORDER:
        tr = [r for r in rows if r["rarity"] == rar]
        forms = len(tr) * (1 if rar == "Common" else 4)
        summ.append([rar, len(tr), forms, tiers[rar]["Odds"], tiers[rar]["Catch"], tiers[rar]["IncomeMult"],
                     min(r["income"] for r in tr), max(r["income"] for r in tr)]
                    + [sum(1 for r in tr if r["zone"] == z["Id"]) for z in zones])
        for c in summ[summ.max_row]:
            c.fill = fills[rar]
        summ.cell(row=summ.max_row, column=4).number_format = "0.0%"
        summ.cell(row=summ.max_row, column=5).number_format = "0%"
        for col in (7, 8):
            summ.cell(row=summ.max_row, column=col).number_format = "#,##0.00"
    summ.append(["Total", len(rows), sum(1 if r["rarity"] == "Common" else 4 for r in rows)])
    for c in summ[summ.max_row]:
        c.font = Font(bold=True)
    summ.append([])
    summ.append(["Zone", "Base income $/s", "Dogs", "Common $/s", "Mythic $/s (top)"])
    for c in summ[summ.max_row]:
        c.fill, c.font = head_fill, head_font
    for z in zones:
        zr = [r for r in rows if r["zone"] == z["Id"]]
        summ.append([z["Name"], z["BaseIncome"], len(zr),
                     min(r["income"] for r in zr if r["rarity"] == "Common"),
                     max(r["income"] for r in zr if r["rarity"] == "Mythic")])
    for i, wd in enumerate([16, 16, 22, 11, 13, 12, 15, 15] + [12] * 9, 1):
        summ.column_dimensions[get_column_letter(i)].width = wd
    summ.freeze_panes = "A2"
    summ.auto_filter.ref = f"A1:{get_column_letter(len(sh))}7"
    os.makedirs(os.path.dirname(OUT_XLSX), exist_ok=True)
    wb.save(OUT_XLSX)


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "build"):
        print(__doc__)
        return 2
    ok, rows, zones, tiers = run_check(verbose=True)
    if argv[1] == "check":
        return 0 if ok else 1
    if not ok:
        print("build aborted: fix check failures first")
        return 1
    build_luau(rows, zones)
    build_xlsx(rows, zones, tiers)
    print(f"wrote {os.path.relpath(OUT_LUAU, ROOT)} and {os.path.relpath(OUT_XLSX, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
