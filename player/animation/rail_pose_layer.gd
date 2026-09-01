class_name RailPoseLayer
extends RefCounted

func approach_target(frame: SkierAnimationFrame) -> float:
	return frame.rail_approach_anticipation if frame.locomotion_state != 2 else 0.0

func slide_target(rail_pose: int, maximum_angle: float) -> float:
	if rail_pose < 0:
		return -maximum_angle
	if rail_pose > 0:
		return maximum_angle
	return 0.0

func exit_target(distance_to_end: float, anticipation_distance: float) -> float:
	return clampf(1.0 - smoothstep(0.0, maxf(anticipation_distance, 0.05), distance_to_end), 0.0, 1.0)
