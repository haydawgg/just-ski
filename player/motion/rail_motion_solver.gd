class_name RailMotionSolver
extends RefCounted

## Rail movement is a sampled solver. The controller owns rail resources and
## scene transforms; this module owns scalar speed/offset/balance policy.

func advance(
	current_speed: float,
	current_offset: float,
	direction: float,
	path_length: float,
	slope_acceleration: float,
	friction: float,
	delta: float
) -> RailMotionResult:
	var result := RailMotionResult.new()
	result.speed = current_speed + slope_acceleration * delta
	result.speed = move_toward(result.speed, 0.0, friction * delta)
	# Gravity integrating through zero is a legitimate reversal; the crawl
	# floor only sustains travel while gravity assists the current direction,
	# so an uphill grind can stop and reverse instead of being held at a crawl.
	result.reversed = (
		not is_zero_approx(signf(result.speed))
		and not is_zero_approx(signf(current_speed))
		and signf(result.speed) != signf(current_speed)
	)
	if not result.reversed and absf(result.speed) < 0.35 and slope_acceleration * signf(current_speed) > 0.0:
		result.speed = signf(current_speed) * 0.35
	result.stalled = absf(result.speed) < 0.05
	result.offset = current_offset + result.speed * direction * delta
	result.reached_end = result.offset <= 0.02 or result.offset >= path_length - 0.02
	return result

func update_balance(
	current_balance: float,
	input_value: float,
	drift: float,
	authored_drift_bias: float,
	input_gain: float,
	delta: float
) -> float:
	var balance := current_balance
	if absf(balance) > 0.08:
		balance += signf(balance) * drift * delta
	else:
		balance += authored_drift_bias * drift * delta
	balance += -input_value * input_gain * delta
	return clampf(balance, -1.35, 1.35)

func instability(kink: float, rail_pose: int, profile: SkiPhysicsProfile) -> float:
	var boardslide_factor := 1.0 + absf(float(rail_pose)) * profile.rail_boardslide_instability
	return (profile.rail_balance_drift + maxf(kink, 0.0) * profile.rail_kink_instability) * boardslide_factor

func has_failed(balance: float, failure_threshold: float) -> bool:
	return absf(balance) >= maxf(failure_threshold, 0.0)
