class_name SkierEquipment
extends RefCounted

const SKI_SIZE := Vector3(0.115, 0.025, 1.82)
const SKI_CENTER := Vector3(0.0, 0.0, -0.10)
const POLE_SHAFT_RADIUS := 0.014
const POLE_SHAFT_LENGTH := 1.15
const POLE_BASKET_RADIUS := 0.065
const POLE_BASKET_THICKNESS := 0.018

static func material(color: Color, roughness: float, metallic: float, specular: float = 0.5) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = roughness
	value.metallic = metallic
	value.metallic_specular = specular
	return value

static func add_box(parent: Node3D, node_name: String, size: Vector3, local_position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func add_capsule(parent: Node3D, node_name: String, radius: float, height: float, local_position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func add_sphere(parent: Node3D, node_name: String, radius: float, local_position: Vector3, surface: Material, local_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.scale = local_scale
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func add_cylinder(parent: Node3D, node_name: String, radius: float, height: float, local_position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func add_tapered_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, local_position: Vector3, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func build_boot(parent: Node3D, side: String, surface: Material, accent_surface: Material = null) -> void:
	var prefix := side.capitalize()
	# The lower shell retains the calibrated sole envelope while the cuff, toe cap,
	# heel block, and buckles provide a readable alpine-boot silhouette.
	add_box(parent, prefix + "BootMesh", Vector3(0.2, 0.17, 0.4), Vector3(0.0, -0.02, -0.09), surface)
	add_box(parent, prefix + "BootCuff", Vector3(0.18, 0.22, 0.19), Vector3(0.0, 0.145, 0.015), surface).rotation.x = -0.12
	add_box(parent, prefix + "BootToeCap", Vector3(0.205, 0.105, 0.12), Vector3(0.0, 0.015, -0.285), surface)
	add_box(parent, prefix + "BootHeel", Vector3(0.18, 0.08, 0.09), Vector3(0.0, -0.005, 0.145), surface)
	if accent_surface != null:
		for buckle_index: int in 3:
			add_box(parent, "%sBootBuckle%d" % [prefix, buckle_index + 1], Vector3(0.215, 0.018, 0.025), Vector3(0.0, 0.075 + buckle_index * 0.055, -0.03 + buckle_index * 0.025), accent_surface)

static func build_ski(parent: Node3D, side: String, surface: Material, accent_surface: Material = null) -> void:
	var prefix := side.capitalize()
	var instance := MeshInstance3D.new()
	instance.name = prefix + "SkiMesh"
	instance.mesh = _ski_mesh(surface)
	parent.add_child(instance)
	if accent_surface != null:
		# A restrained inlaid top-sheet stripe reads at gameplay distance without
		# changing the collision-free, calibrated ski envelope.
		add_box(parent, prefix + "SkiAccent", Vector3(0.022, 0.004, 1.28), Vector3(0.0, 0.014, -0.08), accent_surface)

static func build_headwear(parent: Node3D, helmet_surface: Material, frame_surface: Material, lens_surface: Material) -> void:
	var center := Vector3(-0.01, 0.144, 0.027)
	var helmet := MeshInstance3D.new()
	helmet.name = "HelmetShell"
	helmet.mesh = _helmet_mesh(center, helmet_surface)
	helmet.material_override = helmet_surface
	parent.add_child(helmet)
	add_box(parent, "HelmetBrim", Vector3(0.2, 0.018, 0.06), Vector3(-0.01, 0.202, -0.055), helmet_surface)
	var strap := MeshInstance3D.new()
	strap.name = "GoggleStrap"
	strap.mesh = _band_mesh(center, deg_to_rad(-105.0), deg_to_rad(105.0), 16, [[0.125, 0.125, 0.125], [0.085, 0.125, 0.125]], frame_surface)
	strap.material_override = frame_surface
	parent.add_child(strap)
	var frame := MeshInstance3D.new()
	frame.name = "GoggleFrame"
	frame.mesh = _band_mesh(center, deg_to_rad(208.0), deg_to_rad(332.0), 14, [[0.195, 0.125, 0.125], [0.115, 0.125, 0.125]], frame_surface)
	frame.material_override = frame_surface
	parent.add_child(frame)
	var lens := MeshInstance3D.new()
	lens.name = "GoggleLens"
	lens.mesh = _band_mesh(center, deg_to_rad(219.0), deg_to_rad(321.0), 12, [[0.185, 0.14, 0.14], [0.125, 0.14, 0.14]], lens_surface)
	lens.material_override = lens_surface
	parent.add_child(lens)

static func build_pole(parent: Node3D, side: String, shaft_surface: Material, accent_surface: Material) -> void:
	var prefix := side.capitalize()
	add_cylinder(parent, prefix + "PoleMesh", POLE_SHAFT_RADIUS, POLE_SHAFT_LENGTH, Vector3(0.0, -0.52, 0.08), shaft_surface)
	add_cylinder(parent, prefix + "PoleGrip", 0.026, 0.18, Vector3(0.0, 0.105, 0.08), accent_surface)
	add_cylinder(parent, prefix + "PoleBasket", POLE_BASKET_RADIUS, POLE_BASKET_THICKNESS, Vector3(0.0, -1.02, 0.08), accent_surface)
	add_tapered_cylinder(parent, prefix + "PolePoint", 0.003, 0.012, 0.12, Vector3(0.0, -1.105, 0.08), shaft_surface)

static func _ski_mesh(surface: Material) -> ArrayMesh:
	# Cross-sections run tail-to-tip. The waist narrows underfoot, the shovel
	# widens, and the last two sections rise to form a real upturned tip.
	var sections := [
		Vector3(0.050, 0.000, 0.81),
		Vector3(0.055, 0.000, 0.65),
		Vector3(0.046, 0.000, 0.08),
		Vector3(0.044, 0.000, -0.18),
		Vector3(0.052, 0.000, -0.72),
		Vector3(0.0575, 0.006, -0.92),
		Vector3(0.050, 0.010, -1.01),
	]
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for section: Vector3 in sections:
		top.append(Vector3(-section.x, 0.0125 + section.y, section.z))
		top.append(Vector3(section.x, 0.0125 + section.y, section.z))
		bottom.append(Vector3(-section.x, -0.0125 + section.y, section.z))
		bottom.append(Vector3(section.x, -0.0125 + section.y, section.z))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section_index: int in range(sections.size() - 1):
		var a := section_index * 2
		var b := a + 2
		_add_quad(tool, top[a], top[a + 1], top[b + 1], top[b])
		_add_quad(tool, bottom[a + 1], bottom[a], bottom[b], bottom[b + 1])
		_add_quad(tool, top[a], top[b], bottom[b], bottom[a])
		_add_quad(tool, top[b + 1], top[a + 1], bottom[a + 1], bottom[b + 1])
	_add_quad(tool, top[0], bottom[0], bottom[1], top[1])
	var last := top.size() - 2
	_add_quad(tool, top[last + 1], bottom[last + 1], bottom[last], top[last])
	tool.generate_normals()
	tool.set_material(surface)
	return tool.commit()

static func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		tool.set_uv(Vector2(point.x, point.z))
		tool.add_vertex(point)

static func _add_quad_smooth(tool: SurfaceTool, quad: Array) -> void:
	for corner: Array in [quad[0], quad[1], quad[2], quad[3], quad[0], quad[2]]:
		tool.set_normal(corner[1])
		tool.add_vertex(corner[0])

static func _spherical_point(center: Vector3, radius: float, vertical_scale: float, phi: float, az: float) -> Vector3:
	return center + Vector3(radius * sin(phi) * cos(az), vertical_scale * radius * cos(phi), radius * sin(phi) * sin(az))

static func _spherical_normal(vertical_scale: float, phi: float, az: float) -> Vector3:
	return Vector3(sin(phi) * cos(az), vertical_scale * cos(phi), sin(phi) * sin(az)).normalized()

static func _helmet_edge_height(az: float) -> float:
	var base := 0.135 - 0.02 * maxf(0.0, sin(az))
	var zone_start := deg_to_rad(215.0)
	var zone_end := deg_to_rad(325.0)
	var blend := deg_to_rad(12.0)
	var span := zone_end - zone_start
	var value := fposmod(az - zone_start, TAU)
	var inside := 0.0
	if value <= span:
		inside = minf(value, span - value) / blend
	return lerpf(base, 0.205, smoothstep(0.0, 1.0, minf(inside, 1.0)))

static func _helmet_mesh(center: Vector3, surface: Material) -> ArrayMesh:
	var columns := 24
	var rings := 7
	var outer_radius := 0.165
	var inner_radius := 0.152
	var vertical_scale := 0.85
	var phi_min := deg_to_rad(6.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := center + Vector3(0.0, vertical_scale * outer_radius, 0.0)
	for column: int in columns:
		var az0 := -PI + TAU * float(column) / float(columns)
		var az1 := -PI + TAU * float(column + 1) / float(columns)
		var phi_e0 := acos(clampf((_helmet_edge_height(az0) - center.y) / (vertical_scale * outer_radius), -1.0, 1.0))
		var phi_e1 := acos(clampf((_helmet_edge_height(az1) - center.y) / (vertical_scale * outer_radius), -1.0, 1.0))
		_add_quad_smooth(tool, [
			[apex, Vector3.UP],
			[_spherical_point(center, outer_radius, vertical_scale, phi_min, az1), _spherical_normal(vertical_scale, phi_min, az1)],
			[_spherical_point(center, outer_radius, vertical_scale, phi_min, az0), _spherical_normal(vertical_scale, phi_min, az0)],
			[apex, Vector3.UP],
		])
		for ring: int in rings:
			var f0 := float(ring) / float(rings)
			var f1 := float(ring + 1) / float(rings)
			var phi00 := lerpf(phi_min, phi_e0, f0)
			var phi01 := lerpf(phi_min, phi_e0, f1)
			var phi10 := lerpf(phi_min, phi_e1, f0)
			var phi11 := lerpf(phi_min, phi_e1, f1)
			var o00 := _spherical_point(center, outer_radius, vertical_scale, phi00, az0)
			var o10 := _spherical_point(center, outer_radius, vertical_scale, phi10, az1)
			var o11 := _spherical_point(center, outer_radius, vertical_scale, phi11, az1)
			var o01 := _spherical_point(center, outer_radius, vertical_scale, phi01, az0)
			var n00 := _spherical_normal(vertical_scale, phi00, az0)
			var n10 := _spherical_normal(vertical_scale, phi10, az1)
			var n11 := _spherical_normal(vertical_scale, phi11, az1)
			var n01 := _spherical_normal(vertical_scale, phi01, az0)
			var i00 := _spherical_point(center, inner_radius, vertical_scale, phi00, az0)
			var i10 := _spherical_point(center, inner_radius, vertical_scale, phi10, az1)
			var i11 := _spherical_point(center, inner_radius, vertical_scale, phi11, az1)
			var i01 := _spherical_point(center, inner_radius, vertical_scale, phi01, az0)
			_add_quad_smooth(tool, [[o00, n00], [o10, n10], [o11, n11], [o01, n01]])
			_add_quad_smooth(tool, [[i01, -n01], [i11, -n11], [i10, -n10], [i00, -n00]])
			var rim := Vector3(cos(0.5 * (az0 + az1)), 0.0, sin(0.5 * (az0 + az1))).normalized()
			_add_quad_smooth(tool, [[o00, n00], [o10, n10], [i10, rim], [i00, rim]])
	tool.set_material(surface)
	return tool.commit()

static func _band_point(center: Vector3, az: float, y: float, radius_x: float, radius_z: float) -> Vector3:
	return Vector3(center.x + radius_x * cos(az), y, center.z + radius_z * sin(az))

static func _band_mesh(center: Vector3, azimuth_start: float, azimuth_end: float, segments: int, rows: Array, surface: Material) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in segments:
		var az0 := lerpf(azimuth_start, azimuth_end, float(segment) / float(segments))
		var az1 := lerpf(azimuth_start, azimuth_end, float(segment + 1) / float(segments))
		var n0 := Vector3(cos(az0), 0.0, sin(az0))
		var n1 := Vector3(cos(az1), 0.0, sin(az1))
		for row: int in rows.size() - 1:
			var upper0: Array = rows[row]
			var upper1: Array = rows[row + 1]
			_add_quad_smooth(tool, [
				[_band_point(center, az0, upper0[0], upper0[1], _band_depth(upper0)), n0],
				[_band_point(center, az0, upper1[0], upper0[1], _band_depth(upper0)), n0],
				[_band_point(center, az1, upper1[0], upper1[1], _band_depth(upper1)), n1],
				[_band_point(center, az1, upper0[0], upper1[1], _band_depth(upper1)), n1],
			])
	tool.set_material(surface)
	return tool.commit()

static func _band_depth(row: Array) -> float:
	return row[2] if row.size() > 2 else row[1]
