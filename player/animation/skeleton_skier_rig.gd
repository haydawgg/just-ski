class_name SkeletonSkierRig
extends SkierRigAdapter

const TRANSLATED_JOINTS := [&"pelvis", &"chest", &"left_shoulder", &"right_shoulder"]
const DEFAULT_BODY_PATH := "res://assets/characters/skier/skier_body.glb"
const DEFAULT_OUTFIT := preload("res://resources/character/default_skier_outfit_profile.tres")
const MAX_HELPER_TURN := PI

@export var outfit_profile: SkierOutfitProfile = DEFAULT_OUTFIT

# Retarget chains in parent-first order. Each sequence starts from the accumulated
# canonical and model world rotations of its root context semantic.
const SYNC_SEQUENCES := [
	[&"pelvis", &"spine", &"chest", &"head"],
	[&"left_hip", &"left_knee", &"left_boot"],
	[&"right_hip", &"right_knee", &"right_boot"],
	[&"left_shoulder", &"left_elbow", &"left_hand"],
	[&"right_shoulder", &"right_elbow", &"right_hand"],
]
const SEQUENCE_ROOT_CONTEXT := {
	&"left_hip": &"pelvis",
	&"right_hip": &"pelvis",
	&"left_shoulder": &"chest",
	&"right_shoulder": &"chest",
}
const CHAIN_PARENTS := {
	&"pelvis": &"",
	&"spine": &"pelvis",
	&"chest": &"spine",
	&"head": &"chest",
	&"left_hip": &"pelvis",
	&"left_knee": &"left_hip",
	&"left_boot": &"left_knee",
	&"right_hip": &"pelvis",
	&"right_knee": &"right_hip",
	&"right_boot": &"right_knee",
	&"left_shoulder": &"chest",
	&"left_elbow": &"left_shoulder",
	&"left_hand": &"left_elbow",
	&"right_shoulder": &"chest",
	&"right_elbow": &"right_shoulder",
	&"right_hand": &"right_elbow",
}

var profile: SkierSkeletonProfile
var body_root: Node3D
var skeleton: Skeleton3D
var bone_indices: Dictionary = {}
var initial_pose_positions: Dictionary = {}
var equipment_nodes: Dictionary = {}
var equipment_targets: Dictionary = {}
var equipment_tips: Dictionary = {}
# World-space orientation each mapped bone should hold when the canonical driver
# is at rest. Defaults to the model's own bind orientation; limb bones whose bind
# direction disagrees with the canonical rest direction are redirected.
var _neutral_world: Dictionary = {}
# Model transform rotation, used to convert canonical deltas into skeleton space.
var _axis: Quaternion = Quaternion.IDENTITY
# Per-bone inverse of unmapped helper-bone rest rotations between the mapped
# parent and the bone, baked into local poses during sync.
var _unroll: Dictionary = {}
# Static bone-local position offsets (hip pinning) computed at configure time.
var _static_position_offsets: Dictionary = {}
var _helper_bone_indices: Dictionary = {}
var _initial_helper_pose_rotations: Dictionary = {}
var _production_arm_lengths: Dictionary = {}
var _grab_contact_points: Dictionary = {
	&"left": Vector3.ZERO,
	&"right": Vector3.ZERO,
}
var _grab_reach_errors: Dictionary = {
	&"left": 0.0,
	&"right": 0.0,
}
var _grab_target_world: Dictionary = {
	&"left": Vector3.ZERO,
	&"right": Vector3.ZERO,
}
var _grab_solver_state := "IDLE"

func configure(value: SkierPoseDriver, skeleton_profile: Resource = null) -> bool:
	if not super.configure(value, skeleton_profile):
		error_message = "Skeleton rig requires a canonical pose driver"
		return false
	profile = skeleton_profile as SkierSkeletonProfile
	if profile == null:
		error_message = "Skeleton profile is missing or has the wrong type"
		return false
	var body_scene := profile.body_scene
	if body_scene == null and ResourceLoader.exists(DEFAULT_BODY_PATH):
		body_scene = load(DEFAULT_BODY_PATH) as PackedScene
	if body_scene == null:
		error_message = "Skeleton body is missing; expected assets/characters/skier/skier_body.glb or profile.body_scene"
		return false
	body_root = body_scene.instantiate() as Node3D
	if body_root == null:
		error_message = "The configured body scene does not instantiate as Node3D"
		return false
	body_root.name = "SkinnedBody"
	body_root.transform = profile.model_transform
	add_child(body_root)
	skeleton = _find_skeleton(body_root)
	if skeleton == null:
		error_message = "The configured body scene contains no Skeleton3D"
		body_root.queue_free()
		body_root = null
		return false
	if profile.require_skinned_mesh and not _has_skinned_mesh(body_root):
		error_message = "The configured body scene contains no skinned MeshInstance3D"
		body_root.queue_free()
		body_root = null
		skeleton = null
		return false
	if not _cache_and_validate_bones():
		body_root.queue_free()
		body_root = null
		skeleton = null
		return false
	_compute_unroll()
	_compute_retarget_calibration()
	_apply_body_materials(body_root)
	_build_attachments()
	sync_pose(0.0, [])
	return true

