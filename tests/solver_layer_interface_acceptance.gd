extends Node

const PHYSICS_PROFILE := preload("res://resources/physics/default_ski_profile.tres")
const ANIMATION_PROFILE := preload("res://resources/animation/default_animation_profile.tres")

var failures: Array[String] = []

func _ready() -> void:
	_test_motion_interfaces()
	_test_animation_interfaces()
	_test_camera_interfaces()
	if failures.is_empty():
		print("SOLVER_LAYER_PASS: typed ground, air, rail, landing, crash, animation, framing, collision, and composition interfaces passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_LAYER_FAIL: " + failure)
	get_tree().quit(1)

func _test_motion_interfaces() -> void:
	var ground := GroundMotionSolver.new()
	var grounded := ground.resolve_contact(true, 0.0, 1.0 / 60.0, PHYSICS_PROFILE.coyote_time)
	if grounded.should_enter_air or grounded.coyote_remaining <= 0.0:
		failures.append("Ground solver did not preserve coyote time while grounded")
	var airborne := ground.resolve_contact(false, 0.01, 0.02, PHYSICS_PROFILE.coyote_time)
	if not airborne.should_enter_air:
		failures.append("Ground solver did not return the air transition after coyote expiry")
	var constrained := ground.constrain_heading_to_travel(
		Vector3.RIGHT,
		Vector3.FORWARD * 10.0,
		Vector3.UP,
		1.0,
		1.0 / 60.0,
		PHYSICS_PROFILE.low_speed_heading_travel_limit_degrees,
		PHYSICS_PROFILE.high_speed_heading_travel_limit_degrees,
		PHYSICS_PROFILE.heading_travel_limit_response
	)
	if not constrained.is_finite():
		failures.append("Ground solver returned a non-finite constrained heading")

	var air := AirMotionSolver.new()
	var air_step := air.step_gravity(Vector3(0.0, -100.0, 0.0), 1.0 / 60.0, PHYSICS_PROFILE.air_gravity, PHYSICS_PROFILE.air_terminal_speed)
	if air_step.velocity.y < -PHYSICS_PROFILE.air_terminal_speed - 0.001:
		failures.append("Air solver exceeded its terminal speed")
	if air.landing_assist_availability(0.0, PHYSICS_PROFILE.air_landing_window) != 0.0:
		failures.append("Air solver landing assist window did not start at zero")

	var rail := RailMotionSolver.new()
	var rail_step := rail.advance(4.0, 1.0, 1.0, 20.0, -2.0, 0.5, 0.1)
	if rail_step.speed >= 4.0 or rail_step.offset <= 1.0:
		failures.append("Rail solver did not advance speed and offset independently")
	var rail_balance := rail.update_balance(0.0, 1.0, 0.5, 0.2, 1.0, 0.1)
	if rail_balance >= 0.1:
		failures.append("Rail solver did not apply balance input")

	var landing := LandingTransition.new()
	var landing_result := landing.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0.0, 0.0, -4.0), Vector3.ZERO, PHYSICS_PROFILE)
	if landing_result == null or not landing_result.data.has("outcome"):
		failures.append("Landing transition did not return an explicit outcome")
	landing.apply_assist(landing_result, 0.0, PHYSICS_PROFILE)

	var crash := CollisionCrashEvaluator.new()
	var diagnostics: Array[Dictionary] = [{
		"collider_layer": 4,
		"speed_before": PHYSICS_PROFILE.feature_collision_min_speed + 1.0,
		"incoming_normal_speed": PHYSICS_PROFILE.feature_collision_min_normal_speed + 1.0,
		"speed_retention": PHYSICS_PROFILE.feature_collision_max_speed_retention,
		"normal": Vector3.FORWARD,
		"velocity_before": Vector3.FORWARD * 8.0,
		"velocity_after": Vector3.ZERO,
	}]
	var crash_context := crash.evaluate(diagnostics, 0, PHYSICS_PROFILE.feature_collision_min_speed, PHYSICS_PROFILE.feature_collision_min_normal_speed, PHYSICS_PROFILE.feature_collision_max_speed_retention, 0.0, Basis.IDENTITY, Vector3.ZERO)
	if crash_context == null or not crash_context.active:
		failures.append("Collision crash evaluator did not produce a guarded context")

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

func _test_camera_interfaces() -> void:
	var projection := CompositionEvaluator.project_point(Vector3(0.0, 2.0, 5.0), Basis.IDENTITY, 68.0, Vector2(1920.0, 1080.0), Vector3.ZERO)
	if not (projection.get("screen", Vector2.ZERO) as Vector2).is_finite():
		failures.append("Composition evaluator returned a non-finite projection")
	var evaluation := {"hard_violation": 0.0, "body_occlusion": 0.0}
	if not CompositionEvaluator.hard_valid(evaluation, 0.25):
		failures.append("Composition evaluator rejected a valid hard pose")
	var framing := CameraFramingSolver.new()
	framing.configure(0.5, 1.15, 3.4, 9.0, 20.0)
	framing.reset(0.0, true)
	if not framing.step_air(Vector3(0.0, 1.0, 0.0), Vector3.UP, 1.0 / 60.0, 0.2).is_finite():
		failures.append("Camera framing solver returned a non-finite target")
	var collision := CameraCollisionSolver.new()
	collision.configure(null, null, 1 | 4, 0.22, 0.35)
	if not bool(collision.destination_is_clear(Vector3.ZERO)):
		failures.append("Camera collision solver did not treat an unbound world as clear")
