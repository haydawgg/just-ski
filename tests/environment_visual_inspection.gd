extends Node

const OUTPUT_DIRECTORY := "res://.godot_user/captures/snow_depth_after"
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const OutputPathGuard := preload("res://util/output_path_guard.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")

const CAPTURE_FILENAMES: Array[String] = [
	"gameplay_carve.png",
	"gameplay_transition.png",
	"gameplay_speed.png",
	"gameplay_skid.png",
	"gameplay_landing_first_contact.png",
	"gameplay_landing_impact.png",
	"gameplay_landing_compression.png",
	"gameplay_landing_recovery.png",
	"gameplay_landing.png",
]

var frame_count := 0
var frame_time_sum := 0.0
var frame_time_samples := 0
var landing_captured := false
var first_contact_failed := false
var output_directory := OUTPUT_DIRECTORY
var evidence_root := ""
var evidence: VisualEvidenceSession
var evidence_finished := false
var fixed_fps := 0
var capture_failed := false
var captured_filenames: Array[String] = []
var _finish_started := false
var visual_preset := "default"
var visual_render_scale := 1.0
var visual_environment := "daytime"
var visual_seed := 0

func _ready() -> void:
	_parse_visual_arguments()
	var evidence_directory := evidence_root if not evidence_root.is_empty() else output_directory
	if not evidence_root.is_empty():
		output_directory = evidence_root.path_join("compat")
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	_clear_capture_outputs()
	evidence = VisualEvidence.begin({
		"suite_id": "environment",
		"evidence_root": evidence_directory,
		"fixed_fps": fixed_fps,
		"capture_width": 1280,
		"capture_height": 720,
		"context": {
			"scene": "environment_visual_inspection",
			"environment": visual_environment,
			"preset": visual_preset,
			"render_scale": visual_render_scale,
			"seed": visual_seed,
			"renderer": "Forward Plus",
		},
	})
	get_viewport().scaling_3d_scale = visual_render_scale
	if RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: GPU renderer required for pixel capture (runtime.headless=true)")
		call_deferred("_finish", 1)
		return
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null:
		skier.landed.connect(_on_gameplay_landed)

func _parse_visual_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture-character-scale":
			output_directory = "res://.godot_user/captures/priority_0_scale_after"
		elif argument.begins_with("--capture-dir="):
			output_directory = OutputPathGuard.sanitize(argument.trim_prefix("--capture-dir="), PackedStringArray(), OUTPUT_DIRECTORY)
		elif argument.begins_with("--evidence-root="):
			evidence_root = argument.trim_prefix("--evidence-root=")
		elif argument.begins_with("--fixed-fps="):
			fixed_fps = OutputPathGuard.parse_int_range(argument.trim_prefix("--fixed-fps="), 0, 0, 240)
		elif argument.begins_with("--visual-preset="):
			visual_preset = argument.trim_prefix("--visual-preset=")
		elif argument.begins_with("--visual-render-scale="):
			visual_render_scale = OutputPathGuard.parse_finite_float(argument.trim_prefix("--visual-render-scale="), 1.0, 0.5, 1.5)
		elif argument.begins_with("--visual-environment="):
			visual_environment = argument.trim_prefix("--visual-environment=").to_lower()
		elif argument.begins_with("--visual-seed="):
			var seed_text := argument.trim_prefix("--visual-seed=")
			if seed_text.is_valid_int():
				visual_seed = int(seed_text)

