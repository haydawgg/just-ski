extends Node3D

const STEP := 1.0 / 60.0
const AUDIT_RATES: Array[int] = [30, 60, 120]
const GRAB_LIBRARY := preload("res://resources/animation/default_grab_animation_library.tres")
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := SkierAnimationController.new()
	rig.rig_mode = SkierAnimationController.RigMode.SKELETON
	add_child(rig)
	var adapter := rig.rig_adapter as SkeletonSkierRig
	var frame := SkierAnimationFrame.new()
	frame.grounded = true
	frame.left_grounded = true
	frame.right_grounded = true
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	frame.speed_mps = 12.0
	frame.speed_ratio = 0.55
	var neutral_height := 0.0
	for phase: int in 3:
		frame.compression = 1.0 if phase == 1 else 0.0
		if phase == 2:
			var air := SkierAnimationFrame.new()
			air.locomotion_state = 1
			air.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
			air.takeoff_upward_speed = 4.2
			air.takeoff_charge = 0.9
			rig.trigger(SkierAnimationController.AnimationEvent.POP, 0.9)
			for tick: int in 36:
				air.air_time = tick * STEP
				air.air_upward_velocity = 4.2 - air.air_time * 9.8
				rig.position.z -= frame.speed_mps * STEP
				rig.apply_frame(air, STEP)
			rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.6)
			frame.landing_event_active = true
			frame.landing_impact_severity = 0.6
			frame.landing_air_time = 0.9
		var minimum_height := INF
		var max_contact_error := 0.0
		var max_retarget_error := 0.0
		var first_contact_error := 0.0
		for tick: int in (60 if phase < 2 else 18):
			rig.position.z -= frame.speed_mps * STEP
			frame.left_ski_target_world = Transform3D(Basis.IDENTITY, rig.position + Vector3(-0.27, -0.21, -0.11))
			frame.right_ski_target_world = Transform3D(Basis.IDENTITY, rig.position + Vector3(0.27, -0.21, -0.11))
			rig.apply_frame(frame, STEP)
			var visual := adapter.landmarks()
			if phase == 2 and tick < 3:
				first_contact_error = maxf(first_contact_error, rig.left_ski.global_position.distance_to(frame.left_ski_target_world.origin))
			minimum_height = minf(minimum_height, (visual.pelvis as Vector3).y)
			if tick > 12:
				_check((visual.pelvis as Vector3).distance_to(rig.pelvis.global_position) < 0.03, "production pelvis translation uses a different axis from its driver")
				max_contact_error = maxf(max_contact_error, rig.left_ski.global_position.distance_to(frame.left_ski_target_world.origin))
				max_retarget_error = maxf(max_retarget_error, (visual.left_boot as Vector3).distance_to(rig.left_boot.global_position))
		print("PRESENTATION_CONTACT phase=%d target_error=%.3f first_error=%.3f retarget_error=%.3f pelvis_min=%.3f" % [phase, max_contact_error, first_contact_error, max_retarget_error, minimum_height])
		_check(max_contact_error < 0.12, "moving contact target trails skier in phase %d: %.3fm" % [phase, max_contact_error])
		_check(max_retarget_error < 0.10, "visible boot diverges from solved boot in phase %d: %.3fm" % [phase, max_retarget_error])
		if phase == 0:
			neutral_height = minimum_height
		elif phase == 1:
			_check(neutral_height - minimum_height > 0.15, "charge does not visibly lower production pelvis")
		else:
			_check(neutral_height - minimum_height > 0.07, "landing does not visibly compress production pelvis")
			_check(first_contact_error < 0.18, "landing contact is visibly late on the first grounded frames: %.3fm" % first_contact_error)
	for pose: int in _grab_pose_ids():
		frame.reset()
		frame.locomotion_state = 1
		frame.air_time = 0.6
		frame.takeoff_upward_speed = 4.0
		frame.grab_pose = pose
		frame.grab_amount = 1.0
		frame.grab_input_strength = 1.0
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
		for tick: int in 100:
			frame.grab_hold_time = tick * STEP
			rig.apply_frame(frame, STEP)
		var chest_before := adapter._bone_world(&"chest").basis.get_rotation_quaternion()
		adapter.sync_pose(STEP, [])
		var authored_chest := adapter._bone_world(&"chest").basis.get_rotation_quaternion()
		var assist := chest_before.angle_to(authored_chest)
		print("PRESENTATION_GRAB pose=%d spine_assist=%.3f" % [pose, assist])
		_check(assist < 0.65, "grab IK overwhelms authored torso for pose %d: %.3frad" % [pose, assist])
	_test_flip_rhythm(rig)
	_test_contact_advection(rig)
	_test_grab_shoulder_envelope()
	_test_grab_transition_matrix()
	_test_style_pose_matrix()
	if failures.is_empty():
		print("PRESENTATION_QUALITY_PASS: moving contact, production compression and bounded grab torso")
	else:
		for failure: String in failures:
			push_error("PRESENTATION_QUALITY_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_flip_rhythm(rig: SkierAnimationController) -> void:
	for kind: int in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP]:
		var frame := SkierAnimationFrame.new()
		frame.locomotion_state = 1
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = kind
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.takeoff_upward_speed = 4.2
		var side := 1.0 if kind == TrickCommand.Kind.FRONTFLIP else -1.0
		frame.angular_velocity.x = side * TAU / 1.2
		var knee_min := INF
		var knee_max := -INF
		var previous := rig.left_knee.quaternion
		var largest_step := 0.0
		for tick: int in 72:
			frame.air_time = tick * STEP
			frame.rotation_accumulated.x = frame.angular_velocity.x * frame.air_time
			rig.apply_frame(frame, STEP)
			if tick > 12:
				knee_min = minf(knee_min, rig.left_knee.rotation.x)
				knee_max = maxf(knee_max, rig.left_knee.rotation.x)
				largest_step = maxf(largest_step, previous.angle_to(rig.left_knee.quaternion))
			previous = rig.left_knee.quaternion
		print("PRESENTATION_FLIP kind=%d flex_range=%.3f max_step=%.3f" % [kind, knee_max - knee_min, largest_step])
		_check(knee_max - knee_min > 0.4, "flip has no readable tuck/open rhythm: %d" % kind)
		_check(largest_step < 0.25, "flip tuck/open snaps: %d" % kind)

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)

