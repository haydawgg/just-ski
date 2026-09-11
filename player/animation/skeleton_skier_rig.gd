class_name SkeletonSkierRig
extends SkierRigAdapter

const TRANSLATED_JOINTS := [&"pelvis", &"chest", &"left_shoulder", &"right_shoulder"]
const DEFAULT_BODY_PATH := "res://assets/characters/skier/skier_body.glb"
const DEFAULT_OUTFIT := preload("res://resources/character/default_skier_outfit_profile.tres")
const MIN_POLE_KNEE_CLEARANCE := 0.10
const MIN_POLE_BODY_CLEARANCE := 0.015
## Minimum shaft-to-shaft clearance between the two poles. Shaft radius is
## 0.016 per pole, so 0.05 keeps visible daylight between the shafts.
const MIN_POLE_POLE_CLEARANCE := 0.05
const POLE_HAND_EXCLUSION_RATIO := 0.075
const POLE_SHAFT_LENGTH := 1.185
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
				var translation_frame := axis_inverse if CHAIN_PARENTS[semantic] == &"" else (parent_neutral as Quaternion).inverse()
				pose_position += (_unroll[semantic] as Quaternion) * translation_frame * offset
			if _static_position_offsets.has(semantic):
				pose_position += _static_position_offsets[semantic]
			skeleton.set_bone_pose_position(index, pose_position)
			canonical_world[semantic] = canonical
			model_world[semantic] = world
			parent_skeleton = world
			parent_neutral = _neutral_world[semantic] as Quaternion
	skeleton.force_update_all_bone_transforms()
	_sync_equipment_pose()
	# Reach must target this tick's ski pose, including its BoneAttachment.
	_refresh_bone_attachments()
	_apply_grab_reach(grab_requests)
	# BoneAttachment3D normally refreshes during the scene's notification pass.
	# Gameplay and capture callers can sample immediately after apply_frame,
	# though, so force the attachments to consume the same pose in this tick.
	# Without this explicit refresh, equipment mounted to moving hands/limbs can
	# remain at its previous-frame transform and read as detached during grabs,
	# flips, and rail transitions. This runs after optional production IK as well,
	# because the reach solve can move the hand bones a second time.
	_refresh_bone_attachments()
	_stabilize_equipment_poles()

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
		# Match the canonical segment lengths once at calibration. Pinning only
		# the neutral ankle leaves bent knees/boots centimetres off the solved
		# support pose because the imported thigh/shin lengths differ.
		for semantic: StringName in [StringName(side + "_hip"), StringName(side + "_knee"), boot]:
			var parent_semantic: StringName = CHAIN_PARENTS[semantic]
			var desired_segment := _canonical_rest_world(semantic) - _canonical_rest_world(parent_semantic)
			var model_segment := _model_bone_rest(semantic).origin - _model_bone_rest(parent_semantic).origin
			_static_position_offsets[semantic] = (_unroll[semantic] as Quaternion) * (_neutral_world[parent_semantic] as Quaternion).inverse() * (desired_segment - model_segment)
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
	var head_index := int(bone_indices[&"head"])
	var head_before := _bone_world_index(head_index).basis.orthonormalized().get_rotation_quaternion()
	_apply_upper_spine_assist(valid_requests)
	_refine_torso_reach(valid_requests)
	for request: SkierGrabReachRequest in valid_requests:
		_apply_clavicle_assist(request)
	skeleton.force_update_all_bone_transforms()
	_compensate_head_for_spine_assist(head_index, head_before)
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

func _compensate_head_for_spine_assist(head_index: int, head_before: Quaternion) -> void:
	# The upper-spine assist yanks the whole thorax and the head rides along
	# as a descendant, dragging the gaze toward the ski. Blend the head back
	# halfway toward its pre-assist world orientation so it keeps tracking the
	# canonical head: full restoration would look neck-broken against the
	# folded torso. Anchoring on the head's own before/after avoids any
	# assumption about which ancestor moved or in which rest frame it composes.
	# Blend is strong (0.97): like a real vestibulo-ocular reflex the gaze
	# stabilizes while the torso folds underneath it.
	var head_after := _bone_world_index(head_index).basis.orthonormalized().get_rotation_quaternion()
	_set_bone_world_rotation(head_index, head_after.slerp(head_before, 0.97).normalized())
	skeleton.force_update_all_bone_transforms()

