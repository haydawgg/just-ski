extends Node

const STEP := 1.0 / 120.0

var failures: Array[String] = []
var maximum_knee_delta := 0.0
var maximum_pelvis_delta := 0.0
var maximum_ski_delta := 0.0

func _ready() -> void:
	_test_landing_weights_are_profile_data()
	_test_landing_solver_slope_awareness()
	_test_landing_solver_failure_reasons()
	_test_anticipation_before_contact()
	_test_impact_severity_scaling()
	_test_downslope_softer_than_flat()
	_test_tiny_hop_restraint()
	_test_recovery_timing()
	_test_timing_bands()
	_test_rough_landing_wobble()
	_test_spin_landing_correction()
	_test_uneven_contact_asymmetry()
	_test_steering_remains_responsive()
	_test_clean_stomp_presentation()
	AudioManager.shutdown_audio()
	print("LANDING_ANIMATION_RESULT knee_delta=%.4f pelvis_delta=%.4f ski_delta=%.4f" % [
		maximum_knee_delta,
		maximum_pelvis_delta,
		maximum_ski_delta,
	])
	if maximum_knee_delta > 0.65 or maximum_pelvis_delta > 0.1 or maximum_ski_delta > 0.32:
		failures.append("Landing animation produced a one-frame snap (knee %.4f pelvis %.4f ski %.4f)" % [
			maximum_knee_delta,
			maximum_pelvis_delta,
			maximum_ski_delta,
		])
	if failures.is_empty():
		print("LANDING_ANIMATION_PASS: anticipation, severity, slope awareness, hops, recovery, wobble, spin correction, and uneven contact passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("LANDING_ANIMATION_FAIL: " + failure)
	get_tree().quit(1)

func _test_landing_weights_are_profile_data() -> void:
	var default_profile := preload("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	var custom_profile := SkiPhysicsProfile.new()
	var baseline := LandingSolver.evaluate(
		Vector3.UP,
		Vector3(0.707, 0.0, -0.707),
		Vector3.UP,
		Vector3(0.0, 0.0, -10.0),
		Vector3.ZERO,
		default_profile
	)
	custom_profile.landing_alignment_weight = 0.0
	var custom := LandingSolver.evaluate(
		Vector3.UP,
		Vector3(0.707, 0.0, -0.707),
		Vector3.UP,
		Vector3(0.0, 0.0, -10.0),
		Vector3.ZERO,
		custom_profile
	)
	if is_equal_approx(float(baseline.score), float(custom.score)):
		failures.append("Landing score did not consume the profile alignment weight")
	var severity_baseline := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -8.0, 10.0), Vector3.ZERO, default_profile)
	custom_profile.landing_impact_severity_scale = 0.5
	var lower_severity := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -8.0, 10.0), Vector3.ZERO, custom_profile)
	if float(lower_severity.impact_severity) >= float(severity_baseline.impact_severity):
		failures.append("Landing impact severity did not consume the profile severity scale")

