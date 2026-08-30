extends Node

const STEP := 1.0 / 60.0

var failures: Array[String] = []

func _ready() -> void:
	_test_ground_stance_and_carve_loading()
	_test_gameplay_distance_pole_direction()
	_test_straight_air_has_deterministic_asymmetry()
	_test_spin_changes_body_shape_through_rotation()
	_test_landing_alignment_precedes_visible_readiness()
	_test_landing_readiness_projection_and_recovery()
	_test_landing_readiness_gameplay_frame_semantics()
	_test_landing_readiness_invalid_prediction()
	_test_grabs_separate_from_straight_air_at_gameplay_distance()
	_test_ground_vocabulary_through_gameplay_camera()
	_test_rotation_rail_and_stomp_vocabulary_through_gameplay_camera()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ANIMATION_SILHOUETTE_PASS: ground loading, pole direction, deterministic air/spin shapes, delayed landing readiness, and gameplay-distance grab separation passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ANIMATION_SILHOUETTE_FAIL: " + failure)
	get_tree().quit(1)

func _test_ground_stance_and_carve_loading() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _ground_frame()
	_step(rig, frame, 90)
	var neutral := rig.debug_snapshot()
	if float((neutral.left_knee_rotation as Vector3).x) < 0.58 or float((neutral.right_knee_rotation as Vector3).x) < 0.58:
		failures.append("Ground neutral returned to a straight-legged mannequin stance")
	if float((neutral.pelvis_position as Vector3).y) > 0.83:
		failures.append("Ground neutral pelvis remained too high for an athletic ski stance")
	if absf(float((neutral.spine_rotation as Vector3).x)) < 0.19:
		failures.append("Ground neutral torso remained too upright")

	frame.edge = 1.0
	frame.turn_input = 1.0
	frame.turn_rate = 0.9
	frame.lateral_acceleration = 11.0
	frame.carve_ratio = 1.0
	frame.skid_ratio = 0.0
	_step(rig, frame, 120)
	var loaded := rig.debug_snapshot()
	var leg_difference := absf(float((loaded.left_knee_rotation as Vector3).x) - float((loaded.right_knee_rotation as Vector3).x))
	if leg_difference < 0.48:
		failures.append("Loaded carve did not create a gameplay-readable inside/outside leg difference (%.3f rad)" % leg_difference)
	if absf(float((loaded.pelvis_position as Vector3).x)) < 0.24:
		failures.append("Loaded carve pelvis did not move inside the turn strongly enough")
	if absf(float((loaded.balance_root_rotation as Vector3).z)) > 0.05:
		failures.append("Loaded carve still relied too heavily on whole-body root lean")
	if float((loaded.pelvis_rotation as Vector3).z) * float((loaded.chest_rotation as Vector3).z) >= 0.0 or absf(float((loaded.chest_rotation as Vector3).z)) < 0.1:
		failures.append("Loaded carve torso did not visibly counterbalance the lower body (pelvis %.3f, chest %.3f)" % [float((loaded.pelvis_rotation as Vector3).z), float((loaded.chest_rotation as Vector3).z)])

	remove_child(rig)
	rig.free()

func _test_gameplay_distance_pole_direction() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var camera := Camera3D.new()
	camera.fov = 72.0
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 2.15, 5.2), Vector3(0.0, 0.72, 0.0), Vector3.UP)
	var frame := _ground_frame()
	frame.edge = -1.0
	frame.turn_input = -1.0
	frame.turn_rate = -0.9
	frame.lateral_acceleration = -11.0
	_step(rig, frame, 120)
	var landmarks := rig.debug_snapshot().get("canonical_landmarks", {}) as Dictionary
	if not landmarks.has("left_hand") or not landmarks.has("left_pole_tip"):
		failures.append("Animation telemetry did not expose silhouette landmarks")
	else:
		var left_direction := camera.unproject_position(landmarks.left_pole_tip as Vector3) - camera.unproject_position(landmarks.left_hand as Vector3)
		var right_direction := camera.unproject_position(landmarks.right_pole_tip as Vector3) - camera.unproject_position(landmarks.right_hand as Vector3)
		var left_vertical_deviation := absf(rad_to_deg(Vector2.DOWN.angle_to(left_direction.normalized())))
		var right_vertical_deviation := absf(rad_to_deg(Vector2.DOWN.angle_to(right_direction.normalized())))
		var separation := absf(rad_to_deg(left_direction.normalized().angle_to(right_direction.normalized())))
		if left_vertical_deviation < 25.0 or right_vertical_deviation < 25.0:
			failures.append("Ground poles remained too vertical at gameplay distance (left %.1f°, right %.1f°)" % [left_vertical_deviation, right_vertical_deviation])
		if separation < 12.0:
			failures.append("Ground poles remained visually parallel during a carve (%.1f° separation)" % separation)
	remove_child(camera)
	camera.free()
	remove_child(rig)
	rig.free()

