extends Node

const STEP := 1.0 / 120.0
const GRAB_POSES: Array[int] = [
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

func _ready() -> void:
	var profile := _synthetic_profile()
	_test_skeleton_adapter(profile)
	_test_invalid_mapping(profile)
	_test_controller_selection(profile)
	_test_supplied_asset_when_present()
	_test_production_visual_alignment()
	_test_production_calibration()
	await _test_production_pose_sweep()
	await _test_production_grab_reach()
	await _test_production_contact_envelope()
	if failures.is_empty():
		print("SKELETON_RIG_PASS: bone mapping, production pose sweep, grab reach, neutral-relative retargeting, equipment attachments, strict selection, and AUTO fallback passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("SKELETON_RIG_FAIL: " + failure)
		get_tree().quit(1)

func _test_skeleton_adapter(profile: SkierSkeletonProfile) -> void:
	var driver := SkierPoseDriver.new()
	driver.name = "Driver"
	add_child(driver)
	driver.build()
	var adapter := SkeletonSkierRig.new()
	adapter.name = "SkeletonAdapter"
	add_child(adapter)
	_check(adapter.configure(driver, profile), "A valid synthetic Skeleton3D profile was rejected: " + adapter.validation_error())
	if adapter.skeleton != null:
		var pelvis_index := int(adapter.bone_indices[&"pelvis"])
		var knee_index := int(adapter.bone_indices[&"left_knee"])
		driver.joint(&"pelvis").rotation = Vector3(0.18, -0.12, 0.08)
		driver.joint(&"pelvis").position += Vector3(0.06, -0.11, 0.03)
		driver.joint(&"left_knee").rotation = Vector3(0.74, 0.0, 0.0)
		adapter.sync_pose(1.0 / 60.0)
		var pelvis_rotation := adapter.skeleton.get_bone_pose_rotation(pelvis_index)
		var expected_pelvis := Quaternion.from_euler(driver.joint(&"pelvis").rotation)
		_check(absf(pelvis_rotation.dot(expected_pelvis)) > 0.9999, "Pelvis canonical rotation was not retargeted in local bone space")
		_check(adapter.skeleton.get_bone_pose_position(pelvis_index).distance_to(Vector3(0.06, -0.11, 0.03)) < 0.0001, "Pelvis positional delta was not written relative to neutral pose")
		_check(absf(adapter.skeleton.get_bone_pose_rotation(knee_index).dot(Quaternion.from_euler(Vector3(0.74, 0.0, 0.0)))) > 0.9999, "Knee rotation did not reach the mapped lower-leg bone")
		var target := adapter.grab_target(&"left", &"nose")
		var before := target.global_position if target != null else Vector3.ZERO
		driver.joint(&"left_ski").rotation = Vector3(0.22, -0.14, 0.19)
		adapter.sync_pose(1.0 / 60.0)
		_check(target != null and target.global_position.distance_to(before) > 0.01, "Ski-local grab target did not follow the attached ski pivot")
		var landmarks := adapter.landmarks()
		for key: String in ["head", "pelvis", "left_hand", "right_hand", "left_ski_nose", "right_pole_tip"]:
			_check(landmarks.has(key) and (landmarks[key] as Vector3).is_finite(), "Skeleton landmark '%s' is missing or non-finite" % key)
	remove_child(adapter)
	adapter.free()
	remove_child(driver)
	driver.free()

func _test_invalid_mapping(valid_profile: SkierSkeletonProfile) -> void:
	var driver := SkierPoseDriver.new()
	add_child(driver)
	driver.build()
	var invalid := valid_profile.duplicate(true) as SkierSkeletonProfile
	invalid.bone_names = invalid.bone_names.duplicate(true)
	invalid.bone_names[&"left_hand"] = &"MissingHand"
	var adapter := SkeletonSkierRig.new()
	add_child(adapter)
	_check(not adapter.configure(driver, invalid), "An invalid required bone mapping was accepted")
	_check("MissingHand" in adapter.validation_error(), "Invalid mapping did not identify the missing bone")
	remove_child(adapter)
	adapter.free()
	remove_child(driver)
	driver.free()

func _test_controller_selection(valid_profile: SkierSkeletonProfile) -> void:
	var skeleton_controller := SkierAnimationController.new()
	skeleton_controller.rig_mode = SkierAnimationController.RigMode.SKELETON
	skeleton_controller.skeleton_profile = valid_profile
	add_child(skeleton_controller)
	var strict_snapshot := skeleton_controller.debug_snapshot()
	_check(str(strict_snapshot.rig_adapter) == "skeleton", "Strict mode did not select the valid Skeleton3D adapter")
	var root_before := skeleton_controller.transform
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	skeleton_controller.apply_frame(frame, 1.0 / 60.0)
	_check(skeleton_controller.transform.is_equal_approx(root_before), "Skeleton pose application changed the animation/gameplay root")
	remove_child(skeleton_controller)
	skeleton_controller.free()

	var fallback_controller := SkierAnimationController.new()
	fallback_controller.rig_mode = SkierAnimationController.RigMode.AUTO
	fallback_controller.skeleton_profile = SkierSkeletonProfile.new()
	add_child(fallback_controller)
	var fallback_snapshot := fallback_controller.debug_snapshot()
	_check(str(fallback_snapshot.rig_adapter) == "primitive", "AUTO did not select the primitive fallback for a missing body scene")
	_check(not str(fallback_snapshot.rig_fallback_reason).is_empty(), "AUTO fallback did not expose its validation reason")
	remove_child(fallback_controller)
	fallback_controller.free()

func _test_supplied_asset_when_present() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		print("SKELETON_RIG_ASSET_PENDING: " + body_path)
		return
	var controller := SkierAnimationController.new()
	controller.rig_mode = SkierAnimationController.RigMode.SKELETON
	add_child(controller)
	var snapshot := controller.debug_snapshot()
	_check(str(snapshot.rig_adapter) == "skeleton", "The supplied production GLB failed strict selection: " + str(snapshot.rig_fallback_reason))
	remove_child(controller)
	controller.free()

func _test_production_visual_alignment() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		return
	var controller := SkierAnimationController.new()
	controller.rig_mode = SkierAnimationController.RigMode.SKELETON
	add_child(controller)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GROUND
	frame.grounded = true
	controller.apply_frame(frame, 1.0 / 60.0)
	var adapter := controller.rig_adapter as SkeletonSkierRig
	var visual := adapter.landmarks() if adapter != null else {}
	var canonical := controller.pose_driver.canonical_landmarks() if controller.pose_driver != null else {}
	for landmark: String in ["pelvis", "left_boot", "right_boot", "left_hand", "right_hand"]:
		if not visual.has(landmark) or not canonical.has(landmark):
			_check(false, "Production visual alignment did not expose %s" % landmark)
			continue
		var distance := (visual[landmark] as Vector3).distance_to(canonical[landmark] as Vector3)
		print("SKELETON_RIG_ALIGNMENT %s=%.3f" % [landmark, distance])
		_check(distance < 0.45, "Production %s is %.2fm from its canonical landmark" % [landmark, distance])
	remove_child(controller)
	controller.free()

func _test_production_calibration() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		return
	var controller := _production_controller()
	var adapter := controller.rig_adapter as SkeletonSkierRig
	if adapter == null:
		_check(false, "Production calibration could not create the Skeleton3D adapter")
		controller.free()
		return
	var left_lengths := adapter.arm_lengths(&"left")
	var right_lengths := adapter.arm_lengths(&"right")
	print("SKELETON_RIG_CALIBRATION left=(%.4f,%.4f) right=(%.4f,%.4f) helpers=%s" % [
		left_lengths.x, left_lengths.y, right_lengths.x, right_lengths.y, adapter.grab_debug_snapshot().get("helper_bones", {}),
	])
	for side: StringName in [&"left", &"right"]:
		var lengths := adapter.arm_lengths(side)
		_check(lengths.x > 0.30 and lengths.x < 0.36, "%s production upper-arm length was not measured from the scaled rest pose" % side)
		_check(lengths.y > 0.20 and lengths.y < 0.28, "%s production forearm length was not measured from the scaled rest pose" % side)
		_check(absf(lengths.x - controller.profile.grab_upper_arm_length) > 0.05, "%s production upper-arm length fell back to the canonical value" % side)
		_check(absf(lengths.y - controller.profile.grab_forearm_length) > 0.05, "%s production forearm length fell back to the canonical value" % side)
	_check(left_lengths.distance_to(right_lengths) < 0.002, "Mirrored production arm lengths were not calibrated consistently")
	_check(adapter._helper_bone_indices.has(&"upper_spine"), "Default production profile did not enable the upper-spine helper")
	_check(adapter._helper_bone_indices.has(&"left_clavicle"), "Default production profile did not enable the left clavicle helper")
	_check(adapter._helper_bone_indices.has(&"right_clavicle"), "Default production profile did not enable the right clavicle helper")
	_check(str(adapter.grab_debug_snapshot().get("solver", "")) == "IDLE", "Production solver was active without a grab request")
	controller.free()

func _test_production_pose_sweep() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		return
	var scenarios: Array[Array] = [
		["straight", _ground_frame(0.0, false)],
		["carve_left", _ground_frame(-1.0, false)],
		["carve_right", _ground_frame(1.0, false)],
		["switch", _ground_frame(0.0, true)],
		["jump", _air_frame()],
		["spin_360", _trick_frame(TrickCommand.Kind.SPIN_RIGHT, Vector3(0.0, 4.2, 0.0), Vector3(0.0, TAU, 0.0))],
		["spin_720", _trick_frame(TrickCommand.Kind.SPIN_LEFT, Vector3(0.0, -6.2, 0.0), Vector3(0.0, -TAU * 2.0, 0.0))],
		["frontflip", _trick_frame(TrickCommand.Kind.FRONTFLIP, Vector3(5.0, 0.0, 0.0), Vector3(TAU, 0.0, 0.0))],
		["backflip", _trick_frame(TrickCommand.Kind.BACKFLIP, Vector3(-5.0, 0.0, 0.0), Vector3(-TAU, 0.0, 0.0))],
		["cork", _trick_frame(TrickCommand.Kind.CORK_RIGHT, Vector3(0.0, 4.2, 4.0), Vector3(0.0, TAU, PI))],
		["spread_eagle", _style_frame(TrickController.StylePose.SPREAD_EAGLE)],
		["daffy", _style_frame(TrickController.StylePose.DAFFY)],
		["shifty", _style_frame(TrickController.StylePose.SHIFTY_LEFT)],
		["rail", _rail_frame(0)],
		["boardslide", _rail_frame(1)],
		["landing", _landing_frame()],
		["crash_impact", _crash_frame(CrashContext.Stage.IMPACT, 0.18)],
		["crash_fall", _crash_frame(CrashContext.Stage.FALL, 0.7)],
		["crash_rest", _crash_frame(CrashContext.Stage.REST, 1.4)],
	]
	var maximum_orientation_error := 0.0
	var maximum_helper_drift := 0.0
	var maximum_segment_drift := 0.0
	var maximum_landmark_step := 0.0
	for scenario: Array in scenarios:
		var controller := _production_controller()
		var adapter := controller.rig_adapter as SkeletonSkierRig
		if adapter == null:
			_check(false, "Production pose sweep could not create the Skeleton3D adapter")
			controller.free()
			return
		var helper_baseline := _helper_pose_rotations(adapter)
		var segment_baseline := _segment_lengths(adapter)
		var previous := adapter.landmarks()
		var frame := scenario[1] as SkierAnimationFrame
		for _index: int in 120:
			controller.apply_frame(frame, STEP)
			var current := adapter.landmarks()
			for key: String in ["pelvis", "left_knee", "right_knee", "left_boot", "right_boot", "left_hand", "right_hand"]:
				_check(current.has(key) and (current[key] as Vector3).is_finite(), "%s produced a missing or non-finite %s landmark" % [scenario[0], key])
				if previous.has(key) and current.has(key):
					maximum_landmark_step = maxf(maximum_landmark_step, (current[key] as Vector3).distance_to(previous[key] as Vector3))
			previous = current
		await get_tree().process_frame
		maximum_orientation_error = maxf(maximum_orientation_error, _mapped_orientation_error(adapter, controller.pose_driver))
		maximum_helper_drift = maxf(maximum_helper_drift, _helper_pose_drift(adapter, helper_baseline))
		maximum_segment_drift = maxf(maximum_segment_drift, _segment_length_drift(adapter, segment_baseline))
		var visual := adapter.landmarks()
		var expected_ski_gap := controller.pose_driver.rest_position(&"left_ski").length()
		for side: StringName in [&"left", &"right"]:
			var ski_gap := (adapter.equipment_nodes[StringName(side + "_ski")] as Node3D).global_position.distance_to(visual[String(side + "_boot")] as Vector3)
			var pole_gap := (adapter.equipment_nodes[StringName(side + "_pole")] as Node3D).global_position.distance_to(visual[String(side + "_hand")] as Vector3)
			_check(absf(ski_gap - expected_ski_gap) < 0.003, "%s %s ski mount drifted from its boot (%.3fm)" % [scenario[0], side, ski_gap])
			_check(pole_gap < 0.003, "%s %s pole mount drifted from its hand (%.3fm)" % [scenario[0], side, pole_gap])
		controller.free()
	print("SKELETON_RIG_SWEEP poses=%d orientation=%.4f helper=%.4f segment=%.4f landmark_step=%.4f" % [
		scenarios.size(), maximum_orientation_error, maximum_helper_drift, maximum_segment_drift, maximum_landmark_step,
	])
	_check(maximum_orientation_error < 0.01, "Production mapped-bone orientation diverged by %.3f radians" % maximum_orientation_error)
	_check(maximum_helper_drift < 0.001, "Production helper bones twisted by %.3f radians" % maximum_helper_drift)
	_check(maximum_segment_drift < 0.003, "Production limb segments stretched by %.3fm" % maximum_segment_drift)
	_check(maximum_landmark_step < 0.3, "Production pose sweep produced a %.3fm one-frame landmark snap" % maximum_landmark_step)

func _test_production_grab_reach() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		return
	var maximum_reach := 0.0
	var maximum_wrist_error := 0.0
	var maximum_segment_drift := 0.0
	for pose: int in GRAB_POSES:
		var controller := _production_controller()
		var adapter := controller.rig_adapter as SkeletonSkierRig
		if adapter == null:
			_check(false, "Production grab reach could not create the Skeleton3D adapter")
			controller.free()
			return
		var helper_baseline := _helper_pose_rotations(adapter)
		var segment_baseline := _segment_lengths(adapter)
		var frame := _air_frame()
		frame.grab_pose = pose
		frame.grab_amount = 1.0
		frame.grab_input_strength = 1.0
		frame.grab_hold_time = 0.8
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
		var pose_max_hold_error := 0.0
		var pose_max_wrist_error := 0.0
		var minimum_hold_contact := 1.0
		var hold_frames := 0
		for _index: int in 140:
			controller.apply_frame(frame, STEP)
			var snapshot := controller.debug_snapshot()
			var definition := controller._grab_definition as GrabAnimationDefinition
			if str(snapshot.get("grab_phase", "")) == "HOLD" and definition != null:
				hold_frames += 1
				minimum_hold_contact = minf(minimum_hold_contact, float(snapshot.get("grab_contact_weight", 0.0)))
				for hand_side: StringName in _grab_hand_sides(definition):
					var reach_error := _production_grab_error(adapter, definition, hand_side)
					var wrist_error := _production_wrist_error(adapter, definition, hand_side)
					pose_max_hold_error = maxf(pose_max_hold_error, reach_error)
					pose_max_wrist_error = maxf(pose_max_wrist_error, wrist_error)
		var final_snapshot := controller.debug_snapshot()
		var definition := controller._grab_definition as GrabAnimationDefinition
		var final_reach := 0.0
		var final_wrist_error := 0.0
		if definition != null:
			for hand_side: StringName in _grab_hand_sides(definition):
				final_reach = maxf(final_reach, _production_grab_error(adapter, definition, hand_side))
				final_wrist_error = maxf(final_wrist_error, _production_wrist_error(adapter, definition, hand_side))
		maximum_reach = maxf(maximum_reach, maxf(pose_max_hold_error, final_reach))
		maximum_wrist_error = maxf(maximum_wrist_error, maxf(pose_max_wrist_error, final_wrist_error))
		maximum_segment_drift = maxf(maximum_segment_drift, _segment_length_drift(adapter, segment_baseline))
		var helper_drift := _helper_pose_drift(adapter, helper_baseline)
		print("SKELETON_RIG_GRAB pose=%s reach=%.3f hold_frames=%d contact_min=%.2f wrist=%.3f helper=%.3f solver=%s" % [
			definition.display_name if definition != null else "NONE",
			maxf(pose_max_hold_error, final_reach), hold_frames, minimum_hold_contact,
			maxf(pose_max_wrist_error, final_wrist_error), helper_drift,
			adapter.grab_debug_snapshot().get("solver", "IDLE"),
		])
		_check(hold_frames > 20, "%s never settled into a sustained HOLD" % (definition.display_name if definition != null else pose))
		_check(maxf(pose_max_hold_error, final_reach) <= 0.1205, "%s exceeded the 0.12m visual palm envelope" % (definition.display_name if definition != null else pose))
		_check(minimum_hold_contact > 0.8, "%s contact weight was not stable during HOLD" % (definition.display_name if definition != null else pose))
		_check(str(final_snapshot.get("grab_phase", "")) == "HOLD", "%s finished outside HOLD" % (definition.display_name if definition != null else pose))
		_check(str(adapter.grab_debug_snapshot().get("solver", "")) == "CONTACT", "%s production solver did not report CONTACT" % (definition.display_name if definition != null else pose))
		_check(_segment_length_drift(adapter, segment_baseline) < 0.003, "%s changed a measured arm segment length" % (definition.display_name if definition != null else pose))
		if pose == TrickController.GrabPose.MUTE_LEFT or pose == TrickController.GrabPose.MUTE_RIGHT:
			_check(helper_drift > 0.02, "%s did not activate production helper bones for the cross-body reach" % (definition.display_name if definition != null else pose))
			var clavicle_name: StringName = &"shoulder.L" if pose == TrickController.GrabPose.MUTE_LEFT else &"shoulder.R"
			_check(_helper_pose_delta(adapter, helper_baseline, clavicle_name) > 0.02, "%s did not activate its clavicle helper" % (definition.display_name if definition != null else pose))
		controller.free()
	print("SKELETON_RIG_GRAB_SUMMARY poses=%d maximum_reach=%.4f maximum_wrist=%.4f maximum_segment_drift=%.4f" % [
		GRAB_POSES.size(), maximum_reach, maximum_wrist_error, maximum_segment_drift,
	])
	_check(maximum_reach <= 0.1205, "Production grab palm exceeded %.3fm" % maximum_reach)
	_check(maximum_wrist_error < 0.08, "Production wrist orientation diverged by %.3f radians" % maximum_wrist_error)

func _test_production_contact_envelope() -> void:
	const body_path := "res://assets/characters/skier/skier_body.glb"
	if not ResourceLoader.exists(body_path):
		return
	var controller := _production_controller()
	var adapter := controller.rig_adapter as SkeletonSkierRig
	var target := adapter.grab_target(&"left", &"binding_outside")
	_check(target != null, "Production contact-envelope fixture could not find the attached ski marker")
	if target == null:
		controller.free()
		return
	target.position += Vector3(0.0, 2.0, 0.0)
	var frame := _air_frame()
	frame.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.8
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	for _index: int in 140:
		controller.apply_frame(frame, STEP)
	var snapshot := controller.debug_snapshot()
	var definition := controller._grab_definition as GrabAnimationDefinition
	var reach_error := _production_grab_error(adapter, definition, &"left") if definition != null else 0.0
	print("SKELETON_RIG_ENVELOPE outside_error=%.3f phase=%s contact=%.2f" % [reach_error, snapshot.get("grab_phase", ""), snapshot.get("grab_contact_weight", 0.0)])
	_check(reach_error > 0.12, "An out-of-envelope production marker was reported as visual contact")
	_check(str(snapshot.get("grab_phase", "")) != "HOLD", "Production lifecycle entered HOLD outside the 0.12m maintenance envelope")
	_check(float(snapshot.get("grab_contact_weight", 0.0)) < 0.72, "Out-of-envelope production marker accumulated HOLD contact weight")
	controller.free()

func _grab_hand_sides(definition: GrabAnimationDefinition) -> Array[StringName]:
	var result: Array[StringName] = []
	if definition.hand == GrabAnimationDefinition.Hand.LEFT or definition.hand == GrabAnimationDefinition.Hand.BOTH:
		result.append(&"left")
	if definition.hand == GrabAnimationDefinition.Hand.RIGHT or definition.hand == GrabAnimationDefinition.Hand.BOTH:
		result.append(&"right")
	return result

func _target_name(target: int) -> StringName:
	return [&"", &"binding_outside", &"binding_inside", &"nose", &"tail"][target]

func _target_side_for_hand(definition: GrabAnimationDefinition, hand_side: StringName) -> StringName:
	if definition.target_ski == GrabAnimationDefinition.Ski.BOTH:
		return hand_side
	return &"left" if definition.target_ski == GrabAnimationDefinition.Ski.LEFT else &"right"

func _production_grab_error(adapter: SkeletonSkierRig, definition: GrabAnimationDefinition, hand_side: StringName) -> float:
	if adapter == null or definition == null:
		return INF
	var target := adapter.grab_target(_target_side_for_hand(definition, hand_side), _target_name(definition.target))
	if target == null:
		return INF
	return adapter.grab_contact_point(hand_side).distance_to(target.global_position)

func _production_wrist_error(adapter: SkeletonSkierRig, definition: GrabAnimationDefinition, hand_side: StringName) -> float:
	if adapter == null or definition == null:
		return INF
	var target := adapter.grab_target(_target_side_for_hand(definition, hand_side), _target_name(definition.target))
	if target == null:
		return INF
	var correction := adapter._as_quaternion(adapter.profile.hand_wrist_corrections.get(hand_side, Quaternion.IDENTITY), Quaternion.IDENTITY)
	var expected := (target.global_transform.basis.orthonormalized().get_rotation_quaternion() * correction).normalized()
	var actual := adapter._bone_world(StringName("%s_hand" % hand_side)).basis.orthonormalized().get_rotation_quaternion()
	return _quaternion_delta(expected, actual)

func _production_controller() -> SkierAnimationController:
	var controller := SkierAnimationController.new()
	controller.rig_mode = SkierAnimationController.RigMode.SKELETON
	add_child(controller)
	return controller

func _mapped_orientation_error(adapter: SkeletonSkierRig, driver: SkierPoseDriver) -> float:
	var maximum := 0.0
	var canonical_world: Dictionary = {}
	for sequence: Array in SkeletonSkierRig.SYNC_SEQUENCES:
		var root: StringName = sequence[0]
		var context: StringName = SkeletonSkierRig.SEQUENCE_ROOT_CONTEXT.get(root, &"")
		var canonical: Quaternion = canonical_world.get(context, Quaternion.IDENTITY)
		for semantic: StringName in sequence:
			var delta := Quaternion.from_euler(driver.joint(semantic).rotation)
			if adapter.profile.axis_corrections.has(semantic):
				var correction := adapter._as_quaternion(adapter.profile.axis_corrections[semantic], Quaternion.IDENTITY)
				delta = correction * delta * correction.inverse()
			canonical = canonical * delta
			var expected := adapter._axis.inverse() * (canonical * (adapter._neutral_world[semantic] as Quaternion))
			var actual := adapter.skeleton.get_bone_global_pose(int(adapter.bone_indices[semantic])).basis.orthonormalized().get_rotation_quaternion()
			maximum = maxf(maximum, _quaternion_delta(expected, actual))
			canonical_world[semantic] = canonical
	return maximum

func _helper_pose_rotations(adapter: SkeletonSkierRig) -> Dictionary:
	var result: Dictionary = {}
	for name: StringName in [&"spine.002", &"spine.004", &"shoulder.L", &"shoulder.R"]:
		var index := adapter.skeleton.find_bone(name)
		if index >= 0:
			result[name] = adapter.skeleton.get_bone_pose_rotation(index)
	return result

func _helper_pose_drift(adapter: SkeletonSkierRig, baseline: Dictionary) -> float:
	var maximum := 0.0
	for name: StringName in baseline:
		maximum = maxf(maximum, _quaternion_delta(baseline[name] as Quaternion, adapter.skeleton.get_bone_pose_rotation(adapter.skeleton.find_bone(name))))
	return maximum

func _helper_pose_delta(adapter: SkeletonSkierRig, baseline: Dictionary, name: StringName) -> float:
	if adapter == null or not baseline.has(name):
		return 0.0
	var index := adapter.skeleton.find_bone(name)
	if index < 0:
		return 0.0
	return _quaternion_delta(baseline[name] as Quaternion, adapter.skeleton.get_bone_pose_rotation(index))

func _segment_lengths(adapter: SkeletonSkierRig) -> Dictionary:
	var result: Dictionary = {}
	for pair: Array in [
		[&"left_hip", &"left_knee"], [&"left_knee", &"left_boot"],
		[&"right_hip", &"right_knee"], [&"right_knee", &"right_boot"],
		[&"left_shoulder", &"left_elbow"], [&"left_elbow", &"left_hand"],
		[&"right_shoulder", &"right_elbow"], [&"right_elbow", &"right_hand"],
	]:
		result[StringName("%s:%s" % [pair[0], pair[1]])] = adapter._bone_world(pair[0]).origin.distance_to(adapter._bone_world(pair[1]).origin)
	return result

func _segment_length_drift(adapter: SkeletonSkierRig, baseline: Dictionary) -> float:
	var current := _segment_lengths(adapter)
	var maximum := 0.0
	for key: StringName in baseline:
		maximum = maxf(maximum, absf(float(current[key]) - float(baseline[key])))
	return maximum

func _quaternion_delta(first: Quaternion, second: Quaternion) -> float:
	return 2.0 * acos(clampf(absf(first.dot(second)), -1.0, 1.0))

func _ground_frame(carve: float, switch_stance: bool) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GROUND
	frame.grounded = true
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.82
	frame.contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	frame.edge = carve
	frame.turn_input = carve
	frame.turn_rate = -carve * 0.9
	frame.lateral_acceleration = -carve * 11.0
	frame.carve_ratio = 1.0
	frame.switch_stance = switch_stance
	return frame

func _air_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_AIR
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.82
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.9
	frame.takeoff_upward_speed = 4.2
	frame.air_time = 0.55
	frame.air_upward_velocity = 0.1
	frame.predicted_landing_time = 0.5
	return frame

func _trick_frame(kind: int, velocity: Vector3, accumulated: Vector3) -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = kind
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = velocity
	frame.rotation_accumulated = accumulated
	return frame

func _style_frame(pose: int) -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.style_pose = pose
	frame.style_amount = 1.0
	return frame

func _rail_frame(pose: int) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GRIND
	frame.speed_mps = 13.0
	frame.speed_ratio = 0.55
	frame.rail_speed = 13.0
	frame.rail_pose = pose
	frame.rail_distance_to_end = 5.0
	return frame

func _landing_frame() -> SkierAnimationFrame:
	var frame := _ground_frame(0.0, false)
	frame.landing_event_active = true
	frame.landing_impact_severity = 0.5
	frame.landing_air_time = 1.0
	frame.landing_outcome = LandingSolver.Outcome.CLEAN
	return frame

func _crash_frame(stage: int, elapsed: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_BAIL
	frame.crash_reason = CrashContext.Reason.FEATURE_IMPACT
	frame.crash_stage = stage
	frame.crash_elapsed = elapsed
	frame.crash_incoming_velocity = Vector3(6.0, -3.0, -14.0)
	frame.crash_current_velocity = Vector3(5.0, -2.0, -11.0)
	frame.crash_impact_speed = 9.0
	frame.crash_lateral_bias = 1.0
	frame.crash_angular_speed = 4.5
	frame.crash_rest_detected = stage == CrashContext.Stage.REST
	return frame

func _synthetic_profile() -> SkierSkeletonProfile:
	var root := Node3D.new()
	root.name = "SyntheticBody"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	var indices: Dictionary = {}
	_add_bone(skeleton, indices, &"Hips", &"", Vector3.ZERO)
	_add_bone(skeleton, indices, &"Spine", &"Hips", Vector3(0.0, 0.14, 0.0))
	_add_bone(skeleton, indices, &"Chest", &"Spine", Vector3(0.0, 0.42, 0.0))
	_add_bone(skeleton, indices, &"Head", &"Chest", Vector3(0.0, 0.38, 0.0))
	_add_bone(skeleton, indices, &"LeftUpperLeg", &"Hips", Vector3(-0.27, -0.04, 0.0))
	_add_bone(skeleton, indices, &"LeftLowerLeg", &"LeftUpperLeg", Vector3(0.0, -0.52, 0.0))
	_add_bone(skeleton, indices, &"LeftFoot", &"LeftLowerLeg", Vector3(0.0, -0.49, -0.03))
	_add_bone(skeleton, indices, &"RightUpperLeg", &"Hips", Vector3(0.27, -0.04, 0.0))
	_add_bone(skeleton, indices, &"RightLowerLeg", &"RightUpperLeg", Vector3(0.0, -0.52, 0.0))
	_add_bone(skeleton, indices, &"RightFoot", &"RightLowerLeg", Vector3(0.0, -0.49, -0.03))
	_add_bone(skeleton, indices, &"LeftUpperArm", &"Chest", Vector3(-0.4, 0.24, 0.0))
	_add_bone(skeleton, indices, &"LeftLowerArm", &"LeftUpperArm", Vector3(0.0, -0.42, 0.0))
	_add_bone(skeleton, indices, &"LeftHand", &"LeftLowerArm", Vector3(0.0, -0.37, 0.0))
	_add_bone(skeleton, indices, &"RightUpperArm", &"Chest", Vector3(0.4, 0.24, 0.0))
	_add_bone(skeleton, indices, &"RightLowerArm", &"RightUpperArm", Vector3(0.0, -0.42, 0.0))
	_add_bone(skeleton, indices, &"RightHand", &"RightLowerArm", Vector3(0.0, -0.37, 0.0))
	var packed := PackedScene.new()
	var packed_result := packed.pack(root)
	_check(packed_result == OK, "Could not pack the synthetic Skeleton3D fixture")
	root.free()
	var profile := SkierSkeletonProfile.new()
	profile.body_scene = packed
	profile.require_skinned_mesh = false
	return profile

func _add_bone(skeleton: Skeleton3D, indices: Dictionary, bone_name: StringName, parent_name: StringName, rest_position: Vector3) -> void:
	var index := skeleton.add_bone(bone_name)
	indices[bone_name] = index
	if parent_name != &"":
		skeleton.set_bone_parent(index, int(indices[parent_name]))
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, rest_position))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
