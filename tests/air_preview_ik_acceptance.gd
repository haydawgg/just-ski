extends Node

const ANIMATION_PROFILE := preload("res://resources/animation/default_animation_profile.tres")
const TEST_HZ := [30, 60, 120]
const STEP := 1.0 / 60.0
const PLANE_POINT := Vector3(0.0, -0.21, 0.0)
const CROSS_RATE_POSITION := 0.08
const CROSS_RATE_ANGLE := deg_to_rad(8.0)

var failures: Array[String] = []

func _ready() -> void:
	_test_targets_invalid_outside_window()
	_test_targets_valid_inside_window()
	_test_targets_lie_on_predicted_plane()
	_test_forwards_are_plane_tangent()
	_test_stance_and_no_crossing()
	_test_finite_slope_and_degenerate_heading()
	_test_pelvis_correction_bounded()
	_test_no_root_transform_writes()
	_test_preview_to_ground_handoff()
	_test_cross_rate_determinism()
	await _test_feature_obstruction_veto()
	await _test_gameplay_ownership_and_prediction_cache()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("AIR_PREVIEW_IK_PASS: predicted-surface AIR ski IK window, plane, stance, ownership, veto, handoff, and 30/60/120 Hz determinism passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("AIR_PREVIEW_IK_FAIL: " + failure)
	get_tree().quit(1)

func _test_targets_invalid_outside_window() -> void:
	var frame := _preview_frame(ANIMATION_PROFILE.landing_anticipation_time + 0.15)
	var preview: Dictionary = _synthesize(frame)
	if bool(preview.valid):
		failures.append("Preview targets were valid outside the landing anticipation window")
	frame.predicted_landing_valid = false
	frame.predicted_landing_time = 0.1
	preview = _synthesize(frame)
	if bool(preview.valid):
		failures.append("Preview targets were valid without a landing prediction")
	frame = _preview_frame(0.12)
	frame.spawn_settle_active = true
	preview = _synthesize(frame)
	if bool(preview.valid):
		failures.append("Preview targets were valid during spawn settle")

func _test_targets_valid_inside_window() -> void:
	var frame := _preview_frame(0.18)
	var preview: Dictionary = _synthesize(frame)
	if not bool(preview.valid):
		failures.append("Preview targets were invalid inside the landing anticipation window")
	if not SkiConstrainedLegIK.is_finite_transform(preview.left) or not SkiConstrainedLegIK.is_finite_transform(preview.right):
		failures.append("Preview targets inside the window were non-finite")

func _test_targets_lie_on_predicted_plane() -> void:
	var normal := Vector3(0.0, 0.92, 0.39).normalized()
	var frame := _preview_frame(0.12, PLANE_POINT, normal)
	var preview: Dictionary = _synthesize(frame)
	if not bool(preview.valid):
		failures.append("Sloped preview targets were invalid")
		return
	var lift := SkiConstrainedLegIK.CONTACT_LIFT
	for side: String in ["left", "right"]:
		var origin: Vector3 = (preview[side] as Transform3D).origin
		var height := (origin - PLANE_POINT).dot(normal)
		if absf(height - lift) > 0.025:
			failures.append("Preview %s target was %.3f m from the predicted plane (expected %.3f m lift)" % [side, height, lift])

func _test_forwards_are_plane_tangent() -> void:
	var normal := Vector3(0.25, 0.9, 0.35).normalized()
	var frame := _preview_frame(0.1, PLANE_POINT, normal)
	var preview: Dictionary = _synthesize(frame)
	if not bool(preview.valid):
		failures.append("Tangent-forward preview targets were invalid")
		return
	for side: String in ["left", "right"]:
		var forward := -(preview[side] as Transform3D).basis.z
		if absf(forward.dot(normal)) > 0.03:
			failures.append("Preview %s forward was not tangent to the predicted plane" % side)

func _test_stance_and_no_crossing() -> void:
	var frame := _preview_frame(0.1)
	var preview: Dictionary = _synthesize(frame)
	if not bool(preview.valid):
		failures.append("Stance preview targets were invalid")
		return
	var left: Vector3 = (preview.left as Transform3D).origin
	var right: Vector3 = (preview.right as Transform3D).origin
	var lateral := ((preview.left as Transform3D).basis.x + (preview.right as Transform3D).basis.x).normalized()
	var separation := (right - left).dot(lateral)
	if separation < ANIMATION_PROFILE.leg_ik_min_stance_width - 0.0001:
		failures.append("Preview stance dropped below the minimum (%.3f m)" % separation)
	if left.x > right.x - 0.05:
		failures.append("Preview ski targets crossed")

func _test_finite_slope_and_degenerate_heading() -> void:
	var steep := Vector3(0.55, 0.55, 0.63).normalized()
	var frame := _preview_frame(0.08, Vector3(0.4, -0.1, -0.2), steep)
	frame.ski_forward = steep
	frame.velocity_heading = Vector3.ZERO
	var preview: Dictionary = _synthesize(frame, Vector3(0.1, 0.2, -0.05), Basis.IDENTITY)
	if not bool(preview.valid):
		failures.append("Degenerate heading/slope preview targets were invalid")
		return
	if not SkiConstrainedLegIK.is_finite_transform(preview.left) or not SkiConstrainedLegIK.is_finite_transform(preview.right):
		failures.append("Degenerate heading/slope preview produced a non-finite transform")

func _test_pelvis_correction_bounded() -> void:
	var rig := _new_rig()
	var frame := _air_preview_pose_frame(0.08)
	_step(rig, frame, 48)
	var snapshot := rig.debug_snapshot()
	var correction := snapshot.pelvis_ik_correction as Vector3
	if correction.length() > ANIMATION_PROFILE.leg_ik_pelvis_translation_limit + 0.001:
		failures.append("AIR preview pelvis correction exceeded %.3f m (%.3f m)" % [
			ANIMATION_PROFILE.leg_ik_pelvis_translation_limit,
			correction.length(),
		])
	_dispose_rig(rig)

func _test_no_root_transform_writes() -> void:
	var rig := _new_rig()
	rig.global_transform = Transform3D(Basis.from_euler(Vector3(0.05, 0.2, -0.04)), Vector3(1.5, 0.4, -2.2))
	var before := rig.global_transform
	var frame := _air_preview_pose_frame(0.08)
	_step(rig, frame, 36)
	if not before.is_equal_approx(rig.global_transform):
		failures.append("AIR preview IK wrote the animation root transform")
	_dispose_rig(rig)

func _test_preview_to_ground_handoff() -> void:
	var rig := _new_rig()
	var frame := _air_preview_pose_frame(0.08)
	_step(rig, frame, 50)
	var air_snapshot := rig.debug_snapshot()
	if not bool(air_snapshot.air_preview_targets_valid):
		failures.append("AIR preview targets did not become valid before the GROUND handoff")
	if float(air_snapshot.leg_ik_weight) < 0.08:
		failures.append("AIR preview IK weight stayed near zero before the GROUND handoff")
	var air_left := rig.left_ski.global_transform
	var air_right := rig.right_ski.global_transform
	frame.locomotion_state = 0
	frame.grounded = true
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.predicted_landing_valid = false
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	frame.left_ski_target_world = air_left
	frame.right_ski_target_world = air_right
	rig.apply_frame(frame, STEP)
	var first := rig.debug_snapshot()
	var first_left_delta := rig.left_ski.global_position.distance_to(air_left.origin)
	if first_left_delta > 0.22:
		failures.append("AIR-to-GROUND ski handoff snapped %.3f m on the first contact frame" % first_left_delta)
	if float(first.leg_ik_weight) + 0.02 < float(air_snapshot.leg_ik_weight) * 0.35:
		failures.append("AIR-to-GROUND ski handoff dropped IK weight instead of transferring to contact targets")
	_step(rig, frame, 18)
	_dispose_rig(rig)

func _test_cross_rate_determinism() -> void:
	var poses: Dictionary = {}
	for hz: int in TEST_HZ:
		poses[hz] = _preview_pose_at_rate(hz, 0.22)
	for hz: int in TEST_HZ:
		var pose: Dictionary = poses[hz]
		if not bool(pose.valid):
			failures.append("AIR preview pose at %d Hz was non-finite or invalid" % hz)
	var reference: Dictionary = poses[60]
	for hz: int in TEST_HZ:
		if hz == 60:
			continue
		var pose: Dictionary = poses[hz]
		var left_delta: float = (pose.left_origin as Vector3).distance_to(reference.left_origin as Vector3)
		var right_delta: float = (pose.right_origin as Vector3).distance_to(reference.right_origin as Vector3)
		var angle := (pose.left_basis as Basis).get_rotation_quaternion().angle_to((reference.left_basis as Basis).get_rotation_quaternion())
		if left_delta > CROSS_RATE_POSITION or right_delta > CROSS_RATE_POSITION or angle > CROSS_RATE_ANGLE:
			failures.append("AIR preview %d Hz pose diverged from 60 Hz (left %.3f m right %.3f m angle %.2f deg)" % [
				hz,
				left_delta,
				right_delta,
				rad_to_deg(angle),
			])

func _test_feature_obstruction_veto() -> void:
	var floor_body := _make_box_body("PreviewSnow", 1, Vector3(8.0, 0.2, 8.0), Vector3(0.0, -0.31, 0.0))
	var feature := _make_box_body("PreviewFeature", 4, Vector3(1.2, 0.08, 1.2), Vector3(0.0, -0.13, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var blocked := SkiConstrainedLegIK.feature_obstruction_scale(
		space,
		Vector3(0.0, 0.05, 0.0),
		Vector3(0.0, -0.21, 0.0)
	)
	if blocked > 0.001:
		failures.append("Feature obstruction veto did not disable a solid park feature between ski and snow")
	var clear := SkiConstrainedLegIK.feature_obstruction_scale(
		space,
		Vector3(3.0, 0.4, 3.0),
		Vector3(3.0, -0.21, 3.0)
	)
	if clear < 0.999:
		failures.append("Feature obstruction veto disabled a clear predicted-surface reach")
	var rig := _new_rig()
	rig.position = Vector3(0.0, 0.12, 0.0)
	var frame := _air_preview_pose_frame(0.08)
	_step(rig, frame, 40)
	var snapshot := rig.debug_snapshot()
	if bool(snapshot.air_preview_targets_valid) and float(snapshot.air_preview_obstruction) > 0.001:
		failures.append("AIR preview IK stayed active through a solid park feature (obstruction %.3f weight %.3f)" % [
			float(snapshot.air_preview_obstruction),
			float(snapshot.air_preview_ik_weight),
		])
	_dispose_rig(rig)
	floor_body.queue_free()
	feature.queue_free()

func _test_gameplay_ownership_and_prediction_cache() -> void:
	var floor_body := _make_box_body("OwnershipSnow", 1, Vector3(12.0, 0.4, 12.0), Vector3(0.0, -0.2, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier._end_spawn_settle()
	skier.state = SkierController.State.AIR
	skier.air_deliberate = true
	skier.air_time = 0.55
	skier.global_position = Vector3(0.0, 1.35, 0.0)
	skier.velocity = Vector3(0.0, -4.5, -7.0)
	skier.angular_velocity = Vector3(0.1, 0.4, -0.05)
	skier.trick.active = true
	skier.trick.accumulated_rotation = Vector3(0.2, 1.4, 0.0)
	skier.scoring.total_score = 1250
	skier.contact.grounded = false
	await get_tree().physics_frame
	skier._physics_step_serial += 1
	var before_evaluations: int = skier._landing_prediction_evaluations
	var before_transform := skier.global_transform
	var before_velocity := skier.velocity
	var before_contact := skier.contact.grounded
	var before_left_hit := skier.contact.left_hit_position
	var before_score := skier.scoring.snapshot()
	var before_rotation := skier.trick.accumulated_rotation
	var before_trick_active := skier.trick.active
	var before_landing := skier.landing_context.duplicate(true)
	skier._update_animation(STEP)
	skier._update_animation(STEP)
	if skier._landing_prediction_evaluations - before_evaluations != 1:
		failures.append("Landing prediction evaluated %d times in one physics step" % (skier._landing_prediction_evaluations - before_evaluations))
	if not before_transform.is_equal_approx(skier.global_transform):
		failures.append("AIR preview IK wrote the gameplay root transform")
	if not before_velocity.is_equal_approx(skier.velocity):
		failures.append("AIR preview IK wrote gameplay velocity")
	if skier.contact.grounded != before_contact or not skier.contact.left_hit_position.is_equal_approx(before_left_hit):
		failures.append("AIR preview IK wrote gameplay contact")
	if skier.scoring.snapshot() != before_score:
		failures.append("AIR preview IK wrote scoring state")
	if skier.trick.accumulated_rotation != before_rotation or skier.trick.active != before_trick_active:
		failures.append("AIR preview IK wrote trick rotation state")
	if str(skier.landing_context) != str(before_landing):
		failures.append("AIR preview IK wrote landing classification state")
	remove_child(skier)
	skier.queue_free()
	floor_body.queue_free()

func _preview_pose_at_rate(hz: int, seconds: float) -> Dictionary:
	var rig := _new_rig()
	var frame := _air_preview_pose_frame(0.2)
	var dt := 1.0 / float(hz)
	var steps := int(round(seconds * float(hz)))
	for index: int in steps:
		frame.predicted_landing_time = maxf(0.04, 0.22 - dt * float(index + 1))
		rig.apply_frame(frame, dt)
	var left := rig.left_ski.global_transform
	var right := rig.right_ski.global_transform
	var valid := SkiConstrainedLegIK.is_finite_transform(left) and SkiConstrainedLegIK.is_finite_transform(right)
	var result := {
		"valid": valid,
		"left_origin": left.origin,
		"right_origin": right.origin,
		"left_basis": left.basis,
	}
	_dispose_rig(rig)
	return result

func _synthesize(
	frame: SkierAnimationFrame,
	body_origin: Vector3 = Vector3.ZERO,
	body_basis: Basis = Basis.IDENTITY
) -> Dictionary:
	return LandingPoseLayer.air_preview_targets(
		frame,
		ANIMATION_PROFILE,
		ANIMATION_PROFILE.leg_ik_min_stance_width,
		body_origin,
		body_basis
	)

func _preview_frame(
	time_to_contact: float,
	point: Vector3 = PLANE_POINT,
	normal: Vector3 = Vector3.UP
) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.predicted_landing_valid = true
	frame.predicted_landing_time = time_to_contact
	frame.predicted_landing_point = point
	frame.predicted_landing_normal = normal
	frame.ski_forward = Vector3.FORWARD
	frame.ski_forward_valid = true
	frame.ski_up = Vector3.UP
	frame.ski_up_valid = true
	frame.velocity_heading = Vector3.FORWARD
	frame.body_up = Vector3.UP
	frame.body_up_valid = true
	frame.left_ground_distance = 0.92
	frame.right_ground_distance = 0.92
	frame.seat_distance = 0.54
	return frame

func _air_preview_pose_frame(time_to_contact: float) -> SkierAnimationFrame:
	var frame := _preview_frame(time_to_contact)
	frame.speed_mps = 14.0
	frame.speed_ratio = 0.6
	frame.air_time = 0.7
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.85
	frame.takeoff_upward_speed = 3.8
	frame.air_upward_velocity = -3.2
	frame.vertical_velocity = -3.2
	return frame

func _new_rig() -> SkierAnimationController:
	var rig := SkierAnimationController.new()
	add_child(rig)
	return rig

func _dispose_rig(rig: SkierAnimationController) -> void:
	remove_child(rig)
	rig.queue_free()

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int) -> void:
	for _index: int in count:
		rig.apply_frame(frame, STEP)

func _make_box_body(body_name: String, layer: int, size: Vector3, body_position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = body_position
	add_child(body)
	return body
