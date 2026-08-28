class_name SkierAnimationController
extends Node3D

enum AnimationEvent {
	POP,
	LAND_CLEAN,
	LAND_SKETCHY,
	LAND_HARD,
	GRIND_ENTER,
	GRIND_EXIT,
	BAIL,
	RESPAWN,
}

const STATE_GROUND := 0
const STATE_AIR := 1
const STATE_GRIND := 2
const STATE_BAIL := 3

@export var profile: SkierAnimationProfile = preload("res://resources/animation/default_animation_profile.tres")

var balance_root: Node3D
var pelvis: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var left_hip: Node3D
var right_hip: Node3D
var left_knee: Node3D
var right_knee: Node3D
var left_boot: Node3D
var right_boot: Node3D
var left_ski: Node3D
var right_ski: Node3D
var left_shoulder: Node3D
var right_shoulder: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_hand: Node3D
var right_hand: Node3D
var left_pole: Node3D
var right_pole: Node3D

var _rotation_targets: Dictionary = {}
var _position_targets: Dictionary = {}
var _elapsed := 0.0
var _reaction_event := -1
var _reaction_time := 0.0
var _reaction_duration := 0.0
var _reaction_strength := 0.0
var _reaction_side := 0.0
var _current_state := STATE_AIR
var _current_pose_name := "Air Neutral"
var _current_blend := 0.0
var _layer_weight := 1.0
var _grab_target_world := Vector3.ZERO
var _grab_hand: Node3D
var _crouch_amount := 0.0
var _carve_target := 0.0
var _ski_carve := 0.0
var _leg_carve := 0.0
var _pelvis_carve := 0.0
var _torso_carve := 0.0
var _arm_carve := 0.0
var _pole_carve := 0.0
var _last_loaded_direction := 0.0
var _crossover_time := 0.0
var _terrain_influence := 0.0
var _terrain_correction_influence := 0.0
var _left_contact_confidence := 0.0
var _right_contact_confidence := 0.0
var _left_terrain_weight := 0.0
var _right_terrain_weight := 0.0
var _left_terrain_gap := 0.0
var _right_terrain_gap := 0.0
var _left_terrain_flex := 0.0
var _right_terrain_flex := 0.0
var _terrain_pelvis_offset := 0.0
var _terrain_pelvis_roll_amount := 0.0
var _left_terrain_normal := Vector3.UP
var _right_terrain_normal := Vector3.UP
var _left_terrain_angles := Vector2.ZERO
var _right_terrain_angles := Vector2.ZERO
var _left_leg_compression := 0.0
var _right_leg_compression := 0.0
var _average_leg_compression := 0.0
var _previous_average_compression := 0.0
var _compression_velocity := 0.0
var _left_foot_target_world := Vector3.ZERO
var _right_foot_target_world := Vector3.ZERO
var _pelvis_target_world := Vector3.ZERO
var _jump_anticipation := 0.0
var _air_size := 0.0
var _air_takeoff_weight := 0.0
var _air_early_weight := 0.0
var _air_apex_weight := 0.0
var _air_descent_weight := 0.0
var _air_flex := 0.0
var _air_phase_name := "Ground"

func _ready() -> void:
	_build_articulated_rig()

func apply_frame(frame: SkierAnimationFrame, delta: float) -> void:
	_elapsed += delta
	_current_state = frame.locomotion_state
	_update_skiing_dynamics(frame, delta)
	_update_terrain_suspension(frame, delta)
	_update_jump_animation(frame, delta)
	_reset_targets()
	match frame.locomotion_state:
		STATE_GROUND: _apply_ground_pose(frame)
		STATE_AIR: _apply_air_pose(frame)
		STATE_GRIND: _apply_grind_pose(frame)
		STATE_BAIL: _apply_bail_pose(frame)
	_apply_trick_layer(frame)
	_apply_reaction(frame, delta)
	_apply_secondary_motion(frame)
	_blend_targets(delta)

func trigger(event: int, strength: float = 1.0, side: float = 0.0) -> void:
	_reaction_event = event
	_reaction_time = 0.0
	_reaction_strength = clampf(strength, 0.0, 1.5)
	_reaction_side = clampf(side, -1.0, 1.0)
	match event:
		AnimationEvent.POP: _reaction_duration = profile.pop_duration
		AnimationEvent.LAND_CLEAN: _reaction_duration = profile.clean_landing_duration
		AnimationEvent.LAND_SKETCHY: _reaction_duration = profile.sketchy_landing_duration
		AnimationEvent.LAND_HARD: _reaction_duration = profile.hard_landing_duration
		AnimationEvent.GRIND_ENTER, AnimationEvent.GRIND_EXIT: _reaction_duration = 0.28
		AnimationEvent.BAIL: _reaction_duration = 1.2
		AnimationEvent.RESPAWN:
			_reaction_duration = 0.0
			_reset_pose_immediately()

func debug_snapshot() -> Dictionary:
	return {
		"state": ["GROUND", "AIR", "GRIND", "BAIL"][_current_state],
		"pose": _current_pose_name,
		"blend": _current_blend,
		"reaction": _reaction_event,
		"reaction_time": _reaction_time,
		"pelvis_height": pelvis.position.y,
		"pelvis_position": pelvis.position,
		"pelvis_rotation": pelvis.rotation,
		"chest_rotation": chest.rotation,
		"head_rotation": head.rotation,
		"left_knee_rotation": left_knee.rotation,
		"right_knee_rotation": right_knee.rotation,
		"left_ski_rotation": left_ski.rotation,
		"right_ski_rotation": right_ski.rotation,
		"left_pole_rotation": left_pole.rotation,
		"right_pole_rotation": right_pole.rotation,
		"crouch": _crouch_amount,
		"carve_target": _carve_target,
		"ski_carve": _ski_carve,
		"leg_carve": _leg_carve,
		"pelvis_carve": _pelvis_carve,
		"torso_carve": _torso_carve,
		"arm_carve": _arm_carve,
		"crossover": _crossover_release(),
		"terrain_influence": _terrain_influence,
		"terrain_correction_influence": _terrain_correction_influence,
		"left_contact_confidence": _left_contact_confidence,
		"right_contact_confidence": _right_contact_confidence,
		"left_terrain_weight": _left_terrain_weight,
		"right_terrain_weight": _right_terrain_weight,
		"left_gap": _left_terrain_gap,
		"right_gap": _right_terrain_gap,
		"left_leg_compression": _left_leg_compression,
		"right_leg_compression": _right_leg_compression,
		"average_leg_compression": _average_leg_compression,
		"compression_velocity": _compression_velocity,
		"terrain_pelvis_offset": _terrain_pelvis_offset,
		"terrain_pelvis_roll": _terrain_pelvis_roll_amount,
		"left_terrain_angles": _left_terrain_angles,
		"right_terrain_angles": _right_terrain_angles,
		"left_foot_target_world": _left_foot_target_world,
		"right_foot_target_world": _right_foot_target_world,
		"pelvis_target_world": _pelvis_target_world,
		"jump_anticipation": _jump_anticipation,
		"air_size": _air_size,
		"air_phase": _air_phase_name,
		"air_takeoff_weight": _air_takeoff_weight,
		"air_early_weight": _air_early_weight,
		"air_apex_weight": _air_apex_weight,
		"air_descent_weight": _air_descent_weight,
		"air_flex": _air_flex,
		"grab_reach_error": _grab_hand.global_position.distance_to(_grab_target_world) if _grab_hand != null else 0.0,
	}