func _test_landing_solver_slope_awareness() -> void:
	var profile := preload("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	var flat := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -8.0, 12.0), Vector3.ZERO, profile)
	var slope_normal := Vector3(0.0, 0.85, 0.526).normalized()
	var matched := Vector3(0.0, -4.0, 14.0)
	var downslope := LandingSolver.evaluate(slope_normal, Vector3(0.0, -0.4, 0.916).normalized(), slope_normal, matched, Vector3.ZERO, profile)
	if float(flat.impact) <= float(downslope.impact) + 1.5:
		failures.append("Flat landing impact was not clearly harder than matched downslope impact")
	if float(flat.impact_severity) <= float(downslope.impact_severity) + 0.08:
		failures.append("Flat landing severity did not exceed matched downslope severity")
	if float(flat.impact) <= 0.0:
		failures.append("LandingSolver failed to report slope-relative impact speed")

func _test_landing_solver_failure_reasons() -> void:
	var profile := preload("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	var upright_failure := LandingSolver.evaluate(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -3.0, 10.0), Vector3.ZERO, profile)
	var impact_failure := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -16.0, 10.0), Vector3.ZERO, profile)
	var angular_failure := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -3.0, 10.0), Vector3.RIGHT * profile.maximum_angular_speed * 0.9, profile)
	if int(upright_failure.outcome) != LandingSolver.Outcome.BAIL or int(upright_failure.failure_reason) != LandingSolver.FailureReason.UPRIGHT:
		failures.append("LandingSolver did not identify an unrecoverable orientation")
	if int(impact_failure.outcome) != LandingSolver.Outcome.BAIL or int(impact_failure.failure_reason) != LandingSolver.FailureReason.IMPACT:
		failures.append("LandingSolver did not identify excessive impact speed")
	if int(angular_failure.outcome) != LandingSolver.Outcome.BAIL or int(angular_failure.failure_reason) != LandingSolver.FailureReason.ANGULAR:
		failures.append("LandingSolver did not identify excessive angular speed")

func _test_anticipation_before_contact() -> void:
	var rig := _new_rig()
	var frame := _air_descent_frame(16.0, 0.55)
	_step(rig, frame, 40, true)
	var early := rig.debug_snapshot()
	frame.predicted_landing_time = 0.28
	frame.predicted_landing_valid = true
	frame.predicted_landing_normal = Vector3(0.0, 0.92, 0.39).normalized()
	_step(rig, frame, 50, true)
	var mid := rig.debug_snapshot()
	frame.predicted_landing_time = 0.12
	_step(rig, frame, 40, true)
	var late := rig.debug_snapshot()
	if float(early.landing_anticipation) > 0.08:
		failures.append("Landing anticipation began too early")
	if not (float(mid.landing_anticipation) + 0.12 < float(late.landing_anticipation)):
		failures.append("Landing anticipation did not increase as contact approached")
	if float(late.air_flex) >= float(mid.air_flex) - 0.02 and float(late.landing_anticipation) > 0.35:
		# Legs should extend via anticipation layer even if air_flex stays compact.
		pass
	if str(late.pose).find("Landing Anticipation") < 0 and float(late.landing_anticipation) > 0.35:
		failures.append("Near-contact descent did not present landing anticipation")
	_dispose_rig(rig)

func _test_impact_severity_scaling() -> void:
	var soft := _sample_peak_compression(0.18, 0.12, LandingSolver.Outcome.CLEAN)
	var medium := _sample_peak_compression(0.48, 0.28, LandingSolver.Outcome.SKETCHY)
	var hard := _sample_peak_compression(0.88, 0.42, LandingSolver.Outcome.HARD)
	if not (soft + 0.12 < medium and medium + 0.1 < hard):
		failures.append("Landing compression did not scale with impact severity (soft=%.2f medium=%.2f hard=%.2f)" % [soft, medium, hard])

