# Controls

## Keyboard

- A/D steer, W/S pressure, Shift tuck, Ctrl brake, Space pop/tricks.
- Q/E grab in air, arrows trick flicks, T marker, R return, F3 debug.
- F9 start/stop a gameplay clip (max 15 s, 960x540 @ 30 fps) saved to your Downloads folder as `ski_clip_<timestamp>.mp4` (MJPEG-in-MP4; plays in VLC, Windows Media Player, and QuickTime); a red REC indicator shows while capturing and encoding finishes in the background.

## Controller and Input

All actions are declared in `project.godot` and use Godot's SDL-compatible input abstraction. Gameplay code never depends on controller button indices.

## Controller layout

- Left stick X carves on snow, trims yaw in air, and balances on rails.
- Left stick Y pressures the skis on snow (forward = tip bite / speed, back = unweight) and trims flip in air.
- Right stick is the Flick-It trick control.
- LT/L2 provides analog braking on snow and controls the left hand after takeoff.
- RT/R2 tucks on snow and controls the right hand after takeoff.
- B/Circle is a full-brake fallback; LB/L1 and RB/R1 are alternate hand inputs.
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
- Both triggers + centered right stick: double grab.
- Both + dominant horizontal right-stick input: mirrored left/right shifty.
- Both + dominant vertical input: spread eagle up, daffy down. On diagonals, the larger axis wins.

Trigger pressure controls reach. Right-stick magnitude controls grab tweak or style intensity. While a grab/style is active, right-stick movement cannot also commit a rotation gesture. Physical grabs and style-only poses are resolved separately, but both feed the existing style scoring path.

## Rails and keyboard fallback

Neutral rail capture produces a 50-50. Flick left/right to select a boardslide and use a down-to-up flick to pop off. Left stick X is balance; ignore it long enough on a kink or boardslide and you slip off into air. Uphill / rainbow features can reverse and slide you back.

Keyboard development/accessibility bindings remain A/D (carve), W/S (pressure), Space, Shift, Ctrl, arrow keys, Q/E, R, T, Esc, and F3. Space preserves the charge/release pop fallback because a keyboard cannot reproduce an analog Flick-It path.

The optional HUD visualizer shows the recent right-stick path, recognized command, presentation phase, gesture strength, trigger pressure, and active grab. The pause menu contains the same mappings in a controller-navigable Trick Guide.
