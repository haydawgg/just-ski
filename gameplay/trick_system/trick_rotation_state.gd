class_name TrickRotationState
extends RefCounted

var active := false
var kind := TrickCommand.Kind.NONE
var takeoff_reference_basis := Basis.IDENTITY
var primary_axis_local := Vector3.UP
var primary_axis_world := Vector3.UP
var axis_weights := Vector3.ZERO
var total_takeoff_impulse := Vector3.ZERO
var release_duration := 0.14
var release_elapsed := 0.0
var released_fraction := 0.0
var spin_progress_radians := 0.0
var flip_progress_radians := 0.0
var cork_progress_radians := 0.0
var reference_progress_radians := Vector3.ZERO
var orientation_delta := Quaternion.IDENTITY
# 0 = fully open, 0.5 = neutral, 1 = fully compact.
var compactness := 0.5
var inertia_scale := 1.0
var assist_angular_contribution := Vector3.ZERO
var assist_budget_remaining := 0.0
var air_control_armed := false

func begin(
	committed_kind: int,
	reference_basis: Basis,
	takeoff_impulse_local: Vector3,
	duration: float = 0.14,
	assist_budget: float = 0.32
) -> void:
	reset()
	active = true
	kind = committed_kind
	takeoff_reference_basis = reference_basis.orthonormalized()
	total_takeoff_impulse = takeoff_impulse_local
	release_duration = maxf(duration, 0.0)
	primary_axis_local = takeoff_impulse_local.normalized() if takeoff_impulse_local.length_squared() > 0.000001 else _fallback_axis(committed_kind)
	primary_axis_world = (takeoff_reference_basis * primary_axis_local).normalized()
	axis_weights = _normalized_weights(primary_axis_local)
	assist_budget_remaining = maxf(assist_budget, 0.0)

func reset() -> void:
	active = false
	kind = TrickCommand.Kind.NONE
	takeoff_reference_basis = Basis.IDENTITY
	primary_axis_local = Vector3.UP
	primary_axis_world = Vector3.UP
	axis_weights = Vector3.ZERO
	total_takeoff_impulse = Vector3.ZERO
	release_duration = 0.14
	release_elapsed = 0.0
	released_fraction = 0.0
	spin_progress_radians = 0.0
	flip_progress_radians = 0.0
	cork_progress_radians = 0.0
	reference_progress_radians = Vector3.ZERO
	orientation_delta = Quaternion.IDENTITY
	compactness = 0.5
	inertia_scale = 1.0
	assist_angular_contribution = Vector3.ZERO
	assist_budget_remaining = 0.0
	air_control_armed = false

func consume_takeoff_release(delta: float) -> Vector3:
	if not active or released_fraction >= 1.0:
		return Vector3.ZERO
	if release_duration <= 0.0001:
		var instant := total_takeoff_impulse * (1.0 - released_fraction)
		released_fraction = 1.0
		release_elapsed = release_duration
		return instant
	var previous_fraction := released_fraction
	release_elapsed = minf(release_elapsed + maxf(delta, 0.0), release_duration)
	var normalized_time := clampf(release_elapsed / release_duration, 0.0, 1.0)
	released_fraction = _smoothstep01(normalized_time)
	if release_elapsed >= release_duration:
		released_fraction = 1.0
	return total_takeoff_impulse * (released_fraction - previous_fraction)

func takeoff_release_active() -> bool:
	return active and released_fraction < 1.0

func record_takeoff_release(applied_impulse_local: Vector3, delta: float) -> void:
	if not active or released_fraction >= 1.0:
		return
	release_elapsed = minf(release_elapsed + maxf(delta, 0.0), release_duration)
	var total_length_squared := total_takeoff_impulse.length_squared()
	if total_length_squared <= 0.000001:
		released_fraction = 1.0
		return
	# Only the component along the committed takeoff budget advances release.
	# Continuation/check impulses are tracked separately by TrickCommand and must
	# not make the gameplay release clock finish early.
	var released_delta := applied_impulse_local.dot(total_takeoff_impulse) / total_length_squared
	released_fraction = clampf(released_fraction + maxf(released_delta, 0.0), 0.0, 1.0)
	if release_elapsed >= release_duration and released_fraction >= 0.999:
		released_fraction = 1.0

func integrate_world_angular_velocity(world_angular_velocity: Vector3, delta: float) -> void:
	if not active or delta <= 0.0:
		return
	var dt := maxf(delta, 0.0)
	var reference_rate := takeoff_reference_basis.transposed() * world_angular_velocity
	reference_progress_radians += reference_rate * dt
	spin_progress_radians = reference_progress_radians.y
	flip_progress_radians = reference_progress_radians.x
	cork_progress_radians = reference_progress_radians.dot(primary_axis_local)

func record_world_basis(world_basis: Basis) -> void:
	if not active:
		return
	var relative_basis := takeoff_reference_basis.transposed() * world_basis.orthonormalized()
	orientation_delta = relative_basis.get_rotation_quaternion().normalized()

