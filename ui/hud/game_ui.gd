class_name GameUI
extends CanvasLayer

var player: SkierController
var speed_label: Label
var trick_label: Label
var score_label: Label
var hint_label: Label
var debug_label: Label
var notice_label: Label
var pause_panel: PanelContainer
var options_panel: PanelContainer
var trick_guide_panel: PanelContainer
var trick_visualizer: FlickVisualizer
var total_score := 0
var notice_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_pause_menu()
	_build_trick_guide()
	_build_options_menu()
	InputManager.device_changed.connect(_on_device_changed)
	SessionManager.marker_changed.connect(_on_marker_changed)
	InputManager.controller_connection_changed.connect(_on_controller_connection)
	_update_hint()

func bind_player(value: SkierController) -> void:
	player = value
	player.telemetry_updated.connect(_on_telemetry)
	player.trick.trick_changed.connect(_on_trick_changed)
	player.trick.trick_landed.connect(_on_trick_landed)
	player.landed.connect(_on_landed)
	player.crashed.connect(_on_crashed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if trick_guide_panel.visible:
			_close_trick_guide()
		elif options_panel.visible:
			_close_options(false)
		elif get_tree().paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time -= delta
		notice_label.modulate.a = clampf(notice_time, 0.0, 1.0)
	if player != null and player.debug_enabled:
		debug_label.visible = true
	else:
		debug_label.visible = false

func _build_hud() -> void:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 26)
	safe.add_theme_constant_override("margin_top", 22)
	safe.add_theme_constant_override("margin_right", 26)
	safe.add_theme_constant_override("margin_bottom", 22)
	add_child(safe)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(overlay)

	speed_label = _label("0 km/h", 28)
	speed_label.position = Vector2(0, 0)
	overlay.add_child(speed_label)
	trick_label = _label("", 30)
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_label.position = Vector2(360, 36)
	trick_label.size = Vector2(800, 54)
	overlay.add_child(trick_label)
	score_label = _label("SCORE 000000", 20)
	score_label.position = Vector2(0, 42)
	overlay.add_child(score_label)
	hint_label = _label("", 17)
	hint_label.position = Vector2(0, 780)
	hint_label.size = Vector2(900, 40)
	overlay.add_child(hint_label)
	notice_label = _label("", 22)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.position = Vector2(460, 120)
	notice_label.size = Vector2(600, 40)
	overlay.add_child(notice_label)
	debug_label = _label("", 14)
	debug_label.position = Vector2(1120, 0)
	debug_label.size = Vector2(410, 360)
	overlay.add_child(debug_label)
	trick_visualizer = FlickVisualizer.new()
	trick_visualizer.position = Vector2(1240, 585)
	overlay.add_child(trick_visualizer)

func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.visible = false
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
	box.add_child(_button("Resume", _resume))
	box.add_child(_button("Return to Marker", _respawn_from_menu))
	box.add_child(_button("Set Marker Here", _set_marker_from_menu))
	var guide_button := _button("Trick Guide", _open_trick_guide)
	guide_button.name = "TrickGuideButton"
	box.add_child(guide_button)
	box.add_child(_button("Options", _open_options))
	box.add_child(_button("Restart from Summit", _restart_summit))
	box.add_child(_button("Quit to Desktop", _quit_game))

func _build_trick_guide() -> void:
	trick_guide_panel = PanelContainer.new()
	trick_guide_panel.name = "TrickGuidePanel"
	trick_guide_panel.visible = false
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
		"Flick left/right: spin impulse",
		"Flick up: frontflip   •   Flick down: backflip",
		"Flick diagonal: left/right cork",
		"Recenter before each additional flick; left stick trims yaw",
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
	var back := _button("Back", _close_trick_guide)
	back.name = "TrickGuideBack"
	box.add_child(back)

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
	options_panel.visible = false
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
	scale.max_value = 1.25
	scale.step = 0.05
	graphics_tab.add_child(_row("3D render scale", scale))
	scale.value_changed.connect(func(value: float) -> void: GameSettings.set_pending("render_scale", value))
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
	buttons.add_child(_button("Apply", _apply_options))
	buttons.add_child(_button("Cancel", _cancel_options))
	buttons.add_child(_button("Reset Defaults", _reset_options))

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
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#f4fbff"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 52)
	button.pressed.connect(callback)
	return button

func _pause() -> void:
	get_tree().paused = true
	AudioManager.stop_feedback()
	pause_panel.visible = true
	trick_guide_panel.visible = false
	var first := pause_panel.find_child("", true, false)
	for node: Node in pause_panel.find_children("*", "Button", true, false):
		(node as Button).grab_focus()
		break

