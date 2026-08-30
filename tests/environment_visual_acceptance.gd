extends Node

var frame_count := 0
@onready var resort: Node3D = $Resort

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count < 360:
		return
	var failures: Array[String] = []
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
		elif marker_material.albedo_color.a > 0.7 or marker_material.emission_enabled:
			failures.append("Snow jump guide returned to an opaque or emissive UI-like treatment")
		if not marker.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("A presentation-only snow jump marker created collision")
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
		AudioManager.shutdown_audio()
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ENVIRONMENT_VISUAL_FAIL: " + failure)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
