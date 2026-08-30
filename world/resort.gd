extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const SnowSurface := preload("res://world/snow_material.gd")
const ParkLayout := preload("res://world/park_features/park_layout.gd")
const ParkCourseBuilderModule := preload("res://world/course/park_course_builder.gd")
const CourseRecoveryModule := preload("res://world/course/course_recovery.gd")

@export var course_profile: ParkCourseProfile = preload("res://resources/course/default_course_profile.tres")
@export var physics_profile: SkiPhysicsProfile = preload("res://resources/physics/default_ski_profile.tres")
@export var environment_profile: ResortEnvironmentProfile = preload("res://resources/environment/default_resort_environment_profile.tres")

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
	var profile := environment_profile
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = profile.sky_top_color
	sky_mat.sky_horizon_color = profile.sky_horizon_color
	sky_mat.sky_curve = profile.sky_curve
	sky_mat.sky_energy_multiplier = profile.sky_energy
	sky_mat.ground_bottom_color = profile.ground_bottom_color
	sky_mat.ground_horizon_color = profile.ground_horizon_color
	sky_mat.ground_curve = profile.ground_curve
	sky_mat.ground_energy_multiplier = profile.ground_energy
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.07
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = profile.ambient_sky_contribution
	env.ambient_light_energy = profile.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = profile.exposure
	env.tonemap_white = profile.white_point
	env.adjustment_enabled = true
	env.adjustment_brightness = profile.brightness
	env.adjustment_contrast = profile.contrast
	env.adjustment_saturation = profile.saturation
	env.fog_enabled = true
	env.fog_light_color = profile.fog_color
	env.fog_sun_scatter = profile.fog_sun_scatter
	env.fog_density = profile.fog_density
	env.fog_aerial_perspective = profile.fog_aerial_perspective
	env.fog_sky_affect = profile.fog_sky_affect
	env.fog_height = profile.fog_height
	env.fog_height_density = profile.fog_height_density
	env.glow_enabled = true
	env.glow_intensity = profile.glow_intensity
	env.glow_strength = profile.glow_strength
	env.glow_bloom = profile.glow_bloom
	env.glow_hdr_threshold = profile.glow_hdr_threshold
	env.ssao_radius = profile.ssao_radius
	env.ssao_intensity = profile.ssao_intensity
	env.ssao_power = profile.ssao_power
	env.ssao_detail = profile.ssao_detail
	env.ssao_horizon = profile.ssao_horizon
	env.ssao_light_affect = profile.ssao_light_affect
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = profile.sun_rotation_degrees
	sun.light_color = profile.sun_color
	sun.light_energy = profile.sun_energy
	sun.light_indirect_energy = profile.sun_indirect_energy
	sun.light_specular = profile.sun_specular
	sun.shadow_opacity = profile.shadow_opacity
	sun.shadow_blur = profile.shadow_blur
	sun.light_angular_distance = profile.sun_angular_distance
	sun.shadow_enabled = true
	sun.shadow_bias = 0.028
	sun.shadow_normal_bias = 0.82
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = profile.shadow_fade_start
	add_child(sun)

func _build_resort() -> void:
	var face_len := ParkLayout.FACE_SLOPE_LENGTH
	ParkLayout.add_slope_box(self, "MainSnowFace", 0.0, 0.0, Vector3(ParkLayout.FACE_WIDTH, ParkLayout.FACE_THICKNESS, face_len), 0.0, SNOW, SnowSurface.Kind.POWDER, true, 0.0, SnowSurface.Kind.GROOMED)
	_add_box("BottomHub", Vector3(92.0, 1.5, 92.0), Vector3(0.0, 2.4, -181.0), Vector3.ZERO, SNOW, true, SnowSurface.Kind.POWDER, SnowSurface.Kind.PACKED)
	ParkLayout.add_slope_box(self, "LeftBank", -36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), -10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	ParkLayout.add_slope_box(self, "RightBank", 36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), 10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	course_features = ParkCourseBuilderModule.build(self, course_profile, physics_profile)
	var lodge_pos := ParkLayout.snow_at(-18.0, 145.0) + Vector3(0.0, 2.6, 0.0)
	_add_lodge(lodge_pos)
	_add_tree_clusters()
	_add_course_dressing()
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
	player.scoring.run_finished.connect(_on_run_finished_recorder)
	SessionManager.respawn_requested.connect(_on_respawn_requested_recorder)

func _on_run_finished_recorder(_snapshot: Dictionary) -> void:
	ClipRecorder.end_run_capture()

