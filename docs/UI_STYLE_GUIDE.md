# Throw a Ball for Dogs — UI Style Guide

Status: binding for everything under `src/client/UI/**`. Written after a research pass on the current
top-of-chart simulator HUDs (Grow a Garden, Steal a Brainrot, Fish It, Throw Food For Animals, Pet Simulator 99)
and Roblox's own UI guidance. The theme values live in `src/client/UI/Theme.luau`; that file wins over this doc.

## 1. The direction in one line

**Chunky cartoon, pixel icons, zero clutter.** Big rounded panels with a thick dark outline, saturated
vertical gradients, bold rounded type with a dark stroke, and a single pixel-art icon language drawn by us.
No emoji anywhere (text, names, buttons, broadcasts, chat prompts). No stock Roblox icons.

What the chart games have in common, and what we copy:

| Convention | Seen in | Our rule |
|---|---|---|
| Currencies as pills in the top-left, icon left, number right, white text with dark stroke | all five | `HUD.Currencies` — Cash, Bones, Throw Power stacked, biggest first |
| Vertical stack of square icon buttons with a small label under each, left edge, mid-height | GaG, SaB, PS99 | `HUD.SideMenu` — Shop, Dogs, Book, Odds, Settings. Max 5. Badge dot for "new" |
| One wide banner at top-centre for the current event / timer | GaG (weather), SaB (events) | `HUD.EventBanner` — squirrel, daily walk, runaway dog. Only one visible at a time |
| Bottom-centre is the action zone: the main verb and its feedback | TFFA (throw meter), Fish It (cast bar) | `HUD.ThrowMeter` + reach line + catch chance. Nothing else lives there |
| Rarity is a colour, used everywhere identically (frames, text, glow, broadcasts) | all five | `Rarities.Tiers[*].Color` is the only source; never restyle it per screen |
| Panels: coloured header band with a title, light body, red close button hanging off the top-right corner | SaB, PS99, GaG | `Components.Panel` — one component, every screen uses it |
| Cards in a grid: thumbnail, name, rarity-coloured frame, price or value under it | all shops | `Components.Card` with `Rarity` prop |
| Juice: hover/press scale 1.0 → 1.06 → 0.94, 0.08 s, Back easing; panels pop in from 0.85 scale | all | `Motion.luau` — the only place tweens are defined |

## 2. Layout grid

- Design canvas: **1280 × 720**. Everything is authored in offset pixels on that canvas, then a `UIScale`
  on the root multiplies by `clamp(min(vw/1280, vh/720), 0.75, 1.4)` (the root frame is enlarged by
  1/scale so it still fills the screen). The 0.75 floor keeps touch targets usable on an iPhone SE; the
  1.4 cap stops the HUD from becoming a postage stamp on 4K.
- **Touch layout** (`IsTouch`): currencies become one horizontal row, the side menu becomes a horizontal
  row under it, the event banner and toasts sit left of the top-right stack, the throw cluster narrows to
  350 px, the ticker is hidden and the throw cluster hides while a panel is open. This keeps the
  bottom-left 180 × 180 and bottom-right 200 × 200 px (thumbstick and jump) completely clear.
- `ScreenGui.ScreenInsets = CoreUISafeInsets`, `IgnoreGuiInset = false`. The top bar is **58 px** now and
  can grow; never place anything in the top 60 px of the raw screen. Safe-area insets come from
  `GuiService:GetGuiInset()` and `ScreenGui.AbsolutePosition`.
- **Edge margins:** 12 px phone, 16 px tablet, 20 px desktop (scaled values, `Theme.Space.Edge`).
- **Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32. No other gaps.
- **Touch targets:** every button is at least 44 px tall on the canvas (33 px physical on an SE at
  scale 0.75; the check fails below 32). Side-menu buttons are 56 px on desktop and 58 × 48 on touch;
  the throw button is 96 × 64.
- **Reserved regions** (nothing of ours may be placed there):
  - Bottom-left 180 × 180 px and bottom-right 200 × 200 px on touch devices (Roblox thumbstick and jump).
  - Top-right 260 × 60 px (player list / chat toggles when the player opens them).
