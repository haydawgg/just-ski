class_name SecondaryMotionLayer
extends RefCounted

var result := SecondaryMotionResult.new()

var _initialized := false
var _previous_vertical_velocity := 0.0
var _previous_yaw_rate := 0.0
var _previous_landing_compression := 0.0
var _previous_left_hand_position := Vector3.ZERO
var _previous_right_hand_position := Vector3.ZERO
var _previous_left_hand_velocity := Vector3.ZERO
var _previous_right_hand_velocity := Vector3.ZERO
var _filtered_left_hand_accel := Vector3.ZERO
var _filtered_right_hand_accel := Vector3.ZERO

const STATE_BAIL := 3

func reset(left_hand_position: Vector3 = Vector3.ZERO, right_hand_position: Vector3 = Vector3.ZERO) -> void:
	result.reset()
	_initialized = false
	_previous_vertical_velocity = 0.0
	_previous_yaw_rate = 0.0
	_previous_landing_compression = 0.0
	_previous_left_hand_position = left_hand_position
	_previous_right_hand_position = right_hand_position
	_previous_left_hand_velocity = Vector3.ZERO
	_previous_right_hand_velocity = Vector3.ZERO
	_filtered_left_hand_accel = Vector3.ZERO
	_filtered_right_hand_accel = Vector3.ZERO

