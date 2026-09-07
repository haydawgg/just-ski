class_name LowPolyEnvironmentAsset
extends Node3D

## Project-authored low-poly environment presentation.
##
## Each PackedScene selects one asset kind. Geometry is deliberately built
## from meter-valued primitives so the scene remains easy to audit, recolor,
## and replace with a reviewed GLB later without changing the catalog API.

enum AssetKind { PARK_TREE, ROUTE_GATE, COURSE_BOUNDARY, LIFT_TOWER, SNOWMAKER, TRAIL_BOARD, SNOW_BOULDER }

const DEFAULT_LOD_DISTANCES := Vector3(35.0, 105.0, 230.0)

@export var asset_kind: AssetKind = AssetKind.PARK_TREE

var _built := false

func _ready() -> void:
	build_now()

func build_now() -> void:
	if _built:
		return
	_built = true
	var has_catalog_lod := has_meta("lod_distances_m")
	var lod_distances := _lod_distances()
	set_meta("lod_distances_m", lod_distances)
	set_meta("lod_source", "catalog" if has_catalog_lod else "asset_default")
	var render := Node3D.new()
	render.name = "Render"
	add_child(render)
	var lod0 := Node3D.new()
	lod0.name = "LOD0"
	render.add_child(lod0)
	var lod1 := Node3D.new()
	lod1.name = "LOD1"
	render.add_child(lod1)
	match asset_kind:
		AssetKind.PARK_TREE:
			_build_tree(lod0, lod1)
		AssetKind.ROUTE_GATE:
			_build_gate(lod0, lod1)
		AssetKind.COURSE_BOUNDARY:
			_build_boundary(lod0, lod1)
		AssetKind.LIFT_TOWER:
			_build_lift_tower(lod0, lod1)
		AssetKind.SNOWMAKER:
			_build_snowmaker(lod0, lod1)
		AssetKind.TRAIL_BOARD:
			_build_trail_board(lod0, lod1)
		AssetKind.SNOW_BOULDER:
			_build_snow_boulder(lod0, lod1)

