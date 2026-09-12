class_name SummitEnvironmentBuilder
extends RefCounted

## Builds the authored presentation layer for the summit-to-first-landing
## slice. The existing MainSnowFace StaticBody3D remains the sole gameplay
## collider; this builder replaces only its render mesh and adds decoration.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowSurface := preload("res://world/snow_material.gd")
const EnvironmentAssetCatalog := preload("res://resources/environment/environment_asset_catalog.gd")
const EnvironmentAssetDefinition := preload("res://resources/environment/environment_asset_definition.gd")
const DISTANT_MOUNTAIN_SHADER: Shader = preload("res://shaders/distant_mountain.gdshader")

static func build(parent: Node3D, main_face: StaticBody3D, profile: SummitEnvironmentProfile, catalog: EnvironmentAssetCatalog = null) -> Dictionary:
	var built := {
		"terrain": false,
		"boulders": 0,
		"lift_line": false,
	}
	if parent == null or profile == null or not profile.enabled:
		return built
	if main_face != null:
		_replace_main_face_render(parent, main_face, profile)
	if profile.dressing_enabled:
		if profile.rock_clusters_enabled:
			built["boulders"] = _add_boulders(parent, profile, catalog)
		if profile.lift_line_enabled:
			built["lift_line"] = _add_lift_line(parent, profile, catalog)
	built["terrain"] = true
	return built

static func build_backdrop(parent: Node3D, profile: SummitEnvironmentProfile) -> int:
	if parent == null or profile == null or not profile.enabled or not profile.backdrop_enabled:
		return 0
	var count := 0
	for spec: Dictionary in _backdrop_specs():
		_add_ridge(parent, profile, spec)
		count += 1
	return count

static func _replace_main_face_render(parent: Node3D, main_face: StaticBody3D, profile: SummitEnvironmentProfile) -> void:
	# Keep the original box and its BoxShape3D in place for physics. Only hide
	# the coarse render mesh so the generated surface cannot z-fight with it.
	for node: Node in main_face.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.visible = false
			# The coarse box is retained for physics, but a hidden renderer can
			# still participate in directional shadows/SDFGI. Exclude it from both
			# so it cannot blanket-shadow the authored surface at a low sun angle.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.set_meta("gi_exclude", true)
	# Phase 10: the playable corridor and the presentation-only shoulder relief
	# are separate render regions with different shadow architecture. The
	# interactive piste uses the standard shadow-receiving snow material; only
	# the off-corridor relief keeps the shadow-safe summit workaround.
	var playable_half := clampf(profile.playable_half_width_m, 1.0, ParkLayout.FACE_WIDTH * 0.5)
	var outer_half := clampf(profile.outer_half_width_m, playable_half + 1.0, ParkLayout.FACE_WIDTH * 0.5)
	_add_render_region(parent, profile, "SummitPlayableRenderSurface", "playable", -playable_half, playable_half, false)
	_add_render_region(parent, profile, "SummitReliefRenderSurfaceLeft", "shoulder_left", -outer_half, -playable_half, true)
	_add_render_region(parent, profile, "SummitReliefRenderSurfaceRight", "shoulder_right", playable_half, outer_half, true)

static func _add_render_region(parent: Node3D, profile: SummitEnvironmentProfile, label: String, region: String, x_min: float, x_max: float, shadow_safe: bool) -> void:
	var render := MeshInstance3D.new()
	render.name = label
	render.mesh = _create_region_mesh(profile, x_min, x_max)
	render.material_override = SnowSurface.create(SnowSurface.Kind.GROOMED, Vector2(0.0, -1.0), 0.0, shadow_safe, SnowSurface.PresentationRole.GROUND)
	render.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	render.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	render.visibility_range_end = maxf(profile.terrain_lod_end_m, 100.0)
	render.visibility_range_end_margin = 28.0
	render.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	render.set_meta("environment_summit_visual", true)
	render.set_meta("render_only", true)
	render.set_meta("gi_exclude", true)
	render.set_meta("summit_render_region", region)
	render.set_meta("summit_shadow_receiving", not shadow_safe)
	render.add_to_group("environment_summit_visual")
	parent.add_child(render)