func _test_straight_air_has_deterministic_asymmetry() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var ground := _ground_frame()
	ground.edge = -0.8
	ground.turn_input = -0.7
	ground.turn_rate = -0.65
	ground.lateral_acceleration = -8.0
	_step(rig, ground, 60)
	var air := _air_frame()
	_step(rig, air, 90)
	var snapshot := rig.debug_snapshot()
	var knee_difference := absf(float((snapshot.left_knee_rotation as Vector3).x) - float((snapshot.right_knee_rotation as Vector3).x))
	if knee_difference < 0.18:
		failures.append("Straight air converged on symmetric legs (%.3f rad difference)" % knee_difference)
	if absf(float(snapshot.get("air_style_side", 0.0))) < 0.9:
		failures.append("Takeoff did not cache a deterministic air-style side")
	if absf(float((snapshot.pelvis_position as Vector3).x)) < 0.035:
		failures.append("Straight-air pelvis remained centered and mannequin-like")
	remove_child(rig)
	rig.free()

func _test_spin_changes_body_shape_through_rotation() -> void:
	var signatures: Array[PackedFloat32Array] = []
	for degrees: float in [0.0, 90.0, 180.0, 270.0]:
		signatures.append(_sample_spin_signature(degrees))
	for index: int in 3:
		var difference := _signature_difference(signatures[index], signatures[index + 1])
		if difference < 0.22:
			failures.append("Spin body shape barely changed from %.0f° to %.0f° (signature delta %.3f)" % [float(index) * 90.0, float(index + 1) * 90.0, difference])
	var left_180 := _sample_spin_signature(180.0, -1.0)
	var right_180 := _sample_spin_signature(180.0, 1.0)
	if left_180[3] * right_180[3] >= 0.0:
		failures.append("Left/right 180 spin torso shapes were not mirrored (left %.3f, right %.3f)" % [left_180[3], right_180[3]])

func _test_landing_alignment_precedes_visible_readiness() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _air_frame()
	frame.predicted_landing_valid = true
	frame.predicted_landing_time = 0.24
	frame.predicted_landing_normal = Vector3(0.0, 0.98, 0.2).normalized()
	_step(rig, frame, 60)
	var alignment := float(rig.debug_snapshot().get("landing_alignment", 0.0))
	var readiness := float(rig.debug_snapshot().get("landing_readiness", 1.0))
	if alignment < 0.1:
		failures.append("Landing alignment did not begin inside the 0.32 s spotting window")
	if readiness < 0.7:
		failures.append("Landing readiness did not remain independent of anticipation for a well-aligned skier (%.3f at 0.24 s)" % readiness)

	frame.predicted_landing_time = 0.09
	_step(rig, frame, 30)
	var late := rig.debug_snapshot()
	var late_anticipation := float(late.get("landing_anticipation", 0.0))
	readiness = float(late.get("landing_readiness", 0.0))
	if late_anticipation < 0.38 or readiness < 0.7:
		failures.append("Landing preparation did not establish both timing and readiness near contact (anticipation %.3f readiness %.3f)" % [late_anticipation, readiness])
	remove_child(rig)
	rig.free()

