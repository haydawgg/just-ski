extends Node3D

const STEP := 1.0 / 60.0
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().physics_frame
	await _check_visual_ski_feature_sweep()
	_check_pole_body_and_snow_clearance()
	_check_ski_span_separation()
	await _check_airborne_pole_obstruction()
	await _check_airborne_pole_feature_crash()
	await _check_airborne_pole_crash_exemptions()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("EQUIPMENT_COLLISION_PASS: visual skis stop at solid features, pole shafts clear the body and snow envelopes, and ski nose/tail pairs hold separation")
		await _finish(0)
		return
	for failure: String in failures:
		push_error("EQUIPMENT_COLLISION_FAIL: " + failure)
	await _finish(1)

func _check_visual_ski_feature_sweep() -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, 0.0, -12.0))
	await get_tree().process_frame
	var landmarks := skier.animation_controller.rig_adapter.landmarks()
	var left_nose := landmarks.get("left_ski_nose", Vector3.ZERO) as Vector3
	var left_tail := landmarks.get("left_ski_tail", Vector3.ZERO) as Vector3
	var ski_forward := (left_nose - left_tail).normalized()
	if ski_forward.length_squared() < 0.9:
		failures.append("Production rig did not expose a valid visual ski segment")
		_remove_now(skier)
		return
	var obstacle := StaticBody3D.new()
	obstacle.name = "SkiTipFixture"
	obstacle.collision_layer = 4
	obstacle.collision_mask = 0
	obstacle.set_meta("asset_id", "ski_tip_fixture")
	obstacle.set_meta("asset_class", "solid_feature")
	obstacle.set_meta("collision_policy", "crash")
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 0.22, 0.18)
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	obstacle.global_position = left_nose + ski_forward * 0.24
	await get_tree().physics_frame
	if not skier.has_method("resolve_visual_ski_feature_sweep"):
		failures.append("Skier has no swept visual-ski feature collision seam")
	else:
		var speed_before := skier.velocity.length()
		var result := skier.call("resolve_visual_ski_feature_sweep", STEP, skier.velocity) as Dictionary
		if not bool(result.get("hit", false)):
			failures.append("Swept visual ski missed a solid feature placed beyond the body capsule")
		if float(result.get("safe_fraction", 1.0)) >= 0.99:
			failures.append("Visual ski feature sweep did not limit travel before overlap")
		if skier.state != SkierController.State.BAIL:
			failures.append("Visual ski feature impact did not enter the existing bail path")
		if skier.velocity.length() >= speed_before * 0.9:
			failures.append("Visual ski feature impact retained enough speed to penetrate on the same tick")
		if skier.last_collision_diagnostics.is_empty():
			failures.append("Visual ski feature impact emitted no collision diagnostic")
	_remove_now(obstacle)
	_remove_now(skier)

func _check_pole_body_and_snow_clearance() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frames: Array[Dictionary] = [{"label": "ground", "frame": _ground_frame()}]
	for pose: int in range(1, 10):
		var grab := _air_frame()
		grab.grab_pose = pose
		grab.grab_amount = 1.0
		grab.grab_input_strength = 1.0
		grab.grab_hold_time = 0.65
		grab.trick_phase = TrickCommand.PresentationPhase.GRAB
		frames.append({"label": "grab_%d" % pose, "frame": grab})
	for entry: Dictionary in frames:
		for _index: int in 90:
			rig.apply_frame(entry.frame as SkierAnimationFrame, STEP)
		var adapter := rig.rig_adapter as SkeletonSkierRig
		if adapter == null:
			failures.append("Production skeleton rig was unavailable for pole clearance")
			break
		var signed_clearance := _minimum_pole_body_clearance(adapter)
		var snow_clearance := _minimum_ground_pole_tip_clearance(adapter) if str(entry.label) == "ground" else INF
		var production_clearance := adapter.pole_clearance_snapshot()
		print("EQUIPMENT_POLE_CLEARANCE %s body=%.3f snow=%.3f left=%.3f right=%.3f polepole=%.3f" % [entry.label, signed_clearance, snow_clearance, float(production_clearance.get("left_pole_body_clearance_m", -INF)), float(production_clearance.get("right_pole_body_clearance_m", -INF)), float(production_clearance.get("pole_pole_clearance_m", -INF))])
		if signed_clearance < 0.015:
			failures.append("%s pole shaft entered the body envelope (%.3fm signed clearance)" % [entry.label, signed_clearance])
		if snow_clearance < -0.055:
			failures.append("%s pole tip passed too far below the ski contact plane (%.3fm)" % [entry.label, snow_clearance])
		if str(entry.label) == "ground" and float(production_clearance.get("pole_pole_clearance_m", -INF)) < 0.04:
			failures.append("%s pole shafts converged (%.3fm shaft daylight)" % [entry.label, float(production_clearance.get("pole_pole_clearance_m", -INF))])
	_remove_now(rig)

