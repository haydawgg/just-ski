extends Node

const STEP := 1.0 / 120.0

var failures: Array[String] = []
var maximum_pelvis_delta := 0.0
var maximum_ski_delta := 0.0
var maximum_shoulder_delta := 0.0

func _ready() -> void:
	_test_approach_anticipation_is_subtle()
	_test_entry_severity_scales_compression()
	_test_entry_sharper_and_smaller_than_landing()
	_test_balance_hierarchy_arms_over_skis()
	_test_no_fake_constant_wobble()
	_test_sideways_slide_separation()
	_test_exit_anticipation_near_end()
	_test_terrain_suspension_yields_to_rail()
	_test_poles_trail_on_rail()
	_test_full_sequence_bounded_deltas()
	AudioManager.shutdown_audio()
	print("RAIL_ANIMATION_RESULT pelvis_delta=%.4f ski_delta=%.4f shoulder_delta=%.4f" % [
		maximum_pelvis_delta,
		maximum_ski_delta,
		maximum_shoulder_delta,
	])
	if maximum_pelvis_delta > 0.1 or maximum_ski_delta > 0.32 or maximum_shoulder_delta > 0.55:
		failures.append("Rail animation produced a one-frame snap (pelvis %.4f ski %.4f shoulder %.4f)" % [
			maximum_pelvis_delta,
			maximum_ski_delta,
			maximum_shoulder_delta,
		])
	if failures.is_empty():
		print("RAIL_ANIMATION_PASS: approach, entry, balance hierarchy, sideways slide, exit, and handoff checks passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RAIL_ANIMATION_FAIL: " + failure)
	get_tree().quit(1)

func _test_approach_anticipation_is_subtle() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(12.0)
	_step(rig, frame, 30, false)
	var far := rig.debug_snapshot()
	frame.rail_approach_anticipation = 0.9
	_step(rig, frame, 60, false)
	var near := rig.debug_snapshot()
	if float(far.rail_approach_anticipation) > 0.05:
		failures.append("Rail anticipation appeared with no nearby rail")
	if float(near.rail_approach_anticipation) < 0.3:
		failures.append("Rail anticipation did not build up when a capture was imminent")
	if str(near.pose).find("Boardslide") >= 0 or str(near.pose).find("Rail") >= 0:
		failures.append("Approach anticipation incorrectly forced a full rail pose before contact")
	_dispose_rig(rig)

func _test_entry_severity_scales_compression() -> void:
	var clean := _sample_peak_entry_compression(0.1, 0.0)
	var rough := _sample_peak_entry_compression(0.9, 0.6)
	if clean + 0.1 >= rough:
		failures.append("Rail entry compression did not scale with entry severity (clean=%.2f rough=%.2f)" % [clean, rough])

func _test_entry_sharper_and_smaller_than_landing() -> void:
	var rail_peak := _sample_peak_entry_compression(1.0, 0.0)
	var profile := preload("res://resources/animation/default_animation_profile.tres") as SkierAnimationProfile
	if rail_peak > profile.rail_entry_max_compression + 0.02:
		failures.append("Rail entry compression exceeded its configured cap")
	if rail_peak >= profile.landing_compression_depth * 2.0:
		failures.append("Rail entry compression was not clearly smaller than a comparable snow landing")

func _test_balance_hierarchy_arms_over_skis() -> void:
	var rig := _new_rig()
	var frame := _grind_frame(9.0)
	_step(rig, frame, 20, false)
	var neutral := rig.debug_snapshot()
	frame.rail_balance = 0.8
	_step(rig, frame, 60, false)
	var leaning := rig.debug_snapshot()
	var ski_delta := absf(float((leaning.left_ski_rotation as Vector3).y) - float((neutral.left_ski_rotation as Vector3).y))
	var shoulder_delta := absf(float((leaning.left_shoulder_rotation as Vector3).z) - float((neutral.left_shoulder_rotation as Vector3).z))
	if shoulder_delta <= ski_delta:
		failures.append("Arms did not carry a larger balance response than the skis (ski=%.3f shoulder=%.3f)" % [ski_delta, shoulder_delta])
	_dispose_rig(rig)

func _test_no_fake_constant_wobble() -> void:
	var rig := _new_rig()
	var frame := _grind_frame(8.0)
	frame.rail_balance = 0.0
	_step(rig, frame, 30, false)
	var previous := rig.debug_snapshot().pelvis_rotation as Vector3
	var drifted := false
	for _index: int in 90:
		rig.apply_frame(frame, STEP)
		var current := rig.debug_snapshot().pelvis_rotation as Vector3
		if current.distance_to(previous) > 0.01:
			drifted = true
		previous = current
	if drifted:
		failures.append("Rail pose drifted with zero balance error (fake constant wobble)")
	_dispose_rig(rig)

