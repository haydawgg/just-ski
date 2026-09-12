extends Node

## Phase 11 environment camera sweep: replay the canonical line plus
## edge-of-lane variations through the dressed resort and require the chase
## camera to stay composition-valid, unoccluded beyond the body budget, and
## inside its authored distance band. Props can sit outside the ski corridor
## and still land in the chase-camera corridor, so this is the occlusion gate.

const ParkLayout := preload("res://world/park_features/park_layout.gd")

const STATIONS: Array[Dictionary] = [
	{"x": -18.0, "z": 128.0, "speed": 12.0, "steer": 0.5},
	{"x": -8.0, "z": 100.0, "speed": 14.0, "steer": -0.6},
	{"x": 2.0, "z": 70.0, "speed": 13.0, "steer": 0.55},
	{"x": -20.0, "z": 30.0, "speed": 15.0, "steer": -0.65},
	{"x": 4.0, "z": -18.0, "speed": 16.0, "steer": 0.6},
	{"x": -16.0, "z": -58.0, "speed": 15.0, "steer": -0.55},
	{"x": 6.0, "z": -92.0, "speed": 17.0, "steer": 0.65},
	{"x": 2.0, "z": -150.0, "speed": 16.0, "steer": -0.6},
	{"x": -16.0, "z": -182.0, "speed": 15.0, "steer": 0.5},
	{"x": -10.0, "z": -218.0, "speed": 13.0, "steer": -0.5},
]
const WARMUP_FRAMES := 30
const RUN_FRAMES := 90
const CHANGE_FRAME := 45
const MAX_BODY_OCCLUSION := 0.25
const MAX_OCCLUSION_STREAK := 9
const MIN_CAMERA_DISTANCE := 3.33
const MAX_CAMERA_DISTANCE := 7.42
const MAX_FALLBACKS_PER_STATION := 3

@onready var resort: Node = $Resort

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().physics_frame
	var skier := resort.get_node("Skier") as SkierController
	var camera := resort.get_node("CameraRig") as SkiCameraController
	if skier == null or camera == null:
		failures.append("Resort did not expose the skier and camera rig")
		_finish()
		return
	for station_index: int in range(STATIONS.size()):
		await _run_station(station_index, STATIONS[station_index], skier, camera)
	_finish()

