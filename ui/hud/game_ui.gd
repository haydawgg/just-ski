class_name GameUI
extends CanvasLayer

var player: SkierController
var camera_rig: SkiCameraController
var hud_overlay: Control
var speed_label: Label
var trick_label: Label
var trick_result_label: Label
var score_label: Label
var hint_label: Label
var landing_cue_label: Label
var debug_label: Label
var notice_label: Label
var menu_backdrop: ColorRect
var pause_panel: PanelContainer
var options_panel: PanelContainer
var trick_guide_panel: PanelContainer
var results_panel: PanelContainer
var results_score_label: Label
var results_detail_label: Label
var trick_visualizer: FlickVisualizer
var rail_balance_bar: ProgressBar
var combo_timer_bar: ProgressBar
var recording_label: Label
var recovery_overlay: ColorRect
var recovery_fade_out_duration := 0.12
var recovery_fade_in_duration := 0.18
var recording_pulse := 0.0
var total_score := 0
var combo_count := 0
var combo_multiplier := 1.0
var notice_time := 0.0
var trick_result_time := 0.0
var onboarding_remaining := 8.0
var clean_capture_mode := false
const ONBOARDING_FADE_TIME := 2.5
var _stored_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	clean_capture_mode = OS.get_cmdline_user_args().has("--clean-capture")
	_build_hud()
	_build_menu_backdrop()
	_build_pause_menu()
	_build_results_panel()
	_build_trick_guide()
	_build_options_menu()
	_build_notice_overlay()
	_build_recovery_overlay()
	InputManager.device_changed.connect(_on_device_changed)
	SessionManager.marker_changed.connect(_on_marker_changed)
	InputManager.controller_connection_changed.connect(_on_controller_connection)
	GameSettings.settings_save_failed.connect(_on_settings_save_failed)
	ClipRecorder.recording_changed.connect(_on_recording_changed)
	ClipRecorder.encoding_changed.connect(_on_clip_encoding_changed)
	ClipRecorder.armed_changed.connect(_on_recorder_armed)
	ClipRecorder.clip_saved.connect(_on_clip_saved)
	ClipRecorder.clip_failed.connect(_on_clip_failed)
	ClipRecorder.clip_info.connect(_show_notice)
	_update_hint()

func bind_player(value: SkierController) -> void:
	player = value
	player.telemetry_updated.connect(_on_telemetry)
	player.trick.trick_changed.connect(_on_trick_changed)
	player.scoring.score_awarded.connect(_on_score_awarded)
	player.scoring.score_changed.connect(_on_score_changed)
	player.scoring.run_finished.connect(_on_run_finished)
	player.landed.connect(_on_landed)
	player.crashed.connect(_on_crashed)
	_on_score_changed(player.scoring.snapshot())

func bind_camera(value: SkiCameraController) -> void:
	camera_rig = value

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event.is_action_pressed("ui_cancel") and get_tree().paused):
		if trick_guide_panel.visible:
			_close_trick_guide()
		elif options_panel.visible:
			_close_options(false)
		elif get_tree().paused:
			_resume()
		elif event.is_action_pressed("pause"):
			_pause()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if hint_label != null and onboarding_remaining > 0.0 and not get_tree().paused:
		onboarding_remaining = maxf(0.0, onboarding_remaining - delta)
		hint_label.modulate.a = clampf(onboarding_remaining / ONBOARDING_FADE_TIME, 0.0, 0.82)
		hint_label.visible = onboarding_remaining > 0.0
	if notice_time > 0.0:
		notice_time -= delta
		notice_label.modulate.a = clampf(notice_time, 0.0, 1.0)
	if trick_result_time > 0.0:
		trick_result_time -= delta
		trick_result_label.modulate.a = clampf(trick_result_time / 0.55, 0.0, 1.0)
		if trick_result_time <= 0.0:
			trick_result_label.visible = false
	if recording_label != null and recording_label.visible:
		recording_pulse += delta * 3.2
		recording_label.modulate.a = 0.55 + 0.45 * sin(recording_pulse)
	if player != null and player.debug_enabled:
		debug_label.visible = true
	else:
		debug_label.visible = false

