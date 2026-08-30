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
	if path == null or path.point_count < 2:
		push_warning("Disabled invalid grind rail: %s" % name)
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	path.bake_interval = 0.18
	path_length = path.get_baked_length()
	_build_visual_and_collision()

func capture_candidate(world_position: Vector3, world_velocity: Vector3, required_radius: float, minimum_speed: float) -> Dictionary:
	if path_length <= 0.01 or world_velocity.length() < minimum_speed:
		return {"valid": false}
	var local_position := to_local(world_position)
	var local_offset := path.get_closest_offset(local_position)
	var rail_position := to_global(path.sample_baked(local_offset, true) + Vector3.UP * grind_height_offset)
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
	var rail_position := to_global(path.sample_baked(local_offset, true) + Vector3.UP * grind_height_offset)
	var distance := world_position.distance_to(rail_position)
	if distance > preview_radius:
		return {"valid": false}
	var tangent := tangent_at(local_offset)
	var approach := world_velocity.normalized().dot(tangent)
	return {"valid": absf(approach) > 0.35, "distance": distance}

func sample_world(offset: float) -> Vector3:
	return to_global(path.sample_baked(clampf(offset, 0.0, path_length), true) + Vector3.UP * grind_height_offset)

func tangent_at(offset: float) -> Vector3:
	var a := path.sample_baked(clampf(offset - 0.08, 0.0, path_length), true)
	var b := path.sample_baked(clampf(offset + 0.08, 0.0, path_length), true)
	return global_basis * (b - a).normalized()

func _build_visual_and_collision() -> void:
	var samples := path.get_baked_points()
	for index: int in range(samples.size() - 1):
		var a := samples[index]
		var b := samples[index + 1]
		var delta := b - a
		var midpoint := (a + b) * 0.5
		var visual := MeshInstance3D.new()
		var collision := CollisionShape3D.new()
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 2
		if rail_type == RailType.BOX:
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1.15, 0.22, delta.length())
			visual.mesh = box_mesh
			var box_shape := BoxShape3D.new()
			box_shape.size = box_mesh.size
			collision.shape = box_shape
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.075
			cylinder.bottom_radius = 0.075
			cylinder.height = delta.length()
			visual.mesh = cylinder
			var cylinder_shape := CylinderShape3D.new()
			cylinder_shape.radius = 0.075
			cylinder_shape.height = delta.length()
			collision.shape = cylinder_shape
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b9784e") if rail_type == RailType.BOX else Color("#536d78")
		material.metallic = 0.48 if rail_type != RailType.BOX else 0.08
		material.roughness = 0.46 if rail_type != RailType.BOX else 0.58
		material.emission_enabled = false
		visual.material_override = material
		visual.visibility_range_end = 190.0
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		visual.position = midpoint
		visual.basis = Basis.looking_at(delta.normalized(), Vector3.UP).rotated(Vector3.RIGHT, PI * 0.5)
		body.position = midpoint
		body.basis = visual.basis
		body.add_child(collision)
		add_child(visual)
		add_child(body)
