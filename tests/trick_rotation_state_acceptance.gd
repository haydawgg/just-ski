extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_release_is_frame_rate_independent()
	_test_recorded_release_tracks_applied_budget()
	_test_reference_frame_progress()
	_test_cork_axis_progress()
	_test_authoritative_rotation_vectors()
	_test_continuous_management_and_assist_budget()
	_test_compactness_changes_existing_rotation_only()
	_test_compactness_is_frame_rate_independent()
	_test_reset_clears_state()
	if failures.is_empty():
		print("TRICK_ROTATION_STATE_PASS: release, reference-frame progress, and time-based compactness inertia passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("TRICK_ROTATION_STATE_FAIL: " + failure)
		get_tree().quit(1)

func _test_release_is_frame_rate_independent() -> void:
	var expected := Vector3(0.0, -6.9, 0.0)
	var at_30 := _integrate_release(expected, 1.0 / 30.0)
	var at_60 := _integrate_release(expected, 1.0 / 60.0)
	var at_120 := _integrate_release(expected, 1.0 / 120.0)
	if at_30.distance_to(expected) > 0.001:
		failures.append("30 Hz release did not integrate to the requested takeoff impulse")
	if at_60.distance_to(expected) > 0.001:
		failures.append("60 Hz release did not integrate to the requested takeoff impulse")
	if at_120.distance_to(expected) > 0.001:
		failures.append("120 Hz release did not integrate to the requested takeoff impulse")
	if at_30.distance_to(at_120) > 0.001 or at_60.distance_to(at_120) > 0.001:
		failures.append("Takeoff release total changed with physics tick rate")

func _test_recorded_release_tracks_applied_budget() -> void:
	var state := TrickRotationState.new()
	var total := Vector3(0.0, -6.9, 0.0)
	state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, total, 0.14)
	state.record_takeoff_release(total * 0.4, 0.05)
	if absf(state.released_fraction - 0.4) > 0.001:
		failures.append("Gameplay release state did not record the applied takeoff fraction")
	state.record_takeoff_release(total * 0.6, 0.09)
	if state.takeoff_release_active() or absf(state.released_fraction - 1.0) > 0.001:
		failures.append("Gameplay release state did not finish with the full applied budget")

func _test_reference_frame_progress() -> void:
	var state := TrickRotationState.new()
	state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.9, 0.0))
	state.integrate_world_angular_velocity(Vector3(0.0, -TAU, 0.0), 1.0)
	if absf(rad_to_deg(state.primary_progress_radians()) - 360.0) > 0.1:
		failures.append("Spin progress did not integrate around takeoff up")

	var rotated_basis := Basis(Vector3.FORWARD, deg_to_rad(35.0))
	state.begin(TrickCommand.Kind.SPIN_RIGHT, rotated_basis, Vector3(0.0, 6.9, 0.0))
	var world_rate := rotated_basis.y * TAU
	state.integrate_world_angular_velocity(world_rate, 1.0)
	if absf(rad_to_deg(state.primary_progress_radians()) - 360.0) > 0.1:
		failures.append("Spin progress did not stay attached to the captured takeoff reference frame")

func _test_cork_axis_progress() -> void:
	var state := TrickRotationState.new()
	var impulse := Vector3(0.0, -4.8, -5.2)
	state.begin(TrickCommand.Kind.CORK_LEFT, Basis.IDENTITY, impulse)
	var world_rate := state.primary_axis_world * TAU
	state.integrate_world_angular_velocity(world_rate, 0.5)
	if absf(rad_to_deg(state.primary_progress_radians()) - 180.0) > 0.1:
		failures.append("Cork progress did not integrate around the committed diagonal axis")

func _test_authoritative_rotation_vectors() -> void:
	var spin := TrickRotationState.new()
	spin.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.9, 0.0))
	spin.integrate_world_angular_velocity(Vector3(0.0, -TAU, 0.0), 1.0)
	if spin.accumulated_rotation_vector().distance_to(Vector3(0.0, -TAU, 0.0)) > 0.001:
		failures.append("Spin reference progress did not map into authoritative yaw accumulation")
	var coupled_rate := Vector3(0.24, -TAU, -0.31)
	spin.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.8, -0.5))
	spin.integrate_world_angular_velocity(coupled_rate, 1.0)
	if spin.accumulated_rotation_vector().distance_to(coupled_rate) > 0.001:
		failures.append("Authoritative spin accumulation discarded subtle coupled-axis motion")

	var cork := TrickRotationState.new()
	var impulse := Vector3(0.0, -4.0, -5.8)
	cork.begin(TrickCommand.Kind.CORK_LEFT, Basis.IDENTITY, impulse)
	cork.integrate_world_angular_velocity(cork.primary_axis_world * PI, 1.0)
	var cork_rotation := cork.accumulated_rotation_vector()
	if cork_rotation.distance_to(cork.primary_axis_local * PI) > 0.001:
		failures.append("Cork reference progress did not preserve its continuous committed axis")

