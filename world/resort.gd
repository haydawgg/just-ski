extends Node3D

const SNOW := Color("#dcecf5")
const SNOW_SHADOW := Color("#a9c7d8")
const SnowSurface := preload("res://world/snow_material.gd")
const ParkLayout := preload("res://world/park_features/park_layout.gd")
const ParkCourseBuilderModule := preload("res://world/course/park_course_builder.gd")
const CourseRecoveryModule := preload("res://world/course/course_recovery.gd")
const SummitEnvironmentBuilderModule := preload("res://world/summit_environment_builder.gd")
const ParkTreeBatchModule := preload("res://world/environment/park_tree_batch.gd")
const EnvironmentAssetDefinition := preload("res://resources/environment/environment_asset_definition.gd")
const EnvironmentAssetCatalog := preload("res://resources/environment/environment_asset_catalog.gd")
const DISTANT_MOUNTAIN_SHADER: Shader = preload("res://shaders/distant_mountain.gdshader")
const DAY_ENVIRONMENT_PROFILE: ResortEnvironmentProfile = preload("res://resources/environment/default_resort_environment_profile.tres")
const GOLDEN_HOUR_ENVIRONMENT_PROFILE: ResortEnvironmentProfile = preload("res://resources/environment/golden_hour_resort_environment_profile.tres")
const SUNSET_ENVIRONMENT_PROFILE: ResortEnvironmentProfile = preload("res://resources/environment/sunset_resort_environment_profile.tres")
const SESSION_YARD_PROFILE: SessionYardCourseProfile = preload("res://resources/course/session_yard_course_profile.tres")

@export var course_profile: ParkCourseProfile = preload("res://resources/course/default_course_profile.tres")
@export var physics_profile: SkiPhysicsProfile = preload("res://resources/physics/default_ski_profile.tres")
@export var environment_profile: ResortEnvironmentProfile = DAY_ENVIRONMENT_PROFILE
@export var follow_environment_setting := true
@export var environment_asset_catalog: EnvironmentAssetCatalog = preload("res://resources/environment/default_environment_asset_catalog.tres")
@export var summit_environment_profile: SummitEnvironmentProfile = preload("res://resources/environment/default_summit_environment_profile.tres")
@export var force_production_assets := false

var player: SkierController
var tree_batch: Node3D
var camera_rig: SkiCameraController
var environment: WorldEnvironment
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var high_haze: MeshInstance3D
var player_probe: ReflectionProbe
var course_features: Dictionary = {}
var course_recovery: CourseRecovery
var content_tracker: ParkContentTracker
var finish_trigger: Area3D

# Player-following reflection experiment: exactly one probe, UPDATE_ONCE only.
# The probe body stays parked at its last capture point; only a logical target
# is tracked per frame. Relocation IS the recapture trigger (an UPDATE_ONCE
# probe re-renders whenever its transform moves), so the probe is never eased
# continuously. Remove if A/B shows negligible benefit.
const PLAYER_PROBE_FOLLOW_OFFSET := Vector3(0.0, 2.5, 0.0)
const PLAYER_PROBE_SIZE := Vector3(28.0, 12.0, 28.0)
const PLAYER_PROBE_MAX_DISTANCE := 50.0
const PLAYER_PROBE_INTENSITY := 0.6
const PLAYER_PROBE_RECAPTURE_DISTANCE := 10.0
const PLAYER_PROBE_RECAPTURE_INTERVAL := 0.33
const PLAYER_PROBE_SNAP_DISTANCE := 40.0
const PLAYER_PROBE_REFRESH_OFFSET := 0.025
var _player_probe_allowed := false
var _probe_capture_position := Vector3.ZERO
var _probe_time_since_capture := 0.0
var _probe_refresh_pending := false
var _probe_refresh_parity := false
var player_probe_recaptures := 0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--session-yard"):
		course_profile = SESSION_YARD_PROFILE
	if follow_environment_setting:
		environment_profile = profile_for_preset(int(GameSettings.active.get("environment_preset", 0)))
	if environment_asset_catalog != null and (force_production_assets or OS.get_cmdline_user_args().has("--production-assets")):
		environment_asset_catalog.mode = EnvironmentAssetCatalog.AssetMode.PRODUCTION
	_validate_environment_asset_catalog()
	_build_environment()
	_build_resort()
	_configure_gi_geometry()
	_build_player()
	GameSettings.settings_applied.connect(_apply_graphics_settings)
	_apply_graphics_settings()
	_build_player_probe()

func _process(delta: float) -> void:
	_update_player_probe(delta)

