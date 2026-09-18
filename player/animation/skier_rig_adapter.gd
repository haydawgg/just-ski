class_name SkierRigAdapter
extends Node3D

const CollisionProxyModule := preload("res://player/animation/equipment_collision_proxy.gd")
const CollisionResultModule := preload("res://player/animation/equipment_collision_result.gd")
const SelfCollisionSolverModule := preload("res://player/animation/equipment_self_collision_solver.gd")
const COLLISION_RECONCILIATION_PASSES := 6
const MAX_TOTAL_ASSEMBLY_TRANSLATION := 0.35
const MAX_TOTAL_POLE_ANGLE := 1.2

var driver: SkierPoseDriver
var error_message := ""
var _equipment_collision_solver := SelfCollisionSolverModule.new()
var _last_equipment_collision_result := CollisionResultModule.new() as EquipmentCollisionResult
var _active_collision_context: EquipmentCollisionContext

func configure(value: SkierPoseDriver, _skeleton_profile: Resource = null) -> bool:
	driver = value
	error_message = ""
	return driver != null

func sync_pose(_delta: float, _grab_requests: Array[SkierGrabReachRequest] = []) -> void:
	pass

func landmarks() -> Dictionary:
	return driver.canonical_landmarks() if driver != null else {}

func grab_target(side: StringName, target: StringName) -> Node3D:
	return driver.grab_target(side, target) if driver != null else null

func arm_lengths(_side: StringName) -> Vector2:
	if driver == null:
		return Vector2.ZERO
	return Vector2(
		driver.rest_position(&"left_elbow").length(),
		driver.rest_position(&"left_hand").length()
	)

## Returns true when this adapter owns the final visual hand-to-ski solve. The
## canonical controller keeps its existing arm solve for adapters that return
## false, preserving the primitive fallback behavior.
func owns_grab_reach() -> bool:
	return false

func grab_contact_point(side: StringName) -> Vector3:
	if driver == null:
		return Vector3.ZERO
	var hand := driver.joint(StringName("%s_hand" % side))
	return hand.global_position if hand != null else Vector3.ZERO

func grab_reach_error(_side: StringName) -> float:
	return 0.0

func grab_target_world(_side: StringName) -> Vector3:
	return Vector3.ZERO

## Grip-excluded pole shaft segments for feature sweeps, keyed by side with
## {start, end} endpoints. The base adapter (and any rig without mounted
## poles) returns an empty set, which disables pole sweeping.
func pole_shaft_segments() -> Dictionary:
	return {}

func ragdoll_world_transforms() -> Dictionary:
	var transforms := {}
	if driver == null:
		return transforms
	for semantic: StringName in [
		&"pelvis", &"spine", &"chest", &"head",
		&"left_hip", &"left_knee", &"left_boot",
		&"right_hip", &"right_knee", &"right_boot",
		&"left_shoulder", &"left_elbow", &"left_hand",
		&"right_shoulder", &"right_elbow", &"right_hand",
		&"left_ski", &"right_ski", &"left_pole", &"right_pole",
	]:
		var node := driver.joint(semantic)
		if node != null:
			transforms[semantic] = node.global_transform
	for side: StringName in [&"left", &"right"]:
		var tip := driver.pole_tips.get(side) as Node3D
		if tip != null:
			transforms[StringName(String(side) + "_pole_tip")] = tip.global_transform
	return transforms

func apply_ragdoll_pose(world_transforms: Dictionary, weight: float = 1.0) -> void:
	if driver == null or world_transforms.is_empty():
		return
	var blend := clampf(weight, 0.0, 1.0)
	for semantic: StringName in [
		&"pelvis", &"spine", &"chest", &"head",
		&"left_hip", &"left_knee", &"left_boot",
		&"right_hip", &"right_knee", &"right_boot",
		&"left_shoulder", &"left_elbow", &"left_hand",
		&"right_shoulder", &"right_elbow", &"right_hand",
		&"left_ski", &"right_ski", &"left_pole", &"right_pole",
	]:
		if not world_transforms.has(semantic):
			continue
		var node := driver.joint(semantic)
		if node != null:
			node.global_transform = node.global_transform.interpolate_with(world_transforms[semantic] as Transform3D, blend)
	sync_pose(0.0, [])

