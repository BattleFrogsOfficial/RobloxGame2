# QA: HUD looks clean (concern 2)

Tool: `node tools/hud_preview.js` (Playwright + Chromium). It rebuilds the HUD as HTML from the real numbers:

- It parses every `HudLayout.*` constant from `src/client/UI/HudLayout.luau` and the colours, corners, stroke and text caps from `Theme.luau`.
- `HudLayout.Compute` is ported 1:1 into `computeLayout()`. **Keep the two in sync.**
- Component geometry comes from the controller and component sources, either parsed or mirrored. A small UDim2 engine handles scale/offset, AnchorPoint, UIPadding, UIListLayout, SizeConstraint, UIAspectRatioConstraint, TextScaled and UITextSizeConstraint.
- Device model: CoreUISafeInsets places the safe area below the 58 px top bar. The phone (844x390) also gets 47 px notch insets on the left and right and a 21 px home-indicator inset. The Roblox touch jump button gets a 140x140 screen-corner reserve, drawn as a red dashed box.
- It renders three scenes per resolution: HUD (meter charging, feed, spectator banner, toasts, boosts, debug button), Shop modal and Kennel Book modal.
- It exits with code 1 on any of these: region overlap, an element under the top bar or in the jump reserve, an element off-screen or escaping its region, list overflow, text that does not fit at MinTextSize (including the alternative runtime strings for the throw summary), or a Book grid showing fewer than 1.8 rows.

Screenshots (after fixes): `docs/qa/hud/{hud,shop,book}_{1920x1080,1366x768,844x390}.png`.
Before fixes: `docs/qa/hud/before/*.png`.

## Findings and fixes

| # | Before | Fix |
|---|--------|-----|
| 1 | Phone: the rail (Odds and part of Boost) sat in the jump-button corner. The reserve was only 96x92 and measured in safe-area pixels. | `HudLayout.JumpReserve` now has a phone size (140x140, short side <= 500) and a tablet size (180x150). `Compute(w, h, touch)` takes a touch flag, and HudController passes `UserInputService.TouchEnabled`. When one column would shrink buttons below MinButton, the rail wraps into 2 columns. HudController now uses a `UIGridLayout` (`RailButtonW` / `RailColumns`). |
| 2 | Throw panel: the Lucky Streak pips overflowed their holder and covered the "Streak" label ("Streal"). | Summary width is now 0.62 and the Streak block 0.37. The label and the pip holder each take 50%. |
| 3 | Kennel Book: the GOLD/SHADOW/RAINBOW tags did not fit (35x12 box) and overlapped the swatch. | The tag is now a ribbon across the bottom of the swatch (0.86 width). The swatch is 0.44 and the name label is taller. |
| 4 | Kennel Book on phone: only 1.0 grid row visible, and 9 px names. | `Window` now uses a responsive title bar (34-44 px). `Modal.HeightFrac` went from 0.92 to 0.95. Book compact mode (body < 300 px): milestones and progress share the bottom line, the detail line becomes a popup over the grid for 5 s after a tap, and cells are 84 px with aspect 0.9. Result: about 1.9 rows. On desktop, `CellMinWidth` went from 84 to 96, so names no longer drop to 9 px. Added `VirtualGrid:SetCellSize`. |
| 5 | Inconsistent font sizes: each rail button and each boost row had its own TextScaled size ("Boost" smaller than "Shop"; wrapped "Lucky Bone 12m 05s"). | Rail: one TextSize for every button, `0.36 x RailButton`. Boost rows: one TextSize for every row (`0.46 x row`), no wrap, truncate at the end. Boosts width is now 190 (min 170, max 220), so "Lucky Biscuit  14m 59s" fits. |
| 6 | Boost list could have up to 6 rows but the region only held 4, so extra rows overflowed toward the Debug button. | `MaxRows = 6`. Rows that do not fit in the region are hidden. |
| 7 | `$3.4K/s` rate rendered at 9 px on phone. | Currencies height went from 96 to 100 and the row fractions to 0.38/0.22/0.28. It now renders at about 11 px. |
| 8 | Idle throw hints (for example "Next: buy a Training upgrade in the Shop!") would truncate on phone because wrapping was off. | The summary label now wraps (2 lines on phone). The preview checks these strings as alternatives. |
| 9 | The Book badge dot covered the "Book" label on small buttons. | The dot is now centred on the corner, 3 px in. |
| 10 | Horizontal tab strips (Book zones) gave no hint that they scroll. | 3 px scrollbar on `Tabs`. |
| 11 | The feed padding (4) was hard-coded in two places. | `HudLayout.Feed.Gap` is used by both Compute and NotificationController. |

Unchanged and verified clean: top bar clearance, 8 px margins, Theme corners, strokes and colours, contrast (white or tinted text on dark plum panels), and hierarchy (big Fredoka numbers and buttons, Gotham body text).

## Known gaps

- This is an HTML approximation. Fredoka One is real; Montserrat stands in for Gotham. Do a final pass in Studio's device emulator.
- The spectator banner (PlaceholderCutscene) uses fixed 40/58 px heights. On phone it is taller than the toasts. That is acceptable for a placeholder cutscene.
- On phone, the Boosts and Debug regions sit over the dynamic-thumbstick area. They are non-Active labels, but test touch input there in Studio.
- The Modal can overlap the jump reserve corner on phone. It is an overlay with a backdrop and does not cover the button itself.