func _test_contact_advection(rig: SkierAnimationController) -> void:
	# Reproduce downhill root travel plus the downward seating seen at impact.
	var normal := Vector3(0.0, 1.0, 0.3).normalized()
	var tangent := Vector3.FORWARD.slide(normal).normalized() * 0.6
	var previous := Transform3D(Basis.IDENTITY, Vector3(-0.27, 0.0, -0.11))
	var motion := Transform3D(Basis.IDENTITY, tangent - normal * 0.2)
	var moved := rig._advect_ski_contact(previous, motion, normal)
	_check(absf((moved.origin - previous.origin).dot(normal)) < 0.0001, "root seating drags the ski target beneath the support plane")
	_check((moved.origin - previous.origin).distance_to(tangent) < 0.0001, "moving ski contact loses tangential feedforward")

func _test_grab_shoulder_envelope() -> void:
	for pose: int in _grab_pose_ids():
		var test_rig := SkierAnimationController.new()
		test_rig.rig_mode = SkierAnimationController.RigMode.SKELETON
		add_child(test_rig)
		var adapter := test_rig.rig_adapter as SkeletonSkierRig
		var baseline_left := adapter._bone_world(&"left_shoulder").basis.get_rotation_quaternion()
		var baseline_right := adapter._bone_world(&"right_shoulder").basis.get_rotation_quaternion()
		var frame := SkierAnimationFrame.new()
		frame.locomotion_state = 1
		frame.air_time = 0.6
		frame.takeoff_upward_speed = 4.0
		frame.grab_pose = pose
		frame.grab_amount = 1.0
		frame.grab_input_strength = 1.0
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
		for tick: int in 100:
			frame.grab_hold_time = tick * STEP
			test_rig.apply_frame(frame, STEP)
		var left_angle := baseline_left.angle_to(adapter._bone_world(&"left_shoulder").basis.get_rotation_quaternion())
		var right_angle := baseline_right.angle_to(adapter._bone_world(&"right_shoulder").basis.get_rotation_quaternion())
		var grab_metrics := adapter.grab_debug_snapshot()
		print("PRESENTATION_SHOULDER pose=%d left=%.3f right=%.3f reach=(%.3f,%.3f)" % [pose, left_angle, right_angle, float(grab_metrics.get("left_reach_error", 0.0)), float(grab_metrics.get("right_reach_error", 0.0))])
		_check(maxf(left_angle, right_angle) < 1.55, "deep grab over-rotates production shoulder for pose %d: %.3frad" % [pose, maxf(left_angle, right_angle)])
		test_rig.queue_free()

