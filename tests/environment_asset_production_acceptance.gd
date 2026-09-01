extends Node

var failures: Array[String] = []

@onready var resort: Node3D = $Resort

func _ready() -> void:
	for _frame: int in 120:
		await get_tree().physics_frame
	var catalog := resort.get("environment_asset_catalog") as EnvironmentAssetCatalog
	if catalog == null or catalog.mode != EnvironmentAssetCatalog.AssetMode.PRODUCTION:
		failures.append("Resort did not enter strict production asset mode")
	else:
		for reason: String in catalog.validate(true):
			failures.append("Strict catalog validation failed: %s" % reason)
		_validate_source_scenes(catalog)
	var features: Dictionary = resort.get("course_features") as Dictionary
	var profile := resort.get("course_profile") as ParkCourseProfile
	if profile == null or features.size() != profile.feature_specs().size():
		failures.append("Strict production mode did not build every authored course feature")
	for feature_name: String in features:
		var feature := features[feature_name] as Node3D
		var source := str(feature.get_meta("asset_source", "")) if feature != null else ""
		if source not in ["production_scene", "project_authored_parametric_scene"]:
			failures.append("%s bypassed the production asset catalog" % feature_name)
		else:
			_validate_runtime_collision_contract(feature_name, feature)
			_validate_runtime_lod_contract(feature_name, feature, catalog)
	_validate_finish_gate_scale(features, profile)
	if catalog != null:
		_validate_catalog_colliders(catalog)
	for asset_id: String in ["park_tree", "route_gate", "grind_rail", "snow_feature", "course_boundary", "lift_tower", "snowmaker", "trail_board", "snow_boulder", "lift_line"]:
		var instances := _instances_for_asset(asset_id)
		if instances.is_empty():
			failures.append("Strict production resort did not instantiate %s" % asset_id)
	if failures.is_empty():
		print("ENVIRONMENT_PRODUCTION_PASS: strict catalog scenes, parametric features, LODs, and collision companions instantiated")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ENVIRONMENT_PRODUCTION_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_runtime_collision_contract(feature_name: String, feature: Node3D) -> void:
	if feature == null:
		return
	var asset_id := str(feature.get_meta("asset_id", ""))
	var asset_class := str(feature.get_meta("asset_class", ""))
	if asset_class == "GUIDE":
		return
	var expected_layer := 8 if asset_class == "GRIND_ONLY" else (4 if asset_class == "BOUNDARY" or feature_name.contains("Bonk") else 1 if asset_id == "snow_feature" else 4)
	var collision_objects: Array[Node] = []
	if feature is CollisionObject3D:
		collision_objects.append(feature)
	collision_objects.append_array(feature.find_children("*", "CollisionObject3D", true, false))
	if collision_objects.is_empty():
		failures.append("%s has no runtime collision object for %s" % [feature_name, asset_id])
		return
	for node: Node in collision_objects:
		var collider := node as CollisionObject3D
		if collider == null:
			continue
		if collider.collision_layer != expected_layer:
			failures.append("%s collider %s used layer %d; expected %d for %s" % [feature_name, collider.name, collider.collision_layer, expected_layer, asset_class])
		if str(collider.get_meta("asset_id", "")) != asset_id:
			failures.append("%s collider %s lost asset id %s" % [feature_name, collider.name, asset_id])

func _validate_runtime_lod_contract(feature_name: String, feature: Node3D, catalog: EnvironmentAssetCatalog) -> void:
	if feature == null or catalog == null:
		return
	var definition := catalog.definition_for(str(feature.get_meta("asset_id", "")))
	if definition == null or not definition.parametric_feature:
		return
	var render_meshes := feature.find_children("*", "MeshInstance3D", true, false)
	if render_meshes.is_empty():
		failures.append("%s parametric feature has no render mesh for LOD validation" % feature_name)
		return
	var expected_end := maxf(definition.lod_distances_m.z, definition.lod_distances_m.x + 1.0)
	var found_culled_mesh := false
	for node: Node in render_meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		if mesh_instance.visibility_range_end > definition.lod_distances_m.y and mesh_instance.visibility_range_end <= expected_end + 0.01:
			found_culled_mesh = true
			break
	if not found_culled_mesh:
		failures.append("%s parametric render mesh does not honor its finite LOD cull range" % feature_name)

func _validate_finish_gate_scale(features: Dictionary, profile: ParkCourseProfile) -> void:
	var gate := features.get("FinishGate") as Node3D
	if gate == null or profile == null:
		failures.append("FinishGate was not built for runtime scale validation")
		return
	var expected_width := 50.0
	for spec: Dictionary in profile.feature_specs():
		if str(spec.get("name", "")) == "FinishGate":
			expected_width = float(spec.get("width", expected_width))
			break
	var expected_scale := expected_width / 13.0
	if absf(gate.scale.x - expected_scale) > 0.01 or absf(gate.scale.y - 1.0) > 0.01 or absf(gate.scale.z - 1.0) > 0.01:
		failures.append("FinishGate scale %s did not preserve authored %.1f m width without vertical distortion" % [gate.scale, expected_width])

