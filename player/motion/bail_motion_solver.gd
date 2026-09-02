class_name BailMotionSolver
extends RefCounted

func step_motion(
	current_velocity: Vector3,
	current_angular_velocity: Vector3,
	ground_normal: Vector3,
	grounded: bool,
	stage: int,
	delta: float,
	profile: SkiPhysicsProfile
) -> BailMotionResult:
	var result := BailMotionResult.new()
	result.velocity = current_velocity + Vector3.DOWN * profile.air_gravity * delta
	result.angular_velocity = current_angular_velocity
	if grounded:
		var normal := ground_normal.normalized() if ground_normal.length_squared() > 0.0001 else Vector3.UP
		result.velocity = result.velocity.slide(normal)
		var ground_damping := profile.bail_ground_damping
		var angular_damping := profile.crash_ground_angular_damping
		if stage == CrashContext.Stage.FALL:
			ground_damping *= 0.55
			angular_damping *= 0.6
		elif stage == CrashContext.Stage.REST:
			ground_damping *= 0.38
			angular_damping *= 0.45
		result.velocity *= exp(-ground_damping * delta)
		result.angular_velocity *= exp(-angular_damping * delta)
		if stage == CrashContext.Stage.REST and result.velocity.length() > 0.15:
			var wobble_axis := normal.cross(result.velocity.normalized())
			if wobble_axis.length_squared() > 0.001:
				result.angular_velocity += wobble_axis.normalized() * 0.08 * clampf(result.velocity.length() / 5.0, 0.0, 1.0) * delta
	else:
		result.angular_velocity *= exp(-profile.crash_air_angular_damping * delta)
	return result

func resolve_rest(
	grounded: bool,
	elapsed: float,
	linear_speed: float,
	angular_speed: float,
	rest_detected: bool,
	rest_elapsed: float,
	delta: float,
	release_duration: float,
	impact_duration: float,
	profile: SkiPhysicsProfile
) -> BailMotionResult:
	var result := BailMotionResult.new()
	result.rest_detected = rest_detected
	result.rest_elapsed = rest_elapsed
	var impact_end := release_duration + impact_duration
	if elapsed < release_duration:
		result.stage = CrashContext.Stage.RELEASE
	elif elapsed < impact_end:
		result.stage = CrashContext.Stage.IMPACT
	elif not rest_detected:
		result.stage = CrashContext.Stage.FALL
	else:
		result.stage = CrashContext.Stage.REST
	var resting_candidate := grounded and elapsed >= profile.crash_min_duration and linear_speed <= profile.crash_rest_speed and angular_speed <= profile.crash_rest_angular_speed
	if not result.rest_detected:
		result.rest_elapsed = rest_elapsed + delta if resting_candidate else 0.0
		if result.rest_elapsed >= profile.crash_rest_confirm_time or (grounded and elapsed >= profile.crash_max_duration):
			result.rest_detected = true
			result.rest_elapsed = 0.0
			result.stage = CrashContext.Stage.REST
	else:
		result.stage = CrashContext.Stage.REST
		result.rest_elapsed = rest_elapsed + delta
		result.should_recover = result.rest_elapsed >= profile.crash_rest_hold_time
	return result
