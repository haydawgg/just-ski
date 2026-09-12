extends Node

const OUTPUT_DIRECTORY := "res://.godot_user/captures/snow_depth_after"
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const OutputPathGuard := preload("res://util/output_path_guard.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")
const MOTION_BEHAVIORS := ["carve", "straight", "landing"]
const STARTUP_CHARACTER_MIN_PIXELS := 100

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
var capture_motion := false
var motion_behavior := "carve"
var motion_duration_seconds := 10.0
var motion_frame_limit := 600
var motion_capture_targets: Array[int] = []
var motion_capture_cursor := 0
var motion_scenario_id := ""
var motion_samples: Array[Dictionary] = []
var motion_landing_events: Array[Dictionary] = []
var capture_recovery := false
var recovery_scenario_id := "environment.recovery.oob"
var recovery_triggered := false
var recovery_capture_finished := false
var recovery_events: Array[Dictionary] = []
var hide_skier := false

func _ready() -> void:
	_parse_visual_arguments()
	_configure_capture_mode()
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
			"capture_mode": "recovery" if capture_recovery else ("motion" if capture_motion else "canonical"),
			"motion_behavior": motion_behavior if capture_motion else "",
			"motion_duration_s": motion_duration_seconds if capture_motion else 0.0,
		},
	})
	if capture_motion:
		motion_scenario_id = "environment.motion.%s" % motion_behavior
		evidence.register_scenario(motion_scenario_id, {"capture_mode": "motion", "behavior": motion_behavior})
	elif capture_recovery:
		evidence.register_scenario(recovery_scenario_id, {"capture_mode": "recovery", "phase": "oob"})
	_apply_visual_environment()
	get_viewport().scaling_3d_scale = visual_render_scale
	if RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: GPU renderer required for pixel capture (runtime.headless=true)")
		call_deferred("_finish", 1)
		return
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null:
		skier.landed.connect(_on_gameplay_landed)
		if hide_skier:
			# Phase 11 review variant: the static late-run frame must read as a
			# believable resort without the character carrying the composition.
			skier.visible = false
	var course_recovery := get_node_or_null("Resort/CourseRecovery")
	if course_recovery != null:
		course_recovery.connect("recovery_started", Callable(self, "_on_recovery_started"))
		course_recovery.connect("recovery_respawned", Callable(self, "_on_recovery_respawned"))
		course_recovery.connect("recovery_completed", Callable(self, "_on_recovery_completed"))

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
		elif argument == "--capture-motion":
			capture_motion = true
		elif argument == "--capture-recovery":
			capture_recovery = true
		elif argument == "--hide-skier":
			hide_skier = true
		elif argument.begins_with("--motion-behavior="):
			motion_behavior = argument.trim_prefix("--motion-behavior=").to_lower()
		elif argument.begins_with("--motion-duration="):
			motion_duration_seconds = OutputPathGuard.parse_finite_float(argument.trim_prefix("--motion-duration="), 10.0, 1.0, 30.0)

func _configure_capture_mode() -> void:
	if not MOTION_BEHAVIORS.has(motion_behavior):
		motion_behavior = "carve"
	if capture_motion and capture_recovery:
		# Keep the two evidence contracts independently reviewable. A motion run
		# wins when both flags are supplied, while the recovery run remains an
		# explicit separate invocation in the PowerShell bundle driver.
		capture_recovery = false
	if capture_motion:
		var capture_rate := fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second
		motion_frame_limit = maxi(1, int(round(motion_duration_seconds * float(capture_rate))))
		motion_capture_targets = [
			0,
			int(round(float(motion_frame_limit - 1) * 0.2)),
			int(round(float(motion_frame_limit - 1) * 0.4)),
			int(round(float(motion_frame_limit - 1) * 0.6)),
			int(round(float(motion_frame_limit - 1) * 0.8)),
			motion_frame_limit - 1,
		]

func _apply_visual_environment() -> void:
	var preset := 0
	match visual_environment:
		"golden":
			preset = 1
		"sunset":
			preset = 2
		_:
			preset = 0
	if int(GameSettings.active.get("environment_preset", 0)) == preset:
		return
	GameSettings.begin_edit()
	GameSettings.set_pending("environment_preset", preset)
	GameSettings.apply_pending()

func _process(delta: float) -> void:
	if frame_count > 90:
		frame_time_sum += delta
		frame_time_samples += 1

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if capture_motion:
		_step_motion_capture()
		return
	if capture_recovery:
		_step_recovery_capture()
		return
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

