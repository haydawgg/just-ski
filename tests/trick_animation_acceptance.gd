extends Node

const STEP := 1.0 / 120.0

var failures: Array[String] = []
var maximum_knee_delta := 0.0
var maximum_pelvis_delta := 0.0
var maximum_ski_delta := 0.0
var maximum_shoulder_delta := 0.0

func _ready() -> void:
	_test_straight_air_stays_clean()
	_test_prewind_and_abort()
	_test_takeoff_release_propagation()
	_test_mirrored_spin_counts()
	_test_higher_spin_compactness()
	_test_under_and_over_rotation()
	_test_landing_handoff()
	_test_air_to_rail_handoff()
	_test_rail_exit_spin_handoff()
	_test_supported_multi_axis_rotation()
	_test_spin_visual_phase_vocabulary()
	_test_flip_family_shape_separation()
	_test_clean_360_frame_sequence()
	AudioManager.shutdown_audio()
	print("TRICK_ANIMATION_RESULT knee_delta=%.4f pelvis_delta=%.4f ski_delta=%.4f shoulder_delta=%.4f" % [
		maximum_knee_delta,
		maximum_pelvis_delta,
		maximum_ski_delta,
		maximum_shoulder_delta,
	])
	if maximum_knee_delta > 0.65 or maximum_pelvis_delta > 0.1 or maximum_ski_delta > 0.32 or maximum_shoulder_delta > 0.55:
		failures.append("Trick animation produced a one-frame snap")
	if failures.is_empty():
		print("TRICK_ANIMATION_PASS: straight air, prewind, mirrored 180/360, higher spins, rotation error, landing, rail handoffs, and supported multi-axis rotation passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("TRICK_ANIMATION_FAIL: " + failure)
	get_tree().quit(1)

func _test_straight_air_stays_clean() -> void:
	var rig := _new_rig()
	var frame := _air_frame()
	frame.angular_velocity = Vector3(0.08, 0.18, 0.05)
	_step(rig, frame, 90, true)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.trick_pose_weight) > 0.05 or float(snapshot.spin_compactness) > 0.05:
		failures.append("Straight air gained a trick pose from insignificant angular drift")
	if str(snapshot.pose).find("Spin") >= 0 or str(snapshot.pose).find("Cork") >= 0:
		failures.append("Straight air was mislabeled as a rotation")
	_assert_root_unchanged(rig, "Straight-air animation")
	_dispose_rig(rig)

func _test_prewind_and_abort() -> void:
	var rig := _new_rig()
	var frame := _ground_frame()
	frame.trick_phase = TrickCommand.PresentationPhase.SETUP
	frame.trick_intent = true
	frame.gesture_strength = 0.9
	frame.gesture_direction = Vector2(-0.72, 0.7)
	_step(rig, frame, 55, true)
	var set_pose := rig.debug_snapshot()
	if float(set_pose.prewind_weight) < 0.45 or str(set_pose.pose).find("Prewind Left") < 0:
		failures.append("Left trick intent did not build a readable prewind")
	if absf(float((set_pose.chest_rotation as Vector3).y)) > rig.profile.trick_chest_yaw_limit + 0.03:
		failures.append("Prewind exceeded the configured chest yaw limit")
	if absf(float((set_pose.left_ski_rotation as Vector3).y) - float((set_pose.right_ski_rotation as Vector3).y)) > 0.04:
		failures.append("Prewind rotated the skis apart while grounded")
	frame.trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	frame.trick_intent = false
	frame.gesture_strength = 0.0
	frame.gesture_direction = Vector2.ZERO
	_step(rig, frame, 90, true)
	if float(rig.debug_snapshot().prewind_weight) > 0.08:
		failures.append("Aborted trick intent did not unwind smoothly")
	_dispose_rig(rig)