func _test_landing_readiness_projection_and_recovery() -> void:
	var overshoot_rig := SkierAnimationController.new()
	add_child(overshoot_rig)
	var overshoot := _air_frame()
	overshoot.predicted_landing_valid = true
	overshoot.predicted_landing_time = 0.08
	overshoot.angular_velocity = Vector3(0.0, 8.0, 0.0)
	overshoot.angular_velocity_world = overshoot.angular_velocity
	overshoot.body_up = Vector3.UP
	_step(overshoot_rig, overshoot, 90)
	var overshoot_snapshot := overshoot_rig.debug_snapshot()
	var overshoot_readiness := float(overshoot_snapshot.get("landing_readiness", 0.0))
	if overshoot_readiness > 0.55:
		failures.append("Aligned high-speed overshoot was treated as ready (%.3f)" % overshoot_readiness)
	remove_child(overshoot_rig)
	overshoot_rig.free()

	var recovery_rig := SkierAnimationController.new()
	add_child(recovery_rig)
	var recovery := _air_frame()
	recovery.predicted_landing_valid = true
	recovery.predicted_landing_time = 0.5
	recovery.skier_heading = Vector3(0.7071, 0.0, -0.7071).normalized()
	recovery.velocity_heading = Vector3.FORWARD
	recovery.angular_velocity = Vector3(0.0, -0.9, 0.0)
	recovery.angular_velocity_world = recovery.angular_velocity
	recovery.body_up = Vector3.UP
	_step(recovery_rig, recovery, 90)
	var recovery_snapshot := recovery_rig.debug_snapshot()
	var recovery_readiness := float(recovery_snapshot.get("landing_readiness", 0.0))
	if recovery_readiness < overshoot_readiness + 0.15:
		failures.append("A misaligned skier rotating toward the target did not outrank an overshooting skier (%.3f vs %.3f)" % [recovery_readiness, overshoot_readiness])
	if absf(float(recovery_snapshot.get("landing_projected_heading_error", 0.0))) > deg_to_rad(30.0):
		failures.append("Recovering heading remained too far from the target at contact")
	remove_child(recovery_rig)
	recovery_rig.free()

func _test_landing_readiness_invalid_prediction() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _air_frame()
	frame.predicted_landing_valid = false
	frame.predicted_landing_time = 0.08
	frame.body_up = Vector3.ZERO
	_step(rig, frame, 60)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.get("landing_readiness", 1.0)) > 0.02:
		failures.append("Invalid landing prediction produced non-zero readiness")
	if bool(snapshot.get("landing_ready", true)):
		failures.append("Invalid landing prediction exposed LANDING READY")
	for key: String in ["landing_readiness_heading", "landing_readiness_pitch", "landing_readiness_spin", "landing_readiness_upright", "landing_readiness_residual"]:
		var value := float(snapshot.get(key, -1.0))
		if value < -0.001 or value > 1.001 or not is_finite(value):
			failures.append("Landing readiness component %s left the finite 0..1 range (%.3f)" % [key, value])
	remove_child(rig)
	rig.free()

