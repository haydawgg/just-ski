extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_ground_preload_flick_pops()
	_test_directional_takeoffs()
	_test_preload_quality_orders_strength()
	_test_invalid_ground_gestures()
	_test_forgiving_input_buffer()
	_test_air_rotation_requires_preload()
	_test_legacy_air_flip_commands()
	_test_contextual_trigger_grabs()
	_test_grind_gestures()
	_test_motion_driven_recognition_and_scoring()
	_test_live_degrees_are_not_finalized()
	if failures.is_empty():
		print("FLICK_PASS: preload quality, takeoff commitment, bounded air management, grabs, scoring, and rails passed")
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
	if command.setup_duration <= 0.0 or command.setup_depth < 0.8:
		failures.append("Setup telemetry did not record preload depth/duration")
	sample.right_stick = Vector2(0.0, -0.9)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.08)
	if command.kind != TrickCommand.Kind.POP:
		failures.append("Down-to-up right-stick gesture did not request a pop")
	if command.pop_strength < 0.35:
		failures.append("Committed pop fell below the configured minimum command strength")
	if command.setup_quality <= 0.0 or command.release_speed <= 0.0:
		failures.append("Committed pop did not expose setup quality and release speed")

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
	if expected in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT, TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT] and not command.takeoff_rotation_committed:
		failures.append("%s did not mark rotational takeoff commitment" % label)

func _test_preload_quality_orders_strength() -> void:
	var weak := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2(0.0, 0.58)
	weak.step(sample, FlickTrickInterpreter.Context.GROUND, 0.04)
	sample.right_stick = Vector2(-0.65, 0.0)
	var weak_command := weak.step(sample, FlickTrickInterpreter.Context.GROUND, 0.05)

	var strong := FlickTrickInterpreter.new()
	sample.reset()
	sample.right_stick = Vector2(0.0, 1.0)
	strong.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	strong.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	var strong_command := strong.step(sample, FlickTrickInterpreter.Context.GROUND, 0.05)

	if weak_command.kind != TrickCommand.Kind.SPIN_LEFT or strong_command.kind != TrickCommand.Kind.SPIN_LEFT:
		failures.append("Preload quality comparison did not produce matching spin families")
		return
	if strong_command.setup_quality <= weak_command.setup_quality:
		failures.append("Strong preload did not measure higher setup quality than weak preload")
	if strong_command.rotation_impulse.length() <= weak_command.rotation_impulse.length():
		failures.append("Strong preload did not produce more takeoff rotation than weak preload")

func _test_invalid_ground_gestures() -> void:
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
		failures.append("Gesture just inside the forgiving input buffer was rejected")

func _test_air_rotation_requires_preload() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.LEFT
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.NONE or command.rotation_impulse.length() > 0.001:
		failures.append("Neutral-air spin flick created major rotation without takeoff preload")

	interpreter.reset()
	sample.reset()
	sample.right_stick = Vector2(0.0, 0.9)
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	var takeoff := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.06)
	var takeoff_impulse := takeoff.rotation_impulse.length()
	if takeoff.kind != TrickCommand.Kind.SPIN_LEFT or not takeoff.takeoff_rotation_committed:
		failures.append("Preloaded left spin did not establish takeoff commitment")
		return

	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.12)
	sample.right_stick = Vector2.LEFT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.SPIN_LEFT or command.air_management != TrickCommand.AirManagement.CONTINUE:
		failures.append("Same-direction air input did not continue the committed spin")
	if command.rotation_impulse.length() <= 0.0 or command.rotation_impulse.length() >= takeoff_impulse:
		failures.append("Air continuation was not lower-authority than the takeoff")

	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.RIGHT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.SPIN_LEFT or command.air_management != TrickCommand.AirManagement.CHECK:
		failures.append("Opposite-direction air input did not check the committed spin")
	if command.rotation_impulse.y <= 0.0:
		failures.append("Spin check did not apply opposing angular authority")

	interpreter.reset()
	sample.reset()
	sample.right_stick = Vector2(0.0, 0.9)
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.10)
	sample.right_stick = Vector2.LEFT
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.06)
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.12)
	sample.right_stick = Vector2(-0.8, -0.8).normalized()
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Air input switched a committed spin into a cork family")

func _test_legacy_air_flip_commands() -> void:
	# Flip preload mapping is a separate migration step. Keep the established
	# flip path covered until that mapping is introduced so this control family
	# is not accidentally deleted while spin/cork authority moves to takeoff.
	var interpreter := FlickTrickInterpreter.new()
	_check_legacy_air_flip(interpreter, Vector2.UP, TrickCommand.Kind.FRONTFLIP, Vector3.RIGHT, "frontflip")
	_check_legacy_air_flip(interpreter, Vector2.DOWN, TrickCommand.Kind.BACKFLIP, Vector3.LEFT, "backflip")

