class_name LandingPoseLayer
extends RefCounted

## Landing readiness is a sampled-data policy and is intentionally independent
## of the coordinator's joint-target application.

func score_error(error: float, good: float, bad: float) -> float:
	if not is_finite(error) or not is_finite(good) or not is_finite(bad):
		return 0.0
	var good_limit := maxf(good, 0.0)
	var bad_limit := maxf(bad, good_limit + 0.001)
	return 1.0 - smoothstep(good_limit, bad_limit, absf(error))

func readiness_targets(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> Dictionary:
	var empty := {
		"valid": false,
		"inputs_valid": false,
		"heading": 0.0,
		"pitch": 0.0,
		"spin": 0.0,
		"upright": 0.0,
		"residual": 0.0,
		"projected_heading_error": 0.0,
		"projected_residual": 0.0,
	}
	if frame.locomotion_state != 1 or not frame.predicted_landing_valid or not is_finite(frame.predicted_landing_time) or frame.predicted_landing_time < 0.0:
		return empty
	var landing_normal := frame.predicted_landing_normal
	if not _finite_vector(landing_normal) or landing_normal.length_squared() <= 0.000001:
		return empty
	landing_normal = landing_normal.normalized()
	var time_to_contact := clampf(frame.predicted_landing_time, 0.0, 2.0)
	var body_up_valid := frame.body_up_valid and _finite_vector(frame.body_up) and frame.body_up.length_squared() > 0.000001
	var ski_forward_valid := frame.ski_forward_valid and _finite_vector(frame.ski_forward) and frame.ski_forward.length_squared() > 0.000001
	var ski_up_valid := frame.ski_up_valid and _finite_vector(frame.ski_up) and frame.ski_up.length_squared() > 0.000001
	var desired_heading_valid := _finite_vector(frame.velocity_heading) and frame.velocity_heading.length_squared() > 0.000001
	var local_angular_valid := _finite_vector(frame.angular_velocity)
	var world_angular_valid := frame.angular_velocity_world_valid and _finite_vector(frame.angular_velocity_world)
	var residual_valid := _finite_vector(frame.rotation_residual)
	var heading_valid := ski_forward_valid and desired_heading_valid and world_angular_valid
	var pitch_valid := ski_forward_valid and ski_up_valid
	var upright_valid := body_up_valid
	var spin_valid := local_angular_valid
	var maneuver_residual_valid := local_angular_valid and residual_valid
	var ski_forward := frame.ski_forward.normalized() if ski_forward_valid else Vector3.FORWARD
	var body_up := frame.body_up.normalized() if body_up_valid else Vector3.UP
	var heading := ski_forward.slide(landing_normal)
	var desired_heading := frame.velocity_heading.slide(landing_normal)
	var heading_error := 0.0
	if heading_valid and heading.length_squared() > 0.000001 and desired_heading.length_squared() > 0.000001:
		heading_error = heading.normalized().signed_angle_to(desired_heading.normalized(), landing_normal)
	else:
		heading_valid = false
	var projected_heading_error := 0.0
	if heading_valid and is_finite(heading_error):
		var yaw_rate_about_landing := frame.angular_velocity_world.dot(landing_normal)
		projected_heading_error = wrapf(heading_error + yaw_rate_about_landing * time_to_contact, -PI, PI)
	else:
		heading_valid = false
	var pitch_error := 0.0
	if pitch_valid:
		var ski_forward_plane := ski_forward.slide(landing_normal)
		if ski_forward_plane.length_squared() > 0.000001:
			pitch_error = absf(atan2(ski_forward.dot(landing_normal), ski_forward_plane.length()))
		else:
			pitch_valid = false
	var spin_error := frame.angular_velocity.length() if spin_valid else NAN
	var upright_error := acos(clampf(body_up.dot(landing_normal), -1.0, 1.0)) if upright_valid else NAN
	var projected_residual := 0.0
	if maneuver_residual_valid:
		var projected_residual_vector := Vector3(
			wrapf(frame.rotation_residual.x + frame.angular_velocity.x * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.y + frame.angular_velocity.y * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.z + frame.angular_velocity.z * time_to_contact, -PI, PI)
		)
		if _finite_vector(projected_residual_vector):
			projected_residual = maxf(absf(projected_residual_vector.x), maxf(absf(projected_residual_vector.y), absf(projected_residual_vector.z)))
		else:
			maneuver_residual_valid = false
	var inputs_valid := heading_valid and pitch_valid and spin_valid and upright_valid and maneuver_residual_valid
	return {
		"valid": true,
		"inputs_valid": inputs_valid,
		"heading": score_error(projected_heading_error, profile.landing_readiness_heading_good, profile.landing_readiness_heading_bad) if heading_valid else 0.0,
		"pitch": score_error(pitch_error, profile.landing_readiness_pitch_good, profile.landing_readiness_pitch_bad) if pitch_valid else 0.0,
		"spin": score_error(spin_error, profile.landing_readiness_spin_good, profile.landing_readiness_spin_bad) if spin_valid else 0.0,
		"upright": score_error(upright_error, profile.landing_readiness_upright_good, profile.landing_readiness_upright_bad) if upright_valid else 0.0,
		"residual": score_error(projected_residual, profile.landing_readiness_residual_good, profile.landing_readiness_residual_bad) if maneuver_residual_valid else 0.0,
		"projected_heading_error": projected_heading_error,
		"projected_residual": projected_residual,
	}

func ready_for_values(valid: bool, anticipation: float, readiness: float, profile: SkierAnimationProfile) -> bool:
	return valid and anticipation >= profile.ready_anticipation_threshold and readiness >= profile.ready_readiness_threshold

func _finite_vector(value: Vector3) -> bool:
	return value.is_finite()