- **Exclusive zones** (one owner each):
  - Top-left: currencies. Top-centre: event banner. Top-right: boost chips + Lucky Streak.
  - Left-middle: side menu. Right-middle: nothing (keeps the field view clear for spectating).
  - Bottom-centre: throw meter + reach + catch line. Bottom-right (desktop only): tiny broadcast ticker.
- **Modal panels** are centred, `min(90 vw, 900 px)` wide, `min(84 vh, 560 px)` tall, with a 40 % black
  scrim behind them. Only one modal open at a time; opening another closes the first.
- **Toasts** stack downward from under the event banner, max 3, 3.5 s each.

## 3. Type

- **Display / numbers / buttons:** `Enum.Font.FredokaOne` (rounded, friendly, reads as "dog game").
- **Body / descriptions / odds tables:** `Enum.Font.GothamMedium`; bold rows `GothamBold`.
- **Pixel flavour (sparingly):** `Enum.Font.Arcade` only for the "+1" style pop numbers and the
  rarity tag on the reveal card, at ≥ 14 px. Never for paragraphs.
- Every *light* display label (white or pale text on a colour) has a `UIStroke` (Contextual, Round join)
  **thickness 2 px**, colour `Theme.Color.Ink` (#1B1A26). Dark text on paper never gets a stroke
  (`Label` decides by luminance). Body text has no stroke.
- Sizes (at 1280 × 720, before UIScale): H1 32, H2 24, Button 20, Currency 22, Body 16, Caption 14.
  **Minimum legible size is 10 px after scaling** (14 px canvas on a phone at scale 0.75); use
  `UITextSizeConstraint` (MinTextSize) on anything `TextScaled`. Prefer fixed sizes + `TextTruncate = AtEnd`
  over `TextScaled` for labels of unknown length, and `TextWrapped` with a two-line box for names.
- Numbers use `FormatNumber.Short` (1.2K, 3.4M, 1.1B) everywhere except the odds panel (exact).

## 4. Colour

Tokens live in `Theme.luau`. Hex here for reference.

| Token | Hex | Use |
|---|---|---|
| Ink | #1B1A26 | outlines, text stroke, shadows |
| Paper | #FFFDF7 | panel body top |
| PaperShade | #EDE8DC | panel body bottom (vertical gradient) |
| Sky | #4FB3FF → #2F7FE0 | primary buttons, header bands |
| Grass | #7ED957 → #3FA34D | confirm / buy / positive |
| Tennis | #E5FF3D → #B8D400 | throw button, Throw Power |
| Cash | #FFD54A → #F4A000 | cash pill |
| Bone | #F3EFE6 → #CFC7B8 | bones pill |
| Danger | #FF5A5A → #D32F2F | close button, sell, warnings |
| Text | #FFFFFF on colour, #2B2A3A on paper | |

Rarity colours come from `Config/Rarities.luau` and are never redefined:
Common #C8C8C8, Uncommon #5AC85A, Rare #468CFF, Epic #AA50E6, Legendary #FFAA1E, Mythic #FF3C78.
Variants: Gold #FFD24A with sparkle, Shadow #2A1B3D with purple edge, Rainbow animated hue cycle (UIGradient
rotation tween, 2 s loop).

Gradients are always **vertical, light on top**, two stops. Panels use Paper → PaperShade. Buttons use their
token pair. Nothing is flat-coloured except text and strokes.

## 5. Surfaces

- `UICorner`: **12 px** on panels, **10 px** on buttons and cards, **999 px** (pill) on currency pills and
  progress bars. Individual-corner rounding (new in June 2026) is used for header bands: top corners 12,
  bottom corners 0.
- `UIStroke` on every panel/button/card: **3 px** Ink, `ApplyStrokeMode = Border`. Cards in a rarity frame use
  the rarity colour at 3 px with an outer Ink stroke at 1 px (two strokes, nested frames).
- `UIShadow` (new in June 2026): `BlurRadius 0`, `Offset (0, 4)`, Ink at 35 % on buttons and cards (the hard
  cartoon drop shadow); `BlurRadius 24`, `Offset (0, 8)`, Ink at 40 % under modal panels. Hard cap: 60
  shadows on screen (Roblox recommends ≤ 100). The Kennel Book grid therefore has shadows on the viewport,
  not on each cell.