func step(
	frame: SkierAnimationFrame,
	delta: float,
	profile: SkierAnimationProfile,
	state_changed: bool,
	landing_compression: float,
	rail_entry_compression: float,
	trick_pose_weight: float,
	grab_pose_weight: float,
	grab_contact_weight: float,
	crossover: float,
	spin_compactness: float,
	grab_compactness: float,
	grab_left_active: bool,
	grab_right_active: bool,
	pelvis_carve: float,
	torso_carve: float,
	arm_carve: float,
	compression_velocity: float,
	spotting_weight: float,
	left_hand_position: Vector3,
	right_hand_position: Vector3
) -> SecondaryMotionResult:
	var safe_delta := maxf(delta, 0.0001)
	if state_changed:
		result.state_transition_weight = 0.0
	result.state_transition_weight = _damp(result.state_transition_weight, 1.0, profile.secondary_release_response, delta)

	var bounded_lateral := clampf(
		frame.lateral_acceleration,
		-profile.secondary_max_lateral_accel,
		profile.secondary_max_lateral_accel
	)
	var bounded_yaw_rate := clampf(
		frame.angular_velocity.y,
		-profile.trick_max_animation_rate,
		profile.trick_max_animation_rate
	)
	var raw_vertical_accel := 0.0
	var raw_yaw_accel := 0.0
	if _initialized:
		raw_vertical_accel = (frame.vertical_velocity - _previous_vertical_velocity) / safe_delta
		raw_yaw_accel = (bounded_yaw_rate - _previous_yaw_rate) / safe_delta
	result.landing_compression_velocity = (
		(landing_compression - _previous_landing_compression) / safe_delta
		if _initialized
		else 0.0
	)
	raw_vertical_accel = clampf(raw_vertical_accel, -profile.secondary_max_vertical_accel, profile.secondary_max_vertical_accel)
	raw_yaw_accel = clampf(raw_yaw_accel, -profile.secondary_max_yaw_accel, profile.secondary_max_yaw_accel)
	result.filtered_lateral_accel = _damp(result.filtered_lateral_accel, bounded_lateral, profile.secondary_signal_response, delta)
	result.filtered_vertical_accel = _damp(result.filtered_vertical_accel, raw_vertical_accel, profile.secondary_signal_response, delta)
	result.filtered_yaw_accel = _damp(result.filtered_yaw_accel, raw_yaw_accel, profile.secondary_signal_response, delta)
	result.filtered_heading_delta = _damp(
		result.filtered_heading_delta,
		clampf(frame.heading_velocity_delta, -0.9, 0.9),
		profile.head_stabilization_response,
		delta
	)

	if _initialized:
		var left_velocity := (left_hand_position - _previous_left_hand_position) / safe_delta
		var right_velocity := (right_hand_position - _previous_right_hand_position) / safe_delta
		var left_accel := (left_velocity - _previous_left_hand_velocity) / safe_delta
		var right_accel := (right_velocity - _previous_right_hand_velocity) / safe_delta
		left_accel = _limit_vector(left_accel, profile.secondary_max_vertical_accel)
		right_accel = _limit_vector(right_accel, profile.secondary_max_vertical_accel)
		_filtered_left_hand_accel = _damp_vector(_filtered_left_hand_accel, left_accel, profile.secondary_signal_response, delta)
		_filtered_right_hand_accel = _damp_vector(_filtered_right_hand_accel, right_accel, profile.secondary_signal_response, delta)
		_previous_left_hand_velocity = left_velocity
		_previous_right_hand_velocity = right_velocity
	_previous_left_hand_position = left_hand_position
	_previous_right_hand_position = right_hand_position
	_previous_vertical_velocity = frame.vertical_velocity
	_previous_yaw_rate = bounded_yaw_rate
	_previous_landing_compression = landing_compression
	_initialized = true

	var acceleration_value := acceleration_activity(
		result.filtered_lateral_accel,
		result.filtered_vertical_accel,
		result.filtered_yaw_accel,
		profile
	)
	var state_value := state_activity(
		landing_compression,
		rail_entry_compression,
		trick_pose_weight,
		grab_pose_weight,
		crossover
	)
	var secondary_target := target(
		acceleration_value,
		state_value,
		frame.speed_ratio,
		frame.locomotion_state == STATE_BAIL
	)
	result.secondary_motion_weight = _damp(result.secondary_motion_weight, secondary_target, profile.secondary_signal_response, delta)

	var torso_target := Vector3(
		-result.filtered_vertical_accel * profile.torso_vertical_accel_gain,
		-result.filtered_yaw_accel * profile.torso_yaw_accel_gain,
		(pelvis_carve - torso_carve) * profile.torso_carve_lag_gain
			- result.filtered_lateral_accel * profile.torso_lateral_accel_gain
	)
	torso_target *= lerpf(1.0, 0.62, trick_pose_weight) * result.secondary_motion_weight
	torso_target = _limit_vector_components(torso_target, profile.torso_follow_limit)
	result.torso_follow_through = _damp_vector(result.torso_follow_through, torso_target, profile.torso_follow_response, delta)
	var head_target := -result.torso_follow_through * profile.head_stabilization_gain * (1.0 - spotting_weight * 0.78)
	result.head_stabilization = _damp_vector(result.head_stabilization, head_target, profile.head_stabilization_response, delta)

	var compact_arm_scale := lerpf(1.0, 0.48, maxf(spin_compactness, grab_compactness * 0.65))
	var common_arm_target := Vector3(
		-result.filtered_vertical_accel * profile.arm_vertical_accel_gain,
		-result.filtered_yaw_accel * profile.arm_yaw_accel_gain,
		-result.filtered_lateral_accel * profile.arm_lateral_accel_gain
	) * compact_arm_scale * result.secondary_motion_weight
	var left_arm_target := common_arm_target + Vector3(0.0, 0.0, (pelvis_carve - arm_carve) * profile.torso_carve_lag_gain * 0.32)
	var right_arm_target := common_arm_target + Vector3(0.0, 0.0, (pelvis_carve - arm_carve) * profile.torso_carve_lag_gain * 0.24)
	var grab_constraint := maxf(grab_pose_weight * 0.9, grab_contact_weight)
	if grab_left_active:
		left_arm_target *= 1.0 - grab_constraint * 0.95
	if grab_right_active:
		right_arm_target *= 1.0 - grab_constraint * 0.95
	left_arm_target = _limit_vector_components(left_arm_target, profile.arm_inertia_limit)
	right_arm_target = _limit_vector_components(right_arm_target, profile.arm_inertia_limit)
	result.left_arm_inertia = _damp_vector(result.left_arm_inertia, left_arm_target, profile.arm_inertia_response, delta)
	result.right_arm_inertia = _damp_vector(result.right_arm_inertia, right_arm_target, profile.arm_inertia_response, delta)

	var pole_tightness := lerpf(1.0, 0.58, spin_compactness)
	var left_pole_target := Vector3(
		-_filtered_left_hand_accel.z * profile.pole_hand_accel_gain,
		-result.filtered_yaw_accel * profile.pole_yaw_accel_gain,
		_filtered_left_hand_accel.x * profile.pole_hand_accel_gain
	) * pole_tightness * result.secondary_motion_weight - result.left_arm_inertia * 0.28
	var right_pole_target := Vector3(
		-_filtered_right_hand_accel.z * profile.pole_hand_accel_gain,
		-result.filtered_yaw_accel * profile.pole_yaw_accel_gain,
		_filtered_right_hand_accel.x * profile.pole_hand_accel_gain
	) * pole_tightness * result.secondary_motion_weight - result.right_arm_inertia * 0.28
	left_pole_target = _limit_vector_components(left_pole_target, profile.pole_inertia_limit)
	right_pole_target = _limit_vector_components(right_pole_target, profile.pole_inertia_limit)
	var pole_response := profile.pole_inertia_response if left_pole_target.length_squared() + right_pole_target.length_squared() > 0.0002 else profile.pole_release_response
	result.left_pole_inertia = _damp_vector(result.left_pole_inertia, left_pole_target, pole_response, delta)
	result.right_pole_inertia = _damp_vector(result.right_pole_inertia, right_pole_target, pole_response, delta)

	var rebound_target := clampf(
		(-compression_velocity * profile.leg_rebound_gain
			- result.landing_compression_velocity * profile.landing_rebound_gain) * result.secondary_motion_weight,
		-profile.leg_rebound_limit,
		profile.leg_rebound_limit
	)
	result.leg_rebound = _damp(result.leg_rebound, rebound_target, profile.leg_rebound_response, delta)
	return result

