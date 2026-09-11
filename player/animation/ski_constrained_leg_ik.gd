class_name SkiConstrainedLegIK
extends RefCounted

const FEATURE_MASK := 4
const CONTACT_LIFT := 0.04

var _last_poles: Dictionary = {}
var _last_rotations: Dictionary = {}

func reset() -> void:
	_last_poles.clear()
	_last_rotations.clear()

## Enforce a minimum lateral boot stance so crossed ski targets can never form
## an X-shaped configuration. Separation is applied along the pelvis lateral
## axis in world space and is idempotent once the stance is satisfied.
static func separate_boot_targets(left_target: Vector3, right_target: Vector3, pelvis_global_basis: Basis, min_stance: float) -> Array:
	var lateral := pelvis_global_basis.x
	if lateral.length_squared() < 0.5 or not lateral.is_finite():
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	var separation := (right_target - left_target).dot(lateral)
	if separation >= min_stance:
		return [left_target, right_target]
	var push := (min_stance - separation) * 0.5
	return [left_target - lateral * push, right_target + lateral * push]

## Enforce a minimum lateral span between the ski nose pair and tail pair so
## ski bodies cannot overlap when per-side yaw differs (boot stance alone only
## separates the boot points). Push offsets apply to the boot targets along the
## lateral axis and are idempotent once the span is satisfied.
## Ski half-length matches SkierEquipment.SKI_SIZE.z * 0.5; kept as a local
## constant so this RefCounted helper does not depend on the equipment module.
const SKI_HALF_LENGTH := 0.91

static func separate_ski_span(
	left_boot: Vector3,
	right_boot: Vector3,
	left_forward: Vector3,
	right_forward: Vector3,
	lateral: Vector3,
	min_span: float
) -> Array:
	var axis := lateral
	if axis.length_squared() < 0.5 or not axis.is_finite():
		axis = Vector3.RIGHT
	else:
		axis = axis.normalized()
	var left_fwd := left_forward if left_forward.is_finite() and left_forward.length_squared() > 0.0001 else Vector3.ZERO
	var right_fwd := right_forward if right_forward.is_finite() and right_forward.length_squared() > 0.0001 else Vector3.ZERO
	if left_fwd.length_squared() <= 0.0001 and right_fwd.length_squared() <= 0.0001:
		return [left_boot, right_boot]
	left_fwd = left_fwd.normalized() if left_fwd.length_squared() > 0.0001 else Vector3.ZERO
	right_fwd = right_fwd.normalized() if right_fwd.length_squared() > 0.0001 else Vector3.ZERO
	var push := 0.0
	for end_sign: float in [1.0, -1.0]:
		var left_end := left_boot + left_fwd * (SKI_HALF_LENGTH * end_sign)
		var right_end := right_boot + right_fwd * (SKI_HALF_LENGTH * end_sign)
		var separation := (right_end - left_end).dot(axis)
		if separation < min_span:
			push = maxf(push, (min_span - separation) * 0.5)
	if push <= 0.00001:
		return [left_boot, right_boot]
	return [left_boot - axis * push, right_boot + axis * push]

## Shared ski-contact frame used by ground probes, rail stance, spawn, and AIR
## predicted-surface preview. Degenerate heading/normal fall back without
## producing a non-finite basis.
static func contact_transform(contact_point: Vector3, forward: Vector3, normal: Vector3, lift: float = CONTACT_LIFT) -> Transform3D:
	var up := normal.normalized() if normal.is_finite() and normal.length_squared() > 0.001 else Vector3.UP
	var planar_forward := forward.slide(up) if forward.is_finite() else Vector3.ZERO
	if planar_forward.length_squared() < 0.001:
		planar_forward = Vector3.FORWARD.slide(up)
	if planar_forward.length_squared() < 0.001:
		planar_forward = Vector3.RIGHT.slide(up)
	if planar_forward.length_squared() < 0.001:
		planar_forward = Vector3.RIGHT
	var origin := contact_point if contact_point.is_finite() else Vector3.ZERO
	var basis := Basis.looking_at(planar_forward.normalized(), up).orthonormalized()
	if not is_finite_basis(basis):
		basis = Basis.IDENTITY
	return Transform3D(basis, origin + up * lift)

static func project_onto_plane(point: Vector3, plane_point: Vector3, plane_normal: Vector3) -> Vector3:
	var up := plane_normal.normalized() if plane_normal.is_finite() and plane_normal.length_squared() > 0.0001 else Vector3.UP
	var source := point if point.is_finite() else Vector3.ZERO
	var plane_origin := plane_point if plane_point.is_finite() else Vector3.ZERO
	return source - up * (source - plane_origin).dot(up)

