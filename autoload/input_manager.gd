extends Node

signal device_changed(device_name: String)
signal controller_connection_changed(connected: bool)

var last_device := "keyboard"

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _input(event: InputEvent) -> void:
	var next_device := last_device
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		next_device = _controller_family(event.device)
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
	var pad := last_device != "keyboard"
	match action:
		&"jump": return "Right stick flick" if pad else "Space"
		&"respawn": return "Y / Triangle" if pad else "R"
		&"set_marker": return "D-pad Up" if pad else "T"
		&"brake": return "LT / L2" if pad else "Ctrl"
		&"grab_left": return "LT / L2" if pad else "Q"
		&"grab_right": return "RT / R2" if pad else "E"
		_: return str(action)

func rumble(weak: float, strong: float, duration: float) -> void:
	if last_device == "keyboard":
		return
	var strength := float(GameSettings.active.get("controller_rumble", 0.75))
	Input.start_joy_vibration(0, weak * strength, strong * strength, duration)

func stop_rumble() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)

func _controller_family(device: int) -> String:
	var name := Input.get_joy_name(device).to_lower()
	if "playstation" in name or "dualshock" in name or "dualsense" in name:
		return "playstation"
	if "xbox" in name or "xinput" in name:
		return "xbox"
	return "controller"

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected:
		stop_rumble()
	controller_connection_changed.emit(connected)
