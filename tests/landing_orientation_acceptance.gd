extends Node

const SkiProfile := preload("res://resources/physics/default_ski_profile.tres")
const TEST_HZ := [30, 60, 120]
const MAX_SETTLE_SECONDS := 0.25
const TARGET_ERROR := deg_to_rad(2.0)
const TOUCHDOWN_SNAP_LIMIT := deg_to_rad(0.5)
const RATE_TOLERANCE := 0.0001
const BASIS_TOLERANCE := 0.001
const CROSS_RATE_POSE_TOLERANCE := deg_to_rad(2.0)
const CROSS_RATE_TIME_TOLERANCE := 0.05
# Flat-floor spawn hover must stay inside probe reach (distance - origin height
# = 1.10 m). ParkLayout.SPAWN_HOVER is 1.15 m along the slope normal, which is
# below 1.10 m in world Y on the 18-degree face; a 1.15 m world-Y hover misses.
const SPAWN_SETTLE_HOVER_Y := 0.85

var failures: Array[String] = []
var profile: SkiPhysicsProfile = SkiProfile
var results_by_scenario: Dictionary = {}

func _ready() -> void:
	for scenario: String in [
		"aligned_clean",
		"yaw_offset_clean",
		"tilted_sketchy",
		"hard_non_bail",
		"residual_spin",
		"slope_18_degrees",
		"immediate_steering",
	]:
		var scenario_results: Array[Dictionary] = []
		for hz: int in TEST_HZ:
			scenario_results.append(_run_case(scenario, hz))
		results_by_scenario[scenario] = scenario_results
		_validate_cross_rate_results(scenario, scenario_results)
	var reseat_results: Array[Dictionary] = []
	for hz: int in TEST_HZ:
		reseat_results.append(_run_case("tilted_sketchy", hz, false))
	_validate_cross_rate_results("terrain_hop", reseat_results)
	_test_rotational_landing_releases_crouch()
	_test_landing_idle_does_not_retrigger()
	_test_spawn_reseat_seats_quietly()
	_test_touchdown_freezes_trick_snapshot()
	_test_spawn_settle_does_not_alter_pop_or_hops()
	await _test_spawn_settle_window()

	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("LANDING_ORIENTATION_PASS: bounded deliberate and terrain-hop landing orientation, residual rotation, slope, steering, spawn settle, and 30/60/120 Hz continuity passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("LANDING_ORIENTATION_FAIL: " + failure)
	get_tree().quit(1)

func _run_case(scenario: String, hz: int, deliberate: bool = true) -> Dictionary:
	var setup := _scenario_setup(scenario)
	var normal: Vector3 = setup.normal
	var touchdown_basis: Basis = setup.basis
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.state = SkierController.State.AIR
	skier.air_deliberate = deliberate
	skier.air_time = 0.8
	skier.landing_feedback_armed = false
	skier._spawn_settle_active = false
	skier.contact.grounded = true
	skier.contact.average_normal = normal
	skier.contact.last_normal = normal
	skier.global_basis = touchdown_basis
	skier.velocity = setup.velocity
	skier.angular_velocity = setup.angular_velocity

	var before_basis := skier.global_basis
	if deliberate:
		skier._handle_landing()
	else:
		skier._reseat_on_snow()
	var touchdown_rotation := _basis_angle(before_basis, skier.global_basis)
	if touchdown_rotation > TOUCHDOWN_SNAP_LIMIT:
		failures.append("%s at %d Hz changed root orientation by %.3f degrees at touchdown (deliberate=%s)" % [scenario, hz, rad_to_deg(touchdown_rotation), deliberate])
	if skier.state != SkierController.State.GROUND:
		failures.append("%s at %d Hz did not enter GROUND immediately" % [scenario, hz])
	if skier.motion_mode != CharacterBody3D.MOTION_MODE_GROUNDED:
		failures.append("%s at %d Hz did not switch to grounded motion immediately" % [scenario, hz])
	if skier.velocity.dot(normal) < -0.01:
		failures.append("%s at %d Hz retained %.4f m/s into-snow velocity" % [scenario, hz, skier.velocity.dot(normal)])

	var expected_outcome: int = int(setup.expected_outcome)
	var actual_outcome := int(skier.landing_context.get("outcome", -1))
	if actual_outcome != expected_outcome:
		failures.append("%s at %d Hz classified outcome %d instead of %d" % [scenario, hz, actual_outcome, expected_outcome])
	if scenario == "residual_spin":
		var expected_residual: float = setup.angular_velocity.length() * profile.landing_residual_yaw_transfer
		if skier.landing_residual_angular_velocity.length() < expected_residual * 0.85:
			failures.append("Residual-spin landing at %d Hz did not transfer yaw momentum into the settle residual" % hz)

	var target_basis := _ground_target_from_touchdown(touchdown_basis, normal)
	var delta := 1.0 / float(hz)
	var frame_count := int(ceil(MAX_SETTLE_SECONDS * float(hz)))
	var elapsed := 0.0
	var previous_basis := skier.global_basis
	var maximum_step := 0.0
	var settle_time := INF
	var final_target_error := _basis_angle(skier.global_basis, target_basis)
	var steering_seen := false
	if scenario == "immediate_steering":
		skier.input_frame.steer_raw = -1.0
		skier.input_frame.steer = -1.0
		skier.input_frame.movement_stick = Vector2(-1.0, 0.0)
		skier.input_frame.left_stick = skier.input_frame.movement_stick

	for _frame: int in frame_count:
		skier._update_ground(delta)
		elapsed += delta
		var current_basis := skier.global_basis
		var step_angle := _basis_angle(previous_basis, current_basis)
		maximum_step = maxf(maximum_step, step_angle)
		var allowed_step := deg_to_rad(profile.landing_orientation_max_rate_degrees) * delta + RATE_TOLERANCE
		if step_angle > allowed_step:
			failures.append("%s at %d Hz rotated %.3f degrees in one ground frame; limit was %.3f degrees" % [scenario, hz, rad_to_deg(step_angle), rad_to_deg(allowed_step)])
		if not _basis_valid(current_basis):
			failures.append("%s at %d Hz produced a non-orthonormal or non-finite root basis" % [scenario, hz])
		final_target_error = _basis_angle(current_basis, target_basis)
		if settle_time == INF and final_target_error <= TARGET_ERROR:
			settle_time = elapsed
		if absf(skier.steering_input) > 0.1 or absf(skier.edge_amount) > 0.05:
			steering_seen = true
		previous_basis = current_basis

	if scenario == "immediate_steering":
		if not steering_seen:
			failures.append("Immediate steering snapshot was ignored during landing settle at %d Hz" % hz)
		if _basis_angle(before_basis, skier.global_basis) < deg_to_rad(2.0):
			failures.append("Immediate steering snapshot did not produce responsive heading change at %d Hz" % hz)
	else:
		if settle_time == INF:
			failures.append("%s at %d Hz did not reach the ground target within %.3f seconds (final error %.3f degrees)" % [scenario, hz, elapsed, rad_to_deg(final_target_error)])

	var result := {
		"hz": hz,
		"basis": skier.global_basis,
		"settle_time": settle_time,
		"final_target_error": final_target_error,
		"maximum_step": maximum_step,
		"touchdown_rotation": touchdown_rotation,
		"outcome": actual_outcome,
	}
	remove_child(skier)
	skier.queue_free()
	return result

func _validate_cross_rate_results(scenario: String, samples: Array[Dictionary]) -> void:
	if samples.size() != TEST_HZ.size():
		return
	var reference := samples[1]
	for sample: Dictionary in [samples[0], samples[2]]:
		var pose_error := _basis_angle(sample.basis, reference.basis)
		if pose_error > CROSS_RATE_POSE_TOLERANCE:
			failures.append("%s final pose diverged %.3f degrees between %d and %d Hz" % [scenario, rad_to_deg(pose_error), int(sample.hz), int(reference.hz)])
		var reference_time := float(reference.settle_time)
		var sample_time := float(sample.settle_time)
		if is_finite(reference_time) and is_finite(sample_time) and absf(sample_time - reference_time) > CROSS_RATE_TIME_TOLERANCE:
			failures.append("%s settle time differed by %.3f seconds between %d and %d Hz" % [scenario, absf(sample_time - reference_time), int(sample.hz), int(reference.hz)])

func _scenario_setup(scenario: String) -> Dictionary:
	var normal := Vector3.UP
	var forward := Vector3.FORWARD
	var basis := Basis.looking_at(forward, normal).orthonormalized()
	var impact := 2.0
	var angular_velocity := Vector3.ZERO
	var expected_outcome := LandingSolver.Outcome.CLEAN

	match scenario:
		"aligned_clean":
			pass
		"yaw_offset_clean":
			forward = forward.rotated(normal, deg_to_rad(15.0)).normalized()
			basis = Basis.looking_at(forward, normal).orthonormalized()
		"tilted_sketchy":
			var right := forward.cross(normal).normalized()
			basis = Basis(right, deg_to_rad(12.0)) * Basis(forward, deg_to_rad(14.0)) * basis
			forward = (-basis.z).slide(normal).normalized()
			impact = 10.5
			expected_outcome = LandingSolver.Outcome.SKETCHY
		"hard_non_bail":
			impact = 13.4
			expected_outcome = LandingSolver.Outcome.HARD
		"residual_spin":
			angular_velocity = Vector3(0.0, 4.0, 0.0)
		"slope_18_degrees":
			var slope_angle := deg_to_rad(18.0)
			normal = Vector3(0.0, cos(slope_angle), sin(slope_angle)).normalized()
			forward = Vector3(0.0, -sin(slope_angle), cos(slope_angle)).normalized()
			basis = Basis.looking_at(forward, normal).orthonormalized()
		"immediate_steering":
			pass

	var touchdown_forward := (-basis.z).slide(normal)
	if touchdown_forward.length_squared() < 0.0001:
		touchdown_forward = forward
	touchdown_forward = touchdown_forward.normalized()
	return {
		"normal": normal,
		"basis": basis,
		"velocity": touchdown_forward * 10.0 - normal * impact,
		"angular_velocity": angular_velocity,
		"expected_outcome": expected_outcome,
	}

func _ground_target_from_touchdown(touchdown_basis: Basis, normal: Vector3) -> Basis:
	var projected_forward := (-touchdown_basis.z).slide(normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD.slide(normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	return Basis.looking_at(projected_forward.normalized(), normal.normalized()).orthonormalized()

func _basis_angle(a: Basis, b: Basis) -> float:
	return a.orthonormalized().get_rotation_quaternion().angle_to(b.orthonormalized().get_rotation_quaternion())

func _test_rotational_landing_releases_crouch() -> void:
	# A 360-style landing carries high balance error; the crouch and wobble
	# must still decay and release instead of holding indefinitely.
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(0.0, -1.0, -9.0))
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.landing_context = {
		"impact_speed": 3.0,
		"impact_severity": 0.8,
		"balance_error": 0.85,
		"ski_alignment_error": 0.2,
		"body_roll_error": 0.2,
		"body_pitch_error": 0.2,
		"rotation_error": 0.4,
		"rotation_accumulated": Vector3(0.0, TAU, 0.0),
		"rotation_residual": Vector3(0.0, 0.4, 0.0),
		"lateral_velocity": 1.0,
		"forward_velocity": 9.0,
		"air_time": 0.9,
		"surface_normal": Vector3.UP,
		"outcome": LandingSolver.Outcome.CLEAN,
		"active": true,
		"deliberate": true,
	}
	skier.animation_controller.trigger(SkierAnimationController.AnimationEvent.LAND_HARD, 0.8, 1.0)
	for _frame: int in 180:
		skier._update_animation(1.0 / 60.0)
	if not skier.animation_controller.is_landing_idle():
		failures.append("Rotational landing held compression/wobble past 3 seconds instead of releasing the crouch")
	if float(skier.animation_controller.debug_snapshot().get("landing_compression", 1.0)) > 0.05:
		failures.append("Rotational landing remained compressed after the recovery window")
	remove_child(skier)
	skier.queue_free()

func _test_landing_idle_does_not_retrigger() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(0.0, -1.0, -9.0))
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.landing_context = {
		"impact_speed": 2.4,
		"impact_severity": 0.35,
		"balance_error": 0.2,
		"ski_alignment_error": 0.1,
		"body_roll_error": 0.08,
		"body_pitch_error": 0.08,
		"rotation_error": 0.05,
		"rotation_accumulated": Vector3.ZERO,
		"rotation_residual": Vector3.ZERO,
		"lateral_velocity": 0.4,
		"forward_velocity": 9.0,
		"air_time": 0.7,
		"surface_normal": Vector3.UP,
		"outcome": LandingSolver.Outcome.CLEAN,
		"active": true,
		"deliberate": true,
	}
	var landed_count := [0]
	skier.landed.connect(func(_result: Dictionary) -> void: landed_count[0] += 1)
	skier.animation_controller.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.35, 0.0)
	for _frame: int in 180:
		skier._update_animation(1.0 / 60.0)
	if not skier.animation_controller.is_landing_idle():
		failures.append("Ordinary landing did not reach idle presentation")
	if bool(skier.landing_context.get("active", false)):
		failures.append("Landing context stayed active after idle")
	for _frame: int in 30:
		skier._update_animation(1.0 / 60.0)
	if not skier.animation_controller.is_landing_idle():
		failures.append("Idle landing presentation restarted after recovery")
	if landed_count[0] != 0:
		failures.append("Animation recovery emitted an extra landed event")
	if str(skier.animation_controller.debug_snapshot().get("landing_phase", "Idle")) in ["Contact", "Compression"]:
		failures.append("Idle landing restarted a second impact event")
	remove_child(skier)
	skier.queue_free()

