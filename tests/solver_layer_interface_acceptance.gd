extends Node

const PHYSICS_PROFILE := preload("res://resources/physics/default_ski_profile.tres")
const ANIMATION_PROFILE := preload("res://resources/animation/default_animation_profile.tres")

var failures: Array[String] = []

func _ready() -> void:
	_test_motion_interfaces()
	_test_animation_interfaces()
	_test_camera_interfaces()
	_test_contact_and_extension_contracts()
	if failures.is_empty():
		print("SOLVER_LAYER_PASS: typed ground, air, rail, landing, crash, animation, framing, collision, and composition interfaces passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_LAYER_FAIL: " + failure)
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

func _test_camera_interfaces() -> void:
	var projection := CompositionEvaluator.project_point(Vector3(0.0, 2.0, 5.0), Basis.IDENTITY, 68.0, Vector2(1920.0, 1080.0), Vector3.ZERO)
	if not (projection.get("screen", Vector2.ZERO) as Vector2).is_finite():
		failures.append("Composition evaluator returned a non-finite projection")
	var evaluation := {"hard_violation": 0.0, "body_occlusion": 0.0}
	if not CompositionEvaluator.hard_valid(evaluation, 0.25):
		failures.append("Composition evaluator rejected a valid hard pose")
	var projected_points: Array[Dictionary] = []
	projected_points.append({"screen": Vector2(0.5, 0.5), "depth": 4.0})
	projected_points.append({"screen": Vector2(0.6, 0.55), "depth": 5.0})
	var landmark_evaluation := CompositionEvaluator.evaluate_landmarks(
		projected_points,
		0,
		projected_points.size(),
		Rect2(0.0, 0.0, 1.0, 1.0),
		Rect2(0.1, 0.1, 0.8, 0.8)
	)
	if float(landmark_evaluation.get("average_depth", 0.0)) <= 0.0 or float(landmark_evaluation.get("hard_violation", INF)) != 0.0:
		failures.append("Composition evaluator did not preserve valid landmark bounds")
	var behind_points: Array[Dictionary] = []
	behind_points.append({"screen": Vector2(0.5, 0.5), "depth": -1.0})
	var behind_evaluation := CompositionEvaluator.evaluate_landmarks(
		behind_points,
		0,
		behind_points.size(),
		Rect2(0.0, 0.0, 1.0, 1.0),
		Rect2(0.1, 0.1, 0.8, 0.8)
	)
	if float(behind_evaluation.get("hard_violation", 0.0)) != INF:
		failures.append("Composition evaluator did not hard-fail a behind-camera landmark")
	var framing := CameraFramingSolver.new()
	framing.configure(0.5, 1.15, 3.4, 9.0, 20.0)
	framing.reset(0.0, true)
	if not framing.step_air(Vector3(0.0, 1.0, 0.0), Vector3.UP, 1.0 / 60.0, 0.2).is_finite():
		failures.append("Camera framing solver returned a non-finite target")
	var collision := CameraCollisionSolver.new()
	collision.configure(null, null, 1 | 4, 0.22, 0.35)
	if not bool(collision.destination_is_clear(Vector3.ZERO)):
		failures.append("Camera collision solver did not treat an unbound world as clear")
	if collision.foreground_occluded(Vector3.ZERO, Vector3.FORWARD, 0.12):
		failures.append("Camera collision solver reported foreground occlusion without a bound world")