func _update_skiing_dynamics(frame: SkierAnimationFrame, delta: float) -> void:
	var grounded := frame.locomotion_state == STATE_GROUND
	var desired_crouch := smoothstep(0.02, 1.0, frame.speed_ratio) if grounded else 0.0
	_crouch_amount = lerpf(_crouch_amount, desired_crouch, 1.0 - exp(-profile.pose_response * delta))
	_carve_target = _calculate_carve_target(frame) if grounded else 0.0
	if absf(_carve_target) > 0.12:
		var direction := signf(_carve_target)
		if _last_loaded_direction != 0.0 and direction != _last_loaded_direction:
			_crossover_time = profile.crossover_duration
		_last_loaded_direction = direction
	elif not grounded:
		_last_loaded_direction = 0.0
		_crossover_time = 0.0
	if _crossover_time > 0.0:
		_crossover_time = maxf(0.0, _crossover_time - delta)
	_ski_carve = _damp(_ski_carve, _carve_target, profile.ski_carve_response, delta)
	_leg_carve = _damp(_leg_carve, _carve_target, profile.leg_carve_response, delta)
	_pelvis_carve = _damp(_pelvis_carve, _carve_target, profile.pelvis_carve_response, delta)
	_torso_carve = _damp(_torso_carve, _carve_target, profile.torso_carve_response, delta)
	_arm_carve = _damp(_arm_carve, _carve_target, profile.arm_carve_response, delta)
	_pole_carve = _damp(_pole_carve, _arm_carve, profile.secondary_response, delta)

func _calculate_carve_target(frame: SkierAnimationFrame) -> float:
	var edge_strength := absf(clampf(frame.edge, -1.0, 1.0))
	if edge_strength < 0.01:
		return 0.0
	var speed_load := smoothstep(0.08, 0.9, clampf(frame.speed_ratio, 0.0, 1.0))
	var lateral_load := clampf(absf(frame.lateral_acceleration) / maxf(profile.lateral_acceleration_reference, 0.01), 0.0, 1.0)
	var turn_load := clampf(absf(frame.turn_rate) / maxf(profile.turn_rate_reference, 0.01), 0.0, 1.0)
	var intent := absf(clampf(frame.turn_input, -1.0, 1.0))
	var tracking := clampf(frame.carve_ratio, 0.0, 1.0) * (1.0 - clampf(frame.skid_ratio, 0.0, 1.0) * 0.72)
	var physical_load := maxf(lateral_load, turn_load * 0.82)
	var intensity := edge_strength * clampf(
		0.18 + speed_load * 0.22 + physical_load * 0.32 + tracking * 0.16 + intent * 0.12,
		0.0,
		1.0
	)
	if frame.braking:
		intensity *= 0.45
	return signf(frame.edge) * intensity

func _update_jump_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var grounded := frame.locomotion_state == STATE_GROUND and frame.grounded
	var anticipation_target := clampf(frame.compression, 0.0, 1.0) if grounded else 0.0
	_jump_anticipation = _damp(_jump_anticipation, anticipation_target, profile.jump_anticipation_response, delta)
	if frame.locomotion_state != STATE_AIR:
		_air_size = _damp(_air_size, 0.0, profile.air_phase_response, delta)
		_air_takeoff_weight = _damp(_air_takeoff_weight, 0.0, profile.air_phase_response, delta)
		_air_early_weight = _damp(_air_early_weight, 0.0, profile.air_phase_response, delta)
		_air_apex_weight = _damp(_air_apex_weight, 0.0, profile.air_phase_response, delta)
		_air_descent_weight = _damp(_air_descent_weight, 0.0, profile.air_phase_response, delta)
		_air_flex = 0.0
		_air_phase_name = "Ground"
		return

	var takeoff_size := smoothstep(
		minf(profile.air_small_takeoff_speed, profile.air_large_takeoff_speed),
		maxf(profile.air_small_takeoff_speed, profile.air_large_takeoff_speed),
		frame.takeoff_upward_speed
	)
	if frame.takeoff_type == SkierAnimationFrame.TakeoffType.CHARGED_POP:
		takeoff_size = maxf(takeoff_size, frame.takeoff_charge)
	elif frame.takeoff_type == SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF:
		takeoff_size *= 0.82
	_air_size = _damp(_air_size, clampf(takeoff_size, 0.0, 1.0), profile.air_phase_response, delta)

	var hold_time := maxf(profile.air_takeoff_hold_time, 0.02) * lerpf(0.65, 1.15, _air_size)
	var takeoff_target := 1.0 - smoothstep(0.0, hold_time, frame.air_time)
	if frame.takeoff_type == SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF:
		takeoff_target *= lerpf(0.55, 0.82, _air_size)
	var apex_band := maxf(profile.air_apex_velocity_band, 0.05)
	var ascent_reference := maxf(frame.takeoff_upward_speed * 0.82, apex_band * 1.5)
	var early_target := (1.0 - takeoff_target) * smoothstep(apex_band * 0.35, ascent_reference, frame.air_upward_velocity)
	var apex_target := (1.0 - takeoff_target) * (1.0 - smoothstep(apex_band * 0.28, apex_band * 1.35, absf(frame.air_upward_velocity)))
	var descent_target := (1.0 - takeoff_target) * smoothstep(
		apex_band * 0.25,
		maxf(profile.air_descent_velocity_reference, apex_band),
		-frame.air_upward_velocity
	)
	if frame.predicted_landing_time >= 0.0:
		var proximity := 1.0 - smoothstep(0.12, maxf(profile.landing_anticipation_time, 0.13), frame.predicted_landing_time)
		descent_target = maxf(descent_target, proximity * (1.0 - takeoff_target))
	_air_takeoff_weight = _damp(_air_takeoff_weight, takeoff_target, profile.air_phase_response, delta)
	_air_early_weight = _damp(_air_early_weight, early_target, profile.air_phase_response, delta)
	_air_apex_weight = _damp(_air_apex_weight, apex_target, profile.air_phase_response, delta)
	_air_descent_weight = _damp(_air_descent_weight, descent_target, profile.air_phase_response, delta)
	if _air_takeoff_weight > 0.42:
		_air_phase_name = "Takeoff"
	elif _air_descent_weight > 0.28:
		_air_phase_name = "Descent"
	elif _air_apex_weight > 0.32:
		_air_phase_name = "Apex"
	else:
		_air_phase_name = "Early Air"

func _update_terrain_suspension(frame: SkierAnimationFrame, delta: float) -> void:
	var desired_influence := 1.0 if frame.grounded else 0.0
	_terrain_influence = _damp(_terrain_influence, desired_influence, profile.terrain_influence_response, delta)
	var left_confidence_target := frame.left_contact_confidence if frame.grounded and frame.left_grounded else 0.0
	var right_confidence_target := frame.right_contact_confidence if frame.grounded and frame.right_grounded else 0.0
	_left_contact_confidence = _damp(_left_contact_confidence, left_confidence_target, profile.contact_confidence_response, delta)
	_right_contact_confidence = _damp(_right_contact_confidence, right_confidence_target, profile.contact_confidence_response, delta)
	var left_gap_target := frame.left_ground_distance - frame.seat_distance if frame.left_grounded else 0.0
	var right_gap_target := frame.right_ground_distance - frame.seat_distance if frame.right_grounded else 0.0
	_left_terrain_gap = _damp(_left_terrain_gap, left_gap_target, profile.terrain_follow_response, delta)
	_right_terrain_gap = _damp(_right_terrain_gap, right_gap_target, profile.terrain_follow_response, delta)
	var left_feasibility := _terrain_gap_feasibility(_left_terrain_gap)
	var right_feasibility := _terrain_gap_feasibility(_right_terrain_gap)
	_left_terrain_weight = _terrain_influence * _left_contact_confidence * left_feasibility
	_right_terrain_weight = _terrain_influence * _right_contact_confidence * right_feasibility
	_terrain_correction_influence = (_left_terrain_weight + _right_terrain_weight) * 0.5
	var weighted_left_gap := _left_terrain_gap * _left_terrain_weight
	var weighted_right_gap := _right_terrain_gap * _right_terrain_weight
	var average_gap := (weighted_left_gap + weighted_right_gap) * 0.5
	var pelvis_follow := clampf(profile.pelvis_terrain_response, 0.0, 1.0)
	_terrain_pelvis_offset = clampf(
		-(1.0 - pelvis_follow) * average_gap,
		-profile.pelvis_terrain_drop_limit,
		profile.pelvis_terrain_drop_limit
	)
	_terrain_pelvis_roll_amount = clampf(
		(weighted_left_gap - weighted_right_gap) * profile.terrain_pelvis_roll,
		-0.18,
		0.18
	)
	_left_terrain_flex = -(weighted_left_gap - pelvis_follow * average_gap) * profile.terrain_flex_gain
	_right_terrain_flex = -(weighted_right_gap - pelvis_follow * average_gap) * profile.terrain_flex_gain
	var compression_travel := maxf(profile.compression_travel, 0.01)
	_left_leg_compression = clampf(-weighted_left_gap / compression_travel, -1.0, 1.0)
	_right_leg_compression = clampf(-weighted_right_gap / compression_travel, -1.0, 1.0)
	_average_leg_compression = (_left_leg_compression + _right_leg_compression) * 0.5
	var raw_compression_velocity := (_average_leg_compression - _previous_average_compression) / maxf(delta, 0.0001)
	_compression_velocity = _damp(_compression_velocity, raw_compression_velocity, profile.terrain_follow_response, delta)
	_previous_average_compression = _average_leg_compression

	var left_normal_target := _stable_terrain_normal(frame, true, _left_terrain_normal)
	var right_normal_target := _stable_terrain_normal(frame, false, _right_terrain_normal)
	_left_terrain_normal = _damp_normal(_left_terrain_normal, left_normal_target, profile.terrain_normal_response, delta)
	_right_terrain_normal = _damp_normal(_right_terrain_normal, right_normal_target, profile.terrain_normal_response, delta)
	var left_angle_target := _terrain_orientation_target(frame, true, _left_terrain_normal) * _left_terrain_weight
	var right_angle_target := _terrain_orientation_target(frame, false, _right_terrain_normal) * _right_terrain_weight
	_left_terrain_angles = _damp_terrain_angles(_left_terrain_angles, left_angle_target, delta)
	_right_terrain_angles = _damp_terrain_angles(_right_terrain_angles, right_angle_target, delta)
	_left_foot_target_world = frame.left_hit_position if frame.left_grounded else left_ski.global_position
	_right_foot_target_world = frame.right_hit_position if frame.right_grounded else right_ski.global_position

