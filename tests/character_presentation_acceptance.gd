extends Node

const SKIER_VISUAL_SCENE := preload("res://player/animation/skier_visual.tscn")
const REQUIRED_BODY_REGIONS := ["Outfit_Jacket", "Outfit_Pants", "Outfit_Skin", "Outfit_Gloves", "Outfit_BootUnderlay"]
const REQUIRED_CLOTHING_SHELLS := ["Outfit_Jacket", "Outfit_Pants", "Outfit_Gloves"]
const REQUIRED_RIGID_PARTS := [
	"HelmetShell", "HelmetBrim", "GoggleFrame", "GoggleLens",
	"LeftBootCuff", "RightBootCuff", "LeftSkiAccent", "RightSkiAccent",
	"LeftPoleGrip", "RightPoleGrip", "LeftPolePoint", "RightPolePoint",
]

var failures: Array[String] = []

func _ready() -> void:
	var controller := SKIER_VISUAL_SCENE.instantiate() as SkierAnimationController
	add_child(controller)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GROUND
	frame.grounded = true
	controller.apply_frame(frame, 1.0 / 60.0)
	await get_tree().process_frame
	var adapter := controller.rig_adapter as SkeletonSkierRig
	_check(adapter != null, "Production visual did not select SkeletonSkierRig")
	if adapter != null:
		_check(adapter.outfit_profile != null, "Production rig has no data-driven outfit profile")
		_check_body_regions(adapter)
		_check_rigid_parts(adapter)
		_print_inventory(adapter)
	if failures.is_empty():
		print("CHARACTER_PRESENTATION_PASS: explicit body regions, shared palette, headwear, and detailed equipment passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("CHARACTER_PRESENTATION_FAIL: " + failure)
		get_tree().quit(1)

func _check_body_regions(adapter: SkeletonSkierRig) -> void:
	var found: Dictionary = {}
	var region_counts: Dictionary = {}
	var body_surfaces := 0
	for node: Node in adapter.body_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.skin == null and instance.skeleton.is_empty():
			continue
		for surface_index: int in instance.mesh.get_surface_count():
			body_surfaces += 1
			var surface := instance.get_surface_override_material(surface_index) as StandardMaterial3D
			_check(surface != null, "Skinned body surface %d has no explicit override material" % surface_index)
			if surface != null:
				found[surface.resource_name] = surface
				region_counts[surface.resource_name] = int(region_counts.get(surface.resource_name, 0)) + 1
	_check(body_surfaces >= REQUIRED_BODY_REGIONS.size() + REQUIRED_CLOTHING_SHELLS.size(), "Expected at least %d skinned body surfaces (regions plus shells), found %d" % [REQUIRED_BODY_REGIONS.size() + REQUIRED_CLOTHING_SHELLS.size(), body_surfaces])
	for region: String in REQUIRED_BODY_REGIONS:
		_check(found.has(region), "Missing explicit skinned region " + region)
	for shell_region: String in REQUIRED_CLOTHING_SHELLS:
		_check(int(region_counts.get(shell_region, 0)) >= 2, "Clothing shell surface missing over " + shell_region)
	if found.has("Outfit_Jacket") and found.has("Outfit_Pants"):
		var jacket := (found["Outfit_Jacket"] as StandardMaterial3D).albedo_color
		var pants := (found["Outfit_Pants"] as StandardMaterial3D).albedo_color
		var color_distance := Vector3(jacket.r, jacket.g, jacket.b).distance_to(Vector3(pants.r, pants.g, pants.b))
		_check(color_distance >= 0.18, "Jacket and pants do not provide readable color blocking")
		_check(maxf(jacket.r, maxf(jacket.g, jacket.b)) < 0.9, "Jacket is still near-white")
		_check(maxf(pants.r, maxf(pants.g, pants.b)) < 0.9, "Pants are still near-white")

func _check_rigid_parts(adapter: SkeletonSkierRig) -> void:
	for part_name: String in REQUIRED_RIGID_PARTS:
		_check(adapter.find_child(part_name, true, false) is MeshInstance3D, "Missing rigid visual part " + part_name)
	var head_attachment := adapter.find_child("HeadAttachment", true, false) as BoneAttachment3D
	_check(head_attachment != null, "Helmet and goggles are not mounted through a head BoneAttachment3D")
	if head_attachment != null:
		_check(head_attachment.bone_name == adapter.skeleton.get_bone_name(int(adapter.bone_indices[&"head"])), "Headwear attachment targets the wrong bone")

func _print_inventory(adapter: SkeletonSkierRig) -> void:
	var mesh_instances := adapter.find_children("*", "MeshInstance3D", true, false)
	var surface_count := 0
	var material_ids: Dictionary = {}
	for node: Node in mesh_instances:
		var instance := node as MeshInstance3D
		surface_count += instance.mesh.get_surface_count()
		if instance.material_override != null:
			material_ids[instance.material_override.get_instance_id()] = true
		for surface_index: int in instance.mesh.get_surface_count():
			var override := instance.get_surface_override_material(surface_index)
			if override != null:
				material_ids[override.get_instance_id()] = true
	print("CHARACTER_PRESENTATION_INVENTORY meshes=%d surfaces=%d unique_runtime_materials=%d body_regions=%d rigid_parts=%d" % [mesh_instances.size(), surface_count, material_ids.size(), REQUIRED_BODY_REGIONS.size(), REQUIRED_RIGID_PARTS.size()])

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
