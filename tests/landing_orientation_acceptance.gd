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

	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("LANDING_ORIENTATION_PASS: bounded deliberate landing orientation, residual rotation, slope, steering, and 30/60/120 Hz continuity passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("LANDING_ORIENTATION_FAIL: " + failure)
	get_tree().quit(1)

func _run_case(scenario: String, hz: int) -> Dictionary:
	Input.action_release("steer_left")
	var setup := _scenario_setup(scenario)
	var normal: Vector3 = setup.normal
	var touchdown_basis: Basis = setup.basis
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.state = SkierController.State.AIR
	skier.air_deliberate = true
	skier.air_time = 0.8
	skier.landing_feedback_armed = false
	skier.contact.grounded = true
	skier.contact.average_normal = normal
	skier.contact.last_normal = normal
	skier.global_basis = touchdown_basis
	skier.velocity = setup.velocity
	skier.angular_velocity = setup.angular_velocity

	var before_basis := skier.global_basis
	skier._handle_landing()
	var touchdown_rotation := _basis_angle(before_basis, skier.global_basis)
	if touchdown_rotation > TOUCHDOWN_SNAP_LIMIT:
		failures.append("%s at %d Hz changed root orientation by %.3f degrees inside _handle_landing()" % [scenario, hz, rad_to_deg(touchdown_rotation)])
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
		Input.action_press("steer_left", 1.0)

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
		Input.action_release("steer_left")
		if not steering_seen:
			failures.append("Immediate steering input was ignored during landing settle at %d Hz" % hz)
		if _basis_angle(before_basis, skier.global_basis) < deg_to_rad(2.0):
			failures.append("Immediate steering input did not produce responsive heading change at %d Hz" % hz)
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
