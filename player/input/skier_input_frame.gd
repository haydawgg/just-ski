class_name SkierInputFrame
extends TrickInputSample

## Immutable-by-convention view of every gameplay input sampled for one
## physics tick. SkierController owns one instance and the sampler overwrites it
## exactly once before state policy runs.

var sequence := 0
var steer_raw := 0.0
var steer := 0.0
var pressure := 0.0
var trick_stick := Vector2.ZERO
var movement_stick := Vector2.ZERO
var brake := 0.0
var tuck := 0.0
var jump_pressed := false
var jump_held := false
var jump_released := false
var respawn_pressed := false
var marker_pressed := false

func clear_values() -> void:
	reset()
	steer_raw = 0.0
	steer = 0.0
	pressure = 0.0
	trick_stick = Vector2.ZERO
	movement_stick = Vector2.ZERO
	brake = 0.0
	tuck = 0.0
	jump_pressed = false
	jump_held = false
	jump_released = false
	respawn_pressed = false
	marker_pressed = false
