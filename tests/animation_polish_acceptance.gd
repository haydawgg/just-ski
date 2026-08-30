extends Node

const RATES: Array[float] = [30.0, 60.0, 120.0]

var failures: Array[String] = []

func _ready() -> void:
	var results: Array[Dictionary] = []
	for hz: float in RATES:
		results.append(_run_full_sequence(hz))
	_check_rate_independence(results)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ANIMATION_POLISH_PASS: 30/60/120 Hz inertia, connected-body hierarchy, transitions, grab constraints, and uninterrupted full run passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ANIMATION_POLISH_FAIL: " + failure)
	get_tree().quit(1)

func _run_full_sequence(hz: float) -> Dictionary:
	var delta := 1.0 / hz
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _ground_frame()
	var stats := _new_stats()

	_advance(rig, frame, 0.4, delta, "STRAIGHT", stats)
	_set_carve(frame, -1.0)
	_advance(rig, frame, 0.65, delta, "CARVE_LEFT", stats)
	_set_carve(frame, 1.0)
	_advance(rig, frame, 0.65, delta, "CROSSOVER_RIGHT", stats)
	frame.left_ground_distance = frame.seat_distance - 0.12
	frame.right_ground_distance = frame.seat_distance + 0.08
	frame.left_normal = Vector3(-0.08, 0.99, 0.05).normalized()
	frame.right_normal = Vector3(0.1, 0.99, -0.04).normalized()
	_advance(rig, frame, 0.35, delta, "UNEVEN_TERRAIN", stats)
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	frame.left_normal = Vector3.UP
	frame.right_normal = Vector3.UP

	frame.compression = 1.0
	_advance(rig, frame, 0.18, delta, "POP_LOAD", stats)
	rig.trigger(SkierAnimationController.AnimationEvent.POP, 1.0)
	_set_air(frame)
	_advance_air(rig, frame, 0.34, delta, "TAKEOFF", stats, 4.2, -1.0)

	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.SPIN_LEFT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(0.0, -6.2, 0.0)
	_advance_air(rig, frame, 0.98, delta, "SPIN_360", stats, 0.2, -1.0)

	frame.grab_pose = TrickController.GrabPose.MUTE_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.7
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	_advance_air(rig, frame, 0.55, delta, "GRAB_HOLD", stats, -0.4, -1.0)
	if float(stats.get("maximum_grab_contact", 0.0)) < 0.7:
		failures.append("%.0f Hz full run never established stable grab contact" % hz)

	frame.grab_pose = TrickController.GrabPose.NONE
	frame.grab_amount = 0.0
	frame.grab_input_strength = 0.0
	frame.grab_release_time = 0.22
	frame.trick_phase = TrickCommand.PresentationPhase.LANDING
	frame.angular_velocity = Vector3(0.0, -1.2, 0.0)
	_advance_air(rig, frame, 0.28, delta, "GRAB_RELEASE", stats, -2.6, 0.18)

	_set_ground(frame)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.85
	frame.landing_balance_error = 0.35
	frame.landing_lateral_velocity = 2.0
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_HARD, 0.85, 1.0)
	_advance(rig, frame, 0.12, delta, "LANDING_IMPACT", stats)
	frame.landing_event_active = false
	_advance(rig, frame, 0.42, delta, "LANDING_RECOVERY", stats)

	_set_air(frame)
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF
	frame.takeoff_upward_speed = 1.6
	_advance_air(rig, frame, 0.2, delta, "RAIL_APPROACH", stats, -0.3, -1.0)
	frame.locomotion_state = 2
	frame.rail_speed = 15.0
	frame.rail_balance = -0.65
	frame.rail_pose = 1
	frame.rail_distance_to_end = 3.0
	frame.rail_entry_severity = 0.55
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, 0.55, -1.0)
	_advance(rig, frame, 0.5, delta, "RAIL_SLIDE", stats)

	frame.locomotion_state = 1
	frame.rail_speed = 0.0
	frame.rail_balance = 0.0
	frame.rail_pose = 0
	frame.rail_distance_to_end = 999.0
	frame.rail_entry_severity = 0.0
	frame.air_time = 0.0
	frame.takeoff_upward_speed = 1.8
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, 0.7, -1.0)
	_advance_air(rig, frame, 0.28, delta, "RAIL_EXIT", stats, -1.4, 0.14)

	_set_ground(frame)
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.25, 0.0)
	_advance(rig, frame, 0.3, delta, "SECOND_LANDING", stats)
	frame.landing_event_active = false

	_set_air(frame)
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(0.8, 5.8, 1.1)
	frame.pre_bail_weight = 0.88
	frame.pre_bail_side = 1.0
	_advance_air(rig, frame, 0.34, delta, "FAILED_TRICK_WARNING", stats, -3.2, 0.12)

	frame.locomotion_state = 3
	frame.trick_active = false
	frame.trick_intent = false
	frame.grab_pose = TrickController.GrabPose.NONE
	frame.grab_amount = 0.0
	frame.pre_bail_weight = 0.0
	frame.crash_reason = CrashContext.Reason.LANDING_ANGULAR
	frame.crash_incoming_velocity = Vector3(2.0, -6.0, -14.0)
	frame.crash_current_velocity = Vector3(1.8, -3.5, -11.0)
	frame.crash_impact_normal = Vector3.UP
	frame.crash_impact_speed = 6.0
	frame.crash_lateral_bias = 1.0
	frame.crash_angular_speed = 6.0
	rig.trigger(SkierAnimationController.AnimationEvent.BAIL, 1.0, 1.0)
	frame.crash_stage = CrashContext.Stage.RELEASE
	frame.crash_elapsed = 0.08
	_advance(rig, frame, 0.18, delta, "CRASH_RELEASE", stats)
	frame.crash_stage = CrashContext.Stage.IMPACT
	frame.crash_elapsed = 0.28
	_advance(rig, frame, 0.22, delta, "CRASH_IMPACT", stats)
	frame.crash_stage = CrashContext.Stage.FALL
	frame.crash_elapsed = 0.72
	_advance(rig, frame, 0.48, delta, "CRASH_FALL", stats)
	frame.crash_stage = CrashContext.Stage.REST
	frame.crash_rest_detected = true
	frame.crash_elapsed = 1.3
	_advance(rig, frame, 0.38, delta, "CRASH_REST", stats)

	rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
	frame.reset()
	_set_ground(frame)
	frame.speed_mps = 14.0
	frame.speed_ratio = 0.62
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.edge = 0.0
	frame.turn_input = 0.0
	frame.turn_rate = 0.0
	frame.lateral_acceleration = 0.0
	_advance(rig, frame, 0.65, delta, "RESPAWN_SKI_AWAY", stats)

	var final_snapshot := rig.debug_snapshot()
	stats["final_pelvis_rotation"] = final_snapshot.pelvis_rotation
	stats["final_chest_rotation"] = final_snapshot.chest_rotation
	stats["final_left_pole_rotation"] = final_snapshot.left_pole_rotation
	stats["final_secondary_weight"] = float(final_snapshot.get("secondary_motion_weight", 0.0))
	stats["final_pole_lag"] = maxf(
		(final_snapshot.get("left_pole_inertia", Vector3.ZERO) as Vector3).length(),
		(final_snapshot.get("right_pole_inertia", Vector3.ZERO) as Vector3).length()
	)
	stats["hz"] = hz
	print("ANIMATION_POLISH_RATE hz=%.0f torso=%.3f arm=%.3f pole=%.3f secondary=%.3f grab_pose=%.3f grab_contact=%.3f grab_error=%.3f pelvis_delta=%.3f chest_delta=%.3f pole_delta=%.3f" % [
		hz,
		stats.peak_torso_lag,
		stats.peak_arm_lag,
		stats.peak_pole_lag,
		stats.peak_secondary_weight,
		stats.maximum_grab_pose,
		stats.maximum_grab_contact,
		stats.minimum_grab_error,
		stats.maximum_pelvis_delta,
		stats.maximum_chest_delta,
		stats.maximum_pole_delta,
	])
	_check_run_metrics(stats)
	remove_child(rig)
	rig.free()
	return stats

