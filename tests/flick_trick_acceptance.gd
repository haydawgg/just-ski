extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_ground_preload_flick_pops()
	_test_directional_takeoffs()
	_test_invalid_and_repeated_gestures()
	_test_forgiving_input_buffer()
	_test_air_gesture_commands()
	_test_contextual_trigger_grabs()
	_test_grind_gestures()
	_test_motion_driven_recognition_and_scoring()
	if failures.is_empty():
		print("FLICK_PASS: takeoff, air, trigger, repeat, rejection, and rail gestures passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_FAIL: " + failure)
		get_tree().quit(1)

func _test_ground_preload_flick_pops() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	var command: TrickCommand
	sample.right_stick = Vector2(0.0, 0.8)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.08)
	if command.phase != TrickCommand.PresentationPhase.SETUP:
		failures.append("Downward right-stick preload did not enter setup")
	sample.right_stick = Vector2(0.0, -0.9)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.08)
	if command.kind != TrickCommand.Kind.POP:
		failures.append("Down-to-up right-stick gesture did not request a pop")
	if command.pop_strength < 0.7:
		failures.append("Committed pop was weaker than the forgiving minimum")

func _test_directional_takeoffs() -> void:
	var interpreter := FlickTrickInterpreter.new()
	_check_takeoff(interpreter, Vector2(-0.9, 0.0), TrickCommand.Kind.SPIN_LEFT, "left spin")
	interpreter.reset()
	_check_takeoff(interpreter, Vector2(0.9, 0.0), TrickCommand.Kind.SPIN_RIGHT, "right spin")
	interpreter.reset()
	_check_takeoff(interpreter, Vector2(-0.8, -0.8), TrickCommand.Kind.CORK_LEFT, "left cork")
	interpreter.reset()
	_check_takeoff(interpreter, Vector2(0.8, -0.8), TrickCommand.Kind.CORK_RIGHT, "right cork")

func _check_takeoff(interpreter: FlickTrickInterpreter, endpoint: Vector2, expected: int, label: String) -> void:
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2(0.0, 0.85)
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.06)
	sample.right_stick = endpoint.normalized()
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.08)
	if command.kind != expected or command.pop_strength <= 0.0:
		failures.append("Directional takeoff did not resolve %s" % label)

func _test_invalid_and_repeated_gestures() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2(0.0, 0.8)
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.06)
	sample.right_stick = Vector2(0.0, 0.4)
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.08)
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Sub-threshold gesture committed a trick")
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.4)
	sample.right_stick = Vector2(0.0, -1.0)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.01)
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Expired setup committed a late trick")

	interpreter.reset()
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	sample.right_stick = Vector2.LEFT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.SPIN_LEFT:
		failures.append("First airborne flick was not recognized")
	sample.right_stick = Vector2.RIGHT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.2)
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Gesture repeated without recentering")
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.RIGHT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.SPIN_RIGHT:
		failures.append("Gesture did not repeat after recenter and cooldown")

func _test_forgiving_input_buffer() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2(0.0, 0.85)
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.05)
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.38)
	sample.right_stick = Vector2.UP
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.02)
	if command.kind != TrickCommand.Kind.POP:
		failures.append("Gesture just inside the 120 ms forgiving buffer was rejected")

func _test_air_gesture_commands() -> void:
	var interpreter := FlickTrickInterpreter.new()
	_check_air_flick(interpreter, Vector2.UP, TrickCommand.Kind.FRONTFLIP, Vector3.RIGHT, "frontflip")
	_check_air_flick(interpreter, Vector2.DOWN, TrickCommand.Kind.BACKFLIP, Vector3.LEFT, "backflip")
	_check_air_flick(interpreter, Vector2(-0.8, -0.8).normalized(), TrickCommand.Kind.CORK_LEFT, Vector3(0.0, -1.0, -1.0).normalized(), "left cork")