func _build_hud() -> void:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", 26)
	safe.add_theme_constant_override("margin_top", 22)
	safe.add_theme_constant_override("margin_right", 26)
	safe.add_theme_constant_override("margin_bottom", 22)
	add_child(safe)
	hud_overlay = Control.new()
	hud_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(hud_overlay)

	speed_label = _label("0 km/h", 28)
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_label.position = Vector2(0, 0)
	hud_overlay.add_child(speed_label)
	trick_label = _label("", 24)
	trick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_label.position = Vector2(360, 36)
	trick_label.size = Vector2(800, 54)
	hud_overlay.add_child(trick_label)
	trick_result_label = _label("", 20)
	trick_result_label.name = "TrickResult"
	trick_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trick_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_result_label.position = Vector2(360, 96)
	trick_result_label.size = Vector2(800, 42)
	trick_result_label.add_theme_color_override("font_color", Color("#f0cf87"))
	trick_result_label.visible = false
	hud_overlay.add_child(trick_result_label)
	landing_cue_label = _label("", 17)
	landing_cue_label.name = "LandingCue"
	landing_cue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	landing_cue_label.position = Vector2(1120, 500)
	landing_cue_label.size = Vector2(410, 36)
	landing_cue_label.modulate.a = 0.82
	landing_cue_label.visible = false
	hud_overlay.add_child(landing_cue_label)
	score_label = _label("SCORE 000000", 20)
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_label.position = Vector2(0, 42)
	hud_overlay.add_child(score_label)
	combo_timer_bar = ProgressBar.new()
	combo_timer_bar.name = "ComboTimer"
	combo_timer_bar.show_percentage = false
	combo_timer_bar.min_value = 0.0
	combo_timer_bar.max_value = 1.0
	combo_timer_bar.position = Vector2(0, 72)
	combo_timer_bar.size = Vector2(220, 7)
	combo_timer_bar.visible = false
	combo_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_overlay.add_child(combo_timer_bar)
	hint_label = _label("", 15)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.position = Vector2(0, 780)
	hint_label.size = Vector2(900, 40)
	hint_label.modulate.a = 0.82
	hud_overlay.add_child(hint_label)
	debug_label = _label("", 14)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.position = Vector2(1120, 0)
	debug_label.size = Vector2(430, 480)
	hud_overlay.add_child(debug_label)
	trick_visualizer = FlickVisualizer.new()
	trick_visualizer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trick_visualizer.position = Vector2(1240, 585)
	hud_overlay.add_child(trick_visualizer)
	rail_balance_bar = ProgressBar.new()
	rail_balance_bar.name = "RailBalance"
	rail_balance_bar.show_percentage = false
	rail_balance_bar.min_value = -1.0
	rail_balance_bar.max_value = 1.0
	rail_balance_bar.position = Vector2(560, 730)
	rail_balance_bar.size = Vector2(400, 16)
	rail_balance_bar.visible = false
	rail_balance_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_overlay.add_child(rail_balance_bar)
	recording_label = _label("● REC", 24)
	recording_label.name = "RecordingLight"
	recording_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recording_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	recording_label.position = Vector2(1300, 848)
	recording_label.size = Vector2(260, 40)
	recording_label.add_theme_color_override("font_color", Color("#ff3b30"))
	recording_label.visible = false
	hud_overlay.add_child(recording_label)

func _build_notice_overlay() -> void:
	notice_label = _label("", 22)
	notice_label.name = "NoticeLabel"
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.position = Vector2(460, 148)
	notice_label.size = Vector2(600, 40)
	notice_label.z_index = 20
	add_child(notice_label)

func _build_recovery_overlay() -> void:
	recovery_overlay = ColorRect.new()
	recovery_overlay.name = "RecoveryFade"
	recovery_overlay.color = Color(0.015, 0.035, 0.055, 0.0)
	recovery_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recovery_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recovery_overlay.z_index = 15
	recovery_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(recovery_overlay)

func _build_menu_backdrop() -> void:
	menu_backdrop = ColorRect.new()
	menu_backdrop.name = "MenuBackdrop"
	menu_backdrop.visible = false
	menu_backdrop.color = Color(0.02, 0.05, 0.09, 0.62)
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_backdrop)