func _validate_catalog_colliders(catalog: EnvironmentAssetCatalog) -> void:
	var seen_assets: Dictionary = {}
	for node: Node in resort.find_children("*", "CollisionObject3D", true, false):
		var collider := node as CollisionObject3D
		if collider == null:
			continue
		var asset_id := str(collider.get_meta("asset_id", ""))
		if asset_id.is_empty():
			continue
		seen_assets[asset_id] = true
		var definition := catalog.definition_for(asset_id)
		if definition == null:
			failures.append("Runtime collider %s referenced unknown asset %s" % [collider.name, asset_id])
			continue
		var is_snow_feature_bonk := asset_id == "snow_feature" and collider.name == "BonkBody"
		var expected_layer := 8 if definition.asset_class == EnvironmentAssetDefinition.AssetClass.GRIND_ONLY else (4 if definition.asset_class == EnvironmentAssetDefinition.AssetClass.BOUNDARY or asset_id != "snow_feature" or is_snow_feature_bonk else 1)
		if definition.asset_class == EnvironmentAssetDefinition.AssetClass.GUIDE:
			failures.append("GUIDE asset %s created runtime collider %s" % [asset_id, collider.name])
		elif collider.collision_layer != expected_layer:
			failures.append("Runtime asset %s collider %s used layer %d; expected %d" % [asset_id, collider.name, collider.collision_layer, expected_layer])
		if str(collider.get_meta("asset_class", "")) != EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class]:
			failures.append("Runtime collider %s lost class metadata for %s" % [collider.name, asset_id])
	for definition: EnvironmentAssetDefinition in catalog.definitions:
		if definition == null or definition.asset_class in [EnvironmentAssetDefinition.AssetClass.GUIDE, EnvironmentAssetDefinition.AssetClass.DECORATION]:
			continue
		if not seen_assets.has(definition.asset_id):
			failures.append("No runtime collider carried production asset id %s" % definition.asset_id)

func _instances_for_asset(asset_id: String) -> Array[Node]:
	var matches: Array[Node] = []
	for node: Node in resort.find_children("*", "Node3D", true, false):
		if str(node.get_meta("asset_id", "")) == asset_id:
			matches.append(node)
	return matches

func _validate_source_scenes(catalog: EnvironmentAssetCatalog) -> void:
	for definition: EnvironmentAssetDefinition in catalog.definitions:
		if definition == null or definition.visual_scene == null:
			continue
		var visual := definition.visual_scene.instantiate() as Node3D
		if visual == null:
			failures.append("%s visual scene is not a Node3D" % definition.asset_id)
			continue
		if definition.parametric_feature:
			if not bool(visual.get_meta("parametric_course_template", false)):
				failures.append("%s is marked parametric but lacks its template contract" % definition.asset_id)
			visual.free()
			continue
		var audit_root := Node3D.new()
		audit_root.name = "%sAudit" % definition.asset_id
		add_child(audit_root)
		audit_root.add_child(visual)
		for reason: String in definition.validate_instance(visual):
			failures.append("%s source scale/grounding failed: %s" % [definition.asset_id, reason])
		if visual.get_node_or_null("Render/LOD0") == null or visual.get_node_or_null("Render/LOD1") == null:
			failures.append("%s does not separate Render/LOD0 and Render/LOD1 nodes" % definition.asset_id)
		if definition.asset_class in [EnvironmentAssetDefinition.AssetClass.GUIDE, EnvironmentAssetDefinition.AssetClass.DECORATION]:
			if definition.collision_scene != null or not visual.find_children("*", "CollisionShape3D", true, false).is_empty():
				failures.append("Non-colliding asset %s authored collision" % definition.asset_id)
		else:
			if definition.collision_scene == null:
				failures.append("Physical asset %s has no collision companion" % definition.asset_id)
			else:
				var collision := definition.collision_scene.instantiate() as Node3D
				if collision == null:
					failures.append("%s collision scene is not a Node3D" % definition.asset_id)
				else:
					audit_root.add_child(collision)
					var visual_bounds := _mesh_bounds(visual, audit_root)
					var collision_bounds := _collision_bounds(collision, audit_root)
					if visual_bounds.size == Vector3.ZERO or collision_bounds.size == Vector3.ZERO:
						failures.append("%s could not produce render/collision bounds" % definition.asset_id)
					else:
						for axis: int in 3:
							var visible_size := maxf(visual_bounds.size[axis], 0.001)
							if absf(collision_bounds.size[axis] - visible_size) / visible_size > definition.scale_tolerance + 0.001:
								failures.append("%s collision extent %.3f m differs from visible extent %.3f m" % [definition.asset_id, collision_bounds.size[axis], visible_size])
							var position_tolerance := maxf(visible_size * definition.scale_tolerance, 0.05)
							if absf(collision_bounds.position[axis] - visual_bounds.position[axis]) > position_tolerance:
								failures.append("%s collision origin %.3f m differs from visible origin %.3f m" % [definition.asset_id, collision_bounds.position[axis], visual_bounds.position[axis]])
		audit_root.queue_free()

func _mesh_bounds(root: Node3D, space: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var nodes: Array[Node] = []
	if root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for corner: Vector3 in _aabb_corners(mesh_instance.mesh.get_aabb()):
			var point := space.to_local(mesh_instance.to_global(corner))
			if not has_bounds:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds

func _collision_bounds(root: Node3D, space: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape_bounds := _shape_aabb(shape_node.shape)
		for corner: Vector3 in _aabb_corners(shape_bounds):
			var point := space.to_local(shape_node.to_global(corner))
			if not has_bounds:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds

func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		return AABB(-size * 0.5, size)
	return AABB()

func _aabb_corners(value: AABB) -> Array[Vector3]:
	var p := value.position
	var s := value.size
	return [
		p, p + Vector3(s.x, 0.0, 0.0), p + Vector3(0.0, s.y, 0.0), p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0), p + Vector3(s.x, 0.0, s.z), p + Vector3(0.0, s.y, s.z), p + s,
	]
