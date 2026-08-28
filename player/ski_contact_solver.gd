class_name SkiContactSolver
extends RefCounted

const TERRAIN_MASK := 1
const HEIGHT_DISAGREEMENT_SOFT := 0.12
const HEIGHT_DISAGREEMENT_HARD := 0.48
const NORMAL_DISAGREEMENT_SOFT := 0.08
const NORMAL_DISAGREEMENT_HARD := 0.5
const DISTANCE_DISCONTINUITY_SOFT := 0.12
const DISTANCE_DISCONTINUITY_HARD := 0.5
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
var surface_kind := 0
var grounded_band := 0.5
var average_hit_position := Vector3.ZERO
var left_distance := 2.0
var right_distance := 2.0
var left_normal := Vector3.UP
var right_normal := Vector3.UP
var left_hit_position := Vector3.ZERO
var right_hit_position := Vector3.ZERO
var left_grounded := false
var right_grounded := false
var left_contact_confidence := 0.0
var right_contact_confidence := 0.0
var left_front_valid := false
var left_rear_valid := false
var right_front_valid := false
var right_rear_valid := false
var left_front_distance := 2.0
var left_rear_distance := 2.0
var right_front_distance := 2.0
var right_rear_distance := 2.0
var left_front_position := Vector3.ZERO
var left_rear_position := Vector3.ZERO
var right_front_position := Vector3.ZERO
var right_rear_position := Vector3.ZERO
var left_front_normal := Vector3.UP
var left_rear_normal := Vector3.UP
var right_front_normal := Vector3.UP
var right_rear_normal := Vector3.UP
var _left_had_contact := false
var _right_had_contact := false

func sample(body: CharacterBody3D, distance: float = 1.45, band: float = 0.5) -> void:
	grounded_band = maxf(band, 0.05)
	var previous_left_distance := left_distance
	var previous_right_distance := right_distance
	var previous_left_normal := left_normal
	var previous_right_normal := right_normal
	var space := body.get_world_3d().direct_space_state
	var up := last_normal.normalized() if last_normal.length_squared() > 0.01 else Vector3.UP
	var down := -up
	var normal_sum := Vector3.ZERO
	var distance_sum := 0.0
	var front_distance := 0.0
	var rear_distance := 0.0
	var front_hits := 0
	var rear_hits := 0
	var left_distance_sum := 0.0
	var right_distance_sum := 0.0
	var left_normal_sum := Vector3.ZERO
	var right_normal_sum := Vector3.ZERO
	var left_position_sum := Vector3.ZERO
	var right_position_sum := Vector3.ZERO
	var left_hits := 0
	var right_hits := 0
	var surface_counts := [0, 0, 0]
	hit_points.clear()
	tip_load = 0.0
	left_distance = distance
	right_distance = distance
	left_normal = average_normal
	right_normal = average_normal
	left_hit_position = Vector3.ZERO
	right_hit_position = Vector3.ZERO
	left_grounded = false
	right_grounded = false
	left_contact_confidence = 0.0
	right_contact_confidence = 0.0
	left_front_valid = false
	left_rear_valid = false
	right_front_valid = false
	right_rear_valid = false
	left_front_distance = distance
	left_rear_distance = distance
	right_front_distance = distance
	right_rear_distance = distance
	left_front_position = Vector3.ZERO
	left_rear_position = Vector3.ZERO
	right_front_position = Vector3.ZERO
	right_rear_position = Vector3.ZERO
	left_front_normal = average_normal
	left_rear_normal = average_normal
	right_front_normal = average_normal
	right_rear_normal = average_normal
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
			var hit_position := hit.position as Vector3
			var hit_normal := hit.normal as Vector3
			distance_sum += hit_distance
			hit_points.append(hit_position)
			if local_offset.x < 0.0:
				left_distance_sum += hit_distance
				left_normal_sum += hit_normal
				left_position_sum += hit_position
				left_hits += 1
				if local_offset.z < 0.0:
					left_front_valid = true
					left_front_distance = hit_distance
					left_front_position = hit_position
					left_front_normal = hit_normal
				else:
					left_rear_valid = true
					left_rear_distance = hit_distance
					left_rear_position = hit_position
					left_rear_normal = hit_normal
			else:
				right_distance_sum += hit_distance
				right_normal_sum += hit_normal
				right_position_sum += hit_position
				right_hits += 1
				if local_offset.z < 0.0:
					right_front_valid = true
					right_front_distance = hit_distance
					right_front_position = hit_position
					right_front_normal = hit_normal
				else:
					right_rear_valid = true
					right_rear_distance = hit_distance
					right_rear_position = hit_position
					right_rear_normal = hit_normal
			var collider := hit.get("collider") as Object
			if collider != null and collider.has_meta("ski_surface_kind"):
				var hit_surface := clampi(int(collider.get_meta("ski_surface_kind")), 0, surface_counts.size() - 1)
				surface_counts[hit_surface] += 1
			if local_offset.z < 0.0:
				front_distance += hit_distance
				front_hits += 1
			else:
				rear_distance += hit_distance
				rear_hits += 1
	if hit_points.size() > 0:
		average_distance = distance_sum / float(hit_points.size())
		var hit_sum := Vector3.ZERO
		for point: Vector3 in hit_points:
			hit_sum += point
		average_hit_position = hit_sum / float(hit_points.size())
	if left_hits > 0:
		left_distance = left_distance_sum / float(left_hits)
		left_normal = left_normal_sum.normalized()
		left_hit_position = left_position_sum / float(left_hits)
		left_grounded = left_distance <= grounded_band
	if right_hits > 0:
		right_distance = right_distance_sum / float(right_hits)
		right_normal = right_normal_sum.normalized()
		right_hit_position = right_position_sum / float(right_hits)
		right_grounded = right_distance <= grounded_band
	confidence = float(hit_points.size()) / float(PROBE_OFFSETS.size())
	grounded = confidence >= 0.5 and average_distance <= grounded_band
	left_contact_confidence = _side_contact_confidence(
		left_front_valid, left_rear_valid,
		left_front_distance, left_rear_distance,
		left_front_normal, left_rear_normal,
		previous_left_distance, previous_left_normal,
		_left_had_contact, left_grounded, grounded
	)
	right_contact_confidence = _side_contact_confidence(
		right_front_valid, right_rear_valid,
		right_front_distance, right_rear_distance,
		right_front_normal, right_rear_normal,
		previous_right_distance, previous_right_normal,
		_right_had_contact, right_grounded, grounded
	)
	_left_had_contact = left_front_valid or left_rear_valid
	_right_had_contact = right_front_valid or right_rear_valid
	if grounded:
		average_normal = normal_sum.normalized()
		last_normal = average_normal
		var most_hits := 0
		for kind: int in range(surface_counts.size()):
			if surface_counts[kind] > most_hits:
				most_hits = surface_counts[kind]
				surface_kind = kind
		if front_hits > 0 and rear_hits > 0:
			tip_load = (rear_distance / float(rear_hits)) - (front_distance / float(front_hits))