func _check_air_flick(interpreter: FlickTrickInterpreter, endpoint: Vector2, expected: int, expected_axis: Vector3, label: String) -> void:
	interpreter.reset()
	var sample := TrickInputSample.new()
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = endpoint
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != expected:
		failures.append("Air gesture did not resolve %s" % label)
	if command.rotation_impulse.normalized().dot(expected_axis) < 0.7:
		failures.append("%s used the wrong rotation axis" % label)

func _test_contextual_trigger_grabs() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_trigger = 1.0
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.02)
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.grab_pose != TrickController.GrabPose.NONE:
		failures.append("Ground-held tuck trigger became an accidental grab")
	sample.right_trigger = 0.0
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	sample.right_trigger = 0.8
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.grab_pose != TrickController.GrabPose.SAFETY_RIGHT:
		failures.append("Fresh airborne right trigger did not grab with the right hand")
	if command.phase != TrickCommand.PresentationPhase.GRAB:
		failures.append("Active trigger grab did not enter the grab presentation phase")

	interpreter.reset()
	sample.reset()
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	sample.left_trigger = 1.0
	sample.right_trigger = 1.0
	sample.right_stick = Vector2.UP
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.grab_pose != TrickController.GrabPose.SPREAD_EAGLE:
		failures.append("Dual triggers plus up did not resolve Spread Eagle")
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Grab tweak also committed a rotation gesture")

func _test_grind_gestures() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	interpreter.step(sample, FlickTrickInterpreter.Context.GRIND, 0.11)
	sample.right_stick = Vector2.LEFT
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.GRIND, 0.02)
	if command.kind != TrickCommand.Kind.RAIL_SLIDE_LEFT:
		failures.append("Left rail flick did not select a left boardslide")
	interpreter.reset()
	sample.right_stick = Vector2(0.0, 0.8)
	interpreter.step(sample, FlickTrickInterpreter.Context.GRIND, 0.05)
	sample.right_stick = Vector2.UP
	command = interpreter.step(sample, FlickTrickInterpreter.Context.GRIND, 0.06)
	if command.kind != TrickCommand.Kind.RAIL_POP:
		failures.append("Down-to-up rail gesture did not pop off")

func _test_motion_driven_recognition_and_scoring() -> void:
	var tricks := TrickController.new()
	add_child(tricks)
	var landed_count := [0]
	var landed_name := [""]
	var landed_points := [0]
	tricks.trick_landed.connect(func(name: String, points: int, _quality: float) -> void:
		landed_count[0] += 1
		landed_name[0] = name
		landed_points[0] = points
	)
	var command := TrickCommand.new()
	command.kind = TrickCommand.Kind.SPIN_LEFT
	command.committed = true
	tricks.begin_air(false, TrickCommand.Kind.SPIN_LEFT)
	tricks.update_air(Vector3.ZERO, 0.2, command)
	tricks.land(1.0, false)
	if landed_count[0] != 0:
		failures.append("A recognized input with no completed physical rotation earned points")

	tricks.begin_air(false, TrickCommand.Kind.SPIN_LEFT)
	command.reset()
	command.kind = TrickCommand.Kind.SPIN_LEFT
	command.committed = true
	tricks.update_air(Vector3(0.0, -TAU, 0.0), 1.0, command)
	command.reset()
	command.phase = TrickCommand.PresentationPhase.GRAB
	command.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	command.grab_amount = 1.0
	command.grab_tweak = Vector2(0.0, 0.8)
	tricks.update_air(Vector3.ZERO, 0.6, command)
	tricks.land(1.0, false)
	if landed_count[0] != 1:
		failures.append("Completed spin and grab did not emit a landed trick")
	if "Left 360" not in landed_name[0] or "Safety Grab Left" not in landed_name[0]:
		failures.append("Completed physical trick was named incorrectly: %s" % landed_name[0])
	if landed_points[0] <= 870:
		failures.append("Grab duration and tweak did not add to the completed trick score")
