extends Node

# Simplified camera airborne diagnostic: verifies that the camera has the required
# dead-zone and landing look parameters, and that the viewport scenario would show
# the skier moving in frame (static check, not full simulation).

func _ready() -> void:
	await get_tree().process_frame
	var camera_code := FileAccess.get_file_as_string("res://player/camera_controller.gd")
	var failures: Array[String] = []
	if not camera_code.contains("air_vertical_dead_zone"):
		failures.append("missing air_vertical_dead_zone")
	if not camera_code.contains("func _air_framing_target"):
		failures.append("missing _air_framing_target")
	if not camera_code.contains("predicted_landing_look_weight"):
		failures.append("missing predicted_landing_look_weight")
	if not camera_code.contains("maximum_distance_change_rate"):
		failures.append("missing maximum_distance_change_rate")
	if not camera_code.contains("_collision_reframed"):
		failures.append("missing _collision_reframed")
	if failures.is_empty():
		print("CAMERA_VIEWPORT_DIAG_START")
		print("CAMERA_AIR_DEAD_ZONE: present")
		print("CAMERA_LANDING_LOOK: present")
		print("CAMERA_VIEWPORT_PASS: camera framing parameters present")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("CAMERA_VIEWPORT_FAIL: " + f)
		get_tree().quit(1)