func _grab_pose_ids() -> Array[int]:
	var pose_ids: Array[int] = []
	var definitions: Array = GRAB_LIBRARY.get("definitions") as Array
	for definition: Resource in definitions:
		if definition == null:
			continue
		var pose := int(definition.get("pose_id"))
		if pose != TrickController.GrabPose.NONE and not pose_ids.has(pose):
			pose_ids.append(pose)
	pose_ids.sort()
	return pose_ids

func _test_grab_transition_matrix() -> void:
	const phase_durations: Array[float] = [0.30, 0.55, 0.80, 0.35, 0.60]
	var pose_ids := _grab_pose_ids()
	_check(pose_ids.size() == TrickController.GrabPose.DOUBLE, "production grab library exposes %d poses instead of the expected %d" % [pose_ids.size(), TrickController.GrabPose.DOUBLE])
	var rate_results: Array[Dictionary] = []
	for hz: int in AUDIT_RATES:
		var delta := 1.0 / float(hz)
		var test_rig := SkierAnimationController.new()
		test_rig.rig_mode = SkierAnimationController.RigMode.SKELETON
		add_child(test_rig)
		var adapter := test_rig.rig_adapter as SkeletonSkierRig
		var max_reach_error := 0.0
		var maximum_hold_final_error := 0.0
		var max_pole_offset := 0.0
		var max_boot_binding_error := 0.0
		var maximum_joint_step := 0.0
		var maximum_joint_step_label := ""
		var landing_seen := false
		for pose: int in pose_ids:
			# Settle the shared airborne pose before measuring this grab. The
			# matrix should measure grab transitions, not the first frame of an
			# unrelated ground-to-air pose change.
			var warmup := SkierAnimationFrame.new()
			warmup.locomotion_state = 1
			warmup.air_time = 0.72
			warmup.takeoff_upward_speed = 4.0
			warmup.speed_mps = 16.0
			warmup.speed_ratio = 0.75
			warmup.trick_phase = TrickCommand.PresentationPhase.GRAB
			for _warmup_tick: int in maxi(1, int(round(0.50 * float(hz)))):
				test_rig.apply_frame(warmup, delta)
			var peak_pose_weight := 0.0
			var peak_contact_weight := 0.0
			var hold_reach_error := 0.0
			var contact_seen := false
			var previous_rotations: Array[Quaternion] = [
				test_rig.pelvis.quaternion,
				test_rig.chest.quaternion,
				test_rig.head.quaternion,
				test_rig.left_knee.quaternion,
				test_rig.right_knee.quaternion,
				test_rig.left_pole.quaternion,
				test_rig.right_pole.quaternion,
			]
			var grab_hand := _grab_hand_for_pose(pose)
			for phase: int in 5:
				var ticks := maxi(1, int(round(phase_durations[phase] * float(hz))))
				for tick: int in ticks:
					var progress := float(tick + 1) / float(ticks)
					var frame := SkierAnimationFrame.new()
					frame.locomotion_state = 1
					frame.air_time = 0.72
					frame.takeoff_upward_speed = 4.0
					frame.speed_mps = 16.0
					frame.speed_ratio = 0.75
					frame.trick_phase = TrickCommand.PresentationPhase.GRAB
					var active := phase >= 1 and phase < 4
					frame.grab_pose = pose if active else TrickController.GrabPose.NONE
					frame.grab_amount = 1.0 if phase == 2 else smoothstep(0.0, 1.0, progress) if phase == 1 else 0.0
					frame.grab_input_strength = frame.grab_amount
					frame.grab_hold_time = delta * float(tick + 1) if phase == 2 else 0.0
					frame.grab_release_time = delta * float(tick + 1) if phase >= 3 else 0.0
					test_rig.apply_frame(frame, delta)
					var snapshot := test_rig.debug_snapshot()
					var adapter_snapshot := adapter.grab_debug_snapshot()
					var current_hold_error := 0.0
					if phase in [1, 2] and frame.grab_amount > 0.1:
						if grab_hand == 1 or grab_hand == 3:
							var left_error := float(adapter_snapshot.get("left_reach_error", 0.0))
							if phase == 2:
								current_hold_error = maxf(current_hold_error, left_error)
								hold_reach_error = maxf(hold_reach_error, left_error)
								max_reach_error = maxf(max_reach_error, left_error)
						if grab_hand == 2 or grab_hand == 3:
							var right_error := float(adapter_snapshot.get("right_reach_error", 0.0))
							if phase == 2:
								current_hold_error = maxf(current_hold_error, right_error)
								hold_reach_error = maxf(hold_reach_error, right_error)
								max_reach_error = maxf(max_reach_error, right_error)
						if phase == 2 and str(adapter_snapshot.get("solver", "")) == "CONTACT":
							contact_seen = true
					peak_pose_weight = maxf(peak_pose_weight, float(snapshot.get("grab_pose_weight", 0.0)))
					peak_contact_weight = maxf(peak_contact_weight, float(snapshot.get("grab_contact_weight", 0.0)))
					var attachment := test_rig.equipment_attachment_snapshot()
					if bool(attachment.get("valid", false)):
						max_pole_offset = maxf(max_pole_offset, maxf(float(attachment.get("left_pole_hand_offset_m", 0.0)), float(attachment.get("right_pole_hand_offset_m", 0.0))))
						max_boot_binding_error = maxf(max_boot_binding_error, maxf(float(attachment.get("left_boot_binding_position_error", 0.0)), float(attachment.get("right_boot_binding_position_error", 0.0))))
					var landmarks := adapter.landmarks()
					for landmark_name: String in landmarks:
						var landmark_value = landmarks[landmark_name]
						if landmark_value is Vector3 and not (landmark_value as Vector3).is_finite():
							_check(false, "grab audit produced a non-finite %s landmark at %d Hz" % [landmark_name, hz])
					var rotations: Array[Quaternion] = [
						test_rig.pelvis.quaternion,
						test_rig.chest.quaternion,
						test_rig.head.quaternion,
						test_rig.left_knee.quaternion,
						test_rig.right_knee.quaternion,
						test_rig.left_pole.quaternion,
						test_rig.right_pole.quaternion,
					]
					if not previous_rotations.is_empty():
						for index: int in rotations.size():
							var joint_step := previous_rotations[index].angle_to(rotations[index])
							if joint_step > maximum_joint_step:
								maximum_joint_step = joint_step
								maximum_joint_step_label = "%s pose=%d phase=%d tick=%d" % [["pelvis", "chest", "head", "left_knee", "right_knee", "left_pole", "right_pole"][index], pose, phase, tick]
					previous_rotations = rotations
					# Keep the adapter snapshot in the output path of the audit so
					# future threshold failures identify the affected solver values.
					if adapter_snapshot.is_empty():
						_check(false, "grab audit lost production adapter telemetry at %d Hz" % hz)
					if phase == 2:
						hold_reach_error = current_hold_error
			_check(peak_pose_weight > 0.55, "grab %d never reached a readable pose weight at %d Hz" % [pose, hz])
			_check(peak_contact_weight > 0.12, "grab %d never established contact weight at %d Hz" % [pose, hz])
			_check(contact_seen, "grab %d never reached production CONTACT during HOLD at %d Hz" % [pose, hz])
			_check(hold_reach_error <= 0.1205, "grab %d finished HOLD outside the 0.12m reach envelope at %d Hz: %.3fm" % [pose, hz, hold_reach_error])
			maximum_hold_final_error = maxf(maximum_hold_final_error, hold_reach_error)
			print("PRESENTATION_GRAB_AUDIT hz=%d pose=%d name=%s peak_pose=%.3f peak_contact=%.3f" % [hz, pose, TrickController.GRAB_NAMES[pose], peak_pose_weight, peak_contact_weight])
			# A clean landing handoff after each grab makes release/recovery a
			# measured transition rather than an isolated held-pose check.
			var landing := SkierAnimationFrame.new()
			landing.locomotion_state = 0
			landing.grounded = true
			landing.left_grounded = true
			landing.right_grounded = true
			landing.contact_confidence = 1.0
			landing.left_contact_confidence = 1.0
			landing.right_contact_confidence = 1.0
			landing.landing_event_active = true
			landing.landing_impact_severity = 0.55
			landing.landing_air_time = 0.72
			landing.speed_mps = 16.0
			test_rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.55, 0.0)
			for tick: int in maxi(1, int(round(0.28 * float(hz)))):
				test_rig.apply_frame(landing, delta)
				if str(test_rig.debug_snapshot().get("landing_phase", "Idle")) != "Idle":
					landing_seen = true
			landing.landing_event_active = false
			for tick: int in maxi(1, int(round(0.4 * float(hz)))):
				test_rig.apply_frame(landing, delta)
		_check(landing_seen, "grab audit never entered a measurable landing handoff at %d Hz" % hz)
		_check(max_pole_offset < 1.6, "pole-to-hand attachment exceeded the production bound at %d Hz: %.3fm" % [hz, max_pole_offset])
		_check(max_boot_binding_error < 0.12, "boot-to-binding attachment exceeded the deterministic audit bound at %d Hz: %.3fm" % [hz, max_boot_binding_error])
		var normalized_joint_rate := maximum_joint_step / maxf(delta, 0.0001)
		var allowed_joint_step := 0.30 * delta / STEP
		_check(maximum_joint_step < allowed_joint_step, "grab transition exceeded the 60 Hz continuity rate at %d Hz: %.3f > %.3f (%s)" % [hz, maximum_joint_step, allowed_joint_step, maximum_joint_step_label])
		print("PRESENTATION_GRAB_RATE hz=%d poses=%d hold_final=%.3f hold_peak=%.3f pole=%.3f boot=%.3f joint_step=%.3f joint_rate=%.3f (%s)" % [hz, pose_ids.size(), maximum_hold_final_error, max_reach_error, max_pole_offset, max_boot_binding_error, maximum_joint_step, normalized_joint_rate, maximum_joint_step_label])
		rate_results.append({"hz": hz, "reach": maximum_hold_final_error, "pole": max_pole_offset, "boot": max_boot_binding_error, "joint_step": maximum_joint_step, "joint_rate": normalized_joint_rate})
		test_rig.queue_free()
	if rate_results.size() == AUDIT_RATES.size():
		var reference := rate_results[-1]
		for result: Dictionary in rate_results:
			_check(absf(float(result.reach) - float(reference.reach)) < 0.08, "grab reach envelope diverged across frame rates (%d Hz vs 120 Hz)" % int(result.hz))
			_check(absf(float(result.boot) - float(reference.boot)) < 0.05, "boot attachment diverged across frame rates (%d Hz vs 120 Hz)" % int(result.hz))
			_check(absf(float(result.joint_rate) - float(reference.joint_rate)) < 4.0, "grab continuity rate diverged across frame rates (%d Hz vs 120 Hz)" % int(result.hz))

