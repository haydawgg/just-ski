extends Node

signal device_changed(device_name: String)
signal controller_connection_changed(connected: bool)
signal active_controller_changed(device_id: int, family: String)

var last_device := "keyboard"
var active_joypad_id := -1
var active_controller_family := "controller"
var connected_joypads: Dictionary = {}
var _rumbled_devices: Dictionary = {}

func _ready() -> void:
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device: int in Input.get_connected_joypads():
		_register_controller(device)
	if not connected_joypads.is_empty():
		_select_lowest_connected_controller()

func _input(event: InputEvent) -> void:
	var next_device := last_device
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_register_controller(event.device)
		_set_active_controller(event.device)
		next_device = active_controller_family
	elif event is InputEventKey or event is InputEventMouse:
		next_device = "keyboard"
	if next_device != last_device:
		last_device = next_device
		device_changed.emit(last_device)

func axis(negative_action: StringName, positive_action: StringName) -> float:
	return _shape_axis(raw_axis(negative_action, positive_action))

func raw_axis(negative_action: StringName, positive_action: StringName) -> float:
	return Input.get_action_raw_strength(positive_action) - Input.get_action_raw_strength(negative_action)

func _shape_axis(raw: float) -> float:
	var inner := float(GameSettings.active.get("stick_deadzone", 0.18))
	var outer := float(GameSettings.active.get("stick_outer_deadzone", 0.06))
	var magnitude := absf(raw)
	if magnitude <= inner:
		return 0.0
	var normalized := clampf((magnitude - inner) / maxf(0.01, 1.0 - inner - outer), 0.0, 1.0)
	normalized = pow(normalized, float(GameSettings.active.get("stick_response", 1.35)))
	return signf(raw) * normalized

func vector(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	var value := Vector2(axis(left, right), axis(up, down))
	return value.limit_length(1.0)

func glyph(action: StringName) -> String:
	var pad := last_device != "keyboard" and active_joypad_id >= 0 and connected_joypads.has(active_joypad_id)
	var family := active_controller_family if pad else "keyboard"
	match action:
		&"jump": return "Right stick flick" if pad else "Space"
		&"respawn": return _family_glyph(family, "Y", "Triangle") if pad else "R"
		&"set_marker": return "D-pad Up" if pad else "T"
		&"brake": return _family_glyph(family, "LT", "L2") if pad else "Ctrl"
		&"grab_left": return _family_glyph(family, "LT", "L2") if pad else "Q"
		&"grab_right": return _family_glyph(family, "RT", "R2") if pad else "E"
		_: return str(action)

func rumble(weak: float, strong: float, duration: float) -> void:
	var device := _rumble_target()
	if device < 0:
		return
	var strength := float(GameSettings.active.get("controller_rumble", 0.75))
	var scaled_weak := weak * strength
	var scaled_strong := strong * strength
	if scaled_weak <= 0.001 and scaled_strong <= 0.001:
		return
	_rumbled_devices[device] = true
	Input.start_joy_vibration(device, scaled_weak, scaled_strong, duration)

func _rumble_target() -> int:
	return active_joypad_id if active_joypad_id >= 0 and connected_joypads.has(active_joypad_id) else -1

func stop_rumble() -> void:
	var devices := {}
	for device: Variant in _rumbled_devices.keys():
		devices[int(device)] = true
	for device: Variant in connected_joypads.keys():
		devices[int(device)] = true
	for device: int in Input.get_connected_joypads():
		devices[device] = true
	for device: Variant in devices.keys():
		Input.stop_joy_vibration(int(device))
	_rumbled_devices.clear()

func _controller_family(device: int) -> String:
	return _controller_family_from_name(Input.get_joy_name(device))

func _controller_family_from_name(raw_name: String) -> String:
	var name := raw_name.to_lower()
	if "playstation" in name or "dualshock" in name or "dualsense" in name:
		return "playstation"
	if "xbox" in name or "xinput" in name:
		return "xbox"
	return "controller"

func _family_glyph(family: String, xbox_glyph: String, playstation_glyph: String) -> String:
	if family == "xbox":
		return xbox_glyph
	if family == "playstation":
		return playstation_glyph
	return "%s / %s" % [xbox_glyph, playstation_glyph]

func _register_controller(device: int) -> void:
	if device < 0:
		return
	connected_joypads[device] = _controller_family(device)

func _set_active_controller(device: int) -> void:
	if device < 0:
		return
	if not connected_joypads.has(device):
		_register_controller(device)
	var family := str(connected_joypads.get(device, "controller"))
	var changed := active_joypad_id != device or active_controller_family != family
	if changed and active_joypad_id >= 0 and active_joypad_id != device:
		Input.stop_joy_vibration(active_joypad_id)
		_rumbled_devices.erase(active_joypad_id)
	active_joypad_id = device
	active_controller_family = family
	if changed:
		active_controller_changed.emit(active_joypad_id, active_controller_family)

func _select_lowest_connected_controller() -> void:
	if connected_joypads.is_empty():
		_clear_active_controller()
		return
	var ids: Array[int] = []
	for device: Variant in connected_joypads.keys():
		ids.append(int(device))
	ids.sort()
	_set_active_controller(ids[0])
	if last_device != "keyboard" and last_device != active_controller_family:
		last_device = active_controller_family
		device_changed.emit(last_device)

func _clear_active_controller() -> void:
	var changed := active_joypad_id != -1 or active_controller_family != "controller"
	active_joypad_id = -1
	active_controller_family = "controller"
	if changed:
		active_controller_changed.emit(active_joypad_id, active_controller_family)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var had_controller := not connected_joypads.is_empty()
	if connected:
		_register_controller(device)
		if active_joypad_id < 0:
			_select_lowest_connected_controller()
	else:
		Input.stop_joy_vibration(device)
		_rumbled_devices.erase(device)
		connected_joypads.erase(device)
		if active_joypad_id == device:
			if connected_joypads.is_empty():
				_clear_active_controller()
				if last_device != "keyboard":
					last_device = "keyboard"
					device_changed.emit(last_device)
			else:
				_select_lowest_connected_controller()
	stop_rumble()
	var has_controller := not connected_joypads.is_empty()
	if had_controller != has_controller:
		controller_connection_changed.emit(has_controller)
