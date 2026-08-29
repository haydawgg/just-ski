extends Node

const STEP := 1.0 / 120.0
const SKI_GRABS: Array[int] = [
	TrickController.GrabPose.SAFETY_LEFT,
	TrickController.GrabPose.SAFETY_RIGHT,
	TrickController.GrabPose.MUTE_LEFT,
	TrickController.GrabPose.MUTE_RIGHT,
	TrickController.GrabPose.JAPAN_LEFT,
	TrickController.GrabPose.JAPAN_RIGHT,
	TrickController.GrabPose.TAIL,
	TrickController.GrabPose.NOSE,
	TrickController.GrabPose.DOUBLE,
]

var failures: Array[String] = []
var maximum_shoulder_delta := 0.0
var maximum_knee_delta := 0.0
var maximum_pelvis_delta := 0.0
var maximum_ski_delta := 0.0

func _ready() -> void:
	_test_no_ground_contact()
	_test_safety_left_sequence()
	_test_mirrored_and_cross_body_targets()
	_test_supported_definition_coverage()
	_test_leg_and_body_lead_hand_contact()
	_test_spin_grab_layering()
	_test_release_and_landing_handoff()
	_test_short_air_and_late_hold()
	_test_target_tracks_ski()
	_test_released_grab_scoring_regression()
	AudioManager.shutdown_audio()
	print("GRAB_ANIMATION_RESULT shoulder_delta=%.4f knee_delta=%.4f pelvis_delta=%.4f ski_delta=%.4f" % [
		maximum_shoulder_delta,
		maximum_knee_delta,
		maximum_pelvis_delta,
		maximum_ski_delta,
	])
	if maximum_shoulder_delta > 0.55 or maximum_knee_delta > 0.65 or maximum_pelvis_delta > 0.1 or maximum_ski_delta > 0.32:
		failures.append("Grab sequence produced a one-frame joint snap")
	if failures.is_empty():
		print("GRAB_ANIMATION_PASS: supported targets, body-assisted reach, contact hold, release, spins, landing, and scoring persistence passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("GRAB_ANIMATION_FAIL: " + failure)
	get_tree().quit(1)

func _test_no_ground_contact() -> void:
	var rig := _new_rig()
	var frame := _ground_frame()
	frame.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	_step(rig, frame, 60)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.get("grab_contact_weight", 0.0)) > 0.01:
		failures.append("Grounded grab input established visual hand-to-ski contact")
	if float(snapshot.get("grab_pose_weight", 0.0)) > 0.08:
		failures.append("Grounded grab input forced the full airborne grab pose")
	_assert_root_unchanged(rig, "Grounded grab")
	_dispose_rig(rig)

func _test_safety_left_sequence() -> void:
	var rig := _new_rig()
	var frame := _air_frame()
	_step(rig, frame, 30)
	var neutral := rig.debug_snapshot()
	frame.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	frame.grab_amount = 0.45
	frame.grab_input_strength = 0.45
	frame.grab_hold_time = 0.08
	_step(rig, frame, 24)
	var setup := rig.debug_snapshot()
	if str(setup.get("grab_phase", "")) not in ["SETUP", "REACH", "CONTACT"]:
		failures.append("Safety Left did not enter a progressive setup/reach phase")
	if float(setup.get("grab_compactness", 0.0)) < 0.12:
		failures.append("Safety Left setup did not compact the body")
	if absf(float((setup.left_knee_rotation as Vector3).x) - float((neutral.left_knee_rotation as Vector3).x)) < 0.04:
		failures.append("Safety Left setup did not involve the target leg")
	if absf(float((setup.chest_rotation as Vector3).z) - float((neutral.chest_rotation as Vector3).z)) < 0.015:
		failures.append("Safety Left setup did not involve the torso")
	var setup_error := float(setup.get("grab_reach_error_left", INF))
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.7
	_step(rig, frame, 100)
	var held := rig.debug_snapshot()
	print("GRAB_SEQUENCE setup_phase=%s setup_error=%.3f hold_phase=%s hold_error=%.3f contact=%.2f pose=%.2f" % [
		setup.get("grab_phase", ""), setup_error, held.get("grab_phase", ""),
		held.get("grab_reach_error_left", 0.0), held.get("grab_contact_weight", 0.0), held.get("grab_pose_weight", 0.0),
	])
	print("GRAB_REACH hand=%s target=%s shoulder=%s elbow=%s" % [
		held.get("grab_hand_left", Vector3.ZERO), held.get("grab_target_left", Vector3.ZERO),
		held.left_shoulder_rotation, rig.left_elbow.rotation,
	])
	if str(held.get("grab_type", "")) != "Safety Grab Left":
		failures.append("Safety Left did not resolve its authoritative display name")
	if str(held.get("grab_hand", "")) != "LEFT" or str(held.get("grab_target_ski", "")) != "LEFT":
		failures.append("Safety Left resolved the wrong hand or ski")
	if float(held.get("grab_reach_error_left", INF)) >= setup_error:
		failures.append("Safety Left hand did not close distance after body setup")
	if float(held.get("grab_contact_weight", 0.0)) < 0.55:
		failures.append("Safety Left never established stable visual contact")
	if str(held.get("grab_phase", "")) != "HOLD":
		failures.append("Sustained Safety Left did not settle into HOLD")
	_assert_root_unchanged(rig, "Safety Left")
	_dispose_rig(rig)

