class_name LandingSolver
extends RefCounted

enum Outcome { CLEAN, SKETCHY, HARD, BAIL }

static func evaluate(up: Vector3, forward: Vector3, normal: Vector3, velocity: Vector3, angular_velocity: Vector3, profile: SkiPhysicsProfile) -> Dictionary:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var safe_up := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var safe_forward := forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var tangent_velocity := velocity.slide(safe_normal)
	var travel := tangent_velocity.normalized() if tangent_velocity.length() > 0.5 else safe_forward
	var projected_forward := safe_forward.slide(safe_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = travel
	var aligned_forward := absf(projected_forward.normalized().dot(travel))
	var upright_dot := clampf(safe_up.dot(safe_normal), -1.0, 1.0)
	var upright := clampf((upright_dot + 0.15) / 1.15, 0.0, 1.0)
	var impact := maxf(0.0, -velocity.dot(safe_normal))
	var impact_score := 1.0 - clampf(impact / profile.bail_impact_speed, 0.0, 1.0)
	var angular_ratio := angular_velocity.length() / maxf(profile.maximum_angular_speed, 0.01)
	var spin_score := 1.0 - clampf(angular_ratio, 0.0, 1.0)
	var score := aligned_forward * 0.32 + upright * 0.36 + impact_score * 0.22 + spin_score * 0.1
	var outcome := Outcome.BAIL
	var hard_failure := (
		upright_dot < profile.recoverable_upright_dot
		or impact >= profile.bail_impact_speed
		or angular_ratio >= profile.bail_angular_ratio
	)
	if not hard_failure and score >= profile.clean_threshold and upright_dot >= profile.clean_upright_dot and impact <= profile.bail_impact_speed * profile.clean_impact_ratio:
		outcome = Outcome.CLEAN
	elif not hard_failure and score >= profile.sketchy_threshold and upright_dot >= profile.sketchy_upright_dot and impact <= profile.bail_impact_speed * profile.sketchy_impact_ratio:
		outcome = Outcome.SKETCHY
	elif not hard_failure:
		outcome = Outcome.HARD
	return {
		"score": score,
		"outcome": outcome,
		"impact": impact,
		"alignment": aligned_forward,
		"upright": upright,
		"upright_dot": upright_dot,
		"angular_ratio": angular_ratio,
		"hard_failure": hard_failure,
	}
