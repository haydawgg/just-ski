class_name SkierAnimationController
extends Node3D

const GrabDefinition = preload("res://player/animation/grab_animation_definition.gd")

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
@export var grab_library: Resource = preload("res://resources/animation/default_grab_animation_library.tres")

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
var left_grab_binding_outside: Node3D
var left_grab_binding_inside: Node3D
var left_grab_nose: Node3D
var left_grab_tail: Node3D
var right_grab_binding_outside: Node3D
var right_grab_binding_inside: Node3D
var right_grab_nose: Node3D
var right_grab_tail: Node3D

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
var _grab_definitions_by_pose: Dictionary = {}
var _grab_definition: Resource
var _grab_pose_id := TrickController.GrabPose.NONE
var _grab_phase_name := "IDLE"
var _grab_pose_weight := 0.0
var _grab_contact_weight := 0.0
var _grab_compactness := 0.0
var _grab_input_strength := 0.0
var _grab_hold_time := 0.0
var _grab_release_time := 0.0
var _grab_contact_latched := false
var _grab_left_target_world := Vector3.ZERO
var _grab_right_target_world := Vector3.ZERO
var _grab_left_reach_error := 0.0
var _grab_right_reach_error := 0.0
var _grab_left_target_active := false
var _grab_right_target_active := false
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
var _smoothed_angular_velocity := Vector3.ZERO
var _trick_rotation_accumulated := Vector3.ZERO
var _trick_rotation_residual := Vector3.ZERO
var _trick_pose_weight := 0.0
var _prewind_weight := 0.0
var _prewind_direction := 0.0
var _trick_release_weight := 0.0
var _spin_compactness := 0.0
var _spotting_weight := 0.0
var _trick_active := false
var _trick_intent := false
var _trick_kind := TrickCommand.Kind.NONE
var _landing_anticipation := 0.0
var _landing_compression := 0.0
var _landing_compression_target := 0.0
var _landing_severity := 0.0
var _landing_balance_error := 0.0
var _landing_ski_alignment_error := 0.0
var _landing_body_roll_error := 0.0
var _landing_body_pitch_error := 0.0
var _landing_rotation_error := 0.0
var _landing_lateral_bias := 0.0
var _landing_recovery_amount := 0.0
var _landing_wobble_phase := 0.0
var _landing_wobble_amount := 0.0
var _landing_phase_name := "Idle"
var _landing_active := false
var _landing_compressing := false
var _landing_outcome := 0
var _landing_left_asymmetry := 0.0
var _landing_right_asymmetry := 0.0
var _landing_arm_open := 0.0
var _landing_pole_lag := 0.0
var _landing_head_nod := 0.0
var _landing_ski_yaw := 0.0
var _landing_ski_pitch := 0.0
var _landing_torso_prepare := 0.0
var _rail_influence := 0.0
var _rail_approach_anticipation := 0.0
var _rail_entry_active := false
var _rail_entry_compressing := false
var _rail_entry_severity := 0.0
var _rail_entry_compression := 0.0
var _rail_entry_compression_target := 0.0
var _rail_entry_lateral_bias := 0.0
var _rail_entry_left_asymmetry := 0.0
var _rail_entry_right_asymmetry := 0.0
var _rail_slide_angle := 0.0
var _rail_exit_anticipation := 0.0
var _rail_pole_lag := 0.0
var _rail_balance_last := 0.0
var _rail_phase_name := "Idle"

func _ready() -> void:
	_build_articulated_rig()
	_cache_grab_definitions()

func apply_frame(frame: SkierAnimationFrame, delta: float) -> void:
	_elapsed += delta
	_current_state = frame.locomotion_state
	_update_skiing_dynamics(frame, delta)
	_update_terrain_suspension(frame, delta)
	_update_jump_animation(frame, delta)
	_update_landing_animation(frame, delta)
	_update_rail_animation(frame, delta)
	_update_trick_animation(frame, delta)
	_update_grab_animation(frame, delta)
	_reset_targets()
	match frame.locomotion_state:
		STATE_GROUND: _apply_ground_pose(frame)
		STATE_AIR: _apply_air_pose(frame)
		STATE_GRIND: _apply_grind_pose(frame)
		STATE_BAIL: _apply_bail_pose(frame)
	_apply_trick_layer(frame)
	_apply_grab_layer(frame)
	_apply_landing_layers(frame)
	_apply_rail_approach_layer(frame)
	_apply_rail_release_layer(frame)
	_apply_reaction(frame, delta)
	_apply_secondary_motion(frame)
	_enforce_joint_limits()
	_blend_targets(delta)

func trigger(event: int, strength: float = 1.0, side: float = 0.0) -> void:
	_reaction_event = event
	_reaction_time = 0.0
	_reaction_strength = clampf(strength, 0.0, 1.5)
	_reaction_side = clampf(side, -1.0, 1.0)
	match event:
		AnimationEvent.POP: _reaction_duration = profile.pop_duration
		AnimationEvent.LAND_CLEAN, AnimationEvent.LAND_SKETCHY, AnimationEvent.LAND_HARD:
			_begin_landing_impact(event, _reaction_strength, _reaction_side)
			_reaction_duration = 0.0
			_reaction_event = -1
		AnimationEvent.GRIND_ENTER:
			_begin_rail_entry(_reaction_strength, _reaction_side)
			_reaction_duration = 0.0
			_reaction_event = -1
		AnimationEvent.GRIND_EXIT: _reaction_duration = 0.28
		AnimationEvent.BAIL:
			_reaction_duration = 1.2
			_clear_landing_state()
		AnimationEvent.RESPAWN:
			_reaction_duration = 0.0
			_reset_pose_immediately()

func is_landing_idle() -> bool:
	return not _landing_active and _landing_compression < 0.02 and _landing_anticipation < 0.02

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
		"left_shoulder_rotation": left_shoulder.rotation,
		"right_shoulder_rotation": right_shoulder.rotation,
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
		"trick_active": _trick_active,
		"trick_intent": _trick_intent,
		"spin_direction": signf(_smoothed_angular_velocity.y) if absf(_smoothed_angular_velocity.y) > 0.05 else _prewind_direction,
		"rotation_accumulated": _trick_rotation_accumulated,
		"root_yaw_rate": _smoothed_angular_velocity.y,
		"root_pitch_rate": _smoothed_angular_velocity.x,
		"root_roll_rate": _smoothed_angular_velocity.z,
		"spin_compactness": _spin_compactness,
		"prewind_weight": _prewind_weight,
		"trick_release_weight": _trick_release_weight,
		"trick_pose_weight": _trick_pose_weight,
		"spotting_weight": _spotting_weight,
		"landing_blend": _landing_anticipation,
		"rotation_residual": _trick_rotation_residual,
		"landing_anticipation": _landing_anticipation,
		"landing_compression": _landing_compression,
		"landing_severity": _landing_severity,
		"landing_balance_error": _landing_balance_error,
		"landing_ski_alignment_error": _landing_ski_alignment_error,
		"landing_body_roll_error": _landing_body_roll_error,
		"landing_body_pitch_error": _landing_body_pitch_error,
		"landing_rotation_error": _landing_rotation_error,
		"landing_recovery": _landing_recovery_amount,
		"landing_phase": _landing_phase_name,
		"landing_wobble": _landing_wobble_amount,
		"grab_type": _grab_definition.display_name if _grab_definition != null else "",
		"grab_pose": _grab_pose_id,
		"grab_hand": _grab_hand_name(),
		"grab_target_ski": _grab_target_ski_name(),
		"grab_phase": _grab_phase_name,
		"grab_pose_weight": _grab_pose_weight,
		"grab_contact_weight": _grab_contact_weight,
		"grab_compactness": _grab_compactness,
		"grab_input_strength": _grab_input_strength,
		"grab_hold_time": _grab_hold_time,
		"grab_release_time": _grab_release_time,
		"grab_target_count": int(_grab_left_target_active) + int(_grab_right_target_active),
		"grab_target_left": _grab_left_target_world,
		"grab_target_right": _grab_right_target_world,
		"grab_hand_left": left_hand.global_position,
		"grab_hand_right": right_hand.global_position,
		"grab_reach_error": _grab_primary_reach_error(),
		"grab_reach_error_left": _grab_left_reach_error,
		"grab_reach_error_right": _grab_right_reach_error,
		"rail_influence": _rail_influence,
		"rail_approach_anticipation": _rail_approach_anticipation,
		"rail_entry_severity": _rail_entry_severity,
		"rail_entry_compression": _rail_entry_compression,
		"rail_slide_angle": _rail_slide_angle,
		"rail_exit_anticipation": _rail_exit_anticipation,
		"rail_balance": _rail_balance_last,
		"rail_phase": _rail_phase_name,
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

