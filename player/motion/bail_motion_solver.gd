class_name BailMotionSolver
extends RefCounted

const TRAVEL_EPSILON_SQ := 0.0025
const AXIS_EPSILON_SQ := 0.0001
const NORMAL_EPSILON_SQ := 0.0001
const BASIS_ANGLE_EPSILON := 0.000001

func step_motion(
	current_velocity: Vector3,
	current_angular_velocity: Vector3,
	ground_normal: Vector3,
	grounded: bool,
	stage: int,
	delta: float,
	profile: SkiPhysicsProfile,
	body_basis: Basis = Basis.IDENTITY
) -> BailMotionResult:
	var result := BailMotionResult.new()
	var incoming_velocity := current_velocity if _finite_vector(current_velocity) else Vector3.ZERO
	var incoming_angular := current_angular_velocity if _finite_vector(current_angular_velocity) else Vector3.ZERO
	result.velocity = incoming_velocity + Vector3.DOWN * profile.air_gravity * delta
	result.angular_velocity = incoming_angular
	if not _finite_vector(result.velocity):
		result.velocity = Vector3.ZERO
	if grounded:
		var sampled_normal := _safe_normal(ground_normal)
		var linear_normal := sampled_normal if sampled_normal.length_squared() >= NORMAL_EPSILON_SQ else Vector3.UP
		result.velocity = result.velocity.slide(linear_normal)
		result.planar_travel = planar_travel(result.velocity, sampled_normal)
		var ground_damping := profile.bail_ground_damping
		var angular_damping := profile.crash_ground_angular_damping
		if stage == CrashContext.Stage.FALL:
			ground_damping *= 0.55
			angular_damping *= 0.6
		result.velocity *= exp(-ground_damping * delta)
		result.planar_travel = planar_travel(result.velocity, sampled_normal)
		result.angular_velocity *= exp(-angular_damping * delta)
		if stage == CrashContext.Stage.FALL:
			_apply_ground_roll(result, sampled_normal, body_basis, profile)
		result.align_rate = ground_align_rate(stage, result.planar_travel.length(), profile)
	else:
		result.angular_velocity *= exp(-profile.crash_air_angular_damping * delta)
	return result

func planar_travel(velocity: Vector3, ground_normal: Vector3) -> Vector3:
	if not _finite_vector(velocity):
		return Vector3.ZERO
	var normal := _safe_normal(ground_normal)
	if normal.length_squared() < NORMAL_EPSILON_SQ:
		return Vector3.ZERO
	var travel := velocity.slide(normal)
	if not _finite_vector(travel):
		return Vector3.ZERO
	return travel

func surface_roll_axis(ground_normal: Vector3, travel: Vector3) -> Vector3:
	var normal := _safe_normal(ground_normal)
	if normal.length_squared() < NORMAL_EPSILON_SQ:
		return Vector3.ZERO
	if not _finite_vector(travel) or travel.length_squared() < TRAVEL_EPSILON_SQ:
		return Vector3.ZERO
	var axis := normal.cross(travel.normalized())
	if not _finite_vector(axis) or axis.length_squared() < AXIS_EPSILON_SQ:
		return Vector3.ZERO
	return axis.normalized()

func surface_roll_speed(planar_speed: float, profile: SkiPhysicsProfile) -> float:
	if not is_finite(planar_speed) or planar_speed < maxf(profile.crash_roll_min_travel, 0.0):
		return 0.0
	var radius := maxf(profile.crash_roll_body_radius, 0.05)
	var fade_speed := maxf(profile.crash_roll_fade_speed, 0.001)
	var fade := clampf(planar_speed / fade_speed, 0.0, 1.0)
	var uncapped := planar_speed / radius
	var capped := minf(uncapped, maxf(profile.crash_roll_max_angular_speed, 0.0))
	return capped * fade

func ground_align_rate(stage: int, planar_speed: float, profile: SkiPhysicsProfile) -> float:
	var base := maxf(profile.bail_ground_align_rate, 0.0)
	if stage == CrashContext.Stage.REST or stage == CrashContext.Stage.RECOVERY:
		return base
	var safe_speed := planar_speed if is_finite(planar_speed) else 0.0
	var reference := maxf(profile.crash_align_speed_reference, 0.001)
	var speed_ratio := clampf(safe_speed / reference, 0.0, 1.0)
	var fast := clampf(profile.crash_align_fall_fast_factor, 0.0, 1.0)
	var slow := clampf(profile.crash_align_fall_slow_factor, 0.0, 1.0)
	# Alignment may not strengthen as travel speed increases.
	if slow < fast:
		slow = fast
	return base * lerpf(slow, fast, speed_ratio)

func couple_surface_roll(
	local_angular_velocity: Vector3,
	ground_normal: Vector3,
	travel: Vector3,
	body_basis: Basis,
	profile: SkiPhysicsProfile
) -> Vector3:
	if not _finite_vector(local_angular_velocity):
		return Vector3.ZERO
	var axis := surface_roll_axis(ground_normal, travel)
	var planar_speed := travel.length() if _finite_vector(travel) else 0.0
	if axis.length_squared() < AXIS_EPSILON_SQ or planar_speed < maxf(profile.crash_roll_min_travel, 0.0):
		return local_angular_velocity
	var fade_speed := maxf(profile.crash_roll_fade_speed, 0.001)
	var fade := clampf(planar_speed / fade_speed, 0.0, 1.0)
	var coupling := clampf(profile.crash_roll_coupling, 0.0, 1.0) * fade
	if coupling <= 0.0:
		return local_angular_velocity
	var safe_basis := body_basis.orthonormalized()
	if not _finite_basis(safe_basis):
		return local_angular_velocity
	var world_omega := AirRotationIntegrator.local_to_world_angular_velocity(safe_basis, local_angular_velocity)
	if not _finite_vector(world_omega):
		return local_angular_velocity
	var parallel := axis * world_omega.dot(axis)
	var perpendicular := world_omega - parallel
	var target_speed := minf(planar_speed / maxf(profile.crash_roll_body_radius, 0.05), maxf(profile.crash_roll_max_angular_speed, 0.0))
	var blended_world := perpendicular + parallel.lerp(axis * target_speed, coupling)
	if not _finite_vector(blended_world):
		return local_angular_velocity
	var local_omega := safe_basis.inverse() * blended_world
	if not _finite_vector(local_omega):
		return local_angular_velocity
	return local_omega

