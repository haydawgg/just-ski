extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const FEATURE := Color("#ff9f43")
const SnowSurface := preload("res://world/snow_material.gd")

var player: SkierController
var camera_rig: SkiCameraController
var environment: WorldEnvironment
var sun: DirectionalLight3D

func _ready() -> void:
	_build_environment()
	_build_resort()
	_build_player()
	GameSettings.settings_applied.connect(_apply_graphics_settings)
	_apply_graphics_settings()

func _build_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.23, 0.45, 0.72)
	sky_mat.sky_horizon_color = Color(0.82, 0.9, 0.96)
	sky_mat.sky_curve = 0.09
	sky_mat.sky_energy_multiplier = 1.15
	sky_mat.ground_bottom_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_horizon_color = Color(0.9, 0.94, 0.97)
	sky_mat.ground_curve = 0.12
	sky_mat.ground_energy_multiplier = 0.85
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.07
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.92
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.92, 0.97)
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.0032
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.45
	env.fog_height = 2.0
	env.fog_height_density = 0.055
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 0.72
	env.glow_bloom = 0.035
	env.glow_hdr_threshold = 0.85
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, -42.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.72
	sun.light_indirect_energy = 0.85
	sun.light_specular = 0.7
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)

func _build_resort() -> void:
	# One broad seamless face plus side lanes and a flat bottom hub.
	_add_box("MainSnowFace", Vector3(48.0, 1.5, 155.0), Vector3(0.0, 9.5, 0.0), Vector3(-7.8, 0.0, 0.0), SNOW, true)
	_add_box("BottomHub", Vector3(70.0, 1.5, 42.0), Vector3(0.0, -0.4, -93.0), Vector3.ZERO, SNOW, true)
	_add_box("LeftBank", Vector3(16.0, 1.5, 145.0), Vector3(-29.0, 11.0, 3.0), Vector3(-8.0, 0.0, -12.0), SNOW_SHADOW, true)
	_add_box("RightBank", Vector3(16.0, 1.5, 145.0), Vector3(29.0, 11.0, 3.0), Vector3(-8.0, 0.0, 12.0), SNOW_SHADOW, true)

	# Main jump line: three predictable blockout kickers with open landings.
	_add_kicker(Vector3(-11.0, 16.7, 44.0), 10.0, 13.0)
	_add_kicker(Vector3(-11.0, 10.8, 3.0), 13.0, 16.0)
	_add_kicker(Vector3(-11.0, 5.0, -39.0), 16.0, 18.0)

	# Technical lane: five grindable features and multiple transfers.
	_add_rail("SummitFlatBox", [Vector3(7, 17.7, 52), Vector3(7, 16.3, 42)], GrindRail3D.RailType.BOX)
	_add_rail("DownRail", [Vector3(12, 14.3, 28), Vector3(12, 12.1, 14)], GrindRail3D.RailType.RAIL)
	_add_rail("KinkRail", [Vector3(7, 10.5, 2), Vector3(7, 9.6, -5), Vector3(7, 7.9, -13)], GrindRail3D.RailType.RAIL)
	_add_rail("LongTube", [Vector3(14, 7.6, -17), Vector3(14, 5.0, -38)], GrindRail3D.RailType.PIPE)
	_add_rail("FinalBox", [Vector3(7, 3.8, -48), Vector3(7, 2.0, -63)], GrindRail3D.RailType.BOX)
	_add_rail("Rainbow", [Vector3(17, 3.6, -49), Vector3(17, 5.0, -55), Vector3(17, 1.8, -63)], GrindRail3D.RailType.RAIL)

	# Side hits / banked ramps — packed snow shader (not flat feature paint).
	_add_box("LeftSideHit", Vector3(8, 1.5, 13), Vector3(-21, 8.0, -12), Vector3(10, -18, 0), SNOW_SHADOW, true)
	_add_box("QuarterBank", Vector3(10, 2.0, 9), Vector3(21, 4.2, -42), Vector3(18, 0, -8), SNOW_SHADOW, true)
	_add_lodge(Vector3(-18, 21.0, 72))
	for z: float in [-75, -48, -18, 12, 42, 68]:
		_add_tree(Vector3(-38.0, 10.5 + z * 0.135, z))
		_add_tree(Vector3(38.0, 10.5 + z * 0.135, z + 5.0))
	_add_sign(Vector3(0, 21.2, 74), "PARK ↓   RAILS →   JUMPS ←")
	_add_sign(Vector3(0, 1.0, -87), "BASE HUB   •   PRESS R TO RETURN")
	_add_distant_ridges()

