class_name SkierAnimationProfile
extends Resource

@export_category("Response")
@export var pose_response: float = 10.0
@export var fast_pose_response: float = 18.0
@export var secondary_response: float = 6.0

@export_category("Ground")
@export var neutral_knee_flex: float = 0.24
@export var speed_knee_flex: float = 0.22
@export var carve_hip_roll: float = 0.28
@export var carve_spine_roll: float = 0.2
@export var deep_carve_threshold: float = 0.62
@export var brake_ski_yaw: float = 0.72
@export var tuck_spine_pitch: float = 0.54
@export var tuck_arm_pitch: float = 1.05
@export var compression_depth: float = 0.26

@export_category("Air")
@export var air_tuck_strength: float = 0.7
@export var spin_compact_threshold: float = 2.2
@export var flip_compact_threshold: float = 1.8
@export var landing_anticipation_time: float = 0.55
@export var grab_reach: float = 1.0
@export var flick_setup_depth: float = 0.16
@export var flick_pop_extension: float = 0.12
@export var spin_head_spot: float = 0.68
@export var grab_chest_drop: float = 0.24
@export var grab_leg_tuck: float = 0.58

@export_category("Rail")
@export var rail_knee_flex: float = 0.56
@export var rail_balance_lean: float = 0.3
@export var rail_counter_rotation: float = 0.45

@export_category("Reactions")
@export var pop_duration: float = 0.24
@export var clean_landing_duration: float = 0.3
@export var sketchy_landing_duration: float = 0.62
@export var hard_landing_duration: float = 0.82
@export var bail_flail_speed: float = 7.0
