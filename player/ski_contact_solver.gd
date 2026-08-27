class_name SkiContactSolver
extends RefCounted

const TERRAIN_MASK := 1
const PROBE_OFFSETS := [
	Vector3(-0.34, 0.0, -0.72),
	Vector3(-0.34, 0.0, 0.72),
	Vector3(0.34, 0.0, -0.72),
	Vector3(0.34, 0.0, 0.72),
]

var grounded := false
var average_normal := Vector3.UP
var average_distance := 2.0
var confidence := 0.0
var hit_points: Array[Vector3] = []
var last_normal := Vector3.UP
var tip_load := 0.0

func sample(body: CharacterBody3D, distance: float = 1.45) -> void:
	var space := body.get_world_3d().direct_space_state
	var up := last_normal.normalized() if last_normal.length_squared() > 0.01 else Vector3.UP
	var down := -up
	var normal_sum := Vector3.ZERO
	var distance_sum := 0.0
	var front_distance := 0.0
	var rear_distance := 0.0
	var front_hits := 0
	var rear_hits := 0
	hit_points.clear()
	tip_load = 0.0
	for local_offset: Vector3 in PROBE_OFFSETS:
		var planar_offset := body.global_basis * Vector3(local_offset.x, 0.0, local_offset.z)
		var origin := body.global_position + planar_offset - down * 0.35
		var target := origin + down * distance
		var query := PhysicsRayQueryParameters3D.create(origin, target, TERRAIN_MASK)
		query.exclude = [body.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			normal_sum += hit.normal as Vector3
			var hit_distance := origin.distance_to(hit.position as Vector3)
			distance_sum += hit_distance
			hit_points.append(hit.position as Vector3)
			if local_offset.z < 0.0:
				front_distance += hit_distance
				front_hits += 1
			else:
				rear_distance += hit_distance
				rear_hits += 1
	confidence = float(hit_points.size()) / float(PROBE_OFFSETS.size())
	grounded = confidence >= 0.5
	if grounded:
		average_normal = normal_sum.normalized()
		average_distance = distance_sum / float(hit_points.size())
		last_normal = average_normal
		if front_hits > 0 and rear_hits > 0:
			tip_load = (rear_distance / float(rear_hits)) - (front_distance / float(front_hits))

func merge_capsule_floor(on_floor: bool, floor_normal: Vector3) -> void:
	if grounded:
		return
	if not on_floor or floor_normal.length_squared() < 0.01:
		return
	if floor_normal.dot(Vector3.UP) < 0.35:
		return
	grounded = true
	average_normal = floor_normal.normalized()
	last_normal = average_normal
	confidence = maxf(confidence, 0.5)

func downhill(gravity_direction: Vector3 = Vector3.DOWN) -> Vector3:
	var tangent := gravity_direction.slide(average_normal)
	return tangent.normalized() if tangent.length_squared() > 0.0001 else Vector3.ZERO
