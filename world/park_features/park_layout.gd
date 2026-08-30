class_name ParkLayout
extends RefCounted

const PITCH_DEG := 18.0
const FACE_THICKNESS := 1.5
const FACE_WIDTH := 64.0
const FACE_SLOPE_LENGTH := 315.0
const SURFACE_Y_AT_ORIGIN := 52.0
const SNOW_SHADOW := Color("#a9c7d8")
const SnowSurface := preload("res://world/snow_material.gd")

static func pitch_rad() -> float:
	return deg_to_rad(PITCH_DEG)

static func snow_normal() -> Vector3:
	var pitch := pitch_rad()
	return Vector3(0.0, cos(pitch), -sin(pitch))

static func downhill() -> Vector3:
	var pitch := pitch_rad()
	return Vector3(0.0, -sin(pitch), -cos(pitch))

static func downhill_basis(yaw_deg: float = 0.0) -> Basis:
	var basis := Basis.looking_at(downhill(), snow_normal())
	if absf(yaw_deg) > 0.01:
		basis = basis.rotated(snow_normal(), deg_to_rad(yaw_deg))
	return basis

static func snow_at(x: float, z: float) -> Vector3:
	return Vector3(x, SURFACE_Y_AT_ORIGIN + z * tan(pitch_rad()), z)

static func along_slope(origin: Vector3, distance: float, yaw_deg: float = 0.0) -> Vector3:
	return origin + downhill_basis(yaw_deg) * Vector3(0.0, 0.0, -distance)

static func face_center() -> Vector3:
	return snow_at(0.0, 0.0) - snow_normal() * (FACE_THICKNESS * 0.5)

static func spawn_position() -> Vector3:
	return snow_at(0.0, 138.0) + snow_normal() * 1.15

static func hub_position() -> Vector3:
	return Vector3(0.0, 0.2, -168.0)

static func jump_table(physics_profile: SkiPhysicsProfile, design_speed: float, extra_lip_deg: float, drop: float = 0.0, design_pop_strength: float = -1.0) -> Dictionary:
	var extra := deg_to_rad(extra_lip_deg)
	var n := snow_normal()
	var d := downhill()
	var lip_dir := (d * cos(extra) + n * sin(extra)).normalized()
	var velocity := lip_dir * design_speed
	var resolved_pop_strength := design_pop_strength if design_pop_strength >= 0.0 else physics_profile.minimum_pop_strength
	velocity += n * physics_profile.pop_impulse * clampf(resolved_pop_strength, 0.0, 1.0)
	var gravity := Vector3(0.0, -physics_profile.air_gravity, 0.0)
	var position := Vector3.ZERO
	var dt := 1.0 / 120.0
	var range_along := 0.0
	for _i in range(1440):
		position += velocity * dt
		velocity += gravity * dt
		range_along = position.dot(d)
		if range_along > 2.5 and n.dot(position) <= -drop:
			break
	range_along = maxf(range_along, 6.0)
	var table_length := range_along * 0.72
	var landing_length := maxf(8.0, (range_along - table_length) * 1.4)
	var lip_length := clampf(7.0 + extra_lip_deg * 0.35, 7.0, 12.0)
	return {
		"lip_length": lip_length,
		"table_length": table_length,
		"landing_length": landing_length,
		"range": range_along,
		"lip_dir": lip_dir,
	}