func orientation_error_radians() -> float:
	return orientation_delta.get_angle() if active else 0.0

## Applies bounded continuous precision trim. This is the only airborne input
## that can add angular momentum; body compactness itself conserves momentum.
func consume_assist_acceleration(local_acceleration: Vector3, delta: float) -> Vector3:
	if not active or assist_budget_remaining <= 0.0001 or delta <= 0.0:
		return Vector3.ZERO
	var requested := local_acceleration * delta
	if requested.length_squared() <= 0.0000001:
		return Vector3.ZERO
	var applied := requested.limit_length(assist_budget_remaining)
	assist_budget_remaining = maxf(0.0, assist_budget_remaining - applied.length())
	assist_angular_contribution += applied
	return applied

func control_projection(stick: Vector2, center_deadzone: float = 0.28) -> float:
	if not active or primary_axis_local.length_squared() <= 0.0001:
		return 0.0
	if stick.length() <= center_deadzone:
		air_control_armed = true
		return 0.0
	if not air_control_armed:
		return 0.0
	var absolute := Vector3(absf(primary_axis_local.x), absf(primary_axis_local.y), absf(primary_axis_local.z))
	if absolute.x >= maxf(absolute.y, absolute.z):
		return clampf(-stick.y * signf(primary_axis_local.x), -1.0, 1.0)
	return clampf(stick.x * signf(primary_axis_local.y), -1.0, 1.0)

func apply_compactness(
	current_angular_velocity: Vector3,
	new_compactness: float,
	delta: float,
	open_inertia_scale: float = 1.18,
	compact_inertia_scale: float = 0.82,
	inertia_response_rate: float = 12.0
) -> Vector3:
	compactness = clampf(new_compactness, 0.0, 1.0)
	var target_inertia := maxf(lerpf(open_inertia_scale, compact_inertia_scale, compactness), 0.05)
	var response := 1.0 - exp(-maxf(inertia_response_rate, 0.0) * maxf(delta, 0.0))
	var previous_inertia := maxf(inertia_scale, 0.05)
	var next_inertia := lerpf(previous_inertia, target_inertia, response)
	if current_angular_velocity.length_squared() <= 0.000001:
		inertia_scale = next_inertia
		return Vector3.ZERO
	# Approximate angular-momentum conservation as body inertia changes. Because
	# the inertia response is time based, the same held body input converges to
	# the same result at different physics tick rates.
	var multiplier := previous_inertia / maxf(next_inertia, 0.05)
	inertia_scale = next_inertia
	return current_angular_velocity * multiplier

func primary_progress_radians() -> float:
	return reference_progress_radians.dot(primary_axis_local) if active else 0.0

func accumulated_rotation_vector() -> Vector3:
	return reference_progress_radians if active else Vector3.ZERO

func snapshot() -> Dictionary:
	return {
		"active": active,
		"kind": kind,
		"release_fraction": released_fraction,
		"release_elapsed": release_elapsed,
		"release_duration": release_duration,
		"total_takeoff_impulse": total_takeoff_impulse,
		"primary_axis_local": primary_axis_local,
		"primary_axis_world": primary_axis_world,
		"axis_weights": axis_weights,
		"spin_progress_radians": spin_progress_radians,
		"flip_progress_radians": flip_progress_radians,
		"cork_progress_radians": cork_progress_radians,
		"reference_progress_radians": reference_progress_radians,
		"orientation_delta": orientation_delta,
		"orientation_error_radians": orientation_error_radians(),
		"primary_progress_radians": primary_progress_radians(),
		"accumulated_rotation": accumulated_rotation_vector(),
		"compactness": compactness,
		"inertia_scale": inertia_scale,
		"assist_angular_contribution": assist_angular_contribution,
		"assist_budget_remaining": assist_budget_remaining,
		"air_control_armed": air_control_armed,
	}

func _fallback_axis(committed_kind: int) -> Vector3:
	match committed_kind:
		TrickCommand.Kind.SPIN_LEFT: return Vector3(0.0, -1.0, 0.0)
		TrickCommand.Kind.SPIN_RIGHT: return Vector3(0.0, 1.0, 0.0)
		TrickCommand.Kind.FRONTFLIP: return Vector3(1.0, 0.0, 0.0)
		TrickCommand.Kind.BACKFLIP: return Vector3(-1.0, 0.0, 0.0)
		TrickCommand.Kind.CORK_LEFT: return Vector3(0.0, -1.0, -1.0).normalized()
		TrickCommand.Kind.CORK_RIGHT: return Vector3(0.0, 1.0, 1.0).normalized()
	return Vector3.UP

func _normalized_weights(axis: Vector3) -> Vector3:
	var absolute := Vector3(absf(axis.x), absf(axis.y), absf(axis.z))
	var total := absolute.x + absolute.y + absolute.z
	return absolute / total if total > 0.0001 else Vector3.ZERO

func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
