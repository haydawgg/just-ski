class_name ParkCourseBuilder
extends RefCounted

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const EnvironmentAssetDefinition := preload("res://resources/environment/environment_asset_definition.gd")
const EnvironmentAssetCatalog := preload("res://resources/environment/environment_asset_catalog.gd")

static func build(parent: Node3D, profile: ParkCourseProfile, physics_profile: SkiPhysicsProfile, asset_catalog: EnvironmentAssetCatalog = null) -> Dictionary:
	var built: Dictionary = {}
	if profile == null:
		push_warning("ParkCourseBuilder received no course profile")
		return built
	if physics_profile == null:
		push_warning("ParkCourseBuilder received no ski physics profile")
		return built
	var readability := profile.feature_readability()
	for spec: Dictionary in profile.feature_specs():
		var feature := _build_production_feature(parent, spec, physics_profile, readability, asset_catalog)
		if feature == null and asset_catalog != null and asset_catalog.should_use_production_scenes():
			# Production mode is intentionally strict: never hide a missing authored
			# asset behind a primitive that has different scale or collision.
			push_error("ENVIRONMENT_ASSET_FAIL: required production asset '%s' is unavailable for %s" % [str(spec.get("asset_id", spec.get("kind", "feature"))), str(spec.get("name", "ParkFeature"))])
			continue
		if feature == null:
			feature = _build_feature(parent, spec, physics_profile, readability)
		if feature == null:
			push_warning("Unsupported park feature: %s" % spec.get("kind", "<missing>"))
			continue
		var feature_name := str(spec.get("name", "ParkFeature"))
		feature.name = feature_name
		_apply_asset_contract(feature, spec)
		_apply_content_metadata(feature, spec)
		feature.set_meta("difficulty", str(spec.get("difficulty", "intermediate")))
		built[feature_name] = feature
	return built

static func _apply_content_metadata(feature: Node3D, spec: Dictionary) -> void:
	var defaults := {
		"feature_id": StringName(str(spec.get("name", "park_feature")).to_snake_case()),
		"feature_kind": StringName(spec.get("kind", "feature")),
		"spot_id": &"unassigned",
		"route": &"intermediate",
		"discipline": StringName(spec.get("kind", "feature")),
		"skill_floor": 0,
		"skill_ceiling": 5,
		"intent_tags": [&"legacy"],
		"risk_level": 1,
		"hero_feature": false,
		"optional": false,
	}
	for key: String in defaults:
		feature.set_meta(key, spec.get(key, defaults[key]))

static func _build_production_feature(parent: Node3D, spec: Dictionary, physics_profile: SkiPhysicsProfile, readability: Dictionary, asset_catalog: EnvironmentAssetCatalog) -> Node3D:
	if asset_catalog == null:
		return null
	var defaults := _asset_defaults(str(spec.get("kind", "feature")))
	var asset_id := str(spec.get("asset_id", defaults.asset_id))
	if not asset_catalog.should_use_scene(asset_id):
		return null
	var scene := asset_catalog.scene_for(asset_id)
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		push_error("ENVIRONMENT_ASSET_FAIL: %s scene did not instantiate as Node3D" % asset_id)
		return null
	var definition := asset_catalog.definition_for(asset_id)
	if definition != null and definition.parametric_feature:
		# Rails and sculpted snow forms are authored templates because their
		# dimensions and paths live in the course specification. The existing
		# parametric builders generate render and collision from that same data,
		# preserving exact gameplay geometry while still requiring a cataloged
		# production template.
		var template_kind := str(instance.get_meta("parametric_kind", ""))
		var expected_kind := "grind_rail" if str(spec.get("kind", "")) == "rail" else "snow_feature"
		instance.free()
		if template_kind != expected_kind:
			push_error("ENVIRONMENT_ASSET_FAIL: %s template kind '%s' does not match %s" % [asset_id, template_kind, expected_kind])
			return null
		var parametric_feature := _build_feature(parent, spec, physics_profile, readability)
		if parametric_feature != null:
			parametric_feature.set_meta("asset_source", "project_authored_parametric_scene")
			_tag_parametric_feature(parametric_feature, definition)
		return parametric_feature
	var x := float(spec.get("x", 0.0))
	var z := float(spec.get("z", 0.0))
	var yaw := float(spec.get("yaw", 0.0))
	instance.position = ParkLayout.snow_at(x, z)
	instance.basis = ParkLayout.downhill_basis(yaw)
	var scale_override := maxf(float(spec.get("scale_override", 1.0)), 0.001)
	# Gate width is authored in the X axis. Do not uniformly scale the post
	# height when a wider finish gate is requested.
	instance.scale = Vector3(scale_override, 1.0, 1.0) if str(spec.get("kind", "")) == "gate" else Vector3.ONE * scale_override
	instance.set_meta("asset_id", asset_id)
	instance.set_meta("asset_source", "production_scene")
	instance.set_meta("accent_color", spec.get("color", readability.get("guide_color", Color("#55d6be"))))
	if definition != null:
		instance.set_meta("lod_distances_m", definition.lod_distances_m)
	var collision_root: Node
	if definition != null and definition.collision_scene != null:
		collision_root = definition.collision_scene.instantiate()
		if collision_root != null:
			collision_root.name = "%s_Collision" % asset_id
			instance.add_child(collision_root)
	parent.add_child(instance)
	if instance.has_method("build_now"):
		instance.call("build_now")
	if collision_root != null:
		_configure_production_collision(collision_root, definition.asset_class, asset_id)
	if definition != null:
		var dimension_failures := definition.validate_instance(instance)
		for reason: String in dimension_failures:
			if asset_catalog.should_use_production_scenes():
				push_error("ENVIRONMENT_ASSET_FAIL: %s: %s" % [asset_id, reason])
			else:
				push_warning("ENVIRONMENT_ASSET_WARNING: %s: %s" % [asset_id, reason])
		if asset_catalog.should_use_production_scenes() and not dimension_failures.is_empty():
			parent.remove_child(instance)
			instance.free()
			return null
	return instance

