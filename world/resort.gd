extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const FEATURE := Color("#ff9f43")

var player: SkierController
var camera_rig: SkiCameraController
var environment: WorldEnvironment

func _ready() -> void:
	_build_environment()
	_build_resort()
	_build_player()
	GameSettings.settings_applied.connect(_apply_graphics_settings)
	_apply_graphics_settings()

func _build_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#84bde3")
	env.background_energy_multiplier = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a8c8df")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#d8e8f2")
	env.fog_density = 0.0045
	env.fog_height = 4.0
	env.fog_height_density = 0.08
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#fff3df")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
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

	# Side hits, banks, landmarks, and readable boundary trees.
	_add_box("LeftSideHit", Vector3(8, 1.5, 13), Vector3(-21, 8.0, -12), Vector3(10, -18, 0), FEATURE, true)
	_add_box("QuarterBank", Vector3(10, 2.0, 9), Vector3(21, 4.2, -42), Vector3(18, 0, -8), FEATURE, true)
	_add_lodge(Vector3(-18, 21.0, 72))
	for z: float in [-75, -48, -18, 12, 42, 68]:
		_add_tree(Vector3(-38.0, 10.5 + z * 0.135, z))
		_add_tree(Vector3(38.0, 10.5 + z * 0.135, z + 5.0))
	_add_sign(Vector3(0, 20.0, 66), "PARK ↓   RAILS →   JUMPS ←")
	_add_sign(Vector3(0, 1.0, -87), "BASE HUB   •   PRESS R TO RETURN")

func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	player.position = Vector3(0.0, 20.4, 67.0)
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
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.84 if color == SNOW else 0.5
	mesh_instance.material_override = material
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
	_add_box("Kicker", Vector3(8.5, 1.2, length), position, Vector3(angle, 0, 0), FEATURE, true)
	_add_box("Landing", Vector3(11.0, 1.3, length * 1.7), position + Vector3(0, -2.0, -length * 1.55), Vector3(-12.0, 0, 0), SNOW_SHADOW, true)

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
	var root := Node3D.new()
	root.position = position
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
	add_child(root)

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
