extends Node

var failures: Array[String] = []
var rig: SkierAnimationController
var frame := SkierAnimationFrame.new()

func _ready() -> void:
	rig = SkierAnimationController.new()
	add_child(rig)
	_test_rig_structure()
	_test_ground_poses()
	_test_basic_skiing_phase_two()
	_test_air_and_trick_poses()
	_test_flick_presentation_layers()
	_test_continuous_grab_reach()
	_test_pre_bail_balance_response()
	_test_grind_and_bail_poses()
	_test_reactions()
	_test_trick_resolution()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ANIMATION_PASS: athletic stance, loaded carves, crossover, linked turns, air, grabs, rail, reactions, and bail poses passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ANIMATION_FAIL: " + failure)
		get_tree().quit(1)

func _test_rig_structure() -> void:
	var snapshot := rig.debug_snapshot()
	for key: String in ["pelvis_rotation", "spine_rotation", "chest_rotation", "head_rotation", "left_hip_rotation", "right_hip_rotation", "left_ski_rotation", "right_ski_rotation", "left_hand_rotation", "right_hand_rotation", "left_pole_rotation", "right_pole_rotation"]:
		if not snapshot.has(key):
			failures.append("Missing semantic rig observation: " + key)
	if str(snapshot.get("rig_adapter", "none")) == "none":
		failures.append("No presentation adapter was selected")

func _test_ground_poses() -> void:
	frame.reset()
	frame.locomotion_state = 0
	frame.grounded = true
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
	_check_pose_contains("Jump Anticipation", "Jump anticipation pose was not selected")

func _test_basic_skiing_phase_two() -> void:
	frame.reset()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_ratio = 0.05
	frame.speed_mps = 2.0
	_step(120)
	var low_speed := rig.debug_snapshot()
	if float((low_speed.left_knee_rotation as Vector3).x) < deg_to_rad(20.0):
		failures.append("Low-speed neutral stance did not keep athletic knee flex")
	if float(low_speed.pelvis_height) >= 0.92:
		failures.append("Neutral stance did not lower the pelvis")

	frame.speed_ratio = 1.0
	frame.speed_mps = 18.0
	_step(120)
	var high_speed := rig.debug_snapshot()
	if float(high_speed.pelvis_height) >= float(low_speed.pelvis_height) - 0.035:
		failures.append("High-speed stance did not become more compact")
	if float((high_speed.left_knee_rotation as Vector3).x) <= float((low_speed.left_knee_rotation as Vector3).x) + 0.12:
		failures.append("High-speed stance did not increase knee flex continuously")
	if absf(float((high_speed.left_pole_rotation as Vector3).x)) <= absf(float((low_speed.left_pole_rotation as Vector3).x)) + 0.2:
		failures.append("Poles did not trail farther at speed")

	_set_loaded_carve(-1.0)
	_step(160)
	var left_carve := rig.debug_snapshot()
	_check_pose_contains("Carve Left", "Loaded left carve pose was not selected")
	if float((left_carve.pelvis_position as Vector3).x) >= -0.08:
		failures.append("Left carve did not displace the pelvis inside the turn")
	if float((left_carve.left_knee_rotation as Vector3).x) <= float((left_carve.right_knee_rotation as Vector3).x) + 0.08:
		failures.append("Left inside leg was not more compressed than the right outside leg")
	if absf(float((left_carve.pelvis_rotation as Vector3).z)) <= absf(float((left_carve.chest_rotation as Vector3).z)) * 2.0:
		failures.append("Left carve did not separate lower-body lean from chest lean")

	_set_loaded_carve(1.0)
	_step(7)
	var crossover := rig.debug_snapshot()
	_check_pose_contains("Crossover", "Turn reversal did not present a crossover")
	if float(crossover.ski_carve) <= 0.0:
		failures.append("Skis did not engage the new edge first during crossover")
	if float(crossover.pelvis_carve) >= 0.0 or float(crossover.torso_carve) >= 0.0:
		failures.append("Pelvis/torso did not follow behind the skis during crossover")
	if float(crossover.pelvis_height) <= float(left_carve.pelvis_height):
		failures.append("Crossover did not visibly unload and extend the old turn")

	_step(160)
	var right_carve := rig.debug_snapshot()
	_check_pose_contains("Carve Right", "Loaded right carve pose was not selected")
	if float((right_carve.pelvis_position as Vector3).x) <= 0.08:
		failures.append("Right carve did not displace the pelvis inside the turn")
	if float((right_carve.right_knee_rotation as Vector3).x) <= float((right_carve.left_knee_rotation as Vector3).x) + 0.08:
		failures.append("Right inside leg was not more compressed than the left outside leg")
	if float((left_carve.pelvis_rotation as Vector3).z) * float((right_carve.pelvis_rotation as Vector3).z) >= 0.0:
		failures.append("Left/right loaded carve pelvis angles were not mirrored")

	for direction: float in [-1.0, 1.0, -1.0, 1.0]:
		_set_loaded_carve(direction)
		_step(60)
	var linked_turns := rig.debug_snapshot()
	if float(linked_turns.carve_target) <= 0.5 or not is_finite(float(linked_turns.pelvis_carve)):
		failures.append("Linked S-turns did not remain continuous and finish on the requested edge")

