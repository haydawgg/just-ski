extends Node

## Phase 11 resort density acceptance: off-line parallax props exist in every
## course band, stay outside the competition corridor, obey their catalog
## collision semantics, and expose catalog-driven LOD metadata.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowMaterial := preload("res://world/snow_material.gd")
const EXPECTED_ASSETS: Array[String] = ["piste_marker", "snow_bank", "lift_station"]
const MIN_COUNTS := {"piste_marker": 14, "snow_bank": 8, "lift_station": 1, "lift_tower": 5, "lift_line": 3}
const CORRIDOR_HALF_WIDTH := 27.0
const CORRIDOR_CLEARANCE_M := 1.5
const PARALLAX_MIN_LATERAL := 8.0
const PARALLAX_MAX_LATERAL := 48.0
const PARALLAX_BAND_M := 50.0
const PARALLAX_MIN_PROPS := 2
const PARALLAX_Z_MAX := 140.0
const PARALLAX_Z_MIN := -240.0

@onready var resort: Node3D = $Resort

var failures: Array[String] = []
var instances_by_asset: Dictionary = {}

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var catalog := resort.get("environment_asset_catalog") as EnvironmentAssetCatalog
	if catalog == null:
		failures.append("Resort did not expose its environment asset catalog")
		_finish()
		return
	_collect_instances()
	_validate_catalog(catalog)
	_validate_counts()
	_validate_semantics(catalog)
	_validate_corridor_clearance()
	_validate_parallax_bands()
	_validate_landing_scrapes()
	_finish()

func _validate_catalog(catalog: EnvironmentAssetCatalog) -> void:
	for asset_id: String in EXPECTED_ASSETS:
		var definition := catalog.definition_for(asset_id)
		if definition == null:
			failures.append("Catalog is missing density asset %s" % asset_id)
			continue
		if definition.nominal_size_m.x <= 0.0 or definition.nominal_size_m.y <= 0.0 or definition.nominal_size_m.z <= 0.0:
			failures.append("Density asset %s has a non-positive nominal size" % asset_id)
		if definition.source_license.is_empty() or definition.source_license.findn("replace") >= 0:
			failures.append("Density asset %s retained placeholder license metadata" % asset_id)

func _validate_counts() -> void:
	for asset_id: String in MIN_COUNTS:
		var count := (instances_by_asset.get(asset_id, []) as Array).size()
		if count < int(MIN_COUNTS[asset_id]):
			failures.append("Resort built %d %s props; expected at least %d" % [count, asset_id, int(MIN_COUNTS[asset_id])])
	print("DENSITY_COUNTS %s" % _counts_text())

func _validate_semantics(catalog: EnvironmentAssetCatalog) -> void:
	for asset_id: String in EXPECTED_ASSETS:
		var definition := catalog.definition_for(asset_id)
		if definition == null:
			continue
		var expected_class: String = EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class]
		for node: Node in instances_by_asset.get(asset_id, []):
			var prop := node as Node3D
			if prop == null:
				failures.append("Density prop %s is not spatial" % asset_id)
				continue
			if str(prop.get_meta("asset_class", "")) != expected_class:
				failures.append("%s instance lost its %s catalog class" % [asset_id, expected_class])
			if definition.asset_class == EnvironmentAssetDefinition.AssetClass.GUIDE or definition.asset_class == EnvironmentAssetDefinition.AssetClass.DECORATION:
				if not prop.find_children("*", "CollisionObject3D", true, false).is_empty():
					failures.append("%s instance introduced gameplay collision" % asset_id)
			if prop.has_meta("lod_distances_m") and prop.get_meta("lod_distances_m") != definition.lod_distances_m:
				failures.append("%s instance did not inherit catalog LOD distances" % asset_id)
			for mesh_node: Node in prop.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := mesh_node as MeshInstance3D
				if mesh_instance == null or mesh_instance.mesh == null:
					continue
				var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
				if bounds.position.x < CORRIDOR_HALF_WIDTH and bounds.end.x > -CORRIDOR_HALF_WIDTH:
					failures.append("%s instance reaches inside the competition corridor (x %.1f..%.1f)" % [asset_id, bounds.position.x, bounds.end.x])
					break

func _collect_instances() -> void:
	for node: Node in resort.find_children("*", "Node3D", true, false):
		var asset_id := str(node.get_meta("asset_id", ""))
		if asset_id.is_empty():
			continue
		if not instances_by_asset.has(asset_id):
			instances_by_asset[asset_id] = []
		instances_by_asset[asset_id].append(node)

func _validate_corridor_clearance() -> void:
	for asset_id: String in EXPECTED_ASSETS:
		for node: Node in instances_by_asset.get(asset_id, []):
			var prop := node as Node3D
			if prop == null:
				continue
			var bounds := _prop_aabb(prop)
			if bounds.size == Vector3.ZERO:
				continue
			var clearance := 0.0
			if bounds.end.x < -CORRIDOR_HALF_WIDTH:
				clearance = -CORRIDOR_HALF_WIDTH - bounds.end.x
			elif bounds.position.x > CORRIDOR_HALF_WIDTH:
				clearance = bounds.position.x - CORRIDOR_HALF_WIDTH
			if clearance < CORRIDOR_CLEARANCE_M:
				failures.append("%s prop %s has only %.2f m of corridor clearance (need %.2f)" % [asset_id, prop.name, clearance, CORRIDOR_CLEARANCE_M])