func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.name = "PausePanel"
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.position = Vector2(530, 145)
	pause_panel.size = Vector2(540, 580)
	add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	pause_panel.add_child(box)
	var title := _label("SUMMIT SESSIONS", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label("PAUSED", 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_named_button("ResumeButton", "Resume", _resume))
	box.add_child(_named_button("ReturnMarkerButton", "Return to Marker", _respawn_from_menu))
	box.add_child(_named_button("SetMarkerButton", "Set Marker Here", _set_marker_from_menu))
	box.add_child(_named_button("TrickGuideButton", "Trick Guide", _open_trick_guide))
	box.add_child(_named_button("OptionsButton", "Options", _open_options))
	box.add_child(_named_button("RestartButton", "Restart from Summit", _restart_summit))
	box.add_child(_named_button("QuitButton", "Quit to Desktop", _quit_game))

func _build_results_panel() -> void:
	results_panel = PanelContainer.new()
	results_panel.name = "RunResultsPanel"
	results_panel.visible = false
	results_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	results_panel.position = Vector2(470, 125)
	results_panel.size = Vector2(660, 650)
	add_child(results_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	results_panel.add_child(box)
	var title := _label("RUN COMPLETE", 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	results_score_label = _label("SCORE 000000", 32)
	results_score_label.name = "ResultsScore"
	results_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_score_label.add_theme_color_override("font_color", Color("#ffc857"))
	box.add_child(results_score_label)
	results_detail_label = _label("", 20)
	results_detail_label.name = "ResultsDetails"
	results_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_detail_label.custom_minimum_size = Vector2(610, 220)
	box.add_child(results_detail_label)
	box.add_child(_named_button("ResultsRetryButton", "Retry from Summit", _restart_summit))
	box.add_child(_named_button("ResultsMarkerButton", "Return to Marker", _results_return_marker))
	box.add_child(_named_button("ResultsContinueButton", "Keep Riding", _results_continue))

func _build_trick_guide() -> void:
	trick_guide_panel = PanelContainer.new()
	trick_guide_panel.name = "TrickGuidePanel"
	trick_guide_panel.visible = false
	trick_guide_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	trick_guide_panel.position = Vector2(330, 55)
	trick_guide_panel.size = Vector2(940, 790)
	add_child(trick_guide_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	trick_guide_panel.add_child(box)
	var title := _label("FLICK-IT TRICK GUIDE", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 650)
	box.add_child(scroll)
	var guide := VBoxContainer.new()
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.add_theme_constant_override("separation", 12)
	scroll.add_child(guide)
	_add_guide_section(guide, "TAKEOFFS", [
		"Right stick down → up: straight pop",
		"Right stick down → left/right: pop into spin",
		"Right stick down → diagonal: pop into cork",
	])
	_add_guide_section(guide, "AIR ROTATIONS", [
		"After takeoff, recenter once to arm airborne management",
		"Hold the committed direction to compact and preserve angular momentum",
		"Hold the opposite direction to open up and check the rotation",
		"Airborne input shapes body and inertia; it does not create repeated rotation impulses",
		"Left stick provides a finite yaw trim",
	])
	_add_guide_section(guide, "GRABS & TWEAKS", [
		"LT/L2: left hand   •   RT/R2: right hand   •   Both: double grab",
		"Trigger + inward stick: mute   •   Trigger + up: Japan",
		"Left trigger + down: tail   •   Right trigger + down: nose",
		"Both + up: spread eagle   •   Both + down: daffy",
		"Triggers must be released after takeoff before the first grab",
	])
	_add_guide_section(guide, "RAILS", [
		"Neutral entry: 50-50   •   Flick left/right: boardslide",
		"Down → up: pop off   •   Left stick: balance",
	])
	box.add_child(_named_button("TrickGuideBack", "Back", _close_trick_guide))

func _add_guide_section(parent: VBoxContainer, heading: String, lines: Array[String]) -> void:
	var heading_label := _label(heading, 20)
	heading_label.add_theme_color_override("font_color", Color("#ffc857"))
	parent.add_child(heading_label)
	for line: String in lines:
		var label := _label("  " + line, 17)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(label)

func _build_options_menu() -> void:
	options_panel = PanelContainer.new()
	options_panel.name = "OptionsPanel"
	options_panel.visible = false
	options_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	options_panel.position = Vector2(365, 58)
	options_panel.size = Vector2(870, 785)
	add_child(options_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	options_panel.add_child(box)
	var title := _label("OPTIONS — CHANGES ARE STAGED", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(820, 620)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	var display_tab := VBoxContainer.new()
	display_tab.name = "Display"
	display_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(display_tab)
	var mode := OptionButton.new()
	mode.name = "DisplayMode"
	for text: String in ["Windowed", "Fullscreen", "Exclusive Fullscreen"]:
		mode.add_item(text)
	display_tab.add_child(_row("Display mode", mode))
	mode.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("display_mode", index))
	var resolution := OptionButton.new()
	resolution.name = "Resolution"
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		resolution.add_item("%d × %d" % [size.x, size.y])
		resolution.set_item_metadata(resolution.item_count - 1, size)
	display_tab.add_child(_row("Resolution", resolution))
	resolution.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("resolution", resolution.get_item_metadata(index)))
	var vsync := OptionButton.new()
	vsync.name = "VSync"
	for text: String in ["Disabled", "Enabled", "Adaptive"]:
		vsync.add_item(text)
	display_tab.add_child(_row("Vertical sync", vsync))
	vsync.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("vsync_mode", index))
	var fps_cap := SpinBox.new()
	fps_cap.name = "FPSCap"
	fps_cap.min_value = 0
	fps_cap.max_value = 360
	fps_cap.step = 10
	fps_cap.suffix = " fps (0 = unlimited)"
	display_tab.add_child(_row("Frame-rate cap", fps_cap))
	fps_cap.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("fps_cap", int(value)))

	var graphics_tab := VBoxContainer.new()
	graphics_tab.name = "Graphics"
	graphics_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(graphics_tab)
	var preset := OptionButton.new()
	preset.name = "Preset"
	for text: String in ["Low", "Medium", "High", "Ultra", "Custom"]:
		preset.add_item(text)
	graphics_tab.add_child(_row("Graphics preset", preset))
	preset.item_selected.connect(func(index: int) -> void:
		GameSettings.apply_preset(index)
		_sync_options()
	)
	var scale := HSlider.new()
	scale.name = "RenderScale"
	scale.min_value = 0.5
	scale.max_value = 1.5
	scale.step = 0.05
	graphics_tab.add_child(_row("3D render scale", scale))
	scale.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("render_scale", value))
	var anti_aliasing := OptionButton.new()
	anti_aliasing.name = "AntiAliasing"
	for text: String in ["Off", "TAA"]:
		anti_aliasing.add_item(text)
	graphics_tab.add_child(_row("Anti-aliasing", anti_aliasing))
	anti_aliasing.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("anti_aliasing", index))
	var shadow_quality := OptionButton.new()
	shadow_quality.name = "ShadowQuality"
	for text: String in ["Low", "Medium", "High", "Ultra"]:
		shadow_quality.add_item(text)
	graphics_tab.add_child(_row("Shadow quality", shadow_quality))
	shadow_quality.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("shadow_quality", index))
	var snow_quality := OptionButton.new()
	snow_quality.name = "SnowQuality"
	for text: String in ["Fast", "Premium"]:
		snow_quality.add_item(text)
	graphics_tab.add_child(_row("Snow quality", snow_quality))
	snow_quality.item_selected.connect(func(index: int) -> void: GameSettings.set_pending("snow_quality", index))
	var ssao := CheckButton.new()
	ssao.name = "SSAO"
	ssao.text = "Enabled"
	graphics_tab.add_child(_row("Ambient occlusion", ssao))
	ssao.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("ssao_enabled", value))
	var ssil := CheckButton.new()
	ssil.name = "SSIL"
	ssil.text = "Enabled"
	graphics_tab.add_child(_row("Indirect screen light", ssil))
	ssil.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("ssil_enabled", value))
	var ssr := CheckButton.new()
	ssr.name = "SSR"
	ssr.text = "Enabled"
	graphics_tab.add_child(_row("Screen-space reflections", ssr))
	ssr.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("ssr_enabled", value))
	var fog := CheckButton.new()
	fog.name = "Fog"
	fog.text = "Enabled"
	graphics_tab.add_child(_row("Mountain fog", fog))
	fog.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("fog_enabled", value))
	var gi := CheckButton.new()
	gi.name = "GI"
	gi.text = "Enabled"
	graphics_tab.add_child(_row("Global illumination", gi))
	gi.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("gi_enabled", value))

	var audio_tab := VBoxContainer.new()
	audio_tab.name = "Audio"
	audio_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(audio_tab)
	var master := HSlider.new()
	master.name = "Master"
	master.min_value = -30.0
	master.max_value = 0.0
	master.step = 1.0
	audio_tab.add_child(_row("Master volume", master))
	master.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("master_volume_db", value))
	var music := HSlider.new()
	music.name = "Music"
	music.min_value = -30.0
	music.max_value = 0.0
	music.step = 1.0
	audio_tab.add_child(_row("Music volume", music))
	music.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("music_volume_db", value))
	var sfx := HSlider.new()
	sfx.name = "SFX"
	sfx.min_value = -30.0
	sfx.max_value = 0.0
	sfx.step = 1.0
	audio_tab.add_child(_row("Effects volume", sfx))
	sfx.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("sfx_volume_db", value))

	var gameplay_tab := VBoxContainer.new()
	gameplay_tab.name = "Gameplay"
	gameplay_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(gameplay_tab)
	var mph := CheckButton.new()
	mph.name = "MPH"
	mph.text = "Use mph"
	gameplay_tab.add_child(_row("Speed units", mph))
	mph.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("units_mph", value))
	var assist := HSlider.new()
	assist.name = "LandingAssist"
	assist.min_value = 0.0
	assist.max_value = 1.0
	assist.step = 0.05
	gameplay_tab.add_child(_row("Landing assist", assist))
	assist.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("landing_assist", value))
	var visualizer_toggle := CheckButton.new()
	visualizer_toggle.name = "TrickVisualizerToggle"
	visualizer_toggle.text = "Enabled"
	gameplay_tab.add_child(_row("Flick-It visualizer", visualizer_toggle))
	visualizer_toggle.toggled.connect(func(value: bool) -> void: GameSettings.set_pending("trick_visualizer_enabled", value))

	var controller_tab := VBoxContainer.new()
	controller_tab.name = "Controller"
	controller_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(controller_tab)
	var rumble := HSlider.new()
	rumble.name = "Rumble"
	rumble.min_value = 0.0
	rumble.max_value = 1.0
	rumble.step = 0.05
	controller_tab.add_child(_row("Rumble strength", rumble))
	rumble.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("controller_rumble", value))
	var deadzone := HSlider.new()
	deadzone.name = "Deadzone"
	deadzone.min_value = 0.0
	deadzone.max_value = 0.4
	deadzone.step = 0.01
	controller_tab.add_child(_row("Inner deadzone", deadzone))
	deadzone.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("stick_deadzone", value))
	var outer := HSlider.new()
	outer.name = "OuterDeadzone"
	outer.min_value = 0.0
	outer.max_value = 0.25
	outer.step = 0.01
	controller_tab.add_child(_row("Outer deadzone", outer))
	outer.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("stick_outer_deadzone", value))
	var response := HSlider.new()
	response.name = "Response"
	response.min_value = 0.5
	response.max_value = 3.0
	response.step = 0.05
	controller_tab.add_child(_row("Stick response curve", response))
	response.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("stick_response", value))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	buttons.add_child(_named_button("ApplyButton", "Apply", _apply_options))
	buttons.add_child(_named_button("CancelButton", "Cancel", _cancel_options))
	buttons.add_child(_named_button("ResetButton", "Reset Defaults", _reset_options))

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(label_text, 18)
	label.custom_minimum_size = Vector2(310, 48)
	control.custom_minimum_size = Vector2(300, 48)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#f4fbff"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.09, 0.42))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("outline_size", 2)
	return label