func _minimum_pole_body_clearance(adapter: SkeletonSkierRig) -> float:
	var capsules: Array[Dictionary] = [
		{"a": adapter._bone_world(&"pelvis").origin, "b": adapter._bone_world(&"chest").origin, "radius": 0.18},
		{"a": adapter._bone_world(&"chest").origin, "b": adapter._bone_world(&"head").origin, "radius": 0.145},
		{"a": adapter._bone_world(&"left_hip").origin, "b": adapter._bone_world(&"left_knee").origin, "radius": 0.105},
		{"a": adapter._bone_world(&"right_hip").origin, "b": adapter._bone_world(&"right_knee").origin, "radius": 0.105},
		{"a": adapter._bone_world(&"left_knee").origin, "b": adapter._bone_world(&"left_boot").origin, "radius": 0.09},
		{"a": adapter._bone_world(&"right_knee").origin, "b": adapter._bone_world(&"right_boot").origin, "radius": 0.09},
	]
	var minimum := INF
	for side: StringName in [&"left", &"right"]:
		var pivot := adapter.equipment_nodes.get(StringName(side + "_pole")) as Node3D
		var tip := adapter.equipment_tips.get(side) as Node3D
		if pivot == null or tip == null:
			return -INF
		var start := pivot.global_position.lerp(tip.global_position, 0.075)
		for sample_index: int in 25:
			var point := start.lerp(tip.global_position, float(sample_index) / 24.0)
			for capsule: Dictionary in capsules:
				minimum = minf(minimum, _point_to_segment(point, capsule.a as Vector3, capsule.b as Vector3) - float(capsule.radius))
	return minimum

func _minimum_ground_pole_tip_clearance(adapter: SkeletonSkierRig) -> float:
	var landmarks := adapter.landmarks()
	var ski_plane_point := ((landmarks.left_ski_nose as Vector3) + (landmarks.left_ski_tail as Vector3) + (landmarks.right_ski_nose as Vector3) + (landmarks.right_ski_tail as Vector3)) * 0.25
	var up := adapter.driver.global_basis.y.normalized()
	return minf(
		((landmarks.left_pole_tip as Vector3) - ski_plane_point).dot(up),
		((landmarks.right_pole_tip as Vector3) - ski_plane_point).dot(up)
	)

func _check_ski_span_separation() -> void:
	# Yawed ski pair with coincident boots: nose pair crosses laterally.
	# The span solver must separate nose and tail pairs to at least the
	# stance width without moving the pair centroid.
	var lateral := Vector3.RIGHT
	var left_boot := Vector3.ZERO
	var right_boot := Vector3.ZERO
	var left_forward := Vector3(0.0, 0.0, -1.0)
	var right_forward := Vector3(0.35, 0.0, -0.94).normalized()
	var separated: Array = SkiConstrainedLegIK.separate_ski_span(
		left_boot, right_boot, left_forward, right_forward, lateral, 0.16)
	var left_out := separated[0] as Vector3
	var right_out := separated[1] as Vector3
	for end_sign: float in [1.0, -1.0]:
		var left_end := left_out + left_forward * (SkiConstrainedLegIK.SKI_HALF_LENGTH * end_sign)
		var right_end := right_out + right_forward * (SkiConstrainedLegIK.SKI_HALF_LENGTH * end_sign)
		if (right_end - left_end).dot(lateral) < 0.16 - 0.0001:
			failures.append("Ski span solver left nose/tail pairs overlapping after separation")
	# Idempotency: a satisfied span passes through unchanged.
	var settled: Array = SkiConstrainedLegIK.separate_ski_span(
		left_out, right_out, left_forward, right_forward, lateral, 0.16)
	if not (settled[0] as Vector3).is_equal_approx(left_out) or not (settled[1] as Vector3).is_equal_approx(right_out):
		failures.append("Ski span solver is not idempotent on a satisfied span")
	# Degenerate forward falls back to boot positions without failing.
	var degenerate: Array = SkiConstrainedLegIK.separate_ski_span(
		left_boot, right_boot, Vector3.ZERO, Vector3.ZERO, lateral, 0.16)
	if not (degenerate[0] as Vector3).is_finite() or not (degenerate[1] as Vector3).is_finite():
		failures.append("Ski span solver produced a non-finite result for degenerate ski forward")

