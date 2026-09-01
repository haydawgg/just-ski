class_name GroundPoseLayer
extends RefCounted

## Policy-only ground presentation calculations. The coordinator owns the
## target dictionaries and applies the returned values to the rig.

func crouch_target(frame: SkierAnimationFrame, grounded: bool) -> float:
	return smoothstep(0.02, 1.0, frame.speed_ratio) if grounded else 0.0

func carve_target(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> float:
	var edge_strength := absf(clampf(frame.edge, -1.0, 1.0))
	if edge_strength < 0.01:
		return 0.0
	var speed_load := smoothstep(0.08, 0.9, clampf(frame.speed_ratio, 0.0, 1.0))
	var lateral_load := clampf(absf(frame.lateral_acceleration) / maxf(profile.lateral_acceleration_reference, 0.01), 0.0, 1.0)
	var turn_load := clampf(absf(frame.turn_rate) / maxf(profile.turn_rate_reference, 0.01), 0.0, 1.0)
	var intent := absf(clampf(frame.turn_input, -1.0, 1.0))
	var tracking := clampf(frame.carve_ratio, 0.0, 1.0) * (1.0 - clampf(frame.skid_ratio, 0.0, 1.0) * 0.72)
	var physical_load := maxf(lateral_load, turn_load * 0.82)
	var intensity := edge_strength * clampf(
		0.18 + speed_load * 0.22 + physical_load * 0.32 + tracking * 0.16 + intent * 0.12,
		0.0,
		1.0
	)
	if frame.braking:
		intensity *= 0.45
	return signf(frame.edge) * intensity

func slarve_target(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> float:
	if frame.locomotion_state != 0 or frame.braking:
		return 0.0
	var skid_demand := smoothstep(profile.slarve_skid_start, profile.slarve_skid_full, clampf(frame.skid_ratio, 0.0, 1.0))
	var heading_demand := smoothstep(0.08, maxf(profile.slarve_heading_reference, 0.09), absf(frame.heading_velocity_delta))
	return skid_demand * lerpf(0.58, 1.0, heading_demand)

func slarve_side(frame: SkierAnimationFrame) -> float:
	if frame.locomotion_state != 0 or frame.braking:
		return 0.0
	var side_source := frame.heading_velocity_delta if absf(frame.heading_velocity_delta) > 0.05 else frame.skid
	return signf(side_source) if absf(side_source) > 0.02 else 0.0
