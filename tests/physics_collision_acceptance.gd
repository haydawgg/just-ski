extends Node

const ParkLayout := preload("res://world/park_features/park_layout.gd")

@onready var resort: Node = $Resort
var skier: SkierController
var jump: Node3D
var frame := 0
var failures: Array[String] = []
var grounded_frames := 0
var air_frames := 0
var kicker_seen := false
var kicker_speed := 0.0
var grind_speed := 0.0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	jump = resort.get_node("SmallTable") as Node3D
	_test_small_table_geometry.call_deferred()
	if jump == null:
		failures.append("Named SmallTable jump was not spawned")
	_test_tree_block.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 120:
		_place_on_open_slope()
	if frame >= 180 and frame <= 360:
		if skier.state == SkierController.State.GROUND:
			grounded_frames += 1
		elif skier.state == SkierController.State.AIR:
			air_frames += 1
	if frame == 360:
		var total := grounded_frames + air_frames
		if total == 0 or float(grounded_frames) / float(total) < 0.7:
			failures.append("Main-face contact was not stably grounded")
		_place_on_kicker_line()
	elif frame > 360 and frame < 520:
		if jump != null:
			var lip_z := float(jump.get_meta("lip_z"))
			if not kicker_seen and skier.global_position.z <= lip_z + 6.0 and skier.global_position.z >= lip_z - 8.0:
				kicker_seen = true
				kicker_speed = skier.velocity.length()
				if skier.state == SkierController.State.BAIL:
					failures.append("Kicker ride entered Bail")
				if kicker_speed < 2.5:
					failures.append("Kicker ride collapsed speed")
	elif frame == 520:
		if not kicker_seen:
			failures.append("Skier never reached the first kicker")
		_place_on_rail_approach()
	elif frame == 590:
		if skier.state != SkierController.State.GRIND:
			failures.append("Rail approach did not capture grind")
		else:
			grind_speed = skier.rail_speed
			if grind_speed < 3.0:
				failures.append("Rail capture collapsed speed")
			if skier.rail_entry_severity < 0.0 or skier.rail_entry_severity > 1.0:
				failures.append("Rail entry severity out of range")
			var rail_debug := skier.animation_controller.debug_snapshot()
			if float(rail_debug.get("rail_influence", 0.0)) < 0.2:
				failures.append("Rail animation influence did not rise after real capture")
		_finish()

func _place_on_open_slope() -> void:
	# Isolate contact stability from the summit rollers, which intentionally unweight the skis.
	skier.global_position = ParkLayout.snow_at(25.0, 130.0) + ParkLayout.snow_normal() * 1.15
	skier.velocity = ParkLayout.downhill() * 9.0
	skier.global_basis = ParkLayout.downhill_basis()
	skier.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	skier.state = SkierController.State.AIR
	skier.air_time = 0.2
	skier.contact.grounded = false
	skier.contact.last_normal = ParkLayout.snow_normal()

func _place_on_kicker_line() -> void:
	if jump == null:
		return
	var lip_z := float(jump.get_meta("lip_z"))
	skier.global_position = ParkLayout.snow_at(-12.0, lip_z + 8.0) + ParkLayout.snow_normal() * 1.5
	skier.velocity = ParkLayout.downhill() * 12.0
	skier.global_basis = ParkLayout.downhill_basis()
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state = SkierController.State.AIR
	skier.air_time = 0.2

func _place_on_rail_approach() -> void:
	var rail := resort.get_node("DownRail") as GrindRail3D
	var offset := rail.path_length * 0.25
	var tangent := rail.tangent_at(offset)
	skier.global_position = rail.sample_world(offset) + Vector3.UP * 0.55
	skier.velocity = tangent * 10.0
	skier.global_basis = Basis.looking_at(tangent, Vector3.UP)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state = SkierController.State.AIR
	skier.air_time = 0.2
	skier.active_rail = null
	skier.contact.grounded = false
	skier.contact.last_normal = Vector3.UP

func _test_tree_block() -> void:
	var trees := get_tree().get_nodes_in_group("park_trees")
	if trees.is_empty():
		failures.append("Park trees were not spawned as obstacles")
		return
	var tree := trees[0] as Node3D
	var origin := tree.global_position + Vector3(2.0, 1.7, 0.0)
	var target := tree.global_position + Vector3(0.0, 1.7, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, target, 4)
	var hit := skier.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		failures.append("Tree trunk was not solid")
	elif not (hit.get("collider") is CollisionObject3D) or (int((hit.get("collider") as CollisionObject3D).collision_layer) & 4) == 0:
		failures.append("Tree trunk collision was not authored on the Features layer")

