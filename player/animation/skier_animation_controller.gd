class_name SkierAnimationController
extends Node3D

const GrabDefinition = preload("res://player/animation/grab_animation_definition.gd")
const PoseShapeDefinition = preload("res://player/animation/skier_pose_shape_definition.gd")
const PoseDriverModule = preload("res://player/animation/skier_pose_driver.gd")
const PrimitiveRigModule = preload("res://player/animation/primitive_skier_rig.gd")
const SkeletonRigModule = preload("res://player/animation/skeleton_skier_rig.gd")

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

enum RigMode { AUTO, SKELETON, PRIMITIVE }

const STATE_GROUND := 0
const STATE_AIR := 1
const STATE_GRIND := 2
const STATE_BAIL := 3

@export var profile: SkierAnimationProfile = preload("res://resources/animation/default_animation_profile.tres")
@export var grab_library: Resource = preload("res://resources/animation/default_grab_animation_library.tres")
@export var style_library: Resource = preload("res://resources/animation/default_style_pose_library.tres")
@export var rig_mode: RigMode = RigMode.AUTO
@export var skeleton_profile: SkierSkeletonProfile = preload("res://resources/animation/default_skier_skeleton_profile.tres")

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
var left_pole_tip: Node3D
var right_pole_tip: Node3D
var left_grab_binding_outside: Node3D
var left_grab_binding_inside: Node3D
var left_grab_nose: Node3D
var left_grab_tail: Node3D
var right_grab_binding_outside: Node3D
var right_grab_binding_inside: Node3D
var right_grab_nose: Node3D
var right_grab_tail: Node3D
var pose_driver: SkierPoseDriver
var rig_adapter: SkierRigAdapter
var rig_fallback_reason := ""
var requested_rig_adapter := "skeleton"

var _rotation_targets: Dictionary = {}
var _position_targets: Dictionary = {}
var _elapsed := 0.0
var _reaction_event := -1
var _reaction_time := 0.0
var _reaction_duration := 0.0
var _reaction_strength := 0.0
var _reaction_side := 0.0
var _current_state := STATE_AIR
var _previous_state := STATE_AIR
var _state_transition_weight := 1.0
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
var _style_definitions_by_pose: Dictionary = {}
var _style_definition: Resource
var _style_pose_id := TrickController.StylePose.NONE
var _style_pose_weight := 0.0
var _style_phase_name := "IDLE"
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
var _slarve_weight := 0.0
var _slarve_side := 0.0
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
var _air_style_side := 1.0
var _smoothed_angular_velocity := Vector3.ZERO
var _trick_rotation_accumulated := Vector3.ZERO
var _trick_rotation_residual := Vector3.ZERO
var _trick_pose_weight := 0.0
var _prewind_weight := 0.0
var _prewind_direction := 0.0
var _trick_release_weight := 0.0
var _spin_compactness := 0.0
var _spin_cycle := 0.0
var _spotting_weight := 0.0
var _spin_open_weight := 0.0
var _spin_visual_phase_name := "IDLE"
var _trick_active := false
var _trick_intent := false
var _trick_kind := TrickCommand.Kind.NONE
var _landing_alignment := 0.0
var _landing_anticipation := 0.0
var _landing_readiness := 0.0
var _landing_readiness_heading := 0.0
var _landing_readiness_pitch := 0.0
var _landing_readiness_spin := 0.0
var _landing_readiness_upright := 0.0
var _landing_readiness_residual := 0.0
var _landing_projected_heading_error := 0.0
var _landing_projected_residual := 0.0
var _landing_readiness_valid := false
var _landing_ready := false
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
var _stomp_candidate := false
var _stomp_active := false
var _stomp_time := 0.0
var _stomp_weight := 0.0
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
var _secondary_signals_initialized := false
var _previous_vertical_velocity := 0.0
var _previous_yaw_rate := 0.0
var _previous_landing_compression := 0.0
var _filtered_lateral_accel := 0.0
var _filtered_vertical_accel := 0.0
var _filtered_yaw_accel := 0.0
var _filtered_heading_delta := 0.0
var _landing_compression_velocity := 0.0
var _torso_follow_through := Vector3.ZERO
var _head_stabilization := Vector3.ZERO
var _left_arm_inertia := Vector3.ZERO
var _right_arm_inertia := Vector3.ZERO
var _left_pole_inertia := Vector3.ZERO
var _right_pole_inertia := Vector3.ZERO
var _leg_rebound := 0.0
var _secondary_motion_weight := 0.0
var _crash_stage_name := "None"
var _crash_layer_weight := 0.0
var _pre_bail_weight := 0.0
var _pre_bail_side := 0.0
var _previous_left_hand_position := Vector3.ZERO
var _previous_right_hand_position := Vector3.ZERO
var _previous_left_hand_velocity := Vector3.ZERO
var _previous_right_hand_velocity := Vector3.ZERO
var _filtered_left_hand_accel := Vector3.ZERO
var _filtered_right_hand_accel := Vector3.ZERO

func _ready() -> void:
	_build_articulated_rig()
	_cache_grab_definitions()
	_cache_style_definitions()
	_initialize_secondary_motion_state()

func apply_frame(frame: SkierAnimationFrame, delta: float) -> void:
	_elapsed += delta
	_current_state = frame.locomotion_state
	_cache_air_style_side(frame)
	_update_skiing_dynamics(frame, delta)
	_update_terrain_suspension(frame, delta)
	_update_jump_animation(frame, delta)
	_update_landing_animation(frame, delta)
	_update_rail_animation(frame, delta)
	_update_trick_animation(frame, delta)
	_update_grab_animation(frame, delta)
	_update_style_animation(frame, delta)
	_update_secondary_motion_signals(frame, delta)
	_update_pre_bail_response(frame, delta)
	_reset_targets()
	match frame.locomotion_state:
		STATE_GROUND: _apply_ground_pose(frame)
		STATE_AIR: _apply_air_pose(frame)
		STATE_GRIND: _apply_grind_pose(frame)
		STATE_BAIL: _apply_bail_pose(frame)
	_apply_trick_layer(frame)
	_apply_grab_layer(frame)
	_apply_style_layer(frame)
	_apply_landing_layers(frame)
	_apply_stomp_layer(frame)
	_apply_rail_approach_layer(frame)
	_apply_rail_release_layer(frame)
	_apply_reaction(frame, delta)
	_apply_secondary_motion(frame)
	_apply_pre_bail_layer(frame)
	_enforce_joint_limits()
	_blend_targets(delta)
	if rig_adapter != null:
		rig_adapter.sync_pose(delta)

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
			_reset_pose_immediately(false)

func is_landing_idle() -> bool:
	return not _landing_active and not _stomp_active and _landing_compression < 0.02 and _landing_alignment < 0.02 and _landing_anticipation < 0.02

