extends Node

## Deterministic screen-space camera acceptance. This intentionally drives the
## real SkiCameraController with a synthetic jump so a camera can fail on the
## same symptom as the gameplay clip without requiring a rendered recording.

const STEP := 1.0 / 120.0
const HARD_SAFE_RECT := Rect2(0.10, 0.08, 0.80, 0.80)
const INNER_SAFE_RECT := Rect2(0.30, 0.24, 0.40, 0.36)
const LANDING_RECT := Rect2(0.14, 0.46, 0.72, 0.36)
const FOV_RATE_LIMIT := 24.0
const LANDMARK_OFFSETS := [
	Vector3(0.0, 1.95, 0.0),
	Vector3(0.0, 1.05, 0.0),
	Vector3(-0.32, 0.78, 0.0),
	Vector3(0.32, 0.78, 0.0),
	Vector3(-0.34, 0.30, 0.0),
	Vector3(0.34, 0.30, 0.0),
	Vector3(-0.42, 0.10, -0.10),
	Vector3(0.42, 0.10, -0.10),
	Vector3(-0.52, 0.08, -0.65),
	Vector3(0.52, 0.08, -0.65),
	Vector3(-0.52, 0.08, 0.40),
	Vector3(0.52, 0.08, 0.40),
]

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	for step: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		_run_airborne_composition_reproduction(step)
		_run_carve_lookahead_reproduction(step)
		_run_foreground_occlusion_reproduction(step)
		_run_respawn_initialization_reproduction(step)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_VIEWPORT_PASS: airborne composition, landing framing, recovery, rates, and respawn initialization passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_VIEWPORT_FAIL: " + failure)
	get_tree().quit(1)

func _run_airborne_composition_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_position = Vector3(0.0, 0.35, 0.0)
	skier.state = SkierController.State.AIR
	skier.velocity = Vector3(0.0, 7.5, -10.0)

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	if not _validate_camera_exports(camera_rig, step):
		_remove_target_and_camera(skier, camera_rig)
		return

	var previous_distance := camera_rig.global_position.distance_to(skier.global_position)
	var previous_fov := camera_rig.camera.fov
	var landing_frames := 0
	var landing_visible_frames := 0
	var recovery_seen := false
	var frame_count := ceili(2.0 / step)
	for frame_index: int in frame_count:
		var elapsed := float(frame_index) * step
		var phase := clampf(elapsed / 1.8, 0.0, 1.0)
		var height := 0.35 + 3.6 * sin(phase * PI)
		var vertical_speed := 3.6 * PI / 1.8 * cos(phase * PI)
		var lateral_excursion := sin(elapsed * 3.7) * 2.45
		skier.global_position = Vector3(lateral_excursion, height, -10.0 * elapsed)
		skier.velocity = Vector3(0.0, vertical_speed, -10.0)
		# Rotate the gameplay body through a flip/spin while preserving velocity.
		# Airborne camera heading must remain trajectory-driven.
		skier.rotation = Vector3(0.35 * sin(elapsed * 5.0), elapsed * 4.0, 0.2 * cos(elapsed * 4.0))
		skier.state = SkierController.State.AIR
		skier.predicted_landing_valid = true
		skier.predicted_landing_point = Vector3(0.0, 0.35, -18.0)
		skier.predicted_landing_time = maxf(0.02, 1.8 - elapsed)

		camera_rig._physics_process(step)
		var bounds := _projected_landmark_bounds(camera_rig, skier)
		var snapshot := camera_rig.debug_snapshot()
		if not bool(snapshot.get("composition_valid", false)):
			failures.append("Airborne %.0f Hz frame %d reported invalid composition" % [1.0 / step, frame_index])
			break
		if not camera_rig._camera_destination_is_clear(camera_rig.global_position):
			failures.append("Airborne %.0f Hz frame %d placed the camera volume inside geometry" % [1.0 / step, frame_index])
			break
		if not _rect_contains_rect(HARD_SAFE_RECT, bounds):
			failures.append("Airborne %.0f Hz frame %d placed skier bounds %s outside hard safe rect" % [1.0 / step, frame_index, bounds])
			break
		if not _rect_contains_rect(INNER_SAFE_RECT, bounds):
			if snapshot.has("composition_recovery_active"):
				recovery_seen = recovery_seen or bool(snapshot.composition_recovery_active)
			else:
				failures.append("Airborne edge displacement exposed no composition recovery telemetry")
		var descending := vertical_speed < 0.0
		if descending and skier.predicted_landing_valid:
			landing_frames += 1
			var landing_screen := _project_normalized(camera_rig, skier.predicted_landing_point)
			if LANDING_RECT.has_point(landing_screen):
				landing_visible_frames += 1

		var distance := camera_rig.global_position.distance_to(skier.global_position)
		var fov := camera_rig.camera.fov
		if absf(distance - previous_distance) > camera_rig.maximum_distance_change_rate * step + 0.02:
			failures.append("Airborne %.0f Hz frame %d changed camera distance by %.3f m beyond its rate limit" % [1.0 / step, frame_index, absf(distance - previous_distance)])
			break
		if absf(fov - previous_fov) > FOV_RATE_LIMIT * step + 0.02:
			failures.append("Airborne %.0f Hz frame %d changed FOV by %.3f degrees beyond its rate limit" % [1.0 / step, frame_index, absf(fov - previous_fov)])
			break
		previous_distance = distance
		previous_fov = fov

	if landing_frames > 0 and float(landing_visible_frames) / float(landing_frames) < 0.95:
		failures.append("Predicted landing was inside its descent visibility window for only %d/%d frames" % [landing_visible_frames, landing_frames])
	if not recovery_seen:
		failures.append("Airborne composition never exposed edge-recovery telemetry")

	_remove_target_and_camera(skier, camera_rig)