static func _tag_parametric_feature(feature: Node3D, definition: EnvironmentAssetDefinition) -> void:
	var lod_contract := Node3D.new()
	lod_contract.name = "LODContract"
	lod_contract.set_meta("lod_distances_m", definition.lod_distances_m)
	feature.add_child(lod_contract)
	var lod_start := maxf(definition.lod_distances_m.x, 1.0)
	var lod_end := maxf(definition.lod_distances_m.z, lod_start + 1.0)
	for node: Node in feature.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			# Parametric snow features do not have authored replacement meshes yet,
			# but they still need a finite visibility budget. Without this cull the
			# full-resolution profile remains in the frame far past the catalog's
			# intended horizon and defeats the production asset contract.
			mesh_instance.visibility_range_begin = 0.0
			mesh_instance.visibility_range_begin_margin = 0.0
			mesh_instance.visibility_range_end = lod_end
			mesh_instance.visibility_range_end_margin = maxf(lod_start * 0.2, 8.0)
			mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mesh_instance.set_meta("lod_cull_start_m", lod_start)
			mesh_instance.set_meta("lod_cull_end_m", lod_end)
		mesh_instance.add_to_group("production_asset_render")
	for node: Node in feature.find_children("*", "CollisionShape3D", true, false):
		node.add_to_group("production_asset_collision")

static func _configure_production_collision(root: Node, asset_class: EnvironmentAssetDefinition.AssetClass, asset_id: String = "") -> void:
	var collision_layer := 1
	if asset_class == EnvironmentAssetDefinition.AssetClass.GRIND_ONLY:
		collision_layer = 8
	elif asset_class == EnvironmentAssetDefinition.AssetClass.BOUNDARY:
		collision_layer = 4
	var collision_nodes: Array[Node] = []
	if root is CollisionObject3D:
		collision_nodes.append(root)
	collision_nodes.append_array(root.find_children("*", "CollisionObject3D", true, false))
	for node: Node in collision_nodes:
		var collision_object := node as CollisionObject3D
		if collision_object == null:
			continue
		collision_object.collision_layer = collision_layer
		collision_object.collision_mask = 2
		if not asset_id.is_empty():
			collision_object.set_meta("asset_id", asset_id)
		collision_object.set_meta("asset_class", EnvironmentAssetDefinition.AssetClass.keys()[asset_class])
		collision_object.set_meta("collision_policy", EnvironmentAssetDefinition.AssetClass.keys()[asset_class])

