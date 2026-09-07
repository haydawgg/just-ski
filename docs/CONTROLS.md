# Controls

Summit Sessions is designed around a standard gamepad, with keyboard bindings kept for development and accessibility. Gameplay input is declared through Godot's InputMap; gameplay code reads named actions rather than hard-coding controller button indices.

## Core mapping

| Action | Controller | Keyboard |
|---|---|---|
| Carve left / right | Left stick X | A / D |
| Ski pressure | Left stick Y | W / S |
| Trick input | Right stick | Arrow keys |
| Pop | Right-stick preload and flick | Space |
| Tuck | RT / R2 | Shift |
| Brake | LT / L2 or B / Circle | Ctrl |
| Left / right hand | LT / L2, RT / R2; bumpers alternate | Q / E |
| Rail balance | Left stick X | A / D |
| Save marker | D-pad Up | T |
| Return to marker | Y / Triangle or D-pad Down | R |
| Pause | Menu / Start | Esc |
| Settings | Pause → Settings | Pause → Settings |
| Debug overlay | — | F3 |
| Arm / stop clip capture | — | F9 |

The HUD changes prompt families based on the most recently used input device.

## Left stick

On snow, the left stick is the ski-control input:

- X carves left and right.
- Y changes ski pressure. Forward pressure loads the tips; back pressure helps unweight the skis.

In the air, the same axes provide limited yaw and flip correction. This precision assist is finite for the whole jump and remains lower-authority than the committed takeoff.

On rails, left-stick X counters balance drift.

## Right-stick Flick-It input

The right stick is the primary trick control. Ground and rail takeoffs begin from a preload by holding the stick down, then flicking out of that setup.

Ground release regions provide familiar controls, but the physical throw axis varies continuously between them:

- Down → up with neutral left-stick pressure: straight pop.
- Down → up while holding left-stick forward/back: frontflip/backflip intent.
- Down → left or right: pop with spin intent.
- Down → diagonal: pop with an off-axis/cork intent whose yaw/roll blend follows the release angle.

Left-stick pressure, edge input, and right-stick release direction are combined into one local rotation axis. Spin, flip, and cork names are derived afterward for presentation and scoring; they do not select separate physics impulses.

On rails, down → up remains an unmodified rail pop.

Airborne gestures while not grabbing:

- Holding the committed direction compacts the skier and preserves angular momentum through lower effective inertia.
- Holding the opposite direction opens the skier and checks the committed rotation.
- A neutral takeoff cannot start a new spin, cork, or flip in midair.
- Pitch-dominant axes use up/down management; yaw/off-axis throws use left/right management.

The stick must recenter once after the takeoff release before airborne management becomes active. After that, held input continuously controls compact/open body shape without generating repeated rotation impulses. Small left-stick corrections draw from a finite assist budget and cannot regenerate during the jump.

Keyboard arrows provide the corresponding digital trick directions. Space remains the keyboard pop fallback because a keyboard cannot reproduce the analog preload path.

## Tuck, brake, and airborne hands

The triggers are state-dependent:

- LT / L2 brakes while grounded.
- RT / R2 tucks while grounded.
- B / Circle is an additional full-brake input.
- In the air, LT / L2 controls the left hand and RT / R2 controls the right hand.
- LB / L1 and RB / R1 are alternate airborne hand inputs.

A trigger already held for braking or tucking through takeoff does not immediately become a grab. Release it after takeoff and press it again to arm that hand. If both ground trigger functions are requested together, braking takes precedence over tuck.

## Grabs and style poses

Airborne hand input combines with right-stick direction:

- Left trigger: left Safety.
- Right trigger: right Safety.
- Left hand + stick right, or right hand + stick left: Mute.
- Either hand + stick up: Japan.
- Left hand + stick down: Tail.
- Right hand + stick down: Nose.
- Both triggers + centered stick: Double.
- Both triggers + dominant horizontal input: Shifty left / right.
- Both triggers + dominant vertical input: Spread Eagle / Daffy.

Analog trigger pressure controls reach. Right-stick magnitude controls tweak or style intensity. While a grab or style pose owns the right stick, the same movement is not also committed as a rotation gesture.

Physical grabs and style-only poses are separate presentation concepts, but both feed the established trick/style scoring path.

## Rails

A neutral rail capture produces a 50-50 stance. During a grind:

- Flick left or right to select the boardslide presentation.
- Use left-stick X to counter balance drift.
- Use a down → up right-stick gesture to pop off.

Rails can be traversed in either direction when the spline and momentum allow it. Losing the balance threshold releases the skier back into air rather than causing an immediate bail.

## Session controls

A marker can only be saved while grounded on valid snow contact. Returning to the marker uses the normal session respawn path, which clears transient crash, rail, landing, and motion state.

The pause menu is controller navigable and includes an in-game trick guide.

## Debug overlay

F3 toggles gameplay and presentation telemetry. The exact fields evolve with the prototype, but the overlay is intended to expose the active locomotion state, ski/contact data, carving and skid response, trick input, landing prediction, rail state, crash context, and rig/animation diagnostics.

## Gameplay clip recorder

F9 controls the built-in run recorder:

1. Press F9 while not recording to arm capture.
2. Start a run from the summit.
3. Capture begins automatically.
4. It ends at the finish trigger, when F9 is pressed again, or at the 90-second safety cap.
5. Encoding finishes after recording stops.

Capture format:

- 960×540
- 30 fps
- JPEG frames muxed as MJPEG-in-MP4
- no game audio
- saved as `ski_clip_<timestamp>.mp4`
- Downloads folder when available, otherwise the Godot user-data directory

The recorder will not start a new capture while the previous clip is still being encoded.