func _test_takeoff_release_propagation() -> void:
	var rig := _new_rig()
	var setup := _ground_frame()
	setup.trick_phase = TrickCommand.PresentationPhase.SETUP
	setup.trick_intent = true
	setup.gesture_strength = 1.0
	setup.gesture_direction = Vector2(-0.8, 0.65)
	_step(rig, setup, 35, true)
	var release := _spin_frame(-1.0, 18.0, 4.2)
	release.trick_phase = TrickCommand.PresentationPhase.RELEASE
	_step(rig, release, 10, true)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.trick_release_weight) < 0.08:
		failures.append("Takeoff did not retain a release impulse")
	var chest_yaw := absf(float((snapshot.chest_rotation as Vector3).y))
	var pelvis_yaw := absf(float((snapshot.pelvis_rotation as Vector3).y))
	if chest_yaw <= pelvis_yaw + 0.025:
		failures.append("Takeoff release did not propagate shoulders/chest ahead of the pelvis")
	_assert_root_unchanged(rig, "Takeoff release")
	_dispose_rig(rig)

func _test_mirrored_spin_counts() -> void:
	for degrees: float in [180.0, 360.0]:
		var left := _sample_spin(-1.0, degrees, 2.8 if degrees <= 180.0 else 4.2)
		var right := _sample_spin(1.0, degrees, 2.8 if degrees <= 180.0 else 4.2)
		var left_chest := float((left.chest_rotation as Vector3).y)
		var right_chest := float((right.chest_rotation as Vector3).y)
		if left_chest * right_chest >= 0.0:
			failures.append("Left/right %.0f spins did not mirror torso participation" % degrees)
		if absf(absf(left_chest) - absf(right_chest)) > 0.08:
			failures.append("Left/right %.0f spin magnitudes diverged unexpectedly" % degrees)
		if float(left.ski_yaw_separation) > 0.08 or float(right.ski_yaw_separation) > 0.08:
			failures.append("%.0f spin allowed unsafe ski yaw separation (left %.3f right %.3f)" % [degrees, float(left.ski_yaw_separation), float(right.ski_yaw_separation)])

func _test_higher_spin_compactness() -> void:
	var low := _sample_spin(1.0, 180.0, 2.2)
	var high := _sample_spin(1.0, 720.0, 6.6)
	if float(high.spin_compactness) <= float(low.spin_compactness) + 0.18:
		failures.append("Higher supported spin demand did not produce a more compact pose")
	if float(high.knee_flex) <= float(low.knee_flex) + 0.05:
		failures.append("Higher spin demand did not increase athletic knee flex")

func _test_under_and_over_rotation() -> void:
	var under := _sample_late_spin(351.0)
	var over := _sample_late_spin(367.0)
	if float((under.rotation_residual as Vector3).y) >= 0.0:
		failures.append("351-degree execution was not preserved as under-rotation")
	if float((over.rotation_residual as Vector3).y) <= 0.0:
		failures.append("367-degree execution was not preserved as over-rotation")
	var under_chest := float((under.chest_rotation as Vector3).y)
	var over_chest := float((over.chest_rotation as Vector3).y)
	if under_chest * over_chest >= 0.0:
		failures.append("Under/over rotation did not produce opposite bounded torso recovery")

func _test_landing_handoff() -> void:
	var rig := _new_rig()
	var frame := _spin_frame(1.0, 260.0, 4.6)
	frame.predicted_landing_time = 0.5
	_step(rig, frame, 35, true)
	var midair_weight := float(rig.debug_snapshot().trick_pose_weight)
	frame.rotation_accumulated.y = deg_to_rad(351.0)
	frame.rotation_residual.y = deg_to_rad(-9.0)
	frame.predicted_landing_time = 0.08
	frame.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, frame, 45, true)
	var late := rig.debug_snapshot()
	if float(late.landing_blend) < 0.35:
		failures.append("Landing preparation did not gain priority near contact")
	if float(late.trick_pose_weight) >= midair_weight:
		failures.append("Trick layer did not yield progressively to landing preparation")
	var smooth_peak := _sample_landing_peak(0.2, LandingSolver.Outcome.CLEAN)
	var rough_peak := _sample_landing_peak(0.72, LandingSolver.Outcome.SKETCHY)
	if rough_peak <= smooth_peak + 0.12:
		failures.append("Rough spin landing did not hand off to stronger Phase 6 recovery")
	_assert_root_unchanged(rig, "Landing handoff")
	_dispose_rig(rig)

