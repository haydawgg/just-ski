extends Node

var failures: Array[String] = []
var rig: SkierAnimationController
var frame := SkierAnimationFrame.new()

func _ready() -> void:
	rig = SkierAnimationController.new()
	add_child(rig)
	_test_rig_structure()
	_test_ground_poses()
	_test_air_and_trick_poses()
	_test_flick_presentation_layers()
	_test_continuous_grab_reach()
	_test_grind_and_bail_poses()
	_test_reactions()
	_test_trick_resolution()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ANIMATION_PASS: articulated rig, ground, air, grabs, rail, reactions, and bail poses passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ANIMATION_FAIL: " + failure)
		get_tree().quit(1)

func _test_rig_structure() -> void:
	for node_name: String in ["Pelvis", "Spine", "Chest", "Head", "LeftHip", "RightHip", "LeftSki", "RightSki", "LeftHand", "RightHand", "LeftPole", "RightPole"]:
		if rig.find_child(node_name, true, false) == null:
			failures.append("Missing articulated rig node: " + node_name)

func _test_ground_poses() -> void:
	frame.reset()
	frame.locomotion_state = 0
	frame.speed_ratio = 0.85
	frame.speed_mps = 30.0
	frame.edge = 0.9
	_step(90)
	_check_pose_contains("Carve", "Deep carve pose was not selected")
	var carved := rig.debug_snapshot()
	if absf(float((carved.pelvis_rotation as Vector3).z)) < 0.08:
		failures.append("Carve did not create visible pelvis angulation")

	frame.tuck = 1.0
	_step(45)
	_check_pose_contains("Tuck", "Tuck pose was not selected")

	frame.tuck = 0.0
	frame.braking = true
	frame.skid = 8.0
	_step(45)
	_check_pose_contains("Hockey Stop", "Brake/skid pose was not selected")

	frame.braking = false
	frame.edge = 0.0
	frame.compression = 1.0
	_step(45)
	_check_pose_contains("Jump Compression", "Jump compression pose was not selected")

func _test_air_and_trick_poses() -> void:
	frame.reset()
	frame.locomotion_state = 1
	frame.angular_velocity = Vector3(0.0, 4.0, 0.0)
	_step(45)
	_check_pose_contains("Spin", "Spin silhouette was not selected")

	frame.angular_velocity = Vector3(3.5, 0.0, 0.0)
	_step(45)
	_check_pose_contains("Frontflip", "Frontflip tuck was not selected")

	frame.angular_velocity = Vector3(0.0, 0.0, -3.2)
	_step(45)
	_check_pose_contains("Cork", "Cork silhouette was not selected")

	frame.angular_velocity = Vector3.ZERO
	frame.grab_pose = TrickController.GrabPose.JAPAN_LEFT
	_step(45)
	_check_pose_contains("Japan Grab Left", "Japan grab pose was not selected")

	frame.grab_pose = TrickController.GrabPose.SPREAD_EAGLE
	_step(45)
	_check_pose_contains("Spread Eagle", "Spread-eagle pose was not selected")

	frame.grab_pose = TrickController.GrabPose.NONE
	frame.predicted_landing_time = 0.18
	_step(45)
	_check_pose_contains("Landing Ready", "Landing anticipation did not activate")

func _test_flick_presentation_layers() -> void:
	frame.reset()
	frame.locomotion_state = 0
	frame.trick_phase = TrickCommand.PresentationPhase.SETUP
	frame.gesture_strength = 1.0
	frame.gesture_direction = Vector2(0.0, 1.0)
	_step(45)
	_check_pose_contains("Flick Setup", "Right-stick preload did not create a directional setup pose")

	frame.reset()
	frame.locomotion_state = 1
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.trick_kind = TrickCommand.Kind.CORK_LEFT
	frame.rotation_progress = 0.4
	frame.angular_velocity = Vector3(0.0, -2.0, -2.4)
	_step(45)
	_check_pose_contains("Cork Left", "Left cork command did not drive the command-specific silhouette")
	var left_cork := rig.debug_snapshot().pelvis_rotation as Vector3
	frame.trick_kind = TrickCommand.Kind.CORK_RIGHT
	frame.angular_velocity = Vector3(0.0, 2.0, 2.4)
	_step(60)
	_check_pose_contains("Cork Right", "Right cork command did not drive the mirrored silhouette")
	var right_cork := rig.debug_snapshot().pelvis_rotation as Vector3
	if left_cork.z * right_cork.z >= 0.0:
		failures.append("Left/right cork silhouettes were not mirrored")

	frame.trick_phase = TrickCommand.PresentationPhase.OPEN
	frame.trick_kind = TrickCommand.Kind.NONE
	frame.angular_velocity = Vector3.ZERO
	_step(45)
	_check_pose_contains("Open", "Grab/trick release did not create an opening pose")

func _test_continuous_grab_reach() -> void:
	frame.reset()
	frame.locomotion_state = 1
	frame.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	frame.grab_amount = 0.25
	_step(45)
	var light_reach := float(rig.debug_snapshot().grab_reach_error)
	frame.grab_amount = 1.0
	frame.grab_tweak = Vector2(0.0, 0.8)
	_step(60)
	var full_reach := float(rig.debug_snapshot().grab_reach_error)
	if full_reach >= light_reach:
		failures.append("Increasing trigger pressure did not move the hand closer to its ski target")
	if full_reach > 0.62:
		failures.append("Full grab reach remained visibly detached from the ski (light %.3f, full %.3f)" % [light_reach, full_reach])

func _test_grind_and_bail_poses() -> void:
	frame.reset()
	frame.locomotion_state = 2
	frame.rail_speed = 18.0
	frame.rail_balance = 0.8
	_step(60)
	_check_pose_contains("Boardslide Right", "Boardslide pose was not selected")

	frame.reset()
	frame.locomotion_state = 3
	_step(30)
	_check_pose_contains("Bail Tumble", "Bail pose was not selected")

func _test_reactions() -> void:
	frame.reset()
	frame.locomotion_state = 1
	rig.trigger(SkierAnimationController.AnimationEvent.POP, 1.0)
	_step(4)
	_check_pose_contains("Pop Extension", "Pop one-shot reaction did not override the base pose")

	frame.locomotion_state = 0
	rig.trigger(SkierAnimationController.AnimationEvent.LAND_HARD, 1.0, 1.0)
	_step(8)
	var landing := rig.debug_snapshot()
	if float(landing.pelvis_height) > 0.94:
		failures.append("Hard-landing reaction did not compress the pelvis")

func _test_trick_resolution() -> void:
	var tricks := TrickController.new()
	add_child(tricks)
	tricks.begin_air(false)
	Input.action_press("grab_left", 1.0)
	tricks.update_air(Vector3.ZERO, 0.016)
	if tricks.grab_pose != TrickController.GrabPose.SAFETY_LEFT:
		failures.append("Left grab input did not resolve to Safety Left")
	Input.action_press("grab_right", 1.0)
	Input.action_press("trick_up", 1.0)
	tricks.update_air(Vector3.ZERO, 0.016)
	if tricks.grab_pose != TrickController.GrabPose.SPREAD_EAGLE:
		failures.append("Dual grab plus up input did not resolve to Spread Eagle")
	Input.action_release("grab_left")
	Input.action_release("grab_right")
	Input.action_release("trick_up")

func _step(count: int) -> void:
	for _index: int in count:
		rig.apply_frame(frame, 1.0 / 120.0)

func _check_pose_contains(fragment: String, message: String) -> void:
	if fragment not in str(rig.debug_snapshot().pose):
		failures.append(message + " (got %s)" % rig.debug_snapshot().pose)