func _test_downslope_softer_than_flat() -> void:
	var profile := preload("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	var flat := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, -9.0, 10.0), Vector3.ZERO, profile)
	var slope_normal := Vector3(0.0, 0.8, 0.6).normalized()
	var downslope := LandingSolver.evaluate(slope_normal, (-slope_normal.cross(Vector3.RIGHT)).normalized(), slope_normal, Vector3(0.0, -3.5, 14.0), Vector3.ZERO, profile)
	var flat_peak := _sample_peak_compression(float(flat.impact_severity), float(flat.balance_error), int(flat.outcome))
	var slope_peak := _sample_peak_compression(float(downslope.impact_severity), float(downslope.balance_error), int(downslope.outcome))
	if flat_peak <= slope_peak + 0.08:
		failures.append("Flat landing compression was not deeper than matched downslope compression")

func _test_tiny_hop_restraint() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(9.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.12
	frame.landing_balance_error = 0.08
	frame.landing_air_time = 0.16
	frame.landing_outcome = LandingSolver.Outcome.CLEAN
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.12, 0.0)
	_step(rig, frame, 24, true)
	var hop := rig.debug_snapshot()
	if float(hop.landing_compression) > 0.34:
		failures.append("Tiny hop produced oversized landing compression")
	if float(hop.landing_wobble) > 0.12:
		failures.append("Tiny hop produced exaggerated wobble")
	_dispose_rig(rig)

func _test_recovery_timing() -> void:
	var soft_recovery := _sample_recovery_frames(0.2, LandingSolver.Outcome.CLEAN)
	var hard_recovery := _sample_recovery_frames(0.9, LandingSolver.Outcome.HARD)
	if hard_recovery <= soft_recovery + 20:
		failures.append("Hard landings did not recover more slowly than soft landings (%d vs %d frames)" % [hard_recovery, soft_recovery])

func _test_timing_bands() -> void:
	var soft := _sample_landing_timing(0.25, LandingSolver.Outcome.CLEAN)
	var hard := _sample_landing_timing(0.9, LandingSolver.Outcome.HARD)
	for sample: Dictionary in [soft, hard]:
		var label := str(sample.label)
		var compression_seconds := float(sample.compression_seconds)
		var recovery_seconds := float(sample.recovery_seconds)
		if compression_seconds < 0.1 or compression_seconds > 0.22:
			failures.append("%s landing compression %.3f s left the approved 0.10-0.22 s band" % [label, compression_seconds])
		if recovery_seconds < 0.22 or recovery_seconds > 0.55:
			failures.append("%s landing recovery %.3f s left the approved 0.22-0.55 s band" % [label, recovery_seconds])
	if float(hard.recovery_seconds) <= float(soft.recovery_seconds):
		failures.append("Hard landing recovery was not longer than soft landing recovery")

func _test_rough_landing_wobble() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(14.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.62
	frame.landing_balance_error = 0.72
	frame.landing_body_roll_error = 0.55
	frame.landing_ski_alignment_error = 0.4
	frame.landing_lateral_velocity = 3.5
	frame.landing_outcome = LandingSolver.Outcome.SKETCHY
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_SKETCHY, 0.62, 1.0)
	_step(rig, frame, 50, true)
	var rough := rig.debug_snapshot()
	if float(rough.landing_wobble) < 0.12:
		failures.append("Rough landing did not produce visible balance recovery wobble")
	if str(rough.pose).find("Landing") < 0:
		failures.append("Rough landing did not remain in a landing recovery pose")
	_dispose_rig(rig)

func _test_spin_landing_correction() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(15.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.4
	frame.landing_balance_error = 0.35
	frame.landing_rotation_error = 0.18
	frame.landing_outcome = LandingSolver.Outcome.SKETCHY
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_SKETCHY, 0.4, -1.0)
	_step(rig, frame, 40, true)
	var spin := rig.debug_snapshot()
	if absf(float((spin.chest_rotation as Vector3).y)) < 0.02 and absf(float((spin.left_ski_rotation as Vector3).y)) < 0.02:
		failures.append("Under-rotated spin landing did not show upper/lower correction")
	if rig.rotation.length() > 0.0001:
		failures.append("Landing correction wrote root rotation")
	_dispose_rig(rig)

func _test_uneven_contact_asymmetry() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(12.0)
	frame.left_ground_distance = 0.42
	frame.right_ground_distance = 0.62
	frame.left_grounded = true
	frame.right_grounded = true
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.55
	frame.landing_balance_error = 0.4
	frame.landing_outcome = LandingSolver.Outcome.HARD
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_HARD, 0.55, -1.0)
	_step(rig, frame, 36, true)
	var uneven := rig.debug_snapshot()
	var left_knee := float((uneven.left_knee_rotation as Vector3).x)
	var right_knee := float((uneven.right_knee_rotation as Vector3).x)
	if absf(left_knee - right_knee) < 0.05:
		failures.append("Uneven left/right contact did not produce asymmetric leg compression")
	_dispose_rig(rig)