func _on_respawn_requested_recorder(transform: Transform3D) -> void:
	if transform == SessionManager.default_spawn:
		# Fresh run from the summit: start the armed clip capture.
		if ClipRecorder.armed:
			ClipRecorder.begin_run_capture()
	elif ClipRecorder.is_recording():
		# Mid-run interruption (marker respawn, course recovery): save what was captured.
		ClipRecorder.end_run_capture()

func _add_box(label: String, size: Vector3, position: Vector3, rotation_degrees: Vector3, color: Color, collision_enabled: bool, surface_kind: int = -1, visual_surface_kind: int = -1) -> StaticBody3D:
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
	mesh_instance.material_override = _material_for_surface(color, surface_kind, visual_surface_kind)
	body.add_child(mesh_instance)
	if collision_enabled:
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
	add_child(body)
	return body

func _add_tree(position: Vector3, scale_multiplier: float = 1.0, yaw_degrees: float = 0.0, variant: int = 0) -> void:
	var root := StaticBody3D.new()
	root.name = "ParkTree"
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	root.scale = Vector3.ONE * scale_multiplier
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
	trunk.visibility_range_end = 245.0
	trunk.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("#594337")
	trunk.material_override = bark
	root.add_child(trunk)
	var tier_heights := PackedFloat32Array([2.2, 3.25, 4.35])
	if variant % 3 == 1:
		tier_heights = PackedFloat32Array([2.0, 3.0, 4.15, 4.9])
	elif variant % 3 == 2:
		tier_heights = PackedFloat32Array([2.45, 3.65, 4.6])
	for tier_index: int in range(tier_heights.size()):
		var height := tier_heights[tier_index]
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = maxf(0.62, 1.52 - height * 0.12 + float(variant % 2) * 0.08)
		cone.height = 2.15 + float((tier_index + variant) % 2) * 0.32
		cone.radial_segments = 7 if variant % 2 == 0 else 6
		crown.mesh = cone
		crown.position = Vector3(sin(float(tier_index + variant)) * 0.08, height, cos(float(tier_index * 2 + variant)) * 0.06)
		crown.visibility_range_end = 245.0
		crown.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var needles := StandardMaterial3D.new()
		needles.albedo_color = Color("#214b46")
		crown.material_override = needles
		root.add_child(crown)
	if variant % 3 != 2:
		var cap := MeshInstance3D.new()
		var cap_mesh := SphereMesh.new()
		cap_mesh.radius = 0.72 + float(variant % 2) * 0.12
		cap_mesh.height = 0.38 + float(variant % 2) * 0.11
		cap.mesh = cap_mesh
		cap.position = Vector3(0.1 * float(variant % 2), tier_heights[-1] + 0.78, -0.06)
		cap.scale = Vector3(1.15, 0.72, 0.88 + float(variant % 2) * 0.2)
		cap.visibility_range_end = 245.0
		cap.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER)
		root.add_child(cap)
	add_child(root)

func _add_tree_clusters() -> void:
	# Deterministic clusters leave deliberate openings between vegetation masses.
	var tree_specs: Array[Vector4] = [
		Vector4(-43.0, 139.0, 1.18, -12.0), Vector4(-47.0, 134.0, 0.82, 34.0), Vector4(-41.5, 128.0, 1.04, 8.0),
		Vector4(43.5, 121.0, 0.94, -28.0), Vector4(48.0, 116.0, 1.25, 11.0), Vector4(42.0, 110.0, 0.76, 42.0), Vector4(51.0, 107.0, 0.9, -5.0),
		Vector4(-44.0, 88.0, 1.3, 19.0), Vector4(-50.0, 82.0, 0.88, -31.0), Vector4(-42.0, 76.0, 1.02, 7.0),
		Vector4(44.0, 60.0, 0.82, 23.0), Vector4(49.0, 54.0, 1.12, -18.0), Vector4(42.5, 47.0, 1.34, 36.0),
		Vector4(-45.0, 27.0, 0.9, -22.0), Vector4(-51.0, 18.0, 1.22, 14.0), Vector4(-43.0, 10.0, 0.74, 41.0), Vector4(-49.0, 4.0, 1.0, -9.0),
		Vector4(43.0, -20.0, 1.18, 28.0), Vector4(49.0, -27.0, 0.8, -14.0), Vector4(45.0, -35.0, 0.96, 7.0),
		Vector4(-43.0, -57.0, 0.78, 31.0), Vector4(-48.0, -64.0, 1.28, -26.0), Vector4(-41.5, -72.0, 1.04, 12.0),
		Vector4(44.0, -91.0, 0.86, -35.0), Vector4(51.0, -99.0, 1.2, 17.0), Vector4(43.0, -107.0, 0.96, 38.0), Vector4(48.0, -114.0, 0.72, -8.0),
		Vector4(-44.0, -130.0, 1.22, 25.0), Vector4(-51.0, -138.0, 0.9, -17.0), Vector4(-42.0, -145.0, 1.05, 6.0),
	]
	for index: int in range(tree_specs.size()):
		var spec := tree_specs[index]
		_add_tree(ParkLayout.snow_at(spec.x, spec.y), spec.z, spec.w, index % 3)