## Deep rig-adapter seam for presentation-only self-collision. Each adapter
## supplies final-pose semantic capsules and applies the solver's actuator
## result without exposing rig-specific bone or attachment details.
func resolve_equipment_self_collision(context: EquipmentCollisionContext) -> EquipmentCollisionResult:
	if driver == null or context == null:
		_last_equipment_collision_result = CollisionResultModule.new() as EquipmentCollisionResult
		return _last_equipment_collision_result
	_active_collision_context = context
	var result := CollisionResultModule.new() as EquipmentCollisionResult
	var applied_contacts: Array[Dictionary] = []
	var accumulated_translations: Dictionary = {}
	var initial_pole_directions: Dictionary = {}
	# Bounded reconciliation closes the gap between the solver's capsule model
	# and the adapter's bone/attachment application without introducing frame-time
	# feedback or touching the gameplay transform.
	for _pass: int in COLLISION_RECONCILIATION_PASSES:
		result = _equipment_collision_solver.solve(_equipment_collision_proxies(context), context)
		applied_contacts.append_array(result.applied_contacts)
		_limit_collision_result(result, context, accumulated_translations, initial_pole_directions)
		_apply_equipment_collision_result(result)
		if _equipment_collision_solver.audit(
			_equipment_collision_proxies(context), context.clearance, context.tolerance
		).is_empty():
			break
	var final_contacts := _equipment_collision_solver.audit(
		_equipment_collision_proxies(context), context.clearance, context.tolerance)
	result.applied_contacts = applied_contacts
	result.unresolved_contacts = final_contacts
	result.max_penetration = 0.0
	for contact: Dictionary in final_contacts:
		result.max_penetration = maxf(result.max_penetration, float(contact.get("penetration_m", 0.0)))
	_last_equipment_collision_result = result
	return result

func equipment_collision_snapshot() -> Dictionary:
	return _last_equipment_collision_result.snapshot()

func _equipment_collision_proxies(context: EquipmentCollisionContext) -> Array[EquipmentCollisionProxy]:
	var proxies: Array[EquipmentCollisionProxy] = []
	if driver == null:
		return proxies
	_append_body_proxies(proxies, context, false)
	for side: StringName in [&"left", &"right"]:
		var ski := driver.joint(StringName(side + "_ski"))
		var boot := driver.joint(StringName(side + "_boot"))
		var pole := driver.joint(StringName(side + "_pole"))
		var tip := driver.pole_tips.get(side) as Node3D
		if ski != null:
			var half_length := SkierEquipment.SKI_SIZE.z * 0.5
			var forward := -ski.global_basis.z.normalized()
			var grab_tags := _grab_tags_for_equipment(context, side)
			var ski_tags: Array[StringName] = [StringName("leg_binding_" + side)]
			ski_tags.append_array(grab_tags)
			proxies.append(_proxy(
				StringName(side + "_ski"), CollisionProxyModule.Kind.SKI, side,
				ski.global_position - forward * half_length,
				ski.global_position + forward * half_length,
				EquipmentFeatureCollisionSolver.SKI_RADIUS,
				StringName("boot_ski_" + side),
				CollisionProxyModule.Mobility.FIXED if context.skis_locked else CollisionProxyModule.Mobility.TRANSLATE,
				ski.global_position, ski_tags))
		if boot != null:
			var boot_forward := -boot.global_basis.z.normalized()
			var boot_grab_tags := _grab_tags_for_equipment(context, side)
			var boot_tags: Array[StringName] = [StringName("leg_binding_" + side)]
			boot_tags.append_array(boot_grab_tags)
			proxies.append(_proxy(
				StringName(side + "_boot"), CollisionProxyModule.Kind.BOOT, side,
				boot.global_position - boot_forward * 0.15,
				boot.global_position + boot_forward * 0.15,
				0.075,
				StringName("boot_ski_" + side),
				CollisionProxyModule.Mobility.FIXED if context.skis_locked else CollisionProxyModule.Mobility.TRANSLATE,
				boot.global_position, boot_tags))
		if pole != null and tip != null:
			var shaft_start := pole.global_position.lerp(tip.global_position, 0.15)
			var pole_tags: Array[StringName] = [StringName("grip_" + side)]
			proxies.append(_proxy(
				StringName(side + "_pole_shaft"), CollisionProxyModule.Kind.POLE, side,
				shaft_start, tip.global_position, SkierEquipment.POLE_SHAFT_RADIUS,
				StringName("pole_" + side), CollisionProxyModule.Mobility.PIVOT,
				pole.global_position, pole_tags))
			proxies.append(_proxy(
				StringName(side + "_pole_basket"), CollisionProxyModule.Kind.POLE, side,
				tip.global_position, tip.global_position, SkierEquipment.POLE_BASKET_RADIUS,
				StringName("pole_" + side), CollisionProxyModule.Mobility.PIVOT,
				pole.global_position, pole_tags))
	return proxies

