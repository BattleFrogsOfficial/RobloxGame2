# QA: HUD layout

Superseded. The first HUD pass was checked with an HTML re-implementation (`tools/hud_preview.js`) of the
old controller-based client. That client was replaced by the UI kit in `src/client/UI/` (screens, components,
Router, State), and the preview tool and its screenshots were deleted with it.

The current check is `tools/uicheck`:

- `lune run tools/uicheck/run.luau -- --quiet` builds the real client UI (`src/client/UI`) under a headless Roblox
  emulator (`tools/uicheck/roblox.luau`) at desktop, laptop, tablet and phone viewports, runs the layout rules
  from `docs/UI_STYLE_GUIDE.md` section 9 (overlap, off-screen, safe area, jump-button reserve, text fit, touch
  target size) over every scenario, and writes `build/ui-preview/*.svg` + `report.json`. It must report
  0 errors and 0 warnings.
- `node tools/uicheck/screenshot.js build/ui-preview` renders those SVGs to PNG for a visual review.

Kept screenshots: `docs/qa/hud/meter/` (throw prompt and vertical power meter: off the platform, waiting in the
queue, idle "Click/Tap to throw", charging at 0/50/100, desktop and phone).

## Known gaps

- The emulator approximates Roblox text metrics (Fredoka One / Gotham). Do a final pass in Studio's device
  emulator.
- On phone, check touch input around the dynamic thumbstick and the jump button in Studio.
