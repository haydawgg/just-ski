extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_release_total_is_tick_rate_independent()
	_test_release_is_distributed_not_instant()
	_test_grab_does_not_interrupt_release()
	_test_reset_clears_pending_release()
	if failures.is_empty():
		print("FLICK_TAKEOFF_RELEASE_PASS: distributed takeoff impulse is bounded and frame-rate consistent")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_TAKEOFF_RELEASE_FAIL: " + failure)
		get_tree().quit(1)

func _test_release_total_is_tick_rate_independent() -> void:
	var at_30 := _integrated_spin_release(30)
	var at_60 := _integrated_spin_release(60)
	var at_120 := _integrated_spin_release(120)
	var expected := Vector3(0.0, -6.9, 0.0)
	if at_30.distance_to(expected) > 0.002:
		failures.append("30 Hz interpreter release did not sum to the requested spin impulse")
	if at_60.distance_to(expected) > 0.002:
		failures.append("60 Hz interpreter release did not sum to the requested spin impulse")
	if at_120.distance_to(expected) > 0.002:
		failures.append("120 Hz interpreter release did not sum to the requested spin impulse")
	if at_30.distance_to(at_120) > 0.002 or at_60.distance_to(at_120) > 0.002:
		failures.append("Interpreter takeoff impulse total changed with physics tick rate")

func _test_release_is_distributed_not_instant() -> void:
	var profile := _release_test_profile()
	var interpreter := FlickTrickInterpreter.new(profile)
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2.DOWN
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	var takeoff := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 1.0 / 60.0)
	if takeoff.rotation_impulse.length() <= 0.0:
		failures.append("Takeoff release did not begin on the committed ground frame")
	if takeoff.rotation_impulse.length() >= profile.spin_impulse * 0.95:
		failures.append("Takeoff still applied essentially the full spin impulse in one frame")
	var snapshot := interpreter.snapshot()
	var release_fraction := float(snapshot.get("takeoff_release_fraction", 0.0))
	if release_fraction <= 0.0 or release_fraction >= 1.0:
		failures.append("Takeoff release fraction was not partially consumed after the first frame")

func _test_grab_does_not_interrupt_release() -> void:
	var interpreter := FlickTrickInterpreter.new(_release_test_profile())
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2.DOWN
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 1.0 / 60.0)

	sample.reset()
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 1.0 / 60.0)
	sample.right_trigger = 0.8
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 1.0 / 60.0)
	if command.phase != TrickCommand.PresentationPhase.GRAB:
		failures.append("Fresh airborne trigger did not enter grab phase during takeoff release")
	if command.rotation_impulse.length() <= 0.0 or not command.committed:
		failures.append("Grab input interrupted the remaining preloaded takeoff rotation")

func _test_reset_clears_pending_release() -> void:
	var interpreter := FlickTrickInterpreter.new(_release_test_profile())
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2.DOWN
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 1.0 / 60.0)
	interpreter.reset()
	var snapshot := interpreter.snapshot()
	if bool(snapshot.get("takeoff_rotation_committed", true)):
		failures.append("Interpreter reset left takeoff rotation committed")
	if float(snapshot.get("takeoff_release_fraction", -1.0)) != 0.0:
		failures.append("Interpreter reset did not clear takeoff release progress")
	if (snapshot.get("pending_takeoff_impulse", Vector3.ONE) as Vector3) != Vector3.ZERO:
		failures.append("Interpreter reset left a pending takeoff impulse")

func _integrated_spin_release(hz: int) -> Vector3:
	var profile := _release_test_profile()
	var interpreter := FlickTrickInterpreter.new(profile)
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2.DOWN
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	var delta := 1.0 / float(hz)
	var takeoff := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, delta)
	var total := takeoff.rotation_impulse
	sample.reset()
	var guard := 0
	while float(interpreter.snapshot().get("takeoff_release_fraction", 0.0)) < 1.0 and guard < 1000:
		var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, delta)
		total += command.rotation_impulse
		guard += 1
	return total

func _release_test_profile() -> FlickTrickProfile:
	var profile := FlickTrickProfile.new()
	profile.minimum_command_strength = 0.0
	profile.setup_depth_weight = 1.0
	profile.setup_duration_weight = 0.0
	profile.release_speed_weight = 0.0
	profile.takeoff_release_duration = 0.14
	return profile