func _new_stats() -> Dictionary:
	return {
		"previous_pelvis_position": Vector3.ZERO,
		"previous_pelvis_rotation": Vector3.ZERO,
		"previous_chest_rotation": Vector3.ZERO,
		"previous_head_rotation": Vector3.ZERO,
		"previous_left_knee_rotation": Vector3.ZERO,
		"previous_left_shoulder_rotation": Vector3.ZERO,
		"previous_left_pole_rotation": Vector3.ZERO,
		"initialized": false,
		"maximum_pelvis_delta": 0.0,
		"maximum_chest_delta": 0.0,
		"maximum_head_delta": 0.0,
		"maximum_knee_delta": 0.0,
		"maximum_shoulder_delta": 0.0,
		"maximum_pole_delta": 0.0,
		"peak_torso_lag": 0.0,
		"peak_arm_lag": 0.0,
		"peak_pole_lag": 0.0,
		"peak_secondary_weight": 0.0,
		"peak_lateral_accel": 0.0,
		"peak_vertical_accel": 0.0,
		"peak_yaw_accel": 0.0,
		"maximum_grab_contact": 0.0,
		"maximum_grab_pose": 0.0,
		"minimum_grab_error": 999.0,
		"seen_ground": false,
		"seen_air": false,
		"seen_grind": false,
		"seen_bail": false,
		"seen_crash_release": false,
		"seen_crash_impact": false,
		"seen_crash_fall": false,
		"seen_crash_rest": false,
	}

