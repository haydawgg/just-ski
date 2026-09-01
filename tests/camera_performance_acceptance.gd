extends Node3D

## Deterministic camera update benchmark. This does not impose a machine-specific
## frame-time budget; it records the cost at each supported physics rate while
## asserting the same finite, bounded pose contract used by the runtime tests.

const SAMPLE_RATES := [30, 60, 120]
const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 720
const TRACK_RADIUS := 1.8
const TRACK_SPEED := 11.0

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	for rate: int in SAMPLE_RATES:
		_run_sample(rate)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_PERF_PASS: deterministic 30/60/120 Hz camera samples stayed finite, bounded, and collision-safe")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_PERF_FAIL: " + failure)
	get_tree().quit(1)

func _run_sample(rate: int) -> void:
	var floor := _create_floor()
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_position = Vector3.ZERO
	skier.velocity = Vector3(0.0, 0.0, -TRACK_SPEED)

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	var step := 1.0 / float(rate)
	for frame_index: int in WARMUP_FRAMES:
		_apply_target_motion(skier, float(frame_index) * step)
		camera_rig._physics_process(step)

	var previous_position := camera_rig.global_position
	var previous_distance := previous_position.distance_to(skier.global_position)
	var previous_skier_pos := skier.global_position
	var max_frame_usec := 0
	var start_usec := Time.get_ticks_usec()
	for frame_index: int in SAMPLE_FRAMES:
		var elapsed := float(WARMUP_FRAMES + frame_index) * step
		_apply_target_motion(skier, elapsed)
		var skier_pos_now := skier.global_position
		var target_disp := skier_pos_now - previous_skier_pos
		var frame_start_usec := Time.get_ticks_usec()
		camera_rig._physics_process(step)
		max_frame_usec = maxi(max_frame_usec, Time.get_ticks_usec() - frame_start_usec)
		var position := camera_rig.global_position
		var distance := position.distance_to(skier_pos_now)
		if not position.is_finite() or not camera_rig.camera.global_transform.is_finite() or not is_finite(camera_rig.camera.fov):
			failures.append("%.0f Hz produced a non-finite camera pose at frame %d" % [float(rate), frame_index])
			break
		if distance < camera_rig.minimum_camera_distance - 0.02 or distance > camera_rig.maximum_camera_distance + 0.02:
			failures.append("%.0f Hz produced an out-of-bounds camera distance %.3f m at frame %d" % [float(rate), distance, frame_index])
			break
		var distance_delta := absf(distance - previous_distance)
		if distance_delta > camera_rig.maximum_distance_change_rate * step + 0.035:
			failures.append("%.0f Hz changed camera distance by %.3f m at frame %d" % [float(rate), distance_delta, frame_index])
			break
		var frame_translation := position - previous_position
		var frame_relative := frame_translation - target_disp
		# Relative correction limit: 12 m/s hard, 8 m/s comfortable. Allow 12 for this benchmark.
		if frame_relative.length() > camera_rig.maximum_relative_correction_speed * step + 0.045:
			failures.append("%.0f Hz relative camera correction %.3f m exceeded %.3f at frame %d" % [float(rate), frame_relative.length(), camera_rig.maximum_relative_correction_speed * step + 0.045, frame_index])
			break
		if not camera_rig._camera_destination_is_clear(position):
			failures.append("%.0f Hz placed the camera volume inside geometry at frame %d" % [float(rate), frame_index])
			break
		previous_position = position
		previous_distance = distance
		previous_skier_pos = skier_pos_now
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var average_usec := float(elapsed_usec) / float(SAMPLE_FRAMES)
	print(
		"CAMERA_PERF_SAMPLE hz=", rate,
		" frames=", SAMPLE_FRAMES,
		" elapsed_ms=", snappedf(float(elapsed_usec) / 1000.0, 0.01),
		" average_us=", snappedf(average_usec, 0.01),
		" max_frame_us=", max_frame_usec,
		" fallback_count=", camera_rig.debug_snapshot().get("camera_fallback_count", -1)
	)

	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
	remove_child(floor)
	floor.free()

func _apply_target_motion(skier: SkierController, elapsed: float) -> void:
	var lateral := sin(elapsed * 1.7) * TRACK_RADIUS
	var lateral_speed := cos(elapsed * 1.7) * 1.7 * TRACK_RADIUS
	skier.global_position = Vector3(lateral, 0.35, -TRACK_SPEED * elapsed)
	skier.velocity = Vector3(lateral_speed, 0.0, -TRACK_SPEED)
	skier.rotation.y = atan2(lateral_speed, TRACK_SPEED)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP

func _create_floor() -> StaticBody3D:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.5, 10000.0)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	floor.position = Vector3(0.0, 0.0, -5000.0)
	add_child(floor)
	return floor