func acceleration_activity(lateral: float, vertical: float, yaw: float, profile: SkierAnimationProfile) -> float:
	return maxf(
		absf(lateral) / maxf(profile.secondary_max_lateral_accel, 0.01),
		maxf(absf(vertical) / maxf(profile.secondary_max_vertical_accel, 0.01), absf(yaw) / maxf(profile.secondary_max_yaw_accel, 0.01))
	)

func state_activity(landing_compression: float, rail_compression: float, trick_weight: float, grab_weight: float, crossover: float) -> float:
	return maxf(landing_compression, maxf(rail_compression, maxf(trick_weight, maxf(grab_weight, crossover))))

func target(acceleration: float, state: float, speed_ratio: float, bail: bool) -> float:
	if bail:
		return 0.0
	return clampf(acceleration * 0.62 + state * 0.48 + smoothstep(0.08, 0.85, clampf(speed_ratio, 0.0, 1.0)) * 0.16, 0.0, 1.0)

func _damp(current: float, target_value: float, response: float, delta: float) -> float:
	return lerpf(current, target_value, 1.0 - exp(-response * delta))

func _damp_vector(current: Vector3, target_value: Vector3, response: float, delta: float) -> Vector3:
	return current.lerp(target_value, 1.0 - exp(-response * delta))

func _limit_vector(value: Vector3, maximum_length: float) -> Vector3:
	return value.limit_length(maxf(maximum_length, 0.0))

func _limit_vector_components(value: Vector3, limit: float) -> Vector3:
	return Vector3(
		clampf(value.x, -limit, limit),
		clampf(value.y, -limit, limit),
		clampf(value.z, -limit, limit)
	)