func _test_spawn_reseat_seats_quietly() -> void:
	# Post-spawn hover seating (never armed via _enter_air) must settle without
	# playing a landing crouch; armed terrain hops keep their presentation.
	var quiet := SkierController.new()
	add_child(quiet)
	quiet.set_physics_process(false)
	quiet.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(0.0, -0.5, -2.0))
	quiet.state = SkierController.State.AIR
	quiet.air_deliberate = false
	quiet.air_time = 0.05
	quiet.landing_feedback_armed = false
	quiet.contact.grounded = true
	quiet.contact.average_normal = Vector3.UP
	quiet.velocity = Vector3(0.0, -0.5, -2.0)
	quiet.angular_velocity = Vector3.ZERO
	quiet._reseat_on_snow()
	if quiet.state != SkierController.State.GROUND:
		failures.append("Quiet spawn reseat did not reach GROUND")
	elif not quiet.animation_controller.is_landing_idle():
		failures.append("Spawn hover seating played a landing crouch instead of settling quietly")
	remove_child(quiet)
	quiet.queue_free()

	var hop := SkierController.new()
	add_child(hop)
	hop.set_physics_process(false)
	hop.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)), Vector3(0.0, -2.0, -6.0))
	hop.state = SkierController.State.AIR
	hop.air_deliberate = false
	hop.air_time = 0.3
	hop.landing_feedback_armed = true
	hop.contact.grounded = true
	hop.contact.average_normal = Vector3.UP
	hop.velocity = Vector3(0.0, -2.0, -6.0)
	hop.angular_velocity = Vector3.ZERO
	hop._reseat_on_snow()
	if hop.state != SkierController.State.GROUND:
		failures.append("Armed terrain-hop reseat did not reach GROUND")
	elif hop.animation_controller.is_landing_idle():
		failures.append("Armed terrain-hop reseat lost its landing presentation")
	remove_child(hop)
	hop.queue_free()

	var spawn := SkierController.new()
	add_child(spawn)
	spawn.set_physics_process(false)
	spawn.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(0.0, -0.5, -2.0))
	spawn.state = SkierController.State.AIR
	spawn.air_deliberate = false
	spawn.air_time = 0.5
	spawn.landing_feedback_armed = false
	spawn._spawn_settle_active = true
	spawn.contact.grounded = true
	spawn.contact.average_normal = Vector3.UP
	spawn.velocity = Vector3(0.0, -0.5, -2.0)
	spawn.angular_velocity = Vector3.ZERO
	var spawn_landed := [false]
	spawn.landed.connect(func(_result: Dictionary) -> void: spawn_landed[0] = true)
	spawn._reseat_on_snow()
	if spawn.state != SkierController.State.GROUND:
		failures.append("Explicit spawn-settle reseat did not reach GROUND")
	elif spawn._spawn_settle_active:
		failures.append("Spawn settle stayed active after quiet reseat")
	elif not spawn.animation_controller.is_landing_idle():
		failures.append("Spawn settle emitted a landing crouch after min_air_time")
	elif spawn_landed[0]:
		failures.append("Spawn settle emitted the deliberate landing signal")
	elif bool(spawn.landing_context.get("active", false)):
		failures.append("Spawn settle left landing presentation context active")
	remove_child(spawn)
	spawn.queue_free()