func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	# Upper main face (still on-snow); z past ~76.7 falls off the ridge.
	player.position = Vector3(0.0, 21.5, 75.0)
	player.rotation.y = 0.0
	add_child(player)
	SessionManager.set_default_spawn(player.global_transform)

	camera_rig = SkiCameraController.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	SessionManager.respawn_requested.connect(func(_value: Transform3D) -> void: camera_rig.call_deferred("reset_immediate"))

	var ui := GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.call_deferred("bind_player", player)

func _add_box(label: String, size: Vector3, position: Vector3, rotation_degrees: Vector3, color: Color, collision_enabled: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.rotation_degrees = rotation_degrees
	body.collision_layer = 1
	body.collision_mask = 2
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_color(color)
	body.add_child(mesh_instance)
	if collision_enabled:
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
	add_child(body)
	return body

func _add_kicker(position: Vector3, length: float, angle: float) -> void:
	var width := 8.5
	var bury := 0.45
	var rise := length * tan(deg_to_rad(angle))
	var hw := width * 0.5
	var hl := length * 0.5
	var points := PackedVector3Array([
		Vector3(-hw, 0.04, hl),
		Vector3(hw, 0.04, hl),
		Vector3(-hw, rise, -hl),
		Vector3(hw, rise, -hl),
		Vector3(-hw, -bury, hl),
		Vector3(hw, -bury, hl),
		Vector3(-hw, -bury, -hl),
		Vector3(hw, -bury, -hl),
	])
	var body := StaticBody3D.new()
	body.name = "Kicker"
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 2
	var shape_node := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape_node.shape = convex
	body.add_child(shape_node)
	var snow := SnowSurface.create(SnowSurface.Kind.GROOMED)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _wedge_mesh(points)
	mesh_instance.material_override = snow
	body.add_child(mesh_instance)
	add_child(body)
	_add_box("Landing", Vector3(11.0, 1.6, length * 1.85), position + Vector3(0.0, -2.15, -length * 1.42), Vector3(-12.0, 0.0, 0.0), SNOW_SHADOW, true)

func _wedge_mesh(points: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Quads listed CCW when viewed from outside so normals face outward.
	var faces := [
		[0, 2, 3, 1], # deck (rideable face)
		[4, 5, 7, 6], # bottom
		[0, 1, 5, 4], # lip / approach
		[2, 6, 7, 3], # tip / takeoff wall
		[0, 4, 6, 2], # left side
		[1, 3, 7, 5], # right side
	]
	for face: Array in faces:
		var a: Vector3 = points[int(face[0])]
		var b: Vector3 = points[int(face[1])]
		var c: Vector3 = points[int(face[2])]
		var d: Vector3 = points[int(face[3])]
		_add_wedge_tri(st, a, b, c)
		_add_wedge_tri(st, a, c, d)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _add_wedge_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if not normal.is_finite() or normal.length_squared() < 0.0001:
		normal = Vector3.UP
	for point: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.set_uv(Vector2(point.x * 0.12, point.z * 0.12))
		st.add_vertex(point)

func _add_rail(label: String, points: Array[Vector3], type: GrindRail3D.RailType) -> void:
	var rail := GrindRail3D.new()
	rail.name = label
	rail.rail_type = type
	rail.capture_radius = 1.0 if type != GrindRail3D.RailType.BOX else 1.35
	rail.path = Curve3D.new()
	for point: Vector3 in points:
		rail.path.add_point(point)
	add_child(rail)

func _add_tree(position: Vector3) -> void:
	var root := StaticBody3D.new()
	root.name = "ParkTree"
	root.position = position
	root.collision_layer = 4
	root.collision_mask = 2
	root.add_to_group("park_trees")
	var trunk_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.32
	cylinder.height = 3.4
	trunk_shape.shape = cylinder
	trunk_shape.position.y = 1.7
	root.add_child(trunk_shape)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.4
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.7
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("#594337")
	trunk.material_override = bark
	root.add_child(trunk)
	for height: float in [2.3, 3.4, 4.5]:
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.35 - height * 0.08
		cone.height = 2.4
		crown.mesh = cone
		crown.position.y = height
		var needles := StandardMaterial3D.new()
		needles.albedo_color = Color("#214b46")
		crown.material_override = needles
		root.add_child(crown)
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.95
	cap_mesh.height = 0.55
	cap.mesh = cap_mesh
	cap.position.y = 5.35
	cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER)
	root.add_child(cap)
	add_child(root)

func _add_distant_ridges() -> void:
	_add_box("NorthRidge", Vector3(220.0, 38.0, 70.0), Vector3(0.0, 28.0, 165.0), Vector3(-18.0, 0.0, 0.0), SNOW, false)
	_add_box("WestRidge", Vector3(70.0, 32.0, 180.0), Vector3(-95.0, 22.0, 10.0), Vector3(-8.0, 12.0, -16.0), SNOW_SHADOW, false)
	_add_box("EastRidge", Vector3(70.0, 30.0, 180.0), Vector3(98.0, 20.0, 8.0), Vector3(-8.0, -14.0, 14.0), SNOW_SHADOW, false)

func _material_for_color(color: Color) -> Material:
	if color.is_equal_approx(SNOW):
		return SnowSurface.create(SnowSurface.Kind.POWDER)
	if color.is_equal_approx(SNOW_SHADOW):
		return SnowSurface.create(SnowSurface.Kind.PACKED)
	if color.is_equal_approx(FEATURE):
		return SnowSurface.create(SnowSurface.Kind.GROOMED)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material

func _add_lodge(position: Vector3) -> void:
	_add_box("SummitLodge", Vector3(14, 5, 9), position, Vector3.ZERO, Color("#6f4837"), true)
	var roof := _add_box("LodgeRoof", Vector3(16, 1.2, 11), position + Vector3(0, 3.1, 0), Vector3(0, 0, 8), Color("#233849"), false)
	roof.collision_layer = 0

func _add_sign(position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 10
	label.modulate = Color("#172a3a")
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	add_child(label)

func _apply_graphics_settings() -> void:
	if environment == null or environment.environment == null:
		return
	var env := environment.environment
	env.ssao_enabled = bool(GameSettings.active.get("ssao_enabled", true))
	env.ssil_enabled = bool(GameSettings.active.get("ssil_enabled", false))
	env.ssr_enabled = bool(GameSettings.active.get("ssr_enabled", true))
	env.fog_enabled = bool(GameSettings.active.get("fog_enabled", true))
	_apply_shadow_quality(int(GameSettings.active.get("shadow_quality", 2)))

func _apply_shadow_quality(quality: int) -> void:
	if sun == null:
		return
	var level := clampi(quality, 0, 3)
	sun.shadow_enabled = true
	match level:
		0:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 120.0
			sun.shadow_bias = 0.06
			sun.shadow_normal_bias = 1.6
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 160.0
			sun.shadow_bias = 0.05
			sun.shadow_normal_bias = 1.4
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0
			sun.shadow_bias = 0.04
			sun.shadow_normal_bias = 1.2
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 280.0
			sun.shadow_bias = 0.03
			sun.shadow_normal_bias = 1.0
