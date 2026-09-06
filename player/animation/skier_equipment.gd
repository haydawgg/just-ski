class_name SkierEquipment
extends RefCounted

const SKI_SIZE := Vector3(0.126, 0.025, 1.82)
const POLE_SHAFT_RADIUS := 0.016
const POLE_SHAFT_LENGTH := 1.15
const POLE_BASKET_RADIUS := 0.052
const POLE_BASKET_THICKNESS := 0.018

static func material(color: Color, roughness: float, metallic: float, specular: float = 0.5) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = roughness
	value.metallic = metallic
	value.metallic_specular = specular
	return value

static func region_surface(region: String, outfit: SkierOutfitProfile) -> StandardMaterial3D:
	# Single source of truth mapping an imported "Outfit_*" region to its
	# runtime surface. Unmarked regions get a neutral dark instead of silently
	# inheriting the jacket coral, so a future import change reads as an
	# unfinished part rather than miscoloring the torso.
	var color := outfit.jacket_color
	var roughness := outfit.cloth_roughness
	var metallic := 0.0
	var specular := outfit.cloth_specular
	var resolved := region
	match region:
		"Pants":
			color = outfit.pants_color
			roughness = outfit.pants_roughness
			specular = outfit.pants_specular
		"Skin":
			color = outfit.skin_color
			roughness = outfit.skin_roughness
			specular = outfit.skin_specular
		"Gloves":
			color = outfit.glove_color
			roughness = outfit.hardgoods_roughness
			specular = outfit.hardgoods_specular
		"BootUnderlay":
			color = outfit.boot_color
			roughness = outfit.hardgoods_roughness
			metallic = outfit.hardgoods_metallic
			specular = outfit.hardgoods_specular
		"Jacket":
			pass
		_:
			color = Color("#20262c")
			roughness = outfit.hardgoods_roughness
			specular = outfit.hardgoods_specular
			resolved = "Unmarked"
	var surface := material(color, roughness, metallic, specular)
	surface.resource_name = "Outfit_" + resolved
	return surface

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
	instance.name = node_name
	# Bake the ellipsoid dimensions into the vertex data instead of leaving a
	# non-uniform Node3D scale behind. Non-uniform attachment scales distort
	# skinned/attached detail transforms and violate the equipment scale contract.
	if local_scale.is_equal_approx(Vector3.ONE):
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		instance.mesh = sphere
	else:
		instance.mesh = _ellipsoid_mesh(radius, local_scale)
	instance.position = local_position
	instance.material_override = surface
	parent.add_child(instance)
	return instance

static func _ellipsoid_mesh(radius: float, dimensions: Vector3) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stacks := 12
	var slices := 20
	for stack: int in stacks:
		var phi0 := PI * float(stack) / float(stacks)
		var phi1 := PI * float(stack + 1) / float(stacks)
		for slice: int in slices:
			var theta0 := TAU * float(slice) / float(slices)
			var theta1 := TAU * float(slice + 1) / float(slices)
			var p00 := _ellipsoid_point(radius, dimensions, phi0, theta0)
			var p01 := _ellipsoid_point(radius, dimensions, phi0, theta1)
			var p10 := _ellipsoid_point(radius, dimensions, phi1, theta0)
			var p11 := _ellipsoid_point(radius, dimensions, phi1, theta1)
			var uv00 := Vector2(float(slice) / float(slices), float(stack) / float(stacks))
			var uv01 := Vector2(float(slice + 1) / float(slices), float(stack) / float(stacks))
			var uv10 := Vector2(float(slice) / float(slices), float(stack + 1) / float(stacks))
			var uv11 := Vector2(float(slice + 1) / float(slices), float(stack + 1) / float(stacks))
			_add_ellipsoid_triangle(tool, p00, p10, p11, uv00, uv10, uv11)
			_add_ellipsoid_triangle(tool, p00, p11, p01, uv00, uv11, uv01)
	tool.generate_normals()
	return tool.commit()