func _advance(rig: SkierAnimationController, frame: SkierAnimationFrame, duration: float, delta: float, stage: String, stats: Dictionary) -> void:
	var count := maxi(1, int(round(duration / delta)))
	for _index: int in count:
		rig.apply_frame(frame, delta)
		_record(rig, stage, delta, stats)

func _advance_air(rig: SkierAnimationController, frame: SkierAnimationFrame, duration: float, delta: float, stage: String, stats: Dictionary, end_vertical_velocity: float, end_landing_time: float) -> void:
	var count := maxi(1, int(round(duration / delta)))
	var start_vertical := frame.air_upward_velocity
	var start_landing := frame.predicted_landing_time
	for index: int in count:
		var progress := float(index + 1) / float(count)
		frame.air_time += delta
		frame.air_upward_velocity = lerpf(start_vertical, end_vertical_velocity, progress)
		frame.vertical_velocity = frame.air_upward_velocity
		if end_landing_time >= 0.0:
			var landing_start := start_landing if start_landing >= 0.0 else duration
			frame.predicted_landing_time = lerpf(landing_start, end_landing_time, progress)
		else:
			frame.predicted_landing_time = -1.0
		if frame.trick_active:
			frame.rotation_accumulated += frame.angular_velocity * delta
		rig.apply_frame(frame, delta)
		_record(rig, stage, delta, stats)