func _terrain_gap_feasibility(gap: float) -> float:
	return 1.0 - smoothstep(
		minf(profile.terrain_discontinuity_soft_gap, profile.terrain_discontinuity_hard_gap),
		maxf(profile.terrain_discontinuity_soft_gap, profile.terrain_discontinuity_hard_gap),
		absf(gap)
	)

func _stable_terrain_normal(frame: SkierAnimationFrame, use_left: bool, current_local: Vector3) -> Vector3:
	var front_valid := frame.left_front_valid if use_left else frame.right_front_valid
	var rear_valid := frame.left_rear_valid if use_left else frame.right_rear_valid
	var front_normal := frame.left_front_normal if use_left else frame.right_front_normal
	var rear_normal := frame.left_rear_normal if use_left else frame.right_rear_normal
	var fallback := frame.left_normal if use_left else frame.right_normal
	var chosen := fallback
	if front_valid and rear_valid:
		var agreement := front_normal.normalized().dot(rear_normal.normalized())
		if agreement >= profile.terrain_normal_agreement_threshold:
			chosen = (front_normal + rear_normal).normalized()
		else:
			var current_world := (global_basis * current_local).normalized()
			chosen = front_normal if front_normal.normalized().dot(current_world) >= rear_normal.normalized().dot(current_world) else rear_normal
	elif front_valid:
		chosen = front_normal
	elif rear_valid:
		chosen = rear_normal
	elif not (frame.left_grounded if use_left else frame.right_grounded):
		chosen = frame.ground_normal
	return _terrain_normal_local(chosen)

func _terrain_orientation_target(frame: SkierAnimationFrame, use_left: bool, stable_normal: Vector3) -> Vector2:
	var angles := _terrain_angles_from_normal(stable_normal)
	var front_valid := frame.left_front_valid if use_left else frame.right_front_valid
	var rear_valid := frame.left_rear_valid if use_left else frame.right_rear_valid
	if front_valid and rear_valid:
		var front_position := frame.left_front_position if use_left else frame.right_front_position
		var rear_position := frame.left_rear_position if use_left else frame.right_rear_position
		var surface_forward_world := front_position - rear_position
		if surface_forward_world.length_squared() > 0.01:
			var surface_forward_local := (global_basis.inverse() * surface_forward_world.normalized()).normalized()
			if -surface_forward_local.z > 0.15:
				angles.x = clampf(
					atan2(surface_forward_local.y, -surface_forward_local.z),
					-profile.max_ankle_pitch,
					profile.max_ankle_pitch
				)
	return angles

func _damp_terrain_angles(current: Vector2, target: Vector2, delta: float) -> Vector2:
	var blend_weight := 1.0 - exp(-maxf(profile.terrain_normal_response, 0.01) * delta)
	var blended := current.lerp(target, blend_weight)
	var maximum_step := maxf(profile.terrain_orientation_speed_limit, 0.01) * delta
	return Vector2(
		move_toward(current.x, blended.x, maximum_step),
		move_toward(current.y, blended.y, maximum_step)
	)

func _terrain_normal_local(world_normal: Vector3) -> Vector3:
	if world_normal.length_squared() < 0.001:
		return Vector3.UP
	var local_normal := global_basis.inverse() * world_normal.normalized()
	return local_normal.normalized() if local_normal.length_squared() > 0.001 else Vector3.UP

func _damp_normal(current: Vector3, target: Vector3, response: float, delta: float) -> Vector3:
	var blended := current.lerp(target, 1.0 - exp(-maxf(response, 0.01) * delta))
	return blended.normalized() if blended.length_squared() > 0.001 else Vector3.UP

func _terrain_angles_from_normal(normal: Vector3) -> Vector2:
	var pitch := clampf(atan2(normal.z, maxf(normal.y, 0.001)), -profile.max_ankle_pitch, profile.max_ankle_pitch)
	var roll := clampf(atan2(-normal.x, maxf(normal.y, 0.001)), -profile.max_ankle_roll, profile.max_ankle_roll)
	return Vector2(pitch, roll)

func _damp(current: float, target: float, response: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-maxf(response, 0.01) * delta))

func _crossover_release() -> float:
	if _crossover_time <= 0.0 or profile.crossover_duration <= 0.0:
		return 0.0
	var progress := 1.0 - _crossover_time / profile.crossover_duration
	return sin(clampf(progress, 0.0, 1.0) * PI)

func _reset_targets() -> void:
	_rotation_targets.clear()
	_position_targets.clear()
	_grab_hand = null
	for joint: Node3D in [
		balance_root, pelvis, spine, chest, head,
		left_hip, right_hip, left_knee, right_knee,
		left_boot, right_boot, left_ski, right_ski,
		left_shoulder, right_shoulder, left_elbow, right_elbow,
		left_hand, right_hand, left_pole, right_pole,
	]:
		_rotation_targets[joint] = Vector3.ZERO
	_position_targets[pelvis] = Vector3(0.0, 0.96, 0.0)
	_position_targets[chest] = Vector3(0.0, 0.42, 0.0)
	_position_targets[left_hip] = Vector3(-0.24, -0.04, 0.0)
	_position_targets[right_hip] = Vector3(0.24, -0.04, 0.0)
	_position_targets[left_shoulder] = Vector3(-0.4, 0.24, 0.0)
	_position_targets[right_shoulder] = Vector3(0.4, 0.24, 0.0)