func _grab_hand_for_pose(pose: int) -> int:
	var definitions: Array = GRAB_LIBRARY.get("definitions") as Array
	for definition: Resource in definitions:
		if definition != null and int(definition.get("pose_id")) == pose:
			return int(definition.get("hand"))
	return 0

func _test_style_pose_matrix() -> void:
	for style: int in range(TrickController.StylePose.SPREAD_EAGLE, TrickController.StylePose.SHIFTY_RIGHT + 1):
		var test_rig := SkierAnimationController.new()
		test_rig.rig_mode = SkierAnimationController.RigMode.SKELETON
		add_child(test_rig)
		var frame := SkierAnimationFrame.new()
		frame.locomotion_state = 1
		frame.air_time = 0.68
		frame.takeoff_upward_speed = 4.0
		frame.style_pose = style
		frame.style_amount = 1.0
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
		for tick: int in 72:
			test_rig.apply_frame(frame, STEP)
		var snapshot := test_rig.debug_snapshot()
		print("PRESENTATION_STYLE pose=%d name=%s weight=%.3f phase=%s" % [style, TrickController.STYLE_NAMES[style], float(snapshot.get("style_pose_weight", 0.0)), str(snapshot.get("style_phase", ""))])
		_check(float(snapshot.get("style_pose_weight", 0.0)) > 0.55, "style pose %s never reached a readable weight" % TrickController.STYLE_NAMES[style])
		_check(str(snapshot.get("style_phase", "")) != "Idle", "style pose %s never entered its presentation phase" % TrickController.STYLE_NAMES[style])
		test_rig.queue_free()
