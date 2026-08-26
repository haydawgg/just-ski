extends Node

var feedback_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var target_speed := 0.0
var target_skid := 0.0
var target_rail := 0.0
var phase := 0.0
var noise := RandomNumberGenerator.new()

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
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

func _process(_delta: float) -> void:
	if playback == null:
		return
	var frame_count := playback.get_frames_available()
	var mix_rate := 22050.0
	var speed_mix := clampf(target_speed / 32.0, 0.0, 1.0)
	var amplitude := 0.004 + speed_mix * 0.028 + target_skid * 0.05 + target_rail * 0.04
	if get_tree().paused:
		amplitude = 0.0
	for _frame: int in frame_count:
		phase = fmod(phase + (90.0 + target_speed * 9.0) / mix_rate, 1.0)
		var glide_noise := noise.randf_range(-1.0, 1.0) * (0.35 + target_skid * 0.65)
		var rail_tone := sin(phase * TAU) * target_rail
		var sample := (glide_noise + rail_tone * 0.7) * amplitude
		playback.push_frame(Vector2(sample, sample))

func update_surface_audio(speed: float, skid: float, grinding: bool) -> void:
	target_speed = move_toward(target_speed, speed, 1.0)
	target_skid = move_toward(target_skid, clampf(skid, 0.0, 1.0), 0.08)
	target_rail = move_toward(target_rail, 1.0 if grinding else 0.0, 0.12)

func stop_feedback() -> void:
	InputManager.stop_rumble()
	target_speed = 0.0
	target_skid = 0.0
	target_rail = 0.0

func shutdown_audio() -> void:
	stop_feedback()
	if feedback_player != null:
		feedback_player.stop()
		feedback_player.stream = null
		feedback_player.queue_free()
	feedback_player = null
	playback = null

func landing_feedback(quality: float, impact: float) -> void:
	var strength := clampf(impact / 16.0, 0.08, 1.0)
	InputManager.rumble(strength * 0.35, strength, 0.12 if quality > 0.35 else 0.3)

func skid_feedback(force: float) -> void:
	if force > 0.25:
		InputManager.rumble(0.05 + force * 0.12, force * 0.2, 0.06)

func rail_feedback(speed: float) -> void:
	InputManager.rumble(0.08, clampf(speed / 50.0, 0.08, 0.35), 0.08)

func crash_feedback() -> void:
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