static func add_tabletop(parent: Node3D, label: String, physics_profile: SkiPhysicsProfile, x: float, lip_z: float, design_speed: float, extra_lip_deg: float, width: float = 8.5, drop: float = 0.0, yaw_deg: float = 0.0, design_pop_strength: float = -1.0) -> Node3D:
	var sizing := jump_table(physics_profile, design_speed, extra_lip_deg, drop, design_pop_strength)
	var extra := deg_to_rad(extra_lip_deg)
	var n := snow_normal()
	var basis := downhill_basis(yaw_deg)
	var down := -basis.z
	var lip_start := snow_at(x, lip_z)
	var lip_length: float = sizing.lip_length
	var table_length: float = sizing.table_length
	var landing_length: float = sizing.landing_length
	var lip_rise := maxf(0.42, lip_length * tan(extra) * 0.62)
	var run_in_length := clampf(lip_length * 0.68, 4.5, 7.5)
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_jumps")
	parent.add_child(root)

	var lip_centers: Array[Vector3] = []
	var lip_widths := PackedFloat32Array()
	var lip_shoulders := PackedFloat32Array()
	var lip_samples := 14
	for sample: int in range(lip_samples):
		var t := float(sample) / float(lip_samples - 1)
		var distance_along := lerpf(-run_in_length, lip_length, t)
		var height := 0.001
		if distance_along > 0.0:
			var ramp_t := clampf(distance_along / lip_length, 0.0, 1.0)
			height += _hermite(ramp_t, 0.0, lip_rise, 0.0, tan(extra), lip_length)
		lip_centers.append(lip_start + down * distance_along + n * height)
		lip_widths.append(width * lerpf(1.38, 1.0, smoothstep(0.0, 1.0, t)))
		lip_shoulders.append(maxf(height - 0.001, 0.0))
	_add_profiled_snow_body(root, "Lip", lip_centers, lip_widths, lip_shoulders, n, 0.58, SnowSurface.Kind.GROOMED, 0.18, true)

	# The table is a rounded knuckle mound rather than a raised rectangular slab.
	var table_centers: Array[Vector3] = []
	var table_widths := PackedFloat32Array()
	var table_shoulders := PackedFloat32Array()
	var table_samples := 10
	for sample: int in range(table_samples):
		var t := float(sample) / float(table_samples - 1)
		var distance_along := lip_length + 0.32 + table_length * t
		var knuckle_height := lerpf(maxf(lip_rise - 0.34, 0.18), 0.055, _smootherstep(t))
		table_centers.append(lip_start + down * distance_along + n * knuckle_height)
		table_widths.append(width * lerpf(1.08, 1.34, _smootherstep(t)))
		table_shoulders.append(maxf(knuckle_height - 0.001, 0.0))
	_add_profiled_snow_body(root, "Table", table_centers, table_widths, table_shoulders, n, 0.62, SnowSurface.Kind.PACKED, 0.42, true)

	# A raised knuckle rolls progressively back into the piste, giving both the
	# touchdown and run-out a matched tangent instead of a landing slab edge.
	var landing_centers: Array[Vector3] = []
	var landing_widths := PackedFloat32Array()
	var landing_shoulders := PackedFloat32Array()
	var run_out_length := clampf(landing_length * 0.28, 3.5, 6.0)
	var landing_samples := 14
	var landing_crown := clampf(0.28 + lip_rise * 0.22, 0.42, 0.82)
	for sample: int in range(landing_samples):
		var t := float(sample) / float(landing_samples - 1)
		var distance_along := lip_length + table_length + (landing_length + run_out_length) * t
		var landing_t := clampf((landing_length + run_out_length) * t / landing_length, 0.0, 1.0)
		var height := 0.001 + landing_crown * (1.0 - _smootherstep(landing_t))
		landing_centers.append(lip_start + down * distance_along + n * height)
		landing_widths.append(width * lerpf(1.28, 1.62, _smootherstep(t)))
		landing_shoulders.append(maxf(height - 0.001, 0.0))
	_add_profiled_snow_body(root, "Landing", landing_centers, landing_widths, landing_shoulders, n, 0.68, SnowSurface.Kind.PACKED, 0.28, true, SnowSurface.Kind.GROOMED)
	root.set_meta("lip_z", lip_z)
	root.set_meta("table_length", table_length)
	root.set_meta("range", sizing.range)
	root.set_meta("profile_samples", lip_samples + table_samples + landing_samples)
	return root