func _test_landing_readiness_gameplay_frame_semantics() -> void:
	var threshold_rig := SkierAnimationController.new()
	add_child(threshold_rig)
	if not threshold_rig._landing_ready_for_values(true, 0.65, 0.75):
		failures.append("Landing-ready threshold equality did not use inclusive >= semantics")
	if threshold_rig._landing_ready_for_values(false, 0.65, 0.75):
		failures.append("Invalid readiness inputs incorrectly satisfied landing-ready thresholds")
	remove_child(threshold_rig)
	threshold_rig.free()

	var steep_normal := Vector3(0.0, 0.8, 0.6).normalized()
	var tangent_forward := Vector3(0.0, steep_normal.z, -steep_normal.y).normalized()
	var flat_ski_rig := SkierAnimationController.new()
	add_child(flat_ski_rig)
	var flat_ski := _air_frame()
	flat_ski.predicted_landing_valid = true
	flat_ski.predicted_landing_time = 0.08
	flat_ski.predicted_landing_normal = steep_normal
	flat_ski.body_up = steep_normal
	flat_ski.ski_up = steep_normal
	flat_ski.ski_forward = tangent_forward
	flat_ski.velocity_heading = tangent_forward
	_step(flat_ski_rig, flat_ski, 90)
	var flat_snapshot := flat_ski_rig.debug_snapshot()

	var pitched_rig := SkierAnimationController.new()
	add_child(pitched_rig)
	var pitched := flat_ski
	pitched.ski_forward = Vector3.FORWARD
	pitched.velocity_heading = tangent_forward
	_step(pitched_rig, pitched, 90)
	var pitched_snapshot := pitched_rig.debug_snapshot()
	if absf(float(flat_snapshot.get("landing_readiness_upright", 0.0)) - float(pitched_snapshot.get("landing_readiness_upright", 0.0))) > 0.02:
		failures.append("Steep-slope pitch changes incorrectly altered independent upright score")
	if float(pitched_snapshot.get("landing_readiness_pitch", 1.0)) >= float(flat_snapshot.get("landing_readiness_pitch", 0.0)):
		failures.append("Gameplay ski-forward pitch data did not reduce readiness on a steep landing")
	remove_child(flat_ski_rig)
	flat_ski_rig.free()
	remove_child(pitched_rig)
	pitched_rig.free()

	var angular_rig := SkierAnimationController.new()
	add_child(angular_rig)
	var angular_frame := _air_frame()
	angular_frame.predicted_landing_valid = true
	angular_frame.predicted_landing_time = 0.5
	angular_frame.predicted_landing_normal = steep_normal
	angular_frame.body_up = steep_normal
	angular_frame.ski_up = steep_normal
	angular_frame.ski_forward = tangent_forward
	angular_frame.velocity_heading = tangent_forward
	angular_frame.angular_velocity = Vector3(0.0, 2.0, 0.0)
	angular_frame.angular_velocity_world = steep_normal * 2.0
	_step(angular_rig, angular_frame, 90)
	var angular_snapshot := angular_rig.debug_snapshot()
	var projected_heading_error := float(angular_snapshot.get("landing_projected_heading_error", 0.0))
	if absf(projected_heading_error - 1.0) > 0.06:
		failures.append("Heading projection did not use world angular velocity around the landing normal (%.3f)" % projected_heading_error)
	remove_child(angular_rig)
	angular_rig.free()

	var invalid_rig := SkierAnimationController.new()
	add_child(invalid_rig)
	var invalid := _air_frame()
	invalid.predicted_landing_valid = true
	invalid.predicted_landing_time = 0.08
	invalid.body_up_valid = false
	invalid.body_up = Vector3.ZERO
	invalid.ski_forward_valid = false
	invalid.ski_forward = Vector3.ZERO
	invalid.ski_up_valid = false
	invalid.ski_up = Vector3.ZERO
	invalid.velocity_heading = Vector3(INF, 0.0, 0.0)
	_step(invalid_rig, invalid, 90)
	var invalid_snapshot := invalid_rig.debug_snapshot()
	if bool(invalid_snapshot.get("landing_readiness_valid", true)) or bool(invalid_snapshot.get("landing_ready", true)):
		failures.append("Invalid readiness vectors were not handled conservatively")
	if float(invalid_snapshot.get("landing_readiness", 1.0)) > 0.02:
		failures.append("Invalid readiness vectors produced non-zero aggregate readiness")
	remove_child(invalid_rig)
	invalid_rig.free()

func _test_grabs_separate_from_straight_air_at_gameplay_distance() -> void:
	var straight := _sample_projected_pose(TrickController.GrabPose.NONE)
	for pose: int in range(TrickController.GrabPose.SAFETY_LEFT, TrickController.GrabPose.DOUBLE + 1):
		var grabbed := _sample_projected_pose(pose)
		_assert_projected_separation("Grab pose %d" % pose, straight, grabbed)
	for pose: int in range(TrickController.StylePose.SPREAD_EAGLE, TrickController.StylePose.SHIFTY_RIGHT + 1):
		var styled := _sample_projected_style(pose)
		_assert_projected_separation("Style pose %d" % pose, straight, styled)
	var spin := _sample_projected_pose(TrickController.GrabPose.NONE, true)
	for pose: int in range(TrickController.GrabPose.SAFETY_LEFT, TrickController.GrabPose.DOUBLE + 1):
		var spinning_grab := _sample_projected_pose(pose, true)
		_assert_projected_separation("Spinning grab pose %d" % pose, spin, spinning_grab)

func _sample_projected_pose(grab_pose: int, spinning: bool = false) -> Dictionary:
	var frame := _air_frame()
	if spinning:
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.angular_velocity = Vector3(0.0, 5.4, 0.0)
		frame.rotation_accumulated = Vector3(0.0, PI, 0.0)
	if grab_pose != TrickController.GrabPose.NONE:
		frame.grab_pose = grab_pose
		frame.grab_amount = 1.0
		frame.grab_input_strength = 1.0
		frame.grab_hold_time = 0.65
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	return _sample_actual_gameplay_camera(frame)

