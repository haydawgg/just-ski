class_name SkierGrabReachRequest
extends RefCounted

## Presentation-only request consumed by a rig adapter after the canonical pose
## has been retargeted. The target remains a live marker so equipment motion from
## the current frame is observed by the production solver.
var side: StringName = &""
var target_marker: Node3D
var weight: float = 0.0
var clavicle_assist_scale: float = 1.0

func configure(value_side: StringName, value_target_marker: Node3D, value_weight: float, value_clavicle_assist_scale: float = 1.0) -> SkierGrabReachRequest:
	side = value_side
	target_marker = value_target_marker
	weight = clampf(value_weight, 0.0, 1.0)
	clavicle_assist_scale = clampf(value_clavicle_assist_scale, 0.0, 1.0)
	return self