func _run_station(station_index: int, station: Dictionary, skier: SkierController, camera: SkiCameraController) -> void:
	_place(skier, camera, float(station.x), float(station.z), float(station.speed))
	var steer: float = float(station.steer)
	Input.action_press("steer_right" if steer > 0.0 else "steer_left", absf(steer))
	var invalid_frames := 0
	var invalid_streak := 0
	var maximum_invalid_streak := 0
	var recovery_invalid_frames := 0
	var maximum_occlusion := 0.0
	var occlusion_streak := 0
	var maximum_occlusion_streak := 0
	var occluded_frames := 0
	var fallback_start := -1
	var fallback_end := 0
	var minimum_distance := INF
	var maximum_distance := 0.0
	for frame: int in range(RUN_FRAMES):
		if frame == CHANGE_FRAME:
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			Input.action_press("steer_left" if steer > 0.0 else "steer_right", absf(steer))
		await get_tree().physics_frame
		if frame < WARMUP_FRAMES:
			continue
		var snapshot := camera.debug_snapshot()
		var occlusion := float(snapshot.get("foreground_occlusion_fraction", 0.0))
		maximum_occlusion = maxf(maximum_occlusion, occlusion)
		if occlusion > MAX_BODY_OCCLUSION:
			occlusion_streak += 1
			maximum_occlusion_streak = maxi(maximum_occlusion_streak, occlusion_streak)
		else:
			occlusion_streak = 0
		var skier_state := int(skier.state)
		var grounded := skier_state == SkierController.State.GROUND or skier_state == SkierController.State.GRIND
		# Landing-recovery framing is owned by the camera phase suites; this
		# environment sweep asserts hard validity for ordinary grounded travel
		# while measuring occlusion, collisions and distance on every frame.
		var recovery_active := bool(snapshot.get("composition_recovery_active", false))
		if recovery_active and not bool(snapshot.get("composition_valid", true)):
			recovery_invalid_frames += 1
		if grounded and not recovery_active and not bool(snapshot.get("composition_valid", true)):
			invalid_frames += 1
			invalid_streak += 1
			maximum_invalid_streak = maxi(maximum_invalid_streak, invalid_streak)
			if invalid_frames <= 3:
				print("ENV_CAMERA_INVALID station=%d frame=%d skier=%s state=%s camera=%s clearance=%.2f recovery=%s emergency=%s screen=%s size=%s" % [
					station_index, frame, str(skier.global_position), str(skier.state), str(camera.global_position),
					float(snapshot.get("camera_clearance", 0.0)), str(snapshot.get("composition_recovery_active", false)),
					str(snapshot.get("emergency_fallback_used", false)), str(snapshot.get("target_screen_position", Vector2.ZERO)),
					str(snapshot.get("skier_screen_size", 0.0))
				])
		else:
			invalid_streak = 0
		if bool(snapshot.get("camera_occluded", false)):
			occluded_frames += 1
		var fallback_count := int(snapshot.get("camera_fallback_count", 0))
		if fallback_start < 0:
			fallback_start = fallback_count
		fallback_end = fallback_count
		var distance := float(snapshot.get("target_distance", MIN_CAMERA_DISTANCE))
		minimum_distance = minf(minimum_distance, distance)
		maximum_distance = maxf(maximum_distance, distance)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	var fallback_delta := maxi(fallback_end - maxi(fallback_start, 0), 0)
	print("ENV_CAMERA_SAMPLE station=%d pos=(%.0f,%.0f) invalid=%d invalid_streak=%d recovery_invalid=%d occlusion=%.3f occlusion_streak=%d occluded=%d fallbacks=%d distance=(%.2f,%.2f)" % [
		station_index, float(station.x), float(station.z), invalid_frames, maximum_invalid_streak, recovery_invalid_frames, maximum_occlusion, maximum_occlusion_streak, occluded_frames, fallback_delta, minimum_distance, maximum_distance
	])
	if invalid_frames > 0:
		failures.append("Station %d (%s) produced %d hard-composition-invalid frames (streak %d)" % [station_index, station, invalid_frames, maximum_invalid_streak])
	if maximum_occlusion > MAX_BODY_OCCLUSION:
		failures.append("Station %d (%s) body occlusion reached %.3f (limit %.2f)" % [station_index, station, maximum_occlusion, MAX_BODY_OCCLUSION])
	if maximum_occlusion_streak > MAX_OCCLUSION_STREAK:
		failures.append("Station %d (%s) held occlusion over the budget for %d frames" % [station_index, station, maximum_occlusion_streak])
	if occluded_frames > MAX_OCCLUSION_STREAK:
		failures.append("Station %d (%s) placed the camera volume inside geometry for %d frames" % [station_index, station, occluded_frames])
	if minimum_distance < MIN_CAMERA_DISTANCE or maximum_distance > MAX_CAMERA_DISTANCE:
		failures.append("Station %d (%s) camera distance escaped [%.2f, %.2f] with (%.2f, %.2f)" % [station_index, station, MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE, minimum_distance, maximum_distance])
	if fallback_delta > MAX_FALLBACKS_PER_STATION:
		failures.append("Station %d (%s) needed %d camera fallbacks" % [station_index, station, fallback_delta])

func _place(skier: SkierController, camera: SkiCameraController, x: float, z: float, speed: float) -> void:
	skier.global_position = ParkLayout.surface_hover(x, z, ParkLayout.SPAWN_HOVER)
	skier.global_basis = ParkLayout.downhill_basis()
	skier.velocity = ParkLayout.downhill() * speed
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = ParkLayout.snow_normal()
	skier.contact.average_hit_position = ParkLayout.snow_at(x, z)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	camera.reset_immediate()

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ENVIRONMENT_CAMERA_SWEEP_PASS: dressed resort kept zero hard-frame violations and bounded occlusion on the canonical/edge-of-lane sweep")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ENVIRONMENT_CAMERA_SWEEP_FAIL: " + failure)
	get_tree().quit(1)
