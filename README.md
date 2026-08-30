# Summit Sessions

A controller-first, single-player park-skiing prototype for Godot **4.7.2 stable**. The current build is a fully generated graybox resort: no manual editor setup or third-party assets are required.

## Run

Open `project.godot` in Godot 4.7.2 and press **F6/F5**, or run:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe --path .
```

The project uses Forward+ and requests Jolt Physics at 120 physics ticks per second.

## Controls

| Action | Controller | Keyboard |
|---|---|---|
| Carve / pressure | Left stick | A / D carve, W / S pressure |
| Preload / pop | Right stick down, then flick | Space |
| Spin / flip / cork | Right-stick flicks; left stick trims | Arrow keys |
| Ground tuck | RT / R2 | Shift |
| Brake / hockey stop | LT / L2 or B / Circle | Ctrl |
| Air grabs / tweaks | LT/RT; bumpers are alternates; right stick tweaks | Q / E + arrows |
| Rail stance / pop-off | Right-stick left/right or down→up; left stick balances | Arrow keys; A/D balance |
| Save session marker | D-pad Up | T |
| Return to marker | Y / Triangle or D-pad Down | R |
| Pause / options | Menu / Start | Esc |
| Debug overlay and vectors | — | F3 |

All gameplay input is defined through Godot's InputMap. The HUD switches prompts based on the last-used input family.

## Implemented prototype slice

- Momentum-based slope gravity (steeper ~18° park face), lower air gravity for hang time, powder/packed/groomed grip and drag, bounded lateral edge grip, carving, skidding, stick pressure, tuck, and hockey-stop braking.
- Skate-inspired Flick-It preload/pop gestures, discrete spin/flip/cork impulses sized for ~360° on the middle kicker, low-authority air trim, ballistic landing prediction, plausibility-gated landing evaluation, and momentum-preserving controlled crash/recovery.
- Slope-relative spring camera with larger skier framing, per-channel smoothing (split horizontal/vertical springs, yaw lag scaled by speed, stabilized pitch), carve-aware travel/heading look blending, restrained turn bank, filtered terrain up-vector, smoothed air framing, speed look-ahead/FOV, and collision avoidance.
- Signed world-triplanar CC0 snow PBR with Fast and Premium shader tiers, directional groomer corduroy, distance-faded detail, reflection-driven crystals, and premium SSS/transmittance.
- Reusable spline-backed rails/boxes/tubes with height/approach validation, blended capture, balance drift / slip-off, bidirectional and reverse travel, grind friction, and pop-off.
- Gameplay-readable layered skier animation with athletic carve/slarve/switch silhouettes, trailing poles, setup→compact→spot→open spin phases, distinct flip/cork shapes, data-driven physical grabs and independent spread/daffy/shifty styles, contrasted rail stances, clean-landing stomp, delta-filtered inertia, predictive pre-bail, and directional crash poses.
- Spin/flip/grab/grind recognition, landing quality, centralized timed combo / line-link scoring, combo and rail-balance HUD feedback, surface-aware procedural audio, throttled rumble, and snow spray.
- Data-driven ~300 m graybox face with six zones and 36 authored features: tables, rollers, hips, side hits, berms, moguls, butter pads, rails, boxes, tubes, wallrides, bonks, gates, and a cannon.
- Fast session markers plus automatic recovery after leaving the playable course.
- A finish trigger with medal targets, best-trick and clean/bail summaries, persisted personal bests, and immediate summit/marker/free-ride follow-up actions.
- Controller-navigable pause/options menu with staged pending settings, explicit Apply, Cancel, Reset Defaults, and persistence.

## Verification

The physics/handling and snow upgrades have no-launch static verification paths:

```powershell
.\tests\physics_static_acceptance.ps1
.\tests\shader_static_acceptance.ps1
```

The runtime quality gate launches every gameplay suite and rejects engine, shader, script, and acceptance errors:

```powershell
.\tests\runtime_quality_gate.ps1
```

Individual gameplay suites can also be launched during a controlled play/test session:

```powershell
$env:APPDATA=(Resolve-Path '.godot_user\roaming').Path
$env:LOCALAPPDATA=(Resolve-Path '.godot_user\local').Path
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/runtime_smoke.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/gameplay_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/physics_benchmark.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/physics_collision_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/settings_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/character_presentation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/skeleton_rig_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/jump_animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/landing_animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/rail_animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/trick_animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/grab_animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/animation_silhouette_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/animation_polish_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/crash_recovery_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ski_feel_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/terrain_suspension_course.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/flick_trick_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/flick_gameplay_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/trick_ui_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/session_flow_acceptance.tscn
```

Generate the deterministic 21.6-second actual-follow-camera animation comparison (MP4 plus 18 review frames):

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 30 --disable-vsync res://tests/animation_silhouette_inspection.tscn -- --capture-silhouette-showcase
```

The comparison is written to `.godot_user/captures/animation_silhouette_comparison.mp4`.

Use `-- --primitive-skier` to force the temporary primitive presentation adapter. Normal runtime uses `AUTO`, which prefers the configured Skeleton3D body and records a validation reason before falling back when that asset is unavailable.

See `docs/KNOWN_ISSUES.md` for the honest boundary between exercised automated behavior and hardware/visual checks that still require a human play session.
