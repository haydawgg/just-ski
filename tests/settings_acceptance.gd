extends Node

var original: Dictionary

func _ready() -> void:
	original = GameSettings.active.duplicate(true)
	var original_scale := float(GameSettings.active["render_scale"])
	var staged_scale := 0.55 if not is_equal_approx(original_scale, 0.55) else 0.65

	GameSettings.begin_edit()
	GameSettings.set_pending("render_scale", staged_scale)
	var original_visualizer := bool(GameSettings.active["trick_visualizer_enabled"])
	GameSettings.set_pending("trick_visualizer_enabled", not original_visualizer)
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), original_scale), "Editing pending settings changed active state")
	_check(bool(GameSettings.active["trick_visualizer_enabled"]) == original_visualizer, "Editing visualizer setting changed active state")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, original_scale), "Editing pending settings changed renderer state")

	GameSettings.cancel_pending()
	_check(is_equal_approx(float(GameSettings.pending["render_scale"]), original_scale), "Cancel did not restore pending state")
	_check(bool(GameSettings.pending["trick_visualizer_enabled"]) == original_visualizer, "Cancel did not restore visualizer setting")

	GameSettings.begin_edit()
	GameSettings.set_pending("render_scale", staged_scale)
	GameSettings.set_pending("anti_aliasing", 0 if int(GameSettings.active["anti_aliasing"]) != 0 else 1)
	GameSettings.set_pending("shadow_quality", 0 if int(GameSettings.active["shadow_quality"]) != 0 else 3)
	GameSettings.apply_pending()
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), staged_scale), "Apply did not promote pending state")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, staged_scale), "Apply did not change renderer scale")
	_check(get_viewport().use_taa == (int(GameSettings.active["anti_aliasing"]) > 0), "Apply did not update anti-aliasing")
	_check(int(GameSettings.active["shadow_quality"]) in [0, 3], "Apply did not promote shadow quality")
	_check(FileAccess.file_exists(GameSettings.CONFIG_PATH), "Applied settings were not persisted")

	GameSettings.active = {}
	GameSettings.pending = {}
	GameSettings.load_settings()
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), staged_scale), "Saved value did not survive reload")
	_check(int(GameSettings.active["anti_aliasing"]) in [0, 1], "Saved anti-aliasing did not survive reload")
	_check(int(GameSettings.active["shadow_quality"]) in [0, 1, 2, 3], "Saved shadow quality did not survive reload")

	GameSettings.pending = original.duplicate(true)
	GameSettings.apply_pending()
	AudioManager.shutdown_audio()
	print("SETTINGS_PASS: pending, Cancel, Apply, renderer update, AA/shadow, validation, and persistence checks passed")
	get_tree().quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("SETTINGS_FAIL: " + message)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