func _validate_environment_asset_catalog() -> void:
	if environment_asset_catalog == null:
		push_error("Environment asset catalog is missing; refusing to build an untracked environment")
		return
	var require_production := environment_asset_catalog.should_use_production_scenes()
	for failure: String in environment_asset_catalog.validate(require_production):
		if require_production:
			push_error("ENVIRONMENT_ASSET_FAIL: " + failure)
		else:
			push_warning("ENVIRONMENT_ASSET_WARNING: " + failure)

func _build_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.07
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.glow_enabled = true
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.028
	sun.shadow_normal_bias = 0.82
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	fill_light = DirectionalLight3D.new()
	fill_light.name = "EnvironmentFill"
	fill_light.light_indirect_energy = 0.0
	fill_light.light_specular = 0.0
	fill_light.shadow_enabled = false
	fill_light.set_meta("gi_exclude", true)
	add_child(fill_light)
	_apply_environment_profile(environment_profile)

static func profile_for_preset(preset: int) -> ResortEnvironmentProfile:
	match clampi(preset, 0, 2):
		1: return GOLDEN_HOUR_ENVIRONMENT_PROFILE
		2: return SUNSET_ENVIRONMENT_PROFILE
		_: return DAY_ENVIRONMENT_PROFILE

func _apply_environment_profile(profile: ResortEnvironmentProfile) -> void:
	if profile == null or environment == null or environment.environment == null or sun == null:
		return
	var env := environment.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = profile.sky_top_color
		sky_mat.sky_horizon_color = profile.sky_horizon_color
		sky_mat.sky_curve = profile.sky_curve
		sky_mat.sky_energy_multiplier = profile.sky_energy
		sky_mat.ground_bottom_color = profile.ground_bottom_color
		sky_mat.ground_horizon_color = profile.ground_horizon_color
		sky_mat.ground_curve = profile.ground_curve
		sky_mat.ground_energy_multiplier = profile.ground_energy
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if profile.use_sky_ambient else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = profile.ambient_color
	env.ambient_light_sky_contribution = profile.ambient_sky_contribution
	env.ambient_light_energy = profile.ambient_energy
	env.tonemap_exposure = profile.exposure
	env.tonemap_white = profile.white_point
	env.adjustment_brightness = profile.brightness
	env.adjustment_contrast = profile.contrast
	env.adjustment_saturation = profile.saturation
	env.fog_light_color = profile.fog_color
	env.fog_sun_scatter = profile.fog_sun_scatter
	env.fog_density = profile.fog_density
	env.fog_aerial_perspective = profile.fog_aerial_perspective
	env.fog_sky_affect = profile.fog_sky_affect
	env.fog_height = profile.fog_height
	env.fog_height_density = profile.fog_height_density
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
	env.sdfgi_energy = profile.gi_energy
	env.sdfgi_bounce_feedback = clampf(profile.gi_bounce_feedback, 0.0, 0.5)
	env.sdfgi_cascades = clampi(profile.gi_cascades, 1, 8)
	env.sdfgi_cascade0_distance = maxf(profile.gi_cascade0_distance, 4.0)
	env.sdfgi_max_distance = maxf(profile.gi_max_distance, 32.0)
	env.sdfgi_use_occlusion = profile.gi_use_occlusion
	env.sdfgi_read_sky_light = profile.gi_read_sky_light
	sun.rotation_degrees = profile.sun_rotation_degrees
	sun.light_color = profile.sun_color
	sun.light_energy = profile.sun_energy
	sun.light_indirect_energy = profile.sun_indirect_energy
	sun.light_specular = profile.sun_specular
	sun.shadow_opacity = profile.shadow_opacity
	sun.shadow_blur = profile.shadow_blur
	sun.light_angular_distance = profile.sun_angular_distance
	sun.directional_shadow_fade_start = profile.shadow_fade_start
	if fill_light != null:
		fill_light.rotation_degrees = profile.fill_light_rotation_degrees
		fill_light.light_color = profile.fill_light_color
		fill_light.light_energy = profile.fill_light_energy
		fill_light.visible = profile.fill_light_enabled and profile.fill_light_energy > 0.0

func _configure_gi_geometry() -> void:
	if environment_profile == null or not environment_profile.gi_enabled:
		return
	# SDFGI only voxelizes GeometryInstance3D nodes marked static. All resort
	# scenery is generated before the player and VFX, so this pass cleanly marks
	# terrain, props, rails, and ridges while leaving the moving skier dynamic.
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == null or bool(geometry.get_meta("gi_exclude", false)):
			continue
		if player != null and (geometry == player or player.is_ancestor_of(geometry)):
			continue
		geometry.gi_mode = GeometryInstance3D.GI_MODE_STATIC

