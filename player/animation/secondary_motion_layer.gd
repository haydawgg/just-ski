class_name SecondaryMotionLayer
extends RefCounted

func acceleration_activity(lateral: float, vertical: float, yaw: float, profile: SkierAnimationProfile) -> float:
	return maxf(
		absf(lateral) / maxf(profile.secondary_max_lateral_accel, 0.01),
		maxf(absf(vertical) / maxf(profile.secondary_max_vertical_accel, 0.01), absf(yaw) / maxf(profile.secondary_max_yaw_accel, 0.01))
	)

func state_activity(landing_compression: float, rail_compression: float, trick_weight: float, grab_weight: float, crossover: float) -> float:
	return maxf(landing_compression, maxf(rail_compression, maxf(trick_weight, maxf(grab_weight, crossover))))

func target(acceleration: float, state: float, speed_ratio: float, bail: bool) -> float:
	if bail:
		return 0.0
	return clampf(acceleration * 0.62 + state * 0.48 + smoothstep(0.08, 0.85, clampf(speed_ratio, 0.0, 1.0)) * 0.16, 0.0, 1.0)