func _test_air_to_rail_handoff() -> void:
	var rig := _new_rig()
	var frame := _spin_frame(-1.0, 225.0, 4.0)
	_step(rig, frame, 35, true)
	frame = _grind_frame()
	_step(rig, frame, 70, true)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.trick_pose_weight) > 0.08:
		failures.append("Airborne trick influence fought the attached rail state")
	if float(snapshot.rail_influence) < 0.65 or str(snapshot.pose).find("Rail") < 0:
		failures.append("Phase 7 did not dominate after air-to-rail capture")
	_assert_root_unchanged(rig, "Air-to-rail handoff")
	_dispose_rig(rig)

func _test_rail_exit_spin_handoff() -> void:
	var rig := _new_rig()
	var grind := _grind_frame()
	_step(rig, grind, 45, true)
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, 0.5, 1.0)
	var air := _spin_frame(1.0, 120.0, 4.2)
	_step(rig, air, 55, true)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.trick_pose_weight) < 0.35 or str(snapshot.pose).find("Spin") < 0:
		failures.append("Actual rotation after rail release did not resume Phase 8")
	air.predicted_landing_time = 0.1
	air.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, air, 40, true)
	if float(rig.debug_snapshot().landing_blend) < 0.25:
		failures.append("Rail-exit spin did not blend onward into landing preparation")
	_assert_root_unchanged(rig, "Rail-exit spin")
	_dispose_rig(rig)

func _test_supported_multi_axis_rotation() -> void:
	var rig := _new_rig()
	var cork := _spin_frame(-1.0, 240.0, 3.8)
	cork.trick_kind = TrickCommand.Kind.CORK_LEFT
	cork.angular_velocity.z = -4.1
	cork.rotation_accumulated.z = deg_to_rad(-255.0)
	cork.rotation_residual.z = deg_to_rad(-75.0)
	_step(rig, cork, 60, true)
	var cork_snapshot := rig.debug_snapshot()
	if str(cork_snapshot.pose).find("Cork Left") < 0:
		failures.append("Existing yaw/roll cork support lost its readable pose")
	if absf(float((cork_snapshot.chest_rotation as Vector3).z)) > 0.48:
		failures.append("Combined cork correction exceeded a plausible chest roll")
	var flip := _air_frame()
	flip.trick_active = true
	flip.trick_intent = true
	flip.trick_kind = TrickCommand.Kind.FRONTFLIP
	flip.trick_phase = TrickCommand.PresentationPhase.ROTATE
	flip.angular_velocity = Vector3(4.5, 0.0, 0.0)
	flip.rotation_accumulated.x = PI
	_step(rig, flip, 60, true)
	if str(rig.debug_snapshot().pose).find("Frontflip") < 0:
		failures.append("Existing pitch flip support was not preserved")
	_assert_root_unchanged(rig, "Multi-axis trick animation")
	_dispose_rig(rig)

func _test_spin_visual_phase_vocabulary() -> void:
	var rig := _new_rig()
	var setup := _ground_frame()
	setup.trick_phase = TrickCommand.PresentationPhase.SETUP
	setup.trick_intent = true
	setup.gesture_strength = 1.0
	setup.gesture_direction = Vector2.RIGHT
	_step(rig, setup, 40, true)
	if str(rig.debug_snapshot().spin_visual_phase) != "SETUP":
		failures.append("Spin vocabulary did not expose setup/prewind")
	var spin := _spin_frame(1.0, 82.0, 5.0)
	spin.rotation_residual.y = deg_to_rad(-98.0)
	_step(rig, spin, 35, true)
	if str(rig.debug_snapshot().spin_visual_phase) != "COMPACT":
		failures.append("Spin vocabulary did not enter compact rotation")
	spin.rotation_accumulated.y = PI
	spin.rotation_residual.y = 0.0
	_step(rig, spin, 30, true)
	if str(rig.debug_snapshot().spin_visual_phase) != "SPOT":
		failures.append("Spin vocabulary did not spot near half-turn alignment")
	spin.rotation_accumulated.y = deg_to_rad(351.0)
	spin.rotation_residual.y = deg_to_rad(-9.0)
	spin.predicted_landing_time = 0.08
	spin.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, spin, 35, true)
	if str(rig.debug_snapshot().spin_visual_phase) != "OPEN":
		failures.append("Spin vocabulary did not delay opening until final landing readiness")
	_assert_root_unchanged(rig, "Spin visual phases")
	_dispose_rig(rig)

