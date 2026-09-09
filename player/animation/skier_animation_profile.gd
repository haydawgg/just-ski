class_name SkierAnimationProfile
extends Resource

@export_category("Response")
@export var pose_response: float = 10.0
@export var fast_pose_response: float = 18.0
@export var secondary_response: float = 6.0

@export_category("Ground")
@export var neutral_ankle_flex: float = 0.24
@export var speed_ankle_flex: float = 0.15
@export var neutral_knee_flex: float = 0.55
@export var speed_knee_flex: float = 0.34
@export var neutral_hip_flex: float = 0.24
@export var speed_hip_flex: float = 0.14
@export var neutral_torso_pitch: float = 0.22
@export var speed_torso_pitch: float = 0.12
@export var pelvis_flex_depth: float = 0.27
@export var neutral_pelvis_drop: float = 0.03
@export var neutral_pelvis_offset: float = 0.035
@export var neutral_hand_forward_pitch: float = 0.34
@export var neutral_elbow_bend: float = 0.72
@export var speed_arm_tuck: float = 0.12

@export_category("Carve")
@export var lateral_acceleration_reference: float = 9.0
@export var turn_rate_reference: float = 0.72
@export var carve_ski_roll: float = 0.25
@export var carve_root_roll_share: float = 0.18
@export var carve_knee_roll: float = 0.16
@export var carve_hip_roll: float = 0.4
@export var carve_spine_roll: float = 0.26
@export var carve_chest_roll: float = 0.16
@export var carve_head_level: float = 0.18
@export var carve_pelvis_shift: float = 0.28
@export var carve_pelvis_drop: float = 0.1
@export var inside_leg_extra_flex: float = 0.38
@export var outside_leg_extension: float = 0.26
@export var chest_counter_yaw: float = 0.24
@export var chest_travel_alignment: float = 0.42
@export var deep_carve_threshold: float = 0.62
@export var carve_leg_load_start: float = 0.18
@export var carve_leg_load_full: float = 0.78
@export var ski_carve_response: float = 22.0
@export var leg_carve_response: float = 15.0
@export var pelvis_carve_response: float = 9.0
@export var torso_carve_response: float = 6.5
@export var arm_carve_response: float = 4.8
@export var crossover_duration: float = 0.42
@export var crossover_extension: float = 0.18

@export_category("Ground Actions")
@export var brake_ski_yaw: float = 0.92
@export var tuck_spine_pitch: float = 0.54
@export var tuck_arm_pitch: float = 1.05
@export var compression_depth: float = 0.26
@export var slarve_skid_start: float = 0.16
@export var slarve_skid_full: float = 0.72
@export var slarve_heading_reference: float = 0.62
@export var slarve_ski_yaw: float = 0.46
@export var slarve_pelvis_yaw: float = 0.28
@export var slarve_chest_counter_yaw: float = 0.34
@export var slarve_leg_flex: float = 0.18
@export var slarve_arm_open: float = 0.2
@export var switch_leg_lead: float = 0.52
@export var switch_pelvis_yaw: float = 0.34
@export var switch_chest_yaw: float = 0.5
@export var switch_head_spot: float = 0.48
@export var switch_arm_asymmetry: float = 0.42
@export var switch_pole_split: float = 0.38

