class_name GrabPoseLayer
extends RefCounted

const CONTACT_ACQUIRE_CAP := 0.14
const CONTACT_MAINTAIN_CAP := 0.12
const CONTACT_HOLD_WEIGHT := 0.8

## Grab lifecycle policy. Reach and target transforms remain coordinator-owned
## because they depend on the selected rig adapter and live marker nodes.

func input_strength(frame: SkierAnimationFrame, grab_pose_none: int) -> float:
	var legacy_strength := 1.0 if frame.grab_pose != grab_pose_none and frame.grab_amount <= 0.0 and frame.grab_input_strength <= 0.0 else 0.0
	var strength := clampf(maxf(frame.grab_input_strength, maxf(frame.grab_amount, legacy_strength)), 0.0, 1.0)
	return 0.0 if frame.grab_pose == grab_pose_none else strength

func pose_target(input_strength_value: float, airborne: bool, air_time: float, minimum_air_time: float, landing_anticipation: float, current_weight: float, profile: SkierAnimationProfile) -> float:
	var readiness := clampf(air_time / maxf(minimum_air_time, 0.01), 0.0, 1.0) if airborne and air_time > 0.0 else (1.0 if airborne else 0.0)
	var target := input_strength_value * readiness
	if input_strength_value > 0.0 and landing_anticipation > 0.0:
		var held_landing_floor := profile.grab_late_hold_floor * input_strength_value
		var landing_target := maxf(held_landing_floor, target * (1.0 - profile.grab_landing_release_strength))
		target = lerpf(target, landing_target, landing_anticipation)
	return target

func should_latch_contact(definition: Resource, input_strength_value: float, airborne: bool, pose_weight: float, air_time: float, minimum_air_time: float, already_latched: bool, reach_error: float) -> bool:
	if definition == null or input_strength_value <= 0.0 or not airborne or pose_weight <= 0.48 or air_time < minimum_air_time:
		return false
	var threshold: float = float(definition.contact_maintain_distance) if already_latched else float(definition.contact_acquire_distance)
	threshold = minf(threshold, CONTACT_MAINTAIN_CAP if already_latched else CONTACT_ACQUIRE_CAP)
	return reach_error <= threshold

func phase_name(definition: Resource, pose_weight: float, input_strength_value: float, release_time: float, contact_weight: float, contact_latched: bool) -> String:
	if definition == null or pose_weight < 0.01:
		return "IDLE"
	if input_strength_value <= 0.0:
		return "RELEASE" if release_time > 0.0 and pose_weight > 0.16 else "RECOVER"
	if pose_weight < 0.28:
		return "SETUP"
	if contact_weight > CONTACT_HOLD_WEIGHT:
		return "HOLD"
	if contact_latched or contact_weight > 0.08:
		return "CONTACT"
	return "REACH"