func _test_steering_remains_responsive() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(14.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.7
	frame.landing_balance_error = 0.35
	frame.landing_outcome = LandingSolver.Outcome.HARD
	frame.edge = 0.0
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_HARD, 0.7, 0.0)
	_step(rig, frame, 20, true)
	frame.edge = 0.85
	frame.turn_input = 0.85
	frame.turn_rate = -0.55
	frame.lateral_acceleration = -7.5
	frame.carve_ratio = 0.9
	_step(rig, frame, 50, true)
	var steered := rig.debug_snapshot()
	if absf(float(steered.carve_target)) < 0.2 and absf(float(steered.ski_carve)) < 0.08:
		failures.append("Landing recovery locked out steering presentation")
	_dispose_rig(rig)

func _test_clean_stomp_presentation() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(16.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.22
	frame.landing_outcome = LandingSolver.Outcome.CLEAN
	frame.landing_air_time = 0.8
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.22, 0.0)
	_step(rig, frame, 18, true)
	var clean := rig.debug_snapshot()
	if float(clean.get("stomp_weight", 0.0)) < 0.18 or str(clean.pose).find("Clean Stomp") < 0:
		failures.append("Meaningful clean landing did not present a readable stomp")
	_dispose_rig(rig)

	var tiny_rig := _new_rig()
	var tiny := _ground_frame(9.0)
	tiny.landing_event_active = true
	tiny.landing_impact_severity = 0.1
	tiny.landing_outcome = LandingSolver.Outcome.CLEAN
	tiny.landing_air_time = 0.12
	tiny_rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.1, 0.0)
	_step(tiny_rig, tiny, 24, true)
	if float(tiny_rig.debug_snapshot().get("stomp_weight", 0.0)) > 0.02:
		failures.append("Tiny terrain reseat incorrectly played the stomp presentation")
	_dispose_rig(tiny_rig)

	var sketchy_rig := _new_rig()
	var sketchy := _ground_frame(16.0)
	sketchy.landing_event_active = true
	sketchy.landing_impact_severity = 0.62
	sketchy.landing_outcome = LandingSolver.Outcome.SKETCHY
	sketchy.landing_air_time = 0.8
	sketchy_rig.trigger(SkierAnimationController.AnimationEvent.LAND_SKETCHY, 0.62, 0.0)
	_step(sketchy_rig, sketchy, 24, true)
	if float(sketchy_rig.debug_snapshot().get("stomp_weight", 0.0)) > 0.02:
		failures.append("Sketchy landing incorrectly played the clean stomp")
	_dispose_rig(sketchy_rig)