func _apply_upper_spine_assist(requests: Array[SkierGrabReachRequest]) -> void:
	if not _helper_bone_indices.has(&"upper_spine"):
		return
	var target_sum := Vector3.ZERO
	var weight_sum := 0.0
	var assist_scale_sum := 0.0
	for request: SkierGrabReachRequest in requests:
		target_sum += request.target_marker.global_position * request.weight
		weight_sum += request.weight
		assist_scale_sum += request.upper_spine_assist_scale * request.weight
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
	var average_assist_scale := clampf(assist_scale_sum / maxf(weight_sum, 0.001), 0.0, 4.0)
	var assist_strength := profile.upper_spine_reach_assist * average_assist_scale
	var assist_limit := clampf(profile.upper_spine_reach_limit * average_assist_scale, 0.0, MAX_HELPER_TURN)
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
		var parent_assist := clampf(assist_strength * average_weight * 0.65, 0.0, 1.0)
		var parent_limit := minf(assist_limit * 0.65, 1.2)
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
		assist_strength * average_weight
	)
	assisted_direction = _limit_direction_turn(
		current_direction,
		assisted_direction,
		assist_limit
	)
	_set_bone_world_rotation(
		helper_index,
		_aligned_world_rotation(helper_index, child_index, assisted_direction)
	)
	skeleton.force_update_all_bone_transforms()