func _process(delta: float) -> void:
	if frame_count > 90:
		frame_time_sum += delta
		frame_time_samples += 1

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count == 150:
		Input.action_press("steer_right", 0.82)
	if frame_count == 260:
		Input.action_release("steer_right")
		Input.action_press("steer_left", 1.0)
	if frame_count == 340:
		Input.action_release("steer_left")
	if frame_count == 230:
		call_deferred("_capture_gameplay_frame", "gameplay_carve.png")
	if frame_count == 315:
		call_deferred("_capture_gameplay_frame", "gameplay_transition.png")
	if frame_count == 430:
		call_deferred("_capture_gameplay_frame", "gameplay_speed.png")
		Input.action_press("steer_right", 1.0)
		Input.action_press("brake", 0.88)
	if frame_count == 470:
		call_deferred("_capture_gameplay_frame", "gameplay_skid.png")
	if frame_count == 485:
		Input.action_release("steer_right")
		Input.action_release("brake")
		Input.action_press("jump")
	if frame_count == 535:
		Input.action_release("jump")
	if frame_count >= 780 or (landing_captured and frame_count > 610):
		Input.action_release("steer_right")
		Input.action_release("steer_left")
		Input.action_release("brake")
		Input.action_release("jump")
		var average_fps := float(frame_time_samples) / maxf(frame_time_sum, 0.001)
		print("ENVIRONMENT_VISUAL_PERF: average rendered FPS %.1f with capped tracks and snow VFX" % average_fps)
		print("ENVIRONMENT_VISUAL_CAPTURED: %s" % ProjectSettings.globalize_path(output_directory))
		var missing_count := CAPTURE_FILENAMES.size() - captured_filenames.size()
		if not landing_captured:
			capture_failed = true
			push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: landing signal/captures were not produced")
		if missing_count > 0:
			capture_failed = true
			push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: %d required captures are missing" % missing_count)
		_finish(1 if capture_failed or first_contact_failed else 0)