static func add_roller(parent: Node3D, label: String, x: float, z: float, length: float = 8.0, height: float = 0.8, width: float = 9.0) -> Node3D:
	var n := snow_normal()
	var down := downhill()
	var start := snow_at(x, z)
	var root := Node3D.new()
	root.name = label
	parent.add_child(root)
	var transition := clampf(length * 0.22, 1.0, 2.0)
	var centers: Array[Vector3] = []
	var widths := PackedFloat32Array()
	var shoulders := PackedFloat32Array()
	var samples := 13
	for sample: int in range(samples):
		var t := float(sample) / float(samples - 1)
		var distance_along := lerpf(-transition, length + transition, t)
		var roller_t := clampf(distance_along / length, 0.0, 1.0)
		var inside := 1.0 if distance_along >= 0.0 and distance_along <= length else 0.0
		var shaped_height := height * pow(sin(PI * roller_t), 2.0) * inside
		centers.append(start + down * distance_along + n * (0.001 + shaped_height))
		widths.append(width * lerpf(1.18, 1.0, sin(PI * t)))
		shoulders.append(shaped_height)
	_add_profiled_snow_body(root, "RollerSurface", centers, widths, shoulders, n, 0.52, SnowSurface.Kind.PACKED, 0.16, true)
	root.set_meta("profile_samples", samples)
	return root

static func add_hip(parent: Node3D, label: String, physics_profile: SkiPhysicsProfile, x: float, lip_z: float, design_speed: float, extra_lip_deg: float, yaw_deg: float, design_pop_strength: float = -1.0) -> Node3D:
	return add_tabletop(parent, label, physics_profile, x, lip_z, design_speed, extra_lip_deg, 9.0, 0.0, yaw_deg, design_pop_strength)