@export_category("Secondary Motion")
@export var pole_speed_trail: float = 0.56
@export var pole_turn_lag: float = 0.2
@export var ground_pole_outward: float = 0.28
@export var carve_pole_split: float = 0.22
@export var air_pole_outward: float = 0.38
@export var spin_pole_phase: float = 0.22
@export var stance_asymmetry: float = 0.025
@export var secondary_signal_response: float = 10.0
@export var secondary_release_response: float = 7.0
@export var secondary_max_lateral_accel: float = 14.0
@export var secondary_max_vertical_accel: float = 24.0
@export var secondary_max_yaw_accel: float = 28.0
@export var torso_follow_response: float = 6.0
@export var torso_carve_lag_gain: float = 0.16
@export var torso_lateral_accel_gain: float = 0.006
@export var torso_vertical_accel_gain: float = 0.0025
@export var torso_yaw_accel_gain: float = 0.002
@export var torso_follow_limit: float = 0.14
@export var head_stabilization_response: float = 8.5
@export var head_stabilization_gain: float = 0.32
@export var arm_inertia_response: float = 5.2
@export var arm_lateral_accel_gain: float = 0.008
@export var arm_vertical_accel_gain: float = 0.004
@export var arm_yaw_accel_gain: float = 0.003
@export var arm_inertia_limit: float = 0.18
@export var hand_inertia_gain: float = 0.22
@export var pole_inertia_response: float = 4.8
@export var pole_release_response: float = 7.0
@export var pole_hand_accel_gain: float = 0.007
@export var pole_yaw_accel_gain: float = 0.006
@export var pole_inertia_limit: float = 0.34
@export var leg_rebound_response: float = 7.0
@export var leg_rebound_gain: float = 0.025
@export var landing_rebound_gain: float = 0.018
@export var leg_rebound_limit: float = 0.07

@export_category("Joint Response Hierarchy")
@export var ski_joint_response: float = 18.0
@export var leg_joint_response: float = 15.0
@export var pelvis_joint_response: float = 11.0
@export var spine_joint_response: float = 9.0
@export var chest_joint_response: float = 7.5
@export var head_joint_response: float = 8.5
@export var shoulder_joint_response: float = 6.5
@export var elbow_joint_response: float = 5.8
@export var hand_joint_response: float = 5.2
@export var pole_joint_response: float = 4.8

@export_category("Terrain Suspension")
@export var terrain_follow_response: float = 14.0
@export var contact_confidence_response: float = 8.0
@export_range(0.0, 1.0) var pelvis_terrain_response: float = 0.24
@export var terrain_flex_gain: float = 1.85
@export var terrain_pelvis_roll: float = 0.65
@export var terrain_influence_response: float = 10.0
@export var terrain_normal_response: float = 12.0
@export_range(0.0, 1.0) var ankle_terrain_response: float = 0.58
@export var min_leg_flex: float = 0.12
@export var max_leg_flex: float = 1.7
@export var pelvis_terrain_drop_limit: float = 0.28
@export var max_ankle_pitch: float = 0.5
@export var max_ankle_roll: float = 0.4
@export var compression_travel: float = 0.32
@export var terrain_discontinuity_soft_gap: float = 0.26
@export var terrain_discontinuity_hard_gap: float = 0.58
@export_range(-1.0, 1.0) var terrain_normal_agreement_threshold: float = 0.78
@export var terrain_orientation_speed_limit: float = 3.2

@export_category("Air")
@export var air_tuck_strength: float = 0.7
@export var spin_compact_threshold: float = 2.2
@export var flip_compact_threshold: float = 1.8
@export var jump_anticipation_response: float = 9.0
@export var jump_anticipation_knee_flex: float = 0.34
@export var jump_anticipation_ankle_flex: float = 0.13
@export var jump_anticipation_pelvis_drop: float = 0.13
@export var jump_anticipation_hip_flex: float = 0.12
@export var jump_anticipation_torso_pitch: float = 0.1
@export var jump_anticipation_arm_back: float = 0.24
@export var pop_pose_response: float = 24.0
@export var air_phase_response: float = 10.0
@export var air_takeoff_hold_time: float = 0.16
@export var air_apex_velocity_band: float = 0.75
@export var air_descent_velocity_reference: float = 5.5
@export var air_small_takeoff_speed: float = 0.55
@export var air_large_takeoff_speed: float = 4.2
@export var air_takeoff_leg_flex: float = 0.14
@export var air_compact_leg_flex: float = 0.58
@export var air_spin_leg_flex: float = 0.22
@export var air_pelvis_compact_drop: float = 0.13
@export var air_takeoff_pelvis_rise: float = 0.11
@export var air_ski_pitch: float = 0.11
@export var air_arm_balance_open: float = 0.34
@export var air_pole_trail: float = 0.52
@export var air_leg_asymmetry: float = 0.16
@export var air_pelvis_side_offset: float = 0.06
@export var air_torso_counter_roll: float = 0.12
@export var air_arm_asymmetry: float = 0.22
@export var air_ski_scissor: float = 0.06

