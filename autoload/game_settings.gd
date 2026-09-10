extends Node

signal settings_applied
signal settings_saved
signal settings_save_failed(error: Error)

const CONFIG_PATH := "user://settings.cfg"
const RENDERER_SETTING_KEYS := [
	"render_scale",
	"anti_aliasing",
	"shadow_quality",
	"snow_quality",
	"ssao_enabled",
	"ssil_enabled",
	"ssr_enabled",
	"fog_enabled",
	"gi_enabled",
]
const DEFAULTS := {
	"display_mode": 1,
	"resolution": Vector2i(1920, 1080),
	"vsync_mode": 1,
	"fps_cap": 120,
	"graphics_preset": 2,
	"render_scale": 1.0,
	"anti_aliasing": 1,
	"shadow_quality": 2,
	"snow_quality": 1,
	"ssao_enabled": true,
	"ssil_enabled": false,
	"ssr_enabled": true,
	"fog_enabled": true,
	"gi_enabled": true,
	"environment_preset": 0,
	"master_volume_db": -3.0,
	"music_volume_db": -8.0,
	"sfx_volume_db": -2.0,
	"controller_rumble": 0.75,
	"stick_deadzone": 0.18,
	"stick_outer_deadzone": 0.06,
	"stick_response": 1.35,
	"units_mph": false,
	"landing_assist": 0.35,
	"trick_visualizer_enabled": true,
}

var active: Dictionary = {}
var pending: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_pending()

func load_settings() -> void:
	active = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		for key: String in DEFAULTS.keys():
			if config.has_section_key("settings", key):
				active[key] = _validated(key, config.get_value("settings", key))
	pending = active.duplicate(true)

func begin_edit() -> void:
	pending = active.duplicate(true)

func cancel_pending() -> void:
	pending = active.duplicate(true)

func reset_pending() -> void:
	pending = DEFAULTS.duplicate(true)

func set_pending(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	pending[key] = _validated(key, value)
	if key != "graphics_preset" and key in RENDERER_SETTING_KEYS:
		pending["graphics_preset"] = 4

static func graphics_preset_allows_gi(preset: int) -> bool:
	# Low and Medium are the explicitly GI-free capability tiers. High, Ultra,
	# and Custom may use GI when the environment profile and user setting allow it.
	return clampi(preset, 0, 4) >= 2

func apply_pending(persist: bool = true) -> Error:
	active = _validated_settings(pending)
	pending = active.duplicate(true)
	_apply_display()
	_apply_audio()
	var save_error := save_settings(CONFIG_PATH, false) if persist else OK
	if save_error != OK:
		push_warning("GAME_SETTINGS_SAVE_WARNING: Active settings were applied but could not be persisted (%s)" % error_string(save_error))
	settings_applied.emit()
	return save_error

func restore_settings(settings: Dictionary, persist: bool = true) -> Error:
	active = _validated_settings(settings)
	pending = active.duplicate(true)
	_apply_display()
	_apply_audio()
	var save_error := save_settings(CONFIG_PATH, false) if persist else OK
	if save_error != OK:
		push_warning("GAME_SETTINGS_SAVE_WARNING: Restored settings were applied but could not be persisted (%s)" % error_string(save_error))
	settings_applied.emit()
	return save_error

func apply_preset(preset: int) -> void:
	var selected_preset := clampi(preset, 0, 4)
	pending["graphics_preset"] = selected_preset
	if selected_preset == 4:
		return
	# Medium keeps its additional lighting/atmosphere features but uses the
	# target-class integrated-GPU render scale so the 1080p frame budget remains
	# attainable without changing gameplay or scene geometry.
	var scales := [0.65, 0.65, 1.0, 1.0]
	pending["render_scale"] = scales[selected_preset]
	pending["anti_aliasing"] = 0 if selected_preset == 0 else 1
	pending["shadow_quality"] = selected_preset
	pending["snow_quality"] = 1 if selected_preset >= 2 else 0
	pending["ssao_enabled"] = selected_preset >= 1
	pending["ssil_enabled"] = selected_preset >= 3
	pending["ssr_enabled"] = selected_preset >= 2
	pending["fog_enabled"] = selected_preset >= 1
	pending["gi_enabled"] = graphics_preset_allows_gi(selected_preset)

func save_settings(path: String = CONFIG_PATH, warn_on_failure := true) -> Error:
	var config := ConfigFile.new()
	for key: String in active.keys():
		config.set_value("settings", key, active[key])
	var error := config.save(path)
	if error != OK:
		if warn_on_failure:
			push_warning("GAME_SETTINGS_SAVE_ERROR: Could not save settings (%s)" % error_string(error))
		settings_save_failed.emit(error)
	else:
		settings_saved.emit()
	return error

func _validated(key: String, value: Variant) -> Variant:
	match key:
		"display_mode", "vsync_mode":
			return _validated_int(key, value, 0, 2)
		"fps_cap": return _validated_int(key, value, 0, 360)
		"render_scale": return _validated_float(key, value, 0.5, 1.5)
		"anti_aliasing": return _validated_int(key, value, 0, 1)
		"shadow_quality": return _validated_int(key, value, 0, 3)
		"snow_quality": return _validated_int(key, value, 0, 1)
		"graphics_preset": return _validated_int(key, value, 0, 4)
		"environment_preset": return _validated_int(key, value, 0, 2)
		"master_volume_db", "music_volume_db", "sfx_volume_db": return _validated_float(key, value, -30.0, 0.0)
		"controller_rumble", "landing_assist": return _validated_float(key, value, 0.0, 1.0)
		"stick_deadzone": return _validated_float(key, value, 0.0, 0.45)
		"stick_outer_deadzone": return _validated_float(key, value, 0.0, 0.25)
		"stick_response": return _validated_float(key, value, 0.5, 3.0)
		"ssao_enabled", "ssil_enabled", "ssr_enabled", "fog_enabled", "gi_enabled", "units_mph", "trick_visualizer_enabled":
			return value if typeof(value) == TYPE_BOOL else DEFAULTS[key]
		"resolution":
			if typeof(value) != TYPE_VECTOR2I:
				return DEFAULTS[key]
			var size: Vector2i = value
			return Vector2i(clampi(size.x, 960, 7680), clampi(size.y, 540, 4320))
		_:
			return DEFAULTS[key]

func _validated_int(key: String, value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) != TYPE_INT:
		return int(DEFAULTS[key])
	return clampi(int(value), minimum, maximum)

func _validated_float(key: String, value: Variant, minimum: float, maximum: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return float(DEFAULTS[key])
	var numeric := float(value)
	if not is_finite(numeric):
		return float(DEFAULTS[key])
	return clampf(numeric, minimum, maximum)

func _validated_settings(source: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	for key: String in DEFAULTS.keys():
		if source.has(key):
			result[key] = _validated(key, source[key])
	return result

func _apply_display() -> void:
	Engine.max_fps = int(active["fps_cap"])
	DisplayServer.window_set_vsync_mode(int(active["vsync_mode"]) as DisplayServer.VSyncMode)
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED
	if int(active["display_mode"]) == 1:
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif int(active["display_mode"]) == 2:
		mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(mode)
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(active["resolution"] as Vector2i)
	get_viewport().scaling_3d_scale = float(active["render_scale"])
	get_viewport().use_taa = int(active["anti_aliasing"]) > 0

func _apply_audio() -> void:
	for bus_name: String in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			var key := bus_name.to_lower() + "_volume_db"
			AudioServer.set_bus_volume_db(index, float(active[key]))
