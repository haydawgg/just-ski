extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_identity_for_zero_velocity()
	_test_frame_rate_equivalence()
	_test_mixed_axis_stability()
	_test_local_to_world_conversion()
	if failures.is_empty():
		print("AIR_ROTATION_INTEGRATOR_PASS: quaternion integration is stable and frame-rate consistent")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("AIR_ROTATION_INTEGRATOR_FAIL: " + failure)
		get_tree().quit(1)

func _test_identity_for_zero_velocity() -> void:
	var initial := Basis(Vector3.UP, deg_to_rad(23.0))
	var result := AirRotationIntegrator.integrate_basis(initial, Vector3.ZERO, 1.0 / 60.0)
	if not _basis_close(result, initial.orthonormalized(), 0.00001):
		failures.append("Zero angular velocity changed the skier orientation")

func _test_frame_rate_equivalence() -> void:
	var angular_velocity := Vector3(2.2, -4.8, 1.7)
	var at_30 := _integrate_for_one_second(angular_velocity, 30)
	var at_60 := _integrate_for_one_second(angular_velocity, 60)
	var at_120 := _integrate_for_one_second(angular_velocity, 120)
	if not _basis_close(at_30, at_60, 0.001):
		failures.append("Quaternion integration diverged between 30 and 60 Hz")
	if not _basis_close(at_60, at_120, 0.001):
		failures.append("Quaternion integration diverged between 60 and 120 Hz")

func _test_mixed_axis_stability() -> void:
	var basis := Basis.IDENTITY
	var angular_velocity := Vector3(4.5, -5.1, 3.7)
	for index: int in range(720):
		basis = AirRotationIntegrator.integrate_basis(basis, angular_velocity, 1.0 / 120.0)
	if absf(basis.x.length() - 1.0) > 0.001 or absf(basis.y.length() - 1.0) > 0.001 or absf(basis.z.length() - 1.0) > 0.001:
		failures.append("Long mixed-axis integration lost normalized basis axes")
	if absf(basis.x.dot(basis.y)) > 0.001 or absf(basis.y.dot(basis.z)) > 0.001 or absf(basis.z.dot(basis.x)) > 0.001:
		failures.append("Long mixed-axis integration lost basis orthogonality")
	if absf(basis.determinant() - 1.0) > 0.001:
		failures.append("Long mixed-axis integration produced an invalid rotation basis")

func _test_local_to_world_conversion() -> void:
	var basis := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	var local_rate := Vector3.UP * 3.0
	var expected := basis.orthonormalized().y * 3.0
	var actual := AirRotationIntegrator.local_to_world_angular_velocity(basis, local_rate)
	if actual.distance_to(expected) > 0.0001:
		failures.append("Local angular velocity did not convert into the gameplay world frame")

func _integrate_for_one_second(angular_velocity: Vector3, hz: int) -> Basis:
	var basis := Basis.IDENTITY
	var delta := 1.0 / float(hz)
	for index: int in range(hz):
		basis = AirRotationIntegrator.integrate_basis(basis, angular_velocity, delta)
	return basis

func _basis_close(a: Basis, b: Basis, tolerance: float) -> bool:
	return (
		a.x.distance_to(b.x) <= tolerance
		and a.y.distance_to(b.y) <= tolerance
		and a.z.distance_to(b.z) <= tolerance
	)