func _test_contact_and_extension_contracts() -> void:
	# Grab awards require convincing hand-to-ski proximity: a 0.16 m reach must
	# not acquire, a 0.10 m reach acquires, and a held grab tolerates 0.11 m
	# hysteresis but releases at 0.13 m.
	var grab := GrabPoseLayer.new()
	var definition := GrabAnimationDefinition.new()
	if GrabPoseLayer.CONTACT_ACQUIRE_CAP > 0.141:
		failures.append("Grab acquire cap %.3f m still permits proximity awards" % GrabPoseLayer.CONTACT_ACQUIRE_CAP)
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, false, 0.16):
		failures.append("Grab latched at 0.16 m without convincing hand-to-ski contact")
	if not grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, false, 0.10):
		failures.append("Grab refused a convincing 0.10 m hand-to-ski contact")
	if not grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, true, 0.11):
		failures.append("Held grab dropped inside its 0.12 m maintenance envelope")
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, true, 0.13):
		failures.append("Held grab survived outside its maintenance envelope")
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.03, 0.08, false, 0.05):
		failures.append("Grab latched before the minimum air time")
	# Anticipation reach stays full without snow readings but restrains near
	# the seat so rendered skis cannot punch through before touchdown.
	var landing := LandingPoseLayer.new()
	if absf(landing.air_extension_scale(2.0, 2.0, 0.54) - 1.0) > 0.001:
		failures.append("Extension restraint altered the reach without snow readings")
	if absf(landing.air_extension_scale(1.0, 1.0, 0.54) - 1.0) > 0.001:
		failures.append("Extension restraint altered the reach far above the seat")
	var near_scale := landing.air_extension_scale(0.64, 0.64, 0.54)
	if near_scale < 0.25 or near_scale > 0.45:
		failures.append("Extension restraint did not scale the reach at 0.10 m seat gap (%.3f)" % near_scale)
	if absf(landing.air_extension_scale(0.5, 0.5, 0.54) - 0.15) > 0.001:
		failures.append("Extension restraint did not hold its minimum at seat penetration")
	var asymmetric := landing.air_extension_scale(2.0, 0.60, 0.54)
	if asymmetric < 0.15 or asymmetric > 0.3:
		failures.append("Extension restraint ignored the nearer ski probe (%.3f)" % asymmetric)
	# Crossed boot targets must be separated to the minimum stance so the leg
	# solve can never present an X-shaped ski configuration.
	var crossed: Array = SkiConstrainedLegIK.separate_boot_targets(Vector3(0.2, 0.0, 0.0), Vector3(-0.2, 0.0, 0.0), Basis.IDENTITY, 0.16)
	if float((crossed[1] as Vector3 - crossed[0] as Vector3).x) < 0.159:
		failures.append("Boot stance separation did not restore the minimum ski stance")
	var ordered: Array = SkiConstrainedLegIK.separate_boot_targets(Vector3(-0.3, 0.0, 0.0), Vector3(0.3, 0.0, 0.0), Basis.IDENTITY, 0.16)
	if (ordered[0] as Vector3).distance_to(Vector3(-0.3, 0.0, 0.0)) > 0.001 or (ordered[1] as Vector3).distance_to(Vector3(0.3, 0.0, 0.0)) > 0.001:
		failures.append("Boot stance separation moved an already valid stance")
	var degenerate := SkiConstrainedLegIK.contact_transform(Vector3.ZERO, Vector3.UP, Vector3.UP)
	if not SkiConstrainedLegIK.is_finite_transform(degenerate):
		failures.append("Shared ski-contact helper produced a non-finite degenerate heading frame")
	var slope_normal := Vector3(0.0, 0.8, 0.6).normalized()
	var stance: Dictionary = SkiConstrainedLegIK.stance_ski_targets(Vector3.ZERO, Vector3.FORWARD, slope_normal, 0.22)
	if not bool(stance.valid):
		failures.append("Shared stance helper rejected a sloped landing frame")
	elif absf((stance.forward as Vector3).dot(slope_normal)) > 0.02:
		failures.append("Shared stance helper did not keep ski forward tangent to the support plane")
	var profile := ANIMATION_PROFILE
	var preview_frame := SkierAnimationFrame.new()
	preview_frame.locomotion_state = 1
	preview_frame.predicted_landing_valid = true
	preview_frame.predicted_landing_time = 0.12
	preview_frame.predicted_landing_point = Vector3.ZERO
	preview_frame.predicted_landing_normal = Vector3.UP
	preview_frame.ski_forward = Vector3.FORWARD
	preview_frame.ski_forward_valid = true
	preview_frame.velocity_heading = Vector3.FORWARD
	if not LandingPoseLayer.preview_window_active(preview_frame, profile):
		failures.append("Landing preview window rejected a valid near-contact prediction")
	preview_frame.predicted_landing_time = profile.landing_anticipation_time + 0.2
	if LandingPoseLayer.preview_window_active(preview_frame, profile):
		failures.append("Landing preview window accepted a prediction outside anticipation")
	if absf(LandingPoseLayer.preview_ik_weight(0.8, 0.5, 0.5, 1.0) - 0.2) > 0.0001:
		failures.append("AIR preview weight is not preview × anticipation × extension clearance")
	if LandingPoseLayer.preview_ik_weight(1.0, 1.0, 1.0, 0.0) != 0.0:
		failures.append("AIR preview weight ignored a feature-obstruction veto")
	if SkiConstrainedLegIK.feature_obstruction_scale(null, Vector3.UP, Vector3.DOWN) != 1.0:
		failures.append("Feature obstruction veto did not no-op without a physics space")
	# Contact spray must ramp toward demand instead of switching on/off in one
	# frame, while still responding within a few physics ticks.
	var first_step := SkiSnowVFX.smooth_emitter_ratio(0.0, 0.68, 1.0 / 60.0)
	if first_step <= 0.04 or first_step >= 0.68:
		failures.append("Emitter smoothing did not ramp spray onset (first step %.3f)" % first_step)
	var settled := 0.0
	for _frame: int in 120:
		settled = SkiSnowVFX.smooth_emitter_ratio(settled, 0.68, 1.0 / 60.0)
	if absf(settled - 0.68) > 0.01:
		failures.append("Emitter smoothing did not converge to spray demand")
	var released := 0.68
	for _frame: int in 120:
		released = SkiSnowVFX.smooth_emitter_ratio(released, 0.0, 1.0 / 60.0)
	if released > 0.04:
		failures.append("Emitter smoothing did not trail spray off after demand ended")