@export_category("Airborne Rotation")
@export var trick_rate_response: float = 12.0
@export var trick_pose_response: float = 11.0
@export var trick_activation_rate: float = 0.65
@export var trick_max_animation_rate: float = 8.0
@export var trick_release_duration: float = 0.18
@export var trick_prewind_chest_yaw: float = 0.32
@export var trick_pelvis_yaw_limit: float = 0.16
@export var trick_spine_yaw_limit: float = 0.25
@export var trick_chest_yaw_limit: float = 0.38
@export var trick_head_yaw_limit: float = 0.48
@export var trick_shoulder_yaw_limit: float = 0.32
@export var trick_spin_knee_flex: float = 0.28
@export var trick_spin_pelvis_drop: float = 0.11
@export var trick_spin_arm_tuck: float = 0.42
@export var trick_spin_phase_leg_shape: float = 0.28
@export var trick_spin_phase_pelvis_shift: float = 0.1
@export var trick_spin_phase_torso_shape: float = 0.25
@export var trick_spin_phase_arm_shape: float = 0.38
@export var trick_spin_phase_ski_shape: float = 0.2
@export var trick_landing_arm_open: float = 0.58
@export var trick_open_pelvis_follow_yaw: float = 0.06
@export var trick_open_spine_counter_yaw: float = 0.12
@export var trick_open_chest_counter_yaw: float = 0.18
@export var trick_open_ski_follow_yaw: float = 0.05
@export var trick_leg_asymmetry: float = 0.06
@export var trick_pole_lag: float = 0.14
@export_range(0.0, 1.0) var trick_multi_axis_weight: float = 0.65
@export var trick_flip_leg_shape: float = 0.22
@export var trick_flip_arm_shape: float = 0.28
@export var trick_cork_leg_shape: float = 0.24
@export var trick_cork_arm_shape: float = 0.34

@export_category("Landing")
@export var landing_anticipation_time: float = 0.55
@export var landing_anticipation_start: float = 0.18
@export var landing_alignment_start: float = 0.32
@export var landing_readiness_start: float = 0.2
@export var landing_anticipation_leg_extend: float = 0.26
@export var landing_anticipation_arm_open: float = 0.18
@export var landing_anticipation_torso_pitch: float = 0.1
@export var landing_anticipation_head_pitch: float = 0.16
@export var landing_ski_align_yaw: float = 0.22
@export var landing_ski_align_pitch: float = 0.14
@export var landing_anticipation_response: float = 8.0
@export var landing_compression_response: float = 15.5
@export var landing_recovery_response_soft: float = 6.8
@export var landing_recovery_response_hard: float = 5.0
@export var landing_compression_depth: float = 0.34
@export var landing_knee_flex: float = 0.8
@export var landing_hip_flex: float = 0.28
@export var landing_ankle_flex: float = 0.16
@export var landing_pelvis_drop: float = 0.24
@export var landing_torso_pitch: float = 0.18
@export var landing_arm_open: float = 0.42
@export var landing_pole_lag: float = 0.28
@export var landing_head_nod: float = 0.08
@export var landing_wobble_amplitude: float = 0.22
@export var landing_wobble_frequency: float = 7.5
@export var landing_wobble_decay: float = 3.2
@export var landing_rotation_correct_yaw: float = 0.18
@export var landing_asymmetry_gain: float = 0.28
@export var landing_hop_air_time_reference: float = 0.35
@export var landing_min_air_time_scale: float = 0.12
@export var stomp_min_air_time: float = 0.28
@export var stomp_duration: float = 0.42
@export var stomp_stack_strength: float = 0.34