static func add_berm(parent: Node3D, label: String, x: float, z: float, length: float, width: float, bank_deg: float, yaw_deg: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_terrain_features")
	parent.add_child(root)
	var basis := downhill_basis(yaw_deg)
	var right := basis.x.normalized()
	var down := -basis.z.normalized()
	var normal := snow_normal()
	var start := snow_at(x, z)
	var half_width := width * 0.5
	var bank_rise := tan(deg_to_rad(bank_deg)) * half_width
	var transition := clampf(length * 0.28, 3.0, 5.5)
	var rows: Array[PackedVector3Array] = []
	var longitudinal_samples := 13
	var lateral_samples := 9
	for longitudinal: int in range(longitudinal_samples):
		var t := float(longitudinal) / float(longitudinal_samples - 1)
		var distance_along := lerpf(-transition, length + transition, t)
		var enter := smoothstep(-transition, minf(transition, length * 0.42), distance_along)
		var exit := 1.0 - smoothstep(maxf(length - transition, length * 0.58), length + transition, distance_along)
		var bank_presence := minf(enter, exit)
		var row := PackedVector3Array()
		for lateral: int in range(lateral_samples):
			var across := lerpf(-1.0, 1.0, float(lateral) / float(lateral_samples - 1))
			var inner_across := clampf(across / 0.74, -1.0, 1.0)
			var shoulder_blend := 1.0 - _smootherstep(inverse_lerp(0.72, 1.0, absf(across)))
			var center := start + down * distance_along + normal * 0.001
			var bank_height := bank_rise * inner_across * bank_presence * shoulder_blend
			row.append(center + right * (half_width * across) + normal * bank_height)
		rows.append(row)
	_add_grid_snow_body(root, "BankSurface", rows, normal, 0.72, SnowSurface.Kind.PACKED, 0.24, true)
	root.set_meta("profile_samples", longitudinal_samples)
	return root

static func add_mogul_field(parent: Node3D, label: String, x: float, z: float, rows: int, spacing: float, height: float, width: float) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_terrain_features")
	parent.add_child(root)
	for row: int in range(maxi(rows, 1)):
		var row_x := x + (-1.0 if row % 2 == 0 else 1.0) * width * 0.28
		add_roller(root, "Mogul%02d" % row, row_x, z - float(row) * spacing, spacing * 0.72, height, width)
	return root

static func add_butter_pad(parent: Node3D, label: String, x: float, z: float, length: float, width: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_terrain_features")
	parent.add_child(root)
	add_slope_box(root, "ButterDeck", x, z, Vector3(width, maxf(height, 0.08), length), 0.0, SNOW_SHADOW, SnowSurface.Kind.PACKED, true, height)
	return root

static func add_side_hit(parent: Node3D, label: String, x: float, z: float, length: float, height: float, width: float, yaw_deg: float) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_jumps")
	parent.add_child(root)
	var basis := downhill_basis(yaw_deg)
	var down := -basis.z.normalized()
	var normal := snow_normal()
	var start := snow_at(x, z)
	var transition := clampf(length * 0.28, 2.2, 4.0)
	var centers: Array[Vector3] = []
	var widths := PackedFloat32Array()
	var shoulders := PackedFloat32Array()
	var samples := 12
	for sample: int in range(samples):
		var t := float(sample) / float(samples - 1)
		var distance_along := lerpf(-transition, length, t)
		var ramp_t := clampf(distance_along / length, 0.0, 1.0)
		var shaped_height := height * _smootherstep(ramp_t)
		centers.append(start + down * distance_along + normal * (0.001 + shaped_height))
		widths.append(width * lerpf(1.34, 1.0, _smootherstep(t)))
		shoulders.append(shaped_height)
	_add_profiled_snow_body(root, "SideHitDeck", centers, widths, shoulders, normal, 0.66, SnowSurface.Kind.GROOMED, 0.2, true)
	root.set_meta("profile_samples", samples)
	return root

static func add_wallride(parent: Node3D, label: String, x: float, z: float, length: float, height: float, yaw_deg: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_wallrides")
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.name = "RideSurface"
	body.collision_layer = 1
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", SnowSurface.Kind.GROOMED)
	body.transform = Transform3D(downhill_basis(yaw_deg), snow_at(x, z) + snow_normal() * (height * 0.5))
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, height, length)
	mesh_instance.mesh = mesh
	var wall_direction_3d := -downhill_basis(yaw_deg).z
	mesh_instance.material_override = material_for_surface(color, -1, Vector2(wall_direction_3d.x, wall_direction_3d.z))
	body.add_child(mesh_instance)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	shape_node.shape = shape
	body.add_child(shape_node)
	root.add_child(body)
	return root

static func add_bonk(parent: Node3D, label: String, x: float, z: float, height: float, radius: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_bonks")
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.name = "BonkBody"
	body.collision_layer = 4
	body.collision_mask = 2
	body.transform = Transform3D(downhill_basis(), snow_at(x, z) + snow_normal() * (height * 0.5))
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.55
	material.roughness = 0.28
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shape_node.shape = shape
	body.add_child(shape_node)
	root.add_child(body)
	return root

static func add_cannon(parent: Node3D, label: String, x: float, z: float, length: float, width: float, height: float) -> Node3D:
	var root := add_side_hit(parent, label, x, z, length, height, width, 0.0)
	root.add_to_group("park_cannons")
	return root

static func add_gate(parent: Node3D, label: String, x: float, z: float, width: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_gates")
	parent.add_child(root)
	var normal := snow_normal()
	var center := snow_at(x, z)
	var destination_gate := width >= 30.0
	var post_height := 5.4 if destination_gate else 3.6
	var beam_thickness := 0.64 if destination_gate else 0.28
	var post_thickness := 0.52 if destination_gate else 0.22
	_add_gate_mesh(root, center + Vector3.LEFT * width * 0.5 + normal * (post_height * 0.5), Vector3(post_thickness, post_height, post_thickness), color)
	_add_gate_mesh(root, center + Vector3.RIGHT * width * 0.5 + normal * (post_height * 0.5), Vector3(post_thickness, post_height, post_thickness), color)
	_add_gate_mesh(root, center + normal * (post_height - beam_thickness * 0.5), Vector3(width + post_thickness, beam_thickness, beam_thickness), color)
	return root

static func _add_gate_mesh(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.42
	instance.material_override = material
	parent.add_child(instance)

static func add_slope_box(parent: Node3D, label: String, x: float, z: float, size: Vector3, yaw_deg: float, color: Color, surface_kind: int, collision_enabled: bool, extra_height: float = 0.0, visual_surface_kind: int = -1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	var n := snow_normal()
	body.transform = Transform3D(downhill_basis(yaw_deg), snow_at(x, z) + n * (extra_height - size.y * 0.5))
	body.collision_layer = 1 if collision_enabled else 0
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", surface_kind)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var groom_direction_3d := -downhill_basis(yaw_deg).z
	var material_kind := visual_surface_kind if visual_surface_kind >= 0 else surface_kind
	mesh_instance.material_override = material_for_surface(color, material_kind, Vector2(groom_direction_3d.x, groom_direction_3d.z))
	body.add_child(mesh_instance)
	if collision_enabled:
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
	parent.add_child(body)
	return body

static func add_rail(parent: Node3D, label: String, points: Array, type: GrindRail3D.RailType, capture_radius: float, friction: float) -> GrindRail3D:
	var rail := GrindRail3D.new()
	rail.name = label
	rail.rail_type = type
	rail.capture_radius = capture_radius
	rail.base_friction = friction
	rail.path = Curve3D.new()
	for point: Vector3 in points:
		rail.path.add_point(point)
	parent.add_child(rail)
	return rail

static func rail_point(x: float, z: float, extra_height: float = 0.18) -> Vector3:
	return snow_at(x, z) + snow_normal() * extra_height

static func add_rail_contours(parent: Node3D, label: String, points: Array[Vector3]) -> Node3D:
	if points.size() < 2:
		return null
	var root := Node3D.new()
	root.name = label + "SnowContours"
	root.add_to_group("park_terrain_features")
	parent.add_child(root)
	var normal := snow_normal()
	var entry_tangent := (points[1] - points[0]).normalized()
	var exit_tangent := (points[-1] - points[-2]).normalized()
	_add_rail_apron(root, "Approach", points[0], entry_tangent, normal, true)
	_add_rail_apron(root, "Runout", points[-1], exit_tangent, normal, false)
	return root

static func _add_rail_apron(parent: Node3D, label: String, anchor: Vector3, tangent: Vector3, normal: Vector3, approach: bool) -> void:
	var centers: Array[Vector3] = []
	var widths := PackedFloat32Array()
	var shoulders := PackedFloat32Array()
	var samples := 9
	for sample: int in range(samples):
		var t := float(sample) / float(samples - 1)
		var distance_along := lerpf(-5.2, 1.8, t) if approach else lerpf(-1.3, 4.8, t)
		var position := anchor + tangent * distance_along
		var snow_position := snow_at(position.x, position.z)
		var crest := pow(sin(PI * t), 2.0) * 0.16
		centers.append(snow_position + normal * (0.001 + crest))
		var narrow_t := _smootherstep(t) if approach else 1.0 - _smootherstep(t)
		widths.append(lerpf(4.6, 3.0, narrow_t))
		shoulders.append(crest)
	_add_profiled_snow_body(parent, label, centers, widths, shoulders, normal, 0.34, SnowSurface.Kind.GROOMED, 0.12, true)

static func material_for_surface(color: Color, surface_kind: int, groom_direction_world_xz: Vector2 = Vector2(0.0, -1.0)) -> Material:
	if surface_kind >= 0:
		return SnowSurface.create(surface_kind, groom_direction_world_xz)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material

static func _hermite(t: float, start_height: float, end_height: float, start_slope: float, end_slope: float, length: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (
		(2.0 * t3 - 3.0 * t2 + 1.0) * start_height
		+ (t3 - 2.0 * t2 + t) * length * start_slope
		+ (-2.0 * t3 + 3.0 * t2) * end_height
		+ (t3 - t2) * length * end_slope
	)

static func _smootherstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

static func _add_profiled_snow_body(
	parent: Node3D,
	label: String,
	centers: Array[Vector3],
	widths: PackedFloat32Array,
	edge_drops: PackedFloat32Array,
	normal: Vector3,
	bury: float,
	kind: SnowSurface.Kind,
	feature_emphasis: float,
	collision_enabled: bool,
	visual_kind: int = -1
) -> StaticBody3D:
	if centers.size() < 2 or widths.size() != centers.size() or edge_drops.size() != centers.size():
		push_error("Invalid profiled snow form: " + label)
		return null
	var longitudinal := (centers[-1] - centers[0]).normalized()
	var right := longitudinal.cross(normal).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var rows: Array[PackedVector3Array] = []
	var lateral_samples := 7
	for section: int in range(centers.size()):
		var row := PackedVector3Array()
		for lateral: int in range(lateral_samples):
			var across := lerpf(-1.0, 1.0, float(lateral) / float(lateral_samples - 1))
			var shoulder := smoothstep(0.58, 1.0, absf(across))
			row.append(centers[section] + right * (widths[section] * 0.5 * across) - normal * edge_drops[section] * shoulder)
		rows.append(row)
	return _add_grid_snow_body(parent, label, rows, normal, bury, kind, feature_emphasis, collision_enabled, visual_kind)

static func _add_grid_snow_body(
	parent: Node3D,
	label: String,
	world_rows: Array[PackedVector3Array],
	normal: Vector3,
	bury: float,
	kind: SnowSurface.Kind,
	feature_emphasis: float,
	collision_enabled: bool,
	visual_kind: int = -1
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1 if collision_enabled else 0
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", kind)
	body.set_meta("profile_rows", world_rows.size())
	body.set_meta("profile_columns", world_rows[0].size() if not world_rows.is_empty() else 0)
	if world_rows.size() < 2 or world_rows[0].size() < 2:
		push_error("Snow grid requires at least two rows and columns: " + label)
		parent.add_child(body)
		return body
	var origin := world_rows[0][world_rows[0].size() / 2]
	body.position = origin
	var local_rows: Array[PackedVector3Array] = []
	for world_row: PackedVector3Array in world_rows:
		var local_row := PackedVector3Array()
		for point: Vector3 in world_row:
			local_row.append(point - origin)
		local_rows.append(local_row)
	var mesh := _profile_grid_mesh(local_rows, normal, bury)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var groom_direction := world_rows[-1][world_rows[-1].size() / 2] - world_rows[0][world_rows[0].size() / 2]
	var material_kind := visual_kind if visual_kind >= 0 else kind
	mesh_instance.material_override = SnowSurface.create(material_kind, Vector2(groom_direction.x, groom_direction.z), feature_emphasis)
	body.add_child(mesh_instance)
	if collision_enabled:
		var shape_node := CollisionShape3D.new()
		shape_node.shape = mesh.create_trimesh_shape()
		if shape_node.shape is ConcavePolygonShape3D:
			(shape_node.shape as ConcavePolygonShape3D).backface_collision = true
		body.add_child(shape_node)
	parent.add_child(body)
	return body

static func _profile_grid_mesh(rows: Array[PackedVector3Array], normal: Vector3, bury: float) -> ArrayMesh:
	var row_count := rows.size()
	var column_count := rows[0].size()
	var bottom_rows: Array[PackedVector3Array] = []
	for row: PackedVector3Array in rows:
		var bottom := PackedVector3Array()
		for point: Vector3 in row:
			bottom.append(point - normal * bury)
		bottom_rows.append(bottom)
	var top_normals: Array[PackedVector3Array] = []
	for row_index: int in range(row_count):
		var normal_row := PackedVector3Array()
		for column_index: int in range(column_count):
			var previous_row := maxi(row_index - 1, 0)
			var next_row := mini(row_index + 1, row_count - 1)
			var previous_column := maxi(column_index - 1, 0)
			var next_column := mini(column_index + 1, column_count - 1)
			var longitudinal := rows[next_row][column_index] - rows[previous_row][column_index]
			var lateral := rows[row_index][next_column] - rows[row_index][previous_column]
			var vertex_normal := lateral.cross(longitudinal).normalized()
			if vertex_normal.dot(normal) < 0.0:
				vertex_normal = -vertex_normal
			normal_row.append(vertex_normal)
		top_normals.append(normal_row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row_index: int in range(row_count - 1):
		for column_index: int in range(column_count - 1):
			var a := rows[row_index][column_index]
			var b := rows[row_index + 1][column_index]
			var c := rows[row_index + 1][column_index + 1]
			var d := rows[row_index][column_index + 1]
			var uv_a := Vector2(float(column_index), float(row_index)) * 0.2
			var uv_b := Vector2(float(column_index), float(row_index + 1)) * 0.2
			var uv_c := Vector2(float(column_index + 1), float(row_index + 1)) * 0.2
			var uv_d := Vector2(float(column_index + 1), float(row_index)) * 0.2
			_add_smooth_tri(st, a, d, c, top_normals[row_index][column_index], top_normals[row_index][column_index + 1], top_normals[row_index + 1][column_index + 1], uv_a, uv_d, uv_c)
			_add_smooth_tri(st, a, c, b, top_normals[row_index][column_index], top_normals[row_index + 1][column_index + 1], top_normals[row_index + 1][column_index], uv_a, uv_c, uv_b)
			_add_flat_quad(st, bottom_rows[row_index][column_index], bottom_rows[row_index + 1][column_index], bottom_rows[row_index + 1][column_index + 1], bottom_rows[row_index][column_index + 1])
	for row_index: int in range(row_count - 1):
		_add_flat_quad(st, rows[row_index][0], rows[row_index + 1][0], bottom_rows[row_index + 1][0], bottom_rows[row_index][0])
		_add_flat_quad(st, rows[row_index][-1], bottom_rows[row_index][-1], bottom_rows[row_index + 1][-1], rows[row_index + 1][-1])
	for column_index: int in range(column_count - 1):
		_add_flat_quad(st, rows[0][column_index], bottom_rows[0][column_index], bottom_rows[0][column_index + 1], rows[0][column_index + 1])
		_add_flat_quad(st, rows[-1][column_index], rows[-1][column_index + 1], bottom_rows[-1][column_index + 1], bottom_rows[-1][column_index])
	st.generate_tangents()
	return st.commit()

static func _add_smooth_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3, normal_b: Vector3, normal_c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	for vertex: Array in [[a, normal_a, uv_a], [b, normal_b, uv_b], [c, normal_c, uv_c]]:
		st.set_normal(vertex[1])
		st.set_uv(vertex[2])
		st.add_vertex(vertex[0])

static func _add_flat_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var face_normal := (b - a).cross(c - a).normalized()
	_add_smooth_tri(st, a, b, c, face_normal, face_normal, face_normal, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE)
	_add_smooth_tri(st, a, c, d, face_normal, face_normal, face_normal, Vector2.ZERO, Vector2.ONE, Vector2.DOWN)

static func _deck_quad(uphill: Vector3, downhill_edge: Vector3, right: Vector3, width: float) -> PackedVector3Array:
	var hw := width * 0.5
	return PackedVector3Array([
		uphill - right * hw,
		uphill + right * hw,
		downhill_edge - right * hw,
		downhill_edge + right * hw,
	])

static func _add_deck_prism(parent: Node3D, label: String, deck: PackedVector3Array, normal: Vector3, bury: float, kind: SnowSurface.Kind, collision_enabled: bool) -> StaticBody3D:
	var origin := (deck[0] + deck[1] + deck[2] + deck[3]) * 0.25
	var local := PackedVector3Array()
	for point: Vector3 in deck:
		local.append(point - origin)
	var buried := PackedVector3Array()
	for point: Vector3 in local:
		buried.append(point - normal * bury)
	var points := PackedVector3Array()
	points.append_array(local)
	points.append_array(buried)
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 1 if collision_enabled else 0
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", kind)
	var shape_node := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape_node.shape = convex
	body.add_child(shape_node)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _wedge_mesh(points)
	var uphill_center := (deck[0] + deck[1]) * 0.5
	var downhill_center := (deck[2] + deck[3]) * 0.5
	var deck_direction := downhill_center - uphill_center
	# Traffic breaks up the source texture on feature decks without stamping the
	# same scuffed pattern across the freshly groomed main face.
	var feature_emphasis := 0.0
	match label:
		"Lip": feature_emphasis = 0.18
		"Table": feature_emphasis = 0.42
		"Landing": feature_emphasis = 0.28
	mesh_instance.material_override = SnowSurface.create(kind, Vector2(deck_direction.x, deck_direction.z), feature_emphasis)
	body.add_child(mesh_instance)
	parent.add_child(body)
	return body

static func _wedge_mesh(points: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[0, 2, 3, 1],
		[4, 5, 7, 6],
		[0, 1, 5, 4],
		[2, 6, 7, 3],
		[0, 4, 6, 2],
		[1, 3, 7, 5],
	]
	for face: Array in faces:
		var a: Vector3 = points[int(face[0])]
		var b: Vector3 = points[int(face[1])]
		var c: Vector3 = points[int(face[2])]
		var d: Vector3 = points[int(face[3])]
		_add_wedge_tri(st, a, b, c)
		_add_wedge_tri(st, a, c, d)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func _add_wedge_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if not normal.is_finite() or normal.length_squared() < 0.0001:
		normal = Vector3.UP
	for point: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.set_uv(Vector2(point.x * 0.12, point.z * 0.12))
		st.add_vertex(point)
