#!/usr/bin/env python3
"""Pixel-art icon source for Throw a Ball for Dogs.

The small icons are authored here as 16x16 character grids (one letter per pixel, "." = transparent); the hero
icons (balls, cash, bone, strength arm, dog, book, odds, settings, shop, robux, close) are drawn procedurally at
32x32 with shading and an ink outline (see "BIG ICONS").
Running this file:
    python3 tools/icons.py            # validate, write assets/icons/*.png (1x and 4x), a contact sheet,
                                      # and src/shared/UI/PixelIcons.luau
    python3 tools/icons.py --check    # validate only (CI)

Rules (docs/UI_STYLE_GUIDE.md section 6): 16x16 (max 6 colours + ink) or 32x32 (max 11 colours + ink), light from
the top-left, ink outline, objects not glyphs, no emoji anywhere. The Luau module is generated; do not hand-edit it.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PNG = os.path.join(ROOT, "assets", "icons")
OUT_LUAU = os.path.join(ROOT, "src", "shared", "UI", "PixelIcons.luau")

# Shared palette: letter -> hex. Keep letters stable; the Luau module emits this table.
PALETTE = {
    "k": "#1B1A26",  # ink
    "w": "#FFFFFF",
    "h": "#2B2A3A",  # near-black (eyes, pads)
    "K": "#4A4860",  # dark grey
    "S": "#9A9AAE",  # grey
    "s": "#DDDDE6",  # silver
    "e": "#F3EFE6",  # bone white
    "E": "#CFC7B8",  # bone shade
    "y": "#E5FF3D",  # tennis light
    "Y": "#B8D400",  # tennis base
    "g": "#8CA020",  # tennis dark
    "r": "#FF5A5A",  # red
    "R": "#C62828",  # dark red
    "o": "#FF9F1C",  # orange
    "G": "#FFD54A",  # gold
    "A": "#F4A000",  # dark gold
    "a": "#FFF0A0",  # pale gold
    "b": "#4FB3FF",  # blue
    "B": "#2F7FE0",  # dark blue
    "x": "#BFE8FF",  # sky light
    "c": "#7FF5E8",  # cyan
    "C": "#2BB5A0",  # teal
    "n": "#7ED957",  # green
    "N": "#3FA34D",  # dark green
    "m": "#C8FFB0",  # mint
    "p": "#AA50E6",  # purple
    "P": "#6C2BB0",  # dark purple
    "v": "#2A1B3D",  # shadow violet
    "t": "#D9A066",  # tan
    "T": "#8B5A2B",  # brown
    "u": "#F1D3A6",  # light tan
    "d": "#5A3A1A",  # dark brown
    "i": "#FF7BAC",  # pink
    "I": "#FF3C78",  # hot pink
    "z": "#EAF4FF",  # snow
    # shading tones for the 32 x 32 hero icons
    "f": "#F7FFB0",  # tennis highlight
    "D": "#5E6E10",  # tennis deep shadow
    "j": "#FFB3AC",  # red highlight
    "l": "#8A1A1A",  # red deep
    "q": "#1C4F9C",  # blue deep
    "F": "#147A68",  # teal deep
    "H": "#B86E00",  # gold deep
    "J": "#A89C86",  # bone deep
    # recolourable dog coat (Components/Icon Recolor): defaults are a tan dog with a cream muzzle
    "1": "#C68A4E",  # coat primary
    "5": "#E3B07A",  # coat primary light
    "2": "#8F5A2A",  # coat primary dark
    "3": "#F4E3C8",  # coat secondary
    "4": "#CDB48F",  # coat secondary shade
}

ICONS: dict[str, list[str]] = {}


def icon(name: str, rows: str) -> None:
    ICONS[name] = [r for r in rows.strip("\n").split("\n")]


icon("cash", """
.....kkkkkk.....
...kkGGGGGGkk...
..kGaaGGGGGGAk..
.kGaGGGGGGGGGAk.
.kGaGGkkkkGGGAk.
kGaGGkaaaakGGAAk
kGGGkaGGGGakGAAk
kGGGkaGGGGakGAAk
kGGGkaGGGGakGAAk
kGGGkaGGGGakGAAk
kGGGGkaaaakGAAAk
.kGGGGkkkkGAAAk.
.kGGGGGGGGAAAAk.
..kGGGGGGAAAAk..
...kkAAAAAAkk...
.....kkkkkk.....
""")

icon("bone", """
................
................
..kkk......kkk..
.keeek....keeek.
keeeeek..keeeeek
keeeEeekkeeeEEek
.keeeeeeeeeeeek.
..kEeeeeeeeeEk..
..kEeeeeeeeeEk..
.keeeeeeeeeeeek.
keeeEeekkeeeEEek
keeeeek..keeeeek
.keeek....keeek.
..kkk......kkk..
................
................
""")

icon("throw_power", """
................
................
..kkk......kkk..
.kSssk....kSssk.
.kSssk....kSssk.
kKSsskkkkkkSssKk
kKSsssssssssssKk
kKSsssssssssssKk
kKSSsssssssssSKk
kKSSskkkkkkkSSKk
.kSSk......kSSk.
.kSSk......kSSk.
..kkk......kkk..
................
................
................
""")

icon("ball_tennis", """
.....kkkkkk.....
...kkyyyyyykk...
..kyyyywyyyyyk..
.kyyyyywyyyyyyk.
.kyyyyywyyyyYyk.
kyyyyyywyyyyYYyk
kyyyyyywyyyyYYYk
kyyyyyyywyyyYYYk
kyyyyyyyywyyYYYk
kyyyyyyyyywyYYYk
kyYyyyyyyyywYYYk
.kYYyyyyyyyywYk.
.kYYYyyyyyyyywk.
..kYYYYyyyyYwk..
...kkYYYYYYkk...
.....kkkkkk.....
""")

icon("ball_rubber", """
.....kkkkkk.....
...kkrrrrrrkk...
..krrwwrrrrrRk..
.krrwrrrrrrrrRk.
.krwrrrrrrrrrRk.
krrrrrrrrrrrrRRk
kwwwwwwwwwwwwwwk
kwwwwwwwwwwwwwwk
krrrrrrrrrrrrRRk
krrrrrrrrrrrRRRk
krrrrrrrrrrrRRRk
.krrrrrrrrrRRRk.
.krrrrrrrrRRRRk.
..krrrrrRRRRRk..
...kkRRRRRRkk...
.....kkkkkk.....
""")

icon("ball_flying_disc", """
................
................
................
.....kkkkkk.....
...kkbbbbbbkk...
..kbbxxbbbbbbk..
.kbbxbbbbbbbbbk.
kbbbbbbkkkkbbbbk
kbbbbbkBBBBkbbBk
kBbbbbkBBBBkbBBk
.kBBbbbkkkkbBBk.
..kBBBBBBBBBBk..
...kkBBBBBBkk...
.....kkkkkk.....
................
................
""")

icon("ball_glow", """
.......kk.......
..k....cc....k..
...k...cc...k...
....kkkkkkkk....
...kccccccccck..
..kccwwcccccCck.
.kccwccccccccCk.
kkcccccccccccCkk
kkcccccccccccCkk
.kccccccccccCCk.
..kcccccccCCCk..
...kcccccCCCk...
....kkkkkkkk....
...k...cc...k...
..k....cc....k..
.......kk.......
""")

icon("ball_golden", """
.k..............
kwk..kkkkkkkk...
.k..kGaaGGGGGAk.
...kGaGGGGGGGGAk
...kGaGGGGGGGGAk
...kGGGGGGGGGAAk
...kGGGGGGGGGAAk
...kGGGGGGGGAAAk
...kGGGGGGGGAAAk
...kGGGGGGGAAAAk
...kAGGGGGAAAAAk
....kAAAAAAAAAk.
.....kkkkkkkk.k.
.............kwk
..............k.
................
""")

icon("shop", """
................
.kkkkkkkkkkkkkk.
krwrrwrrwrrwrrwk
krwrrwrrwrrwrrwk
kkkkkkkkkkkkkkkk
.kuuuuuuuuuuuuk.
.kukkkkkkkkkkuk.
.kukbbbbkttttuk.
.kukbbbbkttGtuk.
.kukbbbbkttttuk.
.kukkkkkkttttuk.
.kuuuuuuuttttuk.
.kkkkkkkkkkkkkk.
................
................
................
""")

icon("dog", """
................
..kkk......kkk..
.kTTkkkkkkkkTTk.
kTTkttttttttkTTk
kTTkttttttttkTTk
kTTktkttttktkTTk
kTTkthttttthkTTk
kTTkttttttttkTTk
kTTTkttttttkTTTk
.kkkkttthhtttkk.
...ktttkhhktttk.
...ktttkwktttk..
....kttttttk....
.....kkkkkk.....
................
................
""")

icon("book", """
................
..kkkkkkkkkkkk..
.kbbbbbbbbbbbbk.
.kbbrrbbbbbbbBk.
.kbbrrbbbbbbbBk.
.kbbrrbbbbbbbBk.
.kbbrrbbbbbbbBk.
.kbbbbbbbbbbbBk.
.kbbbbbbbbbbbBk.
.kbbbbbbbbbbbBk.
.kbbbbbbbbbbbBk.
.kBBBBBBBBBBBBk.
.keeeeeeeeeeeek.
.kwwwwwwwwwwwwk.
..kkkkkkkkkkkk..
................
""")

icon("odds", """
................
...kkkkkkkkkk...
..kwwwwwwwwwwk..
.kwkkwwwwwwwwwk.
.kwkkwwwwwwwwwk.
.kwwwwwwwwwwwwk.
.kwwwwwwwwwwwwk.
.kwwwwwkkwwwwwk.
.kwwwwwkkwwwwwk.
.kwwwwwwwwwwwwk.
.kwwwwwwwwwwwwk.
.kwwwwwwwwwkkwk.
.kswwwwwwwwkksk.
..kssssssssssk..
...kkkkkkkkkk...
................
""")

icon("settings", """
......kkkk......
..kk..kSSk..kk..
.kSSkkkSSkkkSSk.
.kSSSSSSSSSSSSk.
..kSSSSSSSSSSk..
..kSSSkkkkSSSk..
kkkSSkwwwwkSSkkk
kSSSSkwwwwkSSSSk
kSSSSkwwwwkSSSSk
kkkSSkwwwwkSSkkk
..kSSSkkkkSSSk..
..kSSSSSSSSSSk..
.kSSSSSSSSSSSSk.
.kSSkkkSSkkkSSk.
..kk..kSSk..kk..
......kkkk......
""")

icon("close", """
................
.kkk........kkk.
kwwwk......kwwwk
kwwwwk....kwwwwk
.kwwwwk..kwwwwk.
..kwwwwkkwwwwk..
...kwwwwwwwwk...
....kwwwwwwk....
....kwwwwwwk....
...kwwwwwwwwk...
..kwwwwkkwwwwk..
.kwwwwk..kwwwwk.
kwwwwk....kwwwwk
kwwwk......kwwwk
.kkk........kkk.
................
""")

icon("check", """
................
................
............kk..
...........knnk.
..........knnnk.
.........knnnk..
..kk....knnnk...
.knnk..knnnk....
knnnnkknnnk.....
knnnnnnnnk......
.knnnnnnk.......
..knnnnk........
...knnk.........
....kk..........
................
................
""")

icon("lock", """
................
.....kkkkkk.....
....kSSSSSSk....
...kSSkkkkSSk...
...kSk....kSk...
...kSk....kSk...
..kkkkkkkkkkkk..
.kGGGGGGGGGGGGk.
.kGGGGGGGGGGGAk.
.kGGGGGkkGGGGAk.
.kGGGGkAAkGGGAk.
.kGGGGGkkGGGAAk.
.kGGGGGkkGGGAAk.
.kAAAAAAAAAAAAk.
..kkkkkkkkkkkk..
................
""")

icon("arrow_left", """
................
................
......kk........
.....kwwk.......
....kwwwk.......
...kwwwwk.......
..kwwwwwkkkkkkk.
.kwwwwwwwwwwwwwk
.kwwwwwwwwwwwwwk
..kwwwwwkkkkkkk.
...kwwwwk.......
....kwwwk.......
.....kwwk.......
......kk........
................
................
""")

icon("luck", """
................
...kkk....kkk...
..knmnk..knnnk..
.knnnnnkknnnnnk.
.knnnnnnnnnnnnk.
.kNnnnnnnnnnnNk.
..kNnnnnnnnnNk..
.kknnnnnnnnnnkk.
.knnnnnnnnnnnnk.
.knnnnnkknnnnnk.
.kNnnnkTTknnnNk.
..kkkkkTTkkkkk..
.......kTTk.....
.......kTTk.....
........kk......
................
""")

icon("sticky", """
.....kkkkkk.....
...kkyyyyyykk...
..kyywyyyyyyYk..
.kyyyyyyyyyyyYk.
.kyyyyyyyyyyyYk.
kyyyyyyyyyyyyYYk
kyyyyyyyyyyyyYYk
kyyyyyyyyyyyYYYk
kyyyyyyyyyyyYYYk
kYyyyyyyyyyYYYYk
.kYyyyyyyyyYYYk.
.kYYyyyyyyYYYYk.
..kYYkYYYkYYYk..
...kkkGGkGGkk...
.....kGGkGGk....
......kk.kk.....
""")

icon("whistle", """
................
................
................
....kkkkkkkk....
...kGGGGGGGGkkk.
..kGaGGGGGGGGGGk
..kGGGGGGGGGGGGk
..kGGGGGGGGGGGGk
..kGGGGGGGGGkkkk
..kGGkkGGGGk....
..kGGkkGGGAk....
...kGGGGGAAk....
...kAGGGAAk.....
....kAAAAk......
.....kkkk.......
................
""")

icon("treat", """
................
................
................
..kkk......kkk..
.kuutk....kuutk.
kuuuutk..kuuuutk
kuuuuutkkuuuuutk
.kuuuuuuuuuuuuk.
..kuuTuuuuTuuk..
..kuuuuTuuuuuk..
.kuuuuuuuuuuuuk.
kuuuuutkkuuuuutk
kuuuutk..kuuuutk
.kuutk....kuutk.
..kkk......kkk..
................
""")

icon("trophy", """
................
.kkkkkkkkkkkkkk.
kGkGGGGGGGGGGkGk
kGkGaGGGGGGGAkGk
kGkGaGGGGGGGAkGk
kGkGGGGGGGGGAkGk
.kkGGGGGGGGGAkk.
...kGGGGGGGAAk..
....kGGGGGAAk...
.....kGGGAAk....
......kGAAk.....
......kGAk......
.....kkGAkk.....
....kTTTTTTk....
...kTTTTTTTTk...
...kkkkkkkkkk...
""")

icon("timer", """
......kkkk......
.....kSSSSk.....
..k...kkkk...k..
.kSk.kkkkkk.kSk.
..kkkwwwwwwkkk..
..kwwwwkwwwwwk..
.kwwwwwkwwwwwwk.
.kwwwwwkwwwwwwk.
.kwwwwwkkkwwwwk.
.kwwwwwwwwwwwwk.
.kwwwwwwwwwwwwk.
..kwwwwwwwwwwk..
..kkwwwwwwwwkk..
....kkkkkkkk....
................
................
""")

icon("squirrel", """
................
..........kkk...
.........kTTTk..
........kTTTTTk.
..kk....kTTTTTk.
.kttk..kTTTTTTk.
.kttkkkTTTTTTTk.
kttktkttkTTTTTk.
kttttttttkTTTTk.
kthtttttttkTTTk.
.ktttttttttkTTk.
.kuuuttttttttTk.
..kuuttttttTTk..
...kkttttttkk...
....kkkkkkkk....
................
""")

icon("paw", """
................
....kk....kk....
...khhk..khhk...
...khhk..khhk...
.kk.kk....kk.kk.
khhk........khhk
khhk........khhk
.kk...kkkk...kk.
.....khhhhk.....
....khhhhhhk....
...khhhhhhhhk...
...khhhhhhhhk...
...khhhhhhhhk...
....khhhhhhk....
.....kkkkkk.....
................
""")

icon("star", """
.......kk.......
......kGGk......
......kGGk......
.....kGaGGk.....
kkkkkkGaGGkkkkkk
kGGGGGGaGGGGGGGk
.kGGGGGaGGGGGGk.
..kGGGGaGGGGGk..
...kGGGaGGGGk...
...kGGGGGGGAk...
..kGGGGkkGGGAk..
..kGGGk..kGGAk..
.kGGkk....kkAAk.
.kkk........kkk.
................
................
""")

icon("kennel", """
.......kk.......
......krrk......
.....krrrrk.....
....krrrrrrk....
...krrrrrrrrk...
..krrrrrrrrrrk..
.krrrrrrrrrrrrk.
kkkkkkkkkkkkkkkk
.kuuuuuuuuuuuuk.
.kuuuukkkkuuuuk.
.kuuukhhhhkuuuk.
.kuuukhhhhkuuuk.
.kuuukhhhhkuuuk.
.kuuukhhhhkuuuk.
.kkkkkkkkkkkkkk.
................
""")

icon("slot", """
................
.kkk.kkk.kkk.kkk
.k............k.
.k............k.
.......nn.......
.k.....nn.....k.
.k.....nn.....k.
.....nnnnnn.....
.....nnnnnn.....
.k.....nn.....k.
.k.....nn.....k.
.......nn.......
.k............k.
.k............k.
.kkk.kkk.kkk.kkk
................
""")

icon("boost_luck", """
......kkkk......
......ksSk......
......kSSk......
.....kkkkkk.....
.....kwwwwk.....
....kwwwwwwk....
...kwwwwwwwwk...
..kwwnnnnnnwwk..
.kwnnnnnnnnnnwk.
.knnnnmnnnnnnnk.
.knnnnmnnnnnNnk.
.knnnnnnnnnnNnk.
.kNnnnnnnnnNNNk.
..kNNnnnnnNNNk..
...kkNNNNNNkk...
.....kkkkkk.....
""")

icon("walk", """
................
................
.....kkkkkk.....
...kkrrrrrrkk...
..krrkkkkkkrrk..
.krrk......krrk.
.krk........krk.
.krk........krk.
.krrk......krrk.
..krrk....krrk..
...krrkkkkrrk...
....krrGGrrk....
.....kkGGkk.....
......kGGk......
......kkkk......
................
""")

icon("music", """
................
........kkkk....
........kSSSkk..
........kSkkSSk.
........kSk.kSk.
........kSk.kSk.
........kSk..kk.
........kSk.....
........kSk.....
....kkkkkSk.....
..kkSSSSSSk.....
.kSSSSSSSSk.....
.kSSSSSSSk......
..kSSSSSk.......
...kkkkk........
................
""")

icon("mute", """
................
................
.......kk.......
......ksSk......
.....kssSk......
.kkkkksssSk.r..r
.kssssssssk..rr.
.ksssssssSk..rr.
.ksssssssSk.r..r
.kkkkksssSk.....
.....kssSk......
......ksSk......
.......kk.......
................
................
................
""")

icon("info", """
.......kk.......
..kkkkkkkkkkkkk.
.kbbbbbbbbbbbbbk
.kbbwwwwwwwwwbBk
.kbbbbbbbbbbbBBk
..kkkkkkkkkkkkk.
.......kk.......
......kTTk......
......kTTk......
......kTTk......
......kTTk......
......kTTk......
......kTTk......
.....kTTTTk.....
.....kkkkkk.....
................
""")

icon("variant_gold", """
.......kk.......
......kaak......
.....kaGGak.....
....kaGGGGak....
...kaGGGGGGak...
..kaGGGGGGGGak..
.kaGGGGGGGGGGak.
kaGGGGGGGGGGGGak
kAGGGGGGGGGGGGAk
.kAGGGGGGGGGGAk.
..kAGGGGGGGGAk..
...kAGGGGGGAk...
....kAGGGGAk....
.....kAGGAk.....
......kAAk......
.......kk.......
""")

icon("variant_shadow", """
.......kk.......
......kvvk......
.....kvvvvk.....
.....kvPvvk.....
....kvvPPvvk....
....kvPPPvvk....
...kvvPPPPvvk...
...kvPPpPPPvk...
..kvvPPppPPvvk..
..kvPPpppPPPvk..
..kvPPppppPPvk..
..kvvPPpppPPvk..
...kvPPPPPPvk...
...kvvPPPPvvk...
....kkvvvvkk....
......kkkk......
""")

icon("variant_rainbow", """
................
................
......kkkk......
....kkrrrrkk....
...kroooooook...
..kroGGGGGGork..
.kroGnnnnnnGork.
kroGnbbbbbbnGork
kroGnbppppbnGork
kroGnbp..pbnGork
kroGnbp..pbnGork
kroGnbp..pbnGork
kkkkkkk..kkkkkkk
................
................
................
""")

icon("bolt", """
.........kk.....
........kGGk....
.......kGGGk....
......kGGGk.....
.....kGGGk......
....kGGGGkkkkk..
...kGGGGGGGGGk..
..kkkkkkGGGGk...
.......kGGGk....
......kGGGk.....
.....kGGGk......
....kGGk........
...kGGk.........
..kGk...........
.kk.............
................
""")

icon("skip", """
................
................
.kk......kk.....
.kwwk....kwwk...
.kwwwk...kwwwk..
.kwwwwk..kwwwwk.
.kwwwwwk.kwwwwwk
.kwwwwwwkkwwwwwk
.kwwwwwk.kwwwwwk
.kwwwwk..kwwwwk.
.kwwwk...kwwwk..
.kwwk....kwwk...
.kk......kk.....
................
................
................
""")

# Zones
icon("zone_backyard", """
................
..kk...kk...kk..
.kuuk.kuuk.kuuk.
.kuuk.kuuk.kuuk.
kkuukkkuukkkuukk
kuuuuuuuuuuuuuuk
kuuuuuuuuuuuuuuk
kkuukkkuukkkuukk
.kuuk.kuuk.kuuk.
.kuuk.kuuk.kuuk.
kkuukkkuukkkuukk
kuuuuuuuuuuuuuuk
kuuuuuuuuuuuuuuk
kkuukkkuukkkuukk
.kuuk.kuuk.kuuk.
.kkkk.kkkk.kkkk.
""")

icon("zone_park", """
.....kkkkkk.....
...kknnnnnnkk...
..knnmnnnnnnnk..
.knnmnnnnnnnNnk.
.knnnnnnnnnnNnk.
kknnnnnnnnnnnNkk
knnnnnnnnnnnnNNk
knnnnnnnnnnnNNNk
.kNnnnnnnnnNNNk.
..kNNnnnnnNNNk..
...kkNNkkNNkk...
.....kkTTkk.....
......kTTk......
......kTTk......
.....kTTTTk.....
.....kkkkkk.....
""")

icon("zone_beach", """
.......kk.......
.....kkrrkk.....
...kkrrwwrrkk...
..krrrwwwwrrrk..
.krrrwwwwwwrrrk.
krrrrwwwwwwrrrrk
kkkkkkkkkkkkkkkk
........kk......
........kTk.....
........kTk.....
........kTk.....
........kTk.....
........kTk.....
kkkkkkkkkTkkkkkk
kuuuuuuukTkuuuuk
kkkkkkkkkkkkkkkk
""")

icon("zone_farm", """
................
......kkkk......
....kkrrrrkk....
..kkrrrrrrrrkk..
.krrrrrrrrrrrrk.
kkkkkkkkkkkkkkkk
.krrrrkkkkrrrrk.
.krrrkuuuukrrrk.
.krrrkukkukrrrk.
.krrrkukkukrrrk.
.krrrkuuuukrrrk.
.krrrkukkukrrrk.
.krrrkukkukrrrk.
.krrrkuuuukrrrk.
.kkkkkkkkkkkkkk.
................
""")

icon("zone_forest", """
.......kk.......
......kNNk......
.....kNnNNk.....
....kNnnNNNk....
.....kNnNNk.....
....kNnnNNNk....
...kNnnnNNNNk...
..kNnnnnNNNNNk..
....kNnnNNNk....
...kNnnnNNNNk...
..kNnnnnNNNNNk..
.kNnnnnnNNNNNNk.
kkkkkkkTTkkkkkkk
......kTTk......
.....kkkkkk.....
................
""")

icon("zone_snow", """
.......kk.......
......kzzk......
...k..kzzk..k...
..kzk.kzzk.kzk..
...kzkkzzkkzk...
....kzzzzzzk....
.....kzzzzk.....
kkkkkkzzzzkkkkkk
kzzzzzzzzzzzzzzk
kkkkkkzzzzkkkkkk
.....kzzzzk.....
....kzzzzzzk....
...kzkkzzkkzk...
..kzk.kzzk.kzk..
...k..kzzk..k...
......kkkk......
""")

icon("zone_city", """
..........kkkk..
..........kSSk..
..kkkkkkkkkSSk..
..kSSSSSSSSSSk..
..kSkGkSkGkSSk..
..kSSSSSSSSSSk..
..kSkGkSkGkSSk..
..kSSSSSSSSSSk..
..kSkGkSkGkSSk..
..kSSSSSSSSSSk..
..kSkGkSkGkSSk..
..kSSSSSSSSSSk..
..kSSSSkkSSSSk..
..kSSSSkkSSSSk..
..kkkkkkkkkkkk..
................
""")

icon("zone_space", """
................
.....kkkkkk.....
...kkbbbbbbkk...
..kbbxbbbbbbbk..
.kbbxbbbbbbbbBk.
.kbbbbbbbbbbbBk.
kkkkkkkkkkkkkkkk
kaaaaaaaaaaaaaak
kaaaaaaaaaaaaaak
kkkkkkkkkkkkkkkk
.kbbbbbbbbbbBBk.
.kbbbbbbbbbbBBk.
..kbbbbbbbbBBk..
...kkBBBBBBkk...
.....kkkkkk.....
................
""")

icon("zone_mythic", """
.......kk.......
......kiik......
......kiik......
.....kiwiik.....
.....kiwiik.....
....kiiwiiIk....
....kiiwiiIk....
...kiiiwiiIIk...
...kiiiwiiIIk...
..kiiiiwiiIIIk..
..kiiiiiiiIIIk..
...kiiiiiiIIk...
....kiiiiIIk....
.....kiiIIk.....
......kiIk......
.......kk.......
""")

# ---------------------------------------------------------------------------------------------------------------
# BIG ICONS (32 x 32). The hero icons (balls, currencies, the side menu, the strength arm, the dog, the Robux mark,
# the close X) are drawn procedurally here from simple shapes, then shaded (light from the top-left: highlight,
# light, base, dark) and given a 1 px ink outline on all eight sides, so they read chunky at 48-96 px. They replace
# the 16 x 16 grids of the same name; every other icon stays 16 x 16. Recolourable letters "1".."5" (the dog coat)
# are swapped at runtime by Components/Icon (Recolor = { ["1"] = Color3, ... }).
# ---------------------------------------------------------------------------------------------------------------
import math as _m

BIG = 32
LIGHT = (-0.55, -0.65, 0.52)
_ll = _m.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _ll for v in LIGHT)


class Canvas:
    def __init__(self, n: int = BIG) -> None:
        self.n = n
        self.px: list[list[str | None]] = [[None] * n for _ in range(n)]

    def paint(self, inside, colour) -> None:
        """inside(x, y) -> bool at the pixel centre; colour(x, y) -> letter (or a letter)."""
        for y in range(self.n):
            for x in range(self.n):
                cx, cy = x + 0.5, y + 0.5
                if inside(cx, cy):
                    c = colour(cx, cy) if callable(colour) else colour
                    if c is not None:
                        self.px[y][x] = c

    def erase(self, inside) -> None:
        for y in range(self.n):
            for x in range(self.n):
                if inside(x + 0.5, y + 0.5):
                    self.px[y][x] = None

    def outline(self, letter: str = "k") -> None:
        n = self.n
        add = []
        for y in range(n):
            for x in range(n):
                if self.px[y][x] is None:
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            xx, yy = x + dx, y + dy
                            if 0 <= xx < n and 0 <= yy < n and self.px[yy][xx] not in (None, letter):
                                add.append((x, y))
                                break
                        else:
                            continue
                        break
        for x, y in add:
            self.px[y][x] = letter

    def rows(self) -> list[str]:
        return ["".join(c or "." for c in row) for row in self.px]


def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def rect(x0, y0, x1, y1):
    return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1


def capsule(ax, ay, bx, by, r):
    def f(x, y):
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
        px, py = ax + vx * t, ay + vy * t
        return (x - px) ** 2 + (y - py) ** 2 <= r * r
    return f


def polygon(pts):
    def f(x, y):
        inside = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        return inside
    return f


def union(*fs):
    return lambda x, y: any(f(x, y) for f in fs)


def minus(a, b):
    return lambda x, y: a(x, y) and not b(x, y)


def sphere_tone(cx, cy, r, tones, flat: float = 1.0):
    """tones = (highlight, light, base, dark[, deep]). Lambert from LIGHT on a sphere (flat < 1 squashes it)."""
    def f(x, y):
        nx, ny = (x - cx) / r, (y - cy) / r
        nz = _m.sqrt(max(0.0, 1 - nx * nx - ny * ny)) * flat
        ln = _m.sqrt(nx * nx + ny * ny + nz * nz) or 1
        d = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
        if d > 0.9:
            return tones[0]
        if d > 0.62:
            return tones[1]
        if d > 0.2 or len(tones) < 4:
            return tones[2]
        if len(tones) > 4 and d < -0.25:
            return tones[4]
        return tones[3]
    return f


def bevel(mask, tones, depth: float = 1.6):
    """Flat-shape shading: light on the edges facing the light, dark on the far edges. tones = (hi, base, dark)."""
    def f(x, y):
        if not mask(x + depth, y + depth) or not mask(x + 0.5, y + depth + 0.6):
            return tones[2]
        if not mask(x - depth, y - depth):
            return tones[0]
        return tones[1]
    return f


def sparkle(c: Canvas, cx, cy, size, letter="w"):
    c.paint(union(rect(cx - 0.5, cy - size, cx + 0.5, cy + size), rect(cx - size, cy - 0.5, cx + size, cy + 0.5)), letter)


def big(name: str, c: Canvas) -> None:
    c.outline("k")
    ICONS[name] = c.rows()


# --- balls ---------------------------------------------------------------------------------------------------------
def _ball(tones, extra=None, r=13.0, cx=16.0, cy=16.0):
    c = Canvas()
    c.paint(circle(cx, cy, r), sphere_tone(cx, cy, r, tones))
    if extra:
        extra(c, cx, cy, r)
    return c


def _tennis_seam(c, cx, cy, r):
    inside = circle(cx, cy, r - 0.6)
    for sx in (-1, 1):
        ox = cx + sx * r * 1.22
        ring = lambda x, y, ox=ox: abs(_m.hypot(x - ox, y - cy) - r * 0.92) < 0.95
        c.paint(lambda x, y, ring=ring: inside(x, y) and ring(x, y), lambda x, y: "w" if (x + y) < cx + cy + 4 else "e")


big("ball_tennis", _ball(("f", "y", "Y", "g", "D"), _tennis_seam))


def _rubber_band(c, cx, cy, r):
    inside = circle(cx, cy, r - 0.6)
    band = lambda x, y: abs((y - cy) - 0.18 * (x - cx) - 0.004 * (x - cx) ** 2 * 6) < 2.4
    c.paint(lambda x, y: inside(x, y) and band(x, y), lambda x, y: "w" if x < cx + 3 else "s")


big("ball_rubber", _ball(("j", "r", "R", "l", "l"), _rubber_band))


def _disc():
    c = Canvas()
    c.paint(ellipse(16, 19.5, 14.5, 8.0), lambda x, y: "q" if y > 19.5 else "B")
    top = ellipse(16, 16.5, 14.5, 8.0)
    c.paint(top, lambda x, y: "x" if (x - 16) * 0.5 + (y - 16.5) < -5.5 else ("b" if (x - 16) * 0.4 + (y - 16.5) < 3.0 else "B"))
    c.paint(lambda x, y: abs(((x - 16) / 8.2) ** 2 + ((y - 16.5) / 4.4) ** 2 - 1) < 0.28, "B")
    c.paint(ellipse(16, 16.5, 5.0, 2.4), "b")
    c.paint(ellipse(12.5, 12.5, 3.0, 1.0), "w")
    return c


big("ball_flying_disc", _disc())


def _glow_extra(c, cx, cy, r):
    c.paint(ellipse(cx - 4, cy - 5, 3.2, 2.2), "w")


def _glow():
    c = Canvas()
    # soft halo pixels around the ball
    for i in range(8):
        a = i * _m.pi / 4 + _m.pi / 8
        x, y = 16 + _m.cos(a) * 13.4, 16 + _m.sin(a) * 13.4
        c.paint(circle(x, y, 1.3), "c")
    c.paint(circle(16, 16, 10.5), sphere_tone(16, 16, 10.5, ("z", "c", "C", "F")))
    _glow_extra(c, 16, 16, 10.5)
    return c


big("ball_glow", _glow())


def _golden_extra(c, cx, cy, r):
    c.paint(ellipse(cx - 5, cy - 6, 3.0, 2.0), "w")


g = _ball(("a", "G", "A", "H", "H"), _golden_extra, r=12.0, cx=15.0, cy=17.0)
sparkle(g, 27, 5, 3, "w")
sparkle(g, 5, 7, 2, "a")
big("ball_golden", g)

# --- currencies + stats ----------------------------------------------------------------------------------------------
def _coin():
    c = Canvas()
    c.paint(circle(16, 16, 14.5), sphere_tone(16, 16, 14.5, ("a", "G", "A", "H", "H"), flat=0.6))
    face = circle(16, 16, 10.8)
    c.paint(face, lambda x, y: "G" if (x - 16) + (y - 16) < 6 else "A")
    c.paint(lambda x, y: abs(_m.hypot(x - 16, y - 16) - 11.2) < 0.7, "H")
    # embossed paw: dark print with a highlight one pixel up-left
    paw = union(ellipse(16, 19.2, 4.4, 3.4), circle(10.6, 13.8, 1.9), circle(14.1, 10.8, 1.9), circle(17.9, 10.8, 1.9), circle(21.4, 13.8, 1.9))
    c.paint(lambda x, y: paw(x + 1, y + 1) and not paw(x, y) and face(x, y), "a")
    c.paint(paw, "H")
    c.paint(ellipse(9.5, 7.5, 2.6, 1.4), "w")
    return c


big("cash", _coin())


def _bone():
    c = Canvas()
    ax, ay, bx, by = 9.0, 23.0, 23.0, 9.0
    shape = union(
        capsule(ax, ay, bx, by, 3.8),
        circle(ax - 3.6, ay - 1.4, 4.0), circle(ax + 1.4, ay + 3.6, 4.0),
        circle(bx - 1.4, by - 3.6, 4.0), circle(bx + 3.6, by + 1.4, 4.0),
    )
    c.paint(shape, bevel(shape, ("w", "e", "E"), 1.8))
    c.paint(lambda x, y: shape(x, y) and not shape(x + 3.2, y + 3.2), lambda x, y: "J" if shape(x, y) else None)
    c.paint(capsule(12.5, 17.5, 17.5, 12.5, 0.8), "w")
    return c


big("bone", _bone())


def _arm():
    c = Canvas()
    upper = capsule(6.0, 25.5, 19.5, 25.5, 4.6)
    bicep = circle(11.0, 20.0, 6.8)
    fore = capsule(20.0, 25.0, 22.5, 12.0, 4.0)
    fist = union(circle(22.0, 8.5, 5.0), capsule(16.5, 9.0, 18.0, 12.5, 2.2))
    shape = union(upper, bicep, fore, fist)
    c.paint(shape, bevel(shape, ("a", "G", "A"), 1.8))
    c.paint(lambda x, y: shape(x, y) and not shape(x + 3.0, y + 3.0), "H")
    # ink creases: under the bicep peak, elbow, and wrist; knuckles
    c.paint(lambda x, y: abs(_m.hypot(x - 11.0, y - 20.0) - 6.8) < 0.75 and x > 14.0 and y < 26 and fore(x, y), "k")
    c.paint(lambda x, y: abs(_m.hypot(x - 22.0, y - 8.5) - 5.0) < 0.75 and y > 11.0 and fore(x, y), "k")
    c.paint(capsule(18.5, 6.0, 24.5, 5.0, 0.5), "A")
    c.paint(capsule(19.0, 9.0, 24.0, 8.5, 0.5), "A")
    c.paint(ellipse(8.0, 17.0, 2.6, 1.5), "w")
    return c


big("throw_power", _arm())

# --- the dog (recolourable coat: 1 base, 5 light, 2 dark; 3 secondary, 4 secondary shade) ----------------------------
def _dog():
    c = Canvas()
    for sx in (-1, 1):
        ear = ellipse(16 + sx * 10.2, 15.5, 3.8, 7.6)
        c.paint(ear, lambda x, y: "2")
    head = ellipse(16, 15.0, 10.4, 9.6)
    c.paint(head, bevel(head, ("5", "1", "2"), 1.8))
    c.paint(minus(rect(14.6, 6.0, 17.4, 16.0), lambda x, y: not head(x, y)), "3")
    muzzle = ellipse(16, 21.0, 7.0, 5.4)
    c.paint(muzzle, lambda x, y: "4" if y > 23.6 or (x > 20.5 and y > 20) else "3")
    c.paint(ellipse(16, 18.4, 2.9, 2.0), "h")
    c.paint(rect(14.6, 17.3, 15.4, 17.9), "w")
    c.paint(rect(15.6, 20.2, 16.4, 22.2), "h")
    c.paint(ellipse(16, 24.6, 1.8, 1.5), "i")
    for ex in (11.2, 20.8):
        c.paint(ellipse(ex, 13.2, 1.7, 2.0), "h")
        c.paint(rect(ex - 1.2, 11.8, ex - 0.2, 12.6), "w")
    return c


big("dog", _dog())

# --- side menu + panels --------------------------------------------------------------------------------------------
def _book():
    c = Canvas()
    c.paint(rect(8.0, 6.0, 27.5, 28.5), lambda x, y: "E" if y > 27 else "e")       # page block
    c.paint(lambda x, y: 24.5 <= x <= 27.5 and 7 <= y <= 27.5 and int(y) % 3 == 0, "E")
    cover = rect(4.5, 3.5, 24.5, 26.5)
    c.paint(cover, bevel(cover, ("r", "R", "l"), 1.6))
    c.paint(rect(4.5, 3.5, 7.5, 26.5), lambda x, y: "l" if x > 6.5 else "R")      # spine
    paw = union(ellipse(16, 17.2, 3.6, 2.8), circle(11.6, 12.4, 1.6), circle(14.6, 10.0, 1.6), circle(17.8, 10.0, 1.6), circle(20.6, 12.4, 1.6))
    c.paint(lambda x, y: paw(x - 1, y - 1) and not paw(x, y), "A")
    c.paint(paw, "G")
    c.paint(rect(19.0, 26.5, 21.0, 30.5), "b")                                     # ribbon
    return c


big("book", _book())


def _die():
    c = Canvas()
    top = polygon([(16, 2.5), (29, 9), (16, 15.5), (3, 9)])
    left = polygon([(3, 9), (16, 15.5), (16, 29.5), (3, 23)])
    right = polygon([(16, 15.5), (29, 9), (29, 23), (16, 29.5)])
    c.paint(left, "s")
    c.paint(right, "S")
    c.paint(top, "w")
    c.paint(ellipse(16, 9, 2.8, 1.6), "r")
    for (x, y) in ((7.0, 14.5), (12.0, 23.0)):
        c.paint(ellipse(x, y, 1.5, 1.9), "h")
    for (x, y) in ((20.0, 15.0), (22.5, 19.5), (25.0, 24.0)):
        c.paint(ellipse(x, y, 1.5, 1.9), "h")
    return c


big("odds", _die())


def _gear():
    c = Canvas()

    def shape(x, y):
        dx, dy = x - 16, y - 16
        r = _m.hypot(dx, dy)
        a = _m.atan2(dy, dx)
        tooth = _m.cos(8 * a) > 0.15
        return r <= (14.6 if tooth else 11.4)
    c.paint(shape, bevel(shape, ("w", "s", "S"), 1.6))
    c.paint(lambda x, y: shape(x, y) and not shape(x + 2.6, y + 2.6), "K")
    c.paint(lambda x, y: abs(_m.hypot(x - 16, y - 16) - 7.6) < 0.8, "S")
    c.erase(circle(16, 16, 4.6))
    c.paint(lambda x, y: abs(_m.hypot(x - 16, y - 16) - 5.2) < 0.7 and (x + y) > 32, "w")
    return c


big("settings", _gear())


def _shop():
    c = Canvas()
    wall = rect(5.0, 12.0, 27.0, 28.5)
    c.paint(wall, bevel(wall, ("t", "t", "T"), 1.6))
    c.paint(rect(8.0, 15.5, 15.0, 22.5), lambda x, y: "x" if x + y < 27 else "b")    # window
    c.paint(rect(11.2, 15.5, 11.8, 22.5), "T")
    c.paint(rect(18.0, 16.0, 24.0, 28.5), lambda x, y: "d" if x > 22.5 else "T")     # door
    c.paint(circle(19.8, 22.5, 0.9), "G")
    c.paint(rect(3.0, 28.0, 29.0, 29.5), "K")                                        # step
    # striped awning with a scalloped edge
    def awning(x, y):
        if not (2.5 <= x <= 29.5):
            return False
        if y < 4.0 or y > 13.5:
            return False
        if y > 10.5:
            k = int((x - 2.5) // 4.5)
            mx = 2.5 + k * 4.5 + 2.25
            return (x - mx) ** 2 + (y - 10.5) ** 2 <= 2.3 ** 2
        return True
    c.paint(awning, lambda x, y: ("r" if y < 8 else "R") if int((x - 2.5) // 4.5) % 2 == 0 else ("w" if y < 8 else "s"))
    c.paint(rect(4.0, 2.5, 28.0, 4.0), "R")
    return c


big("shop", _shop())


def _robux():
    c = Canvas()

    def hexagon(r):
        pts = [(16 + r * _m.cos(_m.pi / 6 + i * _m.pi / 3), 16 + r * _m.sin(_m.pi / 6 + i * _m.pi / 3)) for i in range(6)]
        return polygon(pts)
    outer = hexagon(14.5)
    c.paint(outer, bevel(outer, ("w", "w", "s"), 1.4))
    c.paint(hexagon(10.2), "k")
    c.paint(rect(12.3, 12.3, 19.7, 19.7), lambda x, y: "s" if x + y > 34 else "w")
    return c


big("robux", _robux())


def _close():
    c = Canvas()
    shape = union(capsule(7.5, 7.5, 24.5, 24.5, 4.2), capsule(24.5, 7.5, 7.5, 24.5, 4.2))
    c.paint(shape, bevel(shape, ("w", "w", "s"), 1.4))
    return c


big("close", _close())


# Derived icons
ICONS["arrow_right"] = [row[::-1] for row in ICONS["arrow_left"]]
ICONS["arrow_up"] = ["".join(ICONS["arrow_left"][x][y] for x in range(16)) for y in range(16)]
ICONS["arrow_down"] = ICONS["arrow_up"][::-1]
ICONS["boost_catch"] = [row.translate(str.maketrans("nNm", "bBx")) for row in ICONS["boost_luck"]]

ZONE_ICON = {
    "Backyard": "zone_backyard", "Park": "zone_park", "Beach": "zone_beach", "Farm": "zone_farm",
    "Forest": "zone_forest", "SnowyPeaks": "zone_snow", "CityRooftops": "zone_city",
    "SpaceStation": "zone_space", "MythicMeadow": "zone_mythic",
}
BALL_ICON = {"Tennis": "ball_tennis", "Rubber": "ball_rubber", "FlyingDisc": "ball_flying_disc", "Glow": "ball_glow",
             "Golden": "ball_golden"}


def grid_size(name: str) -> int:
    return len(ICONS[name])


def validate() -> list[str]:
    errors = []
    for name, rows in ICONS.items():
        n = len(rows)
        if n not in (16, 32):
            errors.append(f"{name}: {n} rows (want 16 or 32)")
        for i, row in enumerate(rows):
            if len(row) != n:
                errors.append(f"{name}: row {i} has {len(row)} columns (want {n}): {row!r}")
            for ch in row:
                if ch != "." and ch not in PALETTE:
                    errors.append(f"{name}: unknown palette letter {ch!r} in row {i}")
        colours = {ch for row in rows for ch in row if ch not in ".k"}
        limit = 6 if n == 16 else 11
        if len(colours) > limit:
            errors.append(f"{name}: {len(colours)} colours (max {limit} + ink): {''.join(sorted(colours))}")
        if all(ch == "." for row in rows for ch in row):
            errors.append(f"{name}: empty")
    return errors


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def write_pngs() -> None:
    from PIL import Image

    os.makedirs(OUT_PNG, exist_ok=True)
    names = sorted(ICONS)
    for name in names:
        n = grid_size(name)
        img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        px = img.load()
        for y, row in enumerate(ICONS[name]):
            for x, ch in enumerate(row):
                if ch != ".":
                    px[x, y] = hex_to_rgb(PALETTE[ch]) + (255,)
        img.save(os.path.join(OUT_PNG, f"{name}.png"))
        img.resize((n * 4, n * 4), Image.NEAREST).save(os.path.join(OUT_PNG, f"{name}@4x.png"))
    # Contact sheet for review: 8 per row at 4x on a mid-grey background with the name under each.
    from PIL import ImageDraw

    cols, cell = 8, 160
    rows_n = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows_n * cell), (120, 124, 140, 255))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        cx, cy = (i % cols) * cell, (i // cols) * cell
        img = Image.open(os.path.join(OUT_PNG, f"{name}.png")).resize((128, 128), Image.NEAREST)
        sheet.alpha_composite(img, (cx + (cell - 128) // 2, cy + 4))
        draw.text((cx + 4, cy + 140), f"{name[:20]} ({grid_size(name)})", fill=(255, 255, 255, 255))
    sheet.save(os.path.join(OUT_PNG, "_contact_sheet.png"))


def write_luau() -> None:
    os.makedirs(os.path.dirname(OUT_LUAU), exist_ok=True)
    lines = [
        "--!strict",
        "-- GENERATED by tools/icons.py. Do not edit; edit the grids in tools/icons.py and re-run it.",
        "-- Pixel icons: 16x16 or 32x32 grids (#rows) of palette letters, '.' = transparent. Rendered by",
        "-- client/UI/Components/Icon. Letters 1-5 are the recolourable dog coat (Icon Recolor).",
        "local PixelIcons = {}",
        "",
        "PixelIcons.Size = 16 -- the small grid; the hero icons are 32 (PixelIcons.GridSize(name))",
        "",
        "PixelIcons.Palette = {",
    ]
    for letter, hexv in PALETTE.items():
        r, g, b = hex_to_rgb(hexv)
        lines.append(f'\t["{letter}"] = Color3.fromRGB({r}, {g}, {b}),')
    lines.append("} :: { [string]: Color3 }")
    lines.append("")
    lines.append("PixelIcons.Icons = {")
    for name in sorted(ICONS):
        lines.append(f"\t{name} = {{")
        for row in ICONS[name]:
            lines.append(f'\t\t"{row}",')
        lines.append("\t},")
    lines.append("} :: { [string]: { string } }")
    lines.append("")
    lines.append("PixelIcons.ZoneIcon = {")
    for zone, ic in ZONE_ICON.items():
        lines.append(f'\t{zone} = "{ic}",')
    lines.append("} :: { [string]: string }")
    lines.append("")
    lines.append("PixelIcons.BallIcon = {")
    for ball, ic in BALL_ICON.items():
        lines.append(f'\t{ball} = "{ic}",')
    lines.append("} :: { [string]: string }")
    lines.append("")
    lines.append("function PixelIcons.GridSize(name: string): number")
    lines.append("\tlocal rows = PixelIcons.Icons[name]")
    lines.append("\treturn if rows then #rows else PixelIcons.Size")
    lines.append("end")
    lines.append("")
    lines.append("function PixelIcons.Has(name: string): boolean")
    lines.append("\treturn PixelIcons.Icons[name] ~= nil")
    lines.append("end")
    lines.append("")
    lines.append("return PixelIcons")
    lines.append("")
    with open(OUT_LUAU, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main() -> int:
    errors = validate()
    if errors:
        print("\n".join(errors))
        return 1
    if "--check" in sys.argv:
        print(f"{len(ICONS)} icons OK")
        return 0
    write_pngs()
    write_luau()
    print(f"wrote {len(ICONS)} icons to {OUT_PNG} and {OUT_LUAU}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