func _update_trick_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var maximum_rate := maxf(profile.trick_max_animation_rate, 0.1)
	var bounded_rate := Vector3(
		clampf(frame.angular_velocity.x, -maximum_rate, maximum_rate),
		clampf(frame.angular_velocity.y, -maximum_rate, maximum_rate),
		clampf(frame.angular_velocity.z, -maximum_rate, maximum_rate)
	)
	var rate_weight := 1.0 - exp(-maxf(profile.trick_rate_response, 0.01) * delta)
	_smoothed_angular_velocity = _smoothed_angular_velocity.lerp(bounded_rate, rate_weight)
	_trick_rotation_accumulated = frame.rotation_accumulated
	_trick_rotation_residual = frame.rotation_residual
	_trick_active = frame.trick_active
	_trick_intent = (
		frame.trick_intent
		or _is_rotation_kind(frame.trick_kind)
		or frame.trick_phase in [TrickCommand.PresentationPhase.SETUP, TrickCommand.PresentationPhase.ROTATE]
	)
	_trick_kind = frame.trick_kind

	var setup_active := (
		frame.locomotion_state == STATE_GROUND
		and frame.trick_phase == TrickCommand.PresentationPhase.SETUP
	)
	if setup_active and absf(frame.gesture_direction.x) > 0.05:
		_prewind_direction = _damp(
			_prewind_direction,
			signf(frame.gesture_direction.x),
			profile.trick_pose_response,
			delta
		)
	var prewind_target := clampf(frame.gesture_strength, 0.0, 1.0) if setup_active and absf(_prewind_direction) > 0.05 else 0.0
	_prewind_weight = _damp(_prewind_weight, prewind_target, profile.trick_pose_response, delta)

	if frame.trick_phase == TrickCommand.PresentationPhase.RELEASE:
		_trick_release_weight = maxf(_trick_release_weight, maxf(frame.gesture_strength, 0.7))
	else:
		var release_response := 4.6 / maxf(profile.trick_release_duration, 0.02)
		_trick_release_weight = _damp(_trick_release_weight, 0.0, release_response, delta)
	if _prewind_weight < 0.02 and _trick_release_weight < 0.02 and frame.locomotion_state != STATE_AIR:
		_prewind_direction = _damp(_prewind_direction, 0.0, profile.trick_pose_response, delta)

	var demand_start := maxf(profile.trick_activation_rate, 0.05)
	var demand_full := maxf(demand_start + 0.1, profile.trick_max_animation_rate * 0.82)
	var yaw_demand := smoothstep(demand_start, demand_full, absf(_smoothed_angular_velocity.y))
	var pitch_demand := smoothstep(demand_start, demand_full, absf(_smoothed_angular_velocity.x))
	var roll_demand := smoothstep(demand_start, demand_full, absf(_smoothed_angular_velocity.z))
	var rate_demand := maxf(yaw_demand, maxf(pitch_demand, roll_demand))
	var meaningful_rotation := (
		_trick_intent
		and (
			_smoothed_angular_velocity.length() >= profile.trick_activation_rate
			or frame.rotation_accumulated.length() >= deg_to_rad(5.0)
			or (_trick_release_weight > 0.05 and _is_rotation_kind(frame.trick_kind))
		)
	) or _smoothed_angular_velocity.length() >= profile.trick_activation_rate * 2.0
	var pose_target := 1.0 if frame.locomotion_state == STATE_AIR and meaningful_rotation else 0.0
	if frame.trick_phase == TrickCommand.PresentationPhase.OPEN:
		pose_target *= 0.42
	elif frame.trick_phase == TrickCommand.PresentationPhase.LANDING:
		pose_target *= lerpf(0.22, 0.5, rate_demand)
	var landing_yield := _landing_anticipation * lerpf(0.82, 0.48, rate_demand)
	pose_target *= 1.0 - landing_yield
	_trick_pose_weight = _damp(_trick_pose_weight, pose_target, profile.trick_pose_response, delta)
	_spin_compactness = _damp(
		_spin_compactness,
		rate_demand * _trick_pose_weight,
		profile.trick_pose_response,
		delta
	)
	var spot_target := 0.0
	if meaningful_rotation and frame.locomotion_state == STATE_AIR:
		spot_target = clampf(
			0.18 + _landing_anticipation * 0.82 + smoothstep(0.0, PI, absf(frame.rotation_accumulated.y)) * 0.18,
			0.0,
			1.0
		)
	_spotting_weight = _damp(_spotting_weight, spot_target, profile.trick_pose_response, delta)

func _cache_grab_definitions() -> void:
	_grab_definitions_by_pose.clear()
	if grab_library == null:
		return
	for definition: Resource in grab_library.definitions:
		if definition != null and definition.pose_id != TrickController.GrabPose.NONE:
			_grab_definitions_by_pose[definition.pose_id] = definition

func _update_grab_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var live_pose := frame.grab_pose
	var live_definition := _grab_definitions_by_pose.get(live_pose) as Resource
	var legacy_strength := 1.0 if live_pose != TrickController.GrabPose.NONE and frame.grab_amount <= 0.0 and frame.grab_input_strength <= 0.0 else 0.0
	var input_strength := clampf(maxf(frame.grab_input_strength, maxf(frame.grab_amount, legacy_strength)), 0.0, 1.0)
	var airborne := frame.locomotion_state == STATE_AIR
	var pose_changed := live_pose != TrickController.GrabPose.NONE and live_pose != _grab_pose_id
	if pose_changed:
		_grab_pose_id = live_pose
		_grab_definition = live_definition
		_grab_contact_latched = false
		_grab_contact_weight = minf(_grab_contact_weight, 0.2)
	elif live_pose != TrickController.GrabPose.NONE and _grab_definition == null:
		_grab_pose_id = live_pose
		_grab_definition = live_definition
	if live_pose == TrickController.GrabPose.NONE:
		input_strength = 0.0

	_grab_input_strength = input_strength
	_grab_hold_time = frame.grab_hold_time
	_grab_release_time = frame.grab_release_time
	var minimum_air_time := profile.grab_min_contact_air_time
	if _grab_definition != null:
		minimum_air_time = maxf(minimum_air_time, _grab_definition.minimum_air_time)
	var airborne_readiness := (
		clampf(frame.air_time / maxf(minimum_air_time, 0.01), 0.0, 1.0)
		if airborne and frame.air_time > 0.0
		else (1.0 if airborne else 0.0)
	)
	var pose_target := input_strength * airborne_readiness
	if input_strength > 0.0 and _landing_anticipation > 0.0:
		var held_landing_floor := profile.grab_late_hold_floor * input_strength
		var landing_target := maxf(held_landing_floor, pose_target * (1.0 - profile.grab_landing_release_strength))
		pose_target = lerpf(pose_target, landing_target, _landing_anticipation)
	var response := profile.grab_pose_response if pose_target > _grab_pose_weight else (
		profile.grab_release_response if frame.grab_release_time > 0.0 else profile.grab_recover_response
	)
	_grab_pose_weight = _damp(_grab_pose_weight, pose_target, response, delta)
	var compact_target := 0.0
	if _grab_definition != null:
		compact_target = _grab_definition.body_compactness * _grab_pose_weight
	_grab_compactness = _damp(_grab_compactness, compact_target, profile.grab_pose_response * 0.72, delta)

	var target_was_active := _grab_left_target_active or _grab_right_target_active
	var reach_error := _grab_primary_reach_error()
	if _grab_definition == null or bool(_grab_definition.style_only) or input_strength <= 0.0 or not airborne:
		_grab_contact_latched = false
	elif target_was_active and _grab_pose_weight > 0.48 and frame.air_time >= minimum_air_time:
		var threshold: float = float(_grab_definition.contact_maintain_distance) if _grab_contact_latched else float(_grab_definition.contact_acquire_distance)
		_grab_contact_latched = reach_error <= threshold
	var contact_target := 1.0 if _grab_contact_latched else 0.0
	_grab_contact_weight = _damp(_grab_contact_weight, contact_target, profile.grab_contact_response, delta)

	if _grab_definition == null or _grab_pose_weight < 0.01:
		_grab_phase_name = "IDLE"
	elif input_strength <= 0.0:
		_grab_phase_name = "RELEASE" if frame.grab_release_time > 0.0 and _grab_pose_weight > 0.16 else "RECOVER"
	elif _grab_definition.style_only:
		_grab_phase_name = "HOLD" if _grab_pose_weight > 0.72 else "SETUP"
	elif _grab_pose_weight < 0.28:
		_grab_phase_name = "SETUP"
	elif _grab_contact_weight > 0.72:
		_grab_phase_name = "HOLD"
	elif _grab_contact_latched or _grab_contact_weight > 0.08:
		_grab_phase_name = "CONTACT"
	else:
		_grab_phase_name = "REACH"

	if live_pose == TrickController.GrabPose.NONE and _grab_pose_weight < 0.01:
		_grab_pose_id = TrickController.GrabPose.NONE
		_grab_definition = null
		_grab_left_target_active = false
		_grab_right_target_active = false

