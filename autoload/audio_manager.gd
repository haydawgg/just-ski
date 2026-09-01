extends Node

var feedback_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var target_speed := 0.0
var target_skid := 0.0
var target_rail := 0.0
var target_air := 0.0
var desired_speed := 0.0
var desired_skid := 0.0
var desired_rail := 0.0
var desired_air := 0.0
var target_surface_kind := 0
var phase := 0.0
var rail_phase := 0.0
var pop_phase := 0.0
var gust_phase := 0.0
var wind_filter_left := 0.0
var wind_filter_right := 0.0
var pop_envelope := 0.0
var impact_envelope := 0.0
var noise := RandomNumberGenerator.new()
var last_skid_rumble_ms := 0
var last_rail_rumble_ms := 0
var _shutdown_requested := false
var _headless_audio := false
var _profile_process_samples := 0
var _profile_process_total_usec := 0
var _profile_process_max_usec := 0

func _ready() -> void:
	# Headless acceptance runs do not have a listener or an audio device. Avoid
	# creating an AudioStreamGeneratorPlayback in that mode: the engine keeps a
	# short-lived playback reference in the audio server until the process exits,
	# which otherwise reports a false ObjectDB leak for fast tests.
	_headless_audio = OS.has_feature("headless") or DisplayServer.get_name().to_lower() == "headless"
	if _headless_audio:
		return
	_ensure_bus("Music")
	_ensure_bus("SFX")
	if _shutdown_requested:
		# A fast headless acceptance scene can request shutdown before this
		# autoload reaches _ready(). Do not create a generator that will outlive
		# the scene and trigger an ObjectDB playback leak at process exit.
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.22
	feedback_player = AudioStreamPlayer.new()
	feedback_player.stream = generator
	feedback_player.bus = "SFX"
	add_child(feedback_player)
	feedback_player.play()
	playback = feedback_player.get_stream_playback() as AudioStreamGeneratorPlayback
	GameSettings.settings_applied.connect(_apply_bus_settings)
	_apply_bus_settings()

func _process(delta: float) -> void:
	if playback == null:
		return
	var profile_started_usec := Time.get_ticks_usec()
	target_speed = lerpf(target_speed, desired_speed, 1.0 - exp(-7.0 * delta))
	target_skid = lerpf(target_skid, desired_skid, 1.0 - exp(-12.0 * delta))
	target_rail = lerpf(target_rail, desired_rail, 1.0 - exp(-15.0 * delta))
	target_air = lerpf(target_air, desired_air, 1.0 - exp(-9.0 * delta))
	pop_envelope *= exp(-8.0 * delta)
	impact_envelope *= exp(-13.0 * delta)
	var frame_count := playback.get_frames_available()
	var mix_rate := 22050.0
	var speed_mix := clampf(target_speed / 32.0, 0.0, 1.0)
	var surface_loudness := 1.12 if target_surface_kind == 0 else (0.9 if target_surface_kind == 1 else 0.78)
	var ground_mix := 1.0 - target_air * 0.88
	var surface_amplitude := (speed_mix * 0.025 + target_skid * 0.052) * surface_loudness * ground_mix
	var wind_amplitude := 0.0035 + speed_mix * 0.018 + target_air * 0.034
	var output_gain := 0.0 if get_tree().paused else 1.0
	for _frame: int in frame_count:
		phase = fmod(phase + (72.0 + target_speed * 7.0) / mix_rate, 1.0)
		rail_phase = fmod(rail_phase + (118.0 + target_speed * 11.0) / mix_rate, 1.0)
		pop_phase = fmod(pop_phase + (82.0 + pop_envelope * 34.0) / mix_rate, 1.0)
		gust_phase = fmod(gust_phase + 0.11 / mix_rate, 1.0)
		var wind_smoothing := 0.018 + speed_mix * 0.035 + target_air * 0.045
		wind_filter_left = lerpf(wind_filter_left, noise.randf_range(-1.0, 1.0), wind_smoothing)
		wind_filter_right = lerpf(wind_filter_right, noise.randf_range(-1.0, 1.0), wind_smoothing)
		var gust := 0.82 + sin(gust_phase * TAU) * 0.12 + sin(gust_phase * TAU * 2.37) * 0.06
		var surface_texture := 0.52 if target_surface_kind == 0 else (0.36 if target_surface_kind == 1 else 0.24)
		var glide_left := noise.randf_range(-1.0, 1.0) * (surface_texture + target_skid * 0.62)
		var glide_right := noise.randf_range(-1.0, 1.0) * (surface_texture + target_skid * 0.62)
		var edge_sing := sin(phase * TAU) * target_skid * speed_mix * 0.012
		var rail_tone := (sin(rail_phase * TAU) * 0.72 + sin(rail_phase * TAU * 2.01) * 0.18) * target_rail * 0.038
		var pop_tone := sin(pop_phase * TAU) * pop_envelope * 0.052
		var impact_noise := noise.randf_range(-1.0, 1.0) * impact_envelope * 0.082
		var left := wind_filter_left * wind_amplitude * gust + glide_left * surface_amplitude + edge_sing + rail_tone + pop_tone + impact_noise
		var right := wind_filter_right * wind_amplitude * gust + glide_right * surface_amplitude - edge_sing + rail_tone + pop_tone + impact_noise
		playback.push_frame(Vector2(clampf(left * output_gain, -0.9, 0.9), clampf(right * output_gain, -0.9, 0.9)))
	var process_usec := Time.get_ticks_usec() - profile_started_usec
	_profile_process_samples += 1
	_profile_process_total_usec += process_usec
	_profile_process_max_usec = maxi(_profile_process_max_usec, process_usec)

