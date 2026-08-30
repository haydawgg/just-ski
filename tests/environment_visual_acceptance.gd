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
		if marker_material == null or marker_material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			failures.append("Snow jump guide did not preserve its restrained dye color through changing snow light")
		if not marker.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("A presentation-only snow jump marker created collision")
	var world_signs := resort.find_children("*", "Label3D", true, false)
	if world_signs.is_empty():
		failures.append("Resort did not build any world-space wayfinding signs")
	for sign_node: Node in world_signs:
		var sign := sign_node as Label3D
		if sign != null and sign.pixel_size > 0.0048:
			failures.append("World-space wayfinding sign exceeds the skier-safe screen hierarchy (%.4f)" % sign.pixel_size)
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
	if failures.is_empty():
		print("ENVIRONMENT_VISUAL_PASS: bounded collision-free jump guides plus existing-contact tracks and restrained snow spray")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ENVIRONMENT_VISUAL_FAIL: " + failure)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
