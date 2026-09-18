class_name CrashRagdoll3D
extends Node3D

## Crash-only physical skeleton. The normal skier remains animation/controller
## driven; this node is activated only after SkierController has committed to a
## BAIL and hands the evaluated visual pose plus root momentum to physics.

const CollisionLayers := preload("res://resources/physics/collision_layers.gd")
const TERRAIN_AND_FEATURE_MASK := CollisionLayers.WORLD_SOLID_MASK
const RAGDOLL_LAYER := CollisionLayers.RAGDOLL
const REQUIRED_BODY_SEMANTICS: Array[StringName] = [
	&"pelvis", &"spine", &"chest", &"head",
	&"left_hip", &"left_knee", &"left_boot",
	&"right_hip", &"right_knee", &"right_boot",
	&"left_shoulder", &"left_elbow", &"left_hand",
	&"right_shoulder", &"right_elbow", &"right_hand",
]
const POSE_BODY: Dictionary = {
	&"pelvis": &"pelvis",
	&"spine": &"chest",
	&"chest": &"chest",
	&"head": &"head",
	&"left_hip": &"left_thigh",
	&"left_knee": &"left_shin",
	&"left_boot": &"left_shin",
	&"right_hip": &"right_thigh",
	&"right_knee": &"right_shin",
	&"right_boot": &"right_shin",
	&"left_shoulder": &"left_upper_arm",
	&"left_elbow": &"left_forearm",
	&"left_hand": &"left_forearm",
	&"right_shoulder": &"right_upper_arm",
	&"right_elbow": &"right_forearm",
	&"right_hand": &"right_forearm",
	&"left_ski": &"left_ski",
	&"right_ski": &"right_ski",
	&"left_pole": &"left_pole",
	&"right_pole": &"right_pole",
}

var active := false
var recovering := false
var age := 0.0
var severity := 0.0
var left_ski_released := false
var right_ski_released := false
var left_pole_released := false
var right_pole_released := false
var bodies: Dictionary = {}
var pose_offsets: Dictionary = {}
var _joints: Array[Joint3D] = []
var _joint_anchors: Array[Dictionary] = []
var _profile: SkiPhysicsProfile
var _recovery_pose: Dictionary = {}
var _physics_material: PhysicsMaterial

func _physics_process(delta: float) -> void:
	if not active or recovering:
		return
	age += maxf(delta, 0.0)
	var active_weight := 1.0 - smoothstep(
		0.0,
		maxf(_profile.ragdoll_active_muscle_duration, 0.001),
		age
	)
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if body == null:
			continue
		# The short high-damping phase approximates muscles resisting the initial
		# impact. Joint limits provide the actual articulated constraint; damping
		# then falls away into a passive ragdoll.
		body.angular_damp = lerpf(_profile.ragdoll_passive_angular_damp, _profile.ragdoll_active_angular_damp, active_weight)
		body.linear_damp = lerpf(_profile.ragdoll_passive_linear_damp, _profile.ragdoll_active_linear_damp, active_weight)
		var angular_limit := lerpf(
			_profile.ragdoll_passive_max_angular_velocity,
			_profile.ragdoll_active_max_angular_velocity,
			active_weight
		)
		body.angular_velocity = body.angular_velocity.limit_length(maxf(angular_limit, 0.0))
	_apply_ski_snow_resistance(&"left_ski", left_ski_released)
	_apply_ski_snow_resistance(&"right_ski", right_ski_released)

