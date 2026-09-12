extends Node

const OUTPUT_DIRECTORY := "res://.godot_user/captures/ramp_surface_after"
const ParkLayout := preload("res://world/park_features/park_layout.gd")
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const OutputPathGuard := preload("res://util/output_path_guard.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")

const SHOTS: Array[Dictionary] = [
	{"id": "approach", "label": "Tabletop approach", "feature": "SmallTable", "x": -19.0, "z": 116.0, "yaw": -15.0},
	{"id": "lip", "label": "Tabletop lip", "feature": "SmallTable", "x": -19.0, "z": 111.5, "yaw": -15.0},
	{"id": "deck", "label": "Tabletop deck and knuckle", "feature": "SmallTable", "x": -19.0, "z": 106.0, "yaw": -15.0},
	{"id": "landing", "label": "Tabletop landing", "feature": "SmallTable", "x": -19.0, "z": 96.0, "yaw": -15.0},
	{"id": "medium_deck", "label": "Medium tabletop deck", "feature": "MediumTable", "x": -19.0, "z": 8.0, "yaw": -15.0},
	{"id": "medium_landing", "label": "Medium tabletop landing", "feature": "MediumTable", "x": -19.0, "z": -8.0, "yaw": -15.0},
	{"id": "large_knuckle", "label": "Large tabletop knuckle", "feature": "LargeTable", "x": -19.0, "z": -116.0, "yaw": -15.0},
	{"id": "large_landing", "label": "Large tabletop landing", "feature": "LargeTable", "x": -19.0, "z": -138.0, "yaw": -15.0},
	{"id": "roller", "label": "Summit roller", "feature": "SummitRollerB", "x": -7.0, "z": 124.0, "yaw": -15.0},
	{"id": "berm", "label": "Upper berm", "feature": "UpperBermLeft", "x": -8.0, "z": 102.0, "yaw": -16.0},
	{"id": "side_hit", "label": "Upper side hit", "feature": "UpperLeftSideHit", "x": -28.0, "z": 101.0, "yaw": -18.0},
]

var output_directory := OUTPUT_DIRECTORY
var evidence_root := ""
var visual_environment := "daytime"
var visual_render_scale := 1.0
var visual_seed := 0
var fixed_fps := 60
var hide_guides := false
var frame_count := 0
var shot_index := 0
var capture_failed := false
var _finish_started := false
var evidence: VisualEvidenceSession


