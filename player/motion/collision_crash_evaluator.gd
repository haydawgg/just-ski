class_name CollisionCrashEvaluator
extends RefCounted

## Turns post-motion collision diagnostics into one CrashContext, keeping the
## controller as the only owner of the enter_crash seam.

func evaluate(
	diagnostics: Array[Dictionary],
	state: int,
	minimum_speed: float,
	minimum_normal_speed: float,
	maximum_speed_retention: float,
	angular_speed: float,
	body_basis: Basis,
	velocity_fallback: Vector3
) -> CrashContext:
	if state not in [0, 1]:
		return null
	for diagnostic: Dictionary in diagnostics:
		if (int(diagnostic.get("collider_layer", 0)) & 4) == 0:
			continue
		var speed_before := float(diagnostic.get("speed_before", 0.0))
		var incoming_normal_speed := float(diagnostic.get("incoming_normal_speed", 0.0))
		var speed_retention := float(diagnostic.get("speed_retention", 1.0))
		if speed_before < minimum_speed or incoming_normal_speed < minimum_normal_speed or speed_retention > maximum_speed_retention:
			continue
		var normal := diagnostic.get("normal", Vector3.UP) as Vector3
		var before := diagnostic.get("velocity_before", velocity_fallback) as Vector3
		var after := diagnostic.get("velocity_after", velocity_fallback) as Vector3
		var context := CrashContext.new()
		context.begin(
			CrashContext.Reason.FEATURE_IMPACT,
			CrashContext.Source.OBSTACLE,
			state,
			before,
			after,
			normal,
			incoming_normal_speed,
			angular_speed,
			0.0,
			0.0,
			clampf(-normal.dot(body_basis.x), -1.0, 1.0)
		)
		context.attach_collision_diagnostic(diagnostic)
		return context
	return null
