class_name EquipmentSelfCollisionSolver
extends RefCounted

## Deterministic capsule-proxy projection for visual equipment self-collision.
## It never touches gameplay/root state: adapters apply the returned actuator
## translations or pole directions to presentation nodes only.

const ProxyModule := preload("res://player/animation/equipment_collision_proxy.gd")
const ResultModule := preload("res://player/animation/equipment_collision_result.gd")

func solve(input_proxies: Array[EquipmentCollisionProxy], context: EquipmentCollisionContext) -> EquipmentCollisionResult:
	var result := ResultModule.new() as EquipmentCollisionResult
	var proxies: Array[EquipmentCollisionProxy] = []
	for source: EquipmentCollisionProxy in input_proxies:
		if source == null or not source.is_valid():
			result.valid = false
			continue
		proxies.append(source.copy())
	proxies.sort_custom(func(left: EquipmentCollisionProxy, right: EquipmentCollisionProxy) -> bool:
		return String(left.id) < String(right.id))
	result.proxy_count = proxies.size()
	if context == null or not result.valid:
		return result
	var translations: Dictionary = {}
	var directions: Dictionary = {}
	var pivot_angles: Dictionary = {}
	var candidate_pairs := _candidate_pairs(proxies)
	result.pair_count = candidate_pairs.size()
	for iteration: int in maxi(context.iterations, 0):
		result.iterations = iteration + 1
		for pair: Vector2i in candidate_pairs:
			var first := proxies[pair.x]
			var second := proxies[pair.y]
			var contact := _contact(first, second, context.clearance)
			var penetration := float(contact.get("penetration", 0.0))
			if penetration <= context.tolerance:
				continue
			var first_movable := first.mobility != ProxyModule.Mobility.FIXED and not first.actuator.is_empty()
			var second_movable := second.mobility != ProxyModule.Mobility.FIXED and not second.actuator.is_empty()
			if not first_movable and not second_movable:
				continue
			var normal := contact.get("normal", Vector3.RIGHT) as Vector3
			# Bias beyond the audit tolerance so approximate pivot projection does
			# not settle on the unresolved side of the clearance boundary.
			var correction := normal * minf(penetration + context.tolerance * 3.0, context.max_step)
			var first_point := contact.get("first_point", first.center()) as Vector3
			var second_point := contact.get("second_point", second.center()) as Vector3
			if first_movable and second_movable:
				_apply_actuator(proxies, first, correction * 0.5, first_point, translations, directions, pivot_angles)
				_apply_actuator(proxies, second, -correction * 0.5, second_point, translations, directions, pivot_angles)
			elif first_movable:
				_apply_actuator(proxies, first, correction, first_point, translations, directions, pivot_angles)
			else:
				_apply_actuator(proxies, second, -correction, second_point, translations, directions, pivot_angles)
			result.applied_contacts.append(_diagnostic(first, second, penetration))
	result.translations = translations
	result.directions = directions
	for pair: Vector2i in candidate_pairs:
		var first := proxies[pair.x]
		var second := proxies[pair.y]
		var contact := _contact(first, second, context.clearance)
		var penetration := float(contact.get("penetration", 0.0))
		if penetration <= context.tolerance:
			continue
		result.max_penetration = maxf(result.max_penetration, penetration)
		result.unresolved_contacts.append(_diagnostic(first, second, penetration))
	return result

func audit(input_proxies: Array[EquipmentCollisionProxy], clearance: float = 0.015, tolerance: float = 0.001) -> Array[Dictionary]:
	var proxies: Array[EquipmentCollisionProxy] = []
	for source: EquipmentCollisionProxy in input_proxies:
		if source != null and source.is_valid():
			proxies.append(source.copy())
	proxies.sort_custom(func(left: EquipmentCollisionProxy, right: EquipmentCollisionProxy) -> bool:
		return String(left.id) < String(right.id))
	var unresolved: Array[Dictionary] = []
	for pair: Vector2i in _candidate_pairs(proxies):
		var first := proxies[pair.x]
		var second := proxies[pair.y]
		var penetration := float(_contact(first, second, clearance).get("penetration", 0.0))
		if penetration > tolerance:
			unresolved.append(_diagnostic(first, second, penetration))
	return unresolved

func _candidate_pairs(proxies: Array[EquipmentCollisionProxy]) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	for first_index: int in proxies.size():
		for second_index: int in range(first_index + 1, proxies.size()):
			var first := proxies[first_index]
			var second := proxies[second_index]
			if first.kind == ProxyModule.Kind.BODY and second.kind == ProxyModule.Kind.BODY:
				continue
			if not first.actuator.is_empty() and first.actuator == second.actuator:
				continue
			if _shares_tag(first, second):
				continue
			pairs.append(Vector2i(first_index, second_index))
	return pairs

func _shares_tag(first: EquipmentCollisionProxy, second: EquipmentCollisionProxy) -> bool:
	for tag: StringName in first.tags:
		if not tag.is_empty() and tag in second.tags:
			return true
	return false

func _contact(first: EquipmentCollisionProxy, second: EquipmentCollisionProxy, clearance: float) -> Dictionary:
	var closest := _closest_segment_points(first.a, first.b, second.a, second.b)
	var first_point := closest[0] as Vector3
	var second_point := closest[1] as Vector3
	var delta := first_point - second_point
	var distance := delta.length()
	var normal := delta / distance if distance > 0.000001 else _fallback_normal(first, second)
	return {
		"normal": normal,
		"distance": distance,
		"penetration": maxf(0.0, first.radius + second.radius + maxf(clearance, 0.0) - distance),
		"first_point": first_point,
		"second_point": second_point,
	}