func _test_touchdown_freezes_trick_snapshot() -> void:
	# Display, scoring, and landing validity must share one touchdown snapshot:
	# accumulation stops at contact and the captured rotation stays stable.
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3.ZERO)
	skier.state = SkierController.State.AIR
	skier.air_deliberate = true
	skier.air_time = 0.8
	skier.landing_feedback_armed = true
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.contact.last_normal = Vector3.UP
	skier.global_basis = Basis.IDENTITY
	skier.velocity = Vector3(0.0, -2.0, -10.0)
	skier.angular_velocity = Vector3(0.0, 0.5, 0.0)
	skier.trick.begin_air(false, TrickCommand.Kind.SPIN_RIGHT, true, Vector3.UP)
	for _frame: int in 60:
		skier.trick.update_air(Vector3(0.0, 6.0, 0.0), 1.0 / 60.0, null)
	var touchdown_display := skier.trick.live_name()
	var touchdown_accumulated: Vector3 = skier.trick.accumulated_rotation
	if touchdown_accumulated.y < 5.0:
		failures.append("Trick snapshot setup did not accumulate spin rotation")
		remove_child(skier)
		skier.queue_free()
		return
	skier._handle_landing()
	if skier.state != SkierController.State.GROUND:
		failures.append("Trick snapshot landing did not reach GROUND")
		remove_child(skier)
		skier.queue_free()
		return
	var captured: Vector3 = skier.landing_context.get("rotation_accumulated", Vector3.ZERO)
	if captured.distance_to(touchdown_accumulated) > 0.001:
		failures.append("Landing validity captured different rotation than the touchdown display")
	for _frame: int in 30:
		skier._update_ground(1.0 / 60.0)
		skier._update_animation(1.0 / 60.0)
	var settled: Vector3 = skier.landing_context.get("rotation_accumulated", Vector3.ZERO)
	if settled.distance_to(touchdown_accumulated) > 0.001:
		failures.append("Accumulated trick rotation kept changing after ground contact")
	if skier.trick.active:
		failures.append("Trick state stayed active after the landing was scored")
	if touchdown_display.is_empty():
		failures.append("Touchdown display showed no trick name for a near-360 spin")
	remove_child(skier)
	skier.queue_free()