func _test_continuous_management_and_assist_budget() -> void:
	var state := TrickRotationState.new()
	state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.9, 0.0), 0.14, 0.1)
	if state.control_projection(Vector2.LEFT) != 0.0:
		failures.append("Air management became active before the takeoff gesture recentered")
	state.control_projection(Vector2.ZERO)
	if state.control_projection(Vector2.LEFT) <= 0.99 or state.control_projection(Vector2.RIGHT) >= -0.99:
		failures.append("Continuous air management did not project held input onto the committed axis")
	var first := state.consume_assist_acceleration(Vector3(10.0, 0.0, 0.0), 0.02)
	var second := state.consume_assist_acceleration(Vector3(10.0, 0.0, 0.0), 0.02)
	if absf(first.length() - 0.1) > 0.001 or second.length() > 0.001:
		failures.append("Continuous precision assist exceeded or regenerated its takeoff budget")

func _test_compactness_changes_existing_rotation_only() -> void:
	var compact_state := TrickRotationState.new()
	compact_state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.9, 0.0))
	var baseline := Vector3(0.0, -4.0, 0.0)
	var compact := compact_state.apply_compactness(baseline, 1.0, 0.20)
	if compact.length() <= baseline.length():
		failures.append("Compact body state did not increase/preserve existing angular speed through lower inertia")

	var open_state := TrickRotationState.new()
	open_state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3(0.0, -6.9, 0.0))
	var opened := open_state.apply_compactness(baseline, 0.0, 0.20)
	if opened.length() >= baseline.length():
		failures.append("Open body state did not reduce existing angular speed through higher inertia")

	var zero_state := TrickRotationState.new()
	zero_state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3.ZERO)
	var zero_result := zero_state.apply_compactness(Vector3.ZERO, 1.0, 0.20)
	if zero_result != Vector3.ZERO:
		failures.append("Compactness created rotation from a neutral angular state")

func _test_compactness_is_frame_rate_independent() -> void:
	var compact_30 := _hold_compactness_for_one_second(1.0, 30)
	var compact_60 := _hold_compactness_for_one_second(1.0, 60)
	var compact_120 := _hold_compactness_for_one_second(1.0, 120)
	if compact_30.distance_to(compact_60) > 0.002 or compact_60.distance_to(compact_120) > 0.002:
		failures.append("One second of compact body input changed angular speed across 30/60/120 Hz")

	var open_30 := _hold_compactness_for_one_second(0.0, 30)
	var open_60 := _hold_compactness_for_one_second(0.0, 60)
	var open_120 := _hold_compactness_for_one_second(0.0, 120)
	if open_30.distance_to(open_60) > 0.002 or open_60.distance_to(open_120) > 0.002:
		failures.append("One second of open body input changed angular speed across 30/60/120 Hz")

func _test_reset_clears_state() -> void:
	var state := TrickRotationState.new()
	state.begin(TrickCommand.Kind.SPIN_RIGHT, Basis.IDENTITY, Vector3(0.0, 6.9, 0.0))
	state.consume_takeoff_release(0.05)
	state.integrate_world_angular_velocity(Vector3(0.0, TAU, 0.0), 0.5)
	state.compactness = 0.8
	state.inertia_scale = 0.75
	state.assist_angular_contribution = Vector3.ONE
	state.reset()
	if state.active or state.kind != TrickCommand.Kind.NONE:
		failures.append("Rotation state remained active after reset")
	if state.released_fraction != 0.0 or state.primary_progress_radians() != 0.0:
		failures.append("Rotation release/progress survived reset")
	if state.compactness != 0.5 or state.inertia_scale != 1.0 or state.assist_angular_contribution != Vector3.ZERO:
		failures.append("Rotation management telemetry survived reset")

func _integrate_release(expected: Vector3, delta: float) -> Vector3:
	var state := TrickRotationState.new()
	state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, expected, 0.14)
	var total := Vector3.ZERO
	var guard := 0
	while state.takeoff_release_active() and guard < 1000:
		total += state.consume_takeoff_release(delta)
		guard += 1
	return total

func _hold_compactness_for_one_second(compactness: float, hz: int) -> Vector3:
	var state := TrickRotationState.new()
	state.begin(TrickCommand.Kind.SPIN_LEFT, Basis.IDENTITY, Vector3.ZERO)
	var angular_velocity := Vector3(0.0, -4.0, 0.0)
	var delta := 1.0 / float(hz)
	for index: int in range(hz):
		angular_velocity = state.apply_compactness(angular_velocity, compactness, delta)
	return angular_velocity
