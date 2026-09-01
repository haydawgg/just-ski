class_name SecondaryMotionResult
extends RefCounted

## Complete output of one secondary-motion sample. The coordinator consumes
## these values for presentation application and public debug snapshots.

var state_transition_weight := 1.0
var filtered_lateral_accel := 0.0
var filtered_vertical_accel := 0.0
var filtered_yaw_accel := 0.0
var filtered_heading_delta := 0.0
var landing_compression_velocity := 0.0
var torso_follow_through := Vector3.ZERO
var head_stabilization := Vector3.ZERO
var left_arm_inertia := Vector3.ZERO
var right_arm_inertia := Vector3.ZERO
var left_pole_inertia := Vector3.ZERO
var right_pole_inertia := Vector3.ZERO
var leg_rebound := 0.0
var secondary_motion_weight := 0.0

func reset() -> void:
	state_transition_weight = 1.0
	filtered_lateral_accel = 0.0
	filtered_vertical_accel = 0.0
	filtered_yaw_accel = 0.0
	filtered_heading_delta = 0.0
	landing_compression_velocity = 0.0
	torso_follow_through = Vector3.ZERO
	head_stabilization = Vector3.ZERO
	left_arm_inertia = Vector3.ZERO
	right_arm_inertia = Vector3.ZERO
	left_pole_inertia = Vector3.ZERO
	right_pole_inertia = Vector3.ZERO
	leg_rebound = 0.0
	secondary_motion_weight = 0.0