- Pressed state: shadow offset to (0, 1) and the button moves down 3 px. Hover: scale 1.04.
- Disabled: 50 % transparency on the whole button, no hover.

## 6. Icons

- All icons are **pixel art we drew**, authored at **16 × 16** (HUD, buttons, badges) and **24 × 24** (shop
  cards, reveal card) in `assets/icons/*.png`, generated by `tools/icons.py` from the pixel strings in
  `src/shared/UI/PixelIcons.luau` (single source of truth; the PNGs are exports).
- Two renderers: `Components.Icon` draws from `PixelIcons` as a grid of Frames when the asset id for that
  icon in `Config/Icons.luau` is `0` (works before any upload, used in Studio and tests), and switches to an
  `ImageLabel` with `ResampleMode = Pixelated` once the id is filled in. Both scale by **integer multiples
  only** (2×, 3×, 4×) so pixels stay crisp; the component rounds its requested size down to the nearest
  multiple.
- Palette per icon: at most 6 colours + a 1 px Ink outline on the silhouette. Light source top-left, one
  highlight pixel row. Icons are drawn as objects, never as glyphs or letters.
- Set (v1): cash, bone, throw_power, ball_tennis, ball_rubber, ball_frisbee, ball_glow, ball_golden, shop,
  dog, book, odds, settings, close, check, lock, arrow_left, arrow_right, luck, sticky, whistle, treat,
  trophy, timer, squirrel, paw, star, kennel, slot, boost_luck, boost_catch, walk, mute, music, info.

## 7. Motion

Defined once in `Motion.luau`.

| Event | Tween |
|---|---|
| Panel open | scale 0.85 → 1, transparency 1 → 0, 0.18 s, Back out |
| Panel close | scale 1 → 0.9, transparency 0 → 1, 0.12 s, Quad in |
| Button press | scale 0.94 for 0.06 s then back, Quad |
| Currency change | number counts up over 0.4 s; the pill scales 1.0 → 1.08 → 1.0 |
| Toast | slide down 24 px + fade, 0.2 s; hold; fade 0.3 s |
| Lucky Streak increment | pill shakes ±4 px, 0.3 s; at 2 it pulses gold until used |
| Rarity reveal card | handled by the cutscene; the end card uses Panel open with a rarity-coloured flash |

Reduced motion: `Settings.ReducedMotion` swaps every tween for a 0.05 s linear fade.

## 8. Screens (what exists)

HUD (currencies, side menu, event banner, boost chips, lucky streak, throw meter, reach + catch line,
broadcast ticker), Shop (tabs: Balls, Boosts, Yard, Cosmetics), Dogs (yard manager: displayed vs kennel,
sell/keep, dupes), Kennel Book (zone tabs, virtualised 158-cell grid, milestone bar, claim), Odds (the
posted tables, exact numbers, current ball and luck applied), Settings (music, SFX, reduced motion, treat
pocket mode, keep-dupes toggles), Reveal end card, Spectator banner, Toasts, FTUE prompts.

## 9. Checks before merge

`lune run tools/uicheck/run.luau` builds the real UI under `tools/uicheck/roblox.luau` (a Roblox
emulator with the layout rules) at five viewports (667 × 375, 844 × 390, 1024 × 768, 1366 × 768,
1920 × 1080) and ten scenarios (HUD, HUD with events, each panel, both reveal outcomes), then fails on:
anything off-screen, HUD regions overlapping each other or the touch zones, text wider than its box
without truncation, text under 10 px, touch targets under 32 px, list children overflowing a fixed list,
modals within 8 px of an edge, and any emoji codepoint under `src/`. Truncated or clipped text is a
warning. `node tools/uicheck/screenshot.js` turns the SVG previews in `build/ui-preview/` into PNGs.
Both run in CI.

Sources: Roblox staff "Designing UI – Tips and Best Practices" (DevForum), "New UI Capabilities: Shadows &
Individual Corners" release post (June 23, 2026), vizzbees "12 Roblox UI Design Ideas (2026)", and a
screenshot review of the current Top Playing Now simulators.