func sync_pose(_delta: float, grab_requests: Array[SkierGrabReachRequest] = []) -> void:
	if skeleton == null or driver == null:
		return
	transform = driver.joint(&"balance_root").transform
	_reset_helper_poses()
	var axis_inverse := _axis.inverse()
	var canonical_world: Dictionary = {}
	var model_world: Dictionary = {}
	for sequence: Array in SYNC_SEQUENCES:
		var root: StringName = sequence[0]
		var context: StringName = SEQUENCE_ROOT_CONTEXT.get(root, &"")
		var canonical: Quaternion = canonical_world.get(context, Quaternion.IDENTITY)
		var parent_skeleton: Quaternion = model_world.get(context, Quaternion.IDENTITY)
		var parent_neutral: Quaternion = _neutral_world.get(context, Quaternion.IDENTITY)
		for semantic: StringName in sequence:
			var index := int(bone_indices[semantic])
			var source := driver.joint(semantic)
			var delta := Quaternion.from_euler(source.rotation)
			if profile.axis_corrections.has(semantic):
				var correction := _as_quaternion(profile.axis_corrections[semantic], Quaternion.IDENTITY)
				delta = correction * delta * correction.inverse()
			canonical = canonical * delta
			# Adapter-space orientation, then converted into skeleton space: bone
			# poses are written below the model transform, so its rotation must not
			# be baked into the pose a second time. The unroll factor cancels the
			# rest rotations of unmapped helper bones in between.
			var world := axis_inverse * (canonical * (_neutral_world[semantic] as Quaternion))
			skeleton.set_bone_pose_rotation(index, (_unroll[semantic] as Quaternion) * parent_skeleton.inverse() * world)
			var pose_position := initial_pose_positions[semantic] as Vector3
			if semantic in TRANSLATED_JOINTS:
				var offset := (source.position - driver.rest_position(semantic)) * profile.pose_translation_scale
				pose_position += (_unroll[semantic] as Quaternion) * (parent_neutral as Quaternion).inverse() * offset
			if _static_position_offsets.has(semantic):
				pose_position += _static_position_offsets[semantic]
			skeleton.set_bone_pose_position(index, pose_position)
			canonical_world[semantic] = canonical
			model_world[semantic] = world
			parent_skeleton = world
			parent_neutral = _neutral_world[semantic] as Quaternion
	skeleton.force_update_all_bone_transforms()
	_sync_equipment_pose()
	_apply_grab_reach(grab_requests)

func adapter_name() -> String:
	return "skeleton"

func landmarks() -> Dictionary:
	if skeleton == null:
		return super.landmarks()
	return {
		"head": _bone_world(&"head").origin + skeleton.global_basis * profile.head_landmark_offset,
		"pelvis": _bone_world(&"pelvis").origin,
		"left_knee": _bone_world(&"left_knee").origin,
		"right_knee": _bone_world(&"right_knee").origin,
		"left_boot": _bone_world(&"left_boot").origin,
		"right_boot": _bone_world(&"right_boot").origin,
		"left_ski_nose": (equipment_targets[&"left_nose"] as Node3D).global_position,
		"right_ski_nose": (equipment_targets[&"right_nose"] as Node3D).global_position,
		"left_ski_tail": (equipment_targets[&"left_tail"] as Node3D).global_position,
		"right_ski_tail": (equipment_targets[&"right_tail"] as Node3D).global_position,
		"left_hand": _bone_world(&"left_hand").origin,
		"right_hand": _bone_world(&"right_hand").origin,
		"left_hand_contact": grab_contact_point(&"left"),
		"right_hand_contact": grab_contact_point(&"right"),
		"left_pole_tip": (equipment_tips[&"left"] as Node3D).global_position,
		"right_pole_tip": (equipment_tips[&"right"] as Node3D).global_position,
	}

func grab_target(side: StringName, target: StringName) -> Node3D:
	# Production contact must be measured against the marker attached to the
	# visible ski, not the canonical driver's parallel marker.
	return equipment_targets.get(StringName("%s_%s" % [side, target])) as Node3D

func arm_lengths(side: StringName) -> Vector2:
	if _production_arm_lengths.has(side):
		return _production_arm_lengths[side] as Vector2
	return super.arm_lengths(side)

func owns_grab_reach() -> bool:
	return skeleton != null

func grab_contact_point(side: StringName) -> Vector3:
	if skeleton == null or not bone_indices.has(StringName("%s_hand" % side)):
		return super.grab_contact_point(side)
	var hand := _bone_world(StringName("%s_hand" % side))
	var offset := profile.hand_contact_offsets.get(side, Vector3.ZERO) as Vector3
	return hand.origin + hand.basis.orthonormalized() * offset

func grab_reach_error(side: StringName) -> float:
	return float(_grab_reach_errors.get(side, 0.0))

func grab_target_world(side: StringName) -> Vector3:
	return _grab_target_world.get(side, Vector3.ZERO) as Vector3

