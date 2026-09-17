class_name SkierInputSampler
extends RefCounted

var _sequence := 0

func sample_into(frame: SkierInputFrame) -> void:
	_sequence += 1
	InputManager.begin_scope_frame()
	frame.clear_values()
	frame.sequence = _sequence
	frame.steer_raw = InputManager.raw_axis(&"steer_left", &"steer_right")
	frame.steer = InputManager.axis(&"steer_left", &"steer_right")
	frame.pressure = InputManager.axis(&"steer_back", &"steer_forward")
	frame.movement_stick = InputManager.vector(&"steer_left", &"steer_right", &"steer_forward", &"steer_back")
	frame.trick_stick = InputManager.vector(&"trick_left", &"trick_right", &"trick_up", &"trick_down")
	frame.brake = InputManager.gameplay_strength(&"brake")
	frame.tuck = InputManager.gameplay_strength(&"tuck")
	frame.left_trigger = InputManager.gameplay_strength(&"grab_left")
	frame.right_trigger = InputManager.gameplay_strength(&"grab_right")
	frame.jump_pressed = InputManager.gameplay_just_pressed(&"jump")
	frame.jump_held = InputManager.gameplay_pressed(&"jump")
	frame.jump_released = InputManager.gameplay_just_released(&"jump")
	frame.respawn_pressed = InputManager.gameplay_just_pressed(&"respawn")
	frame.marker_pressed = InputManager.gameplay_just_pressed(&"set_marker")
	frame.right_stick = frame.trick_stick
	frame.left_stick = frame.movement_stick
	frame.keyboard_pop_pressed = frame.jump_held
	frame.keyboard_pop_released = frame.jump_released