func _build_resort() -> void:
	var face_len := ParkLayout.FACE_SLOPE_LENGTH
	var main_face := ParkLayout.add_slope_box(self, "MainSnowFace", 0.0, 0.0, Vector3(ParkLayout.FACE_WIDTH, ParkLayout.FACE_THICKNESS, face_len), 0.0, SNOW, SnowSurface.Kind.POWDER, true, 0.0, SnowSurface.Kind.GROOMED)
	if summit_environment_profile != null and summit_environment_profile.enabled:
		SummitEnvironmentBuilderModule.build(self, main_face, summit_environment_profile, environment_asset_catalog)
	_add_box("BottomHub", Vector3(92.0, 1.5, 92.0), Vector3(0.0, 2.4, -181.0), Vector3.ZERO, SNOW, true, SnowSurface.Kind.POWDER, SnowSurface.Kind.PACKED)
	ParkLayout.add_slope_box(self, "LeftBank", -36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), -10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	ParkLayout.add_slope_box(self, "RightBank", 36.0, 0.0, Vector3(18.0, ParkLayout.FACE_THICKNESS, face_len), 10.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true)
	course_features = ParkCourseBuilderModule.build(self, course_profile, physics_profile, environment_asset_catalog)
	var lodge_pos := ParkLayout.snow_at(-18.0, 145.0) + Vector3(0.0, 2.6, 0.0)
	_add_lodge(lodge_pos)
	_add_tree_clusters()
	_add_course_dressing()
	_add_distant_terrain_skirt()
	_add_distant_ridges()
	# The high-altitude cloud card is a presentation layer. Keep it out of
	# headless acceptance runs because some software drivers reject the large
	# transparent plane, while production windows benefit from the extra horizon
	# breakup and depth cue.
	if environment_profile != null and environment_profile.high_haze_enabled and not OS.has_feature("headless"):
		_add_high_haze()

func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	player.profile = physics_profile
	player.position = ParkLayout.spawn_position(course_profile.spawn_world_z() if course_profile != null else 138.0)
	player.basis = ParkLayout.downhill_basis()
	add_child(player)
	for node: Node in player.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	SessionManager.set_default_spawn(player.global_transform)
	course_recovery = CourseRecoveryModule.new()
	course_recovery.name = "CourseRecovery"
	add_child(course_recovery)
	course_recovery.set_target(player)
	course_recovery.course_profile = course_profile

	camera_rig = SkiCameraController.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	player.respawn_applied.connect(_on_player_respawn_applied)

	var ui := GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.call_deferred("bind_player", player)
	ui.call_deferred("bind_camera", camera_rig)
	content_tracker = ParkContentTracker.new()
	content_tracker.name = "ParkContentTracker"
	add_child(content_tracker)
	content_tracker.configure(course_profile, player)
	ui.call_deferred("bind_content_tracker", content_tracker)
	ui.recovery_fade_out_duration = course_recovery.fade_out_duration
	ui.recovery_fade_in_duration = course_recovery.fade_in_duration
	course_recovery.recovery_started.connect(ui.notify_course_recovery)
	course_recovery.recovery_respawned.connect(ui.complete_course_recovery)
	_build_finish_trigger()

func _build_finish_trigger() -> void:
	finish_trigger = Area3D.new()
	finish_trigger.name = "FinishTrigger"
	finish_trigger.collision_layer = 0
	finish_trigger.collision_mask = 2
	finish_trigger.monitoring = true
	finish_trigger.position = ParkLayout.snow_at(0.0, course_profile.finish_trigger_world_z() if course_profile != null else -155.0) + ParkLayout.snow_normal() * 1.5
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

