extends Node

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SummitEnvironmentBuilderModule := preload("res://world/summit_environment_builder.gd")
const SummitEnvironmentProfileResource := preload("res://world/summit_environment_profile.gd")
const EnvironmentAssetDefinition := preload("res://resources/environment/environment_asset_definition.gd")

var failures: Array[String] = []

@onready var resort: Node3D = $Resort

func _ready() -> void:
	for _frame: int in 120:
		await get_tree().physics_frame
	var profile := resort.get("summit_environment_profile") as SummitEnvironmentProfileResource
	if profile == null or not profile.enabled:
		failures.append("Resort did not expose an enabled summit environment profile")
	else:
		_validate_render_surface(profile)
	_validate_backdrop()
	_validate_decorations()
	if failures.is_empty():
		print("SUMMIT_ENVIRONMENT_PASS: deterministic summit terrain, authored ridge backdrop, decoration LODs, and collision preservation validated")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SUMMIT_ENVIRONMENT_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_render_surface(profile: SummitEnvironmentProfileResource) -> void:
	var visual_nodes := get_tree().get_nodes_in_group("environment_summit_visual")
	if visual_nodes.size() != 1:
		failures.append("Summit render layer count was %d instead of one" % visual_nodes.size())
		return
	var visual := visual_nodes[0] as MeshInstance3D
	if visual == null or visual.mesh == null or not visual.mesh is ArrayMesh:
		failures.append("Summit render layer did not produce an ArrayMesh")
		return
	if visual.find_children("*", "CollisionShape3D", true, false).size() > 0:
		failures.append("Summit render layer introduced a second collision surface")
	var arrays := visual.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		failures.append("Summit render layer surface arrays were empty")
		return
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var upward_normal_count := 0
	for probe_normal: Vector3 in normals:
		if probe_normal.dot(ParkLayout.snow_normal()) >= 0.85:
			upward_normal_count += 1
	if vertices.size() < 100 or normals.size() != vertices.size():
		failures.append("Summit heightfield vertex/normal coverage was incomplete")
	for vertex: Vector3 in vertices:
		if not vertex.is_finite():
			failures.append("Summit heightfield emitted a non-finite vertex")
			break
	for normal: Vector3 in normals:
		if not normal.is_finite():
			failures.append("Summit heightfield emitted a non-finite normal")
			break
	if upward_normal_count < int(float(normals.size()) * 0.4):
		failures.append("Summit heightfield did not provide enough upward-facing surface normals")
	for x: float in [-20.0, 0.0, 20.0]:
		for z: float in [96.0, 110.0, 128.0]:
			var expected := ParkLayout.snow_at(x, z).y + profile.surface_offset_m
			var actual := SummitEnvironmentBuilderModule.sample_height(x, z, profile)
			if absf(actual - expected) > 0.002:
				failures.append("Playable summit sample (%.1f, %.1f) drifted %.4f m from the collision slope" % [x, z, actual - expected])
	var center_height := SummitEnvironmentBuilderModule.sample_height(0.0, 110.0, profile)
	var shoulder_height := SummitEnvironmentBuilderModule.sample_height(30.0, 110.0, profile)
	if shoulder_height - center_height < 0.15:
		failures.append("Summit shoulder relief did not separate from the playable corridor")
	var main_face := resort.get_node_or_null("MainSnowFace") as StaticBody3D
	var collision_candidates := main_face.find_children("*", "CollisionShape3D", true, false) if main_face != null else []
	var collision_shape := collision_candidates[0] as CollisionShape3D if not collision_candidates.is_empty() else null
	var box_shape := collision_shape.shape as BoxShape3D if collision_shape != null else null
	if box_shape == null or box_shape.size.distance_to(Vector3(ParkLayout.FACE_WIDTH, ParkLayout.FACE_THICKNESS, ParkLayout.FACE_SLOPE_LENGTH)) > 0.001:
		failures.append("MainSnowFace collision extents changed while adding the summit render layer")

func _validate_backdrop() -> void:
	var ridges := resort.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool:
		var node_name := str(node.name)
		return node_name.begins_with("HazePeak") or node_name.begins_with("FarPeak") or node_name in ["WestShoulder", "EastShoulder"]
	)
	if ridges.size() < 10:
		failures.append("Authored summit backdrop produced only %d ridge roots" % ridges.size())
	for ridge_node: Node in ridges:
		for mesh_node: Node in ridge_node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null or not mesh_instance.mesh is ArrayMesh:
				failures.append("Backdrop ridge %s did not produce an ArrayMesh" % ridge_node.name)
			if mesh_instance != null and mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				failures.append("Backdrop ridge %s casts a gameplay-irrelevant shadow" % ridge_node.name)

func _validate_decorations() -> void:
	for asset_id: String in ["snow_boulder", "lift_line"]:
		var instances := resort.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return str(node.get_meta("asset_id", "")) == asset_id)
		if instances.is_empty():
			failures.append("Summit decoration %s was not instantiated" % asset_id)
			continue
		for instance_node: Node in instances:
			var instance := instance_node as Node3D
			if instance == null:
				continue
			if str(instance.get_meta("asset_source", "")) != "production_scene":
				failures.append("Summit decoration %s bypassed the production catalog" % asset_id)
			if str(instance.get_meta("asset_class", "")) != "DECORATION":
				failures.append("Summit decoration %s did not use DECORATION semantics" % asset_id)
			if not instance.find_children("*", "CollisionShape3D", true, false).is_empty():
				failures.append("Summit decoration %s introduced gameplay collision" % asset_id)
