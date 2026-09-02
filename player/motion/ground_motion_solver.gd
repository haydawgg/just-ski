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

func resolve_handling(
	planar_speed: float,
	edge: float,
	brake: float,
	tuck: float,
	pressure: float,
	tip_load: float,
	landing_control: float,
	surface_grip: float,
	profile: SkiPhysicsProfile
) -> GroundMotionResult:
	var result := GroundMotionResult.new()
	result.speed_ratio = clampf(planar_speed / maxf(profile.steering_speed_reference, 1.0), 0.0, 1.0)
	var steer_rate := lerpf(profile.low_speed_steering, profile.high_speed_steering, result.speed_ratio)
	var speed_gate := clampf(planar_speed / maxf(profile.full_steer_speed, 1.0), profile.minimum_steer_speed_gate, 1.0)
	if brake > 0.01:
		steer_rate *= lerpf(1.0, profile.brake_steer_multiplier, brake)
		speed_gate = lerpf(speed_gate, 1.0, brake)
	steer_rate *= speed_gate * lerpf(1.0, profile.tuck_steering_multiplier, tuck)
	result.effective_steer_rate = (steer_rate + planar_speed * profile.sidecut) * lerpf(landing_control, 1.0, brake)
	result.centripetal_demand = planar_speed * absf(edge) * result.effective_steer_rate
	var tip_scale := clampf(1.0 + (tip_load + pressure * 0.35) * profile.tip_grip_gain, 0.7, 1.22)
	tip_scale *= clampf(1.0 + pressure * profile.pressure_grip_gain, 0.78, 1.28)
	result.available_grip = (profile.lateral_friction + absf(edge) * profile.maximum_edge_grip * lerpf(0.82, 1.0, result.speed_ratio)) * surface_grip * tip_scale
	if brake > 0.01:
		result.available_grip = lerpf(result.available_grip, maxf(result.available_grip, profile.brake_friction), brake)
	result.carve_ratio = 1.0 if result.centripetal_demand <= 0.05 else clampf(result.available_grip / result.centripetal_demand, 0.0, 1.0)
	return result