func _apply_ground_pose(frame: SkierAnimationFrame) -> void:
	var speed_flex := profile.speed_knee_flex * _crouch_amount
	var jump_flex := _jump_anticipation * profile.jump_anticipation_knee_flex
	var crossover_release := _crossover_release()
	var flex := maxf(0.2, profile.neutral_knee_flex + speed_flex + jump_flex - crossover_release * profile.crossover_extension)
	var deep_carve := smoothstep(profile.deep_carve_threshold, 1.0, absf(_carve_target))
	var pelvis_roll := -_pelvis_carve * profile.carve_hip_roll + _terrain_pelvis_roll_amount
	var skid_side := signf(frame.skid) if absf(frame.skid) > 0.05 else signf(frame.edge)
	var load := absf(_pelvis_carve)
	var asymmetry := profile.stance_asymmetry
	_current_blend = _pelvis_carve
	_current_pose_name = "Ground Neutral"

	_add_rotation(balance_root, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll * 0.28))
	_add_rotation(pelvis, Vector3(
		-profile.neutral_hip_flex * 0.45 - _crouch_amount * profile.speed_hip_flex * 0.45 - frame.tuck * 0.2 - _jump_anticipation * profile.jump_anticipation_hip_flex,
		-_pelvis_carve * profile.chest_counter_yaw * 0.2,
		pelvis_roll
	))
	_add_rotation(spine, Vector3(
		-profile.neutral_torso_pitch - _crouch_amount * profile.speed_torso_pitch - frame.tuck * profile.tuck_spine_pitch - _jump_anticipation * profile.jump_anticipation_torso_pitch,
		-_torso_carve * profile.chest_counter_yaw,
		_torso_carve * profile.carve_spine_roll - _terrain_pelvis_roll_amount * 0.52
	))
	_add_rotation(chest, Vector3(
		-frame.tuck * 0.18,
		-_torso_carve * profile.chest_counter_yaw - frame.heading_velocity_delta * profile.chest_travel_alignment,
		_torso_carve * profile.carve_chest_roll - _terrain_pelvis_roll_amount * 0.22
	))
	_add_rotation(head, Vector3(
		profile.neutral_torso_pitch * 0.62 + _crouch_amount * profile.speed_torso_pitch * 0.72 + frame.tuck * 0.24,
		_torso_carve * profile.chest_counter_yaw * 0.45 + frame.heading_velocity_delta * profile.chest_travel_alignment * 0.72,
		_torso_carve * profile.carve_head_level - _terrain_pelvis_roll_amount * 0.16
	))
	_apply_leg_flex(flex, _leg_carve, deep_carve, _left_terrain_flex, _right_terrain_flex)
	_add_rotation(left_boot, Vector3(-_jump_anticipation * profile.jump_anticipation_ankle_flex, 0.0, 0.0))
	_add_rotation(right_boot, Vector3(-_jump_anticipation * profile.jump_anticipation_ankle_flex, 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll))
	_add_rotation(right_ski, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll))
	_apply_terrain_foot_orientation()
	_position_targets[pelvis] = Vector3(
		_pelvis_carve * profile.carve_pelvis_shift,
		0.96 - flex * profile.pelvis_flex_depth - _jump_anticipation * profile.jump_anticipation_pelvis_drop - load * profile.carve_pelvis_drop + crossover_release * profile.crossover_extension * 0.36 + _terrain_pelvis_offset,
		0.0
	)
	_pelvis_target_world = balance_root.to_global(_position_targets[pelvis] as Vector3)

	var left_inside := maxf(0.0, -_arm_carve)
	var right_inside := maxf(0.0, _arm_carve)
	var left_outside := right_inside
	var right_outside := left_inside
	var base_arm_pitch := profile.neutral_hand_forward_pitch - _crouch_amount * profile.speed_arm_tuck - _jump_anticipation * profile.jump_anticipation_arm_back
	_add_rotation(left_shoulder, Vector3(base_arm_pitch + left_outside * 0.14 - left_inside * 0.04 + asymmetry, -_arm_carve * 0.06, -0.2 - _arm_carve * 0.12))
	_add_rotation(right_shoulder, Vector3(base_arm_pitch + right_outside * 0.14 - right_inside * 0.04 - asymmetry, -_arm_carve * 0.06, 0.2 - _arm_carve * 0.12))
	_add_rotation(left_elbow, Vector3(profile.neutral_elbow_bend + asymmetry, 0.0, -_arm_carve * 0.04))
	_add_rotation(right_elbow, Vector3(profile.neutral_elbow_bend - asymmetry, 0.0, -_arm_carve * 0.04))
	_position_targets[left_shoulder] += Vector3(0.0, -left_inside * 0.035 + asymmetry, 0.0)
	_position_targets[right_shoulder] += Vector3(0.0, -right_inside * 0.035 - asymmetry, 0.0)

	if absf(_carve_target) > 0.08:
		_current_pose_name = "Deep Carve %s" % ("Left" if _carve_target < 0.0 else "Right") if deep_carve > 0.5 else "Carve %s" % ("Left" if _carve_target < 0.0 else "Right")
	if crossover_release > 0.08:
		_current_pose_name = "Crossover to %s" % ("Left" if _carve_target < 0.0 else "Right")

	if frame.tuck > 0.05:
		_current_pose_name = "Tuck"
		_add_rotation(left_shoulder, Vector3(-profile.tuck_arm_pitch * frame.tuck, -0.16, -0.26))
		_add_rotation(right_shoulder, Vector3(-profile.tuck_arm_pitch * frame.tuck, 0.16, 0.26))
		_add_rotation(left_elbow, Vector3(-0.9 * frame.tuck, 0.0, 0.0))
		_add_rotation(right_elbow, Vector3(-0.9 * frame.tuck, 0.0, 0.0))

	if frame.braking:
		_current_pose_name = "Hockey Stop %s" % ("Left" if skid_side < 0.0 else "Right")
		var brake_yaw := skid_side * profile.brake_ski_yaw
		_add_rotation(pelvis, Vector3(0.05, -brake_yaw * 0.35, -skid_side * 0.16))
		_add_rotation(chest, Vector3(-0.08, brake_yaw * 0.48, skid_side * 0.12))
		_add_rotation(left_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(right_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(left_shoulder, Vector3(-0.42, -brake_yaw * 0.28, -0.25))
		_add_rotation(right_shoulder, Vector3(-0.42, -brake_yaw * 0.28, 0.25))

	if _jump_anticipation > 0.08:
		_current_pose_name = "Jump Anticipation"

func _apply_air_pose(frame: SkierAnimationFrame) -> void:
	var yaw_speed := absf(frame.angular_velocity.y)
	var flip_speed := absf(frame.angular_velocity.x)
	var roll_speed := absf(frame.angular_velocity.z)
	var rotation_compact := maxf(
		clampf(yaw_speed / profile.spin_compact_threshold, 0.0, 1.0),
		clampf(flip_speed / profile.flip_compact_threshold, 0.0, 1.0)
	)
	var phase_compact := clampf(_air_early_weight * 0.55 + _air_apex_weight + _air_descent_weight * 0.3, 0.0, 1.0)
	_air_flex = clampf(
		profile.air_takeoff_leg_flex
		+ _air_size * phase_compact * profile.air_compact_leg_flex
		+ rotation_compact * profile.air_spin_leg_flex,
		profile.min_leg_flex,
		profile.max_leg_flex
	)
	_current_blend = maxf(_air_size * phase_compact, rotation_compact)
	_current_pose_name = "Air %s" % _air_phase_name
	var leg_settle := (_air_early_weight - _air_descent_weight) * profile.air_leg_asymmetry
	_apply_leg_flex(_air_flex, 0.0, 0.0, _left_terrain_flex, _right_terrain_flex)
	_add_rotation(left_hip, Vector3(-leg_settle * 0.35, 0.0, -leg_settle))
	_add_rotation(right_hip, Vector3(leg_settle * 0.35, 0.0, -leg_settle))
	_add_rotation(left_knee, Vector3(leg_settle, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(-leg_settle, 0.0, 0.0))
	_apply_terrain_foot_orientation()
	var ski_pitch := profile.air_ski_pitch * (_air_early_weight * 0.3 + _air_apex_weight * 0.5 - _air_descent_weight * 0.35)
	_add_rotation(left_ski, Vector3(ski_pitch + leg_settle * 0.22, 0.0, 0.0))
	_add_rotation(right_ski, Vector3(ski_pitch - leg_settle * 0.22, 0.0, 0.0))
	var deliberate_pop := 1.0 if frame.takeoff_type == SkierAnimationFrame.TakeoffType.CHARGED_POP else 0.35
	_position_targets[pelvis] = Vector3(
		0.0,
		0.96
		+ _air_takeoff_weight * profile.air_takeoff_pelvis_rise * deliberate_pop
		- _air_size * phase_compact * profile.air_pelvis_compact_drop
		+ _terrain_pelvis_offset,
		0.0
	)
	_pelvis_target_world = balance_root.to_global(_position_targets[pelvis] as Vector3)
	_add_rotation(spine, Vector3(
		-_air_takeoff_weight * 0.035 - _air_size * phase_compact * 0.14 + _air_descent_weight * 0.045 - flip_speed * 0.02,
		-frame.angular_velocity.y * 0.025,
		-frame.angular_velocity.z * 0.05
	))
	_add_rotation(pelvis, Vector3(-_air_size * phase_compact * 0.08, frame.angular_velocity.y * 0.012, 0.0))
	var arm_in := _air_size * phase_compact * 0.2 + rotation_compact * 0.28
	var arm_open := profile.air_arm_balance_open * (0.32 + _air_descent_weight * 0.68) * (1.0 - rotation_compact * 0.45)
	var takeoff_swing := _air_takeoff_weight * deliberate_pop * 0.2
	var asymmetry := profile.stance_asymmetry + leg_settle * 0.25
	_add_rotation(left_shoulder, Vector3(takeoff_swing - 0.18 - arm_in + asymmetry, -frame.angular_velocity.y * 0.018, -arm_open - asymmetry))
	_add_rotation(right_shoulder, Vector3(takeoff_swing - 0.18 - arm_in - asymmetry, -frame.angular_velocity.y * 0.018, arm_open - asymmetry))
	_add_rotation(left_elbow, Vector3(0.54 - arm_in * 0.32 + asymmetry, 0.0, 0.0))
	_add_rotation(right_elbow, Vector3(0.54 - arm_in * 0.32 - asymmetry, 0.0, 0.0))

	if yaw_speed > 0.5:
		_current_pose_name += " / Spin %s" % ("Left" if frame.angular_velocity.y > 0.0 else "Right")
		_add_rotation(head, Vector3(0.0, signf(frame.angular_velocity.y) * 0.28 * rotation_compact, 0.0))
	if flip_speed > 0.6:
		_current_pose_name += " / %s" % ("Frontflip" if frame.angular_velocity.x > 0.0 else "Backflip")
		_add_rotation(pelvis, Vector3(-signf(frame.angular_velocity.x) * 0.2, 0.0, 0.0))
		_add_rotation(spine, Vector3(-signf(frame.angular_velocity.x) * 0.32, 0.0, 0.0))
	if roll_speed > 0.55:
		_current_pose_name += " / Cork %s" % ("Left" if frame.angular_velocity.z > 0.0 else "Right")
		_add_rotation(chest, Vector3(0.0, signf(frame.angular_velocity.z) * 0.24, -signf(frame.angular_velocity.z) * 0.38))
		_add_rotation(pelvis, Vector3(0.0, -signf(frame.angular_velocity.z) * 0.16, signf(frame.angular_velocity.z) * 0.22))

	_apply_grab_pose(frame.grab_pose, frame)

func _apply_trick_layer(frame: SkierAnimationFrame) -> void:
	var strength := clampf(frame.gesture_strength, 0.0, 1.0)
	match frame.trick_phase:
		TrickCommand.PresentationPhase.SETUP:
			_current_pose_name = "Flick Setup"
			var direction := frame.gesture_direction.x
			# Charge already drives the shared anticipation layer; Flick setup adds
			# directional pre-wind without double-compressing the legs.
			_position_targets[pelvis] += Vector3(direction * 0.04, -profile.flick_setup_depth * strength * 0.12, 0.05 * strength)
			_add_rotation(pelvis, Vector3(-0.04 * strength, direction * 0.08, -direction * 0.18))
			_add_rotation(spine, Vector3(-0.08 * strength, -direction * 0.1, direction * 0.12))
			_add_rotation(left_shoulder, Vector3(-0.12 * strength, 0.0, -0.12))
			_add_rotation(right_shoulder, Vector3(-0.12 * strength, 0.0, 0.12))
		TrickCommand.PresentationPhase.RELEASE:
			_current_pose_name = "Flick Release"
			_position_targets[pelvis] += Vector3.UP * profile.flick_pop_extension * maxf(0.7, strength) * 0.35
			_add_rotation(left_knee, Vector3(-0.08, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-0.08, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.1, 0.0, -0.18))
			_add_rotation(right_shoulder, Vector3(0.1, 0.0, 0.18))
		TrickCommand.PresentationPhase.ROTATE:
			_apply_command_rotation_pose(frame)
		TrickCommand.PresentationPhase.OPEN:
			_current_pose_name = "Open / Landing Ready"
			_add_rotation(left_hip, Vector3(0.18, 0.0, -0.08))
			_add_rotation(right_hip, Vector3(0.18, 0.0, 0.08))
			_add_rotation(left_knee, Vector3(-0.32, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-0.32, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.12, 0.0, -0.52))
			_add_rotation(right_shoulder, Vector3(0.12, 0.0, 0.52))
		TrickCommand.PresentationPhase.LANDING:
			_current_pose_name = "Landing Ready"

func _apply_command_rotation_pose(frame: SkierAnimationFrame) -> void:
	var progress_wave := sin(clampf(frame.rotation_progress, 0.0, 1.0) * PI)
	match frame.trick_kind:
		TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT:
			var commanded_side := -1.0 if frame.trick_kind == TrickCommand.Kind.SPIN_LEFT else 1.0
			var side := signf(frame.angular_velocity.y) if absf(frame.angular_velocity.y) > 0.1 else commanded_side
			var support := clampf(absf(frame.angular_velocity.y) / maxf(profile.spin_compact_threshold, 0.01), 0.0, 1.0)
			_current_pose_name = "Spin %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(pelvis, Vector3(-0.08 * support, side * 0.08 * support, side * 0.05 * support))
			_add_rotation(chest, Vector3(-0.04 * support, side * 0.16 * support, -side * 0.08 * support))
			_add_rotation(head, Vector3(0.0, side * profile.spin_head_spot * (0.55 + progress_wave * 0.25) * support, 0.0))
			_add_rotation(left_shoulder, Vector3(-0.28 * support, -side * 0.1 * support, -0.18 * support))
			_add_rotation(right_shoulder, Vector3(-0.28 * support, -side * 0.1 * support, 0.18 * support))
		TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP:
			var side := 1.0 if frame.trick_kind == TrickCommand.Kind.FRONTFLIP else -1.0
			_current_pose_name = "%s Tuck" % ("Frontflip" if side > 0.0 else "Backflip")
			_add_rotation(pelvis, Vector3(-side * 0.3, 0.0, 0.0))
			_add_rotation(spine, Vector3(-side * (0.28 + progress_wave * 0.22), 0.0, 0.0))
			_add_rotation(left_hip, Vector3(-0.32 * progress_wave, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(-0.32 * progress_wave, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.62 * progress_wave, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.62 * progress_wave, 0.0, 0.0))
		TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT:
			var side := -1.0 if frame.trick_kind == TrickCommand.Kind.CORK_LEFT else 1.0
			_current_pose_name = "Cork %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(balance_root, Vector3(0.0, side * 0.12, side * 0.18))
			_add_rotation(pelvis, Vector3(-0.22, -side * 0.2, side * 0.46))
			_add_rotation(spine, Vector3(-0.3, side * 0.28, -side * 0.36))
			_add_rotation(chest, Vector3(-0.12, side * 0.34, -side * 0.38))
			_add_rotation(head, Vector3(0.12, -side * 0.25, side * 0.16))
			_add_rotation(left_shoulder, Vector3(-0.6, side * 0.2, -0.56))
			_add_rotation(right_shoulder, Vector3(-0.42, side * 0.2, 0.4))

func _apply_grind_pose(frame: SkierAnimationFrame) -> void:
	var balance := frame.rail_balance
	var flex := profile.rail_knee_flex + clampf(frame.rail_speed / 45.0, 0.0, 1.0) * 0.12
	_current_blend = balance
	_current_pose_name = "50-50 Grind"
	_apply_leg_flex(flex, balance * 0.3, absf(balance))
	_position_targets[pelvis] = Vector3(balance * 0.05, 0.96 - flex * 0.22, 0.0)
	_add_rotation(balance_root, Vector3(0.0, balance * profile.rail_counter_rotation, -balance * profile.rail_balance_lean))
	_add_rotation(pelvis, Vector3(-0.08, -balance * 0.32, balance * 0.2))
	_add_rotation(chest, Vector3(0.04, balance * 0.46, -balance * 0.18))
	_add_rotation(left_shoulder, Vector3(-0.25, balance * 0.25, -0.62))
	_add_rotation(right_shoulder, Vector3(-0.25, balance * 0.25, 0.62))
	if absf(balance) > 0.35:
		_current_pose_name = "Boardslide %s" % ("Left" if balance < 0.0 else "Right")
		_add_rotation(left_ski, Vector3(0.0, balance * 0.65, 0.0))
		_add_rotation(right_ski, Vector3(0.0, balance * 0.65, 0.0))

func _apply_bail_pose(frame: SkierAnimationFrame) -> void:
	var phase := _elapsed * profile.bail_flail_speed
	_current_blend = 1.0
	_current_pose_name = "Bail Tumble"
	_add_rotation(pelvis, Vector3(sin(phase) * 0.3, cos(phase * 0.7) * 0.4, sin(phase * 0.5) * 0.45))
	_add_rotation(spine, Vector3(cos(phase * 0.8) * 0.42, sin(phase) * 0.25, cos(phase * 0.6) * 0.36))
	_add_rotation(left_shoulder, Vector3(-1.0 + sin(phase) * 0.5, 0.3, -0.8))
	_add_rotation(right_shoulder, Vector3(-0.7 + cos(phase) * 0.55, -0.3, 0.8))
	_add_rotation(left_hip, Vector3(-0.5 + cos(phase * 0.8) * 0.35, 0.0, -0.35))
	_add_rotation(right_hip, Vector3(-0.25 + sin(phase * 0.7) * 0.4, 0.0, 0.35))
	_add_rotation(left_knee, Vector3(0.9, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(0.55, 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.0, -0.35, -0.2))
	_add_rotation(right_ski, Vector3(0.0, 0.4, 0.24))

func _apply_grab_pose(pose: int, frame: SkierAnimationFrame) -> void:
	if pose == 0:
		_grab_hand = null
		return
	_layer_weight = frame.grab_amount if frame.grab_amount > 0.0 else 1.0
	match pose:
		1:
			_current_pose_name = "Safety Grab Left"
			_add_rotation(left_shoulder, Vector3(-0.35, 0.12, -1.15))
			_add_rotation(left_elbow, Vector3(-1.0, 0.0, -0.2))
			_add_rotation(left_hip, Vector3(-0.28, 0.0, -0.18))
			_add_rotation(left_knee, Vector3(0.8, 0.0, 0.0))
		2:
			_current_pose_name = "Safety Grab Right"
			_add_rotation(right_shoulder, Vector3(-0.35, -0.12, 1.15))
			_add_rotation(right_elbow, Vector3(-1.0, 0.0, 0.2))
			_add_rotation(right_hip, Vector3(-0.28, 0.0, 0.18))
			_add_rotation(right_knee, Vector3(0.8, 0.0, 0.0))
		3:
			_current_pose_name = "Mute Grab Left"
			_add_rotation(left_shoulder, Vector3(-0.55, -0.45, -0.95))
			_add_rotation(left_elbow, Vector3(-1.12, 0.0, -0.25))
			_add_rotation(right_knee, Vector3(0.78, 0.0, 0.0))
		4:
			_current_pose_name = "Mute Grab Right"
			_add_rotation(right_shoulder, Vector3(-0.55, 0.45, 0.95))
			_add_rotation(right_elbow, Vector3(-1.12, 0.0, 0.25))
			_add_rotation(left_knee, Vector3(0.78, 0.0, 0.0))
		5, 6:
			var side := -1.0 if pose == 5 else 1.0
			_current_pose_name = "Japan Grab %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(spine, Vector3(-0.35, side * 0.18, side * 0.24))
			_add_rotation(left_knee if side < 0.0 else right_knee, Vector3(1.05, 0.0, side * 0.12))
			_add_rotation(left_ski if side < 0.0 else right_ski, Vector3(0.22, 0.0, side * 0.2))
			_add_rotation(left_shoulder if side < 0.0 else right_shoulder, Vector3(-0.42, side * 0.32, side * 1.12))
		7:
			_current_pose_name = "Tail Grab"
			_add_rotation(spine, Vector3(-0.38, 0.28, 0.0))
			_add_rotation(right_shoulder, Vector3(-0.55, 0.5, 1.0))
			_add_rotation(right_ski, Vector3(0.22, 0.0, 0.0))
		8:
			_current_pose_name = "Nose Grab"
			_add_rotation(spine, Vector3(-0.5, -0.18, 0.0))
			_add_rotation(left_shoulder, Vector3(-0.72, -0.4, -0.9))
			_add_rotation(left_ski, Vector3(-0.18, 0.0, 0.0))
		9:
			_current_pose_name = "Double Grab"
			_add_rotation(left_shoulder, Vector3(-0.6, 0.2, -1.0))
			_add_rotation(right_shoulder, Vector3(-0.6, -0.2, 1.0))
			_add_rotation(left_elbow, Vector3(-0.95, 0.0, 0.0))
			_add_rotation(right_elbow, Vector3(-0.95, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.8, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.8, 0.0, 0.0))
		10:
			_current_pose_name = "Spread Eagle"
			_add_rotation(left_hip, Vector3(0.3, -0.2, -0.55))
			_add_rotation(right_hip, Vector3(0.3, 0.2, 0.55))
			_add_rotation(left_shoulder, Vector3(0.0, 0.0, -1.35))
			_add_rotation(right_shoulder, Vector3(0.0, 0.0, 1.35))
		11:
			_current_pose_name = "Daffy"
			_add_rotation(left_hip, Vector3(-0.7, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(0.48, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.28, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.08, 0.0, 0.0))
	_apply_grab_reach(pose, frame, _layer_weight)
	_layer_weight = 1.0

func _apply_grab_reach(pose: int, frame: SkierAnimationFrame, amount: float) -> void:
	var reach_amount := clampf(amount, 0.0, 1.0)
	if pose not in [TrickController.GrabPose.SPREAD_EAGLE, TrickController.GrabPose.DAFFY]:
		_position_targets[chest] = Vector3(0.0, 0.42 - profile.grab_chest_drop * reach_amount, 0.1 * reach_amount)
		_add_rotation(spine, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(left_hip, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(right_hip, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(left_knee, Vector3(profile.grab_leg_tuck * reach_amount, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(profile.grab_leg_tuck * reach_amount, 0.0, 0.0))
	match pose:
		TrickController.GrabPose.SAFETY_LEFT, TrickController.GrabPose.JAPAN_LEFT:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
		TrickController.GrabPose.SAFETY_RIGHT, TrickController.GrabPose.JAPAN_RIGHT:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
		TrickController.GrabPose.MUTE_LEFT:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.0)), reach_amount)
		TrickController.GrabPose.MUTE_RIGHT:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.0)), reach_amount)
		TrickController.GrabPose.TAIL:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.78)), reach_amount)
		TrickController.GrabPose.NOSE:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, -0.9)), reach_amount)
		TrickController.GrabPose.DOUBLE:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
	if absf(frame.grab_tweak.x) > 0.05:
		_add_rotation(left_ski, Vector3(0.0, frame.grab_tweak.x * 0.18 * reach_amount, -frame.grab_tweak.x * 0.12 * reach_amount))
		_add_rotation(right_ski, Vector3(0.0, -frame.grab_tweak.x * 0.18 * reach_amount, frame.grab_tweak.x * 0.12 * reach_amount))