func _check_airborne_pole_obstruction() -> void:
	# A solid park feature on the pole shaft must retract AIR preview IK
	# (presentation-only obstruction), while an empty scene stays at full
	# weight. Leg rays aim straight down from the hips so only the pole ray
	# can observe the fixture.
	var rig := SkierAnimationController.new()
	add_child(rig)
	await get_tree().physics_frame
	if rig.left_hand == null or rig.left_pole_tip == null:
		failures.append("Articulated rig did not expose hand and pole-tip nodes")
		_remove_now(rig)
		return
	var clear_scale := rig._preview_obstruction_scale(
		rig.left_hip.global_position + Vector3(0.0, -3.0, 0.0),
		rig.right_hip.global_position + Vector3(0.0, -3.0, 0.0))
	if clear_scale < 0.999:
		failures.append("AIR preview reported obstruction with no feature present (%.3f)" % clear_scale)
	var midpoint := (rig.left_hand.global_position + rig.left_pole_tip.global_position) * 0.5
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 4
	obstacle.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 0.12, 0.12)
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	obstacle.global_position = midpoint
	await get_tree().physics_frame
	var blocked_scale := rig._preview_obstruction_scale(
		rig.left_hip.global_position + Vector3(0.0, -3.0, 0.0),
		rig.right_hip.global_position + Vector3(0.0, -3.0, 0.0))
	if blocked_scale > 0.001:
		failures.append("AIR preview ignored a solid feature on the pole shaft (%.3f)" % blocked_scale)
	_remove_now(obstacle)
	_remove_now(rig)

func _check_airborne_pole_feature_crash() -> void:
	# A pole spearing a solid feature mid-flight at speed must bail through
	# the existing crash path, tagged as pole equipment.
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, 0.0, -12.0))
	skier.predicted_landing_time = -1.0
	await get_tree().process_frame
	var segments := skier.animation_controller.rig_adapter.pole_shaft_segments()
	if segments.is_empty() or not (segments.has(&"left") or segments.has(&"right")):
		failures.append("Production rig did not expose pole shaft segments")
		_remove_now(skier)
		return
	var side := &"left" if segments.has(&"left") else &"right"
	var segment := segments[side] as Dictionary
	var midpoint := ((segment.start as Vector3) + (segment.end as Vector3)) * 0.5
	var obstacle := _feature_fixture(midpoint + Vector3(0.0, 0.0, -0.24))
	await get_tree().physics_frame
	var speed_before := skier.velocity.length()
	var result := skier.resolve_airborne_pole_feature_sweep(STEP, skier.velocity) as Dictionary
	if not bool(result.get("hit", false)):
		failures.append("Airborne pole sweep missed a solid feature on the shaft path")
	if float(result.get("safe_fraction", 1.0)) >= 0.99:
		failures.append("Airborne pole sweep did not limit travel before overlap")
	if skier.state != SkierController.State.BAIL:
		failures.append("Airborne pole impact did not enter the existing bail path")
	if skier.velocity.length() >= speed_before * 0.9:
		failures.append("Airborne pole impact retained enough speed to penetrate on the same tick")
	if skier.last_collision_diagnostics.is_empty():
		failures.append("Airborne pole impact emitted no collision diagnostic")
	else:
		var diagnostic := skier.last_collision_diagnostics.back() as Dictionary
		if str(diagnostic.get("equipment_kind", "")) != "pole":
			failures.append("Airborne pole impact diagnostic was not tagged as pole equipment")
	_remove_now(obstacle)
	_remove_now(skier)

