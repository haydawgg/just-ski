extends Node

var failures: Array[String] = []

func _ready() -> void:
	var manager_script := load("res://autoload/input_manager.gd") as GDScript
	var manager = manager_script.new()
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(manager)
	await get_tree().process_frame
	manager.connected_joypads.clear()
	manager._clear_active_controller()
	manager.last_device = "keyboard"

	var availability: Array[bool] = []
	var active_changes: Array[Dictionary] = []
	manager.controller_connection_changed.connect(func(connected: bool) -> void: availability.append(connected))
	manager.active_controller_changed.connect(func(device_id: int, family: String) -> void:
		active_changes.append({"device": device_id, "family": family})
	)

	manager._on_joy_connection_changed(5, true)
	manager._on_joy_connection_changed(2, true)
	_check(availability == [true], "Controller availability was emitted once for aggregate connect state: " + str(availability))
	_check(manager.active_joypad_id == 5, "First connected controller became active")

	var joy_event := InputEventJoypadButton.new()
	joy_event.device = 2
	manager._input(joy_event)
	_check(manager.active_joypad_id == 2, "Input activity selected the physical joypad ID")
	_check(manager.last_device == "controller", "Unknown controller family used the generic presentation")
	_check(manager.glyph(&"respawn") == "Y / Triangle", "Generic controller glyph retained both face-button labels")

	var key_event := InputEventKey.new()
	manager._input(key_event)
	_check(manager.active_joypad_id == 2, "Keyboard presentation did not discard active controller identity")
	_check(manager.glyph(&"respawn") == "R", "Keyboard presentation used keyboard glyphs")

	manager._on_joy_connection_changed(2, false)
	_check(manager.active_joypad_id == 5, "Active disconnect selected the lowest connected joypad ID")
	_check(availability == [true], "Disconnecting one of several controllers emitted no aggregate disconnect: " + str(availability))
	manager._on_joy_connection_changed(5, false)
	_check(manager.active_joypad_id == -1, "Final disconnect cleared the active controller")
	_check(manager.last_device == "keyboard", "Final disconnect returned presentation to keyboard")
	_check(availability == [true, false], "Aggregate availability emitted a single final disconnect: " + str(availability))

	_check(manager._controller_family_from_name("Xbox Wireless Controller") == "xbox", "Xbox family was detected")
	_check(manager._controller_family_from_name("DualSense Wireless Controller") == "playstation", "PlayStation family was detected")
	_check(manager._controller_family_from_name("Unknown Pad") == "controller", "Unknown family used generic fallback")
	manager.connected_joypads[7] = "xbox"
	manager._set_active_controller(7)
	manager.last_device = "xbox"
	_check(manager.glyph(&"grab_left") == "LT" and manager.glyph(&"grab_right") == "RT", "Xbox glyphs used the active family")
	manager.connected_joypads[8] = "playstation"
	manager._set_active_controller(8)
	manager.last_device = "playstation"
	_check(manager.glyph(&"grab_left") == "L2" and manager.glyph(&"grab_right") == "R2", "PlayStation glyphs used the active family")
	manager.last_device = "keyboard"
	_check(manager._rumble_target() == 8, "Keyboard presentation discarded the active rumble target")
	_check(active_changes.size() >= 5, "Active controller changes were observable")
	_check(manager_script.source_code.find("start_joy_vibration(0") < 0, "Rumble is not hard-coded to joypad 0")

	manager.queue_free()
	if failures.is_empty():
		print("INPUT_MANAGER_PASS: controller identity, aggregate hotplug, glyph families, keyboard fallback, and rumble targeting passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("INPUT_MANAGER_FAIL: " + failure)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