func _on_player_respawn_applied(_value: Transform3D) -> void:
	if camera_rig != null:
		camera_rig.reset_immediate()
	# Teleports invalidate the parked capture point: snap immediately rather
	# than waiting for the distance/time throttle.
	if player != null and player_probe != null and _player_probe_allowed:
		_move_probe_and_capture(_player_probe_target())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if player != null and player.respawn_applied.is_connected(_on_player_respawn_applied):
			player.respawn_applied.disconnect(_on_player_respawn_applied)
		if SessionManager.respawn_requested.is_connected(_on_respawn_requested_recorder):
			SessionManager.respawn_requested.disconnect(_on_respawn_requested_recorder)
		if player != null and player.scoring != null and player.scoring.run_finished.is_connected(_on_run_finished_recorder):
			player.scoring.run_finished.disconnect(_on_run_finished_recorder)

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
		body.set_meta("ski_surface_class", "snow")
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
	if tree_batch != null and _add_batched_tree(position, scale_multiplier, yaw_degrees, variant):
		return
	if _try_add_environment_asset("park_tree", position, yaw_degrees, Vector3.ONE * scale_multiplier, Color.TRANSPARENT, variant):
		return
	if _production_assets_required():
		push_error("ENVIRONMENT_ASSET_FAIL: park_tree scene is required in PRODUCTION mode")
		return
	var root := StaticBody3D.new()
	root.name = "ParkTree"
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	root.scale = Vector3.ONE * scale_multiplier
	root.collision_layer = 4
	root.collision_mask = 2
	root.add_to_group("park_trees")
	root.set_meta("asset_id", "park_tree")
	root.set_meta("asset_class", "SOLID")
	root.set_meta("collision_policy", "SOLID")
	root.set_meta("nominal_size_m", Vector3(3.0, 6.0, 3.0) * scale_multiplier)
	root.set_meta("readability_category", "landmark")
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
		var cap_mesh := CylinderMesh.new()
		# Vary cap shape per variant and scale to avoid repetitive flat disks.
		var cap_scale_var := 0.88 + 0.24 * float(variant % 4) / 3.0 + scale_multiplier * 0.06
		cap_mesh.top_radius = (0.12 + float(variant % 3) * 0.04) * cap_scale_var
		cap_mesh.bottom_radius = (0.78 + float(variant % 5) * 0.09 + scale_multiplier * 0.08) * cap_scale_var
		cap_mesh.height = (0.28 + float(variant % 3) * 0.07 + float(variant % 2) * 0.05) * cap_scale_var
		cap_mesh.radial_segments = 7 + variant % 2
		cap.mesh = cap_mesh
		# Intersect into foliage instead of hovering above: lower by ~0.45 and add slight random offset/yaw.
		var cap_offset_x := sin(float(variant * 1.7 + int(position.x * 0.1))) * 0.14
		var cap_offset_z := cos(float(variant * 1.3 + int(position.z * 0.1))) * 0.11
		var cap_y := tier_heights[-1] + 0.68 + float(variant % 2) * 0.12 - 0.06 * scale_multiplier
		cap.position = Vector3(cap_offset_x, cap_y, cap_offset_z)
		cap.rotation_degrees.y = float((variant * 47 + int(position.x + position.z)) % 360)
		cap.rotation_degrees.x = sin(float(variant * 2.1)) * 4.0
		cap.visibility_range_end = 245.0
		cap.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER)
		root.add_child(cap)
	add_child(root)

func _add_tree_clusters() -> void:
	# Deterministic clusters leave deliberate openings between vegetation masses.
	var tree_definition := environment_asset_catalog.definition_for("park_tree") if environment_asset_catalog != null else null
	if tree_definition != null and tree_definition.visual_scene != null and tree_definition.collision_scene != null and environment_asset_catalog.mode != EnvironmentAssetCatalog.AssetMode.GRAYBOX_FALLBACK:
		tree_batch = ParkTreeBatchModule.new()
		add_child(tree_batch)
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
	var jitter := RandomNumberGenerator.new()
	jitter.seed = 3817
	for index: int in range(tree_specs.size()):
		var spec := tree_specs[index]
		var x_offset := jitter.randf_range(-1.8, 1.8)
		var z_offset := jitter.randf_range(-2.6, 2.6)
		_add_tree(ParkLayout.snow_at(spec.x + x_offset, spec.y + z_offset), spec.z * jitter.randf_range(0.92, 1.08), spec.w + jitter.randf_range(-7.0, 7.0), index % 3)
	if tree_batch != null:
		tree_batch.commit()