func _append_body_proxies(proxies: Array[EquipmentCollisionProxy], context: EquipmentCollisionContext, production: bool) -> void:
	var point := func(semantic: StringName) -> Vector3:
		return _collision_body_point(semantic, production)
	proxies.append(_proxy(&"body_torso", CollisionProxyModule.Kind.BODY, &"center", point.call(&"pelvis"), point.call(&"chest"), 0.18))
	proxies.append(_proxy(&"body_head", CollisionProxyModule.Kind.BODY, &"center", point.call(&"chest"), point.call(&"head"), 0.145))
	for side: StringName in [&"left", &"right"]:
		var hand_tags: Array[StringName] = [StringName("grip_" + side)]
		var arm_tags: Array[StringName] = []
		var forearm_tags: Array[StringName] = [StringName("grip_" + side)]
		if context.grab_targets.has(side):
			var grab_tag := StringName("grab_" + side)
			hand_tags.append(grab_tag)
			arm_tags.append(grab_tag)
			forearm_tags.append(grab_tag)
		proxies.append(_proxy(
			StringName("body_" + side + "_upper_arm"), CollisionProxyModule.Kind.BODY, side,
			point.call(StringName(side + "_shoulder")), point.call(StringName(side + "_elbow")), 0.086,
			&"", CollisionProxyModule.Mobility.FIXED, Vector3.ZERO, arm_tags))
		proxies.append(_proxy(
			StringName("body_" + side + "_forearm"), CollisionProxyModule.Kind.BODY, side,
			point.call(StringName(side + "_elbow")), point.call(StringName(side + "_hand")), 0.073,
			&"", CollisionProxyModule.Mobility.FIXED, Vector3.ZERO, forearm_tags))
		var hand := point.call(StringName(side + "_hand")) as Vector3
		proxies.append(_proxy(
			StringName("body_" + side + "_hand"), CollisionProxyModule.Kind.BODY, side,
			hand, hand, 0.068, &"", CollisionProxyModule.Mobility.FIXED,
			hand, hand_tags))
		proxies.append(_proxy(
			StringName("body_" + side + "_thigh"), CollisionProxyModule.Kind.BODY, side,
			point.call(StringName(side + "_hip")), point.call(StringName(side + "_knee")), 0.105,
			&"", CollisionProxyModule.Mobility.FIXED, Vector3.ZERO,
			[StringName("leg_binding_" + side)]))
		proxies.append(_proxy(
			StringName("body_" + side + "_shin"), CollisionProxyModule.Kind.BODY, side,
			point.call(StringName(side + "_knee")), point.call(StringName(side + "_boot")), 0.09,
			&"", CollisionProxyModule.Mobility.FIXED,
			Vector3.ZERO, [StringName("leg_binding_" + side)]))

func _collision_body_point(semantic: StringName, _production: bool) -> Vector3:
	var joint := driver.joint(semantic) if driver != null else null
	return joint.global_position if joint != null else Vector3.ZERO

func _proxy(
	id: StringName,
	kind: int,
	side: StringName,
	a: Vector3,
	b: Vector3,
	radius: float,
	actuator: StringName = &"",
	mobility: int = CollisionProxyModule.Mobility.FIXED,
	pivot: Vector3 = Vector3.ZERO,
	tags: Array[StringName] = []
) -> EquipmentCollisionProxy:
	var proxy := CollisionProxyModule.new() as EquipmentCollisionProxy
	proxy.id = id
	proxy.kind = kind
	proxy.side = side
	proxy.a = a
	proxy.b = b
	proxy.radius = radius
	proxy.actuator = actuator
	proxy.mobility = mobility
	proxy.pivot = pivot
	proxy.tags = tags.duplicate()
	return proxy

