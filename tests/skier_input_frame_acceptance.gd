extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_all_joypad_bindings_are_device_independent()
	_test_keyboard_bindings()
	await _test_nonzero_joypad_event_and_snapshot()
	if failures.is_empty():
		print("SKIER_INPUT_FRAME_PASS: all-device bindings and one complete sampled input frame passed")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SKIER_INPUT_FRAME_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _test_all_joypad_bindings_are_device_independent() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"steer_forward", &"steer_back", &"trick_left", &"trick_right", &"trick_up", &"trick_down", &"tuck", &"brake", &"grab_left", &"grab_right", &"respawn", &"set_marker", &"pause"]:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				if event.device != -1:
					failures.append("%s still targets joypad device %d" % [action, event.device])

func _test_keyboard_bindings() -> void:
	_check_keyboard_binding(&"trick_left", KEY_LEFT)
	_check_keyboard_binding(&"trick_right", KEY_RIGHT)
	_check_keyboard_binding(&"debug_toggle", KEY_F3)

func _check_keyboard_binding(action: StringName, expected_physical_keycode: Key) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == expected_physical_keycode:
			return
	failures.append("%s is missing physical keyboard binding %s" % [action, expected_physical_keycode])

func _test_nonzero_joypad_event_and_snapshot() -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 7
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 1.0
	Input.parse_input_event(event)
	await get_tree().process_frame
	var sampler := SkierInputSampler.new()
	var frame := SkierInputFrame.new()
	sampler.sample_into(frame)
	if frame.sequence != 1:
		failures.append("First sampled physics frame did not receive sequence 1")
	if frame.steer_raw < 0.99 or frame.steer <= 0.0 or frame.movement_stick.x <= 0.0:
		failures.append("Joypad 7 steering did not reach the deterministic snapshot")
	if frame.trick_stick != frame.right_stick or frame.movement_stick != frame.left_stick:
		failures.append("TrickInputSample compatibility fields diverged from the full snapshot")
	sampler.sample_into(frame)
	if frame.sequence != 2:
		failures.append("Sampler did not advance exactly once per capture")
	var release_event := event.duplicate() as InputEventJoypadMotion
	release_event.axis_value = 0.0
	Input.parse_input_event(release_event)
	Input.action_release("steer_right")