func _validate_camera_exports(camera_rig: SkiCameraController, step: float) -> bool:
	var valid := true
	if camera_rig.composition_hard_rect != HARD_SAFE_RECT:
		failures.append("Camera %.0f Hz composition_hard_rect %s != expected %s" % [1.0 / step, camera_rig.composition_hard_rect, HARD_SAFE_RECT])
		valid = false
	if camera_rig.composition_inner_rect != INNER_SAFE_RECT:
		failures.append("Camera %.0f Hz composition_inner_rect %s != expected %s" % [1.0 / step, camera_rig.composition_inner_rect, INNER_SAFE_RECT])
		valid = false
	if camera_rig.composition_landing_rect != LANDING_RECT:
		failures.append("Camera %.0f Hz composition_landing_rect %s != expected %s" % [1.0 / step, camera_rig.composition_landing_rect, LANDING_RECT])
		valid = false
	if absf(camera_rig.maximum_fov_change_rate - FOV_RATE_LIMIT) > 0.001:
		failures.append("Camera %.0f Hz maximum_fov_change_rate %.2f != expected %.2f" % [1.0 / step, camera_rig.maximum_fov_change_rate, FOV_RATE_LIMIT])
		valid = false
	return valid

func _run_carve_lookahead_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.velocity = Vector3(0.0, 0.0, -12.0)
	skier.heading_travel_angle_degrees = 35.0

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	for _index: int in ceili(1.0 / step):
		camera_rig._physics_process(step)
	var snapshot := camera_rig.debug_snapshot()
	var carve_offset := snapshot.get("carve_look_ahead_offset", Vector3.ZERO) as Vector3
	if carve_offset.length() < 0.05:
		failures.append("Lateral carve look-ahead did not open space in the travel direction")
	_remove_target_and_camera(skier, camera_rig)