func activate(
	world_transforms: Dictionary,
	root_linear_velocity: Vector3,
	root_angular_velocity: Vector3,
	crash_severity: float,
	lateral_bias: float,
	profile: SkiPhysicsProfile,
	binding_severity: float = -1.0
) -> bool:
	stop()
	if profile == null or world_transforms.is_empty():
		return false
	_profile = profile
	severity = clampf(crash_severity, 0.0, 1.0)
	left_ski_released = false
	right_ski_released = false
	_choose_equipment_release(
		crash_severity if binding_severity < 0.0 else clampf(binding_severity, 0.0, 1.0),
		lateral_bias
	)
	if not _has_required_transforms(world_transforms):
		return false
	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = clampf(_profile.ragdoll_body_friction, 0.0, 1.0)
	_physics_material.bounce = clampf(_profile.ragdoll_restitution, 0.0, 1.0)

	var pelvis := _origin(world_transforms, &"pelvis")
	var spine := _origin(world_transforms, &"spine")
	var chest := _origin(world_transforms, &"chest")
	var head := _origin(world_transforms, &"head")
	var left_hip := _origin(world_transforms, &"left_hip")
	var right_hip := _origin(world_transforms, &"right_hip")
	var left_shoulder := _origin(world_transforms, &"left_shoulder")
	var right_shoulder := _origin(world_transforms, &"right_shoulder")

	_add_capsule(&"pelvis", pelvis - Vector3.UP * 0.12, spine, 0.20, 16.0)
	_add_capsule(&"chest", spine, chest + (head - chest) * 0.18, 0.22, 24.0)
	var head_axis := head - chest
	var head_tip := head + (head_axis.normalized() * 0.18 if head_axis.length_squared() > 0.0001 else Vector3.UP * 0.18)
	_add_capsule(&"head", chest + head_axis * 0.55, head_tip, 0.145, 5.0)
	_add_limb(world_transforms, &"left_upper_arm", &"left_shoulder", &"left_elbow", 0.09, 2.2)
	_add_limb(world_transforms, &"left_forearm", &"left_elbow", &"left_hand", 0.075, 1.5)
	_add_limb(world_transforms, &"right_upper_arm", &"right_shoulder", &"right_elbow", 0.09, 2.2)
	_add_limb(world_transforms, &"right_forearm", &"right_elbow", &"right_hand", 0.075, 1.5)
	_add_limb(world_transforms, &"left_thigh", &"left_hip", &"left_knee", 0.11, 7.0)
	_add_limb(world_transforms, &"left_shin", &"left_knee", &"left_boot", 0.095, 5.0)
	_add_limb(world_transforms, &"right_thigh", &"right_hip", &"right_knee", 0.11, 7.0)
	_add_limb(world_transforms, &"right_shin", &"right_knee", &"right_boot", 0.095, 5.0)
	_add_equipment(world_transforms)

	_add_cone_joint(&"spine_joint", bodies[&"pelvis"], bodies[&"chest"], spine, 30.0, 25.0)
	_add_cone_joint(&"neck_joint", bodies[&"chest"], bodies[&"head"], chest + (head - chest) * 0.58, 35.0, 45.0)
	_add_cone_joint(&"left_shoulder_joint", bodies[&"chest"], bodies[&"left_upper_arm"], left_shoulder, 95.0, 80.0)
	_add_cone_joint(&"right_shoulder_joint", bodies[&"chest"], bodies[&"right_upper_arm"], right_shoulder, 95.0, 80.0)
	_add_cone_joint(&"left_elbow_joint", bodies[&"left_upper_arm"], bodies[&"left_forearm"], _origin(world_transforms, &"left_elbow"), 18.0, 130.0)
	_add_cone_joint(&"right_elbow_joint", bodies[&"right_upper_arm"], bodies[&"right_forearm"], _origin(world_transforms, &"right_elbow"), 18.0, 130.0)
	_add_cone_joint(&"left_hip_joint", bodies[&"pelvis"], bodies[&"left_thigh"], left_hip, 55.0, 45.0)
	_add_cone_joint(&"right_hip_joint", bodies[&"pelvis"], bodies[&"right_thigh"], right_hip, 55.0, 45.0)
	_add_cone_joint(&"left_knee_joint", bodies[&"left_thigh"], bodies[&"left_shin"], _origin(world_transforms, &"left_knee"), 15.0, 115.0)
	_add_cone_joint(&"right_knee_joint", bodies[&"right_thigh"], bodies[&"right_shin"], _origin(world_transforms, &"right_knee"), 15.0, 115.0)
	for semantic_value: Variant in POSE_BODY.keys():
		var semantic := semantic_value as StringName
		var body_id := _pose_body_id(semantic)
		var body := bodies.get(body_id) as RigidBody3D
		var visual_transform := world_transforms.get(semantic, Transform3D.IDENTITY) as Transform3D
		if body != null:
			pose_offsets[semantic] = body.global_transform.affine_inverse() * visual_transform

	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		var radial := body.global_position - pelvis
		body.linear_velocity = root_linear_velocity + root_angular_velocity.cross(radial)
		body.angular_velocity = root_angular_velocity
		body.sleeping = false
	active = true
	recovering = false
	age = 0.0
	return true

func begin_recovery() -> void:
	if not active or recovering:
		return
	_recovery_pose = physics_pose()
	recovering = true
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0

func stop() -> void:
	for joint: Joint3D in _joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_joints.clear()
	_joint_anchors.clear()
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if is_instance_valid(body):
			body.freeze = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.queue_free()
	bodies.clear()
	pose_offsets.clear()
	_recovery_pose.clear()
	active = false
	recovering = false
	age = 0.0