func _test_spawn_settle_does_not_alter_pop_or_hops() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3.RIGHT * 8.0)
	if skier._spawn_settle_active:
		failures.append("Benchmark reset enabled spawn settle, which would change crest hops and charged pops")
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.contact.last_normal = Vector3.UP
	var normal := Vector3.UP
	var tangent := Vector3.RIGHT * 8.0
	for approach_speed: float in [-1.4, 0.0, 2.0]:
		skier.state = SkierController.State.GROUND
		skier._spawn_settle_active = false
		skier.velocity = tangent + normal * approach_speed
		skier._pop(normal, 1.0)
		if skier._spawn_settle_active:
			failures.append("Charged pop left spawn settle active")
		if absf(skier.velocity.dot(normal) - (skier.profile.pop_impulse + maxf(0.0, approach_speed))) > 0.001:
			failures.append("Spawn-settle work changed charged pop impulse")
		if skier.velocity.slide(normal).distance_to(tangent) > 0.001:
			failures.append("Spawn-settle work changed charged pop tangential momentum")
	remove_child(skier)
	skier.queue_free()

func _test_spawn_settle_window() -> void:
	var floor_body := _make_box_body("SpawnSettleFloor", 1, Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_test_reset_contact_is_fresh(skier)
	for hz: int in TEST_HZ:
		_run_spawn_settle_descent(skier, hz)
	_test_non_deliberate_air_is_not_spawn_settle(skier)
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_reset_contact_is_fresh(skier: SkierController) -> void:
	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 8.0, 0.0)))
	var stale_distance := skier.contact.average_distance
	var stale_hits := skier.contact.hit_points.size()
	var published_state := [-1]
	var published_left_distance := [-1.0]
	var published_hits := [-1]
	var published_spawn_settle := [false]
	skier.respawn_applied.connect(func(_value: Transform3D) -> void:
		published_state[0] = skier.state
		published_left_distance[0] = skier.animation_frame.left_ground_distance
		published_hits[0] = skier.contact.hit_points.size()
		published_spawn_settle[0] = skier._spawn_settle_active
	, CONNECT_ONE_SHOT)
	var hover := Transform3D(Basis.IDENTITY, Vector3(0.0, SPAWN_SETTLE_HOVER_Y, 0.0))
	skier.respawn_at(hover)
	if skier.state != SkierController.State.AIR or published_state[0] != SkierController.State.AIR:
		failures.append("Spawn reset forced gameplay out of AIR")
	if not skier._spawn_settle_active or not published_spawn_settle[0]:
		failures.append("respawn_at did not enable the spawn-settle window before publishing")
	if skier.contact.hit_points.is_empty() or published_hits[0] <= 0:
		failures.append("Synchronous reset contact stayed empty instead of sampling the support surface")
	if is_equal_approx(skier.contact.average_distance, stale_distance) and skier.contact.hit_points.size() == stale_hits:
		failures.append("Synchronous reset contact reused the stale high-air sample")
	if absf(published_left_distance[0] - skier.contact.left_distance) > 0.0001:
		failures.append("First published reset pose did not use the fresh contact sample")
	var reset_pose := _visible_pose(skier)
	skier._update_animation(1.0 / 120.0)
	var first_step := _pose_distance(reset_pose, _visible_pose(skier))
	if first_step > 0.03:
		failures.append("Spawn reset pose jumped %.3f m on the first published frame" % first_step)