static func _build_feature(parent: Node3D, spec: Dictionary, physics_profile: SkiPhysicsProfile, readability: Dictionary) -> Node3D:
	var kind := str(spec.get("kind", ""))
	var label := str(spec.get("name", "ParkFeature"))
	match kind:
		"tabletop":
			return ParkLayout.add_tabletop(
				parent, label, physics_profile, float(spec.x), float(spec.z), float(spec.speed), float(spec.lip),
				float(spec.get("width", 8.5)), float(spec.get("drop", 0.0)), float(spec.get("yaw", 0.0)),
				float(spec.get("pop", physics_profile.minimum_pop_strength)), readability
			)
		"hip":
			return ParkLayout.add_hip(
				parent, label, physics_profile, float(spec.x), float(spec.z), float(spec.speed), float(spec.lip),
				float(spec.yaw), float(spec.get("pop", physics_profile.minimum_pop_strength)), readability
			)
		"roller":
			return ParkLayout.add_roller(
				parent, label, float(spec.x), float(spec.z), float(spec.get("length", 8.0)),
				float(spec.get("height", 0.8)), float(spec.get("width", 9.0))
			)
		"rail":
			var rail_points: Array[Vector3] = []
			for encoded: Vector3 in spec.get("points", []):
				rail_points.append(ParkLayout.rail_point(encoded.x, encoded.y, encoded.z))
			var rail := ParkLayout.add_rail(
				parent, label, rail_points, int(spec.get("rail_type", GrindRail3D.RailType.RAIL)),
				float(spec.get("radius", 0.9)), float(spec.get("friction", 0.7))
			)
			rail.approach_angle_degrees = float(spec.get("approach", 44.0))
			rail.drift_bias = float(spec.get("drift_bias", 0.0))
			ParkLayout.add_rail_contours(parent, label, rail_points)
			return rail
		"berm":
			return ParkLayout.add_berm(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width),
				float(spec.bank), float(spec.get("yaw", 0.0))
			)
		"moguls":
			return ParkLayout.add_mogul_field(
				parent, label, float(spec.x), float(spec.z), int(spec.rows), float(spec.spacing),
				float(spec.height), float(spec.width)
			)
		"butter":
			return ParkLayout.add_butter_pad(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width), float(spec.height)
			)
		"side_hit":
			return ParkLayout.add_side_hit(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.height),
				float(spec.width), float(spec.get("yaw", 0.0))
			)
		"wallride":
			var wall_color: Color = spec.get("color", readability.get("solid_feature_color", Color("#ef8354")))
			return ParkLayout.add_wallride(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.height),
				float(spec.get("yaw", 0.0)), wall_color
			)
		"bonk":
			var bonk_color: Color = spec.get("color", readability.get("boundary_color", Color("#ffc857")))
			return ParkLayout.add_bonk(
				parent, label, float(spec.x), float(spec.z), float(spec.height), float(spec.radius),
				bonk_color
			)
		"cannon":
			return ParkLayout.add_cannon(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width), float(spec.height)
			)
		"gate":
			var gate_color: Color = spec.get("color", readability.get("guide_color", Color("#55d6be")))
			return ParkLayout.add_gate(
				parent, label, float(spec.x), float(spec.z), float(spec.width),
				gate_color, readability
			)
	return null

static func _apply_asset_contract(feature: Node3D, spec: Dictionary) -> void:
	var kind := str(spec.get("kind", "feature"))
	var defaults := _asset_defaults(kind)
	var asset_id := str(spec.get("asset_id", defaults.asset_id))
	var asset_class := int(spec.get("asset_class", defaults.asset_class))
	feature.set_meta("asset_id", asset_id)
	var class_names := ["SOLID", "GRIND_ONLY", "GUIDE", "BOUNDARY"]
	feature.set_meta("asset_class", class_names[clampi(asset_class, 0, class_names.size() - 1)])
	var collision_policy := str(spec.get("collision_policy", ""))
	if collision_policy.is_empty():
		collision_policy = "SOLID"
		match asset_class:
			EnvironmentAssetDefinition.AssetClass.GRIND_ONLY:
				collision_policy = "GRIND_ONLY"
			EnvironmentAssetDefinition.AssetClass.GUIDE:
				collision_policy = "GUIDE"
			EnvironmentAssetDefinition.AssetClass.BOUNDARY:
				collision_policy = "BOUNDARY"
	feature.set_meta("collision_policy", collision_policy)
	feature.set_meta("readability_category", str(spec.get("readability_category", defaults.readability_category)))
	feature.set_meta("scale_override", float(spec.get("scale_override", 1.0)))
	# Parametric features own their collision bodies, so propagate the same
	# catalog identity to each collider used by post-motion crash telemetry.
	# Preserve the feature's authored layer (snow bodies remain terrain layer 1;
	# bonks and other obstacle bodies can remain on layer 4).
	var collision_objects: Array[Node] = []
	if feature is CollisionObject3D:
		collision_objects.append(feature)
	collision_objects.append_array(feature.find_children("*", "CollisionObject3D", true, false))
	for node: Node in collision_objects:
		var collider := node as CollisionObject3D
		if collider == null:
			continue
		collider.set_meta("asset_id", asset_id)
		collider.set_meta("asset_class", class_names[clampi(asset_class, 0, class_names.size() - 1)])
		collider.set_meta("collision_policy", collision_policy)

static func _asset_defaults(kind: String) -> Dictionary:
	match kind:
		"gate":
			return {"asset_id": "route_gate", "asset_class": EnvironmentAssetDefinition.AssetClass.GUIDE, "readability_category": "guide"}
		"rail":
			return {"asset_id": "grind_rail", "asset_class": EnvironmentAssetDefinition.AssetClass.GRIND_ONLY, "readability_category": "jib"}
		"roller", "tabletop", "hip", "berm", "moguls", "butter", "side_hit", "wallride", "bonk", "cannon":
			return {"asset_id": "snow_feature", "asset_class": EnvironmentAssetDefinition.AssetClass.SOLID, "readability_category": "terrain_feature"}
		_:
			return {"asset_id": "course_landmark", "asset_class": EnvironmentAssetDefinition.AssetClass.GUIDE, "readability_category": "landmark"}