static func _ellipsoid_point(radius: float, dimensions: Vector3, phi: float, theta: float) -> Vector3:
	return Vector3(
		radius * dimensions.x * sin(phi) * cos(theta),
		radius * dimensions.y * cos(phi),
		radius * dimensions.z * sin(phi) * sin(theta)
	)

static func _add_ellipsoid_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	for entry: Array in [[a, uv_a], [b, uv_b], [c, uv_c]]:
		tool.set_uv(entry[1] as Vector2)
		tool.add_vertex(entry[0] as Vector3)

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
	# Heel block overlaps the shell by more than half its length so it reads
	# as part of the boot, not a spur floating behind it.
	add_box(parent, prefix + "BootHeel", Vector3(0.18, 0.08, 0.09), Vector3(0.0, -0.005, 0.10), surface)
	if accent_surface != null:
		for buckle_index: int in 3:
			# Buckles sit just proud of the cuff: readable hardware, no
			# floating side tabs.
			add_box(parent, "%sBootBuckle%d" % [prefix, buckle_index + 1], Vector3(0.188, 0.018, 0.025), Vector3(0.0, 0.075 + buckle_index * 0.055, -0.03 + buckle_index * 0.025), accent_surface)

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
	# Whole stack is centered on the skull axis (x=0). The earlier -0.01 bias
	# made every part lopsided close-up while staying internally consistent.
	var center := Vector3(0.0, 0.144, 0.027)
	var helmet := MeshInstance3D.new()
	helmet.name = "HelmetShell"
	helmet.mesh = _helmet_mesh(center, helmet_surface)
	helmet.material_override = helmet_surface
	parent.add_child(helmet)
	# Small rounded visor lip resting on the brow: it overlaps the shell rim
	# and goggle top without interpenetrating either volume.
	add_sphere(parent, "HelmetBrim", 0.085, Vector3(0.0, 0.202, -0.130), helmet_surface, Vector3(1.0, 0.09, 0.20))
	# Slim liner pads filling the head-to-shell gap on each side. A 28mm-thick
	# pad centered at +/-0.126 spans the skull surface (0.112) to just inside
	# the shell wall (0.141) instead of clipping 30mm into the head.
	add_sphere(parent, "HelmetEarPadLeft", 0.05, Vector3(-0.126, 0.10, 0.01), frame_surface, Vector3(0.28, 0.64, 0.8))
	add_sphere(parent, "HelmetEarPadRight", 0.05, Vector3(0.126, 0.10, 0.01), frame_surface, Vector3(0.28, 0.64, 0.8))
	var strap := MeshInstance3D.new()
	strap.name = "GoggleStrap"
	# Wrap the back of the head from one frame end around to the other
	# (332deg -> 208deg+360deg), centered on the back (90deg). The previous
	# -105deg..105deg arc was centered on the right side, overlapped the frame
	# in front, and left the left side bare, pulling the strap 4cm off-center.
	# Radius 0.17 rides just proud of the shell (outer ~0.165) so the band
	# reads on the outside instead of hiding inside the helmet wall. The band
	# is tapered: the top ring clears the shell while the bottom ring hugs the
	# skull (0.125) below the rim, so the sides dive under the shell edge
	# instead of floating off the head as a bar.
	strap.mesh = _band_mesh(center, deg_to_rad(332.0), deg_to_rad(568.0), 20, [[0.125, 0.17, 0.17], [0.085, 0.125, 0.125]], frame_surface)
	strap.material_override = frame_surface
	parent.add_child(strap)
	# Use shallow rounded lenses instead of the former two-row band mesh. The
	# ellipsoids keep a natural goggle contour at gameplay distance and leave a
	# visible dark frame around the cyan lens without a rectangular centre block.
	# Front faces sit ~1cm proud of the imported face surface: pulling the depth
	# in buries the band inside the head, pushing it out floats the goggles.
	var frame := add_sphere(parent, "GoggleFrame", 0.105, Vector3(0.0, 0.144, -0.118), frame_surface, Vector3(1.28, 0.56, 0.18))
	var lens := add_sphere(parent, "GoggleLens", 0.095, Vector3(0.0, 0.144, -0.137), lens_surface, Vector3(1.24, 0.50, 0.22))
	# Seat a small rounded bridge against the lens surface instead of the old
	# oversized box that obscured the middle of the skier's face.
	var bridge := add_capsule(parent, "GoggleNoseBridge", 0.012, 0.055, Vector3(0.0, 0.144, -0.157), frame_surface)
	bridge.rotation.z = PI * 0.5

