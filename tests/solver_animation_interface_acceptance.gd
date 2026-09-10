extends Node

const ANIMATION_PROFILE := preload("res://resources/animation/default_animation_profile.tres")

var failures: Array[String] = []

func _ready() -> void:
	_test_animation_interfaces()
	AudioManager.shutdown_audio()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SOLVER_ANIMATION_INTERFACE_PASS: ground, air, grab, style, landing, rail, crash, and secondary-motion interfaces passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_ANIMATION_INTERFACE_FAIL: " + failure)
	get_tree().quit(1)

func _test_animation_interfaces() -> void:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_ratio = 0.7
	frame.edge = 0.8
	frame.carve_ratio = 0.9
	var ground := GroundPoseLayer.new()
	if ground.crouch_target(frame, true) <= 0.0 or ground.carve_target(frame, ANIMATION_PROFILE) <= 0.0:
		failures.append("Ground pose layer did not resolve grounded presentation targets")

	frame.locomotion_state = 1
	frame.air_time = 0.25
	frame.takeoff_upward_speed = 3.0
	frame.air_upward_velocity = 0.1
	var air := AirTrickPoseLayer.new()
	air.update_jump_animation(frame, 1.0 / 60.0, ANIMATION_PROFILE)
	if air.air_size <= 0.0 or air.air_phase_name == "Ground":
		failures.append("Air trick pose layer did not resolve airborne phase state")

	frame.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	frame.grab_input_strength = 0.8
	var grab := GrabPoseLayer.new()
	if grab.input_strength(frame, TrickController.GrabPose.NONE) <= 0.0:
		failures.append("Grab pose layer rejected an active grab input")
	frame.style_pose = TrickController.StylePose.SHIFTY_LEFT
	var style := StylePoseLayer.new()
	if style.input_strength(frame, TrickController.StylePose.NONE) <= 0.0:
		failures.append("Style pose layer rejected an active style input")

	var landing := LandingPoseLayer.new()
	var readiness := landing.readiness_targets(frame, ANIMATION_PROFILE)
	if not readiness.has("valid") or not readiness.has("inputs_valid"):
		failures.append("Landing pose layer returned an untyped readiness shape")
	var rail := RailPoseLayer.new()
	if rail.slide_target(-1, 0.5) >= 0.0 or rail.exit_target(0.0, 1.0) <= 0.0:
		failures.append("Rail pose layer did not resolve slide/exit targets")
	var crash := CrashReactionLayer.new()
	var pre_bail := crash.step_pre_bail(0.0, 0.0, frame, 1.0 / 60.0, ANIMATION_PROFILE)
	if not pre_bail.has("weight") or not pre_bail.has("side"):
		failures.append("Crash reaction layer did not return a typed pre-bail step")
	frame.crash_stage = CrashContext.Stage.FALL
	frame.crash_current_velocity = Vector3(0.0, 0.0, -6.0)
	frame.ground_normal = Vector3.UP
	frame.body_up = Vector3.UP
	frame.body_up_valid = true
	frame.ski_forward = Vector3.FORWARD
	frame.ski_forward_valid = true
	var sprawl := crash.fall_travel_sprawl(frame, ANIMATION_PROFILE)
	if not bool(sprawl.get("valid", false)) or not sprawl.has("pelvis") or not sprawl.has("left_ski"):
		failures.append("Crash reaction layer did not resolve travel-direction FALL sprawl")
	var secondary := SecondaryMotionLayer.new()
	if secondary.target(0.5, 0.5, 0.5, false) <= 0.0:
		failures.append("Secondary motion layer did not resolve activity")
	secondary.reset(Vector3.ZERO, Vector3.ZERO)
	var secondary_result := secondary.step(
		frame,
		1.0 / 60.0,
		ANIMATION_PROFILE,
		false,
		0.1,
		0.0,
		0.2,
		0.4,
		0.1,
		0.25,
		0.2,
		true,
		false,
		0.2,
		0.1,
		0.05,
		0.0,
		0.0,
		0.0,
		Vector3.ZERO,
		Vector3.ZERO
	)
	if secondary_result == null or not secondary_result.torso_follow_through.is_finite() or not secondary_result.left_arm_inertia.is_finite():
		failures.append("Secondary motion layer did not return a finite typed result")
