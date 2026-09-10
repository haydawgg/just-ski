extends Node

const PHYSICS_PROFILE := preload("res://resources/physics/default_ski_profile.tres")

var failures: Array[String] = []

func _ready() -> void:
	_test_motion_interfaces()
	AudioManager.shutdown_audio()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SOLVER_MOTION_INTERFACE_PASS: ground, air, rail, bail, landing, and collision interfaces passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_MOTION_INTERFACE_FAIL: " + failure)
	get_tree().quit(1)

func _test_motion_interfaces() -> void:
	var probe_offsets := PHYSICS_PROFILE.contact_probe_offsets()
	if probe_offsets.size() != 4 or probe_offsets[0] != PHYSICS_PROFILE.left_front_probe_offset or probe_offsets[3] != PHYSICS_PROFILE.right_rear_probe_offset:
		failures.append("Physics profile did not expose the four configured ski contact probes")
	if PHYSICS_PROFILE.ground_probe_distance <= PHYSICS_PROFILE.ground_probe_reach or PHYSICS_PROFILE.ground_probe_origin_height <= 0.0:
		failures.append("Physics profile contact probe dimensions were not valid")

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
	var ground_handling := ground.resolve_handling(18.0, 0.8, 0.0, 0.0, 0.25, 0.1, 1.0, 1.0, PHYSICS_PROFILE)
	if ground_handling.effective_steer_rate <= 0.0 or ground_handling.available_grip <= 0.0:
		failures.append("Ground solver did not resolve positive steering and grip authority")
	if ground_handling.carve_ratio < 0.0 or ground_handling.carve_ratio > 1.0:
		failures.append("Ground solver returned an unbounded carve ratio")

	var air := AirMotionSolver.new()
	var air_step := air.step_gravity(Vector3(0.0, -100.0, 0.0), 1.0 / 60.0, PHYSICS_PROFILE.air_gravity, PHYSICS_PROFILE.air_terminal_speed)
	if air_step.velocity.y < -PHYSICS_PROFILE.air_terminal_speed - 0.001:
		failures.append("Air solver exceeded its terminal speed")
	if air.landing_assist_availability(0.0, PHYSICS_PROFILE.air_landing_window) != 0.0:
		failures.append("Air solver landing assist window did not start at zero")
	var open_damping := air.angular_damping(0.0, -1.0, 0.35, true, PHYSICS_PROFILE)
	var landing_damping := air.angular_damping(0.0, PHYSICS_PROFILE.air_landing_window * 0.1, 1.0, true, PHYSICS_PROFILE)
	if landing_damping <= open_damping:
		failures.append("Air solver did not increase angular damping near landing")
	var capped := air.limit_normal_approach(Vector3(0.0, -6.0, 0.0), Vector3.UP, PHYSICS_PROFILE.seat_approach_speed, PHYSICS_PROFILE.seat_approach_speed, 0.0, 1.0 / 60.0)
	if capped.y < -PHYSICS_PROFILE.seat_approach_speed - 0.0001:
		failures.append("Air solver did not enforce the seat approach-speed ceiling")
	var slower := air.limit_normal_approach(Vector3(0.0, -0.4, 0.0), Vector3.UP, PHYSICS_PROFILE.seat_approach_speed, PHYSICS_PROFILE.seat_approach_speed, PHYSICS_PROFILE.spawn_settle_response, 1.0 / 60.0)
	if slower.y < -0.4001:
		failures.append("Air solver added extra into-surface pull below the desired approach speed")
	var eased := air.limit_normal_approach(Vector3(0.0, -2.0, 0.0), Vector3.UP, PHYSICS_PROFILE.seat_approach_speed, 0.4, PHYSICS_PROFILE.spawn_settle_response, 1.0 / 60.0)
	if eased.y <= -2.0 or eased.y > -0.4:
		failures.append("Air solver did not ease an over-fast approach toward the desired seat speed")

	var rail := RailMotionSolver.new()
	var rail_step := rail.advance(4.0, 1.0, 1.0, 20.0, -2.0, 0.5, 0.1)
	if rail_step.speed >= 4.0 or rail_step.offset <= 1.0:
		failures.append("Rail solver did not advance speed and offset independently")
	var rail_balance := rail.update_balance(0.0, 1.0, 0.5, 0.2, 1.0, 0.1)
	if rail_balance >= 0.1:
		failures.append("Rail solver did not apply balance input")
	var stable_drift := rail.instability(0.0, 0, PHYSICS_PROFILE)
	var kinked_boardslide_drift := rail.instability(0.5, 1, PHYSICS_PROFILE)
	if kinked_boardslide_drift <= stable_drift or not rail.has_failed(PHYSICS_PROFILE.rail_balance_fail, PHYSICS_PROFILE.rail_balance_fail):
		failures.append("Rail solver did not own kink/boardslide instability and failure policy")

	var bail := BailMotionSolver.new()
	var bail_motion := bail.step_motion(Vector3(8.0, -2.0, 0.0), Vector3.ONE, Vector3.UP, true, CrashContext.Stage.FALL, 0.1, PHYSICS_PROFILE)
	if bail_motion.velocity.length() >= Vector3(8.0, 0.0, 0.0).length():
		failures.append("Bail solver did not damp grounded linear motion")
	if not bail_motion.roll_valid or bail_motion.generated_roll_speed <= 0.0:
		failures.append("Bail solver did not couple grounded FALL motion to a surface-roll axis")
	var rest_motion := bail.step_motion(Vector3(8.0, -2.0, 0.0), Vector3.ONE, Vector3.UP, true, CrashContext.Stage.REST, 0.1, PHYSICS_PROFILE)
	if rest_motion.angular_velocity.length() >= Vector3.ONE.length() or rest_motion.roll_valid:
		failures.append("Bail solver did not damp REST angular motion without manufacturing roll")
	var rest := bail.resolve_rest(true, PHYSICS_PROFILE.crash_min_duration, 0.0, 0.0, false, 0.0, PHYSICS_PROFILE.crash_rest_confirm_time, 0.05, 0.05, PHYSICS_PROFILE)
	if not rest.rest_detected or rest.stage != CrashContext.Stage.REST:
		failures.append("Bail solver did not confirm a bounded rest state")

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