static func build_face(parent: Node3D, surface: Material, mouth_pos: Vector3) -> void:
	# Stylized mouth line on the lower face. The goggles cover the eyes, so no
	# eye geometry is authored (it would hide behind the opaque lens). Position
	# is per-rig calibrated like the jacket details: the primitive jaw and the
	# imported base-mesh chin sit at different heights/depths under the head
	# mount. The line itself stays flat (r=0.006) so it reads as color, not a
	# protruding snout.
	var mouth := add_capsule(parent, "Mouth", 0.006, 0.04, mouth_pos, surface)
	mouth.rotation.z = PI * 0.5

static func build_jacket_details(spine_parent: Node3D, chest_parent: Node3D, accent_surface: Material, dark_surface: Material, trim_surface: Material, back_z: float, front_z: float, pocket_offset: Vector3) -> void:
	# The authored body supplies the jacket volume. Keep these accents small enough
	# to read as garment construction at gameplay distance rather than as floating
	# panels or a second blocky torso.
	# Depths are per-rig calibrated: the primitive ellipsoid torso and the
	# imported base mesh sit at different depths under their mounts, so each
	# caller passes seating measured against its own torso wall.
	add_box(spine_parent, "JacketBackStripe", Vector3(0.035, 0.34, 0.012), Vector3(0.0, 0.28, back_z), accent_surface)
	# Front-facing details follow the chest, not the lower spine, so a carve,
	# grab, or flip cannot leave the zipper/pocket floating off the jacket shell.
	add_box(chest_parent, "JacketFrontZip", Vector3(0.012, 0.30, 0.008), Vector3(0.0, -0.08, front_z), dark_surface)
	add_box(chest_parent, "JacketChestPocket", Vector3(0.095, 0.052, 0.008), pocket_offset, trim_surface)

static func build_sleeves(shoulder_parent: Node3D, elbow_parent: Node3D, side: String, jacket_surface: Material, cuff_surface: Material) -> void:
	# The source arm silhouette is intentionally light on geometry. These two
	# calibrated soft volumes add sleeve bulk and a readable cuff while remaining
	# independently attached to the existing shoulder/elbow bones.
	var prefix := side.capitalize()
	add_capsule(shoulder_parent, prefix + "UpperSleeve", 0.10, 0.46, Vector3(0.0, -0.23, 0.0), jacket_surface)
	add_capsule(elbow_parent, prefix + "ForearmSleeve", 0.082, 0.40, Vector3(0.0, -0.18, 0.0), jacket_surface)
	# A rounded cuff avoids the square wrist blocks that read as detached gloves
	# in front-facing views while keeping the existing calibrated wrist position.
	# The cuff flares wider than the forearm sleeve so it stays visible where
	# the glove meets the wrist instead of burying inside it. Height admits the
	# radius: CapsuleMesh clamps radius to height/2, so a stubby tall cuff
	# would silently shrink back below the sleeve. The cuff sits mid-forearm,
	# clear of the glove: wrist coverage comes from the glove itself, and a
	# cuff concentric with the hand swallows it whole.
	add_capsule(elbow_parent, prefix + "SleeveCuff", 0.085, 0.18, Vector3(0.0, -0.30, 0.0), cuff_surface)

