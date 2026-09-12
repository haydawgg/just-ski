extends Node3D

## CAM-03 regression: the camera collision sweep must never commit a colliding
## destination as its safe position.
##
## When cast_motion reports a safe fraction at/near 1.0 but the destination
## sphere overlaps geometry (e.g. the desired pose sits inside the clearance
## margin of a crest), trace() must back off along the segment to a point that
## is actually clear instead of returning the colliding desired point.

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await _run_destination_overlap_reproduction()
	await _run_deep_penetration_sanity()
	await _run_clear_path_sanity()
	if failures.is_empty():
		print("CAMERA_DESTINATION_PASS: overlap-only sweep backs off to a clear point; deep and clear paths unchanged")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_DESTINATION_FAIL: " + failure)
	get_tree().quit(1)

func _make_solver() -> CameraCollisionSolver:
	var solver := CameraCollisionSolver.new()
	solver.configure(get_world_3d(), null, 1 | 4, 0.22, 0.35)
	return solver

func _make_blocker() -> StaticBody3D:
	var box := StaticBody3D.new()
	box.collision_layer = 4
	box.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box_shape
	box.add_child(shape)
	box.position = Vector3(0.0, 1.0, 0.0)
	add_child(box)
	return box

func _run_destination_overlap_reproduction() -> void:
	var blocker := _make_blocker()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var solver := _make_solver()
	var from := Vector3(0.0, 1.0, 6.0)
	# Box face sits at z = 1.0; the sphere surface at z = 1.3 is only 0.08 m
	# off the face, well inside the 0.35 m clearance margin, so the
	# destination overlaps while the cast along +Z can report ~1.0.
	var desired := Vector3(0.0, 1.0, 1.3)
	if solver.destination_is_clear(desired):
		failures.append("Overlap fixture is not overlapping: destination %s reported clear" % desired)
		_release(blocker)
		return
	var result: Dictionary = solver.trace(from, desired)
	var position := result.get("position", desired) as Vector3
	if not bool(result.get("hit", false)):
		failures.append("Overlap-only trace reported no hit for colliding destination %s" % desired)
	if not solver.destination_is_clear(position):
		failures.append("Overlap-only trace committed colliding position %s for destination %s" % [position, desired])
	if position.distance_to(desired) < 0.01:
		failures.append("Overlap-only trace returned the colliding desired point %s unchanged" % desired)
	_release(blocker)

func _run_deep_penetration_sanity() -> void:
	var blocker := _make_blocker()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var solver := _make_solver()
	var from := Vector3(0.0, 1.0, 6.0)
	var desired := Vector3(0.0, 1.0, 0.0)
	var result: Dictionary = solver.trace(from, desired)
	var position := result.get("position", desired) as Vector3
	if not bool(result.get("hit", false)):
		failures.append("Deep sweep reported no hit for interior destination")
	if not solver.destination_is_clear(position):
		failures.append("Deep sweep committed colliding position %s" % position)
	if position.distance_to(from) < 0.01 and not solver.destination_is_clear(from):
		failures.append("Deep sweep made no progress from a clear start")
	_release(blocker)

func _run_clear_path_sanity() -> void:
	var blocker := _make_blocker()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var solver := _make_solver()
	var from := Vector3(0.0, 1.0, 6.0)
	var desired := Vector3(0.0, 1.0, 3.0)
	var result: Dictionary = solver.trace(from, desired)
	var position := result.get("position", from) as Vector3
	if bool(result.get("hit", false)):
		failures.append("Clear path reported a hit")
	if position.distance_to(desired) > 0.001:
		failures.append("Clear path moved the safe position %s away from desired %s" % [position, desired])
	_release(blocker)

func _release(blocker: StaticBody3D) -> void:
	remove_child(blocker)
	blocker.free()