@export_category("Landing Readiness")
@export var landing_readiness_heading_good: float = 0.0872665
@export var landing_readiness_heading_bad: float = 0.7853982
@export var landing_readiness_pitch_good: float = 0.0698132
@export var landing_readiness_pitch_bad: float = 0.5235988
@export var landing_readiness_spin_good: float = 0.5235988
@export var landing_readiness_spin_bad: float = 4.1887902
@export var landing_readiness_upright_good: float = 0.1745329
@export var landing_readiness_upright_bad: float = 0.9599311
@export var landing_readiness_residual_good: float = 0.1745329
@export var landing_readiness_residual_bad: float = 1.5707963
@export_range(0.0, 1.0) var landing_readiness_heading_weight: float = 0.3
@export_range(0.0, 1.0) var landing_readiness_pitch_weight: float = 0.2
@export_range(0.0, 1.0) var landing_readiness_spin_weight: float = 0.2
@export_range(0.0, 1.0) var landing_readiness_upright_weight: float = 0.1
@export_range(0.0, 1.0) var landing_readiness_residual_weight: float = 0.2
@export var landing_readiness_rise_response: float = 16.0
@export var landing_readiness_fall_response: float = 10.0
@export var landing_readiness_near_contact_response: float = 28.0
@export var landing_readiness_near_contact_window: float = 0.2
@export_range(0.0, 1.0) var landing_corrective_pose_gain: float = 0.85
@export_range(0.0, 1.0) var ready_anticipation_threshold: float = 0.65
@export_range(0.0, 1.0) var ready_readiness_threshold: float = 0.75

@export_category("Grab")
@export var grab_reach: float = 1.0
@export var grab_silhouette_scale: float = 1.32
@export_range(0.0, 1.0) var grab_spin_leg_priority_floor: float = 0.74
@export_range(0.0, 1.0) var grab_landing_leg_retention: float = 0.75
@export var grab_pose_response: float = 12.0
@export var grab_contact_response: float = 15.0
@export var grab_release_response: float = 11.0
@export var grab_recover_response: float = 6.5
@export var grab_min_contact_air_time: float = 0.1
@export_range(0.0, 1.0) var grab_landing_release_strength: float = 0.68
@export_range(0.0, 1.0) var grab_late_hold_floor: float = 0.28
@export var grab_chest_drop: float = 0.34
@export var grab_leg_tuck: float = 0.58
@export var grab_ski_lift_knee: float = 0.35
@export var grab_ski_lift_hip: float = 0.05
@export var grab_knee_flex_limit: float = 2.65
@export var grab_upper_arm_length: float = 0.42
@export var grab_forearm_length: float = 0.37
@export var grab_shoulder_pitch_limit: float = 1.35
@export var grab_shoulder_yaw_limit: float = 0.95
@export var grab_shoulder_roll_limit: float = 1.35
@export var grab_elbow_limit: float = 1.5
@export var grab_tweak_angle: float = 0.16
@export var grab_pole_away: float = 0.18

@export_category("Style Poses")
@export var style_pose_response: float = 10.0

@export_category("Flick")
@export var flick_setup_depth: float = 0.16
@export var flick_pop_extension: float = 0.12
@export var spin_head_spot: float = 0.68

