# Morph Matrix Track-FX

This module tree contains the Track-FX implementation.

## Boundaries

- `Core/TrackFXMatrixEngine.lua` owns Matrix commands and adapter-independent behavior.
- `Core/TrackFXMatrixSnapshot.lua` owns the registered instance state model.
- `Core/TrackFXMatrixRuntime.lua` owns deferred frames, shutdown commits, and context cleanup.
- `Tests/test_track_fx_matrix_engine.lua` exercises the public engine seam with a fake adapter.
- The ReaImGui `File` menu saves and loads portable `.mmxpreset` files.
- Save opens the native operating-system Save dialog in `User Presets/` by default; Load opens that folder.
- Learned parameters retain REAPER `TrackFX_GetParamIdent` values when available, so stale dynamic mappings are rejected instead of guessed.
- The corner panel includes `Randomize All`, which randomizes all four corners and the cursor position.
- The Matrix cursor reveals a soft, low-alpha field of corner-colored background dots, leaving the rest of the matrix dark.
- Each mapped parameter has lower and upper Matrix clamp handles; they remap the full interpolated Matrix range into the selected interval and persist with project Snapshots and portable Presets.
- Direct edits on the mapped fader expand a crossed lower or upper clamp to include the user-selected value; Matrix-driven updates do not change clamp bounds.
- Assigned parameter corner chips can be removed with right-click or Ctrl-click; the selected corner returns to its baseline while other assignments remain intact.
- Left-clicking a Matrix corner Save icon stores the corner; right-clicking it clears all mapped parameter assignments from that corner and restores their baselines. The corner number remains a snap control.
- A successful full-corner Save also snaps the cursor to the saved corner.
- `Clear Mappings` preserves the mapped parameters, clears all corner assignments, restores their baselines and full `0..1` clamp ranges, recenters the cursor, and persists the reset state.

The REAPER adapter, project persistence, Preset files, and ReaImGui entry point are included. Take-FX modules should use separate names and adapters.

## Test

Run `Tests/run_all.lua` inside REAPER with ReaImGui installed. The aggregate covers pure fake-adapter tests, persistence failures, UI lifecycle fakes, and repeated real ReaImGui frames.

For the real dynamic-parameter fixture, create an isolated one-track project with a track named `Morph Matrix Pro-Q 4 Fixture`, then run `Tests/test_track_fx_matrix_live_pro_q4.lua` through the MCP bridge. The test inserts the installed `FabFilter Pro-Q 4.vst3`, verifies `Band 1 Used` remains available while inactive, verifies `Band 1 Frequency` follows the band's active state, checks its `TrackFX_GetParamIdent` identity after reactivation, and removes the test FX before returning. It is intentionally separate from `run_all.lua` because it requires the dedicated live fixture.