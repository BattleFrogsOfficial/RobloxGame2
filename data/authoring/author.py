#!/usr/bin/env python3
"""Bootstrap authoring script: data/authoring/<ZoneId>.txt  ->  data/zones/<ZoneId>.csv

The .txt files are the hand-written roster in a compact pipe format (one dog per line,
tier given by '# <Rarity>' headers, order in file = order_in_tier = income order):

  Common / Uncommon : Name | body[@scale] | coat1 | coat2 | pattern | flavor
  Rare / Epic / Leg : Name | body[@scale] | coat1 | coat2 | pattern | accessory | flavor
  Mythic            : Name | body[@scale] | coat1 | coat2 | pattern | accessory | part+part | flavor

Coats are a PALETTE name (realistic dog coat colours; a tiny deterministic per-dog shade
shift is applied so no two dogs share an exact hex) or a literal #RRGGBB (used as-is).
Scale defaults to the body's base size + a small deterministic spread + a rarity bump.
Income is computed from Zones.luau / Rarities.luau exactly like roster.py check expects.

After the bootstrap the CSVs are the source of truth; you can keep editing the .txt and
re-running this, or edit the CSVs directly. Then: python3 tools/roster.py check && build.
"""
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import roster  # noqa: E402

PALETTE = {
    "black": "#1F1B1A", "charcoal": "#3A3836", "white": "#F3EFE6", "cream": "#E8D8B5",
    "biscuit": "#D4B48A", "wheaten": "#D9BF8C", "lemon": "#E5CD87", "yellow_lab": "#D8B173",
    "apricot": "#E1A66B", "fawn": "#C79B63", "gold": "#CF9A45", "tan": "#B88148",
    "sable": "#7E5431", "red": "#9E4B26", "fox_red": "#B5582B", "copper": "#A8622E",
    "rust": "#8E4520", "mahogany": "#6E2E1E", "chocolate": "#5A3822", "liver": "#6C3A2B",
    "mocha": "#7A5640", "brindle": "#5E4330", "boar": "#6E5A45", "grizzle": "#7F6A55",
    "blue": "#6D7580", "slate": "#4F555C", "grey": "#8C8A86", "silver": "#B5B7B4",
    "smoke": "#A9A9A6", "isabella": "#BFA88A", "lilac": "#9C8C8E", "skin_pink": "#D9A99A",
    "skin_grey": "#7D7470", "sand": "#D6BE92", "champagne": "#DCC6A0", "ivory": "#F7EEDA",
    "red_brown": "#7C3F22", "seal": "#2E2420", "wolf_grey": "#9A948A", "fawn_dark": "#A87E4E",
}

BODY_SCALE = {
    "toy": 0.66, "small_terrier": 0.76, "long_low": 0.8, "small_fluffy": 0.74, "corgi_type": 0.86,
    "medium_lean": 1.0, "medium_stocky": 0.96, "medium_fluffy": 1.02, "large_lean": 1.24,
    "large_athletic": 1.3, "large_fluffy": 1.36, "giant": 1.6, "giant_fluffy": 1.66, "poodle_type": 1.06,
}
RARITY_BUMP = {"Common": 0.0, "Uncommon": 0.04, "Rare": 0.08, "Epic": 0.14, "Legendary": 0.24, "Mythic": 0.34}
FIELDS = {"Common": 6, "Uncommon": 6, "Rare": 7, "Epic": 7, "Legendary": 7, "Mythic": 8}


def h(s: str) -> int:
    return int(hashlib.md5(s.encode()).hexdigest(), 16)


def colour(token: str, seed: str) -> str:
    token = token.strip()
    if token.startswith("#"):
        if len(token) != 7:
            raise ValueError(f"bad hex {token}")
        return token.upper()
    base = PALETTE[token]
    v = h(seed)
    out = []
    for i, c in enumerate((base[1:3], base[3:5], base[5:7])):
        shift = ((v >> (i * 8)) % 9) - 4  # -4..+4 per channel: shade, not hue
        out.append(max(0, min(255, int(c, 16) + shift)))
    return "#" + "".join(f"{c:02X}" for c in out)


def parse_zone(zone_id: str):
    path = os.path.join(HERE, f"{zone_id}.txt")
    tiers = {r: [] for r in roster.RARITY_ORDER}
    cur = None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("#"):
            cur = line[1:].strip()
            if cur not in tiers:
                raise SystemExit(f"{path}:{n}: unknown tier {cur}")
            continue
        parts = [p.strip() for p in line.split("|")]
        want = FIELDS[cur]
        if len(parts) != want:
            raise SystemExit(f"{path}:{n}: expected {want} fields for {cur}, got {len(parts)}: {line}")
        tiers[cur].append((n, parts))
    return tiers


def main():
    zones = roster.load_zones()
    rar_tiers, _ = roster.load_rarities()
    os.makedirs(roster.ZONES_DIR, exist_ok=True)
    for z in zones:
        if not os.path.exists(os.path.join(HERE, f"{z['Id']}.txt")):
            print(f"{z['Id']}: no authoring file, skipped")
            continue
        tiers = parse_zone(z["Id"])
        rows = []
        for rar in roster.RARITY_ORDER:
            entries = tiers[rar]
            count = len(entries)
            for i, (n, p) in enumerate(entries, 1):
                name, body = p[0], p[1]
                scale = None
                if "@" in body:
                    body, s = body.split("@")
                    scale = float(s)
                did = f"{z['Id'].lower()}_{roster.RARITY_LETTER[rar]}{i:02d}"
                if scale is None:
                    spread = ((h(did + name) % 13) - 6) / 100.0
                    scale = BODY_SCALE[body] + spread + RARITY_BUMP[rar]
                scale = round(max(0.6, min(2.2, scale)), 2)
                accessory, parts, flavor = "none", "", p[-1]
                if rar in ("Rare", "Epic", "Legendary", "Mythic"):
                    accessory = p[5]
                if rar == "Mythic":
                    parts = ";".join(x.strip() for x in p[6].split("+"))
                try:
                    c1 = colour(p[2], did + ":1")
                    c2 = colour(p[3], did + ":2")
                except (KeyError, ValueError) as e:
                    raise SystemExit(f"{z['Id']}.txt:{n}: bad colour {e}")
                income = roster.expected_income(z["BaseIncome"], rar_tiers[rar]["IncomeMult"], i, count)
                rows.append({
                    "id": did, "zone": z["Id"], "rarity": rar, "order_in_tier": i, "name": name,
                    "body": body, "scale": f"{scale:.2f}", "coat_primary": c1, "coat_secondary": c2,
                    "pattern": p[4], "accessory": accessory, "vfx": roster.REQUIRED_VFX[rar],
                    "unique_parts": parts, "income": f"{income:.2f}", "flavor": flavor,
                })
        with open(os.path.join(roster.ZONES_DIR, f"{z['Id']}.csv"), "w", newline="", encoding="utf-8") as fh:
            wr = csv.DictWriter(fh, fieldnames=roster.COLUMNS, lineterminator="\n")
            wr.writeheader()
            wr.writerows(rows)
        print(f"{z['Id']}: {len(rows)} dogs")


if __name__ == "__main__":
    main()
