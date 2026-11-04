# Throw a Ball for Dogs — UI Style Guide

Status: binding for everything under `src/client/UI/**` and the cutscene's screen pieces
(`src/client/Cutscene/Overlay.luau`, `TestPanel.luau`). The values live in `src/client/UI/Theme.luau`; that file
wins over this doc. Rewritten for the November 2026 overhaul from the user's reference screenshots (a shop panel and a
throw bar from the simulator genre). They are **style references only**: every icon, name, text and asset here is
ours.

## 1. The direction in one line

**Chunky, saturated, toy-like.** Thick near-black outlines on everything (panels, cards, buttons, icons, text),
a heavy rounded display font with a thick dark stroke on all display text, dark panel bodies so the colourful cards
pop, and big shaded pixel-art icons that we draw ourselves. No emoji, no stock icons, no copied text or branding.

The principles, extracted from the reference boxes:

| Principle | Rule |
|---|---|
| Thick dark outlines | `UIStroke` Ink (#14131B): panels 4 px, cards 3 px, buttons 3 px, hotbar slots 3 px (selected: white 4 px), the throw bar 5 px. Icons carry a 1-pixel ink outline in the art. |
| Outlined display type | **All** display text (titles, names, prices, numbers, buttons, tags) is `FredokaOne`, white or bright, with an Ink text stroke: 2 px up to 16 px type, 3 px to 28 px, 4 px above (`Theme.TextStrokeFor`). The loudest callouts (TAP TO THROW!, the meter value, the strength number) use `LuckiestGuy`. This replaces the old "strokes on light text only" rule. Body copy (odds notes, settings rows) is light `GothamBold` on the dark body, no stroke. |
| Panels | A warm gradient header (`Theme.Palette.Header`, yellow to orange) with diagonal highlight stripes (`Decor.Stripes`), the big outlined title left-aligned (with a 48 px icon), a square red close button with a heavy white X at the right end of the header; an Ink rule under the header; a near-black/charcoal body (`Theme.Color.Body`). Every panel uses the same header colour. |
| Item cards | A row of tall cards. Each card's **background is its rarity colour** (Common grey, Uncommon green, Rare blue, Epic purple, Legendary orange, Mythic pink, from `Config/Rarities`), the name big at the top, the rarity word under it in a bright rarity tint, a big icon in the middle (128 px art, scaled down only to fit), a dark translucent stat strip ("x1.25 Range  +10% Luck"), then a bottom row: a grey cash price button ("$150") and a purple Robux button (Robux mark + number). Equipped / Owned / Maxed = one full-width grey button. A small dark badge in the top-right corner of the art carries the owned count ("x3"). Things without a rarity (boosts, upgrades) wear a fitting tier colour and a descriptive tag word instead of a rarity. |
| Hotbar | Bottom centre: square dark slots with the slot number in the top-left corner, the item icon in the middle and the count bottom-right; the selected slot has a white border. It holds the balls: slot 1 Tennis, then each consumable ball you own. Click or number key = `EquipBall`. |
| Icons | Big, chunky, shaded (light from the top-left), ink-outlined pixel art (section 6). |
| Few colours per screen | Charcoal chips for every HUD stat (the icon carries the colour), one blue for the side menu, one header orange for every panel, rarity colours only where rarity means something. |
| Nothing floating with no purpose | No empty panels, no decorative frames without content (the old bottom-right ticker is gone; broadcasts are toasts). |
| Clear hierarchy | Cash is the biggest number on screen (32 px desktop), then strength (40 px LuckiestGuy but only one short number), then bones (24 px). |

## 2. Layout grid

- Design canvas: **1280 × 720**, offset pixels; a `UIScale` on the root multiplies by
  `clamp(min(vw/1280, vh/720), 0.75, 1.4)` (the root frame is enlarged by 1/scale so it still fills the screen).
- `ScreenGui.ScreenInsets = CoreUISafeInsets`, `IgnoreGuiInset = false`; never place anything in the top 60 px.
- **Edge margins:** 12 px touch, 16 px desktop. **Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32.
- **Touch targets:** at least 44 px on the canvas (the check fails below 32 physical px). Side menu 68 × 68 desktop,
  60 × 52 touch; hotbar slots 64 desktop, 56 touch; card buttons 44.
- **Reserved regions:** bottom-left 180 × 180 and bottom-right 200 × 200 screen px on touch (thumbstick, jump);
  top-right 260 × 60 (player list / chat). Nothing of ours goes there.
- **HUD regions (one owner each):**
  - Top-left: `Currencies`. Desktop: cash pill (52 px, the biggest), the income line, the bones pill. Touch: one row —
    cash, bones, then the strength stat.
  - Left: `SideMenu` (Shop, Dogs, Book, Odds, Options): vertical on desktop, a row under the currencies on touch.
  - Top-centre: `EventBanner` (squirrel / runaway dog / daily walk) with `Toasts` under it (touch: left of the
    top-right stack). The spectator banner shares the toast slot.
  - Top-right: `TopRight` — the Lucky Streak chip (gold when full) and boost chips with countdowns.
  - Bottom-centre: `Hotbar`; the `ThrowCluster` above it (only while the bar is up).
  - Bottom-left (desktop): `Strength` — the flexed-arm icon and ThrowPower as a big blue LuckiestGuy number.
  - Right-middle: nothing (keeps the field clear), except the dev / cutscene-test pills.
- **Modal panels:** centred, `min(92 % vw, 900)` × `min(93 % vh, 560)` (the tall fraction keeps phone cards whole),
  55 % black scrim, one at a time.

### Throw bar (Components/PowerMeter + the HUD throw cluster)

- A tall rounded capsule (56 px wide desktop, 44 touch; 230 px tall desktop, `clamp(screenH − 300, 120, 230)` on
  touch) with a 5 px Ink outline, filled with a top-to-bottom gradient **green → yellow → orange → red**, split into
  5 segments by Ink dividers, with a white gloss stripe down its left side.
- A white pill marker with a 4 px Ink outline, wider than the capsule, rides up and down: **top = full power =
  Perfect** (`Util/Meter`: position 1 = top). The live value 0-100 rides to the right of the marker (LuckiestGuy 30,
  turns green in the Perfect band).
- Under the bar: **TAP TO THROW!** (touch) / **CLICK TO THROW!** (desktop), LuckiestGuy 26 / 36, then one small line:
  reach zone + distance and the Legendary catch chance.
- Flow (one tap, no turns): the bar appears by itself when the server sets the player attribute `InThrowZone`
  (falls back to `OnPlatform` only when `InThrowZone` is nil), nothing is in flight, no panel is open and the HUD is
  visible. On appearing it fires `ChargeBegin` and the marker sweeps on `Meter.Period(isTutorial)` (the server's
  clock). One tap / click / Space / R2 fires `ChargeRelease` (and `ui.ThrowReleased`, which starts the cutscene
  wind-up). An untapped sweep is restarted with another `ChargeBegin` on the last period boundary before
  `Game.Throw.MaxChargeSeconds` (the server cancels idle charges silently). Leaving the zone hides the bar with no
  remote. After a throw, when `ui:FinishThrow` unlocks and the player is still in the zone, the bar comes back (no
  sooner than `Game.Throw.MinSecondsBetweenThrows` after the release) and fires `ChargeBegin`. There is no queue and
  no "waiting for your turn" UI.

## 3. Type

| Role | Font | Size (canvas) | Stroke |
|---|---|---|---|
| Panel title | FredokaOne | 36 | 4 px Ink |
| Card name | FredokaOne | 22 → 16 (fits the card) | 3 px |
| Rarity word / tag | FredokaOne | 16, rarity tint | 2 px |
| Prices, buttons | FredokaOne | 20 | 3 px |
| Cash / bones | FredokaOne | 32 / 24 desktop, 26 / 20 touch | 4 / 3 px |
| TAP TO THROW!, meter value, strength | LuckiestGuy | 36 / 30 / 40 | 4 px |
| Odds counter (cutscene) | FredokaOne | 60 | 5 px |
| Body copy | GothamBold | 16 / 14 | none |

Minimum legible size 10 px after scaling. Fixed sizes + `TextTruncate.AtEnd` for unknown lengths; names step down
through sizes (`Card.FitSize`) before truncating. Numbers use `FormatNumber` everywhere except the odds tables.

## 4. Colour

| Token | Hex | Use |
|---|---|---|
| Ink | #14131B | every outline, text stroke, divider |
| Body | #22212B | panel body |
| BodyDeep | #18171F | hotbar slots, wells |
| BodyRaised | #302F3C | section boxes, unknown Book cards |
| TextOnPaper (now: text on the body) | #F7F5FF | body copy |
| TextMuted | #B4B1C6 | captions |
| Header | #FFD15A → #FF8C1A | every panel header, the selected tab |
| Sky | #5CCBFF → #1F7FE6 | side menu, primary actions |
| Grass | #8CEB4C → #36A12C | Equip, positive |
| Slate | #9C9AAA → #5E5C6C | cash price buttons, Equipped / Owned / Maxed |
| Robux / Purple | #C16BFF → #7B2FE0 | Robux buttons |
| Danger | #FF5C52 → #C81E1E | close button, Sell |
| Dark | #3A3947 → #24232E | HUD chips, unselected tabs, Skip |
| Strength | #4FC3FF | the strength number |
| Strip | #000000 @ 55 % | the stat strip on cards |

Rarity colours come only from `Config/Rarities.luau`; `Theme.Palette.<Rarity>` (toasts) and `Card.Paint` derive
from them. A card's gradient runs from the rarity colour 28 % toward white at the top to 12 % toward Ink at the
bottom; its rarity word is the colour 55 % toward white. Gradients are vertical, light on top.

## 5. Surfaces

- Corners: panels 14, cards and buttons 8, hotbar slots 6, chips and the throw bar fully round.
- Strokes: section 1. Buttons get a soft white gloss band over their top 42 % (toy plastic).
- `UIShadow`: hard (0 blur, 4 px down) on buttons, chips and the bar marker; soft under panels; max 60 on screen.
- Close button: 48 × 48 square, Danger gradient, the 32 px `close` icon (heavy white X), inside the header's right end.
- Tabs: chunky 44 px buttons with a 32 px icon; selected = Header gradient, others Dark.
- Pressed: scale 0.94; hover 1.04; disabled: 50 % transparency.

## 6. Icons

- All icons are pixel art we drew, generated by `tools/icons.py` (the single source) into `assets/icons/*.png`
  (1x, 4x and a contact sheet) and `src/shared/UI/PixelIcons.luau`. Never hand-edit the Luau module.
- Two grid sizes: **32 × 32 hero icons**, drawn procedurally in `icons.py` (section "BIG ICONS") from shapes, shaded
  with four tones (highlight, light, base, dark; light from the top-left) and outlined in Ink on all eight sides:
  `ball_tennis`, `ball_rubber`, `ball_flying_disc`, `ball_glow`, `ball_golden`, `cash` (a gold coin with an embossed
  paw), `bone`, `throw_power` (a flexed arm), `dog`, `book`, `odds` (a die), `settings` (a gear), `shop`
  (a storefront), `robux` (a hexagon mark), `close` (a heavy X). Everything else stays a 16 × 16 grid (max 6 colours
  + ink). Icon names never change, so old call sites keep working.
- The `dog` icon is **recolourable**: palette letters `1` `5` `2` (coat primary, light, dark) and `3` `4` (secondary,
  shade) are swapped at runtime (`Icon.new{ Recolor = Icon.DogColors(def) }`), so every card in My Dogs and the
  Kennel Book shows the dog in its own coat colours (unknown Book dogs: an Ink silhouette via `Tint`).
- Renderer: `Components/Icon` draws Frames from the grids (same-colour runs merged into rectangles and cached per
  icon) until an asset id is set in `Config/Icons.luau`, then an `ImageLabel` with `ResampleMode = Pixelated`.
  Sizes snap to multiples of 16 px (a 32-grid icon at 64 px is 2 px per pixel). Card art is 128 px, scaled down by a
  `UIScale` only when a short (phone) card has less room.

## 7. Motion

Defined once in `Motion.luau`: panel open (scale 0.85 → 1, Back), close (→ 0.9, Quad), press 0.94, currency count-up
0.4 s with a pulse, toasts slide + fade, the meter value pulses when it enters the Perfect band, the TAP label
pulses when the bar appears. Reduced motion swaps every tween for a 0.05 s fade.

### Reveal end card (prize screen)

`Screens/Reveal.luau`, 600 × 400 canvas px. The panel look: dark body, 4 px Ink outline, a rarity-coloured header
band with diagonal stripes and the outlined rarity word (variant badge right), the live 3D dog on its pedestal
(`Components/DogViewport`, unchanged) on the left 60 %, a rotated CAUGHT / RAN OFF stamp, and on the right the
outlined white name, rarity pips, zone + distance, the income cascade, a rarity-coloured income plate with the big
$/s counting up, and the buttons. Scrim, flash, Epic+ light rays and the pop are as before (`Config/Cutscene`
`EndCard`).

### Cutscene overlay

`Cutscene/Overlay.luau`: the "1 out of N" counter in FredokaOne 60 with a 5 px Ink stroke (colour = the tier it has
reached), the dog's name, a rarity tag pill in the rarity gradient with outlined text, the variant badge on a dark
chip, the flourish line in gold, and a dark Skip button. All outlined display type.

## 8. Screens

HUD (currencies, side menu, banner + toasts, streak + boosts, strength, hotbar, throw bar), Shop (Balls, Boosts,
Yard, Items, Style, Robux: every tab is a row of cards; the header shows cash and bones), My Dogs (rarity cards with
the dog's coat colours, $/s strip, Show/Kennel + Sell), Kennel Book (zone tabs, milestone bar + claims, rarity cards /
silhouettes), Odds, Settings, Dev tools, Cutscene test, Reveal end card, spectator banner, cutscene overlay.

Robux: ball cards show the `Products.Balls[id]` pack (Robux price, throws per purchase). The button calls
`MarketplaceService:PromptProductPurchase` when `ProductId ~= 0`, otherwise toasts "Not available yet"; the server
grants on its receipt.

## 9. Checks before merge

`lune run tools/uicheck/run.luau` builds the real UI under `tools/uicheck/roblox.luau` at five viewports
(667 × 375, 844 × 390, 1024 × 768, 1366 × 768, 1920 × 1080) and every scenario (HUD, events, out of / in the throw
zone, the bar at 0 / 50 / 100, the hotbar with counts, every shop tab, dogs, book, odds, settings, dev, the cutscene
test panel, the overlay counter states, every reveal), then fails on: anything off-screen, HUD regions overlapping
each other or the touch zones, text wider than its box without truncation, text under 10 px, touch targets under
32 px, list children overflowing a fixed list, modals within 8 px of an edge, a reveal card taller than 84 % of the
screen or without its dog viewport, and any emoji codepoint under `src/`. Truncated or clipped text is a warning;
keep both at zero. `node tools/uicheck/screenshot.js <svgDir> <outDir> [filter]` renders the SVG previews to PNGs;
`docs/ui-reference/after/` holds the post-overhaul set next to `docs/ui-reference/current/` (before).
