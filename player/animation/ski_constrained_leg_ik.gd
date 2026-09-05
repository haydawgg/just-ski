class_name SkiConstrainedLegIK
extends RefCounted

var _last_poles: Dictionary = {}

func reset() -> void:
	_last_poles.clear()

func solve_leg(
	hip: Node3D,
	knee: Node3D,
	boot: Node3D,
	target_boot_world: Transform3D,
	preferred_pole_world: Vector3,
	weight: float,
	maximum_angular_rate: float,
	delta: float,
	side: StringName
) -> Dictionary:
	var result := {
		"valid": false,
		"reach_ratio": 0.0,
		"knee_correction": 0.0,
		"infeasibility": 1.0,
		"pole": preferred_pole_world,
	}
	if hip == null or knee == null or boot == null or weight <= 0.001:
		return result
	var hip_position := hip.global_position
	var target_position := target_boot_world.origin
	var target_delta := target_position - hip_position
	var target_distance := target_delta.length()
	var thigh_length := maxf(knee.position.length(), 0.001)
	var shin_length := maxf(boot.position.length(), 0.001)
	var maximum_reach := maxf(thigh_length + shin_length - 0.012, 0.02)
	var minimum_reach := absf(thigh_length - shin_length) + 0.025
	var clamped_distance := clampf(target_distance, minimum_reach, maximum_reach)
	var infeasibility := absf(target_distance - clamped_distance) / maximum_reach
	if target_distance <= 0.0001:
		return result
	var direction := target_delta / target_distance
	var pole := preferred_pole_world.slide(direction)
	if pole.length_squared() <= 0.0001:
		pole = (_last_poles.get(side, -hip.global_basis.z) as Vector3).slide(direction)
	if pole.length_squared() <= 0.0001:
		pole = hip.global_basis.x.slide(direction)
	pole = pole.normalized()
	var previous_pole := _last_poles.get(side, pole) as Vector3
	if pole.dot(previous_pole) < 0.0:
		pole = -pole
	_last_poles[side] = pole
	var along := (clamped_distance * clamped_distance + thigh_length * thigh_length - shin_length * shin_length) / (2.0 * clamped_distance)
	var height := sqrt(maxf(thigh_length * thigh_length - along * along, 0.0))
	var desired_knee := hip_position + direction * along + pole * height
	var thigh_current := (knee.global_position - hip_position).normalized()
	var thigh_target := (desired_knee - hip_position).normalized()
	var hip_correction := thigh_current.angle_to(thigh_target)
	_rotate_toward_direction(hip, thigh_current, thigh_target, weight, maximum_angular_rate, delta)
	var knee_position := knee.global_position
	var shin_current := (boot.global_position - knee_position).normalized()
	var shin_target := (target_position - knee_position).normalized()
	var knee_correction := shin_current.angle_to(shin_target)
	_rotate_toward_direction(knee, shin_current, shin_target, weight, maximum_angular_rate, delta)
	_clamp_local_euler(hip, Vector3(-1.4, -0.7, -0.72), Vector3(0.72, 0.7, 0.72))
	# Canonical knees flex on +X. Reject the mathematically equivalent negative
	# Euler branch so a terrain discontinuity cannot flip the knee backward.
	_clamp_local_euler(knee, Vector3(0.0, -0.28, -0.35), Vector3(2.3, 0.28, 0.35))
	var current_boot_basis := boot.global_basis.orthonormalized()
	var target_boot_basis := target_boot_world.basis.orthonormalized()
	var orientation_weight := _bounded_weight(
		Quaternion(current_boot_basis).angle_to(Quaternion(target_boot_basis)),
		weight,
		maximum_angular_rate,
		delta
	)
	boot.global_basis = Basis(Quaternion(current_boot_basis).slerp(Quaternion(target_boot_basis), orientation_weight)).orthonormalized()
	_clamp_local_euler(boot, Vector3(-0.9, -0.45, -0.5), Vector3(0.55, 0.45, 0.5))
	result.valid = _finite_transform(boot.global_transform)
	result.reach_ratio = target_distance / maximum_reach
	result.knee_correction = knee_correction
	result.infeasibility = clampf(infeasibility, 0.0, 1.0)
	result.pole = pole
	return result

func _rotate_toward_direction(node: Node3D, current: Vector3, target: Vector3, weight: float, maximum_rate: float, delta: float) -> void:
	if current.length_squared() <= 0.0001 or target.length_squared() <= 0.0001:
		return
	var angle := current.angle_to(target)
	if angle <= 0.00001:
		return
	var correction := Quaternion(current, target)
	var current_basis := node.global_basis.orthonormalized()
	var desired := (Basis(correction) * current_basis).orthonormalized()
	var bounded := _bounded_weight(angle, weight, maximum_rate, delta)
	node.global_basis = Basis(Quaternion(current_basis).slerp(Quaternion(desired), bounded)).orthonormalized()

func _bounded_weight(angle: float, weight: float, maximum_rate: float, delta: float) -> float:
	if angle <= 0.00001:
		return clampf(weight, 0.0, 1.0)
	return minf(clampf(weight, 0.0, 1.0), maxf(maximum_rate, 0.01) * maxf(delta, 0.0) / angle)

func _clamp_local_euler(node: Node3D, minimum: Vector3, maximum: Vector3) -> void:
	var value := node.rotation
	node.rotation = Vector3(
		clampf(value.x, minimum.x, maximum.x),
		clampf(value.y, minimum.y, maximum.y),
		clampf(value.z, minimum.z, maximum.z)
	)

func _finite_transform(value: Transform3D) -> bool:
	var values := [
		value.origin.x, value.origin.y, value.origin.z,
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
	]
	for item: float in values:
		if not is_finite(item):
			return false
	return true