func _add_batched_tree(position: Vector3, scale_multiplier: float, yaw_degrees: float, variant: int) -> bool:
	var definition := environment_asset_catalog.definition_for("park_tree") if environment_asset_catalog != null else null
	if definition == null or definition.collision_scene == null:
		return false
	var root := Node3D.new()
	root.name = "park_tree"
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	root.scale = Vector3.ONE * scale_multiplier
	root.add_to_group("park_trees")
	root.set_meta("asset_id", "park_tree")
	root.set_meta("asset_source", "production_multimesh")
	root.set_meta("style_variant", variant)
	root.set_meta("asset_class", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
	root.set_meta("collision_policy", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
	root.set_meta("nominal_size_m", definition.nominal_size_m * scale_multiplier)
	root.set_meta("readability_category", definition.readability_category)
	var collision_root := definition.collision_scene.instantiate()
	if collision_root == null:
		return false
	collision_root.name = "park_tree_Collision"
	root.add_child(collision_root)
	add_child(root)
	_configure_environment_collisions(collision_root, definition.asset_class, "park_tree")
	tree_batch.add_tree(root.transform)
	return true

func _add_distant_terrain_skirt() -> void:
	var columns := 11
	var rows := 6
	var skirt_mesh := SurfaceTool.new()
	skirt_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[PackedVector3Array] = []
	for row: int in range(rows):
		var row_points := PackedVector3Array()
		var z := lerpf(-132.0, -760.0, float(row) / float(rows - 1))
		for column: int in range(columns):
			var x := lerpf(-360.0, 360.0, float(column) / float(columns - 1))
			var broad_roll := sin(x * 0.007 + z * 0.004) * 4.2 + cos(x * 0.013 - z * 0.002) * 2.6
			var height := -3.0 - float(row) * 0.38 + broad_roll + sin(x * 0.021 + z * 0.014) * 1.4 + cos(x * 0.047 - z * 0.009) * 0.6
			row_points.append(Vector3(x, height, z))
		points.append(row_points)
	for row: int in range(rows - 1):
		for column: int in range(columns - 1):
			var a := points[row][column]
			var b := points[row][column + 1]
			var c := points[row + 1][column + 1]
			var d := points[row + 1][column]
			skirt_mesh.add_vertex(a); skirt_mesh.add_vertex(b); skirt_mesh.add_vertex(c)
			skirt_mesh.add_vertex(a); skirt_mesh.add_vertex(c); skirt_mesh.add_vertex(d)
	skirt_mesh.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "DistantTerrainSkirt"
	instance.add_to_group("environment_backdrop")
	instance.mesh = skirt_mesh.commit()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 900.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.material_override = _simple_material(Color("#647c8b"), 0.98)
	add_child(instance)

func _add_distant_ridges() -> void:
	if summit_environment_profile != null and summit_environment_profile.enabled and summit_environment_profile.backdrop_enabled:
		SummitEnvironmentBuilderModule.build_backdrop(self, summit_environment_profile)
		return
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
	# _add_high_haze() disabled for gate stability - high plane at 320m may cause driver leak in headless

func _add_high_haze() -> void:
	var haze := MeshInstance3D.new()
	haze.name = "HighHaze"
	haze.set_meta("gi_exclude", true)
	var plane := PlaneMesh.new()
	plane.size = Vector2(3800.0, 3800.0)
	haze.mesh = plane
	haze.position = Vector3(0, 320.0, -420.0)
	haze.rotation_degrees.x = 0.0
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.visibility_range_end = 2400.0
	haze.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/high_haze.gdshader")
	mat.set_shader_parameter("haze_color", Color(0.88, 0.92, 0.96, 1.0))
	mat.set_shader_parameter("haze_alpha", 0.09)
	mat.set_shader_parameter("haze_scale", 0.008)
	haze.material_override = mat
	add_child(haze)
	high_haze = haze

func _add_mountain_peak(label: String, position: Vector3, radius: float, height: float, color: Color, yaw_degrees: float, seed: int) -> void:
	var root := Node3D.new()
	root.name = label
	root.position = position
	root.rotation_degrees.y = yaw_degrees
	var mountain := MeshInstance3D.new()
	mountain.mesh = _create_mountain_mesh(radius, height, seed)
	var rock_material := ShaderMaterial.new()
	rock_material.shader = DISTANT_MOUNTAIN_SHADER
	rock_material.set_shader_parameter("base_color", color.lightened(0.08))
	rock_material.set_shader_parameter("haze_color", Color("#b4c2ca"))
	rock_material.set_shader_parameter("haze_start_distance", 170.0)
	rock_material.set_shader_parameter("haze_end_distance", 620.0)
	rock_material.set_shader_parameter("facet_value_range", 0.055)
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
	var ring_heights := [-height * 0.55, 0.0, height * 0.34, height * 0.7, height]
	var ring_scales := [1.2, 1.04, 0.72, 0.34, 0.035]
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
	_add_lift_tower(ParkLayout.snow_at(-30.0, 126.0), 6.5)
	_add_lift_tower(ParkLayout.snow_at(31.0, 42.0), 5.5)

func _add_lift_tower(position: Vector3, height: float) -> void:
	if _try_add_environment_asset("lift_tower", position, 0.0, Vector3(1.0, height / 6.3, 1.0)):
		return
	if _production_assets_required():
		push_error("ENVIRONMENT_ASSET_FAIL: lift_tower scene is required in PRODUCTION mode")
		return
	var root := Node3D.new()
	root.name = "LiftTower"
	root.set_meta("asset_id", "course_landmark")
	root.set_meta("asset_class", "GUIDE")
	root.set_meta("collision_policy", "GUIDE")
	root.set_meta("nominal_size_m", Vector3(2.0, height, 0.2))
	root.position = position + Vector3(0.0, height * 0.5, 0.0)
	var metal := _simple_material(Color("#435b68"), 0.64)
	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.055
		leg_mesh.bottom_radius = 0.075
		leg_mesh.height = height
		leg_mesh.radial_segments = 6
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.72, 0.0, 0.0)
		leg.material_override = metal
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(leg)
	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(2.0, 0.12, 0.16)
	crossbar.mesh = crossbar_mesh
	crossbar.position.y = height * 0.5
	crossbar.material_override = metal
	crossbar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crossbar)
	add_child(root)

