extends Node

var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _ready() -> void:
	_rows_for_preload_strength()
	_rows_for_air_authority()
	_validate_relationships()
	for row: Dictionary in rows:
		print("TRICK_ROTATION_BENCHMARK: " + JSON.stringify(row))
	if failures.is_empty():
		print("TRICK_ROTATION_BENCHMARK_PASS: preload and air-authority relationships are ordered")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("TRICK_ROTATION_BENCHMARK_FAIL: " + failure)
		get_tree().quit(1)

func _rows_for_preload_strength() -> void:
	rows.append(_measure_takeoff("weak", 0.58, 0.04, Vector2(-0.65, 0.0), 0.05))
	rows.append(_measure_takeoff("medium", 0.78, 0.12, Vector2(-0.82, 0.0), 0.05))
	rows.append(_measure_takeoff("strong", 1.0, 0.22, Vector2.LEFT, 0.05))

func _rows_for_air_authority() -> void:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2.DOWN
	interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.22)
	sample.right_stick = Vector2.LEFT
	var takeoff := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, 0.05)
	var total_takeoff := takeoff.rotation_impulse
	sample.reset()
	while float(interpreter.snapshot().get("takeoff_release_fraction", 0.0)) < 1.0:
		var release := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 1.0 / 60.0)
		total_takeoff += release.rotation_impulse

	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.LEFT
	var continuation_one := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	var continuation_one_impulse := continuation_one.rotation_impulse.length()
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.LEFT
	var continuation_two := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	var continuation_two_impulse := continuation_two.rotation_impulse.length()
	sample.right_stick = Vector2.ZERO
	interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.LEFT
	var continuation_three := interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	var continuation_three_impulse := continuation_three.rotation_impulse.length()

	rows.append({
		"scenario": "air_authority",
		"takeoff_total_impulse": total_takeoff.length(),
		"continuation_1": continuation_one_impulse,
		"continuation_2": continuation_two_impulse,
		"continuation_3": continuation_three_impulse,
		"remaining_budget": float(interpreter.snapshot().get("air_authority_remaining", -1.0)),
	})

	var neutral := FlickTrickInterpreter.new()
	sample.reset()
	neutral.step(sample, FlickTrickInterpreter.Context.AIR, 0.11)
	sample.right_stick = Vector2.LEFT
	var neutral_command := neutral.step(sample, FlickTrickInterpreter.Context.AIR, 0.02)
	rows.append({
		"scenario": "neutral_air_spin",
		"impulse": neutral_command.rotation_impulse.length(),
		"committed": neutral_command.committed,
	})

func _measure_takeoff(label: String, setup_depth: float, setup_seconds: float, release: Vector2, release_delta: float) -> Dictionary:
	var interpreter := FlickTrickInterpreter.new()
	var sample := TrickInputSample.new()
	sample.right_stick = Vector2(0.0, setup_depth)
	var elapsed := 0.0
	while elapsed < setup_seconds:
		var dt := minf(1.0 / 60.0, setup_seconds - elapsed)
		interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, dt)
		elapsed += dt
	sample.right_stick = release
	var command := interpreter.step(sample, FlickTrickInterpreter.Context.GROUND, release_delta)
	var setup_depth_value := command.setup_depth
	var setup_duration_value := command.setup_duration
	var release_speed_value := command.release_speed
	var setup_quality_value := command.setup_quality
	var command_strength_value := command.gesture_strength
	var kind_value := command.kind
	var total_impulse := command.rotation_impulse
	sample.reset()
	var guard := 0
	while float(interpreter.snapshot().get("takeoff_release_fraction", 0.0)) < 1.0 and guard < 100:
		total_impulse += interpreter.step(sample, FlickTrickInterpreter.Context.AIR, 1.0 / 60.0).rotation_impulse
		guard += 1
	return {
		"scenario": "preload_" + label,
		"setup_depth": setup_depth_value,
		"setup_duration": setup_duration_value,
		"release_speed": release_speed_value,
		"setup_quality": setup_quality_value,
		"command_strength": command_strength_value,
		"total_takeoff_impulse": total_impulse.length(),
		"kind": TrickCommand.Kind.keys()[kind_value],
	}

func _validate_relationships() -> void:
	if rows.size() < 5:
		failures.append("Benchmark did not produce all expected scenarios")
		return
	var weak := rows[0]
	var medium := rows[1]
	var strong := rows[2]
	if not (float(weak.setup_quality) < float(medium.setup_quality) and float(medium.setup_quality) < float(strong.setup_quality)):
		failures.append("Preload setup quality was not ordered weak < medium < strong")
	if not (float(weak.total_takeoff_impulse) < float(medium.total_takeoff_impulse) and float(medium.total_takeoff_impulse) < float(strong.total_takeoff_impulse)):
		failures.append("Physical takeoff impulse was not ordered weak < medium < strong")
	var air := rows[3]
	if float(air.continuation_1) >= float(air.takeoff_total_impulse):
		failures.append("Air continuation authority matched/exceeded the committed takeoff")
	if float(air.continuation_3) >= float(air.continuation_1):
		failures.append("Repeated air continuation did not diminish as the finite budget was consumed")
	var neutral := rows[4]
	if float(neutral.impulse) > 0.001 or bool(neutral.committed):
		failures.append("Neutral-air spin benchmark still produced a committed impulse")
