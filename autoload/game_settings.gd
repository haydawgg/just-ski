extends Node

signal settings_applied

const CONFIG_PATH := "user://settings.cfg"
const DEFAULTS := {
	"display_mode": 0,
	"resolution": Vector2i(1280, 720),
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
	if key != "graphics_preset" and key in ["render_scale", "anti_aliasing", "shadow_quality", "snow_quality", "ssao_enabled", "ssil_enabled", "ssr_enabled", "fog_enabled"]:
		pending["graphics_preset"] = 4

func apply_pending() -> void:
	active = pending.duplicate(true)
	_apply_display()
	_apply_audio()
	save_settings()
	settings_applied.emit()

func apply_preset(preset: int) -> void:
	pending["graphics_preset"] = clampi(preset, 0, 4)
	if preset == 4:
		return
	var scales := [0.65, 0.8, 1.0, 1.0]
	pending["render_scale"] = scales[preset]
	pending["anti_aliasing"] = 0 if preset == 0 else 1
	pending["shadow_quality"] = preset
	pending["snow_quality"] = 1 if preset >= 2 else 0
	pending["ssao_enabled"] = preset >= 1
	pending["ssil_enabled"] = preset >= 3
	pending["ssr_enabled"] = preset >= 2
	pending["fog_enabled"] = preset >= 1

func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in active.keys():
		config.set_value("settings", key, active[key])
	config.save(CONFIG_PATH)

func _validated(key: String, value: Variant) -> Variant:
	match key:
		"fps_cap": return clampi(int(value), 0, 360)
		"render_scale": return clampf(float(value), 0.5, 1.5)
		"anti_aliasing": return clampi(int(value), 0, 1)
		"shadow_quality": return clampi(int(value), 0, 3)
		"snow_quality": return clampi(int(value), 0, 1)
		"graphics_preset": return clampi(int(value), 0, 4)
		"controller_rumble", "landing_assist": return clampf(float(value), 0.0, 1.0)
		"stick_deadzone": return clampf(float(value), 0.0, 0.45)
		"stick_outer_deadzone": return clampf(float(value), 0.0, 0.25)
		"stick_response": return clampf(float(value), 0.5, 3.0)
		"resolution":
			var size := value as Vector2i
			return Vector2i(clampi(size.x, 960, 7680), clampi(size.y, 540, 4320))
		_:
			return value

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