static func sample_height(x: float, z: float, profile: SummitEnvironmentProfile) -> float:
	if profile == null:
		return ParkLayout.snow_at(x, z).y
	return _terrain_height(x, z, profile)


static func _terrain_height(x: float, z: float, profile: SummitEnvironmentProfile) -> float:
	var base := ParkLayout.snow_at(x, z)
	var outer_half_width := clampf(profile.outer_half_width_m, profile.playable_half_width_m + 1.0, ParkLayout.FACE_WIDTH * 0.5)
	var playable_half_width := clampf(profile.playable_half_width_m, 1.0, outer_half_width - 1.0)
	var edge_blend := smoothstep(playable_half_width, outer_half_width, absf(x))
	# Relief is limited to the authored summit window. The playable corridor is
	# therefore exactly coplanar with the existing collision surface, including
	# under the first tabletop and its landing.
	var uphill_fade := smoothstep(92.0, 103.0, z)
	var downhill_fade := 1.0 - smoothstep(128.0, 145.0, z)
	var summit_window := clampf(uphill_fade * downhill_fade, 0.0, 1.0)
	var seed_phase := float(profile.relief_seed) * 0.0137
	var broad := 0.5 + 0.30 * sin(z * profile.relief_frequency + x * 0.095 + seed_phase)
	var fine := 0.5 + 0.20 * cos(z * profile.secondary_relief_frequency - x * 0.073 - seed_phase * 0.7)
	var relief := clampf(broad + fine - 0.32, 0.0, 1.0)
	return base.y + profile.surface_offset_m + edge_blend * summit_window * profile.shoulder_amplitude_m * relief