func _test_sideways_slide_separation() -> void:
	var rig := _new_rig()
	var frame := _grind_frame(7.0)
	frame.rail_pose = -1
	_step(rig, frame, 90, false)
	var slid := rig.debug_snapshot()
	var pelvis_yaw := float((slid.pelvis_rotation as Vector3).y)
	var chest_yaw := float((slid.chest_rotation as Vector3).y)
	if absf(pelvis_yaw) < 0.05:
		failures.append("Sideways rail intent did not visibly rotate the hips/skis")
	if signf(pelvis_yaw) == signf(chest_yaw) and absf(chest_yaw) > 0.02:
		failures.append("Chest did not counter-rotate against the sideways hip/ski rotation")
	var profile := preload("res://resources/animation/default_animation_profile.tres") as SkierAnimationProfile
	if absf(chest_yaw) > profile.rail_slide_chest_counter + 0.05:
		failures.append("Chest counter-rotation exceeded a plausible clamp")
	_dispose_rig(rig)

func _test_exit_anticipation_near_end() -> void:
	var rig := _new_rig()
	var frame := _grind_frame(10.0)
	frame.rail_distance_to_end = 8.0
	_step(rig, frame, 40, false)
	var mid_rail := rig.debug_snapshot()
	frame.rail_distance_to_end = 0.15
	_step(rig, frame, 40, false)
	var near_end := rig.debug_snapshot()
	if float(near_end.rail_exit_anticipation) <= float(mid_rail.rail_exit_anticipation) + 0.15:
		failures.append("Exit anticipation did not build up near the end of the rail")
	_dispose_rig(rig)

func _test_terrain_suspension_yields_to_rail() -> void:
	var rig := _new_rig()
	var ground := _ground_frame(14.0)
	_step(rig, ground, 40, false)
	var grounded_snapshot := rig.debug_snapshot()
	if float(grounded_snapshot.terrain_influence) < 0.5:
		failures.append("Terrain suspension baseline did not engage on snow before the rail check")
	var grind := _grind_frame(11.0)
	_step(rig, grind, 60, false)
	var on_rail := rig.debug_snapshot()
	if float(on_rail.terrain_influence) > 0.15:
		failures.append("Terrain suspension did not yield while rail-locked")
	_dispose_rig(rig)

func _test_poles_trail_on_rail() -> void:
	var rig := _new_rig()
	var frame := _grind_frame(12.0)
	_step(rig, frame, 40, false)
	var snapshot := rig.debug_snapshot()
	var pole_rotation := snapshot.left_pole_rotation as Vector3
	if pole_rotation.length() < 0.05:
		failures.append("Poles stayed neutral during a rail slide instead of trailing")
	_dispose_rig(rig)

func _test_full_sequence_bounded_deltas() -> void:
	var rig := _new_rig()
	var ground := _ground_frame(13.0)
	_step(rig, ground, 30, true)
	ground.rail_approach_anticipation = 0.8
	_step(rig, ground, 20, true)
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, 0.55, 0.4)
	var grind := _grind_frame(11.0)
	grind.rail_balance = 0.3
	_step(rig, grind, 20, true)
	grind.rail_pose = 1
	_step(rig, grind, 40, true)
	grind.rail_distance_to_end = 0.2
	_step(rig, grind, 30, true)
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, 0.4, 1.0)
	var air := _air_descent_frame(11.0, 0.4)
	_step(rig, air, 20, true)
	var landing := _ground_frame(10.0)
	landing.landing_event_active = true
	landing.landing_impact_severity = 0.2
	landing.landing_outcome = LandingSolver.Outcome.CLEAN
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.2, 0.0)
	_step(rig, landing, 40, true)
	var last := rig.debug_snapshot()
	if rig.rotation.length() > 0.0001:
		failures.append("Rail sequence wrote root rotation instead of staying presentation-only")
	if str(last.pose).is_empty():
		failures.append("Skier lost a readable pose after the full rail sequence")
	_dispose_rig(rig)

func _sample_peak_entry_compression(severity: float, lateral_bias: float) -> float:
	var rig := _new_rig()
	var frame := _grind_frame(10.0)
	rig.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, severity, lateral_bias)
	var peak := 0.0
	for _index: int in 40:
		rig.apply_frame(frame, STEP)
		peak = maxf(peak, float(rig.debug_snapshot().rail_entry_compression))
	_dispose_rig(rig)
	return peak

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
	frame.air_time = 0.15
	frame.air_upward_velocity = -2.0
	frame.predicted_landing_time = predicted
	frame.skier_heading = Vector3.FORWARD
	frame.velocity_heading = Vector3.FORWARD
	return frame

func _grind_frame(speed: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 2
	frame.grounded = false
	frame.speed_mps = speed
	frame.speed_ratio = clampf(speed / 24.0, 0.0, 1.0)
	frame.rail_speed = speed
	frame.rail_balance = 0.0
	frame.rail_pose = 0
	frame.rail_direction = Vector3.FORWARD
	frame.rail_up = Vector3.UP
	frame.rail_progress = 0.3
	frame.rail_distance_to_end = 6.0
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
			maximum_pelvis_delta = maxf(maximum_pelvis_delta, (current.pelvis_position as Vector3).distance_to(previous.pelvis_position as Vector3))
			maximum_ski_delta = maxf(maximum_ski_delta, (current.left_ski_rotation as Vector3).distance_to(previous.left_ski_rotation as Vector3))
			maximum_shoulder_delta = maxf(maximum_shoulder_delta, (current.left_shoulder_rotation as Vector3).distance_to(previous.left_shoulder_rotation as Vector3))
			previous = current