func grab_debug_snapshot() -> Dictionary:
	var left_shoulder_transform := _bone_world(&"left_shoulder") if skeleton != null else Transform3D.IDENTITY
	var left_elbow_transform := _bone_world(&"left_elbow") if skeleton != null else Transform3D.IDENTITY
	var left_hand_transform := _bone_world(&"left_hand") if skeleton != null else Transform3D.IDENTITY
	var right_shoulder_transform := _bone_world(&"right_shoulder") if skeleton != null else Transform3D.IDENTITY
	var right_elbow_transform := _bone_world(&"right_elbow") if skeleton != null else Transform3D.IDENTITY
	var right_hand_transform := _bone_world(&"right_hand") if skeleton != null else Transform3D.IDENTITY
	return {
		"solver": _grab_solver_state,
		"left_arm_lengths": _production_arm_lengths.get(&"left", Vector2.ZERO),
		"right_arm_lengths": _production_arm_lengths.get(&"right", Vector2.ZERO),
		"left_contact_point": _grab_contact_points.get(&"left", Vector3.ZERO),
		"right_contact_point": _grab_contact_points.get(&"right", Vector3.ZERO),
		"left_target": _grab_target_world.get(&"left", Vector3.ZERO),
		"right_target": _grab_target_world.get(&"right", Vector3.ZERO),
		"left_reach_error": _grab_reach_errors.get(&"left", 0.0),
		"right_reach_error": _grab_reach_errors.get(&"right", 0.0),
		"helper_bones": _helper_bone_indices.duplicate(),
		"left_shoulder": left_shoulder_transform.origin,
		"left_elbow": left_elbow_transform.origin,
		"left_hand": left_hand_transform.origin,
		"right_shoulder": right_shoulder_transform.origin,
		"right_elbow": right_elbow_transform.origin,
		"right_hand": right_hand_transform.origin,
		"upper_spine": _bone_world_index(int(_helper_bone_indices[&"upper_spine"])).origin if _helper_bone_indices.has(&"upper_spine") else Vector3.ZERO,
		"chest": _bone_world(&"chest").origin,
		"left_clavicle": _bone_world_index(int(_helper_bone_indices[&"left_clavicle"])).origin if _helper_bone_indices.has(&"left_clavicle") else Vector3.ZERO,
		"right_clavicle": _bone_world_index(int(_helper_bone_indices[&"right_clavicle"])).origin if _helper_bone_indices.has(&"right_clavicle") else Vector3.ZERO,
	}

func _cache_and_validate_bones() -> bool:
	var used: Dictionary = {}
	_helper_bone_indices.clear()
	_initial_helper_pose_rotations.clear()
	_production_arm_lengths.clear()
	for semantic: StringName in profile.required_semantics():
		var bone_name := StringName(profile.bone_names.get(semantic, &""))
		if bone_name == &"":
			error_message = "No bone mapping for %s" % semantic
			return false
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			error_message = "Mapped bone '%s' for %s was not found" % [bone_name, semantic]
			return false
		if used.has(index):
			error_message = "Bone '%s' is mapped to both %s and %s" % [bone_name, used[index], semantic]
			return false
		used[index] = semantic
		bone_indices[semantic] = index
		initial_pose_positions[semantic] = skeleton.get_bone_pose_position(index)
		if not _finite_transform(skeleton.get_bone_rest(index)):
			error_message = "Bone '%s' has a non-finite rest transform" % bone_name
			return false
	for chain: Array in [
		[&"pelvis", &"spine", &"chest", &"head"],
		[&"pelvis", &"left_hip", &"left_knee", &"left_boot"],
		[&"pelvis", &"right_hip", &"right_knee", &"right_boot"],
		[&"chest", &"left_shoulder", &"left_elbow", &"left_hand"],
		[&"chest", &"right_shoulder", &"right_elbow", &"right_hand"],
	]:
		for position: int in range(chain.size() - 1):
			if not _is_descendant(int(bone_indices[chain[position + 1]]), int(bone_indices[chain[position]])):
				error_message = "%s must descend from %s" % [chain[position + 1], chain[position]]
				return false
	for semantic: StringName in profile.helper_semantics():
		var bone_name := StringName(profile.helper_bone_names.get(semantic, &""))
		if bone_name == &"":
			continue
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			error_message = "Optional helper bone '%s' for %s was not found" % [bone_name, semantic]
			return false
		if used.has(index):
			error_message = "Bone '%s' is mapped to both %s and %s" % [bone_name, used[index], semantic]
			return false
		used[index] = semantic
		_helper_bone_indices[semantic] = index
		_initial_helper_pose_rotations[semantic] = skeleton.get_bone_pose_rotation(index)
	for relation: Array in [
		[&"upper_spine", &"spine"],
		[&"left_clavicle", &"chest"],
		[&"right_clavicle", &"chest"],
	]:
		var helper: StringName = relation[0]
		if not _helper_bone_indices.has(helper):
			continue
		if not _is_descendant(int(_helper_bone_indices[helper]), int(bone_indices[relation[1]])):
			error_message = "%s must descend from %s" % [helper, relation[1]]
			return false
	return true

