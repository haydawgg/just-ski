class_name FlickTrickProfile
extends Resource

@export_group("Gesture Recognition")
@export var setup_threshold := 0.55
@export var flick_threshold := 0.62
@export var center_reset_threshold := 0.28
@export var maximum_gesture_duration := 0.35
@export var input_buffer_seconds := 0.12
@export var repeat_cooldown := 0.10
@export var direction_sector_degrees := 35.0
@export var trigger_press_threshold := 0.35

@export_group("Preload Quality")
# A lower floor makes marginal takeoffs meaningfully weaker instead of granting
# nearly full rotation authority to every recognized gesture.
@export var minimum_command_strength := 0.35
@export var setup_duration_reference := 0.22
@export var release_velocity_window := 0.10
@export var release_speed_reference := 7.0
@export var setup_depth_weight := 0.45
@export var setup_duration_weight := 0.20
@export var release_speed_weight := 0.35

@export_group("Takeoff Rotation")
@export var spin_impulse := 6.9
@export var flip_impulse := 6.5
@export var cork_yaw_impulse := 4.8
@export var cork_roll_impulse := 5.2
# Total requested takeoff impulse is released through a normalized curve across
# this window, so the same gesture produces the same total at different tick rates.
@export var takeoff_release_duration := 0.14

@export_group("Air Management")
# Air input is intentionally subordinate to the takeoff. The normalized budget
# is consumed by repeated management gestures and never regenerates in an air.
@export var air_authority_budget := 0.32
@export var air_continue_fraction := 0.16
@export var air_check_fraction := 0.20
# Left-stick yaw is precision trim, not a second way to manufacture a spin.
@export var air_yaw_trim_acceleration := 0.5
