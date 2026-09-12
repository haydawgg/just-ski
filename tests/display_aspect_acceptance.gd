extends Node

## Phase 12 display validation: normalized composition math must generalize
## across aspect ratios, the supported resolution presets must keep menus and
## the fixed-design-space HUD contained, HDR presentation must follow the
## display's actual active state, and QA captures must not leak tooling UI.

const ResortModule := preload("res://world/resort.gd")

const SUPPORTED_RESOLUTIONS: Array[Vector2] = [
	Vector2(1280.0, 720.0),
	Vector2(1600.0, 900.0),
	Vector2(1920.0, 1080.0),
	Vector2(2560.0, 1440.0),
]
const ASPECTS: Array[float] = [4.0 / 3.0, 16.0 / 10.0, 16.0 / 9.0, 21.0 / 9.0]
const HARD_RECT := Rect2(0.10, 0.08, 0.80, 0.80)
const INNER_RECT := Rect2(0.30, 0.24, 0.40, 0.36)
const DESIGN_SPACE := Vector2(1920.0, 1080.0)
const TEST_FOV := 72.0
const SUBJECT_DEPTH := 10.0

var failures: Array[String] = []

func _ready() -> void:
	_test_composition_across_aspects()
	await _test_supported_resolutions()
	_test_hdr_policy()
	await _test_hud_release_separation()
	_finish()

func _test_composition_across_aspects() -> void:
	var horizontal_offsets: Dictionary = {}
	var correction_offsets: Dictionary = {}
	for aspect: float in ASPECTS:
		var viewport := Vector2(round(1080.0 * aspect), 1080.0)
		var projected := _project(_body_points(), viewport)
		var evaluation := CompositionEvaluator.evaluate_landmarks(projected, 0, projected.size(), HARD_RECT, INNER_RECT)
		if float(evaluation.get("hard_violation", INF)) > 0.0001:
			failures.append("Centered subject left the hard rect at aspect %.3f" % aspect)
		if float(evaluation.get("inner_violation", INF)) > 0.0001:
			failures.append("Centered subject left the inner rect at aspect %.3f" % aspect)
		var bounds := evaluation.get("skier_screen_rect", Rect2()) as Rect2
		if bounds.position.x < 0.0 or bounds.position.y < 0.0 or bounds.end.x > 1.0 or bounds.end.y > 1.0:
			failures.append("Projected subject bounds escaped normalized space at aspect %.3f (%.3f, %.3f)" % [aspect, bounds.end.x, bounds.end.y])
		var probe := CompositionEvaluator.project_point(Vector3.ZERO, Basis.IDENTITY, TEST_FOV, viewport, Vector3(1.0, 0.0, -SUBJECT_DEPTH))
		horizontal_offsets[aspect] = absf((probe.screen as Vector2).x - 0.5)
		var shifted := {
			"skier_screen_rect": Rect2(1.30, 0.40, 0.10, 0.30),
			"average_depth": SUBJECT_DEPTH,
			"body_occlusion": 0.0,
		}
		var correction := CompositionEvaluator.screen_correction_world_offset(shifted, INNER_RECT, Basis.IDENTITY, TEST_FOV, viewport, 1.0)
		correction_offsets[aspect] = absf(correction.x)
	# Horizontal projection and correction must scale inversely/proportionally
	# with aspect instead of assuming 16:9.
	var narrow := 4.0 / 3.0
	var wide := 21.0 / 9.0
	var expected_projection_ratio := wide / narrow
	var projection_ratio := float(horizontal_offsets[narrow]) / maxf(float(horizontal_offsets[wide]), 0.000001)
	if absf(projection_ratio - expected_projection_ratio) > 0.01:
		failures.append("Horizontal projection did not scale with aspect (%.3f vs %.3f)" % [projection_ratio, expected_projection_ratio])
	var expected_correction_ratio := wide / narrow
	var correction_ratio := float(correction_offsets[wide]) / maxf(float(correction_offsets[narrow]), 0.000001)
	if absf(correction_ratio - expected_correction_ratio) > 0.02:
		failures.append("Horizontal correction did not scale with aspect (%.3f vs %.3f)" % [correction_ratio, expected_correction_ratio])
	# Vertical correction is aspect-independent.
	var vertical_offsets: Array[float] = []
	for aspect: float in ASPECTS:
		var viewport := Vector2(round(1080.0 * aspect), 1080.0)
		var shifted := {
			"skier_screen_rect": Rect2(0.40, 1.30, 0.20, 0.10),
			"average_depth": SUBJECT_DEPTH,
			"body_occlusion": 0.0,
		}
		var correction := CompositionEvaluator.screen_correction_world_offset(shifted, INNER_RECT, Basis.IDENTITY, TEST_FOV, viewport, 1.0)
		vertical_offsets.append(absf(correction.y))
	var vertical_min := vertical_offsets[0]
	var vertical_max := vertical_offsets[0]
	for value: float in vertical_offsets:
		vertical_min = minf(vertical_min, value)
		vertical_max = maxf(vertical_max, value)
	if vertical_max - vertical_min > 0.001:
		failures.append("Vertical correction drifted across aspects (%.4f..%.4f)" % [vertical_min, vertical_max])
	print("DISPLAY_ASPECT_SAMPLE projection_ratio=%.3f correction_ratio=%.3f vertical=%.3f" % [projection_ratio, correction_ratio, vertical_offsets[0]])