func physics_pose() -> Dictionary:
	if recovering and not _recovery_pose.is_empty():
		return _recovery_pose.duplicate()
	var pose := {}
	for semantic_value: Variant in pose_offsets.keys():
		var semantic := semantic_value as StringName
		var body_id := _pose_body_id(semantic)
		var body := bodies.get(body_id) as RigidBody3D
		if body != null:
			pose[semantic] = body.global_transform * (pose_offsets[semantic] as Transform3D)
	return pose

func pelvis_transform() -> Transform3D:
	var body := bodies.get(&"pelvis") as RigidBody3D
	return body.global_transform if body != null else Transform3D.IDENTITY

func pelvis_velocity() -> Vector3:
	var body := bodies.get(&"pelvis") as RigidBody3D
	return body.linear_velocity if body != null and not recovering else Vector3.ZERO

func pelvis_angular_velocity() -> Vector3:
	var body := bodies.get(&"pelvis") as RigidBody3D
	return body.angular_velocity if body != null and not recovering else Vector3.ZERO

func tether_pelvis(target_world_position: Vector3) -> void:
	if not active or recovering or not target_world_position.is_finite():
		return
	var pelvis_body := bodies.get(&"pelvis") as RigidBody3D
	if pelvis_body == null:
		return
	var correction := target_world_position - pelvis_body.global_position
	if not correction.is_finite() or correction.length_squared() <= 0.00000001:
		return
	# Translate the entire articulated assembly, preserving all relative body
	# transforms and joint error. The CharacterBody remains the smooth carrier;
	# rigid bodies own rotations, contacts, and articulation around it.
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if body != null:
			body.global_position += correction

func maximum_linear_speed() -> float:
	var maximum := 0.0
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if body != null:
			maximum = maxf(maximum, body.linear_velocity.length())
	return maximum

func maximum_angular_speed() -> float:
	var maximum := 0.0
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if body != null:
			maximum = maxf(maximum, body.angular_velocity.length())
	return maximum

func maximum_joint_error() -> float:
	var maximum := 0.0
	for entry: Dictionary in _joint_anchors:
		var body_a := entry["body_a"] as RigidBody3D
		var body_b := entry["body_b"] as RigidBody3D
		if body_a == null or body_b == null:
			continue
		var world_a := body_a.global_transform * (entry["anchor_a"] as Vector3)
		var world_b := body_b.global_transform * (entry["anchor_b"] as Vector3)
		var error := world_a.distance_to(world_b)
		if is_finite(error):
			maximum = maxf(maximum, error)
	return maximum

func has_ground_support() -> bool:
	var pelvis_body := bodies.get(&"pelvis") as RigidBody3D
	if pelvis_body == null or not pelvis_body.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(
		pelvis_body.global_position + Vector3.UP * 0.15,
		pelvis_body.global_position + Vector3.DOWN * 1.25,
		TERRAIN_AND_FEATURE_MASK
	)
	var excluded: Array[RID] = []
	for body_value: Variant in bodies.values():
		var body := body_value as RigidBody3D
		if body != null:
			excluded.append(body.get_rid())
	query.exclude = excluded
	return not pelvis_body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func snapshot() -> Dictionary:
	return {
		"active": active,
		"recovering": recovering,
		"age": age,
		"severity": severity,
		"body_count": bodies.size(),
		"joint_count": _joints.size(),
		"left_ski_released": left_ski_released,
		"right_ski_released": right_ski_released,
		"left_pole_released": left_pole_released,
		"right_pole_released": right_pole_released,
		"linear_speed": pelvis_velocity().length(),
		"angular_speed": pelvis_angular_velocity().length(),
		"joint_error": maximum_joint_error(),
	}

func _choose_equipment_release(binding_severity: float, lateral_bias: float) -> void:
	left_pole_released = binding_severity >= _profile.ragdoll_pole_release_severity
	right_pole_released = left_pole_released
	if binding_severity >= _profile.ragdoll_release_both_severity:
		left_ski_released = true
		right_ski_released = true
	elif binding_severity >= _profile.ragdoll_release_one_severity:
		if lateral_bias < 0.0:
			left_ski_released = true
		else:
			right_ski_released = true

func _has_required_transforms(world_transforms: Dictionary) -> bool:
	for semantic: StringName in REQUIRED_BODY_SEMANTICS:
		if not world_transforms.has(semantic):
			return false
	if left_ski_released and not world_transforms.has(&"left_ski"):
		return false
	if right_ski_released and not world_transforms.has(&"right_ski"):
		return false
	if left_pole_released and not world_transforms.has(&"left_pole"):
		return false
	if right_pole_released and not world_transforms.has(&"right_pole"):
		return false
	return true