static func build_pole(parent: Node3D, side: String, shaft_surface: Material, accent_surface: Material) -> void:
	var prefix := side.capitalize()
	# The pole pivot is the hand origin in both rig adapters. Keep the grip
	# centered on that origin and run the shaft straight down its local -Y axis;
	# the previous +Z/raised grip offset made the pole appear detached or inverted
	# in front-facing gameplay captures.
	add_cylinder(parent, prefix + "PoleMesh", POLE_SHAFT_RADIUS, POLE_SHAFT_LENGTH, Vector3(0.0, -0.625, 0.0), shaft_surface)
	add_cylinder(parent, prefix + "PoleGrip", 0.026, 0.18, Vector3(0.0, 0.0, 0.0), accent_surface)
	add_cylinder(parent, prefix + "PoleBasket", POLE_BASKET_RADIUS, POLE_BASKET_THICKNESS, Vector3(0.0, -1.125, 0.0), accent_surface)
	add_tapered_cylinder(parent, prefix + "PolePoint", 0.012, 0.003, 0.12, Vector3(0.0, -1.21, 0.0), shaft_surface)

static func _ski_mesh(surface: Material) -> ArrayMesh:
	# Cross-sections run tail-to-tip. The waist narrows underfoot, the shovel
	# widens, and the last two sections rise to form a real upturned tip.
	var sections := [
		Vector3(0.055, 0.000, 0.81),
		Vector3(0.061, 0.000, 0.65),
		Vector3(0.051, 0.000, 0.08),
		Vector3(0.049, 0.000, -0.18),
		Vector3(0.057, 0.000, -0.72),
		Vector3(0.063, 0.006, -0.92),
		Vector3(0.055, 0.010, -1.01),
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
	# True ellipsoid normal: the y component scales inversely. The old version
	# multiplied by vertical_scale, tilting dome lighting ~38% off-axis.
	return Vector3(sin(phi) * cos(az), cos(phi) / vertical_scale, sin(phi) * sin(az)).normalized()

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
	# Front rim (0.185) tucks just under the goggle bands (frame top 0.203,
	# lens top 0.192) so the brow overlaps with no forehead skin strip.
	return lerpf(base, 0.185, smoothstep(0.0, 1.0, minf(inside, 1.0)))

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
		# Close the true bottom edge (f1 == 1): without this wall the 13mm rim
		# slot stays open around the full circumference and leaks light.
		var phi_b0 := lerpf(phi_min, phi_e0, 1.0)
		var phi_b1 := lerpf(phi_min, phi_e1, 1.0)
		var ob0 := _spherical_point(center, outer_radius, vertical_scale, phi_b0, az0)
		var ob1 := _spherical_point(center, outer_radius, vertical_scale, phi_b1, az1)
		var ib0 := _spherical_point(center, inner_radius, vertical_scale, phi_b0, az0)
		var ib1 := _spherical_point(center, inner_radius, vertical_scale, phi_b1, az1)
		var nb0 := _spherical_normal(vertical_scale, phi_b0, az0)
		var nb1 := _spherical_normal(vertical_scale, phi_b1, az1)
		var rim_b := Vector3(cos(0.5 * (az0 + az1)), 0.0, sin(0.5 * (az0 + az1))).normalized()
		_add_quad_smooth(tool, [[ob0, nb0], [ob1, nb1], [ib1, rim_b], [ib0, rim_b]])
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
			# Each ring keeps its own radii; mixing rows twists the band when
			# a tapered (multi-radius) strap is authored.
			_add_quad_smooth(tool, [
				[_band_point(center, az0, upper0[0], upper0[1], _band_depth(upper0)), n0],
				[_band_point(center, az0, upper1[0], upper1[1], _band_depth(upper1)), n0],
				[_band_point(center, az1, upper1[0], upper1[1], _band_depth(upper1)), n1],
				[_band_point(center, az1, upper0[0], upper0[1], _band_depth(upper0)), n1],
			])
	tool.set_material(surface)
	return tool.commit()

static func _band_depth(row: Array) -> float:
	return row[2] if row.size() > 2 else row[1]
