extends Node

const SIMULATION_SECONDS := 3.0
const RATES := [30, 60, 120]

var failures: Array[String] = []

func _ready() -> void:
	_validate_uphill_reversal()
	_validate_flat_rail_stall()
	_validate_gravity_assisted_crawl()
	_validate_mild_opposed_slope_reversal()
	_validate_cross_rate_consistency()
	if failures.is_empty():
		print("RAIL_REVERSAL_PASS: uphill zero crossing, flat-rail stall, and crawl policy hold at 30/60/120 Hz")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RAIL_REVERSAL_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _simulate(slope_acceleration: float, friction: float, initial_speed: float, rate: int) -> Dictionary:
	var solver := RailMotionSolver.new()
	var speed := initial_speed
	var offset := 20.0
	var direction := 1.0
	var path_length := 100.0
	var delta := 1.0 / float(rate)
	var steps := int(round(SIMULATION_SECONDS * rate))
	var sign_changes := 0
	var previous_sign := signf(speed)
	var reversed_seen := false
	var stalled_seen := false
	var consecutive_stalled := 0
	var max_consecutive_stalled := 0
	for _step: int in steps:
		var result := solver.advance(speed, offset, direction, path_length, slope_acceleration, friction, delta)
		reversed_seen = reversed_seen or result.reversed
		stalled_seen = stalled_seen or result.stalled
		if result.stalled:
			consecutive_stalled += 1
			max_consecutive_stalled = maxi(max_consecutive_stalled, consecutive_stalled)
		else:
			consecutive_stalled = 0
		var current_sign := signf(result.speed)
		if current_sign != 0.0 and previous_sign != 0.0 and current_sign != previous_sign:
			sign_changes += 1
		if current_sign != 0.0:
			previous_sign = current_sign
		speed = result.speed
		offset = result.offset
	return {
		"speed": speed,
		"offset": offset,
		"sign_changes": sign_changes,
		"reversed_seen": reversed_seen,
		"stalled_seen": stalled_seen,
		"max_consecutive_stalled": max_consecutive_stalled,
		"rate": rate,
	}

func _validate_uphill_reversal() -> void:
	for rate: int in RATES:
		var run := _simulate(-2.0, 0.1, 0.5, rate)
		if float(run.speed) >= 0.0:
			failures.append("Uphill grind at %d Hz did not reverse (final speed %.3f)" % [rate, run.speed])
			continue
		if int(run.sign_changes) != 1:
			failures.append("Uphill grind at %d Hz crossed zero %d times instead of once" % [rate, run.sign_changes])
		if not bool(run.reversed_seen):
			failures.append("Uphill reversal at %d Hz never raised the reversed flag" % rate)
		if int(run.max_consecutive_stalled) > rate / 2:
			failures.append("Uphill reversal at %d Hz reported a sustained stall (%d frames)" % [rate, run.max_consecutive_stalled])

func _validate_flat_rail_stall() -> void:
	for rate: int in RATES:
		var run := _simulate(0.0, 0.5, 0.5, rate)
		if absf(float(run.speed)) > 0.02:
			failures.append("Flat rail at %d Hz did not stall to rest (final speed %.3f)" % [rate, run.speed])
		if int(run.sign_changes) != 0:
			failures.append("Flat rail at %d Hz oscillated through zero" % rate)
		if not bool(run.stalled_seen) or int(run.max_consecutive_stalled) < 30:
			failures.append("Flat rail at %d Hz never reported the stalled state" % rate)

func _validate_gravity_assisted_crawl() -> void:
	for rate: int in RATES:
		var run := _simulate(2.0, 0.1, 0.1, rate)
		if float(run.speed) <= 0.35:
			failures.append("Gravity-assisted crawl at %d Hz lost forward motion (final speed %.3f)" % [rate, run.speed])

func _validate_mild_opposed_slope_reversal() -> void:
	for rate: int in RATES:
		var run := _simulate(-0.2, 0.05, 0.3, rate)
		if float(run.speed) >= 0.0:
			failures.append("Mild uphill grind at %d Hz did not reverse (final speed %.3f)" % [rate, run.speed])
		if int(run.sign_changes) != 1:
			failures.append("Mild uphill grind at %d Hz crossed zero %d times" % [rate, run.sign_changes])

func _validate_cross_rate_consistency() -> void:
	var runs: Array[Dictionary] = []
	for rate: int in RATES:
		runs.append(_simulate(-2.0, 0.1, 0.5, rate))
	var reference: Dictionary = runs[2]
	for run: Dictionary in runs:
		if absf(float(run.speed) - float(reference.speed)) > 0.5:
			failures.append("Reversal speed at %d Hz diverged from 120 Hz by %.3f" % [int(run.rate), absf(float(run.speed) - float(reference.speed))])
		if signf(float(run.speed)) != signf(float(reference.speed)):
			failures.append("Reversal sign at %d Hz disagrees with 120 Hz" % int(run.rate))
		if absf(float(run.offset) - float(reference.offset)) > 0.5:
			failures.append("Reversal offset at %d Hz diverged from 120 Hz by %.3f" % [int(run.rate), absf(float(run.offset) - float(reference.offset))])
