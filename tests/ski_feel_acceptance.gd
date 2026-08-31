extends Node

const STEP := 1.0 / 120.0

var failures: Array[String] = []

func _ready() -> void:
	_test_air_trim_authority()
	_test_landing_control_recovery()
	_test_camera_speed_and_bank()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SKI_FEEL_PASS: precision air trim, landing recovery, speed FOV, and restrained camera bank passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SKI_FEEL_FAIL: " + failure)
	get_tree().quit(1)

func _test_air_trim_authority() -> void:
	var ski_profile := preload("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	var flick_profile := preload("res://resources/physics/default_flick_trick_profile.tres") as FlickTrickProfile
	var yaw_ratio := flick_profile.air_yaw_trim_acceleration / maxf(flick_profile.spin_impulse, 0.01)
	var flip_ratio := ski_profile.air_flip_trim_acceleration / maxf(flick_profile.flip_impulse, 0.01)
	# Trim should correct an existing maneuver, not act as a second full trick
	# input. Keep it to a small fraction of the takeoff rotation authority.
	if yaw_ratio < 0.05 or yaw_ratio > 0.09:
		failures.append("Air yaw trim authority %.3f left the approved 5-9%% precision range" % yaw_ratio)
	if flip_ratio < 0.05 or flip_ratio > 0.09:
		failures.append("Air flip trim authority %.3f left the approved 5-9%% precision range" % flip_ratio)

func _test_landing_control_recovery() -> void:
	var skier := _new_skier()
	skier._begin_landing_control_recovery(1.0)
	var initial := skier.landing_control_multiplier
	if initial < 0.62 or initial > 0.75:
		failures.append("Hard landing steering penalty %.2f was either punitive or imperceptible" % initial)
	var elapsed := 0.0
	while skier.landing_control_multiplier < 1.0 and elapsed < 1.0:
		skier._update_landing_control_recovery(STEP)
		elapsed += STEP
	if elapsed < 0.35 or elapsed > 0.55:
		failures.append("Hard landing steering recovery %.3f s left the approved 0.35-0.55 s band" % elapsed)
	if not is_equal_approx(skier.landing_control_multiplier, 1.0):
		failures.append("Landing steering authority did not return fully")
	_dispose(skier)

func _test_camera_speed_and_bank() -> void:
	var skier := _new_skier()
	var camera_controller := SkiCameraController.new()
	add_child(camera_controller)
	camera_controller.set_physics_process(false)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.velocity = Vector3.ZERO
	camera_controller.set_target(skier)
	var low_fov := float(camera_controller.debug_snapshot().fov)

	skier.velocity = Vector3(0.0, 0.0, -camera_controller.fov_speed_reference)
	skier.edge_amount = 1.0
	_step_camera(camera_controller, 240)
	var loaded := camera_controller.debug_snapshot()
	var fov_gain := float(loaded.fov) - low_fov
	var left_bank := float(loaded.bank_degrees)
	if fov_gain < 5.0 or fov_gain > 8.0:
		failures.append("Full-range speed FOV gain %.2f degrees left the approved 5-8 degree band" % fov_gain)
	if absf(left_bank) < 2.0 or absf(left_bank) > 5.1:
		failures.append("Loaded-turn camera bank %.2f degrees was absent or excessive" % left_bank)

	skier.edge_amount = -1.0
	_step_camera(camera_controller, 240)
	var right_bank := float(camera_controller.debug_snapshot().bank_degrees)
	if left_bank * right_bank >= 0.0:
		failures.append("Left/right camera bank did not mirror")

	skier.state = SkierController.State.AIR
	_step_camera(camera_controller, 240)
	var air := camera_controller.debug_snapshot()
	if absf(float(air.bank_degrees)) > 0.15:
		failures.append("Ground turn bank did not settle in the air")
	if str(air.state) != "AIR":
		failures.append("Camera did not enter its trajectory-only air profile")
	_dispose(camera_controller)
	_dispose(skier)

func _new_skier() -> SkierController:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	return skier

func _step_camera(camera_controller: SkiCameraController, frames: int) -> void:
	for _index: int in frames:
		camera_controller._physics_process(STEP)

func _dispose(node: Node) -> void:
	remove_child(node)
	node.queue_free()
