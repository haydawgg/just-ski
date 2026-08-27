extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const FEATURE := Color("#ff9f43")
const SnowSurface := preload("res://world/snow_material.gd")
const ParkLayout := preload("res://world/park_features/park_layout.gd")

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
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)

func _build_resort() -> void:
	var face_len := ParkLayout.FACE_SLOPE_LENGTH
	ParkLayout.add_slope_box(self, "MainSnowFace", 0.0, 0.0, Vector3(ParkLayout.FACE_WIDTH, ParkLayout.FACE_THICKNESS, face_len), 0.0, SNOW, true)
	_add_box("BottomHub", Vector3(80.0, 1.5, 52.0), Vector3(0.0, 2.4, -165.0), Vector3.ZERO, SNOW, true)
	ParkLayout.add_slope_box(self, "LeftBank", -36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), -10.0, SNOW_SHADOW, true)
	ParkLayout.add_slope_box(self, "RightBank", 36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), 10.0, SNOW_SHADOW, true)
	_build_jump_line()
	_build_rail_line()
	_build_transfers()
	var lodge_pos := ParkLayout.snow_at(-18.0, 145.0) + Vector3(0.0, 2.6, 0.0)
	_add_lodge(lodge_pos)
	for z: float in [130.0, 95.0, 55.0, 15.0, -25.0, -70.0, -115.0]:
		_add_tree(ParkLayout.snow_at(-40.0, z))
		_add_tree(ParkLayout.snow_at(40.0, z + 6.0))
	_add_sign(ParkLayout.snow_at(0.0, 142.0) + Vector3(0.0, 1.2, 0.0), "PARK ↓   RAILS →   JUMPS ←")
	_add_sign(Vector3(0.0, 4.2, -158.0), "BASE HUB   •   PRESS R TO RETURN")
	_add_distant_ridges()

func _build_jump_line() -> void:
	ParkLayout.add_tabletop(self, "SmallTable", -12.0, 110.0, 14.0, 7.0)
	ParkLayout.add_roller(self, "UpperRoller", -12.0, 82.0, 8.0, 0.8)
	ParkLayout.add_tabletop(self, "MediumTable", -12.0, 52.0, 18.0, 9.0)
	ParkLayout.add_hip(self, "HipTransfer", -12.0, 12.0, 16.0, 8.0, 28.0)
	ParkLayout.add_tabletop(self, "LargeTable", -12.0, -32.0, 22.0, 11.0)
	ParkLayout.add_tabletop(self, "StepDownTable", -12.0, -88.0, 18.0, 8.0, 8.5, 3.0)

func _build_rail_line() -> void:
	ParkLayout.add_rail(self, "SummitFlatBox", [ParkLayout.rail_point(10.0, 124.0, 0.22), ParkLayout.rail_point(10.0, 110.0, 0.22)], GrindRail3D.RailType.BOX, 1.35, 1.15)
	ParkLayout.add_rail(self, "DownRail", [ParkLayout.rail_point(14.0, 98.0, 0.16), ParkLayout.rail_point(14.0, 80.0, 0.16)], GrindRail3D.RailType.RAIL, 1.0, 0.55)
	ParkLayout.add_rail(self, "KinkRail", [ParkLayout.rail_point(10.0, 68.0, 0.16), ParkLayout.rail_point(10.0, 58.0, 0.16), ParkLayout.rail_point(15.0, 46.0, 0.16)], GrindRail3D.RailType.RAIL, 1.0, 0.7)
	var dfd_start := ParkLayout.rail_point(10.0, 40.0, 0.22)
	var dfd_end := ParkLayout.rail_point(10.0, 16.0, 0.22)
	var dfd_flat := dfd_start.lerp(dfd_end, 0.5)
	dfd_flat.y = dfd_start.y - 0.9
	ParkLayout.add_rail(self, "DFDBox", [dfd_start, dfd_flat, dfd_end], GrindRail3D.RailType.BOX, 1.35, 1.05)
	ParkLayout.add_rail(self, "LongTube", [ParkLayout.rail_point(18.0, 8.0, 0.14), ParkLayout.rail_point(18.0, -18.0, 0.14)], GrindRail3D.RailType.PIPE, 0.9, 0.45)
	ParkLayout.add_rail(self, "SRail", [ParkLayout.rail_point(16.0, -24.0, 0.16), ParkLayout.rail_point(9.0, -36.0, 0.16), ParkLayout.rail_point(16.0, -48.0, 0.16)], GrindRail3D.RailType.RAIL, 1.0, 0.7)
	var rainbow_crest := ParkLayout.snow_at(16.0, -58.0) + ParkLayout.snow_normal() * 0.18 + Vector3(0.0, 3.2, 0.0)
	ParkLayout.add_rail(self, "Rainbow", [ParkLayout.rail_point(16.0, -50.0, 0.16), rainbow_crest, ParkLayout.rail_point(16.0, -70.0, 0.16)], GrindRail3D.RailType.RAIL, 1.0, 0.6)
	ParkLayout.add_rail(self, "TransferBox", [ParkLayout.rail_point(14.0, 4.0, 0.22), ParkLayout.rail_point(2.0, -22.0, 0.22)], GrindRail3D.RailType.BOX, 1.35, 0.95)
	ParkLayout.add_rail(self, "FinalBox", [ParkLayout.rail_point(8.0, -96.0, 0.22), ParkLayout.rail_point(8.0, -118.0, 0.22)], GrindRail3D.RailType.BOX, 1.35, 1.1)

func _build_transfers() -> void:
	ParkLayout.add_slope_box(self, "SpineBank", 0.0, 38.0, Vector3(14.0, 2.0, 16.0), -16.0, SNOW_SHADOW, true, 0.35)
	ParkLayout.add_slope_box(self, "QuarterBank", 21.0, -72.0, Vector3(12.0, 2.2, 14.0), -32.0, SNOW_SHADOW, true, 0.45)
	ParkLayout.add_roller(self, "MidRoller", 0.0, -8.0, 9.0, 0.7, 12.0)

func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	player.position = ParkLayout.spawn_position()
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
	_add_box("NorthRidge", Vector3(280.0, 48.0, 90.0), Vector3(0.0, 42.0, 210.0), Vector3(-18.0, 0.0, 0.0), SNOW, false)
	_add_box("WestRidge", Vector3(80.0, 40.0, 280.0), Vector3(-110.0, 30.0, 10.0), Vector3(-8.0, 12.0, -16.0), SNOW_SHADOW, false)
	_add_box("EastRidge", Vector3(80.0, 38.0, 280.0), Vector3(112.0, 28.0, 8.0), Vector3(-8.0, -14.0, 14.0), SNOW_SHADOW, false)

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
			sun.directional_shadow_max_distance = 180.0
			sun.shadow_bias = 0.06
			sun.shadow_normal_bias = 1.6
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 240.0
			sun.shadow_bias = 0.05
			sun.shadow_normal_bias = 1.4
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 320.0
			sun.shadow_bias = 0.04
			sun.shadow_normal_bias = 1.2
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 400.0
			sun.shadow_bias = 0.03
			sun.shadow_normal_bias = 1.0
