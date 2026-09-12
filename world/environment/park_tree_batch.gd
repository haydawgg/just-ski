class_name ParkTreeBatch
extends Node3D

## Render-only batching for deterministic park-tree placements. Collision and
## catalog identity stay on the lightweight placement roots owned by Resort.
##
## Phase 11: placements are grouped into deterministic spatial chunks and four
## structural conifer families. Each MultiMesh component therefore carries a
## course-local AABB, so visibility/LOD is evaluated per chunk instead of once
## for a batch spanning the whole course.

var _placements: Array[Dictionary] = []

const DEFAULT_LOD_DISTANCES := Vector3(48.0, 96.0, 235.0)
const CONIFER_ALBEDO := preload("res://assets/materials/alpine_props/conifer_needles_albedo_512.png")
const FAMILY_COUNT := 4
const CHUNK_COUNT := 4
const CHUNK_Z_MAX := 150.0
const CHUNK_SPAN_M := 130.0
# Distinct structural conifer families: tall/narrow, broad/mature, juvenile,
# snow-heavy. Family 0 remains the nominal catalog silhouette.
const FAMILY_PROFILES: Array[Dictionary] = [
	{"trunk_h": 3.6, "lower_r": 1.05, "lower_h": 2.6, "lower_y": 2.75, "upper_r": 0.62, "upper_h": 1.9, "upper_y": 4.55, "cap_r": 0.40, "cap_h": 0.34, "cap_y": 5.40, "lower_mat": 0, "upper_mat": 2},
	{"trunk_h": 3.0, "lower_r": 1.50, "lower_h": 2.3, "lower_y": 2.45, "upper_r": 0.95, "upper_h": 1.8, "upper_y": 3.95, "cap_r": 0.60, "cap_h": 0.36, "cap_y": 4.70, "lower_mat": 0, "upper_mat": 1},
	{"trunk_h": 2.6, "lower_r": 0.85, "lower_h": 1.9, "lower_y": 2.10, "upper_r": 0.52, "upper_h": 1.4, "upper_y": 3.30, "cap_r": 0.34, "cap_h": 0.28, "cap_y": 3.90, "lower_mat": 1, "upper_mat": 2},
	{"trunk_h": 3.2, "lower_r": 1.25, "lower_h": 2.2, "lower_y": 2.50, "upper_r": 0.72, "upper_h": 1.6, "upper_y": 4.00, "cap_r": 0.72, "cap_h": 0.50, "cap_y": 4.80, "lower_mat": 0, "upper_mat": 1},
]

func _init() -> void:
	name = "ParkTreeBatch"
	add_to_group("park_tree_batches")
	set_meta("asset_id", "park_tree")
	set_meta("asset_source", "production_multimesh")

func add_tree(tree_transform: Transform3D, variant: int = 0, family: int = -1) -> void:
	var resolved_family := family if family >= 0 else posmod(variant, FAMILY_COUNT)
	_placements.append({"transform": tree_transform, "variant": variant, "family": posmod(resolved_family, FAMILY_COUNT)})

