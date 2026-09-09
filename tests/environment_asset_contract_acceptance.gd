extends Node

const DEFAULT_CATALOG := preload("res://resources/environment/default_environment_asset_catalog.tres")
const ParkLayout := preload("res://world/park_features/park_layout.gd")
var failures: Array[String] = []

@onready var resort: Node3D = $Resort

func _ready() -> void:
	for _frame: int in 120:
		await get_tree().physics_frame
	_validate_catalog()
	_validate_feature_specs()
	_validate_built_contracts()
	_validate_bonk_assembly()
	if failures.is_empty():
		print("ENVIRONMENT_ASSET_PASS: production catalog metadata, scene selection, feature contracts, and collision affordances validated")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ENVIRONMENT_ASSET_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_catalog() -> void:
	var catalog := resort.get("environment_asset_catalog") as EnvironmentAssetCatalog
	if catalog == null:
		failures.append("Resort did not expose an environment asset catalog")
		return
	if catalog == DEFAULT_CATALOG:
		failures.append("Resort mutated the shared environment catalog resource")
	if DEFAULT_CATALOG.mode != EnvironmentAssetCatalog.AssetMode.AUTO:
		failures.append("Shared environment catalog mode was changed by a resort instance")
	for reason: String in catalog.validate(false):
		failures.append("Catalog validation failed: %s" % reason)
	if catalog.mode != EnvironmentAssetCatalog.AssetMode.AUTO:
		failures.append("Normal runtime must select authored scenes through AUTO mode")
	for reason: String in catalog.validate(true):
		failures.append("Strict production catalog validation failed: %s" % reason)
	for required_asset_id: String in ["park_tree", "route_gate", "grind_rail", "snow_feature", "course_boundary", "lift_tower", "snowmaker", "trail_board", "snow_boulder", "lift_line"]:
		var definition := catalog.definition_for(required_asset_id)
		if definition == null:
			failures.append("Catalog is missing production asset %s" % required_asset_id)
			continue
		if not catalog.should_use_scene(required_asset_id):
			failures.append("AUTO mode did not select production scene %s" % required_asset_id)
		if definition.source_license.strip_edges().is_empty() or "replace" in definition.source_license.to_lower():
			failures.append("Production asset %s retained placeholder source/license metadata" % required_asset_id)
	if catalog.definition_for("missing_asset") != null:
		failures.append("Catalog returned a definition for an unknown asset id")

func _validate_feature_specs() -> void:
	var profile := resort.get("course_profile") as ParkCourseProfile
	var catalog := resort.get("environment_asset_catalog") as EnvironmentAssetCatalog
	if profile == null or catalog == null:
		return
	for spec: Dictionary in profile.feature_specs():
		for key: String in ["asset_id", "scale_override", "collision_policy", "readability_category"]:
			if not spec.has(key):
				failures.append("Feature %s is missing contract key %s" % [str(spec.get("name", "<unnamed>")), key])
		var asset_id := str(spec.get("asset_id", ""))
		if catalog.definition_for(asset_id) == null:
			failures.append("Feature %s references unregistered asset %s" % [str(spec.get("name", "<unnamed>")), asset_id])
		if float(spec.get("scale_override", 1.0)) <= 0.0:
			failures.append("Feature %s has a non-positive scale override" % str(spec.get("name", "<unnamed>")))

func _validate_built_contracts() -> void:
	var features: Dictionary = resort.get("course_features") as Dictionary
	if features.is_empty():
		failures.append("Resort did not build any course features")
		return
	for feature_name: String in features:
		var feature := features[feature_name] as Node3D
		if feature == null:
			failures.append("Feature %s is not a Node3D" % feature_name)
			continue
		for key: String in ["asset_id", "asset_class", "collision_policy", "readability_category", "scale_override"]:
			if not feature.has_meta(key):
				failures.append("Feature %s is missing runtime metadata %s" % [feature_name, key])
		var asset_class := str(feature.get_meta("asset_class", ""))
		var asset_source := str(feature.get_meta("asset_source", ""))
		if asset_source not in ["production_scene", "project_authored_parametric_scene"]:
			failures.append("Feature %s did not originate from a production catalog scene" % feature_name)
		var colliders := feature.find_children("*", "CollisionShape3D", true, false)
		if asset_class == "GUIDE" and not colliders.is_empty():
			failures.append("GUIDE feature %s created collision geometry" % feature_name)
		if asset_class in ["SOLID", "GRIND_ONLY", "BOUNDARY"] and colliders.is_empty():
			failures.append("Physical feature %s has no matching collision geometry" % feature_name)
		if float(feature.get_meta("scale_override", 0.0)) <= 0.0:
			failures.append("Feature %s retained an invalid scale override" % feature_name)

func _validate_bonk_assembly() -> void:
	# The orange bonk's collider and visual mesh share one body transform, the
	# snow cap rides the physical top, and the base seats into the slope so
	# skis cannot slip through a visual/collision gap.
	var parent := Node3D.new()
	add_child(parent)
	var bonk := ParkLayout.add_bonk(parent, "ContractBonk", 22.0, 76.0, 1.3, 0.42, Color("#ffc857"))
	var body := bonk.get_node_or_null("BonkBody") as StaticBody3D
	if body == null:
		failures.append("Bonk assembly did not create its BonkBody collider")
		parent.queue_free()
		return
	if int(body.collision_layer) != 4:
		failures.append("BonkBody left the Features collision layer")
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var mesh_instance := body.get_node_or_null("BonkMesh") as MeshInstance3D
	var shape := shape_node.shape as CylinderShape3D if shape_node != null else null
	var mesh := mesh_instance.mesh as CylinderMesh if mesh_instance != null else null
	if shape == null or mesh == null:
		failures.append("Bonk assembly lost its cylinder collider or visual mesh")
	elif absf(shape.radius - mesh.top_radius) > 0.001 or absf(shape.radius - mesh.bottom_radius) > 0.001 or absf(shape.height - mesh.height) > 0.001:
		failures.append("Bonk collider (r=%.3f h=%.3f) disagrees with its visual mesh (r=%.3f/%.3f h=%.3f)" % [shape.radius, shape.height, mesh.top_radius, mesh.bottom_radius, mesh.height])
	var cap := body.get_node_or_null("SnowCap")
	if cap == null:
		for child: Node in body.get_children():
			if child is MeshInstance3D and child != mesh_instance:
				cap = child
	if cap == null:
		failures.append("Bonk snow cap is not attached to the collider body")
	elif (cap as Node3D).position.distance_to(Vector3(0.0, 1.3 * 0.5 + 0.045, 0.0)) > 0.001:
		failures.append("Bonk snow cap drifted off the physical top")
	var snow := ParkLayout.snow_at(22.0, 76.0)
	var normal := ParkLayout.snow_normal()
	var base_point: Vector3 = body.global_transform * Vector3(0.0, -1.3 * 0.5, 0.0)
	if (base_point - snow).dot(normal) > 0.01:
		failures.append("Bonk base floats above the snow surface")
	parent.queue_free()