func _apply_actuator(
	proxies: Array[EquipmentCollisionProxy],
	reference: EquipmentCollisionProxy,
	delta: Vector3,
	contact_point: Vector3,
	translations: Dictionary,
	directions: Dictionary,
	pivot_angles: Dictionary
) -> void:
	if delta.length_squared() <= 0.00000001:
		return
	if reference.mobility == ProxyModule.Mobility.TRANSLATE:
		var accumulated := translations.get(reference.actuator, Vector3.ZERO) as Vector3
		var remaining := maxf(reference.max_translation - accumulated.length(), 0.0)
		var applied := delta.limit_length(remaining)
		if applied.length_squared() <= 0.00000001:
			return
		translations[reference.actuator] = accumulated + applied
		for proxy: EquipmentCollisionProxy in proxies:
			if proxy.actuator == reference.actuator:
				proxy.a += applied
				proxy.b += applied
				proxy.pivot += applied
		return
	if reference.mobility != ProxyModule.Mobility.PIVOT:
		return
	var old_direction := _actuator_direction(proxies, reference.actuator, reference.pivot)
	if old_direction.length_squared() <= 0.0001:
		return
	var contact_direction := contact_point - reference.pivot
	var desired := contact_direction + delta
	if contact_direction.length_squared() <= 0.0001 or desired.length_squared() <= 0.0001:
		return
	contact_direction = contact_direction.normalized()
	var target_direction := desired.normalized()
	var angle := acos(clampf(contact_direction.dot(target_direction), -1.0, 1.0))
	var accumulated_angle := float(pivot_angles.get(reference.actuator, 0.0))
	var allowed := minf(angle, minf(0.25, maxf(reference.max_angle - accumulated_angle, 0.0)))
	if allowed <= 0.00001:
		return
	var axis := contact_direction.cross(target_direction)
	if axis.length_squared() <= 0.000001:
		axis = _orthogonal(contact_direction)
	var rotation := Basis(axis.normalized(), allowed)
	for proxy: EquipmentCollisionProxy in proxies:
		if proxy.actuator != reference.actuator:
			continue
		proxy.a = reference.pivot + rotation * (proxy.a - reference.pivot)
		proxy.b = reference.pivot + rotation * (proxy.b - reference.pivot)
		proxy.pivot = reference.pivot
	pivot_angles[reference.actuator] = accumulated_angle + allowed
	directions[reference.actuator] = (rotation * old_direction).normalized()

func _actuator_direction(proxies: Array[EquipmentCollisionProxy], actuator: StringName, pivot: Vector3) -> Vector3:
	var furthest := Vector3.ZERO
	for proxy: EquipmentCollisionProxy in proxies:
		if proxy.actuator != actuator:
			continue
		for point: Vector3 in [proxy.a, proxy.b]:
			var offset := point - pivot
			if offset.length_squared() > furthest.length_squared():
				furthest = offset
	return furthest.normalized() if furthest.length_squared() > 0.0001 else Vector3.ZERO

func _fallback_normal(first: EquipmentCollisionProxy, second: EquipmentCollisionProxy) -> Vector3:
	var centers := first.center() - second.center()
	if centers.length_squared() > 0.000001:
		return centers.normalized()
	var seed := String(first.id) + ":" + String(second.id)
	var axis: int = absi(seed.hash()) % 3
	if axis == 0:
		return Vector3.RIGHT
	if axis == 1:
		return Vector3.UP
	return Vector3.FORWARD

func _orthogonal(direction: Vector3) -> Vector3:
	var axis := direction.cross(Vector3.UP)
	if axis.length_squared() <= 0.0001:
		axis = direction.cross(Vector3.RIGHT)
	return axis.normalized()

func _diagnostic(first: EquipmentCollisionProxy, second: EquipmentCollisionProxy, penetration: float) -> Dictionary:
	return {
		"first": String(first.id),
		"second": String(second.id),
		"first_side": String(first.side),
		"second_side": String(second.side),
		"penetration_m": penetration,
	}

func _closest_segment_points(first_a: Vector3, first_b: Vector3, second_a: Vector3, second_b: Vector3) -> Array[Vector3]:
	var first_direction := first_b - first_a
	var second_direction := second_b - second_a
	var offset := first_a - second_a
	var first_length := first_direction.length_squared()
	var second_length := second_direction.length_squared()
	var second_offset := second_direction.dot(offset)
	var first_parameter := 0.0
	var second_parameter := 0.0
	if first_length <= 0.000001 and second_length <= 0.000001:
		return [first_a, second_a]
	if first_length <= 0.000001:
		second_parameter = clampf(second_offset / second_length, 0.0, 1.0)
	elif second_length <= 0.000001:
		first_parameter = clampf(-first_direction.dot(offset) / first_length, 0.0, 1.0)
	else:
		var first_offset := first_direction.dot(offset)
		var directions_dot := first_direction.dot(second_direction)
		var denominator := first_length * second_length - directions_dot * directions_dot
		if not is_zero_approx(denominator):
			first_parameter = clampf((directions_dot * second_offset - first_offset * second_length) / denominator, 0.0, 1.0)
		var projected_second := directions_dot * first_parameter + second_offset
		if projected_second < 0.0:
			second_parameter = 0.0
			first_parameter = clampf(-first_offset / first_length, 0.0, 1.0)
		elif projected_second > second_length:
			second_parameter = 1.0
			first_parameter = clampf((directions_dot - first_offset) / first_length, 0.0, 1.0)
		else:
			second_parameter = projected_second / second_length
	return [
		first_a + first_direction * first_parameter,
		second_a + second_direction * second_parameter,
	]
