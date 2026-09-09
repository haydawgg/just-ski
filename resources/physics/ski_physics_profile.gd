class_name SkiPhysicsProfile
extends Resource

@export_category("Snow")
@export var gravity: float = 9.81
@export var air_gravity: float = 9.81
@export var base_drag: float = 0.009
@export var tuck_drag_multiplier: float = 0.55
@export var longitudinal_friction: float = 0.18
@export var lateral_friction: float = 4.8
@export var maximum_edge_grip: float = 12.5
@export var low_speed_steering: float = 0.85
@export var high_speed_steering: float = 0.62
@export var edge_response: float = 4.5
@export var edge_release: float = 3.0
@export var steering_speed_reference: float = 20.0
@export var full_steer_speed: float = 10.0
@export var minimum_steer_speed_gate: float = 0.16
@export var sidecut: float = 0.01
@export var weathervane_rate: float = 1.8
@export var weathervane_edge: float = 0.22
@export var brake_steer_multiplier: float = 1.25
@export var brake_speed_scrub_multiplier: float = 0.65
@export var tuck_steering_multiplier: float = 0.8
@export var low_speed_heading_travel_limit_degrees: float = 50.0
@export var high_speed_heading_travel_limit_degrees: float = 24.0
@export var heading_travel_limit_response: float = 5.5
@export var glide_acceleration: float = 0.35
@export var tip_grip_gain: float = 0.3
@export var pressure_grip_gain: float = 0.2
@export var pressure_glide_gain: float = 0.6
@export var ground_align_rate: float = 10.0
@export var skid_friction: float = 3.2
@export var brake_friction: float = 16.0
@export var maximum_speed: float = 38.0

@export_category("Ground Contact")
@export var ground_probe_distance: float = 1.45
@export var ground_probe_reach: float = 1.15
@export var ground_probe_origin_height: float = 0.35
@export var left_front_probe_offset: Vector3 = Vector3(-0.34, 0.0, -0.72)
@export var left_rear_probe_offset: Vector3 = Vector3(-0.34, 0.0, 0.72)
@export var right_front_probe_offset: Vector3 = Vector3(0.34, 0.0, -0.72)
@export var right_rear_probe_offset: Vector3 = Vector3(0.34, 0.0, 0.72)
@export var ground_attach_height: float = 0.19
@export var ground_attach_stiffness: float = 55.0
@export var ground_attach_max_accel: float = 24.0
@export var seat_approach_speed: float = 2.0
## Spawn-settle easing toward the support surface. The hard ceiling remains
## `seat_approach_speed`; this only shapes how quickly the approach speed
## responds as remaining seat clearance shrinks.
@export var spawn_settle_response: float = 8.0
@export_range(0.0, 89.0) var maximum_ground_angle_degrees: float = 62.0

func contact_probe_offsets() -> Array[Vector3]:
	return [
		left_front_probe_offset,
		left_rear_probe_offset,
		right_front_probe_offset,
		right_rear_probe_offset,
	]

@export_category("Surface Response")
@export var powder_drag_multiplier: float = 1.32
@export var powder_grip_multiplier: float = 0.78
@export var packed_drag_multiplier: float = 1.0
@export var packed_grip_multiplier: float = 1.0
@export var groomed_drag_multiplier: float = 0.82
@export var groomed_grip_multiplier: float = 1.12

@export_category("Jump and Air")
# Keep a charged keyboard pop as a controllable short hop; course jump sizing
# reads this same value so authored features and free pops stay calibrated.
@export var pop_impulse: float = 3.6
@export var maximum_jump_charge: float = 0.32
@export var minimum_pop_strength: float = 0.72
@export var coyote_time: float = 0.14
@export var min_air_time: float = 0.1
@export var air_angular_damping: float = 0.32
@export var air_landing_damping: float = 2.8
@export var air_landing_window: float = 0.28
@export var air_open_inertia_scale: float = 1.18
@export var air_compact_inertia_scale: float = 0.82
@export var air_inertia_response_rate: float = 12.0
@export var air_open_damping_multiplier: float = 1.65
@export var air_compact_damping_multiplier: float = 0.62
# The visible landing-open pose now owns most late-air slowdown. This retains a
# conservative safety layer without allowing assist to perform the rotation.
@export var air_landing_assist_damping_weight: float = 0.35
@export var maximum_angular_speed: float = 7.5
# Left-stick pitch is precision trim, not a replacement for takeoff trick authority.
@export var air_flip_trim_acceleration: float = 0.48
@export var air_terminal_speed: float = 45.0
@export var landing_prediction_seconds: float = 2.2
@export var landing_prediction_step: float = 0.06

