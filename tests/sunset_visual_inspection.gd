extends Node

const OUTPUT_PATH := "res://.godot_user/captures/sunset_resort.png"

var frame_count := 0
var frame_time_sum := 0.0
var frame_time_samples := 0
var landing_captured := false
var isolation_mode := "baseline"
var feature_isolation_name := ""
var capture_path := OUTPUT_PATH

func _ready() -> void:
	_parse_visual_arguments()
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
			capture_path = argument.trim_prefix("--capture-path=")

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
	if not is_physics_processing():
		return
	set_physics_process(false)
	RenderingServer.force_draw(true)
	var image := get_viewport().get_texture().get_image()
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
	print("SUNSET_VISUAL_CAPTURED: mode=%s path=%s" % [isolation_mode, absolute_path])
	_finish(0)

func _finish(exit_code: int) -> void:
	var average_fps := float(frame_time_samples) / maxf(frame_time_sum, 0.001)
	print("SUNSET_VISUAL_PERF: average rendered FPS %.1f samples=%d" % [average_fps, frame_time_samples])
	AudioManager.shutdown_audio()
	get_tree().quit(exit_code)