func _test_flip_family_shape_separation() -> void:
	var front_rig := _new_rig()
	var front := _air_frame()
	front.trick_active = true
	front.trick_intent = true
	front.trick_kind = TrickCommand.Kind.FRONTFLIP
	front.trick_phase = TrickCommand.PresentationPhase.ROTATE
	front.angular_velocity.x = 4.8
	front.rotation_accumulated.x = deg_to_rad(60.0)
	_step(front_rig, front, 55, true)
	var front_pose := front_rig.debug_snapshot()
	var back_rig := _new_rig()
	var back := _air_frame()
	back.trick_active = true
	back.trick_intent = true
	back.trick_kind = TrickCommand.Kind.BACKFLIP
	back.trick_phase = TrickCommand.PresentationPhase.ROTATE
	back.angular_velocity.x = -4.8
	back.rotation_accumulated.x = deg_to_rad(-60.0)
	_step(back_rig, back, 55, true)
	var back_pose := back_rig.debug_snapshot()
	var torso_difference := (front_pose.spine_rotation as Vector3).distance_to(back_pose.spine_rotation as Vector3)
	var arm_difference := (front_pose.left_shoulder_rotation as Vector3).distance_to(back_pose.left_shoulder_rotation as Vector3)
	if torso_difference < 0.22 or arm_difference < 0.22:
		failures.append("Frontflip and backflip body shapes remained visually interchangeable")
	if str(front_pose.pose).find("Frontflip") < 0 or str(back_pose.pose).find("Backflip") < 0:
		failures.append("Flip-family pose labels were not distinct")
	_assert_root_unchanged(front_rig, "Frontflip family")
	_assert_root_unchanged(back_rig, "Backflip family")
	_dispose_rig(front_rig)
	_dispose_rig(back_rig)

func _test_clean_360_frame_sequence() -> void:
	var rig := _new_rig()
	var frame := _ground_frame()
	frame.trick_phase = TrickCommand.PresentationPhase.SETUP
	frame.trick_intent = true
	frame.gesture_strength = 1.0
	frame.gesture_direction = Vector2(0.8, 0.7)
	_step(rig, frame, 30, true)
	if str(rig.debug_snapshot().pose).find("Prewind") < 0:
		failures.append("Clean 360 frame A/B lacked a set pose")
	frame = _spin_frame(1.0, 12.0, 4.4)
	frame.trick_phase = TrickCommand.PresentationPhase.RELEASE
	_step(rig, frame, 8, true)
	if str(rig.debug_snapshot().pose).find("Release") < 0:
		failures.append("Clean 360 frame C lacked takeoff release")
	for degrees: float in [90.0, 180.0, 270.0]:
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.rotation_accumulated.y = deg_to_rad(degrees)
		_step(rig, frame, 18, true)
		if str(rig.debug_snapshot().pose).find("Spin") < 0:
			failures.append("Clean 360 rotation lost its body pose near %.0f degrees" % degrees)
	frame.rotation_accumulated.y = deg_to_rad(351.0)
	frame.rotation_residual.y = deg_to_rad(-9.0)
	frame.predicted_landing_time = 0.09
	frame.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, frame, 35, true)
	if str(rig.debug_snapshot().pose).find("Landing") < 0:
		failures.append("Clean 360 frame H/I lacked landing preparation")
	var ground := _ground_frame()
	ground.landing_event_active = true
	ground.landing_impact_severity = 0.25
	ground.landing_outcome = LandingSolver.Outcome.CLEAN
	ground.landing_rotation_error = -0.05
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.25, 0.0)
	_step(rig, ground, 40, true)
	if str(rig.debug_snapshot().pose).find("Landing") < 0:
		failures.append("Clean 360 frame J did not enter impact/recovery")
	_assert_root_unchanged(rig, "Clean 360 sequence")
	_dispose_rig(rig)

func _sample_spin(side: float, degrees: float, rate: float) -> Dictionary:
	var rig := _new_rig()
	var frame := _spin_frame(side, degrees, rate)
	_step(rig, frame, 75, true)
	var snapshot := rig.debug_snapshot()
	snapshot["ski_yaw_separation"] = absf(float((snapshot.left_ski_rotation as Vector3).y) - float((snapshot.right_ski_rotation as Vector3).y))
	snapshot["knee_flex"] = (
		float((snapshot.left_knee_rotation as Vector3).x)
		+ float((snapshot.right_knee_rotation as Vector3).x)
	) * 0.5
	_assert_root_unchanged(rig, "%.0f spin" % degrees)
	_dispose_rig(rig)
	return snapshot