func _check_legacy_air_flip(interpreter: FlickTrickInterpreter, endpoint: Vector2, expected: int, expected_axis: Vector3, label: String) -> void:
	interpreter.reset()
	var sample := TrickInputSample.new()
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = endpoint
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.kind != expected:
		failures.append("Legacy air gesture did not preserve %s during migration" % label)
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
	if command.style_pose != TrickController.StylePose.SPREAD_EAGLE:
		failures.append("Dual triggers plus up did not resolve Spread Eagle")
	if command.grab_pose != TrickController.GrabPose.NONE:
		failures.append("Style input also selected a hand-to-ski grab")
	if command.kind != TrickCommand.Kind.NONE:
		failures.append("Grab tweak also committed a rotation gesture")
	sample.right_stick = Vector2.LEFT
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.style_pose != TrickController.StylePose.SHIFTY_LEFT:
		failures.append("Dual triggers plus left did not resolve Shifty Left")
	sample.right_stick = Vector2(0.8, 0.6)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.style_pose != TrickController.StylePose.SHIFTY_RIGHT:
		failures.append("Horizontal-dominant diagonal did not resolve Shifty Right")
	sample.right_stick = Vector2(0.6, -0.8)
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.style_pose != TrickController.StylePose.SPREAD_EAGLE:
		failures.append("Vertical-dominant diagonal did not preserve Spread Eagle")
	sample.right_stick = Vector2.ZERO
	command = interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	if command.grab_pose != TrickController.GrabPose.DOUBLE or command.style_pose != TrickController.StylePose.NONE:
		failures.append("Centered dual triggers did not preserve Double Grab")

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
	tricks.set_grab_contact(1.0, "HOLD", 0.12)
	command.reset()
	tricks.update_air(Vector3.ZERO, 0.2, command)
	if "Safety Grab Left" not in tricks.current_name():
		failures.append("Releasing a grab before touchdown erased it from the active trick")
	tricks.land(1.0, false)
	if landed_count[0] != 1:
		failures.append("Completed spin and grab did not emit a landed trick")
	if "Left 360" not in landed_name[0] or "Safety Grab Left" not in landed_name[0]:
		failures.append("Completed physical trick was named incorrectly: %s" % landed_name[0])
	if landed_points[0] <= 870:
		failures.append("Released grab duration and tweak did not add to the completed trick score")

	tricks.begin_air(false, TrickCommand.Kind.POP)
	command.reset()
	command.phase = TrickCommand.PresentationPhase.GRAB
	command.style_pose = TrickController.StylePose.SHIFTY_LEFT
	command.style_amount = 1.0
	command.grab_tweak = Vector2.LEFT
	tricks.update_air(Vector3.ZERO, 0.6, command)
	command.reset()
	tricks.update_air(Vector3.ZERO, 0.1, command)
	if "Shifty Left" not in tricks.current_name() or tricks.grab_pose != TrickController.GrabPose.NONE:
		failures.append("Releasing a shifty erased its name or contaminated the grab channel")
	tricks.land(1.0, false)
	if landed_count[0] != 2 or "Shifty Left" not in landed_name[0]:
		failures.append("Shifty did not produce a separately recognized landed style")
	if landed_points[0] < 220:
		failures.append("Shifty did not preserve the existing style scoring path")

func _test_live_degrees_are_not_finalized() -> void:
	var tricks := TrickController.new()
	add_child(tricks)
	var live_text := [""]
	var landed_text := [""]
	tricks.trick_changed.connect(func(text: String) -> void: live_text[0] = text)
	tricks.trick_landed.connect(func(text: String, _points: int, _quality: float) -> void: landed_text[0] = text)
	var command := TrickCommand.new()
	command.kind = TrickCommand.Kind.SPIN_LEFT
	command.committed = true
	tricks.begin_air(false, TrickCommand.Kind.SPIN_LEFT)
	tricks.update_air(Vector3(0.0, -deg_to_rad(243.0), 0.0), 1.0, command)
	if live_text[0] != "Left 243°":
		failures.append("Airborne trick text did not report live degrees: %s" % live_text[0])
	if tricks.current_name() != "Left 180":
		failures.append("Finalized trick naming stopped using scored rotation buckets")
	tricks.land(1.0, false)
	if landed_text[0] != "Left 180":
		failures.append("Contact result did not use the finalized scored trick: %s" % landed_text[0])
	tricks.queue_free()
