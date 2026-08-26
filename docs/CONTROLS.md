# Controls and Input

All actions are declared in `project.godot` InputMap and queried by action name. No gameplay script relies on controller button indices.

The controller layout targets standard SDL mappings:

- Left stick: carve.
- Right stick: spin and flip in air.
- A/Cross: compress and pop.
- RT/R2: tuck.
- LT/L2 or B/Circle: braking/skid.
- LB/L1 and RB/R1: grabs with roll influence.
- Y/Triangle or D-pad Down: return to the session marker.
- D-pad Up: save a grounded marker.
- Menu/Start: pause.

Keyboard development bindings are A/D, Space, Shift, Ctrl, arrow keys, Q/E, R, T, Esc, and F3.

`InputManager` applies configurable inner/outer deadzones and a response exponent, detects the most recently used device family, updates HUD glyph text, responds to hot-plug/disconnect, and owns rumble shutdown.