func _record(rig: SkierAnimationController, stage: String, _delta: float, stats: Dictionary) -> void:
	var snapshot := rig.debug_snapshot()
	stats.seen_ground = bool(stats.seen_ground) or str(snapshot.state) == "GROUND"
	stats.seen_air = bool(stats.seen_air) or str(snapshot.state) == "AIR"
	stats.seen_grind = bool(stats.seen_grind) or str(snapshot.state) == "GRIND"
	stats.seen_bail = bool(stats.seen_bail) or str(snapshot.state) == "BAIL"
	stats.seen_crash_release = bool(stats.seen_crash_release) or str(snapshot.crash_stage) == "Release"
	stats.seen_crash_impact = bool(stats.seen_crash_impact) or str(snapshot.crash_stage) == "Impact"
	stats.seen_crash_fall = bool(stats.seen_crash_fall) or str(snapshot.crash_stage) == "Fall"
	stats.seen_crash_rest = bool(stats.seen_crash_rest) or str(snapshot.crash_stage) == "Rest"
	stats.peak_torso_lag = maxf(float(stats.peak_torso_lag), (snapshot.get("torso_follow_through", Vector3.ZERO) as Vector3).length())
	stats.peak_arm_lag = maxf(float(stats.peak_arm_lag), maxf(
		(snapshot.get("left_arm_inertia", Vector3.ZERO) as Vector3).length(),
		(snapshot.get("right_arm_inertia", Vector3.ZERO) as Vector3).length()
	))
	stats.peak_pole_lag = maxf(float(stats.peak_pole_lag), maxf(
		(snapshot.get("left_pole_inertia", Vector3.ZERO) as Vector3).length(),
		(snapshot.get("right_pole_inertia", Vector3.ZERO) as Vector3).length()
	))
	stats.peak_secondary_weight = maxf(float(stats.peak_secondary_weight), float(snapshot.get("secondary_motion_weight", 0.0)))
	stats.peak_lateral_accel = maxf(float(stats.peak_lateral_accel), absf(float(snapshot.get("lateral_accel_filtered", 0.0))))
	stats.peak_vertical_accel = maxf(float(stats.peak_vertical_accel), absf(float(snapshot.get("vertical_accel_filtered", 0.0))))
	stats.peak_yaw_accel = maxf(float(stats.peak_yaw_accel), absf(float(snapshot.get("yaw_accel_filtered", 0.0))))
	if stage == "GRAB_HOLD":
		stats.maximum_grab_contact = maxf(float(stats.maximum_grab_contact), float(snapshot.get("grab_contact_weight", 0.0)))
		stats.maximum_grab_pose = maxf(float(stats.maximum_grab_pose), float(snapshot.get("grab_pose_weight", 0.0)))
		stats.minimum_grab_error = minf(float(stats.minimum_grab_error), float(snapshot.get("grab_reach_error", 999.0)))
	if not bool(stats.initialized):
		stats.initialized = true
	else:
		stats.maximum_pelvis_delta = maxf(float(stats.maximum_pelvis_delta), (snapshot.pelvis_position as Vector3).distance_to(stats.previous_pelvis_position as Vector3))
		stats.maximum_chest_delta = maxf(float(stats.maximum_chest_delta), _euler_delta(snapshot.chest_rotation as Vector3, stats.previous_chest_rotation as Vector3))
		stats.maximum_head_delta = maxf(float(stats.maximum_head_delta), _euler_delta(snapshot.head_rotation as Vector3, stats.previous_head_rotation as Vector3))
		stats.maximum_knee_delta = maxf(float(stats.maximum_knee_delta), _euler_delta(snapshot.left_knee_rotation as Vector3, stats.previous_left_knee_rotation as Vector3))
		stats.maximum_shoulder_delta = maxf(float(stats.maximum_shoulder_delta), _euler_delta(snapshot.left_shoulder_rotation as Vector3, stats.previous_left_shoulder_rotation as Vector3))
		stats.maximum_pole_delta = maxf(float(stats.maximum_pole_delta), _euler_delta(snapshot.left_pole_rotation as Vector3, stats.previous_left_pole_rotation as Vector3))
	stats.previous_pelvis_position = snapshot.pelvis_position
	stats.previous_pelvis_rotation = snapshot.pelvis_rotation
	stats.previous_chest_rotation = snapshot.chest_rotation
	stats.previous_head_rotation = snapshot.head_rotation
	stats.previous_left_knee_rotation = snapshot.left_knee_rotation
	stats.previous_left_shoulder_rotation = snapshot.left_shoulder_rotation
	stats.previous_left_pole_rotation = snapshot.left_pole_rotation
	if not _finite_vector(snapshot.pelvis_rotation as Vector3) or not _finite_vector(snapshot.chest_rotation as Vector3) or not _finite_vector(snapshot.left_pole_rotation as Vector3):
		failures.append("Full run produced a non-finite joint transform during %s" % stage)

func _check_run_metrics(stats: Dictionary) -> void:
	var hz := float(stats.hz)
	if not bool(stats.seen_ground) or not bool(stats.seen_air) or not bool(stats.seen_grind) or not bool(stats.seen_bail):
		failures.append("%.0f Hz full run did not traverse ground, air, grind, and crash" % hz)
	if not bool(stats.seen_crash_release) or not bool(stats.seen_crash_impact) or not bool(stats.seen_crash_fall) or not bool(stats.seen_crash_rest):
		failures.append("%.0f Hz full run did not traverse every controlled-fall stage" % hz)
	if float(stats.peak_torso_lag) < 0.008 or float(stats.peak_torso_lag) > 0.3:
		failures.append("%.0f Hz torso follow-through was absent or excessive (%.3f)" % [hz, stats.peak_torso_lag])
	if float(stats.peak_arm_lag) < 0.008 or float(stats.peak_arm_lag) > 0.38:
		failures.append("%.0f Hz arm inertia was absent or excessive (%.3f)" % [hz, stats.peak_arm_lag])
	if float(stats.peak_pole_lag) < 0.015 or float(stats.peak_pole_lag) > 0.75:
		failures.append("%.0f Hz pole inertia was absent or uncontrolled (%.3f)" % [hz, stats.peak_pole_lag])
	if float(stats.peak_secondary_weight) < 0.12 or float(stats.peak_secondary_weight) > 1.01:
		failures.append("%.0f Hz secondary-motion weight was invalid (%.3f)" % [hz, stats.peak_secondary_weight])
	if float(stats.peak_lateral_accel) > 14.1 or float(stats.peak_vertical_accel) > 24.1 or float(stats.peak_yaw_accel) > 28.1:
		failures.append("%.0f Hz filtered inertial signal exceeded its safety clamp" % hz)
	var frame_scale := 120.0 / hz
	if float(stats.maximum_pelvis_delta) > 0.11 * frame_scale:
		failures.append("%.0f Hz pelvis snapped during full run (%.3f)" % [hz, stats.maximum_pelvis_delta])
	if float(stats.maximum_chest_delta) > 0.5 * frame_scale:
		failures.append("%.0f Hz chest snapped during full run (%.3f)" % [hz, stats.maximum_chest_delta])
	if float(stats.maximum_head_delta) > 0.45 * frame_scale:
		failures.append("%.0f Hz head snapped during full run (%.3f)" % [hz, stats.maximum_head_delta])
	if float(stats.maximum_knee_delta) > 0.75 * frame_scale:
		failures.append("%.0f Hz knee snapped during full run (%.3f)" % [hz, stats.maximum_knee_delta])
	if float(stats.maximum_shoulder_delta) > 0.65 * frame_scale:
		failures.append("%.0f Hz shoulder snapped during full run (%.3f)" % [hz, stats.maximum_shoulder_delta])
	if float(stats.maximum_pole_delta) > 0.85 * frame_scale:
		failures.append("%.0f Hz pole snapped during full run (%.3f)" % [hz, stats.maximum_pole_delta])
	if float(stats.final_pole_lag) > 0.08:
		failures.append("%.0f Hz poles failed to settle after ski-away (%.3f)" % [hz, stats.final_pole_lag])