## Left/right ski transforms on a support plane. Stance is applied along the
## plane-right axis derived from the projected forward so left/right cannot swap.
static func stance_ski_targets(
	origin: Vector3,
	forward: Vector3,
	normal: Vector3,
	half_stance: float,
	lift: float = CONTACT_LIFT
) -> Dictionary:
	var empty := {
		"valid": false,
		"left": Transform3D.IDENTITY,
		"right": Transform3D.IDENTITY,
		"forward": Vector3.FORWARD,
		"up": Vector3.UP,
		"lateral": Vector3.RIGHT,
		"basis": Basis.IDENTITY,
	}
	if not origin.is_finite() or not is_finite(half_stance):
		return empty
	var sample := contact_transform(origin, forward, normal, 0.0)
	if not is_finite_transform(sample):
		return empty
	var up: Vector3 = sample.basis.y.normalized()
	var planar_forward: Vector3 = -sample.basis.z
	var lateral: Vector3 = sample.basis.x
	if lateral.length_squared() < 0.0001 or not lateral.is_finite():
		return empty
	lateral = lateral.normalized()
	var width := maxf(half_stance, 0.0)
	var left := contact_transform(origin - lateral * width, planar_forward, up, lift)
	var right := contact_transform(origin + lateral * width, planar_forward, up, lift)
	if not is_finite_transform(left) or not is_finite_transform(right):
		return empty
	return {
		"valid": true,
		"left": left,
		"right": right,
		"forward": planar_forward,
		"up": up,
		"lateral": lateral,
		"basis": sample.basis,
	}

## Cheap feature veto for presentation reach. A solid park-feature collider
## between the visual ski and the predicted snow plane disables preview IK.
## This is not a landing-prediction query and does not solve ski-feature contact.
static func feature_obstruction_scale(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclude: Array = [],
	mask: int = FEATURE_MASK
) -> float:
	if space == null or not from.is_finite() or not to.is_finite():
		return 1.0
	if from.distance_squared_to(to) <= 0.0001:
		return 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var blocked: Array[RID] = []
	for item: Variant in exclude:
		if item is RID:
			blocked.append(item)
	query.exclude = blocked
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return 0.0

static func is_finite_basis(value: Basis) -> bool:
	return value.x.is_finite() and value.y.is_finite() and value.z.is_finite()

static func is_finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and is_finite_basis(value.basis)

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
	var thigh_target := (desired_knee - hip_position).normalized()
	var previous: Array = _last_rotations.get(side, [hip.quaternion, knee.quaternion, boot.quaternion])
	# Solve the complete chain first. Limiting each correction against the newly
	# evaluated free pose loses the same part of the solve every frame, so deep
	# compression never reaches contact even after the target has stopped moving.
	var thigh_up := -thigh_target
	var bend_out := pole.slide(thigh_up).normalized()
	var hinge_axis := thigh_up.cross(bend_out).normalized()
	hip.global_basis = Basis(hinge_axis, thigh_up, hinge_axis.cross(thigh_up)).orthonormalized()
	var knee_position := knee.global_position
	var shin_current := (boot.global_position - knee_position).normalized()
	var shin_target := (target_position - knee_position).normalized()
	var knee_correction := shin_current.angle_to(shin_target)
	_clamp_local_euler(hip, Vector3(-1.4, -0.7, -0.72), Vector3(0.72, 0.7, 0.72))
	# Beyond 90 degrees Godot's YXZ Euler decomposition transfers the rotation
	# into Y/Z. Clamping that representation destroys deep knee flexion. Bound
	# the analytic hinge angle instead, without allowing sideways knee bend.
	var flexion := PI - acos(clampf((thigh_length * thigh_length + shin_length * shin_length - clamped_distance * clamped_distance) / (2.0 * thigh_length * shin_length), -1.0, 1.0))
	flexion -= atan2(-boot.position.z, -boot.position.y)
	knee.quaternion = Quaternion(Vector3.RIGHT, clampf(flexion, 0.0, 2.3))
	var target_boot_basis := target_boot_world.basis.orthonormalized()
	boot.global_basis = target_boot_basis
	_clamp_local_euler(boot, Vector3(-0.9, -0.45, -0.5), Vector3(0.55, 0.45, 0.5))
	var joints: Array[Node3D] = [hip, knee, boot]
	var solved: Array[Quaternion] = []
	for index: int in joints.size():
		var joint := joints[index]
		var before: Quaternion = previous[index]
		var target := joint.quaternion
		var blend := _bounded_weight(before.angle_to(target), weight, maximum_angular_rate, delta)
		joint.quaternion = before.slerp(target, blend).normalized()
		solved.append(joint.quaternion)
	_last_rotations[side] = solved
	result.valid = is_finite_transform(boot.global_transform)
	result.reach_ratio = target_distance / maximum_reach
	result.knee_correction = knee_correction
	result.infeasibility = clampf(infeasibility, 0.0, 1.0)
	result.pole = pole
	return result

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