func _step_motion_capture() -> void:
	var motion_frame := frame_count - 1
	_apply_motion_inputs(motion_frame)
	_record_motion_sample(motion_frame)
	if motion_capture_cursor < motion_capture_targets.size() and motion_frame == motion_capture_targets[motion_capture_cursor]:
		var capture_slot := motion_capture_cursor
		motion_capture_cursor += 1
		call_deferred("_capture_motion_frame", motion_frame, capture_slot)
	if motion_frame >= motion_frame_limit - 1:
		call_deferred("_finish_motion_capture")

func _apply_motion_inputs(motion_frame: int) -> void:
	if motion_behavior == "straight":
		return
	if motion_frame == 75:
		Input.action_press("steer_right", 0.82)
	if motion_frame == 190:
		Input.action_release("steer_right")
		Input.action_press("steer_left", 1.0)
	if motion_frame == 285:
		Input.action_release("steer_left")
	if motion_behavior == "landing":
		if motion_frame == 365:
			Input.action_press("steer_right", 1.0)
			Input.action_press("brake", 0.88)
		if motion_frame == 410:
			Input.action_release("steer_right")
			Input.action_release("brake")
			Input.action_press("jump")
		if motion_frame == 465:
			Input.action_release("jump")

func _record_motion_sample(motion_frame: int) -> void:
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier == null:
		capture_failed = true
		return
	var camera := get_node_or_null("Resort/CameraRig") as Node3D
	var vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX
	var snapshot := skier.animation_controller.debug_snapshot() if skier.animation_controller != null else {}
	var payload := {
		"frame_index": motion_frame,
		"time_s": snappedf(float(motion_frame) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
		"behavior": motion_behavior,
		"state": _state_name(skier.state),
		"root_position_m": _vector3_array(skier.global_position),
		"velocity_mps": _vector3_array(skier.velocity),
		"grounded": skier.contact.grounded,
		"contact_normal": _vector3_array(skier.contact.average_normal),
		"skid_amount": skier.skid_amount,
		"carve_ratio": skier.current_carve_ratio,
		"edge_amount": skier.edge_amount,
		"landing_compression": snapshot.get("landing_compression", 0.0),
		"camera_position_m": _vector3_array(camera.global_position) if camera != null else _vector3_array(Vector3.ZERO),
		"camera_forward": _vector3_array(-camera.global_transform.basis.z.normalized()) if camera != null else _vector3_array(Vector3.FORWARD),
	}
	if vfx != null:
		payload["vfx"] = vfx.debug_snapshot()
	motion_samples.append(payload)
	if evidence != null:
		evidence.record_sample(motion_scenario_id, payload)

func _capture_motion_frame(motion_frame: int, capture_slot: int) -> void:
	if _finish_started or RuntimeEnvironment.is_headless():
		capture_failed = true
		return
	if motion_frame == 0:
		# The first forced draw can precede the renderer's initial camera sync and
		# read back the construction pose at the world origin. The first completed
		# render frame is the earliest frame a player can actually see.
		await RenderingServer.frame_post_draw
	else:
		RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	var image := viewport_texture.get_image() if viewport_texture != null else null
	if image == null or image.is_empty():
		capture_failed = true
		return
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	if motion_frame == 0:
		var startup_character_pixels := _count_startup_character_pixels(image)
		var startup_character_visible := startup_character_pixels >= STARTUP_CHARACTER_MIN_PIXELS
		if evidence != null:
			evidence.record_check(
				"environment.motion.startup_character_visible",
				"visual",
				"pass" if startup_character_visible else "fail",
				startup_character_pixels,
				STARTUP_CHARACTER_MIN_PIXELS,
				"Warm jacket pixels inside the expected center-frame character region"
			)
		if not startup_character_visible:
			capture_failed = true
			push_error(
				"ENVIRONMENT_VISUAL_CAPTURE_FAIL: startup frame omitted the skier (%d warm character pixels, expected at least %d)"
				% [startup_character_pixels, STARTUP_CHARACTER_MIN_PIXELS]
			)
	var filename := "motion_%02d_f%04d.png" % [capture_slot, motion_frame]
	var metadata := {
		"artifact_filename": filename,
		"frame_index": motion_frame,
		"time_s": snappedf(float(motion_frame) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
		"capture_kind": "motion_frame",
		"behavior": motion_behavior,
		"view": "gameplay",
	}
	if evidence == null or evidence.capture_image(motion_scenario_id, "motion_frame_%02d" % capture_slot, image, metadata).is_empty():
		capture_failed = true

func _count_startup_character_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var character_pixels := 0
	var minimum_x := int(image.get_width() * 0.40)
	var maximum_x := int(image.get_width() * 0.60)
	var minimum_y := int(image.get_height() * 0.25)
	var maximum_y := int(image.get_height() * 0.72)
	for y: int in range(minimum_y, maximum_y, 2):
		for x: int in range(minimum_x, maximum_x, 2):
			var color := image.get_pixel(x, y)
			if color.r > 0.58 and color.r > color.g * 1.15 and color.g > color.b * 1.05:
				character_pixels += 1
	return character_pixels

func _finish_motion_capture() -> void:
	if _finish_started:
		return
	Input.action_release("steer_right")
	Input.action_release("steer_left")
	Input.action_release("brake")
	Input.action_release("jump")
	var payload := {
		"schema_version": "visual-evidence-v1",
		"scenario_id": motion_scenario_id,
		"capture_kind": "fixed_physics_motion_sweep",
		"behavior": motion_behavior,
		"duration_s": motion_duration_seconds,
		"fixed_fps": fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second,
		"sample_count": motion_samples.size(),
		"landing_events": motion_landing_events,
	}
	if evidence == null or evidence.write_json_artifact(motion_scenario_id, "motion", "motion_trace.json", payload, {"sample_count": motion_samples.size(), "behavior": motion_behavior}).is_empty():
		capture_failed = true
	_finish(1 if capture_failed else 0)

func _step_recovery_capture() -> void:
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null and not recovery_triggered and frame_count == 90:
		recovery_triggered = true
		skier.velocity = Vector3.ZERO
		skier.global_position = Vector3(100.0, 2.0, 0.0)
	if frame_count > 360 and not recovery_capture_finished:
		capture_failed = true
		push_error("ENVIRONMENT_RECOVERY_CAPTURE_FAIL: recovery lifecycle did not complete")
		_finish(1)

func _on_recovery_started(reason: String) -> void:
	recovery_events.append({"phase": "started", "reason": reason, "frame_index": frame_count})
	call_deferred("_capture_recovery_phase", "started", reason)

func _on_recovery_respawned(reason: String, _spawn_transform: Transform3D) -> void:
	recovery_events.append({"phase": "respawned", "reason": reason, "frame_index": frame_count})
	call_deferred("_capture_recovery_phase", "respawned", reason)

func _on_recovery_completed(reason: String, _spawn_transform: Transform3D) -> void:
	recovery_events.append({"phase": "completed", "reason": reason, "frame_index": frame_count})
	call_deferred("_capture_recovery_phase", "completed", reason)

func _capture_recovery_phase(phase: String, reason: String) -> void:
	if _finish_started or RuntimeEnvironment.is_headless():
		capture_failed = true
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_capture_render_frame()
	var skier := get_node_or_null("Resort/Skier") as SkierController
	var ui := get_node_or_null("Resort/GameUI") as GameUI
	var camera := get_node_or_null("Resort/CameraRig") as Node3D
	var overlay_alpha := float(ui.recovery_overlay.color.a) if ui != null and ui.recovery_overlay != null else 0.0
	var payload := {
		"phase": phase,
		"reason": reason,
		"frame_index": frame_count,
		"time_s": snappedf(float(frame_count) / maxf(float(fixed_fps if fixed_fps > 0 else Engine.physics_ticks_per_second), 1.0), 0.001),
		"overlay_visible": ui != null and ui.recovery_overlay != null and ui.recovery_overlay.visible,
		"overlay_alpha": overlay_alpha,
		"root_position_m": _vector3_array(skier.global_position) if skier != null else _vector3_array(Vector3.ZERO),
		"velocity_mps": _vector3_array(skier.velocity) if skier != null else _vector3_array(Vector3.ZERO),
		"camera_position_m": _vector3_array(camera.global_position) if camera != null else _vector3_array(Vector3.ZERO),
	}
	if evidence != null:
		evidence.record_sample(recovery_scenario_id, payload)
		var filename := "recovery_%s.png" % phase
		var viewport_texture := get_viewport().get_texture()
		var image := viewport_texture.get_image() if viewport_texture != null else null
		if image == null or image.is_empty():
			capture_failed = true
		else:
			image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
			var metadata := {"artifact_filename": filename, "phase": phase, "reason": reason, "frame_index": frame_count, "capture_kind": "recovery_phase", "view": "gameplay"}
			if evidence.capture_image(recovery_scenario_id, "raw_%s" % phase, image, metadata).is_empty():
				capture_failed = true
	else:
		capture_failed = true
	if phase == "completed":
		var trace := {"schema_version": "visual-evidence-v1", "scenario_id": recovery_scenario_id, "capture_kind": "course_recovery_lifecycle", "events": recovery_events}
		if evidence == null or evidence.write_json_artifact(recovery_scenario_id, "recovery", "recovery_trace.json", trace).is_empty():
			capture_failed = true
		recovery_capture_finished = true
		_finish(1 if capture_failed else 0)

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
	if capture_motion:
		motion_landing_events.append({"frame_index": frame_count, "outcome": result.get("outcome", "unknown"), "impact_severity": result.get("impact_severity", 0.0)})
		return
	if capture_recovery:
		return
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
