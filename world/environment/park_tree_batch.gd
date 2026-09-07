class_name ParkTreeBatch
extends Node3D

## Render-only batching for deterministic park-tree placements. Collision and
## catalog identity stay on the lightweight placement roots owned by Resort.

var _placements: Array[Transform3D] = []

const DEFAULT_LOD_DISTANCES := Vector3(35.0, 105.0, 230.0)

func _init() -> void:
	name = "ParkTreeBatch"
	add_to_group("park_tree_batches")
	set_meta("asset_id", "park_tree")
	set_meta("asset_source", "production_multimesh")

func add_tree(tree_transform: Transform3D) -> void:
	_placements.append(tree_transform)

func commit() -> void:
	for child: Node in get_children():
		child.queue_free()
	if _placements.is_empty():
		return
	var bark := _material(Color("#59483b"), 0.9)
	var needle_dark := _material(Color("#163f38"), 0.86)
	var needle_mid := _material(Color("#255c50"), 0.84)
	var needle_light := _material(Color("#397565"), 0.82)
	var snow := _material(Color("#dcebf0"), 0.96)
	var lod := _lod_distances()
	# MultiMesh visibility is evaluated for the batch bounds, not each instance.
	# A compact six-part silhouette avoids drawing overlapping per-tree LODs for
	# a batch that spans the length of the course.
	_add_component("Trunks", _cylinder(0.24, 0.32, 3.0, 6, bark), Vector3(0.0, 1.5, 0.0), 0.0, lod.y, true)
	_add_component("LowerCanopies", _cylinder(0.12, 1.50, 2.4, 7, needle_dark), Vector3(0.0, 2.5, 0.0), 0.0, lod.y, true)
	_add_component("LowerSnow", _cylinder(0.05, 1.02, 0.38, 7, snow), Vector3(0.0, 3.48, 0.0), 0.0, lod.y, true)
	_add_component("MiddleCanopies", _cylinder(0.10, 1.18, 2.1, 7, needle_mid), Vector3(0.0, 3.7, 0.0), 0.0, lod.y, true)
	_add_component("UpperCanopies", _cylinder(0.04, 0.82, 1.8, 7, needle_light), Vector3(0.0, 4.85, 0.0), 0.0, lod.y, true)
	_add_component("UpperSnow", _cylinder(0.02, 0.56, 0.32, 7, snow), Vector3(0.0, 5.60, 0.0), 0.0, lod.y, true)
	# The far representation is intentionally simple and shadow-free. It uses
	# the catalog's near/far overlap and cull horizon, avoiding the old fixed
	# 230m range for every quality tier.
	_add_component("FarTrunks", _cylinder(0.24, 0.30, 3.0, 5, bark), Vector3(0.0, 1.5, 0.0), lod.x, lod.z, false)
	_add_component("FarCanopies", _cylinder(0.06, 1.34, 4.4, 6, needle_mid), Vector3(0.0, 3.65, 0.0), lod.x, lod.z, false)
	_add_component("FarSnow", _cylinder(0.03, 0.84, 0.36, 6, snow), Vector3(0.0, 5.52, 0.0), lod.x, lod.z, false)

func _add_component(label: String, mesh: Mesh, local_position: Vector3, range_begin: float, range_end: float, casts_shadow: bool) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _placements.size()
	var component_transform := Transform3D(Basis.IDENTITY, local_position)
	for index: int in _placements.size():
		multimesh.set_instance_transform(index, _placements[index] * component_transform)
	var render := MultiMeshInstance3D.new()
	render.name = label
	render.multimesh = multimesh
	render.visibility_range_begin = range_begin
	render.visibility_range_begin_margin = 18.0 if range_begin > 0.0 else 0.0
	render.visibility_range_end = range_end
	render.visibility_range_end_margin = 24.0
	render.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	render.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	render.set_meta("lod_distances_m", _lod_distances())
	render.set_meta("lod_source", "catalog" if has_meta("lod_distances_m") else "asset_default")
	add_child(render)

func _lod_distances() -> Vector3:
	var value = get_meta("lod_distances_m", DEFAULT_LOD_DISTANCES)
	if value is Vector3:
		var distances := value as Vector3
		if is_finite(distances.x) and is_finite(distances.y) and is_finite(distances.z) \
			and distances.x > 0.0 and distances.x < distances.y and distances.y < distances.z:
			return distances
	return DEFAULT_LOD_DISTANCES

func _cylinder(top_radius: float, bottom_radius: float, height: float, segments: int, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.material = material
	return mesh

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
