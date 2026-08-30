class_name SkeletonSkierRig
extends SkierRigAdapter

const TRANSLATED_JOINTS := [&"pelvis", &"chest", &"left_shoulder", &"right_shoulder"]
const DEFAULT_BODY_PATH := "res://assets/characters/skier/skier_body.glb"
const DEFAULT_OUTFIT := preload("res://resources/character/default_skier_outfit_profile.tres")

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
	sync_pose(0.0)
	return true

func sync_pose(_delta: float) -> void:
	if skeleton == null or driver == null:
		return
	transform = driver.joint(&"balance_root").transform
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
		"left_pole_tip": (equipment_tips[&"left"] as Node3D).global_position,
		"right_pole_tip": (equipment_tips[&"right"] as Node3D).global_position,
	}

func grab_target(side: StringName, target: StringName) -> Node3D:
	# The controller solves its existing reach in canonical pose space. Equipment
	# markers remain visual-only children of BoneAttachment3D; returning the
	# canonical marker here keeps gameplay pose math independent of model scale.
	return super.grab_target(side, target)

func arm_lengths(side: StringName) -> Vector2:
	# The procedural solver owns canonical hand contact and must retain the
	# calibrated canonical limb lengths. This supplied model has different limb
	# proportions; its visual bones consume the resulting canonical rotations.
	return super.arm_lengths(side)

func _cache_and_validate_bones() -> bool:
	var used: Dictionary = {}
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
	return true

func _compute_retarget_calibration() -> void:
	_neutral_world.clear()
	_static_position_offsets.clear()
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
