class_name CameraCollisionSolver
extends RefCounted

## Owns the camera's collision query objects and their narrow query interface.
## The camera coordinator still owns policy (which candidate to choose and how
## quickly to apply it); this module owns the physics-query implementation.

var world: World3D
var target: CharacterBody3D
var collision_mask := 1 | 4
var camera_collision_radius := 0.22
var collision_clearance := 0.35

var shape_queries := 0
var ray_queries := 0

var _camera_sphere: SphereShape3D
var _camera_sweep_query: PhysicsShapeQueryParameters3D
var _camera_destination_query: PhysicsShapeQueryParameters3D
var _camera_foreground_query: PhysicsRayQueryParameters3D
var _camera_clearance_query: PhysicsRayQueryParameters3D

func configure(
	value_world: World3D,
	value_target: CharacterBody3D,
	value_collision_mask: int,
	value_radius: float,
	value_clearance: float
) -> void:
	world = value_world
	target = value_target
	collision_mask = value_collision_mask
	camera_collision_radius = value_radius
	collision_clearance = value_clearance
	if _camera_sphere == null:
		_camera_sphere = SphereShape3D.new()
		_camera_sweep_query = PhysicsShapeQueryParameters3D.new()
		_camera_destination_query = PhysicsShapeQueryParameters3D.new()
		_camera_foreground_query = PhysicsRayQueryParameters3D.new()
		_camera_clearance_query = PhysicsRayQueryParameters3D.new()
	_camera_sphere.radius = maxf(camera_collision_radius, 0.05)
	_camera_sweep_query.shape = _camera_sphere
	_camera_sweep_query.collision_mask = collision_mask
	_camera_sweep_query.margin = collision_clearance
	_camera_destination_query.shape = _camera_sphere
	_camera_destination_query.collision_mask = collision_mask
	_camera_destination_query.margin = collision_clearance
	_camera_foreground_query.collision_mask = collision_mask
	_camera_clearance_query.collision_mask = collision_mask
	_refresh_excludes()

func set_target(value_target: CharacterBody3D) -> void:
	target = value_target
	_refresh_excludes()

func reset_query_counts() -> void:
	shape_queries = 0
	ray_queries = 0

func _refresh_excludes() -> void:
	var excludes: Array[RID] = []
	if target != null:
		excludes.append(target.get_rid())
	if _camera_sweep_query != null:
		_camera_sweep_query.exclude = excludes
	if _camera_destination_query != null:
		_camera_destination_query.exclude = excludes
	if _camera_foreground_query != null:
		_camera_foreground_query.exclude = excludes
	if _camera_clearance_query != null:
		_camera_clearance_query.exclude = excludes

func destination_is_clear(position: Vector3) -> bool:
	if world == null:
		return true
	_camera_sphere.radius = maxf(camera_collision_radius, 0.05)
	_camera_destination_query.transform = Transform3D(Basis.IDENTITY, position)
	shape_queries += 1
	return world.direct_space_state.intersect_shape(_camera_destination_query, 1).is_empty()

func foreground_occluded(camera_position: Vector3, world_position: Vector3, clearance: float) -> bool:
	if world == null or target == null:
		return false
	var distance := camera_position.distance_to(world_position)
	if distance <= 0.1 or not camera_position.is_finite() or not world_position.is_finite():
		return false
	_camera_foreground_query.from = camera_position
	_camera_foreground_query.to = world_position
	ray_queries += 1
	var hit := world.direct_space_state.intersect_ray(_camera_foreground_query)
	if hit.is_empty() or not (hit.position is Vector3):
		return false
	return (hit.position as Vector3).distance_to(camera_position) < distance - maxf(clearance, 0.1)

func trace(from: Vector3, desired: Vector3) -> Dictionary:
	if world == null:
		return {"hit": false, "position": desired}
	if not from.is_finite() or not desired.is_finite():
		return {"hit": true, "position": from}
	var space := world.direct_space_state
	if space == null:
		return {"hit": false, "position": desired}
	_camera_sphere.radius = maxf(camera_collision_radius, 0.05)
	_camera_sweep_query.transform = Transform3D(Basis.IDENTITY, from)
	_camera_sweep_query.motion = desired - from
	shape_queries += 2
	var cast := space.cast_motion(_camera_sweep_query)
	var safe_fraction := 1.0
	if cast.size() >= 2:
		safe_fraction = clampf(float(cast[0]), 0.0, 1.0)
	_camera_destination_query.transform = Transform3D(Basis.IDENTITY, desired)
	var destination_hits := space.intersect_shape(_camera_destination_query, 1)
	var hit := safe_fraction < 0.999 or not destination_hits.is_empty()
	if not hit:
		return {"hit": false, "position": desired}
	return {"hit": true, "position": from.lerp(desired, safe_fraction)}

func measure_clearance(position: Vector3, basis: Basis, maximum_distance: float) -> float:
	if world == null or not position.is_finite():
		return maximum_distance
	var space := world.direct_space_state
	if space == null:
		return maximum_distance
	var axes: Array[Vector3] = [basis.x, -basis.x, basis.y, -basis.y, basis.z, -basis.z]
	var nearest := maximum_distance + collision_clearance
	for axis: Vector3 in axes:
		if axis.length_squared() < 0.001 or not axis.is_finite():
			continue
		var direction := axis.normalized()
		_camera_clearance_query.from = position
		_camera_clearance_query.to = position + direction * (maximum_distance + collision_clearance)
		ray_queries += 1
		var hit := space.intersect_ray(_camera_clearance_query)
		if not hit.is_empty() and hit.position is Vector3:
			nearest = minf(nearest, position.distance_to(hit.position as Vector3))
	return maxf(0.0, nearest - camera_collision_radius - collision_clearance)