func debug_snapshot() -> Dictionary:
	return {
		"rig_adapter": rig_adapter.adapter_name() if rig_adapter != null else "none",
		"rig_requested": requested_rig_adapter,
		"rig_fallback_reason": rig_fallback_reason,
		"state": ["GROUND", "AIR", "GRIND", "BAIL"][_current_state],
		"pose": _current_pose_name,
		"blend": _current_blend,
		"reaction": _reaction_event,
		"reaction_time": _reaction_time,
		"pelvis_height": pelvis.position.y,
		"pelvis_position": pelvis.position,
		"balance_root_rotation": balance_root.rotation,
		"pelvis_rotation": pelvis.rotation,
		"spine_rotation": spine.rotation,
		"chest_rotation": chest.rotation,
		"head_rotation": head.rotation,
		"left_hip_rotation": left_hip.rotation,
		"right_hip_rotation": right_hip.rotation,
		"left_knee_rotation": left_knee.rotation,
		"right_knee_rotation": right_knee.rotation,
		"left_boot_rotation": left_boot.rotation,
		"right_boot_rotation": right_boot.rotation,
		"left_ski_rotation": left_ski.rotation,
		"right_ski_rotation": right_ski.rotation,
		"left_shoulder_rotation": left_shoulder.rotation,
		"right_shoulder_rotation": right_shoulder.rotation,
		"left_elbow_rotation": left_elbow.rotation,
		"right_elbow_rotation": right_elbow.rotation,
		"left_hand_rotation": left_hand.rotation,
		"right_hand_rotation": right_hand.rotation,
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
		"slarve_weight": _slarve_weight,
		"slarve_side": _slarve_side,
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
		"air_style_side": _air_style_side,
		"trick_active": _trick_active,
		"trick_intent": _trick_intent,
		"spin_direction": signf(_smoothed_angular_velocity.y) if absf(_smoothed_angular_velocity.y) > 0.05 else _prewind_direction,
		"spin_visual_phase": _spin_visual_phase_name,
		"spin_open_weight": _spin_open_weight,
		"rotation_accumulated": _trick_rotation_accumulated,
		"root_yaw_rate": _smoothed_angular_velocity.y,
		"root_pitch_rate": _smoothed_angular_velocity.x,
		"root_roll_rate": _smoothed_angular_velocity.z,
		"spin_compactness": _spin_compactness,
		"spin_cycle": _spin_cycle,
		"prewind_weight": _prewind_weight,
		"trick_release_weight": _trick_release_weight,
		"trick_pose_weight": _trick_pose_weight,
		"spotting_weight": _spotting_weight,
		"landing_blend": _landing_anticipation,
		"landing_alignment": _landing_alignment,
		"landing_readiness": _landing_readiness,
		"rotation_residual": _trick_rotation_residual,
		"landing_anticipation": _landing_anticipation,
		"landing_readiness_heading": _landing_readiness_heading,
		"landing_readiness_pitch": _landing_readiness_pitch,
		"landing_readiness_spin": _landing_readiness_spin,
		"landing_readiness_upright": _landing_readiness_upright,
		"landing_readiness_residual": _landing_readiness_residual,
		"landing_projected_heading_error": _landing_projected_heading_error,
		"landing_projected_residual": _landing_projected_residual,
		"landing_readiness_valid": _landing_readiness_valid,
		"landing_ready": _landing_ready,
		"landing_compression": _landing_compression,
		"landing_severity": _landing_severity,
		"landing_balance_error": _landing_balance_error,
		"landing_ski_alignment_error": _landing_ski_alignment_error,
		"landing_body_roll_error": _landing_body_roll_error,
		"landing_body_pitch_error": _landing_body_pitch_error,
		"landing_rotation_error": _landing_rotation_error,
		"landing_recovery": _landing_recovery_amount,
		"landing_phase": _landing_phase_name,
		"stomp_weight": _stomp_weight,
		"stomp_active": _stomp_active,
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
		"style_pose": _style_pose_id,
		"style_pose_name": _style_definition.display_name if _style_definition != null else "NONE",
		"style_pose_weight": _style_pose_weight,
		"style_phase": _style_phase_name,
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
		"lateral_accel_filtered": _filtered_lateral_accel,
		"vertical_accel_filtered": _filtered_vertical_accel,
		"yaw_accel_filtered": _filtered_yaw_accel,
		"heading_delta_filtered": _filtered_heading_delta,
		"torso_follow_through": _torso_follow_through,
		"head_stabilization": _head_stabilization,
		"left_arm_inertia": _left_arm_inertia,
		"right_arm_inertia": _right_arm_inertia,
		"left_pole_inertia": _left_pole_inertia,
		"right_pole_inertia": _right_pole_inertia,
		"canonical_landmarks": pose_driver.canonical_landmarks() if pose_driver != null else {},
		"silhouette_landmarks": _silhouette_landmarks(),
		"leg_rebound": _leg_rebound,
		"secondary_motion_weight": _secondary_motion_weight,
		"crash_stage": _crash_stage_name,
		"crash_layer_weight": _crash_layer_weight,
		"pre_bail_weight": _pre_bail_weight,
		"pre_bail_side": _pre_bail_side,
		"state_transition_weight": _state_transition_weight,
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
	elif not grounded and _crossover_time <= 0.0:
		_last_loaded_direction = 0.0
	if _crossover_time > 0.0:
		_crossover_time = maxf(0.0, _crossover_time - delta)
	var slarve_target := 0.0
	if grounded and not frame.braking:
		var skid_demand := smoothstep(profile.slarve_skid_start, profile.slarve_skid_full, clampf(frame.skid_ratio, 0.0, 1.0))
		var heading_demand := smoothstep(0.08, maxf(profile.slarve_heading_reference, 0.09), absf(frame.heading_velocity_delta))
		slarve_target = skid_demand * lerpf(0.58, 1.0, heading_demand)
		var side_source := frame.heading_velocity_delta if absf(frame.heading_velocity_delta) > 0.05 else frame.skid
		if absf(side_source) > 0.02:
			_slarve_side = signf(side_source)
	_slarve_weight = _damp(_slarve_weight, slarve_target, profile.leg_carve_response, delta)
	if _slarve_weight < 0.01 and not grounded:
		_slarve_side = 0.0
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

func _initialize_secondary_motion_state() -> void:
	_previous_left_hand_position = to_local(left_hand.global_position)
	_previous_right_hand_position = to_local(right_hand.global_position)
	_previous_left_hand_velocity = Vector3.ZERO
	_previous_right_hand_velocity = Vector3.ZERO

func _cache_air_style_side(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state != STATE_AIR or _previous_state == STATE_AIR:
		return
	if absf(frame.gesture_direction.x) > 0.05:
		_air_style_side = signf(frame.gesture_direction.x)
	elif absf(_last_loaded_direction) > 0.05:
		_air_style_side = signf(_last_loaded_direction)
	else:
		_air_style_side = -1.0 if frame.switch_stance else 1.0

func _update_secondary_motion_signals(frame: SkierAnimationFrame, delta: float) -> void:
	var safe_delta := maxf(delta, 0.0001)
	if frame.locomotion_state != _previous_state:
		_previous_state = frame.locomotion_state
		_state_transition_weight = 0.0
	_state_transition_weight = _damp(_state_transition_weight, 1.0, profile.secondary_release_response, delta)

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
	if _secondary_signals_initialized:
		raw_vertical_accel = (frame.vertical_velocity - _previous_vertical_velocity) / safe_delta
		raw_yaw_accel = (bounded_yaw_rate - _previous_yaw_rate) / safe_delta
	_landing_compression_velocity = (
		(_landing_compression - _previous_landing_compression) / safe_delta
		if _secondary_signals_initialized
		else 0.0
	)
	raw_vertical_accel = clampf(raw_vertical_accel, -profile.secondary_max_vertical_accel, profile.secondary_max_vertical_accel)
	raw_yaw_accel = clampf(raw_yaw_accel, -profile.secondary_max_yaw_accel, profile.secondary_max_yaw_accel)
	_filtered_lateral_accel = _damp(_filtered_lateral_accel, bounded_lateral, profile.secondary_signal_response, delta)
	_filtered_vertical_accel = _damp(_filtered_vertical_accel, raw_vertical_accel, profile.secondary_signal_response, delta)
	_filtered_yaw_accel = _damp(_filtered_yaw_accel, raw_yaw_accel, profile.secondary_signal_response, delta)
	_filtered_heading_delta = _damp(
		_filtered_heading_delta,
		clampf(frame.heading_velocity_delta, -0.9, 0.9),
		profile.head_stabilization_response,
		delta
	)

	var left_hand_position := to_local(left_hand.global_position)
	var right_hand_position := to_local(right_hand.global_position)
	if _secondary_signals_initialized:
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
	_previous_landing_compression = _landing_compression
	_secondary_signals_initialized = true

	var acceleration_activity := maxf(
		absf(_filtered_lateral_accel) / maxf(profile.secondary_max_lateral_accel, 0.01),
		maxf(
			absf(_filtered_vertical_accel) / maxf(profile.secondary_max_vertical_accel, 0.01),
			absf(_filtered_yaw_accel) / maxf(profile.secondary_max_yaw_accel, 0.01)
		)
	)
	var state_activity := maxf(
		_landing_compression,
		maxf(_rail_entry_compression, maxf(_trick_pose_weight, maxf(_grab_pose_weight, _crossover_release())))
	)
	var speed_activity := smoothstep(0.08, 0.85, clampf(frame.speed_ratio, 0.0, 1.0))
	var secondary_target := clampf(acceleration_activity * 0.62 + state_activity * 0.48 + speed_activity * 0.16, 0.0, 1.0)
	if frame.locomotion_state == STATE_BAIL:
		secondary_target = 0.0
	_secondary_motion_weight = _damp(_secondary_motion_weight, secondary_target, profile.secondary_signal_response, delta)

	var torso_target := Vector3(
		-_filtered_vertical_accel * profile.torso_vertical_accel_gain,
		-_filtered_yaw_accel * profile.torso_yaw_accel_gain,
		(_pelvis_carve - _torso_carve) * profile.torso_carve_lag_gain
			- _filtered_lateral_accel * profile.torso_lateral_accel_gain
	)
	torso_target *= lerpf(1.0, 0.62, _trick_pose_weight) * _secondary_motion_weight
	torso_target = _limit_vector_components(torso_target, profile.torso_follow_limit)
	_torso_follow_through = _damp_vector(_torso_follow_through, torso_target, profile.torso_follow_response, delta)
	var head_target := -_torso_follow_through * profile.head_stabilization_gain * (1.0 - _spotting_weight * 0.78)
	_head_stabilization = _damp_vector(_head_stabilization, head_target, profile.head_stabilization_response, delta)

	var compact_arm_scale := lerpf(1.0, 0.48, maxf(_spin_compactness, _grab_compactness * 0.65))
	var common_arm_target := Vector3(
		-_filtered_vertical_accel * profile.arm_vertical_accel_gain,
		-_filtered_yaw_accel * profile.arm_yaw_accel_gain,
		-_filtered_lateral_accel * profile.arm_lateral_accel_gain
	) * compact_arm_scale * _secondary_motion_weight
	var left_arm_target := common_arm_target + Vector3(0.0, 0.0, (_pelvis_carve - _arm_carve) * profile.torso_carve_lag_gain * 0.32)
	var right_arm_target := common_arm_target + Vector3(0.0, 0.0, (_pelvis_carve - _arm_carve) * profile.torso_carve_lag_gain * 0.24)
	if _grab_definition != null:
		var grab_constraint := maxf(_grab_pose_weight * 0.9, _grab_contact_weight)
		if _grab_definition.hand == GrabDefinition.Hand.LEFT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
			left_arm_target *= 1.0 - grab_constraint * 0.95
		if _grab_definition.hand == GrabDefinition.Hand.RIGHT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
			right_arm_target *= 1.0 - grab_constraint * 0.95
	left_arm_target = _limit_vector_components(left_arm_target, profile.arm_inertia_limit)
	right_arm_target = _limit_vector_components(right_arm_target, profile.arm_inertia_limit)
	_left_arm_inertia = _damp_vector(_left_arm_inertia, left_arm_target, profile.arm_inertia_response, delta)
	_right_arm_inertia = _damp_vector(_right_arm_inertia, right_arm_target, profile.arm_inertia_response, delta)

	var pole_tightness := lerpf(1.0, 0.58, _spin_compactness)
	var left_pole_target := Vector3(
		-_filtered_left_hand_accel.z * profile.pole_hand_accel_gain,
		-_filtered_yaw_accel * profile.pole_yaw_accel_gain,
		_filtered_left_hand_accel.x * profile.pole_hand_accel_gain
	) * pole_tightness * _secondary_motion_weight - _left_arm_inertia * 0.28
	var right_pole_target := Vector3(
		-_filtered_right_hand_accel.z * profile.pole_hand_accel_gain,
		-_filtered_yaw_accel * profile.pole_yaw_accel_gain,
		_filtered_right_hand_accel.x * profile.pole_hand_accel_gain
	) * pole_tightness * _secondary_motion_weight - _right_arm_inertia * 0.28
	left_pole_target = _limit_vector_components(left_pole_target, profile.pole_inertia_limit)
	right_pole_target = _limit_vector_components(right_pole_target, profile.pole_inertia_limit)
	var pole_response := profile.pole_inertia_response if left_pole_target.length_squared() + right_pole_target.length_squared() > 0.0002 else profile.pole_release_response
	_left_pole_inertia = _damp_vector(_left_pole_inertia, left_pole_target, pole_response, delta)
	_right_pole_inertia = _damp_vector(_right_pole_inertia, right_pole_target, pole_response, delta)

	var rebound_target := clampf(
		(-_compression_velocity * profile.leg_rebound_gain
			- _landing_compression_velocity * profile.landing_rebound_gain) * _secondary_motion_weight,
		-profile.leg_rebound_limit,
		profile.leg_rebound_limit
	)
	_leg_rebound = _damp(_leg_rebound, rebound_target, profile.leg_rebound_response, delta)

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
		_air_flex = _damp(_air_flex, 0.0, profile.air_phase_response, delta)
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
	_spin_cycle = fposmod(absf(frame.rotation_accumulated.y), TAU) / TAU
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
		rate_demand * _trick_pose_weight * (1.0 - _spin_open_weight * 0.78),
		profile.trick_pose_response,
		delta
	)
	var spot_target := 0.0
	if meaningful_rotation and frame.locomotion_state == STATE_AIR:
		var yaw_progress := smoothstep(deg_to_rad(40.0), deg_to_rad(120.0), absf(frame.rotation_accumulated.y))
		var half_turn_alignment := 1.0 - smoothstep(deg_to_rad(12.0), deg_to_rad(58.0), absf(frame.rotation_residual.y))
		spot_target = clampf(
			0.08 + yaw_progress * half_turn_alignment * 0.62 + _landing_alignment * 0.72,
			0.0,
			1.0
		)
	_spotting_weight = _damp(_spotting_weight, spot_target, profile.trick_pose_response, delta)
	var opening_target := 0.0
	if frame.locomotion_state == STATE_AIR:
		if frame.trick_phase == TrickCommand.PresentationPhase.OPEN:
			opening_target = 1.0
		elif _landing_anticipation > 0.0:
			var residual_ready := 1.0 - smoothstep(deg_to_rad(20.0), deg_to_rad(72.0), absf(frame.rotation_residual.y))
			opening_target = _landing_anticipation * lerpf(0.45, 1.0, residual_ready)
	_spin_open_weight = _damp(_spin_open_weight, opening_target, profile.trick_pose_response, delta)
	if _prewind_weight > 0.08:
		_spin_visual_phase_name = "SETUP"
	elif _spin_open_weight > 0.28:
		_spin_visual_phase_name = "OPEN"
	elif _spotting_weight > 0.42:
		_spin_visual_phase_name = "SPOT"
	elif _trick_pose_weight > 0.08:
		_spin_visual_phase_name = "COMPACT"
	else:
		_spin_visual_phase_name = "IDLE"

func _cache_grab_definitions() -> void:
	_grab_definitions_by_pose.clear()
	if grab_library == null:
		return
	for definition: Resource in grab_library.definitions:
		if definition != null and definition.pose_id != TrickController.GrabPose.NONE:
			_grab_definitions_by_pose[definition.pose_id] = definition

func _cache_style_definitions() -> void:
	_style_definitions_by_pose.clear()
	if style_library == null:
		return
	for definition: Resource in style_library.definitions:
		if definition != null and definition.pose_id != TrickController.StylePose.NONE:
			_style_definitions_by_pose[definition.pose_id] = definition

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
	if _grab_definition == null or input_strength <= 0.0 or not airborne:
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

func _update_style_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var live_pose := frame.style_pose
	var live_definition := _style_definitions_by_pose.get(live_pose) as Resource
	var legacy_strength := 1.0 if live_pose != TrickController.StylePose.NONE and frame.style_amount <= 0.0 else 0.0
	var input_strength := clampf(maxf(frame.style_amount, legacy_strength), 0.0, 1.0)
	if live_pose != TrickController.StylePose.NONE and live_pose != _style_pose_id:
		_style_pose_id = live_pose
		_style_definition = live_definition
	elif live_pose != TrickController.StylePose.NONE and _style_definition == null:
		_style_definition = live_definition
	if frame.locomotion_state != STATE_AIR or live_pose == TrickController.StylePose.NONE:
		input_strength = 0.0
	var rise_scale := float(_style_definition.pose_response_scale) if _style_definition != null else 1.0
	var release_scale := float(_style_definition.release_response_scale) if _style_definition != null else 1.0
	var response := profile.style_pose_response * (rise_scale if input_strength > _style_pose_weight else release_scale)
	_style_pose_weight = _damp(_style_pose_weight, input_strength, response, delta)
	if _style_definition == null or _style_pose_weight < 0.01:
		_style_phase_name = "IDLE"
	elif input_strength > 0.0:
		_style_phase_name = "HOLD" if _style_pose_weight > 0.72 else "SETUP"
	else:
		_style_phase_name = "RELEASE"
	if live_pose == TrickController.StylePose.NONE and _style_pose_weight < 0.01:
		_style_pose_id = TrickController.StylePose.NONE
		_style_definition = null

func _score_landing_error(error: float, good: float, bad: float) -> float:
	if not is_finite(error) or not is_finite(good) or not is_finite(bad):
		return 0.0
	var good_limit := maxf(good, 0.0)
	var bad_limit := maxf(bad, good_limit + 0.001)
	return 1.0 - smoothstep(good_limit, bad_limit, absf(error))

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _landing_readiness_targets(frame: SkierAnimationFrame) -> Dictionary:
	var empty := {
		"valid": false,
		"inputs_valid": false,
		"heading": 0.0,
		"pitch": 0.0,
		"spin": 0.0,
		"upright": 0.0,
		"residual": 0.0,
		"projected_heading_error": 0.0,
		"projected_residual": 0.0,
	}
	if frame.locomotion_state != STATE_AIR or not frame.predicted_landing_valid or not is_finite(frame.predicted_landing_time) or frame.predicted_landing_time < 0.0:
		return empty
	var landing_normal := frame.predicted_landing_normal
	if not _finite_vector(landing_normal) or landing_normal.length_squared() <= 0.000001:
		return empty
	landing_normal = landing_normal.normalized()
	var time_to_contact := clampf(frame.predicted_landing_time, 0.0, 2.0)
	var body_up_valid := frame.body_up_valid and _finite_vector(frame.body_up) and frame.body_up.length_squared() > 0.000001
	var ski_forward_valid := frame.ski_forward_valid and _finite_vector(frame.ski_forward) and frame.ski_forward.length_squared() > 0.000001
	var ski_up_valid := frame.ski_up_valid and _finite_vector(frame.ski_up) and frame.ski_up.length_squared() > 0.000001
	var desired_heading_valid := _finite_vector(frame.velocity_heading) and frame.velocity_heading.length_squared() > 0.000001
	var local_angular_valid := _finite_vector(frame.angular_velocity)
	var world_angular_valid := frame.angular_velocity_world_valid and _finite_vector(frame.angular_velocity_world)
	var residual_valid := _finite_vector(frame.rotation_residual)
	var heading_valid := ski_forward_valid and desired_heading_valid and world_angular_valid
	var pitch_valid := ski_forward_valid and ski_up_valid
	var upright_valid := body_up_valid
	var spin_valid := local_angular_valid
	var maneuver_residual_valid := local_angular_valid and residual_valid
	var ski_forward := frame.ski_forward.normalized() if ski_forward_valid else Vector3.FORWARD
	var body_up := frame.body_up.normalized() if body_up_valid else Vector3.UP
	var heading := ski_forward.slide(landing_normal)
	var desired_heading := frame.velocity_heading.slide(landing_normal)
	var heading_error := 0.0
	if heading_valid and heading.length_squared() > 0.000001 and desired_heading.length_squared() > 0.000001:
		heading_error = heading.normalized().signed_angle_to(desired_heading.normalized(), landing_normal)
	else:
		heading_valid = false
	var projected_heading_error := 0.0
	if heading_valid and is_finite(heading_error):
		var yaw_rate_about_landing := frame.angular_velocity_world.dot(landing_normal)
		projected_heading_error = wrapf(heading_error + yaw_rate_about_landing * time_to_contact, -PI, PI)
	else:
		heading_valid = false
	var pitch_error := 0.0
	if pitch_valid:
		var ski_forward_plane := ski_forward.slide(landing_normal)
		if ski_forward_plane.length_squared() > 0.000001:
			pitch_error = absf(atan2(ski_forward.dot(landing_normal), ski_forward_plane.length()))
		else:
			pitch_valid = false
	var spin_error := frame.angular_velocity.length() if spin_valid else NAN
	var upright_error := acos(clampf(body_up.dot(landing_normal), -1.0, 1.0)) if upright_valid else NAN
	var projected_residual := 0.0
	if maneuver_residual_valid:
		var projected_residual_vector := Vector3(
			wrapf(frame.rotation_residual.x + frame.angular_velocity.x * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.y + frame.angular_velocity.y * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.z + frame.angular_velocity.z * time_to_contact, -PI, PI)
		)
		if _finite_vector(projected_residual_vector):
			projected_residual = maxf(
				absf(projected_residual_vector.x),
				maxf(absf(projected_residual_vector.y), absf(projected_residual_vector.z))
			)
		else:
			maneuver_residual_valid = false
	var inputs_valid := heading_valid and pitch_valid and spin_valid and upright_valid and maneuver_residual_valid
	return {
		"valid": true,
		"inputs_valid": inputs_valid,
		"heading": _score_landing_error(projected_heading_error, profile.landing_readiness_heading_good, profile.landing_readiness_heading_bad) if heading_valid else 0.0,
		"pitch": _score_landing_error(pitch_error, profile.landing_readiness_pitch_good, profile.landing_readiness_pitch_bad) if pitch_valid else 0.0,
		"spin": _score_landing_error(spin_error, profile.landing_readiness_spin_good, profile.landing_readiness_spin_bad) if spin_valid else 0.0,
		"upright": _score_landing_error(upright_error, profile.landing_readiness_upright_good, profile.landing_readiness_upright_bad) if upright_valid else 0.0,
		"residual": _score_landing_error(projected_residual, profile.landing_readiness_residual_good, profile.landing_readiness_residual_bad) if maneuver_residual_valid else 0.0,
		"projected_heading_error": projected_heading_error,
		"projected_residual": projected_residual,
	}

func _update_landing_readiness(frame: SkierAnimationFrame, delta: float) -> void:
	var targets := _landing_readiness_targets(frame)
	var valid := bool(targets.valid)
	_landing_readiness_valid = valid and bool(targets.inputs_valid)
	var time_to_contact := frame.predicted_landing_time if valid else -1.0
	var urgency := 1.0 - clampf(time_to_contact / maxf(profile.landing_readiness_near_contact_window, 0.01), 0.0, 1.0) if valid else 0.0
	var rise_response := lerpf(profile.landing_readiness_rise_response, profile.landing_readiness_near_contact_response, urgency)
	var fall_response := lerpf(profile.landing_readiness_fall_response, profile.landing_readiness_near_contact_response, urgency)
	_landing_readiness_heading = _damp(_landing_readiness_heading, float(targets.heading), _landing_readiness_response(_landing_readiness_heading, float(targets.heading), rise_response, fall_response), delta)
	_landing_readiness_pitch = _damp(_landing_readiness_pitch, float(targets.pitch), _landing_readiness_response(_landing_readiness_pitch, float(targets.pitch), rise_response, fall_response), delta)
	_landing_readiness_spin = _damp(_landing_readiness_spin, float(targets.spin), _landing_readiness_response(_landing_readiness_spin, float(targets.spin), rise_response, fall_response), delta)
	_landing_readiness_upright = _damp(_landing_readiness_upright, float(targets.upright), _landing_readiness_response(_landing_readiness_upright, float(targets.upright), rise_response, fall_response), delta)
	_landing_readiness_residual = _damp(_landing_readiness_residual, float(targets.residual), _landing_readiness_response(_landing_readiness_residual, float(targets.residual), rise_response, fall_response), delta)
	var weighted_total := (
		_landing_readiness_heading * profile.landing_readiness_heading_weight
		+ _landing_readiness_pitch * profile.landing_readiness_pitch_weight
		+ _landing_readiness_spin * profile.landing_readiness_spin_weight
		+ _landing_readiness_upright * profile.landing_readiness_upright_weight
		+ _landing_readiness_residual * profile.landing_readiness_residual_weight
	)
	var weight_total := (
		profile.landing_readiness_heading_weight
		+ profile.landing_readiness_pitch_weight
		+ profile.landing_readiness_spin_weight
		+ profile.landing_readiness_upright_weight
		+ profile.landing_readiness_residual_weight
	)
	_landing_readiness = clampf(weighted_total / maxf(weight_total, 0.001), 0.0, 1.0)
	if not _landing_readiness_valid:
		_landing_readiness = 0.0
	_landing_projected_heading_error = float(targets.projected_heading_error) if valid else 0.0
	_landing_projected_residual = float(targets.projected_residual) if valid else 0.0
	_landing_ready = _landing_ready_for_values(_landing_readiness_valid, _landing_anticipation, _landing_readiness)

func _landing_readiness_response(current: float, target: float, rise_response: float, fall_response: float) -> float:
	return rise_response if target > current else fall_response

func _landing_ready_for_values(valid: bool, anticipation: float, readiness: float) -> bool:
	return valid and anticipation >= profile.ready_anticipation_threshold and readiness >= profile.ready_readiness_threshold

func _update_landing_animation(frame: SkierAnimationFrame, delta: float) -> void:
	var alignment_target := 0.0
	var readiness_target := 0.0
	if frame.locomotion_state == STATE_AIR and frame.predicted_landing_time >= 0.0:
		var alignment_start := maxf(profile.landing_alignment_start, 0.05)
		var readiness_start := maxf(profile.landing_readiness_start, 0.05)
		if frame.predicted_landing_time <= alignment_start:
			alignment_target = 1.0 - smoothstep(0.0, alignment_start, frame.predicted_landing_time)
			alignment_target *= lerpf(0.7, 1.0, _air_size)
		if frame.predicted_landing_time <= readiness_start:
			readiness_target = 1.0 - smoothstep(0.0, readiness_start, frame.predicted_landing_time)
			readiness_target *= lerpf(0.55, 1.0, _air_size)
	_landing_alignment = _damp(_landing_alignment, alignment_target, profile.landing_anticipation_response, delta)
	_landing_anticipation = _damp(_landing_anticipation, readiness_target, profile.landing_anticipation_response, delta)
	_update_landing_readiness(frame, delta)

	if frame.predicted_landing_valid and _landing_alignment > 0.02:
		var local_normal := _terrain_normal_local(frame.predicted_landing_normal)
		var pitch_target := clampf(atan2(local_normal.z, maxf(local_normal.y, 0.001)), -profile.landing_ski_align_pitch, profile.landing_ski_align_pitch)
		var travel := frame.velocity_heading
		var heading := frame.skier_heading
		var yaw_target := 0.0
		if _finite_vector(travel) and _finite_vector(heading) and travel.length_squared() > 0.001 and heading.length_squared() > 0.001:
			var planar_travel := Vector3(travel.x, 0.0, travel.z)
			var planar_heading := Vector3(heading.x, 0.0, heading.z)
			if _finite_vector(planar_travel) and _finite_vector(planar_heading) and planar_travel.length_squared() > 0.001 and planar_heading.length_squared() > 0.001:
				yaw_target = clampf(planar_heading.normalized().signed_angle_to(planar_travel.normalized(), Vector3.UP), -profile.landing_ski_align_yaw, profile.landing_ski_align_yaw)
		_landing_ski_yaw = _damp(_landing_ski_yaw, yaw_target * _landing_alignment, profile.landing_anticipation_response, delta)
		_landing_ski_pitch = _damp(_landing_ski_pitch, pitch_target * _landing_alignment, profile.landing_anticipation_response, delta)
		_landing_torso_prepare = _damp(_landing_torso_prepare, _landing_alignment, profile.landing_anticipation_response, delta)
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
		_landing_phase_name = "Readiness" if _landing_anticipation > 0.12 else ("Alignment" if _landing_alignment > 0.08 else "Idle")
	if _stomp_active:
		_stomp_time += delta
		var duration := maxf(profile.stomp_duration, 0.12)
		var rise := smoothstep(0.04, minf(0.14, duration * 0.42), _stomp_time)
		var fall := 1.0 - smoothstep(duration * 0.62, duration, _stomp_time)
		_stomp_weight = rise * fall
		if _stomp_time >= duration:
			_stomp_active = false
			_stomp_candidate = false
			_stomp_weight = 0.0
	else:
		_stomp_weight = _damp(_stomp_weight, 0.0, profile.landing_recovery_response_soft, delta)

func _begin_landing_impact(event: int, severity: float, side: float) -> void:
	_landing_active = true
	_landing_compressing = true
	_landing_outcome = event
	_stomp_candidate = event == AnimationEvent.LAND_CLEAN
	_stomp_active = false
	_stomp_time = 0.0
	_stomp_weight = 0.0
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
	if _stomp_candidate and not _stomp_active and frame.landing_air_time >= profile.stomp_min_air_time:
		_stomp_active = true
		_stomp_time = 0.0
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
	_landing_readiness_valid = false
	_landing_ready = false
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
	var alignment := _landing_alignment
	var anticipation := _landing_anticipation
	var readiness := _landing_readiness
	var compression := _landing_compression
	if alignment <= 0.01 and anticipation <= 0.01 and compression <= 0.01 and _landing_wobble_amount <= 0.01:
		return
	if alignment > 0.01 and frame.locomotion_state == STATE_AIR:
		_current_pose_name = "Air Descent / Landing Readiness" if anticipation > 0.12 else "Air Descent / Landing Alignment"
		var correction_strength := clampf(
			anticipation * (1.0 - readiness) * profile.landing_corrective_pose_gain if _landing_readiness_valid else 0.0,
			0.0,
			1.0
		)
		var correction_side := signf(_landing_projected_heading_error)
		if absf(correction_side) < 0.05:
			correction_side = signf(frame.rotation_residual.y)
		if absf(correction_side) < 0.05:
			correction_side = signf(_smoothed_angular_velocity.y)
		if absf(correction_side) < 0.05:
			correction_side = 1.0
		var heading_correction := clampf(_landing_projected_heading_error, -0.6, 0.6) * correction_strength
		var extend := anticipation * profile.landing_anticipation_leg_extend
		_add_rotation(left_hip, Vector3(extend * 0.55, 0.0, -0.04 * anticipation))
		_add_rotation(right_hip, Vector3(extend * 0.55, 0.0, 0.04 * anticipation))
		_add_rotation(left_knee, Vector3(-extend * 1.15, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(-extend * 1.15, 0.0, 0.0))
		_add_rotation(left_boot, Vector3(-anticipation * 0.06, 0.0, 0.0))
		_add_rotation(right_boot, Vector3(-anticipation * 0.06, 0.0, 0.0))
		_add_rotation(left_ski, Vector3(_landing_ski_pitch, _landing_ski_yaw * 0.5, -0.025 * anticipation))
		_add_rotation(right_ski, Vector3(_landing_ski_pitch, _landing_ski_yaw * 0.5, 0.025 * anticipation))
		_add_rotation(spine, Vector3(-_landing_torso_prepare * profile.landing_anticipation_torso_pitch, _landing_ski_yaw * 0.35 + heading_correction * 0.18, -correction_side * correction_strength * 0.08))
		_add_rotation(chest, Vector3(-_landing_torso_prepare * profile.landing_anticipation_torso_pitch * 0.65, _landing_ski_yaw * 0.45 + heading_correction * 0.28, correction_side * correction_strength * 0.05))
		_add_rotation(head, Vector3(alignment * profile.landing_anticipation_head_pitch, _landing_ski_yaw * 0.55, 0.0))
		_add_rotation(left_shoulder, Vector3(0.08 * anticipation, -correction_side * correction_strength * 0.05, -profile.landing_anticipation_arm_open * anticipation - correction_side * correction_strength * 0.12))
		_add_rotation(right_shoulder, Vector3(0.08 * anticipation, -correction_side * correction_strength * 0.05, profile.landing_anticipation_arm_open * anticipation + correction_side * correction_strength * 0.12))
		_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(correction_side * correction_strength * 0.035, anticipation * 0.03, 0.0)
	if compression > 0.01 or _landing_wobble_amount > 0.01:
		var depth := compression
		var left_support_headroom := 1.0 - clampf(maxf(_left_terrain_flex, 0.0) / maxf(profile.max_leg_flex, 0.01), 0.0, 0.35)
		var right_support_headroom := 1.0 - clampf(maxf(_right_terrain_flex, 0.0) / maxf(profile.max_leg_flex, 0.01), 0.0, 0.35)
		var left_depth := clampf((depth + _landing_left_asymmetry * depth) * left_support_headroom, 0.0, 1.35)
		var right_depth := clampf((depth + _landing_right_asymmetry * depth) * right_support_headroom, 0.0, 1.35)
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

func _apply_stomp_layer(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state != STATE_GROUND or _stomp_weight <= 0.005:
		return
	var amount := _stomp_weight * profile.stomp_stack_strength
	_current_pose_name = "Clean Stomp"
	_add_rotation(left_hip, Vector3(0.16 * amount, 0.0, -0.035 * amount))
	_add_rotation(right_hip, Vector3(0.16 * amount, 0.0, 0.035 * amount))
	_add_rotation(left_knee, Vector3(-0.32 * amount, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(-0.32 * amount, 0.0, 0.0))
	_add_rotation(left_boot, Vector3(-0.06 * amount, 0.0, 0.0))
	_add_rotation(right_boot, Vector3(-0.06 * amount, 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.02 * amount, -_landing_ski_yaw * 0.7 * amount, 0.0))
	_add_rotation(right_ski, Vector3(0.02 * amount, -_landing_ski_yaw * 0.7 * amount, 0.0))
	_add_rotation(pelvis, Vector3(-0.04 * amount, 0.0, 0.0))
	_add_rotation(spine, Vector3(0.08 * amount, 0.0, 0.0))
	_add_rotation(chest, Vector3(0.1 * amount, 0.0, 0.0))
	_add_rotation(head, Vector3(-0.06 * amount, 0.0, 0.0))
	_add_rotation(left_shoulder, Vector3(0.24 * amount, 0.0, -0.18 * amount))
	_add_rotation(right_shoulder, Vector3(0.24 * amount, 0.0, 0.18 * amount))
	_add_rotation(left_elbow, Vector3(0.36 * amount, 0.0, 0.0))
	_add_rotation(right_elbow, Vector3(0.36 * amount, 0.0, 0.0))
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(0.0, 0.08 * amount, -0.025 * amount)
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

func _damp_vector(current: Vector3, target: Vector3, response: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-maxf(response, 0.01) * delta))

func _limit_vector(value: Vector3, maximum_length: float) -> Vector3:
	var limit := maxf(maximum_length, 0.001)
	if value.length_squared() <= limit * limit:
		return value
	return value.normalized() * limit

func _limit_vector_components(value: Vector3, limit: float) -> Vector3:
	var safe_limit := maxf(limit, 0.001)
	return Vector3(
		clampf(value.x, -safe_limit, safe_limit),
		clampf(value.y, -safe_limit, safe_limit),
		clampf(value.z, -safe_limit, safe_limit)
	)

func _crossover_release() -> float:
	if _crossover_time <= 0.0 or profile.crossover_duration <= 0.0:
		return 0.0
	var progress := 1.0 - _crossover_time / profile.crossover_duration
	return sin(clampf(progress, 0.0, 1.0) * PI)

func _reset_targets() -> void:
	_rotation_targets.clear()
	_position_targets.clear()
	_rotation_targets[balance_root] = Vector3.ZERO
	_rotation_targets[pelvis] = Vector3.ZERO
	_rotation_targets[spine] = Vector3.ZERO
	_rotation_targets[chest] = Vector3.ZERO
	_rotation_targets[head] = Vector3.ZERO
	_rotation_targets[left_hip] = Vector3.ZERO
	_rotation_targets[right_hip] = Vector3.ZERO
	_rotation_targets[left_knee] = Vector3.ZERO
	_rotation_targets[right_knee] = Vector3.ZERO
	_rotation_targets[left_boot] = Vector3.ZERO
	_rotation_targets[right_boot] = Vector3.ZERO
	_rotation_targets[left_ski] = Vector3.ZERO
	_rotation_targets[right_ski] = Vector3.ZERO
	_rotation_targets[left_shoulder] = Vector3.ZERO
	_rotation_targets[right_shoulder] = Vector3.ZERO
	_rotation_targets[left_elbow] = Vector3.ZERO
	_rotation_targets[right_elbow] = Vector3.ZERO
	_rotation_targets[left_hand] = Vector3.ZERO
	_rotation_targets[right_hand] = Vector3.ZERO
	_rotation_targets[left_pole] = Vector3.ZERO
	_rotation_targets[right_pole] = Vector3.ZERO
	_position_targets[pelvis] = Vector3(0.0, 0.96, 0.0)
	_position_targets[chest] = Vector3(0.0, 0.42, 0.0)
	_position_targets[left_hip] = Vector3(-0.27, -0.04, 0.0)
	_position_targets[right_hip] = Vector3(0.27, -0.04, 0.0)
	_position_targets[left_shoulder] = Vector3(-0.4, 0.24, 0.0)
	_position_targets[right_shoulder] = Vector3(0.4, 0.24, 0.0)

func _apply_ground_pose(frame: SkierAnimationFrame) -> void:
	var speed_flex := profile.speed_knee_flex * _crouch_amount
	var jump_flex := _jump_anticipation * profile.jump_anticipation_knee_flex
	var crossover_release := _crossover_release()
	var flex := maxf(0.2, profile.neutral_knee_flex + speed_flex + jump_flex + _slarve_weight * profile.slarve_leg_flex - crossover_release * profile.crossover_extension)
	var deep_carve := smoothstep(profile.deep_carve_threshold, 1.0, absf(_carve_target))
	var leg_load := smoothstep(profile.carve_leg_load_start, profile.carve_leg_load_full, absf(_leg_carve))
	var pelvis_roll := -_pelvis_carve * profile.carve_hip_roll + _terrain_pelvis_roll_amount
	var skid_side := signf(frame.skid) if absf(frame.skid) > 0.05 else signf(frame.edge)
	var load := absf(_pelvis_carve)
	var asymmetry := profile.stance_asymmetry
	_current_blend = _pelvis_carve
	_current_pose_name = "Ground Neutral"

	_add_rotation(balance_root, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll * profile.carve_root_roll_share))
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
		-_torso_carve * profile.chest_counter_yaw - _filtered_heading_delta * profile.chest_travel_alignment,
		_torso_carve * profile.carve_chest_roll - _terrain_pelvis_roll_amount * 0.22
	))
	_add_rotation(head, Vector3(
		profile.neutral_torso_pitch * 0.62 + _crouch_amount * profile.speed_torso_pitch * 0.72 + frame.tuck * 0.24,
		_torso_carve * profile.chest_counter_yaw * 0.45 + _filtered_heading_delta * profile.chest_travel_alignment * 0.72,
		_torso_carve * profile.carve_head_level - _terrain_pelvis_roll_amount * 0.16
	))
	_apply_leg_flex(flex, _leg_carve, leg_load, _left_terrain_flex, _right_terrain_flex)
	_add_rotation(left_boot, Vector3(-_jump_anticipation * profile.jump_anticipation_ankle_flex, 0.0, 0.0))
	_add_rotation(right_boot, Vector3(-_jump_anticipation * profile.jump_anticipation_ankle_flex, 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll))
	_add_rotation(right_ski, Vector3(0.0, 0.0, -_ski_carve * profile.carve_ski_roll))
	_apply_terrain_foot_orientation()
	_position_targets[pelvis] = Vector3(
		_pelvis_carve * profile.carve_pelvis_shift,
		0.96 - profile.neutral_pelvis_drop - flex * profile.pelvis_flex_depth - _jump_anticipation * profile.jump_anticipation_pelvis_drop - load * profile.carve_pelvis_drop + crossover_release * profile.crossover_extension * 0.36 + _terrain_pelvis_offset,
		profile.neutral_pelvis_offset
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

	if _slarve_weight > 0.02 and not frame.braking:
		_current_pose_name = "Slarve %s" % ("Left" if _slarve_side < 0.0 else "Right")
		var slarve_yaw := _slarve_side * _slarve_weight
		_add_rotation(left_ski, Vector3(0.02 * _slarve_weight, slarve_yaw * profile.slarve_ski_yaw, -slarve_yaw * 0.08))
		_add_rotation(right_ski, Vector3(-0.02 * _slarve_weight, slarve_yaw * profile.slarve_ski_yaw, -slarve_yaw * 0.08))
		_add_rotation(pelvis, Vector3(-0.08 * _slarve_weight, -slarve_yaw * profile.slarve_pelvis_yaw, -slarve_yaw * 0.1))
		_add_rotation(spine, Vector3(0.03 * _slarve_weight, slarve_yaw * profile.slarve_chest_counter_yaw * 0.45, slarve_yaw * 0.08))
		_add_rotation(chest, Vector3(0.05 * _slarve_weight, slarve_yaw * profile.slarve_chest_counter_yaw, slarve_yaw * 0.1))
		_add_rotation(left_shoulder, Vector3(-0.12 * _slarve_weight, 0.0, -profile.slarve_arm_open * _slarve_weight))
		_add_rotation(right_shoulder, Vector3(-0.12 * _slarve_weight, 0.0, profile.slarve_arm_open * _slarve_weight))
		_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(-slarve_yaw * 0.07, -_slarve_weight * 0.035, 0.025 * _slarve_weight)

	if frame.braking:
		_current_pose_name = "Hockey Stop %s" % ("Left" if skid_side < 0.0 else "Right")
		var brake_yaw := skid_side * profile.brake_ski_yaw
		_add_rotation(pelvis, Vector3(0.05, -brake_yaw * 0.58, -skid_side * 0.24))
		_add_rotation(spine, Vector3(-0.04, brake_yaw * 0.34, skid_side * 0.14))
		_add_rotation(chest, Vector3(-0.08, brake_yaw * 0.72, skid_side * 0.2))
		_add_rotation(left_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(right_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(left_hip, Vector3(-0.18 - skid_side * 0.12, 0.0, -skid_side * 0.12))
		_add_rotation(right_hip, Vector3(-0.18 + skid_side * 0.12, 0.0, -skid_side * 0.12))
		_add_rotation(left_knee, Vector3(0.34 + skid_side * 0.18, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(0.34 - skid_side * 0.18, 0.0, 0.0))
		_add_rotation(left_shoulder, Vector3(-0.5, -brake_yaw * 0.36, -0.48))
		_add_rotation(right_shoulder, Vector3(-0.5, -brake_yaw * 0.36, 0.48))
		_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(-skid_side * 0.24, -0.1, 0.1)

	if frame.switch_stance:
		_apply_switch_skiing_layer()

	if _jump_anticipation > 0.08:
		_current_pose_name = "Jump Anticipation"

func _apply_switch_skiing_layer() -> void:
	var side := _last_loaded_direction if absf(_last_loaded_direction) > 0.05 else 1.0
	_current_pose_name += " / Switch"
	_add_rotation(left_hip, Vector3(-profile.switch_leg_lead * (0.62 + side * 0.38), side * 0.05, -side * 0.05))
	_add_rotation(right_hip, Vector3(-profile.switch_leg_lead * (0.62 - side * 0.38), side * 0.05, -side * 0.05))
	_add_rotation(left_knee, Vector3(profile.switch_leg_lead * (1.0 + side * 0.48), 0.0, 0.0))
	_add_rotation(right_knee, Vector3(profile.switch_leg_lead * (1.0 - side * 0.48), 0.0, 0.0))
	_add_rotation(left_ski, Vector3(side * 0.04, 0.0, -side * 0.05))
	_add_rotation(right_ski, Vector3(-side * 0.04, 0.0, side * 0.05))
	_add_rotation(pelvis, Vector3(-0.04, side * profile.switch_pelvis_yaw, side * 0.04))
	_add_rotation(spine, Vector3(-0.04, -side * profile.switch_chest_yaw * 0.45, -side * 0.05))
	_add_rotation(chest, Vector3(0.02, -side * profile.switch_chest_yaw, -side * 0.06))
	_add_rotation(head, Vector3(0.02, -side * profile.switch_head_spot, side * 0.03))
	_add_rotation(left_shoulder, Vector3(-side * profile.switch_arm_asymmetry * 0.45, side * 0.06, -side * profile.switch_arm_asymmetry))
	_add_rotation(right_shoulder, Vector3(side * profile.switch_arm_asymmetry * 0.35, side * 0.06, -side * profile.switch_arm_asymmetry * 0.55))
	_add_rotation(left_pole, Vector3(-0.14, -side * profile.switch_pole_split, side * 0.12))
	_add_rotation(right_pole, Vector3(-0.28, side * profile.switch_pole_split * 0.55, -side * 0.08))
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(side * 0.22, -0.075, 0.09)

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
	var silhouette_side := _yaw_direction(frame) if _trick_pose_weight > 0.01 else _air_style_side
	var style_phase := clampf(_air_early_weight * 0.75 + _air_apex_weight - _air_descent_weight * 0.35, -1.0, 1.0)
	var style_weight := 1.0 - rotation_compact * 0.92
	var leg_settle := silhouette_side * style_phase * profile.air_leg_asymmetry * style_weight
	_apply_leg_flex(_air_flex, 0.0, 0.0, _left_terrain_flex, _right_terrain_flex)
	_add_rotation(left_hip, Vector3(-leg_settle * 0.35, 0.0, -leg_settle))
	_add_rotation(right_hip, Vector3(leg_settle * 0.35, 0.0, -leg_settle))
	_add_rotation(left_knee, Vector3(leg_settle, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(-leg_settle, 0.0, 0.0))
	_apply_terrain_foot_orientation()
	var ski_pitch := profile.air_ski_pitch * (_air_early_weight * 0.3 + _air_apex_weight * 0.5 - _air_descent_weight * 0.35)
	_add_rotation(left_ski, Vector3(ski_pitch + leg_settle * profile.air_ski_scissor, 0.0, leg_settle * 0.06))
	_add_rotation(right_ski, Vector3(ski_pitch - leg_settle * profile.air_ski_scissor, 0.0, -leg_settle * 0.06))
	var deliberate_pop := 1.0 if frame.takeoff_type == SkierAnimationFrame.TakeoffType.CHARGED_POP else 0.35
	_position_targets[pelvis] = Vector3(
		silhouette_side * style_phase * profile.air_pelvis_side_offset * style_weight,
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
	_add_rotation(spine, Vector3(0.0, -silhouette_side * style_phase * 0.045 * style_weight, -silhouette_side * style_phase * profile.air_torso_counter_roll * style_weight))
	_add_rotation(chest, Vector3(0.0, silhouette_side * style_phase * 0.07 * style_weight, -silhouette_side * style_phase * profile.air_torso_counter_roll * 0.72 * style_weight))
	var arm_in := _air_size * phase_compact * 0.2 + rotation_compact * 0.28
	var arm_open := profile.air_arm_balance_open * (0.32 + _air_descent_weight * 0.68) * (1.0 - rotation_compact * 0.45)
	var takeoff_swing := _air_takeoff_weight * deliberate_pop * 0.2
	var asymmetry := profile.stance_asymmetry + leg_settle * 0.25
	_add_rotation(left_shoulder, Vector3(takeoff_swing - 0.18 - arm_in + asymmetry, 0.0, -arm_open - asymmetry))
	_add_rotation(right_shoulder, Vector3(takeoff_swing - 0.18 - arm_in - asymmetry, 0.0, arm_open - asymmetry))
	var arm_shape := silhouette_side * style_phase * profile.air_arm_asymmetry * style_weight
	_add_rotation(left_shoulder, Vector3(-arm_shape * 0.55, arm_shape * 0.25, -arm_shape))
	_add_rotation(right_shoulder, Vector3(arm_shape * 0.42, arm_shape * 0.2, -arm_shape * 0.48))
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
		var opening := _spin_open_weight
		if opening > 0.01:
			if _landing_anticipation < 0.08:
				_current_pose_name = "Open Style"
			else:
				_current_pose_name = "Landing Ready"
			var leg_opening := opening
			var arm_opening := opening
			var yaw_opening := opening if frame.trick_kind in [
				TrickCommand.Kind.SPIN_LEFT,
				TrickCommand.Kind.SPIN_RIGHT,
				TrickCommand.Kind.CORK_LEFT,
				TrickCommand.Kind.CORK_RIGHT,
			] else 0.0
			var yaw_open_side := _yaw_direction(frame)
			# Opening must read as a sequence rather than a uniformly rotating
			# mannequin: the upper body brakes first while the pelvis and skis
			# visibly finish the maneuver. These are rig-local offsets only.
			_add_rotation(pelvis, Vector3(0.0, yaw_open_side * profile.trick_open_pelvis_follow_yaw * yaw_opening, 0.0))
			_add_rotation(spine, Vector3(0.0, -yaw_open_side * profile.trick_open_spine_counter_yaw * yaw_opening, 0.0))
			_add_rotation(chest, Vector3(0.0, -yaw_open_side * profile.trick_open_chest_counter_yaw * yaw_opening, 0.0))
			_add_rotation(left_ski, Vector3(0.0, yaw_open_side * profile.trick_open_ski_follow_yaw * yaw_opening, 0.0))
			_add_rotation(right_ski, Vector3(0.0, yaw_open_side * profile.trick_open_ski_follow_yaw * yaw_opening, 0.0))
			_add_rotation(left_hip, Vector3(0.12 * leg_opening, 0.0, -0.035 * leg_opening))
			_add_rotation(right_hip, Vector3(0.12 * leg_opening, 0.0, 0.035 * leg_opening))
			_add_rotation(left_knee, Vector3(-profile.trick_spin_knee_flex * 0.68 * leg_opening, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-profile.trick_spin_knee_flex * 0.68 * leg_opening, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.08 * arm_opening, -yaw_open_side * profile.trick_open_chest_counter_yaw * 0.55 * yaw_opening, -profile.trick_landing_arm_open * arm_opening))
			_add_rotation(right_shoulder, Vector3(0.08 * arm_opening, -yaw_open_side * profile.trick_open_chest_counter_yaw * 0.45 * yaw_opening, profile.trick_landing_arm_open * arm_opening))

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
		if frame.trick_kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP]:
			_apply_flip_family_pose(frame, pitch_amount)
		else:
			_current_pose_name += " / %s" % ("Frontflip" if pitch_side > 0.0 else "Backflip")
			_add_rotation(pelvis, Vector3(-pitch_side * 0.14 * pitch_amount, 0.0, 0.0))
			_add_rotation(spine, Vector3(-pitch_side * 0.18 * pitch_amount, 0.0, 0.0))
			_add_rotation(chest, Vector3(-pitch_side * 0.1 * pitch_amount, 0.0, 0.0))
			_add_rotation(head, Vector3(pitch_side * 0.08 * pitch_amount, 0.0, 0.0))

	if roll_amount > 0.01:
		if frame.trick_kind not in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
			_current_pose_name += " / Cork"
		_add_rotation(pelvis, Vector3(-0.08 * roll_amount, 0.0, roll_side * 0.14 * roll_amount))
		_add_rotation(spine, Vector3(-0.1 * roll_amount, 0.0, -roll_side * 0.18 * roll_amount))
		_add_rotation(chest, Vector3(-0.04 * roll_amount, 0.0, -roll_side * 0.16 * roll_amount))
		_add_rotation(head, Vector3(0.05 * roll_amount, 0.0, roll_side * 0.07 * roll_amount))
	if frame.trick_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		_apply_cork_family_pose(yaw_side, maxf(yaw_amount, roll_amount))

	var compact := _spin_compactness
	if compact > 0.01:
		var leg_asymmetry := yaw_side * profile.trick_leg_asymmetry * compact
		var cycle_angle := _spin_cycle * TAU
		var phase_sine := sin(cycle_angle) * yaw_side * compact
		var phase_cosine := cos(cycle_angle) * yaw_side * compact
		# The root owns actual rotation. This periodic local motif changes the
		# skier's silhouette at each quarter turn and repeats for higher spins.
		_add_rotation(left_hip, Vector3(0.0, 0.0, -leg_asymmetry))
		_add_rotation(right_hip, Vector3(0.0, 0.0, -leg_asymmetry))
		_add_rotation(left_hip, Vector3(-phase_cosine * profile.trick_spin_phase_leg_shape * 0.22, 0.0, -phase_sine * profile.trick_spin_phase_leg_shape * 0.42))
		_add_rotation(right_hip, Vector3(phase_cosine * profile.trick_spin_phase_leg_shape * 0.18, 0.0, -phase_sine * profile.trick_spin_phase_leg_shape * 0.3))
		_add_rotation(left_knee, Vector3(leg_asymmetry + phase_sine * profile.trick_spin_phase_leg_shape, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(-leg_asymmetry - phase_sine * profile.trick_spin_phase_leg_shape, 0.0, 0.0))
		_add_rotation(chest, Vector3(0.0, phase_cosine * profile.trick_spin_phase_torso_shape, -phase_sine * profile.trick_spin_phase_torso_shape * 0.72))
		_add_rotation(left_shoulder, Vector3(-phase_cosine * profile.trick_spin_phase_arm_shape, 0.0, -phase_sine * profile.trick_spin_phase_arm_shape * 0.82))
		_add_rotation(right_shoulder, Vector3(phase_cosine * profile.trick_spin_phase_arm_shape * 0.68, 0.0, -phase_sine * profile.trick_spin_phase_arm_shape * 0.46))
		_add_rotation(left_ski, Vector3(phase_sine * profile.trick_spin_phase_ski_shape, 0.0, phase_cosine * profile.trick_spin_phase_ski_shape * 0.7))
		_add_rotation(right_ski, Vector3(-phase_sine * profile.trick_spin_phase_ski_shape, 0.0, -phase_cosine * profile.trick_spin_phase_ski_shape * 0.7))
		_position_targets[pelvis] += Vector3(
			phase_sine * profile.trick_spin_phase_pelvis_shift,
			-profile.trick_spin_pelvis_drop * compact,
			phase_cosine * profile.trick_spin_phase_pelvis_shift * 0.42
		)

func _apply_flip_family_pose(frame: SkierAnimationFrame, amount: float) -> void:
	var cycle := fposmod(absf(frame.rotation_accumulated.x), TAU) / TAU
	var inversion := sin(cycle * PI)
	if frame.trick_kind == TrickCommand.Kind.FRONTFLIP:
		_current_pose_name = "Frontflip"
		var fold := amount * lerpf(0.7, 1.0, inversion)
		_add_rotation(pelvis, Vector3(-0.24 * fold, 0.0, 0.0))
		_add_rotation(spine, Vector3(-0.38 * fold, 0.0, 0.0))
		_add_rotation(chest, Vector3(-0.24 * fold, 0.0, 0.0))
		_add_rotation(head, Vector3(0.16 * fold, 0.0, 0.0))
		_add_rotation(left_hip, Vector3(-0.24 * fold, 0.0, -0.04 * fold))
		_add_rotation(right_hip, Vector3(-0.24 * fold, 0.0, 0.04 * fold))
		_add_rotation(left_knee, Vector3(0.62 * fold, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(0.62 * fold, 0.0, 0.0))
		_add_rotation(left_ski, Vector3(0.16 * fold, 0.0, -0.04 * fold))
		_add_rotation(right_ski, Vector3(0.16 * fold, 0.0, 0.04 * fold))
		_add_rotation(left_shoulder, Vector3(-0.42 * fold, 0.0, -0.18 * fold))
		_add_rotation(right_shoulder, Vector3(-0.42 * fold, 0.0, 0.18 * fold))
		_position_targets[pelvis] += Vector3(0.0, -0.1 * fold, 0.08 * fold)
	else:
		_current_pose_name = "Backflip"
		var opening := amount * (1.0 - smoothstep(0.12, 0.42, cycle))
		var tuck := amount * smoothstep(0.18, 0.5, inversion)
		_add_rotation(pelvis, Vector3(0.22 * opening + 0.06 * tuck, 0.0, 0.0))
		_add_rotation(spine, Vector3(0.38 * opening + 0.12 * tuck, 0.0, 0.0))
		_add_rotation(chest, Vector3(0.3 * opening + 0.08 * tuck, 0.0, 0.0))
		_add_rotation(head, Vector3(-0.2 * opening + 0.08 * tuck, 0.0, 0.0))
		_add_rotation(left_hip, Vector3(-0.12 * tuck, 0.0, -0.05 * amount))
		_add_rotation(right_hip, Vector3(-0.12 * tuck, 0.0, 0.05 * amount))
		_add_rotation(left_knee, Vector3(0.12 * tuck, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(0.12 * tuck, 0.0, 0.0))
		_add_rotation(left_ski, Vector3(-0.2 * tuck, 0.0, -0.05 * amount))
		_add_rotation(right_ski, Vector3(-0.2 * tuck, 0.0, 0.05 * amount))
		_add_rotation(left_shoulder, Vector3(0.44 * opening + 0.22 * tuck, 0.0, -0.3 * amount))
		_add_rotation(right_shoulder, Vector3(0.44 * opening + 0.22 * tuck, 0.0, 0.3 * amount))
		_position_targets[pelvis] += Vector3(0.0, 0.04 * opening - 0.05 * tuck, -0.05 * opening)

func _apply_cork_family_pose(side: float, amount: float) -> void:
	if amount <= 0.01:
		return
	_current_pose_name = "Cork %s" % ("Left" if side < 0.0 else "Right")
	_add_rotation(pelvis, Vector3(-0.14 * amount, side * 0.08 * amount, side * 0.2 * amount))
	_add_rotation(spine, Vector3(-0.18 * amount, -side * 0.16 * amount, -side * 0.24 * amount))
	_add_rotation(chest, Vector3(-0.08 * amount, -side * 0.22 * amount, -side * 0.28 * amount))
	_add_rotation(head, Vector3(0.08 * amount, side * 0.18 * amount, side * 0.12 * amount))
	_add_rotation(left_hip, Vector3(-0.42 * amount * (1.0 - side * 0.45), 0.0, -side * 0.18 * amount))
	_add_rotation(right_hip, Vector3(-0.42 * amount * (1.0 + side * 0.45), 0.0, -side * 0.18 * amount))
	_add_rotation(left_knee, Vector3(0.72 * amount * (1.0 - side * 0.42), 0.0, 0.0))
	_add_rotation(right_knee, Vector3(0.72 * amount * (1.0 + side * 0.42), 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.18 * amount * (1.0 - side * 0.35), 0.0, -side * 0.14 * amount))
	_add_rotation(right_ski, Vector3(0.18 * amount * (1.0 + side * 0.35), 0.0, -side * 0.14 * amount))
	_add_rotation(left_shoulder, Vector3(-0.26 * amount, side * 0.12 * amount, -0.38 * amount))
	_add_rotation(right_shoulder, Vector3(0.08 * amount, side * 0.08 * amount, 0.24 * amount))
	_position_targets[pelvis] += Vector3(side * 0.14 * amount, -0.1 * amount, 0.07 * amount)

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
	_current_pose_name = "Rail Entry" if entry > 0.12 else ("Rail Exit Prep" if exit_prep > 0.35 else "Rail 50-50")

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
	var arm_silhouette := lerpf(0.28, 0.72, sideways)
	_add_rotation(left_shoulder, Vector3(-0.16 - sideways * 0.12 - entry * 0.1 + exit_prep * profile.rail_exit_arm_ready, slide * 0.14, -arm_silhouette - balance * arm_gain))
	_add_rotation(right_shoulder, Vector3(-0.16 - sideways * 0.12 - entry * 0.1 + exit_prep * profile.rail_exit_arm_ready, slide * 0.14, arm_silhouette - balance * arm_gain))
	_add_rotation(left_elbow, Vector3(0.1 * entry, 0.0, 0.0))
	_add_rotation(right_elbow, Vector3(0.1 * entry, 0.0, 0.0))

	_add_rotation(left_ski, Vector3(0.0, slide * profile.rail_slide_ski_yaw, balance * 0.05))
	_add_rotation(right_ski, Vector3(0.0, slide * profile.rail_slide_ski_yaw, balance * 0.05))

	if sideways > 0.3:
		_current_pose_name = "Boardslide %s" % ("Left" if slide < 0.0 else "Right")

func _apply_bail_pose(frame: SkierAnimationFrame) -> void:
	var side := clampf(frame.crash_lateral_bias, -1.0, 1.0)
	if absf(side) < 0.05:
		side = signf(frame.crash_incoming_velocity.x)
	if absf(side) < 0.05:
		side = 1.0
	var impact_strength := clampf(frame.crash_impact_speed / 15.0, 0.25, 1.0)
	var angular_strength := clampf(frame.crash_angular_speed / 7.5, 0.15, 1.0)
	var downward_bias := clampf(-frame.crash_incoming_velocity.y / 15.0, -0.35, 1.0)
	_current_blend = 1.0
	_crash_stage_name = CrashContext.Stage.keys()[clampi(frame.crash_stage, CrashContext.Stage.NONE, CrashContext.Stage.REST)].capitalize()
	_crash_layer_weight = 1.0
	match frame.crash_stage:
		CrashContext.Stage.RELEASE:
			_current_pose_name = "Crash Release"
			var release := clampf(frame.crash_elapsed / maxf(profile.crash_release_duration, 0.01), 0.0, 1.0)
			_crash_layer_weight = release
			_add_rotation(pelvis, Vector3(-0.12 * release, 0.0, side * 0.16 * release))
			_add_rotation(chest, Vector3(0.08 * release, -side * 0.12 * release, -side * 0.2 * release))
			_add_rotation(head, Vector3(-0.04 * release, side * 0.1 * release, side * 0.08 * release))
			_add_rotation(left_shoulder, Vector3(-0.62 * release, 0.18, -0.72 * release))
			_add_rotation(right_shoulder, Vector3(-0.62 * release, -0.18, 0.72 * release))
			_add_rotation(left_knee, Vector3(0.52 + side * 0.12, 0.0, -side * 0.08))
			_add_rotation(right_knee, Vector3(0.52 - side * 0.12, 0.0, side * 0.08))
		CrashContext.Stage.IMPACT:
			_current_pose_name = "Crash Impact"
			var directional := side * profile.crash_directional_response * impact_strength
			_add_rotation(pelvis, Vector3(-0.28 - downward_bias * 0.18, side * 0.12, directional * 0.62))
			_add_rotation(spine, Vector3(-0.34 - downward_bias * 0.24, -side * 0.08, directional * 0.5))
			_add_rotation(chest, Vector3(-0.3 - downward_bias * 0.22, -side * 0.16, directional * 0.82))
			_add_rotation(head, Vector3(0.14, side * 0.16, -directional * 0.28))
			_add_rotation(left_shoulder, Vector3(-1.05, 0.3, -0.88 + directional * 0.18))
			_add_rotation(right_shoulder, Vector3(-0.82, -0.3, 0.88 + directional * 0.18))
			_add_rotation(left_hip, Vector3(-0.58, 0.08, -side * 0.32))
			_add_rotation(right_hip, Vector3(-0.34, -0.08, side * 0.32))
			_add_rotation(left_knee, Vector3(1.05, 0.0, -side * 0.12))
			_add_rotation(right_knee, Vector3(0.68, 0.0, side * 0.12))
		CrashContext.Stage.FALL:
			_current_pose_name = "Crash Fall"
			var phase := frame.crash_elapsed * profile.crash_tumble_speed
			var tumble := profile.crash_tumble_limit * angular_strength
			_add_rotation(pelvis, Vector3(-0.42 + sin(phase) * tumble * 0.3, side * 0.18, side * 0.48 + sin(phase * 0.6) * tumble * 0.28))
			_add_rotation(spine, Vector3(-0.38 + cos(phase * 0.72) * tumble * 0.32, -side * 0.12, side * 0.3))
			_add_rotation(chest, Vector3(-0.24, -side * 0.2, side * 0.5 + sin(phase * 0.55) * tumble * 0.22))
			_add_rotation(head, Vector3(0.18, side * 0.2, -side * 0.18))
			_add_rotation(left_shoulder, Vector3(-1.18 + sin(phase) * 0.16, 0.28, -0.95))
			_add_rotation(right_shoulder, Vector3(-0.86 + cos(phase * 0.8) * 0.16, -0.28, 0.95))
			_add_rotation(left_hip, Vector3(-0.72, 0.08, -side * 0.38))
			_add_rotation(right_hip, Vector3(-0.42, -0.08, side * 0.38))
			_add_rotation(left_knee, Vector3(1.28, 0.0, -side * 0.16))
			_add_rotation(right_knee, Vector3(0.82, 0.0, side * 0.16))
		CrashContext.Stage.REST:
			_current_pose_name = "Crash Rest"
			_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(0.0, -profile.crash_rest_pelvis_drop, 0.0)
			_add_rotation(pelvis, Vector3(-0.38, side * 0.12, side * 0.58))
			_add_rotation(spine, Vector3(-0.34, -side * 0.08, side * 0.34))
			_add_rotation(chest, Vector3(-0.2, -side * 0.12, side * 0.42))
			_add_rotation(head, Vector3(0.12, side * 0.15, -side * 0.15))
			_add_rotation(left_shoulder, Vector3(-profile.crash_rest_arm_spread, 0.2, -0.72))
			_add_rotation(right_shoulder, Vector3(-profile.crash_rest_arm_spread, -0.2, 0.72))
			_add_rotation(left_hip, Vector3(-0.62, 0.0, -side * 0.32))
			_add_rotation(right_hip, Vector3(-0.4, 0.0, side * 0.32))
			_add_rotation(left_knee, Vector3(1.18, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.78, 0.0, 0.0))
			_add_rotation(left_ski, Vector3(0.08, -side * 0.28, -side * 0.18))
			_add_rotation(right_ski, Vector3(-0.06, side * 0.3, side * 0.18))
		_:
			_current_pose_name = "Crash Release"
			_crash_stage_name = "Release"

func _update_pre_bail_response(frame: SkierAnimationFrame, delta: float) -> void:
	var target := clampf(frame.pre_bail_weight, 0.0, 1.0) if frame.locomotion_state == STATE_AIR else 0.0
	var response := profile.pre_bail_response if target > _pre_bail_weight else profile.secondary_release_response
	_pre_bail_weight = lerpf(_pre_bail_weight, target, 1.0 - exp(-response * delta))
	_pre_bail_side = lerpf(_pre_bail_side, clampf(frame.pre_bail_side, -1.0, 1.0), 1.0 - exp(-response * delta))

func _apply_pre_bail_layer(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state != STATE_AIR or _pre_bail_weight <= 0.01:
		return
	var weight := _pre_bail_weight
	var side := _pre_bail_side
	if absf(side) < 0.05:
		side = 1.0
	_current_pose_name = "Loss of Control"
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + Vector3(side * profile.pre_bail_pelvis_shift * weight, -0.04 * weight, 0.0)
	_add_rotation(pelvis, Vector3(-0.08 * weight, side * 0.06 * weight, side * 0.16 * weight))
	_add_rotation(spine, Vector3(0.06 * weight, -side * 0.1 * weight, -side * profile.pre_bail_torso_counter * 0.65 * weight))
	_add_rotation(chest, Vector3(0.08 * weight, -side * 0.14 * weight, -side * profile.pre_bail_torso_counter * weight))
	_add_rotation(head, Vector3(-0.04 * weight, side * 0.08 * weight, side * 0.06 * weight))
	_add_rotation(left_shoulder, Vector3(-0.5 * weight, 0.12, -profile.pre_bail_arm_open * weight))
	_add_rotation(right_shoulder, Vector3(-0.5 * weight, -0.12, profile.pre_bail_arm_open * weight))
	_add_rotation(left_hip, Vector3(-profile.pre_bail_leg_asymmetry * weight * (1.0 + side * 0.45), 0.0, -side * 0.08 * weight))
	_add_rotation(right_hip, Vector3(-profile.pre_bail_leg_asymmetry * weight * (1.0 - side * 0.45), 0.0, side * 0.08 * weight))
	_add_rotation(left_knee, Vector3(profile.pre_bail_leg_asymmetry * weight * (1.0 + side * 0.5), 0.0, 0.0))
	_add_rotation(right_knee, Vector3(profile.pre_bail_leg_asymmetry * weight * (1.0 - side * 0.5), 0.0, 0.0))
	_add_rotation(left_pole, Vector3(-profile.pre_bail_pole_trail * weight, 0.0, -0.16 * weight))
	_add_rotation(right_pole, Vector3(-profile.pre_bail_pole_trail * weight, 0.0, 0.16 * weight))

func _apply_grab_layer(frame: SkierAnimationFrame) -> void:
	_grab_left_target_active = false
	_grab_right_target_active = false
	if frame.locomotion_state != STATE_AIR or _grab_definition == null or _grab_pose_weight <= 0.005:
		return
	var definition: Resource = _grab_definition
	var leg_stage := smoothstep(0.02, 0.52, _grab_pose_weight)
	var body_stage := smoothstep(0.12, 0.72, _grab_pose_weight)
	var arm_stage := smoothstep(0.34, 0.9, _grab_pose_weight)
	var body_weight := body_stage * profile.grab_silhouette_scale
	var leg_weight := (
		leg_stage
		* clampf(1.0 - _spin_compactness * 0.32, profile.grab_spin_leg_priority_floor, 1.0)
		* (1.0 - _landing_anticipation * (1.0 - profile.grab_landing_leg_retention))
	)
	var arm_weight := arm_stage * profile.grab_silhouette_scale
	_current_pose_name = "%s / %s" % [definition.display_name, _grab_phase_name.capitalize()]
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + definition.pelvis_offset * body_weight
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
	_apply_pose_shape(definition, body_weight, leg_weight, arm_weight)
	_apply_grab_tweak(definition, frame.grab_tweak, body_weight)
	var reach_weight := clampf(
		arm_stage * profile.grab_reach * definition.reach_response_scale,
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

func _apply_style_layer(frame: SkierAnimationFrame) -> void:
	if frame.locomotion_state != STATE_AIR or _style_definition == null or _style_pose_weight <= 0.005:
		return
	_current_pose_name = "%s / %s" % [_style_definition.display_name, _style_phase_name.capitalize()]
	_position_targets[pelvis] = (_position_targets[pelvis] as Vector3) + _style_definition.pelvis_offset * _style_pose_weight
	_apply_pose_shape(_style_definition, _style_pose_weight, _style_pose_weight)

func _apply_pose_shape(definition: Resource, body_weight: float, leg_weight: float, arm_weight: float = -1.0) -> void:
	if arm_weight < 0.0:
		arm_weight = body_weight
	_add_rotation(pelvis, definition.pelvis_rotation * body_weight)
	_add_rotation(spine, definition.spine_rotation * body_weight)
	_add_rotation(chest, definition.chest_rotation * body_weight)
	_add_rotation(head, definition.head_rotation * body_weight)
	_add_rotation(left_hip, definition.left_hip_rotation * leg_weight)
	_add_rotation(right_hip, definition.right_hip_rotation * leg_weight)
	_add_rotation(left_knee, definition.left_knee_rotation * leg_weight)
	_add_rotation(right_knee, definition.right_knee_rotation * leg_weight)
	_add_rotation(left_boot, definition.left_boot_rotation * leg_weight)
	_add_rotation(right_boot, definition.right_boot_rotation * leg_weight)
	_add_rotation(left_ski, definition.left_ski_rotation * leg_weight)
	_add_rotation(right_ski, definition.right_ski_rotation * leg_weight)
	_add_rotation(left_shoulder, definition.left_shoulder_rotation * arm_weight)
	_add_rotation(right_shoulder, definition.right_shoulder_rotation * arm_weight)
	_add_rotation(left_elbow, definition.left_elbow_rotation * arm_weight)
	_add_rotation(right_elbow, definition.right_elbow_rotation * arm_weight)
	_add_rotation(left_hand, definition.left_hand_rotation * arm_weight)
	_add_rotation(right_hand, definition.right_hand_rotation * arm_weight)
	_add_rotation(left_pole, definition.left_pole_rotation * arm_weight)
	_add_rotation(right_pole, definition.right_pole_rotation * arm_weight)

func _apply_grab_tweak(definition: Resource, tweak: Vector2, amount: float) -> void:
	if tweak.length() <= 0.05:
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
	var side := &"left" if ski_side == GrabDefinition.Ski.LEFT else (&"right" if ski_side == GrabDefinition.Ski.RIGHT else &"")
	var target_name := &""
	match target:
		GrabDefinition.Target.BINDING_OUTSIDE: target_name = &"binding_outside"
		GrabDefinition.Target.BINDING_INSIDE: target_name = &"binding_inside"
		GrabDefinition.Target.NOSE: target_name = &"nose"
		GrabDefinition.Target.TAIL: target_name = &"tail"
	if rig_adapter != null and side != &"" and target_name != &"":
		var adapter_target := rig_adapter.grab_target(side, target_name)
		if adapter_target != null:
			return adapter_target
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
	if rig_adapter != null:
		var measured_lengths := rig_adapter.arm_lengths(&"left" if side < 0.0 else &"right")
		if measured_lengths.x > 0.01 and measured_lengths.y > 0.01:
			upper = measured_lengths.x
			lower = measured_lengths.y
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
	if frame.locomotion_state != STATE_BAIL:
		_add_rotation(spine, _torso_follow_through * 0.38)
		_add_rotation(chest, _torso_follow_through)
		_add_rotation(head, _head_stabilization)
		var left_constraint := 1.0
		var right_constraint := 1.0
		if _grab_definition != null:
			var grab_constraint := maxf(_grab_pose_weight * 0.9, _grab_contact_weight)
			if _grab_definition.hand == GrabDefinition.Hand.LEFT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
				left_constraint = 1.0 - grab_constraint * 0.98
			if _grab_definition.hand == GrabDefinition.Hand.RIGHT or _grab_definition.hand == GrabDefinition.Hand.BOTH:
				right_constraint = 1.0 - grab_constraint * 0.98
		var left_arm_follow := _left_arm_inertia * left_constraint
		var right_arm_follow := _right_arm_inertia * right_constraint
		_add_rotation(left_shoulder, left_arm_follow)
		_add_rotation(right_shoulder, right_arm_follow)
		_add_rotation(left_elbow, left_arm_follow * 0.34)
		_add_rotation(right_elbow, right_arm_follow * 0.34)
		_add_rotation(left_hand, left_arm_follow * profile.hand_inertia_gain)
		_add_rotation(right_hand, right_arm_follow * profile.hand_inertia_gain)
		_add_rotation(left_hip, Vector3(-_leg_rebound * 0.22, 0.0, 0.0))
		_add_rotation(right_hip, Vector3(-_leg_rebound * 0.22, 0.0, 0.0))
		_add_rotation(left_knee, Vector3(_leg_rebound, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(_leg_rebound, 0.0, 0.0))
		_add_rotation(left_boot, Vector3(-_leg_rebound * 0.24, 0.0, 0.0))
		_add_rotation(right_boot, Vector3(-_leg_rebound * 0.24, 0.0, 0.0))
	if frame.locomotion_state == STATE_GROUND:
		var speed_trail := 0.14 + clampf(frame.speed_ratio, 0.0, 1.0) * profile.pole_speed_trail
		var asymmetry := profile.stance_asymmetry
		var arm_chain_pitch := profile.neutral_hand_forward_pitch - _crouch_amount * profile.speed_arm_tuck + profile.neutral_elbow_bend
		var left_arm_roll := -0.2 - _arm_carve * 0.16
		var right_arm_roll := 0.2 - _arm_carve * 0.16
		var landing_trail := _landing_pole_lag + _landing_compression * 0.18
		var carve_split := absf(_pole_carve) * profile.carve_pole_split
		_add_rotation(left_pole, Vector3(-arm_chain_pitch - speed_trail - landing_trail + asymmetry, -_pole_carve * profile.pole_turn_lag - carve_split - _landing_lateral_bias * landing_trail * 0.35, -left_arm_roll + profile.ground_pole_outward - asymmetry - _landing_arm_open * 0.2))
		_add_rotation(right_pole, Vector3(-arm_chain_pitch - speed_trail - landing_trail - asymmetry, -_pole_carve * profile.pole_turn_lag + carve_split - _landing_lateral_bias * landing_trail * 0.35, -right_arm_roll - profile.ground_pole_outward + asymmetry + _landing_arm_open * 0.2))
	elif frame.locomotion_state == STATE_AIR:
		var rotation_follow := _spin_compactness
		var takeoff_lag := _air_takeoff_weight * 0.16
		var settle := 1.0 - _landing_anticipation * 0.48
		var phase_trail := (profile.air_pole_trail + _air_early_weight * 0.12 - _air_descent_weight * 0.08) * settle
		var anticipation_trail := _landing_anticipation * 0.12
		var spin_side := signf(_smoothed_angular_velocity.y)
		var asymmetry := profile.stance_asymmetry + spin_side * profile.trick_leg_asymmetry * rotation_follow * 0.35
		var pole_phase_sine := sin(_spin_cycle * TAU) * spin_side * rotation_follow * profile.spin_pole_phase
		var pole_phase_cosine := cos(_spin_cycle * TAU) * rotation_follow * profile.spin_pole_phase
		var yaw_lag := clampf(
			-_smoothed_angular_velocity.y * profile.trick_pole_lag * 0.12 * _trick_pose_weight,
			-profile.trick_shoulder_yaw_limit,
			profile.trick_shoulder_yaw_limit
		)
		_add_rotation(left_pole, Vector3(-phase_trail - takeoff_lag - anticipation_trail + asymmetry + pole_phase_cosine * 0.35, yaw_lag - pole_phase_cosine, profile.air_pole_outward + rotation_follow * 0.08 + pole_phase_sine + _landing_anticipation * 0.12))
		_add_rotation(right_pole, Vector3(-phase_trail - takeoff_lag - anticipation_trail - asymmetry - pole_phase_cosine * 0.25, yaw_lag * 0.82 + pole_phase_cosine * 0.65, -profile.air_pole_outward - rotation_follow * 0.08 + pole_phase_sine * 0.55 - _landing_anticipation * 0.12))
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
	_add_rotation(left_pole, _left_pole_inertia)
	_add_rotation(right_pole, _right_pole_inertia)

func _silhouette_landmarks() -> Dictionary:
	if rig_adapter != null:
		var adapter_landmarks := rig_adapter.landmarks()
		if not adapter_landmarks.is_empty():
			return adapter_landmarks
	return {
		"head": head.to_global(Vector3(0.0, 0.22, 0.0)),
		"pelvis": pelvis.global_position,
		"left_knee": left_knee.global_position,
		"right_knee": right_knee.global_position,
		"left_boot": left_boot.global_position,
		"right_boot": right_boot.global_position,
		"left_ski_nose": left_grab_nose.global_position,
		"right_ski_nose": right_grab_nose.global_position,
		"left_ski_tail": left_grab_tail.global_position,
		"right_ski_tail": right_grab_tail.global_position,
		"left_hand": left_hand.global_position,
		"right_hand": right_hand.global_position,
		"left_pole_tip": left_pole_tip.global_position,
		"right_pole_tip": right_pole_tip.global_position,
	}

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
	for key: Variant in _rotation_targets:
		var joint := key as Node3D
		var target := _rotation_targets[key] as Vector3
		var rotation_response := _joint_rotation_response(joint)
		var pop_response := maxf(rotation_response, profile.pop_pose_response * _joint_pop_response_scale(joint))
		var rotation_weight := 1.0 - exp(-lerpf(rotation_response, pop_response, pop_blend) * delta)
		joint.rotation = Vector3(
			lerp_angle(joint.rotation.x, target.x, rotation_weight),
			lerp_angle(joint.rotation.y, target.y, rotation_weight),
			lerp_angle(joint.rotation.z, target.z, rotation_weight)
		)
	for key: Variant in _position_targets:
		var joint := key as Node3D
		var position_response := _joint_position_response(joint)
		var position_weight := 1.0 - exp(-position_response * delta)
		joint.position = joint.position.lerp(_position_targets[key] as Vector3, position_weight)

func _joint_rotation_response(joint: Node3D) -> float:
	if _current_state == STATE_BAIL:
		return profile.crash_pose_response
	if joint == left_ski or joint == right_ski or joint == left_boot or joint == right_boot:
		return profile.ski_joint_response
	if joint == left_hip or joint == right_hip or joint == left_knee or joint == right_knee:
		return profile.leg_joint_response
	if joint == balance_root or joint == pelvis:
		return profile.pelvis_joint_response
	if joint == spine:
		return profile.spine_joint_response
	if joint == chest:
		return profile.chest_joint_response
	if joint == head:
		return profile.head_joint_response
	if joint == left_shoulder or joint == right_shoulder:
		return profile.shoulder_joint_response
	if joint == left_elbow or joint == right_elbow:
		return profile.elbow_joint_response
	if joint == left_hand or joint == right_hand:
		return profile.hand_joint_response
	if joint == left_pole or joint == right_pole:
		return profile.pole_joint_response
	return profile.pose_response

func _joint_pop_response_scale(joint: Node3D) -> float:
	if joint == left_ski or joint == right_ski or joint == left_boot or joint == right_boot:
		return 1.0
	if joint == left_hip or joint == right_hip or joint == left_knee or joint == right_knee or joint == pelvis:
		return 0.9
	if joint == spine or joint == chest or joint == left_shoulder or joint == right_shoulder:
		return 0.72
	if joint == head:
		return 0.62
	if joint == left_pole or joint == right_pole:
		return 0.5
	return 0.65

func _joint_position_response(joint: Node3D) -> float:
	if joint == pelvis:
		return profile.fast_pose_response
	if joint == left_hip or joint == right_hip:
		return profile.leg_joint_response
	if joint == chest:
		return profile.spine_joint_response
	if joint == left_shoulder or joint == right_shoulder:
		return profile.shoulder_joint_response
	return profile.pose_response

func _add_rotation(joint: Node3D, value: Vector3) -> void:
	_rotation_targets[joint] = (_rotation_targets.get(joint, Vector3.ZERO) as Vector3) + value * _layer_weight

func _reset_pose_immediately(snap_joints: bool = true) -> void:
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
	_slarve_weight = 0.0
	_slarve_side = 0.0
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
	_air_style_side = 1.0
	_smoothed_angular_velocity = Vector3.ZERO
	_trick_rotation_accumulated = Vector3.ZERO
	_trick_rotation_residual = Vector3.ZERO
	_trick_pose_weight = 0.0
	_prewind_weight = 0.0
	_prewind_direction = 0.0
	_trick_release_weight = 0.0
	_spin_compactness = 0.0
	_spin_cycle = 0.0
	_spotting_weight = 0.0
	_spin_open_weight = 0.0
	_spin_visual_phase_name = "IDLE"
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
	_style_definition = null
	_style_pose_id = TrickController.StylePose.NONE
	_style_pose_weight = 0.0
	_style_phase_name = "IDLE"
	_clear_landing_state()
	_landing_alignment = 0.0
	_landing_anticipation = 0.0
	_landing_readiness = 0.0
	_landing_readiness_heading = 0.0
	_landing_readiness_pitch = 0.0
	_landing_readiness_spin = 0.0
	_landing_readiness_upright = 0.0
	_landing_readiness_residual = 0.0
	_landing_projected_heading_error = 0.0
	_landing_projected_residual = 0.0
	_landing_readiness_valid = false
	_landing_ready = false
	_landing_compression = 0.0
	_landing_arm_open = 0.0
	_landing_pole_lag = 0.0
	_landing_head_nod = 0.0
	_landing_ski_yaw = 0.0
	_landing_ski_pitch = 0.0
	_landing_torso_prepare = 0.0
	_stomp_candidate = false
	_stomp_active = false
	_stomp_time = 0.0
	_stomp_weight = 0.0
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
	_previous_state = _current_state
	_state_transition_weight = 1.0
	_secondary_signals_initialized = false
	_previous_vertical_velocity = 0.0
	_previous_yaw_rate = 0.0
	_previous_landing_compression = 0.0
	_filtered_lateral_accel = 0.0
	_filtered_vertical_accel = 0.0
	_filtered_yaw_accel = 0.0
	_filtered_heading_delta = 0.0
	_landing_compression_velocity = 0.0
	_torso_follow_through = Vector3.ZERO
	_head_stabilization = Vector3.ZERO
	_left_arm_inertia = Vector3.ZERO
	_right_arm_inertia = Vector3.ZERO
	_left_pole_inertia = Vector3.ZERO
	_right_pole_inertia = Vector3.ZERO
	_leg_rebound = 0.0
	_secondary_motion_weight = 0.0
	_crash_stage_name = "None"
	_crash_layer_weight = 0.0
	_pre_bail_weight = 0.0
	_pre_bail_side = 0.0
	_previous_left_hand_velocity = Vector3.ZERO
	_previous_right_hand_velocity = Vector3.ZERO
	_filtered_left_hand_accel = Vector3.ZERO
	_filtered_right_hand_accel = Vector3.ZERO
	_reset_targets()
	if snap_joints:
		for key: Variant in _rotation_targets:
			(key as Node3D).rotation = _rotation_targets[key] as Vector3
		for key: Variant in _position_targets:
			(key as Node3D).position = _position_targets[key] as Vector3
	_initialize_secondary_motion_state()

func _build_articulated_rig() -> void:
	pose_driver = PoseDriverModule.new() as SkierPoseDriver
	pose_driver.name = "CanonicalPoseDriver"
	add_child(pose_driver)
	pose_driver.build()
	balance_root = pose_driver.joint(&"balance_root")
	pelvis = pose_driver.joint(&"pelvis")
	spine = pose_driver.joint(&"spine")
	chest = pose_driver.joint(&"chest")
	head = pose_driver.joint(&"head")
	left_hip = pose_driver.joint(&"left_hip")
	right_hip = pose_driver.joint(&"right_hip")
	left_knee = pose_driver.joint(&"left_knee")
	right_knee = pose_driver.joint(&"right_knee")
	left_boot = pose_driver.joint(&"left_boot")
	right_boot = pose_driver.joint(&"right_boot")
	left_ski = pose_driver.joint(&"left_ski")
	right_ski = pose_driver.joint(&"right_ski")
	left_shoulder = pose_driver.joint(&"left_shoulder")
	right_shoulder = pose_driver.joint(&"right_shoulder")
	left_elbow = pose_driver.joint(&"left_elbow")
	right_elbow = pose_driver.joint(&"right_elbow")
	left_hand = pose_driver.joint(&"left_hand")
	right_hand = pose_driver.joint(&"right_hand")
	left_pole = pose_driver.joint(&"left_pole")
	right_pole = pose_driver.joint(&"right_pole")
	left_grab_binding_outside = pose_driver.grab_target(&"left", &"binding_outside")
	left_grab_binding_inside = pose_driver.grab_target(&"left", &"binding_inside")
	left_grab_nose = pose_driver.grab_target(&"left", &"nose")
	left_grab_tail = pose_driver.grab_target(&"left", &"tail")
	right_grab_binding_outside = pose_driver.grab_target(&"right", &"binding_outside")
	right_grab_binding_inside = pose_driver.grab_target(&"right", &"binding_inside")
	right_grab_nose = pose_driver.grab_target(&"right", &"nose")
	right_grab_tail = pose_driver.grab_target(&"right", &"tail")
	left_pole_tip = pose_driver.pole_tips[&"left"] as Node3D
	right_pole_tip = pose_driver.pole_tips[&"right"] as Node3D
	_select_rig_adapter()
	_reset_pose_immediately()
	if rig_adapter != null:
		rig_adapter.sync_pose(0.0)

func _select_rig_adapter() -> void:
	var selected_mode := rig_mode
	if OS.get_cmdline_user_args().has("--primitive-skier"):
		selected_mode = RigMode.PRIMITIVE
	requested_rig_adapter = "primitive" if selected_mode == RigMode.PRIMITIVE else "skeleton"
	if selected_mode != RigMode.PRIMITIVE:
		var skeleton_candidate := SkeletonRigModule.new() as SkierRigAdapter
		skeleton_candidate.name = "SkeletonRigAdapter"
		add_child(skeleton_candidate)
		if skeleton_candidate.configure(pose_driver, skeleton_profile):
			rig_adapter = skeleton_candidate
			return
		rig_fallback_reason = skeleton_candidate.validation_error()
		remove_child(skeleton_candidate)
		skeleton_candidate.free()
	var primitive_candidate := PrimitiveRigModule.new() as SkierRigAdapter
	primitive_candidate.name = "PrimitiveRigAdapter"
	add_child(primitive_candidate)
	primitive_candidate.configure(pose_driver)
	rig_adapter = primitive_candidate