func _capture_gameplay_frame(filename: String) -> bool:
	if _finish_started or RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: pixel capture is unavailable in headless mode")
		return false
	RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: viewport texture was unavailable")
		return false
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: viewport image was empty")
		return false
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var error := image.save_png(ProjectSettings.globalize_path(output_directory.path_join(filename)))
	if error != OK:
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: %s" % error_string(error))
		return false
	var scenario_id := _scenario_id_for_filename(filename)
	var capture_ok := true
	var metadata := {
		"artifact_filename": filename,
		"frame_index": frame_count,
		"time_s": snappedf(float(frame_count) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
		"state": "GROUND",
		"phase": _phase_for_filename(filename),
		"view": "gameplay",
	}
	if evidence != null:
		if evidence.capture_image(scenario_id, "raw", image, metadata).is_empty():
			capture_ok = false
			capture_failed = true
		if not _capture_clean_analysis_image(scenario_id, filename, metadata):
			capture_ok = false
			capture_failed = true
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier == null or skier.animation_controller == null:
		capture_ok = false
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: skier telemetry was unavailable for %s" % filename)
	else:
		var controller := skier.animation_controller
		var snapshot := controller.debug_snapshot()
		var adapter := controller.rig_adapter as SkeletonSkierRig
		var ski := adapter.equipment_nodes.get(&"left_ski") as Node3D if adapter != null else controller.left_ski
		var metrics := {
			"state_code": skier.state,
			"state": _state_name(skier.state),
			"root_position_m": _vector3_array(skier.global_position),
			"grounded": skier.contact.grounded,
			"left_grounded": skier.contact.left_grounded,
			"right_grounded": skier.contact.right_grounded,
			"average_hit_position_m": _vector3_array(skier.contact.average_hit_position),
			"left_hit_position_m": _vector3_array(skier.contact.left_hit_position),
			"compression": snapshot.get("landing_compression", 0.0),
			"pelvis_height_m": controller.pelvis.position.y,
			"left_boot_target_error_m": snapshot.get("left_boot_target_position_error", 0.0),
			"hip_rotation_rad": _vector3_array(controller.left_hip.rotation),
			"knee_rotation_rad": _vector3_array(controller.left_knee.rotation),
			"boot_rotation_rad": _vector3_array(controller.left_boot.rotation),
			"boot_target_local_m": _vector3_array(controller.to_local(controller._left_boot_target_world.origin)),
			"ski_target_error_m": _vector3_array(controller._left_ski_target_smoothed.origin - skier.animation_frame.left_ski_target_world.origin),
			"leg_ik": controller._left_leg_ik_debug,
			"visible_ski_surface_gap_m": (ski.global_position - skier.contact.left_hit_position).dot(skier.contact.left_normal) if ski != null and skier.contact.left_grounded else -1.0,
		}
		var vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX
		if vfx != null:
			var vfx_snapshot := vfx.debug_snapshot()
			metrics["vfx_mode"] = vfx_snapshot.get("mode", "none")
			metrics["landing_spray_active"] = vfx_snapshot.get("landing_spray_active", false)
			metrics["landing_amount_ratio"] = vfx_snapshot.get("landing_amount_ratio", 0.0)
		if evidence != null:
			evidence.record_sample(scenario_id, metrics)
		if filename == "gameplay_landing_first_contact.png" and skier.contact.grounded:
			var support_offset := (skier.global_position - skier.contact.average_hit_position).dot(skier.contact.average_normal)
			print("ENVIRONMENT_LANDING_FIRST_CONTACT support_offset=%.3f target=%.3f left=%s right=%s" % [support_offset, skier.profile.ground_attach_height, skier.contact.left_grounded, skier.contact.right_grounded])
			if absf(support_offset - skier.profile.ground_attach_height) > 0.12:
				first_contact_failed = true
				push_error("ENVIRONMENT_VISUAL_FAIL: first grounded frame leaves the root %.3fm from the support seat" % absf(support_offset - skier.profile.ground_attach_height))
			if evidence != null:
				evidence.record_check("environment.landing.first_contact.support_seat", "semantic", "fail" if first_contact_failed else "pass", absf(support_offset - skier.profile.ground_attach_height), 0.12, "Root-to-support seat error in metres")
		var file := FileAccess.open(ProjectSettings.globalize_path(output_directory.path_join(filename.get_basename() + ".json")), FileAccess.WRITE)
		if file == null:
			capture_ok = false
			capture_failed = true
			push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: telemetry file could not be opened for %s" % filename)
		else:
			file.store_string(JSON.stringify(VisualEvidence.normalize(metrics), "\t"))
			file.close()
	if capture_ok and not captured_filenames.has(filename):
		captured_filenames.append(filename)
	return capture_ok

func _on_gameplay_landed(result: Dictionary) -> void:
	# Capture the first grounded compression frame, then keep two recovery samples
	# so the stomp/compression handoff is reviewable.
	print("ENVIRONMENT_LANDING_CAPTURE outcome=%s severity=%.3f impact=%.3f" % [
		str(result.get("outcome", "unknown")),
		float(result.get("impact_severity", 0.0)),
		float(result.get("impact", 0.0)),
	])
	var skier := get_node_or_null("Resort/Skier") as SkierController
	var vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX if skier != null else null
	if vfx != null:
		print("ENVIRONMENT_LANDING_VFX mode=%s snow_contact=%s landing_severity=%.3f emitting=%s" % [
			str(vfx.debug_snapshot().get("mode", "none")),
			str(vfx.debug_snapshot().get("snow_contact", false)),
			float(vfx.debug_snapshot().get("landing_severity", 0.0)),
			str(vfx.landing_spray.emitting),
		])
	# The landed signal is emitted before the controller's next animation-frame
	# build. Wait through the next physics and render frames so the first evidence
	# image contains the newly-applied landing pose and contact VFX instead of the
	# final airborne render from the preceding frame.
	await get_tree().physics_frame
	await get_tree().process_frame
	await _wait_for_capture_render_frame()
	_capture_gameplay_frame("gameplay_landing_first_contact.png")
	# The root reaches the ground before the smoothed presentation layer reaches
	# its readable compression peak. Hold the impact sample until that visual
	# state is present, bounded so a failed animation cannot stall the capture.
	await _wait_for_landing_compression(0.42, 16)
	await _wait_for_capture_render_frame()
	_capture_gameplay_frame("gameplay_landing_impact.png")
	for _frame in range(3):
		await get_tree().process_frame
	await _wait_for_capture_render_frame()
	_capture_gameplay_frame("gameplay_landing_compression.png")
	for _frame in range(8):
		await get_tree().process_frame
	await _wait_for_capture_render_frame()
	_capture_gameplay_frame("gameplay_landing_recovery.png")
	# Keep the original filename as the stable entry point for existing review
	# tooling; it now represents the post-impact compression frame.
	await _wait_for_capture_render_frame()
	_capture_gameplay_frame("gameplay_landing.png")
	landing_captured = true

func _clear_capture_outputs() -> void:
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	for filename: String in CAPTURE_FILENAMES:
		var image_path := absolute_directory.path_join(filename)
		var json_path := absolute_directory.path_join(filename.get_basename() + ".json")
		if FileAccess.file_exists(image_path):
			DirAccess.remove_absolute(image_path)
		if FileAccess.file_exists(json_path):
			DirAccess.remove_absolute(json_path)

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
	if evidence != null:
		_finish_evidence(exit_code)
	var resort := get_node_or_null("Resort")
	if resort != null and resort.has_method("release_render_resources"):
		resort.call("release_render_resources")
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

func _finish_evidence(exit_code: int) -> void:
	if evidence == null or evidence_finished:
		return
	evidence_finished = true
	evidence.finish(exit_code)

func _scenario_id_for_filename(filename: String) -> String:
	var stem := filename.get_basename()
	if stem.begins_with("gameplay_landing_first_contact"):
		return "environment.landing.first_contact"
	if stem.begins_with("gameplay_landing_impact"):
		return "environment.landing.impact"
	if stem.begins_with("gameplay_landing_compression"):
		return "environment.landing.compression"
	if stem.begins_with("gameplay_landing_recovery"):
		return "environment.landing.recovery"
	if stem == "gameplay_landing":
		return "environment.landing.final"
	return "environment.trajectory.%s" % stem.trim_prefix("gameplay_")

func _phase_for_filename(filename: String) -> String:
	var stem := filename.get_basename()
	if stem.contains("landing_first_contact"):
		return "first_contact"
	if stem.contains("landing_impact"):
		return "impact"
	if stem.contains("landing_compression"):
		return "compression"
	if stem.contains("landing_recovery"):
		return "recovery"
	if stem == "gameplay_landing":
		return "post_impact"
	return stem.trim_prefix("gameplay_")

func _state_name(state_code: int) -> String:
	var names := SkierController.State.keys()
	return names[state_code] if state_code >= 0 and state_code < names.size() else "UNKNOWN"

func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _capture_clean_analysis_image(scenario_id: String, filename: String, source_metadata: Dictionary) -> bool:
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
	var clean_metadata := source_metadata.duplicate(true)
	clean_metadata["artifact_filename"] = "%s_clean.png" % filename.get_basename()
	clean_metadata["capture_kind"] = "clean_analysis"
	clean_metadata["hud_suppressed"] = ui != null and ui.hud_overlay != null
	return not evidence.capture_image(scenario_id, "analysis", clean_image, clean_metadata).is_empty()

func _wait_for_landing_compression(threshold: float, maximum_frames: int) -> void:
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier == null or skier.animation_controller == null:
		return
	for _frame in range(maximum_frames):
		await get_tree().process_frame
		var snapshot := skier.animation_controller.debug_snapshot()
		var contact_ready := skier.contact.grounded and (skier.contact.left_grounded or skier.contact.right_grounded)
		if contact_ready and float(snapshot.get("landing_compression", 0.0)) >= threshold:
			return

func _wait_for_capture_render_frame() -> void:
	if RuntimeEnvironment.is_headless():
		return
	await RenderingServer.frame_post_draw
