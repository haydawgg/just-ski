extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_visualizer_contract()
	_test_game_ui_teaching_surfaces()
	if failures.is_empty():
		print("TRICK_UI_PASS: visualizer, persisted toggle, and controller guide surfaces passed")
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