@export_category("Landing Continuity")
@export var landing_orientation_settle_time_soft: float = 0.12
@export var landing_orientation_settle_time_hard: float = 0.22
@export var landing_orientation_max_rate_degrees: float = 240.0
@export var landing_residual_angular_damping: float = 14.0
@export var landing_residual_yaw_transfer: float = 0.30
@export var landing_residual_tilt_transfer: float = 0.10

@export_category("Landing")
@export var clean_threshold: float = 0.72
@export var sketchy_threshold: float = 0.42
@export var bail_impact_speed: float = 15.0
@export var clean_upright_dot: float = 0.78
@export var sketchy_upright_dot: float = 0.5
@export var recoverable_upright_dot: float = 0.22
@export var clean_impact_ratio: float = 0.62
@export var sketchy_impact_ratio: float = 0.82
@export var bail_angular_ratio: float = 0.85
@export var landing_alignment_weight: float = 0.32
@export var landing_upright_weight: float = 0.36
@export var landing_impact_weight: float = 0.22
@export var landing_angular_weight: float = 0.1
@export var landing_impact_severity_scale: float = 1.25
@export var landing_impact_body_roll_weight: float = 0.2
@export var landing_flat_surface_bias_start: float = 0.82
@export var landing_flat_surface_bias_end: float = 0.98
@export var landing_flat_surface_bias_weight: float = 0.18
@export var landing_balance_alignment_weight: float = 0.45
@export var landing_balance_upright_weight: float = 0.3
@export var landing_balance_angular_weight: float = 0.25
@export var landing_balance_lateral_weight: float = 0.2
@export var landing_balance_lateral_speed_reference: float = 8.0
@export var sketchy_landing_speed_retain: float = 0.78
@export var hard_landing_speed_retain: float = 0.48
@export var landing_control_penalty_max: float = 0.32
@export var landing_control_recovery_time_soft: float = 0.25
@export var landing_control_recovery_time_hard: float = 0.45
@export var bail_ground_damping: float = 2.8
@export var bail_ground_align_rate: float = 6.0
@export var bail_recovery_speed_retain: float = 0.55

@export_category("Crash")
@export var feature_collision_min_speed: float = 6.0
@export var feature_collision_min_normal_speed: float = 4.5
@export_range(0.0, 1.0) var feature_collision_max_speed_retention: float = 0.65
@export var crash_min_duration: float = 0.35
@export var crash_rest_confirm_time: float = 0.12
@export var crash_rest_hold_time: float = 0.32
@export var crash_rest_speed: float = 1.25
@export var crash_rest_angular_speed: float = 0.45
@export var crash_max_duration: float = 2.4
@export var crash_air_angular_damping: float = 1.1
@export var crash_ground_angular_damping: float = 4.0

@export_category("Rails")
@export var rail_capture_radius: float = 1.1
@export var rail_min_speed: float = 3.0
@export var rail_friction: float = 0.75
@export var rail_balance_drift: float = 0.55
@export var rail_balance_input_gain: float = 2.4
@export var rail_balance_fail: float = 1.0
@export var rail_kink_instability: float = 0.85
@export var rail_boardslide_instability: float = 0.35
@export var rail_capture_blend_time: float = 0.11
@export var rail_capture_max_snap: float = 1.15
@export var rail_alignment_rate: float = 12.0
@export var rail_pop_strength: float = 0.72
@export var rail_slip_speed_retain: float = 0.55
@export var rail_slip_lateral_speed: float = 3.5
@export var rail_slip_upward_speed: float = 1.2
@export var rail_entry_severity_speed_reference: float = 6.0
@export var rail_preview_radius: float = 3.2