func _run_spawn_settle_descent(skier: SkierController, hz: int) -> void:
	var delta := 1.0 / float(hz)
	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, SPAWN_SETTLE_HOVER_Y, 0.0)))
	if skier.state != SkierController.State.AIR:
		failures.append("Spawn settle at %d Hz did not begin in AIR" % hz)
		return
	var landed_emitted := [false]
	var on_landed := func(_result: Dictionary) -> void: landed_emitted[0] = true
	skier.landed.connect(on_landed)
	var previous_gap := INF
	var frames := 0
	var frame_limit := int(ceil(2.0 * float(hz)))
	while skier.state == SkierController.State.AIR and frames < frame_limit:
		skier._physics_process(delta)
		frames += 1
		if skier.state != SkierController.State.AIR:
			break
		if not skier._spawn_settle_active:
			failures.append("Spawn settle at %d Hz cleared before quiet reseat" % hz)
			break
		var into := skier.velocity.dot(skier.contact.average_normal)
		if into < -skier.profile.seat_approach_speed - 0.0001:
			failures.append("Spawn settle at %d Hz exceeded seat_approach_speed (into=%.4f)" % [hz, into])
			break
		if skier.contact.hit_points.is_empty():
			continue
		var gap := skier._seat_clearance()
		if previous_gap < INF and gap > previous_gap + 0.002:
			failures.append("Spawn settle at %d Hz increased seat distance from %.3f to %.3f" % [hz, previous_gap, gap])
			break
		previous_gap = gap
	if skier.landed.is_connected(on_landed):
		skier.landed.disconnect(on_landed)
	if skier.state != SkierController.State.GROUND:
		failures.append("Spawn settle at %d Hz did not reach GROUND through quiet reseat" % hz)
	elif skier._spawn_settle_active:
		failures.append("Spawn settle at %d Hz stayed active after GROUND" % hz)
	elif landed_emitted[0]:
		failures.append("Spawn settle at %d Hz emitted a landing event" % hz)
	elif skier.animation_controller._landing_active or skier.animation_controller._stomp_active:
		failures.append("Spawn settle at %d Hz invoked landing crouch presentation" % hz)
	elif bool(skier.landing_context.get("active", false)):
		failures.append("Spawn settle at %d Hz left landing context active" % hz)

