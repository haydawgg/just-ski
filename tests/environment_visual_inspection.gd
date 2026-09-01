extends Node

const OUTPUT_DIRECTORY := "res://.godot_user/captures/phase_15_after"

var frame_count := 0
var frame_time_sum := 0.0
var frame_time_samples := 0
var landing_captured := false
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
		get_tree().quit(0)

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

func _on_gameplay_landed(_result: Dictionary) -> void:
	for _frame in range(3):
		await get_tree().process_frame
	_capture_gameplay_frame("gameplay_landing.png")
	landing_captured = true