func _check_rate_independence(results: Array[Dictionary]) -> void:
	var baseline := results[2]
	for index: int in 2:
		var result := results[index]
		var hz := float(result.hz)
		if (result.final_pelvis_rotation as Vector3).distance_to(baseline.final_pelvis_rotation as Vector3) > 0.08:
			failures.append("%.0f Hz pelvis result diverged from 120 Hz" % hz)
		if (result.final_chest_rotation as Vector3).distance_to(baseline.final_chest_rotation as Vector3) > 0.1:
			failures.append("%.0f Hz chest result diverged from 120 Hz" % hz)
		if (result.final_left_pole_rotation as Vector3).distance_to(baseline.final_left_pole_rotation as Vector3) > 0.12:
			failures.append("%.0f Hz pole result diverged from 120 Hz" % hz)
		if absf(float(result.peak_torso_lag) - float(baseline.peak_torso_lag)) > 0.08:
			failures.append("%.0f Hz torso follow-through amplitude diverged from 120 Hz" % hz)
		if absf(float(result.peak_pole_lag) - float(baseline.peak_pole_lag)) > 0.12:
			failures.append("%.0f Hz pole inertia amplitude diverged from 120 Hz" % hz)

func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	_set_ground(frame)
	frame.speed_mps = 16.0
	frame.speed_ratio = 0.75
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_front_valid = true
	frame.left_rear_valid = true
	frame.right_front_valid = true
	frame.right_rear_valid = true
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	return frame

func _set_ground(frame: SkierAnimationFrame) -> void:
	frame.locomotion_state = 0
	frame.grounded = true
	frame.compression = 0.0
	frame.angular_velocity = Vector3.ZERO
	frame.trick_active = false
	frame.trick_intent = false
	frame.trick_kind = TrickCommand.Kind.NONE
	frame.trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	frame.grab_pose = TrickController.GrabPose.NONE
	frame.grab_amount = 0.0
	frame.grab_input_strength = 0.0
	frame.predicted_landing_time = -1.0
	frame.landing_event_active = false
	frame.vertical_velocity = 0.0

func _set_air(frame: SkierAnimationFrame) -> void:
	frame.locomotion_state = 1
	frame.grounded = false
	frame.compression = 0.0
	frame.air_time = 0.0
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.85
	frame.takeoff_upward_speed = 4.2
	frame.air_upward_velocity = 4.2
	frame.vertical_velocity = 4.2
	frame.predicted_landing_time = -1.0

func _set_carve(frame: SkierAnimationFrame, side: float) -> void:
	frame.edge = side * 0.9
	frame.turn_input = side
	frame.turn_rate = side * 0.72
	frame.lateral_acceleration = side * 8.5
	frame.carve_ratio = 0.92
	frame.skid_ratio = 0.04

func _euler_delta(current: Vector3, previous: Vector3) -> float:
	return Vector3(
		absf(wrapf(current.x - previous.x, -PI, PI)),
		absf(wrapf(current.y - previous.y, -PI, PI)),
		absf(wrapf(current.z - previous.z, -PI, PI))
	).length()

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