func _set_loaded_carve(direction: float) -> void:
	frame.edge = direction
	frame.turn_input = direction
	frame.turn_rate = -direction * 0.68
	frame.lateral_acceleration = -direction * 8.5
	frame.carve_force = 8.5
	frame.carve_ratio = 0.94
	frame.skid_ratio = 0.06
	frame.skid = direction * 0.35
	frame.heading_velocity_delta = direction * 0.12
	frame.speed_ratio = 0.86
	frame.speed_mps = 15.5
	frame.braking = false
	frame.compression = 0.0

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

	frame.grab_pose = TrickController.GrabPose.NONE
	frame.style_pose = TrickController.StylePose.SPREAD_EAGLE
	frame.style_amount = 1.0
	_step(45)
	_check_pose_contains("Spread Eagle", "Spread-eagle pose was not selected")

	frame.style_pose = TrickController.StylePose.NONE
	frame.style_amount = 0.0
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.7
	frame.takeoff_upward_speed = 3.0
	frame.air_time = 0.7
	frame.air_upward_velocity = -3.0
	frame.predicted_landing_time = 0.18
	_step(45)
	_check_pose_contains("Descent", "Physical descent phase did not activate")

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

func _test_pre_bail_balance_response() -> void:
	frame.reset()
	frame.locomotion_state = 1
	frame.speed_mps = 16.0
	frame.speed_ratio = 0.65
	frame.pre_bail_weight = 0.82
	frame.pre_bail_side = 1.0
	_step(36)
	var response := rig.debug_snapshot()
	if float(response.pre_bail_weight) < 0.65:
		failures.append("Near-failure balance data did not reach the presentation layer")
	if str(response.pose).find("Loss of Control") < 0:
		failures.append("Near-failure pose did not read as controlled loss of balance")
	if float((response.chest_rotation as Vector3).z) >= -0.04:
		failures.append("Near-failure torso did not counter-lean against the imbalance")
	if absf(float((response.left_shoulder_rotation as Vector3).z) - float((response.right_shoulder_rotation as Vector3).z)) < 0.35:
		failures.append("Near-failure arms did not widen asymmetrically")

func _test_grind_and_bail_poses() -> void:
	frame.reset()
	frame.locomotion_state = 2
	frame.rail_speed = 18.0
	frame.rail_balance = 0.8
	frame.rail_pose = 1
	_step(60)
	_check_pose_contains("Boardslide Right", "Boardslide pose was not selected")

	frame.reset()
	frame.locomotion_state = 3
	frame.crash_reason = CrashContext.Reason.FEATURE_IMPACT
	frame.crash_impact_normal = Vector3.LEFT
	frame.crash_incoming_velocity = Vector3(8.0, -2.0, -12.0)
	frame.crash_current_velocity = Vector3(4.0, -1.0, -8.0)
	frame.crash_impact_speed = 8.0
	frame.crash_lateral_bias = 1.0
	frame.crash_angular_speed = 3.0
	frame.crash_stage = CrashContext.Stage.RELEASE
	frame.crash_elapsed = 0.08
	_step(12)
	_check_pose_contains("Crash Release", "Crash release pose was not selected")
	var release := rig.debug_snapshot()
	if str(release.crash_stage) != "Release":
		failures.append("Crash release stage was not exposed through animation telemetry")

	frame.crash_stage = CrashContext.Stage.IMPACT
	frame.crash_elapsed = 0.24
	_step(18)
	_check_pose_contains("Crash Impact", "Directional impact pose was not selected")
	var impact := rig.debug_snapshot()
	if float((impact.chest_rotation as Vector3).z) <= 0.04:
		failures.append("Side impact did not bias the torso in the impact direction")

	frame.crash_stage = CrashContext.Stage.FALL
	frame.crash_elapsed = 0.58
	_step(24)
	_check_pose_contains("Crash Fall", "Crash fall pose was not selected")

	frame.crash_stage = CrashContext.Stage.REST
	frame.crash_rest_detected = true
	frame.crash_elapsed = 1.25
	_step(72)
	_check_pose_contains("Crash Rest", "Crash rest pose was not selected")
	var rest := rig.debug_snapshot()
	if rig.rotation.length() > 0.0001 or rig.position.length() > 0.0001:
		failures.append("Crash presentation modified the gameplay visual root")
	if absf(float((rest.left_knee_rotation as Vector3).x)) > 2.35 or absf(float((rest.right_knee_rotation as Vector3).x)) > 2.35:
		failures.append("Crash rest pose exceeded knee limits")

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
	if tricks.style_pose != TrickController.StylePose.SPREAD_EAGLE:
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
