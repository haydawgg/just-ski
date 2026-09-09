extends Node

const STEP := 1.0 / 60.0

var failures: Array[String] = []

func _ready() -> void:
	_test_landing_readiness_retains_combined_trick()
	_test_crash_context_has_recovery_stage()
	_test_authored_pose_handoffs_blend()
	_test_combined_trick_preserves_boot_binding()
	_test_full_trick_rail_bail_recovery_sequence()
	_test_contact_targets_drive_valid_two_bone_ik()
	_test_rail_slip_preserves_bounded_angular_state()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ANIMATION_TRANSITION_REGRESSION_PASS: trick, authored pose handoffs, rail phases, angular handoff, atomic bail cleanup, recovery, rigid bindings, and ski-constrained leg IK passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ANIMATION_TRANSITION_REGRESSION_FAIL: " + failure)
	get_tree().quit(1)

func _test_landing_readiness_retains_combined_trick() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = 16.0
	frame.speed_ratio = 0.7
	frame.air_time = 0.55
	frame.air_upward_velocity = -2.8
	frame.vertical_velocity = -2.8
	frame.predicted_landing_valid = true
	frame.predicted_landing_time = 0.5
	frame.predicted_landing_normal = Vector3.UP
	frame.skier_heading = Vector3.FORWARD
	frame.velocity_heading = Vector3.FORWARD
	frame.body_up = Vector3.UP
	frame.ski_forward = Vector3.FORWARD
	frame.ski_up = Vector3.UP
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.BACKFLIP
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(3.8, 5.2, 0.0)
	frame.rotation_axis_weights = Vector3(0.45, 0.55, 0.0)
	for index: int in 42:
		frame.rotation_accumulated += frame.angular_velocity * STEP
		frame.predicted_landing_time = lerpf(0.5, 0.08, float(index + 1) / 42.0)
		# Reproduce the gameplay seam that used to force LANDING while the
		# combined rotation was still materially active.
		if frame.predicted_landing_time < 0.24:
			frame.trick_phase = TrickCommand.PresentationPhase.LANDING
		rig.apply_frame(frame, STEP)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.trick_pose_weight) < 0.62:
		failures.append("landing readiness erased the active combined trick before contact (weight %.3f)" % float(snapshot.trick_pose_weight))
	if str(snapshot.spin_visual_phase) == "IDLE":
		failures.append("combined trick became visually idle before contact")
	remove_child(rig)
	rig.queue_free()

func _test_crash_context_has_recovery_stage() -> void:
	if not CrashContext.Stage.keys().has("RECOVERY"):
		failures.append("crash lifecycle has no explicit RECOVERY presentation stage")

func _test_authored_pose_handoffs_blend() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = 16.0
	frame.speed_ratio = 0.7
	frame.air_time = 0.55
	frame.air_upward_velocity = -1.5
	frame.vertical_velocity = -1.5
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	frame.grab_pose = TrickController.GrabPose.MUTE_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	_advance(rig, frame, 60)
	frame.grab_pose = TrickController.GrabPose.JAPAN_LEFT
	rig.apply_frame(frame, STEP)
	var grab_transition := rig.debug_snapshot()
	if float(grab_transition.get("grab_definition_blend", 1.0)) >= 0.99:
		failures.append("grab definition changed without a crossfade")
	if int(grab_transition.get("grab_previous_pose", TrickController.GrabPose.NONE)) != TrickController.GrabPose.MUTE_LEFT:
		failures.append("grab handoff did not retain the outgoing authored pose")
	_advance(rig, frame, 30)
	if float(rig.debug_snapshot().get("grab_definition_blend", 0.0)) <= float(grab_transition.get("grab_definition_blend", 0.0)):
		failures.append("grab definition handoff did not progress")

	frame.grab_pose = TrickController.GrabPose.NONE
	frame.grab_amount = 0.0
	frame.grab_input_strength = 0.0
	frame.style_pose = TrickController.StylePose.SPREAD_EAGLE
	frame.style_amount = 1.0
	_advance(rig, frame, 60)
	frame.style_pose = TrickController.StylePose.DAFFY
	rig.apply_frame(frame, STEP)
	var style_transition := rig.debug_snapshot()
	if float(style_transition.get("style_definition_blend", 1.0)) >= 0.99:
		failures.append("style definition changed without a crossfade")
	if int(style_transition.get("style_previous_pose", TrickController.StylePose.NONE)) != TrickController.StylePose.SPREAD_EAGLE:
		failures.append("style handoff did not retain the outgoing authored pose")
	remove_child(rig)
	rig.queue_free()

func _test_combined_trick_preserves_boot_binding() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.speed_mps = 15.0
	frame.air_time = 0.6
	frame.air_upward_velocity = -1.0
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.BACKFLIP
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(4.2, -5.4, 0.5)
	frame.rotation_axis_weights = Vector3(0.45, 0.5, 0.05)
	for _index: int in 60:
		frame.rotation_accumulated += frame.angular_velocity * STEP
		rig.apply_frame(frame, STEP)
	var attachment := rig.equipment_attachment_snapshot()
	var left_error := float(attachment.get("left_boot_binding_angular_error", 999.0))
	var right_error := float(attachment.get("right_boot_binding_angular_error", 999.0))
	if maxf(left_error, right_error) > deg_to_rad(3.0):
		failures.append("combined trick broke rigid boot/ski binding (errors %.3f, %.3f rad)" % [left_error, right_error])
	remove_child(rig)
	rig.queue_free()