func _aim_arm_at(shoulder: Node3D, elbow: Node3D, hand: Node3D, target_world: Vector3, amount: float) -> void:
	var target_local := shoulder.to_local(target_world)
	if target_local.length_squared() < 0.0001:
		return
	var upper := 0.42
	var lower := 0.37
	var raw_distance := target_local.length()
	var distance := clampf(raw_distance, absf(upper - lower) + 0.01, upper + lower - 0.005)
	var direction := target_local.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var pole := Vector3.FORWARD
	var bend_axis := (pole - direction * pole.dot(direction)).normalized()
	if bend_axis.length_squared() < 0.01:
		bend_axis = Vector3.RIGHT
	var elbow_target := direction * along + bend_axis * height * (-1.0 if shoulder == left_shoulder else 1.0)
	var shoulder_rotation := Quaternion(Vector3.DOWN, elbow_target.normalized())
	var lower_direction := (direction * distance - elbow_target).normalized()
	var elbow_rotation := Quaternion(Vector3.DOWN, shoulder_rotation.inverse() * lower_direction)
	var current_target := _rotation_targets[shoulder] as Vector3
	_rotation_targets[shoulder] = current_target.lerp(shoulder_rotation.get_euler(), amount)
	_rotation_targets[elbow] = (_rotation_targets[elbow] as Vector3).lerp(elbow_rotation.get_euler(), amount)
	_grab_hand = hand
	_grab_target_world = target_world

