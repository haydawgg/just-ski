class_name SkiPhysicsProfile
extends Resource

@export_category("Snow")
@export var gravity: float = 24.0
@export var air_gravity: float = 14.0
@export var base_drag: float = 0.024
@export var tuck_drag_multiplier: float = 0.42
@export var longitudinal_friction: float = 0.35
@export var lateral_friction: float = 9.5
@export var maximum_edge_grip: float = 28.0
@export var low_speed_steering: float = 2.2
@export var high_speed_steering: float = 1.35
@export var edge_response: float = 6.8
@export var edge_release: float = 3.4
@export var steering_speed_reference: float = 18.0
@export var full_steer_speed: float = 7.0
@export var sidecut: float = 0.022
@export var weathervane_rate: float = 2.8
@export var weathervane_edge: float = 0.22
@export var glide_acceleration: float = 2.0
@export var tip_grip_gain: float = 0.4
@export var pressure_grip_gain: float = 0.28
@export var pressure_glide_gain: float = 1.6
@export var ground_align_rate: float = 10.0
@export var skid_friction: float = 5.5
@export var brake_friction: float = 16.0
@export var maximum_speed: float = 48.0

@export_category("Jump and Air")
@export var pop_impulse: float = 8.2
@export var coyote_time: float = 0.14
@export var min_air_time: float = 0.1
@export var air_yaw_acceleration: float = 8.0
@export var air_flip_acceleration: float = 6.5
@export var air_roll_acceleration: float = 4.0
@export var air_angular_damping: float = 0.22
@export var air_landing_damping: float = 3.5
@export var air_landing_window: float = 0.22
@export var maximum_angular_speed: float = 9.0
@export var air_flip_trim_acceleration: float = 1.8

@export_category("Landing")
@export var clean_threshold: float = 0.72
@export var sketchy_threshold: float = 0.42
@export var bail_impact_speed: float = 18.0
@export var landing_assist_distance: float = 2.2
@export var bail_tumble_time: float = 1.05
@export var bail_speed_retain: float = 0.28

@export_category("Rails")
@export var rail_capture_radius: float = 1.1
@export var rail_min_speed: float = 3.0
@export var rail_friction: float = 0.75
@export var rail_balance_drift: float = 0.55
@export var rail_balance_input_gain: float = 2.4
@export var rail_balance_fail: float = 1.0
@export var rail_kink_instability: float = 0.85
@export var rail_boardslide_instability: float = 0.35