func _add_boundary_fence(position: Vector3, length: float, yaw_degrees: float) -> void:
	if _try_add_environment_asset("course_boundary", position, yaw_degrees, Vector3(1.0, 1.0, length / 20.0), Color.TRANSPARENT, 0, true):
		return
	if _production_assets_required():
		push_error("ENVIRONMENT_ASSET_FAIL: course_boundary scene is required in PRODUCTION mode")
		return
	var root := Node3D.new()
	root.name = "BoundaryFence"
	root.add_to_group("course_landmarks")
	root.set_meta("asset_id", "course_boundary")
	root.set_meta("asset_class", "BOUNDARY")
	root.set_meta("collision_policy", "BOUNDARY")
	root.set_meta("nominal_size_m", Vector3(0.2, 1.1, length))
	root.transform = Transform3D(ParkLayout.downhill_basis(yaw_degrees), position + ParkLayout.snow_normal() * 0.03)
	var material := _simple_material(Color("#55666b"), 0.9)
	for along: float in [-length * 0.5, -length * 0.25, 0.0, length * 0.25, length * 0.5]:
		_add_visual_box(root, Vector3(0.11, 1.05, 0.11), Vector3(0.0, 0.52, along), material)
		_add_collision_box(root, Vector3(0.11, 1.05, 0.11), Vector3(0.0, 0.52, along), "BoundaryFencePost")
	for height: float in [0.34, 0.78]:
		_add_visual_box(root, Vector3(0.075, 0.075, length), Vector3(0.0, height, 0.0), material)
		_add_collision_box(root, Vector3(0.075, 0.075, length), Vector3(0.0, height, 0.0), "BoundaryFenceWire")
	add_child(root)

func _add_snowmaker(position: Vector3, yaw_degrees: float) -> void:
	if _try_add_environment_asset("snowmaker", position, yaw_degrees, Vector3.ONE):
		return
	if _production_assets_required():
		push_error("ENVIRONMENT_ASSET_FAIL: snowmaker scene is required in PRODUCTION mode")
		return
	var root := Node3D.new()
	root.name = "Snowmaker"
	root.add_to_group("course_landmarks")
	root.set_meta("asset_id", "course_landmark")
	root.set_meta("asset_class", "GUIDE")
	root.set_meta("collision_policy", "GUIDE")
	root.set_meta("nominal_size_m", Vector3(0.7, 1.8, 0.8))
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
	if _try_add_environment_asset("trail_board", position, 0.0, Vector3.ONE, color):
		return
	if _production_assets_required():
		push_error("ENVIRONMENT_ASSET_FAIL: trail_board scene is required in PRODUCTION mode")
		return
	var root := Node3D.new()
	root.name = "TrailBoard"
	root.add_to_group("course_landmarks")
	root.set_meta("asset_id", "course_landmark")
	root.set_meta("asset_class", "GUIDE")
	root.set_meta("collision_policy", "GUIDE")
	root.set_meta("nominal_size_m", Vector3(1.5, 2.0, 0.2))
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