func commit() -> void:
	for child: Node in get_children():
		child.queue_free()
	if _placements.is_empty():
		return
	var bark := _material(Color("#59483b"), 0.9)
	# Near-white tints compensate the dark (~58/255) conifer map so the batch
	# matches the LOD0 hierarchy in low_poly_environment_asset.gd.
	var needle_materials: Array[StandardMaterial3D] = [
		_material(Color("#c9d8d2"), 0.86, CONIFER_ALBEDO, 2.0),
		_material(Color("#dbe5e0"), 0.84, CONIFER_ALBEDO, 1.7),
		_material(Color("#e9f0ec"), 0.82, CONIFER_ALBEDO, 1.45),
	]
	var snow := _material(Color("#edf4f5"), 0.96)
	var lod := _lod_distances()
	var groups: Dictionary = {}
	var far_placements: Dictionary = {}
	for placement: Dictionary in _placements:
		var tree_transform := placement.get("transform", Transform3D.IDENTITY) as Transform3D
		var family := int(placement.get("family", 0))
		var chunk := _chunk_index(tree_transform.origin.z)
		var key := _group_key(chunk, family)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(placement)
		if not far_placements.has(chunk):
			far_placements[chunk] = []
		(far_placements[chunk] as Array).append(placement)
	var ordered_keys: Array[String] = []
	for key: String in groups:
		ordered_keys.append(key)
	ordered_keys.sort()
	for key: String in ordered_keys:
		var placements: Array = groups[key]
		var split := key.split(":")
		var chunk := int(split[0])
		var family := int(split[1])
		_build_family_chunk(chunk, family, placements, lod, bark, needle_materials, snow)
	var ordered_chunks: Array[int] = []
	for chunk: int in far_placements:
		ordered_chunks.append(chunk)
	ordered_chunks.sort()
	for chunk: int in ordered_chunks:
		_build_far_chunk(chunk, far_placements[chunk], lod, bark, needle_materials[1], snow)
	_placements.clear()

func _build_family_chunk(chunk: int, family: int, placements: Array, lod: Vector3, bark: StandardMaterial3D, needle_materials: Array[StandardMaterial3D], snow: StandardMaterial3D) -> void:
	var profile: Dictionary = FAMILY_PROFILES[family]
	var prefix := "Chunk%02d_Family%d" % [chunk, family]
	_add_component(prefix + "_Trunk", "trunk", family, chunk, "near", _cylinder(0.24, 0.32, float(profile.trunk_h), 6, bark), Vector3(0.0, float(profile.trunk_h) * 0.5, 0.0), 0.0, lod.y, true, placements)
	_add_component(prefix + "_LowerCanopy", "canopy", family, chunk, "near", _fir_mesh(float(profile.lower_r), float(profile.lower_h), 2, needle_materials[int(profile.lower_mat)]), Vector3(0.0, float(profile.lower_y), 0.0), 0.0, lod.y, true, placements)
	_add_component(prefix + "_UpperCanopy", "canopy", family, chunk, "near", _fir_mesh(float(profile.upper_r), float(profile.upper_h), 2, needle_materials[int(profile.upper_mat)]), Vector3(0.0, float(profile.upper_y), 0.0), 0.0, lod.y, true, placements)
	_add_component(prefix + "_SnowCap", "cap", family, chunk, "near", _fir_mesh(float(profile.cap_r), float(profile.cap_h), 1, snow), Vector3(0.0, float(profile.cap_y), 0.0), 0.0, lod.y, true, placements)

func _build_far_chunk(chunk: int, placements: Array, lod: Vector3, bark: StandardMaterial3D, needle_mid: StandardMaterial3D, snow: StandardMaterial3D) -> void:
	# The far representation is a single cheap silhouette per spatial chunk: it
	# keeps the LOD batch chunk-local without multiplying it by family.
	var prefix := "Chunk%02d_Far" % chunk
	_add_component(prefix + "_Trunk", "far_trunk", -1, chunk, "far", _cylinder(0.24, 0.30, 3.0, 5, bark), Vector3(0.0, 1.5, 0.0), lod.x, lod.z, false, placements)
	_add_component(prefix + "_Canopy", "far_canopy", -1, chunk, "far", _fir_mesh(1.40, 4.4, 4, needle_mid), Vector3(0.0, 3.65, 0.0), lod.x, lod.z, false, placements)
	_add_component(prefix + "_Snow", "far_cap", -1, chunk, "far", _fir_mesh(0.78, 0.4, 1, snow), Vector3(0.0, 5.52, 0.0), lod.x, lod.z, false, placements)

