class_name GrindRail3D
extends Node3D

enum RailType { RAIL, BOX, PIPE, COPING, LOG, OTHER }

@export var path: Curve3D
@export var capture_radius: float = 1.1
@export_range(0.0, 90.0) var approach_angle_degrees: float = 68.0
@export var grind_height_offset: float = 0.2
@export var base_friction: float = 0.75
@export var rail_type := RailType.RAIL
@export var allow_both_directions := true
@export var maximum_capture_height := 0.95
@export var maximum_capture_depth := 0.32
@export_range(-1.0, 1.0) var drift_bias := 0.0

var path_length := 0.0

func _ready() -> void:
	add_to_group("grind_rails")
	set_meta("asset_id", "grind_rail")
	set_meta("asset_class", "GRIND_ONLY")
	set_meta("collision_policy", "GRIND_ONLY")
	set_meta("readability_category", "jib")
	if path == null or path.point_count < 2:
		push_warning("Disabled invalid grind rail: %s" % name)
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	path.bake_interval = 0.08
	path_length = path.get_baked_length()
	_build_visual_and_collision()

func capture_candidate(world_position: Vector3, world_velocity: Vector3, required_radius: float, minimum_speed: float) -> Dictionary:
	if path_length <= 0.01 or world_velocity.length() < minimum_speed:
		return {"valid": false}
	var local_position := to_local(world_position)
	var local_offset := path.get_closest_offset(local_position)
	var rail_position := to_global(path.sample_baked(local_offset, true) + _grind_offset())
	var tangent := tangent_at(local_offset)
	var offset_from_rail := world_position - rail_position
	var vertical_gap := offset_from_rail.dot(Vector3.UP)
	var lateral_axis := Vector3.UP.cross(tangent).normalized()
	if lateral_axis.length_squared() < 0.01:
		lateral_axis = global_basis.x.normalized()
	var signed_lateral := offset_from_rail.dot(lateral_axis)
	var distance := offset_from_rail.length()
	var approach := absf(world_velocity.normalized().dot(tangent))
	var minimum_alignment := cos(deg_to_rad(approach_angle_degrees))
	if (
		distance > minf(capture_radius, required_radius)
		or approach < minimum_alignment
		or vertical_gap > maximum_capture_height
		or vertical_gap < -maximum_capture_depth
	):
		return {"valid": false}
	var direction := 1.0 if world_velocity.dot(tangent) >= 0.0 else -1.0
	if not allow_both_directions and direction < 0.0:
		return {"valid": false}
	return {
		"valid": true,
		"offset": local_offset,
		"direction": direction,
		"position": rail_position,
		"tangent": tangent * direction,
		"speed": maxf(minimum_speed, absf(world_velocity.dot(tangent))),
		"distance": distance,
		"signed_lateral": signed_lateral,
	}

func approach_preview(world_position: Vector3, world_velocity: Vector3, preview_radius: float) -> Dictionary:
	# Geometry-only read used for subtle pre-capture anticipation. Never
	# attaches or mutates state; capture_candidate remains the sole authority
	# on whether/when the skier actually locks onto the feature.
	if path_length <= 0.01 or world_velocity.length() < 0.5:
		return {"valid": false}
	var local_offset := path.get_closest_offset(to_local(world_position))
	var rail_position := to_global(path.sample_baked(local_offset, true) + _grind_offset())
	var distance := world_position.distance_to(rail_position)
	if distance > preview_radius:
		return {"valid": false}
	var tangent := tangent_at(local_offset)
	var approach := world_velocity.normalized().dot(tangent)
	return {"valid": absf(approach) > 0.35, "distance": distance}

func sample_world(offset: float) -> Vector3:
	return to_global(path.sample_baked(clampf(offset, 0.0, path_length), true) + _grind_offset())

func tangent_at(offset: float) -> Vector3:
	var a := path.sample_baked(clampf(offset - 0.10, 0.0, path_length), true)
	var b := path.sample_baked(clampf(offset + 0.10, 0.0, path_length), true)
	var delta := b - a
	if delta.length_squared() < 0.0001:
		return global_basis.z.normalized()
	return (global_basis * delta).normalized()

func _grind_offset() -> Vector3:
	return ParkLayout.snow_normal() * grind_height_offset