@export_category("Rail")
@export var rail_knee_flex: float = 0.56
@export var rail_balance_lean: float = 0.3
@export var rail_counter_rotation: float = 0.45
@export var rail_approach_response: float = 6.0
@export var rail_approach_knee_ready: float = 0.12
@export var rail_approach_arm_open: float = 0.14
@export var rail_approach_torso_center: float = 0.08
@export var rail_influence_rise_response: float = 14.0
@export var rail_influence_fall_response: float = 5.5
@export var rail_entry_compression_response: float = 22.0
@export var rail_entry_recovery_response: float = 10.0
@export var rail_entry_max_compression: float = 0.55
@export var rail_entry_knee_flex: float = 0.3
@export var rail_entry_hip_drop: float = 0.12
@export var rail_entry_pole_lag: float = 0.3
@export var rail_slide_response: float = 5.5
@export var rail_slide_max_angle: float = 1.25
@export var rail_slide_hip_yaw: float = 0.98
@export var rail_slide_chest_counter: float = 0.72
@export var rail_slide_ski_yaw: float = 0.55
@export var rail_arm_balance_gain: float = 0.9
@export var rail_torso_counter_lean: float = 0.3
@export var rail_pelvis_shift: float = 0.16
@export var rail_leg_asymmetry_gain: float = 0.3
@export var rail_exit_response: float = 7.0
@export var rail_exit_anticipation_distance: float = 1.6
@export var rail_exit_leg_extend: float = 0.18
@export var rail_exit_pelvis_rise: float = 0.07
@export var rail_exit_arm_ready: float = 0.12

@export_category("Lower Body IK")
@export_range(0.0, 1.0) var ground_leg_ik_weight: float = 1.0
@export_range(0.0, 1.0) var rail_leg_ik_weight: float = 0.94
@export_range(0.0, 1.0) var air_leg_ik_weight: float = 0.0
@export_range(0.0, 1.0) var bail_leg_ik_weight: float = 0.0
@export var leg_ik_weight_response: float = 12.0
@export var leg_ik_max_angular_rate: float = 8.0
@export var landing_leg_ik_max_angular_rate: float = 24.0
@export var landing_leg_ik_pelvis_translation_limit: float = 0.28
@export var leg_ik_pelvis_translation_limit: float = 0.14
@export var leg_ik_pelvis_rotation_limit: float = 0.14
@export var leg_ik_max_reach_ratio: float = 1.02
@export var leg_ik_min_stance_width: float = 0.16
@export var pose_handoff_duration: float = 0.2
@export var landing_pose_handoff_duration: float = 0.08
@export var pop_pose_handoff_duration: float = 0.08
@export var rail_contact_duration: float = 0.12
@export var rail_compression_duration: float = 0.2

@export_category("Reactions")
@export var pop_duration: float = 0.24
@export var clean_landing_duration: float = 0.3
@export var sketchy_landing_duration: float = 0.62
@export var hard_landing_duration: float = 0.82

@export_category("Crash")
@export var crash_release_duration: float = 0.18
@export var crash_impact_duration: float = 0.22
@export var crash_pose_response: float = 12.0
@export var crash_tumble_speed: float = 5.2
@export var crash_tumble_limit: float = 0.58
@export var crash_directional_response: float = 0.7
@export var crash_sprawl_pelvis_pitch: float = 0.32
@export var crash_sprawl_pelvis_yaw: float = 0.16
@export var crash_sprawl_pelvis_roll: float = 0.42
@export var crash_sprawl_torso_fold: float = 0.24
@export var crash_sprawl_arm_spread: float = 0.38
@export var crash_sprawl_leg_drag: float = 0.22
@export var crash_sprawl_ski_yaw: float = 0.18
@export var crash_rest_pelvis_drop: float = 0.28
@export var crash_rest_arm_spread: float = 0.82
@export var crash_recovery_duration: float = 0.72
@export var crash_recovery_recenter_portion: float = 0.45
@export var crash_recovery_ik_start: float = 0.38
@export var pre_bail_response: float = 8.0
@export var pre_bail_arm_open: float = 0.68
@export var pre_bail_torso_counter: float = 0.34
@export var pre_bail_pelvis_shift: float = 0.12
@export var pre_bail_leg_asymmetry: float = 0.24
@export var pre_bail_pole_trail: float = 0.28
