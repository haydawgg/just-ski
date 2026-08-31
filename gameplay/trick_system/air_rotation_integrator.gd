class_name AirRotationIntegrator
extends RefCounted

static func integrate_basis(current_basis: Basis, local_angular_velocity: Vector3, delta: float) -> Basis:
	var safe_basis := current_basis.orthonormalized()
	var dt := maxf(delta, 0.0)
	var angular_speed := local_angular_velocity.length()
	if dt <= 0.0 or angular_speed <= 0.000001:
		return safe_basis
	var local_axis := local_angular_velocity / angular_speed
	var incremental_rotation := Basis(Quaternion(local_axis, angular_speed * dt))
	# Right multiplication applies the angular step in the skier's local/body
	# frame. This replaces ordered X/Y/Z Euler updates with one combined step.
	return (safe_basis * incremental_rotation).orthonormalized()

static func local_to_world_angular_velocity(current_basis: Basis, local_angular_velocity: Vector3) -> Vector3:
	return current_basis.orthonormalized() * local_angular_velocity
