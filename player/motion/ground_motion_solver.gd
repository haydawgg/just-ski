class_name GroundMotionSolver
extends RefCounted

## Ground policy receives sampled contact/input values and returns a transition
## result. It never reads InputManager or mutates a CharacterBody3D.

func resolve_contact(grounded: bool, current_coyote: float, delta: float, coyote_time: float) -> GroundMotionResult:
	var result := GroundMotionResult.new()
	if grounded:
		result.coyote_remaining = maxf(coyote_time, 0.0)
		return result
	result.coyote_remaining = current_coyote - maxf(delta, 0.0)
	result.should_enter_air = result.coyote_remaining <= 0.0
	return result

func constrain_heading_to_travel(
	candidate: Vector3,
	velocity: Vector3,
	normal: Vector3,
	speed_ratio: float,
	delta: float,
	low_speed_limit_degrees: float,
	high_speed_limit_degrees: float,
	response: float
) -> Vector3:
	var travel := velocity.slide(normal)
	if travel.length_squared() <= 0.01:
		return candidate
	travel = travel.normalized()
	if candidate.dot(travel) < 0.0:
		travel = -travel
	var maximum_angle := deg_to_rad(lerpf(low_speed_limit_degrees, high_speed_limit_degrees, speed_ratio))
	var signed_angle := travel.signed_angle_to(candidate, normal)
	var excess := absf(signed_angle) - maximum_angle
	if excess <= 0.0:
		return candidate
	var correction := minf(excess, response * delta)
	return candidate.rotated(normal, -signf(signed_angle) * correction).normalized()