func _named_button(button_name: String, text: String, callback: Callable) -> Button:
	var button := _button(text, callback)
	button.name = button_name
	return button

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(260, 52)
	button.pressed.connect(callback)
	return button

func _focus_first_pause_button() -> void:
	var resume := pause_panel.find_child("ResumeButton", true, false) as Button
	if resume != null:
		resume.grab_focus()
		return
	for node: Node in pause_panel.find_children("*", "Button", true, false):
		(node as Button).grab_focus()
		break

func _set_menu_visible(panel: Control) -> void:
	menu_backdrop.visible = true
	pause_panel.visible = panel == pause_panel
	results_panel.visible = panel == results_panel
	trick_guide_panel.visible = panel == trick_guide_panel
	options_panel.visible = panel == options_panel

func _pause() -> void:
	_stored_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	AudioManager.stop_feedback()
	_set_menu_visible(pause_panel)
	_focus_first_pause_button()

func _resume() -> void:
	options_panel.visible = false
	trick_guide_panel.visible = false
	pause_panel.visible = false
	results_panel.visible = false
	menu_backdrop.visible = false
	hud_overlay.visible = true
	get_tree().paused = false
	Input.mouse_mode = _stored_mouse_mode

func _respawn_from_menu() -> void:
	if not SessionManager.has_marker:
		_show_notice("NO MARKER SET")
		_focus_first_pause_button()
		return
	SessionManager.request_respawn()
	_show_notice("RETURNED TO MARKER")
	_resume()

