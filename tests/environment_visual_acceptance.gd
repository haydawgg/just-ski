extends Node

const ResortModule := preload("res://world/resort.gd")
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var frame_count := 0
var _finish_started := false
@onready var resort: Node3D = $Resort

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count < 360:
		return
	var failures: Array[String] = []
	if RuntimeEnvironment.is_headless():
		if resort.get_node_or_null("PlayerProbe") != null:
			failures.append("Headless resort created a reflection probe")
		if resort.get_node_or_null("HighHaze") != null:
			failures.append("Headless resort created a haze presentation node")
	var world_environment := resort.get("environment") as WorldEnvironment
	var sun := resort.get("sun") as DirectionalLight3D
	if world_environment == null or world_environment.environment == null:
		failures.append("Resort did not create its tuned WorldEnvironment")
	else:
		var tuned_environment := world_environment.environment
		if tuned_environment.ssao_radius > 1.0 or tuned_environment.ssao_intensity > 1.5:
			failures.append("SSAO escaped the local-contact budget (radius %.2f, intensity %.2f)" % [tuned_environment.ssao_radius, tuned_environment.ssao_intensity])
		if tuned_environment.fog_density > 0.003:
			failures.append("Course fog is dense enough to obscure midground terrain (%.4f)" % tuned_environment.fog_density)
		_test_environment_preset_application(tuned_environment, sun, failures)
	if sun == null:
		failures.append("Resort did not create its single directional sun")
	else:
		if sun.shadow_opacity < 0.45 or sun.shadow_opacity > 0.72:
			failures.append("Sun shadow opacity no longer preserves restrained depth (%.2f)" % sun.shadow_opacity)
		if not sun.shadow_enabled:
			failures.append("Sun shadows were removed instead of tuned")
	var extra_lights := resort.find_children("*", "OmniLight3D", true, false).size() + resort.find_children("*", "SpotLight3D", true, false).size()
	if extra_lights > 0:
		failures.append("Snow readability added %d local lights instead of using the existing environment" % extra_lights)
	var snow_profile := SnowMaterial.PRESENTATION
	if snow_profile.groomed_form_contrast < 0.1 or snow_profile.groomed_broad_variation < 0.1:
		failures.append("Groomed snow lost its large-scale normal/value separation")
	if snow_profile.minimum_albedo_luminance < 0.4:
		failures.append("Snow lost the minimum value floor that protects skier and feature readability")
	if snow_profile.steepness_contrast > 0.1:
		failures.append("Steep snow response can become charcoal again (%.3f)" % snow_profile.steepness_contrast)
	var marked_jump_specs := 0
	var course_profile := resort.get("course_profile") as ParkCourseProfile
	if course_profile != null:
		for spec: Dictionary in course_profile.feature_specs():
			if str(spec.get("kind", "")) in ["tabletop", "hip"]:
				marked_jump_specs += 1
	var readability_markers := get_tree().get_nodes_in_group("park_readability_markers")
	if marked_jump_specs == 0:
		failures.append("Course profile did not author any marked snow jumps")
	if readability_markers.size() != marked_jump_specs:
		failures.append("Snow jump readability markers were not bounded to one mesh per authored tabletop/hip (%d markers for %d specs)" % [readability_markers.size(), marked_jump_specs])
	for marker_node: Node in readability_markers:
		var marker := marker_node as MeshInstance3D
		if marker == null or marker.mesh == null or marker.mesh.get_surface_count() != 1:
			failures.append("A snow jump readability marker is not a single render surface")
			continue
		if marker.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("A snow jump readability marker casts an unnecessary shadow")
		var marker_material := marker.material_override as StandardMaterial3D
		if marker_material == null or marker_material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
			failures.append("Snow jump guide is not integrated into scene lighting")
		elif marker_material.albedo_color.a < 0.98 or marker_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or marker_material.emission_enabled:
			failures.append("Snow jump guide is still translucent or emissive instead of an opaque surface stamp")
		if not marker.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("A presentation-only snow jump marker created collision")
	var profiled_feature_meshes := 0
	var profiled_feature_colliders := 0
	var minimum_feature_texture_weight := INF
	for body_node: Node in resort.find_children("*", "StaticBody3D", true, false):
		if not body_node.has_meta("profile_rows"):
			continue
		if not bool(body_node.get_meta("render_collision_separated", false)):
			failures.append("Profiled feature %s does not declare separate render/collision geometry" % body_node.get_path())
		var profiled_body := body_node as StaticBody3D
		if profiled_body != null and profiled_body.collision_layer & 1 != 0:
			if profiled_body.find_children("*", "CollisionShape3D", true, false).is_empty():
				failures.append("Playable profiled feature %s lost its collision shape" % body_node.get_path())
			else:
				profiled_feature_colliders += 1
		for mesh_node: Node in body_node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance == null:
				continue
			profiled_feature_meshes += 1
			if not bool(mesh_instance.get_meta("render_surface_only", false)):
				failures.append("Profiled feature %s is missing the render-surface marker" % mesh_instance.get_path())
			var snow_material := mesh_instance.material_override as ShaderMaterial
			if snow_material == null or snow_material.shader == null:
				failures.append("Profiled feature %s has no snow shader material" % mesh_instance.get_path())
				continue
			var texture_weight := float(snow_material.get_shader_parameter("albedo_texture_strength"))
			minimum_feature_texture_weight = minf(minimum_feature_texture_weight, texture_weight)
	if profiled_feature_meshes == 0:
		failures.append("No profiled feature meshes were available for texture coverage validation")
	elif minimum_feature_texture_weight < 0.25:
		failures.append("Profiled feature albedo texture blend is only %.3f; jump surfaces remain mostly flat" % minimum_feature_texture_weight)
	if profiled_feature_colliders == 0:
		failures.append("No playable profiled feature retained a collision shape")
	var world_signs := resort.find_children("*", "Label3D", true, false)
	if not world_signs.is_empty():
		failures.append("Normal play still contains %d world labels that can cover the skier" % world_signs.size())
	var authored_gates := 0
	if course_profile != null:
		for spec: Dictionary in course_profile.feature_specs():
			if str(spec.get("kind", "")) == "gate":
				authored_gates += 1
	var route_gates := get_tree().get_nodes_in_group("park_gates")
	var route_flags := get_tree().get_nodes_in_group("route_guide_flags")
	if route_gates.size() != authored_gates:
		failures.append("Minimal route flags do not match the authored gate count")
	if route_flags.size() != authored_gates * 2:
		failures.append("Minimal route guidance did not create exactly two flags per gate")
	for gate_node: Node in route_gates:
		var gate := gate_node as Node3D
		if gate == null or str(gate.get_meta("guidance_style", "")) != "minimal_flag_posts":
			failures.append("A route gate did not use the minimal flag-post language")
			continue
		if not gate.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("A route guide created collision")
		for flag_node: Node in route_flags:
			if not gate.is_ancestor_of(flag_node):
				continue
			var flag := flag_node as MeshInstance3D
			if flag.visibility_range_begin < 2.0 or flag.visibility_range_end > 90.0:
				failures.append("Route flag lost its proximity/distance fade budget")
	var trees := get_tree().get_nodes_in_group("park_trees")
	if trees.size() < 24:
		failures.append("Environment lacks enough trees to form intentional clusters")
	var tree_scales: Dictionary = {}
	for tree_node: Node in trees:
		var tree := tree_node as Node3D
		if tree != null:
			tree_scales[snappedf(tree.scale.x, 0.05)] = true
	if tree_scales.size() < 5:
		failures.append("Tree scale variation is too uniform")
	for asset_id: String in ["park_tree", "course_boundary", "lift_tower", "snowmaker", "trail_board"]:
		var asset_instances := resort.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return str(node.get_meta("asset_id", "")) == asset_id)
		var near_shadow_mesh_found := false
		for asset_node: Node in asset_instances:
			for mesh_node: Node in asset_node.find_children("*", "GeometryInstance3D", true, false):
				var mesh_instance := mesh_node as GeometryInstance3D
				if mesh_instance != null and mesh_instance.visibility_range_begin <= 0.01 and mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
					near_shadow_mesh_found = true
					break
			if near_shadow_mesh_found:
				break
		if not near_shadow_mesh_found:
			failures.append("Production %s has no near-field shadow-casting mesh" % asset_id)
	var mountain_meshes := resort.find_children("*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool: return node.get_parent() != null and (node.get_parent().name.begins_with("FarPeak") or node.get_parent().name.begins_with("HazePeak")))
	if mountain_meshes.size() < 8:
		failures.append("Layered mountain composition was not built")
	for mountain_node: Node in mountain_meshes:
		var mountain := mountain_node as MeshInstance3D
		if mountain != null and not mountain.mesh is ArrayMesh:
			failures.append("A distant ridge returned to a repeated primitive silhouette")
	var landmarks := get_tree().get_nodes_in_group("course_landmarks")
	if landmarks.size() < 8:
		failures.append("Course edge lacks sparse resort scale landmarks")
	_validate_lower_run_hub_dressing(failures)
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		failures.append("Resort did not create the skier")
	else:
		var vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX
		if vfx == null:
			failures.append("Skier is missing the presentation-only snow VFX component")
		else:
			var snapshot := vfx.debug_snapshot()
			if not bool(snapshot.uses_existing_contact):
				failures.append("Snow VFX is not bound to the existing skier contact data")
			if int(snapshot.left_track_samples) < 4 or int(snapshot.right_track_samples) < 4:
				failures.append("Normal resort travel did not produce both bounded ski tracks")
			if int(snapshot.left_track_samples) > int(snapshot.track_cap) or int(snapshot.right_track_samples) > int(snapshot.track_cap):
				failures.append("Persistent track history exceeded its hard cap")
			if int(snapshot.track_rebuild_count) <= 0 or int(snapshot.track_rebuild_count) >= frame_count:
				failures.append("Track mesh rebuilds are no longer gated below the physics-frame rate")
			if int(snapshot.continuous_particle_cap) > 200:
				failures.append("Continuous snow particle budget exceeded the acceptance ceiling")
			if not vfx.find_children("*", "RayCast3D", true, false).is_empty():
				failures.append("Snow VFX created a second terrain-contact system")
			var track_mesh := vfx.get_node_or_null("PersistentSkiTracks") as MeshInstance3D
			if track_mesh == null or track_mesh.mesh == null or track_mesh.mesh.get_surface_count() == 0:
				failures.append("Track ribbon mesh was not generated")
			var result := {
				"score": 0.76,
				"impact_severity": 0.72,
				"lateral_velocity": 2.0,
			}
			skier.landed.emit(result)
			if float(vfx.debug_snapshot().landing_severity) < 0.7:
				failures.append("Landing severity did not reach the one-shot landing burst")
			if not vfx.landing_spray.emitting:
				failures.append("Hard landing did not restart the one-shot landing emitter")
			skier.state = SkierController.State.BAIL
			skier.contact.grounded = true
			skier.contact.average_normal = Vector3.UP
			skier.contact.average_hit_position = skier.global_position
			skier.velocity = Vector3(0.0, 0.0, -7.0)
			vfx.update_from_existing_contact(1.0 / 60.0)
			var bail_snapshot := vfx.debug_snapshot()
			if not bool(bail_snapshot.bail_scrape_active) or float(bail_snapshot.bail_surface_speed) < 6.5:
				failures.append("Surface-velocity bail scrape did not activate")
	if failures.is_empty():
		print("ENVIRONMENT_VISUAL_PASS: minimal route flags, readable snow, layered scenery, and state-specific snow contact feedback")
		_finish(0)
	else:
		for failure: String in failures:
			push_error("ENVIRONMENT_VISUAL_FAIL: " + failure)
		_finish(1)

func _finish(exit_code: int) -> void:
	if _finish_started:
		return
	_finish_started = true
	set_process(false)
	set_physics_process(false)
	AudioManager.shutdown_audio()
	for child: Node in get_children():
		if is_instance_valid(child):
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not RuntimeEnvironment.is_headless():
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	get_tree().quit(exit_code)

func _validate_lower_run_hub_dressing(failures: Array[String]) -> void:
	var catalog := resort.get("environment_asset_catalog") as EnvironmentAssetCatalog
	var dressing := get_tree().get_nodes_in_group("lower_run_hub_dressing")
	if dressing.size() < 12:
		failures.append("Lower-run/hub dressing is incomplete (%d deterministic props; expected 12)" % dressing.size())
	var zone_counts: Dictionary = {}
	for node: Node in dressing:
		var prop := node as Node3D
		if prop == null:
			failures.append("Lower-run/hub dressing group contains a non-spatial node")
			continue
		var zone := str(prop.get_meta("dressing_zone", ""))
		zone_counts[zone] = int(zone_counts.get(zone, 0)) + 1
		if str(prop.get_meta("asset_id", "")) != "snow_boulder":
			failures.append("Lower-run/hub dressing used an unexpected asset: %s" % prop.get_meta("asset_id", ""))
		if str(prop.get_meta("asset_class", "")) != "DECORATION":
			failures.append("Lower-run/hub dressing %s is not classified as DECORATION" % prop.name)
		if not prop.find_children("*", "CollisionObject3D", true, false).is_empty():
			failures.append("Lower-run/hub decoration %s introduced a collision object" % prop.name)
		var expected_position := prop.get_meta("dressing_expected_position", Vector3.INF) as Vector3
		if expected_position.is_finite() and prop.global_position.distance_to(expected_position) > 0.01:
			failures.append("Dressing prop %s moved away from its deterministic anchor" % prop.name)
		if zone != "hub":
			_validate_dressing_feature_clearance(prop, resort.get("course_profile") as ParkCourseProfile, failures)
		var definition := catalog.definition_for(str(prop.get_meta("asset_id", ""))) if catalog != null else null
		if definition == null:
			failures.append("Dressing prop %s is not present in the environment catalog" % prop.name)
			continue
		var authored_lod := prop.get_meta("lod_distances_m", Vector3.ZERO) as Vector3
		if authored_lod != definition.lod_distances_m:
			failures.append("Dressing prop %s did not inherit catalog LOD distances" % prop.name)
		var near_shadow := false
		var far_silhouette := false
		for mesh_node: Node in prop.find_children("*", "GeometryInstance3D", true, false):
			var mesh := mesh_node as GeometryInstance3D
			if mesh == null:
				continue
			if str(mesh.get_meta("lod_source", "")) != "catalog":
				failures.append("Dressing mesh %s does not declare catalog-driven LOD" % mesh.get_path())
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and mesh.visibility_range_begin <= 0.01 and mesh.visibility_range_end <= definition.lod_distances_m.y + 0.01:
				near_shadow = true
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mesh.visibility_range_begin >= definition.lod_distances_m.x - 0.01 and mesh.visibility_range_end <= definition.lod_distances_m.z + 0.01:
				far_silhouette = true
		if not near_shadow:
			failures.append("Dressing prop %s has no catalog-bounded near shadow mesh" % prop.name)
		if not far_silhouette:
			failures.append("Dressing prop %s has no catalog-bounded far silhouette" % prop.name)
	for required_zone: String in ["lower_run", "finale", "hub"]:
		if int(zone_counts.get(required_zone, 0)) < 4:
			failures.append("Dressing zone %s has fewer than four deterministic props" % required_zone)

func _validate_dressing_feature_clearance(prop: Node3D, course_profile: ParkCourseProfile, failures: Array[String]) -> void:
	if course_profile == null:
		failures.append("Dressing prop %s could not verify course corridor clearance without a course profile" % prop.name)
		return
	var anchor_variant: Variant = prop.get_meta("dressing_anchor_xz", Vector2.INF)
	if not anchor_variant is Vector2:
		failures.append("Dressing prop %s is missing its authored X/Z clearance anchor" % prop.name)
		return
	var anchor: Vector2 = anchor_variant
	var nearest_distance: float = INF
	var nearest_feature := ""
	for spec: Dictionary in course_profile.feature_specs():
		var distance: float = _dressing_distance_to_feature(anchor, spec)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_feature = str(spec.get("name", spec.get("kind", "feature")))
	if nearest_distance < 5.5:
		failures.append("Dressing prop %s is only %.2fm from the %s approach/landing corridor" % [prop.name, nearest_distance, nearest_feature])

func _dressing_distance_to_feature(anchor: Vector2, spec: Dictionary) -> float:
	var kind := str(spec.get("kind", ""))
	var points: Array[Vector2] = []
	if kind == "rail":
		for point_variant in spec.get("points", []):
			if point_variant is Vector3:
				var point: Vector3 = point_variant
				points.append(Vector2(point.x, point.y))
	else:
		var center := Vector2(float(spec.get("x", 0.0)), float(spec.get("z", 0.0)))
		points.append(center)
		var length := float(spec.get("length", 0.0))
		if length > 0.0:
			points.append(center + Vector2(0.0, length * 0.5))
			points.append(center - Vector2(0.0, length * 0.5))
	if points.is_empty():
		return INF
	var minimum := INF
	for point in points:
		minimum = minf(minimum, anchor.distance_to(point))
	for index in range(points.size() - 1):
		minimum = minf(minimum, _distance_to_segment(anchor, points[index], points[index + 1]))
	return minimum

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _test_environment_preset_application(env: Environment, active_sun: DirectionalLight3D, failures: Array[String]) -> void:
	if active_sun == null:
		return
	var original_active := GameSettings.active.duplicate(true)
	var original_pending := GameSettings.pending.duplicate(true)
	GameSettings.begin_edit()
	GameSettings.set_pending("environment_preset", 0)
	GameSettings.apply_pending()
	GameSettings.begin_edit()
	GameSettings.set_pending("environment_preset", 2)
	GameSettings.apply_pending()
	var expected_profile := ResortModule.profile_for_preset(2)
	var selected_profile := resort.get("environment_profile") as ResortEnvironmentProfile
	if selected_profile != expected_profile:
		failures.append("Applying time of day did not select its authored environment profile")
	var sky_material := env.sky.sky_material as ProceduralSkyMaterial
	if sky_material == null or sky_material.sky_horizon_color != expected_profile.sky_horizon_color:
		failures.append("Applying time of day did not update the live procedural sky")
	if active_sun.light_color != expected_profile.sun_color:
		failures.append("Applying time of day did not update the live directional sun")
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier != null:
		for node: Node in skier.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).gi_mode == GeometryInstance3D.GI_MODE_STATIC:
				failures.append("Live Sunset switching marked moving skier geometry as static GI")
				break
	GameSettings.active = original_active
	GameSettings.pending = original_pending
	GameSettings.apply_pending()
