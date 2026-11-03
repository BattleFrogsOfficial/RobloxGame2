# Workstreams (who owns what)

Two sessions build this game in parallel. To keep merges clean, each owns a set of paths. Touch another
session's paths only through a PR note.

| Area | Paths | Owner |
|---|---|---|
| Design doc, balance, roster, server services, world builder, cutscene | `docs/DESIGN.md`, `data/**`, `tools/roster.py`, `src/server/**` (except ZoneDressing), `src/client/Cutscene/**` | Session A (Claude Code, daytime) |
| HUD / UI, pixel icons, UI layout checker | `src/client/UI/**`, `src/client/UIBootstrap.client.luau`, `src/shared/UI/**`, `src/shared/Config/Icons.luau`, `assets/icons/**`, `tools/icons.py`, `tools/uicheck/**`, `docs/UI_STYLE_GUIDE.md` | Session B (overnight) |
| Ball visuals and zone set dressing | `src/shared/Ball/**`, `src/server/World/ZoneDressing/**`, `src/shared/Config/WorldTheme.luau`, `docs/WORLD_ART.md` | Session B |
| Tests and CI | `tests/**`, `.github/workflows/**`, `tools/install-tools.sh` | Session B |
| Store presence | `docs/STORE_PRESENCE.md`, `assets/store/**` | Session B |

Integration points Session A needs to know about:

- `src/client/UIBootstrap.client.luau` starts the UI. If the cutscene controller wants the UI handle, call
  `require(Client.UI).Start{ PlaceholderCutscene = false }` yourself and set the attribute
  `UIStartedElsewhere = true` on the Client folder (or delete the bootstrap script).
- With `PlaceholderCutscene = true` (default) the UI shows the end card `Timers.Cutscene[rarity]` seconds
  after `ThrowResult` and fires `CutsceneFinished` itself. The cutscene module should set it to `false`
  and call `ui:ShowReveal(result, { OnClose = ... })` then `ui:FinishThrow(throwId)` at the end of its own
  sequence.
- The HUD owns throw input (Space / gamepad R2 / the ball button) and fires `ChargeBegin` /
  `ChargeRelease`. Pass `OwnsThrowInput = false` to `UI.Start` if the input lives elsewhere, then drive
  `ui.HUD:SetCharging(true, os.clock(), isTutorial)` / `SetCharging(false)` / `SetThrowLocked(bool)`.
- Settings that live on the server (`TreatPocketMode`, `KeepDupes`) are sent through a `SetSetting`
  RemoteFunction `(key, value)` **if it exists** under `ReplicatedStorage.Remotes`. It is not in
  `Remotes.luau` yet; add it there and handle it in DataService when convenient.
- Icons: `tools/icons.py` is the only source. After uploading PNGs from `assets/icons/`, paste ids into
  `src/shared/Config/Icons.luau`; nothing else changes.