func _update_landing_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var anticipation_target := 0.0
	if frame.locomotion_state == STATE_AIR and frame.predicted_landing_time >= 0.0:
		var window := maxf(profile.landing_anticipation_time, 0.05)
		var start := clampf(profile.landing_anticipation_start, 0.05, window)
		if frame.predicted_landing_time <= start:
			anticipation_target = 1.0 - smoothstep(0.0, start, frame.predicted_landing_time)
			anticipation_target *= lerpf(0.55, 1.0, _air_size)
	_landing_anticipation = _damp(_landing_anticipation, anticipation_target, profile.landing_anticipation_response, delta)

	if frame.predicted_landing_valid and _landing_anticipation > 0.02:
		var local_normal := _terrain_normal_local(frame.predicted_landing_normal)
		var pitch_target := clampf(atan2(local_normal.z, maxf(local_normal.y, 0.001)), -profile.landing_ski_align_pitch, profile.landing_ski_align_pitch)
		var travel := frame.velocity_heading
		var heading := frame.skier_heading
		var yaw_target := 0.0
		if travel.length_squared() > 0.001 and heading.length_squared() > 0.001:
			var planar_travel := Vector3(travel.x, 0.0, travel.z)
			var planar_heading := Vector3(heading.x, 0.0, heading.z)
			if planar_travel.length_squared() > 0.001 and planar_heading.length_squared() > 0.001:
				yaw_target = clampf(planar_heading.normalized().signed_angle_to(planar_travel.normalized(), Vector3.UP), -profile.landing_ski_align_yaw, profile.landing_ski_align_yaw)
		_landing_ski_yaw = _damp(_landing_ski_yaw, yaw_target * _landing_anticipation, profile.landing_anticipation_response, delta)
		_landing_ski_pitch = _damp(_landing_ski_pitch, pitch_target * _landing_anticipation, profile.landing_anticipation_response, delta)
		_landing_torso_prepare = _damp(_landing_torso_prepare, _landing_anticipation, profile.landing_anticipation_response, delta)
	else:
		_landing_ski_yaw = _damp(_landing_ski_yaw, 0.0, profile.landing_anticipation_response, delta)
		_landing_ski_pitch = _damp(_landing_ski_pitch, 0.0, profile.landing_anticipation_response, delta)
		_landing_torso_prepare = _damp(_landing_torso_prepare, 0.0, profile.landing_anticipation_response, delta)

	if frame.landing_event_active and frame.locomotion_state == STATE_GROUND:
		_seed_landing_from_frame(frame)

	if _landing_active or _landing_compression > 0.001:
		if _landing_compressing:
			_landing_compression = _damp(_landing_compression, _landing_compression_target, profile.landing_compression_response, delta)
			if absf(_landing_compression_target - _landing_compression) <= 0.03:
				_landing_compressing = false
				_landing_phase_name = "Recovery"
			else:
				_landing_phase_name = "Compression"
		else:
			var recovery_response := lerpf(profile.landing_recovery_response_soft, profile.landing_recovery_response_hard, _landing_severity)
			_landing_compression = _damp(_landing_compression, 0.0, recovery_response, delta)
			_landing_recovery_amount = 1.0 - clampf(_landing_compression / maxf(_landing_compression_target, 0.001), 0.0, 1.0)
			_landing_phase_name = "Recovery" if _landing_compression > 0.04 else "Idle"
		_landing_wobble_phase += profile.landing_wobble_frequency * delta
		var wobble_target := _landing_balance_error * (0.35 + _landing_compression * 0.65)
		_landing_wobble_amount = _damp(_landing_wobble_amount, wobble_target, profile.landing_wobble_decay, delta)
		_landing_arm_open = _damp(_landing_arm_open, _landing_severity * (0.45 + _landing_balance_error * 0.55), profile.landing_compression_response, delta)
		_landing_pole_lag = _damp(_landing_pole_lag, _landing_severity * profile.landing_pole_lag, profile.secondary_response, delta)
		_landing_head_nod = _damp(_landing_head_nod, _landing_compression * profile.landing_head_nod, profile.landing_compression_response, delta)
		if _landing_compression < 0.02 and _landing_wobble_amount < 0.03 and not _landing_compressing:
			_clear_landing_state()
	else:
		_landing_arm_open = _damp(_landing_arm_open, 0.0, profile.landing_anticipation_response, delta)
		_landing_pole_lag = _damp(_landing_pole_lag, 0.0, profile.secondary_response, delta)
		_landing_head_nod = _damp(_landing_head_nod, 0.0, profile.landing_anticipation_response, delta)
		_landing_phase_name = "Anticipation" if _landing_anticipation > 0.12 else "Idle"

func _begin_landing_impact(event: int, severity: float, side: float) -> void:
	_landing_active = true
	_landing_compressing = true
	_landing_outcome = event
	_landing_severity = clampf(severity, 0.0, 1.0)
	_landing_lateral_bias = clampf(side, -1.0, 1.0)
	_landing_compression_target = clampf(
		lerpf(0.18, 1.0, _landing_severity) * profile.landing_compression_depth / maxf(profile.landing_compression_depth, 0.01),
		0.12,
		1.0
	)
	if event == AnimationEvent.LAND_SKETCHY:
		_landing_compression_target = maxf(_landing_compression_target, 0.42)
	elif event == AnimationEvent.LAND_HARD:
		_landing_compression_target = maxf(_landing_compression_target, 0.72)
	_landing_compression = maxf(_landing_compression, 0.08)
	_landing_recovery_amount = 0.0
	_landing_wobble_phase = 0.0
	_landing_phase_name = "Contact"
	_landing_left_asymmetry = clampf((-_landing_lateral_bias) * profile.landing_asymmetry_gain, -0.35, 0.35)
	_landing_right_asymmetry = clampf(_landing_lateral_bias * profile.landing_asymmetry_gain, -0.35, 0.35)

func _seed_landing_from_frame(frame: SkierAnimationFrame) -> void:
	_landing_severity = maxf(_landing_severity, clampf(frame.landing_impact_severity, 0.0, 1.0))
	_landing_balance_error = clampf(frame.landing_balance_error, 0.0, 1.0)
	_landing_ski_alignment_error = clampf(frame.landing_ski_alignment_error, 0.0, 1.0)
	_landing_body_roll_error = clampf(frame.landing_body_roll_error, 0.0, 1.0)
	_landing_body_pitch_error = clampf(frame.landing_body_pitch_error, 0.0, 1.0)
	_landing_rotation_error = clampf(frame.landing_rotation_error, -0.5, 0.5)
	if absf(frame.landing_lateral_velocity) > 0.05:
		_landing_lateral_bias = signf(frame.landing_lateral_velocity)
	_landing_left_asymmetry = clampf((-_landing_lateral_bias + (frame.left_ground_distance - frame.right_ground_distance) * 1.5) * profile.landing_asymmetry_gain, -0.4, 0.4)
	_landing_right_asymmetry = clampf((_landing_lateral_bias + (frame.right_ground_distance - frame.left_ground_distance) * 1.5) * profile.landing_asymmetry_gain, -0.4, 0.4)
	if not _landing_active:
		var event := AnimationEvent.LAND_CLEAN
		match frame.landing_outcome:
			LandingSolver.Outcome.SKETCHY: event = AnimationEvent.LAND_SKETCHY
			LandingSolver.Outcome.HARD: event = AnimationEvent.LAND_HARD
			_: event = AnimationEvent.LAND_CLEAN
		_begin_landing_impact(event, maxf(_landing_severity, frame.landing_impact_severity), _landing_lateral_bias)

func _clear_landing_state() -> void:
	_landing_active = false
	_landing_compressing = false
	_landing_compression_target = 0.0
	_landing_severity = 0.0
	_landing_balance_error = 0.0
	_landing_ski_alignment_error = 0.0
	_landing_body_roll_error = 0.0
	_landing_body_pitch_error = 0.0
	_landing_rotation_error = 0.0
	_landing_lateral_bias = 0.0
	_landing_recovery_amount = 0.0
	_landing_wobble_amount = 0.0
	_landing_left_asymmetry = 0.0
	_landing_right_asymmetry = 0.0
	_landing_phase_name = "Idle"
	_landing_outcome = 0

func _update_rail_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var approach_target := frame.rail_approach_anticipation if frame.locomotion_state != STATE_GRIND else 0.0
	_rail_approach_anticipation = _damp(_rail_approach_anticipation, approach_target, profile.rail_approach_response, delta)

	var influence_target := 1.0 if frame.locomotion_state == STATE_GRIND else 0.0
	var influence_response := profile.rail_influence_rise_response if influence_target > _rail_influence else profile.rail_influence_fall_response
	_rail_influence = _damp(_rail_influence, influence_target, influence_response, delta)

	if frame.locomotion_state == STATE_GRIND:
		_rail_balance_last = frame.rail_balance
		if _rail_entry_compressing:
			_rail_entry_compression = _damp(_rail_entry_compression, _rail_entry_compression_target, profile.rail_entry_compression_response, delta)
			if absf(_rail_entry_compression_target - _rail_entry_compression) <= 0.02:
				_rail_entry_compressing = false
		else:
			_rail_entry_compression = _damp(_rail_entry_compression, 0.0, profile.rail_entry_recovery_response, delta)
			if _rail_entry_compression < 0.03:
				_rail_entry_active = false
		var slide_target := 0.0
		if frame.rail_pose < 0:
			slide_target = -profile.rail_slide_max_angle
		elif frame.rail_pose > 0:
			slide_target = profile.rail_slide_max_angle
		_rail_slide_angle = _damp(_rail_slide_angle, slide_target, profile.rail_slide_response, delta)
		var end_window := maxf(profile.rail_exit_anticipation_distance, 0.05)
		var exit_target := clampf(1.0 - smoothstep(0.0, end_window, frame.rail_distance_to_end), 0.0, 1.0)
		_rail_exit_anticipation = _damp(_rail_exit_anticipation, exit_target, profile.rail_exit_response, delta)
		_rail_pole_lag = _damp(_rail_pole_lag, _rail_entry_compression * profile.rail_entry_pole_lag, profile.secondary_response, delta)
		if _rail_entry_compression > 0.1:
			_rail_phase_name = "Entry"
		elif _rail_exit_anticipation > 0.3:
			_rail_phase_name = "Exit"
		else:
			_rail_phase_name = "Slide"
	else:
		_rail_entry_active = false
		_rail_entry_compressing = false
		_rail_entry_compression = _damp(_rail_entry_compression, 0.0, profile.rail_entry_recovery_response, delta)
		_rail_slide_angle = _damp(_rail_slide_angle, 0.0, profile.rail_slide_response, delta)
		_rail_exit_anticipation = _damp(_rail_exit_anticipation, 0.0, profile.rail_exit_response, delta)
		_rail_pole_lag = _damp(_rail_pole_lag, 0.0, profile.secondary_response, delta)
		_rail_phase_name = "Approach" if _rail_approach_anticipation > 0.12 else "Idle"

