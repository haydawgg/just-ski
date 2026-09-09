class_name CrashReactionLayer
extends RefCounted

const TRAVEL_EPSILON := 0.08

func step_pre_bail(current_weight: float, current_side: float, frame: SkierAnimationFrame, delta: float, profile: SkierAnimationProfile) -> Dictionary:
	var target := clampf(frame.pre_bail_weight, 0.0, 1.0) if frame.locomotion_state == 1 else 0.0
	var response := profile.pre_bail_response if target > current_weight else profile.secondary_release_response
	var weight := lerpf(current_weight, target, 1.0 - exp(-response * delta))
	var side := lerpf(current_side, clampf(frame.pre_bail_side, -1.0, 1.0), 1.0 - exp(-response * delta))
	return {"weight": weight, "side": side}

func is_crash_stage(stage: int) -> bool:
	return stage in [CrashContext.Stage.RELEASE, CrashContext.Stage.IMPACT, CrashContext.Stage.FALL, CrashContext.Stage.REST, CrashContext.Stage.RECOVERY]

func crash_surface_normal(frame: SkierAnimationFrame) -> Vector3:
	var normal := frame.ground_normal
	if not _finite_vector(normal) or normal.length_squared() < 0.0001:
		normal = frame.crash_impact_normal
	if not _finite_vector(normal) or normal.length_squared() < 0.0001:
		return Vector3.UP
	return normal.normalized()

func skier_local_travel(frame: SkierAnimationFrame) -> Dictionary:
	var result := {
		"valid": false,
		"travel": Vector3.ZERO,
		"local": Vector3.ZERO,
		"forward": 0.0,
		"lateral": 0.0,
		"speed": 0.0,
		"influence": 0.0,
	}
	var normal := crash_surface_normal(frame)
	var travel := frame.crash_current_velocity.slide(normal)
	if not _finite_vector(travel):
		return result
	result["travel"] = travel
	var speed := travel.length()
	result["speed"] = speed
	result["influence"] = clampf(speed / 7.0, 0.0, 1.0)
	if speed < TRAVEL_EPSILON:
		return result
	var forward := frame.ski_forward if frame.ski_forward_valid else Vector3.ZERO
	var up := frame.body_up if frame.body_up_valid else Vector3.ZERO
	if not _finite_vector(forward) or forward.length_squared() < 0.0001:
		return result
	if not _finite_vector(up) or up.length_squared() < 0.0001:
		up = normal
	forward = forward.slide(normal)
	if forward.length_squared() < 0.0001:
		return result
	forward = forward.normalized()
	up = up.normalized()
	var right := forward.cross(up)
	if not _finite_vector(right) or right.length_squared() < 0.0001:
		right = forward.cross(normal)
	if not _finite_vector(right) or right.length_squared() < 0.0001:
		return result
	right = right.normalized()
	var local_forward := travel.dot(forward) / speed
	var local_lateral := travel.dot(right) / speed
	if not is_finite(local_forward) or not is_finite(local_lateral):
		return result
	result["valid"] = true
	result["local"] = Vector3(local_lateral, 0.0, local_forward)
	result["forward"] = local_forward
	result["lateral"] = local_lateral
	return result

func fall_travel_sprawl(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> Dictionary:
	var travel := skier_local_travel(frame)
	var influence := float(travel.get("influence", 0.0))
	var forward := float(travel.get("forward", 0.0))
	var lateral := float(travel.get("lateral", 0.0))
	var valid := bool(travel.get("valid", false))
	if not valid:
		influence = 0.0
		forward = 0.0
		lateral = 0.0
	var directional := profile.crash_directional_response
	var pitch := -forward * profile.crash_sprawl_pelvis_pitch * influence
	var yaw := lateral * profile.crash_sprawl_pelvis_yaw * influence
	var roll := lateral * profile.crash_sprawl_pelvis_roll * influence
	var fold := maxf(forward, 0.0) * profile.crash_sprawl_torso_fold * influence
	var back_arch := maxf(-forward, 0.0) * profile.crash_sprawl_torso_fold * 0.65 * influence
	var arm := profile.crash_sprawl_arm_spread * influence * directional
	var drag := profile.crash_sprawl_leg_drag * influence
	var ski_yaw := profile.crash_sprawl_ski_yaw * influence
	return {
		"valid": valid,
		"forward": forward,
		"lateral": lateral,
		"influence": influence,
		"speed": float(travel.get("speed", 0.0)),
		"travel": travel.get("travel", Vector3.ZERO),
		"local": travel.get("local", Vector3.ZERO),
		"pelvis": Vector3(pitch - fold * 0.35 + back_arch * 0.2, yaw, roll),
		"spine": Vector3(-fold + back_arch, -lateral * 0.08 * influence, roll * 0.55),
		"chest": Vector3(-fold * 0.85 + back_arch * 0.4, -lateral * 0.12 * influence, roll * 0.7),
		"head": Vector3(fold * 0.2, lateral * 0.12 * influence, -roll * 0.28),
		"left_shoulder": Vector3(-arm * (0.35 + maxf(-lateral, 0.0)), 0.08 * influence, -arm * (0.55 + maxf(lateral, 0.0) * 0.35)),
		"right_shoulder": Vector3(-arm * (0.35 + maxf(lateral, 0.0)), -0.08 * influence, arm * (0.55 + maxf(-lateral, 0.0) * 0.35)),
		"left_hip": Vector3(-drag * (0.55 + maxf(-forward, 0.0) * 0.4), 0.04 * influence, -lateral * drag),
		"right_hip": Vector3(-drag * (0.55 + maxf(-forward, 0.0) * 0.4), -0.04 * influence, lateral * drag),
		"left_knee": Vector3(drag * (0.7 + maxf(forward, 0.0) * 0.35), 0.0, -lateral * drag * 0.45),
		"right_knee": Vector3(drag * (0.7 + maxf(forward, 0.0) * 0.35), 0.0, lateral * drag * 0.45),
		"left_ski": Vector3(0.0, -ski_yaw * (0.4 + lateral * 0.35), -lateral * ski_yaw * 0.4),
		"right_ski": Vector3(0.0, ski_yaw * (0.4 - lateral * 0.35), lateral * ski_yaw * 0.4),
	}

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