func reset_profiling() -> void:
	_profile_process_samples = 0
	_profile_process_total_usec = 0
	_profile_process_max_usec = 0

func profiling_snapshot() -> Dictionary:
	return {
		"samples": _profile_process_samples,
		"total_usec": _profile_process_total_usec,
		"average_usec": float(_profile_process_total_usec) / maxf(float(_profile_process_samples), 1.0),
		"max_usec": _profile_process_max_usec,
		"headless": _headless_audio,
	}

func update_surface_audio(speed: float, skid: float, grinding: bool, surface_kind: int = 0, airborne: bool = false) -> void:
	desired_speed = speed
	desired_skid = clampf(skid, 0.0, 1.0)
	desired_rail = 1.0 if grinding else 0.0
	desired_air = 1.0 if airborne else 0.0
	target_surface_kind = clampi(surface_kind, 0, 2)

func stop_feedback() -> void:
	InputManager.stop_rumble()
	target_speed = 0.0
	target_skid = 0.0
	target_rail = 0.0
	target_air = 0.0
	desired_speed = 0.0
	desired_skid = 0.0
	desired_rail = 0.0
	desired_air = 0.0
	pop_envelope = 0.0
	impact_envelope = 0.0

func pop_feedback(strength: float) -> void:
	pop_envelope = maxf(pop_envelope, clampf(strength, 0.0, 1.0))
	InputManager.rumble(0.08 * pop_envelope, 0.16 * pop_envelope, 0.07)

func shutdown_audio() -> void:
	_shutdown_requested = true
	stop_feedback()
	if feedback_player != null:
		# Release our playback reference before tearing down the stream/player so
		# the generator can drop its internal playback object cleanly.
		playback = null
		feedback_player.stop()
		feedback_player.stream = null
		# Tests and the quit path often shut audio down immediately before the
		# tree exits. Free synchronously so the generator playback reference is
		# released before ObjectDB performs its final leak audit.
		feedback_player.free()
	feedback_player = null

func landing_feedback(quality: float, impact: float) -> void:
	var strength := clampf(impact / 16.0, 0.08, 1.0)
	impact_envelope = maxf(impact_envelope, strength * (1.05 if quality < 0.42 else 0.72))
	InputManager.rumble(strength * 0.35, strength, 0.12 if quality > 0.35 else 0.3)

func skid_feedback(force: float) -> void:
	var now := Time.get_ticks_msec()
	if force > 0.25 and now - last_skid_rumble_ms >= 90:
		last_skid_rumble_ms = now
		InputManager.rumble(0.05 + force * 0.12, force * 0.2, 0.08)

func rail_feedback(speed: float) -> void:
	var now := Time.get_ticks_msec()
	if now - last_rail_rumble_ms < 110:
		return
	last_rail_rumble_ms = now
	InputManager.rumble(0.08, clampf(speed / 50.0, 0.08, 0.35), 0.1)

func crash_feedback() -> void:
	impact_envelope = 1.0
	InputManager.rumble(0.4, 1.0, 0.45)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)

func _apply_bus_settings() -> void:
	for bus_name: String in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			var key := bus_name.to_lower() + "_volume_db"
			AudioServer.set_bus_volume_db(index, float(GameSettings.active.get(key, 0.0)))