static func _create_region_mesh(profile: SummitEnvironmentProfile, x_min: float, x_max: float) -> ArrayMesh:
	# Each render region samples exactly from x_min to x_max so the playable and
	# shoulder meshes share an identical boundary column (the edge blend is zero
	# at the playable edge), leaving no crack or overlap along x = +/- playable.
	var spacing := maxf(profile.sample_spacing_m, 0.5)
	var column_count := maxi(2, ceili((x_max - x_min) / spacing) + 1)
	var z_min := -ParkLayout.face_half_world_z()
	var z_max := ParkLayout.face_half_world_z()
	var row_count := maxi(3, ceili((z_max - z_min) / spacing) + 1)
	var world_rows: Array[PackedVector3Array] = []
	for row_index: int in range(row_count):
		var z := lerpf(z_max, z_min, float(row_index) / float(row_count - 1))
		var world_row := PackedVector3Array()
		for column_index: int in range(column_count):
			var x := lerpf(x_min, x_max, float(column_index) / float(column_count - 1))
			world_row.append(Vector3(x, _terrain_height(x, z, profile), z))
		world_rows.append(world_row)
	var normal := ParkLayout.snow_normal()
	var bottom_rows: Array[PackedVector3Array] = []
	for world_row: PackedVector3Array in world_rows:
		var bottom := PackedVector3Array()
		for point: Vector3 in world_row:
			# The original box collider remains below this surface. A shallow render
			# skirt prevents a bright vertical wall at the visible edge while still
			# closing the mesh for stable backface/culling behavior.
			bottom.append(point - normal * 0.18)
		bottom_rows.append(bottom)
	var top_normals: Array[PackedVector3Array] = []
	for row_index: int in range(row_count):
		var normal_row := PackedVector3Array()
		for column_index: int in range(column_count):
			var previous_row := maxi(row_index - 1, 0)
			var next_row := mini(row_index + 1, row_count - 1)
			var previous_column := maxi(column_index - 1, 0)
			var next_column := mini(column_index + 1, column_count - 1)
			var longitudinal := world_rows[next_row][column_index] - world_rows[previous_row][column_index]
			var lateral := world_rows[row_index][next_column] - world_rows[row_index][previous_column]
			var vertex_normal := lateral.cross(longitudinal).normalized()
			if vertex_normal.dot(normal) < 0.0:
				vertex_normal = -vertex_normal
			normal_row.append(vertex_normal)
		top_normals.append(normal_row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row_index: int in range(row_count - 1):
		for column_index: int in range(column_count - 1):
			var a := world_rows[row_index][column_index]
			var b := world_rows[row_index + 1][column_index]
			var c := world_rows[row_index + 1][column_index + 1]
			var d := world_rows[row_index][column_index + 1]
			var uv_a := Vector2(float(column_index), float(row_index)) * 0.12
			var uv_b := Vector2(float(column_index), float(row_index + 1)) * 0.12
			var uv_c := Vector2(float(column_index + 1), float(row_index + 1)) * 0.12
			var uv_d := Vector2(float(column_index + 1), float(row_index)) * 0.12
			_add_smooth_tri(st, a, d, c, top_normals[row_index][column_index], top_normals[row_index][column_index + 1], top_normals[row_index + 1][column_index + 1], uv_a, uv_d, uv_c)
			_add_smooth_tri(st, a, c, b, top_normals[row_index][column_index], top_normals[row_index + 1][column_index + 1], top_normals[row_index + 1][column_index], uv_a, uv_c, uv_b)
			_add_flat_quad(st, bottom_rows[row_index][column_index], bottom_rows[row_index + 1][column_index], bottom_rows[row_index + 1][column_index + 1], bottom_rows[row_index][column_index + 1])
	for row_index: int in range(row_count - 1):
		_add_flat_quad(st, world_rows[row_index][0], world_rows[row_index + 1][0], bottom_rows[row_index + 1][0], bottom_rows[row_index][0])
		_add_flat_quad(st, world_rows[row_index][-1], bottom_rows[row_index][-1], bottom_rows[row_index + 1][-1], world_rows[row_index + 1][-1])
	for column_index: int in range(column_count - 1):
		_add_flat_quad(st, world_rows[0][column_index], bottom_rows[0][column_index], bottom_rows[0][column_index + 1], world_rows[0][column_index + 1])
		_add_flat_quad(st, world_rows[-1][column_index], world_rows[-1][column_index + 1], bottom_rows[-1][column_index + 1], bottom_rows[-1][column_index])
	st.generate_tangents()
	return st.commit()

static func _add_boulders(parent: Node3D, profile: SummitEnvironmentProfile, catalog: EnvironmentAssetCatalog) -> int:
	if catalog == null or not catalog.should_use_scene("snow_boulder"):
		return 0
	var placements: Array[Vector4] = [
		Vector4(-29.0, 132.0, 1.10, 14.0),
		Vector4(-30.0, 116.0, 0.78, -22.0),
		Vector4(29.4, 126.0, 0.92, 31.0),
		Vector4(30.0, 104.0, 1.22, -18.0),
	]
	var added := 0
	for placement: Vector4 in placements:
		var position := ParkLayout.snow_at(placement.x, placement.y)
		var boulder := _instantiate_catalog_asset(parent, catalog, "snow_boulder", position, Basis(Vector3.UP, deg_to_rad(placement.w)), Vector3.ONE * placement.z, int(added))
		if boulder != null:
			added += 1
	return added

static func _add_lift_line(parent: Node3D, profile: SummitEnvironmentProfile, catalog: EnvironmentAssetCatalog) -> bool:
	if catalog == null or not catalog.should_use_scene("lift_line"):
		return false
	var position := ParkLayout.snow_at(30.2, 116.0)
	var lift_line := _instantiate_catalog_asset(parent, catalog, "lift_line", position, ParkLayout.downhill_basis(), Vector3.ONE, 0)
	return lift_line != null

static func _instantiate_catalog_asset(parent: Node3D, catalog: EnvironmentAssetCatalog, asset_id: String, position: Vector3, basis: Basis, scale: Vector3, variant: int) -> Node3D:
	var scene := catalog.scene_for(asset_id)
	if scene == null:
		if catalog.should_use_production_scenes():
			push_error("ENVIRONMENT_ASSET_FAIL: summit decoration '%s' is missing" % asset_id)
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		push_error("ENVIRONMENT_ASSET_FAIL: summit decoration '%s' did not instantiate as Node3D" % asset_id)
		return null
	instance.name = asset_id
	instance.position = position
	instance.basis = basis
	instance.scale = scale
	instance.set_meta("asset_id", asset_id)
	instance.set_meta("asset_source", "production_scene")
	instance.set_meta("style_variant", variant)
	var definition := catalog.definition_for(asset_id)
	if definition != null:
		instance.set_meta("lod_distances_m", definition.lod_distances_m)
		instance.set_meta("asset_class", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
		instance.set_meta("collision_policy", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
	parent.add_child(instance)
	if instance.has_method("build_now"):
		instance.call("build_now")
	if definition != null:
		for reason: String in definition.validate_instance(instance):
			if catalog.should_use_production_scenes():
				push_error("ENVIRONMENT_ASSET_FAIL: %s: %s" % [asset_id, reason])
			else:
				push_warning("ENVIRONMENT_ASSET_WARNING: %s: %s" % [asset_id, reason])
	return instance

static func _backdrop_specs() -> Array[Dictionary]:
	# Phase 11: multiple topology families and a rebalanced depth ladder so the
	# close shoulders no longer loom over the ski area. Global environment fog
	# is the primary aerial-perspective system; the shader only adds a bounded
	# local blend (haze_blend) on top of it.
	return [
		{"name": "LongRidgeWest", "topology": "long_ridge", "position": Vector3(-240.0, 18.0, -250.0), "radius": 150.0, "height": 58.0, "color": Color("#63819a"), "yaw": -6.0, "seed": 211},
		{"name": "LowRidgeCenter", "topology": "low_ridge", "position": Vector3(0.0, 20.0, -258.0), "radius": 180.0, "height": 34.0, "color": Color("#6d8ba3"), "yaw": 3.0, "seed": 223},
		{"name": "LongRidgeEast", "topology": "long_ridge", "position": Vector3(245.0, 17.0, -240.0), "radius": 145.0, "height": 55.0, "color": Color("#63819a"), "yaw": 7.0, "seed": 229},
		{"name": "ShoulderNorthWest", "topology": "shoulder", "position": Vector3(-210.0, 14.0, -190.0), "radius": 90.0, "height": 72.0, "color": Color("#6f8fa7"), "yaw": 20.0, "seed": 233},
		{"name": "ShoulderNorthEast", "topology": "shoulder", "position": Vector3(215.0, 15.0, -175.0), "radius": 86.0, "height": 76.0, "color": Color("#6f8fa7"), "yaw": -18.0, "seed": 239},
		{"name": "SaddleRidgeWest", "topology": "saddle", "position": Vector3(-120.0, 6.0, -300.0), "radius": 110.0, "height": 105.0, "color": Color("#6889a2"), "yaw": -9.0, "seed": 241},
		{"name": "SaddleRidgeEast", "topology": "saddle", "position": Vector3(135.0, 8.0, -285.0), "radius": 105.0, "height": 100.0, "color": Color("#6889a2"), "yaw": 11.0, "seed": 251},
		{"name": "FarPeakWest", "topology": "sharp_peak", "position": Vector3(-190.0, 10.0, -380.0), "radius": 80.0, "height": 150.0, "color": Color("#7897ad"), "yaw": -11.0, "seed": 11},
		{"name": "FarPeakCenter", "topology": "sharp_peak", "position": Vector3(15.0, 2.0, -420.0), "radius": 88.0, "height": 165.0, "color": Color("#6f8fa8"), "yaw": 2.0, "seed": 43},
		{"name": "FarPeakEast", "topology": "sharp_peak", "position": Vector3(205.0, 12.0, -360.0), "radius": 84.0, "height": 148.0, "color": Color("#7897ad"), "yaw": 9.0, "seed": 83},
		{"name": "HazePeakWest", "topology": "massif", "position": Vector3(-260.0, 0.0, -560.0), "radius": 150.0, "height": 120.0, "color": Color("#9aafbd"), "yaw": -8.0, "seed": 101},
		{"name": "HazePeakCenter", "topology": "massif", "position": Vector3(10.0, -6.0, -600.0), "radius": 190.0, "height": 140.0, "color": Color("#a3b5c0"), "yaw": 4.0, "seed": 203},
		{"name": "HazePeakEast", "topology": "massif", "position": Vector3(250.0, 0.0, -545.0), "radius": 160.0, "height": 125.0, "color": Color("#96abb9"), "yaw": 13.0, "seed": 307},
	]

static func _add_ridge(parent: Node3D, profile: SummitEnvironmentProfile, spec: Dictionary) -> void:
	var root := Node3D.new()
	root.name = str(spec.name)
	root.position = spec.position
	root.rotation_degrees.y = float(spec.yaw)
	root.set_meta("environment_backdrop", true)
	root.set_meta("backdrop_topology", str(spec.get("topology", "massif")))
	root.add_to_group("environment_backdrop")
	var mountain := MeshInstance3D.new()
	mountain.name = "RidgeBody"
	mountain.mesh = _create_topology_mesh(float(spec.radius), float(spec.height), int(spec.seed), str(spec.get("topology", "massif")))
	var rock_material := ShaderMaterial.new()
	rock_material.shader = DISTANT_MOUNTAIN_SHADER
	rock_material.set_shader_parameter("base_color", Color(spec.color).lightened(0.08))
	rock_material.set_shader_parameter("haze_color", Color("#b4c2ca"))
	rock_material.set_shader_parameter("haze_start_distance", 170.0)
	rock_material.set_shader_parameter("haze_end_distance", 620.0)
	rock_material.set_shader_parameter("haze_blend", float(spec.get("haze_blend", 0.28)))
	rock_material.set_shader_parameter("facet_value_range", 0.12)
	rock_material.set_shader_parameter("mountain_height", float(spec.height))
	mountain.material_override = rock_material
	mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mountain.visibility_range_end = maxf(profile.backdrop_lod_end_m, 300.0)
	mountain.visibility_range_end_margin = 48.0
	mountain.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mountain)
	parent.add_child(root)

# Topology families: each entry defines the ring silhouette and footprint
# stretch. Saddle and massif place multiple summits inside one ridge mesh.
const TOPOLOGY_PROFILES := {
	"massif": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.42, 1.24, 1.06, 0.94, 0.78, 0.64, 0.5, 0.34, 0.16, 0.0],
		"x_stretch": 1.7, "z_stretch": 1.05, "ridge_primary": 5.0, "ridge_secondary": 9.0,
		"summits": [{"x": -0.34, "z": 0.05, "scale": 0.78, "height": 0.82}, {"x": 0.0, "z": -0.04, "scale": 1.0, "height": 1.0}, {"x": 0.38, "z": 0.02, "scale": 0.72, "height": 0.78}],
	},
	"sharp_peak": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.0, 0.82, 0.66, 0.52, 0.4, 0.3, 0.22, 0.14, 0.07, 0.0],
		"x_stretch": 0.9, "z_stretch": 0.72, "ridge_primary": 6.0, "ridge_secondary": 11.0,
		"summits": [{"x": 0.0, "z": 0.0, "scale": 1.0, "height": 1.0}],
	},
	"saddle": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.28, 1.12, 0.96, 0.84, 0.7, 0.58, 0.44, 0.3, 0.13, 0.0],
		"x_stretch": 1.8, "z_stretch": 0.9, "ridge_primary": 5.0, "ridge_secondary": 8.0,
		"summits": [{"x": -0.42, "z": 0.0, "scale": 0.74, "height": 0.88}, {"x": 0.42, "z": -0.03, "scale": 0.7, "height": 0.82}],
	},
	"long_ridge": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.18, 1.08, 0.98, 0.9, 0.8, 0.68, 0.54, 0.36, 0.16, 0.0],
		"x_stretch": 2.3, "z_stretch": 0.55, "ridge_primary": 4.0, "ridge_secondary": 7.0,
		"summits": [{"x": -0.3, "z": 0.0, "scale": 0.82, "height": 0.9}, {"x": 0.02, "z": 0.0, "scale": 1.0, "height": 1.0}, {"x": 0.36, "z": 0.0, "scale": 0.78, "height": 0.86}],
	},
	"shoulder": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.12, 1.02, 0.92, 0.82, 0.7, 0.58, 0.44, 0.28, 0.12, 0.0],
		"x_stretch": 1.45, "z_stretch": 0.8, "ridge_primary": 5.0, "ridge_secondary": 9.0,
		"summits": [{"x": 0.3, "z": -0.05, "scale": 1.0, "height": 1.0}],
	},
	"low_ridge": {
		"ring_heights": [-0.55, -0.2, 0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.93, 1.0],
		"ring_scales": [1.24, 1.14, 1.04, 0.94, 0.84, 0.72, 0.58, 0.4, 0.18, 0.0],
		"x_stretch": 2.6, "z_stretch": 0.7, "ridge_primary": 3.0, "ridge_secondary": 6.0,
		"summits": [{"x": -0.2, "z": 0.0, "scale": 0.9, "height": 0.9}, {"x": 0.24, "z": 0.02, "scale": 0.86, "height": 0.94}],
	},
}