func _refine_torso_reach(requests: Array[SkierGrabReachRequest]) -> void:
	# Supplement the authored fold with at most 0.2 radians of reach-directed
	# correction, so reduced knee flex does not require longer arm segments.
	var index := int(bone_indices[&"spine"])
	var baseline := _bone_world_index(index).basis.orthonormalized().get_rotation_quaternion()
	for iteration: int in 5:
		var pivot := _bone_world_index(index).origin
		var current_sum := Vector3.ZERO
		var desired_sum := Vector3.ZERO
		var weight_sum := 0.0
		for request: SkierGrabReachRequest in requests:
			var shoulder := _bone_world(StringName("%s_shoulder" % request.side)).origin
			var toward := request.target_marker.global_position - shoulder
			var lengths := arm_lengths(request.side)
			var deficit := maxf(0.0, toward.length() - lengths.x - lengths.y + 0.04)
			current_sum += (shoulder - pivot) * request.weight
			desired_sum += (shoulder + toward.normalized() * deficit - pivot) * request.weight
			weight_sum += request.weight
		if current_sum.length_squared() < 0.0001 or desired_sum.length_squared() < 0.0001:
			continue
		var rotation := _bone_world_index(index).basis.orthonormalized().get_rotation_quaternion()
		var correction := Quaternion(current_sum.normalized(), desired_sum.normalized())
		var candidate := (correction * rotation).normalized()
		var limit := profile.upper_spine_reach_limit * 0.4 * clampf(weight_sum / requests.size(), 0.0, 1.0)
		var turn := baseline.angle_to(candidate)
		if turn > limit and turn > 0.0001:
			candidate = baseline.slerp(candidate, limit / turn).normalized()
		_set_bone_world_rotation(index, candidate)
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
		profile.clavicle_reach_assist * request.clavicle_assist_scale * request.weight
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
	var dark := SkierEquipment.material(outfit_profile.boot_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var boot_accent := SkierEquipment.material(outfit_profile.ski_accent_color.darkened(0.32), 0.48, 0.18, outfit_profile.hardgoods_specular)
	var ski_base := SkierEquipment.material(outfit_profile.ski_base_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var accent := SkierEquipment.material(outfit_profile.ski_accent_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var jacket := SkierEquipment.material(outfit_profile.jacket_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var jacket_trim := SkierEquipment.material(outfit_profile.jacket_trim_color, outfit_profile.cloth_roughness, 0.02, outfit_profile.cloth_specular)
	var jacket_accent := SkierEquipment.material(outfit_profile.jacket_panel_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var jacket_detail := SkierEquipment.material(outfit_profile.jacket_detail_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var pole_surface := SkierEquipment.material(outfit_profile.pole_color.darkened(0.16), outfit_profile.hardgoods_roughness, 0.28, outfit_profile.hardgoods_specular)
	var helmet_surface := SkierEquipment.material(outfit_profile.helmet_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var frame_surface := SkierEquipment.material(outfit_profile.goggle_frame_color, 0.36, 0.18, outfit_profile.hardgoods_specular)
	var lens_surface := SkierEquipment.material(outfit_profile.goggle_lens_color, outfit_profile.lens_roughness, outfit_profile.lens_metallic, outfit_profile.lens_specular)
	var head_attachment := _bone_attachment(&"head", "HeadAttachment")
	var head_mount := Node3D.new()
	head_mount.name = "HeadMount"
	head_mount.transform = _neutral_mount_transform(&"head")
	head_attachment.add_child(head_mount)
	SkierEquipment.build_headwear(head_mount, helmet_surface, frame_surface, lens_surface)
	# Shaded mouth line on the base-mesh chin (measured seating, not a guess).
	# Darkened skin reads as a mouth at gameplay distance without face texture.
	var mouth_surface := SkierEquipment.material(outfit_profile.skin_color.darkened(0.45), outfit_profile.skin_roughness, 0.0, outfit_profile.skin_specular)
	SkierEquipment.build_face(head_mount, mouth_surface, Vector3(0.0, 0.03, -0.112))
	var spine_attachment := _bone_attachment(&"spine", "JacketSpineAttachment")
	var spine_mount := Node3D.new()
	spine_mount.name = "JacketSpineMount"
	spine_mount.transform = _neutral_mount_transform(&"spine")
	spine_attachment.add_child(spine_mount)
	var chest_attachment := _bone_attachment(&"chest", "JacketChestAttachment")
	var chest_mount := Node3D.new()
	chest_mount.name = "JacketChestMount"
	chest_mount.transform = _neutral_mount_transform(&"chest")
	chest_attachment.add_child(chest_mount)
	# Jacket-detail depths seated against the imported insulated jacket shell
	# (measured, not eyeballed): stripe/zip inner faces ~2-4mm embedded, pocket
	# on the chest wall. Primitive-calibrated values would float centimeters
	# off this body, hence per-rig calibration.
	SkierEquipment.build_jacket_details(spine_mount, chest_mount, jacket_accent, jacket_detail, jacket_trim,
		0.152, -0.155, Vector3(-0.085, 0.06, -0.140))
	for side: StringName in [&"left", &"right"]:
		var shoulder_attachment := _bone_attachment(StringName(side + "_shoulder"), side.capitalize() + "SleeveShoulderAttachment")
		var shoulder_mount := Node3D.new()
		shoulder_mount.name = side.capitalize() + "SleeveShoulderMount"
		shoulder_mount.transform = _neutral_mount_transform(StringName(side + "_shoulder"))
		shoulder_attachment.add_child(shoulder_mount)
		var elbow_attachment := _bone_attachment(StringName(side + "_elbow"), side.capitalize() + "SleeveElbowAttachment")
		var elbow_mount := Node3D.new()
		elbow_mount.name = side.capitalize() + "SleeveElbowMount"
		elbow_mount.transform = _neutral_mount_transform(StringName(side + "_elbow"))
		elbow_attachment.add_child(elbow_mount)
		SkierEquipment.build_sleeves(shoulder_mount, elbow_mount, side, jacket, dark)
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
		tip.position = Vector3(0.0, -1.185, 0.0)
		pole_pivot.add_child(tip)
		equipment_nodes[StringName(side + "_pole")] = pole_pivot
		equipment_tips[side] = tip

func _apply_body_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface_index: int in instance.mesh.get_surface_count():
			var imported := instance.mesh.surface_get_material(surface_index)
			var region := imported.resource_name.trim_prefix("Outfit_") if imported != null else ""
			instance.set_surface_override_material(surface_index, SkierEquipment.region_surface(region, outfit_profile))
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
		[&"tail", SkierPoseDriver.GRAB_TAIL_OFFSET],
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

func _refresh_bone_attachments() -> void:
	if skeleton == null:
		return
	for child: Node in skeleton.get_children():
		var attachment := child as BoneAttachment3D
		if attachment != null:
			attachment.on_skeleton_update()

func _stabilize_equipment_poles() -> void:
	# Pole joints are authored relative to each hand, but a large grab/flip can
	# rotate a hand far enough that the local -Y shaft points above the skier.
	# Preserve authored angles while they are readable; only replace an inverted
	# presentation direction with a stable, slightly outward/downhill one.
	# Use the skier frame, not the imported model's quarter-turn calibration or
	# world gravity. During a flip the poles must rotate with their hands.
	var skier_basis := driver.global_basis.orthonormalized()
	var forward := -skier_basis.z
	var lateral := skier_basis.x
	var down := -skier_basis.y
	for side: StringName in [&"left", &"right"]:
		var pivot := equipment_nodes.get(StringName(side + "_pole")) as Node3D
		var tip := equipment_tips.get(side) as Node3D
		if pivot == null or tip == null:
			continue
		var current_direction := (tip.global_position - pivot.global_position).normalized()
		var downward_alignment := current_direction.dot(down)
		var grabbing := (_grab_target_world[side] as Vector3) != Vector3.ZERO
		var side_sign := -1.0 if side == &"left" else 1.0
		# Cross-body grabs and switch/style poses can move a hand across the
		# pelvis. Sweep away from the hand's actual lateral position so the pole
		# remains outside the nearest leg while preserving the hand attachment.
		side_sign = _pole_side_sign(side, pivot.global_position, lateral)
		# A pole can still be vertical enough to pass the gravity check while its
		# shaft is folded into the thigh during a grab or compact style pose. Keep
		# a small lateral clearance on every side of the skier before deciding the
		# authored orientation is safe.
		var lateral_alignment := current_direction.dot(lateral) * side_sign
		var lateral_correction := clampf((0.12 - lateral_alignment) / 0.55, 0.0, 1.0)
		var current_clearance := _minimum_pole_knee_clearance(pivot.global_position, tip.global_position)
		var clearance_correction := clampf((MIN_POLE_KNEE_CLEARANCE - current_clearance) / MIN_POLE_KNEE_CLEARANCE, 0.0, 1.0)
		var current_body_clearance := _minimum_pole_body_clearance(pivot.global_position, tip.global_position)
		var body_correction := clampf((MIN_POLE_BODY_CLEARANCE - current_body_clearance) / 0.12, 0.0, 1.0)
		if downward_alignment >= 0.58 and not grabbing and lateral_correction <= 0.0 and clearance_correction <= 0.0 and body_correction <= 0.0:
			continue
		var target_lateral_strength := 0.72 if grabbing else 0.28
		var target_direction := (down * 0.88 - forward * 0.32 + lateral * side_sign * target_lateral_strength).normalized()
		var target_tip := pivot.global_position + target_direction * POLE_SHAFT_LENGTH
		var target_clearance := _minimum_pole_knee_clearance(pivot.global_position, target_tip)
		var target_body_clearance := _minimum_pole_body_clearance(pivot.global_position, target_tip)
		var target_outward := target_direction.dot(lateral) * side_sign
		# Cross-body hands can sit on either side of several moving body capsules,
		# so one fixed fallback vector is not sufficient. Select from a bounded set
		# of readable outward/downhill directions using the current skeleton pose.
		if target_clearance < MIN_POLE_KNEE_CLEARANCE or target_body_clearance < MIN_POLE_BODY_CLEARANCE or target_outward < 0.08:
			target_direction = _safest_pole_direction(pivot.global_position, target_direction, side_sign, down, forward, lateral)
			target_tip = pivot.global_position + target_direction * POLE_SHAFT_LENGTH
			target_clearance = _minimum_pole_knee_clearance(pivot.global_position, target_tip)
			target_body_clearance = _minimum_pole_body_clearance(pivot.global_position, target_tip)
			target_outward = target_direction.dot(lateral) * side_sign
		var target_basis := _pole_basis_for_direction(target_direction, forward, lateral)
		# A hard replacement made a pole twitch when a grab or flip crossed the
		# readability threshold. Preserve the authored hand pose and blend only
		# the unsafe part back toward a downhill shaft direction.
		var vertical_correction := clampf((0.58 - downward_alignment) / 0.85, 0.0, 1.0)
		var correction_weight := maxf(maxf(maxf(maxf(0.85 if grabbing else 0.0, vertical_correction), lateral_correction), clearance_correction), body_correction)
		# Lateral violations need a firmer blend than the gentle vertical
		# readability correction; otherwise the shaft remains between the knees
		# for the entire held pose even though its tip points downhill.
		var blend_limit := 0.72 if lateral_correction <= 0.0 and clearance_correction <= 0.0 and body_correction <= 0.0 else 0.96
		pivot.global_basis = pivot.global_basis.slerp(target_basis, correction_weight * blend_limit).orthonormalized()
		# If the blended result is still inside the minimum envelope, finish the
		# correction in the same deterministic update rather than allowing a one
		# frame knee penetration to reach the renderer.
		if (lateral_alignment < 0.02 or _minimum_pole_knee_clearance(pivot.global_position, tip.global_position) < MIN_POLE_KNEE_CLEARANCE or _minimum_pole_body_clearance(pivot.global_position, tip.global_position) < MIN_POLE_BODY_CLEARANCE) and target_outward >= 0.08:
			pivot.global_basis = target_basis
		# Re-read the attachment after the transform write. BoneAttachment3D can
		# refresh its parent during a skeleton update, so a final deterministic
		# check prevents a style/switch pose from restoring an inward shaft.
		var final_direction := (tip.global_position - pivot.global_position).normalized()
		var final_side_sign := _pole_side_sign(side, pivot.global_position, lateral)
		if final_direction.dot(lateral) * final_side_sign < 0.02 or _minimum_pole_body_clearance(pivot.global_position, tip.global_position) < MIN_POLE_BODY_CLEARANCE:
			pivot.global_basis = target_basis
	_separate_pole_shafts(skier_basis)

## Symmetric pole-to-pole repulsion. After per-side stabilization, the two
## shafts can still cross (e.g. switch landings, tight tucks). Yaw both pivots
## outward around the skier-forward axis until shaft daylight reaches
## MIN_POLE_POLE_CLEARANCE. Skipped while either hand holds a grab, where
## poles intentionally gather near the ski. Rotation preserves pivot position;
## the per-frame cap plus the high release threshold prevent oscillation.
func _separate_pole_shafts(skier_basis: Basis) -> void:
	var left_pivot := equipment_nodes.get(&"left_pole") as Node3D
	var right_pivot := equipment_nodes.get(&"right_pole") as Node3D
	var left_tip := equipment_tips.get(&"left") as Node3D
	var right_tip := equipment_tips.get(&"right") as Node3D
	if left_pivot == null or right_pivot == null or left_tip == null or right_tip == null:
		return
	if (_grab_target_world.get(&"left", Vector3.ZERO) as Vector3) != Vector3.ZERO:
		return
	if (_grab_target_world.get(&"right", Vector3.ZERO) as Vector3) != Vector3.ZERO:
		return
	var left_start := left_pivot.global_position.lerp(left_tip.global_position, POLE_HAND_EXCLUSION_RATIO)
	var right_start := right_pivot.global_position.lerp(right_tip.global_position, POLE_HAND_EXCLUSION_RATIO)
	var distance := _segment_to_segment_distance(left_start, left_tip.global_position, right_start, right_tip.global_position)
	if not is_finite(distance) or distance >= MIN_POLE_POLE_CLEARANCE + 0.01:
		return
	# Rotating a downward shaft about the forward axis swings its tip
	# laterally: angle sign -side_sign moves each tip outward. See derivation
	# in _pole_basis_for_direction usage; capped so one frame cannot snap.
	var forward := -skier_basis.z
	if forward.length_squared() < 0.5 or not forward.is_finite():
		return
	forward = forward.normalized()
	var magnitude := clampf((MIN_POLE_POLE_CLEARANCE - distance) * 2.0, 0.0, 0.10)
	if magnitude <= 0.0001:
		return
	left_pivot.global_basis = (Basis(forward, magnitude) * left_pivot.global_basis).orthonormalized()
	right_pivot.global_basis = (Basis(forward, -magnitude) * right_pivot.global_basis).orthonormalized()

func pole_clearance_snapshot() -> Dictionary:
	var left_pivot := equipment_nodes.get(&"left_pole") as Node3D
	var right_pivot := equipment_nodes.get(&"right_pole") as Node3D
	var left_tip := equipment_tips.get(&"left") as Node3D
	var right_tip := equipment_tips.get(&"right") as Node3D
	if left_pivot == null or right_pivot == null or left_tip == null or right_tip == null:
		return {}
	var lateral := driver.global_basis.x.normalized()
	var left_direction := (left_tip.global_position - left_pivot.global_position).normalized()
	var right_direction := (right_tip.global_position - right_pivot.global_position).normalized()
	var pelvis_position := _bone_world(&"pelvis").origin
	var left_side_sign := _pole_side_sign(&"left", left_pivot.global_position, lateral, pelvis_position)
	var right_side_sign := _pole_side_sign(&"right", right_pivot.global_position, lateral, pelvis_position)
	var left_clearance := _minimum_pole_knee_clearance(left_pivot.global_position, left_tip.global_position)
	var right_clearance := _minimum_pole_knee_clearance(right_pivot.global_position, right_tip.global_position)
	var left_body_clearance := _minimum_pole_body_clearance(left_pivot.global_position, left_tip.global_position)
	var right_body_clearance := _minimum_pole_body_clearance(right_pivot.global_position, right_tip.global_position)
	var pole_pole_clearance := _segment_to_segment_distance(
		left_pivot.global_position.lerp(left_tip.global_position, POLE_HAND_EXCLUSION_RATIO), left_tip.global_position,
		right_pivot.global_position.lerp(right_tip.global_position, POLE_HAND_EXCLUSION_RATIO), right_tip.global_position)
	return {
		"left_pole_knee_clearance_m": left_clearance,
		"right_pole_knee_clearance_m": right_clearance,
		"pole_knee_clearance_m": minf(left_clearance, right_clearance),
		"left_pole_body_clearance_m": left_body_clearance,
		"right_pole_body_clearance_m": right_body_clearance,
		"pole_body_clearance_m": minf(left_body_clearance, right_body_clearance),
		"pole_pole_clearance_m": pole_pole_clearance,
		"left_pole_outward_dot": left_direction.dot(lateral) * left_side_sign,
		"right_pole_outward_dot": right_direction.dot(lateral) * right_side_sign,
		"poles_outward": left_direction.dot(lateral) * left_side_sign >= 0.02 and right_direction.dot(lateral) * right_side_sign >= 0.02,
	}

func _pole_basis_for_direction(direction: Vector3, forward: Vector3, lateral: Vector3) -> Basis:
	var safe_direction := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.DOWN
	var y_axis := -safe_direction
	var z_axis := forward.slide(y_axis)
	if z_axis.length_squared() < 0.0001:
		z_axis = lateral.slide(y_axis)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.FORWARD.slide(y_axis)
	z_axis = z_axis.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _minimum_pole_knee_clearance(start: Vector3, end: Vector3) -> float:
	var left_knee := _bone_world(&"left_knee").origin
	var right_knee := _bone_world(&"right_knee").origin
	return minf(_point_to_segment_distance(left_knee, start, end), _point_to_segment_distance(right_knee, start, end))

func _minimum_pole_body_clearance(start: Vector3, end: Vector3) -> float:
	# Ignore the short section captured by the hand; touching the grip is
	# intentional. Everything below it must remain outside the visible body.
	var shaft_start := start.lerp(end, POLE_HAND_EXCLUSION_RATIO)
	var capsules: Array[Dictionary] = [
		{"a": _bone_world(&"pelvis").origin, "b": _bone_world(&"chest").origin, "radius": 0.18},
		{"a": _bone_world(&"chest").origin, "b": _bone_world(&"head").origin, "radius": 0.145},
		{"a": _bone_world(&"left_hip").origin, "b": _bone_world(&"left_knee").origin, "radius": 0.105},
		{"a": _bone_world(&"right_hip").origin, "b": _bone_world(&"right_knee").origin, "radius": 0.105},
		{"a": _bone_world(&"left_knee").origin, "b": _bone_world(&"left_boot").origin, "radius": 0.09},
		{"a": _bone_world(&"right_knee").origin, "b": _bone_world(&"right_boot").origin, "radius": 0.09},
	]
	var minimum := INF
	for capsule: Dictionary in capsules:
		minimum = minf(minimum, _segment_to_segment_distance(shaft_start, end, capsule.a as Vector3, capsule.b as Vector3) - float(capsule.radius))
	return minimum

func _pole_side_sign(side: StringName, pivot: Vector3, lateral: Vector3, pelvis: Vector3 = Vector3.INF) -> float:
	var pelvis_position := _bone_world(&"pelvis").origin if not pelvis.is_finite() else pelvis
	var hand_lateral := (pivot - pelvis_position).dot(lateral)
	# Do not let sub-centimeter IK motion flip the pole's presentation side on
	# consecutive frames while a hand crosses the skier's centerline.
	if absf(hand_lateral) <= 0.025:
		return -1.0 if side == &"left" else 1.0
	return signf(hand_lateral)

func _safest_pole_direction(pivot: Vector3, preferred: Vector3, side_sign: float, down: Vector3, forward: Vector3, lateral: Vector3) -> Vector3:
	var best_direction := preferred.normalized()
	var best_score := -INF
	var lateral_strengths: Array[float] = [0.72, 1.0, 1.35, 1.75, 2.2]
	var downward_strengths: Array[float] = [0.10, 0.25, 0.5, 0.75, 1.0]
	var forward_strengths: Array[float] = [-6.0, -5.0, -4.0, -3.0, -2.0, -1.2, -0.65, -0.30, 0.0, 0.30, 0.65, 1.2, 2.0, 3.0, 4.0, 5.0, 6.0]
	for lateral_strength: float in lateral_strengths:
		for downward_strength: float in downward_strengths:
			for forward_strength: float in forward_strengths:
				var candidate := (lateral * side_sign * lateral_strength + down * downward_strength + forward * forward_strength).normalized()
				var outward_alignment := candidate.dot(lateral) * side_sign
				var downward_alignment := candidate.dot(down)
				if outward_alignment < 0.12 or downward_alignment < 0.12:
					continue
				var candidate_tip := pivot + candidate * POLE_SHAFT_LENGTH
				var body_clearance := _minimum_pole_body_clearance(pivot, candidate_tip)
				var knee_clearance := _minimum_pole_knee_clearance(pivot, candidate_tip)
				# Body clearance dominates. The remaining terms choose a downhill,
				# outward, pose-adjacent result among similarly safe candidates.
				var score := body_clearance * 8.0 + minf(knee_clearance, 0.25) * 0.7 + downward_alignment * 0.08 + outward_alignment * 0.04 + candidate.dot(preferred) * 0.04
				if knee_clearance < MIN_POLE_KNEE_CLEARANCE:
					score -= (MIN_POLE_KNEE_CLEARANCE - knee_clearance) * 12.0
				if body_clearance < MIN_POLE_BODY_CLEARANCE:
					score -= (MIN_POLE_BODY_CLEARANCE - body_clearance) * 24.0
				if score > best_score:
					best_score = score
					best_direction = candidate
	return best_direction

func _segment_to_segment_distance(start_a: Vector3, end_a: Vector3, start_b: Vector3, end_b: Vector3) -> float:
	var direction_a := end_a - start_a
	var direction_b := end_b - start_b
	var offset := start_a - start_b
	var length_a := direction_a.length_squared()
	var length_b := direction_b.length_squared()
	var direction_b_offset := direction_b.dot(offset)
	var parameter_a := 0.0
	var parameter_b := 0.0
	if length_a <= 0.000001 and length_b <= 0.000001:
		return start_a.distance_to(start_b)
	if length_a <= 0.000001:
		parameter_b = clampf(direction_b_offset / length_b, 0.0, 1.0)
	else:
		var direction_a_offset := direction_a.dot(offset)
		if length_b <= 0.000001:
			parameter_a = clampf(-direction_a_offset / length_a, 0.0, 1.0)
		else:
			var directions_dot := direction_a.dot(direction_b)
			var denominator := length_a * length_b - directions_dot * directions_dot
			if not is_zero_approx(denominator):
				parameter_a = clampf((directions_dot * direction_b_offset - direction_a_offset * length_b) / denominator, 0.0, 1.0)
			var projected_b := directions_dot * parameter_a + direction_b_offset
			if projected_b < 0.0:
				parameter_b = 0.0
				parameter_a = clampf(-direction_a_offset / length_a, 0.0, 1.0)
			elif projected_b > length_b:
				parameter_b = 1.0
				parameter_a = clampf((directions_dot - direction_a_offset) / length_a, 0.0, 1.0)
			else:
				parameter_b = projected_b / length_b
	return (start_a + direction_a * parameter_a).distance_to(start_b + direction_b * parameter_b)

func _point_to_segment_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start.lerp(end, t))

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