func _check_airborne_pole_crash_exemptions() -> void:
	# Below-threshold speed, held grabs, and the landing window must never
	# convert a pole/feature overlap into a bail.
	var slow := SkierController.new()
	slow.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(slow)
	slow.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, 0.0, -5.5))
	slow.predicted_landing_time = -1.0
	await get_tree().process_frame
	var slow_segments := slow.animation_controller.rig_adapter.pole_shaft_segments()
	if not slow_segments.is_empty():
		var slow_side := &"left" if slow_segments.has(&"left") else &"right"
		var slow_segment := slow_segments[slow_side] as Dictionary
		# Anchor the fixture to the pole TIP along the travel direction: the
		# tip cap is equidistant by construction for any shaft orientation,
		# unlike a midpoint offset when poles splay sideways. A sphere has no
		# corners, so the margin window stays valid at any travel length.
		var slow_tip := slow_segment.end as Vector3
		var slow_travel := slow.velocity.length() * STEP
		var slow_obstacle := _sphere_fixture(slow_tip + Vector3(0.0, 0.0, -1.0) * (0.165 + slow_travel * 0.5), 0.09)
		await get_tree().physics_frame
		var slow_result := slow.resolve_airborne_pole_feature_sweep(STEP, slow.velocity) as Dictionary
		if not bool(slow_result.get("hit", false)):
			failures.append("Low-speed pole overlap did not register a sweep hit")
		if slow.state == SkierController.State.BAIL:
			failures.append("Low-speed pole overlap incorrectly entered the bail path")
		_remove_now(slow_obstacle)
	_remove_now(slow)
	var landing := SkierController.new()
	landing.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(landing)
	landing.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, 0.0, -12.0))
	landing.predicted_landing_time = 0.1
	await get_tree().process_frame
	var landing_segments := landing.animation_controller.rig_adapter.pole_shaft_segments()
	if not landing_segments.is_empty():
		var landing_side := &"left" if landing_segments.has(&"left") else &"right"
		var landing_segment := landing_segments[landing_side] as Dictionary
		var landing_mid := ((landing_segment.start as Vector3) + (landing_segment.end as Vector3)) * 0.5
		var landing_obstacle := _feature_fixture(landing_mid)
		await get_tree().physics_frame
		var landing_result := landing.resolve_airborne_pole_feature_sweep(STEP, landing.velocity) as Dictionary
		if bool(landing_result.get("hit", false)):
			failures.append("Landing-window pole overlap was swept instead of exempted")
		if landing.state == SkierController.State.BAIL:
			failures.append("Landing-window pole overlap incorrectly entered the bail path")
		_remove_now(landing_obstacle)
	_remove_now(landing)
	var grab := SkierController.new()
	grab.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(grab)
	grab.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, 0.0, -12.0))
	grab.predicted_landing_time = -1.0
	await get_tree().process_frame
	var grab_frame := _air_frame()
	grab_frame.grab_pose = 1
	grab_frame.grab_amount = 1.0
	grab_frame.grab_input_strength = 1.0
	grab_frame.grab_hold_time = 0.65
	grab_frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	for _index: int in 90:
		grab.animation_controller.apply_frame(grab_frame, STEP)
	var grab_left := grab.animation_controller.rig_adapter.grab_target_world(&"left") as Vector3
	var grab_right := grab.animation_controller.rig_adapter.grab_target_world(&"right") as Vector3
	if grab_left == Vector3.ZERO and grab_right == Vector3.ZERO:
		failures.append("Grab fixture did not engage a hand target for the exemption check")
	else:
		var grab_segments := grab.animation_controller.rig_adapter.pole_shaft_segments()
		if not grab_segments.is_empty():
			var grab_side := &"left" if grab_segments.has(&"left") else &"right"
			var grab_segment := grab_segments[grab_side] as Dictionary
			var grab_mid := ((grab_segment.start as Vector3) + (grab_segment.end as Vector3)) * 0.5
			var grab_obstacle := _feature_fixture(grab_mid)
			await get_tree().physics_frame
			var grab_result := grab.resolve_airborne_pole_feature_sweep(STEP, grab.velocity) as Dictionary
			if bool(grab_result.get("hit", false)):
				failures.append("Held-grab pole overlap was swept instead of exempted")
			if grab.state == SkierController.State.BAIL:
				failures.append("Held-grab pole overlap incorrectly entered the bail path")
			_remove_now(grab_obstacle)
	_remove_now(grab)

func _feature_fixture(position: Vector3) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.name = "PoleShaftFixture"
	obstacle.collision_layer = 4
	obstacle.collision_mask = 0
	obstacle.set_meta("asset_id", "pole_shaft_fixture")
	obstacle.set_meta("asset_class", "solid_feature")
	obstacle.set_meta("collision_policy", "crash")
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 0.22, 0.18)
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	obstacle.global_position = position
	return obstacle

func _sphere_fixture(position: Vector3, radius: float) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.name = "PoleTipFixture"
	obstacle.collision_layer = 4
	obstacle.collision_mask = 0
	obstacle.set_meta("asset_id", "pole_tip_fixture")
	obstacle.set_meta("asset_class", "solid_feature")
	obstacle.set_meta("collision_policy", "crash")
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	obstacle.global_position = position
	return obstacle

func _point_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var denominator := segment.length_squared()
	if denominator <= 0.000001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / denominator, 0.0, 1.0)
	return point.distance_to(start.lerp(end, t))

func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierController.State.GROUND
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
	frame.locomotion_state = SkierController.State.AIR
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.8
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.9
	frame.takeoff_upward_speed = 4.0
	frame.air_time = 0.48
	frame.predicted_landing_time = 0.52
	return frame

func _remove_now(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()

func _finish(exit_code: int) -> void:
	for child: Node in get_children():
		if is_instance_valid(child):
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not RuntimeEnvironment.is_headless():
		await RenderingServer.frame_post_draw
	get_tree().quit(exit_code)