func _test_mirrored_and_cross_body_targets() -> void:
	var left := _sample_grab(TrickController.GrabPose.SAFETY_LEFT)
	var right := _sample_grab(TrickController.GrabPose.SAFETY_RIGHT)
	if str(left.grab_hand) != "LEFT" or str(right.grab_hand) != "RIGHT":
		failures.append("Mirrored safety grabs selected incorrect hands")
	if str(left.grab_target_ski) != "LEFT" or str(right.grab_target_ski) != "RIGHT":
		failures.append("Mirrored safety grabs selected incorrect skis")
	var left_roll := float((left.chest_rotation as Vector3).z)
	var right_roll := float((right.chest_rotation as Vector3).z)
	if left_roll * right_roll >= 0.0:
		failures.append("Safety Left/Right torso contribution did not mirror")
	var mute_left := _sample_grab(TrickController.GrabPose.MUTE_LEFT)
	var mute_right := _sample_grab(TrickController.GrabPose.MUTE_RIGHT)
	if str(mute_left.grab_hand) != "LEFT" or str(mute_left.grab_target_ski) != "RIGHT":
		failures.append("Mute Left did not use the left hand on the opposite ski")
	if str(mute_right.grab_hand) != "RIGHT" or str(mute_right.grab_target_ski) != "LEFT":
		failures.append("Mute Right did not use the right hand on the opposite ski")

func _test_supported_definition_coverage() -> void:
	for pose: int in SKI_GRABS:
		var snapshot := _sample_grab(pose)
		print("GRAB_SUPPORTED pose=%d hand=%s ski=%s targets=%d reach=%.3f contact=%.2f" % [
			pose, snapshot.get("grab_hand", "NONE"), snapshot.get("grab_target_ski", "NONE"),
			snapshot.get("grab_target_count", 0), snapshot.get("grab_reach_error", 0.0), snapshot.get("grab_contact_weight", 0.0),
		])
		if int(snapshot.get("grab_target_count", 0)) <= 0:
			failures.append("Supported ski grab %d has no stable target definition" % pose)
		if float(snapshot.get("grab_pose_weight", 0.0)) < 0.5:
			failures.append("Supported ski grab %d did not build pose weight" % pose)
		if float(snapshot.get("grab_contact_weight", 0.0)) < 0.35:
			failures.append("Supported ski grab %d never reached stable visual contact" % pose)
	for pose: int in range(TrickController.StylePose.SPREAD_EAGLE, TrickController.StylePose.SHIFTY_RIGHT + 1):
		var style := _sample_style(pose)
		if int(style.get("grab_target_count", -1)) != 0:
			failures.append("Style pose %d incorrectly invented a hand-to-ski target" % pose)
		if float(style.get("style_pose_weight", 0.0)) < 0.5:
			failures.append("Style pose %d did not build pose weight" % pose)