func _set_marker_from_menu() -> void:
	if player == null or not player.contact.grounded:
		_show_notice("NEED SNOW CONTACT")
		_focus_first_pause_button()
		return
	SessionManager.set_marker(player.global_transform.translated_local(Vector3.UP * 0.5))
	_resume()

func _restart_summit() -> void:
	SessionManager.clear_marker()
	if player != null and player.scoring != null:
		player.scoring.reset_run()
	else:
		total_score = 0
		_reset_combo()
		score_label.text = "SCORE 000000"
	SessionManager.request_respawn()
	_show_notice("RESTART FROM SUMMIT")
	_resume()

func _results_return_marker() -> void:
	if not SessionManager.has_marker:
		_show_notice("NO MARKER SET")
		return
	if player != null and player.scoring != null:
		player.scoring.reset_run()
	SessionManager.request_respawn()
	_show_notice("NEW RUN FROM MARKER")
	_resume()

func _results_continue() -> void:
	if player != null and player.scoring != null:
		player.scoring.reset_run()
	_show_notice("FREE RIDE")
	_resume()

func _quit_game() -> void:
	AudioManager.shutdown_audio()
	get_tree().quit()

func _open_trick_guide() -> void:
	_set_menu_visible(trick_guide_panel)
	(trick_guide_panel.find_child("TrickGuideBack", true, false) as Button).grab_focus()

func _close_trick_guide() -> void:
	_set_menu_visible(pause_panel)
	var guide_button := pause_panel.find_child("TrickGuideButton", true, false) as Button
	if guide_button != null:
		guide_button.grab_focus()

func _open_options() -> void:
	GameSettings.begin_edit()
	_set_menu_visible(options_panel)
	_sync_options()
	(options_panel.find_child("Preset", true, false) as OptionButton).grab_focus()