func _ready() -> void:
	_parse_visual_arguments()
	_apply_visual_environment()
	var evidence_directory := evidence_root if not evidence_root.is_empty() else output_directory
	evidence = VisualEvidence.begin({
		"suite_id": "environment",
		"evidence_root": evidence_directory,
		"fixed_fps": fixed_fps,
		"capture_width": 1280,
		"capture_height": 720,
		"context": {
			"scene": "ramp_surface_visual_inspection",
			"environment": visual_environment,
			"preset": "default",
			"render_scale": visual_render_scale,
			"seed": visual_seed,
			"renderer": "Forward Plus",
			"capture_mode": "ramp_surface_gameplay_camera",
		},
	})
	for shot: Dictionary in SHOTS:
		evidence.register_scenario(_scenario_id(shot), {"surface": shot.feature, "shot_label": shot.label})
	get_viewport().scaling_3d_scale = visual_render_scale
	if RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("RAMP_SURFACE_CAPTURE_FAIL: GPU renderer required for pixel capture")
		call_deferred("_finish", 1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if hide_guides:
		_apply_guide_hiding()
	if not _configure_gameplay_camera_fixture():
		capture_failed = true
		call_deferred("_finish", 1)
		return
	call_deferred("_capture_next_shot")


func _parse_visual_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			output_directory = OutputPathGuard.sanitize(argument.trim_prefix("--capture-dir="), PackedStringArray(), OUTPUT_DIRECTORY)
		elif argument.begins_with("--evidence-root="):
			evidence_root = argument.trim_prefix("--evidence-root=")
		elif argument.begins_with("--fixed-fps="):
			fixed_fps = OutputPathGuard.parse_int_range(argument.trim_prefix("--fixed-fps="), 60, 1, 240)
		elif argument.begins_with("--visual-render-scale="):
			visual_render_scale = OutputPathGuard.parse_finite_float(argument.trim_prefix("--visual-render-scale="), 1.0, 0.5, 1.5)
		elif argument.begins_with("--visual-environment="):
			visual_environment = argument.trim_prefix("--visual-environment=").to_lower()
		elif argument.begins_with("--visual-seed="):
			var seed_text := argument.trim_prefix("--visual-seed=")
			if seed_text.is_valid_int():
				visual_seed = int(seed_text)
		elif argument == "--hide-guides":
			hide_guides = true


func _apply_visual_environment() -> void:
	var preset := 2 if visual_environment == "sunset" else (1 if visual_environment == "golden" else 0)
	if int(GameSettings.active.get("environment_preset", 0)) == preset:
		return
	GameSettings.begin_edit()
	GameSettings.set_pending("environment_preset", preset)
	GameSettings.apply_pending()


func _apply_guide_hiding() -> void:
	# The Phase 9 gate requires the lip/knuckle/landing to read from geometry
	# and material alone; guides may stay as restrained gameplay aids afterward.
	for node: Node in get_tree().get_nodes_in_group("park_readability_markers"):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visible = false
	print("RAMP_SURFACE_GUIDES_HIDDEN: park_readability_markers suppressed for geometry review")

func _configure_gameplay_camera_fixture() -> bool:
	var skier := get_node_or_null("Resort/Skier") as SkierController
	var camera_rig := get_node_or_null("Resort/CameraRig") as SkiCameraController
	if skier == null or camera_rig == null or camera_rig.camera == null:
		push_error("RAMP_SURFACE_CAPTURE_FAIL: gameplay skier or camera rig was unavailable")
		return false
	# Freeze the real gameplay camera and skier after the runtime scene has built;
	# reset_immediate still computes the authored gameplay framing for every shot.
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	# Keep the real gameplay camera implementation and collision-safe reset, but
	# use a capture-only close framing so the acceptance images contain enough
	# ramp surface to judge texture response.
	camera_rig.follow_distance = 2.8
	camera_rig.follow_height = 0.95
	camera_rig.look_ahead_min = 5.5
	camera_rig.look_ahead_max = 8.0
	camera_rig.camera.current = true
	var ui := get_node_or_null("Resort/GameUI") as GameUI
	if ui != null:
		ui.visible = false
		ui.process_mode = Node.PROCESS_MODE_DISABLED
	return true


func _capture_next_shot() -> void:
	if _finish_started:
		return
	if shot_index >= SHOTS.size():
		_finish(1 if capture_failed else 0)
		return
	var shot := SHOTS[shot_index]
	_position_gameplay_fixture(shot)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(true)
	var image := get_viewport().get_texture().get_image() if get_viewport().get_texture() != null else null
	var scenario_id := _scenario_id(shot)
	var material_snapshot := _material_snapshot(str(shot.feature))
	var metadata := {
		"artifact_filename": "ramp_%02d_%s.png" % [shot_index, shot.id],
		"shot_index": shot_index,
		"shot_id": shot.id,
		"surface": shot.feature,
		"capture_kind": "ramp_surface_close_gameplay",
		"view": "gameplay",
		"environment": visual_environment,
		"frame_index": frame_count,
	}
	if image == null or image.is_empty() or evidence.capture_image(scenario_id, "raw", image, metadata).is_empty():
		capture_failed = true
		push_error("RAMP_SURFACE_CAPTURE_FAIL: image capture failed for %s" % shot.id)
	var skier := get_node_or_null("Resort/Skier") as SkierController
	var camera_rig := get_node_or_null("Resort/CameraRig") as SkiCameraController
	evidence.record_sample(scenario_id, {
		"shot_index": shot_index,
		"shot_id": shot.id,
		"surface": shot.feature,
		"environment": visual_environment,
		"player_position_m": _vector3_array(skier.global_position) if skier != null else _vector3_array(Vector3.ZERO),
		"camera_position_m": _vector3_array(camera_rig.global_position) if camera_rig != null else _vector3_array(Vector3.ZERO),
		"camera_forward": _vector3_array(-camera_rig.global_transform.basis.z.normalized()) if camera_rig != null else _vector3_array(Vector3.FORWARD),
		"geometry": _geometry_snapshot(str(shot.feature), camera_rig),
		"material": material_snapshot,
	})
	shot_index += 1
	call_deferred("_capture_next_shot")


func _position_gameplay_fixture(shot: Dictionary) -> void:
	var skier := get_node_or_null("Resort/Skier") as SkierController
	var camera_rig := get_node_or_null("Resort/CameraRig") as SkiCameraController
	if skier == null or camera_rig == null:
		capture_failed = true
		return
	var x := float(shot.x)
	var z := float(shot.z)
	var normal := ParkLayout.snow_normal()
	skier.global_position = ParkLayout.surface_hover(x, z, 1.15)
	skier.basis = ParkLayout.downhill_basis(float(shot.yaw))
	skier.velocity = ParkLayout.downhill() * 12.0
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = normal
	skier.contact.average_hit_position = ParkLayout.snow_at(x, z)
	camera_rig.reset_immediate()


func _material_snapshot(feature_name: String) -> Dictionary:
	var feature := get_node_or_null("Resort/%s" % feature_name)
	if feature == null:
		return {}
	for mesh_node: Node in feature.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial if mesh != null else null
		if material == null or material.shader == null:
			continue
		return {
			"role": material.get("presentation_role"),
			"texture_world_size": material.get_shader_parameter("texture_world_size"),
			"albedo_texture_strength": material.get_shader_parameter("albedo_texture_strength"),
			"normal_strength": material.get_shader_parameter("normal_strength"),
			"roughness_texture_strength": material.get_shader_parameter("roughness_texture_strength"),
			"detail_far_distance": material.get_shader_parameter("detail_far_distance"),
		}
	return {}


func _geometry_snapshot(feature_name: String, camera_rig: SkiCameraController) -> Dictionary:
	var feature := get_node_or_null("Resort/%s" % feature_name)
	if feature == null or camera_rig == null or camera_rig.camera == null:
		return {}
	var world_min := Vector3(INF, INF, INF)
	var world_max := Vector3(-INF, -INF, -INF)
	var screen_min := Vector2(INF, INF)
	var screen_max := Vector2(-INF, -INF)
	var mesh_count := 0
	for node: Node in feature.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		mesh_count += 1
		var aabb := mesh_node.mesh.get_aabb()
		for corner: Vector3 in _aabb_corners(aabb):
			var world_point := mesh_node.global_transform * corner
			world_min = world_min.min(world_point)
			world_max = world_max.max(world_point)
			var screen_point := camera_rig.camera.unproject_position(world_point)
			screen_min = screen_min.min(screen_point)
			screen_max = screen_max.max(screen_point)
	if mesh_count == 0:
		return {}
	var world_center := (world_min + world_max) * 0.5
	var center_screen := camera_rig.camera.unproject_position(world_center)
	return {
		"mesh_count": mesh_count,
		"world_min": _vector3_array(world_min),
		"world_max": _vector3_array(world_max),
		"world_center": _vector3_array(world_center),
		"center_screen": [center_screen.x, center_screen.y],
		"center_behind_camera": camera_rig.camera.is_position_behind(world_center),
		"screen_min": [screen_min.x, screen_min.y],
		"screen_max": [screen_max.x, screen_max.y],
	}


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var min_corner := aabb.position
	var max_corner := aabb.position + aabb.size
	return [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z),
	]


func _scenario_id(shot: Dictionary) -> String:
	return "environment.ramp_texture.%s" % str(shot.id)


func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _process(_delta: float) -> void:
	frame_count += 1


func _finish(exit_code: int) -> void:
	if _finish_started:
		return
	_finish_started = true
	if evidence != null:
		evidence.finish(exit_code)
	AudioManager.shutdown_audio()
	get_tree().quit(exit_code)