func _test_supported_resolutions() -> void:
	if str(ProjectSettings.get_setting("display/window/stretch/mode", "")) != "canvas_items":
		failures.append("UI stretch mode is no longer canvas_items; the fixed 1920x1080 HUD design space contract changed")
	for resolution: Vector2 in SUPPORTED_RESOLUTIONS:
		var viewport := Vector2(round(1080.0 * (resolution.x / resolution.y)), 1080.0)
		var projected := _project(_body_points(), viewport)
		var evaluation := CompositionEvaluator.evaluate_landmarks(projected, 0, projected.size(), HARD_RECT, INNER_RECT)
		evaluation["body_occlusion"] = 0.0
		if not CompositionEvaluator.hard_valid(evaluation, 0.25):
			failures.append("Supported resolution %s failed camera hard-valid composition" % str(resolution))
		var ui := GameUI.new()
		add_child(ui)
		ui._layout_menus(resolution)
		for panel: Control in [ui.pause_panel, ui.results_panel, ui.trick_guide_panel, ui.challenge_panel, ui.options_panel]:
			var rect := Rect2(panel.position, panel.size)
			if rect.position.x < 0.0 or rect.position.y < 0.0 or rect.end.x > resolution.x + 1.0 or rect.end.y > resolution.y + 1.0:
				failures.append("Menu panel %s exceeded %s (position=%s size=%s)" % [panel.name, str(resolution), str(panel.position), str(panel.size)])
		if ui.hud_overlay != null:
			# Fixed-offset gameplay HUD elements must stay inside the 1920x1080
			# design space; canvas_items stretch guarantees that space maps to
			# every supported 16:9 resolution. Anchored/converted layout controls
			# are governed by their containers instead of fixed coordinates.
			for control: Control in [ui.speed_label, ui.score_label, ui.trick_label, ui.trick_result_label, ui.landing_cue_label, ui.combo_timer_bar, ui.rail_balance_bar, ui.debug_label, ui.recording_label]:
				if control == null:
					failures.append("Gameplay HUD lost one of its fixed-design-space elements at %s" % str(resolution))
					continue
				var rect := Rect2(control.position, control.size)
				if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > DESIGN_SPACE.x + 0.5 or rect.end.y > DESIGN_SPACE.y + 0.5:
					failures.append("HUD element %s escaped the 1920x1080 design space (position=%s size=%s)" % [control.name, str(control.position), str(control.size)])
		ui.queue_free()
		await get_tree().process_frame
	print("DISPLAY_RESOLUTION_SAMPLE resolutions=%d" % SUPPORTED_RESOLUTIONS.size())

func _test_hdr_policy() -> void:
	var combinations := [
		{"requested": false, "active": false, "headless": false, "expected": false},
		{"requested": true, "active": false, "headless": false, "expected": false},
		{"requested": false, "active": true, "headless": false, "expected": false},
		{"requested": true, "active": true, "headless": false, "expected": true},
		{"requested": true, "active": true, "headless": true, "expected": false},
	]
	for combination: Dictionary in combinations:
		var actual: bool = ResortModule.hdr_presentation_enabled(bool(combination.requested), bool(combination.active), bool(combination.headless))
		if actual != bool(combination.expected):
			failures.append("HDR policy mismatch for %s" % str(combination))
	var resort := ResortModule.new()
	if resort.effective_hdr_enabled():
		failures.append("Headless resort enabled HDR presentation")
	resort.free()
	print("DISPLAY_HDR_SAMPLE policy_combinations=%d" % combinations.size())

func _test_hud_release_separation() -> void:
	var ui := GameUI.new()
	add_child(ui)
	await get_tree().process_frame
	if ui.debug_label == null or ui.debug_label.visible:
		failures.append("Developer telemetry label is visible by default")
	if ui.recording_label == null or ui.recording_label.visible:
		failures.append("Recording indicator is visible outside capture tooling")
	if ui.hud_overlay == null:
		failures.append("Gameplay HUD overlay is missing")
	ui.clean_capture_mode = true
	ui._show_notice("SHOULD NOT LEAK")
	if ui.notice_time != 0.0 or ui.notice_label.text == "SHOULD NOT LEAK":
		failures.append("Clean QA capture leaked a transient HUD notice")
	ui._on_recording_changed(true)
	if ui.recording_label.visible:
		failures.append("Clean QA capture leaked the REC indicator")
	ui.clean_capture_mode = false
	ui._on_recording_changed(true)
	if not ui.recording_label.visible:
		failures.append("Recording indicator no longer appears during an intentional capture")
	ui._on_recording_changed(false)
	ui.queue_free()
	print("DISPLAY_HUD_SAMPLE clean_capture_separation=true")

func _body_points(offset_x: float = 0.0) -> Array[Vector3]:
	return [
		Vector3(offset_x, 0.0, -SUBJECT_DEPTH),
		Vector3(offset_x, 0.9, -SUBJECT_DEPTH),
		Vector3(offset_x, -0.9, -SUBJECT_DEPTH),
		Vector3(offset_x - 0.35, -0.2, -SUBJECT_DEPTH),
		Vector3(offset_x + 0.35, -0.2, -SUBJECT_DEPTH),
	]

func _project(points: Array[Vector3], viewport: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Vector3 in points:
		result.append(CompositionEvaluator.project_point(Vector3.ZERO, Basis.IDENTITY, TEST_FOV, viewport, point))
	return result

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("DISPLAY_ASPECT_PASS: composition generalizes across aspects, supported resolutions stay contained, HDR follows active state, and QA captures stay clean")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("DISPLAY_ASPECT_FAIL: " + failure)
	get_tree().quit(1)