func _add_limb(
	world_transforms: Dictionary,
	id: StringName,
	start_semantic: StringName,
	end_semantic: StringName,
	radius: float,
	mass: float
) -> void:
	_add_capsule(id, _origin(world_transforms, start_semantic), _origin(world_transforms, end_semantic), radius, mass)

func _add_equipment(world_transforms: Dictionary) -> void:
	for side: StringName in [&"left", &"right"]:
		var ski_id := StringName(String(side) + "_ski")
		var ski_released := left_ski_released if side == &"left" else right_ski_released
		if ski_released:
			var ski_transform := world_transforms.get(ski_id, Transform3D.IDENTITY) as Transform3D
			_add_box(ski_id, ski_transform, Vector3(0.12, 0.045, 1.62), 2.8)
		var pole_id := StringName(String(side) + "_pole")
		var pole_released := left_pole_released if side == &"left" else right_pole_released
		if not pole_released:
			continue
		var tip_id := StringName(String(side) + "_pole_tip")
		var pivot := _origin(world_transforms, pole_id)
		var tip := _origin(world_transforms, tip_id)
		if pivot.distance_squared_to(tip) < 0.01:
			tip = pivot + Vector3.DOWN * 1.185
		_add_capsule(pole_id, pivot, tip, 0.018, 0.28)

func _add_capsule(id: StringName, start: Vector3, end: Vector3, radius: float, mass: float) -> RigidBody3D:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.UP * maxf(radius * 2.0, 0.1)
	var body := _new_body(id, mass)
	body.global_transform = Transform3D(_basis_from_y(direction.normalized()), (start + end) * 0.5)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(direction.length(), radius * 2.0)
	collision.shape = shape
	body.add_child(collision)
	return body

func _add_box(id: StringName, world_transform: Transform3D, size: Vector3, mass: float) -> RigidBody3D:
	var body := _new_body(id, mass)
	body.global_transform = world_transform.orthonormalized()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _new_body(id: StringName, body_mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = String(id).to_pascal_case()
	body.mass = body_mass
	body.collision_layer = RAGDOLL_LAYER
	body.collision_mask = TERRAIN_AND_FEATURE_MASK
	body.continuous_cd = true
	body.can_sleep = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.physics_material_override = _physics_material
	add_child(body)
	body.top_level = true
	bodies[id] = body
	return body

func _add_cone_joint(
	id: StringName,
	body_a: RigidBody3D,
	body_b: RigidBody3D,
	anchor: Vector3,
	swing_degrees: float,
	twist_degrees: float
) -> void:
	var joint := ConeTwistJoint3D.new()
	joint.name = String(id).to_pascal_case()
	add_child(joint)
	joint.top_level = true
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_degrees))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_degrees))
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
	body_a.add_collision_exception_with(body_b)
	_joints.append(joint)
	_joint_anchors.append({
		"body_a": body_a,
		"body_b": body_b,
		"anchor_a": body_a.global_transform.affine_inverse() * anchor,
		"anchor_b": body_b.global_transform.affine_inverse() * anchor,
	})

func _apply_ski_snow_resistance(id: StringName, released: bool) -> void:
	var ski := bodies.get(id) as RigidBody3D
	if ski == null or ski.freeze:
		return
	var forward := -ski.global_basis.z.normalized()
	var right := ski.global_basis.x.normalized()
	var forward_speed := ski.linear_velocity.dot(forward)
	var lateral_speed := ski.linear_velocity.dot(right)
	var lateral_grip := _profile.ragdoll_released_ski_lateral_drag if released else _profile.ragdoll_attached_ski_lateral_drag
	var force := -forward * forward_speed * _profile.ragdoll_ski_longitudinal_drag
	force -= right * lateral_speed * lateral_grip
	ski.apply_central_force(force)

func _origin(world_transforms: Dictionary, semantic: StringName) -> Vector3:
	return (world_transforms.get(semantic, Transform3D.IDENTITY) as Transform3D).origin

func _pose_body_id(semantic: StringName) -> StringName:
	match semantic:
		&"left_ski":
			return &"left_ski" if left_ski_released else &"left_shin"
		&"right_ski":
			return &"right_ski" if right_ski_released else &"right_shin"
		&"left_pole":
			return &"left_pole" if left_pole_released else &"left_forearm"
		&"right_pole":
			return &"right_pole" if right_pole_released else &"right_forearm"
	return POSE_BODY.get(semantic, &"") as StringName

func _basis_from_y(up_axis: Vector3) -> Basis:
	var y := up_axis.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z).orthonormalized()
