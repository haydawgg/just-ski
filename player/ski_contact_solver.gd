class_name SkiContactSolver
extends RefCounted

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

func sample(body: CharacterBody3D, distance: float = 1.45) -> void:
	var space := body.get_world_3d().direct_space_state
	var normal_sum := Vector3.ZERO
	var distance_sum := 0.0
	hit_points.clear()
	for local_offset: Vector3 in PROBE_OFFSETS:
		var origin := body.global_transform * local_offset + Vector3.UP * 0.35
		var target := origin - body.global_basis.y * distance
		var query := PhysicsRayQueryParameters3D.create(origin, target, 0b101)
		query.exclude = [body.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			normal_sum += hit.normal as Vector3
			distance_sum += origin.distance_to(hit.position as Vector3)
			hit_points.append(hit.position as Vector3)
	confidence = float(hit_points.size()) / float(PROBE_OFFSETS.size())
	grounded = confidence >= 0.5
	if grounded:
		average_normal = normal_sum.normalized()
		average_distance = distance_sum / float(hit_points.size())

func downhill(gravity_direction: Vector3 = Vector3.DOWN) -> Vector3:
	var tangent := gravity_direction.slide(average_normal)
	return tangent.normalized() if tangent.length_squared() > 0.0001 else Vector3.ZERO
