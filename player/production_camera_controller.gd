class_name ProductionSkiCameraController
extends SkiCameraController

## Production integration layer for carve composition. The base camera keeps
## heading/travel divergence for skid and hockey-stop semantics, but a clean
## carve can keep those vectors almost aligned while the trajectory is turning
## strongly. Measure real planar trajectory curvature and inject a bounded
## camera-only signed turn signal while the base camera performs its normal
## composition pass. The skier telemetry is restored immediately afterward so
## VFX, HUD, and physics continue to see the true heading/travel divergence.

@export_range(5.0, 90.0, 1.0) var turn_rate_reference_degrees_per_second := 28.0
@export_range(5.0, 60.0, 1.0) var maximum_camera_turn_signal_degrees := 32.0
@export_range(1.0, 20.0, 0.5) var turn_rate_response := 8.0
@export_range(0.0, 10.0, 0.25) var minimum_turn_rate_degrees_per_second := 2.0

var _previous_planar_heading_for_lead := Vector3.ZERO
var _smoothed_trajectory_turn_rate_degrees_per_second := 0.0
var _camera_turn_signal_degrees := 0.0

func reset_immediate() -> void:
	super.reset_immediate()
	_previous_planar_heading_for_lead = Vector3.ZERO
	_smoothed_trajectory_turn_rate_degrees_per_second = 0.0
	_camera_turn_signal_degrees = 0.0
	_seed_turn_heading()

func _physics_process(delta: float) -> void:
	var skier := target as SkierController
	var original_heading_travel := 0.0
	var injected := false
	if skier != null:
		original_heading_travel = skier.heading_travel_angle_degrees
		var signal := _trajectory_turn_signal(skier, delta)
		# Never reinterpret braking/skid divergence. During ordinary grounded
		# carving, whichever signed signal has greater magnitude owns the camera
		# look for this one camera update only.
		if not skier.braking and skier.state == SkierController.State.GROUND and absf(signal) > absf(original_heading_travel):
			skier.heading_travel_angle_degrees = signal
			injected = true
	super._physics_process(delta)
	if injected and skier != null:
		skier.heading_travel_angle_degrees = original_heading_travel

func _trajectory_turn_signal(skier: SkierController, delta: float) -> float:
	if skier == null or target == null:
		return 0.0
	var safe_delta := maxf(delta, 0.0001)
	var up := _filtered_surface_up.normalized() if _filtered_surface_up.length_squared() > 0.01 else Vector3.UP
	var planar := target.velocity.slide(up)
	if skier.state != SkierController.State.GROUND or planar.length() <= trajectory_heading_speed_threshold:
		_previous_planar_heading_for_lead = Vector3.ZERO
		_smoothed_trajectory_turn_rate_degrees_per_second = move_toward(
			_smoothed_trajectory_turn_rate_degrees_per_second,
			0.0,
			turn_rate_response * safe_delta * turn_rate_reference_degrees_per_second
		)
		_camera_turn_signal_degrees = 0.0
		return 0.0
	var heading := planar.normalized()
	if _previous_planar_heading_for_lead.length_squared() < 0.5:
		_previous_planar_heading_for_lead = heading
		return 0.0
	var signed_step := _previous_planar_heading_for_lead.signed_angle_to(heading, up)
	_previous_planar_heading_for_lead = heading
	var turn_rate := rad_to_deg(signed_step) / safe_delta
	# Reject single-frame reversals/noise; the physical skier steering envelope
	# is far below this and sustained curves will survive the clamp unchanged.
	turn_rate = clampf(turn_rate, -120.0, 120.0)
	var response_weight := 1.0 - exp(-turn_rate_response * safe_delta)
	_smoothed_trajectory_turn_rate_degrees_per_second = lerpf(
		_smoothed_trajectory_turn_rate_degrees_per_second,
		turn_rate,
		response_weight
	)
	if absf(_smoothed_trajectory_turn_rate_degrees_per_second) < minimum_turn_rate_degrees_per_second:
		_camera_turn_signal_degrees = 0.0
		return 0.0
	var normalized_rate := clampf(
		absf(_smoothed_trajectory_turn_rate_degrees_per_second) / maxf(turn_rate_reference_degrees_per_second, 0.1),
		0.0,
		1.0
	)
	_camera_turn_signal_degrees = signf(_smoothed_trajectory_turn_rate_degrees_per_second) * normalized_rate * maximum_camera_turn_signal_degrees
	return _camera_turn_signal_degrees

func _seed_turn_heading() -> void:
	if target == null:
		return
	var up := _filtered_surface_up.normalized() if _filtered_surface_up.length_squared() > 0.01 else Vector3.UP
	var planar := target.velocity.slide(up)
	if planar.length() > trajectory_heading_speed_threshold:
		_previous_planar_heading_for_lead = planar.normalized()

func debug_snapshot() -> Dictionary:
	var snapshot := super.debug_snapshot()
	snapshot["trajectory_turn_rate_degrees_per_second"] = _smoothed_trajectory_turn_rate_degrees_per_second
	snapshot["camera_turn_signal_degrees"] = _camera_turn_signal_degrees
	return snapshot
