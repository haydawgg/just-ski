# Summit Sessions

Summit Sessions is a controller-first, single-player park-skiing prototype built in Godot 4.7. The project focuses on momentum-led skiing, Flick-It-style trick input, rail riding, procedural animation, and a deterministic graybox resort that can be launched without manual scene setup.

The current presentation combines project-built geometry and effects with two documented CC0 sources: the Snow 02 material set and the production skier body. See [Asset Sources](docs/ASSET_SOURCES.md) for attribution and processing details.

## Run

Open `project.godot` in Godot 4.7.2 stable and run the project, or use the bundled Windows engine when present:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe --path .
```

The main scene is `res://world/resort.tscn` and the renderer targets Forward+.

To run the warm-lighting variant, launch the sunset scene directly:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe --path . res://world/sunset_resort.tscn
```

The sunset profile enables Forward+ SDFGI for the static procedural resort geometry, with lower graphics presets disabling it automatically.

## Controls

| Action | Controller | Keyboard |
|---|---|---|
| Carve / pressure | Left stick | A / D, W / S |
| Preload / pop | Right stick down, then flick | Space |
| Spin / flip / cork | Right-stick flicks | Arrow keys |
| Air correction | Left stick | A / D / W / S |
| Tuck | RT / R2 | Shift |
| Brake / hockey stop | LT / L2 or B / Circle | Ctrl |
| Grabs / styles | Triggers, bumpers, right stick | Q / E + arrows |
| Rail balance | Left stick | A / D |
| Save marker | D-pad Up | T |
| Return to marker | Y / Triangle or D-pad Down | R |
| Pause | Menu / Start | Esc |
| Debug overlay | — | F3 |
| Arm / stop run capture | — | F9 |

Controller triggers change role after takeoff: LT/L2 and RT/R2 are ground brake/tuck inputs, then become airborne hand inputs after they are released and pressed again. See [Controls](docs/CONTROLS.md) for the full gesture and grab mapping.

## Current prototype

The playable slice includes:

- Four authoritative locomotion states: ground, air, grind, and bail.
- Slope-relative gravity, anisotropic ski friction, carving, skidding, pressure, tuck, braking, terrain suspension, and surface-specific handling.
- Charged pop and right-stick gesture recognition for spins, flips, corks, rail pop-off, grabs, tweaks, and style poses.
- Landing prediction, plausibility-gated landing evaluation, controlled crash/recovery, course recovery, and session markers.
- Spline-backed rails, boxes, and tubes with approach validation, bidirectional travel, balance drift, slip-off, and pop-off.
- Procedural skier presentation driven from gameplay telemetry, with a production Skeleton3D rig and a primitive fallback adapter.
- Triplanar snow shading with Fast and Premium tiers, procedural environment presentation, snow spray, audio, rumble, HUD feedback, scoring, combos, and finish results.
- A data-driven downhill park with jump, flow, and jib routes assembled from reusable procedural features.
- Controller-navigable options with staged Apply / Cancel / Reset behavior and persisted settings.
- Gameplay clip capture to MJPEG-in-MP4.

## Documentation

- [Controls](docs/CONTROLS.md) — input mapping, Flick-It gestures, grabs, rails, and clip capture.
- [Physics](docs/PHYSICS.md) — locomotion state ownership, ski handling, landings, crashes, rails, and tuning.
- [Animation](docs/ANIMATION.md) — presentation architecture, rig adapters, procedural layers, and animation test coverage.
- [Graphics](docs/GRAPHICS.md) — renderer settings, snow, environment, character presentation, HUD, and visual verification.
- [Asset Sources](docs/ASSET_SOURCES.md) — third-party source index and provenance.
- [Known Issues](docs/KNOWN_ISSUES.md) — automated coverage boundaries and remaining human validation work.

## Verification

Use the static checks for fast source-level validation:

```powershell
.\tests\physics_static_acceptance.ps1
.\tests\shader_static_acceptance.ps1
```

Use the runtime quality gate for the full headless acceptance pass:

```powershell
.\tests\runtime_quality_gate.ps1
```

`tests/runtime_quality_gate.ps1` is the source of truth for the runtime scene list. It launches the maintained acceptance, diagnostic, benchmark, environment, camera, character, animation, gameplay, and capture suites and fails on non-zero exits or emitted engine / shader / script / acceptance errors.

Run the complete local gate (static physics, static shaders, and every headless runtime scene) with one command:

```powershell
.\tests\quality_gate.ps1
```

Individual gameplay suites can also be launched during a controlled play/test session:

For a single scene, set the repository-local Godot user folders and launch the desired `.tscn` directly. Example:

```powershell
$env:APPDATA=(Resolve-Path '.godot_user\roaming').Path
$env:LOCALAPPDATA=(Resolve-Path '.godot_user\local').Path
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/gameplay_acceptance.tscn
```

## Visual review and capture

The deterministic animation silhouette comparison can be generated with:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-silhouette-showcase
```

The comparison is written under `.godot_user/captures/`.

During normal play, F9 arms the gameplay recorder. The next run started from the summit is captured at 960×540 / 30 fps until the finish, a manual F9 stop, or the recorder's safety cap. The result is written to the user's Downloads folder when available, with `user://` as a fallback. The file is MJPEG video in an MP4 container and does not include game audio.

Use `-- --primitive-skier` to force the generated primitive skier presentation for debugging or comparison. Normal runtime uses automatic rig selection and prefers the configured Skeleton3D production body.

## Scope

This repository is a prototype, not a finished content release. Automated tests exercise a large part of the gameplay and presentation contract, but controller feel, long-session comfort, hardware behavior, visual polish, clipping, and performance still require human play and profiling. The maintained boundary is documented in [Known Issues](docs/KNOWN_ISSUES.md).
