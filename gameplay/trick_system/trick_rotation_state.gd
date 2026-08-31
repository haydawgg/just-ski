class_name TrickRotationState
extends RefCounted

var active := false
var kind := TrickCommand.Kind.NONE
var takeoff_reference_basis := Basis.IDENTITY
var primary_axis_world := Vector3.UP
var total_takeoff_impulse := Vector3.ZERO
var release_duration := 0.14
var release_elapsed := 0.0
var released_fraction := 0.0
var spin_progress_radians := 0.0
var flip_progress_radians := 0.0
var cork_progress_radians := 0.0
# 0 = fully open, 0.5 = neutral, 1 = fully compact.
var compactness := 0.5
var inertia_scale := 1.0
var assist_angular_contribution := Vector3.ZERO

func begin(
	committed_kind: int,
	reference_basis: Basis,
	takeoff_impulse_local: Vector3,
	duration: float = 0.14
) -> void:
	reset()
	active = true
	kind = committed_kind
	takeoff_reference_basis = reference_basis.orthonormalized()
	total_takeoff_impulse = takeoff_impulse_local
	release_duration = maxf(duration, 0.0)
	primary_axis_world = _resolve_primary_axis_world(committed_kind, takeoff_impulse_local)

func reset() -> void:
	active = false
	kind = TrickCommand.Kind.NONE
	takeoff_reference_basis = Basis.IDENTITY
	primary_axis_world = Vector3.UP
	total_takeoff_impulse = Vector3.ZERO
	release_duration = 0.14
	release_elapsed = 0.0
	released_fraction = 0.0
	spin_progress_radians = 0.0
	flip_progress_radians = 0.0
	cork_progress_radians = 0.0
	compactness = 0.5
	inertia_scale = 1.0
	assist_angular_contribution = Vector3.ZERO

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

func integrate_world_angular_velocity(world_angular_velocity: Vector3, delta: float) -> void:
	if not active or delta <= 0.0:
		return
	var dt := maxf(delta, 0.0)
	spin_progress_radians += world_angular_velocity.dot(takeoff_reference_basis.y) * dt
	flip_progress_radians += world_angular_velocity.dot(takeoff_reference_basis.x) * dt
	cork_progress_radians += world_angular_velocity.dot(primary_axis_world) * dt

func apply_compactness(
	current_angular_velocity: Vector3,
	new_compactness: float,
	open_inertia_scale: float = 1.18,
	compact_inertia_scale: float = 0.82,
	maximum_speed_multiplier_per_step: float = 1.15
) -> Vector3:
	compactness = clampf(new_compactness, 0.0, 1.0)
	var target_inertia := lerpf(open_inertia_scale, compact_inertia_scale, compactness)
	target_inertia = maxf(target_inertia, 0.05)
	if current_angular_velocity.length_squared() <= 0.000001:
		inertia_scale = target_inertia
		return Vector3.ZERO
	var maximum_multiplier := maxf(maximum_speed_multiplier_per_step, 1.0)
	var desired_multiplier := inertia_scale / target_inertia
	var applied_multiplier := clampf(desired_multiplier, 1.0 / maximum_multiplier, maximum_multiplier)
	inertia_scale = inertia_scale / applied_multiplier
	return current_angular_velocity * applied_multiplier

func primary_progress_radians() -> float:
	match kind:
		TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT:
			return spin_progress_radians
		TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP:
			return flip_progress_radians
		TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT:
			return cork_progress_radians
	return 0.0

func snapshot() -> Dictionary:
	return {
		"active": active,
		"kind": kind,
		"release_fraction": released_fraction,
		"release_elapsed": release_elapsed,
		"release_duration": release_duration,
		"total_takeoff_impulse": total_takeoff_impulse,
		"primary_axis_world": primary_axis_world,
		"spin_progress_radians": spin_progress_radians,
		"flip_progress_radians": flip_progress_radians,
		"cork_progress_radians": cork_progress_radians,
		"primary_progress_radians": primary_progress_radians(),
		"compactness": compactness,
		"inertia_scale": inertia_scale,
		"assist_angular_contribution": assist_angular_contribution,
	}

func _resolve_primary_axis_world(committed_kind: int, impulse_local: Vector3) -> Vector3:
	match committed_kind:
		TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT:
			return takeoff_reference_basis.y
		TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP:
			return takeoff_reference_basis.x
		TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT:
			var world_impulse := takeoff_reference_basis * impulse_local
			if world_impulse.length_squared() > 0.000001:
				return world_impulse.normalized()
	return takeoff_reference_basis.y

func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
