class_name LandingTransition
extends RefCounted

## Landing classification is a pure transition boundary. Assist is explicit so
## the controller can preserve the existing post-rotation ordering.

func evaluate(
	up: Vector3,
	forward: Vector3,
	normal: Vector3,
	velocity: Vector3,
	angular_velocity: Vector3,
	profile: SkiPhysicsProfile
) -> LandingTransitionResult:
	return LandingTransitionResult.new(LandingSolver.evaluate(up, forward, normal, velocity, angular_velocity, profile))

func apply_assist(result: LandingTransitionResult, assist: float, profile: SkiPhysicsProfile) -> void:
	if result == null or int(result.data.get("outcome", LandingSolver.Outcome.BAIL)) == LandingSolver.Outcome.BAIL:
		return
	var values := result.data
	var assisted_score := minf(1.0, float(values.get("score", 0.0)) + assist * 0.06)
	values["score"] = assisted_score
	if assisted_score >= profile.clean_threshold and float(values.get("upright_dot", 0.0)) >= profile.clean_upright_dot and float(values.get("impact", 0.0)) <= profile.bail_impact_speed * profile.clean_impact_ratio:
		values["outcome"] = LandingSolver.Outcome.CLEAN
	elif assisted_score >= profile.sketchy_threshold and float(values.get("upright_dot", 0.0)) >= profile.sketchy_upright_dot and float(values.get("impact", 0.0)) <= profile.bail_impact_speed * profile.sketchy_impact_ratio:
		values["outcome"] = LandingSolver.Outcome.SKETCHY
	else:
		values["outcome"] = LandingSolver.Outcome.HARD