func _compute_retarget_calibration() -> void:
	_neutral_world.clear()
	_static_position_offsets.clear()
	_production_arm_lengths.clear()
	_axis = profile.model_transform.basis.orthonormalized().get_rotation_quaternion()
	for semantic: StringName in profile.required_semantics():
		var rest := _model_bone_rest(semantic)
		_neutral_world[semantic] = rest.basis.orthonormalized().get_rotation_quaternion()
	# The model binds in an A-pose while the canonical rest keeps the arms hanging;
	# rotate the whole arm chain (shoulder, elbow, hand) rigidly to match.
	for side: StringName in [&"left", &"right"]:
		var shoulder := StringName(side + "_shoulder")
		var elbow := StringName(side + "_elbow")
		var direction := _model_bone_rest(elbow).origin - _model_bone_rest(shoulder).origin
		if direction.length_squared() < 0.0001:
			continue
		var redirect := Quaternion(direction.normalized(), Vector3.DOWN)
		for semantic: StringName in [shoulder, elbow, StringName(side + "_hand")]:
			_neutral_world[semantic] = redirect * (_neutral_world[semantic] as Quaternion)
	for semantic: StringName in profile.neutral_pose_rotations:
		_neutral_world[semantic] = _as_quaternion(profile.neutral_pose_rotations[semantic], _neutral_world.get(semantic, Quaternion.IDENTITY))
	# Pin the hips so the model ankles (and the skis mounted on them) rest on the
	# canonical boot positions, preserving ground contact and stance width.
	for side: StringName in [&"left", &"right"]:
		var boot := StringName(side + "_boot")
		var delta := _canonical_rest_world(boot) - _model_bone_rest(boot).origin
		_static_position_offsets[StringName(side + "_hip")] = (_neutral_world[&"pelvis"] as Quaternion).inverse() * delta
		var shoulder_rest := _model_bone_rest(StringName(side + "_shoulder")).origin
		var elbow_rest := _model_bone_rest(StringName(side + "_elbow")).origin
		var hand_rest := _model_bone_rest(StringName(side + "_hand")).origin
		_production_arm_lengths[side] = Vector2(
			shoulder_rest.distance_to(elbow_rest),
			elbow_rest.distance_to(hand_rest)
		)

func _compute_unroll() -> void:
	# Imported rigs may place unmapped helper bones (clavicles, extra spine
	# segments) between mapped joints. Their rest rotations stay part of the
	# skeleton chain, so each mapped bone's local pose bakes their inverse to
	# keep the retarget composition exact in world space.
	_unroll.clear()
	var mapped: Dictionary = {}
	for semantic: StringName in bone_indices:
		mapped[int(bone_indices[semantic])] = true
	for semantic: StringName in bone_indices:
		var unroll := Quaternion.IDENTITY
		var parent := skeleton.get_bone_parent(int(bone_indices[semantic]))
		while parent >= 0 and not mapped.has(parent):
			unroll = unroll * skeleton.get_bone_rest(parent).basis.get_rotation_quaternion().inverse()
			parent = skeleton.get_bone_parent(parent)
		_unroll[semantic] = unroll

func _reset_helper_poses() -> void:
	for semantic: StringName in _initial_helper_pose_rotations:
		var index := int(_helper_bone_indices[semantic])
		skeleton.set_bone_pose_rotation(index, _initial_helper_pose_rotations[semantic] as Quaternion)
	_grab_solver_state = "IDLE"
	for side: StringName in [&"left", &"right"]:
		_grab_contact_points[side] = Vector3.ZERO
		_grab_reach_errors[side] = 0.0
		_grab_target_world[side] = Vector3.ZERO

func _apply_grab_reach(requests: Array[SkierGrabReachRequest]) -> void:
	var valid_requests: Array[SkierGrabReachRequest] = []
	for request: SkierGrabReachRequest in requests:
		if request == null or request.side not in [&"left", &"right"]:
			continue
		if request.target_marker == null or not is_instance_valid(request.target_marker):
			continue
		# Track the live marker even while the authored reach is still in setup.
		# This keeps lifecycle diagnostics meaningful before the final solve has
		# enough weight to move the production arm.
		var target_world := request.target_marker.global_position
		var contact_point := grab_contact_point(request.side)
		_grab_target_world[request.side] = target_world
		_grab_contact_points[request.side] = contact_point
		_grab_reach_errors[request.side] = contact_point.distance_to(target_world)
		if request.weight > 0.001:
			valid_requests.append(request)
	if valid_requests.is_empty():
		if not requests.is_empty():
			_grab_solver_state = "TRACKING"
		return
	_grab_solver_state = "ACTIVE"
	_apply_upper_spine_assist(valid_requests)
	for request: SkierGrabReachRequest in valid_requests:
		_apply_clavicle_assist(request)
	skeleton.force_update_all_bone_transforms()
	for request: SkierGrabReachRequest in valid_requests:
		_solve_production_arm(request)
	skeleton.force_update_all_bone_transforms()
	var all_in_contact := true
	for request: SkierGrabReachRequest in valid_requests:
		var target_world := request.target_marker.global_position
		var contact_point := grab_contact_point(request.side)
		var reach_error := contact_point.distance_to(target_world)
		_grab_target_world[request.side] = target_world
		_grab_contact_points[request.side] = contact_point
		_grab_reach_errors[request.side] = reach_error
		all_in_contact = all_in_contact and reach_error <= 0.12
	_grab_solver_state = "CONTACT" if all_in_contact else "SOLVED"

