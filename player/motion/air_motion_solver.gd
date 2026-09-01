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
