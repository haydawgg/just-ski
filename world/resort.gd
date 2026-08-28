extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const SnowSurface := preload("res://world/snow_material.gd")
const ParkLayout := preload("res://world/park_features/park_layout.gd")
const ParkCourseBuilderModule := preload("res://world/course/park_course_builder.gd")
const CourseRecoveryModule := preload("res://world/course/course_recovery.gd")

@export var course_profile: ParkCourseProfile = preload("res://resources/course/default_course_profile.tres")
@export var physics_profile: SkiPhysicsProfile = preload("res://resources/physics/default_ski_profile.tres")

var player: SkierController
var camera_rig: SkiCameraController
var environment: WorldEnvironment
var sun: DirectionalLight3D
var course_features: Dictionary = {}
var course_recovery: CourseRecovery
var finish_trigger: Area3D

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
	ParkLayout.add_slope_box(self, "MainSnowFace", 0.0, 0.0, Vector3(ParkLayout.FACE_WIDTH, ParkLayout.FACE_THICKNESS, face_len), 0.0, SNOW, SnowSurface.Kind.POWDER, true)
	_add_box("BottomHub", Vector3(92.0, 1.5, 92.0), Vector3(0.0, 2.4, -181.0), Vector3.ZERO, SNOW, true, SnowSurface.Kind.POWDER)
	ParkLayout.add_slope_box(self, "LeftBank", -36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), -10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	ParkLayout.add_slope_box(self, "RightBank", 36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), 10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	course_features = ParkCourseBuilderModule.build(self, course_profile, physics_profile)
	var lodge_pos := ParkLayout.snow_at(-18.0, 145.0) + Vector3(0.0, 2.6, 0.0)
	_add_lodge(lodge_pos)
	for z: float in [142.0, 126.0, 106.0, 88.0, 68.0, 48.0, 26.0, 4.0, -18.0, -42.0, -66.0, -92.0, -118.0, -145.0]:
		_add_tree(ParkLayout.snow_at(-40.0, z))
		_add_tree(ParkLayout.snow_at(40.0, z + 6.0))
	_add_sign(ParkLayout.snow_at(-12.0, 133.0) + Vector3(0.0, 1.55, 0.0), "AIR LINE", Color("#4cc9f0"))
	_add_sign(ParkLayout.snow_at(0.0, 133.0) + Vector3(0.0, 1.55, 0.0), "FLOW LINE", Color("#55d6be"))
	_add_sign(ParkLayout.snow_at(12.0, 133.0) + Vector3(0.0, 1.55, 0.0), "JIB LINE", Color("#ffc857"))
	_add_sign(ParkLayout.snow_at(0.0, 74.0) + Vector3(0.0, 2.0, 0.0), "UPPER PARK")
	_add_sign(ParkLayout.snow_at(0.0, 18.0) + Vector3(0.0, 2.0, 0.0), "TRANSFER ZONE")
	_add_sign(ParkLayout.snow_at(0.0, -76.0) + Vector3(0.0, 2.0, 0.0), "FINAL FEATURES")
	_add_sign(ParkLayout.snow_at(0.0, -151.0) + ParkLayout.snow_normal() * 6.2, "FINISH", Color("#ff9f1c"))
	_add_sign(Vector3(0.0, 4.2, -166.0), "BASE HUB")
	_add_distant_ridges()

func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	player.profile = physics_profile
	player.position = ParkLayout.spawn_position()
	player.basis = ParkLayout.downhill_basis()
	add_child(player)
	SessionManager.set_default_spawn(player.global_transform)
	course_recovery = CourseRecoveryModule.new()
	course_recovery.name = "CourseRecovery"
	add_child(course_recovery)
	course_recovery.set_target(player)

	camera_rig = SkiCameraController.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	SessionManager.respawn_requested.connect(func(_value: Transform3D) -> void: camera_rig.call_deferred("reset_immediate"))

	var ui := GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.call_deferred("bind_player", player)
	ui.call_deferred("bind_camera", camera_rig)
	course_recovery.recovery_started.connect(ui.notify_course_recovery)
	_build_finish_trigger()

