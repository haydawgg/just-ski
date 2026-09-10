extends Node3D

const STEP := 1.0 / 60.0
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().physics_frame
	await _check_visual_ski_feature_sweep()
	_check_pole_body_and_snow_clearance()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("EQUIPMENT_COLLISION_PASS: visual skis stop at solid features and pole shafts clear the body and snow envelopes")
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
		print("EQUIPMENT_POLE_CLEARANCE %s body=%.3f snow=%.3f left=%.3f right=%.3f" % [entry.label, signed_clearance, snow_clearance, float(production_clearance.get("left_pole_body_clearance_m", -INF)), float(production_clearance.get("right_pole_body_clearance_m", -INF))])
		if signed_clearance < 0.015:
			failures.append("%s pole shaft entered the body envelope (%.3fm signed clearance)" % [entry.label, signed_clearance])
		if snow_clearance < -0.055:
			failures.append("%s pole tip passed too far below the ski contact plane (%.3fm)" % [entry.label, snow_clearance])
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
