extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_visualizer_contract()
	_test_visualizer_does_not_duplicate_trick_readout()
	_test_game_ui_teaching_surfaces()
	_test_scoring_finish_contract()
	await _test_pause_menu_actions()
	await _test_run_results_panel()
	if failures.is_empty():
		print("TRICK_UI_PASS: visualizer, controller guide, pause menu, scoring summary, and results flow passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("TRICK_UI_FAIL: " + failure)
		get_tree().quit(1)

func _test_visualizer_contract() -> void:
	if not GameSettings.active.has("trick_visualizer_enabled"):
		failures.append("Visualizer setting is not persisted by GameSettings")
	var visualizer := FlickVisualizer.new()
	add_child(visualizer)
	visualizer.apply_snapshot({
		"stick": Vector2(0.7, -0.7),
		"kind": "CORK_RIGHT",
		"phase": "ROTATE",
		"strength": 0.9,
		"left_trigger": 0.0,
		"right_trigger": 0.8,
		"grab": "Safety Grab Right",
	})
	var snapshot := visualizer.debug_snapshot()
	if not visualizer.visible:
		failures.append("Active trick input did not reveal the visualizer")
	if snapshot.kind != "CORK_RIGHT" or snapshot.phase != "ROTATE":
		failures.append("Visualizer did not present the recognized gesture and phase")
	if int(snapshot.path_points) < 1:
		failures.append("Visualizer did not retain the recent stick path")
	visualizer.apply_snapshot({"stick": Vector2.ZERO, "kind": "NONE", "phase": "NEUTRAL", "strength": 0.0})
	visualizer._process(1.0)
	if visualizer.visible:
		failures.append("Neutral trick input kept the full visualizer on screen")

func _test_visualizer_does_not_duplicate_trick_readout() -> void:
	# The center-top trick label owns the scored trick name and degrees. The
	# lower-right teaching widget must show input gesture state, not a second
	# copy of the scored readout.
	var visualizer := FlickVisualizer.new()
	add_child(visualizer)
	visualizer.apply_snapshot({
		"stick": Vector2(0.7, -0.7),
		"kind": "SPIN_RIGHT",
		"phase": "ROTATE",
		"strength": 0.9,
		"left_trigger": 0.0,
		"right_trigger": 0.0,
		"grab": "",
		"trick_text": "Right 360",
		"yaw_degrees": 360,
		"flip_degrees": 0,
	})
	if "Right 360" in visualizer.title_label.text:
		failures.append("Visualizer repeated the scored trick name from the trick label")
	if "360" in visualizer.detail_label.text:
		failures.append("Visualizer repeated scored rotation degrees from the trick label")
	if "Spin Right" not in visualizer.title_label.text:
		failures.append("Visualizer lost its input-gesture teaching title")
	visualizer.queue_free()
func _test_game_ui_teaching_surfaces() -> void:
	var ui := GameUI.new()
	add_child(ui)
	ui._layout_menus(Vector2(1280, 720))
	for panel: Control in [ui.pause_panel, ui.results_panel, ui.trick_guide_panel, ui.challenge_panel, ui.options_panel]:
		var rect := Rect2(panel.position, panel.size)
		if rect.position.x < 0.0 or rect.position.y < 0.0 or rect.end.x > 1280.0 or rect.end.y > 720.0:
			failures.append("Menu panel %s exceeded the 1280x720 viewport (position=%s size=%s)" % [panel.name, panel.position, panel.size])
	if ui.find_child("TrickVisualizer", true, false) == null:
		failures.append("Gameplay HUD is missing the Flick-It visualizer")
	if ui.find_child("TrickGuidePanel", true, false) == null:
		failures.append("Pause UI is missing the trick guide")
	var guide_button := ui.find_child("TrickGuideButton", true, false) as Button
	if guide_button == null or guide_button.focus_mode == Control.FOCUS_NONE:
		failures.append("Trick guide is not controller-focusable")
	elif guide_button.get_theme_font("font").resource_path != "res://assets/ui/fonts/Inter-4.1-Variable.ttf":
		failures.append("Gameplay UI is not inheriting the pinned project font")
	elif not guide_button.get_theme_stylebox("normal") is StyleBoxFlat:
		failures.append("Gameplay UI is not inheriting the project control theme")
	var resume_button := ui.find_child("ResumeButton", true, false) as Button
	var options_button := ui.find_child("OptionsButton", true, false) as Button
	var restart_button := ui.find_child("RestartButton", true, false) as Button
	if resume_button == null or resume_button.icon == null or options_button == null or options_button.icon == null or restart_button == null or restart_button.icon == null:
		failures.append("Pause menu is missing the restrained project icon set")
	if options_button != null and options_button.text != "Settings":
		failures.append("Pause menu does not expose the in-game Settings entry")
	if ui.find_child("AntiAliasing", true, false) == null:
		failures.append("Options menu is missing anti-aliasing control")
	if ui.find_child("ShadowQuality", true, false) == null:
		failures.append("Options menu is missing shadow quality control")
	if ui.find_child("GI", true, false) == null:
		failures.append("Options menu is missing global illumination control")
	if ui.find_child("EnvironmentPreset", true, false) == null:
		failures.append("Options menu is missing the Day / Golden Hour / Sunset control")
	for control_name: String in ["RenderScale", "AntiAliasing", "ShadowQuality", "GI"]:
		var control := ui.find_child(control_name, true, false) as Control
		if control == null or control.focus_mode == Control.FOCUS_NONE:
			failures.append("Settings control %s is not controller-focusable" % control_name)
	if ui.find_child("RunResultsPanel", true, false) == null:
		failures.append("Gameplay UI is missing the run results panel")
	var guide_text := ""
	for node: Node in ui.find_children("*", "Label", true, false):
		guide_text += "\n" + (node as Label).text
	if "recenter once" not in guide_text.to_lower() or "does not create repeated rotation impulses" not in guide_text.to_lower():
		failures.append("Trick guide does not describe the implemented airborne hold model")
	if "Recenter before each additional flick" in guide_text:
		failures.append("Trick guide still teaches repeated airborne flicks")
	var original_gi := bool(GameSettings.active["gi_enabled"])
	var original_environment_preset := int(GameSettings.active["environment_preset"])
	ui._open_options()
	var gi_control := ui.find_child("GI", true, false) as CheckButton
	if gi_control != null:
		gi_control.toggled.emit(not original_gi)
		if bool(GameSettings.active["gi_enabled"]) != original_gi:
			failures.append("Options GI edit changed active settings before Apply")
		if bool(GameSettings.pending["gi_enabled"]) == original_gi:
			failures.append("Options GI edit was not staged")
	var environment_control := ui.find_child("EnvironmentPreset", true, false) as OptionButton
	if environment_control != null:
		environment_control.item_selected.emit((original_environment_preset + 1) % 3)
		if int(GameSettings.active["environment_preset"]) != original_environment_preset:
			failures.append("Options time-of-day edit changed active settings before Apply")
		if int(GameSettings.pending["environment_preset"]) == original_environment_preset:
			failures.append("Options time-of-day edit was not staged")
	ui._cancel_options()
	if bool(GameSettings.pending["gi_enabled"]) != bool(GameSettings.active["gi_enabled"]):
		failures.append("Options GI Cancel did not restore the pending value")
	if int(GameSettings.pending["environment_preset"]) != int(GameSettings.active["environment_preset"]):
		failures.append("Options time-of-day Cancel did not restore the pending value")
	var settings_title_found := false
	for node: Node in ui.options_panel.find_children("*", "Label", true, false):
		if "SETTINGS" in (node as Label).text:
			settings_title_found = true
			break
	if not settings_title_found:
		failures.append("In-game settings panel is missing its Settings title")
	var original_resolution := GameSettings.active["resolution"] as Vector2i
	ui._open_options()
	var staged_resolution := Vector2i(1280, 720) if original_resolution != Vector2i(1280, 720) else Vector2i(1600, 900)
	GameSettings.set_pending("resolution", staged_resolution)
	ui._apply_options()
	if ui.display_confirmation_panel == null or not ui.display_confirmation_panel.visible:
		failures.append("Risky display Apply did not open the timed confirmation panel")
	if GameSettings.active["resolution"] != staged_resolution:
		failures.append("Display confirmation did not preview the staged resolution")
	var persisted_preview := ConfigFile.new()
	if persisted_preview.load(GameSettings.CONFIG_PATH) == OK and persisted_preview.get_value("settings", "resolution", original_resolution) == staged_resolution:
		failures.append("Unconfirmed display preview was persisted before the player kept it")
	ui._revert_display_settings()
	if GameSettings.active["resolution"] != original_resolution:
		failures.append("Display confirmation Revert did not restore the previous resolution")
	if not ui.pause_panel.visible:
		failures.append("Display confirmation Revert did not return to the pause menu")
	ui._open_options()
	GameSettings.set_pending("resolution", staged_resolution)
	ui._apply_options()
	ui._display_confirmation_seconds = 0.01
	ui._process(0.02)
	if GameSettings.active["resolution"] != original_resolution or ui.display_confirmation_panel.visible:
		failures.append("Display confirmation timeout did not automatically restore the previous resolution")
	ui._set_menu_visible(ui.results_panel)
	get_tree().paused = true
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	ui._unhandled_input(cancel_event)
	if get_tree().paused or ui.results_panel.visible:
		failures.append("Escape did not dismiss the run results panel")
	get_tree().paused = false
	var original_active := GameSettings.active.duplicate(true)
	var live_preset := 0 if int(original_active["graphics_preset"]) != 0 else 2
	ui._open_options()
	var preset_control := ui.find_child("Preset", true, false) as OptionButton
	var apply_button := ui.find_child("ApplyButton", true, false) as Button
	if preset_control == null or apply_button == null:
		failures.append("Settings menu is missing live graphics Apply controls")
	else:
		preset_control.item_selected.emit(live_preset)
		apply_button.pressed.emit()
		var expected_scale := float(GameSettings.active["render_scale"])
		if int(GameSettings.active["graphics_preset"]) != live_preset:
			failures.append("Settings Apply did not promote the graphics preset")
		if not is_equal_approx(get_viewport().scaling_3d_scale, expected_scale):
			failures.append("Settings Apply did not update the live render scale")
		if not FileAccess.file_exists(GameSettings.CONFIG_PATH):
			failures.append("Settings Apply did not persist the live graphics change")
	GameSettings.pending = original_active.duplicate(true)
	GameSettings.apply_pending()
	ui._resume()
	if ui._quality_name(LandingSolver.Outcome.CLEAN) != "CLEAN" or ui._quality_name(LandingSolver.Outcome.SKETCHY) != "SKETCHY" or ui._quality_name(LandingSolver.Outcome.HARD) != "HARD":
		failures.append("Landing labels did not use explicit outcomes")
	ui._process(10.0)
	if ui.hint_label.visible:
		failures.append("Onboarding controls remained permanently visible during normal play")
	var trick := TrickController.new()
	trick.begin_air(false, TrickCommand.Kind.POP)
	trick.update_air(Vector3.ZERO, 0.1)
	if not trick.live_name().is_empty():
		failures.append("A micro-hop presented Straight Air feedback")
	trick.update_air(Vector3.ZERO, 0.4)
	if trick.live_name() != "Straight Air":
		failures.append("A sustained straight air lost useful trick feedback")
	trick.free()
	var grab_trick := TrickController.new()
	add_child(grab_trick)
	grab_trick.begin_air(false, TrickCommand.Kind.SPIN_LEFT)
	var grab_command := TrickCommand.new()
	grab_command.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	grab_command.grab_amount = 1.0
	grab_trick.update_air(Vector3.ZERO, 0.1, grab_command)
	if "Safety Grab Left" in grab_trick.live_name():
		failures.append("Grab intent appeared before visual contact qualification")
	grab_trick.set_grab_contact(1.0, "HOLD", 0.12)
	if "Safety Grab Left" not in grab_trick.live_name():
		failures.append("Qualified visual grab contact did not reach live trick feedback")
	grab_command.reset()
	grab_trick.update_air(Vector3.ZERO, 0.1, grab_command)
	if "Safety Grab Left" in grab_trick.live_name():
		failures.append("Released visual grab remained in live trick feedback")
	grab_trick.free()
	ui.queue_free()

func _test_scoring_finish_contract() -> void:
	var scoring := RunScoring.new()
	add_child(scoring)
	var finish_events := [0]
	scoring.run_finished.connect(func(_snapshot: Dictionary) -> void: finish_events[0] += 1)
	scoring.accept_trick("Left 360", 1000, 0.8, LandingSolver.Outcome.CLEAN)
	scoring.bail()
	scoring.finish_run()
	scoring.finish_run()
	var snapshot := scoring.snapshot()
	if int(finish_events[0]) != 1 or not bool(snapshot.finished):
		failures.append("Run scoring did not finish exactly once")
	if int(snapshot.best_trick_points) != 1000 or str(snapshot.best_trick_name) != "Left 360":
		failures.append("Run scoring did not retain the best trick")
	if int(snapshot.landed_trick_count) != 1 or int(snapshot.clean_trick_count) != 1 or int(snapshot.bail_count) != 1:
		failures.append("Run scoring summary counters were incorrect")
	var outcome_scoring := RunScoring.new()
	add_child(outcome_scoring)
	outcome_scoring.accept_trick("Sketchy 360", 1000, 0.99, LandingSolver.Outcome.SKETCHY)
	if int(outcome_scoring.snapshot().clean_trick_count) != 0:
		failures.append("Run scoring inferred CLEAN from a high quality float instead of the explicit outcome")
	outcome_scoring.queue_free()
	scoring.reset_run()
	if bool(scoring.snapshot().finished) or int(scoring.snapshot().total_score) != 0:
		failures.append("Reset run did not clear the finished score")
	scoring.queue_free()

func _test_pause_menu_actions() -> void:
	var ui := GameUI.new()
	add_child(ui)
	await get_tree().process_frame

	ui._pause()
	if not get_tree().paused:
		failures.append("Pause did not pause the scene tree")
	if not ui.pause_panel.visible:
		failures.append("Pause did not show the pause panel")
	if ui.find_child("MenuBackdrop", true, false) == null or not (ui.find_child("MenuBackdrop", true, false) as CanvasItem).visible:
		failures.append("Pause did not show the modal menu backdrop")

	var options_button := ui.find_child("OptionsButton", true, false) as Button
	if options_button == null:
		failures.append("Pause menu is missing OptionsButton")
	else:
		options_button.pressed.emit()
		if not ui.options_panel.visible or ui.pause_panel.visible:
			failures.append("Options button did not open the options panel")
		var cancel_button := ui.find_child("CancelButton", true, false) as Button
		if cancel_button != null:
			cancel_button.pressed.emit()
		if not ui.pause_panel.visible or ui.options_panel.visible:
			failures.append("Options Cancel did not return to the pause panel")

	var guide_button := ui.find_child("TrickGuideButton", true, false) as Button
	if guide_button != null:
		guide_button.pressed.emit()
		if not ui.trick_guide_panel.visible:
			failures.append("Trick Guide button did not open the guide panel")
		var back := ui.find_child("TrickGuideBack", true, false) as Button
		if back != null:
			back.pressed.emit()
		if not ui.pause_panel.visible:
			failures.append("Trick Guide Back did not return to the pause panel")

	ui.total_score = 12345
	ui.score_label.text = "SCORE 012345"
	SessionManager.set_marker(Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	var restart := ui.find_child("RestartButton", true, false) as Button
	if restart != null:
		restart.pressed.emit()
	if ui.total_score != 0 or ui.score_label.text != "SCORE 000000":
		failures.append("Restart from Summit did not reset score")
	if SessionManager.has_marker:
		failures.append("Restart from Summit did not clear the session marker")
	if get_tree().paused:
		failures.append("Restart from Summit did not resume gameplay")

	ui._pause()
	var return_button := ui.find_child("ReturnMarkerButton", true, false) as Button
	if return_button != null:
		return_button.pressed.emit()
	if not get_tree().paused:
		failures.append("Return to Marker with no marker should stay paused")
	if ui.notice_label.text != "NO MARKER SET":
		failures.append("Return to Marker without a marker did not show feedback")

	var resume := ui.find_child("ResumeButton", true, false) as Button
	if resume != null:
		resume.pressed.emit()
	if get_tree().paused or ui.pause_panel.visible:
		failures.append("Resume button did not close the pause menu")

	ui.queue_free()

func _test_run_results_panel() -> void:
	SessionManager.clear_marker()
	var ui := GameUI.new()
	add_child(ui)
	await get_tree().process_frame
	ui._on_run_finished({
		"total_score": 0,
		"best_trick_name": "",
		"best_trick_points": 0,
		"landed_trick_count": 0,
		"clean_trick_count": 0,
		"bail_count": 0,
	})
	if not get_tree().paused or not ui.results_panel.visible:
		failures.append("Finishing a run did not open a paused results panel")
	if "NO MEDAL" not in ui.results_score_label.text or "No scored trick" not in ui.results_detail_label.text:
		failures.append("Run results did not present score, medal, and best-trick feedback")
	var marker_button := ui.find_child("ResultsMarkerButton", true, false) as Button
	if marker_button == null or not marker_button.disabled:
		failures.append("Run results did not disable Return to Marker when no marker exists")
	var continue_button := ui.find_child("ResultsContinueButton", true, false) as Button
	if continue_button != null:
		continue_button.pressed.emit()
	if get_tree().paused or ui.results_panel.visible:
		failures.append("Keep Riding did not close the results panel")
	ui.queue_free()
