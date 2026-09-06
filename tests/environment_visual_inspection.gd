extends Node

const OUTPUT_DIRECTORY := "res://.godot_user/captures/phase_15_after"

var frame_count := 0
var frame_time_sum := 0.0
var frame_time_samples := 0
var landing_captured := false
var first_contact_failed := false
var output_directory := OUTPUT_DIRECTORY

func _ready() -> void:
	_parse_visual_arguments()
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null:
		skier.landed.connect(_on_gameplay_landed)

func _parse_visual_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture-character-scale":
			output_directory = "res://.godot_user/captures/priority_0_scale_after"
		elif argument.begins_with("--capture-dir="):
			output_directory = argument.trim_prefix("--capture-dir=")

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
		AudioManager.shutdown_audio()
		get_tree().quit(1 if first_contact_failed else 0)

func _capture_gameplay_frame(filename: String) -> void:
	RenderingServer.force_draw(true)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: viewport image was empty")
		return
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var error := image.save_png(ProjectSettings.globalize_path(output_directory.path_join(filename)))
	if error != OK:
		push_error("ENVIRONMENT_VISUAL_CAPTURE_FAIL: %s" % error_string(error))
	var skier := get_node_or_null("Resort/Skier") as SkierController
	if skier != null and skier.animation_controller != null:
		var controller := skier.animation_controller
		var snapshot := controller.debug_snapshot()
		var adapter := controller.rig_adapter as SkeletonSkierRig
		var ski := adapter.equipment_nodes.get(&"left_ski") as Node3D if adapter != null else controller.left_ski
		var metrics := {
			"state": skier.state,
			"root_position": str(skier.global_position),
			"grounded": skier.contact.grounded,
			"left_grounded": skier.contact.left_grounded,
			"right_grounded": skier.contact.right_grounded,
			"average_hit_position": str(skier.contact.average_hit_position),
			"left_hit_position": str(skier.contact.left_hit_position),
			"compression": snapshot.get("landing_compression", 0.0),
			"pelvis_height": controller.pelvis.position.y,
			"left_boot_target_error": snapshot.get("left_boot_target_position_error", 0.0),
			"hip_rotation": str(controller.left_hip.rotation),
			"knee_rotation": str(controller.left_knee.rotation),
			"boot_rotation": str(controller.left_boot.rotation),
			"boot_target_local": str(controller.to_local(controller._left_boot_target_world.origin)),
			"ski_target_error": str(controller._left_ski_target_smoothed.origin - skier.animation_frame.left_ski_target_world.origin),
			"leg_ik": controller._left_leg_ik_debug,
			"visible_ski_surface_gap": (ski.global_position - skier.contact.left_hit_position).dot(skier.contact.left_normal) if ski != null and skier.contact.left_grounded else -1.0,
		}
		if filename == "gameplay_landing_first_contact.png" and skier.contact.grounded:
			var support_offset := (skier.global_position - skier.contact.average_hit_position).dot(skier.contact.average_normal)
			print("ENVIRONMENT_LANDING_FIRST_CONTACT support_offset=%.3f target=%.3f left=%s right=%s" % [support_offset, skier.profile.ground_attach_height, skier.contact.left_grounded, skier.contact.right_grounded])
			if absf(support_offset - skier.profile.ground_attach_height) > 0.12:
				first_contact_failed = true
				push_error("ENVIRONMENT_VISUAL_FAIL: first grounded frame leaves the root %.3fm from the support seat" % absf(support_offset - skier.profile.ground_attach_height))
		var file := FileAccess.open(ProjectSettings.globalize_path(output_directory.path_join(filename.get_basename() + ".json")), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(metrics, "\t"))

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
	_capture_gameplay_frame("gameplay_landing_first_contact.png")
	# The root reaches the ground before the smoothed presentation layer reaches
	# its readable compression peak. Hold the impact sample until that visual
	# state is present, bounded so a failed animation cannot stall the capture.
	await _wait_for_landing_compression(0.42, 16)
	_capture_gameplay_frame("gameplay_landing_impact.png")
	for _frame in range(3):
		await get_tree().process_frame
	_capture_gameplay_frame("gameplay_landing_compression.png")
	for _frame in range(8):
		await get_tree().process_frame
	_capture_gameplay_frame("gameplay_landing_recovery.png")
	# Keep the original filename as the stable entry point for existing review
	# tooling; it now represents the post-impact compression frame.
	_capture_gameplay_frame("gameplay_landing.png")
	landing_captured = true

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