func _sync_options() -> void:
	(options_panel.find_child("DisplayMode", true, false) as OptionButton).select(int(GameSettings.pending["display_mode"]))
	var resolution_control := options_panel.find_child("Resolution", true, false) as OptionButton
	for index: int in resolution_control.item_count:
		if resolution_control.get_item_metadata(index) == GameSettings.pending["resolution"]:
			resolution_control.select(index)
			break
	(options_panel.find_child("VSync", true, false) as OptionButton).select(clampi(int(GameSettings.pending["vsync_mode"]), 0, 2))
	(options_panel.find_child("FPSCap", true, false) as SpinBox).set_value_no_signal(float(GameSettings.pending["fps_cap"]))
	(options_panel.find_child("Preset", true, false) as OptionButton).select(int(GameSettings.pending["graphics_preset"]))
	(options_panel.find_child("RenderScale", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["render_scale"]))
	(options_panel.find_child("AntiAliasing", true, false) as OptionButton).select(clampi(int(GameSettings.pending["anti_aliasing"]), 0, 1))
	(options_panel.find_child("ShadowQuality", true, false) as OptionButton).select(clampi(int(GameSettings.pending["shadow_quality"]), 0, 3))
	(options_panel.find_child("SnowQuality", true, false) as OptionButton).select(clampi(int(GameSettings.pending["snow_quality"]), 0, 1))
	(options_panel.find_child("SSAO", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssao_enabled"]))
	(options_panel.find_child("SSIL", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssil_enabled"]))
	(options_panel.find_child("SSR", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssr_enabled"]))
	(options_panel.find_child("Fog", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["fog_enabled"]))
	(options_panel.find_child("GI", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["gi_enabled"]))
	(options_panel.find_child("Master", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["master_volume_db"]))
	(options_panel.find_child("Music", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["music_volume_db"]))
	(options_panel.find_child("SFX", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["sfx_volume_db"]))
	(options_panel.find_child("MPH", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["units_mph"]))
	(options_panel.find_child("LandingAssist", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["landing_assist"]))
	(options_panel.find_child("TrickVisualizerToggle", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["trick_visualizer_enabled"]))
	(options_panel.find_child("Rumble", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["controller_rumble"]))
	(options_panel.find_child("Deadzone", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["stick_deadzone"]))
	(options_panel.find_child("OuterDeadzone", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["stick_outer_deadzone"]))
	(options_panel.find_child("Response", true, false) as HSlider).set_value_no_signal(float(GameSettings.pending["stick_response"]))

func _apply_options() -> void:
	GameSettings.apply_pending()
	_close_options(true)

func _cancel_options() -> void:
	_close_options(false)

func _reset_options() -> void:
	GameSettings.reset_pending()
	_sync_options()

func _close_options(applied: bool) -> void:
	if not applied:
		GameSettings.cancel_pending()
	_set_menu_visible(pause_panel)
	var options_button := pause_panel.find_child("OptionsButton", true, false) as Button
	if options_button != null:
		options_button.grab_focus()
	else:
		_focus_first_pause_button()

func _on_telemetry(data: Dictionary) -> void:
	var speed := float(data.speed_mps) * (2.23694 if bool(GameSettings.active["units_mph"]) else 3.6)
	speed_label.text = "%d %s" % [roundi(speed), "mph" if bool(GameSettings.active["units_mph"]) else "km/h"]
	var animation: Dictionary = data.get("animation", {})
	var flick_data: Dictionary = data.get("flick", {})
	var crash_data: Dictionary = data.get("crash", {})
	var landing_time := float(data.get("predicted_landing_time", -1.0))
	var landing_readiness_valid := bool(animation.get("landing_readiness_valid", false))
	var pre_bail_weight := float(animation.get("pre_bail_weight", 0.0))
	var landing_imminent := (
		bool(data.get("landing_feedback_armed", false))
		and bool(data.get("predicted_landing_valid", false))
		and str(data.get("state", "")) == "AIR"
		and landing_time >= 0.0
		and landing_time < 0.55
		and pre_bail_weight < 0.62
		and landing_readiness_valid
	)
	landing_cue_label.visible = landing_imminent
	if landing_imminent:
		var ready := bool(animation.get("landing_ready", false))
		landing_cue_label.text = "LANDING SET" if ready else "PREPARE LANDING"
		landing_cue_label.add_theme_color_override("font_color", Color("#8fd5cd") if ready else Color("#e4c37b"))
	if trick_visualizer != null:
		trick_visualizer.apply_snapshot(flick_data)
	var score_data: Dictionary = data.get("scoring", {})
	if combo_timer_bar != null:
		var combo_window := maxf(float(score_data.get("combo_window", 1.0)), 0.01)
		combo_timer_bar.value = float(score_data.get("combo_remaining", 0.0)) / combo_window
		combo_timer_bar.visible = combo_count > 0
	if rail_balance_bar != null:
		rail_balance_bar.value = float(data.get("rail_balance", 0.0))
		rail_balance_bar.visible = str(data.state) == "GRIND"
	debug_label.text = "FPS %d\nPhysics %d Hz\nState %s\nGrounded %s (%.2f)\nSurface %s\nSpeed %.2f m/s  Slope %.1f°\nNormal %s\nSteer raw %.2f  shaped %.2f  rate %.2f\nHeading/travel %.1f°\nEdge %.2f  carve %.2f  skid %.2f\nGrip %.2f  demand %.2f\nBrake %.2f  pressure %.2f  landing ctrl %.2f\nLateral slip %.2f  carve force %.2f\nAngular %s\nRail %s (bal %.2f prog %.2f toEnd %.1f)\nFlick %s / %s\nAnim %s\nPose %s\nAnim blend %.2f\nAir %s size %.2f anticip %.2f\nLand %s sev %.2f bal %.2f cmp %.2f\nRailAnim %s inf %.2f appr %.2f entrySev %.2f cmp %.2f slide %.2f exit %.2f" % [
		Engine.get_frames_per_second(), Engine.physics_ticks_per_second, data.state, data.grounded, data.contact_confidence,
		data.get("surface", "Powder"), data.speed_mps, data.get("slope_angle_degrees", 0.0), data.surface_normal,
		data.get("steering_raw", 0.0), data.get("steering", 0.0), data.get("effective_steer_rate", 0.0),
		data.get("heading_travel_angle_degrees", 0.0), data.edge, data.get("carve_ratio", 1.0), data.get("skid_amount", 0.0),
		data.get("available_grip", 0.0), data.get("centripetal_demand", 0.0), data.get("brake_amount", 0.0), data.get("pressure", 0.0), data.get("landing_control_multiplier", 1.0),
		data.lateral_slip, data.carve_force, data.angular_velocity, data.rail,
		data.get("rail_balance", 0.0), data.get("rail_progress", 0.0), data.get("rail_distance_to_end", 0.0),
		flick_data.get("kind", "NONE"), flick_data.get("phase", "NEUTRAL"),
		animation.get("state", "—"), animation.get("pose", "—"), animation.get("blend", 0.0),
		animation.get("air_phase", "—"), animation.get("air_size", 0.0), animation.get("jump_anticipation", 0.0),
		animation.get("landing_phase", "Idle"), animation.get("landing_severity", 0.0), animation.get("landing_balance_error", 0.0), animation.get("landing_compression", 0.0),
		animation.get("rail_phase", "Idle"), animation.get("rail_influence", 0.0), animation.get("rail_approach_anticipation", 0.0),
		animation.get("rail_entry_severity", 0.0), animation.get("rail_entry_compression", 0.0), animation.get("rail_slide_angle", 0.0), animation.get("rail_exit_anticipation", 0.0)]
	debug_label.text += "\nTrickAnim active %s intent %s dir %.0f pose %.2f prewind %.2f compact %.2f spot %.2f\nRates y/p/r %.2f %.2f %.2f  residual %s  landBlend %.2f" % [
		animation.get("trick_active", false), animation.get("trick_intent", false), animation.get("spin_direction", 0.0),
		animation.get("trick_pose_weight", 0.0), animation.get("prewind_weight", 0.0), animation.get("spin_compactness", 0.0),
		animation.get("spotting_weight", 0.0), animation.get("root_yaw_rate", 0.0), animation.get("root_pitch_rate", 0.0),
		animation.get("root_roll_rate", 0.0), animation.get("rotation_residual", Vector3.ZERO), animation.get("landing_blend", 0.0)]
	debug_label.text += "\nLanding readiness valid %s ant %.2f ready %.2f [%0.2f %0.2f %0.2f %0.2f %0.2f] projHead %.1f° projResidual %.1f°" % [
		animation.get("landing_readiness_valid", false),
		animation.get("landing_anticipation", 0.0), animation.get("landing_readiness", 0.0),
		animation.get("landing_readiness_heading", 0.0), animation.get("landing_readiness_pitch", 0.0),
		animation.get("landing_readiness_spin", 0.0), animation.get("landing_readiness_upright", 0.0),
		animation.get("landing_readiness_residual", 0.0),
		rad_to_deg(float(animation.get("landing_projected_heading_error", 0.0))),
		rad_to_deg(float(animation.get("landing_projected_residual", 0.0)))]
	debug_label.text += "\nGrab %s %s hand %s ski %s pose %.2f contact %.2f reach %.2f hold %.2f" % [
		animation.get("grab_type", "—"), animation.get("grab_phase", "IDLE"), animation.get("grab_hand", "NONE"),
		animation.get("grab_target_ski", "NONE"), animation.get("grab_pose_weight", 0.0),
		animation.get("grab_contact_weight", 0.0), animation.get("grab_reach_error", 0.0), animation.get("grab_hold_time", 0.0)]
	debug_label.text += "\nContact class %s  snow VFX %s" % [data.get("surface_class", "UNKNOWN"), data.get("snow_contact", true)]
	debug_label.text += "\nRig %s (requested %s)%s" % [
		animation.get("rig_adapter", "none"), animation.get("rig_requested", "none"),
		(" fallback: " + str(animation.get("rig_fallback_reason", ""))) if not str(animation.get("rig_fallback_reason", "")).is_empty() else ""]
	var torso_follow := animation.get("torso_follow_through", Vector3.ZERO) as Vector3
	var left_arm_inertia := animation.get("left_arm_inertia", Vector3.ZERO) as Vector3
	var right_arm_inertia := animation.get("right_arm_inertia", Vector3.ZERO) as Vector3
	var left_pole_inertia := animation.get("left_pole_inertia", Vector3.ZERO) as Vector3
	var right_pole_inertia := animation.get("right_pole_inertia", Vector3.ZERO) as Vector3
	debug_label.text += "\nPolish accel lat %.2f vert %.2f yaw %.2f  lag torso %.3f arm %.3f pole %.3f  weight %.2f" % [
		animation.get("lateral_accel_filtered", 0.0), animation.get("vertical_accel_filtered", 0.0),
		animation.get("yaw_accel_filtered", 0.0), torso_follow.length(),
		maxf(left_arm_inertia.length(), right_arm_inertia.length()),
		maxf(left_pole_inertia.length(), right_pole_inertia.length()),
		animation.get("secondary_motion_weight", 0.0)]
	var crash_reason := str(crash_data.get("reason", "NONE"))
	var crash_stage := str(crash_data.get("stage", "NONE"))
	debug_label.text += "\nCrash %s / %s src %s impact %.2f angular %.2f balance %.2f rest %s t %.2f" % [
		crash_reason,
		crash_stage,
		crash_data.get("source", "NONE"),
		crash_data.get("impact_speed", 0.0),
		crash_data.get("angular_speed", 0.0),
		crash_data.get("balance_error", 0.0),
		crash_data.get("rest_detected", false),
		crash_data.get("elapsed", 0.0)]
	debug_label.text += "\nCrash collider %s asset %s layer %s normal %s" % [
		crash_data.get("collision_collider", "—"), crash_data.get("collision_asset_id", "—"),
		crash_data.get("collision_layer", 0), crash_data.get("collision_normal", Vector3.UP)]
	if camera_rig != null:
		debug_label.text += "\n" + camera_rig.debug_summary()

func _on_trick_changed(text: String) -> void:
	trick_label.text = text
	trick_label.visible = not text.is_empty()
	if not text.is_empty():
		trick_result_time = 0.0
		trick_result_label.visible = false

func _on_score_awarded(text: String, awarded: int, quality: float, outcome: int, snapshot: Dictionary) -> void:
	_on_score_changed(snapshot)
	var link_note := "  LINE" if text.begins_with("Line Link") else ""
	_show_trick_result("%s  +%d  [%s]%s" % [text, awarded, _quality_name(outcome), link_note])

func _on_score_changed(snapshot: Dictionary) -> void:
	total_score = int(snapshot.get("total_score", 0))
	combo_count = int(snapshot.get("combo_count", 0))
	combo_multiplier = float(snapshot.get("combo_multiplier", 1.0))
	var combo_text := "" if combo_count <= 1 else "  x%.1f (%d)" % [combo_multiplier, combo_count]
	score_label.text = "SCORE %06d%s" % [total_score, combo_text]

func _on_run_finished(snapshot: Dictionary) -> void:
	var score := int(snapshot.get("total_score", 0))
	var previous_best := SessionManager.best_score
	var personal_best := SessionManager.submit_score(score)
	var medal := _medal_for_score(score)
	var next_target := _next_medal_target(score)
	var best_name := str(snapshot.get("best_trick_name", ""))
	var best_points := int(snapshot.get("best_trick_points", 0))
	if best_name.is_empty():
		best_name = "No scored trick"
	results_score_label.text = "SCORE %06d  •  %s" % [score, medal]
	var record_line := "NEW PERSONAL BEST" if personal_best else "PERSONAL BEST %06d" % maxi(previous_best, SessionManager.best_score)
	var target_line := "All medal targets cleared" if next_target <= 0 else "%d points to the next medal" % maxi(0, next_target - score)
	results_detail_label.text = "%s\n\nBest trick: %s  (+%d)\nLanded tricks: %d  •  Clean: %d  •  Bails: %d\n\n%s" % [
		record_line,
		best_name,
		best_points,
		int(snapshot.get("landed_trick_count", 0)),
		int(snapshot.get("clean_trick_count", 0)),
		int(snapshot.get("bail_count", 0)),
		target_line,
	]
	var marker_button := results_panel.find_child("ResultsMarkerButton", true, false) as Button
	if marker_button != null:
		marker_button.disabled = not SessionManager.has_marker
	_stored_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	AudioManager.stop_feedback()
	hud_overlay.visible = false
	_set_menu_visible(results_panel)
	var retry := results_panel.find_child("ResultsRetryButton", true, false) as Button
	if retry != null:
		retry.grab_focus()

func _on_landed(result: Dictionary) -> void:
	_show_trick_result(_quality_name(int(result.get("outcome", LandingSolver.Outcome.BAIL))) + " LANDING")

func _on_crashed() -> void:
	_show_notice("BAIL — recover on snow")

func _reset_combo() -> void:
	if player != null and player.scoring != null:
		player.scoring.reset_combo()
	else:
		combo_count = 0
		combo_multiplier = 1.0
		score_label.text = "SCORE %06d" % total_score

func _on_marker_changed(_position: Vector3) -> void:
	_show_notice("SESSION MARKER SAVED")

func _on_controller_connection(connected: bool) -> void:
	_show_notice("CONTROLLER CONNECTED" if connected else "CONTROLLER DISCONNECTED — KEYBOARD ACTIVE")

func _on_settings_save_failed(error: Error) -> void:
	_show_notice("SETTINGS COULD NOT BE SAVED (%d)" % int(error))

func notify_course_recovery(reason: String = "") -> void:
	_show_notice("RETURNING TO THE SLOPE" if reason.is_empty() else "RETURNING TO THE SLOPE — %s" % reason.replace("_", " "))
	if recovery_overlay == null:
		return
	recovery_overlay.visible = true
	recovery_overlay.color.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(recovery_overlay, "color:a", 1.0, maxf(recovery_fade_out_duration, 0.0))

func complete_course_recovery(_reason: String = "", _spawn_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if recovery_overlay == null:
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(recovery_overlay, "color:a", 0.0, maxf(recovery_fade_in_duration, 0.0))
	tween.tween_callback(func() -> void:
		recovery_overlay.visible = false
	)

func _on_recorder_armed(value: bool) -> void:
	if recording_label != null:
		# Arming is an internal capture state; keep the gameplay HUD quiet until
		# frames are actually being recorded or encoded.
		recording_label.visible = false
		recording_label.text = "● REC ARMED"
		recording_label.add_theme_color_override("font_color", Color("#ffc857"))
	recording_pulse = 0.0

func _on_recording_changed(active: bool) -> void:
	if recording_label != null:
		recording_label.visible = active and not clean_capture_mode
		recording_label.text = "● REC"
		recording_label.add_theme_color_override("font_color", Color("#ff3b30"))
	recording_pulse = 0.0
	if active and not clean_capture_mode:
		_show_notice("RECORDING — F9 TO STOP")

func _on_clip_encoding_changed(active: bool) -> void:
	if recording_label != null:
		recording_label.visible = active and not clean_capture_mode
		recording_label.text = "● ENC"
		recording_label.add_theme_color_override("font_color", Color("#ffc857"))
	recording_pulse = 0.0
	if active and not clean_capture_mode:
		_show_notice("ENCODING CLIP — SAVES TO DOWNLOADS WHEN DONE")

func _on_clip_saved(path: String) -> void:
	if not clean_capture_mode:
		_show_notice("CLIP SAVED — %s" % path.get_file())

func _on_clip_failed(reason: String) -> void:
	if not clean_capture_mode:
		_show_notice("CLIP CAPTURE FAILED — %s" % reason)

func _on_device_changed(_device: String) -> void:
	_update_hint()

func _update_hint() -> void:
	hint_label.text = "%s pop/tricks   •   LT/RT grabs in air   •   %s marker   •   %s return   •   F3 debug" % [InputManager.glyph(&"jump"), InputManager.glyph(&"set_marker"), InputManager.glyph(&"respawn")]
	if onboarding_remaining > 0.0:
		hint_label.visible = true

func _show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	notice_time = 2.0

func _show_trick_result(text: String) -> void:
	trick_result_label.text = text
	trick_result_label.modulate.a = 1.0
	trick_result_time = 1.25
	trick_result_label.visible = true

func _quality_name(outcome: int) -> String:
	match outcome:
		LandingSolver.Outcome.CLEAN: return "CLEAN"
		LandingSolver.Outcome.SKETCHY: return "SKETCHY"
		LandingSolver.Outcome.HARD: return "HARD"
		_: return "BAIL"

func _medal_for_score(score: int) -> String:
	if score >= 6000:
		return "GOLD"
	if score >= 3000:
		return "SILVER"
	if score >= 1000:
		return "BRONZE"
	return "NO MEDAL"

func _next_medal_target(score: int) -> int:
	if score < 1000:
		return 1000
	if score < 3000:
		return 3000
	if score < 6000:
		return 6000
	return 0
