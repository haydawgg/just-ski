extends Node3D

@export_range(0.05, 1.0, 0.05) var playback_rate := 0.3

const STAGE_NAMES := ["CHARGE", "POP", "TAKEOFF", "EARLY AIR", "APEX", "DESCENT"]
const STAGE_DURATION := 1.15

var rig: SkierAnimationController
var frame := SkierAnimationFrame.new()
var label: Label
var inspection_time := 0.0
var paused := false
var manual_stage := -1
var previous_stage := -1
var capture_mode := false
var capture_stage := 0

func _ready() -> void:
	_build_view()
	rig = SkierAnimationController.new()
	add_child(rig)
	capture_mode = OS.get_cmdline_user_args().has("--capture-jump-frames")
	if capture_mode:
		manual_stage = 0
		paused = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://jump_animation_frames"))
		get_tree().create_timer(16.0).timeout.connect(_on_capture_timeout)
		_run_capture()
		return
	_apply_stage(0, 0.0)

func _process(delta: float) -> void:
	if capture_mode:
		return
	if not paused and manual_stage < 0:
		inspection_time = fmod(inspection_time + delta * playback_rate, STAGE_DURATION * float(STAGE_NAMES.size()))
	var stage := manual_stage if manual_stage >= 0 else int(inspection_time / STAGE_DURATION)
	var stage_progress := 0.65 if manual_stage >= 0 else fmod(inspection_time, STAGE_DURATION) / STAGE_DURATION
	if stage != previous_stage:
		if stage == 1:
			rig.trigger(SkierAnimationController.AnimationEvent.POP, 1.0)
		elif stage == 0:
			rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
		previous_stage = stage
	_apply_stage(stage, stage_progress)
	rig.apply_frame(frame, delta * (playback_rate if manual_stage < 0 else 1.0))
	var debug := rig.debug_snapshot()
	label.text = "PHASE 5 SLOW-MOTION INSPECTION\n%s  |  air phase: %s  |  size %.2f\nSpace: pause   Left/Right: inspect stage   Down: resume loop" % [
		STAGE_NAMES[stage],
		str(debug.air_phase),
		float(debug.air_size),
	]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		paused = not paused
	elif event.is_action_pressed("ui_left"):
		manual_stage = posmod((manual_stage if manual_stage >= 0 else int(inspection_time / STAGE_DURATION)) - 1, STAGE_NAMES.size())
		paused = true
	elif event.is_action_pressed("ui_right"):
		manual_stage = posmod((manual_stage if manual_stage >= 0 else int(inspection_time / STAGE_DURATION)) + 1, STAGE_NAMES.size())
		paused = true
	elif event.is_action_pressed("ui_down"):
		manual_stage = -1
		paused = false

func _apply_stage(stage: int, progress: float) -> void:
	frame.reset()
	frame.speed_mps = 14.0
	frame.speed_ratio = 0.58
	if stage == 0:
		frame.locomotion_state = 0
		frame.grounded = true
		frame.left_grounded = true
		frame.right_grounded = true
		frame.left_contact_confidence = 1.0
		frame.right_contact_confidence = 1.0
		frame.contact_confidence = 1.0
		frame.left_ground_distance = frame.seat_distance
		frame.right_ground_distance = frame.seat_distance
		frame.left_ski_target_valid = true
		frame.right_ski_target_valid = true
		frame.left_ski_target_world = Transform3D(Basis.IDENTITY, Vector3(-0.27, -0.21, -0.11))
		frame.right_ski_target_world = Transform3D(Basis.IDENTITY, Vector3(0.27, -0.21, -0.11))
		frame.compression = lerpf(0.12, 1.0, progress)
		return
	frame.locomotion_state = 1
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 1.0
	frame.takeoff_upward_speed = 4.2
	match stage:
		1:
			frame.air_time = 0.02 + progress * 0.06
			frame.air_upward_velocity = lerpf(4.2, 3.7, progress)
		2:
			frame.air_time = 0.08 + progress * 0.1
			frame.air_upward_velocity = lerpf(3.7, 3.0, progress)
		3:
			frame.air_time = 0.2 + progress * 0.22
			frame.air_upward_velocity = lerpf(2.8, 0.9, progress)
		4:
			frame.air_time = 0.44 + progress * 0.16
			frame.air_upward_velocity = lerpf(0.55, -0.55, progress)
			frame.predicted_landing_time = 0.52
		5:
			frame.air_time = 0.64 + progress * 0.28
			frame.air_upward_velocity = lerpf(-1.2, -4.2, progress)
			frame.predicted_landing_time = lerpf(0.4, 0.16, progress)

func _run_capture() -> void:
	var stage_progress := [0.92, 0.12, 0.18, 0.45, 0.55, 0.62]
	var settle_frames := [40, 10, 18, 28, 28, 28]
	for stage: int in STAGE_NAMES.size():
		if stage == 0:
			rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
		elif stage == 1:
			rig.trigger(SkierAnimationController.AnimationEvent.POP, 1.0)
		manual_stage = stage
		previous_stage = stage
		_apply_stage(stage, float(stage_progress[stage]))
		for _settle: int in int(settle_frames[stage]):
			rig.apply_frame(frame, 1.0 / 60.0)
			await get_tree().process_frame
		var debug := rig.debug_snapshot()
		label.text = "PHASE 5 SLOW-MOTION INSPECTION\n%s  |  air phase: %s  |  size %.2f" % [
			STAGE_NAMES[stage],
			str(debug.air_phase),
			float(debug.air_size),
		]
		RenderingServer.force_draw(true)
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image == null or image.get_width() < 8:
			push_error("JUMP_INSPECTION_FAIL: viewport image was empty at %s" % STAGE_NAMES[stage])
			get_tree().quit(1)
			return
		var filename := "%02d_%s.png" % [stage + 1, STAGE_NAMES[stage].to_lower().replace(" ", "_")]
		image.save_png("user://jump_animation_frames/" + filename)
		capture_stage = stage + 1
	print("JUMP_INSPECTION_CAPTURED: ", ProjectSettings.globalize_path("user://jump_animation_frames"))
	get_tree().quit(0)

func _on_capture_timeout() -> void:
	if capture_stage < STAGE_NAMES.size():
		push_error("JUMP_INSPECTION_TIMEOUT after capturing %d stages" % capture_stage)
		get_tree().quit(1)

func _build_view() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(3.1, 1.85, 4.8)
	camera.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	add_child(light)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b9d9ec")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	add_child(environment_node)
	var snow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	snow.mesh = plane
	snow.position.y = -0.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#edf8fc")
	material.roughness = 0.94
	snow.material_override = material
	add_child(snow)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24.0, 22.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#102938"))
	canvas.add_child(label)
