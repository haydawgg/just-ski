extends Node

var original: Dictionary

func _ready() -> void:
	original = GameSettings.active.duplicate(true)
	var original_scale := float(GameSettings.active["render_scale"])
	var staged_scale := 0.55 if not is_equal_approx(original_scale, 0.55) else 0.65

	GameSettings.begin_edit()
	GameSettings.set_pending("render_scale", staged_scale)
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), original_scale), "Editing pending settings changed active state")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, original_scale), "Editing pending settings changed renderer state")

	GameSettings.cancel_pending()
	_check(is_equal_approx(float(GameSettings.pending["render_scale"]), original_scale), "Cancel did not restore pending state")

	GameSettings.begin_edit()
	GameSettings.set_pending("render_scale", staged_scale)
	GameSettings.apply_pending()
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), staged_scale), "Apply did not promote pending state")
	_check(is_equal_approx(get_viewport().scaling_3d_scale, staged_scale), "Apply did not change renderer scale")
	_check(FileAccess.file_exists(GameSettings.CONFIG_PATH), "Applied settings were not persisted")

	GameSettings.active = {}
	GameSettings.pending = {}
	GameSettings.load_settings()
	_check(is_equal_approx(float(GameSettings.active["render_scale"]), staged_scale), "Saved value did not survive reload")

	GameSettings.pending = original.duplicate(true)
	GameSettings.apply_pending()
	AudioManager.shutdown_audio()
	print("SETTINGS_PASS: pending, Cancel, Apply, renderer update, validation, and persistence checks passed")
	get_tree().quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("SETTINGS_FAIL: " + message)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