func _apply_upper_spine_assist(requests: Array[SkierGrabReachRequest]) -> void:
	if not _helper_bone_indices.has(&"upper_spine"):
		return
	var target_sum := Vector3.ZERO
	var weight_sum := 0.0
	for request: SkierGrabReachRequest in requests:
		target_sum += request.target_marker.global_position * request.weight
		weight_sum += request.weight
	if weight_sum <= 0.001:
		return
	var helper_index := int(_helper_bone_indices[&"upper_spine"])
	var child_index := int(bone_indices[&"chest"])
	var helper_transform := _bone_world_index(helper_index)
	var child_position := _bone_world_index(child_index).origin
	var current_direction := child_position - helper_transform.origin
	var target_direction := target_sum / weight_sum - helper_transform.origin
	if current_direction.length_squared() < 0.0001 or target_direction.length_squared() < 0.0001:
		return
	var average_weight := clampf(weight_sum / float(requests.size()), 0.0, 1.0)
	# The mapped spine segment is the long visual lever into the optional
	# upper-spine helper. Rotating it only for active requests lets the helper
	# reach assist fold the production torso without translating gameplay or
	# changing the canonical driver.
	var parent_index := int(bone_indices[&"spine"])
	var parent_transform := _bone_world_index(parent_index)
	var parent_child_transform := _bone_world_index(helper_index)
	var parent_direction := parent_child_transform.origin - parent_transform.origin
	var parent_target_direction := target_sum / weight_sum - parent_transform.origin
	if parent_direction.length_squared() > 0.0001 and parent_target_direction.length_squared() > 0.0001:
		var parent_assist := clampf(profile.upper_spine_reach_assist * average_weight * 0.65, 0.0, 1.0)
		var parent_limit := minf(clampf(profile.upper_spine_reach_limit, 0.0, MAX_HELPER_TURN) * 0.65, 1.2)
		var assisted_parent_direction := _slerp_direction(parent_direction, parent_target_direction, parent_assist)
		assisted_parent_direction = _limit_direction_turn(parent_direction, assisted_parent_direction, parent_limit)
		_set_bone_world_rotation(
			parent_index,
			_aligned_world_rotation(parent_index, helper_index, assisted_parent_direction)
		)
		skeleton.force_update_all_bone_transforms()
		helper_transform = _bone_world_index(helper_index)
		child_position = _bone_world_index(child_index).origin
	var assisted_direction := _slerp_direction(
		current_direction,
		target_direction,
		profile.upper_spine_reach_assist * average_weight
	)
	assisted_direction = _limit_direction_turn(
		current_direction,
		assisted_direction,
		clampf(profile.upper_spine_reach_limit, 0.0, MAX_HELPER_TURN)
	)
	_set_bone_world_rotation(
		helper_index,
		_aligned_world_rotation(helper_index, child_index, assisted_direction)
	)
	skeleton.force_update_all_bone_transforms()

func _apply_clavicle_assist(request: SkierGrabReachRequest) -> void:
	var helper_semantic := StringName("%s_clavicle" % request.side)
	if not _helper_bone_indices.has(helper_semantic):
		return
	var shoulder_semantic := StringName("%s_shoulder" % request.side)
	var helper_index := int(_helper_bone_indices[helper_semantic])
	var shoulder_index := int(bone_indices[shoulder_semantic])
	var helper_position := _bone_world_index(helper_index).origin
	var shoulder_position := _bone_world_index(shoulder_index).origin
	var target_position := _ik_target_position(request)
	var current_direction := shoulder_position - helper_position
	var target_direction := target_position - helper_position
	if current_direction.length_squared() < 0.0001 or target_direction.length_squared() < 0.0001:
		return
	var arm_lengths_value := arm_lengths(request.side)
	var arm_reach := arm_lengths_value.x + arm_lengths_value.y
	var desired_direction := current_direction
	if shoulder_position.distance_to(target_position) > arm_reach * 0.94:
		desired_direction = _reachable_clavicle_direction(
			helper_position,
			shoulder_position,
			target_position,
			arm_reach,
			request.side
		)
	else:
		desired_direction = _slerp_direction(current_direction, target_direction, 0.18)
	desired_direction = _slerp_direction(
		current_direction,
		desired_direction,
		profile.clavicle_reach_assist * request.weight
	)
	desired_direction = _limit_direction_turn(
		current_direction,
		desired_direction,
		clampf(profile.clavicle_reach_limit, 0.0, MAX_HELPER_TURN)
	)
	_set_bone_world_rotation(
		helper_index,
		_aligned_world_rotation(helper_index, shoulder_index, desired_direction)
	)
	skeleton.force_update_all_bone_transforms()

