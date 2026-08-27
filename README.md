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
| Carve | Left stick | A / D |
| Preload / pop | Right stick down, then flick | Space |
| Spin / flip / cork | Right-stick flicks; left stick trims yaw | Arrow keys |
| Ground tuck | RT / R2 | Shift |
| Brake / hockey stop | LT / L2 or B / Circle | Ctrl |
| Air grabs / tweaks | LT/RT; bumpers are alternates; right stick tweaks | Q / E + arrows |
| Rail stance / pop-off | Right-stick left/right or down→up | Arrow keys |
| Save session marker | D-pad Up | T |
| Return to marker | Y / Triangle or D-pad Down | R |
| Pause / options | Menu / Start | Esc |
| Debug overlay and vectors | — | F3 |

All gameplay input is defined through Godot's InputMap. The HUD switches prompts based on the last-used input family.

## Implemented prototype slice

- Four logical ski probes and slope-normal/downhill sampling.
- Momentum-based slope gravity, low longitudinal drag, bounded lateral edge grip, carving, skidding, tuck, and hockey-stop braking.
- Skate-inspired Flick-It preload/pop gestures, discrete spin/flip/cork impulses, low-authority air trim, weighted landing evaluation, and bail/recovery.
- Spring third-person camera with speed distance/FOV, look-ahead, slope-readable horizon, and collision avoidance.
- Reusable spline-backed rails/boxes/tubes, approach validation, bidirectional capture, grind friction, and pop-off.
- Detailed layered skier animation with directional setup/release, head spotting, mirrored spin/flip/cork silhouettes, continuous trigger-pressure grabs, two-bone hand-to-ski reach, rail balance, bail motion, and debug telemetry.
- Spin/flip/grab/grind recognition, landing quality, scoring, minimal HUD, speed/skid/rail procedural audio, rumble feedback, and snow spray.
- Seamless graybox mountain with jump, technical rail, side-hit, and freeride-edge lanes plus summit/base landmarks.
- Fast session markers and respawn.
- Controller-navigable pause/options menu with staged pending settings, explicit Apply, Cancel, Reset Defaults, and persistence.

## Verification

```powershell
$env:APPDATA=(Resolve-Path '.godot_user\roaming').Path
$env:LOCALAPPDATA=(Resolve-Path '.godot_user\local').Path
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/runtime_smoke.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/gameplay_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/physics_collision_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/settings_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/animation_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/flick_trick_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/flick_gameplay_acceptance.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/trick_ui_acceptance.tscn
```

See `docs/KNOWN_ISSUES.md` for the honest boundary between exercised automated behavior and hardware/visual checks that still require a human play session.
