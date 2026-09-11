# Summit Sessions

Summit Sessions is a controller-first, single-player park-skiing prototype built for Godot 4.7.2 stable. The project focuses on momentum-led skiing, analog Flick-It-style trick input, rail riding, procedural animation, and a deterministic data-driven resort.

Project-authored code and content are released under the [MIT License](LICENSE). Third-party CC0/OFL material and processing records are documented in [Asset Sources](docs/ASSET_SOURCES.md).

## Run

Open `project.godot` in Godot 4.7.2 stable and run the project. The main scene is `res://world/resort.tscn` and the renderer targets Forward+.

When the bundled Windows engine is present:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe --path .
```

To launch the authored sunset validation variant directly:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe --path . res://world/sunset_resort.tscn
```

## Controls

| Action | Controller | Keyboard |
| --- | --- | --- |
| Carve / pressure | Left stick | A / D, W / S |
| Preload / pop | Right stick down, then flick | Space |
| Spin / flip / cork | Right-stick release direction | Arrow keys |
| Air correction | Left stick | A / D / W / S |
| Tuck | RT / R2 | Shift |
| Brake / hockey stop | LT / L2 or B / Circle | Ctrl |
| Grabs / styles | Triggers, bumpers, right stick | Q / E + arrows |
| Rail balance | Left stick | A / D |
| Save marker | D-pad Up | T |
| Return to marker | Y / Triangle or D-pad Down | R |
| Pause | Menu / Start | Esc |
| Debug overlay | — | F3 |
| Debug run capture | — | F9 |

Controller triggers change role after takeoff: LT/L2 and RT/R2 are ground brake/tuck inputs, then become airborne hand inputs after they are released and pressed again. See [Controls](docs/CONTROLS.md) for the full mapping.

## Current prototype

The playable slice includes:

- four authoritative locomotion states: ground, air, grind, and bail;
- slope-relative gravity, ski friction/grip, carving, skidding, pressure, tuck, braking, suspension, and surface-specific handling;
- charged pop and continuous-axis right-stick trick input with compact/open airborne management;
- landing prediction, plausibility-gated landing evaluation, controlled crash/recovery, course recovery, and session markers;
- spline-backed rails, boxes, and tubes with bidirectional travel, approach validation, balance drift, slip-off, and pop-off;
- procedural skier presentation driven by gameplay telemetry, with a production Skeleton3D rig and primitive fallback;
- triplanar snow, environment presentation, snow VFX, audio, rumble, HUD feedback, scoring, combos, and finish results;
- a data-driven downhill park organized into six sessionable spots plus an opt-in Session Yard profile;
- controller-navigable settings with staged Apply / Cancel / Reset behavior and persisted graphics settings;
- a prototype/debug 960×540 30 fps MJPEG-in-MP4 recorder without synchronized game audio.

## Design and architecture

Gameplay owns the authoritative skier root, collision, movement state, and trick history. Presentation systems consume that state but do not move the gameplay root.

The trick system is built around takeoff commitment rather than midair trick commands:

```text
preload -> analog throw -> committed rotation -> compact/open/check -> physical landing
```

Course content is deterministic and data-driven. Runtime construction and editor preview baking use the same course profiles and builders so there is one authoring source of truth.

## Documentation

Start with [Documentation](docs/README.md). The maintained docs are grouped by product/gameplay, presentation/world, validation/performance, and build/assets.

Key references:

- [Content Design](docs/CONTENT_DESIGN_PLAN.md)
- [Controls](docs/CONTROLS.md)
- [Physics](docs/PHYSICS.md)
- [Animation](docs/ANIMATION.md)
- [Graphics](docs/GRAPHICS.md)
- [Known Issues](docs/KNOWN_ISSUES.md)
- [Performance Baseline](docs/PERFORMANCE_BASELINE_1080P.md)
- [Release](docs/RELEASE.md)

Completed plans, dated postmortems, and one-off implementation reports are intentionally not kept as permanent docs; Git, issues, and pull requests retain that history.

## Verification

Fast source-level checks:

```powershell
.\tests\physics_static_acceptance.ps1
.\tests\shader_static_acceptance.ps1
```

Full headless runtime gate:

```powershell
.\tests\runtime_quality_gate.ps1
```

Complete local gate:

```powershell
.\tests\quality_gate.ps1
```

The hosted Quality Gate keeps static checks separate from five runtime shards (`environment-camera`, `physics`, `animation`, `tricks-gameplay`, and `systems-media`). The final `quality` job succeeds only when static preparation and every runtime shard pass.

For GPU-backed visual review:

```powershell
.\tests\visual_analysis_bundle.ps1
```

The generated `visual_report.md` links contact sheets, subject crops, structured telemetry, raw captures, and compatible-baseline comparisons. See [Visual Evidence](docs/VISUAL_EVIDENCE.md).

## Build and release

The supported engine is the official Godot 4.7.2 stable release. `export_presets.cfg` contains the maintained Windows Desktop export preset.

Install matching export templates, then run:

```powershell
$godot = $env:GODOT_PATH
New-Item -ItemType Directory -Force builds\windows | Out-Null
& $godot --headless --path . --export-release "Windows Desktop" builds\windows\SummitSessions.exe
```

Smoke-test the exported build on a machine with the required graphics driver:

```powershell
& .\builds\windows\SummitSessions.exe --headless --quit-after 120
```

See [Release](docs/RELEASE.md) and [Export Content](docs/EXPORT_CONTENT.md) for the maintained release contract.

## Scope

This repository is a prototype, not a finished content release. Automated tests cover a large part of the gameplay and presentation contract, but controller feel, long-session comfort, hardware behavior, visual polish, clipping, exported-build behavior, and representative-hardware performance still require human validation. Current unresolved defects are tracked in [Known Issues](docs/KNOWN_ISSUES.md), while broader human release checks live in [Production Ski-Run QA](docs/PRODUCTION_SKI_RUN_QA.md).