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
	var right := basis.x
	var down := -basis.z
	var lip_start := snow_at(x, lip_z)
	var lip_length: float = sizing.lip_length
	var table_length: float = sizing.table_length
	var landing_length: float = sizing.landing_length
	var lip_tip := lip_start + down * lip_length + n * (lip_length * tan(extra))
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_jumps")
	parent.add_child(root)
	_add_deck_prism(root, "Lip", _deck_quad(lip_start, lip_tip, right, width), n, 0.55, SnowSurface.Kind.GROOMED, true)
	var table_end := lip_tip + down * table_length
	_add_deck_prism(root, "Table", _deck_quad(lip_tip, table_end, right, width * 1.05), n, 0.5, SnowSurface.Kind.PACKED, true)
	var land_start := lip_start + down * (lip_length + table_length) - n * drop
	var land_end := land_start + down * landing_length
	_add_deck_prism(root, "Landing", _deck_quad(land_start, land_end, right, width * 1.25), n, 0.7, SnowSurface.Kind.PACKED, true)
	root.set_meta("lip_z", lip_z)
	root.set_meta("table_length", table_length)
	root.set_meta("range", sizing.range)
	return root

static func add_roller(parent: Node3D, label: String, x: float, z: float, length: float = 8.0, height: float = 0.8, width: float = 9.0) -> Node3D:
	var n := snow_normal()
	var down := downhill()
	var right := Vector3.RIGHT
	var start := snow_at(x, z)
	var peak := start + down * (length * 0.5) + n * height
	var finish := start + down * length
	var root := Node3D.new()
	root.name = label
	parent.add_child(root)
	_add_deck_prism(root, "RollerUp", _deck_quad(start, peak, right, width), n, 0.55, SnowSurface.Kind.PACKED, true)
	_add_deck_prism(root, "RollerDown", _deck_quad(peak, finish, right, width), n, 0.55, SnowSurface.Kind.PACKED, true)
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
	var finish := start + down * length
	var half_width := width * 0.5
	var bank_rise := tan(deg_to_rad(bank_deg)) * half_width
	# Lead-in ramp: the raised side of the bank otherwise ends in a sheer wall
	# that dead-stops anyone riding the fall line into it.
	var lead := clampf(bank_rise / tan(deg_to_rad(12.0)), 3.0, 8.0)
	var lead_end := start + down * lead
	var ramp := PackedVector3Array([
		start - right * half_width,
		start + right * half_width,
		lead_end - right * half_width - normal * bank_rise,
		lead_end + right * half_width + normal * bank_rise,
	])
	_add_deck_prism(root, "BankLeadIn", ramp, normal, 0.8, SnowSurface.Kind.PACKED, true)
	# The banked deck starts where the lead-in reaches full bank height, so no
	# sheer uphill wall is ever exposed.
	var deck := PackedVector3Array([
		lead_end - right * half_width - normal * bank_rise,
		lead_end + right * half_width + normal * bank_rise,
		finish - right * half_width - normal * bank_rise,
		finish + right * half_width + normal * bank_rise,
	])
	_add_deck_prism(root, "BankedDeck", deck, normal, 0.8, SnowSurface.Kind.PACKED, true)
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
	var right := basis.x.normalized()
	var down := -basis.z.normalized()
	var normal := snow_normal()
	var start := snow_at(x, z)
	var tip := start + down * length + normal * height
	_add_deck_prism(root, "SideHitDeck", _deck_quad(start, tip, right, width), normal, 0.7, SnowSurface.Kind.GROOMED, true)
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

static func add_slope_box(parent: Node3D, label: String, x: float, z: float, size: Vector3, yaw_deg: float, color: Color, surface_kind: int, collision_enabled: bool, extra_height: float = 0.0) -> StaticBody3D:
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
	mesh_instance.material_override = material_for_surface(color, surface_kind, Vector2(groom_direction_3d.x, groom_direction_3d.z))
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

static func material_for_surface(color: Color, surface_kind: int, groom_direction_world_xz: Vector2 = Vector2(0.0, -1.0)) -> Material:
	if surface_kind >= 0:
		return SnowSurface.create(surface_kind, groom_direction_world_xz)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material

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
	mesh_instance.material_override = SnowSurface.create(kind, Vector2(deck_direction.x, deck_direction.z))
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