func _resume() -> void:
	options_panel.visible = false
	trick_guide_panel.visible = false
	pause_panel.visible = false
	get_tree().paused = false

func _respawn_from_menu() -> void:
	SessionManager.request_respawn()
	_resume()

func _set_marker_from_menu() -> void:
	if player != null and player.contact.grounded:
		SessionManager.set_marker(player.global_transform.translated_local(Vector3.UP * 0.5))
	_resume()

func _restart_summit() -> void:
	SessionManager.clear_marker()
	SessionManager.request_respawn()
	_resume()

func _quit_game() -> void:
	AudioManager.shutdown_audio()
	get_tree().quit()

func _open_trick_guide() -> void:
	pause_panel.visible = false
	trick_guide_panel.visible = true
	(trick_guide_panel.find_child("TrickGuideBack", true, false) as Button).grab_focus()

func _close_trick_guide() -> void:
	trick_guide_panel.visible = false
	pause_panel.visible = true
	var guide_button := pause_panel.find_child("TrickGuideButton", true, false) as Button
	if guide_button != null:
		guide_button.grab_focus()

func _open_options() -> void:
	GameSettings.begin_edit()
	pause_panel.visible = false
	options_panel.visible = true
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
	(options_panel.find_child("SSAO", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssao_enabled"]))
	(options_panel.find_child("SSIL", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssil_enabled"]))
	(options_panel.find_child("SSR", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["ssr_enabled"]))
	(options_panel.find_child("Fog", true, false) as CheckButton).set_pressed_no_signal(bool(GameSettings.pending["fog_enabled"]))
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
	options_panel.visible = false
	pause_panel.visible = true
	for node: Node in pause_panel.find_children("*", "Button", true, false):
		(node as Button).grab_focus()
		break

func _on_telemetry(data: Dictionary) -> void:
	var speed := float(data.speed_mps) * (2.23694 if bool(GameSettings.active["units_mph"]) else 3.6)
	speed_label.text = "%d %s" % [roundi(speed), "mph" if bool(GameSettings.active["units_mph"]) else "km/h"]
	var animation: Dictionary = data.get("animation", {})
	var flick_data: Dictionary = data.get("flick", {})
	if trick_visualizer != null:
		trick_visualizer.apply_snapshot(flick_data)
	debug_label.text = "FPS %d\nPhysics %d Hz\nState %s\nGrounded %s (%.2f)\nSpeed %.2f m/s\nNormal %s\nEdge %.2f\nLateral slip %.2f\nCarve force %.2f\nAngular %s\nRail %s\nFlick %s / %s\nAnim %s\nPose %s\nAnim blend %.2f" % [
		Engine.get_frames_per_second(), Engine.physics_ticks_per_second, data.state, data.grounded, data.contact_confidence,
		data.speed_mps, data.surface_normal, data.edge, data.lateral_slip, data.carve_force, data.angular_velocity, data.rail,
		flick_data.get("kind", "NONE"), flick_data.get("phase", "NEUTRAL"),
		animation.get("state", "—"), animation.get("pose", "—"), animation.get("blend", 0.0)]

func _on_trick_changed(text: String) -> void:
	trick_label.text = text

func _on_trick_landed(text: String, points: int, quality: float) -> void:
	total_score += points
	score_label.text = "SCORE %06d" % total_score
	_show_notice("%s  +%d  [%s]" % [text, points, _quality_name(quality)])

func _on_landed(result: Dictionary) -> void:
	if float(result.score) < 0.72:
		_show_notice(_quality_name(float(result.score)) + " LANDING")

func _on_crashed() -> void:
	_show_notice("BAIL — recovering…")

func _on_marker_changed(_position: Vector3) -> void:
	_show_notice("SESSION MARKER SAVED")

func _on_controller_connection(connected: bool) -> void:
	_show_notice("CONTROLLER CONNECTED" if connected else "CONTROLLER DISCONNECTED — KEYBOARD ACTIVE")

func _on_device_changed(_device: String) -> void:
	_update_hint()

func _update_hint() -> void:
	hint_label.text = "%s pop/tricks   •   LT/RT grabs in air   •   %s marker   •   %s return   •   F3 debug" % [InputManager.glyph(&"jump"), InputManager.glyph(&"set_marker"), InputManager.glyph(&"respawn")]

func _show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	notice_time = 2.0

func _quality_name(quality: float) -> String:
	if quality >= 0.72: return "CLEAN"
	if quality >= 0.42: return "SKETCHY"
	if quality >= 0.25: return "HARD"
	return "BAIL"
