extends Node

## Phase 13 cross-state preservation: bail/recovery, low-speed stop and restart,
## and respawn relocation must not strand locomotion, camera, or presentation
## state. Rail/one-sided contact preservation stays owned by the existing
## solver/equipment fixtures and is mapped in the release report.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const CLEARANCE_PHASE_FRAMES := 30
const BAIL_RECOVERY_FRAMES := 600
const RESPAWN_SETTLE_FRAMES := 90
const MAX_FALLBACK_DELTA := 4
const MIN_CAMERA_DISTANCE := 3.28
const MAX_CAMERA_DISTANCE := 7.47

@onready var resort: Node = $Resort

var skier: SkierController
var camera: SkiCameraController
var failures: Array[String] = []
var maximum_fallbacks := 0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	camera = resort.get_node("CameraRig") as SkiCameraController
	if skier == null or camera == null:
		failures.append("Cross-state acceptance could not bind the skier and camera")
		_finish()
		return
	var course_recovery := resort.get_node_or_null("CourseRecovery")
	if course_recovery != null:
		# This fixture drives explicit relocation states; course recovery would
		# relocate the skier out from under the low-speed/stop measurement.
		course_recovery.process_mode = Node.PROCESS_MODE_DISABLED
	await _test_low_speed_stop_restart()
	await _test_bail_recovery()
	await _test_respawn_relocation()
	_finish()

func _test_low_speed_stop_restart() -> void:
	# Braked slow-down to walking pace on the piste, camera/stance recovery,
	# then release and restart. (A literal stationary hold is not physical on
	# the 18-degree face; the finish pad is exercised by the runout instead.)
	_place_grounded(-6.0, -180.0, 4.0)
	Input.action_press("brake", 1.0)
	var grounded_samples := 0
	for _frame: int in range(150):
		await get_tree().physics_frame
		if skier.state == SkierController.State.GROUND or skier.state == SkierController.State.GRIND:
			grounded_samples += 1
	var slow_speed := skier.velocity.length()
	Input.action_release("brake")
	if slow_speed > 2.5:
		failures.append("Braking did not reach walking pace (%.2f m/s)" % slow_speed)
	if grounded_samples < 90:
		failures.append("Low-speed travel left the ground on %d frames" % (150 - grounded_samples))
	if skier.state == SkierController.State.BAIL:
		failures.append("Low-speed travel entered bail")
	if not _camera_clear("low-speed"):
		failures.append("Low-speed stop left the camera outside its valid band")
	print("RELEASE_CROSS_STATE_SAMPLE phase=low_speed slow_speed=%.2f grounded=%d" % [slow_speed, grounded_samples])
	skier.velocity = ParkLayout.downhill() * 7.0
	var restart_speed := 0.0
	for _frame: int in range(60):
		await get_tree().physics_frame
		restart_speed = skier.velocity.length()
	if restart_speed < 3.0:
		failures.append("Skier did not restart from low speed (%.2f m/s)" % restart_speed)
	print("RELEASE_CROSS_STATE_SAMPLE phase=restart speed=%.2f" % restart_speed)

func _test_bail_recovery() -> void:
	_place_grounded(-8.0, -170.0, 9.0)
	await get_tree().physics_frame
	skier._bail()
	var recovered := false
	var frames := 0
	for _frame: int in range(BAIL_RECOVERY_FRAMES):
		await get_tree().physics_frame
		frames += 1
		if skier.state != SkierController.State.BAIL:
			recovered = true
			break
	if not recovered:
		failures.append("Bail did not recover within %.1f s" % (float(BAIL_RECOVERY_FRAMES) / 60.0))
	else:
		skier.velocity = ParkLayout.downhill() * 7.0
		for _frame: int in range(90):
			await get_tree().physics_frame
		if skier.velocity.length() < 2.0 or skier.state == SkierController.State.BAIL:
			failures.append("Skier did not resume normal skiing after bail recovery")
		if not _camera_clear("bail-recovery"):
			failures.append("Camera did not reacquire after bail recovery")
	print("RELEASE_CROSS_STATE_SAMPLE phase=bail recovered=%s frames=%d speed=%.2f" % [str(recovered), frames, skier.velocity.length()])

func _test_respawn_relocation() -> void:
	var marker := Transform3D(ParkLayout.downhill_basis(), ParkLayout.surface_hover(-6.0, -60.0, ParkLayout.SPAWN_HOVER))
	SessionManager.set_marker(marker)
	skier.respawn_at(marker)
	await get_tree().physics_frame
	var relocation_error := skier.global_position.distance_to(marker.origin)
	for _frame: int in range(RESPAWN_SETTLE_FRAMES):
		await get_tree().physics_frame
	if relocation_error > 0.5:
		failures.append("Respawn relocation error was %.2f m" % relocation_error)
	if skier.state == SkierController.State.BAIL:
		failures.append("Respawn left the skier in bail")
	if not _camera_clear("respawn"):
		failures.append("Camera did not reacquire after respawn relocation")
	SessionManager.clear_marker()
	print("RELEASE_CROSS_STATE_SAMPLE phase=respawn error=%.3f state=%d distance=%.2f" % [relocation_error, skier.state, float(camera.debug_snapshot().get("target_distance", 0.0))])

func _camera_clear(label: String) -> bool:
	var snapshot := camera.debug_snapshot()
	maximum_fallbacks = maxi(maximum_fallbacks, int(snapshot.get("camera_fallback_count", 0)))
	var distance := float(snapshot.get("target_distance", 0.0))
	if distance < MIN_CAMERA_DISTANCE or distance > MAX_CAMERA_DISTANCE:
		print("RELEASE_CROSS_STATE_DETAIL phase=%s distance=%.2f" % [label, distance])
		return false
	return bool(snapshot.get("composition_valid", true)) or bool(snapshot.get("composition_recovery_active", false))

func _place_grounded(x: float, z: float, speed: float) -> void:
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
	if maximum_fallbacks > MAX_FALLBACK_DELTA:
		failures.append("Cross-state run needed %d camera fallbacks" % maximum_fallbacks)
	if failures.is_empty():
		print("RELEASE_CROSS_STATE_PASS: bail/recovery, low-speed restart, and respawn relocation preserved locomotion and camera state")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RELEASE_CROSS_STATE_FAIL: " + failure)
	get_tree().quit(1)
