extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_visualizer_contract()
	_test_game_ui_teaching_surfaces()
	_test_pause_menu_actions()
	if failures.is_empty():
		print("TRICK_UI_PASS: visualizer, persisted toggle, controller guide, and pause menu actions passed")
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

func _test_game_ui_teaching_surfaces() -> void:
	var ui := GameUI.new()
	add_child(ui)
	if ui.find_child("TrickVisualizer", true, false) == null:
		failures.append("Gameplay HUD is missing the Flick-It visualizer")
	if ui.find_child("TrickGuidePanel", true, false) == null:
		failures.append("Pause UI is missing the trick guide")
	var guide_button := ui.find_child("TrickGuideButton", true, false) as Button
	if guide_button == null or guide_button.focus_mode == Control.FOCUS_NONE:
		failures.append("Trick guide is not controller-focusable")
	if ui.find_child("AntiAliasing", true, false) == null:
		failures.append("Options menu is missing anti-aliasing control")
	if ui.find_child("ShadowQuality", true, false) == null:
		failures.append("Options menu is missing shadow quality control")
	ui.queue_free()

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