func _sample_projected_style(style_pose: int) -> Dictionary:
	var frame := _air_frame()
	frame.style_pose = style_pose
	frame.style_amount = 1.0
	return _sample_actual_gameplay_camera(frame)

func _sample_actual_gameplay_camera(frame: SkierAnimationFrame, event: int = -1, event_strength: float = 0.3, step_count: int = 90) -> Dictionary:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_transform = Transform3D.IDENTITY
	skier.state = frame.locomotion_state
	skier.velocity = Vector3(0.0, 0.0, -maxf(frame.speed_mps, 1.0))
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	if event >= 0:
		skier.animation_controller.trigger(event, event_strength, 0.0)
	for _index: int in step_count:
		skier.animation_controller.apply_frame(frame, STEP)
		camera_rig._physics_process(STEP)
	var world := skier.animation_controller.debug_snapshot().canonical_landmarks as Dictionary
	var projected := {}
	for key: String in ["head", "pelvis", "left_knee", "right_knee", "left_boot", "right_boot", "left_hand", "right_hand", "left_ski_nose", "right_ski_nose", "left_ski_tail", "right_ski_tail"]:
		projected[key] = _project_gameplay_landmark(camera_rig.camera, world[key] as Vector3)
	var ski_center_y := ((projected.left_ski_tail as Vector2).y + (projected.right_ski_tail as Vector2).y) * 0.5
	projected["body_height"] = maxf(1.0, absf((projected.head as Vector2).y - ski_center_y))
	projected["camera_state"] = camera_rig.debug_snapshot().state
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
	return projected

func _test_ground_vocabulary_through_gameplay_camera() -> void:
	var neutral := _sample_actual_gameplay_camera(_ground_frame())
	if str(neutral.camera_state) != "GROUND":
		failures.append("Silhouette acceptance did not use the real ground camera profile")
	var carve_frame := _ground_frame()
	carve_frame.edge = 1.0
	carve_frame.turn_input = 1.0
	carve_frame.turn_rate = 0.9
	carve_frame.lateral_acceleration = 11.0
	var carve := _sample_actual_gameplay_camera(carve_frame)
	_assert_projected_separation("Ground carve", neutral, carve)
	var slarve_frame := _ground_frame()
	slarve_frame.edge = 0.45
	slarve_frame.turn_input = 0.5
	slarve_frame.carve_ratio = 0.42
	slarve_frame.skid_ratio = 0.72
	slarve_frame.skid = 1.0
	slarve_frame.heading_velocity_delta = 0.52
	var slarve := _sample_actual_gameplay_camera(slarve_frame)
	_assert_projected_separation("Slarve", carve, slarve)
	var stop_frame := _ground_frame()
	stop_frame.braking = true
	stop_frame.skid = 1.0
	stop_frame.skid_ratio = 1.0
	var stop := _sample_actual_gameplay_camera(stop_frame)
	_assert_projected_separation("Hockey stop", slarve, stop)
	var switch_frame := _ground_frame()
	switch_frame.switch_stance = true
	var switch_pose := _sample_actual_gameplay_camera(switch_frame)
	_assert_projected_separation("Switch skiing", neutral, switch_pose)

func _test_rotation_rail_and_stomp_vocabulary_through_gameplay_camera() -> void:
	var front_frame := _rotation_frame(TrickCommand.Kind.FRONTFLIP, Vector3(4.8, 0.0, 0.0), Vector3(PI, 0.0, 0.0))
	var back_frame := _rotation_frame(TrickCommand.Kind.BACKFLIP, Vector3(-4.8, 0.0, 0.0), Vector3(-PI, 0.0, 0.0))
	var cork_frame := _rotation_frame(TrickCommand.Kind.CORK_RIGHT, Vector3(0.0, 4.4, 4.1), Vector3(0.0, PI, PI * 0.72))
	var front := _sample_actual_gameplay_camera(front_frame)
	var back := _sample_actual_gameplay_camera(back_frame)
	var cork := _sample_actual_gameplay_camera(cork_frame)
	_assert_projected_separation("Frontflip vs backflip", front, back)
	_assert_projected_separation("Backflip vs cork", back, cork)
	var fifty := _sample_actual_gameplay_camera(_grind_frame(0))
	var boardslide := _sample_actual_gameplay_camera(_grind_frame(1))
	_assert_projected_separation("50-50 vs boardslide", fifty, boardslide)
	var ground := _ground_frame()
	ground.landing_event_active = true
	ground.landing_impact_severity = 0.22
	ground.landing_outcome = LandingSolver.Outcome.CLEAN
	ground.landing_air_time = 0.8
	var stomp := _sample_actual_gameplay_camera(ground, SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.22, 12)
	var neutral := _sample_actual_gameplay_camera(_ground_frame())
	_assert_projected_separation("Clean stomp", neutral, stomp)