func _test_leg_and_body_lead_hand_contact() -> void:
	var baseline_rig := _new_rig()
	var baseline_frame := _air_frame()
	_step(baseline_rig, baseline_frame, 6)
	var baseline := baseline_rig.debug_snapshot()
	var rig := _new_rig()
	var frame := _grab_frame(TrickController.GrabPose.SAFETY_LEFT)
	_step(rig, frame, 6)
	var early := rig.debug_snapshot()
	var knee_change := absf(float((early.left_knee_rotation as Vector3).x) - float((baseline.left_knee_rotation as Vector3).x))
	var shoulder_change := (early.left_shoulder_rotation as Vector3).distance_to(baseline.left_shoulder_rotation as Vector3)
	if knee_change < 0.16:
		failures.append("Grab target leg did not move before the reach")
	if shoulder_change >= knee_change:
		failures.append("Grab arm led the target knee instead of finishing the body-led reach")
	if float(early.get("grab_contact_weight", 0.0)) > 0.12:
		failures.append("Grab hand contacted the ski before the body committed")
	_dispose_rig(baseline_rig)
	_dispose_rig(rig)

func _test_spin_grab_layering() -> void:
	for spin_rate: float in [-4.2, 4.2, 6.4]:
		var rig := _new_rig()
		var frame := _grab_frame(TrickController.GrabPose.SAFETY_LEFT)
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.SPIN_LEFT if spin_rate < 0.0 else TrickCommand.Kind.SPIN_RIGHT
		frame.angular_velocity.y = spin_rate
		frame.rotation_accumulated.y = signf(spin_rate) * TAU
		_step(rig, frame, 100)
		var snapshot := rig.debug_snapshot()
		if float(snapshot.get("trick_pose_weight", 0.0)) < 0.35:
			failures.append("Grab suppressed Phase 8 during %.1f rad/s spin" % spin_rate)
		if float(snapshot.get("grab_pose_weight", 0.0)) < 0.45:
			failures.append("Spin suppressed the active grab at %.1f rad/s" % spin_rate)
		if absf(float((snapshot.left_knee_rotation as Vector3).x)) > 2.32:
			failures.append("Spin and grab compactness double-stacked beyond knee limits")
		if absf(float((snapshot.head_rotation as Vector3).y)) > rig.profile.trick_head_yaw_limit + 0.08:
			failures.append("Grab overrode bounded Phase 8 head spotting")
		_assert_root_unchanged(rig, "Spin plus grab")
		_dispose_rig(rig)

func _test_release_and_landing_handoff() -> void:
	var rig := _new_rig()
	var frame := _grab_frame(TrickController.GrabPose.SAFETY_LEFT)
	frame.grab_hold_time = 0.8
	_step(rig, frame, 90)
	var held := rig.debug_snapshot()
	frame.grab_pose = TrickController.GrabPose.NONE
	frame.grab_amount = 0.0
	frame.grab_input_strength = 0.0
	frame.grab_release_time = 0.22
	frame.trick_phase = TrickCommand.PresentationPhase.OPEN
	_step(rig, frame, 16)
	var released := rig.debug_snapshot()
	if str(released.get("grab_phase", "")) not in ["RELEASE", "RECOVER"]:
		failures.append("Grab input release did not enter RELEASE/RECOVER")
	if float(released.get("grab_pose_weight", 0.0)) <= 0.02:
		failures.append("Grab hand snapped immediately to neutral on release")
	if float(released.get("grab_pose_weight", 0.0)) >= float(held.get("grab_pose_weight", 0.0)):
		failures.append("Released grab did not begin unwinding")
	frame.predicted_landing_time = 0.08
	frame.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, frame, 55)
	var landing := rig.debug_snapshot()
	if float(landing.get("landing_blend", 0.0)) < 0.35:
		failures.append("Phase 6 did not regain priority after grab release")
	if float(landing.get("grab_contact_weight", 0.0)) > 0.15:
		failures.append("Released hand remained visually stuck to the ski")
	_assert_root_unchanged(rig, "Grab landing handoff")
	_dispose_rig(rig)

func _test_short_air_and_late_hold() -> void:
	var rig := _new_rig()
	var short_air := _grab_frame(TrickController.GrabPose.SAFETY_RIGHT)
	short_air.air_time = 0.03
	short_air.predicted_landing_time = 0.08
	_step(rig, short_air, 12)
	var short_snapshot := rig.debug_snapshot()
	if float(short_snapshot.get("grab_contact_weight", 0.0)) > 0.35:
		failures.append("Tiny air completed an implausibly immediate grab contact")
	var late := _grab_frame(TrickController.GrabPose.SAFETY_RIGHT)
	late.air_time = 0.7
	late.predicted_landing_time = 0.04
	late.trick_phase = TrickCommand.PresentationPhase.LANDING
	_step(rig, late, 55)
	var late_snapshot := rig.debug_snapshot()
	if float(late_snapshot.get("grab_pose_weight", 0.0)) < 0.12:
		failures.append("Late held grab was silently cancelled into a perfect landing pose")
	if float(late_snapshot.get("landing_blend", 0.0)) < 0.4:
		failures.append("Late held grab prevented Phase 6 landing preparation")
	_dispose_rig(rig)