static func _create_ridge_mesh(radius: float, height: float, seed: int) -> ArrayMesh:
	return _create_topology_mesh(radius, height, seed, "massif")

static func _create_topology_mesh(radius: float, height: float, seed: int, topology: String) -> ArrayMesh:
	var params: Dictionary = TOPOLOGY_PROFILES.get(topology, TOPOLOGY_PROFILES["massif"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var summit_index := 0
	for summit: Dictionary in params.summits:
		_append_ridge_body(
			st,
			radius * float(summit.scale),
			height * float(summit.height),
			seed + summit_index * 17,
			params,
			Vector2(float(summit.x), float(summit.z)) * radius
		)
		summit_index += 1
	st.generate_normals()
	return st.commit()

static func _append_ridge_body(st: SurfaceTool, radius: float, height: float, seed: int, params: Dictionary, peak_offset: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var segments := 32
	var ring_heights: Array = params.ring_heights
	var ring_scales: Array = params.ring_scales
	var x_stretch := float(params.x_stretch)
	var z_stretch := float(params.z_stretch)
	var ridge_primary := float(params.ridge_primary)
	var ridge_secondary := float(params.ridge_secondary)
	var ridge_points: Array[PackedVector3Array] = []
	for ring_index: int in range(ring_heights.size()):
		var points := PackedVector3Array()
		var center_offset := peak_offset * (float(ring_index) / float(ring_heights.size() - 1))
		for segment: int in range(segments):
			var angle := TAU * float(segment) / float(segments)
			var ridge := sin(angle * ridge_primary + float(seed)) * 0.12 + sin(angle * ridge_secondary + 0.4) * 0.07
			var irregularity := 1.0 + ridge + rng.randf_range(-0.035, 0.035)
			var ring_radius := radius * float(ring_scales[ring_index]) * irregularity
			var ring_y := float(ring_heights[ring_index]) + sin(angle * 3.0 + seed) * height * 0.08 * sin(float(ring_index) / 9.0 * PI)
			points.append(Vector3(cos(angle) * ring_radius * x_stretch + center_offset.x, ring_y, sin(angle) * ring_radius * z_stretch + center_offset.y))
		ridge_points.append(points)
	for ring_index: int in range(ridge_points.size() - 1):
		for segment: int in range(segments):
			var next := (segment + 1) % segments
			var a := ridge_points[ring_index][segment]
			var b := ridge_points[ring_index][next]
			var c := ridge_points[ring_index + 1][next]
			var d := ridge_points[ring_index + 1][segment]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _add_smooth_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3, normal_b: Vector3, normal_c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	for vertex: Array in [[a, normal_a, uv_a], [b, normal_b, uv_b], [c, normal_c, uv_c]]:
		st.set_normal(vertex[1])
		st.set_uv(vertex[2])
		st.add_vertex(vertex[0])

static func _add_flat_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var face_normal := (b - a).cross(c - a).normalized()
	if not face_normal.is_finite() or face_normal.length_squared() < 0.0001:
		face_normal = Vector3.UP
	_add_smooth_tri(st, a, b, c, face_normal, face_normal, face_normal, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE)
	_add_smooth_tri(st, a, c, d, face_normal, face_normal, face_normal, Vector2.ZERO, Vector2.ONE, Vector2.DOWN)
