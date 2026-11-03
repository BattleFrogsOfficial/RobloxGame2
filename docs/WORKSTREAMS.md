# Workstreams (who owns what)

Sessions build this game in parallel. To keep merges clean, each owns a set of paths. Touch another
session's paths only through a PR note.

| Area | Paths | Owner |
|---|---|---|
| Design doc, balance, roster, server services, world builder, cutscene | `docs/DESIGN.md`, `docs/WORLD.md`, `data/**`, `tools/roster.py`, `tools/balance_sim.py`, `tools/world_bounds.py`, `tools/worldcheck/**`, `src/server/**`, `src/shared/Cutscene/**`, `src/client/Cutscene/**`, `src/client/Controllers/**`, `src/client/BallFlight.client.luau`, `src/client/ZoneAmbience.client.luau` | Session A |
| HUD / UI, pixel icons, UI layout checker | `src/client/UI/**`, `src/client/Main.client.luau`, `src/shared/UI/**`, `src/shared/Config/Icons.luau`, `assets/icons/**`, `tools/icons.py`, `tools/uicheck/**`, `docs/UI_STYLE_GUIDE.md`, `docs/qa/hud/**` | Session B |
| Shared maths and configs | `src/shared/Config/**`, `src/shared/Util/**`, `src/shared/Remotes.luau`, `tools/tests/**` | Either, with a note in the PR |

Integration points:

- `src/client/Main.client.luau` is the only client entry script. It starts the UI with
  `require(Client.UI).Start{ PlaceholderCutscene = false }`, then `Cutscene` (`src/client/Cutscene/init.luau`)
  and `Controllers/WorldController` with the UI handle (if the cutscene fails to start, the UI's built-in end
  card is switched back on). `BallFlight.client.luau` (other players' throws via `Cutscene/Spectator`) and
  `ZoneAmbience.client.luau` (per-zone colour grading) are standalone LocalScripts.
- `Cutscene` starts a `Director` session at the meter release (`ui.ThrowReleased`), buffers the `ThrowResult`
  into it, plays wind-up -> ball POV -> landing -> dog -> odds counter -> outcome, then
  `ui:ShowReveal(result, { OnClose = ... })` and `ui:FinishThrow(throwId)`, which fires `CutsceneFinished`
  exactly once for a server throw (never for test-panel fakes). Every timing is in `Config/Cutscene.luau`;
  the server's timeout (`Config/Timers.Cutscene`) is computed from it.
- The HUD owns throw input (`UI/Screens/HUD.luau` + `UI/Components/PowerMeter.luau`): the prompt and the
  vertical meter only show while the `OnPlatform` attribute is true and `ThrowQueuePos == 1`. First click /
  tap / Space / gamepad R2 fires `ChargeBegin`, the second fires `ChargeRelease`.
- Server-side settings (`TreatPocketMode`, `KeepDupes`) go through the `DogAction` remote
  (`SetTreatPocketMode`, `SetKeepDupes "<Rarity>=true|false"`); the client mirrors `PlayerState.Settings`.
- Icons: `tools/icons.py` is the only source (it writes `assets/icons/` and `src/shared/UI/PixelIcons.luau`).
  After uploading PNGs, paste ids into `src/shared/Config/Icons.luau`; nothing else changes.