func _apply_leg_flex(flex: float, carve: float, deep_carve: float, left_terrain_flex: float = 0.0, right_terrain_flex: float = 0.0) -> void:
	var left_inside := maxf(0.0, -carve)
	var right_inside := maxf(0.0, carve)
	var left_flex := clampf(
		flex + left_inside * profile.inside_leg_extra_flex * deep_carve - right_inside * profile.outside_leg_extension * deep_carve + left_terrain_flex,
		profile.min_leg_flex,
		profile.max_leg_flex
	)
	var right_flex := clampf(
		flex + right_inside * profile.inside_leg_extra_flex * deep_carve - left_inside * profile.outside_leg_extension * deep_carve + right_terrain_flex,
		profile.min_leg_flex,
		profile.max_leg_flex
	)
	var knee_roll := -carve * profile.carve_knee_roll
	var ankle_flex := profile.neutral_ankle_flex + _crouch_amount * profile.speed_ankle_flex
	_add_rotation(left_hip, Vector3(-0.08 - left_flex * 0.34, 0.0, knee_roll))
	_add_rotation(right_hip, Vector3(-0.08 - right_flex * 0.34, 0.0, knee_roll))
	_add_rotation(left_knee, Vector3(left_flex * 1.05, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(right_flex * 1.05, 0.0, 0.0))
	_add_rotation(left_boot, Vector3(-ankle_flex - left_flex * 0.08, 0.0, -carve * profile.carve_ski_roll * 0.42))
	_add_rotation(right_boot, Vector3(-ankle_flex - right_flex * 0.08, 0.0, -carve * profile.carve_ski_roll * 0.42))

func _apply_terrain_foot_orientation() -> void:
	var ankle_share := clampf(profile.ankle_terrain_response, 0.0, 1.0)
	var ski_share := 1.0 - ankle_share
	_add_rotation(left_boot, Vector3(_left_terrain_angles.x * ankle_share, 0.0, _left_terrain_angles.y * ankle_share))
	_add_rotation(right_boot, Vector3(_right_terrain_angles.x * ankle_share, 0.0, _right_terrain_angles.y * ankle_share))
	_add_rotation(left_ski, Vector3(_left_terrain_angles.x * ski_share, 0.0, _left_terrain_angles.y * ski_share))
	_add_rotation(right_ski, Vector3(_right_terrain_angles.x * ski_share, 0.0, _right_terrain_angles.y * ski_share))

func _apply_reaction(frame: SkierAnimationFrame, delta: float) -> void:
	if _reaction_event < 0 or _reaction_duration <= 0.0:
		return
	_reaction_time += delta
	var normalized := clampf(_reaction_time / _reaction_duration, 0.0, 1.0)
	var pulse := sin(normalized * PI)
	match _reaction_event:
		AnimationEvent.POP:
			_current_pose_name = "Pop Extension"
			_position_targets[pelvis] += Vector3.UP * pulse * 0.12 * _reaction_strength
			_add_rotation(left_hip, Vector3(pulse * 0.22, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(pulse * 0.22, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(-pulse * 0.42, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-pulse * 0.42, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(pulse * 0.25, 0.0, -pulse * 0.12))
			_add_rotation(right_shoulder, Vector3(pulse * 0.25, 0.0, pulse * 0.12))
		AnimationEvent.LAND_CLEAN, AnimationEvent.LAND_SKETCHY, AnimationEvent.LAND_HARD:
			var depth := 0.16
			if _reaction_event == AnimationEvent.LAND_SKETCHY: depth = 0.28
			if _reaction_event == AnimationEvent.LAND_HARD: depth = 0.4
			_position_targets[pelvis] += Vector3(0.0, -pulse * depth * _reaction_strength, 0.0)
			_add_rotation(left_hip, Vector3(-pulse * depth, 0.0, -_reaction_side * pulse * 0.08))
			_add_rotation(right_hip, Vector3(-pulse * depth, 0.0, -_reaction_side * pulse * 0.08))
			_add_rotation(left_knee, Vector3(pulse * depth * 1.7, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(pulse * depth * 1.7, 0.0, 0.0))
			_add_rotation(chest, Vector3(pulse * depth * 0.35, 0.0, _reaction_side * pulse * depth))
		AnimationEvent.GRIND_ENTER, AnimationEvent.GRIND_EXIT:
			_position_targets[pelvis] += Vector3(0.0, -pulse * 0.08, 0.0)
	if normalized >= 1.0:
		_reaction_event = -1

func _apply_secondary_motion(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state == STATE_GROUND:
		var speed_trail := 0.14 + clampf(frame.speed_ratio, 0.0, 1.0) * profile.pole_speed_trail
		var asymmetry := profile.stance_asymmetry
		var arm_chain_pitch := profile.neutral_hand_forward_pitch - _crouch_amount * profile.speed_arm_tuck + profile.neutral_elbow_bend
		var left_arm_roll := -0.2 - _arm_carve * 0.16
		var right_arm_roll := 0.2 - _arm_carve * 0.16
		_add_rotation(left_pole, Vector3(-arm_chain_pitch - speed_trail + asymmetry, -_pole_carve * profile.pole_turn_lag, -left_arm_roll - asymmetry))
		_add_rotation(right_pole, Vector3(-arm_chain_pitch - speed_trail - asymmetry, -_pole_carve * profile.pole_turn_lag, -right_arm_roll + asymmetry))
	elif frame.locomotion_state == STATE_AIR:
		var rotation_follow := clampf(frame.angular_velocity.length() / maxf(profile.spin_compact_threshold, 0.01), 0.0, 1.0)
		var takeoff_lag := _air_takeoff_weight * 0.16
		var phase_trail := profile.air_pole_trail + _air_early_weight * 0.12 - _air_descent_weight * 0.08
		var asymmetry := profile.stance_asymmetry
		_add_rotation(left_pole, Vector3(-phase_trail - takeoff_lag + asymmetry, -frame.angular_velocity.y * 0.035, 0.18 + rotation_follow * 0.08))
		_add_rotation(right_pole, Vector3(-phase_trail - takeoff_lag - asymmetry, -frame.angular_velocity.y * 0.035, -0.18 - rotation_follow * 0.08))
	if frame.switch_stance:
		_add_rotation(chest, Vector3(0.0, 0.08, 0.0))
		_add_rotation(head, Vector3(0.0, -0.12, 0.0))

func _blend_targets(delta: float) -> void:
	var pop_blend := 1.0 if _reaction_event == AnimationEvent.POP or (_current_state == STATE_AIR and _air_takeoff_weight > 0.18) else 0.0
	var rotation_response := lerpf(profile.pose_response, profile.pop_pose_response, pop_blend)
	var rotation_weight := 1.0 - exp(-rotation_response * delta)
	var position_weight := 1.0 - exp(-profile.fast_pose_response * delta)
	for key: Variant in _rotation_targets.keys():
		var joint := key as Node3D
		var target := _rotation_targets[key] as Vector3
		joint.rotation = Vector3(
			lerp_angle(joint.rotation.x, target.x, rotation_weight),
			lerp_angle(joint.rotation.y, target.y, rotation_weight),
			lerp_angle(joint.rotation.z, target.z, rotation_weight)
		)
	for key: Variant in _position_targets.keys():
		var joint := key as Node3D
		joint.position = joint.position.lerp(_position_targets[key] as Vector3, position_weight)

func _add_rotation(joint: Node3D, value: Vector3) -> void:
	_rotation_targets[joint] = (_rotation_targets.get(joint, Vector3.ZERO) as Vector3) + value * _layer_weight

func _reset_pose_immediately() -> void:
	_crouch_amount = 0.0
	_carve_target = 0.0
	_ski_carve = 0.0
	_leg_carve = 0.0
	_pelvis_carve = 0.0
	_torso_carve = 0.0
	_arm_carve = 0.0
	_pole_carve = 0.0
	_last_loaded_direction = 0.0
	_crossover_time = 0.0
	_terrain_influence = 0.0
	_terrain_correction_influence = 0.0
	_left_contact_confidence = 0.0
	_right_contact_confidence = 0.0
	_left_terrain_weight = 0.0
	_right_terrain_weight = 0.0
	_left_terrain_gap = 0.0
	_right_terrain_gap = 0.0
	_left_terrain_flex = 0.0
	_right_terrain_flex = 0.0
	_terrain_pelvis_offset = 0.0
	_terrain_pelvis_roll_amount = 0.0
	_left_terrain_normal = Vector3.UP
	_right_terrain_normal = Vector3.UP
	_left_terrain_angles = Vector2.ZERO
	_right_terrain_angles = Vector2.ZERO
	_left_leg_compression = 0.0
	_right_leg_compression = 0.0
	_average_leg_compression = 0.0
	_previous_average_compression = 0.0
	_compression_velocity = 0.0
	_jump_anticipation = 0.0
	_air_size = 0.0
	_air_takeoff_weight = 0.0
	_air_early_weight = 0.0
	_air_apex_weight = 0.0
	_air_descent_weight = 0.0
	_air_flex = 0.0
	_air_phase_name = "Ground"
	_reset_targets()
	for key: Variant in _rotation_targets.keys():
		(key as Node3D).rotation = _rotation_targets[key] as Vector3
	for key: Variant in _position_targets.keys():
		(key as Node3D).position = _position_targets[key] as Vector3

func _build_articulated_rig() -> void:
	var jacket := _material(Color("#f24f68"), 0.78, 0.05)
	var pants := _material(Color("#243543"), 0.82, 0.0)
	var skin := _material(Color("#e8b58e"), 0.9, 0.0)
	var dark := _material(Color("#132532"), 0.5, 0.25)
	var accent := _material(Color("#ffc857"), 0.65, 0.05)
	var lens := _material(Color("#5ac8fa"), 0.2, 0.55)

	balance_root = _joint("BalanceRoot", self, Vector3.ZERO)
	pelvis = _joint("Pelvis", balance_root, Vector3(0.0, 0.96, 0.0))
	_add_box(pelvis, "PelvisMesh", Vector3(0.52, 0.22, 0.3), Vector3(0.0, 0.05, 0.0), pants)
	spine = _joint("Spine", pelvis, Vector3(0.0, 0.14, 0.0))
	_add_capsule(spine, "TorsoMesh", 0.31, 0.72, Vector3(0.0, 0.34, 0.0), jacket)
	chest = _joint("Chest", spine, Vector3(0.0, 0.42, 0.0))
	_add_box(chest, "ShoulderJacket", Vector3(0.74, 0.2, 0.34), Vector3(0.0, 0.14, 0.0), jacket)
	head = _joint("Head", chest, Vector3(0.0, 0.38, 0.0))
	_add_sphere(head, "HeadMesh", 0.2, Vector3(0.0, 0.11, 0.0), skin)
	_add_sphere(head, "Helmet", 0.225, Vector3(0.0, 0.19, 0.02), dark, Vector3(1.0, 0.72, 1.0))
	_add_box(head, "Goggles", Vector3(0.29, 0.105, 0.08), Vector3(0.0, 0.13, -0.19), lens)

	left_hip = _joint("LeftHip", pelvis, Vector3(-0.24, -0.04, 0.0))
	right_hip = _joint("RightHip", pelvis, Vector3(0.24, -0.04, 0.0))
	_add_capsule(left_hip, "LeftThigh", 0.105, 0.56, Vector3(0.0, -0.26, 0.0), pants)
	_add_capsule(right_hip, "RightThigh", 0.105, 0.56, Vector3(0.0, -0.26, 0.0), pants)
	left_knee = _joint("LeftKnee", left_hip, Vector3(0.0, -0.52, 0.0))
	right_knee = _joint("RightKnee", right_hip, Vector3(0.0, -0.52, 0.0))
	_add_capsule(left_knee, "LeftShin", 0.09, 0.52, Vector3(0.0, -0.24, 0.0), pants)
	_add_capsule(right_knee, "RightShin", 0.09, 0.52, Vector3(0.0, -0.24, 0.0), pants)
	left_boot = _joint("LeftBoot", left_knee, Vector3(0.0, -0.49, -0.03))
	right_boot = _joint("RightBoot", right_knee, Vector3(0.0, -0.49, -0.03))
	_add_box(left_boot, "LeftBootMesh", Vector3(0.2, 0.17, 0.4), Vector3(0.0, -0.02, -0.09), dark)
	_add_box(right_boot, "RightBootMesh", Vector3(0.2, 0.17, 0.4), Vector3(0.0, -0.02, -0.09), dark)
	left_ski = _joint("LeftSki", left_boot, Vector3(0.0, -0.12, -0.08))
	right_ski = _joint("RightSki", right_boot, Vector3(0.0, -0.12, -0.08))
	_add_box(left_ski, "LeftSkiMesh", Vector3(0.14, 0.055, 2.15), Vector3(0.0, 0.0, -0.12), accent)
	_add_box(right_ski, "RightSkiMesh", Vector3(0.14, 0.055, 2.15), Vector3(0.0, 0.0, -0.12), accent)

	left_shoulder = _joint("LeftShoulder", chest, Vector3(-0.4, 0.24, 0.0))
	right_shoulder = _joint("RightShoulder", chest, Vector3(0.4, 0.24, 0.0))
	_add_capsule(left_shoulder, "LeftUpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
	_add_capsule(right_shoulder, "RightUpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
	left_elbow = _joint("LeftElbow", left_shoulder, Vector3(0.0, -0.42, 0.0))
	right_elbow = _joint("RightElbow", right_shoulder, Vector3(0.0, -0.42, 0.0))
	_add_capsule(left_elbow, "LeftForearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
	_add_capsule(right_elbow, "RightForearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
	left_hand = _joint("LeftHand", left_elbow, Vector3(0.0, -0.37, 0.0))
	right_hand = _joint("RightHand", right_elbow, Vector3(0.0, -0.37, 0.0))
	_add_sphere(left_hand, "LeftGlove", 0.09, Vector3.ZERO, dark)
	_add_sphere(right_hand, "RightGlove", 0.09, Vector3.ZERO, dark)
	left_pole = _joint("LeftPole", left_hand, Vector3.ZERO)
	right_pole = _joint("RightPole", right_hand, Vector3.ZERO)
	_add_cylinder(left_pole, "LeftPoleMesh", 0.022, 1.15, Vector3(0.0, -0.52, 0.08), dark)
	_add_cylinder(right_pole, "RightPoleMesh", 0.022, 1.15, Vector3(0.0, -0.52, 0.08), dark)
	_reset_pose_immediately()

func _joint(joint_name: String, parent: Node3D, position: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = position
	parent.add_child(joint)
	return joint

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _add_box(parent: Node3D, mesh_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)

func _add_capsule(parent: Node3D, mesh_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)

func _add_sphere(parent: Node3D, mesh_name: String, radius: float, position: Vector3, material: Material, scale: Vector3 = Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale
	instance.material_override = material
	parent.add_child(instance)

func _add_cylinder(parent: Node3D, mesh_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
