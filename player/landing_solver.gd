class_name LandingSolver
extends RefCounted

enum Outcome { CLEAN, SKETCHY, HARD, BAIL }

static func evaluate(up: Vector3, forward: Vector3, normal: Vector3, velocity: Vector3, angular_velocity: Vector3, profile: SkiPhysicsProfile) -> Dictionary:
	var tangent_velocity := velocity.slide(normal)
	var travel := tangent_velocity.normalized() if tangent_velocity.length() > 0.5 else forward
	var aligned_forward := absf(forward.slide(normal).normalized().dot(travel))
	var upright := clampf((up.dot(normal) + 0.15) / 1.15, 0.0, 1.0)
	var impact := maxf(0.0, -velocity.dot(normal))
	var impact_score := 1.0 - clampf(impact / profile.bail_impact_speed, 0.0, 1.0)
	var spin_score := 1.0 - clampf(angular_velocity.length() / profile.maximum_angular_speed, 0.0, 1.0)
	var score := aligned_forward * 0.32 + upright * 0.36 + impact_score * 0.22 + spin_score * 0.1
	var outcome := Outcome.BAIL
	if score >= profile.clean_threshold:
		outcome = Outcome.CLEAN
	elif score >= profile.sketchy_threshold:
		outcome = Outcome.SKETCHY
	elif impact < profile.bail_impact_speed * 0.85 and upright > 0.25:
		outcome = Outcome.HARD
	return {"score": score, "outcome": outcome, "impact": impact, "alignment": aligned_forward, "upright": upright}
