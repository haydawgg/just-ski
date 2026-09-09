extends Node

const OUTPUT_PATH := "res://.godot_user/captures/sunset_resort.png"
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const OutputPathGuard := preload("res://util/output_path_guard.gd")
const ProfileMetrics := preload("res://tests/performance_profile_metrics.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")

var frame_count := 0
var frame_time_sum := 0.0
var frame_time_samples := 0
var frame_times_ms: Array[float] = []
var landing_captured := false
var isolation_mode := "baseline"
var feature_isolation_name := ""
var capture_path := OUTPUT_PATH
var profile_snow_quality := -1
var profile_graphics_preset := -1
var profile_output_path := "res://.godot_user/captures/sunset_visual_profile.json"
var profile_environment := "sunset"
var profile_commit_sha := "unknown"
var profile_working_tree_dirty := false
var profile_render_scale := -1.0
var evidence_root := ""
var evidence: VisualEvidenceSession
var evidence_finished := false
var fixed_fps := 0
var _finish_started := false
var capture_written := false

func _ready() -> void:
	_parse_visual_arguments()
	var evidence_directory := evidence_root
	if evidence_directory.is_empty():
		evidence_directory = "res://.godot_user/captures/sunset_visual_evidence"
	else:
		var compatibility_directory := evidence_directory.path_join("compat")
		capture_path = compatibility_directory.path_join("sunset_resort.png")
		profile_output_path = compatibility_directory.path_join("sunset_visual_profile.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_path.get_base_dir()))
	evidence = VisualEvidence.begin({
		"suite_id": "sunset",
		"evidence_root": evidence_directory,
		"fixed_fps": fixed_fps,
		"capture_width": 1280,
		"capture_height": 720,
		"context": {
			"scene": "sunset_visual_inspection",
			"environment": profile_environment,
			"preset": profile_graphics_preset,
			"isolation_mode": isolation_mode,
			"render_scale": profile_render_scale,
		},
	})
	if RuntimeEnvironment.is_headless():
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: GPU renderer required for pixel capture (runtime.headless=true)")
		call_deferred("_finish", 1)
		return
	_apply_profile_settings()
	_apply_isolation()
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null:
		skier.landed.connect(_on_gameplay_landed)

func _parse_visual_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sunset-isolation="):
			isolation_mode = argument.trim_prefix("--sunset-isolation=").to_lower()
		elif argument.begins_with("--sunset-feature="):
			feature_isolation_name = argument.trim_prefix("--sunset-feature=")
		elif argument.begins_with("--capture-path="):
			capture_path = OutputPathGuard.sanitize(argument.trim_prefix("--capture-path="), PackedStringArray([".png"]), OUTPUT_PATH)
		elif argument.begins_with("--evidence-root="):
			evidence_root = argument.trim_prefix("--evidence-root=")
		elif argument.begins_with("--fixed-fps="):
			fixed_fps = OutputPathGuard.parse_int_range(argument.trim_prefix("--fixed-fps="), 0, 0, 240)
		elif argument.begins_with("--profile-snow-quality="):
			profile_snow_quality = OutputPathGuard.parse_int_range(argument.trim_prefix("--profile-snow-quality="), 0, 0, 1)
		elif argument.begins_with("--profile-preset="):
			profile_graphics_preset = OutputPathGuard.parse_int_range(argument.trim_prefix("--profile-preset="), -1, 0, 4)
		elif argument.begins_with("--profile-path="):
			profile_output_path = OutputPathGuard.sanitize(argument.trim_prefix("--profile-path="), PackedStringArray([".json"]), "res://.godot_user/captures/sunset_visual_profile.json")
		elif argument.begins_with("--profile-environment="):
			profile_environment = argument.trim_prefix("--profile-environment=").to_lower()
		elif argument.begins_with("--profile-commit="):
			profile_commit_sha = argument.trim_prefix("--profile-commit=")
		elif argument.begins_with("--profile-dirty="):
			profile_working_tree_dirty = argument.trim_prefix("--profile-dirty=").to_lower() == "true"
		elif argument.begins_with("--profile-render-scale="):
			profile_render_scale = OutputPathGuard.parse_finite_float(argument.trim_prefix("--profile-render-scale="), -1.0, 0.5, 1.5)

func _apply_profile_settings() -> void:
	if profile_snow_quality < 0 and profile_graphics_preset < 0:
		return
	var active := GameSettings.active.duplicate(true)
	if profile_graphics_preset >= 0:
		GameSettings.pending = active.duplicate(true)
		GameSettings.apply_preset(profile_graphics_preset)
		active = GameSettings.pending.duplicate(true)
		profile_snow_quality = int(active.get("snow_quality", 0))
	else:
		active["snow_quality"] = profile_snow_quality
	active["fps_cap"] = 0
	active["vsync_mode"] = 0
	if profile_render_scale >= 0.0:
		active["render_scale"] = profile_render_scale
	active = GameSettings._validated_settings(active)
	GameSettings.active = active
	GameSettings.pending = active.duplicate(true)
	get_viewport().scaling_3d_scale = float(active.get("render_scale", 1.0))
	get_viewport().use_taa = int(active.get("anti_aliasing", 0)) > 0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameSettings.settings_applied.emit()
	AudioManager.reset_profiling()

func _apply_isolation() -> void:
	var resort := get_node_or_null("Resort") as Node3D
	if resort == null:
		push_error("SUNSET_VISUAL_ISOLATION_FAIL: resort instance is unavailable")
		return
	match isolation_mode:
		"baseline":
			pass
		"sdfgi":
			var world_environment := resort.get("environment") as WorldEnvironment
			if world_environment == null or world_environment.environment == null:
				push_error("SUNSET_VISUAL_ISOLATION_FAIL: WorldEnvironment is unavailable for SDFGI isolation")
			else:
				world_environment.environment.sdfgi_enabled = false
		"summit":
			_set_group_visibility(resort, &"environment_summit_visual", false)
		"high_haze":
			_set_node_visibility(resort.get_node_or_null("HighHaze"), false)
		"audio":
			AudioManager.stop_feedback()
			AudioManager.set_process(false)
		"trees":
			_set_group_visibility(resort, &"park_trees", false)
		"course_dressing":
			_set_group_visibility(resort, &"course_landmarks", false)
		"distant_ridges":
			_set_group_visibility(resort, &"environment_backdrop", false)
			_set_node_visibility(resort.get_node_or_null("DistantTerrainSkirt"), false)
		"character":
			_set_node_visibility(resort.get_node_or_null("Skier"), false)
		"shadows":
			_disable_shadows(resort)
		"environment_effects":
			_disable_environment_effects(resort)
		"profiled_features":
			_hide_profiled_feature_meshes(resort)
		"profiled_feature_shadows":
			_set_profiled_feature_render_property(resort, false, true)
		"profiled_feature_gi":
			_set_profiled_feature_render_property(resort, true, false)
		"profiled_feature_unshaded":
			_set_profiled_feature_render_property(resort, false, false, true)
		"profiled_feature":
			if feature_isolation_name.is_empty():
				push_error("SUNSET_VISUAL_ISOLATION_FAIL: profiled_feature mode requires --sunset-feature=<feature name>")
				return
			_hide_profiled_feature_meshes(resort, feature_isolation_name)
		"rails_markers":
			_set_group_visibility(resort, &"park_readability_markers", false)
			_set_group_visibility(resort, &"grind_rails", false)
		"banks":
			_set_node_visibility(resort.get_node_or_null("LeftBank"), false)
			_set_node_visibility(resort.get_node_or_null("RightBank"), false)
		_:
			push_error("SUNSET_VISUAL_ISOLATION_FAIL: unknown isolation mode '%s'" % isolation_mode)
			return
	print("SUNSET_VISUAL_ISOLATION: mode=%s" % isolation_mode)

func _set_group_visibility(parent: Node, group_name: StringName, visible: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if parent.is_ancestor_of(node) or node == parent:
			_set_node_visibility(node, visible)

func _set_node_visibility(node: Node, visible: bool) -> void:
	var node_3d := node as Node3D
	if node_3d != null:
		node_3d.visible = visible

func _disable_shadows(resort: Node3D) -> void:
	for node: Node in resort.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light != null:
			light.shadow_enabled = false
	for node: Node in resort.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _disable_environment_effects(resort: Node3D) -> void:
	_set_node_visibility(resort.get_node_or_null("HighHaze"), false)
	var world_environment := resort.get("environment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	world_environment.environment.sdfgi_enabled = false
	world_environment.environment.fog_enabled = false
	world_environment.environment.volumetric_fog_enabled = false
	world_environment.environment.glow_enabled = false

func _hide_profiled_feature_meshes(resort: Node3D, feature_name: String = "") -> void:
	for body_node: Node in resort.find_children("*", "StaticBody3D", true, false):
		if not body_node.has_meta("profile_rows"):
			continue
		if not feature_name.is_empty():
			var feature_root := body_node.get_parent()
			if feature_root == null or feature_root.name != feature_name:
				continue
		for mesh_node: Node in body_node.find_children("*", "MeshInstance3D", true, false):
			_set_node_visibility(mesh_node, false)

func _set_profiled_feature_render_property(resort: Node3D, set_gi_disabled: bool, set_shadow_disabled: bool, set_unshaded: bool = false) -> void:
	var unshaded_material: StandardMaterial3D
	if set_unshaded:
		unshaded_material = StandardMaterial3D.new()
		unshaded_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		unshaded_material.albedo_color = Color("#dcecf5")
		unshaded_material.roughness = 1.0
	for body_node: Node in resort.find_children("*", "StaticBody3D", true, false):
		if not body_node.has_meta("profile_rows"):
			continue
		for mesh_node: Node in body_node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance == null:
				continue
			if set_gi_disabled:
				mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if set_shadow_disabled:
				mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if set_unshaded:
				mesh_instance.material_override = unshaded_material

func _process(delta: float) -> void:
	if frame_count > 90:
		frame_time_sum += delta
		frame_time_samples += 1
		frame_times_ms.append(delta * 1000.0)

func _physics_process(_delta: float) -> void:
	frame_count += 1
	# Reuse the production visual-inspection trajectory so the sunset capture is
	# judged from the same composed skiing/landing view as the daytime baseline.
	if frame_count == 150:
		Input.action_press("steer_right", 0.82)
	elif frame_count == 260:
		Input.action_release("steer_right")
		Input.action_press("steer_left", 1.0)
	elif frame_count == 340:
		Input.action_release("steer_left")
	elif frame_count == 430:
		Input.action_press("steer_right", 1.0)
		Input.action_press("brake", 0.88)
	elif frame_count == 485:
		Input.action_release("steer_right")
		Input.action_release("brake")
		Input.action_press("jump")
	elif frame_count == 535:
		Input.action_release("jump")
	# The deterministic fallback keeps the inspection useful even if a physics
	# backend does not emit the landing signal on exactly the same frame.
	if frame_count == 610 and not landing_captured:
		call_deferred("_capture")
	if frame_count >= 780 or (landing_captured and frame_count > 610):
		_finish(0)

func _on_gameplay_landed(_result: Dictionary) -> void:
	if landing_captured:
		return
	landing_captured = true
	for _frame in range(3):
		await get_tree().process_frame
	_capture()

func _capture() -> void:
	if _finish_started or not is_physics_processing():
		return
	set_physics_process(false)
	if RuntimeEnvironment.is_headless():
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: pixel capture is unavailable in headless mode")
		_finish(1)
		return
	RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: viewport texture was unavailable")
		_finish(1)
		return
	var image := viewport_texture.get_image()
	var absolute_path := ProjectSettings.globalize_path(capture_path)
	if image == null or image.is_empty():
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: viewport image was empty")
		_finish(1)
		return
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: %s" % error_string(error))
		_finish(1)
		return
	capture_written = true
	if evidence != null:
		if evidence.capture_image("sunset.capture", "raw", image, {
			"artifact_filename": "sunset_resort.png",
			"frame_index": frame_count,
			"time_s": snappedf(float(frame_count) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
			"state": "GROUND",
			"phase": "trajectory",
			"view": "gameplay",
			"environment": profile_environment,
			"preset": profile_graphics_preset,
			"isolation_mode": isolation_mode,
		}).is_empty():
			push_error("SUNSET_VISUAL_CAPTURE_FAIL: evidence artifact could not be written")
			_finish(1)
			return
		if not _capture_clean_analysis_image(image):
			push_error("SUNSET_VISUAL_CAPTURE_FAIL: clean analysis artifact could not be written")
			_finish(1)
			return
		evidence.record_sample("sunset.capture", {
			"time_s": snappedf(float(frame_count) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
			"frame_index": frame_count,
			"state": "GROUND",
			"phase": "trajectory",
			"view": "gameplay",
			"capture_written": true,
			"finite_telemetry": true,
		})
	print("SUNSET_VISUAL_CAPTURED: mode=%s path=%s" % [isolation_mode, absolute_path])
	_finish(0)

func _finish(exit_code: int) -> void:
	if _finish_started:
		return
	_finish_started = true
	set_process(false)
	set_physics_process(false)
	Input.action_release("steer_right")
	Input.action_release("steer_left")
	Input.action_release("brake")
	Input.action_release("jump")
	if not capture_written:
		push_error("SUNSET_VISUAL_CAPTURE_FAIL: required capture was not written")
		exit_code = 1
	var average_fps := float(frame_time_samples) / maxf(frame_time_sum, 0.001)
	var average_frame_ms := 1000.0 / maxf(average_fps, 0.001)
	var render_metrics := {
		"viewport_width": get_viewport().get_visible_rect().size.x,
		"viewport_height": get_viewport().get_visible_rect().size.y,
		"render_scale": float(GameSettings.active.get("render_scale", 1.0)),
		"graphics_preset": profile_graphics_preset,
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
	}
	var preset_names: Array[String] = ["low", "medium", "high", "ultra"]
	var preset_name: String = preset_names[profile_graphics_preset] if profile_graphics_preset >= 0 else ("fast" if profile_snow_quality == 0 else ("premium" if profile_snow_quality == 1 else "configured"))
	var render_profile := ProfileMetrics.make_profile(
		profile_environment,
		preset_name,
		isolation_mode,
		profile_commit_sha,
		profile_working_tree_dirty,
		frame_times_ms,
		render_metrics,
		AudioManager.profiling_snapshot()
	)
	render_profile["legacy"] = {
		"average_rendered_fps": average_fps,
		"average_frame_ms": average_frame_ms,
		"snow_quality": profile_snow_quality,
	}
	var validation := ProfileMetrics.validate_profile(render_profile)
	if not bool(validation.get("valid", false)):
		push_error("SUNSET_VISUAL_PROFILE_SCHEMA_FAIL: %s" % str(validation.get("errors", [])))
		exit_code = 1
	if evidence != null:
		evidence.register_scenario("sunset.profile", {
		"environment": profile_environment,
		"preset": profile_graphics_preset,
		"phase": "profile",
		"view": "gameplay",
	})
		evidence.record_check("sunset.profile.schema", "semantic", "pass" if bool(validation.get("valid", false)) else "fail", validation.get("errors", []), [], "Performance profile schema validation")
	var profile_absolute_path := ProjectSettings.globalize_path(profile_output_path)
	DirAccess.make_dir_recursive_absolute(profile_absolute_path.get_base_dir())
	var profile_file := FileAccess.open(profile_absolute_path, FileAccess.WRITE)
	if profile_file == null:
		push_error("SUNSET_VISUAL_PROFILE_FAIL: profile output could not be opened")
		exit_code = 1
	else:
		profile_file.store_string(JSON.stringify(render_profile, "\t"))
		profile_file.close()
	if evidence != null:
		var profile_artifact := evidence.write_json_artifact("sunset.profile", "profile", "sunset_visual_profile.json", render_profile, {
		"environment": profile_environment,
		"preset": profile_graphics_preset,
		"isolation_mode": isolation_mode,
	})
		if profile_artifact.is_empty():
			push_error("SUNSET_VISUAL_PROFILE_FAIL: evidence profile artifact could not be written")
			exit_code = 1
	if not FileAccess.file_exists(profile_absolute_path) or FileAccess.get_file_as_bytes(profile_absolute_path).is_empty():
		push_error("SUNSET_VISUAL_PROFILE_FAIL: profile JSON was not produced")
		exit_code = 1
	if evidence != null:
		_finish_evidence(exit_code)
	print("SUNSET_VISUAL_PERF: average rendered FPS %.1f frame_ms %.2f samples=%d" % [average_fps, average_frame_ms, frame_time_samples])
	print("SUNSET_RENDER_PROFILE: %s" % JSON.stringify(render_profile))
	var resort := get_node_or_null("Resort")
	if resort != null and resort.has_method("release_render_resources"):
		resort.call("release_render_resources")
	AudioManager.shutdown_audio()
	for child: Node in get_children():
		if is_instance_valid(child):
			child.queue_free()
	for _frame in range(10):
		await get_tree().process_frame
	if not RuntimeEnvironment.is_headless():
		await RenderingServer.frame_post_draw
		for _frame in range(4):
			await get_tree().process_frame
	get_tree().quit(exit_code)

func _finish_evidence(exit_code: int) -> void:
	if evidence == null or evidence_finished:
		return
	evidence_finished = true
	evidence.finish(exit_code)

func _capture_clean_analysis_image(_source_image: Image) -> bool:
	var ui := get_node_or_null("Resort/GameUI") as GameUI
	var previous_visible := true
	if ui != null and ui.hud_overlay != null:
		previous_visible = ui.hud_overlay.visible
		ui.hud_overlay.visible = false
	RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	var clean_image := viewport_texture.get_image() if viewport_texture != null else null
	if ui != null and ui.hud_overlay != null:
		ui.hud_overlay.visible = previous_visible
	if clean_image == null or clean_image.is_empty():
		return false
	return not evidence.capture_image("sunset.capture", "analysis", clean_image, {
		"artifact_filename": "sunset_resort_clean.png",
		"frame_index": frame_count,
		"capture_kind": "clean_analysis",
		"hud_suppressed": ui != null and ui.hud_overlay != null,
		"environment": profile_environment,
		"preset": profile_graphics_preset,
		"isolation_mode": isolation_mode,
	}).is_empty()