func _rotation_frame(kind: int, rate: Vector3, accumulated: Vector3) -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = kind
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = rate
	frame.rotation_accumulated = accumulated
	return frame

func _grind_frame(pose: int) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 2
	frame.speed_mps = 13.0
	frame.speed_ratio = 0.55
	frame.rail_speed = 13.0
	frame.rail_pose = pose
	frame.rail_distance_to_end = 5.0
	return frame

func _project_gameplay_landmark(camera: Camera3D, world_position: Vector3) -> Vector2:
	var camera_space := camera.global_transform.affine_inverse() * world_position
	var depth := maxf(0.01, -camera_space.z)
	var focal_scale := 1.0 / tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(camera_space.x, -camera_space.y) * focal_scale / depth

func _assert_projected_separation(label: String, baseline: Dictionary, candidate: Dictionary) -> void:
	var body_height := float(baseline.body_height)
	var differences: Array[float] = []
	var largest_landmark := ""
	var largest := 0.0
	for key: String in ["left_knee", "right_knee", "pelvis", "left_boot", "right_boot", "left_hand", "right_hand", "left_ski_nose", "right_ski_nose"]:
		var difference := (candidate[key] as Vector2).distance_to(baseline[key] as Vector2) / body_height
		differences.append(difference)
		if difference > largest:
			largest = difference
			largest_landmark = key
	differences.sort()
	var readable_count := 0
	for difference: float in differences:
		if difference >= 0.05:
			readable_count += 1
	if largest < 0.12 or readable_count < 3:
		failures.append("%s was not distinct from straight air at gameplay distance (max %.1f%% at %s, landmarks over 5%%: %d)" % [label, largest * 100.0, largest_landmark, readable_count])

func _sample_spin_signature(degrees: float, side: float = 1.0) -> PackedFloat32Array:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _air_frame()
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.SPIN_LEFT if side < 0.0 else TrickCommand.Kind.SPIN_RIGHT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(0.0, side * 5.4, 0.0)
	frame.rotation_accumulated = Vector3(0.0, side * deg_to_rad(degrees), 0.0)
	_step(rig, frame, 90)
	var snapshot := rig.debug_snapshot()
	var signature := PackedFloat32Array([
		(snapshot.left_knee_rotation as Vector3).x - (snapshot.right_knee_rotation as Vector3).x,
		(snapshot.pelvis_position as Vector3).x,
		(snapshot.pelvis_rotation as Vector3).y,
		(snapshot.chest_rotation as Vector3).y,
		(snapshot.chest_rotation as Vector3).z,
		(snapshot.left_shoulder_rotation as Vector3).x - (snapshot.right_shoulder_rotation as Vector3).x,
		(snapshot.left_shoulder_rotation as Vector3).z - (snapshot.right_shoulder_rotation as Vector3).z,
		(snapshot.left_ski_rotation as Vector3).x - (snapshot.right_ski_rotation as Vector3).x,
		(snapshot.left_ski_rotation as Vector3).z - (snapshot.right_ski_rotation as Vector3).z,
	])
	remove_child(rig)
	rig.free()
	return signature

func _signature_difference(left: PackedFloat32Array, right: PackedFloat32Array) -> float:
	var difference := 0.0
	for index: int in left.size():
		difference += absf(left[index] - right[index])
	return difference

func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = 20.0
	frame.speed_ratio = 1.0
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	return frame

func _air_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.8
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.9
	frame.takeoff_upward_speed = 4.0
	frame.air_time = 0.48
	frame.air_upward_velocity = 0.0
	frame.predicted_landing_time = 0.52
	return frame

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int) -> void:
	for _index: int in count:
		rig.apply_frame(frame, STEP)