func _sample_late_spin(degrees: float) -> Dictionary:
	var rig := _new_rig()
	var frame := _spin_frame(1.0, degrees, 2.8)
	frame.rotation_residual.y = deg_to_rad(degrees - 360.0)
	frame.predicted_landing_time = 0.06
	frame.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, frame, 70, true)
	var snapshot := rig.debug_snapshot()
	_assert_root_unchanged(rig, "Late spin")
	_dispose_rig(rig)
	return snapshot

func _sample_landing_peak(severity: float, outcome: int) -> float:
	var rig := _new_rig()
	var frame := _ground_frame()
	frame.landing_event_active = true
	frame.landing_impact_severity = severity
	frame.landing_balance_error = severity * 0.45
	frame.landing_rotation_error = -0.05
	frame.landing_outcome = outcome
	var event := SkierAnimationController.AnimationEvent.LAND_CLEAN if outcome == LandingSolver.Outcome.CLEAN else SkierAnimationController.AnimationEvent.LAND_SKETCHY
	rig.trigger(event, severity, 0.0)
	var peak := 0.0
	for _index: int in 80:
		rig.apply_frame(frame, STEP)
		peak = maxf(peak, float(rig.debug_snapshot().landing_compression))
	_assert_root_unchanged(rig, "Spin landing recovery")
	_dispose_rig(rig)
	return peak

func _spin_frame(side: float, degrees: float, rate: float) -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.SPIN_LEFT if side < 0.0 else TrickCommand.Kind.SPIN_RIGHT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(0.0, side * rate, 0.0)
	frame.rotation_accumulated = Vector3(0.0, side * deg_to_rad(degrees), 0.0)
	frame.rotation_progress = fmod(degrees / 360.0, 1.0)
	return frame

func _air_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.8
	frame.takeoff_upward_speed = 4.0
	frame.air_time = 0.45
	frame.air_upward_velocity = 0.4
	frame.speed_mps = 15.0
	frame.speed_ratio = 0.62
	frame.skier_heading = Vector3.FORWARD
	frame.velocity_heading = Vector3.FORWARD
	return frame

func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = 13.0
	frame.speed_ratio = 0.54
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	return frame

func _grind_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 2
	frame.speed_mps = 10.0
	frame.speed_ratio = 0.42
	frame.rail_speed = 10.0
	frame.rail_balance = 0.18
	frame.rail_pose = 0
	frame.rail_direction = Vector3.FORWARD
	frame.rail_distance_to_end = 5.0
	return frame

func _new_rig() -> SkierAnimationController:
	var rig := SkierAnimationController.new()
	add_child(rig)
	return rig

func _dispose_rig(rig: SkierAnimationController) -> void:
	remove_child(rig)
	rig.queue_free()

func _assert_root_unchanged(rig: SkierAnimationController, context: String) -> void:
	if rig.rotation.length() > 0.0001:
		failures.append("%s wrote visual root rotation instead of remaining physics-subordinate" % context)

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int, record_deltas: bool) -> void:
	var previous := rig.debug_snapshot()
	for _index: int in count:
		rig.apply_frame(frame, STEP)
		if record_deltas:
			var current := rig.debug_snapshot()
			maximum_knee_delta = maxf(maximum_knee_delta, (current.left_knee_rotation as Vector3).distance_to(previous.left_knee_rotation as Vector3))
			maximum_pelvis_delta = maxf(maximum_pelvis_delta, (current.pelvis_position as Vector3).distance_to(previous.pelvis_position as Vector3))
			maximum_ski_delta = maxf(maximum_ski_delta, (current.left_ski_rotation as Vector3).distance_to(previous.left_ski_rotation as Vector3))
			maximum_shoulder_delta = maxf(maximum_shoulder_delta, (current.left_shoulder_rotation as Vector3).distance_to(previous.left_shoulder_rotation as Vector3))
			previous = current