func _add_distant_ridges() -> void:
	# Layered low-poly peaks give the downhill view a destination and a useful
	# sense of scale without adding collision or expensive terrain geometry.
	_add_mountain_peak("HazePeakWest", Vector3(-245.0, 2.0, -520.0), 128.0, 105.0, Color("#9aafbd"), -8.0, 101)
	_add_mountain_peak("HazePeakCenter", Vector3(0.0, -4.0, -565.0), 155.0, 126.0, Color("#a3b5c0"), 4.0, 203)
	_add_mountain_peak("HazePeakEast", Vector3(242.0, 1.0, -510.0), 135.0, 112.0, Color("#96abb9"), 13.0, 307)
	_add_mountain_peak("FarPeakWest", Vector3(-165.0, 13.0, -310.0), 88.0, 118.0, Color("#6887a0"), -11.0, 11)
	_add_mountain_peak("FarPeakMidWest", Vector3(-72.0, 4.0, -356.0), 62.0, 87.0, Color("#7897ad"), 17.0, 29)
	_add_mountain_peak("FarPeakCenter", Vector3(19.0, 2.0, -392.0), 83.0, 116.0, Color("#6f8fa8"), 2.0, 43)
	_add_mountain_peak("FarPeakMidEast", Vector3(101.0, 5.0, -348.0), 71.0, 91.0, Color("#7897ad"), -18.0, 67)
	_add_mountain_peak("FarPeakEast", Vector3(181.0, 14.0, -298.0), 92.0, 124.0, Color("#66859e"), 9.0, 83)
	_add_mountain_peak("WestShoulder", Vector3(-138.0, 22.0, -88.0), 52.0, 68.0, Color("#718fa5"), 24.0, 127)
	_add_mountain_peak("EastShoulder", Vector3(141.0, 20.0, -76.0), 47.0, 79.0, Color("#6b899f"), -21.0, 149)

func _add_mountain_peak(label: String, position: Vector3, radius: float, height: float, color: Color, yaw_degrees: float, seed: int) -> void:
	var root := Node3D.new()
	root.name = label
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	var mountain := MeshInstance3D.new()
	mountain.mesh = _create_mountain_mesh(radius, height, seed)
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = color.lightened(0.08)
	rock_material.roughness = 0.96
	rock_material.metallic = 0.0
	mountain.material_override = rock_material
	root.add_child(mountain)
	var cap := MeshInstance3D.new()
	cap.mesh = _create_mountain_mesh(radius * 0.46, height * 0.38, seed + 997)
	cap.position.y = height * 0.33
	cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER)
	root.add_child(cap)
	add_child(root)