func _validate_parallax_bands() -> void:
	var band_coverage: Dictionary = {}
	for node: Node in resort.find_children("*", "Node3D", true, false):
		var asset_id := str(node.get_meta("asset_id", ""))
		if asset_id.is_empty() or not (instances_by_asset.get(asset_id, []) as Array).has(node):
			continue
		var prop := node as Node3D
		if prop == null or prop.get_parent() != resort:
			continue
		var origin := prop.global_position
		var lateral := absf(origin.x - (-12.0))
		if lateral < PARALLAX_MIN_LATERAL or lateral > PARALLAX_MAX_LATERAL:
			continue
		if origin.z > PARALLAX_Z_MAX or origin.z < PARALLAX_Z_MIN:
			continue
		var band := int(floor((PARALLAX_Z_MAX - origin.z) / PARALLAX_BAND_M))
		band_coverage[band] = int(band_coverage.get(band, 0)) + 1
	var band_count := int(ceil((PARALLAX_Z_MAX - PARALLAX_Z_MIN) / PARALLAX_BAND_M))
	for band: int in range(band_count):
		if int(band_coverage.get(band, 0)) < PARALLAX_MIN_PROPS:
			failures.append("Parallax band %d (z %.0f..%.0f) has %d near-lane props; expected %d" % [band, PARALLAX_Z_MAX - float(band + 1) * PARALLAX_BAND_M, PARALLAX_Z_MAX - float(band) * PARALLAX_BAND_M, int(band_coverage.get(band, 0)), PARALLAX_MIN_PROPS])
	print("DENSITY_BANDS %s" % str(band_coverage))

func _validate_landing_scrapes() -> void:
	var features: Dictionary = resort.course_features
	var checked := 0
	for feature_name: String in features:
		var root := features[feature_name] as Node3D
		if root == null or root.get_node_or_null("Landing") == null:
			continue
		checked += 1
		var scrapes: Array[MeshInstance3D] = []
		for mesh_node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance != null and bool(mesh_instance.get_meta("landing_scrape", false)):
				scrapes.append(mesh_instance)
		if scrapes.size() != 1:
			failures.append("%s has %d landing scrape surfaces (expected one)" % [feature_name, scrapes.size()])
			continue
		var scrape := scrapes[0]
		if not scrape.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("%s landing scrape introduced collision" % feature_name)
		var material := scrape.material_override as ShaderMaterial
		if material == null or material.shader == null or material.get("presentation_role") == null or int(material.get("presentation_role")) != SnowMaterial.PresentationRole.PARK_FEATURE:
			failures.append("%s landing scrape lost its park-feature snow material" % feature_name)
		elif float(material.get("feature_emphasis")) < 0.4:
			failures.append("%s landing scrape is not more disturbed than the landing (%.2f)" % [feature_name, float(material.get("feature_emphasis"))])
		var landing := root.get_node("Landing") as StaticBody3D
		var offset := _scrape_offset(scrape, landing)
		if offset < 0.015 or offset > 0.06:
			failures.append("%s landing scrape sits %.3f m above the landing (expected 0.015-0.06)" % [feature_name, offset])
	print("DENSITY_SCRAPES features=%d" % checked)

func _scrape_offset(scrape: MeshInstance3D, landing: StaticBody3D) -> float:
	var scrape_arrays := (scrape.mesh as ArrayMesh).surface_get_arrays(0)
	var scrape_vertices: PackedVector3Array = scrape_arrays[Mesh.ARRAY_VERTEX]
	var landing_vertices := PackedVector3Array()
	for mesh_node: Node in landing.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var arrays := (mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
		for vertex: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			landing_vertices.append(landing.global_transform * vertex)
	var minimum := INF
	for vertex: Vector3 in scrape_vertices:
		if not vertex.is_finite():
			continue
		var world_vertex := scrape.global_transform * vertex
		for landing_vertex: Vector3 in landing_vertices:
			minimum = minf(minimum, world_vertex.distance_to(landing_vertex))
	return minimum if is_finite(minimum) else 0.0

func _prop_aabb(prop: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for mesh_node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		result = bounds if not initialized else result.merge(bounds)
		initialized = true
	return result

func _counts_text() -> String:
	var parts: Array[String] = []
	for asset_id: String in MIN_COUNTS:
		parts.append("%s=%d" % [asset_id, (instances_by_asset.get(asset_id, []) as Array).size()])
	return str(parts)

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("RESORT_DENSITY_PASS: parallax props fill every course band outside the competition corridor with catalog-correct semantics")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RESORT_DENSITY_FAIL: " + failure)
	get_tree().quit(1)