func _add_collision_box(parent: Node3D, size: Vector3, position: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 4
	body.collision_mask = 2
	var parent_asset_id := str(parent.get_meta("asset_id", ""))
	if not parent_asset_id.is_empty():
		body.set_meta("asset_id", parent_asset_id)
	body.set_meta("asset_class", "BOUNDARY")
	body.set_meta("collision_policy", "BOUNDARY")
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = position
	body.add_child(shape_node)
	parent.add_child(body)

func _simple_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material

func _production_assets_required() -> bool:
	return environment_asset_catalog != null and environment_asset_catalog.should_use_production_scenes()

func _try_add_environment_asset(asset_id: String, position: Vector3, yaw_degrees: float, scale: Vector3, accent_color: Color = Color.TRANSPARENT, style_variant: int = 0, slope_aligned: bool = false) -> bool:
	if environment_asset_catalog == null or not environment_asset_catalog.should_use_scene(asset_id):
		return false
	var scene := environment_asset_catalog.scene_for(asset_id)
	if scene == null:
		return false
	var instance := scene.instantiate() as Node3D
	if instance == null:
		push_error("ENVIRONMENT_ASSET_FAIL: %s scene did not instantiate as Node3D" % asset_id)
		return false
	instance.name = asset_id
	instance.position = position
	instance.basis = ParkLayout.downhill_basis(yaw_degrees) if slope_aligned else Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	instance.scale = scale
	instance.set_meta("asset_id", asset_id)
	instance.set_meta("asset_source", "production_scene")
	instance.set_meta("style_variant", style_variant)
	if asset_id == "park_tree":
		instance.add_to_group("park_trees")
	elif asset_id in ["lift_tower", "course_boundary", "snowmaker", "trail_board"]:
		instance.add_to_group("course_landmarks")
	if accent_color.a > 0.0:
		instance.set_meta("accent_color", accent_color)
	var definition := environment_asset_catalog.definition_for(asset_id)
	var collision_root: Node
	if definition != null:
		if definition.collision_scene != null:
			collision_root = definition.collision_scene.instantiate()
			if collision_root != null:
				collision_root.name = "%s_Collision" % asset_id
				instance.add_child(collision_root)
	add_child(instance)
	if definition != null:
		if collision_root != null:
			_configure_environment_collisions(collision_root, definition.asset_class, asset_id)
		var dimension_failures := definition.validate_instance(instance)
		for reason: String in dimension_failures:
			if _production_assets_required():
				push_error("ENVIRONMENT_ASSET_FAIL: %s: %s" % [asset_id, reason])
			else:
				push_warning("ENVIRONMENT_ASSET_WARNING: %s: %s" % [asset_id, reason])
		if _production_assets_required() and not dimension_failures.is_empty():
			remove_child(instance)
			instance.free()
			return false
		instance.set_meta("asset_class", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
		instance.set_meta("collision_policy", EnvironmentAssetDefinition.AssetClass.keys()[definition.asset_class])
		_configure_environment_collisions(instance, definition.asset_class, asset_id)
	return true

func _configure_environment_collisions(root: Node, asset_class: EnvironmentAssetDefinition.AssetClass, asset_id: String = "") -> void:
	# Environment props are solid obstacles, not skiable terrain. Keep them on
	# Features so post-motion crash diagnostics can identify impacts separately
	# from snow-surface contacts.
	var collision_layer := 4
	if asset_class == EnvironmentAssetDefinition.AssetClass.GRIND_ONLY:
		collision_layer = 8
	elif asset_class == EnvironmentAssetDefinition.AssetClass.BOUNDARY:
		collision_layer = 4
	elif asset_class == EnvironmentAssetDefinition.AssetClass.GUIDE or asset_class == EnvironmentAssetDefinition.AssetClass.DECORATION:
		collision_layer = 0
	var collision_nodes: Array[Node] = []
	if root is CollisionObject3D:
		collision_nodes.append(root)
	collision_nodes.append_array(root.find_children("*", "CollisionObject3D", true, false))
	for node: Node in collision_nodes:
		var collision_object := node as CollisionObject3D
		if collision_object == null:
			continue
		collision_object.collision_layer = collision_layer
		collision_object.collision_mask = 2
		if not asset_id.is_empty():
			collision_object.set_meta("asset_id", asset_id)
		collision_object.set_meta("asset_class", EnvironmentAssetDefinition.AssetClass.keys()[asset_class])
		collision_object.set_meta("collision_policy", EnvironmentAssetDefinition.AssetClass.keys()[asset_class])

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

static func player_probe_allowed_for_preset(preset: int) -> bool:
	# Dedicated probe capability policy: High, Ultra, and Custom. Numerically
	# identical to the GI gate, but reflections are not GI policy, so this
	# stays local to resort.gd instead of reusing graphics_preset_allows_gi().
	return clampi(preset, 0, 4) >= 2

static func probe_should_recapture(distance: float, elapsed: float) -> bool:
	return distance >= PLAYER_PROBE_RECAPTURE_DISTANCE and elapsed >= PLAYER_PROBE_RECAPTURE_INTERVAL

static func probe_should_snap(distance: float) -> bool:
	return distance >= PLAYER_PROBE_SNAP_DISTANCE

func _player_probe_target() -> Vector3:
	if player == null:
		return _probe_capture_position
	return player.global_position + PLAYER_PROBE_FOLLOW_OFFSET

func _build_player_probe() -> void:
	# Created after _build_player() so the first cubemap is centered on the
	# player, with the same semantics as every later capture.
	if OS.has_feature("headless") or player == null:
		return
	var probe := ReflectionProbe.new()
	probe.name = "PlayerProbe"
	probe.size = PLAYER_PROBE_SIZE
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = PLAYER_PROBE_MAX_DISTANCE
	probe.intensity = PLAYER_PROBE_INTENSITY
	probe.enable_shadows = false
	probe.interior = false
	probe.box_projection = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.set_meta("gi_exclude", true)
	add_child(probe)
	player_probe = probe
	player_probe.visible = _player_probe_allowed
	_probe_capture_position = _player_probe_target()
	_probe_time_since_capture = PLAYER_PROBE_RECAPTURE_INTERVAL
	_probe_refresh_pending = false
	probe.global_position = _probe_capture_position
	probe.update_mode = ReflectionProbe.UPDATE_ONCE

func _move_probe_and_capture(target: Vector3) -> void:
	# Relocation IS the UPDATE_ONCE recapture trigger: the probe re-renders
	# whenever its transform moves, so no continuous easing is used.
	if player_probe == null:
		return
	player_probe.global_position = target
	player_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe_capture_position = target
	_probe_time_since_capture = 0.0
	_probe_refresh_pending = false
	player_probe_recaptures += 1

func _force_probe_refresh() -> void:
	# Environment changed while stationary: relocation normally supplies the
	# movement that triggers an UPDATE_ONCE capture, so nudge instead.
	# Alternating +-offset around the canonical center avoids cumulative drift
	# across repeated Day/Sunset switches.
	if player_probe == null:
		return
	_probe_refresh_parity = not _probe_refresh_parity
	var sign := 1.0 if _probe_refresh_parity else -1.0
	player_probe.global_position = _probe_capture_position + Vector3(0.0, sign * PLAYER_PROBE_REFRESH_OFFSET, 0.0)
	player_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe_time_since_capture = 0.0
	_probe_refresh_pending = false
	player_probe_recaptures += 1

func _update_player_probe(delta: float) -> void:
	# Settings policy lives in _apply_graphics_settings(); this only handles
	# movement/time policy. The probe body never eases: it stays parked where
	# its current cubemap was captured until a gate fires.
	if player_probe == null or player == null or not _player_probe_allowed:
		return
	var target := _player_probe_target()
	var distance := target.distance_to(_probe_capture_position)
	if probe_should_snap(distance):
		_move_probe_and_capture(target)
		return
	_probe_time_since_capture += delta
	if probe_should_recapture(distance, _probe_time_since_capture):
		_move_probe_and_capture(target)
		return
	if _probe_refresh_pending and _probe_time_since_capture >= PLAYER_PROBE_RECAPTURE_INTERVAL:
		_force_probe_refresh()

func _apply_graphics_settings() -> void:
	if environment == null or environment.environment == null:
		return
	var profile_changed := false
	if follow_environment_setting:
		var selected_profile := profile_for_preset(int(GameSettings.active.get("environment_preset", 0)))
		if selected_profile != environment_profile:
			environment_profile = selected_profile
			_apply_environment_profile(environment_profile)
			_configure_gi_geometry()
			profile_changed = true
	# Cache probe policy here so _process() only handles movement/time policy.
	var was_allowed := _player_probe_allowed
	_player_probe_allowed = player_probe_allowed_for_preset(int(GameSettings.active.get("graphics_preset", 2)))
	if player_probe != null:
		player_probe.visible = _player_probe_allowed
	if player_probe != null and profile_changed:
		if _player_probe_allowed:
			if _probe_time_since_capture >= PLAYER_PROBE_RECAPTURE_INTERVAL:
				_force_probe_refresh()
			else:
				_probe_refresh_pending = true
		else:
			# Disabled: mark dirty rather than paying for a hidden capture.
			_probe_refresh_pending = true
	if _player_probe_allowed and not was_allowed and player_probe != null:
		# Disabled -> enabled edge: snap immediately instead of waiting for
		# the normal distance/time gate.
		_move_probe_and_capture(_player_probe_target())
	var env := environment.environment
	env.ssao_enabled = bool(GameSettings.active.get("ssao_enabled", true))
	env.ssil_enabled = bool(GameSettings.active.get("ssil_enabled", false))
	env.ssr_enabled = bool(GameSettings.active.get("ssr_enabled", true))
	env.fog_enabled = bool(GameSettings.active.get("fog_enabled", true))
	if high_haze != null:
		# The high card and environment fog serve the same distant-atmosphere role.
		# Avoid paying for the full-screen transparent noise pass when fog already
		# provides that depth cue; retain the card as the user's fog-off fallback.
		high_haze.visible = environment_profile.high_haze_enabled and not env.fog_enabled
	env.sdfgi_enabled = effective_gi_enabled()
	_apply_shadow_quality(int(GameSettings.active.get("shadow_quality", 2)))

static func resolve_effective_gi(profile: ResortEnvironmentProfile, user_enabled: bool, graphics_preset: int) -> bool:
	return profile != null and profile.gi_enabled and user_enabled and GameSettings.graphics_preset_allows_gi(graphics_preset)

func effective_gi_enabled() -> bool:
	return resolve_effective_gi(
		environment_profile,
		bool(GameSettings.active.get("gi_enabled", true)),
		int(GameSettings.active.get("graphics_preset", 2)),
	)

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
