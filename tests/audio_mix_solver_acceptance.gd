extends Node

var failures: Array[String] = []

func _ready() -> void:
	var solver := AudioMixSolver.new()
	var stopped := solver.resolve(0.0, 0.0, 0.0, 0)
	if float(stopped.surface_amplitude) != 0.0 or float(stopped.wind_amplitude) <= 0.0:
		failures.append("Stopped mix did not mute surface motion while retaining ambient wind")
	var powder_skid := solver.resolve(32.0, 1.0, 0.0, 0)
	var ice_skid := solver.resolve(32.0, 1.0, 0.0, 2)
	if float(powder_skid.surface_amplitude) <= float(ice_skid.surface_amplitude):
		failures.append("Surface policy no longer makes powder louder than ice")
	var airborne := solver.resolve(32.0, 1.0, 1.0, 0)
	if float(airborne.surface_amplitude) >= float(powder_skid.surface_amplitude) * 0.2:
		failures.append("Airborne mix did not suppress ground surface audio")
	if float(airborne.wind_amplitude) <= float(powder_skid.wind_amplitude):
		failures.append("Airborne mix did not strengthen wind")
	if failures.is_empty():
		print("AUDIO_MIX_SOLVER_PASS: surface, skid, and airborne mix policy remained bounded")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("AUDIO_MIX_SOLVER_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)
