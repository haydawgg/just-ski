class_name AirMotionSolver
extends RefCounted

## Air motion owns only sampled ballistic policy; angular integration remains
## with the controller's authoritative rotation state.

func step_gravity(current_velocity: Vector3, delta: float, gravity: float, terminal_speed: float) -> AirMotionResult:
	var result := AirMotionResult.new()
	result.velocity = current_velocity + Vector3.DOWN * gravity * delta
	result.velocity.y = maxf(result.velocity.y, -terminal_speed)
	return result

func landing_assist_availability(predicted_time: float, landing_window: float) -> float:
	return smoothstep(0.0, 1.0, predicted_time / maxf(landing_window, 0.01)) if predicted_time >= 0.0 else 1.0

func angular_damping(compactness: float, predicted_time: float, landing_assist: float, rotation_active: bool, profile: SkiPhysicsProfile) -> float:
	var body_multiplier := lerpf(
		profile.air_open_damping_multiplier,
		profile.air_compact_damping_multiplier,
		clampf(compactness, 0.0, 1.0)
	) if rotation_active else 1.0
	var damping := profile.air_angular_damping * body_multiplier
	if predicted_time >= 0.0 and predicted_time < profile.air_landing_window:
		var proximity := 1.0 - predicted_time / maxf(profile.air_landing_window, 0.01)
		var assist_weight := proximity * clampf(landing_assist, 0.0, 1.0) * profile.air_landing_assist_damping_weight
		damping = lerpf(damping, profile.air_landing_damping, assist_weight)
	return maxf(damping, 0.0)