func _test_small_table_geometry() -> void:
	if jump == null:
		return
	var table := jump.get_node_or_null("Table") as StaticBody3D
	if table == null:
		failures.append("SmallTable has no authored Table collision body")
		return
	var shape_node: CollisionShape3D
	var mesh_instance: MeshInstance3D
	for child: Node in table.get_children():
		if child is CollisionShape3D:
			shape_node = child as CollisionShape3D
		elif child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
	if shape_node == null or not shape_node.shape is ConcavePolygonShape3D:
		failures.append("SmallTable Table collision is not the sampled knuckle surface")
		return
	if mesh_instance == null or mesh_instance.mesh == null:
		failures.append("SmallTable Table has no visible mesh to compare against collision")
		return
	var concave := shape_node.shape as ConcavePolygonShape3D
	var collision_aabb := _points_aabb(concave.data)
	var mesh_aabb := mesh_instance.mesh.get_aabb()
	var render_arrays := (mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
	var render_vertices := render_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var missing_render_vertices := _count_vertices_missing_from_shape(render_vertices, concave.data)
	if missing_render_vertices > 0:
		failures.append("SmallTable Table collision does not contain %d visible-surface vertices" % missing_render_vertices)
	if collision_aabb.position.y > mesh_aabb.position.y + 0.05 or collision_aabb.end.y < mesh_aabb.end.y - 0.05:
		failures.append("SmallTable Table collision no longer covers the visible surface height")
	if int(table.get_meta("profile_rows", 0)) < 8 or int(table.get_meta("profile_columns", 0)) < 7:
		failures.append("SmallTable Table does not have enough profile samples for a rounded knuckle and shoulders")
	if mesh_instance.mesh.get_faces().size() < 120:
		failures.append("SmallTable Table mesh is still too coarse to read as a sculpted snow form")
	# Direct overhead approach must hit the visible tabletop body.
	var center := table.to_global(mesh_aabb.get_center())
	var direct := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 4.0, center - Vector3.UP * 4.0, 1)
	direct.exclude = [skier.get_rid()]
	var direct_hit := skier.get_world_3d().direct_space_state.intersect_ray(direct)
	if direct_hit.is_empty() or direct_hit.get("collider") != table:
		failures.append("Direct SmallTable approach did not hit the authored Table collider")
	# A lateral skim across the rolled shoulder must meet this profile rather
	# than an adjacent lip body or an oversized vertical slab.
	var surface_point: Vector3 = direct_hit.get("position", center)
	var glancing_from := surface_point + Vector3.RIGHT * 7.0 + ParkLayout.snow_normal() * 0.2
	var glancing_to := surface_point - ParkLayout.snow_normal() * 0.2
	var glancing := PhysicsRayQueryParameters3D.create(glancing_from, glancing_to, 1)
	glancing.exclude = [skier.get_rid()]
	var glancing_hit := skier.get_world_3d().direct_space_state.intersect_ray(glancing)
	if glancing_hit.is_empty() or glancing_hit.get("collider") != table:
		failures.append("Glancing SmallTable approach did not meet the authored side collision")
	print(
		"SMALLTABLE_PROFILE rows=", table.get_meta("profile_rows", 0),
		" columns=", table.get_meta("profile_columns", 0),
		" collision_aabb=", collision_aabb,
		" mesh_aabb=", mesh_aabb,
		" direct_collider=", direct_hit.get("collider", null),
		" glancing_collider=", glancing_hit.get("collider", null),
		" direct_normal=", direct_hit.get("normal", Vector3.ZERO),
		" glancing_normal=", glancing_hit.get("normal", Vector3.ZERO)
	)

func _points_aabb(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var result := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		result = result.expand(point)
	return result

func _count_vertices_missing_from_shape(vertices: PackedVector3Array, shape_data: PackedVector3Array) -> int:
	var missing := 0
	for vertex: Vector3 in vertices:
		var found := false
		for shape_vertex: Vector3 in shape_data:
			if vertex.distance_squared_to(shape_vertex) <= 0.000001:
				found = true
				break
		if not found:
			missing += 1
	return missing

func _finish() -> void:
	print(
		"COLLISION_TELEMETRY grounded=", grounded_frames,
		" air=", air_frames,
		" kicker_speed=", kicker_speed,
		" grind_speed=", grind_speed,
		" state=", SkierController.State.keys()[skier.state]
	)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("COLLISION_PASS: sculpted kicker ride, rail capture, contact stability, and tree block checks passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("COLLISION_FAIL: " + failure)
		get_tree().quit(1)
