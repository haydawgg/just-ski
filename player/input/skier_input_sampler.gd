class_name SkierInputSampler
extends RefCounted

var _sequence := 0

func sample_into(frame: SkierInputFrame) -> void:
	_sequence += 1
	frame.clear_values()
	frame.sequence = _sequence
	frame.steer_raw = InputManager.raw_axis(&"steer_left", &"steer_right")
	frame.steer = InputManager.axis(&"steer_left", &"steer_right")
	frame.pressure = InputManager.axis(&"steer_back", &"steer_forward")
	frame.movement_stick = InputManager.vector(&"steer_left", &"steer_right", &"steer_forward", &"steer_back")
	frame.trick_stick = InputManager.vector(&"trick_left", &"trick_right", &"trick_up", &"trick_down")
	frame.brake = Input.get_action_strength(&"brake")
	frame.tuck = Input.get_action_strength(&"tuck")
	frame.left_trigger = Input.get_action_strength(&"grab_left")
	frame.right_trigger = Input.get_action_strength(&"grab_right")
	frame.jump_pressed = Input.is_action_just_pressed(&"jump")
	frame.jump_held = Input.is_action_pressed(&"jump")
	frame.jump_released = Input.is_action_just_released(&"jump")
	frame.respawn_pressed = Input.is_action_just_pressed(&"respawn")
	frame.marker_pressed = Input.is_action_just_pressed(&"set_marker")
	frame.right_stick = frame.trick_stick
	frame.left_stick = frame.movement_stick
	frame.keyboard_pop_pressed = frame.jump_held
	frame.keyboard_pop_released = frame.jump_released