func _solve_production_arm(request: SkierGrabReachRequest) -> void:
	var shoulder_semantic := StringName("%s_shoulder" % request.side)
	var elbow_semantic := StringName("%s_elbow" % request.side)
	var hand_semantic := StringName("%s_hand" % request.side)
	var shoulder_index := int(bone_indices[shoulder_semantic])
	var elbow_index := int(bone_indices[elbow_semantic])
	var hand_index := int(bone_indices[hand_semantic])
	var shoulder_position := _bone_world_index(shoulder_index).origin
	var elbow_position := _bone_world_index(elbow_index).origin
	var hand_target := _ik_target_position(request)
	var target_delta := hand_target - shoulder_position
	if target_delta.length_squared() < 0.0001:
		return
	var lengths := arm_lengths(request.side)
	var upper_length := maxf(lengths.x, 0.01)
	var lower_length := maxf(lengths.y, 0.01)
	# Keep the target inside the measured two-bone envelope so the solve never
	# hyperextends or changes segment scale when a marker is genuinely too far.
	var maximum_distance := maxf(upper_length + lower_length - 0.002, 0.01)
	var minimum_distance := absf(upper_length - lower_length) + 0.002
	var distance := clampf(target_delta.length(), minimum_distance, maximum_distance)
	var direction := target_delta.normalized()
	var bend_axis := elbow_position - shoulder_position
	bend_axis -= direction * bend_axis.dot(direction)
	if bend_axis.length_squared() < 0.0001:
		var chest_basis := _bone_world(&"chest").basis.orthonormalized()
		var side_sign := -1.0 if request.side == &"left" else 1.0
		bend_axis = chest_basis.x * side_sign
		bend_axis -= direction * bend_axis.dot(direction)
	if bend_axis.length_squared() < 0.0001:
		bend_axis = Vector3.UP.cross(direction)
	if bend_axis.length_squared() < 0.0001:
		return
	bend_axis = bend_axis.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var elbow_target := shoulder_position + direction * along + bend_axis * height
	var current_upper_direction := elbow_position - shoulder_position
	if current_upper_direction.length_squared() < 0.0001:
		current_upper_direction = direction
	var target_upper_direction := (elbow_target - shoulder_position).normalized()
	var upper_direction := _slerp_direction(
		current_upper_direction,
		target_upper_direction,
		request.weight
	)
	_set_bone_world_rotation(
		shoulder_index,
		_aligned_world_rotation(shoulder_index, elbow_index, upper_direction)
	)
	skeleton.force_update_all_bone_transforms()
	var solved_elbow_position := _bone_world_index(elbow_index).origin
	var current_hand_position := _bone_world_index(hand_index).origin
	var current_lower_direction := current_hand_position - solved_elbow_position
	if current_lower_direction.length_squared() < 0.0001:
		current_lower_direction = direction
	var target_lower_direction := hand_target - solved_elbow_position
	if target_lower_direction.length_squared() > 0.0001:
		var lower_direction := _slerp_direction(
			current_lower_direction,
			target_lower_direction,
			request.weight
		)
		_set_bone_world_rotation(
			elbow_index,
			_aligned_world_rotation(elbow_index, hand_index, lower_direction)
		)
		skeleton.force_update_all_bone_transforms()
	var target_rotation := _target_hand_rotation(request)
	var current_hand_rotation := _bone_world_index(hand_index).basis.orthonormalized().get_rotation_quaternion()
	_set_bone_world_rotation(hand_index, current_hand_rotation.slerp(target_rotation, request.weight).normalized())

func _reachable_clavicle_direction(root: Vector3, shoulder: Vector3, target: Vector3, arm_reach: float, side: StringName) -> Vector3:
	var current_direction := (shoulder - root).normalized()
	var target_delta := target - root
	var target_distance := target_delta.length()
	if target_distance < 0.0001 or current_direction.length_squared() < 0.0001:
		return current_direction
	var target_direction := target_delta / target_distance
	var clavicle_length := root.distance_to(shoulder)
	if clavicle_length < 0.0001:
		return current_direction
	if target_distance <= absf(clavicle_length - arm_reach) + 0.002:
		return target_direction
	var along := clampf(
		(clavicle_length * clavicle_length + target_distance * target_distance - arm_reach * arm_reach) / (2.0 * target_distance),
		-clavicle_length,
		clavicle_length
	)
	var height := sqrt(maxf(0.0, clavicle_length * clavicle_length - along * along))
	var bend_axis := current_direction - target_direction * current_direction.dot(target_direction)
	if bend_axis.length_squared() < 0.0001:
		var chest_basis := _bone_world(&"chest").basis.orthonormalized()
		var side_sign := -1.0 if side == &"left" else 1.0
		bend_axis = chest_basis.x * side_sign
		bend_axis -= target_direction * bend_axis.dot(target_direction)
	if bend_axis.length_squared() < 0.0001:
		bend_axis = Vector3.UP.cross(target_direction)
	if bend_axis.length_squared() < 0.0001:
		return current_direction
	bend_axis = bend_axis.normalized()
	var first := (target_direction * along + bend_axis * height) / clavicle_length
	var second := (target_direction * along - bend_axis * height) / clavicle_length
	return first if first.dot(current_direction) >= second.dot(current_direction) else second