func _test_non_deliberate_air_is_not_spawn_settle(skier: SkierController) -> void:
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.85, 0.0)), Vector3(0.0, -5.0, 0.0))
	skier.air_deliberate = false
	skier.landing_feedback_armed = true
	if skier._spawn_settle_active:
		failures.append("Non-deliberate AIR inferred spawn settle from air_deliberate == false")
		return
	skier._physics_process(1.0 / 60.0)
	if skier.velocity.y > -5.0:
		failures.append("Ordinary non-deliberate AIR was clamped by spawn settle (vy=%.3f)" % skier.velocity.y)

func _visible_pose(skier: SkierController) -> Array[Vector3]:
	var rig := skier.animation_controller
	var result: Array[Vector3] = []
	for point: Vector3 in rig.rig_adapter.landmarks().values():
		result.append(skier.to_local(point))
	for joint: Node3D in [rig.left_ski, rig.right_ski, rig.left_pole, rig.right_pole]:
		result.append(skier.to_local(joint.global_position))
		result.append(skier.to_local(joint.to_global(Vector3.FORWARD)))
	return result

func _pose_distance(first: Array[Vector3], second: Array[Vector3]) -> float:
	var maximum := 0.0
	for index: int in first.size():
		maximum = maxf(maximum, first[index].distance_to(second[index]))
	return maximum

func _make_box_body(body_name: String, layer: int, size: Vector3, body_position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = body_position
	add_child(body)
	return body

func _basis_valid(value: Basis) -> bool:
	return (
		value.x.is_finite()
		and value.y.is_finite()
		and value.z.is_finite()
		and absf(value.x.length() - 1.0) <= BASIS_TOLERANCE
		and absf(value.y.length() - 1.0) <= BASIS_TOLERANCE
		and absf(value.z.length() - 1.0) <= BASIS_TOLERANCE
		and absf(value.x.dot(value.y)) <= BASIS_TOLERANCE
		and absf(value.y.dot(value.z)) <= BASIS_TOLERANCE
		and absf(value.z.dot(value.x)) <= BASIS_TOLERANCE
		and absf(value.determinant() - 1.0) <= BASIS_TOLERANCE
	)