func _build_tree(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("park_trees")
	set_meta("readability_category", "landmark")
	var variant := int(get_meta("style_variant", 0))
	var sway := sin(float(variant) * 1.73) * 0.12
	var counter_sway := cos(float(variant) * 1.21) * 0.09
	var bark := _material(Color("#59483b"), 0.9)
	var color_shift := float(variant % 4) * 0.035
	var needle_dark := _material(Color("#163f38").lightened(color_shift), 0.86)
	var needle_mid := _material(Color("#255c50").lightened(color_shift), 0.84)
	var needle_light := _material(Color("#397565").lightened(color_shift), 0.82)
	var snow_cap := _material(Color("#dcebf0"), 0.96)
	_add_cylinder(lod0, "Trunk", 0.24, 0.32, 3.0, Vector3(0.0, 1.5, 0.0), bark, 8, 0.0, 105.0)
	_add_cone(lod0, "LowerCanopy", 0.12, 1.50, 2.4, Vector3(sway, 2.5, counter_sway), needle_dark, 9, 0.0, 105.0)
	_add_cone(lod0, "LowerSnowCap", 0.05, 1.10, 0.42, Vector3(sway, 3.52, counter_sway), snow_cap, 9, 0.0, 105.0)
	_add_cone(lod0, "MiddleCanopy", 0.10, 1.18, 2.1, Vector3(-counter_sway, 3.7, sway * 0.6), needle_mid, 9, 0.0, 105.0)
	_add_cone(lod0, "MiddleSnowCap", 0.04, 0.86, 0.4, Vector3(-counter_sway, 4.59, sway * 0.6), snow_cap, 9, 0.0, 105.0)
	_add_cone(lod0, "UpperCanopy", 0.04, 0.82, 1.8, Vector3(sway * 0.45, 4.85, -counter_sway), needle_light, 8, 0.0, 105.0)
	_add_cone(lod0, "UpperSnowCap", 0.02, 0.56, 0.32, Vector3(sway * 0.45, 5.60, -counter_sway), snow_cap, 8, 0.0, 105.0)
	_add_cylinder(lod1, "TrunkLow", 0.24, 0.31, 3.0, Vector3(0.0, 1.5, 0.0), bark, 6, 82.0, 230.0)
	_add_cone(lod1, "CanopyLow", 0.05, 1.45, 4.2, Vector3(sway * 0.4, 3.7, counter_sway * 0.4), needle_mid, 7, 82.0, 230.0)
	_add_cone(lod1, "CanopySnowLow", 0.03, 0.9, 0.42, Vector3(sway * 0.4, 5.56, counter_sway * 0.4), snow_cap, 7, 82.0, 230.0)

func _build_gate(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("park_gates")
	set_meta("guidance_style", "minimal_flag_posts")
	set_meta("non_colliding", true)
	var post_material := _material(Color("#274956"), 0.72, 0.08, 0.72)
	var post_base := _material(Color("#17323c"), 0.8, 0.04, 0.82)
	var accent: Color = get_meta("accent_color", Color("#55d6be"))
	var flag_material := _material(accent.lerp(Color("#d8eef2"), 0.12), 0.8, 0.0, 0.78, true)
	var flag_stripe := _material(Color("#e8f6f5"), 0.9, 0.0, 0.76, true)
	for side: float in [-1.0, 1.0]:
		_add_box(lod0, "GatePost", Vector3(0.19, 2.15, 0.19), Vector3(side * 6.405, 1.075, 0.0), post_material, 0.0, 90.0)
		_add_box(lod0, "GatePostBase", Vector3(0.2, 0.32, 0.2), Vector3(side * 6.4, 0.16, 0.0), post_base, 0.0, 90.0)
		# Keep the fabric readable without adding a second shadow silhouette to
		# the snow. The structural posts/base still cast a near-field shadow.
		var flag := _add_quad(lod0, "RouteFlag", Vector2(1.02, 0.58), Vector3(side * 5.88, 1.68, 0.0), flag_material, 2.5, 88.0, false)
		flag.rotation_degrees.y = -8.0 * side
		flag.add_to_group("route_guide_flags")
		var stripe := _add_quad(lod0, "RouteFlagStripe", Vector2(0.78, 0.1), Vector3(side * 5.88, 1.68, 0.008), flag_stripe, 2.5, 88.0, false)
		stripe.rotation_degrees.y = -8.0 * side
		_add_box(lod1, "GatePostLow", Vector3(0.19, 2.15, 0.19), Vector3(side * 6.405, 1.075, 0.0), post_material, 72.0, 190.0)

func _build_boundary(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("course_landmarks")
	var post_material := _material(Color("#43555c"), 0.76, 0.08)
	var rail_material := _material(Color("#e0a64f"), 0.68, 0.04)
	for along: float in [-9.9, -5.0, 0.0, 5.0, 9.9]:
		_add_box(lod0, "BoundaryPost", Vector3(0.2, 1.1, 0.2), Vector3(0.0, 0.55, along), post_material, 0.0, 125.0)
		_add_box(lod0, "BoundaryReflector", Vector3(0.2, 0.16, 0.2), Vector3(0.0, 1.02, along), rail_material, 0.0, 125.0)
	for height: float in [0.36, 0.82]:
		_add_box(lod0, "BoundaryRail", Vector3(0.12, 0.12, 20.0), Vector3(0.0, height, 0.0), rail_material, 0.0, 125.0)
	var safety_fabric := _material(Color("#d9853b"), 0.88, 0.0, 0.3)
	for panel_z: float in [-7.45, -2.5, 2.5, 7.45]:
		_add_box(lod0, "BoundarySafetyPanel", Vector3(0.08, 0.38, 4.7), Vector3(0.0, 0.59, panel_z), safety_fabric, 0.0, 125.0)
	for along: float in [-9.9, 0.0, 9.9]:
		_add_box(lod1, "BoundaryPostLow", Vector3(0.2, 1.1, 0.2), Vector3(0.0, 0.55, along), post_material, 102.0, 260.0)
	_add_box(lod1, "BoundaryRailLow", Vector3(0.14, 0.16, 20.0), Vector3(0.0, 0.65, 0.0), rail_material, 102.0, 260.0)

func _build_lift_tower(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("course_landmarks")
	var metal := _material(Color("#405863"), 0.62, 0.28)
	var accent := _material(Color("#d6a14e"), 0.7, 0.06)
	for side: float in [-1.0, 1.0]:
		_add_cylinder(lod0, "TowerLeg", 0.09, 0.13, 6.3, Vector3(side * 0.82, 3.15, 0.0), metal, 7, 0.0, 150.0)
	_add_box(lod0, "TowerCrossbar", Vector3(3.2, 0.22, 0.5), Vector3(0.0, 6.05, 0.0), metal, 0.0, 150.0)
	for side: float in [-1.15, 1.15]:
		_add_cylinder(lod0, "Pulley", 0.22, 0.22, 0.18, Vector3(side, 5.83, 0.0), accent, 10, 0.0, 150.0, Vector3(90.0, 0.0, 0.0))
	_add_box(lod1, "TowerLow", Vector3(1.8, 6.3, 0.5), Vector3(0.0, 3.15, 0.0), metal, 125.0, 300.0)
	_add_box(lod1, "TowerCrossbarLow", Vector3(3.2, 0.22, 0.5), Vector3(0.0, 6.05, 0.0), accent, 125.0, 300.0)

func _build_snowmaker(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("course_landmarks")
	var frame := _material(Color("#50636b"), 0.66, 0.24)
	var barrel := _material(Color("#d98a36"), 0.5, 0.18)
	_add_box(lod0, "SnowmakerBase", Vector3(0.72, 0.2, 0.82), Vector3(0.0, 0.1, 0.0), frame, 0.0, 105.0)
	_add_box(lod0, "SnowmakerMast", Vector3(0.16, 1.35, 0.16), Vector3(0.0, 0.78, 0.0), frame, 0.0, 105.0)
	var barrel_mesh := _add_cylinder(lod0, "SnowmakerBarrel", 0.28, 0.36, 1.0, Vector3(0.0, 1.63, -0.14), barrel, 10, 0.0, 105.0, Vector3(66.0, 0.0, 0.0))
	barrel_mesh.set_meta("readability_accent", true)
	_add_box(lod1, "SnowmakerLow", Vector3(0.8, 2.0, 1.0), Vector3(0.0, 1.0, -0.08), frame, 84.0, 210.0)

func _build_trail_board(lod0: Node3D, lod1: Node3D) -> void:
	add_to_group("course_landmarks")
	var post := _material(Color("#43545a"), 0.82)
	var accent: Color = get_meta("accent_color", Color("#5d8891"))
	var board := _material(accent, 0.76)
	for side: float in [-1.0, 1.0]:
		_add_box(lod0, "BoardPost", Vector3(0.12, 1.55, 0.14), Vector3(side * 0.56, 0.775, 0.0), post, 0.0, 120.0)
	_add_box(lod0, "TrailBoardFace", Vector3(1.6, 0.65, 0.2), Vector3(0.0, 1.65, 0.0), board, 0.0, 120.0)
	_add_box(lod0, "TrailBoardStripe", Vector3(1.08, 0.11, 0.205), Vector3(0.0, 1.65, -0.002), _material(Color("#edf4ed"), 0.9), 0.0, 120.0)
	_add_box(lod1, "TrailBoardLow", Vector3(1.6, 1.98, 0.2), Vector3(0.0, 0.99, 0.0), board, 98.0, 230.0)

func _build_snow_boulder(lod0: Node3D, lod1: Node3D) -> void:
	set_meta("readability_category", "environment_rock")
	var variant := int(get_meta("style_variant", 0))
	var rock := _material(Color("#667985").lightened(float(variant % 3) * 0.035), 0.94, 0.0)
	var snow := _material(Color("#dcebf0"), 0.98)
	# Keep the authored bounds stable across style variants so the catalog's
	# nominal dimensions remain meaningful after each placement is validated.
	var width := 2.15
	var height := 1.25
	var depth := 2.15
	_add_rock(lod0, "BoulderBody", Vector3(width, height, depth), Vector3(0.0, height * 0.5, 0.0), rock, 0.0, 110.0, 8 + variant % 3)
	_add_rock(lod0, "BoulderSnow", Vector3(width * 0.64, height * 0.24, depth * 0.58), Vector3(-width * 0.08, height * 0.91, -depth * 0.06), snow, 0.0, 110.0, 7)
	_add_rock(lod1, "BoulderLow", Vector3(width * 1.04, height * 0.94, depth * 0.98), Vector3(0.0, height * 0.47, 0.0), rock, 82.0, 230.0, 7)

func _add_rock(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, begin: float, end: float, segments: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = maxi(segments, 8)
	instance.mesh = mesh
	instance.position = position
	instance.scale = size
	instance.material_override = material
	_configure_lod(instance, begin, end, true)
	parent.add_child(instance)
	return instance

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, begin: float, end: float, casts_shadow := true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	_configure_lod(instance, begin, end, casts_shadow)
	parent.add_child(instance)
	return instance

func _add_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material, segments: int, begin: float, end: float, rotation: Vector3 = Vector3.ZERO, casts_shadow := true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation
	instance.material_override = material
	_configure_lod(instance, begin, end, casts_shadow)
	parent.add_child(instance)
	return instance

func _add_cone(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material, segments: int, begin: float, end: float, casts_shadow := true) -> MeshInstance3D:
	return _add_cylinder(parent, node_name, top_radius, bottom_radius, height, position, material, segments, begin, end, Vector3.ZERO, casts_shadow)

func _add_quad(parent: Node3D, node_name: String, size: Vector2, position: Vector3, material: Material, begin: float, end: float, casts_shadow := true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Z
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	_configure_lod(instance, begin, end, casts_shadow)
	parent.add_child(instance)
	return instance

func _configure_lod(instance: GeometryInstance3D, begin: float, end: float, casts_shadow: bool) -> void:
	# Near LODs ground the prop with a real shadow; far LODs retain the cheap
	# silhouette and stop contributing duplicate shadow maps. A guide's fabric
	# can opt out while its posts remain shadow-casting.
	var catalog_lod := _lod_distances()
	var resolved_begin := begin
	var resolved_end := end
	if begin <= 0.01:
		# High-detail geometry remains visible through the catalog's middle-band
		# boundary. The overlap with the low-detail band prevents a visible hole
		# while the renderer cross-fades the two representations.
		resolved_end = catalog_lod.y
	elif begin >= 60.0:
		# Existing authored calls use a large begin value to identify their low
		# LOD. Its start and cull horizon come from the catalog, not the helper's
		# historical per-asset constants.
		resolved_begin = catalog_lod.x
		resolved_end = catalog_lod.z
	else:
		# Small non-zero ranges are intentionally authored sub-parts (for example
		# route-flag fabric). Keep their near fade but still use the catalog's
		# middle boundary as the end of the high-detail band.
		resolved_end = catalog_lod.y
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow and begin <= 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_begin = resolved_begin
	instance.visibility_range_begin_margin = 18.0 if resolved_begin > 0.0 else 0.0
	instance.visibility_range_end = resolved_end
	instance.visibility_range_end_margin = 24.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.set_meta("lod_distances_m", catalog_lod)
	instance.set_meta("lod_source", "catalog" if get_meta("lod_source", "asset_default") == "catalog" else "asset_default")
	instance.set_meta("lod_cull_start_m", resolved_begin)
	instance.set_meta("lod_cull_end_m", resolved_end)

func _lod_distances() -> Vector3:
	var value = get_meta("lod_distances_m", DEFAULT_LOD_DISTANCES)
	if value is Vector3:
		var distances := value as Vector3
		if is_finite(distances.x) and is_finite(distances.y) and is_finite(distances.z) \
			and distances.x > 0.0 and distances.x < distances.y and distances.y < distances.z:
			return distances
	return DEFAULT_LOD_DISTANCES

func _material(color: Color, roughness: float, metallic: float = 0.0, alpha: float = 1.0, double_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	material.roughness = roughness
	material.metallic = metallic
	if alpha < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