func _limit_collision_result(
	result: EquipmentCollisionResult,
	context: EquipmentCollisionContext,
	accumulated_translations: Dictionary,
	initial_pole_directions: Dictionary
) -> void:
	for actuator: Variant in result.translations.keys():
		var accumulated := accumulated_translations.get(actuator, Vector3.ZERO) as Vector3
		var requested := result.translations[actuator] as Vector3
		var bounded_total := (accumulated + requested).limit_length(MAX_TOTAL_ASSEMBLY_TRANSLATION)
		result.translations[actuator] = bounded_total - accumulated
		accumulated_translations[actuator] = bounded_total
	var current_proxies := _equipment_collision_proxies(context)
	for actuator: Variant in result.directions.keys():
		var current := _collision_actuator_direction(current_proxies, actuator as StringName)
		var desired := result.directions[actuator] as Vector3
		if current.length_squared() <= 0.0001 or desired.length_squared() <= 0.0001:
			result.directions.erase(actuator)
			continue
		if not initial_pole_directions.has(actuator):
			initial_pole_directions[actuator] = current.normalized()
		var initial := initial_pole_directions[actuator] as Vector3
		var total_angle := acos(clampf(initial.dot(desired.normalized()), -1.0, 1.0))
		if total_angle > MAX_TOTAL_POLE_ANGLE:
			result.directions[actuator] = initial.slerp(
				desired.normalized(), MAX_TOTAL_POLE_ANGLE / total_angle).normalized()

func _collision_actuator_direction(
	proxies: Array[EquipmentCollisionProxy], actuator: StringName
) -> Vector3:
	var furthest := Vector3.ZERO
	for proxy: EquipmentCollisionProxy in proxies:
		if proxy.actuator != actuator:
			continue
		for point: Vector3 in [proxy.a, proxy.b]:
			var offset := point - proxy.pivot
			if offset.length_squared() > furthest.length_squared():
				furthest = offset
	return furthest.normalized() if furthest.length_squared() > 0.0001 else Vector3.ZERO

func _grab_tags_for_equipment(
	context: EquipmentCollisionContext, equipment_side: StringName
) -> Array[StringName]:
	var tags: Array[StringName] = []
	for hand_side: Variant in context.grab_targets:
		var target := context.grab_targets[hand_side] as Vector3
		var nearest_equipment_side: StringName
		var nearest_distance := INF
		for candidate: StringName in [&"left", &"right"]:
			var distance := target.distance_squared_to(_equipment_collision_position(candidate))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_equipment_side = candidate
		if nearest_equipment_side == equipment_side and nearest_distance <= 1.0:
			tags.append(StringName("grab_" + String(hand_side)))
	return tags

func _grab_hands_for_equipment(
	context: EquipmentCollisionContext, equipment_side: StringName
) -> Array[StringName]:
	var hands: Array[StringName] = []
	for tag: StringName in _grab_tags_for_equipment(context, equipment_side):
		hands.append(StringName(String(tag).trim_prefix("grab_")))
	return hands

func _equipment_collision_position(side: StringName) -> Vector3:
	var ski := driver.joint(StringName(side + "_ski")) if driver != null else null
	return ski.global_position if ski != null else Vector3.ZERO

func _apply_equipment_collision_result(result: EquipmentCollisionResult) -> void:
	if driver == null or result == null:
		return
	for side: StringName in [&"left", &"right"]:
		var assembly := StringName("boot_ski_" + side)
		var translation := result.translations.get(assembly, Vector3.ZERO) as Vector3
		var boot := driver.joint(StringName(side + "_boot"))
		if boot != null and translation.length_squared() > 0.00000001:
			boot.global_position += translation
			# The primitive rig has no post-adapter IK. Translate the active arm
			# root with its selected ski so the established grab contact and limb
			# segment lengths survive the presentation correction.
			if _active_collision_context != null:
				for hand_side: StringName in _grab_hands_for_equipment(
					_active_collision_context, side
				):
					var shoulder := driver.joint(StringName(hand_side + "_shoulder"))
					if shoulder != null:
						shoulder.global_position += translation
		var pole_actuator := StringName("pole_" + side)
		if result.directions.has(pole_actuator):
			var pole := driver.joint(StringName(side + "_pole"))
			_apply_pole_direction(pole, result.directions[pole_actuator] as Vector3)

func _apply_pole_direction(pole: Node3D, direction: Vector3) -> void:
	if pole == null or direction.length_squared() <= 0.0001:
		return
	var current := -pole.global_basis.y.normalized()
	if current.length_squared() <= 0.0001:
		return
	var rotation := Quaternion(current, direction.normalized())
	pole.global_basis = (Basis(rotation) * pole.global_basis).orthonormalized()

func grab_debug_snapshot() -> Dictionary:
	return {}

func adapter_name() -> String:
	return "base"

func validation_error() -> String:
	return error_message