func _build_finish_trigger() -> void:
	finish_trigger = Area3D.new()
	finish_trigger.name = "FinishTrigger"
	finish_trigger.collision_layer = 0
	finish_trigger.collision_mask = 2
	finish_trigger.monitoring = true
	finish_trigger.position = ParkLayout.snow_at(0.0, -155.0) + ParkLayout.snow_normal() * 1.5
	finish_trigger.basis = ParkLayout.downhill_basis()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ParkLayout.FACE_WIDTH - 2.0, 5.0, 6.0)
	shape_node.shape = shape
	finish_trigger.add_child(shape_node)
	add_child(finish_trigger)
	finish_trigger.body_entered.connect(func(body: Node3D) -> void:
		if body == player and player.scoring != null:
			player.scoring.finish_run()
	)

func _add_box(label: String, size: Vector3, position: Vector3, rotation_degrees: Vector3, color: Color, collision_enabled: bool, surface_kind: int = -1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.rotation_degrees = rotation_degrees
	body.collision_layer = 1 if surface_kind >= 0 else 4
	body.collision_mask = 2
	if surface_kind >= 0:
		body.set_meta("ski_surface_kind", surface_kind)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for_surface(color, surface_kind)
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
	# Layered low-poly peaks give the downhill view a destination and a useful
	# sense of scale without adding collision or expensive terrain geometry.
	_add_mountain_peak("FarPeakWest", Vector3(-150.0, 13.0, -300.0), 82.0, 112.0, Color("#6887a0"), -11.0)
	_add_mountain_peak("FarPeakMidWest", Vector3(-67.0, 4.0, -342.0), 65.0, 92.0, Color("#7897ad"), 17.0)
	_add_mountain_peak("FarPeakCenter", Vector3(13.0, 2.0, -375.0), 78.0, 108.0, Color("#6f8fa8"), 2.0)
	_add_mountain_peak("FarPeakMidEast", Vector3(85.0, 5.0, -340.0), 68.0, 96.0, Color("#7897ad"), -18.0)
	_add_mountain_peak("FarPeakEast", Vector3(158.0, 14.0, -292.0), 86.0, 118.0, Color("#66859e"), 9.0)
	_add_mountain_peak("WestShoulder", Vector3(-125.0, 22.0, -80.0), 48.0, 72.0, Color("#718fa5"), 24.0)
	_add_mountain_peak("EastShoulder", Vector3(128.0, 20.0, -70.0), 50.0, 75.0, Color("#6b899f"), -21.0)

func _add_mountain_peak(label: String, position: Vector3, radius: float, height: float, color: Color, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = label
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	var mountain := MeshInstance3D.new()
	var mountain_mesh := CylinderMesh.new()
	mountain_mesh.top_radius = 0.0
	mountain_mesh.bottom_radius = radius
	mountain_mesh.height = height
	mountain_mesh.radial_segments = 5
	mountain_mesh.rings = 1
	mountain.mesh = mountain_mesh
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = color
	rock_material.roughness = 0.96
	mountain.material_override = rock_material
	root.add_child(mountain)
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.0
	cap_mesh.bottom_radius = radius * 0.42
	cap_mesh.height = height * 0.43
	cap_mesh.radial_segments = 5
	cap_mesh.rings = 1
	cap.mesh = cap_mesh
	cap.position.y = height * 0.285
	cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER)
	root.add_child(cap)
	add_child(root)

func _material_for_surface(color: Color, surface_kind: int) -> Material:
	if surface_kind >= 0:
		return SnowSurface.create(surface_kind)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material

func _add_lodge(position: Vector3) -> void:
	_add_box("SummitLodge", Vector3(14, 5, 9), position, Vector3.ZERO, Color("#6f4837"), true)
	var roof := _add_box("LodgeRoof", Vector3(16, 1.2, 11), position + Vector3(0, 3.1, 0), Vector3(0, 0, 8), Color("#233849"), false)
	roof.collision_layer = 0

func _add_sign(position: Vector3, text: String, color: Color = Color("#172a3a")) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 8
	label.modulate = color
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = false
	label.pixel_size = 0.0065
	label.no_depth_test = false
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
