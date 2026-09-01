extends Node3D

## Phase-specific camera profile on the production resort scene. The test keeps
## the camera's safety contract red-capable while reporting state-local CPU and
## physics-query costs without imposing a machine-specific time budget.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const STEP := 1.0 / 120.0
const WARMUP_AIR_FRAMES := 48
const PROFILE_FRAMES := 30
const STATE_NAMES := ["GROUND", "AIR", "LANDING", "RAIL", "CRASH"]

@onready var resort: Node3D = $Resort

var skier: SkierController
var camera_rig: SkiCameraController
var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	skier = resort.get_node_or_null("Skier") as SkierController
	camera_rig = resort.get_node_or_null("CameraRig") as SkiCameraController
	if skier == null or camera_rig == null:
		push_error("CAMERA_PHASE_PERF_FAIL: production resort did not create its skier and camera rig")
		AudioManager.shutdown_audio()
		get_tree().quit(1)
		return

	skier.process_mode = Node.PROCESS_MODE_DISABLED
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	_run_ground_phase()
	_run_air_phase()
	_run_landing_phase()
	_run_simple_phase("RAIL", SkierController.State.GRIND)
	_run_simple_phase("CRASH", SkierController.State.BAIL)

	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_PHASE_PERF_PASS: production resort camera stayed finite and bounded across ground, air, landing, rail, and crash phases")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_PHASE_PERF_FAIL: " + failure)
	get_tree().quit(1)

func _run_ground_phase() -> void:
	_prepare_state(SkierController.State.GROUND)
	camera_rig.reset_immediate()
	_run_profile_phase("GROUND", 12)

func _run_air_phase() -> void:
	_prepare_state(SkierController.State.AIR)
	camera_rig.reset_immediate()
	for frame_index: int in WARMUP_AIR_FRAMES:
		_drive_phase("AIR", frame_index)
		camera_rig._physics_process(STEP)
	_run_profile_phase("AIR", PROFILE_FRAMES)

func _run_landing_phase() -> void:
	_prepare_state(SkierController.State.GROUND)
	_run_profile_phase("LANDING", PROFILE_FRAMES)

func _run_simple_phase(phase_name: String, state_value: int) -> void:
	_prepare_state(state_value)
	camera_rig.reset_immediate()
	_run_profile_phase(phase_name, PROFILE_FRAMES)

func _run_profile_phase(phase_name: String, sample_frames: int) -> void:
	camera_rig.begin_performance_profile()
	for frame_index: int in sample_frames:
		_drive_phase(phase_name, frame_index)
		camera_rig._physics_process(STEP)
		_validate_camera_pose(phase_name, frame_index)
	var profile := camera_rig.end_performance_profile()
	var state_index := STATE_NAMES.find(phase_name)
	var state_frames := int((profile.get("state_frames", []) as Array)[state_index]) if state_index >= 0 else 0
	if state_frames != sample_frames:
		failures.append("%s profile sampled %d frames in camera state instead of %d" % [phase_name, state_frames, sample_frames])
	print(
		"CAMERA_PHASE_PERF phase=%s frames=%d state_frames=%d average_us=%.2f max_us=%d shape_queries=%d ray_queries=%d composition_evaluations=%d landmark_samples=%d fallbacks=%d" % [
			phase_name,
			sample_frames,
			state_frames,
			float(profile.get("average_usec", 0.0)),
			int(profile.get("max_usec", 0)),
			int(profile.get("shape_queries", 0)),
			int(profile.get("ray_queries", 0)),
			int(profile.get("composition_evaluations", 0)),
			int(profile.get("landmark_samples", 0)),
			int(camera_rig.debug_snapshot().get("camera_fallback_count", 0)),
		]
	)

func _prepare_state(state_value: int) -> void:
	var normal := ParkLayout.snow_normal()
	skier.state = state_value
	skier.global_position = ParkLayout.spawn_position()
	skier.rotation = Vector3.ZERO
	skier.velocity = ParkLayout.downhill() * 13.0
	skier.angular_velocity = Vector3.ZERO
	skier.contact.grounded = state_value in [SkierController.State.GROUND, SkierController.State.GRIND]
	skier.contact.average_normal = normal
	skier.predicted_landing_valid = state_value == SkierController.State.AIR
	skier.predicted_landing_point = ParkLayout.spawn_position() + ParkLayout.downhill() * 12.0
	skier.predicted_landing_time = 0.45 if state_value == SkierController.State.AIR else -1.0

func _drive_phase(phase_name: String, frame_index: int) -> void:
	var normal := ParkLayout.snow_normal()
	var travel := ParkLayout.downhill()
	var distance := float(frame_index) * 0.08
	var position := ParkLayout.spawn_position() + travel * distance
	var state_value := SkierController.State.GROUND
	match phase_name:
		"AIR":
			state_value = SkierController.State.AIR
			position += normal * (1.8 + 0.45 * sin(float(frame_index) * 0.18))
			skier.velocity = travel * 14.0 - normal * 2.0
			skier.predicted_landing_valid = true
			skier.predicted_landing_point = ParkLayout.spawn_position() + travel * (10.0 + distance)
			skier.predicted_landing_time = 0.35
		"LANDING":
			state_value = SkierController.State.GROUND
			skier.velocity = travel * 12.0
			skier.predicted_landing_valid = false
		"RAIL":
			state_value = SkierController.State.GRIND
			skier.velocity = travel * 12.0
		"CRASH":
			state_value = SkierController.State.BAIL
			position += normal * 0.6
			skier.velocity = travel * 10.0 + normal * 1.5
			_skier_crash_rotation(float(frame_index))

	skier.state = state_value
	skier.global_position = position
	skier.contact.grounded = state_value in [SkierController.State.GROUND, SkierController.State.GRIND]
	skier.contact.average_normal = normal
	skier.basis = ParkLayout.downhill_basis(sin(float(frame_index) * 0.08) * 8.0)

func _skier_crash_rotation(frame_index: float) -> void:
	skier.rotation = Vector3(0.25 * sin(frame_index * 0.12), frame_index * 0.18, 0.2 * cos(frame_index * 0.11))

func _validate_camera_pose(phase_name: String, frame_index: int) -> void:
	var position := camera_rig.global_position
	var distance := position.distance_to(skier.global_position)
	if not position.is_finite() or not camera_rig.camera.global_transform.is_finite() or not is_finite(camera_rig.camera.fov):
		failures.append("%s produced a non-finite camera pose at frame %d" % [phase_name, frame_index])
		return
	if distance < camera_rig.minimum_camera_distance - 0.02 or distance > camera_rig.maximum_camera_distance + 0.02:
		failures.append("%s produced an out-of-bounds camera distance %.3f m at frame %d" % [phase_name, distance, frame_index])