func integrate_grounded_crash_basis(
	current_basis: Basis,
	local_angular_velocity: Vector3,
	ground_normal: Vector3,
	travel: Vector3,
	align_rate: float,
	delta: float,
	profile: SkiPhysicsProfile
) -> Basis:
	var current := current_basis.orthonormalized()
	if not _finite_basis(current):
		return Basis.IDENTITY
	var dt := maxf(delta, 0.0)
	var tumbled := current
	if dt > 0.0 and _finite_vector(local_angular_velocity) and local_angular_velocity.length_squared() > 0.000001:
		tumbled = AirRotationIntegrator.integrate_basis(current, local_angular_velocity, dt)
		if not _finite_basis(tumbled):
			tumbled = current
	var aligned := tumbled
	var rate := align_rate if is_finite(align_rate) else 0.0
	if dt > 0.0 and rate > 0.0:
		var target := snow_align_target(tumbled, ground_normal, travel)
		var align_weight := 1.0 - exp(-rate * dt)
		var tumbled_quat := tumbled.get_rotation_quaternion()
		var target_quat := target.get_rotation_quaternion()
		if _finite_quat(tumbled_quat) and _finite_quat(target_quat) and align_weight > 0.0:
			aligned = Basis(tumbled_quat.slerp(target_quat, clampf(align_weight, 0.0, 1.0))).orthonormalized()
			if not _finite_basis(aligned):
				aligned = tumbled
	return _clamp_basis_step(current, aligned, dt, profile)

func snow_align_target(current_basis: Basis, ground_normal: Vector3, travel: Vector3) -> Basis:
	var current := current_basis.orthonormalized()
	if not _finite_basis(current):
		current = Basis.IDENTITY
	var normal := _safe_normal(ground_normal)
	if normal.length_squared() < NORMAL_EPSILON_SQ:
		return current
	var forward := travel if _finite_vector(travel) else Vector3.ZERO
	if forward.length_squared() < TRAVEL_EPSILON_SQ:
		forward = (-current.z).slide(normal)
	if forward.length_squared() < TRAVEL_EPSILON_SQ:
		forward = Vector3.FORWARD.slide(normal)
	if forward.length_squared() < TRAVEL_EPSILON_SQ:
		forward = Vector3.RIGHT.slide(normal)
	if forward.length_squared() < TRAVEL_EPSILON_SQ or absf(forward.normalized().dot(normal)) > 0.98:
		return current
	var target := Basis.looking_at(forward.normalized(), normal).orthonormalized()
	if not _finite_basis(target):
		return current
	return target

func grounded_rotation_step_limit(delta: float, profile: SkiPhysicsProfile) -> float:
	return deg_to_rad(maxf(profile.crash_ground_max_rotation_rate_degrees, 0.0)) * maxf(delta, 0.0)

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
		elif not grounded and elapsed >= profile.crash_max_duration:
			result.should_respawn = true
	else:
		result.stage = CrashContext.Stage.REST
		result.rest_elapsed = rest_elapsed + delta
		result.should_recover = result.rest_elapsed >= profile.crash_rest_hold_time
	return result

func _apply_ground_roll(result: BailMotionResult, normal: Vector3, body_basis: Basis, profile: SkiPhysicsProfile) -> void:
	var axis := surface_roll_axis(normal, result.planar_travel)
	result.roll_axis = axis
	result.roll_valid = axis.length_squared() >= AXIS_EPSILON_SQ
	result.generated_roll_speed = surface_roll_speed(result.planar_travel.length(), profile) if result.roll_valid else 0.0
	if not result.roll_valid or result.generated_roll_speed <= 0.0:
		return
	result.angular_velocity = couple_surface_roll(
		result.angular_velocity,
		normal,
		result.planar_travel,
		body_basis,
		profile
	)

func _clamp_basis_step(current: Basis, proposed: Basis, delta: float, profile: SkiPhysicsProfile) -> Basis:
	var max_step := grounded_rotation_step_limit(delta, profile)
	var current_quat := current.get_rotation_quaternion()
	var proposed_quat := proposed.get_rotation_quaternion()
	if not _finite_quat(current_quat) or not _finite_quat(proposed_quat):
		return current
	var angle := current_quat.angle_to(proposed_quat)
	if angle <= BASIS_ANGLE_EPSILON or max_step <= 0.0:
		return current if max_step <= 0.0 and angle > BASIS_ANGLE_EPSILON else proposed
	if angle <= max_step:
		return proposed
	return Basis(current_quat.slerp(proposed_quat, max_step / angle)).orthonormalized()

func _safe_normal(ground_normal: Vector3) -> Vector3:
	if not _finite_vector(ground_normal) or ground_normal.length_squared() < NORMAL_EPSILON_SQ:
		return Vector3.ZERO
	return ground_normal.normalized()

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _finite_basis(value: Basis) -> bool:
	return _finite_vector(value.x) and _finite_vector(value.y) and _finite_vector(value.z)

func _finite_quat(value: Quaternion) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)