func _test_target_tracks_ski() -> void:
	var rig := _new_rig()
	var frame := _grab_frame(TrickController.GrabPose.TAIL)
	_step(rig, frame, 60)
	var before := rig.debug_snapshot()
	frame.grab_tweak = Vector2(0.65, 0.0)
	_step(rig, frame, 45)
	var after := rig.debug_snapshot()
	var before_target := before.get("grab_target_left", Vector3.ZERO) as Vector3
	var after_target := after.get("grab_target_left", Vector3.ZERO) as Vector3
	if before_target.distance_to(after_target) < 0.01:
		failures.append("Grab target did not move with the animated ski transform")
	_dispose_rig(rig)

func _test_released_grab_scoring_regression() -> void:
	var tricks := TrickController.new()
	add_child(tricks)
	var landed_name := [""]
	var landed_points := [0]
	tricks.trick_landed.connect(func(name: String, points: int, _quality: float) -> void:
		landed_name[0] = name
		landed_points[0] = points
	)
	tricks.begin_air(false, TrickCommand.Kind.SPIN_LEFT)
	var command := TrickCommand.new()
	command.kind = TrickCommand.Kind.SPIN_LEFT
	command.committed = true
	tricks.update_air(Vector3(0.0, -TAU, 0.0), 1.0, command)
	command.reset()
	command.phase = TrickCommand.PresentationPhase.GRAB
	command.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	command.grab_amount = 1.0
	tricks.update_air(Vector3.ZERO, 0.65, command)
	command.reset()
	tricks.update_air(Vector3.ZERO, 0.2, command)
	if "Safety Grab Left" not in tricks.current_name():
		failures.append("Animation-time grab release erased gameplay trick history")
	tricks.land(1.0, false)
	if "Safety Grab Left" not in landed_name[0] or landed_points[0] <= 870:
		failures.append("Released grab was not preserved for landing name/score")
	remove_child(tricks)
	tricks.queue_free()

func _sample_grab(pose: int) -> Dictionary:
	var rig := _new_rig()
	var frame := _grab_frame(pose)
	_step(rig, frame, 110)
	var snapshot := rig.debug_snapshot()
	_assert_root_unchanged(rig, "Grab pose %d" % pose)
	_dispose_rig(rig)
	return snapshot

func _sample_style(pose: int) -> Dictionary:
	var rig := _new_rig()
	var frame := _air_frame()
	frame.style_pose = pose
	frame.style_amount = 1.0
	_step(rig, frame, 110)
	var snapshot := rig.debug_snapshot()
	_assert_root_unchanged(rig, "Style pose %d" % pose)
	_dispose_rig(rig)
	return snapshot

func _grab_frame(pose: int) -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.grab_pose = pose
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.6
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	return frame

func _air_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.8
	frame.takeoff_upward_speed = 4.2
	frame.air_time = 0.35
	frame.air_upward_velocity = 0.2
	frame.speed_mps = 15.0
	frame.speed_ratio = 0.62
	frame.skier_heading = Vector3.FORWARD
	frame.velocity_heading = Vector3.FORWARD
	return frame

func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = 12.0
	frame.speed_ratio = 0.5
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
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
		failures.append("%s changed the animation root" % context)

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int) -> void:
	var previous := rig.debug_snapshot()
	for _index: int in count:
		rig.apply_frame(frame, STEP)
		var current := rig.debug_snapshot()
		maximum_shoulder_delta = maxf(maximum_shoulder_delta, (current.left_shoulder_rotation as Vector3).distance_to(previous.left_shoulder_rotation as Vector3))
		maximum_knee_delta = maxf(maximum_knee_delta, (current.left_knee_rotation as Vector3).distance_to(previous.left_knee_rotation as Vector3))
		maximum_pelvis_delta = maxf(maximum_pelvis_delta, (current.pelvis_position as Vector3).distance_to(previous.pelvis_position as Vector3))
		maximum_ski_delta = maxf(maximum_ski_delta, (current.left_ski_rotation as Vector3).distance_to(previous.left_ski_rotation as Vector3))
		previous = current