func _ik_target_position(request: SkierGrabReachRequest) -> Vector3:
	var target_transform := request.target_marker.global_transform
	var target_rotation := _target_hand_rotation(request)
	var offset := profile.hand_contact_offsets.get(request.side, Vector3.ZERO) as Vector3
	return target_transform.origin - Basis(target_rotation) * offset

func _target_hand_rotation(request: SkierGrabReachRequest) -> Quaternion:
	var target_rotation := request.target_marker.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var correction := _as_quaternion(
		profile.hand_wrist_corrections.get(request.side, Quaternion.IDENTITY),
		Quaternion.IDENTITY
	)
	return (target_rotation * correction).normalized()

func _bone_world_index(index: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(index)

func _aligned_world_rotation(index: int, child_index: int, target_direction: Vector3) -> Quaternion:
	var bone_transform := _bone_world_index(index)
	var child_transform := _bone_world_index(child_index)
	var current_direction := child_transform.origin - bone_transform.origin
	if current_direction.length_squared() < 0.0001 or target_direction.length_squared() < 0.0001:
		return bone_transform.basis.orthonormalized().get_rotation_quaternion()
	return (_direction_rotation(current_direction.normalized(), target_direction.normalized()) * bone_transform.basis.orthonormalized().get_rotation_quaternion()).normalized()

func _set_bone_world_rotation(index: int, target_rotation: Quaternion) -> void:
	var parent_rotation := skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var parent_index := skeleton.get_bone_parent(index)
	if parent_index >= 0:
		parent_rotation = _bone_world_index(parent_index).basis.orthonormalized().get_rotation_quaternion()
	var local_rotation := (parent_rotation.inverse() * target_rotation).normalized()
	skeleton.set_bone_pose_rotation(index, local_rotation)

func _direction_rotation(from: Vector3, to: Vector3) -> Quaternion:
	var first := from.normalized()
	var second := to.normalized()
	var dot := clampf(first.dot(second), -1.0, 1.0)
	if dot > 0.9999:
		return Quaternion.IDENTITY
	if dot < -0.9999:
		var axis := Vector3.RIGHT.cross(first)
		if axis.length_squared() < 0.0001:
			axis = Vector3.UP.cross(first)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(first, second).normalized()

func _slerp_direction(from: Vector3, to: Vector3, weight: float) -> Vector3:
	if from.length_squared() < 0.0001:
		return to.normalized()
	if to.length_squared() < 0.0001:
		return from.normalized()
	return from.normalized().slerp(to.normalized(), clampf(weight, 0.0, 1.0)).normalized()

func _limit_direction_turn(from: Vector3, to: Vector3, limit: float) -> Vector3:
	if limit <= 0.0 or from.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return from.normalized()
	var angle := acos(clampf(from.normalized().dot(to.normalized()), -1.0, 1.0))
	if angle <= limit:
		return to.normalized()
	return _slerp_direction(from, to, limit / angle)

func _model_bone_rest(semantic: StringName) -> Transform3D:
	# Bind transform expressed in body space.
	return profile.model_transform * skeleton.get_bone_global_rest(int(bone_indices[semantic]))

func _canonical_rest_world(semantic: StringName) -> Vector3:
	var value := Vector3.ZERO
	var current := semantic
	while current != &"":
		value += driver.rest_position(current)
		current = CHAIN_PARENTS.get(current, &"")
	return value

func _build_attachments() -> void:
	var dark := SkierEquipment.material(outfit_profile.boot_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic)
	var boot_accent := SkierEquipment.material(outfit_profile.ski_accent_color.darkened(0.32), 0.48, 0.18)
	var ski_base := SkierEquipment.material(outfit_profile.ski_base_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic)
	var accent := SkierEquipment.material(outfit_profile.ski_accent_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic)
	var pole_surface := SkierEquipment.material(outfit_profile.pole_color, outfit_profile.hardgoods_roughness, 0.28)
	var helmet_surface := SkierEquipment.material(outfit_profile.helmet_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic)
	var frame_surface := SkierEquipment.material(outfit_profile.goggle_frame_color, 0.36, 0.18)
	var lens_surface := SkierEquipment.material(outfit_profile.goggle_lens_color, outfit_profile.lens_roughness, outfit_profile.lens_metallic, 0.82)
	var head_attachment := _bone_attachment(&"head", "HeadAttachment")
	var head_mount := Node3D.new()
	head_mount.name = "HeadMount"
	head_mount.transform = _neutral_mount_transform(&"head")
	head_attachment.add_child(head_mount)
	SkierEquipment.build_headwear(head_mount, helmet_surface, frame_surface, lens_surface)
	for side: StringName in [&"left", &"right"]:
		var boot_attachment := _bone_attachment(StringName(side + "_boot"), side.capitalize() + "BootAttachment")
		var boot_mount := Node3D.new()
		boot_mount.name = side.capitalize() + "BootMount"
		boot_mount.transform = _neutral_mount_transform(StringName(side + "_boot")) * (
			profile.left_boot_offset if side == &"left" else profile.right_boot_offset
		)
		boot_attachment.add_child(boot_mount)
		SkierEquipment.build_boot(boot_mount, side, dark, boot_accent)
		var ski_pivot := Node3D.new()
		ski_pivot.name = side.capitalize() + "SkiPivot"
		ski_pivot.position = driver.rest_position(StringName(side + "_ski"))
		boot_mount.add_child(ski_pivot)
		SkierEquipment.build_ski(ski_pivot, side, ski_base, accent)
		equipment_nodes[StringName(side + "_ski")] = ski_pivot
		_build_equipment_targets(ski_pivot, side)
		var pole_attachment := _bone_attachment(StringName(side + "_hand"), side.capitalize() + "PoleAttachment")
		var pole_mount := Node3D.new()
		pole_mount.name = side.capitalize() + "PoleMount"
		pole_mount.transform = _neutral_mount_transform(StringName(side + "_hand")) * (
			profile.left_pole_offset if side == &"left" else profile.right_pole_offset
		)
		pole_attachment.add_child(pole_mount)
		var pole_pivot := Node3D.new()
		pole_pivot.name = side.capitalize() + "PolePivot"
		pole_mount.add_child(pole_pivot)
		SkierEquipment.build_pole(pole_pivot, side, pole_surface, dark)
		var tip := Node3D.new()
		tip.name = side.capitalize() + "PoleTip"
		tip.position = Vector3(0.0, -1.08, 0.08)
		pole_pivot.add_child(tip)
		equipment_nodes[StringName(side + "_pole")] = pole_pivot
		equipment_tips[side] = tip

func _apply_body_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface_index: int in instance.mesh.get_surface_count():
			var imported := instance.mesh.surface_get_material(surface_index)
			var region := imported.resource_name.trim_prefix("Outfit_") if imported != null else ""
			var color := outfit_profile.jacket_color
			var roughness := outfit_profile.cloth_roughness
			match region:
				"Pants": color = outfit_profile.pants_color
				"Skin": color = outfit_profile.skin_color
				"Gloves":
					color = outfit_profile.glove_color
					roughness = outfit_profile.hardgoods_roughness
				"BootUnderlay":
					color = outfit_profile.boot_color
					roughness = outfit_profile.hardgoods_roughness
			var surface := SkierEquipment.material(color, roughness, 0.0)
			surface.resource_name = "Outfit_" + (region if region != "" else "Jacket")
			instance.set_surface_override_material(surface_index, surface)
	for child: Node in node.get_children():
		_apply_body_materials(child)

func _neutral_mount_transform(semantic: StringName) -> Transform3D:
	# BoneAttachment3D follows the bone's world pose, so a mount carrying the
	# inverse neutral orientation rides in the canonical joint frame at rest and
	# keeps tracking canonical joint rotations during animation.
	return Transform3D(Basis((_neutral_world[semantic] as Quaternion).inverse()), Vector3.ZERO)

func _build_equipment_targets(ski_pivot: Node3D, side: StringName) -> void:
	var side_sign := -1.0 if side == &"left" else 1.0
	for definition: Array in [
		[&"binding_outside", Vector3(0.075 * side_sign, 0.04, 0.05)],
		[&"binding_inside", Vector3(-0.075 * side_sign, 0.04, 0.02)],
		[&"nose", Vector3(0.0, 0.04, -0.72)],
		[&"tail", Vector3(0.0, 0.04, 0.42)],
	]:
		var marker := Node3D.new()
		marker.name = "%s_%s" % [side, definition[0]]
		marker.position = definition[1] as Vector3
		ski_pivot.add_child(marker)
		equipment_targets[StringName("%s_%s" % [side, definition[0]])] = marker

func _sync_equipment_pose() -> void:
	for side: StringName in [&"left", &"right"]:
		(equipment_nodes[StringName(side + "_ski")] as Node3D).rotation = driver.joint(StringName(side + "_ski")).rotation
		(equipment_nodes[StringName(side + "_pole")] as Node3D).rotation = driver.joint(StringName(side + "_pole")).rotation

func _bone_attachment(semantic: StringName, node_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = node_name
	attachment.bone_name = skeleton.get_bone_name(int(bone_indices[semantic]))
	attachment.override_pose = false
	skeleton.add_child(attachment)
	return attachment

func _bone_world(semantic: StringName) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(bone_indices[semantic]))

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _has_skinned_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
			return true
	for child: Node in node.get_children():
		if _has_skinned_mesh(child):
			return true
	return false

func _is_descendant(child_index: int, ancestor_index: int) -> bool:
	var current := child_index
	while current >= 0:
		if current == ancestor_index:
			return true
		current = skeleton.get_bone_parent(current)
	return false

func _finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()

func _as_quaternion(value: Variant, fallback: Quaternion) -> Quaternion:
	if value is Quaternion:
		return value as Quaternion
	if value is Vector3:
		return Quaternion.from_euler(value as Vector3)
	return fallback