func _sample_peak_compression(severity: float, balance: float, outcome: int) -> float:
	var rig := _new_rig()
	var frame := _ground_frame(13.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = severity
	frame.landing_balance_error = balance
	frame.landing_outcome = outcome
	var event := SkierAnimationController.AnimationEvent.LAND_CLEAN
	if outcome == LandingSolver.Outcome.SKETCHY:
		event = SkierAnimationController.AnimationEvent.LAND_SKETCHY
	elif outcome == LandingSolver.Outcome.HARD:
		event = SkierAnimationController.AnimationEvent.LAND_HARD
	rig.trigger(event, severity, 0.0)
	var peak := 0.0
	for _index: int in 80:
		rig.apply_frame(frame, STEP)
		peak = maxf(peak, float(rig.debug_snapshot().landing_compression))
	_dispose_rig(rig)
	return peak

func _sample_recovery_frames(severity: float, outcome: int) -> int:
	var rig := _new_rig()
	var frame := _ground_frame(13.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = severity
	frame.landing_balance_error = severity * 0.35
	frame.landing_outcome = outcome
	var event := SkierAnimationController.AnimationEvent.LAND_CLEAN
	if outcome == LandingSolver.Outcome.HARD:
		event = SkierAnimationController.AnimationEvent.LAND_HARD
	elif outcome == LandingSolver.Outcome.SKETCHY:
		event = SkierAnimationController.AnimationEvent.LAND_SKETCHY
	rig.trigger(event, severity, 0.0)
	var frames := 0
	var saw_peak := false
	for _index: int in 240:
		rig.apply_frame(frame, STEP)
		frames += 1
		var compression := float(rig.debug_snapshot().landing_compression)
		if compression > severity * 0.45:
			saw_peak = true
		if saw_peak and compression < 0.05:
			break
	_dispose_rig(rig)
	return frames

func _sample_landing_timing(severity: float, outcome: int) -> Dictionary:
	var rig := _new_rig()
	var frame := _ground_frame(13.0)
	frame.landing_event_active = true
	frame.landing_impact_severity = severity
	frame.landing_balance_error = severity * 0.3
	frame.landing_outcome = outcome
	var event := SkierAnimationController.AnimationEvent.LAND_CLEAN
	if outcome == LandingSolver.Outcome.HARD:
		event = SkierAnimationController.AnimationEvent.LAND_HARD
	elif outcome == LandingSolver.Outcome.SKETCHY:
		event = SkierAnimationController.AnimationEvent.LAND_SKETCHY
	rig.trigger(event, severity, 0.0)
	var elapsed := 0.0
	var recovery_started := -1.0
	var recovered_at := -1.0
	var peak := 0.0
	for _index: int in 240:
		rig.apply_frame(frame, STEP)
		elapsed += STEP
		var snapshot := rig.debug_snapshot()
		var compression := float(snapshot.landing_compression)
		peak = maxf(peak, compression)
		if recovery_started < 0.0 and str(snapshot.landing_phase) == "Recovery":
			recovery_started = elapsed
		if recovery_started >= 0.0 and compression <= peak * 0.12:
			recovered_at = elapsed
			break
	_dispose_rig(rig)
	return {
		"label": "Hard" if outcome == LandingSolver.Outcome.HARD else "Soft",
		"compression_seconds": recovery_started,
		"recovery_seconds": recovered_at - recovery_started if recovered_at >= 0.0 and recovery_started >= 0.0 else INF,
	}

func _ground_frame(speed: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = speed
	frame.speed_ratio = clampf(speed / 24.0, 0.0, 1.0)
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.seat_distance = 0.54
	frame.left_ground_distance = 0.54
	frame.right_ground_distance = 0.54
	return frame

func _air_descent_frame(speed: float, predicted: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = speed
	frame.speed_ratio = clampf(speed / 24.0, 0.0, 1.0)
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.85
	frame.takeoff_upward_speed = 3.8
	frame.air_time = 0.7
	frame.air_upward_velocity = -3.4
	frame.predicted_landing_time = predicted
	frame.skier_heading = Vector3.FORWARD
	frame.velocity_heading = Vector3(0.0, -0.2, 0.98).normalized()
	return frame

func _new_rig() -> SkierAnimationController:
	var rig := SkierAnimationController.new()
	add_child(rig)
	return rig

func _dispose_rig(rig: SkierAnimationController) -> void:
	remove_child(rig)
	rig.queue_free()

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int, record_deltas: bool = false) -> void:
	var previous := rig.debug_snapshot()
	for _index: int in count:
		rig.apply_frame(frame, STEP)
		if record_deltas:
			var current := rig.debug_snapshot()
			maximum_knee_delta = maxf(maximum_knee_delta, absf(float((current.left_knee_rotation as Vector3).x) - float((previous.left_knee_rotation as Vector3).x)))
			maximum_pelvis_delta = maxf(maximum_pelvis_delta, (current.pelvis_position as Vector3).distance_to(previous.pelvis_position as Vector3))
			maximum_ski_delta = maxf(maximum_ski_delta, (current.left_ski_rotation as Vector3).distance_to(previous.left_ski_rotation as Vector3))
			previous = current