func _test_full_trick_rail_bail_recovery_sequence() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = 14.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_ski_target_world = rig.left_ski.global_transform
	frame.right_ski_target_world = rig.right_ski.global_transform
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	_advance(rig, frame, 24)

	frame.locomotion_state = 1
	frame.grounded = false
	frame.left_ski_target_valid = false
	frame.right_ski_target_valid = false
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.BACKFLIP
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(3.9, 5.0, 0.4)
	for index: int in 36:
		frame.rotation_accumulated += frame.angular_velocity * STEP
		frame.predicted_landing_valid = true
		frame.predicted_landing_time = lerpf(0.48, 0.08, float(index + 1) / 36.0)
		if frame.predicted_landing_time < 0.22:
			frame.trick_phase = TrickCommand.PresentationPhase.LANDING
		rig.apply_frame(frame, STEP)

	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, 0.7, 0.5)
	frame.locomotion_state = 2
	frame.trick_active = false
	frame.trick_intent = false
	frame.rail_speed = 14.0
	frame.rail_balance = 0.45
	frame.rail_balance_velocity = 1.2
	frame.rail_kink_severity = 0.08
	frame.rail_slope = deg_to_rad(-8.0)
	frame.rail_pose = 0
	frame.left_ski_target_world = rig.left_ski.global_transform
	frame.right_ski_target_world = rig.right_ski.global_transform
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	var rail_phases: Dictionary = {}
	var max_transition_delta := 0.0
	var previous_pelvis := rig.debug_snapshot().pelvis_rotation as Vector3
	for _index: int in 90:
		rig.apply_frame(frame, STEP)
		var rail_snapshot := rig.debug_snapshot()
		rail_phases[str(rail_snapshot.rail_phase)] = true
		max_transition_delta = maxf(max_transition_delta, _euler_delta(rail_snapshot.pelvis_rotation as Vector3, previous_pelvis))
		previous_pelvis = rail_snapshot.pelvis_rotation
	for expected: String in ["CONTACT", "COMPRESSION", "GRIND"]:
		if not rail_phases.has(expected):
			failures.append("combined sequence never exposed rail %s phase" % expected)
	var grind_snapshot := rig.debug_snapshot()
	if float(grind_snapshot.leg_ik_weight) < 0.75:
		failures.append("rail contact did not acquire high leg IK weight")

	rig.trigger(SkierAnimationController.AnimationEvent.BAIL, 1.0, 1.0)
	frame.locomotion_state = 3
	frame.left_ski_target_valid = false
	frame.right_ski_target_valid = false
	frame.rail_balance = 0.0
	frame.rail_balance_velocity = 0.0
	frame.crash_incoming_velocity = Vector3(2.0, -5.0, -12.0)
	frame.crash_current_velocity = Vector3(1.4, -1.0, -8.0)
	frame.crash_impact_speed = 6.0
	frame.crash_angular_speed = 4.0
	frame.crash_lateral_bias = 1.0
	var stages := [
		[CrashContext.Stage.RELEASE, 12],
		[CrashContext.Stage.IMPACT, 14],
		[CrashContext.Stage.FALL, 36],
		[CrashContext.Stage.REST, 22],
	]
	var fall_motion := 0.0
	var previous_fall_pose := rig.debug_snapshot().pelvis_rotation as Vector3
	var bail_entry_snapshot: Dictionary = {}
	for stage_data: Array in stages:
		frame.crash_stage = int(stage_data[0])
		frame.crash_stage_elapsed = 0.0
		var stage_frames := int(stage_data[1])
		for index: int in stage_frames:
			frame.crash_elapsed += STEP
			frame.crash_stage_elapsed += STEP
			frame.crash_stage_progress = float(index + 1) / float(stage_frames)
			rig.apply_frame(frame, STEP)
			if frame.crash_stage == CrashContext.Stage.RELEASE and index == 0:
				bail_entry_snapshot = rig.debug_snapshot()
			if frame.crash_stage == CrashContext.Stage.FALL:
				var current_fall_pose := rig.debug_snapshot().pelvis_rotation as Vector3
				fall_motion += _euler_delta(current_fall_pose, previous_fall_pose)
				previous_fall_pose = current_fall_pose
	if fall_motion < 0.08:
		failures.append("moving bail presentation remained visually static")
	if float(bail_entry_snapshot.get("rail_influence", 1.0)) > 0.02:
		failures.append("rail presentation ownership survived bail entry")
	if str(bail_entry_snapshot.get("pose_owner", "")) != "BAIL_BOOT":
		failures.append("bail did not atomically acquire presentation ownership")

	frame.crash_stage = CrashContext.Stage.RECOVERY
	frame.crash_stage_elapsed = 0.0
	frame.left_ski_target_world = rig.left_ski.global_transform
	frame.right_ski_target_world = rig.right_ski.global_transform
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	var recovery_weight_start := float(rig.debug_snapshot().leg_ik_weight)
	for index: int in 48:
		frame.crash_elapsed += STEP
		frame.crash_stage_elapsed += STEP
		frame.crash_stage_progress = float(index + 1) / 48.0
		rig.apply_frame(frame, STEP)
	var recovered := rig.debug_snapshot()
	if str(recovered.pose_owner) != "RECOVERY_CONTACT":
		failures.append("recovery did not own the contact reacquisition handoff")
	if float(recovered.leg_ik_weight) <= recovery_weight_start + 0.45:
		failures.append("recovery did not progressively reacquire leg IK")
	if max_transition_delta > 0.35:
		failures.append("air/rail transition exceeded the pelvis continuity bound (%.3f rad)" % max_transition_delta)
	var attachment := rig.equipment_attachment_snapshot()
	if maxf(float(attachment.left_boot_binding_angular_error), float(attachment.right_boot_binding_angular_error)) > deg_to_rad(3.0):
		failures.append("full transition sequence lost rigid boot/ski binding")

	frame.locomotion_state = 0
	frame.crash_stage = CrashContext.Stage.NONE
	frame.grounded = true
	_advance(rig, frame, 24)
	if str(rig.debug_snapshot().state) != "GROUND":
		failures.append("combined sequence did not finish in ground presentation")
	remove_child(rig)
	rig.queue_free()