func _add_component(label: String, part: String, family: int, chunk: int, lod_band: String, mesh: Mesh, local_position: Vector3, range_begin: float, range_end: float, casts_shadow: bool, placements: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()
	var component_transform := Transform3D(Basis.IDENTITY, local_position)
	var local_bounds := AABB()
	var bounds_initialized := false
	for index: int in placements.size():
		var placement: Dictionary = placements[index]
		var tree_transform := placement.get("transform", Transform3D.IDENTITY) as Transform3D
		var instance_transform := tree_transform * component_transform
		multimesh.set_instance_transform(index, instance_transform)
		multimesh.set_instance_color(index, _variant_color(int(placement.get("variant", 0))))
		var instance_bounds := instance_transform * mesh.get_aabb()
		local_bounds = instance_bounds if not bounds_initialized else local_bounds.merge(instance_bounds)
		bounds_initialized = true
	if bounds_initialized:
		multimesh.custom_aabb = local_bounds
	var render := MultiMeshInstance3D.new()
	render.name = label
	render.multimesh = multimesh
	render.visibility_range_begin = range_begin
	render.visibility_range_begin_margin = 18.0 if range_begin > 0.0 else 0.0
	render.visibility_range_end = range_end
	render.visibility_range_end_margin = 24.0
	render.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	render.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	render.set_meta("tree_part", part)
	render.set_meta("tree_family", family)
	render.set_meta("tree_chunk", chunk)
	render.set_meta("tree_lod", lod_band)
	render.set_meta("lod_distances_m", _lod_distances())
	render.set_meta("lod_source", "catalog" if has_meta("lod_distances_m") else "asset_default")
	add_child(render)

func _group_key(chunk: int, family: int) -> String:
	return "%02d:%02d" % [chunk, family]

func _chunk_index(z: float) -> int:
	return clampi(int(floor((CHUNK_Z_MAX - z) / CHUNK_SPAN_M)), 0, CHUNK_COUNT - 1)

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

func _material(color: Color, roughness: float, albedo_texture: Texture2D = null, texture_world_size: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.vertex_color_use_as_albedo = true
	if albedo_texture != null:
		material.albedo_texture = albedo_texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		var texture_scale := 1.0 / maxf(texture_world_size, 0.01)
		material.uv1_scale = Vector3(texture_scale, texture_scale, texture_scale)
	return material

func _variant_color(variant: int) -> Color:
	# Subtle per-instance temperature shifts keep the batched grove from reading
	# as one repeated stamp while preserving the authored low-poly palette.
	match posmod(variant, 3):
		1:
			return Color(0.93, 1.0, 0.97, 1.0)
		2:
			return Color(1.0, 0.96, 0.91, 1.0)
		_:
			return Color.WHITE

func _fir_mesh(radius: float, height: float, tiers: int, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tier: int in tiers:
		var fraction := float(tier) / float(tiers)
		var tier_radius := radius * (1.0 - fraction * 0.72)
		var bottom := -height * 0.5 + height * fraction
		var tip := Vector3(0.0, bottom + height / tiers * 1.5, 0.0)
		for branch: int in 16:
			var angle := TAU * branch / 16.0 + tier * 0.37
			var next_angle := TAU * (branch + 1) / 16.0 + tier * 0.37
			var length_a := tier_radius * (1.0 if branch % 2 == 0 else 0.78)
			var length_b := tier_radius * (0.78 if branch % 2 == 0 else 1.0)
			var a := Vector3(cos(angle) * length_a, bottom + sin(angle * 3.0) * height * 0.025, sin(angle) * length_a)
			var b := Vector3(cos(next_angle) * length_b, bottom + sin(next_angle * 3.0) * height * 0.025, sin(next_angle) * length_b)
			surface.add_vertex(a)
			surface.add_vertex(b)
			surface.add_vertex(tip)
			surface.add_vertex(b)
			surface.add_vertex(a)
			surface.add_vertex(Vector3(0.0, bottom + 0.08, 0.0))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, material)
	return mesh
