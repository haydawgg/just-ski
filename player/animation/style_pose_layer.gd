class_name StylePoseLayer
extends RefCounted

func input_strength(frame: SkierAnimationFrame, style_pose_none: int) -> float:
	var legacy_strength := 1.0 if frame.style_pose != style_pose_none and frame.style_amount <= 0.0 else 0.0
	if frame.locomotion_state != 1 or frame.style_pose == style_pose_none:
		return 0.0
	return clampf(maxf(frame.style_amount, legacy_strength), 0.0, 1.0)

func phase_name(definition: Resource, pose_weight: float, input_strength_value: float) -> String:
	if definition == null or pose_weight < 0.01:
		return "IDLE"
	return "HOLD" if input_strength_value > 0.0 and pose_weight > 0.72 else ("SETUP" if input_strength_value > 0.0 else "RELEASE")
