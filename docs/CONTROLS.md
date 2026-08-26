# Controls and Input

All actions are declared in `project.godot` and use Godot's SDL-compatible input abstraction. Gameplay code never depends on controller button indices.

## Controller layout

- Left stick carves on snow, trims yaw in air, and balances on rails.
- Right stick is the Flick-It trick control.
- LT/L2 brakes on snow and controls the left hand after takeoff.
- RT/R2 tucks on snow and controls the right hand after takeoff.
- B/Circle is an alternate brake; LB/L1 and RB/R1 are alternate hand inputs.
- Y/Triangle or D-pad Down returns to the session marker; D-pad Up saves a grounded marker.
- Menu/Start pauses.

A trigger held for braking or tucking through takeoff cannot accidentally grab. Release it in the air and press it again to arm that hand. When both ground triggers are held, braking takes precedence over tuck.

## Flick-It gestures

Ground and rail takeoffs begin by holding the right stick down to compress:

- Down then up: straight pop.
- Down then left/right: pop with a left/right spin impulse.
- Down then diagonal: pop with a left/right cork impulse.

While airborne and not grabbing:

- Flick left/right: spin impulse.
- Flick up: frontflip impulse.
- Flick down: backflip impulse.
- Flick diagonally: left/right cork impulse.
- Recenter before the next gesture. Repeated flicks can build larger rotations up to the physics angular-speed cap.

Recognition uses tunable setup/flick/center thresholds, a 350 ms gesture window, a 120 ms forgiving buffer, a 100 ms repeat cooldown, and generous direction sectors. The left stick supplies low-authority correction rather than starting tricks by itself.

## Grabs and tweaks

Fresh airborne trigger presses combine with right-stick style direction:

- LT/L2: left safety; RT/R2: right safety.
- Left hand + stick right or right hand + stick left: mute.
- Either hand + stick up: Japan.
- Left hand + stick down: tail; right hand + stick down: nose.
- Both triggers: double grab.
- Both + up: spread eagle; both + down: daffy.

Trigger pressure controls reach. Right-stick magnitude controls tweak intensity. While a grab is active, right-stick movement tweaks the pose and cannot also commit a rotation gesture. The animation and scoring systems consume the same resolved grab command.

## Rails and keyboard fallback

Neutral rail capture produces a 50-50. Flick left/right to select a boardslide and use a down-to-up flick to pop off. Left stick remains the balance input.

Keyboard development/accessibility bindings remain A/D, Space, Shift, Ctrl, arrow keys, Q/E, R, T, Esc, and F3. Space preserves the charge/release pop fallback because a keyboard cannot reproduce an analog Flick-It path.

The optional HUD visualizer shows the recent right-stick path, recognized command, presentation phase, gesture strength, trigger pressure, and active grab. The pause menu contains the same mappings in a controller-navigable Trick Guide.
