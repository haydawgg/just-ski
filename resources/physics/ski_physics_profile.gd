class_name SkiPhysicsProfile
extends Resource

@export_category("Snow")
@export var gravity: float = 25.0
@export var base_drag: float = 0.045
@export var tuck_drag_multiplier: float = 0.42
@export var longitudinal_friction: float = 0.35
@export var lateral_friction: float = 7.5
@export var maximum_edge_grip: float = 22.0
@export var low_speed_steering: float = 2.4
@export var high_speed_steering: float = 1.0
@export var edge_response: float = 5.5
@export var brake_friction: float = 13.0
@export var maximum_speed: float = 48.0

@export_category("Jump and Air")
@export var pop_impulse: float = 8.2
@export var coyote_time: float = 0.1
@export var air_yaw_acceleration: float = 8.0
@export var air_flip_acceleration: float = 6.5
@export var air_roll_acceleration: float = 4.0
@export var air_angular_damping: float = 0.65
@export var maximum_angular_speed: float = 9.0

@export_category("Landing")
@export var clean_threshold: float = 0.72
@export var sketchy_threshold: float = 0.42
@export var bail_impact_speed: float = 18.0
@export var landing_assist_distance: float = 2.2

@export_category("Rails")
@export var rail_capture_radius: float = 1.1
@export var rail_min_speed: float = 3.0
@export var rail_friction: float = 0.75