func _begin_rail_entry(severity: float, lateral_bias: float) -> void:
	_rail_entry_active = true
	_rail_entry_compressing = true
	_rail_entry_severity = clampf(severity, 0.0, 1.0)
	_rail_entry_lateral_bias = clampf(lateral_bias, -1.0, 1.0)
	_rail_entry_compression = maxf(_rail_entry_compression, 0.08)
	_rail_entry_compression_target = clampf(
		lerpf(0.16, profile.rail_entry_max_compression, _rail_entry_severity),
		0.1,
		profile.rail_entry_max_compression
	)
	_rail_entry_left_asymmetry = clampf(-_rail_entry_lateral_bias * profile.rail_leg_asymmetry_gain, -0.35, 0.35)
	_rail_entry_right_asymmetry = clampf(_rail_entry_lateral_bias * profile.rail_leg_asymmetry_gain, -0.35, 0.35)

func _apply_rail_approach_layer(frame: SkierAnimationFrame) -> void:
	if _rail_approach_anticipation <= 0.01 or frame.locomotion_state == STATE_GRIND:
		return
	var amount := _rail_approach_anticipation
	_add_rotation(left_knee, Vector3(profile.rail_approach_knee_ready * amount, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(profile.rail_approach_knee_ready * amount, 0.0, 0.0))
	_add_rotation(spine, Vector3(-profile.rail_approach_torso_center * amount, 0.0, 0.0))
	_add_rotation(left_shoulder, Vector3(0.0, 0.0, -profile.rail_approach_arm_open * amount))
	_add_rotation(right_shoulder, Vector3(0.0, 0.0, profile.rail_approach_arm_open * amount))

func _apply_rail_release_layer(frame: SkierAnimationFrame) -> void:
	# Lets balance/slide correction fade out into the air briefly instead of
	# vanishing on the exact frame the rail releases, without moving the root.
	if _rail_influence <= 0.02 or frame.locomotion_state == STATE_GRIND:
		return
	var fade := _rail_influence
	_add_rotation(pelvis, Vector3(0.0, _rail_slide_angle * 0.3 * fade, _rail_balance_last * profile.rail_pelvis_shift * fade))
	_add_rotation(chest, Vector3(0.0, -_rail_slide_angle * profile.rail_slide_chest_counter * 0.5 * fade, -_rail_balance_last * profile.rail_torso_counter_lean * 0.5 * fade))
	_add_rotation(left_shoulder, Vector3(0.0, 0.0, -_rail_balance_last * profile.rail_arm_balance_gain * 0.6 * fade))
	_add_rotation(right_shoulder, Vector3(0.0, 0.0, -_rail_balance_last * profile.rail_arm_balance_gain * 0.6 * fade))

func _apply_landing_layers(frame: SkierAnimationFrame) -> void:
	var anticipation := _landing_anticipation
	var compression := _landing_compression
	if anticipation <= 0.01 and compression <= 0.01 and _landing_wobble_amount <= 0.01:
		return
	if anticipation > 0.01 and frame.locomotion_state == STATE_AIR:
		_current_pose_name = "Air Descent / Landing Anticipation"
		var extend := anticipation * profile.landing_anticipation_leg_extend
		_add_rotation(left_hip, Vector3(extend * 0.55, 0.0, -0.04 * anticipation))
		_add_rotation(right_hip, Vector3(extend * 0.55, 0.0, 0.04 * anticipation))
		_add_rotation(left_knee, Vector3(-extend * 1.15, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(-extend * 1.15, 0.0, 0.0))
		_add_rotation(left_boot, Vector3(-anticipation * 0.06, 0.0, 0.0))
		_add_rotation(right_boot, Vector3(-anticipation * 0.06, 0.0, 0.0))
		_add_rotation(left_ski, Vector3(_landing_ski_pitch, _landing_ski_yaw * 0.5, 0.0))
		_add_rotation(right_ski, Vector3(_landing_ski_pitch, _landing_ski_yaw * 0.5, 0.0))
		_add_rotation(spine, Vector3(-_landing_torso_prepare * profile.landing_anticipation_torso_pitch, _landing_ski_yaw * 0.35, 0.0))
		_add_rotation(chest, Vector3(-_landing_torso_prepare * profile.landing_anticipation_torso_pitch * 0.65, _landing_ski_yaw * 0.45, 0.0))
		_add_rotation(head, Vector3(anticipation * profile.landing_anticipation_head_pitch, _landing_ski_yaw * 0.55, 0.0))
		_add_rotation(left_shoulder, Vector3(0.08 * anticipation, 0.0, -profile.landing_anticipation_arm_open * anticipation))
		_add_rotation(right_shoulder, Vector3(0.08 * anticipation, 0.0, profile.landing_anticipation_arm_open * anticipation))
		_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(0.0, anticipation * 0.03, 0.0)
	if compression > 0.01 or _landing_wobble_amount > 0.01:
		var depth := compression
		var left_depth := clampf(depth + _landing_left_asymmetry * depth, 0.0, 1.35)
		var right_depth := clampf(depth + _landing_right_asymmetry * depth, 0.0, 1.35)
		var wobble := sin(_landing_wobble_phase) * _landing_wobble_amount * profile.landing_wobble_amplitude
		var counter := -wobble * 0.65
		var rotation_correct := clampf(_landing_rotation_error * 2.0, -1.0, 1.0) * profile.landing_rotation_correct_yaw * (0.4 + depth)
		if _landing_phase_name == "Compression" or _landing_phase_name == "Contact":
			_current_pose_name = "Landing Compression"
		elif _landing_balance_error > 0.28:
			_current_pose_name = "Landing Recovery Wobble"
		else:
			_current_pose_name = "Landing Recovery"
		_add_rotation(left_hip, Vector3(-left_depth * profile.landing_hip_flex, -rotation_correct * 0.35, wobble * 0.35 + _landing_left_asymmetry * 0.2))
		_add_rotation(right_hip, Vector3(-right_depth * profile.landing_hip_flex, -rotation_correct * 0.35, wobble * 0.35 + _landing_right_asymmetry * 0.2))
		_add_rotation(left_knee, Vector3(left_depth * profile.landing_knee_flex, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(right_depth * profile.landing_knee_flex, 0.0, 0.0))
		_add_rotation(left_boot, Vector3(-left_depth * profile.landing_ankle_flex, rotation_correct * 0.25, _landing_left_asymmetry * 0.08))
		_add_rotation(right_boot, Vector3(-right_depth * profile.landing_ankle_flex, rotation_correct * 0.25, _landing_right_asymmetry * 0.08))
		_add_rotation(left_ski, Vector3(-left_depth * 0.04, rotation_correct * 0.55 + _landing_ski_alignment_error * 0.08 * signf(_landing_lateral_bias), _landing_left_asymmetry * 0.1))
		_add_rotation(right_ski, Vector3(-right_depth * 0.04, rotation_correct * 0.55 - _landing_ski_alignment_error * 0.08 * signf(_landing_lateral_bias), _landing_right_asymmetry * 0.1))
		_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(
			wobble * 0.05 - _landing_lateral_bias * depth * 0.04,
			-depth * profile.landing_pelvis_drop,
			0.0
		)
		_add_rotation(pelvis, Vector3(-depth * 0.08 - _landing_body_pitch_error * 0.05, -rotation_correct * 0.4, wobble * 0.55 + _landing_body_roll_error * _landing_lateral_bias * 0.12))
		_add_rotation(spine, Vector3(depth * profile.landing_torso_pitch * 0.55, rotation_correct * 0.5, counter * 0.7))
		_add_rotation(chest, Vector3(depth * profile.landing_torso_pitch, rotation_correct * 0.65, counter))
		_add_rotation(head, Vector3(_landing_head_nod - depth * 0.02, -rotation_correct * 0.35, -counter * 0.45))
		_add_rotation(left_shoulder, Vector3(-0.08 * depth, -rotation_correct * 0.2, -(_landing_arm_open + depth * profile.landing_arm_open * 0.35) - wobble * 0.2))
		_add_rotation(right_shoulder, Vector3(-0.08 * depth, -rotation_correct * 0.2, (_landing_arm_open + depth * profile.landing_arm_open * 0.35) - wobble * 0.2))
		_add_rotation(left_elbow, Vector3(0.12 * depth, 0.0, 0.0))
		_add_rotation(right_elbow, Vector3(0.12 * depth, 0.0, 0.0))
	_pelvis_target_world = balance_root.to_global(_position_targets[pelvis] as Vector3)

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
	var rotation_compact := _spin_compactness
	var phase_compact := clampf(_air_early_weight * 0.55 + _air_apex_weight + _air_descent_weight * 0.3, 0.0, 1.0)
	_air_flex = clampf(
		profile.air_takeoff_leg_flex
		+ _air_size * phase_compact * profile.air_compact_leg_flex
		+ rotation_compact * minf(profile.air_spin_leg_flex, profile.trick_spin_knee_flex),
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
		-_air_takeoff_weight * 0.035 - _air_size * phase_compact * 0.14 + _air_descent_weight * 0.045,
		-_smoothed_angular_velocity.y * 0.008 * _trick_pose_weight,
		-_smoothed_angular_velocity.z * 0.012 * _trick_pose_weight
	))
	_add_rotation(pelvis, Vector3(-_air_size * phase_compact * 0.08, _smoothed_angular_velocity.y * 0.004 * _trick_pose_weight, 0.0))
	var arm_in := _air_size * phase_compact * 0.2 + rotation_compact * 0.28
	var arm_open := profile.air_arm_balance_open * (0.32 + _air_descent_weight * 0.68) * (1.0 - rotation_compact * 0.45)
	var takeoff_swing := _air_takeoff_weight * deliberate_pop * 0.2
	var asymmetry := profile.stance_asymmetry + leg_settle * 0.25
	_add_rotation(left_shoulder, Vector3(takeoff_swing - 0.18 - arm_in + asymmetry, 0.0, -arm_open - asymmetry))
	_add_rotation(right_shoulder, Vector3(takeoff_swing - 0.18 - arm_in - asymmetry, 0.0, arm_open - asymmetry))
	_add_rotation(left_elbow, Vector3(0.54 - arm_in * 0.32 + asymmetry, 0.0, 0.0))
	_add_rotation(right_elbow, Vector3(0.54 - arm_in * 0.32 - asymmetry, 0.0, 0.0))

func _apply_trick_layer(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state == STATE_GRIND:
		return
	var prewind := _prewind_weight
	if frame.trick_phase == TrickCommand.PresentationPhase.SETUP and prewind <= 0.01:
		_current_pose_name = "Flick Setup"
		var setup_strength := clampf(frame.gesture_strength, 0.0, 1.0)
		_position_targets[pelvis] += Vector3(0.0, -profile.flick_setup_depth * setup_strength * 0.06, 0.02 * setup_strength)
		_add_rotation(chest, Vector3(-0.035 * setup_strength, 0.0, 0.0))
		_add_rotation(left_shoulder, Vector3(-0.08 * setup_strength, 0.0, -0.08 * setup_strength))
		_add_rotation(right_shoulder, Vector3(-0.08 * setup_strength, 0.0, 0.08 * setup_strength))
	if prewind > 0.01:
		var side := _prewind_direction
		_current_pose_name = "Spin Prewind %s" % ("Left" if side < 0.0 else "Right")
		# The skis and legs stay in the Phase 2 takeoff pose. Rotation is limited
		# to an athletic upper-body set and unwinds if the flick is abandoned.
		_position_targets[pelvis] += Vector3(side * 0.025 * prewind, -profile.flick_setup_depth * prewind * 0.08, 0.025 * prewind)
		_add_rotation(pelvis, Vector3(-0.025 * prewind, -side * profile.trick_pelvis_yaw_limit * 0.25 * prewind, 0.0))
		_add_rotation(spine, Vector3(-0.05 * prewind, -side * profile.trick_spine_yaw_limit * 0.55 * prewind, side * 0.035 * prewind))
		_add_rotation(chest, Vector3(-0.025 * prewind, -side * profile.trick_prewind_chest_yaw * prewind, side * 0.04 * prewind))
		_add_rotation(head, Vector3(0.0, side * profile.trick_head_yaw_limit * 0.18 * prewind, 0.0))
		_add_rotation(left_shoulder, Vector3(-0.08 * prewind - side * 0.05 * prewind, side * 0.04 * prewind, -0.12 * prewind))
		_add_rotation(right_shoulder, Vector3(-0.08 * prewind + side * 0.05 * prewind, side * 0.04 * prewind, 0.12 * prewind))

	if _trick_release_weight > 0.01 and _is_rotation_kind(frame.trick_kind):
		var release_side := _yaw_direction(frame)
		var release := _trick_release_weight
		_current_pose_name = "Takeoff Release %s" % ("Left" if release_side < 0.0 else "Right")
		_position_targets[pelvis] += Vector3.UP * profile.flick_pop_extension * release * 0.28
		# Shoulder/chest offsets are largest, then pelvis and legs: the physical
		# root still carries every degree of actual takeoff rotation.
		_add_rotation(chest, Vector3(-0.025 * release, release_side * profile.trick_chest_yaw_limit * 0.72 * release, 0.0))
		_add_rotation(spine, Vector3(-0.04 * release, release_side * profile.trick_spine_yaw_limit * 0.58 * release, 0.0))
		_add_rotation(pelvis, Vector3(-0.035 * release, release_side * profile.trick_pelvis_yaw_limit * 0.42 * release, 0.0))
		_add_rotation(left_knee, Vector3(profile.trick_spin_knee_flex * 0.18 * release, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(profile.trick_spin_knee_flex * 0.14 * release, 0.0, 0.0))
		_add_rotation(left_shoulder, Vector3(0.08 * release, release_side * profile.trick_shoulder_yaw_limit * release, -0.2 * release))
		_add_rotation(right_shoulder, Vector3(0.04 * release, release_side * profile.trick_shoulder_yaw_limit * 0.82 * release, 0.16 * release))

	if frame.locomotion_state == STATE_AIR:
		if _trick_pose_weight > 0.01 and frame.trick_phase != TrickCommand.PresentationPhase.RELEASE:
			_apply_command_rotation_pose(frame)
		var opening := 0.0
		if frame.trick_phase == TrickCommand.PresentationPhase.OPEN:
			opening = 1.0
		elif frame.trick_phase == TrickCommand.PresentationPhase.LANDING:
			opening = 0.72
		opening = maxf(opening, _landing_anticipation)
		if opening > 0.01:
			if frame.trick_phase == TrickCommand.PresentationPhase.OPEN:
				_current_pose_name = "Open / Landing Ready"
			elif frame.trick_phase == TrickCommand.PresentationPhase.LANDING:
				_current_pose_name = "Landing Ready"
			_add_rotation(left_hip, Vector3(0.12 * opening, 0.0, -0.035 * opening))
			_add_rotation(right_hip, Vector3(0.12 * opening, 0.0, 0.035 * opening))
			_add_rotation(left_knee, Vector3(-profile.trick_spin_knee_flex * 0.68 * opening, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-profile.trick_spin_knee_flex * 0.68 * opening, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.08 * opening, 0.0, -profile.trick_landing_arm_open * opening))
			_add_rotation(right_shoulder, Vector3(0.08 * opening, 0.0, profile.trick_landing_arm_open * opening))

func _apply_command_rotation_pose(frame: SkierAnimationFrame) -> void:
	var pose := _trick_pose_weight
	var yaw_support := clampf(absf(_smoothed_angular_velocity.y) / maxf(profile.spin_compact_threshold, 0.01), 0.0, 1.0)
	var pitch_support := clampf(absf(_smoothed_angular_velocity.x) / maxf(profile.flip_compact_threshold, 0.01), 0.0, 1.0)
	var roll_support := clampf(absf(_smoothed_angular_velocity.z) / maxf(profile.flip_compact_threshold, 0.01), 0.0, 1.0)
	var yaw_primary := 1.0 if frame.trick_kind in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT, TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT] else profile.trick_multi_axis_weight
	var pitch_primary := 1.0 if frame.trick_kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP] else profile.trick_multi_axis_weight
	var roll_primary := 1.0 if frame.trick_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT] else profile.trick_multi_axis_weight
	var yaw_amount := yaw_support * yaw_primary * pose
	var pitch_amount := pitch_support * pitch_primary * pose
	var roll_amount := roll_support * roll_primary * pose
	var yaw_side := _yaw_direction(frame)
	var pitch_side := signf(_smoothed_angular_velocity.x)
	var roll_side := signf(_smoothed_angular_velocity.z)
	var initiation := 1.0 - smoothstep(deg_to_rad(20.0), deg_to_rad(115.0), absf(frame.rotation_accumulated.y))
	var residual_counter := clampf(
		-frame.rotation_residual.y * _landing_anticipation,
		-profile.trick_chest_yaw_limit * 0.55,
		profile.trick_chest_yaw_limit * 0.55
	)
	var heading_spot := _landing_heading_yaw(frame) * _spotting_weight
	if frame.trick_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		_current_pose_name = "Cork %s" % ("Left" if yaw_side < 0.0 else "Right")

	if yaw_amount > 0.01:
		if frame.trick_kind not in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
			_current_pose_name = "Spin %s" % ("Left" if yaw_side < 0.0 else "Right")
		var lead := yaw_amount * lerpf(0.28, 1.0, initiation)
		_add_rotation(pelvis, Vector3(-0.045 * yaw_amount, clampf(yaw_side * profile.trick_pelvis_yaw_limit * lead + residual_counter * 0.18, -profile.trick_pelvis_yaw_limit, profile.trick_pelvis_yaw_limit), yaw_side * 0.025 * yaw_amount))
		_add_rotation(spine, Vector3(-0.035 * yaw_amount, clampf(yaw_side * profile.trick_spine_yaw_limit * lead + residual_counter * 0.48, -profile.trick_spine_yaw_limit, profile.trick_spine_yaw_limit), -yaw_side * 0.025 * yaw_amount))
		_add_rotation(chest, Vector3(-0.025 * yaw_amount, clampf(yaw_side * profile.trick_chest_yaw_limit * lead + residual_counter, -profile.trick_chest_yaw_limit, profile.trick_chest_yaw_limit), -yaw_side * 0.04 * yaw_amount))
		var head_yaw := clampf(
			yaw_side * profile.trick_head_yaw_limit * 0.28 * yaw_amount * (1.0 - _landing_anticipation)
			+ heading_spot
			+ residual_counter * 0.45,
			-profile.trick_head_yaw_limit,
			profile.trick_head_yaw_limit
		)
		_add_rotation(head, Vector3(0.0, head_yaw, 0.0))
		var arm_tuck := profile.trick_spin_arm_tuck * _spin_compactness
		var arm_asymmetry := yaw_side * 0.055 * yaw_amount
		_add_rotation(left_shoulder, Vector3(-arm_tuck - arm_asymmetry, -yaw_side * profile.trick_shoulder_yaw_limit * lead, -0.11 * yaw_amount))
		_add_rotation(right_shoulder, Vector3(-arm_tuck + arm_asymmetry, -yaw_side * profile.trick_shoulder_yaw_limit * lead * 0.82, 0.14 * yaw_amount))
		_add_rotation(left_elbow, Vector3(-arm_tuck * 0.28, 0.0, -arm_asymmetry * 0.4))
		_add_rotation(right_elbow, Vector3(-arm_tuck * 0.22, 0.0, -arm_asymmetry * 0.32))

	if pitch_amount > 0.01:
		_current_pose_name += " / %s" % ("Frontflip" if pitch_side > 0.0 else "Backflip")
		_add_rotation(pelvis, Vector3(-pitch_side * 0.18 * pitch_amount, 0.0, 0.0))
		_add_rotation(spine, Vector3(-pitch_side * 0.24 * pitch_amount, 0.0, 0.0))
		_add_rotation(chest, Vector3(-pitch_side * 0.12 * pitch_amount, 0.0, 0.0))
		_add_rotation(head, Vector3(pitch_side * 0.1 * pitch_amount, 0.0, 0.0))

	if roll_amount > 0.01:
		if frame.trick_kind not in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
			_current_pose_name += " / Cork"
		_add_rotation(pelvis, Vector3(-0.08 * roll_amount, 0.0, roll_side * 0.14 * roll_amount))
		_add_rotation(spine, Vector3(-0.1 * roll_amount, 0.0, -roll_side * 0.18 * roll_amount))
		_add_rotation(chest, Vector3(-0.04 * roll_amount, 0.0, -roll_side * 0.16 * roll_amount))
		_add_rotation(head, Vector3(0.05 * roll_amount, 0.0, roll_side * 0.07 * roll_amount))

	var compact := _spin_compactness
	if compact > 0.01:
		var leg_asymmetry := yaw_side * profile.trick_leg_asymmetry * compact
		_add_rotation(left_hip, Vector3(-profile.trick_spin_knee_flex * 0.38 * compact, 0.0, -leg_asymmetry))
		_add_rotation(right_hip, Vector3(-profile.trick_spin_knee_flex * 0.34 * compact, 0.0, -leg_asymmetry))
		_add_rotation(left_knee, Vector3(profile.trick_spin_knee_flex * compact + leg_asymmetry, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(profile.trick_spin_knee_flex * compact - leg_asymmetry, 0.0, 0.0))
		_position_targets[pelvis] += Vector3(0.0, -profile.trick_spin_pelvis_drop * compact, 0.0)

func _is_rotation_kind(kind: int) -> bool:
	return kind in [
		TrickCommand.Kind.SPIN_LEFT,
		TrickCommand.Kind.SPIN_RIGHT,
		TrickCommand.Kind.FRONTFLIP,
		TrickCommand.Kind.BACKFLIP,
		TrickCommand.Kind.CORK_LEFT,
		TrickCommand.Kind.CORK_RIGHT,
	]

func _yaw_direction(frame: SkierAnimationFrame) -> float:
	if absf(_smoothed_angular_velocity.y) > 0.05:
		return signf(_smoothed_angular_velocity.y)
	if frame.trick_kind in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.CORK_LEFT]:
		return -1.0
	if frame.trick_kind in [TrickCommand.Kind.SPIN_RIGHT, TrickCommand.Kind.CORK_RIGHT]:
		return 1.0
	return _prewind_direction if absf(_prewind_direction) > 0.05 else 1.0

func _landing_heading_yaw(frame: SkierAnimationFrame) -> float:
	var heading := Vector3(frame.skier_heading.x, 0.0, frame.skier_heading.z)
	var travel := Vector3(frame.velocity_heading.x, 0.0, frame.velocity_heading.z)
	if heading.length_squared() <= 0.001 or travel.length_squared() <= 0.001:
		return 0.0
	return clampf(
		heading.normalized().signed_angle_to(travel.normalized(), Vector3.UP),
		-profile.trick_head_yaw_limit,
		profile.trick_head_yaw_limit
	)

func _apply_grind_pose(frame: SkierAnimationFrame) -> void:
	# Response hierarchy: skis stay nearly stable, legs/pelvis take a moderate
	# share, the torso counters, and the arms carry the largest visible
	# balance correction. rail_balance already comes from real drift/kink
	# physics (SkierController._update_grind) rather than a fabricated wobble.
	var balance := clampf(frame.rail_balance, -1.0, 1.0)
	var balance_severity := clampf(absf(frame.rail_balance), 0.0, 1.35)
	var slide := _rail_slide_angle / maxf(profile.rail_slide_max_angle, 0.01)
	var sideways := absf(slide)
	var entry := _rail_entry_compression
	var exit_prep := _rail_exit_anticipation
	var speed_flex := clampf(frame.rail_speed / 45.0, 0.0, 1.0) * 0.1
	var flex := clampf(
		profile.rail_knee_flex + speed_flex + entry * profile.rail_entry_knee_flex - exit_prep * profile.rail_exit_leg_extend,
		profile.min_leg_flex,
		profile.max_leg_flex
	)
	_current_blend = balance
	_current_pose_name = "Rail Entry" if entry > 0.12 else ("Rail Exit Prep" if exit_prep > 0.35 else "Rail Slide")

	var left_asym := _rail_entry_left_asymmetry * entry - balance * profile.rail_leg_asymmetry_gain * 0.35
	var right_asym := _rail_entry_right_asymmetry * entry + balance * profile.rail_leg_asymmetry_gain * 0.35
	_apply_leg_flex(flex, slide * 0.2, sideways, left_asym, right_asym)

	_position_targets[pelvis] = Vector3(
		balance * profile.rail_pelvis_shift * 0.4,
		0.96 - flex * profile.pelvis_flex_depth - entry * profile.rail_entry_hip_drop + exit_prep * profile.rail_exit_pelvis_rise,
		0.0
	)
	_add_rotation(balance_root, Vector3(0.0, balance * profile.rail_counter_rotation * 0.6, -balance * profile.rail_balance_lean * 0.6))
	_add_rotation(pelvis, Vector3(
		-0.1 - entry * 0.08,
		slide * profile.rail_slide_hip_yaw - balance * 0.08,
		balance * profile.rail_pelvis_shift + slide * 0.06
	))
	_add_rotation(spine, Vector3(0.02 + entry * 0.06, -slide * profile.rail_slide_chest_counter * 0.4, -balance * profile.rail_torso_counter_lean * 0.5))
	_add_rotation(chest, Vector3(
		0.04 + entry * 0.05,
		-slide * profile.rail_slide_chest_counter,
		-balance * profile.rail_torso_counter_lean
	))
	_add_rotation(head, Vector3(exit_prep * 0.1, slide * 0.18, 0.0))

	var near_failure := smoothstep(0.55, 1.0, balance_severity)
	var arm_gain := profile.rail_arm_balance_gain * (1.0 + near_failure * 0.6)
	_add_rotation(left_shoulder, Vector3(-0.22 - entry * 0.1 + exit_prep * profile.rail_exit_arm_ready, slide * 0.1, -0.55 - balance * arm_gain))
	_add_rotation(right_shoulder, Vector3(-0.22 - entry * 0.1 + exit_prep * profile.rail_exit_arm_ready, slide * 0.1, 0.55 - balance * arm_gain))
	_add_rotation(left_elbow, Vector3(0.1 * entry, 0.0, 0.0))
	_add_rotation(right_elbow, Vector3(0.1 * entry, 0.0, 0.0))

	_add_rotation(left_ski, Vector3(0.0, slide * profile.rail_slide_ski_yaw, balance * 0.05))
	_add_rotation(right_ski, Vector3(0.0, slide * profile.rail_slide_ski_yaw, balance * 0.05))

	if sideways > 0.3:
		_current_pose_name = "Boardslide %s" % ("Left" if slide < 0.0 else "Right")

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

func _apply_grab_layer(frame: SkierAnimationFrame) -> void:
	_grab_left_target_active = false
	_grab_right_target_active = false
	if frame.locomotion_state != STATE_AIR or _grab_definition == null or _grab_pose_weight <= 0.005:
		return
	var definition: Resource = _grab_definition
	var body_weight := _grab_pose_weight
	var leg_weight := body_weight * clampf(1.0 - _spin_compactness * 0.38, 0.52, 1.0)
	_current_pose_name = "%s / %s" % [definition.display_name, _grab_phase_name.capitalize()]
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + definition.pelvis_offset * body_weight
	if not definition.style_only:
		var shared_compact := maxf(_spin_compactness, _grab_compactness)
		var extra_compact := maxf(0.0, shared_compact - _spin_compactness)
		_position_targets[chest] = (_position_targets[chest] as Vector3) + Vector3(
			0.0,
			-profile.grab_chest_drop * extra_compact,
			extra_compact * 0.075
		)
		_add_rotation(left_hip, Vector3(-profile.grab_leg_tuck * extra_compact * 0.24, 0.0, 0.0))
		_add_rotation(right_hip, Vector3(-profile.grab_leg_tuck * extra_compact * 0.24, 0.0, 0.0))
		_add_rotation(left_knee, Vector3(profile.grab_leg_tuck * extra_compact * 0.85, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(profile.grab_leg_tuck * extra_compact * 0.85, 0.0, 0.0))
	_apply_grab_definition_pose(definition, body_weight, leg_weight)
	_apply_grab_tweak(definition, frame.grab_tweak, body_weight)
	if definition.style_only:
		return
	var reach_weight := clampf(
		body_weight * profile.grab_reach * definition.reach_response_scale,
		0.0,
		1.0
	)
	reach_weight = maxf(reach_weight, _grab_contact_weight * 0.92)
	if definition.hand == GrabDefinition.Hand.LEFT or definition.hand == GrabDefinition.Hand.BOTH:
		var left_marker := _grab_target_marker(GrabDefinition.Ski.LEFT if definition.target_ski == GrabDefinition.Ski.BOTH else definition.target_ski, definition.target)
		if left_marker != null:
			_grab_left_target_active = true
			_grab_left_target_world = left_marker.global_position
			_grab_left_reach_error = left_hand.global_position.distance_to(_grab_left_target_world)
			_aim_arm_at(left_shoulder, left_elbow, left_hand, _grab_left_target_world, reach_weight, -1.0)
	if definition.hand == GrabDefinition.Hand.RIGHT or definition.hand == GrabDefinition.Hand.BOTH:
		var right_marker := _grab_target_marker(GrabDefinition.Ski.RIGHT if definition.target_ski == GrabDefinition.Ski.BOTH else definition.target_ski, definition.target)
		if right_marker != null:
			_grab_right_target_active = true
			_grab_right_target_world = right_marker.global_position
			_grab_right_reach_error = right_hand.global_position.distance_to(_grab_right_target_world)
			_aim_arm_at(right_shoulder, right_elbow, right_hand, _grab_right_target_world, reach_weight, 1.0)

func _apply_grab_definition_pose(definition: Resource, body_weight: float, leg_weight: float) -> void:
	_add_rotation(pelvis, definition.pelvis_rotation * body_weight)
	_add_rotation(spine, definition.spine_rotation * body_weight)
	_add_rotation(chest, definition.chest_rotation * body_weight)
	_add_rotation(left_hip, definition.left_hip_rotation * leg_weight)
	_add_rotation(right_hip, definition.right_hip_rotation * leg_weight)
	_add_rotation(left_knee, definition.left_knee_rotation * leg_weight)
	_add_rotation(right_knee, definition.right_knee_rotation * leg_weight)
	_add_rotation(left_ski, definition.left_ski_rotation * leg_weight)
	_add_rotation(right_ski, definition.right_ski_rotation * leg_weight)
	_add_rotation(left_shoulder, definition.left_shoulder_rotation * body_weight)
	_add_rotation(right_shoulder, definition.right_shoulder_rotation * body_weight)
	_add_rotation(left_elbow, definition.left_elbow_rotation * body_weight)
	_add_rotation(right_elbow, definition.right_elbow_rotation * body_weight)

func _apply_grab_tweak(definition: Resource, tweak: Vector2, amount: float) -> void:
	if tweak.length() <= 0.05 or definition.style_only:
		return
	var pitch := clampf(tweak.y, -1.0, 1.0) * profile.grab_tweak_angle * amount
	var roll := clampf(tweak.x, -1.0, 1.0) * profile.grab_tweak_angle * amount
	if definition.target_ski == GrabDefinition.Ski.LEFT or definition.target_ski == GrabDefinition.Ski.BOTH:
		_add_rotation(left_hip, Vector3(-pitch * 0.3, 0.0, -roll * 0.28))
		_add_rotation(left_knee, Vector3(pitch * 0.55, 0.0, 0.0))
		_add_rotation(left_boot, Vector3(pitch * 0.55, 0.0, -roll * 0.72))
		_add_rotation(left_ski, Vector3(pitch * 0.18, 0.0, -roll * 0.28))
	if definition.target_ski == GrabDefinition.Ski.RIGHT or definition.target_ski == GrabDefinition.Ski.BOTH:
		_add_rotation(right_hip, Vector3(-pitch * 0.3, 0.0, roll * 0.28))
		_add_rotation(right_knee, Vector3(pitch * 0.55, 0.0, 0.0))
		_add_rotation(right_boot, Vector3(pitch * 0.55, 0.0, roll * 0.72))
		_add_rotation(right_ski, Vector3(pitch * 0.18, 0.0, roll * 0.28))

func _grab_target_marker(ski_side: int, target: int) -> Node3D:
	if ski_side == GrabDefinition.Ski.LEFT:
		match target:
			GrabDefinition.Target.BINDING_OUTSIDE: return left_grab_binding_outside
			GrabDefinition.Target.BINDING_INSIDE: return left_grab_binding_inside
			GrabDefinition.Target.NOSE: return left_grab_nose
			GrabDefinition.Target.TAIL: return left_grab_tail
	elif ski_side == GrabDefinition.Ski.RIGHT:
		match target:
			GrabDefinition.Target.BINDING_OUTSIDE: return right_grab_binding_outside
			GrabDefinition.Target.BINDING_INSIDE: return right_grab_binding_inside
			GrabDefinition.Target.NOSE: return right_grab_nose
			GrabDefinition.Target.TAIL: return right_grab_tail
	return null

func _aim_arm_at(shoulder: Node3D, elbow: Node3D, hand: Node3D, target_world: Vector3, amount: float, side: float) -> void:
	var target_local := shoulder.to_local(target_world)
	if target_local.length_squared() < 0.0001:
		return
	var upper := profile.grab_upper_arm_length
	var lower := profile.grab_forearm_length
	var raw_distance := target_local.length()
	var distance := clampf(raw_distance, absf(upper - lower) + 0.01, upper + lower - 0.005)
	var direction := target_local.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var pole := Vector3(side, 0.08, 0.42).normalized()
	var bend_axis := (pole - direction * pole.dot(direction)).normalized()
	if bend_axis.length_squared() < 0.01:
		bend_axis = Vector3(side, 0.0, 0.0)
	var elbow_target := direction * along + bend_axis * height
	var shoulder_rotation := Quaternion(Vector3.DOWN, elbow_target.normalized())
	var lower_direction := (direction * distance - elbow_target).normalized()
	var elbow_rotation := Quaternion(Vector3.DOWN, shoulder_rotation.inverse() * lower_direction)
	var current_target := _rotation_targets[shoulder] as Vector3
	var shoulder_target := shoulder_rotation.get_euler()
	shoulder_target = Vector3(
		clampf(shoulder_target.x, -profile.grab_shoulder_pitch_limit, profile.grab_shoulder_pitch_limit),
		clampf(shoulder_target.y, -profile.grab_shoulder_yaw_limit, profile.grab_shoulder_yaw_limit),
		clampf(shoulder_target.z, -profile.grab_shoulder_roll_limit, profile.grab_shoulder_roll_limit)
	)
	var elbow_target_rotation := elbow_rotation.get_euler()
	elbow_target_rotation = Vector3(
		clampf(elbow_target_rotation.x, -profile.grab_elbow_limit, profile.grab_elbow_limit),
		clampf(elbow_target_rotation.y, -profile.grab_elbow_limit * 0.35, profile.grab_elbow_limit * 0.35),
		clampf(elbow_target_rotation.z, -profile.grab_elbow_limit * 0.35, profile.grab_elbow_limit * 0.35)
	)
	var solve_weight := clampf(amount, 0.0, 0.92)
	_rotation_targets[shoulder] = current_target.lerp(shoulder_target, solve_weight)
	_rotation_targets[elbow] = (_rotation_targets[elbow] as Vector3).lerp(elbow_target_rotation, solve_weight)
	var hand_direction := hand.to_local(target_world)
	if hand_direction.length_squared() > 0.0001:
		var hand_yaw := clampf(atan2(hand_direction.x, -hand_direction.z), -0.45, 0.45)
		_rotation_targets[hand] = (_rotation_targets[hand] as Vector3).lerp(Vector3(0.0, hand_yaw, 0.0), solve_weight * 0.45)

func _grab_primary_reach_error() -> float:
	if _grab_left_target_active and _grab_right_target_active:
		return maxf(_grab_left_reach_error, _grab_right_reach_error)
	if _grab_left_target_active:
		return _grab_left_reach_error
	if _grab_right_target_active:
		return _grab_right_reach_error
	return 0.0

func _grab_hand_name() -> String:
	if _grab_definition == null:
		return "NONE"
	match int(_grab_definition.hand):
		GrabDefinition.Hand.LEFT: return "LEFT"
		GrabDefinition.Hand.RIGHT: return "RIGHT"
		GrabDefinition.Hand.BOTH: return "BOTH"
	return "NONE"

func _grab_target_ski_name() -> String:
	if _grab_definition == null:
		return "NONE"
	match int(_grab_definition.target_ski):
		GrabDefinition.Ski.LEFT: return "LEFT"
		GrabDefinition.Ski.RIGHT: return "RIGHT"
		GrabDefinition.Ski.BOTH: return "BOTH"
	return "NONE"

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
		var landing_trail := _landing_pole_lag + _landing_compression * 0.18
		_add_rotation(left_pole, Vector3(-arm_chain_pitch - speed_trail - landing_trail + asymmetry, -_pole_carve * profile.pole_turn_lag - _landing_lateral_bias * landing_trail * 0.35, -left_arm_roll - asymmetry - _landing_arm_open * 0.2))
		_add_rotation(right_pole, Vector3(-arm_chain_pitch - speed_trail - landing_trail - asymmetry, -_pole_carve * profile.pole_turn_lag - _landing_lateral_bias * landing_trail * 0.35, -right_arm_roll + asymmetry + _landing_arm_open * 0.2))
	elif frame.locomotion_state == STATE_AIR:
		var rotation_follow := _spin_compactness
		var takeoff_lag := _air_takeoff_weight * 0.16
		var settle := 1.0 - _landing_anticipation * 0.48
		var phase_trail := (profile.air_pole_trail + _air_early_weight * 0.12 - _air_descent_weight * 0.08) * settle
		var anticipation_trail := _landing_anticipation * 0.12
		var spin_side := signf(_smoothed_angular_velocity.y)
		var asymmetry := profile.stance_asymmetry + spin_side * profile.trick_leg_asymmetry * rotation_follow * 0.35
		var yaw_lag := clampf(
			-_smoothed_angular_velocity.y * profile.trick_pole_lag * 0.12 * _trick_pose_weight,
			-profile.trick_shoulder_yaw_limit,
			profile.trick_shoulder_yaw_limit
		)
		_add_rotation(left_pole, Vector3(-phase_trail - takeoff_lag - anticipation_trail + asymmetry, yaw_lag, 0.18 + rotation_follow * 0.08 + _landing_anticipation * 0.12))
		_add_rotation(right_pole, Vector3(-phase_trail - takeoff_lag - anticipation_trail - asymmetry, yaw_lag * 0.82, -0.18 - rotation_follow * 0.08 - _landing_anticipation * 0.12))
		if _grab_definition != null and _grab_pose_weight > 0.01:
			var pole_away := profile.grab_pole_away * _grab_pose_weight
			if _grab_definition.hand == GrabDefinition.Hand.LEFT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
				_add_rotation(left_pole, Vector3(-pole_away * 0.35, yaw_lag * 0.25, pole_away))
			if _grab_definition.hand == GrabDefinition.Hand.RIGHT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
				_add_rotation(right_pole, Vector3(-pole_away * 0.35, yaw_lag * 0.25, -pole_away))
	elif frame.locomotion_state == STATE_GRIND:
		var speed_trail := 0.1 + clampf(frame.rail_speed / 20.0, 0.0, 1.0) * 0.22
		var slide_amount := _rail_slide_angle / maxf(profile.rail_slide_max_angle, 0.01)
		var asymmetry := profile.stance_asymmetry
		_add_rotation(left_pole, Vector3(-0.3 - speed_trail - _rail_pole_lag + asymmetry, slide_amount * 0.15, 0.05))
		_add_rotation(right_pole, Vector3(-0.3 - speed_trail - _rail_pole_lag - asymmetry, slide_amount * 0.15, -0.05))
	if frame.switch_stance:
		_add_rotation(chest, Vector3(0.0, 0.08, 0.0))
		_add_rotation(head, Vector3(0.0, -0.12, 0.0))

func _enforce_joint_limits() -> void:
	_clamp_rotation_target(pelvis, Vector3(-1.0, -0.72, -0.72), Vector3(0.65, 0.72, 0.72))
	_clamp_rotation_target(spine, Vector3(-1.15, -0.78, -0.78), Vector3(0.72, 0.78, 0.78))
	_clamp_rotation_target(chest, Vector3(-0.95, -0.82, -0.82), Vector3(0.72, 0.82, 0.82))
	_clamp_rotation_target(head, Vector3(-0.55, -profile.trick_head_yaw_limit, -0.48), Vector3(0.55, profile.trick_head_yaw_limit, 0.48))
	var shoulder_minimum := Vector3(-profile.grab_shoulder_pitch_limit, -profile.grab_shoulder_yaw_limit, -profile.grab_shoulder_roll_limit)
	var shoulder_maximum := Vector3(profile.grab_shoulder_pitch_limit, profile.grab_shoulder_yaw_limit, profile.grab_shoulder_roll_limit)
	_clamp_rotation_target(left_shoulder, shoulder_minimum, shoulder_maximum)
	_clamp_rotation_target(right_shoulder, shoulder_minimum, shoulder_maximum)
	var elbow_minimum := Vector3(-profile.grab_elbow_limit, -0.55, -0.55)
	var elbow_maximum := Vector3(profile.grab_elbow_limit, 0.55, 0.55)
	_clamp_rotation_target(left_elbow, elbow_minimum, elbow_maximum)
	_clamp_rotation_target(right_elbow, elbow_minimum, elbow_maximum)
	_clamp_rotation_target(left_hip, Vector3(-1.4, -0.7, -0.72), Vector3(0.72, 0.7, 0.72))
	_clamp_rotation_target(right_hip, Vector3(-1.4, -0.7, -0.72), Vector3(0.72, 0.7, 0.72))
	_clamp_rotation_target(left_knee, Vector3(-0.45, -0.28, -0.35), Vector3(2.35, 0.28, 0.35))
	_clamp_rotation_target(right_knee, Vector3(-0.45, -0.28, -0.35), Vector3(2.35, 0.28, 0.35))
	_clamp_rotation_target(left_boot, Vector3(-0.9, -0.45, -0.5), Vector3(0.55, 0.45, 0.5))
	_clamp_rotation_target(right_boot, Vector3(-0.9, -0.45, -0.5), Vector3(0.55, 0.45, 0.5))
	_clamp_rotation_target(left_ski, Vector3(-0.48, -0.5, -0.48), Vector3(0.48, 0.5, 0.48))
	_clamp_rotation_target(right_ski, Vector3(-0.48, -0.5, -0.48), Vector3(0.48, 0.5, 0.48))
	if _current_state == STATE_AIR:
		var left_target := _rotation_targets[left_ski] as Vector3
		var right_target := _rotation_targets[right_ski] as Vector3
		var yaw_average := (left_target.y + right_target.y) * 0.5
		var yaw_half_separation := clampf((left_target.y - right_target.y) * 0.5, -0.14, 0.14)
		left_target.y = yaw_average + yaw_half_separation
		right_target.y = yaw_average - yaw_half_separation
		_rotation_targets[left_ski] = left_target
		_rotation_targets[right_ski] = right_target

func _clamp_rotation_target(joint: Node3D, minimum: Vector3, maximum: Vector3) -> void:
	var target := _rotation_targets[joint] as Vector3
	_rotation_targets[joint] = Vector3(
		clampf(target.x, minimum.x, maximum.x),
		clampf(target.y, minimum.y, maximum.y),
		clampf(target.z, minimum.z, maximum.z)
	)

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
	_smoothed_angular_velocity = Vector3.ZERO
	_trick_rotation_accumulated = Vector3.ZERO
	_trick_rotation_residual = Vector3.ZERO
	_trick_pose_weight = 0.0
	_prewind_weight = 0.0
	_prewind_direction = 0.0
	_trick_release_weight = 0.0
	_spin_compactness = 0.0
	_spotting_weight = 0.0
	_trick_active = false
	_trick_intent = false
	_trick_kind = TrickCommand.Kind.NONE
	_grab_definition = null
	_grab_pose_id = TrickController.GrabPose.NONE
	_grab_phase_name = "IDLE"
	_grab_pose_weight = 0.0
	_grab_contact_weight = 0.0
	_grab_compactness = 0.0
	_grab_input_strength = 0.0
	_grab_hold_time = 0.0
	_grab_release_time = 0.0
	_grab_contact_latched = false
	_grab_left_target_active = false
	_grab_right_target_active = false
	_grab_left_reach_error = 0.0
	_grab_right_reach_error = 0.0
	_clear_landing_state()
	_landing_anticipation = 0.0
	_landing_compression = 0.0
	_landing_arm_open = 0.0
	_landing_pole_lag = 0.0
	_landing_head_nod = 0.0
	_landing_ski_yaw = 0.0
	_landing_ski_pitch = 0.0
	_landing_torso_prepare = 0.0
	_rail_influence = 0.0
	_rail_approach_anticipation = 0.0
	_rail_entry_active = false
	_rail_entry_compressing = false
	_rail_entry_severity = 0.0
	_rail_entry_compression = 0.0
	_rail_entry_compression_target = 0.0
	_rail_entry_lateral_bias = 0.0
	_rail_entry_left_asymmetry = 0.0
	_rail_entry_right_asymmetry = 0.0
	_rail_slide_angle = 0.0
	_rail_exit_anticipation = 0.0
	_rail_pole_lag = 0.0
	_rail_balance_last = 0.0
	_rail_phase_name = "Idle"
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
	left_grab_binding_outside = _joint("LeftGrabBindingOutside", left_ski, Vector3(-0.075, 0.04, 0.05))
	left_grab_binding_inside = _joint("LeftGrabBindingInside", left_ski, Vector3(0.075, 0.04, 0.02))
	left_grab_nose = _joint("LeftGrabNose", left_ski, Vector3(0.0, 0.04, -0.72))
	left_grab_tail = _joint("LeftGrabTail", left_ski, Vector3(0.0, 0.04, 0.42))
	right_grab_binding_outside = _joint("RightGrabBindingOutside", right_ski, Vector3(0.075, 0.04, 0.05))
	right_grab_binding_inside = _joint("RightGrabBindingInside", right_ski, Vector3(-0.075, 0.04, 0.02))
	right_grab_nose = _joint("RightGrabNose", right_ski, Vector3(0.0, 0.04, -0.72))
	right_grab_tail = _joint("RightGrabTail", right_ski, Vector3(0.0, 0.04, 0.42))

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