func _side_contact_confidence(
	front_valid: bool,
	rear_valid: bool,
	front_sample_distance: float,
	rear_sample_distance: float,
	front_sample_normal: Vector3,
	rear_sample_normal: Vector3,
	previous_distance: float,
	previous_normal: Vector3,
	had_previous_contact: bool,
	side_is_grounded: bool,
	authoritative_grounded: bool
) -> float:
	var hit_count := int(front_valid) + int(rear_valid)
	if hit_count == 0:
		return 0.0
	var coverage := 1.0 if hit_count == 2 else 0.52
	var side_distance := 0.0
	if front_valid: side_distance += front_sample_distance
	if rear_valid: side_distance += rear_sample_distance
	side_distance /= float(hit_count)
	var distance_quality := 1.0 - smoothstep(grounded_band * 0.72, grounded_band * 1.05, side_distance)
	var height_quality := 0.68
	var normal_quality := 0.72
	if front_valid and rear_valid:
		height_quality = 1.0 - smoothstep(
			HEIGHT_DISAGREEMENT_SOFT,
			HEIGHT_DISAGREEMENT_HARD,
			absf(front_sample_distance - rear_sample_distance)
		)
		var normal_disagreement := 1.0 - clampf(front_sample_normal.normalized().dot(rear_sample_normal.normalized()), -1.0, 1.0)
		normal_quality = 1.0 - smoothstep(NORMAL_DISAGREEMENT_SOFT, NORMAL_DISAGREEMENT_HARD, normal_disagreement)
	var continuity_quality := 1.0
	var side_normal := (front_sample_normal if front_valid else Vector3.ZERO) + (rear_sample_normal if rear_valid else Vector3.ZERO)
	if side_normal.length_squared() > 0.001:
		side_normal = side_normal.normalized()
	if had_previous_contact:
		continuity_quality *= 1.0 - smoothstep(
			DISTANCE_DISCONTINUITY_SOFT,
			DISTANCE_DISCONTINUITY_HARD,
			absf(side_distance - previous_distance)
		)
		if side_normal.length_squared() > 0.001 and previous_normal.length_squared() > 0.001:
			var normal_jump := 1.0 - clampf(side_normal.dot(previous_normal.normalized()), -1.0, 1.0)
			continuity_quality *= 1.0 - smoothstep(NORMAL_DISAGREEMENT_SOFT, NORMAL_DISAGREEMENT_HARD, normal_jump)
	var grounded_quality := 1.0 if authoritative_grounded and side_is_grounded else (0.3 if side_is_grounded else 0.0)
	return clampf(coverage * distance_quality * height_quality * normal_quality * continuity_quality * grounded_quality, 0.0, 1.0)

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