func _create_mountain_mesh(radius: float, height: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var segments := 7 + seed % 3
	var ring_heights := [0.0, height * 0.38, height * 0.72, height]
	var ring_scales := [1.0, 0.72, 0.34, 0.035]
	var ring_points: Array[PackedVector3Array] = []
	var peak_offset := Vector2(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.12, 0.12)) * radius
	for ring_index: int in range(ring_heights.size()):
		var points := PackedVector3Array()
		var center_offset := peak_offset * (float(ring_index) / float(ring_heights.size() - 1))
		for segment: int in range(segments):
			var angle := TAU * float(segment) / float(segments)
			var irregularity := rng.randf_range(0.78, 1.18)
			var ring_radius := radius * float(ring_scales[ring_index]) * irregularity
			points.append(Vector3(cos(angle) * ring_radius + center_offset.x, float(ring_heights[ring_index]), sin(angle) * ring_radius + center_offset.y))
		ring_points.append(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index: int in range(ring_points.size() - 1):
		for segment: int in range(segments):
			var next := (segment + 1) % segments
			var a := ring_points[ring_index][segment]
			var b := ring_points[ring_index][next]
			var c := ring_points[ring_index + 1][next]
			var d := ring_points[ring_index + 1][segment]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	st.generate_normals()
	return st.commit()

func _add_course_dressing() -> void:
	# Sparse edge landmarks add scale and resort context without narrowing the
	# playable face or competing with feature silhouettes.
	_add_boundary_fence(ParkLayout.snow_at(-47.0, 113.0), 18.0, -5.0)
	_add_boundary_fence(ParkLayout.snow_at(47.0, 35.0), 22.0, 6.0)
	_add_boundary_fence(ParkLayout.snow_at(-48.0, -84.0), 20.0, -7.0)
	_add_boundary_fence(ParkLayout.snow_at(47.0, -132.0), 15.0, 4.0)
	_add_snowmaker(ParkLayout.snow_at(43.0, 91.0), -18.0)
	_add_snowmaker(ParkLayout.snow_at(-44.0, -20.0), 22.0)
	_add_snowmaker(ParkLayout.snow_at(45.0, -75.0), -12.0)
	_add_trail_board(ParkLayout.snow_at(-42.0, 119.0), Color("#5d8891"))
	_add_trail_board(ParkLayout.snow_at(42.0, -47.0), Color("#c08a55"))

func _add_boundary_fence(position: Vector3, length: float, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "BoundaryFence"
	root.add_to_group("course_landmarks")
	root.transform = Transform3D(ParkLayout.downhill_basis(yaw_degrees), position + ParkLayout.snow_normal() * 0.03)
	var material := _simple_material(Color("#55666b"), 0.9)
	for along: float in [-length * 0.5, -length * 0.25, 0.0, length * 0.25, length * 0.5]:
		_add_visual_box(root, Vector3(0.11, 1.05, 0.11), Vector3(0.0, 0.52, along), material)
	for height: float in [0.34, 0.78]:
		_add_visual_box(root, Vector3(0.075, 0.075, length), Vector3(0.0, height, 0.0), material)
	add_child(root)

func _add_snowmaker(position: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Snowmaker"
	root.add_to_group("course_landmarks")
	root.transform = Transform3D(ParkLayout.downhill_basis(yaw_degrees), position + ParkLayout.snow_normal() * 0.04)
	var metal := _simple_material(Color("#63747b"), 0.64)
	var accent := _simple_material(Color("#9b6d48"), 0.78)
	_add_visual_box(root, Vector3(0.55, 0.16, 0.62), Vector3(0.0, 0.08, 0.0), metal)
	_add_visual_box(root, Vector3(0.13, 1.35, 0.13), Vector3(0.0, 0.74, 0.0), metal)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.22
	barrel_mesh.bottom_radius = 0.31
	barrel_mesh.height = 1.05
	barrel_mesh.radial_segments = 10
	barrel.mesh = barrel_mesh
	barrel.position = Vector3(0.0, 1.45, -0.18)
	barrel.rotation_degrees.x = 66.0
	barrel.material_override = accent
	root.add_child(barrel)
	add_child(root)

func _add_trail_board(position: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = "TrailBoard"
	root.add_to_group("course_landmarks")
	root.transform = Transform3D(ParkLayout.downhill_basis(), position + ParkLayout.snow_normal() * 0.03)
	var post_material := _simple_material(Color("#48575b"), 0.88)
	var board_material := _simple_material(color, 0.82)
	_add_visual_box(root, Vector3(0.1, 1.4, 0.1), Vector3(-0.55, 0.7, 0.0), post_material)
	_add_visual_box(root, Vector3(0.1, 1.4, 0.1), Vector3(0.55, 0.7, 0.0), post_material)
	_add_visual_box(root, Vector3(1.5, 0.58, 0.1), Vector3(0.0, 1.28, 0.0), board_material)
	add_child(root)

func _add_visual_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 230.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(instance)

func _simple_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material

func _material_for_surface(color: Color, surface_kind: int, visual_surface_kind: int = -1) -> Material:
	var material_kind := visual_surface_kind if visual_surface_kind >= 0 else surface_kind
	if material_kind >= 0:
		return SnowSurface.create(material_kind)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material

func _add_lodge(position: Vector3) -> void:
	_add_box("SummitLodge", Vector3(14, 5, 9), position, Vector3.ZERO, Color("#6f4837"), true)
	var roof := _add_box("LodgeRoof", Vector3(16, 1.2, 11), position + Vector3(0, 3.1, 0), Vector3(0, 0, 8), Color("#233849"), false)
	roof.collision_layer = 0

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
