# Dog roster data

The game has 720 base dogs: 9 zones x 80. Each non-Common dog also has Gold, Shadow and Rainbow forms, which come from the runtime VariantFX module and are not separate rows.

| Path | What it is |
|---|---|
| `data/zones/<ZoneId>.csv` | **Source of truth.** One file per zone, 80 rows each |
| `tools/roster.py` | Has the `check` and `build` commands. Its vocab lists are at the top of the file |
| `src/shared/Data/Dogs.luau` | **Generated.** Do not edit by hand |
| `data/Roster.xlsx` | **Generated.** Has one sheet per zone, plus `All` and `Summary` |

## Workflow

```
python3 tools/roster.py check    # prints a report; exits 1 on any failure
python3 tools/roster.py build    # runs check first, then writes Dogs.luau and Roster.xlsx
```


## CSV columns

`id,zone,rarity,order_in_tier,name,body,scale,coat_primary,coat_secondary,pattern,accessory,vfx,unique_parts,income,flavor`

- `id` = `<zone lowercased>_<c|u|r|e|l|m><NN>`, where NN is `order_in_tier` (for example `backyard_c01` or `beach_m01`).
- `unique_parts` is a list separated by `;`. Only Mythic dogs have unique parts.
- `income` = zone `BaseIncome` x rarity `IncomeMult` x (1 + offset), with offset = 0.2 x (order-1)/(count-1), rounded to 2 decimals. It is the base $/s for an adult dog before the variant multiplier. Base incomes come from `src/shared/Config/Zones.luau` and rarity multipliers from `src/shared/Config/Rarities.luau`. If you change those numbers, fix the `income` column, then run `check`.

## What `check` enforces

- **Counts per zone:** 54 Common, 13 Uncommon, 7 Rare, 3 Epic, 2 Legendary, 1 Mythic. MythicMeadow has 53 Common and 2 Mythic instead.
- **Ids:** unique and well formed.
- **Names:**
  - Unique across the whole game, ignoring case, spaces and punctuation.
  - ASCII only.
  - No variant words (gold, golden, shadow, rainbow). The real breed names "Golden Retriever" and "Goldendoodle" are the only exceptions.
- **Vocab:** body, pattern, accessory, vfx and unique part must come from the lists at the top of `roster.py`.
- **Rarity visual budget:**
  - Common: natural marking only, no accessory, vfx `none`.
  - Uncommon: adds a natural or stylised pattern.
  - Rare: adds an everyday accessory.
  - Epic: signature accessory and vfx `sparkle`.
  - Legendary: a coat texture used by no other Legendary, and vfx `aura`.
  - Mythic: unique parts and vfx `full`.
- **Looks:**
  - No two dogs anywhere share the same (Body, CoatPrimary, CoatSecondary, Pattern, Accessory).
  - Within a zone, two dogs fail as **too similar** when they share body, pattern and accessory and both coats are within CIE76 deltaE < 12. Coats are compared both in order and swapped.
  - Across the whole game, **too-similar names** (Levenshtein ratio > 0.85) fail.
- **Income:** must match the formula above, and must not decrease as `order_in_tier` goes up.
- **Scale:** must be between 0.6 and 2.2.

## Naming rules

- Commons use real breed names. Each real breed appears as a plain name only once in the game, and the most familiar breeds are in the early zones. Commons also include coat or type descriptors such as "Lemon Beagle" or "Blue Merle Aussie".
- Uncommons have zone-flavoured names, such as "Surf Corgi".
- Rares are named after their accessory, such as "Lifeguard Lab".
- Epic, Legendary and Mythic dogs are original named characters.
- No franchise characters, celebrities, brands, or dogs from film, TV or games.
