extends Node

const STEP := 1.0 / 120.0

var failures: Array[String] = []
var maximum_knee_delta := 0.0
var maximum_pelvis_delta := 0.0
var maximum_ski_delta := 0.0

func _ready() -> void:
	_test_charge_anticipation()
	_test_air_phase_sequence()
	_test_jump_size_scaling()
	_test_terrain_hop()
	_test_straight_air_at_multiple_speeds()
	_test_physics_driven_spin_support()
	AudioManager.shutdown_audio()
	print("JUMP_ANIMATION_RESULT knee_delta=%.4f pelvis_delta=%.4f ski_delta=%.4f" % [
		maximum_knee_delta,
		maximum_pelvis_delta,
		maximum_ski_delta,
	])
	if maximum_knee_delta > 0.55 or maximum_pelvis_delta > 0.08 or maximum_ski_delta > 0.28:
		failures.append("Jump animation produced a one-frame snap (knee %.4f pelvis %.4f ski %.4f)" % [
			maximum_knee_delta,
			maximum_pelvis_delta,
			maximum_ski_delta,
		])
	if failures.is_empty():
		print("JUMP_ANIMATION_PASS: anticipation, extension, takeoff, early air, apex, descent, size scaling, terrain hops, straight air, and spin support passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("JUMP_ANIMATION_FAIL: " + failure)
	get_tree().quit(1)

func _test_charge_anticipation() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(10.0)
	frame.compression = 0.2
	_step(rig, frame, 60)
	var low := rig.debug_snapshot()
	frame.compression = 0.6
	_step(rig, frame, 60)
	var medium := rig.debug_snapshot()
	frame.compression = 1.0
	_step(rig, frame, 60)
	var high := rig.debug_snapshot()
	var low_knee := float((low.left_knee_rotation as Vector3).x)
	var medium_knee := float((medium.left_knee_rotation as Vector3).x)
	var high_knee := float((high.left_knee_rotation as Vector3).x)
	if not (low_knee + 0.06 < medium_knee and medium_knee + 0.06 < high_knee):
		failures.append("Jump anticipation did not scale progressively with charge")
	if not (float(low.pelvis_height) > float(medium.pelvis_height) and float(medium.pelvis_height) > float(high.pelvis_height)):
		failures.append("Pelvis did not lower continuously through jump charge")
	if high_knee >= rig.profile.max_leg_flex * 1.05 + 0.08:
		failures.append("Jump anticipation exceeded the bounded leg-flex range")
	_dispose_rig(rig)

func _test_air_phase_sequence() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(14.0)
	frame.compression = 1.0
	_step(rig, frame, 90)
	var charged := rig.debug_snapshot()
	rig.trigger(SkierAnimationController.AnimationEvent.POP, 1.0)
	frame = _air_frame(14.0, SkierAnimationFrame.TakeoffType.CHARGED_POP, 1.0, 4.2)
	frame.air_time = 0.04
	frame.air_upward_velocity = 3.8
	_step(rig, frame, 10, true)
	var takeoff := rig.debug_snapshot()
	frame.air_time = 0.27
	frame.air_upward_velocity = 2.2
	frame.predicted_landing_time = 0.75
	_step(rig, frame, 28, true)
	var early := rig.debug_snapshot()
	frame.air_time = 0.52
	frame.air_upward_velocity = 0.0
	frame.predicted_landing_time = 0.48
	_step(rig, frame, 36, true)
	var apex := rig.debug_snapshot()
	frame.air_time = 0.78
	frame.air_upward_velocity = -3.2
	frame.predicted_landing_time = 0.25
	_step(rig, frame, 36, true)
	var descent := rig.debug_snapshot()
	if str(takeoff.air_phase) != "Takeoff":
		failures.append("Authoritative takeoff did not begin in the takeoff phase")
	if str(early.air_phase) != "Early Air":
		failures.append("Ascending jump did not progress into early air")
	if str(apex.air_phase) != "Apex":
		failures.append("Near-zero takeoff-relative velocity did not select apex")
	if str(descent.air_phase) != "Descent":
		failures.append("Negative takeoff-relative velocity did not select descent")
	if not (float(takeoff.air_flex) + 0.1 < float(early.air_flex) and float(early.air_flex) < float(apex.air_flex)):
		failures.append("Legs did not extend through takeoff before compacting toward apex")
	if float(descent.air_flex) >= float(apex.air_flex) - 0.08:
		failures.append("Legs did not progressively extend during descent")
	if float(takeoff.pelvis_height) <= float(charged.pelvis_height) + 0.08:
		failures.append("Pop/takeoff did not visibly raise the pelvis from anticipation")
	_dispose_rig(rig)

func _test_jump_size_scaling() -> void:
	var small := _sample_apex_flex(SkierAnimationFrame.TakeoffType.CHARGED_POP, 0.2, 1.0, 7.0)
	var medium := _sample_apex_flex(SkierAnimationFrame.TakeoffType.CHARGED_POP, 0.58, 2.6, 13.0)
	var large := _sample_apex_flex(SkierAnimationFrame.TakeoffType.CHARGED_POP, 1.0, 4.3, 20.0)
	if not (small + 0.12 < medium and medium + 0.12 < large):
		failures.append("Small, medium, and large charged jumps did not produce distinct continuous compacting")

func _test_terrain_hop() -> void:
	var rig := _new_rig()
	var frame := _ground_frame(9.0)
	_step(rig, frame, 60)
	frame = _air_frame(9.0, SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF, 0.0, 0.78)
	frame.air_time = 0.12
	frame.air_upward_velocity = 0.05
	frame.predicted_landing_time = 0.12
	_step(rig, frame, 28, true)
	var hop := rig.debug_snapshot()
	if float(hop.air_size) > 0.16 or float(hop.air_flex) > 0.3:
		failures.append("A tiny uncharged terrain hop played an oversized jump pose")
	if int(hop.reaction) == SkierAnimationController.AnimationEvent.POP:
		failures.append("Terrain takeoff incorrectly played the charged-pop reaction")
	if float(hop.terrain_influence) > 0.12:
		failures.append("Terrain suspension remained magnetized during the terrain hop")
	_dispose_rig(rig)

func _test_straight_air_at_multiple_speeds() -> void:
	for entry_speed: float in [6.0, 13.0, 21.0]:
		var rig := _new_rig()
		var frame := _air_frame(entry_speed, SkierAnimationFrame.TakeoffType.CHARGED_POP, 0.68, 3.0)
		frame.air_time = 0.48
		frame.air_upward_velocity = 0.0
		frame.predicted_landing_time = 0.5
		_step(rig, frame, 70, true)
		var snapshot := rig.debug_snapshot()
		var ski_difference := (snapshot.left_ski_rotation as Vector3).distance_to(snapshot.right_ski_rotation as Vector3)
		if ski_difference > 0.035:
			failures.append("Neutral straight-air skis stopped reading as controlled and parallel at %.0f m/s" % entry_speed)
		if not _finite_pose(snapshot):
			failures.append("Straight air produced a non-finite pose at %.0f m/s" % entry_speed)
		_dispose_rig(rig)

func _test_physics_driven_spin_support() -> void:
	var rig := _new_rig()
	var frame := _air_frame(16.0, SkierAnimationFrame.TakeoffType.CHARGED_POP, 0.82, 3.6)
	frame.air_time = 0.42
	frame.air_upward_velocity = 0.15
	frame.predicted_landing_time = 0.58
	frame.angular_velocity = Vector3(0.0, 4.2, 0.0)
	frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.rotation_progress = 0.5
	_step(rig, frame, 70, true)
	var spin := rig.debug_snapshot()
	if "Spin" not in str(spin.pose):
		failures.append("Actual angular velocity did not produce restrained spin support")
	if absf(float((spin.pelvis_rotation as Vector3).y)) > 0.55 or absf(float((spin.chest_rotation as Vector3).y)) > 0.65:
		failures.append("Spin support over-rotated the internal skeleton against the physical root")
	if rig.rotation.length() > 0.0001:
		failures.append("Animation generated root rotation instead of following physics")
	_dispose_rig(rig)

func _sample_apex_flex(takeoff_type: int, charge: float, upward_speed: float, entry_speed: float) -> float:
	var rig := _new_rig()
	var frame := _air_frame(entry_speed, takeoff_type, charge, upward_speed)
	frame.air_time = maxf(0.25, upward_speed / 9.2)
	frame.air_upward_velocity = 0.0
	frame.predicted_landing_time = maxf(0.2, upward_speed / 9.2)
	_step(rig, frame, 80, true)
	var result := float(rig.debug_snapshot().air_flex)
	_dispose_rig(rig)
	return result

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
	return frame

func _air_frame(speed: float, takeoff_type: int, charge: float, upward_speed: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = speed
	frame.speed_ratio = clampf(speed / 24.0, 0.0, 1.0)
	frame.takeoff_type = takeoff_type
	frame.takeoff_charge = charge
	frame.takeoff_upward_speed = upward_speed
	frame.air_upward_velocity = upward_speed
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

func _finite_pose(snapshot: Dictionary) -> bool:
	for value: Vector3 in [
		snapshot.pelvis_rotation as Vector3,
		snapshot.left_knee_rotation as Vector3,
		snapshot.right_knee_rotation as Vector3,
		snapshot.left_ski_rotation as Vector3,
		snapshot.right_ski_rotation as Vector3,
	]:
		if not is_finite(value.x) or not is_finite(value.y) or not is_finite(value.z):
			return false
	return true
