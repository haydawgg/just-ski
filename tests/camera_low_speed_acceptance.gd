extends Node3D

const STEP := 1.0 / 120.0
const MAXIMUM_FRAME_TRAVEL := 0.45

var failures: Array[String] = []

func _ready() -> void:
	_run_low_speed_pivot_reproduction()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_LOW_SPEED_PASS: slow pivots retained stable framing and clearance")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_LOW_SPEED_FAIL: " + failure)
	get_tree().quit(1)

func _run_low_speed_pivot_reproduction() -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.5, 80.0)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	floor.position.y = -0.25
	add_child(floor)

	var skier := SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_position = Vector3.ZERO

	var camera_controller := SkiCameraController.new()
	camera_controller.set_physics_process(false)
	add_child(camera_controller)
	camera_controller.set_target(skier)

	# Establish a normal downhill follow pose before entering the unstable band.
	skier.velocity = Vector3(0.0, 0.0, -10.0)
	_step_and_measure(camera_controller, skier, 120, "settle")

	# Repeatedly cross the old 0.5 m/s heading threshold while pivoting the
	# gameplay body. Tiny velocity changes deliberately point in very different
	# directions, matching the 1-2 km/h clip reproduction.
	for frame_index: int in 240:
		if not failures.is_empty():
			break
		var direction_index := int(frame_index / 3) % 4
		var direction := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][direction_index] as Vector3
		var low_speed := 0.48 if frame_index % 2 == 0 else 0.56
		skier.velocity = direction * low_speed
		skier.rotation.y += deg_to_rad(3.0)
		_step_and_measure(camera_controller, skier, 1, "threshold pivot frame %d" % frame_index)

	# Finish at an almost stationary aggressive reorientation.
	for _frame_index: int in 120:
		if not failures.is_empty():
			break
		skier.velocity = Vector3(0.02, 0.0, -0.01)
		skier.rotation.y += deg_to_rad(4.0)
		_step_and_measure(camera_controller, skier, 1, "stationary pivot")

	var telemetry := camera_controller.debug_snapshot()
	for key: String in ["desired_yaw_degrees", "actual_yaw_degrees", "horizontal_speed", "target_distance"]:
		if not telemetry.has(key) or not is_finite(float(telemetry.get(key, NAN))):
			failures.append("Camera telemetry %s was missing or non-finite" % key)

	remove_child(camera_controller)
	camera_controller.queue_free()
	remove_child(skier)
	skier.queue_free()
	remove_child(floor)
	floor.queue_free()

func _step_and_measure(camera_controller: SkiCameraController, skier: SkierController, frames: int, phase: String) -> void:
	for _index: int in frames:
		var previous_position := camera_controller.global_position
		camera_controller._physics_process(STEP)
		var distance := camera_controller.global_position.distance_to(skier.global_position)
		var frame_travel := camera_controller.global_position.distance_to(previous_position)
		if not is_finite(distance) or distance < camera_controller.minimum_camera_distance - 0.01:
			failures.append("%s collapsed camera to %.3f m from the skier" % [phase, distance])
			return
		if camera_controller.global_position.y < 0.2:
			failures.append("Camera entered terrain at y=%.3f" % camera_controller.global_position.y)
			return
		if frame_travel > MAXIMUM_FRAME_TRAVEL:
			failures.append("Camera jumped %.3f m in one frame" % frame_travel)
			return
