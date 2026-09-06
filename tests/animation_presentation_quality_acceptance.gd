extends Node3D

const STEP := 1.0 / 60.0
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
	for pose: int in [TrickController.GrabPose.MUTE_LEFT, TrickController.GrabPose.JAPAN_LEFT, TrickController.GrabPose.TAIL, TrickController.GrabPose.NOSE, TrickController.GrabPose.DOUBLE]:
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
	for pose: int in [TrickController.GrabPose.MUTE_LEFT, TrickController.GrabPose.JAPAN_LEFT, TrickController.GrabPose.TAIL, TrickController.GrabPose.NOSE, TrickController.GrabPose.DOUBLE]:
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