func _build_visual_and_collision() -> void:
	var samples := path.get_baked_points()
	if samples.size() < 2:
		return
	var visual := MeshInstance3D.new()
	visual.name = "ContinuousRailVisual"
	visual.mesh = _build_continuous_visual_mesh(samples)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#c76833") if rail_type == RailType.BOX else Color("#2f6f82")
	material.metallic = 0.52 if rail_type != RailType.BOX else 0.12
	material.roughness = 0.38 if rail_type != RailType.BOX else 0.52
	material.emission_enabled = false
	visual.material_override = material
	var lod_end := 190.0
	var lod_start := 30.0
	var lod_contract := get_node_or_null("LODContract")
	if lod_contract != null:
		var distances := lod_contract.get_meta("lod_distances_m", Vector3(30.0, 90.0, 190.0)) as Vector3
		lod_start = maxf(distances.x, 1.0)
		lod_end = maxf(distances.z, lod_start + 1.0)
	visual.set_meta("lod_cull_start_m", lod_start)
	visual.set_meta("lod_cull_end_m", lod_end)
	visual.visibility_range_begin = 0.0
	visual.visibility_range_begin_margin = 0.0
	visual.visibility_range_end = lod_end
	visual.visibility_range_end_margin = maxf(lod_start * 0.2, 8.0)
	visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(visual)
	for index: int in range(samples.size() - 1):
		var a := samples[index]
		var b := samples[index + 1]
		var delta := b - a
		var midpoint := (a + b) * 0.5
		var collision := CollisionShape3D.new()
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 2
		body.set_meta("ski_surface_class", "metal")
		body.set_meta("asset_id", "grind_rail")
		body.set_meta("asset_class", "GRIND_ONLY")
		body.set_meta("collision_policy", "GRIND_ONLY")
		if rail_type == RailType.BOX:
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(1.15, 0.22, delta.length())
			collision.shape = box_shape
		else:
			var cylinder_shape := CylinderShape3D.new()
			cylinder_shape.radius = 0.075
			cylinder_shape.height = delta.length()
			collision.shape = cylinder_shape
		body.position = midpoint
		body.basis = _segment_basis(delta)
		body.add_child(collision)
		add_child(body)

func _build_continuous_visual_mesh(samples: PackedVector3Array) -> ArrayMesh:
	var section_count := 12 if rail_type != RailType.BOX else 8
	var section_width := 0.068 if rail_type != RailType.BOX else 0.52
	var section_height := 0.068 if rail_type != RailType.BOX else 0.105
	var is_box := rail_type == RailType.BOX
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for index: int in range(samples.size()):
		var previous := samples[maxi(index - 1, 0)]
		var next := samples[mini(index + 1, samples.size() - 1)]
		var tangent := (next - previous).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector3.FORWARD
		var reference_up := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.94 else Vector3.FORWARD
		var across := tangent.cross(reference_up).normalized()
		var ring_up := across.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var normals := PackedVector3Array()
		if is_box:
			var half_w := section_width
			var half_h := section_height
			var bevel := 0.045
			var box_points_local := PackedVector2Array([
				Vector2(half_w - bevel, half_h),
				Vector2(half_w, half_h - bevel),
				Vector2(half_w, -half_h + bevel),
				Vector2(half_w - bevel, -half_h),
				Vector2(-half_w + bevel, -half_h),
				Vector2(-half_w, -half_h + bevel),
				Vector2(-half_w, half_h - bevel),
				Vector2(-half_w + bevel, half_h),
			])
			var box_normals_local := PackedVector2Array([
				Vector2(0, 1), Vector2(0.707, 0.707), Vector2(1, 0), Vector2(0.707, -0.707),
				Vector2(0, -1), Vector2(-0.707, -0.707), Vector2(-1, 0), Vector2(-0.707, 0.707),
			])
			for section: int in range(section_count):
				var pt := box_points_local[section]
				var n2d := box_normals_local[section]
				var normal := (across * n2d.x + ring_up * n2d.y).normalized()
				ring.append(samples[index] + across * pt.x + ring_up * pt.y)
				normals.append(normal)
		else:
			for section: int in range(section_count):
				var angle := TAU * float(section) / float(section_count)
				var normal := (across * cos(angle) + ring_up * sin(angle)).normalized()
				ring.append(samples[index] + across * cos(angle) * section_width + ring_up * sin(angle) * section_height)
				normals.append(normal)
		rings.append(ring)
		ring_normals.append(normals)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(samples.size() - 1):
		for section: int in range(section_count):
			var next_section := (section + 1) % section_count
			_add_surface_triangle(surface, rings[index][section], ring_normals[index][section], rings[index + 1][section], ring_normals[index + 1][section], rings[index + 1][next_section], ring_normals[index + 1][next_section])
			_add_surface_triangle(surface, rings[index][section], ring_normals[index][section], rings[index + 1][next_section], ring_normals[index + 1][next_section], rings[index][next_section], ring_normals[index][next_section])
	return surface.commit()

func _add_surface_triangle(surface: SurfaceTool, a: Vector3, normal_a: Vector3, b: Vector3, normal_b: Vector3, c: Vector3, normal_c: Vector3) -> void:
	surface.set_normal(normal_a)
	surface.add_vertex(a)
	surface.set_normal(normal_b)
	surface.add_vertex(b)
	surface.set_normal(normal_c)
	surface.add_vertex(c)

func _segment_basis(delta: Vector3) -> Basis:
	var direction := delta.normalized() if delta.length_squared() > 0.0001 else Vector3.FORWARD
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.92:
		up = Vector3.FORWARD
	return Basis.looking_at(direction, up).rotated(Vector3.RIGHT, PI * 0.5)