func _run_foreground_occlusion_reproduction(step: float) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 0.5, 80.0)
	floor_shape.shape = floor_box
	floor.position.y = -0.25
	floor.add_child(floor_shape)
	add_child(floor)

	var feature := StaticBody3D.new()
	feature.collision_layer = 4
	feature.collision_mask = 0
	feature.position = Vector3(0.0, 1.0, 2.25)
	var feature_shape := CollisionShape3D.new()
	var feature_box := BoxShape3D.new()
	feature_box.size = Vector3(3.0, 2.0, 0.9)
	feature_shape.shape = feature_box
	feature.add_child(feature_shape)
	add_child(feature)

	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 1.0, 0.0)
	skier.velocity = Vector3(0.0, 0.0, -8.0)
	skier.predicted_landing_valid = true
	skier.predicted_landing_point = Vector3(0.0, 0.35, -8.0)
	skier.predicted_landing_time = 0.55

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	for _index: int in ceili(0.75 / step):
		camera_rig._physics_process(step)
		var frame_snapshot := camera_rig.debug_snapshot()
		if not bool(frame_snapshot.get("composition_valid", false)) or not camera_rig._camera_destination_is_clear(camera_rig.global_position):
			failures.append("Foreground feature produced an invalid or colliding camera pose at %s" % camera_rig.global_position)
			break
	var snapshot := camera_rig.debug_snapshot()
	if not bool(snapshot.get("composition_valid", false)):
		failures.append("Foreground feature left the camera in an invalid composition at %s, fallback %s" % [camera_rig.global_position, snapshot.get("camera_fallback_count", -1)])
	if float(snapshot.get("foreground_occlusion_fraction", 1.0)) > camera_rig.maximum_body_occlusion_fraction:
		failures.append("Foreground feature left %.2f of skier samples occluded" % float(snapshot.foreground_occlusion_fraction))
	if not snapshot.has("camera_fallback_count") or not snapshot.has("composition_recovery_active"):
		failures.append("Foreground composition fallback telemetry was incomplete")

	_remove_target_and_camera(skier, camera_rig)
	remove_child(feature)
	feature.free()
	remove_child(floor)
	floor.free()

func _run_respawn_initialization_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 18.0, -40.0)
	skier.velocity = Vector3(0.0, 8.0, -12.0)

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	skier.respawn_applied.connect(func(_value: Transform3D) -> void: camera_rig.reset_immediate())
	for _index: int in ceili(0.75 / step):
		camera_rig._physics_process(step)

	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 98.0, 138.0))
	skier.respawn_at(spawn)

	var reset_position := camera_rig.global_position
	var reset_distance := reset_position.distance_to(skier.global_position)
	camera_rig._physics_process(step)
	var first_frame_delta := camera_rig.global_position.distance_to(reset_position)
	if reset_distance < camera_rig.minimum_camera_distance - 0.01 or reset_distance > camera_rig.maximum_camera_distance + 0.01:
		failures.append("Respawn reset produced an invalid camera distance %.3f m" % reset_distance)
	if first_frame_delta > 0.35:
		failures.append("Respawn first-frame camera correction was %.3f m instead of a seeded pose" % first_frame_delta)
	var bounds := _projected_landmark_bounds(camera_rig, skier)
	if not _rect_contains_rect(HARD_SAFE_RECT, bounds):
		failures.append("Respawn first frame placed skier bounds %s outside hard safe rect" % bounds)

	_remove_target_and_camera(skier, camera_rig)

func _projected_landmark_bounds(camera_rig: SkiCameraController, skier: SkierController) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for offset: Vector3 in LANDMARK_OFFSETS:
		var world_position := skier.global_position + skier.global_basis * offset
		var camera_space := camera_rig.global_transform.affine_inverse() * world_position
		if -camera_space.z <= 0.01:
			return Rect2(-10.0, -10.0, 20.0, 20.0)
		var screen := _project_normalized(camera_rig, world_position)
		if not initialized:
			bounds = Rect2(screen, Vector2.ZERO)
			initialized = true
		else:
			bounds = bounds.expand(screen)
	return bounds

func _project_normalized(camera_rig: SkiCameraController, world_position: Vector3) -> Vector2:
	var camera_space := camera_rig.global_transform.affine_inverse() * world_position
	var depth := maxf(0.01, -camera_space.z)
	var viewport_size := camera_rig._composition_viewport_size()
	var aspect := viewport_size.x / viewport_size.y
	var focal_scale := 1.0 / tan(deg_to_rad(camera_rig.camera.fov) * 0.5)
	return Vector2(
		0.5 + camera_space.x * focal_scale / (aspect * depth) * 0.5,
		0.5 - camera_space.y * focal_scale / depth * 0.5
	)

func _rect_contains_rect(container: Rect2, value: Rect2) -> bool:
	var container_end := container.position + container.size
	var value_end := value.position + value.size
	return value.position.x >= container.position.x \
		and value.position.y >= container.position.y \
		and value_end.x <= container_end.x \
		and value_end.y <= container_end.y

func _remove_target_and_camera(skier: SkierController, camera_rig: SkiCameraController) -> void:
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