func _advance(rig: SkierAnimationController, frame: SkierAnimationFrame, frames: int) -> void:
	for _index: int in frames:
		rig.apply_frame(frame, STEP)

func _test_contact_targets_drive_valid_two_bone_ik() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	var slope := Basis(Vector3.RIGHT, deg_to_rad(9.0))
	frame.left_ski_target_world = Transform3D(slope * rig.left_ski.global_basis, rig.left_ski.global_position + Vector3(0.0, -0.055, 0.035))
	frame.right_ski_target_world = Transform3D(slope * rig.right_ski.global_basis, rig.right_ski.global_position + Vector3(0.0, 0.035, -0.025))
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	_advance(rig, frame, 90)
	var snapshot := rig.debug_snapshot()
	if float(snapshot.leg_ik_weight) < 0.9:
		failures.append("ground contact did not acquire full two-bone IK")
	if maxf(float(snapshot.left_leg_reach_ratio), float(snapshot.right_leg_reach_ratio)) > 1.03:
		failures.append("two-bone IK exceeded configured limb reach")
	if maxf(float(snapshot.left_boot_target_position_error), float(snapshot.right_boot_target_position_error)) > 0.1:
		failures.append("two-bone IK did not converge boots onto ski binding targets")
	if not is_finite(float(snapshot.left_knee_constraint_correction)) or not is_finite(float(snapshot.right_knee_constraint_correction)):
		failures.append("two-bone IK produced non-finite knee correction")
	var left_local := rig.pelvis.to_local(rig.left_boot.global_position)
	var right_local := rig.pelvis.to_local(rig.right_boot.global_position)
	if left_local.x >= right_local.x:
		failures.append("two-bone IK crossed the leg chains")
	remove_child(rig)
	rig.queue_free()

func _test_rail_slip_preserves_bounded_angular_state() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	var rail := GrindRail3D.new()
	rail.path = Curve3D.new()
	rail.path.add_point(Vector3.ZERO)
	rail.path.add_point(Vector3(0.0, 0.5, -12.0))
	add_child(rail)
	skier.state = SkierController.State.GRIND
	skier.active_rail = rail
	skier.rail_offset = minf(rail.path_length * 0.5, 4.0)
	skier.rail_direction = 1.0
	skier.rail_speed = 13.0
	skier.rail_balance = 0.82
	skier.rail_balance_velocity = -4.5
	skier.angular_velocity = Vector3(0.35, 0.6, -0.2)
	skier.trick.begin_air(false, TrickCommand.Kind.BACKFLIP, true, Vector3.RIGHT)
	skier.trick.accumulated_rotation = Vector3(1.1, -0.7, 0.2)
	skier.active_trick_kind = TrickCommand.Kind.BACKFLIP
	skier._slip_off_rail()
	if skier.state != SkierController.State.AIR or skier.active_rail != null:
		failures.append("rail slip did not atomically release rail gameplay ownership")
	if skier.angular_velocity.length() < 0.5 or skier.angular_velocity.length() > skier.profile.maximum_angular_speed + 0.001:
		failures.append("rail slip discarded or failed to bound inherited angular state")
	if skier.trick.accumulated_rotation.length() > 0.001 or skier.trick.had_trick_intent:
		failures.append("rail slip retained inbound trick rotation for post-rail scoring")
	remove_child(rail)
	rail.queue_free()
	remove_child(skier)
	skier.queue_free()

func _euler_delta(current: Vector3, previous: Vector3) -> float:
	return Vector3(
		absf(wrapf(current.x - previous.x, -PI, PI)),
		absf(wrapf(current.y - previous.y, -PI, PI)),
		absf(wrapf(current.z - previous.z, -PI, PI))
	).length()
